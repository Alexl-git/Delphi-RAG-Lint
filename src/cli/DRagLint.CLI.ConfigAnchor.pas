unit DRagLint.CLI.ConfigAnchor;

{ drag-lint 1.53 (lane BUGS; docs\INBOX-lint-all-db-copy-misses-project-config.md): the lint config of
  the project an index was BUILT FROM. `lint-all --db <copy>` names no file and no project, and a copy in
  a scratch folder has no drag-lint-lint.json at or above it, so the project's rulings were dropped with
  no word. The index itself names its project: the project_tag stamp plus the indexed project source
  (.dpr / .dpk). DRagLint.CLI.LoadLintConfig asks here after the DB-folder walk and before the CWD. }

interface

/// <summary>The project source file (.dpr / .dpk / .lpr) an index was built from.</summary>
/// <param name="pDbPath">The index file.</param>
/// <returns>The full path, or '' when the index is not a project index (no project_tag), cannot be
/// opened, holds no such file or several in different folders, or the file is not on this machine.</returns>
/// <remarks>Opens the index read-only; the answer for the last pDbPath is kept, so repeated calls for one
/// index open it once. Never raises for an unreadable index. Not thread-safe.</remarks>
function IndexedProjectFile(const pDbPath: string): string;

/// <summary>The nearest drag-lint-lint.json at or above the project: in each folder, then in its
/// _D-RAG.</summary>
/// <param name="pProject">--project value; '' = the project pDbPath was indexed from.</param>
/// <param name="pDbPath">The index file.</param>
/// <returns>The config path, or '' when there is none.</returns>
function ConfigAboveProject(const pProject, pDbPath: string): string;

/// <summary>Says on stderr, once per process, that the rulings of an index's project could not be
/// found: it IS a project index, but its project is not on this machine.</summary>
/// <param name="pDbPath">The index file.</param>
/// <remarks>Silent for a folder-scan index, and for a project that is here but has no config. The caller
/// keeps it off machine-readable and --quiet runs. Not thread-safe.</remarks>
procedure NoteNoLintConfig(const pDbPath: string);

implementation

uses
  System.SysUtils
  , System.StrUtils
  , System.IOUtils
  , DRagLint.Core.Interfaces
  , DRagLint.Project.Coherence
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

function IndexedProjectFile(const pDbPath: string): string;
begin
  LoadIndexFacts(pDbPath);
  Result:= GProjectFile;
end;

function ConfigAboveProject(const pProject, pDbPath: string): string;
begin
  var ProjectFile: string:= if pProject <> '' then TPath.GetFullPath(StringReplace(pProject, '/', '\', [rfReplaceAll]))
    else IndexedProjectFile(pDbPath);
  Result:= if ProjectFile = '' then '' else FindConfigAbove(ExtractFilePath(ProjectFile));
end;

procedure NoteNoLintConfig(const pDbPath: string);
begin
  LoadIndexFacts(pDbPath);
  if GNoted or (GTag = '') or (GProjectFile <> '') then Exit;
  GNoted:= True;
  Writeln(ErrOutput, Format('drag-lint: note: no drag-lint-lint.json was found for %s (looked in %s and above it, and in %s); ' +
    'it is the index of project %s, whose project file was not found on this machine, so that project''s lint rulings are NOT applied. ' +
    'Pass --config <drag-lint-lint.json> or --project <%s.dproj> (--quiet hides this note).',
    [pDbPath, ExcludeTrailingPathDelimiter(ExtractFilePath(TPath.GetFullPath(pDbPath))), GetCurrentDir, GTag, GTag]));
end;

end.
