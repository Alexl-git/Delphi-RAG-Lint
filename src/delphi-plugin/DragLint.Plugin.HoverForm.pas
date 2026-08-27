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
  System.SysUtils
  , System.Classes
  , Vcl.Forms
  , Vcl.Controls
  , Vcl.StdCtrls
  , Vcl.ExtCtrls
  , Vcl.Graphics
  , Vcl.ComCtrls
  , Winapi.Windows
  , Winapi.Messages
  , Winapi.RichEdit
  , ToolsAPI
  , ToolsAPI.Editor
  , DragLint.Plugin.SyntaxColors  { the palette, shared with the completion popup }
  ;

type
  TDragLintCallerInfo = record
    FilePath: string ;
    Line    : Integer;
    CodeText: string ;
  end;

  /// <summary>One parsed parameter for the structured hover model: the leading
  /// const/var/out modifier (if any), the parameter name, and its type text.
  /// Populated by the Editor from the `hover --json` payload (Task 8).</summary>
  TDragLintHoverParam = record
    Modifier: string;
    Name    : string;
    TypeText: string;
  end;

  /// <summary>The structured hover payload the Help-Insight body renders:
  /// the qualified name + one-line signature, the declaring unit + 1-based
  /// definition line (for click-navigation), the parsed parameter list, the
  /// return type, and the mined `Result:=`/`Exit()` return expressions plus an
  /// overflow count. The Editor builds this from `hover --qname X --json`
  /// (Task 8); the form never re-parses a flat string.</summary>
  TDragLintHoverModel = record
    QualifiedName: string                    ;
    Kind         : string                    ;   // FB #3: friendly qualifier (function/local var/property/...) shown before the name
    RawSignature : string                    ;   // enum-value ordinal etc. straight from the CLI (Signature below is the RECONSTRUCTED display line)
    Signature    : string                    ;
    UnitFile     : string                    ;
    DefLine      : Integer                   ;
    Params       : TArray<TDragLintHoverParam>;
    ReturnType   : string                    ;
    Returns      : TArray<string>            ;
    ReturnLines  : TArray<Integer>           ;   // FB3: parallel to Returns -- abs source line of each (0 = unknown), for click-to-jump
    ReturnsMore  : Integer                   ;
    { v(hover facts fix): the Phase-2 analysis fact lines (Complexity / Reads /
      Writes / SQL / Handles / Owns returned / Covered by) from `hover --json`'s
      new "facts" array. Rendered as a FACTS section by RenderModel. }
    Facts        : TArray<string>            ;
    { v(hover-both): lint / compiler findings that apply to the hovered LINE.
      Kept on the MODEL rather than passed alongside it because the structured
      and string popups were two exclusive branches, and the structured one
      simply dropped the diagnostic: hovering a symbol on a line that had a
      finding showed either the signature or the finding, never both. The user
      asked for both, and the signature is the half that must never be lost. }
    Diagnostics  : TArray<string>            ;
  end;

  /// <summary>Logical syntax roles the hover body colors. Each maps to a real
  /// IDE editor color (Tools > Options > Editor) when available, falling back
  /// to the fixed CL_* palette otherwise; every color still passes through the
  /// WCAG contrast guard against the actual popup background.</summary>
  { MOVED to DragLint.Plugin.SyntaxColors so the completion popup can render in
    the same palette. Aliased here so existing references keep compiling. }
  TDLSynRole = DragLint.Plugin.SyntaxColors.TDLSynRole;

  TDragLintHoverForm = class(TForm)
    private
      FBody       : TRichEdit  ;
      FCallers    : TListView  ;
      FCallerPaths: TStringList;
      FWatchTimer : TTimer     ;
      FAnchor     : TPoint     ;
      FShowTickMs : Cardinal   ;
      { v0.94: structured-render state. FModelQName/FModelDefLine capture the
      header line's navigation target so a click on line 0 opens the definition;
      FSynOpts caches the IDE editor-color interface for the duration of one
      RenderModel call (resolved once, not per Emit -- see GetSyntaxColor).
      FStructured marks a model-rendered popup so the click/mouse-move handlers
      use the header-line rule instead of the legacy definition-row parsing. }
      FModelQName  : string                ;
      FModelDefLine: Integer               ;
      FSynOpts     : INTACodeEditorOptions ;
      FStructured  : Boolean               ;
      { FB3: parallel to the model's Returns/ReturnLines, kept so a click on a
        "Result := <expr>" body line can jump to that return's source line. }
      FReturnExprs : TArray<string>        ;
      FReturnLines : TArray<Integer>       ;
      { v0.42: dwell popups dismiss tightly -- the moment the cursor leaves a
      small box around the ORIGINAL dwell point (where the user was pointing),
      not the whole 900 px popup rect. This stops the popup lingering over the
      Projects/Messages pane and also clears it when the mouse leaves the
      editor (that motion necessarily exits the anchor box). Menu-invoked
      popups keep the generous popup-rect dismissal so they stay interactive. }
      FAnchorDismiss: Boolean;
      FDwellAnchor  : TPoint ;
      { v(hover-resize): True for the duration of a user resize drag (between
        WM_ENTERSIZEMOVE and WM_EXITSIZEMOVE). HandleWatchTick is the sole
        automatic dismissal (OnDeactivate has been a no-op since v0.40.8), and
        it closes on "cursor outside the popup rect" -- which a sizing drag can
        satisfy while the rect is being dragged smaller. Suppress that tick
        while set, so grabbing an edge cannot make the popup vanish. }
      FSizing: Boolean;
      { v(hover-title): the signature line is the popup's TITLE BAND now, not body
        line 0 -- a separate one-line TRichEdit docked alTop, with a hairline
        separator under it, matching the way the IDE's own Code Insight popup puts
        the declaration in a caption above the detail. It is still the click target
        that navigates to the definition (HandleTitleClick). Keeping it a TRichEdit
        rather than a TLabel is what preserves the per-token syntax colouring --
        EmitSignatureHeader writes coloured runs, which a TLabel cannot show.
        Moving it out of the body also takes the WIDEST line out of the body, which
        is what used to force the horizontal scrollbar and, through it, the vertical
        one (see ShowAt's h-scrollbar reservation). }
      FTitle    : TRichEdit;
      FTitleSep : TBevel   ;
      { Emit target for the current run: FTitle while the header is being written,
        FBody for everything after. Never nil in practice -- Emit falls back to
        FBody defensively. }
      FEmitTarget: TRichEdit;
      procedure HandleTitleClick(Sender: TObject);
      procedure HandleKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
      procedure HandleDeactivate    (Sender: TObject);
      procedure HandleTimerTick     (Sender: TObject);
      procedure HandleWatchTick     (Sender: TObject);
      procedure HandleCallerDblClick(Sender: TObject);
      procedure HandleCallerKey(Sender: TObject; var Key: Word; Shift: TShiftState);
      procedure HandleMemoClick(Sender: TObject);
      procedure HandleMemoMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
      function LineIsClickable(const ALineText: string): Boolean;
      { FB3: if ALineText is a rendered "Result := <expr>" return line whose expr
        matches a mined return, its absolute source line; 0 otherwise. }
      function ReturnLineForBodyLine(const ALineText: string): Integer;
      { v0.94: colored + selectable Help-Insight body (TRichEdit). }
      procedure Emit(const AText: string; AColor: TColor; ABold: Boolean);
      function  GetSyntaxColor(ARole: TDLSynRole): TColor;
      procedure EmitSignatureHeader(const ASignature, AUnitFile: string; ADefLine: Integer);
      procedure RenderModel(const AModel: TDragLintHoverModel; ACallerCount: Integer);
      { v0.94: shared final placement + no-steal-focus show, used by BOTH ShowAt
      overloads so the focus/dwell mechanics can never drift between them. }
      procedure PlaceAndShow(X, Y, W, H: Integer);
      /// <summary>Widest of ALines rendered in the body font, in pixels.</summary>
      /// <param name="ALines">Logical (unwrapped) lines the body will show.</param>
      /// <returns>Pixel width of the widest line; 0 when ALines is empty.</returns>
      /// <remarks>Replaces a fixed ~7.6 px-per-character estimate, which is only
      /// right for a monospaced font at one size: it over-measured narrow text
      /// (needless whitespace) and under-measured wide text (the message wrapped
      /// when it did not need to). Bold is measured explicitly because the
      /// signature header -- usually the widest line -- is drawn bold.</remarks>
      function MeasureTextWidth(const ALines: array of string; ABold: Boolean): Integer;
      /// <summary>Usable width for a popup shown at screen point (AX, AY): the
      /// work area of the monitor it lands on, less a small margin.</summary>
      function MaxPopupWidthAt(AX, AY: Integer): Integer;
    protected
      { v(hover-resize): the popup is BorderStyle=bsNone by design (a bare info
        panel, no caption). A borderless window gets no sizing border from
        Windows, so resizing needs two things: WS_THICKFRAME added in
        CreateParams (gives DefWindowProc a sizing loop to run) and a hit-test
        that reports the edges as sizing zones. The frame stays invisible
        because there is still no caption and no border style to paint. }
      procedure WMNCHitTest    (var Msg: TWMNCHitTest); message WM_NCHITTEST;
      procedure WMEnterSizeMove(var Msg: TMessage    ); message WM_ENTERSIZEMOVE;
      procedure WMExitSizeMove (var Msg: TMessage    ); message WM_EXITSIZEMOVE;
      procedure DoClose(var Action: TCloseAction); override;
      { v0.47: WS_EX_NOACTIVATE -- show as an info popup that NEVER steals keyboard
      focus, so the user can keep typing in the editor. Mouse clicks on the
      clickable rows still work (mouse activation is independent). }
      procedure CreateParams(var Params: TCreateParams); override;
    public
      constructor Create(AOwner: TComponent); override;
      procedure ShowAt(X, Y: Integer; const AHeader, ASummary: string; const ACallers: TArray<TDragLintCallerInfo>; AAnchorDismiss: Boolean; AAnchorX, AAnchorY: Integer); overload;
      /// <summary>Structured (Help-Insight) show: renders the colored, selectable
      /// signature header + Parameters + Returns from AModel into the TRichEdit
      /// body, and the callers into the ListView. The header line click-navigates
      /// to AModel.DefLine. Reuses the exact same no-steal-focus placement and
      /// dwell/menu dismissal as the string overload.</summary>
      /// <param name="AModel">The structured hover payload (Task 8 builds it).</param>
      procedure ShowAt(X, Y: Integer; const AModel: TDragLintHoverModel; const ACallers: TArray<TDragLintCallerInfo>; AAnchorDismiss: Boolean; AAnchorX, AAnchorY: Integer); overload;
  end;

procedure ShowDragLintHover(
  const AHeader, ASummary: string; const ACallers: TArray<TDragLintCallerInfo>; AScreenX,
  AScreenY: Integer; AAnchorDismiss: Boolean = False; AAnchorX: Integer = -1; AAnchorY: Integer = -1); overload;
procedure ShowDragLintHover(const AContent: string; AScreenX, AScreenY: Integer); overload;
/// <summary>Structured factory: shows a Help-Insight hover for AModel (colored
/// signature + params + returns) with ACallers in the grid. No-ops while a
/// hover is already visible (singleton), like the string overloads.</summary>
procedure ShowDragLintHover(
  const AModel: TDragLintHoverModel; const ACallers: TArray<TDragLintCallerInfo>; AScreenX,
  AScreenY: Integer; AAnchorDismiss: Boolean = False; AAnchorX: Integer = -1; AAnchorY: Integer = -1); overload;
procedure CloseDragLintHover;
function IsDragLintHoverVisible  : Boolean;
function IsMouseOverDragLintHover: Boolean;
procedure OpenSourceAt(const AFile: string; ALine: Integer);

var { v0.46: set by the Editor at startup. When the user clicks a popup line that
    reads "... add unit X to the uses clause", the hover calls this with X to
    insert the unit (the lightbulb quick-fix from the diagnostic popup). }
  GOnAddUnit: TProc<string> = nil;
  { v0.46.x: set by the Editor. When the user clicks a definition row, the hover
    calls this with the def's QUALIFIED NAME + line; the Editor resolves it to an
    ABSOLUTE source path via the index (the query JSON now carries "file") and
    opens the .pas there. The popup keeps its display clean -- the path is
    resolved on click, never shown. }
  GOnNavigateToQname: TProc<string, Integer> = nil;

implementation

uses
  System.StrUtils           // IsWordChar-style checks in the header tokenizer
  , System.Math             // Max
  , Vcl.Themes              // StyleServices / TStyleManager (themed bg for opted-out controls)
  , DRagLint.Hover.Contrast // EnsureReadable (T1)
  , DragLint.Plugin.Fonts   // GetIdeEditorFont (T5)
  , DragLint.Plugin.Theme   // session 27: shared IDE theming (was duplicated here)
  ;

var
  GCurrentHover: TDragLintHoverForm = nil;

const
  { v0.94 fixed fallback palette (light-theme base). Used per-token when the IDE
    editor colors are unavailable. Every value is still run through the contrast
    guard against the actual background before it is emitted. TColor is BGR, so
    these bytes are the reverse of the #RRGGBB the comments name. }
  { The CL_* fallback palette MOVED to DragLint.Plugin.SyntaxColors -- two
    copies of one palette is a drift channel, and the completion popup needed
    the same values. }

  { Delphi reserved words we color as keywords in the one-line signature. Lower-
    case; the tokenizer compares case-insensitively. Kept tight to what appears
    in a routine signature (function/procedure headers + param modifiers). }
  KEYWORDS: array[0..12] of string = (
    'function', 'procedure', 'constructor', 'destructor', 'const', 'var',
    'out', 'array', 'of', 'string', 'set', 'record', 'class');

procedure OpenSourceAt(const AFile: string; ALine: Integer);
var
  ActSvc: IOTAActionServices;
  EdSvc : IOTAEditorServices;
  View  : IOTAEditView      ;
  MS    : IOTAModuleServices;
  Module: IOTAModule        ;
  Editor: IOTAEditor        ;
  Src   : IOTASourceEditor  ;
  i     : Integer           ;
  SrcFound: Boolean         ;
begin
  { v0.46.x: never feed OpenFile a non-absolute path -- a bare unit filename
    ("Foo.pas") resolves against the IDE working dir (...\bin) and raises
    "Cannot create file". Require a rooted path. }
  if (AFile = '') or (ExtractFileDrive(AFile) = '') then Exit;
  { v0.46.x: for a FORM unit, IOTAActionServices.OpenFile can surface the form
    designer/DFM view instead of the .pas source. Force the IOTASourceEditor
    (code view) explicitly; fall back to OpenFile only if that fails. }
  SrcFound:= False;
  if Supports(BorlandIDEServices, IOTAModuleServices, MS) then
  begin
    Module:= MS.OpenModule(AFile);
    if Module <> nil then
    begin
      for i:= 0 to Module.GetModuleFileCount - 1 do
      begin
        Editor:= Module.GetModuleFileEditor(i);
        if Supports(Editor, IOTASourceEditor, Src) then
        begin
          Src.Show; { forces the .pas code view, not the form designer }
          SrcFound:= True;
          Break;
        end;
      end;
    end;
  end;
  if not SrcFound then
  begin
    if not Supports(BorlandIDEServices, IOTAActionServices, ActSvc) then Exit;
    ActSvc.OpenFile(AFile);
  end;
  if Supports(BorlandIDEServices, IOTAEditorServices, EdSvc) then
  begin
    View:= EdSvc.TopView;
    if (View <> nil) and (ALine > 0) then
    begin
      View.Position.GotoLine(ALine);
      View.Paint;
    end;
  end;
end;

/// <summary>How many caller rows to display: all when total &lt;= 15, else 10.</summary>
/// <returns>Row count to render; caller adds a "NN more" trailer when it is &lt; total.</returns>
function DisplayedCallerCount(ATotal: Integer): Integer;
begin
  if ATotal <= 15 then Result:= ATotal else Result:= 10;
end;

{ ---- IDE theme follow (v0.46) ---- }

procedure ApplyIdeTheme(AForm: TCustomForm);
{ v0.46 made the popup follow the IDE's light/dark theme. Session 27 moved the
  implementation into DragLint.Plugin.Theme so the About window uses the SAME
  code rather than a second copy -- see that unit's header for the
  IOTAIDEThemingServices-vs-global-StyleServices trap this originally uncovered.
  Kept as a local wrapper so the call sites below are unchanged. }
begin
  DragLint.Plugin.Theme.ApplyIdeTheme(AForm, TDragLintHoverForm);
end;

function ThemedColor(ASystemColor: TColor): TColor;
{ Shared with the About window -- see DragLint.Plugin.Theme.

  Still needed here because FBody (TRichEdit) and FCallers (TListView) set
  StyleElements:=[] so our per-token syntax colors survive style-hooking, which
  also opts them out of the themed BACKGROUND: without this they paint on a
  hardcoded clWindow (white) under a DARK IDE theme. }
begin
  Result:= DragLint.Plugin.Theme.ThemedColor(ASystemColor);
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
    v0.94.1: BORDERLESS (bsNone) like Delphi's Code Insight popup -- no OS title
    bar. The colored signature line (body line 0) IS the header now, so a
    "drag-lint" title bar was redundant chrome. A thin 1px border is drawn in
    CreateParams (WS_BORDER) so the popup still reads as a distinct window. }
  Caption    := 'drag-lint';
  BorderStyle:= bsNone;
  FormStyle  := fsStayOnTop;
  Color      := clWindow;
  KeyPreview := True;
  Position   := poDesigned;

  OnKeyDown:= HandleKeyDown;

  { v0.40.8e: top header label removed -- the title bar shows the same
    "drag-lint -- kind name -- unit.pas (line)" string and a duplicate
    inside the body is just visual noise. }

  { Top: the TITLE BAND -- one line, the coloured signature + its unit/line
    locator. Created FIRST so it docks at the very top; the hairline separator
    docks immediately under it, then the callers grid takes the bottom and the
    body fills what is left. ScrollBars is deliberately ssNone: the band is
    exactly one line tall and must never grow a scrollbar of its own; a signature
    wider than the popup is simply clipped, and the popup is resizable. }
  FTitle:= TRichEdit.Create(Self);
  FTitle.Parent        := Self;
  FTitle.Align         := alTop;
  FTitle.BorderStyle   := bsNone;
  FTitle.ReadOnly      := True;
  FTitle.WordWrap      := False;
  FTitle.ScrollBars    := ssNone;
  FTitle.TabStop       := False;
  FTitle.StyleElements := [];   { same reason as FBody -- keep our syntax colours }
  FTitle.Color         := clWindow;
  FTitle.Cursor        := crHandPoint; { the whole band navigates to the definition }
  FTitle.OnClick       := HandleTitleClick;

  FTitleSep:= TBevel.Create(Self);
  FTitleSep.Parent := Self;
  FTitleSep.Align  := alTop;
  FTitleSep.Height := 2;
  FTitleSep.Shape  := bsTopLine;

  { Bottom: callers ListView. Created BEFORE memo so alClient memo fills middle. }
  FCallers:= TListView.Create(Self);
  FCallers.Parent           := Self;
  FCallers.Align            := alBottom;
  FCallers.Height           := 130;
  FCallers.ViewStyle        := vsReport;
  FCallers.RowSelect        := True;
  FCallers.ReadOnly         := True;
  FCallers.GridLines        := False;
  { v0.94.1: the grey OS column-header row is HIDDEN. The "CALLED FROM (N)" label
    is now a blue bold section line at the bottom of the body (RenderModel),
    matching PARAMETERS/RETURNS -- guaranteed bold+blue in every theme, unlike a
    themed ListView header which ignores custom-draw font/color. }
  FCallers.ShowColumnHeaders:= False;
  FCallers.HideSelection    := False;
  { v0.94.1: opt the grid out of VCL/DevExpress style-hooking (same reason as
    FBody) so it renders on the light window surface like the body -- not the
    theme's dark grid -- and reads as one popup. }
  FCallers.StyleElements:= [];
  FCallers.Color        := clWindow;
  { Columns: Unit / Line / Code. Headers are hidden (label lives in the body), so
    these captions are never shown -- only the widths matter for column layout. }
  with FCallers.Columns.Add do begin Caption:= 'Unit'; Width:= 260; end;
  with FCallers.Columns.Add do begin Caption:= 'Line'; Width:= 55 ; end;
  with FCallers.Columns.Add do begin Caption:= 'Code'; Width:= 620; end;
  FCallers.OnDblClick:= HandleCallerDblClick;
  FCallers.OnKeyDown := HandleCallerKey;
  FCallers.Cursor    := crHandPoint; { every row navigates -> hand cursor }

  { Middle: colored + SELECTABLE Help-Insight body (v0.94: TRichEdit, was a
    plain TMemo). ReadOnly with no border and a vertical scrollbar; runs are
    written by Emit with per-token IDE colors. Click on the header line (0)
    navigates to the definition (see HandleMemoClick). }
  FBody:= TRichEdit.Create(Self);
  FBody.Parent     := Self;
  FBody.Align      := alClient;
  FBody.BorderStyle:= bsNone;
  FBody.ReadOnly   := True;
  { v0.94.1: no word-wrap so the signature header stays on ONE line (like the
    Delphi IDE). If the window is narrower than the signature, a horizontal
    scrollbar appears instead of wrapping the header. ssBoth enables both bars. }
  FBody.WordWrap   := False;
  FBody.ScrollBars := ssBoth;
  FBody.Color      := clWindow;
  FBody.TabStop    := False;
  { v0.94.1: CRITICAL for the colored render. When VCL styles / DevExpress IDE
    theming are active, TRichEditStyleHook repaints the control and OVERRIDES the
    per-run SelAttributes.Color we set in Emit -- so every token comes out the
    theme's default foreground (i.e. "no colors"). StyleElements := [] opts this
    one control out of style-hooking, letting our syntax colors + IDE font
    survive. The popup form itself still follows the theme (ApplyIdeTheme). }
  FBody.StyleElements:= [];
  FBody.OnClick    := HandleMemoClick;
  FBody.OnMouseMove:= HandleMemoMouseMove; { hand cursor over clickable lines }

  { v0.94: render both the body and the callers grid in the IDE's configured
    editor font (Tools > Options > Editor). Fall back to Consolas 9 when the
    IDE font is unavailable (older IDE / service absent -- GetIdeEditorFont is
    guarded and returns False). Replaces the old hardcoded Consolas lines. }
  var FN: string;
  var FS: Integer;
  if GetIdeEditorFont(FN, FS) then
  begin
    FBody.Font.Name   := FN; FBody.Font.Size   := FS;
    FTitle.Font.Name  := FN; FTitle.Font.Size  := FS;
    FCallers.Font.Name:= FN; FCallers.Font.Size:= FS;
  end
  else
  begin
    FBody.Font.Name   := 'Consolas'; FBody.Font.Size   := 9;
    FTitle.Font.Name  := 'Consolas'; FTitle.Font.Size  := 9;
    FCallers.Font.Name:= 'Consolas'; FCallers.Font.Size:= 9;
  end;

  FCallerPaths:= TStringList.Create;

  FWatchTimer:= TTimer.Create(Self);
  FWatchTimer.Enabled := False;
  FWatchTimer.Interval:= 150;
  FWatchTimer.OnTimer := HandleWatchTick;

  { v0.46: follow the IDE light/dark theme (guarded; no-op on older IDEs). }
  ApplyIdeTheme(Self);
  { v(theme fix): FBody + FCallers opt OUT of VCL style-hooking (StyleElements:=[])
    so our per-token syntax colors survive -- but that also means they never pick
    up the themed BACKGROUND and would paint on hardcoded clWindow (white) even
    under a DARK IDE theme (ApplyTheme themes the form frame; Self.Color stays
    clWindow). Pull the ACTIVE style's real window bg + text and apply them by hand
    to the form and the two opted-out children, so the popup matches the IDE theme.
    The contrast guard (Emit -> EnsureReadable) then adapts every syntax color to
    this background; the callers grid (no per-run colors) needs its Font.Color set
    explicitly so its text stays readable on a dark surface. }
  Color              := ThemedColor(clWindow);
  FBody.Color        := Color;
  FTitle.Color       := Color;
  FCallers.Color     := Color;
  FCallers.Font.Color:= ThemedColor(clWindowText);
  { Runs written before RenderModel redirects it go to the body, which is what
    the legacy string path expects. }
  FEmitTarget:= FBody;
end; // constructor

procedure TDragLintHoverForm.DoClose(var Action: TCloseAction);
begin
  if FWatchTimer <> nil then FWatchTimer.Enabled:= False;
  if GCurrentHover = Self then GCurrentHover:= nil;
  FreeAndNil(FCallerPaths);
  inherited;
  Action:= caFree;
end;

function GetIdeMainHwnd: HWND;
var
  Svcs: IOTAServices;
begin
  Result:= 0;
  if Supports(BorlandIDEServices, IOTAServices, Svcs) then Result:= Svcs.GetParentHandle;
  if (Result = 0) and (Application <> nil) and (Application.MainForm <> nil) then Result:= Application.MainForm.Handle;
end;

procedure TDragLintHoverForm.HandleWatchTick(Sender: TObject);
const
  MARGIN   = 20;
  GRACE_MS = 1500;
  { v0.42: anchor-box half-extents ~ "1 line up/down, 3-4 chars left/right". }
  ANCHOR_HALF_W   = 28;
  ANCHOR_HALF_H   = 13;
  ANCHOR_GRACE_MS = 300;
var
  Pt     : TPoint;
  ExtRect: TRect ;
  AncRect: TRect ;
begin
  { v0.94.1 z-order: the IDE's OWN Code Insight / parameter-hint popup can spawn
    AFTER ours and claim the topmost slot, sliding in front of us. Re-assert our
    topmost position on every tick (SWP_NOACTIVATE so we never steal focus from
    the editor caret) -- within one 150 ms tick we reclaim the top and the IDE
    popup drops behind. Cheap idempotent no-op when we are already on top. }
  { v(hover-resize): a sizing drag keeps the cursor on the popup edge and briefly
    activates the window; both would otherwise satisfy a dismissal rule below and
    close the popup mid-drag. Also skip the topmost re-assert, which fights the
    sizing loop's own painting. }
  if FSizing then Exit;

  if Visible and HandleAllocated then
    SetWindowPos(Handle, HWND_TOPMOST, 0, 0, 0, 0,
      SWP_NOMOVE or SWP_NOSIZE or SWP_NOACTIVATE);

  if not GetCursorPos(Pt) then Exit;

  if FAnchorDismiss then
  begin
    { v0.42 dwell popup: close the instant the cursor leaves a tight box around
      the ORIGINAL dwell point. Short grace so a sub-pixel jitter at spawn
      doesn't self-close. Leaving the editor moves well outside this box, so
      this also satisfies "clear hover when the mouse leaves the edit page". }
    if GetTickCount - FShowTickMs < ANCHOR_GRACE_MS then Exit;
    { v0.46: once the cursor reaches the popup, make it STICKY (switch to the
      generous popup-rect dismissal) so the user can move in and scroll a long
      list -- previously any move off the tiny anchor box closed it instantly. }
    ExtRect:= BoundsRect;
    InflateRect(ExtRect, 24, 24);
    if PtInRect(ExtRect, Pt) then
    begin
      FAnchorDismiss:= False;
      Exit;
    end;
    AncRect:= Rect(FDwellAnchor.X - ANCHOR_HALF_W, FDwellAnchor.Y - ANCHOR_HALF_H, FDwellAnchor.X + ANCHOR_HALF_W, FDwellAnchor.Y + ANCHOR_HALF_H);
    if not PtInRect(AncRect, Pt) then Close;
    Exit;
  end; // if

  { v0.40.8 menu popup: stays interactive -- mouse outside (popup + 20 px
    margin) closes it. ESC also closes via HandleKeyDown. Title-bar close
    button is provided by bsSizeToolWin.
    v0.40.8b: first 1.5 seconds after Show are a grace period -- the popup
    spawns at cursor+20, so the cursor is 20 px above the popup top; any
    1-px upward drift would otherwise close it immediately. }
  if GetTickCount - FShowTickMs < GRACE_MS then Exit;
  ExtRect:= BoundsRect;
  InflateRect(ExtRect, MARGIN, MARGIN);
  if not PtInRect(ExtRect, Pt) then Close;
end; // procedure

procedure TDragLintHoverForm.HandleKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = VK_ESCAPE then
  begin
    Key:= 0;
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
  Ln : Integer  ;
  Idx: Integer  ;
begin
  Sel:= FCallers.Selected;
  if (Sel = nil) or (FCallerPaths = nil) then Exit;
  if Sel.SubItems.Count = 0 then Exit;
  Idx:= Sel.Index;
  if (Idx < 0) or (Idx >= FCallerPaths.Count) then Exit;
  Ln:= StrToIntDef(Sel.SubItems[0], 0);
  OpenSourceAt(FCallerPaths[Idx], Ln);
  Close;
end;

procedure TDragLintHoverForm.HandleCallerKey(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = VK_RETURN then
  begin
    Key:= 0;
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
  Lines      : TArray<string>;
  SB         : TStringBuilder;
  L          : string        ;
  T          : string        ;
  BlankRun   : Boolean       ;
  SeenContent: Boolean       ;
  I          : Integer       ;
begin
  if Trim(AMarkdown) = '' then Exit('');
  Lines:= AMarkdown.Split([#10]);
  SB:= TStringBuilder.Create;
  try
    BlankRun   := False;
    SeenContent:= False;
    for I:= 0 to High(Lines) do
    begin
      L:= StringReplace(Lines[I], #13, '', [rfReplaceAll]);
      L:= StringReplace(L, '`' , '', [rfReplaceAll]);
      L:= StringReplace(L, '**', '', [rfReplaceAll]);
      { unwrap whole-line italics only (don't disturb in-identifier underscores) }
      T:= Trim(L);
      if (Length(T) >= 2) and (T[1] = '_') and (T[Length(T)] = '_') then L:= Copy(T, 2, Length(T) - 2);
      if Trim(L) = '' then
      begin
        { v0.46: drop LEADING blank lines (the empty first row the user saw) and
          collapse runs of blanks. }
        if (not SeenContent) or BlankRun then Continue;
        BlankRun:= True;
      end
      else
      begin
        BlankRun   := False;
        SeenContent:= True;
      end;
      SB.AppendLine(L.TrimRight);
    end; // for
    Result:= SB.ToString;
  finally
    SB.Free;
  end; // try
end; // function

function UnitNameFromQname(const AQname: string): string;
{ Mirror of Editor.ExtractHoverHeader's heuristic: drop the last 1 or 2
  segments of a dotted qname to get the unit. If the next-to-last segment
  starts with T/I/E it's a class/interface/exception, drop two; else drop one. }
var
  P       : Integer;
  P2      : Integer;
  I       : Integer;
  DotCount: Integer;
begin
  Result  := '';
  DotCount:= 0;
  for I:= 1 to Length(AQname) do
    if AQname[I] = '.' then Inc(DotCount);
  if DotCount    = 0 then Exit;
  Result:= AQname;
  if DotCount >= 2 then
  begin
    P:= 0;
    for I:= Length(Result) downto 1 do
      if Result[I] = '.' then begin P:= I; Break; end;
    P2:= 0;
    for I:= P - 1 downto 1 do
      if Result[I] = '.' then begin P2:= I; Break; end;
    if (P2 > 0) and (P2 + 1 <= Length(Result)) and CharInSet(Result[P2 + 1], ['T','I','E']) then Result:= Copy(Result, 1, P2 - 1)
    else Result:= Copy(Result, 1, P - 1);
  end
  else Result:= Copy(Result, 1, Pos('.', Result) - 1);
end; // function

function TDragLintHoverForm.ReturnLineForBodyLine(const ALineText: string): Integer;
{ FB3: a rendered return line reads "...Result := <expr>" (inline for a single
  mined value, or one per line for several). Extract <expr> after the LAST
  'Result := ' and match it against the mined returns (deduped -> unique), giving
  that value's absolute source line. 0 when the line is not a return. }
var
  P, I: Integer;
  Expr: string ;
begin
  Result:= 0;
  P:= Pos('Result := ', ALineText);
  if P <= 0 then Exit;
  Expr:= Trim(Copy(ALineText, P + Length('Result := '), MaxInt));
  if Expr = '' then Exit;
  for I:= 0 to High(FReturnExprs) do
    if (FReturnExprs[I] = Expr) and (I <= High(FReturnLines)) and (FReturnLines[I] > 0) then
      Exit(FReturnLines[I]);
end;

{ A "- Wiki: <name> -> <qname> - line N" indicator, reduced to the plain
  "<qname> - line N" tail every other clickable definition row already uses.

  WHY A PREFIX AND NOT A NEW CONTROL. Owner ruling R3 asked for a clickable
  "has Wiki" link and explicitly said to establish whether the popup already
  had a navigation affordance before designing one. It does: a memo line of
  that shape navigates via GOnNavigateToQname. So the engine emits the pointer
  in that shape with a readable prefix, and this strips the prefix -- no new
  control, no second navigation path to keep working.

  The producer is WikiIndicatorLines in DRagLint.Hover.Renderer; the two
  formats must stay in step. Returns ABody unchanged when it is not one. }
function StripWikiIndicatorPrefix(const ABody: string): string;
const
  WIKI_PREFIX = 'Wiki: ';
  WIKI_ARROW  = ' -> ';
var
  ArrowAt: Integer;
begin
  Result:= ABody;
  if not ABody.StartsWith(WIKI_PREFIX) then Exit;
  ArrowAt:= Pos(WIKI_ARROW, ABody);
  if ArrowAt <= 0 then Exit;
  Result:= Trim(Copy(ABody, ArrowAt + Length(WIKI_ARROW), MaxInt));
end;

procedure TDragLintHoverForm.HandleMemoClick(Sender: TObject);
{ v0.40.8g: single-click navigation. We don't navigate on every click in the
  memo (the user has to be able to scroll / position the caret to read) -- we
  only navigate when the line under the caret matches the definition shape
  "<qname> - line N". Other lines pass through to normal memo click handling.
  v0.46: the body is now cleaned of markdown (CleanHoverMarkdown), so the rows
  read "- <qname> - line N" WITHOUT backticks; parse that shape. }
var
  LineIdx : Integer;
  LineText: string ;
  Body    : string ;
  Qname   : string ;
  LineStr : string ;
  UnitName: string ;
  DashAt  : Integer;
  LineN   : Integer;
  P       : Integer;
  Q       : Integer;
  AddUnit : string ;
  Tail    : string ;
const
  MARK = 'add unit ';
begin
  LineIdx:= FBody.CaretPos.Y;
  if (LineIdx < 0) or (LineIdx >= FBody.Lines.Count) then Exit;
  LineText:= FBody.Lines[LineIdx];

  { v0.94 Help-Insight body: a structured (model-rendered) popup has its
    definition target on the header line (0). Clicking anywhere on line 0
    navigates to FModelQName at FModelDefLine via the Editor-supplied hook.
    The Parameters/Returns lines below are plain, selectable text (no nav). }
  if FStructured then
  begin
    { Pick the navigation target. v(hover-title): the "line 0 -> the symbol's
      definition" rule is GONE from here -- the signature moved to the title band,
      so body line 0 is now an ordinary content line (usually PARAMETERS) and
      treating it as the definition link would navigate on a click that the user
      meant as a text selection. The definition link lives on FTitle
      (HandleTitleClick). What remains here is the FB3 rule: a "Result := <expr>"
      body line jumps to that return's own source line. }
    var NavQName: string := FModelQName;
    var NavLine : Integer:= -1;   // -1 = this line is not a navigation target
    var RetLine : Integer:= ReturnLineForBodyLine(LineText);
    if RetLine > 0 then NavLine:= RetLine;
    if (NavQName <> '') and (NavLine >= 0) and Assigned(GOnNavigateToQname) then
    begin
      { CRITICAL (AV fix): do NOT Close + navigate INSIDE this mouse-up handler.
        Navigation opens an IDE editor and re-enters the message loop while the VCL
        and DevExpress GLOBAL message hooks (cxContainerGetMessageHook) are still
        dispatching this WM_LBUTTONUP on the popup's controls -- closing frees those
        controls mid-dispatch, and the hook then calls a message handler on freed
        memory (access violation in System.GetDynaMethod). Queue the close+navigate
        to run AFTER this mouse message has fully unwound. NavQName/NavLine are
        captured by value so the deferred block does not touch the form's fields. }
      TThread.ForceQueue(nil,
        procedure
        begin
          Close;
          if Assigned(GOnNavigateToQname) then GOnNavigateToQname(NavQName, NavLine);
        end);
    end;
    Exit;
  end;

  { v0.46 lightbulb: a diagnostic line reading "... add unit X to the uses
    clause" is clickable -- clicking it inserts X via the Editor-supplied hook. }
  if Assigned(GOnAddUnit) then
  begin
    P:= Pos(MARK, LowerCase(LineText));
    if P > 0 then
    begin
      Tail:= Copy(LineText, P + Length(MARK), MaxInt);
      Q:= 1;
      while (Q <= Length(Tail)) and CharInSet(Tail[Q], ['A'..'Z', 'a'..'z', '0'..'9', '_', '.']) do Inc(Q);
      AddUnit:= Copy(Tail, 1, Q - 1);
      if AddUnit <> '' then
      begin
        { AV fix (see the structured branch): defer close+action out of the mouse
          handler so the popup is not freed mid message-dispatch. }
        var LUnit: string:= AddUnit;
        TThread.ForceQueue(nil,
          procedure begin Close; if Assigned(GOnAddUnit) then GOnAddUnit(LUnit); end);
        Exit;
      end;
    end;
  end; // if

  { Gate: a definition row is "- <qname> - line N". Require the bullet, the
    " - line " separator, and a positive trailing integer so doc/blank lines
    (and ordinary "- bullet" prose) are left alone. }
  Body:= LineText.TrimLeft;
  if not Body.StartsWith('- ') then Exit;
  Body:= StripWikiIndicatorPrefix(Copy(Body, 3, MaxInt)); { bullet, then any Wiki: prefix }

  DashAt:= Pos(' - line ', Body);
  if DashAt <= 0 then Exit;
  Qname:= Trim(Copy(Body, 1, DashAt - 1));
  LineStr:= Trim(Copy(Body, DashAt + Length(' - line '), MaxInt));
  LineN:= StrToIntDef(LineStr, 0);
  if (Qname = '') or (LineN <= 0) then Exit;

  UnitName:= UnitNameFromQname(Qname);
  if UnitName = '' then Exit;
  { AV fix (see the structured branch): defer close+navigate out of the mouse-up
    handler -- the Editor hook opens a code view and re-enters the message loop,
    and closing frees controls the VCL/DevExpress hooks are still dispatching on.
    Prefer the Editor hook (resolves the unit to its ABSOLUTE path + forces the
    code view); OpenSourceAt is the guarded fallback. }
  var LQname   : string := Qname;
  var LUnitName: string := UnitName;
  var LLineN   : Integer:= LineN;
  TThread.ForceQueue(nil,
    procedure
    begin
      Close;
      if Assigned(GOnNavigateToQname) then GOnNavigateToQname(LQname, LLineN)
      else OpenSourceAt(LUnitName + '.pas', LLineN);
    end);
end; // procedure

{ Is a memo line clickable? -- an "add unit X" lightbulb line, or a definition
  row "- <qname> - line N". Used to show the hand cursor over it. }
function TDragLintHoverForm.LineIsClickable(const ALineText: string): Boolean;
var
  Body  : string ;
  DashAt: Integer;
begin
  Result:= False;
  if Pos('add unit ', LowerCase(ALineText)) > 0 then Exit(True);
  { FB3: a structured popup's "Result := <expr>" return line is clickable (jumps
    to that value's source line) -> show the hand cursor over it. }
  if FStructured and (ReturnLineForBodyLine(ALineText) > 0) then Exit(True);
  Body:= ALineText.TrimLeft;
  if not Body.StartsWith('- ') then Exit;
  Body:= StripWikiIndicatorPrefix(Copy(Body, 3, MaxInt));
  DashAt:= Pos(' - line ', Body);
  if DashAt <= 0 then Exit;
  Result:= StrToIntDef(Trim(Copy(Body, DashAt + Length(' - line '), MaxInt)), 0) > 0;
end;

{ v0.46.x: show a hand cursor over clickable lines so users see they are links.
  v0.94.1: FBody is a TRichEdit (MSFTEDIT), NOT a TMemo. Its EM_CHARFROMPOS
  contract differs from the plain EDIT control: lParam is a POINTL* (pointer to
  the client point) and the message RETURNS the zero-based CHARACTER index -- it
  does NOT pack (char,line) into the result like a multiline EDIT does. The old
  TMemo idiom `Perform(EM_CHARFROMPOS, 0, MakeLParam(X,Y))` passed the packed
  coordinate where a POINTER was expected, so the rich edit dereferenced a bogus
  address -> AV inside MSFTEDIT.DLL (IID_ITextHost). Fixed: pass @Pt and derive
  the line via EM_EXLINEFROMCHAR on the returned char index. }
procedure TDragLintHoverForm.HandleMemoMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
var
  Pt     : TPoint ;
  CharIdx: Integer;
  LineIdx: Integer;
begin
  Pt.X:= X;
  Pt.Y:= Y;
  CharIdx:= SendMessage(FBody.Handle, EM_CHARFROMPOS, 0, LPARAM(@Pt));
  if CharIdx < 0 then begin FBody.Cursor:= crDefault; Exit; end;
  { EM_EXLINEFROMCHAR: char index -> zero-based line index (rich edit). }
  LineIdx:= SendMessage(FBody.Handle, EM_EXLINEFROMCHAR, 0, CharIdx);
  if FStructured then
  begin
    if (LineIdx = 0) and (FModelQName <> '') then FBody.Cursor:= crHandPoint
    else FBody.Cursor:= crDefault;
    Exit;
  end;
  if (LineIdx >= 0) and (LineIdx < FBody.Lines.Count) and LineIsClickable(FBody.Lines[LineIdx]) then FBody.Cursor:= crHandPoint
  else FBody.Cursor:= crDefault;
end;

{ ---- v0.94 structured Help-Insight body: colored, selectable render ---- }

procedure TDragLintHoverForm.Emit(const AText: string; AColor: TColor; ABold: Boolean);
{ Append AText as one colored run at the end of the body. AColor is run through
  the WCAG contrast guard against the form's actual background first, so a
  keyword blue is never rendered unreadable on a dark theme. }
var
  Safe: TColor;
begin
  if AText = '' then Exit;
  { 3.0 (large/bold) floor for the bold header name so hue is preserved more
    aggressively; 4.5 (body text) for everything else. }
  if ABold then Safe:= EnsureReadable(AColor, Self.Color, 3.0)
  else          Safe:= EnsureReadable(AColor, Self.Color, 4.5);
  { v(hover-title): runs go to whichever rich edit is currently being filled --
    FTitle while EmitSignatureHeader writes the title band, FBody afterwards.
    Both share Self.Color, so the contrast guard above is correct for either. }
  var Target: TRichEdit:= FEmitTarget;
  if Target = nil then Target:= FBody;
  Target.SelStart := Target.GetTextLen;
  Target.SelLength:= 0;
  Target.SelAttributes.Color:= Safe;
  if ABold then Target.SelAttributes.Style:= [fsBold] else Target.SelAttributes.Style:= [];
  Target.SelText:= AText;
end;

procedure TDragLintHoverForm.HandleTitleClick(Sender: TObject);
{ v(hover-title): the title band replaces body line 0 as the definition link.
  Same deferred close+navigate discipline as HandleMemoClick's structured branch:
  navigating re-enters the message loop while the VCL/DevExpress global message
  hooks are still dispatching this click, and closing here would free the control
  mid-dispatch (access violation in System.GetDynaMethod). Queue it instead. }
begin
  if not FStructured then Exit;
  if (FModelQName = '') or not Assigned(GOnNavigateToQname) then Exit;
  var NavQName: string := FModelQName ;
  var NavLine : Integer:= FModelDefLine;
  TThread.ForceQueue(nil,
    procedure
    begin
      Close;
      if Assigned(GOnNavigateToQname) then GOnNavigateToQname(NavQName, NavLine);
    end);
end;

function TDragLintHoverForm.GetSyntaxColor(ARole: TDLSynRole): TColor;
{ Delegates to the shared palette. FSynOpts is resolved once per RenderModel;
  passing it in keeps the "resolve once, never per token" rule visible at the
  call site rather than buried in a field read. }
begin
  Result:= SyntaxColorFor(FSynOpts, ARole);
end;

procedure TDragLintHoverForm.EmitSignatureHeader(const ASignature, AUnitFile: string; ADefLine: Integer);
{ Emit the one-line signature as a sequence of colored runs -- keywords blue,
  identifiers/types/param-names in the name/type color, operators + punctuation
  muted, string/number literals in the literal color -- then a right-hand
  "unit.pas (line)" locator in the muted color. The WHOLE line is line 0, so a
  click anywhere on it navigates (see HandleMemoClick). Header text is bold. }
var
  I   : Integer;
  N   : Integer;
  Ch  : Char   ;
  Tok : string ;
  Loc : string ;
begin
  N:= Length(ASignature);
  I:= 1;
  while I <= N do
  begin
    Ch:= ASignature[I];
    if CharInSet(Ch, ['A'..'Z', 'a'..'z', '_']) then
    begin
      { identifier / keyword run }
      Tok:= '';
      while (I <= N) and CharInSet(ASignature[I], ['A'..'Z', 'a'..'z', '0'..'9', '_']) do
      begin Tok:= Tok + ASignature[I]; Inc(I); end;
      if MatchText(Tok, KEYWORDS) then Emit(Tok, GetSyntaxColor(srKeyword), True)
      else Emit(Tok, GetSyntaxColor(srName), True);
    end
    else if CharInSet(Ch, ['0'..'9']) then
    begin
      Tok:= '';
      while (I <= N) and CharInSet(ASignature[I], ['0'..'9', '.', 'x', 'X', 'a'..'f', 'A'..'F', '$']) do
      begin Tok:= Tok + ASignature[I]; Inc(I); end;
      Emit(Tok, GetSyntaxColor(srLiteralNum), True);
    end
    else if Ch = '''' then
    begin
      { Pascal string literal: capture through the closing quote. }
      Tok:= '''';
      Inc(I);
      while (I <= N) do
      begin
        Tok:= Tok + ASignature[I];
        if ASignature[I] = '''' then begin Inc(I); Break; end;
        Inc(I);
      end;
      Emit(Tok, GetSyntaxColor(srLiteralStr), True);
    end
    else if Ch = ' ' then
    begin
      Emit(' ', GetSyntaxColor(srMuted), True);
      Inc(I);
    end
    else
    begin
      { operator / punctuation -- emit the single char (multi-char ops like :=
        still read correctly as adjacent muted runs). }
      Emit(Ch, GetSyntaxColor(srOperator), True);
      Inc(I);
    end;
  end;

  { Right-hand locator: unit.pas (line). Muted; part of line 0 so it is also
    clickable, matching the "click the header to jump to the definition" rule. }
  if AUnitFile <> '' then
  begin
    Loc:= '   ' + AUnitFile;
    if ADefLine > 0 then Loc:= Loc + ' (' + IntToStr(ADefLine) + ')';
    Emit(Loc, GetSyntaxColor(srMuted), True);
  end;
end;

procedure TDragLintHoverForm.RenderModel(const AModel: TDragLintHoverModel; ACallerCount: Integer);
{ Clear the body and lay out the Help-Insight view: colored signature header
  (line 0, click-navigates), a "Parameters" block (one aligned
  `modifier name : type` line per param), a "Returns" block (single
  `type : Result := expr` or a list of `Result := expr` lines + "... and N
  more"), and -- when ACallerCount > 0 -- a blue bold "CALLED FROM (N)" section
  label as the LAST body line (the callers grid docks directly beneath it).
  Returns is omitted entirely for procedures (no return type, no mined returns).
  Resolves the IDE color interface ONCE here into FSynOpts. }
var
  Svcs     : INTACodeEditorServices;
  MaxNameLen: Integer              ;
  I         : Integer              ;
  P         : TDragLintHoverParam  ;
  NamePad   : string               ;
  HasReturns: Boolean              ;

  { Blank line BETWEEN sections. Suppressed for whichever section happens to be
    first: the body no longer opens with the signature header (that moved to the
    title band), so an unconditional lead-in would start every popup with two
    empty lines -- and those two lines are exactly what pushed the content past
    the measured body height and produced the vertical scrollbar. }
  procedure SectionBreak;
  begin
    if FBody.GetTextLen > 0 then Emit(sLineBreak + sLineBreak, GetSyntaxColor(srMuted), False);
  end;

begin
  FStructured   := True;
  FModelQName   := AModel.QualifiedName;
  FModelDefLine := AModel.DefLine;
  FReturnExprs  := AModel.Returns;      { FB3: remember for click-to-jump on a "Result := <expr>" line }
  FReturnLines  := AModel.ReturnLines;

  { Resolve the IDE editor-color interface once for this render (guarded, like
    Task 5's font read). On any failure FSynOpts stays nil and GetSyntaxColor
    returns the fixed CL_* fallbacks. }
  FSynOpts:= nil;
  try
    if Supports(BorlandIDEServices, INTACodeEditorServices, Svcs) then FSynOpts:= Svcs.Options;
  except
    FSynOpts:= nil;
  end;

  { (1) signature header -- coloured, bold, clickable. v(hover-title): it now
    lands in the TITLE BAND above the body rather than being body line 0, so the
    popup reads like the IDE's own Code Insight window: declaration on top, detail
    underneath. FEmitTarget redirects EmitSignatureHeader's runs; it is restored
    to FBody in the finally so nothing downstream can write into the title. }
  FTitle.Visible   := True;
  FTitleSep.Visible:= True;
  FTitle.Lines.BeginUpdate;
  try
    FTitle.Clear;
    FEmitTarget:= FTitle;
    EmitSignatureHeader(AModel.Signature, AModel.UnitFile, AModel.DefLine);
  finally
    FEmitTarget:= FBody;
    FTitle.Lines.EndUpdate;
  end;

  FBody.Lines.BeginUpdate;
  try
    FBody.Clear;

    { (2) Parameters. Align the colons: pad each name to MaxNameLen + 1. }
    if Length(AModel.Params) > 0 then
    begin
      SectionBreak;
      Emit('PARAMETERS', GetSyntaxColor(srSection), True);
      MaxNameLen:= 0;
      for I:= 0 to High(AModel.Params) do
        MaxNameLen:= Max(MaxNameLen, Length(AModel.Params[I].Name));
      for I:= 0 to High(AModel.Params) do
      begin
        P:= AModel.Params[I];
        Emit(sLineBreak + '  ', GetSyntaxColor(srMuted), False);
        if P.Modifier <> '' then Emit(P.Modifier + ' ', GetSyntaxColor(srKeyword), False);
        NamePad:= P.Name;
        while Length(NamePad) < MaxNameLen + 1 do NamePad:= NamePad + ' ';
        Emit(NamePad, GetSyntaxColor(srParam), False);
        Emit(': ', GetSyntaxColor(srMuted), False);
        { v0.94.1: an untyped var/out parameter (Delphi allows `var X` with no
          type -- passed by address) has no TypeText; label it "by reference" in
          the muted color so it reads as a note, not a real type name. }
        if P.TypeText <> '' then
          Emit(P.TypeText, GetSyntaxColor(srType), False)
        else
          Emit('by reference', GetSyntaxColor(srMuted), False);
      end;
    end;

    { (3) Returns -- omitted for procedures (no return type AND no mined
      returns). v0.94.1: the return TYPE sits on the RETURNS label line to save
      vertical space ("RETURNS: boolean"). A single mined value goes inline too
      ("RETURNS: boolean = Result := expr"); multiple values list one per line. }
    HasReturns:= (AModel.ReturnType <> '') or (Length(AModel.Returns) > 0);
    if HasReturns then
    begin
      SectionBreak;
      Emit('RETURNS', GetSyntaxColor(srSection), True);
      if AModel.ReturnType <> '' then
      begin
        Emit(': ', GetSyntaxColor(srMuted), True);
        Emit(AModel.ReturnType, GetSyntaxColor(srType), True);
      end;
      if Length(AModel.Returns) = 1 then
      begin
        { inline on the RETURNS line: "  =  Result := expr" }
        Emit('   =   ', GetSyntaxColor(srMuted), False);
        Emit('Result := ' + AModel.Returns[0], GetSyntaxColor(srName), False);
      end
      else if Length(AModel.Returns) > 1 then
      begin
        for I:= 0 to High(AModel.Returns) do
        begin
          Emit(sLineBreak + '  ', GetSyntaxColor(srMuted), False);
          Emit('Result := ' + AModel.Returns[I], GetSyntaxColor(srName), False);
        end;
        if AModel.ReturnsMore > 0 then
        begin
          Emit(sLineBreak + '  ', GetSyntaxColor(srMuted), False);
          Emit('... and ' + IntToStr(AModel.ReturnsMore) + ' more', GetSyntaxColor(srMuted), False);
        end;
      end;
    end;

    { (3.5) DETAILS -- the Phase-2 analysis facts (Complexity / Reads / Writes /
      SQL / Handles / Owns returned / Covered by), one line each in the muted
      color (prose facts, not code). These arrive in AModel.Facts from `hover
      --json`'s new "facts" array; before this fix the structured popup omitted
      them entirely. Omitted when the symbol has no facts. }
    if Length(AModel.Facts) > 0 then
    begin
      SectionBreak;
      Emit('DETAILS', GetSyntaxColor(srSection), True);
      for var FI: Integer:= 0 to High(AModel.Facts) do
      begin
        Emit(sLineBreak + '  ', GetSyntaxColor(srMuted), False);
        Emit(AModel.Facts[FI], GetSyntaxColor(srMuted), False);
      end;
    end;

    { (3.6) DIAGNOSTICS -- findings reported on the hovered LINE.
      Placed AFTER the symbol's description on purpose: the reported complaint
      was that a lint message REPLACED the explanation of the symbol, so the
      explanation leads and the finding follows it. Drawn in the error colour so
      it still reads as a warning rather than as more prose. Omitted entirely
      when the line is clean, which is the common case. }
    if Length(AModel.Diagnostics) > 0 then
    begin
      SectionBreak;
      Emit('DIAGNOSTICS', GetSyntaxColor(srSection), True);
      for var DI: Integer:= 0 to High(AModel.Diagnostics) do
      begin
        Emit(sLineBreak + '  ', GetSyntaxColor(srMuted), False);
        Emit(AModel.Diagnostics[DI], GetSyntaxColor(srError), False);
      end;
    end;

    { (4) CALLED FROM label -- blue bold section line (like PARAMETERS/RETURNS),
      the LAST body line; the callers ListView (headers hidden) docks right under
      it. Only when there is at least one caller. }
    if ACallerCount > 0 then
    begin
      SectionBreak;
      Emit('CALLED FROM (' + IntToStr(ACallerCount) + ')', GetSyntaxColor(srSection), True);
    end;

    { keep the caret at the top so the header (line 0) is what shows first. }
    FBody.SelStart := 0;
    FBody.SelLength:= 0;
  finally
    FBody.Lines.EndUpdate;
  end;
  FSynOpts:= nil; { drop the cached interface after the render }
end;

procedure TDragLintHoverForm.CreateParams(var Params: TCreateParams);
begin
  inherited CreateParams(Params);
  { Info popup: never take keyboard focus; keep off the taskbar/alt-tab. }
  Params.ExStyle:= Params.ExStyle or WS_EX_NOACTIVATE or WS_EX_TOOLWINDOW;
  { v0.94.1: borderless form (bsNone) -- add a thin 1px frame so the popup still
    reads as a distinct window against the editor, like Delphi's Code Insight. }
  Params.Style:= Params.Style or WS_BORDER;
  { v(hover-resize): WS_THICKFRAME is what lets DefWindowProc run its sizing
    loop when WMNCHitTest reports an edge. With no caption and bsNone there is
    nothing extra painted -- the visible frame is still the WS_BORDER hairline
    above -- but the window becomes user-resizable. }
  Params.Style:= Params.Style or WS_THICKFRAME;
end;

procedure TDragLintHoverForm.WMNCHitTest(var Msg: TWMNCHitTest);
const
  GRIP = 6; { edge band, in px, that reports as a sizing zone }
var
  P: TPoint;
begin
  inherited;
  if Msg.Result <> HTCLIENT then Exit; { let real non-client results stand }
  P:= ScreenToClient(Point(Msg.XPos, Msg.YPos));
  { Right / bottom / corner only. The top-left edges are deliberately NOT sizing
    zones: the popup is anchored at its top-left to the hovered token, and
    dragging that corner would move the anchor out from under the cursor and
    trip the drift dismissal. }
  if (P.X >= ClientWidth - GRIP) and (P.Y >= ClientHeight - GRIP) then Msg.Result:= HTBOTTOMRIGHT
  else if P.X >= ClientWidth  - GRIP then Msg.Result:= HTRIGHT
  else if P.Y >= ClientHeight - GRIP then Msg.Result:= HTBOTTOM;
end;

procedure TDragLintHoverForm.WMEnterSizeMove(var Msg: TMessage);
begin
  inherited;
  FSizing:= True;
end;

procedure TDragLintHoverForm.WMExitSizeMove(var Msg: TMessage);
begin
  inherited;
  FSizing:= False;
  { Re-anchor to where the user left it, so the post-resize cursor position is
    measured against the NEW rect and the popup does not immediately self-close. }
  FAnchor.X      := Left;
  FAnchor.Y      := Top;
  FAnchorDismiss := False;   { once resized it is an interactive window, not a dwell tip }
  FShowTickMs    := GetTickCount;
end;

procedure TDragLintHoverForm.ShowAt(
  X, Y: Integer; const AHeader, ASummary: string; const ACallers: TArray<TDragLintCallerInfo>; AAnchorDismiss: Boolean; AAnchorX, AAnchorY: Integer);
const
  MAX_W = 900;
  MAX_H = 700;
  PAD   = 8;
var
  I           : Integer  ;
  LI          : TListItem;
  W           : Integer  ;
  H           : Integer  ;
  CallersH    : Integer  ;
  HeaderH     : Integer  ;
  SummaryH    : Integer  ;
  ShortName   : string   ;
  Ln          : string   ;
  CleanSummary: string   ;
  ShownCount  : Integer  ;
  HasTrailer  : Boolean  ;
begin
  FStructured   := False; { legacy string path -> definition-row click parsing }
  { v(hover-title): no model here means no signature to put in the title band --
    hide it (and its separator) so the string path keeps its original single-pane
    look and its height maths stay correct. }
  FTitle.Visible   := False;
  FTitleSep.Visible:= False;
  FAnchorDismiss:= AAnchorDismiss;
  if AAnchorX >= 0 then FDwellAnchor:= Point(AAnchorX, AAnchorY)
  else FDwellAnchor:= Point(X, Y);

  { v0.46: render markdown as clean text (the body has no markdown engine).
    v0.94: the body is a TRichEdit now -- emit the cleaned text as one default-
    colored run (SelStart/SelText) so the "- <qname> - line N" rows still parse
    for single-click navigation via HandleMemoClick / LineIsClickable. }
  CleanSummary:= CleanHoverMarkdown(ASummary);
  FBody.Lines.BeginUpdate;
  try
    FBody.Clear;
    FBody.SelStart := 0;
    FBody.SelLength:= 0;
    FBody.SelAttributes.Color:= EnsureReadable(FBody.Font.Color, Self.Color, 4.5);
    FBody.SelAttributes.Style:= [];
    FBody.SelText:= CleanSummary;
  finally
    FBody.Lines.EndUpdate;
  end;
  { v0.40.8g: title bar carries only "drag-lint -- kind name" (no file/line),
    because the body lists every definition with file:line already and the
    user reported the duplication as noise. ExtractHoverHeader still returns
    "kind name -- unit.pas (line)"; we strip everything from the first
    "   --   " separator onward for the title. }
  if AHeader <> '' then
  begin
    var ShortHeader: string:= AHeader                  ;
    var DashPos: Integer:= Pos('   --   ', ShortHeader);
    if DashPos > 0 then ShortHeader:= Trim(Copy(ShortHeader, 1, DashPos - 1));
    Caption:= 'drag-lint -- ' + ShortHeader;
  end
  else Caption:= 'drag-lint hover';

  { v0.94 Task 7: cap the displayed rows at 15/10 (DisplayedCallerCount) so a
    routine with hundreds of callers doesn't blow out the popup -- the upstream
    Editor already hard-caps the fetch at 200. When capped, a final trailer row
    ("... and NN more") is appended with EMPTY SubItems so HandleCallerDblClick's
    existing `SubItems.Count = 0` guard skips navigation on it, and it is
    deliberately NOT added to FCallerPaths (index alignment would otherwise be
    wrong for it anyway, since it has no source file). The column header carries
    the TOTAL count ("Called from (N)") since Task 6 removed the standalone
    header label as redundant noise. }
  ShownCount:= DisplayedCallerCount(Length(ACallers));
  HasTrailer:= ShownCount < Length(ACallers);
  if Length(ACallers) > 0 then FCallers.Columns[0].Caption:= 'Unit -- Called from (' + IntToStr(Length(ACallers)) + ')'
  else FCallers.Columns[0].Caption:= 'Unit';

  FCallerPaths.Clear;
  FCallers.Items.BeginUpdate;
  try
    FCallers.Items.Clear;
    for I:= 0 to ShownCount - 1 do
    begin
      LI:= FCallers.Items.Add;
      ShortName:= ExtractFileName(ACallers[I].FilePath);
      LI.Caption:= ShortName;
      LI.SubItems.Add(IntToStr(ACallers[I].Line));
      LI.SubItems.Add(ACallers[I].CodeText);
      FCallerPaths.Add(ACallers[I].FilePath);
    end;
    if HasTrailer then
    begin
      LI:= FCallers.Items.Add;
      LI.Caption:= '... and ' + IntToStr(Length(ACallers) - ShownCount) + ' more';
      { SubItems left empty: HandleCallerDblClick exits on SubItems.Count = 0,
        and the row is not in FCallerPaths -- so it can never navigate. }
    end;
  finally
    FCallers.Items.EndUpdate;
  end;

  { Sizing: header 22 + summary lines * 16 + callers (header + rows * 18).
    v0.46: size to the CLEANED text (fewer blank lines after the trim).
    v0.94 Task 7: size to the DISPLAYED row count (capped) + trailer, not the
    full untruncated count, so a huge caller list doesn't oversize the popup. }
  HeaderH:= 22;
  SummaryH:= 16 * (1 + Length(CleanSummary.Split([#10]))); { rough }
  if SummaryH < 60 then SummaryH:= 60;
  if SummaryH > 200 then SummaryH:= 200;
  if Length(ACallers) = 0 then
  begin
    FCallers.Visible:= False;
    CallersH:= 0;
  end
  else
  begin
    FCallers.Visible:= True;
    CallersH:= 28 + (ShownCount + IfThen(HasTrailer, 1, 0)) * 18;
    if CallersH < 60 then CallersH:= 60;
    if CallersH > 200 then CallersH:= 200;
    FCallers.Height:= CallersH;
  end;

  { v0.42: dwell popups size to their content width (the summary is short --
    a couple of declaration lines) instead of the fixed 900 px, so they don't
    blanket the panes behind the editor. Consolas 9 pt ~ 7 px/char. Menu
    popups keep the full width because they carry the callers grid. }
  { v(hover-width): size to the CONTENT, measured in the real body font, and cap
    on the monitor instead of a fixed 900. Two things changed here: the 7 px/char
    estimate is gone (only valid for a monospaced cell), and MENU popups are now
    content-sized too -- they previously took MAX_W unconditionally, so a short
    message got a 900 px popup and a long one was truncated by the same 900. }
  var SumLines: TArray<string>:= [AHeader];
  for Ln in CleanSummary.Split([#10]) do SumLines:= SumLines + [Ln.TrimRight];
  W:= MeasureTextWidth(SumLines, False) + 40;
  if W < 200 then W:= 200;
  if not AAnchorDismiss then
  begin
    { menu popup: never let the callers grid need a horizontal scrollbar }
    var ColsW0: Integer:= 0;
    for var Ci:= 0 to FCallers.Columns.Count - 1 do ColsW0:= ColsW0 + FCallers.Columns[Ci].Width;
    var NeedW0: Integer:= ColsW0 + GetSystemMetrics(SM_CXVSCROLL) + 8;
    if W < NeedW0 then W:= NeedW0;
  end;
  if W > MaxPopupWidthAt(X, Y) then W:= MaxPopupWidthAt(X, Y);
  H:= HeaderH + SummaryH + CallersH + PAD * 2;
  if H > MAX_H then H:= MAX_H;
  if H < 120 then H:= 120;

  PlaceAndShow(X, Y, W, H);
end; // procedure

function TDragLintHoverForm.MeasureTextWidth(const ALines: array of string; ABold: Boolean): Integer;
var
  Bmp: Vcl.Graphics.TBitmap;
  S  : string;
  Wd : Integer;
begin
  Result:= 0;
  Bmp:= Vcl.Graphics.TBitmap.Create;
  try
    Bmp.Canvas.Font.Assign(FBody.Font);
    if ABold then Bmp.Canvas.Font.Style:= Bmp.Canvas.Font.Style + [fsBold];
    for S in ALines do
    begin
      if S = '' then Continue;
      Wd:= Bmp.Canvas.TextWidth(S);
      if Wd > Result then Result:= Wd;
    end;
  finally
    Bmp.Free;
  end;
end;

function TDragLintHoverForm.MaxPopupWidthAt(AX, AY: Integer): Integer;
const
  EDGE_MARGIN = 24; { keep a little air between the popup and the screen edge }
var
  R: TRect;
begin
  R:= Screen.MonitorFromPoint(Point(AX, AY), mdNearest).WorkareaRect;
  Result:= (R.Right - R.Left) - EDGE_MARGIN;
  if Result < 480 then Result:= 480; { pathological tiny display -- keep it usable }
end;

procedure TDragLintHoverForm.PlaceAndShow(X, Y, W, H: Integer);
{ v0.94: the final size + on-screen placement + no-steal-focus show, factored
  out of the string ShowAt so the structured ShowAt shares the EXACT same
  window mechanics (dwell-timer start, WS_EX_NOACTIVATE topmost show, and the
  capture/restore-foreground+focus dance that keeps the editor caret alive).
  Callers pass the already-computed W/H; anchor state (FAnchorDismiss/
  FDwellAnchor) is set by the caller before this runs. }
var
  MonR   : TRect  ;
  AvailH : Integer;
begin
  { v0.94.1: expand to fit the content, but never past the screen. First try to
    grow DOWNWARD from Y; if the content is taller than the space below, pull the
    top up to use the space above too; only if it still doesn't fit the whole
    work area do we clamp H to the work-area height (the TRichEdit then scrolls).
    So: use available space first, fall back to the screen edge -- never run off. }
  { Use the work area of the monitor the popup actually lands on. SPI_GETWORKAREA
    reports the PRIMARY monitor only, so on a multi-monitor desk a popup on the
    secondary screen was clamped against the wrong rectangle. }
  MonR:= Screen.MonitorFromPoint(Point(X, Y), mdNearest).WorkareaRect;
  begin
    { HEIGHT FIRST, because whether a VERTICAL SCROLLBAR appears is decided
      here, and that decision changes the width we need.

      THE SHRINKING-POPUP LOOP (owner, 2026-08-19). When the content is taller
      than the work area H is clamped and the body raises a vertical scrollbar.
      That bar eats SM_CXVSCROLL pixels of the body's WIDTH, which pushes more
      lines past the right edge, which raises the HORIZONTAL bar, which eats
      SM_CYHSCROLL of the height -- so the window that was already too small to
      hold the text ends up holding even less of it. Each bar makes the other
      more likely. The sizing above measured the text but never paid for the
      furniture its own clamp was about to add. }
    AvailH:= MonR.Bottom - Y;            { space below the anchor }
    if H > AvailH then
    begin
      { not enough room below -- move the top up so the bottom sits on the edge }
      Y:= MonR.Bottom - H;
      if Y < MonR.Top then
      begin
        { still taller than the whole work area -- pin to the top and clamp H so
          the popup exactly fills the work area height (scrollbar takes over). }
        Y:= MonR.Top;
        H:= MonR.Bottom - MonR.Top;
        { The clamp above IS the decision to scroll. Buy back the width that
          bar will take, so the text keeps the same usable columns it had
          before the popup got tall. FBody has WordWrap=False, so a wider
          window does not change the wrapped line count and cannot invalidate
          the height just computed -- it only stops the horizontal bar being
          raised for lines that would otherwise have fitted. }
        Inc(W, GetSystemMetrics(SM_CXVSCROLL));
      end;
    end;

    { Width LAST, so the widening above is still subject to the screen. Width
      was once never clamped -- only nudged left -- so a popup wider than the
      work area ran off the right edge (X hit MonR.Left and W stayed
      oversized). }
    if W > MonR.Right - MonR.Left then W:= MonR.Right - MonR.Left;
    if X + W > MonR.Right then X:= MonR.Right - W;
    if X < MonR.Left then X:= MonR.Left;
  end;
  Width := W;
  Height:= H;
  Left:= X;
  Top := Y;
  FAnchor.X:= X;
  FAnchor.Y:= Y;

  FShowTickMs:= GetTickCount;
  FWatchTimer.Enabled:= True;
  { v0.47: show WITHOUT stealing keyboard focus so the user can keep typing.
    WS_EX_NOACTIVATE (CreateParams) is not enough on its own: Visible:=True uses
    SW_SHOWNORMAL which still activates us. So we capture whoever had focus (the
    editor), show topmost+no-activate, then HAND FOCUS BACK. The popup stays
    visible (topmost) but unfocused; the editor keeps the caret + keystrokes. }
  var PrevForeground: HWND:= GetForegroundWindow;
  var PrevFocus     : HWND:= GetFocus;
  Visible:= True;
  SetWindowPos(Handle, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE or SWP_NOSIZE or SWP_NOACTIVATE);
  if (PrevForeground <> 0) and (PrevForeground <> Handle) then
  try SetForegroundWindow(PrevForeground); except end;
  if (PrevFocus <> 0) and (PrevFocus <> Handle) then
  try Winapi.Windows.SetFocus(PrevFocus); except end;
end; // procedure

procedure TDragLintHoverForm.ShowAt(
  X, Y: Integer; const AModel: TDragLintHoverModel; const ACallers: TArray<TDragLintCallerInfo>; AAnchorDismiss: Boolean; AAnchorX, AAnchorY: Integer);
const
  MAX_W = 1200;
  { v0.94.1: MAX_H is a generous ceiling -- PlaceAndShow clamps the final rect to
    the monitor work area, so a tall popup shrinks to the screen edge rather than
    running off it. We size to the ACTUAL content (below) so no scrollbar is
    needed when there is room; only when content genuinely exceeds the screen
    does the scrollbar appear. }
  MAX_H = 1200;
  PAD   = 8;
var
  I       : Integer  ;
  LI      : TListItem;
  W       : Integer  ;
  H       : Integer  ;
  CallersH: Integer  ;
  BodyH   : Integer  ;
  TitleH  : Integer  ;
  ShortName: string  ;
  ShownCount: Integer;
  HasTrailer: Boolean;
begin
  FAnchorDismiss:= AAnchorDismiss;
  if AAnchorX >= 0 then FDwellAnchor:= Point(AAnchorX, AAnchorY)
  else FDwellAnchor:= Point(X, Y);

  { Render the colored, selectable Help-Insight body (sets FStructured := True,
    FModelQName/FModelDefLine for the clickable header). The caller count drives
    the blue bold "CALLED FROM (N)" label at the bottom of the body. }
  RenderModel(AModel, Length(ACallers));

  { Title bar: "drag-lint -- <qname>" (no file/line -- the header line carries
    the unit + line already). }
  { v0.94.1: the colored signature header line (line 0) IS the header now, so the
    title bar just carries the tool name -- repeating the qname there was noise. }
  Caption:= 'drag-lint';

  { v0.94 Task 7: same 15/10 display cap + "... and NN more" trailer as the string
    ShowAt overload. v0.94.1: the count now lives in the body's "CALLED FROM (N)"
    label (RenderModel), so no column caption is set here (headers are hidden). }
  ShownCount:= DisplayedCallerCount(Length(ACallers));
  HasTrailer:= ShownCount < Length(ACallers);

  FCallerPaths.Clear;
  FCallers.Items.BeginUpdate;
  try
    FCallers.Items.Clear;
    for I:= 0 to ShownCount - 1 do
    begin
      LI:= FCallers.Items.Add;
      ShortName:= ExtractFileName(ACallers[I].FilePath);
      LI.Caption:= ShortName;
      LI.SubItems.Add(IntToStr(ACallers[I].Line));
      LI.SubItems.Add(ACallers[I].CodeText);
      FCallerPaths.Add(ACallers[I].FilePath);
    end;
    if HasTrailer then
    begin
      LI:= FCallers.Items.Add;
      LI.Caption:= '... and ' + IntToStr(Length(ACallers) - ShownCount) + ' more';
      { empty SubItems -- HandleCallerDblClick guards on SubItems.Count = 0, and
        this row is never added to FCallerPaths, so it can't navigate. }
    end;
  finally
    FCallers.Items.EndUpdate;
  end;

  { Sizing: body sized to its actual rendered line count (header + params +
    returns), callers grid same rule as the string path. Structured hovers keep
    the full width so long signatures + the callers grid fit.
    v0.94 Task 7: callers height uses the DISPLAYED (capped) count + trailer. }
  { v(hover-polish): WIDTH first, from the widest logical MODEL line (not
    FBody.Lines, which is already wrapped at the current narrow width). The
    signature header (+ its "   unit.pas (line)" locator) is almost always the
    widest line; also consider the widest param line. ~7.6 px/char + padding. }
  { v(hover-width): MEASURE the candidate lines in the real body font instead of
    estimating ~7.6 px per character. The estimate assumed a monospaced cell, so
    on a proportional font it both padded narrow popups and wrapped wide ones
    that would have fitted. Collect every logical line the body can show -- the
    signature header with its locator, each parameter, each mined return, each
    fact -- and take the widest. }
  { v(hover-title): kept as TWO lists now. BodyCands is what the BODY can show;
    the signature is measured separately because it lives in the title band. The
    width still has to satisfy BOTH (the title is clipped, not wrapped), but only
    BodyCands decides whether the body needs a horizontal scrollbar -- and that
    distinction is what lets the body stop reserving space for the signature. }
  var TitleCand: string:= AModel.Signature + '     ' + AModel.UnitFile + ' (line ' + IntToStr(AModel.DefLine) + ')';
  var BodyCands: TArray<string>:= nil;
  for I:= 0 to High(AModel.Params) do
    BodyCands:= BodyCands + [Trim(AModel.Params[I].Modifier + ' ' + AModel.Params[I].Name + ': ' + AModel.Params[I].TypeText) + '    '];
  for I:= 0 to High(AModel.Returns) do BodyCands:= BodyCands + ['    Result := ' + AModel.Returns[I]];
  for I:= 0 to High(AModel.Facts)   do BodyCands:= BodyCands + ['    ' + AModel.Facts[I]];
  { THE LINE THAT WAS NEVER MEASURED (owner, 2026-08-19). The DIAGNOSTICS
    section is drawn by the body -- see the Emit block above -- but its lines
    were left out of BodyCands, so the widest text in the popup did not
    contribute a single pixel to the width. A finding like
    '[object-leak] Object "s" may be leaked: created but not freed or
    transferred on some path.' is far longer than any signature, so the popup
    came up too narrow, raised a horizontal scrollbar, and lost height to it.
    Same two-space indent the renderer uses, so the measurement matches what is
    actually drawn. }
  for I:= 0 to High(AModel.Diagnostics) do BodyCands:= BodyCands + ['  ' + AModel.Diagnostics[I]];
  var Cands: TArray<string>:= [TitleCand] + BodyCands;
  { Bold: the signature header is drawn bold and is almost always the widest. }
  { Owner's rule, 2026-08-19: measure every output line for its REAL length,
    then add a scrollbar's width and a couple of pixels regardless. Paying for
    a bar that turns out not to be needed costs a few pixels of air; not paying
    for one that IS needed costs the bar, and then the second bar it provokes. }
  W:= MeasureTextWidth(Cands, True) + 70 + GetSystemMetrics(SM_CXVSCROLL) + 2;
  if W < 480   then W:= 480;
  { #4: when the callers grid is shown, floor the width to fit ALL of its columns
    (+ a possible vertical scrollbar + borders) so there is NO horizontal
    scrollbar. Sum the actual column widths rather than hard-coding them. }
  var ColsW: Integer:= 0;
  for I:= 0 to FCallers.Columns.Count - 1 do ColsW:= ColsW + FCallers.Columns[I].Width;
  if (Length(ACallers) > 0) then
  begin
    var NeedW: Integer:= ColsW + GetSystemMetrics(SM_CXVSCROLL) + 8;
    if W < NeedW then W:= NeedW;
  end;
  { Cap on the SCREEN, not on a hardcoded 1200: "as wide as the message needs,
    never wider than the monitor it appears on". }
  if W > MaxPopupWidthAt(X, Y) then W:= MaxPopupWidthAt(X, Y);

  { v(hover-polish): CONTENT-FIT sizing. Re-flow the body at the FINAL width so its
    wrapped line count is accurate (alClient FBody follows ClientWidth), then size
    to the EXACT content height. We deliberately do NOT clamp H to a fixed maximum:
    PlaceAndShow grows the popup into the available screen space and only turns on
    the scrollbar when the content exceeds the whole work area. }
  ClientWidth:= W;   // lay FBody out at the final width -> re-wrap before measuring

  { #1: measure the true line height from the font, and the WRAPPED line count via
    EM_GETLINECOUNT, so the body is exactly as tall as its text -- no dead empty
    space between the last body line ("CALLED FROM (N)") and the callers grid. }
  var LineH: Integer;
  { Fully qualified: Winapi.Windows (used later for EM_* / GetSystemMetrics) also
    declares a TBitmap RECORD that would shadow the VCL bitmap class here. }
  var Bmp: Vcl.Graphics.TBitmap:= Vcl.Graphics.TBitmap.Create;
  try
    Bmp.Canvas.Font.Assign(FBody.Font);
    LineH:= Bmp.Canvas.TextHeight('Wg');
  finally
    Bmp.Free;
  end;
  if LineH < 12 then LineH:= Abs(FBody.Font.Height) + 3;

  { v(hover-title): the title band is exactly one line plus a little air, and the
    hairline separator sits under it. Both are alTop, so the body gets whatever is
    left -- their heights therefore have to be part of the total below. }
  TitleH:= LineH + 6;
  FTitle.Height:= TitleH;

  var VisualLines: Integer:= FBody.Perform(EM_GETLINECOUNT, 0, 0);
  if VisualLines < 1 then VisualLines:= FBody.Lines.Count;
  if VisualLines < 3 then VisualLines:= 3;
  { Same rule vertically: the measured lines plus a horizontal bar's height and
    a couple of pixels, so the last line is never the one pushed out of view. }
  BodyH:= VisualLines * LineH + 12 + GetSystemMetrics(SM_CYHSCROLL) + 2;

  { THE VERTICAL SCROLLBAR BUG. FBody has WordWrap=False and ScrollBars=ssBoth, so
    a line wider than the client area raises a HORIZONTAL scrollbar -- which then
    consumes SM_CYHSCROLL pixels of the body's own height. The height computed
    just above does not know that, so the last line is pushed out of view and the
    VERTICAL scrollbar appears as a consequence. The two always arrived together,
    which is why it looked like the body was simply sized one line short.
    Reserve the horizontal bar's height when the widest BODY line genuinely
    overflows. Measured non-bold: body lines are drawn non-bold (only the title
    band is bold), and measuring them bold over-estimates the width and would
    reserve the strip when nothing overflows. The signature is excluded outright
    -- it lives in the title band now and is clipped there, not scrolled. }
  if MeasureTextWidth(BodyCands, False) > (W - GetSystemMetrics(SM_CXVSCROLL) - 8) then
    BodyH:= BodyH + GetSystemMetrics(SM_CYHSCROLL);

  if Length(ACallers) = 0 then
  begin
    FCallers.Visible:= False;
    CallersH:= 0;
  end
  else
  begin
    FCallers.Visible:= True;
    { Size the grid to EXACTLY fit its rows (+ a little chrome) so even a single
      caller is fully painted. }
    var RowH: Integer:= Abs(FCallers.Font.Height) + 8;
    if RowH < 18 then RowH:= 18;
    var Rows: Integer:= ShownCount + IfThen(HasTrailer, 1, 0);
    if Rows < 1 then Rows:= 1;
    CallersH:= Rows * RowH + 8;
    { #2: if a horizontal scrollbar will still appear (columns wider than the
      client area -- e.g. when MAX_W capped the width below ColsW), reserve its
      height so it does not cover the last caller row. }
    if ColsW > (W - GetSystemMetrics(SM_CXVSCROLL) - 6) then
      CallersH:= CallersH + GetSystemMetrics(SM_CYHSCROLL);
    if CallersH > 360 then CallersH:= 360;
    FCallers.Height:= CallersH;
  end;

  { Exact stack: title band + separator + body + grid + minimal border. }
  H:= TitleH + FTitleSep.Height + BodyH + CallersH + 2;
  if H < 120 then H:= 120;

  PlaceAndShow(X, Y, W, H);
end; // procedure

{ ---- public factory ---- }

procedure ShowDragLintHover(
  const AHeader, ASummary: string; const ACallers: TArray<TDragLintCallerInfo>; AScreenX,
  AScreenY: Integer; AAnchorDismiss: Boolean = False; AAnchorX: Integer = -1; AAnchorY: Integer = -1);
var
  Form: TDragLintHoverForm;
begin
  if (GCurrentHover <> nil) and GCurrentHover.Visible then Exit;
  Form:= TDragLintHoverForm.Create(Application);
  GCurrentHover:= Form;
  Form.ShowAt(AScreenX, AScreenY, AHeader, ASummary, ACallers, AAnchorDismiss, AAnchorX, AAnchorY);
end;

procedure ShowDragLintHover(const AContent: string; AScreenX, AScreenY: Integer);
var
  Empty: TArray<TDragLintCallerInfo>;
begin
  SetLength(Empty, 0);
  ShowDragLintHover('', AContent, Empty, AScreenX, AScreenY);
end;

procedure ShowDragLintHover(
  const AModel: TDragLintHoverModel; const ACallers: TArray<TDragLintCallerInfo>; AScreenX,
  AScreenY: Integer; AAnchorDismiss: Boolean = False; AAnchorX: Integer = -1; AAnchorY: Integer = -1);
var
  Form: TDragLintHoverForm;
begin
  if (GCurrentHover <> nil) and GCurrentHover.Visible then Exit;
  Form:= TDragLintHoverForm.Create(Application);
  GCurrentHover:= Form;
  Form.ShowAt(AScreenX, AScreenY, AModel, ACallers, AAnchorDismiss, AAnchorX, AAnchorY);
end;

procedure CloseDragLintHover;
begin
  if (GCurrentHover <> nil) and GCurrentHover.Visible then GCurrentHover.Close;
end;

function IsDragLintHoverVisible: Boolean;
begin
  Result:= (GCurrentHover <> nil) and GCurrentHover.Visible;
end;

function IsMouseOverDragLintHover: Boolean;
{ v0.42: True when the cursor is within the visible hover popup (+ a small
  margin). Lets the dwell tracker close the popup when the mouse leaves the
  editor WITHOUT killing the interactive menu popup the user is reaching for. }
var
  Pt: TPoint;
  R : TRect ;
begin
  Result:= False;
  if (GCurrentHover = nil) or not GCurrentHover.Visible then Exit;
  if not GetCursorPos(Pt) then Exit;
  R:= GCurrentHover.BoundsRect;
  InflateRect(R, 12, 12);
  Result:= PtInRect(R, Pt);
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
    GCurrentHover:= nil;
  end;
except
end;

end.
