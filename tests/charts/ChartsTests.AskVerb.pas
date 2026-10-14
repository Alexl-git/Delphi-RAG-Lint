unit ChartsTests.AskVerb;

{ Cases for DRagLint.Charts.AskVerb (`drag-lint ask`): the argument set, the COMMAND line it
  names, the two output modes (plain = the producer's answer, default = its DocInsight block)
  and Ask-Report's exit codes. A stub producer answers, except in the one in-process case,
  which runs touches-tables on the FROZEN SERVER clone (a missing clone passes with a note). }

interface

uses
  DUnitX.TestFramework, DRagLint.Charts.ReportHeader, DRagLint.Charts.Producer, DRagLint.Charts.AskVerb;

type
  /// <summary>A producer that answers with fixed text and records what it was asked.</summary>
  TStubAskProducer = class(TInterfacedObject, IReportProducer)
  private
    FCalls  : Integer;
    FExit   : Integer;
    FText   : string;
    FReason : string;
    FCommand: TReportCommand;
    FOptions: TProduceOptions;
  public
    constructor Create(pExit: Integer; const pText, pReason: string);
    property Calls: Integer read FCalls;
    property Command: TReportCommand read FCommand;
    property Options: TProduceOptions read FOptions;
    function Produce(const pCommand: TReportCommand; const pOptions: TProduceOptions): TProduceResult;
    function Describe: string;
  end;

  [TestFixture]
  TAskVerbTests = class
  private
    FOut    : TArray<string>;
    FErr    : TArray<string>;
    FTempDir: string;
    function Run(const pArgv: TArray<string>; const pProducer: IReportProducer): Integer;
    function FreshIndex: string;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure ParsesThePositionalQuestionAndEveryFlag;
    [Test] procedure RejectsUnknownFlagsMissingValuesAndNonIntegers;
    [Test] procedure CommandNamesTheArgumentsAsGivenInAskReportOrder;
    [Test] procedure QuestionIdIsMatchedCaseInsensitivelyAndLowerCased;
    [Test] procedure UnknownQuestionIsSetup;
    [Test] procedure MissingTargetIsSetup;
    [Test] procedure NoIndexNamedIsSetup;
    [Test] procedure MissingIndexIsSetup;
    [Test] procedure ResolveOnlyPrintsTheIndexesAndStops;
    [Test] procedure DefaultOutputIsTheDocInsightBlockOfThePlainAnswer;
    [Test] procedure PlainOutputIsTheProducersAnswer;
    [Test] procedure ProducerRefusalKeepsItsExitCode;
    [Test] procedure StaleIndexIsExitThreeBeforeTheProducerRuns;
    [Test] procedure AllowStaleAnswersWithANote;
    [Test] procedure PortedQuestionAnswersInProcess;
    [Test] procedure HelpIsExitZero;
  end;

implementation

uses
  Winapi.Windows, System.SysUtils, System.IOUtils, DRagLint.Core.Interfaces, DRagLint.Storage.SQLite, DRagLint.Index.Freshness,
  DRagLint.Charts.DocInsight, DRagLint.Charts.Question;

const
  REPO_ROOT_ENV = 'DRAGLINT_REPO_ROOT';
  ASK_REPORT_ENV = 'DRAGLINT_ASK_REPORT';
  QUESTION_COUNT = 26;  { New-DiagramArtifact.ps1's ValidateSet }
  INDEX_LINE_NO = 3;    { the plain answer's INDEX line: header, COMMAND, ENGINE, INDEX }
  CHARTS_MARK = 'charts\src\Ask-Report.ps1';
  CLONE_DIR = 'charts\scratch\db';
  SERVER_CLONE = 'SERVER-MicroniteMW1Service.sqlite';
  DL_CLONE = 'DL-drag-lint.sqlite';
  TT_TARGET = 'uPipeSessionBuilder.TPipeSessionBuilder.HandleCopyOperation';
  CRLF = #13#10;
  { a plain answer in Ask-Report -Plain's shape }
  PLAIN_ANSWER =
    'Who reads this field (drag-lint report who-reads) for U.TA.FB, asked on 2026-10-14 09:30, engine 1.0.' + CRLF +
    'COMMAND who-reads -Target "U.TA.FB"' + CRLF +
    'BUNDLE C:\T\who-reads-U_TA_FB' + CRLF +
    'INDEX C:\T\x.sqlite' + CRLF +
    'CHART who-reads U.TA.FB -- 2 read sites / 1 routines' + CRLF +
    '  TARGET U.TA.FB @U.pas:10' + CRLF +
    '  U.TA.Run @U.pas:20' + CRLF;
  STUB_REASON = 'who-reads: no such field';

function RepoRoot: string;
begin
  var Root:= GetEnvironmentVariable(REPO_ROOT_ENV);
  if (Root <> '') and TFile.Exists(TPath.Combine(Root, CHARTS_MARK)) then
    Exit(Root);
  var Dir:= GetCurrentDir;
  while Dir <> '' do
  begin
    if TFile.Exists(TPath.Combine(Dir, CHARTS_MARK)) then
      Exit(Dir);
    var Up:= ExtractFileDir(ExcludeTrailingPathDelimiter(Dir));
    if SameText(Up, Dir) then
      Break;
    Dir:= Up;
  end;
  Result:= '';
end;

function Clone(const pName: string; out pPath: string): Boolean;
begin
  var Root:= RepoRoot;
  pPath:= if Root = '' then '' else TPath.Combine(TPath.Combine(Root, CLONE_DIR), pName);
  Result:= (pPath <> '') and TFile.Exists(pPath);
  if not Result then
    Assert.Pass('clone missing: ' + pName);
end;

function IsStale(const pDb: string): Boolean;
begin
  var Store: ISymbolStore:= TSQLiteSymbolStore.Create(pDb, True);
  Result:= ProbeIndexFreshness(Store).Verdict = fvStale;
end;

function Joined(const pLines: TArray<string>): string;
begin
  Result:= string.Join(CRLF, pLines);
end;

constructor TStubAskProducer.Create(pExit: Integer; const pText, pReason: string);
begin
  inherited Create;
  FExit:= pExit;
  FText:= pText;
  FReason:= pReason;
end;

function TStubAskProducer.Produce(const pCommand: TReportCommand; const pOptions: TProduceOptions): TProduceResult;
begin
  Inc(FCalls);
  FCommand:= pCommand;
  FOptions:= pOptions;
  Result:= Default(TProduceResult);
  Result.ExitCode:= FExit;
  Result.Ok:= FExit = 0;
  Result.Text:= FText;
  Result.Reason:= FReason;
end;

function TStubAskProducer.Describe: string;
begin
  Result:= 'stub';
end;

procedure TAskVerbTests.Setup;
begin
  FOut:= nil;
  FErr:= nil;
  FTempDir:= TPath.Combine(TPath.GetTempPath, 'drag-lint-charts-ask-' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(FTempDir);
end;

procedure TAskVerbTests.TearDown;
begin
  if TDirectory.Exists(FTempDir) then
    TDirectory.Delete(FTempDir, True);
end;

function TAskVerbTests.Run(const pArgv: TArray<string>; const pProducer: IReportProducer): Integer;
var
  A    : TAskVerbArgs;
  Error: string;
begin
  FOut:= nil;
  FErr:= nil;
  Assert.IsTrue(ParseAskArgs(pArgv, A, Error), Error);
  Result:= RunAsk(A, pProducer,
    procedure(const pLine: string)
    begin
      FOut:= FOut + [pLine];
    end,
    procedure(const pLine: string)
    begin
      FErr:= FErr + [pLine];
    end);
end;

{ An empty engine index: a real store the freshness probe can read, with no files to be stale. }
function TAskVerbTests.FreshIndex: string;
begin
  Result:= TPath.Combine(FTempDir, 'fresh.sqlite');
  var Store: ISymbolStore:= TSQLiteSymbolStore.Create(Result, False);  // dl:ok write-only-local@0fd0 -- REVIEWED 2026-10-14: held only so the store CREATES the empty index file; released (nil) before the verb opens it
  Store:= nil;
end;

procedure TAskVerbTests.ParsesThePositionalQuestionAndEveryFlag;
var
  A    : TAskVerbArgs;
  Error: string;
begin
  Assert.IsTrue(ParseAskArgs(['path', '--target', 'U.TA.Run', '--to', 'U.TB.Stop', '--project', 'P.dproj', '--in', 'U.pas',
    '--db', 'd.sqlite', '--server-db', 's.sqlite', '--sql-db', 'q.sqlite', '--counterpart-db', 'c.sqlite', '--depth', '3',
    '--cap', '5', '--surface-cap', '6', '--control', 'c1', '--mode', 'read', '--max-rows', '7', '--out-root', 'o',
    '--pairs-file', 'pf.json', '--allow-stale', '--plain', '--open', '--resolve-only'], A, Error), Error);
  Assert.AreEqual('path|U.TA.Run|U.TB.Stop|P.dproj|U.pas|d.sqlite|s.sqlite|q.sqlite|c.sqlite|3|5|6|c1|read|7|o|pf.json',
    string.Join('|', [A.Question, A.Target, A.ToRoutine, A.Project, A.InFile, A.DbPath, A.ServerDb, A.SqlDb, A.CounterpartDb,
      A.Depth, A.Cap, A.SurfaceCap, A.Control, A.Mode, A.MaxRows, A.OutRoot, A.PairsFile]));
  Assert.IsTrue(A.AllowStale and A.Plain and A.Open and A.ResolveOnly and not A.Help);
  Assert.IsTrue(ParseAskArgs(['--question', 'deps', '--target', 'X'], A, Error), Error);
  Assert.AreEqual('deps', A.Question, '--question names it too');
end;

procedure TAskVerbTests.RejectsUnknownFlagsMissingValuesAndNonIntegers;
var
  A    : TAskVerbArgs;
  Error: string;
begin
  Assert.IsFalse(ParseAskArgs(['deps', '--bogus'], A, Error));
  Assert.AreEqual('unknown argument: --bogus', Error);
  Assert.IsFalse(ParseAskArgs(['deps', '--target'], A, Error));
  Assert.AreEqual('--target needs a value', Error);
  Assert.IsFalse(ParseAskArgs(['deps', '--cap', 'x'], A, Error));
  Assert.StartsWith('--cap needs an integer', Error);
  Assert.IsFalse(ParseAskArgs(['deps', 'who-calls'], A, Error), 'a second question');
end;

procedure TAskVerbTests.CommandNamesTheArgumentsAsGivenInAskReportOrder;
var
  A    : TAskVerbArgs;
  Error: string;
begin
  { the same arguments as Test-AskReport AR-HDR-CMD-ALL, which pins Get-ReportCommandLine }
  Assert.IsTrue(ParseAskArgs(['path', '--target', 'A', '--to', 'B', '--in', 'C:\P\u.pas', '--cap', '5', '--surface-cap', '6',  // dl:ok hardcoded-absolute-path@44bd -- REVIEWED 2026-10-14: inert test string -- ParseAskArgs/BuildCommandLine only echo it; nothing touches the filesystem
    '--control', 'c1', '--mode', 'x', '--max-rows', '7', '--db', 'zz', '--plain', '--open'], A, Error), Error);
  Assert.AreEqual('path -Target "A" -To "B" -In "C:\P\u.pas" -Cap 5 -SurfaceCap 6 -Control "c1" -Mode x -MaxRows 7',
    BuildCommandLine(AskCommandOf(A)));
  Assert.IsTrue(ParseAskArgs(['who-writes', '--target', 'T', '--project', 'C:\P\A.dproj', '--in', 'C:\P\u.pas', '--depth', '3'], A, Error), Error);  // dl:ok hardcoded-absolute-path@88de -- REVIEWED 2026-10-14: inert test string -- ParseAskArgs/BuildCommandLine only echo it; nothing touches the filesystem
  Assert.AreEqual('who-writes -Target "T" -Project "C:\P\A.dproj" -Depth 3', BuildCommandLine(AskCommandOf(A)), '--project wins over --in');
end;

procedure TAskVerbTests.QuestionIdIsMatchedCaseInsensitivelyAndLowerCased;
var
  Id: string;
begin
  Assert.IsTrue(NormaliseAskQuestion('Who-Reads', Id));
  Assert.AreEqual('who-reads', Id);
  Assert.IsFalse(NormaliseAskQuestion('who-reads-x', Id));
  Assert.AreEqual(QUESTION_COUNT, Integer(Length(QuestionIds)), 'the 26 ids of New-DiagramArtifact.ps1''s ValidateSet');
end;

procedure TAskVerbTests.UnknownQuestionIsSetup;
begin
  var Stub:= TStubAskProducer.Create(0, PLAIN_ANSWER, '');
  var Keep: IReportProducer:= Stub;
  Assert.AreEqual(ASK_VERB_EXIT_SETUP, Run(['nope', '--target', 'X', '--db', 'x.sqlite'], Keep));
  Assert.StartsWith('ask-report: unknown question ''nope'' -- one of: butterfly, ', Joined(FErr));
  Assert.AreEqual(0, Integer(Length(FOut)), 'nothing on stdout for a refusal');
  Assert.AreEqual(0, Stub.Calls);
end;

procedure TAskVerbTests.MissingTargetIsSetup;
begin
  Assert.AreEqual(ASK_VERB_EXIT_SETUP, Run(['deps', '--db', 'x.sqlite'], nil));
  Assert.StartsWith('ask-report: name the target', Joined(FErr));
end;

procedure TAskVerbTests.NoIndexNamedIsSetup;
begin
  Assert.AreEqual(ASK_VERB_EXIT_SETUP, Run(['who-writes', '--target', 'U.TA.FB'], nil));
  Assert.Contains(Joined(FErr), 'name the project: --project <x.dproj> or --in <any .pas/.dfm of it>');
end;

procedure TAskVerbTests.MissingIndexIsSetup;
begin
  var Missing:= TPath.Combine(FTempDir, 'missing.sqlite');
  Assert.AreEqual(ASK_VERB_EXIT_SETUP, Run(['deps', '--target', 'X', '--db', Missing], nil));
  Assert.AreEqual('ask-report: index not found: ' + Missing, Joined(FErr));
end;

procedure TAskVerbTests.ResolveOnlyPrintsTheIndexesAndStops;
begin
  var Stub:= TStubAskProducer.Create(0, PLAIN_ANSWER, '');
  var Keep: IReportProducer:= Stub;
  var D:= TPath.Combine(FTempDir, 'c.sqlite');
  var S:= TPath.Combine(FTempDir, 's.sqlite');
  var Q:= TPath.Combine(FTempDir, 'q.sqlite');
  Assert.AreEqual(0, Run(['round-trip', '--target', 'f.C', '--db', D, '--server-db', S, '--sql-db', Q, '--resolve-only'], Keep));
  Assert.AreEqual('PROJECT ' + D + CRLF + 'SERVER ' + S + CRLF + 'SQL ' + Q, Joined(FOut));
  Assert.AreEqual(0, Stub.Calls, 'resolve-only never asks');
end;

procedure TAskVerbTests.DefaultOutputIsTheDocInsightBlockOfThePlainAnswer;
begin
  var Stub:= TStubAskProducer.Create(0, PLAIN_ANSWER, '');
  var Keep: IReportProducer:= Stub;
  var Db:= FreshIndex;
  Assert.AreEqual(0, Run(['Who-Reads', '--target', 'U.TA.FB', '--db', Db, '--out-root', FTempDir], Keep), Joined(FErr));
  { what Ask-Report's default mode printed: the DocInsight block of the -Plain answer }
  var Want:= FormatAnswerAsDocInsight(QuestionPhrase('who-reads'), 'who-reads', 'U.TA.FB', Now, PLAIN_ANSWER);
  Assert.AreEqual(Want, Joined(FOut) + CRLF);
  Assert.AreEqual('/// <remarks>', FOut[0]);
  { the producer got the resolved index, every check done, and the question as asked }
  Assert.AreEqual(1, Stub.Calls);
  Assert.AreEqual(Db, Stub.Options.DbOverride);
  Assert.IsTrue(Stub.Options.AllowStale, 'freshness is checked before the producer runs');
  Assert.AreEqual(FTempDir, Stub.Options.OutRoot);
  Assert.AreEqual('who-reads -Target "U.TA.FB"', BuildCommandLine(Stub.Command));
end;

procedure TAskVerbTests.PlainOutputIsTheProducersAnswer;
begin
  var Keep: IReportProducer:= TStubAskProducer.Create(0, PLAIN_ANSWER, '');
  Assert.AreEqual(0, Run(['who-reads', '--target', 'U.TA.FB', '--db', FreshIndex, '--plain'], Keep), Joined(FErr));
  Assert.AreEqual(PLAIN_ANSWER, Joined(FOut) + CRLF);
end;

procedure TAskVerbTests.ProducerRefusalKeepsItsExitCode;
begin
  var Keep: IReportProducer:= TStubAskProducer.Create(ASK_VERB_EXIT_REFUSED, '', STUB_REASON);
  Assert.AreEqual(ASK_VERB_EXIT_REFUSED, Run(['who-reads', '--target', 'U.TA.FB', '--db', FreshIndex], Keep));
  Assert.AreEqual('ask-report: ' + STUB_REASON, FErr[High(FErr)], 'the refusal is the last stderr line (an empty index adds a no-freshness note first)');
  Assert.AreEqual(0, Integer(Length(FOut)));
  Keep:= TStubAskProducer.Create(ASK_VERB_EXIT_SETUP, '', 'pwsh.exe (PowerShell 7) not found');
  Assert.AreEqual(ASK_VERB_EXIT_SETUP, Run(['butterfly', '--target', 'U.TA.Run', '--db', FreshIndex], Keep));
end;

procedure TAskVerbTests.StaleIndexIsExitThreeBeforeTheProducerRuns;
var
  Db: string;
begin
  if not Clone(DL_CLONE, Db) then
    Exit;
  if not IsStale(Db) then
    Assert.Pass('the DL clone is fresh; AR-STALE needs it stale');
  var Stub:= TStubAskProducer.Create(0, PLAIN_ANSWER, '');
  var Keep: IReportProducer:= Stub;
  Assert.AreEqual(ASK_VERB_EXIT_STALE, Run(['who-calls', '--target', 'DRagLint.CLI.Main', '--db', Db], Keep));
  Assert.StartsWith('ask-report: stale index -- the answer would be short or wrong. Reindex incrementally, then ask again:', Joined(FErr));
  Assert.Contains(Joined(FErr), Db + ': ');
  Assert.Contains(Joined(FErr), 'file(s) changed since it was indexed');
  Assert.AreEqual(0, Stub.Calls, 'nothing runs for a stale index');
end;

procedure TAskVerbTests.AllowStaleAnswersWithANote;
var
  Db: string;
begin
  if not Clone(DL_CLONE, Db) then
    Exit;
  if not IsStale(Db) then
    Assert.Pass('the DL clone is fresh');
  var Keep: IReportProducer:= TStubAskProducer.Create(0, PLAIN_ANSWER, '');
  Assert.AreEqual(0, Run(['deps', '--target', 'DRagLint.CLI', '--db', Db, '--allow-stale', '--plain'], Keep));
  Assert.StartsWith('ask-report: note -- stale index allowed by --allow-stale: ', Joined(FErr));
end;

procedure TAskVerbTests.PortedQuestionAnswersInProcess;
var
  Db: string;
begin
  if not Clone(SERVER_CLONE, Db) then
    Exit;
  var Prev:= GetEnvironmentVariable(ASK_REPORT_ENV);
  SetEnvironmentVariable(ASK_REPORT_ENV, PChar(TPath.Combine(RepoRoot, CHARTS_MARK)));
  try
    var Code:= Run(['touches-tables', '--target', TT_TARGET, '--db', Db, '--allow-stale', '--plain', '--out-root', FTempDir], nil);
    Assert.AreEqual(0, Code, Joined(FErr));
    Assert.Contains(Joined(FOut), CRLF + 'CHART touches-tables ' + TT_TARGET + ' -- 5 tables read / 5 tables written' + CRLF);
    Assert.AreEqual('COMMAND touches-tables -Target "' + TT_TARGET + '"', FOut[1]);
    Assert.AreEqual('INDEX ' + Db, FOut[INDEX_LINE_NO]);
  finally
    SetEnvironmentVariable(ASK_REPORT_ENV, if Prev = '' then nil else PChar(Prev));
  end;
end;

procedure TAskVerbTests.HelpIsExitZero;
begin
  Assert.AreEqual(0, Run(['--help'], nil));
  Assert.StartsWith('Usage: drag-lint ask <question> --target <T>', FOut[0]);
end;

end.
