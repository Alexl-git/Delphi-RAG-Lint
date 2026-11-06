unit DragLint.Plugin.IndexJob;

{ Tier 1 of the lint-tree ladder: what a save-time reindex actually asks for.

  WHY IT IS ITS OWN UNIT. This is one string, and the string is load-bearing in
  three separate ways that are all invisible at a glance:

    NO `--rebuild`. A rebuild re-parses the whole project and, on the rebuild
      path only, STOPS THE RESIDENT LSP first to release the FTS trigger lock.
      Firing that on Ctrl+S would take the IDE's own diagnostics down every time
      anyone saved. The incremental form is what B0(c) measured: a no-op pass
      0.37 s, a one-file write 1.21 s, both exit 0, no `database is locked`,
      with two resident LSP children alive throughout.

    `--project`, not the saved FILE. `index <file> --db <projectDb>` is what the
      save path did before, and it cannot see a NEW unit's closure -- and a
      folder target would be worse still, silently widening a project DB into a
      directory DB (measured 2026-09-02: DataCopy 39 -> 72 files).

    the COALESCE KEY is the DB, not the file. Save All on 30 units used to spawn
      30 detached engines against one database. Keyed on the DB, the queue keeps
      the last one and drops the rest, which is the whole point of routing this
      through the queue rather than CreateProcessW.

  Keeping it here, with no ToolsAPI in sight, is what lets
  tests\IndexJobTests.dpr assert all three without an IDE. }

interface

uses
  System.SysUtils,
  DRagLint.Index.Manifest,
  DragLint.Plugin.JobQueue;

const
  /// <summary>STALL budget for one reindex (fix/late-results, owner ruling
  /// 2026-11-01): the run is killed only after this long with neither output nor
  /// CPU from the engine's tree -- a hung engine. A reindex that is working runs
  /// to completion however slow the machine is (the 120 s WALL clock this used
  /// to be ended "Reindex Micronite2027" with exit -2 twice on 2026-11-01).
  /// Ten minutes because an engine waiting for another process's writer lock
  /// burns no CPU and must not be mistaken for a hung one.</summary>
  INDEX_JOB_TIMEOUT_MS = 600000;

/// <summary>The command line for an incremental, save-time project reindex.</summary>
/// <param name="AExePath">Full path to drag-lint.exe.</param>
/// <param name="AProjectFile">The .dproj (or .dpr) whose closure to refresh.</param>
/// <param name="ADbPath">That project's index database.</param>
/// <param name="APlatform">Win32/Win64; omitted entirely when empty, rather
/// than emitted as a bare flag with nothing after it.</param>
/// <returns>A quoted command line with NO --rebuild.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DragLint.Plugin.IndexJob.BuildProjectIndexJob (DragLint.Plugin.IndexJob.pas), DragLint.Plugin.ProjectNotifier.TDragLintProjectNotifier.SpawnIndexer (DragLint.Plugin.ProjectNotifier.pas)</para>
/// <para>Calls: Format</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function BuildProjectIndexCmdLine(const AExePath, AProjectFile, ADbPath,
                                  APlatform: string): string;

/// <summary>The coalesce key for a save-time reindex: one key per DATABASE, so
/// a Save All collapses to a single run.</summary>
/// <param name="ADbPath">The project's index database.</param>
/// <returns>'index:' followed by the lowercased DB path.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DragLint.Plugin.IndexJob.BuildProjectIndexJob (DragLint.Plugin.IndexJob.pas)</para>
/// <para>Calls: LowerCase</para>
/// <para>Returns: 'index:' + LowerCase(ADbPath)</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ProjectIndexCoalesceKey(const ADbPath: string): string;

/// <summary>A ready-to-enqueue tier-1 reindex job.</summary>
/// <param name="AExePath">Full path to drag-lint.exe.</param>
/// <param name="AProjectFile">The .dproj whose closure to refresh.</param>
/// <param name="ADbPath">That project's index database.</param>
/// <param name="APlatform">Win32/Win64, or '' to leave it to the engine.</param>
/// <returns>A TDragLintJob the caller hands to the queue, which then owns it.</returns>
/// <remarks>
/// Not streaming: there is no progress worth showing for a run that
/// is normally under two seconds, and a marquee that flickers on every save is
/// worse than none.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DragLint.Plugin.Reports.OfferReindex (DragLint.Plugin.Reports.pas), DragLint.Plugin.SaveNotifier.QueueReindexJob (DragLint.Plugin.SaveNotifier.pas)</para>
/// <para>Calls: ChangeFileExt, DragLint.Plugin.IndexJob.BuildProjectIndexCmdLine, DragLint.Plugin.IndexJob.ProjectIndexCoalesceKey, DragLint.Plugin.JobQueue.TDragLintJob.Create, ExtractFileName, Format</para>
/// <para>Returns: TDragLintJob.Create</para>
/// <para>Owns returned: new (caller owns)</para>
/// <seealso cref="DragLint.Plugin.IndexJob.BuildProjectIndexCmdLine"/>
/// <seealso cref="DragLint.Plugin.IndexJob.ProjectIndexCoalesceKey"/>
/// <seealso cref="DragLint.Plugin.JobQueue.TDragLintJob.Create"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function BuildProjectIndexJob(const AExePath, AProjectFile, ADbPath,
                              APlatform: string): TDragLintJob;

/// <summary>The coalesce key for a per-FILE fallback reindex: one key per
/// (database, file) pair.</summary>
/// <param name="ADbPath">The index database the file belongs to.</param>
/// <param name="AFilePath">The saved source file.</param>
/// <returns>'index-file:' + lowercased DB + '|' + lowercased file.</returns>
/// <remarks>
/// Per FILE, not per DB: the fallback indexes only the file it names,
/// so collapsing two different files would leave all but the last one stale.
/// A re-save of the SAME file still collapses. The 'index-file:' prefix keeps it
/// from ever superseding a pending project reindex of the same DB.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DragLint.Plugin.IndexJob.BuildFileIndexJob (DragLint.Plugin.IndexJob.pas)</para>
/// <para>Calls: LowerCase</para>
/// <para>Returns: 'index-file:' + LowerCase(ADbPath) + '|' + LowerCase(AFilePath)</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function FileIndexCoalesceKey(const ADbPath, AFilePath: string): string;

/// <summary>A ready-to-enqueue per-file fallback reindex job:
/// <c>index "file" --db "db" --deep</c>.</summary>
/// <param name="AExePath">Full path to drag-lint.exe.</param>
/// <param name="AFilePath">The saved source file.</param>
/// <param name="ADbPath">The DB the manifest says covers AFilePath.</param>
/// <returns>A jkReindex TDragLintJob the caller hands to the queue, which then
/// owns it.</returns>
/// <remarks>
/// The save path's fallback when no active project has a unique owner
/// DB (deep review F6). Going through the queue means it waits out an
/// ide-release hold, coalesces per file, and reports its exit code -- which the
/// detached CreateProcessW spawn it replaces did not. --deep keeps the identifier
/// usage refs the project DB was built with.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DragLint.Plugin.SaveNotifier.QueueFileReindexJob (DragLint.Plugin.SaveNotifier.pas)</para>
/// <para>Calls: DragLint.Plugin.IndexJob.FileIndexCoalesceKey, DragLint.Plugin.JobQueue.TDragLintJob.Create, ExtractFileName, Format</para>
/// <para>Returns: TDragLintJob.Create</para>
/// <para>Owns returned: new (caller owns)</para>
/// <seealso cref="DragLint.Plugin.IndexJob.FileIndexCoalesceKey"/>
/// <seealso cref="DragLint.Plugin.JobQueue.TDragLintJob.Create"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function BuildFileIndexJob(const AExePath, AFilePath, ADbPath: string): TDragLintJob;

/// <summary>The database a save-time reindex of AProjectFile may write: the
/// manifest's UNIQUE owner of that project, and nothing else.</summary>
/// <param name="AProjectFile">The ACTIVE project's .dproj; '' when none.</param>
/// <param name="AMatch">ManifestDbForProject's verdict for AProjectFile.</param>
/// <param name="AOwnerDb">The DB ManifestDbForProject returned (meaningful only
/// for pdmUnique).</param>
/// <param name="AWhy">Receives why nothing may be written, for the log; ''
/// when a DB is returned.</param>
/// <returns>AOwnerDb when AProjectFile is set, AMatch is pdmUnique and AOwnerDb
/// is not blank; '' otherwise -- the caller then queues NOTHING.</returns>
/// <remarks>
/// Pure. Exists because the save path used to take the last-OPENED
/// project's DB (GLastProjectDb) and pair it with the ACTIVE project, writing
/// one project's closure into another project's index (2026-10-16). A missing
/// or ambiguous owner is a refusal, never permission to guess.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DragLint.Plugin.DbResolver.ActiveProjectWriteDb (DragLint.Plugin.DbResolver.pas)</para>
/// <para>Returns: ''; AOwnerDb</para>
/// <para>Mutates: AWhy (out)</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ReindexTargetDb(const AProjectFile: string; AMatch: TProjectDbMatch;
                         const AOwnerDb: string; out AWhy: string): string;

type
  /// <summary>What a save-time reindex actually started.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DragLint.Plugin.IndexJob.pas), DragLint.Plugin.IndexJob.ChooseSaveReindex (DragLint.Plugin.IndexJob.pas)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TSaveReindexAction = (sraNone, sraProject, sraFile);

/// <summary>Decides what AfterSave started, so the Messages pane only announces a
/// reindex that is really running.</summary>
/// <param name="AProjectQueued">True when the project reindex job was enqueued.</param>
/// <param name="AFallbackDb">The DB the manifest assigns to the saved file, '' if none.</param>
/// <returns>sraProject when a job was queued; else sraFile when AFallbackDb is not blank;
/// else sraNone (nothing started: do not post "reindexing...").</returns>
/// <remarks>
/// Pure.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DragLint.Plugin.SaveNotifier.TDragLintSaveNotifier.AfterSave (DragLint.Plugin.SaveNotifier.pas)</para>
/// <para>Returns: sraProject; sraFile; sraNone</para>
/// <para>Effect-free (proven)</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ChooseSaveReindex(AProjectQueued: Boolean; const AFallbackDb: string): TSaveReindexAction;

implementation

function ChooseSaveReindex(AProjectQueued: Boolean; const AFallbackDb: string): TSaveReindexAction;
begin
  if AProjectQueued then Result:= sraProject
  else if AFallbackDb <> '' then Result:= sraFile
  else Result:= sraNone;
end;
function ReindexTargetDb(const AProjectFile: string; AMatch: TProjectDbMatch;
                         const AOwnerDb: string; out AWhy: string): string;
begin
  Result:= '';
  AWhy  := '';
  if AProjectFile = '' then AWhy:= 'no active project'
  else if AMatch = pdmAmbiguous then AWhy:= 'two or more manifest sections claim ' + AProjectFile
  else if (AMatch <> pdmUnique) or (AOwnerDb = '') then AWhy:= 'no manifest section names ' + AProjectFile
  else Result:= AOwnerDb;
end;
function BuildProjectIndexCmdLine(const AExePath, AProjectFile, ADbPath,
                                  APlatform: string): string;
begin
  Result:= Format('"%s" index --project "%s" --db "%s"',
                  [AExePath, AProjectFile, ADbPath]);
  if APlatform <> '' then Result:= Result + Format(' --platform %s', [APlatform]);
end;

function ProjectIndexCoalesceKey(const ADbPath: string): string;
begin
  Result:= 'index:' + LowerCase(ADbPath);
end;

function BuildProjectIndexJob(const AExePath, AProjectFile, ADbPath,
                              APlatform: string): TDragLintJob;
begin
  Result:= TDragLintJob.Create;
  Result.Kind       := jkReindex;
  Result.Title      := Format('Reindex %s', [ChangeFileExt(ExtractFileName(AProjectFile), '')]);
  Result.CoalesceKey:= ProjectIndexCoalesceKey(ADbPath);
  Result.CmdLine    := BuildProjectIndexCmdLine(AExePath, AProjectFile, ADbPath, APlatform);
  Result.TimeoutMs  := INDEX_JOB_TIMEOUT_MS;
  Result.Streaming  := False;
end;

function FileIndexCoalesceKey(const ADbPath, AFilePath: string): string;
begin
  Result:= 'index-file:' + LowerCase(ADbPath) + '|' + LowerCase(AFilePath);
end;

function BuildFileIndexJob(const AExePath, AFilePath, ADbPath: string): TDragLintJob;
begin
  Result:= TDragLintJob.Create;
  Result.Kind       := jkReindex;
  Result.Title      := Format('Reindex %s', [ExtractFileName(AFilePath)]);
  Result.CoalesceKey:= FileIndexCoalesceKey(ADbPath, AFilePath);
  Result.CmdLine    := Format('"%s" index "%s" --db "%s" --deep', [AExePath, AFilePath, ADbPath]);
  Result.TimeoutMs  := INDEX_JOB_TIMEOUT_MS;
  Result.Streaming  := False;
end;

end.
