program JobQueueHoldTests;
{$APPTYPE CONSOLE}
{ The plugin job queue DEFERS heavy jobs while `ide-release` holds the engine.

  WHAT THIS PINS. Every heavy job in TDragLintJobQueue runs the DEPLOYED
  drag-lint.exe, and a build stages a fresh one over it. `ide-release` writes a
  hold sentinel meaning "do not start anything", and this queue was the one
  component that ignored it: WorkerLoop extracted and RunOne spawned with no
  condition of any kind. A job that began inside a build window either died
  mid-run or held the file the build was replacing -- and worse, a queued bare
  `index` job makes build\stage-engine.ps1 REFUSE to stage rather than kill, so
  a user-requested reindex starting at the wrong moment turned the build's
  recovery path into a refusal.

  WHY A CONSOLE TEST AND NOT AN AUTOTEST. JobQueue.pas's implementation uses
  only DragLint.Plugin.ProcRun, and the gate's one new dependency,
  DRagLint.Core.EngineHold, reads a sentinel file and touches no process. So
  the whole thing links outside the IDE. The design-time BPL cannot be rebuilt
  while RAD Studio is open, so IDE behaviour stays unverified either way --
  but the gate does not need an IDE to be exercised, and waiting for one would
  mean not testing it. Same shape as CodeLensCacheLruTests.dpr.

  THE CONTROLS ARE THE POINT. "the file did not appear" is satisfied by a queue
  that runs nothing at all, by a broken marker command, and by a harness that
  measured the wrong directory. So test 1 is a positive control that proves
  jobs run here, and test 3 proves the deferred job is DEFERRED and not DROPPED
  -- without which test 2 would pass against a queue that silently discarded
  everything.

  4b AND 5 ARE REGRESSION FENCES rather than new behaviour: measured green both
  before and after the gate. They pin the PEEK design -- a gate that extracted
  the job and re-queued it would run the first of a coalesced group and then
  the last (4b), or emit deferred jobs out of order (5), and neither break
  would show up in a spot check.

  4a, by contrast, was PREDICTED to be a fence and measured RED before the
  gate: ungated, the first job starts at once, so the queue is not holding
  three coalescible jobs at the moment its depth is read. Recorded rather
  than quietly reclassified -- the runner header carries the measurement.

  THE SENTINEL IS ONE FILE PER USER, so this program must never leave the
  machine held: every hold is released in a finally, and the run ends with an
  unconditional release. }
uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.Diagnostics,
  DRagLint.Core.EngineHold in '..\src\core\DRagLint.Core.EngineHold.pas',
  DragLint.Plugin.ProcRun in '..\src\delphi-plugin\DragLint.Plugin.ProcRun.pas',
  DragLint.Plugin.JobQueue in '..\src\delphi-plugin\DragLint.Plugin.JobQueue.pas';

var
  GPass, GFail: Integer;
  GWork       : string ;
  GRan        : string ;   { the marker file every job appends to }
  GHookCalls  : Integer;
  GHookText   : string ;

procedure Check(const AName: string; ACond: Boolean; const ADetail: string = '');
begin
  if ACond then begin Inc(GPass); Writeln('PASS  ', AName); end
  else
  begin
    Inc(GFail);
    Writeln('FAIL  ', AName);
    if ADetail <> '' then Writeln('      ', ADetail);
  end;
end;

{ ---- helpers -------------------------------------------------------------- }

procedure ResetMarker;
begin
  if TFile.Exists(GRan) then TFile.Delete(GRan);
end;

{ Lines the marker file holds, in order. Absent file = no lines, which is the
  normal "nothing ran" state and must not raise. }
function MarkerLines: TArray<string>;
var
  L: TStringList;
begin
  SetLength(Result, 0);
  if not TFile.Exists(GRan) then Exit;
  L:= TStringList.Create;
  try
    { A job may be mid-write; a share-denied read here would look like a test
      failure rather than a timing artefact. }
    try L.LoadFromFile(GRan); except Exit; end;
    Result:= L.ToStringArray;
  finally
    L.Free;
  end;
end;

function MarkerCount: Integer;
begin
  Result:= Length(MarkerLines);
end;

{ A job whose only effect is to append ATag to the marker file. cmd.exe, not the
  engine: this test is about WHETHER a job starts, never about what it does. }
function MakeMarkerJob(const ATag, AKey: string): TDragLintJob;
begin
  Result:= TDragLintJob.Create;
  Result.Title      := 'marker ' + ATag;
  Result.CoalesceKey:= AKey;
  Result.CmdLine    := Format('cmd.exe /c echo %s>> "%s"', [ATag, GRan]);
  Result.TimeoutMs  := 20000;
end;

{ Poll for a condition instead of sleeping a fixed time: a fixed sleep either
  makes the suite slow or makes it flaky, and on a loaded box it does both. }
function WaitFor(AMaxMs: Integer; ACond: TFunc<Boolean>): Boolean;
var
  SW: TStopwatch;
begin
  SW:= TStopwatch.StartNew;
  while SW.ElapsedMilliseconds < AMaxMs do
  begin
    if ACond() then Exit(True);
    Sleep(50);
  end;
  Result:= ACond();
end;

procedure Hold(ASeconds: Integer);
var
  Err: string;
begin
  if not HoldEngine(ASeconds, Err) then
  begin
    Writeln('FATAL: could not write the engine hold: ', Err);
    Halt(2);
  end;
end;

procedure Release;
var
  Err: string;
begin
  ReleaseEngineHold(Err);
end;

{ ---- the tests ------------------------------------------------------------ }

{ 1 -- POSITIVE CONTROL. Without this, every "the file did not appear" below is
  equally true of a harness that cannot run a job at all. }
procedure TestRunsWithoutHold;
begin
  Release;
  ResetMarker;
  JobQueue.Enqueue(MakeMarkerJob('one', ''));
  Check('1 positive control: a job runs when nothing is held',
        WaitFor(8000, function: Boolean begin Result:= MarkerCount >= 1 end),
        'the queue never ran a job, so nothing below measures the gate');
end;

{ 2 -- THE FIX. RED before the gate: the file appears in about 0.1 s. }
procedure TestDeferredWhileHeld;
var
  St: TQueueState;
begin
  ResetMarker;
  Hold(6);
  try
    JobQueue.Enqueue(MakeMarkerJob('held', ''));
    Sleep(2000);
    Check('2a the job did NOT run while the engine was held', MarkerCount = 0,
          Format('marker has %d line(s) -- the queue started a job inside a build window', [MarkerCount]));
    St:= JobQueue.GetState;
    { STILL QUEUED, not running and not dropped. Depth is the half that
      distinguishes "deferred" from "silently discarded". }
    Check('2b the job is still pending, and nothing is running',
          (St.QueueDepth = 1) and (not St.Running),
          Format('QueueDepth=%d Running=%s', [St.QueueDepth, BoolToStr(St.Running, True)]));
  finally
    Release;
  end;
end;

{ 3 -- DEFERRED, NOT DROPPED. Continues from 2's queued job: releasing the hold
  must let it run, exactly once. }
procedure TestRunsAfterRelease;
begin
  Release;
  Check('3 the deferred job runs once the hold is released',
        WaitFor(9000, function: Boolean begin Result:= MarkerCount >= 1 end),
        'the job was dropped rather than deferred -- worse than not gating at all');
  Sleep(500);
  Check('3b it ran exactly once', MarkerCount = 1,
        Format('marker has %d line(s)', [MarkerCount]));
end;

{ 4 -- COALESCING SURVIVES THE WAIT. Green before the gate; it fences the PEEK
  design. Extract-and-re-queue would run the first job and then the last. }
procedure TestCoalesceUnderHold;
begin
  ResetMarker;
  Hold(4);
  try
    JobQueue.Enqueue(MakeMarkerJob('c1', 'samekey'));
    JobQueue.Enqueue(MakeMarkerJob('c2', 'samekey'));
    JobQueue.Enqueue(MakeMarkerJob('c3', 'samekey'));
    Sleep(300);
    Check('4a three jobs with one key collapse to one while held',
          JobQueue.GetState.QueueDepth = 1,
          Format('QueueDepth=%d', [JobQueue.GetState.QueueDepth]));
  finally
    Release;
  end;
  WaitFor(9000, function: Boolean begin Result:= MarkerCount >= 1 end);
  Sleep(500);
  Check('4b exactly one of them ran, and it is the LAST enqueued',
        (MarkerCount = 1) and (Length(MarkerLines) = 1) and (Trim(MarkerLines[0]) = 'c3'),
        Format('marker: [%s]', [string.Join('|', MarkerLines)]));
end;

{ 5 -- FIFO SURVIVES THE WAIT. Green before the gate; fences a re-queue-at-tail
  design, which would emit B then A. }
procedure TestFifoUnderHold;
var
  Lines: TArray<string>;
begin
  ResetMarker;
  Hold(4);
  try
    JobQueue.Enqueue(MakeMarkerJob('aaa', 'k-a'));
    JobQueue.Enqueue(MakeMarkerJob('bbb', 'k-b'));
  finally
    Release;
  end;
  WaitFor(12000, function: Boolean begin Result:= MarkerCount >= 2 end);
  Sleep(500);
  Lines:= MarkerLines;
  Check('5 deferred jobs keep their order',
        (Length(Lines) = 2) and (Trim(Lines[0]) = 'aaa') and (Trim(Lines[1]) = 'bbb'),
        Format('marker: [%s]', [string.Join('|', Lines)]));
end;

{ 6 -- PROMPT SHUTDOWN. RED before the gate for a different reason: the job runs
  during the destructor's WaitFor because the worker is already inside RunOne.
  After the gate it must ALSO not hang for a whole recheck interval. }
procedure TestPromptShutdown;
var
  SW   : TStopwatch;
  Elaps: Int64     ;
begin
  ResetMarker;
  Hold(30);
  try
    JobQueue.Enqueue(MakeMarkerJob('shutdown', ''));
    Sleep(400);
    SW:= TStopwatch.StartNew;
    ShutdownJobQueue;
    Elaps:= SW.ElapsedMilliseconds;
    Check('6a shutdown returns promptly even with a job deferred',
          Elaps < 2000,
          Format('took %d ms -- a live hold must not pin IDE unload', [Elaps]));
    Sleep(600);
    Check('6b the deferred job never ran', MarkerCount = 0,
          Format('marker has %d line(s)', [MarkerCount]));
  finally
    Release;
  end;
end;

{ 7 -- THE HOOK FIRES ONCE PER EPISODE. A per-wait log would write 24 identical
  lines for one 120 s hold. RED before the gate: the hook does not exist, and a
  compile error counts as RED. }
procedure TestHookOnce;
begin
  ResetMarker;
  GHookCalls:= 0;
  GHookText := '';
  GJobQueueDeferredHook:=
    procedure (AText: string)
    begin
      Inc(GHookCalls);
      if GHookText = '' then GHookText:= AText;
    end;
  try
    Hold(8);
    try
      JobQueue.Enqueue(MakeMarkerJob('hook', 'hookkey'));
      { Longer than one recheck interval (5 s), so a per-wait log would show up
        as two or more calls rather than one. }
      Sleep(7000);
      Check('7a the deferral was reported exactly once', GHookCalls = 1,
            Format('hook called %d time(s)', [GHookCalls]));
      Check('7b the message names the job and its key',
            (Pos('marker hook', GHookText) > 0) and (Pos('hookkey', GHookText) > 0),
            'got: ' + GHookText);
    finally
      Release;
    end;
    WaitFor(9000, function: Boolean begin Result:= MarkerCount >= 1 end);
  finally
    GJobQueueDeferredHook:= nil;
  end;
end;

begin
  GPass:= 0;
  GFail:= 0;
  GWork:= TPath.Combine(TPath.GetTempPath, 'drag-lint-jobqueue-hold');
  GRan := TPath.Combine(GWork, 'ran.txt');
  TDirectory.CreateDirectory(GWork);
  Writeln('JobQueueHoldTests -- work dir: ', GWork);

  try
    try
      TestRunsWithoutHold;
      TestDeferredWhileHeld;
      TestRunsAfterRelease;
      TestCoalesceUnderHold;
      TestFifoUnderHold;
      TestHookOnce;
      { LAST: it destroys the singleton, so nothing may enqueue after it. }
      TestPromptShutdown;
    except
      on E: Exception do
      begin
        Inc(GFail);
        Writeln('FAIL  unhandled ', E.ClassName, ': ', E.Message);
      end;
    end;
  finally
    { THE SENTINEL IS ONE FILE PER USER. A failed assertion must never leave
      this machine held -- every other drag-lint on the box would defer. }
    Release;
  end;

  Writeln;
  Writeln(Format('%d passed, %d failed', [GPass, GFail]));
  if GFail > 0 then Halt(1);
end.
