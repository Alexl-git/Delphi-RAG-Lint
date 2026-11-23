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
  DRagLint.FieldRepo.Locate in '..\..\src\sql\DRagLint.FieldRepo.Locate.pas';

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

begin
  GDir := TPath.Combine(TPath.GetTempPath, 'dl-fieldrepo-schemafacts-' + IntToStr(GetCurrentProcessId));
  TDirectory.CreateDirectory(GDir);
  try
    TestTables;
    TestMigrate;
    TestFacts;
    TestLocate;
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
