unit DRagLint.CLI.ConsumerDbs;

// ---------------------------------------------------------------------------
// Which databases a consumer verb reads (lane v1511 SPLIT, T07): the explicit --db list, else the manifest
// selection for the run's platform (CLI flag > the project's own folder > cwd > manifest default), with the
// first-use auto-create of a missing project index. Moved verbatim out of DRagLint.CLI.
// ---------------------------------------------------------------------------

interface

uses
  DRagLint.Index.Manifest, DRagLint.CLI.Common;

/// <summary>Reads the default platform from the first .dproj found under the
/// manifest section that covers ACwd. Returns '' if not found.</summary>
/// <param name="AManifest">Parsed manifest providing section include paths.</param>
/// <param name="ACwd">Current working directory; used for longest-prefix match.</param>
/// <returns>'Win32', 'Win64', or '' when no .dproj or Platform element is found.</returns>
/// <remarks>
/// Performs a top-directory-first search, then recursive if none found
/// at the top level. Not thread-safe; call from the main thread only.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.ConsumerDbs.ReadPlatformFor (DRagLint.CLI.ConsumerDbs.pas), DRagLint.CLI.DoResolveDbsList (DRagLint.CLI.pas), DRagLint.CLI.LoadManifestNameToDb (DRagLint.CLI.pas), DRagLint.CLI.ResolveReadDbsForFileWith (DRagLint.CLI.pas)</para>
/// <para>Calls: DRagLint.CLI.ConsumerDbs.PlatformFromDprojFile, IncludeTrailingPathDelimiter, SameText</para>
/// <para>Returns: ''; PlatformFromDprojFile(DprojFile)</para>
/// <para>Catches: Exception (swallowed)</para>
/// <para>Touches: file system</para>
/// <seealso cref="DRagLint.CLI.ConsumerDbs.PlatformFromDprojFile"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function DetectPlatformFromDproj(const AManifest: TIndexManifest; const ACwd: string): string;

/// <summary>Reads the active platform of ONE .dproj: its <c>&lt;Platform Condition=...&gt;</c> element.</summary>
/// <param name="ADproj">Path of the .dproj; an unreadable or platform-less file yields ''.</param>
/// <returns>'Win32', 'Win64', or '' when the file names neither.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.ConsumerDbs.DetectPlatformFromDproj (DRagLint.CLI.ConsumerDbs.pas), DRagLint.CLI.SectionLibraryPlatform (DRagLint.CLI.pas)</para>
/// <para>Calls: Pos</para>
/// <para>Returns: ''; Xml.Substring(P1, P2 - P1 - 1).Trim</para>
/// <para>Catches: Exception (swallowed)</para>
/// <para>Touches: file system</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function PlatformFromDprojFile(const ADproj: string): string;

/// <summary>Loads the manifest a --project run reads: the walk starts at the project's
/// folder, falling back to the current directory when that manifest has no owner for the
/// project (so a cwd-only registration keeps working).</summary>
/// <param name="AEngineDir">The engine exe folder (the engine-level manifest location).</param>
/// <param name="AProjectPath">The --project argument, or ''.</param>
/// <returns>The loaded manifest; never nil-like, an empty manifest when none is found.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.ConsumerDbs.ResolveConsumerDbs (DRagLint.CLI.ConsumerDbs.pas), DRagLint.CLI.ResolveCompileCheckDb (DRagLint.CLI.pas), DRagLint.CLI.RunCommand (DRagLint.CLI.pas)</para>
/// <para>Calls: DRagLint.CLI.Common.ResolveOwnProjectDb, DRagLint.CLI.ConsumerDbs.ManifestStartDir, DRagLint.Index.Manifest.TManifestIO.Load</para>
/// <para>Returns: TManifestIO.Load(AEngineDir, ManifestStartDir(AProjectPath)); TManifestIO.Load(AEngineDir, GetCurrentDir)</para>
/// <seealso cref="DRagLint.CLI.Common.ResolveOwnProjectDb"/>
/// <seealso cref="DRagLint.CLI.ConsumerDbs.ManifestStartDir"/>
/// <seealso cref="DRagLint.Index.Manifest.TManifestIO.Load"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function LoadManifestForProject(const AEngineDir, AProjectPath: string): TIndexManifest;

/// <summary>The platform a read command works in: --platform, else the platform of the
/// --project folder, else of the current directory, else the manifest's default.</summary>
/// <param name="AManifest">The loaded manifest.</param>
/// <param name="ACheckPlatform">--platform, or ''.</param>
/// <param name="AProjectPath">--project, or ''.</param>
/// <returns>The platform name; '' only when the manifest names no default either.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.ConsumerDbs.ResolveConsumerDbs (DRagLint.CLI.ConsumerDbs.pas), DRagLint.CLI.ResolveLibraryDbs (DRagLint.CLI.pas)</para>
/// <para>Calls: DRagLint.CLI.ConsumerDbs.DetectPlatformFromDproj, ExtractFilePath</para>
/// <para>Returns: ACheckPlatform; DetectPlatformFromDproj(AManifest, ExtractFilePath(TPath.GetFullPath(AProjectPath))); ''; DetectPlatformFromDproj(AManifest, GetCurrentDir); AManifest.Settings.DefaultPlatform</para>
/// <para>Catches: Exception (swallowed)</para>
/// <para>Touches: file system</para>
/// <seealso cref="DRagLint.CLI.ConsumerDbs.DetectPlatformFromDproj"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ReadPlatformFor(const AManifest: TIndexManifest; const ACheckPlatform, AProjectPath: string): string;

/// <summary>Builds the missing project index AProjDb of AArgs.ProjectPath once, under a create lock (first use); never in lsp / serve or with --no-create.</summary>
/// <param name="AArgs">The run's arguments (ProjectPath, NoCreate, Command).</param>
/// <param name="AProjDb">The project index the manifest names.</param>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.ConsumerDbs.ResolveConsumerDbs (DRagLint.CLI.ConsumerDbs.pas), DRagLint.CLI.UsagesDbForFile (DRagLint.CLI.pas)</para>
/// <para>Calls: DRagLint.CLI.Common.ReindexOwnerProject, DRagLint.CLI.ConsumerDbs.EngineIsDeployedForCreate, DRagLint.CLI.ConsumerDbs.NoteOnce, DRagLint.CLI.ConsumerDbs.TryAcquireCreateLock, ExpandFileName, Flush, Format, Writeln</para>
/// <para>Complexity: 13 (cyclomatic, outer body), 29 lines (full implementation)</para>
/// <para>Touches: file system</para>
/// <seealso cref="DRagLint.CLI.Common.ReindexOwnerProject"/>
/// <seealso cref="DRagLint.CLI.ConsumerDbs.EngineIsDeployedForCreate"/>
/// <seealso cref="DRagLint.CLI.ConsumerDbs.NoteOnce"/>
/// <seealso cref="DRagLint.CLI.ConsumerDbs.TryAcquireCreateLock"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure AutoCreateMissingProjectDb(const AArgs: TArgs; const AProjDb: string);

/// <summary>The databases a consumer verb reads: the explicit --db list unchanged, else the manifest selection for the run's platform and project.</summary>
/// <param name="AArgs">The run's arguments.</param>
/// <returns>The databases, in reading order.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.CallGraph.DoButterfly (DRagLint.CLI.CallGraph.pas), DRagLint.CLI.CallGraph.DoReverseCallTree (DRagLint.CLI.CallGraph.pas), DRagLint.CLI.Convert.DoConvertReemit (DRagLint.CLI.Convert.pas), DRagLint.CLI.Convert.DoConvertScaffold (DRagLint.CLI.Convert.pas), DRagLint.CLI.Convert.DoConvertValidate (DRagLint.CLI.Convert.pas) (+24 more)</para>
/// <para>Calls: DRagLint.CLI.Common.IsLibrarySectionDb, DRagLint.CLI.Common.LibrarySectionDbs, DRagLint.CLI.Common.ResolveOwnProjectDb, DRagLint.CLI.ConsumerDbs.AutoCreateMissingProjectDb, DRagLint.CLI.ConsumerDbs.LoadManifestForProject, DRagLint.CLI.ConsumerDbs.NoteOnce, DRagLint.CLI.ConsumerDbs.ReadPlatformFor, DRagLint.Index.DbSelect.TDbSelect.Resolve, DRagLint.Index.Manifest.OrderDbsByMembership, DRagLint.Project.Resolver.TProjectResolver.Create (+6 more)</para>
/// <para>Complexity: 15 (cyclomatic, outer body), 132 lines (full implementation)</para>
/// <para>Catches: Exception (swallowed)</para>
/// <para>Touches: file system</para>
/// <seealso cref="DRagLint.CLI.Common.IsLibrarySectionDb"/>
/// <seealso cref="DRagLint.CLI.Common.LibrarySectionDbs"/>
/// <seealso cref="DRagLint.CLI.Common.ResolveOwnProjectDb"/>
/// <seealso cref="DRagLint.CLI.ConsumerDbs.AutoCreateMissingProjectDb"/>
/// <seealso cref="DRagLint.CLI.ConsumerDbs.LoadManifestForProject"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ResolveConsumerDbs(const AArgs: TArgs): TArray<string>;

implementation

uses
  System.SysUtils, System.Generics.Collections, Winapi.Windows, System.Classes, System.IOUtils,
  System.NetEncoding, System.DateUtils, System.SyncObjs, System.Math, System.Character, FireDAC.Stan.Async,
  FireDAC.DApt, DRagLint.Storage.FileMembership, DRagLint.Project.Resolver, DRagLint.Index.DbSelect;

function DetectPlatformFromDproj(const AManifest: TIndexManifest; const ACwd: string): string;
var
  Sections  : TArray<TIndexSection>;
  Sec       : TIndexSection        ;
  IncPath   : string               ;
  BestLen   : Integer              ;
  BestInc   : string               ;
  CwdNorm   : string               ;
  IncNorm   : string               ;
  DprojFile : string               ;
  DprojFiles: TArray<string>       ;
  Xml       : string               ;
  P1        : Integer              ;
  P2        : Integer              ;
begin
  Result:= '';
  CwdNorm:= IncludeTrailingPathDelimiter( TPath.GetFullPath(ACwd)).ToLower;
  BestLen:= -1;
  BestInc:= '';

  // Find manifest section whose include is the longest ancestor of ACwd.
  Sections:= AManifest.Sections;
  for Sec in Sections do
  begin
    if SameText(Sec.Source, 'registry-libraries') then Continue;
    for IncPath in Sec.Include do
    begin
      IncNorm:= IncludeTrailingPathDelimiter( TPath.GetFullPath(IncPath)).ToLower;
      if CwdNorm.StartsWith(IncNorm) and (Length(IncNorm) > BestLen) then begin BestLen:= Length(IncNorm); BestInc:= IncPath; end;
    end;
  end;

  if BestInc = '' then Exit;

  // Find first .dproj under that include path (top dir first, then recursive).
  try
    DprojFiles:= TDirectory.GetFiles(BestInc, '*.dproj', TSearchOption.soTopDirectoryOnly);
    if Length(DprojFiles) = 0 then DprojFiles:= TDirectory.GetFiles(BestInc, '*.dproj', TSearchOption.soAllDirectories);
    if Length(DprojFiles) = 0 then Exit;
    DprojFile:= DprojFiles[0];
  except  // dl:ok bare-except@8f3b, try-except-swallowed@8f3b -- REVIEWED 2026-11-19 SLZ-MARK: deliberate: an unreadable dir, file or stamp becomes the empty result or an Exit; best-effort file operation, failure is harmless to the caller
    Exit;
  end;
  Result:= PlatformFromDprojFile(DprojFile);
end; // function DetectPlatformFromDproj

function PlatformFromDprojFile(const ADproj: string): string;
var
  Xml: string ;
  P1 : Integer;
  P2 : Integer;
begin
  Result:= '';
  // Parse <Platform Condition="'$(Platform)'==''">Win64</Platform>
  try
    Xml:= TFile.ReadAllText(ADproj);
  except  // dl:ok try-except-swallowed@8f3b, bare-except@8f3b -- REVIEWED 2026-11-19 SLZ-MARK: best-effort probe or file read with a documented fallback; the handler assigns that fallback or exits, so no result is lost silently
    Exit;
  end;

  // Find <Platform Condition=...>Win64</Platform> ? search for the opening tag
  // directly so we are not confused by attribute quote style.
  P1:= Pos('<Platform Condition=', Xml);
  if P1 = 0 then P1:= Pos('<platform condition=', Xml.ToLower);
  while P1 > 0 do
  begin
    P1:= Pos('>', Xml, P1);
    if P1 = 0 then Break;
    P2:= Pos('<', Xml, P1 + 1);
    if P2 = 0 then Break;
    Result:= Xml.Substring(P1, P2 - P1 - 1).Trim;
    if (Result = 'Win32') or (Result = 'Win64') then Exit;
    Result:= '';
    // Search again from after this element (handles multiple Platform elements).
    P1:= Pos('<Platform Condition=', Xml, P2);
    if P1 = 0 then Break;
  end;
end; // function PlatformFromDprojFile

// v0.45 Task 9: resolve the DB list for consumer commands (query/lsp/serve)
// when the user supplied no --db flags.
// Steps:
//   1. If the user gave --db flags, return those unchanged.
//   2. Otherwise load the manifest, pick platform, call TDbSelect.Resolve,
//      use that list.
//   3. If no manifest is found or the resolved list is empty, fall back to the
//      default .\drag-lint.sqlite so existing behaviour is preserved.
//   4. --project: the list is the project's OWN index (when it exists) plus the
//      platform library, nothing else (owner ruling 2026-08-13; 1.20.4).
/// <summary>Where the local-manifest walk starts for a run.</summary>
/// <param name="AProjectPath">The --project argument, or ''.</param>
/// <returns>The folder of an existing --project file, else the current directory.</returns>
function ManifestStartDir(const AProjectPath: string): string;
begin
  Result:= GetCurrentDir;
  if (AProjectPath <> '') and TFile.Exists(AProjectPath) then
    Result:= ExcludeTrailingPathDelimiter(ExtractFilePath(TPath.GetFullPath(AProjectPath)));
end;

function LoadManifestForProject(const AEngineDir, AProjectPath: string): TIndexManifest;
var
  NoClaimants: TArray<string>;
  NoDb       : string        ;
begin
  Result:= TManifestIO.Load(AEngineDir, ManifestStartDir(AProjectPath));
  if (AProjectPath <> '') and (ManifestStartDir(AProjectPath) <> GetCurrentDir) then
    if ResolveOwnProjectDb(Result, AProjectPath, NoDb, NoClaimants) = pdmNone then
      Result:= TManifestIO.Load(AEngineDir, GetCurrentDir);
end;

var
  GNotedOnce: string = '';

{ True the FIRST time AKey is seen in this process, so a note printed per
  ResolveConsumerDbs call (lint-all calls it repeatedly) appears once. }
function NoteOnce(const AKey: string): Boolean;
begin
  Result:= not GNotedOnce.Contains('|' + LowerCase(AKey) + '|');
  if Result then GNotedOnce:= GNotedOnce + '|' + LowerCase(AKey) + '|';
end;

function ReadPlatformFor(const AManifest: TIndexManifest; const ACheckPlatform, AProjectPath: string): string;
begin
  Result:= ACheckPlatform;
  if Result <> '' then Exit;
  if AProjectPath <> '' then
    try
      Result:= DetectPlatformFromDproj(AManifest, ExtractFilePath(TPath.GetFullPath(AProjectPath)));
    except  // dl:ok bare-except@86a2 -- REVIEWED 2026-11-05 any failure on a bad --project path means "no platform from it"; the cwd and manifest fallbacks below still answer
      Result:= '';
    end;
  if Result = '' then Result:= DetectPlatformFromDproj(AManifest, GetCurrentDir);
  if Result = '' then Result:= AManifest.Settings.DefaultPlatform;
end;

{ C8 (owner override 2026-11-05): the project's own index is missing and the run names the
  project (--project). A verb that needs it builds it fresh at the project's proper path
  (the manifest owner, else <project dir>\_D-RAG\<base>.sqlite) and says so on ONE stderr
  line. NEVER when: --no-create; an explicit --db (ResolveConsumerDbs returned earlier);
  no project file; the servers (lsp, serve); a non-deployed engine (a private copy: not under third_party\dll-win64,
  Program Files or LocalAppData\Programs) or DRAGLINT_NO_AUTOCREATE=1. Two creators must not
  race: an exclusive <db>.creating lock; the loser creates nothing. resolve-dbs never calls this. }
function EngineIsDeployedForCreate: Boolean;
var
  Dir: string;
begin
  if GetEnvironmentVariable('DRAGLINT_NO_AUTOCREATE') = '1' then Exit(False);
  Dir:= LowerCase(ExtractFilePath(ParamStr(0)));
  Result:= Dir.Contains('\third_party\dll-win64\') or Dir.Contains('\program files')
    or Dir.Contains('\appdata\local\programs\');
end;

function TryAcquireCreateLock(const AProjDb, ALockPath: string): TFileStream;
begin
  try
    TDirectory.CreateDirectory(ExtractFilePath(ExpandFileName(AProjDb)));
    Result:= TFileStream.Create(ALockPath, fmCreate or fmShareExclusive);
  except
    on Exception do Result:= nil; { held by another creator, or the folder is not writable }
  end;
end;

procedure AutoCreateMissingProjectDb(const AArgs: TArgs; const AProjDb: string);
var
  Lock: TFileStream;
  LockPath: string;
begin
  { the servers are read-only: opening a file never builds an index }
  if AArgs.NoCreate or (AProjDb = '') or (AArgs.ProjectPath = '') or (AArgs.Command = 'lsp') or (AArgs.Command = 'serve') then Exit;
  if TFile.Exists(AProjDb) or (not TFile.Exists(AArgs.ProjectPath)) then Exit;
  if not EngineIsDeployedForCreate then Exit;
  if not NoteOnce('autocreate|' + ExpandFileName(AProjDb)) then Exit;
  LockPath:= AProjDb + '.creating';
  Lock:= TryAcquireCreateLock(AProjDb, LockPath);
  if Lock = nil then Exit; { another creator holds the lock (or the folder is not writable): create nothing }
  try
    Writeln(ErrOutput, Format('NOTE: the index of %s did not exist; building it now at %s (first use; pass --no-create to skip): drag-lint index --project "%s" --db "%s"',
      [AArgs.ProjectPath, AProjDb, AArgs.ProjectPath, AProjDb]));
    Flush(ErrOutput);
    { 148 IX: a build stopped after the parse wrote the file (the 10-minute child timeout on a large project)
      leaves a HALF index. Say so, or this run and every later one read it as complete.
      Guard: run_autocreate_project_db.ps1 arm M. }
    if not ReindexOwnerProject(AArgs.ProjectPath, AProjDb, 'auto-create') then
      if TFile.Exists(AProjDb) then
        Writeln(ErrOutput, Format('NOTE: building it did not finish; %s is INCOMPLETE and answers short until ' +
          'this completes it: drag-lint index --project "%s" --db "%s"', [AProjDb, AArgs.ProjectPath, AProjDb]))
      else Writeln(ErrOutput, 'NOTE: building it failed; the run continues without the project index.');
  finally
    Lock.Free;
    TFile.Delete(LockPath);
  end;
end;

function ResolveConsumerDbs(const AArgs: TArgs): TArray<string>;
var
  Manifest : TIndexManifest                            ;
  Resolver : DRagLint.Project.Resolver.TProjectResolver;
  EngineDir: string                                    ;
  Platform : string                                    ;
  Resolved : TArray<string>                            ;
  ProjDb   : string                                    ;
  Claimants: TArray<string>                            ;
  LibDbs   : TArray<string>                            ;
  D        : string                                    ;
begin
  // User supplied explicit --db: honour without modification.
  if Length(AArgs.DbPaths) > 0 then begin Result:= AArgs.DbPaths; Exit; end;

  ProjDb   := '';
  Claimants:= nil;
  LibDbs   := nil;
  // Try manifest-driven selection.
  try
    EngineDir:= ExtractFilePath(ParamStr(0));
    { 1.20.4 #4b-2: the local-manifest walk starts at the PROJECT's folder when --project
      names one (as index / refresh-findings do), so a read picks the same DB the write
      did. Conservative: when that manifest has no owner for the project, fall back to the
      old cwd walk, so a cwd-only registration keeps working. }
    Manifest:= LoadManifestForProject(EngineDir, AArgs.ProjectPath);

    { Pick platform: CLI --platform > the PROJECT'S OWN folder when --project
      names one > cwd detection > manifest defaultPlatform. Reading only the cwd
      is how `lint-all --project C:\Projects\YADF\YADF.dproj`, run from this
      repo, took its platform from a directory the project has nothing to do
      with -- and then resolved a foreign index to match. --project is a far
      stronger signal about which project is meant than where the shell
      happens to be standing. }
    Platform:= ReadPlatformFor(Manifest, AArgs.CheckPlatform, AArgs.ProjectPath);


    Resolver:= DRagLint.Project.Resolver.TProjectResolver.Create;
    try
      Resolved:= TDbSelect.Resolve(Manifest, Platform, Resolver, True);
    finally
      Resolver.Free;
    end;

    { The one DB that owns --project: the manifest's exact owner (the same
      ResolveProjectDb the IDE's Rebuild Index and `resolve-dbs --project` use),
      else the project's own _D-RAG default. Two claimants name no owner: a
      guessed owner is worse than none. }
    if AArgs.ProjectPath <> '' then
    begin
      if ResolveOwnProjectDb(Manifest, AArgs.ProjectPath, ProjDb, Claimants) = pdmAmbiguous then ProjDb:= '';
      LibDbs:= LibrarySectionDbs(Manifest);
      AutoCreateMissingProjectDb(AArgs, ProjDb);
    end;
  except
    on E: Exception do
    begin
      // Any manifest parse / IO error: fall through to default -- and say so.
      Resolved:= nil;
      ProjDb  := '';
      LibDbs  := nil;
      Writeln(ErrOutput, Format('NOTE: could not load the manifest (%s: %s); falling back to the default database.',
                                [E.ClassName, E.Message]));
    end;
  end; // try

  if Length(Resolved) > 0 then Result:= Resolved
  else
  begin
    // Fallback: single default DB (preserves pre-Task-9 behaviour).
    Result:= [AArgs.DbPath];
  end;

  { --project: THE PROJECT'S OWN INDEX, THEN THE PLATFORM LIBRARY, AND NOTHING
    ELSE. Owner ruling 2026-08-13: the authoritative set is the platform library
    plus the project DB; every other database -- another project's above all --
    is noise and misleading, for reads as much as for writes.

    This list used to be the manifest's sections with the owner PROMOTED to the
    front and the siblings kept behind it. Consumers take Result[0] as their
    store (lint-all, wiring, exceptions-sync), so an owner-less project then
    opened whichever sibling was declared first; and multi-DB readers (query,
    hover) answered by NAME from every sibling even when the owner was in
    front. Library sections are recognised by section KIND (LibrarySectionDbs),
    not by a file-name prefix.

    With no index of its own (never built, or two sections claim it) only the
    library is left, and that is SAID: an empty answer must not read as a
    clean one. }
  if AArgs.ProjectPath <> '' then
  begin
    var Kept: TArray<string>:= nil;
    if (ProjDb <> '') and TFile.Exists(ProjDb) then Kept:= [ProjDb]
    else if Length(Claimants) > 1 then
    begin
      if NoteOnce('claim|' + ExpandFileName(AArgs.ProjectPath)) then
      Writeln(ErrOutput, Format('NOTE: %d manifest sections claim %s (%s) -- no index owns it, and other ' +
                                'projects'' indexes are not consulted. Fix the manifest or pass --db.',
                                [Length(Claimants), AArgs.ProjectPath, string.Join(', ', Claimants)]));
    end
    else if NoteOnce('noowner|' + ExpandFileName(AArgs.ProjectPath)) then
      Writeln(ErrOutput, Format('NOTE: no index owns %s -- other projects'' indexes are not consulted. ' +
                                'Build it: drag-lint index --project "%s"', [AArgs.ProjectPath, AArgs.ProjectPath]));
    for D in Result do
      if IsLibrarySectionDb(LibDbs, D) and not SameText(ExpandFileName(D), ExpandFileName(ProjDb)) then Kept:= Kept + [D];
    Result:= Kept;
  end;

  { Then reorder by what the indexes ACTUALLY CONTAIN, when this run names a
    target file. `resolve-dbs --in <file>` has answered this correctly all along
    -- DoResolveDbsList calls OrderDbsByMembership -- but the DIAGNOSTIC had the
    ordering and the CONSUMERS did not, so a bare `lint <file>` took Result[0],
    i.e. the manifest's FIRST section, and opened an index that does not hold the
    file. Observed as `index schema v19 < v21` from ORM3's Micronite2027.sqlite
    while linting a YADF unit whose own index was current -- and the quiet form is
    worse than the warning: every store-backed per-file rule and every
    index-dependent autofix (CheckTypeAware, the naming fixes, hover, find-unit)
    silently consults a foreign project's symbols and returns a
    wrong-but-plausible answer.

    Target file resolved with DoLint's own precedence -- positional Path wins,
    else --file/--in -- so the two cannot disagree about which file the run is
    about. OrderDbsByMembership returns its input UNCHANGED when the path is
    empty or when no index contains it, so this is a no-op for the commands that
    name no file (the library-source case included) and for lint-all's directory
    targets. It runs AFTER the --project promotion above deliberately: an explicit
    --project is a stronger statement than membership, and OrderDbsByMembership
    takes ProjDb as its tiebreak, which is what ORM3's shared COMMON\ units need. }
  var TargetFile: string:= AArgs.Path;
  if TargetFile = '' then TargetFile:= AArgs.InFile;
  if TargetFile <> '' then
    Result:= OrderDbsByMembership(Result, ProjDb, TargetFile, DbContainsFile);
end; // function

end.
