unit DRagLint.FieldRepo.SchemaSeed;

{ drag-lint 1.52 -- lane TTS: seed / refresh a field repository from the Firebird schema.

  Port of TableTools FieldsInfo.Model.pas UpdateFieldsInfo, CleanOrphanFields and
  UpdateDatasetsInfo (design 2026-11-16-tabletools-into-dl-design.md sections 2.1 and 9a).
  The Firebird system tables arrive as four datasets (TSchemaSources), so the logic runs
  on TFDMemTable in the tests and on live queries (OpenSchemaSources) in the CLI.
  Firebird is only READ. }

interface

uses
  System.SysUtils,
  Data.DB,
  FireDAC.Comp.Client;

type
  /// <summary>Seed = first fill of an EMPTY repository (repo seed-fb); refresh = the old
  /// TableTools "Update Fields Info" on a filled one (repo refresh-schema).</summary>
  TSchemaSeedMode = (ssmSeed, ssmRefresh);

  /// <summary>The Firebird schema facts the seed reads. The caller owns the datasets.</summary>
  /// <remarks>Required columns (names case-insensitive; trailing blanks are trimmed):
  /// Fields: TABLE_NAME, FIELD_NAME, DEFAULT_SOURCE, FIELD_LENGTH, FIELD_TYPE,
  /// FIELD_SUB_TYPE, NULL_FLAG, CHARACTER_LEN, FIELD_SCALE -- one row per column of a
  /// user table (no views, no system tables), ordered by table then field position
  /// (the TableTools qryFields). RelationFields: RELATION_NAME, FIELD_NAME of EVERY
  /// relation (the orphan check). PrimaryKeys: TABLE_NAME, FIELD_NAME, FIELD_POSITION, one
  /// row per primary-key segment. Generators: GENERATOR_NAME. A NULL integer reads as 0.</remarks>
  TSchemaSources = record
    Fields: TDataSet;
    RelationFields: TDataSet;
    PrimaryKeys: TDataSet;
    Generators: TDataSet;
  end;

  /// <summary>What one seed / refresh run did (or, in a dry run, would do).</summary>
  /// <remarks>Diff lines: "+ FIELD T.F", "~ FIELD T.F COL: old -> new",
  /// "! FIELD T.F ISCALCULATED (column vanished)", "+ DATASET T DS_ID=n",
  /// "~ DATASET T DS_ID=n". Warnings: a (type, sub_type) without a dictionary entry,
  /// a value cut to its column length, a dataset skipped for an over-long KEY_FIELD.</remarks>
  TSchemaSeedResult = record
    Added: Integer;
    Changed: Integer;
    Orphaned: Integer;
    DatasetsInserted: Integer;
    DatasetsUpdated: Integer;
    DatasetsSkipped: Integer;
    Diff: TArray<string>;
    Warnings: TArray<string>;
  end;

/// <summary>Seeds or refreshes DL_FIELDS_INFO and DL_DATASETS_INFO from the schema.</summary>
/// <param name="pTarget">An open, writable repository connection (OpenRepository).
/// Must not be inside a transaction: the run owns one.</param>
/// <param name="pSources">The schema datasets; see TSchemaSources.</param>
/// <param name="pMode">ssmSeed requires an empty repository; ssmRefresh takes any.</param>
/// <param name="pDryRun">True = compute counts and diff, then roll back: nothing written.</param>
/// <param name="pStampUtc">UTC time written to DESCRIPTION of generated datasets and to
/// DL_META schema_refreshed_at_utc.</param>
/// <returns>Counts, diff and warnings.</returns>
/// <exception cref="ERepoError">ssmSeed on a non-empty repository, or a source dataset
/// is nil or lacks a required column (the message names it). Any other error rolls the
/// whole run back and is re-raised.</exception>
/// <remarks>Per column of Fields (UpdateFieldsInfo): a new row gets the TableTools
/// new-row values (DISPLAY_LABEL '', VISIBLE False, ALIGNMENT -2, ...); every row gets the
/// schema-derived columns FIELD_AS_TYPE, VAR_TYPE (ENUMTYPE when CUSTOM_TYPE or ISENUM),
/// FIELD_SIZE, STRING_SIZE, NULL_FLAG, FIELD_KIND = 1, FIELD_TYPE, FIELD_SUBTYPE,
/// FIELD_LENGTH, FIELD_SCALE, PRIMARY_KEY; DEFAULTVAL only while it is NULL;
/// SEQUENCE_NAME = GEN_T_F and TRIGGERED = True only for a single-segment BIGINT key whose
/// generator exists (otherwise both keep their value). Hand-maintained columns are never
/// written for an existing row. Then CleanOrphanFields: a non-calculated, non-lookup row
/// of a non RDB$/MON$/SEC$ table whose column is absent from RelationFields becomes
/// ISCALCULATED (never deleted). Then UpdateDatasetsInfo: one DL_DATASETS_INFO row per
/// table of DL_FIELDS_INFO (not RDB$/MON$/SEC$/FIB$) that has a primary key; the SQL lists
/// the non-calculated, non-lookup fields in FIELD_NAME order; an existing row (matched by
/// UPDATE_TABLE_NAME) keeps its DS_ID, UPDATE_ONLY_MODIFIED_FIELDS and CONDITIONS and is
/// rewritten only when its generated text changed; a new row gets MAX(DS_ID) + 1.</remarks>
function RunSchemaSeed(pTarget: TFDConnection; const pSources: TSchemaSources;  // dl:ok unused-public-symbol@d7b0 -- consumed by lane TTE (CLI.Repo) and SchemaSeedTests
  pMode: TSchemaSeedMode; pDryRun: Boolean; pStampUtc: TDateTime): TSchemaSeedResult;

/// <summary>Opens the four schema queries on a live Firebird connection.</summary>
/// <param name="pFb">An open Firebird connection; only SELECTs on RDB$ tables run.</param>
/// <returns>Open datasets owned by the caller; release them with FreeSchemaSources.</returns>
/// <exception cref="EFDDBEngineException">Raised by FireDAC when a query fails; the
/// datasets opened so far are freed first.</exception>
function OpenSchemaSources(pFb: TFDConnection): TSchemaSources;  // dl:ok unused-public-symbol@0b64 -- consumed by lane TTE (CLI.Repo)

/// <summary>Frees the datasets of pSources and sets them to nil.</summary>
/// <param name="pSources">Sources from OpenSchemaSources; nil members are skipped.</param>
procedure FreeSchemaSources(var pSources: TSchemaSources);  // dl:ok unused-public-symbol@9833 -- consumed by lane TTE (CLI.Repo)

implementation

uses
  System.Variants,
  System.StrUtils,
  System.DateUtils,
  System.Generics.Defaults,
  System.Generics.Collections,
  FireDAC.Stan.Param,
  FireDAC.DApt,
  DRagLint.FieldRepo.Schema,
  DRagLint.FieldRepo.FbTypes;

const
  FIELDS_TABLE = 'DL_FIELDS_INFO';
  DATASETS_TABLE = 'DL_DATASETS_INFO';
  META_REFRESHED = 'schema_refreshed_at_utc';
  { DL_DATASETS_INFO.KEY_FIELD is VARCHAR(68): a longer composite key is skipped (TableTools). }
  MAX_KEY_FIELD_LEN = 68;
  { FIELD_KIND of a real table column; ALIGNMENT of a new row (TableTools new-row values). }
  FIELD_KIND_COLUMN = 1;
  ALIGNMENT_NEW_ROW = -2;
  FB_TYPE_INT64 = 16;
  DEFAULT_PREFIX = 'DEFAULT ';
  NULL_TEXT = 'NULL';

  { Schema-derived columns of DL_FIELDS_INFO (design 2.1), in read / write order. }
  SCHEMA_COLS: array[0..13] of string = ('FIELD_AS_TYPE', 'VAR_TYPE', 'DEFAULTVAL',
    'FIELD_SIZE', 'STRING_SIZE', 'NULL_FLAG', 'FIELD_KIND', 'FIELD_TYPE', 'FIELD_SUBTYPE',
    'FIELD_LENGTH', 'FIELD_SCALE', 'PRIMARY_KEY', 'SEQUENCE_NAME', 'TRIGGERED');
  COL_AS_TYPE = 0;
  COL_VAR_TYPE = 1;
  COL_DEFAULTVAL = 2;
  COL_FIELD_SIZE = 3;
  COL_STRING_SIZE = 4;
  COL_NULL_FLAG = 5;
  COL_FIELD_KIND = 6;
  COL_FIELD_TYPE = 7;
  COL_FIELD_SUBTYPE = 8;
  COL_FIELD_LENGTH = 9;
  COL_FIELD_SCALE = 10;
  COL_PRIMARY_KEY = 11;
  COL_SEQUENCE = 12;
  COL_TRIGGERED = 13;

  { Generated columns of DL_DATASETS_INFO compared on refresh (DESCRIPTION is not). }
  DS_COLS: array[0..6] of string = ('SELECT_SQL', 'INSERT_SQL', 'UPDATE_SQL', 'DELETE_SQL',
    'REFRESH_SQL', 'NAME_GENERATOR', 'KEY_FIELD');
  GEN_SELECT = 0;
  GEN_INSERT = 1;
  GEN_UPDATE = 2;
  GEN_DELETE = 3;
  GEN_REFRESH = 4;
  GEN_NAME_GENERATOR = 5;
  GEN_KEY_FIELD = 6;

  SQL_FIELDS =
    'SELECT TRIM(F.RDB$RELATION_NAME) AS TABLE_NAME, TRIM(F.RDB$FIELD_NAME) AS FIELD_NAME, ' +
    'L.RDB$DEFAULT_SOURCE AS DEFAULT_SOURCE, L.RDB$FIELD_LENGTH AS FIELD_LENGTH, ' +
    'L.RDB$FIELD_TYPE AS FIELD_TYPE, L.RDB$FIELD_SUB_TYPE AS FIELD_SUB_TYPE, ' +
    'L.RDB$NULL_FLAG AS NULL_FLAG, L.RDB$CHARACTER_LENGTH AS CHARACTER_LEN, ' +
    'L.RDB$FIELD_SCALE AS FIELD_SCALE ' +
    'FROM RDB$RELATION_FIELDS F ' +
    'INNER JOIN RDB$RELATIONS R ON F.RDB$RELATION_NAME = R.RDB$RELATION_NAME ' +
    'AND R.RDB$VIEW_BLR IS NULL AND (R.RDB$SYSTEM_FLAG IS NULL OR R.RDB$SYSTEM_FLAG = 0) ' +
    'INNER JOIN RDB$FIELDS L ON L.RDB$FIELD_NAME = F.RDB$FIELD_SOURCE ' +
    'ORDER BY 1, F.RDB$FIELD_POSITION';
  SQL_RELATION_FIELDS =
    'SELECT TRIM(RDB$RELATION_NAME) AS RELATION_NAME, TRIM(RDB$FIELD_NAME) AS FIELD_NAME ' +
    'FROM RDB$RELATION_FIELDS';
  SQL_PRIMARY_KEYS =
    'SELECT TRIM(RC.RDB$RELATION_NAME) AS TABLE_NAME, TRIM(SG.RDB$FIELD_NAME) AS FIELD_NAME, ' +
    'SG.RDB$FIELD_POSITION AS FIELD_POSITION ' +
    'FROM RDB$RELATION_CONSTRAINTS RC ' +
    'INNER JOIN RDB$INDEX_SEGMENTS SG ON RC.RDB$INDEX_NAME = SG.RDB$INDEX_NAME ' +
    'WHERE RC.RDB$CONSTRAINT_TYPE = ''PRIMARY KEY'' ORDER BY 1, 3';
  SQL_GENERATORS = 'SELECT TRIM(RDB$GENERATOR_NAME) AS GENERATOR_NAME FROM RDB$GENERATORS';

  { System-table prefixes TableTools never touches; FIB$ is also skipped for datasets. }
  SQL_NOT_SYSTEM = 'substr("TABLE_NAME", 1, 4) NOT IN (''RDB$'', ''MON$'', ''SEC$'')';
  SQL_NOT_SYSTEM_OR_FIB = 'substr("TABLE_NAME", 1, 4) NOT IN (''RDB$'', ''MON$'', ''SEC$'', ''FIB$'')';

type
  { One seed / refresh run: the source maps plus the result being built. }
  TSeedRun = class  // dl:ok high-response@a9ca -- one object per run: the three passes share one transaction's maps and result
  strict private
    FConn: TFDConnection;
    FSrc: TSchemaSources;
    FStampText: string;
    FPk: TObjectDictionary<string, TList<string>>;
    FGenerators: TDictionary<string, Boolean>;
    FRelFields: TDictionary<string, Boolean>;
    FDiff: TList<string>;
    FWarnings: TList<string>;
    FStringMax: array[0..13] of Integer;
    procedure LoadMaps;
    procedure LoadColumnLimits;
    function PkOf(const pTable: string): TArray<string>;
    function ReadOld(const pTable, pField: string; out pOld: TArray<Variant>;
      out pEnumVar: Boolean; out pEnumType: string): Boolean;
    function Fit(const pValue, pTable, pField: string; pCol: Integer): string;
    procedure WriteField(pIsNew: Boolean; const pTable, pField: string; const pValues: TArray<Variant>);
    procedure UpdateFields(var pRes: TSchemaSeedResult);
    procedure CleanOrphans(var pRes: TSchemaSeedResult);
    procedure UpdateDatasets(var pRes: TSchemaSeedResult);
  public
    constructor Create(pConn: TFDConnection; const pSources: TSchemaSources; pStampUtc: TDateTime);
    destructor Destroy; override;
    function Execute: TSchemaSeedResult;
  end;

function ValText(const pValue: Variant): string;
begin
  Result := if VarIsNull(pValue) or VarIsEmpty(pValue) then NULL_TEXT else VarToStr(pValue);
end;

function SameVal(const pA, pB: Variant): Boolean;
var
  NullA, NullB: Boolean;
begin
  NullA := VarIsNull(pA) or VarIsEmpty(pA);
  NullB := VarIsNull(pB) or VarIsEmpty(pB);
  if NullA or NullB then
    Exit(NullA = NullB);
  Result := VarToStr(pA) = VarToStr(pB);
end;

function IntOf(pData: TDataSet; const pName: string): Integer;
begin
  Result := pData.FieldByName(pName).AsInteger;
end;

function NameOf(pData: TDataSet; const pName: string): string;
begin
  Result := Trim(pData.FieldByName(pName).AsString);
end;

{ TableTools GetDefaultVal: drops everything up to and including "DEFAULT ". }
function DefaultValOf(const pSource: string): string;
begin
  Result := pSource;
  if Result.Contains(DEFAULT_PREFIX) then
    Result := Copy(Result, Length(DEFAULT_PREFIX) + 1);
end;

function JoinNames(const pNames: TArray<string>; const pSep, pPrefix, pSuffixFmt: string): string;
var
  i: Integer;
  Part: string;
begin
  Result := '';
  for i := 0 to High(pNames) do
  begin
    Part := if pSuffixFmt = '' then pPrefix + pNames[i] else Format(pSuffixFmt, [pNames[i], pNames[i]]);
    Result := if i = 0 then Part else Result + pSep + Part;
  end;
end;

procedure CheckSource(pData: TDataSet; const pRole: string; const pColumns: array of string);
var
  Missing: string;
  Col: string;
begin
  if pData = nil then
    raise ERepoError.CreateFmt('Schema source %s is missing', [pRole]);
  Missing := '';
  for Col in pColumns do
    if pData.FindField(Col) = nil then
      Missing := if Missing = '' then Col else Missing + ', ' + Col;
  if Missing <> '' then
    raise ERepoError.CreateFmt('Schema source %s lacks column(s): %s', [pRole, Missing]);
end;

{ TSeedRun }

constructor TSeedRun.Create(pConn: TFDConnection; const pSources: TSchemaSources; pStampUtc: TDateTime);
begin
  inherited Create;
  FConn := pConn;
  FSrc := pSources;
  FStampText := DateToISO8601(pStampUtc, True);
  FPk := TObjectDictionary<string, TList<string>>.Create([doOwnsValues]);
  FGenerators := TDictionary<string, Boolean>.Create;
  FRelFields := TDictionary<string, Boolean>.Create;
  FDiff := TList<string>.Create;
  FWarnings := TList<string>.Create;
end;

destructor TSeedRun.Destroy;
begin
  FWarnings.Free;
  FDiff.Free;
  FRelFields.Free;
  FGenerators.Free;
  FPk.Free;
  inherited;
end;

procedure TSeedRun.LoadColumnLimits;
var
  Tab: TRepoTable;
  Col: TRepoColumn;
  i: Integer;
begin
  if not FindRepoTable(FIELDS_TABLE, Tab) then
    raise ERepoError.Create('Repository contract lacks ' + FIELDS_TABLE);
  for i := 0 to High(SCHEMA_COLS) do
  begin
    if not Tab.FindColumn(SCHEMA_COLS[i], Col) then
      raise ERepoError.CreateFmt('Repository contract lacks %s.%s', [FIELDS_TABLE, SCHEMA_COLS[i]]);
    FStringMax[i] := if Col.Kind = rckString then Col.MaxLen else 0;
  end;
end;

procedure TSeedRun.LoadMaps;
var
  PkRows: TList<TPair<Integer, string>>;
  Table: string;
  Pair: TPair<Integer, string>;
  Keys: TList<string>;
begin
  CheckSource(FSrc.Fields, 'Fields', ['TABLE_NAME', 'FIELD_NAME', 'DEFAULT_SOURCE', 'FIELD_LENGTH',
    'FIELD_TYPE', 'FIELD_SUB_TYPE', 'NULL_FLAG', 'CHARACTER_LEN', 'FIELD_SCALE']);
  CheckSource(FSrc.RelationFields, 'RelationFields', ['RELATION_NAME', 'FIELD_NAME']);
  CheckSource(FSrc.PrimaryKeys, 'PrimaryKeys', ['TABLE_NAME', 'FIELD_NAME', 'FIELD_POSITION']);
  CheckSource(FSrc.Generators, 'Generators', ['GENERATOR_NAME']);

  FSrc.Generators.First;
  while not FSrc.Generators.Eof do
  begin
    FGenerators.AddOrSetValue(NameOf(FSrc.Generators, 'GENERATOR_NAME'), True);
    FSrc.Generators.Next;
  end;

  FSrc.RelationFields.First;
  while not FSrc.RelationFields.Eof do
  begin
    FRelFields.AddOrSetValue(NameOf(FSrc.RelationFields, 'RELATION_NAME') + '.' +
      NameOf(FSrc.RelationFields, 'FIELD_NAME'), True);
    FSrc.RelationFields.Next;
  end;

  { primary-key segments per table, in FIELD_POSITION order }
  PkRows := TList<TPair<Integer, string>>.Create;
  try
    FSrc.PrimaryKeys.First;
    while not FSrc.PrimaryKeys.Eof do
    begin
      PkRows.Add(TPair<Integer, string>.Create(IntOf(FSrc.PrimaryKeys, 'FIELD_POSITION'),
        NameOf(FSrc.PrimaryKeys, 'TABLE_NAME') + #9 + NameOf(FSrc.PrimaryKeys, 'FIELD_NAME')));
      FSrc.PrimaryKeys.Next;
    end;
    PkRows.Sort(TComparer<TPair<Integer, string>>.Construct(
      function(const pLeft, pRight: TPair<Integer, string>): Integer
      begin
        Result := pLeft.Key - pRight.Key;
      end));
    for Pair in PkRows do
    begin
      Table := Pair.Value.Split([#9])[0];
      if not FPk.TryGetValue(Table, Keys) then
      begin
        Keys := TList<string>.Create;
        FPk.Add(Table, Keys);
      end;
      Keys.Add(Pair.Value.Split([#9])[1]);
    end;
  finally
    PkRows.Free;
  end;
end;

function TSeedRun.PkOf(const pTable: string): TArray<string>;
var
  Keys: TList<string>;
begin
  Result := if FPk.TryGetValue(pTable, Keys) then Keys.ToArray else nil;
end;

function TSeedRun.ReadOld(const pTable, pField: string; out pOld: TArray<Variant>;
  out pEnumVar: Boolean; out pEnumType: string): Boolean;
var
  Q: TFDQuery;
  Cols: string;
  i: Integer;
begin
  Cols := '';
  for i := 0 to High(SCHEMA_COLS) do
    Cols := Cols + QuoteRepoIdent(SCHEMA_COLS[i]) + ', ';
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := FConn;
    Q.Open(
      'SELECT ' + Cols + 'CAST("CUSTOM_TYPE" AS INTEGER), CAST("ISENUM" AS INTEGER), "ENUMTYPE" ' +  // dl:ok path-traversal@c160 -- SQL text, not a path: identifiers go through QuoteRepoIdent
      'FROM ' + QuoteRepoIdent(FIELDS_TABLE) + ' WHERE "TABLE_NAME" = :T AND "FIELD_NAME" = :F',
      [pTable, pField]);
    SetLength(pOld, Length(SCHEMA_COLS));
    Result := not Q.Eof;
    if not Result then
    begin
      { a new row: what TableTools' Append leaves in the schema columns }
      for i := 0 to High(pOld) do
        pOld[i] := Null;
      pOld[COL_PRIMARY_KEY] := 0;
      pOld[COL_TRIGGERED] := 0;
      pEnumVar := False;
      pEnumType := '';
      Exit;
    end;
    for i := 0 to High(SCHEMA_COLS) do
      pOld[i] := Q.Fields[i].Value;
    pOld[COL_PRIMARY_KEY] := Ord(Q.Fields[COL_PRIMARY_KEY].AsBoolean);
    pOld[COL_TRIGGERED] := Ord(Q.Fields[COL_TRIGGERED].AsBoolean);
    pEnumVar := (Q.Fields[Length(SCHEMA_COLS)].AsInteger <> 0) or (Q.Fields[Length(SCHEMA_COLS) + 1].AsInteger <> 0);
    pEnumType := Q.Fields[Length(SCHEMA_COLS) + 2].AsString;
  finally
    Q.Free;
  end;
end;

function TSeedRun.Fit(const pValue, pTable, pField: string; pCol: Integer): string;
begin
  Result := pValue;
  if (FStringMax[pCol] > 0) and (Length(Result) > FStringMax[pCol]) then
  begin
    FWarnings.Add(Format('%s.%s %s cut to %d chars: %s', [pTable, pField, SCHEMA_COLS[pCol],
      FStringMax[pCol], pValue]));
    Result := Copy(Result, 1, FStringMax[pCol]);
  end;
end;

procedure TSeedRun.WriteField(pIsNew: Boolean; const pTable, pField: string; const pValues: TArray<Variant>);
var
  Sql, Names, Marks: string;
  Params: TArray<Variant>;
  Types: TArray<TFieldType>;
  i: Integer;
begin
  SetLength(Params, Length(SCHEMA_COLS) + 2);
  SetLength(Types, Length(SCHEMA_COLS) + 2);
  for i := 0 to High(SCHEMA_COLS) do
  begin
    Params[i] := pValues[i];
    Types[i] := if FStringMax[i] > 0 then ftWideString else ftInteger;
  end;
  Params[Length(SCHEMA_COLS)] := pTable;
  Params[Length(SCHEMA_COLS) + 1] := pField;
  Types[Length(SCHEMA_COLS)] := ftWideString;
  Types[Length(SCHEMA_COLS) + 1] := ftWideString;
  Names := '';
  Marks := '';
  for i := 0 to High(SCHEMA_COLS) do
  begin
    if pIsNew then
    begin
      Names := Names + QuoteRepoIdent(SCHEMA_COLS[i]) + ', ';
      Marks := Marks + ':P' + IntToStr(i) + ', ';
    end
    else
      Names := Names + (if i = 0 then '' else ', ') + QuoteRepoIdent(SCHEMA_COLS[i]) + ' = :P' + IntToStr(i);
  end;
  { a new row gets the TableTools new-row values for the hand-maintained columns; the rest
    take the DDL defaults }
  Sql := if pIsNew then
    'INSERT INTO ' + QuoteRepoIdent(FIELDS_TABLE) + ' (' + Names +
      '"TABLE_NAME", "FIELD_NAME", "DISPLAY_LABEL", "VISIBLE", "DISPLAY_FORMAT", "EDIT_FORMAT", ' +
      '"DISPLAY_WIDTH", "BG_COLOR", "FG_COLOR", "ALIGNMENT", "CUSTOM_TYPE", "ISCALCULATED", ' +
      '"ISLOOKUP", "DESTTABLE", "SOURCEKEY", "DESTKEY", "DESTVALUE") VALUES (' + Marks +
      ':T, :F, '''', 0, '''', '''', 0, 0, 0, ' + IntToStr(ALIGNMENT_NEW_ROW) +
      ', 0, 0, 0, '''', '''', '''', '''')'
  else
    'UPDATE ' + QuoteRepoIdent(FIELDS_TABLE) + ' SET ' + Names +
      ' WHERE "TABLE_NAME" = :T AND "FIELD_NAME" = :F';
  FConn.ExecSQL(Sql, Params, Types);
end;

procedure TSeedRun.UpdateFields(var pRes: TSchemaSeedResult);
var
  Src: TDataSet;
  DefaultField: TField;
  Table, Field, Accessor, VarType, Seq, EnumType: string;
  FbType, FbSub, FbLen: Integer;
  OldVals, NewVals: TArray<Variant>;
  Exists, EnumVar, InPk, Differs: Boolean;
  Pk: TArray<string>;
  Key: string;
  i: Integer;
begin
  Src := FSrc.Fields;
  DefaultField := Src.FieldByName('DEFAULT_SOURCE');
  Src.First;
  while not Src.Eof do
  begin
    Table := NameOf(Src, 'TABLE_NAME').ToUpper;
    Field := NameOf(Src, 'FIELD_NAME').ToUpper;
    FbType := IntOf(Src, 'FIELD_TYPE');
    FbSub := IntOf(Src, 'FIELD_SUB_TYPE');
    FbLen := IntOf(Src, 'FIELD_LENGTH');
    Exists := ReadOld(Table, Field, OldVals, EnumVar, EnumType);
    NewVals := Copy(OldVals);

    if TryFbFieldAccessor(FbType, FbSub, Accessor) then
      NewVals[COL_AS_TYPE] := Accessor
    else
      FWarnings.Add(Format('%s.%s type=%d sub_type=%d: no entry in the type dictionary, ' +
        'FIELD_AS_TYPE / VAR_TYPE left as they were', [Table, Field, FbType, FbSub]));
    if EnumVar then
      NewVals[COL_VAR_TYPE] := EnumType
    else if TryFbFieldVarType(FbType, FbSub, FbLen, VarType) then
      NewVals[COL_VAR_TYPE] := VarType;
    if VarIsNull(NewVals[COL_DEFAULTVAL]) then
      NewVals[COL_DEFAULTVAL] := Fit(DefaultValOf(DefaultField.AsString),
        Table, Field, COL_DEFAULTVAL);
    NewVals[COL_FIELD_SIZE] := FbLen;
    NewVals[COL_STRING_SIZE] := IntOf(Src, 'CHARACTER_LEN');
    NewVals[COL_NULL_FLAG] := IntOf(Src, 'NULL_FLAG');
    NewVals[COL_FIELD_KIND] := FIELD_KIND_COLUMN;
    NewVals[COL_FIELD_TYPE] := FbType;
    NewVals[COL_FIELD_SUBTYPE] := FbSub;
    NewVals[COL_FIELD_LENGTH] := FbLen;
    NewVals[COL_FIELD_SCALE] := IntOf(Src, 'FIELD_SCALE');

    Pk := PkOf(Table);
    InPk := False;
    for Key in Pk do
      if Key = Field then
        InPk := True;
    NewVals[COL_PRIMARY_KEY] := Ord(InPk);
    { SEQUENCE_NAME only for a single-segment BIGINT key whose generator exists }
    if InPk and (Length(Pk) = 1) and (FbType = FB_TYPE_INT64) then
    begin
      Seq := 'GEN_' + Table + '_' + Field;
      if FGenerators.ContainsKey(Seq) then
        if Length(Seq) > FStringMax[COL_SEQUENCE] then
          FWarnings.Add(Format('%s.%s generator %s longer than SEQUENCE_NAME: not set', [Table, Field, Seq]))
        else
        begin
          NewVals[COL_SEQUENCE] := Seq;
          NewVals[COL_TRIGGERED] := 1;
        end;
    end;

    if not Exists then
    begin
      WriteField(True, Table, Field, NewVals);
      Inc(pRes.Added);
      FDiff.Add(Format('+ FIELD %s.%s', [Table, Field]));
    end
    else
    begin
      Differs := False;
      for i := 0 to High(SCHEMA_COLS) do
        if not SameVal(OldVals[i], NewVals[i]) then
        begin
          Differs := True;
          FDiff.Add(Format('~ FIELD %s.%s %s: %s -> %s', [Table, Field, SCHEMA_COLS[i],
            ValText(OldVals[i]), ValText(NewVals[i])]));
        end;
      if Differs then
      begin
        WriteField(False, Table, Field, NewVals);
        Inc(pRes.Changed);
      end;
    end;
    Src.Next;
  end;
end;

procedure TSeedRun.CleanOrphans(var pRes: TSchemaSeedResult);
var
  Q: TFDQuery;
  RowIds: TList<Int64>;
  RowId: Int64;
  Table, Field: string;
begin
  RowIds := TList<Int64>.Create;
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := FConn;
    Q.Open(
      'SELECT rowid, TRIM("TABLE_NAME"), TRIM("FIELD_NAME") FROM ' + QuoteRepoIdent(FIELDS_TABLE) +  // dl:ok path-traversal@366d -- SQL text, not a path: identifiers go through QuoteRepoIdent
      ' WHERE "ISCALCULATED" = 0 AND "ISLOOKUP" = 0 AND ' + SQL_NOT_SYSTEM + ' ORDER BY 2, 3');
    while not Q.Eof do
    begin
      Table := Q.Fields[1].AsString;
      Field := Q.Fields[2].AsString;
      if not FRelFields.ContainsKey(Table + '.' + Field) then
      begin
        RowIds.Add(Q.Fields[0].AsLargeInt);
        FDiff.Add(Format('! FIELD %s.%s ISCALCULATED (column vanished)', [Table, Field]));
      end;
      Q.Next;
    end;
    Q.Close;
    for RowId in RowIds do
      FConn.ExecSQL('UPDATE ' + QuoteRepoIdent(FIELDS_TABLE) + ' SET "ISCALCULATED" = 1 WHERE rowid = :R',
        [RowId], [ftLargeint]);
    Inc(pRes.Orphaned, RowIds.Count);
  finally
    Q.Free;
    RowIds.Free;
  end;
end;

procedure TSeedRun.UpdateDatasets(var pRes: TSchemaSeedResult);
var
  Tables: TList<string>;
  Q: TFDQuery;
  Table, KeyField, NameGen, Description, UpdateSql: string;
  Pk, AllFields, NonPk: TArray<string>;
  Gen: TArray<string>;
  NextId, DsId, i: Integer;
  Differs: Boolean;

  function ReadNames(const pSql: string; const pParams: array of Variant): TArray<string>;
  var
    R: TFDQuery;
    Names: TList<string>;
  begin
    Names := TList<string>.Create;
    R := TFDQuery.Create(nil);
    try
      R.Connection := FConn;
      R.Open(pSql, pParams);
      while not R.Eof do
      begin
        Names.Add(R.Fields[0].AsString);
        R.Next;
      end;
      Result := Names.ToArray;
    finally
      R.Free;
      Names.Free;
    end;
  end;

begin
  NextId := FConn.ExecSQLScalar('SELECT COALESCE(MAX("DS_ID"), 0) + 1 FROM ' + QuoteRepoIdent(DATASETS_TABLE));
  Description := 'Auto by drag-lint ' + FStampText;
  Tables := TList<string>.Create;
  Q := TFDQuery.Create(nil);
  try
    Tables.AddRange(ReadNames('SELECT DISTINCT TRIM("TABLE_NAME") FROM ' + QuoteRepoIdent(FIELDS_TABLE) +
      ' WHERE ' + SQL_NOT_SYSTEM_OR_FIB + ' ORDER BY 1', []));
    Q.Connection := FConn;
    for Table in Tables do
    begin
      Pk := PkOf(Table);
      AllFields := ReadNames('SELECT TRIM("FIELD_NAME") FROM ' + QuoteRepoIdent(FIELDS_TABLE) +
        ' WHERE TRIM("TABLE_NAME") = :T AND "ISCALCULATED" = 0 AND "ISLOOKUP" = 0 ORDER BY "FIELD_NAME"', [Table]);
      if (Length(Pk) = 0) or (Length(AllFields) = 0) then
      begin
        Inc(pRes.DatasetsSkipped);
        Continue;
      end;
      KeyField := string.Join(',', Pk);
      if Length(KeyField) > MAX_KEY_FIELD_LEN then
      begin
        FWarnings.Add(Format('%s KEY_FIELD %d chars exceeds VARCHAR(%d): %s -- dataset skipped',
          [Table, Length(KeyField), MAX_KEY_FIELD_LEN, KeyField]));
        Inc(pRes.DatasetsSkipped);
        Continue;
      end;
      NameGen := '';
      if Length(Pk) = 1 then
      begin
        Gen := ReadNames('SELECT TRIM("SEQUENCE_NAME") FROM ' + QuoteRepoIdent(FIELDS_TABLE) +
          ' WHERE TRIM("TABLE_NAME") = :T AND "FIELD_NAME" = :F', [Table, Pk[0]]);
        if Length(Gen) > 0 then
          NameGen := Gen[0];
      end;
      NonPk := nil;
      for i := 0 to High(AllFields) do
        if IndexText(AllFields[i], Pk) < 0 then
          NonPk := NonPk + [AllFields[i]];

      UpdateSql := '';
      if Length(NonPk) > 0 then
        UpdateSql := 'UPDATE ' + Table + ' SET ' + JoinNames(NonPk, ', ', '', '%s=:%s') + ' WHERE ' +
          JoinNames(Pk, ' AND ', '', '%s=:OLD_%s');
      Gen := [
        'SELECT ' + string.Join(', ', AllFields) + ' FROM ' + Table,
        'INSERT INTO ' + Table + ' (' +  // dl:ok sql-injection-concat@18a9 -- generated SQL TEXT stored as data (DL_DATASETS_INFO), never executed here; Table comes from the schema
          string.Join(', ', AllFields) + ') VALUES (' +
          JoinNames(AllFields, ', ', ':', '') + ')',
        UpdateSql,
        'DELETE FROM ' + Table + ' WHERE ' +  // dl:ok sql-injection-concat@9f1a -- generated SQL TEXT stored as data (DL_DATASETS_INFO), never executed here; Table comes from the schema
          JoinNames(Pk, ' AND ', '', '%s=:OLD_%s'),
        'SELECT ' + string.Join(', ', AllFields) + ' FROM ' + Table + ' WHERE ' +
          JoinNames(Pk, ' AND ', '', '%s=:%s'),
        NameGen,
        KeyField];

      Q.Open(
        'SELECT "DS_ID", "SELECT_SQL", "INSERT_SQL", "UPDATE_SQL", "DELETE_SQL", "REFRESH_SQL", ' +  // dl:ok path-traversal@1e3d -- SQL text, not a path: identifiers go through QuoteRepoIdent
        '"NAME_GENERATOR", "KEY_FIELD" FROM ' + QuoteRepoIdent(DATASETS_TABLE) +
        ' WHERE TRIM("UPDATE_TABLE_NAME") = :T ORDER BY "DS_ID" LIMIT 1', [Table]);
      if Q.Eof then
      begin
        Q.Close;
        FConn.ExecSQL('INSERT INTO ' + QuoteRepoIdent(DATASETS_TABLE) + ' ("DS_ID", "DESCRIPTION", ' +
          '"SELECT_SQL", "INSERT_SQL", "UPDATE_SQL", "DELETE_SQL", "REFRESH_SQL", "NAME_GENERATOR", ' +
          '"KEY_FIELD", "UPDATE_TABLE_NAME", "UPDATE_ONLY_MODIFIED_FIELDS", "CONDITIONS") VALUES ' +
          '(:ID, :DE, :S1, :S2, :S3, :S4, :S5, :NG, :KF, :T, 1, '''')',
          [NextId, Description, Gen[GEN_SELECT], Gen[GEN_INSERT], Gen[GEN_UPDATE], Gen[GEN_DELETE], Gen[GEN_REFRESH], Gen[GEN_NAME_GENERATOR], Gen[GEN_KEY_FIELD], Table],
          [ftInteger, ftWideString, ftWideMemo, ftWideMemo, ftWideMemo, ftWideMemo, ftWideMemo,
          ftWideString, ftWideString, ftWideString]);
        FDiff.Add(Format('+ DATASET %s DS_ID=%d', [Table, NextId]));
        Inc(NextId);
        Inc(pRes.DatasetsInserted);
        Continue;
      end;
      DsId := Q.Fields[0].AsInteger;
      Differs := False;
      for i := 0 to High(DS_COLS) do
        if Q.Fields[i + 1].AsString <> Gen[i] then
          Differs := True;
      Q.Close;
      if Differs then
      begin
        FConn.ExecSQL('UPDATE ' + QuoteRepoIdent(DATASETS_TABLE) + ' SET "DESCRIPTION" = :DE, ' +
          '"SELECT_SQL" = :S1, "INSERT_SQL" = :S2, "UPDATE_SQL" = :S3, "DELETE_SQL" = :S4, ' +
          '"REFRESH_SQL" = :S5, "NAME_GENERATOR" = :NG, "KEY_FIELD" = :KF WHERE "DS_ID" = :ID',
          [Description, Gen[GEN_SELECT], Gen[GEN_INSERT], Gen[GEN_UPDATE], Gen[GEN_DELETE], Gen[GEN_REFRESH], Gen[GEN_NAME_GENERATOR], Gen[GEN_KEY_FIELD], DsId],
          [ftWideString, ftWideMemo, ftWideMemo, ftWideMemo, ftWideMemo, ftWideMemo,
          ftWideString, ftWideString, ftInteger]);
        FDiff.Add(Format('~ DATASET %s DS_ID=%d', [Table, DsId]));
        Inc(pRes.DatasetsUpdated);
      end;
    end;
  finally
    Q.Free;
    Tables.Free;
  end;
end;

function TSeedRun.Execute: TSchemaSeedResult;
begin
  Result := Default(TSchemaSeedResult);
  LoadColumnLimits;
  LoadMaps;
  UpdateFields(Result);
  CleanOrphans(Result);
  UpdateDatasets(Result);
  SetRepoMeta(FConn, META_REFRESHED, FStampText);
  Result.Diff := FDiff.ToArray;
  Result.Warnings := FWarnings.ToArray;
end;

function RunSchemaSeed(pTarget: TFDConnection; const pSources: TSchemaSources;
  pMode: TSchemaSeedMode; pDryRun: Boolean; pStampUtc: TDateTime): TSchemaSeedResult;
var
  Run: TSeedRun;
begin
  if (pMode = ssmSeed) and not RepoIsEmpty(pTarget) then
    raise ERepoError.Create('seed needs an EMPTY repository; use refresh on a filled one');
  Run := TSeedRun.Create(pTarget, pSources, pStampUtc);
  try
    pTarget.StartTransaction;
    try
      Result := Run.Execute;
      if pDryRun then
        pTarget.Rollback
      else
        pTarget.Commit;
    except  // dl:ok bare-except@46a7 -- rollback then re-raise, nothing swallowed
      pTarget.Rollback;
      raise;
    end;
  finally
    Run.Free;
  end;
end;

function OpenSchemaSources(pFb: TFDConnection): TSchemaSources;

  function OpenQuery(const pSql: string): TFDQuery;
  begin
    Result := TFDQuery.Create(nil);
    try
      Result.Connection := pFb;
      Result.FetchOptions.Unidirectional := False;
      Result.Open(pSql);  // dl:ok dataset-open-without-close@9c7f -- the open dataset IS the result; FreeSchemaSources releases it
      Result.FetchAll;
    except  // dl:ok bare-except@041e -- free the half-built query, then re-raise
      Result.Free;
      raise;
    end;
  end;

begin
  Result := Default(TSchemaSources);
  try
    Result.Fields := OpenQuery(SQL_FIELDS);
    Result.RelationFields := OpenQuery(SQL_RELATION_FIELDS);
    Result.PrimaryKeys := OpenQuery(SQL_PRIMARY_KEYS);
    Result.Generators := OpenQuery(SQL_GENERATORS);
  except  // dl:ok bare-except@92a7 -- free the queries opened so far, then re-raise
    FreeSchemaSources(Result);
    raise;
  end;
end;

procedure FreeSchemaSources(var pSources: TSchemaSources);
begin
  FreeAndNil(pSources.Fields);
  FreeAndNil(pSources.RelationFields);
  FreeAndNil(pSources.PrimaryKeys);
  FreeAndNil(pSources.Generators);
end;

end.
