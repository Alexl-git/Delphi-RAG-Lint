program ModelTests;

{$APPTYPE CONSOLE}

{ drag-lint 1.53 lane FR-MODEL -- console tests for the repository model v2: field kinds + macros, field use
  (S1-S5), exceptions, repo check, migrate, change set. Output: one PASS / FAIL line per check, then
  "SUMMARY pass=N fail=M". Exit code 0 only when fail=0. Fixture: tests\fixtures\fieldrepo\model_kinds.txt
  (every kind, a lookup, a calc chain, a cycle, field use, an exception) and golden.dlrepo.txt (v1). }

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.Variants,
  System.StrUtils,
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
  DRagLint.FieldRepo.Kinds in '..\..\src\sql\DRagLint.FieldRepo.Kinds.pas',
  DRagLint.FieldRepo.Exceptions in '..\..\src\sql\DRagLint.FieldRepo.Exceptions.pas',
  DRagLint.FieldRepo.Check in '..\..\src\sql\DRagLint.FieldRepo.Check.pas',
  DRagLint.FieldRepo.Migrate in '..\..\src\sql\DRagLint.FieldRepo.Migrate.pas',
  DRagLint.FieldRepo.ChangeSet in '..\..\src\sql\DRagLint.FieldRepo.ChangeSet.pas';

var
  GPass: Integer = 0;
  GFail: Integer = 0;
  GDir: string;
  GFix: string;
  GSeq: Integer = 0;

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

function Fixture(const pName: string): string;
begin
  Result := TPath.Combine(GFix, pName);
end;

function NewPath: string;
begin
  Inc(GSeq);
  Result := TPath.Combine(GDir, 'm' + IntToStr(GSeq) + '.dlrepo');
end;

{ A fresh repository of the given version restored from a fixture; returns the open read-write connection. }
function NewRepoFrom(const pFixture: string; pVersion: Integer): TFDConnection;
var
  vPath: string;
begin
  vPath := NewPath;
  CreateRepository(vPath, pVersion);
  Result := OpenRepository(vPath, False);
  RestoreRepository(Result, Fixture(pFixture), False);
end;

function ScalarInt(pConn: TFDConnection; const pSql: string): Integer;
begin
  Result := pConn.ExecSQLScalar(pSql);
end;

function ScalarStr(pConn: TFDConnection; const pSql: string): string;
var
  vQuery: TFDQuery;
begin
  vQuery := TFDQuery.Create(nil);
  try
    vQuery.Connection := pConn;
    vQuery.Open(pSql);
    Result := if vQuery.Eof then '<norow>' else if vQuery.Fields[0].IsNull then '<null>' else vQuery.Fields[0].AsString;
  finally
    vQuery.Free;
  end;
end;

function Join(const pItems: TArray<string>): string;
begin
  Result := string.Join(',', pItems);
end;

function FileBytesText(const pFile: string): string;
begin
  Result := TEncoding.ASCII.GetString(TFile.ReadAllBytes(pFile));
end;

{ ---- task 1: kinds and macros ------------------------------------------------ }

procedure CheckDeps(const pName, pBody, pWant: string);
begin
  Check(pName, Join(CalcDependencies(pBody, 'T')) = pWant, Join(CalcDependencies(pBody, 'T')));
end;

procedure TestKinds;
var
  vMacros: TArray<TFrMacro>;
  vKind: TFrFieldKind;
begin
  Check('K1a NULL reads as data', FrKindFromCode(Null) = frkData);
  Check('K1b code 1 is data, 2 calc, 3 lookup, 4 internal-calc, 5 aggregate, 10 graphical',
    (FrKindFromCode(1) = frkData) and (FrKindFromCode(2) = frkCalc) and (FrKindFromCode(3) = frkLookup)
    and (FrKindFromCode(4) = frkInternalCalc) and (FrKindFromCode(5) = frkAggregate)
    and (FrKindFromCode(10) = frkGraphical));
  Check('K1c unknown code 7 raises EFrKindError', RaisedClass(procedure begin FrKindFromCode(7); end) = 'EFrKindError');
  Check('K1d code 0 raises EFrKindError (control: 1 does not)',
    (RaisedClass(procedure begin FrKindFromCode(0); end) = 'EFrKindError')
    and (RaisedClass(procedure begin FrKindFromCode(1); end) = ''));
  Check('K1e FrKindCodeKnown mirrors it', FrKindCodeKnown(Null) and FrKindCodeKnown(10) and not FrKindCodeKnown(7));
  Check('K1f code round trip for every kind', (FrKindToCode(frkData) = 1) and (FrKindToCode(frkGraphical) = 10)
    and (FrKindFromCode(FrKindToCode(frkAggregate)) = frkAggregate));
  vKind := frkInternalCalc;
  Check('K1g body kinds are calc, internal-calc, aggregate', FrKindHasBody(vKind) and FrKindHasBody(frkCalc)
    and FrKindHasBody(frkAggregate) and not FrKindHasBody(frkLookup) and not FrKindHasBody(frkData));

  vMacros := ParseMacros('{{TOTAL}} := {{QTY}} * {{p_1$}};');
  Check('K2a ParseMacros finds three macros in order',
    (Length(vMacros) = 3) and (vMacros[0].Name = 'TOTAL') and (vMacros[1].Name = 'QTY') and (vMacros[2].Name = 'p_1$'));
  Check('K2b offset and length of a macro', (vMacros[1].Offset = 14) and (vMacros[1].Len = 7));
  Check('K2c a body without macros gives none (control)', Length(ParseMacros('Result := 1;')) = 0);
  Check('K2d {{TABLE.FIELD}} is an error', RaisedClass(procedure begin ParseMacros('{{T.F}}'); end) = 'EFrKindError');
  Check('K2e unterminated {{ is an error naming the offset',
    RaisedMessage(procedure begin ParseMacros('ab {{QTY'); end).Contains('offset 4'),
    RaisedMessage(procedure begin ParseMacros('ab {{QTY'); end));
  Check('K2f {{{{ is not an escape', RaisedClass(procedure begin ParseMacros('{{{{A}}}}'); end) = 'EFrKindError');
  Check('K2g an empty or numeric-first identifier is an error',
    (RaisedClass(procedure begin ParseMacros('{{}}'); end) = 'EFrKindError')
    and (RaisedClass(procedure begin ParseMacros('{{1A}}'); end) = 'EFrKindError'));

  Check('K3a CalcDependencies of the spec example = [QTY, PRICE]',
    Join(CalcDependencies('{{TOTAL}} := {{QTY}} * {{PRICE}};', 'TOTAL')) = 'QTY,PRICE');
  Check('K3b a right-hand use of the field itself stays a dependency',
    Join(CalcDependencies('{{TOTAL}} := {{TOTAL}} + 1;', 'TOTAL')) = 'TOTAL');
  Check('K3c duplicates collapse case-insensitively, first spelling kept',
    Join(CalcDependencies('{{T}} := {{A}} + {{a}} + {{B}};', 'T')) = 'A,B');
  Check('K3d assignment to ANOTHER field counts as a dependency',
    Join(CalcDependencies('{{X}} := 1; {{T}} := {{X}};', 'T')) = 'X');
  Check('K3e an aggregate expression', Join(CalcDependencies('SUM({{QTY}})', 'SUMQ')) = 'QTY');
  Check('K3f no macros = no dependencies (control)', Length(CalcDependencies('Result := 1;', 'T')) = 0);

  CheckDeps('K4a a member assignment is the target', '{{T}}.AsFloat := {{Q}}.AsInteger * {{P}}.AsFloat;', 'Q,P');
  CheckDeps('K4b blanks and line breaks inside the target', '{{T}} .'#13#10'  AsFloat'#9':= {{Q}}.AsInteger;', 'Q');
  CheckDeps('K4c Clear writes too', 'if {{Q}}.IsNull then'#13#10'  {{T}}.Clear'#13#10'else'#13#10'  {{T}}.AsFloat := 1;', 'Q');
  CheckDeps('K4d a read of the field before it is assigned stays', 'if {{T}}.IsNull then {{T}}.AsFloat := 1;', 'T');
  CheckDeps('K4e the field in its own expression stays', '{{T}}.AsFloat := {{T}}.AsFloat + 1;', 'T');
  CheckDeps('K4f a read behind an assignment statement is no dependency', '{{T}}.AsFloat := {{Q}}.AsFloat; if {{T}}.AsFloat > 9 then {{T}}.AsFloat := 9;', 'Q');
  CheckDeps('K4g a semicolon in a string or comment ends no statement', '{{T}}.AsString := ''a;'' { ; } + // ;'#13#10'  (* ; *) {{T}}.AsString;', 'T');
  CheckDeps('K4h a comparison is no assignment', 'if {{T}}.AsFloat = 1 then {{T}}.AsFloat := 2;', 'T');
  CheckDeps('K4i another field''s member target stays a dependency', '{{X}}.AsFloat := 1; {{T}}.AsFloat := 2;', 'X');
  CheckDeps('K4j a member of a member is a read', '{{T}}.DataSet.Tag := 1;', 'T');
end;

{ ---- task 4: migrate ---------------------------------------------------------- }

{ The v1 backup text of the migrate test repository, transformed the way the migration must change it. }
function ExpectedMigrated(const pV1Text: string): string;
var
  vLines: TArray<string>;
  vOut: TStringList;
  vLine, vCur: string;
begin
  vLines := pV1Text.Replace('#DLREPO 1', '#DLREPO 3').Replace('META_VALUE=1', 'META_VALUE=3').Split([#13#10]);
  vOut := TStringList.Create;
  try
    vCur := '';
    for vLine in vLines do
    begin
      if vLine.StartsWith('[') then
        vCur := vLine;
      if (vCur = '[DL_FIELDS_INFO ORDERS|CALCX]') and (vLine = 'PRIMARY_KEY=false') then
        vOut.Add('FIELD_KIND=2');
      if (vCur = '[DL_FIELDS_INFO ORDERS|CALCY]') and (vLine = 'FIELD_KIND=1') then
        vOut.Add('FIELD_KIND=2')
      else
        vOut.Add(vLine);
    end;
    Result := vOut.Text;
  finally
    vOut.Free;
  end;
  { TStringList.Text ends with a line break; the split left one empty last element, so the join is exact }
  Result := Result.Substring(0, Length(Result) - Length(sLineBreak))
    + '#end DL_LAYOUT_EVENTS 0' + #13#10 + '#end DL_EXCEPTIONS 0' + #13#10 + '#end DL_DOMAINS 0' + #13#10 + '#end DL_CONSTRAINTS 0' + #13#10 + '#end DL_CONSTRAINT_COLUMNS 0' + #13#10 + '#end DL_GENERATORS 0' + #13#10 + '#end DL_GRID_COLUMNS 0' + #13#10;
end;

procedure TestMigrate;
var
  vPath, vText, vExpect: string;
  vConn: TFDConnection;
  vBefore, vAfter: TBytes;
  vRes, vRes2: TFrMigrateResult;
  vV1Text: string;
begin
  { golden (v1) migrated: byte expectation }
  vPath := NewPath;
  CreateRepository(vPath, 1);
  vConn := OpenRepository(vPath, False);
  try
    RestoreRepository(vConn, Fixture('golden.dlrepo.txt'), False);
    vConn.ExecSQL('INSERT INTO "DL_FIELDS_INFO" ("TABLE_NAME","FIELD_NAME","ISCALCULATED") VALUES (''ORDERS'',''CALCX'',1)');
    vConn.ExecSQL('INSERT INTO "DL_FIELDS_INFO" ("TABLE_NAME","FIELD_NAME","ISCALCULATED","FIELD_KIND") VALUES (''ORDERS'',''CALCY'',1,1)');
    vConn.ExecSQL('INSERT INTO "DL_FIELDS_INFO" ("TABLE_NAME","FIELD_NAME","ISCALCULATED","FIELD_KIND") VALUES (''ORDERS'',''ODD'',1,10)');
    BackupRepository(vConn, TPath.Combine(GDir, 'v1-before.txt'));
  finally
    vConn.Free;
  end;
  vV1Text := FileBytesText(TPath.Combine(GDir, 'v1-before.txt'));
  vBefore := TFile.ReadAllBytes(vPath);
  vRes := MigrateRepository(vPath, False);
  vAfter := TFile.ReadAllBytes(vPath);
  Check('M1a dry run reports 2 calc rows and the plan line (NULL and 1 count, 10 does not)',
    (not vRes.AlreadyCurrent) and (not vRes.Applied) and (vRes.CalcRows = 2)
    and (vRes.Plan = 'v1 -> v3: add DL_FIELDS_INFO.CALC_BODY, DOMAIN_NAME, CHAR_LENGTH, ONGETTEXT_BODY, ONSETTEXT_BODY, ONVALIDATE_BODY, '
      + 'ONCHANGE_BODY, GRID_DISPLAYTEXT_BODY, GRID_DRAWCELL_BODY, create DL_LAYOUT_EVENTS, DL_EXCEPTIONS, DL_DOMAINS, DL_CONSTRAINTS, '
      + 'DL_CONSTRAINT_COLUMNS, DL_GENERATORS, DL_GRID_COLUMNS, FIELD_KIND 2 for 2 ISCALCULATED rows, ALIGNMENT -2 to NULL in 0 rows, user_version 3'), vRes.Plan);
  Check('M1b dry run leaves the file byte-identical', (Length(vBefore) = Length(vAfter))
    and CompareMem(@vBefore[0], @vAfter[0], Length(vBefore)));
  Check('M1c dry run wrote no backup file', Length(TDirectory.GetFiles(GDir, ExtractFileName(vPath) + '.before-migrate-*')) = 0);

  vRes := MigrateRepository(vPath, True);
  Check('M2a apply reports Applied and the backup name', vRes.Applied and (vRes.CalcRows = 2)
    and vRes.BackupFile.Contains('.before-migrate-') and TFile.Exists(vRes.BackupFile), vRes.BackupFile);
  Check('M2b the before-migrate backup is the v1 text byte for byte', FileBytesText(vRes.BackupFile) = vV1Text);
  vConn := OpenRepository(vPath, False);
  try
    Check('M2c user_version 3 and DL_META schema_version 3', (RepoSchemaVersion(vConn) = 3)
      and (ScalarStr(vConn, 'SELECT "META_VALUE" FROM "DL_META" WHERE "META_KEY" = ''schema_version''') = '3'));
    Check('M2d ISCALCULATED rows with kind NULL / 1 became kind 2',
      (ScalarInt(vConn, 'SELECT "FIELD_KIND" FROM "DL_FIELDS_INFO" WHERE "FIELD_NAME" = ''CALCX''') = 2)
      and (ScalarInt(vConn, 'SELECT "FIELD_KIND" FROM "DL_FIELDS_INFO" WHERE "FIELD_NAME" = ''CALCY''') = 2));
    Check('M2e a row with another kind keeps it (control)',
      ScalarInt(vConn, 'SELECT "FIELD_KIND" FROM "DL_FIELDS_INFO" WHERE "FIELD_NAME" = ''ODD''') = 10);
    Check('M2f the new tables exist and are empty, CALC_BODY is NULL everywhere',
      (RepoRowCount(vConn, 'DL_LAYOUT_EVENTS') = 0) and (RepoRowCount(vConn, 'DL_EXCEPTIONS') = 0)
      and (ScalarInt(vConn, 'SELECT COUNT(*) FROM "DL_FIELDS_INFO" WHERE "CALC_BODY" IS NOT NULL') = 0));
    BackupRepository(vConn, TPath.Combine(GDir, 'v2-after.txt'));
  finally
    vConn.Free;
  end;
  vText := FileBytesText(TPath.Combine(GDir, 'v2-after.txt'));
  Check('M2g backup(migrated) starts with #DLREPO 3 and ends with the empty trailers',
    vText.StartsWith('#DLREPO 3' + #13#10) and vText.EndsWith('#end DL_LAYOUT_EVENTS 0' + #13#10 + '#end DL_EXCEPTIONS 0' + #13#10 + '#end DL_DOMAINS 0' + #13#10 + '#end DL_CONSTRAINTS 0' + #13#10 + '#end DL_CONSTRAINT_COLUMNS 0' + #13#10 + '#end DL_GENERATORS 0' + #13#10 + '#end DL_GRID_COLUMNS 0' + #13#10));
  vExpect := ExpectedMigrated(vV1Text);
  Check('M2h the migrated backup differs from the v1 backup ONLY by magic, schema_version, FIELD_KIND 2 and the trailers',
    vText = vExpect, 'lengths ' + IntToStr(Length(vText)) + ' vs ' + IntToStr(Length(vExpect)));  vRes2 := MigrateRepository(vPath, True);
  Check('M3a a second run says already current and writes no backup', vRes2.AlreadyCurrent and (vRes2.BackupFile = ''));
  Check('M3b the second dry run is also already current', MigrateRepository(vPath, False).AlreadyCurrent and (vRes2.Plan = ''));
  Check('M4 migrating a missing file raises ERepoError',
    RaisedClass(procedure begin MigrateRepository(TPath.Combine(GDir, 'nope.dlrepo'), False); end) = 'ERepoError');
end;

{ The v2 backup text as the migration must change it: TOTAL has its OnGetText column, AMOUNT no ALIGNMENT. }
function ExpectedFromV2(const pText: string): string;
begin
  Result := pText.Replace('#DLREPO 2', '#DLREPO 3').Replace('META_VALUE=2', 'META_VALUE=3').Replace('ALIGNMENT=-2' + #13#10, '')
    .Replace(' |{{TOTAL}} := {{AMOUNT}} * 2;' + #13#10, ' |{{TOTAL}} := {{AMOUNT}} * 2;' + #13#10 + 'ONGETTEXT_BODY:' + #13#10
      + ' |Text := ''T'';' + #13#10)
    .Replace('[DL_LAYOUT_EVENTS ORDERS|TOTAL|Field|OnGetText]' + #13#10 + 'EVENT_CODE:' + #13#10 + ' |Text := ''T'';' + #13#10 + #13#10, '')
    .Replace('#end DL_LAYOUT_EVENTS 5', '#end DL_LAYOUT_EVENTS 4') + '#end DL_GRID_COLUMNS 0' + #13#10;
end;

{ EVCOLS: schema 2 -> 3. }
procedure TestMigrateV2;
var
  vPath, vText: string;
  vConn: TFDConnection;
  vRes: TFrMigrateResult;
  vBefore, vAfter: TBytes;
begin
  vPath := NewPath;
  CreateRepository(vPath, 2);
  vConn := OpenRepository(vPath, False);
  try
    RestoreRepository(vConn, Fixture('golden_v2.txt'), False);
    vConn.ExecSQL('UPDATE "DL_FIELDS_INFO" SET "ALIGNMENT" = -2 WHERE "FIELD_NAME" = ''AMOUNT''');
    vConn.ExecSQL('INSERT INTO "DL_LAYOUT_EVENTS" VALUES (''ORDERS'',''TOTAL'',''Field'',''OnGetText'',''Text := ''''T'''';'')');
    vConn.ExecSQL('INSERT INTO "DL_LAYOUT_EVENTS" VALUES (''ORDERS'',''GONE'',''Field'',''OnGetText'',''x;'')');
    vConn.ExecSQL('INSERT INTO "DL_LAYOUT_EVENTS" VALUES (''ORDERS'',''TOTAL'',''Field'',''OnOther'',''y;'')');
    vConn.ExecSQL('INSERT INTO "DL_LAYOUT_EVENTS" VALUES (''ORDERS'',''NOTE'',''Card'',''OnGetText'',''z;'')');
    BackupRepository(vConn, TPath.Combine(GDir, 'v2-before.txt'));
  finally
    vConn.Free;
  end;
  vBefore := TFile.ReadAllBytes(vPath);
  vRes := MigrateRepository(vPath, False);
  vAfter := TFile.ReadAllBytes(vPath);
  Check('M5a v2 -> v3 plan', vRes.Plan = 'v2 -> v3: add DL_FIELDS_INFO.ONGETTEXT_BODY, ONSETTEXT_BODY, ONVALIDATE_BODY, ONCHANGE_BODY, '
    + 'GRID_DISPLAYTEXT_BODY, GRID_DRAWCELL_BODY, create DL_GRID_COLUMNS, ALIGNMENT -2 to NULL in 1 rows, move 1 Field events into columns, user_version 3', vRes.Plan);
  Check('M5b dry run leaves the file byte-identical', (Length(vBefore) = Length(vAfter)) and CompareMem(@vBefore[0], @vAfter[0], Length(vBefore)));
  vRes := MigrateRepository(vPath, True);
  vText := FileBytesText(TPath.Combine(GDir, 'v2-before.txt'));
  Check('M5c the before-migrate backup is the #DLREPO 2 text byte for byte', vRes.Applied and (FileBytesText(vRes.BackupFile) = vText));
  vConn := OpenRepository(vPath, False);
  try
    BackupRepository(vConn, TPath.Combine(GDir, 'v3-after.txt'));
    Check('M5d a Field event without a field row, and one without a column, stay',
      ScalarInt(vConn, 'SELECT COUNT(*) FROM "DL_LAYOUT_EVENTS" WHERE "LAYOUT_TYPE" = ''Field''') = 2);
  finally
    vConn.Free;
  end;
  Check('M5e nothing else changed: the migrated backup is the v2 backup with the moved event, the cleared ALIGNMENT, the new trailer',
    FileBytesText(TPath.Combine(GDir, 'v3-after.txt')) = ExpectedFromV2(vText));
  Check('M5f a second run is already current', MigrateRepository(vPath, True).AlreadyCurrent);
  { a failure inside the transaction rolls everything back }
  vPath := NewPath;
  CreateRepository(vPath, 2);
  vConn := OpenRepository(vPath, False);
  try
    vConn.ExecSQL('INSERT INTO "DL_FIELDS_INFO" ("TABLE_NAME","FIELD_NAME","ALIGNMENT") VALUES (''T'',''F'',-2)');
    vConn.ExecSQL('CREATE TRIGGER t1 BEFORE UPDATE ON "DL_FIELDS_INFO" BEGIN SELECT RAISE(ABORT, ''no''); END');
  finally
    vConn.Free;
  end;
  Check('M5g a migration that fails raises', RaisedClass(procedure begin MigrateRepository(vPath, True); end) <> '');
  vConn := OpenRepository(vPath, True);
  try
    Check('M5h ... and the file is still schema 2, row unchanged', (RepoSchemaVersion(vConn) = 2)
      and (ScalarInt(vConn, 'SELECT "ALIGNMENT" FROM "DL_FIELDS_INFO"') = -2));
  finally
    vConn.Free;
  end;
end;

{ ---- FR-4: layout events -------------------------------------------------------- }

procedure TestLayoutEvents;
var
  vConn: TFDConnection;
begin
  vConn := NewRepoFrom('model_kinds.txt', 2);
  try
    Check('L1 the fixture restores both layout-event rows with their code',
      (RepoRowCount(vConn, 'DL_LAYOUT_EVENTS') = 2)
      and (ScalarStr(vConn, 'SELECT "EVENT_CODE" FROM "DL_LAYOUT_EVENTS" WHERE "FIELD_NAME" = ''PIC''') = 'ACanvas.Brush.Color := clSilver;'));
    Check('L2 key = (table, field, layout type, event): the same field + event with another layout type is a new row',
      RaisedClass(procedure begin
        vConn.ExecSQL('INSERT INTO "DL_LAYOUT_EVENTS" ("TABLE_NAME","FIELD_NAME","LAYOUT_TYPE","EVENT_NAME") VALUES (''ORDERS'',''PIC'',''TdxTreeList'',''OnCustomDrawCell'')');
      end) = '');
    Check('L3 the identical key is refused (control)',
      RaisedClass(procedure begin
        vConn.ExecSQL('INSERT INTO "DL_LAYOUT_EVENTS" ("TABLE_NAME","FIELD_NAME","LAYOUT_TYPE","EVENT_NAME") VALUES (''ORDERS'',''PIC'',''TdxTreeList'',''OnCustomDrawCell'')');
      end) <> '');
  finally
    vConn.Free;
  end;
end;
{ ---- task 7: exceptions ------------------------------------------------------- }

function Ex(const pRule, pDs, pTab, pFld, pProp: string): TFrException;
begin
  Result.RuleId := pRule;
  Result.DatasetKey := pDs;
  Result.TableName := pTab;
  Result.FieldName := pFld;
  Result.Prop := pProp;
  Result.Reason := 'x';
end;

function Fi(const pRule, pDs, pTab, pFld, pProp: string): TFrFinding;
begin
  Result.RuleId := pRule;
  Result.DatasetKey := pDs;
  Result.TableName := pTab;
  Result.FieldName := pFld;
  Result.Prop := pProp;
end;

procedure TestExceptions;
var
  vConn: TFDConnection;
  vRows: TArray<TFrException>;
begin
  vConn := NewRepoFrom('model_kinds.txt', 2);
  try
    vRows := LoadExceptions(vConn);
  finally
    vConn.Free;
  end;
  Check('E0 LoadExceptions reads the fixture row', (Length(vRows) = 1) and (vRows[0].Prop = 'DisplayWidth') and (vRows[0].DatasetKey = ''));
  Check('E1 an empty dataset key is a wildcard: the row silences the finding in any dataset',
    IsExcepted(vRows, Fi('r1', 'Any.ds', 'ORDERS', 'PIC', 'DisplayWidth')));
  Check('E2 a non-matching PROP does not suppress',
    not IsExcepted(vRows, Fi('r1', 'Any.ds', 'ORDERS', 'PIC', 'DisplayFormat')));
  Check('E3 a finding without a property is not silenced by a row that names one',
    not IsExcepted(vRows, Fi('r1', 'Any.ds', 'ORDERS', 'PIC', '')));
  Check('E4 another rule or field is not silenced',
    (not IsExcepted(vRows, Fi('r2', 'Any.ds', 'ORDERS', 'PIC', 'DisplayWidth')))
    and (not IsExcepted(vRows, Fi('r1', 'Any.ds', 'ORDERS', 'QTY', 'DisplayWidth'))));
  Check('E5 matching is case-insensitive', IsExcepted(vRows, Fi('R1', 'x', 'orders', 'pic', 'displaywidth')));
  vRows := [Ex('*', '', 'ORDERS', '', '')];
  Check('E6 the * rule silences every rule for that table, nothing for another table',
    IsExcepted(vRows, Fi('anything', 'd', 'ORDERS', 'QTY', 'p')) and (not IsExcepted(vRows, Fi('anything', 'd', 'CUSTOMER', 'ID', 'p'))));
  vRows := [Ex('r9', 'U.qry', '', '', '')];
  Check('E7 a dataset-only row silences that dataset and not another',
    IsExcepted(vRows, Fi('r9', 'u.QRY', 'T', 'F', '')) and (not IsExcepted(vRows, Fi('r9', 'V.qry', 'T', 'F', ''))));
  Check('E8 no rows silence nothing (control)', not IsExcepted(nil, Fi('r1', '', '', '', '')));
  vConn := NewRepoFrom('golden.dlrepo.txt', 1);
  try
    Check('E9 a schema-1 repository has no exceptions (and no table to read)', Length(LoadExceptions(vConn)) = 0);
  finally
    vConn.Free;
  end;
end;

{ ---- task 8: check ------------------------------------------------------------ }

function CodesOf(const pFindings: TArray<TFrCheckFinding>): string;
var
  vFinding: TFrCheckFinding;
begin
  Result := '';
  for vFinding in pFindings do
    Result := Result + IfThen(Result = '', '', ' ') + vFinding.Code + '@' + vFinding.Where;
end;

procedure TestCheck;
var
  vConn: TFDConnection;
  vFindings: TArray<TFrCheckFinding>;
  vText: TArray<string>;
  vPath: string;
begin
  vConn := NewRepoFrom('model_kinds.txt', 2);
  try
    vFindings := CheckRepository(vConn);
    Check('C1 the fixture gives exactly the six planted findings', Length(vFindings) = 6, CodesOf(vFindings));
    Check('C2a kind/flag mismatch', CodesOf(vFindings).Contains('kind-flag-mismatch@ORDERS.BADFLAG'), CodesOf(vFindings));
    Check('C2b lookup missing DESTVALUE', CodesOf(vFindings).Contains('lookup-incomplete@ORDERS.LK_NOVAL'));
    Check('C2c lookup DESTKEY not PK is a WARNING',
      CodesOf(vFindings).Contains('lookup-key-not-pk@ORDERS.LK_KEY') and (vFindings[1].Severity = fcsWarn), CodesOf(vFindings));
    Check('C2d macro to an unknown field', CodesOf(vFindings).Contains('calc-unknown-field@ORDERS.BADMACRO'));
    Check('C2e the cycle is named once, in order, starting at the smallest field',
      CodesOf(vFindings).Contains('calc-cycle@ORDERS.CYC_A') and (Pos('CYC_A -> CYC_B -> CYC_A', string.Join('|', RenderCheckText(vFindings))) > 0));
    Check('C2f layout-event row for an unknown field',
      CodesOf(vFindings).Contains('layout-event-unknown-field@layout TcxGridDBBandedTableView ORDERS.GHOST OnGetText'), CodesOf(vFindings));
    vText := RenderCheckText(vFindings);
    Check('C3a text: one line per finding and a summary', (Length(vText) = 7) and (vText[6] = 'check: 6 findings (5 errors, 1 warnings)'), vText[Length(vText) - 1]);
    Check('C3b json mirrors the findings', RenderCheckJson(vFindings).Contains('"errors":5') and RenderCheckJson(vFindings).Contains('"warnings":1')
      and RenderCheckJson(vFindings).Contains('"code":"calc-cycle"'));

    vConn.ExecSQL('INSERT INTO "DL_FIELDS_INFO" ("TABLE_NAME","FIELD_NAME","FIELD_KIND") VALUES (''ORDERS'',''WEIRD'',7)');
    vConn.ExecSQL('INSERT INTO "DL_FIELDS_INFO" ("TABLE_NAME","FIELD_NAME","ISCALCULATED") VALUES (''ORDERS'',''LEGACYCALC'',1)');
    vConn.ExecSQL('INSERT INTO "DL_FIELDS_INFO" ("TABLE_NAME","FIELD_NAME","FIELD_KIND","CALC_BODY") VALUES (''ORDERS'',''BADBODY'',5,''SUM({{QTY'')');
    vConn.ExecSQL('INSERT INTO "DL_FIELDS_INFO" ("TABLE_NAME","FIELD_NAME","FIELD_KIND","ISCALCULATED","CALC_BODY") VALUES (''ORDERS'',''SELFREF'',2,1,''{{SELFREF}} := {{SELFREF}} + 1;'')');
    vConn.ExecSQL('INSERT INTO "DL_FIELDS_INFO" ("TABLE_NAME","FIELD_NAME","FIELD_KIND","ISLOOKUP","DESTTABLE","DESTVALUE") VALUES (''ORDERS'',''LK_BADTAB'',3,1,''NOTABLE'',''X'')');
    vConn.ExecSQL('INSERT INTO "DL_FIELDS_INFO" ("TABLE_NAME","FIELD_NAME","FIELD_KIND","ISLOOKUP","DESTTABLE","DESTVALUE") VALUES (''ORDERS'',''LK_BADVAL'',3,1,''CUSTOMER'',''NOCOL'')');
    vFindings := CheckRepository(vConn);
    Check('C4a a NULL-kind ISCALCULATED row is a mismatch until migrated', CodesOf(vFindings).Contains('kind-flag-mismatch@ORDERS.LEGACYCALC'));
    Check('C4b an unknown FIELD_KIND is a finding, not a crash', CodesOf(vFindings).Contains('unknown-kind@ORDERS.WEIRD'));
    Check('C4c a malformed body is a calc-macro-error', CodesOf(vFindings).Contains('calc-macro-error@ORDERS.BADBODY'));
    Check('C4d a body using its own field is a one-field cycle', Pos('SELFREF -> SELFREF', string.Join('|', RenderCheckText(vFindings))) > 0);
    Check('C4e lookup to an unknown table / value', CodesOf(vFindings).Contains('lookup-unknown-table@ORDERS.LK_BADTAB')
      and CodesOf(vFindings).Contains('lookup-unknown-value@ORDERS.LK_BADVAL'));

    vConn.ExecSQL('DELETE FROM "DL_FIELDS_INFO" WHERE "FIELD_NAME" IN (''BADFLAG'',''BADMACRO'',''CYC_A'',''CYC_B'',''LK_KEY'',''LK_NOVAL'',''WEIRD'',''LEGACYCALC'',''BADBODY'',''SELFREF'',''LK_BADTAB'',''LK_BADVAL'')');
    vConn.ExecSQL('DELETE FROM "DL_LAYOUT_EVENTS" WHERE "FIELD_NAME" = ''GHOST''');
    vFindings := CheckRepository(vConn);
    Check('C5 positive control: with the planted rows removed the repository is clean (exit 0)', Length(vFindings) = 0, CodesOf(vFindings));
    Check('C5b clean text is "check: clean"', RenderCheckText(vFindings)[0] = 'check: clean');
  finally
    vConn.Free;
  end;

  vPath := NewPath;
  CreateRepository(vPath, 1);
  vConn := OpenRepository(vPath, False);
  try
    RestoreRepository(vConn, Fixture('golden.dlrepo.txt'), False);
    Check('C6 a schema-1 repository checks clean without CALC_BODY / field-use tables', Length(CheckRepository(vConn)) = 0);
    vConn.ExecSQL('INSERT INTO "DL_FIELDS_INFO" ("TABLE_NAME","FIELD_NAME","ISCALCULATED") VALUES (''ORDERS'',''C1'',1)');
    Check('C6b and still reports a v1 NULL-kind calc row', CodesOf(CheckRepository(vConn)).Contains('kind-flag-mismatch@ORDERS.C1'));
  finally
    vConn.Free;
  end;
end;

{ EVCOLS: what repo check adds on schema 3. }
procedure TestCheckV3;
var
  vConn: TFDConnection;
  vCodes: string;

  procedure Event(const pField, pLayout, pEvent, pCode: string);
  begin
    vConn.ExecSQL('INSERT INTO "DL_LAYOUT_EVENTS" VALUES (''ORDERS'',:f,:l,:e,:c)', [pField, pLayout, pEvent, pCode]);
  end;

begin
  vConn := NewRepoFrom('golden_v3.txt', 3);
  try
    Check('V0 control: the fixture checks clean, member macros and an unbound column included', Length(CheckRepository(vConn)) = 0, CodesOf(CheckRepository(vConn)));
    vConn.ExecSQL('UPDATE "DL_FIELDS_INFO" SET "ONCHANGE_BODY" = ''{{NOPE}}.Clear; {{nope}}.AsInteger := 1;'' WHERE "FIELD_NAME" = ''AMOUNT''');
    vConn.ExecSQL('UPDATE "DL_FIELDS_INFO" SET "GRID_DRAWCELL_BODY" = ''if {{ID'' WHERE "FIELD_NAME" = ''ID'' AND "TABLE_NAME" = ''ORDERS''');
    vConn.ExecSQL('UPDATE "DL_FIELDS_INFO" SET "ALIGNMENT" = -2 WHERE "FIELD_NAME" = ''NOTE''');
    vConn.ExecSQL('INSERT INTO "DL_GRID_COLUMNS" VALUES (''frmA'',''view1'',''colBad'',''ORDERS'',''GHOST'',7)');
    Event('', 'DBTable', 'OnCustomDrawCell', 'if {{AMOUNT}}.IsNull then ADone := True;');
    Event('NOTE', 'Field', 'OnGetText', 'x;');
    Event('AMOUNT', 'Card', 'OnGetDisplayText', 'AText := {{GONE}}.AsString;');
    vCodes := CodesOf(CheckRepository(vConn));
    Check('V1 a macro of an event column that names no field, once', vCodes.Contains('event-unknown-field@ORDERS.AMOUNT ONCHANGE_BODY'), vCodes);
    Check('V2 a malformed macro of an event column', vCodes.Contains('event-macro-error@ORDERS.ID GRID_DRAWCELL_BODY'), vCodes);
    Check('V3 ALIGNMENT outside NULL / 0 / 1 / 2 is a warning', vCodes.Contains('alignment-invalid@ORDERS.NOTE') and not vCodes.Contains('alignment-invalid@ORDERS.AMOUNT'), vCodes);
    Check('V4 a grid column that names an unknown field', vCodes.Contains('grid-column-unknown-field@grid frmA.view1.colBad'), vCodes);
    Check('V5 a Field event left in DL_LAYOUT_EVENTS', vCodes.Contains('layout-event-field-type@layout Field ORDERS.NOTE OnGetText'), vCodes);
    Check('V6 a macro of a layout event that names no field', vCodes.Contains('event-unknown-field@layout Card ORDERS.AMOUNT OnGetDisplayText'), vCodes);
    Check('V7 a view-level event needs no field row', not vCodes.Contains('layout DBTable'), vCodes);
    Check('V8 exactly these six', Length(CheckRepository(vConn)) = 6, vCodes);
    vConn.ExecSQL('INSERT INTO "DL_FIELDS_INFO" ("TABLE_NAME","FIELD_NAME","FIELD_KIND","ISCALCULATED","CALC_BODY") VALUES (''ORDERS'',''IC'',4,1,''if {{IC}}.IsNull then {{IC}}.AsInteger := 1;'')');
    vConn.ExecSQL('INSERT INTO "DL_FIELDS_INFO" ("TABLE_NAME","FIELD_NAME","FIELD_KIND","ISCALCULATED","CALC_BODY") VALUES (''ORDERS'',''CF'',2,1,''if {{CF}}.IsNull then {{CF}}.AsInteger := 1;'')');
    vCodes := CodesOf(CheckRepository(vConn));
    Check('V9 an internal-calc field may read itself, a calc field may not', vCodes.Contains('calc-cycle@ORDERS.CF') and not vCodes.Contains('calc-cycle@ORDERS.IC'), vCodes);
  finally
    vConn.Free;
  end;
end;

{ ---- task 9: change set ------------------------------------------------------- }

function MakeChange(pId: Integer; pOp: TFrChangeOp; const pTarget, pProp, pOld, pNew, pBlocked: string): TFrChange;
begin
  Result.Id := pId;
  Result.Op := pOp;
  Result.Target := pTarget;
  Result.Prop := pProp;
  Result.OldValue := pOld;
  Result.NewValue := pNew;
  Result.Blocked := pBlocked;
  Result.Checked := pBlocked = '';
end;

procedure TestChangeSet;
var
  vSet: TFrChangeSet;
  vText: TArray<string>;
  vSel: TArray<TFrChange>;
begin
  vSet.Direction := fdDbToRepo;
  vSet.Changes := [
    MakeChange(1, fcoInsert, 'DL_FIELDS_INFO MSCLIST|DIMNAME', '', '', 'new row', ''),
    MakeChange(2, fcoUpdate, 'DL_FIELDS_INFO MSCLIST|DIMABBR', 'DISPLAY_WIDTH', '10', '12', ''),
    MakeChange(3, fcoDelete, 'DL_FIELDS_INFO MSCLIST|OLD', '', 'gone', '', ''),
    MakeChange(4, fcoUpdate, 'MSCLIST.DIMABBR', 'FIELD_SIZE', '20', 'caf' + WideChar($E9), 'Firebird refuses: data in the column')];
  vText := RenderChangeSetText(vSet);
  Check('S1a header line', vText[0] = 'direction db-to-repo, 4 changes, 1 blocked, 0 unchecked', vText[0]);
  Check('S1b update line', vText[2] = '[2] update DL_FIELDS_INFO MSCLIST|DIMABBR DISPLAY_WIDTH: 10 -> 12', vText[2]);
  Check('S1c insert and delete lines without a property', (vText[1] = '[1] insert DL_FIELDS_INFO MSCLIST|DIMNAME:  -> new row')
    and (vText[3] = '[3] delete DL_FIELDS_INFO MSCLIST|OLD: gone -> '), vText[1]);
  Check('S1d blocked change: line, escaped non-ASCII, BLOCKED line',
    (vText[4] = '[4] update MSCLIST.DIMABBR FIELD_SIZE: 20 -> caf\' + 'u00E9') and (vText[5] = '  BLOCKED: Firebird refuses: data in the column'), vText[4]);
  Check('S1e render is pure ASCII', TEncoding.ASCII.GetString(TEncoding.ASCII.GetBytes(string.Join('', vText))) = string.Join('', vText));
  Check('S2a json mirrors the record', RenderChangeSetJson(vSet).Contains('"direction":"db-to-repo"')
    and RenderChangeSetJson(vSet).Contains('"count":4') and RenderChangeSetJson(vSet).Contains('"blocked":1')
    and RenderChangeSetJson(vSet).Contains('"op":"delete"'));
  Check('S2b a blocked change is never checked in the json', RenderChangeSetJson(vSet).Contains('"checked":false'));
  Check('S2c direction names', (FrDirectionName(fdRepoToDb) = 'repo-to-db') and (FrDirectionName(fdDfmToRepo) = 'dfm-to-repo')
    and (FrDirectionName(fdRepoToDfm) = 'repo-to-dfm'));

  vSel := SelectChanges(vSet, ['# comment', '', ' 2 ', '1', '2']);
  Check('S3a ids select, comments and blanks are ignored, duplicates collapse', (Length(vSel) = 2) and (vSel[0].Id = 1) and (vSel[1].Id = 2));
  vSel := SelectChanges(vSet, ['all']);
  Check('S3b all selects every change except the blocked one', (Length(vSel) = 3) and (vSel[2].Id = 3));
  Check('S3c an unknown id raises EFrChangeSetError', RaisedClass(procedure begin SelectChanges(vSet, ['9']); end) = 'EFrChangeSetError');
  Check('S3d naming a blocked change raises (nothing selected)', RaisedClass(procedure begin SelectChanges(vSet, ['4']); end) = 'EFrChangeSetError');
  Check('S3e a line that is neither id nor all raises', RaisedClass(procedure begin SelectChanges(vSet, ['two']); end) = 'EFrChangeSetError');
  Check('S3f an empty file selects nothing (control)', Length(SelectChanges(vSet, ['# only a comment'])) = 0);
  Check('S4 the itemised log line', ApplyLogLine(vSet.Changes[1]) = 'replacing 10 with 12');
end;

begin
  GDir := TPath.Combine(TPath.GetTempPath, 'dl-fieldrepo-model-' + IntToStr(GetCurrentProcessId));
  TDirectory.CreateDirectory(GDir);
  GFix := TPath.GetFullPath(TPath.Combine(ExtractFilePath(ParamStr(0)), '..\fixtures\fieldrepo'));
  try
    TestKinds;
    TestMigrate;
    TestMigrateV2;
    TestLayoutEvents;
    TestExceptions;
    TestCheck;
    TestCheckV3;
    TestChangeSet;
  except
    on E: Exception do
    begin
      Inc(GFail);
      Writeln('FAIL unhandled ', E.ClassName, ': ', E.Message);
    end;
  end;
  if TDirectory.Exists(GDir) then
    TDirectory.Delete(GDir, True);
  Writeln('SUMMARY pass=', GPass, ' fail=', GFail);
  if GFail > 0 then
    Halt(1);
end.
