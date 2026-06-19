unit Config.MainForm;

/// <summary>Main application form for drag-lint-config. Hosts a TPageControl
/// with Indexes and Settings tabs; owns the working TIndexManifest and
/// drives load / validate / save via TManifestIO.</summary>

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
    FIndexFrame:     TIndexesFrame;
    FSettingsFrame:  TSettingsFrame;
    FOpenDialog:     TOpenDialog;
    /// <summary>Resolve the config path: --config arg, then &lt;ExeDir&gt;\drag-lint.json,
    /// else empty (load via TManifestIO discovery).</summary>
    /// <returns>Resolved absolute path, or empty string if not found by arg/default.</returns>
    function ResolveConfigPath: string;
    /// <summary>Load the manifest from FConfigPath (or by TManifestIO discovery when
    /// FConfigPath is empty) and push the result into FManifest and FIndexFrame.</summary>
    procedure LoadManifest;
    /// <summary>Push the current FManifest into the frame so its controls reflect
    /// the newly loaded data.</summary>
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
  if FConfigPath <> '' then
  begin
    try
      FManifest := TManifestIO.ParseText(
        TFile.ReadAllText(FConfigPath),
        TPath.GetDirectoryName(FConfigPath));
    except
      on E: Exception do
      begin
        ShowMessage('Error loading config: ' + E.Message);
        FManifest := Default(TIndexManifest);
        FManifest.Settings := TIndexSettings.Defaults;
        FManifest.RootDir  := TPath.GetDirectoryName(FConfigPath);
      end;
    end;
  end
  else
  begin
    FManifest := TManifestIO.Load(ExeDir, GetCurrentDir);
    { If still no config path, derive one beside the EXE for Save operations }
    if FConfigPath = '' then
      FConfigPath := TPath.Combine(ExeDir, 'drag-lint.json');
  end;
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
  if FConfigPath <> '' then
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
        ErrMsg: string;
      begin
        if FIndexFrame <> nil then FIndexFrame.FlushToManifest;
        if FSettingsFrame <> nil then FSettingsFrame.FlushToManifest;
        ErrMsg := TManifestIO.Validate(FManifest);
        if (ErrMsg = '') and (FConfigPath <> '') then
        try
          TManifestIO.Save(FManifest, FConfigPath);
        except
          { swallow; build will use whatever is on disk }
        end;
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
  ErrMsg: string;
begin
  { Pull edits back from frames into FManifest }
  if FIndexFrame <> nil then
    FIndexFrame.FlushToManifest;
  if FSettingsFrame <> nil then
    FSettingsFrame.FlushToManifest;

  ErrMsg := TManifestIO.Validate(FManifest);
  if ErrMsg <> '' then
  begin
    ShowMessage('Validation error: ' + ErrMsg);
    Exit;
  end;

  if FConfigPath = '' then
  begin
    ShowMessage('No config path set. Use Open... to choose a file first.');
    Exit;
  end;

  try
    TManifestIO.Save(FManifest, FConfigPath);
    ShowMessage('Saved to ' + FConfigPath);
  except
    on E: Exception do
      ShowMessage('Save failed: ' + E.Message);
  end;
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
