unit DRagLint.FieldRepo.SchemaSeed;

{ drag-lint 1.53 -- lane FR-SCHEMA: seed / refresh is now a CHANGE SET producer (PlanSchemaChanges) with a separate
  applier (ApplySchemaChanges), fed by a schema model (live reader or DDL reader). RunSchemaSeed (below) is the 1.52
  direct writer, kept for its regression tests; the repo verbs use the change-set pair.

  drag-lint 1.52 -- lane TTS: seed / refresh a field repository from the Firebird schema.

  Port of TableTools FieldsInfo.Model.pas UpdateFieldsInfo, CleanOrphanFields and
  UpdateDatasetsInfo (design 2026-11-16-tabletools-into-dl-design.md sections 2.1 and 9a).
  The Firebird system tables arrive as four datasets (TSchemaSources), so the logic runs
  on TFDMemTable in the tests and on live queries (OpenSchemaSources) in the CLI.
  Firebird is only READ. }

interface

uses
  System.SysUtils,
  Data.DB,
  FireDAC.Comp.Client,
  DRagLint.FieldRepo.ChangeSet,
  DRagLint.FieldRepo.FbSchemaRead;

type
  /// <summary>Seed = first fill of an EMPTY repository (repo seed-fb); refresh = the old
  /// TableTools "Update Fields Info" on a filled one (repo refresh-schema).</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.FieldRepo.SchemaSeed.pas), DRagLint.CLI.Repo.RepoSeed (DRagLint.CLI.Repo.pas), DRagLint.FieldRepo.SchemaSeed.RunSchemaSeed (DRagLint.FieldRepo.SchemaSeed.pas)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TSchemaSeedMode = (ssmSeed, ssmRefresh);

  /// <summary>The Firebird schema facts the seed reads. The caller owns the datasets.</summary>
  /// <remarks>
  /// Required columns (names case-insensitive; trailing blanks are trimmed):
  /// Fields: TABLE_NAME, FIELD_NAME, DEFAULT_SOURCE, FIELD_LENGTH, FIELD_TYPE,
  /// FIELD_SUB_TYPE, NULL_FLAG, CHARACTER_LEN, FIELD_SCALE -- one row per column of a
  /// user table (no views, no system tables), ordered by table then field position
  /// (the TableTools qryFields). RelationFields: RELATION_NAME, FIELD_NAME of EVERY
  /// relation (the orphan check). PrimaryKeys: TABLE_NAME, FIELD_NAME, FIELD_POSITION, one
  /// row per primary-key segment. Generators: GENERATOR_NAME. A NULL integer reads as 0.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.FieldRepo.SchemaSeed.pas) ?, DRagLint.CLI.Repo.RepoSeed (DRagLint.CLI.Repo.pas) ?, DRagLint.FieldRepo.SchemaSeed.OpenSchemaSources (DRagLint.FieldRepo.SchemaSeed.pas), DRagLint.FieldRepo.SchemaSeed.RunSchemaSeed (DRagLint.FieldRepo.SchemaSeed.pas) ?, DRagLint.FieldRepo.SchemaSeed.TSeedRun.Create (DRagLint.FieldRepo.SchemaSeed.pas) ? (+1 more)</para>
  /// <para>Used in units: DRagLint.CLI.Repo, DRagLint.FieldRepo.SchemaSeed</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TSchemaSources = record
    Fields: TDataSet;
    RelationFields: TDataSet;
    PrimaryKeys: TDataSet;
    Generators: TDataSet;
  end;

  /// <summary>What one seed / refresh run did (or, in a dry run, would do).</summary>
  /// <remarks>
  /// Diff lines: "+ FIELD T.F", "~ FIELD T.F COL: old -> new",
  /// "! FIELD T.F ISCALCULATED (column vanished)", "+ DATASET T DS_ID=n",
  /// "~ DATASET T DS_ID=n". Warnings: a (type, sub_type) without a dictionary entry,
  /// a value cut to its column length, a dataset skipped for an over-long KEY_FIELD.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.FieldRepo.SchemaSeed.pas) ?, DRagLint.CLI.Repo.PrintSeedResult (DRagLint.CLI.Repo.pas) ?, DRagLint.CLI.Repo.RepoSeed (DRagLint.CLI.Repo.pas) ?, DRagLint.FieldRepo.SchemaSeed.TSeedRun.Execute (DRagLint.FieldRepo.SchemaSeed.pas), DRagLint.FieldRepo.SchemaSeed.TSeedRun.UpdateFields (DRagLint.FieldRepo.SchemaSeed.pas) ? (+3 more)</para>
  /// <para>Used in units: DRagLint.CLI.Repo, DRagLint.FieldRepo.SchemaSeed</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
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
/// <remarks>
/// Per column of Fields (UpdateFieldsInfo): a new row gets the TableTools
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
/// rewritten only when its generated text changed; a new row gets MAX(DS_ID) + 1.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.Repo.RepoSeed (DRagLint.CLI.Repo.pas)</para>
/// <para>Calls: DRagLint.FieldRepo.Schema.RepoIsEmpty, DRagLint.FieldRepo.SchemaSeed.TSeedRun.Create, DRagLint.FieldRepo.SchemaSeed.TSeedRun.Execute</para>
/// <para>Returns: Run.Execute</para>
/// <para>Catches: Exception (re-raise)</para>
/// <para>Transaction: starts, commits, rolls back</para>
/// <seealso cref="DRagLint.FieldRepo.Schema.RepoIsEmpty"/>
/// <seealso cref="DRagLint.FieldRepo.SchemaSeed.TSeedRun.Create"/>
/// <seealso cref="DRagLint.FieldRepo.SchemaSeed.TSeedRun.Execute"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function RunSchemaSeed(pTarget: TFDConnection; const pSources: TSchemaSources;
  pMode: TSchemaSeedMode; pDryRun: Boolean; pStampUtc: TDateTime): TSchemaSeedResult;

/// <summary>Opens the four schema queries on a live Firebird connection.</summary>
/// <param name="pFb">An open Firebird connection; only SELECTs on RDB$ tables run.</param>
/// <returns>Open datasets owned by the caller; release them with FreeSchemaSources.</returns>
/// <exception cref="EFDDBEngineException">Raised by FireDAC when a query fails; the
/// datasets opened so far are freed first.</exception>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.Repo.RepoSeed (DRagLint.CLI.Repo.pas)</para>
/// <para>Calls: Default, DRagLint.FieldRepo.SchemaSeed.FreeSchemaSources, DRagLint.FieldRepo.SchemaSeed.OpenSchemaSources.OpenQuery</para>
/// <para>Returns: Default(TSchemaSources)</para>
/// <para>Catches: Exception (re-raise)</para>
/// <seealso cref="DRagLint.FieldRepo.SchemaSeed.FreeSchemaSources"/>
/// <seealso cref="DRagLint.FieldRepo.SchemaSeed.OpenSchemaSources.OpenQuery"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function OpenSchemaSources(pFb: TFDConnection): TSchemaSources;

/// <summary>Frees the datasets of pSources and sets them to nil.</summary>
/// <param name="pSources">Sources from OpenSchemaSources; nil members are skipped.</param>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.Repo.RepoSeed (DRagLint.CLI.Repo.pas), DRagLint.FieldRepo.SchemaSeed.OpenSchemaSources (DRagLint.FieldRepo.SchemaSeed.pas)</para>
/// <para>Calls: FreeAndNil</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure FreeSchemaSources(var pSources: TSchemaSources);

/// <summary>Computes the change set that brings the repository's schema-derived values in line with a schema model.</summary>
/// <param name="pRepo">An open repository connection, schema 2; only SELECTs run (a dry run changes no byte).</param>
/// <param name="pModel">The schema (live reader or DDL reader); Source 'ddl' limits deletes to what the DDL declares.</param>
/// <param name="pMode">ssmSeed needs an EMPTY repository; ssmRefresh works on any.</param>
/// <param name="pWarnings">Values that did not fit their column, types without a dictionary entry, ...</param>
/// <returns>Direction db-to-repo. New tables / fields / domains / constraints / generators are checked inserts;
/// changed schema-derived values are checked updates, one per column; rows whose source vanished are deletes,
/// UNCHECKED. Hand-kept columns (captions, formats, widths, kinds, calc code, ...) never appear.</returns>
/// <exception cref="ERepoError">The repository is schema 1 ("run repo migrate first") or, for seed, not empty.</exception>
/// <remarks>Ids are 1-based in plan order, so the same repository and model always give the same ids.</remarks>
function PlanSchemaChanges(pRepo: TFDConnection; const pModel: TFbSchemaModel; pMode: TSchemaSeedMode;
  out pWarnings: TArray<string>): TFrChangeSet;

/// <summary>What ApplySchemaChanges did.</summary>
type
  TSchemaApplyResult = record
    /// <summary>Changes applied.</summary>
    Applied: Integer;
    DatasetsInserted: Integer;
    DatasetsUpdated: Integer;
    DatasetsSkipped: Integer;
    /// <summary>One 'replacing <old> with <new>' line per applied change.</summary>
    Log: TArray<string>;
    Warnings: TArray<string>;
  end;

/// <summary>Applies the chosen changes of a change set, in one transaction.</summary>
/// <param name="pRepo">An open read-write repository connection, schema 2.</param>
/// <param name="pModel">The same model the set was planned from.</param>
/// <param name="pMode">The mode the set was planned with.</param>
/// <param name="pChosen">The changes to apply (the checked ones, or those a --select file named); blocked ones are refused.</param>
/// <param name="pStampUtc">Time stamped into DL_META schema_read_at_utc.</param>
/// <returns>Counts and the log lines. DL_DATASETS_INFO is regenerated from the repository when anything was applied.</returns>
/// <exception cref="ERepoError">A chosen change is not in the plan the repository and model give now (re-run the dry run);
/// nothing is written.</exception>
/// <remarks>Writes DL_META schema_read_at_utc, schema_source and schema_database (the Database value only, never a
/// password) and schema_refreshed_at_utc even when nothing was chosen, so the read itself is on record.</remarks>
function ApplySchemaChanges(pRepo: TFDConnection; const pModel: TFbSchemaModel; pMode: TSchemaSeedMode;
  const pChosen: TArray<TFrChange>; pStampUtc: TDateTime): TSchemaApplyResult;

implementation

uses
  System.Classes,
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
  { The per-column inputs of ComputeValues: what one source column says (dataset row or model column). }
  TColumnIn = record
    Table, Field, DefaultSource: string;
    FbType, FbSub, FbLen, CharLen, NullFlag, Scale: Integer;
  end;

  { One change of the plan together with what applying it needs. }
  TPlanned = record
    Change: TFrChange;
    RepoTable: string;
    KeyCols: TArray<string>;
    KeyVals: TArray<Variant>;
    { insert: the value columns; update: the one column; delete: unused }
    Cols: TArray<string>;
    Vals: TArray<Variant>;
    { DL_FIELDS_INFO insert: the 14 computed schema values (WriteField), the extras go through Cols / Vals }
    FieldValues: TArray<Variant>;
  end;

  { A row the model says should exist in a schema table. }
  TDesiredRow = record
    KeyVals: TArray<Variant>;
    Vals: TArray<Variant>;
  end;

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
    FModel: TFbSchemaModel;
    FPlanned: TList<TPlanned>;
    FFromDdl: Boolean;
    FScope: TDictionary<string, Boolean>;
    procedure LoadMaps;
    procedure LoadModelMaps;
    function ComputeValues(const pIn: TColumnIn; const pOld: TArray<Variant>; pEnumVar: Boolean;
      const pEnumType: string): TArray<Variant>;
    function ReadExtras(const pTable, pField: string): TArray<Variant>;
    function KeyText(const pKeyVals: TArray<Variant>): string;
    function IsInScope(const pTable: string): Boolean;
    function AddPlanned(pOp: TFrChangeOp; const pTable: string; const pKeyCols: TArray<string>;
      const pKeyVals: TArray<Variant>; const pProp: string; const pOld, pNew: string; pChecked: Boolean;
      const pCols: TArray<string>; const pVals: TArray<Variant>): Integer;
    procedure PlanFields;
    procedure PlanVanishedFields;
    procedure PlanTable(const pTable: string; const pKeyCols, pValCols: TArray<string>;
      const pDesired: TArray<TDesiredRow>; pAllowDelete: TFunc<TArray<Variant>, Boolean>);
    procedure PlanSchemaTables;
    procedure ExecUpdateColumn(const pTable: string; const pKeyCols: TArray<string>; const pKeyVals: TArray<Variant>;
      const pCol: string; const pValue: Variant);
    procedure ExecDelete(const pItem: TPlanned);
    procedure ExecInsert(const pItem: TPlanned);
    procedure ExecPlanned(const pItem: TPlanned);
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
    constructor CreateForModel(pConn: TFDConnection; const pModel: TFbSchemaModel; pStampUtc: TDateTime);
    destructor Destroy; override;
    function Execute: TSchemaSeedResult;
    function Plan: TFrChangeSet;
    function Apply(const pChosen: TArray<TFrChange>; pStampUtc: TDateTime): TSchemaApplyResult;
    property Warnings: TList<string> read FWarnings;
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
  FScope.Free;
  FPlanned.Free;
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
  ColIn: TColumnIn;
  Table, Field, EnumType: string;
  FbType, FbSub, FbLen: Integer;
  OldVals, NewVals: TArray<Variant>;
  Exists, EnumVar, Differs: Boolean;
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
    ColIn := Default(TColumnIn);
    ColIn.Table := Table;
    ColIn.Field := Field;
    ColIn.FbType := FbType;
    ColIn.FbSub := FbSub;
    ColIn.FbLen := FbLen;
    ColIn.CharLen := IntOf(Src, 'CHARACTER_LEN');
    ColIn.NullFlag := IntOf(Src, 'NULL_FLAG');
    ColIn.Scale := IntOf(Src, 'FIELD_SCALE');
    ColIn.DefaultSource := DefaultField.AsString;
    NewVals := ComputeValues(ColIn, OldVals, EnumVar, EnumType);

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
      ' WHERE "ISCALCULATED" = 0 AND "ISLOOKUP" = 0 AND ("FIELD_KIND" IS NULL OR "FIELD_KIND" = 1) AND ' +
      SQL_NOT_SYSTEM + ' ORDER BY 2, 3');
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
      FConn.ExecSQL('UPDATE ' + QuoteRepoIdent(FIELDS_TABLE) + ' SET "ISCALCULATED" = 1, "FIELD_KIND" = 2 WHERE rowid = :R',
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
        ' WHERE TRIM("TABLE_NAME") = :T AND "ISCALCULATED" = 0 AND "ISLOOKUP" = 0 ' +
          'AND ("FIELD_KIND" IS NULL OR "FIELD_KIND" = 1) ORDER BY "FIELD_NAME"', [Table]);
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

{ ---- the change-set producer / applier (FR-SCHEMA) ------------------------------------------------------ }

const
  DOMAINS_TABLE = 'DL_DOMAINS';
  CONSTRAINTS_TABLE = 'DL_CONSTRAINTS';
  CONSTRAINT_COLUMNS_TABLE = 'DL_CONSTRAINT_COLUMNS';
  GENERATORS_TABLE = 'DL_GENERATORS';
  META_SCHEMA_READ = 'schema_read_at_utc';
  META_SCHEMA_SOURCE = 'schema_source';
  META_SCHEMA_DATABASE = 'schema_database';
  KEY_SEP = '|';
  FIELD_KEY_COLS: TArray<string> = ['TABLE_NAME', 'FIELD_NAME'];
  FIELD_EXTRA_COLS: TArray<string> = ['DOMAIN_NAME', 'CHAR_LENGTH'];
  EXTRA_DOMAIN = 0;
  EXTRA_CHARLEN = 1;
  DOMAIN_COLS: TArray<string> = ['FIELD_TYPE', 'FIELD_SUBTYPE', 'FIELD_LENGTH', 'CHAR_LENGTH', 'FIELD_SCALE',
    'FIELD_PRECISION', 'NULL_FLAG', 'DEFAULT_SOURCE', 'CHECK_SOURCE', 'CHARSET'];
  CONSTRAINT_COLS: TArray<string> = ['TABLE_NAME', 'KIND', 'REF_TABLE', 'REF_CONSTRAINT', 'UPDATE_RULE',
    'DELETE_RULE'];
  SUMMARY_MAX = 60;

function NullIfEmpty(const pValue: string): Variant;
begin
  Result := Null;
  if pValue <> '' then
    Result := pValue;
end;

function NullIfZero(pValue: Integer): Variant;
begin
  Result := Null;
  if pValue <> 0 then
    Result := pValue;
end;

function SummaryOf(const pCols: TArray<string>; const pVals: TArray<Variant>): string;
var
  i: Integer;
begin
  Result := '';
  for i := 0 to High(pCols) do
    if not (VarIsNull(pVals[i]) or VarIsEmpty(pVals[i])) then
      Result := Result + (if Result = '' then '' else ', ') + pCols[i] + '=' + VarToStr(pVals[i]);
  if Length(Result) > SUMMARY_MAX then
    Result := Copy(Result, 1, SUMMARY_MAX) + '...';
end;

function ParamTypeOf(const pTable, pColumn: string): TFieldType;
var
  Tab: TRepoTable;
  Col: TRepoColumn;
begin
  Result := ftInteger;
  if FindRepoTable(pTable, Tab) and Tab.FindColumn(pColumn, Col) then
    case Col.Kind of
      rckString: Result := ftWideString;
      rckText: Result := ftWideMemo;
      rckBoolean: Result := ftBoolean;
    end;
end;

procedure TSeedRun.LoadModelMaps;
var
  Con: TFbConstraint;
  Col: TFbColumn;
  Keys: TList<string>;
  Name: string;
begin
  FScope := TDictionary<string, Boolean>.Create;
  for Con in FModel.Constraints do
  begin
    FScope.AddOrSetValue(Con.TableName.ToUpper, True);
    if Con.Kind = 'PK' then
    begin
      Keys := TList<string>.Create;
      for Name in Con.Columns do
        Keys.Add(Name.ToUpper);
      FPk.AddOrSetValue(Con.TableName.ToUpper, Keys);
    end;
  end;
  for Col in FModel.Columns do
    FScope.AddOrSetValue(Col.TableName.ToUpper, True);
  for Name in FModel.Generators do
    FGenerators.AddOrSetValue(Name.ToUpper, True);
end;

constructor TSeedRun.CreateForModel(pConn: TFDConnection; const pModel: TFbSchemaModel; pStampUtc: TDateTime);
begin
  Create(pConn, Default(TSchemaSources), pStampUtc);
  FModel := pModel;
  FFromDdl := SameText(pModel.Source, 'ddl');
  FPlanned := TList<TPlanned>.Create;
  LoadColumnLimits;
  LoadModelMaps;
end;

{ The 14 schema-derived DL_FIELDS_INFO values of one column, from what the source says plus what the row holds now
  (a stored DEFAULTVAL and an enum VAR_TYPE are hand-kept and survive). }
function TSeedRun.ComputeValues(const pIn: TColumnIn; const pOld: TArray<Variant>; pEnumVar: Boolean;
  const pEnumType: string): TArray<Variant>;
var
  Accessor, VarType, Seq, Key: string;
  Pk: TArray<string>;
  InPk: Boolean;
begin
  Result := Copy(pOld);
  if TryFbFieldAccessor(pIn.FbType, pIn.FbSub, Accessor) then
    Result[COL_AS_TYPE] := Accessor
  else
    FWarnings.Add(Format('%s.%s type=%d sub_type=%d: no entry in the type dictionary, ' +
      'FIELD_AS_TYPE / VAR_TYPE left as they were', [pIn.Table, pIn.Field, pIn.FbType, pIn.FbSub]));
  if pEnumVar then
    Result[COL_VAR_TYPE] := pEnumType
  else if TryFbFieldVarType(pIn.FbType, pIn.FbSub, pIn.FbLen, VarType) then
    Result[COL_VAR_TYPE] := VarType;
  if VarIsNull(Result[COL_DEFAULTVAL]) then
    Result[COL_DEFAULTVAL] := Fit(DefaultValOf(pIn.DefaultSource), pIn.Table, pIn.Field, COL_DEFAULTVAL);
  Result[COL_FIELD_SIZE] := pIn.FbLen;
  Result[COL_STRING_SIZE] := pIn.CharLen;
  Result[COL_NULL_FLAG] := pIn.NullFlag;
  Result[COL_FIELD_KIND] := FIELD_KIND_COLUMN;
  Result[COL_FIELD_TYPE] := pIn.FbType;
  Result[COL_FIELD_SUBTYPE] := pIn.FbSub;
  Result[COL_FIELD_LENGTH] := pIn.FbLen;
  Result[COL_FIELD_SCALE] := pIn.Scale;

  Pk := PkOf(pIn.Table);
  InPk := False;
  for Key in Pk do
    if Key = pIn.Field then
      InPk := True;
  Result[COL_PRIMARY_KEY] := Ord(InPk);
  { SEQUENCE_NAME only for a single-segment BIGINT key whose generator exists }
  if InPk and (Length(Pk) = 1) and (pIn.FbType = FB_TYPE_INT64) then
  begin
    Seq := 'GEN_' + pIn.Table + '_' + pIn.Field;
    if FGenerators.ContainsKey(Seq) then
      if Length(Seq) > FStringMax[COL_SEQUENCE] then
        FWarnings.Add(Format('%s.%s generator %s longer than SEQUENCE_NAME: not set', [pIn.Table, pIn.Field, Seq]))
      else
      begin
        Result[COL_SEQUENCE] := Seq;
        Result[COL_TRIGGERED] := 1;
      end;
  end;
end;

function TSeedRun.ReadExtras(const pTable, pField: string): TArray<Variant>;
var
  Q: TFDQuery;
begin
  Result := [Null, Null];
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := FConn;
    Q.Open('SELECT "DOMAIN_NAME", "CHAR_LENGTH" FROM ' + QuoteRepoIdent(FIELDS_TABLE) +  // dl:ok path-traversal -- SQL text, not a path: the identifier goes through QuoteRepoIdent
      ' WHERE "TABLE_NAME" = :T AND "FIELD_NAME" = :F', [pTable, pField]);
    if not Q.Eof then
    begin
      Result[EXTRA_DOMAIN] := Q.Fields[EXTRA_DOMAIN].Value;
      Result[EXTRA_CHARLEN] := Q.Fields[EXTRA_CHARLEN].Value;
    end;
  finally
    Q.Free;
  end;
end;

function TSeedRun.KeyText(const pKeyVals: TArray<Variant>): string;
var
  i: Integer;
begin
  Result := '';
  for i := 0 to High(pKeyVals) do
    Result := Result + (if i = 0 then '' else KEY_SEP) + VarToStr(pKeyVals[i]);
end;

{ A DDL source is partial: only the tables it declares are candidates for "vanished". }
function TSeedRun.IsInScope(const pTable: string): Boolean;
begin
  Result := (not FFromDdl) or FScope.ContainsKey(pTable.ToUpper);
end;

function TSeedRun.AddPlanned(pOp: TFrChangeOp; const pTable: string; const pKeyCols: TArray<string>;
  const pKeyVals: TArray<Variant>; const pProp: string; const pOld, pNew: string; pChecked: Boolean;
  const pCols: TArray<string>; const pVals: TArray<Variant>): Integer;
var
  Item: TPlanned;
begin
  Item := Default(TPlanned);
  Item.RepoTable := pTable;
  Item.KeyCols := pKeyCols;
  Item.KeyVals := pKeyVals;
  Item.Cols := pCols;
  Item.Vals := pVals;
  Item.Change.Op := pOp;
  Item.Change.Target := pTable + ' ' + KeyText(pKeyVals);
  Item.Change.Prop := pProp;
  Item.Change.OldValue := pOld;
  Item.Change.NewValue := pNew;
  Item.Change.Checked := pChecked;
  Result := FPlanned.Add(Item);
end;

procedure TSeedRun.PlanFields;
var
  Col: TFbColumn;
  ColIn: TColumnIn;
  Table, Field, EnumType: string;
  OldVals, NewVals, OldExtra, NewExtra, Keys: TArray<Variant>;
  Exists, EnumVar: Boolean;
  i, Idx: Integer;
  Item: TPlanned;
begin
  for Col in FModel.Columns do
  begin
    Table := Col.TableName.ToUpper;
    Field := Col.ColumnName.ToUpper;
    ColIn := Default(TColumnIn);
    ColIn.Table := Table;
    ColIn.Field := Field;
    ColIn.FbType := Col.FieldType;
    ColIn.FbSub := Col.SubType;
    ColIn.FbLen := Col.FieldLength;
    ColIn.CharLen := Col.CharLength;
    ColIn.NullFlag := Col.NullFlag;
    ColIn.Scale := Col.Scale;
    ColIn.DefaultSource := Col.DefaultSource;
    Exists := ReadOld(Table, Field, OldVals, EnumVar, EnumType);
    NewVals := ComputeValues(ColIn, OldVals, EnumVar, EnumType);
    NewExtra := [NullIfEmpty(Col.DomainName), NullIfZero(Col.CharLength)];
    OldExtra := ReadExtras(Table, Field);
    Keys := [Table, Field];
    if not Exists then
    begin
      Idx := AddPlanned(fcoInsert, FIELDS_TABLE, FIELD_KEY_COLS, Keys, '', '',
        Format('type=%d sub=%d len=%d', [Col.FieldType, Col.SubType, Col.FieldLength]), True, FIELD_EXTRA_COLS, NewExtra);
      Item := FPlanned[Idx];
      Item.FieldValues := NewVals;
      FPlanned[Idx] := Item;
      Continue;
    end;
    for i := 0 to High(SCHEMA_COLS) do
      if not SameVal(OldVals[i], NewVals[i]) then
        AddPlanned(fcoUpdate, FIELDS_TABLE, FIELD_KEY_COLS, Keys, SCHEMA_COLS[i], ValText(OldVals[i]),
          ValText(NewVals[i]), True, [SCHEMA_COLS[i]], [NewVals[i]]);
    for i := 0 to High(FIELD_EXTRA_COLS) do
      if not SameVal(OldExtra[i], NewExtra[i]) then
        AddPlanned(fcoUpdate, FIELDS_TABLE, FIELD_KEY_COLS, Keys, FIELD_EXTRA_COLS[i], ValText(OldExtra[i]),
          ValText(NewExtra[i]), True, [FIELD_EXTRA_COLS[i]], [NewExtra[i]]);
  end;
end;

procedure TSeedRun.PlanVanishedFields;
var
  Seen: TDictionary<string, Boolean>;
  Col: TFbColumn;
  Q: TFDQuery;
  Table, Field: string;
begin
  Seen := TDictionary<string, Boolean>.Create;
  Q := TFDQuery.Create(nil);
  try
    for Col in FModel.Columns do
      Seen.AddOrSetValue(Col.TableName.ToUpper + KEY_SEP + Col.ColumnName.ToUpper, True);
    Q.Connection := FConn;
    Q.Open('SELECT "TABLE_NAME", "FIELD_NAME", "FIELD_TYPE", "FIELD_LENGTH" FROM ' + QuoteRepoIdent(FIELDS_TABLE) +  // dl:ok path-traversal -- SQL text, not a path: the identifier goes through QuoteRepoIdent
      ' WHERE "ISCALCULATED" = 0 AND "ISLOOKUP" = 0 AND ("FIELD_KIND" IS NULL OR "FIELD_KIND" = 1) AND ' +
      SQL_NOT_SYSTEM + ' ORDER BY 1, 2');
    while not Q.Eof do
    begin
      Table := Q.Fields[0].AsString;
      Field := Q.Fields[1].AsString;
      if IsInScope(Trim(Table)) and not Seen.ContainsKey(Trim(Table) + KEY_SEP + Trim(Field)) then
        AddPlanned(fcoDelete, FIELDS_TABLE, FIELD_KEY_COLS, [Table, Field], '',
          Format('type=%s len=%s (column vanished)', [Q.Fields[2].AsString, Q.Fields[3].AsString]), '', False, nil, nil);
      Q.Next;
    end;
  finally
    Q.Free;
    Seen.Free;
  end;
end;

procedure TSeedRun.PlanTable(const pTable: string; const pKeyCols, pValCols: TArray<string>;
  const pDesired: TArray<TDesiredRow>; pAllowDelete: TFunc<TArray<Variant>, Boolean>);
var
  Q: TFDQuery;
  Existing: TDictionary<string, TArray<Variant>>;
  ExistKeys: TDictionary<string, TArray<Variant>>;
  Order, Wanted: TStringList;
  KeyV, OldV: TArray<Variant>;
  Row: TDesiredRow;
  Key, ColList, OrderBy: string;
  i, NKey: Integer;
begin
  NKey := Length(pKeyCols);
  ColList := '';
  for i := 0 to NKey - 1 do
    ColList := ColList + (if i = 0 then '' else ', ') + QuoteRepoIdent(pKeyCols[i]);
  OrderBy := ColList;
  for i := 0 to High(pValCols) do
    ColList := ColList + ', ' + QuoteRepoIdent(pValCols[i]);
  Existing := TDictionary<string, TArray<Variant>>.Create;
  ExistKeys := TDictionary<string, TArray<Variant>>.Create;
  Order := TStringList.Create;
  Wanted := TStringList.Create;
  Q := TFDQuery.Create(nil);
  try
    Wanted.Sorted := True;
    Q.Connection := FConn;
    Q.Open('SELECT ' + ColList + ' FROM ' + QuoteRepoIdent(pTable) + ' ORDER BY ' + OrderBy);  // dl:ok path-traversal -- SQL text, not a path: identifiers go through QuoteRepoIdent
    while not Q.Eof do
    begin
      SetLength(KeyV, NKey);
      SetLength(OldV, Length(pValCols));
      for i := 0 to NKey - 1 do
        KeyV[i] := Q.Fields[i].Value;
      for i := 0 to High(pValCols) do
        OldV[i] := Q.Fields[NKey + i].Value;
      Key := KeyText(KeyV);
      Existing.AddOrSetValue(Key, Copy(OldV));
      ExistKeys.AddOrSetValue(Key, Copy(KeyV));
      Order.Add(Key);
      Q.Next;
    end;
    for Row in pDesired do
    begin
      Key := KeyText(Row.KeyVals);
      Wanted.Add(Key);
      if not Existing.TryGetValue(Key, OldV) then
        AddPlanned(fcoInsert, pTable, pKeyCols, Row.KeyVals, '', '', SummaryOf(pValCols, Row.Vals), True, pValCols,
          Row.Vals)
      else
        for i := 0 to High(pValCols) do
          if not SameVal(OldV[i], Row.Vals[i]) then
            AddPlanned(fcoUpdate, pTable, pKeyCols, Row.KeyVals, pValCols[i], ValText(OldV[i]), ValText(Row.Vals[i]),
              True, [pValCols[i]], [Row.Vals[i]]);
    end;
    for Key in Order do
      if (Wanted.IndexOf(Key) < 0) and ((not Assigned(pAllowDelete)) or pAllowDelete(ExistKeys[Key])) then
        AddPlanned(fcoDelete, pTable, pKeyCols, ExistKeys[Key], '', SummaryOf(pValCols, Existing[Key]), '', False,
          nil, nil);
  finally
    Q.Free;
    Wanted.Free;
    Order.Free;
    ExistKeys.Free;
    Existing.Free;
  end;
end;

procedure TSeedRun.PlanSchemaTables;
var
  Dom: TFbDomain;
  Con: TFbConstraint;
  Gen: string;
  Rows: TArray<TDesiredRow>;
  Row: TDesiredRow;
  i: Integer;
  ModelCons: TDictionary<string, Boolean>;
  NotDdl: TFunc<TArray<Variant>, Boolean>;
begin
  NotDdl := function(pKey: TArray<Variant>): Boolean
    begin
      Result := not FFromDdl;
    end;
  Rows := nil;
  for Dom in FModel.Domains do
  begin
    Row.KeyVals := [Dom.Name];
    Row.Vals := [Dom.FieldType, Dom.SubType, Dom.FieldLength, NullIfZero(Dom.CharLength), Dom.Scale, Dom.Precision,
      Dom.NullFlag, NullIfEmpty(Dom.DefaultSource), NullIfEmpty(Dom.CheckSource), NullIfEmpty(Dom.Charset)];
    Rows := Rows + [Row];
  end;
  PlanTable(DOMAINS_TABLE, ['DOMAIN_NAME'], DOMAIN_COLS, Rows, NotDdl);

  Rows := nil;
  ModelCons := TDictionary<string, Boolean>.Create;
  try
    for Con in FModel.Constraints do
    begin
      ModelCons.AddOrSetValue(Con.Name, True);
      Row.KeyVals := [Con.Name];
      Row.Vals := [Con.TableName, Con.Kind, NullIfEmpty(Con.RefTable), NullIfEmpty(Con.RefConstraint),
        NullIfEmpty(Con.UpdateRule), NullIfEmpty(Con.DeleteRule)];
      Rows := Rows + [Row];
    end;
    PlanTable(CONSTRAINTS_TABLE, ['CONSTRAINT_NAME'], CONSTRAINT_COLS, Rows, NotDdl);

    Rows := nil;
    for Con in FModel.Constraints do
      for i := 0 to High(Con.Columns) do
      begin
        Row.KeyVals := [Con.Name, i + 1];
        Row.Vals := [Con.Columns[i]];
        Rows := Rows + [Row];
      end;
    PlanTable(CONSTRAINT_COLUMNS_TABLE, ['CONSTRAINT_NAME', 'POSITION'], ['COLUMN_NAME'], Rows,
      function(pKey: TArray<Variant>): Boolean
      begin
        Result := (not FFromDdl) or ModelCons.ContainsKey(VarToStr(pKey[0]));
      end);
  finally
    ModelCons.Free;
  end;

  Rows := nil;
  for Gen in FModel.Generators do
  begin
    Row.KeyVals := [Gen];
    Row.Vals := nil;
    Rows := Rows + [Row];
  end;
  PlanTable(GENERATORS_TABLE, ['GENERATOR_NAME'], nil, Rows, NotDdl);
end;

function TSeedRun.Plan: TFrChangeSet;
var
  i: Integer;
  Item: TPlanned;
begin
  FPlanned.Clear;
  PlanSchemaTables;
  PlanFields;
  PlanVanishedFields;
  Result := Default(TFrChangeSet);
  Result.Direction := fdDbToRepo;
  SetLength(Result.Changes, FPlanned.Count);
  for i := 0 to FPlanned.Count - 1 do
  begin
    Item := FPlanned[i];
    Item.Change.Id := i + 1;
    FPlanned[i] := Item;
    Result.Changes[i] := Item.Change;
  end;
end;

procedure TSeedRun.ExecUpdateColumn(const pTable: string; const pKeyCols: TArray<string>;
  const pKeyVals: TArray<Variant>; const pCol: string; const pValue: Variant);
var
  Where: string;
  Params: TArray<Variant>;
  Types: TArray<TFieldType>;
  i: Integer;
begin
  Where := '';
  Params := [pValue];
  Types := [ParamTypeOf(pTable, pCol)];
  for i := 0 to High(pKeyCols) do
  begin
    Where := Where + (if i = 0 then '' else ' AND ') + QuoteRepoIdent(pKeyCols[i]) + ' = :K' + IntToStr(i);
    Params := Params + [pKeyVals[i]];
    Types := Types + [ParamTypeOf(pTable, pKeyCols[i])];
  end;
  FConn.ExecSQL('UPDATE ' + QuoteRepoIdent(pTable) + ' SET ' + QuoteRepoIdent(pCol) + ' = :V WHERE ' + Where,  // dl:ok sql-injection-concat -- the table and column names are the repository's own constants, quoted
    Params, Types);
end;

procedure TSeedRun.ExecDelete(const pItem: TPlanned);
var
  Where: string;
  Types: TArray<TFieldType>;
  i: Integer;
begin
  Where := '';
  for i := 0 to High(pItem.KeyCols) do
  begin
    Where := Where + (if i = 0 then '' else ' AND ') + QuoteRepoIdent(pItem.KeyCols[i]) + ' = :K' + IntToStr(i);
    Types := Types + [ParamTypeOf(pItem.RepoTable, pItem.KeyCols[i])];
  end;
  FConn.ExecSQL('DELETE FROM ' + QuoteRepoIdent(pItem.RepoTable) + ' WHERE ' + Where, pItem.KeyVals, Types);  // dl:ok sql-injection-concat -- the table name is one of the repository's own constants, quoted
end;

procedure TSeedRun.ExecInsert(const pItem: TPlanned);
var
  Names, Marks: string;
  Params: TArray<Variant>;
  Types: TArray<TFieldType>;
  i, N: Integer;
begin
  Names := '';
  Marks := '';
  Params := Copy(pItem.KeyVals);
  N := Length(pItem.KeyCols);
  for i := 0 to N - 1 do
  begin
    Names := Names + (if i = 0 then '' else ', ') + QuoteRepoIdent(pItem.KeyCols[i]);
    Marks := Marks + (if i = 0 then '' else ', ') + ':P' + IntToStr(i);
    Types := Types + [ParamTypeOf(pItem.RepoTable, pItem.KeyCols[i])];
  end;
  for i := 0 to High(pItem.Cols) do
  begin
    Names := Names + ', ' + QuoteRepoIdent(pItem.Cols[i]);
    Marks := Marks + ', :P' + IntToStr(N + i);
    Params := Params + [pItem.Vals[i]];
    Types := Types + [ParamTypeOf(pItem.RepoTable, pItem.Cols[i])];
  end;
  FConn.ExecSQL('INSERT INTO ' + QuoteRepoIdent(pItem.RepoTable) + ' (' + Names + ') VALUES (' + Marks + ')',  // dl:ok sql-injection-concat -- the table name is one of the repository's own constants, quoted
    Params, Types);
end;

procedure TSeedRun.ExecPlanned(const pItem: TPlanned);
var
  i: Integer;
begin
  case pItem.Change.Op of
    fcoDelete:
      ExecDelete(pItem);
    fcoUpdate:
      ExecUpdateColumn(pItem.RepoTable, pItem.KeyCols, pItem.KeyVals, pItem.Cols[0], pItem.Vals[0]);
  else
    if SameText(pItem.RepoTable, FIELDS_TABLE) then
    begin
      { a new field row: the TableTools new-row values + the 14 computed columns, then the two extras }
      WriteField(True, VarToStr(pItem.KeyVals[0]), VarToStr(pItem.KeyVals[1]), pItem.FieldValues);
      for i := 0 to High(pItem.Cols) do
        if not VarIsNull(pItem.Vals[i]) then
          ExecUpdateColumn(pItem.RepoTable, pItem.KeyCols, pItem.KeyVals, pItem.Cols[i], pItem.Vals[i]);
    end
    else
      ExecInsert(pItem);
  end;
end;
function TSeedRun.Apply(const pChosen: TArray<TFrChange>; pStampUtc: TDateTime): TSchemaApplyResult;
var
  Ch: TFrChange;
  Item: TPlanned;
  Ids: TList<Integer>;
  Id: Integer;
  Ds: TSchemaSeedResult;
  Stamp: string;
begin
  Result := Default(TSchemaApplyResult);
  Plan;
  Ids := TList<Integer>.Create;
  try
    for Ch in pChosen do
    begin
      if (Ch.Id < 1) or (Ch.Id > FPlanned.Count) then
        raise ERepoError.CreateFmt('Change %d is not in the plan the repository and schema give now; re-run the dry run',
          [Ch.Id]);
      Item := FPlanned[Ch.Id - 1];
      if (Item.Change.Op <> Ch.Op) or (Item.Change.Target <> Ch.Target) or (Item.Change.Prop <> Ch.Prop) then
        raise ERepoError.CreateFmt('Change %d no longer matches the plan (%s); re-run the dry run',
          [Ch.Id, Item.Change.Target]);
      if Item.Change.Blocked <> '' then
        raise ERepoError.CreateFmt('Change %d is blocked: %s', [Ch.Id, Item.Change.Blocked]);
      if Ids.IndexOf(Ch.Id) < 0 then
        Ids.Add(Ch.Id);
    end;
    Ids.Sort;
    Stamp := DateToISO8601(pStampUtc, True);
    FConn.StartTransaction;
    try
      for Id in Ids do
      begin
        Item := FPlanned[Id - 1];
        ExecPlanned(Item);
        Inc(Result.Applied);
        Result.Log := Result.Log + [ApplyLogLine(Item.Change)];
      end;
      if Result.Applied > 0 then
      begin
        Ds := Default(TSchemaSeedResult);
        UpdateDatasets(Ds);
        Result.DatasetsInserted := Ds.DatasetsInserted;
        Result.DatasetsUpdated := Ds.DatasetsUpdated;
        Result.DatasetsSkipped := Ds.DatasetsSkipped;
      end;
      SetRepoMeta(FConn, META_SCHEMA_READ, Stamp);
      SetRepoMeta(FConn, META_SCHEMA_SOURCE, FModel.Source);
      SetRepoMeta(FConn, META_SCHEMA_DATABASE, FModel.Database);
      SetRepoMeta(FConn, META_REFRESHED, Stamp);
      FConn.Commit;
    except
      FConn.Rollback;
      raise;
    end;
  finally
    Ids.Free;
  end;
  Result.Warnings := FWarnings.ToArray;
end;

procedure RequireV2(pRepo: TFDConnection);
begin
  if RepoSchemaVersion(pRepo) < 2 then
    raise ERepoError.Create('The repository is schema 1: run `repo migrate --apply` before reading schema facts');
end;

function PlanSchemaChanges(pRepo: TFDConnection; const pModel: TFbSchemaModel; pMode: TSchemaSeedMode;
  out pWarnings: TArray<string>): TFrChangeSet;
var
  Run: TSeedRun;
begin
  RequireV2(pRepo);
  if (pMode = ssmSeed) and not RepoIsEmpty(pRepo) then
    raise ERepoError.Create('seed needs an EMPTY repository; use refresh on a filled one');
  Run := TSeedRun.CreateForModel(pRepo, pModel, 0);
  try
    Result := Run.Plan;
    pWarnings := Run.Warnings.ToArray;
  finally
    Run.Free;
  end;
end;

function ApplySchemaChanges(pRepo: TFDConnection; const pModel: TFbSchemaModel; pMode: TSchemaSeedMode;
  const pChosen: TArray<TFrChange>; pStampUtc: TDateTime): TSchemaApplyResult;
var
  Run: TSeedRun;
begin
  RequireV2(pRepo);
  if (pMode = ssmSeed) and not RepoIsEmpty(pRepo) then
    raise ERepoError.Create('seed needs an EMPTY repository; use refresh on a filled one');
  Run := TSeedRun.CreateForModel(pRepo, pModel, pStampUtc);
  try
    Result := Run.Apply(pChosen, pStampUtc);
  finally
    Run.Free;
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
    except
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
    except
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
  except
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
