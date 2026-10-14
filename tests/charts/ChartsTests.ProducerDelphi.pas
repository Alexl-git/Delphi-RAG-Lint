unit ChartsTests.ProducerDelphi;

{ Cases for DRagLint.Charts.Producer.Delphi: which producer compare gets (the Delphi one, on live
  indexes), that the clone guard still holds where live is not allowed, what is answered
  in-process and what is delegated, and the exit codes of Ask-Report's contract. The
  in-process cases run against the FROZEN clones (a missing clone passes with a note). }

interface

uses
  DUnitX.TestFramework, DRagLint.Charts.ReportHeader, DRagLint.Charts.Producer;

type
  /// <summary>A fallback that records whether it was asked.</summary>
  TRecordingProducer = class(TInterfacedObject, IReportProducer)
  private
    FCalls: Integer;
    FLastQuestion: string;
    FLastDb: string;
  public
    property Calls: Integer read FCalls;
    property LastQuestion: string read FLastQuestion;
    property LastDb: string read FLastDb;
    function Produce(const pCommand: TReportCommand; const pOptions: TProduceOptions): TProduceResult;
    function Describe: string;
  end;

  [TestFixture]
  TProducerDelphiTests = class
  private
    FFallback: TRecordingProducer;
    FKeep    : IReportProducer;
    FProducer: IReportProducer;
    FOutRoot : string;
    function Clone(const pName: string; out pPath: string): Boolean;
    function BareScriptFolder: string;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure CompareGetsTheDelphiProducerOnLiveIndexes;
    [Test] procedure CloneGuardStaysOnWhenLiveIsNotAllowed;
    [Test] procedure UnportedQuestionFallsBack;
    [Test] procedure ProjectWithoutIndexFallsBack;
    [Test] procedure PortedQuestionIsAnsweredInProcess;
    [Test] procedure StaleIndexRefusesWithoutAllowStale;
    [Test] procedure MissingIndexIsSetup;
    [Test] procedure RefusalIsExitOne;
    [Test] procedure UnknownTargetIsExitOne;
    [Test] procedure CloneGuardRefusalIsSetup;
    [Test] procedure UnexpectedFailureFallsBack;
    [Test] procedure CrossesBoundaryWithoutCounterpartFallsBack;
    [Test] procedure CrossesBoundaryWithCounterpartIsInProcess;
    [Test] procedure OtherIndexesAQuestionDoesNotReadAreIgnored;
    [Test] procedure MissingSqlIndexOfAReadingQuestionIsSetup;
    [Test] procedure SqlIndexOfAReadingQuestionIsCarriedAndChecked;
    [Test] procedure MissingServerIndexOfAReadingQuestionIsSetup;
    [Test] procedure ServerAndSqlIndexesAreCarriedInAskReportOrder;
    [Test] procedure PortedFallbackWithoutEmitterScriptIsSetup;
    [Test] procedure PortedFallbackWithEmitterScriptFallsBack;
    [Test] procedure UnexpectedFailureWithoutEmitterScriptIsSetup;
    [Test] procedure EveryPortedIdHasAnEmitterScriptInTheRepo;
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
  STUB_EXIT = 42;
  NOT_INSTALLED = 'crosses-boundary is answered by the engine in this install, and its PowerShell fallback is not installed: ';

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

function TRecordingProducer.Produce(const pCommand: TReportCommand; const pOptions: TProduceOptions): TProduceResult;
begin
  Inc(FCalls);
  FLastQuestion:= pCommand.Question;
  FLastDb:= pOptions.DbOverride;
  Result:= Default(TProduceResult);
  Result.ExitCode:= STUB_EXIT;
end;

function TRecordingProducer.Describe: string;
begin
  Result:= 'recording stub';
end;

procedure TProducerDelphiTests.Setup;
begin
  FFallback:= TRecordingProducer.Create;
  FKeep:= FFallback;
  FOutRoot:= TPath.Combine(TPath.GetTempPath, 'drag-lint-charts-p-' + TGUID.NewGuid.ToString);
  FProducer:= TDelphiProducer.Create(FKeep, True, FOutRoot);
end;

procedure TProducerDelphiTests.TearDown;
begin
  FProducer:= nil;
  FKeep:= nil;
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
  FProducer:= TDelphiProducer.Create(FKeep, False, FOutRoot);
  var O:= DefaultProduceOptions;
  O.DbOverride:= Live;
  O.ScriptPath:= TPath.Combine(RepoRoot, CHARTS_MARK);
  var R:= FProducer.Produce(Cmd('deps', 'X'), O);
  Assert.AreEqual(EXIT_SETUP, R.ExitCode, R.Reason);
  Assert.StartsWith('refusing a non-clone database: ', R.Reason);
  Assert.AreEqual(0, FFallback.Calls);
end;

procedure TProducerDelphiTests.UnportedQuestionFallsBack;
begin
  var O:= DefaultProduceOptions;
  O.DbOverride:= 'any.sqlite';
  var R:= FProducer.Produce(Cmd('butterfly', 'A.B'), O);
  Assert.AreEqual(1, FFallback.Calls);
  Assert.AreEqual('butterfly', FFallback.LastQuestion);
  Assert.AreEqual('any.sqlite', FFallback.LastDb);
  Assert.AreEqual(STUB_EXIT, R.ExitCode);
  Assert.Contains(FProducer.Describe, 'fell back to: recording stub');
end;

procedure TProducerDelphiTests.ProjectWithoutIndexFallsBack;
begin
  var R:= FProducer.Produce(Cmd('touches-tables', TT_TARGET, 'X.dproj'), DefaultProduceOptions);
  Assert.AreEqual(1, FFallback.Calls);
  Assert.AreEqual(STUB_EXIT, R.ExitCode);
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
  Assert.AreEqual(0, FFallback.Calls);
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
  Assert.AreEqual(0, FFallback.Calls);
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
  Assert.AreEqual(0, FFallback.Calls, 'a refusal PowerShell would also give is not handed to the fallback');
end;

procedure TProducerDelphiTests.CloneGuardRefusalIsSetup;
var
  Db: string;
begin
  { a history copy in the clone root: a valid index, but the clone guard refuses its name }
  if not Clone(CLIENT_HISTORY, Db) then
    Exit;
  FProducer:= TDelphiProducer.Create(FKeep, False, FOutRoot);  { clone guard ON for this case }
  var O:= DefaultProduceOptions;
  O.DbOverride:= Db;
  O.ScriptPath:= TPath.Combine(RepoRoot, CHARTS_MARK);
  O.AllowStale:= True;
  var R:= FProducer.Produce(Cmd('touches-tables', TT_TARGET), O);
  Assert.AreEqual(EXIT_SETUP, R.ExitCode, R.Reason);
  Assert.StartsWith('refusing a database whose name does not end in .sqlite', R.Reason);
  Assert.AreEqual(0, FFallback.Calls);
end;

procedure TProducerDelphiTests.UnexpectedFailureFallsBack;
begin
  { not an index at all: the freshness probe fails inside the try, which is a failure of the
    in-process path, not a verdict -- so the fallback answers and nothing escapes }
  TDirectory.CreateDirectory(FOutRoot);
  var Bad:= TPath.Combine(FOutRoot, 'corrupt.sqlite');
  TFile.WriteAllText(Bad, 'this is not an SQLite database');
  var O:= DefaultProduceOptions;
  O.DbOverride:= Bad;
  O.ScriptPath:= TPath.Combine(RepoRoot, CHARTS_MARK);
  var R:= FProducer.Produce(Cmd('deps', 'X'), O);
  Assert.AreEqual(1, FFallback.Calls, 'the fallback answers an unexpected failure');
  Assert.AreEqual(STUB_EXIT, R.ExitCode);
  Assert.Contains(FProducer.Describe, 'Delphi in-process failed (');
  Assert.Contains(FProducer.Describe, 'fell back to: recording stub');
end;

procedure TProducerDelphiTests.CrossesBoundaryWithoutCounterpartFallsBack;
begin
  { Ask-Report would pair the far side from report-pairs.json, which only the fallback reads }
  var O:= DefaultProduceOptions;
  O.DbOverride:= 'any.sqlite';
  var R:= FProducer.Produce(Cmd('crosses-boundary', CB_TARGET), O);
  Assert.AreEqual(1, FFallback.Calls);
  Assert.AreEqual(STUB_EXIT, R.ExitCode);
  Assert.Contains(FProducer.Describe, 'fell back to: recording stub');
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
  Assert.AreEqual(0, FFallback.Calls);
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
  Assert.AreEqual(0, FFallback.Calls);
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
  var R:= FProducer.Produce(Cmd('feeds-from', FF_TARGET), O);
  Assert.AreEqual(0, FFallback.Calls);
  Assert.IsTrue(R.Ok, R.Reason);
  Assert.AreEqual<Integer>(2, Length(R.IndexPaths));
  Assert.AreEqual(Sql, R.IndexPaths[1]);
  Assert.Contains(R.Text, #13#10'INDEX ' + Sql + ' (sql)'#13#10'CHART feeds-from ' + FF_TARGET + ' -- ');
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
  Assert.AreEqual(0, FFallback.Calls);
end;

procedure TProducerDelphiTests.ServerAndSqlIndexesAreCarriedInAskReportOrder;
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
  Assert.AreEqual(0, FFallback.Calls);
  Assert.IsTrue(R.Ok, R.Reason);
  Assert.AreEqual<Integer>(3, Length(R.IndexPaths));
  Assert.AreEqual(Server, R.IndexPaths[1]);
  Assert.AreEqual(Sql, R.IndexPaths[2]);
  Assert.Contains(R.Text, #13#10'INDEX ' + Server + ' (server)'#13#10'INDEX ' + Sql + ' (sql)'#13#10'CHART lands-where ' + LW_TARGET + ' -- ');
  Assert.AreEqual('Delphi in-process (lands-where)', FProducer.Describe);
end;
{ a folder holding only an empty Ask-Report.ps1: an installed copy, where the ported Emit-*.ps1 are not shipped }
function TProducerDelphiTests.BareScriptFolder: string;
begin
  var Dir:= TPath.Combine(FOutRoot, 'bin');
  TDirectory.CreateDirectory(Dir);
  Result:= TPath.Combine(Dir, 'Ask-Report.ps1');
  TFile.WriteAllText(Result, '');
end;

procedure TProducerDelphiTests.PortedFallbackWithoutEmitterScriptIsSetup;
begin
  var O:= DefaultProduceOptions;
  O.DbOverride:= 'any.sqlite';
  O.ScriptPath:= BareScriptFolder;
  var R:= FProducer.Produce(Cmd('crosses-boundary', CB_TARGET), O);
  Assert.AreEqual(EXIT_SETUP, R.ExitCode, R.Reason);
  Assert.AreEqual(NOT_INSTALLED + 'no counterpart index given (--counterpart-db / -CounterpartDb, or report-pairs.json)', R.Reason);
  Assert.AreEqual(0, FFallback.Calls, 'a fallback that cannot run is not called');
end;

procedure TProducerDelphiTests.PortedFallbackWithEmitterScriptFallsBack;
begin
  var O:= DefaultProduceOptions;
  O.DbOverride:= 'any.sqlite';
  O.ScriptPath:= TPath.Combine(RepoRoot, CHARTS_MARK);
  var R:= FProducer.Produce(Cmd('crosses-boundary', CB_TARGET), O);
  Assert.AreEqual(1, FFallback.Calls, 'the repo has Emit-CrossesBoundary.ps1, so the fallback answers');
  Assert.AreEqual(STUB_EXIT, R.ExitCode);
end;

procedure TProducerDelphiTests.UnexpectedFailureWithoutEmitterScriptIsSetup;
begin
  var Script:= BareScriptFolder;
  var Bad:= TPath.Combine(FOutRoot, 'corrupt.sqlite');
  TFile.WriteAllText(Bad, 'this is not an SQLite database');
  var O:= DefaultProduceOptions;
  O.DbOverride:= Bad;
  O.ScriptPath:= Script;
  var R:= FProducer.Produce(Cmd('deps', 'X'), O);
  Assert.AreEqual(EXIT_SETUP, R.ExitCode, R.Reason);
  Assert.StartsWith('deps is answered by the engine in this install, and its PowerShell fallback is not installed: ' +
    'the in-process answer failed (', R.Reason);
  Assert.AreEqual(0, FFallback.Calls, 'a fallback that cannot run is not called');
end;

procedure TProducerDelphiTests.EveryPortedIdHasAnEmitterScriptInTheRepo;
begin
  var Src:= ExtractFileDir(TPath.Combine(RepoRoot, CHARTS_MARK));
  Assert.IsTrue(Length(PortedQuestionIds) > 0, 'questions are registered');
  for var Id in PortedQuestionIds do
    Assert.IsTrue(TFile.Exists(TPath.Combine(Src, EmitterScriptName(Id))), Id + ' -> ' + EmitterScriptName(Id) + ' is not in charts\src');
end;

end.