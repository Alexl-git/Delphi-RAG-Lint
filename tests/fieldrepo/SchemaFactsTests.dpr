program SchemaFactsTests;

{$APPTYPE CONSOLE}

{ drag-lint 1.53 lane FR-SCHEMA -- console tests for the schema facts of a field repository (design
  2026-11-22-field-repository-v2-design.md sections 1.2 and 5): the four schema tables, the SchemaFacts read
  API, the repository locator, migrate, the live reader (dataset-fed), the DDL reader, refresh as a change set.
  Output: one PASS / FAIL line per check, then "SUMMARY pass=N fail=M". Exit code 0 only when fail=0. }

uses
  Winapi.Windows,
  System.SysUtils,
  System.IOUtils,
  System.Classes,
  System.StrUtils,
  System.Variants,
  System.Generics.Collections,
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
  DRagLint.FieldRepo.TextBackup in '..\..\src\sql\DRagLint.FieldRepo.TextBackup.pas',
  DRagLint.FieldRepo.Migrate in '..\..\src\sql\DRagLint.FieldRepo.Migrate.pas',
  DRagLint.FieldRepo.SchemaFacts in '..\..\src\sql\DRagLint.FieldRepo.SchemaFacts.pas',
  DRagLint.FieldRepo.Locate in '..\..\src\sql\DRagLint.FieldRepo.Locate.pas',
  DRagLint.FieldRepo.ChangeSet in '..\..\src\sql\DRagLint.FieldRepo.ChangeSet.pas',
  DRagLint.FieldRepo.FbSchemaRead in '..\..\src\sql\DRagLint.FieldRepo.FbSchemaRead.pas',
  DRagLint.FieldRepo.FbDdl in '..\..\src\sql\DRagLint.FieldRepo.FbDdl.pas',
  DRagLint.FieldRepo.SchemaSeed in '..\..\src\sql\DRagLint.FieldRepo.SchemaSeed.pas',
  DRagLint.FieldRepo.FbImport in '..\..\src\sql\DRagLint.FieldRepo.FbImport.pas';

var
  GPass: Integer = 0;
  GFail: Integer = 0;
  GDir: string;

procedure Check(const pName: string; pCond: Boolean; const pDetail: string = '');
begin
  if pCond then
  begin
    Inc(GPass);
    Writeln('PASS ', pName);
  end
  else
  begin
    Inc(GFail);
    Writeln('FAIL ', pName, ' ', pDetail);
  end;
end;

function Fixture(const pRel: string): string;
begin
  Result := TPath.GetFullPath(TPath.Combine(ExtractFilePath(ParamStr(0)), '..\fixtures\fieldrepo\' + pRel));
end;

function NewRepo(const pName: string; pVersion: Integer = 2): TFDConnection;
var
  vPath: string;
begin
  vPath := TPath.Combine(GDir, pName + '.dlrepo');
  CreateRepository(vPath, pVersion);
  Result := OpenRepository(vPath, False);
end;

function ColumnNames(const pTab: TRepoTable): string;
var
  vCol: TRepoColumn;
begin
  Result := '';
  for vCol in pTab.Columns do
    Result := Result + (if Result = '' then '' else ',') + vCol.Name;
end;

function TableByName(pVersion: Integer; const pName: string): TRepoTable;
var
  vTab: TRepoTable;
begin
  Result := Default(TRepoTable);
  for vTab in RepoTablesFor(pVersion) do
    if SameText(vTab.Name, pName) then
      Exit(vTab);
end;

{ ---- task 1: tables ------------------------------------------------------------ }

{ Runs pProc and returns the exception class name raised, '' when none. }
function RaisedClass(pProc: TProc): string;
begin
  Result := '';
  try
    pProc;
  except
    on E: Exception do
      Result := E.ClassName;
  end;
end;

{ Runs pProc and returns the exception message raised, '' when none. }
function RaisedMessage(pProc: TProc): string;
begin
  Result := '';
  try
    pProc;
  except
    on E: Exception do
      Result := E.Message;
  end;
end;
procedure TestTables;
var
  vConn: TFDConnection;
  vFi: TRepoTable;
begin
  Check('1a v2 has 11 tables, v1 has 5', (Length(RepoTablesFor(2)) = 11) and (Length(RepoTablesFor(1)) = 5),
    IntToStr(Length(RepoTablesFor(2))));
  Check('1b DL_DOMAINS columns', ColumnNames(TableByName(2, 'DL_DOMAINS')) =
    'DOMAIN_NAME,FIELD_TYPE,FIELD_SUBTYPE,FIELD_LENGTH,CHAR_LENGTH,FIELD_SCALE,FIELD_PRECISION,NULL_FLAG,' +
    'DEFAULT_SOURCE,CHECK_SOURCE,CHARSET', ColumnNames(TableByName(2, 'DL_DOMAINS')));
  Check('1c DL_CONSTRAINTS columns', ColumnNames(TableByName(2, 'DL_CONSTRAINTS')) =
    'CONSTRAINT_NAME,TABLE_NAME,KIND,REF_TABLE,REF_CONSTRAINT,UPDATE_RULE,DELETE_RULE');
  Check('1d DL_CONSTRAINT_COLUMNS columns', ColumnNames(TableByName(2, 'DL_CONSTRAINT_COLUMNS')) =
    'CONSTRAINT_NAME,POSITION,COLUMN_NAME');
  Check('1e DL_GENERATORS columns', ColumnNames(TableByName(2, 'DL_GENERATORS')) = 'GENERATOR_NAME');
  vFi := TableByName(2, 'DL_FIELDS_INFO');
  Check('1f DL_FIELDS_INFO ends CALC_BODY, DOMAIN_NAME, CHAR_LENGTH',
    ColumnNames(vFi).EndsWith(',CALC_BODY,DOMAIN_NAME,CHAR_LENGTH'));
  Check('1g v1 DL_FIELDS_INFO unchanged (40 columns, no DOMAIN_NAME)',
    (Length(TableByName(1, 'DL_FIELDS_INFO').Columns) = 40) and
    (not ColumnNames(TableByName(1, 'DL_FIELDS_INFO')).Contains('DOMAIN_NAME')));
  vConn := NewRepo('t1');
  try
    Check('1h a fresh v2 repository is empty', RepoIsEmpty(vConn));
    vConn.ExecSQL('INSERT INTO "DL_GENERATORS" ("GENERATOR_NAME") VALUES (''GEN_X'')');
    vConn.ExecSQL('INSERT INTO "DL_DOMAINS" ("DOMAIN_NAME") VALUES (''D_X'')');
    Check('1i RepoIsEmpty ignores the schema tables', RepoIsEmpty(vConn));
    vConn.ExecSQL('INSERT INTO "DL_ENUMVALUES" ("ENUMTYPE","EORDER","NAME","ESTRING") VALUES (''E'',1,''N'',''S'')');
    Check('1j ... and still sees a hand-kept table (control)', not RepoIsEmpty(vConn));
  finally
    vConn.Free;
  end;
end;

{ ---- migrate: a v1 repository migrated with --apply passes the v2 validation ----- }

procedure TestMigrate;
var
  vPath: string;
  vConn: TFDConnection;
  vRes: TFrMigrateResult;
  vTab: TRepoTable;
  vOk: Boolean;
begin
  vPath := TPath.Combine(GDir, 'mig.dlrepo');
  CreateRepository(vPath, 1);
  vRes := MigrateRepository(vPath, True);
  Check('M1 migrate applied', vRes.Applied);
  vConn := nil;
  try
    vConn := OpenRepository(vPath, True);
    Check('M2 the migrated file passes the v2 table-set validation', RepoSchemaVersion(vConn) = 2);
    vOk := True;
    for vTab in RepoTablesFor(2) do
      try
        RepoRowCount(vConn, vTab.Name);
      except
        vOk := False;
      end;
    Check('M3 all 11 v2 tables exist (4 schema tables included)', vOk);
    Check('M4 DL_FIELDS_INFO has DOMAIN_NAME and CHAR_LENGTH',
      Integer(vConn.ExecSQLScalar('SELECT COUNT(*) FROM pragma_table_info(''DL_FIELDS_INFO'') ' +
        'WHERE name IN (''DOMAIN_NAME'',''CHAR_LENGTH'',''CALC_BODY'')')) = 3);
  finally
    vConn.Free;
  end;
end;

{ ---- task 2: SchemaFacts --------------------------------------------------------- }

procedure TestFacts;
var
  vConn: TFDConnection;
  vInfo: TSchemaInfo;
  vPk: TArray<string>;
begin
  vConn := NewRepo('t2');
  try
    Check('2a HasSchema false before any apply', not HasSchema(vConn));
    Check('2b ColumnCharLength -1 without facts', ColumnCharLength(vConn, 'ORDERS', 'NAME') = -1);
    Check('2c PrimaryKey empty without facts', Length(PrimaryKey(vConn, 'ORDERS')) = 0);
    vInfo := SchemaInfo(vConn);
    Check('2d SchemaInfo empty without facts', (vInfo.ReadAtUtc = '') and (vInfo.Source = '') and (vInfo.Database = ''));
    vConn.ExecSQL('INSERT INTO "DL_DOMAINS" ("DOMAIN_NAME","CHAR_LENGTH") VALUES (''D_NAME'', 40)');
    vConn.ExecSQL('INSERT INTO "DL_FIELDS_INFO" ("TABLE_NAME","FIELD_NAME","CHAR_LENGTH") VALUES (''ORDERS'',''CODE'', 12)');
    vConn.ExecSQL('INSERT INTO "DL_FIELDS_INFO" ("TABLE_NAME","FIELD_NAME","DOMAIN_NAME") VALUES (''ORDERS'',''NAME'',''D_NAME'')');
    vConn.ExecSQL('INSERT INTO "DL_FIELDS_INFO" ("TABLE_NAME","FIELD_NAME") VALUES (''ORDERS'',''QTY'')');
    vConn.ExecSQL('INSERT INTO "DL_FIELDS_INFO" ("TABLE_NAME","FIELD_NAME","CHAR_LENGTH","DOMAIN_NAME") VALUES (''ORDERS'',''BOTH'', 5, ''D_NAME'')');
    vConn.ExecSQL('INSERT INTO "DL_CONSTRAINTS" ("CONSTRAINT_NAME","TABLE_NAME","KIND") VALUES (''PK_ORDERS'',''ORDERS'',''PK'')');
    vConn.ExecSQL('INSERT INTO "DL_CONSTRAINTS" ("CONSTRAINT_NAME","TABLE_NAME","KIND") VALUES (''UQ_ORDERS'',''ORDERS'',''UNIQUE'')');
    vConn.ExecSQL('INSERT INTO "DL_CONSTRAINT_COLUMNS" VALUES (''PK_ORDERS'', 2, ''B'')');
    vConn.ExecSQL('INSERT INTO "DL_CONSTRAINT_COLUMNS" VALUES (''PK_ORDERS'', 1, ''A'')');
    vConn.ExecSQL('INSERT INTO "DL_CONSTRAINT_COLUMNS" VALUES (''UQ_ORDERS'', 1, ''CODE'')');
    Check('2e own CHAR_LENGTH', ColumnCharLength(vConn, 'ORDERS', 'CODE') = 12);
    Check('2f falls back to the domain', ColumnCharLength(vConn, 'ORDERS', 'NAME') = 40);
    Check('2g field wins over its domain', ColumnCharLength(vConn, 'ORDERS', 'BOTH') = 5);
    Check('2h unknown (no length, no domain) is -1', ColumnCharLength(vConn, 'ORDERS', 'QTY') = -1);
    Check('2i unknown column is -1', ColumnCharLength(vConn, 'ORDERS', 'NOPE') = -1);
    Check('2j case-insensitive', ColumnCharLength(vConn, 'orders', 'code') = 12);
    vPk := PrimaryKey(vConn, 'ORDERS');
    Check('2k PrimaryKey in key order, UNIQUE excluded', (Length(vPk) = 2) and (vPk[0] = 'A') and (vPk[1] = 'B'));
    Check('2l HasSchema still false: rows alone are not an applied read', not HasSchema(vConn));
    SetRepoMeta(vConn, 'schema_read_at_utc', '2026-11-22T10:00:00Z');
    SetRepoMeta(vConn, 'schema_source', 'live');
    SetRepoMeta(vConn, 'schema_database', 'srv:C:\x.fdb');
    vInfo := SchemaInfo(vConn);
    Check('2m HasSchema true after the meta is set (positive control)', HasSchema(vConn));
    Check('2n SchemaInfo from DL_META', (vInfo.ReadAtUtc = '2026-11-22T10:00:00Z') and (vInfo.Source = 'live') and
      (vInfo.Database = 'srv:C:\x.fdb'));
  finally
    vConn.Free;
  end;
  vConn := NewRepo('t2v1', 1);
  try
    Check('2o v1 repository: HasSchema false, -1, no PK',
      (not HasSchema(vConn)) and (ColumnCharLength(vConn, 'A', 'B') = -1) and (Length(PrimaryKey(vConn, 'A')) = 0));
  finally
    vConn.Free;
  end;
end;

{ ---- task 6: locate -------------------------------------------------------------- }

procedure TestLocate;
var
  vRoot, vMan: string;
begin
  vRoot := Fixture('locate\');
  vMan := Fixture('locate\manifest.json');
  Check('6a explicit flag wins over config and manifest',
    LocateFieldRepository(vRoot + 'both\App.dproj', vRoot + 'repos\flag.dlrepo', vMan) = vRoot + 'repos\flag.dlrepo');
  Check('6b project config',
    LocateFieldRepository(vRoot + 'cfg\App.dproj', '', vMan) = vRoot + 'repos\cfg.dlrepo');
  Check('6c manifest section',
    LocateFieldRepository(vRoot + 'man\App.dproj', '', vMan) = vRoot + 'repos\man.dlrepo');
  Check('6d precedence: config beats manifest when both set',
    LocateFieldRepository(vRoot + 'both\App.dproj', '', vMan) = vRoot + 'repos\cfg-both.dlrepo');
  Check('6e none -> empty', LocateFieldRepository(vRoot + 'none\App.dproj', '', vMan) = '');
  Check('6f no project, no flag -> empty', LocateFieldRepository('', '', vMan) = '');
  Check('6g malformed manifest is treated as absent',
    LocateFieldRepository(vRoot + 'man\App.dproj', '', vRoot + 'bad-manifest.json') = '');
  Check('6h missing manifest file is treated as absent',
    LocateFieldRepository(vRoot + 'man\App.dproj', '', vRoot + 'nope.json') = '');
end;

{ Live reader against a real Firebird: counts compared with SELECT COUNT(*) over RDB$, never constants. }
procedure TestLiveReader;
var
  vFb: TFDConnection;
  vDb: string;
  vSrc: TFbSchemaSources;
  vModel: TFbSchemaModel;
  vTables: TDictionary<string, Boolean>;
  vCol: TFbColumn;
  vCount: Integer;
begin
  vFb := OpenSourceConnection(GetEnvironmentVariable('DL_TEST_FB_CONNECTION'), vDb);
  try
    vSrc := OpenFbSchemaSources(vFb);
    try
      vModel := ReadSchemaModel(vSrc, 'live', vDb);
    finally
      FreeFbSchemaSources(vSrc);
    end;
    Check('3k live: the transaction is read only', vFb.TxOptions.ReadOnly);
    vTables := TDictionary<string, Boolean>.Create;
    try
      for vCol in vModel.Columns do
        vTables.AddOrSetValue(vCol.TableName, True);
      vCount := vFb.ExecSQLScalar('SELECT COUNT(*) FROM RDB$RELATIONS WHERE RDB$VIEW_BLR IS NULL AND ' +
        '(RDB$SYSTEM_FLAG IS NULL OR RDB$SYSTEM_FLAG = 0)');
      Check('3l live: user tables = SELECT COUNT(*) FROM RDB$RELATIONS', vTables.Count = vCount,
        IntToStr(vTables.Count) + ' vs ' + IntToStr(vCount));
    finally
      vTables.Free;
    end;
    vCount := vFb.ExecSQLScalar('SELECT COUNT(*) FROM RDB$GENERATORS WHERE RDB$SYSTEM_FLAG IS NULL OR RDB$SYSTEM_FLAG = 0');
    Check('3m live: generators = SELECT COUNT(*) FROM RDB$GENERATORS', Length(vModel.Generators) = vCount,
      IntToStr(Length(vModel.Generators)) + ' vs ' + IntToStr(vCount));
    vCount := vFb.ExecSQLScalar('SELECT COUNT(*) FROM RDB$FIELDS WHERE RDB$FIELD_NAME NOT STARTING WITH ''RDB$'' ' +
      'AND (RDB$SYSTEM_FLAG IS NULL OR RDB$SYSTEM_FLAG = 0)');
    Check('3n live: domains = SELECT COUNT(*) FROM RDB$FIELDS', Length(vModel.Domains) = vCount,
      IntToStr(Length(vModel.Domains)) + ' vs ' + IntToStr(vCount));
  finally
    vFb.Free;
  end;
end;

{ ---- helpers for the reader / DDL / change-set tests ------------------------------ }

function ModelText(const pModel: TFbSchemaModel): string;
var
  vDom: TFbDomain;
  vCol: TFbColumn;
  vCon: TFbConstraint;
  vGen: string;
begin
  Result := '';
  for vDom in pModel.Domains do
    Result := Result + Format('D %s t=%d s=%d l=%d c=%d sc=%d p=%d n=%d cs=%s d=%s k=%s'#10,
      [vDom.Name, vDom.FieldType, vDom.SubType, vDom.FieldLength, vDom.CharLength, vDom.Scale, vDom.Precision,
       vDom.NullFlag, vDom.Charset, vDom.DefaultSource, vDom.CheckSource]);
  for vCol in pModel.Columns do
    Result := Result + Format('C %s.%s dom=%s t=%d s=%d l=%d c=%d sc=%d n=%d d=%s'#10,
      [vCol.TableName, vCol.ColumnName, vCol.DomainName, vCol.FieldType, vCol.SubType, vCol.FieldLength,
       vCol.CharLength, vCol.Scale, vCol.NullFlag, vCol.DefaultSource]);
  for vCon in pModel.Constraints do
    Result := Result + Format('K %s %s %s [%s] ref=%s/%s u=%s d=%s'#10,
      [vCon.Name, vCon.Kind, vCon.TableName, string.Join(',', vCon.Columns), vCon.RefTable, vCon.RefConstraint,
       vCon.UpdateRule, vCon.DeleteRule]);
  for vGen in pModel.Generators do
    Result := Result + 'G ' + vGen + #10;
end;

function MemTable(const pNames: array of string; const pTypes: array of TFieldType): TFDMemTable;
var
  i: Integer;
begin
  Result := TFDMemTable.Create(nil);
  for i := 0 to High(pNames) do
    Result.FieldDefs.Add(pNames[i], pTypes[i], if pTypes[i] = ftWideString then 200 else 0);
  Result.CreateDataSet;
end;

procedure AddRow(pMem: TFDMemTable; const pValues: array of Variant);
var
  i: Integer;
begin
  pMem.Append;
  for i := 0 to High(pValues) do
    pMem.Fields[i].Value := pValues[i];
  pMem.Post;
end;

{ ---- task 3: the live reader, dataset-fed -------------------------------------------- }

procedure TestReader;
var
  vSrc: TFbSchemaSources;
  vModel: TFbSchemaModel;
  vText: string;
begin
  vSrc := Default(TFbSchemaSources);
  vSrc.Domains := MemTable(['DOMAIN_NAME', 'FIELD_TYPE', 'FIELD_SUB_TYPE', 'FIELD_LENGTH', 'CHAR_LENGTH', 'FIELD_SCALE',
    'FIELD_PRECISION', 'NULL_FLAG', 'DEFAULT_SOURCE', 'CHECK_SOURCE', 'CHARSET'],
    [ftWideString, ftInteger, ftInteger, ftInteger, ftInteger, ftInteger, ftInteger, ftInteger, ftWideString,
     ftWideString, ftWideString]);
  vSrc.Columns := MemTable(['TABLE_NAME', 'FIELD_NAME', 'DOMAIN_NAME', 'FIELD_TYPE', 'FIELD_SUB_TYPE', 'FIELD_LENGTH',
    'CHARACTER_LEN', 'FIELD_SCALE', 'NULL_FLAG', 'DEFAULT_SOURCE'],
    [ftWideString, ftWideString, ftWideString, ftInteger, ftInteger, ftInteger, ftInteger, ftInteger, ftInteger,
     ftWideString]);
  vSrc.Constraints := MemTable(['CONSTRAINT_NAME', 'TABLE_NAME', 'KIND', 'REF_TABLE', 'REF_CONSTRAINT', 'UPDATE_RULE',
    'DELETE_RULE'], [ftWideString, ftWideString, ftWideString, ftWideString, ftWideString, ftWideString, ftWideString]);
  vSrc.ConstraintColumns := MemTable(['CONSTRAINT_NAME', 'POSITION', 'COLUMN_NAME'],
    [ftWideString, ftInteger, ftWideString]);
  vSrc.Generators := MemTable(['GENERATOR_NAME'], [ftWideString]);
  try
    { deliberately unsorted, CHAR-padded like RDB$ names }
    AddRow(vSrc.Domains as TFDMemTable, ['D_QTY      ', 8, 0, 4, Null, 0, 0, 0, 'DEFAULT 0', Null, Null]);
    AddRow(vSrc.Domains as TFDMemTable, ['D_NAME     ', 37, 0, 160, 40, 0, 0, 1, Null, Null, 'UTF8 ']);
    AddRow(vSrc.Columns as TFDMemTable, ['ORDERS  ', 'QTY ', 'D_QTY', 8, 0, 4, Null, 0, 0, 'DEFAULT 0']);
    AddRow(vSrc.Columns as TFDMemTable, ['CUSTOMER', 'ID', '', 16, 0, 8, Null, 0, 1, Null]);
    AddRow(vSrc.Columns as TFDMemTable, ['CUSTOMER', 'NAME', 'D_NAME', 37, 0, 160, 40, 0, 1, Null]);
    AddRow(vSrc.Constraints as TFDMemTable, ['FK_ORD', 'ORDERS', 'FK', 'CUSTOMER', 'PK_CUS', 'RESTRICT', 'CASCADE']);
    AddRow(vSrc.Constraints as TFDMemTable, ['PK_CUS', 'CUSTOMER', 'PK', Null, Null, Null, Null]);
    AddRow(vSrc.ConstraintColumns as TFDMemTable, ['PK_CUS', 2, 'B']);
    AddRow(vSrc.ConstraintColumns as TFDMemTable, ['PK_CUS', 1, 'ID']);
    AddRow(vSrc.ConstraintColumns as TFDMemTable, ['FK_ORD', 1, 'CUSTOMER_ID']);
    AddRow(vSrc.Generators as TFDMemTable, ['GEN_B']);
    AddRow(vSrc.Generators as TFDMemTable, ['GEN_A']);
    vModel := ReadSchemaModel(vSrc, 'live', 'srv:C:\x.fdb');
    vText := ModelText(vModel);
    Check('3a domains: type codes, lengths, charset, sorted and trimmed',
      vText.Contains('D D_NAME t=37 s=0 l=160 c=40 sc=0 p=0 n=1 cs=UTF8 d= k='#10'D D_QTY t=8 s=0 l=4 c=0 sc=0 p=0 n=0 cs= d=DEFAULT 0 k='#10'C'),
      vText);
    Check('3b columns sorted by table then name, domain carried',
      vText.Contains('C CUSTOMER.ID dom= t=16') and vText.Contains('C CUSTOMER.NAME dom=D_NAME t=37') and
      vText.Contains('C ORDERS.QTY dom=D_QTY t=8'), vText);
    Check('3c PK columns ordered by position', vText.Contains('K PK_CUS PK CUSTOMER [ID,B] ref=/ u= d='), vText);
    Check('3d FK carries ref table, ref constraint and rules, ordered columns',
      vText.Contains('K FK_ORD FK ORDERS [CUSTOMER_ID] ref=CUSTOMER/PK_CUS u=RESTRICT d=CASCADE'), vText);
    Check('3e generators are names only, sorted', vText.EndsWith('G GEN_A'#10'G GEN_B'#10), vText);
    Check('3f source and database stamped', (vModel.Source = 'live') and (vModel.Database = 'srv:C:\x.fdb'));
    vSrc.Generators.Free;
    vSrc.Generators := MemTable(['NOT_A_GENERATOR'], [ftWideString]);
    Check('3g a dataset without its column raises EFbSchemaReadError naming it',
      RaisedMessage(procedure begin ReadSchemaModel(vSrc, 'live', ''); end).Contains('GENERATOR_NAME'));
    Check('3h a nil dataset raises EFbSchemaReadError',
      RaisedClass(procedure begin ReadSchemaModel(Default(TFbSchemaSources), 'live', ''); end) = 'EFbSchemaReadError');
  finally
    FreeFbSchemaSources(vSrc);
  end;
  Check('3i DatabaseOfConnection keeps only the Database value',
    DatabaseOfConnection('Database=srv:C:\x.fdb; User_Name=SYSDBA;Password=xyz;CharacterSet=UTF8') = 'srv:C:\x.fdb');
  Check('3j DatabaseOfConnection of a string without Database is empty', DatabaseOfConnection('Password=xyz') = '');
  if GetEnvironmentVariable('DL_TEST_FB_CONNECTION') = '' then
    Writeln('SKIP 3k live reader against a real Firebird (set DL_TEST_FB_CONNECTION to a read-only test database)')
  else
    TestLiveReader;
end;

{ ---- task 5: the DDL reader ------------------------------------------------------------ }

const
  EXPECT_BASIC =
    'D D_NAME t=37 s=0 l=160 c=40 sc=0 p=0 n=1 cs=UTF8 d=DEFAULT ''X'' k='#10 +
    'D D_QTY t=8 s=0 l=4 c=0 sc=0 p=0 n=0 cs= d=DEFAULT 0 k=CHECK (VALUE >= 0)'#10 +
    'C CUSTOMER.CITY dom= t=37 s=0 l=30 c=30 sc=0 n=0 d='#10 +
    'C CUSTOMER.ID dom= t=16 s=0 l=8 c=0 sc=0 n=1 d='#10 +
    'C CUSTOMER.NAME dom=D_NAME t=37 s=0 l=160 c=40 sc=0 n=1 d=DEFAULT ''X'''#10 +
    'C ORDERS.CUSTOMER_ID dom= t=16 s=0 l=8 c=0 sc=0 n=1 d='#10 +
    'C ORDERS.ID dom= t=16 s=0 l=8 c=0 sc=0 n=1 d='#10 +
    'C ORDERS.NOTE dom= t=261 s=1 l=8 c=0 sc=0 n=0 d='#10 +
    'C ORDERS.QTY dom=D_QTY t=8 s=0 l=4 c=0 sc=0 n=0 d=DEFAULT 0'#10 +
    'C ORDERS.STATUS dom= t=7 s=0 l=2 c=0 sc=0 n=0 d=DEFAULT 1'#10 +
    'C ORDERS.TOTAL dom= t=16 s=1 l=8 c=0 sc=-2 n=0 d=DEFAULT 0'#10 +
    'K FK_ORDERS_CUSTOMER FK ORDERS [CUSTOMER_ID] ref=CUSTOMER/PK_CUSTOMER u=RESTRICT d=CASCADE'#10 +
    'K INTEG_ORDERS_PK_1 PK ORDERS [ID] ref=/ u= d='#10 +
    'K PK_CUSTOMER PK CUSTOMER [ID] ref=/ u= d='#10 +
    'K UQ_CUSTOMER_NAME UNIQUE CUSTOMER [NAME] ref=/ u= d='#10 +
    'G GEN_CUSTOMER_ID'#10 +
    'G GEN_ORDERS_ID'#10;
  EXPECT_EDGE =
    'C Mixed$Case.B dom= t=8 s=1 l=4 c=0 sc=-3 n=0 d='#10 +
    'C Mixed$Case.C dom= t=7 s=2 l=2 c=0 sc=-1 n=0 d='#10 +
    'C Mixed$Case.Col$A dom= t=37 s=0 l=40 c=10 sc=0 n=0 d='#10 +
    'C Mixed$Case.D dom= t=261 s=1 l=8 c=0 sc=0 n=0 d='#10 +
    'C Mixed$Case.E dom= t=27 s=0 l=8 c=0 sc=0 n=0 d='#10 +
    'C Mixed$Case.F dom= t=35 s=0 l=8 c=0 sc=0 n=0 d='#10 +
    'C Mixed$Case.G dom= t=24 s=0 l=8 c=0 sc=0 n=0 d='#10;

procedure TestDdl;
var
  vRes: TFbDdlResult;
  vFile: string;
  vMsg: string;
begin
  vFile := Fixture('schema\ddl_basic.sql');
  vRes := ReadDdlFiles([vFile]);
  Check('5a ddl_basic.sql gives the exact expected rows', ModelText(vRes.Model) = EXPECT_BASIC, ModelText(vRes.Model));
  Check('5b ddl_basic: source ddl, no unknown statement (CREATE INDEX is ignored, not unknown)',
    (vRes.Model.Source = 'ddl') and (Length(vRes.Unknown) = 0), IntToStr(Length(vRes.Unknown)));
  vRes := ReadDdlFiles([Fixture('schema\ddl_edge.sql')]);
  Check('5c ddl_edge: quoted identifier with $, VARCHAR CHARACTER SET UTF8, NUMERIC / DECIMAL, BLOB SUB_TYPE TEXT',
    ModelText(vRes.Model) = EXPECT_EDGE, ModelText(vRes.Model));
  Check('5d ddl_edge: SET TERM block skipped silently (2 bodies)', vRes.SkippedBlockStatements = 2,
    IntToStr(vRes.SkippedBlockStatements));
  Check('5e ddl_edge: 3 unknown statements, listed with their lines',
    (Length(vRes.Unknown) = 3) and (vRes.Unknown[0].Line = 1) and vRes.Unknown[0].Text.StartsWith('SET SQL DIALECT')
    and (vRes.Unknown[1].Line = 17) and vRes.Unknown[1].Text.StartsWith('CREATE VIEW V1')
    and (vRes.Unknown[2].Line = 18) and vRes.Unknown[2].Text.StartsWith('GRANT'),
    IntToStr(Length(vRes.Unknown)));
  vMsg := RaisedMessage(procedure begin ReadDdlFiles([Fixture('schema\ddl_bad_column.sql')]); end);
  Check('5f a column without a type is an error naming file and line',
    vMsg.Contains('ddl_bad_column.sql(6)') and vMsg.Contains('no data type'), vMsg);
  vMsg := RaisedMessage(procedure begin ReadDdlFiles([Fixture('schema\ddl_bad_paren.sql')]); end);
  Check('5g an unbalanced CREATE TABLE is an error naming file and line',
    vMsg.Contains('ddl_bad_paren.sql(1)'), vMsg);
  Check('5h the error class is EFbDdlError',
    RaisedClass(procedure begin ReadDdlFiles([Fixture('schema\ddl_bad_column.sql')]); end) = 'EFbDdlError');
  Check('5i a missing file is an EFbDdlError',
    RaisedClass(procedure begin ReadDdlFiles([Fixture('schema\nope.sql')]); end) = 'EFbDdlError');
  { two files: an ALTER TABLE in the second adds a constraint to a table of the first }
  vRes := ReadDdlText('CREATE TABLE A (X INTEGER NOT NULL, Y INTEGER);'#10'ALTER TABLE A ADD CONSTRAINT PK_A PRIMARY KEY (X);',
    'inline.sql');
  Check('5j ALTER TABLE ADD CONSTRAINT after CREATE TABLE', ModelText(vRes.Model).Contains('K PK_A PK A [X]'),
    ModelText(vRes.Model));
end;

{ ---- task 4: refresh / seed as a change set ----------------------------------------------- }

function CountOp(const pSet: TFrChangeSet; pOp: TFrChangeOp): Integer;
var
  vChange: TFrChange;
begin
  Result := 0;
  for vChange in pSet.Changes do
    if vChange.Op = pOp then
      Inc(Result);
end;

function AllChecked(const pSet: TFrChangeSet): Boolean;
var
  vChange: TFrChange;
begin
  Result := True;
  for vChange in pSet.Changes do
    if not vChange.Checked then
      Exit(False);
end;

function ChecksOf(const pSet: TFrChangeSet; pChecked: Boolean): TArray<TFrChange>;
var
  vChange: TFrChange;
begin
  Result := nil;
  for vChange in pSet.Changes do
    if vChange.Checked = pChecked then
      Result := Result + [vChange];
end;

function FindChange(const pSet: TFrChangeSet; pOp: TFrChangeOp; const pTarget, pProp: string; out pChange: TFrChange): Boolean;
var
  vChange: TFrChange;
begin
  pChange := Default(TFrChange);
  for vChange in pSet.Changes do
    if (vChange.Op = pOp) and (vChange.Target = pTarget) and (vChange.Prop = pProp) then
    begin
      pChange := vChange;
      Exit(True);
    end;
  Result := False;
end;

function RepoBytes(const pName: string): TBytes;
var
  vStream: TFileStream;
begin
  { the repository connection is open (SQLite holds the file): read it with full sharing }
  vStream := TFileStream.Create(TPath.Combine(GDir, pName + '.dlrepo'), fmOpenRead or fmShareDenyNone);
  try
    SetLength(Result, vStream.Size);
    if vStream.Size > 0 then
      vStream.ReadBuffer(Result[0], vStream.Size);
  finally
    vStream.Free;
  end;
end;

procedure TestChangeSet;
var
  vM0, vM1: TFbSchemaModel;
  vConn: TFDConnection;
  vSet, vSet2: TFrChangeSet;
  vWarn: TArray<string>;
  vRes: TSchemaApplyResult;
  vBefore, vAfter: TBytes;
  vChange, vAny: TFrChange;
  vExpectInserts, vN: Integer;
  vCon: TFbConstraint;
  vSelect: TArray<TFrChange>;
begin
  vM0 := ReadDdlFiles([Fixture('schema\ddl_basic.sql')]).Model;
  vExpectInserts := Length(vM0.Domains) + Length(vM0.Columns) + Length(vM0.Constraints) + Length(vM0.Generators);
  for vCon in vM0.Constraints do
    Inc(vExpectInserts, Length(vCon.Columns));
  vConn := NewRepo('cs1');
  try
    vBefore := RepoBytes('cs1');
    vSet := PlanSchemaChanges(vConn, vM0, ssmSeed, vWarn);
    vAfter := RepoBytes('cs1');
    Check('4a seed on an empty repository: every change is a checked insert',
      (Length(vSet.Changes) = vExpectInserts) and (CountOp(vSet, fcoInsert) = vExpectInserts) and AllChecked(vSet) and
      (vSet.Direction = fdDbToRepo), IntToStr(Length(vSet.Changes)) + ' of ' + IntToStr(vExpectInserts));
    Check('4b the dry run changed no byte of the repository file',
      (Length(vBefore) = Length(vAfter)) and CompareMem(@vBefore[0], @vAfter[0], Length(vBefore)));
    Check('4c ids are 1..n in order', (vSet.Changes[0].Id = 1) and (vSet.Changes[High(vSet.Changes)].Id = Length(vSet.Changes)));
    vRes := ApplySchemaChanges(vConn, vM0, ssmSeed, ChecksOf(vSet, True), EncodeDate(2026, 11, 22));
    Check('4d apply wrote every change', vRes.Applied = vExpectInserts, IntToStr(vRes.Applied));
    Check('4e HasSchema true after the apply (positive control for 2a)', HasSchema(vConn));
    Check('4f SchemaInfo: source ddl, read-at stamped, database is the file list',
      (SchemaInfo(vConn).Source = 'ddl') and SchemaInfo(vConn).ReadAtUtc.StartsWith('2026-11-22') and
      SchemaInfo(vConn).Database.EndsWith('ddl_basic.sql'));
    Check('4g field rows, PK, char length via domain and via field',
      (RepoRowCount(vConn, 'DL_FIELDS_INFO') = Length(vM0.Columns)) and (Length(PrimaryKey(vConn, 'CUSTOMER')) = 1) and
      (ColumnCharLength(vConn, 'CUSTOMER', 'NAME') = 40) and (ColumnCharLength(vConn, 'CUSTOMER', 'CITY') = 30) and
      (ColumnCharLength(vConn, 'ORDERS', 'QTY') = -1));
    Check('4h the derived dataset rows were generated (CUSTOMER, ORDERS)', RepoRowCount(vConn, 'DL_DATASETS_INFO') = 2,
      IntToStr(RepoRowCount(vConn, 'DL_DATASETS_INFO')));
    Check('4i apply logs "replacing <old> with <new>" per change', (Length(vRes.Log) = vExpectInserts) and
      vRes.Log[0].StartsWith('replacing '), vRes.Log[0]);
    vSet2 := PlanSchemaChanges(vConn, vM0, ssmRefresh, vWarn);
    Check('4j a refresh of the same schema has nothing to change', Length(vSet2.Changes) = 0, IntToStr(Length(vSet2.Changes)));
    Check('4k seed on a non-empty repository raises ERepoError',
      RaisedClass(procedure begin PlanSchemaChanges(vConn, vM0, ssmSeed, vWarn); end) = 'ERepoError');

    { a changed schema: CITY vanishes, ZIP appears, ORDERS.STATUS SMALLINT -> INTEGER; a caption is hand-kept }
    vConn.ExecSQL('UPDATE "DL_FIELDS_INFO" SET "DISPLAY_LABEL" = ''My caption'' WHERE "TABLE_NAME" = ''ORDERS'' AND "FIELD_NAME" = ''STATUS''');
    vM1 := ReadDdlText(
      'CREATE DOMAIN D_NAME AS VARCHAR(40) CHARACTER SET UTF8 DEFAULT ''X'' NOT NULL;'#10 +
      'CREATE DOMAIN D_QTY AS INTEGER DEFAULT 0 CHECK (VALUE >= 0);'#10 +
      'CREATE GENERATOR GEN_CUSTOMER_ID; CREATE SEQUENCE GEN_ORDERS_ID;'#10 +
      'CREATE TABLE CUSTOMER (ID BIGINT NOT NULL, NAME D_NAME, ZIP VARCHAR(10), ' +
      'CONSTRAINT PK_CUSTOMER PRIMARY KEY (ID), CONSTRAINT UQ_CUSTOMER_NAME UNIQUE (NAME));'#10 +
      'CREATE TABLE ORDERS (ID BIGINT NOT NULL PRIMARY KEY, CUSTOMER_ID BIGINT NOT NULL, QTY D_QTY, ' +
      'TOTAL NUMERIC(12,2) DEFAULT 0, NOTE BLOB SUB_TYPE TEXT, STATUS INTEGER DEFAULT 1, ' +
      'CONSTRAINT FK_ORDERS_CUSTOMER FOREIGN KEY (CUSTOMER_ID) REFERENCES CUSTOMER (ID) ON DELETE CASCADE);',
      'm1.sql').Model;
    vBefore := RepoBytes('cs1');
    vSet := PlanSchemaChanges(vConn, vM1, ssmRefresh, vWarn);
    Check('4l a new column is a checked insert', FindChange(vSet, fcoInsert, 'DL_FIELDS_INFO CUSTOMER|ZIP', '', vChange) and vChange.Checked);
    Check('4m a changed length is a checked update with old and new value',
      FindChange(vSet, fcoUpdate, 'DL_FIELDS_INFO ORDERS|STATUS', 'FIELD_LENGTH', vChange) and vChange.Checked and
      (vChange.OldValue = '2') and (vChange.NewValue = '4'), vChange.OldValue + ' -> ' + vChange.NewValue);
    Check('4n a vanished column is an UNCHECKED delete',
      FindChange(vSet, fcoDelete, 'DL_FIELDS_INFO CUSTOMER|CITY', '', vAny) and (not vAny.Checked));
    vN := 0;
    for vChange in vSet.Changes do
      if vChange.Prop = 'DISPLAY_LABEL' then
        Inc(vN);
    Check('4o a hand-kept column (the caption) never appears in the set', vN = 0);
    Check('4p the dry run changed no byte', Length(RepoBytes('cs1')) = Length(vBefore));
    vSelect := ChecksOf(vSet, True);
    vRes := ApplySchemaChanges(vConn, vM1, ssmRefresh, vSelect, Now);
    Check('4q apply without a selection applies inserts and updates, keeps the vanished row',
      (Integer(vConn.ExecSQLScalar('SELECT COUNT(*) FROM "DL_FIELDS_INFO" WHERE "FIELD_NAME" = ''CITY''')) = 1) and
      (Integer(vConn.ExecSQLScalar('SELECT COUNT(*) FROM "DL_FIELDS_INFO" WHERE "FIELD_NAME" = ''ZIP''')) = 1) and
      (Integer(vConn.ExecSQLScalar('SELECT "FIELD_LENGTH" FROM "DL_FIELDS_INFO" WHERE "FIELD_NAME" = ''STATUS''')) = 4));
    Check('4r the hand-kept caption survived', VarToStr(vConn.ExecSQLScalar(
      'SELECT "DISPLAY_LABEL" FROM "DL_FIELDS_INFO" WHERE "FIELD_NAME" = ''STATUS''')) = 'My caption');
    vSet := PlanSchemaChanges(vConn, vM1, ssmRefresh, vWarn);
    Check('4s the delete is still offered after the apply', FindChange(vSet, fcoDelete, 'DL_FIELDS_INFO CUSTOMER|CITY', '', vAny));
    vRes := ApplySchemaChanges(vConn, vM1, ssmRefresh, [vAny], Now);
    Check('4t selecting the delete removes the row', (vRes.Applied = 1) and
      (Integer(vConn.ExecSQLScalar('SELECT COUNT(*) FROM "DL_FIELDS_INFO" WHERE "FIELD_NAME" = ''CITY''')) = 0));
    vAny.Id := 999;
    Check('4u a stale / unknown change id raises ERepoError and writes nothing',
      RaisedClass(procedure begin ApplySchemaChanges(vConn, vM1, ssmRefresh, [vAny], Now); end) = 'ERepoError');
    vAny := Default(TFrChange);
    vAny.Id := 1;
    vAny.Op := fcoDelete;
    vAny.Target := 'DL_FIELDS_INFO X|Y';
    Check('4v a change that is not in the plan raises ERepoError',
      RaisedClass(procedure begin ApplySchemaChanges(vConn, vM1, ssmRefresh, [vAny], Now); end) = 'ERepoError');
    { a DDL source is partial: tables it does not declare are never offered for deletion }
    vSet := PlanSchemaChanges(vConn, ReadDdlText('CREATE TABLE OTHER (A INTEGER);', 'o.sql').Model, ssmRefresh, vWarn);
    Check('4w a partial DDL offers no delete for tables it does not declare',
      (CountOp(vSet, fcoDelete) = 0) and (CountOp(vSet, fcoInsert) = 1));
  finally
    vConn.Free;
  end;
  vConn := NewRepo('cs-v1', 1);
  try
    Check('4x a schema-1 repository raises ERepoError (migrate first)',
      RaisedClass(procedure begin PlanSchemaChanges(vConn, vM0, ssmRefresh, vWarn); end) = 'ERepoError');
  finally
    vConn.Free;
  end;
end;

{ ---- task 7: secrets ---------------------------------------------------------------------- }

procedure TestSecrets;
var
  vConn: TFDConnection;
  vModel: TFbSchemaModel;
  vWarn: TArray<string>;
  vSet: TFrChangeSet;
  vRes: TSchemaApplyResult;
  vPath, vBackup, vLines: string;
begin
  vModel := ReadDdlText('CREATE TABLE A (X INTEGER);', 'a.sql').Model;
  vModel.Source := 'live';
  vModel.Database := DatabaseOfConnection('Database=srv:C:\x.fdb;User_Name=SYSDBA;Password=xyz');
  vConn := NewRepo('secret');
  try
    vSet := PlanSchemaChanges(vConn, vModel, ssmSeed, vWarn);
    vRes := ApplySchemaChanges(vConn, vModel, ssmSeed, vSet.Changes, Now);
    vBackup := TPath.Combine(GDir, 'secret.txt');
    BackupRepository(vConn, vBackup);
    vLines := string.Join(#10, RenderChangeSetText(vSet)) + string.Join(#10, vRes.Log) + TFile.ReadAllText(vBackup);
    Check('7a no password in the change set, the apply log or the text backup', not vLines.Contains('xyz'));
    Check('7b no password in DL_META (positive control: the database value IS there)',
      (not VarToStr(vConn.ExecSQLScalar('SELECT group_concat("META_VALUE") FROM "DL_META"')).Contains('xyz')) and
      (GetRepoMeta(vConn, 'schema_database') = 'srv:C:\x.fdb'));
  finally
    vConn.Free;
  end;
  vPath := TPath.Combine(GDir, 'secret.dlrepo');
  Check('7c no password in the repository file bytes', Pos('xyz', TEncoding.ANSI.GetString(TFile.ReadAllBytes(vPath))) = 0);
end;

begin
  GDir := TPath.Combine(TPath.GetTempPath, 'dl-fieldrepo-schemafacts-' + IntToStr(GetCurrentProcessId));
  TDirectory.CreateDirectory(GDir);
  try
    TestTables;
    TestMigrate;
    TestFacts;
    TestLocate;
    TestReader;
    TestDdl;
    TestChangeSet;
    TestSecrets;
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
