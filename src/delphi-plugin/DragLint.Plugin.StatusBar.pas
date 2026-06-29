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
  end;

implementation

constructor TDragLintStatusBar.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
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
    if AState.LastResult <> '' then
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

end.
