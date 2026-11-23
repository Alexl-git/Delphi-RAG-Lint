unit DRagLint.FieldRepo.Locate;

{ drag-lint 1.53 -- lane FR-SCHEMA: how a project finds its field repository
  (design 2026-11-22-field-repository-v2-design.md section 1.2). One resolver for lint, resolve-dbs
  and the repo verbs. API FROZEN in the first FR-SCHEMA commit. }

interface

/// <summary>Resolves the field repository file of a project; first hit wins.</summary>
/// <param name="pProjectFile">The project file (.dproj / .dpr), '' when none is known.</param>
/// <param name="pExplicit">The --repo flag value, '' when not given.</param>
/// <returns>(1) pExplicit; (2) "fieldRepository" in the project's _D-RAG\drag-lint-project.json (relative paths
/// against the project folder); (3) "fieldRepository" on the manifest section whose "include" lists the project
/// file; else '' (no repository). The file is NOT required to exist: existence is the caller's business.</returns>
/// <remarks>The manifest of step 3 is the file named by the DRAGLINT_MANIFEST environment variable, else
/// drag-lint.json beside the running exe. An unreadable or malformed config or manifest is treated as
/// absent, never raised.</remarks>
function LocateFieldRepository(const pProjectFile, pExplicit: string): string; overload;

/// <summary>As the two-argument overload, with the manifest file named by the caller (resolve-dbs --config).</summary>
/// <param name="pProjectFile">The project file, '' when none.</param>
/// <param name="pExplicit">The --repo flag value, '' when none.</param>
/// <param name="pManifestFile">Full path of the manifest to read for step 3; '' = the default lookup.</param>
/// <returns>See the two-argument overload.</returns>
function LocateFieldRepository(const pProjectFile, pExplicit, pManifestFile: string): string; overload;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.JSON;

const
  CFG_KEY = 'fieldRepository';
  CFG_FILE = 'drag-lint-project.json';
  CFG_DIR = '_D-RAG';
  MANIFEST_FILE = 'drag-lint.json';
  MANIFEST_ENV = 'DRAGLINT_MANIFEST';

function ParseFile(const pFile: string): TJSONValue;
begin
  Result := nil;
  if not TFile.Exists(pFile) then
    Exit;
  try
    Result := TJSONObject.ParseJSONValue(TFile.ReadAllText(pFile));
  except
    on EInOutError do
      Result := nil;
  end;
end;

function StringKey(pObject: TJSONValue): string;
var
  VNode: TJSONValue;
begin
  Result := '';
  if pObject is TJSONObject then
  begin
    VNode := TJSONObject(pObject).GetValue(CFG_KEY);
    if VNode is TJSONString then
      Result := TJSONString(VNode).Value;
  end;
end;

function FromProjectConfig(const pProjectFile: string): string;
var
  VDir: string;
  VRoot: TJSONValue;
begin
  Result := '';
  VDir := ExtractFilePath(ExpandFileName(pProjectFile));
  VRoot := ParseFile(TPath.Combine(TPath.Combine(VDir, CFG_DIR), CFG_FILE));
  if VRoot = nil then
    Exit;
  try
    Result := StringKey(VRoot);
    if Result <> '' then
      Result := TPath.GetFullPath(TPath.Combine(VDir, Result));
  finally
    VRoot.Free;
  end;
end;

function IncludeMatches(pIncludes: TJSONValue; const pRoot, pProject: string): Boolean;
var
  VItem: TJSONValue;
begin
  Result := False;
  if pIncludes is not TJSONArray then
    Exit;
  for VItem in TJSONArray(pIncludes) do
    if (VItem is TJSONString) and
      SameText(TPath.GetFullPath(TPath.Combine(pRoot, TJSONString(VItem).Value)), pProject) then
      Exit(True);
end;

function FromManifest(const pProjectFile, pManifestFile: string): string;
var
  VFile, VRootDir, VProject: string;
  VRoot, VSections, VSection: TJSONValue;
begin
  Result := '';
  VFile := pManifestFile;
  if VFile = '' then
    VFile := GetEnvironmentVariable(MANIFEST_ENV);
  if VFile = '' then
    VFile := TPath.Combine(ExtractFilePath(ParamStr(0)), MANIFEST_FILE);
  VRoot := ParseFile(VFile);
  if VRoot = nil then
    Exit;
  try
    VRootDir := ExtractFilePath(ExpandFileName(VFile));
    VProject := TPath.GetFullPath(pProjectFile);
    if VRoot is not TJSONObject then
      Exit;
    VSections := TJSONObject(VRoot).GetValue('indexes');
    if VSections is TJSONObject then
      VSections := TJSONObject(VSections).GetValue('sections');
    if VSections is not TJSONArray then
      Exit;
    for VSection in TJSONArray(VSections) do
      if (VSection is TJSONObject) and IncludeMatches(TJSONObject(VSection).GetValue('include'), VRootDir, VProject)
        and (StringKey(VSection) <> '') then
        Exit(TPath.GetFullPath(TPath.Combine(VRootDir, StringKey(VSection))));
  finally
    VRoot.Free;
  end;
end;

function LocateFieldRepository(const pProjectFile, pExplicit: string): string;
begin
  Result := LocateFieldRepository(pProjectFile, pExplicit, '');
end;

function LocateFieldRepository(const pProjectFile, pExplicit, pManifestFile: string): string;
begin
  if pExplicit <> '' then
    Exit(ExpandFileName(pExplicit));
  Result := '';
  if pProjectFile = '' then
    Exit;
  Result := FromProjectConfig(pProjectFile);
  if Result = '' then
    Result := FromManifest(pProjectFile, pManifestFile);
end;

end.
