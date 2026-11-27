program SchemaTests;

{$APPTYPE CONSOLE}

{ drag-lint 1.52 lane TTA -- console tests for DRagLint.FieldRepo.Schema.
  Output: one PASS / FAIL line per check, then "SUMMARY pass=N fail=M".
  Exit code 0 only when fail=0. Contract: design section 4 (FIB$VERSION skipped,
  owner ruling A4: column counts 2 / 40 / 12 / 6 / 3). }

uses
  Winapi.Windows,
  System.SysUtils,
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
  DRagLint.FieldRepo.Kinds in '..\..\src\sql\DRagLint.FieldRepo.Kinds.pas',
  DRagLint.FieldRepo.Schema in '..\..\src\sql\DRagLint.FieldRepo.Schema.pas';

var
  GPass: Integer = 0;
  GFail: Integer = 0;
  GDir: string;

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

function NewPath(const pName: string): string;
begin
  Result := TPath.Combine(GDir, pName + '.dlrepo');
end;

function RawConn(const pFile, pMode: string): TFDConnection;
begin
  Result := TFDConnection.Create(nil);
  Result.LoginPrompt := False;
  Result.Params.Values['DriverID'] := 'SQLite';
  Result.Params.Values['Database'] := pFile;
  Result.Params.Values['OpenMode'] := pMode;
  Result.Connected := True;
end;

function ScalarInt(pConn: TFDConnection; const pSql: string): Integer;
begin
  Result := pConn.ExecSQLScalar(pSql);
end;

{ First column of the first row, read through a TFDQuery that inherits the
  connection's FormatOptions (as every repository reader does). }
function ScalarStr(pConn: TFDConnection; const pSql: string): string;
var
  vQuery: TFDQuery;
begin
  vQuery := TFDQuery.Create(nil);
  try
    vQuery.Connection := pConn;
    vQuery.Open(pSql);
    Result := if vQuery.Eof then '' else vQuery.Fields[0].AsString;
  finally
    vQuery.Free;
  end;
end;

procedure TestContract;
var
  vTabs: TArray<TRepoTable>;
  vCol: TRepoColumn;
  vTab: TRepoTable;
  vCounts: array[0..4] of Integer;
  vNames: array[0..4] of string;
  vI: Integer;
  vOk: Boolean;
begin
  vTabs := RepoTablesFor(1);
  vNames[0] := 'DL_META'; vNames[1] := 'DL_FIELDS_INFO'; vNames[2] := 'DL_DATASETS_INFO';
  vNames[3] := 'DL_ENUMVALUES'; vNames[4] := 'DL_ERROR_MESSAGES';
  vCounts[0] := 2; vCounts[1] := 40; vCounts[2] := 12; vCounts[3] := 6; vCounts[4] := 3;
  Check('1a RepoTablesFor(1) has 5 tables', Length(vTabs) = 5);
  vOk := Length(vTabs) = 5;
  if vOk then
    for vI := 0 to 4 do
      vOk := vOk and (vTabs[vI].Name = vNames[vI]);
  Check('1b table order', vOk);
  vOk := Length(vTabs) = 5;
  if vOk then
    for vI := 0 to 4 do
      vOk := vOk and (Length(vTabs[vI].Columns) = vCounts[vI]);
  Check('1c column counts 2/40/12/6/3', vOk);
  Check('1d FindRepoTable case-insensitive', FindRepoTable('dl_fields_info', vTab) and (vTab.Name = 'DL_FIELDS_INFO'));
  Check('1e FindRepoTable unknown name is False (control)', not FindRepoTable('NOPE', vTab));

  vTab := vTabs[1];
  Check('2a TABLE_NAME string 68 not null pk1',
    vTab.FindColumn('TABLE_NAME', vCol) and (vCol.Kind = rckString) and (vCol.MaxLen = 68)
    and vCol.NotNull and (vCol.PkOrder = 1));
  Check('2b FIELD_NAME pk2', vTab.FindColumn('FIELD_NAME', vCol) and (vCol.PkOrder = 2));
  Check('2c VISIBLE boolean not null default 1',
    vTab.FindColumn('VISIBLE', vCol) and (vCol.Kind = rckBoolean) and vCol.NotNull and (vCol.DefaultSql = '1'));
  Check('2d DOC_SUMMARY text default Summary here',
    vTab.FindColumn('DOC_SUMMARY', vCol) and (vCol.Kind = rckText) and (vCol.DefaultSql = '''Summary here'''));
  Check('2e FIB$VERSION is absent (ruling A4)', not vTab.FindColumn('FIB$VERSION', vCol));
  Check('2e2 UI_TAG is the last v1 FIELDS_INFO column', vTab.Columns[High(vTab.Columns)].Name = 'UI_TAG');
  Check('2f PkColumns of FIELDS_INFO in order',
    (Length(vTab.PkColumns) = 2) and (vTab.PkColumns[0].Name = 'TABLE_NAME') and (vTab.PkColumns[1].Name = 'FIELD_NAME'));
  FindRepoTable('DL_DATASETS_INFO', vTab);
  Check('2g DATASETS_INFO has no FIB$VERSION and ends at CONDITIONS',
    not vTab.FindColumn('FIB$VERSION', vCol) and (vTab.Columns[High(vTab.Columns)].Name = 'CONDITIONS'));
  Check('2h UPDATE_ONLY_MODIFIED_FIELDS default 1',
    vTab.FindColumn('UPDATE_ONLY_MODIFIED_FIELDS', vCol) and (vCol.DefaultSql = '1'));
  FindRepoTable('DL_ERROR_MESSAGES', vTab);
  Check('2i ERROR_MESSAGES third column is CONSTR_TYPE not null default UNIQUE',
    (vTab.Columns[2].Name = 'CONSTR_TYPE') and vTab.Columns[2].NotNull
    and (vTab.Columns[2].DefaultSql = '''UNIQUE'''));
  FindRepoTable('DL_ENUMVALUES', vTab);
  Check('2j EVALUE byte default 0', vTab.FindColumn('EVALUE', vCol) and (vCol.Kind = rckByte) and (vCol.DefaultSql = '0'));
  Check('2k QuoteRepoIdent', QuoteRepoIdent('FIB$VERSION') = '"FIB$VERSION"');
  Check('2l RepoTableDdl single integer key is inline',
    (Pos('"DS_ID" INTEGER NOT NULL PRIMARY KEY', RepoTableDdl(RepoTables[2])) > 0));
  Check('2m RepoTableDdl composite key is table-level',
    (Pos('PRIMARY KEY ("TABLE_NAME", "FIELD_NAME")', RepoTableDdl(RepoTables[1])) > 0));
  Check('2n RepoTableDdl string CHECK',
    (Pos('CHECK (length("TABLE_NAME") <= 68)', RepoTableDdl(RepoTables[1])) > 0));
  Check('2o RepoTableDdl byte CHECK',
    (Pos('CHECK ("EVALUE" BETWEEN 0 AND 255)', RepoTableDdl(RepoTables[3])) > 0));
end;

{ FR-MODEL task 2: schema version 2 next to the still-valid version 1. }
procedure TestV2;
var
  vTabs: TArray<TRepoTable>;
  vV1, vV2, vRaw: TFDConnection;
  vFile, vFileV1, vCls: string;
  vCol: TRepoColumn;
  vTab: TRepoTable;
begin
  vTabs := RepoTablesFor(2);
  Check('12a v2 has 11 tables', Length(vTabs) = 11);
  Check('12b v2 order: DL_LAYOUT_EVENTS, DL_EXCEPTIONS, then the four schema tables',
    (vTabs[5].Name = 'DL_LAYOUT_EVENTS') and (vTabs[6].Name = 'DL_EXCEPTIONS'));
  Check('12c v2 DL_FIELDS_INFO has 43 columns: CALC_BODY (TEXT), DOMAIN_NAME, CHAR_LENGTH last',
    (Length(vTabs[1].Columns) = 43) and (vTabs[1].Columns[40].Name = 'CALC_BODY') and (vTabs[1].Columns[40].Kind = rckText)
    and (vTabs[1].Columns[41].Name = 'DOMAIN_NAME') and (vTabs[1].Columns[42].Name = 'CHAR_LENGTH'));
  Check('12d layout events table: 5 columns, 4-part key, EVENT_CODE text',
    (Length(vTabs[5].Columns) = 5) and (Length(vTabs[5].PkColumns) = 4)
    and vTabs[5].FindColumn('EVENT_CODE', vCol) and (vCol.Kind = rckText) and (vCol.PkOrder = 0));
  Check('12e exceptions table: 6 columns, 5-part key, REASON not null',
    (Length(vTabs[6].Columns) = 6) and (Length(vTabs[6].PkColumns) = 5)
    and vTabs[6].FindColumn('REASON', vCol) and vCol.NotNull and (vCol.PkOrder = 0));
  Check('12f RepoTablesFor(1) keeps 40 columns without CALC_BODY (positive control against 12c)',
    (Length(RepoTablesFor(1)[1].Columns) = 40) and not RepoTablesFor(1)[1].FindColumn('CALC_BODY', vCol));
  Check('12g RepoTablesFor(6) raises ERepoError (1.56: the range ends at 5)', RaisedClass(procedure begin RepoTablesFor(6); end) = 'ERepoError');
  Check('12h FindRepoTable finds a schema-2 table', FindRepoTable('dl_exceptions', vTab));

  vFile := NewPath('v2new');
  CreateRepository(vFile, 2);
  vV2 := OpenRepository(vFile, True);
  try
    Check('13a an explicit v2 repository is user_version 2 and RepoSchemaVersion reads it',
      (ScalarInt(vV2, 'PRAGMA user_version') = 2) and (RepoSchemaVersion(vV2) = 2));
    Check('13b DL_META schema_version is 2', GetRepoMeta(vV2, 'schema_version') = '2');
    Check('13c RepoRowCount works on a schema-2 table', RepoRowCount(vV2, 'DL_EXCEPTIONS') = 0);
  finally
    vV2.Free;
  end;

  vFileV1 := NewPath('v1new');
  CreateRepository(vFileV1, 1);
  vV1 := OpenRepository(vFileV1, True);
  try
    Check('14a explicit v1 repository opens and validates as v1', RepoSchemaVersion(vV1) = 1);
    Check('14b DL_META schema_version is 1', GetRepoMeta(vV1, 'schema_version') = '1');
    Check('14c v1 file has no DL_EXCEPTIONS table',
      ScalarInt(vV1, 'SELECT COUNT(*) FROM sqlite_master WHERE name = ''DL_EXCEPTIONS''') = 0);
    Check('14d v1 file is empty (RepoIsEmpty)', RepoIsEmpty(vV1));
  finally
    vV1.Free;
  end;
  Check('14e CreateRepository version 6 raises ERepoError',
    RaisedClass(procedure begin CreateRepository(NewPath('v6'), 6); end) = 'ERepoError');

  vRaw := RawConn(vFile, 'ReadWrite');
  try
    vRaw.ExecSQL('PRAGMA user_version = 3');
  finally
    vRaw.Free;
  end;
  vCls := RaisedClass(procedure begin OpenRepository(vFile, True).Free; end);
  Check('15 a v2 file that only says it is v3 raises ERepoSchemaError', vCls = 'ERepoSchemaError', vCls);

  vFile := NewPath('v2keys');
  CreateRepository(vFile, 2);
  vV2 := OpenRepository(vFile, False);
  try
    vV2.ExecSQL('INSERT INTO "DL_LAYOUT_EVENTS" ("TABLE_NAME","FIELD_NAME","LAYOUT_TYPE","EVENT_NAME") VALUES (''T'',''F'',''TcxGridCardView'',''OnGetText'')');
    Check('16a duplicate layout-event PK fails',
      RaisedClass(procedure begin
        vV2.ExecSQL('INSERT INTO "DL_LAYOUT_EVENTS" ("TABLE_NAME","FIELD_NAME","LAYOUT_TYPE","EVENT_NAME") VALUES (''T'',''F'',''TcxGridCardView'',''OnGetText'')');
      end) <> '');
    Check('16b the same field with another layout type or event is a distinct row',
      RaisedClass(procedure begin
        vV2.ExecSQL('INSERT INTO "DL_LAYOUT_EVENTS" ("TABLE_NAME","FIELD_NAME","LAYOUT_TYPE","EVENT_NAME") VALUES (''T'',''F'',''TdxTreeList'',''OnGetText'')');
      end) = '');
    Check('16c RepoIsEmpty ignores the two schema-2 tables', RepoIsEmpty(vV2));
    vV2.ExecSQL('INSERT INTO "DL_EXCEPTIONS" ("RULE_ID","REASON") VALUES (''r1'',''because'')');
    Check('16d DL_EXCEPTIONS key columns default to empty string',
      ScalarStr(vV2, 'SELECT "DATASET_KEY" || "TABLE_NAME" || "FIELD_NAME" || "PROP" FROM "DL_EXCEPTIONS"') = '');
    Check('16e duplicate exception PK fails',
      RaisedClass(procedure begin
        vV2.ExecSQL('INSERT INTO "DL_EXCEPTIONS" ("RULE_ID","REASON") VALUES (''r1'',''again'')');
      end) <> '');
    Check('16f DL_EXCEPTIONS without REASON fails',
      RaisedClass(procedure begin vV2.ExecSQL('INSERT INTO "DL_EXCEPTIONS" ("RULE_ID") VALUES (''r2'')'); end) <> '');
    Check('16g positive control: with REASON it inserts',
      RaisedClass(procedure begin
        vV2.ExecSQL('INSERT INTO "DL_EXCEPTIONS" ("RULE_ID","REASON") VALUES (''r2'',''x'')');
      end) = '');
  finally
    vV2.Free;
  end;
end;

{ EVCOLS: schema version 3. }
procedure TestV3;
var
  vTabs: TArray<TRepoTable>;
  vCol: TRepoColumn;
  vEvent: TFrEventColumn;
  vI: Integer;
  vOk: Boolean;
  vFile: string;
  vConn: TFDConnection;
begin
  vTabs := RepoTablesFor(3);
  Check('17a RepoTablesFor(3) is the v3 set, DL_GRID_COLUMNS last (1.55: schema 4 adds three tables after it)', (Length(vTabs) = 12)
    and (vTabs[11].Name = 'DL_GRID_COLUMNS'));
  vOk := Length(vTabs[1].Columns) = 49;
  vI := 43;
  for vEvent in FR_EVENT_COLUMNS do
  begin
    vOk := vOk and (vTabs[1].Columns[vI].Name = vEvent.Column) and (vTabs[1].Columns[vI].Kind = rckText) and not vTabs[1].Columns[vI].NotNull;
    Inc(vI);
  end;
  Check('17b DL_FIELDS_INFO: 49 columns, the six nullable event TEXT columns of FR_EVENT_COLUMNS last, in order', vOk);
  Check('17c they follow CHAR_LENGTH, the last v2 column', vTabs[1].Columns[42].Name = 'CHAR_LENGTH');
  Check('17d v2 has none of them (control)', not RepoTablesFor(2)[1].FindColumn('ONGETTEXT_BODY', vCol));
  Check('17e DL_GRID_COLUMNS: key form + view + column, table and field nullable, index not null',
    (Length(vTabs[11].PkColumns) = 3) and (vTabs[11].PkColumns[0].Name = 'FORM_NAME') and (vTabs[11].PkColumns[1].Name = 'VIEW_NAME')
    and (vTabs[11].PkColumns[2].Name = 'COLUMN_NAME') and vTabs[11].FindColumn('TABLE_NAME', vCol) and (not vCol.NotNull)
    and vTabs[11].FindColumn('FIELD_NAME', vCol) and (not vCol.NotNull) and vTabs[11].FindColumn('COLUMN_INDEX', vCol) and vCol.NotNull);
  vFile := NewPath('v3new');
  CreateRepository(vFile, 3);
  vConn := OpenRepository(vFile, False);
  try
    Check('17f a repository created at schema 3 is version 3', RepoSchemaVersion(vConn) = 3);
    vConn.ExecSQL('INSERT INTO "DL_GRID_COLUMNS" VALUES (''frmA'',''view1'',''colA'',''T'',''F'',0)');
    Check('17g two columns of one field, an unbound column, another form',
      RaisedClass(procedure begin
        vConn.ExecSQL('INSERT INTO "DL_GRID_COLUMNS" VALUES (''frmA'',''view1'',''colB'',''T'',''F'',1)');
        vConn.ExecSQL('INSERT INTO "DL_GRID_COLUMNS" VALUES (''frmA'',''view1'',''colC'',NULL,NULL,2)');
        vConn.ExecSQL('INSERT INTO "DL_GRID_COLUMNS" VALUES (''frmB'',''view1'',''colA'',''T'',''F'',0)');
      end) = '');
    Check('17h the same form + view + column is refused',
      RaisedClass(procedure begin vConn.ExecSQL('INSERT INTO "DL_GRID_COLUMNS" VALUES (''frmA'',''view1'',''colA'',''T'',''G'',9)'); end) <> '');
    Check('17i a column without an index is refused',
      RaisedClass(procedure begin vConn.ExecSQL('INSERT INTO "DL_GRID_COLUMNS" ("FORM_NAME","VIEW_NAME","COLUMN_NAME") VALUES (''a'',''b'',''c'')'); end) <> '');
    Check('17j RepoIsEmpty ignores DL_GRID_COLUMNS', RepoIsEmpty(vConn) and (RepoRowCount(vConn, 'DL_GRID_COLUMNS') = 4));
  finally
    vConn.Free;
  end;
end;

procedure TestCreateOpen;
var
  vFile, vFile2, vPlain: string;
  vConn, vRaw: TFDConnection;
  vCls: string;
begin
  vFile := NewPath('a');
  CreateRepository(vFile);
  vConn := OpenRepository(vFile, True);
  try
    Check('3a CreateRepository + OpenRepository(read-only) succeed', vConn.Connected);
    Check('3b application_id reads back', ScalarInt(vConn, 'PRAGMA application_id') = REPO_APPLICATION_ID);
    Check('3c user_version reads back', ScalarInt(vConn, 'PRAGMA user_version') = REPO_SCHEMA_VERSION);
    Check('3d schema_version in DL_META', GetRepoMeta(vConn, 'schema_version') = IntToStr(REPO_SCHEMA_VERSION));
  finally
    vConn.Free;
  end;
  vConn := OpenRepository(vFile, False);
  try
    SetRepoMeta(vConn, 'trim_probe', 'x  ');
    Check('3e OpenRepository keeps trailing blanks (StrsTrim off on the connection)',
      ScalarStr(vConn, 'SELECT "META_VALUE" FROM "DL_META" WHERE "META_KEY" = ''trim_probe''') = 'x  ',
      'got [' + ScalarStr(vConn, 'SELECT "META_VALUE" FROM "DL_META" WHERE "META_KEY" = ''trim_probe''') + ']');
  finally
    vConn.Free;
  end;
  Check('4a CreateRepository on existing file raises ERepoError',
    RaisedClass(procedure begin CreateRepository(vFile); end) = 'ERepoError');
  vFile2 := NewPath('missing');
  Check('4b OpenRepository on missing file raises ERepoError',
    RaisedClass(procedure begin OpenRepository(vFile2, True).Free; end) = 'ERepoError');
  Check('4c missing file was not created', not TFile.Exists(vFile2));
  Check('4d CreateRepository creates the folder',
    (RaisedClass(procedure begin CreateRepository(TPath.Combine(TPath.Combine(GDir, 'sub'), 'x.dlrepo')); end) = '')
    and TFile.Exists(TPath.Combine(TPath.Combine(GDir, 'sub'), 'x.dlrepo')));

  vPlain := NewPath('plain');
  vRaw := RawConn(vPlain, 'CreateUTF8');
  try
    vRaw.ExecSQL('CREATE TABLE other (x INTEGER)');
  finally
    vRaw.Free;
  end;
  vCls := RaisedClass(procedure begin OpenRepository(vPlain, True).Free; end);
  Check('5a plain SQLite file raises ERepoSchemaError', vCls = 'ERepoSchemaError', vCls);
  Check('5b positive control: real repository does not raise',
    RaisedClass(procedure begin OpenRepository(vFile, True).Free; end) = '');

  vFile2 := NewPath('v99');
  CreateRepository(vFile2);
  vRaw := RawConn(vFile2, 'ReadWrite');
  try
    vRaw.ExecSQL('PRAGMA user_version = 99');
  finally
    vRaw.Free;
  end;
  vCls := RaisedClass(procedure begin OpenRepository(vFile2, True).Free; end);
  Check('6 user_version 99 raises ERepoSchemaError', vCls = 'ERepoSchemaError', vCls);
end;

procedure TestStructural;
var
  vFile: string;
  vRaw: TFDConnection;
  vCls: string;
begin
  vFile := NewPath('missingcol');
  CreateRepository(vFile);
  vRaw := RawConn(vFile, 'ReadWrite');
  try
    vRaw.ExecSQL('ALTER TABLE DL_ENUMVALUES ADD COLUMN EXTRA INTEGER');
  finally
    vRaw.Free;
  end;
  vCls := RaisedClass(procedure begin OpenRepository(vFile, True).Free; end);
  Check('6b unexpected column raises ERepoSchemaError', vCls = 'ERepoSchemaError', vCls);

  vFile := NewPath('droptab');
  CreateRepository(vFile);
  vRaw := RawConn(vFile, 'ReadWrite');
  try
    vRaw.ExecSQL('DROP TABLE DL_ERROR_MESSAGES');
  finally
    vRaw.Free;
  end;
  vCls := RaisedClass(procedure begin OpenRepository(vFile, True).Free; end);
  Check('6c missing table raises ERepoSchemaError', vCls = 'ERepoSchemaError', vCls);

  vFile := NewPath('dropcol');
  CreateRepository(vFile);
  vRaw := RawConn(vFile, 'ReadWrite');
  try
    vRaw.ExecSQL('ALTER TABLE DL_ENUMVALUES DROP COLUMN DOCUMENTATION');
  finally
    vRaw.Free;
  end;
  vCls := RaisedClass(procedure begin OpenRepository(vFile, True).Free; end);
  Check('6d missing column raises ERepoSchemaError', vCls = 'ERepoSchemaError', vCls);

  vFile := NewPath('wrongapp');
  CreateRepository(vFile);
  vRaw := RawConn(vFile, 'ReadWrite');
  try
    vRaw.ExecSQL('PRAGMA application_id = 1');
  finally
    vRaw.Free;
  end;
  vCls := RaisedClass(procedure begin OpenRepository(vFile, True).Free; end);
  Check('6e wrong application_id raises ERepoSchemaError', vCls = 'ERepoSchemaError', vCls);
end;

procedure TestRows;
var
  vFile: string;
  vConn: TFDConnection;
  vQ: TFDQuery;
  vLong, vOk68: string;
begin
  vFile := NewPath('rows');
  CreateRepository(vFile);
  vConn := OpenRepository(vFile, False);
  try
    vConn.ExecSQL('INSERT INTO "DL_FIELDS_INFO" ("TABLE_NAME","FIELD_NAME") VALUES (''T1'',''F1'')');
    vQ := TFDQuery.Create(nil);
    try
      vQ.Connection := vConn;
      vQ.Open('SELECT * FROM "DL_FIELDS_INFO"');
      Check('7a VISIBLE defaults True', vQ.FieldByName('VISIBLE').AsBoolean);
      Check('7b TRIGGERED defaults False', not vQ.FieldByName('TRIGGERED').AsBoolean);
      Check('7c DOC_SUMMARY default', vQ.FieldByName('DOC_SUMMARY').AsString = 'Summary here');
      Check('7d UI_TAG default 0', vQ.FieldByName('UI_TAG').AsInteger = 0);
    finally
      vQ.Free;
    end;
    Check('8a duplicate key raises',
      RaisedClass(procedure begin
        vConn.ExecSQL('INSERT INTO "DL_FIELDS_INFO" ("TABLE_NAME","FIELD_NAME") VALUES (''T1'',''F1'')');
      end) <> '');
    Check('8a2 different key is accepted (control)',
      RaisedClass(procedure begin
        vConn.ExecSQL('INSERT INTO "DL_FIELDS_INFO" ("TABLE_NAME","FIELD_NAME") VALUES (''T1'',''F2'')');
      end) = '');
    vLong := StringOfChar('A', 69);
    vOk68 := StringOfChar('B', 68);
    Check('8b 69-char TABLE_NAME raises (CHECK)',
      RaisedClass(procedure begin
        vConn.ExecSQL('INSERT INTO "DL_FIELDS_INFO" ("TABLE_NAME","FIELD_NAME") VALUES (''' + vLong + ''',''X'')');
      end) <> '');
    Check('8c 68-char TABLE_NAME accepted (control)',
      RaisedClass(procedure begin
        vConn.ExecSQL('INSERT INTO "DL_FIELDS_INFO" ("TABLE_NAME","FIELD_NAME") VALUES (''' + vOk68 + ''',''X'')');
      end) = '');
    Check('8d EVALUE 256 raises (CHECK)',
      RaisedClass(procedure begin
        vConn.ExecSQL('INSERT INTO "DL_ENUMVALUES" ("ENUMTYPE","EORDER","NAME","ESTRING","EVALUE") VALUES (''E'',1,''n'',''s'',256)');
      end) <> '');
    Check('8e EVALUE 255 accepted (control)',
      RaisedClass(procedure begin
        vConn.ExecSQL('INSERT INTO "DL_ENUMVALUES" ("ENUMTYPE","EORDER","NAME","ESTRING","EVALUE") VALUES (''E'',2,''n'',''s'',255)');
      end) = '');
    Check('8f ERROR_MESSAGES CONSTR_TYPE defaults UNIQUE',
      (vConn.ExecSQL('INSERT INTO "DL_ERROR_MESSAGES" ("CONSTRAINT_NAME") VALUES (''C1'')') = 1)
      and (string(vConn.ExecSQLScalar('SELECT "CONSTR_TYPE" FROM "DL_ERROR_MESSAGES"')) = 'UNIQUE'));
    Check('8g DATASETS UPDATE_ONLY_MODIFIED_FIELDS defaults 1',
      (vConn.ExecSQL('INSERT INTO "DL_DATASETS_INFO" ("DS_ID") VALUES (1)') = 1)
      and (Integer(vConn.ExecSQLScalar('SELECT CAST("UPDATE_ONLY_MODIFIED_FIELDS" AS INTEGER) FROM "DL_DATASETS_INFO"')) = 1));
    Check('12a RepoRowCount FIELDS_INFO', RepoRowCount(vConn, 'DL_FIELDS_INFO') = 3);
    Check('12b RepoIsEmpty False when rows exist', not RepoIsEmpty(vConn));
    Check('12c RepoRowCount unknown table raises ERepoError',
      RaisedClass(procedure begin RepoRowCount(vConn, 'NOPE'); end) = 'ERepoError');
  finally
    vConn.Free;
  end;
  vFile := NewPath('empty');
  CreateRepository(vFile);
  vConn := OpenRepository(vFile, True);
  try
    Check('12d RepoIsEmpty True on fresh repository (DL_META ignored)', RepoIsEmpty(vConn));
  finally
    vConn.Free;
  end;
end;

procedure TestFieldClasses;
var
  vFile, vS: string;
  vConn: TFDConnection;
  vQ: TFDQuery;
begin
  vFile := NewPath('classes');
  CreateRepository(vFile);
  vConn := OpenRepository(vFile, False);
  try
    vConn.ExecSQL('INSERT INTO "DL_FIELDS_INFO" ("TABLE_NAME","FIELD_NAME") VALUES (''T'',''F'')');
    vConn.ExecSQL('INSERT INTO "DL_DATASETS_INFO" ("DS_ID") VALUES (1)');
    vConn.ExecSQL('INSERT INTO "DL_ENUMVALUES" ("ENUMTYPE","EORDER","NAME","ESTRING","EVALUE") VALUES (''E'',1,''n'',''s'',7)');
    vQ := TFDQuery.Create(nil);
    try
      vQ.Connection := vConn;
      vQ.Open('SELECT * FROM "DL_FIELDS_INFO"');
      vS := vQ.FieldByName('TABLE_NAME').ClassName;
      Check('9a string -> TWideStringField Size=68',
        (vQ.FieldByName('TABLE_NAME') is TWideStringField) and (vQ.FieldByName('TABLE_NAME').Size = 68),
        vS + ' size ' + IntToStr(vQ.FieldByName('TABLE_NAME').Size));
      Check('9b boolean -> TBooleanField', vQ.FieldByName('VISIBLE') is TBooleanField, vQ.FieldByName('VISIBLE').ClassName);
      Check('9c smallint -> TSmallintField', vQ.FieldByName('ALIGNMENT') is TSmallintField, vQ.FieldByName('ALIGNMENT').ClassName);
      Check('9d text -> TWideMemoField', vQ.FieldByName('DOC_SUMMARY') is TWideMemoField, vQ.FieldByName('DOC_SUMMARY').ClassName);
      Check('9e integer -> TIntegerField', vQ.FieldByName('DISPLAY_WIDTH') is TIntegerField, vQ.FieldByName('DISPLAY_WIDTH').ClassName);
      vQ.Open('SELECT * FROM "DL_ENUMVALUES"');
      Check('9f byte -> TSmallintField', vQ.FieldByName('EVALUE') is TSmallintField, vQ.FieldByName('EVALUE').ClassName);
      vQ.Open('SELECT * FROM "DL_DATASETS_INFO"');
      Check('9g DS_ID class is integer-like',
        (vQ.FieldByName('DS_ID') is TIntegerField) or (vQ.FieldByName('DS_ID') is TLargeintField)
        or (vQ.FieldByName('DS_ID') is TAutoIncField), vQ.FieldByName('DS_ID').ClassName);
    finally
      vQ.Free;
    end;
  finally
    vConn.Free;
  end;
end;

procedure TestMeta;
var
  vFile: string;
  vConn: TFDConnection;
begin
  vFile := NewPath('meta');
  CreateRepository(vFile);
  vConn := OpenRepository(vFile, False);
  try
    SetRepoMeta(vConn, 'source_database', 'C:\x\y.fdb');
    Check('10a Set/GetRepoMeta round-trip', GetRepoMeta(vConn, 'source_database') = 'C:\x\y.fdb');
    SetRepoMeta(vConn, 'source_database', 'second');
    Check('10b SetRepoMeta overwrites', GetRepoMeta(vConn, 'source_database') = 'second');
    Check('10c GetRepoMeta unknown key is empty', GetRepoMeta(vConn, 'nope') = '');
  finally
    vConn.Free;
  end;
  vConn := OpenRepository(vFile, True);
  try
    Check('10d read-only connection rejects SetRepoMeta',
      RaisedClass(procedure begin SetRepoMeta(vConn, 'k', 'v'); end) <> '');
    Check('10e read-only connection still reads', GetRepoMeta(vConn, 'source_database') = 'second');
  finally
    vConn.Free;
  end;
end;

begin
  GDir := TPath.Combine(TPath.GetTempPath, 'dl-fieldrepo-schema-' + IntToStr(GetCurrentProcessId));
  TDirectory.CreateDirectory(GDir);
  try
    TestContract;
    TestV2;
  TestV3;
    TestCreateOpen;
    TestStructural;
    TestRows;
    TestFieldClasses;
    TestMeta;
    Check('11 DefaultRepoPath', DefaultRepoPath('C:\P\App.dproj') = 'C:\P\_DL-REPO\App.dlrepo');
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
