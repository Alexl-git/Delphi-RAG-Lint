unit Config.ManifestSession;

/// <summary>Non-visual load and guarded save of the drag-lint.json the Config
/// tool edits. The ONLY place in src\config that reads or writes a manifest
/// file, so the refusal to write back a file that did not load, and the rule
/// that a Save writes only what the user edited, live in one routine every
/// writer goes through.</summary>

interface

uses
  DRagLint.Index.Manifest;

/// <summary>The one file the Config tool loads and saves.</summary>
/// <param name="AExplicitPath">The --config argument; '' when none was given.</param>
/// <param name="AExeDir">Directory of the Config tool exe.</param>
/// <returns>AExplicitPath made absolute when it is not ''; otherwise
/// &lt;AExeDir&gt;\drag-lint.json, whether or not it exists yet. Never ''.</returns>
/// <remarks>There is deliberately no discovery: the engine's TManifestIO.Load
/// MERGES a local .drag-lint.json found above the working directory into the
/// global one, and a Save of that merge put the local file's sections into the
/// global file (B-22). The tool edits one file, the one it names.</remarks>
function ConfigTargetPath(const AExplicitPath, AExeDir: string): string;

/// <summary>Load the manifest the Config tool will edit, and say whether it
/// loaded cleanly.</summary>
/// <param name="AConfigPath">The file to edit, from ConfigTargetPath. An
/// existing file is parsed on its own with TManifestIO.ParseText (RootDir = its
/// directory); one that fails to read or parse returns an error. A missing file
/// in an EXISTING folder gives the defaults and '' -- there is nothing to
/// overwrite, so a Save creates the file. A missing file whose folder does not
/// exist or cannot be reached (a disconnected share, an unmounted drive) gives
/// the defaults and an error, so Save stays refused and nothing is created.
/// '' gives the defaults and an error.</param>
/// <param name="AManifest">Receives the parsed manifest. When the file could not
/// be read or parsed, or its folder is missing, it receives the DEFAULTS (no
/// sections, default settings, RootDir = the file's directory), which must
/// never be saved over the file.</param>
/// <param name="AOriginalText">Receives the file's text exactly as read; ''
/// when there is no file yet or it could not be read. Pass it unchanged to
/// TrySaveConfigManifest: it is what the Save patches.</param>
/// <returns>'' when the manifest loaded cleanly or AConfigPath does not exist
/// yet in an existing folder; otherwise why it did not load, as
/// '&lt;file&gt;: &lt;message&gt;' -- the same shape as TIndexManifest.LoadError
/// (a missing folder gives '&lt;file&gt;: folder not found or not reachable --
/// not creating a new config there'). Pass it unchanged to
/// TrySaveConfigManifest.</returns>
/// <remarks>Never raises for a bad or unreadable file: every exception from the
/// read or the parse is turned into the returned text.</remarks>
function LoadConfigManifest(const AConfigPath: string;
  out AManifest: TIndexManifest; out AOriginalText: string): string;

/// <summary>Save the user's edits in AManifest into APath -- and only the
/// edits -- unless doing so could destroy the file: refuses when the manifest
/// did not load, when it does not validate, or when there is no path.</summary>
/// <param name="AManifest">The manifest as edited.</param>
/// <param name="ALoadError">The text LoadConfigManifest returned for this
/// manifest; '' when it loaded cleanly. Anything else refuses the save, because
/// the in-memory manifest is then the defaults or a partial parse, and writing
/// it would replace the user's file with less than it held.</param>
/// <param name="AOriginalText">The text LoadConfigManifest returned in
/// AOriginalText for this manifest.</param>
/// <param name="APath">Destination file: the file the manifest was loaded from.</param>
/// <param name="AReason">Receives the message to show the user, success or
/// not: 'Not saved: &lt;path&gt; did not load (&lt;error&gt;). Fix the file,
/// then Reload.' / 'Validation error: &lt;error&gt;' / 'No config path set. Use
/// Open... to choose a file first.' / 'Save failed: &lt;error&gt;' /
/// 'Saved to &lt;path&gt;'.</param>
/// <returns>True only when the file was written.</returns>
/// <remarks>
/// <para>What is written is AOriginalText with only the edits applied
/// (TManifestIO.SaveEdits): unmodelled keys and untouched modelled keys keep
/// their original text.</para>
/// <para>Checks in this order: load error, validation, empty path, then the
/// write itself. Never raises: a failing write becomes AReason. The write is
/// atomic (TManifestIO.SaveEdits), so a failed write leaves the old file
/// intact.</para></remarks>
function TrySaveConfigManifest(const AManifest: TIndexManifest;
  const ALoadError, AOriginalText, APath: string; out AReason: string): Boolean;

implementation

uses
  System.SysUtils,
  System.IOUtils;

// The manifest LoadConfigManifest hands back when AConfigPath gives it nothing
// to parse: no sections, default settings, RootDir = the file's directory.
// Exactly what the parser makes of an EMPTY file -- docs defaults included --
// so a Save of an unedited new file writes no key (a zeroed docs block would
// read as an edit: complexity_min 0, dialog_routines [] = off).
procedure SetDefaults(out AManifest: TIndexManifest; const AConfigPath: string);
begin
  AManifest := TManifestIO.ParseText('', ExtractFileDir(AConfigPath));
end;

function ConfigTargetPath(const AExplicitPath, AExeDir: string): string;
begin
  if AExplicitPath <> '' then
    Result := TPath.GetFullPath(AExplicitPath)
  else
    Result := TPath.Combine(AExeDir, 'drag-lint.json');
end;

function LoadConfigManifest(const AConfigPath: string;
  out AManifest: TIndexManifest; out AOriginalText: string): string;
begin
  Result := '';
  AOriginalText := '';
  if AConfigPath = '' then
  begin
    SetDefaults(AManifest, AConfigPath);
    Result := '(no config path)';
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
    AOriginalText := TFile.ReadAllText(AConfigPath);
    AManifest := TManifestIO.ParseText(AOriginalText,
      ExtractFileDir(AConfigPath));
  except
    on E: Exception do
    begin
      Result := AConfigPath + ': ' + E.Message;
      AOriginalText := '';
      SetDefaults(AManifest, AConfigPath);
    end;
  end;
end;

function TrySaveConfigManifest(const AManifest: TIndexManifest;
  const ALoadError, AOriginalText, APath: string; out AReason: string): Boolean;
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
    TManifestIO.SaveEdits(AOriginalText, AManifest, APath);
    AReason := 'Saved to ' + APath;
    Result := True;
  except
    on E: Exception do
      AReason := 'Save failed: ' + E.Message;
  end;
end;

end.
