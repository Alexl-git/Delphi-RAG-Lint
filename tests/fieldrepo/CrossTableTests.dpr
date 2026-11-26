program CrossTableTests;

{$APPTYPE CONSOLE}

{ drag-lint 1.55 lane XTABLE slice X1 -- console tests for cross-table fields (design
  docs\superpowers\specs\2026-11-26-cross-table-fields-design.md section 2): schema 4 (DL_RELATIONS,
  DL_RELATION_COLUMNS, DL_FIELD_INPUTS), migrate 3 -> 4, #DLREPO 4, ALIAS.FIELD macros, the dependency closure
  over aliases (2.4) and the `repo check` rules of 2.3. Output: one PASS / FAIL line per check, then
  "SUMMARY pass=N fail=M". Exit code 0 only when fail=0. }

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.StrUtils,
  System.Hash,
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
  DRagLint.FieldRepo.Kinds in '..\..\src\sql\DRagLint.FieldRepo.Kinds.pas',
  DRagLint.FieldRepo.CrossTable in '..\..\src\sql\DRagLint.FieldRepo.CrossTable.pas',
  DRagLint.FieldRepo.Check in '..\..\src\sql\DRagLint.FieldRepo.Check.pas',
  DRagLint.FieldRepo.Migrate in '..\..\src\sql\DRagLint.FieldRepo.Migrate.pas';

const
  BODY_OK = '{{FTRNAME}}.AsString := FloatToStr({{VALUE}}.AsFloat) + IntToStr({{MSC.DECIMALS}}.AsInteger);';
  PATH_OK = 'FK_IPCHART_INSP>FK_INSP_MSC';

var
  GPass: Integer = 0;
  GFail: Integer = 0;
  GDir: string;
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

function NewPath: string;
begin
  Inc(GSeq);
  Result := TPath.Combine(GDir, 'x' + IntToStr(GSeq) + '.dlrepo');
end;

function FileHash(const pPath: string): string;
begin
  Result := THashSHA2.GetHashStringFromFile(pPath);
end;

function TableNames(const pTables: TArray<TRepoTable>): string;
var
  vTable: TRepoTable;
begin
  Result := '';
  for vTable in pTables do
    Result := Result + IfThen(Result = '', '', ',') + vTable.Name;
end;

function Codes(const pFindings: TArray<TFrCheckFinding>): string;
var
  vFinding: TFrCheckFinding;
begin
  Result := '';
  for vFinding in pFindings do
    Result := Result + IfThen(Result = '', '', ',') + vFinding.Code;
end;

function HasCode(const pFindings: TArray<TFrCheckFinding>; const pCode: string): Boolean;
var
  vFinding: TFrCheckFinding;
begin
  Result := False;
  for vFinding in pFindings do
    if vFinding.Code = pCode then
      Exit(True);
end;

procedure AddField(pConn: TFDConnection; const pTable, pField: string; pKind: Integer; pPk: Boolean; const pBody: string = '');
begin
  pConn.ExecSQL('INSERT INTO "DL_FIELDS_INFO" ("TABLE_NAME", "FIELD_NAME", "FIELD_KIND", "ISCALCULATED", "PRIMARY_KEY", "CALC_BODY") ' +
    'VALUES (:t, :f, :k, :c, :p, NULLIF(:b, ''''))', [pTable, pField, pKind, pKind = 2, pPk, pBody]);
end;

procedure AddConstraint(pConn: TFDConnection; const pName, pTable, pKind, pRefTable, pRefConstraint, pColumn: string);
begin
  pConn.ExecSQL('INSERT INTO "DL_CONSTRAINTS" ("CONSTRAINT_NAME", "TABLE_NAME", "KIND", "REF_TABLE", "REF_CONSTRAINT") ' +
    'VALUES (:n, :t, :k, :r, :c)', [pName, pTable, pKind, pRefTable, pRefConstraint]);
  pConn.ExecSQL('INSERT INTO "DL_CONSTRAINT_COLUMNS" ("CONSTRAINT_NAME", "POSITION", "COLUMN_NAME") VALUES (:n, 1, :c)', [pName, pColumn]);
end;

procedure AddRelation(pConn: TFDConnection; const pName, pChild, pParent, pSource, pConstraint, pParentKey: string;
  pDefault: Boolean; const pChildCol, pParentCol: string);
begin
  pConn.ExecSQL('INSERT INTO "DL_RELATIONS" ("RELATION_NAME", "CHILD_TABLE", "PARENT_TABLE", "SOURCE", "CONSTRAINT_NAME", ' +
    '"PARENT_KEY", "IS_DEFAULT") VALUES (:n, :c, :p, :s, NULLIF(:k, ''''), :pk, :d)',
    [pName, pChild, pParent, pSource, pConstraint, pParentKey, pDefault]);
  if pChildCol <> '' then
    pConn.ExecSQL('INSERT INTO "DL_RELATION_COLUMNS" ("RELATION_NAME", "POSITION", "CHILD_COLUMN", "PARENT_COLUMN") ' +
      'VALUES (:n, 1, :c, :p)', [pName, pChildCol, pParentCol]);
end;

procedure AddInput(pConn: TFDConnection; const pTable, pField, pBinding, pAlias, pPath, pTarget: string);
begin
  pConn.ExecSQL('INSERT INTO "DL_FIELD_INPUTS" ("TABLE_NAME", "FIELD_NAME", "BINDING", "ALIAS", "PATH", "TARGET_TABLE") ' +
    'VALUES (:t, :f, :b, :a, :p, :g)', [pTable, pField, pBinding, pAlias, pPath, pTarget]);
end;

{ The clean IPCHART -> INSPRSLT -> MSCLIST fixture (design 2.1). }
function NewCleanRepo: TFDConnection;
var
  vPath: string;
begin
  vPath := NewPath;
  CreateRepository(vPath);
  Result := OpenRepository(vPath, False);
  AddField(Result, 'IPCHART', 'ID', 1, True);
  AddField(Result, 'IPCHART', 'INSPID', 1, False);
  AddField(Result, 'IPCHART', 'VALUE', 1, False);
  AddField(Result, 'IPCHART', 'FTRNAME', 2, False, BODY_OK);
  AddField(Result, 'INSPRSLT', 'ID', 1, True);
  AddField(Result, 'INSPRSLT', 'FTRID', 1, False);
  AddField(Result, 'MSCLIST', 'ID', 1, True);
  AddField(Result, 'MSCLIST', 'DECIMALS', 1, False);
  AddConstraint(Result, 'PK_IPCHART', 'IPCHART', 'PK', '', '', 'ID');
  AddConstraint(Result, 'PK_INSPRSLT', 'INSPRSLT', 'PK', '', '', 'ID');
  AddConstraint(Result, 'PK_MSCLIST', 'MSCLIST', 'PK', '', '', 'ID');
  AddConstraint(Result, 'FK_IPCHART_INSP', 'IPCHART', 'FK', 'INSPRSLT', 'PK_INSPRSLT', 'INSPID');
  AddConstraint(Result, 'FK_INSP_MSC', 'INSPRSLT', 'FK', 'MSCLIST', 'PK_MSCLIST', 'FTRID');
  AddRelation(Result, 'FK_IPCHART_INSP', 'IPCHART', 'INSPRSLT', 'FK', 'FK_IPCHART_INSP', 'PK_INSPRSLT', True, 'INSPID', 'ID');
  AddRelation(Result, 'FK_INSP_MSC', 'INSPRSLT', 'MSCLIST', 'FK', 'FK_INSP_MSC', 'PK_MSCLIST', True, 'FTRID', 'ID');
  AddInput(Result, 'IPCHART', 'FTRNAME', '', 'MSC', PATH_OK, 'MSCLIST');
end;

procedure TestSchema;
var
  vTabs: TArray<TRepoTable>;
  vTable: TRepoTable;
  vPk: string;
  vCol: TRepoColumn;
  vConn: TFDConnection;
  vPath: string;
begin
  vTabs := RepoTablesFor(4);
  Check('S1 REPO_SCHEMA_VERSION is 4', REPO_SCHEMA_VERSION = 4, IntToStr(REPO_SCHEMA_VERSION));
  Check('S2 schema 4 = schema 3 + DL_RELATIONS, DL_RELATION_COLUMNS, DL_FIELD_INPUTS (last, in this order)',
    TableNames(vTabs) = TableNames(RepoTablesFor(3)) + ',DL_RELATIONS,DL_RELATION_COLUMNS,DL_FIELD_INPUTS', TableNames(vTabs));
  vPk := '';
  if FindRepoTable(REPO_TABLE_FIELD_INPUTS, vTable) then
    for vCol in vTable.PkColumns do
      vPk := vPk + IfThen(vPk = '', '', ',') + vCol.Name;
  Check('S3 DL_FIELD_INPUTS key = TABLE_NAME, FIELD_NAME, BINDING, ALIAS', vPk = 'TABLE_NAME,FIELD_NAME,BINDING,ALIAS', vPk);
  vPk := '';
  if FindRepoTable(REPO_TABLE_RELATION_COLUMNS, vTable) then
    for vCol in vTable.PkColumns do
      vPk := vPk + IfThen(vPk = '', '', ',') + vCol.Name;
  Check('S4 DL_RELATION_COLUMNS key = RELATION_NAME, POSITION', vPk = 'RELATION_NAME,POSITION', vPk);
  vPath := NewPath;
  CreateRepository(vPath);
  vConn := OpenRepository(vPath, True);
  try
    Check('S5 a new repository is user_version 4 and validates', RepoSchemaVersion(vConn) = 4);
    Check('S6 the cross-table tables are side tables: a new repository is empty', RepoIsEmpty(vConn));
  finally
    vConn.Free;
  end;
  Check('S7 RepoTablesFor(5) raises (control: the range ends at 4)', RaisedClass(procedure begin RepoTablesFor(5); end) = 'ERepoError');
end;

procedure TestMigrate;
var
  vPath: string;
  vConn: TFDConnection;
  vHash: string;
  vRes: TFrMigrateResult;
  vText: string;
begin
  vPath := NewPath;
  CreateRepository(vPath, 3);
  vConn := OpenRepository(vPath, False);
  try
    AddField(vConn, 'ORDERS', 'ID', 1, True);
  finally
    vConn.Free;
  end;
  vHash := FileHash(vPath);
  vRes := MigrateRepository(vPath, False);
  Check('M1 v3 -> v4 dry run plan: three CREATEs, nothing else', vRes.Plan =
    'v3 -> v4: create DL_RELATIONS, DL_RELATION_COLUMNS, DL_FIELD_INPUTS, ALIGNMENT -2 to NULL in 0 rows, user_version 4', vRes.Plan);
  Check('M2 the dry run changes no byte', vHash = FileHash(vPath));
  vRes := MigrateRepository(vPath, True);
  Check('M3 apply: migrated and a before-migrate backup written', vRes.Applied and TFile.Exists(vRes.BackupFile));
  vText := TFile.ReadAllText(vRes.BackupFile);
  Check('M4 the before-migrate backup is the schema-3 text', vText.StartsWith('#DLREPO 3' + #13#10), Copy(vText, 1, 20));
  vConn := OpenRepository(vPath, True);
  try
    Check('M5 user_version 4, DL_META schema_version 4, the row kept',
      (RepoSchemaVersion(vConn) = 4) and (GetRepoMeta(vConn, 'schema_version') = '4') and (RepoRowCount(vConn, 'DL_FIELDS_INFO') = 1));
    Check('M6 the three new tables exist, empty', (RepoRowCount(vConn, REPO_TABLE_RELATIONS) = 0) and
      (RepoRowCount(vConn, REPO_TABLE_RELATION_COLUMNS) = 0) and (RepoRowCount(vConn, REPO_TABLE_FIELD_INPUTS) = 0));
  finally
    vConn.Free;
  end;
  Check('M7 a second migrate is already current', MigrateRepository(vPath, True).AlreadyCurrent);
  vPath := NewPath;
  CreateRepository(vPath, 2);
  vRes := MigrateRepository(vPath, False);
  Check('M8 v2 -> v4 plan also creates the three tables and still moves Field events',
    vRes.Plan.Contains('create DL_GRID_COLUMNS, DL_RELATIONS, DL_RELATION_COLUMNS, DL_FIELD_INPUTS,') and
    vRes.Plan.Contains('move 0 Field events into columns') and vRes.Plan.EndsWith('user_version 4'), vRes.Plan);
end;

procedure TestBackup;
var
  vConn, vOther: TFDConnection;
  vLines, vAgain, vOld: TStringList;
  vPath, vV3: string;
begin
  vConn := NewCleanRepo;
  vLines := TStringList.Create;
  vAgain := TStringList.Create;
  vOld := TStringList.Create;
  try
    BackupRepositoryToStrings(vConn, vLines);
    Check('B1 a schema-4 backup starts with #DLREPO 4', vLines[0] = '#DLREPO 4', vLines[0]);
    Check('B2 it carries the relation, its columns and the input row',
      vLines.Text.Contains('[DL_RELATIONS FK_IPCHART_INSP]') and vLines.Text.Contains('[DL_RELATION_COLUMNS FK_INSP_MSC|1]') and
      vLines.Text.Contains('[DL_FIELD_INPUTS IPCHART|FTRNAME||MSC]'), vLines.Text);
    vPath := NewPath;
    CreateRepository(vPath);
    vOther := OpenRepository(vPath, False);
    try
      RestoreRepositoryFromStrings(vOther, vLines, False);
      BackupRepositoryToStrings(vOther, vAgain);
      Check('B3 restore + backup is byte-identical', vAgain.Text = vLines.Text);
    finally
      vOther.Free;
    end;
    vV3 := NewPath;
    CreateRepository(vV3, 3);
    vOther := OpenRepository(vV3, False);
    try
      AddField(vOther, 'ORDERS', 'ID', 1, True);
      BackupRepositoryToStrings(vOther, vOld);
    finally
      vOther.Free;
    end;
    vPath := NewPath;
    CreateRepository(vPath);
    vOther := OpenRepository(vPath, False);
    try
      RestoreRepositoryFromStrings(vOther, vOld, False);
      vAgain.Clear;
      BackupRepositoryToStrings(vOther, vAgain);
      Check('B4 a #DLREPO 3 backup restores into schema 4: the same rows, #DLREPO 4 and three empty trailers',
        vAgain.Text = vOld.Text.Replace('#DLREPO 3', '#DLREPO 4').Replace('META_VALUE=3', 'META_VALUE=4') +
        '#end DL_RELATIONS 0' + #13#10 + '#end DL_RELATION_COLUMNS 0' + #13#10 + '#end DL_FIELD_INPUTS 0' + #13#10, vAgain.Text);
    finally
      vOther.Free;
    end;
    vOther := OpenRepository(vV3, False);
    try
      Check('B5 a #DLREPO 4 backup into a schema-3 file is refused (migrate first)',
        RaisedClass(procedure begin RestoreRepositoryFromStrings(vOther, vLines, True); end) = 'ERepoError');
    finally
      vOther.Free;
    end;
  finally
    vOld.Free;
    vAgain.Free;
    vLines.Free;
    vConn.Free;
  end;
end;

procedure TestMacros;
var
  vMacros: TArray<TFrMacro>;
  vInputs: TArray<TFrInput>;
begin
  Check('K1 control: ParseMacros still refuses {{A.F}} (generators cannot deliver it yet)',
    RaisedClass(procedure begin ParseMacros('{{MSC.DECIMALS}}.AsInteger'); end) = 'EFrKindError');
  vMacros := ParseMacrosWithAliases('X := {{MSC.DECIMALS}}.AsInteger + {{VALUE}}.AsFloat;', ['msc']);
  Check('K2 a declared alias is legal: alias + field, own macro has no alias', (Length(vMacros) = 2) and
    (vMacros[0].Alias = 'MSC') and (vMacros[0].Name = 'DECIMALS') and (vMacros[1].Alias = '') and (vMacros[1].Name = 'VALUE'));
  Check('K3 an undeclared alias raises EFrAliasError',
    RaisedClass(procedure begin ParseMacrosWithAliases('{{X.DECIMALS}}', ['MSC']); end) = 'EFrAliasError');
  Check('K4 two dots, an empty alias and an empty field are malformed (EFrKindError)',
    (RaisedClass(procedure begin ParseMacrosWithAliases('{{MSC.A.B}}', ['MSC']); end) = 'EFrKindError') and
    (RaisedClass(procedure begin ParseMacrosWithAliases('{{.A}}', ['MSC']); end) = 'EFrKindError') and
    (RaisedClass(procedure begin ParseMacrosWithAliases('{{MSC.}}', ['MSC']); end) = 'EFrKindError'));
  Check('K5 a macro in a string is text, also with an alias', Length(ParseMacrosWithAliases('S := ''{{X.Y}}'';', [])) = 0);
  vInputs := CalcInputs('{{FTRNAME}}.AsString := F({{MSC.NOTATION}}.AsInteger, {{msc.decimals}}.AsInteger, ' +
    '{{MSC.DECIMALS}}.AsInteger, {{VALUE}}.AsFloat);', 'FTRNAME', ['MSC']);
  Check('K6 CalcInputs: foreign and own inputs in order, distinct case-insensitively, the target left out',
    (Length(vInputs) = 3) and (vInputs[0].Alias = 'MSC') and (vInputs[0].Field = 'NOTATION') and
    (vInputs[1].Field = 'decimals') and (vInputs[2].Alias = '') and (vInputs[2].Field = 'VALUE'), IntToStr(Length(vInputs)));
  Check('K7 CalcDependencies is unchanged for own-field bodies (control)',
    string.Join(',', CalcDependencies('{{TOTAL}}.AsFloat := {{QTY}}.AsInteger * {{PRICE}}.AsFloat;', 'TOTAL')) = 'QTY,PRICE');
end;

function Input(const pTable, pField, pAlias, pPath, pTarget: string): TFrFieldInput;
begin
  Result.TableName := pTable;
  Result.FieldName := pField;
  Result.Binding := '';
  Result.Alias := pAlias;
  Result.Path := pPath;
  Result.TargetTable := pTarget;
end;

function NeedsText(const pNeeds: TArray<TFrNeed>): string;
var
  vNeed: TFrNeed;
begin
  Result := '';
  for vNeed in pNeeds do
    Result := Result + IfThen(Result = '', '', ' ; ') + vNeed.Path + '|' + vNeed.TableName + '.' + vNeed.FieldName;
end;

procedure TestClosure;
var
  vNeeds: TArray<TFrNeed>;
  vBody: TFrBodyFunc;
  vInputs: TFrInputsFunc;
begin
  vBody := function(const pTable, pField: string): string
    begin
      if SameText(pTable + '.' + pField, 'IPCHART.FTRNAME') then
        Result := '{{FTRNAME}}.AsString := {{MSC.FMT}}.AsString + {{VALUE}}.AsString;'
      else if SameText(pTable + '.' + pField, 'MSCLIST.FMT') then
        Result := '{{FMT}}.AsString := IntToStr({{DECIMALS}}.AsInteger) + {{U.NAME}}.AsString;'
      else if SameText(pTable + '.' + pField, 'A.X') then
        Result := '{{X}}.AsInteger := {{P.Y}}.AsInteger;'
      else if SameText(pTable + '.' + pField, 'B.Y') then
        Result := '{{Y}}.AsInteger := {{Q.X}}.AsInteger;'
      else
        Result := '';
    end;
  vInputs := function(const pTable, pField: string): TArray<TFrFieldInput>
    begin
      if SameText(pTable + '.' + pField, 'IPCHART.FTRNAME') then
        Result := [Input('IPCHART', 'FTRNAME', 'MSC', PATH_OK, 'MSCLIST')]
      else if SameText(pTable + '.' + pField, 'MSCLIST.FMT') then
        Result := [Input('MSCLIST', 'FMT', 'U', 'MSCLIST_UNITS', 'UNITS')]
      else if SameText(pTable + '.' + pField, 'A.X') then
        Result := [Input('A', 'X', 'P', 'A_B', 'B')]
      else if SameText(pTable + '.' + pField, 'B.Y') then
        Result := [Input('B', 'Y', 'Q', 'B_A', 'A')]
      else
        Result := nil;
    end;
  vNeeds := CrossTableClosure('IPCHART', 'FTRNAME', vBody, vInputs);
  Check('C1 closure: a parent calc brings its own inputs, paths concatenated', NeedsText(vNeeds) =
    PATH_OK + '|MSCLIST.FMT ; ' + PATH_OK + '|MSCLIST.DECIMALS ; ' + PATH_OK + '>MSCLIST_UNITS|UNITS.NAME ; |IPCHART.VALUE',
    NeedsText(vNeeds));
  vNeeds := CrossTableClosure('A', 'X', vBody, vInputs);
  Check('C2 a cycle across two tables ends (cycle guard over table + field)', NeedsText(vNeeds) = 'A_B|B.Y ; A_B>B_A|A.X', NeedsText(vNeeds));
  Check('C3 a field with no body needs nothing (control)', Length(CrossTableClosure('MSCLIST', 'DECIMALS', vBody, vInputs)) = 0);
  Check('C4 JoinInputPath / SplitInputPath', (JoinInputPath('', 'R1') = 'R1') and (JoinInputPath('R1', '') = 'R1') and
    (JoinInputPath('R1', 'R2>R3') = 'R1>R2>R3') and (Length(SplitInputPath('')) = 0) and (Length(SplitInputPath('R1>R2')) = 2));
end;

{ Runs repo check after pBreak changed a fresh clean fixture. }
function CheckAfter(pBreak: TProc<TFDConnection>): TArray<TFrCheckFinding>;
var
  vConn: TFDConnection;
begin
  vConn := NewCleanRepo;
  try
    if Assigned(pBreak) then
      pBreak(vConn);
    Result := CheckRepository(vConn);
  finally
    vConn.Free;
  end;
end;

procedure TestCheck;
var
  vF: TArray<TFrCheckFinding>;
  vConn: TFDConnection;
  vPath: string;
begin
  vF := CheckAfter(nil);
  Check('R1 positive control: the clean fixture checks clean', Length(vF) = 0, Codes(vF));
  vF := CheckAfter(procedure(pC: TFDConnection) begin
      pC.ExecSQL('UPDATE "DL_FIELDS_INFO" SET "CALC_BODY" = ''{{FTRNAME}}.AsString := {{X.DECIMALS}}.AsString;'' WHERE "FIELD_NAME" = ''FTRNAME''');
    end);
  Check('R2 an undeclared alias', HasCode(vF, 'input-alias-undeclared'), Codes(vF));
  vF := CheckAfter(procedure(pC: TFDConnection) begin
      pC.ExecSQL('UPDATE "DL_FIELDS_INFO" SET "CALC_BODY" = ''{{FTRNAME}}.AsString := {{MSC.NOPE}}.AsString;'' WHERE "FIELD_NAME" = ''FTRNAME''');
    end);
  Check('R3 a field the target table does not have', HasCode(vF, 'input-unknown-field'), Codes(vF));
  vF := CheckAfter(procedure(pC: TFDConnection) begin
      pC.ExecSQL('UPDATE "DL_FIELD_INPUTS" SET "PATH" = ''FK_INSP_MSC''');
    end);
  Check('R4 a path whose first step does not start at the home table', HasCode(vF, 'input-path-broken'), Codes(vF));
  vF := CheckAfter(procedure(pC: TFDConnection) begin
      pC.ExecSQL('UPDATE "DL_FIELD_INPUTS" SET "PATH" = ''FK_IPCHART_INSP>NO_SUCH''');
    end);
  Check('R5 a path step that is no relation', HasCode(vF, 'input-path-broken'), Codes(vF));
  vF := CheckAfter(procedure(pC: TFDConnection) begin
      pC.ExecSQL('UPDATE "DL_FIELD_INPUTS" SET "TARGET_TABLE" = ''INSPRSLT''');
    end);
  Check('R6 TARGET_TABLE is not the end of the path', HasCode(vF, 'input-target-mismatch'), Codes(vF));
  vF := CheckAfter(procedure(pC: TFDConnection) begin
      pC.ExecSQL('UPDATE "DL_RELATIONS" SET "PARENT_KEY" = ''FK_INSP_MSC'' WHERE "RELATION_NAME" = ''FK_IPCHART_INSP''');
    end);
  Check('R7 a parent key that is no PK / UNIQUE of the parent', HasCode(vF, 'relation-key-not-unique'), Codes(vF));
  vF := CheckAfter(procedure(pC: TFDConnection) begin
      pC.ExecSQL('UPDATE "DL_RELATION_COLUMNS" SET "PARENT_COLUMN" = ''FTRID'' WHERE "RELATION_NAME" = ''FK_IPCHART_INSP''');
    end);
  Check('R7b a parent key on other columns than the relation''s', HasCode(vF, 'relation-key-not-unique'), Codes(vF));
  vF := CheckAfter(procedure(pC: TFDConnection) begin
      pC.ExecSQL('UPDATE "DL_RELATIONS" SET "PARENT_KEY" = ''PK_GONE'' WHERE "RELATION_NAME" = ''FK_IPCHART_INSP''');
    end);
  Check('R7c a parent key the schema facts do not hold is a warning only',
    HasCode(vF, 'relation-key-unknown') and (vF[0].Severity = fcsWarn) and (Length(vF) = 1), Codes(vF));
  vF := CheckAfter(procedure(pC: TFDConnection) begin
      AddRelation(pC, 'IPCHART_INSP_HAND', 'IPCHART', 'INSPRSLT', 'HAND', '', 'PK_INSPRSLT', True, 'INSPID', 'ID');
    end);
  Check('R8 two default relations for one child + parent pair', HasCode(vF, 'relation-two-defaults'), Codes(vF));
  vF := CheckAfter(procedure(pC: TFDConnection) begin
      AddInput(pC, 'IPCHART', 'FTRNAME', 'IPTrack.qryRSTools', 'OTHER', PATH_OK, 'MSCLIST');
    end);
  Check('R9 an override binding with another alias set', HasCode(vF, 'binding-alias-set'), Codes(vF));
  vF := CheckAfter(procedure(pC: TFDConnection) begin
      AddInput(pC, 'IPCHART', 'FTRNAME', 'IPTrack.qryRSTools', 'MSC', 'FK_IPCHART_INSP>FK_INSP_MSC', 'MSCLIST');
    end);
  Check('R9b an override binding with the same alias set is clean (control)', Length(vF) = 0, Codes(vF));
  vF := CheckAfter(procedure(pC: TFDConnection) begin
      AddInput(pC, 'IPCHART', 'NOFIELD', '', 'MSC', PATH_OK, 'MSCLIST');
    end);
  Check('R10 an input row of a field that has no field row', HasCode(vF, 'input-no-field-row'), Codes(vF));
  vF := CheckAfter(procedure(pC: TFDConnection) begin
      AddField(pC, 'MSCLIST', 'CX', 2, False, '{{CX}}.AsString := {{B.FTRNAME}}.AsString;');
      AddRelation(pC, 'MSCLIST_IPCHART', 'MSCLIST', 'IPCHART', 'HAND', '', 'PK_IPCHART', False, 'ID', 'ID');
      AddInput(pC, 'MSCLIST', 'CX', '', 'B', 'MSCLIST_IPCHART', 'IPCHART');
      pC.ExecSQL('UPDATE "DL_FIELDS_INFO" SET "CALC_BODY" = ''{{FTRNAME}}.AsString := {{MSC.CX}}.AsString;'' WHERE "FIELD_NAME" = ''FTRNAME''');
    end);
  Check('R11 a calc cycle across two tables', HasCode(vF, 'calc-cycle'), Codes(vF));
  vF := CheckAfter(procedure(pC: TFDConnection) begin
      pC.ExecSQL('UPDATE "DL_FIELDS_INFO" SET "ONGETTEXT_BODY" = ''Text := IntToStr({{MSC.DECIMALS}}.AsInteger);'' WHERE "FIELD_NAME" = ''FTRNAME''');
    end);
  Check('R12 an event body of the field may use its aliases (control: clean)', Length(vF) = 0, Codes(vF));
  vF := CheckAfter(procedure(pC: TFDConnection) begin
      pC.ExecSQL('UPDATE "DL_FIELDS_INFO" SET "ONGETTEXT_BODY" = ''Text := {{Z.DECIMALS}}.AsString;'' WHERE "FIELD_NAME" = ''FTRNAME''');
    end);
  Check('R12b an event body with an undeclared alias', HasCode(vF, 'input-alias-undeclared'), Codes(vF));
  vF := CheckAfter(procedure(pC: TFDConnection) begin
      pC.ExecSQL('DELETE FROM "DL_CONSTRAINTS" WHERE "CONSTRAINT_NAME" = ''FK_INSP_MSC''');
    end);
  Check('R13 an FK relation whose constraint is gone is a warning', HasCode(vF, 'relation-fk-gone') and (Length(vF) = 1), Codes(vF));
  vF := CheckAfter(procedure(pC: TFDConnection) begin
      pC.ExecSQL('DELETE FROM "DL_RELATION_COLUMNS" WHERE "RELATION_NAME" = ''FK_INSP_MSC''');
      pC.ExecSQL('UPDATE "DL_RELATIONS" SET "SOURCE" = ''GUESS'' WHERE "RELATION_NAME" = ''FK_IPCHART_INSP''');
    end);
  Check('R14 a relation without columns, a SOURCE that is none of FK / FORM / HAND',
    HasCode(vF, 'relation-no-columns') and HasCode(vF, 'relation-source-invalid'), Codes(vF));
  vF := CheckAfter(procedure(pC: TFDConnection) begin
      pC.ExecSQL('UPDATE "DL_CONSTRAINTS" SET "REF_TABLE" = ''IPCHART'' WHERE "CONSTRAINT_NAME" = ''FK_INSP_MSC''');
    end);
  Check('R15 an FK relation whose constraint names another parent', HasCode(vF, 'relation-fk-mismatch'), Codes(vF));
  vPath := NewPath;
  CreateRepository(vPath, 3);
  vConn := OpenRepository(vPath, False);
  try
    AddField(vConn, 'IPCHART', 'FTRNAME', 2, False, '{{FTRNAME}}.AsString := {{MSC.DECIMALS}}.AsString;');
    vF := CheckRepository(vConn);
    Check('R16 control: on schema 3 {{A.F}} stays calc-macro-error', HasCode(vF, 'calc-macro-error'), Codes(vF));
  finally
    vConn.Free;
  end;
end;

{ One test group; an exception it raises is one FAIL, the next group still runs. }
procedure Run(const pName: string; pProc: TProc);
begin
  try
    pProc;
  except
    on E: Exception do
    begin
      Inc(GFail);
      Writeln('FAIL ', pName, ' unhandled ', E.ClassName, ': ', E.Message);
    end;
  end;
end;

{ `--write-fixture <file>`: writes the text backup of the clean fixture (tests\fixtures\fieldrepo\xtable\xtable_v4.txt). }
procedure WriteFixture(const pFile: string);
var
  vConn: TFDConnection;
begin
  vConn := NewCleanRepo;
  try
    BackupRepository(vConn, pFile);
  finally
    vConn.Free;
  end;
end;

begin
  GDir := TPath.Combine(TPath.GetTempPath, 'dl-fieldrepo-xtable-' + IntToStr(GetCurrentProcessId));
  TDirectory.CreateDirectory(GDir);
  if SameText(ParamStr(1), '--write-fixture') then
  begin
    WriteFixture(ParamStr(2));
    TDirectory.Delete(GDir, True);
    Exit;
  end;
  Run('schema', TestSchema);
  Run('migrate', TestMigrate);
  Run('backup', TestBackup);
  Run('macros', TestMacros);
  Run('closure', TestClosure);
  Run('check', TestCheck);
  if TDirectory.Exists(GDir) then
    TDirectory.Delete(GDir, True);
  Writeln('SUMMARY pass=', GPass, ' fail=', GFail);
  if GFail > 0 then
    Halt(1);
end.
