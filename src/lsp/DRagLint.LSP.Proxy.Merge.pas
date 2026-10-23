unit DRagLint.LSP.Proxy.Merge;

{ Merge plan P0 -- the interception seam of the LSP merge proxy.

  The relay in DRagLint.LSP.Proxy hands every COMPLETE frame to an optional
  interceptor before forwarding it. This unit provides that interceptor's
  types, the frame helpers the merge handlers will share, and the engine that
  owns the merge state (the lazily-opened index, the single worker thread that
  enforces a per-frame time budget).

  P0 shipped the seam; A1 adds the first handler, the DIAGNOSTICS merge: with
  --merge-diagnostics, a DelphiLSP textDocument/publishDiagnostics frame gets
  drag-lint's findings for the same file appended to its OWN diagnostics array
  (publishDiagnostics replaces the client's set per URI, so a separate frame
  would erase, or be erased by, DelphiLSP's compiler errors). The other
  handlers (completion, hover, definition) arrive in later tasks.

  FAIL OPEN, ALWAYS. A handler that raises, overruns its budget or cannot open
  the index makes the relay forward DelphiLSP's original bytes. The engine
  never decides on its own to drop a frame. }

interface

uses
    System.SysUtils
  , System.Classes
  , System.SyncObjs
  , System.Generics.Collections
  , DRagLint.Lint.Linter
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
  /// forward the original bytes unchanged. True with an EMPTY AReplacement is
  /// treated as False (the original is forwarded): an interceptor can never drop
  /// a frame by leaving the replacement unset.</returns>
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
  /// internally. The dirty-URI set has its own lock (written by the C&gt;S pump,
  /// read by the S&gt;C pump). The linter is created and used ONLY on the merge
  /// worker thread, so it needs none.</para>
  /// <para>Latency (P0 review I3): only the S&gt;C diagnostics merge calls
  /// RunWithinBudget; the C&gt;S document tracking runs inline without
  /// FCallLock, so a diagnostics merge never delays a client request. A later
  /// handler that also uses RunWithinBudget may wait up to about twice the
  /// budget for the lock.</para>
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
    FTestEmptyReplacement: Boolean;
    FLinter      : TLinter;
    FDirty       : TDictionary<string, Boolean>;
    FDirtyLock   : TCriticalSection;
    FBudgetWarned: Boolean;
    FWarmQueued  : Boolean;
    FWarming     : Integer;
    procedure WorkerLoop;
    procedure WarmLinter;
    function  IsDirty(const APath: string): Boolean;
    procedure TrackDocument(const AFrame: TBytes; ALen: Integer);
    function  MergeDiagnostics(const AFrame: TBytes; ALen: Integer; out AReplacement: TBytes): Boolean;
  public
    /// <summary>Copies the options and starts the merge worker thread.</summary>
    /// <remarks>Test seam: with the environment variable
    /// DRAGLINT_MERGE_TEST_EMPTY_REPLACEMENT=1 Intercept answers True with an
    /// EMPTY replacement for every frame, so a guard can prove the relay
    /// declines it (run_lsp_proxy_stub_modes_guard.ps1 case f).</remarks>
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
    /// <returns>True, with AReplacement set to the rewritten frame, only for an
    /// S&gt;C textDocument/publishDiagnostics frame when MergeDiagnostics is on,
    /// the file has no unsaved edits, drag-lint has at least one finding for it
    /// and the findings were computed within MergeBudgetMs. False otherwise:
    /// the relay forwards the original bytes. Under the test seam (see Create):
    /// True with an empty replacement.</returns>
    /// <remarks>
    /// <para>C&gt;S frames are never replaced. With MergeDiagnostics on, a
    /// didChange marks its URI dirty and a didSave, didOpen or didClose clears it; a
    /// publish for a dirty URI is forwarded unmerged, because drag-lint lints
    /// the file on DISK and its ranges would not match the edited buffer.</para>
    /// <para>Fail-open: unparseable JSON, a missing uri or diagnostics array,
    /// or a lint exception forwards the original frame and writes one stderr
    /// line naming the merge. The first over-budget refusal writes one stderr
    /// line, once per process.</para>
    /// <para>The pre-check is a byte substring scan for the method name, so a
    /// frame that is not a publishDiagnostics is never parsed. The linter is
    /// created on the first merge, never at startup, so the first publish of a
    /// session may overrun the budget and be forwarded unmerged.</para>
    /// </remarks>
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
function FrameBody(const AFrame: TBytes; ALen: Integer): string;

/// <summary>Frames a UTF-8 body as one LSP message.</summary>
/// <param name="ABodyUtf8">The body bytes, already UTF-8.</param>
/// <returns>`Content-Length: N` CR LF CR LF followed by the body, where N is
/// the BYTE count of the body.</returns>
function BuildFrame(const ABodyUtf8: TBytes): TBytes;

implementation

uses
    Winapi.Windows
  , System.JSON
  , DRagLint.LSP.Completion
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

  METHOD_PUBLISH_DIAGNOSTICS = 'textDocument/publishDiagnostics';
  METHOD_DID_CHANGE          = 'textDocument/didChange';
  METHOD_DID_SAVE            = 'textDocument/didSave';
  METHOD_DID_OPEN            = 'textDocument/didOpen';
  METHOD_DID_CLOSE           = 'textDocument/didClose';
  { The common prefix of the three document notifications tracked above. }
  METHOD_DID_PREFIX          = 'textDocument/did';

  MERGE_ERR_PREFIX = 'drag-lint lsp --proxy: merge-diagnostics ';

{ True when the ASCII text ANeedle occurs in the first ALen bytes of AFrame.
  The pre-check of every handler: a frame that cannot match is never decoded
  or parsed. }
function FrameContains(const AFrame: TBytes; ALen: Integer; const ANeedle: RawByteString): Boolean;
var
  I, J, N: Integer;
begin
  N:= Length(ANeedle);
  if ALen > Length(AFrame) then ALen:= Length(AFrame);
  for I:= 0 to ALen - N do
  begin
    J:= 0;
    while (J < N) and (AFrame[I + J] = Byte(ANeedle[J + 1])) do Inc(J);
    if J = N then Exit(True);
  end;
  Result:= False;
end;

{ The dirty-set key of a file path: case-folded, so the client's and the
  server's spellings of one file agree. }
function DocKey(const APath: string): string;
begin
  Result:= LowerCase(APath);
end;

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
  FTestEmptyReplacement:= GetEnvironmentVariable('DRAGLINT_MERGE_TEST_EMPTY_REPLACEMENT') = '1';
  FDirty    := TDictionary<string, Boolean>.Create;
  FDirtyLock:= TCriticalSection.Create;
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
  FLinter.Free;
  FDirty.Free;
  FDirtyLock.Free;
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

function TProxyMergeEngine.IsDirty(const APath: string): Boolean;
begin
  FDirtyLock.Enter;
  try
    Result:= FDirty.ContainsKey(DocKey(APath));
  finally
    FDirtyLock.Leave;
  end;
end;

{ C>S, first didOpen only: builds the lint engine on the merge worker, off the
  relay path (budget 0 = enqueue and return at once). TLinter.Create loads every
  rule file, which takes seconds cold and would otherwise make the FIRST
  publishDiagnostics of a session miss any budget. Does not touch
  FBudgetWarned. FWarming tells the S>C side an overrun is the warm-up, not a
  dead merge. Runs on the C>S pump thread. }
procedure TProxyMergeEngine.WarmLinter;
begin
  if FWarmQueued then Exit;
  FWarmQueued:= True;
  TInterlocked.Exchange(FWarming, 1);
  if not RunWithinBudget(
    procedure
    begin
      try
        if FLinter = nil then FLinter:= TLinter.Create('');
      finally
        TInterlocked.Exchange(FWarming, 0);
      end;
    end, 0) then
    TInterlocked.Exchange(FWarming, 0);
end;

{ C>S: didChange marks the document dirty, didSave / didOpen / didClose clear it.
  A first didOpen also warms the linter. Runs on the C>S pump thread, inline
  (no worker, no FCallLock). }
procedure TProxyMergeEngine.TrackDocument(const AFrame: TBytes; ALen: Integer);
var
  Json  : TJSONValue;
  Method: string;
  Uri   : string;
  Key   : string;
begin
  if not FrameContains(AFrame, ALen, METHOD_DID_PREFIX) then Exit;
  Method:= '';
  try
    Json:= TJSONObject.ParseJSONValue(FrameBody(AFrame, ALen));
    try
      if not (Json is TJSONObject) then Exit;
      if not Json.TryGetValue<string>('method', Method) then Exit;
      if (Method <> METHOD_DID_CHANGE) and (Method <> METHOD_DID_SAVE) and (Method <> METHOD_DID_OPEN)
         and (Method <> METHOD_DID_CLOSE) then Exit;
      if not Json.TryGetValue<string>('params.textDocument.uri', Uri) then Exit;
      Key:= DocKey(TLSPServer.FileFromUri(Uri));
      FDirtyLock.Enter;
      try
        if Method = METHOD_DID_CHANGE then FDirty.AddOrSetValue(Key, True)
        else FDirty.Remove(Key);
      finally
        FDirtyLock.Leave;
      end;
      if Method = METHOD_DID_OPEN then WarmLinter;
    finally
      Json.Free;
    end;
  except
    on E: Exception do
      MergeErrLine(MERGE_ERR_PREFIX + 'could not track ' + Method + ' (' + E.ClassName + ': ' + E.Message + ').');
  end;
end;

{ S>C: rewrites a publishDiagnostics frame with drag-lint's findings appended.
  Runs on the S>C pump thread; the lint itself runs on the merge worker, inside
  the budget. }
function TProxyMergeEngine.MergeDiagnostics(const AFrame: TBytes; ALen: Integer;  // dl:ok too-many-exit-points@3a8f -- each Exit is a fail-open decline (forward the original frame); one flat guard sequence reads better than nesting
  out AReplacement: TBytes): Boolean;
var
  Json  : TJSONValue;
  Method: string;
  Uri   : string;
  Path  : string;
  Diags : TJSONArray;
  Items : string;
  Err   : string;
  Added : TJSONValue;
  Elem  : TJSONValue;

  procedure Skip(const AWhy: string);
  begin
    MergeErrLine(MERGE_ERR_PREFIX + 'skipped a frame (' + AWhy + '); forwarded unchanged.');
  end;

begin
  Result:= False;
  AReplacement:= nil;
  if not FrameContains(AFrame, ALen, METHOD_PUBLISH_DIAGNOSTICS) then Exit;
  try
    Json:= TJSONObject.ParseJSONValue(FrameBody(AFrame, ALen));
    try
      if not (Json is TJSONObject) then
      begin
        Skip('body is not a JSON object');
        Exit;
      end;
      { A frame that merely mentions the method (a response, a log message)
        is not ours to touch. }
      if not Json.TryGetValue<string>('method', Method) then Exit;
      if Method <> METHOD_PUBLISH_DIAGNOSTICS then Exit;
      if not (Json.TryGetValue<string>('params.uri', Uri) and
              Json.TryGetValue<TJSONArray>('params.diagnostics', Diags)) then
      begin
        Skip('no params.uri or params.diagnostics array');
        Exit;
      end;
      Path:= TLSPServer.FileFromUri(Uri);
      if IsDirty(Path) then Exit;   { unsaved edits: our on-disk ranges would lie }

      { The job publishes ONLY through the captured strings Items / Err, read
        after a True return; an over-budget job writes them after this method
        stopped looking, which is harmless. The job never raises, so a False
        return means over budget or worker still busy. }
      Items:= '';
      Err  := '';
      if not RunWithinBudget(
        procedure
        var
          Arr: TJSONArray;
        begin
          try
            if FLinter = nil then FLinter:= TLinter.Create('');
            Arr:= TLspCompletion.BuildDiagnostics(FLinter, Path, nil);
            try
              Items:= Arr.ToJSON;
            finally
              Arr.Free;
            end;
          except  // dl:ok try-except-swallowed@a7c8 -- not swallowed: the message is published through Err and logged by the caller
            on E: Exception do Err:= E.ClassName + ': ' + E.Message;
          end;
        end, FOptions.MergeBudgetMs) then
      begin
        if (not FBudgetWarned) and (TInterlocked.CompareExchange(FWarming, 0, 0) = 0) then
        begin
          FBudgetWarned:= True;   { S>C pump thread only: no lock needed }
          MergeErrLine(MERGE_ERR_PREFIX + 'over its ' + IntToStr(FOptions.MergeBudgetMs) +
                       ' ms budget; publishDiagnostics is forwarded unmerged while the merge worker is busy (reported once).');
        end;
        Exit;
      end;
      if Err <> '' then
      begin
        Skip(Err);
        Exit;
      end;

      Added:= TJSONObject.ParseJSONValue(Items);
      try
        if not (Added is TJSONArray) or (TJSONArray(Added).Count = 0) then Exit;   { clean file: original bytes }
        for Elem in TJSONArray(Added) do
          Diags.AddElement(TJSONValue(Elem.Clone));
      finally
        Added.Free;
      end;
      AReplacement:= BuildFrame(TEncoding.UTF8.GetBytes(Json.ToJSON));
      Result:= True;
    finally
      Json.Free;
    end;
  except
    on E: Exception do
    begin
      AReplacement:= nil;
      Result:= False;
      Skip(E.ClassName + ': ' + E.Message);
    end;
  end;
end;

function TProxyMergeEngine.Intercept(ADir: TMergeDirection; const AFrame: TBytes;
  ALen: Integer; out AReplacement: TBytes): Boolean;
begin
  AReplacement:= nil;
  if FTestEmptyReplacement then Exit(True);
  if not FOptions.MergeDiagnostics then Exit(False);
  if ADir = mdClientToServer then
  begin
    TrackDocument(AFrame, ALen);
    Exit(False);
  end;
  Result:= MergeDiagnostics(AFrame, ALen, AReplacement);
end;

end.
