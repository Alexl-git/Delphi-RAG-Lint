unit DRagLint.Refactor.CompileGate;

// ---------------------------------------------------------------------------
// The compile gate every rewrite of the project's source goes through (lane 144 T0, lifted verbatim out of
// DRagLint.CLI.CycleFix). A static proof decides whether a rewrite is sound; the gate is the backstop: it builds the
// untouched project first (refusal dirty-baseline), writes all the changed files or none under backups, builds again,
// makes at most one bounded repair pass with a second build, and on any failure restores every file byte-identically
// from originals held in memory, last-write times included.
// `cycles --fix` keeps its own pipeline on these parts (BaselineCompile, CompileAfter, WriteAll, ApplyGroup); any other
// rewrite calls ApplyGated.
// ---------------------------------------------------------------------------

interface

uses
  System.SysUtils, System.Classes, Winapi.Windows,
  DRagLint.Core.ControlChannel,  // dl:ok uses-global-census@dbdf -- CONTROL_MSG_SHUTDOWN is the stand-down contract the gate's control channel answers; it travels with the channel class
  DRagLint.Core.Model;  // dl:ok uses-global-census@1abd -- version and ref-kind constants of the model; a small unit of its own would add nothing (146 int); TCompilerFinding moved it to the interface (v151 GATE)

const
  /// <summary>The compile gate builds at most twice: the after-build and one retry after the repairs.</summary>
  CGateSecondBuild = 2;
  /// <summary>Refusal kind: the rewrite was not attempted, the RAD Studio build environment was not found.</summary>
  CGateCompilerUnavailable = 'compiler-unavailable';
  /// <summary>Refusal kind: the untouched project does not build.</summary>
  CGateDirtyBaseline = 'dirty-baseline';
  /// <summary>Refusal kind: a write failed; the project was rolled back.</summary>
  CGateWriteFailed = 'write-failed';
  /// <summary>Refusal kind: the project does not build after the rewrite; rolled back.</summary>
  CGateCompileError = 'compile-error';
  /// <summary>Refusal kind: a build ran past --build-timeout; rolled back.</summary>
  CGateBuildTimeout = 'build-timeout';
  /// <summary>Refusal kind: a build could not even run; rolled back.</summary>
  CGateBuildError = 'build-error';
  /// <summary>Refusal kind: a stand-down request arrived; rolled back.</summary>
  CGateCancelled = 'cancelled';

type
  /// <summary>Raised inside a gated run once a stand-down request (the maintenance control
  /// channel: `drag-lint stop-now`, or the IDE's Cancel) is taken while the run waits on a child.</summary>
  /// <remarks>
  /// The child's process tree is already gone when it is raised. The caller turns it into a
  /// rollback and the refusal `cancelled`, or, raised before any file was written, into
  /// "cancelled -- nothing written". Either way the run exits 1.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.CLI.CycleFix.pas) ?, DRagLint.Refactor.CompileGate.RunBounded (DRagLint.Refactor.CompileGate.pas), DRagLint.Refactor.NarrowParam.TNarrowPlanner.Decide (DRagLint.Refactor.NarrowParam.pas), DRagLint.Refactor.RedundantCast.TCastPlanner.Decide (DRagLint.Refactor.RedundantCast.pas), DRagLint.Refactor.RedundantCast.TCastPlanner.ReadAllRows (DRagLint.Refactor.RedundantCast.pas) (+5 more)</para>
  /// <para>Used in units: DRagLint.CLI.CycleFix, DRagLint.Refactor.CompileGate, DRagLint.Refactor.NarrowParam, DRagLint.Refactor.RedundantCast, DRagLint.Refactor.ScratchGate, DRagLint.Refactor.Unwith</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  ECompileGateCancelled = class(Exception);

  /// <summary>The outcome of one msbuild run of a whole project (RunMsBuild).</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.CLI.CycleFix.pas) ?, declaration (DRagLint.Refactor.CompileGate.pas) ?, DRagLint.CLI.CycleFix.BaselineCompile (DRagLint.CLI.CycleFix.pas) ?, DRagLint.Refactor.CompileGate.RunMsBuild (DRagLint.Refactor.CompileGate.pas)</para>
  /// <para>Used in units: DRagLint.CLI.CycleFix, DRagLint.Refactor.CompileGate</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TBuildOutcome = record
    /// <summary>True when msbuild exited 0 and printed no `error E`/`fatal F` line.</summary>
    Ok: Boolean;
    /// <summary>The distinct dcc error lines, trimmed, in log order (empty when Ok).</summary>
    Errors: TArray<string>;
    /// <summary>Wall-clock seconds of the build.</summary>
    Seconds: Double;
    /// <summary>True when the build ran past its time limit and was killed (Ok is False).</summary>
    TimedOut: Boolean;
    /// <summary>Every dcc message of the build -- errors, warnings and hints -- once each, in log order (DccMessages).
    /// Empty when the build did not run or was killed.</summary>
    Messages: TArray<TCompilerFinding>;
  end;

  /// <summary>One bounded repair (R4) the compile gate made; an item of `repairs[]` in cycle-fix/1.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.CLI.CycleFix.pas), declaration (DRagLint.Refactor.CompileGate.pas), DRagLint.CLI.CycleFix.CompileAfter (DRagLint.CLI.CycleFix.pas), DRagLint.CLI.CycleFix.TryRepair (DRagLint.CLI.CycleFix.pas), DRagLint.CLI.CycleFix.TryRepair.AddRepair (DRagLint.CLI.CycleFix.pas)</para>
  /// <para>Used in units: DRagLint.CLI.CycleFix, DRagLint.Refactor.CompileGate</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TRepair = record
    /// <summary>The dcc code repaired: E2003, E2015 or E2010.</summary>
    Code: string;
    /// <summary>The file the dcc line names, as found in the build tree.</summary>
    FilePath: string;
    /// <summary>The line the dcc line names.</summary>
    Line: Integer;
    /// <summary>What was changed, in words.</summary>
    Action: string;
  end;

  /// <summary>The result of the after-gate (CompileAfter).</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.CLI.CycleFix.pas) ?, DRagLint.CLI.CycleFix.CompileAfter (DRagLint.CLI.CycleFix.pas) ?, DRagLint.CLI.CycleFix.RunCycleFixGroups (DRagLint.CLI.CycleFix.pas), DRagLint.CLI.CycleFix.RunHubSurfaceFix (DRagLint.CLI.CycleFix.pas), DRagLint.Refactor.CompileGate.CompileAfterWith (DRagLint.Refactor.CompileGate.pas) (+1 more)</para>
  /// <para>Used in units: DRagLint.CLI.CycleFix, DRagLint.Refactor.CompileGate</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TCompileAfterResult = record
    /// <summary>True when the last build was clean.</summary>
    Ok: Boolean;
    /// <summary>The dcc error lines of the last build.</summary>
    Errors: TArray<string>;
    /// <summary>The repairs made between the first and the second build; empty = no retry.</summary>
    Repairs: TArray<TRepair>;
    /// <summary>1, or 2 when a repair was retried.</summary>
    Builds: Integer;
    /// <summary>Seconds of every build together.</summary>
    Seconds: Double;
    /// <summary>True when the last build was killed at its time limit.</summary>
    TimedOut: Boolean;
    /// <summary>Every dcc message of the last build (TBuildOutcome.Messages).</summary>
    Messages: TArray<TCompilerFinding>;
  end;

  /// <summary>What WriteAll wrote and everything RollBack needs to undo it.</summary>
  /// <remarks>
  /// Owns no object; the original bytes are held in memory, so a rollback never depends on
  /// the backup files.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.CLI.CycleFix.pas) ?, declaration (DRagLint.Refactor.CompileGate.pas) ?, DRagLint.CLI.CycleFix.WriteAll (DRagLint.CLI.CycleFix.pas) ?, DRagLint.Refactor.CompileGate.MakeDirs (DRagLint.Refactor.CompileGate.pas) ?, DRagLint.Refactor.CompileGate.WriteStaged (DRagLint.Refactor.CompileGate.pas) (+2 more)</para>
  /// <para>Used in units: DRagLint.CLI.CycleFix, DRagLint.Refactor.CompileGate</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TApplyTransaction = record
    /// <summary>The project paths written, new files first, in write order.</summary>
    Written: TArray<string>;
    /// <summary>The new files among Written.</summary>
    NewFiles: TArray<string>;
    /// <summary>Every existing file the plan touches (written or not: a repair may edit it).</summary>
    Held: TArray<string>;
    /// <summary>The original bytes of Held, index for index.</summary>
    Originals: TArray<TBytes>;
    /// <summary>The original last-write times of Held (UTC), restored with the bytes so the index sees no change.</summary>
    Stamps: TArray<TDateTime>;
    /// <summary>The "orig -&gt; backup" lines of the backups made (empty with --no-backup).</summary>
    Backups: TArray<string>;
    /// <summary>The backup files made.</summary>
    BackupPaths: TArray<string>;
    /// <summary>The folders created for new files, outermost first.</summary>
    CreatedDirs: TArray<string>;
    /// <summary>recovery.txt in the project folder ('' with --no-backup).</summary>
    RecoveryPath: string;
    /// <summary>True when recovery.txt existed before the write.</summary>
    RecoveryExisted: Boolean;
    /// <summary>Its bytes before the write.</summary>
    RecoveryBefore: TBytes;
    /// <summary>Its last-write time (UTC) before the write.</summary>
    RecoveryStamp: TDateTime;
    /// <summary>Why the write failed; '' when it succeeded.</summary>
    Error: string;
    /// <summary>When the write failed: the files the rollback could not restore; '' = restored.</summary>
    RollbackFailure: string;
  end;

  /// <summary>One bounded repair pass over the dcc lines of a failed after-build (CompileAfterWith).</summary>
  /// <param name="pErrors">The dcc lines of the failed build.</param>
  /// <returns>The repairs made; empty = nothing repairable, no second build.</returns>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Refactor.CompileGate.pas), DRagLint.Refactor.CompileGate.CompileAfterWith (DRagLint.Refactor.CompileGate.pas)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TGateRepairFunc = reference to function(const pErrors: TArray<string>): TArray<TRepair>;

  /// <summary>The bytes a rewrite wants one existing file to hold.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Refactor.CompileGate.pas) ?, DRagLint.CLI.ApplyEditsGated (DRagLint.CLI.pas) ?, DRagLint.CLI.RepoParamArray.RunGate (DRagLint.CLI.RepoParamArray.pas) ?, DRagLint.Refactor.NarrowParam.BuildGateFiles (DRagLint.Refactor.NarrowParam.pas) ?, DRagLint.Refactor.Unwith.UnwithApply (DRagLint.Refactor.Unwith.pas) (+3 more)</para>
  /// <para>Used in units: DRagLint.CLI, DRagLint.CLI.RepoParamArray, DRagLint.Refactor.CompileGate, DRagLint.Refactor.NarrowParam, DRagLint.Refactor.RedundantCast, DRagLint.Refactor.RenameProof, DRagLint.Refactor.Unwith, DRagLint.Refactor.VerbShape</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TGateFile = record
    /// <summary>The file, absolute. It must exist; a new file has no place in this record.</summary>
    Path: string;
    /// <summary>Its full new content.</summary>
    Bytes: TBytes;
  end;

  /// <summary>A rewrite to pass through the gate (ApplyGated).</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.CLI.ApplyEditsGated (DRagLint.CLI.pas), DRagLint.CLI.RepoParamArray.RunGate (DRagLint.CLI.RepoParamArray.pas), DRagLint.Refactor.NarrowParam.RunNarrowParam (DRagLint.Refactor.NarrowParam.pas), DRagLint.Refactor.RedundantCast.RunRedundantCastFix (DRagLint.Refactor.RedundantCast.pas), DRagLint.Refactor.RenameProof.ApplyRenameGated (DRagLint.Refactor.RenameProof.pas) (+6 more)</para>
  /// <para>Used in units: DRagLint.CLI, DRagLint.CLI.RepoParamArray, DRagLint.Refactor.CompileGate, DRagLint.Refactor.NarrowParam, DRagLint.Refactor.RedundantCast, DRagLint.Refactor.RenameProof, DRagLint.Refactor.ScratchGate, DRagLint.Refactor.Unwith, DRagLint.Refactor.VerbShape</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TGateRequest = record
    /// <summary>The .dproj to build; its folder holds the backups' recovery.txt.</summary>
    Project: string;
    /// <summary>win32 / win64 (any case); '' = Win64.</summary>
    Platform: string;
    /// <summary>The verb's name in the progress lines, e.g. 'lint --fix'.</summary>
    Verb: string;
    /// <summary>The recovery.txt block's header.</summary>
    Header: string;
    /// <summary>--no-backup: no `.BCK&lt;n&gt;` copies and no recovery.txt.</summary>
    NoBackup: Boolean;
    /// <summary>--rsvars, expanded; '' = the Studio the registry / BDS names.</summary>
    RsVars: string;
    /// <summary>The folder of the builds' .bat files and logs: outside the project.</summary>
    LogDir: string;
    /// <summary>The rewrite.</summary>
    Files: TArray<TGateFile>;
    /// <summary>Optional repair pass; nil = none.</summary>
    Repair: TGateRepairFunc;
    /// <summary>The other .dproj files that compile the rewritten units (E-RENAME-MULTIPROJECT): each is built before the
    /// write and after it, on the same terms as Project; any failure refuses or rolls back, naming it. The repair pass
    /// does not run for them.</summary>
    AlsoProjects: TArray<string>;
  end;

  /// <summary>What ApplyGated did.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.Refactor.CompileGate.ApplyGated (DRagLint.Refactor.CompileGate.pas), DRagLint.Refactor.ExtractInterface.RunExtractInterface (DRagLint.Refactor.ExtractInterface.pas), DRagLint.Refactor.LazyInit.RunLazyInit (DRagLint.Refactor.LazyInit.pas), DRagLint.Refactor.NarrowParam.RunNarrowParam (DRagLint.Refactor.NarrowParam.pas), DRagLint.Refactor.RedundantCast.RunRedundantCastFix (DRagLint.Refactor.RedundantCast.pas) (+13 more)</para>
  /// <para>Used in units: DRagLint.CLI.RepoParamArray, DRagLint.Refactor.CompileGate, DRagLint.Refactor.ExtractInterface, DRagLint.Refactor.LazyInit, DRagLint.Refactor.NarrowParam, DRagLint.Refactor.RedundantCast, DRagLint.Refactor.RenameProof, DRagLint.Refactor.ScratchGate, DRagLint.Refactor.VerbShape</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TGateOutcome = record
    /// <summary>True when the files are written and the project builds.</summary>
    Applied: Boolean;
    /// <summary>'' when Applied; else one of the CGate* refusal kinds.</summary>
    Refusal: string;
    /// <summary>One line for the user: the first dcc line, the write error, the rollback's state.</summary>
    Detail: string;
    /// <summary>True when files were written and then restored.</summary>
    RolledBack: Boolean;
    /// <summary>True when the restore itself failed: the project may be PARTLY changed.</summary>
    RollbackFailed: Boolean;
    /// <summary>The baseline build.</summary>
    Baseline: TBuildOutcome;
    /// <summary>The after gate.</summary>
    After: TCompileAfterResult;
    /// <summary>What was written, and the backups.</summary>
    Tx: TApplyTransaction;
    /// <summary>True when build 1 (the baseline of Project) ran to its end, clean or not.</summary>
    BeforeBuilt: Boolean;
    /// <summary>Every message of build 1 of Project -- errors, warnings and hints -- kept whether it passed or not (P14).</summary>
    BeforeMessages: TArray<TCompilerFinding>;
    /// <summary>True when build 2 (the last after-build of Project) ran to its end, clean or not.</summary>
    AfterBuilt: Boolean;
    /// <summary>Every message of build 2 of Project.</summary>
    AfterMessages: TArray<TCompilerFinding>;
    /// <summary>When Applied: the warnings and hints of build 2 that build 1 did not have (NewCompilerMessages).</summary>
    NewMessages: TArray<TCompilerFinding>;
    /// <summary>When Applied: how many warnings and hints of build 1 build 2 no longer has.</summary>
    GoneMessages: Integer;
  end;

var
  GRsVars    : string; // W6 C7: --rsvars, expanded; '' = TStudioEnv
  GBuildTimeoutMs: Cardinal = INFINITE; // --build-timeout in ms; INFINITE = no limit (CDefaultBuildTimeoutS)
  GStandDown : TControlChannel; // the run's control channel (RunCycleFix); nil = not listening
  GCancelTaken: Boolean; // a stand-down request was taken: every later child wait raises at once
  GScratchCited: Boolean; // a message of this run names a file in its scratch: DeleteDefaultScratch keeps it
  GProgressDb : string; // the run's --db, expanded: the progress lines name the `stop-now --db` that cancels it
  /// <summary>The verb the progress lines name.</summary>
  GGateVerb: string = 'cycles --fix';

/// <summary>Builds a whole project with msbuild, the recipe of tools\score-cycle-playbook.ps1
/// Invoke-Build: a generated `.bat` calls rsvars.bat, changes to the project folder and runs
/// `msbuild /t:Build /p:Config=Debug /p:Platform=&lt;p&gt; /v:minimal`, output to pLogPath.</summary>
/// <param name="pProject">The .dproj to build.</param>
/// <param name="pPlatform">win32 / win64 (any case); '' = Win64.</param>
/// <param name="pLogPath">The build log; the `.bat` is written next to it (same name, .bat).
/// Its folder is created; neither file is in the project.</param>
/// <param name="pWhat">The step the progress names, e.g. 'baseline build'.</param>
/// <returns>Ok, the distinct `error E`/`fatal F` lines and the seconds taken. A missing rsvars.bat
/// gives Ok = False with one line saying so (CompilerAvailable tells beforehand).</returns>
/// <exception cref="ECompileGateCancelled">A stand-down request arrived on the run's control channel while
/// the build ran: the build's process tree was killed.</exception>
/// <remarks>
/// The build writes what any build of the project writes (dcu, exe) into the project's
/// own output folders; it writes no source file. The build is UNBOUNDED by default (owner ruling
/// 2026-10-26); --build-timeout &lt;s&gt; bounds it: a run past the limit is killed with its whole process tree
/// (a job object) and returns Ok = False, TimedOut = True and one `build-timeout` line. The test seam
/// DRAGLINT_CYCLEFIX_BUILD_TIMEOUT_MS (milliseconds, so a test can force an instant timeout) overrides
/// the flag for a project under %TEMP% / C:\TEMP only.
/// While it waits the build reports progress (owner ruling D4, 2026-11-03): `&lt;GGateVerb&gt;: &lt;pWhat&gt; --
/// started`, then every 10 s `&lt;GGateVerb&gt;: &lt;pWhat&gt; -- &lt;n&gt; s ...` on stderr, and the heartbeat step
/// `&lt;pWhat&gt; &lt;n&gt; s` (the IDE status strip).
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.CycleFix.BaselineCompile (DRagLint.CLI.CycleFix.pas), DRagLint.Refactor.CompileGate.ApplyGated (DRagLint.Refactor.CompileGate.pas), DRagLint.Refactor.CompileGate.CompileAfterWith (DRagLint.Refactor.CompileGate.pas)</para>
/// <para>Calls: ChangeFileExt, ContainsStr, Default, DRagLint.Refactor.CompileGate.BuildEnvBat, DRagLint.Refactor.CompileGate.BuildTimeoutMs, DRagLint.Refactor.CompileGate.CiteScratch, DRagLint.Refactor.CompileGate.CompilerAvailable, DRagLint.Refactor.CompileGate.DccErrorLines, DRagLint.Refactor.CompileGate.DccMessages, DRagLint.Refactor.CompileGate.MsBuildPlatform (+8 more)</para>
/// <para>Returns: Default(TBuildOutcome)</para>
/// <para>Touches: file system</para>
/// <seealso cref="DRagLint.Refactor.CompileGate.BuildEnvBat"/>
/// <seealso cref="DRagLint.Refactor.CompileGate.BuildTimeoutMs"/>
/// <seealso cref="DRagLint.Refactor.CompileGate.CiteScratch"/>
/// <seealso cref="DRagLint.Refactor.CompileGate.CompilerAvailable"/>
/// <seealso cref="DRagLint.Refactor.CompileGate.DccErrorLines"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function RunMsBuild(const pProject, pPlatform, pLogPath: string; const pWhat: string = 'build'): TBuildOutcome;

/// <summary>True when the RAD Studio rsvars.bat RunMsBuild calls exists.</summary>
/// <returns>False when no Studio root resolves (TStudioEnv: $BDS, the registry, the fallback) or
/// its rsvars.bat is missing.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.CycleFix.PassBaselineGate (DRagLint.CLI.CycleFix.pas), DRagLint.Refactor.CompileGate.ApplyGated (DRagLint.Refactor.CompileGate.pas), DRagLint.Refactor.CompileGate.RunMsBuild (DRagLint.Refactor.CompileGate.pas), DRagLint.Refactor.ScratchGate.ApplyThroughScratch (DRagLint.Refactor.ScratchGate.pas)</para>
/// <para>Calls: DRagLint.Refactor.CompileGate.BuildEnvBat</para>
/// <para>Returns: (Bat &lt;&gt; '') and TFile.Exists(Bat)</para>
/// <para>Touches: file system</para>
/// <seealso cref="DRagLint.Refactor.CompileGate.BuildEnvBat"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function CompilerAvailable: Boolean;

/// <summary>The Studio build-environment batch: --rsvars when given (GRsVars), else the repo's one Studio-root
/// resolver; '' when no root resolves.</summary>
/// <returns>The path of rsvars.bat, or ''.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.CycleFix.PassBaselineGate (DRagLint.CLI.CycleFix.pas), DRagLint.Refactor.CompileGate.ApplyGated (DRagLint.Refactor.CompileGate.pas), DRagLint.Refactor.CompileGate.CompilerAvailable (DRagLint.Refactor.CompileGate.pas), DRagLint.Refactor.CompileGate.RunMsBuild (DRagLint.Refactor.CompileGate.pas), DRagLint.Refactor.ScratchGate.BuildMirror (DRagLint.Refactor.ScratchGate.pas)</para>
/// <para>Calls: DRagLint.Core.StudioEnv.TStudioEnv.RootOrEmpty, DRagLint.Core.StudioEnv.TStudioEnv.RsvarsBat</para>
/// <para>Returns: if TStudioEnv.RootOrEmpty = '' then ''</para>
/// <seealso cref="DRagLint.Core.StudioEnv.TStudioEnv.RootOrEmpty"/>
/// <seealso cref="DRagLint.Core.StudioEnv.TStudioEnv.RsvarsBat"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function BuildEnvBat: string;

/// <summary>Runs pCmd as a child in its own job object and waits at most pTimeoutMs (INFINITE = no limit).</summary>
/// <param name="pWhat">The step the progress names.</param>
/// <param name="pCmd">The command line.</param>
/// <param name="pOutFile">'' or the file that receives the child's stdout and stderr.</param>
/// <param name="pTimeoutMs">The limit; on expiry the whole job is terminated.</param>
/// <param name="pTimedOut">True when the limit was hit.</param>
/// <param name="pEngineChild">True when the child is a `cycles --fix`, which stands down by itself.</param>
/// <returns>The exit code, or -1 after a kill.</returns>
/// <exception cref="EOSError">The child cannot start.</exception>
/// <exception cref="ECompileGateCancelled">A stand-down request was taken.</exception>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.CycleFix.AllIteration (DRagLint.CLI.CycleFix.pas), DRagLint.CLI.CycleFix.NextGroup (DRagLint.CLI.CycleFix.pas), DRagLint.CLI.CycleFix.RerunAfterReindex (DRagLint.CLI.CycleFix.pas), DRagLint.CLI.CycleFix.VerifyAfterCore (DRagLint.CLI.CycleFix.pas), DRagLint.Refactor.CompileGate.RunMsBuild (DRagLint.Refactor.CompileGate.pas) (+2 more)</para>
/// <para>Calls: AssignProcessToJobObject, Cardinal, CloseHandle, CreateFile, CreateJobObject, CreateProcess, DRagLint.Core.ControlChannel.TControlChannel.RequestEvent, DRagLint.Refactor.CompileGate.ReportWaitProgress, DRagLint.Refactor.CompileGate.StandDownChild, DRagLint.Refactor.CompileGate.TakeStandDown (+16 more)</para>
/// <para>Returns: -1; Integer(Code)</para>
/// <para>Complexity: 23 (cyclomatic, outer body), 87 lines (full implementation)</para>
/// <para>Mutates: pTimedOut (out)</para>
/// <seealso cref="DRagLint.Core.ControlChannel.TControlChannel.RequestEvent"/>
/// <seealso cref="DRagLint.Refactor.CompileGate.ReportWaitProgress"/>
/// <seealso cref="DRagLint.Refactor.CompileGate.StandDownChild"/>
/// <seealso cref="DRagLint.Refactor.CompileGate.TakeStandDown"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function RunBounded(const pWhat, pCmd, pOutFile: string; pTimeoutMs: Cardinal; out pTimedOut: Boolean;
  pEngineChild: Boolean = False): Integer;

/// <summary>True when pPath lies under C:\TEMP, %TEMP% or the system temp folder (GetTempPath, which reads %TMP%
/// first): the scope of every test seam.</summary>
/// <param name="pPath">The path.</param>
/// <returns>True under any of the three roots.</returns>
/// <remarks>
/// 1.52 BK-VERIFY: a runner that builds its fixture under [IO.Path]::GetTempPath() lands in %TMP%; with
/// %TEMP% = C:\TEMP and %TMP% elsewhere the seam used to miss it.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.CycleFix.BreakSeam (DRagLint.CLI.CycleFix.pas), DRagLint.CLI.CycleFix.ChildExe (DRagLint.CLI.CycleFix.pas), DRagLint.CLI.CycleFix.PrepareChildOutput (DRagLint.CLI.CycleFix.pas), DRagLint.CLI.CycleFix.ProbeSpec (DRagLint.CLI.CycleFix.pas), DRagLint.CLI.FixEditsUnderTestSeam (DRagLint.CLI.pas) (+6 more)</para>
/// <para>Calls: ExpandFileName, GetEnvironmentVariable, IncludeTrailingPathDelimiter, StartsText</para>
/// <para>Touches: file system</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function IsUnderTemp(const pPath: string): Boolean;

/// <summary>The time limit of a build of pProject: --build-timeout (INFINITE = none, the default), or the test seam
/// DRAGLINT_CYCLEFIX_BUILD_TIMEOUT_MS (milliseconds) for a project under %TEMP% / C:\TEMP.</summary>
/// <param name="pProject">The project.</param>
/// <returns>The limit in milliseconds.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.CycleFix.AnnounceSeams (DRagLint.CLI.CycleFix.pas), DRagLint.Refactor.CompileGate.RunMsBuild (DRagLint.Refactor.CompileGate.pas), DRagLint.Refactor.ScratchGate.BuildMirror (DRagLint.Refactor.ScratchGate.pas)</para>
/// <para>Calls: DRagLint.Refactor.CompileGate.IsUnderTemp, GetEnvironmentVariable, StrToIntDef</para>
/// <para>Returns: GBuildTimeoutMs; Seam</para>
/// <seealso cref="DRagLint.Refactor.CompileGate.IsUnderTemp"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function BuildTimeoutMs(const pProject: string): Cardinal;

/// <summary>The stand-down request, if one is pending: takes it and remembers that it was taken.</summary>
/// <returns>False when there is none, or the listener withdrew it a moment ago.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Refactor.CompileGate.RunBounded (DRagLint.Refactor.CompileGate.pas), DRagLint.Refactor.NarrowParam.TNarrowPlanner.Decide (DRagLint.Refactor.NarrowParam.pas), DRagLint.Refactor.RedundantCast.TCastPlanner.Decide (DRagLint.Refactor.RedundantCast.pas), DRagLint.Refactor.RedundantCast.TCastPlanner.ReadAllRows (DRagLint.Refactor.RedundantCast.pas), DRagLint.Refactor.RedundantCast.TCastPlanner.StandDownProbe (DRagLint.Refactor.RedundantCast.pas)</para>
/// <para>Calls: DRagLint.Core.ControlChannel.TControlChannel.StandDownRequested</para>
/// <para>Returns: GCancelTaken</para>
/// <seealso cref="DRagLint.Core.ControlChannel.TControlChannel.StandDownRequested"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function TakeStandDown: Boolean;

/// <summary>The text a message uses to cite pPath, a file in this run's scratch.</summary>
/// <param name="pPath">The file.</param>
/// <param name="pFmt">The format, with one %s.</param>
/// <returns>Format(pFmt, [pPath]) when the file exists (the scratch is then kept at exit), else ''.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.CycleFix.AllIteration (DRagLint.CLI.CycleFix.pas), DRagLint.CLI.CycleFix.NextGroup (DRagLint.CLI.CycleFix.pas), DRagLint.CLI.CycleFix.VerifyAfterCore (DRagLint.CLI.CycleFix.pas), DRagLint.Refactor.CompileGate.RunMsBuild (DRagLint.Refactor.CompileGate.pas)</para>
/// <para>Calls: Format</para>
/// <para>Returns: Format(pFmt, [pPath])</para>
/// <para>Touches: file system</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function CiteScratch(const pPath, pFmt: string): string;

/// <summary>A scratch name under C:\TEMP that does not exist now.</summary>
/// <param name="pTail">The name's tail, e.g. '_build'.</param>
/// <returns>The directory name with a trailing delimiter; nothing is created.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.ApplyEditsGated (DRagLint.CLI.pas), DRagLint.CLI.CycleFix.BuildScratchDir (DRagLint.CLI.CycleFix.pas), DRagLint.CLI.CycleFix.DefaultShadowDir (DRagLint.CLI.CycleFix.pas), DRagLint.CLI.RepoParamArray.RunGate (DRagLint.CLI.RepoParamArray.pas), DRagLint.Refactor.NarrowParam.RunNarrowParam (DRagLint.Refactor.NarrowParam.pas) (+4 more)</para>
/// <para>Calls: Copy, Format, GetEnvironmentVariable, GUIDToString, IntToStr</para>
/// <para>Returns: Format('C:\TEMP\draglint_cyclefix_%s%s\', [Pid, pTail]); Format('C:\TEMP\draglint_cyclefix_%s_%s%s\', [Pid, Copy(GUIDToString(TGUID.NewGuid), CGuidHexFrom, CGuidHexLen), pTail])</para>
/// <para>Touches: file system</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function FreshScratchName(const pTail: string): string;

  /// <summary>One dcc error line, parsed (ParseDccLine).</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.CLI.CycleFix.DccErrorsToJson (DRagLint.CLI.CycleFix.pas), DRagLint.CLI.CycleFix.TryRepair (DRagLint.CLI.CycleFix.pas) ?, DRagLint.CLI.CycleFix.TryRepair.AddRepair (DRagLint.CLI.CycleFix.pas) ?, DRagLint.CLI.CycleFix.TryRepair.RepairCast (DRagLint.CLI.CycleFix.pas) ?, DRagLint.Refactor.CompileGate.ParseDccLine (DRagLint.Refactor.CompileGate.pas) (+4 more)</para>
  /// <para>Used in units: DRagLint.CLI.CycleFix, DRagLint.CLI.RepoParamArray, DRagLint.Refactor.CompileGate</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
type
  TDccLine = record
    /// <summary>The file the line names.</summary>
    FileName: string;
    /// <summary>The line it names.</summary>
    Line: Integer;
    /// <summary>E2003, F2047, ...</summary>
    Code: string;
    /// <summary>The message.</summary>
    Message: string;
  end;

/// <summary>Parses `File.pas(57): error E2015: Message [proj]` (msbuild) or `[dcc64 Error] File.pas(57): E2015 Message` (dcc).</summary>
/// <param name="pText">The line.</param>
/// <param name="pLine">Receives the parts.</param>
/// <returns>False when it is neither.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.CycleFix.DccErrorsToJson (DRagLint.CLI.CycleFix.pas), DRagLint.CLI.CycleFix.TryRepair (DRagLint.CLI.CycleFix.pas), DRagLint.CLI.RepoParamArray.RefuseNamedUnits (DRagLint.CLI.RepoParamArray.pas)</para>
/// <para>Calls: Default, StrToIntDef, Trim, UpperCase</para>
/// <para>Returns: M.Success</para>
/// <para>Mutates: pLine (out)</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ParseDccLine(const pText: string; out pLine: TDccLine): Boolean;

/// <summary>The first line in [pFrom, pTo) matching pPattern, case-insensitively.</summary>
/// <param name="pLines">The lines.</param>
/// <param name="pPattern">The regular expression.</param>
/// <param name="pFrom">First index.</param>
/// <param name="pTo">One past the last index.</param>
/// <returns>The index, or -1.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.CycleFix.TryRepair.RepairPointer (DRagLint.CLI.CycleFix.pas), DRagLint.Refactor.CompileGate.AddToUses (DRagLint.Refactor.CompileGate.pas), DRagLint.Refactor.CompileGate.SectionNameOf (DRagLint.Refactor.CompileGate.pas), DRagLint.Refactor.CompileGate.SectionRange (DRagLint.Refactor.CompileGate.pas)</para>
/// <para>Returns: -1</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function LineIndexOf(pLines: TStrings; const pPattern: string; pFrom, pTo: Integer): Integer;

/// <summary>interface / implementation / program: the section holding 0-based line pIdx.</summary>
/// <param name="pLines">The unit's lines.</param>
/// <param name="pIdx">The line.</param>
/// <returns>The section's name.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.CycleFix.TryRepair.QueueUses (DRagLint.CLI.CycleFix.pas), DRagLint.Refactor.NarrowParam.BuildGateFiles (DRagLint.Refactor.NarrowParam.pas), DRagLint.Refactor.NarrowParam.BuildNarrowEdits (DRagLint.Refactor.NarrowParam.pas)</para>
/// <para>Calls: DRagLint.Refactor.CompileGate.LineIndexOf</para>
/// <para>Returns: if LineIndexOf(pLines, '^\s*interface\b', 0, pLines.Count) &gt;= 0 then 'interface'</para>
/// <seealso cref="DRagLint.Refactor.CompileGate.LineIndexOf"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function SectionNameOf(pLines: TStrings; pIdx: Integer): string;

/// <summary>Adds pLeaf as the first entry of the section's uses clause (a section without one gets one).</summary>
/// <param name="pLines">The unit's lines; edited in place.</param>
/// <param name="pSection">interface / implementation / program (SectionNameOf).</param>
/// <param name="pLeaf">The unit to add.</param>
/// <returns>False when it is there already or the section has no place for it.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.CycleFix.TryRepair (DRagLint.CLI.CycleFix.pas), DRagLint.Refactor.NarrowParam.BuildGateFiles (DRagLint.Refactor.NarrowParam.pas), DRagLint.Refactor.NarrowParam.BuildNarrowEdits (DRagLint.Refactor.NarrowParam.pas)</para>
/// <para>Calls: DRagLint.Refactor.CompileGate.LineIndexOf, DRagLint.Refactor.CompileGate.SectionRange, DRagLint.Refactor.CompileGate.UsesEntries, MatchText, Trim</para>
/// <para>Returns: True</para>
/// <seealso cref="DRagLint.Refactor.CompileGate.LineIndexOf"/>
/// <seealso cref="DRagLint.Refactor.CompileGate.SectionRange"/>
/// <seealso cref="DRagLint.Refactor.CompileGate.UsesEntries"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function AddToUses(pLines: TStrings; const pSection, pLeaf: string): Boolean;

/// <summary>pPaths expanded, each once (case-insensitive), in first-seen order.</summary>
/// <param name="pPaths">The paths.</param>
/// <returns>The distinct full paths.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Refactor.CompileGate.WriteStaged (DRagLint.Refactor.CompileGate.pas)</para>
/// <para>Calls: ExpandFileName, LowerCase</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function DistinctPaths(const pPaths: TArray<string>): TArray<string>;  // dl:ok unused-public-symbol@64dc -- public API for the next gated rewrites (items 3 and 4) and the owed report rule

/// <summary>Writes a staged result into the project: all files or none.</summary>
/// <param name="pTouched">Every existing file the rewrite touches.</param>
/// <param name="pNew">The new files.</param>
/// <param name="pProjectDir">The project folder (recovery.txt; the write-failure test seam's scope).</param>
/// <param name="pNoBackup">--no-backup: no `.BCK&lt;n&gt;` copies and no recovery.txt.</param>
/// <param name="pStaged">The bytes a path is to hold; raises when there are none.</param>
/// <param name="pHeader">The recovery.txt block's header, from the changed and new file counts.</param>
/// <param name="pTx">Receives what was written and what a rollback needs.</param>
/// <returns>True when every file was written; False when anything failed, in which case the
/// project is already rolled back (pTx.Error says why, pTx.RollbackFailure what could not be restored).</returns>
/// <exception cref="EInOutError"><!-- drag-lint:auto exc -->the new unit's file already exists: %s</exception>
/// <remarks>
/// Order: every touched file's original bytes are read into memory; unless pNoBackup each
/// changed file is copied to its NextBackupName sibling and a recovery.txt block is appended
/// (AppendRecoveryBlock) BEFORE any write; then the new files are written, then the changed
/// files. A file whose staged bytes equal the original is not written. Each write passes FailWriteForTests
/// (DRAGLINT_TEST_FAIL_WRITE_AT).
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.CycleFix.WriteAll (DRagLint.CLI.CycleFix.pas), DRagLint.Refactor.CompileGate.ApplyGated (DRagLint.Refactor.CompileGate.pas)</para>
/// <para>Calls: Default, DRagLint.Refactor.CompileGate.BackUpChanged, DRagLint.Refactor.CompileGate.DistinctPaths, DRagLint.Refactor.CompileGate.MakeDirs, DRagLint.Refactor.CompileGate.RollBack, DRagLint.Refactor.CompileGate.SameBytes, DRagLint.Refactor.CompileGate.WriteStaged.WriteOne, ExtractFilePath, FailWriteForTests, IsUnderTemp, LowerCase, pHeader, pStaged</para>
/// <para>Returns: True; False</para>
/// <para>Catches: Exception (swallowed)</para>
/// <para>Mutates: pTx (out)</para>
/// <para>Touches: file system</para>
/// <seealso cref="DRagLint.Refactor.CompileGate.BackUpChanged"/>
/// <seealso cref="DRagLint.Refactor.CompileGate.DistinctPaths"/>
/// <seealso cref="DRagLint.Refactor.CompileGate.MakeDirs"/>
/// <seealso cref="DRagLint.Refactor.CompileGate.RollBack"/>
/// <seealso cref="DRagLint.Refactor.CompileGate.SameBytes"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function WriteStaged(const pTouched, pNew: TArray<string>; const pProjectDir: string; pNoBackup: Boolean;
  const pStaged: TFunc<string, TBytes>; const pHeader: TFunc<Integer, Integer, string>;
  out pTx: TApplyTransaction): Boolean;

/// <summary>The lines a gated verb prints about its two builds (P14).</summary>
/// <param name="pOutcome">What ApplyGated did.</param>
/// <returns>One `compile gate: ...` line each: the counts of build 1, every error of build 1, the counts of build 2,
/// every error of build 2, and when the rewrite was applied the new warnings and hints of build 2 (or that there are
/// none) and how many of build 1 are gone. Empty when no build ran.</returns>
/// <remarks>
/// Pure. The caller decides the stream (the CLI writes them to stderr).
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.ApplyEditsGated (DRagLint.CLI.pas), DRagLint.CLI.FinishRename (DRagLint.CLI.pas), DRagLint.CLI.RepoParamArray.NoteGate (DRagLint.CLI.RepoParamArray.pas), DRagLint.Refactor.ExtractInterface.RunExtractInterface (DRagLint.Refactor.ExtractInterface.pas)</para>
/// <para>Calls: DRagLint.Refactor.CompileGate.GateMessageReport.Build, DRagLint.Refactor.CompileGate.GateMessageReport.Shown, Format, SameText</para>
/// <seealso cref="DRagLint.Refactor.CompileGate.GateMessageReport.Build"/>
/// <seealso cref="DRagLint.Refactor.CompileGate.GateMessageReport.Shown"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function GateMessageReport(const pOutcome: TGateOutcome): TArray<string>;

/// <summary>The after gate: builds the written project, repairs once and builds again.</summary>
/// <param name="pBuildProject">The .dproj to build.</param>
/// <param name="pPlatform">As RunMsBuild.</param>
/// <param name="pLogDir">Folder for the .bat and logs (after-1.log, after-2.log).</param>
/// <param name="pRepair">The repair pass; nil = none.</param>
/// <returns>Ok, the last build's errors, the repairs and the build count and time.</returns>
/// <remarks>
/// Rolls nothing back: on not Ok the caller restores the transaction.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.CycleFix.CompileAfter (DRagLint.CLI.CycleFix.pas), DRagLint.Refactor.CompileGate.ApplyGated (DRagLint.Refactor.CompileGate.pas)</para>
/// <para>Calls: Default, DRagLint.Refactor.CompileGate.RunMsBuild, Format, IncludeTrailingPathDelimiter, pRepair</para>
/// <para>Returns: Default(TCompileAfterResult)</para>
/// <seealso cref="DRagLint.Refactor.CompileGate.RunMsBuild"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function CompileAfterWith(const pBuildProject, pPlatform, pLogDir: string; const pRepair: TGateRepairFunc): TCompileAfterResult;

/// <summary>Undoes WriteAll byte-identically.</summary>
/// <param name="pTx">The transaction WriteAll returned.</param>
/// <returns>'' when every file is restored; else the files that could not be, with the reason.</returns>
/// <remarks>
/// Restores every held original whose bytes changed (a repair's edits included) with its last-write time, deletes
/// the new files and the folders made for them, the backups made, and restores recovery.txt (or
/// deletes it when the write created it). Never raises.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.CycleFix.ApplyGroup (DRagLint.CLI.CycleFix.pas), DRagLint.CLI.CycleFix.CancelledApply (DRagLint.CLI.CycleFix.pas), DRagLint.Refactor.CompileGate.ApplyGated.RollBackAs (DRagLint.Refactor.CompileGate.pas), DRagLint.Refactor.CompileGate.WriteStaged (DRagLint.Refactor.CompileGate.pas), DRagLint.Refactor.Unwith.UnwithApply (DRagLint.Refactor.Unwith.pas) (+1 more)</para>
/// <para>Calls: DRagLint.Refactor.CompileGate.DeleteIfPresent, DRagLint.Refactor.CompileGate.RollBack.Attempt, DRagLint.Refactor.CompileGate.SameBytes, pStep</para>
/// <para>Returns: string.Join('; ', Fails.ToArray)</para>
/// <para>Catches: Exception (swallowed)</para>
/// <para>Touches: file system</para>
/// <seealso cref="DRagLint.Refactor.CompileGate.DeleteIfPresent"/>
/// <seealso cref="DRagLint.Refactor.CompileGate.RollBack.Attempt"/>
/// <seealso cref="DRagLint.Refactor.CompileGate.SameBytes"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function RollBack(const pTx: TApplyTransaction): string;

/// <summary>The one way a rewrite outside `cycles --fix` reaches the disk: baseline build, all-or-nothing write
/// under backups, after build (one repair pass when the request has one), rollback on any failure.</summary>
/// <param name="pReq">The rewrite.</param>
/// <returns>Applied, or the refusal with its detail. Never raises.</returns>
/// <exception cref="EInOutError"><!-- drag-lint:auto exc -->nothing staged for %s; via DRagLint.Refactor.CompileGate.WriteStaged: the new unit's file already exists: %s</exception>
/// <remarks>
/// Nothing is written when the baseline does not build. Test seam: DRAGLINT_GATE_TEST_BREAK=1, for a project
/// under %TEMP% / C:\TEMP, puts a line dcc rejects at the top of the first written file before the after build, so a guard can
/// prove the rollback on a rewrite that is itself sound.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.ApplyEditsGated (DRagLint.CLI.pas), DRagLint.CLI.RepoParamArray.RunGate (DRagLint.CLI.RepoParamArray.pas), DRagLint.Refactor.NarrowParam.RunNarrowParam (DRagLint.Refactor.NarrowParam.pas), DRagLint.Refactor.RedundantCast.RunRedundantCastFix (DRagLint.Refactor.RedundantCast.pas), DRagLint.Refactor.RenameProof.ApplyRenameGated (DRagLint.Refactor.RenameProof.pas) (+2 more)</para>
/// <para>Calls: Default, DRagLint.Refactor.CompileGate.ApplyGated.RollBackAs, DRagLint.Refactor.CompileGate.BuildEnvBat, DRagLint.Refactor.CompileGate.CompileAfterWith, DRagLint.Refactor.CompileGate.CompilerAvailable, DRagLint.Refactor.CompileGate.IsUnderTemp, DRagLint.Refactor.CompileGate.NewCompilerMessages, DRagLint.Refactor.CompileGate.RunMsBuild, DRagLint.Refactor.CompileGate.WriteStaged, ExpandFileName (+7 more)</para>
/// <para>Returns: Outcome</para>
/// <para>Complexity: 22 (cyclomatic, outer body), 138 lines (full implementation)</para>
/// <para>Catches: ECompileGateCancelled (swallowed); Exception (swallowed)</para>
/// <para>Touches: file system</para>
/// <seealso cref="DRagLint.Refactor.CompileGate.ApplyGated.RollBackAs"/>
/// <seealso cref="DRagLint.Refactor.CompileGate.BuildEnvBat"/>
/// <seealso cref="DRagLint.Refactor.CompileGate.CompileAfterWith"/>
/// <seealso cref="DRagLint.Refactor.CompileGate.CompilerAvailable"/>
/// <seealso cref="DRagLint.Refactor.CompileGate.IsUnderTemp"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ApplyGated(const pReq: TGateRequest): TGateOutcome;

/// <summary>Opens the control channel of a gated `--apply` run, so `drag-lint stop-now` and the IDE's Cancel
/// reach it while it waits on a build (E-NARROW-CHANNEL).</summary>
/// <param name="pVerb">The verb hosting the run; must be one ControlChannelEnabledFor accepts.</param>
/// <param name="pDb">The run's --db; the channel answers `stop-now --db` for it.</param>
/// <returns>True when the channel listens (GStandDown is set). False when the verb does not listen or the
/// pipe could not start (said on stderr: a cancel then kills the run instead of rolling it back).</returns>
/// <exception cref="EInvalidOperation"><!-- drag-lint:auto exc -->via DRagLint.Core.ControlChannel.TControlChannel.Create: TControlChannel must be created on the main thread -- the one the listener has to wake</exception>
/// <remarks>
/// Main thread only. Pair with CloseGateStandDown in a finally. A request taken while ApplyGated
/// builds kills the build and rolls back: ApplyGated returns Refusal = CGateCancelled.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.DoCreateEnumHelper (DRagLint.CLI.pas), DRagLint.CLI.DoExtractInterface (DRagLint.CLI.pas), DRagLint.CLI.DoExtractMethod (DRagLint.CLI.pas), DRagLint.CLI.DoLazyInit (DRagLint.CLI.pas), DRagLint.CLI.DoNarrowParam (DRagLint.CLI.pas) (+2 more)</para>
/// <para>Calls: DRagLint.Core.ControlChannel.ControlChannelEnabledFor, DRagLint.Core.ControlChannel.TControlChannel.Create, DRagLint.Core.ControlChannel.TControlChannel.Start, ExpandFileName, Writeln</para>
/// <para>Returns: False; True</para>
/// <seealso cref="DRagLint.Core.ControlChannel.ControlChannelEnabledFor"/>
/// <seealso cref="DRagLint.Core.ControlChannel.TControlChannel.Create"/>
/// <seealso cref="DRagLint.Core.ControlChannel.TControlChannel.Start"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function OpenGateStandDown(const pVerb, pDb: string): Boolean;

/// <summary>Closes the channel OpenGateStandDown opened; a pending or taken request is answered `exiting`.</summary>
/// <remarks>
/// Safe when no channel is open. Call after the run's files are rolled back or kept.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.DoCreateEnumHelper (DRagLint.CLI.pas), DRagLint.CLI.DoExtractInterface (DRagLint.CLI.pas), DRagLint.CLI.DoExtractMethod (DRagLint.CLI.pas), DRagLint.CLI.DoLazyInit (DRagLint.CLI.pas), DRagLint.CLI.DoNarrowParam (DRagLint.CLI.pas) (+2 more)</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure CloseGateStandDown;

implementation

uses
  System.IOUtils, System.StrUtils, System.RegularExpressions, System.Diagnostics, System.Math,
  System.Generics.Collections,
  DRagLint.Convert.Backup, DRagLint.Core.StudioEnv, DRagLint.Refactor.TextEdit, DRagLint.Diagnostics.CompileCheck;

const
  CDefaultPlatform = 'win64';
  CMsPerSec        = 1000;
  CChildStandDownMs = 60 * 1000; // how long a child `cycles --fix` gets to roll back after a forwarded stand-down
  CPipeConnectMs    = 2000;  // how long to wait for a child's control pipe to accept the forwarded request
  CChildKillWaitMs = 5000;  // how long to wait for a killed child to exit
  CKilledExitCode  = 1;     // the exit code a killed child is given
  { Progress of a child wait (owner ruling D4, 2026-11-03: no time limit -- show progress, let the user
    cancel). The heartbeat step is refreshed every CProgressTickMs (the IDE status strip reads it); a
    stderr line repeats every CProgressLineMs. tests\autotest\run_cyclefix_progress.ps1 pins both. }
  CProgressTickMs   = 1000;
  CProgressLineMs   = 10 * 1000;
  CSectionStop   = '^\s*(type|const|var|threadvar|resourcestring|procedure|function|constructor|destructor|' +
                   'class|begin|initialization|finalization|exports|end\.)\b';

// The text a message uses to cite pPath, a file in this run's scratch: Format(pFmt, [pPath]) when the file
// exists -- and the scratch is then kept at exit (E18 final review F5, amended) -- else '' (a message never
// names a file that is not there, e.g. the log of a build killed before msbuild opened it).
function CiteScratch(const pPath, pFmt: string): string;
begin
  if not TFile.Exists(pPath) then Exit('');
  GScratchCited:= True;
  Result:= Format(pFmt, [pPath]);
end;

// A scratch name under C:\TEMP that does not exist NOW: the pid-based name, else the same with a random
// suffix. A leftover dir of an earlier process with this pid is therefore never reused (its contents
// never reach a build) and never deleted: whatever exists under a picked name at the end of the run,
// THIS run created.
function FreshScratchName(const pTail: string): string;
const
  CGuidHexFrom = 2; // past the opening brace
  CGuidHexLen  = 8;
var
  Pid: string;
begin
  { DRAGLINT_TEST_SCRATCH_PID (test seam, only names a dir under C:\TEMP): stands in for the pid, so a runner
    can plant the would-be name before the run }
  Pid:= GetEnvironmentVariable('DRAGLINT_TEST_SCRATCH_PID');
  if Pid = '' then Pid:= IntToStr(GetCurrentProcessId);
  Result:= Format('C:\TEMP\draglint_cyclefix_%s%s\', [Pid, pTail]); // dl:ok hardcoded-absolute-path@022b -- the debug shadow location is fixed by the E18 design; --shadow-out overrides it
  if TDirectory.Exists(Result) then
    Result:= Format('C:\TEMP\draglint_cyclefix_%s_%s%s\', [Pid, Copy(GUIDToString(TGUID.NewGuid), CGuidHexFrom, CGuidHexLen), pTail]); // dl:ok hardcoded-absolute-path@b155 -- same fixed location
end;

{ The Studio build-environment batch, from the repo's one Studio-root resolver (T17b D4:
  run_studio_root_guard); '' when no root resolves. }
function BuildEnvBat: string;
begin
  if GRsVars <> '' then Exit(GRsVars);  { W6 C7: --rsvars }
  Result:= if TStudioEnv.RootOrEmpty = '' then '' else TStudioEnv.RsvarsBat;
end;

function CompilerAvailable: Boolean;
begin
  var Bat:= BuildEnvBat;
  Result:= (Bat <> '') and TFile.Exists(Bat);
end;

/// <summary>Every dcc message of a build log: errors, warnings and hints, each (file, line, code, message) once, in
/// log order.</summary>
/// <param name="pLog">The msbuild or dcc output.</param>
/// <returns>The parsed messages (TCompileChecker.ParseLine), the trailing `[project]` msbuild appends cut from the
/// message.</returns>
/// <remarks>Pure. A line that is no dcc message (msbuild banners, the BUILD_EXITCODE line) is skipped.</remarks>
function DccMessages(const pLog: string): TArray<TCompilerFinding>; forward;

/// <summary>The warnings and hints of build 2 that build 1 did not have.</summary>
/// <param name="pBefore">Every message of build 1.</param>
/// <param name="pAfter">Every message of build 2.</param>
/// <param name="pGone">Receives how many warnings and hints of build 1 build 2 no longer has.</param>
/// <returns>The new warnings and hints, in build-2 order; errors and information lines are never in it.</returns>
/// <remarks>Pure. A message is matched by file, code and message text, never by line: the rewrite between the builds
/// moves lines. Matching counts: a hint build 1 had once and build 2 has twice is one new hint.</remarks>
function NewCompilerMessages(const pBefore, pAfter: TArray<TCompilerFinding>; out pGone: Integer): TArray<TCompilerFinding>; forward;

function MsBuildPlatform(const pPlatform: string): string;
begin
  if SameText(pPlatform, 'win32') then Result:= 'Win32'
  else if (pPlatform = '') or SameText(pPlatform, CDefaultPlatform) then Result:= 'Win64'
  else Result:= pPlatform;
end;

// The distinct `error E....` / `fatal F....` lines of a build log, trimmed, in log order.
function DccErrorLines(const pLog: string): TArray<string>;
var
  L: TList<string>;
begin
  L:= TList<string>.Create;
  try
    for var M in TRegEx.Matches(pLog, '^.*\b(error|fatal) [EF]\d{4}\b.*$', [roMultiLine]) do
    begin
      var S:= Trim(M.Value);
      if not L.Contains(S) then L.Add(S);
    end;
    Result:= L.ToArray;
  finally
    L.Free;
  end;
end;

function IsUnderTemp(const pPath: string): Boolean;
begin
  var Full:= ExpandFileName(pPath);
  var Temp:= GetEnvironmentVariable('TEMP');
  Result:= StartsText('C:\TEMP\', Full) or // dl:ok hardcoded-absolute-path@485b -- the test seams' fixed scratch root (ruling T10)
    ((Temp <> '') and StartsText(IncludeTrailingPathDelimiter(ExpandFileName(Temp)), Full)) or
    StartsText(IncludeTrailingPathDelimiter(ExpandFileName(TPath.GetTempPath)), Full);
end;

// The time limit of a build of pProject: --build-timeout (INFINITE = none, the default), or the test seam
// DRAGLINT_CYCLEFIX_BUILD_TIMEOUT_MS (milliseconds) for a project under %TEMP% / C:\TEMP. The seam stays
// beside the flag on purpose: the flag counts whole seconds, and a test that must time out the FIRST build
// before it can finish needs a limit of 1 ms.
function BuildTimeoutMs(const pProject: string): Cardinal;
begin
  Result:= GBuildTimeoutMs;
  var Seam:= StrToIntDef(GetEnvironmentVariable('DRAGLINT_CYCLEFIX_BUILD_TIMEOUT_MS'), 0);
  if (Seam > 0) and IsUnderTemp(pProject) then Result:= Seam;
end;

// The stand-down request, if one is pending: takes it (the listener can no longer withdraw it) and remembers
// that it was taken. False when there is none, or the listener withdrew it a moment ago.
function TakeStandDown: Boolean;
begin
  if not GCancelTaken and (GStandDown <> nil) and GStandDown.StandDownRequested then GCancelTaken:= True;
  Result:= GCancelTaken;
end;

// A stand-down taken while pPI ran: a child `cycles --fix` (pEngineChild) is asked to stand down in turn and
// given CChildStandDownMs to roll back and exit -- True, its exit code in pCode; otherwise (or when it does not
// exit in time) the whole job is terminated and False is returned.
function StandDownChild(const pPI: TProcessInformation; pJob: THandle; pEngineChild: Boolean; out pCode: Integer): Boolean;
var
  Code: Cardinal;
begin
  pCode:= -1;
  if pEngineChild then
  begin
    var Reply, Err: string;
    { blocks until the child answers: `exiting` once it rolled back and closed its stores, else `busy` }
    ControlRequest(ControlPipeNameFor(pPI.dwProcessId), CONTROL_MSG_SHUTDOWN + #9 + IntToStr(CChildStandDownMs),
      CPipeConnectMs, Reply, Err);
    if WaitForSingleObject(pPI.hProcess, CChildStandDownMs) = WAIT_OBJECT_0 then
    begin
      GetExitCodeProcess(pPI.hProcess, Code);
      pCode:= Integer(Code);
      Exit(True);
    end;
  end;
  if pJob <> 0 then TerminateJobObject(pJob, CKilledExitCode)
  else TerminateProcess(pPI.hProcess, CKilledExitCode);
  WaitForSingleObject(pPI.hProcess, CChildKillWaitMs);
  Result:= False;
end;

{ Runs pCmd as a child in its own job object and waits at most pTimeoutMs (INFINITE = no limit). pOutFile
  <> '': the child's stdout and stderr go to that file (created). On expiry the WHOLE job is terminated (a
  cmd.exe -> msbuild -> dcc tree dies with it) and pTimedOut is set. Returns the exit code, or -1 after a
  kill. Raises EOSError when the child cannot start. Replaces TCompileChecker.RunCommand for the gate's
  builds: that one waits INFINITE (CompileCheck.pas), and stays so for its callers.
  CANCEL (lane X-BT): the wait also watches the run's stand-down request (GStandDown). Once it is taken the
  child is stopped (StandDownChild) and ECompileGateCancelled is raised -- except for a child `cycles --fix`
  (pEngineChild) that stood down by itself: its exit code is returned, so the caller relays its own
  (rolled-back) result. A request taken earlier raises before anything is spawned.
  PROGRESS (lane 142-cyc, owner ruling D4): pWhat names the step ('baseline build', 're-index', ...). The
  run says `cycles --fix: <pWhat> -- started` on stderr, then every CProgressLineMs `... -- <n> s ...`, and
  keeps the heartbeat step at `<pWhat> <n> s` (refreshed every CProgressTickMs), which is what the IDE's
  status strip shows. Main thread only, so a progress line never lands inside a document on stdout. }
procedure ReportWaitProgress(const pWhat: string; pElapsedMs: UInt64; pLine: Boolean);
begin
  var Secs:= pElapsedMs div CMsPerSec;
  BeatStep(Format('%s %d s', [pWhat, Secs]));
  if pLine then
    Writeln(ErrOutput, Format(GGateVerb + ': %s -- %d s (no time limit; Cancel, or drag-lint stop-now --db "%s", stops it)',
      [pWhat, Secs, GProgressDb]));
end;

function RunBounded(const pWhat, pCmd, pOutFile: string; pTimeoutMs: Cardinal; out pTimedOut: Boolean;
  pEngineChild: Boolean = False): Integer;
var
  SA     : TSecurityAttributes;
  SI     : TStartupInfo;
  PI     : TProcessInformation;
  Job    : THandle;
  Output : THandle;
  Code   : Cardinal;
  Waits  : array[0..1] of THandle;
begin
  Result:= -1; { every path below Exit()s with a value or raises; this is the -1 of "no exit code" }
  pTimedOut:= False;
  if GCancelTaken then raise ECompileGateCancelled.Create('cancelled');
  Output:= INVALID_HANDLE_VALUE;
  FillChar(SI, SizeOf(SI), 0);
  SI.cb         := SizeOf(SI);
  SI.dwFlags    := STARTF_USESHOWWINDOW;
  SI.wShowWindow:= SW_HIDE;
  if pOutFile <> '' then
  begin
    SA.nLength:= SizeOf(SA);
    SA.lpSecurityDescriptor:= nil;
    SA.bInheritHandle:= True;
    ForceDirectories(ExtractFilePath(pOutFile));  // dl:ok ignored-must-use-result@93bb -- moved verbatim from CLI.CycleFix; a failed call surfaces at the next file operation
    Output:= CreateFile(PChar(pOutFile), GENERIC_WRITE, FILE_SHARE_READ, @SA, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, 0);
    if Output = INVALID_HANDLE_VALUE then RaiseLastOSError;
    SI.dwFlags   := SI.dwFlags or STARTF_USESTDHANDLES;
    SI.hStdOutput:= Output;
    SI.hStdError := Output;
    SI.hStdInput := 0;
  end;
  Job:= CreateJobObject(nil, nil);
  try
    var Cmd:= pCmd;
    UniqueString(Cmd);
    if not CreateProcess(nil, PChar(Cmd), nil, nil, pOutFile <> '', CREATE_NO_WINDOW or CREATE_SUSPENDED, nil, nil, SI, PI) then  // dl:ok unsafe-shellexecute@5152, taint-command-injection@5152 -- the gate's own generated .bat, or this engine (ParamStr(0)) on the run's own --db / --project
      RaiseLastOSError;
    try
      if Job <> 0 then AssignProcessToJobObject(Job, PI.hProcess);
      ResumeThread(PI.hThread);
      Waits[0]:= PI.hProcess;
      if GStandDown <> nil then Waits[1]:= GStandDown.RequestEvent;
      var Started:= GetTickCount64;
      var Deadline:= if pTimeoutMs = INFINITE then High(UInt64) else Started + pTimeoutMs;
      var NextLine:= Started + CProgressLineMs;
      Writeln(ErrOutput, GGateVerb, ': ', pWhat, ' -- started');
      ReportWaitProgress(pWhat, 0, False);
      repeat
        var Tick:= GetTickCount64;
        var Left:= if Deadline = High(UInt64) then INFINITE else Cardinal(Max(Int64(Deadline) - Int64(Tick), 0));
        var Rc:= WaitForMultipleObjects(if GStandDown <> nil then 2 else 1, @Waits[0], False, Min(Left, CProgressTickMs));
        if (Rc = WAIT_TIMEOUT) and (GetTickCount64 < Deadline) then
        begin
          { a progress tick, not the limit }
          Tick:= GetTickCount64;
          ReportWaitProgress(pWhat, Tick - Started, Tick >= NextLine);
          if Tick >= NextLine then NextLine:= Tick + CProgressLineMs;
          Continue;
        end;
        if Rc = WAIT_OBJECT_0 then
        begin
          GetExitCodeProcess(PI.hProcess, Code);
          Exit(Integer(Code));
        end;
        if Rc = WAIT_OBJECT_0 + 1 then
        begin
          if not TakeStandDown then Continue; { withdrawn by the listener a moment ago: keep waiting }
          var Stood: Integer;
          if StandDownChild(PI, Job, pEngineChild, Stood) then Exit(Stood);
          raise ECompileGateCancelled.Create('cancelled');
        end;
        { WAIT_TIMEOUT (or a failed wait): the limit is up }
        pTimedOut:= True;
        if Job <> 0 then TerminateJobObject(Job, CKilledExitCode)
        else TerminateProcess(PI.hProcess, CKilledExitCode);
        WaitForSingleObject(PI.hProcess, CChildKillWaitMs);
        Exit(-1);
      until False;
    finally
      CloseHandle(PI.hThread);
      CloseHandle(PI.hProcess);
    end;
  finally
    if Job <> 0 then CloseHandle(Job);
    if Output <> INVALID_HANDLE_VALUE then CloseHandle(Output);
  end;
end;

function RunMsBuild(const pProject, pPlatform, pLogPath: string; const pWhat: string = 'build'): TBuildOutcome;
begin
  Result:= Default(TBuildOutcome);
  if not CompilerAvailable then
  begin
    Result.Errors:= ['cannot build: the RAD Studio build environment was not found: ' + BuildEnvBat];
    Exit;
  end;
  var Project:= ExpandFileName(pProject);
  if SameText(ExtractFileExt(Project), '.dpr') and TFile.Exists(ChangeFileExt(Project, '.dproj')) then
    Project:= ChangeFileExt(Project, '.dproj');
  var Log:= ExpandFileName(pLogPath);
  var Bat:= ChangeFileExt(Log, '.bat');
  ForceDirectories(ExtractFilePath(Log));  // dl:ok ignored-must-use-result@50ff, taint-path-traversal@50ff -- moved verbatim from CLI.CycleFix; a failed call surfaces at the next file operation
  System.SysUtils.DeleteFile(Log); // a stale log of an earlier run must not be read as this one's; absent = fine  // dl:ok taint-path-traversal@6cab -- the path is the operator's own --project, the run's fixed scratch or the Studio root: local input, no privilege crossed
  TFile.WriteAllText(Bat, string.Join(#13#10, [
    '@echo off',
    Format('call "%s"', [BuildEnvBat]),
    Format('cd /d "%s"', [ExcludeTrailingPathDelimiter(ExtractFilePath(Project))]),
    Format('msbuild /t:Build /p:Config=Debug /p:Platform=%s /v:minimal "%s" > "%s" 2>&1',
      [MsBuildPlatform(pPlatform), Project, Log]),
    { redirection FIRST: `echo X=%ERRORLEVEL%>> f` expands to `X=0>> f`, a redirect of handle 0 }
    Format('>> "%s" echo BUILD_EXITCODE=%%ERRORLEVEL%%', [Log])]) + #13#10, TEncoding.ASCII);  // dl:ok locale-sensitive-conversion@9aa5 -- diagnostic / batch text, not data; locale formatting is harmless here -- SLZ-S10 2026-11-22
  var Watch:= TStopwatch.StartNew;
  var Limit:= BuildTimeoutMs(Project);
  RunBounded(pWhat, 'cmd.exe /c ""' + Bat + '""', '', Limit, Result.TimedOut);
  Result.Seconds:= Watch.Elapsed.TotalSeconds;
  if Result.TimedOut then
  begin
    Result.Errors:= [Format('build-timeout: msbuild did not finish within %d ms and was killed', [Limit]) + CiteScratch(Log, '; see %s')];
    Exit;
  end;
  var Text:= if TFile.Exists(Log) then TFile.ReadAllText(Log, TEncoding.ANSI) else '';  // dl:ok taint-path-traversal@88fe -- the path is the operator's own --project, the run's fixed scratch or the Studio root: local input, no privilege crossed
  Result.Errors:= DccErrorLines(Text);
  Result.Messages:= DccMessages(Text);
  Result.Ok:= ContainsStr(Text, 'BUILD_EXITCODE=0') and (Length(Result.Errors) = 0);
  if not Result.Ok and (Length(Result.Errors) = 0) then
    Result.Errors:= ['msbuild failed without a dcc error line' + CiteScratch(Log, '; see %s')];
end;

function DccMessages(const pLog: string): TArray<TCompilerFinding>;
var
  Seen: TDictionary<string, Boolean>;
  Found: TList<TCompilerFinding>;
begin
  Seen := TDictionary<string, Boolean>.Create;
  Found:= TList<TCompilerFinding>.Create;
  try
    for var Raw in pLog.Split([#10]) do
    begin
      var F: TCompilerFinding;
      if not TCompileChecker.ParseLine(Trim(Raw), F) then Continue;
      { msbuild ends every line with ` [<the .dproj>]`: not part of what dcc said }
      F.Message:= TRegEx.Replace(F.Message, '\s*\[[^\[\]]*\]\s*$', '');
      var Key:= LowerCase(F.RawPath) + '|' + IntToStr(F.LineNo) + '|' + F.Code + '|' + F.Message;
      if Seen.ContainsKey(Key) then Continue;
      Seen.Add(Key, True);
      Found.Add(F);
    end;
    Result:= Found.ToArray;
  finally
    Found.Free;
    Seen.Free;
  end;
end;

// A warning or hint, matched across two builds: file, code and text, not the line (the rewrite moves lines).
function MessageMatchKey(const pF: TCompilerFinding): string;
begin
  Result:= LowerCase(pF.RawPath) + '|' + pF.Code + '|' + pF.Message;
end;

function IsWarningOrHint(const pF: TCompilerFinding): Boolean;
begin
  Result:= SameText(pF.Severity, 'Warning') or SameText(pF.Severity, 'Hint');
end;

function NewCompilerMessages(const pBefore, pAfter: TArray<TCompilerFinding>; out pGone: Integer): TArray<TCompilerFinding>;
var
  Left: TDictionary<string, Integer>;
begin
  Result:= nil;
  pGone := 0;
  Left:= TDictionary<string, Integer>.Create;
  try
    for var F in pBefore do
      if IsWarningOrHint(F) then
      begin
        var N: Integer;
        Left.TryGetValue(MessageMatchKey(F), N);
        Left.AddOrSetValue(MessageMatchKey(F), N + 1);
      end;
    for var F in pAfter do
    begin
      if not IsWarningOrHint(F) then Continue;
      var N: Integer;
      if Left.TryGetValue(MessageMatchKey(F), N) and (N > 0) then Left[MessageMatchKey(F)]:= N - 1
      else Result:= Result + [F];
    end;
    for var N in Left.Values do Inc(pGone, N);
  finally
    Left.Free;
  end;
end;

function GateMessageReport(const pOutcome: TGateOutcome): TArray<string>;

  function Shown(const pF: TCompilerFinding): string;
  begin
    Result:= Format('%s(%d): %s %s', [pF.RawPath, pF.LineNo, pF.Code, pF.Message]);
  end;

  { the counts line, then every error line; pRawErrors stand in when no error line parsed (a timeout, a broken msbuild) }
  procedure Build(const pTag, pWhen: string; const pMessages: TArray<TCompilerFinding>; const pRawErrors: TArray<string>;
    var pLines: TArray<string>);
  begin
    var Errors, Warnings, Hints: Integer;
    Errors:= 0;
    Warnings:= 0;
    Hints:= 0;
    for var F in pMessages do
      if SameText(F.Severity, 'Error') then Inc(Errors)
      else if SameText(F.Severity, 'Warning') then Inc(Warnings)
      else if SameText(F.Severity, 'Hint') then Inc(Hints);
    pLines:= pLines + [Format('compile gate: %s (%s): %d error(s), %d warning(s), %d hint(s)', [pTag, pWhen, Errors, Warnings, Hints])];
    for var F in pMessages do
      if SameText(F.Severity, 'Error') then pLines:= pLines + ['compile gate: ' + pTag + ' error: ' + Shown(F)];
    if Errors = 0 then
      for var S in pRawErrors do pLines:= pLines + ['compile gate: ' + pTag + ' error: ' + S];
  end;

begin
  Result:= nil;
  if pOutcome.BeforeBuilt then
    Build('build 1', 'before the write', pOutcome.BeforeMessages,
      if pOutcome.AfterBuilt or pOutcome.Applied then nil else pOutcome.Baseline.Errors, Result);
  if pOutcome.AfterBuilt then
    Build('build 2', 'after the write', pOutcome.AfterMessages, if pOutcome.Applied then nil else pOutcome.After.Errors, Result);
  if not pOutcome.Applied then Exit;
  if Length(pOutcome.NewMessages) = 0 then Result:= Result + ['compile gate: no new warnings or hints after the write']
  else
  begin
    Result:= Result + [Format('compile gate: %d new warning(s)/hint(s) after the write:', [Length(pOutcome.NewMessages)])];
    for var F in pOutcome.NewMessages do Result:= Result + ['compile gate: new: ' + Shown(F)];
  end;
  if pOutcome.GoneMessages > 0 then
    Result:= Result + [Format('compile gate: %d warning(s)/hint(s) of build 1 are gone', [pOutcome.GoneMessages])];
end;

// `File.pas(57): error E2015: Message [proj]` (msbuild) or `[dcc64 Error] File.pas(57): E2015 Message` (dcc).
function ParseDccLine(const pText: string; out pLine: TDccLine): Boolean;
const
  CPattern = '^\s*(?:\[dcc\w*\s+\w+\]\s*)?(?<file>.+?)\((?<line>\d+)(?:,\d+)?\)\s*:?\s*(?:(?:error|fatal)\s*:?\s*)?' +
             '(?<code>[EF]\d{4})\s*:?\s*(?<msg>.*?)\s*(?:\[[^\[\]]*\])?\s*$';
begin
  pLine:= Default(TDccLine);
  var M:= TRegEx.Match(pText, CPattern, [roIgnoreCase]);
  Result:= M.Success;
  if not Result then Exit;
  pLine.FileName:= Trim(M.Groups['file'].Value);
  pLine.Line    := StrToIntDef(M.Groups['line'].Value, 0);
  pLine.Code    := UpperCase(M.Groups['code'].Value);
  pLine.Message := M.Groups['msg'].Value;
end;

function LineIndexOf(pLines: TStrings; const pPattern: string; pFrom, pTo: Integer): Integer;
begin
  for var I:= pFrom to pTo - 1 do
    if TRegEx.IsMatch(pLines[I], pPattern, [roIgnoreCase]) then Exit(I);
  Result:= -1;
end;

// interface / implementation / program: the section holding 0-based line pIdx.
function SectionNameOf(pLines: TStrings; pIdx: Integer): string;
begin
  var Impl:= LineIndexOf(pLines, '^\s*implementation\b', 0, pLines.Count);
  if (Impl >= 0) and (pIdx > Impl) then Exit('implementation');
  Result:= if LineIndexOf(pLines, '^\s*interface\b', 0, pLines.Count) >= 0 then 'interface' else 'program';
end;

// The [pLo, pHi) lines of the named section, pLo the line after its keyword.
procedure SectionRange(pLines: TStrings; const pName: string; out pLo, pHi: Integer);
begin
  var Impl:= LineIndexOf(pLines, '^\s*implementation\b', 0, pLines.Count);
  pLo:= 0;
  pHi:= pLines.Count;
  if pName = 'implementation' then pLo:= Impl + 1
  else if pName = 'interface' then
  begin
    pLo:= LineIndexOf(pLines, '^\s*interface\b', 0, pLines.Count) + 1;
    if Impl >= 0 then pHi:= Impl;
  end;
end;

// The unit names of the uses clause that starts at line pUses (comments and `in '...'` dropped).
function UsesEntries(pLines: TStrings; pUses: Integer): TArray<string>;
var
  Buf: TStringBuilder;
begin
  Result:= nil;
  Buf:= TStringBuilder.Create;
  try
    for var I:= pUses to pLines.Count - 1 do
    begin
      var S:= TRegEx.Replace(pLines[I], '//.*$', '');
      Buf.Append(S).Append(' ');
      if ContainsStr(S, ';') then Break;
    end;
    var Text:= TRegEx.Replace(Buf.ToString, '\{[^}]*\}|\(\*.*?\*\)', ' ');
    Text:= TRegEx.Replace(Text, '^\s*uses\b', '', [roIgnoreCase]);
    if Text.Contains(';') then Text:= Copy(Text, 1, Pos(';', Text) - 1);
    for var E in Text.Split([',']) do
      Result:= Result + [Trim(TRegEx.Replace(E, '\s+in\s+''[^'']*''', '', [roIgnoreCase]))];
  finally
    Buf.Free;
  end;
end;

// Adds pLeaf as the first entry of the section's uses clause (a section without one gets one).
// False when it is there already or the section has no place for it.
function AddToUses(pLines: TStrings; const pSection, pLeaf: string): Boolean;
var
  Lo, Hi: Integer;
begin
  SectionRange(pLines, pSection, Lo, Hi);
  var Stop:= LineIndexOf(pLines, CSectionStop, Lo, Hi);
  var U:= LineIndexOf(pLines, '^\s*uses\b', Lo, if Stop >= 0 then Stop else Hi);
  if U >= 0 then
  begin
    if MatchText(pLeaf, UsesEntries(pLines, U)) then Exit(False);
    var M:= TRegEx.Match(pLines[U], '^(\s*uses)\b(.*)$', [roIgnoreCase]);
    var Rest:= Trim(M.Groups[2].Value);
    if Rest = '' then pLines.Insert(U + 1, '  ' + pLeaf + ',')
    else pLines[U]:= M.Groups[1].Value + ' ' + pLeaf + ', ' + Rest;
  end
  else if pSection = 'program' then Exit(False)
  else
  begin
    pLines.Insert(Lo, '  ' + pLeaf + ';');
    pLines.Insert(Lo, 'uses');
    pLines.Insert(Lo, '');
  end;
  Result:= True;
end;

function SameBytes(const pA, pB: TBytes): Boolean;
begin
  Result:= (Length(pA) = Length(pB)) and ((Length(pA) = 0) or CompareMem(@pA[0], @pB[0], Length(pA)));
end;

// pPaths expanded, each once (case-insensitive), in first-seen order.
function DistinctPaths(const pPaths: TArray<string>): TArray<string>;
var
  Seen: TList<string>;
begin
  Seen:= TList<string>.Create;
  try
    Result:= nil;
    for var P in pPaths do
    begin
      var Full:= ExpandFileName(P);
      if Seen.Contains(LowerCase(Full)) then Continue;
      Seen.Add(LowerCase(Full));
      Result:= Result + [Full];
    end;
  finally
    Seen.Free;
  end;
end;

// Creates pDir and records every folder it had to make, outermost first.
procedure MakeDirs(const pDir: string; var pTx: TApplyTransaction);
begin
  var Missing: TArray<string>:= nil;
  var D:= ExcludeTrailingPathDelimiter(pDir);
  while (D <> '') and not TDirectory.Exists(D) do
  begin
    Missing:= [D] + Missing;
    var Up:= ExcludeTrailingPathDelimiter(ExtractFilePath(D));
    if Up = D then Break;
    D:= Up;
  end;
  if Length(Missing) = 0 then Exit;
  pTx.CreatedDirs:= pTx.CreatedDirs + Missing;
  ForceDirectories(pDir);  // dl:ok ignored-must-use-result@9e30 -- moved verbatim from CLI.CycleFix; a failed call surfaces at the next file operation
end;

// The backups of pChanged (NextBackupName siblings) and the recovery.txt block, before any write.
procedure BackUpChanged(const pChanged: TArray<string>; const pProjectDir, pHeader: string; var pTx: TApplyTransaction);
begin
  for var P in pChanged do
  begin
    var B:= NextBackupName(P);
    pTx.BackupPaths:= pTx.BackupPaths + [B];
    TFile.Copy(P, B);  // dl:ok taint-path-traversal@5e5c -- the path is the operator's own --project, the run's fixed scratch or the Studio root: local input, no privilege crossed
    pTx.Backups:= pTx.Backups + [Format('%s -> %s', [P, B])];
  end;
  pTx.RecoveryPath   := TPath.Combine(pProjectDir, 'recovery.txt');
  pTx.RecoveryExisted:= TFile.Exists(pTx.RecoveryPath);
  if pTx.RecoveryExisted then
  begin
    pTx.RecoveryBefore:= TFile.ReadAllBytes(pTx.RecoveryPath);  // dl:ok taint-path-traversal@dba5 -- the path is the operator's own --project, the run's fixed scratch or the Studio root: local input, no privilege crossed
    pTx.RecoveryStamp := TFile.GetLastWriteTimeUtc(pTx.RecoveryPath);
  end;
  AppendRecoveryBlock(pProjectDir, pHeader, pTx.Backups);
end;

// Deletes pPath; a file that is not there is fine, any other failure raises.
procedure DeleteIfPresent(const pPath: string);
begin
  if not System.SysUtils.DeleteFile(pPath) and (GetLastError <> ERROR_FILE_NOT_FOUND) then RaiseLastOSError;  // dl:ok taint-path-traversal@5455 -- the path is the operator's own --project, the run's fixed scratch or the Studio root: local input, no privilege crossed
end;

function RollBack(const pTx: TApplyTransaction): string;
var
  Fails: TList<string>;

  procedure Attempt(const pWhat: string; const pStep: TProc);
  begin
    try
      pStep();
    except
      on E: Exception do Fails.Add(pWhat + ': ' + E.Message);
    end;
  end;

begin
  Fails:= TList<string>.Create;
  try
    for var I:= 0 to High(pTx.Held) do
    begin
      var P:= pTx.Held[I];
      var Orig:= pTx.Originals[I];
      var Stamp:= pTx.Stamps[I];
      Attempt('restore ' + P, procedure
        begin
          if not TFile.Exists(P) or not SameBytes(TFile.ReadAllBytes(P), Orig) then TFile.WriteAllBytes(P, Orig);  // dl:ok taint-path-traversal@4690 -- the path is the operator's own --project, the run's fixed scratch or the Studio root: local input, no privilege crossed
          if TFile.GetLastWriteTimeUtc(P) <> Stamp then TFile.SetLastWriteTimeUtc(P, Stamp);
        end);
    end;
    for var P in pTx.NewFiles do
      Attempt('delete ' + P, procedure begin DeleteIfPresent(P); end);
    for var I:= High(pTx.CreatedDirs) downto 0 do
    begin
      var D:= pTx.CreatedDirs[I];
      Attempt('remove folder ' + D, procedure begin if TDirectory.Exists(D) then TDirectory.Delete(D); end);  // dl:ok taint-path-traversal@ee7b -- the path is the operator's own --project, the run's fixed scratch or the Studio root: local input, no privilege crossed
    end;
    for var P in pTx.BackupPaths do
      Attempt('delete ' + P, procedure begin DeleteIfPresent(P); end);
    if pTx.RecoveryPath <> '' then
      Attempt('restore ' + pTx.RecoveryPath, procedure
        begin
          if not pTx.RecoveryExisted then
          begin
            DeleteIfPresent(pTx.RecoveryPath);
            Exit;
          end;
          TFile.WriteAllBytes(pTx.RecoveryPath, pTx.RecoveryBefore);  // dl:ok taint-path-traversal@b542 -- the path is the operator's own --project, the run's fixed scratch or the Studio root: local input, no privilege crossed
          TFile.SetLastWriteTimeUtc(pTx.RecoveryPath, pTx.RecoveryStamp);
        end);
    Result:= string.Join('; ', Fails.ToArray);
  finally
    Fails.Free;
  end;
end;

function WriteStaged(const pTouched, pNew: TArray<string>; const pProjectDir: string; pNoBackup: Boolean;
  const pStaged: TFunc<string, TBytes>; const pHeader: TFunc<Integer, Integer, string>;
  out pTx: TApplyTransaction): Boolean;
var
  Changed: TList<string>;
  Staged : TDictionary<string, TBytes>;
  Writes : Integer;

  procedure WriteOne(const pPath: string);
  begin
    Inc(Writes);
    { the write-failure test seam acts only on a project under %TEMP% / C:\TEMP (fix round 1);
      TextEdit.FailWriteForTests itself stays unscoped for convert-apply }
    if IsUnderTemp(pProjectDir) then FailWriteForTests(Writes, pPath);
    TFile.WriteAllBytes(pPath, Staged[LowerCase(pPath)]);  // dl:ok dictionary-get-without-check@ee29 -- the key was staged a few lines above in the same routine; a miss is a programming error and should raise -- SLZ-S10 2026-11-22
    pTx.Written:= pTx.Written + [pPath];
  end;

begin
  pTx:= Default(TApplyTransaction);
  Changed:= TList<string>.Create;
  Staged := TDictionary<string, TBytes>.Create;
  try
    try
      { everything is read before anything is written: a missing staged file fails here }
      for var P in DistinctPaths(pTouched) do
      begin
        var Orig:= TFile.ReadAllBytes(P);  // dl:ok taint-path-traversal@d04e -- the path is the operator's own --project, the run's fixed scratch or the Studio root: local input, no privilege crossed
        pTx.Held     := pTx.Held + [P];
        pTx.Originals:= pTx.Originals + [Orig];
        pTx.Stamps   := pTx.Stamps + [TFile.GetLastWriteTimeUtc(P)];
        var Bytes:= pStaged(P);
        if SameBytes(Bytes, Orig) then Continue;
        Changed.Add(P);
        Staged.AddOrSetValue(LowerCase(P), Bytes);
      end;
      var News:= DistinctPaths(pNew);
      for var P in News do
      begin
        if TFile.Exists(P) then raise EInOutError.CreateFmt('the new unit''s file already exists: %s', [P]);
        Staged.AddOrSetValue(LowerCase(P), pStaged(P));
      end;
      if not pNoBackup then BackUpChanged(Changed.ToArray, pProjectDir, pHeader(Changed.Count, Length(News)), pTx);
      Writes:= 0;
      for var P in News do
      begin
        MakeDirs(ExtractFilePath(P), pTx);
        pTx.NewFiles:= pTx.NewFiles + [P];
        WriteOne(P);
      end;
      for var P in Changed do WriteOne(P);
      Result:= True;
    except
      on E: Exception do
      begin
        pTx.Error          := E.Message;
        pTx.RollbackFailure:= RollBack(pTx);
        Result:= False;
      end;
    end;
  finally
    Staged.Free;
    Changed.Free;
  end;
end;

function CompileAfterWith(const pBuildProject, pPlatform, pLogDir: string; const pRepair: TGateRepairFunc): TCompileAfterResult;
begin
  Result:= Default(TCompileAfterResult);
  var Dir:= IncludeTrailingPathDelimiter(pLogDir);
  var B:= RunMsBuild(pBuildProject, pPlatform, Dir + 'after-1.log', 'build after the edit');
  Result.Builds := 1;
  Result.Seconds:= B.Seconds;
  if not B.Ok and Assigned(pRepair) then
  begin
    Result.Repairs:= pRepair(B.Errors);
    if Length(Result.Repairs) > 0 then
    begin
      B:= RunMsBuild(pBuildProject, pPlatform, Dir + Format('after-%d.log', [CGateSecondBuild]), 'build after the repairs');
      Result.Builds := CGateSecondBuild;
      Result.Seconds:= Result.Seconds + B.Seconds;
    end;
  end;
  Result.Ok      := B.Ok;
  Result.Errors  := B.Errors;
  Result.TimedOut:= B.TimedOut;
  Result.Messages:= B.Messages;
end;

function ApplyGated(const pReq: TGateRequest): TGateOutcome;  // dl:ok too-many-exit-points@6b0f -- one guard per named refusal, in the documented order: the exits are the contract
const
  CTestBreakVar  = 'DRAGLINT_GATE_TEST_BREAK';
  CTestBreakLine = #13#10'this line does not compile (DRAGLINT_GATE_TEST_BREAK)'#13#10;
var
  Outcome: TGateOutcome;

  { A refusal after the write: every file goes back. }
  procedure RollBackAs(const pKind, pWhy: string);
  begin
    var Failure:= RollBack(Outcome.Tx);
    Outcome.Refusal:= pKind;
    Outcome.RolledBack:= Failure = '';
    Outcome.RollbackFailed:= Failure <> '';
    Outcome.Detail:= if Failure = '' then pWhy + '; rolled back, project not changed'
                     else pWhy + '; the rollback FAILED: ' + Failure + ' -- the project may be PARTLY changed; recovery.txt names the backups';
  end;

begin
  Outcome:= Default(TGateOutcome);
  GGateVerb:= if pReq.Verb <> '' then pReq.Verb else GGateVerb;
  GRsVars  := pReq.RsVars;
  var Dir:= IncludeTrailingPathDelimiter(pReq.LogDir);
  var AfterFailed:= 'the project';
  var Touched: TArray<string>:= nil;
  var Wanted:= TDictionary<string, TBytes>.Create;
  try
    for var F in pReq.Files do
    begin
      Touched:= Touched + [F.Path];
      Wanted.AddOrSetValue(LowerCase(ExpandFileName(F.Path)), F.Bytes);
    end;
    try
      if not CompilerAvailable then
      begin
        Outcome.Refusal:= CGateCompilerUnavailable;
        Outcome.Detail := 'the RAD Studio build environment was not found (' + BuildEnvBat + '): the compile gate cannot run; nothing written';
        Exit(Outcome);
      end;
      Outcome.Baseline:= RunMsBuild(pReq.Project, pReq.Platform, Dir + 'baseline.log', 'baseline build');
      Outcome.BeforeBuilt   := not Outcome.Baseline.TimedOut;
      Outcome.BeforeMessages:= Outcome.Baseline.Messages;
      if not Outcome.Baseline.Ok then
      begin
        Outcome.Refusal:= if Outcome.Baseline.TimedOut then CGateBuildTimeout else CGateDirtyBaseline;
        Outcome.Detail := Format('the project does not build BEFORE the rewrite (%d dcc line(s), first: %s); nothing written',
          [Length(Outcome.Baseline.Errors), if Length(Outcome.Baseline.Errors) > 0 then Outcome.Baseline.Errors[0] else '']);
        Exit(Outcome);
      end;
      { The other projects that compile these units: one that is already broken would make the after build mean nothing. }
      for var I:= 0 to High(pReq.AlsoProjects) do
      begin
        var Also:= RunMsBuild(pReq.AlsoProjects[I], pReq.Platform, Dir + Format('also%d\baseline.log', [I + 1]), 'baseline build of ' + ExtractFileName(pReq.AlsoProjects[I]));
        Outcome.Baseline.Seconds:= Outcome.Baseline.Seconds + Also.Seconds;
        if Also.Ok then Continue;
        Outcome.Baseline:= Also;
        Outcome.Refusal:= if Also.TimedOut then CGateBuildTimeout else CGateDirtyBaseline;
        Outcome.Detail := Format('%s, which also compiles the rewritten units, does not build BEFORE the rewrite (%d dcc line(s), first: %s); nothing written',
          [pReq.AlsoProjects[I], Length(Also.Errors), if Length(Also.Errors) > 0 then Also.Errors[0] else '']);
        Exit(Outcome);
      end;
    except
      on E: ECompileGateCancelled do
      begin
        Outcome.Refusal:= CGateCancelled;
        Outcome.Detail := 'cancelled -- nothing written';
        Exit(Outcome);
      end;
      on E: Exception do
      begin
        Outcome.Refusal:= CGateBuildError;
        Outcome.Detail := 'the baseline build could not run: ' + E.Message + '; nothing written';
        Exit(Outcome);
      end;
    end;
    if not WriteStaged(Touched, nil, ExtractFilePath(ExpandFileName(pReq.Project)), pReq.NoBackup,
      function(pPath: string): TBytes
      begin
        if not Wanted.TryGetValue(LowerCase(pPath), Result) then raise EInOutError.CreateFmt('nothing staged for %s', [pPath]);
      end,
      function(pChanged, pNew: Integer): string
      begin
        Result:= pReq.Header;
      end, Outcome.Tx) then
    begin
      Outcome.Refusal:= CGateWriteFailed;
      Outcome.RolledBack:= Outcome.Tx.RollbackFailure = '';
      Outcome.RollbackFailed:= not Outcome.RolledBack;
      Outcome.Detail:= if Outcome.RolledBack then 'rolled back, project not changed: ' + Outcome.Tx.Error
                       else 'write failed (' + Outcome.Tx.Error + ') and the rollback FAILED: ' + Outcome.Tx.RollbackFailure;
      Exit(Outcome);
    end;
    try
      if (GetEnvironmentVariable(CTestBreakVar) = '1') and IsUnderTemp(pReq.Project) and (Length(Outcome.Tx.Written) > 0) then
        { at the top: dcc reads nothing after the final end. }
        TFile.WriteAllBytes(Outcome.Tx.Written[0], TEncoding.ASCII.GetBytes(CTestBreakLine) + TFile.ReadAllBytes(Outcome.Tx.Written[0]));  // dl:ok taint-path-traversal@57e9 -- the path is the operator's own --project, the run's fixed scratch or the Studio root: local input, no privilege crossed
      Outcome.After:= CompileAfterWith(pReq.Project, pReq.Platform, Dir, pReq.Repair);
      Outcome.AfterBuilt   := not Outcome.After.TimedOut;
      Outcome.AfterMessages:= Outcome.After.Messages;
      if Outcome.After.Ok then
        for var I:= 0 to High(pReq.AlsoProjects) do
        begin
          var Also:= CompileAfterWith(pReq.AlsoProjects[I], pReq.Platform, Dir + Format('also%d', [I + 1]), nil);
          Also.Builds := Also.Builds + Outcome.After.Builds;
          Also.Seconds:= Also.Seconds + Outcome.After.Seconds;
          Also.Repairs:= Outcome.After.Repairs;
          Outcome.After:= Also;
          if not Also.Ok then
          begin
            AfterFailed:= pReq.AlsoProjects[I];
            Break;
          end;
        end;
    except
      on E: ECompileGateCancelled do
      begin
        RollBackAs(CGateCancelled, 'cancelled');
        Exit(Outcome);
      end;
      on E: Exception do
      begin
        RollBackAs(CGateBuildError, 'the after gate failed: ' + E.Message);
        Exit(Outcome);
      end;
    end;
    if not Outcome.After.Ok then
    begin
      RollBackAs(if Outcome.After.TimedOut then CGateBuildTimeout else CGateCompileError,
        Format('%s does not build after the rewrite (%d dcc line(s), first: %s)',
          [AfterFailed, Length(Outcome.After.Errors), if Length(Outcome.After.Errors) > 0 then Outcome.After.Errors[0] else '']));
      Exit(Outcome);
    end;
    Outcome.Applied:= True;
    Outcome.NewMessages:= NewCompilerMessages(Outcome.BeforeMessages, Outcome.AfterMessages, Outcome.GoneMessages);
  finally
    Wanted.Free;
  end;
  Result:= Outcome;
end;
function OpenGateStandDown(const pVerb, pDb: string): Boolean;
begin
  Result:= False;
  if (GStandDown <> nil) or not ControlChannelEnabledFor(pVerb) then Exit;
  var Ctl:= TControlChannel.Create([ExpandFileName(pDb)], DRAGLINT_VERSION, DRAGLINT_EXTRACTOR_VERSION, pVerb);
  var Err: string;
  if Ctl.Start(Err) then
  begin
    GStandDown  := Ctl;
    GCancelTaken:= False;
    GProgressDb := ExpandFileName(pDb); { the progress lines name the stop-now --db that cancels the run }
    Exit(True);
  end;
  Writeln(ErrOutput, pVerb, ': control channel NOT started (', Err, '); a cancel will kill this run instead of rolling it back');
  Ctl.Free;
end;

procedure CloseGateStandDown;
begin
  if GStandDown = nil then Exit;
  var Ctl:= GStandDown;
  GStandDown:= nil;
  Ctl.StandDownComplete;
  Ctl.Free;
end;
end.
