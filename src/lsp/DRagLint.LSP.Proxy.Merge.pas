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

  --merge-navigation does the same for the plain server's newer features: the
  type and call hierarchy, typeDefinition, documentHighlight and foldingRange
  (NAV_CAPS / NAV_METHODS). Each provider DelphiLSP does not advertise is added
  to its initialize reply and its requests are answered by the registered LSP
  feature (TLSPServer.ComputeFeatureResult); one it advertises stays its own.

  1.52.2 PROXYMERGE (owner 2026-11-20: never drop drag-lint's part, deliver it
  late and say it is coming): a diagnostics lint past its budget runs on, and
  the merged set for the URI is published again through ClientWriter when it
  ends; every forward carries the last known drag-lint set. An over-budget
  hover carries an "analysing" placeholder, its drag-lint part is cached per
  position, and the VS Code deferred-hover companion's second request is
  answered here. A lint is wrapped in a work-done progress when the client
  advertised window.workDoneProgress.

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
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.LSP.Proxy.Merge.pas), DRagLint.LSP.Proxy.ForwardIntercepted (DRagLint.LSP.Proxy.pas), DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.Intercept (DRagLint.LSP.Proxy.Merge.pas), DRagLint.LSP.Proxy.RunLspProxy (DRagLint.LSP.Proxy.pas)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
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
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.LSP.Proxy.pas)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
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
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.LSP.Proxy.pas)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TFrameAnswerer = reference to function(const AFrame: TBytes; ALen: Integer; const AOnTake: TProc): Boolean;

  /// <summary>Writes one complete frame to the client, serialised with the
  /// relay's own S&gt;C writes.</summary>
  /// <param name="AFrame">The whole frame, headers included.</param>
  /// <returns>False when the client end is closed.</returns>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.LSP.Proxy.Merge.pas)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TClientWriter = reference to function(const AFrame: TBytes): Boolean;

  /// <summary>Runs AProc while holding the relay's client-write lock, so a
  /// frame composed inside it and written by it cannot be overtaken by an
  /// S&gt;C frame the relay forwards (1.52.2 HOVER, the publish race).</summary>
  /// <param name="AProc">Composes and writes; must not wait on a pump.</param>
  TClientLocker = reference to procedure(const AProc: TProc);

  /// <summary>The relay's last S&gt;C step before writing an intercepted frame,
  /// under its client-write lock (TProxyMergeEngine.FinishServerFrame).</summary>
  TFrameFinisher = reference to function: TBytes;

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
  /// <para>Thread-safety: Intercept is called from both
  /// pump threads concurrently; Server serialises
  /// internally. The dirty-URI set has its own lock (written by the C&gt;S pump,
  /// read by the S&gt;C pump). The linter is created and used ONLY on the merge
  /// worker thread, so it needs none.</para>
  /// <para>Latency (P0 review I3): no pump thread waits for a queued job beyond
  /// its budget; the C&gt;S side (document tracking, the live-document
  /// tap, recording a completion request) runs inline : a completion job and the warm-up are QUEUED on the worker
  /// (Enqueue, no wait), so a diagnostics merge never delays a client request.
  /// The S&gt;C completion merge waits on its own request's event, at most the
  /// part of the budget left since the request.</para>
  /// <para>The live-document overlay (TLiveDocuments, not thread-safe) is
  /// written ONLY on the merge worker: the C&gt;S pump queues each text under
  /// FDocLock and the next completion job applies the queue before it reads
  /// the buffer.</para>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.LSP.Proxy.Merge.pas) ?, DRagLint.LSP.Proxy.Merge.TMergeWorker.Create (DRagLint.LSP.Proxy.Merge.pas) ?, DRagLint.LSP.Proxy.RunLspProxy (DRagLint.LSP.Proxy.pas)</para>
  /// <para>Used in units: DRagLint.LSP.Proxy, DRagLint.LSP.Proxy.Merge</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TProxyMergeEngine = class  // dl:ok high-response@fad6 -- the one owner of a proxy's merge state by P0 design (worker, index, per-handler state); split per handler when A4/A5 add theirs
  private type
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Used by: declaration (DRagLint.LSP.Proxy.Merge.pas), DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.Create (DRagLint.LSP.Proxy.Merge.pas), DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.FlushDocUpdates (DRagLint.LSP.Proxy.Merge.pas), DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.QueueDocUpdate (DRagLint.LSP.Proxy.Merge.pas)</para>
    /// <para>Used in units: DRagLint.LSP.Proxy.Merge</para>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.AnnounceOpen"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.Answer"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.AnswerOnWorker"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.ComputeCompletion"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.ComputeDefinition"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    TDocUpdate = record
      Path  : string;
      Text  : string;
      Remove: Boolean;
    end;
    /// <summary>One queued full-rules run (1.52.3 MERGE-FULLRULES): the per-URI
    /// diagnostics state (a TDiagState), the file, and the generation of the
    /// subset lint that queued it.</summary>
    TFullJob = record
      State: TObject;
      Path : string;
      Gen  : Integer;
    end;
    { One request the proxy answers itself (A5). }
    /// <summary><!-- drag-lint:auto sum -->One request the proxy answers itself (A5).</summary>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Used by: declaration (DRagLint.LSP.Proxy.Merge.pas), DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.Answer (DRagLint.LSP.Proxy.Merge.pas), DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.AnswerOnWorker (DRagLint.LSP.Proxy.Merge.pas), DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.NavAnswer (DRagLint.LSP.Proxy.Merge.pas)</para>
    /// <para>Used in units: DRagLint.LSP.Proxy.Merge</para>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.AnnounceOpen"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.Answer"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.AnswerOnWorker"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.ComputeCompletion"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.ComputeDefinition"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    TAnswerJob = record
      Id         : string;    { the request id, as JSON }
      Symbols    : Boolean;   { workspace/symbol; else textDocument/references }
      Query      : string;
      Path       : string;    { '' when the request named no usable position }
      Line0      : Integer;
      Col0       : Integer;
      IncludeDecl: Boolean;
      NavMethod  : string;    { --merge-navigation: the feature method; '' = references / symbols }
      NavParams  : string;    { its params, as JSON }
      Hover      : Boolean;   { 1.52.2: the deferred hover's whole step -- drag-lint's hover part alone }
    end;
  private
    FOptions    : TLspProxyOptions;
    FServer     : TLSPServer;
    FServerTried: Boolean;
    FServerLock : TCriticalSection;
    FPendingSettingsFile: string; { LSP-1 CORE: the .delphilsp.json the IDE named, applied to FServer on the next Server call; under FServerLock }
    FStateLock  : TCriticalSection;
    FJobReady   : TEvent;
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
    FHoverErrWarned  : Integer;   { 1 once a DelphiLSP hover error reply was reported (1.52.3 HOVER-ISE) }
    FDefinitionOff   : Integer;
    FDefinitionWarned: Integer;
    FTheirReferences : Integer;
    FTheirSymbols    : Integer;
    FTheirNavigation : Integer;   { bit per NAV_CAPS entry DelphiLSP advertised; written once by MergeInitialize }
    FClientWriter    : TClientWriter;
    FClientLocker    : TClientLocker;
    FPublishPending  : TObject;   { S>C pump only: the TDiagState of the publishDiagnostics frame being forwarded }
    FPublishOurs     : string;    { S>C pump only: the drag-lint set that frame was composed with }
    FAnswersOut      : Integer;
    FAnswersIdle     : TEvent;
    FAnsweredIds     : TDictionary<string, Boolean>;   { C>S pump only: ids Answer took }
    FTestAnswerInline: Boolean;
    FTestFastPath    : Boolean;
    { 1.52.2 PROXYMERGE: drag-lint's part is delivered late, never dropped. }
    FDiagStates      : TDictionary<string, TObject>;   { DocKey -> TDiagState; under FDiagLock; freed by Destroy }
    FDiagLock        : TCriticalSection;
    FHoverCache      : TDictionary<string, string>;    { HoverKey -> drag-lint hover markdown; under FPendingLock }
    FProgressIds     : TDictionary<string, Boolean>;   { ids of our window/workDoneProgress/create requests, as JSON; under FPendingLock }
    FClientProgress  : Integer;   { 1 once the client's initialize advertised window.workDoneProgress }
    FProgressSeq     : Integer;
    FDeferKey        : string;    { C>S pump only: the position the last draglint/deferHover named }
    FDeferHovers     : Integer;   { C>S pump only: hover requests seen at FDeferKey since }
    FTestLintDelayMs : Integer;
    { 1.52.3 MERGE-FULLRULES: with --full-rules the merged set is the full
      `lint <file> --json` set, run out of process on its own thread (one child
      at a time) so a 90 s lint never holds the merge worker (hover, completion). }
    FFullRules  : Boolean;
    FFullThread : TThread;            { created with the engine when FFullRules; freed by Destroy }
    FFullLock   : TCriticalSection;   { guards FFullQueue, FFullProcess }
    FFullReady  : TEvent;
    FFullQueue  : TList<TFullJob>;
    FFullProcess: THandle;            { the running child; 0 = none }
    /// <summary>Queues a full-rules run of APath for the per-URI state AState
    /// (a TDiagState) whose subset lint had generation AGen; replaces a queued
    /// run of the same state.</summary>
    procedure QueueFullRules(AState: TObject; const APath: string; AGen: Integer);
    /// <summary>Full-rules thread body: runs the queued jobs one at a time until
    /// the thread is terminated.</summary>
    procedure FullRulesLoop;
    /// <summary>Full-rules thread: runs `lint APath --json` as a child process.</summary>
    /// <param name="AJob">The job; its state's generation is checked while the
    /// child runs and a newer subset lint kills it.</param>
    /// <param name="AJson">The child's stdout (a JSON array) on success.</param>
    /// <returns>True when the child exited 0 or 1 with a JSON array; False when
    /// it failed, stalled past LintChildTimeoutMs, was superseded or the engine
    /// is stopping.</returns>
    function  RunFullRulesChild(const AJob: TFullJob; out AJson: string): Boolean;
    /// <summary>Full-rules thread: stores AItems (a JSON array of diagnostics)
    /// as the drag-lint set of AJob's state and publishes the merged set when it
    /// differs from what the client was last sent. No-op when the state's
    /// generation moved on or a newer lint is queued. AFull: AItems is a full set.</summary>
    procedure ApplyFullRules(const AJob: TFullJob; const AItems: string; AFull: Boolean);
    /// <summary>Queues one lint of APath for the per-URI diagnostics state
    /// AState (a TDiagState) on the merge worker.</summary>
    /// <returns>False when the worker queue is full; AState is then marked idle
    /// again.</returns>
    function  StartLint(AState: TObject; const APath: string): Boolean;
    /// <summary>Worker thread: lints APath, stores the findings in AState and,
    /// when nobody waits for them inline any more, publishes the merged set for
    /// the URI through ClientWriter (only when it differs from what the client
    /// was last sent). Runs a queued re-lint when a publish arrived meanwhile.</summary>
    procedure LintOnWorker(AState: TObject; const APath: string);
    /// <summary>Worker thread: starts a work-done progress "drag-lint: analysing
    /// AUnit" when the client advertised window.workDoneProgress.</summary>
    /// <returns>The progress token; '' when no progress was started.</returns>
    function  ProgressBegin(const AUnit: string): string;
    /// <summary>Ends the work-done progress AToken ('' = none).</summary>
    procedure ProgressEnd(const AToken: string);
    /// <summary>C&gt;S: True (consumed) for the client's reply to one of our
    /// window/workDoneProgress/create requests.</summary>
    function  TakeProgressReply(const AFrame: TBytes; ALen: Integer; const AOnTake: TProc): Boolean;
    /// <summary>C&gt;S: True (consumed) for a draglint/deferHover notification;
    /// remembers its position so the second hover there is answered here.</summary>
    function  TakeDeferHover(const AFrame: TBytes; ALen: Integer; const AOnTake: TProc): Boolean;
    /// <summary>C&gt;S: reads window.workDoneProgress from the client's
    /// initialize request.</summary>
    procedure NoteClientCapabilities(const AFrame: TBytes; ALen: Integer);
    /// <summary>Drops the cached hover parts of APath (its text changed).</summary>
    procedure ForgetHovers(const APath: string);
    /// <summary>Caches drag-lint's hover markdown for one position.</summary>
    procedure CacheHover(const AKey, AMarkdown: string);
    /// <summary>The cached drag-lint hover markdown for one position.</summary>
    /// <returns>True on a hit.</returns>
    function  CachedHover(const AKey: string; out AMarkdown: string): Boolean;
    /// <summary>Worker thread: the reply result (JSON) to the deferred hover's
    /// whole step: drag-lint's hover part alone, or null.</summary>
    function  HoverAnswer(const AServer: TLSPServer; const AJob: TAnswerJob): string;
    /// <param name="AFrame"><!-- drag-lint:auto type -->const TBytes</param>
    /// <param name="ALen"><!-- drag-lint:auto type -->Integer</param>
    /// <param name="AOnTake"><!-- drag-lint:auto type -->const TProc</param>
    /// <returns><!-- drag-lint:auto -->Boolean -- Observed: False; True.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.Answer (DRagLint.LSP.Proxy.Merge.pas)</para>
    /// <para>Calls: DRagLint.LSP.Proxy.Merge.FrameBody, DRagLint.LSP.Proxy.Merge.FrameContains, TJSONObject</para>
    /// <para>Reads: FAnsweredIds</para>
    /// <para>Catches: Exception (swallowed)</para>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.FrameBody"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.FrameContains"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.AnnounceOpen"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.Answer"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.AnswerOnWorker"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function  TakeCancel(const AFrame: TBytes; ALen: Integer; const AOnTake: TProc): Boolean;
    /// <summary><!-- drag-lint:auto sum -->The NAV_METHODS index of AMethod when
    /// --merge-navigation owes it an answer: on, and DelphiLSP did not advertise its
    /// provider. -1 otherwise.</summary>
    /// <param name="AMethod"><!-- drag-lint:auto type -->const string</param>
    /// <returns><!-- drag-lint:auto -->Integer -- Observed: -1; I.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.Answer (DRagLint.LSP.Proxy.Merge.pas)</para>
    /// <para>Reads: FOptions, FTheirNavigation</para>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.AnnounceOpen"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.Answer"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.AnswerOnWorker"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.ComputeCompletion"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.ComputeDefinition"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function  NavMethodIndex(const AMethod: string): Integer;
    /// <summary><!-- drag-lint:auto sum -->Could this frame hold a NAV_METHODS request?
    /// The scan before the parse.</summary>
    /// <param name="AFrame"><!-- drag-lint:auto type -->const TBytes</param>
    /// <param name="ALen"><!-- drag-lint:auto type -->Integer</param>
    /// <returns><!-- drag-lint:auto -->Boolean -- Observed: False.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.Answer (DRagLint.LSP.Proxy.Merge.pas)</para>
    /// <para>Calls: DRagLint.LSP.Proxy.Merge.FrameContains</para>
    /// <para>Reads: FOptions</para>
    /// <para>Effect-free (proven)</para>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.FrameContains"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.AnnounceOpen"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.Answer"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.AnswerOnWorker"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.ComputeCompletion"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function  MayBeNavRequest(const AFrame: TBytes; ALen: Integer): Boolean;
    /// <summary><!-- drag-lint:auto sum -->Worker thread: the registered feature's result
    /// for one --merge-navigation request, as JSON. Whatever the plain server would
    /// answer, null included; [] when no feature answered.</summary>
    /// <param name="AServer"><!-- drag-lint:auto type -->const TLSPServer</param>
    /// <param name="AJob"><!-- drag-lint:auto type -->const TAnswerJob</param>
    /// <returns><!-- drag-lint:auto -->string -- Observed: '[]'; Res.ToJSON.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.AnswerOnWorker (DRagLint.LSP.Proxy.Merge.pas)</para>
    /// <para>Calls: DRagLint.LSP.Server.TLSPServer.ComputeFeatureResult</para>
    /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ComputeFeatureResult"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.AnnounceOpen"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.Answer"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.AnswerOnWorker"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.ComputeCompletion"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function  NavAnswer(const AServer: TLSPServer; const AJob: TAnswerJob): string;
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.LSP.Proxy.Merge.TMergeWorker.Execute (DRagLint.LSP.Proxy.Merge.pas)</para>
    /// <para>Calls: Work</para>
    /// <para>Reads: FJobReady, FStateLock, FQueue</para>
    /// <para>Catches: Exception (swallowed)</para>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.AnnounceOpen"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.Answer"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.AnswerOnWorker"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.ComputeCompletion"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure WorkerLoop;
    /// <summary><!-- drag-lint:auto sum -->Merge worker only (no lock: the linter is
    /// touched on no other thread). The first call runs Options.PrepareLint -- the CLI's
    /// lint preprocessing setup, the same routine plain `lsp` runs at startup (C14) --
    /// and then creates the linter, so the first publish is already linted from the
    /// preprocessed text.</summary>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.MergeDiagnostics (DRagLint.LSP.Proxy.Merge.pas), DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.WarmUp (DRagLint.LSP.Proxy.Merge.pas)</para>
    /// <para>Calls: DRagLint.Lint.Linter.TLinter.Create</para>
    /// <para>Reads: FLinter, FOptions   Writes: FLinter</para>
    /// <seealso cref="DRagLint.Lint.Linter.TLinter.Create"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.AnnounceOpen"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.Answer"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.AnswerOnWorker"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.ComputeCompletion"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure EnsureLinter;
    /// <summary><!-- drag-lint:auto sum -->C&gt;S, first didOpen only: builds what the
    /// enabled merges need on the merge worker, off the relay path (queued, never waited
    /// on). TLinter.Create loads every rule file, which takes seconds cold and would
    /// otherwise make the FIRST publishDiagnostics of a session miss any budget; opening
    /// the index does the same to the first completion. Does not touch FBudgetWarned.
    /// FWarming tells the S&gt;C side an overrun is the warm-up, not a dead merge; it
    /// stays set until the job ends (A3: it used to be cleared at once, because the
    /// budget-0 wait this replaced always reported an overrun). Runs on the C&gt;S pump
    /// thread.</summary>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.TrackDocument (DRagLint.LSP.Proxy.Merge.pas)</para>
    /// <para>Calls: DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.Enqueue, DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.EnsureLinter, DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.Server</para>
    /// <para>Reads: FWarmQueued, FWarming, FOptions   Writes: FWarmQueued</para>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.Enqueue"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.EnsureLinter"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.Server"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.AnnounceOpen"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.Answer"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure WarmUp;
    /// <summary><!-- drag-lint:auto sum -->Queues AWork on the merge worker and returns
    /// at once; nobody waits on it, so it must publish its result through its own
    /// captured state. False (AWork is dropped, never run) when QUEUE_MAX jobs are
    /// already waiting.</summary>
    /// <param name="AWork"><!-- drag-lint:auto type -->const TProc</param>
    /// <returns><!-- drag-lint:auto -->Boolean -- Observed: FQueue.Count &lt; QUEUE_MAX.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.AnnounceOpen (DRagLint.LSP.Proxy.Merge.pas), DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.Answer (DRagLint.LSP.Proxy.Merge.pas), DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.Enqueue (DRagLint.LSP.Proxy.Merge.pas) ?, DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.RecordRequest (DRagLint.LSP.Proxy.Merge.pas), DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.WarmUp (DRagLint.LSP.Proxy.Merge.pas)</para>
    /// <para>Reads: FStateLock, FQueue, FJobReady</para>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.AnnounceOpen"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.Answer"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.AnswerOnWorker"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.ComputeCompletion"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.ComputeDefinition"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function  Enqueue(const AWork: TProc): Boolean;
    /// <param name="APath"><!-- drag-lint:auto type -->const string</param>
    /// <returns><!-- drag-lint:auto -->Boolean -- Observed:
    /// FDirty.ContainsKey(DocKey(APath)).</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.MergeDiagnostics (DRagLint.LSP.Proxy.Merge.pas)</para>
    /// <para>Calls: DRagLint.LSP.Proxy.Merge.DocKey</para>
    /// <para>Reads: FDirtyLock, FDirty</para>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.DocKey"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.AnnounceOpen"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.Answer"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.AnswerOnWorker"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.ComputeCompletion"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function  IsDirty(const APath: string): Boolean;
    /// <param name="APath"><!-- drag-lint:auto type -->const string</param>
    /// <remarks>
    /// <!-- drag-lint:auto -->C&gt;S: with MergeDiagnostics, didChange marks the document dirty and
    /// didSave / didOpen / didClose clear it; with MergeCompletion or MergeHover, the text the
    /// notification implies is queued for the live-document overlay. A first didOpen also warms the
    /// worker. Runs on the C&gt;S pump thread, inline (no worker). C&gt;S, didOpen:
    /// queues (never waits) the announcement of the file's context on the merge worker: the
    /// embedded server then sends draglint/context with its notice through the client writer and
    /// starts the background re-index of a project DB marked needs-re-resolve (once per DB: the
    /// server keys the run by DB). Needs the server, so only when an index-backed merge is on and a
    /// writer is set.
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.TrackDocument (DRagLint.LSP.Proxy.Merge.pas)</para>
    /// <para>Calls: DRagLint.LSP.Proxy.Merge.BuildFrame, DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.Enqueue, DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.Server, DRagLint.LSP.Server.TLSPServer.AnnounceProxyOpen, DRagLint.LSP.Server.TLSPServer.EnableProxyNotices, FClientWriter</para>
    /// <para>Reads: FOptions, FClientWriter</para>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.BuildFrame"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.Enqueue"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.Server"/>
    /// <seealso cref="DRagLint.LSP.Server.TLSPServer.AnnounceProxyOpen"/>
    /// <seealso cref="DRagLint.LSP.Server.TLSPServer.EnableProxyNotices"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure AnnounceOpen(const APath: string);
    /// <param name="AFrame"><!-- drag-lint:auto type -->const TBytes</param>
    /// <param name="ALen"><!-- drag-lint:auto type -->Integer</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.Intercept (DRagLint.LSP.Proxy.Merge.pas)</para>
    /// <para>Calls: DRagLint.LSP.Proxy.Merge.DocKey, DRagLint.LSP.Proxy.Merge.FrameBody, DRagLint.LSP.Proxy.Merge.FrameContains, DRagLint.LSP.Proxy.Merge.HeadStringValue, DRagLint.LSP.Proxy.Merge.LiveUpdateOf, DRagLint.LSP.Proxy.Merge.MergeErrLine, DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.AnnounceOpen, DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.QueueDocUpdate, DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.WarmUp, DRagLint.LSP.Server.TLSPServer.FileFromUri</para>
    /// <para>Complexity: 26 (cyclomatic, outer body), 67 lines (full implementation)</para>
    /// <para>Reads: FOptions, FTestFastPath, FDirtyLock, FDirty</para>
    /// <para>Catches: Exception (swallowed)</para>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.DocKey"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.FrameBody"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.FrameContains"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.HeadStringValue"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.LiveUpdateOf"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure TrackDocument(const AFrame: TBytes; ALen: Integer);
    /// <summary><!-- drag-lint:auto sum -->LSP-1 CORE (.delphilsp.json pickup): DelphiLSP
    /// is configured by the IDE through a `settingsFile` naming
    /// `&lt;Project&gt;.delphilsp.json` (initialize's initializationOptions or
    /// workspace/didChangeConfiguration's settings). That is the IDE's ACTIVE project, so
    /// it becomes the merge server's client context. Read only when the frame contains
    /// the key; never alters the relayed bytes.</summary>
    /// <param name="AFrame"><!-- drag-lint:auto type -->const TBytes</param>
    /// <param name="ALen"><!-- drag-lint:auto type -->Integer</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.Intercept (DRagLint.LSP.Proxy.Merge.pas)</para>
    /// <para>Calls: DRagLint.LSP.Proxy.Merge.FrameBody, DRagLint.LSP.Proxy.Merge.FrameContains, DRagLint.LSP.Proxy.Merge.MergeErrLine, DRagLint.LSP.Server.TLSPServer.FileFromUri</para>
    /// <para>Reads: FServerLock   Writes: FPendingSettingsFile</para>
    /// <para>Catches: Exception (swallowed)</para>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.FrameBody"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.FrameContains"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.MergeErrLine"/>
    /// <seealso cref="DRagLint.LSP.Server.TLSPServer.FileFromUri"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.AnnounceOpen"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure PickupContext(const AFrame: TBytes; ALen: Integer);
    /// <summary><!-- drag-lint:auto sum -->C&gt;S: queues one overlay update; the latest
    /// per file wins. Applied on the worker by FlushDocUpdates, because TLiveDocuments is
    /// not thread-safe.</summary>
    /// <param name="APath"><!-- drag-lint:auto type -->const string</param>
    /// <param name="ARemove"><!-- drag-lint:auto type -->Boolean</param>
    /// <param name="AText"><!-- drag-lint:auto type -->const string</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.TrackDocument (DRagLint.LSP.Proxy.Merge.pas)</para>
    /// <para>Calls: DRagLint.LSP.Proxy.Merge.DocKey</para>
    /// <para>Reads: FDocLock, FDocUpdates</para>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.DocKey"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.AnnounceOpen"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.Answer"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.AnswerOnWorker"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.ComputeCompletion"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure QueueDocUpdate(const APath: string; ARemove: Boolean; const AText: string);
    /// <summary><!-- drag-lint:auto sum -->Worker thread only: applies the queued overlay
    /// updates.</summary>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.AnswerOnWorker (DRagLint.LSP.Proxy.Merge.pas), DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.ComputeCompletion (DRagLint.LSP.Proxy.Merge.pas), DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.ComputeDefinition (DRagLint.LSP.Proxy.Merge.pas), DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.ComputeHover (DRagLint.LSP.Proxy.Merge.pas)</para>
    /// <para>Calls: DRagLint.Core.LiveDocs.TLiveDocuments.Remove, DRagLint.Core.LiveDocs.TLiveDocuments.SetText</para>
    /// <para>Reads: FDocLock, FDocUpdates</para>
    /// <seealso cref="DRagLint.Core.LiveDocs.TLiveDocuments.Remove"/>
    /// <seealso cref="DRagLint.Core.LiveDocs.TLiveDocuments.SetText"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.AnnounceOpen"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.Answer"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.AnswerOnWorker"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure FlushDocUpdates;
    /// <param name="AFrame"><!-- drag-lint:auto type -->const TBytes</param>
    /// <param name="ALen"><!-- drag-lint:auto type -->Integer</param>
    /// <remarks>
    /// <!-- drag-lint:auto -->C&gt;S: records a textDocument/completion (MergeCompletion) or
    /// textDocument/hover (MergeHover) request by id and queues drag-lint's answer for it on the
    /// worker at once, so it is usually ready before DelphiLSP answers. Never delays the frame
    /// beyond one JSON parse.
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.Intercept (DRagLint.LSP.Proxy.Merge.pas)</para>
    /// <para>Calls: DRagLint.LSP.Proxy.Merge.FrameBody, DRagLint.LSP.Proxy.Merge.FrameContains, DRagLint.LSP.Proxy.Merge.MergeErrLine, DRagLint.LSP.Proxy.Merge.PrefixOf, DRagLint.LSP.Proxy.Merge.TPendingRequest.AddRef, DRagLint.LSP.Proxy.Merge.TPendingRequest.Create, DRagLint.LSP.Proxy.Merge.TPendingRequest.Release, DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.ComputeCompletion, DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.ComputeDefinition, DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.ComputeHover, DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.Enqueue, DRagLint.LSP.Server.TLSPServer.FileFromUri, TJSONObject, TPendingRequest</para>
    /// <para>Complexity: 39 (cyclomatic, outer body), 112 lines (full implementation)</para>
    /// <para>Reads: FOptions, FCompletionOff, FHoverOff, FDefinitionOff, FPendingLock, FPending</para>
    /// <para>Catches: Exception (swallowed)</para>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.FrameBody"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.FrameContains"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.MergeErrLine"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.PrefixOf"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TPendingRequest.AddRef"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure RecordRequest(const AFrame: TBytes; ALen: Integer);
    /// <summary><!-- drag-lint:auto sum -->Worker thread: drag-lint's items for one
    /// recorded request. Publishes only through the record (Items / Err / Elapsed, then
    /// Done) and releases the job's reference. No store at all turns completion merging
    /// off for the session, with one stderr line (Server reports its own failures).</summary>
    /// <param name="APending"><!-- drag-lint:auto type -->TObject</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.RecordRequest (DRagLint.LSP.Proxy.Merge.pas)</para>
    /// <para>Calls: DRagLint.LSP.Completion.TLspCompletion.BuildCompletionItems/4, DRagLint.LSP.Context.ILspServerContext.Stores, DRagLint.LSP.Proxy.Merge.MergeErrLine, DRagLint.LSP.Proxy.Merge.TPendingRequest.Release, DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.FlushDocUpdates, DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.Server, DRagLint.LSP.Server.TLSPServer.StoresForFile, TPendingRequest</para>
    /// <para>Reads: FCompletionOff</para>
    /// <para>Catches: Exception (swallowed)</para>
    /// <seealso cref="DRagLint.LSP.Completion.TLspCompletion.BuildCompletionItems"/>
    /// <seealso cref="DRagLint.LSP.Context.ILspServerContext.Stores"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.MergeErrLine"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TPendingRequest.Release"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.FlushDocUpdates"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure ComputeCompletion(APending: TObject);
    /// <param name="APending"><!-- drag-lint:auto type -->TObject</param>
    /// <remarks>
    /// <!-- drag-lint:auto -->Worker thread: drag-lint's hover markdown for one recorded request,
    /// the same text plain `lsp` answers (TLSPServer.ComputeHoverMarkdown, which reads the
    /// live-document overlay). Publishes only through the record, like ComputeCompletion. No index
    /// turns hover merging off for the session (Server reports the failure once).
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.RecordRequest (DRagLint.LSP.Proxy.Merge.pas)</para>
    /// <para>Calls: DRagLint.LSP.Proxy.Merge.TPendingRequest.Release, DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.FlushDocUpdates, DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.Server, DRagLint.LSP.Server.TLSPServer.ComputeHoverMarkdown, TPendingRequest</para>
    /// <para>Reads: FHoverOff</para>
    /// <para>Catches: Exception (swallowed)</para>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TPendingRequest.Release"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.FlushDocUpdates"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.Server"/>
    /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ComputeHoverMarkdown"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.AnnounceOpen"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure ComputeHover(APending: TObject);
    /// <param name="APending"><!-- drag-lint:auto type -->TObject</param>
    /// <remarks>
    /// <!-- drag-lint:auto -->Worker thread: drag-lint's definition locations for one recorded
    /// request (TLSPServer.ComputeDefinition, the plain server's own F12). Publishes only through
    /// the record, like ComputeHover. No index turns the definition fallback off for the session
    /// (Server reports the failure once).
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.RecordRequest (DRagLint.LSP.Proxy.Merge.pas)</para>
    /// <para>Calls: DRagLint.LSP.Proxy.Merge.TPendingRequest.Release, DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.FlushDocUpdates, DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.Server, DRagLint.LSP.Server.TLSPServer.ComputeDefinition, TPendingRequest</para>
    /// <para>Reads: FDefinitionOff</para>
    /// <para>Catches: Exception (swallowed)</para>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TPendingRequest.Release"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.FlushDocUpdates"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.Server"/>
    /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ComputeDefinition"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.AnnounceOpen"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure ComputeDefinition(APending: TObject);
    /// <summary><!-- drag-lint:auto sum -->S&gt;C, the reply to the recorded initialize:
    /// sets referencesProvider and workspaceSymbolProvider to true when absent, false or
    /// null, and notes which ones DelphiLSP advertised itself (Answer then leaves those
    /// requests to it). Returns True when AReply was changed.</summary>
    /// <param name="AReply"><!-- drag-lint:auto type -->const TJSONObject</param>
    /// <returns><!-- drag-lint:auto -->Boolean -- Observed: False; True.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.MergeReply (DRagLint.LSP.Proxy.Merge.pas)</para>
    /// <para>Calls: DRagLint.LSP.Proxy.Merge.Advertises, TJSONObject</para>
    /// <para>Complexity: 11 (cyclomatic, outer body), 46 lines (full implementation)</para>
    /// <para>Reads: FOptions, FTheirReferences, FTheirSymbols, FTheirNavigation</para>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.Advertises"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.AnnounceOpen"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.Answer"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.AnswerOnWorker"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.ComputeCompletion"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function  MergeInitialize(const AReply: TJSONObject): Boolean;
    /// <summary><!-- drag-lint:auto sum -->Worker thread: computes and writes the reply
    /// to one request Answer took.</summary>
    /// <param name="AJob"><!-- drag-lint:auto type -->const TAnswerJob</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.Answer (DRagLint.LSP.Proxy.Merge.pas)</para>
    /// <para>Calls: DRagLint.LSP.Proxy.Merge.MergeErrLine, DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.EndAnswer, DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.FlushDocUpdates, DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.NavAnswer, DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.SendAnswer, DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.Server, DRagLint.LSP.Server.TLSPServer.ComputeReferences, DRagLint.LSP.Server.TLSPServer.ComputeWorkspaceSymbols</para>
    /// <para>Catches: Exception (swallowed)</para>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.MergeErrLine"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.EndAnswer"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.FlushDocUpdates"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.NavAnswer"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.SendAnswer"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure AnswerOnWorker(const AJob: TAnswerJob);
    /// <summary><!-- drag-lint:auto sum -->Writes the JSON-RPC reply (id AId, result
    /// AResultJson) to the client.</summary>
    /// <param name="AId"><!-- drag-lint:auto type -->const string</param>
    /// <param name="AResultJson"><!-- drag-lint:auto type -->const string</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.Answer (DRagLint.LSP.Proxy.Merge.pas), DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.AnswerOnWorker (DRagLint.LSP.Proxy.Merge.pas)</para>
    /// <para>Calls: DRagLint.LSP.Proxy.Merge.BuildFrame, DRagLint.LSP.Proxy.Merge.MergeErrLine, FClientWriter</para>
    /// <para>Reads: FClientWriter</para>
    /// <para>Catches: Exception (swallowed)</para>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.BuildFrame"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.MergeErrLine"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.AnnounceOpen"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.Answer"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.AnswerOnWorker"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure SendAnswer(const AId, AResultJson: string);
    /// <summary><!-- drag-lint:auto sum -->One request Answer took has been replied to.</summary>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.Answer (DRagLint.LSP.Proxy.Merge.pas), DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.AnswerOnWorker (DRagLint.LSP.Proxy.Merge.pas)</para>
    /// <para>Reads: FStateLock, FAnswersOut, FAnswersIdle   Writes: FAnswersOut</para>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.AnnounceOpen"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.Answer"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.AnswerOnWorker"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.ComputeCompletion"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.ComputeDefinition"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure EndAnswer;
    /// <summary><!-- drag-lint:auto sum -->S&gt;C: a reply to a recorded completion
    /// request gets drag-lint's items unioned in; a reply to a recorded hover request
    /// gets drag-lint's markdown merged in (see Intercept). Waits for drag-lint's answer
    /// at most the part of the budget left since the request. Runs on the S&gt;C pump
    /// thread.</summary>
    /// <param name="AFrame"><!-- drag-lint:auto type -->const TBytes</param>
    /// <param name="ALen"><!-- drag-lint:auto type -->Integer</param>
    /// <param name="AReplacement"><!-- drag-lint:auto type -->out TBytes</param>
    /// <returns><!-- drag-lint:auto -->Boolean -- Observed: False; True.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.Intercept (DRagLint.LSP.Proxy.Merge.pas)</para>
    /// <para>Calls: Cardinal, DRagLint.LSP.Proxy.Merge.BuildFrame, DRagLint.LSP.Proxy.Merge.FrameBody, DRagLint.LSP.Proxy.Merge.FrameContains, DRagLint.LSP.Proxy.Merge.IsEmptyLocations, DRagLint.LSP.Proxy.Merge.KindName, DRagLint.LSP.Proxy.Merge.MergeErrLine, DRagLint.LSP.Proxy.Merge.MergeHoverResult, DRagLint.LSP.Proxy.Merge.PrefixOf, DRagLint.LSP.Proxy.Merge.TPendingRequest.Release (+9 more)</para>
    /// <para>Complexity: 30 (cyclomatic, outer body), 111 lines (full implementation)</para>
    /// <para>Reads: FPendingLock, FPending, FOptions, FHoverWarned, FDefinitionWarned, FCompletionWarned</para>
    /// <para>Catches: Exception (swallowed)</para>
    /// <para>Mutates: AReplacement (out)</para>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.BuildFrame"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.FrameBody"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.FrameContains"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.IsEmptyLocations"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.KindName"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function  MergeReply(const AFrame: TBytes; ALen: Integer; out AReplacement: TBytes): Boolean;
    /// <param name="AFrame"><!-- drag-lint:auto type -->const TBytes</param>
    /// <param name="ALen"><!-- drag-lint:auto type -->Integer</param>
    /// <param name="AReplacement"><!-- drag-lint:auto type -->out TBytes</param>
    /// <returns><!-- drag-lint:auto -->Boolean -- Observed: False; True.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto -->S&gt;C: rewrites a publishDiagnostics frame with drag-lint's findings
    /// appended. Runs on the S&gt;C pump thread; the lint itself runs on the merge worker, inside
    /// the budget.
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.Intercept (DRagLint.LSP.Proxy.Merge.pas)</para>
    /// <para>Calls: DRagLint.LSP.Completion.TLspCompletion.BuildDiagnostics/3, DRagLint.LSP.Proxy.Merge.BuildFrame, DRagLint.LSP.Proxy.Merge.FrameBody, DRagLint.LSP.Proxy.Merge.FrameContains, DRagLint.LSP.Proxy.Merge.MergeErrLine, DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.EnsureLinter, DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.IsDirty, DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.MergeDiagnostics.Skip, DRagLint.LSP.Server.TLSPServer.FileFromUri, IntToStr, TJSONArray, TJSONValue</para>
    /// <para>Complexity: 14 (cyclomatic, outer body), 102 lines (full implementation)</para>
    /// <para>Reads: FLinter, FOptions, FBudgetWarned, FWarming   Writes: FBudgetWarned</para>
    /// <para>Catches: Exception (swallowed)</para>
    /// <para>Mutates: AReplacement (out)</para>
    /// <seealso cref="DRagLint.LSP.Completion.TLspCompletion.BuildDiagnostics"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.BuildFrame"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.FrameBody"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.FrameContains"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.MergeErrLine"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function  MergeDiagnostics(const AFrame: TBytes; ALen: Integer; out AReplacement: TBytes): Boolean;
  public
    /// <summary>Copies the options and starts the merge worker thread.</summary>
    /// <param name="AOptions">The proxy options; Merge*, MergeBudgetMs and
    /// DbPaths are the fields this class reads.</param>
    /// <remarks>
    /// Test seam: with the environment variable
    /// DRAGLINT_MERGE_TEST_EMPTY_REPLACEMENT=1 Intercept answers True with an
    /// EMPTY replacement for every frame, so a guard can prove the relay
    /// declines it (run_lsp_proxy_stub_modes_guard.ps1 case f). With
    /// DRAGLINT_MERGE_TEST_FASTPATH=1 every didChange taken by the bounded head
    /// scan (no JSON parse) writes one stderr line, so a guard can prove that
    /// path runs (run_lsp_proxy_merge_diagnostics_guard.ps1 case g2). With
    /// DRAGLINT_MERGE_TEST_LINT_DELAY_MS=N every diagnostics lint sleeps N ms
    /// first, so a guard can force a lint past its budget (case l).
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.LSP.Proxy.RunLspProxy (DRagLint.LSP.Proxy.pas)</para>
    /// <para>Calls: DRagLint.LSP.Proxy.Merge.TMergeWorker.Create, GetEnvironmentVariable</para>
    /// <para>constructor</para>
    /// <para>Writes: FOptions, FServerLock, FStateLock, FJobReady, FWorker, FTestEmptyReplacement (+11 more)</para>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TMergeWorker.Create"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.AnnounceOpen"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.Answer"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.AnswerOnWorker"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.ComputeCompletion"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    constructor Create(const AOptions: TLspProxyOptions);
    /// <summary>Stops the worker (waiting for a running job) and frees the
    /// server.</summary>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Calls: DRagLint.LSP.Proxy.Merge.TPendingRequest.Release, TPendingRequest</para>
    /// <para>Reads: FWorker, FJobReady, FServer, FLinter, FPending, FPendingLock, FDocUpdates, FDocLock (+9 more)</para>
    /// <para>Directives: override</para>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TPendingRequest.Release"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.AnnounceOpen"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.Answer"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.AnswerOnWorker"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.ComputeCompletion"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
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
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.LSP.Proxy.RunLspProxy (DRagLint.LSP.Proxy.pas)</para>
    /// <para>Calls: DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.MergeDiagnostics, DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.MergeReply, DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.PickupContext, DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.RecordRequest, DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.TrackDocument</para>
    /// <para>Returns: False; FOptions.MergeDiagnostics and MergeDiagnostics(AFrame, ALen, AReplacement)</para>
    /// <para>Complexity: 13 (cyclomatic, outer body), 15 lines (full implementation)</para>
    /// <para>Reads: FTestEmptyReplacement, FOptions</para>
    /// <para>Mutates: AReplacement (out)</para>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.MergeDiagnostics"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.MergeReply"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.PickupContext"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.RecordRequest"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.TrackDocument"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function Intercept(ADir: TMergeDirection; const AFrame: TBytes; ALen: Integer;
      out AReplacement: TBytes): Boolean;
    /// <summary>The relay's C&gt;S answerer (TFrameAnswerer) for this engine.</summary>
    /// <param name="AFrame">Buffer holding the frame at offset 0.</param>
    /// <param name="ALen">Byte length of the frame.</param>
    /// <param name="AOnTake">Called once, at the commit point, before the reply
    /// can be written (see TFrameAnswerer); may be nil.</param>
    /// <returns>True for a textDocument/references or workspace/symbol request
    /// (one with an id) when MergeDefinition is on, ClientWriter is set and
    /// DelphiLSP's initialize reply did not advertise that provider: drag-lint
    /// answers it (TLSPServer.ComputeReferences / ComputeWorkspaceSymbols, on
    /// the merge worker) and the relay must NOT forward it. The same for a
    /// NAV_METHODS request when MergeNavigation is on (the registered feature
    /// answers, TLSPServer.ComputeFeatureResult). True also for a
    /// $/cancelRequest whose params.id is a request Answer took and has not
    /// seen cancelled yet: it is consumed and nothing is written (DelphiLSP
    /// never saw that id; group-4 P1). 1.52.2: True also for the client's reply
    /// to one of our window/workDoneProgress/create requests and for a
    /// draglint/deferHover notification (both consumed, nothing written), and,
    /// with MergeHover, for the SECOND textDocument/hover at the position the
    /// last draglint/deferHover named (the VS Code companion's whole step):
    /// answered with drag-lint's hover part alone, or null. False otherwise,
    /// and for a frame that does not parse.</returns>
    /// <remarks>
    /// Once True for a request, exactly one reply is written through
    /// ClientWriter: [] when no index opens, the computation raises (one stderr
    /// line) or the worker queue is full. The C&gt;S pump never waits for the
    /// worker. The taken ids are remembered on the C&gt;S pump thread only (no
    /// lock), at most ANSWERED_IDS_MAX of them; past that the set restarts.
    /// Test seam: DRAGLINT_MERGE_TEST_ANSWER_INLINE=1 replies [] inline on the
    /// C&gt;S pump, as the queue-full path does (run_lsp_proxy_trace_guard.ps1).
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.LSP.Proxy.RunLspProxy (DRagLint.LSP.Proxy.pas)</para>
    /// <para>Calls: DRagLint.LSP.Proxy.Merge.FrameBody, DRagLint.LSP.Proxy.Merge.FrameContains, DRagLint.LSP.Proxy.Merge.MergeErrLine, DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.AnswerOnWorker, DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.EndAnswer, DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.Enqueue, DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.MayBeNavRequest, DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.NavMethodIndex, DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.SendAnswer, DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.TakeCancel, DRagLint.LSP.Server.TLSPServer.FileFromUri, TJSONBool, TJSONObject</para>
    /// <para>Returns: False; True</para>
    /// <para>Complexity: 33 (cyclomatic, outer body), 92 lines (full implementation)</para>
    /// <para>Reads: FOptions, FClientWriter, FTheirReferences, FTheirSymbols, FAnsweredIds, FStateLock, FAnswersIdle, FTestAnswerInline   Writes: FAnswersOut</para>
    /// <para>Catches: Exception (swallowed)</para>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.FrameBody"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.FrameContains"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.MergeErrLine"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.AnswerOnWorker"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.EndAnswer"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function Answer(const AFrame: TBytes; ALen: Integer; const AOnTake: TProc = nil): Boolean;
    /// <summary>Waits until every request Answer took has been replied to.</summary>
    /// <param name="ATimeoutMs">Longest wait, in milliseconds.</param>
    /// <returns>True when none is outstanding (any more).</returns>
    /// <remarks>
    /// RunLspProxy calls it once the S&gt;C stream ended, so a reply
    /// still being computed is not lost to process exit.
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.LSP.Proxy.RunLspProxy (DRagLint.LSP.Proxy.pas)</para>
    /// <para>Returns: FAnswersIdle.WaitFor(ATimeoutMs) = wrSignaled</para>
    /// <para>Reads: FAnswersIdle</para>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.AnnounceOpen"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.Answer"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.AnswerOnWorker"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.ComputeCompletion"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.ComputeDefinition"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function WaitForAnswers(ATimeoutMs: Cardinal): Boolean;
    /// <summary>Where Answer's replies go; set by RunLspProxy before any pump
    /// starts. Unset, Answer declines every frame.</summary>
    property ClientWriter: TClientWriter write FClientWriter;
    /// <summary>The relay's client-write lock (TClientLocker); set by
    /// RunLspProxy with ClientWriter. Unset, the worker writes without it.</summary>
    property ClientLocker: TClientLocker write FClientLocker;
    /// <summary>S&gt;C, under the relay's client-write lock, right before the
    /// relay writes the frame Intercept just answered: when that frame is a
    /// publishDiagnostics whose drag-lint set went stale since Intercept
    /// composed it (a lint finished in between), recomposes it with the
    /// current set, so the client never ends on an older set (1.52.2 HOVER).</summary>
    /// <returns>The recomposed frame to write instead of the one Intercept
    /// answered; nil when that one is still current.</returns>
    /// <remarks>S&gt;C pump thread only. Takes FDiagLock inside the client
    /// lock -- the same order as the worker's publish.</remarks>
    function FinishServerFrame: TBytes;
    /// <summary>The drag-lint LSP server over the index, created on first
    /// use: Options.DbPaths, or Options.ResolveDbs() when that list is empty
    /// (P0 review I1: resolved lazily, never on the relay's startup path).
    /// Paths that do not exist are dropped before the server is created; when
    /// only some are missing, one stderr line names them.</summary>
    /// <returns>The server, or nil when no database exists or the server could
    /// not be created; the failure is reported once on stderr and never
    /// retried (fail-open).</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.AnnounceOpen (DRagLint.LSP.Proxy.Merge.pas), DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.AnswerOnWorker (DRagLint.LSP.Proxy.Merge.pas), DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.ComputeCompletion (DRagLint.LSP.Proxy.Merge.pas), DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.ComputeDefinition (DRagLint.LSP.Proxy.Merge.pas), DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.ComputeHover (DRagLint.LSP.Proxy.Merge.pas) (+1 more)</para>
    /// <para>Calls: DRagLint.LSP.Proxy.Merge.MergeErrLine, DRagLint.LSP.Server.TLSPServer.ApplyClientSettingsFile, DRagLint.LSP.Server.TLSPServer.Create/1, FileExists</para>
    /// <para>Returns: FServer</para>
    /// <para>Complexity: 10 (cyclomatic, outer body), 54 lines (full implementation)</para>
    /// <para>Reads: FServerLock, FServerTried, FOptions, FServer, FPendingSettingsFile   Writes: FServerTried, FServer, FPendingSettingsFile</para>
    /// <para>Owns returned: borrowed</para>
    /// <para>Catches: Exception (swallowed)</para>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.MergeErrLine"/>
    /// <seealso cref="DRagLint.LSP.Server.TLSPServer.ApplyClientSettingsFile"/>
    /// <seealso cref="DRagLint.LSP.Server.TLSPServer.Create"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.AnnounceOpen"/>
    /// <seealso cref="DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.Answer"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function Server: TLSPServer;
    /// <summary>The options this engine was created with.</summary>
    property Options: TLspProxyOptions read FOptions;
  end;

/// <summary>The body of a complete LSP frame, decoded as UTF-8.</summary>
/// <param name="AFrame">Buffer holding the frame at offset 0.</param>
/// <param name="ALen">Byte length of the frame in AFrame.</param>
/// <returns>The text after the blank line that ends the headers; an empty
/// string when no header terminator lies within ALen.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.Answer (DRagLint.LSP.Proxy.Merge.pas), DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.MergeDiagnostics (DRagLint.LSP.Proxy.Merge.pas), DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.MergeReply (DRagLint.LSP.Proxy.Merge.pas), DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.PickupContext (DRagLint.LSP.Proxy.Merge.pas), DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.RecordRequest (DRagLint.LSP.Proxy.Merge.pas) (+2 more)</para>
/// <para>Returns: ''; TEncoding.UTF8.GetString(AFrame, I + Length(HEADER_END), ALen - I - Length(HEADER_END))</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function FrameBody(const AFrame: TBytes; ALen: Integer): string;

/// <summary>Frames a UTF-8 body as one LSP message.</summary>
/// <param name="ABodyUtf8">The body bytes, already UTF-8.</param>
/// <returns>`Content-Length: N` CR LF CR LF followed by the body, where N is
/// the BYTE count of the body.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.AnnounceOpen (DRagLint.LSP.Proxy.Merge.pas), DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.MergeDiagnostics (DRagLint.LSP.Proxy.Merge.pas), DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.MergeReply (DRagLint.LSP.Proxy.Merge.pas), DRagLint.LSP.Proxy.Merge.TProxyMergeEngine.SendAnswer (DRagLint.LSP.Proxy.Merge.pas)</para>
/// <para>Calls: Format</para>
/// <para>Returns: Hdr + ABodyUtf8</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function BuildFrame(const ABodyUtf8: TBytes): TBytes;

implementation

uses
    Winapi.Windows
  , System.IOUtils
  , DRagLint.Core.Interfaces
  , DRagLint.Core.LintBudget
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

type
  { 1.52.3 MERGE-FULLRULES: the thread that runs the full-rules children. }
  TFullRulesWorker = class(TThread)
  private
    FOwner: TProxyMergeEngine;
  protected
    procedure Execute; override;
  public
    constructor Create(AOwner: TProxyMergeEngine);
  end;

constructor TFullRulesWorker.Create(AOwner: TProxyMergeEngine);
begin
  FOwner:= AOwner;
  FreeOnTerminate:= False;
  inherited Create(False);
end;

procedure TFullRulesWorker.Execute;
begin
  FOwner.FullRulesLoop;
end;

{ True when the proxy's own command line carries --full-rules (1.52.3
  MERGE-FULLRULES stopgap: TLspProxyOptions has no field for it yet). }
function CommandLineHasFullRules: Boolean;
begin
  Result:= False;
  for var I:= 1 to ParamCount do
    if SameText(ParamStr(I), '--full-rules') then Exit(True);
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

  { 1.52.3 MERGE-FULLRULES: the full-rules child's poll, reap and CPU-progress
    steps (the values of plain lsp's LSP_FULL_RULES_* in DRagLint.LSP.Server). }
  FULL_RULES_POLL_MS = 200;
  FULL_RULES_REAP_MS = 2000;
  FULL_RULES_CPU_PROGRESS_100NS = 50 * 10000;

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
  { --merge-navigation: each provider and the requests it covers. A follow-up
    (supertypes, incomingCalls) belongs to the provider of its prepare request. }
  NAV_CAPS: array[0..4] of string = ('typeHierarchyProvider', 'callHierarchyProvider', 'typeDefinitionProvider',
    'documentHighlightProvider', 'foldingRangeProvider');
  NAV_METHODS: array[0..8] of string = ('textDocument/prepareTypeHierarchy', 'typeHierarchy/supertypes', 'typeHierarchy/subtypes',
    'textDocument/prepareCallHierarchy', 'callHierarchy/incomingCalls', 'callHierarchy/outgoingCalls',
    'textDocument/typeDefinition', 'textDocument/documentHighlight', 'textDocument/foldingRange');
  NAV_METHOD_CAP: array[0..8] of Integer = (0, 0, 0, 1, 1, 1, 2, 3, 4);
  { What a frame holding any NAV_METHODS name must contain: a cheap pre-parse scan
    (four needles, not nine, on a path every client frame takes). }
  NAV_NEEDLES: array[0..3] of RawByteString = ('Hierarchy', 'textDocument/typeDefinition',
    'textDocument/documentHighlight', 'textDocument/foldingRange');
  MERGE_NAVIGATION_PREFIX = 'drag-lint lsp --proxy: merge-navigation ';
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

type
  { 1.52.2 PROXYMERGE: the diagnostics of one URI, as the proxy last saw and
    sent them. Owned by TProxyMergeEngine.FDiagStates (never removed before
    the engine's Destroy); every field is read and written under FDiagLock.
    Invariant: FDone is set exactly when FRunning is False. }
  TDiagState = class
  private   { unit-visible: only this unit's engine reads and writes them }
    FUri    : string;
    FBody   : string;    { DelphiLSP's last publishDiagnostics body for the URI }
    FOurs   : string;    { drag-lint's last findings (JSON array); '' = none known }
    FShown  : string;    { the drag-lint set the client was last sent; '' = none }
    FRunning: Boolean;   { a lint of the file is queued or running }
    FWaiting: Boolean;   { the S>C pump still waits for it inline (inside the budget) }
    FRerun  : Boolean;   { a publish arrived while it ran: lint again when it ends }
    FDone   : TEvent;
    { 1.52.3 MERGE-FULLRULES (--full-rules only) }
    FGen    : Integer;   { bumped by every subset lint: a full-rules result of an older one is stale }
    FHasFull: Boolean;   { FOurs holds a full `lint --json` set: a later subset does not replace it }
  public
    constructor Create;
    destructor Destroy; override;
  end;

constructor TDiagState.Create;
begin
  inherited Create;
  FDone:= TEvent.Create(nil, True, True, '');
end;

destructor TDiagState.Destroy;
begin
  FDone.Free;
  inherited Destroy;
end;

const
  { The over-budget hover answer's drag-lint part (owner 2026-11-20). The VS Code
    companion (lib/deferredhover.js PROXY_PLACEHOLDER) treats it as the deferred
    hover's placeholder. }
  HOVER_PLACEHOLDER = '_drag-lint: analysing..._';
  METHOD_DEFER_HOVER    = 'draglint/deferHover';
  METHOD_PROGRESS       = '$/progress';
  METHOD_PROGRESS_CREATE = 'window/workDoneProgress/create';
  PROGRESS_ID_PREFIX    = 'drag-lint-progress-';
  PROGRESS_TOKEN_PREFIX = 'drag-lint-lint-';
  HOVER_CACHE_MAX = 512;
  PROGRESS_IDS_MAX = 256;

{ True when a findings array (JSON) holds at least one finding. }
function HasFindings(const AOurs: string): Boolean;
begin
  Result:= (AOurs <> '') and (AOurs <> '[]');
end;

{ The publishDiagnostics frame for DelphiLSP's body ABody with drag-lint's
  findings AOurs appended (ABody alone when AOurs has none); nil when ABody
  does not parse. }
function ComposePublish(const ABody, AOurs: string): TBytes;
var
  Json : TJSONValue;
  Diags: TJSONArray;
  Added: TJSONValue;
  Elem : TJSONValue;
begin
  Result:= nil;
  Json:= TJSONObject.ParseJSONValue(ABody);
  try
    if (Json is not TJSONObject) or not Json.TryGetValue<TJSONArray>('params.diagnostics', Diags) then Exit;
    if HasFindings(AOurs) then
    begin
      Added:= TJSONObject.ParseJSONValue(AOurs);
      try
        if Added is TJSONArray then
          for Elem in TJSONArray(Added) do Diags.AddElement(TJSONValue(Elem.Clone));
      finally
        Added.Free;
      end;
    end;
    Result:= BuildFrame(TEncoding.UTF8.GetBytes(Json.ToJSON));
  finally
    Json.Free;
  end;
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

{ The hover cache key of one position (1-based line and column). }
function HoverKey(const APath: string; ALine1, ACol1: Integer): string;
begin
  Result:= DocKey(APath) + '#' + IntToStr(ALine1) + ':' + IntToStr(ACol1);
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
  FStateLock := TCriticalSection.Create;
  FJobReady  := TEvent.Create(nil, False, False, '');
  FWorker    := TMergeWorker.Create(Self);
  FTestEmptyReplacement:= GetEnvironmentVariable('DRAGLINT_MERGE_TEST_EMPTY_REPLACEMENT') = '1';
  FTestAnswerInline    := GetEnvironmentVariable('DRAGLINT_MERGE_TEST_ANSWER_INLINE') = '1';
  FTestFastPath        := GetEnvironmentVariable('DRAGLINT_MERGE_TEST_FASTPATH') = '1';
  FTestLintDelayMs     := StrToIntDef(GetEnvironmentVariable('DRAGLINT_MERGE_TEST_LINT_DELAY_MS'), 0);
  FDiagStates := TDictionary<string, TObject>.Create;
  FDiagLock   := TCriticalSection.Create;
  FHoverCache := TDictionary<string, string>.Create;
  FProgressIds:= TDictionary<string, Boolean>.Create;
  FAnsweredIds         := TDictionary<string, Boolean>.Create;
  FDirty    := TDictionary<string, Boolean>.Create;
  FDirtyLock:= TCriticalSection.Create;
  FQueue      := TQueue<TProc>.Create;
  FPending    := TDictionary<string, TObject>.Create;
  FPendingLock:= TCriticalSection.Create;
  FDocUpdates := TDictionary<string, TDocUpdate>.Create;
  FDocLock    := TCriticalSection.Create;
  FAnswersIdle:= TEvent.Create(nil, True, True, '');
  FFullRules  := AOptions.MergeDiagnostics and CommandLineHasFullRules;
  FFullLock   := TCriticalSection.Create;
  FFullReady  := TEvent.Create(nil, False, False, '');
  FFullQueue  := TList<TFullJob>.Create;
  if FFullRules then FFullThread:= TFullRulesWorker.Create(Self);
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
  { after the merge worker: it is the one that queues full-rules jobs }
  if FFullThread <> nil then
  begin
    FFullThread.Terminate;
    FFullLock.Enter;
    try
      if FFullProcess <> 0 then TerminateProcess(FFullProcess, 1);
    finally
      FFullLock.Leave;
    end;
    FFullReady.SetEvent;
    FFullThread.WaitFor;
    FFullThread.Free;
  end;
  FFullQueue.Free;
  FFullReady.Free;
  FFullLock.Free;
  FServer.Free;
  FLinter.Free;
  for var Left: TObject in FPending.Values do TPendingRequest(Left).Release;
  FPending.Free;
  if FDiagStates <> nil then
    for var St: TObject in FDiagStates.Values do St.Free;
  FDiagStates.Free;
  FDiagLock.Free;
  FHoverCache.Free;
  FProgressIds.Free;
  FPendingLock.Free;
  FDocUpdates.Free;
  FDocLock.Free;
  FAnswersIdle.Free;
  FQueue.Free;
  FDirty.Free;
  FDirtyLock.Free;
  FAnsweredIds.Free;
  FJobReady.Free;
  FStateLock.Free;
  FServerLock.Free;
  inherited Destroy;
end;

procedure TProxyMergeEngine.WorkerLoop;
var
  Work: TProc;
begin
  while not TThread.CheckTerminated do
  begin
    FJobReady.WaitFor(INFINITE);
    { Drain: one wake-up may stand for several queued jobs (auto-reset event). }
    while not TThread.CheckTerminated do
    begin
      FStateLock.Enter;
      try
        Work:= if FQueue.Count > 0 then FQueue.Dequeue() else nil;
      finally
        FStateLock.Leave;
      end;
      if not Assigned(Work) then Break;
      try
        Work();
      except  // a queued job publishes through its own state; a raise must not end the worker
        on E: Exception do MergeErrLine('drag-lint lsp --proxy: a merge job raised (' + E.ClassName + ': ' + E.Message + ').');
      end;
      Work:= nil;  // dl:ok overwrite-before-read@f29e -- releases the job closure (and what it captured) before blocking for the next job
    end;
  end;
end;

{ Queues AWork on the merge worker and returns at once; nobody waits on it, so
  it must publish its result through its own captured state. False (AWork is
  dropped, never run) when QUEUE_MAX jobs are already waiting. }
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
        if FOptions.MergeCompletion or FOptions.MergeHover or FOptions.MergeDefinition or FOptions.MergeNavigation then Server;   { opens the index; a failure is reported there }
      finally
        TInterlocked.Exchange(FWarming, 0);
      end;
    end) then
    TInterlocked.Exchange(FWarming, 0);
end;

{ C>S: with MergeDiagnostics, didChange marks the document dirty and didSave /
  didOpen / didClose clear it; with MergeCompletion or MergeHover, the text the notification
  implies is queued for the live-document overlay. A first didOpen also warms
  the worker. Runs on the C>S pump thread, inline (no worker). }
{ C>S, didOpen: queues (never waits) the announcement of the file's context on the
  merge worker: the embedded server then sends draglint/context with its notice
  through the client writer and starts the background re-index of a project DB
  marked needs-re-resolve (once per DB: the server keys the run by DB). Needs
  the server, so only when an index-backed merge is on and a writer is set. }
procedure TProxyMergeEngine.AnnounceOpen(const APath: string);
begin
  if not (FOptions.MergeCompletion or FOptions.MergeHover or FOptions.MergeDefinition or FOptions.MergeNavigation) or not Assigned(FClientWriter) then Exit;
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
  DirtyOnly:= FOptions.MergeDiagnostics and not (FOptions.MergeCompletion or FOptions.MergeHover or FOptions.MergeDefinition or FOptions.MergeNavigation);
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
      if FOptions.MergeCompletion or FOptions.MergeHover or FOptions.MergeDefinition or FOptions.MergeNavigation then
      begin
        Upd:= LiveUpdateOf(Method, Json, LiveText);
        if Upd <> luNone then QueueDocUpdate(Path, Upd = luRemove, LiveText);
      end;
      if FOptions.MergeHover then ForgetHovers(Path);   { the text may have changed: cached hover parts go }
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
procedure TProxyMergeEngine.RecordRequest(const AFrame: TBytes; ALen: Integer);  // dl:ok too-many-exit-points@3bc9, cyclomatic-complexity@6112 -- each Exit is a decline (nothing recorded, relay unchanged); one flat guard sequence reads better than nesting (re-reviewed A5: 8 exits; the four request kinds share one parse, so the kind selection adds branches, not state)
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
  Init := (FOptions.MergeDefinition or FOptions.MergeNavigation) and FrameContains(AFrame, ALen, '"' + METHOD_INITIALIZE + '"');
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
      { 1.52.2: a position whose drag-lint part was computed before (often
        late, past the budget) answers from the cache, at once. }
      if (Kind = rkHover) and CachedHover(HoverKey(Path, Line0 + 1, Col0 + 1), P.FItems) then
      begin
        P.FDone.SetEvent;
        Exit;
      end;
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
  Mask: Integer;
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
  if FOptions.MergeDefinition then
  begin
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
  if FOptions.MergeNavigation then
  begin
    Mask:= 0;
    for var I: Integer:= Low(NAV_CAPS) to High(NAV_CAPS) do
      if Advertises(TJSONObject(Caps).GetValue(NAV_CAPS[I])) then Mask:= Mask or (1 shl I)
      else
      begin
        TJSONObject(Caps).RemovePair(NAV_CAPS[I]).Free;
        TJSONObject(Caps).AddPair(NAV_CAPS[I], TJSONBool.Create(True));
        Result:= True;
      end;
    TInterlocked.Exchange(FTheirNavigation, Mask);
  end;
end;

{ The NAV_METHODS index of AMethod when --merge-navigation owes it an answer: on,
  and DelphiLSP did not advertise its provider. -1 otherwise. }
function TProxyMergeEngine.NavMethodIndex(const AMethod: string): Integer;
begin
  Result:= -1;
  if not FOptions.MergeNavigation then Exit;
  for var I: Integer:= Low(NAV_METHODS) to High(NAV_METHODS) do
    if AMethod = NAV_METHODS[I] then
    begin
      if (TInterlocked.CompareExchange(FTheirNavigation, 0, 0) and (1 shl NAV_METHOD_CAP[I])) = 0 then Result:= I;
      Exit;
    end;
end;

{ Could this frame hold a NAV_METHODS request? The scan before the parse. }
function TProxyMergeEngine.MayBeNavRequest(const AFrame: TBytes; ALen: Integer): Boolean;
begin
  Result:= False;
  if not FOptions.MergeNavigation then Exit;
  for var Needle: RawByteString in NAV_NEEDLES do
    if FrameContains(AFrame, ALen, Needle) then Exit(True);
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
  Nav   : Boolean;
  Hov   : Boolean;
  Job   : TAnswerJob;
begin
  Result:= False;
  if not Assigned(FClientWriter) then Exit;
  { 1.52.2: the client's reply to our progress create, and the VS Code
    deferred-hover announcement, are the proxy's own traffic. }
  if TakeProgressReply(AFrame, ALen, AOnTake) or TakeDeferHover(AFrame, ALen, AOnTake) then Exit(True);
  if not (FOptions.MergeDefinition or FOptions.MergeNavigation or FOptions.MergeHover) then Exit;
  if TakeCancel(AFrame, ALen, AOnTake) then Exit(True);
  Refs:= FOptions.MergeDefinition and (TInterlocked.CompareExchange(FTheirReferences, 0, 0) = 0) and FrameContains(AFrame, ALen, METHOD_REFERENCES);
  Syms:= FOptions.MergeDefinition and (TInterlocked.CompareExchange(FTheirSymbols, 0, 0) = 0) and FrameContains(AFrame, ALen, METHOD_WORKSPACE_SYMBOL);
  Nav := MayBeNavRequest(AFrame, ALen);
  { the deferred hover's WHOLE step: the second hover at the announced position }
  Hov := FOptions.MergeHover and (FDeferKey <> '') and FrameContains(AFrame, ALen, METHOD_HOVER);
  if not (Refs or Syms or Nav or Hov) then Exit;
  Method:= '';
  try
    Json:= TJSONObject.ParseJSONValue(FrameBody(AFrame, ALen));
    try
      if not (Json is TJSONObject) or not Json.TryGetValue<string>('method', Method) then Exit;
      Refs:= Refs and (Method = METHOD_REFERENCES);
      Syms:= Syms and (Method = METHOD_WORKSPACE_SYMBOL);
      Nav := Nav and (NavMethodIndex(Method) >= 0);
      Hov := Hov and (Method = METHOD_HOVER);
      if not (Refs or Syms or Nav or Hov) then Exit;
      IdVal:= TJSONObject(Json).GetValue('id');
      if IdVal = nil then Exit;   { a notification of that name is not a request we owe }
      Job.Id         := IdVal.ToJSON;
      Job.Symbols    := Syms;
      Job.Query      := '';
      Job.Path       := '';
      Job.Line0      := 0;
      Job.Col0       := 0;
      Job.IncludeDecl:= True;   { as TLSPServer.HandleReferences defaults it }
      Job.NavMethod  := '';
      Job.NavParams  := '';
      Job.Hover      := False;
      if Hov then
      begin
        { The first hover there is the fast step (forwarded and merged as
          usual); the second is the companion's whole step, answered here. }
        if not (Json.TryGetValue<string>('params.textDocument.uri', Uri) and
                Json.TryGetValue<Integer>('params.position.line', Job.Line0) and
                Json.TryGetValue<Integer>('params.position.character', Job.Col0)) then Exit;
        Job.Path:= TLSPServer.FileFromUri(Uri);
        if HoverKey(Job.Path, Job.Line0 + 1, Job.Col0 + 1) <> FDeferKey then Exit;
        Inc(FDeferHovers);
        if FDeferHovers < 2 then Exit;
        FDeferKey:= '';
        Job.Hover:= True;
      end
      else if Nav then
      begin
        Job.NavMethod:= Method;
        var NavParams: TJSONValue:= TJSONObject(Json).GetValue('params');
        if NavParams is TJSONObject then Job.NavParams:= NavParams.ToJSON;
      end
      else if Syms then
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
      if AJob.Hover then
      begin
        Body:= 'null';
        if S <> nil then Body:= HoverAnswer(S, AJob);
      end
      else if AJob.NavMethod <> '' then
      begin
        if S <> nil then Body:= NavAnswer(S, AJob);
      end
      else if S <> nil then
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
        MergeErrLine((if AJob.NavMethod <> '' then MERGE_NAVIGATION_PREFIX else MERGE_DEFINITION_PREFIX) +
                     'answered a request with [] (' + E.ClassName + ': ' + E.Message + ').');
    end;
    SendAnswer(AJob.Id, Body);
  finally
    EndAnswer;
  end;
end;

{ Worker thread: the registered feature's result for one --merge-navigation
  request, as JSON. Whatever the plain server would answer, null included; [] when
  no feature answered. }
function TProxyMergeEngine.NavAnswer(const AServer: TLSPServer; const AJob: TAnswerJob): string;
var
  Params: TJSONValue;
  Res   : TJSONValue;
begin
  Result:= '[]';
  Params:= nil;
  if AJob.NavParams <> '' then Params:= TJSONObject.ParseJSONValue(AJob.NavParams);
  try
    Res:= AServer.ComputeFeatureResult(AJob.NavMethod, Params as TJSONObject);
    if Res <> nil then
      try
        Result:= Res.ToJSON;
      finally
        Res.Free;
      end;
  finally
    Params.Free;
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
      else
      begin
        P.FItems:= S.ComputeHoverMarkdown(P.FPath, P.FLine1 - 1, P.FCol1 - 1);
        CacheHover(HoverKey(P.FPath, P.FLine1, P.FCol1), P.FItems);   { a late answer serves the next hover }
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
      if P = nil then Exit;   { not ours }
      if TJSONObject(Json).GetValue('result') = nil then
      begin
        { 1.52.3 HOVER-ISE (VS Code log 2026-11-20 07:04 / 07:07: "Request
          textDocument/hover failed. Internal server error -32603" -- DelphiLSP's
          own error reply, after an EAccessViolation in DelphiLSP.exe): an error
          reply to a HOVER is merged as a null result, so drag-lint's part (or
          the placeholder) still shows. With nothing of ours to add the original
          error bytes go out. Any other kind: forwarded as is. }
        if (P.FKind <> rkHover) or (TJSONObject(Json).GetValue('error') = nil) then Exit;
        if TInterlocked.Exchange(FHoverErrWarned, 1) = 0 then
          MergeErrLine(MERGE_HOVER_PREFIX + 'DelphiLSP answered a hover with an error (' +
                       TJSONObject(Json).GetValue('error').ToJSON + '); drag-lint''s part is sent alone (reported once).');
        TJSONObject(Json).RemovePair('error').Free;
        TJSONObject(Json).AddPair('result', TJSONNull.Create);
      end;
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
      { A hover whose part is ready (cached, or done late) is merged whatever it took. }
      if (P.FDone.WaitFor(Cardinal(Remain)) <> wrSignaled) or
         ((P.FElapsed > UInt64(FOptions.MergeBudgetMs)) and (P.FKind <> rkHover)) then
      begin
        case P.FKind of
          rkHover     : Warned:= TInterlocked.Exchange(FHoverWarned, 1);
          rkDefinition: Warned:= TInterlocked.Exchange(FDefinitionWarned, 1);
          else Warned:= TInterlocked.Exchange(FCompletionWarned, 1);
        end;
        if Warned = 0 then
          MergeErrLine(Prefix + 'over its ' + IntToStr(FOptions.MergeBudgetMs) +
                       ' ms budget; the ' + KindName(P.FKind) + ' reply is forwarded ' +
                       (if P.FKind = rkHover then 'with an "analysing" placeholder; drag-lint''s part is cached for the next hover'
                        else 'unmerged') + ' (reported once).');
        { 1.52.2 (owner 2026-11-20): a hover says drag-lint's part is coming
          (the job runs on and caches it; the VS Code companion asks again). }
        if (P.FKind = rkHover) and MergeHoverResult(TJSONObject(Json), HOVER_PLACEHOLDER) then
        begin
          AReplacement:= BuildFrame(TEncoding.UTF8.GetBytes(Json.ToJSON));
          Result:= True;
        end;
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
  Ours  : string;
  Added : TJSONValue;
  Elem  : TJSONValue;
  Obj   : TObject;
  St    : TDiagState;
  Dirty : Boolean;
  Start : Boolean;
  Late  : Boolean;

  procedure Skip(const AWhy: string);
  begin
    MergeErrLine(MERGE_ERR_PREFIX + 'skipped a frame (' + AWhy + '); forwarded unchanged.');
  end;

begin
  Result:= False;
  AReplacement:= nil;
  FPublishPending:= nil;
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
      { Unsaved edits: our on-disk ranges would lie, so no NEW lint; the last
        known set still goes with the forward (as plain `lsp` keeps it shown). }
      Dirty:= IsDirty(Path);
      Start:= False;
      Late := False;
      FDiagLock.Enter;
      try
        if FDiagStates.TryGetValue(DocKey(Path), Obj) then St:= TDiagState(Obj)
        else
        begin
          St:= TDiagState.Create;
          FDiagStates.Add(DocKey(Path), St);
        end;
        St.FUri := Uri;
        St.FBody:= FrameBody(AFrame, ALen);
        if not Dirty then
        begin
          if St.FRunning then St.FRerun:= True   { a newer compile: lint again when this one ends }
          else
          begin
            Start:= True;
            St.FRunning:= True;
            St.FWaiting:= True;
            St.FDone.ResetEvent;
          end;
        end;
      finally
        FDiagLock.Leave;
      end;
      if Start and StartLint(St, Path) then
        St.FDone.WaitFor(Cardinal(if FOptions.MergeBudgetMs < 0 then 0 else FOptions.MergeBudgetMs));
      { Inside the budget the fresh set goes in this frame; past it the worker
        publishes the merged set the moment the lint ends (owner 2026-11-20),
        and this frame carries the last known one. }
      FDiagLock.Enter;
      try
        if Start and St.FRunning then
        begin
          St.FWaiting:= False;
          Late:= True;
        end;
        Ours:= St.FOurs;
        St.FShown:= if HasFindings(Ours) then Ours else '';
        FPublishPending:= St;   { FinishServerFrame re-checks it under the client lock }
        FPublishOurs   := Ours;
      finally
        FDiagLock.Leave;
      end;
      if Late and (not FBudgetWarned) and (TInterlocked.CompareExchange(FWarming, 0, 0) = 0) then
      begin
        FBudgetWarned:= True;   { S>C pump thread only: no lock needed }
        MergeErrLine(MERGE_ERR_PREFIX + 'over its ' + IntToStr(FOptions.MergeBudgetMs) +
                     ' ms budget; publishDiagnostics is forwarded with the last known drag-lint findings and re-published merged when the lint ends (reported once).');
      end;
      if not HasFindings(Ours) then Exit;   { nothing of ours known: original bytes }

      Added:= TJSONObject.ParseJSONValue(Ours);
      try
        if Added is not TJSONArray then Exit;
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

function TProxyMergeEngine.FinishServerFrame: TBytes;
var
  St   : TDiagState;
  Cur  : string;
  Shown: string;
  Was  : string;
  Frame: TBytes;
begin
  Result:= nil;
  if FPublishPending = nil then Exit;
  St:= TDiagState(FPublishPending);
  FPublishPending:= nil;
  FDiagLock.Enter;
  try
    Cur:= St.FOurs;
    { Locals on purpose: comparing two if-expressions directly
      (`(if A then X else '') = (if B then Y else '')`) answered equal here
      under Delphi 13 Win64 Debug and the recomposed frame was never sent. }
    Shown:= if HasFindings(Cur) then Cur else '';
    Was  := if HasFindings(FPublishOurs) then FPublishOurs else '';
    if Shown = Was then Exit;
    { a lint ended after Intercept composed this frame: send the current set }
    Frame:= ComposePublish(St.FBody, Cur);
    if Frame = nil then Exit;
    Result   := Frame;
    St.FShown:= Shown;
  finally
    FDiagLock.Leave;
  end;
end;

function TProxyMergeEngine.StartLint(AState: TObject; const APath: string): Boolean;
var
  St: TDiagState;
begin
  St:= TDiagState(AState);
  Result:= Enqueue(
    procedure
    begin
      LintOnWorker(St, APath);
    end);
  if Result then Exit;
  FDiagLock.Enter;   { queue full: nothing will lint, so the state is idle again }
  try
    St.FRunning:= False;
    St.FWaiting:= False;
    St.FDone.SetEvent;
  finally
    FDiagLock.Leave;
  end;
end;

procedure TProxyMergeEngine.LintOnWorker(AState: TObject; const APath: string);
var
  St   : TDiagState;
  Items: string;
  Err  : string;
  Arr  : TJSONArray;
  Frame: TBytes;
  Shown: string;
  Rerun: Boolean;
  Token: string;
  Publish: TProc;
  Gen  : Integer;
begin
  St   := TDiagState(AState);
  Items:= '';
  Err  := '';
  Frame:= nil;
  FDiagLock.Enter;
  try
    Inc(St.FGen);   { a full-rules run of an older lint is stale from here on }
    Gen:= St.FGen;
  finally
    FDiagLock.Leave;
  end;
  Token:= ProgressBegin(ExtractFileName(APath));
  try
    try
      if FTestLintDelayMs > 0 then Sleep(FTestLintDelayMs);
      EnsureLinter;
      Arr:= TLspCompletion.BuildDiagnostics(FLinter, APath, nil);
      try
        Items:= Arr.ToJSON;
      finally
        Arr.Free;
      end;
    except   { not swallowed: the message is logged below and the last known set stays }
      on E: Exception do Err:= E.ClassName + ': ' + E.Message;
    end;
    if Err <> '' then MergeErrLine(MERGE_ERR_PREFIX + 'skipped a lint (' + Err + '); the last known findings stay.');
    { 1.52.2 HOVER: compose AND write under the relay's client lock, so a
      publish the S>C pump is forwarding cannot land after this one with an
      older set (FinishServerFrame re-checks the pump's frame under it). }
    Publish:=
      procedure
      begin
        FDiagLock.Enter;
        try
          { --full-rules: the last full set stays shown until the next full run
            ends, as plain `lsp --full-rules` keeps it until the child is done. }
          if (Err = '') and not St.FHasFull then St.FOurs:= Items;
          { Nobody waits inline any more: publish the merged set ourselves, when
            it differs from what the client was last sent. }
          if not St.FWaiting then
          begin
            Shown:= if HasFindings(St.FOurs) then St.FOurs else '';
            if Shown <> St.FShown then
            begin
              Frame:= ComposePublish(St.FBody, St.FOurs);
              if Frame <> nil then St.FShown:= Shown;
            end;
          end;
          St.FWaiting:= False;
          Rerun:= St.FRerun;
          St.FRerun:= False;
          St.FRunning:= Rerun;
          if not Rerun then St.FDone.SetEvent;
        finally
          FDiagLock.Leave;
        end;
        if (Frame <> nil) and Assigned(FClientWriter) then FClientWriter(Frame);
      end;
    if Assigned(FClientLocker) then FClientLocker(Publish) else Publish();
  finally
    ProgressEnd(Token);
  end;
  if Rerun then StartLint(St, APath)
  else if FFullRules and (Err = '') then QueueFullRules(St, APath, Gen);
end;

procedure TProxyMergeEngine.QueueFullRules(AState: TObject; const APath: string; AGen: Integer);
var
  Job: TFullJob;
begin
  Job.State:= AState;
  Job.Path := APath;
  Job.Gen  := AGen;
  FFullLock.Enter;
  try
    for var I:= FFullQueue.Count - 1 downto 0 do
      if FFullQueue[I].State = AState then FFullQueue.Delete(I);
    FFullQueue.Add(Job);
  finally
    FFullLock.Leave;
  end;
  FFullReady.SetEvent;
end;

procedure TProxyMergeEngine.FullRulesLoop;
var
  Job    : TFullJob;
  Have   : Boolean;
  Json   : string;
  Arr    : TJSONArray;
  Items  : string;
  Started: UInt64;
  Count  : Integer;
begin
  while not TThread.CheckTerminated do
  begin
    FFullReady.WaitFor(INFINITE);
    while not TThread.CheckTerminated do
    begin
      FFullLock.Enter;
      try
        Have:= FFullQueue.Count > 0;
        if Have then
        begin
          Job:= FFullQueue[0];
          FFullQueue.Delete(0);
        end;
      finally
        FFullLock.Leave;
      end;
      if not Have then Break;
      Started:= GetTickCount64;
      Items  := '';
      Count  := -1;
      try
        if RunFullRulesChild(Job, Json) then
        begin
          Arr:= TLspCompletion.DiagnosticsFromLintJson(Json);
          if Arr <> nil then
          try
            Items:= Arr.ToJSON;
            Count:= Arr.Count;
          finally
            Arr.Free;
          end;
        end;
      except
        on E: Exception do MergeErrLine(MERGE_ERR_PREFIX + 'full-rules run raised (' + E.ClassName + ': ' + E.Message + ').');
      end;
      if TThread.CheckTerminated then Break;
      if Count >= 0 then
      begin
        MergeErrLine(Format('drag-lint lsp --proxy: full-rules %s %d ms %d findings', [Job.Path, GetTickCount64 - Started, Count]));
        ApplyFullRules(Job, Items, True);
      end
      else
      begin
        MergeErrLine('drag-lint lsp --proxy: full-rules skipped (stalled, superseded, failed run or invalid JSON); the subset stays: ' + Job.Path);
        FDiagLock.Enter;
        try
          if TDiagState(Job.State).FGen = Job.Gen then TDiagState(Job.State).FHasFull:= False;   { the next subset lint is shown again }
        finally
          FDiagLock.Leave;
        end;
      end;
    end;
  end;
end;

{ Superseded = the state's generation moved on (a newer subset lint started). }
function FullJobStale(ALock: TCriticalSection; const AJob: TProxyMergeEngine.TFullJob): Boolean;
begin
  ALock.Enter;
  try
    Result:= TDiagState(AJob.State).FGen <> AJob.Gen;
  finally
    ALock.Leave;
  end;
end;

function TProxyMergeEngine.RunFullRulesChild(const AJob: TFullJob; out AJson: string): Boolean;
var
  Sa      : TSecurityAttributes;
  TmpPath : string;
  HOut    : THandle;
  HNul    : THandle;
  Si      : TStartupInfo;
  Pi      : TProcessInformation;
  Cmd     : string;
  ChildExe: string;
  Code    : DWORD;
  Budget  : Cardinal;
  Deadline: UInt64;
  LastSize: DWORD;
  Size    : DWORD;
  CpuMark : Int64;
  Cpu     : Int64;
  CreateT, ExitT, KernelT, UserT: TFileTime;
begin
  Result:= False;
  AJson := '';
  if FullJobStale(FDiagLock, AJob) then Exit;
  Budget := LintChildTimeoutMs('');
  TmpPath:= TPath.GetTempFileName;
  FillChar(Sa, SizeOf(Sa), 0);
  Sa.nLength       := SizeOf(Sa);
  Sa.bInheritHandle:= True;
  HOut:= CreateFile(PChar(TmpPath), GENERIC_WRITE, FILE_SHARE_READ, @Sa, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, 0);
  HNul:= CreateFile('NUL', GENERIC_READ or GENERIC_WRITE, FILE_SHARE_READ or FILE_SHARE_WRITE, @Sa, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, 0);
  try
    if (HOut = INVALID_HANDLE_VALUE) or (HNul = INVALID_HANDLE_VALUE) then Exit;
    FillChar(Si, SizeOf(Si), 0);
    Si.cb         := SizeOf(Si);
    Si.dwFlags    := STARTF_USESTDHANDLES or STARTF_USESHOWWINDOW;
    Si.wShowWindow:= SW_HIDE;
    Si.hStdInput  := HNul;
    Si.hStdOutput := HOut;
    Si.hStdError  := HNul;
    { the same child plain `lsp --full-rules` runs (TLSPServer.RunFullRulesLint),
      including its test-only stub override }
    ChildExe:= GetEnvironmentVariable('DRAGLINT_FULLRULES_CHILD_EXE');
    if ChildExe = '' then ChildExe:= ParamStr(0);
    Cmd:= '"' + ChildExe + '" lint "' + StringReplace(AJob.Path, '"', '', [rfReplaceAll]) + '" --json --output-encoding utf8';
    for var DbP in FOptions.DbPaths do
      if DbP <> '' then Cmd:= Cmd + ' --db "' + StringReplace(DbP, '"', '', [rfReplaceAll]) + '"';
    UniqueString(Cmd);
    if not CreateProcess(PChar(ChildExe), PChar(Cmd), nil, nil, True, CREATE_NO_WINDOW, nil, nil, Si, Pi) then Exit;  // dl:ok taint-command-injection@6e02 -- REVIEWED 2026-11-20: the exe is our own (ParamStr(0) or the test-only DRAGLINT_FULLRULES_CHILD_EXE, same trust as the process); every argument is quoted with every double quote dropped
    try
      FFullLock.Enter;
      try
        FFullProcess:= Pi.hProcess;
      finally
        FFullLock.Leave;
      end;
      { a STALL budget, as plain lsp: output growth or CPU progress re-arms it }
      LastSize:= 0;
      CpuMark := 0;
      Deadline:= GetTickCount64 + Budget;
      while WaitForSingleObject(Pi.hProcess, FULL_RULES_POLL_MS) <> WAIT_OBJECT_0 do
      begin
        if TThread.CheckTerminated or FullJobStale(FDiagLock, AJob) or (GetTickCount64 >= Deadline) then
        begin
          TerminateProcess(Pi.hProcess, 1);
          WaitForSingleObject(Pi.hProcess, FULL_RULES_REAP_MS);
          Exit;
        end;
        Size:= GetFileSize(HOut, nil);
        if (Size <> INVALID_FILE_SIZE) and (Size > LastSize) then
        begin
          LastSize:= Size;
          Deadline:= GetTickCount64 + Budget;
        end;
        if GetProcessTimes(Pi.hProcess, CreateT, ExitT, KernelT, UserT) then
        begin
          Cpu:= PInt64(@UserT)^ + PInt64(@KernelT)^;
          if Cpu - CpuMark >= FULL_RULES_CPU_PROGRESS_100NS then
          begin
            CpuMark := Cpu;
            Deadline:= GetTickCount64 + Budget;
          end;
        end;
      end;
      Code:= 1;
      GetExitCodeProcess(Pi.hProcess, Code);
      CloseHandle(HOut);
      HOut:= INVALID_HANDLE_VALUE;
      try
        AJson:= TFile.ReadAllText(TmpPath, TEncoding.UTF8);
      except
        on Exception do AJson:= '';  // dl:ok try-except-swallowed -- REVIEWED 2026-11-20: an unreadable result is a failed run; the caller keeps the subset
      end;
      Result:= (Code <= 1) and AJson.TrimLeft.StartsWith('[');
    finally
      FFullLock.Enter;
      try
        FFullProcess:= 0;
      finally
        FFullLock.Leave;
      end;
      CloseHandle(Pi.hThread);
      CloseHandle(Pi.hProcess);
    end;
  finally
    if HOut <> INVALID_HANDLE_VALUE then CloseHandle(HOut);
    if HNul <> INVALID_HANDLE_VALUE then CloseHandle(HNul);
    try
      TFile.Delete(TmpPath);
    except  // dl:ok try-except-swallowed -- REVIEWED 2026-11-20: a leftover temp file is harmless; the full-rules thread must not die on it
      on Exception do ;
    end;
  end;
end;

procedure TProxyMergeEngine.ApplyFullRules(const AJob: TFullJob; const AItems: string; AFull: Boolean);
var
  St     : TDiagState;
  Frame  : TBytes;
  Publish: TProc;
begin
  St   := TDiagState(AJob.State);
  Frame:= nil;
  Publish:=
    procedure
    var
      Shown: string;
    begin
      FDiagLock.Enter;
      try
        if (St.FGen <> AJob.Gen) or St.FRunning then Exit;   { a newer lint owns the URI now }
        St.FOurs   := AItems;
        St.FHasFull:= AFull;
        Shown:= if HasFindings(St.FOurs) then St.FOurs else '';
        if Shown <> St.FShown then
        begin
          Frame:= ComposePublish(St.FBody, St.FOurs);
          if Frame <> nil then St.FShown:= Shown;
        end;
      finally
        FDiagLock.Leave;
      end;
      if (Frame <> nil) and Assigned(FClientWriter) then FClientWriter(Frame);
    end;
  if Assigned(FClientLocker) then FClientLocker(Publish) else Publish();
end;

function TProxyMergeEngine.ProgressBegin(const AUnit: string): string;
var
  N    : Integer;
  Id   : string;
  Msg  : TJSONObject;
  Value: TJSONObject;
  Par  : TJSONObject;
begin
  Result:= '';
  if (TInterlocked.CompareExchange(FClientProgress, 0, 0) = 0) or not Assigned(FClientWriter) then Exit;
  N:= TInterlocked.Increment(FProgressSeq);
  Id:= PROGRESS_ID_PREFIX + IntToStr(N);
  Result:= PROGRESS_TOKEN_PREFIX + IntToStr(N);
  FPendingLock.Enter;
  try
    if FProgressIds.Count >= PROGRESS_IDS_MAX then FProgressIds.Clear;
    FProgressIds.AddOrSetValue('"' + Id + '"', True);
  finally
    FPendingLock.Leave;
  end;
  FClientWriter(BuildFrame(TEncoding.UTF8.GetBytes('{"jsonrpc":"2.0","id":"' + Id + '","method":"' +
    METHOD_PROGRESS_CREATE + '","params":{"token":"' + Result + '"}}')));
  Msg:= TJSONObject.Create;
  try
    Value:= TJSONObject.Create;
    Value.AddPair('kind', 'begin');
    Value.AddPair('title', 'drag-lint');
    Value.AddPair('message', 'analysing ' + AUnit);
    Value.AddPair('cancellable', TJSONBool.Create(False));
    Par:= TJSONObject.Create;
    Par.AddPair('token', Result);
    Par.AddPair('value', Value);
    Msg.AddPair('jsonrpc', '2.0');
    Msg.AddPair('method', METHOD_PROGRESS);
    Msg.AddPair('params', Par);
    FClientWriter(BuildFrame(TEncoding.UTF8.GetBytes(Msg.ToJSON)));
  finally
    Msg.Free;
  end;
end;

procedure TProxyMergeEngine.ProgressEnd(const AToken: string);
begin
  if (AToken = '') or not Assigned(FClientWriter) then Exit;
  FClientWriter(BuildFrame(TEncoding.UTF8.GetBytes('{"jsonrpc":"2.0","method":"' + METHOD_PROGRESS +
    '","params":{"token":"' + AToken + '","value":{"kind":"end"}}}')));
end;

function TProxyMergeEngine.TakeProgressReply(const AFrame: TBytes; ALen: Integer; const AOnTake: TProc): Boolean;
var
  Json : TJSONValue;
  IdVal: TJSONValue;
begin
  Result:= False;
  if not FrameContains(AFrame, ALen, PROGRESS_ID_PREFIX) then Exit;
  try
    Json:= TJSONObject.ParseJSONValue(FrameBody(AFrame, ALen));
    try
      if (Json is not TJSONObject) or (TJSONObject(Json).GetValue('method') <> nil) then Exit;
      IdVal:= TJSONObject(Json).GetValue('id');
      if IdVal = nil then Exit;
      FPendingLock.Enter;
      try
        Result:= FProgressIds.ContainsKey(IdVal.ToJSON);
        if Result then FProgressIds.Remove(IdVal.ToJSON);
      finally
        FPendingLock.Leave;
      end;
    finally
      Json.Free;
    end;
  except   { a frame that does not parse is not our reply: forwarded }
    on E: Exception do Result:= False;
  end;
  if Result and Assigned(AOnTake) then AOnTake;
end;

function TProxyMergeEngine.TakeDeferHover(const AFrame: TBytes; ALen: Integer; const AOnTake: TProc): Boolean;
var
  Json  : TJSONValue;
  Method: string;
  Uri   : string;
  Line0 : Integer;
  Col0  : Integer;
begin
  Result:= False;
  if not FOptions.MergeHover or not FrameContains(AFrame, ALen, METHOD_DEFER_HOVER) then Exit;
  try
    Json:= TJSONObject.ParseJSONValue(FrameBody(AFrame, ALen));
    try
      if (Json is not TJSONObject) or not Json.TryGetValue<string>('method', Method) or
         (Method <> METHOD_DEFER_HOVER) or (TJSONObject(Json).GetValue('id') <> nil) then Exit;
      Result:= True;   { ours either way: DelphiLSP has no use for it }
      FDeferKey:= if Json.TryGetValue<string>('params.textDocument.uri', Uri) and
                     Json.TryGetValue<Integer>('params.position.line', Line0) and
                     Json.TryGetValue<Integer>('params.position.character', Col0)
                   then HoverKey(TLSPServer.FileFromUri(Uri), Line0 + 1, Col0 + 1) else '';
      FDeferHovers:= 0;
    finally
      Json.Free;
    end;
  except   { a frame that does not parse is forwarded as before }
    on E: Exception do Result:= False;
  end;
  if Result and Assigned(AOnTake) then AOnTake;
end;

procedure TProxyMergeEngine.NoteClientCapabilities(const AFrame: TBytes; ALen: Integer);
var
  Json  : TJSONValue;
  Method: string;
  On    : Boolean;
begin
  if not FOptions.MergeDiagnostics or not FrameContains(AFrame, ALen, 'workDoneProgress') or
     not FrameContains(AFrame, ALen, '"' + METHOD_INITIALIZE + '"') then Exit;
  try
    Json:= TJSONObject.ParseJSONValue(FrameBody(AFrame, ALen));
    try
      if (Json is TJSONObject) and Json.TryGetValue<string>('method', Method) and (Method = METHOD_INITIALIZE) and
         Json.TryGetValue<Boolean>('params.capabilities.window.workDoneProgress', On) then
        TInterlocked.Exchange(FClientProgress, Ord(On));
    finally
      Json.Free;
    end;
  except  // dl:ok try-except-swallowed@26a2 -- an unreadable initialize only means no progress is shown
    on E: Exception do TInterlocked.Exchange(FClientProgress, 0);
  end;
end;

procedure TProxyMergeEngine.ForgetHovers(const APath: string);
var
  Prefix: string;
  K     : string;
begin
  Prefix:= DocKey(APath) + '#';
  FPendingLock.Enter;
  try
    for K in FHoverCache.Keys.ToArray do
      if K.StartsWith(Prefix) then FHoverCache.Remove(K);
  finally
    FPendingLock.Leave;
  end;
end;

procedure TProxyMergeEngine.CacheHover(const AKey, AMarkdown: string);
begin
  FPendingLock.Enter;
  try
    if FHoverCache.Count >= HOVER_CACHE_MAX then FHoverCache.Clear;
    FHoverCache.AddOrSetValue(AKey, AMarkdown);
  finally
    FPendingLock.Leave;
  end;
end;

function TProxyMergeEngine.CachedHover(const AKey: string; out AMarkdown: string): Boolean;
begin
  FPendingLock.Enter;
  try
    Result:= FHoverCache.TryGetValue(AKey, AMarkdown);
  finally
    FPendingLock.Leave;
  end;
end;

function TProxyMergeEngine.HoverAnswer(const AServer: TLSPServer; const AJob: TAnswerJob): string;
var
  Md : string;
  Key: string;
  Res: TJSONObject;
  Con: TJSONObject;
begin
  Key:= HoverKey(AJob.Path, AJob.Line0 + 1, AJob.Col0 + 1);
  if not CachedHover(Key, Md) then
  begin
    Md:= AServer.ComputeHoverMarkdown(AJob.Path, AJob.Line0, AJob.Col0);
    CacheHover(Key, Md);
  end;
  if Md = '' then Exit('null');
  Res:= TJSONObject.Create;
  try
    Con:= TJSONObject.Create;
    Con.AddPair('kind', 'markdown');
    Con.AddPair('value', Md);
    Res.AddPair('contents', Con);
    Result:= Res.ToJSON;
  finally
    Res.Free;
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
    TrackDocument(AFrame, ALen);
    PickupContext(AFrame, ALen);
    NoteClientCapabilities(AFrame, ALen);
    if FOptions.MergeCompletion or FOptions.MergeHover or FOptions.MergeDefinition or FOptions.MergeNavigation then RecordRequest(AFrame, ALen);
    Exit(False);
  end;
  if (FOptions.MergeCompletion or FOptions.MergeHover or FOptions.MergeDefinition or FOptions.MergeNavigation) and
     MergeReply(AFrame, ALen, AReplacement) then Exit(True);
  Result:= FOptions.MergeDiagnostics and MergeDiagnostics(AFrame, ALen, AReplacement);
end;

end.
