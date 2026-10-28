unit ProjectSetup.MainForm;

{ Code-built setup form (no DFM). Plain VCL. }

interface

uses
  System.SysUtils, System.Classes, Vcl.Forms, Vcl.Controls, Vcl.StdCtrls,
  Vcl.Dialogs, ProjectSetup.ContextJson;

type
  /// <summary>Single form that edits and saves a project's .dlcontext.json.</summary>
  TSetupForm = class(TForm)
  private
    FProjectEdit: TEdit;
    FPlatformCombo: TComboBox;
    FConfigCombo: TComboBox;
    FDefinesMemo: TMemo;
    FSearchMemo: TMemo;
    FNamespacesMemo: TMemo;
    FLibraryDbEdit: TEdit;
    FRootsMemo: TMemo;
    FStatus: TLabel;
    FCompilerEdit: TEdit;
    procedure ApplyCentralDefaults;
    function AddLabel(const pCaption: string; pTop: Integer): TLabel;
    function AddMemo(const pCaption: string; pTop, pHeight: Integer): TMemo;
    procedure BrowseClick(pSender: TObject);
    procedure SaveClick(pSender: TObject);
    procedure PlatformChange(pSender: TObject);
    procedure ProjectChanged;
    procedure FillMemo(pMemo: TMemo; const pItems: TArray<string>);
  public
    /// <summary>Builds the form.</summary>
    /// <param name="pOwner">Component owner.</param>
    /// <param name="pProjectFile">Initial .dpr path ('' for none); an existing context is loaded.</param>
    constructor CreateSetup(pOwner: TComponent; const pProjectFile: string);
    /// <summary>Path currently in the project field.</summary>
    function ProjectFile: string;
  end;

implementation

const
  CLeft = 12;
  CWide = 560;

constructor TSetupForm.CreateSetup(pOwner: TComponent; const pProjectFile: string);
var
  lBtn: TButton;
  lP: string;
begin
  inherited CreateNew(pOwner);
  Caption := 'dl-project-setup - project context';
  Position := poScreenCenter;
  BorderStyle := bsDialog;
  ClientWidth := CWide + 2 * CLeft;
  ClientHeight := 640;

  AddLabel('Project file (.dpr)', 8);
  FProjectEdit := TEdit.Create(Self);
  FProjectEdit.Parent := Self;
  FProjectEdit.SetBounds(CLeft, 26, CWide - 90, 23);
  lBtn := TButton.Create(Self);
  lBtn.Parent := Self;
  lBtn.Caption := 'Browse...';
  lBtn.SetBounds(CLeft + CWide - 82, 25, 82, 25);
  lBtn.OnClick := BrowseClick;

  AddLabel('Target platform', 58);
  FPlatformCombo := TComboBox.Create(Self);
  FPlatformCombo.Parent := Self;
  FPlatformCombo.Style := csDropDownList;
  FPlatformCombo.SetBounds(CLeft, 76, 180, 23);
  for lP in SetupPlatforms do
    FPlatformCombo.Items.Add(lP);
  FPlatformCombo.ItemIndex := FPlatformCombo.Items.IndexOf('Win32');
  FPlatformCombo.OnChange := PlatformChange;

  AddLabel('Configuration', 58).Left := CLeft + 200;
  FConfigCombo := TComboBox.Create(Self);
  FConfigCombo.Parent := Self;
  FConfigCombo.Style := csDropDown;
  FConfigCombo.SetBounds(CLeft + 200, 76, 180, 23);
  FConfigCombo.Items.Add('Debug');
  FConfigCombo.Items.Add('Release');
  FConfigCombo.Text := 'Debug';
  FConfigCombo.OnChange := PlatformChange;

  FDefinesMemo := AddMemo('Conditional defines (one per line)', 106, 100);
  FSearchMemo := AddMemo('Unit search path (one per line)', 216, 80);
  FNamespacesMemo := AddMemo('Namespaces (one per line)', 306, 60);

  AddLabel('Library DB path (optional)', 376);
  FLibraryDbEdit := TEdit.Create(Self);
  FLibraryDbEdit.Parent := Self;
  FLibraryDbEdit.SetBounds(CLeft, 394, CWide, 23);

  FRootsMemo := AddMemo('RTL/VCL source roots (optional, one per line)', 424, 60);

  FStatus := AddLabel('', 556);
  lBtn := TButton.Create(Self);
  lBtn.Parent := Self;
  lBtn.Caption := 'Save';
  lBtn.Default := True;
  lBtn.SetBounds(CLeft + CWide - 170, 596, 80, 28);
  lBtn.OnClick := SaveClick;
  lBtn := TButton.Create(Self);
  lBtn.Parent := Self;
  lBtn.Caption := 'Close';
  lBtn.Cancel := True;
  lBtn.ModalResult := mrCancel;
  lBtn.SetBounds(CLeft + CWide - 82, 596, 82, 28);

  AddLabel('Target compiler (optional, e.g. 37; empty = default)', 494);
  FCompilerEdit := TEdit.Create(Self);
  FCompilerEdit.Parent := Self;
  FCompilerEdit.SetBounds(CLeft, 512, 180, 23);

  PlatformChange(nil);
  ApplyCentralDefaults;
  FProjectEdit.Text := pProjectFile;
  ProjectChanged;
end;

function TSetupForm.AddLabel(const pCaption: string; pTop: Integer): TLabel;
begin
  Result := TLabel.Create(Self);
  Result.Parent := Self;
  Result.Caption := pCaption;
  Result.SetBounds(CLeft, pTop, CWide, 15);
end;

function TSetupForm.AddMemo(const pCaption: string; pTop, pHeight: Integer): TMemo;
begin
  AddLabel(pCaption, pTop);
  Result := TMemo.Create(Self);
  Result.Parent := Self;
  Result.ScrollBars := ssVertical;
  Result.SetBounds(CLeft, pTop + 18, CWide, pHeight - 20);
end;

procedure TSetupForm.FillMemo(pMemo: TMemo; const pItems: TArray<string>);
var
  lS: string;
begin
  pMemo.Lines.Clear;
  for lS in pItems do
    pMemo.Lines.Add(lS);
end;

function TSetupForm.ProjectFile: string;
begin
  Result := Trim(FProjectEdit.Text);
end;

procedure TSetupForm.PlatformChange(pSender: TObject);
begin
  FillMemo(FDefinesMemo, DefaultDefines(FPlatformCombo.Text, FConfigCombo.Text));
  FillMemo(FNamespacesMemo, DefaultNamespaces(FPlatformCombo.Text));
end;

procedure TSetupForm.ApplyCentralDefaults;
var
  lDef: TContextDefaults;
begin
  if not TryLoadContextDefaults('', lDef) then
    Exit;
  if FPlatformCombo.Items.IndexOf(lDef.PlatformName) >= 0 then
    FPlatformCombo.ItemIndex := FPlatformCombo.Items.IndexOf(lDef.PlatformName);
  if lDef.Config <> '' then
    FConfigCombo.Text := lDef.Config;
  FCompilerEdit.Text := lDef.TargetCompiler;
  FLibraryDbEdit.Text := lDef.LibraryDb;
  FillMemo(FRootsMemo, lDef.LibraryRoots);
  PlatformChange(nil);
end;

procedure TSetupForm.ProjectChanged;
var
  lCtx: TSetupContext;
begin
  FStatus.Caption := '';
  if (ProjectFile <> '') and TryLoadContext(ProjectFile, lCtx) then
  begin
    if FPlatformCombo.Items.IndexOf(lCtx.PlatformName) >= 0 then
      FPlatformCombo.ItemIndex := FPlatformCombo.Items.IndexOf(lCtx.PlatformName);
    FConfigCombo.Text := lCtx.Config;
    FillMemo(FDefinesMemo, lCtx.Defines);
    FillMemo(FSearchMemo, lCtx.SearchPath);
    FillMemo(FNamespacesMemo, lCtx.Namespaces);
    FLibraryDbEdit.Text := lCtx.LibraryDb;
    FCompilerEdit.Text := lCtx.TargetCompiler;
    FillMemo(FRootsMemo, lCtx.LibraryRoots);
    FStatus.Caption := 'Loaded ' + ContextFileFor(ProjectFile);
  end;
end;

procedure TSetupForm.BrowseClick(pSender: TObject);
var
  lDlg: TOpenDialog;
begin
  lDlg := TOpenDialog.Create(Self);
  try
    lDlg.Filter := 'Delphi project (*.dpr)|*.dpr|All files|*.*';
    if lDlg.Execute then
    begin
      FProjectEdit.Text := lDlg.FileName;
      ProjectChanged;
    end;
  finally
    lDlg.Free;
  end;
end;

procedure TSetupForm.SaveClick(pSender: TObject);
var
  lCtx: TSetupContext;
begin
  if (ProjectFile = '') or not FileExists(ProjectFile) then
  begin
    FStatus.Caption := 'Choose an existing .dpr first.';
    Exit;
  end;
  lCtx := Default(TSetupContext);
  lCtx.Project := ExpandFileName(ProjectFile);
  lCtx.SourceFile := lCtx.Project;
  lCtx.SourceSha1 := FileSha1(lCtx.Project);
  lCtx.PlatformName := FPlatformCombo.Text;
  lCtx.Config := Trim(FConfigCombo.Text);
  lCtx.Defines := SplitLines(FDefinesMemo.Text);
  lCtx.SearchPath := SplitLines(FSearchMemo.Text);
  lCtx.Namespaces := SplitLines(FNamespacesMemo.Text);
  lCtx.LibraryDb := Trim(FLibraryDbEdit.Text);
  lCtx.TargetCompiler := Trim(FCompilerEdit.Text);
  lCtx.LibraryRoots := SplitLines(FRootsMemo.Text);
  FStatus.Caption := 'Saved ' + SaveContext(lCtx);
end;

end.
