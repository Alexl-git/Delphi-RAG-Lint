unit ChartsTests.CoreColumns;

(* Cases for DRagLint.Charts.Columns (THE column state and its wording) against the FROZEN
  clone charts\scratch\db\SQL-drag-lint-sql.sqlite. Every expected value is what
  Emit-Common.ps1 printed for the same call on 2026-10-13 (spec P3/P4); the quoted state is
  driven the way the gate drives it, by hiding an extracted column (Hide-ExtractedColumns). *)

interface

uses
  DUnitX.TestFramework, DRagLint.Charts.Index, DRagLint.Charts.Source, DRagLint.Charts.Sql;

type
  [TestFixture]
  TCoreColumnsTests = class
  private
    FIndex  : TChartsIndex;
    FReader : TSourceReader;
    FCatalog: TSqlCatalog;
    function Open: Boolean;
  public
    [TearDown] procedure TearDown;
    [Test] procedure StateYesAnchorsOnColumnLine;
    [Test] procedure StateOlderAndNo;
    [Test] procedure StateServerSql;
    [Test] procedure HiddenColumnReadsQuoted;
    [Test] procedure WordingHelpers;
    [Test] procedure CheapTestAndNotHeld;
    [Test] procedure StaleScriptIsNotKnown;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, DRagLint.Charts.Columns;

const
  REPO_ROOT_ENV = 'DRAGLINT_REPO_ROOT';
  CLONE_REL = 'charts\scratch\db\SQL-drag-lint-sql.sqlite';
  ACTION_LINE = 2243;
  OPTRID_OLDER_LINE = 1951;
  IPCHART_LINE = 2220;
  TABLE_LINE = 3848;
  SERVER_LINE = 7;
  OLDER_LINE_SYNTH = 3;
  NEWEST = '137 columns extracted from the newest of 2 declaration(s), MS1.SQL:2220';
  MS1_INDEXED = 'C:\Projects\DB\SQL\MS1.SQL';  // dl:ok hardcoded-absolute-path@e02a -- REVIEWED 2026-10-13: the path the FROZEN SQL clone indexed for MS1.SQL -- the key AddOverride must match; the test passes when the file is absent

function FindUp(const pRel: string): string;
begin
  var Root:= GetEnvironmentVariable(REPO_ROOT_ENV);
  if (Root <> '') and TFile.Exists(TPath.Combine(Root, pRel)) then
    Exit(TPath.Combine(Root, pRel));
  var Dir:= GetCurrentDir;
  while Dir <> '' do
  begin
    if TFile.Exists(TPath.Combine(Dir, pRel)) then
      Exit(TPath.Combine(Dir, pRel));
    var Up:= ExtractFileDir(ExcludeTrailingPathDelimiter(Dir));
    if SameText(Up, Dir) then
      Break;
    Dir:= Up;
  end;
  Result:= '';
end;

function TCoreColumnsTests.Open: Boolean;
begin
  var Clone:= FindUp(CLONE_REL);
  Result:= Clone <> '';
  if not Result then
  begin
    Assert.Pass('clone missing');
    Exit;
  end;
  FIndex:= TChartsIndex.Create(Clone);
  FReader:= TSourceReader.Create(FIndex);
  FCatalog:= TSqlCatalog.Create(FIndex, FReader);
end;

procedure TCoreColumnsTests.TearDown;
begin
  FreeAndNil(FCatalog);
  FreeAndNil(FReader);
  FreeAndNil(FIndex);
end;

procedure TCoreColumnsTests.StateYesAnchorsOnColumnLine;
begin
  if not Open then
    Exit;
  var S:= SqlColumnState(FCatalog, FCatalog.TableSet, 'ipchart', 'action', TServerSqlHit.None, '');
  Assert.AreEqual('IPCHART|ACTION|yes|True', Format('%s|%s|%s|%s', [S.Table, S.Column, S.State, BoolToStr(S.IsColumn, True)]));
  Assert.AreEqual(ACTION_LINE, S.Line, 'the sql_column''s own line, not the table''s');
  Assert.AreEqual('[certain] a column of the newest of 2 declaration(s), MS1.SQL', S.Caption);
end;

procedure TCoreColumnsTests.StateOlderAndNo;
begin
  if not Open then
    Exit;
  var S:= SqlColumnState(FCatalog, FCatalog.TableSet, 'IPCHART', 'OptrId', TServerSqlHit.None, '');
  Assert.AreEqual('older', S.State);
  Assert.AreEqual('MScript2.SQL', ExtractFileName(S.Path));
  Assert.AreEqual(OPTRID_OLDER_LINE, S.Line);
  Assert.AreEqual('none', S.QuotedScan);
  Assert.AreEqual('column extracted ONLY from an older declaration (MScript2.SQL:1951); not extracted from the newest (' +
    NEWEST + '); nor a quoted identifier in that declaration', S.Caption);
  S:= SqlColumnState(FCatalog, FCatalog.TableSet, 'IPCHART', 'NOPE', TServerSqlHit.None, 'TDataService_IPCHART_SERVER');
  Assert.AreEqual('no', S.State);
  Assert.IsFalse(S.IsColumn);
  Assert.AreEqual(IPCHART_LINE, S.Line);
  Assert.AreEqual('not extracted as a column by the SQL index (' + NEWEST + '); nor a quoted identifier in that declaration; ' +
    'no SQL for IPCHART in TDataService_IPCHART_SERVER names it', S.Caption);
  Assert.WillRaiseWithMessage(procedure begin SqlColumnState(FCatalog, FCatalog.TableSet, 'NOTABLE', 'X', TServerSqlHit.None, ''); end,
    EChartsIndex, 'Get-SqlColumnState: no table NOTABLE in the SQL index -- the caller checks the table first');
end;

procedure TCoreColumnsTests.StateServerSql;
begin
  if not Open then
    Exit;
  var S:= SqlColumnState(FCatalog, FCatalog.TableSet, 'IPCHART', 'NOPE', TServerSqlHit.Make('S.pas', SERVER_LINE, 'TFoo.Bar'), '');
  Assert.AreEqual('server-sql|True|S.pas|7', Format('%s|%s|%s|%d', [S.State, BoolToStr(S.IsColumn, True), S.Path, S.Line]));
  Assert.AreEqual('[inferred] not extracted as a column by the SQL index (' + NEWEST + '); nor a quoted identifier in that ' +
    'declaration -- but the SQL for IPCHART in TFoo.Bar names it: the scripts lag the schema', S.Caption);
end;

procedure TCoreColumnsTests.HiddenColumnReadsQuoted;
begin
  if not Open then
    Exit;
  var Hidden:= FCatalog.TableSet.HideExtractedColumns(['IPCHART.ACTION', 'FOLDERCOUNT.TABLE']);
  try
    Assert.IsTrue(Hidden.Doctored);
    var S:= SqlColumnState(FCatalog, Hidden, 'IPCHART', 'ACTION', TServerSqlHit.None, '');
    Assert.AreEqual('quoted|True|2243|hit', Format('%s|%s|%d|%s', [S.State, BoolToStr(S.IsColumn, True), S.Line, S.QuotedScan]));
    Assert.AreEqual('"ACTION"         D_INTEGER ,', S.Text);
    Assert.AreEqual('[inferred -- source scan] a QUOTED identifier in the newest declaration (MS1.SQL:2243) that the SQL ' +
      'index did not extract as a column', S.Caption);
    Assert.AreEqual('column "ACTION"', ColumnHopLabel(S));
    S:= SqlColumnState(FCatalog, Hidden, 'FOLDERCOUNT', 'TABLE', TServerSqlHit.None, '');
    Assert.AreEqual(TABLE_LINE, S.Line);
    Assert.IsTrue(FCatalog.TableSet.Table('IPCHART').HasColumn('ACTION'), 'the real set is untouched');
  finally
    Hidden.Free;
  end;
  Assert.WillRaiseWithMessage(procedure begin FCatalog.TableSet.HideExtractedColumns(['IPCHART.NOPE']).Free; end,
    EChartsIndex, 'Hide-ExtractedColumns: IPCHART.NOPE is not an extracted column of the SQL index');
end;

procedure TCoreColumnsTests.WordingHelpers;
begin
  Assert.AreEqual('column,older-only,not-a-column,[stale source],quoted,server-sql', string.Join(',', [ColumnStateName('yes'),
    ColumnStateName('older'), ColumnStateName('no'), ColumnStateName('stale'), ColumnStateName('quoted'), ColumnStateName('server-sql')]));
  Assert.AreEqual('Foo is not a column of T -- computed or UI-only: LBL; the database side is empty',
    FormatNotAColumnNote('Foo', 'T', 'LBL', 'TDataService_T_SERVER'));
  Assert.AreEqual('Foo is not extracted as a column of T: LBL; no DataService was searched (no TDataService_T_SERVER in the SERVER ' +
    'index), so whether it is computed, UI-only or written by server SQL is NOT known', FormatNotAColumnNote('Foo', 'T', 'LBL', ''));
end;

procedure TCoreColumnsTests.CheapTestAndNotHeld;
begin
  if not Open then
    Exit;
  var T:= FCatalog.TableSet.Table('IPCHART');
  Assert.IsTrue(T.IsColumn('optrid'), 'an older-only column is a column');
  Assert.IsFalse(T.IsColumn('nope'));
  Assert.AreEqual('NOPE', string.Join(',', ColumnsNotHeld(FCatalog, FCatalog.TableSet, 'IPCHART', ['ACTION', 'OPTRID', 'NOPE', 'action'])));
  var Older: TOlderColumn;
  Older.Column:= 'ACTION';
  Older.Path:= 'f';
  Older.Line:= OLDER_LINE_SYNTH;
  var C:= T.CopyWithout('action', Older, True);
  try
    Assert.AreEqual(Length(T.ColumnNames) - 1, Length(C.ColumnNames));
    Assert.IsFalse(C.HasColumn('ACTION'));
    Assert.AreEqual('OPTRID,ACTION', string.Join(',', C.OlderKeys));
  finally
    C.Free;
  end;
end;

procedure TCoreColumnsTests.StaleScriptIsNotKnown;
begin
  if not Open then
    Exit;
  if not TFile.Exists(MS1_INDEXED) then
  begin
    Assert.Pass('MS1.SQL missing');
    Exit;
  end;
  { -SourceOverride: a copy of the newest script with one line added is stale by construction }
  var StaleCopy:= TPath.Combine(TPath.GetTempPath, 'ms1-stale-' + TGUID.NewGuid.ToString + '.sql');
  TFile.Copy(MS1_INDEXED, StaleCopy);
  try
    TFile.AppendAllText(StaleCopy, '-- changed' + sLineBreak, TEncoding.ASCII);
    FReader.AddOverride(MS1_INDEXED, StaleCopy);
    var S:= SqlColumnState(FCatalog, FCatalog.TableSet, 'IPCHART', 'NOPE', TServerSqlHit.None, '');
    Assert.AreEqual('stale|False|stale', Format('%s|%s|%s', [S.State, BoolToStr(S.IsColumn, True), S.QuotedScan]));
    Assert.AreEqual('[stale source] not extracted as a column by the SQL index (' + NEWEST + '); MS1.SQL differs from the ' +
      'indexed copy, so it was not scanned for a quoted identifier -- whether NOPE is a column of IPCHART is NOT known', S.Caption);
    S:= SqlColumnState(FCatalog, FCatalog.TableSet, 'IPCHART', 'OPTRID', TServerSqlHit.None, '');
    Assert.AreEqual('column extracted ONLY from an older declaration (MScript2.SQL:1951); not extracted from the newest (' + NEWEST +
      '); MS1.SQL differs from the indexed copy, so it was not scanned for a quoted identifier [stale source]', S.Caption);
  finally
    TFile.Delete(StaleCopy);
  end;
end;

end.