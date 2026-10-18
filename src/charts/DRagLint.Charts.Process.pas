unit DRagLint.Charts.Process;

{ Runs one child process and captures its stdout and stderr (separately) with a timeout.

  Why this unit exists and does not wrap an existing helper (checked 2026-10-11, query
  --name RunCapture / RunProcess / RunCaptureStdout / CreateProcess against the engine
  self-index, then a text search of src\ for CreatePipe): the engine's own spawners are
  private class methods (TCompileChecker.SpawnAndCapture, TYadfFormatter.SpawnAndCapture)
  or a git-only function (Doc.GitSince.SpawnGit) that merge stderr into stdout and block on
  ReadFile; the plugin's RunCaptureStdout (src\delphi-plugin\DragLint.Plugin.ProcRun) does the
  same and the engine must not link a plugin unit. None returns the two streams apart or
  kills a child that overruns, so this unit is the reference shape (CreateProcessW with
  pipes) with both pipes polled instead of read to EOF.

  Both pipes are drained alternately with PeekNamedPipe while the process is waited on in
  short slices, so a child that fills either pipe cannot deadlock against a parent that is
  only reading the other one. Output is decoded as UTF-8. }

interface

type
  /// <summary>What a captured child process produced.</summary>
  TProcessResult = record
    /// <summary>The child's exit code; -1 when it was killed on timeout.</summary>
    ExitCode: Integer;
    /// <summary>Everything the child wrote to stdout, decoded as UTF-8.</summary>
    StdOut  : string;
    /// <summary>Everything the child wrote to stderr, decoded as UTF-8.</summary>
    StdErr  : string;
    /// <summary>True when the timeout elapsed and the child was terminated.</summary>
    TimedOut: Boolean;
  end;

/// <summary>Runs a command line without a console window and captures both output streams.</summary>
/// <param name="pCommandLine">The complete command line, program first (quote it yourself).</param>
/// <param name="pWorkDir">The child's working directory; '' inherits the caller's.</param>
/// <param name="pTimeoutMs">Wall-clock limit in milliseconds; 0 waits without limit. On expiry
/// the child is terminated and pResult.TimedOut is set.</param>
/// <param name="pResult">The exit code and the captured streams; reset on entry.</param>
/// <returns>False only when the process could not be started (CreateProcess failed); a child that
/// ran and failed returns True with its exit code.</returns>
/// <remarks>The child's stdin is the NUL device, so it can never block waiting for input.
/// Only the child itself is terminated on timeout, not grandchildren it started. Safe to call
/// from any thread; holds no shared state.</remarks>
function RunCapture(const pCommandLine, pWorkDir: string; pTimeoutMs: Cardinal;
  out pResult: TProcessResult): Boolean;

/// <summary>Quotes one command-line argument for CreateProcess.</summary>
/// <param name="pValue">The argument, any text.</param>
/// <returns>pValue in double quotes, escaped the way CommandLineToArgvW splits it: n backslashes
/// before an embedded quote become 2n+1, n before the closing quote become 2n, others stay.</returns>
/// <remarks>Pure; thread-safe. Lives beside RunCapture, whose command line it builds.</remarks>
function QuoteArg(const pValue: string): string;

implementation

uses
  Winapi.Windows, System.SysUtils, System.Classes;

const
  PIPE_CHUNK = 4096;
  WAIT_SLICE_MS = 10;
  KILL_WAIT_MS = 5000;
  NUL_DEVICE = 'NUL';
  QUOTE: Char = '"';
  BACKSLASH: Char = '\';

{ Quotes one argument for CreateProcess the way CommandLineToArgvW splits it: n backslashes
  before an embedded quote become 2n+1 (each doubled, plus one escaping the quote), n before the
  closing quote become 2n, and backslashes anywhere else stay as they are. }
function QuoteArg(const pValue: string): string;
var
  Slashes: Integer;
begin
  var SB:= TStringBuilder.Create;
  try
    SB.Append(QUOTE);
    Slashes:= 0;
    for var C in pValue do
    begin
      if C = BACKSLASH then
        Inc(Slashes)
      else
      begin
        if C = QUOTE then SB.Append(BACKSLASH, Slashes * 2 + 1)
        else SB.Append(BACKSLASH, Slashes);
        Slashes:= 0;
        SB.Append(C);
      end;
    end;
    SB.Append(BACKSLASH, Slashes * 2);
    SB.Append(QUOTE);
    Result:= SB.ToString;
  finally
    SB.Free;
  end;
end;

{ Moves whatever is waiting in pPipe into pSink, without blocking. A broken or empty pipe
  simply ends the loop. }
procedure DrainPipe(pPipe: THandle; pSink: TStream);
var
  Buf  : TBytes;
  Avail: DWORD;
  Want : DWORD;
  Got  : DWORD;
begin
  SetLength(Buf, PIPE_CHUNK);
  Avail:= 0;
  while PeekNamedPipe(pPipe, nil, 0, nil, @Avail, nil) and (Avail > 0) do
  begin
    Want:= Avail;
    if Want > PIPE_CHUNK then Want:= PIPE_CHUNK;
    Got:= 0;
    if not ReadFile(pPipe, Buf[0], Want, Got, nil) then Break;
    if Got = 0 then Break;
    pSink.WriteBuffer(Buf[0], Got);
  end;
end;

function Decode(pSink: TBytesStream): string;
begin
  Result:= TEncoding.UTF8.GetString(pSink.Bytes, 0, Integer(pSink.Size));
end;

procedure CloseIfOpen(var pHandle: THandle);
begin
  if (pHandle <> 0) and (pHandle <> INVALID_HANDLE_VALUE) then CloseHandle(pHandle);
  pHandle:= 0;
end;

function RunCapture(const pCommandLine, pWorkDir: string; pTimeoutMs: Cardinal;
  out pResult: TProcessResult): Boolean;
var
  SA                 : TSecurityAttributes;
  SI                 : TStartupInfoW;
  PI                 : TProcessInformation;
  OutRd, OutWr       : THandle;
  ErrRd, ErrWr       : THandle;
  NulIn              : THandle;
  Cmd, Dir           : string;
  OutSink, ErrSink   : TBytesStream;
  Started, Waited    : UInt64;
  Code               : DWORD;
  DirPtr             : PWideChar;
begin
  Result:= False;
  pResult.ExitCode:= -1;
  pResult.StdOut:= '';
  pResult.StdErr:= '';
  pResult.TimedOut:= False;
  OutRd:= 0;
  OutWr:= 0;
  ErrRd:= 0;
  ErrWr:= 0;
  NulIn:= 0;
  FillChar(PI, SizeOf(PI), 0);
  SA.nLength:= SizeOf(SA);
  SA.bInheritHandle:= True;
  SA.lpSecurityDescriptor:= nil;
  try
    if not CreatePipe(OutRd, OutWr, @SA, 0) then Exit;
    if not CreatePipe(ErrRd, ErrWr, @SA, 0) then Exit;
    // The parent's read ends must not be inherited, or the pipes never report EOF.
    SetHandleInformation(OutRd, HANDLE_FLAG_INHERIT, 0);
    SetHandleInformation(ErrRd, HANDLE_FLAG_INHERIT, 0);
    NulIn:= CreateFile(PChar(NUL_DEVICE), GENERIC_READ, FILE_SHARE_READ or FILE_SHARE_WRITE, @SA,
      OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, 0);
    if NulIn = INVALID_HANDLE_VALUE then NulIn:= 0;
    FillChar(SI, SizeOf(SI), 0);
    SI.cb:= SizeOf(SI);
    SI.dwFlags:= STARTF_USESTDHANDLES;
    SI.hStdOutput:= OutWr;
    SI.hStdError:= ErrWr;
    SI.hStdInput:= NulIn;
    Cmd:= pCommandLine;
    UniqueString(Cmd);  // CreateProcessW may write into the buffer
    Dir:= pWorkDir;
    DirPtr:= nil;
    if Dir <> '' then DirPtr:= PWideChar(Dir);
    if not CreateProcessW(nil, PWideChar(Cmd), nil, nil, True, CREATE_NO_WINDOW, nil, DirPtr, SI, PI) then Exit;
    Result:= True;
    // The child owns its copies now; closing ours is what lets the pipes end.
    CloseIfOpen(OutWr);
    CloseIfOpen(ErrWr);
    CloseIfOpen(NulIn);
    OutSink:= TBytesStream.Create;
    try
      ErrSink:= TBytesStream.Create;
      try
        Started:= GetTickCount64;
        while True do
        begin
          DrainPipe(OutRd, OutSink);
          DrainPipe(ErrRd, ErrSink);
          if WaitForSingleObject(PI.hProcess, WAIT_SLICE_MS) = WAIT_OBJECT_0 then Break;
          Waited:= GetTickCount64 - Started;
          if (pTimeoutMs <> 0) and (Waited >= pTimeoutMs) then
          begin
            pResult.TimedOut:= True;
            TerminateProcess(PI.hProcess, 1);
            WaitForSingleObject(PI.hProcess, KILL_WAIT_MS);
            Break;
          end;
        end;
        // The child has ended (or been killed): take what it left in the pipes.
        DrainPipe(OutRd, OutSink);
        DrainPipe(ErrRd, ErrSink);
        Code:= 0;
        if not pResult.TimedOut and GetExitCodeProcess(PI.hProcess, Code) then pResult.ExitCode:= Integer(Code);
        pResult.StdOut:= Decode(OutSink);
        pResult.StdErr:= Decode(ErrSink);
      finally
        ErrSink.Free;
      end;
    finally
      OutSink.Free;
    end;
  finally
    CloseIfOpen(PI.hProcess);
    CloseIfOpen(PI.hThread);
    CloseIfOpen(OutRd);
    CloseIfOpen(OutWr);
    CloseIfOpen(ErrRd);
    CloseIfOpen(ErrWr);
    CloseIfOpen(NulIn);
  end;
end;

end.
