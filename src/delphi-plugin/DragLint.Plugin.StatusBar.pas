unit DragLint.Plugin.StatusBar;

{ v0.65.1 (R2): the status strip docked along the bottom of the drag-lint dock
  window. It is a pure VIEW: a TTimer polls DragLint.Plugin.JobQueue.GetState
  (no worker->UI callbacks) and renders the running job + live %, the pending
  depth, the last result, and a Cancel button (clears pending). Polling sidesteps
  any dangling-Self/unload-AV hazard from marshalling closures off the worker. }

interface

uses
  System.Classes
  , System.SysUtils
  , System.StrUtils
  , Vcl.Controls
  , Vcl.ExtCtrls
  , Vcl.StdCtrls
  , Vcl.ComCtrls
  , System.Generics.Collections   { GBars -- the live strips a note reaches }
  , DragLint.Plugin.JobQueue
  , DRagLint.Core.EngineHold      { EngineIsHeld -- announced from the tick below }
  , DragLint.Plugin.QueueText     { DLQueueLines -- the pure task-line formatter }
  ;

type
  TDragLintStatusBar = class(TPanel)
  private
    FStateLbl: TLabel      ;
    FBar     : TProgressBar;
    FDepthLbl: TLabel      ;
    FCancel  : TButton     ;
    { 2026-10-23 (spec ide-help-line 3.6): the Now:/Next:/Then: task lines,
      under the one-line strip. Hidden, and the strip one row high, while no
      job waits -- the strip then looks exactly as before. }
    FLinesLbl: TLabel      ;
    FTimer   : TTimer      ;
    FLast    : TQueueState ;
    FHasLast : Boolean     ;
    { Engine-hold announcement. FHoldText is what WE last wrote, so the clear
      can check it is still ours and not stomp a note somebody else set. }
    FHoldTick: Integer     ;
    FHoldText: string      ;
    procedure PollEngineHold;
    procedure HandleTimer (Sender: TObject);
    procedure HandleCancel(Sender: TObject);
    procedure Relayout;
    procedure ApplyState(const AState: TQueueState);
    procedure ApplyTaskLines(const AState: TQueueState);
    function  StatesEqual(const A, B: TQueueState): Boolean;
  protected
    procedure Resize; override; { lays out once parented/sized (handle-safe) }
  public
    constructor Create(AOwner: TComponent); override;
    destructor  Destroy; override;
  end;

/// <summary>Shows a short transient note on every live drag-lint status
/// strip -- e.g. 'drag-lint: hover WindowState'.</summary>
/// <param name="AText">The note. An empty string clears it.</param>
/// <remarks>
/// <para>WHY IT LIVES HERE, and not in a status-bar unit of its own. It did
/// have one -- DragLint.Plugin.StatusLine appended a panel to
/// INTAEditWindow.StatusBar -- written without noticing that a working
/// drag-lint status strip already existed and was the one the owner watches
/// (it is where 'Reindex ...' appears). Two status bars is how a note gets
/// written correctly and still never seen. There is now one.</para>
/// <para>A note YIELDS to job state: while the queue is running, the running
/// job and its percentage are the more important thing and win. The note
/// reappears when the queue goes idle, until cleared.</para>
/// <para>STATED PLAINLY: the strip is docked in the drag-lint dock window, so
/// the note is visible when that window is. Main thread only; guarded.</para>
/// </remarks>
procedure SetDragLintNote(const AText: string);

implementation

const
  { The strip's one-line row: the state label, bar, depth and Cancel live here. }
  STRIP_ROW_HEIGHT = 26;
  { Left inset of every label in the strip. }
  LABEL_INSET = 6;
  { Space the state label leaves before the depth label. }
  STATE_LABEL_GAP = 10;
  { Extra pixels per task line above the font's own height. }
  TASK_LINE_LEADING = 4;

var
  { Every live strip, so a note reaches all of them; and the note itself, so a
    strip created AFTER the note was set still shows it. Both unit-level rather
    than fields: the callers (the hover dwell timer, the editor) have no handle
    on any particular strip and must not need one. }
  GBars: TList<TDragLintStatusBar> = nil;
  GNote: string = '';

procedure SetDragLintNote(const AText: string);
var
  B: TDragLintStatusBar;
begin
  try
    if GNote = AText then Exit;   { a 200 ms dwell timer calls this repeatedly }
    GNote:= AText;
    if GBars = nil then Exit;
    for B in GBars do
      { Repaint from the LAST KNOWN state rather than re-polling: HandleTimer
        skips ApplyState when the queue state has not changed, so without this
        a note set between ticks would not appear until something else did. }
      if B.FHasLast then B.ApplyState(B.FLast)
      else               B.ApplyState(JobQueue.GetState);
  except
    { Called from a dwell timer, where an escaping exception surfaces as an IDE
      crash. A missing note is not worth that. }
  end;
end;

constructor TDragLintStatusBar.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  if GBars = nil then GBars:= TList<TDragLintStatusBar>.Create;
  GBars.Add(Self);
  Align     := alBottom;
  Height    := STRIP_ROW_HEIGHT;
  BevelOuter:= bvNone;
  Caption   := '';
  FHasLast  := False;

  FStateLbl:= TLabel.Create(Self);
  FStateLbl.Parent     := Self;
  FStateLbl.AutoSize   := False;
  FStateLbl.Transparent:= True;
  FStateLbl.Layout     := tlCenter;
  FStateLbl.Caption    := 'drag-lint: idle';

  FDepthLbl:= TLabel.Create(Self);
  FDepthLbl.Parent     := Self;
  FDepthLbl.AutoSize   := False;
  FDepthLbl.Transparent:= True;
  FDepthLbl.Layout     := tlCenter;
  FDepthLbl.Alignment  := taRightJustify;
  FDepthLbl.Caption    := '';

  FBar:= TProgressBar.Create(Self);
  FBar.Parent  := Self;
  FBar.Min     := 0;
  FBar.Max     := 100;
  FBar.Visible := False;

  FCancel:= TButton.Create(Self);
  FCancel.Parent  := Self;
  FCancel.Caption := 'Cancel';
  FCancel.Enabled := False;
  FCancel.OnClick := HandleCancel;

  FLinesLbl:= TLabel.Create(Self);
  FLinesLbl.Parent     := Self;
  FLinesLbl.AutoSize   := False;
  FLinesLbl.WordWrap   := False; { one task per line, via sLineBreak }
  FLinesLbl.Transparent:= True;
  FLinesLbl.Layout     := tlTop;
  FLinesLbl.Caption    := '';
  FLinesLbl.Visible    := False;

  { NB: do NOT lay out here -- reading ClientHeight/Width (or any handle-bound
    property) in the ctor forces handle creation while the panel still has no
    parent -> "control has no parent window". Layout happens in Resize, which the
    VCL calls after the dock frame parents + aligns us. }
  FTimer:= TTimer.Create(Self);
  FTimer.Interval:= 200;
  FTimer.OnTimer := HandleTimer;
  FTimer.Enabled := True;
end;

destructor TDragLintStatusBar.Destroy;
begin
  { Without this the list keeps a dangling strip and the next note writes
    through it. The dock window is closed and reopened routinely, so this is
    the normal path, not an edge case. }
  if GBars <> nil then GBars.Remove(Self);
  inherited;
end;

procedure TDragLintStatusBar.Relayout;
var
  H, W: Integer;
begin
  { Guard: Resize can fire during construction (Align/Height set) before the
    child controls exist; and use Height/Width (field reads) not ClientHeight/
    ClientWidth (which force a window handle). }
  if (FCancel = nil) or (FLinesLbl = nil) then Exit;
  { The controls keep to the first row; task lines (ApplyTaskLines) fill the
    rest of the height below it. }
  H:= STRIP_ROW_HEIGHT;
  W:= Width;
  FCancel  .SetBounds(W - 4 - 60, (H - 22) div 2, 60, 22);
  FBar     .SetBounds(FCancel.Left - 8 - 150, (H - 14) div 2, 150, 14);
  FDepthLbl.SetBounds(FBar.Left - 8 - 80, 0, 80, H);
  FStateLbl.SetBounds(LABEL_INSET, 0, FDepthLbl.Left - STATE_LABEL_GAP, H);
  FLinesLbl.SetBounds(LABEL_INSET, H, W - 2 * LABEL_INSET, Height - H);
end;

procedure TDragLintStatusBar.Resize;
begin
  inherited;
  Relayout;
end;

procedure TDragLintStatusBar.HandleCancel(Sender: TObject);
begin
  JobQueue.ClearPending;
  { reflect immediately; the timer would catch it within 200ms anyway }
  HandleTimer(nil);
end;

function TDragLintStatusBar.StatesEqual(const A, B: TQueueState): Boolean;
begin
  Result:= (A.Running = B.Running)
       and (A.Percent = B.Percent)
       { Phase is compared for the same reason every other field is: ApplyState
         only runs when the state DIFFERS, so a field left out of this test is a
         field that never reaches the screen. Percent alone is not enough --
         within one percent the phase can change, and those are precisely the
         slow tail phases the label exists to name. }
       and (A.Phase = B.Phase)
       and (A.QueueDepth = B.QueueDepth)
       and (A.CurrentTitle = B.CurrentTitle)
       and (A.LastResult = B.LastResult)
       { The Next:/Then: lines: a coalesced re-enqueue can reorder the waiting
         jobs without changing QueueDepth. }
       and (string.Join(#10, A.PendingTitles) = string.Join(#10, B.PendingTitles));
end;

procedure TDragLintStatusBar.PollEngineHold;
const
  { 200 ms tick; every fifth is once a second, which is the resolution the
    countdown is printed at anyway. }
  HOLD_POLL_TICKS = 5;
var
  Secs: Integer;
  Txt : string ;
begin
  { WHY THIS IS ON A TIMER, AND WHY THAT IS NOT THE THING THE NO-TIMER RULE
    FORBIDS.
    ------------------------------------------------------------------------
    EnsureLspClient already announces the hold, but only when something ASKS
    for the client. That is correct for the no-spawn rule and useless for the
    person who is not currently interacting: a build takes the engine away, the
    IDE goes quiet, and nothing on screen says why.

    The rule recorded on GLspRetryAfter objects to "a second uninvited source
    of PROCESS SPAWNS". This spawns nothing -- it stats one file, five times
    slower than the tick it rides on. It also must NOT grow into the respawn
    path: stopping and restarting the client stays lazy, exactly where it is.
    Announcing is not the same act as acting.

    BOUND, stated rather than discovered later: this strip lives in the
    drag-lint dock window. With that window closed there is nowhere to show
    this. Adding a second status surface to the IDE was tried before and
    removed -- see SetDragLintNote's own remarks. }
  Inc(FHoldTick);
  if (FHoldTick mod HOLD_POLL_TICKS) <> 0 then Exit;
  try
    if EngineIsHeld(Secs) then
    begin
      Txt:= Format('drag-lint: engine held for a rebuild (%ds)', [Secs]);
      SetDragLintNote(Txt);
      FHoldText:= Txt;
    end
    else if (FHoldText <> '') then
    begin
      { Clear ONLY what we wrote. Between two ticks a hover can set its own
        note, and clearing that would make the hover look like it never ran --
        the very symptom this strip spent a session fixing. }
      if GNote = FHoldText then SetDragLintNote('');
      FHoldText:= '';
    end;
  except
    { A status strip must never take the IDE down over a missing sentinel. }
  end;
end;

procedure TDragLintStatusBar.HandleTimer(Sender: TObject);
var
  S: TQueueState;
begin
  { BEFORE the unchanged-state early exit below. The queue is idle for the
    whole duration of a hold, so anything downstream of that Exit would never
    run -- which is exactly how a correct announcement ends up never appearing. }
  PollEngineHold;

  S:= JobQueue.GetState;
  if FHasLast and StatesEqual(S, FLast) then Exit;
  FLast   := S;
  FHasLast:= True;
  ApplyState(S);
end;

procedure TDragLintStatusBar.ApplyTaskLines(const AState: TQueueState);
var
  Lines : TArray<string>;
  NewH  : Integer;
begin
  Lines:= DLQueueLines(AState);
  FLinesLbl.Caption:= string.Join(sLineBreak, Lines);
  FLinesLbl.Visible:= Length(Lines) > 0;
  { Font.Height, not Canvas.TextHeight: no handle is forced (see Create). With
    no lines this is exactly STRIP_ROW_HEIGHT -- the strip as it always was. }
  NewH:= STRIP_ROW_HEIGHT + Length(Lines) * (Abs(Font.Height) + TASK_LINE_LEADING);
  if Height <> NewH then Height:= NewH; { Resize -> Relayout places the label }
end;

procedure TDragLintStatusBar.ApplyState(const AState: TQueueState);
begin
  if AState.Running then
  begin
    if AState.Percent >= 0 then
      FStateLbl.Caption:= AState.CurrentTitle + '  ' + IntToStr(AState.Percent) + '%'
                        + (if AState.Phase <> '' then '  ' + AState.Phase else '')
    else
      FStateLbl.Caption:= AState.CurrentTitle + '  ...';
    if not FBar.Visible then FBar.Visible:= True;
    if AState.Percent < 0 then
      FBar.Style:= pbstMarquee
    else
    begin
      FBar.Style   := pbstNormal;
      FBar.Position:= AState.Percent;
    end;
  end
  else
  begin
    { The transient note outranks 'idle' but never a running job -- a hover note
      must not hide a reindex's progress. }
    if GNote <> '' then
      FStateLbl.Caption:= GNote
    else if AState.LastResult <> '' then
      FStateLbl.Caption:= 'drag-lint: idle   (' + AState.LastResult + ')'
    else
      FStateLbl.Caption:= 'drag-lint: idle';
    if FBar.Visible then FBar.Visible:= False;
  end;
  if AState.QueueDepth > 0 then
    FDepthLbl.Caption:= IntToStr(AState.QueueDepth) + ' queued'
  else
    FDepthLbl.Caption:= '';
  FCancel.Enabled:= AState.QueueDepth > 0;
  ApplyTaskLines(AState);

  { PAINT NOW, DO NOT MERELY INVALIDATE.

    Assigning TLabel.Caption invalidates the control and leaves the actual
    drawing to the next pass of the message loop. That is fine for the job
    queue, whose state changes on a timer while the IDE is idle. It is USELESS
    for the hover note, which is the case this strip's note mechanism exists
    for: DragLint.Plugin.HoverTracker sets the note and then BLOCKS THE MAIN
    THREAD in the hover request (its own comment: "all on the main thread while
    a tooltip was trying to appear"), then clears the note as soon as the answer
    arrives. Between the set and the clear the message loop never runs, so the
    invalidation is never serviced and the caption is painted neither time.

    Reported by the owner as "I never saw this message ever" -- which was
    exactly right, and had been true since the note was added on 2026-08-19.
    The logic was correct the whole time; the pixels never happened.

    Update sends WM_PAINT straight to the control rather than posting it, so
    the note is on screen BEFORE the caller blocks. Cheap, and idempotent when
    nothing is invalid. }
  FStateLbl.Update;
  FDepthLbl.Update;
end;

{ `initialization` is REQUIRED here even though it is empty: Delphi rejects a
  bare `finalization` with E2029 ("Declaration expected but FINALIZATION
  found"). Removing it as dead syntax broke the BPL build on 2026-08-19. }
initialization

finalization
  { The strips are owned by their forms and are gone by now; only the list
    itself is ours to release. }
  FreeAndNil(GBars);

end.
