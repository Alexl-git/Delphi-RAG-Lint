unit ProjectSetup.MainForm;

{ Code-built setup form (no DFM). Plain VCL. }

interface

uses
  System.SysUtils, System.Classes, Vcl.Forms, Vcl.Controls, Vcl.StdCtrls,
  Vcl.Dialogs, DRagLint.Project.ContextFile, ProjectSetup.ContextJson;

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
    function AddEdit(pTop, pWidth: Integer): TEdit;
    function AddButton(const pCaption: string; pLeft, pWidth: Integer): TButton;
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
  GENERATED_BY = 'dl-project-setup 1.0';
  // Layout, in pixels. Rows are stacked top to bottom: label, then control.
  MARGIN = 12;
  CONTENT_WIDTH = 560;
  LABEL_HEIGHT = 15;
  LABEL_GAP = 18;
  EDIT_HEIGHT = 23;
  BUTTON_HEIGHT = 28;
  BROWSE_WIDTH = 82;
  SAVE_WIDTH = 80;
  BUTTON_GAP = 8;
  COMBO_WIDTH = 180;
  COMBO_COLUMN_GAP = 20;
  ROW_PROJECT = 8;
  ROW_PLATFORM = 58;
  ROW_DEFINES = 106;
  ROW_SEARCH = 216;
  ROW_NAMESPACES = 306;
  ROW_LIBRARY_DB = 376;
  ROW_ROOTS = 424;
  ROW_COMPILER = 494;
  ROW_STATUS = 556;
  ROW_BUTTONS = 596;
  HEIGHT_DEFINES = 100;
  HEIGHT_SEARCH = 80;
  HEIGHT_SMALL_MEMO = 60;
  MEMO_TRIM = 20;
  FORM_HEIGHT = 640;

constructor TSetupForm.CreateSetup(pOwner: TComponent; const pProjectFile: string);
var
  Plat: string;
  Btn: TButton;
begin
  inherited CreateNew(pOwner);
  Caption := 'dl-project-setup - project context';
  Position := poScreenCenter;
  BorderStyle := bsDialog;
  ClientWidth := CONTENT_WIDTH + 2 * MARGIN;
  ClientHeight := FORM_HEIGHT;

  AddLabel('Project file (.dpr)', ROW_PROJECT);
  FProjectEdit := AddEdit(ROW_PROJECT + LABEL_GAP, CONTENT_WIDTH - BROWSE_WIDTH - BUTTON_GAP);
  AddButton('Browse...', MARGIN + CONTENT_WIDTH - BROWSE_WIDTH, BROWSE_WIDTH).OnClick := BrowseClick;

  AddLabel('Target platform', ROW_PLATFORM);
  FPlatformCombo := TComboBox.Create(Self);
  FPlatformCombo.Parent := Self;
  FPlatformCombo.Style := csDropDownList;
  FPlatformCombo.SetBounds(MARGIN, ROW_PLATFORM + LABEL_GAP, COMBO_WIDTH, EDIT_HEIGHT);
  for Plat in SetupPlatforms do
    FPlatformCombo.Items.Add(Plat);
  FPlatformCombo.ItemIndex := FPlatformCombo.Items.IndexOf('Win32');
  FPlatformCombo.OnChange := PlatformChange;

  AddLabel('Configuration', ROW_PLATFORM).Left := MARGIN + COMBO_WIDTH + COMBO_COLUMN_GAP;
  FConfigCombo := TComboBox.Create(Self);
  FConfigCombo.Parent := Self;
  FConfigCombo.Style := csDropDown;
  FConfigCombo.SetBounds(MARGIN + COMBO_WIDTH + COMBO_COLUMN_GAP, ROW_PLATFORM + LABEL_GAP, COMBO_WIDTH, EDIT_HEIGHT);
  FConfigCombo.Items.Add('Debug');
  FConfigCombo.Items.Add('Release');
  FConfigCombo.Text := 'Debug';
  FConfigCombo.OnChange := PlatformChange;

  FDefinesMemo := AddMemo('Conditional defines (one per line)', ROW_DEFINES, HEIGHT_DEFINES);
  FSearchMemo := AddMemo('Unit search path (one per line)', ROW_SEARCH, HEIGHT_SEARCH);
  FNamespacesMemo := AddMemo('Namespaces (one per line)', ROW_NAMESPACES, HEIGHT_SMALL_MEMO);

  AddLabel('Library DB path (optional)', ROW_LIBRARY_DB);
  FLibraryDbEdit := AddEdit(ROW_LIBRARY_DB + LABEL_GAP, CONTENT_WIDTH);

  FRootsMemo := AddMemo('RTL/VCL source roots (optional, one per line)', ROW_ROOTS, HEIGHT_SMALL_MEMO);

  AddLabel('Target compiler (optional, e.g. 37; empty = default)', ROW_COMPILER);
  FCompilerEdit := AddEdit(ROW_COMPILER + LABEL_GAP, COMBO_WIDTH);

  FStatus := AddLabel('', ROW_STATUS);
  AddButton('Save', MARGIN + CONTENT_WIDTH - BROWSE_WIDTH - BUTTON_GAP - SAVE_WIDTH, SAVE_WIDTH).OnClick := SaveClick;
  Btn := AddButton('Close', MARGIN + CONTENT_WIDTH - BROWSE_WIDTH, BROWSE_WIDTH);
  Btn.Cancel := True;
  Btn.ModalResult := mrCancel;

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
  Result.SetBounds(MARGIN, pTop, CONTENT_WIDTH, LABEL_HEIGHT);
end;

function TSetupForm.AddEdit(pTop, pWidth: Integer): TEdit;
begin
  Result := TEdit.Create(Self);
  Result.Parent := Self;
  Result.SetBounds(MARGIN, pTop, pWidth, EDIT_HEIGHT);
end;

function TSetupForm.AddButton(const pCaption: string; pLeft, pWidth: Integer): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := Self;
  Result.Caption := pCaption;
  Result.SetBounds(pLeft, ROW_BUTTONS, pWidth, BUTTON_HEIGHT);
end;

function TSetupForm.AddMemo(const pCaption: string; pTop, pHeight: Integer): TMemo;
begin
  AddLabel(pCaption, pTop);
  Result := TMemo.Create(Self);
  Result.Parent := Self;
  Result.ScrollBars := ssVertical;
  Result.SetBounds(MARGIN, pTop + LABEL_GAP, CONTENT_WIDTH, pHeight - MEMO_TRIM);
end;

procedure TSetupForm.FillMemo(pMemo: TMemo; const pItems: TArray<string>);
var
  Item: string;
begin
  pMemo.Lines.Clear;
  for Item in pItems do
    pMemo.Lines.Add(Item);
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
  Def: TContextDefaults;
  Lib: TLibraryDefault;
begin
  if not TryLoadContextDefaults(Def) then
    Exit;
  if FPlatformCombo.Items.IndexOf(Def.Platform) >= 0 then
    FPlatformCombo.ItemIndex := FPlatformCombo.Items.IndexOf(Def.Platform);
  if Def.Config <> '' then
    FConfigCombo.Text := Def.Config;
  FCompilerEdit.Text := Def.TargetCompiler;
  for Lib in Def.Libraries do
    if SameText(Lib.Platform, FPlatformCombo.Text) then
    begin
      FLibraryDbEdit.Text := Lib.LibraryDb;
      FillMemo(FRootsMemo, Lib.LibraryRoots);
    end;
  PlatformChange(nil);
end;

procedure TSetupForm.ProjectChanged;
var
  Ctx: TProjectContext;
begin
  FStatus.Caption := '';
  if (ProjectFile <> '') and TryLoadProjectContext(ContextFileFor(ProjectFile), Ctx) then
  begin
    if FPlatformCombo.Items.IndexOf(Ctx.Platform) >= 0 then
      FPlatformCombo.ItemIndex := FPlatformCombo.Items.IndexOf(Ctx.Platform);
    FConfigCombo.Text := Ctx.Config;
    FillMemo(FDefinesMemo, Ctx.Defines);
    FillMemo(FSearchMemo, Ctx.SearchPath);
    FillMemo(FNamespacesMemo, Ctx.Namespaces);
    FLibraryDbEdit.Text := Ctx.LibraryDb;
    FCompilerEdit.Text := Ctx.TargetCompiler;
    FillMemo(FRootsMemo, Ctx.LibraryRoots);
    FStatus.Caption := 'Loaded ' + ContextFileFor(ProjectFile);
  end;
end;

procedure TSetupForm.BrowseClick(pSender: TObject);
var
  Dlg: TOpenDialog;
begin
  Dlg := TOpenDialog.Create(Self);
  try
    Dlg.Filter := 'Delphi project (*.dpr)|*.dpr|All files|*.*';
    if Dlg.Execute then
    begin
      FProjectEdit.Text := Dlg.FileName;
      ProjectChanged;
    end;
  finally
    Dlg.Free;
  end;
end;

procedure TSetupForm.SaveClick(pSender: TObject);
var
  Ctx: TProjectContext;
begin
  if (ProjectFile = '') or not FileExists(ProjectFile) then
  begin
    FStatus.Caption := 'Choose an existing .dpr first.';
    Exit;
  end;
  Ctx := Default(TProjectContext);
  Ctx.Schema := CONTEXT_SCHEMA;
  Ctx.GeneratedBy := GENERATED_BY;
  Ctx.Project := ExpandFileName(ProjectFile);
  Ctx.SourceFile := Ctx.Project;
  Ctx.SourceSha1 := FileSha1Hex(Ctx.Project);
  Ctx.Platform := FPlatformCombo.Text;
  Ctx.Config := Trim(FConfigCombo.Text);
  Ctx.Defines := SplitLines(FDefinesMemo.Text);
  Ctx.SearchPath := SplitLines(FSearchMemo.Text);
  Ctx.Namespaces := SplitLines(FNamespacesMemo.Text);
  Ctx.LibraryDb := Trim(FLibraryDbEdit.Text);
  Ctx.TargetCompiler := Trim(FCompilerEdit.Text);
  Ctx.LibraryRoots := SplitLines(FRootsMemo.Text);
  SaveProjectContext(Ctx, ContextFileFor(Ctx.Project));
  FStatus.Caption := 'Saved ' + ContextFileFor(Ctx.Project);
end;

end.
