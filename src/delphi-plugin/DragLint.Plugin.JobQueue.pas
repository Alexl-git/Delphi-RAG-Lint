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
    procedure WorkerLoop;
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

{ Lazy singleton (create/access on the main thread) + finalization teardown. }
function JobQueue: TDragLintJobQueue;
procedure ShutdownJobQueue;

implementation

uses
  DragLint.Plugin.ProcRun
  ;

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

procedure TDragLintJobQueue.WorkerLoop;
var
  Job: TDragLintJob;
begin
  while not FShutdown do
  begin
    FWake.WaitFor(INFINITE);
    if FShutdown then Break;
    repeat
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
