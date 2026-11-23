unit DRagLint.CLI.ConfigAnchor;

{ drag-lint 1.53 (lane BUGS; docs\INBOX-lint-all-db-copy-misses-project-config.md): the lint config of
  the project an index was BUILT FROM. `lint-all --db <copy>` names no file and no project, and a copy in
  a scratch folder has no drag-lint-lint.json at or above it, so the project's rulings were dropped with
  no word. The index itself names its project: the project_tag stamp plus the indexed project source
  (.dpr / .dpk). DRagLint.CLI.LoadLintConfig asks here after the DB-folder walk and before the CWD. }

interface

/// <summary>The index that anchors a run no file names.</summary>
/// <param name="pDbPath">--db value, or ''.</param>
/// <param name="pFile">The file the run is about (any of its names), or ''.</param>
/// <returns>pDbPath, or '' when a file names the run (the file is the more specific anchor).</returns>
function DbWhenNoFile(const pDbPath, pFile: string): string;

/// <summary>The project-settings folder of a run: the one already resolved, else that of the project
/// the index was built from.</summary>
/// <param name="pAnchor">The folder already resolved, or ''.</param>
/// <param name="pDbPath">The anchoring index, or ''.</param>
/// <returns>The folder, or ''.</returns>
function SettingsAnchorOr(const pAnchor, pDbPath: string): string;

/// <summary>The lint config of a run: the one already found, else the nearest drag-lint-lint.json at or
/// above the project (in each folder, then in its _D-RAG).</summary>
/// <param name="pPath">The config already found, or ''.</param>
/// <param name="pProject">--project value; '' = the project pDbPath was indexed from.</param>
/// <param name="pDbPath">The anchoring index, or '' (then pPath is the answer).</param>
/// <returns>The config path, or '' when there is none.</returns>
function ConfigPathOr(const pPath, pProject, pDbPath: string): string;

/// <summary>Says on stderr, once per process, that the rulings of an index's project could not be
/// found: no config was found, it IS a project index, but its project is not on this machine.</summary>
/// <param name="pPath">The config found, or ''.</param>
/// <param name="pProject">--project value, or ''.</param>
/// <param name="pDbPath">The anchoring index, or ''.</param>
/// <remarks>Silent with a config or a --project, for a folder-scan index, for a project that is here but
/// has no config, and under --quiet / --json / --format sarif (TManifestIO.QuietNoManifest). Not
/// thread-safe.</remarks>
procedure NoteNoLintConfig(const pPath, pProject, pDbPath: string);

implementation

uses
  System.SysUtils
  , System.StrUtils
  , System.IOUtils
  , DRagLint.Core.Interfaces
  , DRagLint.Index.Manifest
  , DRagLint.Project.Coherence // dl:unit DRagLint.Project.Coherence accepted -- PROJECT_TAG_KEY is the key the coherence check reads; the anchor must use the same name, so it travels with that unit
  , DRagLint.Project.Settings
  , DRagLint.CLI.Common
  , DRagLint.CLI.RuleScope
  ;

var
  { The answer for GDb: its project tag ('' = not a project index) and project file. }
  GDb         : string;
  GTag        : string;
  GProjectFile: string;
  GNoted      : Boolean;

{ The one indexed project source named pTag; '' when there is none, or when the candidates sit in
  different folders (then no folder is THE project's). A .dpr and a .dpk side by side are one folder. }
function FindProjectFile(const pStore: ISymbolStore; const pTag: string): string;
begin
  Result:= '';
  for var Fid in pStore.GetAllFileIds do
  begin
    var FileName: string:= pStore.GetFilePath(Fid);
    if not MatchText(ExtractFileExt(FileName), ['.dpr', '.dpk', '.lpr']) then Continue;
    if not SameText(SanitizeProjectTag(TPath.GetFileNameWithoutExtension(FileName)), pTag) then Continue;
    if (Result <> '') and not SameText(ExtractFilePath(Result), ExtractFilePath(FileName)) then Exit('');
    Result:= FileName;
  end;
end;

procedure LoadIndexFacts(const pDbPath: string);
begin
  if SameText(GDb, pDbPath) then Exit;
  GDb:= pDbPath;
  GTag:= '';
  GProjectFile:= '';
  if not TFile.Exists(pDbPath) then Exit;
  var IsOpen: Boolean;
  var Store: ISymbolStore:= OpenReadOnlyStore(pDbPath, IsOpen, {AQuiet=}True);
  if not IsOpen then Exit;
  GTag:= Trim(Store.GetMetaValue(PROJECT_TAG_KEY));
  if GTag = '' then Exit;
  GProjectFile:= FindProjectFile(Store, GTag);
  if not TFile.Exists(GProjectFile) then GProjectFile:= '';
end;

{ The project source file (.dpr / .dpk / .lpr) pDbPath was built from; '' when it is not a project
  index, cannot be opened, names no single project file, or the file is not on this machine. Opens the
  index once per pDbPath. }
function IndexedProjectFile(const pDbPath: string): string;
begin
  LoadIndexFacts(pDbPath);
  Result:= GProjectFile;
end;

function DbWhenNoFile(const pDbPath, pFile: string): string;
begin
  Result:= if pFile = '' then pDbPath else '';
end;

function SettingsAnchorOr(const pAnchor, pDbPath: string): string;
begin
  Result:= pAnchor;
  if (Result = '') and (pDbPath <> '') then Result:= TProjectSettings.ResolveAnchor('', IndexedProjectFile(pDbPath), '', '');
end;

function ConfigPathOr(const pPath, pProject, pDbPath: string): string;
begin
  if (pPath <> '') or (pDbPath = '') then Exit(pPath);
  var ProjectFile: string:= if pProject <> '' then TPath.GetFullPath(StringReplace(pProject, '/', '\', [rfReplaceAll]))
    else IndexedProjectFile(pDbPath);
  Result:= if ProjectFile = '' then '' else FindConfigAbove(ExtractFilePath(ProjectFile));
end;

procedure NoteNoLintConfig(const pPath, pProject, pDbPath: string);
begin
  if (pPath + pProject <> '') or (pDbPath = '') or TManifestIO.QuietNoManifest then Exit;
  LoadIndexFacts(pDbPath);
  if GNoted or (GTag = '') or (GProjectFile <> '') then Exit;
  GNoted:= True;
  Writeln(ErrOutput, Format('drag-lint: note: no drag-lint-lint.json was found for %s (looked in %s and above it, and in %s); ' +
    'it is the index of project %s, whose project file was not found on this machine, so that project''s lint rulings are NOT applied. ' +
    'Pass --config <drag-lint-lint.json> or --project <%s.dproj> (--quiet hides this note).',
    [pDbPath, ExcludeTrailingPathDelimiter(ExtractFilePath(TPath.GetFullPath(pDbPath))), GetCurrentDir, GTag, GTag]));
end;

end.
