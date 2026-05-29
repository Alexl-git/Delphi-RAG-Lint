unit DragLint.Plugin.HoverForm;

{ Borderless hover popup for drag-lint LSP hover results.
  Auto-closes on ESC key, deactivation (click outside), or a 30-second timer.
  Call ShowDragLintHover() from the main thread only. }

interface

uses
  System.SysUtils, System.Classes,
  Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Graphics,
  Winapi.Windows, Winapi.Messages;

type
  TDragLintHoverForm = class(TForm)
  private
    FMemo:       TMemo;
    FCloseTimer: TTimer;
    procedure HandleKeyDown(Sender: TObject; var Key: Word;
      Shift: TShiftState);
    procedure HandleDeactivate(Sender: TObject);
    procedure HandleTimerTick(Sender: TObject);
  protected
    procedure DoClose(var Action: TCloseAction); override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure ShowAt(X, Y: Integer; const AContent: string);
  end;

procedure ShowDragLintHover(const AContent: string;
  AScreenX, AScreenY: Integer);

implementation

{ ---- TDragLintHoverForm ---- }

constructor TDragLintHoverForm.Create(AOwner: TComponent);
begin
  inherited CreateNew(AOwner);

  Caption     := '';
  BorderStyle := bsNone;
  FormStyle   := fsStayOnTop;
  Color       := clInfoBk;
  KeyPreview  := True;
  Position    := poDesigned;

  OnKeyDown   := HandleKeyDown;
  OnDeactivate := HandleDeactivate;

  FMemo := TMemo.Create(Self);
  FMemo.Parent      := Self;
  FMemo.Align       := alClient;
  FMemo.BorderStyle := bsNone;
  FMemo.ReadOnly    := True;
  FMemo.ScrollBars  := ssVertical;
  FMemo.Color       := clInfoBk;
  FMemo.Font.Name   := 'Consolas';
  FMemo.Font.Size   := 9;
  FMemo.TabStop     := False;

  FCloseTimer          := TTimer.Create(Self);
  FCloseTimer.Enabled  := False;
  FCloseTimer.Interval := 30000;
  FCloseTimer.OnTimer  := HandleTimerTick;
end;

procedure TDragLintHoverForm.DoClose(var Action: TCloseAction);
begin
  inherited;
  Action := caFree;
end;

procedure TDragLintHoverForm.HandleKeyDown(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
  if Key = VK_ESCAPE then
  begin
    Key := 0;
    Close;
  end;
end;

procedure TDragLintHoverForm.HandleDeactivate(Sender: TObject);
begin
  Close;
end;

procedure TDragLintHoverForm.HandleTimerTick(Sender: TObject);
begin
  FCloseTimer.Enabled := False;
  Close;
end;

procedure TDragLintHoverForm.ShowAt(X, Y: Integer; const AContent: string);
const
  MAX_W = 600;
  MAX_H = 400;
  PAD   = 8;
var
  Lines:      TArray<string>;
  L:          string;
  MaxLineLen: Integer;
  LineCount:  Integer;
  W, H:       Integer;
  MonR:       TRect;
begin
  FMemo.Text := AContent;

  Lines      := AContent.Split([#10, #13]);
  MaxLineLen := 0;
  LineCount  := 0;
  for L in Lines do
  begin
    Inc(LineCount);
    if Length(L) > MaxLineLen then
      MaxLineLen := Length(L);
  end;
  if LineCount = 0 then LineCount := 1;

  { Heuristic: ~7 px per char (Consolas 9pt), 16 px line height }
  W := MaxLineLen * 7 + PAD * 2;
  if W < 200  then W := 200;
  if W > MAX_W then W := MAX_W;

  H := LineCount * 16 + PAD * 2;
  if H < 60   then H := 60;
  if H > MAX_H then H := MAX_H;

  Width  := W;
  Height := H;

  { Clamp position so the popup stays on-screen }
  if SystemParametersInfo(SPI_GETWORKAREA, 0, @MonR, 0) then
  begin
    if X + W > MonR.Right  then X := MonR.Right  - W;
    if Y + H > MonR.Bottom then Y := MonR.Bottom - H;
    if X < MonR.Left then X := MonR.Left;
    if Y < MonR.Top  then Y := MonR.Top;
  end;

  Left := X;
  Top  := Y;

  FCloseTimer.Enabled := True;
  Show;
end;

{ ---- public factory ---- }

procedure ShowDragLintHover(const AContent: string;
  AScreenX, AScreenY: Integer);
var
  Form: TDragLintHoverForm;
begin
  Form := TDragLintHoverForm.Create(Application);
  Form.ShowAt(AScreenX, AScreenY, AContent);
end;

end.
