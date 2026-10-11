unit ChartsTests.Compare;

(* Cases for DRagLint.Charts.Compare (spec C1-C6, D8, S1a-S1c, S3, S4a): the orchestration
  of `drag-lint compare` -- load the OLD side from one of five sources, rerun its COMMAND
  through an IReportProducer, diff, warn, and write the snapshot / update-doc side effects.

  Every rerun goes through the REAL TPowerShellProducer against
  tests\charts\fixtures\producer\Stub-AskReport.ps1 (pwsh needed). The stub's knobs:
  $env:STUB_VARIANT = 'B' adds one body row; -Project ending in stale.dproj (or -DbPath
  ending in stale.sqlite) without -AllowStale exits 3.

  Files are written ONLY under a per-test temp folder; committed fixtures are copied there
  before anything could modify them.

  PS trap handled: question ids and argument names are compared with SameText, as the
  PowerShell side does case-insensitively. *)

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TCompareTests = class
  private
    FTemp: string;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure SameQuestionTwiceIsEmptyAndExitZero;
    [Test] procedure VariantBIsExitOneWithOneInsertHunk;
    [Test] procedure OldWithoutCommandWarnsAndUsesGiven;
    [Test] procedure OldWithoutCommandAndNoneGivenIsExitTwo;
    [Test] procedure DifferingGivenCommandWarnsNamingArguments;
    [Test] procedure StaleNewRunIsExitThreeWithoutDiff;
    [Test] procedure OldIndexCopySideRunsWithAllowStale;
    [Test] procedure RemarksSourceComparesOnlyThatBlock;
    [Test] procedure RemarksNotAReportIsExitTwo;
    [Test] procedure UpdateDocReplacesExactlyThatBlock;
    [Test] procedure AutoSnapshotIsTheOldSide;
    [Test] procedure SaveWritesF2Name;
    [Test] procedure TwoCsvFilesCompareWithoutProducer;
    [Test] procedure TwoBundlesCompareGraphs;
    [Test] procedure DifferentFormatsRefused;
    [Test] procedure AutoSnapshotCommandMeetsGivenCommand;
    [Test] procedure GraphRerunKeepsOldSvgAndSavesDot;
    [Test] procedure AllowStaleNeverReachesTheNewRun;
    [Test] procedure SaveWithTwoFilesRefused;
    [Test] procedure UnchangedRemarksBlockIsExitZero;
    [Test] procedure AutoGraphSnapshotIsFoundNextTime;
    [Test] procedure EmptyChartIsRefusedNotSame;
  end;

implementation

uses
  Winapi.Windows, System.SysUtils, System.Classes, System.IOUtils, System.DateUtils,
  DRagLint.Charts.Diff, DRagLint.Charts.ReportHeader, DRagLint.Charts.Adapters,
  DRagLint.Charts.Producer, DRagLint.Charts.Producer.PowerShell, DRagLint.Charts.Remarks,
  DRagLint.Charts.Snapshot, DRagLint.Charts.DocInsight, DRagLint.Charts.Compare;

const
  REPO_ROOT_ENV = 'DRAGLINT_REPO_ROOT';
  FIXTURE_DIR = 'tests\charts\fixtures';
  FIXTURE_PROBE = 'producer\Stub-AskReport.ps1';
  VARIANT_ENV = 'STUB_VARIANT';
  VARIANT_B = 'B';
  BUNDLE_ENV = 'STUB_BUNDLE';
  STUB_NEW_SVG = '<svg>NEW</svg>';
  COMMAND_NO_DEPTH = 'who-writes -Target "OPERAT.NAME" -Project "C:\P\A.dproj"';
  PHRASE = 'Who writes this field';
  UNIT_BLOCK_LINE = 4;
  GRAPH_NODES_A = 21;
  STUB_NEW_NODES = 2;
  EMPTY_DOT = 'digraph G {' + #13#10 + '  rankdir=LR;' + #13#10 + '  a -- b;' + #13#10 + '}' + #13#10;
  ENGINE_FIXTURE = 'C:\X\drag-lint.exe'; // dl:ok hardcoded-absolute-path@7ebd -- synthetic test input: never touches the filesystem
  COMMAND_STUB = 'who-writes -Target "OPERAT.NAME" -Project "C:\P\A.dproj" -Depth 3';
  COMMAND_DEPTH5 = 'who-writes -Target "OPERAT.NAME" -Project "C:\P\A.dproj" -Depth 5';
  COMMAND_STALE = 'who-writes -Target "OPERAT.NAME" -Project "C:\P\stale.dproj" -Depth 3';
  QUESTION = 'who-writes';
  TARGET = 'OPERAT.NAME';
  STALE_DB = 'stale.sqlite';
  VARIANT_ROW = 'Unit1.TFoo.Reset';
  BLOCK2_LINE = 22;
  BLOCK1_FIRST = 9;
  BLOCK1_LAST = 16;
  NOT_REPORT_LINE = 7;
  STUB_TIMEOUT_MS = 120000;
  EXIT_SAME = 0;
  EXIT_DIFFERENT = 1;
  EXIT_SETUP = 2;
  EXIT_STALE = 3;
  ONE = 1;
  TWO = 2;
  UNCHANGED_ROWS = 3;
  ASKED_YEAR = 2026;
  ASKED_MONTH = 10;
  ASKED_DAY = 11;
  ASKED_HOUR = 9;
  ASKED_MIN = 5;
  F2_NAME = 'who-writes--OPERAT.NAME--20261011-0905.txt';

function FixtureDir: string;
begin
  var Root:= GetEnvironmentVariable(REPO_ROOT_ENV);
  if (Root <> '') and TFile.Exists(TPath.Combine(TPath.Combine(Root, FIXTURE_DIR), FIXTURE_PROBE)) then
    Exit(TPath.Combine(Root, FIXTURE_DIR));
  var Dir:= GetCurrentDir;
  while Dir <> '' do
  begin
    if TFile.Exists(TPath.Combine(TPath.Combine(Dir, FIXTURE_DIR), FIXTURE_PROBE)) then
      Exit(TPath.Combine(Dir, FIXTURE_DIR));
    var Up:= ExtractFileDir(ExcludeTrailingPathDelimiter(Dir));
    if SameText(Up, Dir) then
      Break;
    Dir:= Up;
  end;
  Result:= '';
end;

function Fixture(const pSub, pName: string): string;
begin
  var Dir:= FixtureDir;
  Assert.IsTrue(Dir <> '', 'fixture folder ' + FIXTURE_DIR + ' not found from ' + GetCurrentDir);
  Result:= TPath.Combine(TPath.Combine(Dir, pSub), pName);
end;

function Cmd(const pText: string): TReportCommand;
begin
  Assert.IsTrue(ParseCommandLine(pText, Result), 'fixture command does not parse: ' + pText);
end;

function AskedAt: TDateTime;
begin
  Result:= EncodeDateTime(ASKED_YEAR, ASKED_MONTH, ASKED_DAY, ASKED_HOUR, ASKED_MIN, 0, 0);
end;

{ A request wired to the stub producer, with the snapshot folder inside the test's temp
  folder so nothing is ever written beside a real project. }
function StubRequest(pSource: TCompareSource; const pSnapshotDir: string): TCompareRequest;
begin
  Result:= Default(TCompareRequest);
  Result.Source:= pSource;
  Result.SnapshotDir:= pSnapshotDir;
  Result.Producer:= TPowerShellProducer.Create;
  Result.Options:= DefaultProduceOptions;
  Result.Options.ScriptPath:= Fixture('producer', 'Stub-AskReport.ps1');
  Result.Options.EnginePath:= ENGINE_FIXTURE;
  Result.Options.TimeoutMs:= STUB_TIMEOUT_MS;
  Result.Now:= AskedAt;
end;

{ Runs the stub once and returns its plain answer. }
function StubText(const pCommand: string): string;
begin
  var Req:= StubRequest(csFile, '');
  var R:= Req.Producer.Produce(Cmd(pCommand), Req.Options);
  Assert.IsTrue(R.Ok, 'stub failed: exit ' + IntToStr(R.ExitCode) + ' ' + R.Reason);
  Result:= R.Text;
end;

function WriteTemp(const pDir, pName, pText: string): string;
begin
  Result:= TPath.Combine(pDir, pName);
  TFile.WriteAllText(Result, pText, TEncoding.ASCII);
end;

function JoinWarnings(const pWarnings: TArray<string>): string;
begin
  Result:= string.Join(' | ', pWarnings);
end;

function SliceLines(const pLines: TArray<string>; pFirst, pLast: Integer): string;
begin
  var B:= TStringBuilder.Create;
  try
    for var I:= pFirst - 1 to pLast - 1 do
      B.Append(pLines[I]).Append(#13#10);
    Result:= B.ToString;
  finally
    B.Free;
  end;
end;

procedure TCompareTests.Setup;
begin
  FTemp:= TPath.Combine(TPath.GetTempPath, 'drag-lint-charts-cmp-' + TGUID.NewGuid.ToString);
  ForceDirectories(FTemp);
  SetEnvironmentVariable(VARIANT_ENV, nil);
  SetEnvironmentVariable(BUNDLE_ENV, nil);
end;

procedure TCompareTests.TearDown;
begin
  SetEnvironmentVariable(VARIANT_ENV, nil);
  SetEnvironmentVariable(BUNDLE_ENV, nil);
  if TDirectory.Exists(FTemp) then
    TDirectory.Delete(FTemp, True);
end;

procedure TCompareTests.SameQuestionTwiceIsEmptyAndExitZero;
begin
  var Req:= StubRequest(csFile, FTemp);
  Req.OldPath:= WriteTemp(FTemp, 'old.txt', StubText(COMMAND_STUB));
  var R:= RunCompare(Req);
  Assert.AreEqual(EXIT_SAME, R.ExitCode, R.Message);
  Assert.AreEqual(0, Integer(Length(R.Hunks)), 'no hunks');
  Assert.AreEqual(0, Integer(Length(R.Warnings)), 'no warnings: ' + JoinWarnings(R.Warnings));
  Assert.IsTrue(R.Format = cfReportText, 'report format');
  Assert.IsTrue(Length(R.OldItems) > 0, 'old items');
  Assert.AreEqual(Integer(Length(R.OldItems)), Integer(Length(R.NewItems)), 'same item count');
  // C5: both sides' date/time and engine, and the new run's index facts
  Assert.AreEqual('2026-10-10 14:32', R.OldHeader.AskedOn);
  Assert.AreEqual('1.27.0', R.OldHeader.EngineVersion);
  Assert.AreEqual('2026-10-10 14:32', R.NewHeader.AskedOn);
  Assert.AreEqual(ONE, Integer(Length(R.NewIndexes)), 'one index fact');
  Assert.IsFalse(R.NewIndexes[0].Stale, 'a missing stub index is not stale');
end;

procedure TCompareTests.VariantBIsExitOneWithOneInsertHunk;
begin
  var Req:= StubRequest(csFile, FTemp);
  Req.OldPath:= WriteTemp(FTemp, 'old.txt', StubText(COMMAND_STUB));
  SetEnvironmentVariable(VARIANT_ENV, VARIANT_B);
  var R:= RunCompare(Req);
  Assert.AreEqual(EXIT_DIFFERENT, R.ExitCode, R.Message);
  Assert.AreEqual(ONE, Integer(Length(R.Hunks)), 'one hunk');
  var Eq, Del, Ins: Integer;
  CountEdits(R.Edits, Eq, Del, Ins);
  Assert.AreEqual(0, Del, 'deleted');
  Assert.AreEqual(ONE, Ins, 'inserted');
  Assert.IsTrue(R.NewText.Contains(VARIANT_ROW), 'the new text is the variant');
end;

procedure TCompareTests.OldWithoutCommandWarnsAndUsesGiven;
begin
  var Req:= StubRequest(csFile, FTemp);
  var Legacy:= TPath.Combine(FTemp, 'legacy.txt');
  TFile.Copy(Fixture('reports', 'who-writes.legacy.doc.txt'), Legacy);
  Req.OldPath:= Legacy;
  Req.Command:= Cmd(COMMAND_STUB);
  var R:= RunCompare(Req);
  Assert.IsTrue((R.ExitCode = EXIT_SAME) or (R.ExitCode = EXIT_DIFFERENT), 'exit ' + IntToStr(R.ExitCode) + ': ' + R.Message);
  Assert.AreEqual(ONE, Integer(Length(R.Warnings)), JoinWarnings(R.Warnings));
  Assert.AreEqual(WARN_NO_COMMAND, R.Warnings[0]);
  Assert.IsFalse(R.OldHeader.HasCommand, 'the legacy header has no COMMAND');
  Assert.AreEqual('OPERAT.NAME', R.NewHeader.Command.Get('Target'), 'the given command was run');
end;

procedure TCompareTests.OldWithoutCommandAndNoneGivenIsExitTwo;
begin
  var Req:= StubRequest(csFile, FTemp);
  var Legacy:= TPath.Combine(FTemp, 'legacy.txt');
  TFile.Copy(Fixture('reports', 'who-writes.legacy.doc.txt'), Legacy);
  Req.OldPath:= Legacy;
  var R:= RunCompare(Req);
  Assert.AreEqual(EXIT_SETUP, R.ExitCode, R.Message);
  Assert.IsTrue(R.Message.StartsWith('no COMMAND in the old report and none given'), R.Message);
  Assert.AreEqual(0, Integer(Length(R.Edits)), 'no diff');
end;

procedure TCompareTests.DifferingGivenCommandWarnsNamingArguments;
begin
  var Req:= StubRequest(csFile, FTemp);
  Req.OldPath:= WriteTemp(FTemp, 'old.txt', StubText(COMMAND_STUB));
  Req.Command:= Cmd(COMMAND_DEPTH5);
  var R:= RunCompare(Req);
  Assert.AreEqual(EXIT_SAME, R.ExitCode, R.Message);
  Assert.AreEqual(ONE, Integer(Length(R.Warnings)), JoinWarnings(R.Warnings));
  Assert.IsTrue(R.Warnings[0].StartsWith('The given command differs from the report''s COMMAND: '), R.Warnings[0]);
  Assert.IsTrue(R.Warnings[0].Contains('Depth: 3 vs 5'), R.Warnings[0]);
  Assert.AreEqual('5', R.NewHeader.Command.Get('Depth'), 'the GIVEN command wins');
  // R10: a different question id is named by Compare itself
  Req.Command:= Cmd('who-calls -Target "OPERAT.NAME" -Project "C:\P\A.dproj" -Depth 3');
  R:= RunCompare(Req);
  Assert.AreEqual(ONE, Integer(Length(R.Warnings)), JoinWarnings(R.Warnings));
  Assert.IsTrue(R.Warnings[0].Contains('Question: who-writes vs who-calls'), R.Warnings[0]);
end;

procedure TCompareTests.StaleNewRunIsExitThreeWithoutDiff;
begin
  var Req:= StubRequest(csFile, FTemp);
  Req.OldPath:= WriteTemp(FTemp, 'old.txt', StubText(COMMAND_STUB));
  Req.Command:= Cmd(COMMAND_STALE);
  Req.SaveSnapshot:= True;
  var R:= RunCompare(Req);
  Assert.AreEqual(EXIT_STALE, R.ExitCode, R.Message);
  Assert.IsTrue(R.Message.Contains('stale'), R.Message);
  Assert.AreEqual(0, Integer(Length(R.Edits)), 'no diff against stale facts');
  Assert.AreEqual(0, Integer(Length(R.Hunks)), 'no hunks');
  Assert.AreEqual('', R.SnapshotPath, 'no snapshot on exit 3');
end;

procedure TCompareTests.OldIndexCopySideRunsWithAllowStale;
begin
  var Req:= StubRequest(csOldIndex, FTemp);
  Req.OldDb:= STALE_DB;
  Req.Command:= Cmd(COMMAND_STUB);
  var R:= RunCompare(Req);
  Assert.AreEqual(EXIT_SAME, R.ExitCode, R.Message);
  Assert.IsTrue(R.OldText.Contains('INDEX ' + STALE_DB), 'the old side answered from the old index copy');
  Assert.IsFalse(R.NewText.Contains(STALE_DB), 'the new side answered from the current index');
end;

procedure TCompareTests.RemarksSourceComparesOnlyThatBlock;
begin
  var Req:= StubRequest(csRemarks, FTemp);
  var Unit_:= TPath.Combine(FTemp, 'TwoBlocks.pas');
  TFile.Copy(Fixture('remarks', 'TwoBlocks.pas'), Unit_);
  Req.OldPath:= Unit_;
  Req.OldLine:= BLOCK2_LINE;
  var R:= RunCompare(Req);
  Assert.IsTrue((R.ExitCode = EXIT_SAME) or (R.ExitCode = EXIT_DIFFERENT), 'exit ' + IntToStr(R.ExitCode) + ': ' + R.Message);
  Assert.AreEqual('who-calls', R.OldHeader.QuestionId, 'the caret''s block');
  Assert.AreEqual('TFoo.Two', R.OldHeader.Command.Get('Target'));
  Assert.AreEqual('who-calls', R.NewHeader.QuestionId, 'the block''s COMMAND was rerun');
  Assert.IsFalse(R.OldText.Contains('FOO.ONE'), 'block 1 is not part of the old side');
end;

procedure TCompareTests.RemarksNotAReportIsExitTwo;
begin
  var Req:= StubRequest(csRemarks, FTemp);
  Req.OldPath:= Fixture('remarks', 'NotAReport.pas');
  Req.OldLine:= NOT_REPORT_LINE;
  Req.Command:= Cmd(COMMAND_STUB);
  var R:= RunCompare(Req);
  Assert.AreEqual(EXIT_SETUP, R.ExitCode, R.Message);
  Assert.AreEqual(Format('the remarks block at line %d holds no drag-lint report', [NOT_REPORT_LINE]), R.Message);
  // outside any block: the locator's own reason
  Req.OldLine:= ONE;
  R:= RunCompare(Req);
  Assert.AreEqual(EXIT_SETUP, R.ExitCode, R.Message);
  Assert.IsTrue(R.Message.Contains('is not inside'), R.Message);
end;

procedure TCompareTests.UpdateDocReplacesExactlyThatBlock;
begin
  var Req:= StubRequest(csRemarks, FTemp);
  var Unit_:= TPath.Combine(FTemp, 'TwoBlocks.pas');
  TFile.Copy(Fixture('remarks', 'TwoBlocks.pas'), Unit_);
  var Before:= TFile.ReadAllLines(Unit_);
  Req.OldPath:= Unit_;
  Req.OldLine:= BLOCK2_LINE;
  Req.UpdateDoc:= True;
  var R:= RunCompare(Req);
  Assert.IsTrue((R.ExitCode = EXIT_SAME) or (R.ExitCode = EXIT_DIFFERENT), 'exit ' + IntToStr(R.ExitCode) + ': ' + R.Message);
  Assert.AreEqual(Unit_, R.UpdatedFile, 'the unit was updated');
  var After:= TFile.ReadAllLines(Unit_);
  Assert.AreEqual(SliceLines(Before, BLOCK1_FIRST, BLOCK1_LAST), SliceLines(After, BLOCK1_FIRST, BLOCK1_LAST),
    'block 1 untouched');
  var Block: TRemarksBlock;
  var Why: string;
  Assert.IsTrue(FindRemarksBlockAt(After, BLOCK2_LINE, Block, Why), Why);
  var H: TReportHeader;
  Assert.IsTrue(RemarksBlockIsReport(Block, H), 'the new block is a report');
  Assert.AreEqual('2026-10-10 14:32', H.AskedOn, 'the new header carries a time');
  Assert.AreEqual('who-calls', H.Command.Question, 'the new header carries the COMMAND');
  Assert.IsFalse(string.Join(#10, After).Contains(VARIANT_ROW), 'not the variant');
  Assert.IsTrue(string.Join(#10, After).Contains('Unit1.TFoo.SetName'), 'the new body was written');
end;

procedure TCompareTests.AutoSnapshotIsTheOldSide;
begin
  SetEnvironmentVariable(VARIANT_ENV, VARIANT_B);
  var Older:= StubText(COMMAND_STUB);
  SetEnvironmentVariable(VARIANT_ENV, nil);
  var Saved: string;
  Assert.IsTrue(SaveSnapshot(FTemp, True, QUESTION, TARGET, Older, IncDay(AskedAt, -ONE), Saved), 'seed snapshot');
  var Req:= StubRequest(csAutoSnapshot, FTemp);
  Req.Command:= Cmd(COMMAND_STUB);
  var R:= RunCompare(Req);
  Assert.AreEqual(EXIT_DIFFERENT, R.ExitCode, R.Message);
  Assert.IsTrue(R.OldText.Contains(VARIANT_ROW), 'the old side is the snapshot');
  var Eq, Del, Ins: Integer;
  CountEdits(R.Edits, Eq, Del, Ins);
  Assert.AreEqual(ONE, Del, 'the variant row is gone');
  Assert.AreEqual(0, Ins, 'nothing new');
  Assert.AreEqual(0, Integer(Length(R.Warnings)), 'the snapshot''s COMMAND equals the given one: ' + JoinWarnings(R.Warnings));
  // none to compare against: exit 2 naming the folder
  var Req2:= StubRequest(csAutoSnapshot, TPath.Combine(FTemp, 'empty'));
  Req2.Command:= Cmd(COMMAND_STUB);
  R:= RunCompare(Req2);
  Assert.AreEqual(EXIT_SETUP, R.ExitCode, R.Message);
  Assert.IsTrue(R.Message.StartsWith('no auto snapshot for who-writes OPERAT.NAME under '), R.Message);
end;

procedure TCompareTests.SaveWritesF2Name;
begin
  var Req:= StubRequest(csFile, FTemp);
  Req.OldPath:= WriteTemp(FTemp, 'old.txt', StubText(COMMAND_STUB));
  Req.SaveSnapshot:= True;
  var R:= RunCompare(Req);
  Assert.AreEqual(EXIT_SAME, R.ExitCode, R.Message);
  Assert.AreEqual(TPath.Combine(FTemp, F2_NAME), R.SnapshotPath);
  Assert.IsTrue(TFile.Exists(R.SnapshotPath), 'snapshot written');
  Assert.IsTrue(TFile.ReadAllText(R.SnapshotPath).Contains('COMMAND who-writes'), 'plain text with its header');
end;

procedure TCompareTests.TwoCsvFilesCompareWithoutProducer;
begin
  var Req:= Default(TCompareRequest);
  Req.Source:= csTwoFiles;
  Req.OldPath:= Fixture('forms', 'a.csv');
  Req.NewPath:= Fixture('forms', 'b.csv');
  var R:= RunCompare(Req);
  Assert.AreEqual(EXIT_DIFFERENT, R.ExitCode, R.Message);
  Assert.IsTrue(R.Format = cfFormsCsv, 'forms-csv');
  var Eq, Del, Ins: Integer;
  CountEdits(R.Edits, Eq, Del, Ins);
  Assert.AreEqual(UNCHANGED_ROWS, Eq, 'equal');
  Assert.AreEqual(TWO, Del, 'deleted');
  Assert.AreEqual(TWO, Ins, 'inserted');
  Assert.AreEqual(0, Integer(Length(R.Warnings)), 'two files need no command: ' + JoinWarnings(R.Warnings));
end;

procedure TCompareTests.TwoBundlesCompareGraphs;
begin
  var DirA:= TPath.Combine(FTemp, 'a');
  var DirB:= TPath.Combine(FTemp, 'b');
  ForceDirectories(DirA);
  ForceDirectories(DirB);
  TFile.Copy(Fixture('graph', 'who-writes-a.dot'), TPath.Combine(DirA, 'graph.dot'));
  TFile.Copy(Fixture('graph', 'who-writes-a.svg'), TPath.Combine(DirA, 'graph.svg'));
  TFile.Copy(Fixture('graph', 'who-writes-b.dot'), TPath.Combine(DirB, 'graph.dot'));
  var Req:= Default(TCompareRequest);
  Req.Source:= csTwoFiles;
  Req.OldPath:= DirA;
  Req.NewPath:= DirB;
  var R:= RunCompare(Req);
  Assert.AreEqual(EXIT_DIFFERENT, R.ExitCode, R.Message);
  Assert.IsTrue(R.Format = cfGraph, 'chart-graph');
  var Eq, Del, Ins: Integer;
  CountEdits(R.Edits, Eq, Del, Ins);
  Assert.AreEqual(TWO, Del, 'deleted: one node + one edge');
  Assert.AreEqual(TWO, Ins, 'inserted: one node + one edge');
  Assert.IsTrue(Length(R.OldGraph.Nodes) > 0, 'old graph parsed');
  Assert.IsTrue(Length(R.NewGraph.Nodes) > 0, 'new graph parsed');
  Assert.AreEqual(TPath.Combine(DirA, 'graph.svg'), R.OldSvgPath, 'old svg');
end;

procedure TCompareTests.DifferentFormatsRefused;
begin
  var Req:= Default(TCompareRequest);
  Req.Source:= csTwoFiles;
  Req.OldPath:= Fixture('forms', 'a.csv');
  Req.NewPath:= Fixture('reports', 'who-writes.plain.txt');
  var R:= RunCompare(Req);
  Assert.AreEqual(EXIT_SETUP, R.ExitCode, R.Message);
  Assert.AreEqual('cannot compare a forms-csv with a report', R.Message);
  Assert.AreEqual(0, Integer(Length(R.Edits)), 'no diff');
end;

procedure TCompareTests.AutoSnapshotCommandMeetsGivenCommand;
begin
  // R16: the snapshot's own COMMAND (-Depth 3) meets the caller's (no -Depth) like a saved report's
  var Saved: string;
  Assert.IsTrue(SaveSnapshot(FTemp, True, QUESTION, TARGET, StubText(COMMAND_STUB), IncDay(AskedAt, -ONE), Saved), 'seed snapshot');
  var Req:= StubRequest(csAutoSnapshot, FTemp);
  Req.Command:= Cmd(COMMAND_NO_DEPTH);
  var R:= RunCompare(Req);
  Assert.AreEqual(EXIT_SAME, R.ExitCode, R.Message);
  Assert.AreEqual('3', R.OldHeader.Command.Get('Depth'), 'the snapshot''s header was parsed');
  Assert.AreEqual(ONE, Integer(Length(R.Warnings)), JoinWarnings(R.Warnings));
  Assert.IsTrue(R.Warnings[0].Contains('Depth: 3 vs (absent)'), R.Warnings[0]);
  Assert.IsFalse(R.NewHeader.Command.Has('Depth'), 'the GIVEN command was run');
end;

procedure TCompareTests.GraphRerunKeepsOldSvgAndSavesDot;
begin
  var Bundle:= TPath.Combine(FTemp, 'bundle');
  ForceDirectories(Bundle);
  TFile.Copy(Fixture('graph', 'who-writes-a.dot'), TPath.Combine(Bundle, 'graph.dot'));
  TFile.Copy(Fixture('graph', 'who-writes-a.svg'), TPath.Combine(Bundle, 'graph.svg'));
  var OldSvg:= TFile.ReadAllText(TPath.Combine(Bundle, 'graph.svg'));
  var Req:= StubRequest(csFile, TPath.Combine(FTemp, 'snap'));
  Req.OldPath:= Bundle;
  Req.Command:= Cmd(COMMAND_STUB);
  Req.SaveSnapshot:= True;
  // no bundle from the rerun: the refusal names the chart it could not read
  var R:= RunCompare(Req);
  Assert.AreEqual(EXIT_SETUP, R.ExitCode, R.Message);
  Assert.IsTrue(R.Message.StartsWith('the new run''s chart could not be read from '), R.Message);
  DeleteFile(R.OldSvgPath); // the temp copy taken before the rerun; False when there is none
  // the rerun rewrites the very bundle folder the old chart came from
  SetEnvironmentVariable(BUNDLE_ENV, PChar(Bundle));
  R:= RunCompare(Req);
  try
    Assert.AreEqual(EXIT_DIFFERENT, R.ExitCode, R.Message);
    Assert.IsTrue(R.Format = cfGraph, 'chart-graph');
    Assert.AreEqual(GRAPH_NODES_A, Integer(Length(R.OldGraph.Nodes)), 'the old DOT was read before the rerun');
    Assert.AreEqual(STUB_NEW_NODES, Integer(Length(R.NewGraph.Nodes)), 'the rerun''s DOT parsed (emitter dialect): StubA, StubB');
    Assert.AreEqual(STUB_NEW_SVG, TFile.ReadAllText(TPath.Combine(Bundle, 'graph.svg')), 'the stub did rewrite the bundle');
    Assert.AreEqual(OldSvg, TFile.ReadAllText(R.OldSvgPath), 'OldSvgPath still holds the OLD svg');
    Assert.AreEqual(STUB_NEW_SVG, TFile.ReadAllText(R.NewSvgPath), 'NewSvgPath is the new svg');
    // R18: a chart snapshot is a .dot, so a later compare detects a chart
    Assert.IsTrue(R.SnapshotPath.EndsWith(SNAPSHOT_EXT_GRAPH), R.SnapshotPath);
    Assert.IsTrue(DetectFormat(R.SnapshotPath, True) = cfGraph, 'detected as a chart');
  finally
    DeleteFile(R.OldSvgPath); // the temp copy; False when there is none
  end;
end;

procedure TCompareTests.AllowStaleNeverReachesTheNewRun;
begin
  // R17: AllowStale is for the OLD side of S4 only
  var Req:= StubRequest(csFile, FTemp);
  Req.OldPath:= WriteTemp(FTemp, 'old.txt', StubText(COMMAND_STUB));
  Req.Command:= Cmd(COMMAND_STALE);
  Req.Options.AllowStale:= True;
  var R:= RunCompare(Req);
  Assert.AreEqual(EXIT_STALE, R.ExitCode, R.Message);
  Assert.AreEqual(0, Integer(Length(R.Edits)), 'no diff');
end;

procedure TCompareTests.SaveWithTwoFilesRefused;
begin
  var Req:= Default(TCompareRequest);
  Req.Source:= csTwoFiles;
  Req.OldPath:= Fixture('forms', 'a.csv');
  Req.NewPath:= Fixture('forms', 'b.csv');
  Req.SaveSnapshot:= True;
  var R:= RunCompare(Req);
  Assert.AreEqual(EXIT_SETUP, R.ExitCode, R.Message);
  Assert.IsTrue(R.Message.StartsWith('save needs a rerun'), R.Message);
  Assert.AreEqual(0, Integer(Length(R.Edits)), 'no diff');
end;

procedure TCompareTests.UnchangedRemarksBlockIsExitZero;
begin
  // a block pasted from the same answer, rerun with the same variant: nothing changed
  var Block:= FormatAnswerAsDocInsight(PHRASE, QUESTION, TARGET, AskedAt, StubText(COMMAND_STUB));
  var Unit_:= WriteTemp(FTemp, 'U.pas', 'unit U;' + #13#10 + 'interface' + #13#10 + Block +
    'procedure P;' + #13#10 + 'implementation' + #13#10 + 'procedure P; begin end;' + #13#10 + 'end.' + #13#10);
  var Req:= StubRequest(csRemarks, FTemp);
  Req.OldPath:= Unit_;
  Req.OldLine:= UNIT_BLOCK_LINE;
  var R:= RunCompare(Req);
  Assert.AreEqual(EXIT_SAME, R.ExitCode, R.Message);
  var Eq, Del, Ins: Integer;
  CountEdits(R.Edits, Eq, Del, Ins);
  Assert.AreEqual(0, Del + Ins, 'zero changed edits');
  Assert.IsTrue(Eq > 0, 'the block has items');
  Assert.AreEqual(0, Integer(Length(R.Warnings)), JoinWarnings(R.Warnings));
end;

procedure TCompareTests.AutoGraphSnapshotIsFoundNextTime;
begin
  // seed an auto CHART snapshot (.dot), older than the run below
  var Seeded: string;
  Assert.IsTrue(SaveSnapshot(FTemp, True, QUESTION, TARGET, TFile.ReadAllText(Fixture('graph', 'who-writes-a.dot')),
    IncDay(AskedAt, -ONE), Seeded, SNAPSHOT_EXT_GRAPH), 'seed snapshot');
  var Bundle:= TPath.Combine(FTemp, 'bundle');
  SetEnvironmentVariable(BUNDLE_ENV, PChar(Bundle));
  // run 1: --auto --save of a chart writes a .dot into auto\
  var Req:= StubRequest(csAutoSnapshot, FTemp);
  Req.Command:= Cmd(COMMAND_STUB);
  Req.SaveSnapshot:= True;
  var R:= RunCompare(Req);
  Assert.AreEqual(EXIT_DIFFERENT, R.ExitCode, R.Message);
  Assert.IsTrue(R.Format = cfGraph, 'run 1 compared charts');
  Assert.IsTrue(R.SnapshotPath.EndsWith(SNAPSHOT_EXT_GRAPH), R.SnapshotPath);
  DeleteFile(R.OldSvgPath); // a temp copy when the seed had an svg; False when there is none
  // run 2: the auto lookup finds that .dot as the old side
  Req.SaveSnapshot:= False;
  R:= RunCompare(Req);
  Assert.AreEqual(EXIT_SAME, R.ExitCode, R.Message);
  Assert.IsTrue(R.Format = cfGraph, 'run 2 found the chart snapshot');
  Assert.IsTrue(R.OldText.Contains('StubA'), 'the old side is run 1''s snapshot, not the seed');
end;

procedure TCompareTests.EmptyChartIsRefusedNotSame;
begin
  // a DOT the adapter cannot read gives no nodes and no edges: comparing two of those would
  // report "no differences" for two different charts, so it is refused, naming the file
  var Empty1:= WriteTemp(FTemp, 'empty1.dot', EMPTY_DOT);
  var Empty2:= WriteTemp(FTemp, 'empty2.dot', EMPTY_DOT.Replace('a -- b', 'c -- d'));
  var Good:= TPath.Combine(FTemp, 'good.dot');
  TFile.Copy(Fixture('graph', 'who-writes-a.dot'), Good);
  var Req:= Default(TCompareRequest);
  Req.Source:= csTwoFiles;
  Req.OldPath:= Empty1;
  Req.NewPath:= Empty2;
  var R:= RunCompare(Req);
  Assert.AreEqual(EXIT_SETUP, R.ExitCode, R.Message);
  Assert.AreEqual('the chart ' + Empty1 + ' parsed as empty -- cannot compare', R.Message);
  Req.OldPath:= Good;
  R:= RunCompare(Req);
  Assert.AreEqual(EXIT_SETUP, R.ExitCode, R.Message);
  Assert.AreEqual('the chart ' + Empty2 + ' parsed as empty -- cannot compare', R.Message);
end;

initialization
  TDUnitX.RegisterTestFixture(TCompareTests);

end.
