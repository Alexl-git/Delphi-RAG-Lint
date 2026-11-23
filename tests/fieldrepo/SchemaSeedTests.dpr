program SchemaSeedTests;

{$APPTYPE CONSOLE}

{ drag-lint 1.52 lane TTS -- console tests for DRagLint.FieldRepo.FbTypes and
  DRagLint.FieldRepo.SchemaSeed. The Firebird system tables are TFDMemTable fixtures;
  no Firebird is needed. Output: one PASS / FAIL line per check, then
  "SUMMARY pass=N fail=M"; exit code 0 only when fail=0. Contract: the DocInsight
  comments of RunSchemaSeed / TryFbFieldAccessor / TryFbFieldVarType. }

uses
  Winapi.Windows,
  System.SysUtils,
  System.Variants,
  System.IOUtils,
  Data.DB,
  FireDAC.Stan.Intf,
  FireDAC.Stan.Option,
  FireDAC.Stan.Error,
  FireDAC.UI.Intf,
  FireDAC.Phys.Intf,
  FireDAC.Stan.Def,
  FireDAC.Stan.Pool,
  FireDAC.Stan.Async,
  FireDAC.Phys,
  FireDAC.Phys.SQLite,
  FireDAC.Phys.SQLiteDef,
  FireDAC.Stan.ExprFuncs,
  FireDAC.ConsoleUI.Wait,
  FireDAC.Stan.Param,
  FireDAC.DatS,
  FireDAC.DApt.Intf,
  FireDAC.DApt,
  FireDAC.Comp.DataSet,
  FireDAC.Comp.Client,
  DRagLint.FieldRepo.Schema in '..\..\src\sql\DRagLint.FieldRepo.Schema.pas',
  DRagLint.FieldRepo.FbTypes in '..\..\src\sql\DRagLint.FieldRepo.FbTypes.pas',
  DRagLint.FieldRepo.SchemaSeed in '..\..\src\sql\DRagLint.FieldRepo.SchemaSeed.pas';

type
  { Fixture switches: each one changes the schema the way a later run would see it. }
  TFixtureOpt = record
    DropOrdersName: Boolean;
    OrdersNameChars: Integer;
    AddNewTable: Boolean;
  end;

var
  GPass: Integer = 0;
  GFail: Integer = 0;
  GDir: string;
  GStamp: TDateTime;

procedure Check(const pName: string; pCond: Boolean; const pDetail: string = '');
begin
  if pCond then
  begin
    Inc(GPass);
    if pDetail = '' then
      Writeln('PASS ', pName)
    else
      Writeln('PASS ', pName, ' (', pDetail, ')');
  end
  else
  begin
    Inc(GFail);
    Writeln('FAIL ', pName, ' ', pDetail);
  end;
end;

function RaisedMessage(pProc: TProc): string;
begin
  Result := '';
  try
    pProc;
  except
    on E: Exception do
      Result := E.ClassName + ': ' + E.Message;
  end;
end;

function DefaultOpt: TFixtureOpt;
begin
  Result := Default(TFixtureOpt);
  Result.OrdersNameChars := 40;
end;

function NewMem(const pNames: array of string; const pTypes: array of TFieldType): TFDMemTable;
var
  i: Integer;
begin
  Result := TFDMemTable.Create(nil);
  for i := 0 to High(pNames) do
    if pTypes[i] = ftString then
      Result.FieldDefs.Add(pNames[i], ftString, 63)
    else
      Result.FieldDefs.Add(pNames[i], pTypes[i]);
  Result.CreateDataSet;
end;

procedure AddField(pMem: TFDMemTable; const pTable, pField: string; pType, pSub, pLen, pChars,
  pNullFlag: Integer; const pDefault: Variant);
begin
  pMem.Append;
  pMem.FieldByName('TABLE_NAME').AsString := pTable;
  pMem.FieldByName('FIELD_NAME').AsString := pField;
  pMem.FieldByName('DEFAULT_SOURCE').Value := pDefault;
  pMem.FieldByName('FIELD_LENGTH').AsInteger := pLen;
  pMem.FieldByName('FIELD_TYPE').AsInteger := pType;
  if pSub >= 0 then
    pMem.FieldByName('FIELD_SUB_TYPE').AsInteger := pSub;
  pMem.FieldByName('NULL_FLAG').AsInteger := pNullFlag;
  if pChars >= 0 then
    pMem.FieldByName('CHARACTER_LEN').AsInteger := pChars;
  pMem.FieldByName('FIELD_SCALE').AsInteger := 0;
  pMem.Post;
end;

procedure AddPk(pMem: TFDMemTable; const pTable, pField: string; pPos: Integer);
begin
  pMem.AppendRecord([pTable, pField, pPos]);
end;

{ The fixture schema. ORDERS: BIGINT key with generator. LINES: composite key (a
  generator named like a single key exists and must be ignored). CODES: VARCHAR key
  (generator exists, must be ignored). ALLTYPES: one column per dictionary key, no PK.
  FIB$THING: excluded from datasets. NUMERICS: a NUMERIC column (8, 1) = no entry.
  WIDEKEY: composite KEY_FIELD longer than 68. A view column V_ORDERS.EXTRA exists only
  in RelationFields. }
function MakeSources(const pOpt: TFixtureOpt): TSchemaSources;
const
  WIDE_A = 'A_VERY_LONG_PRIMARY_KEY_COLUMN_NUMBER_ONE';
  WIDE_B = 'A_VERY_LONG_PRIMARY_KEY_COLUMN_NUMBER_TWO';
var
  vF, vR, vP, vG: TFDMemTable;
  vEntry: TFbTypeEntry;
  vType, vSub: Integer;
begin
  vF := NewMem(['TABLE_NAME', 'FIELD_NAME', 'DEFAULT_SOURCE', 'FIELD_LENGTH', 'FIELD_TYPE',
    'FIELD_SUB_TYPE', 'NULL_FLAG', 'CHARACTER_LEN', 'FIELD_SCALE'],
    [ftString, ftString, ftWideMemo, ftInteger, ftInteger, ftInteger, ftInteger, ftInteger, ftInteger]);
  AddField(vF, 'ORDERS', 'ID', 16, 0, 8, -1, 1, Null);
  if not pOpt.DropOrdersName then
    AddField(vF, 'ORDERS', 'NAME', 37, 0, pOpt.OrdersNameChars * 4, pOpt.OrdersNameChars, 0,
      'DEFAULT ''x''');
  AddField(vF, 'ORDERS', 'QTY', 8, 0, 4, -1, 0, 'DEFAULT 0');
  AddField(vF, 'ORDERS', 'FLAG', 23, -1, 1, -1, 1, Null);
  AddField(vF, 'LINES', 'ORDER_ID', 16, 0, 8, -1, 1, Null);
  AddField(vF, 'LINES', 'LINE_NO', 8, 0, 4, -1, 1, Null);
  AddField(vF, 'LINES', 'NOTE', 261, 1, 8, -1, 0, Null);
  AddField(vF, 'CODES', 'CODE', 37, 0, 160, 40, 1, Null);
  for vEntry in FbTypeEntries do
  begin
    vType := vEntry.Key mod FB_SUBTYPE_ADD;
    vSub := vEntry.Key div FB_SUBTYPE_ADD;
    AddField(vF, 'ALLTYPES', Format('C%d_%d', [vType, vSub]), vType, vSub, 4, -1, 0, Null);
  end;
  AddField(vF, 'ALLTYPES', 'BYTE1', 14, 1, 1, 1, 0, Null);
  AddField(vF, 'FIB$THING', 'ID', 16, 0, 8, -1, 1, Null);
  AddField(vF, 'NUMERICS', 'ID', 16, 0, 8, -1, 1, Null);
  AddField(vF, 'NUMERICS', 'AMOUNT', 8, 1, 4, -1, 0, Null);
  AddField(vF, 'WIDEKEY', WIDE_A, 8, 0, 4, -1, 1, Null);
  AddField(vF, 'WIDEKEY', WIDE_B, 8, 0, 4, -1, 1, Null);
  if pOpt.AddNewTable then
    AddField(vF, 'ZNEW', 'ID', 16, 0, 8, -1, 1, Null);

  vR := NewMem(['RELATION_NAME', 'FIELD_NAME'], [ftString, ftString]);
  vF.First;
  while not vF.Eof do
  begin
    vR.AppendRecord([vF.FieldByName('TABLE_NAME').AsString, vF.FieldByName('FIELD_NAME').AsString]);
    vF.Next;
  end;
  vR.AppendRecord(['V_ORDERS', 'EXTRA']);

  vP := NewMem(['TABLE_NAME', 'FIELD_NAME', 'FIELD_POSITION'], [ftString, ftString, ftInteger]);
  AddPk(vP, 'ORDERS', 'ID', 0);
  AddPk(vP, 'LINES', 'ORDER_ID', 0);
  AddPk(vP, 'LINES', 'LINE_NO', 1);
  AddPk(vP, 'CODES', 'CODE', 0);
  AddPk(vP, 'FIB$THING', 'ID', 0);
  AddPk(vP, 'NUMERICS', 'ID', 0);
  AddPk(vP, 'WIDEKEY', WIDE_A, 0);
  AddPk(vP, 'WIDEKEY', WIDE_B, 1);
  if pOpt.AddNewTable then
    AddPk(vP, 'ZNEW', 'ID', 0);

  vG := NewMem(['GENERATOR_NAME'], [ftString]);
  vG.AppendRecord(['GEN_ORDERS_ID']);
  vG.AppendRecord(['GEN_LINES_ORDER_ID']);
  vG.AppendRecord(['GEN_CODES_CODE']);

  Result.Fields := vF;
  Result.RelationFields := vR;
  Result.PrimaryKeys := vP;
  Result.Generators := vG;
end;

function FieldCount(const pSources: TSchemaSources): Integer;
begin
  Result := pSources.Fields.RecordCount;
end;

function NewRepo(const pName: string): TFDConnection;
var
  vFile: string;
begin
  vFile := TPath.Combine(GDir, pName + REPO_FILE_EXT);
  CreateRepository(vFile);
  Result := OpenRepository(vFile, False);
end;

function Scalar(pConn: TFDConnection; const pSql: string): Variant;
begin
  Result := pConn.ExecSQLScalar(pSql);
end;

function FieldVal(pConn: TFDConnection; const pTable, pField, pColumn: string): string;
var
  vVal: Variant;
begin
  vVal := pConn.ExecSQLScalar('SELECT ' + QuoteRepoIdent(pColumn) + ' FROM "DL_FIELDS_INFO" ' +
    'WHERE "TABLE_NAME" = :T AND "FIELD_NAME" = :F', [pTable, pField]);
  if VarIsEmpty(vVal) then
    Exit('<norow>');
  Result := if VarIsNull(vVal) then '<null>' else VarToStr(vVal);
end;

function BoolVal(pConn: TFDConnection; const pTable, pField, pColumn: string): Integer;
var
  vVal: Variant;
begin
  vVal := pConn.ExecSQLScalar('SELECT CAST(' + QuoteRepoIdent(pColumn) + ' AS INTEGER) FROM ' +
    '"DL_FIELDS_INFO" WHERE "TABLE_NAME" = :T AND "FIELD_NAME" = :F', [pTable, pField]);
  if VarIsEmpty(vVal) then
    Exit(-2);
  Result := if VarIsNull(vVal) then -1 else Integer(vVal);
end;

function DsVal(pConn: TFDConnection; const pTable, pColumn: string): string;
var
  vVal: Variant;
begin
  vVal := pConn.ExecSQLScalar('SELECT ' + QuoteRepoIdent(pColumn) + ' FROM "DL_DATASETS_INFO" ' +
    'WHERE "UPDATE_TABLE_NAME" = :T', [pTable]);
  if VarIsEmpty(vVal) then
    Exit('<norow>');
  Result := if VarIsNull(vVal) then '<null>' else VarToStr(vVal);
end;

function HasLine(const pLines: TArray<string>; const pLine: string): Boolean;
var
  vLine: string;
begin
  Result := False;
  for vLine in pLines do
    if vLine = pLine then
      Exit(True);
end;

function HasPrefix(const pLines: TArray<string>; const pPrefix: string): Boolean;
var
  vLine: string;
begin
  Result := False;
  for vLine in pLines do
    if vLine.StartsWith(pPrefix) then
      Exit(True);
end;

procedure TestFbTypes;
const
  EXPECT: array[0..19] of string = (
    '7=AsInteger/integer', '8=AsInteger/integer', '10=AsSingle/double',
    '12=AsDateTime/TDateTime', '13=AsDateTime/TDateTime', '14=AsString/string',
    '16=AsLargeInt/Int64', '23=AsBoolean/Boolean', '24=AsBCD/TBCD', '25=AsBCD/TBCD',
    '26=AsBCD/TBCD', '27=AsFloat/double', '28=AsDateTime/TDateTime',
    '29=AsSQLTimeStampOffset/TSQLTimeStampOffset', '35=AsSQLTimeStamp/TSQLTimeStamp',
    '37=AsString/string', '261=AsBlob/TPicture', '10014=AsByte/TBytes',
    '10037=AsByte/TBytes', '10261=AsString/TStringList');
var
  vText, vAcc, vVar: string;
  vKey, vType, vSub: Integer;
  vOk: Boolean;
begin
  Check('T1 dictionary has 20 keys', Length(FbTypeEntries) = Length(EXPECT),
    IntToStr(Length(FbTypeEntries)));
  for vText in EXPECT do
  begin
    vKey := StrToInt(vText.Split(['='])[0]);
    vType := vKey mod FB_SUBTYPE_ADD;
    vSub := vKey div FB_SUBTYPE_ADD;
    vOk := TryFbFieldAccessor(vType, vSub, vAcc) and TryFbFieldVarType(vType, vSub, 4, vVar);
    Check('T2 type code ' + vText, vOk and (Format('%d=%s/%s', [vKey, vAcc, vVar]) = vText),
      Format('%d=%s/%s', [vKey, vAcc, vVar]));
  end;
  Check('T3 CHAR(1) OCTETS is Byte', TryFbFieldVarType(14, 1, 1, vVar) and (vVar = 'Byte'), vVar);
  Check('T3b CHAR(2) OCTETS stays TBytes (control)',
    TryFbFieldVarType(14, 1, 2, vVar) and (vVar = 'TBytes'), vVar);
  Check('T4 NUMERIC (8,1) has no entry', not TryFbFieldAccessor(8, 1, vAcc) and (vAcc = ''));
  Check('T4b DECIMAL sub_type 2 has no entry', not TryFbFieldAccessor(16, 2, vAcc));
  Check('T4c unknown code 9 has no entry', not TryFbFieldVarType(9, 0, 4, vVar) and (vVar = ''));
  Check('T4d BLOB sub_type 2 has no entry', not TryFbFieldAccessor(261, 2, vAcc));
end;

procedure TestSeed;
var
  vConn: TFDConnection;
  vSrc: TSchemaSources;
  vRes: TSchemaSeedResult;
  vTotal: Integer;
begin
  vSrc := MakeSources(DefaultOpt);
  vConn := NewRepo('seed');
  try
    vTotal := FieldCount(vSrc);
    vRes := RunSchemaSeed(vConn, vSrc, ssmSeed, False, GStamp);
    Check('S1 seed adds one row per schema column', (vRes.Added = vTotal) and
      (RepoRowCount(vConn, 'DL_FIELDS_INFO') = vTotal),
      Format('added=%d rows=%d expected=%d', [vRes.Added, RepoRowCount(vConn, 'DL_FIELDS_INFO'), vTotal]));
    Check('S1b seed changes and orphans nothing', (vRes.Changed = 0) and (vRes.Orphaned = 0),
      Format('changed=%d orphaned=%d', [vRes.Changed, vRes.Orphaned]));
    Check('S2 accessor of BIGINT key', FieldVal(vConn, 'ORDERS', 'ID', 'FIELD_AS_TYPE') = 'AsLargeInt');
    Check('S2b var type of BIGINT key', FieldVal(vConn, 'ORDERS', 'ID', 'VAR_TYPE') = 'Int64');
    Check('S2c every dictionary column got its accessor',
      Scalar(vConn, 'SELECT COUNT(*) FROM "DL_FIELDS_INFO" WHERE "TABLE_NAME" = ''ALLTYPES'' ' +
      'AND "FIELD_AS_TYPE" IS NOT NULL AND "VAR_TYPE" IS NOT NULL') = Length(FbTypeEntries) + 1);
    Check('S2d BLOB TEXT is AsString / TStringList',
      (FieldVal(vConn, 'LINES', 'NOTE', 'FIELD_AS_TYPE') = 'AsString') and
      (FieldVal(vConn, 'LINES', 'NOTE', 'VAR_TYPE') = 'TStringList'));
    Check('S2e CHAR(1) OCTETS is Byte', FieldVal(vConn, 'ALLTYPES', 'BYTE1', 'VAR_TYPE') = 'Byte');
    Check('S3 schema numbers of ORDERS.NAME',
      (FieldVal(vConn, 'ORDERS', 'NAME', 'FIELD_SIZE') = '160') and
      (FieldVal(vConn, 'ORDERS', 'NAME', 'STRING_SIZE') = '40') and
      (FieldVal(vConn, 'ORDERS', 'NAME', 'FIELD_LENGTH') = '160') and
      (FieldVal(vConn, 'ORDERS', 'NAME', 'FIELD_TYPE') = '37') and
      (FieldVal(vConn, 'ORDERS', 'NAME', 'FIELD_SUBTYPE') = '0') and
      (FieldVal(vConn, 'ORDERS', 'NAME', 'FIELD_SCALE') = '0') and
      (FieldVal(vConn, 'ORDERS', 'NAME', 'FIELD_KIND') = '1') and
      (FieldVal(vConn, 'ORDERS', 'NAME', 'NULL_FLAG') = '0'));
    Check('S3b NULL sub_type / char length read as 0',
      (FieldVal(vConn, 'ORDERS', 'FLAG', 'FIELD_SUBTYPE') = '0') and
      (FieldVal(vConn, 'ORDERS', 'FLAG', 'STRING_SIZE') = '0') and
      (FieldVal(vConn, 'ORDERS', 'FLAG', 'NULL_FLAG') = '1'));
    Check('S4 DEFAULTVAL strips "DEFAULT "', (FieldVal(vConn, 'ORDERS', 'QTY', 'DEFAULTVAL') = '0') and
      (FieldVal(vConn, 'ORDERS', 'NAME', 'DEFAULTVAL') = '''x'''),
      FieldVal(vConn, 'ORDERS', 'NAME', 'DEFAULTVAL'));
    Check('S4b no default source gives empty DEFAULTVAL', FieldVal(vConn, 'ORDERS', 'ID', 'DEFAULTVAL') = '');
    Check('S5 single BIGINT key: PK + sequence + triggered',
      (BoolVal(vConn, 'ORDERS', 'ID', 'PRIMARY_KEY') = 1) and
      (FieldVal(vConn, 'ORDERS', 'ID', 'SEQUENCE_NAME') = 'GEN_ORDERS_ID') and
      (BoolVal(vConn, 'ORDERS', 'ID', 'TRIGGERED') = 1));
    Check('S5b non-key column is not PK (control)', (BoolVal(vConn, 'ORDERS', 'QTY', 'PRIMARY_KEY') = 0) and
      (BoolVal(vConn, 'ORDERS', 'QTY', 'TRIGGERED') = 0));
    Check('S6 composite key: both PK, no sequence although a generator exists',
      (BoolVal(vConn, 'LINES', 'ORDER_ID', 'PRIMARY_KEY') = 1) and
      (BoolVal(vConn, 'LINES', 'LINE_NO', 'PRIMARY_KEY') = 1) and
      (FieldVal(vConn, 'LINES', 'ORDER_ID', 'SEQUENCE_NAME') = '<null>') and
      (BoolVal(vConn, 'LINES', 'ORDER_ID', 'TRIGGERED') = 0));
    Check('S6b VARCHAR key: PK, no sequence', (BoolVal(vConn, 'CODES', 'CODE', 'PRIMARY_KEY') = 1) and
      (FieldVal(vConn, 'CODES', 'CODE', 'SEQUENCE_NAME') = '<null>'));
    Check('S7 TableTools new-row values', (FieldVal(vConn, 'ORDERS', 'QTY', 'DISPLAY_LABEL') = '') and
      (BoolVal(vConn, 'ORDERS', 'QTY', 'VISIBLE') = 0) and
      (FieldVal(vConn, 'ORDERS', 'QTY', 'ALIGNMENT') = '-2') and
      (FieldVal(vConn, 'ORDERS', 'QTY', 'DISPLAY_WIDTH') = '0') and
      (FieldVal(vConn, 'ORDERS', 'QTY', 'DESTTABLE') = '') and
      (FieldVal(vConn, 'ORDERS', 'QTY', 'DOC_SUMMARY') = 'Summary here') and
      (BoolVal(vConn, 'ORDERS', 'QTY', 'ISCALCULATED') = 0));
    Check('S8 NUMERIC column added without accessor, run not aborted',
      (FieldVal(vConn, 'NUMERICS', 'AMOUNT', 'FIELD_AS_TYPE') = '<null>') and
      (FieldVal(vConn, 'NUMERICS', 'AMOUNT', 'FIELD_TYPE') = '8') and
      HasPrefix(vRes.Warnings, 'NUMERICS.AMOUNT type=8 sub_type=1'),
      string.Join(' | ', vRes.Warnings));
    Check('S9 diff lists every added row', (Length(vRes.Diff) >= vTotal) and
      HasLine(vRes.Diff, '+ FIELD ORDERS.ID'));
    { datasets }
    Check('D1 dataset rows: ORDERS LINES CODES NUMERICS (FIB$, no-PK and wide-key skipped)',
      (vRes.DatasetsInserted = 4) and (RepoRowCount(vConn, 'DL_DATASETS_INFO') = 4),
      Format('inserted=%d rows=%d skipped=%d', [vRes.DatasetsInserted,
      RepoRowCount(vConn, 'DL_DATASETS_INFO'), vRes.DatasetsSkipped]));
    Check('D2 ORDERS SELECT_SQL', DsVal(vConn, 'ORDERS', 'SELECT_SQL') = 'SELECT FLAG, ID, NAME, QTY FROM ORDERS',
      DsVal(vConn, 'ORDERS', 'SELECT_SQL'));
    Check('D2b ORDERS INSERT_SQL', DsVal(vConn, 'ORDERS', 'INSERT_SQL') =
      'INSERT INTO ORDERS (FLAG, ID, NAME, QTY) VALUES (:FLAG, :ID, :NAME, :QTY)');
    Check('D2c ORDERS UPDATE_SQL', DsVal(vConn, 'ORDERS', 'UPDATE_SQL') =
      'UPDATE ORDERS SET FLAG=:FLAG, NAME=:NAME, QTY=:QTY WHERE ID=:OLD_ID');
    Check('D2d ORDERS DELETE_SQL', DsVal(vConn, 'ORDERS', 'DELETE_SQL') = 'DELETE FROM ORDERS WHERE ID=:OLD_ID');
    Check('D2e ORDERS REFRESH_SQL', DsVal(vConn, 'ORDERS', 'REFRESH_SQL') =
      'SELECT FLAG, ID, NAME, QTY FROM ORDERS WHERE ID=:ID');
    Check('D2f ORDERS key, generator, flags', (DsVal(vConn, 'ORDERS', 'KEY_FIELD') = 'ID') and
      (DsVal(vConn, 'ORDERS', 'NAME_GENERATOR') = 'GEN_ORDERS_ID') and
      (DsVal(vConn, 'ORDERS', 'UPDATE_ONLY_MODIFIED_FIELDS') <> 'False') and
      (DsVal(vConn, 'ORDERS', 'CONDITIONS') = '') and
      DsVal(vConn, 'ORDERS', 'DESCRIPTION').StartsWith('Auto by drag-lint '),
      DsVal(vConn, 'ORDERS', 'UPDATE_ONLY_MODIFIED_FIELDS') + ' ' + DsVal(vConn, 'ORDERS', 'DESCRIPTION'));
    Check('D3 composite KEY_FIELD in key order, no generator',
      (DsVal(vConn, 'LINES', 'KEY_FIELD') = 'ORDER_ID,LINE_NO') and
      (DsVal(vConn, 'LINES', 'NAME_GENERATOR') = '') and
      (DsVal(vConn, 'LINES', 'UPDATE_SQL') =
      'UPDATE LINES SET NOTE=:NOTE WHERE ORDER_ID=:OLD_ORDER_ID AND LINE_NO=:OLD_LINE_NO'),
      DsVal(vConn, 'LINES', 'UPDATE_SQL'));
    Check('D4 all-key table has empty UPDATE_SQL', DsVal(vConn, 'CODES', 'UPDATE_SQL') = '');
    Check('D5 FIB$ / no-PK tables get no dataset', (DsVal(vConn, 'FIB$THING', 'DS_ID') = '<norow>') and
      (DsVal(vConn, 'ALLTYPES', 'DS_ID') = '<norow>'));
    Check('D6 over-long composite KEY_FIELD skipped with a warning',
      (DsVal(vConn, 'WIDEKEY', 'DS_ID') = '<norow>') and HasPrefix(vRes.Warnings, 'WIDEKEY KEY_FIELD'),
      string.Join(' | ', vRes.Warnings));
    Check('D7 DS_IDs are 1..4 in table order', (DsVal(vConn, 'CODES', 'DS_ID') = '1') and
      (DsVal(vConn, 'ORDERS', 'DS_ID') = '4'));
    Check('M1 DL_META schema_refreshed_at_utc', GetRepoMeta(vConn, 'schema_refreshed_at_utc') <> '');
    Check('E1 seed on a non-empty repository raises ERepoError',
      RaisedMessage(procedure begin RunSchemaSeed(vConn, vSrc, ssmSeed, False, GStamp); end)
      .StartsWith('ERepoError'));
  finally
    vConn.Free;
    FreeSchemaSources(vSrc);
  end;
end;

procedure TestRefresh;
var
  vConn: TFDConnection;
  vSrc: TSchemaSources;
  vOpt: TFixtureOpt;
  vRes: TSchemaSeedResult;
  vRows: Integer;
begin
  vSrc := MakeSources(DefaultOpt);
  vConn := NewRepo('refresh');
  try
    RunSchemaSeed(vConn, vSrc, ssmSeed, False, GStamp);
    vRows := RepoRowCount(vConn, 'DL_FIELDS_INFO');
    { an identical second run is a no-op }
    vRes := RunSchemaSeed(vConn, vSrc, ssmRefresh, False, GStamp);
    Check('R1 identical refresh changes nothing',
      (vRes.Added = 0) and (vRes.Changed = 0) and (vRes.Orphaned = 0) and
      (vRes.DatasetsInserted = 0) and (vRes.DatasetsUpdated = 0) and (Length(vRes.Diff) = 0),
      Format('added=%d changed=%d orphaned=%d dsins=%d dsupd=%d diff=%d', [vRes.Added, vRes.Changed,
      vRes.Orphaned, vRes.DatasetsInserted, vRes.DatasetsUpdated, Length(vRes.Diff)]));
    { hand edits + one damaged schema column }
    vConn.ExecSQL('UPDATE "DL_FIELDS_INFO" SET "DISPLAY_LABEL" = ''Customer'', "VISIBLE" = 1, ' +
      '"DISPLAY_WIDTH" = 33, "DEFAULTVAL" = ''hand'', "DOC_SUMMARY" = ''doc'', "ALIGNMENT" = 1, ' +
      '"FIELD_SIZE" = 999 WHERE "TABLE_NAME" = ''ORDERS'' AND "FIELD_NAME" = ''NAME''');
    vConn.ExecSQL('UPDATE "DL_FIELDS_INFO" SET "ISENUM" = 1, "ENUMTYPE" = ''TQtyKind'' ' +
      'WHERE "TABLE_NAME" = ''ORDERS'' AND "FIELD_NAME" = ''QTY''');
    vConn.ExecSQL('UPDATE "DL_DATASETS_INFO" SET "CONDITIONS" = ''hand cond'', ' +
      '"UPDATE_ONLY_MODIFIED_FIELDS" = 0 WHERE "UPDATE_TABLE_NAME" = ''ORDERS''');
    vOpt := DefaultOpt;
    vOpt.OrdersNameChars := 50;
    FreeSchemaSources(vSrc);
    vSrc := MakeSources(vOpt);
    vRes := RunSchemaSeed(vConn, vSrc, ssmRefresh, False, GStamp);
    Check('R2 hand columns survive a second run',
      (FieldVal(vConn, 'ORDERS', 'NAME', 'DISPLAY_LABEL') = 'Customer') and
      (BoolVal(vConn, 'ORDERS', 'NAME', 'VISIBLE') = 1) and
      (FieldVal(vConn, 'ORDERS', 'NAME', 'DISPLAY_WIDTH') = '33') and
      (FieldVal(vConn, 'ORDERS', 'NAME', 'DEFAULTVAL') = 'hand') and
      (FieldVal(vConn, 'ORDERS', 'NAME', 'DOC_SUMMARY') = 'doc') and
      (FieldVal(vConn, 'ORDERS', 'NAME', 'ALIGNMENT') = '1'));
    Check('R3 schema columns are overwritten (positive control)',
      (FieldVal(vConn, 'ORDERS', 'NAME', 'FIELD_SIZE') = '200') and
      (FieldVal(vConn, 'ORDERS', 'NAME', 'STRING_SIZE') = '50'),
      FieldVal(vConn, 'ORDERS', 'NAME', 'FIELD_SIZE'));
    Check('R3b changed count and diff line', (vRes.Changed = 2) and
      HasLine(vRes.Diff, '~ FIELD ORDERS.NAME STRING_SIZE: 40 -> 50') and
      HasLine(vRes.Diff, '~ FIELD ORDERS.NAME FIELD_SIZE: 999 -> 200'),
      Format('changed=%d diff=%s', [vRes.Changed, string.Join(' | ', vRes.Diff)]));
    Check('R4 ISENUM column takes ENUMTYPE as VAR_TYPE',
      FieldVal(vConn, 'ORDERS', 'QTY', 'VAR_TYPE') = 'TQtyKind');
    Check('R5 hand dataset columns survive', (DsVal(vConn, 'ORDERS', 'CONDITIONS') = 'hand cond') and
      ((DsVal(vConn, 'ORDERS', 'UPDATE_ONLY_MODIFIED_FIELDS') = 'False') or (DsVal(vConn, 'ORDERS', 'UPDATE_ONLY_MODIFIED_FIELDS') = '0')) and
      (DsVal(vConn, 'ORDERS', 'DS_ID') = '4'));
    Check('R6 no rows added', RepoRowCount(vConn, 'DL_FIELDS_INFO') = vRows);

    { vanished column + a new table }
    vConn.ExecSQL('INSERT INTO "DL_FIELDS_INFO" ("TABLE_NAME", "FIELD_NAME") VALUES (''RDB$FAKE'', ''F'')');
    vConn.ExecSQL('INSERT INTO "DL_FIELDS_INFO" ("TABLE_NAME", "FIELD_NAME") VALUES (''V_ORDERS'', ''EXTRA'')');
    { FR-MODEL: calc (2), aggregate (5) and graphical (10) rows are not orphans }
    vConn.ExecSQL('INSERT INTO "DL_FIELDS_INFO" ("TABLE_NAME", "FIELD_NAME", "FIELD_KIND", "ISCALCULATED", "CALC_BODY") ' +
      'VALUES (''ORDERS'', ''CALCF'', 2, 1, ''{{CALCF}} := 1;'')');
    vConn.ExecSQL('INSERT INTO "DL_FIELDS_INFO" ("TABLE_NAME", "FIELD_NAME", "FIELD_KIND") VALUES (''ORDERS'', ''AGGF'', 5)');
    vConn.ExecSQL('INSERT INTO "DL_FIELDS_INFO" ("TABLE_NAME", "FIELD_NAME", "FIELD_KIND") VALUES (''ORDERS'', ''PICF'', 10)');
    vConn.ExecSQL('INSERT INTO "DL_FIELDS_INFO" ("TABLE_NAME", "FIELD_NAME", "FIELD_KIND") VALUES (''ORDERS'', ''LOOKF'', 3)');
    vOpt.DropOrdersName := True;
    vOpt.AddNewTable := True;
    FreeSchemaSources(vSrc);
    vSrc := MakeSources(vOpt);
    vRes := RunSchemaSeed(vConn, vSrc, ssmRefresh, False, GStamp);
    Check('O1 vanished column -> ISCALCULATED, row kept',
      (BoolVal(vConn, 'ORDERS', 'NAME', 'ISCALCULATED') = 1) and
      (FieldVal(vConn, 'ORDERS', 'NAME', 'DISPLAY_LABEL') = 'Customer') and (vRes.Orphaned = 1) and
      HasLine(vRes.Diff, '! FIELD ORDERS.NAME ISCALCULATED (column vanished)'),
      Format('orphaned=%d', [vRes.Orphaned]));
    Check('O1b a vanished data column becomes FIELD_KIND 2 (calc)',
      FieldVal(vConn, 'ORDERS', 'NAME', 'FIELD_KIND') = '2', FieldVal(vConn, 'ORDERS', 'NAME', 'FIELD_KIND'));
    Check('O1c calc / aggregate / graphical / lookup rows survive refresh unchanged',
      (FieldVal(vConn, 'ORDERS', 'CALCF', 'FIELD_KIND') = '2') and (BoolVal(vConn, 'ORDERS', 'CALCF', 'ISCALCULATED') = 1)
      and (FieldVal(vConn, 'ORDERS', 'CALCF', 'CALC_BODY') = '{{CALCF}} := 1;')
      and (FieldVal(vConn, 'ORDERS', 'AGGF', 'FIELD_KIND') = '5') and (BoolVal(vConn, 'ORDERS', 'AGGF', 'ISCALCULATED') = 0)
      and (FieldVal(vConn, 'ORDERS', 'PICF', 'FIELD_KIND') = '10') and (BoolVal(vConn, 'ORDERS', 'PICF', 'ISCALCULATED') = 0)
      and (FieldVal(vConn, 'ORDERS', 'LOOKF', 'FIELD_KIND') = '3') and (BoolVal(vConn, 'ORDERS', 'LOOKF', 'ISCALCULATED') = 0));
    Check('O2 present columns stay non-calculated (control)',
      (BoolVal(vConn, 'ORDERS', 'QTY', 'ISCALCULATED') = 0) and
      (BoolVal(vConn, 'ORDERS', 'ID', 'ISCALCULATED') = 0));
    Check('O3 RDB$ rows and view columns are not orphaned',
      (BoolVal(vConn, 'RDB$FAKE', 'F', 'ISCALCULATED') = 0) and
      (BoolVal(vConn, 'V_ORDERS', 'EXTRA', 'ISCALCULATED') = 0));
    Check('O4 dataset SQL drops the calculated field, keeps DS_ID',
      (DsVal(vConn, 'ORDERS', 'SELECT_SQL') = 'SELECT FLAG, ID, QTY FROM ORDERS') and
      (DsVal(vConn, 'ORDERS', 'DS_ID') = '4') and (vRes.DatasetsUpdated >= 1),
      DsVal(vConn, 'ORDERS', 'SELECT_SQL'));
    Check('O5 new table: field rows + dataset with next DS_ID',
      (vRes.Added = 1) and (DsVal(vConn, 'ZNEW', 'DS_ID') = '5') and (vRes.DatasetsInserted = 1),
      Format('added=%d ds=%s', [vRes.Added, DsVal(vConn, 'ZNEW', 'DS_ID')]));
    Check('O6 a third identical run reports nothing more',
      RunSchemaSeed(vConn, vSrc, ssmRefresh, False, GStamp).Orphaned = 0);
  finally
    vConn.Free;
    FreeSchemaSources(vSrc);
  end;
end;

procedure TestDryRun;
var
  vConn: TFDConnection;
  vSrc: TSchemaSources;
  vOpt: TFixtureOpt;
  vRes: TSchemaSeedResult;
begin
  vSrc := MakeSources(DefaultOpt);
  vConn := NewRepo('dryrun');
  try
    vRes := RunSchemaSeed(vConn, vSrc, ssmSeed, True, GStamp);
    Check('Y1 dry-run seed reports rows but writes none', (vRes.Added = FieldCount(vSrc)) and
      RepoIsEmpty(vConn) and (GetRepoMeta(vConn, 'schema_refreshed_at_utc') = ''),
      Format('added=%d', [vRes.Added]));
    RunSchemaSeed(vConn, vSrc, ssmSeed, False, GStamp);
    vOpt := DefaultOpt;
    vOpt.DropOrdersName := True;
    FreeSchemaSources(vSrc);
    vSrc := MakeSources(vOpt);
    vRes := RunSchemaSeed(vConn, vSrc, ssmRefresh, True, GStamp);
    Check('Y2 dry-run refresh reports the orphan', (vRes.Orphaned = 1) and (Length(vRes.Diff) > 0));
    Check('Y3 ... and leaves the repository unchanged',
      (BoolVal(vConn, 'ORDERS', 'NAME', 'ISCALCULATED') = 0) and
      (DsVal(vConn, 'ORDERS', 'SELECT_SQL') = 'SELECT FLAG, ID, NAME, QTY FROM ORDERS'));
    Check('Y4 the connection is usable after a dry run (no open transaction)',
      not vConn.InTransaction);
  finally
    vConn.Free;
    FreeSchemaSources(vSrc);
  end;
end;

procedure TestBadSources;
var
  vConn: TFDConnection;
  vSrc: TSchemaSources;
  vMsg: string;
  vOrig: TDataSet;
begin
  vSrc := MakeSources(DefaultOpt);
  vConn := NewRepo('bad');
  try
    vOrig := vSrc.Generators;
    vSrc.Generators := NewMem(['NAME'], [ftString]);
    try
      vMsg := RaisedMessage(procedure begin RunSchemaSeed(vConn, vSrc, ssmSeed, False, GStamp); end);
      Check('B1 a missing source column raises ERepoError naming it',
        vMsg.StartsWith('ERepoError') and vMsg.Contains('GENERATOR_NAME'), vMsg);
      Check('B1b nothing written', RepoIsEmpty(vConn));
    finally
      vSrc.Generators.Free;
      vSrc.Generators := vOrig;
    end;
    vOrig := vSrc.PrimaryKeys;
    vSrc.PrimaryKeys := nil;
    vMsg := RaisedMessage(procedure begin RunSchemaSeed(vConn, vSrc, ssmSeed, False, GStamp); end);
    Check('B2 a nil source raises ERepoError', vMsg.StartsWith('ERepoError'), vMsg);
    vSrc.PrimaryKeys := vOrig;
    Check('B3 the same sources succeed when complete (control)',
      RaisedMessage(procedure begin RunSchemaSeed(vConn, vSrc, ssmSeed, False, GStamp); end) = '');
  finally
    vConn.Free;
    FreeSchemaSources(vSrc);
  end;
end;

begin
  GStamp := EncodeDate(2026, 11, 17) + EncodeTime(12, 0, 0, 0);
  GDir := TPath.Combine(TPath.GetTempPath, 'dl-fieldrepo-TTS-' + IntToStr(GetCurrentProcessId));
  TDirectory.CreateDirectory(GDir);
  try
    TestFbTypes;
    TestSeed;
    TestRefresh;
    TestDryRun;
    TestBadSources;
  except
    on E: Exception do
    begin
      Inc(GFail);
      Writeln('FAIL unhandled ', E.ClassName, ': ', E.Message);
    end;
  end;
  Writeln('SUMMARY pass=', GPass, ' fail=', GFail);
  if GFail > 0 then
    ExitCode := 1;
end.
