unit DRagLint.Core.ControlChannel;

{ ---------------------------------------------------------------------------
  THE MAINTENANCE CONTROL CHANNEL -- a documented, local, user-scoped way to
  ask a long-lived engine to stand down.  docs\PLAN-maintenance-shutdown-channel.md

  WHY IT EXISTS
    Staging a new engine, or re-parsing an index, needs the engines that hold
    the file or the database to let go. Every mechanism that existed keyed on
    the OWNER going away: LSP shutdown/exit rides the editor's own stdio and
    only the editor can send it; --parent-pid fires when the spawning IDE
    dies; the Job Object when the parent dies. The maintenance case is the
    owner STAYING while a third process needs the file released. Until this
    unit the only answer was TerminateProcess, which leaves -wal/-shm sidecars
    and in-flight work behind. (`ide-release` is the plugin-side sibling: it
    asks the Delphi IDE plugin not to RESPAWN; it cannot reach an engine VS
    Code spawned, and it frees nothing itself.)

  WHAT IT IS, AND IS NOT
    * A Windows NAMED PIPE, never a TCP port. A loopback listener is reachable
      by every local user and by a browser page (DNS rebinding defeats naive
      Origin checks), and it needs a port that can collide. A pipe is not
      reachable from a browser, needs no port, and carries an ACL.
    * Per user and per session: the name carries the creating user's SID and
      the logon session id, and the pipe is created with an EXPLICIT DACL that
      grants the creating user only. A NULL DACL would grant Everyone. Remote
      clients are rejected at the pipe as well (PIPE_REJECT_REMOTE_CLIENTS).
    * It does ONE thing. Two messages exist -- `status` (describe yourself)
      and `shutdown` (stand down) -- and `status` is there only so a
      maintenance tool can learn which engine holds which database before it
      asks. Nothing here runs a query, reindexes, or takes an argument that
      names work. A control channel that can do arbitrary work is the
      "backdoor" the owner's wording reached for, and is exactly what this is
      not.
    * Every honoured or refused request is audited -- who asked (pid + exe),
      when -- on the engine's stderr (the editor's engine log captures it) and
      in %LOCALAPPDATA%\drag-lint\control-channel-audit.log, beside the
      engine-hold sentinel and for the same reason (TEMP is per-process).

  WHO LISTENS -- ONE gate, ControlChannelEnabledFor, and it is PROVISIONAL.
    See that function.

  WIRE -- one message per connection, UTF-8, TAB-separated, LF-terminated:
    status                   -> status<TAB>pid<TAB>version<TAB>extractor<TAB>db...
    shutdown[<TAB>wait-ms]   -> exiting<TAB>pid<TAB>db...   (stores closed; exit 0 follows)
                             -> busy<TAB>pid<TAB>what       (still running; nothing changed)
    anything else            -> unknown<TAB>pid             (still running; nothing changed)

  HOW THE HOST STANDS DOWN
    The LSP main thread blocks in a synchronous ReadFile on stdin, which only
    the editor writes to. So the listener (1) flags the request, (2) cancels
    the main thread's pending stdin read with CancelSynchronousIo -- ONLY
    while the host says it is inside that read, so an unrelated synchronous
    I/O (a SQLite page read inside a handler) is never the one cancelled --
    and (3) waits, up to the requested deadline, for the host to report that
    it has left its loop AND CLOSED EVERY STORE. Only then is `exiting`
    written, so a tool that reads the reply may proceed at once. If the
    deadline passes first, and no cancel has landed, the request is WITHDRAWN
    atomically, `busy` names the in-flight method, and the host carries on
    untouched. State moves through ONE interlocked word, so the host taking
    the request and the listener withdrawing it cannot both happen.
  --------------------------------------------------------------------------- }

interface

uses
  Winapi.Windows
  , System.SysUtils
  , System.Classes
  , System.SyncObjs
  ;

const
  /// <summary>Leaf prefix of every control pipe: <c>\\.\pipe\drag-lint-ctl-&lt;sid&gt;-s&lt;session&gt;-p&lt;pid&gt;</c>.</summary>
  CONTROL_PIPE_PREFIX     = 'drag-lint-ctl-';
  CONTROL_MSG_STATUS      = 'status';
  CONTROL_MSG_SHUTDOWN    = 'shutdown';
  CONTROL_REPLY_STATUS    = 'status';
  CONTROL_REPLY_EXITING   = 'exiting';
  CONTROL_REPLY_BUSY      = 'busy';
  CONTROL_REPLY_UNKNOWN   = 'unknown';
  /// <summary>Graceful deadline when the request names none, in ms.</summary>
  CONTROL_DEFAULT_WAIT_MS = 5000;
  /// <summary>Upper clamp on any requested deadline, in ms (10 minutes).</summary>
  CONTROL_MAX_WAIT_MS     = 600000;
  /// <summary>PROCESS_QUERY_LIMITED_INFORMATION -- not declared by Winapi.Windows;
  /// the access GetExitCodeProcess / QueryFullProcessImageName need.</summary>
  PROCESS_QUERY_LIMITED_INFORMATION_ACCESS = $1000;

/// <summary>THE ONE GATE: does an engine running <paramref name="ACommand"/>
/// open a control channel?</summary>
/// <param name="ACommand">The CLI verb the engine was started with.</param>
/// <returns>True for <c>lsp</c> only.</returns>
/// <remarks>PROVISIONAL ANSWER to the plan's open owner question (Q1, session
/// 93): honoured by every running engine, or only by one in <c>lsp</c> mode?
/// Taken as <c>lsp</c> only, in the owner's absence, for two reasons: an
/// engine in the middle of an index is the one process a stray message must
/// never stop, and the LSP servers are the processes that actually linger
/// (four were live during session 92-93, one five days old). Narrow is the
/// REVERSIBLE direction -- widening later is additive, narrowing after
/// something shipped is a breaking change. To widen: add the verb here AND
/// start the channel in that verb's dispatch branch the way the <c>lsp</c>
/// branch in DRagLint.CLI does (Create after the stores are open, Run,
/// StandDownComplete after they are closed). Nothing else consults the mode.</remarks>
function ControlChannelEnabledFor(const ACommand: string): Boolean;

/// <summary>The current user's SID as a string (<c>S-1-5-21-...</c>).</summary>
/// <returns>The SID string, or '' when the token cannot be read.</returns>
function CurrentUserSidString: string;

/// <summary>The logon session id of the current process.</summary>
/// <returns>The session id (0 when it cannot be read).</returns>
function CurrentSessionId: Cardinal;

/// <summary>Full pipe name an engine with pid <paramref name="APid"/> of THIS
/// user and session would listen on.</summary>
/// <param name="APid">Process id of the engine.</param>
/// <returns><c>\\.\pipe\drag-lint-ctl-&lt;sid&gt;-s&lt;session&gt;-p&lt;pid&gt;</c>.</returns>
function ControlPipeNameFor(APid: Cardinal): string;

/// <summary>Pid encoded in a control pipe name, or 0 when the name is not one.</summary>
/// <param name="APipeLeaf">The name without the <c>\\.\pipe\</c> prefix.</param>
/// <returns>The pid, or 0.</returns>
function PidFromControlPipeLeaf(const APipeLeaf: string): Cardinal;

/// <summary>Every control pipe currently in the pipe namespace that belongs
/// to THIS user and session.</summary>
/// <returns>Full pipe names. A pipe disappears with its process, so this is
/// also the live instance list -- no registry file to go stale.</returns>
function ListControlPipesForThisUser: TArray<string>;

/// <summary>Sends ONE message to a control pipe and reads its one-line reply.</summary>
/// <param name="APipeName">Full pipe name.</param>
/// <param name="AMessage">The message without its LF terminator.</param>
/// <param name="AConnectTimeoutMs">How long to wait for a free pipe instance.</param>
/// <param name="AReply">The reply with its terminator stripped; '' on failure.</param>
/// <param name="AError">Why it failed; '' on success.</param>
/// <returns>True when a reply was read.</returns>
/// <remarks>The read blocks until the engine replies; for <c>shutdown</c>
/// that is bounded by the wait-ms the message itself carries.</remarks>
function ControlRequest(const APipeName, AMessage: string; AConnectTimeoutMs: Integer; out AReply, AError: string): Boolean;

/// <summary>Where honoured and refused requests are appended.</summary>
/// <returns><c>%LOCALAPPDATA%\drag-lint\control-channel-audit.log</c>.</returns>
function ControlAuditLogPath: string;

type
  /// <summary>The engine side of the channel: one listener thread on the
  /// per-user pipe, and the hooks the host loop uses to cooperate.</summary>
  /// <remarks>
  /// <para>Create and Start on the MAIN thread (the one that blocks in the
  /// stdin read) -- Start duplicates the calling thread's handle so the
  /// listener can cancel that read. Create raises otherwise.</para>
  /// <para>Host contract: bracket the blocking read with EnterRead/LeaveRead,
  /// bracket each request with BeginWork/EndWork, test StandDownRequested at
  /// the top of the loop, and call StandDownComplete AFTER every store is
  /// closed -- the `exiting` reply is withheld until then. Then Free.</para>
  /// <para>Thread-safety: the host hooks are interlocked; the listener owns
  /// the pipe handles exclusively.</para>
  /// </remarks>
  TControlChannel = class
    private
      const
        ST_IDLE      = 0;
        ST_REQUESTED = 1;
        ST_TAKEN     = 2;
      var
        FDbs        : TArray<string>;
        FVersion    : string        ;
        FExtractor  : string        ;
        FPipeName   : string        ;
        FOwnerSid   : string        ;
        FSD         : Pointer       ; { self-relative SECURITY_DESCRIPTOR from SDDL; LocalFree'd }
        FSA         : TSecurityAttributes;
        FMainThread : THandle       ;
        FListener   : TThread       ;
        FFirstPipe  : THandle       ;
        FState      : Integer       ; { ST_* -- one interlocked word }
        FInRead     : Integer       ; { 1 while the host is inside its stdin read }
        FWorkLock   : TCriticalSection;
        FWork       : string        ;
        FDone       : TEvent        ; { StandDownComplete }
        FReplied    : TEvent        ; { the listener wrote its final reply }
      function CreatePipeInstance(out AError: string): THandle;
      function CurrentWork: string;
    public
      /// <summary>Prepares a channel describing the stores <paramref name="ADbs"/>.
      /// Nothing listens until Start.</summary>
      /// <param name="ADbs">Databases the engine holds -- what `status` reports.</param>
      /// <param name="AVersion">DRAGLINT_VERSION.</param>
      /// <param name="AExtractor">DRAGLINT_EXTRACTOR_VERSION.</param>
      /// <exception cref="EInvalidOperation">Not called on the main thread.</exception>
      constructor Create(const ADbs: TArray<string>; const AVersion, AExtractor: string);
      /// <summary>Stops the listener (bounded wait) and releases the pipe.</summary>
      destructor Destroy; override;
      /// <summary>Builds the DACL, creates the first pipe instance and starts
      /// the listener. Synchronous, so the pipe exists before this returns.</summary>
      /// <param name="AError">Why it could not listen; '' on success.</param>
      /// <returns>True when listening.</returns>
      function Start(out AError: string): Boolean;
      /// <summary>Full name of the pipe this engine listens on.</summary>
      property PipeName: string read FPipeName;
      /// <summary>SID string the DACL grants -- the only trustee.</summary>
      property OwnerSid: string read FOwnerSid;
      /// <summary>Host hook: True exactly once, when a stand-down request is
      /// pending; taking it commits the host to exiting.</summary>
      /// <returns>True when the host must leave its loop.</returns>
      function StandDownRequested: Boolean;
      /// <summary>Host hook: the host is about to block in its stdin read.</summary>
      procedure EnterRead;
      /// <summary>Host hook: the stdin read returned.</summary>
      procedure LeaveRead;
      /// <summary>Host hook: a request is being handled (named in a `busy` reply).</summary>
      /// <param name="AWhat">The method name.</param>
      procedure BeginWork(const AWhat: string);
      /// <summary>Host hook: the request is done.</summary>
      procedure EndWork;
      /// <summary>Host hook: every store is closed; the `exiting` reply may go.</summary>
      procedure StandDownComplete;
  end;

implementation

uses
  System.IOUtils
  , System.DateUtils
  ;

type
  TControlListener = class(TThread)
    private
      FOwner: TControlChannel;
      procedure AcceptAndServe(APipe: THandle);
      procedure Serve(APipe: THandle);
      procedure ServeStandDown(APipe: THandle; AWaitMs: Integer);
      procedure Reply(APipe: THandle; const ALine: string);
      function RequesterText(APipe: THandle): string;
    protected
      procedure Execute; override;
    public
      constructor Create(AOwner: TControlChannel);
  end;

const
  MAX_MSG                          = 4096;
  CC_IO_BUF_BYTES                  = 512;   { one ReadFile chunk; a message is a few hundred bytes }
  CC_POLL_MS                       = 25;    { listener's wait slice between cancel attempts }
  CC_STORE_CLOSE_GRACE_MS          = 60000; { after the read is cancelled, how long the host may take to close stores }
  CC_RETRY_MS                      = 200;   { back-off when CreateNamedPipe transiently fails }
  CC_WAKE_PIPE_MS                  = 100;   { teardown: WaitNamedPipe for the throwaway wake-up client }
  CC_WAKE_POLL_MS                  = 150;   { teardown: per-attempt wait for the listener to notice Terminated }
  CC_REPLY_JOIN_MS                 = 5000;  { teardown while a reply is being written: let it finish }
  CC_LISTENER_JOIN_MS              = 3000;  { teardown: bounded final join, then detach (never freeze exit) }
  CC_WAKE_ATTEMPTS                 = 10;
  CC_LF                            = 10;    { the one-line wire terminator }
  CC_NO_WAIT_MS                    = 0;     { TEvent.WaitFor poll: is it signalled right now }
  MS_PER_SECOND                    = 1000;
  PIPE_PREFIX_FULL                 = '\\.\pipe\';
  CC_FILE_FLAG_FIRST_PIPE_INSTANCE = $00080000;
  CC_PIPE_REJECT_REMOTE_CLIENTS    = $00000008;
  CC_SDDL_REVISION_1               = 1;
  CC_THREAD_TERMINATE              = $0001; { the access CancelSynchronousIo needs on the thread handle }
  AUDIT_DIR_NAME                   = 'drag-lint';
  AUDIT_FILE_NAME                  = 'control-channel-audit.log';

{ Not in Winapi.Windows (checked against the RTL source, not assumed). }
function ConvertStringSecurityDescriptorToSecurityDescriptorW(StringSecurityDescriptor: LPCWSTR; StringSDRevision: DWORD;
  var SecurityDescriptor: Pointer; SecurityDescriptorSize: PULONG): BOOL; stdcall; external advapi32;
function QueryFullProcessImageNameW(hProcess: THandle; dwFlags: DWORD; lpExeName: LPWSTR; var lpdwSize: DWORD): BOOL; stdcall; external kernel32;

{ ---- gate ---------------------------------------------------------------- }

function ControlChannelEnabledFor(const ACommand: string): Boolean;
begin
  { PROVISIONAL -- see the interface remarks. `lsp` only. }
  Result:= SameText(ACommand, 'lsp');
end;

{ ---- identity ------------------------------------------------------------ }

function CurrentUserSidString: string;
var
  Token  : THandle    ;
  Needed : DWORD      ;
  Buf    : TBytes     ;
  SidStr : LPWSTR     ;
begin
  Result:= '';
  if not OpenProcessToken(GetCurrentProcess, TOKEN_QUERY, Token) then Exit;
  try
    Needed:= 0;
    GetTokenInformation(Token, TokenUser, nil, 0, Needed);
    if Needed = 0 then Exit;
    SetLength(Buf, Needed);
    if not GetTokenInformation(Token, TokenUser, @Buf[0], Needed, Needed) then Exit;
    if ConvertSidToStringSidW(PTokenUser(@Buf[0])^.User.Sid, SidStr) then
    begin
      try
        Result:= SidStr;
      finally
        LocalFree(HLOCAL(SidStr));
      end;
    end;
  finally
    CloseHandle(Token);
  end;
end;

function CurrentSessionId: Cardinal;
var
  S: DWORD;
begin
  S:= 0;
  if not ProcessIdToSessionId(GetCurrentProcessId, S) then S:= 0;
  Result:= S;
end;

function ControlPipeLeafFor(APid: Cardinal): string;
begin
  Result:= CONTROL_PIPE_PREFIX + CurrentUserSidString + '-s' + IntToStr(CurrentSessionId) + '-p' + IntToStr(APid);
end;

function ControlPipeNameFor(APid: Cardinal): string;
begin
  Result:= PIPE_PREFIX_FULL + ControlPipeLeafFor(APid);
end;

function PidFromControlPipeLeaf(const APipeLeaf: string): Cardinal;
var
  P: Integer;
begin
  Result:= 0;
  if not APipeLeaf.StartsWith(CONTROL_PIPE_PREFIX, True) then Exit;
  P:= APipeLeaf.LastIndexOf('-p');
  if P < 0 then Exit;
  Result:= StrToIntDef(APipeLeaf.Substring(P + 2), 0);
end;

function ListControlPipesForThisUser: TArray<string>;
var
  Mine  : string          ;
  H     : THandle         ;
  Found : TWin32FindDataW ;
  Leaf  : string          ;
begin
  SetLength(Result, 0);
  { Everything up to the pid: the SID and the session are ours by construction,
    so another user's or another session's engines are never even listed. }
  Mine:= CONTROL_PIPE_PREFIX + CurrentUserSidString + '-s' + IntToStr(CurrentSessionId) + '-p';
  H:= FindFirstFileW(PIPE_PREFIX_FULL + '*', Found);
  if H = INVALID_HANDLE_VALUE then Exit;
  try
    repeat
      Leaf:= Found.cFileName;
      if Leaf.StartsWith(Mine, True) and (PidFromControlPipeLeaf(Leaf) > 0) then
      begin
        SetLength(Result, Length(Result) + 1);
        Result[High(Result)]:= PIPE_PREFIX_FULL + Leaf;
      end;
    until not FindNextFileW(H, Found);
  finally
    Winapi.Windows.FindClose(H);
  end;
end;

function ControlAuditLogPath: string;
var
  Base: string;
begin
  { Mirrors DRagLint.Core.EngineHold: LOCALAPPDATA is the one per-user place a
    shell, an editor and the IDE agree on; TEMP is per-process. }
  Base:= GetEnvironmentVariable('LOCALAPPDATA');
  if Base = '' then Base:= TPath.GetCachePath;
  if Base = '' then Base:= TPath.GetTempPath;
  Result:= TPath.Combine(TPath.Combine(Base, AUDIT_DIR_NAME), AUDIT_FILE_NAME);
end;

{ ---- wire ---------------------------------------------------------------- }

{ Reads ONE LF-terminated line from a pipe handle (either end uses it). Stops
  at the terminator, at EOF / a broken pipe, or at MAX_MSG bytes. }
function ReadLineFromPipe(AHandle: THandle): TBytes;
var
  Buf : array[0..CC_IO_BUF_BYTES - 1] of Byte;
  Got : DWORD  ;
  I   : Integer;
  Term: Boolean;
begin
  SetLength(Result, 0);
  Term:= False;
  while (not Term) and (Length(Result) < MAX_MSG) do
  begin
    Got:= 0;
    if not ReadFile(AHandle, Buf[0], Length(Buf), Got, nil) then Break;  // dl:ok used-before-assignment@c7b1
    if Got = 0 then Break;
    I:= Length(Result);
    SetLength(Result, I + Integer(Got));
    Move(Buf[0], Result[I], Got);
    Term:= Buf[Got - 1] = CC_LF;
  end;
end;

{ ---- client -------------------------------------------------------------- }

function ControlRequest(const APipeName, AMessage: string; AConnectTimeoutMs: Integer; out AReply, AError: string): Boolean;
var
  H      : THandle;
  Bytes  : TBytes ;
  Written: DWORD  ;
  Acc    : TBytes ;
begin
  Result:= False;
  AReply:= '';
  AError:= '';
  if not WaitNamedPipeW(PChar(APipeName), Cardinal(AConnectTimeoutMs)) then
  begin
    AError:= 'no free pipe instance within ' + IntToStr(AConnectTimeoutMs) + ' ms (' + SysErrorMessage(GetLastError) + ')';
    Exit;
  end;
  H:= CreateFileW(PChar(APipeName), GENERIC_READ or GENERIC_WRITE, 0, nil, OPEN_EXISTING, 0, 0);
  if H = INVALID_HANDLE_VALUE then
  begin
    AError:= 'could not open the pipe: ' + SysErrorMessage(GetLastError);
    Exit;
  end;
  try
    Bytes:= TEncoding.UTF8.GetBytes(AMessage + #10);
    if not WriteFile(H, Bytes[0], Length(Bytes), Written, nil) then
    begin
      AError:= 'write failed: ' + SysErrorMessage(GetLastError);
      Exit;
    end;
    Acc:= ReadLineFromPipe(H);
    if Length(Acc) = 0 then
    begin
      AError:= 'no reply (the engine closed the pipe)';
      Exit;
    end;
    AReply:= TEncoding.UTF8.GetString(Acc).TrimRight([#13, #10]);
    Result:= True;
  finally
    CloseHandle(H);
  end;
end;

{ ---- audit --------------------------------------------------------------- }

function NowIso: string;
begin
  Result:= FormatDateTime('yyyy-mm-dd"T"hh:nn:ss"Z"', TTimeZone.Local.ToUniversalTime(Now));
end;

{ ONE WriteFile per line, straight to the stderr handle: the listener runs on
  its own thread and Delphi's ErrOutput text file is not thread-safe. }
procedure StderrLine(const S: string);
var
  B      : TBytes;
  Written: DWORD ;
  H      : THandle;
begin
  H:= GetStdHandle(STD_ERROR_HANDLE);
  if (H = 0) or (H = INVALID_HANDLE_VALUE) then Exit;
  B:= TEncoding.UTF8.GetBytes(S + sLineBreak);
  WriteFile(H, B[0], Length(B), Written, nil);
end;

procedure Audit(const ALine: string);
var
  P: string;
begin
  StderrLine('drag-lint LSP: control channel: ' + ALine);
  try
    P:= ControlAuditLogPath;
    TDirectory.CreateDirectory(ExtractFileDir(P));
    { The file is shared by every engine of this user: each line names its writer. }
    TFile.AppendAllText(P, 'engine pid ' + IntToStr(GetCurrentProcessId) + ': ' + ALine + sLineBreak, TEncoding.ASCII);
  except
    { best effort: the stderr line above is the record that always exists }
  end;
end;

{ ---- TControlChannel ----------------------------------------------------- }

constructor TControlChannel.Create(const ADbs: TArray<string>; const AVersion, AExtractor: string);
begin
  inherited Create;
  if GetCurrentThreadId <> MainThreadID then
    raise EInvalidOperation.Create('TControlChannel must be created on the main thread -- the one the listener has to wake');
  FDbs      := Copy(ADbs);
  FVersion  := AVersion;
  FExtractor:= AExtractor;
  FState    := ST_IDLE;
  FInRead   := 0;
  FFirstPipe:= INVALID_HANDLE_VALUE;
  FWorkLock := TCriticalSection.Create;
  FDone     := TEvent.Create(nil, {ManualReset=}True, False, '');
  FReplied  := TEvent.Create(nil, {ManualReset=}True, False, '');
  FOwnerSid := CurrentUserSidString;
  FPipeName := ControlPipeNameFor(GetCurrentProcessId);
end;

destructor TControlChannel.Destroy;
var
  H: THandle;
  I: Integer;
begin
  if FListener <> nil then
  begin
    FListener.Terminate;
    if InterlockedCompareExchange(FState, ST_TAKEN, ST_TAKEN) = ST_TAKEN then
      { a request is being honoured: the listener is writing `exiting`; let it }
      FReplied.WaitFor(CC_REPLY_JOIN_MS)
    else
    begin
      { Wake it out of ConnectNamedPipe with a throwaway client (the
        OpenSourceServer teardown, which is the one that does not freeze). }
      for I:= 1 to CC_WAKE_ATTEMPTS do
      begin
        if WaitForSingleObject(FListener.Handle, 0) = WAIT_OBJECT_0 then Break;
        if WaitNamedPipeW(PChar(FPipeName), CC_WAKE_PIPE_MS) then
        begin
          H:= CreateFileW(PChar(FPipeName), GENERIC_READ or GENERIC_WRITE, 0, nil, OPEN_EXISTING, 0, 0);
          if H <> INVALID_HANDLE_VALUE then CloseHandle(H);
        end;
        if WaitForSingleObject(FListener.Handle, CC_WAKE_POLL_MS) = WAIT_OBJECT_0 then Break;
      end;
    end;
    if WaitForSingleObject(FListener.Handle, CC_LISTENER_JOIN_MS) = WAIT_OBJECT_0 then FreeAndNil(FListener)
    else
    begin
      { never block process exit on a stuck listener -- detach, as the IDE server does }
      FListener.FreeOnTerminate:= True;
      FListener:= nil;
    end;
  end;
  if FFirstPipe <> INVALID_HANDLE_VALUE then CloseHandle(FFirstPipe);
  if FMainThread <> 0 then CloseHandle(FMainThread);
  if FSD <> nil then LocalFree(HLOCAL(FSD));
  FReplied.Free;
  FDone.Free;
  FWorkLock.Free;
  inherited Destroy;
end;

function TControlChannel.CreatePipeInstance(out AError: string): THandle;
begin
  AError:= '';
  { ONE instance, first-instance-only: a second creator of this name -- which
    carries our own pid, so it could only be deliberate -- makes OUR create
    fail rather than silently sharing the name with a squatter. }
  Result:= CreateNamedPipeW(PChar(FPipeName),
    PIPE_ACCESS_DUPLEX or CC_FILE_FLAG_FIRST_PIPE_INSTANCE,
    PIPE_TYPE_BYTE or PIPE_READMODE_BYTE or PIPE_WAIT or CC_PIPE_REJECT_REMOTE_CLIENTS,
    1, MAX_MSG, MAX_MSG, 0, @FSA);
  if Result = INVALID_HANDLE_VALUE then AError:= SysErrorMessage(GetLastError);
end;

function TControlChannel.Start(out AError: string): Boolean;
var
  Sddl: string;
begin
  Result:= False;
  AError:= '';
  if FOwnerSid = '' then
  begin
    AError:= 'cannot read the current user''s SID; refusing to listen with a weaker DACL';
    Exit;
  end;
  { EXPLICIT DACL, creating user only. P = protected (no inherited ACEs),
    A = allow, GA = generic all. Never nil (NULL DACL = Everyone). }
  Sddl:= 'D:P(A;;GA;;;' + FOwnerSid + ')';
  if not ConvertStringSecurityDescriptorToSecurityDescriptorW(PChar(Sddl), CC_SDDL_REVISION_1, FSD, nil) then
  begin
    AError:= 'security descriptor: ' + SysErrorMessage(GetLastError);
    Exit;
  end;
  FSA.nLength             := SizeOf(FSA);
  FSA.lpSecurityDescriptor:= FSD;
  FSA.bInheritHandle      := False;
  if not DuplicateHandle(GetCurrentProcess, GetCurrentThread, GetCurrentProcess, @FMainThread, CC_THREAD_TERMINATE, False, 0) then
  begin
    AError:= 'main thread handle: ' + SysErrorMessage(GetLastError);
    Exit;
  end;
  FFirstPipe:= CreatePipeInstance(AError);
  if FFirstPipe = INVALID_HANDLE_VALUE then
  begin
    AError:= 'CreateNamedPipe ' + FPipeName + ': ' + AError;
    Exit;
  end;
  FListener:= TControlListener.Create(Self);
  Result:= True;
end;

function TControlChannel.StandDownRequested: Boolean;
begin
  Result:= InterlockedCompareExchange(FState, ST_TAKEN, ST_REQUESTED) = ST_REQUESTED;
end;

procedure TControlChannel.EnterRead;
begin
  InterlockedExchange(FInRead, 1);
end;

procedure TControlChannel.LeaveRead;
begin
  InterlockedExchange(FInRead, 0);
end;

procedure TControlChannel.BeginWork(const AWhat: string);
begin
  FWorkLock.Enter;
  try
    FWork:= AWhat;
  finally
    FWorkLock.Leave;
  end;
end;

procedure TControlChannel.EndWork;
begin
  BeginWork('');
end;

function TControlChannel.CurrentWork: string;
begin
  FWorkLock.Enter;
  try
    Result:= FWork;
  finally
    FWorkLock.Leave;
  end;
end;

procedure TControlChannel.StandDownComplete;
begin
  { The host left its loop because the cancelled read returned nil, or because
    it took the request explicitly; either way the request is now TAKEN. }
  InterlockedCompareExchange(FState, ST_TAKEN, ST_REQUESTED);
  FDone.SetEvent;
end;

{ ---- TControlListener ---------------------------------------------------- }

constructor TControlListener.Create(AOwner: TControlChannel);
begin
  FOwner:= AOwner;
  FreeOnTerminate:= False;
  inherited Create(False);
end;

procedure TControlListener.Reply(APipe: THandle; const ALine: string);
var
  B      : TBytes;
  Written: DWORD ;
begin
  B:= TEncoding.UTF8.GetBytes(ALine + #10);
  if WriteFile(APipe, B[0], Length(B), Written, nil) then FlushFileBuffers(APipe);
end;

function TControlListener.RequesterText(APipe: THandle): string;
var
  Pid : ULONG                     ;
  H   : THandle                   ;
  Name: array[0..MAX_PATH] of Char;
  Len : DWORD                     ;
begin
  Result:= 'pid ? (unknown)';
  Pid:= 0;
  if not GetNamedPipeClientProcessId(APipe, Pid) then Exit;
  Result:= 'pid ' + IntToStr(Pid) + ' (unknown exe)';
  H:= OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION_ACCESS, False, Pid);
  if H = 0 then Exit;
  try
    Len:= Length(Name);
    if QueryFullProcessImageNameW(H, 0, @Name[0], Len) then Result:= 'pid ' + IntToStr(Pid) + ' (' + string(PChar(@Name[0])) + ')';
  finally
    CloseHandle(H);
  end;
end;

procedure TControlListener.Serve(APipe: THandle);
var
  Acc     : TBytes               ;
  Fields  : TArray<string>       ;
  Verb    : string               ;
  Pid     : string               ;
  Line    : string               ;
  WaitMs  : Integer              ;
  D       : string               ;
begin
  Acc:= ReadLineFromPipe(APipe);
  if Length(Acc) = 0 then Exit; { the teardown wake-up, or a client that said nothing }
  Fields:= TEncoding.UTF8.GetString(Acc).TrimRight([#13, #10]).Split([#9]);
  Verb:= '';
  if Length(Fields) > 0 then Verb:= Trim(Fields[0]);
  Pid:= IntToStr(GetCurrentProcessId);

  if SameText(Verb, CONTROL_MSG_STATUS) then
  begin
    Line:= CONTROL_REPLY_STATUS + #9 + Pid + #9 + FOwner.FVersion + #9 + FOwner.FExtractor;
    for D in FOwner.FDbs do Line:= Line + #9 + D;
    Reply(APipe, Line);
  end
  else if SameText(Verb, CONTROL_MSG_SHUTDOWN) then
  begin
    WaitMs:= CONTROL_DEFAULT_WAIT_MS;
    if Length(Fields) > 1 then WaitMs:= StrToIntDef(Trim(Fields[1]), CONTROL_DEFAULT_WAIT_MS);
    if WaitMs < 0 then WaitMs:= 0;
    if WaitMs > CONTROL_MAX_WAIT_MS then WaitMs:= CONTROL_MAX_WAIT_MS;
    ServeStandDown(APipe, WaitMs);
  end
  else
    { ONE thing. Anything else is answered and changes nothing. }
    Reply(APipe, CONTROL_REPLY_UNKNOWN + #9 + Pid);
end;

procedure TControlListener.ServeStandDown(APipe: THandle; AWaitMs: Integer);
var
  Pid      : string ;
  Line     : string ;
  Started  : UInt64 ;
  Cancelled: Boolean;
  Who      : string ;
  D        : string ;
begin
  Pid:= IntToStr(GetCurrentProcessId);
  Who:= RequesterText(APipe);

  if InterlockedCompareExchange(FOwner.FState, TControlChannel.ST_REQUESTED, TControlChannel.ST_IDLE) <> TControlChannel.ST_IDLE then
  begin
    { a stand-down is already in flight -- report the same answer it will get }
    if FOwner.FDone.WaitFor(AWaitMs) = wrSignaled then Reply(APipe, CONTROL_REPLY_EXITING + #9 + Pid)
    else Reply(APipe, CONTROL_REPLY_BUSY + #9 + Pid + #9 + 'a stand-down is already in progress');
    Exit;
  end;

  Started  := GetTickCount64;
  Cancelled:= False;
  repeat
    { Cancel the host's stdin read -- and ONLY that read: never while it is
      inside a handler, where the synchronous I/O in flight would be SQLite's. }
    if (not Cancelled) and (InterlockedCompareExchange(FOwner.FInRead, 1, 1) = 1) then
      if CancelSynchronousIo(FOwner.FMainThread) then Cancelled:= True;
    if FOwner.FDone.WaitFor(CC_POLL_MS) = wrSignaled then Break;
  until (GetTickCount64 - Started >= UInt64(AWaitMs)) and (not Cancelled);

  if FOwner.FDone.WaitFor(CC_NO_WAIT_MS) <> wrSignaled then
  begin
    if Cancelled then
    begin
      { the read is gone, so the host IS leaving: wait for the stores to close }
      if FOwner.FDone.WaitFor(CC_STORE_CLOSE_GRACE_MS) <> wrSignaled then
      begin
        Audit('shutdown asked by ' + Who + ' at ' + NowIso + ' -- read cancelled but the host has not closed its stores after '
          + IntToStr(CC_STORE_CLOSE_GRACE_MS div MS_PER_SECOND) + ' s');
        Reply(APipe, CONTROL_REPLY_BUSY + #9 + Pid + #9 + 'stand-down started but not finished');
        Exit;
      end;
    end
    else if InterlockedCompareExchange(FOwner.FState, TControlChannel.ST_IDLE, TControlChannel.ST_REQUESTED) = TControlChannel.ST_REQUESTED then
    begin
      { WITHDRAWN atomically: the host never took it, nothing changed }
      Line:= FOwner.CurrentWork;
      if Line = '' then Line:= 'not idle';
      Audit('shutdown REFUSED at ' + NowIso + ' -- busy with ' + Line + '; asked by ' + Who + '; deadline ' + IntToStr(AWaitMs) + ' ms');
      Reply(APipe, CONTROL_REPLY_BUSY + #9 + Pid + #9 + Line);
      Exit;
    end
    else
      { the host took it in the same instant: it is exiting, wait for the stores }
      FOwner.FDone.WaitFor(CC_STORE_CLOSE_GRACE_MS);
  end;

  Line:= CONTROL_REPLY_EXITING + #9 + Pid;
  for D in FOwner.FDbs do Line:= Line + #9 + D;
  Audit('shutdown honoured at ' + NowIso + ' -- asked by ' + Who + '; closed ' + IntToStr(Length(FOwner.FDbs)) + ' store(s), exiting 0');
  Reply(APipe, Line);
  FOwner.FReplied.SetEvent;
  Terminate;
end;

procedure TControlListener.AcceptAndServe(APipe: THandle);
var
  Connected: Boolean;
begin
  try
    { Blocks until a client connects -- a tool, or the teardown's throwaway
      wake-up, which Serve then reads as an empty message and ignores. }
    Connected:= ConnectNamedPipe(APipe, nil) or (GetLastError = ERROR_PIPE_CONNECTED);
    if Connected and not Terminated then Serve(APipe);
  finally
    DisconnectNamedPipe(APipe);
    CloseHandle(APipe);
  end;
end;

procedure TControlListener.Execute;
var
  Pipe: THandle;
  Err : string ;
begin
  NameThreadForDebugging('drag-lint control channel');
  { The first instance was created synchronously by Start, so the pipe already
    existed when the engine announced it. Every later instance is ours to make. }
  Pipe:= FOwner.FFirstPipe;
  FOwner.FFirstPipe:= INVALID_HANDLE_VALUE;
  if (Pipe <> INVALID_HANDLE_VALUE) and not Terminated then AcceptAndServe(Pipe);
  while not Terminated do
  begin
    Pipe:= FOwner.CreatePipeInstance(Err);
    if Pipe = INVALID_HANDLE_VALUE then Sleep(CC_RETRY_MS) { transient; the name is ours, retry }
    else AcceptAndServe(Pipe);
  end;
end;

end.
