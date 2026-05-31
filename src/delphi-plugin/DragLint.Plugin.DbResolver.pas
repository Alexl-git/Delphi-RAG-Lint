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

function ResolveActiveIndexDbs(const ASettings: TDragLintSettings): TArray<string>;
var
  EditorPath: string;
  ProjPath:   string;
  PrimaryDb:  string;
  P:          string;
  LibPath:    string;
begin
  SetLength(Result, 0);

  EditorPath := GetActiveEditorFilePath;
  ProjPath := FindOwningProject(EditorPath);
  PrimaryDb := PrimaryDbForProject(ProjPath, ASettings);
  if TFile.Exists(PrimaryDb) then
    AddUnique(Result, PrimaryDb);

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
