unit DRagLint.FieldRepo.DbProviderFb;

{ drag-lint 1.54 -- lane TT-ALTER: the Firebird dialect (pure SQL text) and the Firebird provider (FireDAC) behind
  IFrDbDialect / IFrDbProvider. Measured on Firebird 4.0.6 (plan 2026-11-23-fr-alter-table.md). }

interface

uses
  DRagLint.FieldRepo.DbProvider;

/// <summary>The Firebird SQL text generator (dialect 3, quoted identifiers).</summary>
/// <returns>A stateless dialect.</returns>
function FirebirdDialect: IFrDbDialect;

/// <summary>Opens a Firebird connection for planning and (through DRagLint.FieldRepo.AlterApply) applying.</summary>
/// <param name="pConnection">FireDAC-style 'Database=..;User_Name=..;Password=..'.</param>
/// <returns>An open provider; it closes with its last reference.</returns>
/// <exception cref="EFbConnStringError">The string names OpenMode, CreateDatabase, DropDatabase or a connection definition, or holds a line break (DRagLint.Sql.FbConnString).</exception>
/// <exception cref="EFrDbProviderError">The string names another driver than FB (it could create a file), or the database is
/// SQL dialect 1.</exception>
/// <remarks>One attachment. Reads run in read-only transactions; nothing is written before BeginWrite. A write transaction
/// with a reserved table is READ COMMITTED, so it sees all that was committed before it got the lock; the others are SNAPSHOT.
/// Not thread-safe.</remarks>
function OpenFirebirdProvider(const pConnection: string): IFrDbProvider;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  Data.DB,
  FireDAC.Stan.Option,
  FireDAC.Comp.Client,
  DRagLint.Sql.FbConnString,
  DRagLint.FieldRepo.FbImport;

const
  FB_SMALLINT = 7;
  FB_INTEGER = 8;
  FB_FLOAT = 10;
  FB_DATE = 12;
  FB_TIME = 13;
  FB_CHAR = 14;
  FB_BIGINT = 16;
  FB_BOOLEAN = 23;
  FB_DEC16 = 24;
  FB_DEC34 = 25;
  FB_INT128 = 26;
  FB_DOUBLE = 27;
  FB_TIME_TZ = 28;
  FB_TIMESTAMP_TZ = 29;
  FB_TIMESTAMP = 35;
  FB_VARCHAR = 37;
  FB_BLOB = 261;
  SUB_DECIMAL = 2;
  SUB_OCTETS = 1;
  FB_MAX_IDENTIFIER = 63;
  PRECISION_SMALLINT = 4;
  PRECISION_INTEGER = 9;
  PRECISION_BIGINT = 18;
  PRECISION_INT128 = 38;
  SQL_DIALECT_3 = 3;

type
  TFrFirebirdDialect = class(TInterfacedObject, IFrDbDialect)
  private
    function Cast(const pExpr: string; const pType: TFrTypeFacts): string;
    function LossTest(const pOldExpr, pNewExpr: string; const pOld, pNew: TFrTypeFacts): string;
  public
    function Name: string;
    function Capabilities: TFrDbCapabilities;
    function MaxIdentifier: Integer;
    function QuoteIdent(const pName: string): string;
    function TypeClause(const pType: TFrTypeFacts; pWithCharset: Boolean): string;
    function CreateDomain(const pDomain: TFrDomainFacts): string;
    function AddColumn(const pTable, pColumn, pDefinition: string): string;
    function DropColumn(const pTable, pColumn: string): string;
    function RenameColumn(const pTable, pOld, pNew: string): string;
    function AlterType(const pTable, pColumn, pTypeText: string): string;
    function SetNotNull(const pTable, pColumn: string; pNotNull: Boolean): string;
    function SetDefault(const pTable, pColumn, pDefaultSource: string): string;
    function SetPosition(const pTable, pColumn: string; pPosition: Integer): string;
    function CommentColumn(const pTable, pColumn, pText: string): string;
    function CopyColumn(const pTable, pFrom, pTo: string; const pType: TFrTypeFacts): string;
    function CountRows(const pTable: string): string;
    function CountNulls(const pTable, pColumn: string): string;
    function CountValues(const pTable, pColumn: string): string;
    function CountCastFailures(const pTable, pColumn: string; const pNew: TFrTypeFacts): string;
    function CountLosses(const pTable, pColumn: string; const pOld, pNew: TFrTypeFacts): string;
    function CountMismatches(const pTable, pFrom, pCopy: string; const pOld, pNew: TFrTypeFacts): string;
  end;

  TFrFirebirdProvider = class(TInterfacedObject, IFrDbProvider)  // dl:ok high-response@b1d3 -- REVIEWED 2026-11-23 TT-ALTER: one provider = one attachment; its RDB$ readers share it
  private
    FConn: TFDConnection;
    FRead: TFDTransaction;
    FWrite: TFDTransaction;
    FDialect: IFrDbDialect;
    FDatabase: string;
    FSession: string;
    function OpenRead(const pSql: string; const pParams: array of Variant): TFDQuery;
    procedure EndRead;
    function ScalarIn(pTx: TFDTransaction; const pSql: string): Int64;
    procedure PrepareQuery(pQuery: TFDQuery; pTx: TFDTransaction);
    function ReadColumns(const pTable: string): TArray<TFrColumnFacts>;
    function ReadDomains: TArray<TFrDomainFacts>;
    function ReadKeys(const pTable: string): TArray<TFrKeyFacts>;
    function ReadDependencies(const pTable: string): TArray<TFrDependency>;
    function ReadUpdateTriggers(const pTable: string): TArray<string>;
    function MaxIndexKey: Integer;
    function RelationKind(const pTable: string; out pReason: string): Boolean;
  public
    constructor Create(const pConnection: string);
    destructor Destroy; override;
    function Dialect: IFrDbDialect;
    function DatabaseName: string;
    function SessionId: string;
    function ReadTable(const pTable: string): TFrTableFacts;
    function ReadScalar(const pSql: string): Int64;
    procedure BeginWrite(const pLockTable: string);
    procedure Execute(const pSql: string);
    function WriteScalar(const pSql: string): Int64;
    procedure Commit;
    procedure Rollback;
  end;

function IsChar(const pType: TFrTypeFacts): Boolean;
begin
  Result := (pType.FieldType = FB_CHAR) or (pType.FieldType = FB_VARCHAR);
end;

function IsNumeric(const pType: TFrTypeFacts): Boolean;
begin
  Result := pType.FieldType in [FB_SMALLINT, FB_INTEGER, FB_FLOAT, FB_BIGINT, FB_DEC16, FB_DEC34, FB_INT128, FB_DOUBLE];
end;

function QuoteText(const pText: string): string;
begin
  Result := '''' + StringReplace(pText, '''', '''''', [rfReplaceAll]) + '''';
end;

{ TFrFirebirdDialect }

function TFrFirebirdDialect.Name: string;
begin
  Result := 'Firebird';
end;

function TFrFirebirdDialect.Capabilities: TFrDbCapabilities;
begin
  Result := [fdcSetNotNull, fdcColumnPosition, fdcSafePath];
end;

function TFrFirebirdDialect.MaxIdentifier: Integer;
begin
  Result := FB_MAX_IDENTIFIER;
end;

function TFrFirebirdDialect.QuoteIdent(const pName: string): string;
begin
  Result := '"' + StringReplace(pName, '"', '""', [rfReplaceAll]) + '"';
end;

function ExactNumber(const pType: TFrTypeFacts; pMaxPrecision: Integer; const pPlain: string): string;
var
  VPrecision: Integer;
begin
  if (pType.Scale = 0) and (pType.SubType = 0) then
    Exit(pPlain);
  VPrecision := if pType.Precision > 0 then pType.Precision else pMaxPrecision;
  Result := Format('%s(%d,%d)', [if pType.SubType = SUB_DECIMAL then 'DECIMAL' else 'NUMERIC', VPrecision, -pType.Scale]);
end;

{ '' counts as plain (no name given) }
function IsPlainName(const pName: string): Boolean;
var
  VChar: Char;
begin
  Result := True;
  for VChar in pName do
    Result := Result and CharInSet(VChar, ['A'..'Z', 'a'..'z', '0'..'9', '_', '$']);
end;

function CharClause(const pType: TFrTypeFacts; pWithCharset: Boolean): string;
var
  VLength: Integer;
begin
  Result := '';
  VLength := if pType.CharLength > 0 then pType.CharLength else pType.ByteLength;
  { the character set of a repository domain goes into DDL as it is: anything but a plain name is refused }
  if (VLength <= 0) or (pWithCharset and not IsPlainName(pType.Charset)) then
    Exit;
  Result := Format('%s(%d)', [if pType.FieldType = FB_CHAR then 'CHAR' else 'VARCHAR', VLength]);
  if pType.SubType = SUB_OCTETS then
    Result := Result + ' CHARACTER SET OCTETS'
  else if pWithCharset and (pType.Charset <> '') then
    Result := Result + ' CHARACTER SET ' + pType.Charset;
end;

function TFrFirebirdDialect.TypeClause(const pType: TFrTypeFacts; pWithCharset: Boolean): string;
begin
  Result := '';
  case pType.FieldType of
    FB_SMALLINT: Result := ExactNumber(pType, PRECISION_SMALLINT, 'SMALLINT');
    FB_INTEGER: Result := ExactNumber(pType, PRECISION_INTEGER, 'INTEGER');
    FB_BIGINT: Result := ExactNumber(pType, PRECISION_BIGINT, 'BIGINT');
    FB_INT128: Result := ExactNumber(pType, PRECISION_INT128, 'INT128');
    FB_FLOAT: Result := 'FLOAT';
    FB_DOUBLE: Result := if pType.Scale = 0 then 'DOUBLE PRECISION' else '';
    FB_DEC16: Result := 'DECFLOAT(16)';
    FB_DEC34: Result := 'DECFLOAT(34)';
    FB_DATE: Result := 'DATE';
    FB_TIME: Result := 'TIME';
    FB_TIMESTAMP: Result := 'TIMESTAMP';
    FB_TIME_TZ: Result := 'TIME WITH TIME ZONE';
    FB_TIMESTAMP_TZ: Result := 'TIMESTAMP WITH TIME ZONE';
    FB_BOOLEAN: Result := 'BOOLEAN';
    FB_BLOB: Result := 'BLOB SUB_TYPE ' + IntToStr(pType.SubType);
    FB_CHAR, FB_VARCHAR: Result := CharClause(pType, pWithCharset);
  end;
end;

function TFrFirebirdDialect.CreateDomain(const pDomain: TFrDomainFacts): string;
begin
  Result := 'CREATE DOMAIN ' + QuoteIdent(pDomain.Name) + ' AS ' + TypeClause(pDomain.DataType, True);
  if pDomain.DefaultSource <> '' then
    Result := Result + ' ' + Trim(pDomain.DefaultSource);
  if pDomain.NotNull then
    Result := Result + ' NOT NULL';
  if pDomain.CheckSource <> '' then
    Result := Result + ' ' + Trim(pDomain.CheckSource);
end;

function TFrFirebirdDialect.AddColumn(const pTable, pColumn, pDefinition: string): string;
begin
  Result := Format('ALTER TABLE %s ADD %s %s', [QuoteIdent(pTable), QuoteIdent(pColumn), pDefinition]);
end;

function TFrFirebirdDialect.DropColumn(const pTable, pColumn: string): string;
begin
  Result := Format('ALTER TABLE %s DROP %s', [QuoteIdent(pTable), QuoteIdent(pColumn)]);
end;

function TFrFirebirdDialect.RenameColumn(const pTable, pOld, pNew: string): string;
begin
  Result := Format('ALTER TABLE %s ALTER COLUMN %s TO %s', [QuoteIdent(pTable), QuoteIdent(pOld), QuoteIdent(pNew)]);
end;

function TFrFirebirdDialect.AlterType(const pTable, pColumn, pTypeText: string): string;
begin
  Result := Format('ALTER TABLE %s ALTER COLUMN %s TYPE %s', [QuoteIdent(pTable), QuoteIdent(pColumn), pTypeText]);
end;

function TFrFirebirdDialect.SetNotNull(const pTable, pColumn: string; pNotNull: Boolean): string;
begin
  Result := Format('ALTER TABLE %s ALTER COLUMN %s %s NOT NULL',
    [QuoteIdent(pTable), QuoteIdent(pColumn), if pNotNull then 'SET' else 'DROP']);
end;

function TFrFirebirdDialect.SetDefault(const pTable, pColumn, pDefaultSource: string): string;
begin
  Result := Format('ALTER TABLE %s ALTER COLUMN %s SET %s', [QuoteIdent(pTable), QuoteIdent(pColumn), Trim(pDefaultSource)]);
end;

function TFrFirebirdDialect.SetPosition(const pTable, pColumn: string; pPosition: Integer): string;
begin
  Result := Format('ALTER TABLE %s ALTER COLUMN %s POSITION %d', [QuoteIdent(pTable), QuoteIdent(pColumn), pPosition]);
end;

function TFrFirebirdDialect.CommentColumn(const pTable, pColumn, pText: string): string;
begin
  Result := Format('COMMENT ON COLUMN %s.%s IS %s', [QuoteIdent(pTable), QuoteIdent(pColumn), QuoteText(pText)]);
end;

function TFrFirebirdDialect.Cast(const pExpr: string; const pType: TFrTypeFacts): string;
begin
  Result := Format('CAST(%s AS %s)', [pExpr, TypeClause(pType, True)]);
end;

function TFrFirebirdDialect.CopyColumn(const pTable, pFrom, pTo: string; const pType: TFrTypeFacts): string;
begin
  Result := Format('UPDATE %s SET %s = %s', [QuoteIdent(pTable), QuoteIdent(pTo), Cast(QuoteIdent(pFrom), pType)]);
end;

function TFrFirebirdDialect.CountRows(const pTable: string): string;
begin
  Result := 'SELECT COUNT(*) FROM ' + QuoteIdent(pTable);
end;

function TFrFirebirdDialect.CountNulls(const pTable, pColumn: string): string;
begin
  Result := Format('SELECT COUNT(*) FROM %s WHERE %s IS NULL', [QuoteIdent(pTable), QuoteIdent(pColumn)]);
end;

function TFrFirebirdDialect.CountValues(const pTable, pColumn: string): string;
begin
  Result := Format('SELECT COUNT(%s) FROM %s', [QuoteIdent(pColumn), QuoteIdent(pTable)]);
end;

{ The condition "the new value is not the old value", for a CAST that succeeded. Text to number also counts leading zeros
  (007), text to date the words that mean another value tomorrow. }
function TFrFirebirdDialect.LossTest(const pOldExpr, pNewExpr: string; const pOld, pNew: TFrTypeFacts): string;
begin
  if IsChar(pOld) and IsChar(pNew) then
    Exit(Format('(%0:s IS DISTINCT FROM %1:s OR CHAR_LENGTH(%0:s) IS DISTINCT FROM CHAR_LENGTH(%1:s))',
      [pOldExpr, pNewExpr]));
  if IsChar(pOld) and IsNumeric(pNew) then
    Exit(Format('(CAST(%0:s AS DECFLOAT(34)) IS DISTINCT FROM CAST(%1:s AS DECFLOAT(34)) OR ' +
      'TRIM(REPLACE(REPLACE(%0:s, ''-'', ''''), ''+'', '''')) SIMILAR TO ''0[0-9]%%'')', [pOldExpr, pNewExpr]));
  if IsChar(pOld) then
    Exit(Format('(UPPER(TRIM(%s)) IN (''NOW'', ''TODAY'', ''TOMORROW'', ''YESTERDAY''))', [pOldExpr]));
  Result := Format('(%s IS DISTINCT FROM %s)', [pOldExpr, Cast(pNewExpr, pOld)]);
end;

function TFrFirebirdDialect.CountCastFailures(const pTable, pColumn: string; const pNew: TFrTypeFacts): string;
begin
  Result := Format('EXECUTE BLOCK RETURNS (N BIGINT) AS DECLARE S TYPE OF COLUMN %0:s.%1:s; DECLARE V %2:s; BEGIN ' +
    'N = 0; FOR SELECT %1:s FROM %0:s INTO :S DO BEGIN V = %3:s; WHEN ANY DO N = N + 1; END SUSPEND; END',
    [QuoteIdent(pTable), QuoteIdent(pColumn), TypeClause(pNew, True), Cast(':S', pNew)]);
end;

{ K = 1: the cast succeeded; a value whose comparison then fails counts as changed. Cast failures are CountCastFailures' }
function TFrFirebirdDialect.CountLosses(const pTable, pColumn: string; const pOld, pNew: TFrTypeFacts): string;
begin
  Result := Format('EXECUTE BLOCK RETURNS (N BIGINT) AS DECLARE S TYPE OF COLUMN %0:s.%1:s; DECLARE V %2:s; DECLARE K SMALLINT; BEGIN ' +
    'N = 0; FOR SELECT %1:s FROM %0:s INTO :S DO BEGIN K = 0; V = %3:s; K = 1; IF (%4:s) THEN N = N + 1; ' +
    'WHEN ANY DO IF (K = 1) THEN N = N + 1; END SUSPEND; END', [QuoteIdent(pTable), QuoteIdent(pColumn), TypeClause(pNew, True),
    Cast(':S', pNew), LossTest(':S', ':V', pOld, pNew)]);
end;

function TFrFirebirdDialect.CountMismatches(const pTable, pFrom, pCopy: string; const pOld, pNew: TFrTypeFacts): string;
begin
  Result := Format('SELECT COUNT(*) FROM %s WHERE %s IS DISTINCT FROM %s OR %s', [QuoteIdent(pTable),
    Cast(QuoteIdent(pFrom), pNew), QuoteIdent(pCopy), LossTest(QuoteIdent(pFrom), QuoteIdent(pCopy), pOld, pNew)]);
end;

{ TFrFirebirdProvider }

procedure SetManual(pTx: TFDTransaction; pReadOnly: Boolean);
begin
  pTx.Options.ReadOnly := pReadOnly;
  pTx.Options.AutoStart := False;
  pTx.Options.AutoStop := False;
  pTx.Options.AutoCommit := False;
  pTx.Options.Isolation := xiSnapshot;
  pTx.Options.DisconnectAction := xdRollback;
end;

{ Another FireDAC driver would open, and some create, whatever Database names. }
procedure RequireFbDriver(const pConnection: string);
const
  KEY_DRIVER = 'DriverID';
  DRIVER_FB = 'FB';
var
  VPair, VValue: string;
begin
  for VPair in pConnection.Split([';'], TStringSplitOptions.ExcludeEmpty) do
    if SameText(Trim(Copy(VPair, 1, Pos('=', VPair + '=') - 1)), KEY_DRIVER) then
    begin
      VValue := Trim(Copy(VPair, Pos('=', VPair + '=') + 1, MaxInt));
      if not SameText(VValue, DRIVER_FB) then
        raise EFrDbProviderError.CreateFmt('%s=%s is not allowed in --connection: only %s is', [KEY_DRIVER, VValue, DRIVER_FB]);
    end;
end;

constructor TFrFirebirdProvider.Create(const pConnection: string);
begin
  inherited Create;
  RequireFbConnectionSafe(pConnection);
  RequireFbDriver(pConnection);
  FDialect := FirebirdDialect;
  FSession := TGUID.NewGuid.ToString;
  FConn := OpenSourceConnection(pConnection, FDatabase);
  FRead := TFDTransaction.Create(nil);
  FRead.Connection := FConn;
  SetManual(FRead, True);
  FWrite := TFDTransaction.Create(nil);
  FWrite.Connection := FConn;
  SetManual(FWrite, False);
  if ReadScalar('SELECT MON$SQL_DIALECT FROM MON$DATABASE') <> SQL_DIALECT_3 then
    raise EFrDbProviderError.Create('the database is not SQL dialect 3');
end;

destructor TFrFirebirdProvider.Destroy;
begin
  try
    if (FWrite <> nil) and FWrite.Active then
      FWrite.Rollback;
  finally
    FreeAndNil(FWrite);
    FreeAndNil(FRead);
    FreeAndNil(FConn);
  end;
  inherited Destroy;
end;

function TFrFirebirdProvider.Dialect: IFrDbDialect;
begin
  Result := FDialect;
end;

function TFrFirebirdProvider.DatabaseName: string;
begin
  Result := FDatabase;
end;

function TFrFirebirdProvider.SessionId: string;
begin
  Result := FSession;
end;

{ The SQL goes to the server as it is: no macro, escape or parameter expansion of a CHECK or COMMENT text. }
procedure TFrFirebirdProvider.PrepareQuery(pQuery: TFDQuery; pTx: TFDTransaction);
begin
  pQuery.Connection := FConn;
  pQuery.Transaction := pTx;
  pQuery.UpdateTransaction := pTx;
  pQuery.ResourceOptions.MacroCreate := False;
  pQuery.ResourceOptions.MacroExpand := False;
  pQuery.ResourceOptions.EscapeExpand := False;
  pQuery.ResourceOptions.ParamCreate := False;
  pQuery.ResourceOptions.ParamExpand := False;
end;

function TFrFirebirdProvider.OpenRead(const pSql: string; const pParams: array of Variant): TFDQuery;
begin
  if not FRead.Active then
    FRead.StartTransaction;
  Result := TFDQuery.Create(nil);
  try
    Result.Connection := FConn;
    Result.Transaction := FRead;
    Result.Open(pSql, pParams);  // dl:ok dataset-open-without-close@1d69 -- REVIEWED 2026-11-23 TT-ALTER: the open dataset IS the result; every caller frees it in a finally, the exception path frees it here
  except
    Result.Free;
    raise;
  end;
end;

procedure TFrFirebirdProvider.EndRead;
begin
  if FRead.Active then
    FRead.Rollback;
end;

function TFrFirebirdProvider.ScalarIn(pTx: TFDTransaction; const pSql: string): Int64;
var
  VQuery: TFDQuery;
begin
  VQuery := TFDQuery.Create(nil);
  try
    PrepareQuery(VQuery, pTx);
    VQuery.Open(pSql);
    { a check without an answer must not read as "0 problems" }
    if VQuery.Eof or VQuery.Fields[0].IsNull then
      raise EFrDbProviderError.Create('the query returned no value: ' + pSql);
    Result := VQuery.Fields[0].AsLargeInt;
  finally
    VQuery.Free;
  end;
end;

function TFrFirebirdProvider.ReadScalar(const pSql: string): Int64;
begin
  if not FRead.Active then
    FRead.StartTransaction;
  try
    Result := ScalarIn(FRead, pSql);
  finally
    EndRead;
  end;
end;

function TFrFirebirdProvider.RelationKind(const pTable: string; out pReason: string): Boolean;
var
  VQuery: TFDQuery;
begin
  pReason := '';
  VQuery := OpenRead('SELECT CASE WHEN RDB$VIEW_BLR IS NOT NULL THEN ''a view'' ' +
    'WHEN COALESCE(RDB$SYSTEM_FLAG, 0) <> 0 THEN ''a system table'' ' +
    'WHEN RDB$EXTERNAL_FILE IS NOT NULL THEN ''an external table'' ' +
    'WHEN COALESCE(RDB$RELATION_TYPE, 0) <> 0 THEN ''not a persistent table'' ELSE '''' END ' +
    'FROM RDB$RELATIONS WHERE RDB$RELATION_NAME = :T', [pTable]);
  try
    Result := not VQuery.Eof;
    if Result then
      pReason := Trim(VQuery.Fields[0].AsString);
  finally
    VQuery.Free;
  end;
end;

{ Field order of the column and the domain query: name, type, sub type, byte length, chars, scale, precision, charset. }
procedure ReadTypeFields(pQuery: TFDQuery; pFirst: Integer; out pType: TFrTypeFacts);
const
  F_SUB = 1;
  F_LENGTH = 2;
  F_CHARS = 3;
  F_SCALE = 4;
  F_PRECISION = 5;
  F_CHARSET = 6;
begin
  pType := Default(TFrTypeFacts);
  pType.FieldType := pQuery.Fields[pFirst].AsInteger;
  pType.SubType := pQuery.Fields[pFirst + F_SUB].AsInteger;
  pType.ByteLength := pQuery.Fields[pFirst + F_LENGTH].AsInteger;
  pType.CharLength := pQuery.Fields[pFirst + F_CHARS].AsInteger;
  pType.Scale := pQuery.Fields[pFirst + F_SCALE].AsInteger;
  pType.Precision := pQuery.Fields[pFirst + F_PRECISION].AsInteger;
  pType.Charset := Trim(pQuery.Fields[pFirst + F_CHARSET].AsString);
end;

const
  SQL_TYPE_COLUMNS =
    'L.RDB$FIELD_TYPE, COALESCE(L.RDB$FIELD_SUB_TYPE, 0), L.RDB$FIELD_LENGTH, COALESCE(L.RDB$CHARACTER_LENGTH, 0), ' +
    'COALESCE(L.RDB$FIELD_SCALE, 0), COALESCE(L.RDB$FIELD_PRECISION, 0), TRIM(CS.RDB$CHARACTER_SET_NAME), ';
  SQL_JOIN_CHARSET = 'LEFT JOIN RDB$CHARACTER_SETS CS ON CS.RDB$CHARACTER_SET_ID = L.RDB$CHARACTER_SET_ID ';

function TFrFirebirdProvider.ReadColumns(const pTable: string): TArray<TFrColumnFacts>;
const
  F_NAME = 0;
  F_DOMAIN = 1;
  F_TYPE = 2;
  F_NN = 9;
  F_DOMAIN_NN = 10;
  F_DEFAULT = 11;
  F_COMPUTED = 12;
  F_IDENTITY = 13;
  F_DESCRIPTION = 14;
  F_COLLATION = 15;
  F_GRANTS = 16;
  SQL =
    'SELECT TRIM(RF.RDB$FIELD_NAME), ' +
    'CASE WHEN RF.RDB$FIELD_SOURCE STARTING WITH ''RDB$'' THEN '''' ELSE TRIM(RF.RDB$FIELD_SOURCE) END, ' +
    SQL_TYPE_COLUMNS +
    'COALESCE(RF.RDB$NULL_FLAG, 0), COALESCE(L.RDB$NULL_FLAG, 0), RF.RDB$DEFAULT_SOURCE, L.RDB$COMPUTED_SOURCE, ' +
    'RF.RDB$IDENTITY_TYPE, RF.RDB$DESCRIPTION, ' +
    'CASE WHEN CO.RDB$COLLATION_NAME = CS.RDB$DEFAULT_COLLATE_NAME THEN '''' ELSE TRIM(CO.RDB$COLLATION_NAME) END, ' +
    '(SELECT COUNT(*) FROM RDB$USER_PRIVILEGES P WHERE P.RDB$RELATION_NAME = RF.RDB$RELATION_NAME ' +
    'AND P.RDB$FIELD_NAME = RF.RDB$FIELD_NAME) ' +
    'FROM RDB$RELATION_FIELDS RF JOIN RDB$FIELDS L ON L.RDB$FIELD_NAME = RF.RDB$FIELD_SOURCE ' + SQL_JOIN_CHARSET +
    'LEFT JOIN RDB$COLLATIONS CO ON CO.RDB$CHARACTER_SET_ID = L.RDB$CHARACTER_SET_ID ' +
    'AND CO.RDB$COLLATION_ID = COALESCE(RF.RDB$COLLATION_ID, L.RDB$COLLATION_ID) ' +
    'WHERE RF.RDB$RELATION_NAME = :T ORDER BY RF.RDB$FIELD_POSITION, RF.RDB$FIELD_NAME';
var
  VQuery: TFDQuery;
  VItem: TFrColumnFacts;
begin
  Result := nil;
  VQuery := OpenRead(SQL, [pTable]);
  try
    while not VQuery.Eof do
    begin
      VItem := Default(TFrColumnFacts);
      VItem.Name := VQuery.Fields[F_NAME].AsString;
      VItem.Position := Length(Result);
      VItem.DomainName := Trim(VQuery.Fields[F_DOMAIN].AsString);
      ReadTypeFields(VQuery, F_TYPE, VItem.DataType);
      VItem.DataType.Collation := Trim(VQuery.Fields[F_COLLATION].AsString);
      VItem.ColumnNotNull := VQuery.Fields[F_NN].AsInteger <> 0;
      VItem.DomainNotNull := VQuery.Fields[F_DOMAIN_NN].AsInteger <> 0;
      VItem.DefaultSource := Trim(VQuery.Fields[F_DEFAULT].AsString);
      VItem.ComputedSource := Trim(VQuery.Fields[F_COMPUTED].AsString);
      VItem.IsIdentity := not VQuery.Fields[F_IDENTITY].IsNull;
      VItem.Description := VQuery.Fields[F_DESCRIPTION].AsString;
      VItem.HasColumnGrants := VQuery.Fields[F_GRANTS].AsInteger > 0;
      Result := Result + [VItem];
      VQuery.Next;
    end;
  finally
    VQuery.Free;
  end;
end;

function TFrFirebirdProvider.ReadDomains: TArray<TFrDomainFacts>;
const
  F_NAME = 0;
  F_TYPE = 1;
  F_NN = 8;
  F_DEFAULT = 9;
  F_CHECK = 10;
  SQL =
    'SELECT TRIM(L.RDB$FIELD_NAME), ' + SQL_TYPE_COLUMNS +
    'COALESCE(L.RDB$NULL_FLAG, 0), L.RDB$DEFAULT_SOURCE, L.RDB$VALIDATION_SOURCE FROM RDB$FIELDS L ' + SQL_JOIN_CHARSET +
    'WHERE L.RDB$FIELD_NAME NOT STARTING WITH ''RDB$'' AND COALESCE(L.RDB$SYSTEM_FLAG, 0) = 0 ORDER BY 1';
var
  VQuery: TFDQuery;
  VItem: TFrDomainFacts;
begin
  Result := nil;
  VQuery := OpenRead(SQL, []);
  try
    while not VQuery.Eof do
    begin
      VItem := Default(TFrDomainFacts);
      VItem.Name := VQuery.Fields[F_NAME].AsString;
      ReadTypeFields(VQuery, F_TYPE, VItem.DataType);
      VItem.NotNull := VQuery.Fields[F_NN].AsInteger <> 0;
      VItem.DefaultSource := Trim(VQuery.Fields[F_DEFAULT].AsString);
      VItem.CheckSource := Trim(VQuery.Fields[F_CHECK].AsString);
      Result := Result + [VItem];
      VQuery.Next;
    end;
  finally
    VQuery.Free;
  end;
end;

function TFrFirebirdProvider.ReadKeys(const pTable: string): TArray<TFrKeyFacts>;
const
  F_NAME = 0;
  F_KIND = 1;
  F_COLUMN = 2;
  SQL =
    'SELECT TRIM(COALESCE(RC.RDB$CONSTRAINT_NAME, I.RDB$INDEX_NAME)), ' +
    'CASE RC.RDB$CONSTRAINT_TYPE WHEN ''PRIMARY KEY'' THEN ''PK'' WHEN ''UNIQUE'' THEN ''UNIQUE'' ' +
    'WHEN ''FOREIGN KEY'' THEN ''FK'' ELSE ''INDEX'' END, TRIM(SG.RDB$FIELD_NAME) ' +
    'FROM RDB$INDICES I JOIN RDB$INDEX_SEGMENTS SG ON SG.RDB$INDEX_NAME = I.RDB$INDEX_NAME ' +
    'LEFT JOIN RDB$RELATION_CONSTRAINTS RC ON RC.RDB$INDEX_NAME = I.RDB$INDEX_NAME ' +
    'WHERE I.RDB$RELATION_NAME = :T ORDER BY 1, SG.RDB$FIELD_POSITION';
var
  VQuery: TFDQuery;
  VName: string;
  VItem: TFrKeyFacts;
begin
  Result := nil;
  VQuery := OpenRead(SQL, [pTable]);
  try
    VItem := Default(TFrKeyFacts);
    while not VQuery.Eof do
    begin
      VName := VQuery.Fields[F_NAME].AsString;
      if VItem.Name <> VName then
      begin
        if VItem.Name <> '' then
          Result := Result + [VItem];
        VItem := Default(TFrKeyFacts);
        VItem.Name := VName;
        VItem.Kind := Trim(VQuery.Fields[F_KIND].AsString);
      end;
      VItem.Columns := VItem.Columns + [VQuery.Fields[F_COLUMN].AsString];
      VQuery.Next;
    end;
    if VItem.Name <> '' then
      Result := Result + [VItem];
  finally
    VQuery.Free;
  end;
end;

procedure SetDependencyKind(var pItem: TFrDependency; pType: Integer; pIsCheck: Boolean);
const
  DEP_VIEW = 1;
  DEP_TRIGGER = 2;
  DEP_COMPUTED = 3;
  DEP_CHECK = 4;
  DEP_PROCEDURE = 5;
  DEP_INDEX = 6;
  DEP_FUNCTION = 15;
  DEP_PACKAGE = 18;
  DEP_PACKAGE_BODY = 19;
begin
  pItem.Kind := fdkObject;
  if pIsCheck or (pType = DEP_CHECK) then
    pItem.Kind := fdkCheck
  else if pType = DEP_COMPUTED then
    pItem.Kind := fdkComputed
  else if pType = DEP_INDEX then
    pItem.Kind := fdkExpressionIndex;
  case pItem.Kind of
    fdkCheck: pItem.KindText := 'check';
    fdkComputed: pItem.KindText := 'computed column';
    fdkExpressionIndex: pItem.KindText := 'expression index';
  else
    case pType of
      DEP_VIEW: pItem.KindText := 'view';
      DEP_TRIGGER: pItem.KindText := 'trigger';
      DEP_PROCEDURE: pItem.KindText := 'procedure';
      DEP_FUNCTION: pItem.KindText := 'function';
      DEP_PACKAGE, DEP_PACKAGE_BODY: pItem.KindText := 'package';
    else
      pItem.KindText := 'object type ' + IntToStr(pType);
    end;
  end;
end;

function TFrFirebirdProvider.ReadDependencies(const pTable: string): TArray<TFrDependency>;
const
  F_COLUMN = 0;
  F_DEPENDENT = 1;
  F_TYPE = 2;
  F_IS_CHECK = 3;
  SQL =
    { the expression of a VIEW column is recorded like a computed column, under the column's own RDB$ domain: name the view }
    'SELECT DISTINCT TRIM(D.RDB$FIELD_NAME), TRIM(COALESCE(CC.RDB$CONSTRAINT_NAME, V.RDB$RELATION_NAME, D.RDB$DEPENDENT_NAME)), ' +
    'CASE WHEN V.RDB$RELATION_NAME IS NULL THEN D.RDB$DEPENDENT_TYPE ELSE 1 END, ' +
    'CASE WHEN CC.RDB$CONSTRAINT_NAME IS NULL THEN 0 ELSE 1 END ' +
    'FROM RDB$DEPENDENCIES D LEFT JOIN RDB$CHECK_CONSTRAINTS CC ON CC.RDB$TRIGGER_NAME = D.RDB$DEPENDENT_NAME ' +
    'AND D.RDB$DEPENDENT_TYPE = 2 ' +
    'LEFT JOIN RDB$RELATION_FIELDS VF ON VF.RDB$FIELD_SOURCE = D.RDB$DEPENDENT_NAME AND D.RDB$DEPENDENT_TYPE = 3 ' +
    'LEFT JOIN RDB$RELATIONS V ON V.RDB$RELATION_NAME = VF.RDB$RELATION_NAME AND V.RDB$VIEW_BLR IS NOT NULL ' +
    'WHERE D.RDB$DEPENDED_ON_NAME = :T AND D.RDB$DEPENDED_ON_TYPE IN (0, 1) AND D.RDB$FIELD_NAME IS NOT NULL ORDER BY 1, 2';
var
  VQuery: TFDQuery;
  VItem: TFrDependency;
begin
  Result := nil;
  VQuery := OpenRead(SQL, [pTable]);
  try
    while not VQuery.Eof do
    begin
      VItem := Default(TFrDependency);
      VItem.ColumnName := VQuery.Fields[F_COLUMN].AsString;
      VItem.DependentName := VQuery.Fields[F_DEPENDENT].AsString;
      SetDependencyKind(VItem, VQuery.Fields[F_TYPE].AsInteger, VQuery.Fields[F_IS_CHECK].AsInteger = 1);
      Result := Result + [VItem];
      VQuery.Next;
    end;
  finally
    VQuery.Free;
  end;
end;

{ RDB$TRIGGER_TYPE packs up to three events of two bits each after a phase bit: (type + 1) shr 1, slots of 2 bits;
  slot value 2 = UPDATE. }
function FiresOnUpdate(pTriggerType: Integer): Boolean;
const
  SLOT_MASK = 3;
  SLOT_BITS = 2;
  EVENT_UPDATE = 2;
  SLOTS = 3;
var
  VBits, VSlot: Integer;
begin
  Result := False;
  VBits := (pTriggerType + 1) shr 1;
  for VSlot := 1 to SLOTS do
  begin
    if (VBits and SLOT_MASK) = EVENT_UPDATE then
      Exit(True);
    VBits := VBits shr SLOT_BITS;
  end;
end;

function TFrFirebirdProvider.ReadUpdateTriggers(const pTable: string): TArray<string>;
var
  VQuery: TFDQuery;
begin
  Result := nil;
  VQuery := OpenRead('SELECT TRIM(RDB$TRIGGER_NAME), RDB$TRIGGER_TYPE FROM RDB$TRIGGERS WHERE RDB$RELATION_NAME = :T ' +
    'AND COALESCE(RDB$SYSTEM_FLAG, 0) = 0 AND COALESCE(RDB$TRIGGER_INACTIVE, 0) = 0 ORDER BY 1', [pTable]);
  try
    while not VQuery.Eof do
    begin
      if FiresOnUpdate(VQuery.Fields[1].AsInteger) then
        Result := Result + [VQuery.Fields[0].AsString];
      VQuery.Next;
    end;
  finally
    VQuery.Free;
  end;
end;

{ Measured on Firebird 4.0.6 for pages of 4, 8 and 16 KB. }
function TFrFirebirdProvider.MaxIndexKey: Integer;
const
  KEYS_PER_PAGE = 4;
  KEY_OVERHEAD = 9;
var
  VQuery: TFDQuery;
begin
  VQuery := OpenRead('SELECT MON$PAGE_SIZE FROM MON$DATABASE', []);
  try
    Result := VQuery.Fields[0].AsInteger div KEYS_PER_PAGE - KEY_OVERHEAD;
  finally
    VQuery.Free;
  end;
end;

function TFrFirebirdProvider.ReadTable(const pTable: string): TFrTableFacts;
begin
  Result := Default(TFrTableFacts);
  Result.TableName := pTable;
  try
    Result.Exists := RelationKind(pTable, Result.NotPlainTable);
    if Result.Exists then
    begin
      Result.Columns := ReadColumns(pTable);
      Result.Domains := ReadDomains;
      Result.Keys := ReadKeys(pTable);
      Result.Dependencies := ReadDependencies(pTable);
      Result.UpdateTriggers := ReadUpdateTriggers(pTable);
      Result.MaxIndexKey := MaxIndexKey;
    end;
  finally
    EndRead;
  end;
end;

procedure TFrFirebirdProvider.BeginWrite(const pLockTable: string);
begin
  if FWrite.Active then
    raise EFrDbProviderError.Create('a write transaction is already open');
  EndRead;
  FWrite.Options.Params.Clear;
  FWrite.Options.Isolation := xiSnapshot;
  if pLockTable <> '' then
  begin
    FWrite.Options.Isolation := xiReadCommitted;
    FWrite.Options.Params.Add('lock_write=' + pLockTable);
    FWrite.Options.Params.Add('protected');
  end;
  FWrite.StartTransaction;
end;

procedure TFrFirebirdProvider.Execute(const pSql: string);
var
  VQuery: TFDQuery;
begin
  if not FWrite.Active then
    raise EFrDbProviderError.Create('no write transaction');
  VQuery := TFDQuery.Create(nil);
  try
    PrepareQuery(VQuery, FWrite);
    VQuery.ResourceOptions.DirectExecute := True;
    VQuery.SQL.Text := pSql;
    VQuery.ExecSQL;
  finally
    VQuery.Free;
  end;
end;

function TFrFirebirdProvider.WriteScalar(const pSql: string): Int64;
begin
  if not FWrite.Active then
    raise EFrDbProviderError.Create('no write transaction');
  Result := ScalarIn(FWrite, pSql);
end;

procedure TFrFirebirdProvider.Commit;
begin
  if not FWrite.Active then
    raise EFrDbProviderError.Create('no write transaction');
  FWrite.Commit;
end;

procedure TFrFirebirdProvider.Rollback;
begin
  if not FConn.Connected then
    raise EFrDbProviderError.Create('the connection is lost');
  if FWrite.Active then
    FWrite.Rollback;
end;

function FirebirdDialect: IFrDbDialect;
begin
  Result := TFrFirebirdDialect.Create;
end;

function OpenFirebirdProvider(const pConnection: string): IFrDbProvider;
begin
  Result := TFrFirebirdProvider.Create(pConnection);
end;

end.
