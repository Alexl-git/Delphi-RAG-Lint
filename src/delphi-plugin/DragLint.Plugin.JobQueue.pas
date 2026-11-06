unit DragLint.Plugin.JobQueue;

{ v0.65.1 (R2): one serialized background-job queue for the heavy, DB-touching
  IDE jobs (reindex / lint-all / forms-csv) so they cannot collide on the
  project SQLite DB ("database is locked"). A single worker thread runs jobs
  FIFO; duplicate enqueues coalesce by key; per-job state is kept under a lock
  and PULLED by the dock status bar on a timer (no worker->UI closures, so no
  dangling-Self/unload-AV hazard). Each job's post-run callback is marshalled to
  the main thread by value. The engine LSP server is a separate long-running
  process and keeps serving concurrently -- the queue governs only these jobs. }

interface

uses
  System.Classes
  , System.SysUtils
  , System.SyncObjs
  , System.Generics.Collections
  ;

const
  /// <summary>How many pending job titles TQueueState.PendingTitles carries
  /// (and DragLint.Plugin.QueueText.DLQueueLines names before "+ N more waiting").</summary>
  DL_QUEUE_NAMED_PENDING = 3;

type
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DragLint.Plugin.JobQueue.pas)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TJobKind = (jkGeneric, jkReindex, jkLintAll, jkFormsCsv);

  { Snapshot of queue state for the status bar. Percent = -1 means indeterminate
    (no % yet, or a non-streaming job -> marquee). }
  /// <summary><!-- drag-lint:auto sum -->Snapshot of queue state for the status bar.
  /// Percent = -1 means indeterminate (no % yet, or a non-streaming job -&gt; marquee).</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DragLint.Plugin.JobQueue.pas), declaration (DragLint.Plugin.QueueText.pas), DragLint.Plugin.JobQueue.TDragLintJobQueue.GetState (DragLint.Plugin.JobQueue.pas), DragLint.Plugin.QueueText.DLQueueLines (DragLint.Plugin.QueueText.pas), DragLint.Plugin.QueueText.NowLine (DragLint.Plugin.QueueText.pas) (+5 more)</para>
  /// <para>Used in units: DragLint.Plugin.JobQueue, DragLint.Plugin.QueueText, DragLint.Plugin.StatusBar</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TQueueState = record
    Running     : Boolean;
    CurrentTitle: string ;
    Percent     : Integer;
    { The phase or file the percent refers to -- 'duplicate-code', 'uMain.pas'.
      Without it a stalled bar says only THAT it is working, never WHAT on,
      which is exactly the question a user has when it stops moving. }
    Phase       : string ;
    QueueDepth  : Integer; { pending jobs, NOT counting the running one }
    LastResult  : string ;
    { Titles of the first DL_QUEUE_NAMED_PENDING (3) pending jobs, in run
      order. Written together with QueueDepth, under FLock (SyncPendingLocked),
      so the status strip's "Next:/Then:" lines never disagree with "N queued". }
    PendingTitles: TArray<string>;
    { The running job takes a Cancel (its CancelGraceMs > 0) and none was sent
      yet: the status strip enables its Cancel button for it (lane X-BT). }
    CanCancelRunning: Boolean;
  end;

  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DragLint.Plugin.JobQueue.pas)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TJobPreRun = TProc;                  { UI thread, before the process starts }
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DragLint.Plugin.JobQueue.pas)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TJobLine   = TProc<string>;          { worker thread, per output line }
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DragLint.Plugin.JobQueue.pas), DragLint.Plugin.JobQueue.TDragLintJobQueue.RunOne (DragLint.Plugin.JobQueue.pas)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TJobDone   = TProc<Integer, string>; { UI thread: (exit code, full output) }

  /// <summary>One queued heavy job. Owned by the queue once enqueued.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DragLint.Plugin.Editor.DLRunMaintenanceJob (DragLint.Plugin.Editor.pas), DragLint.Plugin.Editor.EnqueueRefreshFindings (DragLint.Plugin.Editor.pas), DragLint.Plugin.Editor.InvokeAutoDocumentProject (DragLint.Plugin.Editor.pas), DragLint.Plugin.Editor.InvokeFormatProjectYadf (DragLint.Plugin.Editor.pas), DragLint.Plugin.Editor.InvokeGenerateFormsCsv (DragLint.Plugin.Editor.pas) (+22 more)</para>
  /// <para>Used in units: DragLint.Plugin.Editor, DragLint.Plugin.IndexJob, DragLint.Plugin.JobQueue, DragLint.Plugin.Reports, DragLint.Plugin.SaveNotifier, DragLint.Plugin.StructureForm, DragLint.Plugin.UsesDepsFrame</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TDragLintJob = class
  public
    Kind       : TJobKind  ;
    Title      : string    ; { shown in the status bar, e.g. 'Reindex Micronite2027' }
    CoalesceKey: string    ; { non-empty -> a pending job with the same key is superseded }
    CmdLine    : string    ;
    TimeoutMs  : Integer   ;
    Streaming  : Boolean   ; { true -> RunCaptureStreaming + % parse; false -> RunCaptureStdout }
    OnPreRun   : TJobPreRun;
    OnLine     : TJobLine  ;
    OnDone     : TJobDone  ;
    { true -> a USER-started job that edits source (Fix it / Fix all): counted
      by JobQueueBusy from Enqueue until it is superseded, cancelled, or has
      finished -- released just BEFORE its OnDone runs, so an OnDone that shows
      a dialog or queues the next step is not itself seen as busy }
    Busy       : Boolean   ;  // dl:ok public-field@3419
    { > 0 -> the user may CANCEL this job while it runs (lane X-BT, a cycle-fix
      run): Cancel asks the engine to stand down (ProcRun's AStandDownGraceMs --
      it rolls back and exits) and kills the tree only after this many ms.
      0 (the default) -> a running job is not cancellable, as before.
      Non-streaming jobs only: a Streaming job ignores it. }
    CancelGraceMs: Integer ;  // dl:ok public-field@60f2 -- the job record's fields are its public contract, set by the enqueuer like every field above
    /// <summary><!-- drag-lint:auto sum -->---- TDragLintJob ----</summary>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DragLint.Plugin.Editor.DLRunMaintenanceJob (DragLint.Plugin.Editor.pas), DragLint.Plugin.Editor.EnqueueRefreshFindings (DragLint.Plugin.Editor.pas), DragLint.Plugin.Editor.InvokeAutoDocumentProject (DragLint.Plugin.Editor.pas), DragLint.Plugin.Editor.InvokeFormatProjectYadf (DragLint.Plugin.Editor.pas), DragLint.Plugin.Editor.InvokeGenerateFormsCsv (DragLint.Plugin.Editor.pas) (+11 more)</para>
    /// <para>constructor</para>
    /// <para>Writes: Kind, TimeoutMs, Streaming</para>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    constructor Create;
  end;

  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DragLint.Plugin.JobQueue.pas) ?, DragLint.Plugin.JobQueue.JobQueue (DragLint.Plugin.JobQueue.pas), DragLint.Plugin.JobQueue.TQueueWorker.Create (DragLint.Plugin.JobQueue.pas) ?</para>
  /// <para>Used in units: DragLint.Plugin.JobQueue</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TDragLintJobQueue = class
  private
    FLock    : TCriticalSection;
    FPending : TObjectList<TDragLintJob>;
    FWake    : TEvent;
    FWorker  : TThread;
    FShutdown: Boolean;
    { Manual-reset; set by Destroy. The running job's child polls it, so a
      shutdown kills that child's tree instead of waiting it out (1.31.6). }
    FCancel  : TEvent;
    { Manual-reset; the cancel of a CANCELLABLE running job (CancelGraceMs > 0):
      set by CancelRunning and by Destroy, reset before each job. }
    FRunCancel: TEvent;
    FState   : TQueueState;
    { Worker thread only: whether THIS deferral episode has been logged.
      Cleared when the hold lifts, so a later hold is reported again. }
    FDeferredLogged: Boolean;
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DragLint.Plugin.JobQueue.TQueueWorker.Execute (DragLint.Plugin.JobQueue.pas)</para>
    /// <para>Calls: DragLint.Plugin.JobQueue.AdjustBusy, DragLint.Plugin.JobQueue.TDragLintJobQueue.RunOne, DragLint.Plugin.JobQueue.TDragLintJobQueue.SyncPendingLocked, DragLint.Plugin.JobQueue.TDragLintJobQueue.WaitWhileEngineHeld</para>
    /// <para>Complexity: 10 (cyclomatic, outer body), 74 lines (full implementation)</para>
    /// <para>Reads: FShutdown, FWake, FLock, FPending, FState</para>
    /// <para>Catches: Exception (empty)</para>
    /// <seealso cref="DragLint.Plugin.JobQueue.AdjustBusy"/>
    /// <seealso cref="DragLint.Plugin.JobQueue.TDragLintJobQueue.RunOne"/>
    /// <seealso cref="DragLint.Plugin.JobQueue.TDragLintJobQueue.SyncPendingLocked"/>
    /// <seealso cref="DragLint.Plugin.JobQueue.TDragLintJobQueue.WaitWhileEngineHeld"/>
    /// <seealso cref="DragLint.Plugin.JobQueue.TDragLintJobQueue.CancelRunning"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure WorkerLoop;
    /// <summary><!-- drag-lint:auto sum -->NOT GATED, deliberately: a job ALREADY RUNNING
    /// when the hold appears keeps running. The hold's contract is "will not START
    /// anything" -- the same shape as EnsureLspClient's "will not RESPAWN" -- and the
    /// build kills a running holder exactly as it does today.</summary>
    /// <param name="ATitle"><!-- drag-lint:auto type -->const string</param>
    /// <param name="AKey"><!-- drag-lint:auto type -->const string</param>
    /// <returns><!-- drag-lint:auto -->Boolean -- Observed: True.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DragLint.Plugin.JobQueue.TDragLintJobQueue.WorkerLoop (DragLint.Plugin.JobQueue.pas)</para>
    /// <para>Calls: DRagLint.Core.EngineHold.EngineIsHeld, Format, GJobQueueDeferredHook</para>
    /// <para>Reads: FShutdown, FDeferredLogged, FWake   Writes: FDeferredLogged</para>
    /// <para>Catches: Exception (swallowed)</para>
    /// <seealso cref="DRagLint.Core.EngineHold.EngineIsHeld"/>
    /// <seealso cref="DragLint.Plugin.JobQueue.TDragLintJobQueue.CancelRunning"/>
    /// <seealso cref="DragLint.Plugin.JobQueue.TDragLintJobQueue.ClearPending"/>
    /// <seealso cref="DragLint.Plugin.JobQueue.TDragLintJobQueue.Create"/>
    /// <seealso cref="DragLint.Plugin.JobQueue.TDragLintJobQueue.Destroy"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function  WaitWhileEngineHeld(const ATitle, AKey: string): Boolean;
    /// <param name="AJob"><!-- drag-lint:auto type -->TDragLintJob</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DragLint.Plugin.JobQueue.TDragLintJobQueue.WorkerLoop (DragLint.Plugin.JobQueue.pas)</para>
    /// <para>Calls: CharInSet, Copy, DoneCb, DragLint.Plugin.JobQueue.AdjustBusy, DragLint.Plugin.JobQueue.LogJobLine, DragLint.Plugin.JobQueue.ReindexResultText, DragLint.Plugin.JobQueue.TDragLintJobQueue.SetLastResult, DragLint.Plugin.JobQueue.TDragLintJobQueue.SetPercent/1, DragLint.Plugin.JobQueue.TDragLintJobQueue.SetPercent/2, DragLint.Plugin.ProcRun.RunCaptureStdout (+8 more)</para>
    /// <para>Complexity: 31 (cyclomatic, outer body), 160 lines (full implementation)</para>
    /// <para>Reads: FCancel, FLock, FRunCancel, FShutdown, FState</para>
    /// <para>Catches: Exception (empty); Exception (swallowed)</para>
    /// <seealso cref="DragLint.Plugin.JobQueue.AdjustBusy"/>
    /// <seealso cref="DragLint.Plugin.JobQueue.LogJobLine"/>
    /// <seealso cref="DragLint.Plugin.JobQueue.ReindexResultText"/>
    /// <seealso cref="DragLint.Plugin.JobQueue.TDragLintJobQueue.SetLastResult"/>
    /// <seealso cref="DragLint.Plugin.JobQueue.TDragLintJobQueue.SetPercent"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure RunOne(AJob: TDragLintJob);
    /// <param name="APct"><!-- drag-lint:auto type -->Integer</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DragLint.Plugin.JobQueue.TDragLintJobQueue.RunOne (DragLint.Plugin.JobQueue.pas)</para>
    /// <para>Calls: DragLint.Plugin.JobQueue.TDragLintJobQueue.SetPercent/2</para>
    /// <para>Overload 1 of 2</para>
    /// <para>Directives: overload</para>
    /// <seealso cref="DragLint.Plugin.JobQueue.TDragLintJobQueue.SetPercent"/>
    /// <seealso cref="DragLint.Plugin.JobQueue.TDragLintJobQueue.CancelRunning"/>
    /// <seealso cref="DragLint.Plugin.JobQueue.TDragLintJobQueue.ClearPending"/>
    /// <seealso cref="DragLint.Plugin.JobQueue.TDragLintJobQueue.Create"/>
    /// <seealso cref="DragLint.Plugin.JobQueue.TDragLintJobQueue.Destroy"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure SetPercent(APct: Integer); overload;
    /// <param name="APct"><!-- drag-lint:auto type -->Integer</param>
    /// <param name="APhase"><!-- drag-lint:auto type -->const string</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DragLint.Plugin.JobQueue.TDragLintJobQueue.RunOne (DragLint.Plugin.JobQueue.pas), DragLint.Plugin.JobQueue.TDragLintJobQueue.SetPercent/1 (DragLint.Plugin.JobQueue.pas)</para>
    /// <para>Overload 2 of 2</para>
    /// <para>Reads: FLock, FState</para>
    /// <para>Directives: overload</para>
    /// <seealso cref="DragLint.Plugin.JobQueue.TDragLintJobQueue.CancelRunning"/>
    /// <seealso cref="DragLint.Plugin.JobQueue.TDragLintJobQueue.ClearPending"/>
    /// <seealso cref="DragLint.Plugin.JobQueue.TDragLintJobQueue.Create"/>
    /// <seealso cref="DragLint.Plugin.JobQueue.TDragLintJobQueue.Destroy"/>
    /// <seealso cref="DragLint.Plugin.JobQueue.TDragLintJobQueue.Enqueue"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure SetPercent(APct: Integer; const APhase: string); overload;
    /// <param name="AText"><!-- drag-lint:auto type -->const string</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DragLint.Plugin.JobQueue.TDragLintJobQueue.RunOne (DragLint.Plugin.JobQueue.pas)</para>
    /// <para>Reads: FLock, FState</para>
    /// <seealso cref="DragLint.Plugin.JobQueue.TDragLintJobQueue.CancelRunning"/>
    /// <seealso cref="DragLint.Plugin.JobQueue.TDragLintJobQueue.ClearPending"/>
    /// <seealso cref="DragLint.Plugin.JobQueue.TDragLintJobQueue.Create"/>
    /// <seealso cref="DragLint.Plugin.JobQueue.TDragLintJobQueue.Destroy"/>
    /// <seealso cref="DragLint.Plugin.JobQueue.TDragLintJobQueue.Enqueue"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure SetLastResult(const AText: string);
    { Caller holds FLock. The ONE place QueueDepth and PendingTitles are set. }
    /// <summary><!-- drag-lint:auto sum -->Caller holds FLock. The ONE place QueueDepth
    /// and PendingTitles are set.</summary>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DragLint.Plugin.JobQueue.TDragLintJobQueue.ClearPending (DragLint.Plugin.JobQueue.pas), DragLint.Plugin.JobQueue.TDragLintJobQueue.Create (DragLint.Plugin.JobQueue.pas), DragLint.Plugin.JobQueue.TDragLintJobQueue.Enqueue (DragLint.Plugin.JobQueue.pas), DragLint.Plugin.JobQueue.TDragLintJobQueue.WorkerLoop (DragLint.Plugin.JobQueue.pas)</para>
    /// <para>Calls: Min</para>
    /// <para>Reads: FState, FPending</para>
    /// <seealso cref="DragLint.Plugin.JobQueue.TDragLintJobQueue.CancelRunning"/>
    /// <seealso cref="DragLint.Plugin.JobQueue.TDragLintJobQueue.ClearPending"/>
    /// <seealso cref="DragLint.Plugin.JobQueue.TDragLintJobQueue.Create"/>
    /// <seealso cref="DragLint.Plugin.JobQueue.TDragLintJobQueue.Destroy"/>
    /// <seealso cref="DragLint.Plugin.JobQueue.TDragLintJobQueue.Enqueue"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure SyncPendingLocked;
  public
    /// <summary><!-- drag-lint:auto sum -->---- TDragLintJobQueue ----</summary>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DragLint.Plugin.JobQueue.JobQueue (DragLint.Plugin.JobQueue.pas)</para>
    /// <para>Calls: DragLint.Plugin.JobQueue.TDragLintJobQueue.SyncPendingLocked, DragLint.Plugin.JobQueue.TQueueWorker.Create</para>
    /// <para>constructor</para>
    /// <para>Reads: FState   Writes: FLock, FPending, FWake, FCancel, FRunCancel, FShutdown, FDeferredLogged, FWorker</para>
    /// <seealso cref="DragLint.Plugin.JobQueue.TDragLintJobQueue.SyncPendingLocked"/>
    /// <seealso cref="DragLint.Plugin.JobQueue.TQueueWorker.Create"/>
    /// <seealso cref="DragLint.Plugin.JobQueue.TDragLintJobQueue.CancelRunning"/>
    /// <seealso cref="DragLint.Plugin.JobQueue.TDragLintJobQueue.ClearPending"/>
    /// <seealso cref="DragLint.Plugin.JobQueue.TDragLintJobQueue.Destroy"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    constructor Create;
    /// <summary>Stops the worker: signals the cancel event, so a running job's
    /// child process tree is killed rather than waited out, then joins the
    /// worker. Pending jobs are dropped without their OnDone.</summary>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Calls: Format, OutputDebugString, PChar, WaitForSingleObject</para>
    /// <para>Reads: FCancel, FRunCancel, FWake, FWorker, FPending, FLock   Writes: FShutdown</para>
    /// <para>Directives: override</para>
    /// <seealso cref="DragLint.Plugin.JobQueue.TDragLintJobQueue.CancelRunning"/>
    /// <seealso cref="DragLint.Plugin.JobQueue.TDragLintJobQueue.ClearPending"/>
    /// <seealso cref="DragLint.Plugin.JobQueue.TDragLintJobQueue.Create"/>
    /// <seealso cref="DragLint.Plugin.JobQueue.TDragLintJobQueue.Enqueue"/>
    /// <seealso cref="DragLint.Plugin.JobQueue.TDragLintJobQueue.GetState"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    destructor Destroy; override;
    /// <summary>Enqueue AJob (queue takes ownership). A pending job with the
    /// same non-empty CoalesceKey is dropped first. Call from the main thread.</summary>
    /// <param name="AJob"><!-- drag-lint:auto type -->TDragLintJob</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DragLint.Plugin.Editor.DLRunMaintenanceJob (DragLint.Plugin.Editor.pas), DragLint.Plugin.Editor.EnqueueRefreshFindings (DragLint.Plugin.Editor.pas), DragLint.Plugin.Editor.InvokeAutoDocumentProject (DragLint.Plugin.Editor.pas), DragLint.Plugin.Editor.InvokeFormatProjectYadf (DragLint.Plugin.Editor.pas), DragLint.Plugin.Editor.InvokeGenerateFormsCsv (DragLint.Plugin.Editor.pas) (+12 more)</para>
    /// <para>Calls: DragLint.Plugin.JobQueue.AdjustBusy, DragLint.Plugin.JobQueue.TDragLintJobQueue.SyncPendingLocked, SameText</para>
    /// <para>Reads: FLock, FPending, FWake</para>
    /// <seealso cref="DragLint.Plugin.JobQueue.AdjustBusy"/>
    /// <seealso cref="DragLint.Plugin.JobQueue.TDragLintJobQueue.SyncPendingLocked"/>
    /// <seealso cref="DragLint.Plugin.JobQueue.TDragLintJobQueue.CancelRunning"/>
    /// <seealso cref="DragLint.Plugin.JobQueue.TDragLintJobQueue.ClearPending"/>
    /// <seealso cref="DragLint.Plugin.JobQueue.TDragLintJobQueue.Create"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure Enqueue(AJob: TDragLintJob);
    /// <summary>Cancel all pending (not-yet-running) jobs; the running one finishes.</summary>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DragLint.Plugin.StatusBar.TDragLintStatusBar.HandleCancel (DragLint.Plugin.StatusBar.pas)</para>
    /// <para>Calls: DragLint.Plugin.JobQueue.AdjustBusy, DragLint.Plugin.JobQueue.TDragLintJobQueue.SyncPendingLocked</para>
    /// <para>Reads: FLock, FPending</para>
    /// <seealso cref="DragLint.Plugin.JobQueue.AdjustBusy"/>
    /// <seealso cref="DragLint.Plugin.JobQueue.TDragLintJobQueue.SyncPendingLocked"/>
    /// <seealso cref="DragLint.Plugin.JobQueue.TDragLintJobQueue.CancelRunning"/>
    /// <seealso cref="DragLint.Plugin.JobQueue.TDragLintJobQueue.Create"/>
    /// <seealso cref="DragLint.Plugin.JobQueue.TDragLintJobQueue.Destroy"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure ClearPending;
    /// <summary>Cancels the RUNNING job when it takes a cancel (its CancelGraceMs
    /// &gt; 0): its engine is asked to stand down -- roll back and exit -- and its
    /// process tree is killed only if it has not exited after CancelGraceMs.</summary>
    /// <returns>True when a cancel was sent; False when nothing runs, the running
    /// job takes no cancel, or one was already sent.</returns>
    /// <remarks>
    /// Any thread. The job's OnDone still runs, with the engine's own exit
    /// code and output (or PROCRUN_CANCELLED_EXIT_CODE after the kill).
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DragLint.Plugin.StatusBar.TDragLintStatusBar.HandleCancel (DragLint.Plugin.StatusBar.pas)</para>
    /// <para>Calls: DragLint.Plugin.JobQueue.LogJobLine</para>
    /// <para>Returns: FState.Running and FState.CanCancelRunning</para>
    /// <para>Reads: FLock, FState, FRunCancel</para>
    /// <seealso cref="DragLint.Plugin.JobQueue.LogJobLine"/>
    /// <seealso cref="DragLint.Plugin.JobQueue.TDragLintJobQueue.ClearPending"/>
    /// <seealso cref="DragLint.Plugin.JobQueue.TDragLintJobQueue.Create"/>
    /// <seealso cref="DragLint.Plugin.JobQueue.TDragLintJobQueue.Destroy"/>
    /// <seealso cref="DragLint.Plugin.JobQueue.TDragLintJobQueue.Enqueue"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function CancelRunning: Boolean;
    /// <summary>Thread-safe snapshot of the current state.</summary>
    /// <returns><!-- drag-lint:auto -->TQueueState -- Observed: FState.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DragLint.Plugin.StatusBar.SetDragLintNote (DragLint.Plugin.StatusBar.pas), DragLint.Plugin.StatusBar.TDragLintStatusBar.HandleTimer (DragLint.Plugin.StatusBar.pas)</para>
    /// <para>Reads: FLock, FState</para>
    /// <seealso cref="DragLint.Plugin.JobQueue.TDragLintJobQueue.CancelRunning"/>
    /// <seealso cref="DragLint.Plugin.JobQueue.TDragLintJobQueue.ClearPending"/>
    /// <seealso cref="DragLint.Plugin.JobQueue.TDragLintJobQueue.Create"/>
    /// <seealso cref="DragLint.Plugin.JobQueue.TDragLintJobQueue.Destroy"/>
    /// <seealso cref="DragLint.Plugin.JobQueue.TDragLintJobQueue.Enqueue"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function GetState: TQueueState;
  end;

{ Called ONCE per deferral episode, with a line like
    JobQueue: deferred "Refresh Findings" (key refresh-findings:c:\x.sqlite)
    -- engine held for 118s
  A HOOK, not a direct call to the plugin's DebugLog, for the same reason
  this unit's implementation uses only ProcRun: it has to compile into a
  console test program with no ToolsAPI. Editor.pas assigns it beside the
  other hooks during wizard init.

  ONCE PER EPISODE, not once per wait. The wait is 5 s and a default hold is
  120 s, so a per-wait log would write 24 identical lines for one deferral.
  The flag clears when the hold lifts, so a second hold logs again.

  ALSO the queue's run log (2026-10-16): RunOne reports every job's title and
  command line when it starts and its exit code when it ends, from the WORKER
  thread, through this same hook. }
var
  GJobQueueDeferredHook: TProc<string> = nil;

{ Called on the MAIN thread after EVERY jkReindex job has finished (and after
  its own OnDone), whoever queued it -- the save path, 'Rescan this unit', or a
  project rebuild from the menu. The live runner assigns RequestRelint here:
  project rules such as unused-unit-in-uses read the index, so findings
  computed while a reindex was writing stay stale until the next lint, and
  only some reindex paths used to ask for one (owner report 2026-10-13). A
  HOOK, so this unit keeps compiling into console tests with no ToolsAPI. }
var
  GReindexDoneHook: TProc = nil;

{ Called on the MAIN thread when the count of live Busy jobs goes 0 -> 1 (True)
  and 1 -> 0 (False). The plugin sets the IDE's wait cursor here, so a user does
  not start a second edit while a fix is rewriting files (owner 2026-10-16). A
  HOOK, so this unit stays free of the VCL for its console tests. }
var
  GJobQueueBusyHook: TProc<Boolean> = nil;

/// <summary>Is a Busy job (a user-started fix) queued or running?</summary>
/// <returns>True from the Enqueue of a Busy job until the last one is
/// superseded, cancelled by ClearPending, or released before its OnDone.</returns>
/// <remarks>
/// Main thread only.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DragLint.Plugin.StructureForm.RefusedWhileFixRuns (DragLint.Plugin.StructureForm.pas), DragLint.Plugin.UsesDepsFrame.TCircularUsesSection.RunFix (DragLint.Plugin.UsesDepsFrame.pas), DragLint.Plugin.UsesDepsFrame.TCircularUsesSection.StartRefresh (DragLint.Plugin.UsesDepsFrame.pas), initialization/finalization (DragLint.Plugin.StructureForm.pas)</para>
/// <para>Returns: GBusyJobs &gt; 0</para>
/// <para>Effect-free (proven)</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function JobQueueBusy: Boolean;

/// <summary>The bar text a finished reindex job leaves behind.</summary>
/// <param name="AExitCode">The engine's exit code.</param>
/// <param name="AOutput">Its captured stdout+stderr; scanned only for the index-lock refusal.</param>
/// <returns>'reindex: done' for 0; 'reindex: index busy, will retry' for exit 2 whose
/// output is the index-lock refusal (another run owns the database -- not an error; the
/// next save or reindex retries); 'reindex: failed' for any other exit 2; otherwise
/// 'reindex: failed (exit N)'.</returns>
/// <remarks>
/// Pure. The lock refusal is recognised by the phrase 'another index run',
/// which both AcquireIndexLock refusals (sharing violation, delete pending) carry.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DragLint.Plugin.JobQueue.TDragLintJobQueue.RunOne (DragLint.Plugin.JobQueue.pas)</para>
/// <para>Calls: ContainsText, Format</para>
/// <para>Returns: 'reindex: index busy, will retry'; Format('reindex: failed (exit %d)', [AExitCode])</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ReindexResultText(AExitCode: Integer; const AOutput: string): string;  // dl:ok unused-public-symbol@a063 -- public on purpose: tests\IndexJobTests.dpr (outside the plugin project) pins its wording

{ Lazy singleton (create/access on the main thread) + finalization teardown. }
/// <summary><!-- drag-lint:auto sum -->Lazy singleton (create/access on the main thread)
/// + finalization teardown.</summary>
/// <returns><!-- drag-lint:auto -->TDragLintJobQueue -- Observed: GQueue.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DragLint.Plugin.Editor.DLRunMaintenanceJob (DragLint.Plugin.Editor.pas), DragLint.Plugin.Editor.EnqueueRefreshFindings (DragLint.Plugin.Editor.pas), DragLint.Plugin.Editor.InvokeAutoDocumentProject (DragLint.Plugin.Editor.pas), DragLint.Plugin.Editor.InvokeFormatProjectYadf (DragLint.Plugin.Editor.pas), DragLint.Plugin.Editor.InvokeGenerateFormsCsv (DragLint.Plugin.Editor.pas) (+15 more)</para>
/// <para>Calls: DragLint.Plugin.JobQueue.TDragLintJobQueue.Create</para>
/// <seealso cref="DragLint.Plugin.JobQueue.TDragLintJobQueue.Create"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function JobQueue: TDragLintJobQueue;
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: initialization/finalization (DragLint.Plugin.JobQueue.pas)</para>
/// <para>Calls: FreeAndNil</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure ShutdownJobQueue;

implementation

uses
  System.Math
  , System.StrUtils
  , Winapi.Windows
  , DragLint.Plugin.ProcRun  // dl:unit DragLint.Plugin.ProcRun accepted -- PROCRUN_TIMED_OUT_EXIT_CODE is the runner's own result code; the job reads it to report a timeout
  { The gate's only new dependency. Core.EngineHold reads a sentinel file
    and touches no process and no ToolsAPI, so the unit still compiles
    headless -- which the harness for this gate depends on. }
  , DRagLint.Core.EngineHold
  ;

const
  { Upper bound on the worker join at destruction (IDE exit). The running job's
    child is killed within one poll slice, so a healthy worker is back in well
    under this; anything slower is abandoned rather than holding bds.exe open. }
  JOB_QUEUE_JOIN_MS = 2000;

const
  { How long the worker sleeps between re-checks while the engine is held.
    Short enough that a released hold is picked up promptly, long enough
    that a 120 s hold costs 24 cheap file stats rather than thousands.
    FWake is auto-reset, so an Enqueue during the wait wakes the loop early;
    it simply re-peeks, finds the hold, and waits again. }
  HOLD_RECHECK_MS = 5000;

  { PLUG-INFWAIT (2026-11-01): the idle worker's wait slice. It used to wait
    INFINITE on FWake; now it wakes at least this often, re-peeks the queue and
    re-checks FShutdown, so a lost wake or a shutdown flag set without a
    SetEvent can never strand a job or pin the thread. An idle pass is one
    lock and a Count test. }
  WORKER_IDLE_RECHECK_MS = 1000;

type
  TQueueWorker = class(TThread)
  private
    FOwner: TDragLintJobQueue;
  protected
    procedure Execute; override;
  public
    constructor Create(AOwner: TDragLintJobQueue);
  end;

constructor TQueueWorker.Create(AOwner: TDragLintJobQueue);
begin
  FOwner:= AOwner;
  inherited Create(False { start now });
end;

function ReindexResultText(AExitCode: Integer; const AOutput: string): string;
const
  EXIT_USAGE_OR_LOCK = 2;
  LOCK_REFUSAL_PHRASE = 'another index run';
begin
  if AExitCode = 0 then Exit('reindex: done');
  if (AExitCode = EXIT_USAGE_OR_LOCK) and ContainsText(AOutput, LOCK_REFUSAL_PHRASE) then
    Exit('reindex: index busy, will retry');
  if AExitCode = EXIT_USAGE_OR_LOCK then Exit('reindex: failed');
  Result:= Format('reindex: failed (exit %d)', [AExitCode]);
end;

procedure TQueueWorker.Execute;
begin
  FOwner.WorkerLoop;
end;

{ ---- busy count (main thread only) ---- }

var
  GBusyJobs: Integer = 0;

{ Moves the live Busy-job count by ADelta, never below 0 (a release queued by
  the worker's exception path may follow the normal one), and tells
  GJobQueueBusyHook when the count crosses zero. }
procedure AdjustBusy(ADelta: Integer);
var
  Was: Boolean;
begin
  Was      := GBusyJobs > 0;
  GBusyJobs:= Max(0, GBusyJobs + ADelta);
  if (Was <> (GBusyJobs > 0)) and Assigned(GJobQueueBusyHook) then
    try
      GJobQueueBusyHook(GBusyJobs > 0);
    except
      on E: Exception do
        if Assigned(GJobQueueDeferredHook) then GJobQueueDeferredHook('JobQueue: busy hook failed: ' + E.Message);
    end;
end;

function JobQueueBusy: Boolean;
begin
  Result:= GBusyJobs > 0;
end;

{ ---- TDragLintJob ---- }

constructor TDragLintJob.Create;
begin
  inherited Create;
  Kind     := jkGeneric;
  TimeoutMs:= 180000;
  Streaming:= False;
end;

{ ---- TDragLintJobQueue ---- }

constructor TDragLintJobQueue.Create;
begin
  inherited Create;
  FLock    := TCriticalSection.Create;
  FPending := TObjectList<TDragLintJob>.Create(True { owns });
  FWake    := TEvent.Create(nil, False { auto-reset }, False, '');
  FCancel  := TEvent.Create(nil, True { manual-reset }, False, '');
  FRunCancel:= TEvent.Create(nil, True { manual-reset }, False, '');
  FShutdown:= False;
  FDeferredLogged:= False;
  FState.Running   := False;
  FState.Percent   := -1;
  SyncPendingLocked; { QueueDepth 0, no titles; no other thread exists yet }
  FWorker  := TQueueWorker.Create(Self);
end;

destructor TDragLintJobQueue.Destroy;
begin
  { Stop the worker cleanly BEFORE freeing anything it touches (avoids unload AV).
    CANCEL, THEN WAIT: the running job's child -- and its whole tree -- is
    killed within one poll slice, so closing the IDE no longer waits out a
    reindex. A job dequeued but not yet spawned sees the event and spawns
    nothing. }
  FShutdown:= True;
  if FCancel <> nil then FCancel.SetEvent;
  { a cancellable job (a cycle-fix --apply) stands down and rolls back rather
    than being killed mid-write; the join below waits out its grace at most }
  if FRunCancel <> nil then FRunCancel.SetEvent;
  if FWake <> nil then FWake.SetEvent;
  if FWorker <> nil then
  begin
    { 2026-10-29: BOUNDED. An unbounded WaitFor here is one of the waits that
      can keep bds.exe alive for minutes after its window closed. A worker that
      has not stood down inside the budget is abandoned together with what it
      touches (deliberate leak) -- a leak at exit, not a hung IDE. }
    if WaitForSingleObject(FWorker.Handle, JOB_QUEUE_JOIN_MS) <> WAIT_OBJECT_0 then
    begin
      OutputDebugString(PChar(Format('drag-lint job queue: worker did not stop within %d ms -- abandoned', [JOB_QUEUE_JOIN_MS]))); // dl:ok outputdebugstring@8872 -- runs during unit finalization at IDE exit, when the plugin log may already be torn down
      Exit;
    end;
    FWorker.Free;
  end;
  FPending.Free;
  FWake.Free;
  FCancel.Free;
  FRunCancel.Free;
  FLock.Free;
  inherited;
end;

procedure TDragLintJobQueue.Enqueue(AJob: TDragLintJob);
var
  I    : Integer;
  Delta: Integer; { Busy jobs added minus Busy jobs superseded }
begin
  if AJob = nil then Exit;
  Delta:= if AJob.Busy then 1 else 0;
  FLock.Enter;
  try
    if AJob.CoalesceKey <> '' then
      for I:= FPending.Count - 1 downto 0 do
        if SameText(FPending[I].CoalesceKey, AJob.CoalesceKey) then
        begin
          if FPending[I].Busy then Dec(Delta); { its OnDone will never run }
          FPending.Delete(I); { OwnsObjects -> frees the superseded job }
        end;
    FPending.Add(AJob);
    SyncPendingLocked;
  finally
    FLock.Leave;
  end;
  if Delta <> 0 then AdjustBusy(Delta);
  FWake.SetEvent;
end;

procedure TDragLintJobQueue.ClearPending;
var
  Dropped: Integer; { Busy jobs cancelled: their OnDone will never run }
begin
  Dropped:= 0;
  FLock.Enter;
  try
    for var J: TDragLintJob in FPending do
      if J.Busy then Inc(Dropped);
    FPending.Clear; { frees pending jobs; the running one is owned by the worker frame }
    SyncPendingLocked;
  finally
    FLock.Leave;
  end;
  if Dropped > 0 then AdjustBusy(-Dropped);
end;

procedure TDragLintJobQueue.SyncPendingLocked;
var
  Named: Integer;
begin
  FState.QueueDepth:= FPending.Count;
  Named:= Min(FPending.Count, DL_QUEUE_NAMED_PENDING);
  SetLength(FState.PendingTitles, Named);
  for var I:= 0 to Named - 1 do FState.PendingTitles[I]:= FPending[I].Title;
end;

function TDragLintJobQueue.GetState: TQueueState;
begin
  FLock.Enter;
  try
    Result:= FState;
  finally
    FLock.Leave;
  end;
end;

procedure TDragLintJobQueue.SetPercent(APct: Integer);
begin
  SetPercent(APct, '');
end;

procedure TDragLintJobQueue.SetPercent(APct: Integer; const APhase: string);
begin
  FLock.Enter;
  try
    FState.Percent:= APct;
    FState.Phase  := APhase;
  finally
    FLock.Leave;
  end;
end;

procedure TDragLintJobQueue.SetLastResult(const AText: string);
begin
  FLock.Enter;
  try
    FState.LastResult:= AText;
  finally
    FLock.Leave;
  end;
end;

{ One line through the queue's log hook, from the WORKER thread. Same contract
  as the deferral log in WaitWhileEngineHeld: a hook that raises is disabled
  rather than retried, because this IS the reporting channel. }
procedure LogJobLine(const AText: string);
begin
  if not Assigned(GJobQueueDeferredHook) then Exit;
  try
    GJobQueueDeferredHook(AText);
  except  // dl:ok try-except-swallowed@84ab -- this IS the log channel; a hook that raises is disabled, not retried
    on E: Exception do GJobQueueDeferredHook:= nil;
  end;
end;

function TDragLintJobQueue.CancelRunning: Boolean;
var
  Title: string;
begin
  FLock.Enter;
  try
    Result:= FState.Running and FState.CanCancelRunning;
    if not Result then Exit;
    Title:= FState.CurrentTitle;
    FState.CanCancelRunning:= False; { one cancel per run: the strip disables its button }
    FRunCancel.SetEvent;
  finally
    FLock.Leave;
  end;
  LogJobLine('JobQueue: cancel sent to "' + Title + '" (stand down, then kill after the grace)');
end;

procedure TDragLintJobQueue.RunOne(AJob: TDragLintJob);var
  ExitCode: Integer;
  Output  : string ;
  SB      : TStringBuilder;
  Res     : string ;
  Cancelled: Boolean; { a cancellable job's Cancel was sent during its run }
begin
  ExitCode:= 2;
  Output  := '';
  Cancelled:= False;
  { 2026-10-16: a reindex ran for hours against the WRONG project's DB and
    nothing recorded what was run or how it ended. One line each way. }
  LogJobLine(Format('JobQueue: start "%s": %s', [AJob.Title, AJob.CmdLine]));

  if Assigned(AJob.OnPreRun) then
    TThread.Synchronize(nil,
      procedure
      begin
        try AJob.OnPreRun() except end;
      end);

  if AJob.Streaming then
  begin
    SB:= TStringBuilder.Create;
    try
      RunCaptureStreaming(AJob.CmdLine,
        procedure(ALine: string)
        var
          Pct, P, B, E: Integer;
          Phase       : string ;
        begin
          SB.AppendLine(ALine);
          { parse 'lint-all: ... NN% <what>' -> the digit run just before '%',
            and the text AFTER it: the phase name on a tail line
            ('94% duplicate-code') or the file name during the scan
            ('67% uMain.pas'). Both answer "what is it doing" -- which a bare
            percentage never did, and the tail is exactly where the run used to
            look stuck. }
          Pct:= -1;
          Phase:= '';
          if (Length(ALine) > 9) and (Copy(ALine, 1, 9) = 'lint-all:') then
          begin
            P:= Pos('%', ALine);
            if P > 1 then
            begin
              E:= P - 1; B:= E;
              while (B >= 1) and CharInSet(ALine[B], ['0'..'9']) do Dec(B);
              Pct:= StrToIntDef(Copy(ALine, B + 1, E - B), -1);
              Phase:= Trim(Copy(ALine, P + 1, MaxInt));
            end;
          end;
          if Pct >= 0 then SetPercent(Pct, Phase);
          if Assigned(AJob.OnLine) then
            try AJob.OnLine(ALine) except end;
        end,
        ExitCode, AJob.TimeoutMs, FCancel.Handle);
      Output:= SB.ToString;
    finally
      SB.Free;
    end;
  end
  else
  begin
    SetPercent(-1); { indeterminate -> marquee }
    if AJob.CancelGraceMs > 0 then
    begin
      { a cancellable job: its own cancel event, armed for this run only }
      FLock.Enter;
      try
        FRunCancel.ResetEvent;
        if FShutdown then FRunCancel.SetEvent; { Destroy already ran past its SetEvent }
        FState.CanCancelRunning:= True;
      finally
        FLock.Leave;
      end;
      try
        ExitCode:= RunCaptureStdout(AJob.CmdLine, Output, AJob.TimeoutMs, FRunCancel.Handle, AJob.CancelGraceMs);
      finally
        FLock.Enter;
        try
          FState.CanCancelRunning:= False;
        finally
          FLock.Leave;
        end;
      end;
      Cancelled:= FRunCancel.WaitFor(0) = wrSignaled;
    end
    else ExitCode:= RunCaptureStdout(AJob.CmdLine, Output, AJob.TimeoutMs, FCancel.Handle);
  end;

  SetPercent(100);
  LogJobLine(Format('JobQueue: end "%s": exit %d', [AJob.Title, ExitCode]));

  { Derive a short last-result string for the bar. For lint-all the last output
    line is the meaningful summary; otherwise a kind label. }
  case AJob.Kind of
    jkReindex : Res:= 'reindex';
    jkLintAll : Res:= 'lint-all';
    jkFormsCsv: Res:= 'forms-csv';
  else
    Res:= AJob.Title;
  end;
  if (AJob.Kind = jkLintAll) and (Trim(Output) <> '') then
  begin
    Res:= Trim(Output);
    Res:= Trim(Copy(Res, LastDelimiter(#10, Res) + 1, MaxInt));
  end
  else if ExitCode = PROCRUN_TIMED_OUT_EXIT_CODE then
    Res:= Res + Format(': hung -- no progress for %d s, killed', [AJob.TimeoutMs div MSecsPerSec])
  else if (ExitCode = PROCRUN_CANCELLED_EXIT_CODE) or Cancelled then
    Res:= Res + ': cancelled' { Cancelled: the engine stood down by itself and exited with its own code }
  { F1 (2026-10-25): `index` exits 1 when a file failed to index (the run carried
    on; that file keeps its old rows) and 3 on a fatal -- neither is "done".
    Exit 2 with the lock refusal is not a failure: another run owns the database. }
  else if (AJob.Kind = jkReindex) and (ExitCode <> 0) then
    Res:= ReindexResultText(ExitCode, Output)
  else if ExitCode = 2 then  // dl:ok ifthen-to-if-expression@7e59 -- the other branches of this chain call different routines; one expression would hide the chain
    Res:= Res + ': failed'
  else
    Res:= Res + ': done';
  SetLastResult(Res);

  if Assigned(AJob.OnDone) or AJob.Busy then
  begin
    { value-capture so the closure is independent of AJob (freed next) and of
      the queue: holds the (ref-counted) callback + exit code + output only. }
    var DoneCb  : TJobDone:= AJob.OnDone;
    var DoneExit: Integer := ExitCode;
    var DoneOut : string  := Output;
    var DoneBusy: Boolean := AJob.Busy;
    AJob.Busy:= False; { released here; the worker's exception path must not release it again }
    TThread.Queue(nil,
      procedure
      begin
        { release FIRST: a preview's OnDone confirms and queues the apply,
          which must not find the preview still counted }
        if DoneBusy then AdjustBusy(-1);
        if Assigned(DoneCb) then
          try
            DoneCb(DoneExit, DoneOut);
          except
            on E: Exception do
              if Assigned(GJobQueueDeferredHook) then GJobQueueDeferredHook('JobQueue: OnDone failed: ' + E.ClassName + ': ' + E.Message);
          end;
      end);
  end;
  if AJob.Kind = jkReindex then
    TThread.Queue(nil,
      procedure
      begin
        { read at run time: the runner may have stopped since the job began }
        if Assigned(GReindexDoneHook) then
          try
            GReindexDoneHook();
          except
            on E: Exception do
              if Assigned(GJobQueueDeferredHook) then
                GJobQueueDeferredHook('JobQueue: reindex-done hook raised ' + E.ClassName + ': ' + E.Message);
          end;
      end);
end;

{ THE ENGINE-HOLD GATE.

  A build stages a fresh drag-lint.exe over the deployed one. Every heavy job
  in this queue runs THAT image, so a job starting inside a build window
  either dies mid-run or holds the file the build is trying to replace.
  `ide-release` writes a hold sentinel meaning "do not start anything",
  and until now this queue was the one component that ignored it: RunOne
  spawned unconditionally.

  Two specific failures this prevents, both observed in the build path:
   * a queued bare `index` job makes build\stage-engine.ps1 REFUSE to stage
     (exit 3) rather than kill, so a user-requested reindex that happens to
     begin inside a build window turns the build's recovery into a refusal;
   * a bat-wrapped job is worse -- killing the inner drag-lint.exe leaves
     cmd.exe running the NEXT line of the bat.
  Not starting the job at all avoids both.

  PEEK, DO NOT EXTRACT. The job stays at the head of FPending while it waits,
  which is what preserves both coalescing (a later Enqueue with the same key
  still supersedes it -- Enqueue only looks at PENDING jobs) and FIFO order.
  A design that extracted and re-queued would break one or both, and neither
  break would be visible in a spot check.

  DEFERRED, NOT DROPPED. When the hold lifts the job runs. ClearPending still
  cancels it, because a user cancel is a user decision.

  NOT GATED, deliberately: a job ALREADY RUNNING when the hold appears keeps
  running. The hold's contract is "will not START anything" -- the same
  shape as EnsureLspClient's "will not RESPAWN" -- and the build kills a
  running holder exactly as it does today. }
function TDragLintJobQueue.WaitWhileEngineHeld(const ATitle, AKey: string): Boolean;
var
  SecsLeft: Integer;
begin
  Result:= True; { True = clear to run }
  while EngineIsHeld(SecsLeft) do
  begin
    { SHUTDOWN BEATS THE HOLD. Tested before every wait AND after every wake:
      without it a live hold could pin IDE unload for a whole recheck
      interval, turning a build into a hang at the worst possible moment. }
    if FShutdown then Exit(False);
    if not FDeferredLogged then
    begin
      FDeferredLogged:= True;
      if Assigned(GJobQueueDeferredHook) then
        try
          GJobQueueDeferredHook(Format('JobQueue: deferred "%s" (key %s) -- engine held for %ds',
                                       [ATitle, AKey, SecsLeft]));
        except  // dl:ok try-except-swallowed@31eb -- this IS the log channel; a hook that raises is disabled below, not retried
          { A LOGGING hook that raises cannot be reported anywhere -- this IS
            the reporting channel -- so it is DISABLED rather than swallowed
            and retried. A hook that threw once will throw on every deferral,
            and re-entering a broken logger from the worker thread each time
            trades a lost log line for a risk to the queue itself. Losing the
            line is the lesser harm and it is taken deliberately, once. }
          on E: Exception do GJobQueueDeferredHook:= nil;
        end;
    end;
    FWake.WaitFor(HOLD_RECHECK_MS);
    if FShutdown then Exit(False);
  end;
  { The hold has lifted (or was never there): re-arm the once-per-episode
    log so a LATER hold is reported too. }
  FDeferredLogged:= False;
end; // function

procedure TDragLintJobQueue.WorkerLoop;
var
  Job     : TDragLintJob;
  PeekTtl : string      ;
  PeekKey : string      ;
  HavePeek: Boolean     ;
begin
  while not FShutdown do
  begin
    FWake.WaitFor(WORKER_IDLE_RECHECK_MS);   { bounded: an empty peek just waits again }
    if FShutdown then Break;
    repeat
      { PEEK first -- under the lock, without removing -- so the gate below
        can wait with the job still queued and still coalescable. }
      HavePeek:= False;
      PeekTtl := '';
      PeekKey := '';
      FLock.Enter;
      try
        if FPending.Count > 0 then
        begin
          HavePeek:= True;
          PeekTtl := FPending[0].Title;
          PeekKey := FPending[0].CoalesceKey;
        end;
      finally
        FLock.Leave;
      end;
      if not HavePeek then Break;

      { Blocks while the engine is held. Returns False only on shutdown.
        The job is still in FPending throughout. }
      if not WaitWhileEngineHeld(PeekTtl, PeekKey) then Break;

      { RE-READ THE HEAD AFTER THE WAIT. Minutes may have passed, and both
        coalescing and ClearPending can have changed or emptied the queue
        meanwhile -- so the peeked job is a hint, never the thing that runs. }
      Job:= nil;
      FLock.Enter;
      try
        if FPending.Count > 0 then
        begin
          Job:= FPending.Extract(FPending[0]); { take ownership, remove from list }
          FState.Running     := True;
          FState.CurrentTitle:= Job.Title;
          FState.Percent     := -1;
          SyncPendingLocked;
        end;
      finally
        FLock.Leave;
      end;
      if Job = nil then Break;

      try
        RunOne(Job);
      except
        { a bad job must never kill the worker }
      end;
      { RunOne clears Busy once it has queued the release; still set means it
        raised first, and the count must not stay up (a stuck wait cursor) }
      if Job.Busy then TThread.Queue(nil, procedure begin AdjustBusy(-1); end);
      Job.Free;

      FLock.Enter;
      try
        FState.Running     := False;
        FState.CurrentTitle:= '';
        FState.Percent     := -1;
        SyncPendingLocked;
      finally
        FLock.Leave;
      end;
    until FShutdown;
  end;
end;

{ ---- singleton ---- }

var
  GQueue: TDragLintJobQueue = nil;

function JobQueue: TDragLintJobQueue;
begin
  if GQueue = nil then GQueue:= TDragLintJobQueue.Create;
  Result:= GQueue;
end;

procedure ShutdownJobQueue;
begin
  FreeAndNil(GQueue);
end;

initialization

finalization
  try ShutdownJobQueue; except end;

end.
