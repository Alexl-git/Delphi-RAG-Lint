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
     LSP queries are budgeted at 500ms timeout and only fire once per
     stable (file, line, col) tuple -- see FLastLspKey. Cursor wobble or
     repeated dwell on the same caret position doesn't requery the LSP.

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
  , DragLint.Plugin.StatusLine   { SetEditorStatus -- the 'thinking' note }
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

type
  TDragLintHoverHelper = class
    private
      FTimer             : TTimer ;
      FLastPos           : TPoint ;
      FStableCount       : Integer;
      FHintShown         : Boolean;
      FLastLspKey        : string ; { v0.40.3: dedupes textDocument/hover firings per stable caret }
      FLastLspText       : string ; { v0.40.3: cached symbol info for the last stable caret }
      { v(hover bundle): the model + callers that came back with FLastLspText in
        the SAME request. Cached alongside it, keyed by FLastLspKey, so a dwell
        that re-shows a cached caret does no engine work at all. FLastBundleOk
        False means the bundle was unavailable and the legacy per-part path must
        run -- it is NOT the same as "this symbol has no callers". }
      FLastBundleOk      : Boolean;
      FLastBundleModel   : TDragLintHoverModel        ;
      FLastBundleCallers : TArray<TDragLintCallerInfo>;
      FLastShownKey      : string ; { v0.42: caret key we already popped; don't re-show it }
      FLastForegroundFail: Boolean; { v0.40.8b: log the bail-out only once per transition }
      procedure OnTick(Sender: TObject);
      procedure ResetState;
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
end;

destructor TDragLintHoverHelper.Destroy;
begin
  FTimer.Free;
  inherited;
end;

procedure TDragLintHoverHelper.ResetState;
begin
  FStableCount:= 0;
  FHintShown  := False;
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
  LspText : string                     ;
  DiagText: string                     ;
  Combined: string                     ;
  Uri     : string                     ;
begin
  try
    Settings:= LoadSettings;
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
    if not IsMouseOverEditorView(Pos) then
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

    { v0.40.3: ALSO query LSP hover at (file, row, col) for symbol info.
      Dedupe via FLastLspKey so we don't fire on every dwell cycle for
      the same position. Cache the result so repeated dwell on the same
      caret reuses it. }
    LspKey:= Format('%s|%d|%d', [FilePath, CaretRow, CaretCol]);

    { v0.42: the dwell uses the CARET position for content but the MOUSE for
      placement, so wandering the mouse over a docked pane (still inside the
      editor form rect) for the same caret kept re-popping the same hover.
      Show a given caret's popup once; only a caret change re-arms it. }
    if LspKey = FLastShownKey then
    begin
      FHintShown:= True;
      Exit;
    end;

    if LspKey <> FLastLspKey then
    begin
      Uri:= 'file:///' + StringReplace(FilePath, '\', '/', [rfReplaceAll]);
      { Announce BEFORE the request. Only this branch does engine work -- a
        cached caret re-show is instant and needs no note. Asked for
        2026-08-19 so a slow hover reads as THINKING rather than absent. }
      SetEditorStatus('drag-lint: hover');
      { v(hover bundle): ONE request for markdown + model + callers. This used to
        be a hover round trip here and three drag-lint.exe spawns later on, all
        on the main thread while a tooltip was trying to appear. On any miss --
        an engine that predates the method, a timeout -- fall back to the old
        markdown-only fetch and let the legacy path rebuild the rest. }
      var BQName: string;
      FLastBundleOk:= FetchHoverBundle(Uri, CaretRow, CaretCol,
        FLastLspText, BQName, FLastBundleModel, FLastBundleCallers);
      if not FLastBundleOk then
      begin
        FLastLspText:= QueryHoverText(Uri, CaretRow, CaretCol, 500);
        FLastBundleModel:= Default(TDragLintHoverModel);
        SetLength(FLastBundleCallers, 0);
      end;
      FLastLspKey:= LspKey;
    end;
    LspText:= FLastLspText;

    { Combine the two -- symbol info first, diagnostic underneath. }
    Combined:= '';
    if LspText <> '' then Combined:= LspText;
    if DiagText <> '' then
    begin
      if Combined <> '' then Combined:= Combined + #13#10 + '---' + #13#10;
      Combined:= Combined + DiagText;
    end;

    if Combined = '' then Exit;

    FHintShown:= True;
    { v0.40.7: dwell tracker uses the simple 1-arg overload (no callers /
      no header) because the find-callers shell-out from a 200 ms timer would
      compound latency. Menu InvokeHover does the full three-section show.
      v0.40.8c: still extract the header + strip the duplicated first line so
      the popup looks like Delphi's native Code Insight. Callers list is
      empty for dwell-fired popups (use the menu Hover at Cursor for those).
      v0.40.8f: snap-to-symbol -- close any stale popup before showing the
      new one. Without this the singleton in HoverForm refuses to show
      because the previous popup is still on screen, leaving the user
      reading stale data while pointing at a new identifier. }
    var DwellCallers: TArray<TDragLintCallerInfo>;
    SetLength(DwellCallers, 0);
    CloseDragLintHover;
    { v0.94.1: PREFER the structured Help-Insight model on the DWELL path so a
      MOUSE hover shows the colored signature + Parameters + Returns. Mine the
      qname from the RAW LSP markdown (LspText, before StripFirstHeaderLine) and
      fetch `hover --json`. We try this EVEN when a diagnostic is present -- the
      structured view is the priority, and since v(hover-both) the diagnostic is
      no longer sacrificed for it: it is copied onto Model.Diagnostics and drawn
      as its own section, so the popup shows the symbol AND the finding. On any miss (no
      qname / json fetch fails) we fall back to the legacy string popup so the
      user always sees something. Callers skipped here (light for the 200ms
      timer). Detailed logging tells a live smoke exactly why a fallback fired. }
    var Model: TDragLintHoverModel;
    var ModelCallers: TArray<TDragLintCallerInfo>;
    SetLength(ModelCallers, 0);
    var GotModel: Boolean:= False;
    if FLastBundleOk then
    begin
      { Already in hand from the one request above -- no spawn, no second
        resolution of the same cursor. }
      Model       := FLastBundleModel  ;
      ModelCallers:= FLastBundleCallers;
      GotModel    := Model.QualifiedName <> '';
    end
    else if LspText <> '' then
    begin
      GotModel:= TryBuildHoverModel(LspText, Model, ModelCallers);
    end;

    SetEditorStatus('');   { the popup below IS the answer }
    if GotModel then
    begin
      { v(hover-both): carry the line's findings INTO the structured popup.
        Until now this branch dropped DiagText on the floor -- the comment above
        called a diagnostic on the hovered line "rare" and pointed the user at
        the menu Hover for it. It is not rare (a lint finding and the symbol it
        is about are on the same line by construction), and the effect was that
        the two useful facts were mutually exclusive: signature OR finding,
        decided by which code path happened to run. Show both. }
      SetLength(Model.Diagnostics, 0);
      for var MDI:= 0 to High(Diags) do
      begin
        var MMsg: string:= Diags[MDI].Message;
        if Diags[MDI].Code <> '' then MMsg:= '[' + Diags[MDI].Code + '] ' + MMsg;
        if System.Pos('add unit ', LowerCase(Diags[MDI].Message)) > 0 then MMsg:= MMsg + '   <-- click to add';
        SetLength(Model.Diagnostics, Length(Model.Diagnostics) + 1);
        Model.Diagnostics[High(Model.Diagnostics)]:= MMsg;
      end;
      { v0.42: dwell popups dismiss against the original mouse point (Pos). }
      ShowDragLintHover(Model, ModelCallers, Pos.X, Pos.Y + 20, True, Pos.X, Pos.Y);
    end
    else
    begin
      var DwellHeader: string:= ExtractHoverHeader(Combined);
      Combined:= StripFirstHeaderLine(Combined);
      { v0.42: dwell popups dismiss against the original mouse point (Pos), not
        the wide popup rect -- so a small drift, or leaving the editor, clears
        them. The popup is still drawn at Pos.Y+20 (below the cursor). }
      ShowDragLintHover(DwellHeader, Combined, DwellCallers, Pos.X, Pos.Y + 20, True, Pos.X, Pos.Y);
    end;
    FLastShownKey:= LspKey; { v0.42: don't re-pop this same caret }
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
