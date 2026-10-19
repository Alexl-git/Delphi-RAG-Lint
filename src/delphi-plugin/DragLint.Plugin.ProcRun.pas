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
/// <returns>The child exit code; PROCRUN_TIMED_OUT_EXIT_CODE when the deadline
/// expired; -1 if it could not start.</returns>
function RunCaptureStdout(const ACmdLine: string; out AOutput: string; ATimeoutMs: Integer): Integer;

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

/// <summary>Terminates the process AHandle refers to and WAITS up to AWaitMs
/// for it to actually go away.</summary>
/// <param name="AHandle">A handle published by RunCaptureStdoutCancellable.
/// Zero is accepted and answers False.</param>
/// <param name="AWaitMs">Milliseconds to wait for the exit; negative = wait
/// forever.</param>
/// <returns>True once the process is gone, including when it had already
/// exited on its own. False if it is still running when the budget expires --
/// which is what a caller holding a handle without PROCESS_TERMINATE gets, and
/// it must not treat that as a kill.</returns>
/// <remarks>The wait is not politeness. TerminateProcess is ASYNCHRONOUS, so a
/// caller that returns immediately and respawns can leave two engine runs --
/// and their dcc grandchildren -- competing for the cores the IDE needs. Does
/// NOT close the handle; use CloseProcessHandle for that.</remarks>
function KillProcess(AHandle: THandle; AWaitMs: Integer = PROCRUN_KILL_WAIT_MS): Boolean;

/// <summary>Closes a process handle published by RunCaptureStdoutCancellable
/// and zeroes the variable.</summary>
/// <param name="AHandle">The handle to close; zeroed on return. Safe on an
/// already-zero handle.</param>
procedure CloseProcessHandle(var AHandle: THandle);

/// <summary>Spawns ACmdLine (CREATE_NO_WINDOW), reads stdout+stderr
/// line-by-line, and invokes AOnLine per complete line. Returns when the child
/// process exits.</summary>
/// <param name="ACmdLine">Full command line, as CreateProcessW takes it.</param>
/// <param name="AOnLine">Called once per complete line, from whatever thread
/// this function runs on; a caller needing the UI thread marshals it itself,
/// typically via TThread.Queue.</param>
/// <param name="AExitCode">The child exit code on success; undefined when this
/// function returns False.</param>
/// <returns>True if the child ran; False if it could not be started.</returns>
function RunCaptureStreaming(const ACmdLine: string; AOnLine: TOnLineProc; out AExitCode: Integer): Boolean;

implementation

const
  { One chunk of the stdout pipe. Both readers below MUST agree on it -- they
    are two copies of the same drain loop and the size is the only thing they
    still share by value rather than by call. }
  PROCRUN_PIPE_CHUNK = 4096;

  { Idle slice of RunCore's bounded read loop: how long it parks on the child's
    handle while the pipe is empty before it looks at the pipe and the clock
    again. It bounds both the timeout's overshoot and the latency of output from
    a child that is still running. }
  PROCRUN_POLL_MS = 25;

{ The line RunCore appends to AOutput on a timeout. }
function TimedOutText(ATimeoutMs: Integer): string;
begin
  Result:= Format('drag-lint plugin: timed out after %d s; the child process tree was killed',
                  [(ATimeoutMs + MSecsPerSec div 2) div MSecsPerSec]);
end;

{ The one body behind RunCaptureStdout and RunCaptureStdoutCancellable.

  AHandleOut = nil  -> this function owns PI.hProcess and closes it (the
                       original, uncancellable contract).
  AHandleOut <> nil -> the handle is published to the caller the instant the
                       child exists, and the CALLER closes it.

  THE DEADLINE COVERS THE WHOLE RUN (B-19). Until 1.31.5 the loop sat in a
  blocking ReadFile until EOF and only then waited ATimeoutMs, so the timeout
  bounded the wait AFTER the child had finished writing and never fired on a
  hung child. Now the pipe is peeked, read only when it holds data, and the
  clock is checked on every pass; an idle pass parks on the child's handle for
  PROCRUN_POLL_MS. On expiry the whole job -- the child and everything it
  spawned -- is terminated. }
function RunCore(const ACmdLine: string; out AOutput: string; ATimeoutMs: Integer;
  ACreationFlags: DWORD; AHandleOut: PHandle; APidOut: PDWORD): Integer;
var
  SA       : TSecurityAttributes       ;
  ReadPipe : THandle                   ;
  WritePipe: THandle                   ;
  SI       : TStartupInfoW             ;
  PI       : TProcessInformation       ;
  Buf      : array[0..PROCRUN_PIPE_CHUNK - 1] of AnsiChar;
  BytesRead: DWORD                                       ;
  ExitCode : DWORD                     ;
  WideCmd  : string                    ;
  SB       : TStringBuilder            ;
  TV       : DWORD                     ;
  Job      : THandle                   ;
  Avail    : DWORD                     ;
  Deadline : UInt64                    ;
  NowMs    : UInt64                    ;
  TimedOut : Boolean                   ;
begin
  Result:= -1;
  AOutput:= '';
  if AHandleOut <> nil then AHandleOut^:= 0;
  if APidOut    <> nil then APidOut^   := 0;
  SA.nLength:= SizeOf(SA);
  SA.bInheritHandle:= True;
  SA.lpSecurityDescriptor:= nil;
  if not CreatePipe(ReadPipe, WritePipe, @SA, 0) then Exit;
  { The job is what makes a timeout kill the TREE: a cmd.exe /c wrapper, or the
    engine's own dcc / graph children, inherit the pipe's write end, and killing
    only the direct child leaves them holding it open. No KILL_ON_JOB_CLOSE: a
    child that ends normally may leave a detached process behind on purpose,
    and closing the job must not take that down. }
  Job:= CreateJobObject(nil, nil);
  try
    SetHandleInformation(ReadPipe, HANDLE_FLAG_INHERIT, 0);
    FillChar(SI, SizeOf(SI), 0);
    SI.cb:= SizeOf(SI);
    SI.dwFlags   := STARTF_USESTDHANDLES;
    SI.hStdOutput:= WritePipe;
    SI.hStdError := WritePipe;
    SI.hStdInput := GetStdHandle(STD_INPUT_HANDLE);
    FillChar(PI, SizeOf(PI), 0);
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
    { BEFORE the read loop below, never after it -- see the unit header. }
    if AHandleOut <> nil then AHandleOut^:= PI.hProcess    ;
    if APidOut    <> nil then APidOut^   := PI.dwProcessId ;
    ResumeThread(PI.hThread);
    CloseHandle(WritePipe);
    Deadline:= if ATimeoutMs > 0 then GetTickCount64 + UInt64(ATimeoutMs) else High(UInt64);
    TimedOut:= False;
    SB:= TStringBuilder.Create;
    try
      repeat
        if GetTickCount64 >= Deadline then
        begin
          TimedOut:= True;
          Break;
        end;
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
        SB.Append(string(AnsiString(Buf)));
      until False;
      if not TimedOut then
      begin
        { EOF is normally the exit, but a child can close its stdout and keep
          running: the exit is bounded by what is left of the deadline. }
        NowMs:= GetTickCount64;
        if ATimeoutMs <= 0 then TV:= INFINITE
        else TV:= if NowMs >= Deadline then 0 else DWORD(Deadline - NowMs);
        TimedOut:= WaitForSingleObject(PI.hProcess, TV) = WAIT_TIMEOUT;
      end;
      if TimedOut then
      begin
        if (Job = 0) or not TerminateJobObject(Job, PROCRUN_KILLED_EXIT_CODE) then
          TerminateProcess(PI.hProcess, PROCRUN_KILLED_EXIT_CODE);
        WaitForSingleObject(PI.hProcess, PROCRUN_KILL_WAIT_MS);
        if (SB.Length > 0) and (SB.Chars[SB.Length - 1] <> #10) then SB.AppendLine;
        SB.Append(TimedOutText(ATimeoutMs));
        Result:= PROCRUN_TIMED_OUT_EXIT_CODE;
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
    CloseHandle(ReadPipe);
    if Job <> 0 then CloseHandle(Job);
  end;
end;

function RunCaptureStdout(const ACmdLine: string; out AOutput: string; ATimeoutMs: Integer): Integer;
begin
  Result:= RunCore(ACmdLine, AOutput, ATimeoutMs, CREATE_NO_WINDOW, nil, nil);
end;

function RunCaptureStdoutCancellable(const ACmdLine: string; out AOutput: string;
  ATimeoutMs: Integer; APriority: DWORD; out AHandle: THandle; out APid: DWORD): Integer;
begin
  { @AHandle / @APid are the CALLER's variables -- that indirection is what
    lets RunCore publish them while this call is still blocked. }
  Result:= RunCore(ACmdLine, AOutput, ATimeoutMs, CREATE_NO_WINDOW or APriority,
                   @AHandle, @APid);
end;

function KillProcess(AHandle: THandle; AWaitMs: Integer = PROCRUN_KILL_WAIT_MS): Boolean;
var
  TV: DWORD;
begin
  Result:= False;
  if AHandle = 0 then Exit;
  { Already gone is a SUCCESSFUL kill: the child may have finished between the
    supersession decision and this call, and reporting that as a failure would
    send the worker down a retry path for work that is already over. }
  if WaitForSingleObject(AHandle, 0) = WAIT_OBJECT_0 then Exit(True);
  TerminateProcess(AHandle, PROCRUN_KILLED_EXIT_CODE);
  if AWaitMs < 0 then TV:= INFINITE else TV:= DWORD(AWaitMs);
  Result:= WaitForSingleObject(AHandle, TV) = WAIT_OBJECT_0;
end;

procedure CloseProcessHandle(var AHandle: THandle);
begin
  if AHandle = 0 then Exit;
  CloseHandle(AHandle);
  AHandle:= 0;
end;

function RunCaptureStreaming(const ACmdLine: string; AOnLine: TOnLineProc; out AExitCode: Integer): Boolean;
var
  SA       : TSecurityAttributes;
  ReadPipe : THandle;
  WritePipe: THandle;
  SI       : TStartupInfoW;
  PI       : TProcessInformation;
  Buf      : array[0..PROCRUN_PIPE_CHUNK - 1] of AnsiChar;
  BytesRead: DWORD;
  ExitCode : DWORD;
  WideCmd  : string;
  LineBuffer: AnsiString;
  StartPos, LineEnd: Integer;
  TempStr: AnsiString;
begin
  Result:= False;
  AExitCode:= -1;
  SA.nLength:= SizeOf(SA);
  SA.bInheritHandle:= True;
  SA.lpSecurityDescriptor:= nil;
  if not CreatePipe(ReadPipe, WritePipe, @SA, 0) then Exit;
  try
    SetHandleInformation(ReadPipe, HANDLE_FLAG_INHERIT, 0);
    FillChar(SI, SizeOf(SI), 0);
    SI.cb:= SizeOf(SI);
    SI.dwFlags   := STARTF_USESTDHANDLES;
    SI.hStdOutput:= WritePipe;
    SI.hStdError := WritePipe;
    SI.hStdInput := GetStdHandle(STD_INPUT_HANDLE);
    FillChar(PI, SizeOf(PI), 0);
    WideCmd:= ACmdLine;
    UniqueString(WideCmd);
    if not CreateProcessW(nil, PWideChar(WideCmd), nil, nil, True, CREATE_NO_WINDOW, nil, nil, SI, PI) then
    begin
      CloseHandle(WritePipe);
      Exit;
    end;
    CloseHandle(WritePipe);
    LineBuffer:= '';
    { The dl:ok below: Buf is an OUTPUT buffer. ReadFile fills it and reports
      how many bytes it wrote; nothing here reads it first. The flow lattice
      cannot see through an untyped var parameter, so it scores the call as a
      read of uninitialised memory. }
    repeat
      BytesRead:= 0;
      if not ReadFile(ReadPipe, Buf[0], SizeOf(Buf) - 1, BytesRead, nil) then Break;  // dl:ok used-before-assignment@50aa
      if BytesRead = 0 then Break;
      Buf[BytesRead]:= #0;
      TempStr:= AnsiString(Buf);
      LineBuffer:= LineBuffer + TempStr;

      { Process complete lines from LineBuffer. }
      StartPos:= 1;
      repeat
        LineEnd:= Pos(#10, LineBuffer, StartPos);
        if LineEnd = 0 then Break;
        { Extract line, trimming trailing #13 if present (CRLF -> LF). }
        TempStr:= Copy(LineBuffer, StartPos, LineEnd - StartPos);
        if (Length(TempStr) > 0) and (TempStr[Length(TempStr)] = #13) then
          SetLength(TempStr, Length(TempStr) - 1);
        AOnLine(string(TempStr));
        StartPos:= LineEnd + 1;
      until False;

      { Keep unprocessed tail for next iteration. }
      if StartPos <= Length(LineBuffer) then
        LineBuffer:= Copy(LineBuffer, StartPos, MaxInt)
      else
        LineBuffer:= '';
    until False;

    { Invoke AOnLine for any remaining partial line at EOF. }
    if Length(LineBuffer) > 0 then AOnLine(string(LineBuffer));

    WaitForSingleObject(PI.hProcess, INFINITE);
    GetExitCodeProcess(PI.hProcess, ExitCode);
    AExitCode:= Integer(ExitCode);
    Result:= True;
    CloseHandle(PI.hProcess);
    CloseHandle(PI.hThread);
  finally
    CloseHandle(ReadPipe);
  end;
end;

end.
