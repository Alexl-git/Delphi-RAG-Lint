unit DragLint.Plugin.HoverTracker;

(* Caret-based hover tooltip for drag-lint (v0.35 -> v0.40.3).

   v0.35 behaviour:
     A TTimer fires every 200ms. When the mouse cursor is stable for >= 3
     ticks (600ms) we check the active editor's caret row in the diagnostic
     cache. If a diagnostic exists on that row, we call ShowDragLintHover.

   v0.40.3 extension:
     In addition to the diagnostic lookup, we now fire textDocument/hover
     against the shared LSP client (via QueryHoverText) for the current
     caret position. The two strings — diagnostic + symbol info — are
     combined into one popup. If either is empty the other is shown alone;
     if both are empty we suppress the popup (no change from v0.35).

   Performance:
     LSP queries are budgeted at 500ms timeout and only fire once per
     stable (file, line, col) tuple — see FLastLspKey. Cursor wobble or
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
  DragLint.Plugin.Editor;

type
  TDragLintHoverHelper = class
  private
    FTimer:       TTimer;
    FLastPos:     TPoint;
    FStableCount: Integer;
    FHintShown:   Boolean;
    FLastLspKey:  string;   { v0.40.3: dedupes textDocument/hover firings per stable caret }
    FLastLspText: string;   { v0.40.3: cached symbol info for the last stable caret }
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

    GetCursorPos(Pos);
    if (Pos.X = FLastPos.X) and (Pos.Y = FLastPos.Y) then
      Inc(FStableCount)
    else
    begin
      ResetState;
    end;
    FLastPos := Pos;

    { Wait for cursor to be stable for >= 3 ticks (600ms) }
    if FStableCount < 3 then Exit;

    { Already showed for this stable position }
    if FHintShown then Exit;

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

    { Combine the two — symbol info first, diagnostic underneath. }
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
    ShowDragLintHover(Combined, Pos.X, Pos.Y + 20);
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
