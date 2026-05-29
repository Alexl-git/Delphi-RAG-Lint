unit DragLint.Plugin.EditViewNotifier;

interface

uses
  System.SysUtils, System.Classes,
  Vcl.Graphics, Vcl.Forms, Vcl.Controls,
  DockForm,
  ToolsAPI;

procedure RegisterDragLintEditViewNotifier;
procedure UnregisterDragLintEditViewNotifier;
procedure InvokeInlineInfo;

implementation

uses
  Winapi.Windows,
  System.IOUtils,
  DragLint.Plugin.DiagnosticCache,
  DragLint.Plugin.CodeLensCache,
  DragLint.Plugin.RegistryColors,
  DragLint.Plugin.Settings;

{ ---- TDragLintEditViewNotifier -------------------------------------------- }

type
  TDragLintEditViewNotifier = class(TInterfacedObject, INTAEditViewNotifier)
  public
    { IOTANotifier }
    procedure AfterSave;
    procedure BeforeSave;
    procedure Destroyed;
    procedure Modified;
    { INTAEditViewNotifier }
    procedure EditorIdle(const View: IOTAEditView);
    procedure BeginPaint(const View: IOTAEditView; var FullRepaint: Boolean);
    procedure EndPaint(const View: IOTAEditView);
    procedure PaintLine(const View: IOTAEditView; LineNumber: Integer;
      const LineText: PAnsiChar; const TextWidth: Word;
      const LineAttributes: TOTAAttributeArray; const Canvas: TCanvas;
      const TextRect: TRect; const LineRect: TRect; const CellSize: TSize);
  end;

procedure TDragLintEditViewNotifier.AfterSave; begin end;
procedure TDragLintEditViewNotifier.BeforeSave; begin end;
procedure TDragLintEditViewNotifier.Destroyed; begin end;
procedure TDragLintEditViewNotifier.Modified; begin end;
procedure TDragLintEditViewNotifier.EditorIdle(const View: IOTAEditView); begin end;
procedure TDragLintEditViewNotifier.BeginPaint(const View: IOTAEditView;
  var FullRepaint: Boolean); begin end;
procedure TDragLintEditViewNotifier.EndPaint(const View: IOTAEditView); begin end;

function SeverityColor(ASev: TDragLintSeverity;
  const AC: TDragLintColors): TColor;
begin
  case ASev of
    dlsError:   Result := AC.ErrorColor;
    dlsWarning: Result := AC.WarningColor;
    dlsHint:    Result := AC.HintColor;
  else
    Result := AC.InfoColor;
  end;
end;

procedure TDragLintEditViewNotifier.PaintLine(const View: IOTAEditView;
  LineNumber: Integer; const LineText: PAnsiChar; const TextWidth: Word;
  const LineAttributes: TOTAAttributeArray; const Canvas: TCanvas;
  const TextRect: TRect; const LineRect: TRect; const CellSize: TSize);
var
  Settings: TDragLintSettings;
  Colors:   TDragLintColors;
  FilePath: string;
  Diags: TArray<TDragLintDiagnostic>;
  D: TDragLintDiagnostic;
  MaxSev: TDragLintSeverity;
  HasDiag: Boolean;
  StartX, EndX, BottomY: Integer;
  i: Integer;
  WaveY, WaveX: Integer;
  CY: Integer;
  SavedColor: TColor;
  SavedStyle: TPenStyle;
  SavedWidth: Integer;
  SavedBrush: TColor;
  SavedBrushStyle: TBrushStyle;
  CodeLensText: string;
  SavedFontColor: TColor;
  SavedFontStyle: TFontStyles;

  function SevEnabled(S: TDragLintSeverity): Boolean;
  begin
    case S of
      dlsError:   Result := Settings.ShowErrorsInline;
      dlsWarning: Result := Settings.ShowWarningsInline;
      dlsHint:    Result := Settings.ShowHintsInline;
    else
      Result := Settings.ShowInfoInline;
    end;
  end;

begin
  Settings := LoadSettings;
  if not Settings.EnableInlineMarkers then Exit;
  if View = nil then Exit;
  if View.Buffer = nil then Exit;

  FilePath := View.Buffer.FileName;
  if FilePath = '' then Exit;

  { PaintLine LineNumber is 1-based; cache stores 0-based. }
  Diags := Cache.GetForLine(FilePath, LineNumber - 1);
  if Length(Diags) = 0 then Exit;

  HasDiag := False;
  MaxSev  := dlsHint;
  for D in Diags do
    if SevEnabled(D.Severity) then
    begin
      HasDiag := True;
      if Ord(D.Severity) < Ord(MaxSev) then
        MaxSev := D.Severity;
    end;
  if not HasDiag then Exit;

  Colors := LoadEditorColors;

  SavedColor      := Canvas.Pen.Color;
  SavedStyle      := Canvas.Pen.Style;
  SavedWidth      := Canvas.Pen.Width;
  SavedBrush      := Canvas.Brush.Color;
  SavedBrushStyle := Canvas.Brush.Style;
  try
    { ---- Gutter dot ---- }
    CY := LineRect.Top + (LineRect.Bottom - LineRect.Top) div 2;
    Canvas.Pen.Color   := SeverityColor(MaxSev, Colors);
    Canvas.Brush.Color := SeverityColor(MaxSev, Colors);
    Canvas.Brush.Style := bsSolid;
    Canvas.Ellipse(LineRect.Left + 2, CY - 3, LineRect.Left + 8, CY + 3);

    { ---- Wavy underline per diagnostic ---- }
    for i := 0 to High(Diags) do
    begin
      D := Diags[i];
      if not SevEnabled(D.Severity) then Continue;

      StartX := TextRect.Left + D.StartCol * CellSize.cx;
      EndX   := TextRect.Left + D.EndCol   * CellSize.cx;
      if EndX > TextRect.Right then EndX := TextRect.Right;
      if EndX <= StartX then EndX := StartX + CellSize.cx;

      BottomY := TextRect.Bottom - 1;
      Canvas.Pen.Color := SeverityColor(D.Severity, Colors);
      Canvas.Pen.Style := psSolid;
      Canvas.Pen.Width := 1;

      WaveY := BottomY;
      WaveX := StartX;
      Canvas.MoveTo(WaveX, WaveY);
      while WaveX < EndX do
      begin
        Inc(WaveX, 2);
        if WaveX > EndX then WaveX := EndX;
        { Flip between BottomY and BottomY-2 }
        if WaveY = BottomY then WaveY := BottomY - 2
        else                     WaveY := BottomY;
        Canvas.LineTo(WaveX, WaveY);
      end;
    end;
  finally
    Canvas.Pen.Color   := SavedColor;
    Canvas.Pen.Style   := SavedStyle;
    Canvas.Pen.Width   := SavedWidth;
    Canvas.Brush.Color := SavedBrush;
    Canvas.Brush.Style := SavedBrushStyle;
  end;

  { ---- Code lens overlay ---- }
  if Settings.EnableCodeLens then
  begin
    CodeLensText := CodeLensCache.GetForLine(FilePath, LineNumber - 1);
    if CodeLensText <> '' then
    begin
      SavedFontColor := Canvas.Font.Color;
      SavedFontStyle := Canvas.Font.Style;
      try
        Canvas.Font.Color := $00808080;  { dim grey }
        Canvas.Font.Style := [fsItalic];
        Canvas.Brush.Style := bsClear;
        Canvas.TextOut(
          TextRect.Left + TextWidth * CellSize.cx + 8,
          TextRect.Top,
          CodeLensText);
      finally
        Canvas.Font.Color := SavedFontColor;
        Canvas.Font.Style := SavedFontStyle;
      end;
    end;
  end;
end;

{ ---- TDragLintEditServicesNotifier ---------------------------------------- }

type
  TDragLintEditServicesNotifier = class(TInterfacedObject,
    INTAEditServicesNotifier)
  public
    { IOTANotifier }
    procedure AfterSave;
    procedure BeforeSave;
    procedure Destroyed;
    procedure Modified;
    { INTAEditServicesNotifier }
    procedure WindowShow(const EditWindow: INTAEditWindow;
      Show, LoadedFromDesktop: Boolean);
    procedure WindowNotification(const EditWindow: INTAEditWindow;
      Operation: TOperation);
    procedure WindowActivated(const EditWindow: INTAEditWindow);
    procedure WindowCommand(const EditWindow: INTAEditWindow;
      Command, Param: Integer; var Handled: Boolean);
    procedure EditorViewActivated(const EditWindow: INTAEditWindow;
      const EditView: IOTAEditView);
    procedure EditorViewModified(const EditWindow: INTAEditWindow;
      const EditView: IOTAEditView);
    procedure DockFormVisibleChanged(const EditWindow: INTAEditWindow;
      DockForm: TDockableForm);
    procedure DockFormUpdated(const EditWindow: INTAEditWindow;
      DockForm: TDockableForm);
    procedure DockFormRefresh(const EditWindow: INTAEditWindow;
      DockForm: TDockableForm);
  end;

procedure TDragLintEditServicesNotifier.AfterSave; begin end;
procedure TDragLintEditServicesNotifier.BeforeSave; begin end;
procedure TDragLintEditServicesNotifier.Destroyed; begin end;
procedure TDragLintEditServicesNotifier.Modified; begin end;
procedure TDragLintEditServicesNotifier.WindowShow(const EditWindow: INTAEditWindow;
  Show, LoadedFromDesktop: Boolean); begin end;
procedure TDragLintEditServicesNotifier.WindowNotification(
  const EditWindow: INTAEditWindow; Operation: TOperation); begin end;
procedure TDragLintEditServicesNotifier.WindowActivated(
  const EditWindow: INTAEditWindow); begin end;
procedure TDragLintEditServicesNotifier.WindowCommand(const EditWindow: INTAEditWindow;
  Command, Param: Integer; var Handled: Boolean); begin end;
procedure TDragLintEditServicesNotifier.EditorViewModified(
  const EditWindow: INTAEditWindow; const EditView: IOTAEditView); begin end;
procedure TDragLintEditServicesNotifier.DockFormVisibleChanged(
  const EditWindow: INTAEditWindow; DockForm: TDockableForm); begin end;
procedure TDragLintEditServicesNotifier.DockFormUpdated(
  const EditWindow: INTAEditWindow; DockForm: TDockableForm); begin end;
procedure TDragLintEditServicesNotifier.DockFormRefresh(
  const EditWindow: INTAEditWindow; DockForm: TDockableForm); begin end;

procedure TDragLintEditServicesNotifier.EditorViewActivated(
  const EditWindow: INTAEditWindow; const EditView: IOTAEditView);
var
  S:        TDragLintSettings;
  FilePath: string;
  DbPath:   string;
begin
  if EditView = nil then Exit;
  EditView.AddNotifier(TDragLintEditViewNotifier.Create);
  { Populate code lens cache for this file (synchronous; fast for small files) }
  if EditView.Buffer = nil then Exit;
  FilePath := EditView.Buffer.FileName;
  if FilePath = '' then Exit;
  S      := LoadSettings;
  if not S.EnableCodeLens then Exit;
  DbPath := ResolveDbPath(S.DbPathTemplate,
              TPath.GetDirectoryName(FilePath));
  CodeLensCache.PopulateOnce(FilePath, S.ExePath, DbPath);
end;

{ ---- Register / Unregister ------------------------------------------------ }

var
  GESNotifierIdx: Integer = -1;

procedure RegisterDragLintEditViewNotifier;
var
  ESS: IOTAEditorServices80;
begin
  if GESNotifierIdx >= 0 then Exit;
  if not Supports(BorlandIDEServices, IOTAEditorServices80, ESS) then Exit;
  GESNotifierIdx := ESS.AddNotifier(
    TDragLintEditServicesNotifier.Create);
end;

procedure UnregisterDragLintEditViewNotifier;
var
  ESS: IOTAEditorServices80;
begin
  if GESNotifierIdx < 0 then Exit;
  if Supports(BorlandIDEServices, IOTAEditorServices80, ESS) then
    ESS.RemoveNotifier(GESNotifierIdx);
  GESNotifierIdx := -1;
end;

{ ---- InvokeInlineInfo (Ctrl+Alt+I) ---------------------------------------- }

procedure InvokeInlineInfo;
var
  ESS:      IOTAEditorServices;
  View:     IOTAEditView;
  FilePath: string;
  CurLine:  Integer;
  Diags:    TArray<TDragLintDiagnostic>;
  D:        TDragLintDiagnostic;
  Msg:      string;
  SB:       TStringBuilder;
  HW:       THintWindow;
  P:        TPoint;
  R:        TRect;
begin
  if not Supports(BorlandIDEServices, IOTAEditorServices, ESS) then Exit;
  View := ESS.TopView;
  if View = nil then Exit;
  if View.Buffer = nil then Exit;

  FilePath := View.Buffer.FileName;
  if FilePath = '' then Exit;

  { Position.Row is 1-based; cache is 0-based }
  CurLine := View.Position.Row - 1;
  if CurLine < 0 then CurLine := 0;

  Diags := Cache.GetForLine(FilePath, CurLine);
  if Length(Diags) = 0 then
  begin
    { No diagnostics on this line - silently ignore }
    Exit;
  end;

  SB := TStringBuilder.Create;
  try
    for D in Diags do
    begin
      if SB.Length > 0 then SB.Append(#13#10);
      case D.Severity of
        dlsError:   SB.Append('[E] ');
        dlsWarning: SB.Append('[W] ');
        dlsHint:    SB.Append('[H] ');
      else
        SB.Append('[I] ');
      end;
      if D.Code <> '' then
      begin
        SB.Append(D.Code);
        SB.Append(': ');
      end;
      SB.Append(D.Message);
    end;
    Msg := SB.ToString;
  finally
    SB.Free;
  end;

  GetCursorPos(P);
  HW := THintWindow.Create(nil);
  try
    R := HW.CalcHintRect(400, Msg, nil);
    OffsetRect(R, P.X + 16, P.Y + 16);
    HW.ActivateHint(R, Msg);
    { Show for 4 seconds then free }
    Sleep(4000);
  finally
    HW.Free;
  end;
end;

end.
