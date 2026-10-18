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
/// <para>What is written is AOriginalText patched, not a fresh serialisation:
/// a modelled key whose value the user did not change keeps its original text
/// (or stays absent); a changed key is written; a key the edit removed (an
/// optional section key) is removed; a section is matched by name, a deleted
/// one is dropped and a new one appended. Every key the manifest parser does
/// not model -- a "_comment", a "scan" block, a future setting -- is kept
/// as it was. A renamed section is a delete plus an add, so its unmodelled
/// keys go with the old name.</para>
/// <para>Checks in this order: load error, validation, empty path, then the
/// write itself. Never raises: a failing write becomes AReason. The write is
/// atomic (WriteJsonFileAtomic), so a failed write leaves the old file
/// intact.</para></remarks>
function TrySaveConfigManifest(const AManifest: TIndexManifest;
  const ALoadError, AOriginalText, APath: string; out AReason: string): Boolean;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.JSON,
  DRagLint.Core.JsonFile;

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

function SameJson(const A, B: TJSONValue): Boolean;
begin
  Result := (A <> nil) and (B <> nil) and (A.ToJSON = B.ToJSON);
end;

// Replace (or add) ADest's AKey with AValue, which ADest then owns.
procedure SetKey(const ADest: TJSONObject; const AKey: string;
  const AValue: TJSONValue);
var
  Pair: TJSONPair;
begin
  Pair := ADest.Get(AKey);
  if Pair <> nil then
    Pair.JsonValue := AValue
  else
    ADest.AddPair(AKey, AValue);
end;

function FindSectionByName(const AArr: TJSONArray; const AName: string): TJSONObject;
var
  V: TJSONValue;
  N: TJSONValue;
begin
  Result := nil;
  if AArr = nil then
    Exit;
  for V in AArr do
    if V is TJSONObject then
    begin
      N := TJSONObject(V).GetValue('name');
      if (N is TJSONString) and SameText(N.Value, AName) then
        Exit(TJSONObject(V));
    end;
end;

procedure PatchObject(const ADest, AOld, ANew: TJSONObject); forward;

// The sections array, in the EDITED order: an unchanged section keeps its
// original object verbatim; a changed one is the original patched; a new one
// is the edited object; one the parser never modelled (not in AOld) is kept.
function PatchSections(const ADest, AOld, ANew: TJSONArray): TJSONArray;
var
  V: TJSONValue;
  NewSec, OldSec, DestSec: TJSONObject;
  Name: string;
begin
  Result := TJSONArray.Create;
  try
    for V in ANew do
    begin
      NewSec := V as TJSONObject;
      Name := NewSec.GetValue('name').Value;
      OldSec := FindSectionByName(AOld, Name);
      DestSec := FindSectionByName(ADest, Name);
      if (DestSec <> nil) and (OldSec <> nil) then
      begin
        DestSec := TJSONObject(DestSec.Clone);
        Result.AddElement(DestSec);
        PatchObject(DestSec, OldSec, NewSec);
      end
      else
        Result.AddElement(TJSONValue(NewSec.Clone));
    end;
    if ADest <> nil then
      for V in ADest do
        if (V is TJSONObject) and (TJSONObject(V).GetValue('name') is TJSONString) and
          (FindSectionByName(AOld, TJSONObject(V).GetValue('name').Value) = nil) then
          Result.AddElement(TJSONValue(V.Clone));
  except  // dl:ok bare-except@041e -- frees the half-built result object and re-raises; nothing is swallowed
    Result.Free;
    raise;
  end;
end;

// Apply the difference AOld -> ANew (both TManifestIO.ToJson output) to ADest
// (the file as the user wrote it). Keys only ADest has are never touched.
procedure PatchObject(const ADest, AOld, ANew: TJSONObject);
var
  Pair: TJSONPair;
  Key: string;
  NV, OV, DV: TJSONValue;
begin
  for Pair in ANew do
  begin
    Key := Pair.JsonString.Value;
    NV := Pair.JsonValue;
    OV := AOld.GetValue(Key);
    if SameJson(OV, NV) then
      Continue;
    DV := ADest.GetValue(Key);
    if (Key = 'sections') and (NV is TJSONArray) then
      SetKey(ADest, Key, PatchSections(DV as TJSONArray, OV as TJSONArray, TJSONArray(NV)))
    else if (NV is TJSONObject) and (OV is TJSONObject) and ((DV = nil) or (DV is TJSONObject)) then
    begin
      if DV = nil then
      begin
        DV := TJSONObject.Create;
        ADest.AddPair(Key, DV);
      end;
      PatchObject(TJSONObject(DV), TJSONObject(OV), TJSONObject(NV));
    end
    else
      SetKey(ADest, Key, TJSONValue(NV.Clone));
  end;
  for Pair in AOld do
    if ANew.GetValue(Pair.JsonString.Value) = nil then
      ADest.RemovePair(Pair.JsonString.Value).Free;
end;

// AOriginalText with the edits AEdited made to it, as a new object the caller owns.
function MergeEdits(const AOriginalText, ARootDir: string;
  const AEdited: TIndexManifest): TJSONObject;
var
  Parsed: TJSONValue;
  OldJ, NewJ: TJSONObject;
begin
  if Trim(AOriginalText) = '' then
    Result := TJSONObject.Create
  else
  begin
    Parsed := TJSONObject.ParseJSONValue(AOriginalText, False, True);
    if not (Parsed is TJSONObject) then
    begin
      Parsed.Free;
      raise EManifestError.Create('(root): not a JSON object');
    end;
    Result := TJSONObject(Parsed);
  end;
  try
    OldJ := nil;
    NewJ := nil;
    try
      OldJ := TManifestIO.ToJson(TManifestIO.ParseText(AOriginalText, ARootDir));
      NewJ := TManifestIO.ToJson(AEdited);
      PatchObject(Result, OldJ, NewJ);
    finally
      NewJ.Free;
      OldJ.Free;
    end;
  except  // dl:ok bare-except@041e -- frees the half-built result object and re-raises; nothing is swallowed
    Result.Free;
    raise;
  end;
end;

function TrySaveConfigManifest(const AManifest: TIndexManifest;
  const ALoadError, AOriginalText, APath: string; out AReason: string): Boolean;
var
  Err: string;
  Root: TJSONObject;
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
    Root := MergeEdits(AOriginalText, ExtractFileDir(APath), AManifest);
    try
      WriteJsonFileAtomic(APath, Root);
    finally
      Root.Free;
    end;
    AReason := 'Saved to ' + APath;
    Result := True;
  except
    on E: Exception do
      AReason := 'Save failed: ' + E.Message;
  end;
end;

end.
