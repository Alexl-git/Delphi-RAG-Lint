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
  System.SysUtils
  , System.Classes
  , System.IOUtils
  , System.JSON
  , ToolsAPI
  , DragLint.Plugin.Telemetry
  , { TEMP debug telemetry }
    DragLint.Plugin.Settings
  ;

{ v0.46: returns the manifest section DB whose include folder is an ancestor of
  AFilePath (longest/most-specific match wins), or '' when there is no manifest
  beside the engine or no covering section. This is the SAME clean DB the
  manifest builds (e.g. ...\ORM3\drag-lint.sqlite for any ORM3 file), so the
  plugin stops reading stale per-.dproj DBs. Used by both the read side
  (ResolveActiveIndexDbs) and the write side (ProjectNotifier auto-index). }
function ManifestDbForFile(const AFilePath: string): string;

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
function PrimaryDbForProject(const AProjPath: string; const ASettings: TDragLintSettings): string;

{ The headline function: returns ALL DBs the plugin should query for the
  currently-active editor file, in priority order. Empty paths and
  non-existent files are filtered. Duplicates removed. }
function ResolveActiveIndexDbs(const ASettings: TDragLintSettings): TArray<string>;

{ v0.40.5: exposed for the Find Usages debug panel. Returns a multi-line
  diagnostic string showing exactly what the resolver saw and decided. }
function ResolverDiagnostic(const ASettings: TDragLintSettings): string;

implementation

function ManifestPathBesideEngine: string;
begin
  Result:= ExtractFilePath(GetModuleName(HInstance)) + 'drag-lint.json';
end;

function ManifestDbForFile(const AFilePath: string): string;
var
  MPath   : string     ;
  Content : string     ;
  OutDir  : string     ;
  FileNorm: string     ;
  Db      : string     ;
  IncRaw  : string     ;
  IncNorm : string     ;
  BestDb  : string     ;
  RootVal : TJSONValue ;
  V       : TJSONValue ;
  IdxVal  : TJSONValue ;
  SecsVal : TJSONValue ;
  IncVal  : TJSONValue ;
  Indexes : TJSONObject;
  Sec     : TJSONObject;
  Sections: TJSONArray ;
  Includes: TJSONArray ;
  I       : Integer    ;
  J       : Integer    ;
  BestLen : Integer    ;
begin
  Result:= '';
  if AFilePath = '' then Exit;
  MPath:= ManifestPathBesideEngine;
  if not TFile.Exists(MPath) then Exit;
  FileNorm:= LowerCase(IncludeTrailingPathDelimiter(ExtractFilePath(AFilePath)));
  try
    Content:= TFile      .ReadAllText   (MPath  );
    RootVal:= TJSONObject.ParseJSONValue(Content);
    if not (RootVal is TJSONObject) then Exit;
    try
      IdxVal:= TJSONObject(RootVal).GetValue('indexes');
      if not (IdxVal is TJSONObject) then Exit;
      Indexes:= TJSONObject(IdxVal);

      OutDir:= '';
      V:= Indexes.GetValue('outDir');
      if V is TJSONString then OutDir:= TJSONString(V).Value;

      SecsVal:= Indexes.GetValue('sections');
      if not (SecsVal is TJSONArray) then Exit;
      Sections:= TJSONArray(SecsVal);

      BestDb:= '';
      BestLen:= -1;
      for I:= 0 to Sections.Count - 1 do
      begin
        if not (Sections.Items[I] is TJSONObject) then Continue;
        Sec:= TJSONObject(Sections.Items[I]);

        IncVal:= Sec.GetValue('include');
        if not (IncVal is TJSONArray) then Continue; { skip library sections }
        Includes:= TJSONArray(IncVal);

        Db:= '';
        V:= Sec.GetValue('db');
        if V is TJSONString then Db:= TJSONString(V).Value;
        if Db = '' then Continue;

        for J:= 0 to Includes.Count - 1 do
        begin
          if not (Includes.Items[J] is TJSONString) then Continue;
          IncRaw:= TJSONString(Includes.Items[J]).Value;
          { an include may be a folder OR a .dproj/.dpr -- use its folder }
          if SameText(ExtractFileExt(IncRaw), '.dproj') or SameText(ExtractFileExt(IncRaw), '.dpr') then IncRaw:= ExtractFilePath(IncRaw);
          IncNorm:= LowerCase(IncludeTrailingPathDelimiter(IncRaw));
          { file under this include folder? longest match = most specific }
          if (Length(IncNorm) > 1) and (Pos(IncNorm, FileNorm) = 1) and (Length(IncNorm) > BestLen) then
          begin
            if TPath.IsRelativePath(Db) and (OutDir <> '') then BestDb:= TPath.Combine(OutDir, Db)
            else BestDb:= Db;
            BestLen:= Length(IncNorm);
          end;
        end; // for
      end; // for
      Result:= BestDb;
    finally
      RootVal.Free;
    end; // try
  except
    Result:= '';
  end; // try
end; // function

function GetActiveEditorFilePath: string;
var
  ESS: IOTAEditorServices;
  EV : IOTAEditView      ;
begin
  Result:= '';
  try
    if not Supports(BorlandIDEServices, IOTAEditorServices, ESS) then Exit;
    if ESS = nil then Exit;
    EV:= ESS.TopView;
    if EV        = nil then Exit;
    if EV.Buffer = nil then Exit;
    Result:= EV.Buffer.FileName;
  except
    Result:= '';
  end;
end;

function GetActiveProjectFilePath: string;
{ v0.40.5 fallback when the editor view path is empty -- happens when the
  Find Usages menu is invoked from a non-editor focus (Project Manager,
  Object Inspector, etc.). Pulls the currently-active .dproj from
  IOTAProjectGroup, which is stable across focus changes. }
var
  MS        : IOTAModuleServices;
  ProjGroup : IOTAProjectGroup  ;
  ActiveProj: IOTAProject       ;
begin
  Result:= '';
  try
    if not Supports(BorlandIDEServices, IOTAModuleServices, MS) then Exit;
    if MS = nil then Exit;
    ProjGroup:= MS.MainProjectGroup;
    if ProjGroup = nil then Exit;
    ActiveProj:= ProjGroup.ActiveProject;
    if ActiveProj = nil then Exit;
    Result:= ActiveProj.FileName;
  except
    Result:= '';
  end;
end;

function FindOwningProject(const AFilePath: string): string;
var
  Dir   : string        ;
  Files : TArray<string>;
  Parent: string        ;
begin
  Result:= '';
  if AFilePath = '' then Exit;
  Dir:= ExtractFilePath(ExcludeTrailingPathDelimiter(AFilePath));
  while (Dir <> '') and TDirectory.Exists(Dir) do
  begin
    Files:= TDirectory.GetFiles(Dir, '*.dproj');
    if Length(Files) > 0 then
    begin
      Result:= Files[0];
      Exit;
    end;
    Parent:= ExtractFileDir(ExcludeTrailingPathDelimiter(Dir));
    if (Parent = '') or SameText(Parent, Dir) then Break;
    Dir:= Parent;
  end;
end; // function

function PrimaryDbForProject(const AProjPath: string; const ASettings: TDragLintSettings): string;
var
  ProjDir: string;
begin
  Result:= '';
  if AProjPath = '' then Exit;
  ProjDir:= ExtractFilePath(AProjPath);
  Result:= ResolveDbPath(ASettings.DbPathTemplate, ProjDir);
end;

function NormalizePath(const APath: string): string;
begin
  if APath = '' then Result:= '' else Result:= LowerCase(ExpandFileName(APath));
end;

procedure AddUnique(var ADbs: TArray<string>; const APath: string);
var
  Norm: string ;
  I   : Integer;
begin
  if APath = '' then Exit;
  Norm:= NormalizePath(APath);
  for I:= 0 to High(ADbs) do
    if NormalizePath(ADbs[I]) = Norm then Exit;
  SetLength(ADbs, Length(ADbs) + 1);
  ADbs[High(ADbs)]:= APath;
end;

procedure DiscoverSiblings(var ADbs: TArray<string>; const APrimaryProjPath: string; const ASettings: TDragLintSettings);
var
  ProjDir  : string        ;
  ParentDir: string        ;
  SubDirs  : TArray<string>;
  Sub      : string        ;
  ProjFiles: TArray<string>;
  SiblingDb: string        ;
begin
  if (APrimaryProjPath = '') or (not ASettings.AutoDiscoverDbs) then Exit;
  ProjDir:= ExtractFilePath(APrimaryProjPath);
  ParentDir:= ExtractFileDir(ExcludeTrailingPathDelimiter(ProjDir));
  if (ParentDir = '') or not TDirectory.Exists(ParentDir) then Exit;

  SubDirs:= TDirectory.GetDirectories(ParentDir);
  for Sub in SubDirs do
  begin
    if SameText(IncludeTrailingPathDelimiter(Sub), IncludeTrailingPathDelimiter(ProjDir)) then Continue;
    ProjFiles:= TDirectory.GetFiles(Sub, '*.dproj');
    if Length(ProjFiles) = 0 then Continue;
    SiblingDb:= ResolveDbPath(ASettings.DbPathTemplate, Sub);
    if TFile.Exists(SiblingDb) then AddUnique(ADbs, SiblingDb);
  end;
end; // procedure

function GetLibraryDbPath: string;
{ v0.46: the v0.45 manifest renamed library DBs to library-<platform>.sqlite.
  Prefer a fresh per-platform DB deployed beside the BPL (Win32 is the manifest
  default platform, then Win64), but fall back to the legacy merged
  drag-lint-library.sqlite -- still a complete all-platform symbol set for
  "which unit declares X" -- so existing installs keep working. }
var
  Dir       : string               ;
  C         : string               ;
  Candidates: array[0..2] of string;
begin
  Dir:= ExtractFilePath(GetModuleName(HInstance));
  Candidates[0]:= Dir + 'library-Win32.sqlite';
  Candidates[1]:= Dir + 'library-Win64.sqlite';
  Candidates[2]:= Dir + 'drag-lint-library.sqlite';
  for C in Candidates do
    if TFile.Exists(C) then Exit(C);
  Result:= Dir + 'drag-lint-library.sqlite'; { legacy default even if absent }
end;

/// <summary>Returns the active project's target platform via OTAPI.
/// Returns '' if not determinable (non-IDE context).</summary>
/// <remarks>Duplicates GetActiveProjectPlatform from Plugin.Editor to
/// avoid a circular unit dependency (Editor already uses DbResolver).
/// Not thread-safe; call from the main thread only.</remarks>
function GetActivePlatformForLibrary: string;
var
  MS        : IOTAModuleServices;
  ProjGroup : IOTAProjectGroup  ;
  ActiveProj: IOTAProject       ;
  P         : string            ;
begin
  Result:= '';
  try
    if not Supports(BorlandIDEServices, IOTAModuleServices, MS) then Exit;
    if MS = nil then Exit;
    ProjGroup:= MS.MainProjectGroup;
    if ProjGroup = nil then Exit;
    ActiveProj:= ProjGroup.ActiveProject;
    if ActiveProj = nil then Exit;
    P:= ActiveProj.CurrentPlatform;
    if P <> '' then Result:= P;
  except
  end;
end; // function

/// <summary>Returns the platform-specific library DB path using the manifest
/// outDir and the currently active project's platform from OTAPI.
/// Falls back to GetLibraryDbPath if the manifest or file is unavailable.</summary>
/// <param name="ASettings">Plugin settings; ExePath provides the engine dir
/// where drag-lint.json is located.</param>
/// <returns>Absolute path to the best available library DB.</returns>
/// <remarks>Not thread-safe; call from the main thread only.</remarks>
function GetPlatformAwareLibraryDbPath(
  const ASettings: TDragLintSettings): string;
var
  EngineDir : string      ;
  MPath     : string      ;
  Content   : string      ;
  OutDir    : string      ;
  LibPlat   : string      ;
  Db        : string      ;
  RootVal   : TJSONValue  ;
  IdxVal    : TJSONValue  ;
  OutDirVal : TJSONValue  ;
begin
  try
    // Locate the manifest beside the engine exe (from ExePath setting).
    if ASettings.ExePath <> '' then
      EngineDir:= ExtractFilePath(ASettings.ExePath)
    else
      EngineDir:= ExtractFilePath(GetModuleName(HInstance));
    MPath:= TPath.Combine(EngineDir, 'drag-lint.json');
    if TFile.Exists(MPath) then
    begin
      Content:= TFile.ReadAllText(MPath);
      OutDir:= '';
      RootVal:= TJSONObject.ParseJSONValue(Content);
      if RootVal is TJSONObject then
      try
        IdxVal:= TJSONObject(RootVal).GetValue('indexes');
        if IdxVal is TJSONObject then
        begin
          OutDirVal:= TJSONObject(IdxVal).GetValue('outDir');
          if OutDirVal is TJSONString then
            OutDir:= TJSONString(OutDirVal).Value;
        end;
      finally
        RootVal.Free;
      end; // try

      if OutDir <> '' then
      begin
        LibPlat:= GetActivePlatformForLibrary;
        if LibPlat = '' then LibPlat:= 'Win64';
        Db:= TPath.Combine(OutDir, 'library-' + LibPlat + '.sqlite');
        if TFile.Exists(Db) then Exit(Db);
        // Platform DB missing -- fall through to legacy search.
      end;
    end;
  except
  end;
  Result:= GetLibraryDbPath; // fallback: BPL-relative Win32/Win64/legacy
end; // function

function FindAncestorDb(const AStartDir: string; const ASettings: TDragLintSettings): string;
{ v0.40.5: many real-world projects (Micronite is the canonical case)
  store one shared drag-lint.sqlite ABOVE the .dproj directory because
  the workspace contains multiple sub-projects (CLIENT, SERVER, COMMON,
  PACKAGE) that all index into the same DB. When the primary template-
  resolved DB doesn't exist next to the .dproj, walk up the directory
  tree looking for a drag-lint.sqlite. Stops at the drive root.

  At each level we try BOTH the configured template AND the canonical
  unprefixed default. Catches the case where a user's old registry
  template still points at the legacy '.drag-lint.sqlite' (dot-prefixed)
  pattern but their actual DB lives at 'drag-lint.sqlite'. }
const
  CANONICAL_TEMPLATE = '<projdir>\drag-lint.sqlite';
var
  Dir       : string        ;
  Parent    : string        ;
  Candidates: TArray<string>;
  C         : string        ;
begin
  Result:= '';
  Dir:= ExcludeTrailingPathDelimiter(AStartDir);
  while (Dir <> '') and TDirectory.Exists(Dir) do
  begin
    SetLength(Candidates, 0);
    if ASettings.DbPathTemplate <> '' then
    begin
      SetLength(Candidates, 1);
      Candidates[0]:= ResolveDbPath(ASettings.DbPathTemplate, Dir);
    end;
    { Always also try the canonical default (in case the user's template
      is misconfigured or legacy). }
    SetLength(Candidates, Length(Candidates) + 1);
    Candidates[High(Candidates)]:= ResolveDbPath(CANONICAL_TEMPLATE, Dir);

    for C in Candidates do
      if (C <> '') and TFile.Exists(C) then Exit(C);

    Parent:= ExtractFileDir(Dir);
    if (Parent = '') or SameText(Parent, Dir) then Break;
    Dir:= Parent;
  end; // while
end; // function

function ResolverDiagnostic(const ASettings: TDragLintSettings): string;
var
  EditorPath  : string        ;
  ProjPath    : string        ;
  FallbackProj: string        ;
  PrimaryDb   : string        ;
  AncestorDb  : string        ;
  SB          : TStringBuilder;
begin
  SB:= TStringBuilder.Create;
  try
    EditorPath:= GetActiveEditorFilePath;
    SB.AppendLine('EditorPath: "' + EditorPath + '"');
    ProjPath:= FindOwningProject(EditorPath);
    SB.AppendLine('FindOwningProject(editor): "' + ProjPath + '"');
    if ProjPath = '' then
    begin
      FallbackProj:= GetActiveProjectFilePath;
      SB.AppendLine('GetActiveProjectFilePath fallback: "' + FallbackProj + '"');
      ProjPath:= FallbackProj;
    end;
    PrimaryDb:= PrimaryDbForProject(ProjPath, ASettings);
    SB.AppendLine('PrimaryDb: "' + PrimaryDb + '" (exists=' + BoolToStr(TFile.Exists(PrimaryDb), True) + ')');
    if (not TFile.Exists(PrimaryDb)) and (ProjPath <> '') then
    begin
      AncestorDb:= FindAncestorDb(ExtractFilePath(ProjPath), ASettings);
      SB.AppendLine('FindAncestorDb walking up: "' + AncestorDb + '"');
    end;
    SB.AppendLine('DbPathTemplate: ' + ASettings.DbPathTemplate);
    SB.AppendLine('IncludeLibraryDb: ' + BoolToStr(ASettings.IncludeLibraryDb, True));
    SB.AppendLine('AutoDiscoverDbs: '  + BoolToStr(ASettings.AutoDiscoverDbs , True));
    Result:= SB.ToString;
  finally
    SB.Free;
  end; // try
end; // function

function ResolveActiveIndexDbs(const ASettings: TDragLintSettings): TArray<string>;
var
  EditorPath: string;
  ProjPath  : string;
  ProjDir   : string;
  PrimaryDb : string;
  AncestorDb: string;
  P         : string;
  LibPath   : string;
  ManifestDb: string;
begin
  SetLength(Result, 0);

  { Try editor view first; if no active editor (Find Usages invoked from
    Project Manager focus, etc.), fall back to the active project group's
    project file. Then walk up from THAT to find a .dproj. }
  EditorPath:= GetActiveEditorFilePath;
  ProjPath:= FindOwningProject(EditorPath);
  if ProjPath = '' then ProjPath:= GetActiveProjectFilePath;

  { v0.46: the manifest is the source of truth. If a manifest section's include
    folder covers the active file, use THAT clean DB and skip the per-.dproj
    template/ancestor/sibling walk -- otherwise a stale per-project DB sitting
    next to a sub-project .dproj (e.g. CLIENT\drag-lint.sqlite) shadows the
    manifest's ORM3-root DB and shows phantom/duplicated symbols. The library DB
    is still appended below. }
  ManifestDb:= ManifestDbForFile(EditorPath);
  if ManifestDb = '' then ManifestDb:= ManifestDbForFile(ProjPath);
  if (ManifestDb <> '') and TFile.Exists(ManifestDb) then
  begin
    AddUnique(Result, ManifestDb);
    for P in ASettings.IndexDbs do
      if TFile.Exists(P) then AddUnique(Result, P);
    if ASettings.IncludeLibraryDb then
    begin
      LibPath:= GetPlatformAwareLibraryDbPath(ASettings);
      if TFile.Exists(LibPath) then AddUnique(Result, LibPath);
    end;
    DLT('dbresolve', Format('editor=%s -> MANIFEST db=%s (+%d total)', [ExtractFileName(EditorPath), ManifestDb, Length(Result)]));
    Exit;
  end;

  { Try the template-resolved primary DB next to the .dproj first.
    v0.40.5: if the configured template doesn't yield an existing file,
    walk up the directory tree from the .dproj's folder. FindAncestorDb
    tries both the configured template AND the canonical default at
    each level, so legacy '.drag-lint.sqlite' configs still find the
    user's actual 'drag-lint.sqlite' wherever it lives. }
  if ProjPath <> '' then
  begin
    PrimaryDb:= PrimaryDbForProject(ProjPath, ASettings);
    if TFile.Exists(PrimaryDb) then AddUnique(Result, PrimaryDb)
    else
    begin
      ProjDir:= ExtractFilePath(ProjPath);
      AncestorDb:= FindAncestorDb(ProjDir, ASettings);
      if AncestorDb <> '' then AddUnique(Result, AncestorDb);
    end;
  end;

  DiscoverSiblings(Result, ProjPath, ASettings);

  for P in ASettings.IndexDbs do
    if TFile.Exists(P) then AddUnique(Result, P);

  if ASettings.IncludeLibraryDb then
  begin
    LibPath:= GetPlatformAwareLibraryDbPath(ASettings);
    if TFile.Exists(LibPath) then AddUnique(Result, LibPath);
  end;
  DLT('dbresolve', Format('editor=%s proj=%s -> %d db(s) (no manifest match)', [ExtractFileName(EditorPath), ExtractFileName(ProjPath), Length(Result)]));
end; // function

end.
