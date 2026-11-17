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
  vTabs := RepoTables;
  vNames[0] := 'DL_META'; vNames[1] := 'DL_FIELDS_INFO'; vNames[2] := 'DL_DATASETS_INFO';
  vNames[3] := 'DL_ENUMVALUES'; vNames[4] := 'DL_ERROR_MESSAGES';
  vCounts[0] := 2; vCounts[1] := 40; vCounts[2] := 12; vCounts[3] := 6; vCounts[4] := 3;
  Check('1a RepoTables has 5 tables', Length(vTabs) = 5);
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

  FindRepoTable('DL_FIELDS_INFO', vTab);
  Check('2a TABLE_NAME string 68 not null pk1',
    vTab.FindColumn('TABLE_NAME', vCol) and (vCol.Kind = rckString) and (vCol.MaxLen = 68)
    and vCol.NotNull and (vCol.PkOrder = 1));
  Check('2b FIELD_NAME pk2', vTab.FindColumn('FIELD_NAME', vCol) and (vCol.PkOrder = 2));
  Check('2c VISIBLE boolean not null default 1',
    vTab.FindColumn('VISIBLE', vCol) and (vCol.Kind = rckBoolean) and vCol.NotNull and (vCol.DefaultSql = '1'));
  Check('2d DOC_SUMMARY text default Summary here',
    vTab.FindColumn('DOC_SUMMARY', vCol) and (vCol.Kind = rckText) and (vCol.DefaultSql = '''Summary here'''));
  Check('2e FIB$VERSION is absent (ruling A4)', not vTab.FindColumn('FIB$VERSION', vCol));
  Check('2e2 UI_TAG is the last FIELDS_INFO column', vTab.Columns[High(vTab.Columns)].Name = 'UI_TAG');
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
    Check('3b application_id reads back', ScalarInt(vConn, 'PRAGMA application_id') = cRepoApplicationId);
    Check('3c user_version reads back', ScalarInt(vConn, 'PRAGMA user_version') = cRepoSchemaVersion);
    Check('3d schema_version in DL_META', GetRepoMeta(vConn, 'schema_version') = IntToStr(cRepoSchemaVersion));
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
