program GridCol2SchemaTests;

{$APPTYPE CONSOLE}

{ drag-lint 1.56 lane GC-S -- console tests for repository schema 5 (plan 2026-11-27-v156-plan.md GRIDCOL2, design
  2026-11-27-derived-field-lineage-design.md section 3, owner DL-7): DL_GRID_COLUMNS.PROPERTIES_CLASS_NAME / PROPERTIES
  and DL_FIELDS_INFO.NOTES / DERIVED_KIND; migrate 4 -> 5 (and 1, 2, 3 -> 5), #DLREPO 5, restore of a #DLREPO 4
  backup into schema 5. Fixture repositories only, all under %TEMP%. Output: one PASS / FAIL line per check, then
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
  DRagLint.FieldRepo.Migrate in '..\..\src\sql\DRagLint.FieldRepo.Migrate.pas';

const
  CRLF = #13#10;
  { Owner text around a lineage block, a line that starts with '#', one that starts with '[', a blank line, a
    trailing blank and a TAB: everything the backup text gives a meaning to. }
  NOTES_TEXT = 'Owner text above.' + CRLF + '[dl:lineage 1]' + CRLF + 'kind: direct' + CRLF + 'inputs: {{ORDERS.QTY}}' + CRLF +
    '[/dl:lineage]' + CRLF + '# not a comment' + CRLF + '#end DL_FIELDS_INFO 9' + CRLF + '[DL_META x]' + CRLF + '' + CRLF +
    #9'tabbed, trailing blank ' + CRLF + 'last line';
  PROPS_TEXT = 'Properties.DisplayFormat = ''0.00''' + CRLF + 'Properties.Items.Strings = (' + CRLF + '  ''One''' + CRLF +
    '  ''Two'')';
  PROPS_CLASS = 'TcxComboBoxProperties';

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
  Result := TPath.Combine(GDir, 'g' + IntToStr(GSeq) + '.dlrepo');
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

function ColumnNames(pVersion: Integer; const pTable: string): string;
var
  vTable: TRepoTable;
  vCol: TRepoColumn;
begin
  Result := '';
  for vTable in RepoTablesFor(pVersion) do
    if vTable.Name = pTable then
      for vCol in vTable.Columns do
        Result := Result + IfThen(Result = '', '', ',') + vCol.Name;
end;

{ 'kind/maxlen/notnull/default' of one column of the current schema; '' when the column is missing. }
function ColumnShape(const pTable, pColumn: string): string;
var
  vTable: TRepoTable;
  vCol: TRepoColumn;
begin
  Result := '';
  if FindRepoTable(pTable, vTable) and vTable.FindColumn(pColumn, vCol) then
    Result := Format('%d/%d/%s/%s', [Ord(vCol.Kind), vCol.MaxLen, BoolToStr(vCol.NotNull, True), vCol.DefaultSql]);
end;

{ The cell as text; '<NULL>' for NULL. }
function Cell(pConn: TFDConnection; const pSql: string): string;
var
  vValue: Variant;
begin
  vValue := pConn.ExecSQLScalar(pSql);
  Result := if VarIsNull(vValue) or VarIsEmpty(vValue) then '<NULL>' else VarToStr(vValue);
end;

procedure AddField(pConn: TFDConnection; const pTable, pField: string);
begin
  pConn.ExecSQL('INSERT INTO "DL_FIELDS_INFO" ("TABLE_NAME", "FIELD_NAME", "FIELD_KIND") VALUES (:t, :f, 1)', [pTable, pField]);
end;

procedure AddGridColumn(pConn: TFDConnection; const pColumn, pField: string; pIndex: Integer);
begin
  pConn.ExecSQL('INSERT INTO "DL_GRID_COLUMNS" ("FORM_NAME", "VIEW_NAME", "COLUMN_NAME", "TABLE_NAME", "FIELD_NAME", "COLUMN_INDEX") ' +
    'VALUES (''frmOrders'', ''tvOrders'', :c, ''ORDERS'', :f, :i)', [pColumn, pField, pIndex]);
end;

{ A repository of schema pVersion with two field rows and, from schema 3 on, two grid column rows. }
function NewOldRepo(pVersion: Integer): string;
var
  vConn: TFDConnection;
begin
  Result := NewPath;
  CreateRepository(Result, pVersion);
  vConn := OpenRepository(Result, False);
  try
    AddField(vConn, 'ORDERS', 'ID');
    AddField(vConn, 'ORDERS', 'TOTAL');
    if pVersion >= 3 then
    begin
      AddGridColumn(vConn, 'tvOrdersID', 'ID', 0);
      AddGridColumn(vConn, 'tvOrdersTOTAL', 'TOTAL', 1);
    end;
  finally
    vConn.Free;
  end;
end;

{ A schema-5 repository whose TOTAL row and column carry the four new cells. }
function NewFullRepo: TFDConnection;
var
  vPath: string;
begin
  vPath := NewOldRepo(REPO_SCHEMA_VERSION);
  Result := OpenRepository(vPath, False);
  Result.ExecSQL('UPDATE "DL_FIELDS_INFO" SET "NOTES" = :n, "DERIVED_KIND" = :k WHERE "FIELD_NAME" = ''TOTAL''',
    [NOTES_TEXT, FR_DERIVED_DIRECT]);
  Result.ExecSQL('UPDATE "DL_GRID_COLUMNS" SET "PROPERTIES_CLASS_NAME" = :c, "PROPERTIES" = :p WHERE "COLUMN_NAME" = ''tvOrdersTOTAL''',
    [PROPS_CLASS, PROPS_TEXT]);
end;

procedure TestSchema;
var
  vConn: TFDConnection;
  vPath: string;
  vColumn: TFrGridColumn;
begin
  Check('S1 REPO_SCHEMA_VERSION is 5', REPO_SCHEMA_VERSION = 5, IntToStr(REPO_SCHEMA_VERSION));
  Check('S2 schema 5 has the tables of schema 4, no new table', TableNames(RepoTablesFor(5)) = TableNames(RepoTablesFor(4)),
    TableNames(RepoTablesFor(5)));
  Check('S3 DL_FIELDS_INFO 5 = 4 + NOTES, DERIVED_KIND (last, in this order)',
    ColumnNames(5, 'DL_FIELDS_INFO') = ColumnNames(4, 'DL_FIELDS_INFO') + ',NOTES,DERIVED_KIND', ColumnNames(5, 'DL_FIELDS_INFO'));
  Check('S4 DL_GRID_COLUMNS 5 = 4 + PROPERTIES_CLASS_NAME, PROPERTIES (last, in this order)',
    ColumnNames(5, 'DL_GRID_COLUMNS') = ColumnNames(4, 'DL_GRID_COLUMNS') + ',PROPERTIES_CLASS_NAME,PROPERTIES',
    ColumnNames(5, 'DL_GRID_COLUMNS'));
  Check('S5 control: schema 4 has none of the four columns',
    (not ColumnNames(4, 'DL_FIELDS_INFO').Contains('NOTES')) and (not ColumnNames(4, 'DL_FIELDS_INFO').Contains('DERIVED_KIND')) and
    (not ColumnNames(4, 'DL_GRID_COLUMNS').Contains('PROPERTIES')) and (ColumnNames(4, 'DL_GRID_COLUMNS') <> ''));
  Check('S6 NOTES is NULL-able text with no default (as CALC_BODY)',
    (ColumnShape('DL_FIELDS_INFO', REPO_COL_NOTES) = ColumnShape('DL_FIELDS_INFO', 'CALC_BODY')) and
    (ColumnShape('DL_FIELDS_INFO', REPO_COL_NOTES) = Format('%d/0/False/', [Ord(rckText)])), ColumnShape('DL_FIELDS_INFO', REPO_COL_NOTES));
  Check('S7 DERIVED_KIND is a NULL-able string of 10', ColumnShape('DL_FIELDS_INFO', REPO_COL_DERIVED_KIND) =
    Format('%d/10/False/', [Ord(rckString)]), ColumnShape('DL_FIELDS_INFO', REPO_COL_DERIVED_KIND));
  Check('S8 PROPERTIES_CLASS_NAME is a NULL-able string of 128, PROPERTIES NULL-able text',
    (ColumnShape('DL_GRID_COLUMNS', REPO_COL_PROPERTIES_CLASS_NAME) = Format('%d/128/False/', [Ord(rckString)])) and
    (ColumnShape('DL_GRID_COLUMNS', REPO_COL_PROPERTIES) = Format('%d/0/False/', [Ord(rckText)])),
    ColumnShape('DL_GRID_COLUMNS', REPO_COL_PROPERTIES_CLASS_NAME) + ' ' + ColumnShape('DL_GRID_COLUMNS', REPO_COL_PROPERTIES));
  vPath := NewOldRepo(REPO_SCHEMA_VERSION);
  vConn := OpenRepository(vPath, False);
  try
    Check('S9 a new repository is user_version 5, DL_META 5 and validates',
      (RepoSchemaVersion(vConn) = 5) and (GetRepoMeta(vConn, 'schema_version') = '5'));
    Check('S10 a row written without the new columns holds NULL in all four',
      (Cell(vConn, 'SELECT "NOTES" FROM "DL_FIELDS_INFO" WHERE "FIELD_NAME" = ''ID''') = '<NULL>') and
      (Cell(vConn, 'SELECT "DERIVED_KIND" FROM "DL_FIELDS_INFO" WHERE "FIELD_NAME" = ''ID''') = '<NULL>') and
      (Cell(vConn, 'SELECT "PROPERTIES_CLASS_NAME" FROM "DL_GRID_COLUMNS" WHERE "COLUMN_NAME" = ''tvOrdersID''') = '<NULL>') and
      (Cell(vConn, 'SELECT "PROPERTIES" FROM "DL_GRID_COLUMNS" WHERE "COLUMN_NAME" = ''tvOrdersID''') = '<NULL>'));
  finally
    vConn.Free;
  end;
  Check('S11 RepoTablesFor(6) raises (control: the range ends at 5)', RaisedClass(procedure begin RepoTablesFor(6); end) = 'ERepoError');
  Check('S12 a schema-4 file still opens and validates as schema 4 (its tables lack the columns)',
    RaisedClass(procedure var vOld: TFDConnection; begin vOld := OpenRepository(NewOldRepo(4), True); vOld.Free; end) = '');
  Check('K1 derived kinds: direct, aggregate, unknown are known; '''' is "not derived", not a kind',
    FrDerivedKindKnown(FR_DERIVED_DIRECT) and FrDerivedKindKnown(FR_DERIVED_AGGREGATE) and FrDerivedKindKnown(FR_DERIVED_UNKNOWN) and
    (FR_DERIVED_DIRECT = 'direct') and (FR_DERIVED_AGGREGATE = 'aggregate') and (FR_DERIVED_UNKNOWN = 'unknown') and
    (not FrDerivedKindKnown('')));
  Check('K2 any other text, and another letter case, is not a derived kind',
    (not FrDerivedKindKnown('calc')) and (not FrDerivedKindKnown('Direct')) and (not FrDerivedKindKnown(' direct')));
  vColumn := Default(TFrGridColumn);
  Check('K3 TFrGridColumn: an empty record has no editor; a class name gives one',
    (not vColumn.HasEditor) and (vColumn.PropertiesClassName = '') and (vColumn.Properties = ''));
  vColumn.PropertiesClassName := PROPS_CLASS;
  Check('K4 TFrGridColumn.HasEditor follows PropertiesClassName', vColumn.HasEditor);
end;

procedure TestMigrate;
var
  vPath, vHash, vText: string;
  vConn: TFDConnection;
  vRes: TFrMigrateResult;
  vFrom: Integer;
begin
  vPath := NewOldRepo(4);
  vHash := FileHash(vPath);
  vRes := MigrateRepository(vPath, False);
  Check('M1 v4 -> v5 dry run plan: four columns in two tables, no CREATE', vRes.Plan =
    'v4 -> v5: add DL_FIELDS_INFO.NOTES, DERIVED_KIND, add DL_GRID_COLUMNS.PROPERTIES_CLASS_NAME, PROPERTIES, ' +
    'ALIGNMENT -2 to NULL in 0 rows, user_version 5', vRes.Plan);
  Check('M2 the dry run changes no byte', vHash = FileHash(vPath));
  vRes := MigrateRepository(vPath, True);
  Check('M3 apply: migrated and a before-migrate backup written', vRes.Applied and TFile.Exists(vRes.BackupFile));
  vText := if TFile.Exists(vRes.BackupFile) then TFile.ReadAllText(vRes.BackupFile) else '';
  Check('M4 the before-migrate backup is the schema-4 text with both grid rows',
    vText.StartsWith('#DLREPO 4' + CRLF) and vText.Contains('#end DL_GRID_COLUMNS 2' + CRLF), Copy(vText, 1, 20));
  vConn := nil;
  try
    Check('M5 the migrated file opens and validates as schema 5',
      RaisedClass(procedure begin vConn := OpenRepository(vPath, False); end) = '');
    if vConn <> nil then
    begin
      Check('M6 user_version 5, DL_META schema_version 5, every row kept',
        (RepoSchemaVersion(vConn) = 5) and (GetRepoMeta(vConn, 'schema_version') = '5') and
        (RepoRowCount(vConn, 'DL_FIELDS_INFO') = 2) and (RepoRowCount(vConn, 'DL_GRID_COLUMNS') = 2));
      Check('M7 the old rows hold NULL in the four new columns, the old cells are unchanged',
        (Cell(vConn, 'SELECT COUNT(*) FROM "DL_FIELDS_INFO" WHERE "NOTES" IS NULL AND "DERIVED_KIND" IS NULL') = '2') and
        (Cell(vConn, 'SELECT COUNT(*) FROM "DL_GRID_COLUMNS" WHERE "PROPERTIES_CLASS_NAME" IS NULL AND "PROPERTIES" IS NULL') = '2') and
        (Cell(vConn, 'SELECT "COLUMN_INDEX" FROM "DL_GRID_COLUMNS" WHERE "COLUMN_NAME" = ''tvOrdersTOTAL''') = '1'));
      vConn.ExecSQL('UPDATE "DL_FIELDS_INFO" SET "NOTES" = :n WHERE "FIELD_NAME" = ''TOTAL''', [NOTES_TEXT]);
      Check('M8 the migrated columns take a value (bytes kept)',
        Cell(vConn, 'SELECT "NOTES" FROM "DL_FIELDS_INFO" WHERE "FIELD_NAME" = ''TOTAL''') = NOTES_TEXT);
    end;
  finally
    vConn.Free;
  end;
  Check('M9 a second migrate is already current', MigrateRepository(vPath, True).AlreadyCurrent);
  vRes := MigrateRepository(NewOldRepo(3), False);
  Check('M10 v3 -> v5 plan: both adds, then the schema-4 tables',
    vRes.Plan = 'v3 -> v5: add DL_FIELDS_INFO.NOTES, DERIVED_KIND, add DL_GRID_COLUMNS.PROPERTIES_CLASS_NAME, PROPERTIES, ' +
    'create DL_RELATIONS, DL_RELATION_COLUMNS, DL_FIELD_INPUTS, ALIGNMENT -2 to NULL in 0 rows, user_version 5', vRes.Plan);
  vRes := MigrateRepository(NewOldRepo(2), False);
  Check('M11 v2 -> v5 plan: DL_GRID_COLUMNS is created whole, not altered',
    vRes.Plan.Contains('GRID_DRAWCELL_BODY, NOTES, DERIVED_KIND, create DL_GRID_COLUMNS, DL_RELATIONS,') and
    (not vRes.Plan.Contains('add DL_GRID_COLUMNS')) and vRes.Plan.EndsWith('user_version 5'), vRes.Plan);
  for vFrom := 1 to 3 do
  begin
    vPath := NewOldRepo(vFrom);
    vRes := MigrateRepository(vPath, True);
    vConn := nil;
    try
      Check(Format('M12.%d v%d -> v5 apply: opens as schema 5 with its 2 field rows', [vFrom, vFrom]), vRes.Applied and
        (RaisedClass(procedure begin vConn := OpenRepository(vPath, True); end) = '') and (vConn <> nil) and
        (RepoSchemaVersion(vConn) = 5) and (RepoRowCount(vConn, 'DL_FIELDS_INFO') = 2), vRes.Plan);
    finally
      vConn.Free;
    end;
  end;
end;

procedure TestBackup;
var
  vConn, vOther: TFDConnection;
  vLines, vAgain, vOld: TStringList;
  vPath, vV4, vFile, vFile2: string;
begin
  vConn := NewFullRepo;
  vLines := TStringList.Create;
  vAgain := TStringList.Create;
  vOld := TStringList.Create;
  try
    BackupRepositoryToStrings(vConn, vLines);
    Check('B1 a schema-5 backup starts with #DLREPO 5', vLines[0] = '#DLREPO 5', vLines[0]);
    Check('B2 it names the four new cells on the TOTAL row and column, and none on the ID ones',
      vLines.Text.Contains('DERIVED_KIND=direct' + CRLF) and vLines.Text.Contains('PROPERTIES_CLASS_NAME=' + PROPS_CLASS + CRLF) and
      (Length(vLines.Text.Split([CRLF + 'NOTES:' + CRLF])) = 2) and (Length(vLines.Text.Split([CRLF + 'PROPERTIES:' + CRLF])) = 2) and
      (Length(vLines.Text.Split(['DERIVED_KIND='])) = 2) and (Length(vLines.Text.Split(['PROPERTIES_CLASS_NAME='])) = 2), vLines.Text);
    vPath := NewPath;
    CreateRepository(vPath);
    vOther := OpenRepository(vPath, False);
    try
      RestoreRepositoryFromStrings(vOther, vLines, False);
      BackupRepositoryToStrings(vOther, vAgain);
      Check('B3 restore + backup is byte-identical', vAgain.Text = vLines.Text);
      Check('B4 the restored NOTES cell is the original text, byte for byte (CRLF, lineage block, # and [ lines)',
        Cell(vOther, 'SELECT "NOTES" FROM "DL_FIELDS_INFO" WHERE "FIELD_NAME" = ''TOTAL''') = NOTES_TEXT,
        Cell(vOther, 'SELECT "NOTES" FROM "DL_FIELDS_INFO" WHERE "FIELD_NAME" = ''TOTAL'''));
      Check('B5 the restored DERIVED_KIND, PROPERTIES_CLASS_NAME and PROPERTIES cells are the originals',
        (Cell(vOther, 'SELECT "DERIVED_KIND" FROM "DL_FIELDS_INFO" WHERE "FIELD_NAME" = ''TOTAL''') = FR_DERIVED_DIRECT) and
        (Cell(vOther, 'SELECT "PROPERTIES_CLASS_NAME" FROM "DL_GRID_COLUMNS" WHERE "COLUMN_NAME" = ''tvOrdersTOTAL''') = PROPS_CLASS) and
        (Cell(vOther, 'SELECT "PROPERTIES" FROM "DL_GRID_COLUMNS" WHERE "COLUMN_NAME" = ''tvOrdersTOTAL''') = PROPS_TEXT));
      Check('B6 the cells that were NULL are NULL after the restore',
        (Cell(vOther, 'SELECT COUNT(*) FROM "DL_FIELDS_INFO" WHERE "NOTES" IS NULL AND "DERIVED_KIND" IS NULL') = '1') and
        (Cell(vOther, 'SELECT COUNT(*) FROM "DL_GRID_COLUMNS" WHERE "PROPERTIES_CLASS_NAME" IS NULL AND "PROPERTIES" IS NULL') = '1'));
    finally
      vOther.Free;
    end;
    vFile := TPath.Combine(GDir, 'full_v5.txt');
    vFile2 := TPath.Combine(GDir, 'full_v5_again.txt');
    BackupRepository(vConn, vFile);
    vPath := NewPath;
    CreateRepository(vPath);
    vOther := OpenRepository(vPath, False);
    try
      RestoreRepository(vOther, vFile, False);
      BackupRepository(vOther, vFile2);
      Check('B7 file round trip: backup, restore, backup gives the same bytes; the file says version 5',
        (FileHash(vFile) = FileHash(vFile2)) and (BackupFileVersion(vFile) = 5), IntToStr(BackupFileVersion(vFile)));
    finally
      vOther.Free;
    end;
    vV4 := NewOldRepo(4);
    vOther := OpenRepository(vV4, False);
    try
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
      Check('B8 a #DLREPO 4 backup restores into schema 5: the same rows under #DLREPO 5, nothing added',
        (vOld[0] = '#DLREPO 4') and (vAgain.Text = vOld.Text.Replace('#DLREPO 4', '#DLREPO 5').Replace('META_VALUE=4', 'META_VALUE=5')),
        vAgain.Text);
      Check('B9 and its rows are there: 2 fields, 2 grid columns, the new cells NULL',
        (RepoRowCount(vOther, 'DL_FIELDS_INFO') = 2) and (RepoRowCount(vOther, 'DL_GRID_COLUMNS') = 2) and
        (Cell(vOther, 'SELECT COUNT(*) FROM "DL_GRID_COLUMNS" WHERE "PROPERTIES" IS NULL') = '2') and
        (GetRepoMeta(vOther, 'schema_version') = '5'));
    finally
      vOther.Free;
    end;
    vOther := OpenRepository(vV4, False);
    try
      Check('B10 a #DLREPO 5 backup into a schema-4 file is refused (migrate first)',
        RaisedClass(procedure begin RestoreRepositoryFromStrings(vOther, vLines, True); end) = 'ERepoError');
      Check('B11 and the refused restore left the schema-4 rows alone', RepoRowCount(vOther, 'DL_GRID_COLUMNS') = 2);
    finally
      vOther.Free;
    end;
    vOld.Text := vOld.Text.Replace('COLUMN_INDEX=1' + CRLF, 'COLUMN_INDEX=1' + CRLF + 'PROPERTIES_CLASS_NAME=X' + CRLF);
    vPath := NewPath;
    CreateRepository(vPath);
    vOther := OpenRepository(vPath, False);
    try
      Check('B12 control: a #DLREPO 4 text that names a schema-5 column is malformed',
        RaisedClass(procedure begin RestoreRepositoryFromStrings(vOther, vOld, False); end) = 'ERepoBackupFormatError');
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

begin
  GDir := TPath.Combine(TPath.GetTempPath, 'dl-gridcol2-schema-' + IntToStr(GetCurrentProcessId));
  TDirectory.CreateDirectory(GDir);
  try
    try
      TestSchema;
      TestMigrate;
      TestBackup;
    except
      on E: Exception do
        Check('no unhandled exception', False, E.ClassName + ': ' + E.Message);
    end;
  finally
    TDirectory.Delete(GDir, True);
  end;
  Writeln(Format('SUMMARY pass=%d fail=%d', [GPass, GFail]));
  if GFail > 0 then
    ExitCode := 1;
end.
