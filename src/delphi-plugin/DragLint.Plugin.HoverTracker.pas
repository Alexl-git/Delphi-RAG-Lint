unit DragLint.Plugin.HoverTracker;

(* Caret-based hover tooltip for drag-lint (v0.35 -> v0.40.3).

   v0.35 behaviour:
     A TTimer fires every 200ms. When the mouse cursor is stable for >= 3
     ticks (600ms) we check the active editor's caret row in the diagnostic
     cache. If a diagnostic exists on that row, we call ShowDragLintHover.

   v0.40.3 extension:
     In addition to the diagnostic lookup, we now fire textDocument/hover
     against the shared LSP client (via QueryHoverText) for the current
     caret position. The two strings -- diagnostic + symbol info -- are
     combined into one popup. If either is empty the other is shown alone;
     if both are empty we suppress the popup (no change from v0.35).

   Performance:
     LSP queries only fire once per stable (file, line, col) tuple -- see
     FLastLspKey. Cursor wobble or repeated dwell on the same position doesn't
     requery the LSP.

   2026-10-29 (owner: whatever gets stuck in DL must not make the IDE stuck):
     the dwell no longer waits. ONE async hoverBundle request is in flight at a
     time; a dwell elsewhere cancels it ($/cancelRequest). The answer is shown
     only if the pointer is still over the same editor control and the same
     token (DragLint.Plugin.HoverGate). A busy engine gets no new hover and the
     status strip says 'drag-lint: engine busy'. The tick also runs the stuck-
     engine watchdog.

   Known limitation (still present):
     Uses caret row, not pixel-to-token mapping. OTAPI doesn't expose
     reliable mouse->token resolution without brittle font-metrics
     arithmetic. Caret-based is sufficient until OTAPI gains the hook. *)

interface

procedure StartHoverTracker;
procedure StopHoverTracker;

implementation

uses
  System.SysUtils
  , System.Classes
  , Vcl.Forms
  , Vcl.Controls
  , Vcl.ExtCtrls
  , Winapi.Windows
  , ToolsAPI
  , DragLint.Plugin.DiagnosticCache
  , DragLint.Plugin.HoverForm
  , DragLint.Plugin.Settings
  , DragLint.Plugin.LspClient
  , DragLint.Plugin.EditViewNotifier
  , DragLint.Plugin.Editor
  , DragLint.Plugin.DockForm     { SelectDockedDiagnosticForLine -- caret -> panel }
  , DragLint.Plugin.StatusBar    { SetDragLintNote -- the 'thinking' note }
  , DragLint.Plugin.Telemetry    { DLT -- item 5: where a dwell fired, and whether it showed }
  , DragLint.Plugin.HoverGate    { DLHoverGate -- the async answer's show-gate }
  ;

function IdeIsForeground: Boolean;
{ v0.40.8b: process-ID comparison is the only check that works across
  every IDE window (docked editor, floating tab, property inspector,
  structure pane). The plugin BPL runs inside the IDE process; if the
  foreground window also belongs to that process, the IDE has focus.
  IsChild + GetAncestor failed for floating editor tabs (their root is
  the float container, not the AppBuilder main form). }
var
  Fg : HWND ;
  Pid: DWORD;
begin
  Result:= False;
  Fg    := GetForegroundWindow;
  if Fg = 0 then Exit;
  Pid:= 0;
  GetWindowThreadProcessId(Fg, Pid);
  Result:= (Pid <> 0) and (Pid = GetCurrentProcessId);
end;

function IsMouseOverEditorView(const APt: TPoint): Boolean;
{ v0.40.8d: dwell must fire only when the mouse is over the active editor
  view's window -- not the project manager, structure pane, message pane,
  property inspector, ribbon, status bar, etc. Without this, parking the
  mouse anywhere in the IDE for 1.6 s fires the popup based on the last
  editor caret position, completely disconnected from where the user is
  pointing. Uses IOTAEditView.GetEditWindow.Form.BoundsRect (the whole
  editor dock pane, including its tabs/scrollbars -- fine for this check). }
var
  ESS     : IOTAEditorServices;
  EditView: IOTAEditView      ;
  F       : TCustomForm       ;
  R       : TRect             ;
begin
  Result:= False;
  if not Supports(BorlandIDEServices, IOTAEditorServices, ESS) then Exit;
  EditView:= ESS.TopView;
  if EditView = nil then Exit;
  F:= EditView.GetEditWindow.Form;
  if F = nil then Exit;
  if not GetWindowRect(F.Handle, R) then Exit;
  Result:= PtInRect(R, APt);
end;

{ 2026-10-29: the IDE editor control's window class. WindowFromPoint naming it
  is what "the mouse is over the editor" means -- the edit window FORM's
  rectangle also contains docked panes (Project Manager, Structure), which is
  how popups used to appear over them. }
const
  EDITOR_CONTROL_CLASS = 'TEditControl';
  { Half-size in px of the fallback show-gate box, used before the editor grid
    has been painted once. }
  FALLBACK_HALF_BOX = 8;
  { The dwell popup opens this far below the pointer (unchanged since v0.42). }
  POPUP_BELOW_PX = 20;

function ClassNameOf(AHwnd: HWND): string;
var
  Buf: array[0..255] of Char;
begin
  SetString(Result, Buf, GetClassName(AHwnd, Buf, Length(Buf)));
end;

{ The editor control under the pointer, or 0. The control the gutter painter
  last drew into counts as one even if its class name were ever to change. }
function EditorControlAt(const APt: TPoint): HWND;
var
  H: HWND;
begin
  Result:= 0;
  H:= WindowFromPoint(APt);
  if H = 0 then Exit;
  if (H = GGutterAnchorHwnd) or SameText(ClassNameOf(H), EDITOR_CONTROL_CLASS) then Result:= H;
end;

{ One line of the view's buffer (1-based row), or '' when unreadable. }
function BufferLineText(const AView: IOTAEditView; ARow1: Integer): string;
const
  LINE_BUF = 1024;
var
  CP    : TOTACharPos;
  Reader: IOTAEditReader;
  Buf   : array[0..LINE_BUF - 1] of AnsiChar;
  N     : Integer;
  Eol   : Integer;
begin
  Result:= '';
  try
    if (AView = nil) or (AView.Buffer = nil) or (ARow1 < 1) then Exit;
    CP.Line     := ARow1;
    CP.CharIndex:= 0;
    Reader:= AView.Buffer.CreateReader;
    if Reader = nil then Exit;
    N:= Reader.GetText(AView.CharPosToPos(CP), Buf, LINE_BUF);
    if N <= 0 then Exit;
    Eol:= 0;
    while (Eol < N) and (Buf[Eol] not in [#10, #13]) do Inc(Eol);
    SetString(Result, PAnsiChar(@Buf[0]), Eol);
  except
    on E: Exception do Result:= '';   { an unreadable buffer is no token: the fallback box applies }
  end;
end;

type
  TDragLintHoverHelper = class
    private
      FTimer             : TTimer ;
      FLastPos           : TPoint ;
      FStableCount       : Integer;
      FHintShown         : Boolean;
      FLastLspKey        : string ; { v0.40.3: position the cached answer below belongs to }
      FLastLspText       : string ; { v0.40.3: cached symbol info for FLastLspKey }
      { v(hover bundle): the model + callers that came back with FLastLspText in
        the SAME request, cached alongside it so a re-show does no engine work.
        FLastBundleOk False means only plain markdown is cached -- it is NOT the
        same as "this symbol has no callers". }
      FLastBundleOk      : Boolean;
      FLastBundleModel   : TDragLintHoverModel        ;
      FLastBundleCallers : TArray<TDragLintCallerInfo>;
      FLastShownKey      : string ; { v0.42: position we already popped; don't re-show it }
      { v(session 73): last caret LINE the panel selection was driven from. }
      FLastCaretLine     : Integer;
      FLastCaretFile     : string ;
      FLastForegroundFail: Boolean; { v0.40.8b: log the bail-out only once per transition }
      { 2026-10-29: the ONE hover request in flight (0 = none), the client it
        went to, and everything the answer needs to decide whether -- and
        where -- to show. }
      FInflightId        : Integer                    ;
      FInflightClient    : TDragLintLspClient         ;
      FInflightKey       : string                     ;
      FInflightUri       : string                     ;
      FInflightRow       : Integer                    ;
      FInflightCol       : Integer                    ;
      FInflightPos       : TPoint                     ;
      FInflightAnchor    : TDLHoverAnchor             ;
      FInflightDiags     : TArray<TDragLintDiagnostic>;
      FInflightDiagText  : string                     ;
      procedure OnTick(Sender: TObject);
      { v(session 73): editor caret line -> drag-lint panel selection. }
      procedure DriveCaretPanelSelection;
      procedure ResetState;
      procedure CancelInflight;
      procedure OnHoverBundleAnswer(AId: Integer; AStatus: TDLHoverStatus;
        const AMarkdown, AQName: string; const AModel: TDragLintHoverModel;
        const ACallers: TArray<TDragLintCallerInfo>);
      procedure OnHoverTextAnswer(AId: Integer; AStatus: TDLHoverStatus; const AMarkdown: string);
      procedure GateAndShowInflight;
      procedure ShowHoverPopup(const APos: TPoint; const AKey, ALspText: string;
        const AModel: TDragLintHoverModel; const ACallers: TArray<TDragLintCallerInfo>;
        const ADiags: TArray<TDragLintDiagnostic>; const ADiagText: string);
    public
      constructor Create;
      destructor Destroy; override;
  end;


var
  GHelper: TDragLintHoverHelper = nil;

constructor TDragLintHoverHelper.Create;
begin
  inherited;
  FTimer:= TTimer.Create(nil);
  FTimer.Interval:= 200;
  FTimer.OnTimer := OnTick;
  FTimer.Enabled := True;
  FLastPos:= Point(-1, -1);
  FStableCount:= 0;
  FHintShown  := False;
  FLastCaretLine:= -1;
  FLastCaretFile:= '';
end;

destructor TDragLintHoverHelper.Destroy;
begin
  FTimer.Free;
  { No answer may arrive for a helper that is gone. }
  CancelInflight;
  inherited;
end;

procedure TDragLintHoverHelper.ResetState;
begin
  FStableCount:= 0;
  FHintShown  := False;
end;

procedure TDragLintHoverHelper.CancelInflight;
begin
  { Only cancel against the client the request went to, and only while it is
    still the live one -- a replaced client has already dropped the callback. }
  if (FInflightId <> 0) and (FInflightClient <> nil) and (FInflightClient = CurrentLspClient) then
    FInflightClient.CancelRequest(FInflightId);
  FInflightId    := 0;
  FInflightClient:= nil;
end;

procedure TDragLintHoverHelper.OnHoverBundleAnswer(AId: Integer; AStatus: TDLHoverStatus;
  const AMarkdown, AQName: string; const AModel: TDragLintHoverModel;
  const ACallers: TArray<TDragLintCallerInfo>);
begin
  try
    if AId <> FInflightId then Exit;   { superseded: a newer hover owns the slot }
    DLT('hover', Format('bundle answer id=%d status=%d qname="%s"', [AId, Ord(AStatus), AQName]));
    FInflightId    := 0;
    case AStatus of
      hvsUnsupported:
        begin
          { An engine without the bundle: ask the plain hover now, still async. }
          FInflightId:= RequestHoverTextAsync(FInflightUri, FInflightRow, FInflightCol, OnHoverTextAnswer);
          if FInflightId = 0 then FInflightClient:= nil;
          Exit;
        end;
      hvsTimeout:
        begin
          FInflightClient:= nil;
          SetDragLintNote('drag-lint: engine busy');
          Exit;
        end;
    end;
    FInflightClient   := nil;
    FLastLspKey       := FInflightKey;
    FLastLspText      := AMarkdown;
    FLastBundleOk     := AStatus = hvsOk;
    FLastBundleModel  := AModel;
    FLastBundleCallers:= ACallers;
    GateAndShowInflight;
  except
    { main-thread callback inside the IDE: never let it raise }
    on E: Exception do DLT('hover', 'bundle answer raised: ' + E.Message);
  end;
end;

procedure TDragLintHoverHelper.OnHoverTextAnswer(AId: Integer; AStatus: TDLHoverStatus; const AMarkdown: string);
begin
  try
    if AId <> FInflightId then Exit;
    FInflightId    := 0;
    FInflightClient:= nil;
    if AStatus = hvsTimeout then
    begin
      SetDragLintNote('drag-lint: engine busy');
      Exit;
    end;
    FLastLspKey       := FInflightKey;
    FLastLspText      := AMarkdown;
    FLastBundleOk     := False;
    FLastBundleModel  := Default(TDragLintHoverModel);
    SetLength(FLastBundleCallers, 0);
    GateAndShowInflight;
  except
    on E: Exception do DLT('hover', 'text answer raised: ' + E.Message);
  end;
end;

{ The owner's show-gate (2026-10-29): the answer is shown only while the pointer
  is still over the editor control the dwell started in AND on the same token
  -- see DragLint.Plugin.HoverGate. Otherwise it is discarded (and stays cached,
  so pointing back at the token shows it at once). }
{ The 0-based buffer cell under a SCREEN point NOW, through the grid the gutter
  painter publishes -- the same arithmetic OnTick uses to ask the question, so a
  wheel scroll (GGutterAnchorLine moved) or an edit lands on a different cell
  under a stationary pointer. False (-1, -1) when no grid is painted or the
  point is left of the text. }
function PointerCellNow(const AScreenPt: TPoint; out ARow0, ACol0: Integer): Boolean;
var
  Pt  : TPoint ;
  DY  : Integer;
  ROff: Integer;
begin
  ARow0:= -1;
  ACol0:= -1;
  Result:= False;
  if (GGutterAnchorHwnd = 0) or (GGutterLineHeight <= 0) or (GGutterCharWidth <= 0) then Exit;
  Pt:= AScreenPt;
  if not ScreenToClient(GGutterAnchorHwnd, Pt) then Exit;
  if Pt.X < GGutterTextLeft then Exit;
  DY:= Pt.Y - GGutterAnchorTopY;
  if DY >= 0 then ROff:= DY div GGutterLineHeight
  else ROff:= -((-DY + GGutterLineHeight - 1) div GGutterLineHeight);
  ARow0:= (GGutterAnchorLine + ROff) - 1;
  ACol0:= (Pt.X - GGutterTextLeft) div GGutterCharWidth;
  Result:= ARow0 >= 0;
  if not Result then
  begin
    ARow0:= -1;
    ACol0:= -1;
  end;
end;

procedure TDragLintHoverHelper.GateAndShowInflight;
var
  NowPt  : TPoint;
  Client : TPoint;
  Verdict: TDLHoverGateVerdict;
  NowRow0: Integer;
  NowCol0: Integer;
begin
  GetCursorPos(NowPt);
  Client:= NowPt;
  if FInflightAnchor.Hwnd <> 0 then ScreenToClient(FInflightAnchor.Hwnd, Client);
  PointerCellNow(NowPt, NowRow0, NowCol0);
  Verdict:= DLHoverGate(FInflightAnchor, EditorControlAt(NowPt), Client, NowRow0, NowCol0);
  if (Verdict <> hgvShow) or not IdeIsForeground or not LoadSettings.EnableHoverTooltip then
  begin
    DLT('hover', Format('answer discarded: gate=%d (pointer left the token / editor)', [Ord(Verdict)]));
    SetDragLintNote('');
    { Re-arm: the next dwell at this spot shows the cached answer. }
    FHintShown:= False;
    Exit;
  end;
  ShowHoverPopup(NowPt, FInflightKey, FLastLspText, FLastBundleModel,
    FLastBundleCallers, FInflightDiags, FInflightDiagText);
end;

procedure TDragLintHoverHelper.ShowHoverPopup(const APos: TPoint; const AKey, ALspText: string;
  const AModel: TDragLintHoverModel; const ACallers: TArray<TDragLintCallerInfo>;
  const ADiags: TArray<TDragLintDiagnostic>; const ADiagText: string);
var
  Combined    : string;
  Model       : TDragLintHoverModel;
  GotModel    : Boolean;
  DwellCallers: TArray<TDragLintCallerInfo>;
begin
  { Combine the two -- symbol info first, diagnostic underneath. }
  Combined:= ALspText;
  if ADiagText <> '' then
  begin
    if Combined <> '' then Combined:= Combined + #13#10 + '---' + #13#10;
    Combined:= Combined + ADiagText;
  end;

  { Item 5 (over-eagerness): one line per dwell that reaches this decision, so a
    popup "in non-code areas" is locatable (shown=0 is a correct decline). }
  DLT('hover', Format('dwell %s model=%d lspLen=%d diagLen=%d shown=%d',
    [AKey, Ord(AModel.QualifiedName <> ''), Length(ALspText), Length(ADiagText), Ord(Combined <> '')]));

  { THE NOTE MUST DIE ON EVERY PATH (2026-08-27: "hover TDeltaBatch forever").
    "Asked and got nothing back" stays distinguishable from "here is the popup". }
  if Combined = '' then
  begin
    SetDragLintNote('drag-lint: hover -- nothing indexed at the cursor');
    Exit;
  end;

  FHintShown:= True;
  SetLength(DwellCallers, 0);
  { v0.40.8f: snap-to-symbol -- close any stale popup before showing the new one. }
  CloseDragLintHover;
  { v0.94.1: PREFER the structured Help-Insight model; since v(hover-both) the
    line's findings are carried INTO it as their own section. Without a model
    (intrinsic, or an engine without the bundle) the string popup shows -- no
    CLI spawn from this path any more (2026-10-29). }
  Model   := AModel;
  GotModel:= Model.QualifiedName <> '';   { only a bundle answer carries one }
  SetDragLintNote('');   { the popup below IS the answer }
  if GotModel then
  begin
    SetLength(Model.Diagnostics, 0);
    for var MDI:= 0 to High(ADiags) do
    begin
      var MMsg: string:= ADiags[MDI].Message;
      if ADiags[MDI].Code <> '' then MMsg:= '[' + ADiags[MDI].Code + '] ' + MMsg;
      if System.Pos('add unit ', LowerCase(ADiags[MDI].Message)) > 0 then MMsg:= MMsg + '   <-- click to add'; // dl:ok concat-in-loop@154f -- one suffix per finding on ONE line (a handful), not an accumulation
      SetLength(Model.Diagnostics, Length(Model.Diagnostics) + 1);
      Model.Diagnostics[High(Model.Diagnostics)]:= MMsg;
    end;
    { v0.42: dwell popups dismiss against the original mouse point. }
    ShowDragLintHover(Model, ACallers, APos.X, APos.Y + POPUP_BELOW_PX, True, APos.X, APos.Y);
  end
  else
  begin
    var DwellHeader: string:= ExtractHoverHeader(Combined);
    Combined:= StripFirstHeaderLine(Combined);
    ShowDragLintHover(DwellHeader, Combined, DwellCallers, APos.X, APos.Y + POPUP_BELOW_PX, True, APos.X, APos.Y);
  end;
  FLastShownKey:= AKey; { v0.42: don't re-pop this same position }
end;


{ v(session 73): caret line -> panel selection.
  docs\INBOX-caret-line-should-select-its-finding-in-the-panel.md.

  WHY IT SITS BEFORE EVERY BAIL-OUT IN OnTick. The rest of that method exits
  early when the hover TOOLTIP is switched off, and again when the MOUSE is not
  over the editor view. Both are right for a tooltip and both are wrong here:
  the ask is about where the CARET is, and a user reading the panel has usually
  parked the mouse over the panel, not the code. Wiring this in after those
  guards would have produced a feature that works only while the mouse hovers
  the editor -- which is the shape a reviewer would never notice and a user
  would report as "it works sometimes".

  RE-ENTRANCY (the note's design point 1) is closed by construction, not by a
  flag: this drives editor -> panel only, and SelectDockedDiagnosticForLine
  neither moves the caret nor focuses the panel, so the loop the note warns
  about -- select row, jump editor, caret moves, select row -- has no return
  edge to close it.

  COST (design point 5): guarded on a LINE change, so holding a key down inside
  one line does nothing, and the work when it does fire is a walk of the
  Diagnostics root's children -- tens of nodes -- not of the whole tree. }
procedure TDragLintHoverHelper.DriveCaretPanelSelection;
var
  ESS     : IOTAEditorServices;
  EditView: IOTAEditView      ;
  FilePath: string            ;
  Line    : Integer           ;
begin
  if not Supports(BorlandIDEServices, IOTAEditorServices, ESS) then Exit;
  EditView:= ESS.TopView;
  if EditView = nil then Exit;

  FilePath:= EditView.Buffer.FileName;
  if FilePath = '' then Exit;

  Line:= EditView.Position.Row; { 1-based, which is what the panel stores }
  if (Line = FLastCaretLine) and SameText(FilePath, FLastCaretFile) then Exit;

  FLastCaretLine:= Line;
  FLastCaretFile:= FilePath;

  { Return value ignored on purpose: False means "no finding on this line",
    which is not a failure and has already had its effect (the selection was
    cleared). }
  SelectDockedDiagnosticForLine(Line);
end;

procedure TDragLintHoverHelper.OnTick(Sender: TObject);
var
  Settings: TDragLintSettings          ;
  Pos     : TPoint                     ;
  ESS     : IOTAEditorServices         ;
  EditView: IOTAEditView               ;
  FilePath: string                     ;
  CaretRow: Integer                    ;
  CaretCol: Integer                    ;
  Diags   : TArray<TDragLintDiagnostic>;
  LspKey  : string                     ;
  DiagText: string                     ;
  Uri     : string                     ;
  Client  : TDragLintLspClient         ;
  Anchor  : TDLHoverAnchor             ;
  UnderHwnd: HWND                      ;
begin
  try
    Settings:= LoadSettings;

    { v(session 73): caret -> panel selection, BEFORE the tooltip guards below.
      It is a different feature on the same tick and must not inherit the
      tooltip's on/off switch or its mouse-over-the-editor requirement. See
      DriveCaretPanelSelection's header. }
    try DriveCaretPanelSelection; except // dl:ok try-except-swallowed@6b30 -- a timer tick must not raise into the IDE message loop
      on E: Exception do
        { Isolated from the tooltip path deliberately: a fault in the panel
          link must not take the tooltip down with it, and vice versa. }
        ;
    end;

    { WATCHDOG (2026-10-29): an engine silent for 60 s with requests pending is
      restarted through the normal EnsureLspClient path, even while nobody is
      dwelling -- otherwise a stuck engine would only be noticed by the next
      feature that needs it. Cheap: two lock-guarded reads per tick. }
    if (CurrentLspClient <> nil) and CurrentLspClient.IsStuck then EnsureLspClient;

    if not Settings.EnableHoverTooltip then
    begin
      ResetState;
      Exit;
    end;

    { v0.40.8: bail out if the IDE isn't the foreground app. Prevents the
      popup from covering whatever else the user is typing into (VS Code,
      browser, etc.) when the cursor happens to sit over the IDE. }
    if not IdeIsForeground then
    begin
      if not FLastForegroundFail then FLastForegroundFail:= True;
      ResetState;
      Exit;
    end;
    FLastForegroundFail:= False;

    GetCursorPos(Pos);

    { v0.40.8d: must be over the editor view's form rect, not the project
      manager / structure / messages / etc. Without this the dwell fires
      whenever the cursor parks anywhere in the IDE, based on whatever
      symbol the caret happens to sit on -- completely disconnected from
      what the user is pointing at. }
    { 2026-10-29: AND the window under the pointer must be the editor control
      itself. The form rectangle alone also covers docked panes (Project
      Manager, Structure), which is how popups appeared over them. }
    UnderHwnd:= EditorControlAt(Pos);
    if (not IsMouseOverEditorView(Pos)) or (UnderHwnd = 0) then
    begin
      { v0.42: mouse left the editor view -> clear the popup so it never lingers
        over the Project Manager / Messages / other panes. Keep it alive only
        while the cursor is actually over the popup (so the interactive menu
        popup the user is reaching for isn't yanked away). }
      if IsDragLintHoverVisible and not IsMouseOverDragLintHover then CloseDragLintHover;
      ResetState;
      Exit;
    end;

    { v0.46: tolerate small mouse jitter. Exact-pixel equality almost never held
      for a full dwell (a real hand wobbles 1-2 px), so the popup rarely fired.
      Treat motion within 4 px of the anchor as "stable"; only a real move
      re-anchors + resets. }
    if (Abs(Pos.X - FLastPos.X) <= 4) and (Abs(Pos.Y - FLastPos.Y) <= 4) then Inc(FStableCount)
    else
    begin
      ResetState;
      FLastPos:= Pos; { re-anchor only when the cursor really moved }
    end;

    { v0.46: 5 ticks * 200 ms = 1.0 s dwell (was 1.6 s) -- snappier, and the
      jitter tolerance above keeps it from firing on casual drift.
      v(hover-follows-mouse): 3 ticks = 0.6 s. The reported "takes much longer to
      pop up than the IDE's own" is this dwell plus the work that follows it, and
      the dwell was the part under our control: RAD Studio's Code Insight hover
      arms at roughly half a second, so a 1.0 s dwell always lost the race even
      when the query itself was instant. The remaining latency is the `hover
      --json` PROCESS SPAWN in TryBuildHoverModel -- an out-of-process CLI start
      plus an index open, which no dwell tuning can hide; closing that gap means
      serving the model from the already-running LSP connection instead. }
    if FStableCount < 3 then Exit;

    { Already showed for this stable position }
    if FHintShown then Exit;

    { v0.40.6: don't compete with an already-visible popup. ResetState above
      means FHintShown is False on every mouse move, so without this guard
      the popup would re-anchor at every mouse stop ("jumping around"). }
    if IsDragLintHoverVisible then
    begin
      FHintShown:= True;
      Exit;
    end;

    { Query the active editor's caret row + column }
    if not Supports(BorlandIDEServices, IOTAEditorServices, ESS) then Exit;
    EditView:= ESS.TopView;
    if EditView = nil then Exit;

    FilePath:= EditView.Buffer.FileName;
    if FilePath = '' then Exit;

    { v0.46: GUTTER-glyph hover. Map the MOUSE screen point to an editor row via
      the anchor the painter publishes, and if the cursor is over the gutter
      (x < text start) on a line that has diagnostics, show that line's
      message(s). This is independent of the caret -- it's true mouse hover. }
    if (GGutterAnchorHwnd <> 0) and (GGutterLineHeight > 0) then
    begin
      var CliPt: TPoint:= Pos;
      if ScreenToClient(GGutterAnchorHwnd, CliPt) then
      begin
        var DeltaY: Integer:= CliPt.Y - GGutterAnchorTopY;
        var RowOff: Integer                              ;
        if DeltaY >= 0 then RowOff:= DeltaY div GGutterLineHeight
        else RowOff:= -((-DeltaY + GGutterLineHeight - 1) div GGutterLineHeight);
        var MouseRow1: Integer:= GGutterAnchorLine + RowOff; { 1-based }
        if (CliPt.X >= 0) and (CliPt.X < GGutterTextLeft) and (MouseRow1 >= 1) then
        begin
          var GDiags:= Cache.GetForLine(FilePath, MouseRow1 - 1);
          if Length(GDiags) > 0 then
          begin
            var GMsg: string:= '';
            for var GI:= 0 to High(GDiags) do
            begin
              if GMsg <> '' then GMsg:= GMsg + #13#10;
              if GDiags[GI].Code <> '' then GMsg:= GMsg + '[' + GDiags[GI].Code + '] ';
              GMsg:= GMsg + GDiags[GI].Message;
              { v0.46 lightbulb hint }
              if System.Pos('add unit ', LowerCase(GDiags[GI].Message)) > 0 then GMsg:= GMsg + '   <-- click to add';
            end;
            FHintShown:= True;
            var GEmpty: TArray<TDragLintCallerInfo>;
            SetLength(GEmpty, 0);
            CloseDragLintHover;
            ShowDragLintHover('Diagnostics', GMsg, GEmpty, Pos.X + 18, Pos.Y + 8, True, Pos.X, Pos.Y);
            FLastShownKey:= Format('gutter|%s|%d', [FilePath, MouseRow1]);
            Exit;
          end; // if
        end; // if
      end; // if
    end; // if

    { Fallback anchor (no painted grid yet): a small box around the dwell
      point in the control under the pointer -- the answer still has to land
      where it was asked. Replaced below when the grid is known. }
    begin
      var BoxPt: TPoint:= Pos;
      ScreenToClient(UnderHwnd, BoxPt);
      Anchor:= DLHoverAnchorFor(UnderHwnd, BoxPt.X - FALLBACK_HALF_BOX, 1,
        BoxPt.Y - FALLBACK_HALF_BOX, 2 * FALLBACK_HALF_BOX, 0, 2 * FALLBACK_HALF_BOX, -1);
    end;

    { IOTAEditView.Position is 1-based; LSP / diagnostic cache is 0-based }
    CaretRow:= EditView.Position.Row    - 1;
    CaretCol:= EditView.Position.Column - 1;
    if CaretRow < 0 then CaretRow:= 0;
    if CaretCol < 0 then CaretCol:= 0;

    { v(hover-follows-mouse): THE dwell-hover defect. The caret position above is
      where the user last CLICKED; the popup is placed at the MOUSE. So pointing at
      an identifier described whatever the caret happened to be sitting on -- a
      different token, and after switching tabs a token in a different unit
      entirely. That is the reported "fires in other tabs showing information for a
      different or previous popup": not a stale popup at all, but a correctly-fresh
      popup about the wrong symbol.

      It also explains the popup that never appears. FLastShownKey and FLastLspKey
      are keyed on (file,row,col); with caret coordinates every token on the line
      produced the SAME key, so after the first dwell the "already shown for this
      caret" guard above swallowed every later hover until the caret itself moved.

      Fix: map the pointer to a buffer cell with the grid the gutter painter
      publishes -- the same arithmetic the gutter branch above already uses for
      rows, plus the column now that GGutterCharWidth is exported. The IDE editor
      is fixed-pitch, so the division is exact. Falls back to the caret whenever
      the grid has not been painted yet (GGutter* zero) or the pointer is left of
      the text (the gutter branch above owns that case and has already returned).
      Safe against a split view / second tab: IsMouseOverEditorView(Pos) at the top
      of this timer already established that the pointer is over THIS view, so the
      coordinates and EditView.Buffer.FileName describe the same buffer. }
    if (GGutterAnchorHwnd <> 0) and (GGutterLineHeight > 0) and (GGutterCharWidth > 0) then
    begin
      var MPt: TPoint:= Pos;
      if ScreenToClient(GGutterAnchorHwnd, MPt) then
      begin
        var DY  : Integer:= MPt.Y - GGutterAnchorTopY;
        var ROff: Integer                            ;
        if DY >= 0 then ROff:= DY div GGutterLineHeight
        else ROff:= -((-DY + GGutterLineHeight - 1) div GGutterLineHeight);
        var MouseRow0: Integer:= (GGutterAnchorLine + ROff) - 1;  { 0-based }
        var MouseCol0: Integer:= (MPt.X - GGutterTextLeft) div GGutterCharWidth;
        if (MouseRow0 >= 0) and (MPt.X >= GGutterTextLeft) and (MouseCol0 >= 0) then
        begin
          CaretRow:= MouseRow0;
          CaretCol:= MouseCol0;
          { 2026-10-29: the show-gate's anchor -- the hovered identifier's span
            in the SAME grid, so the answer is shown only while the pointer is
            still on that token. Not on an identifier: the fallback box stays. }
          var TokS, TokE: Integer;
          if DLIdentSpanAt(BufferLineText(EditView, MouseRow0 + 1), MouseCol0, TokS, TokE) then
            Anchor:= DLHoverAnchorFor(GGutterAnchorHwnd, GGutterTextLeft, GGutterCharWidth,
              GGutterAnchorTopY + ROff * GGutterLineHeight, GGutterLineHeight, TokS, TokE, MouseRow0);
        end;
      end;
    end;

    { Pull cached diagnostic for this row, if any. }
    DiagText:= '';
    Diags:= Cache.GetForLine(FilePath, CaretRow);
    if Length(Diags) > 0 then
    begin
      DiagText:= Diags[0].Message;
      { v0.46 lightbulb hint -- the line is clickable to apply the fix. }
      if System.Pos('add unit ', LowerCase(DiagText)) > 0 then DiagText:= DiagText + '   <-- click to add';
    end;

    LspKey:= Format('%s|%d|%d', [FilePath, CaretRow, CaretCol]);

    { v0.42: show a given position's popup once; only a position change re-arms it. }
    if LspKey = FLastShownKey then
    begin
      FHintShown:= True;
      Exit;
    end;

    { Cached answer for this exact position: show at once, no engine work. }
    if LspKey = FLastLspKey then
    begin
      ShowHoverPopup(Pos, LspKey, FLastLspText, FLastBundleModel, FLastBundleCallers, Diags, DiagText);
      Exit;
    end;

    { 2026-10-29: ONE hover in flight. The same position still waiting: keep
      waiting. A different one: the old question is superseded -- drop it and
      tell the engine. }
    if FInflightId <> 0 then
    begin
      if (FInflightKey = LspKey) and (FInflightClient = CurrentLspClient) then
      begin
        FHintShown:= True;
        Exit;
      end;
      CancelInflight;
    end;

    { Diagnostics are local: when the engine cannot be asked they still show. }
    Client:= EnsureLspClient;
    if (Client = nil) or Client.IsBusy then
    begin
      if Client <> nil then SetDragLintNote('drag-lint: engine busy');
      FHintShown:= True;
      if DiagText <> '' then
      begin
        var NoCallers: TArray<TDragLintCallerInfo>;
        SetLength(NoCallers, 0);
        ShowHoverPopup(Pos, LspKey, '', Default(TDragLintHoverModel), NoCallers, Diags, DiagText);
      end;
      Exit;
    end;

    { Announce BEFORE the request (2026-08-19): a slow hover reads as THINKING
      rather than absent. Named through the SAME AnnounceHoverStart the menu
      path uses, so the two paths can never name the same caret differently. }
    AnnounceHoverStart;
    Uri:= 'file:///' + StringReplace(FilePath, '\', '/', [rfReplaceAll]);

    FInflightKey     := LspKey;
    FInflightClient  := Client;
    FInflightPos     := Pos;
    FInflightAnchor  := Anchor;
    FInflightDiags   := Diags;
    FInflightDiagText:= DiagText;
    FInflightUri     := Uri;
    FInflightRow     := CaretRow;
    FInflightCol     := CaretCol;
    FHintShown       := True;

    { ONE request for markdown + model + callers; shown when it arrives, if the
      pointer is still on the token (OnHoverAnswer). No serial fallback round
      trip and no CLI spawn on this path any more: an engine without the bundle
      gets the plain textDocument/hover, asked only after the bundle answered
      with an error. }
    FInflightId:= if HoverBundleUnsupported then RequestHoverTextAsync(Uri, CaretRow, CaretCol, OnHoverTextAnswer)
                  else RequestHoverBundleAsync(Uri, CaretRow, CaretCol, OnHoverBundleAnswer);
    if FInflightId = 0 then
    begin
      FInflightClient:= nil;
      SetDragLintNote('drag-lint: hover not sent -- engine not ready');
    end;

  except
    { Swallow all exceptions: this fires in a VCL timer inside the IDE.
      Any unhandled exception here would surface as an IDE crash or modal
      dialog. Silent failure is strongly preferred. }
  end; // try
end; // procedure

procedure StartHoverTracker;
begin
  if GHelper = nil then GHelper:= TDragLintHoverHelper.Create;
end;

procedure StopHoverTracker;
begin
  FreeAndNil(GHelper);
end;

initialization

finalization
StopHoverTracker;

end.
