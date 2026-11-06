unit DragLint.Plugin.SignatureForm;

{ Borderless signature-help popup for drag-lint LSP signatureHelp results.
  Auto-closes on ESC key, deactivation (click outside), or a 30-second timer.
  Call ShowDragLintSignature() from the main thread only. }

interface

uses
  System.SysUtils
  , System.Classes
  , System.JSON
  , Vcl.Forms
  , Vcl.Controls
  , Vcl.StdCtrls
  , Vcl.ExtCtrls
  , Vcl.Graphics
  , Winapi.Windows
  , Winapi.Messages
  ;

type
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DragLint.Plugin.SignatureForm.ShowDragLintSignature (DragLint.Plugin.SignatureForm.pas)</para>
  /// <para>Used in units: DragLint.Plugin.SignatureForm</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TDragLintSignatureForm = class(TForm)
    private
      FLabel     : TLabel;
      FCloseTimer: TTimer;
      /// <param name="Sender"><!-- drag-lint:auto type -->TObject</param>
      /// <param name="Key"><!-- drag-lint:auto type -->var Word</param>
      /// <param name="Shift"><!-- drag-lint:auto type -->TShiftState</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DragLint.Plugin.SignatureForm.TDragLintSignatureForm.Create (DragLint.Plugin.SignatureForm.pas)</para>
      /// <para>Mutates: Key (var)</para>
      /// <seealso cref="DragLint.Plugin.SignatureForm.TDragLintSignatureForm.Create"/>
      /// <seealso cref="DragLint.Plugin.SignatureForm.TDragLintSignatureForm.Deactivate"/>
      /// <seealso cref="DragLint.Plugin.SignatureForm.TDragLintSignatureForm.DoClose"/>
      /// <seealso cref="DragLint.Plugin.SignatureForm.TDragLintSignatureForm.HandleTimerTick"/>
      /// <seealso cref="DragLint.Plugin.SignatureForm.TDragLintSignatureForm.ShowSignature"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
      /// <param name="Sender"><!-- drag-lint:auto type -->TObject</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DragLint.Plugin.SignatureForm.TDragLintSignatureForm.Create (DragLint.Plugin.SignatureForm.pas)</para>
      /// <para>Reads: FCloseTimer</para>
      /// <seealso cref="DragLint.Plugin.SignatureForm.TDragLintSignatureForm.Create"/>
      /// <seealso cref="DragLint.Plugin.SignatureForm.TDragLintSignatureForm.Deactivate"/>
      /// <seealso cref="DragLint.Plugin.SignatureForm.TDragLintSignatureForm.DoClose"/>
      /// <seealso cref="DragLint.Plugin.SignatureForm.TDragLintSignatureForm.FormKeyDown"/>
      /// <seealso cref="DragLint.Plugin.SignatureForm.TDragLintSignatureForm.ShowSignature"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure HandleTimerTick(Sender: TObject);
    protected
      /// <param name="Action"><!-- drag-lint:auto type -->var TCloseAction</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Mutates: Action (var)</para>
      /// <para>Directives: override</para>
      /// <seealso cref="DragLint.Plugin.SignatureForm.TDragLintSignatureForm.Create"/>
      /// <seealso cref="DragLint.Plugin.SignatureForm.TDragLintSignatureForm.Deactivate"/>
      /// <seealso cref="DragLint.Plugin.SignatureForm.TDragLintSignatureForm.FormKeyDown"/>
      /// <seealso cref="DragLint.Plugin.SignatureForm.TDragLintSignatureForm.HandleTimerTick"/>
      /// <seealso cref="DragLint.Plugin.SignatureForm.TDragLintSignatureForm.ShowSignature"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure DoClose(var Action: TCloseAction); override;
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Directives: override</para>
      /// <seealso cref="DragLint.Plugin.SignatureForm.TDragLintSignatureForm.Create"/>
      /// <seealso cref="DragLint.Plugin.SignatureForm.TDragLintSignatureForm.DoClose"/>
      /// <seealso cref="DragLint.Plugin.SignatureForm.TDragLintSignatureForm.FormKeyDown"/>
      /// <seealso cref="DragLint.Plugin.SignatureForm.TDragLintSignatureForm.HandleTimerTick"/>
      /// <seealso cref="DragLint.Plugin.SignatureForm.TDragLintSignatureForm.ShowSignature"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure Deactivate; override;
    public
      /// <summary><!-- drag-lint:auto sum -->---- TDragLintSignatureForm ----</summary>
      /// <param name="AOwner"><!-- drag-lint:auto type -->TComponent</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DragLint.Plugin.SignatureForm.ShowDragLintSignature (DragLint.Plugin.SignatureForm.pas)</para>
      /// <para>Calls: CreateNew</para>
      /// <para>constructor</para>
      /// <para>Reads: FLabel, FCloseTimer   Writes: FLabel, FCloseTimer</para>
      /// <para>Directives: override</para>
      /// <seealso cref="DragLint.Plugin.SignatureForm.TDragLintSignatureForm.Deactivate"/>
      /// <seealso cref="DragLint.Plugin.SignatureForm.TDragLintSignatureForm.DoClose"/>
      /// <seealso cref="DragLint.Plugin.SignatureForm.TDragLintSignatureForm.FormKeyDown"/>
      /// <seealso cref="DragLint.Plugin.SignatureForm.TDragLintSignatureForm.HandleTimerTick"/>
      /// <seealso cref="DragLint.Plugin.SignatureForm.TDragLintSignatureForm.ShowSignature"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      constructor Create(AOwner: TComponent); override;
      /// <param name="X"><!-- drag-lint:auto type -->Integer</param>
      /// <param name="Y"><!-- drag-lint:auto type -->Integer</param>
      /// <param name="ASigLabel"><!-- drag-lint:auto type -->const string</param>
      /// <param name="AActiveParam"><!-- drag-lint:auto type -->Integer</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DragLint.Plugin.SignatureForm.ShowDragLintSignature (DragLint.Plugin.SignatureForm.pas)</para>
      /// <para>Calls: IntToStr, SystemParametersInfo</para>
      /// <para>Reads: FLabel, FCloseTimer</para>
      /// <seealso cref="DragLint.Plugin.SignatureForm.TDragLintSignatureForm.Create"/>
      /// <seealso cref="DragLint.Plugin.SignatureForm.TDragLintSignatureForm.Deactivate"/>
      /// <seealso cref="DragLint.Plugin.SignatureForm.TDragLintSignatureForm.DoClose"/>
      /// <seealso cref="DragLint.Plugin.SignatureForm.TDragLintSignatureForm.FormKeyDown"/>
      /// <seealso cref="DragLint.Plugin.SignatureForm.TDragLintSignatureForm.HandleTimerTick"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure ShowSignature(X, Y: Integer; const ASigLabel: string; AActiveParam: Integer);
  end;

/// <summary><!-- drag-lint:auto sum -->---- public factory ----</summary>
/// <param name="ASigLabel"><!-- drag-lint:auto type -->const string</param>
/// <param name="AActiveParam"><!-- drag-lint:auto type -->Integer</param>
/// <param name="AScreenX"><!-- drag-lint:auto type -->Integer</param>
/// <param name="AScreenY"><!-- drag-lint:auto type -->Integer</param>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DragLint.Plugin.Editor.InvokeSignatureHelp (DragLint.Plugin.Editor.pas)</para>
/// <para>Calls: DragLint.Plugin.SignatureForm.TDragLintSignatureForm.Create, DragLint.Plugin.SignatureForm.TDragLintSignatureForm.ShowSignature</para>
/// <para>UI thread only -- touches Form, Application</para>
/// <seealso cref="DragLint.Plugin.SignatureForm.TDragLintSignatureForm.Create"/>
/// <seealso cref="DragLint.Plugin.SignatureForm.TDragLintSignatureForm.ShowSignature"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure ShowDragLintSignature(const ASigLabel: string; AActiveParam: Integer; AScreenX, AScreenY: Integer);

implementation

{ ---- TDragLintSignatureForm ---- }

constructor TDragLintSignatureForm.Create(AOwner: TComponent);
begin
  inherited CreateNew(AOwner);

  Caption    := '';
  BorderStyle:= bsNone;
  FormStyle  := fsStayOnTop;
  Color      := clInfoBk;
  KeyPreview := True;
  Position   := poDesigned;

  OnKeyDown:= FormKeyDown;

  FLabel:= TLabel.Create(Self);
  FLabel.Parent:= Self;
  FLabel.Align := alClient;
  FLabel.Layout:= tlCenter;
  FLabel.Font.Name:= 'Consolas';
  FLabel.Font.Size:= 9;
  FLabel.Color   := clInfoBk;
  FLabel.AutoSize:= False;

  FCloseTimer:= TTimer.Create(Self);
  FCloseTimer.Enabled := False;
  FCloseTimer.Interval:= 30000;
  FCloseTimer.OnTimer := HandleTimerTick;
end; // constructor

procedure TDragLintSignatureForm.DoClose(var Action: TCloseAction);
begin
  inherited;
  Action:= caFree;
end;

procedure TDragLintSignatureForm.Deactivate;
begin
  inherited;
  Close;
end;

procedure TDragLintSignatureForm.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = VK_ESCAPE then
  begin
    Key:= 0;
    Close;
  end;
end;

procedure TDragLintSignatureForm.HandleTimerTick(Sender: TObject);
begin
  FCloseTimer.Enabled:= False;
  Close;
end;

procedure TDragLintSignatureForm.ShowSignature(X, Y: Integer; const ASigLabel: string; AActiveParam: Integer);
const
  MIN_W = 300;
  H     = 32;
  PAD_H = 16;
  PAD_V = 4;
var
  DisplayText: string ;
  W          : Integer;
  MonR       : TRect  ;
begin
  { Show full signature; append active-parameter indicator in caption }
  DisplayText:= '  ' + ASigLabel + '  ';
  if AActiveParam >= 0 then Caption:= 'arg ' + IntToStr(AActiveParam + 1)
  else Caption:= '';

  FLabel.Caption:= DisplayText;

  { Heuristic width: ~7px/char (Consolas 9pt) }
  W:= Length(DisplayText) * 7 + PAD_H;
  if W < MIN_W then W:= MIN_W;

  Width := W;
  Height:= H;

  { Clamp to work area }
  if SystemParametersInfo(SPI_GETWORKAREA, 0, @MonR, 0) then
  begin
    if X + W > MonR.Right  then X:= MonR.Right  - W;
    if Y + H > MonR.Bottom then Y:= MonR.Bottom - H;
    if X < MonR.Left then X:= MonR.Left;
    if Y < MonR.Top  then Y:= MonR.Top;
  end;

  Left:= X;
  Top := Y;

  FCloseTimer.Enabled:= True;
  Show;
end; // procedure

{ ---- public factory ---- }

procedure ShowDragLintSignature(const ASigLabel: string; AActiveParam: Integer; AScreenX, AScreenY: Integer);
var
  Form: TDragLintSignatureForm;
begin
  Form:= TDragLintSignatureForm.Create(Application);
  Form.ShowSignature(AScreenX, AScreenY, ASigLabel, AActiveParam);
end;

end.
