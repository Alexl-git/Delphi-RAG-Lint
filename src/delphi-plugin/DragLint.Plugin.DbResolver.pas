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
   files are filtered out. Result is always non-nil but may be empty.

   v0.95+ (Code-Elements-0 fix): the primary DB pick now also probes
   '<projdir>\<projname>.sqlite' (ChangeFileExt of the .dproj) via
   PickProjectDb (DRagLint.Plugin.DbProbe), so a project indexed to the
   PROJECT-NAME file instead of the settings-template file is still found --
   see that unit's DocInsight for the exact resolution order. *)

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
  , DRagLint.Plugin.DbProbe
  , DRagLint.Index.Manifest
  , DragLint.Plugin.ManifestPaths
  ;

{ v(project-scoped): resolves the ACTIVE PROJECT's .dproj to the ONE index DB the
  manifest says owns it, matching the project file EXACTLY (see
  DRagLint.Index.Manifest.ResolveProjectDb). Reads the manifest beside the BPL,
  the same file ManifestDbForFile uses.

  Separate from ManifestDbForFile because the questions differ. That one asks
  "which section covers this FILE" and answers with a folder prefix, which is all
  a .pas can support. This asks "which section IS this project", which a folder
  prefix CANNOT answer once two projects share a directory -- and several now do
  (ORM3\PACKAGE, DataCopy, TableTools, YADF, DragLintGraph\src\pkg).

  Returns pdmNone when no section names the project (INCLUDING when the manifest
  is missing or malformed -- the caller must treat "I could not establish an
  owner" as a refusal, never as permission to guess) and pdmAmbiguous when more
  than one does. Only pdmUnique carries a DB, which may not exist yet: a writer
  legitimately targets a section whose DB has never been built. }
/// <param name="AProjectFile"><!-- drag-lint:auto type -->const string</param>
/// <param name="ADb"><!-- drag-lint:auto type -->out string</param>
/// <param name="AClaimants"><!-- drag-lint:auto type -->out TArray&lt;string&gt;</param>
/// <returns><!-- drag-lint:auto -->TProjectDbMatch -- Observed: pdmNone;
/// ResolveProjectDb(Manifest, AProjectFile, ADb, AClaimants).</returns>
/// <remarks>
/// <!-- drag-lint:auto -->Returns pdmNone when no section names the project (INCLUDING when the
/// manifest is missing or malformed -- the caller must treat "I could not establish an owner" as a
/// refusal, never as permission to guess) and pdmAmbiguous when more than one does. Only pdmUnique
/// carries a DB, which may not exist yet: a writer legitimately targets a section whose DB has
/// never been built.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DragLint.Plugin.DbResolver.ActiveProjectWriteDb (DragLint.Plugin.DbResolver.pas), DragLint.Plugin.DbResolver.ManifestDbForFile (DragLint.Plugin.DbResolver.pas), DragLint.Plugin.Editor.InvokeReindexProject (DragLint.Plugin.Editor.pas), DragLint.Plugin.Editor.ResolvePrimaryIndexDb (DragLint.Plugin.Editor.pas), DragLint.Plugin.LiveDiagnostics.TLiveRunner.OnTick (DragLint.Plugin.LiveDiagnostics.pas)</para>
/// <para>Calls: DRagLint.Index.Manifest.ResolveProjectDb, DragLint.Plugin.DbResolver.TryLoadManifest, DragLint.Plugin.Telemetry.DLT, ExtractFileName, Format</para>
/// <para>Mutates: ADb (out), AClaimants (out)</para>
/// <seealso cref="DRagLint.Index.Manifest.ResolveProjectDb"/>
/// <seealso cref="DragLint.Plugin.DbResolver.TryLoadManifest"/>
/// <seealso cref="DragLint.Plugin.Telemetry.DLT"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ManifestDbForProject(const AProjectFile: string; out ADb: string;
  out AClaimants: TArray<string>): TProjectDbMatch;

{ v(project-scoped): the ordered DB list a READER should open for AEditorFile with
  AActiveProjectFile active -- the active project's section DB first, then the
  folder-matched DB (see DRagLint.Index.Manifest.ResolveReadDbs for why BOTH).
  Empty when the manifest is missing/unreadable or nothing matches. }
/// <param name="AActiveProjectFile"><!-- drag-lint:auto type -->const string</param>
/// <param name="AEditorFile"><!-- drag-lint:auto type -->const string</param>
/// <returns><!-- drag-lint:auto -->TArray&lt;string&gt; -- Observed: nil;
/// ResolveReadDbs(Manifest, AActiveProjectFile, AEditorFile).</returns>
/// <remarks>
/// <!-- drag-lint:auto -->v(project-scoped): the ordered DB list a READER should open for
/// AEditorFile with AActiveProjectFile active -- the active project's section DB first, then the
/// folder-matched DB (see DRagLint.Index.Manifest.ResolveReadDbs for why BOTH). Empty when the
/// manifest is missing/unreadable or nothing matches.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DragLint.Plugin.DbResolver.ResolveActiveIndexDbs (DragLint.Plugin.DbResolver.pas)</para>
/// <para>Calls: DRagLint.Index.Manifest.ResolveReadDbs, DragLint.Plugin.DbResolver.TryLoadManifest, DragLint.Plugin.Telemetry.DLT, ExtractFileName, Format</para>
/// <seealso cref="DRagLint.Index.Manifest.ResolveReadDbs"/>
/// <seealso cref="DragLint.Plugin.DbResolver.TryLoadManifest"/>
/// <seealso cref="DragLint.Plugin.Telemetry.DLT"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ManifestReadDbs(const AActiveProjectFile, AEditorFile: string): TArray<string>;

{ The manifest this BPL actually reads. Exposed for DIAGNOSTICS: when a project
  resolves to no section, the manifest path is half the answer -- in a design-time
  package GetModuleName(HInstance) is the BPL's OWN directory, so this is the
  win32 copy, not the one beside the engine exe. Naming it in the failure message
  is what makes a manifest desync self-evident instead of mysterious. }
/// <summary><!-- drag-lint:auto sum -->The manifest this BPL actually reads. Exposed for
/// DIAGNOSTICS: when a project resolves to no section, the manifest path is half the
/// answer -- in a design-time package GetModuleName(HInstance) is the BPL's OWN
/// directory, so this is the win32 copy, not the one beside the engine exe. Naming it in
/// the failure message is what makes a manifest desync self-evident instead of
/// mysterious.</summary>
/// <returns>The file TInstalledLayout.ManifestLocation answers for the BPL folder (layout v2
/// phase 3): DRAGLINT_MANIFEST, else under DRAGLINT_LAYOUT=v2 the roaming file when it exists,
/// else drag-lint.json in the BPL folder (the only answer before phase 3).</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DragLint.Plugin.DbResolver.ManifestLibraryDbFor (DragLint.Plugin.DbResolver.pas), DragLint.Plugin.DbResolver.TryLoadManifest (DragLint.Plugin.DbResolver.pas), DragLint.Plugin.Diagnose.DiagConfiguration (DragLint.Plugin.Diagnose.pas), DragLint.Plugin.Editor.InvokeReindexProject (DragLint.Plugin.Editor.pas)</para>
/// <para>Calls: ExtractFilePath, GetModuleName</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ManifestPathBesideEngine: string;

{ v0.46: returns the manifest section DB whose include folder is an ancestor of
  AFilePath (longest/most-specific match wins), or '' when there is no manifest
  beside the engine or no covering section. This is the SAME clean DB the
  manifest builds (e.g. ...\ORM3\drag-lint.sqlite for any ORM3 file), so the
  plugin stops reading stale per-.dproj DBs. Used by both the read side
  (ResolveActiveIndexDbs) and the write side (ProjectNotifier auto-index). }
/// <summary><!-- drag-lint:auto sum -->v0.46: returns the manifest section DB whose
/// include folder is an ancestor of AFilePath (longest/most-specific match wins), or ''
/// when there is no manifest beside the engine or no covering section. This is the SAME
/// clean DB the manifest builds (e.g. ...\ORM3\drag-lint.sqlite for any ORM3 file), so
/// the plugin stops reading stale per-.dproj DBs. Used by both the read side
/// (ResolveActiveIndexDbs) and the write side (ProjectNotifier auto-index).</summary>
/// <param name="AFilePath"><!-- drag-lint:auto type -->const string</param>
/// <returns><!-- drag-lint:auto -->string -- Observed: ''; ResolveFolderDb(Manifest,
/// AFilePath).</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DragLint.Plugin.Editor.InvokeLintAll (DragLint.Plugin.Editor.pas), DragLint.Plugin.Editor.ResolvePrimaryIndexDb (DragLint.Plugin.Editor.pas), DragLint.Plugin.LiveDiagnostics.TLintDiagnosticProvider.GetDiagnostics (DragLint.Plugin.LiveDiagnostics.pas), DragLint.Plugin.ProjectNotifier.TDragLintProjectNotifier.FileNotification (DragLint.Plugin.ProjectNotifier.pas), DragLint.Plugin.SaveNotifier.TDragLintSaveNotifier.AfterSave (DragLint.Plugin.SaveNotifier.pas)</para>
/// <para>Calls: DRagLint.Index.Manifest.ResolveFolderDb, DragLint.Plugin.DbResolver.ManifestDbForProject, DragLint.Plugin.DbResolver.TryLoadManifest, ExtractFileExt, SameText</para>
/// <seealso cref="DRagLint.Index.Manifest.ResolveFolderDb"/>
/// <seealso cref="DragLint.Plugin.DbResolver.ManifestDbForProject"/>
/// <seealso cref="DragLint.Plugin.DbResolver.TryLoadManifest"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ManifestDbForFile(const AFilePath: string): string;

{ Returns the absolute path to the .dproj that owns the file currently
  active in the editor. Walks up the directory tree from the file's
  parent looking for any .dproj; the first one found wins. Empty if
  there's no active editor file or no .dproj anywhere above it. }
/// <summary><!-- drag-lint:auto sum -->Returns the absolute path to the .dproj that owns
/// the file currently active in the editor. Walks up the directory tree from the file's
/// parent looking for any .dproj; the first one found wins. Empty if there's no active
/// editor file or no .dproj anywhere above it.</summary>
/// <param name="AFilePath"><!-- drag-lint:auto type -->const string</param>
/// <returns><!-- drag-lint:auto -->string -- Observed: ''; Files[0].</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DragLint.Plugin.DbResolver.ResolveActiveIndexDbs (DragLint.Plugin.DbResolver.pas), DragLint.Plugin.DbResolver.ResolverDiagnostic (DragLint.Plugin.DbResolver.pas)</para>
/// <para>Calls: ExcludeTrailingPathDelimiter, ExtractFileDir, ExtractFilePath, SameText</para>
/// <para>Touches: file system</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function FindOwningProject(const AFilePath: string): string;

{ Returns the absolute path of the active editor's file, or '' if none. }
/// <summary><!-- drag-lint:auto sum -->Returns the absolute path of the active editor's
/// file, or '' if none.</summary>
/// <returns><!-- drag-lint:auto -->string -- Observed: ''; EV.Buffer.FileName.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DragLint.Plugin.DbResolver.ResolveActiveIndexDbs (DragLint.Plugin.DbResolver.pas), DragLint.Plugin.DbResolver.ResolverDiagnostic (DragLint.Plugin.DbResolver.pas), DragLint.Plugin.Editor.ResolvePrimaryIndexDb (DragLint.Plugin.Editor.pas), DragLint.Plugin.UsesDepsFrame.ResolveScope (DragLint.Plugin.UsesDepsFrame.pas)</para>
/// <para>Calls: Supports</para>
/// <para>Catches: Exception (swallowed)</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function GetActiveEditorFilePath: string;

{ The .dproj of the project group's ACTIVE project, or '' if none. Exposed
  because it is the tiebreak every project-scoped resolution needs, and callers
  outside this unit were otherwise reaching for FindOwningProject -- which
  returns the FIRST .dproj in a directory and is therefore the wrong answer in
  exactly the shared-folder case that matters. }
/// <summary><!-- drag-lint:auto sum -->The .dproj of the project group's ACTIVE project,
/// or '' if none. Exposed because it is the tiebreak every project-scoped resolution
/// needs, and callers outside this unit were otherwise reaching for FindOwningProject --
/// which returns the FIRST .dproj in a directory and is therefore the wrong answer in
/// exactly the shared-folder case that matters.</summary>
/// <returns><!-- drag-lint:auto -->string -- Observed: ''; ActiveProj.FileName.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DragLint.Plugin.DbResolver.ActiveProjectWriteDb (DragLint.Plugin.DbResolver.pas), DragLint.Plugin.DbResolver.ResolveActiveIndexDbs (DragLint.Plugin.DbResolver.pas), DragLint.Plugin.DbResolver.ResolverDiagnostic (DragLint.Plugin.DbResolver.pas), DragLint.Plugin.Diagnose.DiagIndexes (DragLint.Plugin.Diagnose.pas), DragLint.Plugin.FanOut.BuildContext (DragLint.Plugin.FanOut.pas) (+3 more)</para>
/// <para>Calls: Supports</para>
/// <para>Catches: Exception (swallowed)</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function GetActiveProjectFilePath: string;

/// <summary>The ONE database a WRITE for the active project may target: the
/// manifest's unique owner of GetActiveProjectFilePath.</summary>
/// <param name="AProjectFile">Receives the active project's file ('' when none).</param>
/// <param name="AWhy">Receives why no DB may be written ('' on success).</param>
/// <returns>The owner DB, or '' -- the caller then writes NOTHING and logs AWhy.</returns>
/// <remarks>
/// Replaces GLastProjectDb (the last project OPENED), which paired the
/// active project with another project's DB on 2026-10-16. The decision itself
/// is IndexJob.ReindexTargetDb, which tests\IndexJobTests.dpr covers. Main
/// thread only (OTAPI).
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DragLint.Plugin.SaveNotifier.QueueReindexJob (DragLint.Plugin.SaveNotifier.pas), DragLint.Plugin.StructureForm.TDragLintStructureForm.FixItClick (DragLint.Plugin.StructureForm.pas), DragLint.Plugin.StructureForm.TDragLintStructureForm.NodeIsFixableFinding (DragLint.Plugin.StructureForm.pas), DragLint.Plugin.StructureForm.TDragLintStructureForm.RunCycleFix (DragLint.Plugin.StructureForm.pas)</para>
/// <para>Calls: DragLint.Plugin.DbResolver.GetActiveProjectFilePath, DragLint.Plugin.DbResolver.ManifestDbForProject, DragLint.Plugin.IndexJob.ReindexTargetDb</para>
/// <para>Returns: ReindexTargetDb(AProjectFile, Match, OwnerDb, AWhy)</para>
/// <para>Mutates: AProjectFile (out)</para>
/// <seealso cref="DragLint.Plugin.DbResolver.GetActiveProjectFilePath"/>
/// <seealso cref="DragLint.Plugin.DbResolver.ManifestDbForProject"/>
/// <seealso cref="DragLint.Plugin.IndexJob.ReindexTargetDb"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ActiveProjectWriteDb(out AProjectFile, AWhy: string): string;
{ Returns the primary DB path for an arbitrary .dproj (or '' for none).
  Uses the template from Settings. Result may point at a file that does
  not yet exist. }
/// <summary><!-- drag-lint:auto sum -->Returns the primary DB path for an arbitrary
/// .dproj (or '' for none). Uses the template from Settings. Result may point at a file
/// that does not yet exist.</summary>
/// <param name="AProjPath"><!-- drag-lint:auto type -->const string</param>
/// <param name="ASettings"><!-- drag-lint:auto type -->const TDragLintSettings</param>
/// <returns><!-- drag-lint:auto -->string -- Observed: '';
/// ResolveDbPath(ASettings.DbPathTemplate, ProjDir, ProjName).</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Calls: ChangeFileExt, DragLint.Plugin.Settings.ResolveDbPath, ExtractFileName, ExtractFilePath</para>
/// <seealso cref="DragLint.Plugin.Settings.ResolveDbPath"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function PrimaryDbForProject(const AProjPath: string; const ASettings: TDragLintSettings): string;

{ The headline function: returns ALL DBs the plugin should query for the
  currently-active editor file, in priority order. Empty paths and
  non-existent files are filtered. Duplicates removed. }
/// <param name="ASettings"><!-- drag-lint:auto type -->const TDragLintSettings</param>
/// <returns><!-- drag-lint:auto type -->TArray&lt;string&gt;</returns>
/// <remarks>
/// <!-- drag-lint:auto -->The headline function: returns ALL DBs the plugin should query for the
/// currently-active editor file, in priority order. Empty paths and non-existent files are
/// filtered. Duplicates removed.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DragLint.Plugin.Diagnose.DiagConnections (DragLint.Plugin.Diagnose.pas), DragLint.Plugin.Diagnose.DiagIndexes (DragLint.Plugin.Diagnose.pas), DragLint.Plugin.Diagnose.RefreshEngineInfo (DragLint.Plugin.Diagnose.pas), DragLint.Plugin.Editor.EnsureLspClient (DragLint.Plugin.Editor.pas), DragLint.Plugin.Editor.InvokeFindUsages (DragLint.Plugin.Editor.pas) (+10 more)</para>
/// <para>Calls: DRagLint.Plugin.DbProbe.PickProjectDb, DragLint.Plugin.DbResolver.AddUnique, DragLint.Plugin.DbResolver.DiscoverSiblings, DragLint.Plugin.DbResolver.FindAncestorDb, DragLint.Plugin.DbResolver.FindOwningProject, DragLint.Plugin.DbResolver.GetActiveEditorFilePath, DragLint.Plugin.DbResolver.GetActiveProjectFilePath, DragLint.Plugin.DbResolver.GetPlatformAwareLibraryDbPath, DragLint.Plugin.DbResolver.ManifestReadDbs, DragLint.Plugin.Telemetry.DLT, ExtractFileName, ExtractFilePath, Format, Pos</para>
/// <para>Complexity: 19 (cyclomatic, outer body), 138 lines (full implementation)</para>
/// <para>Touches: file system</para>
/// <seealso cref="DRagLint.Plugin.DbProbe.PickProjectDb"/>
/// <seealso cref="DragLint.Plugin.DbResolver.AddUnique"/>
/// <seealso cref="DragLint.Plugin.DbResolver.DiscoverSiblings"/>
/// <seealso cref="DragLint.Plugin.DbResolver.FindAncestorDb"/>
/// <seealso cref="DragLint.Plugin.DbResolver.FindOwningProject"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ResolveActiveIndexDbs(const ASettings: TDragLintSettings): TArray<string>;

{ v0.40.5: exposed for the Find Usages debug panel. Returns a multi-line
  diagnostic string showing exactly what the resolver saw and decided. }
/// <summary><!-- drag-lint:auto sum -->v0.40.5: exposed for the Find Usages debug panel.
/// Returns a multi-line diagnostic string showing exactly what the resolver saw and
/// decided.</summary>
/// <param name="ASettings"><!-- drag-lint:auto type -->const TDragLintSettings</param>
/// <returns><!-- drag-lint:auto -->string -- Observed: SB.ToString.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Calls: BoolToStr, DRagLint.Plugin.DbProbe.PickProjectDb, DragLint.Plugin.DbResolver.FindAncestorDb, DragLint.Plugin.DbResolver.FindOwningProject, DragLint.Plugin.DbResolver.GetActiveEditorFilePath, DragLint.Plugin.DbResolver.GetActiveProjectFilePath, ExtractFilePath</para>
/// <para>Touches: file system</para>
/// <seealso cref="DRagLint.Plugin.DbProbe.PickProjectDb"/>
/// <seealso cref="DragLint.Plugin.DbResolver.FindAncestorDb"/>
/// <seealso cref="DragLint.Plugin.DbResolver.FindOwningProject"/>
/// <seealso cref="DragLint.Plugin.DbResolver.GetActiveEditorFilePath"/>
/// <seealso cref="DragLint.Plugin.DbResolver.GetActiveProjectFilePath"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ResolverDiagnostic(const ASettings: TDragLintSettings): string;

/// <summary>Path to the library index for the ACTIVE project's platform
/// (library-&lt;platform&gt;.sqlite under the manifest outDir), falling back to a
/// BPL-relative Win32/Win64/legacy probe.</summary>
/// <param name="ASettings">Plugin settings; ExePath locates drag-lint.json.</param>
/// <returns>Absolute path to the best available library DB; may not exist.</returns>
/// <remarks>
/// Exposed so menu commands can pass it to lint-all as the SECOND
/// --db. Without it used-unit-not-resolvable has no library source and flags
/// every third-party and RTL unit the project legitimately uses.
/// Not thread-safe; call from the main thread only.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DragLint.Plugin.DbResolver.ResolveActiveIndexDbs (DragLint.Plugin.DbResolver.pas), DragLint.Plugin.Editor.DLLibraryDb (DragLint.Plugin.Editor.pas), DragLint.Plugin.Editor.InvokeLintAll (DragLint.Plugin.Editor.pas)</para>
/// <para>Calls: DragLint.Plugin.DbResolver.GetPlatformAwareLibraryDbPathEx</para>
/// <para>Returns: GetPlatformAwareLibraryDbPathEx(ASettings, Ignored)</para>
/// <seealso cref="DragLint.Plugin.DbResolver.GetPlatformAwareLibraryDbPathEx"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function GetPlatformAwareLibraryDbPath(const ASettings: TDragLintSettings): string;

/// <summary>As <c>GetPlatformAwareLibraryDbPath</c>, but also reports WHICH rule
/// produced the path -- a manifest hit, or the precise reason the manifest branch
/// declined and the BPL-relative probe answered instead.</summary>
/// <param name="ASettings">Plugin settings; ExePath locates drag-lint.json.</param>
/// <param name="AReason">Receives a short one-line provenance string. Never empty.</param>
/// <returns>Absolute path to the best available library DB; may not exist.</returns>
/// <remarks>
/// Exists because the plain function fell back through four separate
/// exits without recording any of them, so an IDE resolving RTL/VCL against a
/// months-old index looked exactly like one resolving correctly. That cost a day
/// of misdirected debugging on 2026-08-17. Diagnostics render AReason verbatim.
/// Not thread-safe; call from the main thread only.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DragLint.Plugin.DbResolver.GetPlatformAwareLibraryDbPath (DragLint.Plugin.DbResolver.pas), DragLint.Plugin.Diagnose.DiagIndexes (DragLint.Plugin.Diagnose.pas), DragLint.Plugin.Diagnose.RefreshEngineInfo (DragLint.Plugin.Diagnose.pas)</para>
/// <para>Calls: DragLint.Plugin.DbResolver.GetLibraryDbPathEx, DragLint.Plugin.DbResolver.ManifestLibraryDbFor, DragLint.Plugin.Telemetry.DLT</para>
/// <para>Returns: ManifestLibraryDbFor(ASettings, '', AReason, Declined); GetLibraryDbPathEx(AReason)</para>
/// <para>Mutates: AReason (out)</para>
/// <seealso cref="DragLint.Plugin.DbResolver.GetLibraryDbPathEx"/>
/// <seealso cref="DragLint.Plugin.DbResolver.ManifestLibraryDbFor"/>
/// <seealso cref="DragLint.Plugin.Telemetry.DLT"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function GetPlatformAwareLibraryDbPathEx(const ASettings: TDragLintSettings;
  out AReason: string): string;

/// <summary>The BPL-relative library probe (library-Win32, then library-Win64,
/// then the legacy merged drag-lint-library), reporting which rung answered.</summary>
/// <param name="AReason">Receives the rung that matched, or a not-found note.</param>
/// <returns>First existing candidate, else the legacy path even though absent.</returns>
/// <remarks>
/// Not thread-safe; call from the main thread only.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DragLint.Plugin.DbResolver.GetLibraryDbPath (DragLint.Plugin.DbResolver.pas), DragLint.Plugin.DbResolver.GetPlatformAwareLibraryDbPathEx (DragLint.Plugin.DbResolver.pas)</para>
/// <para>Calls: ExtractFileName, ExtractFilePath, GetModuleName, SameText</para>
/// <para>Returns: C; Dir + 'drag-lint-library.sqlite'</para>
/// <para>Mutates: AReason (out)</para>
/// <para>Touches: file system</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function GetLibraryDbPathEx(out AReason: string): string;

/// <summary>The active project's target platform via OTAPI (e.g. 'Win32').</summary>
/// <returns>Platform name, or '' when not determinable (no project, non-IDE host).</returns>
/// <remarks>
/// Exposed 2026-08-17 for the diagnose report, which must show the
/// platform the library index is being selected FOR. Deliberately shared rather
/// than copied a third time -- Editor.pas already carries its own
/// GetActiveProjectPlatform. Not thread-safe; call from the main thread only.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DragLint.Plugin.DbResolver.ManifestLibraryDbFor (DragLint.Plugin.DbResolver.pas), DragLint.Plugin.Diagnose.DiagIndexes (DragLint.Plugin.Diagnose.pas), DragLint.Plugin.Editor.InvokeCircularUsesFix (DragLint.Plugin.Editor.pas), DragLint.Plugin.FanOut.BuildContext (DragLint.Plugin.FanOut.pas), DragLint.Plugin.SaveNotifier.QueueReindexJob (DragLint.Plugin.SaveNotifier.pas) (+4 more)</para>
/// <para>Calls: Supports</para>
/// <para>Returns: ''; P</para>
/// <para>Catches: Exception (empty)</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function GetActivePlatformForLibrary: string;

/// <summary>Records this install's library index per platform (Win32, Win64) in the central
/// settings file %LOCALAPPDATA%\drag-lint\context-defaults.json (key "libraries.&lt;Platform&gt;.libraryDb"),
/// where the LSP and other readers fall back to it when a project names no library DB.</summary>
/// <remarks>
/// Called once at IDE start (Register); loads the plugin settings itself (ExePath locates
/// the engine's drag-lint.json). Only a library DB that EXISTS under the manifest
/// outDir is written; other keys and a platform's libraryRoots are preserved; a malformed file is
/// left alone; an unchanged value is not rewritten. Never raises: every outcome goes to the
/// plugin log (category ctxdefaults). Main thread only.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DragLint.Plugin.Wizard.Register (DragLint.Plugin.Wizard.pas)</para>
/// <para>Calls: DRagLint.Core.ContextDefaults.ContextDefaultsFile, DRagLint.Core.ContextDefaults.MergeLibraryDefault, DragLint.Plugin.DbResolver.ManifestLibraryDbFor, DragLint.Plugin.Settings.LoadSettings, DragLint.Plugin.Telemetry.DLT</para>
/// <para>Catches: Exception (swallowed)</para>
/// <seealso cref="DRagLint.Core.ContextDefaults.ContextDefaultsFile"/>
/// <seealso cref="DRagLint.Core.ContextDefaults.MergeLibraryDefault"/>
/// <seealso cref="DragLint.Plugin.DbResolver.ManifestLibraryDbFor"/>
/// <seealso cref="DragLint.Plugin.Settings.LoadSettings"/>
/// <seealso cref="DragLint.Plugin.Telemetry.DLT"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure PublishLibraryDefaults;

implementation

uses
  DragLint.Plugin.IndexJob
  , DRagLint.Core.ContextDefaults
  ;

function ActiveProjectWriteDb(out AProjectFile, AWhy: string): string;
var
  OwnerDb  : string;
  Claimants: TArray<string>;
  Match    : TProjectDbMatch;
begin
  AProjectFile:= GetActiveProjectFilePath;
  OwnerDb     := '';
  Match       := pdmNone;
  if AProjectFile <> '' then Match:= ManifestDbForProject(AProjectFile, OwnerDb, Claimants);
  Result:= ReindexTargetDb(AProjectFile, Match, OwnerDb, AWhy);
end; // function
function ManifestPathBesideEngine: string;
begin
  Result:= PluginManifestIn(ExtractFilePath(GetModuleName(HInstance))).Path;
end;

{ Loads + parses the manifest beside the BPL. Returns False when it is absent or
  unparseable -- never raises, and never silently: the telemetry line is the only
  place the reason survives, because a design-time package has nowhere to print.
  Every caller treats False as "no owner could be established", which is the safe
  reading on both the read and the write path. }
function TryLoadManifest(out AManifest: TIndexManifest): Boolean;
var
  MPath  : string;
  Content: string;
  Located: TManifestLocation;
begin
  Result   := False;
  AManifest:= Default(TIndexManifest);
  Located  := PluginManifestIn(ExtractFilePath(GetModuleName(HInstance)));
  MPath    := Located.Path;
  if not TFile.Exists(MPath) then
  begin
    DLT('dbresolve', 'NO MANIFEST at ' + MPath);
    Exit;
  end;
  try
    Content  := TFile.ReadAllText(MPath);
    AManifest:= TManifestIO.ParseText(Content, Located.RootDir);
    Result   := True;
  except
    on E: Exception do
      DLT('dbresolve', Format('manifest UNREADABLE (%s): %s: %s', [MPath, E.ClassName, E.Message]));
  end; // try
end; // function

function ManifestDbForProject(const AProjectFile: string; out ADb: string;
  out AClaimants: TArray<string>): TProjectDbMatch;
var
  Manifest: TIndexManifest;
begin
  ADb       := '';
  AClaimants:= nil;
  Result    := pdmNone;
  if AProjectFile = '' then Exit;
  if not TryLoadManifest(Manifest) then Exit;

  Result:= ResolveProjectDb(Manifest, AProjectFile, ADb, AClaimants);
  DLT('dbresolve', Format('project resolve: %s -> match=%d db=%s claimants=%d',
                          [ExtractFileName(AProjectFile), Ord(Result), ADb, Length(AClaimants)]));
end; // function

function ManifestReadDbs(const AActiveProjectFile, AEditorFile: string): TArray<string>;
var
  Manifest: TIndexManifest;
begin
  Result:= nil;
  if not TryLoadManifest(Manifest) then Exit;
  Result:= ResolveReadDbs(Manifest, AActiveProjectFile, AEditorFile);
  DLT('dbresolve', Format('read resolve: proj=%s file=%s -> %d db(s)',
                          [ExtractFileName(AActiveProjectFile), ExtractFileName(AEditorFile), Length(Result)]));
end; // function

function ManifestDbForFile(const AFilePath: string): string;
var
  Manifest: TIndexManifest;
begin
  Result:= '';
  if AFilePath = '' then Exit;

  { v(project-scoped): when handed a PROJECT FILE, the manifest can answer
    exactly, so ask that way first -- folding a .dproj down to its folder throws
    away the only thing that distinguishes it from its siblings. Falls through to
    the folder walk below on anything other than a single unambiguous owner, so
    genuine FOLDER sections (Library, SQL, a whole-tree union) and every ordinary
    .pas lookup behave exactly as before.

    An AMBIGUOUS project deliberately falls through rather than returning '':
    this is the READ path (hover, Find Usages), where a slightly-too-broad DB is
    a cosmetic problem. The WRITE path must not be so relaxed -- see
    ManifestDbForProject's callers, which refuse. }
  var PExt: string:= ExtractFileExt(AFilePath);
  if SameText(PExt, '.dproj') or SameText(PExt, '.dpr') then
  begin
    var PDb: string:= '';
    var PClaimants: TArray<string>:= nil;
    if ManifestDbForProject(AFilePath, PDb, PClaimants) = pdmUnique then Exit(PDb);
  end;

  { The folder walk itself now lives in DRagLint.Index.Manifest.ResolveFolderDb.
    It used to be a hand-rolled TJSONObject traversal here -- a SECOND copy of
    logic the engine already had, which is how the two drifted into disagreeing
    about which section covers a file. One implementation, and it is the one the
    headless tests exercise. }
  if not TryLoadManifest(Manifest) then Exit;
  Result:= ResolveFolderDb(Manifest, AFilePath);
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
  ProjDir : string;
  ProjName: string;
begin
  Result:= '';
  if AProjPath = '' then Exit;
  ProjDir := ExtractFilePath(AProjPath);
  ProjName:= ChangeFileExt(ExtractFileName(AProjPath), '');
  Result  := ResolveDbPath(ASettings.DbPathTemplate, ProjDir, ProjName);
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
    SiblingDb:= ResolveDbPath(ASettings.DbPathTemplate, Sub, ChangeFileExt(ExtractFileName(ProjFiles[0]), ''));
    if TFile.Exists(SiblingDb) then AddUnique(ADbs, SiblingDb);
  end;
end; // procedure

function GetLibraryDbPathEx(out AReason: string): string;
{ v0.46: the v0.45 manifest renamed library DBs to library-<platform>.sqlite.
  Prefer a fresh per-platform DB deployed beside the BPL (Win32 is the manifest
  default platform, then Win64), but fall back to the legacy merged
  drag-lint-library.sqlite -- still a complete all-platform symbol set for
  "which unit declares X" -- so existing installs keep working.

  2026-08-17: the legacy rung is the one that BIT. On this box neither
  per-platform file was deployed beside the BPL, so every caller silently landed
  on a 1.5 GB pre-2026-08-11 leftover and answered from it with full confidence.
  The rung that matched is now reported, because "which library index am I
  actually using" turned out to be the single question nobody could answer. }
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
    if TFile.Exists(C) then
    begin
      if SameText(ExtractFileName(C), 'drag-lint-library.sqlite') then
        AReason:= 'BPL-relative LEGACY probe (drag-lint-library.sqlite) -- no per-platform index is deployed beside the BPL'
      else
        AReason:= 'BPL-relative probe: ' + ExtractFileName(C);
      Exit(C);
    end;
  AReason:= 'NO library index found -- neither the manifest nor any BPL-relative candidate exists';
  Result:= Dir + 'drag-lint-library.sqlite'; { legacy default even if absent }
end;

function GetLibraryDbPath: string;
var
  Ignored: string;
begin
  Result:= GetLibraryDbPathEx(Ignored);
end;

{ Implementation of the interface-declared GetActivePlatformForLibrary. Still
  duplicates Editor.GetActiveProjectPlatform, which cannot be reused here without
  a circular unit dependency (Editor already uses DbResolver). }
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

function ManifestLibraryDbFor(const ASettings: TDragLintSettings;
  const APlatform: string; out AReason, ADeclined: string): string;
{ 2026-08-17: this lookup used to `Exit` or fall through at FOUR points --
  manifest absent, manifest unparseable, outDir missing, per-platform file
  absent -- and recorded none of them. The result was an IDE quietly resolving
  RTL/VCL against a stale index, indistinguishable from a healthy one. Every
  decline now names itself in ADeclined, and the manifest beside the BPL is tried
  as well as the one beside the engine: a normal install has TWO copies of
  drag-lint.json and nothing keeps them in step, so probing only one turns an
  ordinary desync into a silent downgrade.
  2026-10-28: split out of GetPlatformAwareLibraryDbPathEx so PublishLibraryDefaults
  can ask for Win32 and Win64 explicitly; APlatform = '' keeps the old
  active-platform-else-Win64 behaviour. }
var
  MPath     : string        ;
  Content   : string        ;
  OutDir    : string        ;
  LibPlat   : string        ;
  Db        : string        ;
  RootVal   : TJSONValue    ;
  IdxVal    : TJSONValue    ;
  OutDirVal : TJSONValue    ;
  Manifests : TArray<string>;

  procedure Decline(const AWhy: string);
  begin
    if ADeclined <> '' then ADeclined:= ADeclined + '; ';
    ADeclined:= ADeclined + AWhy;
  end;

begin
  Result   := '';
  AReason  := '';
  ADeclined:= '';

  { The engine's manifest first (it is the one that actually builds the indexes),
    then the BPL's. Duplicates are harmless -- the loop stops at the first hit. }
  Manifests:= PluginManifestCandidates(ASettings.ExePath, ExtractFilePath(GetModuleName(HInstance)));

  for MPath in Manifests do
  begin
    try
      if not TFile.Exists(MPath) then
      begin
        Decline('no manifest at ' + MPath);
        Continue;
      end;

      Content:= TFile.ReadAllText(MPath);
      OutDir := '';
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

      OutDir:= PluginLibraryOutDir(OutDir, MPath);
      if OutDir = '' then
      begin
        Decline('manifest ' + MPath + ' has no indexes.outDir');
        Continue;
      end;

      LibPlat:= APlatform;
      if LibPlat = '' then LibPlat:= GetActivePlatformForLibrary;
      if LibPlat = '' then
      begin
        LibPlat:= 'Win64';
        Decline('active platform unknown, assumed Win64');
      end;

      Db:= TPath.Combine(OutDir, 'library-' + LibPlat + '.sqlite');
      if TFile.Exists(Db) then
      begin
        AReason:= Format('manifest %s -> outDir %s, platform %s', [MPath, OutDir, LibPlat]);
        Exit(Db);
      end;
      Decline(Format('outDir %s has no library-%s.sqlite', [OutDir, LibPlat]));
    except
      on E: Exception do Decline(Format('%s reading %s: %s', [E.ClassName, MPath, E.Message]));
    end; // try
  end; // for
end; // function

function GetPlatformAwareLibraryDbPathEx(const ASettings: TDragLintSettings;
  out AReason: string): string;
var
  Declined: string;
begin
  Result:= ManifestLibraryDbFor(ASettings, '', AReason, Declined);
  if Result <> '' then
  begin
    DLT('dbresolve', 'library: ' + AReason + ' => ' + Result);
    Exit;
  end;
  Result := GetLibraryDbPathEx(AReason);
  AReason:= AReason + ' (manifest declined: ' + Declined + ')';
  DLT('dbresolve', 'library FALLBACK: ' + AReason + ' => ' + Result);
end; // function

procedure PublishLibraryDefaults;
const
  PLATFORMS: array[0..1] of string = ('Win32', 'Win64');
var
  P       : string;
  Db      : string;
  Reason  : string;
  Declined: string;
  Target  : string;
  Settings: TDragLintSettings;
begin
  try
    Settings:= LoadSettings;
  except
    on E: Exception do
    begin
      DLT('ctxdefaults', 'skipped: settings unreadable: ' + E.ClassName + ': ' + E.Message);
      Exit;
    end;
  end; // try
  Target:= ContextDefaultsFile;
  if Target = '' then
  begin
    DLT('ctxdefaults', 'skipped: LOCALAPPDATA not set');
    Exit;
  end;
  for P in PLATFORMS do
    try
      Db:= ManifestLibraryDbFor(Settings, P, Reason, Declined);
      if Db = '' then
        DLT('ctxdefaults', P + ': no library index (' + Declined + ')')
      else if MergeLibraryDefault(Target, P, Db) then
        DLT('ctxdefaults', P + ': wrote ' + Db + ' to ' + Target)
      else
        DLT('ctxdefaults', P + ': unchanged or file not writable as JSON (' + Target + ')');
    except
      on E: Exception do DLT('ctxdefaults', P + ': ' + E.ClassName + ': ' + E.Message);
    end; // try
end; // procedure

function GetPlatformAwareLibraryDbPath(
  const ASettings: TDragLintSettings): string;
var
  Ignored: string;
begin
  Result:= GetPlatformAwareLibraryDbPathEx(ASettings, Ignored);
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
  pattern but their actual DB lives at 'drag-lint.sqlite'. v(project-drag-
  lint-home): the canonical default is ALSO the pre-relocation flat path
  (it predates the move into a project's _D-RAG folder), so this same
  candidate doubles as the fallback that keeps an IDE whose registry still
  holds the pre-relocation template finding an un-migrated DB. }
const
  CANONICAL_TEMPLATE = '<projdir>\drag-lint.sqlite';
var
  Dir       : string        ;
  DirName   : string        ;
  Parent    : string        ;
  Candidates: TArray<string>;
  C         : string        ;
begin
  Result:= '';
  Dir:= ExcludeTrailingPathDelimiter(AStartDir);
  while (Dir <> '') and TDirectory.Exists(Dir) do
  begin
    DirName:= ExtractFileName(Dir); // heuristic <projname> when no .dproj is known at this level
    SetLength(Candidates, 0);
    if ASettings.DbPathTemplate <> '' then
    begin
      SetLength(Candidates, 1);
      Candidates[0]:= ResolveDbPath(ASettings.DbPathTemplate, Dir, DirName);
    end;
    { Always also try the canonical default (in case the user's template
      is misconfigured or legacy). No <projname> substitution -- this is the
      pre-relocation flat filename, which never had one. }
    SetLength(Candidates, Length(Candidates) + 1);
    Candidates[High(Candidates)]:= ResolveDbPath(CANONICAL_TEMPLATE, Dir);

    { v0.95+ Code-Elements-0 fix: also try the project-name file at this
      level (<dirname>.sqlite), matching PickProjectDb's by-name candidate
      so an ancestor DB named after its own directory is found on the walk-up. }
    SetLength(Candidates, Length(Candidates) + 1);
    Candidates[High(Candidates)]:= IncludeTrailingPathDelimiter(Dir) + DirName + '.sqlite';

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
    PrimaryDb:= PickProjectDb(ProjPath, ASettings); // template-first, then <projname>.sqlite
    SB.AppendLine('PrimaryDb: "' + PrimaryDb + '" (exists=' + BoolToStr(TFile.Exists(PrimaryDb), True) + ')');
    if (PrimaryDb = '') and (ProjPath <> '') then
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
const
  M2022DbPath = 'C:\Projects\.drag-lint\M2022.sqlite';
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

  { v0.46: the manifest is the source of truth. If a manifest section covers the
    active file, use THAT clean DB and skip the per-.dproj template/ancestor/
    sibling walk -- otherwise a stale per-project DB sitting next to a sub-project
    .dproj (e.g. CLIENT\drag-lint.sqlite) shadows the manifest's DB and shows
    phantom/duplicated symbols. The library DB is still appended below.

    v(project-scoped): ask by ACTIVE PROJECT FIRST, then by folder. Keying only
    off the editor file was right while one folder meant one section; since the
    manifest was split per project it silently answered from a SIBLING project's
    index -- ORM3\PACKAGE\*.pas resolved to ORM3-Interfaces.sqlite whatever was
    active, and ORM3's COMMON\ units belong to the client AND the server project,
    so no rule keyed on the file alone can pick between them. A wrong hover is
    worse than an absent one: nothing signals the mistake.

    ManifestReadDbs returns BOTH (project DB first, folder DB second) rather than
    replacing one with the other, so an editor file OUTSIDE the active project --
    library or third-party source, browsed with a project open -- is still
    answered by the folder match exactly as before.

    NOTE the argument: GetActiveProjectFilePath, NOT ProjPath. ProjPath above may
    have come from FindOwningProject, which returns TDirectory.GetFiles(dir,
    '*.dproj')[0] -- the FIRST project file in the directory. In a shared folder
    that is precisely the wrong one, and passing it here would have reproduced the
    bug this change exists to remove while looking like a fix. }
  var ActiveProj: string:= GetActiveProjectFilePath;
  var ReadDbs: TArray<string>:= ManifestReadDbs(ActiveProj, EditorPath);
  ManifestDb:= '';
  for P in ReadDbs do
    if (ManifestDb = '') and TFile.Exists(P) then ManifestDb:= P;

  if ManifestDb <> '' then
  begin
    { Every resolved DB that EXISTS is offered, primary first; consumers accept
      repeated --db. Absent ones are dropped: a reader must never be pointed at a
      file that is not there. }
    for P in ReadDbs do
      if TFile.Exists(P) then AddUnique(Result, P);

    { v0.95+: auto-include M2022.sqlite as reference DB when working on ORM3\CLIENT files.
      Brought-in units from Micronite2022 need symbol resolution from the source project
      for unknown symbols/types/uses. This enables "hover-to-find-definition" on 2022
      symbols without explicit --db flag. }
    if Pos('ORM3', ManifestDb) > 0 then
    begin
      if TFile.Exists(M2022DbPath) then
        AddUnique(Result, M2022DbPath);
    end;

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

  { Try the template-resolved primary DB next to the .dproj first, then the
    project-name file (<projdir>\<projname>.sqlite) -- see PickProjectDb.
    v0.40.5: if neither yields an existing file, walk up the directory tree
    from the .dproj's folder. FindAncestorDb tries the configured template,
    the canonical default, AND the project-name file at each level, so legacy
    '.drag-lint.sqlite' configs still find the user's actual 'drag-lint.sqlite'
    or '<dirname>.sqlite' wherever it lives. }
  if ProjPath <> '' then
  begin
    PrimaryDb:= PickProjectDb(ProjPath, ASettings); // template-first, then <projname>.sqlite
    if PrimaryDb <> '' then AddUnique(Result, PrimaryDb)
    else
    begin
      ProjDir:= ExtractFilePath(ProjPath);
      AncestorDb:= FindAncestorDb(ProjDir, ASettings);
      if AncestorDb <> '' then AddUnique(Result, AncestorDb);
    end;
  end
  else if EditorPath <> '' then
  begin
    { NO PROJECT OPEN. Until now this fell straight through and resolved NO
      project index at all -- every walk-up above starts from a .dproj's
      folder, so with ProjPath empty FindAncestorDb was never called and the
      only database left was the platform library.

      That is a real editing situation, not a corner: a loose unit opened
      with File > Open, a file browsed from another repository, anything
      after File > Close All. The symptom is silent and reads as a broken
      index -- hover answers nothing, and nothing on screen says why.
      Reported from a live IDE, 2026-08-27.

      Walking up from the FILE is exactly what FindAncestorDb was written to
      do; it simply had no caller for this case. Its candidates at each level
      are specific -- the configured template, the canonical default, and
      <dirname>.sqlite -- so a hit means a database deliberately named for
      the folder it sits in, which is the convention. It stops at the drive
      root and only tests file existence, so a miss is cheap. }
    AncestorDb:= FindAncestorDb(ExtractFilePath(EditorPath), ASettings);
    if AncestorDb <> '' then
    begin
      AddUnique(Result, AncestorDb);
      DLT('dbresolve', Format('no project open; walked up from %s -> %s',
                              [ExtractFilePath(EditorPath), AncestorDb]));
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
