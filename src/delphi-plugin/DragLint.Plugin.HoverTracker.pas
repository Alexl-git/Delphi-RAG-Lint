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
  System.SysUtils, System.Classes,
  Vcl.Forms, Vcl.Controls, Vcl.ExtCtrls,
  Winapi.Windows,
  ToolsAPI,
  DragLint.Plugin.DiagnosticCache,
  DragLint.Plugin.HoverForm,
  DragLint.Plugin.Settings,
  DragLint.Plugin.LspClient,
  DragLint.Plugin.Editor;

function IdeIsForeground: Boolean;
{ v0.40.8b: process-ID comparison is the only check that works across
  every IDE window (docked editor, floating tab, property inspector,
  structure pane). The plugin BPL runs inside the IDE process; if the
  foreground window also belongs to that process, the IDE has focus.
  IsChild + GetAncestor failed for floating editor tabs (their root is
  the float container, not the AppBuilder main form). }
var
  Fg: HWND;
  Pid: DWORD;
begin
  Result := False;
  Fg := GetForegroundWindow;
  if Fg = 0 then Exit;
  Pid := 0;
  GetWindowThreadProcessId(Fg, Pid);
  Result := (Pid <> 0) and (Pid = GetCurrentProcessId);
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
  ESS: IOTAEditorServices;
  EditView: IOTAEditView;
  F: TCustomForm;
  R: TRect;
begin
  Result := False;
  if not Supports(BorlandIDEServices, IOTAEditorServices, ESS) then Exit;
  EditView := ESS.TopView;
  if EditView = nil then Exit;
  F := EditView.GetEditWindow.Form;
  if F = nil then Exit;
  if not GetWindowRect(F.Handle, R) then Exit;
  Result := PtInRect(R, APt);
end;

type
  TDragLintHoverHelper = class
  private
    FTimer:       TTimer;
    FLastPos:     TPoint;
    FStableCount: Integer;
    FHintShown:   Boolean;
    FLastLspKey:  string;   { v0.40.3: dedupes textDocument/hover firings per stable caret }
    FLastLspText: string;   { v0.40.3: cached symbol info for the last stable caret }
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
  FTimer := TTimer.Create(nil);
  FTimer.Interval := 200;
  FTimer.OnTimer  := OnTick;
  FTimer.Enabled  := True;
  FLastPos        := Point(-1, -1);
  FStableCount    := 0;
  FHintShown      := False;
end;

destructor TDragLintHoverHelper.Destroy;
begin
  FTimer.Free;
  inherited;
end;

procedure TDragLintHoverHelper.ResetState;
begin
  FStableCount := 0;
  FHintShown   := False;
end;

procedure TDragLintHoverHelper.OnTick(Sender: TObject);
var
  Settings:  TDragLintSettings;
  Pos:       TPoint;
  ESS:       IOTAEditorServices;
  EditView:  IOTAEditView;
  FilePath:  string;
  CaretRow:  Integer;
  CaretCol:  Integer;
  Diags:     TArray<TDragLintDiagnostic>;
  LspKey:    string;
  LspText:   string;
  DiagText:  string;
  Combined:  string;
  Uri:       string;
begin
  try
    Settings := LoadSettings;
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
      if not FLastForegroundFail then
      begin
        DebugLog('HoverTracker: bail -- IDE not foreground');
        FLastForegroundFail := True;
      end;
      ResetState;
      Exit;
    end;
    FLastForegroundFail := False;

    GetCursorPos(Pos);

    { v0.40.8d: must be over the editor view's form rect, not the project
      manager / structure / messages / etc. Without this the dwell fires
      whenever the cursor parks anywhere in the IDE, based on whatever
      symbol the caret happens to sit on -- completely disconnected from
      what the user is pointing at. }
    if not IsMouseOverEditorView(Pos) then
    begin
      ResetState;
      Exit;
    end;

    if (Pos.X = FLastPos.X) and (Pos.Y = FLastPos.Y) then
      Inc(FStableCount)
    else
    begin
      ResetState;
    end;
    FLastPos := Pos;

    { v0.40.7: bumped from 3 (600ms) to 8 (1600ms) so casual cursor drift
      doesn't fire the popup. }
    if FStableCount < 8 then Exit;

    { Already showed for this stable position }
    if FHintShown then Exit;

    { v0.40.6: don't compete with an already-visible popup. ResetState above
      means FHintShown is False on every mouse move, so without this guard
      the popup would re-anchor at every mouse stop ("jumping around"). }
    if IsDragLintHoverVisible then
    begin
      FHintShown := True;
      Exit;
    end;

    { Query the active editor's caret row + column }
    if not Supports(BorlandIDEServices, IOTAEditorServices, ESS) then Exit;
    EditView := ESS.TopView;
    if EditView = nil then Exit;

    FilePath := EditView.Buffer.FileName;
    if FilePath = '' then Exit;

    { IOTAEditView.Position is 1-based; LSP / diagnostic cache is 0-based }
    CaretRow := EditView.Position.Row - 1;
    CaretCol := EditView.Position.Column - 1;
    if CaretRow < 0 then CaretRow := 0;
    if CaretCol < 0 then CaretCol := 0;

    { Pull cached diagnostic for this row, if any. }
    DiagText := '';
    Diags := Cache.GetForLine(FilePath, CaretRow);
    if Length(Diags) > 0 then
      DiagText := Diags[0].Message;

    { v0.40.3: ALSO query LSP hover at (file, row, col) for symbol info.
      Dedupe via FLastLspKey so we don't fire on every dwell cycle for
      the same position. Cache the result so repeated dwell on the same
      caret reuses it. }
    LspKey := Format('%s|%d|%d', [FilePath, CaretRow, CaretCol]);
    if LspKey <> FLastLspKey then
    begin
      Uri := 'file:///' + StringReplace(FilePath, '\', '/', [rfReplaceAll]);
      FLastLspText := QueryHoverText(Uri, CaretRow, CaretCol, 500);
      FLastLspKey  := LspKey;
    end;
    LspText := FLastLspText;

    { Combine the two -- symbol info first, diagnostic underneath. }
    Combined := '';
    if LspText <> '' then
      Combined := LspText;
    if DiagText <> '' then
    begin
      if Combined <> '' then
        Combined := Combined + #13#10 + '---' + #13#10;
      Combined := Combined + DiagText;
    end;

    if Combined = '' then Exit;

    FHintShown := True;
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
    var DwellHeader: string := ExtractHoverHeader(Combined);
    Combined := StripFirstHeaderLine(Combined);
    var DwellCallers: TArray<TDragLintCallerInfo>;
    SetLength(DwellCallers, 0);
    DebugLog(Format('HoverTracker: spawning popup at (%d,%d), %d chars, header="%s"',
      [Pos.X, Pos.Y + 20, Length(Combined), DwellHeader]));
    CloseDragLintHover;
    { v0.42: dwell popups dismiss against the original mouse point (Pos), not
      the wide popup rect -- so a small drift, or leaving the editor, clears
      them. The popup is still drawn at Pos.Y+20 (below the cursor). }
    ShowDragLintHover(DwellHeader, Combined, DwellCallers, Pos.X, Pos.Y + 20,
      True, Pos.X, Pos.Y);
  except
    { Swallow all exceptions: this fires in a VCL timer inside the IDE.
      Any unhandled exception here would surface as an IDE crash or modal
      dialog. Silent failure is strongly preferred. }
  end;
end;

procedure StartHoverTracker;
begin
  if GHelper = nil then
    GHelper := TDragLintHoverHelper.Create;
end;

procedure StopHoverTracker;
begin
  FreeAndNil(GHelper);
end;

initialization

finalization
  StopHoverTracker;

end.
