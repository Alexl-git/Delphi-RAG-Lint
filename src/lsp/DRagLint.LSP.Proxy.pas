unit DRagLint.LSP.Proxy;

{ v1.7 Task 1 -- the transparent LSP relay.

  drag-lint registers as the IDE's Pascal Code Insight LSP server, spawns
  DelphiLSP as a child process, and relays the protocol between the IDE and
  DelphiLSP. This unit is the RELAY ONLY. It moves bytes and understands
  nothing: no LSP framing, no JSON, no merging.

  WHY A RELAY AT ALL. The IDE's Code Insight manager is EXCLUSIVE -- one
  manager per language. Registering drag-lint the obvious way would trade away
  the actual compiler front end (generics, `with`, inline vars, the unsaved
  buffer) in exchange for a symbol index. Sitting in FRONT of DelphiLSP removes
  the either/or: DelphiLSP keeps answering everything it answers today, and
  drag-lint's index-derived facts are added on top later.

  WHY THE PARSING COMES LATER, IN ITS OWN TASK. Parsing is the first
  opportunity to corrupt a stream that currently cannot be corrupted. As long
  as this unit only copies bytes, byte-identity with a direct DelphiLSP
  connection is a property of the design rather than a property of the tests.
  Framing lands in Task 4 and merging in Task 6+, each behind the guards that
  prove byte-identity still holds.

  THE RULE THAT OUTRANKS EVERY FEATURE: FAIL OPEN. As a proxy, a drag-lint bug
  no longer costs drag-lint features -- it costs the owner Code Insight
  entirely, in an IDE they would then have to repair through the very dialogs
  that are misbehaving. So there is no "degraded but running" mode here: if the
  child cannot be spawned this process reports on stderr and EXITS NON-ZERO,
  rather than accepting requests it cannot answer. A client that gets a dead
  server retries and eventually tells the user; a client that gets a silent
  server waits forever. }

interface

uses
  Winapi.Windows
  ;

type
  /// <summary>Everything the relay needs to start. All fields are optional;
  /// a zeroed record resolves DelphiLSP from the installed Studio and relays
  /// stdio.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.CLI.Run (DRagLint.CLI.pas), declaration (DRagLint.LSP.Proxy.pas)</para>
  /// <para>Used in units: DRagLint.CLI, DRagLint.LSP.Proxy</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TLspProxyOptions = record
    /// <summary>Full path to the DelphiLSP executable to spawn. Empty means
    /// resolve it from the installed RAD Studio. The test harness sets this to
    /// a stub server so the relay can be proven without RAD Studio in the
    /// loop.</summary>
    DelphiLspExe: string;
    /// <summary>Extra command line passed through to the child, appended after
    /// the executable. DelphiLSP itself takes no arguments (it self-configures
    /// from the IDE-generated `&lt;Project&gt;.delphilsp.json`), so this exists
    /// for stub servers and future diagnostics only.</summary>
    ChildArgs: string;
    /// <summary>When non-empty, every framed LSP message is appended to this
    /// file with a direction tag, in addition to being relayed. Off by
    /// default.</summary>
    /// <remarks>
    /// EXISTS SO A LIVE IDE SESSION PRODUCES EVIDENCE RATHER THAN ANECDOTES.
    /// Registering this relay as the IDE's Pascal language server is the step
    /// where a drag-lint bug stops costing drag-lint features and starts
    /// costing all of Code Insight. The questions that decides -- what the IDE
    /// really sends as initializationOptions, how often it cancels, whether it
    /// restarts the server per project activation -- cannot be answered from
    /// outside the stream.
    /// <para>A trace failure must NEVER perturb the relay. Writes are wrapped
    /// and swallowed, and the bytes recorded are the ones already being
    /// forwarded rather than a re-encoding of them, so the relay stays
    /// byte-identical with tracing on.</para>
    /// </remarks>
    TraceFile: string;
  end;

/// <summary>Resolves the DelphiLSP executable to spawn.</summary>
/// <param name="AOverride">An explicit path; returned as-is when non-empty,
/// whether or not it exists, so that a bad --delphi-lsp reports the path the
/// caller actually asked for rather than a silently substituted default.</param>
/// <returns>Full path to `bin64\DelphiLSP.exe`, or an empty string when no
/// installed Studio could be located.</returns>
/// <remarks>
/// The 64-bit binary is deliberate. The IDE currently launches the
/// 32-bit one (CodeInsightUse64BitBinary = False), so proxying also moves the
/// Pascal LSP to x64, which is the build that copes with a large project.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.LSP.Proxy.RunLspProxy (DRagLint.LSP.Proxy.pas)</para>
/// <para>Calls: DRagLint.LSP.Proxy.StdErrLine, ExcludeTrailingPathDelimiter, FileExists</para>
/// <para>Returns: Root + '\bin64\DelphiLSP.exe'; ''</para>
/// <para>Touches: registry</para>
/// <seealso cref="DRagLint.LSP.Proxy.StdErrLine"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ResolveDelphiLspPath(const AOverride: string): string;

/// <summary>Runs the transparent relay until the child exits or either stream
/// closes, then returns the child's exit code.</summary>
/// <param name="AOptions">Child selection; see TLspProxyOptions.</param>
/// <returns>The child's exit code on a normal relay; 3 when the child could
/// not be found or spawned (criterion 3), which is reported on stderr.</returns>
/// <remarks>
/// Blocking; call from the main thread. Writes NOTHING to stdout
/// except bytes received from the child -- anything else would land inside the
/// JSON-RPC stream and desynchronise the client.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.Run (DRagLint.CLI.pas)</para>
/// <para>Calls: CloseHandle, CreatePipe, CreateProcess, DRagLint.Core.JobObject.AssignToDragLintJob, DRagLint.LSP.Proxy.PumpFramed, DRagLint.LSP.Proxy.ResolveDelphiLspPath, DRagLint.LSP.Proxy.StdErrLine, DRagLint.LSP.Proxy.TPumpThread.Create, FileExists, FillChar (+9 more)</para>
/// <para>Returns: EXIT_SPAWN_FAILED; Integer(Code)</para>
/// <para>Complexity: 12 (cyclomatic, outer body), 147 lines (full implementation)</para>
/// <para>Pure</para>
/// <seealso cref="DRagLint.Core.JobObject.AssignToDragLintJob"/>
/// <seealso cref="DRagLint.LSP.Proxy.PumpFramed"/>
/// <seealso cref="DRagLint.LSP.Proxy.ResolveDelphiLspPath"/>
/// <seealso cref="DRagLint.LSP.Proxy.StdErrLine"/>
/// <seealso cref="DRagLint.LSP.Proxy.TPumpThread.Create"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function RunLspProxy(const AOptions: TLspProxyOptions): Integer;

implementation

uses
    System.SysUtils
  , System.Classes
  , System.Win.Registry
  , DRagLint.Core.JobObject
  ;

const
  { The relay copies whatever a single ReadFile hands it. The size is a
    throughput knob and nothing more: a partial read is normal on a pipe and is
    forwarded as-is, because the byte STREAM is what must match, not the
    chunking of it. }
  PUMP_BUFFER_BYTES = 64 * 1024;

  { Keep in step with the registry root drag-lint-switch writes to. Both are
    pinned to 37.0 (Delphi 13 Florence) because that is the only Studio this
    product supports; a future version bump touches both, deliberately. }
  BDS_REG_KEY  = 'Software\Embarcadero\BDS\37.0';
  BDS_FALLBACK = 'C:\Program Files (x86)\Embarcadero\Studio\37.0';

  EXIT_SPAWN_FAILED = 3;

  { How long to wait for a child that has already closed stdout to actually
    exit. It is a courtesy, not a contract: whatever is still running after it
    is terminated, because the relay has nothing left to relay. }
  CHILD_REAP_TIMEOUT_MS = 5000;

type
  { A one-way byte pump. Two of these run as threads (client->child and the
    child's stderr->ours) while the main thread pumps child->client; the main
    thread is the one that must observe EOF, because that is what ends the
    session.

    EOF IS PART OF THE PROTOCOL, which is what the flags are for. When the
    client closes its end, the child must be TOLD -- by closing the write end
    of its stdin -- or it sits waiting for a request that is never coming, its
    stdout never closes, and the main pump blocks on a session both other
    parties consider finished. Relaying the bytes but not the end-of-stream is
    a deadlock that looks exactly like a hung language server.

    These run as FreeOnTerminate daemons and are deliberately NOT joined. A
    pump blocked in ReadFile on the client's stdin cannot be woken from
    outside, so joining it would trade the deadlock above for the same
    deadlock at shutdown. Once the child's stdout closes there is nothing left
    to relay, and process exit is the correct way to end them. }
  TPumpThread = class(TThread)
  private
    FSrc     : THandle;
    FDst     : THandle;
    FCloseSrc: Boolean;
    FCloseDst: Boolean;
    FFramed  : Boolean;
    FDir     : string ;
  protected
    procedure Execute; override;
  public
    constructor Create(ASrc, ADst: THandle; ACloseSrc, ACloseDst, AFramed: Boolean;
      const ADir: string = '');
  end;

{ Copies bytes from ASrc to ADst until either end closes. Returns when the
  source reports EOF (ReadFile succeeds with 0 bytes, or fails with
  ERROR_BROKEN_PIPE) or the destination stops accepting.

  A partial WriteFile is retried on the remainder rather than treated as done.
  This is the one place a "transparent" relay silently loses data if written
  the obvious way, and the loss would look like a truncated LSP message -- i.e.
  like DelphiLSP misbehaving, not like the proxy. }
procedure PumpBytes(ASrc, ADst: THandle);
var
  Buf     : array[0..PUMP_BUFFER_BYTES - 1] of Byte;
  Got     : DWORD;
  Written : DWORD;
  Offset  : DWORD;
begin
  if (ASrc = 0) or (ASrc = INVALID_HANDLE_VALUE) then Exit;
  if (ADst = 0) or (ADst = INVALID_HANDLE_VALUE) then Exit;
  while True do
  begin
    Got:= 0;
    if not ReadFile(ASrc, Buf, SizeOf(Buf), Got, nil) then Break; { closed }
    if Got = 0 then Break;                                        { EOF }
    Offset:= 0;
    while Offset < Got do
    begin
      Written:= 0;
      if not WriteFile(ADst, Buf[Offset], Got - Offset, Written, nil) then Exit;
      if Written = 0 then Exit;
      Inc(Offset, Written);
    end;
  end;
end;

{ ---- v1.7 Task 4: framing, still transparent -------------------------------

  The merge handlers of Tasks 6+ need whole JSON-RPC messages, so the relay has
  to learn where a message starts and ends. This is that step and ONLY that
  step: the bytes forwarded are still exactly the bytes received, in the same
  order. What changes is the CHUNKING -- a message is handed on complete rather
  than in whatever pieces a pipe read produced.

  The whole design constraint here is that a framer must never become a filter.
  Three ways that could happen, and what prevents each:

  * Bytes that are not part of any message must still be forwarded. A server
    that logs a line to stdout, or a preamble like the test stub's, would
    otherwise vanish -- and it would vanish SILENTLY, which is the worst
    possible way for a relay to fail. Anything before a header is passed
    straight through.
  * A malformed or unparseable header must not stall the stream. It is
    forwarded and the framer moves on, rather than waiting forever for a body
    whose length it never understood.
  * Whatever remains buffered at EOF is flushed. A partial message is still
    the client's data; dropping it would turn a truncated reply into no reply.

  The only bytes ever held back are those of a message that has genuinely not
  arrived in full yet, plus at most the 14 trailing bytes that could be the
  beginning of a "Content-Length:" header. }

const
  LSP_HEADER = 'Content-Length:';

{ Writes ACount bytes from ABuf. Returns False if the destination closed. }
function WriteAll(ADst: THandle; const ABuf: TBytes; AStart, ACount: Integer): Boolean;
var
  Sent  : DWORD;
  Offset: Integer;
begin
  Result:= True;
  Offset:= 0;
  while Offset < ACount do
  begin
    Sent:= 0;
    if not WriteFile(ADst, ABuf[AStart + Offset], DWORD(ACount - Offset), Sent, nil) then Exit(False);
    if Sent = 0 then Exit(False);
    Inc(Offset, Integer(Sent));
  end;
end;

{ Case-insensitive search for the header literal, from AFrom. -1 when absent. }
function IndexOfHeader(const ABuf: TBytes; ALen, AFrom: Integer): Integer;
var
  I, J: Integer;
  Ok  : Boolean;
begin
  for I:= AFrom to ALen - Length(LSP_HEADER) do
  begin
    Ok:= True;
    for J:= 1 to Length(LSP_HEADER) do
      if UpCase(AnsiChar(ABuf[I + J - 1])) <> UpCase(AnsiChar(LSP_HEADER[J])) then
      begin
        Ok:= False;
        Break;
      end;
    if Ok then Exit(I);
  end;
  Result:= -1;
end;

{ How many trailing bytes could still turn into a header once more arrives.
  Without this the framer would forward "Content-Len" as junk and then fail to
  recognise the header when the rest of it showed up in the next read. }
function TrailingHeaderPrefix(const ABuf: TBytes; ALen: Integer): Integer;
var
  N, I: Integer;
  Ok  : Boolean;
begin
  for N:= Length(LSP_HEADER) - 1 downto 1 do
  begin
    if N > ALen then Continue;
    Ok:= True;
    for I:= 1 to N do
      if UpCase(AnsiChar(ABuf[ALen - N + I - 1])) <> UpCase(AnsiChar(LSP_HEADER[I])) then
      begin
        Ok:= False;
        Break;
      end;
    if Ok then Exit(N);
  end;
  Result:= 0;
end;

{ Offset of the CR LF CR LF that ends the header block, or -1. }
function FindHeaderEnd(const ABuf: TBytes; ALen, AFrom: Integer): Integer;
var
  I: Integer;
begin
  for I:= AFrom to ALen - 4 do
    if (ABuf[I] = 13) and (ABuf[I + 1] = 10) and (ABuf[I + 2] = 13) and (ABuf[I + 3] = 10) then Exit(I);
  Result:= -1;
end;

{ The Content-Length value from a header block known to start at 0, or -1 when
  it cannot be read as a non-negative integer. }
function ParseContentLength(const ABuf: TBytes; AHeaderEnd: Integer): Integer;
var
  I  : Integer;
  Val: Int64;
  Any: Boolean;
begin
  I:= Length(LSP_HEADER);
  while (I < AHeaderEnd) and ((ABuf[I] = 32) or (ABuf[I] = 9)) do Inc(I);
  Val:= 0;
  Any:= False;
  while (I < AHeaderEnd) and (ABuf[I] >= Ord('0')) and (ABuf[I] <= Ord('9')) do
  begin
    Val:= Val * 10 + (ABuf[I] - Ord('0'));
    if Val > MaxInt then Exit(-1);
    Any:= True;
    Inc(I);
  end;
  if not Any then Exit(-1);
  Result:= Integer(Val);
end;

{ Forwards every complete message (and every non-message byte) currently in
  ABuf, and compacts what is left to the front. Returns False if the
  destination closed. ALen is updated to the number of bytes still held. }
var
  GTracePath: string              = '';
  GTraceLock: TRTLCriticalSection;

{ Appends one framed message to the trace, verbatim. NEVER raises: a diagnostic
  that can take the session down is worse than no diagnostic, and this one is
  armed precisely when someone is registering the relay in a live IDE. }
procedure TraceFrame(const ADir: string; const ABuf: TBytes; ACount: Integer);
var
  FS : TFileStream;
  Hdr: TBytes     ;
begin
  if (GTracePath = '') or (ACount <= 0) then Exit;
  EnterCriticalSection(GTraceLock);
  try
    try
      if FileExists(GTracePath) then
        FS:= TFileStream.Create(GTracePath, fmOpenWrite or fmShareDenyNone)
      else
        FS:= TFileStream.Create(GTracePath, fmCreate or fmShareDenyNone);
      try
        FS.Seek(0, soEnd);
        Hdr:= TEncoding.ASCII.GetBytes(Format('%s===== %s %d bytes =====%s',
                                              [sLineBreak, ADir, ACount, sLineBreak]));
        FS.WriteBuffer(Hdr[0], Length(Hdr));
        FS.WriteBuffer(ABuf[0], ACount);
      finally
        FS.Free;
      end;
    except
      { swallowed on purpose -- see the header }
    end;
  finally
    LeaveCriticalSection(GTraceLock);
  end;
end;

function DrainFramed(ADst: THandle; var ABuf: TBytes; var ALen: Integer;
  const ADir: string): Boolean;
var
  Idx      : Integer;
  HeaderEnd: Integer;
  BodyLen  : Integer;
  Total    : Integer;
  Keep     : Integer;
  Emit     : Integer;

  procedure Consume(ACount: Integer);
  begin
    if ACount >= ALen then ALen:= 0
    else
    begin
      Move(ABuf[ACount], ABuf[0], ALen - ACount);
      Dec(ALen, ACount);
    end;
  end;

begin
  Result:= True;
  while ALen > 0 do
  begin
    Idx:= IndexOfHeader(ABuf, ALen, 0);

    if Idx < 0 then
    begin
      { No header in sight. Everything here is pass-through, except a tail that
        might yet become one. }
      Keep:= TrailingHeaderPrefix(ABuf, ALen);
      Emit:= ALen - Keep;
      if Emit <= 0 then Exit;
      if not WriteAll(ADst, ABuf, 0, Emit) then Exit(False);
      Consume(Emit);
      Exit;
    end;

    if Idx > 0 then
    begin
      { Junk before the header: forward it now, unchanged, and re-examine. }
      if not WriteAll(ADst, ABuf, 0, Idx) then Exit(False);
      Consume(Idx);
      Continue;
    end;

    HeaderEnd:= FindHeaderEnd(ABuf, ALen, 0);
    if HeaderEnd < 0 then Exit;   { header still arriving }

    BodyLen:= ParseContentLength(ABuf, HeaderEnd);
    if BodyLen < 0 then
    begin
      { A header we cannot read. Forward it and carry on rather than wait for a
        body whose length is unknown -- stalling here would hang the session on
        a malformed message we were never going to interpret anyway. }
      if not WriteAll(ADst, ABuf, 0, HeaderEnd + 4) then Exit(False);
      Consume(HeaderEnd + 4);
      Continue;
    end;

    Total:= HeaderEnd + 4 + BodyLen;
    if ALen < Total then Exit;    { body still arriving }

    { Traced HERE, on the complete frame, and BEFORE the write -- the recorded
      bytes are exactly the bytes forwarded. }
    TraceFrame(ADir, ABuf, Total);
    if not WriteAll(ADst, ABuf, 0, Total) then Exit(False);
    Consume(Total);
  end;
end;

{ As PumpBytes, but hands on whole LSP messages. See the Task 4 note above for
  why every byte still reaches the far end regardless of framing. }
procedure PumpFramed(ASrc, ADst: THandle; const ADir: string);
var
  Chunk: array[0..PUMP_BUFFER_BYTES - 1] of Byte;
  Acc  : TBytes;
  Len  : Integer;
  Got  : DWORD;
begin
  if (ASrc = 0) or (ASrc = INVALID_HANDLE_VALUE) then Exit;
  if (ADst = 0) or (ADst = INVALID_HANDLE_VALUE) then Exit;
  SetLength(Acc, PUMP_BUFFER_BYTES * 2);
  Len:= 0;
  while True do
  begin
    Got:= 0;
    if not ReadFile(ASrc, Chunk, SizeOf(Chunk), Got, nil) then Break;
    if Got = 0 then Break;
    if Len + Integer(Got) > Length(Acc) then SetLength(Acc, (Len + Integer(Got)) * 2);
    Move(Chunk[0], Acc[Len], Got);
    Inc(Len, Integer(Got));
    if not DrainFramed(ADst, Acc, Len, ADir) then Exit;
  end;
  { EOF. Whatever is still buffered is an incomplete message -- forward it
    anyway. It is the client's data, and a silently swallowed tail is
    indistinguishable from a server that stopped talking. }
  if Len > 0 then WriteAll(ADst, Acc, 0, Len);
end;

constructor TPumpThread.Create(ASrc, ADst: THandle; ACloseSrc, ACloseDst, AFramed: Boolean;
  const ADir: string = '');
begin
  FDir     := ADir;
  FSrc     := ASrc;
  FDst     := ADst;
  FCloseSrc:= ACloseSrc;
  FCloseDst:= ACloseDst;
  FFramed  := AFramed;
  FreeOnTerminate:= True;
  inherited Create(False);
end;

procedure TPumpThread.Execute;
begin
  if FFramed then PumpFramed(FSrc, FDst, FDir) else PumpBytes(FSrc, FDst);
  { Owned handles are closed HERE rather than by the caller, because the caller
    cannot know when this thread stopped touching them. The destination close
    is what forwards end-of-stream to the child. }
  if FCloseDst and (FDst <> 0) then CloseHandle(FDst);
  if FCloseSrc and (FSrc <> 0) then CloseHandle(FSrc);
end;

{ Writes a diagnostic line to the real stderr handle.

  Not Writeln(ErrOutput): this process may be started by a client that gave it
  no console, and the point of these messages is that they survive to whatever
  the client logs. WriteFile on the handle does that and cannot accidentally
  land on stdout. }
procedure StdErrLine(const AText: string);
var
  H  : THandle;
  Raw: RawByteString;
  N  : DWORD;
begin
  H:= GetStdHandle(STD_ERROR_HANDLE);
  if (H = 0) or (H = INVALID_HANDLE_VALUE) then Exit;
  Raw:= RawByteString(AnsiString(AText + sLineBreak));
  if Raw = '' then Exit;
  N:= 0;
  WriteFile(H, Raw[1], Length(Raw), N, nil);
end;

function ResolveDelphiLspPath(const AOverride: string): string;
var
  Reg : TRegistry;
  Root: string;
begin
  if AOverride <> '' then Exit(AOverride);

  Root:= '';
  Reg:= TRegistry.Create(KEY_READ);
  try
    try
      Reg.RootKey:= HKEY_CURRENT_USER;
      if Reg.OpenKeyReadOnly(BDS_REG_KEY) and Reg.ValueExists('RootDir') then
        Root:= Reg.ReadString('RootDir');
    except
      on E: Exception do
      begin
        { A missing or unreadable key is not fatal -- the install path below is
          right on every machine this has ever run on. It is still reported,
          because a SILENT fallback here would present a wrong-Studio DelphiLSP
          as the configured one. }
        Root:= '';
        StdErrLine('drag-lint lsp --proxy: cannot read HKCU\' + BDS_REG_KEY +
                   ' (' + E.ClassName + ': ' + E.Message + '); using the default install path.');
      end;
    end;
  finally
    Reg.Free;
  end;

  if Root = '' then Root:= BDS_FALLBACK;
  Root:= ExcludeTrailingPathDelimiter(Root);

  Result:= Root + '\bin64\DelphiLSP.exe';
  if not FileExists(Result) then Result:= '';
end;

function RunLspProxy(const AOptions: TLspProxyOptions): Integer;
var
  SA         : TSecurityAttributes;
  SI         : TStartupInfo;
  PI         : TProcessInformation;
  ChildInRd  : THandle;   { child's stdin  -- read end,  child keeps }
  ChildInWr  : THandle;   { child's stdin  -- write end, we keep     }
  ChildOutRd : THandle;   { child's stdout -- read end,  we keep     }
  ChildOutWr : THandle;   { child's stdout -- write end, child keeps }
  ChildErrRd : THandle;
  ChildErrWr : THandle;
  Exe        : string;
  CmdLine    : string;
  Code       : DWORD;
begin
  { Armed BEFORE the child is spawned, so the very first frame -- the IDE's
    `initialize`, which carries initializationOptions -- is captured. Empty
    leaves tracing off, which is the default. }
  GTracePath:= AOptions.TraceFile;
  Exe:= ResolveDelphiLspPath(AOptions.DelphiLspExe);
  if Exe = '' then
  begin
    StdErrLine('drag-lint lsp --proxy: DelphiLSP.exe not found. Looked for ' +
               'bin64\DelphiLSP.exe under the RAD Studio 37.0 root (registry ' +
               'HKCU\' + BDS_REG_KEY + ' RootDir, then ' + BDS_FALLBACK + '). ' +
               'Pass --delphi-lsp <path> to override.');
    Exit(EXIT_SPAWN_FAILED);
  end;
  if not FileExists(Exe) then
  begin
    StdErrLine('drag-lint lsp --proxy: --delphi-lsp path does not exist: ' + Exe);
    Exit(EXIT_SPAWN_FAILED);
  end;

  ChildInRd := 0; ChildInWr := 0;
  ChildOutRd:= 0; ChildOutWr:= 0;
  ChildErrRd:= 0; ChildErrWr:= 0;

  FillChar(SA, SizeOf(SA), 0);
  SA.nLength             := SizeOf(SA);
  SA.lpSecurityDescriptor:= nil;
  SA.bInheritHandle      := True;

  { Each pipe is created inheritable, then OUR end is made non-inheritable.
    Skipping that second step is the classic hang: the child inherits a copy of
    the write end of its own stdout, so the pipe never reaches EOF when the
    child exits and the relay waits forever on a dead process. }
  if not CreatePipe(ChildInRd, ChildInWr, @SA, 0) then
  begin
    StdErrLine('drag-lint lsp --proxy: CreatePipe (stdin) failed, error ' + IntToStr(GetLastError));
    Exit(EXIT_SPAWN_FAILED);
  end;
  SetHandleInformation(ChildInWr, HANDLE_FLAG_INHERIT, 0);

  if not CreatePipe(ChildOutRd, ChildOutWr, @SA, 0) then
  begin
    StdErrLine('drag-lint lsp --proxy: CreatePipe (stdout) failed, error ' + IntToStr(GetLastError));
    CloseHandle(ChildInRd); CloseHandle(ChildInWr);
    Exit(EXIT_SPAWN_FAILED);
  end;
  SetHandleInformation(ChildOutRd, HANDLE_FLAG_INHERIT, 0);

  if not CreatePipe(ChildErrRd, ChildErrWr, @SA, 0) then
  begin
    StdErrLine('drag-lint lsp --proxy: CreatePipe (stderr) failed, error ' + IntToStr(GetLastError));
    CloseHandle(ChildInRd ); CloseHandle(ChildInWr );
    CloseHandle(ChildOutRd); CloseHandle(ChildOutWr);
    Exit(EXIT_SPAWN_FAILED);
  end;
  SetHandleInformation(ChildErrRd, HANDLE_FLAG_INHERIT, 0);

  FillChar(SI, SizeOf(SI), 0);
  SI.cb        := SizeOf(SI);
  SI.dwFlags   := STARTF_USESTDHANDLES;
  SI.hStdInput := ChildInRd;
  SI.hStdOutput:= ChildOutWr;
  SI.hStdError := ChildErrWr;

  CmdLine:= '"' + Exe + '"';
  if AOptions.ChildArgs <> '' then CmdLine:= CmdLine + ' ' + AOptions.ChildArgs;

  { CREATE_SUSPENDED so the child is inside the kill-on-close job BEFORE it can
    run a single instruction. DelphiLSP starts helper processes of its own
    (Agent0, Agent1); a child assigned to the job after it has already spawned
    them leaves those grandchildren outside it, and an orphan holding the index
    open is the failure this whole mechanism exists to prevent. }
  FillChar(PI, SizeOf(PI), 0);
  { The command line cannot be a literal: spawning a resolved path IS this
    verb's purpose. It is not attacker-influenced either -- it comes from the
    Studio registry root or from --delphi-lsp on our own command line, and it
    is quoted and passed as lpCommandLine with lpApplicationName nil after
    FileExists has confirmed it. Reviewed, not suppressed. }
  if not CreateProcess(nil, PChar(CmdLine), nil, nil, True,  // dl:ok unsafe-shellexecute@2d6b -- resolved install path, verified with FileExists, not attacker-supplied
                       CREATE_NO_WINDOW or CREATE_SUSPENDED, nil, nil, SI, PI) then
  begin
    StdErrLine('drag-lint lsp --proxy: cannot spawn ' + Exe +
               ' (CreateProcess error ' + IntToStr(GetLastError) + ')');
    CloseHandle(ChildInRd ); CloseHandle(ChildInWr );
    CloseHandle(ChildOutRd); CloseHandle(ChildOutWr);
    CloseHandle(ChildErrRd); CloseHandle(ChildErrWr);
    Exit(EXIT_SPAWN_FAILED);
  end;

  { Criterion 5: the child dies with us even when we are killed outright. This
    process holds the only handle to the job, so TerminateProcess on the relay
    still reaps DelphiLSP -- no cleanup code of ours has to run, which is
    fortunate, because in that case none does. }
  AssignToDragLintJob(PI.hProcess);
  ResumeThread(PI.hThread);

  { The child now owns its ends. Ours must be closed or no EOF ever arrives --
    see the note on inheritance above; this is the other half of the same trap. }
  CloseHandle(ChildInRd );
  CloseHandle(ChildOutWr);
  CloseHandle(ChildErrWr);

  { Each pump owns the handles only it can know are finished with -- see
    TPumpThread. The main thread keeps ChildOutRd and closes it below. }
  { No reference is kept: these are FreeOnTerminate daemons that own their own
    lifetime, and a variable holding a pointer that may already have freed
    itself is a use-after-free waiting to be written. }
  { The two LSP directions are framed; the child's stderr is NOT -- it carries
    log lines, not JSON-RPC, and framing it would hold a partial line back
    exactly when someone is reading the log to find out what went wrong. }
  { ChildInWr and ChildErrRd now belong to those threads, which close them; the
    main thread must not touch either again. ChildOutRd stays ours. }
  TPumpThread.Create(GetStdHandle(STD_INPUT_HANDLE), ChildInWr , False, True , True , 'C>S');
  TPumpThread.Create(ChildErrRd, GetStdHandle(STD_ERROR_HANDLE), True , False, False);
  try
    { Child -> client on THIS thread. When it returns, the child has closed
      stdout, which is the only reliable signal that the session is over: a
      language server that has exited is not coming back, and waiting on the
      client's stdin instead would hang until the IDE happened to type. }
    PumpFramed(ChildOutRd, GetStdHandle(STD_OUTPUT_HANDLE), 'S>C');

    WaitForSingleObject(PI.hProcess, CHILD_REAP_TIMEOUT_MS);
    Code:= 0;
    if not GetExitCodeProcess(PI.hProcess, Code) then Code:= 0;
    if Code = STILL_ACTIVE then
    begin
      { It closed stdout but is still running. Nothing further can be relayed,
        so end the session rather than sit on a half-dead child. }
      TerminateProcess(PI.hProcess, 0);
      Code:= 0;
    end;
    Result:= Integer(Code);
  finally
    if ChildOutRd <> 0 then CloseHandle(ChildOutRd);
    CloseHandle(PI.hThread );
    CloseHandle(PI.hProcess);
  end;
end;

initialization
  InitializeCriticalSection(GTraceLock);

finalization
  DeleteCriticalSection(GTraceLock);

end.
