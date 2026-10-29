unit DragLint.Plugin.ProcRun;

{ Shared stdout/stderr capture for spawning drag-lint.exe with no console
  window. Extracted from UsagesForm/SymbolSearchForm (identical copies).

  THE CANCELLABLE VARIANT AND WHY IT IS NOT A COPY. The fan-out worker
  (PLAN-lint-tree P3) has to abandon a run that a newer keystroke superseded.
  B0(b) measured parse+extract+store at ~26 s/MB, so on ORM3 CLIENT a tier-2
  run costs ~0.75 s at the median unit but ~6.2 s at p99 and ~24 s at the
  largest -- which puts supersession INSIDE the normal path for the top ~1% of
  units rather than at the edge of it. So the kill has to be correct, not
  best-effort.

  Everything below CreateProcessW is identical between the two entry points,
  and a second copy is exactly how the two would drift on pipe handling -- the
  first copy of this code already drifted twice before it was extracted here.
  Hence ONE RunCore with the creation flags and handle ownership as parameters.

  HANDLE OWNERSHIP IS THE WHOLE DESIGN. RunCore publishes the process handle
  through AHandleOut IMMEDIATELY after CreateProcessW, BEFORE the blocking read
  loop: an out parameter writes into the CALLER's variable, so another thread
  can kill while this call is still parked in ReadFile. Published after the
  loop, the handle would only exist once the child had already finished, which
  is the moment cancellation stops being worth anything.

  For the same reason RunCore must NOT close a published handle: the thread
  that is about to call TerminateProcess on it existing IS the feature, and
  closing it underneath that thread is a use-after-close. The caller closes it
  with CloseProcessHandle once the run has returned. }

interface

uses
  System.SysUtils, Winapi.Windows;

const
  /// <summary>Exit code TerminateProcess stamps on a child killed by
  /// KillProcess (ERROR_CANCELLED). It exists to make a kill legible in a log;
  /// a superseded run must DISCARD its output rather than interpret its exit
  /// code, because a child that loses its console pipe returns normally.</summary>
  PROCRUN_KILLED_EXIT_CODE = 1223;

  /// <summary>Default budget KillProcess allows a child to actually exit.
  /// Generous on purpose: the alternative to waiting a little is respawning
  /// into a box that is still running the previous engine and its dcc
  /// grandchildren.</summary>
  PROCRUN_KILL_WAIT_MS = 5000;

  /// <summary>What RunCaptureStdout and RunCaptureStdoutCancellable return
  /// when ATimeoutMs elapsed while the child was still running (B-19). By then
  /// the child's whole process tree has been killed and AOutput ends with a
  /// 'timed out after N s' line. Negative like a spawn failure, so a caller
  /// testing &lt; 0 already treats it as "no result"; compare with this
  /// constant to tell the two apart.</summary>
  PROCRUN_TIMED_OUT_EXIT_CODE = -2;

  /// <summary>What the runners return when the caller's cancel event (ACancel)
  /// was signalled (1.31.6). The child's whole process tree has been killed, or
  /// -- when the event was already set at the call -- nothing was spawned.
  /// Negative, so a caller testing &lt; 0 treats it as "no result".</summary>
  PROCRUN_CANCELLED_EXIT_CODE = -3;

type
  /// <summary>Line callback for RunCaptureStreaming. TProc&lt;string&gt; allows
  /// anonymous closures so callers can capture local variables inline.</summary>
  TOnLineProc = TProc<string>;

/// <summary>Spawns ACmdLine (CREATE_NO_WINDOW) and captures stdout+stderr into
/// AOutput.</summary>
/// <param name="ACmdLine">Full command line, as CreateProcessW takes it.</param>
/// <param name="AOutput">Receives everything the child wrote to stdout and
/// stderr, interleaved.</param>
/// <param name="ATimeoutMs">Deadline for the WHOLE run, in milliseconds,
/// enforced while the output is being read: on expiry the child's process tree
/// is killed. &lt;=0 = no deadline.</param>
/// <param name="ACancel">Optional manual-reset event handle (0 = none). Once it
/// is signalled the child's process tree is killed and the call returns; if it
/// is signalled before the call, nothing is spawned. The caller owns it.</param>
/// <param name="AStandDownGraceMs">0 (the default): a cancel kills at once, as
/// above. &gt; 0 (lane X-BT, a `cycles --fix` run): a cancel first ASKS the
/// child to stand down -- the `shutdown` request of the maintenance control
/// channel (DRagLint.Core.ControlChannel) on the pipe named after the child's
/// pid -- and keeps reading its output for up to this many ms; a child that
/// rolls back and exits in that time returns its own exit code and output.
/// Only when the grace ends is the tree killed.</param>
/// <returns>The child exit code; PROCRUN_TIMED_OUT_EXIT_CODE when the deadline
/// expired; PROCRUN_CANCELLED_EXIT_CODE when ACancel was signalled and the tree
/// was killed (with a grace: the child did not exit within it); -1 if it could
/// not start.</returns>
/// <remarks>Once a stand-down has started, the grace replaces ATimeoutMs as the
/// deadline: the engine is rolling back, and a timeout must not cut that short.</remarks>
function RunCaptureStdout(const ACmdLine: string; out AOutput: string; ATimeoutMs: Integer;
  ACancel: THandle = 0; AStandDownGraceMs: Integer = 0): Integer;

/// <summary>As RunCaptureStdout, but publishes the child's process handle and
/// PID so another thread can cancel the run, and applies APriority to the
/// child.</summary>
/// <param name="ACmdLine">Full command line, as CreateProcessW takes it.</param>
/// <param name="AOutput">Receives stdout and stderr, interleaved. MEANINGLESS
/// on a run that was superseded -- discard it rather than parse it.</param>
/// <param name="ATimeoutMs">Deadline for the whole run, as for RunCaptureStdout;
/// &lt;=0 = no deadline.</param>
/// <param name="APriority">Priority class for the child: 0 to inherit the
/// parent's, BELOW_NORMAL_PRIORITY_CLASS for background work.</param>
/// <param name="AHandle">Receives the process handle as soon as the child
/// exists -- before this function blocks -- so a worker thread can call
/// KillProcess on it mid-run. THE CALLER OWNS IT: this function never closes
/// it, and the caller must, via CloseProcessHandle. Zero if the spawn failed.</param>
/// <param name="APid">Receives the child's process id, for supersession
/// telemetry. A PID is the only identity that can distinguish THIS child from
/// the resident LSP drag-lint.exe, which a name-based check cannot.</param>
/// <returns>The child exit code; PROCRUN_TIMED_OUT_EXIT_CODE when the deadline
/// expired; -1 if it could not start. A KILLED child still returns here (the pipe closes), so a caller that
/// superseded the run must discard the result rather than read this.</returns>
/// <remarks>Safe to call KillProcess(AHandle) from another thread while this
/// call is in progress; that is what it is for.</remarks>
function RunCaptureStdoutCancellable(const ACmdLine: string; out AOutput: string;
  ATimeoutMs: Integer; APriority: DWORD; out AHandle: THandle; out APid: DWORD): Integer;

/// <summary>Terminates the process AHandle refers to TOGETHER WITH EVERYTHING
/// IT SPAWNED, and WAITS up to AWaitMs for the whole tree to actually go
/// away.</summary>
/// <param name="AHandle">A handle published by RunCaptureStdoutCancellable.
/// Zero is accepted and answers False.</param>
/// <param name="AWaitMs">Milliseconds to wait for the exit; negative = wait
/// forever.</param>
/// <returns>True once the tree is gone, including when it had already exited
/// on its own. False if any of it is still running when the budget expires --
/// which is what a caller holding a handle without PROCESS_TERMINATE gets, and
/// it must not treat that as a kill.</returns>
/// <remarks>THE TREE (1.31.6): while the run that published AHandle is still in
/// progress, the child's job object is registered against the handle, and the
/// kill terminates the JOB -- a cmd.exe wrapper's grandchild, or the engine's
/// dcc / graph children, would otherwise keep the pipe open and the run parked.
/// A handle with no registered job (the run already returned, or the job could
/// not be created) falls back to the direct child.
/// The wait is not politeness. Termination is ASYNCHRONOUS, so a caller that
/// returns immediately and respawns can leave two engine runs -- and their dcc
/// grandchildren -- competing for the cores the IDE needs. Does NOT close the
/// handle; use CloseProcessHandle for that. Thread-safe.</remarks>
function KillProcess(AHandle: THandle; AWaitMs: Integer = PROCRUN_KILL_WAIT_MS): Boolean;

/// <summary>Closes a process handle published by RunCaptureStdoutCancellable
/// and zeroes the variable.</summary>
/// <param name="AHandle">The handle to close; zeroed on return. Safe on an
/// already-zero handle.</param>
procedure CloseProcessHandle(var AHandle: THandle);

/// <summary>Spawns ACmdLine (CREATE_NO_WINDOW), reads stdout+stderr
/// line-by-line, and invokes AOnLine per complete line. Returns when the child
/// process exits, the deadline expires, or ACancel is signalled.</summary>
/// <param name="ACmdLine">Full command line, as CreateProcessW takes it.</param>
/// <param name="AOnLine">Called once per complete line, from whatever thread
/// this function runs on; a caller needing the UI thread marshals it itself,
/// typically via TThread.Queue. On a timeout the LAST line is the
/// 'timed out after N s' notice.</param>
/// <param name="AExitCode">The child exit code; PROCRUN_TIMED_OUT_EXIT_CODE
/// when the deadline expired; PROCRUN_CANCELLED_EXIT_CODE when ACancel was
/// signalled; -1 if the child could not be started.</param>
/// <param name="ATimeoutMs">Deadline for the WHOLE run, as for
/// RunCaptureStdout: on expiry the child's process tree is killed. &lt;=0 = no
/// deadline. Required, so every caller decides (1.31.6: it had none).</param>
/// <param name="ACancel">Optional cancel event, as for RunCaptureStdout.</param>
/// <returns>True if the child ran (including a run that timed out or was
/// cancelled); False if it was not started -- a spawn failure or a cancel that
/// was already set.</returns>
function RunCaptureStreaming(const ACmdLine: string; AOnLine: TOnLineProc; out AExitCode: Integer;
  ATimeoutMs: Integer; ACancel: THandle = 0): Boolean;

implementation

uses
  System.Math, System.Generics.Collections, System.Classes,
  DRagLint.Core.ControlChannel; // dl:unit DRagLint.Core.ControlChannel accepted -- lane X-BT: a graceful cancel sends the channel's own `shutdown` (ControlRequest, ControlPipeNameFor, CONTROL_MSG_SHUTDOWN); the wire stays defined in one unit

const
  { One chunk of the stdout pipe. }
  PROCRUN_PIPE_CHUNK = 64 * 1024;

  { Requested size of the stdout pipe's buffer. The read loop parks
    PROCRUN_POLL_MS whenever the pipe is empty, so a child writing faster than
    that drains is held to about one buffer per slice: the default (~4 KB)
    capped a burst near 160-500 KB/s, and a large engine report could run into
    its own deadline. 1 MB lifts the ceiling to ~40 MB/s. }
  PROCRUN_PIPE_BUFFER = 1024 * 1024;

  { Idle slice of RunCore's bounded read loop: how long it parks on the child's
    handle while the pipe is empty before it looks at the pipe, the clock and
    the cancel event again. It bounds the timeout's overshoot, the cancel's
    latency and the latency of output from a child that is still running. }
  PROCRUN_POLL_MS = 25;

  { How long a graceful cancel waits for the child's control pipe to accept the request. }
  PROCRUN_STANDDOWN_CONNECT_MS = 2000;

  { Bounded join of the stand-down thread when a run ends (the request itself is bounded, so this
    only trips when the control pipe misbehaves); on expiry the thread is detached, never waited on. }
  PROCRUN_STANDDOWN_JOIN_MS = 5000;

  { How often KillTree re-asks the job whether its members are gone. }
  PROCRUN_KILL_POLL_MS = 10;

  { How many job members KillTree holds by handle while it kills them; the
    WaitForMultipleObjects ceiling (MAXIMUM_WAIT_OBJECTS). An engine run's tree
    is a handful of processes. }
  PROCRUN_KILL_MAX_HELD = MAXIMUM_WAIT_OBJECTS;

type
  { JOBOBJECT_BASIC_PROCESS_ID_LIST with room for PROCRUN_KILL_MAX_HELD ids. }
  TJobPidList = record
    NumberAssigned: DWORD;
    NumberInList  : DWORD;
    Ids           : array[0..PROCRUN_KILL_MAX_HELD - 1] of NativeUInt;
  end;

  TJobMemberHandles = array[0..PROCRUN_KILL_MAX_HELD - 1] of THandle;

  { Winapi.Windows declares the JobObjectBasicAccountingInformation class but
    not its record; layout per winnt.h (JOBOBJECT_BASIC_ACCOUNTING_INFORMATION). }
  TJobAccounting = record
    TotalUserTime            : Int64;
    TotalKernelTime          : Int64;
    ThisPeriodTotalUserTime  : Int64;
    ThisPeriodTotalKernelTime: Int64;
    TotalPageFaultCount      : DWORD;
    TotalProcesses           : DWORD;
    ActiveProcesses          : DWORD;
    TotalTerminatedProcesses : DWORD;
  end;

  { Where RunCore sends each chunk it read; nil = accumulate into AOutput. }
  TChunkProc = reference to procedure(const AChunk: AnsiString);

var
  { Process handle published by a RunCore that is still running -> that run's
    job object. What lets KillProcess, which only holds the handle, kill the
    TREE. Guarded by GJobsLock; both live for the unit's lifetime. }
  GJobsLock: TObject = nil;
  GJobs    : TDictionary<THandle, THandle> = nil;

procedure RegisterJob(AProcess, AJob: THandle);
begin
  TMonitor.Enter(GJobsLock);
  try
    GJobs.AddOrSetValue(AProcess, AJob);
  finally
    TMonitor.Exit(GJobsLock);
  end;
end;

procedure UnregisterJob(AProcess: THandle);
begin
  TMonitor.Enter(GJobsLock);
  try
    GJobs.Remove(AProcess);
  finally
    TMonitor.Exit(GJobsLock);
  end;
end;

{ A private DUPLICATE of the job registered for AProcess, or 0. A duplicate, so
  the run's own CloseHandle(Job) cannot close it under a killer still using it.
  The caller closes it. }
function DuplicateJobFor(AProcess: THandle): THandle;
var
  Job: THandle;
begin
  Result:= 0;
  TMonitor.Enter(GJobsLock);
  try
    if GJobs.TryGetValue(AProcess, Job)
       and not DuplicateHandle(GetCurrentProcess, Job, GetCurrentProcess, @Result, 0, False, DUPLICATE_SAME_ACCESS) then
      Result:= 0;
  finally
    TMonitor.Exit(GJobsLock);
  end;
end;

{ True when no process of AJob is alive. A query that fails answers True: it
  cannot tell, and the caller has already waited for the direct child. }
function JobIsEmpty(AJob: THandle): Boolean;
var
  Info: TJobAccounting;
begin
  FillChar(Info, SizeOf(Info), 0);
  if not QueryInformationJobObject(AJob, JobObjectBasicAccountingInformation, @Info, SizeOf(Info), nil) then Exit(True);
  Result:= Info.ActiveProcesses = 0;
end;

{ Milliseconds left until ADeadline (High(UInt64) = none -> INFINITE). }
function MsLeft(ADeadline: UInt64): DWORD;
var
  NowMs: UInt64;
begin
  if ADeadline = High(UInt64) then Exit(INFINITE);
  NowMs:= GetTickCount64;
  if NowMs >= ADeadline then Exit(0);
  Result:= DWORD(Min(ADeadline - NowMs, UInt64(INFINITE - 1)));
end;

{ Opens every live member of AJob for SYNCHRONIZE into AHandles; returns the
  count (at most PROCRUN_KILL_MAX_HELD). A member that is gone, or cannot be
  opened, is simply not held. }
function HoldJobMembers(AJob: THandle; var AHandles: TJobMemberHandles): Integer;
var
  List: TJobPidList;
  I   : Integer;
  H   : THandle;
begin
  Result:= 0;
  FillChar(List, SizeOf(List), 0);
  { ERROR_MORE_DATA still fills the list as far as it goes; only a failure
    that wrote nothing leaves NumberInList at 0. }
  QueryInformationJobObject(AJob, JobObjectBasicProcessIdList, @List, SizeOf(List), nil);
  for I:= 0 to Min(Integer(List.NumberInList), PROCRUN_KILL_MAX_HELD) - 1 do
  begin
    H:= OpenProcess(SYNCHRONIZE, False, DWORD(List.Ids[I]));
    if H = 0 then Continue;
    AHandles[Result]:= H;
    Inc(Result);
  end;
end;

{ Kills AJob -- every process in it -- or, when there is no job, the process
  AProcess alone; then waits up to AWaitMs (negative = forever) for AProcess AND
  every job member to be gone. True once they are.

  The members are opened BEFORE the kill and waited on by handle: the job's
  active-process count can reach zero while a terminated member's handle is
  not yet signalled, so "the job is empty" alone does not mean a caller that
  holds the grandchild will see it gone. }
function KillTree(AProcess, AJob: THandle; AWaitMs: Integer): Boolean;
var
  Deadline: UInt64;
  Held    : TJobMemberHandles;
  HeldN   : Integer;
  I       : Integer;
begin
  HeldN:= if AJob <> 0 then HoldJobMembers(AJob, Held) else 0;
  try
    if (AJob = 0) or not TerminateJobObject(AJob, PROCRUN_KILLED_EXIT_CODE) then
      TerminateProcess(AProcess, PROCRUN_KILLED_EXIT_CODE);
    Deadline:= if AWaitMs < 0 then High(UInt64) else GetTickCount64 + UInt64(AWaitMs);
    Result:= WaitForSingleObject(AProcess, MsLeft(Deadline)) = WAIT_OBJECT_0;
    if Result and (HeldN > 0) then
      Result:= WaitForMultipleObjects(HeldN, @Held[0], True, MsLeft(Deadline)) <> WAIT_TIMEOUT;
    { Anything past the held set (more members than it holds). }
    if Result and (AJob <> 0) then
      while not JobIsEmpty(AJob) do
      begin
        if MsLeft(Deadline) = 0 then Exit(False);
        Sleep(PROCRUN_KILL_POLL_MS);
      end;
  finally
    for I:= 0 to HeldN - 1 do CloseHandle(Held[I]);
  end;
end;

{ Waits up to AWaitMs for AProcess to exit or ACancel (0 = none) to be set.
  0 = exited, else PROCRUN_TIMED_OUT_EXIT_CODE / PROCRUN_CANCELLED_EXIT_CODE. }
function WaitExitOrCancel(AProcess, ACancel: THandle; AWaitMs: DWORD): Integer;
var
  Handles: array[0..1] of THandle;
  Rc     : DWORD;
begin
  Handles[0]:= AProcess;
  Handles[1]:= ACancel;
  Rc:= WaitForMultipleObjects(if ACancel <> 0 then 2 else 1, @Handles[0], False, AWaitMs);
  if Rc = WAIT_OBJECT_0 + 1 then Result:= PROCRUN_CANCELLED_EXIT_CODE
  else if Rc = WAIT_TIMEOUT then Result:= PROCRUN_TIMED_OUT_EXIT_CODE
  else Result:= 0;
end;

function IsSet(AEvent: THandle): Boolean;
begin
  Result:= (AEvent <> 0) and (WaitForSingleObject(AEvent, 0) = WAIT_OBJECT_0);
end;

{ Why a running RunCore must stop now: PROCRUN_TIMED_OUT_EXIT_CODE once
  ADeadline has passed, PROCRUN_CANCELLED_EXIT_CODE once ACancel is set, else 0. }
function StopReason(ADeadline: UInt64; ACancel: THandle): Integer;
begin
  if GetTickCount64 >= ADeadline then Result:= PROCRUN_TIMED_OUT_EXIT_CODE
  else if IsSet(ACancel) then Result:= PROCRUN_CANCELLED_EXIT_CODE
  else Result:= 0;
end;

{ The line RunCore appends to AOutput on a timeout. }
function TimedOutText(ATimeoutMs: Integer): string;
begin
  Result:= Format('drag-lint plugin: timed out after %d s; the child process tree was killed',
                  [(ATimeoutMs + MSecsPerSec div 2) div MSecsPerSec]);
end;

{ The line RunCore appends to AOutput on a cancel. }
function CancelledText: string;
begin
  Result:= 'drag-lint plugin: cancelled; the child process tree was killed';
end;

{ The line RunCore appends when a child asked to stand down did not exit within its grace. }
function StandDownKilledText(AGraceMs: Integer): string;
begin
  Result:= Format('drag-lint plugin: cancelled; the child did not stand down within %d s and its process tree was killed',
                  [(AGraceMs + MSecsPerSec div 2) div MSecsPerSec]);
end;

{ Sends the control channel's `shutdown` to the engine with pid APid, on a thread of its own: the request
  blocks until the engine answers (once it has rolled back), and RunCore must keep draining the child's
  output meanwhile. The caller WaitFor's and frees the thread once the child is gone -- its pipe is gone
  then, so the request has returned. No pipe (an engine verb that does not listen) is a quick failure. }
function StartStandDown(APid: DWORD; AGraceMs: Integer): TThread;
begin
  Result:= TThread.CreateAnonymousThread(
    procedure
    var
      Reply, Err: string;
    begin
      ControlRequest(ControlPipeNameFor(APid), CONTROL_MSG_SHUTDOWN + #9 + IntToStr(AGraceMs),
        PROCRUN_STANDDOWN_CONNECT_MS, Reply, Err);
    end);
  Result.FreeOnTerminate:= False;
  Result.Start;
end;

{ The one body behind every runner in this unit.

  AHandleOut = nil  -> this function owns PI.hProcess and closes it (the
                       original, uncancellable contract).
  AHandleOut <> nil -> the handle is published to the caller the instant the
                       child exists, and the CALLER closes it. Its job is
                       registered against it until this function returns, so
                       KillProcess on it kills the tree.
  AOnChunk  <> nil  -> each chunk read goes there instead of into AOutput.

  THE DEADLINE COVERS THE WHOLE RUN (B-19), and so does ACancel (1.31.6): the
  pipe is peeked, read only when it holds data, and the clock and the cancel
  event are checked on every pass; an idle pass parks on the child's handle
  for PROCRUN_POLL_MS. On expiry or cancel the whole job -- the child and
  everything it spawned -- is terminated.

  AStandDownGraceMs > 0 (lane X-BT): a cancel first asks the child to stand
  down (StartStandDown) and keeps draining for the grace; the child's own exit
  ends the run normally, the end of the grace kills the tree. }
function RunCore(const ACmdLine: string; out AOutput: string; ATimeoutMs: Integer;  // dl:ok too-many-parameters@dc35, cyclomatic-complexity@ec7c -- the one private body behind four public runners; each parameter is one of their distinct contracts (lane X-BT added the stand-down grace), and a record would carry the same nine fields; the branches are the read loop's stop reasons, kept in one place on purpose
  ACreationFlags: DWORD; AHandleOut: PHandle; APidOut: PDWORD; ACancel: THandle;
  const AOnChunk: TChunkProc; AStandDownGraceMs: Integer = 0): Integer;
var
  SA        : TSecurityAttributes;
  ReadPipe  : THandle            ;
  WritePipe : THandle            ;
  SI        : TStartupInfoW      ;
  PI        : TProcessInformation;
  Buf       : array[0..PROCRUN_PIPE_CHUNK - 1] of AnsiChar;
  BytesRead : DWORD              ;
  ExitCode  : DWORD              ;
  WideCmd   : string             ;
  SB        : TStringBuilder     ;
  Job       : THandle            ;
  Avail     : DWORD              ;
  Deadline  : UInt64             ;
  Stop      : Integer            ; { 0, PROCRUN_TIMED_OUT_EXIT_CODE or PROCRUN_CANCELLED_EXIT_CODE }
  Registered: Boolean            ;
  StandDown : TThread            ; { the stand-down request in flight; nil = none asked }

  { A graceful cancel (AStandDownGraceMs > 0): the first cancel starts the stand-down and moves the
    deadline to the end of the grace; from then the cancel is ignored and the deadline means "kill". }
  function Reason(AStop: Integer): Integer;
  begin
    Result:= AStop;
    if AStandDownGraceMs <= 0 then Exit;
    if StandDown = nil then
    begin
      if AStop <> PROCRUN_CANCELLED_EXIT_CODE then Exit;
      StandDown:= StartStandDown(PI.dwProcessId, AStandDownGraceMs);
      Deadline := GetTickCount64 + UInt64(AStandDownGraceMs);
      Exit(0);
    end;
    if AStop = PROCRUN_CANCELLED_EXIT_CODE then Result:= 0
    else if AStop = PROCRUN_TIMED_OUT_EXIT_CODE then Result:= PROCRUN_CANCELLED_EXIT_CODE;
  end;

begin
  StandDown:= nil;
  Result:= -1;
  AOutput:= '';
  if AHandleOut <> nil then AHandleOut^:= 0;
  if APidOut    <> nil then APidOut^   := 0;
  { A cancel already set spawns nothing: a queue shutdown can land between
    dequeuing a job and starting it. }
  if IsSet(ACancel) then Exit(PROCRUN_CANCELLED_EXIT_CODE);
  SA.nLength:= SizeOf(SA);
  SA.bInheritHandle:= True;
  SA.lpSecurityDescriptor:= nil;
  if not CreatePipe(ReadPipe, WritePipe, @SA, PROCRUN_PIPE_BUFFER) then Exit;
  Registered:= False;
  FillChar(PI, SizeOf(PI), 0);
  { The job is what makes a timeout, a cancel or a KillProcess kill the TREE: a
    cmd.exe /c wrapper, or the engine's own dcc / graph children, inherit the
    pipe's write end, and killing only the direct child leaves them holding it
    open. No KILL_ON_JOB_CLOSE: a child that ends normally may leave a detached
    process behind on purpose, and closing the job must not take that down. }
  Job:= CreateJobObject(nil, nil);
  try
    SetHandleInformation(ReadPipe, HANDLE_FLAG_INHERIT, 0);
    FillChar(SI, SizeOf(SI), 0);
    SI.cb:= SizeOf(SI);
    SI.dwFlags   := STARTF_USESTDHANDLES;
    SI.hStdOutput:= WritePipe;
    SI.hStdError := WritePipe;
    SI.hStdInput := GetStdHandle(STD_INPUT_HANDLE);
    WideCmd:= ACmdLine;
    UniqueString(WideCmd);
    { Suspended, so the child cannot spawn anything before it is in the job. }
    if not CreateProcessW(nil, PWideChar(WideCmd), nil, nil, True, ACreationFlags or CREATE_SUSPENDED,
                          nil, nil, SI, PI) then
    begin
      CloseHandle(WritePipe);
      Exit;
    end;
    { A job that cannot take the child (an enclosing job that forbids nesting)
      degrades to killing the direct child only. }
    if (Job <> 0) and not AssignProcessToJobObject(Job, PI.hProcess) then
    begin
      CloseHandle(Job);
      Job:= 0;
    end;
    { BEFORE the read loop below, never after it -- see the unit header. The
      job is registered first, so a kill that sees the handle finds the job. }
    if (AHandleOut <> nil) and (Job <> 0) then
    begin
      RegisterJob(PI.hProcess, Job);
      Registered:= True;
    end;
    if AHandleOut <> nil then AHandleOut^:= PI.hProcess    ;
    if APidOut    <> nil then APidOut^   := PI.dwProcessId ;
    ResumeThread(PI.hThread);
    CloseHandle(WritePipe);
    Deadline:= if ATimeoutMs > 0 then GetTickCount64 + UInt64(ATimeoutMs) else High(UInt64);
    SB:= TStringBuilder.Create;
    try
      repeat
        Stop:= Reason(StopReason(Deadline, ACancel));
        if Stop <> 0 then Break;
        Avail:= 0;
        { A failed peek is the broken pipe: every writer has closed it -- EOF. }
        if not PeekNamedPipe(ReadPipe, nil, 0, nil, @Avail, nil) then Break;
        if Avail = 0 then
        begin
          { Idle. Once the child has exited its handle is signalled, and the
            slice becomes a plain sleep while a grandchild still holding the
            pipe finishes. }
          if WaitForSingleObject(PI.hProcess, PROCRUN_POLL_MS) = WAIT_OBJECT_0 then Sleep(PROCRUN_POLL_MS);
          Continue;
        end;
        if Avail > SizeOf(Buf) - 1 then Avail:= SizeOf(Buf) - 1;
        BytesRead:= 0;
        if not ReadFile(ReadPipe, Buf[0], Avail, BytesRead, nil) then Break;
        if BytesRead = 0 then Break;
        Buf[BytesRead]:= #0;
        if Assigned(AOnChunk) then AOnChunk(AnsiString(Buf))
        else SB.Append(string(AnsiString(Buf)));
      until False;
      { EOF is normally the exit, but a child can close its stdout and keep
        running: the exit is bounded by what is left of the deadline, and by
        the cancel. }
      if Stop = 0 then Stop:= Reason(WaitExitOrCancel(PI.hProcess, if StandDown = nil then ACancel else 0, MsLeft(Deadline)));
      { a stand-down that began in the wait just above: the grace runs from here }
      if (Stop = 0) and (StandDown <> nil) and (WaitForSingleObject(PI.hProcess, 0) <> WAIT_OBJECT_0) then
        Stop:= Reason(WaitExitOrCancel(PI.hProcess, 0, MsLeft(Deadline)));
      if Stop <> 0 then
      begin
        KillTree(PI.hProcess, Job, PROCRUN_KILL_WAIT_MS);
        if (SB.Length > 0) and (SB.Chars[SB.Length - 1] <> #10) then SB.AppendLine;
        if Stop = PROCRUN_TIMED_OUT_EXIT_CODE then SB.Append(TimedOutText(ATimeoutMs))
        else if StandDown <> nil then SB.Append(StandDownKilledText(AStandDownGraceMs))
        else SB.Append(CancelledText);
        Result:= Stop;
      end
      else
      begin
        GetExitCodeProcess(PI.hProcess, ExitCode);
        Result:= Integer(ExitCode);
      end;
      AOutput:= SB.ToString;
    finally
      SB.Free;
    end;
    { A published handle belongs to the caller: a killer thread may be holding
      it right now, and closing it here would be a use-after-close. }
    if AHandleOut = nil then CloseHandle(PI.hProcess);
    CloseHandle(PI.hThread );
  finally
    { the child is gone (exited or killed), so its pipe is: the request has returned or fails now }
    if StandDown <> nil then
    begin
      if WaitForSingleObject(StandDown.Handle, PROCRUN_STANDDOWN_JOIN_MS) = WAIT_OBJECT_0 then
        StandDown.Free
      else
        StandDown.FreeOnTerminate:= True; { detach: a leaked thread beats a hung IDE }
    end;
    { Unregistered BEFORE the job is closed: a KillProcess from now on falls
      back to the direct child, which has exited. }
    if Registered then UnregisterJob(PI.hProcess);
    CloseHandle(ReadPipe);
    if Job <> 0 then CloseHandle(Job);
  end;
end;

function RunCaptureStdout(const ACmdLine: string; out AOutput: string; ATimeoutMs: Integer;
  ACancel: THandle = 0; AStandDownGraceMs: Integer = 0): Integer;
begin
  Result:= RunCore(ACmdLine, AOutput, ATimeoutMs, CREATE_NO_WINDOW, nil, nil, ACancel, nil, AStandDownGraceMs);
end;

function RunCaptureStdoutCancellable(const ACmdLine: string; out AOutput: string;
  ATimeoutMs: Integer; APriority: DWORD; out AHandle: THandle; out APid: DWORD): Integer;
begin
  { @AHandle / @APid are the CALLER's variables -- that indirection is what
    lets RunCore publish them while this call is still blocked. }
  Result:= RunCore(ACmdLine, AOutput, ATimeoutMs, CREATE_NO_WINDOW or APriority,
                   @AHandle, @APid, 0, nil);
end;

function KillProcess(AHandle: THandle; AWaitMs: Integer = PROCRUN_KILL_WAIT_MS): Boolean;
var
  Job: THandle;
begin
  Result:= False;
  if AHandle = 0 then Exit;
  Job:= DuplicateJobFor(AHandle);
  try
    { Already gone is a SUCCESSFUL kill: the child may have finished between the
      supersession decision and this call, and reporting that as a failure would
      send the worker down a retry path for work that is already over -- unless
      its job still holds a grandchild, which keeps the run parked on the pipe
      and is exactly what the caller wants gone. }
    if (WaitForSingleObject(AHandle, 0) = WAIT_OBJECT_0) and ((Job = 0) or JobIsEmpty(Job)) then Exit(True);
    Result:= KillTree(AHandle, Job, AWaitMs);
  finally
    if Job <> 0 then CloseHandle(Job);
  end;
end;

procedure CloseProcessHandle(var AHandle: THandle);
begin
  if AHandle = 0 then Exit;
  CloseHandle(AHandle);
  AHandle:= 0;
end;

function RunCaptureStreaming(const ACmdLine: string; AOnLine: TOnLineProc; out AExitCode: Integer;
  ATimeoutMs: Integer; ACancel: THandle = 0): Boolean;
var
  LineBuffer: AnsiString;
  Unused    : string    ;
begin
  { A cancel already set spawns nothing -- and says so with False. }
  if IsSet(ACancel) then
  begin
    AExitCode:= PROCRUN_CANCELLED_EXIT_CODE;
    Exit(False);
  end;
  LineBuffer:= '';
  AExitCode:= RunCore(ACmdLine, Unused, ATimeoutMs, CREATE_NO_WINDOW, nil, nil, ACancel,
    procedure(const AChunk: AnsiString)
    var
      StartPos: Integer   ;
      LineEnd : Integer   ;
      Line    : AnsiString;
    begin
      LineBuffer:= LineBuffer + AChunk;
      StartPos:= 1;
      repeat
        { A byte scan, not Pos: Pos has no AnsiString overload and would round-trip
          the buffer through UnicodeString on every pass. }
        LineEnd:= StartPos;
        while (LineEnd <= Length(LineBuffer)) and (LineBuffer[LineEnd] <> #10) do Inc(LineEnd);
        if LineEnd > Length(LineBuffer) then Break;
        { CRLF -> LF: drop the trailing #13. }
        Line:= Copy(LineBuffer, StartPos, LineEnd - StartPos);
        if (Line <> '') and (Line[Length(Line)] = #13) then SetLength(Line, Length(Line) - 1);
        AOnLine(string(Line));
        StartPos:= LineEnd + 1;
      until False;
      { Keep the unfinished tail for the next chunk. }
      if StartPos <= Length(LineBuffer) then LineBuffer:= Copy(LineBuffer, StartPos, MaxInt)
      else LineBuffer:= '';
    end);
  Result:= AExitCode <> -1;
  if not Result then Exit;
  { The partial line at EOF, then the notice a stopped run ends with. }
  if LineBuffer <> '' then AOnLine(string(LineBuffer));
  if AExitCode = PROCRUN_TIMED_OUT_EXIT_CODE then AOnLine(TimedOutText(ATimeoutMs))
  else if AExitCode = PROCRUN_CANCELLED_EXIT_CODE then AOnLine(CancelledText);
end;

initialization
  GJobsLock:= TObject.Create;
  GJobs    := TDictionary<THandle, THandle>.Create;

finalization
  FreeAndNil(GJobs);
  FreeAndNil(GJobsLock);

end.
