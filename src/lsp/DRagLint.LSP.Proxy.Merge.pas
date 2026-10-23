unit DRagLint.LSP.Proxy.Merge;

{ Merge plan P0 -- the interception seam of the LSP merge proxy.

  The relay in DRagLint.LSP.Proxy hands every COMPLETE frame to an optional
  interceptor before forwarding it. This unit provides that interceptor's
  types, the frame helpers the merge handlers will share, and the engine that
  owns the merge state (the lazily-opened index, the single worker thread that
  enforces a per-frame time budget).

  P0 SHIPS THE SEAM, NOT A MERGE. TProxyMergeEngine.Intercept answers False for
  every frame, so a proxy started with a --merge-* flag relays exactly what the
  plain relay relays. The handlers (diagnostics, completion, hover, definition)
  arrive in later tasks, each behind its own guard.

  FAIL OPEN, ALWAYS. A handler that raises, overruns its budget or cannot open
  the index makes the relay forward DelphiLSP's original bytes. The engine
  never decides on its own to drop a frame. }

interface

uses
    System.SysUtils
  , System.Classes
  , System.SyncObjs
  , DRagLint.LSP.Proxy  // dl:ok circular-uses@a9ed -- implementation-only cycle forced by the P0 contract: Merge takes TLspProxyOptions, Proxy installs the engine
  , DRagLint.LSP.Server
  ;

type
  /// <summary>Which way a frame is travelling through the proxy.</summary>
  TMergeDirection = (mdClientToServer, mdServerToClient);

  /// <summary>Called by the relay with every complete LSP frame (headers and
  /// body) before it is forwarded.</summary>
  /// <param name="ADir">Direction of the frame.</param>
  /// <param name="AFrame">Buffer holding the frame at offset 0; it may be
  /// longer than the frame.</param>
  /// <param name="ALen">Byte length of the frame in AFrame.</param>
  /// <param name="AReplacement">The bytes to forward instead, when the result
  /// is True. A replacement must itself be a complete frame.</param>
  /// <returns>True to substitute AReplacement; False (or any exception) means
  /// forward the original bytes unchanged.</returns>
  TFrameInterceptor = reference to function(ADir: TMergeDirection; const AFrame: TBytes;
    ALen: Integer; out AReplacement: TBytes): Boolean;

  /// <summary>Owns the merge state of one proxy process: the options, the
  /// lazily-created drag-lint LSP server over the index, and the single merge
  /// worker thread.</summary>
  /// <remarks>
  /// Created by RunLspProxy ONLY when a Merge* option is on; with every merge
  /// flag off nothing of this class is constructed (criterion 19).
  /// <para>Lifetime: one per proxy process, never freed by the relay. The
  /// relay's pump threads are unjoined daemons (see TPumpThread) and may still
  /// be inside Intercept when RunLspProxy returns, so the engine lives until
  /// process exit.</para>
  /// <para>Thread-safety: Intercept and RunWithinBudget are called from both
  /// pump threads concurrently; Server and RunWithinBudget serialise
  /// internally.</para>
  /// </remarks>
  TProxyMergeEngine = class
  private
    FOptions    : TLspProxyOptions;
    FServer     : TLSPServer;
    FServerTried: Boolean;
    FServerLock : TCriticalSection;
    FCallLock   : TCriticalSection;
    FStateLock  : TCriticalSection;
    FJobReady   : TEvent;
    FJobDone    : TEvent;
    FJob        : TProc;
    FBusy       : Boolean;
    FJobFailed  : Boolean;
    FWorker     : TThread;
    procedure WorkerLoop;
  public
    /// <summary>Copies the options and starts the merge worker thread.</summary>
    /// <param name="AOptions">The proxy options; Merge*, MergeBudgetMs and
    /// DbPaths are the fields this class reads.</param>
    constructor Create(const AOptions: TLspProxyOptions);
    /// <summary>Stops the worker (waiting for a running job) and frees the
    /// server.</summary>
    destructor Destroy; override;
    /// <summary>The relay's interceptor for this engine.</summary>
    /// <param name="ADir">Direction of the frame.</param>
    /// <param name="AFrame">Buffer holding the frame at offset 0.</param>
    /// <param name="ALen">Byte length of the frame.</param>
    /// <param name="AReplacement">Replacement frame when the result is True.</param>
    /// <returns>False for every frame in P0 -- the relay forwards the
    /// original bytes; handlers arrive in later tasks.</returns>
    function Intercept(ADir: TMergeDirection; const AFrame: TBytes; ALen: Integer;
      out AReplacement: TBytes): Boolean;
    /// <summary>Runs AWork on the single merge worker thread and waits at most
    /// ABudgetMs for it.</summary>
    /// <param name="AWork">The work; it must publish its result only through
    /// state the caller reads after a True return.</param>
    /// <param name="ABudgetMs">Wait budget in milliseconds; 0 waits not at
    /// all.</param>
    /// <returns>True when AWork finished, without raising, within the budget.
    /// False when it overran (its late result is to be discarded), raised, or
    /// could not start because a previous over-budget job still occupies the
    /// worker.</returns>
    /// <remarks>Callers are serialised. A job that overruns keeps running to
    /// completion on the worker; it is never killed.</remarks>
    function RunWithinBudget(const AWork: TProc; ABudgetMs: Integer): Boolean;
    /// <summary>The drag-lint LSP server over Options.DbPaths, created on first
    /// use.</summary>
    /// <returns>The server, or nil when it could not be created; the failure is
    /// reported once on stderr and never retried (fail-open).</returns>
    function Server: TLSPServer;
    /// <summary>The options this engine was created with.</summary>
    property Options: TLspProxyOptions read FOptions;
  end;

/// <summary>The body of a complete LSP frame, decoded as UTF-8.</summary>
/// <param name="AFrame">Buffer holding the frame at offset 0.</param>
/// <param name="ALen">Byte length of the frame in AFrame.</param>
/// <returns>The text after the blank line that ends the headers; an empty
/// string when no header terminator lies within ALen.</returns>
function FrameBody(const AFrame: TBytes; ALen: Integer): string;  // dl:ok unused-public-symbol@a220 -- shared frame helper of the merge handlers (A1/A3/A4/A5); P0 ships the seam only

/// <summary>Frames a UTF-8 body as one LSP message.</summary>
/// <param name="ABodyUtf8">The body bytes, already UTF-8.</param>
/// <returns>`Content-Length: N` CR LF CR LF followed by the body, where N is
/// the BYTE count of the body.</returns>
function BuildFrame(const ABodyUtf8: TBytes): TBytes;  // dl:ok unused-public-symbol@5a05 -- shared frame helper of the merge handlers (A1/A3/A4/A5); P0 ships the seam only

implementation

uses
    Winapi.Windows
  ;

type
  TMergeWorker = class(TThread)
  private
    FOwner: TProxyMergeEngine;
  protected
    procedure Execute; override;
  public
    constructor Create(AOwner: TProxyMergeEngine);
  end;

constructor TMergeWorker.Create(AOwner: TProxyMergeEngine);
begin
  FOwner:= AOwner;
  FreeOnTerminate:= False;
  inherited Create(False);
end;

procedure TMergeWorker.Execute;
begin
  FOwner.WorkerLoop;
end;

{ Writes one diagnostic line to the real stderr handle -- never stdout, which
  carries the JSON-RPC stream. }
procedure MergeErrLine(const AText: string);
var
  H  : THandle;
  Raw: RawByteString;
  N  : DWORD;
begin
  H:= GetStdHandle(STD_ERROR_HANDLE);
  if (H = 0) or (H = INVALID_HANDLE_VALUE) then Exit;
  Raw:= RawByteString(AnsiString(AText + sLineBreak));
  N:= 0;
  WriteFile(H, Raw[1], Length(Raw), N, nil);
end;

const
  { The blank line that ends an LSP header block. }
  HEADER_END: array[0..3] of Byte = (13, 10, 13, 10);

function FrameBody(const AFrame: TBytes; ALen: Integer): string;
var
  I, J : Integer;
  Match: Boolean;
begin
  Result:= '';
  if ALen > Length(AFrame) then ALen:= Length(AFrame);
  for I:= 0 to ALen - Length(HEADER_END) do
  begin
    Match:= True;
    for J:= 0 to High(HEADER_END) do
      if AFrame[I + J] <> HEADER_END[J] then
      begin
        Match:= False;
        Break;
      end;
    if Match then
      Exit(TEncoding.UTF8.GetString(AFrame, I + Length(HEADER_END), ALen - I - Length(HEADER_END)));
  end;
end;

function BuildFrame(const ABodyUtf8: TBytes): TBytes;
var
  Hdr: TBytes;
begin
  Hdr:= TEncoding.ASCII.GetBytes(Format('Content-Length: %d'#13#10#13#10, [Length(ABodyUtf8)]));
  Result:= Hdr + ABodyUtf8;
end;

constructor TProxyMergeEngine.Create(const AOptions: TLspProxyOptions);
begin
  inherited Create;
  FOptions   := AOptions;
  FServerLock:= TCriticalSection.Create;
  FCallLock  := TCriticalSection.Create;
  FStateLock := TCriticalSection.Create;
  FJobReady  := TEvent.Create(nil, False, False, '');
  FJobDone   := TEvent.Create(nil, True , False, '');
  FWorker    := TMergeWorker.Create(Self);
end;

destructor TProxyMergeEngine.Destroy;
begin
  if FWorker <> nil then
  begin
    FWorker.Terminate;
    FJobReady.SetEvent;
    FWorker.WaitFor;
    FWorker.Free;
  end;
  FServer.Free;
  FJobDone.Free;
  FJobReady.Free;
  FStateLock.Free;
  FCallLock.Free;
  FServerLock.Free;
  inherited Destroy;
end;

procedure TProxyMergeEngine.WorkerLoop;
var
  Work  : TProc;
  Failed: Boolean;
begin
  while not TThread.CheckTerminated do
  begin
    FJobReady.WaitFor(INFINITE);
    if TThread.CheckTerminated then Break;
    FStateLock.Enter;
    try
      Work:= FJob;
      FJob:= nil;
    finally
      FStateLock.Leave;
    end;
    if not Assigned(Work) then Continue;
    Failed:= False;
    try
      Work();
    except  // dl:ok bare-except@e0ea -- fail-open by design: any merge exception forwards the original frame
      Failed:= True;   { fail-open: the caller forwards the original frame }
    end;
    Work:= nil;  // dl:ok overwrite-before-read@f29e -- releases the job closure (and what it captured) before blocking for the next job
    FStateLock.Enter;
    try
      FJobFailed:= Failed;
      FBusy     := False;
      FJobDone.SetEvent;
    finally
      FStateLock.Leave;
    end;
  end;
end;

function TProxyMergeEngine.RunWithinBudget(const AWork: TProc; ABudgetMs: Integer): Boolean;
begin
  Result:= False;
  if not Assigned(AWork) then Exit;
  if ABudgetMs < 0 then ABudgetMs:= 0;
  FCallLock.Enter;
  try
    FStateLock.Enter;
    try
      { A previous job overran its budget and is still running: this frame
        cannot be served in time, so it is forwarded untouched. }
      if FBusy then Exit(False);
      FBusy     := True;
      FJobFailed:= False;
      FJob      := AWork;
      FJobDone.ResetEvent;
    finally
      FStateLock.Leave;
    end;
    FJobReady.SetEvent;
    if FJobDone.WaitFor(Cardinal(ABudgetMs)) <> wrSignaled then Exit(False);
    FStateLock.Enter;
    try
      Result:= not FJobFailed;
    finally
      FStateLock.Leave;
    end;
  finally
    FCallLock.Leave;
  end;
end;

function TProxyMergeEngine.Server: TLSPServer;
begin
  FServerLock.Enter;
  try
    if not FServerTried then
    begin
      FServerTried:= True;
      try
        FServer:= TLSPServer.Create(FOptions.DbPaths);
      except
        on E: Exception do
        begin
          FServer:= nil;
          MergeErrLine('drag-lint lsp --proxy: merge disabled, cannot open the index (' +
                       E.ClassName + ': ' + E.Message + '); relaying DelphiLSP unchanged.');
        end;
      end;
    end;
    Result:= FServer;
  finally
    FServerLock.Leave;
  end;
end;

function TProxyMergeEngine.Intercept(ADir: TMergeDirection; const AFrame: TBytes;  // dl:ok unused-parameter@abe1 -- P0 Intercept declines every frame; the signature is the TFrameInterceptor contract
  ALen: Integer; out AReplacement: TBytes): Boolean;  // dl:ok unused-parameter@76b8 -- P0 Intercept declines every frame; the signature is the TFrameInterceptor contract
begin
  { P0: the seam only. Every frame is forwarded as received. }
  AReplacement:= nil;
  Result:= False;
end;

end.
