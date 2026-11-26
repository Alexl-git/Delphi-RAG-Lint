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

   2026-11-25 (lane 1.54.1 HOVERNOTE): the dwell asks about the cell under the
     POINTER and about nothing else. The cell comes from the state of the editor
     control under the pointer (ToolsAPI.Editor: its own view, lines, folds and
     scroll). The grid the gutter painter published could never be used: its
     window is WindowFromDC of the IDE's memory DC, which is 0, so every dwell
     fell back to the CARET and the strip spoke about another place. No cell and
     the gutter: no question. *)

interface

uses
  ToolsAPI
  ;

/// <summary>The whole text of a view's buffer, as edited (unsaved changes included).</summary>
/// <param name="AView">The view; nil is allowed.</param>
/// <returns>The text; an empty string when it cannot be read.</returns>
/// <remarks>Main thread only. Never raises.</remarks>
function EditViewText(const AView: IOTAEditView): string;

/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DragLint.Plugin.Editor.RegisterDragLintMenu (DragLint.Plugin.Editor.pas)</para>
/// <para>Calls: DragLint.Plugin.HoverTracker.TDragLintHoverHelper.Create</para>
/// <seealso cref="DragLint.Plugin.HoverTracker.TDragLintHoverHelper.Create"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure StartHoverTracker;
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DragLint.Plugin.Editor.UnregisterDragLintMenu (DragLint.Plugin.Editor.pas), DragLint.Plugin.HoverTracker.finalization (DragLint.Plugin.HoverTracker.pas)</para>
/// <para>Calls: FreeAndNil</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure StopHoverTracker;

implementation

uses
  System.SysUtils
  , System.Classes
  , System.JSON  { v152 ASYNC: the draglint/deferHover params }
  , Vcl.Forms
  , Vcl.Controls
  , Vcl.ExtCtrls
  , Winapi.Windows
  , ToolsAPI.Editor              { INTACodeEditorServices -- the editor under the pointer }
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
  , DragLint.Plugin.HoverNote    { the token under the pointer and the note text }
  , DragLint.Plugin.JobQueue     { IndexGeneration -- an index job finished }
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
  { The row of a pointer below the last line of the buffer: no buffer has it. }
  PAST_EOF_ROW = MaxInt div 2;
  { The dwell popup opens this far below the pointer (unchanged since v0.42). }
  POPUP_BELOW_PX = 20;
  { The gutter popup opens beside the glyph. }
  GUTTER_POPUP_DX = 18;
  GUTTER_POPUP_DY = 8;
  { v152 ASYNC (ruling B9c): the engine's deferred-hover protocol. The server's
    copy lives in DRagLint.LSP.Deferred; the two must stay equal. }
  DEFER_HOVER_METHOD   = 'draglint/deferHover';
  DEFERRED_PLACEHOLDER = 'computing...';

{ v152 ASYNC: True when a bundle answer is the FAST first step of a deferred
  hover -- its facts carry the placeholder line where the slow sections go. }
function IsDeferredFirstAnswer(const AModel: TDragLintHoverModel): Boolean;
begin
  Result:= False;
  for var F in AModel.Facts do
    if F = DEFERRED_PLACEHOLDER then Exit(True);
end;

{ v152 ASYNC: tells the engine the next hoverBundle at this position may be
  answered in two steps. Sent on the same write queue, so it precedes the
  request. An engine before 1.52 ignores the unknown notification and answers
  the request whole, as before. }
procedure AnnounceDeferredHover(AClient: TDragLintLspClient; const AUri: string; ALine0, ACol0: Integer);
var
  Params : TJSONObject;
  TextDoc: TJSONObject;
  Pos    : TJSONObject;
begin
  Params:= TJSONObject.Create;
  try
    TextDoc:= TJSONObject.Create;
    TextDoc.AddPair('uri', AUri);
    Params.AddPair('textDocument', TextDoc);
    Pos:= TJSONObject.Create;
    Pos.AddPair('line'     , TJSONNumber.Create(ALine0));
    Pos.AddPair('character', TJSONNumber.Create(ACol0 ));
    Params.AddPair('position', Pos);
    AClient.Notify(DEFER_HOVER_METHOD, Params);
  finally
    Params.Free;
  end;
end;

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

function EditViewText(const AView: IOTAEditView): string;
const
  CHUNK = 16 * 1024;
var
  Reader: IOTAEditReader;
  Bytes : TBytes ;
  Len   : Integer;
  N     : Integer;
begin
  Result:= '';
  try
    if (AView = nil) or (AView.Buffer = nil) then Exit;
    Reader:= AView.Buffer.CreateReader;
    if Reader = nil then Exit;
    Len:= 0;
    repeat
      SetLength(Bytes, Len + CHUNK);
      N:= Reader.GetText(Len, PAnsiChar(Bytes) + Len, CHUNK);
      if N > 0 then Inc(Len, N);
    until N < CHUNK;
    SetLength(Bytes, Len);
    { the IDE hands the buffer out as UTF-8 whatever the file's encoding }
    try
      Result:= TEncoding.UTF8.GetString(Bytes);
    except
      on E: EEncodingError do Result:= TEncoding.ANSI.GetString(Bytes); { not valid UTF-8 after all }
    end;
  except
    on E: Exception do DLT('hover', 'buffer not readable: ' + E.Message);
  end;
end;

type
  { The text cell under a screen point, from the editor control under it. Row0 /
    Col0 are buffer positions; they are -1 when there is none. }
  TDLPointerCell = record
    Verdict  : TDLCellVerdict;
    Why      : string ; { hcvNoGrid: what was missing }
    Ctl      : HWND   ;
    Client   : TPoint ;
    View     : IOTAEditView;
    FilePath : string ;
    Row0     : Integer;
    Col0     : Integer;
    VisCol0  : Integer; { Col0 before tabs: the column the pixels count }
    CodeLeft : Integer;
    CharWidth: Integer;
    LeftCol1 : Integer;
    LineTop  : Integer;
    LineHeight: Integer;
    ApiCol   : Integer; { what PointToCharacterPos says, for telemetry only }
    ApiLine  : Integer;
  end;

{ Row of the pointer: the painted line whose rectangle holds its Y. A folded
  block is one painted line with its own logical number, so folds need no
  arithmetic. False when the editor reports no line at all. }
function FindPointerRow(const AState: INTACodeEditorState; var ACell: TDLPointerCell; out ALineText: string): Boolean;
var
  Line: INTACodeEditorLineState;
  R   : TRect;
begin
  Result   := False;
  ALineText:= '';
  for var V: Integer:= AState.TopLine to AState.BottomLine do
  begin
    Line:= AState.LineState[V];
    if Line = nil then Continue;
    R     := Line.WholeRect;
    Result:= True;
    if (ACell.Client.Y < R.Top) or (ACell.Client.Y >= R.Bottom) then Continue;
    ACell.Row0      := Line.LogicalLineNum - 1;
    ACell.LineTop   := R.Top;
    ACell.LineHeight:= R.Height;
    ALineText       := Line.Text;
    Exit;
  end;
  ACell.Row0:= PAST_EOF_ROW; { below the last painted line }
end;

procedure FillPointerCell(const AScreenPt: TPoint; var ACell: TDLPointerCell);
var
  Svcs : INTACodeEditorServices;
  State: INTACodeEditorState   ;
  Ctl  : TWinControl           ;
  Text : string                ;
  EdPos: TOTAEditPos           ;
  ChPos: TOTACharPos           ;
begin
  ACell.Ctl:= EditorControlAt(AScreenPt);
  Ctl      := FindControl(ACell.Ctl);
  ACell.Why:= 'no editor control';
  if (Ctl = nil) or not Supports(BorlandIDEServices, INTACodeEditorServices, Svcs) then Exit;
  ACell.Why:= 'no editor state';
  if not Svcs.IsIDEEditor(Ctl) then Exit;
  State     := Svcs.GetEditorState(Ctl);
  ACell.View:= Svcs.GetViewForEditor(Ctl);
  if (State = nil) or (ACell.View = nil) or (ACell.View.Buffer = nil) then Exit;
  State.Refresh; { the state may be the one of the last paint }
  ACell.FilePath:= ACell.View.Buffer.FileName;
  ACell.Client  := AScreenPt;
  ACell.Why     := 'no lines';
  if not ScreenToClient(ACell.Ctl, ACell.Client) or not FindPointerRow(State, ACell, Text) then Exit;
  ACell.Why      := '';
  ACell.CodeLeft := State.CodeLeftEdge;
  ACell.CharWidth:= State.CharWidth;
  ACell.LeftCol1 := ACell.View.LeftColumn;
  State.PointToCharacterPos(ACell.Client, ACell.ApiCol, ACell.ApiLine);
  ACell.Verdict:= DLColumnAt(ACell.Client.X, ACell.CodeLeft, ACell.CharWidth, ACell.LeftCol1, ACell.VisCol0);
  ACell.Col0   := ACell.VisCol0;
  if (ACell.Verdict = hcvText) and Text.Contains(#9) then
  begin
    { a tab is several cells and one character }
    EdPos.Col := ACell.VisCol0 + 1;
    EdPos.Line:= ACell.Row0 + 1;
    ACell.View.ConvertPos(True, EdPos, ChPos);
    ACell.Col0:= ChPos.CharIndex;
  end;
end;

{ The cell under a SCREEN point now. A point without one is hcvNoGrid. }
function PointerCellAt(const AScreenPt: TPoint): TDLPointerCell;
begin
  Result        := Default(TDLPointerCell);
  Result.Verdict:= hcvNoGrid;
  Result.Row0   := -1;
  Result.Col0   := -1;
  Result.VisCol0:= -1;
  try
    FillPointerCell(AScreenPt, Result);
  except
    on E: Exception do
    begin
      Result.Verdict:= hcvNoGrid;
      Result.Why    := E.Message;
    end;
  end;
end;

{ Telemetry: where the cell came from and what was seen there. }
function CellInfo(const ACell: TDLPointerCell; const AToken: TDLToken): string;
begin
  Result:= Format('src=%s x=%d y=%d codeLeft=%d charW=%d leftCol=%d lineTop=%d lineH=%d api=%d,%d vis=%d tok=%s "%s"',
    ['pointer', ACell.Client.X, ACell.Client.Y, ACell.CodeLeft, ACell.CharWidth, ACell.LeftCol1, ACell.LineTop,
     ACell.LineHeight, ACell.ApiCol, ACell.ApiLine, ACell.VisCol0, DLTokenKindName(AToken.Kind), AToken.Text]);
end;

{ The show-gate's anchor: the token's span in the cell's own grid. }
function AnchorOf(const ACell: TDLPointerCell; const AToken: TDLToken): TDLHoverAnchor;
var
  Shift: Integer; { cells by which tabs move this row's characters right }
begin
  Shift := ACell.VisCol0 - ACell.Col0;
  Result:= DLHoverAnchorFor(ACell.Ctl, ACell.CodeLeft - (ACell.LeftCol1 - 1) * ACell.CharWidth, ACell.CharWidth,
    ACell.LineTop, ACell.LineHeight, AToken.Start0 + Shift, AToken.End0 + Shift);
  Result.Row0     := ACell.Row0;
  Result.StartCol0:= AToken.Start0;
  Result.EndCol0  := AToken.End0;
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
      { v152 ASYNC: the in-flight request is the announced FIRST step of a
        deferred hover (its answer may be partial), or the SECOND step that
        completes a partial popup already on screen. }
      FInflightAnnounced : Boolean                    ;
      FInflightSecond    : Boolean                    ;
      FInflightToken     : TDLToken                   ; { the token the question is about }
      FInflightInfo      : string                     ; { its CellInfo }
      FInflightFile      : string                     ;
      FShowInfo          : string                     ; { CellInfo of the answer ShowHoverPopup is about to show }
      { lane 1.54.1 HOVERNOTE: the place of the last EMPTY answer -- not asked
        about and not announced again until a re-dwell or a finished index job }
      FEmpty             : TDLEmptyMemo               ;
      FNoCellLogged      : Boolean                    ; { gutter / no cell: one telemetry line per dwell }
      procedure OnTick(Sender: TObject);
      { v(session 73): editor caret line -> drag-lint panel selection. }
      procedure DriveCaretPanelSelection;
      procedure ResetState;
      procedure CancelInflight;
      procedure OnHoverBundleAnswer(AId: Integer; AStatus: TDLHoverStatus;
        const AMarkdown, AQName: string; const AModel: TDragLintHoverModel;
        const ACallers: TArray<TDragLintCallerInfo>);
      procedure OnHoverTextAnswer(AId: Integer; AStatus: TDLHoverStatus; const AMarkdown: string);
      { Empty answer: names the token on the strip, once. }
      procedure ShowEmptyAnswer(const AFile: string; ARow0: Integer; const AToken: TDLToken);
      { Takes an arrived answer into the cache; an EMPTY one is never cached. }
      procedure CacheAnswer(const AMarkdown: string; AOk: Boolean; const AModel: TDragLintHoverModel;
        const ACallers: TArray<TDragLintCallerInfo>);
      function  ShowGutterDiagnostics(const ACell: TDLPointerCell; const APos: TPoint): Boolean;
      function  InflightGateVerdict: TDLHoverGateVerdict;
      function  GateAndShowInflight(const AText: string; const AModel: TDragLintHoverModel;
        const ACallers: TArray<TDragLintCallerInfo>): Boolean;
      procedure DropAbandonedSecondStep;
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
  FStableCount := 0;
  FHintShown   := False;
  FNoCellLogged:= False;
  FEmpty.Clear; { a re-dwell asks again }
end;

procedure TDragLintHoverHelper.CancelInflight;
begin
  { Only cancel against the client the request went to, and only while it is
    still the live one -- a replaced client has already dropped the callback. }
  if (FInflightId <> 0) and (FInflightClient <> nil) and (FInflightClient = CurrentLspClient) then
    FInflightClient.CancelRequest(FInflightId);
  FInflightId       := 0;
  FInflightClient   := nil;
  FInflightAnnounced:= False;
  FInflightSecond   := False;
end;

procedure TDragLintHoverHelper.OnHoverBundleAnswer(AId: Integer; AStatus: TDLHoverStatus;
  const AMarkdown, AQName: string; const AModel: TDragLintHoverModel;
  const ACallers: TArray<TDragLintCallerInfo>);
begin
  try
    if AId <> FInflightId then Exit;   { superseded: a newer hover owns the slot }
    DLT('hover', Format('bundle answer id=%d status=%d qname="%s"', [AId, Ord(AStatus), AQName]));
    { LATE, not lost (fix/late-results): the slot stays ours, and the answer is
      shown when it arrives if the pointer is still on the token (the gate). }
    if AStatus = hvsTimeout then
    begin
      SetDragLintNote(DL_NOTE_HOVER_LATE);
      Exit;
    end;
    FInflightId    := 0;
    var WasSecond: Boolean:= FInflightSecond;
    var WasFirst : Boolean:= FInflightAnnounced;
    FInflightAnnounced:= False;
    FInflightSecond   := False;
    case AStatus of
      hvsUnsupported:
        begin
          { An engine without the bundle: ask the plain hover now, still async. }
          FInflightId:= RequestHoverTextAsync(FInflightUri, FInflightRow, FInflightCol, OnHoverTextAnswer);
          if FInflightId = 0 then FInflightClient:= nil;
          Exit;
        end;
    end;
    { v152 ASYNC (ruling B9c): the FAST first step of a deferred hover. Show it
      at once -- the 'computing...' line stands where the facts, Raises: and
      callers will go -- and ask the same position again for the whole answer.
      The partial answer is NOT cached: a re-dwell must never show it as final. }
    if WasFirst and (AStatus = hvsOk) and IsDeferredFirstAnswer(AModel) then
    begin
      if not GateAndShowInflight(AMarkdown, AModel, ACallers) then
      begin
        { The pointer already moved on: no second step to cancel later. }
        FInflightClient:= nil;
        Exit;
      end;
      FInflightId:= RequestHoverBundleAsync(FInflightUri, FInflightRow, FInflightCol, OnHoverBundleAnswer);
      FInflightSecond:= FInflightId <> 0;
      if FInflightId = 0 then FInflightClient:= nil;
      Exit;
    end;
    FInflightClient   := nil;
    CacheAnswer(AMarkdown, AStatus = hvsOk, AModel, ACallers);
    { v152 ASYNC: the whole answer replaces its partial popup IN PLACE (at the
      dwell point) while that popup is up -- the user may be reading it, with
      the pointer on the popup rather than on the token. }
    if WasSecond and IsDragLintHoverVisible and (FLastShownKey = FInflightKey) then
    begin
      DLT('hover', 'deferred hover completed: popup updated in place');
      FShowInfo:= FInflightInfo;
      ShowHoverPopup(FInflightPos, FInflightKey, FLastLspText, FLastBundleModel,
        FLastBundleCallers, FInflightDiags, FInflightDiagText);
      Exit;
    end;
    GateAndShowInflight(FLastLspText, FLastBundleModel, FLastBundleCallers);
  except
    { main-thread callback inside the IDE: never let it raise }
    on E: Exception do DLT('hover', 'bundle answer raised: ' + E.Message);
  end;
end;

procedure TDragLintHoverHelper.OnHoverTextAnswer(AId: Integer; AStatus: TDLHoverStatus; const AMarkdown: string);
begin
  try
    if AId <> FInflightId then Exit;
    if AStatus = hvsTimeout then
    begin
      SetDragLintNote(DL_NOTE_HOVER_LATE);
      Exit;
    end;
    FInflightId    := 0;
    FInflightClient:= nil;
    CacheAnswer(AMarkdown, False, Default(TDragLintHoverModel), nil);
    if (AStatus = hvsUnsupported) and (FInflightDiagText = '') then
    begin
      { an ERROR answer says nothing about the index }
      SetDragLintNote('drag-lint: hover -- engine could not answer');
      Exit;
    end;
    GateAndShowInflight(FLastLspText, FLastBundleModel, FLastBundleCallers);
  except
    on E: Exception do DLT('hover', 'text answer raised: ' + E.Message);
  end;
end;

procedure TDragLintHoverHelper.CacheAnswer(const AMarkdown: string; AOk: Boolean; const AModel: TDragLintHoverModel;
  const ACallers: TArray<TDragLintCallerInfo>);
begin
  FLastLspKey       := if AMarkdown <> '' then FInflightKey else ''; { empty: asked again by the next dwell there }
  FLastLspText      := AMarkdown;
  FLastBundleOk     := AOk;
  FLastBundleModel  := AModel;
  FLastBundleCallers:= ACallers;
end;

procedure TDragLintHoverHelper.ShowEmptyAnswer(const AFile: string; ARow0: Integer; const AToken: TDLToken);
begin
  SetDragLintNote(DLEmptyAnswerNote(AToken));
  FEmpty.Remember(AFile, ARow0, AToken, JobQueue.GetState.IndexGeneration);
  { The memo, not FHintShown, keeps this quiet: a drift of a few pixels onto the
    next token must still be asked about. }
  FHintShown:= False;
end;

{ The owner's show-gate (2026-10-29): the answer is shown only while the pointer
  is still over the editor control the dwell started in AND on the same token
  -- see DragLint.Plugin.HoverGate. Otherwise it is discarded (and stays cached,
  so pointing back at the token shows it at once). }
function TDragLintHoverHelper.InflightGateVerdict: TDLHoverGateVerdict;
var
  NowPt : TPoint;
  Client: TPoint;
  Cell  : TDLPointerCell;
begin
  GetCursorPos(NowPt);
  Client:= NowPt;
  if FInflightAnchor.Hwnd <> 0 then ScreenToClient(FInflightAnchor.Hwnd, Client);
  Cell  := PointerCellAt(NowPt);
  Result:= DLHoverGate(FInflightAnchor, Cell.Ctl, Client, Cell.Row0, Cell.Col0);
end;

function TDragLintHoverHelper.GateAndShowInflight(const AText: string; const AModel: TDragLintHoverModel;
  const ACallers: TArray<TDragLintCallerInfo>): Boolean;
var
  NowPt  : TPoint;
  Verdict: TDLHoverGateVerdict;
begin
  Verdict:= InflightGateVerdict;
  Result:= (Verdict = hgvShow) and IdeIsForeground and LoadSettings.EnableHoverTooltip;
  if not Result then
  begin
    DLT('hover', Format('answer discarded: gate=%d (pointer left the token / editor)', [Ord(Verdict)]));
    SetDragLintNote('');
    { Re-arm: the next dwell at this spot shows the cached answer. }
    FHintShown:= False;
    Exit;
  end;
  GetCursorPos(NowPt);
  FShowInfo:= FInflightInfo;
  ShowHoverPopup(NowPt, FInflightKey, AText, AModel, ACallers, FInflightDiags, FInflightDiagText);
end;

procedure TDragLintHoverHelper.DropAbandonedSecondStep;
begin
  { v152 ASYNC (ruling B9c): the user moved on from a partial popup -- it was
    dismissed AND the pointer is off its token -- so the engine stops computing
    the rest ($/cancelRequest; it answers RequestCancelled to a dropped
    callback). While the partial popup is up the step runs on: the user may be
    reading it, with the pointer on the popup rather than on the token. }
  if not FInflightSecond or (FInflightId = 0) then Exit;
  if IsDragLintHoverVisible then Exit;
  if InflightGateVerdict = hgvShow then Exit;
  DLT('hover', Format('deferred hover id=%d abandoned: popup closed, pointer moved on', [FInflightId]));
  CancelInflight;
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
  DLT('hover', Format('dwell %s model=%d lspLen=%d diagLen=%d shown=%d %s',
    [AKey, Ord(AModel.QualifiedName <> ''), Length(ALspText), Length(ADiagText), Ord(Combined <> ''), FShowInfo]));

  { THE NOTE MUST DIE ON EVERY PATH (2026-08-27: "hover TDeltaBatch forever").
    "Asked and got nothing back" stays distinguishable from "here is the popup". }
  if Combined = '' then
  begin
    ShowEmptyAnswer(FInflightFile, FInflightRow, FInflightToken);
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
  { v0.42: don't re-pop this same position -- unless only the line's finding was
    shown: the symbol question was empty and is asked again by a re-dwell. }
  FLastShownKey:= if ALspText <> '' then AKey else '';
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

{ v0.46: the pointer over the gutter of a line with findings shows them. True
  when it did. }
function TDragLintHoverHelper.ShowGutterDiagnostics(const ACell: TDLPointerCell; const APos: TPoint): Boolean;
var
  Diags: TArray<TDragLintDiagnostic> ;
  Empty: TArray<TDragLintCallerInfo> ;
  Lines: TStringBuilder;
begin
  Diags := Cache.GetForLine(ACell.FilePath, ACell.Row0);
  Result:= Length(Diags) > 0;
  if not Result then Exit;
  Lines:= TStringBuilder.Create;
  try
    for var D: TDragLintDiagnostic in Diags do
    begin
      if Lines.Length > 0 then Lines.Append(sLineBreak);
      if D.Code <> '' then Lines.Append('[' + D.Code + '] ');
      Lines.Append(D.Message);
      { v0.46 lightbulb hint }
      if System.Pos('add unit ', LowerCase(D.Message)) > 0 then Lines.Append('   <-- click to add');
    end;
    FHintShown:= True;
    SetLength(Empty, 0);
    CloseDragLintHover;
    ShowDragLintHover('Diagnostics', Lines.ToString, Empty, APos.X + GUTTER_POPUP_DX, APos.Y + GUTTER_POPUP_DY, True, APos.X, APos.Y);
    FLastShownKey:= Format('gutter|%s|%d', [ACell.FilePath, ACell.Row0 + 1]);
  finally
    Lines.Free;
  end;
end;

procedure TDragLintHoverHelper.OnTick(Sender: TObject);
var
  Settings: TDragLintSettings          ;
  Pos     : TPoint                     ;
  Cell    : TDLPointerCell             ;
  Token   : TDLToken                   ;
  Info    : string                     ;
  Diags   : TArray<TDragLintDiagnostic>;
  LspKey  : string                     ;
  DiagText: string                     ;
  Uri     : string                     ;
  Client  : TDragLintLspClient         ;
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

    { v152 ASYNC: a deferred hover's second step stops once the user moved on. }
    DropAbandonedSecondStep;

    { v0.40.8d: must be over the editor view's form rect, not the project
      manager / structure / messages / etc. Without this the dwell fires
      whenever the cursor parks anywhere in the IDE, based on whatever
      symbol the caret happens to sit on -- completely disconnected from
      what the user is pointing at. }
    { 2026-10-29: AND the window under the pointer must be the editor control
      itself. The form rectangle alone also covers docked panes (Project
      Manager, Structure), which is how popups appeared over them. }
    if (not IsMouseOverEditorView(Pos)) or (EditorControlAt(Pos) = 0) then
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

    { What is under the POINTER, in the view under the pointer. Over the gutter
      only that line's findings are shown; without a cell nothing is asked. }
    Cell:= PointerCellAt(Pos);
    if (Cell.Verdict = hcvGutter) and ShowGutterDiagnostics(Cell, Pos) then Exit;
    if (Cell.Verdict <> hcvText) or (Cell.FilePath = '') then
    begin
      if not FNoCellLogged then
        DLT('hover', Format('dwell no question: %s (%s) %s', [if Cell.Verdict = hcvGutter then 'gutter' else 'no cell',
          Cell.Why, CellInfo(Cell, Default(TDLToken))]));
      FNoCellLogged:= True;
      Exit;
    end;
    { The empty answer already on the strip: neither repeated nor asked again. }
    if FEmpty.Holds(Cell.FilePath, Cell.Row0, Cell.Col0, JobQueue.GetState.IndexGeneration) then Exit;
    Token:= DLTokenInText(EditViewText(Cell.View), Cell.Row0, Cell.Col0);
    Info := CellInfo(Cell, Token);
    FShowInfo:= Info;

    { Pull cached diagnostic for this row, if any. }
    DiagText:= '';
    Diags:= Cache.GetForLine(Cell.FilePath, Cell.Row0);
    if Length(Diags) > 0 then
    begin
      DiagText:= Diags[0].Message;
      { v0.46 lightbulb hint -- the line is clickable to apply the fix. }
      if System.Pos('add unit ', LowerCase(DiagText)) > 0 then DiagText:= DiagText + '   <-- click to add';
    end;

    LspKey:= Format('%s|%d|%d', [Cell.FilePath, Cell.Row0, Cell.Col0]);

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

    FInflightToken:= Token;
    FInflightInfo := Info;
    FInflightFile := Cell.FilePath;
    FInflightRow  := Cell.Row0;
    FInflightCol  := Cell.Col0;

    { White space is no symbol: nothing to ask. The line's findings still show. }
    if Token.Kind = htkBlank then
    begin
      ShowHoverPopup(Pos, LspKey, '', Default(TDragLintHoverModel), nil, Diags, DiagText);
      Exit;
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
      rather than absent. It names the token the question is about. }
    SetDragLintNote(DLHoverAnnounceNote(Token));
    Uri:= 'file:///' + StringReplace(Cell.FilePath, '\', '/', [rfReplaceAll]);

    FInflightKey     := LspKey;
    FInflightClient  := Client;
    FInflightPos     := Pos;
    FInflightAnchor  := AnchorOf(Cell, Token);
    FInflightDiags   := Diags;
    FInflightDiagText:= DiagText;
    FInflightUri     := Uri;
    FHintShown       := True;

    { ONE request for markdown + model + callers; shown when it arrives, if the
      pointer is still on the token (OnHoverAnswer). No serial fallback round
      trip and no CLI spawn on this path any more: an engine without the bundle
      gets the plain textDocument/hover, asked only after the bundle answered
      with an error. }
    { v152 ASYNC (ruling B9c): announce first, so the engine answers the fast
      sections at once and the slow ones on our second ask (OnHoverBundleAnswer). }
    FInflightAnnounced:= not HoverBundleUnsupported;
    FInflightSecond   := False;
    if FInflightAnnounced then AnnounceDeferredHover(Client, Uri, Cell.Row0, Cell.Col0);
    FInflightId:= if HoverBundleUnsupported then RequestHoverTextAsync(Uri, Cell.Row0, Cell.Col0, OnHoverTextAnswer)
                  else RequestHoverBundleAsync(Uri, Cell.Row0, Cell.Col0, OnHoverBundleAnswer);
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
