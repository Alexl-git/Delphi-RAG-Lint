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

type
  TJobKind = (jkGeneric, jkReindex, jkLintAll, jkFormsCsv);

  { Snapshot of queue state for the status bar. Percent = -1 means indeterminate
    (no % yet, or a non-streaming job -> marquee). }
  TQueueState = record
    Running     : Boolean;
    CurrentTitle: string ;
    Percent     : Integer;
    QueueDepth  : Integer; { pending jobs, NOT counting the running one }
    LastResult  : string ;
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
    constructor Create;
  end;

  TDragLintJobQueue = class
  private
    FLock    : TCriticalSection;
    FPending : TObjectList<TDragLintJob>;
    FWake    : TEvent;
    FWorker  : TThread;
    FShutdown: Boolean;
    FState   : TQueueState;
    { Worker thread only: whether THIS deferral episode has been logged.
      Cleared when the hold lifts, so a later hold is reported again. }
    FDeferredLogged: Boolean;
    procedure WorkerLoop;
    function  WaitWhileEngineHeld(const ATitle, AKey: string): Boolean;
    procedure RunOne(AJob: TDragLintJob);
    procedure SetPercent(APct: Integer);
    procedure SetLastResult(const AText: string);
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Enqueue AJob (queue takes ownership). A pending job with the
    /// same non-empty CoalesceKey is dropped first. Call from the main thread.</summary>
    procedure Enqueue(AJob: TDragLintJob);
    /// <summary>Cancel all pending (not-yet-running) jobs; the running one finishes.</summary>
    procedure ClearPending;
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
  The flag clears when the hold lifts, so a second hold logs again. }
var
  GJobQueueDeferredHook: TProc<string> = nil;

{ Lazy singleton (create/access on the main thread) + finalization teardown. }
function JobQueue: TDragLintJobQueue;
procedure ShutdownJobQueue;

implementation

uses
  DragLint.Plugin.ProcRun
  { The gate's only new dependency. Core.EngineHold reads a sentinel file
    and touches no process and no ToolsAPI, so the unit still compiles
    headless -- which the harness for this gate depends on. }
  , DRagLint.Core.EngineHold
  ;

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
  FShutdown:= False;
  FDeferredLogged:= False;
  FState.Running   := False;
  FState.Percent   := -1;
  FState.QueueDepth:= 0;
  FWorker  := TQueueWorker.Create(Self);
end;

destructor TDragLintJobQueue.Destroy;
begin
  { Stop the worker cleanly BEFORE freeing anything it touches (avoids unload AV). }
  FShutdown:= True;
  if FWake <> nil then FWake.SetEvent;
  if FWorker <> nil then
  begin
    FWorker.WaitFor;
    FWorker.Free;
  end;
  FPending.Free;
  FWake.Free;
  FLock.Free;
  inherited;
end;

procedure TDragLintJobQueue.Enqueue(AJob: TDragLintJob);
var
  I: Integer;
begin
  if AJob = nil then Exit;
  FLock.Enter;
  try
    if AJob.CoalesceKey <> '' then
      for I:= FPending.Count - 1 downto 0 do
        if SameText(FPending[I].CoalesceKey, AJob.CoalesceKey) then
          FPending.Delete(I); { OwnsObjects -> frees the superseded job }
    FPending.Add(AJob);
    FState.QueueDepth:= FPending.Count;
  finally
    FLock.Leave;
  end;
  FWake.SetEvent;
end;

procedure TDragLintJobQueue.ClearPending;
begin
  FLock.Enter;
  try
    FPending.Clear; { frees pending jobs; the running one is owned by the worker frame }
    FState.QueueDepth:= 0;
  finally
    FLock.Leave;
  end;
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
  FLock.Enter;
  try
    FState.Percent:= APct;
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

procedure TDragLintJobQueue.RunOne(AJob: TDragLintJob);
var
  ExitCode: Integer;
  Output  : string ;
  SB      : TStringBuilder;
  Res     : string ;
begin
  ExitCode:= 2;
  Output  := '';

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
        begin
          SB.AppendLine(ALine);
          { parse 'lint-all: ... NN% ...' -> the digit run just before '%' }
          Pct:= -1;
          if (Length(ALine) > 9) and (Copy(ALine, 1, 9) = 'lint-all:') then
          begin
            P:= Pos('%', ALine);
            if P > 1 then
            begin
              E:= P - 1; B:= E;
              while (B >= 1) and CharInSet(ALine[B], ['0'..'9']) do Dec(B);
              Pct:= StrToIntDef(Copy(ALine, B + 1, E - B), -1);
            end;
          end;
          if Pct >= 0 then SetPercent(Pct);
          if Assigned(AJob.OnLine) then
            try AJob.OnLine(ALine) except end;
        end,
        ExitCode);
      Output:= SB.ToString;
    finally
      SB.Free;
    end;
  end
  else
  begin
    SetPercent(-1); { indeterminate -> marquee }
    ExitCode:= RunCaptureStdout(AJob.CmdLine, Output, AJob.TimeoutMs);
  end;

  SetPercent(100);

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
  else if ExitCode = 2 then
    Res:= Res + ': failed'
  else
    Res:= Res + ': done';
  SetLastResult(Res);

  if Assigned(AJob.OnDone) then
  begin
    { value-capture so the closure is independent of AJob (freed next) and of
      the queue: holds the (ref-counted) callback + exit code + output only. }
    var DoneCb  : TJobDone:= AJob.OnDone;
    var DoneExit: Integer := ExitCode;
    var DoneOut : string  := Output;
    TThread.Queue(nil,
      procedure
      begin
        try DoneCb(DoneExit, DoneOut) except end;
      end);
  end;
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
          FState.QueueDepth  := FPending.Count;
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
      Job.Free;

      FLock.Enter;
      try
        FState.Running     := False;
        FState.CurrentTitle:= '';
        FState.Percent     := -1;
        FState.QueueDepth  := FPending.Count;
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
