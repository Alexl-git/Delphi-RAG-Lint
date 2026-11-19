unit Config.SettingsFrame;

/// <summary>Frame hosting the top-level Settings editor for drag-lint manifests.
/// Binds to the TIndexSettings block inside a TIndexManifest pointer shared
/// with TMainForm. Controls: ProjectsIndexing combo, DefaultPlatform combo
/// (populated from TProjectResolver.EnumRegistryPlatforms, free-type allowed),
/// integer edits for SizeGuardMB / MaxJobs / MaxParseFileKB, and an EnginePath
/// edit with a browse button.</summary>

interface

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  Winapi.Windows,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.Dialogs,
  DRagLint.Index.Manifest,
  DRagLint.Project.Resolver,
  Config.IndexesFrame;

type
  /// <summary>Settings editor frame. Bound to the Settings block of a shared
  /// TIndexManifest pointer owned by TMainForm.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: Config.MainForm.TMainForm.FormShow (Config.MainForm.pas), declaration (Config.MainForm.pas) ?</para>
  /// <para>Used in units: Config.MainForm</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TSettingsFrame = class(TFrame)
    lblProjectsIndexing: TLabel;
    cbProjectsIndexing: TComboBox;
    lblDefaultPlatform: TLabel;
    cbDefaultPlatform: TComboBox;
    lblSizeGuardMB: TLabel;
    edSizeGuardMB: TEdit;
    lblMaxJobs: TLabel;
    edMaxJobs: TEdit;
    lblMaxParseFileKB: TLabel;
    edMaxParseFileKB: TEdit;
    lblEnginePath: TLabel;
    edEnginePath: TEdit;
    btnBrowseEngine: TButton;
    /// <summary><!-- drag-lint:auto sum -->event handlers</summary>
    /// <param name="Sender"><!-- drag-lint:auto type -->TObject</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Reads: FOpenDialog, edEnginePath   Writes: FOpenDialog</para>
    /// <para>Handles: btnBrowseEngine.OnClick</para>
    /// <seealso cref="Config.SettingsFrame.TSettingsFrame.BindManifest"/>
    /// <seealso cref="Config.SettingsFrame.TSettingsFrame.cbProjectsIndexingChange"/>
    /// <seealso cref="Config.SettingsFrame.TSettingsFrame.FlushToManifest"/>
    /// <seealso cref="Config.SettingsFrame.TSettingsFrame.ProjectsIndexingStr"/>
    /// <seealso cref="Config.SettingsFrame.TSettingsFrame.StrToProjectsIndexing"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure btnBrowseEngineClick(Sender: TObject);
    /// <param name="Sender"><!-- drag-lint:auto type -->TObject</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Calls: Config.SettingsFrame.TSettingsFrame.FlushToManifest</para>
    /// <para>Reads: FLoading</para>
    /// <para>Handles: cbProjectsIndexing.OnChange</para>
    /// <seealso cref="Config.SettingsFrame.TSettingsFrame.FlushToManifest"/>
    /// <seealso cref="Config.SettingsFrame.TSettingsFrame.BindManifest"/>
    /// <seealso cref="Config.SettingsFrame.TSettingsFrame.btnBrowseEngineClick"/>
    /// <seealso cref="Config.SettingsFrame.TSettingsFrame.ProjectsIndexingStr"/>
    /// <seealso cref="Config.SettingsFrame.TSettingsFrame.StrToProjectsIndexing"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure cbProjectsIndexingChange(Sender: TObject);
  private
    FManifest:   PIndexManifest;
    FOpenDialog: TOpenDialog;
    FLoading:    Boolean;
    /// <summary>Convert a TProjectsIndexing ordinal to its display string.</summary>
    /// <param name="AVal">The enum value to convert.</param>
    /// <returns>Human-readable string: 'perProject', 'perGroup', or 'single'.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: Config.SettingsFrame.TSettingsFrame.BindManifest (Config.SettingsFrame.pas)</para>
    /// <para>Returns: 'perProject'; 'perGroup'; 'single'</para>
    /// <para>Effect-free (proven)</para>
    /// <seealso cref="Config.SettingsFrame.TSettingsFrame.BindManifest"/>
    /// <seealso cref="Config.SettingsFrame.TSettingsFrame.btnBrowseEngineClick"/>
    /// <seealso cref="Config.SettingsFrame.TSettingsFrame.cbProjectsIndexingChange"/>
    /// <seealso cref="Config.SettingsFrame.TSettingsFrame.FlushToManifest"/>
    /// <seealso cref="Config.SettingsFrame.TSettingsFrame.StrToProjectsIndexing"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function ProjectsIndexingStr(const AVal: TProjectsIndexing): string;
    /// <summary>Parse a display string back to TProjectsIndexing.
    /// Unrecognised values return piPerProject.</summary>
    /// <param name="S">String as returned by ProjectsIndexingStr.</param>
    /// <returns>Corresponding TProjectsIndexing value.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: Config.SettingsFrame.TSettingsFrame.FlushToManifest (Config.SettingsFrame.pas)</para>
    /// <para>Returns: piPerGroup; piSingle; piPerProject</para>
    /// <para>Effect-free (proven)</para>
    /// <seealso cref="Config.SettingsFrame.TSettingsFrame.BindManifest"/>
    /// <seealso cref="Config.SettingsFrame.TSettingsFrame.btnBrowseEngineClick"/>
    /// <seealso cref="Config.SettingsFrame.TSettingsFrame.cbProjectsIndexingChange"/>
    /// <seealso cref="Config.SettingsFrame.TSettingsFrame.FlushToManifest"/>
    /// <seealso cref="Config.SettingsFrame.TSettingsFrame.ProjectsIndexingStr"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function StrToProjectsIndexing(const S: string): TProjectsIndexing;
  public
    /// <summary>Bind the frame to a manifest pointer and repopulate all controls
    /// from its Settings block. Also enumerates registry platforms to fill
    /// cbDefaultPlatform. The pointer must remain valid for the frame's lifetime.</summary>
    /// <param name="AManifest">Pointer to the main form's working TIndexManifest.
    /// Caller owns the pointed-to record.</param>
    /// <remarks>
    /// Not thread-safe; call from the main (UI) thread only.
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: Config.MainForm.TMainForm.PopulateFrame (Config.MainForm.pas)</para>
    /// <para>Calls: Config.SettingsFrame.TSettingsFrame.ProjectsIndexingStr, DRagLint.Project.Resolver.TProjectResolver.Create, DRagLint.Project.Resolver.TProjectResolver.EnumRegistryPlatforms, IntToStr</para>
    /// <para>Reads: cbProjectsIndexing, cbDefaultPlatform, edSizeGuardMB, edMaxJobs, edMaxParseFileKB, edEnginePath   Writes: FManifest, FLoading</para>
    /// <seealso cref="Config.SettingsFrame.TSettingsFrame.ProjectsIndexingStr"/>
    /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.Create"/>
    /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.EnumRegistryPlatforms"/>
    /// <seealso cref="Config.SettingsFrame.TSettingsFrame.btnBrowseEngineClick"/>
    /// <seealso cref="Config.SettingsFrame.TSettingsFrame.cbProjectsIndexingChange"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure BindManifest(AManifest: PIndexManifest);
    /// <summary>Write current control values back into the FManifest^.Settings
    /// block. Called by TMainForm before Save.</summary>
    /// <remarks>
    /// Not thread-safe; call from the main (UI) thread only.
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: Config.MainForm.TMainForm.btnSaveClick (Config.MainForm.pas), Config.MainForm.TMainForm.FormShow (Config.MainForm.pas), Config.SettingsFrame.TSettingsFrame.cbProjectsIndexingChange (Config.SettingsFrame.pas)</para>
    /// <para>Calls: Config.SettingsFrame.TSettingsFrame.StrToProjectsIndexing, StrToIntDef, Trim</para>
    /// <para>Reads: FManifest, cbProjectsIndexing, cbDefaultPlatform, edSizeGuardMB, edMaxJobs, edMaxParseFileKB, edEnginePath</para>
    /// <seealso cref="Config.SettingsFrame.TSettingsFrame.StrToProjectsIndexing"/>
    /// <seealso cref="Config.SettingsFrame.TSettingsFrame.BindManifest"/>
    /// <seealso cref="Config.SettingsFrame.TSettingsFrame.btnBrowseEngineClick"/>
    /// <seealso cref="Config.SettingsFrame.TSettingsFrame.cbProjectsIndexingChange"/>
    /// <seealso cref="Config.SettingsFrame.TSettingsFrame.ProjectsIndexingStr"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure FlushToManifest;
  end;

implementation

{$R *.dfm}

{ helpers }

function TSettingsFrame.ProjectsIndexingStr(const AVal: TProjectsIndexing): string;
begin
  case AVal of
    piPerProject: Result := 'perProject';
    piPerGroup:   Result := 'perGroup';
    piSingle:     Result := 'single';
  else
    Result := 'perProject';
  end;
end;

function TSettingsFrame.StrToProjectsIndexing(const S: string): TProjectsIndexing;
begin
  if S = 'perGroup' then
    Result := piPerGroup
  else if S = 'single' then
    Result := piSingle
  else
    Result := piPerProject;
end;

{ public }

procedure TSettingsFrame.BindManifest(AManifest: PIndexManifest);
var
  Resolver: TProjectResolver;
  Platforms: TArray<string>;
  P: string;
  DefPlatform: string;
begin
  FManifest := AManifest;
  FLoading  := True;
  try
    { Populate ProjectsIndexing combo if empty }
    if cbProjectsIndexing.Items.Count = 0 then
    begin
      cbProjectsIndexing.Items.Add('perProject');
      cbProjectsIndexing.Items.Add('perGroup');
      cbProjectsIndexing.Items.Add('single');
    end;

    if AManifest <> nil then
    begin
      { Settings values }
      cbProjectsIndexing.Text := ProjectsIndexingStr(AManifest^.Settings.CurrentProjectsIndexing);

      { Populate platform combo from registry then add current if not present }
      cbDefaultPlatform.Items.Clear;
      Resolver := TProjectResolver.Create;
      try
        Platforms := Resolver.EnumRegistryPlatforms;
      finally
        Resolver.Free;
      end;
      for P in Platforms do
        cbDefaultPlatform.Items.Add(P);

      DefPlatform := AManifest^.Settings.DefaultPlatform;
      if DefPlatform = '' then
        DefPlatform := 'Win32';
      if cbDefaultPlatform.Items.IndexOf(DefPlatform) < 0 then
        cbDefaultPlatform.Items.Add(DefPlatform);
      cbDefaultPlatform.Text := DefPlatform;

      edSizeGuardMB.Text    := IntToStr(AManifest^.Settings.SizeGuardMB);
      edMaxJobs.Text        := IntToStr(AManifest^.Settings.MaxJobs);
      edMaxParseFileKB.Text := IntToStr(AManifest^.Settings.MaxParseFileKB);

      if AManifest^.Settings.EnginePath <> '' then
        edEnginePath.Text := AManifest^.Settings.EnginePath
      else
        edEnginePath.Text := 'auto';
    end
    else
    begin
      cbProjectsIndexing.Text := 'perProject';
      cbDefaultPlatform.Text  := 'Win32';
      edSizeGuardMB.Text      := '1500';
      edMaxJobs.Text          := '0';
      edMaxParseFileKB.Text   := '2048';
      edEnginePath.Text       := 'auto';
    end;
  finally
    FLoading := False;
  end;
end;

procedure TSettingsFrame.FlushToManifest;
begin
  if FManifest = nil then Exit;
  FManifest^.Settings.CurrentProjectsIndexing :=
    StrToProjectsIndexing(cbProjectsIndexing.Text);
  FManifest^.Settings.DefaultPlatform := Trim(cbDefaultPlatform.Text);
  FManifest^.Settings.SizeGuardMB    := StrToIntDef(Trim(edSizeGuardMB.Text), 1500);
  FManifest^.Settings.MaxJobs        := StrToIntDef(Trim(edMaxJobs.Text), 0);
  FManifest^.Settings.MaxParseFileKB := StrToIntDef(Trim(edMaxParseFileKB.Text), 2048);
  FManifest^.Settings.EnginePath     := Trim(edEnginePath.Text);
end;

{ event handlers }

procedure TSettingsFrame.btnBrowseEngineClick(Sender: TObject);
begin
  if FOpenDialog = nil then
  begin
    FOpenDialog := TOpenDialog.Create(Self);
    FOpenDialog.Title  := 'Locate drag-lint engine EXE';
    FOpenDialog.Filter := 'Executable|*.exe|All files|*.*';
    FOpenDialog.Options := FOpenDialog.Options + [ofFileMustExist];
  end;
  if FOpenDialog.Execute then
    edEnginePath.Text := FOpenDialog.FileName;
end;

procedure TSettingsFrame.cbProjectsIndexingChange(Sender: TObject);
begin
  if not FLoading then
    FlushToManifest;
end;

end.
