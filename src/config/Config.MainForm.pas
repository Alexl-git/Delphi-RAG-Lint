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
    /// <summary>FConfigPath's text as loaded; what a Save patches with the
    /// edits, so keys the parser does not model survive.</summary>
    FOriginalText:   string;
    FIndexFrame:     TIndexesFrame;
    FSettingsFrame:  TSettingsFrame;
    FOpenDialog:     TOpenDialog;
    /// <summary>Resolve the config path: the --config arg, else
    /// &lt;ExeDir&gt;\drag-lint.json (see ConfigTargetPath).</summary>
    /// <returns>Absolute path of the one file this session loads and saves; never ''.</returns>
    function ResolveConfigPath: string;
    /// <summary>Load the manifest from FConfigPath (never by discovery, which would
    /// merge a local .drag-lint.json) and push the result into FManifest and FIndexFrame.
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
  Arg, Next, Explicit: string;
begin
  Explicit := '';

  { Check --config <path> command-line argument }
  for I := 1 to ParamCount - 1 do
  begin
    Arg := ParamStr(I);
    if (Arg = '--config') or (Arg = '-config') then
    begin
      Next := ParamStr(I + 1);
      if Next <> '' then
      begin
        Explicit := Next;
        Break;
      end;
    end;
  end;

  { No --config: <ExeDir>\drag-lint.json, existing or not -- never '' }
  Result := ConfigTargetPath(Explicit, TPath.GetDirectoryName(ParamStr(0)));
end;

procedure TMainForm.LoadManifest;
begin
  FLoadError := LoadConfigManifest(FConfigPath, FManifest, FOriginalText);
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
        if not TrySaveConfigManifest(FManifest, FLoadError, FOriginalText,
          FConfigPath, Reason) and (FLoadError <> '') then
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
  TrySaveConfigManifest(FManifest, FLoadError, FOriginalText, FConfigPath, Reason);
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
