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
  DragLint.Plugin.JobQueue;

const
  /// <summary>Ceiling for one save-time reindex. Generous against the measured
  /// 1.21 s because the cost scales with how much changed, and a timeout kills
  /// a run that was doing real work; the queue's coalescing, not this, is what
  /// keeps the load down.</summary>
  INDEX_JOB_TIMEOUT_MS = 120000;

/// <summary>The command line for an incremental, save-time project reindex.</summary>
/// <param name="AExePath">Full path to drag-lint.exe.</param>
/// <param name="AProjectFile">The .dproj (or .dpr) whose closure to refresh.</param>
/// <param name="ADbPath">That project's index database.</param>
/// <param name="APlatform">Win32/Win64; omitted entirely when empty, rather
/// than emitted as a bare flag with nothing after it.</param>
/// <returns>A quoted command line with NO --rebuild.</returns>
function BuildProjectIndexCmdLine(const AExePath, AProjectFile, ADbPath,
                                  APlatform: string): string;

/// <summary>The coalesce key for a save-time reindex: one key per DATABASE, so
/// a Save All collapses to a single run.</summary>
/// <param name="ADbPath">The project's index database.</param>
/// <returns>'index:' followed by the lowercased DB path.</returns>
function ProjectIndexCoalesceKey(const ADbPath: string): string;

/// <summary>A ready-to-enqueue tier-1 reindex job.</summary>
/// <param name="AExePath">Full path to drag-lint.exe.</param>
/// <param name="AProjectFile">The .dproj whose closure to refresh.</param>
/// <param name="ADbPath">That project's index database.</param>
/// <param name="APlatform">Win32/Win64, or '' to leave it to the engine.</param>
/// <returns>A TDragLintJob the caller hands to the queue, which then owns it.</returns>
/// <remarks>Not streaming: there is no progress worth showing for a run that
/// is normally under two seconds, and a marquee that flickers on every save is
/// worse than none.</remarks>
function BuildProjectIndexJob(const AExePath, AProjectFile, ADbPath,
                              APlatform: string): TDragLintJob;

implementation

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

end.
