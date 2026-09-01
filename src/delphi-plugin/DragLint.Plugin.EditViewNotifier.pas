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
  GOnFileFirstSeenHook: function(const AFile: string): Boolean = nil;

/// <summary>Forgets which files have already been asked for diagnostics, so the
/// next activation of each asks again.</summary>
/// <remarks>MUST be called whenever a NEW LSP server process is started. The
/// "already asked" set records a conversation with ONE server: diagnostics live
/// in that process and are gone when it dies, so a file marked asked against a
/// dead server would keep its stale gutter -- or, far more visibly, keep NO
/// gutter -- for the rest of the IDE session, because the set is consulted
/// before any request is made and never expires on its own.
///
/// Found 2026-09-01 from a live report: several engine rebuilds killed the
/// server, and afterwards a reopened unit showed no drag-lint marks at all
/// while the IDE's own W1002 hint sat in the same gutter. The plugin log named
/// the cause -- it published diagnostics for one unit, the server was replaced,
/// and no request was ever issued for the unit actually on screen.
///
/// This is the THIRD defect in this family. The first marked a file asked even
/// when the request never went out; the second did the same at IDE startup
/// before the server was up. Both were about recording an ask that did not
/// happen; this one is about not forgetting one that did. Main thread only.</remarks>
procedure DragLintForgetDiagnosticsAsked;

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
  , { per-severity gutter icons -- see that unit's header for why they are drawn
      with GDI rather than rasterised from the supplied SVGs }
    DragLint.Plugin.SeverityGlyph
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
  { Files already asked about FOR THE CURRENT SERVER. Keyed per FILE, not per
    view: the IDE fires EditorViewActivated on every focus change, and asking
    the engine again on each of them would put an LSP round-trip behind every
    Alt-Tab. Once per file is enough -- saving still refreshes, which is what
    keeps the marks honest after an edit.

    "FOR THE CURRENT SERVER" is the load-bearing part and was missing until
    2026-09-01: diagnostics live in the server process, so this set is only
    meaningful while that process is. DragLintForgetDiagnosticsAsked clears it
    on every respawn -- see its remarks. }
  GDiagAskedFor     : TStringList               = nil;

procedure DragLintForgetDiagnosticsAsked;
begin
  if GDiagAskedFor <> nil then GDiagAskedFor.Clear;
end;

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

{ ---- PaintLine instrumentation (2026-08-25) -------------------------------
  Why this exists, since a counter block in a paint handler needs justifying.

  The owner reported "no icons in the gutter", and it turned out to mean the
  gutter draws NOTHING. Three explanations fitted equally well from outside:
  PaintLine never runs; it runs and exits early; it runs and paints something
  illegible. The only signal in the log was ForceGutterRepaint's
  "gutterAnchor=0", and that is AMBIGUOUS -- GGutterAnchorHwnd comes from
  WindowFromDC, which returns 0 for the memory DC of a double-buffered paint,
  so 0 means "PaintLine never ran" OR "PaintLine ran normally". A number that
  cannot distinguish the two is not evidence, and the session spent on this one
  would have been minutes if it were.

  So: count what happened and say it. The constraint is that PaintLine fires
  once per visible line per repaint -- hundreds of times a second while
  scrolling -- and DLT opens, appends to and closes a file under a lock. One
  line per call would be a performance bug of its own. Hence counters plus a
  throttled flush: the first call reports immediately (so "it is running" shows
  up at once), then at most one summary every FlushMs, and only when something
  actually changed.

  All of it is inside try/except and never touches the Canvas. }
const
  PAINT_FLUSH_MS = 5000;

var
  GPaintCalls    : Cardinal = 0;
  GPaintDrawn    : Cardinal = 0;
  GPaintNoMarkers: Cardinal = 0;   { EnableInlineMarkers off }
  GPaintNoView   : Cardinal = 0;   { View or Buffer nil }
  GPaintNoPath   : Cardinal = 0;   { buffer has no filename }
  GPaintNoRows   : Cardinal = 0;   { cache had nothing for this line }
  GPaintAllSupp  : Cardinal = 0;   { rows existed, every one switched off }
  GPaintSeenErr  : Cardinal = 0;
  GPaintSeenWarn : Cardinal = 0;
  GPaintSeenInfo : Cardinal = 0;
  GPaintSeenHint : Cardinal = 0;
  { GetTickCount64, not GetTickCount: an IDE session outliving the 49.7-day wrap
    is unlikely but the 32-bit version has no upside here, and drag-lint's own
    gettickcount-wraparound rule fired on the first draft of this block. }
  GPaintLastFlush: UInt64 = 0;
  GPaintLastLine : string = '';

function OnOff(AValue: Boolean): string;
begin
  if AValue then Result:= 'on' else Result:= 'OFF';
end;

procedure PaintTelemetryFlush(const AFile: string; AForce: Boolean);
var
  Now : UInt64            ;
  Line: string            ;
  S   : TDragLintSettings ;
begin
  try
    Now:= GetTickCount64;
    if (not AForce) and (GPaintLastFlush <> 0) and (Now - GPaintLastFlush < PAINT_FLUSH_MS) then Exit;

    { THE FILTER STATE BELONGS ON THIS LINE. Without it, `allSuppressed=N` and
      `rows seen: info=23` are two facts a reader has to JOIN by hand against a
      registry key to reach the conclusion "info is switched off". With it, the
      line says so. Reading settings here is cheap: this flush is throttled to
      PAINT_FLUSH_MS, unlike PaintLine itself, which runs per visible line. }
    S:= LoadSettings;
    Line:= Format('calls=%d drawn=%d | filters: markers=%s E=%s W=%s H=%s I=%s | ' +
                  'exits: markersOff=%d noView=%d noPath=%d ' +
                  'noRows=%d allSuppressed=%d | rows seen: err=%d warn=%d info=%d hint=%d | file=%s',
                  [GPaintCalls, GPaintDrawn,
                   OnOff(S.EnableInlineMarkers), OnOff(S.ShowErrorsInline),
                   OnOff(S.ShowWarningsInline), OnOff(S.ShowHintsInline),
                   OnOff(S.ShowInfoInline),
                   GPaintNoMarkers, GPaintNoView, GPaintNoPath,
                   GPaintNoRows, GPaintAllSupp, GPaintSeenErr, GPaintSeenWarn,
                   GPaintSeenInfo, GPaintSeenHint, ExtractFileName(AFile)]);
    { Nothing changed since the last report -- stay quiet rather than filling the
      log with identical lines while the user reads a file without editing it. }
    if Line = GPaintLastLine then
    begin
      GPaintLastFlush:= Now;
      Exit;
    end;
    GPaintLastLine := Line;
    GPaintLastFlush:= Now;
    DLT('paint', Line);
  except
    { instrumentation must never disturb a paint }
  end;
end; // procedure

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
  Inc(GPaintCalls);
  { The very first call reports at once -- "PaintLine is running" is the single
    fact that was unobtainable before, and waiting 5 s for it helps nobody. }
  if GPaintCalls = 1 then PaintTelemetryFlush('', True);

  Settings:= LoadSettings;
  if not Settings.EnableInlineMarkers then
  begin
    Inc(GPaintNoMarkers);
    PaintTelemetryFlush('', False);
    Exit;
  end;
  if (View = nil) or (View.Buffer = nil) then
  begin
    Inc(GPaintNoView);
    PaintTelemetryFlush('', False);
    Exit;
  end;

  FilePath:= View.Buffer.FileName;
  if FilePath = '' then
  begin
    Inc(GPaintNoPath);
    PaintTelemetryFlush('', False);
    Exit;
  end;

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
  if Length(Diags) = 0 then
  begin
    { The overwhelmingly common case -- most lines have no finding -- so this is
      counted, never logged per call. It matters only in aggregate: "calls in the
      thousands, noRows equal to calls, rows seen all zero" is the signature of a
      cache nothing ever populated, which is what happened on 2026-08-24 when the
      rules-less Win32 engine published 0 findings over the real ones. }
    Inc(GPaintNoRows);
    PaintTelemetryFlush(FilePath, False);
    Exit;
  end;

  { Severity tally is per ROW, before the switches, so the log distinguishes
    "the cache is empty" from "the cache is full and every row is switched off". }
  for D in Diags do
    case D.Severity of
      dlsError  : Inc(GPaintSeenErr );
      dlsWarning: Inc(GPaintSeenWarn);
      dlsHint   : Inc(GPaintSeenHint);
      else        Inc(GPaintSeenInfo);
    end;

  { Most severe ENABLED row wins the glyph colour.

    Seeded from the first enabled row rather than from a constant. The previous
    seed was dlsHint, and TDragLintSeverity is declared (dlsError, dlsWarning,
    dlsHint, dlsInfo) -- so dlsInfo has the HIGHEST Ord, and an info-only line
    could never satisfy Ord(D.Severity) < Ord(MaxSev). It drew the HINT colour
    instead. Invisible today only because ShowInfoInline is off, and info is
    ~83% of all findings, so it would have mislabelled the majority of marks the
    moment that switch was turned on. Seeding from the data cannot go stale if
    the enum gains a member. }
  HasDiag:= False;
  MaxSev := dlsInfo;
  for D in Diags do
    if SevEnabled(D.Severity) then
    begin
      if (not HasDiag) or (Ord(D.Severity) < Ord(MaxSev)) then MaxSev:= D.Severity;
      HasDiag:= True;
    end;
  if not HasDiag then
  begin
    Inc(GPaintAllSupp);
    PaintTelemetryFlush(FilePath, False);
    Exit;
  end;

  Inc(GPaintDrawn);
  PaintTelemetryFlush(FilePath, False);

  Colors:= LoadEditorColors;

  SavedColor     := Canvas.Pen  .Color;
  SavedStyle     := Canvas.Pen  .Style;
  SavedWidth     := Canvas.Pen  .Width;
  SavedBrush     := Canvas.Brush.Color;
  SavedBrushStyle:= Canvas.Brush.Style;
  try
    { ---- Gutter glyph ----
      Until 2026-08-25 this was a filled severity-coloured SQUARE, chosen so as
      not to be confused with the IDE's round red breakpoint dot. It is now a
      per-severity ICON -- circle-X, warning triangle, circle-i, circle-check --
      because the owner asked for icons, and because a single square shape put
      the whole burden of "which severity is this?" on colour alone.

      The breakpoint-confusion concern the square was answering is still real,
      and is answered better than the square answered it: only ONE of the four
      glyphs is a plain circle silhouette, none is a plain red disc, and each
      carries an interior mark a breakpoint does not have.

      Geometry is unchanged -- side from the row height, capped by the gutter
      width and 16 px, so high-DPI still scales from GGutterLineHeight rather
      than from a hardcoded pixel count. }
    var RowH   : Integer:= LineRect.Bottom - LineRect.Top;
    var GutterW: Integer:= TextRect.Left   - LineRect.Left;
    var GlyphD: Integer:= RowH - 2                      ;
    if (GutterW > 4) and (GlyphD > GutterW - 2) then GlyphD:= GutterW - 2;
    if GlyphD > 16 then GlyphD:= 16;
    if GlyphD < 9 then GlyphD:= 9;
    var GX: Integer:= LineRect.Left + 1                   ;
    var GY: Integer:= LineRect.Top + (RowH - GlyphD) div 2;
    { GLYPH_USES_EDITOR_COLORS decides whose palette wins -- see the colour
      policy in DragLint.Plugin.SeverityGlyph's header. The wavy underline below
      keeps using the editor colours either way. }
    var GlyphFill: TColor;
    if GLYPH_USES_EDITOR_COLORS then GlyphFill:= SeverityColor(MaxSev, Colors)
    else GlyphFill:= SeverityGlyphColor(MaxSev);
    PaintSeverityGlyph(Canvas, Rect(GX, GY, GX + GlyphD, GY + GlyphD), MaxSev, GlyphFill);

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
      try
        { RECORD IT ONLY IF THE REQUEST WENT OUT. At IDE startup the first view
          is activated before the LSP child has finished starting, so the hook
          returns False -- and marking the file "asked" there would mean it was
          never asked again, which is exactly how the gutter stayed empty for a
          whole session. Leaving it unrecorded makes the next focus change
          retry, and by then the LSP is up. }
        if LoadSettings.AutoDiagnosticsOnSave then
        begin
          if GOnFileFirstSeenHook(FilePath) then GDiagAskedFor.Add(FilePath);
        end
        else GDiagAskedFor.Add(FilePath);   { switched off: do not keep asking }
      except
        { never let a diagnostics request break opening a file }
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
  { lineHeight and paintCalls are here because gutterAnchor ALONE is ambiguous:
    GGutterAnchorHwnd comes from WindowFromDC, which returns 0 for the memory DC
    of a double-buffered paint, so "gutterAnchor=0" reads identically whether
    PaintLine has never run or has just run normally. That ambiguity is what made
    the empty-gutter report expensive to diagnose. GGutterLineHeight is set
    unconditionally whenever PaintLine reaches the anchor block, so a 0 there is
    real evidence; paintCalls settles it outright. }
  DLT('gutter', Format('ForceGutterRepaint: editFormHwnd=%d gutterAnchor=%d lineHeight=%d paintCalls=%d',
      [H, GGutterAnchorHwnd, GGutterLineHeight, GPaintCalls]));
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
