unit DragLint.Plugin.EditViewNotifier;

interface

uses
  System.SysUtils
  , System.Classes
  , System.Generics.Collections
  , Winapi.Windows
  , Vcl.Graphics
  , Vcl.Forms
  , Vcl.Controls
  , Vcl.ExtCtrls
  , DockForm
  , ToolsAPI
  ;

procedure RegisterDragLintEditViewNotifier;
procedure UnregisterDragLintEditViewNotifier;
procedure InvokeInlineInfo;
{ v0.47: force the editor gutter (our PaintLine glyphs) to redraw NOW, even while
  the user is idle. Robust against double-buffered paints (where the per-paint DC
  has no window): repaints via the edit window's FORM handle + RDW_ALLCHILDREN. }
procedure ForceGutterRepaint;

var
  { v1.7: gutter marks used to appear ONLY after a save.

    Diagnostics were published in response to textDocument/didSave and nothing
    else, so opening a file and reading it produced no marks at all -- reported
    as "our gutter marks disappeared again" when in fact they had never been
    drawn that session. Confirmed from the plugin log: a session with 0 saves
    had 0 publishDiagnostics and 0 marks, while the previous session's single
    didSave was followed within a second by a publishDiagnostics.

    Reading code is the common case; saving is not. This hook lets the FIRST
    activation of each file ask for diagnostics too, over the same LSP
    round-trip the save path uses. Assigned by Editor.RegisterDragLintMenu, in
    the same place and for the same reason as SaveNotifier.GAfterSaveDiagHook:
    this unit must not depend on Editor. }
  GOnFileFirstSeenHook: procedure(const AFile: string) = nil;

var { v0.46: published by PaintLine so the hover tracker can map a screen point to
    an editor row for gutter-glyph hover. The buffer row (1-based) at client-Y y
    is  GGutterAnchorLine + floor((y - GGutterAnchorTopY) / GGutterLineHeight).
    GGutterAnchorHwnd is the edit-surface window (for ScreenToClient); a mouse X
    less than GGutterTextLeft is over the gutter, not the text. }
  GGutterAnchorHwnd: HWND    = 0   ;
  GGutterLineHeight: Integer = 0;
  GGutterAnchorLine: Integer = 0;
  GGutterAnchorTopY: Integer = 0;
  GGutterTextLeft  : Integer = 0;
  { v(hover-follows-mouse): the cell WIDTH, the horizontal twin of
    GGutterLineHeight. The IDE code editor is a fixed-pitch grid, so the 1-based
    buffer column at client-X x is 1 + (x - GGutterTextLeft) div GGutterCharWidth.
    Published so the hover tracker can resolve the symbol UNDER THE POINTER
    instead of the one under the caret -- see TDragLintHoverTracker's timer, where
    using the caret was making the popup describe a different token, and often a
    different FILE, from the one being pointed at. 0 means "not painted yet";
    callers must fall back to the caret rather than dividing by zero. }
  GGutterCharWidth : Integer = 0;

implementation

uses
  System.IOUtils
  , DragLint.Plugin.DiagnosticCache
  , DragLint.Plugin.CodeLensCache
  , DragLint.Plugin.RegistryColors
  , DragLint.Plugin.LiveDiagnostics
  , DragLint.Plugin.AutoComplete
  , DragLint.Plugin.HoverForm
  , { v0.47: dismiss the hover popup when the user types }
    DragLint.Plugin.GraphWindow
  , { v0.48: editor-sync -- graph follows the active unit }
    DragLint.Plugin.Telemetry
  , { v0.47: log the gutter repaint handle }
    DragLint.Plugin.Settings
  ;

{ ---- TDragLintEditViewNotifier -------------------------------------------- }

type
  TDragLintEditViewNotifier = class(TInterfacedObject, INTAEditViewNotifier)
    private
      FView : IOTAEditView;
      FIndex: Integer     ;
    public
      constructor Create(const AView: IOTAEditView);
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
        const LineText      : PAnsiChar         ; const TextWidth: Word;
        const LineAttributes: TOTAAttributeArray; const Canvas   : TCanvas;
        const TextRect: TRect; const LineRect: TRect; const CellSize: TSize);
  end;

  { v0.40: track every (view, index) we register so package unload can
  RemoveNotifier each one before the BPL's code segment is dropped. }
type
  TViewRegistration = record
    View : IOTAEditView;
    Index: Integer     ;
  end;

var
  GViewRegistrations: TList<TViewRegistration> = nil;
  GViewRegLock      : TObject                  = nil                 ;
  { Files already asked about this session. Keyed per FILE, not per view: the
    IDE fires EditorViewActivated on every focus change, and asking the engine
    again on each of them would put an LSP round-trip behind every Alt-Tab.
    Once per file is enough -- saving still refreshes, which is what keeps the
    marks honest after an edit. }
  GDiagAskedFor     : TStringList               = nil;

procedure UnregisterAllViewNotifiers;
var
  I  : Integer          ;
  Reg: TViewRegistration;
begin
  if (GViewRegistrations = nil) or (GViewRegLock = nil) then Exit;
  System.TMonitor.Enter(GViewRegLock);
  try
    for I:= GViewRegistrations.Count - 1 downto 0 do
    begin
      Reg:= GViewRegistrations[I];
      try
        if Reg.View <> nil then Reg.View.RemoveNotifier(Reg.Index);
      except
        { Swallow -- view may already be partially destroyed }
      end;
    end;
    GViewRegistrations.Clear;
  finally
    System.TMonitor.Exit(GViewRegLock);
  end;
end; // procedure

function ViewAlreadyHasNotifier(const AView: IOTAEditView): Boolean;
var
  I: Integer;
begin
  Result:= False;
  if (GViewRegistrations = nil) or (GViewRegLock = nil) then Exit;
  System.TMonitor.Enter(GViewRegLock);
  try
    for I:= 0 to GViewRegistrations.Count - 1 do
      if GViewRegistrations[I].View = AView then Exit(True);
  finally
    System.TMonitor.Exit(GViewRegLock);
  end;
end;

constructor TDragLintEditViewNotifier.Create(const AView: IOTAEditView);
var
  Reg: TViewRegistration;
begin
  inherited Create;
  FView:= AView;
  FIndex:= AView.AddNotifier(Self);
  if GViewRegistrations = nil then GViewRegistrations:= TList<TViewRegistration>.Create;
  Reg.View := AView;
  Reg.Index:= FIndex;
  System.TMonitor.Enter(GViewRegLock);
  try
    GViewRegistrations.Add(Reg);
  finally
    System.TMonitor.Exit(GViewRegLock);
  end;
end;

procedure TDragLintEditViewNotifier.AfterSave ; begin end;
procedure TDragLintEditViewNotifier.BeforeSave; begin end;
procedure TDragLintEditViewNotifier.Destroyed;
var
  I: Integer;
begin
  if (GViewRegistrations <> nil) and (GViewRegLock <> nil) then
  begin
    System.TMonitor.Enter(GViewRegLock);
    try
      for I:= GViewRegistrations.Count - 1 downto 0 do
        if GViewRegistrations[I].View = FView then
        begin
          GViewRegistrations.Delete(I);
          Break;
        end;
    finally
      System.TMonitor.Exit(GViewRegLock);
    end;
  end;
  FView:= nil;
  FIndex:= -1;
end; // procedure
procedure TDragLintEditViewNotifier.Modified;
begin
  { v0.42: an edit happened -> mark the live-diagnostics runner dirty (debounced).
    Guarded; never let a diagnostics path disturb the editor. }
  try NotifyEditDirty; except end;
  { v0.46: also nudge the auto-completion trigger (it debounces + only fires
    after a typed '.'). }
  try NotifyEditForAutoComplete; except end;
end;
procedure TDragLintEditViewNotifier.EditorIdle(const View: IOTAEditView); begin end;
procedure TDragLintEditViewNotifier.BeginPaint(const View: IOTAEditView; var FullRepaint: Boolean); begin end;
procedure TDragLintEditViewNotifier.EndPaint(const View: IOTAEditView); begin end;

function SeverityColor(ASev: TDragLintSeverity; const AC: TDragLintColors): TColor;
begin
  case ASev of
    dlsError  : Result:= AC.ErrorColor;
    dlsWarning: Result:= AC.WarningColor;
    dlsHint   : Result:= AC.HintColor;
    else Result:= AC.InfoColor;
  end;
end;

procedure TDragLintEditViewNotifier.PaintLine(const View: IOTAEditView;
  LineNumber: Integer; const LineText: PAnsiChar; const TextWidth: Word;
  const LineAttributes: TOTAAttributeArray; const Canvas: TCanvas;
  const TextRect: TRect; const LineRect: TRect; const CellSize: TSize);
var
  Settings       : TDragLintSettings          ;
  Colors         : TDragLintColors            ;
  FilePath       : string                     ;
  Diags          : TArray<TDragLintDiagnostic>;
  D              : TDragLintDiagnostic        ;
  MaxSev         : TDragLintSeverity          ;
  HasDiag        : Boolean                    ;
  StartX         : Integer                    ;
  EndX           : Integer                    ;
  BottomY        : Integer                    ;
  I              : Integer                    ;
  WaveY          : Integer                    ;
  WaveX          : Integer                    ;
  CY             : Integer                    ;
  SavedColor     : TColor                     ;
  SavedStyle     : TPenStyle                  ;
  SavedWidth     : Integer                    ;
  SavedBrush     : TColor                     ;
  SavedBrushStyle: TBrushStyle                ;
  CodeLensText   : string                     ;
  SavedFontColor : TColor                     ;
  SavedFontStyle : TFontStyles                ;

  function SevEnabled(S: TDragLintSeverity): Boolean;
  begin
    case S of
      dlsError  : Result:= Settings.ShowErrorsInline;
      dlsWarning: Result:= Settings.ShowWarningsInline;
      dlsHint   : Result:= Settings.ShowHintsInline;
      else Result:= Settings.ShowInfoInline;
    end;
  end;

begin
  Settings:= LoadSettings;
  if not Settings.EnableInlineMarkers then Exit;
  if View        = nil then Exit;
  if View.Buffer = nil then Exit;

  FilePath:= View.Buffer.FileName;
  if FilePath = '' then Exit;

  { v0.46: publish the row<->client-Y anchor for the hover tracker (gutter hover).
    Recorded for EVERY painted line so it stays fresh as the view scrolls. }
  if CellSize.CY > 0 then
  begin
    GGutterAnchorHwnd:= WindowFromDC(Canvas.Handle);
    GGutterLineHeight:= CellSize.CY;
    GGutterAnchorLine:= LineNumber; { 1-based buffer row }
    GGutterAnchorTopY:= LineRect.Top; { client Y of its top }
    GGutterTextLeft  := TextRect.Left; { client X where text begins }
    { v(hover-follows-mouse): the horizontal half of the same grid. Guarded
      separately from CY -- a zero here must leave the previous good value (or 0)
      alone rather than publishing a divisor the tracker would divide by. }
    if CellSize.CX > 0 then GGutterCharWidth:= CellSize.CX;
  end;

  { PaintLine LineNumber is 1-based; cache stores 0-based. }
  Diags:= Cache.GetForLine(FilePath, LineNumber - 1);
  if Length(Diags) = 0 then Exit;

  HasDiag:= False;
  MaxSev := dlsHint;
  for D in Diags do
    if SevEnabled(D.Severity) then
    begin
      HasDiag:= True;
      if Ord(D.Severity) < Ord(MaxSev) then MaxSev:= D.Severity;
    end;
  if not HasDiag then Exit;

  Colors:= LoadEditorColors;

  SavedColor     := Canvas.Pen  .Color;
  SavedStyle     := Canvas.Pen  .Style;
  SavedWidth     := Canvas.Pen  .Width;
  SavedBrush     := Canvas.Brush.Color;
  SavedBrushStyle:= Canvas.Brush.Style;
  try
    { ---- Gutter glyph (v0.47: filled SQUARE + outline) ----
      Deliberately square, not round: the IDE's own breakpoint glyph is a round
      red dot, so a round error glyph is easy to confuse with a breakpoint. A
      square clearly reads as "drag-lint diagnostic". Side = row height, capped
      by the gutter width and 16 px. }
    var RowH   : Integer:= LineRect.Bottom - LineRect.Top;
    var GutterW: Integer:= TextRect.Left   - LineRect.Left;
    var GlyphD: Integer:= RowH - 2                      ;
    if (GutterW > 4) and (GlyphD > GutterW - 2) then GlyphD:= GutterW - 2;
    if GlyphD > 16 then GlyphD:= 16;
    if GlyphD < 9 then GlyphD:= 9;
    var GX: Integer:= LineRect.Left + 1                   ;
    var GY: Integer:= LineRect.Top + (RowH - GlyphD) div 2;
    Canvas.Brush.Color:= SeverityColor(MaxSev, Colors);
    Canvas.Brush.Style:= bsSolid;
    Canvas.Pen  .Color:= clBlack; { outline for contrast on any gutter colour }
    Canvas.Pen  .Style:= psSolid;
    Canvas.Pen  .Width:= 1;
    Canvas.Rectangle(GX, GY, GX + GlyphD + 1, GY + GlyphD + 1);

    { ---- Wavy underline per diagnostic ---- }
    for I:= 0 to High(Diags) do
    begin
      D:= Diags[I];
      if not SevEnabled(D.Severity) then Continue;

      StartX:= TextRect.Left + D.StartCol * CellSize.cx;
      EndX  := TextRect.Left + D.EndCol   * CellSize.cx;
      if EndX > TextRect.Right then EndX:= TextRect.Right;
      if EndX <= StartX then EndX:= StartX + CellSize.cx;

      BottomY:= TextRect.Bottom - 1;
      Canvas.Pen.Color:= SeverityColor(D.Severity, Colors);
      Canvas.Pen.Style:= psSolid;
      Canvas.Pen.Width:= 1;

      WaveY:= BottomY;
      WaveX:= StartX;
      Canvas.MoveTo(WaveX, WaveY);
      while WaveX < EndX do
      begin
        Inc(WaveX, 2);
        if WaveX > EndX then WaveX:= EndX;
        { Flip between BottomY and BottomY-2 }
        if WaveY = BottomY then WaveY:= BottomY - 2
        else WaveY:= BottomY;
        Canvas.LineTo(WaveX, WaveY);
      end;
    end; // for
  finally
    Canvas.Pen  .Color:= SavedColor;
    Canvas.Pen  .Style:= SavedStyle;
    Canvas.Pen  .Width:= SavedWidth;
    Canvas.Brush.Color:= SavedBrush;
    Canvas.Brush.Style:= SavedBrushStyle;
  end; // try

  { ---- Code lens overlay ---- }
  if Settings.EnableCodeLens then
  begin
    CodeLensText:= CodeLensCache.GetForLine(FilePath, LineNumber - 1);
    if CodeLensText <> '' then
    begin
      SavedFontColor:= Canvas.Font.Color;
      SavedFontStyle:= Canvas.Font.Style;
      try
        Canvas.Font.Color:= $00808080; { dim grey }
        Canvas.Font.Style:= [fsItalic];
        Canvas.Brush.Style:= bsClear;
        Canvas.TextOut( TextRect.Left + TextWidth * CellSize.cx + 8, TextRect.Top, CodeLensText);
      finally
        Canvas.Font.Color:= SavedFontColor;
        Canvas.Font.Style:= SavedFontStyle;
      end;
    end;
  end; // if
end; // begin

{ ---- TDragLintEditServicesNotifier ---------------------------------------- }

type
  TDragLintEditServicesNotifier = class(TInterfacedObject, INTAEditServicesNotifier)
    public
      { IOTANotifier }
      procedure AfterSave;
      procedure BeforeSave;
      procedure Destroyed;
      procedure Modified;
      { INTAEditServicesNotifier }
      procedure WindowShow(const EditWindow: INTAEditWindow; Show, LoadedFromDesktop: Boolean);
      procedure WindowNotification(const EditWindow: INTAEditWindow; Operation: TOperation);
      procedure WindowActivated(const EditWindow: INTAEditWindow);
      procedure WindowCommand(const EditWindow: INTAEditWindow; Command, Param: Integer; var Handled: Boolean);
      procedure EditorViewActivated(const EditWindow: INTAEditWindow; const EditView: IOTAEditView);
      procedure EditorViewModified (const EditWindow: INTAEditWindow; const EditView: IOTAEditView);
      procedure DockFormVisibleChanged(const EditWindow: INTAEditWindow; DockForm: TDockableForm);
      procedure DockFormUpdated       (const EditWindow: INTAEditWindow; DockForm: TDockableForm);
      procedure DockFormRefresh       (const EditWindow: INTAEditWindow; DockForm: TDockableForm);
  end;

procedure TDragLintEditServicesNotifier.AfterSave ; begin end;
procedure TDragLintEditServicesNotifier.BeforeSave; begin end;
procedure TDragLintEditServicesNotifier.Destroyed ; begin end;
procedure TDragLintEditServicesNotifier.Modified  ; begin end;
procedure TDragLintEditServicesNotifier.WindowShow(const EditWindow: INTAEditWindow; Show, LoadedFromDesktop: Boolean); begin end;
procedure TDragLintEditServicesNotifier.WindowNotification( const EditWindow: INTAEditWindow; Operation: TOperation); begin end;
procedure TDragLintEditServicesNotifier.WindowActivated( const EditWindow: INTAEditWindow); begin end;
procedure TDragLintEditServicesNotifier.WindowCommand(const EditWindow: INTAEditWindow; Command, Param: Integer; var Handled: Boolean); begin end;
procedure TDragLintEditServicesNotifier.EditorViewModified( const EditWindow: INTAEditWindow; const EditView: IOTAEditView);
begin
  { v0.47: per-edit modify notification. The per-VIEW IOTANotifier.Modified only
    fires on the clean->dirty TRANSITION (once per save-cycle), so continued
    editing never re-triggered the live runner and diagnostics went stale after
    the first keystroke. This services-level callback fires on each modification.
    Guarded; a diagnostics path must never disturb the editor. }
  try NotifyEditDirty; except end;
  try NotifyEditForAutoComplete; except end;
  { v0.47: the user resumed typing -> they are not reading the hover popup, so
    dismiss it immediately (it never held focus, so it cannot eat the keystroke). }
  try CloseDragLintHover; except end;
end;
procedure TDragLintEditServicesNotifier.DockFormVisibleChanged( const EditWindow: INTAEditWindow; DockForm: TDockableForm); begin end;
procedure TDragLintEditServicesNotifier.DockFormUpdated       ( const EditWindow: INTAEditWindow; DockForm: TDockableForm); begin end;
procedure TDragLintEditServicesNotifier.DockFormRefresh       ( const EditWindow: INTAEditWindow; DockForm: TDockableForm); begin end;

procedure TDragLintEditServicesNotifier.EditorViewActivated( const EditWindow: INTAEditWindow; const EditView: IOTAEditView);
var
  S       : TDragLintSettings;
  FilePath: string           ;
  DbPath  : string           ;
begin
  if EditView = nil then Exit;
  { v0.40: constructor now does AddNotifier + dedups via GViewRegistrations.
    The IDE fires EditorViewActivated every focus change; without dedup we
    accumulate notifiers per view and BeginPaint AVs once any one is freed. }
  if not ViewAlreadyHasNotifier(EditView) then TDragLintEditViewNotifier.Create(EditView);
  { Populate code lens cache for this file (synchronous; fast for small files) }
  if EditView.Buffer = nil then Exit;
  FilePath:= EditView.Buffer.FileName;
  if FilePath = '' then Exit;

  { v1.7: ask for diagnostics the FIRST time this file is activated, so a file
    that is only READ still gets its gutter marks. See GOnFileFirstSeenHook.
    Gated on the same preference as the save path -- one "run diagnostics
    automatically" switch, not two. Failure is silent by design: the hook skips
    when the LSP is not up, exactly as TriggerDiagnosticsOnSave does, so
    opening a file is never blocked by a slow engine. }
  if Assigned(GOnFileFirstSeenHook) and SameText(ExtractFileExt(FilePath), '.pas') then
  begin
    if GDiagAskedFor = nil then
    begin
      GDiagAskedFor:= TStringList.Create;
      GDiagAskedFor.Sorted    := True;
      GDiagAskedFor.Duplicates:= dupIgnore;
      GDiagAskedFor.CaseSensitive:= False;
    end;
    if GDiagAskedFor.IndexOf(FilePath) < 0 then
    begin
      GDiagAskedFor.Add(FilePath);
      try
        if LoadSettings.AutoDiagnosticsOnSave then GOnFileFirstSeenHook(FilePath);
      except
        { never let a diagnostics request break opening a file }
      end;
    end;
  end;

  { v0.48: editor-sync -- let the graph viewer follow the active unit. Guarded;
    no-op unless the graph window is open + embedded. Pascal source units only. }
  try
    var Ext: string:= LowerCase(ExtractFileExt(FilePath));
    if (Ext = '.pas') or (Ext = '.dpr') or (Ext = '.dpk') then DragLintGraphNotifyActiveUnit(ChangeFileExt(ExtractFileName(FilePath), ''));
  except
  end;

  S:= LoadSettings;
  if not S.EnableCodeLens then Exit;
  { v(project-drag-lint-home): <projname> is not known here (only a .pas file,
    not its owning .dproj), so fall back to the containing directory's own
    name -- the common convention (e.g. YADF\YADF.dproj) that FindAncestorDb
    already relies on for the same reason. }
  var ProjDir : string:= TPath.GetDirectoryName(FilePath);
  var ProjName: string:= ExtractFileName(ExcludeTrailingPathDelimiter(ProjDir));
  DbPath:= ResolveDbPath(S.DbPathTemplate, ProjDir, ProjName);
  CodeLensCache.PopulateOnce(FilePath, S.ExePath, DbPath);
end; // procedure

procedure ForceGutterRepaint;
var
  ESS : IOTAEditorServices;
  View: IOTAEditView      ;
  Win : INTAEditWindow    ;
  H   : HWND              ;
begin
  if not Supports(BorlandIDEServices, IOTAEditorServices, ESS) then Exit;
  View:= ESS.TopView;
  if View = nil then Exit;
  { re-run our PaintLine via the IDE's own repaint (draws into its buffer) }
  try View.Paint; except end;
  { then force the edit window + ALL children (text + gutter) to repaint NOW.
    Use the edit window FORM handle -- always valid. GGutterAnchorHwnd (from
    WindowFromDC during paint) can be 0 when the IDE double-buffers, which is
    why the earlier InvalidateRect approach silently did nothing. }
  H:= 0;
  try
    Win:= View.GetEditWindow;
    if (Win <> nil) and (Win.Form <> nil) then H:= Win.Form.Handle;
  except
  end;
  if (H = 0) and (GGutterAnchorHwnd <> 0) then H:= GGutterAnchorHwnd;
  DLT('gutter', Format('ForceGutterRepaint: editFormHwnd=%d gutterAnchor=%d', [H, GGutterAnchorHwnd]));
  if (H <> 0) and IsWindow(H) then
  try
    RedrawWindow(H, nil, 0, RDW_INVALIDATE or RDW_UPDATENOW or RDW_ALLCHILDREN or RDW_ERASE);
  except
  end;
end; // procedure

{ ---- Register / Unregister ------------------------------------------------ }

var
  GESNotifierIdx: Integer = -1;

procedure RegisterDragLintEditViewNotifier;
var
  ESS: IOTAEditorServices80;
begin
  if GESNotifierIdx >= 0 then Exit;
  if not Supports(BorlandIDEServices, IOTAEditorServices80, ESS) then Exit;
  GESNotifierIdx:= ESS.AddNotifier( TDragLintEditServicesNotifier.Create);
end;

procedure UnregisterDragLintEditViewNotifier;
var
  ESS: IOTAEditorServices80;
begin
  { v0.40: remove every per-view notifier first; otherwise the IDE keeps
    holding interface pointers into our soon-to-be-unloaded BPL and AVs
    on next paint / shutdown. }
  UnregisterAllViewNotifiers;
  if GESNotifierIdx < 0 then Exit;
  if Supports(BorlandIDEServices, IOTAEditorServices80, ESS) then ESS.RemoveNotifier(GESNotifierIdx);
  GESNotifierIdx:= -1;
end;

{ ---- InvokeInlineInfo (Ctrl+Alt+I) ---------------------------------------- }
{ v0.40: previously used Sleep(4000) inside the active call, which froze the
  UI thread for 4 seconds. Now we keep a singleton hint window + TTimer; the
  timer fires once, closes the hint, and disables itself. Re-invoking before
  the timer fires simply restarts it (and reuses the window). }

var
  GHintWindow: THintWindow = nil;
  GHintTimer : TTimer      = nil     ;

type
  TInlineHintHelper = class
    public
      class procedure OnHintTimer(Sender: TObject);
  end;

  class procedure TInlineHintHelper.OnHintTimer(Sender: TObject);
begin
  if GHintTimer <> nil then GHintTimer.Enabled:= False;
  if GHintWindow <> nil then FreeAndNil(GHintWindow);
end;

procedure InvokeInlineInfo;
var
  ESS     : IOTAEditorServices         ;
  View    : IOTAEditView               ;
  FilePath: string                     ;
  CurLine : Integer                    ;
  Diags   : TArray<TDragLintDiagnostic>;
  D       : TDragLintDiagnostic        ;
  Msg     : string                     ;
  SB      : TStringBuilder             ;
  P       : TPoint                     ;
  R       : TRect                      ;
begin
  if not Supports(BorlandIDEServices, IOTAEditorServices, ESS) then Exit;
  View:= ESS.TopView;
  if View        = nil then Exit;
  if View.Buffer = nil then Exit;

  FilePath:= View.Buffer.FileName;
  if FilePath = '' then Exit;

  { Position.Row is 1-based; cache is 0-based }
  CurLine:= View.Position.Row - 1;
  if CurLine < 0 then CurLine:= 0;

  Diags:= Cache.GetForLine(FilePath, CurLine);
  if Length(Diags) = 0 then
  begin
    { No diagnostics on this line - silently ignore }
    Exit;
  end;

  SB:= TStringBuilder.Create;
  try
    for D in Diags do
    begin
      if SB.Length > 0 then SB.Append(#13#10);
      case D.Severity of
        dlsError  : SB.Append('[E] ');
        dlsWarning: SB.Append('[W] ');
        dlsHint   : SB.Append('[H] ');
        else SB.Append('[I] ');
      end;
      if D.Code <> '' then
      begin
        SB.Append(D.Code);
        SB.Append(': ');
      end;
      SB.Append(D.Message);
    end; // for
    Msg:= SB.ToString;
  finally
    SB.Free;
  end; // try

  GetCursorPos(P);

  { Tear down a previous hint if it's still up }
  if GHintWindow <> nil then FreeAndNil(GHintWindow);

  if GHintTimer = nil then
  begin
    GHintTimer:= TTimer.Create(nil);
    GHintTimer.Interval:= 4000;
    GHintTimer.OnTimer:= TInlineHintHelper.OnHintTimer;
    GHintTimer.Enabled:= False;
  end;

  GHintWindow:= THintWindow.Create(nil);
  R:= GHintWindow.CalcHintRect(400, Msg, nil);
  OffsetRect(R, P.X + 16, P.Y + 16);
  GHintWindow.ActivateHint(R, Msg);

  { (Re)start the auto-close timer without blocking the IDE thread }
  GHintTimer.Enabled:= False;
  GHintTimer.Enabled:= True;
end; // procedure

initialization
GViewRegLock:= TObject.Create;

finalization
{ v0.40: drop our hint window + timer first so the IDE doesn't try to
    paint into objects we've freed }
if GHintTimer  <> nil then FreeAndNil(GHintTimer );
if GHintWindow <> nil then FreeAndNil(GHintWindow);
{ Then remove every per-view notifier (the BPL is about to be unloaded) }
UnregisterAllViewNotifiers;
if GViewRegistrations <> nil then FreeAndNil(GViewRegistrations);
if GViewRegLock       <> nil then FreeAndNil(GViewRegLock      );

end.
