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
  TJobKind = (jkGeneric, jkReindex, jkLintAll, jkFormsCsv);

  { Snapshot of queue state for the status bar. Percent = -1 means indeterminate
    (no % yet, or a non-streaming job -> marquee). }
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

  TJobPreRun = TProc;                  { UI thread, before the process starts }
  TJobLine   = TProc<string>;          { worker thread, per output line }
  TJobDone   = TProc<Integer, string>; { UI thread: (exit code, full output) }

  /// <summary>One queued heavy job. Owned by the queue once enqueued.</summary>
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
    constructor Create;
  end;

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
    procedure WorkerLoop;
    function  WaitWhileEngineHeld(const ATitle, AKey: string): Boolean;
    procedure RunOne(AJob: TDragLintJob);
    procedure SetPercent(APct: Integer); overload;
    procedure SetPercent(APct: Integer; const APhase: string); overload;
    procedure SetLastResult(const AText: string);
    { Caller holds FLock. The ONE place QueueDepth and PendingTitles are set. }
    procedure SyncPendingLocked;
  public
    constructor Create;
    /// <summary>Stops the worker: signals the cancel event, so a running job's
    /// child process tree is killed rather than waited out, then joins the
    /// worker. Pending jobs are dropped without their OnDone.</summary>
    destructor Destroy; override;
    /// <summary>Enqueue AJob (queue takes ownership). A pending job with the
    /// same non-empty CoalesceKey is dropped first. Call from the main thread.</summary>
    procedure Enqueue(AJob: TDragLintJob);
    /// <summary>Cancel all pending (not-yet-running) jobs; the running one finishes.</summary>
    procedure ClearPending;
    /// <summary>Cancels the RUNNING job when it takes a cancel (its CancelGraceMs
    /// &gt; 0): its engine is asked to stand down -- roll back and exit -- and its
    /// process tree is killed only if it has not exited after CancelGraceMs.</summary>
    /// <returns>True when a cancel was sent; False when nothing runs, the running
    /// job takes no cancel, or one was already sent.</returns>
    /// <remarks>Any thread. The job's OnDone still runs, with the engine's own exit
    /// code and output (or PROCRUN_CANCELLED_EXIT_CODE after the kill).</remarks>
    function CancelRunning: Boolean;
    /// <summary>Thread-safe snapshot of the current state.</summary>
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
/// <remarks>Main thread only.</remarks>
function JobQueueBusy: Boolean;

{ Lazy singleton (create/access on the main thread) + finalization teardown. }
function JobQueue: TDragLintJobQueue;
procedure ShutdownJobQueue;

implementation

uses
  System.Math
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
    Res:= Res + Format(': timed out after %d s', [AJob.TimeoutMs div MSecsPerSec])
  else if (ExitCode = PROCRUN_CANCELLED_EXIT_CODE) or Cancelled then
    Res:= Res + ': cancelled' { Cancelled: the engine stood down by itself and exited with its own code }
  else if ExitCode = 2 then
    Res:= Res + ': failed'
  { F1 (2026-10-25): `index` exits 1 when a file failed to index (the run carried
    on; that file keeps its old rows) and 3 on a fatal -- neither is "done". }
  else if (AJob.Kind = jkReindex) and (ExitCode <> 0) then
    Res:= Res + Format(': failed (exit %d)', [ExitCode])
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
    FWake.WaitFor(INFINITE);
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
