unit DRagLint.FieldRepoEd.SelfTest;

{ drag-lint 1.52 -- lane TTD: the editor's --selftest (acceptance of run_fieldrepo_editor.ps1).

  Builds a fixture repository in a temp folder, opens it in the real editor window (the
  window is created but never shown), and prints one PASS / FAIL line per check, then
  "SUMMARY pass=N fail=M". Checks: the grid kind, 4 tabs, per tab the row count and column
  count (columns 40 / 12 / 6 / 3, design section 4 with ruling A4), and an edit round trip
  that must keep a trailing blank. A positive control proves the round-trip check can fail:
  before Save changes a second connection must still see the OLD value. }

interface

/// <summary>Runs every check and writes the report to standard output.</summary>
/// <returns>0 when no check failed, 1 otherwise (the process exit code).</returns>
function RunEditorSelfTest: Integer;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.StrUtils,
  Winapi.Windows,
  Data.DB,
  FireDAC.Comp.Client,
  DRagLint.FieldRepo.Schema,
  DRagLint.FieldRepo.TextBackup,
  DRagLint.FieldRepoEd.Grid,
  DRagLint.FieldRepoEd.Form;

const
  EXPECTED_TABS = 4;
  EXPECTED_COLS: array[0..3] of Integer = (40, 12, 6, 3);
  EXPECTED_NAMES: array[0..3] of string = ('DL_FIELDS_INFO', 'DL_DATASETS_INFO',
    'DL_ENUMVALUES', 'DL_ERROR_MESSAGES');
  FIXTURE_ROWS: array[0..3] of Integer = (3, 2, 4, 1);
  EDITED_VALUE = 'edited  ';
  ORIGINAL_PREFIX = 'v_';

var
  GPass: Integer;
  GFail: Integer;

procedure Check(const pName: string; pCond: Boolean; const pDetail: string = '');
begin
  if pCond then
  begin
    Inc(GPass);
    Writeln('PASS ', pName, ' ', pDetail);
  end
  else
  begin
    Inc(GFail);
    Writeln('FAIL ', pName, ' ', pDetail);
  end;
end;

function SqlLiteral(const pColumn: TRepoColumn; pRow: Integer): string;
begin
  Result := if pColumn.Kind = rckBoolean then IntToStr(pRow mod 2)
    else if pColumn.Kind in [rckInteger, rckSmallint, rckByte] then IntToStr(pRow)
    else QuotedStr(ORIGINAL_PREFIX + pColumn.Name + '_' + IntToStr(pRow));
end;

procedure FillFixture(const pFile: string);
var
  Conn: TFDConnection;
  Table: TRepoTable;
  Col: TRepoColumn;
  Cols, Vals: string;
  Ti, Row: Integer;
begin
  CreateRepository(pFile, 1);  { FR-MODEL: the 4-tab fixture is a schema-1 repository; the schema-2 tables are no tabs }
  Conn := OpenRepository(pFile, False);
  try
    Ti := 0;
    for Table in RepoTablesFor(1) do
    begin
      if SameText(Table.Name, REPO_META_TABLE) then
        Continue;
      for Row := 1 to FIXTURE_ROWS[Ti] do
      begin
        Cols := '';
        Vals := '';
        for Col in Table.Columns do
        begin
          Cols := Cols + IfThen(Cols = '', '', ', ') + QuoteRepoIdent(Col.Name);
          Vals := Vals + IfThen(Vals = '', '', ', ') + SqlLiteral(Col, Row);
        end;
        Conn.ExecSQL('INSERT INTO ' + QuoteRepoIdent(Table.Name) + ' (' + Cols + ') VALUES (' + Vals + ')');
      end;
      Inc(Ti);
    end;
  finally
    Conn.Free;
  end;
end;

{ First non-key string column of a table, '' when there is none. }
function FirstEditableString(const pTable: TRepoTable): string;
var
  Col: TRepoColumn;
begin
  Result := '';
  for Col in pTable.Columns do
    if (Col.Kind = rckString) and (Col.PkOrder = 0) then
      Exit(Col.Name);
end;

{ Reads one value of the first row (ORDER BY rowid) through a fresh connection. }
function ReadFirstValue(const pFile: string; const pTable, pColumn: string): string;
var
  Conn: TFDConnection;
begin
  Conn := OpenRepository(pFile, True);
  try
    Result := Conn.ExecSQLScalar('SELECT ' + QuoteRepoIdent(pColumn) + ' FROM ' +
      QuoteRepoIdent(pTable) + ' ORDER BY rowid LIMIT 1');
  finally
    Conn.Free;
  end;
end;

procedure CheckTabs(pForm: TRepoEditorForm);
var
  I: Integer;
  Tab: TRepoTab;
  Rows: Integer;
begin
  Check('tabs=' + IntToStr(pForm.TabCount), pForm.TabCount = EXPECTED_TABS, '');
  for I := 0 to pForm.TabCount - 1 do
  begin
    Tab := pForm.Tabs[I];
    Rows := RepoRowCount(pForm.Connection, Tab.Table.Name);
    Check('tab ' + IntToStr(I) + ' name', SameText(Tab.Table.Name, EXPECTED_NAMES[I]), Tab.Table.Name);
    Check(Tab.Table.Name + ' rows', (Tab.Grid.RowCount = FIXTURE_ROWS[I]) and (Rows = FIXTURE_ROWS[I]),
      Format('grid=%d repo=%d expected=%d', [Tab.Grid.RowCount, Rows, FIXTURE_ROWS[I]]));
    Check(Tab.Table.Name + ' cols', Tab.Grid.ColumnCount = EXPECTED_COLS[I],
      Format('grid=%d expected=%d', [Tab.Grid.ColumnCount, EXPECTED_COLS[I]]));
  end;
end;

procedure CheckEditRoundTrip(pForm: TRepoEditorForm; const pFile: string);
var
  Tab: TRepoTab;
  Col, Before, After: string;
begin
  Tab := pForm.Tabs[0];
  Col := FirstEditableString(Tab.Table);
  Check('edit column found', Col <> '', Col);
  Before := ReadFirstValue(pFile, Tab.Table.Name, Col);
  Tab.Query.First;
  Tab.Query.Edit;
  Tab.Query.FieldByName(Col).AsString := EDITED_VALUE;
  Tab.Query.Post;
  // Positive control: edits are cached, so a second connection must still see the old value.
  Check('edit not visible before save', ReadFirstValue(pFile, Tab.Table.Name, Col) = Before,
    '[' + Before + ']');
  pForm.SaveChanges;
  After := ReadFirstValue(pFile, Tab.Table.Name, Col);
  Check('edit saved with trailing blanks', After = EDITED_VALUE, '[' + After + ']');
  pForm.ReloadAll;
  Check('reload keeps the saved value', pForm.Tabs[0].Query.FieldByName(Col).AsString = EDITED_VALUE, '');
end;

function RunEditorSelfTest: Integer;
var
  Dir, RepoFile, BackupFile: string;
  Form: TRepoEditorForm;
begin
  GPass := 0;
  GFail := 0;
  Writeln('GRID ', RepoGridKind);
  Dir := TPath.Combine(TPath.GetTempPath, 'dl-field-repo-selftest-' + IntToStr(GetCurrentProcessId));
  TDirectory.CreateDirectory(Dir);
  RepoFile := TPath.Combine(Dir, 'selftest.dlrepo');
  BackupFile := TPath.Combine(Dir, 'selftest.txt');
  try
    FillFixture(RepoFile);
    Form := TRepoEditorForm.CreateEditor(nil);
    try
      Form.OpenRepo(RepoFile);
      CheckTabs(Form);
      CheckEditRoundTrip(Form, RepoFile);
      BackupRepository(Form.Connection, BackupFile);
      Check('backup written', TFile.Exists(BackupFile) and (TFile.GetSize(BackupFile) > 0), '');
    finally
      Form.Free;
    end;
  except
    on E: Exception do
      Check('no exception', False, E.ClassName + ': ' + E.Message);
  end;
  Writeln(Format('SUMMARY pass=%d fail=%d', [GPass, GFail]));
  Result := Ord(GFail > 0);
end;

end.
