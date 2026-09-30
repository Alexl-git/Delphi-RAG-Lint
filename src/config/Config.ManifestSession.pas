unit Config.ManifestSession;

/// <summary>Non-visual load and guarded save of the drag-lint.json the Config
/// tool edits. The ONLY place in src\config that reads or writes a manifest
/// file, so the refusal to write back a file that did not load lives in one
/// routine every writer goes through.</summary>

interface

uses
  DRagLint.Index.Manifest;

/// <summary>Load the manifest the Config tool will edit, and say whether it
/// loaded cleanly.</summary>
/// <param name="AConfigPath">The file to edit. When not '', three cases: an
/// existing file is parsed on its own with TManifestIO.ParseText (RootDir = its
/// directory), and one that fails to read or parse returns an error; a missing
/// file in an EXISTING folder gives the defaults and '' -- there is nothing to
/// overwrite, so a Save creates the file; a missing file whose folder does not
/// exist or cannot be reached (a disconnected share, an unmounted drive) gives
/// the defaults and an error, so Save stays refused and nothing is created.
/// When '', the manifest is found by TManifestIO.Load discovery instead.</param>
/// <param name="AExeDir">Engine directory for TManifestIO.Load discovery; used
/// only when AConfigPath is ''.</param>
/// <param name="AStartDir">Start directory for the upward local-config search of
/// TManifestIO.Load; used only when AConfigPath is ''.</param>
/// <param name="AManifest">Receives the parsed manifest. When AConfigPath exists
/// but could not be read or parsed, or its folder is missing, it receives the
/// DEFAULTS (no sections, default settings, RootDir = the file's directory),
/// which must never be saved over the file.</param>
/// <returns>'' when the manifest loaded cleanly or AConfigPath does not exist
/// yet in an existing folder; otherwise why it did not load, as
/// '&lt;file&gt;: &lt;message&gt;' -- the same shape as TIndexManifest.LoadError
/// (a missing folder gives '&lt;file&gt;: folder not found or not reachable --
/// not creating a new config there'). Pass it unchanged to
/// TrySaveConfigManifest.</returns>
/// <remarks>Never raises for a bad or unreadable file: every exception from the
/// read or the parse is turned into the returned text.</remarks>
function LoadConfigManifest(const AConfigPath, AExeDir, AStartDir: string;
  out AManifest: TIndexManifest): string;

/// <summary>Save AManifest to APath unless doing so could destroy the file:
/// refuses when the manifest did not load, when it does not validate, or when
/// there is no path.</summary>
/// <param name="AManifest">The manifest to write.</param>
/// <param name="ALoadError">The text LoadConfigManifest returned for this
/// manifest; '' when it loaded cleanly. Anything else refuses the save, because
/// the in-memory manifest is then the defaults or a partial merge, and writing
/// it would replace the user's file with less than it held.</param>
/// <param name="APath">Destination file.</param>
/// <param name="AReason">Receives the message to show the user, success or
/// not: 'Not saved: &lt;path&gt; did not load (&lt;error&gt;). Fix the file,
/// then Reload.' / 'Validation error: &lt;error&gt;' / 'No config path set. Use
/// Open... to choose a file first.' / 'Save failed: &lt;error&gt;' /
/// 'Saved to &lt;path&gt;'.</param>
/// <returns>True only when the file was written.</returns>
/// <remarks>Checks in this order: load error, validation, empty path, then the
/// write itself. Never raises: a failing TManifestIO.Save becomes AReason.
/// TManifestIO.Save is atomic, so a failed write leaves the old file intact.</remarks>
function TrySaveConfigManifest(const AManifest: TIndexManifest;
  const ALoadError, APath: string; out AReason: string): Boolean;

implementation

uses
  System.SysUtils,
  System.IOUtils;

// The manifest LoadConfigManifest hands back when AConfigPath gives it nothing
// to parse: no sections, default settings, RootDir = the file's directory.
procedure SetDefaults(out AManifest: TIndexManifest; const AConfigPath: string);
begin
  AManifest := Default(TIndexManifest);
  AManifest.Settings := TIndexSettings.Defaults;
  AManifest.RootDir := ExtractFileDir(AConfigPath);
end;

function LoadConfigManifest(const AConfigPath, AExeDir, AStartDir: string;
  out AManifest: TIndexManifest): string;
begin
  Result := '';
  if AConfigPath = '' then
  begin
    AManifest := TManifestIO.Load(AExeDir, AStartDir);
    Result := AManifest.LoadError;
    Exit;
  end;
  // A file that does not exist yet has nothing on disk to overwrite: start
  // from the defaults, so a Save creates it -- but only in a folder that
  // exists. A disconnected share, an unmounted drive or a transient access
  // error also reads as "no file", and a Save after it comes back would put
  // the defaults over the real manifest.
  if not TFile.Exists(AConfigPath) then
  begin
    SetDefaults(AManifest, AConfigPath);
    if not TDirectory.Exists(ExtractFileDir(AConfigPath)) then
      Result := AConfigPath +
        ': folder not found or not reachable -- not creating a new config there';
    Exit;
  end;
  try
    AManifest := TManifestIO.ParseText(TFile.ReadAllText(AConfigPath),
      ExtractFileDir(AConfigPath));
  except
    on E: Exception do
    begin
      Result := AConfigPath + ': ' + E.Message;
      SetDefaults(AManifest, AConfigPath);
    end;
  end;
end;

function TrySaveConfigManifest(const AManifest: TIndexManifest;
  const ALoadError, APath: string; out AReason: string): Boolean;
var
  Err: string;
begin
  Result := False;
  if ALoadError <> '' then
  begin
    AReason := 'Not saved: ' + APath + ' did not load (' + ALoadError +
      '). Fix the file, then Reload.';
    Exit;
  end;
  Err := TManifestIO.Validate(AManifest);
  if Err <> '' then
  begin
    AReason := 'Validation error: ' + Err;
    Exit;
  end;
  if APath = '' then
  begin
    AReason := 'No config path set. Use Open... to choose a file first.';
    Exit;
  end;
  try
    TManifestIO.Save(AManifest, APath);
    AReason := 'Saved to ' + APath;
    Result := True;
  except
    on E: Exception do
      AReason := 'Save failed: ' + E.Message;
  end;
end;

end.
