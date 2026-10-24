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
  would erase, or be erased by, DelphiLSP's compiler errors).

  A3 adds the COMPLETION merge: with --merge-completion, a client
  textDocument/completion request is recorded by id and drag-lint's items are
  computed at once on the merge worker; DelphiLSP's reply for that id gets
  drag-lint's items appended when their (label, kind) is not already there.
  The client's didOpen/didChange/didSave/didClose texts are tapped into the
  live-document overlay, so completion sees the buffer, not the disk. The
  other handlers (hover, definition) arrive in later tasks.

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
  , DRagLint.LSP.Proxy
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
  /// RunWithinBudget; the C&gt;S side (document tracking, the live-document
  /// tap, recording a completion request) runs inline and never takes
  /// FCallLock: a completion job and the warm-up are QUEUED on the worker
  /// (Enqueue, no wait), so a diagnostics merge never delays a client request.
  /// The S&gt;C completion merge waits on its own request's event, at most the
  /// part of the budget left since the request.</para>
  /// <para>The live-document overlay (TLiveDocuments, not thread-safe) is
  /// written ONLY on the merge worker: the C&gt;S pump queues each text under
  /// FDocLock and the next completion job applies the queue before it reads
  /// the buffer.</para>
  /// </remarks>
  TProxyMergeEngine = class  // dl:ok high-response@fad6 -- the one owner of a proxy's merge state by P0 design (worker, index, per-handler state); split per handler when A4/A5 add theirs
  private type
    TDocUpdate = record
      Path  : string;
      Text  : string;
      Remove: Boolean;
    end;
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
    FQueue       : TQueue<TProc>;
    FPending     : TDictionary<string, TObject>;
    FPendingLock : TCriticalSection;
    FDocUpdates  : TDictionary<string, TDocUpdate>;
    FDocLock     : TCriticalSection;
    FCompletionOff   : Integer;
    FCompletionWarned: Integer;
    procedure WorkerLoop;
    procedure WarmUp;
    function  Enqueue(const AWork: TProc): Boolean;
    function  IsDirty(const APath: string): Boolean;
    procedure TrackDocument(const AFrame: TBytes; ALen: Integer);
    procedure QueueDocUpdate(const APath: string; ARemove: Boolean; const AText: string);
    procedure FlushDocUpdates;
    procedure RecordCompletion(const AFrame: TBytes; ALen: Integer);
    procedure ComputeCompletion(APending: TObject);
    function  MergeCompletionReply(const AFrame: TBytes; ALen: Integer; out AReplacement: TBytes): Boolean;
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
    /// <returns>True, with AReplacement set to the rewritten frame, for (1) an
    /// S&gt;C textDocument/publishDiagnostics frame when MergeDiagnostics is on,
    /// the file has no unsaved edits, drag-lint has at least one finding for it
    /// and the findings were computed within MergeBudgetMs; (2) an S&gt;C reply
    /// to a recorded textDocument/completion request when MergeCompletion is
    /// on, drag-lint's items were computed within MergeBudgetMs of the request
    /// and at least one of them has a (label, kind) the reply lacks. False
    /// otherwise: the relay forwards the original bytes. Under the test seam
    /// (see Create): True with an empty replacement.</returns>
    /// <remarks>
    /// <para>Completion union (spec criteria 11-14): DelphiLSP's items come
    /// first, unchanged and in order; drag-lint's follow, each only when its
    /// (label, kind) is not already present, so the merged list has no
    /// duplicate pair that drag-lint added. A CompletionList object gets its
    /// items array extended; a bare array is extended; an empty array or a
    /// null result is replaced by drag-lint's items. No drag-lint items, an
    /// error reply, or drag-lint over budget: the reply is forwarded
    /// byte-identical. No index (no --db and nothing resolves, a --db that
    /// does not exist, or no store opens): one stderr line, completion merging
    /// off for the session.</para>
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
    /// <summary>The drag-lint LSP server over the index, created on first
    /// use: Options.DbPaths, or Options.ResolveDbs() when that list is empty
    /// (P0 review I1: resolved lazily, never on the relay's startup path).
    /// Paths that do not exist are dropped before the server is created.</summary>
    /// <returns>The server, or nil when no database exists or the server could
    /// not be created; the failure is reported once on stderr and never
    /// retried (fail-open).</returns>
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
  , DRagLint.Core.Interfaces
  , DRagLint.Core.LiveDocs
  , DRagLint.LSP.Completion
  ;

type
  { One recorded textDocument/completion request: where the caret was, and
    drag-lint's items once the worker computed them. Shared by the C>S pump
    (creates it), the merge worker (fills it) and the S>C pump (reads it), so it
    is reference counted: whoever releases last frees it. FItems / FErr /
    FElapsed are written before Done is set and read only after it is. }
  TPendingCompletion = class
  private   { unit-visible: only this unit's engine reads and writes them }
    FRefs: Integer;
    FPath     : string;
    FLine1    : Integer;
    FCol1     : Integer;
    FStartTick: UInt64;
    FElapsed  : UInt64;
    FItems    : string;
    FErr      : string;
    FDone     : TEvent;
  public
    constructor Create(const APath: string; ALine1, ACol1: Integer);
    destructor Destroy; override;
    procedure AddRef;
    procedure Release;
  end;

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

  METHOD_COMPLETION = 'textDocument/completion';
  MERGE_COMPLETION_PREFIX = 'drag-lint lsp --proxy: merge-completion ';
  { Bounds that keep a client that never sees a reply (cancelled requests) or a
    burst of keystrokes from growing the engine's state without limit. }
  QUEUE_MAX   = 8;
  PENDING_MAX = 64;

constructor TPendingCompletion.Create(const APath: string; ALine1, ACol1: Integer);
begin
  inherited Create;
  FRefs     := 1;
  FPath     := APath;
  FLine1    := ALine1;
  FCol1     := ACol1;
  FStartTick:= GetTickCount64;
  FDone     := TEvent.Create(nil, True, False, '');
end;

destructor TPendingCompletion.Destroy;
begin
  FDone.Free;
  inherited Destroy;
end;

procedure TPendingCompletion.AddRef;
begin
  TInterlocked.Increment(FRefs);
end;

procedure TPendingCompletion.Release;
begin
  if TInterlocked.Decrement(FRefs) = 0 then Free;
end;

{ The dedup key of one completion item: its label and its kind ('' when the
  item carries none). Spec criterion 13 keys on exactly this pair. }
function CompletionItemKey(const AItem: TJSONValue): string;
var
  V    : TJSONValue;
  Lab  : string;
  Kind : string;
begin
  Lab := '';
  Kind:= '';
  if AItem is TJSONObject then
  begin
    V:= TJSONObject(AItem).GetValue('label');
    if V <> nil then Lab:= V.Value;
    V:= TJSONObject(AItem).GetValue('kind');
    if V is TJSONNumber then Kind:= V.Value;
  end;
  Result:= Lab + #9 + Kind;
end;

{ Appends to AReply's result every item of AOurs whose (label, kind) it lacks.
  Handles the three result shapes a completion reply may carry: a
  CompletionList object (its items array is extended), a bare array (extended;
  an empty one is simply filled) and null (replaced by a CompletionList of
  AOurs). Returns True when AReply was changed. }
function UnionCompletion(const AReply: TJSONObject; const AOurs: TJSONArray): Boolean;
var
  Res   : TJSONValue;
  Target: TJSONArray;
  Wrap  : TJSONObject;
  Seen  : TDictionary<string, Boolean>;
  Elem  : TJSONValue;
  Key   : string;
begin
  Result:= False;
  Res:= AReply.GetValue('result');
  if Res is TJSONNull then
  begin
    Wrap:= TJSONObject.Create;
    Wrap.AddPair('isIncomplete', TJSONBool.Create(False));
    Wrap.AddPair('items', TJSONArray(AOurs.Clone));
    AReply.RemovePair('result').Free;
    AReply.AddPair('result', Wrap);
    Exit(True);
  end;
  if Res is TJSONArray then Target:= TJSONArray(Res)
  else if (Res is TJSONObject) and (TJSONObject(Res).GetValue('items') is TJSONArray) then
    Target:= TJSONArray(TJSONObject(Res).GetValue('items'))
  else Exit;
  Seen:= TDictionary<string, Boolean>.Create;
  try
    for Elem in Target do Seen.AddOrSetValue(CompletionItemKey(Elem), True);
    for Elem in AOurs do
    begin
      Key:= CompletionItemKey(Elem);
      if Seen.ContainsKey(Key) then Continue;
      Seen.Add(Key, True);
      Target.AddElement(TJSONValue(Elem.Clone));
      Result:= True;
    end;
  finally
    Seen.Free;
  end;
end;

type
  { What a document notification does to the live-document overlay. }
  TLiveUpdate = (luNone, luSet, luRemove);

{ The overlay update a didOpen / didChange / didSave / didClose body implies,
  mirroring TLSPServer's own handlers: didOpen and didSave set the text they
  carry (a didSave without text means the buffer equals disk: remove); a
  full-text didChange sets its LAST change, a ranged one removes (the overlay
  holds whole texts only); didClose removes. }
function LiveUpdateOf(const AMethod: string; const AJson: TJSONValue; out AText: string): TLiveUpdate;
var
  V      : TJSONValue;
  Changes: TJSONArray;
  Last   : TJSONValue;
begin
  AText := '';
  Result:= luNone;
  if AMethod = METHOD_DID_CLOSE then Exit(luRemove);
  if AMethod = METHOD_DID_CHANGE then
  begin
    if not AJson.TryGetValue<TJSONArray>('params.contentChanges', Changes) or (Changes.Count = 0) then Exit;
    Last:= Changes.Items[Changes.Count - 1];
    if not (Last is TJSONObject) then Exit;
    if TJSONObject(Last).GetValue('range') <> nil then Exit(luRemove);
    V:= TJSONObject(Last).GetValue('text');
    if (V = nil) or (V is TJSONNull) then Exit;   { a change without text changes nothing }
  end
  else if AMethod = METHOD_DID_OPEN then V:= AJson.FindValue('params.textDocument.text')
  else V:= AJson.FindValue('params.text');   { didSave }
  if (V = nil) or (V is TJSONNull) then Result:= luRemove
  else
  begin
    AText := V.Value;
    Result:= luSet;
  end;
end;

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
  FQueue      := TQueue<TProc>.Create;
  FPending    := TDictionary<string, TObject>.Create;
  FPendingLock:= TCriticalSection.Create;
  FDocUpdates := TDictionary<string, TDocUpdate>.Create;
  FDocLock    := TCriticalSection.Create;
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
  for var Left: TObject in FPending.Values do TPendingCompletion(Left).Release;
  FPending.Free;
  FPendingLock.Free;
  FDocUpdates.Free;
  FDocLock.Free;
  FQueue.Free;
  FDirty.Free;
  FDirtyLock.Free;
  FJobDone.Free;
  FJobReady.Free;
  FStateLock.Free;
  FCallLock.Free;
  FServerLock.Free;
  inherited Destroy;
end;

{ Takes the next job: the budgeted one (RunWithinBudget's, which a caller is
  waiting on) before the queued ones (Enqueue's, which nobody waits on). }
function TakeJob(var ABudgetJob: TProc; AQueue: TQueue<TProc>; out ABudgeted: Boolean): TProc;
begin
  ABudgeted:= Assigned(ABudgetJob);
  if ABudgeted then
  begin
    Result    := ABudgetJob;
    ABudgetJob:= nil;
  end
  else if AQueue.Count > 0 then Result:= AQueue.Dequeue()
  else Result:= nil;
end;

procedure TProxyMergeEngine.WorkerLoop;
var
  Work    : TProc;
  Failed  : Boolean;
  Budgeted: Boolean;
begin
  while not TThread.CheckTerminated do
  begin
    FJobReady.WaitFor(INFINITE);
    { Drain: one wake-up may stand for several queued jobs (auto-reset event). }
    while not TThread.CheckTerminated do
    begin
      FStateLock.Enter;
      try
        Work:= TakeJob(FJob, FQueue, Budgeted);
      finally
        FStateLock.Leave;
      end;
      if not Assigned(Work) then Break;
      Failed:= False;
      try
        Work();
      except  // dl:ok bare-except@e0ea -- fail-open by design: any merge exception forwards the original frame
        Failed:= True;   { fail-open: the caller forwards the original frame }
      end;
      Work:= nil;  // dl:ok overwrite-before-read@f29e -- releases the job closure (and what it captured) before blocking for the next job
      if not Budgeted then Continue;   { a queued job signals through its own state }
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
end;

{ Queues AWork on the merge worker and returns at once; nobody waits on it, so
  it must publish its result through its own captured state. False (AWork is
  dropped, never run) when QUEUE_MAX jobs are already waiting. A budgeted job
  that arrives meanwhile runs first. }
function TProxyMergeEngine.Enqueue(const AWork: TProc): Boolean;
begin
  FStateLock.Enter;
  try
    Result:= FQueue.Count < QUEUE_MAX;
    if Result then FQueue.Enqueue(AWork);
  finally
    FStateLock.Leave;
  end;
  if Result then FJobReady.SetEvent;
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
var
  Dbs  : TArray<string>;
  Found: TArray<string>;
  D    : string;
begin
  FServerLock.Enter;
  try
    if not FServerTried then
    begin
      FServerTried:= True;
      try
        Dbs:= FOptions.DbPaths;
        if (Length(Dbs) = 0) and Assigned(FOptions.ResolveDbs) then Dbs:= FOptions.ResolveDbs();
        Found:= nil;
        for D in Dbs do
          if FileExists(D) then Found:= Found + [D];
        { Checked here, not left to TLSPServer.Create: it skips a missing path
          with a line of its own and opens nothing, which would cost the
          session a second, less specific stderr line. }
        if Length(Found) = 0 then
          MergeErrLine('drag-lint lsp --proxy: merge disabled, no index database found (' +
                       (if Length(Dbs) = 0 then 'no --db and none resolved' else string.Join(', ', Dbs)) +
                       '); relaying DelphiLSP unchanged.')
        else
          FServer:= TLSPServer.Create(Found);
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

{ C>S, first didOpen only: builds what the enabled merges need on the merge
  worker, off the relay path (queued, never waited on). TLinter.Create loads
  every rule file, which takes seconds cold and would otherwise make the FIRST
  publishDiagnostics of a session miss any budget; opening the index does the
  same to the first completion. Does not touch FBudgetWarned. FWarming tells
  the S>C side an overrun is the warm-up, not a dead merge; it stays set until
  the job ends (A3: it used to be cleared at once, because the budget-0 wait
  this replaced always reported an overrun). Runs on the C>S pump thread. }
procedure TProxyMergeEngine.WarmUp;
begin
  if FWarmQueued then Exit;
  FWarmQueued:= True;
  TInterlocked.Exchange(FWarming, 1);
  if not Enqueue(
    procedure
    begin
      try
        if FOptions.MergeDiagnostics and (FLinter = nil) then FLinter:= TLinter.Create('');
        if FOptions.MergeCompletion then Server;   { opens the index; a failure is reported there }
      finally
        TInterlocked.Exchange(FWarming, 0);
      end;
    end) then
    TInterlocked.Exchange(FWarming, 0);
end;

{ C>S: with MergeDiagnostics, didChange marks the document dirty and didSave /
  didOpen / didClose clear it; with MergeCompletion, the text the notification
  implies is queued for the live-document overlay. A first didOpen also warms
  the worker. Runs on the C>S pump thread, inline (no worker, no FCallLock). }
procedure TProxyMergeEngine.TrackDocument(const AFrame: TBytes; ALen: Integer);
var
  Json  : TJSONValue;
  Method: string;
  Uri   : string;
  Key   : string;
  Path  : string;
  LiveText: string;
  Upd   : TLiveUpdate;
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
      Path:= TLSPServer.FileFromUri(Uri);
      Key := DocKey(Path);
      if FOptions.MergeDiagnostics then
      begin
        FDirtyLock.Enter;
        try
          if Method = METHOD_DID_CHANGE then FDirty.AddOrSetValue(Key, True)
          else FDirty.Remove(Key);
        finally
          FDirtyLock.Leave;
        end;
      end;
      if FOptions.MergeCompletion then
      begin
        Upd:= LiveUpdateOf(Method, Json, LiveText);
        if Upd <> luNone then QueueDocUpdate(Path, Upd = luRemove, LiveText);
      end;
      if Method = METHOD_DID_OPEN then WarmUp;
    finally
      Json.Free;
    end;
  except
    on E: Exception do
      MergeErrLine(MERGE_ERR_PREFIX + 'could not track ' + Method + ' (' + E.ClassName + ': ' + E.Message + ').');
  end;
end;

{ C>S: queues one overlay update; the latest per file wins. Applied on the
  worker by FlushDocUpdates, because TLiveDocuments is not thread-safe. }
procedure TProxyMergeEngine.QueueDocUpdate(const APath: string; ARemove: Boolean; const AText: string);
var
  U: TDocUpdate;
begin
  U.Path  := APath;
  U.Text  := AText;
  U.Remove:= ARemove;
  FDocLock.Enter;
  try
    FDocUpdates.AddOrSetValue(DocKey(APath), U);
  finally
    FDocLock.Leave;
  end;
end;

{ Worker thread only: applies the queued overlay updates. }
procedure TProxyMergeEngine.FlushDocUpdates;
var
  Batch: TArray<TDocUpdate>;
  U    : TDocUpdate;
begin
  FDocLock.Enter;
  try
    Batch:= FDocUpdates.Values.ToArray;
    FDocUpdates.Clear;
  finally
    FDocLock.Leave;
  end;
  for U in Batch do
    if U.Remove then TLiveDocuments.Remove(U.Path)
    else TLiveDocuments.SetText(U.Path, U.Text);
end;

{ C>S: records a textDocument/completion request by id and queues drag-lint's
  items for it on the worker at once, so they are usually ready before
  DelphiLSP answers. Never delays the frame beyond one JSON parse. }
procedure TProxyMergeEngine.RecordCompletion(const AFrame: TBytes; ALen: Integer);  // dl:ok too-many-exit-points@8491 -- each Exit is a decline (nothing recorded, relay unchanged); one flat guard sequence reads better than nesting
var
  Json  : TJSONValue;
  Method: string;
  Uri   : string;
  IdVal : TJSONValue;
  PosObj: TJSONObject;
  P     : TPendingCompletion;
  Key   : string;
  Old   : TObject;
  Full  : Boolean;
begin
  if TInterlocked.CompareExchange(FCompletionOff, 0, 0) <> 0 then Exit;
  if not FrameContains(AFrame, ALen, METHOD_COMPLETION) then Exit;
  try
    Json:= TJSONObject.ParseJSONValue(FrameBody(AFrame, ALen));
    try
      if not (Json is TJSONObject) then Exit;
      if not Json.TryGetValue<string>('method', Method) or (Method <> METHOD_COMPLETION) then Exit;
      IdVal:= TJSONObject(Json).GetValue('id');
      if (IdVal = nil) or not Json.TryGetValue<string>('params.textDocument.uri', Uri)
         or not Json.TryGetValue<TJSONObject>('params.position', PosObj) then Exit;
      { The position exactly as TLSPServer.HandleCompletion converts it: LSP is
        0-based, the completion builder 1-based. }
      P:= TPendingCompletion.Create(TLSPServer.FileFromUri(Uri),  // dl:ok object-leak@7cfa -- reference counted: owned by FPending (or Release on the Full path) and by the job (AddRef/Release); Release frees
        StrToIntDef(PosObj.GetValue('line').Value, 0) + 1,
        StrToIntDef(PosObj.GetValue('character').Value, 0) + 1);
      Key:= IdVal.ToJSON;
      FPendingLock.Enter;
      try
        Full:= FPending.Count >= PENDING_MAX;
        if not Full then
        begin
          if FPending.TryGetValue(Key, Old) then TPendingCompletion(Old).Release;   { a reused id: the stale entry goes }
          FPending.AddOrSetValue(Key, P);
        end;
      finally
        FPendingLock.Leave;
      end;
      if Full then
      begin
        P.Release;
        Exit;
      end;
      P.AddRef;   { the job's reference }
      if not Enqueue(procedure begin ComputeCompletion(P); end) then P.Release;
    finally
      Json.Free;
    end;
  except
    on E: Exception do
      MergeErrLine(MERGE_COMPLETION_PREFIX + 'could not record a request (' + E.ClassName + ': ' + E.Message + ').');
  end;
end;

{ Worker thread: drag-lint's items for one recorded request. Publishes only
  through the record (Items / Err / Elapsed, then Done) and releases the job's
  reference. No store at all turns completion merging off for the session,
  with one stderr line (Server reports its own failures). }
procedure TProxyMergeEngine.ComputeCompletion(APending: TObject);
var
  P     : TPendingCompletion;
  S     : TLSPServer;
  Stores: TArray<ISymbolStore>;
  Arr   : TJSONArray;
begin
  P:= TPendingCompletion(APending);
  try
    try
      FlushDocUpdates;
      S:= Server;
      Stores:= nil;
      if S <> nil then Stores:= S.Context.Stores;
      if Length(Stores) = 0 then
      begin
        if (TInterlocked.Exchange(FCompletionOff, 1) = 0) and (S <> nil) then
          MergeErrLine('drag-lint lsp --proxy: merge disabled for completion, no index store could be opened; relaying DelphiLSP unchanged.');
      end
      else
      begin
        Arr:= TLspCompletion.BuildCompletionItems(Stores, P.FPath, P.FLine1, P.FCol1);
        try
          P.FItems:= Arr.ToJSON;
        finally
          Arr.Free;
        end;
      end;
    except   { not swallowed: the message is published through P.FErr and logged by the S>C side }
      on E: Exception do P.FErr:= E.ClassName + ': ' + E.Message;
    end;
  finally
    P.FElapsed:= GetTickCount64 - P.FStartTick;
    P.FDone.SetEvent;
    P.Release;
  end;
end;

{ S>C: a reply to a recorded completion request gets drag-lint's items
  unioned in (see Intercept). Waits for them at most the part of the budget
  left since the request. Runs on the S>C pump thread. }
function TProxyMergeEngine.MergeCompletionReply(const AFrame: TBytes; ALen: Integer;  // dl:ok too-many-exit-points@a36d -- each Exit is a fail-open decline (forward the original frame); one flat guard sequence reads better than nesting
  out AReplacement: TBytes): Boolean;
var
  Json  : TJSONValue;
  IdVal : TJSONValue;
  Obj   : TObject;
  P     : TPendingCompletion;
  Remain: Int64;
  Ours  : TJSONValue;
  Empty : Boolean;
begin
  Result:= False;
  AReplacement:= nil;
  FPendingLock.Enter;
  try
    Empty:= FPending.Count = 0;
  finally
    FPendingLock.Leave;
  end;
  if Empty or not FrameContains(AFrame, ALen, '"id"') then Exit;
  P:= nil;
  try
    Json:= TJSONObject.ParseJSONValue(FrameBody(AFrame, ALen));
    try
      { A reply has an id and no method; a server request has both. }
      if not (Json is TJSONObject) or (TJSONObject(Json).GetValue('method') <> nil) then Exit;
      IdVal:= TJSONObject(Json).GetValue('id');
      if IdVal = nil then Exit;
      FPendingLock.Enter;
      try
        if FPending.TryGetValue(IdVal.ToJSON, Obj) then
        begin
          FPending.Remove(IdVal.ToJSON);
          P:= TPendingCompletion(Obj);
        end;
      finally
        FPendingLock.Leave;
      end;
      if (P = nil) or (TJSONObject(Json).GetValue('result') = nil) then Exit;   { not ours, or an error reply }
      Remain:= Int64(P.FStartTick) + FOptions.MergeBudgetMs - Int64(GetTickCount64);
      if Remain < 0 then Remain:= 0;
      if (P.FDone.WaitFor(Cardinal(Remain)) <> wrSignaled) or (P.FElapsed > UInt64(FOptions.MergeBudgetMs)) then
      begin
        if TInterlocked.Exchange(FCompletionWarned, 1) = 0 then
          MergeErrLine(MERGE_COMPLETION_PREFIX + 'over its ' + IntToStr(FOptions.MergeBudgetMs) +
                       ' ms budget; the completion reply is forwarded unmerged (reported once).');
        Exit;
      end;
      if P.FErr <> '' then
      begin
        MergeErrLine(MERGE_COMPLETION_PREFIX + 'skipped a reply (' + P.FErr + '); forwarded unchanged.');
        Exit;
      end;
      Ours:= TJSONObject.ParseJSONValue(P.FItems);
      try
        if not (Ours is TJSONArray) or (TJSONArray(Ours).Count = 0) then Exit;   { nothing to add: original bytes }
        if not UnionCompletion(TJSONObject(Json), TJSONArray(Ours)) then Exit;
      finally
        Ours.Free;
      end;
      AReplacement:= BuildFrame(TEncoding.UTF8.GetBytes(Json.ToJSON));
      Result:= True;
    finally
      Json.Free;
      if P <> nil then P.Release;
    end;
  except
    on E: Exception do
    begin
      AReplacement:= nil;
      Result:= False;
      MergeErrLine(MERGE_COMPLETION_PREFIX + 'skipped a reply (' + E.ClassName + ': ' + E.Message + '); forwarded unchanged.');
    end;
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
  if ADir = mdClientToServer then
  begin
    if FOptions.MergeDiagnostics or FOptions.MergeCompletion then TrackDocument(AFrame, ALen);
    if FOptions.MergeCompletion then RecordCompletion(AFrame, ALen);
    Exit(False);
  end;
  if FOptions.MergeCompletion and MergeCompletionReply(AFrame, ALen, AReplacement) then Exit(True);
  Result:= FOptions.MergeDiagnostics and MergeDiagnostics(AFrame, ALen, AReplacement);
end;

end.
