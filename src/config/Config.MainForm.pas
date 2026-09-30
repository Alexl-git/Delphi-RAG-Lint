unit Config.MainForm;

/// <summary>Main application form for drag-lint-config. Hosts a TPageControl
/// with Indexes and Settings tabs; owns the working TIndexManifest and
/// drives load / validate / save through Config.ManifestSession, which
/// refuses to write back a file that did not load.</summary>

interface

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  Winapi.Windows,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.ComCtrls,
  Vcl.ExtCtrls,
  Vcl.StdCtrls,
  Vcl.Dialogs,
  DRagLint.Index.Manifest,
  Config.ManifestSession,
  Config.IndexesFrame,
  Config.SettingsFrame;

type
  /// <summary>Top-level form: tabbed shell over the index section editor and
  /// the settings editor. Owns the working TIndexManifest instance and the
  /// resolved config file path.</summary>
  TMainForm = class(TForm)
    pcMain: TPageControl;
    tsIndexes: TTabSheet;
    tsSettings: TTabSheet;
    pnlBottom: TPanel;
    btnSave: TButton;
    btnReload: TButton;
    btnOpen: TButton;
    lblConfigPath: TLabel;
    procedure FormShow(Sender: TObject);
    procedure btnSaveClick(Sender: TObject);
    procedure btnReloadClick(Sender: TObject);
    procedure btnOpenClick(Sender: TObject);
  private
    FManifest:       TIndexManifest;
    FConfigPath:     string;
    /// <summary>Why the loaded file could not be used; '' when it loaded
    /// cleanly -- while set, nothing is written.</summary>
    FLoadError:      string;
    FIndexFrame:     TIndexesFrame;
    FSettingsFrame:  TSettingsFrame;
    FOpenDialog:     TOpenDialog;
    /// <summary>Resolve the config path: --config arg, then &lt;ExeDir&gt;\drag-lint.json,
    /// else empty (load via TManifestIO discovery).</summary>
    /// <returns>Resolved absolute path, or empty string if not found by arg/default.</returns>
    function ResolveConfigPath: string;
    /// <summary>Load the manifest from FConfigPath (or by TManifestIO discovery when
    /// FConfigPath is empty) and push the result into FManifest and FIndexFrame.
    /// Records the load error in FLoadError and tells the user when it is set.</summary>
    procedure LoadManifest;
    /// <summary>Push the current FManifest into the frame so its controls reflect
    /// the newly loaded data. Disables Save and marks the path caption while
    /// FLoadError is set.</summary>
    procedure PopulateFrame;
  public
    /// <summary>The working manifest. Updated by the frame on each edit.</summary>
    property Manifest: TIndexManifest read FManifest write FManifest;
    /// <summary>Absolute path of the config file being edited.</summary>
    property ConfigPath: string read FConfigPath;
  end;

var
  MainForm: TMainForm;

implementation

{$R *.dfm}

{ TMainForm }

function TMainForm.ResolveConfigPath: string;
var
  I: Integer;
  Arg, Next: string;
  ExeDir, Candidate: string;
begin
  Result := '';

  { Check --config <path> command-line argument }
  for I := 1 to ParamCount - 1 do
  begin
    Arg := ParamStr(I);
    if (Arg = '--config') or (Arg = '-config') then
    begin
      Next := ParamStr(I + 1);
      if Next <> '' then
      begin
        Result := TPath.GetFullPath(Next);
        Exit;
      end;
    end;
  end;

  { Fall back to <ExeDir>\drag-lint.json }
  ExeDir := TPath.GetDirectoryName(ParamStr(0));
  Candidate := TPath.Combine(ExeDir, 'drag-lint.json');
  if TFile.Exists(Candidate) then
  begin
    Result := Candidate;
    Exit;
  end;
end;

procedure TMainForm.LoadManifest;
var
  ExeDir: string;
begin
  ExeDir := TPath.GetDirectoryName(ParamStr(0));
  FLoadError := LoadConfigManifest(FConfigPath, ExeDir, GetCurrentDir, FManifest);
  { If still no config path, derive one beside the EXE for Save operations }
  if FConfigPath = '' then
    FConfigPath := TPath.Combine(ExeDir, 'drag-lint.json');
  if FLoadError <> '' then
    ShowMessage('Error loading config: ' + FLoadError + sLineBreak +
      'Saving is disabled until the file loads cleanly (fix it, then Reload).');
  PopulateFrame;
end;

procedure TMainForm.PopulateFrame;
begin
  if FIndexFrame <> nil then
  begin
    FIndexFrame.BindManifest(PIndexManifest(@FManifest));
    FIndexFrame.ConfigPath := FConfigPath;
  end;
  if FSettingsFrame <> nil then
    FSettingsFrame.BindManifest(PIndexManifest(@FManifest));
  btnSave.Enabled := FLoadError = '';
  if FLoadError <> '' then
    lblConfigPath.Caption := FConfigPath + '  [NOT LOADED -- saving disabled]'
  else if FConfigPath <> '' then
    lblConfigPath.Caption := FConfigPath
  else
    lblConfigPath.Caption := '(no config file)';
end;

procedure TMainForm.FormShow(Sender: TObject);
begin
  { Create the indexes frame on first show }
  if FIndexFrame = nil then
  begin
    FIndexFrame := TIndexesFrame.Create(Self);
    FIndexFrame.Parent := tsIndexes;
    FIndexFrame.Align  := alClient;
    FIndexFrame.OnSaveNeeded :=
      procedure
      var
        Reason: string;
      begin
        if FIndexFrame <> nil then
          FIndexFrame.FlushToManifest;
        if FSettingsFrame <> nil then
          FSettingsFrame.FlushToManifest;
        { A validation or write failure stays silent (the engine reports it
          against whatever is on disk); a file that did not load is SAID,
          because the Build then runs against the file as it is, unsaved. }
        if not TrySaveConfigManifest(FManifest, FLoadError, FConfigPath, Reason)
          and (FLoadError <> '') then
          ShowMessage(Reason);
      end;
  end;

  { Create the settings frame on first show }
  if FSettingsFrame = nil then
  begin
    FSettingsFrame := TSettingsFrame.Create(Self);
    FSettingsFrame.Parent := tsSettings;
    FSettingsFrame.Align  := alClient;
  end;

  FConfigPath := ResolveConfigPath;
  LoadManifest;
end;

procedure TMainForm.btnSaveClick(Sender: TObject);
var
  Reason: string;
begin
  { Pull edits back from frames into FManifest }
  if FIndexFrame <> nil then
    FIndexFrame.FlushToManifest;
  if FSettingsFrame <> nil then
    FSettingsFrame.FlushToManifest;
  { Saved or refused, Reason says which; the Boolean is for the autosave. }
  TrySaveConfigManifest(FManifest, FLoadError, FConfigPath, Reason);
  ShowMessage(Reason);
end;

procedure TMainForm.btnReloadClick(Sender: TObject);
begin
  LoadManifest;
end;

procedure TMainForm.btnOpenClick(Sender: TObject);
begin
  if FOpenDialog = nil then
  begin
    FOpenDialog := TOpenDialog.Create(Self);
    FOpenDialog.Title  := 'Open drag-lint config';
    FOpenDialog.Filter := 'drag-lint config|*.drag-lint.json;drag-lint.json|JSON files|*.json|All files|*.*';
    FOpenDialog.Options := FOpenDialog.Options + [ofFileMustExist];
  end;

  if FOpenDialog.Execute then
  begin
    FConfigPath := FOpenDialog.FileName;
    LoadManifest;
  end;
end;

end.
