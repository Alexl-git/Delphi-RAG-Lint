unit DragLint.Plugin.ReportProgress;

{ The progress window of a Reports question (1.52 REPPROG, owner ruling
  2026-11-18): while `drag-lint ask` computes, a small modeless window shows an
  indeterminate bar and the elapsed seconds, with a Cancel button.

  WHY NO STEPS. `ask` reports no progress of its own (no heartbeat, no per-step
  lines), so the bar is a marquee and the only honest number is the elapsed time.
  ProcRunBeatText is NOT used: it is the newest beat of ANY run, so a reindex
  running beside the report would be shown as the report's progress.

  WHY CliAsync, NOT THE JOB QUEUE. Cancel must stop THIS report and nothing else.
  The queue's CancelRunning cancels whatever job runs at that moment -- by the time
  the click lands that can be a reindex -- and ClearPending drops every pending job.
  A TCliRunSlot owns exactly one child tree: Cancel kills that tree and guarantees
  the answer is never delivered, even one already queued, so nothing half-built is
  shown. The caller keeps the queue's "a report never races a reindex" promise for
  new jobs by holding the report's DB (JobQueue.HoldDb) for the run.

  THREADS. Main thread only, like CliAsync.

  OWNERSHIP. The window owns its run; freeing the window cancels the run. Every
  window still open is freed at this unit's finalization, before the package's
  code goes away. }

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Forms,
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.ComCtrls,
  Vcl.ExtCtrls,
  DragLint.Plugin.CliAsync;

const
  /// <summary>How often the window refreshes the elapsed seconds.</summary>
  REPORT_PROGRESS_TICK_MS = 250;

type
  /// <summary>Receives the elapsed whole seconds of a report run, on the main
  /// thread.</summary>
  /// <param name="pElapsedSec">Seconds since Start, rounded down.</param>
  TReportProgressEvent = reference to procedure(pElapsedSec: Integer);

  /// <summary>One report run: a single engine child off the main thread, with
  /// progress and a cancel that kills only that child.</summary>
  /// <remarks>
  /// Main thread only. The owner frees it; freeing it cancels a run in flight
  /// (TCliRunSlot.Destroy), so pOnDone never reaches a dead owner.
  /// </remarks>
  TReportProgressRun = class
  private
    FSlot      : TCliRunSlot;
    FCmdLine   : string;
    FStallMs   : Integer;
    FOnProgress: TReportProgressEvent;
    FOnDone    : TCliRunDone;
    FStartTick : UInt64;
    FCancelled : Boolean;
    function GetRunning: Boolean;
  public
    /// <summary>Prepares a run; nothing is spawned until Start.</summary>
    /// <param name="pCmdLine">Full command line, as CreateProcessW takes it.</param>
    /// <param name="pStallMs">Stall budget; see ProcRun.RunCaptureStdout.</param>
    /// <param name="pOnProgress">Called with 0 at Start and with the elapsed
    /// seconds on every Tick while the run is in flight; may be nil.</param>
    /// <param name="pOnDone">Called at most once, on the main thread, with the
    /// child's exit code and output; never after Cancel.</param>
    constructor Create(const pCmdLine: string; pStallMs: Integer; const pOnProgress: TReportProgressEvent;
      const pOnDone: TCliRunDone);
    /// <summary>Cancels a run in flight and frees the slot.</summary>
    destructor Destroy; override;
    /// <summary>Starts the child off the main thread and reports 0 s.</summary>
    /// <remarks>Never waits: returns before the child is spawned.</remarks>
    procedure Start;
    /// <summary>Reports the elapsed seconds while the run is in flight; silent
    /// once it answered or was cancelled.</summary>
    procedure Tick;
    /// <summary>Stops the run: its child tree is killed and pOnDone is never
    /// called, even when the answer was already on its way. A no-op when nothing
    /// runs.</summary>
    /// <remarks>Never waits for the kill; it returns at once.</remarks>
    procedure Cancel;
    /// <summary>Whole seconds since Start.</summary>
    /// <returns>0 before Start.</returns>
    function ElapsedSec: Integer;
    /// <summary>True from Start until the answer is about to be delivered or the
    /// run was cancelled.</summary>
    property Running: Boolean read GetRunning;
    /// <summary>True once Cancel stopped a run in flight.</summary>
    property Cancelled: Boolean read FCancelled;
  end;

  /// <summary>The modeless progress window of one report: what is computed, a
  /// marquee bar, the elapsed seconds and Cancel.</summary>
  /// <remarks>
  /// Main thread only. Any number may be open. Cancel, or closing the window,
  /// cancels the run and calls pOnCancelled once; a finished run hides the window,
  /// calls pOnDone once and releases the window. The window never shows a partial
  /// answer.
  /// </remarks>
  TDragLintReportProgressForm = class(TForm)
  private
    FRun        : TReportProgressRun;
    FTitle      : string;
    FStateLbl   : TLabel;
    FBar        : TProgressBar;
    FTimer      : TTimer;
    FOnDone     : TCliRunDone;
    FOnCancelled: TProc;
    procedure HandleTick(Sender: TObject);
    procedure HandleCancel(Sender: TObject);
    procedure ShowElapsed(pSec: Integer);
    procedure RunDone(pExit: Integer; const pOutput: string);
    function GetStateText: string;
  protected
    procedure DoClose(var Action: TCloseAction); override;
  public
    /// <summary>Builds the window and starts the run; the caller shows it.</summary>
    /// <param name="AOwner">Usually Application; nil in a test.</param>
    /// <param name="pTitle">What is computed, e.g. 'round-trip -- TForm1.Edit1'.</param>
    /// <param name="pCmdLine">Full command line of the engine run.</param>
    /// <param name="pStallMs">Stall budget; see ProcRun.RunCaptureStdout.</param>
    /// <param name="pOnDone">The answer, called once on the main thread after
    /// the window is hidden; never after a cancel.</param>
    /// <param name="pOnCancelled">Called once when the user cancels or closes the
    /// window mid-run; may be nil.</param>
    constructor CreateRun(AOwner: TComponent; const pTitle, pCmdLine: string; pStallMs: Integer;
      const pOnDone: TCliRunDone; const pOnCancelled: TProc);
    /// <summary>Cancels a run in flight (without calling pOnCancelled) and
    /// forgets the window.</summary>
    destructor Destroy; override;
    /// <summary>What the Cancel button does: stops the run, calls pOnCancelled
    /// once, closes the window. A no-op once the run answered or was
    /// cancelled.</summary>
    procedure CancelRun;
    /// <summary>The run this window shows.</summary>
    property Run: TReportProgressRun read FRun;
    /// <summary>The progress bar (a marquee).</summary>
    property Bar: TProgressBar read FBar;
    /// <summary>The text the window shows right now.</summary>
    property StateText: string read GetStateText;
  end;

/// <summary>The text of the progress window.</summary>
/// <param name="pTitle">What is computed.</param>
/// <param name="pElapsedSec">Whole seconds since the run started.</param>
/// <returns>pTitle, a line break, then 'Computing... N s elapsed'.</returns>
/// <remarks>Pure.</remarks>
function ReportProgressCaption(const pTitle: string; pElapsedSec: Integer): string;  // dl:ok unused-public-symbol@6d80 -- public as the test seam: ReportProgressTests F13 pins the caption

implementation

uses
  Winapi.Windows,
  System.Generics.Collections;

const
  MS_PER_SEC   = 1000;
  WIN_WIDTH    = 460;
  WIN_HEIGHT   = 150;
  BAR_HEIGHT   = 18;
  BTN_WIDTH    = 90;
  BTN_HEIGHT   = 28;
  GAP          = 8;
  MARQUEE_MS   = 30;
  INNER_WIDTH  = WIN_WIDTH - GAP - GAP;
  BTN_TOP      = WIN_HEIGHT - BTN_HEIGHT - GAP;
  BAR_TOP      = BTN_TOP - BAR_HEIGHT - GAP;
  LABEL_HEIGHT = BAR_TOP - GAP - GAP;

var
  { Every window not yet destroyed; main thread only. }
  GForms: TList<TDragLintReportProgressForm> = nil;

function ReportProgressCaption(const pTitle: string; pElapsedSec: Integer): string;
begin
  Result:= pTitle + sLineBreak + Format('Computing... %d s elapsed', [pElapsedSec]);
end;

{ ---- TReportProgressRun ---- }

constructor TReportProgressRun.Create(const pCmdLine: string; pStallMs: Integer;
  const pOnProgress: TReportProgressEvent; const pOnDone: TCliRunDone);
begin
  inherited Create;
  FSlot      := TCliRunSlot.Create;
  FCmdLine   := pCmdLine;
  FStallMs   := pStallMs;
  FOnProgress:= pOnProgress;
  FOnDone    := pOnDone;
end;

destructor TReportProgressRun.Destroy;
begin
  FreeAndNil(FSlot);
  inherited Destroy;
end;

function TReportProgressRun.GetRunning: Boolean;
begin
  Result:= (FSlot <> nil) and FSlot.Running;
end;

function TReportProgressRun.ElapsedSec: Integer;
begin
  Result:= if FStartTick = 0 then 0 else Integer((GetTickCount64 - FStartTick) div MS_PER_SEC);
end;

procedure TReportProgressRun.Start;
var
  Done: TCliRunDone;
begin
  Done:= FOnDone;
  FCancelled:= False;
  FStartTick:= GetTickCount64;
  FSlot.Start(FCmdLine, FStallMs, Done);
  if Assigned(FOnProgress) then FOnProgress(0);
end;

procedure TReportProgressRun.Tick;
begin
  if Running and Assigned(FOnProgress) then FOnProgress(ElapsedSec);
end;

procedure TReportProgressRun.Cancel;
begin
  if not Running then Exit;
  FSlot.Cancel;  { kills this run's child tree; its answer is dropped, even one already queued }
  FCancelled:= True;
end;

{ ---- TDragLintReportProgressForm ---- }

constructor TDragLintReportProgressForm.CreateRun(AOwner: TComponent; const pTitle, pCmdLine: string;
  pStallMs: Integer; const pOnDone: TCliRunDone; const pOnCancelled: TProc);
var
  Btn: TButton;
begin
  inherited CreateNew(AOwner);
  FTitle      := pTitle;
  FOnDone     := pOnDone;
  FOnCancelled:= pOnCancelled;
  Caption     := 'drag-lint Reports';
  BorderStyle := bsDialog;
  Position    := poScreenCenter;
  ClientWidth := WIN_WIDTH;
  ClientHeight:= WIN_HEIGHT;

  FStateLbl:= TLabel.Create(Self);
  FStateLbl.Parent:= Self;
  FStateLbl.SetBounds(GAP, GAP, INNER_WIDTH, LABEL_HEIGHT);
  FStateLbl.AutoSize:= False;
  FStateLbl.WordWrap:= True;

  FBar:= TProgressBar.Create(Self);
  FBar.Parent:= Self;
  FBar.SetBounds(GAP, BAR_TOP, INNER_WIDTH, BAR_HEIGHT);
  FBar.Style:= pbstMarquee;
  FBar.MarqueeInterval:= MARQUEE_MS;

  Btn:= TButton.Create(Self);  // dl:ok object-leak@0f01 -- owned by the form (Create(Self)); the form frees it
  Btn.Parent:= Self;
  Btn.Caption:= 'Cancel';
  Btn.Cancel:= True;
  Btn.SetBounds(WIN_WIDTH - BTN_WIDTH - GAP, BTN_TOP, BTN_WIDTH, BTN_HEIGHT);
  Btn.OnClick:= HandleCancel;

  FTimer:= TTimer.Create(Self);
  FTimer.Interval:= REPORT_PROGRESS_TICK_MS;
  FTimer.OnTimer:= HandleTick;

  if GForms <> nil then GForms.Add(Self);
  FRun:= TReportProgressRun.Create(pCmdLine, pStallMs, ShowElapsed, RunDone);
  FRun.Start;
end;

destructor TDragLintReportProgressForm.Destroy;
begin
  if GForms <> nil then GForms.Remove(Self);
  FreeAndNil(FRun);  { cancels a run in flight: its answer never reaches this dead window }
  inherited Destroy;
end;

function TDragLintReportProgressForm.GetStateText: string;
begin
  Result:= FStateLbl.Caption;
end;

procedure TDragLintReportProgressForm.ShowElapsed(pSec: Integer);
begin
  FStateLbl.Caption:= ReportProgressCaption(FTitle, pSec);
end;

procedure TDragLintReportProgressForm.HandleTick(Sender: TObject);
begin
  FRun.Tick;
end;

procedure TDragLintReportProgressForm.RunDone(pExit: Integer; const pOutput: string);
var
  Done: TCliRunDone;
begin
  FTimer.Enabled:= False;
  Hide;
  Done:= FOnDone;
  FOnDone:= nil;
  if Assigned(Done) then Done(pExit, pOutput);
  if Owner <> nil then Release;
end;

procedure TDragLintReportProgressForm.CancelRun;
var
  Cancelled: TProc;
begin
  if not FRun.Running then Exit;
  FRun.Cancel;
  FTimer.Enabled:= False;
  Cancelled:= FOnCancelled;
  FOnCancelled:= nil;
  FOnDone:= nil;
  if Assigned(Cancelled) then Cancelled();
  if Visible then Close;
end;

procedure TDragLintReportProgressForm.HandleCancel(Sender: TObject);
begin
  CancelRun;
end;

procedure TDragLintReportProgressForm.DoClose(var Action: TCloseAction);
begin
  inherited DoClose(Action);
  CancelRun;  { the title-bar X is a Cancel too }
  Action:= caFree;
end;

initialization
  GForms:= TList<TDragLintReportProgressForm>.Create;

finalization
  { Free what is still open: a window's run (and its child) must not outlive the
    package. Destroy removes each one from the list. }
  while (GForms <> nil) and (GForms.Count > 0) do GForms.Last.Free;
  FreeAndNil(GForms);

end.
