unit ChartsTests.ProducerDelphi;

{ Cases for DRagLint.Charts.Producer.Delphi: which producer compare gets (the Delphi one, on live
  indexes), that the clone guard still holds where live is not allowed, what is answered
  in-process and what is refused (there is no fallback), and the exit codes of Ask-Report's
  contract. The in-process cases run against the FROZEN clones (a missing clone passes with a note). }

interface

uses
  DUnitX.TestFramework, DRagLint.Charts.ReportHeader, DRagLint.Charts.Producer;

type
  [TestFixture]
  TProducerDelphiTests = class
  private
    FProducer: IReportProducer;
    FOutRoot : string;
    function Clone(const pName: string; out pPath: string): Boolean;
    function PairsFile(const pClient, pServer, pSql: string): string;
    function FakeEngine(const pKnown: string): string;
    function FakeProjectEngine(const pBody: string): string;
    function ProjectFile: string;
    procedure CheckCounterpartDrawn(const pR: TProduceResult; const pOther, pTarget: string);
    function PairedOptions(const pDb, pClient, pServer, pKnown: string): TProduceOptions;
    procedure CheckFeedsFromReadsSql(const pR: TProduceResult; const pSql: string);
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure CompareGetsTheDelphiProducerOnLiveIndexes;
    [Test] procedure CloneGuardStaysOnWhenLiveIsNotAllowed;
    [Test] procedure UnregisteredQuestionIsRefused;
    [Test] procedure MissingProjectFileIsSetup;
    [Test] procedure ProjectIsResolvedToItsIndexInProcess;
    [Test] procedure ProjectWhoseIndexIsNotBuiltIsSetup;
    [Test] procedure ProjectNoManifestSectionOwnsIsSetup;
    [Test] procedure PortedQuestionIsAnsweredInProcess;
    [Test] procedure StaleIndexRefusesWithoutAllowStale;
    [Test] procedure MissingIndexIsSetup;
    [Test] procedure RefusalIsExitOne;
    [Test] procedure UnknownTargetIsExitOne;
    [Test] procedure CloneGuardRefusalIsSetup;
    [Test] procedure UnexpectedFailureIsRefusedExitOne;
    [Test] procedure CrossesBoundaryPairsItsCounterpartFromThePairsFile;
    [Test] procedure CrossesBoundaryWithoutAPairDrawsOneSideAsAskReportDoes;
    [Test] procedure CrossesBoundaryWithoutAnIndexIsSetup;
    [Test] procedure CrossesBoundaryFromTheServerSideDbPairsTheClient;
    [Test] procedure CrossesBoundaryWithAMissingCounterpartFileIsSetup;
    [Test] procedure CrossesBoundaryWithAnUnconfiguredPairEntryIsRefused;
    [Test] procedure CrossesBoundaryWithCounterpartIsInProcess;
    [Test] procedure OtherIndexesAQuestionDoesNotReadAreIgnored;
    [Test] procedure MissingSqlIndexOfAReadingQuestionIsSetup;
    [Test] procedure SqlIndexOfAReadingQuestionIsCarriedAndChecked;
    [Test] procedure MissingServerIndexOfAReadingQuestionIsSetup;
    [Test] procedure ServerAndSqlIndexesAreCarriedInAskReportOrder;
    [Test] procedure ReadingQuestionPairsItsSqlIndexFromThePairsFile;
    [Test] procedure ReadingQuestionWithoutAPairsFileIsAskReportsSetup;
    [Test] procedure ReadingQuestionWithNoEntryIsAskReportsSetup;
    [Test] procedure ServerIndexIsPairedOnlyFromTheClient;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, DRagLint.Core.Interfaces, DRagLint.Storage.SQLite, DRagLint.Index.Freshness,
  DRagLint.Charts.Question, DRagLint.Charts.Producer.Delphi;

const
  REPO_ROOT_ENV = 'DRAGLINT_REPO_ROOT';
  CHARTS_MARK = 'charts\src\Ask-Report.ps1';
  CLONE_DIR = 'charts\scratch\db';
  SERVER_CLONE = 'SERVER-MicroniteMW1Service.sqlite';
  CLIENT_CLONE = 'CLIENT-Micronite2027.sqlite';
  CLIENT_HISTORY = 'CLIENT-Micronite2027.sqlite.pre-1.10';
  NO_SUCH_TARGET = 'NoSuchUnit.TNoSuchClass.NoSuchMethod';
  TT_TARGET = 'uPipeSessionBuilder.TPipeSessionBuilder.HandleCopyOperation';
  CB_TARGET = 'Blueprint4.ViewModel.TBlueprint_ViewModel.SendDeltaOperation';
  SQL_CLONE = 'SQL-drag-lint-sql.sqlite';
  FF_TARGET = 'frmCausFail.colREASON';
  LW_TARGET = 'uCAUSFAIL.TmcCAUSFAIL.REASON';
  EXIT_SETUP = 2;

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

{ the engine's own freshness verdict for a clone; the store is closed on return }
function IsStale(const pDb: string): Boolean;
begin
  var Store: ISymbolStore:= TSQLiteSymbolStore.Create(pDb, True);
  Result:= ProbeIndexFreshness(Store).Verdict = fvStale;
end;

function Cmd(const pQuestion, pTarget: string; const pProject: string = ''): TReportCommand;
begin
  Result:= Default(TReportCommand);
  Result.Question:= pQuestion;
  var A: TCommandArg;
  A.Name:= 'Target';
  A.Value:= pTarget;
  Result.Args:= [A];
  if pProject <> '' then
  begin
    A.Name:= 'Project';
    A.Value:= pProject;
    Result.Args:= Result.Args + [A];
  end;
end;

procedure TProducerDelphiTests.Setup;
begin
  FOutRoot:= TPath.Combine(TPath.GetTempPath, 'drag-lint-charts-p-' + TGUID.NewGuid.ToString);
  FProducer:= TDelphiProducer.Create(True, FOutRoot);
end;

procedure TProducerDelphiTests.TearDown;
begin
  FProducer:= nil;
  if TDirectory.Exists(FOutRoot) then
    TDirectory.Delete(FOutRoot, True);
end;

function TProducerDelphiTests.Clone(const pName: string; out pPath: string): Boolean;
begin
  var Root:= RepoRoot;
  pPath:= if Root = '' then '' else TPath.Combine(TPath.Combine(Root, CLONE_DIR), pName);
  Result:= (pPath <> '') and TFile.Exists(pPath);
  if not Result then
    Assert.Pass('clone missing: ' + pName);
end;

procedure TProducerDelphiTests.CompareGetsTheDelphiProducerOnLiveIndexes;
begin
  { owner ruling 2026-10-14: compare answers ported questions in-process on the LIVE index }
  var P:= ProducerForCompare;
  { P is an INTERFACE: 'as TObject' is the interface-to-object cast, not a redundant one }
  var O:= P as TObject;  // dl:ok redundant-as-tobject@60a8 -- FALSE POSITIVE: P is an IReportProducer, and 'as TObject' is the only interface-to-object cast (logged to draglint-gaps.log)
  Assert.IsTrue(O is TDelphiProducer, 'compare gets the Delphi producer');
  Assert.IsTrue(TDelphiProducer(O).AllowLiveDb, 'live indexes allowed; the staleness refusal protects them');
  Assert.Contains(P.Describe, 'Delphi in-process (');
end;

procedure TProducerDelphiTests.CloneGuardStaysOnWhenLiveIsNotAllowed;
begin
  { the parity / test path: a valid, fresh index outside the clone root is refused by the guard }
  TDirectory.CreateDirectory(FOutRoot);
  var Live:= TPath.Combine(FOutRoot, 'live.sqlite');
  var Store: ISymbolStore:= TSQLiteSymbolStore.Create(Live, False);  // dl:ok write-only-local@e429 -- REVIEWED 2026-10-14: held only so the store CREATES the index file; released (nil) before Produce opens it
  Store:= nil;
  FProducer:= TDelphiProducer.Create(False, FOutRoot);
  var O:= DefaultProduceOptions;
  O.DbOverride:= Live;
  O.ScriptPath:= TPath.Combine(RepoRoot, CHARTS_MARK);
  var R:= FProducer.Produce(Cmd('deps', 'X'), O);
  Assert.AreEqual(EXIT_SETUP, R.ExitCode, R.Reason);
  Assert.StartsWith('refusing a non-clone database: ', R.Reason);
end;

{ Since the round-trip port every one of the 26 question ids is registered, so the registry-miss fallback is reached
  only by an id outside the registry; 'member-access' is not a question id (QuestionIds has 26), which is exactly
  what makes it a registry miss. The mechanism under test (registry miss -> FallBack) is unchanged. }
procedure TProducerDelphiTests.UnregisteredQuestionIsRefused;
begin
  var O:= DefaultProduceOptions;
  O.DbOverride:= 'any.sqlite';
  var R:= FProducer.Produce(Cmd('member-access', 'A.B'), O);
  Assert.AreEqual(EXIT_SETUP, R.ExitCode, R.Reason);
  Assert.StartsWith('unknown question ''member-access'' -- one of: ', R.Reason);
  Assert.Contains(FProducer.Describe, 'Delphi in-process, refused: unknown question');
end;

{ an empty X.dproj under the out root: resolution reads only the path, never the file }
function TProducerDelphiTests.ProjectFile: string;
begin
  TDirectory.CreateDirectory(FOutRoot);
  Result:= TPath.Combine(FOutRoot, 'X.dproj');
  TFile.WriteAllText(Result, '');
end;

{ a stand-in engine whose whole answer is pBody (a cmd script), whatever it is asked }
function TProducerDelphiTests.FakeProjectEngine(const pBody: string): string;
begin
  TDirectory.CreateDirectory(FOutRoot);
  Result:= TPath.Combine(FOutRoot, 'fake-project-engine.cmd');
  TFile.WriteAllText(Result, pBody + #13#10, TEncoding.ASCII);
end;

procedure TProducerDelphiTests.MissingProjectFileIsSetup;
begin
  { Ask-Report's step 1 refusal, before any engine is asked }
  var Missing:= TPath.Combine(FOutRoot, 'NoSuch.dproj');
  var R:= FProducer.Produce(Cmd('touches-tables', TT_TARGET, Missing), DefaultProduceOptions);
  Assert.AreEqual(EXIT_SETUP, R.ExitCode, R.Reason);
  Assert.AreEqual('project file not found: ' + Missing, R.Reason);
end;

procedure TProducerDelphiTests.ProjectIsResolvedToItsIndexInProcess;
var
  Db: string;
begin
  { compare names only a project: the index is the one resolve-dbs --project names, and the
    question is answered in-process from it -- no fallback, no PowerShell }
  if not Clone(SERVER_CLONE, Db) then
    Exit;
  var O:= DefaultProduceOptions;
  O.EnginePath:= FakeProjectEngine('@echo {"project":"x","section":"s","db":"' + Db.Replace('\', '\\') + '"}');
  O.ScriptPath:= TPath.Combine(RepoRoot, CHARTS_MARK);
  O.AllowStale:= True;
  var R:= FProducer.Produce(Cmd('touches-tables', TT_TARGET, ProjectFile), O);
  Assert.IsTrue(R.Ok, R.Reason);
  Assert.AreEqual(Db, R.IndexPaths[0]);
  Assert.Contains(R.Text, #13#10'CHART touches-tables ' + TT_TARGET + ' -- ');
  Assert.AreEqual('Delphi in-process (touches-tables)', FProducer.Describe);
end;

procedure TProducerDelphiTests.ProjectWhoseIndexIsNotBuiltIsSetup;
begin
  var Db:= TPath.Combine(TPath.Combine(FOutRoot, '_D-RAG'), 'X.sqlite');
  var O:= DefaultProduceOptions;
  O.EnginePath:= FakeProjectEngine('@echo {"project":"x","section":"s","db":"' + Db.Replace('\', '\\') + '"}');
  var Pj:= ProjectFile;
  var R:= FProducer.Produce(Cmd('who-writes', 'A.B', Pj), O);
  Assert.AreEqual(EXIT_SETUP, R.ExitCode, R.Reason);
  Assert.AreEqual('index not found: ' + Db + ' -- resolve-dbs --project ' + Pj + ' names it, but it has not been built; ' +
    'index the project first', R.Reason);
end;

procedure TProducerDelphiTests.ProjectNoManifestSectionOwnsIsSetup;
begin
  { resolve-dbs --project exits 2 with no JSON: Ask-Report's own refusal }
  var O:= DefaultProduceOptions;
  O.EnginePath:= FakeProjectEngine('@exit /b 2');
  var Pj:= ProjectFile;
  var R:= FProducer.Produce(Cmd('round-trip', 'A.B', Pj), O);
  Assert.AreEqual(EXIT_SETUP, R.ExitCode, R.Reason);
  Assert.AreEqual('resolve-dbs --project ' + Pj + ' found no index (exit 2) -- the project is not in the engine''s index manifest', R.Reason);
end;

procedure TProducerDelphiTests.PortedQuestionIsAnsweredInProcess;
var
  Db: string;
begin
  if not Clone(SERVER_CLONE, Db) then
    Exit;
  var O:= DefaultProduceOptions;
  O.DbOverride:= Db;
  O.ScriptPath:= TPath.Combine(RepoRoot, CHARTS_MARK);
  O.AllowStale:= True;
  var R:= FProducer.Produce(Cmd('touches-tables', TT_TARGET), O);
  Assert.IsTrue(R.Ok, R.Reason);
  Assert.Contains(R.Text, #13#10'CHART touches-tables ' + TT_TARGET + ' -- 5 tables read / 5 tables written'#13#10);
  Assert.AreEqual(Db, R.IndexPaths[0]);
  Assert.IsTrue(TFile.Exists(TPath.Combine(R.BundlePath, 'graph.dot')));
  Assert.AreEqual('Delphi in-process (touches-tables)', FProducer.Describe);
end;

procedure TProducerDelphiTests.StaleIndexRefusesWithoutAllowStale;
var
  Db: string;
begin
  if not Clone(SERVER_CLONE, Db) then
    Exit;
  var Stale:= IsStale(Db);
  var O:= DefaultProduceOptions;
  O.DbOverride:= Db;
  O.ScriptPath:= TPath.Combine(RepoRoot, CHARTS_MARK);
  var R:= FProducer.Produce(Cmd('touches-tables', TT_TARGET), O);
  if Stale then
  begin
    Assert.AreEqual(PRODUCER_EXIT_STALE, R.ExitCode);
    Assert.StartsWith('stale index -- the answer would be short or wrong.', R.Reason);
  end
  else
    Assert.IsTrue(R.Ok, 'a fresh clone answers');
end;

procedure TProducerDelphiTests.MissingIndexIsSetup;
begin
  var O:= DefaultProduceOptions;
  O.DbOverride:= TPath.Combine(FOutRoot, 'missing.sqlite');
  var R:= FProducer.Produce(Cmd('deps', 'X'), O);
  Assert.AreEqual(EXIT_SETUP, R.ExitCode);
  Assert.StartsWith('index not found: ', R.Reason);
end;

procedure TProducerDelphiTests.RefusalIsExitOne;
var
  Db: string;
begin
  if not Clone(CLIENT_CLONE, Db) then
    Exit;
  var O:= DefaultProduceOptions;
  O.DbOverride:= Db;
  O.ScriptPath:= TPath.Combine(RepoRoot, CHARTS_MARK);
  O.AllowStale:= True;
  var R:= FProducer.Produce(Cmd('touches-tables', TT_TARGET), O);
  Assert.AreEqual(1, R.ExitCode);
  Assert.IsFalse(R.Ok);
  Assert.StartsWith('touches-tables: this index has NO SQL facts at all', R.Reason);
end;


procedure TProducerDelphiTests.UnknownTargetIsExitOne;
var
  Db: string;
begin
  if not Clone(SERVER_CLONE, Db) then
    Exit;
  var O:= DefaultProduceOptions;
  O.DbOverride:= Db;
  O.ScriptPath:= TPath.Combine(RepoRoot, CHARTS_MARK);
  O.AllowStale:= True;
  var R:= FProducer.Produce(Cmd('touches-tables', NO_SUCH_TARGET), O);
  Assert.AreEqual(1, R.ExitCode, R.Reason);
  Assert.Contains(R.Reason, 'is not in this index');
end;

procedure TProducerDelphiTests.CloneGuardRefusalIsSetup;
var
  Db: string;
begin
  { a history copy in the clone root: a valid index, but the clone guard refuses its name }
  if not Clone(CLIENT_HISTORY, Db) then
    Exit;
  FProducer:= TDelphiProducer.Create(False, FOutRoot);  { clone guard ON for this case }
  var O:= DefaultProduceOptions;
  O.DbOverride:= Db;
  O.ScriptPath:= TPath.Combine(RepoRoot, CHARTS_MARK);
  O.AllowStale:= True;
  var R:= FProducer.Produce(Cmd('touches-tables', TT_TARGET), O);
  Assert.AreEqual(EXIT_SETUP, R.ExitCode, R.Reason);
  Assert.StartsWith('refusing a database whose name does not end in .sqlite', R.Reason);
end;

procedure TProducerDelphiTests.UnexpectedFailureIsRefusedExitOne;
begin
  { not an index at all: the freshness probe fails inside the try, which is a failure of the
    in-process path, not a verdict -- it is refused with exit 1 and nothing escapes }
  TDirectory.CreateDirectory(FOutRoot);
  var Bad:= TPath.Combine(FOutRoot, 'corrupt.sqlite');
  TFile.WriteAllText(Bad, 'this is not an SQLite database');
  var O:= DefaultProduceOptions;
  O.DbOverride:= Bad;
  O.ScriptPath:= TPath.Combine(RepoRoot, CHARTS_MARK);
  var R:= FProducer.Produce(Cmd('deps', 'X'), O);
  Assert.AreEqual(1, R.ExitCode, R.Reason);
  Assert.StartsWith('the in-process answer failed (', R.Reason);
  Assert.Contains(FProducer.Describe, 'Delphi in-process failed (');
end;

procedure TProducerDelphiTests.CrossesBoundaryWithoutAnIndexIsSetup;
begin
  { neither an index nor a project: nothing to resolve in-process, so the question is refused }
  var O:= DefaultProduceOptions;
  var R:= FProducer.Produce(Cmd('crosses-boundary', CB_TARGET), O);
  Assert.AreEqual(EXIT_SETUP, R.ExitCode, R.Reason);
  Assert.StartsWith('no index given (--db / -Db) and no project named', R.Reason);
  Assert.Contains(FProducer.Describe, 'Delphi in-process, refused: no index given');
end;

procedure TProducerDelphiTests.CrossesBoundaryPairsItsCounterpartFromThePairsFile;
var
  Db, Other: string;
begin
  { compare passes only --db (R5): the far side is paired from report-pairs.json as Ask-Report's
    step 2 pairs it (the pair's other side), checked with resolve-dbs, and carried like any index }
  if not Clone(CLIENT_CLONE, Db) or not Clone(SERVER_CLONE, Other) then
    Exit;
  var O:= PairedOptions(Db, Db, Other, Other);
  var R:= FProducer.Produce(Cmd('crosses-boundary', CB_TARGET), O);
  CheckCounterpartDrawn(R, Other, CB_TARGET);
  Assert.Contains(R.Text, 'CHART crosses-boundary ' + CB_TARGET + ' -- 2 commands / 1 transport calls'#13#10);
end;

procedure TProducerDelphiTests.CrossesBoundaryWithoutAPairDrawsOneSideAsAskReportDoes;
var
  Db: string;
begin
  { Ask-Report.ps1:262 -- no pair names the project: no refusal, no counterpart, one side drawn }
  if not Clone(CLIENT_CLONE, Db) then
    Exit;
  var O:= DefaultProduceOptions;
  O.DbOverride:= Db;
  O.PairsFile:= PairsFile(TPath.Combine(FOutRoot, 'someone-else.sqlite'), TPath.Combine(FOutRoot, 'server.sqlite'), '');
  O.ScriptPath:= TPath.Combine(RepoRoot, CHARTS_MARK);
  O.AllowStale:= True;
  var R:= FProducer.Produce(Cmd('crosses-boundary', CB_TARGET), O);
  Assert.IsTrue(R.Ok, R.Reason);
  Assert.IsFalse(R.Text.Contains('(counterpart)'), 'no counterpart line');
  Assert.AreEqual<Integer>(1, Length(R.IndexPaths));
  Assert.AreEqual('Delphi in-process (crosses-boundary)', FProducer.Describe);
end;

procedure TProducerDelphiTests.CrossesBoundaryFromTheServerSideDbPairsTheClient;
var
  Db, Other: string;
begin
  { --db is the pair's SERVER: the counterpart is the pair's CLIENT (Ask-Report.ps1:270, the else side) }
  if not Clone(SERVER_CLONE, Db) or not Clone(CLIENT_CLONE, Other) then
    Exit;
  var O:= PairedOptions(Db, Other, Db, Other);
  var R:= FProducer.Produce(Cmd('crosses-boundary', TT_TARGET), O);
  CheckCounterpartDrawn(R, Other, TT_TARGET);
  Assert.AreEqual(Other, R.IndexPaths[1]);
end;

procedure TProducerDelphiTests.CrossesBoundaryWithAMissingCounterpartFileIsSetup;
var
  Db: string;
begin
  { the paired counterpart is configured but its file is gone: Ask-Report.ps1:298, exit 2, no fallback }
  if not Clone(CLIENT_CLONE, Db) then
    Exit;
  var Missing:= TPath.Combine(FOutRoot, 'missing-server.sqlite');
  var O:= PairedOptions(Db, Db, Missing, Missing);
  var R:= FProducer.Produce(Cmd('crosses-boundary', CB_TARGET), O);
  Assert.AreEqual(EXIT_SETUP, R.ExitCode, R.Reason);
  Assert.AreEqual('index not found: ' + Missing, R.Reason);
end;

procedure TProducerDelphiTests.CrossesBoundaryWithAnUnconfiguredPairEntryIsRefused;
var
  Db, Other: string;
begin
  { the pairs file names a counterpart the engine's manifest no longer configures (resolve-dbs):
    Ask-Report.ps1:279, exit 2, before any index is opened }
  if not Clone(CLIENT_CLONE, Db) or not Clone(SERVER_CLONE, Other) then
    Exit;
  var O:= PairedOptions(Db, Db, Other, Db);
  var R:= FProducer.Produce(Cmd('crosses-boundary', CB_TARGET), O);
  Assert.AreEqual(EXIT_SETUP, R.ExitCode, R.Reason);
  Assert.AreEqual(O.PairsFile + ' names ' + Other + ', which the engine''s manifest no longer configures (resolve-dbs) -- fix the pair',
    R.Reason);
end;

procedure TProducerDelphiTests.CrossesBoundaryWithCounterpartIsInProcess;
var
  Db, Other: string;
begin
  if not Clone(CLIENT_CLONE, Db) or not Clone(SERVER_CLONE, Other) then
    Exit;
  var O:= DefaultProduceOptions;
  O.DbOverride:= Db;
  O.CounterpartDbOverride:= Other;
  O.ScriptPath:= TPath.Combine(RepoRoot, CHARTS_MARK);
  O.AllowStale:= True;
  var R:= FProducer.Produce(Cmd('crosses-boundary', CB_TARGET), O);
  Assert.IsTrue(R.Ok, R.Reason);
  Assert.Contains(R.Text, #13#10'INDEX ' + Other + ' (counterpart)'#13#10'CHART crosses-boundary ' + CB_TARGET +
    ' -- 2 commands / 1 transport calls'#13#10);
  Assert.AreEqual<Integer>(2, Length(R.IndexPaths));
  Assert.AreEqual('Delphi in-process (crosses-boundary)', FProducer.Describe);
end;

procedure TProducerDelphiTests.OtherIndexesAQuestionDoesNotReadAreIgnored;
var
  Db: string;
begin
  { Ask-Report checks and names only the indexes the question reads ($needServer / $needSql):
    touches-tables reads neither, so a server and SQL index given anyway -- even missing
    ones -- are not opened, not freshness-checked and not named }
  if not Clone(SERVER_CLONE, Db) then
    Exit;
  var O:= DefaultProduceOptions;
  O.DbOverride:= Db;
  O.ServerDbOverride:= TPath.Combine(FOutRoot, 'missing-server.sqlite');
  O.SqlDbOverride:= TPath.Combine(FOutRoot, 'missing-sql.sqlite');
  O.ScriptPath:= TPath.Combine(RepoRoot, CHARTS_MARK);
  O.AllowStale:= True;
  var R:= FProducer.Produce(Cmd('touches-tables', TT_TARGET), O);
  Assert.IsTrue(R.Ok, R.Reason);
  Assert.AreEqual<Integer>(1, Length(R.IndexPaths));
  Assert.DoesNotContain(R.Text, '(server)');
  Assert.DoesNotContain(R.Text, '(sql)');
end;

procedure TProducerDelphiTests.MissingSqlIndexOfAReadingQuestionIsSetup;
var
  Db: string;
begin
  { feeds-from reads the SQL index: a missing one is Ask-Report's "index not found", exit 2 }
  if not Clone(CLIENT_CLONE, Db) then
    Exit;
  var Missing:= TPath.Combine(FOutRoot, 'missing-sql.sqlite');
  var O:= DefaultProduceOptions;
  O.DbOverride:= Db;
  O.SqlDbOverride:= Missing;
  O.ScriptPath:= TPath.Combine(RepoRoot, CHARTS_MARK);
  O.AllowStale:= True;
  var R:= FProducer.Produce(Cmd('feeds-from', FF_TARGET), O);
  Assert.AreEqual(EXIT_SETUP, R.ExitCode, R.Reason);
  Assert.AreEqual('index not found: ' + Missing, R.Reason);
end;

{ answered in-process, with the SQL index in the freshness list after the project index and named in the answer }
procedure TProducerDelphiTests.CheckFeedsFromReadsSql(const pR: TProduceResult; const pSql: string);
begin
  Assert.IsTrue(pR.Ok, pR.Reason);
  Assert.AreEqual<Integer>(2, Length(pR.IndexPaths));
  Assert.AreEqual(pSql, pR.IndexPaths[1]);
  Assert.Contains(pR.Text, #13#10'INDEX ' + pSql + ' (sql)'#13#10'CHART feeds-from ' + FF_TARGET + ' -- ');
end;
procedure TProducerDelphiTests.SqlIndexOfAReadingQuestionIsCarriedAndChecked;
var
  Db, Sql: string;
begin
  { the SQL index reaches the emitter (without it the clone guard refuses a blank path) and
    joins the freshness list after the project index; the answer names it }
  if not Clone(CLIENT_CLONE, Db) or not Clone(SQL_CLONE, Sql) then
    Exit;
  var O:= DefaultProduceOptions;
  O.DbOverride:= Db;
  O.SqlDbOverride:= Sql;
  O.ScriptPath:= TPath.Combine(RepoRoot, CHARTS_MARK);
  O.AllowStale:= True;
  CheckFeedsFromReadsSql(FProducer.Produce(Cmd('feeds-from', FF_TARGET), O), Sql);
  Assert.AreEqual('Delphi in-process (feeds-from)', FProducer.Describe);
end;

procedure TProducerDelphiTests.MissingServerIndexOfAReadingQuestionIsSetup;
var
  Db, Sql: string;
begin
  { lands-where reads the SERVER index: a missing one is Ask-Report's "index not found", exit 2, before the SQL index is looked at }
  if not Clone(CLIENT_CLONE, Db) or not Clone(SQL_CLONE, Sql) then
    Exit;
  var Missing:= TPath.Combine(FOutRoot, 'missing-server.sqlite');
  var O:= DefaultProduceOptions;
  O.DbOverride:= Db;
  O.ServerDbOverride:= Missing;
  O.SqlDbOverride:= Sql;
  O.ScriptPath:= TPath.Combine(RepoRoot, CHARTS_MARK);
  O.AllowStale:= True;
  var R:= FProducer.Produce(Cmd('lands-where', LW_TARGET), O);
  Assert.AreEqual(EXIT_SETUP, R.ExitCode, R.Reason);
  Assert.AreEqual('index not found: ' + Missing, R.Reason);
end;

procedure TProducerDelphiTests.ServerAndSqlIndexesAreCarriedInAskReportOrder;
const
  PROJECT_SERVER_SQL = 3;
var
  Db, Server, Sql: string;
begin
  { both extra indexes reach the emitter and the freshness list: project, server, sql }
  if not Clone(CLIENT_CLONE, Db) or not Clone(SERVER_CLONE, Server) or not Clone(SQL_CLONE, Sql) then
    Exit;
  var O:= DefaultProduceOptions;
  O.DbOverride:= Db;
  O.ServerDbOverride:= Server;
  O.SqlDbOverride:= Sql;
  O.ScriptPath:= TPath.Combine(RepoRoot, CHARTS_MARK);
  O.AllowStale:= True;
  var R:= FProducer.Produce(Cmd('lands-where', LW_TARGET), O);
  Assert.IsTrue(R.Ok, R.Reason);
  Assert.AreEqual<Integer>(PROJECT_SERVER_SQL, Length(R.IndexPaths));
  Assert.AreEqual(Server, R.IndexPaths[1]);
  Assert.AreEqual(Sql, R.IndexPaths[2]);
  Assert.Contains(R.Text, #13#10'INDEX ' + Server + ' (server)'#13#10'INDEX ' + Sql + ' (sql)'#13#10'CHART lands-where ' + LW_TARGET + ' -- ');
  Assert.AreEqual('Delphi in-process (lands-where)', FProducer.Describe);
end;

{ report-pairs.json in the test folder with one pair }
function TProducerDelphiTests.PairsFile(const pClient, pServer, pSql: string): string;
begin
  TDirectory.CreateDirectory(FOutRoot);
  Result:= TPath.Combine(FOutRoot, 'report-pairs.json');
  TFile.WriteAllText(Result, Format('{"pairs":[{"name":"t","client":"%s","server":"%s","sql":"%s"}]}',
    [pClient.Replace('\', '\\'), pServer.Replace('\', '\\'), pSql.Replace('\', '\\')]));
end;

{ an engine stand-in whose `resolve-dbs --json` lists one configured index }
function TProducerDelphiTests.FakeEngine(const pKnown: string): string;
begin
  TDirectory.CreateDirectory(FOutRoot);
  Result:= TPath.Combine(FOutRoot, 'fake-engine.cmd');
  TFile.WriteAllText(Result, '@echo ["' + pKnown.Replace('\', '\\') + '"]' + #13#10, TEncoding.ASCII);
end;

{ a crosses-boundary answer in-process, with pOther carried as the counterpart: no fallback, two indexes }
procedure TProducerDelphiTests.CheckCounterpartDrawn(const pR: TProduceResult; const pOther, pTarget: string);
begin
  Assert.IsTrue(pR.Ok, pR.Reason);
  Assert.Contains(pR.Text, #13#10'INDEX ' + pOther + ' (counterpart)'#13#10'CHART crosses-boundary ' + pTarget + ' -- ');
  Assert.AreEqual<Integer>(2, Length(pR.IndexPaths));
end;

{ options for a --db-only compare run: pairs file with one client/server pair, fake engine listing pKnown as configured }
function TProducerDelphiTests.PairedOptions(const pDb, pClient, pServer, pKnown: string): TProduceOptions;
begin
  Result:= DefaultProduceOptions;
  Result.DbOverride:= pDb;
  Result.PairsFile:= PairsFile(pClient, pServer, '');
  Result.EnginePath:= FakeEngine(pKnown);
  Result.ScriptPath:= TPath.Combine(RepoRoot, CHARTS_MARK);
  Result.AllowStale:= True;
end;

procedure TProducerDelphiTests.ReadingQuestionPairsItsSqlIndexFromThePairsFile;
var
  Db, Sql: string;
begin
  { compare passes only --db (R5): the SQL index feeds-from reads is paired from report-pairs.json,
    as Ask-Report's step 2 pairs it, and the path taken from the file is checked with resolve-dbs }
  if not Clone(CLIENT_CLONE, Db) or not Clone(SQL_CLONE, Sql) then
    Exit;
  var O:= DefaultProduceOptions;
  O.DbOverride:= Db;
  O.PairsFile:= PairsFile(Db, '', Sql);
  O.EnginePath:= FakeEngine(Sql);
  O.ScriptPath:= TPath.Combine(RepoRoot, CHARTS_MARK);
  O.AllowStale:= True;
  CheckFeedsFromReadsSql(FProducer.Produce(Cmd('feeds-from', FF_TARGET), O), Sql);
end;

procedure TProducerDelphiTests.ReadingQuestionWithoutAPairsFileIsAskReportsSetup;
begin
  { no report-pairs.json: Ask-Report's exit 2 and message, before the index itself is looked at }
  var Missing:= TPath.Combine(FOutRoot, 'report-pairs.json');
  var O:= DefaultProduceOptions;
  O.DbOverride:= 'any.sqlite';
  O.PairsFile:= Missing;
  O.ScriptPath:= TPath.Combine(RepoRoot, CHARTS_MARK);
  var R:= FProducer.Produce(Cmd('feeds-from', FF_TARGET), O);
  Assert.AreEqual(EXIT_SETUP, R.ExitCode, R.Reason);
  Assert.AreEqual('feeds-from also reads the SQL-script index, and report-pairs.json not found at ' + Missing +
    ', so no pairs are configured -- copy charts\report-pairs.example.json to that path and fill in client, server and sql ' +
    '(each checked with resolve-dbs), or pass -SqlDbPath', R.Reason);
end;

procedure TProducerDelphiTests.ReadingQuestionWithNoEntryIsAskReportsSetup;
begin
  { a pairing file without an entry for the index: Ask-Report's exit 2 and message }
  var O:= DefaultProduceOptions;
  O.DbOverride:= 'any.sqlite';
  O.PairsFile:= PairsFile(TPath.Combine(FOutRoot, 'client.sqlite'), TPath.Combine(FOutRoot, 'server.sqlite'), TPath.Combine(FOutRoot, 'sql.sqlite'));
  O.ScriptPath:= TPath.Combine(RepoRoot, CHARTS_MARK);
  var R:= FProducer.Produce(Cmd('lands-where', LW_TARGET), O);
  Assert.AreEqual(EXIT_SETUP, R.ExitCode, R.Reason);
  Assert.AreEqual('lands-where also reads the SERVER index and the SQL-script index, and ' + O.PairsFile +
    ' has no entry for any.sqlite -- add one (client, server, sql; check each with resolve-dbs), or pass -ServerDbPath and -SqlDbPath', R.Reason);
end;

procedure TProducerDelphiTests.ServerIndexIsPairedOnlyFromTheClient;
begin
  { lands-where starts from the CLIENT: given the pair's SERVER, Ask-Report refuses with exit 2 }
  var Server:= TPath.Combine(FOutRoot, 'server.sqlite');
  var O:= DefaultProduceOptions;
  O.DbOverride:= Server;
  O.PairsFile:= PairsFile(TPath.Combine(FOutRoot, 'client.sqlite'), Server, TPath.Combine(FOutRoot, 'sql.sqlite'));
  O.ScriptPath:= TPath.Combine(RepoRoot, CHARTS_MARK);
  var R:= FProducer.Produce(Cmd('lands-where', LW_TARGET), O);
  Assert.AreEqual(EXIT_SETUP, R.ExitCode, R.Reason);
  Assert.AreEqual('lands-where starts from the CLIENT index; ' + Server + ' is the SERVER of pair ''t'' in ' + O.PairsFile +
    ' -- pass the client project', R.Reason);
end;

end.
