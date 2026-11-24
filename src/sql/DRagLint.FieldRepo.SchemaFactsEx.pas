unit DRagLint.FieldRepo.SchemaFactsEx;

{ Wave v154 shared helper S2 (owned by lane SCHEMA): a snapshot of the schema facts of a field repository for lint --
  which columns a table has, their type, NOT NULL, default, trigger and sequence. Read only; the snapshot needs no
  connection once it is made, so it can serve a whole lint run. }

interface

uses
  FireDAC.Comp.Client,
  DRagLint.FieldRepo.SchemaFacts,
  DRagLint.FieldRepo.Exceptions;

type
  /// <summary>What kind of value a column holds; scgUnknown = the repository does not say (domain not resolved,
  /// OCTETS text, a type code without a kind).</summary>
  TSchemaGroup = (scgUnknown, scgText, scgMemo, scgNumber, scgDateTime, scgBoolean, scgBinary);

  /// <summary>One column of the field repository.</summary>
  TSchemaColumn = record
    /// <summary>Upper-case table name.</summary>
    Table: string;
    /// <summary>Upper-case column name.</summary>
    Column: string;
    /// <summary>Kind of value.</summary>
    Group: TSchemaGroup;
    /// <summary>The type for a message, e.g. VARCHAR(20); '' when unknown.</summary>
    TypeText: string;
    /// <summary>Declared characters (own or domain); -1 = unknown or not a character column.</summary>
    CharLength: Integer;
    /// <summary>True when the column or its domain is NOT NULL.</summary>
    NotNull: Boolean;
    /// <summary>True when the database fills a missing value: a default of the column or its domain, a trigger, a
    /// sequence, a generator named after the column, or a numeric primary key (which may have one of another name).</summary>
    Filled: Boolean;
    /// <summary>True for a calculated or lookup row: a dataset field, not a table column.</summary>
    Calculated: Boolean;
  end;

  /// <summary>The schema facts of one field repository at the time it was read.</summary>
  /// <remarks>Immutable, so it may be shared between threads.</remarks>
  ISchemaFacts = interface
    ['{5B4C2B0A-6C60-4B43-9E0D-3C0A1F0E7A54}']
    /// <summary>Where and when the facts were read.</summary>
    /// <returns>The provenance.</returns>
    function Info: TSchemaInfo;
    /// <summary>True when a schema read covered the table.</summary>
    /// <param name="pTable">Table name, any case.</param>
    /// <returns>False also for a table whose rows hold no type facts (entered by hand or from forms only).</returns>
    function KnowsTable(const pTable: string): Boolean;
    /// <summary>Looks a column up.</summary>
    /// <param name="pTable">Table name, any case.</param>
    /// <param name="pColumn">Column name, any case.</param>
    /// <param name="pFact">Receives the column.</param>
    /// <returns>True when the repository has a row for it, calculated and lookup rows included.</returns>
    function FindColumn(const pTable, pColumn: string; out pFact: TSchemaColumn): Boolean;
    /// <summary>The columns of a table.</summary>
    /// <param name="pTable">Table name, any case.</param>
    /// <returns>Ordered by name; empty for an unknown table.</returns>
    function ColumnsOf(const pTable: string): TArray<TSchemaColumn>;
    /// <summary>Every column of that name in any table.</summary>
    /// <param name="pColumn">Column name, any case.</param>
    /// <returns>Ordered by table.</returns>
    function ColumnsNamed(const pColumn: string): TArray<TSchemaColumn>;
    /// <summary>True when a DL_EXCEPTIONS row accepts the finding.</summary>
    /// <param name="pFinding">The finding's keys.</param>
    /// <returns>See DRagLint.FieldRepo.Exceptions.IsExcepted.</returns>
    function Excepted(const pFinding: TFrFinding): Boolean;
  end;

/// <summary>Reads the schema facts of a repository.</summary>
/// <param name="pRepo">An open repository connection; not used after return.</param>
/// <returns>The facts, or nil when no schema read was ever applied (SchemaFacts.HasSchema).</returns>
function LoadSchemaFacts(pRepo: TFDConnection): ISchemaFacts;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  Data.DB;

const
  CHAR_LENGTH_UNKNOWN = -1;
  FIELD_KIND_COLUMN = 1;
  SUBTYPE_ONE = 1;
  FB_SHORT = 7;
  FB_LONG = 8;
  FB_FLOAT = 10;
  FB_DATE = 12;
  FB_TIME = 13;
  FB_CHAR = 14;
  FB_INT64 = 16;
  FB_BOOLEAN = 23;
  FB_DEC16 = 24;
  FB_DEC34 = 25;
  FB_INT128 = 26;
  FB_DOUBLE = 27;
  FB_TIME_TZ = 28;
  FB_TIMESTAMP_TZ = 29;
  FB_TIMESTAMP = 35;
  FB_VARCHAR = 37;
  FB_CSTRING = 40;
  FB_BLOB = 261;
  SQL_COLUMNS =
    'SELECT F."TABLE_NAME", F."FIELD_NAME", F."FIELD_TYPE", F."FIELD_SUBTYPE", F."FIELD_SCALE", F."CHAR_LENGTH", ' +
    'F."NULL_FLAG", F."DEFAULTVAL", F."TRIGGERED", F."SEQUENCE_NAME", F."PRIMARY_KEY", F."ISCALCULATED", F."ISLOOKUP", ' +
    'F."FIELD_KIND", D."FIELD_TYPE", D."FIELD_SUBTYPE", D."FIELD_SCALE", D."CHAR_LENGTH", D."NULL_FLAG", D."DEFAULT_SOURCE" ' +
    'FROM "DL_FIELDS_INFO" F LEFT JOIN "DL_DOMAINS" D ON D."DOMAIN_NAME" = F."DOMAIN_NAME" ORDER BY 1, 2';
  SQL_GENERATORS = 'SELECT "GENERATOR_NAME" FROM "DL_GENERATORS"';
  { columns of SQL_COLUMNS }
  C_TABLE = 0;
  C_FIELD = 1;
  C_TYPE = 2;
  C_SUBTYPE = 3;
  C_SCALE = 4;
  C_CHARS = 5;
  C_NULL = 6;
  C_DEFAULT = 7;
  C_TRIGGERED = 8;
  C_SEQUENCE = 9;
  C_PRIMARY = 10;
  C_CALC = 11;
  C_LOOKUP = 12;
  C_KIND = 13;
  C_DOM_TYPE = 14;
  C_DOM_SUBTYPE = 15;
  C_DOM_SCALE = 16;
  C_DOM_CHARS = 17;
  C_DOM_NULL = 18;
  C_DOM_DEFAULT = 19;

type
  TSchemaFacts = class(TInterfacedObject, ISchemaFacts)
  strict private
    FInfo: TSchemaInfo;
    FExceptions: TArray<TFrException>;
    FColumns: TList<TSchemaColumn>;
    FByKey: TDictionary<string, Integer>;
    FByTable: TObjectDictionary<string, TList<Integer>>;
    FByName: TObjectDictionary<string, TList<Integer>>;
    FRead: TDictionary<string, Boolean>; // tables a schema read covered
    procedure Add(const pFact: TSchemaColumn);
    procedure LoadColumns(pRepo: TFDConnection);
    function Pick(pMap: TObjectDictionary<string, TList<Integer>>; const pKey: string): TArray<TSchemaColumn>;
  public
    constructor Create(pRepo: TFDConnection);
    destructor Destroy; override;
    function Info: TSchemaInfo;
    function KnowsTable(const pTable: string): Boolean;
    function FindColumn(const pTable, pColumn: string; out pFact: TSchemaColumn): Boolean;
    function ColumnsOf(const pTable: string): TArray<TSchemaColumn>;
    function ColumnsNamed(const pColumn: string): TArray<TSchemaColumn>;
    function Excepted(const pFinding: TFrFinding): Boolean;
  end;

function KeyOf(const pTable, pColumn: string): string;
begin
  Result := UpperCase(pTable) + '|' + UpperCase(pColumn);
end;

{ pType / pSubType: RDB$FIELD_TYPE and RDB$FIELD_SUB_TYPE. }
function GroupOf(pType, pSubType: Integer): TSchemaGroup;
begin
  case pType of
    FB_CHAR, FB_VARCHAR, FB_CSTRING:
      Result := if pSubType = SUBTYPE_ONE then scgUnknown else scgText; // sub_type 1 = OCTETS: bytes or a GUID
    FB_SHORT, FB_LONG, FB_FLOAT, FB_INT64, FB_DEC16, FB_DEC34, FB_INT128, FB_DOUBLE:
      Result := scgNumber;
    FB_DATE, FB_TIME, FB_TIMESTAMP, FB_TIME_TZ, FB_TIMESTAMP_TZ:
      Result := scgDateTime;
    FB_BOOLEAN:
      Result := scgBoolean;
    FB_BLOB:
      Result := if pSubType = SUBTYPE_ONE then scgMemo else scgBinary;
  else
    Result := scgUnknown;
  end;
end;

function TypeName(pType, pSubType, pScale: Integer): string;
begin
  case pType of
    FB_SHORT: Result := 'SMALLINT';
    FB_LONG: Result := 'INTEGER';
    FB_FLOAT: Result := 'FLOAT';
    FB_DATE: Result := 'DATE';
    FB_TIME, FB_TIME_TZ: Result := 'TIME';
    FB_CHAR: Result := 'CHAR';
    FB_INT64: Result := 'BIGINT';
    FB_BOOLEAN: Result := 'BOOLEAN';
    FB_DEC16, FB_DEC34: Result := 'DECFLOAT';
    FB_INT128: Result := 'INT128';
    FB_DOUBLE: Result := 'DOUBLE PRECISION';
    FB_TIMESTAMP, FB_TIMESTAMP_TZ: Result := 'TIMESTAMP';
    FB_VARCHAR, FB_CSTRING: Result := 'VARCHAR';
    FB_BLOB: Result := if pSubType = SUBTYPE_ONE then 'BLOB SUB_TYPE TEXT' else 'BLOB';
  else
    Result := '';
  end;
  if (pScale < 0) and (Result <> '') then
    Result := 'NUMERIC';
end;

{ The field's own value, else its domain's, else pNone. }
function OwnOr(pQuery: TFDQuery; pOwn, pDomain, pNone: Integer): Integer;
begin
  if not pQuery.Fields[pOwn].IsNull then
    Result := pQuery.Fields[pOwn].AsInteger
  else if not pQuery.Fields[pDomain].IsNull then
    Result := pQuery.Fields[pDomain].AsInteger
  else
    Result := pNone;
end;

function FactOf(pQuery: TFDQuery; pGenerators: TDictionary<string, Boolean>): TSchemaColumn;
var
  VType, VSubType, VScale: Integer;
  VName: string;
begin
  Result := Default(TSchemaColumn);
  Result.Table := UpperCase(Trim(pQuery.Fields[C_TABLE].AsString));
  Result.Column := UpperCase(Trim(pQuery.Fields[C_FIELD].AsString));
  Result.CharLength := OwnOr(pQuery, C_CHARS, C_DOM_CHARS, CHAR_LENGTH_UNKNOWN);
  VType := OwnOr(pQuery, C_TYPE, C_DOM_TYPE, 0);
  VSubType := OwnOr(pQuery, C_SUBTYPE, C_DOM_SUBTYPE, 0);
  VScale := OwnOr(pQuery, C_SCALE, C_DOM_SCALE, 0);
  Result.Group := GroupOf(VType, VSubType);
  Result.TypeText := TypeName(VType, VSubType, VScale);
  if (Result.Group = scgText) and (Result.CharLength > 0) then
    Result.TypeText := Format('%s(%d)', [Result.TypeText, Result.CharLength]);
  Result.Calculated := pQuery.Fields[C_CALC].AsBoolean or pQuery.Fields[C_LOOKUP].AsBoolean or
    ((not pQuery.Fields[C_KIND].IsNull) and (pQuery.Fields[C_KIND].AsInteger > FIELD_KIND_COLUMN));
  Result.NotNull := (pQuery.Fields[C_NULL].AsInteger = 1) or (pQuery.Fields[C_DOM_NULL].AsInteger = 1);
  Result.Filled := (not pQuery.Fields[C_DEFAULT].IsNull) or (Trim(pQuery.Fields[C_DOM_DEFAULT].AsString) <> '') or
    pQuery.Fields[C_TRIGGERED].AsBoolean or (Trim(pQuery.Fields[C_SEQUENCE].AsString) <> '') or
    (pQuery.Fields[C_PRIMARY].AsBoolean and (Result.Group = scgNumber));
  if not Result.Filled then
    for VName in pGenerators.Keys do
      if VName.Contains(Result.Table) and VName.EndsWith(Result.Column) then
        Result.Filled := True;
end;

{ ---- TSchemaFacts ---- }

constructor TSchemaFacts.Create(pRepo: TFDConnection);
begin
  inherited Create;
  FColumns := TList<TSchemaColumn>.Create;
  FByKey := TDictionary<string, Integer>.Create;
  FByTable := TObjectDictionary<string, TList<Integer>>.Create([doOwnsValues]);
  FByName := TObjectDictionary<string, TList<Integer>>.Create([doOwnsValues]);
  FRead := TDictionary<string, Boolean>.Create;
  FInfo := SchemaInfo(pRepo);
  FExceptions := LoadExceptions(pRepo);
  LoadColumns(pRepo);
end;

destructor TSchemaFacts.Destroy;
begin
  FRead.Free;
  FByName.Free;
  FByTable.Free;
  FByKey.Free;
  FColumns.Free;
  inherited;
end;

procedure TSchemaFacts.Add(const pFact: TSchemaColumn);
var
  VIndex: Integer;
  VList: TList<Integer>;
begin
  VIndex := FColumns.Add(pFact);
  FByKey.AddOrSetValue(KeyOf(pFact.Table, pFact.Column), VIndex);
  if not FByTable.TryGetValue(pFact.Table, VList) then
  begin
    VList := TList<Integer>.Create;
    FByTable.Add(pFact.Table, VList);
  end;
  VList.Add(VIndex);
  if not FByName.TryGetValue(pFact.Column, VList) then
  begin
    VList := TList<Integer>.Create;
    FByName.Add(pFact.Column, VList);
  end;
  VList.Add(VIndex);
end;

procedure TSchemaFacts.LoadColumns(pRepo: TFDConnection);
var
  VQuery: TFDQuery;
  VGenerators: TDictionary<string, Boolean>;
  VFact: TSchemaColumn;
begin
  VGenerators := TDictionary<string, Boolean>.Create;
  VQuery := TFDQuery.Create(nil);
  try
    VQuery.Connection := pRepo;
    VQuery.Open(SQL_GENERATORS);
    while not VQuery.Eof do
    begin
      VGenerators.AddOrSetValue(UpperCase(Trim(VQuery.Fields[0].AsString)), True);
      VQuery.Next;
    end;
    VQuery.Open(SQL_COLUMNS);
    while not VQuery.Eof do
    begin
      VFact := FactOf(VQuery, VGenerators);
      Add(VFact);
      if (not VFact.Calculated) and (not VQuery.Fields[C_TYPE].IsNull) then
        FRead.AddOrSetValue(VFact.Table, True);
      VQuery.Next;
    end;
  finally
    VQuery.Free;
    VGenerators.Free;
  end;
end;

function TSchemaFacts.Info: TSchemaInfo;
begin
  Result := FInfo;
end;

function TSchemaFacts.KnowsTable(const pTable: string): Boolean;
begin
  Result := FRead.ContainsKey(UpperCase(pTable));
end;

function TSchemaFacts.FindColumn(const pTable, pColumn: string; out pFact: TSchemaColumn): Boolean;
var
  VIndex: Integer;
begin
  pFact := Default(TSchemaColumn);
  Result := FByKey.TryGetValue(KeyOf(pTable, pColumn), VIndex);
  if Result then
    pFact := FColumns[VIndex];
end;

function TSchemaFacts.Pick(pMap: TObjectDictionary<string, TList<Integer>>; const pKey: string): TArray<TSchemaColumn>;
var
  VList: TList<Integer>;
  VIndex: Integer;
begin
  Result := nil;
  if pMap.TryGetValue(UpperCase(pKey), VList) then
    for VIndex in VList do
      Result := Result + [FColumns[VIndex]];
end;

function TSchemaFacts.ColumnsOf(const pTable: string): TArray<TSchemaColumn>;
begin
  Result := Pick(FByTable, pTable);
end;

function TSchemaFacts.ColumnsNamed(const pColumn: string): TArray<TSchemaColumn>;
begin
  Result := Pick(FByName, pColumn);
end;

function TSchemaFacts.Excepted(const pFinding: TFrFinding): Boolean;
begin
  Result := IsExcepted(FExceptions, pFinding);
end;

function LoadSchemaFacts(pRepo: TFDConnection): ISchemaFacts;
begin
  Result := nil;
  if HasSchema(pRepo) then
    Result := TSchemaFacts.Create(pRepo);
end;

end.