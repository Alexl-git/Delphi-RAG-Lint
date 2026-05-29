unit DragLint.Plugin.OptionsFrame;

{ TDragLintOptionsFrame: TFrame hosting all drag-lint settings controls.
  Used by:
  - TDragLintOptions (INTAAddInOptions) -- IDE-native Tools > Options page
  - ShowSettingsDialog -- existing modal wrapper (unchanged)

  Load/Save read from / write to the registry via DragLint.Plugin.Settings. }

interface

uses
  System.Classes, System.SysUtils,
  Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.Dialogs;

type
  TDragLintOptionsFrame = class(TFrame)
  private
    { -- Paths group -- }
    FGrpPaths:       TGroupBox;
    FEdExe:          TEdit;
    FBtnBrowse:      TButton;
    FEdDb:           TEdit;
    { -- Auto-index group -- }
    FGrpAutoIndex:   TGroupBox;
    FCbAutoIndex:    TCheckBox;
    FCbAutoReindex:  TCheckBox;
    FCbScanLibraries: TCheckBox;
    { -- Features group -- }
    FGrpFeatures:    TGroupBox;
    FCbHover:        TCheckBox;
    FCbCompletion:   TCheckBox;
    FCbSignature:    TCheckBox;
    FCbDiag:         TCheckBox;
    { -- Inline Markers group -- }
    FGrpMarkers:     TGroupBox;
    FCbInline:       TCheckBox;
    FCbErrInline:    TCheckBox;
    FCbWarnInline:   TCheckBox;
    FCbHintInline:   TCheckBox;
    FCbInfoInline:   TCheckBox;
    { -- Code Lens group -- }
    FGrpCodeLens:    TGroupBox;
    FCbCodeLens:     TCheckBox;
    { -- Workspace group -- }
    FGrpWorkspace:   TGroupBox;
    FCbWorkspace:    TCheckBox;
    { Browse dialog }
    FOpenDlg:        TOpenDialog;
    procedure BtnBrowseClick(Sender: TObject);
    procedure BuildControls;
  public
    constructor Create(AOwner: TComponent); override;
    procedure Load;
    procedure Save;
  end;

implementation

uses
  DragLint.Plugin.Settings;

{ ---- constructor ---- }

constructor TDragLintOptionsFrame.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  BuildControls;
end;

{ ---- BuildControls: create all controls dynamically ---- }

procedure TDragLintOptionsFrame.BuildControls;
const
  LM = 8;   { left margin inside group box }
  GM = 8;   { gap between group boxes }
  GH = 28;  { single group-box header height }
  CH = 22;  { checkbox row height }
  EH = 24;  { edit row height }
var
  Y: Integer;

  function NewGroup(const ACaption: string; AHeight: Integer): TGroupBox;
  begin
    Result := TGroupBox.Create(Self);
    Result.Parent  := Self;
    Result.Left    := GM;
    Result.Top     := Y;
    Result.Width   := Self.Width - GM * 2;
    Result.Height  := AHeight;
    Result.Caption := ACaption;
    Result.Anchors := [akLeft, akTop, akRight];
    Inc(Y, AHeight + GM);
  end;

  function NewLabel(AParent: TWinControl; const ACap: string;
    AX, AY: Integer): TLabel;
  begin
    Result := TLabel.Create(AParent);
    Result.Parent  := AParent;
    Result.Caption := ACap;
    Result.Left    := AX;
    Result.Top     := AY;
    Result.AutoSize := True;
  end;

  function NewEdit(AParent: TWinControl; AX, AY, AW: Integer;
    const ATxt: string): TEdit;
  begin
    Result := TEdit.Create(AParent);
    Result.Parent  := AParent;
    Result.Left    := AX;
    Result.Top     := AY;
    Result.Width   := AW;
    Result.Text    := ATxt;
    Result.Anchors := [akLeft, akTop, akRight];
  end;

  function NewCheck(AParent: TWinControl; AX, AY: Integer;
    const ACap: string; AChecked: Boolean): TCheckBox;
  begin
    Result := TCheckBox.Create(AParent);
    Result.Parent   := AParent;
    Result.Left     := AX;
    Result.Top      := AY;
    Result.Width    := AParent.Width - AX - 4;
    Result.Caption  := ACap;
    Result.Checked  := AChecked;
    Result.Anchors  := [akLeft, akTop, akRight];
  end;

var
  GY: Integer;  { Y inside the current group }
  GW: Integer;  { group box interior width }
begin
  Width  := 460;
  Height := 616;
  Y := GM;

  { --- Paths --- }
  FGrpPaths := NewGroup('Paths', GH + EH + 8 + EH + 28);
  GW := FGrpPaths.Width - LM * 2;
  GY := GH - 4;

  NewLabel(FGrpPaths, 'drag-lint.exe:', LM, GY);
  Inc(GY, 16);
  FEdExe := NewEdit(FGrpPaths, LM, GY, GW - 72, '');

  FBtnBrowse := TButton.Create(FGrpPaths);
  FBtnBrowse.Parent   := FGrpPaths;
  FBtnBrowse.Caption  := 'Browse...';
  FBtnBrowse.Left     := FEdExe.Left + FEdExe.Width + 4;
  FBtnBrowse.Top      := GY;
  FBtnBrowse.Width    := 68;
  FBtnBrowse.Height   := EH;
  FBtnBrowse.Anchors  := [akTop, akRight];
  FBtnBrowse.OnClick  := BtnBrowseClick;
  Inc(GY, EH + 6);

  NewLabel(FGrpPaths, 'Database template (use <projdir>):', LM, GY);
  Inc(GY, 16);
  FEdDb := NewEdit(FGrpPaths, LM, GY, GW, '');

  FOpenDlg := TOpenDialog.Create(Self);
  FOpenDlg.Filter := 'drag-lint.exe|drag-lint.exe|All files|*.*';

  { --- Auto-index --- }
  FGrpAutoIndex := NewGroup('Auto-index', GH + CH * 3 + 4);
  GY := GH - 4;
  FCbAutoIndex  := NewCheck(FGrpAutoIndex,  LM, GY,
    'Auto-index project when .dproj opens', False);
  Inc(GY, CH);
  FCbAutoReindex := NewCheck(FGrpAutoIndex, LM, GY,
    'Auto-reindex on file save (.pas, .dpr, .dfm)', False);
  Inc(GY, CH);
  FCbScanLibraries := NewCheck(FGrpAutoIndex, LM, GY,
    'Scan libraries (RTL + DevExpress + browsing paths) on index', False);

  { --- Feature Toggles --- }
  FGrpFeatures := NewGroup('Feature Toggles', GH + CH * 4 + 4);
  GY := GH - 4;
  FCbHover      := NewCheck(FGrpFeatures, LM, GY, 'Enable Hover at Cursor',   False); Inc(GY, CH);
  FCbCompletion := NewCheck(FGrpFeatures, LM, GY, 'Enable Show Completion',    False); Inc(GY, CH);
  FCbSignature  := NewCheck(FGrpFeatures, LM, GY, 'Enable Show Signature Help',False); Inc(GY, CH);
  FCbDiag       := NewCheck(FGrpFeatures, LM, GY, 'Enable Run Diagnostics',    False);

  { --- Inline Markers --- }
  FGrpMarkers := NewGroup('Inline Markers', GH + CH * 5 + 4);
  GY := GH - 4;
  FCbInline    := NewCheck(FGrpMarkers, LM,      GY, 'Enable inline markers (gutter + underline)', False); Inc(GY, CH);
  FCbErrInline := NewCheck(FGrpMarkers, LM + 16, GY, 'Show errors inline',   False); Inc(GY, CH);
  FCbWarnInline:= NewCheck(FGrpMarkers, LM + 16, GY, 'Show warnings inline', False); Inc(GY, CH);
  FCbHintInline:= NewCheck(FGrpMarkers, LM + 16, GY, 'Show hints inline',    False); Inc(GY, CH);
  FCbInfoInline:= NewCheck(FGrpMarkers, LM + 16, GY, 'Show info inline',     False);

  { --- Code Lens --- }
  FGrpCodeLens := NewGroup('Code Lens', GH + CH + 4);
  GY := GH - 4;
  FCbCodeLens := NewCheck(FGrpCodeLens, LM, GY,
    'Enable inline code lens ([N callers] next to method declarations)', False);

  { --- Workspace --- }
  FGrpWorkspace := NewGroup('Workspace (v0.34)', GH + CH + 4);
  GY := GH - 4;
  FCbWorkspace := NewCheck(FGrpWorkspace, LM, GY,
    'Enable workspace mode (auto-detect .drag-lint-workspace.json)', False);
end;

{ ---- Load: read registry into controls ---- }

procedure TDragLintOptionsFrame.Load;
var
  S: TDragLintSettings;
begin
  S := LoadSettings;
  FEdExe.Text          := S.ExePath;
  FEdDb.Text           := S.DbPathTemplate;
  FCbAutoIndex.Checked     := S.AutoIndex;
  FCbAutoReindex.Checked   := S.AutoReindexOnSave;
  FCbScanLibraries.Checked := S.ScanLibraries;
  FCbHover.Checked      := S.EnableHover;
  FCbCompletion.Checked := S.EnableCompletion;
  FCbSignature.Checked  := S.EnableSignature;
  FCbDiag.Checked       := S.EnableDiagnostics;
  FCbInline.Checked     := S.EnableInlineMarkers;
  FCbErrInline.Checked  := S.ShowErrorsInline;
  FCbWarnInline.Checked := S.ShowWarningsInline;
  FCbHintInline.Checked := S.ShowHintsInline;
  FCbInfoInline.Checked := S.ShowInfoInline;
  FCbCodeLens.Checked   := S.EnableCodeLens;
  FCbWorkspace.Checked  := S.EnableWorkspaceMode;
end;

{ ---- Save: write controls back to registry ---- }

procedure TDragLintOptionsFrame.Save;
var
  S: TDragLintSettings;
begin
  S.ExePath           := FEdExe.Text;
  S.DbPathTemplate    := FEdDb.Text;
  S.AutoIndex            := FCbAutoIndex.Checked;
  S.AutoReindexOnSave    := FCbAutoReindex.Checked;
  S.ScanLibraries        := FCbScanLibraries.Checked;
  S.EnableHover          := FCbHover.Checked;
  S.EnableCompletion     := FCbCompletion.Checked;
  S.EnableSignature      := FCbSignature.Checked;
  S.EnableDiagnostics    := FCbDiag.Checked;
  S.EnableInlineMarkers  := FCbInline.Checked;
  S.ShowErrorsInline     := FCbErrInline.Checked;
  S.ShowWarningsInline   := FCbWarnInline.Checked;
  S.ShowHintsInline      := FCbHintInline.Checked;
  S.ShowInfoInline       := FCbInfoInline.Checked;
  S.EnableCodeLens       := FCbCodeLens.Checked;
  S.EnableWorkspaceMode  := FCbWorkspace.Checked;
  SaveSettings(S);
end;

{ ---- Browse handler ---- }

procedure TDragLintOptionsFrame.BtnBrowseClick(Sender: TObject);
begin
  if FOpenDlg.Execute then
    FEdExe.Text := FOpenDlg.FileName;
end;

end.
