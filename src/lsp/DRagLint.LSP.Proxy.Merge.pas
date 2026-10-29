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
  live-document overlay, so completion sees the buffer, not the disk.

  A4 adds the HOVER merge on the same request-id table: with --merge-hover, a
  client textDocument/hover request is recorded by id and drag-lint's hover
  markdown (TLSPServer.ComputeHoverMarkdown, the plain server's own hover) is
  computed at once on the merge worker; DelphiLSP's reply for that id gets it
  appended after a '---' rule, or carries it alone when DelphiLSP has none.

  A5 adds the DEFINITION fallback and the requests DelphiLSP does not serve:
  with --merge-definition, a recorded textDocument/definition whose reply is
  null or [] gets drag-lint's locations instead (a non-empty reply wins); the
  initialize reply gains referencesProvider / workspaceSymbolProvider when it
  lacks them, and the client's textDocument/references / workspace/symbol
  requests are then ANSWERED here (Answer, written through ClientWriter) and
  never forwarded.

  FAIL OPEN, ALWAYS. A handler that raises, overruns its budget or cannot open
  the index makes the relay forward DelphiLSP's original bytes. The engine
  never decides on its own to drop a frame. }

interface

uses
    System.SysUtils
  , System.Classes
  , System.SyncObjs
  , System.Generics.Collections
  , System.JSON
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

  /// <summary>Called by the relay with every complete C&gt;S frame before the
  /// interceptor (merge plan A5).</summary>
  /// <param name="AFrame">Buffer holding the frame at offset 0.</param>
  /// <param name="ALen">Byte length of the frame in AFrame.</param>
  /// <param name="AOnTake">Called at most once, at the moment the answerer
  /// commits to the frame and BEFORE any reply to it can reach the client, so
  /// the relay can trace the request ahead of its reply (group-4 P2). May be
  /// nil.</param>
  /// <returns>True when the proxy consumes this frame: a request it answers
  /// itself (exactly one reply reaches the client) or a $/cancelRequest for
  /// such a request (nothing is written). The frame is NOT forwarded. False
  /// (or any exception): the frame goes on as usual.</returns>
  TFrameAnswerer = reference to function(const AFrame: TBytes; ALen: Integer; const AOnTake: TProc): Boolean;

  /// <summary>Writes one complete frame to the client, serialised with the
  /// relay's own S&gt;C writes.</summary>
  /// <param name="AFrame">The whole frame, headers included.</param>
  /// <returns>False when the client end is closed.</returns>
  TClientWriter = reference to function(const AFrame: TBytes): Boolean;

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
    { One request the proxy answers itself (A5). }
    TAnswerJob = record
      Id         : string;    { the request id, as JSON }
      Symbols    : Boolean;   { workspace/symbol; else textDocument/references }
      Query      : string;
      Path       : string;    { '' when the request named no usable position }
      Line0      : Integer;
      Col0       : Integer;
      IncludeDecl: Boolean;
    end;
  private
    FOptions    : TLspProxyOptions;
    FServer     : TLSPServer;
    FServerTried: Boolean;
    FServerLock : TCriticalSection;
    FPendingSettingsFile: string; { LSP-1 CORE: the .delphilsp.json the IDE named, applied to FServer on the next Server call; under FServerLock }
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
    FHoverOff        : Integer;
    FHoverWarned     : Integer;
    FDefinitionOff   : Integer;
    FDefinitionWarned: Integer;
    FTheirReferences : Integer;
    FTheirSymbols    : Integer;
    FClientWriter    : TClientWriter;
    FAnswersOut      : Integer;
    FAnswersIdle     : TEvent;
    FAnsweredIds     : TDictionary<string, Boolean>;   { C>S pump only: ids Answer took }
    FTestAnswerInline: Boolean;
    FTestFastPath    : Boolean;
    function  TakeCancel(const AFrame: TBytes; ALen: Integer; const AOnTake: TProc): Boolean;
    procedure WorkerLoop;
    procedure EnsureLinter;
    procedure WarmUp;
    function  Enqueue(const AWork: TProc): Boolean;
    function  IsDirty(const APath: string): Boolean;
    procedure AnnounceOpen(const APath: string);
    procedure TrackDocument(const AFrame: TBytes; ALen: Integer);
    procedure PickupContext(const AFrame: TBytes; ALen: Integer);
    procedure QueueDocUpdate(const APath: string; ARemove: Boolean; const AText: string);
    procedure FlushDocUpdates;
    procedure RecordRequest(const AFrame: TBytes; ALen: Integer);
    procedure ComputeCompletion(APending: TObject);
    procedure ComputeHover(APending: TObject);
    procedure ComputeDefinition(APending: TObject);
    function  MergeInitialize(const AReply: TJSONObject): Boolean;
    procedure AnswerOnWorker(const AJob: TAnswerJob);
    procedure SendAnswer(const AId, AResultJson: string);
    procedure EndAnswer;
    function  MergeReply(const AFrame: TBytes; ALen: Integer; out AReplacement: TBytes): Boolean;
    function  MergeDiagnostics(const AFrame: TBytes; ALen: Integer; out AReplacement: TBytes): Boolean;
  public
    /// <summary>Copies the options and starts the merge worker thread.</summary>
    /// <remarks>Test seam: with the environment variable
    /// DRAGLINT_MERGE_TEST_EMPTY_REPLACEMENT=1 Intercept answers True with an
    /// EMPTY replacement for every frame, so a guard can prove the relay
    /// declines it (run_lsp_proxy_stub_modes_guard.ps1 case f). With
    /// DRAGLINT_MERGE_TEST_FASTPATH=1 every didChange taken by the bounded head
    /// scan (no JSON parse) writes one stderr line, so a guard can prove that
    /// path runs (run_lsp_proxy_merge_diagnostics_guard.ps1 case g2).</remarks>
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
    /// and at least one of them has a (label, kind) the reply lacks; (3) an S&gt;C
    /// reply to a recorded textDocument/hover request when MergeHover is on and
    /// drag-lint's hover markdown is non-empty and was computed within
    /// MergeBudgetMs of the request; (4) an S&gt;C reply to a recorded
    /// textDocument/definition when MergeDefinition is on, the reply's result
    /// is null or [] and drag-lint found at least one location within
    /// MergeBudgetMs (the result becomes drag-lint's Location[]); (5) the S&gt;C
    /// reply to the recorded initialize when MergeDefinition is on and its
    /// capabilities lack referencesProvider or workspaceSymbolProvider (the
    /// missing ones are added as true). False otherwise: the relay forwards the
    /// original bytes. Under the test seam (see Create): True with an empty
    /// replacement.</returns>
    /// <remarks>
    /// <para>Hover merge (spec criteria 15, 16): DelphiLSP's contents present
    /// and drag-lint's non-empty -> contents becomes a markdown MarkupContent
    /// whose value is DelphiLSP's text, LF LF '---' LF LF, then drag-lint's;
    /// every other field of the reply (range) is kept. DelphiLSP's contents is
    /// normalised to markdown FIRST: a MarkupContent keeps its value, a
    /// MarkedString string stays as is, a (language, value) MarkedString
    /// becomes a fenced code block, an array joins its normalised parts with
    /// LF LF. DelphiLSP null -> drag-lint's markdown alone; neither, drag-lint
    /// empty, an error reply, over budget or an exception -> DelphiLSP's bytes
    /// forwarded unchanged.</para>
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
    /// <summary>The relay's C&gt;S answerer (TFrameAnswerer) for this engine.</summary>
    /// <param name="AFrame">Buffer holding the frame at offset 0.</param>
    /// <param name="ALen">Byte length of the frame.</param>
    /// <param name="AOnTake">Called once, at the commit point, before the reply
    /// can be written (see TFrameAnswerer); may be nil.</param>
    /// <returns>True for a textDocument/references or workspace/symbol request
    /// (one with an id) when MergeDefinition is on, ClientWriter is set and
    /// DelphiLSP's initialize reply did not advertise that provider: drag-lint
    /// answers it (TLSPServer.ComputeReferences / ComputeWorkspaceSymbols, on
    /// the merge worker) and the relay must NOT forward it. True also for a
    /// $/cancelRequest whose params.id is a request Answer took and has not
    /// seen cancelled yet: it is consumed and nothing is written (DelphiLSP
    /// never saw that id; group-4 P1). False otherwise, and for a frame that
    /// does not parse.</returns>
    /// <remarks>Once True for a request, exactly one reply is written through
    /// ClientWriter: [] when no index opens, the computation raises (one stderr
    /// line) or the worker queue is full. The C&gt;S pump never waits for the
    /// worker. The taken ids are remembered on the C&gt;S pump thread only (no
    /// lock), at most ANSWERED_IDS_MAX of them; past that the set restarts.
    /// Test seam: DRAGLINT_MERGE_TEST_ANSWER_INLINE=1 replies [] inline on the
    /// C&gt;S pump, as the queue-full path does (run_lsp_proxy_trace_guard.ps1).</remarks>
    function Answer(const AFrame: TBytes; ALen: Integer; const AOnTake: TProc = nil): Boolean;
    /// <summary>Waits until every request Answer took has been replied to.</summary>
    /// <param name="ATimeoutMs">Longest wait, in milliseconds.</param>
    /// <returns>True when none is outstanding (any more).</returns>
    /// <remarks>RunLspProxy calls it once the S&gt;C stream ended, so a reply
    /// still being computed is not lost to process exit.</remarks>
    function WaitForAnswers(ATimeoutMs: Cardinal): Boolean;
    /// <summary>Where Answer's replies go; set by RunLspProxy before any pump
    /// starts. Unset, Answer declines every frame.</summary>
    property ClientWriter: TClientWriter write FClientWriter;
    /// <summary>The drag-lint LSP server over the index, created on first
    /// use: Options.DbPaths, or Options.ResolveDbs() when that list is empty
    /// (P0 review I1: resolved lazily, never on the relay's startup path).
    /// Paths that do not exist are dropped before the server is created; when
    /// only some are missing, one stderr line names them.</summary>
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
  , DRagLint.Core.Interfaces
  , DRagLint.Core.LiveDocs
  , DRagLint.LSP.Completion
  ;

type
  { What a recorded request is; it decides who computes ours and how the reply
    is merged. rkInitialize computes nothing (A5: the reply's capabilities). }
  TRequestKind = (rkCompletion, rkHover, rkDefinition, rkInitialize);

  { One recorded textDocument/completion, hover, definition or initialize
    request: where the caret was, and drag-lint's answer once the worker
    computed it (FItems: the completion items or the definition locations as a
    JSON array, or the hover markdown; '' for none; FKind tells which). Shared
    by the C>S pump
    (creates it), the merge worker (fills it) and the S>C pump (reads it), so it
    is reference counted: whoever releases last frees it. FItems / FErr /
    FElapsed are written before Done is set and read only after it is. }
  TPendingRequest = class
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
    FKind     : TRequestKind;
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
  METHOD_HOVER = 'textDocument/hover';
  MERGE_HOVER_PREFIX = 'drag-lint lsp --proxy: merge-hover ';
  METHOD_DEFINITION       = 'textDocument/definition';
  METHOD_INITIALIZE       = 'initialize';
  METHOD_REFERENCES       = 'textDocument/references';
  METHOD_WORKSPACE_SYMBOL = 'workspace/symbol';
  METHOD_CANCEL_REQUEST   = '$/cancelRequest';
  { Proxy-answered ids remembered for a later $/cancelRequest (group-4 P1). }
  ANSWERED_IDS_MAX = 1024;
  { How far into a body HeadStringValue looks (group-4 P3). }
  HEAD_SCAN_BYTES = 4096;
  { Depths HeadStringValue matches at: the top-level object, and
    params.textDocument (depth 3). }
  JSON_DEPTH_TOP           = 1;
  JSON_DEPTH_TEXT_DOCUMENT = 3;
  { JSON white space: tab, LF, CR, space. }
  JSON_WS: set of Byte = [9, 10, 13, 32];
  MERGE_DEFINITION_PREFIX = 'drag-lint lsp --proxy: merge-definition ';
  CAP_REFERENCES       = 'referencesProvider';
  CAP_WORKSPACE_SYMBOL = 'workspaceSymbolProvider';
  { Between DelphiLSP's hover text and drag-lint's facts (spec criterion 15). }
  HOVER_SEPARATOR = #10#10'---'#10#10;
  { Bounds that keep a client that never sees a reply (cancelled requests) or a
    burst of keystrokes from growing the engine's state without limit. }
  QUEUE_MAX   = 8;
  PENDING_MAX = 64;

constructor TPendingRequest.Create(const APath: string; ALine1, ACol1: Integer);
begin
  inherited Create;
  FRefs     := 1;
  FPath     := APath;
  FLine1    := ALine1;
  FCol1     := ACol1;
  FStartTick:= GetTickCount64;
  FDone     := TEvent.Create(nil, True, False, '');
end;

destructor TPendingRequest.Destroy;
begin
  FDone.Free;
  inherited Destroy;
end;

procedure TPendingRequest.AddRef;
begin
  TInterlocked.Increment(FRefs);
end;

procedure TPendingRequest.Release;
begin
  if TInterlocked.Decrement(FRefs) = 0 then Free;
end;

{ The stderr prefix of the merge a request kind belongs to. }
function PrefixOf(AKind: TRequestKind): string;
begin
  case AKind of
    rkHover                    : Result:= MERGE_HOVER_PREFIX;
    rkDefinition, rkInitialize : Result:= MERGE_DEFINITION_PREFIX;
    else Result:= MERGE_COMPLETION_PREFIX;
  end;
end;

{ The word a budget line uses for a request kind. }
function KindName(AKind: TRequestKind): string;
begin
  case AKind of
    rkHover     : Result:= 'hover';
    rkDefinition: Result:= 'definition';
    rkInitialize: Result:= 'initialize';
    else Result:= 'completion';
  end;
end;

{ True when a server capability value advertises the feature: present and
  neither false nor null (true, or an options object). A5 fix M3. }
function Advertises(const AValue: TJSONValue): Boolean;
begin
  Result:= (AValue <> nil) and not (AValue is TJSONNull) and
           not ((AValue is TJSONBool) and not TJSONBool(AValue).AsBoolean);
end;

{ True when a definition reply's result says "nothing here": null or an empty
  array (A5: only then is drag-lint's answer used). }
function IsEmptyLocations(const AResult: TJSONValue): Boolean;
begin
  Result:= (AResult is TJSONNull) or ((AResult is TJSONArray) and (TJSONArray(AResult).Count = 0));
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

{ A hover reply's contents as markdown text, whatever shape it came in: a
  MarkupContent keeps its value; a MarkedString string stays as is; a
  (language, value) MarkedString becomes a fenced code block; an array joins
  its normalised, non-empty parts with a blank line. '' for anything else. }
function HoverContentsToMarkdown(const AContents: TJSONValue): string;
var
  Obj : TJSONObject;
  Lang: TJSONValue;
  Val : TJSONValue;
  Elem: TJSONValue;
  Part: string;
begin
  Result:= '';
  if AContents is TJSONArray then
  begin
    for Elem in TJSONArray(AContents) do
    begin
      Part:= HoverContentsToMarkdown(Elem);
      if Part = '' then Continue;
      Result:= if Result = '' then Part else Result + #10#10 + Part;
    end;
  end
  else if AContents is TJSONObject then
  begin
    Obj := TJSONObject(AContents);
    Val := Obj.GetValue('value');
    Lang:= Obj.GetValue('language');
    if not (Val is TJSONString) then Exit;
    if (Obj.GetValue('kind') = nil) and (Lang is TJSONString) then
      Result:= '```' + Lang.Value + #10 + Val.Value + #10 + '```'
    else Result:= Val.Value;
  end
  else if (AContents is TJSONString) and not (AContents is TJSONNumber) then Result:= AContents.Value;
end;

{ Puts drag-lint's hover markdown AOurs (non-empty) into AReply's result:
  a null result becomes a markdown MarkupContent of AOurs alone; an object
  result gets its contents replaced by a markdown MarkupContent of DelphiLSP's
  normalised text, the separator, then AOurs (AOurs alone when DelphiLSP's text
  is empty); its other fields are kept. Returns True when AReply was changed. }
function MergeHoverResult(const AReply: TJSONObject; const AOurs: string): Boolean;
var
  Res     : TJSONValue;
  Theirs  : string;
  Contents: TJSONObject;
begin
  Res:= AReply.GetValue('result');
  if not ((Res is TJSONNull) or (Res is TJSONObject)) then Exit(False);
  Theirs:= if Res is TJSONObject then HoverContentsToMarkdown(TJSONObject(Res).GetValue('contents')) else '';
  Contents:= TJSONObject.Create;
  Contents.AddPair('kind', 'markdown');
  Contents.AddPair('value', if Theirs = '' then AOurs else Theirs + HOVER_SEPARATOR + AOurs);
  if Res is TJSONNull then
  begin
    Res:= TJSONObject.Create;
    AReply.RemovePair('result').Free;
    AReply.AddPair('result', Res);
  end
  else TJSONObject(Res).RemovePair('contents').Free;
  TJSONObject(Res).AddPair('contents', Contents);
  Result:= True;
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

{ Group-4 P3: index of the first body byte of the frame, or -1 when no header
  terminator lies within ALen. }
function BodyStart(const AFrame: TBytes; ALen: Integer): Integer;
var
  I, K: Integer;
begin
  Result:= -1;
  if ALen > Length(AFrame) then ALen:= Length(AFrame);
  for I:= 0 to ALen - Length(HEADER_END) do
  begin
    K:= 0;
    while (K < Length(HEADER_END)) and (AFrame[I + K] = HEADER_END[K]) do Inc(K);
    if K = Length(HEADER_END) then Exit(I + Length(HEADER_END));
  end;
end;

{ Group-4 P3: reads the JSON string that starts at AAt (after optional white
  space) and ends before AStop. False when there is none, it runs past AStop,
  or it holds an escape (the caller then parses the whole body). }
function ReadPlainString(const AFrame: TBytes; AAt, AStop: Integer; out AValue: string): Boolean;
var
  J, Start: Integer;
begin
  Result:= False;
  AValue:= '';
  J:= AAt;
  while (J < AStop) and (AFrame[J] in JSON_WS) do Inc(J);
  if (J >= AStop) or (AFrame[J] <> Ord('"')) then Exit;
  Inc(J);
  Start:= J;
  while (J < AStop) and (AFrame[J] <> Ord('"')) and (AFrame[J] <> Ord('\')) do Inc(J);
  if (J >= AStop) or (AFrame[J] <> Ord('"')) then Exit;
  AValue:= TEncoding.UTF8.GetString(AFrame, Start, J - Start);
  Result:= True;
end;

{ Group-4 P3: the string value of key AKey at nesting depth ADepth (1 = the
  top-level object; braces and brackets both count), found within the first
  HEAD_SCAN_BYTES of the frame's body by a byte-level tokenizer -- no decode,
  no parse. Strings are skipped whole (escapes honoured), so a key-like text
  inside a string never matches, and a key at another depth is ignored (fix
  round: a nested "method" must not pass for the frame's own). False when the
  key is not in the head, a string runs past the head, or the value is not a
  plain unescaped string: the caller then parses the whole body, so the
  answer is never a guess. }
function HeadStringValue(const AFrame: TBytes; ALen: Integer; const AKey: string; ADepth: Integer;
  out AValue: string): Boolean;
var
  Key  : TBytes;
  Body : Integer;
  Stop : Integer;
  I    : Integer;
  J    : Integer;
  K    : Integer;
  Depth: Integer;
  Esc  : Boolean;
begin
  Result:= False;
  AValue:= '';
  Body  := BodyStart(AFrame, ALen);
  if Body < 0 then Exit;
  if ALen > Length(AFrame) then ALen:= Length(AFrame);
  Stop := if ALen < Body + HEAD_SCAN_BYTES then ALen else Body + HEAD_SCAN_BYTES;
  Key  := TEncoding.ASCII.GetBytes(AKey);
  Depth:= 0;
  I    := Body;
  while I < Stop do
  begin
    case AFrame[I] of
      Ord('{'), Ord('['): Inc(Depth);
      Ord('}'), Ord(']'): Dec(Depth);
      Ord('"'):
        begin
          J  := I + 1;
          Esc:= False;
          while (J < Stop) and (AFrame[J] <> Ord('"')) do
          begin
            if AFrame[J] = Ord('\') then
            begin
              Esc:= True;
              Inc(J);
            end;
            Inc(J);
          end;
          if J >= Stop then Exit;   { the string runs past the head }
          K:= 0;
          if (Depth = ADepth) and not Esc and (J - I - 1 = Length(Key)) then
            while (K < Length(Key)) and (AFrame[I + 1 + K] = Key[K]) do Inc(K);
          if (K = Length(Key)) and (K > 0) then
          begin
            K:= J + 1;
            while (K < Stop) and (AFrame[K] in JSON_WS) do Inc(K);
            if (K < Stop) and (AFrame[K] = Ord(':')) then Exit(ReadPlainString(AFrame, K + 1, Stop, AValue));
          end;
          I:= J;   { the closing quote; stepped over below }
        end;
    end;
    Inc(I);
  end;
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
  FTestAnswerInline    := GetEnvironmentVariable('DRAGLINT_MERGE_TEST_ANSWER_INLINE') = '1';
  FTestFastPath        := GetEnvironmentVariable('DRAGLINT_MERGE_TEST_FASTPATH') = '1';
  FAnsweredIds         := TDictionary<string, Boolean>.Create;
  FDirty    := TDictionary<string, Boolean>.Create;
  FDirtyLock:= TCriticalSection.Create;
  FQueue      := TQueue<TProc>.Create;
  FPending    := TDictionary<string, TObject>.Create;
  FPendingLock:= TCriticalSection.Create;
  FDocUpdates := TDictionary<string, TDocUpdate>.Create;
  FDocLock    := TCriticalSection.Create;
  FAnswersIdle:= TEvent.Create(nil, True, True, '');
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
  for var Left: TObject in FPending.Values do TPendingRequest(Left).Release;
  FPending.Free;
  FPendingLock.Free;
  FDocUpdates.Free;
  FDocLock.Free;
  FAnswersIdle.Free;
  FQueue.Free;
  FDirty.Free;
  FDirtyLock.Free;
  FAnsweredIds.Free;
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
  Gone : TArray<string>;
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
        Gone := nil;
        for D in Dbs do
          if FileExists(D) then Found:= Found + [D] else Gone:= Gone + [D];
        { Checked here, not left to TLSPServer.Create: it skips a missing path
          with a line of its own and opens nothing, which would cost the
          session a second, less specific stderr line. }
        if Length(Found) = 0 then
          MergeErrLine('drag-lint lsp --proxy: merge disabled, no index database found (' +
                       (if Length(Dbs) = 0 then 'no --db and none resolved' else string.Join(', ', Dbs)) +
                       '); relaying DelphiLSP unchanged.')
        else
        begin
          { A3 fix 4: a partly missing list is named, in one line; the merge
            goes on with the paths that exist. }
          if Length(Gone) > 0 then
            MergeErrLine('drag-lint lsp --proxy: merge index database(s) not found, skipped (' +
                         string.Join(', ', Gone) + '); merging from the rest.');
          FServer:= TLSPServer.Create(Found);
        end;
      except
        on E: Exception do
        begin
          FServer:= nil;
          MergeErrLine('drag-lint lsp --proxy: merge disabled, cannot open the index (' +
                       E.ClassName + ': ' + E.Message + '); relaying DelphiLSP unchanged.');
        end;
      end;
    end;
    { LSP-1 CORE: the IDE's .delphilsp.json names the active project + platform. }
    if (FServer <> nil) and (FPendingSettingsFile <> '') then
    begin
      FServer.ApplyClientSettingsFile(FPendingSettingsFile);
      FPendingSettingsFile:= '';
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

{ Merge worker only (no lock: the linter is touched on no other thread). The
  first call runs Options.PrepareLint -- the CLI's lint preprocessing setup, the
  same routine plain `lsp` runs at startup (C14) -- and then creates the linter,
  so the first publish is already linted from the preprocessed text. }
procedure TProxyMergeEngine.EnsureLinter;
begin
  if FLinter <> nil then Exit;
  if Assigned(FOptions.PrepareLint) then FOptions.PrepareLint();
  FLinter:= TLinter.Create('');
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
        if FOptions.MergeDiagnostics then EnsureLinter;
        if FOptions.MergeCompletion or FOptions.MergeHover or FOptions.MergeDefinition then Server;   { opens the index; a failure is reported there }
      finally
        TInterlocked.Exchange(FWarming, 0);
      end;
    end) then
    TInterlocked.Exchange(FWarming, 0);
end;

{ C>S: with MergeDiagnostics, didChange marks the document dirty and didSave /
  didOpen / didClose clear it; with MergeCompletion or MergeHover, the text the notification
  implies is queued for the live-document overlay. A first didOpen also warms
  the worker. Runs on the C>S pump thread, inline (no worker, no FCallLock). }
{ C>S, didOpen: queues (never waits) the announcement of the file's context on the
  merge worker: the embedded server then sends draglint/context with its notice
  through the client writer and starts the background re-index of a project DB
  marked needs-re-resolve (once per DB: the server keys the run by DB). Needs
  the server, so only when an index-backed merge is on and a writer is set. }
procedure TProxyMergeEngine.AnnounceOpen(const APath: string);
begin
  if not (FOptions.MergeCompletion or FOptions.MergeHover or FOptions.MergeDefinition) or not Assigned(FClientWriter) then Exit;
  Enqueue(
    procedure
    var
      S: TLSPServer;
    begin
      S:= Server;
      if S = nil then Exit;
      S.EnableProxyNotices(
        procedure(AJson: string)
        begin
          FClientWriter(BuildFrame(TEncoding.UTF8.GetBytes(AJson)));
        end);
      S.AnnounceProxyOpen(APath);
    end);
end;

procedure TProxyMergeEngine.TrackDocument(const AFrame: TBytes; ALen: Integer);
var
  Json  : TJSONValue;
  Method: string;
  Uri   : string;
  Key   : string;
  Path  : string;
  LiveText: string;
  Upd   : TLiveUpdate;
  DirtyOnly: Boolean;
begin
  if not FrameContains(AFrame, ALen, METHOD_DID_PREFIX) then Exit;
  { Group-4 P3: with no overlay to feed, a didChange only marks its URI dirty,
    so method and uri are read from the head of the body and the (possibly
    whole-file) text is never parsed. Anything the scan cannot read for
    certain falls through to the full parse below. }
  DirtyOnly:= FOptions.MergeDiagnostics and not (FOptions.MergeCompletion or FOptions.MergeHover or FOptions.MergeDefinition);
  if DirtyOnly and HeadStringValue(AFrame, ALen, 'method', JSON_DEPTH_TOP, Method) and (Method = METHOD_DID_CHANGE)
     and HeadStringValue(AFrame, ALen, 'uri', JSON_DEPTH_TEXT_DOCUMENT, Uri) then
  begin
    if FTestFastPath then MergeErrLine(MERGE_ERR_PREFIX + 'test: didChange read from the head (no parse).');
    FDirtyLock.Enter;
    try
      FDirty.AddOrSetValue(DocKey(TLSPServer.FileFromUri(Uri)), True);
    finally
      FDirtyLock.Leave;
    end;
    Exit;
  end;
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
      if FOptions.MergeCompletion or FOptions.MergeHover or FOptions.MergeDefinition then
      begin
        Upd:= LiveUpdateOf(Method, Json, LiveText);
        if Upd <> luNone then QueueDocUpdate(Path, Upd = luRemove, LiveText);
      end;
      if Method = METHOD_DID_OPEN then
      begin
        WarmUp;
        AnnounceOpen(Path);
      end;
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

{ C>S: records a textDocument/completion (MergeCompletion) or
  textDocument/hover (MergeHover) request by id and queues drag-lint's answer
  for it on the worker at once, so it is usually ready before DelphiLSP
  answers. Never delays the frame beyond one JSON parse. }
procedure TProxyMergeEngine.RecordRequest(const AFrame: TBytes; ALen: Integer);  // dl:ok too-many-exit-points@3bc9, cyclomatic-complexity@13e4 -- each Exit is a decline (nothing recorded, relay unchanged); one flat guard sequence reads better than nesting (re-reviewed A5: 8 exits; the four request kinds share one parse, so the kind selection adds branches, not state)
var
  Json  : TJSONValue;
  Method: string;
  Uri   : string;
  IdVal : TJSONValue;
  PosObj: TJSONObject;
  P     : TPendingRequest;
  Key   : string;
  Old   : TObject;
  Full  : Boolean;
  Hover : Boolean;
  Comp  : Boolean;
  Def   : Boolean;
  Init  : Boolean;
  Kind  : TRequestKind;
  Path  : string;
  Line0 : Integer;
  Col0  : Integer;
begin
  Comp := FOptions.MergeCompletion and (TInterlocked.CompareExchange(FCompletionOff, 0, 0) = 0)
          and FrameContains(AFrame, ALen, METHOD_COMPLETION);
  Hover:= FOptions.MergeHover and (TInterlocked.CompareExchange(FHoverOff, 0, 0) = 0)
          and FrameContains(AFrame, ALen, METHOD_HOVER);
  Def  := FOptions.MergeDefinition and (TInterlocked.CompareExchange(FDefinitionOff, 0, 0) = 0)
          and FrameContains(AFrame, ALen, METHOD_DEFINITION);
  Init := FOptions.MergeDefinition and FrameContains(AFrame, ALen, '"' + METHOD_INITIALIZE + '"');
  if not (Comp or Hover or Def or Init) then Exit;
  Kind:= rkCompletion;
  try
    Json:= TJSONObject.ParseJSONValue(FrameBody(AFrame, ALen));
    try
      if not (Json is TJSONObject) then Exit;
      if not Json.TryGetValue<string>('method', Method) then Exit;
      if Hover and (Method = METHOD_HOVER) then Kind:= rkHover
      else if Comp and (Method = METHOD_COMPLETION) then Kind:= rkCompletion
      else if Def and (Method = METHOD_DEFINITION) then Kind:= rkDefinition
      else if Init and (Method = METHOD_INITIALIZE) then Kind:= rkInitialize
      else Exit;
      IdVal:= TJSONObject(Json).GetValue('id');
      if IdVal = nil then Exit;
      Path := '';
      Line0:= 0;
      Col0 := 0;
      if Kind <> rkInitialize then
      begin
        if not Json.TryGetValue<string>('params.textDocument.uri', Uri)
           or not Json.TryGetValue<TJSONObject>('params.position', PosObj)
           { A3 fix 3: a position without line / character is not ours to answer;
             relayed untouched, silently (it used to raise an access violation
             and write one stderr line per request). }
           or not PosObj.TryGetValue<Integer>('line', Line0)
           or not PosObj.TryGetValue<Integer>('character', Col0) then Exit;
        Path:= TLSPServer.FileFromUri(Uri);
      end;
      { The position exactly as TLSPServer.HandleCompletion converts it: LSP is
        0-based, the completion builder 1-based (hover and definition convert
        back). }
      P:= TPendingRequest.Create(Path, Line0 + 1, Col0 + 1);  // dl:ok object-leak@f6d1 -- reference counted: owned by FPending (or Release on the Full path) and by the job (AddRef/Release); Release frees
      P.FKind:= Kind;
      { initialize: nothing to compute; MergeReply edits the capabilities. }
      if Kind = rkInitialize then P.FDone.SetEvent;
      Key:= IdVal.ToJSON;
      FPendingLock.Enter;
      try
        Full:= FPending.Count >= PENDING_MAX;
        if not Full then
        begin
          if FPending.TryGetValue(Key, Old) then TPendingRequest(Old).Release;   { a reused id: the stale entry goes }
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
      if Kind = rkInitialize then Exit;
      P.AddRef;   { the job's reference }
      if not Enqueue(
        procedure
        begin
          case P.FKind of
            rkHover     : ComputeHover(P);
            rkDefinition: ComputeDefinition(P);
            else ComputeCompletion(P);
          end;
        end) then
      begin
        { A4 fix M3: the queue is full, so nothing will ever answer for this
          id; drop its entry too, or its reply would wait out the budget. }
        P.Release;   { the job's reference }
        FPendingLock.Enter;
        try
          if FPending.TryGetValue(Key, Old) and (Old = P) then
          begin
            FPending.Remove(Key);
            P.Release;   { FPending's reference }
          end;
        finally
          FPendingLock.Leave;
        end;
      end;
    finally
      Json.Free;
    end;
  except
    on E: Exception do
      MergeErrLine(PrefixOf(Kind) + 'could not record a request (' + E.ClassName + ': ' + E.Message + ').');
  end;
end;

{ Worker thread: drag-lint's definition locations for one recorded request
  (TLSPServer.ComputeDefinition, the plain server's own F12). Publishes only
  through the record, like ComputeHover. No index turns the definition
  fallback off for the session (Server reports the failure once). }
procedure TProxyMergeEngine.ComputeDefinition(APending: TObject);
var
  P  : TPendingRequest;
  S  : TLSPServer;
  Arr: TJSONArray;
begin
  P:= TPendingRequest(APending);
  try
    try
      FlushDocUpdates;
      S:= Server;
      if S = nil then TInterlocked.Exchange(FDefinitionOff, 1)
      else
      begin
        Arr:= S.ComputeDefinition(P.FPath, P.FLine1 - 1, P.FCol1 - 1);
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

{ S>C, the reply to the recorded initialize: sets referencesProvider and
  workspaceSymbolProvider to true when absent, false or null, and notes
  which ones DelphiLSP advertised itself (Answer then leaves those requests to
  it). Returns True when AReply was changed. }
function TProxyMergeEngine.MergeInitialize(const AReply: TJSONObject): Boolean;
var
  Res : TJSONValue;
  Caps: TJSONValue;
begin
  Result:= False;
  Res:= AReply.GetValue('result');
  if not (Res is TJSONObject) then Exit;
  Caps:= TJSONObject(Res).GetValue('capabilities');
  if Caps = nil then
  begin
    Caps:= TJSONObject.Create;
    TJSONObject(Res).AddPair('capabilities', Caps);
  end
  else if not (Caps is TJSONObject) then Exit;
  if Advertises(TJSONObject(Caps).GetValue(CAP_REFERENCES)) then TInterlocked.Exchange(FTheirReferences, 1)
  else
  begin
    TJSONObject(Caps).RemovePair(CAP_REFERENCES).Free;   { false / null: replaced }
    TJSONObject(Caps).AddPair(CAP_REFERENCES, TJSONBool.Create(True));
    Result:= True;
  end;
  if Advertises(TJSONObject(Caps).GetValue(CAP_WORKSPACE_SYMBOL)) then TInterlocked.Exchange(FTheirSymbols, 1)
  else
  begin
    TJSONObject(Caps).RemovePair(CAP_WORKSPACE_SYMBOL).Free;
    TJSONObject(Caps).AddPair(CAP_WORKSPACE_SYMBOL, TJSONBool.Create(True));
    Result:= True;
  end;
end;

{ C>S pump: consumes a $/cancelRequest for an id Answer took (group-4 P1).
  DelphiLSP never saw that request, so the cancel is not forwarded; the reply
  (already written or still on the worker) is unaffected. }
function TProxyMergeEngine.TakeCancel(const AFrame: TBytes; ALen: Integer; const AOnTake: TProc): Boolean;
var
  Json : TJSONValue;
  Id   : string;
  IdVal: TJSONValue;
begin
  Result:= False;
  if (FAnsweredIds.Count = 0) or not FrameContains(AFrame, ALen, METHOD_CANCEL_REQUEST) then Exit;
  Id:= '';
  try
    Json:= TJSONObject.ParseJSONValue(FrameBody(AFrame, ALen));
    try
      if (Json is TJSONObject) and (TJSONObject(Json).GetValue<string>('method', '') = METHOD_CANCEL_REQUEST) then
      begin
        IdVal:= Json.FindValue('params.id');
        if IdVal <> nil then Id:= IdVal.ToJSON;
      end;
    finally
      Json.Free;
    end;
  except
    on Exception do Exit(False);   { unreadable: forwarded, as before }
  end;
  if (Id = '') or not FAnsweredIds.ContainsKey(Id) then Exit;
  FAnsweredIds.Remove(Id);
  if Assigned(AOnTake) then AOnTake;
  Result:= True;
end;

function TProxyMergeEngine.Answer(const AFrame: TBytes; ALen: Integer; const AOnTake: TProc): Boolean;  // dl:ok too-many-exit-points@7911 -- each Exit before the commit point is a decline (the frame is forwarded); one flat guard sequence reads better than nesting
var
  Json  : TJSONValue;
  Method: string;
  Uri   : string;
  IdVal : TJSONValue;
  IncDecl: TJSONValue;
  Refs  : Boolean;
  Syms  : Boolean;
  Job   : TAnswerJob;
begin
  Result:= False;
  if not FOptions.MergeDefinition or not Assigned(FClientWriter) then Exit;
  if TakeCancel(AFrame, ALen, AOnTake) then Exit(True);
  Refs:= (TInterlocked.CompareExchange(FTheirReferences, 0, 0) = 0) and FrameContains(AFrame, ALen, METHOD_REFERENCES);
  Syms:= (TInterlocked.CompareExchange(FTheirSymbols, 0, 0) = 0) and FrameContains(AFrame, ALen, METHOD_WORKSPACE_SYMBOL);
  if not (Refs or Syms) then Exit;
  Method:= '';
  try
    Json:= TJSONObject.ParseJSONValue(FrameBody(AFrame, ALen));
    try
      if not (Json is TJSONObject) or not Json.TryGetValue<string>('method', Method) then Exit;
      Refs:= Refs and (Method = METHOD_REFERENCES);
      Syms:= Syms and (Method = METHOD_WORKSPACE_SYMBOL);
      if not (Refs or Syms) then Exit;
      IdVal:= TJSONObject(Json).GetValue('id');
      if IdVal = nil then Exit;   { a notification of that name is not a request we owe }
      Job.Id         := IdVal.ToJSON;
      Job.Symbols    := Syms;
      Job.Query      := '';
      Job.Path       := '';
      Job.Line0      := 0;
      Job.Col0       := 0;
      Job.IncludeDecl:= True;   { as TLSPServer.HandleReferences defaults it }
      if Syms then
      begin
        if not Json.TryGetValue<string>('params.query', Job.Query) then Job.Query:= '';
      end
      else
      begin
        if Json.TryGetValue<string>('params.textDocument.uri', Uri) and
           Json.TryGetValue<Integer>('params.position.line', Job.Line0) and
           Json.TryGetValue<Integer>('params.position.character', Job.Col0) then
          Job.Path:= TLSPServer.FileFromUri(Uri);
        IncDecl:= Json.FindValue('params.context.includeDeclaration');
        if IncDecl is TJSONBool then Job.IncludeDecl:= TJSONBool(IncDecl).AsBoolean;
      end;
    finally
      Json.Free;
    end;
  except
    on E: Exception do
    begin
      MergeErrLine(MERGE_DEFINITION_PREFIX + 'could not read a ' + Method + ' request (' + E.ClassName + ': ' +
                   E.Message + '); forwarded to DelphiLSP.');
      Exit(False);
    end;
  end;
  { From here the request is ours: exactly one reply, [] at worst. }
  if Assigned(AOnTake) then AOnTake;   { P2: the relay traces C>P before any reply exists }
  { After the callback: a raising AOnTake forwards the frame, and an id left
    behind would then swallow DelphiLSP's legitimate cancel for it. }
  if FAnsweredIds.Count >= ANSWERED_IDS_MAX then FAnsweredIds.Clear;
  FAnsweredIds.AddOrSetValue(Job.Id, True);
  FStateLock.Enter;
  try
    Inc(FAnswersOut);
    FAnswersIdle.ResetEvent;
  finally
    FStateLock.Leave;
  end;
  if FTestAnswerInline or not Enqueue(
    procedure
    begin
      AnswerOnWorker(Job);
    end) then
  begin
    SendAnswer(Job.Id, '[]');
    EndAnswer;
  end;
  Result:= True;
end;

{ Worker thread: computes and writes the reply to one request Answer took. }
procedure TProxyMergeEngine.AnswerOnWorker(const AJob: TAnswerJob);
var
  S   : TLSPServer;
  Arr : TJSONArray;
  Body: string;
begin
  Body:= '[]';
  try
    try
      FlushDocUpdates;
      S:= Server;
      Arr:= nil;
      if S <> nil then
        if AJob.Symbols then Arr:= S.ComputeWorkspaceSymbols(AJob.Query)
        else if AJob.Path <> '' then Arr:= S.ComputeReferences(AJob.Path, AJob.Line0, AJob.Col0, AJob.IncludeDecl);
      if Arr <> nil then
        try
          Body:= Arr.ToJSON;
        finally
          Arr.Free;
        end;
    except
      on E: Exception do
        MergeErrLine(MERGE_DEFINITION_PREFIX + 'answered a request with [] (' + E.ClassName + ': ' + E.Message + ').');
    end;
    SendAnswer(AJob.Id, Body);
  finally
    EndAnswer;
  end;
end;

{ Writes the JSON-RPC reply (id AId, result AResultJson) to the client. }
procedure TProxyMergeEngine.SendAnswer(const AId, AResultJson: string);
begin
  try
    FClientWriter(BuildFrame(TEncoding.UTF8.GetBytes('{"jsonrpc":"2.0","id":' + AId + ',"result":' + AResultJson + '}')));
  except
    on E: Exception do
      MergeErrLine(MERGE_DEFINITION_PREFIX + 'could not write a reply (' + E.ClassName + ': ' + E.Message + ').');
  end;
end;

{ One request Answer took has been replied to. }
procedure TProxyMergeEngine.EndAnswer;
begin
  FStateLock.Enter;
  try
    Dec(FAnswersOut);
    if FAnswersOut <= 0 then FAnswersIdle.SetEvent;
  finally
    FStateLock.Leave;
  end;
end;

function TProxyMergeEngine.WaitForAnswers(ATimeoutMs: Cardinal): Boolean;
begin
  Result:= FAnswersIdle.WaitFor(ATimeoutMs) = wrSignaled;
end;

{ Worker thread: drag-lint's hover markdown for one recorded request, the
  same text plain `lsp` answers (TLSPServer.ComputeHoverMarkdown, which reads
  the live-document overlay). Publishes only through the record, like
  ComputeCompletion. No index turns hover merging off for the session (Server
  reports the failure once). }
procedure TProxyMergeEngine.ComputeHover(APending: TObject);
var
  P: TPendingRequest;
  S: TLSPServer;
begin
  P:= TPendingRequest(APending);
  try
    try
      FlushDocUpdates;
      S:= Server;
      if S = nil then TInterlocked.Exchange(FHoverOff, 1)
      else P.FItems:= S.ComputeHoverMarkdown(P.FPath, P.FLine1 - 1, P.FCol1 - 1);
    except   { not swallowed: the message is published through P.FErr and logged by the S>C side }
      on E: Exception do P.FErr:= E.ClassName + ': ' + E.Message;
    end;
  finally
    P.FElapsed:= GetTickCount64 - P.FStartTick;
    P.FDone.SetEvent;
    P.Release;
  end;
end;

{ Worker thread: drag-lint's items for one recorded request. Publishes only
  through the record (Items / Err / Elapsed, then Done) and releases the job's
  reference. No store at all turns completion merging off for the session,
  with one stderr line (Server reports its own failures). }
procedure TProxyMergeEngine.ComputeCompletion(APending: TObject);
var
  P     : TPendingRequest;
  S     : TLSPServer;
  Stores: TArray<ISymbolStore>;
  Arr   : TJSONArray;
begin
  P:= TPendingRequest(APending);
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
        { A3 fix 2: the stores for THIS file, as HandleCompletion picks them,
          so a file no index owns still gets its own declarations. }
        Arr:= TLspCompletion.BuildCompletionItems(S.StoresForFile(P.FPath), P.FPath, P.FLine1, P.FCol1);
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
  unioned in; a reply to a recorded hover request gets drag-lint's markdown
  merged in (see Intercept). Waits for drag-lint's answer at most the part of
  the budget left since the request. Runs on the S>C pump thread. }
function TProxyMergeEngine.MergeReply(const AFrame: TBytes; ALen: Integer;  // dl:ok too-many-exit-points@368d -- each Exit is a fail-open decline (forward the original frame); one flat guard sequence reads better than nesting (re-reviewed A5: 13, the initialize and definition branches decline early so a reply never waits needlessly)
  out AReplacement: TBytes): Boolean;
var
  Json  : TJSONValue;
  IdVal : TJSONValue;
  Obj   : TObject;
  P     : TPendingRequest;
  Remain: Int64;
  Ours  : TJSONValue;
  Empty : Boolean;
  Prefix: string;
  Warned: Integer;
begin
  Prefix:= MERGE_COMPLETION_PREFIX;
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
          P:= TPendingRequest(Obj);
        end;
      finally
        FPendingLock.Leave;
      end;
      if (P = nil) or (TJSONObject(Json).GetValue('result') = nil) then Exit;   { not ours, or an error reply }
      Prefix:= PrefixOf(P.FKind);
      if P.FKind = rkInitialize then
      begin
        if not MergeInitialize(TJSONObject(Json)) then Exit;   { both advertised: original bytes }
        AReplacement:= BuildFrame(TEncoding.UTF8.GetBytes(Json.ToJSON));
        Exit(True);
      end;
      { definition: a non-empty reply wins outright, without waiting for ours }
      if (P.FKind = rkDefinition) and not IsEmptyLocations(TJSONObject(Json).GetValue('result')) then Exit;
      Remain:= Int64(P.FStartTick) + FOptions.MergeBudgetMs - Int64(GetTickCount64);
      if Remain < 0 then Remain:= 0;
      if (P.FDone.WaitFor(Cardinal(Remain)) <> wrSignaled) or (P.FElapsed > UInt64(FOptions.MergeBudgetMs)) then
      begin
        case P.FKind of
          rkHover     : Warned:= TInterlocked.Exchange(FHoverWarned, 1);
          rkDefinition: Warned:= TInterlocked.Exchange(FDefinitionWarned, 1);
          else Warned:= TInterlocked.Exchange(FCompletionWarned, 1);
        end;
        if Warned = 0 then
          MergeErrLine(Prefix + 'over its ' + IntToStr(FOptions.MergeBudgetMs) +
                       ' ms budget; the ' + KindName(P.FKind) +
                       ' reply is forwarded unmerged (reported once).');
        Exit;
      end;
      if P.FErr <> '' then
      begin
        MergeErrLine(Prefix + 'skipped a reply (' + P.FErr + '); forwarded unchanged.');
        Exit;
      end;
      if P.FKind = rkHover then
      begin
        { neither, or nothing of ours to add: original bytes (criterion 16b) }
        if (P.FItems = '') or not MergeHoverResult(TJSONObject(Json), P.FItems) then Exit;
      end
      else if P.FKind = rkDefinition then
      begin
        Ours:= TJSONObject.ParseJSONValue(P.FItems);
        try
          if not (Ours is TJSONArray) or (TJSONArray(Ours).Count = 0) then Exit;   { neither: original bytes }
          TJSONObject(Json).RemovePair('result').Free;
          TJSONObject(Json).AddPair('result', TJSONValue(Ours.Clone));
        finally
          Ours.Free;
        end;
      end
      else
      begin
        Ours:= TJSONObject.ParseJSONValue(P.FItems);
        try
          if not (Ours is TJSONArray) or (TJSONArray(Ours).Count = 0) then Exit;   { nothing to add: original bytes }
          if not UnionCompletion(TJSONObject(Json), TJSONArray(Ours)) then Exit;
        finally
          Ours.Free;
        end;
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
      MergeErrLine(Prefix + 'skipped a reply (' + E.ClassName + ': ' + E.Message + '); forwarded unchanged.');
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
            EnsureLinter;
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

{ LSP-1 CORE (.delphilsp.json pickup): DelphiLSP is configured by the IDE through
  a `settingsFile` naming `<Project>.delphilsp.json` (initialize's
  initializationOptions or workspace/didChangeConfiguration's settings). That is
  the IDE's ACTIVE project, so it becomes the merge server's client context.
  Read only when the frame contains the key; never alters the relayed bytes. }
procedure TProxyMergeEngine.PickupContext(const AFrame: TBytes; ALen: Integer);
var
  Json: TJSONValue;
  F   : string;
begin
  if not FrameContains(AFrame, ALen, 'settingsFile') then Exit;
  F:= '';
  try
    Json:= TJSONObject.ParseJSONValue(FrameBody(AFrame, ALen));
    try
      if not (Json is TJSONObject) then Exit;
      if not Json.TryGetValue<string>('params.initializationOptions.settingsFile', F) then
        if not Json.TryGetValue<string>('params.settings.settingsFile', F) then Exit;
    finally
      Json.Free;
    end;
  except
    on E: Exception do
    begin
      MergeErrLine('drag-lint lsp --proxy: settingsFile not read (' + E.ClassName + ': ' + E.Message + ').');
      Exit;
    end;
  end;
  if F = '' then Exit;
  if F.StartsWith('file:', True) then F:= TLSPServer.FileFromUri(F);
  FServerLock.Enter;
  try
    FPendingSettingsFile:= F;
  finally
    FServerLock.Leave;
  end;
end;

function TProxyMergeEngine.Intercept(ADir: TMergeDirection; const AFrame: TBytes;
  ALen: Integer; out AReplacement: TBytes): Boolean;
begin
  AReplacement:= nil;
  if FTestEmptyReplacement then Exit(True);
  if ADir = mdClientToServer then
  begin
    if FOptions.MergeDiagnostics or FOptions.MergeCompletion or FOptions.MergeHover or FOptions.MergeDefinition then
      TrackDocument(AFrame, ALen);
    if FOptions.MergeDiagnostics or FOptions.MergeCompletion or FOptions.MergeHover or FOptions.MergeDefinition then
      PickupContext(AFrame, ALen);
    if FOptions.MergeCompletion or FOptions.MergeHover or FOptions.MergeDefinition then RecordRequest(AFrame, ALen);
    Exit(False);
  end;
  if (FOptions.MergeCompletion or FOptions.MergeHover or FOptions.MergeDefinition) and
     MergeReply(AFrame, ALen, AReplacement) then Exit(True);
  Result:= FOptions.MergeDiagnostics and MergeDiagnostics(AFrame, ALen, AReplacement);
end;

end.
