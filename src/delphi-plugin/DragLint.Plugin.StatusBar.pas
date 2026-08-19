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
  ;

type
  TDragLintStatusBar = class(TPanel)
  private
    FStateLbl: TLabel      ;
    FBar     : TProgressBar;
    FDepthLbl: TLabel      ;
    FCancel  : TButton     ;
    FTimer   : TTimer      ;
    FLast    : TQueueState ;
    FHasLast : Boolean     ;
    procedure HandleTimer (Sender: TObject);
    procedure HandleCancel(Sender: TObject);
    procedure Relayout;
    procedure ApplyState(const AState: TQueueState);
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
  Height    := 26;
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
  if FCancel = nil then Exit;
  H:= Height;
  W:= Width;
  FCancel  .SetBounds(W - 4 - 60, (H - 22) div 2, 60, 22);
  FBar     .SetBounds(FCancel.Left - 8 - 150, (H - 14) div 2, 150, 14);
  FDepthLbl.SetBounds(FBar.Left - 8 - 80, 0, 80, H);
  FStateLbl.SetBounds(6, 0, FDepthLbl.Left - 10, H);
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
       and (A.QueueDepth = B.QueueDepth)
       and (A.CurrentTitle = B.CurrentTitle)
       and (A.LastResult = B.LastResult);
end;

procedure TDragLintStatusBar.HandleTimer(Sender: TObject);
var
  S: TQueueState;
begin
  S:= JobQueue.GetState;
  if FHasLast and StatesEqual(S, FLast) then Exit;
  FLast   := S;
  FHasLast:= True;
  ApplyState(S);
end;

procedure TDragLintStatusBar.ApplyState(const AState: TQueueState);
begin
  if AState.Running then
  begin
    if AState.Percent >= 0 then
      FStateLbl.Caption:= AState.CurrentTitle + '  ' + IntToStr(AState.Percent) + '%'
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
