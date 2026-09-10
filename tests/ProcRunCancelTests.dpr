program ProcRunCancelTests;
{$APPTYPE CONSOLE}
{ The plugin can KILL a spawned engine run, and the kill is not best-effort.

  WHAT THIS PINS. PLAN-lint-tree's fan-out worker (P3) supersedes a running
  tier-2 run whenever a newer keystroke lands. B0(b) measured parse+extract+
  store at ~26 s/MB, which on ORM3 CLIENT is ~0.75 s at the median unit but
  ~6.2 s at p99 and ~24.0 s at the largest -- so for the top ~1% of units
  SUPERSEDING A RUNNING CHILD IS THE NORMAL PATH, not an edge case. A developer
  editing a large legacy unit hits it on nearly every pause.

  WHY A CONSOLE TEST AND NOT AN AUTOTEST. DragLint.Plugin.ProcRun uses
  Winapi.Windows and System.SysUtils and nothing else -- no OTA, no VCL -- so
  it links and runs outside the IDE. The design-time BPL cannot be rebuilt
  while RAD Studio is open, so in-IDE behaviour stays unverified either way,
  but none of the four decisions below needs an IDE to be exercised. Same
  recipe as JobQueueHoldTests.dpr and CodeLensCacheLruTests.dpr.

  THE FOUR DESIGN DECISIONS, AND THE TEST THAT WOULD CATCH EACH ONE BEING
  UNDONE -- because "the process died" is satisfied by all four being wrong:

    2 handle published BEFORE the blocking read  -> test 2 (it appears while
      the spawn call is still parked; published after the loop it would appear
      only at second ~29, and GDone would already be True)
    3 the CALLER owns the handle, spawner never closes it -> test 1c
      (GetExitCodeProcess still succeeds on it after the run returned; a
      spawner that closed it leaves the caller a use-after-close)
    4 KillProcess WAITS for the exit -> tests 3c/3d, NOT 3b. 3b was written to
      be the check and MEASURED not to be one: with the wait deleted outright
      it stays green, because a ping.exe dies faster than the observation. 3c
      kills through a SYNCHRONIZE-only handle, which cannot terminate, so the
      child stays alive and only an implementation that really waits can
      notice. See the comment on TestKillWaitIsReal.
    1 one shared RunCore -> test 6, the untouched RunCaptureStdout contract

  THE PID IS THE IDENTITY, and that is a correction rather than a detail: a
  name-based tasklist check for drag-lint.exe CANNOT FAIL, because the resident
  LSP child always exists (LspClient.pas). Every liveness assertion here reads
  the PID captured at launch.

  ping.exe, NOT cmd.exe /c ping. Killing a cmd.exe leaves the ping grandchild
  holding the inherited write end of the pipe, so the spawn call would stay
  parked for the full 30 s after a successful kill and test 4 would fail for a
  reason that has nothing to do with the code under test. }
uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.Diagnostics,
  Winapi.Windows,
  DragLint.Plugin.ProcRun in '..\src\delphi-plugin\DragLint.Plugin.ProcRun.pas';

const
  { Winapi.Windows declares this in recent RTLs; a distinct name avoids
    depending on which. }
  PROC_QUERY_LIMITED = $1000;

var
  GPass, GFail: Integer;
  { Written by the worker thread, read by the main thread. GHandle/GPid are
    the OUT parameters of the spawn call, so the publication under test writes
    straight into them. }
  GOut        : string ;
  GRc         : Integer;
  GHandle     : THandle;
  GPid        : DWORD  ;
  GDone       : Boolean;

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

{ A child that runs for about ASeconds and prints as it goes. }
function PingCmd(ASeconds: Integer): string;
begin
  Result:= Format('"%s" -n %d 127.0.0.1',
                  [TPath.Combine(GetEnvironmentVariable('SystemRoot'), 'System32\ping.exe'),
                   ASeconds]);
end;

{ Liveness of ONE process, by id. Valid only while the caller still holds a
  handle to it: once the last handle closes, the id may be reused and this
  would answer about a stranger. Every call below runs before the handle is
  closed, deliberately. }
function PidAlive(APid: DWORD): Boolean;
var
  H   : THandle;
  Code: DWORD  ;
begin
  Result:= False;
  if APid = 0 then Exit;
  H:= OpenProcess(PROC_QUERY_LIMITED, False, APid);
  if H = 0 then Exit;
  try
    if GetExitCodeProcess(H, Code) then Result:= (Code = STILL_ACTIVE);
  finally
    CloseHandle(H);
  end;
end;

{ Poll rather than sleep a fixed time: a fixed sleep either makes the suite
  slow or makes it flaky, and on a loaded box it does both. }
function WaitFor(AMaxMs: Integer; ACond: TFunc<Boolean>): Boolean;
var
  SW: TStopwatch;
begin
  SW:= TStopwatch.StartNew;
  while SW.ElapsedMilliseconds < AMaxMs do
  begin
    if ACond() then Exit(True);
    Sleep(25);
  end;
  Result:= ACond();
end;

{ Starts a cancellable run on a worker thread and returns at once. }
procedure SpawnAsync(const ACmd: string; APriority: DWORD);
begin
  GOut   := '';
  GRc    := 0;
  GHandle:= 0;
  GPid   := 0;
  GDone  := False;
  TThread.CreateAnonymousThread(
    procedure
    begin
      try
        GRc:= RunCaptureStdoutCancellable(ACmd, GOut, 0, APriority, GHandle, GPid);
      finally
        GDone:= True;
      end;
    end).Start;
end;

{ ---- the tests ------------------------------------------------------------ }

{ 1 -- POSITIVE CONTROL plus the ownership contract. Without 1a every "the
  process is gone" below is equally true of a harness that never started one. }
procedure TestSpawnAndOwnHandle;
var
  H   : THandle;
  Pid : DWORD  ;
  Rc  : Integer;
  Outp: string ;
  Code: DWORD  ;
begin
  H:= 0;
  Rc:= RunCaptureStdoutCancellable(PingCmd(2), Outp, 0, 0, H, Pid);
  Check('1a a cancellable run completes normally when nobody kills it',
        (Rc = 0) and (Pos('127.0.0.1', Outp) > 0),
        Format('rc=%d output=[%s]', [Rc, Copy(Outp, 1, 120)]));
  Check('1b it published a handle and a pid', (H <> 0) and (Pid <> 0),
        Format('handle=%d pid=%d', [H, Pid]));
  { DECISION 3. If the spawner had closed the handle this call fails -- and in
    the real worker it would be a use-after-close on the killer thread. }
  Code:= 0;
  Check('1c the handle is still the CALLER''s after the run returned',
        GetExitCodeProcess(H, Code) and (Code = 0),
        Format('GetExitCodeProcess failed (err %d) -- the spawner closed it', [GetLastError]));
  CloseProcessHandle(H);
  Check('1d CloseProcessHandle zeroes the variable', H = 0, Format('handle=%d', [H]));
end;

{ 2 -- DECISION 2. The handle must exist while the spawn call is still parked
  in ReadFile; that is the only window in which cancelling is worth anything.
  Published after the read loop, the handle would first appear at about second
  29 and GDone would already be True. }
procedure TestHandlePublishedWhileRunning;
begin
  SpawnAsync(PingCmd(30), 0);
  Check('2a the handle appears while the child is still running',
        WaitFor(5000, function: Boolean begin Result:= GHandle <> 0 end),
        'no handle within 5 s -- it is published after the blocking read, not before');
  Check('2b the spawn call had NOT returned when the handle appeared',
        not GDone,
        'the run finished first, so this proves nothing about early publication');
  Check('2c the published pid is a live process', PidAlive(GPid),
        Format('pid=%d is not running', [GPid]));
end;

{ 3 -- THE KILL. 3b reads the pid with NO polling loop, so it says something
  stronger than "gone within a second" -- but it is NOT the discriminator for
  decision 4, and saying so is the point of this comment.

  MEASURED 2026-09-10: with the wait removed from KillProcess entirely
  (Result derived from nothing), this whole procedure stays GREEN. A trivial
  ping.exe tears down faster than the OpenProcess inside PidAlive can look, so
  3b passes on a race it happens to win. Test 3c below is what actually fails
  when the wait goes. Recorded rather than quietly relied on: an assertion that
  cannot fail is worse than no assertion, because it is counted. }
procedure TestKillWaitsForExit;
var
  Killed: Boolean;
begin
  Killed:= KillProcess(GHandle);
  Check('3a KillProcess reports success', Killed, 'the child was not terminated');
  Check('3b the process is gone the instant KillProcess returns',
        not PidAlive(GPid),
        Format('pid=%d still alive -- the kill did not wait for the exit', [GPid]));
end;

{ 3c/3d -- THE DISCRIMINATOR FOR DECISION 4, built rather than hunted for.

  A handle holding SYNCHRONIZE but not PROCESS_TERMINATE can be WAITED on and
  cannot KILL. So the child stays alive, and the two implementations part
  company on the only thing that distinguishes them: a KillProcess that waits
  observes the process still running and reports FAILURE after its budget; one
  that skips the wait reports success immediately, on a process it did not
  touch. That is also the contract the fan-out worker needs -- a worker told
  "killed" about a live child would respawn and put two engine runs, and their
  dcc grandchildren, on the cores the IDE is using. }
procedure TestKillWaitIsReal;
var
  Limited: THandle  ;
  SW     : TStopwatch;
  Res    : Boolean  ;
  Elapsed: Int64    ;
begin
  SpawnAsync(PingCmd(30), 0);
  WaitFor(5000, function: Boolean begin Result:= GHandle <> 0 end);
  Limited:= OpenProcess(SYNCHRONIZE, False, GPid);
  if Limited = 0 then
  begin
    Check('3c a kill that cannot terminate reports FAILURE', False,
          Format('OpenProcess(SYNCHRONIZE) failed for pid %d, err %d', [GPid, GetLastError]));
    Check('3d and it waited its budget before saying so', False, 'not reached');
  end
  else
  begin
    SW:= TStopwatch.StartNew;
    Res:= KillProcess(Limited, 400);
    Elapsed:= SW.ElapsedMilliseconds;
    CloseHandle(Limited);
    Check('3c a kill that cannot terminate reports FAILURE', not Res,
          'it claimed success about a process it never killed');
    Check('3d and it waited its full budget before saying so', Elapsed >= 300,
          Format('returned after %d ms of a 400 ms budget -- the wait is not there', [Elapsed]));
  end;
  KillProcess(GHandle);
  WaitFor(3000, function: Boolean begin Result:= GDone end);
  CloseProcessHandle(GHandle);
end;

{ 4 -- A KILLED CHILD STILL RETURNS FROM THE SPAWN CALL, which is why the
  worker must DISCARD a superseded result rather than read its exit code. }
procedure TestKilledRunReturns;
begin
  Check('4a the spawn call returns promptly after the kill',
        WaitFor(3000, function: Boolean begin Result:= GDone end),
        'the worker thread is still parked -- a superseded run would leak a thread per keystroke');
  Check('4b the exit code carries the kill marker',
        GRc = PROCRUN_KILLED_EXIT_CODE,
        Format('rc=%d expected %d', [GRc, PROCRUN_KILLED_EXIT_CODE]));
  CloseProcessHandle(GHandle);
end;

{ 5 -- PRIORITY, with its negative control. Background fan-out runs must not
  compete with the IDE; passing 0 must leave the child at the parent's class,
  or every existing caller silently changes behaviour. }
procedure TestPriority;
var
  Cls: DWORD;
begin
  SpawnAsync(PingCmd(30), BELOW_NORMAL_PRIORITY_CLASS);
  WaitFor(5000, function: Boolean begin Result:= GHandle <> 0 end);
  Cls:= GetPriorityClass(GHandle);
  Check('5a a child spawned with BELOW_NORMAL runs at BELOW_NORMAL',
        Cls = BELOW_NORMAL_PRIORITY_CLASS,
        Format('priority class = $%x', [Cls]));
  KillProcess(GHandle);
  WaitFor(3000, function: Boolean begin Result:= GDone end);
  CloseProcessHandle(GHandle);

  SpawnAsync(PingCmd(30), 0);
  WaitFor(5000, function: Boolean begin Result:= GHandle <> 0 end);
  Cls:= GetPriorityClass(GHandle);
  Check('5b negative control: priority 0 leaves the parent''s class',
        Cls = GetPriorityClass(GetCurrentProcess),
        Format('child $%x parent $%x', [Cls, GetPriorityClass(GetCurrentProcess)]));
  KillProcess(GHandle);
  WaitFor(3000, function: Boolean begin Result:= GDone end);
  CloseProcessHandle(GHandle);
end;

{ 6 -- THE UNTOUCHED CONTRACT. RunCaptureStdout is shared by six plugin units
  and now runs through RunCore; this is the fence on decision 1. }
procedure TestLegacyEntryPointUnchanged;
var
  Outp: string ;
  Rc  : Integer;
begin
  Rc:= RunCaptureStdout(PingCmd(1), Outp, 20000);
  Check('6 RunCaptureStdout still captures output and the exit code',
        (Rc = 0) and (Pos('127.0.0.1', Outp) > 0),
        Format('rc=%d output=[%s]', [Rc, Copy(Outp, 1, 120)]));
end;

{ 7 -- THE DEGENERATE CALLS. A worker that superseded a run which had just
  finished on its own must not read that as a failure and retry. }
procedure TestKillEdgeCases;
var
  H   : THandle;
  Pid : DWORD  ;
  Outp: string ;
begin
  Check('7a KillProcess(0) is False, not a crash', not KillProcess(0));
  H:= 0;
  RunCaptureStdoutCancellable(PingCmd(1), Outp, 0, 0, H, Pid);
  Check('7b killing an already-exited child reports success', KillProcess(H),
        'a child that finished between the decision and the kill would send the worker down a retry path');
  CloseProcessHandle(H);
end;

begin
  GPass:= 0;
  GFail:= 0;
  Writeln('ProcRunCancelTests -- ping: ',
          TPath.Combine(GetEnvironmentVariable('SystemRoot'), 'System32\ping.exe'));

  try
    TestSpawnAndOwnHandle;
    TestHandlePublishedWhileRunning;
    TestKillWaitsForExit;
    TestKilledRunReturns;
    TestKillWaitIsReal;
    TestPriority;
    TestLegacyEntryPointUnchanged;
    TestKillEdgeCases;
  except
    on E: Exception do
    begin
      Inc(GFail);
      Writeln('FAIL  unhandled ', E.ClassName, ': ', E.Message);
    end;
  end;

  Writeln;
  Writeln(Format('%d passed, %d failed', [GPass, GFail]));
  if GFail > 0 then Halt(1);
end.
