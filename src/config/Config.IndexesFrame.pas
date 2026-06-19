unit Config.IndexesFrame;

/// <summary>Frame hosting the section list editor for drag-lint index manifests.
/// Left panel: list of section names with Add/Delete. Right panel: editor for
/// the selected TIndexSection fields. Bottom: TPageControl with
/// Coverage / Plan preview / Build log tabs. Plan preview tab contains a
/// read-only TListView (lvPlan) populated by ResolvePlan. Build log tab has
/// a TMemo for streamed engine output and buttons for Build All, Build
/// Selected, and Library Drift.</summary>

interface

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.Generics.Collections,
  Winapi.Windows,
  Winapi.Messages,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.ComCtrls,
  Vcl.Dialogs,
  Vcl.FileCtrl,
  Vcl.Menus,
  Vcl.Graphics,
  DRagLint.Index.Manifest,
  DRagLint.Index.Plan,
  DRagLint.Index.Coverage,
  DRagLint.Project.Resolver,
  Config.EngineRunner;

type
  /// <summary>Typed pointer to TIndexManifest, used by BindManifest so the frame
  /// and main form share a single working instance without copying.</summary>
  PIndexManifest = ^TIndexManifest;

  /// <summary>Editor frame for the Indexes tab. Binds to a TIndexManifest pointer
  /// so the main form and this frame share a single working manifest.</summary>
  TIndexesFrame = class(TFrame)
    splMain: TSplitter;
    pnlLeft: TPanel;
    lbSections: TListBox;
    pnlLeftBtns: TPanel;
    btnAddSection: TButton;
    btnDelSection: TButton;
    pnlRight: TPanel;
    scrEditor: TScrollBox;
    lblName: TLabel;
    edName: TEdit;
    lblDb: TLabel;
    edDb: TEdit;
    lblSource: TLabel;
    rgSource: TRadioGroup;
    lblPlatforms: TLabel;
    edPlatforms: TEdit;
    lblInclude: TLabel;
    lbInclude: TListBox;
    pnlIncludeBtns: TPanel;
    btnAddFolder: TButton;
    btnAddDproj: TButton;
    btnRemoveInclude: TButton;
    lblExclude: TLabel;
    edExclude: TEdit;
    lblIncludeOnly: TLabel;
    edIncludeOnly: TEdit;
    lblDedup: TLabel;
    edDedup: TEdit;
    cbUseIgnore: TCheckBox;
    cbSqlOnlyMS: TCheckBox;
    splBottom: TSplitter;
    pcBottom: TPageControl;
    tsCoverage: TTabSheet;
    pnlCovTop: TPanel;
    lblCovRoot: TLabel;
    edCovRoot: TEdit;
    btnCovBrowse: TButton;
    btnCovRefresh: TButton;
    tvCoverage: TTreeView;
    pmCoverage: TPopupMenu;
    tsPlanPreview: TTabSheet;
    lvPlan: TListView;
    btnRefreshPlan: TButton;
    pnlPlanTop: TPanel;
    tsBuildLog: TTabSheet;
    pnlBuildBtns: TPanel;
    btnBuildAll: TButton;
    btnBuildSelected: TButton;
    btnDrift: TButton;
    mLog: TMemo;
    procedure lbSectionsClick(Sender: TObject);
    procedure pcBottomChange(Sender: TObject);
    procedure btnRefreshPlanClick(Sender: TObject);
    procedure btnAddSectionClick(Sender: TObject);
    procedure btnDelSectionClick(Sender: TObject);
    procedure edNameChange(Sender: TObject);
    procedure edDbChange(Sender: TObject);
    procedure rgSourceClick(Sender: TObject);
    procedure edPlatformsChange(Sender: TObject);
    procedure lbIncludeClick(Sender: TObject);
    procedure btnAddFolderClick(Sender: TObject);
    procedure btnAddDprojClick(Sender: TObject);
    procedure btnRemoveIncludeClick(Sender: TObject);
    procedure edExcludeChange(Sender: TObject);
    procedure edIncludeOnlyChange(Sender: TObject);
    procedure edDedupChange(Sender: TObject);
    procedure cbUseIgnoreClick(Sender: TObject);
    procedure cbSqlOnlyMSClick(Sender: TObject);
    procedure btnBuildAllClick(Sender: TObject);
    procedure btnBuildSelectedClick(Sender: TObject);
    procedure btnDriftClick(Sender: TObject);
    procedure btnCovBrowseClick(Sender: TObject);
    procedure btnCovRefreshClick(Sender: TObject);
    procedure tvCoverageCustomDrawItem(Sender: TCustomTreeView;
      Node: TTreeNode; State: TCustomDrawState; var DefaultDraw: Boolean);
    procedure tvCoverageExpanding(Sender: TObject; Node: TTreeNode;
      var AllowExpansion: Boolean);
    procedure pmCoveragePopup(Sender: TObject);
  private
    FManifest:      PIndexManifest;
    FLoading:       Boolean;
    FOpenDialog:    TOpenDialog;
    FRunning:       Boolean;
    FConfigPath:    string;
    FOnSaveNeeded:  TProc;
    { Coverage tab: parallel list of TCoverageItem for each leaf node.
      Index stored in Node.Data as Pointer(idx+1); 0 = dummy child sentinel.
      Freed in the destructor. }
    FCoverageItems: TList<TCoverageItem>;
    /// <summary>Split a semicolon-joined string into a TArray of strings,
    /// trimming each element and ignoring empty entries.</summary>
    /// <param name="S">Semicolon-joined input string.</param>
    /// <returns>Array of trimmed non-empty parts.</returns>
    function SplitSemicolon(const S: string): TArray<string>;
    /// <summary>Join a TArray of strings with '; ' as the delimiter.</summary>
    /// <param name="A">Array of strings to join.</param>
    /// <returns>Joined string.</returns>
    function JoinSemicolon(const A: TArray<string>): string;
    /// <summary>Return the coverage item index stored in a tree node, or -1
    /// if the node is a root or dummy child sentinel.</summary>
    /// <param name="ANode">The tree node to query.</param>
    /// <returns>Zero-based index into FCoverageItems, or -1.</returns>
    function NodeCovIdx(ANode: TTreeNode): Integer;
    /// <summary>Populate child nodes of AParent from ComputeCoverage for
    /// AFolderPath. Each child gets a dummy grandchild so it shows [+].
    /// Appends new TCoverageItem entries to FCoverageItems; stores
    /// Pointer(idx+1) in Node.Data. A resolver is created then freed by
    /// this method.</summary>
    /// <param name="AParent">Tree node to add children to.</param>
    /// <param name="AFolderPath">Absolute folder to classify children of.</param>
    procedure PopulateCoverageChildren(AParent: TTreeNode;
      const AFolderPath: string);
    /// <summary>Rebuild the tvCoverage tree for edCovRoot.Text.
    /// Clears FCoverageItems; calls ComputeCoverage for the root; each
    /// child folder gets a single dummy grandchild so [+] is shown.
    /// No-op when edCovRoot.Text is empty or FManifest is nil.</summary>
    procedure RefreshCoverage;
    /// <summary>Return the font colour for a given coverage kind.</summary>
    /// <param name="AKind">Coverage classification of the folder.</param>
    /// <returns>TColor constant matching the kind.</returns>
    function CovKindColor(AKind: TCoverageKind): TColor;
    /// <summary>Popup menu handler: assign the selected coverage node's folder
    /// to the section whose index is stored in Sender.Tag. Appends to Include
    /// (duplicate-guarded), refreshes the section list and coverage tree.</summary>
    /// <param name="Sender">TMenuItem whose Tag is the section index.</param>
    procedure CovAssignToSectionClick(Sender: TObject);
    /// <summary>Popup menu handler: create a new TIndexSection whose Include
    /// contains the selected coverage node's folder. Prompts for the section
    /// name (default = sanitized leaf), appends to FManifest^.Sections, and
    /// refreshes the section list and coverage tree.</summary>
    /// <param name="Sender">TMenuItem (unused beyond dispatch).</param>
    procedure CovNewDbFromFolderClick(Sender: TObject);
    /// <summary>Return the index of the currently selected section, or -1 if
    /// nothing is selected or FManifest is nil.</summary>
    /// <returns>Zero-based section index, or -1.</returns>
    function SelectedSectionIndex: Integer;
    /// <summary>Load the fields of the section at index AIdx into the editor
    /// controls. Sets FLoading to suppress change events during load.</summary>
    /// <param name="AIdx">Zero-based section index.</param>
    procedure LoadSectionToControls(AIdx: Integer);
    /// <summary>Write the current editor control values back into the section
    /// at index AIdx in FManifest^. No-op if FLoading is True.</summary>
    /// <param name="AIdx">Zero-based section index.</param>
    procedure SaveControlsToSection(AIdx: Integer);
    /// <summary>Rebuild the lbSections listbox from FManifest^.Sections,
    /// preserving the current selection if possible.</summary>
    procedure RefreshSectionList;
    /// <summary>Enable or disable the right-hand editor controls based on
    /// whether a section is currently selected.</summary>
    /// <param name="AEnabled">True to enable; False to disable.</param>
    procedure SetEditorEnabled(AEnabled: Boolean);
    /// <summary>Populate lvPlan from the current FManifest by calling ResolvePlan.
    /// One row per TPlanSection: Name, Mode, DbPath, Platform, Roots count,
    /// DedupExcludeRoots count. Silently clears lvPlan on error.</summary>
    /// <remarks>Not thread-safe; call from the main (UI) thread only.</remarks>
    procedure RefreshPlanPreview;
    /// <summary>Convert a TPlanSectionMode to a short display string.</summary>
    /// <param name="AMode">The mode to convert.</param>
    /// <returns>'folderTree', 'closure', or 'library'.</returns>
    function PlanModeDisplayStr(const AMode: TPlanSectionMode): string;
    /// <summary>Enable or disable the three build/drift buttons together.</summary>
    /// <param name="AEnabled">True to enable; False to disable.</param>
    procedure SetBuildButtonsEnabled(AEnabled: Boolean);
    /// <summary>Append ALine to mLog (scrolls to end). Called on the main thread
    /// by TEngineRunner.TRunnerThread via TThread.Queue.</summary>
    /// <param name="ALine">Line of output from the engine process.</param>
    procedure AppendLogLine(const ALine: string);
    /// <summary>Launch the engine with AArgs. Saves first via FOnSaveNeeded;
    /// if the engine path cannot be resolved, logs an error. Disables build
    /// buttons while running; re-enables + logs exit code when done.</summary>
    /// <param name="AArgs">Argument string for drag-lint.exe.</param>
    procedure RunEngine(const AArgs: string);
  public
    /// <summary>Free the coverage item list and all owned objects.</summary>
    destructor Destroy; override;
    /// <summary>Bind the frame to a manifest pointer. The pointer must remain
    /// valid for the lifetime of the frame (owned by TMainForm). Rebuilds the
    /// section list and clears the editor.</summary>
    /// <param name="AManifest">Pointer to the main form's working TIndexManifest.</param>
    /// <remarks>Not thread-safe; call from the main (UI) thread only.</remarks>
    procedure BindManifest(AManifest: PIndexManifest);
    /// <summary>Flush any pending edits from the currently selected section's
    /// controls back into FManifest^. Called by TMainForm before Save.</summary>
    /// <remarks>Not thread-safe; call from the main (UI) thread only.</remarks>
    procedure FlushToManifest;
    /// <summary>Absolute path of the config file currently open in the main form.
    /// Set by TMainForm after load/save. Used by build/drift button handlers
    /// to pass --config to the engine.</summary>
    property ConfigPath: string read FConfigPath write FConfigPath;
    /// <summary>Callback invoked by RunEngine before spawning the process so the
    /// main form can flush edits and write the config file to disk. Assign
    /// TMainForm's save routine here. Optional: if nil, no save is performed.</summary>
    property OnSaveNeeded: TProc read FOnSaveNeeded write FOnSaveNeeded;
  end;

implementation

{$R *.dfm}

{ helpers }

function TIndexesFrame.SplitSemicolon(const S: string): TArray<string>;
var
  Parts: TArray<string>;
  I, N: Integer;
  T: string;
begin
  Parts := S.Split([';']);
  SetLength(Result, Length(Parts));
  N := 0;
  for I := 0 to High(Parts) do
  begin
    T := Trim(Parts[I]);
    if T <> '' then
    begin
      Result[N] := T;
      Inc(N);
    end;
  end;
  SetLength(Result, N);
end;

function TIndexesFrame.JoinSemicolon(const A: TArray<string>): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to High(A) do
  begin
    if Result <> '' then
      Result := Result + '; ';
    Result := Result + A[I];
  end;
end;

function TIndexesFrame.SelectedSectionIndex: Integer;
begin
  if (FManifest = nil) or (lbSections.ItemIndex < 0) then
    Result := -1
  else
    Result := lbSections.ItemIndex;
end;

procedure TIndexesFrame.LoadSectionToControls(AIdx: Integer);
var
  Sec: TIndexSection;
  S: string;
begin
  if (FManifest = nil) or (AIdx < 0) or (AIdx > High(FManifest^.Sections)) then
  begin
    SetEditorEnabled(False);
    Exit;
  end;

  FLoading := True;
  try
    Sec := FManifest^.Sections[AIdx];

    edName.Text := Sec.Name;
    edDb.Text   := Sec.Db;

    if Sec.Source = 'registry-libraries' then
      rgSource.ItemIndex := 1
    else
      rgSource.ItemIndex := 0;

    edPlatforms.Text := JoinSemicolon(Sec.Platforms);

    lbInclude.Clear;
    for S in Sec.Include do
      lbInclude.Items.Add(S);

    edExclude.Text     := JoinSemicolon(Sec.Exclude);
    edIncludeOnly.Text := JoinSemicolon(Sec.IncludeOnly);
    edDedup.Text       := JoinSemicolon(Sec.DedupAgainst);

    cbUseIgnore.Checked := Sec.UseIgnoreFiles;
    cbSqlOnlyMS.Checked := Sec.SqlOnlyMS;

    SetEditorEnabled(True);
  finally
    FLoading := False;
  end;
end;

procedure TIndexesFrame.SaveControlsToSection(AIdx: Integer);
var
  I: Integer;
begin
  if FLoading then Exit;
  if (FManifest = nil) or (AIdx < 0) or (AIdx > High(FManifest^.Sections)) then
    Exit;

  with FManifest^.Sections[AIdx] do
  begin
    Name := edName.Text;
    Db   := edDb.Text;

    if rgSource.ItemIndex = 1 then
      Source := 'registry-libraries'
    else
      Source := '';

    Platforms    := SplitSemicolon(edPlatforms.Text);
    Exclude      := SplitSemicolon(edExclude.Text);
    IncludeOnly  := SplitSemicolon(edIncludeOnly.Text);
    DedupAgainst := SplitSemicolon(edDedup.Text);

    SetLength(Include, lbInclude.Items.Count);
    for I := 0 to lbInclude.Items.Count - 1 do
      Include[I] := lbInclude.Items[I];

    UseIgnoreFiles := cbUseIgnore.Checked;
    SqlOnlyMS      := cbSqlOnlyMS.Checked;
  end;

  { Refresh the section name in the listbox in case Name changed }
  lbSections.Items[AIdx] := FManifest^.Sections[AIdx].Name;
end;

procedure TIndexesFrame.RefreshSectionList;
var
  I, PrevIdx: Integer;
begin
  PrevIdx := lbSections.ItemIndex;
  lbSections.Items.BeginUpdate;
  try
    lbSections.Clear;
    if FManifest <> nil then
      for I := 0 to High(FManifest^.Sections) do
        lbSections.Items.Add(FManifest^.Sections[I].Name);
  finally
    lbSections.Items.EndUpdate;
  end;

  if (PrevIdx >= 0) and (PrevIdx < lbSections.Count) then
    lbSections.ItemIndex := PrevIdx
  else if lbSections.Count > 0 then
    lbSections.ItemIndex := 0
  else
    lbSections.ItemIndex := -1;

  LoadSectionToControls(lbSections.ItemIndex);
end;

procedure TIndexesFrame.SetEditorEnabled(AEnabled: Boolean);
begin
  edName.Enabled        := AEnabled;
  edDb.Enabled          := AEnabled;
  rgSource.Enabled      := AEnabled;
  edPlatforms.Enabled   := AEnabled;
  lbInclude.Enabled     := AEnabled;
  btnAddFolder.Enabled  := AEnabled;
  btnAddDproj.Enabled   := AEnabled;
  btnRemoveInclude.Enabled := AEnabled;
  edExclude.Enabled     := AEnabled;
  edIncludeOnly.Enabled := AEnabled;
  edDedup.Enabled       := AEnabled;
  cbUseIgnore.Enabled   := AEnabled;
  cbSqlOnlyMS.Enabled   := AEnabled;
end;

{ public }

procedure TIndexesFrame.BindManifest(AManifest: PIndexManifest);
var
  DefaultRoot: string;
begin
  FManifest := AManifest;
  RefreshSectionList;

  { Set coverage root default: parent of OutDir if set, else C:\Projects }
  DefaultRoot := 'C:\Projects';
  if (AManifest <> nil) and (AManifest^.OutDir <> '') then
  begin
    var AbsOut: string;
    if TPath.IsPathRooted(AManifest^.OutDir) then
      AbsOut := AManifest^.OutDir
    else if AManifest^.RootDir <> '' then
      AbsOut := TPath.Combine(AManifest^.RootDir, AManifest^.OutDir)
    else
      AbsOut := '';
    if AbsOut <> '' then
    begin
      var Parent: string;
      Parent := TPath.GetDirectoryName(ExcludeTrailingPathDelimiter(AbsOut));
      if (Parent <> '') and TDirectory.Exists(Parent) then
        DefaultRoot := Parent;
    end;
  end;
  if edCovRoot.Text = '' then
    edCovRoot.Text := DefaultRoot;
end;

procedure TIndexesFrame.FlushToManifest;
begin
  SaveControlsToSection(SelectedSectionIndex);
end;

function TIndexesFrame.PlanModeDisplayStr(const AMode: TPlanSectionMode): string;
begin
  case AMode of
    smFolderTree: Result := 'folderTree';
    smClosure:    Result := 'closure';
    smLibrary:    Result := 'library';
  else
    Result := 'folderTree';
  end;
end;

procedure TIndexesFrame.RefreshPlanPreview;
var
  Resolver: TProjectResolver;
  Plan:     TIndexPlan;
  Sec:      TPlanSection;
  Item:     TListItem;
  I:        Integer;
begin
  lvPlan.Items.BeginUpdate;
  try
    lvPlan.Items.Clear;
    if FManifest = nil then Exit;

    { Flush pending edits so the plan reflects the current UI state }
    SaveControlsToSection(SelectedSectionIndex);

    Resolver := TProjectResolver.Create;
    try
      Plan := ResolvePlan(FManifest^, nil, Resolver);
    finally
      Resolver.Free;
    end;

    for I := 0 to High(Plan.Items) do
    begin
      Sec  := Plan.Items[I];
      Item := lvPlan.Items.Add;
      Item.Caption    := Sec.Name;
      Item.SubItems.Add(PlanModeDisplayStr(Sec.Mode));
      Item.SubItems.Add(Sec.DbPath);
      Item.SubItems.Add(Sec.Platform);
      Item.SubItems.Add(IntToStr(Length(Sec.Roots)));
      Item.SubItems.Add(IntToStr(Length(Sec.DedupExcludeRoots)));
    end;
  except
    { swallow so preview never crashes the app; list stays cleared }
  end;
  lvPlan.Items.EndUpdate;
end;

{ event handlers }

procedure TIndexesFrame.lbSectionsClick(Sender: TObject);
begin
  LoadSectionToControls(lbSections.ItemIndex);
end;

procedure TIndexesFrame.btnAddSectionClick(Sender: TObject);
var
  NewSec: TIndexSection;
  N: Integer;
begin
  if FManifest = nil then Exit;

  NewSec            := Default(TIndexSection);
  NewSec.Name       := 'NewDB';
  NewSec.UseIgnoreFiles := True;
  NewSec.SqlOnlyMS  := True;
  NewSec.Include    := [];

  N := Length(FManifest^.Sections);
  SetLength(FManifest^.Sections, N + 1);
  FManifest^.Sections[N] := NewSec;

  lbSections.Items.Add(NewSec.Name);
  lbSections.ItemIndex := N;
  LoadSectionToControls(N);
end;

procedure TIndexesFrame.btnDelSectionClick(Sender: TObject);
var
  Idx, I, N: Integer;
begin
  Idx := SelectedSectionIndex;
  if Idx < 0 then Exit;

  N := Length(FManifest^.Sections);
  for I := Idx to N - 2 do
    FManifest^.Sections[I] := FManifest^.Sections[I + 1];
  SetLength(FManifest^.Sections, N - 1);

  lbSections.Items.Delete(Idx);

  if lbSections.Count > 0 then
  begin
    if Idx >= lbSections.Count then
      lbSections.ItemIndex := lbSections.Count - 1
    else
      lbSections.ItemIndex := Idx;
    LoadSectionToControls(lbSections.ItemIndex);
  end
  else
  begin
    lbSections.ItemIndex := -1;
    SetEditorEnabled(False);
  end;
end;

procedure TIndexesFrame.edNameChange(Sender: TObject);
begin
  SaveControlsToSection(SelectedSectionIndex);
end;

procedure TIndexesFrame.edDbChange(Sender: TObject);
begin
  SaveControlsToSection(SelectedSectionIndex);
end;

procedure TIndexesFrame.rgSourceClick(Sender: TObject);
begin
  SaveControlsToSection(SelectedSectionIndex);
end;

procedure TIndexesFrame.edPlatformsChange(Sender: TObject);
begin
  SaveControlsToSection(SelectedSectionIndex);
end;

procedure TIndexesFrame.lbIncludeClick(Sender: TObject);
begin
  { Selection change only; no write-back needed here }
end;

procedure TIndexesFrame.btnAddFolderClick(Sender: TObject);
var
  Dir: string;
begin
  Dir := '';
  if SelectDirectory('Select folder to include', '', Dir) then
  begin
    lbInclude.Items.Add(Dir);
    SaveControlsToSection(SelectedSectionIndex);
  end;
end;

procedure TIndexesFrame.btnAddDprojClick(Sender: TObject);
begin
  if FOpenDialog = nil then
  begin
    FOpenDialog := TOpenDialog.Create(Self);
    FOpenDialog.Title  := 'Select project file';
    FOpenDialog.Filter := 'Delphi project|*.dpr;*.dproj|All files|*.*';
    FOpenDialog.Options := FOpenDialog.Options + [ofFileMustExist];
  end;

  if FOpenDialog.Execute then
  begin
    lbInclude.Items.Add(FOpenDialog.FileName);
    SaveControlsToSection(SelectedSectionIndex);
  end;
end;

procedure TIndexesFrame.btnRemoveIncludeClick(Sender: TObject);
begin
  if lbInclude.ItemIndex >= 0 then
  begin
    lbInclude.Items.Delete(lbInclude.ItemIndex);
    SaveControlsToSection(SelectedSectionIndex);
  end;
end;

procedure TIndexesFrame.edExcludeChange(Sender: TObject);
begin
  SaveControlsToSection(SelectedSectionIndex);
end;

procedure TIndexesFrame.edIncludeOnlyChange(Sender: TObject);
begin
  SaveControlsToSection(SelectedSectionIndex);
end;

procedure TIndexesFrame.edDedupChange(Sender: TObject);
begin
  SaveControlsToSection(SelectedSectionIndex);
end;

procedure TIndexesFrame.cbUseIgnoreClick(Sender: TObject);
begin
  SaveControlsToSection(SelectedSectionIndex);
end;

procedure TIndexesFrame.cbSqlOnlyMSClick(Sender: TObject);
begin
  SaveControlsToSection(SelectedSectionIndex);
end;

procedure TIndexesFrame.pcBottomChange(Sender: TObject);
begin
  if pcBottom.ActivePage = tsPlanPreview then
    RefreshPlanPreview
  else if pcBottom.ActivePage = tsCoverage then
  begin
    if edCovRoot.Text <> '' then
      RefreshCoverage;
  end;
end;

procedure TIndexesFrame.btnRefreshPlanClick(Sender: TObject);
begin
  RefreshPlanPreview;
end;

{ Build log helpers }

procedure TIndexesFrame.SetBuildButtonsEnabled(AEnabled: Boolean);
begin
  btnBuildAll.Enabled      := AEnabled;
  btnBuildSelected.Enabled := AEnabled;
  btnDrift.Enabled         := AEnabled;
end;

procedure TIndexesFrame.AppendLogLine(const ALine: string);
begin
  mLog.Lines.Add(ALine);
  { Scroll to the last line }
  SendMessage(mLog.Handle, WM_VSCROLL, SB_BOTTOM, 0);
end;

procedure TIndexesFrame.RunEngine(const AArgs: string);
var
  ExePath: string;
  EngPath: string;
begin
  if FRunning then
  begin
    AppendLogLine('[already running -- wait for the current run to finish]');
    Exit;
  end;

  { Save the manifest to disk so the engine reads current state }
  if Assigned(FOnSaveNeeded) then
    FOnSaveNeeded();

  { Resolve engine path from settings }
  EngPath := '';
  if FManifest <> nil then
    EngPath := FManifest^.Settings.EnginePath;
  ExePath := TEngineRunner.ResolveEngineExe(EngPath);

  if ExePath = '' then
  begin
    mLog.Lines.Add('[ERROR] drag-lint.exe not found. Set the engine path in Settings.');
    Exit;
  end;

  mLog.Clear;
  mLog.Lines.Add('> ' + ExePath + ' ' + AArgs);
  mLog.Lines.Add('');
  SetBuildButtonsEnabled(False);
  FRunning := True;

  TEngineRunner.Run(ExePath, AArgs,
    procedure(ALine: string)
    begin
      AppendLogLine(ALine);
    end,
    procedure(ACode: Integer)
    begin
      FRunning := False;
      AppendLogLine('');
      AppendLogLine('=== exit ' + IntToStr(ACode) + ' ===');
      SetBuildButtonsEnabled(True);
    end);
end;

{ Build log button handlers }

procedure TIndexesFrame.btnBuildAllClick(Sender: TObject);
var
  Args: string;
begin
  pcBottom.ActivePage := tsBuildLog;
  Args := 'index --all --jobs 0';
  if FConfigPath <> '' then
    Args := Args + ' --config "' + FConfigPath + '"';
  RunEngine(Args);
end;

procedure TIndexesFrame.btnBuildSelectedClick(Sender: TObject);
var
  Args, Names: string;
  I: Integer;
begin
  pcBottom.ActivePage := tsBuildLog;
  Names := '';
  for I := 0 to lbSections.Count - 1 do
    if lbSections.Selected[I] then
    begin
      if Names <> '' then Names := Names + ',';
      Names := Names + lbSections.Items[I];
    end;
  { Fall back to the single-selected item if multi-select not active }
  if (Names = '') and (lbSections.ItemIndex >= 0) then
    Names := lbSections.Items[lbSections.ItemIndex];

  if Names = '' then
  begin
    mLog.Clear;
    mLog.Lines.Add('[No section selected -- select one in the list first]');
    Exit;
  end;

  Args := 'index --all --only ' + Names;
  if FConfigPath <> '' then
    Args := Args + ' --config "' + FConfigPath + '"';
  RunEngine(Args);
end;

procedure TIndexesFrame.btnDriftClick(Sender: TObject);
var
  Args: string;
begin
  pcBottom.ActivePage := tsBuildLog;
  Args := 'library-drift';
  if FConfigPath <> '' then
    Args := Args + ' --config "' + FConfigPath + '"';
  RunEngine(Args);
end;

{ Coverage tab helpers }

destructor TIndexesFrame.Destroy;
begin
  FCoverageItems.Free;
  inherited;
end;

function TIndexesFrame.CovKindColor(AKind: TCoverageKind): TColor;
begin
  case AKind of
    ckIndexed:    Result := clGreen;
    ckOverlap:    Result := clOlive;
    ckExcluded:   Result := clGray;
    ckLibrary:    Result := clNavy;
  else
    Result := clRed;
  end;
end;

function TIndexesFrame.NodeCovIdx(ANode: TTreeNode): Integer;
begin
  if ANode = nil then
    Result := -1
  else
    Result := Integer(ANode.Data) - 1;
end;

procedure TIndexesFrame.PopulateCoverageChildren(AParent: TTreeNode;
  const AFolderPath: string);
var
  Resolver: TProjectResolver;
  Items:    TArray<TCoverageItem>;
  Item:     TCoverageItem;
  Leaf:     string;
  Caption:  string;
  Child:    TTreeNode;
  Idx:      Integer;
begin
  if FManifest = nil then Exit;

  Resolver := TProjectResolver.Create;
  try
    Items := ComputeCoverage(FManifest^, AFolderPath, Resolver);
  finally
    Resolver.Free;
  end;

  tvCoverage.Items.BeginUpdate;
  try
    for Item in Items do
    begin
      Leaf := TPath.GetFileName(Item.Folder);
      if Item.Detail <> '' then
        Caption := Leaf + '  [' + CoverageKindStr(Item.Kind) + ']  ' + Item.Detail
      else
        Caption := Leaf + '  [' + CoverageKindStr(Item.Kind) + ']';

      { Append item to FCoverageItems; store 1-based index in Node.Data }
      Idx := FCoverageItems.Add(Item);
      Child := tvCoverage.Items.AddChild(AParent, Caption);
      Child.Data := Pointer(Idx + 1);

      { Add a dummy grandchild so the node shows a [+] expander.
        Dummy sentinel is marked with Data=nil (index 0 means "real item 0",
        so we can't use 0; use nil for the dummy). }
      tvCoverage.Items.AddChild(Child, '').Data := nil;
    end;
  finally
    tvCoverage.Items.EndUpdate;
  end;
end;

procedure TIndexesFrame.RefreshCoverage;
var
  Root:     TTreeNode;
  RootPath: string;
begin
  if FManifest = nil then Exit;
  RootPath := Trim(edCovRoot.Text);
  if RootPath = '' then Exit;

  tvCoverage.Items.BeginUpdate;
  try
    tvCoverage.Items.Clear;
    { Re-create the items list on every full refresh }
    if FCoverageItems = nil then
      FCoverageItems := TList<TCoverageItem>.Create
    else
      FCoverageItems.Clear;

    Root := tvCoverage.Items.Add(nil, RootPath);
    Root.Data := nil;

    PopulateCoverageChildren(Root, RootPath);
    Root.Expand(False);
  finally
    tvCoverage.Items.EndUpdate;
  end;
end;

{ Coverage event handlers }

procedure TIndexesFrame.btnCovBrowseClick(Sender: TObject);
var
  Dir: string;
begin
  Dir := edCovRoot.Text;
  if SelectDirectory('Select coverage root', '', Dir) then
    edCovRoot.Text := Dir;
end;

procedure TIndexesFrame.btnCovRefreshClick(Sender: TObject);
begin
  RefreshCoverage;
end;

procedure TIndexesFrame.tvCoverageCustomDrawItem(Sender: TCustomTreeView;
  Node: TTreeNode; State: TCustomDrawState; var DefaultDraw: Boolean);
var
  Idx: Integer;
begin
  DefaultDraw := True;
  Idx := NodeCovIdx(Node);
  if (Idx >= 0) and (FCoverageItems <> nil) and (Idx < FCoverageItems.Count) then
    Sender.Canvas.Font.Color := CovKindColor(FCoverageItems[Idx].Kind)
  else
    Sender.Canvas.Font.Color := clWindowText;
end;

procedure TIndexesFrame.tvCoverageExpanding(Sender: TObject; Node: TTreeNode;
  var AllowExpansion: Boolean);
var
  Idx:     Integer;
  Folder:  string;
  First:   TTreeNode;
begin
  AllowExpansion := True;

  { Root node: no coverage data, children were already populated at refresh }
  if NodeCovIdx(Node) < 0 then Exit;
  if (FCoverageItems = nil) then Exit;

  Idx := NodeCovIdx(Node);
  if (Idx < 0) or (Idx >= FCoverageItems.Count) then Exit;

  { Check whether this node still holds only the dummy sentinel }
  First := Node.GetFirstChild;
  if (First = nil) or (First.Text <> '') then
    Exit; { already populated or no children }

  { Delete the dummy sentinel and populate real children }
  Folder := FCoverageItems[Idx].Folder;
  tvCoverage.Items.Delete(First);
  PopulateCoverageChildren(Node, Folder);
end;

{ Coverage popup menu action handlers }

procedure TIndexesFrame.CovAssignToSectionClick(Sender: TObject);
var
  Node:    TTreeNode;
  MIdx:    Integer;
  SecIdx:  Integer;
  F:       string;
  J:       Integer;
  Already: Boolean;
  OldLen:  Integer;
begin
  Node := tvCoverage.Selected;
  if Node = nil then Exit;
  MIdx := NodeCovIdx(Node);
  if (FManifest = nil) or (MIdx < 0) or
     (FCoverageItems = nil) or (MIdx >= FCoverageItems.Count) then
    Exit;
  F := FCoverageItems[MIdx].Folder;
  SecIdx := TMenuItem(Sender).Tag;
  if (SecIdx < 0) or (SecIdx > High(FManifest^.Sections)) then Exit;

  { Avoid duplicate includes }
  Already := False;
  for J := 0 to High(FManifest^.Sections[SecIdx].Include) do
  begin
    if SameText(FManifest^.Sections[SecIdx].Include[J], F) then
    begin
      Already := True;
      Break;
    end;
  end;
  if not Already then
  begin
    OldLen := Length(FManifest^.Sections[SecIdx].Include);
    SetLength(FManifest^.Sections[SecIdx].Include, OldLen + 1);
    FManifest^.Sections[SecIdx].Include[OldLen] := F;
  end;

  RefreshSectionList;
  RefreshCoverage;
end;

procedure TIndexesFrame.CovNewDbFromFolderClick(Sender: TObject);
var
  SelNode:  TTreeNode;
  SIdx:     Integer;
  Leaf:     string;
  NewName:  string;
  NewSec:   TIndexSection;
  N:        Integer;
begin
  SelNode := tvCoverage.Selected;
  if SelNode = nil then Exit;
  SIdx := NodeCovIdx(SelNode);
  if (FManifest = nil) or (SIdx < 0) or
     (FCoverageItems = nil) or (SIdx >= FCoverageItems.Count) then
    Exit;
  Leaf := TPath.GetFileName(FCoverageItems[SIdx].Folder);
  { Sanitize: replace spaces with underscores }
  NewName := StringReplace(Leaf, ' ', '_', [rfReplaceAll]);
  if not InputQuery('New DB from folder', 'Section name:', NewName) then
    Exit;
  if Trim(NewName) = '' then Exit;

  NewSec               := Default(TIndexSection);
  NewSec.Name          := Trim(NewName);
  NewSec.UseIgnoreFiles := True;
  NewSec.SqlOnlyMS     := True;
  SetLength(NewSec.Include, 1);
  NewSec.Include[0]    := FCoverageItems[SIdx].Folder;

  N := Length(FManifest^.Sections);
  SetLength(FManifest^.Sections, N + 1);
  FManifest^.Sections[N] := NewSec;

  RefreshSectionList;
  RefreshCoverage;
end;

procedure TIndexesFrame.pmCoveragePopup(Sender: TObject);
var
  Node:       TTreeNode;
  Idx:        Integer;
  I:          Integer;
  AssignItem: TMenuItem;
  SubItem:    TMenuItem;
  NewItem:    TMenuItem;
  SecName:    string;
begin
  { Clear dynamic items from a previous popup }
  pmCoverage.Items.Clear;

  Node := tvCoverage.Selected;
  if Node = nil then Exit;
  Idx := NodeCovIdx(Node);
  if (FManifest = nil) or (Idx < 0) or
     (FCoverageItems = nil) or (Idx >= FCoverageItems.Count) then
    Exit;

  { "Assign to ->" submenu }
  AssignItem := TMenuItem.Create(pmCoverage);
  AssignItem.Caption := 'Assign to...';
  pmCoverage.Items.Add(AssignItem);

  for I := 0 to High(FManifest^.Sections) do
  begin
    SecName := FManifest^.Sections[I].Name;
    SubItem := TMenuItem.Create(AssignItem);
    SubItem.Caption := SecName;
    SubItem.Tag := I;
    SubItem.OnClick := CovAssignToSectionClick;
    AssignItem.Add(SubItem);
  end;

  if AssignItem.Count = 0 then
    AssignItem.Enabled := False;

  { "New DB from folder..." item }
  NewItem := TMenuItem.Create(pmCoverage);
  NewItem.Caption := 'New DB from folder...';
  NewItem.OnClick := CovNewDbFromFolderClick;
  pmCoverage.Items.Add(NewItem);
end;

end.
