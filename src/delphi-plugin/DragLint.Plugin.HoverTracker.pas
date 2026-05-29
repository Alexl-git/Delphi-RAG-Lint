unit DragLint.Plugin.HoverTracker;

{ Caret-based hover tooltip for drag-lint diagnostics (v0.35).

  Implementation:
  A TTimer fires every 200ms.  When the mouse cursor is stable for >= 3 ticks
  (600ms) we check the active editor's caret row in the diagnostic cache.
  If a diagnostic exists on that row, we call ShowDragLintHover to display it
  near the cursor.

  Limitation (documented): the tooltip shows the message for whatever row the
  caret is on, not the token precisely under the mouse.  OTAPI does not expose
  a reliable pixel-to-cell mapping without brittle font-metrics arithmetic;
  the caret-based approach is sufficient for v0.35. }

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
  DragLint.Plugin.Settings;

type
  TDragLintHoverHelper = class
  private
    FTimer:       TTimer;
    FLastPos:     TPoint;
    FStableCount: Integer;
    FHintShown:   Boolean;
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
  Diags:     TArray<TDragLintDiagnostic>;
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

    { Query the active editor's caret row }
    if not Supports(BorlandIDEServices, IOTAEditorServices, ESS) then Exit;
    EditView := ESS.TopView;
    if EditView = nil then Exit;

    FilePath := EditView.Buffer.FileName;
    if FilePath = '' then Exit;

    { IOTAEditView.Position.Row is 1-based; diagnostic cache is 0-based (LSP) }
    CaretRow := EditView.Position.Row - 1;
    if CaretRow < 0 then CaretRow := 0;

    Diags := Cache.GetForLine(FilePath, CaretRow);
    if Length(Diags) = 0 then Exit;

    { Show the hover popup.  We reuse the existing TDragLintHoverForm which
      handles ESC / deactivation / 30s auto-close gracefully. }
    FHintShown := True;
    ShowDragLintHover(Diags[0].Message, Pos.X, Pos.Y + 20);
  except
    { Swallow all exceptions: this fires in a VCL timer inside the IDE.
      Any unhandled exception here would surface as an IDE crash or modal
      dialog.  Silent failure is strongly preferred. }
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
