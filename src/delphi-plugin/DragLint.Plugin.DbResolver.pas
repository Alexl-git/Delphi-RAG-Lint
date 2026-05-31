unit DragLint.Plugin.DbResolver;

(* v0.40.3: single source of truth for "which sqlite DBs should we query?"

   Before v0.40.3 there were two divergent resolvers in the plugin:
     - ProjectNotifier.SpawnIndexer used ResolveDbPath(template, projDir)
     - Editor.GetActiveProjectDb used ChangeFileExt(activeProjFile, '.sqlite')
   These disagreed (different filenames -> different paths) so Find Usages
   and similar would point at a non-existent file. This unit replaces both.

   Resolution order:
     1. The "primary" DB derived from the active editor's owning .dproj.
        We walk up from the file under the cursor to find the nearest
        .dproj, then derive its sqlite path via the settings template.
     2. Auto-discovered sibling DBs: every .sqlite file in directories
        adjacent to the primary that ALSO contain a .dproj (so we don't
        pull in random sqlites). Catches Micronite's CLIENT / SERVER /
        COMMON / PACKAGE pattern automatically.
     3. The user's explicit IndexDbs list from Settings.
     4. The exe-relative drag-lint-library.sqlite, if Settings.IncludeLibraryDb.

   Duplicates across these sources are removed (case-insensitive). Missing
   files are filtered out. Result is always non-nil but may be empty. *)

interface

uses
  System.SysUtils, System.Classes, System.IOUtils,
  ToolsAPI,
  DragLint.Plugin.Settings;

{ Returns the absolute path to the .dproj that owns the file currently
  active in the editor. Walks up the directory tree from the file's
  parent looking for any .dproj; the first one found wins. Empty if
  there's no active editor file or no .dproj anywhere above it. }
function FindOwningProject(const AFilePath: string): string;

{ Returns the absolute path of the active editor's file, or '' if none. }
function GetActiveEditorFilePath: string;

{ Returns the primary DB path for an arbitrary .dproj (or '' for none).
  Uses the template from Settings. Result may point at a file that does
  not yet exist. }
function PrimaryDbForProject(const AProjPath: string;
  const ASettings: TDragLintSettings): string;

{ The headline function: returns ALL DBs the plugin should query for the
  currently-active editor file, in priority order. Empty paths and
  non-existent files are filtered. Duplicates removed. }
function ResolveActiveIndexDbs(const ASettings: TDragLintSettings): TArray<string>;

{ v0.40.5: exposed for the Find Usages debug panel. Returns a multi-line
  diagnostic string showing exactly what the resolver saw and decided. }
function ResolverDiagnostic(const ASettings: TDragLintSettings): string;

implementation

function GetActiveEditorFilePath: string;
var
  ESS: IOTAEditorServices;
  EV:  IOTAEditView;
begin
  Result := '';
  try
    if not Supports(BorlandIDEServices, IOTAEditorServices, ESS) then Exit;
    if ESS = nil then Exit;
    EV := ESS.TopView;
    if EV = nil then Exit;
    if EV.Buffer = nil then Exit;
    Result := EV.Buffer.FileName;
  except
    Result := '';
  end;
end;

function GetActiveProjectFilePath: string;
{ v0.40.5 fallback when the editor view path is empty -- happens when the
  Find Usages menu is invoked from a non-editor focus (Project Manager,
  Object Inspector, etc.). Pulls the currently-active .dproj from
  IOTAProjectGroup, which is stable across focus changes. }
var
  MS:         IOTAModuleServices;
  ProjGroup:  IOTAProjectGroup;
  ActiveProj: IOTAProject;
begin
  Result := '';
  try
    if not Supports(BorlandIDEServices, IOTAModuleServices, MS) then Exit;
    if MS = nil then Exit;
    ProjGroup := MS.MainProjectGroup;
    if ProjGroup = nil then Exit;
    ActiveProj := ProjGroup.ActiveProject;
    if ActiveProj = nil then Exit;
    Result := ActiveProj.FileName;
  except
    Result := '';
  end;
end;

function FindOwningProject(const AFilePath: string): string;
var
  Dir:    string;
  Files:  TArray<string>;
  Parent: string;
begin
  Result := '';
  if AFilePath = '' then Exit;
  Dir := ExtractFilePath(ExcludeTrailingPathDelimiter(AFilePath));
  while (Dir <> '') and TDirectory.Exists(Dir) do
  begin
    Files := TDirectory.GetFiles(Dir, '*.dproj');
    if Length(Files) > 0 then
    begin
      Result := Files[0];
      Exit;
    end;
    Parent := ExtractFileDir(ExcludeTrailingPathDelimiter(Dir));
    if (Parent = '') or SameText(Parent, Dir) then Break;
    Dir := Parent;
  end;
end;

function PrimaryDbForProject(const AProjPath: string;
  const ASettings: TDragLintSettings): string;
var
  ProjDir: string;
begin
  Result := '';
  if AProjPath = '' then Exit;
  ProjDir := ExtractFilePath(AProjPath);
  Result := ResolveDbPath(ASettings.DbPathTemplate, ProjDir);
end;

function NormalizePath(const APath: string): string;
begin
  if APath = '' then Result := '' else Result := LowerCase(ExpandFileName(APath));
end;

procedure AddUnique(var ADbs: TArray<string>; const APath: string);
var
  Norm: string;
  I:    Integer;
begin
  if APath = '' then Exit;
  Norm := NormalizePath(APath);
  for I := 0 to High(ADbs) do
    if NormalizePath(ADbs[I]) = Norm then Exit;
  SetLength(ADbs, Length(ADbs) + 1);
  ADbs[High(ADbs)] := APath;
end;

procedure DiscoverSiblings(var ADbs: TArray<string>;
  const APrimaryProjPath: string;
  const ASettings: TDragLintSettings);
var
  ProjDir:    string;
  ParentDir:  string;
  SubDirs:    TArray<string>;
  Sub:        string;
  ProjFiles:  TArray<string>;
  SiblingDb:  string;
begin
  if (APrimaryProjPath = '') or (not ASettings.AutoDiscoverDbs) then Exit;
  ProjDir := ExtractFilePath(APrimaryProjPath);
  ParentDir := ExtractFileDir(ExcludeTrailingPathDelimiter(ProjDir));
  if (ParentDir = '') or not TDirectory.Exists(ParentDir) then Exit;

  SubDirs := TDirectory.GetDirectories(ParentDir);
  for Sub in SubDirs do
  begin
    if SameText(IncludeTrailingPathDelimiter(Sub),
                IncludeTrailingPathDelimiter(ProjDir)) then
      Continue;
    ProjFiles := TDirectory.GetFiles(Sub, '*.dproj');
    if Length(ProjFiles) = 0 then Continue;
    SiblingDb := ResolveDbPath(ASettings.DbPathTemplate, Sub);
    if TFile.Exists(SiblingDb) then
      AddUnique(ADbs, SiblingDb);
  end;
end;

function GetLibraryDbPath: string;
begin
  Result := ExtractFilePath(GetModuleName(HInstance)) +
            'drag-lint-library.sqlite';
end;

function FindAncestorDb(const AStartDir: string;
  const ASettings: TDragLintSettings): string;
{ v0.40.5: many real-world projects (Micronite is the canonical case)
  store one shared drag-lint.sqlite ABOVE the .dproj directory because
  the workspace contains multiple sub-projects (CLIENT, SERVER, COMMON,
  PACKAGE) that all index into the same DB. When the primary template-
  resolved DB doesn't exist next to the .dproj, walk up the directory
  tree looking for a drag-lint.sqlite. Stops at the drive root. }
var
  Dir, Parent, Candidate: string;
begin
  Result := '';
  Dir := ExcludeTrailingPathDelimiter(AStartDir);
  while (Dir <> '') and TDirectory.Exists(Dir) do
  begin
    Candidate := ResolveDbPath(ASettings.DbPathTemplate, Dir);
    if TFile.Exists(Candidate) then Exit(Candidate);
    Parent := ExtractFileDir(Dir);
    if (Parent = '') or SameText(Parent, Dir) then Break;
    Dir := Parent;
  end;
end;

function ResolverDiagnostic(const ASettings: TDragLintSettings): string;
var
  EditorPath, ProjPath, FallbackProj, PrimaryDb, AncestorDb: string;
  SB: TStringBuilder;
begin
  SB := TStringBuilder.Create;
  try
    EditorPath := GetActiveEditorFilePath;
    SB.AppendLine('EditorPath: "' + EditorPath + '"');
    ProjPath := FindOwningProject(EditorPath);
    SB.AppendLine('FindOwningProject(editor): "' + ProjPath + '"');
    if ProjPath = '' then
    begin
      FallbackProj := GetActiveProjectFilePath;
      SB.AppendLine('GetActiveProjectFilePath fallback: "' + FallbackProj + '"');
      ProjPath := FallbackProj;
    end;
    PrimaryDb := PrimaryDbForProject(ProjPath, ASettings);
    SB.AppendLine('PrimaryDb: "' + PrimaryDb + '" (exists=' +
      BoolToStr(TFile.Exists(PrimaryDb), True) + ')');
    if (not TFile.Exists(PrimaryDb)) and (ProjPath <> '') then
    begin
      AncestorDb := FindAncestorDb(ExtractFilePath(ProjPath), ASettings);
      SB.AppendLine('FindAncestorDb walking up: "' + AncestorDb + '"');
    end;
    SB.AppendLine('DbPathTemplate: ' + ASettings.DbPathTemplate);
    SB.AppendLine('IncludeLibraryDb: ' + BoolToStr(ASettings.IncludeLibraryDb, True));
    SB.AppendLine('AutoDiscoverDbs: ' + BoolToStr(ASettings.AutoDiscoverDbs, True));
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function ResolveActiveIndexDbs(const ASettings: TDragLintSettings): TArray<string>;
var
  EditorPath: string;
  ProjPath:   string;
  ProjDir:    string;
  PrimaryDb:  string;
  AncestorDb: string;
  P:          string;
  LibPath:    string;
begin
  SetLength(Result, 0);

  { Try editor view first; if no active editor (Find Usages invoked from
    Project Manager focus, etc.), fall back to the active project group's
    project file. Then walk up from THAT to find a .dproj. }
  EditorPath := GetActiveEditorFilePath;
  ProjPath := FindOwningProject(EditorPath);
  if ProjPath = '' then
    ProjPath := GetActiveProjectFilePath;

  { Try the template-resolved primary DB next to the .dproj first. }
  PrimaryDb := PrimaryDbForProject(ProjPath, ASettings);
  if TFile.Exists(PrimaryDb) then
    AddUnique(Result, PrimaryDb)
  else if ProjPath <> '' then
  begin
    { v0.40.5: walk up from .dproj looking for a parent-level shared DB.
      Catches Micronite's pattern where the DB lives at the workspace
      root and many sub-project .dprojs share it. }
    ProjDir := ExtractFilePath(ProjPath);
    AncestorDb := FindAncestorDb(ProjDir, ASettings);
    if AncestorDb <> '' then
      AddUnique(Result, AncestorDb);
  end;

  DiscoverSiblings(Result, ProjPath, ASettings);

  for P in ASettings.IndexDbs do
    if TFile.Exists(P) then
      AddUnique(Result, P);

  if ASettings.IncludeLibraryDb then
  begin
    LibPath := GetLibraryDbPath;
    if TFile.Exists(LibPath) then
      AddUnique(Result, LibPath);
  end;
end;

end.
