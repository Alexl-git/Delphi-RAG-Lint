unit ChartsTests.Producer;

(* Cases for DRagLint.Charts.Producer and DRagLint.Charts.Producer.PowerShell (spec P2):
  the one interface Compare obtains every new report through, and its first producer,
  which runs Ask-Report.ps1 -Plain.

  The command-line and script-resolution cases are pure string work. The Stub* cases
  run the REAL TPowerShellProducer (so RunCapture, pwsh and the exit-code mapping are
  exercised end to end) against tests\charts\fixtures\producer\Stub-AskReport.ps1,
  which prints the same SHAPE as Ask-Report -Plain without touching an index. They need
  pwsh on the box.

  PS trap handled: the producer compares exit codes as integers and reads names with
  SameText, never trusting PowerShell's own coercions. *)

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TProducerTests = class
  public
    [Test] procedure CommandLineCarriesEveryArgumentAndPlain;
    [Test] procedure DbOverrideAddsDbPathAndAllowStale;
    [Test] procedure ScriptResolutionNamesEveryPlaceLooked;
    [Test] procedure StubProducesHeaderAndIndexLines;
    [Test] procedure StubStaleMapsToExit3;
    [Test] procedure StubRefusalMapsToExit1AndReason;
    [Test] procedure AllowStaleTurnsExit3IntoOk;
  end;

implementation

uses
  System.SysUtils, System.IOUtils,
  DRagLint.Charts.ReportHeader, DRagLint.Charts.Producer, DRagLint.Charts.Producer.PowerShell;

const
  REPO_ROOT_ENV = 'DRAGLINT_REPO_ROOT';
  FIXTURE_DIR = 'tests\charts\fixtures';
  FIXTURE_PROBE = 'producer\Stub-AskReport.ps1';
  PWSH_FIXTURE = 'C:\Tools\pwsh.exe'; // dl:ok hardcoded-absolute-path@86c4 -- synthetic test input: never touches the filesystem
  SCRIPT_FIXTURE = 'C:\X\Ask-Report.ps1'; // dl:ok hardcoded-absolute-path@0c4b -- synthetic test input: never touches the filesystem
  ENGINE_FIXTURE = 'C:\X\drag-lint.exe'; // dl:ok hardcoded-absolute-path@7ebd -- synthetic test input: never touches the filesystem
  COMMAND_ALL = 'who-writes -Target "OPERAT.NAME" -Project "C:\P\A.dproj" -Depth 3 -Cap 5';
  COMMAND_STUB = 'who-writes -Target "OPERAT.NAME" -Project "C:\P\A.dproj" -Depth 3';
  COMMAND_REFUSE = 'who-writes -Target "REFUSE" -Project "C:\P\A.dproj"';
  SENTENCE_START = 'Who writes this field (drag-lint report who-writes) for OPERAT.NAME';
  EXIT_REFUSED = 1;
  EXIT_STALE = 3;
  STUB_TIMEOUT_MS = 120000;
  SCRIPT_PLACES = 5;
  SNIPPET_LEN = 120;

{ The fixture folder: $DRAGLINT_REPO_ROOT, else the first ancestor of the current
  directory that holds it (the Adapters convention). '' when not found. }
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

function StubScript: string;
begin
  var Dir:= FixtureDir;
  Assert.IsTrue(Dir <> '', 'fixture folder ' + FIXTURE_DIR + ' not found from ' + GetCurrentDir);
  Result:= TPath.Combine(TPath.Combine(Dir, 'producer'), 'Stub-AskReport.ps1');
end;

function Cmd(const pText: string): TReportCommand;
begin
  Assert.IsTrue(ParseCommandLine(pText, Result), 'fixture command does not parse: ' + pText);
end;

function StubOptions: TProduceOptions;
begin
  Result:= DefaultProduceOptions;
  Result.ScriptPath:= StubScript;
  Result.EnginePath:= ENGINE_FIXTURE;
  Result.TimeoutMs:= STUB_TIMEOUT_MS;
end;

function RunStub(const pCommand: string; const pOptions: TProduceOptions): TProduceResult;
begin
  var Producer: IReportProducer;
  Producer:= TPowerShellProducer.Create;
  Result:= Producer.Produce(Cmd(pCommand), pOptions);
end;

procedure TProducerTests.CommandLineCarriesEveryArgumentAndPlain;
begin
  var Line:= BuildProducerCommandLine(PWSH_FIXTURE, SCRIPT_FIXTURE, ENGINE_FIXTURE,
    Cmd(COMMAND_ALL), DefaultProduceOptions);
  Assert.AreEqual('"' + PWSH_FIXTURE + '" -NoProfile -NonInteractive -File "' + SCRIPT_FIXTURE +
    '" -Question who-writes -Target "OPERAT.NAME" -Project "C:\P\A.dproj" -Depth 3 -Cap 5' +
    ' -Engine "' + ENGINE_FIXTURE + '" -Plain', Line);
  Assert.IsFalse(Line.Contains('-Open'), 'the producer must never ask for -Open');
  Assert.IsFalse(Line.Contains('-DbPath'), 'no override was given');
  Assert.IsFalse(Line.Contains('-AllowStale'), 'AllowStale was not set');
end;

procedure TProducerTests.DbOverrideAddsDbPathAndAllowStale;
begin
  var Opts:= DefaultProduceOptions;
  Opts.DbOverride:= 'D:\old\A.sqlite'; // dl:ok hardcoded-absolute-path@57fd -- synthetic test input: never touches the filesystem
  Opts.AllowStale:= True;
  var Line:= BuildProducerCommandLine(PWSH_FIXTURE, SCRIPT_FIXTURE, ENGINE_FIXTURE, Cmd(COMMAND_STUB), Opts);
  Assert.IsTrue(Line.EndsWith(' -Plain -DbPath "D:\old\A.sqlite" -AllowStale'), Line);
end;

procedure TProducerTests.ScriptResolutionNamesEveryPlaceLooked;
begin
  var Why: string;
  var Missing:= 'Z:\no\such\Ask-Report.ps1'; // dl:ok hardcoded-absolute-path@967b -- synthetic test input: never touches the filesystem
  var Found:= ResolveAskReportScript(Missing, Why);
  // The machine may legitimately resolve through the env var or the repo layout; the
  // contract under test is the diagnostic for a MISSING explicit path with nothing else found.
  if Found = '' then
  begin
    Assert.IsTrue(Why.Contains(Missing), 'explicit path not named: ' + Why);
    Assert.IsTrue(Why.Contains('DRAGLINT_ASK_REPORT'), 'env var not named: ' + Why);
    Assert.IsTrue(Why.Contains('Ask-Report.ps1'), 'script name not named: ' + Why);
    var Places:= 0;
    for var L in Why.Split([#10]) do
      if L.Trim <> '' then Inc(Places);
    Assert.IsTrue(Places >= SCRIPT_PLACES, 'expected ' + IntToStr(SCRIPT_PLACES) + ' places, got ' + IntToStr(Places) + ': ' + Why);
  end
  else
    Assert.IsTrue(TFile.Exists(Found), 'resolved to a file that does not exist: ' + Found);
  var Explicit:= ResolveAskReportScript(StubScript, Why);
  Assert.AreEqual(StubScript, Explicit, 'an existing explicit path wins');
end;

procedure TProducerTests.StubProducesHeaderAndIndexLines;
begin
  var R:= RunStub(COMMAND_STUB, StubOptions);
  Assert.IsTrue(R.Ok, 'stub failed: exit ' + IntToStr(R.ExitCode) + ' ' + R.Reason);
  Assert.AreEqual(0, R.ExitCode);
  Assert.AreEqual(1, Integer(Length(R.IndexPaths)), 'one INDEX line');
  Assert.IsTrue(R.BundlePath <> '', 'BUNDLE path missing');
  Assert.IsTrue(R.Text.StartsWith(SENTENCE_START), 'text does not start with the sentence: ' + Copy(R.Text, 1, SNIPPET_LEN));
end;

procedure TProducerTests.StubStaleMapsToExit3;
begin
  var Opts:= StubOptions;
  Opts.DbOverride:= 'D:\old\stale.sqlite'; // dl:ok hardcoded-absolute-path@1f38 -- synthetic test input: never touches the filesystem
  var R:= RunStub(COMMAND_STUB, Opts);
  Assert.IsFalse(R.Ok);
  Assert.AreEqual(EXIT_STALE, R.ExitCode);
  Assert.IsTrue(R.Reason.Contains('stale'), 'reason: ' + R.Reason);
end;

procedure TProducerTests.StubRefusalMapsToExit1AndReason;
begin
  var R:= RunStub(COMMAND_REFUSE, StubOptions);
  Assert.IsFalse(R.Ok);
  Assert.AreEqual(EXIT_REFUSED, R.ExitCode);
  Assert.IsTrue(R.Reason.Contains('no such symbol'), 'reason: ' + R.Reason);
end;

procedure TProducerTests.AllowStaleTurnsExit3IntoOk;
begin
  var Opts:= StubOptions;
  Opts.DbOverride:= 'D:\old\stale.sqlite'; // dl:ok hardcoded-absolute-path@1f38 -- synthetic test input: never touches the filesystem
  Opts.AllowStale:= True;
  var R:= RunStub(COMMAND_STUB, Opts);
  Assert.IsTrue(R.Ok, 'exit ' + IntToStr(R.ExitCode) + ' ' + R.Reason);
  Assert.AreEqual(1, Integer(Length(R.IndexPaths)));
  Assert.IsTrue(R.IndexPaths[0].Contains('stale.sqlite'), 'INDEX should echo the override: ' + R.IndexPaths[0]);
end;

initialization
  TDUnitX.RegisterTestFixture(TProducerTests);

end.
