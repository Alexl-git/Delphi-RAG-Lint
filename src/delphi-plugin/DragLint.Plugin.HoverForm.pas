unit DragLint.Plugin.HoverForm;

{ Three-section borderless hover popup (v0.40.7):

    +-----------------------------------------------+
    | <kind>  <qualified-name>                      |  <- header label
    +-----------------------------------------------+
    | LSP hover markdown (docs / params)            |  <- summary memo
    +-----------------------------------------------+
    | Unit       Line  Code                         |  <- callers ListView
    |   file.pas 2192  RepointJobHeaderToFolder;    |     (Ctrl+click row =
    |   file.pas  705  RepointJobHeaderToFolder;    |      open source at line)
    +-----------------------------------------------+

  Auto-closes on ESC, click-outside, 30 s timer, cursor leaves IDE,
  cursor drifts > 220 px from anchor. Singleton: ShowDragLintHover
  no-ops while one is visible -- call CloseDragLintHover first to
  force a fresh popup.

  Main thread only. }

interface

uses
  System.SysUtils, System.Classes,
  Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Graphics, Vcl.ComCtrls,
  Winapi.Windows, Winapi.Messages,
  ToolsAPI;

type
  TDragLintCallerInfo = record
    FilePath: string;
    Line:     Integer;
    CodeText: string;
  end;

  TDragLintHoverForm = class(TForm)
  private
    FMemo:        TMemo;
    FCallers:     TListView;
    FCallerPaths: TStringList;
    FWatchTimer:  TTimer;
    FAnchor:      TPoint;
    FShowTickMs:  Cardinal;
    { v0.42: dwell popups dismiss tightly -- the moment the cursor leaves a
      small box around the ORIGINAL dwell point (where the user was pointing),
      not the whole 900 px popup rect. This stops the popup lingering over the
      Projects/Messages pane and also clears it when the mouse leaves the
      editor (that motion necessarily exits the anchor box). Menu-invoked
      popups keep the generous popup-rect dismissal so they stay interactive. }
    FAnchorDismiss: Boolean;
    FDwellAnchor:   TPoint;
    procedure HandleKeyDown(Sender: TObject; var Key: Word;
      Shift: TShiftState);
    procedure HandleDeactivate(Sender: TObject);
    procedure HandleTimerTick(Sender: TObject);
    procedure HandleWatchTick(Sender: TObject);
    procedure HandleCallerDblClick(Sender: TObject);
    procedure HandleCallerKey(Sender: TObject; var Key: Word;
      Shift: TShiftState);
    procedure HandleMemoClick(Sender: TObject);
  protected
    procedure DoClose(var Action: TCloseAction); override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure ShowAt(X, Y: Integer; const AHeader, ASummary: string;
      const ACallers: TArray<TDragLintCallerInfo>;
      AAnchorDismiss: Boolean; AAnchorX, AAnchorY: Integer);
  end;

procedure ShowDragLintHover(const AHeader, ASummary: string;
  const ACallers: TArray<TDragLintCallerInfo>;
  AScreenX, AScreenY: Integer;
  AAnchorDismiss: Boolean = False;
  AAnchorX: Integer = -1; AAnchorY: Integer = -1); overload;
procedure ShowDragLintHover(const AContent: string;
  AScreenX, AScreenY: Integer); overload;
procedure CloseDragLintHover;
function  IsDragLintHoverVisible: Boolean;
function  IsMouseOverDragLintHover: Boolean;
procedure OpenSourceAt(const AFile: string; ALine: Integer);

implementation

var
  GCurrentHover: TDragLintHoverForm = nil;

procedure OpenSourceAt(const AFile: string; ALine: Integer);
var
  ActSvc: IOTAActionServices;
  EdSvc:  IOTAEditorServices;
  View:   IOTAEditView;
begin
  if not Supports(BorlandIDEServices, IOTAActionServices, ActSvc) then Exit;
  ActSvc.OpenFile(AFile);
  if Supports(BorlandIDEServices, IOTAEditorServices, EdSvc) then
  begin
    View := EdSvc.TopView;
    if (View <> nil) and (ALine > 0) then
    begin
      View.Position.GotoLine(ALine);
      View.Paint;
    end;
  end;
end;

{ ---- IDE theme follow (v0.46) ---- }

var
  GHoverThemeRegistered: Boolean = False;

procedure ApplyIdeTheme(AForm: TCustomForm);
{ v0.46: make the popup follow the IDE's light/dark theme. ApplyTheme recolors
  the form + its child controls to the active VCL style. Guarded end-to-end so a
  missing service or an older IDE never breaks the popup -- it just stays on the
  default light colours. RegisterFormClass (once) lets the theme engine recognise
  our form class. }
var
  Theming: IOTAIDEThemingServices;
begin
  try
    if not Supports(BorlandIDEServices, IOTAIDEThemingServices, Theming) then Exit;
    if not Theming.IDEThemingEnabled then Exit;
    if not GHoverThemeRegistered then
    begin
      Theming.RegisterFormClass(TDragLintHoverForm);
      GHoverThemeRegistered := True;
    end;
    Theming.ApplyTheme(AForm);
  except
    { theming is best-effort -- never let it break the hover }
  end;
end;

{ ---- TDragLintHoverForm ---- }

constructor TDragLintHoverForm.Create(AOwner: TComponent);
begin
  inherited CreateNew(AOwner);

  { v0.40.8: real-tool-window look, not a tooltip.
    - White background (not clInfoBk yellow).
    - Real title bar via bsSizeToolWin + non-empty Caption.
    - No OnDeactivate close: click-outside no longer kills the popup.
    - No 30-second auto-close timer. Only ways to dismiss:
        (a) mouse moves > 20 px off the popup
        (b) ESC pressed
        (c) Close button in the toolwindow title bar }
  Caption     := 'drag-lint hover';
  BorderStyle := bsSizeToolWin;
  FormStyle   := fsStayOnTop;
  Color       := clWindow;
  KeyPreview  := True;
  Position    := poDesigned;

  OnKeyDown   := HandleKeyDown;

  { v0.40.8e: top header label removed -- the title bar shows the same
    "drag-lint -- kind name -- unit.pas (line)" string and a duplicate
    inside the body is just visual noise. }

  { Bottom: callers ListView. Created BEFORE memo so alClient memo fills middle. }
  FCallers := TListView.Create(Self);
  FCallers.Parent      := Self;
  FCallers.Align       := alBottom;
  FCallers.Height      := 130;
  FCallers.ViewStyle   := vsReport;
  FCallers.RowSelect   := True;
  FCallers.ReadOnly    := True;
  FCallers.GridLines   := False;
  FCallers.ShowColumnHeaders := True;
  FCallers.HideSelection     := False;
  FCallers.Font.Name   := 'Consolas';
  FCallers.Font.Size   := 9;
  with FCallers.Columns.Add do begin Caption := 'Unit'; Width := 180; end;
  with FCallers.Columns.Add do begin Caption := 'Line'; Width := 50;  end;
  with FCallers.Columns.Add do begin Caption := 'Code'; Width := 420; end;
  FCallers.OnDblClick  := HandleCallerDblClick;
  FCallers.OnKeyDown   := HandleCallerKey;

  { Middle: memo for docs / params / LSP markdown.
    v0.40.8e: double-clicking a "`qname` - line N" row attempts to navigate. }
  FMemo := TMemo.Create(Self);
  FMemo.Parent      := Self;
  FMemo.Align       := alClient;
  FMemo.BorderStyle := bsNone;
  FMemo.ReadOnly    := True;
  FMemo.ScrollBars  := ssVertical;
  FMemo.Color       := clWindow;
  FMemo.Font.Name   := 'Consolas';
  FMemo.Font.Size   := 9;
  FMemo.TabStop     := False;
  FMemo.OnClick     := HandleMemoClick;

  FCallerPaths := TStringList.Create;

  FWatchTimer          := TTimer.Create(Self);
  FWatchTimer.Enabled  := False;
  FWatchTimer.Interval := 150;
  FWatchTimer.OnTimer  := HandleWatchTick;

  { v0.46: follow the IDE light/dark theme (guarded; no-op on older IDEs). }
  ApplyIdeTheme(Self);
end;

procedure TDragLintHoverForm.DoClose(var Action: TCloseAction);
begin
  if FWatchTimer <> nil then FWatchTimer.Enabled := False;
  if GCurrentHover = Self then GCurrentHover := nil;
  FreeAndNil(FCallerPaths);
  inherited;
  Action := caFree;
end;

function GetIdeMainHwnd: HWND;
var
  Svcs: IOTAServices;
begin
  Result := 0;
  if Supports(BorlandIDEServices, IOTAServices, Svcs) then
    Result := Svcs.GetParentHandle;
  if (Result = 0) and (Application <> nil) and (Application.MainForm <> nil) then
    Result := Application.MainForm.Handle;
end;

procedure TDragLintHoverForm.HandleWatchTick(Sender: TObject);
const
  MARGIN  = 20;
  GRACE_MS = 1500;
  { v0.42: anchor-box half-extents ~ "1 line up/down, 3-4 chars left/right". }
  ANCHOR_HALF_W = 28;
  ANCHOR_HALF_H = 13;
  ANCHOR_GRACE_MS = 300;
var
  Pt:      TPoint;
  ExtRect: TRect;
  AncRect: TRect;
begin
  if not GetCursorPos(Pt) then Exit;

  if FAnchorDismiss then
  begin
    { v0.42 dwell popup: close the instant the cursor leaves a tight box around
      the ORIGINAL dwell point. Short grace so a sub-pixel jitter at spawn
      doesn't self-close. Leaving the editor moves well outside this box, so
      this also satisfies "clear hover when the mouse leaves the edit page". }
    if GetTickCount - FShowTickMs < ANCHOR_GRACE_MS then Exit;
    AncRect := Rect(FDwellAnchor.X - ANCHOR_HALF_W, FDwellAnchor.Y - ANCHOR_HALF_H,
                    FDwellAnchor.X + ANCHOR_HALF_W, FDwellAnchor.Y + ANCHOR_HALF_H);
    if not PtInRect(AncRect, Pt) then
      Close;
    Exit;
  end;

  { v0.40.8 menu popup: stays interactive -- mouse outside (popup + 20 px
    margin) closes it. ESC also closes via HandleKeyDown. Title-bar close
    button is provided by bsSizeToolWin.
    v0.40.8b: first 1.5 seconds after Show are a grace period -- the popup
    spawns at cursor+20, so the cursor is 20 px above the popup top; any
    1-px upward drift would otherwise close it immediately. }
  if GetTickCount - FShowTickMs < GRACE_MS then Exit;
  ExtRect := BoundsRect;
  InflateRect(ExtRect, MARGIN, MARGIN);
  if not PtInRect(ExtRect, Pt) then
    Close;
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
  { v0.40.8: deliberately a no-op. Earlier versions Close'd here, which made
    the popup vanish the moment the user clicked anywhere else (incl. inside
    the editor). The cursor-watch rule (mouse outside popup+20 px) is now
    the sole automatic dismissal. }
end;

procedure TDragLintHoverForm.HandleTimerTick(Sender: TObject);
begin
  { v0.40.8: 30-second auto-close timer removed; left as a no-op so any
    lingering OnTimer callbacks bound by older code don't AV. }
end;

procedure TDragLintHoverForm.HandleCallerDblClick(Sender: TObject);
var
  Sel: TListItem;
  Ln:  Integer;
  Idx: Integer;
begin
  Sel := FCallers.Selected;
  if (Sel = nil) or (FCallerPaths = nil) then Exit;
  if Sel.SubItems.Count = 0 then Exit;
  Idx := Sel.Index;
  if (Idx < 0) or (Idx >= FCallerPaths.Count) then Exit;
  Ln := StrToIntDef(Sel.SubItems[0], 0);
  OpenSourceAt(FCallerPaths[Idx], Ln);
  Close;
end;

procedure TDragLintHoverForm.HandleCallerKey(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
  if Key = VK_RETURN then
  begin
    Key := 0;
    HandleCallerDblClick(Sender);
  end;
end;

function CleanHoverMarkdown(const AMarkdown: string): string;
{ v0.46: the popup body is a plain TMemo with no markdown engine, so the LSP
  hover markdown was showing literal '**', '`' and '_..._' noise plus a blank
  line after almost every element. Render it as clean monospaced text:
    * drop code-span backticks and bold '**' (safe -- identifiers contain
      neither);
    * unwrap a line that is wholly italic '_..._' (e.g. "_2 overloads:_") WITHOUT
      touching underscores inside identifiers (MS_FOLDER stays intact);
    * collapse runs of blank lines to a single blank.
  The definition rows keep their "<qname> - line N" text so HandleMemoClick can
  still parse them for single-click navigation. }
var
  Lines: TArray<string>;
  SB: TStringBuilder;
  L, T: string;
  BlankRun: Boolean;
  I: Integer;
begin
  if Trim(AMarkdown) = '' then Exit('');
  Lines := AMarkdown.Split([#10]);
  SB := TStringBuilder.Create;
  try
    BlankRun := False;
    for I := 0 to High(Lines) do
    begin
      L := StringReplace(Lines[I], #13, '', [rfReplaceAll]);
      L := StringReplace(L, '`', '', [rfReplaceAll]);
      L := StringReplace(L, '**', '', [rfReplaceAll]);
      { unwrap whole-line italics only (don't disturb in-identifier underscores) }
      T := Trim(L);
      if (Length(T) >= 2) and (T[1] = '_') and (T[Length(T)] = '_') then
        L := Copy(T, 2, Length(T) - 2);
      if Trim(L) = '' then
      begin
        if BlankRun then Continue;   { collapse consecutive blanks }
        BlankRun := True;
      end
      else
        BlankRun := False;
      SB.AppendLine(L.TrimRight);
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function UnitNameFromQname(const AQname: string): string;
{ Mirror of Editor.ExtractHoverHeader's heuristic: drop the last 1 or 2
  segments of a dotted qname to get the unit. If the next-to-last segment
  starts with T/I/E it's a class/interface/exception, drop two; else drop one. }
var
  P, P2, I, DotCount: Integer;
begin
  Result := '';
  DotCount := 0;
  for I := 1 to Length(AQname) do
    if AQname[I] = '.' then Inc(DotCount);
  if DotCount = 0 then Exit;
  Result := AQname;
  if DotCount >= 2 then
  begin
    P := 0;
    for I := Length(Result) downto 1 do
      if Result[I] = '.' then begin P := I; Break; end;
    P2 := 0;
    for I := P - 1 downto 1 do
      if Result[I] = '.' then begin P2 := I; Break; end;
    if (P2 > 0) and (P2 + 1 <= Length(Result)) and
       CharInSet(Result[P2 + 1], ['T','I','E']) then
      Result := Copy(Result, 1, P2 - 1)
    else
      Result := Copy(Result, 1, P - 1);
  end
  else
    Result := Copy(Result, 1, Pos('.', Result) - 1);
end;

procedure TDragLintHoverForm.HandleMemoClick(Sender: TObject);
{ v0.40.8g: single-click navigation. We don't navigate on every click in the
  memo (the user has to be able to scroll / position the caret to read) -- we
  only navigate when the line under the caret matches the definition shape
  "<qname> - line N". Other lines pass through to normal memo click handling.
  v0.46: the body is now cleaned of markdown (CleanHoverMarkdown), so the rows
  read "- <qname> - line N" WITHOUT backticks; parse that shape. }
var
  LineIdx:  Integer;
  LineText, Body, Qname, LineStr, UnitName: string;
  DashAt, LineN: Integer;
begin
  LineIdx := FMemo.CaretPos.Y;
  if (LineIdx < 0) or (LineIdx >= FMemo.Lines.Count) then Exit;
  LineText := FMemo.Lines[LineIdx];

  { Gate: a definition row is "- <qname> - line N". Require the bullet, the
    " - line " separator, and a positive trailing integer so doc/blank lines
    (and ordinary "- bullet" prose) are left alone. }
  Body := LineText.TrimLeft;
  if not Body.StartsWith('- ') then Exit;
  Body := Copy(Body, 3, MaxInt);                 { drop the "- " bullet }

  DashAt := Pos(' - line ', Body);
  if DashAt <= 0 then Exit;
  Qname   := Trim(Copy(Body, 1, DashAt - 1));
  LineStr := Trim(Copy(Body, DashAt + Length(' - line '), MaxInt));
  LineN   := StrToIntDef(LineStr, 0);
  if (Qname = '') or (LineN <= 0) then Exit;

  UnitName := UnitNameFromQname(Qname);
  if UnitName = '' then Exit;
  OpenSourceAt(UnitName + '.pas', LineN);
  Close;
end;

procedure TDragLintHoverForm.ShowAt(X, Y: Integer; const AHeader, ASummary: string;
  const ACallers: TArray<TDragLintCallerInfo>;
  AAnchorDismiss: Boolean; AAnchorX, AAnchorY: Integer);
const
  MAX_W = 900;
  MAX_H = 700;
  PAD   = 8;
var
  I:          Integer;
  LI:         TListItem;
  W, H:       Integer;
  MonR:       TRect;
  CallersH:   Integer;
  HeaderH:    Integer;
  SummaryH:   Integer;
  ShortName:  string;
  Ln:         string;
  MaxLen:     Integer;
  CleanSummary: string;
begin
  FAnchorDismiss := AAnchorDismiss;
  if AAnchorX >= 0 then
    FDwellAnchor := Point(AAnchorX, AAnchorY)
  else
    FDwellAnchor := Point(X, Y);

  { v0.46: render markdown as clean memo text (the TMemo has no markdown engine). }
  CleanSummary := CleanHoverMarkdown(ASummary);
  FMemo.Text := CleanSummary;
  { v0.40.8g: title bar carries only "drag-lint -- kind name" (no file/line),
    because the body lists every definition with file:line already and the
    user reported the duplication as noise. ExtractHoverHeader still returns
    "kind name -- unit.pas (line)"; we strip everything from the first
    "   --   " separator onward for the title. }
  if AHeader <> '' then
  begin
    var ShortHeader: string := AHeader;
    var DashPos: Integer := Pos('   --   ', ShortHeader);
    if DashPos > 0 then
      ShortHeader := Trim(Copy(ShortHeader, 1, DashPos - 1));
    Caption := 'drag-lint -- ' + ShortHeader;
  end
  else
    Caption := 'drag-lint hover';

  FCallerPaths.Clear;
  FCallers.Items.BeginUpdate;
  try
    FCallers.Items.Clear;
    for I := 0 to High(ACallers) do
    begin
      LI := FCallers.Items.Add;
      ShortName := ExtractFileName(ACallers[I].FilePath);
      LI.Caption := ShortName;
      LI.SubItems.Add(IntToStr(ACallers[I].Line));
      LI.SubItems.Add(ACallers[I].CodeText);
      FCallerPaths.Add(ACallers[I].FilePath);
    end;
  finally
    FCallers.Items.EndUpdate;
  end;

  { Sizing: header 22 + summary lines * 16 + callers (header + rows * 18).
    v0.46: size to the CLEANED text (fewer blank lines after the trim). }
  HeaderH := 22;
  SummaryH := 16 * (1 + Length(CleanSummary.Split([#10]))); { rough }
  if SummaryH < 60 then SummaryH := 60;
  if SummaryH > 200 then SummaryH := 200;
  if Length(ACallers) = 0 then
  begin
    FCallers.Visible := False;
    CallersH := 0;
  end
  else
  begin
    FCallers.Visible := True;
    CallersH := 28 + Length(ACallers) * 18;
    if CallersH < 60 then CallersH := 60;
    if CallersH > 200 then CallersH := 200;
    FCallers.Height := CallersH;
  end;

  { v0.42: dwell popups size to their content width (the summary is short --
    a couple of declaration lines) instead of the fixed 900 px, so they don't
    blanket the panes behind the editor. Consolas 9 pt ~ 7 px/char. Menu
    popups keep the full width because they carry the callers grid. }
  if AAnchorDismiss then
  begin
    MaxLen := Length(AHeader);
    for Ln in CleanSummary.Split([#10]) do
      if Length(Ln.TrimRight) > MaxLen then MaxLen := Length(Ln.TrimRight);
    W := 40 + MaxLen * 7;
    if W < 200   then W := 200;
    if W > MAX_W then W := MAX_W;
  end
  else
    W := MAX_W;
  H := HeaderH + SummaryH + CallersH + PAD * 2;
  if H > MAX_H then H := MAX_H;
  if H < 120   then H := 120;

  Width  := W;
  Height := H;

  if SystemParametersInfo(SPI_GETWORKAREA, 0, @MonR, 0) then
  begin
    if X + W > MonR.Right  then X := MonR.Right  - W;
    if Y + H > MonR.Bottom then Y := MonR.Bottom - H;
    if X < MonR.Left then X := MonR.Left;
    if Y < MonR.Top  then Y := MonR.Top;
  end;
  Left := X;
  Top  := Y;
  FAnchor.X := X;
  FAnchor.Y := Y;

  FShowTickMs := GetTickCount;
  FWatchTimer.Enabled := True;
  Show;
end;

{ ---- public factory ---- }

procedure ShowDragLintHover(const AHeader, ASummary: string;
  const ACallers: TArray<TDragLintCallerInfo>;
  AScreenX, AScreenY: Integer;
  AAnchorDismiss: Boolean = False;
  AAnchorX: Integer = -1; AAnchorY: Integer = -1);
var
  Form: TDragLintHoverForm;
begin
  if (GCurrentHover <> nil) and GCurrentHover.Visible then Exit;
  Form := TDragLintHoverForm.Create(Application);
  GCurrentHover := Form;
  Form.ShowAt(AScreenX, AScreenY, AHeader, ASummary, ACallers,
    AAnchorDismiss, AAnchorX, AAnchorY);
end;

procedure ShowDragLintHover(const AContent: string;
  AScreenX, AScreenY: Integer);
var
  Empty: TArray<TDragLintCallerInfo>;
begin
  SetLength(Empty, 0);
  ShowDragLintHover('', AContent, Empty, AScreenX, AScreenY);
end;

procedure CloseDragLintHover;
begin
  if (GCurrentHover <> nil) and GCurrentHover.Visible then
    GCurrentHover.Close;
end;

function IsDragLintHoverVisible: Boolean;
begin
  Result := (GCurrentHover <> nil) and GCurrentHover.Visible;
end;

function IsMouseOverDragLintHover: Boolean;
{ v0.42: True when the cursor is within the visible hover popup (+ a small
  margin). Lets the dwell tracker close the popup when the mouse leaves the
  editor WITHOUT killing the interactive menu popup the user is reaching for. }
var
  Pt: TPoint;
  R:  TRect;
begin
  Result := False;
  if (GCurrentHover = nil) or not GCurrentHover.Visible then Exit;
  if not GetCursorPos(Pt) then Exit;
  R := GCurrentHover.BoundsRect;
  InflateRect(R, 12, 12);
  Result := PtInRect(R, Pt);
end;

initialization

finalization
  { v0.40.8d: belt and braces -- if Editor.UnregisterDragLintMenu didn't get
    to call CloseDragLintHover (e.g. an exception broke the teardown chain),
    yank the popup here before the BPL DCU unloads. Touching a half-freed
    form from the watch timer otherwise crashes the IDE. }
  try
    if GCurrentHover <> nil then
    begin
      GCurrentHover.Close;
      GCurrentHover := nil;
    end;
  except
  end;

end.
