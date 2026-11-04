unit DragLint.Plugin.CliAsync;

{ Short drag-lint CLI runs off the IDE main thread (IDE-MAINTHREAD-CLI, 1.42).

  This is RunRefactorCliAsync (IDE-HANG, 1.40) moved to a home every form can use
  and given the two things the dialogs did not need: "latest run wins" for a
  search box, and a stop at package unload. RefactorForm now calls this.

  WHY NOT THE JOB QUEUE. TDragLintJobQueue is one serial worker for long jobs: a
  symbol search behind a ten-minute reindex would wait ten minutes. These runs are
  a person waiting on a read, so each has its own thread and the reindex keeps its
  queue.

  THREADS. Everything public is main-thread only; the worker body touches only its
  own run and the worker count. The run list and FAbandoned therefore need no lock:
  only the main thread reads or writes them.

  OWNERSHIP. A run is freed by Deliver, on the main thread, after the worker has
  queued it and stopped using it; the worker never frees. }

interface

uses
  System.Classes,
  Winapi.Windows,
  DragLint.Plugin.ProcRun;

const
  /// <summary>Default STALL budget of a CLI run (ProcRun semantics): the child is
  /// killed only after this long with neither output nor CPU.</summary>
  CLI_ASYNC_STALL_MS = 60000;

  /// <summary>How long StopAllCliRuns waits for the workers to come back. One
  /// KillProcess budget plus a margin: a cancelled run returns once its tree has
  /// been killed.</summary>
  CLI_ASYNC_STOP_MS = PROCRUN_KILL_WAIT_MS + 1000;

type
  /// <summary>Receives one CLI run's result on the MAIN thread.</summary>
  /// <param name="AExitCode">The child's exit code; PROCRUN_TIMED_OUT_EXIT_CODE when
  /// it was killed for making no progress; -1 when it could not start or the worker
  /// raised (AOutput then names the exception).</param>
  /// <param name="AOutput">stdout and stderr, interleaved.</param>
  TCliRunDone = reference to procedure(AExitCode: Integer; const AOutput: string);

  /// <summary>One consumer's "latest run wins" slot: starting a run abandons the one
  /// before it, so a slow old answer can never overwrite a newer one.</summary>
  /// <remarks>Main thread only. The owner frees the slot in its destructor; that
  /// abandons the run in flight, so ADone (which usually captures the owner) is never
  /// called on a dead owner. An abandoned run's child tree is killed and its ADone is
  /// never called, even when its answer was already on its way to the main
  /// thread.</remarks>
  TCliRunSlot = class
  private
    FCurrent: TObject;
    function GetRunning: Boolean;
  public
    /// <summary>Abandons the current run, if any.</summary>
    destructor Destroy; override;
    /// <summary>Abandons the current run and starts ACmdLine off the main
    /// thread.</summary>
    /// <param name="ACmdLine">Full command line, as CreateProcessW takes it.</param>
    /// <param name="AStallMs">Stall budget; see ProcRun.RunCaptureStdout.</param>
    /// <param name="ADone">Called at most once, on the main thread; not called when
    /// the run was abandoned or after StopAllCliRuns.</param>
    /// <remarks>Never waits: returns before the child is spawned.</remarks>
    procedure Start(const ACmdLine: string; AStallMs: Integer; const ADone: TCliRunDone);
    /// <summary>Abandons the current run, if any; a no-op otherwise.</summary>
    procedure Cancel;
    /// <summary>True from Start until the run's ADone is about to run or the run was
    /// abandoned.</summary>
    property Running: Boolean read GetRunning;
  end;

/// <summary>Runs one command line off the main thread with no slot: nothing can
/// supersede it. For a run whose answer must be shown, such as a rename
/// apply.</summary>
/// <param name="ACmdLine">Full command line, as CreateProcessW takes it.</param>
/// <param name="ADone">Called once on the main thread, unless StopAllCliRuns comes
/// first; it must check for itself that what it touches is still alive.</param>
/// <param name="AStallMs">Stall budget; see ProcRun.RunCaptureStdout.</param>
/// <remarks>Main thread only. Never waits.</remarks>
procedure RunCliAsync(const ACmdLine: string; const ADone: TCliRunDone; AStallMs: Integer = CLI_ASYNC_STALL_MS);

/// <summary>Stops every run for good: kills the children, waits for the workers,
/// and withdraws any answer already queued to the main thread, whose code would be
/// gone after the package unloads. Later Start and RunCliAsync calls do nothing.</summary>
/// <param name="AWaitMs">How long to wait for the workers.</param>
/// <returns>True when every worker came back within AWaitMs.</returns>
/// <remarks>Main thread only. This unit's finalization calls it; call it directly
/// only from a test. A worker that misses the budget leaks its run rather than risk
/// freeing what it still uses.</remarks>
function StopAllCliRuns(AWaitMs: Cardinal = CLI_ASYNC_STOP_MS): Boolean;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  DragLint.Plugin.Telemetry;

const
  CLI_ASYNC_STOP_POLL_MS = 10;

type
  TCliRun = class
  private
    FCmdLine : string;
    FStallMs : Integer;
    FDone    : TCliRunDone;
    FSlot    : TCliRunSlot;
    FCancel  : THandle;
    FExitCode: Integer;
    FOutput  : string;
    procedure Work;
    procedure Deliver;
    procedure Abandon;
    procedure LeaveSlot;
  public
    constructor Create(const ACmdLine: string; AStallMs: Integer; const ADone: TCliRunDone; ASlot: TCliRunSlot);
    destructor Destroy; override;
  end;

var
  { Every run not yet delivered; main thread only. }
  GCliRuns: TObjectList<TCliRun> = nil;
  { Workers still inside Work; interlocked. }
  GCliWorkers: Integer = 0;
  { Set by StopAllCliRuns; main thread only. }
  GCliStopped: Boolean = False;

function StartRun(const ACmdLine: string; AStallMs: Integer; const ADone: TCliRunDone; ASlot: TCliRunSlot): TObject;
var
  Run: TCliRun;
begin
  Result:= nil;
  if GCliStopped then Exit;
  Run:= TCliRun.Create(ACmdLine, AStallMs, ADone, ASlot);
  GCliRuns.Add(Run);
  Result:= Run;
  InterlockedIncrement(GCliWorkers);
  TThread.CreateAnonymousThread(Run.Work).Start;
end;

{ ---- TCliRun ---- }

constructor TCliRun.Create(const ACmdLine: string; AStallMs: Integer; const ADone: TCliRunDone; ASlot: TCliRunSlot);
begin
  inherited Create;
  FCmdLine := ACmdLine;
  FStallMs := AStallMs;
  FDone    := ADone;
  FSlot    := ASlot;
  FCancel  := CreateEvent(nil, True, False, nil);
  FExitCode:= -1;
end;

destructor TCliRun.Destroy;
begin
  if FCancel <> 0 then CloseHandle(FCancel);
  inherited Destroy;
end;

procedure TCliRun.Work;
begin
  try
    try
      FExitCode:= RunCaptureStdout(FCmdLine, FOutput, FStallMs, FCancel);
    except
      on E: Exception do
      begin
        FExitCode:= -1;
        FOutput  := 'drag-lint: the run raised ' + E.ClassName + ': ' + E.Message;
        DLT('cliasync', FOutput);
      end;
    end;
    { Always queued, even when abandoned: Deliver is what frees the run. }
    TThread.Queue(nil, Deliver);
  finally
    InterlockedDecrement(GCliWorkers);
  end;
end;

procedure TCliRun.LeaveSlot;
begin
  if FSlot = nil then Exit;
  FSlot.FCurrent:= nil;
  FSlot:= nil;
end;

procedure TCliRun.Abandon;
begin
  FDone:= nil;   { no answer, and it drops what the closure captured right now }
  LeaveSlot;
  if not SetEvent(FCancel) then DLT('cliasync', 'SetEvent failed: ' + SysErrorMessage(GetLastError));
end;

procedure TCliRun.Deliver;
var
  Done    : TCliRunDone;
  ExitCode: Integer;
  Output  : string;
begin
  Done    := FDone;
  ExitCode:= FExitCode;
  Output  := FOutput;
  LeaveSlot;
  { Freed BEFORE ADone: ADone may start the next run or open a dialog that pumps. }
  GCliRuns.Remove(Self);
  if not Assigned(Done) then Exit;
  try
    Done(ExitCode, Output);
  except
    { Queued code runs inside CheckSynchronize, under the IDE's own message loop:
      an exception out of here would surface as an IDE error box. }
    on E: Exception do DLT('cliasync', 'ADone raised ' + E.ClassName + ': ' + E.Message);
  end;
end;

{ ---- TCliRunSlot ---- }

destructor TCliRunSlot.Destroy;
begin
  Cancel;
  inherited Destroy;
end;

function TCliRunSlot.GetRunning: Boolean;
begin
  Result:= FCurrent <> nil;
end;

procedure TCliRunSlot.Cancel;
begin
  if FCurrent <> nil then TCliRun(FCurrent).Abandon;
end;

procedure TCliRunSlot.Start(const ACmdLine: string; AStallMs: Integer; const ADone: TCliRunDone);
begin
  Cancel;
  FCurrent:= StartRun(ACmdLine, AStallMs, ADone, Self);
end;

{ ---- free functions ---- }

procedure RunCliAsync(const ACmdLine: string; const ADone: TCliRunDone; AStallMs: Integer);
begin
  StartRun(ACmdLine, AStallMs, ADone, nil);
end;

function StopAllCliRuns(AWaitMs: Cardinal): Boolean;
var
  Run : TCliRun;
  T0  : UInt64;
begin
  GCliStopped:= True;
  for Run in GCliRuns do Run.Abandon;
  T0:= GetTickCount64;
  while (GCliWorkers > 0) and (GetTickCount64 - T0 < AWaitMs) do Sleep(CLI_ASYNC_STOP_POLL_MS);
  Result:= GCliWorkers = 0;
  if not Result then
  begin
    { A worker still holds its run: leaking it beats freeing it underneath. }
    GCliRuns.OwnsObjects:= False;
    DLT('cliasync', Format('StopAllCliRuns: %d worker(s) missed %d ms -- abandoned', [GCliWorkers, AWaitMs]));
    Exit;
  end;
  { Every worker has queued and left. Withdraw what the main thread has not run yet:
    it would run from a package that is about to unload. }
  for Run in GCliRuns do TThread.RemoveQueuedEvents(nil, Run.Deliver);
  GCliRuns.Clear;
end;

initialization
  GCliRuns:= TObjectList<TCliRun>.Create(True);

finalization
  try
    StopAllCliRuns;
  except
    on E: Exception do DLT('cliasync', 'StopAllCliRuns raised ' + E.ClassName + ': ' + E.Message);
  end;
  FreeAndNil(GCliRuns);

end.
