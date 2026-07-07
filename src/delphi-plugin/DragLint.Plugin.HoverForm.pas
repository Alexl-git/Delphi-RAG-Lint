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
  , ToolsAPI
  , ToolsAPI.Editor
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
    Signature    : string                    ;
    UnitFile     : string                    ;
    DefLine      : Integer                   ;
    Params       : TArray<TDragLintHoverParam>;
    ReturnType   : string                    ;
    Returns      : TArray<string>            ;
    ReturnsMore  : Integer                   ;
  end;

  /// <summary>Logical syntax roles the hover body colors. Each maps to a real
  /// IDE editor color (Tools > Options > Editor) when available, falling back
  /// to the fixed CL_* palette otherwise; every color still passes through the
  /// WCAG contrast guard against the actual popup background.</summary>
  TDLSynRole = (srKeyword, srType, srName, srParam, srOperator, srLiteralNum, srLiteralStr, srMuted);

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
      { v0.42: dwell popups dismiss tightly -- the moment the cursor leaves a
      small box around the ORIGINAL dwell point (where the user was pointing),
      not the whole 900 px popup rect. This stops the popup lingering over the
      Projects/Messages pane and also clears it when the mouse leaves the
      editor (that motion necessarily exits the anchor box). Menu-invoked
      popups keep the generous popup-rect dismissal so they stay interactive. }
      FAnchorDismiss: Boolean;
      FDwellAnchor  : TPoint ;
      procedure HandleKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
      procedure HandleDeactivate    (Sender: TObject);
      procedure HandleTimerTick     (Sender: TObject);
      procedure HandleWatchTick     (Sender: TObject);
      procedure HandleCallerDblClick(Sender: TObject);
      procedure HandleCallerKey(Sender: TObject; var Key: Word; Shift: TShiftState);
      procedure HandleMemoClick(Sender: TObject);
      procedure HandleMemoMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
      function LineIsClickable(const ALineText: string): Boolean;
      { v0.94: colored + selectable Help-Insight body (TRichEdit). }
      procedure Emit(const AText: string; AColor: TColor; ABold: Boolean);
      function  GetSyntaxColor(ARole: TDLSynRole): TColor;
      procedure EmitSignatureHeader(const ASignature, AUnitFile: string; ADefLine: Integer);
      procedure RenderModel(const AModel: TDragLintHoverModel);
      { v0.94: shared final placement + no-steal-focus show, used by BOTH ShowAt
      overloads so the focus/dwell mechanics can never drift between them. }
      procedure PlaceAndShow(X, Y, W, H: Integer);
    protected
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
  , DRagLint.Hover.Contrast // EnsureReadable (T1)
  , DragLint.Plugin.Fonts   // GetIdeEditorFont (T5)
  ;

var
  GCurrentHover: TDragLintHoverForm = nil;

const
  { v0.94 fixed fallback palette (light-theme base). Used per-token when the IDE
    editor colors are unavailable. Every value is still run through the contrast
    guard against the actual background before it is emitted. TColor is BGR, so
    these bytes are the reverse of the #RRGGBB the comments name. }
  CL_KEYWORD = TColor($00D0570B); // #0B57D0 blue
  CL_TYPE    = TColor($003C7A21); // #217A3C green
  CL_NAME    = TColor($00DB561A); // #1A56DB
  CL_PARAM   = TColor($00C1426F); // #6F42C1
  CL_OP      = TColor($00333333);
  CL_LITNUM  = TColor($001515A3); // #A31515
  CL_LITSTR  = TColor($001515A3);
  CL_MUT     = TColor($008A8A8A);

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
      GHoverThemeRegistered:= True;
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
  Caption    := 'drag-lint hover';
  BorderStyle:= bsSizeToolWin;
  FormStyle  := fsStayOnTop;
  Color      := clWindow;
  KeyPreview := True;
  Position   := poDesigned;

  OnKeyDown:= HandleKeyDown;

  { v0.40.8e: top header label removed -- the title bar shows the same
    "drag-lint -- kind name -- unit.pas (line)" string and a duplicate
    inside the body is just visual noise. }

  { Bottom: callers ListView. Created BEFORE memo so alClient memo fills middle. }
  FCallers:= TListView.Create(Self);
  FCallers.Parent           := Self;
  FCallers.Align            := alBottom;
  FCallers.Height           := 130;
  FCallers.ViewStyle        := vsReport;
  FCallers.RowSelect        := True;
  FCallers.ReadOnly         := True;
  FCallers.GridLines        := False;
  FCallers.ShowColumnHeaders:= True;
  FCallers.HideSelection    := False;
  with FCallers.Columns.Add do begin Caption:= 'Unit'; Width:= 180; end;
  with FCallers.Columns.Add do begin Caption:= 'Line'; Width:= 50 ; end;
  with FCallers.Columns.Add do begin Caption:= 'Code'; Width:= 420; end;
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
  FBody.ScrollBars := ssVertical;
  FBody.Color      := clWindow;
  FBody.TabStop    := False;
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
    FCallers.Font.Name:= FN; FCallers.Font.Size:= FS;
  end
  else
  begin
    FBody.Font.Name   := 'Consolas'; FBody.Font.Size   := 9;
    FCallers.Font.Name:= 'Consolas'; FCallers.Font.Size:= 9;
  end;

  FCallerPaths:= TStringList.Create;

  FWatchTimer:= TTimer.Create(Self);
  FWatchTimer.Enabled := False;
  FWatchTimer.Interval:= 150;
  FWatchTimer.OnTimer := HandleWatchTick;

  { v0.46: follow the IDE light/dark theme (guarded; no-op on older IDEs). }
  ApplyIdeTheme(Self);
  { v0.94: after theming settled the form Color, sync the body background to it
    so the contrast guard (Emit -> EnsureReadable) computes against the color
    the text actually sits on. }
  FBody.Color:= Self.Color;
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
    if (LineIdx = 0) and (FModelQName <> '') and Assigned(GOnNavigateToQname) then
    begin
      Close;
      GOnNavigateToQname(FModelQName, FModelDefLine);
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
        Close;
        GOnAddUnit(AddUnit);
        Exit;
      end;
    end;
  end; // if

  { Gate: a definition row is "- <qname> - line N". Require the bullet, the
    " - line " separator, and a positive trailing integer so doc/blank lines
    (and ordinary "- bullet" prose) are left alone. }
  Body:= LineText.TrimLeft;
  if not Body.StartsWith('- ') then Exit;
  Body:= Copy(Body, 3, MaxInt); { drop the "- " bullet }

  DashAt:= Pos(' - line ', Body);
  if DashAt <= 0 then Exit;
  Qname:= Trim(Copy(Body, 1, DashAt - 1));
  LineStr:= Trim(Copy(Body, DashAt + Length(' - line '), MaxInt));
  LineN:= StrToIntDef(LineStr, 0);
  if (Qname = '') or (LineN <= 0) then Exit;

  UnitName:= UnitNameFromQname(Qname);
  if UnitName = '' then Exit;
  Close;
  { Prefer the Editor hook: it resolves the unit to its ABSOLUTE source path via
    the open project and forces the code view. The fallback OpenSourceAt is now
    guarded against the bare path (it no-ops rather than erroring). }
  if Assigned(GOnNavigateToQname) then GOnNavigateToQname(Qname, LineN)
  else OpenSourceAt(UnitName + '.pas', LineN);
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
  Body:= ALineText.TrimLeft;
  if not Body.StartsWith('- ') then Exit;
  Body:= Copy(Body, 3, MaxInt);
  DashAt:= Pos(' - line ', Body);
  if DashAt <= 0 then Exit;
  Result:= StrToIntDef(Trim(Copy(Body, DashAt + Length(' - line '), MaxInt)), 0) > 0;
end;

{ v0.46.x: show a hand cursor over clickable lines so users see they are links.
  EM_CHARFROMPOS maps the mouse point to a char index in the rich edit; on a
  multiline control its HIWORD is the line index.
  v0.94: for a structured (Help-Insight) popup the only clickable line is the
  header (0) -- the signature that navigates to the definition. }
procedure TDragLintHoverForm.HandleMemoMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
var
  Res    : Integer;
  LineIdx: Integer;
begin
  Res:= FBody.Perform(EM_CHARFROMPOS, 0, MakeLParam(X, Y));
  LineIdx:= HiWord(Cardinal(Res));
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
  FBody.SelStart := FBody.GetTextLen;
  FBody.SelLength:= 0;
  FBody.SelAttributes.Color:= Safe;
  if ABold then FBody.SelAttributes.Style:= [fsBold] else FBody.SelAttributes.Style:= [];
  FBody.SelText:= AText;
end;

function TDragLintHoverForm.GetSyntaxColor(ARole: TDLSynRole): TColor;
{ Real-color-with-fallback. When the IDE editor-color interface resolved for
  this render (FSynOpts, cached once per RenderModel) is available, return the
  user's configured GetFontColor for the mapped TOTASyntaxCode; on nil options,
  a clNone/clDefault result, or any exception, return the fixed CL_* fallback.
  Resolving happens ONCE per render (in RenderModel), never per token here. }
var
  Code    : TOTASyntaxCode;
  Fallback: TColor         ;
  C       : TColor         ;
begin
  case ARole of
    srKeyword   : begin Code:= atReservedWord; Fallback:= CL_KEYWORD; end;
    srType      : begin Code:= atIdentifier  ; Fallback:= CL_TYPE   ; end;
    srName      : begin Code:= atIdentifier  ; Fallback:= CL_NAME   ; end;
    srParam     : begin Code:= atIdentifier  ; Fallback:= CL_PARAM  ; end;
    srOperator  : begin Code:= atSymbol      ; Fallback:= CL_OP     ; end;
    srLiteralNum: begin Code:= atNumber      ; Fallback:= CL_LITNUM ; end;
    srLiteralStr: begin Code:= atString      ; Fallback:= CL_LITSTR ; end;
    srMuted     : begin Code:= atComment     ; Fallback:= CL_MUT    ; end;
  else
    begin Code:= atIdentifier; Fallback:= CL_NAME; end;
  end;

  Result:= Fallback;
  if FSynOpts = nil then Exit;
  try
    C:= FSynOpts.GetFontColor(Code);
    if (C <> clNone) and (C <> clDefault) then Result:= C;
  except
    Result:= Fallback; // any ToolsAPI surprise -> fixed fallback
  end;
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

procedure TDragLintHoverForm.RenderModel(const AModel: TDragLintHoverModel);
{ Clear the body and lay out the Help-Insight view: colored signature header
  (line 0, click-navigates), a "Parameters" block (one aligned
  `modifier name : type` line per param), and a "Returns" block (single
  `type : Result := expr` or a list of `Result := expr` lines + "... and N
  more"). Returns is omitted entirely for procedures (no return type, no mined
  returns). Resolves the IDE color interface ONCE here into FSynOpts. }
var
  Svcs     : INTACodeEditorServices;
  MaxNameLen: Integer              ;
  I         : Integer              ;
  P         : TDragLintHoverParam  ;
  NamePad   : string               ;
  HasReturns: Boolean              ;
begin
  FStructured   := True;
  FModelQName   := AModel.QualifiedName;
  FModelDefLine := AModel.DefLine;

  { Resolve the IDE editor-color interface once for this render (guarded, like
    Task 5's font read). On any failure FSynOpts stays nil and GetSyntaxColor
    returns the fixed CL_* fallbacks. }
  FSynOpts:= nil;
  try
    if Supports(BorlandIDEServices, INTACodeEditorServices, Svcs) then FSynOpts:= Svcs.Options;
  except
    FSynOpts:= nil;
  end;

  FBody.Lines.BeginUpdate;
  try
    FBody.Clear;

    { (1) signature header -- colored, bold, clickable line 0. }
    EmitSignatureHeader(AModel.Signature, AModel.UnitFile, AModel.DefLine);

    { (2) Parameters. Align the colons: pad each name to MaxNameLen + 1. }
    if Length(AModel.Params) > 0 then
    begin
      Emit(sLineBreak + sLineBreak, GetSyntaxColor(srMuted), False);
      Emit('Parameters', GetSyntaxColor(srKeyword), True);
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
        Emit(P.TypeText, GetSyntaxColor(srType), False);
      end;
    end;

    { (3) Returns -- omitted for procedures (no return type AND no mined
      returns). Single mined value -> "type : Result := expr"; multiple ->
      a "type" header then one "Result := expr" per line, + "... and N more". }
    HasReturns:= (AModel.ReturnType <> '') or (Length(AModel.Returns) > 0);
    if HasReturns then
    begin
      Emit(sLineBreak + sLineBreak, GetSyntaxColor(srMuted), False);
      Emit('Returns', GetSyntaxColor(srKeyword), True);
      if Length(AModel.Returns) = 1 then
      begin
        Emit(sLineBreak + '  ', GetSyntaxColor(srMuted), False);
        if AModel.ReturnType <> '' then
        begin
          Emit(AModel.ReturnType, GetSyntaxColor(srType), False);
          Emit(' : ', GetSyntaxColor(srMuted), False);
        end;
        Emit('Result := ' + AModel.Returns[0], GetSyntaxColor(srName), False);
      end
      else
      begin
        if AModel.ReturnType <> '' then
        begin
          Emit(sLineBreak + '  ', GetSyntaxColor(srMuted), False);
          Emit(AModel.ReturnType, GetSyntaxColor(srType), False);
        end;
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
  MaxLen      : Integer  ;
  CleanSummary: string   ;
begin
  FStructured   := False; { legacy string path -> definition-row click parsing }
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

  FCallerPaths.Clear;
  FCallers.Items.BeginUpdate;
  try
    FCallers.Items.Clear;
    for I:= 0 to High(ACallers) do
    begin
      LI:= FCallers.Items.Add;
      ShortName:= ExtractFileName(ACallers[I].FilePath);
      LI.Caption:= ShortName;
      LI.SubItems.Add(IntToStr(ACallers[I].Line));
      LI.SubItems.Add(ACallers[I].CodeText);
      FCallerPaths.Add(ACallers[I].FilePath);
    end;
  finally
    FCallers.Items.EndUpdate;
  end;

  { Sizing: header 22 + summary lines * 16 + callers (header + rows * 18).
    v0.46: size to the CLEANED text (fewer blank lines after the trim). }
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
    CallersH:= 28 + Length(ACallers) * 18;
    if CallersH < 60 then CallersH:= 60;
    if CallersH > 200 then CallersH:= 200;
    FCallers.Height:= CallersH;
  end;

  { v0.42: dwell popups size to their content width (the summary is short --
    a couple of declaration lines) instead of the fixed 900 px, so they don't
    blanket the panes behind the editor. Consolas 9 pt ~ 7 px/char. Menu
    popups keep the full width because they carry the callers grid. }
  if AAnchorDismiss then
  begin
    MaxLen:= Length(AHeader);
    for Ln in CleanSummary.Split([#10]) do
      if Length(Ln.TrimRight) > MaxLen then MaxLen:= Length(Ln.TrimRight);
    W:= 40 + MaxLen * 7;
    if W < 200 then W:= 200;
    if W > MAX_W then W:= MAX_W;
  end
  else W:= MAX_W;
  H:= HeaderH + SummaryH + CallersH + PAD * 2;
  if H > MAX_H then H:= MAX_H;
  if H < 120 then H:= 120;

  PlaceAndShow(X, Y, W, H);
end; // procedure

procedure TDragLintHoverForm.PlaceAndShow(X, Y, W, H: Integer);
{ v0.94: the final size + on-screen placement + no-steal-focus show, factored
  out of the string ShowAt so the structured ShowAt shares the EXACT same
  window mechanics (dwell-timer start, WS_EX_NOACTIVATE topmost show, and the
  capture/restore-foreground+focus dance that keeps the editor caret alive).
  Callers pass the already-computed W/H; anchor state (FAnchorDismiss/
  FDwellAnchor) is set by the caller before this runs. }
var
  MonR: TRect;
begin
  Width := W;
  Height:= H;

  if SystemParametersInfo(SPI_GETWORKAREA, 0, @MonR, 0) then
  begin
    if X + W > MonR.Right  then X:= MonR.Right  - W;
    if Y + H > MonR.Bottom then Y:= MonR.Bottom - H;
    if X < MonR.Left then X:= MonR.Left;
    if Y < MonR.Top  then Y:= MonR.Top;
  end;
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
  MAX_W = 900;
  MAX_H = 700;
  PAD   = 8;
var
  I       : Integer  ;
  LI      : TListItem;
  W       : Integer  ;
  H       : Integer  ;
  CallersH: Integer  ;
  BodyH   : Integer  ;
  BodyLines: Integer ;
  ShortName: string  ;
begin
  FAnchorDismiss:= AAnchorDismiss;
  if AAnchorX >= 0 then FDwellAnchor:= Point(AAnchorX, AAnchorY)
  else FDwellAnchor:= Point(X, Y);

  { Render the colored, selectable Help-Insight body (sets FStructured := True,
    FModelQName/FModelDefLine for the clickable header). }
  RenderModel(AModel);

  { Title bar: "drag-lint -- <qname>" (no file/line -- the header line carries
    the unit + line already). }
  if AModel.QualifiedName <> '' then Caption:= 'drag-lint -- ' + AModel.QualifiedName
  else Caption:= 'drag-lint hover';

  FCallerPaths.Clear;
  FCallers.Items.BeginUpdate;
  try
    FCallers.Items.Clear;
    for I:= 0 to High(ACallers) do
    begin
      LI:= FCallers.Items.Add;
      ShortName:= ExtractFileName(ACallers[I].FilePath);
      LI.Caption:= ShortName;
      LI.SubItems.Add(IntToStr(ACallers[I].Line));
      LI.SubItems.Add(ACallers[I].CodeText);
      FCallerPaths.Add(ACallers[I].FilePath);
    end;
  finally
    FCallers.Items.EndUpdate;
  end;

  { Sizing: body sized to its actual rendered line count (header + params +
    returns), callers grid same rule as the string path. Structured hovers keep
    the full width so long signatures + the callers grid fit. }
  BodyLines:= FBody.Lines.Count;
  if BodyLines < 3 then BodyLines:= 3;
  BodyH:= 22 + BodyLines * 16;
  if BodyH < 60  then BodyH:= 60;
  if BodyH > 320 then BodyH:= 320;

  if Length(ACallers) = 0 then
  begin
    FCallers.Visible:= False;
    CallersH:= 0;
  end
  else
  begin
    FCallers.Visible:= True;
    CallersH:= 28 + Length(ACallers) * 18;
    if CallersH < 60  then CallersH:= 60;
    if CallersH > 200 then CallersH:= 200;
    FCallers.Height:= CallersH;
  end;

  W:= MAX_W;
  H:= BodyH + CallersH + PAD * 2;
  if H > MAX_H then H:= MAX_H;
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
