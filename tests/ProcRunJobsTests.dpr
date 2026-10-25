program ProcRunJobsTests;
{$APPTYPE CONSOLE}
{ Wave 2 (1.31.6), lane C: the plugin's process helpers bound a run and kill the
  WHOLE tree, however the run is ended.

  WHAT THIS PINS. 1.31.5 (B-19) made RunCore enforce its deadline and kill the
  child's job on expiry. Three paths were left outside that:
    * KillProcess, used to supersede a FanOut / live-lint run from another
      thread, TerminateProcess'd the DIRECT child only. A cmd.exe wrapper or the
      engine's own dcc children kept the pipe's write end open, so the run it
      was meant to end stayed parked until the grandchild finished.
    * RunCaptureStreaming (the lint-all job) had no deadline at all.
    * TDragLintJobQueue.Destroy WaitFor'd the worker, so closing the IDE waited
      out whatever child was running.

  THE CASES, and what each one would catch being undone:
    1 positive control: KillProcess on a child that already exited answers
      True (a supersede that lost the race is not a failure).
    2 KillProcess on a LIVE tree (cmd /c ping >nul): returns True, the ping
      grandchild is gone WHEN IT RETURNS, and the run it interrupted returns
      promptly. A kill of the direct child alone fails 2c and 2d.
    3 positive control: RunCaptureStreaming delivers every line and exit 0.
    4 RunCaptureStreaming past its deadline on a silent tree: bounded, reports
      PROCRUN_TIMED_OUT_EXIT_CODE, last line names the timeout, tree gone.
    5 a cancel event set mid-run ends a streaming run within a bound, reports
      PROCRUN_CANCELLED_EXIT_CODE, tree gone; a cancel set BEFORE the call
      spawns nothing and returns at once (the shutdown race).
    6 TDragLintJobQueue.Free with a long job running returns within a bound
      and the job's grandchild is gone. 6a proves the job really was running,
      without which 6b would pass against a queue that ran nothing.

  The grandchild is found by parent PID (Toolhelp) while the run is live and is
  then held open by handle, so its PID cannot be reused under the liveness
  check. }
uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.Diagnostics,
  Winapi.Windows,
  Winapi.TlHelp32,
  DRagLint.Core.EngineHold in '..\src\core\DRagLint.Core.EngineHold.pas',
  DragLint.Plugin.ProcRun in '..\src\delphi-plugin\DragLint.Plugin.ProcRun.pas',
  DragLint.Plugin.JobQueue in '..\src\delphi-plugin\DragLint.Plugin.JobQueue.pas';

const
  CTimedOut    = -2;   { PROCRUN_TIMED_OUT_EXIT_CODE }
  CCancelled   = -3;   { PROCRUN_CANCELLED_EXIT_CODE }
  CTimeoutMs   = 2000;
  CSlackMs     = 2000;
  CFindMs      = 5000;
  CLongPings   = 20;
  CRunWaitMs   = 30000;
  CLineCount   = 500;
  CCancelAfter = 500;
  CQuickMs     = 10000;
  CBigRunMs    = 30000;
  CJobMs       = 60000;

var
  GPass, GFail: Integer;

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

function SysExe(const AName: string): string;
begin
  Result:= TPath.Combine(GetEnvironmentVariable('SystemRoot'), 'System32\' + AName);
end;

{ A command line for a cmd.exe whose ping.exe grandchild runs ~APings seconds
  and writes nothing: the parked-in-the-pipe shape. }
function SilentTreeCmd(APings: Integer): string;
begin
  Result:= Format('"%s" /c "%s" -n %d 127.0.0.1 >nul', [SysExe('cmd.exe'), SysExe('ping.exe'), APings]);
end;

{ First process named AExe whose parent is AParentPid, or 0. By name, because
  cmd.exe's console host (conhost.exe) is also its child. }
function FindChildPid(AParentPid: DWORD; const AExe: string): DWORD;
var
  Snap : THandle;
  Entry: TProcessEntry32W;
begin
  Result:= 0;
  Snap:= CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  if Snap = INVALID_HANDLE_VALUE then Exit;
  try
    Entry.dwSize:= SizeOf(Entry);
    if Process32FirstW(Snap, Entry) then
      repeat
        if (Entry.th32ParentProcessID = AParentPid) and SameText(string(Entry.szExeFile), AExe) then Exit(Entry.th32ProcessID);
      until not Process32NextW(Snap, Entry);
  finally
    CloseHandle(Snap);
  end;
end;

{ Polls until a ping.exe appears under the cmd.exe APidFn names (0 = not yet),
  and opens it for SYNCHRONIZE. 0 when none appeared within CFindMs. }
function HoldGrandchild(APidFn: TFunc<DWORD>): THandle;
var
  SW : TStopwatch;
  Cmd: DWORD;
  Gp : DWORD;
begin
  Result:= 0;
  SW:= TStopwatch.StartNew;
  while (Result = 0) and (SW.ElapsedMilliseconds < CFindMs) do
  begin
    Cmd:= APidFn();
    Gp:= if Cmd <> 0 then FindChildPid(Cmd, 'ping.exe') else 0;
    if Gp <> 0 then Result:= OpenProcess(SYNCHRONIZE, False, Gp);
    if Result = 0 then Sleep(20);
  end;
end;

function IsGone(AHandle: THandle): Boolean;
begin
  Result:= (AHandle <> 0) and (WaitForSingleObject(AHandle, 0) = WAIT_OBJECT_0);
end;

{ ---- 1, 2: KillProcess ---- }

procedure TestKillExited;
var
  Outp: string ;
  H   : THandle;
  Pid : DWORD  ;
begin
  RunCaptureStdoutCancellable(Format('"%s" /c echo done', [SysExe('cmd.exe')]), Outp, CQuickMs, 0, H, Pid);
  try
    Check('1  KillProcess on an exited child answers True', KillProcess(H));
  finally
    CloseProcessHandle(H);
  end;
end;

procedure TestKillTree;
var
  Worker : TThread;
  Done   : Boolean;
  H      : THandle;
  Pid    : DWORD  ;
  Outp   : string ;
  Grand  : THandle;
  Killed : Boolean;
  SW     : TStopwatch;
begin
  Done:= False; H:= 0; Pid:= 0;
  Worker:= TThread.CreateAnonymousThread(
    procedure
    begin
      RunCaptureStdoutCancellable(SilentTreeCmd(CLongPings), Outp, 0, 0, H, Pid);
      Done:= True;
    end);
  Worker.FreeOnTerminate:= False;
  Worker.Start;
  try
    Grand:= HoldGrandchild(function: DWORD begin Result:= Pid; end);
    Check('2a grandchild was observed', Grand <> 0, 'no ping.exe under cmd.exe pid ' + IntToStr(Pid));
    Killed:= KillProcess(H);
    Check('2b KillProcess answers True', Killed);
    Check('2c grandchild is gone when KillProcess returns', IsGone(Grand));
    SW:= TStopwatch.StartNew;
    while (not Done) and (SW.ElapsedMilliseconds < CRunWaitMs) do Sleep(20);
    Check('2d the killed run returns promptly', Done and (SW.ElapsedMilliseconds <= CSlackMs),
          Format('waited=%d ms done=%s', [SW.ElapsedMilliseconds, BoolToStr(Done, True)]));
    if Grand <> 0 then CloseHandle(Grand);
  finally
    Worker.WaitFor;
    Worker.Free;
    CloseProcessHandle(H);
  end;
end;

{ ---- 3, 4, 5: RunCaptureStreaming ---- }

procedure TestStreamLines;
var
  Lines: TStringList;
  Rc   : Integer;
  Ok   : Boolean;
begin
  Lines:= TStringList.Create;
  try
    Ok:= RunCaptureStreaming(Format('"%s" /c for /l %%i in (1,1,%d) do @echo line%%i', [SysExe('cmd.exe'), CLineCount]),
           procedure(ALine: string) begin Lines.Add(ALine); end, Rc, CBigRunMs);
    Check('3a streaming quick child ran', Ok);
    Check('3b streaming exit 0', Rc = 0, Format('rc=%d', [Rc]));
    Check('3c every line arrives, CR stripped', (Lines.Count = CLineCount) and (Lines[Lines.Count - 1] = 'line' + IntToStr(CLineCount)),
          Format('lines=%d last=%s', [Lines.Count, (if Lines.Count > 0 then Lines[Lines.Count - 1] else '')]));
  finally
    Lines.Free;
  end;
end;

{ Runs a silent tree through RunCaptureStreaming on a worker; returns once the
  run ended or CRunWaitMs passed. AGrand receives the held grandchild.
  AElapsed runs from the start, or -- when a cancel is set -- from the SetEvent:
  under load, finding the grandchild alone can take longer than
  ASetCancelAfterMs, and a bound on the cancel latency must not charge that. }
procedure RunStreamTree(ATimeoutMs: Integer; ACancel: THandle; ASetCancelAfterMs: Integer;
  out ARc: Integer; out ALast: string; out AElapsed: Int64; out AGrand: THandle; out ADone: Boolean);
var
  Worker: TThread;
  SW    : TStopwatch;
  Rc    : Integer;
  Last  : string ;
  Done  : Boolean;
  From  : Int64  ;
begin
  Rc:= 0; Last:= ''; Done:= False;
  From:= 0;
  SW:= TStopwatch.StartNew;
  Worker:= TThread.CreateAnonymousThread(
    procedure
    begin
      RunCaptureStreaming(SilentTreeCmd(CLongPings), procedure(ALine: string) begin Last:= ALine; end,
                          Rc, ATimeoutMs, ACancel);
      Done:= True;
    end);
  Worker.FreeOnTerminate:= False;
  Worker.Start;
  try
    AGrand:= HoldGrandchild(function: DWORD begin Result:= FindChildPid(GetCurrentProcessId, 'cmd.exe'); end);
    if ASetCancelAfterMs >= 0 then
    begin
      while SW.ElapsedMilliseconds < ASetCancelAfterMs do Sleep(10);
      From:= SW.ElapsedMilliseconds;
      SetEvent(ACancel);
    end;
    while (not Done) and (SW.ElapsedMilliseconds < CRunWaitMs) do Sleep(20);
    AElapsed:= SW.ElapsedMilliseconds - From;
  finally
    Worker.WaitFor;
    Worker.Free;
  end;
  ARc:= Rc; ALast:= Last; ADone:= Done;
end;

procedure TestStreamTimeout;
var
  Rc     : Integer;
  Last   : string ;
  Elapsed: Int64  ;
  Grand  : THandle;
  Done   : Boolean;
begin
  RunStreamTree(CTimeoutMs, 0, -1, Rc, Last, Elapsed, Grand, Done);
  Check('4a streaming grandchild was observed', Grand <> 0);
  Check('4b streaming run returns within timeout + 2 s', Done and (Elapsed <= CTimeoutMs + CSlackMs), Format('elapsed=%d ms', [Elapsed]));
  Check('4c streaming timeout reported distinctly', Rc = CTimedOut, Format('rc=%d', [Rc]));
  Check('4d last line names the timeout', Pos('timed out after 2 s', Last) > 0, 'last=' + Last);
  Check('4e streaming tree is gone', IsGone(Grand));
  if Grand <> 0 then CloseHandle(Grand);
end;

procedure TestStreamCancel;
var
  Ev     : THandle;
  Rc     : Integer;
  Last   : string ;
  Elapsed: Int64  ;
  Grand  : THandle;
  Done   : Boolean;
  Lines  : Integer;
  SW     : TStopwatch;
  Ok     : Boolean;
begin
  Ev:= CreateEvent(nil, True, False, nil);
  try
    RunStreamTree(0 { no deadline }, Ev, CCancelAfter, Rc, Last, Elapsed, Grand, Done);
    Check('5a cancelled run returns within the bound', Done and (Elapsed <= CSlackMs), Format('elapsed=%d ms', [Elapsed]));
    Check('5b cancel reported distinctly', Rc = CCancelled, Format('rc=%d', [Rc]));
    Check('5c cancelled tree is gone', IsGone(Grand));
    if Grand <> 0 then CloseHandle(Grand);
    { already set: the queue's shutdown can land between dequeue and spawn }
    Lines:= 0;
    SW:= TStopwatch.StartNew;
    Ok:= RunCaptureStreaming(SilentTreeCmd(CLongPings), procedure(ALine: string) begin Inc(Lines); end, Rc, 0, Ev);
    SW.Stop;
    Check('5d pre-set cancel returns at once', SW.ElapsedMilliseconds < CSlackMs div 2, Format('elapsed=%d ms', [SW.ElapsedMilliseconds]));
    Check('5e pre-set cancel spawns nothing', (not Ok) and (Rc = CCancelled) and (FindChildPid(GetCurrentProcessId, 'cmd.exe') = 0),
          Format('ok=%s rc=%d', [BoolToStr(Ok, True), Rc]));
  finally
    CloseHandle(Ev);
  end;
end;

{ ---- 6: the job queue's shutdown ---- }

procedure TestQueueShutdown;
var
  Q    : TDragLintJobQueue;
  Job  : TDragLintJob;
  Grand: THandle;
  SW   : TStopwatch;
  Secs : Integer;
begin
  if EngineIsHeld(Secs) then
  begin
    Check('6  precondition: engine not held', False, Format('an ide-release hold is live (%d s); the queue would defer', [Secs]));
    Exit;
  end;
  Q:= TDragLintJobQueue.Create;
  try
    Job:= TDragLintJob.Create;
    Job.Title    := 'shutdown-probe';
    Job.CmdLine  := SilentTreeCmd(CLongPings);
    Job.TimeoutMs:= CJobMs;
    Q.Enqueue(Job);
    Grand:= HoldGrandchild(
              function: DWORD
              begin
                Result:= FindChildPid(GetCurrentProcessId, 'cmd.exe');
              end);
    Check('6a the queued job is running (grandchild observed)', Grand <> 0);
  finally
    SW:= TStopwatch.StartNew;
    Q.Free;
    SW.Stop;
  end;
  Check('6b queue Free returns within the bound', SW.ElapsedMilliseconds <= CSlackMs + PROCRUN_KILL_WAIT_MS,
        Format('elapsed=%d ms', [SW.ElapsedMilliseconds]));
  Check('6c the running job''s tree is gone', IsGone(Grand));
  if Grand <> 0 then CloseHandle(Grand);
end;

begin
  try
    TestKillExited;
    TestKillTree;
    TestStreamLines;
    TestStreamTimeout;
    TestStreamCancel;
    TestQueueShutdown;
  except
    on E: Exception do begin Inc(GFail); Writeln('FAIL  exception: ', E.ClassName, ': ', E.Message); end;
  end;
  Writeln(Format('%d passed, %d failed', [GPass, GFail]));
  if GFail > 0 then ExitCode:= 1;
end.
