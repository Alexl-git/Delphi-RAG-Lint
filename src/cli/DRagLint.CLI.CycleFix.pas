unit DRagLint.CLI.CycleFix; // dl:ok unit-too-large@1a23 -- one verb's pipeline (plan, gate, stage, build, write, verify) in one unit by the E18 plan's file list; the split belongs to the T18 whole-branch review

// ---------------------------------------------------------------------------
// `drag-lint cycles --fix` -- the dry run (E18 Task 8): pick ONE circular group,
// take the planner's plan for it (DRagLint.Report.CyclePlan.VisitCyclePlans),
// add the mechanisability gate (stale-file, outside-roots, manual-edit) and
// print the verdict as the playbook text or as `cycle-fix/1` JSON
// (docs\superpowers\plans\2026-10-10-auto-cycle-fix.md, contract 4.4).
// Writes nothing to the project. Since Task 9 a mechanical verdict also stages the plan's result
// in a SHADOW TREE (anchored TTextEdits applied in memory, new units, project files); the
// shadow is what the dry run proves would be written. Since Task 10 the COMPILE GATE builds the untouched
// project first (RunMsBuild; refusal dirty-baseline) and provides the after gate with its bounded repairs R4
// (CompileAfter / TryRepair) for the apply. Since Task 11 --apply writes the shadow into the project
// (WriteAll: all files or none, under backups), builds it in place, rolls back byte-identical on any
// failure (RollBack) and verifies the result against the prediction after a child re-index (VerifyAfter).
// ---------------------------------------------------------------------------

interface

uses
  System.SysUtils, System.Generics.Collections,
  DRagLint.Core.Interfaces, DRagLint.Project.OwnRoots, DRagLint.Report.CyclePlan, DRagLint.Refactor.TextEdit, DRagLint.Refactor.CompileGate; // dl:unit DRagLint.Report.CyclePlan accepted -- uses-global-census counts one shared const (CCycleNone, the no-cycle line both print); the unit is needed anyway for the planner itself (TCyclePlanView, TRefusal, VisitCyclePlans), so the const stays with the planner it belongs to

type
  /// <summary>The `cycles --fix` flags, as DoCycles parsed them.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.CLI.CycleFix.pas) ?, DRagLint.CLI.CycleFix.BaselineCompile (DRagLint.CLI.CycleFix.pas) ?, DRagLint.CLI.CycleFix.ReindexTargetProblem (DRagLint.CLI.CycleFix.pas) ?, DRagLint.CLI.CycleFix.TamperAllowed (DRagLint.CLI.CycleFix.pas) ?, DRagLint.CLI.DoCycles (DRagLint.CLI.pas) (+32 more)</para>
  /// <para>Used in units: DRagLint.CLI, DRagLint.CLI.CycleFix</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TCycleFixOptions = record
    /// <summary>--project: the .dproj (or .dpr) whose own roots bound the edit.</summary>
    Project: string;
    /// <summary>--db: the index of that project.</summary>
    Db: string;
    /// <summary>--platform; '' = the project's active Platform, else win32 (ruling a3; RunCycleFix resolves it).</summary>
    Platform: string;
    /// <summary>--apply: write the chosen group's plan into the project (Task 11); with --part all, loop until the group is gone (Task 12).</summary>
    Apply: Boolean;
    /// <summary>--no-backup (apply only).</summary>
    NoBackup: Boolean;
    /// <summary>--no-reindex (apply only).</summary>
    NoReindex: Boolean;
    /// <summary>--no-compile: skip the baseline build; accepted by the dry run only, refused with --apply.</summary>
    NoCompile: Boolean;
    /// <summary>--cycle: the value given (checked: must be 1 or more).</summary>
    CycleIndex: Integer;
    /// <summary>True when --cycle was on the command line.</summary>
    CycleGiven: Boolean;
    /// <summary>--unit: select the group holding this unit stem; '' = not given.</summary>
    UnitStem: string;
    /// <summary>--part: 'a', 'b', 'all' or '' (the group's default).</summary>
    Part: string;
    /// <summary>Every --library-db as given ('none' or a path); empty = the manifest's library. Passed on to the --part all child runs.</summary>
    LibraryDbs: TArray<string>;
    /// <summary>--rules-dir as given, '' = not given. Passed on to the --part all child runs (the fix itself reads no rule files).</summary>
    RulesDir: string;
    /// <summary>--format json.</summary>
    Json: Boolean;
    /// <summary>--shadow-out (debug): the directory the shadow tree is staged in; '' = DefaultShadowDir.</summary>
    ShadowOut: string;
    /// <summary>--rsvars: the rsvars.bat the compile gate calls; '' = the Studio the registry / BDS names. Passed on to the --part all child runs.</summary>
    RsVars: string;
    /// <summary>--build-timeout, as typed: whole seconds one build of the compile gate may take; '' or '0' =
    /// no limit (the default, owner ruling 2026-10-26: an IDE run has progress and Cancel, and a slow machine
    /// must not abort a result the user waits for). Checked by ResolveSelection; passed on to the --part all
    /// child runs. Test runners and unattended scripts pass an explicit value.</summary>
    BuildTimeout: string;
  end;

  /// <summary>The gate's stand-down exception, under the name this verb's handlers and doc-comments use.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.CLI.CycleFix.ApplyGroup (DRagLint.CLI.CycleFix.pas), DRagLint.CLI.CycleFix.RerunAfterReindex (DRagLint.CLI.CycleFix.pas), DRagLint.CLI.CycleFix.RunAll (DRagLint.CLI.CycleFix.pas), DRagLint.CLI.CycleFix.VerifyAfter (DRagLint.CLI.CycleFix.pas), DRagLint.CLI.CycleFix.VerifyAfterCore (DRagLint.CLI.CycleFix.pas) (+1 more)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  ECycleFixCancelled = ECompileGateCancelled;

  /// <summary>The post-apply verification (VerifyAfter): the child re-index and the comparison.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.CLI.CycleFix.pas) ?, DRagLint.CLI.CycleFix.VerifyAfter (DRagLint.CLI.CycleFix.pas), DRagLint.CLI.CycleFix.VerifyAfterCore (DRagLint.CLI.CycleFix.pas)</para>
  /// <para>Used in units: DRagLint.CLI.CycleFix</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TVerifyResult = record
    /// <summary>done | failed | skipped (--no-reindex, or the target guard refused the DB) | dry-run.</summary>
    ReindexStatus: string;
    /// <summary>Why the re-index was skipped or failed; ''.</summary>
    ReindexReason: string;
    /// <summary>The DB re-indexed (the run's --db).</summary>
    ReindexDb: string;
    /// <summary>The project file the DB records.</summary>
    ReindexProject: string;
    /// <summary>Milliseconds of the child re-index.</summary>
    ReindexMs: Int64;
    /// <summary>What `cycles` printed on the re-indexed DB; '' when it did not run.</summary>
    Actual: string;
    /// <summary>True when Actual equals the prediction, order-insensitively on groups.</summary>
    Verified: Boolean;
    /// <summary>'' when verified; else `not re-indexed`, `re-index failed` or `the cycles output differs from the prediction`.</summary>
    Reason: string;
  end;

/// <summary>The baseline gate: builds the UNTOUCHED project before anything is staged.</summary>
/// <param name="pOpts">The flags (Project, Platform).</param>
/// <param name="pLogDir">Folder for the build's .bat and log (BuildScratchDir).</param>
/// <returns>The build outcome; not Ok means the refusal `dirty-baseline`.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.CycleFix.PassBaselineGate (DRagLint.CLI.CycleFix.pas)</para>
/// <para>Calls: DRagLint.Refactor.CompileGate.RunMsBuild, IncludeTrailingPathDelimiter</para>
/// <para>Returns: RunMsBuild(pOpts.Project, pOpts.Platform, IncludeTrailingPathDelimiter(pLogDir) + 'baseline.log', 'baseline build')</para>
/// <seealso cref="DRagLint.Refactor.CompileGate.RunMsBuild"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function BaselineCompile(const pOpts: TCycleFixOptions; const pLogDir: string): TBuildOutcome;

/// <summary>The bounded repairs R4: one pass over the dcc lines of a failed after-build.</summary>
/// <param name="pView">The plan that was written.</param>
/// <param name="pErrors">The dcc lines of the failed build (RunMsBuild.Errors).</param>
/// <param name="pProjectDir">The project folder the plan's paths live in.</param>
/// <param name="pTreeDir">The folder that was built: pProjectDir itself (apply, in place) or a
/// copy laid out like it (the files are found by the shadow mapping, ShadowPathOf).</param>
/// <returns>The repairs made, one per repaired dcc line; empty = nothing repairable (no retry).</returns>
/// <remarks>
/// Only files the plan edits or creates are changed, in their own encoding (DecodeSource /
/// EncodeSource). The rules, each on a line the plan wrote: `E2003 Undeclared identifier: 'X'` where X
/// is a moved symbol (its leaf) or the interface / pointer type / pointer variable (InversionUnit) -&gt;
/// that unit is added to the uses clause of the section holding the line (first entry; a section
/// without uses gets one); `E2015` on a line with `&lt;expr&gt; as &lt;IfaceName&gt;` -&gt; the expression is
/// cast through CastAncestor; `E2010 ... 'Procedure'` on the `PtrVar :=` assignment -&gt; the
/// declaration of PtrType is re-emitted as PtrTypeDecl (the routine's signature verbatim). Any other
/// code, and an R4 code whose condition does not hold, is left alone. Lines dcc prints as a CASCADE of
/// a repaired one (E2003 on a member inside a broken `with`, E2066, F2063) do not block the retry:
/// the second build decides.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.CycleFix.CompileAfter (DRagLint.CLI.CycleFix.pas), DRagLint.CLI.CycleFix.RunRepairProbe (DRagLint.CLI.CycleFix.pas)</para>
/// <para>Calls: ContainsText, Copy, DRagLint.CLI.CycleFix.TryRepair.AddRepair, DRagLint.CLI.CycleFix.TryRepair.FileOf, DRagLint.CLI.CycleFix.TryRepair.QueueUses, DRagLint.CLI.CycleFix.TryRepair.RepairCast, DRagLint.CLI.CycleFix.TryRepair.RepairPointer, DRagLint.CLI.CycleFix.TryRepair.Resolve, DRagLint.Refactor.CompileGate.AddToUses, DRagLint.Refactor.CompileGate.ParseDccLine (+12 more)</para>
/// <para>Returns: Repairs.ToArray</para>
/// <para>Complexity: 11 (cyclomatic, outer body), 146 lines (full implementation)</para>
/// <seealso cref="DRagLint.CLI.CycleFix.TryRepair.AddRepair"/>
/// <seealso cref="DRagLint.CLI.CycleFix.TryRepair.FileOf"/>
/// <seealso cref="DRagLint.CLI.CycleFix.TryRepair.QueueUses"/>
/// <seealso cref="DRagLint.CLI.CycleFix.TryRepair.RepairCast"/>
/// <seealso cref="DRagLint.CLI.CycleFix.TryRepair.RepairPointer"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function TryRepair(const pView: TCyclePlanView; const pErrors: TArray<string>;
  const pProjectDir, pTreeDir: string): TArray<TRepair>;

/// <summary>The after gate: builds the written project, repairs once (TryRepair) and builds again.</summary>
/// <param name="pView">The plan that was written.</param>
/// <param name="pProjectDir">The project folder the plan's paths live in.</param>
/// <param name="pBuildProject">The .dproj to build: the project itself (apply) or the same project in a copy.</param>
/// <param name="pPlatform">As RunMsBuild.</param>
/// <param name="pLogDir">Folder for the .bat and logs (after-1.log, after-2.log).</param>
/// <returns>Ok, the last build's errors, the repairs and the build count and time.</returns>
/// <remarks>
/// Rolls nothing back: on not Ok the caller (Task 11's apply) restores its backups, which
/// cover every file TryRepair may touch.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.CycleFix.ApplyGroup (DRagLint.CLI.CycleFix.pas), DRagLint.CLI.CycleFix.RunRepairProbe (DRagLint.CLI.CycleFix.pas)</para>
/// <para>Calls: DRagLint.CLI.CycleFix.TryRepair, DRagLint.Refactor.CompileGate.CompileAfterWith, ExpandFileName, ExtractFilePath</para>
/// <seealso cref="DRagLint.CLI.CycleFix.TryRepair"/>
/// <seealso cref="DRagLint.Refactor.CompileGate.CompileAfterWith"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function CompileAfter(const pView: TCyclePlanView; const pProjectDir, pBuildProject, pPlatform,
  pLogDir: string): TCompileAfterResult;

/// <summary>Writes the staged shadow into the project: all files or none.</summary>
/// <param name="pView">The plan that was staged.</param>
/// <param name="pProjectDir">The project folder; the plan's paths map into the shadow by ShadowPathOf.</param>
/// <param name="pShadowDir">The shadow StageShadow filled (staged WITHOUT the tamper seam).</param>
/// <param name="pNoBackup">--no-backup: no `.BCK&lt;n&gt;` copies and no recovery.txt.</param>
/// <param name="pTx">Receives what was written and what a rollback needs.</param>
/// <returns>True when every file was written; False when anything failed, in which case the
/// project is already rolled back (pTx.Error says why, pTx.RollbackFailure what could not be restored).</returns>
/// <exception cref="EInOutError"><!-- drag-lint:auto exc -->the shadow holds no staged copy of %s (%s); via DRagLint.Refactor.CompileGate.WriteStaged: the new unit's file already exists: %s</exception>
/// <remarks>
/// Order: every touched file's original bytes are read into memory; unless pNoBackup each
/// changed file is copied to its NextBackupName sibling and a recovery.txt block is appended
/// (AppendRecoveryBlock) BEFORE any write; then the new files are written, then the changed
/// files (the .dpr / .dproj among them). A file whose staged bytes equal the original is not
/// written. Each write passes FailWriteForTests (DRAGLINT_TEST_FAIL_WRITE_AT).
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.CycleFix.ApplyGroup (DRagLint.CLI.CycleFix.pas)</para>
/// <para>Calls: DRagLint.CLI.CycleFix.ShadowPathOf, DRagLint.Refactor.CompileGate.WriteStaged, Format, FormatDateTime</para>
/// <para>Touches: file system</para>
/// <seealso cref="DRagLint.CLI.CycleFix.ShadowPathOf"/>
/// <seealso cref="DRagLint.Refactor.CompileGate.WriteStaged"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function WriteAll(const pView: TCyclePlanView; const pProjectDir, pShadowDir: string; pNoBackup: Boolean;
  out pTx: TApplyTransaction): Boolean;

/// <summary>The post-apply verification: re-index the project DB in a child process, run
/// `cycles` on it and compare with the plan's prediction.</summary>
/// <param name="pView">The plan that was applied (Predicted).</param>
/// <param name="pOpts">The flags (Db, Project, NoReindex).</param>
/// <param name="pStore">The run's index of pOpts.Db; read for the target guard only.</param>
/// <returns>The re-index status and the verdict; never raises.</returns>
/// <remarks>
/// Target guard: the child `index --project &lt;P&gt; --db &lt;D&gt;` runs only when D is a
/// PROJECT index (scan_type) holding exactly one project file, that file is pOpts.Project, and D
/// indexes every unit (.pas) the plan edits -- else skipped with the reason and nothing is written to
/// any DB. --no-reindex skips it. Without a re-index Verified is False, Reason `not re-indexed`.
/// A mismatch keeps the files (they compiled; the prediction is the suspect).
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.CycleFix.ApplyGroup (DRagLint.CLI.CycleFix.pas)</para>
/// <para>Calls: Default, DRagLint.CLI.CycleFix.VerifyAfterCore</para>
/// <para>Returns: VerifyAfterCore(pView, pOpts, pStore); Default(TVerifyResult)</para>
/// <para>Catches: ECycleFixCancelled (re-raise); Exception (swallowed)</para>
/// <seealso cref="DRagLint.CLI.CycleFix.VerifyAfterCore"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function VerifyAfter(const pView: TCyclePlanView; const pOpts: TCycleFixOptions;
  const pStore: ISymbolStore): TVerifyResult;

/// <summary>Compares two `cycles` outputs the way the scorer does (Task 2 rule).</summary>
/// <param name="pPredicted">The plan's prediction.</param>
/// <param name="pActual">What `cycles` printed.</param>
/// <returns>True when they are equal after dropping blank and informational lines and sorting the
/// units inside each group line and the group lines themselves (a SET of groups).</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.CycleFix.VerifyAfterCore (DRagLint.CLI.CycleFix.pas)</para>
/// <para>Calls: CyclesLines, DRagLint.CLI.CycleFix.SameCyclesOutput.Normalized</para>
/// <para>Returns: Normalized(pPredicted) = Normalized(pActual)</para>
/// <seealso cref="DRagLint.CLI.CycleFix.SameCyclesOutput.Normalized"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function SameCyclesOutput(const pPredicted, pActual: string): Boolean;

/// <summary>The DRAGLINT_CYCLEFIX_BREAK test seam: 1 to 4 when set AND the project file lies under
/// %TEMP% or C:\TEMP, else 0.</summary>
/// <param name="pOpts">The flags.</param>
/// <returns>The break mode to apply to the plan before staging (ApplyTestBreak), or 0.</returns>
/// <remarks>
/// Honoured on the dry run and the apply alike (Task 11 proves the after gate with it); the
/// caller prints `TEST BREAK active` to stderr when it is not 0.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.CycleFix.AnnounceSeams (DRagLint.CLI.CycleFix.pas), DRagLint.CLI.CycleFix.ApplyGroup (DRagLint.CLI.CycleFix.pas)</para>
/// <para>Calls: DRagLint.Refactor.CompileGate.IsUnderTemp, GetEnvironmentVariable, StrToIntDef</para>
/// <para>Returns: StrToIntDef(GetEnvironmentVariable('DRAGLINT_CYCLEFIX_BREAK'), 0); 0</para>
/// <seealso cref="DRagLint.Refactor.CompileGate.IsUnderTemp"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function BreakSeam(const pOpts: TCycleFixOptions): Integer;

/// <summary>Spoils a plan the way a planner bug would, so the after gate has something to repair.</summary>
/// <param name="pView">The plan.</param>
/// <param name="pMode">1: a `&lt;Anc&gt;(expr) as I...` line loses its cast (dcc E2015); 2: the pointer
/// type is emitted as `reference to function(...)` without its `const` -- TFunc's own definition,
/// spelled inline because TFunc itself needs System.SysUtils (measured: E2003 'TFunc&lt;,&gt;') -- (dcc
/// E2010 '...' and 'Procedure' on the pointer assignment); 3: every new unit gets a stray line after
/// `interface` that no repair covers (the after gate fails, the apply rolls back). Any other value: unchanged.</param>
/// <returns>A copy; pView's arrays are not modified.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.CycleFix.RunCycleFixGroups (DRagLint.CLI.CycleFix.pas)</para>
/// <para>Calls: Copy, DRagLint.CLI.CycleFix.BrokenLines, Insert, SameText, Trim</para>
/// <para>Returns: pView</para>
/// <seealso cref="DRagLint.CLI.CycleFix.BrokenLines"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ApplyTestBreak(const pView: TCyclePlanView; pMode: Integer): TCyclePlanView;

/// <summary>The refusals the front end adds to the planner's own: outside-roots.</summary>
/// <param name="pView">The plan of one group.</param>
/// <param name="pOwn">The project's own roots (TOwnRoots.Load of the project folder).</param>
/// <returns>One refusal per touched file that is empty or outside every root.</returns>
/// <remarks>
/// Pure: reads no file. stale-file needs the index and is added by RunCycleFix.
/// manual-edit is NOT added here: the planner's own refusals already name every manual
/// edit (TCyclePlanner.CaptureRefusals walks every touched file and the .dproj), so a gate
/// copy could never fire. TOwnRoots.IsOurs lets an empty path through, so an empty touched
/// path is refused explicitly.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.CycleFix.RunCycleFixGroups (DRagLint.CLI.CycleFix.pas)</para>
/// <para>Calls: DRagLint.CLI.CycleFix.MakeRefusal, DRagLint.Project.OwnRoots.TOwnRoots.IsOurs</para>
/// <para>Returns: L.ToArray</para>
/// <seealso cref="DRagLint.CLI.CycleFix.MakeRefusal"/>
/// <seealso cref="DRagLint.Project.OwnRoots.TOwnRoots.IsOurs"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function MechanisabilityGate(const pView: TCyclePlanView; const pOwn: TOwnRoots): TArray<TRefusal>;

/// <summary>The default shadow directory: C:\TEMP\draglint_cyclefix_&lt;pid&gt;\. RunCycleFix deletes it, and the gate's _build dir, when the run ends unless DRAGLINT_CYCLEFIX_KEEP_SCRATCH=1; a --shadow-out directory is never deleted.</summary>
/// <returns>The directory name with a trailing path delimiter; nothing is created.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.CycleFix.RunCycleFixGroups (DRagLint.CLI.CycleFix.pas)</para>
/// <para>Calls: DRagLint.Refactor.CompileGate.FreshScratchName</para>
/// <para>Returns: GShadowPick</para>
/// <seealso cref="DRagLint.Refactor.CompileGate.FreshScratchName"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function DefaultShadowDir: string;

/// <summary>Turns the edits of a plan into anchored TTextEdits.</summary>
/// <param name="pView">The plan of one group.</param>
/// <returns>Per edit of an existing file: a replace or delete becomes delete-lines (First..Last)
/// plus, for a replace, insert-lines after First-1; an insert-after becomes insert-lines after the
/// anchor line. Each carries ExpectLine/ExpectText (the first line of the plan's "Current text", or
/// the anchor line's text) as the applier's stale guard. A line that is blank or starts a comment
/// cannot be guarded by the applier (it never accepts a comment line as an anchor) and is left
/// unguarded; StageShadow checks every line exactly instead. Manual edits are skipped.</returns>
/// <remarks>
/// Pure. Per file the edits are in top-to-bottom order of the playbook's list reversed, so
/// edits that tie on a line land in the file in the order a follower of the playbook produces.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.CycleFix.StageShadow (DRagLint.CLI.CycleFix.pas)</para>
/// <para>Calls: Default, DRagLint.CLI.CycleFix.GuardText, DRagLint.CLI.CycleFix.ToTextEdits.Make, SameText</para>
/// <para>Returns: L.ToArray</para>
/// <seealso cref="DRagLint.CLI.CycleFix.GuardText"/>
/// <seealso cref="DRagLint.CLI.CycleFix.ToTextEdits.Make"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ToTextEdits(const pView: TCyclePlanView): TArray<TTextEdit>;

/// <summary>Stages the result of a plan in a shadow directory without touching the project.</summary>
/// <param name="pView">The plan of one group.</param>
/// <param name="pProjectDir">The project folder; the shadow mirrors paths relative to it.
/// A file outside it is staged under `_outside\&lt;drive&gt;\...`.</param>
/// <param name="pShadowDir">Receives the staged files; existing files of the same name are overwritten.</param>
/// <param name="pTamperAllowed">True only on a dry run, to let the DRAGLINT_CYCLEFIX_TEST_TAMPER test seam alter the staged text (see TamperAllowed); every call that feeds a write must pass False.</param>
/// <returns>The refusals (kind anchor-mismatch) or an empty array when the shadow was written.</returns>
/// <remarks>
/// Everything is computed in memory first; nothing is written when any refusal arises.
/// Refuses when a file is missing or a line of it differs from the plan's "Current text" / anchor
/// (compared exactly, as the follow-cycle-plan oracle does), when TTextEditApplier.RefusalOf finds
/// the edit set unappliable, when the applier drops an edit (line count check), or when a new unit's
/// file already exists. Edited files are written ANSI with the applier's CRLF; new units ASCII,
/// CRLF, one trailing CRLF.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.CycleFix.StageFor (DRagLint.CLI.CycleFix.pas)</para>
/// <para>Calls: DRagLint.CLI.CycleFix.AnchorRefusal, DRagLint.CLI.CycleFix.ApplyTestTamper, DRagLint.CLI.CycleFix.CheckAnchors, DRagLint.CLI.CycleFix.CheckInsertedText, DRagLint.CLI.CycleFix.EscapeInsertedText, DRagLint.CLI.CycleFix.HasNonAscii, DRagLint.CLI.CycleFix.NetLineChange, DRagLint.CLI.CycleFix.ShadowPathOf, DRagLint.CLI.CycleFix.ToTextEdits, DRagLint.Refactor.TextEdit.TTextEditApplier.ApplyToText (+6 more)</para>
/// <para>Returns: Refs.ToArray</para>
/// <para>Touches: file system</para>
/// <seealso cref="DRagLint.CLI.CycleFix.AnchorRefusal"/>
/// <seealso cref="DRagLint.CLI.CycleFix.ApplyTestTamper"/>
/// <seealso cref="DRagLint.CLI.CycleFix.CheckAnchors"/>
/// <seealso cref="DRagLint.CLI.CycleFix.CheckInsertedText"/>
/// <seealso cref="DRagLint.CLI.CycleFix.EscapeInsertedText"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function StageShadow(const pView: TCyclePlanView; const pProjectDir, pShadowDir: string;
  pTamperAllowed: Boolean = False): TArray<TRefusal>;

/// <summary>True when the DRAGLINT_CYCLEFIX_TEST_TAMPER test seam may act: on a dry run only.</summary>
/// <param name="pOpts">The flags.</param>
/// <returns>False whenever --apply is set, whatever the environment says.</returns>
/// <remarks>
/// The seam alters staged text without any anchor guard seeing it, so no write path may honour it.
/// Task 11: the apply writes from the shadow; every StageShadow call that feeds a write must pass
/// pTamperAllowed = False (the default).
/// <!-- drag-lint:auto -->The text the applier's stale guard can hold: '' for a blank line or one
/// that starts a comment (AnchorIsValid never accepts a comment line as an anchor).
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.CycleFix.AnnounceSeams (DRagLint.CLI.CycleFix.pas), DRagLint.CLI.CycleFix.StageFor (DRagLint.CLI.CycleFix.pas)</para>
/// <para>Returns: not pOpts.Apply</para>
/// <para>Effect-free (proven)</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function TamperAllowed(const pOpts: TCycleFixOptions): Boolean;

/// <summary>Runs `cycles --fix` (dry run, or --apply) and prints the result to stdout.</summary>
/// <param name="pOpts">The flags.</param>
/// <param name="pStore">Open index of the project; read only (a child process re-indexes it after --apply).</param>
/// <param name="pSccs">The circular groups, lower-case stems.</param>
/// <param name="pGraph">The uses graph the groups come from.</param>
/// <param name="pLibStore">Platform library index (read only) or nil.</param>
/// <returns>Dry run: 0 mechanical, 1 refused, 2 error (bad flags, no such group). --apply: 0 applied
/// (and verified, or --no-reindex), 1 refused / rolled back after a compile error or build timeout /
/// applied but not verified, 2 error (a write failed part-way: rolled back, project not changed).</returns>
/// <remarks>
/// The dry run writes no source file of the project; unless --no-compile, the baseline build writes what any build
/// of the project writes (dcu, exe) and refuses the run (dirty-baseline, exit 1) when it fails. The first mechanical group is chosen when neither --cycle nor --unit is given.
/// --apply: baseline gate, stage the shadow, WriteAll, CompileAfter in place (at most one repair),
/// then RollBack (compile-error / build-timeout) or VerifyAfter.
/// --part all (needs --apply, not --no-reindex; Task 12): the group is --cycle N / the one holding --unit / cycle 1. Each iteration is
/// one child `cycles --fix --apply --unit` (so ApplyGroup, planned on the index the last iteration re-indexed); its cycle object is
/// appended to the JSON `cycles[]`. The loop ends when no unit of the group is circular any more (exit 0), when an iteration fails
/// (its code is the exit code; earlier iterations stay applied), when an iteration wrote nothing ("no edge is cuttable", exit 1)
/// or after as many iterations as the group had edges (exit 1).
/// CANCEL (lane X-BT): for the whole run the engine listens on the maintenance control channel
/// (DRagLint.Core.ControlChannel; `drag-lint shutdown`, the IDE's Cancel). A stand-down request is taken while
/// the run waits on a child: a build or re-index child is killed, a child `cycles --fix` (--part all, the A1
/// re-run) is asked to stand down in turn. After WriteAll every written file is rolled back (refusal
/// `cancelled`, "cancelled -- rolled back"); before it nothing was written ("cancelled -- nothing written").
/// Both exit 1; a rollback that fails exits 2. A request that arrives when no child is left to wait on is
/// answered when the run ends, with its own result.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.DoCycles (DRagLint.CLI.pas)</para>
/// <para>Calls: DRagLint.CLI.CycleFix.DeleteDefaultScratch, DRagLint.CLI.CycleFix.ReportCancelledBeforeWrite, DRagLint.CLI.CycleFix.RerunAfterReindex, DRagLint.CLI.CycleFix.RunAllSelected, DRagLint.CLI.CycleFix.RunCycleFixGroups, DRagLint.CLI.CycleFix.StartStandDownChannel, DRagLint.Core.ControlChannel.TControlChannel.StandDownComplete, ExpandFileName, SameText</para>
/// <para>Returns: CExitError; RunAllSelected(pOpts, pSccs, pGraph); RunCycleFixGroups(pOpts, pStore, pSccs, pGraph, pLibStore); CExitRefused</para>
/// <para>Catches: ECycleFixCancelled (swallowed)</para>
/// <seealso cref="DRagLint.CLI.CycleFix.DeleteDefaultScratch"/>
/// <seealso cref="DRagLint.CLI.CycleFix.ReportCancelledBeforeWrite"/>
/// <seealso cref="DRagLint.CLI.CycleFix.RerunAfterReindex"/>
/// <seealso cref="DRagLint.CLI.CycleFix.RunAllSelected"/>
/// <seealso cref="DRagLint.CLI.CycleFix.RunCycleFixGroups"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function RunCycleFix(const pOpts: TCycleFixOptions; const pStore: ISymbolStore;
  const pSccs: TList<TArray<string>>; const pGraph: TCycleGraph;
  const pLibStore: ISymbolStore = nil): Integer;

/// <summary>Reports a `cycles --fix` error that ends the run before RunCycleFix is reached
/// (e.g. the platform library does not open): with pOpts.Json a `cycle-fix/1` document
/// {schema, error, ok:false, exit_code:2} on stdout, else `ERROR: <message>`.</summary>
/// <param name="pOpts">The run's options; only Json is read.</param>
/// <param name="pMessage">The error, one line.</param>
/// <remarks>
/// The caller exits 2. E18 final review M1: a JSON caller (the IDE) must get a
/// document it can parse, never plain text.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.DoCycles (DRagLint.CLI.pas)</para>
/// <para>Calls: DRagLint.CLI.CycleFix.ReportError</para>
/// <seealso cref="DRagLint.CLI.CycleFix.ReportError"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure ReportCycleFixError(const pOpts: TCycleFixOptions; const pMessage: string);

implementation

uses
  DRagLint.Core.FileTime,
  System.Classes, System.IOUtils, System.JSON, System.DateUtils, System.Hash,
  System.StrUtils, System.RegularExpressions, System.Diagnostics, System.Math, Winapi.Windows,
  DRagLint.CLI.LibraryReady,    // PlatformOfDproj: the project's active Platform (ruling a3)
  DRagLint.Core.ControlChannel, // lane X-BT: the stand-down request (Cancel) the run listens for
  DRagLint.Core.Model;          // DRAGLINT_VERSION / DRAGLINT_EXTRACTOR_VERSION, what the channel's `status` reports

const
  CExitMechanical = 0;
  CExitRefused    = 1;
  CExitError      = 2;
  CNoPlatform      = 'win32';  // ruling a3: neither --platform nor the project names one (Delphi 7 / 2007..XE)
  CSchema          = 'cycle-fix/1';
  CNeedsProject    = 'cycles --fix needs --project <X.dproj>';
  CVerdictOk       = 'Verdict: mechanical (dry run; add --apply to write)';
  CVerdictRefused  = 'Verdict: refused';
  CShadowLine      = 'Shadow tree: ';
  CMaxAsciiOrd     = 127;  // the last ASCII code point
  CTamperParts     = 3;    // File.pas|from|to
  CBreakCast       = 1;    // DRAGLINT_CYCLEFIX_BREAK=1: drop the cast before `as I...`
  CBreakPointer    = 2;    // DRAGLINT_CYCLEFIX_BREAK=2: the pointer type as a reference type
  CSecondBuild     = 2;    // CompileAfter builds at most twice
  CJsonDecimals    = -2;   // seconds in the JSON, to 1/100
  CProbeWithLines  = 2;    // DRAGLINT_CYCLEFIX_REPAIR_PROBE=<tree>|<errors file>
  CBreakNoRepair   = 3;    // DRAGLINT_CYCLEFIX_BREAK=3: a stray line in every new unit, no repair covers it
  CBreakRaise      = 4;    // DRAGLINT_CYCLEFIX_BREAK=4 (--apply): the after gate raises once the files are written
  { No default limit on a build (owner ruling 2026-10-26, lane X-BT): the IDE shows progress and has
    Cancel, and a slow machine must not abort a result the user waits for. --build-timeout <s> sets one;
    tests\autotest\run_cyclefix_timeouts.ps1 pins this default. }
  CDefaultBuildTimeoutS = 0; // seconds; 0 = no limit
  CMsPerSec         = 1000;
  CMaxBuildTimeoutS = High(Cardinal) div CMsPerSec - 1; // --build-timeout ceiling (~49 days): below INFINITE in ms
  { the C9 bound of convert-apply's child re-index (RefreshProjectIndex): ten minutes }
  CReindexTimeoutMs = 10 * 60 * 1000;
  CPartAll          = 'all';
  CReindexSteps     = 3; // the re-index steps of one --apply: the A1 pre-plan re-index, VerifyAfterCore's re-index and `cycles`
  CKillMarginMs     = 10 * 60 * 1000; // slack above one --apply's own limits for start-up, writes and backups
  CExitApplyUnverified = 1; // --apply: written and compiled, but not verified

function MakeRefusal(const pKind, pSymbol, pFile, pReason: string; pLine: Integer): TRefusal;
begin
  Result.Kind    := pKind;
  Result.Symbol  := pSymbol;
  Result.FilePath:= pFile;
  Result.Reason  := pReason;
  Result.Line    := pLine;
end;

function MechanisabilityGate(const pView: TCyclePlanView; const pOwn: TOwnRoots): TArray<TRefusal>;
var
  L: TList<TRefusal>;
begin
  L:= TList<TRefusal>.Create;
  try
    for var P in pView.TouchedPaths do
      if (P = '') or not pOwn.IsOurs(P) then
        L.Add(MakeRefusal('outside-roots', '', P, 'the plan edits a file outside the project''s own roots', 0));
    Result:= L.ToArray;
  finally
    L.Free;
  end;
end;

// True when APath's on-disk (mtime, sha) is what the index recorded; the same basis as
// DRagLint.Core.Indexer.IndexFile (raw bytes, ANSI-decoded for the sha).
function FileStampIsCurrent(const pStore: ISymbolStore; const pPath: string): Boolean;
begin
  if not TFile.Exists(pPath) then Exit(False);
  var Sha  := THashSHA2.GetHashString(TEncoding.ANSI.GetString(TFile.ReadAllBytes(pPath)));
  var Mtime:= FileMTimeUnix(pPath);
  Result:= pStore.FileIsUpToDate(pPath, Mtime, Sha);
end;

function StaleRefusals(const pStore: ISymbolStore; const pView: TCyclePlanView): TArray<TRefusal>;
var
  L: TList<TRefusal>;
begin
  L:= TList<TRefusal>.Create;
  try
    for var P in pView.TouchedPaths do
      if MatchText(ExtractFileExt(P), ['.pas', '.dpr']) and not FileStampIsCurrent(pStore, P) then
        L.Add(MakeRefusal('stale-file', '', P,
          if GetEnvironmentVariable('DRAGLINT_CYCLEFIX_REINDEXED') <> '' then
            'the file is still stale after a re-index: another process writes it' else
            'the file changed after it was indexed; reindex the project (drag-lint index --project ...) and retry', 0));
    Result:= L.ToArray;
  finally
    L.Free;
  end;
end;

var
  GShadowPick: string; // the default shadow dir this process picked (never one that existed); '' = not asked yet
  GBuildPick : string; // the same for the compile gate's _build dir

function DefaultShadowDir: string;
begin
  if GShadowPick = '' then GShadowPick:= FreshScratchName('');
  Result:= GShadowPick;
end;

// The text the applier's stale guard can hold: '' for a blank line or one that starts a comment
// (AnchorIsValid never accepts a comment line as an anchor).
function TamperAllowed(const pOpts: TCycleFixOptions): Boolean;
begin
  Result:= not pOpts.Apply;
end;

function GuardText(const pLine: string): string;
begin
  Result:= Trim(pLine);
  if (Result <> '') and (StartsStr('//', Result) or StartsStr('{', Result) or StartsStr('(*', Result)) then
    Result:= '';
end;

function ToTextEdits(const pView: TCyclePlanView): TArray<TTextEdit>;
var
  L: TList<TTextEdit>;

  function Make(pKind: TTextEditKind; const pPath: string; pLine, pEndLine: Integer; const pText, pGuard: string;
    pGuardLine: Integer): TTextEdit;
  begin
    Result:= Default(TTextEdit);
    Result.FilePath  := pPath;
    Result.Kind      := pKind;
    Result.Line      := pLine;
    Result.EndLine   := pEndLine;
    Result.Text      := pText;
    Result.ExpectText:= pGuard;
    Result.ExpectLine:= if pGuard = '' then 0 else pGuardLine;
  end;

begin
  L:= TList<TTextEdit>.Create;
  try
    for var I:= High(pView.Edits) downto 0 do
    begin
      var E:= pView.Edits[I];
      if SameText(E.Kind, 'delete') or SameText(E.Kind, 'replace') then
      begin
        var Guard:= if Length(E.CurrentLines) > 0 then GuardText(E.CurrentLines[0]) else '';
        L.Add(Make(tekDeleteLines, E.FilePath, E.First, E.Last, '', Guard, E.First));
        if (E.Kind = 'replace') and (Length(E.NewLines) > 0) then
          L.Add(Make(tekInsertLines, E.FilePath, E.First - 1, 0, string.Join(#13#10, E.NewLines), Guard, E.First));
      end
      else if SameText(E.Kind, 'insert') and (Length(E.NewLines) > 0) then
        L.Add(Make(tekInsertLines, E.FilePath, E.First, 0, string.Join(#13#10, E.NewLines), GuardText(E.AnchorText), E.First));
    end;
    Result:= L.ToArray;
  finally
    L.Free;
  end;
end;

// The shadow path of pPath: relative to the project folder, else _outside\<drive>\rest.
function ShadowPathOf(const pShadowDir, pProjectDir, pPath: string): string;
begin
  var Full:= ExpandFileName(pPath);
  var Root:= IncludeTrailingPathDelimiter(ExpandFileName(pProjectDir));
  if StartsText(Root, Full) then Result:= Copy(Full, Length(Root) + 1, MaxInt)
  else Result:= '_outside\' + StringReplace(Full, ':', '', [rfReplaceAll]);
  Result:= IncludeTrailingPathDelimiter(pShadowDir) + TrimLeft(Result);
end;

function AnchorRefusal(const pFile, pReason: string; pLine: Integer): TRefusal;
begin
  Result:= MakeRefusal('anchor-mismatch', '', pFile, pReason, pLine);
end;

// Exact check of every edit of one file against the lines on disk; adds a refusal per mismatch.
procedure CheckAnchors(const pPath: string; const pView: TCyclePlanView; pLines: TStrings; pOut: TList<TRefusal>);
begin
  for var E in pView.Edits do
  begin
    if not SameText(E.FilePath, pPath) then Continue;
    if SameText(E.Kind, 'insert') then
    begin
      if (E.First < 1) or (E.First > pLines.Count) then
        pOut.Add(AnchorRefusal(pPath, Format('anchor line %d is beyond the end of the file (%d lines)', [E.First, pLines.Count]), E.First))
      else if Trim(pLines[E.First - 1]) <> Trim(E.AnchorText) then
        pOut.Add(AnchorRefusal(pPath, Format('the anchor line differs from the plan: expected [%s], found [%s]',
          [Trim(E.AnchorText), Trim(pLines[E.First - 1])]), E.First));
    end
    else if SameText(E.Kind, 'delete') or SameText(E.Kind, 'replace') then
    begin
      if Length(E.CurrentLines) <> E.Last - E.First + 1 then
        pOut.Add(AnchorRefusal(pPath, Format('the plan lists %d current line(s) for lines %d-%d',
          [Length(E.CurrentLines), E.First, E.Last]), E.First))
      else
        for var K:= 0 to High(E.CurrentLines) do
        begin
          var No:= E.First + K;
          if (No > pLines.Count) or (pLines[No - 1] <> E.CurrentLines[K]) then
          begin
            pOut.Add(AnchorRefusal(pPath, Format('line %d differs from the plan''s "Current text": expected [%s], found [%s]',
              [No, E.CurrentLines[K], if No > pLines.Count then '<end of file>' else pLines[No - 1]]), No));
            Break;
          end;
        end;
    end;
  end;
end;

// Lines the edits of pPath add minus lines they delete.
function NetLineChange(const pPath: string; const pEdits: TArray<TTextEdit>): Integer;
begin
  Result:= 0;
  for var E in pEdits do
  begin
    if not SameText(E.FilePath, pPath) then Continue;
    if E.Kind = tekDeleteLines then Dec(Result, E.EndLine - E.Line + 1)
    else Inc(Result, Length(E.Text.Replace(#13#10, #10).Split([#10])));
  end;
end;

function HasNonAscii(const pLines: TArray<string>): Boolean;
begin
  Result:= False;
  for var Ln in pLines do
    for var Ch in Ln do
      if Ord(Ch) > CMaxAsciiOrd then Exit(True);
end;

// Test seam, inert unless DRAGLINT_CYCLEFIX_TEST_TAMPER = 'File.pas|from|to' is set: replaces the first
// occurrence of `from` in that file's text as staging reads it (in memory only), so a runner can make the
// file differ from what the planner saw -- the one way to reach the anchor-mismatch refusal.
procedure ApplyTestTamper(const pPath: string; var pContent: string);
begin
  var Spec:= GetEnvironmentVariable('DRAGLINT_CYCLEFIX_TEST_TAMPER').Split(['|']);
  if (Length(Spec) = CTamperParts) and SameText(ExtractFileName(pPath), Spec[0]) then
    pContent:= StringReplace(pContent, Spec[1], Spec[2], []);
end;

// C6: the first character of pLines that pEnc does not represent (its round trip through pEnc changes
// the text), as U+XXXX; '' when the encoding carries every line faithfully.
function UnrepresentableChar(const pLines: TArray<string>; pEnc: TEncoding): string;
begin
  Result:= '';
  for var Ln in pLines do
  begin
    var Back:= pEnc.GetString(pEnc.GetBytes(Ln));
    if Back = Ln then Continue;
    for var I:= 1 to Length(Ln) do
      if (I > Length(Back)) or (Back[I] <> Ln[I]) then Exit(Format('U+%.4X', [Ord(Ln[I])]));
    Exit('U+FFFD');
  end;
end;

// Refusals for text the file's encoding cannot carry faithfully: for an ANSI file a character the
// edits insert that its code page does not represent (text copied from a file in another code page);
// C6: a character the code page does represent (cp1252 e-acute into a cp1252 file) is no refusal.
// Lane 142-cyc: such a character inside a string literal is no refusal either -- staging writes it as a
// numeric code (EscapeInsertedText); only one in a comment or an identifier still refuses.
procedure CheckInsertedText(const pPath: string; const pView: TCyclePlanView; pEnc: TEncoding; pOut: TList<TRefusal>);
begin
  if pEnc = TEncoding.UTF8 then Exit;
  for var E in pView.Edits do
  begin
    if not SameText(E.FilePath, pPath) then Continue;
    var Escaped:= EscapeUnfitForPascal(string.Join(#13#10, E.NewLines), pEnc);
    var Ch:= UnrepresentableChar(Escaped.Split([#13#10]), pEnc);
    if Ch <> '' then
    begin
      pOut.Add(MakeRefusal('non-ascii-text', '', pPath, Format('an inserted line holds %s outside a string literal ' +
        '(a comment or an identifier), which the ANSI code page of this file does not represent; edit this file ' +
        'by hand', [Ch]), E.First));
      Exit;
    end;
  end;
end;

// The edits with the inserted text of pPath (an ANSI file: pEnc is not UTF-8) rewritten so a character
// its code page cannot hold, inside a string literal, becomes a numeric code ('a'#20013'b'); the edits
// of every other file and of a UTF-8 file are returned as they are. Line counts do not change.
function EscapeInsertedText(const pEdits: TArray<TTextEdit>; const pPath: string; pEnc: TEncoding): TArray<TTextEdit>;
begin
  Result:= Copy(pEdits);
  if pEnc = TEncoding.UTF8 then Exit;
  for var I:= 0 to High(Result) do
    if SameText(Result[I].FilePath, pPath) and (Result[I].Text <> '') then
      Result[I].Text:= EscapeUnfitForPascal(Result[I].Text, pEnc);
end;

function StageShadow(const pView: TCyclePlanView; const pProjectDir, pShadowDir: string;
  pTamperAllowed: Boolean): TArray<TRefusal>;
type
  TStaged = record
    Path : string;
    Bytes: TBytes;
  end;
var
  Enc    : TEncoding;
  Refs   : TList<TRefusal>;
  Staged : TList<TStaged>;
  Edits  : TArray<TTextEdit>;
  Done   : TList<string>;
  Lines  : TStringList;
  Item   : TStaged;
begin
  Refs  := TList<TRefusal>.Create;
  Staged:= TList<TStaged>.Create;
  Done  := TList<string>.Create;
  Lines := TStringList.Create;
  try
    Edits:= ToTextEdits(pView);
    var Why:= TTextEditApplier.RefusalOf(Edits);
    if Why <> '' then Refs.Add(AnchorRefusal('', Why, 0));
    for var P in pView.TouchedPaths do
    begin
      if Done.Contains(LowerCase(P)) then Continue;
      Done.Add(LowerCase(P));
      if not TFile.Exists(P) then
      begin
        Refs.Add(AnchorRefusal(P, 'the file to edit does not exist', 0));
        Continue;
      end;
      var Content:= DecodeSource(TFile.ReadAllBytes(P), Enc);
      if pTamperAllowed then ApplyTestTamper(P, Content);
      Lines.Text:= Content;
      var Before:= Refs.Count;
      CheckAnchors(P, pView, Lines, Refs);
      CheckInsertedText(P, pView, Enc, Refs);
      if Refs.Count > Before then Continue;
      var Expected:= Lines.Count + NetLineChange(P, Edits);
      var Text:= TTextEditApplier.ApplyToText(P, Content, EscapeInsertedText(Edits, P, Enc));
      Lines.Text:= Text;
      if Lines.Count <> Expected then
      begin
        Refs.Add(AnchorRefusal(P, 'the edit applier dropped an edit of this file', 0));
        Continue;
      end;
      Item.Path := ShadowPathOf(pShadowDir, pProjectDir, P);
      Item.Bytes:= EncodeSource(Text, Enc);
      Staged.Add(Item);
    end;
    for var N in pView.NewUnits do
    begin
      if TFile.Exists(N.Path) then
      begin
        Refs.Add(AnchorRefusal(N.Path, 'the new unit''s file already exists', 0));
        Continue;
      end;
      Item.Path := ShadowPathOf(pShadowDir, pProjectDir, N.Path);
      { W6 C7: a new unit holding text that is not ASCII (copied from the sources, decoded) is written as
        UTF-8 with a BOM -- dcc reads it, and it carries every character; ASCII text stays ASCII }
      Item.Bytes:= EncodeSource(string.Join(#13#10, N.Text) + #13#10,
        if HasNonAscii(N.Text) then TEncoding.UTF8 else TEncoding.ASCII);
      Staged.Add(Item);
    end;
    if Refs.Count = 0 then
      for Item in Staged do
      begin
        ForceDirectories(ExtractFilePath(Item.Path));
        TFile.WriteAllBytes(Item.Path, Item.Bytes);
      end;
    Result:= Refs.ToArray;
  finally
    Lines.Free;
    Done.Free;
    Staged.Free;
    Refs.Free;
  end;
end;

{ ---- the compile gate (E18 Task 10) ---------------------------------------------------------- }

type
  // One file TryRepair edits: its lines in its own encoding, and whether it ended in a line break.
  TRepairFile = class
  strict private
    FPath    : string;
    FLines   : TStringList;
    FEnc     : TEncoding;
    FTrailing: Boolean;
    FDirty   : Boolean;
  public
    constructor Create(const pPath: string);
    destructor Destroy; override;
    procedure Save;
    property Path : string read FPath;
    property Lines: TStringList read FLines;
    property Dirty: Boolean read FDirty write FDirty;
  end;

  // What the gate measured, for the JSON and the timing line.
  TGateReport = record
    Baseline      : TBuildOutcome;
    BaselineStatus: string;  // ok | error | unavailable | skipped | f2047-in-group
    F2047Unit     : string;  // the unit of the baseline's single `F2047: Circular unit reference`; '' otherwise (A4)
    After         : TCompileAfterResult;
    AfterStatus   : string;  // ok | error | skipped
    AfterFiles    : Integer;
  end;

  // What --apply did to one group (ApplyGroup), for the JSON, the text and the exit code.
  TApplyReport = record
    Ran       : Boolean;            // the write was attempted
    Tx        : TApplyTransaction;
    Refusals  : TArray<TRefusal>;   // write-failed / compile-error / build-timeout
    RolledBack: Boolean;
    Verify    : TVerifyResult;
    ExitCode  : Integer;
    Error     : string;             // the top-level error of an exit 2
  end;

const
  CStatusSkipped = 'skipped';
  CStatusF2047   = 'f2047-in-group';
  CKindBuildTimeout = 'build-timeout';

constructor TRepairFile.Create(const pPath: string);
begin
  inherited Create;
  FPath := pPath;
  FLines:= TStringList.Create;
  var Content:= DecodeSource(TFile.ReadAllBytes(pPath), FEnc);
  FTrailing  := EndsStr(#10, Content);
  FLines.Text:= Content;
end;

destructor TRepairFile.Destroy;
begin
  FLines.Free;
  inherited Destroy;
end;

procedure TRepairFile.Save;
begin
  FLines.LineBreak:= #13#10;
  var Text:= FLines.Text;
  if not FTrailing and EndsStr(#13#10, Text) then SetLength(Text, Length(Text) - Length(#13#10));
  TFile.WriteAllBytes(FPath, EncodeSource(Text, FEnc));
end;

// The folder of the gate's .bat files and logs: never inside the project or the shadow tree.
function BuildScratchDir: string;
begin
  if GBuildPick = '' then GBuildPick:= FreshScratchName('_build');
  Result:= GBuildPick;
end;

// The limit of a child that is one whole --apply (a --part all iteration, the A1 re-run): its three builds
// and three re-index steps plus CKillMarginMs, so the child's own limits fire first and it rolls back itself;
// INFINITE when the builds are unbounded.
function ChildApplyLimitMs: Cardinal;
begin
  if GBuildTimeoutMs = INFINITE then Exit(INFINITE);
  Result:= Cardinal(Min(UInt64(1 + CSecondBuild) * GBuildTimeoutMs + UInt64(CReindexSteps) * CReindexTimeoutMs + CKillMarginMs,
    UInt64(INFINITE - 1)));
end;

function BaselineCompile(const pOpts: TCycleFixOptions; const pLogDir: string): TBuildOutcome;
begin
  Result:= RunMsBuild(pOpts.Project, pOpts.Platform, IncludeTrailingPathDelimiter(pLogDir) + 'baseline.log', 'baseline build');
end;

// Where pPath of the plan is in pTreeDir: itself when the tree IS the project folder, else its shadow path.
function TreePathOf(const pTreeDir, pProjectDir, pPath: string): string;
begin
  if SameText(IncludeTrailingPathDelimiter(ExpandFileName(pTreeDir)), IncludeTrailingPathDelimiter(ExpandFileName(pProjectDir))) then
    Result:= ExpandFileName(pPath)
  else Result:= ShadowPathOf(pTreeDir, pProjectDir, pPath);
end;

// Every file the plan edits or creates.
function PlanFiles(const pView: TCyclePlanView): TArray<string>;
begin
  Result:= Copy(pView.TouchedPaths);
  for var N in pView.NewUnits do Result:= Result + [N.Path];
end;

// The unit that declares pName after the plan, '' when the plan does not provide it.
function LeafOf(const pView: TCyclePlanView; const pName: string): string;
begin
  for var M in pView.Moves do
    if SameText(M.Symbol, pName) and (M.ToUnit <> '') then Exit(M.ToUnit);
  if (pView.InversionUnit <> '') and (pName <> '') and
    (MatchText(pName, [pView.PtrType, pView.PtrVar]) or MatchText(pName, pView.IfaceNames)) then
    Exit(pView.InversionUnit);
  Result:= '';
end;

function TryRepair(const pView: TCyclePlanView; const pErrors: TArray<string>;
  const pProjectDir, pTreeDir: string): TArray<TRepair>;
type
  TUsesAdd = record
    FilePath: string;
    Section : string;
    Leaf    : string;
    Err     : TDccLine;
  end;
var
  Files  : TObjectDictionary<string, TRepairFile>;
  Adds   : TList<TUsesAdd>;
  Repairs: TList<TRepair>;
  Seen   : TList<string>;

  // The tree path of the plan file dcc names, '' when the plan has no such file in the tree.
  function Resolve(const pName: string): string;
  begin
    Result:= '';
    for var P in PlanFiles(pView) do
    begin
      var T:= TreePathOf(pTreeDir, pProjectDir, P);
      if not TFile.Exists(T) then Continue;
      if TPath.IsPathRooted(pName) and SameText(T, ExpandFileName(pName)) then Exit(T);
      if (Result = '') and SameText(ExtractFileName(T), ExtractFileName(pName)) then Result:= T;
    end;
  end;

  function FileOf(const pPath: string): TRepairFile;
  begin
    if not Files.TryGetValue(LowerCase(pPath), Result) then
    begin
      Result:= TRepairFile.Create(pPath);
      Files.Add(LowerCase(pPath), Result);
    end;
  end;

  procedure AddRepair(const pErr: TDccLine; const pPath, pAction: string);
  var
    R: TRepair;
  begin
    R.Code    := pErr.Code;
    R.FilePath:= pPath;
    R.Line    := pErr.Line;
    R.Action  := pAction;
    Repairs.Add(R);
  end;

  // E2015 on `<expr> as <IfaceName>`: cast <expr> through the plan's ancestor of that interface.
  procedure RepairCast(const pErr: TDccLine; const pPath: string; pFile: TRepairFile);
  begin
    var Text:= pFile.Lines[pErr.Line - 1];
    for var I:= 0 to High(pView.IfaceNames) do
    begin
      if pView.CastAncestors[I] = '' then Continue;
      var M:= TRegEx.Match(Text, '(?<![\w.)\]^])([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*)\s+as\s+' +
        TRegEx.Escape(pView.IfaceNames[I]) + '\b', [roIgnoreCase]);
      if not M.Success then Continue;
      var G:= M.Groups[1];
      var Fixed:= Copy(Text, 1, G.Index - 1) + pView.CastAncestors[I] + '(' + G.Value + ')' + Copy(Text, G.Index + G.Length, MaxInt);
      pFile.Lines[pErr.Line - 1]:= Fixed;
      pFile.Dirty:= True;
      AddRepair(pErr, pPath, Format('cast `%s` through %s: %s', [G.Value, pView.CastAncestors[I], Trim(Fixed)]));
      Exit;
    end;
  end;

  // E2010 '...' and 'Procedure' on the `PtrVar :=` line: re-emit the pointer type from the plan.
  procedure RepairPointer(const pErr: TDccLine; const pPath: string; pFile: TRepairFile);
  begin
    if (pView.PtrType = '') or (pView.PtrTypeDecl = '') or not ContainsText(pErr.Message, 'Procedure') or
       not TRegEx.IsMatch(pFile.Lines[pErr.Line - 1], '\b' + TRegEx.Escape(pView.PtrVar) + '\s*:=', [roIgnoreCase]) then Exit;
    for var P in PlanFiles(pView) do
    begin
      var T:= TreePathOf(pTreeDir, pProjectDir, P);
      if not TFile.Exists(T) then Continue;
      var D:= FileOf(T);
      var I:= LineIndexOf(D.Lines, '^\s*' + TRegEx.Escape(pView.PtrType) + '\s*=', 0, D.Lines.Count);
      if I < 0 then Continue;
      var Line:= D.Lines[I];
      var Want:= Copy(Line, 1, Length(Line) - Length(TrimLeft(Line))) + pView.PtrTypeDecl;
      if Line = Want then Exit;
      D.Lines[I]:= Want;
      D.Dirty   := True;
      AddRepair(pErr, pPath, Format('re-emitted %s in %s line %d from the routine''s signature: %s',
        [pView.PtrType, ExtractFileName(T), I + 1, pView.PtrTypeDecl]));
      Exit;
    end;
  end;

  // E2003 on a name the plan provides: queue its unit for the uses of the section holding the line.
  procedure QueueUses(const pErr: TDccLine; const pPath: string; pFile: TRepairFile);
  var
    A: TUsesAdd;
  begin
    var M:= TRegEx.Match(pErr.Message, '''([^'']+)''');
    if not M.Success then Exit;
    var Leaf:= LeafOf(pView, M.Groups[1].Value);
    if Leaf = '' then Exit;
    A.FilePath:= pPath;
    A.Section := SectionNameOf(pFile.Lines, pErr.Line - 1);
    A.Leaf    := Leaf;
    A.Err     := pErr;
    Adds.Add(A);
  end;

begin
  Files  := TObjectDictionary<string, TRepairFile>.Create([doOwnsValues]);
  Adds   := TList<TUsesAdd>.Create;
  Repairs:= TList<TRepair>.Create;
  Seen   := TList<string>.Create;
  try
    for var S in pErrors do
    begin
      var E: TDccLine;
      if not ParseDccLine(S, E) then Continue;
      var Key:= Format('%s|%d|%s', [LowerCase(ExtractFileName(E.FileName)), E.Line, E.Code]);
      if Seen.Contains(Key) then Continue;
      Seen.Add(Key);
      var Path:= Resolve(E.FileName);
      if Path = '' then Continue;
      var F:= FileOf(Path);
      if (E.Line < 1) or (E.Line > F.Lines.Count) then Continue;
      if E.Code = 'E2015' then RepairCast(E, Path, F)
      else if E.Code = 'E2010' then RepairPointer(E, Path, F)
      else if E.Code = 'E2003' then QueueUses(E, Path, F);
    end;
    { uses additions last: they insert lines, and every line number above was read before them }
    for var A in Adds do
    begin
      var F:= FileOf(A.FilePath);
      if AddToUses(F.Lines, A.Section, A.Leaf) then
      begin
        F.Dirty:= True;
        AddRepair(A.Err, A.FilePath, Format('added %s to the %s uses', [A.Leaf, A.Section]));
      end;
    end;
    for var F in Files.Values do
      if F.Dirty then F.Save;
    Result:= Repairs.ToArray;
  finally
    Seen.Free;
    Repairs.Free;
    Adds.Free;
    Files.Free;
  end;
end;

function CompileAfter(const pView: TCyclePlanView; const pProjectDir, pBuildProject, pPlatform,
  pLogDir: string): TCompileAfterResult;
begin
  var View:= pView;
  var ProjectDir:= pProjectDir;
  var Tree:= ExtractFilePath(ExpandFileName(pBuildProject));
  Result:= CompileAfterWith(pBuildProject, pPlatform, pLogDir,
    function(const pErrors: TArray<string>): TArray<TRepair>
    begin
      Result:= TryRepair(View, pErrors, ProjectDir, Tree);
    end);
end;

{ ---- the write, the rollback, the verification (E18 Task 11) ---------------------------------- }

function WriteAll(const pView: TCyclePlanView; const pProjectDir, pShadowDir: string; pNoBackup: Boolean;
  out pTx: TApplyTransaction): Boolean;
begin
  var News: TArray<string>:= nil;
  for var N in pView.NewUnits do News:= News + [N.Path];
  var ProjectDir:= pProjectDir;
  var ShadowDir:= pShadowDir;
  var CycleIndex:= pView.CycleIndex;
  var UnitList:= string.Join(' <-> ', pView.Units);
  Result:= WriteStaged(pView.TouchedPaths, News, pProjectDir, pNoBackup,
    function(pPath: string): TBytes
    begin
      var S:= ShadowPathOf(ShadowDir, ProjectDir, pPath);
      if not TFile.Exists(S) then raise EInOutError.CreateFmt('the shadow holds no staged copy of %s (%s)', [pPath, S]);
      Result:= TFile.ReadAllBytes(S);
    end,
    function(pChanged, pNew: Integer): string
    begin
      Result:= Format('[%s] cycles --fix --apply: cycle %d (%s), %d file(s) changed, %d new',
        [FormatDateTime('yyyy-mm-dd hh:nn:ss', Now), CycleIndex, UnitList, pChanged, pNew]);
    end, pTx);
end;

// The lines of a `cycles` output without the informational ones (blank, `(loaded ...`, notes, resolver).
function CyclesLines(const pText: string): TArray<string>;
begin
  Result:= nil;
  for var Raw in pText.Split([#10]) do
  begin
    var T:= TrimRight(Raw);
    if (Trim(T) = '') or StartsStr('(loaded', T) or StartsStr('drag-lint: note:', T) or TRegEx.IsMatch(T, '^\s+resolver:') then Continue;
    Result:= Result + [T];
  end;
end;

function SameCyclesOutput(const pPredicted, pActual: string): Boolean;

  function Normalized(const pText: string): string;
  begin
    var Lines:= CyclesLines(pText);
    var Groups: TArray<string>:= nil;
    var Slots : TArray<Integer>:= nil;
    for var I:= 0 to High(Lines) do
    begin
      var M:= TRegEx.Match(Lines[I], '^(?<head>\s*\[\d+ units\]\s+)(?<units>.+?)(?<tag>\s{2,}\(.*)$');
      if not M.Success then Continue;
      var Units:= TRegEx.Split(M.Groups['units'].Value, '\s*<->\s*');
      TArray.Sort<string>(Units);
      Lines[I]:= M.Groups['head'].Value + string.Join(' <-> ', Units) + M.Groups['tag'].Value;
      Groups:= Groups + [Lines[I]];
      Slots := Slots + [I];
    end;
    TArray.Sort<string>(Groups);
    for var K:= 0 to High(Slots) do Lines[Slots[K]]:= Groups[K];
    Result:= string.Join(#10, Lines);
  end;

begin
  Result:= Normalized(pPredicted) = Normalized(pActual);
end;

// The target guard of the child re-index: '' when pOpts.Db is the project DB that indexes the plan's
// files (pProject receives its project file), else why not.
function ReindexTargetProblem(const pView: TCyclePlanView; const pOpts: TCycleFixOptions; const pStore: ISymbolStore;
  out pProject: string): string;
var
  Indexed: TDictionary<string, Boolean>;
begin
  pProject:= '';
  if pStore = nil then Exit('no index of ' + pOpts.Db + ' is open');
  var Scan:= pStore.GetMetaValue('scan_type');
  if not SameText(Scan, 'project') then
    Exit(Format('%s is not a project index (scan_type "%s"): only the project DB that indexes the units is re-indexed', [pOpts.Db, Scan]));
  Indexed:= TDictionary<string, Boolean>.Create;
  try
    var Proj: TArray<string>:= nil;
    var Dpr : TArray<string>:= nil;
    for var FS in pStore.GetAllFileStamps do
    begin
      Indexed.AddOrSetValue(LowerCase(ExpandFileName(FS.Path)), True);
      if SameText(ExtractFileExt(FS.Path), '.dproj') then Proj:= Proj + [FS.Path]
      else if SameText(ExtractFileExt(FS.Path), '.dpr') then Dpr:= Dpr + [FS.Path];
    end;
    if Length(Proj) = 0 then Proj:= Dpr;
    if Length(Proj) <> 1 then
      Exit(Format('%s holds %d project files: cannot name the one to re-index', [pOpts.Db, Length(Proj)]));
    if not SameText(ChangeFileExt(ExpandFileName(Proj[0]), ''), ChangeFileExt(ExpandFileName(pOpts.Project), '')) then
      Exit(Format('%s is the index of %s, not of --project %s', [pOpts.Db, Proj[0], pOpts.Project]));
    for var P in pView.TouchedPaths do
      if SameText(ExtractFileExt(P), '.pas') and not Indexed.ContainsKey(LowerCase(ExpandFileName(P))) then
        Exit(Format('%s does not index %s', [pOpts.Db, P]));
    pProject:= Proj[0];
    Result:= '';
  finally
    Indexed.Free;
  end;
end;

function VerifyAfterCore(const pView: TCyclePlanView; const pOpts: TCycleFixOptions;
  const pStore: ISymbolStore): TVerifyResult;
const
  CMsPerSecond = 1000;
begin
  Result:= Default(TVerifyResult);
  Result.ReindexDb    := pOpts.Db;
  Result.ReindexStatus:= CStatusSkipped;
  Result.Reason       := 'not re-indexed';
  if pOpts.NoReindex then
  begin
    Result.ReindexReason:= '--no-reindex';
    Exit;
  end;
  Result.ReindexReason:= ReindexTargetProblem(pView, pOpts, pStore, Result.ReindexProject);
  if Result.ReindexReason <> '' then Exit;
  var Dir:= BuildScratchDir;
  var Exe:= ParamStr(0);
  var TimedOut:= False;
  var Code:= -1;
  var Watch:= TStopwatch.StartNew;
  try
    Code:= RunBounded('re-index', Format('"%s" index --project "%s" --db "%s"', [Exe, Result.ReindexProject, pOpts.Db]),
      Dir + 'reindex.log', CReindexTimeoutMs, TimedOut);
  except
    on ECycleFixCancelled do raise; { ApplyGroup rolls back }
    on E: Exception do Result.ReindexReason:= 'could not start the re-index (' + E.Message + ')';
  end;
  Result.ReindexMs:= Watch.ElapsedMilliseconds;
  if TimedOut or (Code <> 0) then
  begin
    Result.ReindexStatus:= 'failed';
    if Result.ReindexReason = '' then
      Result.ReindexReason:= if TimedOut then Format('index did not finish within %d s; the child was terminated', [CReindexTimeoutMs div CMsPerSecond])
                             else Format('index exited %d', [Code]) + CiteScratch(Dir + 'reindex.log', ' (log %s)');
    Result.ReindexReason:= Result.ReindexReason + Format(' -- run: drag-lint index --project "%s" --db "%s"', [Result.ReindexProject, pOpts.Db]);
    Result.Reason:= 're-index failed';
    Exit;
  end;
  Result.ReindexStatus:= 'done';
  var OutFile:= Dir + 'cycles-after.txt';
  try
    RunBounded('re-check of the cycles', Format('"%s" cycles --db "%s"', [Exe, pOpts.Db]), OutFile, CReindexTimeoutMs, TimedOut);
    if not TimedOut and TFile.Exists(OutFile) then
      Result.Actual:= string.Join(#10, CyclesLines(TFile.ReadAllText(OutFile, TEncoding.ANSI)));
  except
    on ECycleFixCancelled do raise; { ApplyGroup rolls back }
    on E: Exception do OutFile:= OutFile + ': ' + E.Message;
  end;
  if Result.Actual = '' then
  begin
    Result.Reason:= '`cycles` on the re-indexed DB printed nothing' + CiteScratch(OutFile, ' (see %s)');
    Exit;
  end;
  Result.Verified:= SameCyclesOutput(pView.Predicted, Result.Actual);
  Result.Reason  := if Result.Verified then '' else 'the cycles output differs from the prediction';
end;

function VerifyAfter(const pView: TCyclePlanView; const pOpts: TCycleFixOptions;
  const pStore: ISymbolStore): TVerifyResult;
begin
  try
    Result:= VerifyAfterCore(pView, pOpts, pStore);
  except
    on ECycleFixCancelled do raise; { ApplyGroup rolls back }
    on E: Exception do
    begin
      { the files compiled and stay; only the verification failed }
      Result:= Default(TVerifyResult);
      Result.ReindexDb    := pOpts.Db;
      Result.ReindexStatus:= 'failed';
      Result.ReindexReason:= E.ClassName + ': ' + E.Message;
      Result.Reason       := 'verification failed: ' + E.Message;
    end;
  end;
end;

function BreakSeam(const pOpts: TCycleFixOptions): Integer;
begin
  Result:= StrToIntDef(GetEnvironmentVariable('DRAGLINT_CYCLEFIX_BREAK'), 0);
  if not (Result in [CBreakCast, CBreakPointer, CBreakNoRepair, CBreakRaise]) or not IsUnderTemp(pOpts.Project) then Result:= 0;
end;

function BreakLine(const pView: TCyclePlanView; const pLine: string; pMode: Integer): string;
begin
  Result:= pLine;
  if pMode = CBreakCast then
  begin
    for var I:= 0 to High(pView.IfaceNames) do
    begin
      if pView.CastAncestors[I] = '' then Continue;
      var M:= TRegEx.Match(Result, '\b' + TRegEx.Escape(pView.CastAncestors[I]) + '\(([^()]*)\)(\s+as\s+' +
        TRegEx.Escape(pView.IfaceNames[I]) + '\b)', [roIgnoreCase]);
      if M.Success then
        Result:= Copy(Result, 1, M.Index - 1) + M.Groups[1].Value + M.Groups[2].Value + Copy(Result, M.Index + M.Length, MaxInt);
    end;
  end
  else if (pMode = CBreakPointer) and (pView.PtrTypeDecl <> '') and (Trim(pLine) = Trim(pView.PtrTypeDecl)) then
  begin
    Result:= StringReplace(pLine, '= function(', '= reference to function(', []);
    Result:= StringReplace(Result, '= procedure(', '= reference to procedure(', []);
    Result:= TRegEx.Replace(Result, '\bconst\s+', '', [roIgnoreCase]);
  end;
end;

// A broken copy of pLines (BreakLine on each); pLines is not modified.
function BrokenLines(const pView: TCyclePlanView; const pLines: TArray<string>; pMode: Integer): TArray<string>;
begin
  Result:= Copy(pLines);
  for var K:= 0 to High(Result) do Result[K]:= BreakLine(pView, Result[K], pMode);
end;

function ApplyTestBreak(const pView: TCyclePlanView; pMode: Integer): TCyclePlanView;
begin
  Result:= pView;
  Result.Edits:= Copy(pView.Edits);
  for var I:= 0 to High(Result.Edits) do
    Result.Edits[I].NewLines:= BrokenLines(pView, pView.Edits[I].NewLines, pMode);
  Result.NewUnits:= Copy(pView.NewUnits);
  for var I:= 0 to High(Result.NewUnits) do
  begin
    Result.NewUnits[I].Text:= BrokenLines(pView, pView.NewUnits[I].Text, pMode);
    if pMode = CBreakNoRepair then
      for var K:= 0 to High(Result.NewUnits[I].Text) do
        if SameText(Trim(Result.NewUnits[I].Text[K]), 'interface') then
        begin
          Insert('  CycleFixTestBreak !', Result.NewUnits[I].Text, K + 1);
          Break;
        end;
  end;
end;

// Test seam DRAGLINT_CYCLEFIX_REPAIR_PROBE=<tree>[|<errors file>], inert with --apply and for a tree
// outside %TEMP% / C:\TEMP. <tree> holds the project with the staged plan laid over it. With an errors
// file, TryRepair runs on <tree> with those dcc lines (no build); without, CompileAfter builds <tree>.
function ProbeSpec(const pOpts: TCycleFixOptions; out pTree, pErrorsFile: string): Boolean;
begin
  pTree      := '';
  pErrorsFile:= '';
  var Spec:= GetEnvironmentVariable('DRAGLINT_CYCLEFIX_REPAIR_PROBE').Split(['|']);
  if pOpts.Apply or (Length(Spec) = 0) or (Trim(Spec[0]) = '') then Exit(False);
  pTree:= IncludeTrailingPathDelimiter(ExpandFileName(Trim(Spec[0])));
  if Length(Spec) >= CProbeWithLines then pErrorsFile:= Trim(Spec[1]);
  Result:= IsUnderTemp(pTree) and TDirectory.Exists(pTree);
end;

// `compile: baseline 9.8 s, after 10.1 s` -- the parts that ran; '' when none did.
function TimingLine(const pGate: TGateReport): string;
begin
  Result:= '';
  if (pGate.BaselineStatus = 'ok') or (pGate.BaselineStatus = 'error') or (pGate.BaselineStatus = CStatusF2047) then
    Result:= Format('baseline %.1f s', [pGate.Baseline.Seconds], TFormatSettings.Invariant);
  if pGate.AfterStatus <> CStatusSkipped then
    Result:= Result + IfThen(Result <> '', ', ') + Format('after %.1f s', [pGate.After.Seconds], TFormatSettings.Invariant);
  if Result <> '' then Result:= 'compile: ' + Result;
  if pGate.BaselineStatus = CStatusF2047 then Result:= Result + sLineBreak + 'compile: baseline F2047 in this group -- the build after the edit is the only proof';
end;

function IntfEdgeCount(const pUnits: TArray<string>; const pGraph: TCycleGraph; pIntfOnly: Boolean): Integer;
var
  Targets: TList<string>;
begin
  Result:= 0;
  for var A in pUnits do
    for var B in pUnits do
    begin
      if A = B then Continue;
      if pIntfOnly then
      begin
        if pGraph.IntfEdges.ContainsKey(A + '->' + B) then Inc(Result);
      end
      else if pGraph.Adj.TryGetValue(A, Targets) and Targets.Contains(B) then Inc(Result);
    end;
end;

function RefusalLine(const pR: TRefusal): string;
begin
  Result:= Format('  - %s: %s %s:%d -- %s', [pR.Kind, pR.Symbol, pR.FilePath, pR.Line, pR.Reason]);
end;

function StringsToJson(const pItems: TArray<string>): TJSONArray;
begin
  Result:= TJSONArray.Create;
  for var S in pItems do Result.Add(S);
end;

function Seconds(pValue: Double): TJSONNumber;
begin
  Result:= TJSONNumber.Create(SimpleRoundTo(pValue, CJsonDecimals));
end;

// compile.errors of cycle-fix/1: {file, line, code, message}; a line dcc did not shape is kept as message.
function DccErrorsToJson(const pErrors: TArray<string>): TJSONArray;
begin
  Result:= TJSONArray.Create;
  for var S in pErrors do
  begin
    var E: TDccLine;
    if not ParseDccLine(S, E) then
    begin
      E:= Default(TDccLine);
      E.Message:= S;
    end;
    var O:= TJSONObject.Create;
    O.AddPair('file', E.FileName);
    O.AddPair('line', TJSONNumber.Create(E.Line));
    O.AddPair('code', E.Code);
    O.AddPair('message', E.Message);
    Result.AddElement(O);
  end;
end;

function BaselineToJson(const pGate: TGateReport): TJSONObject;
begin
  Result:= TJSONObject.Create;
  Result.AddPair('status', pGate.BaselineStatus);
  Result.AddPair('seconds', Seconds(pGate.Baseline.Seconds));
  Result.AddPair('errors', StringsToJson(pGate.Baseline.Errors));
end;

function RefusalToJson(const pR: TRefusal): TJSONObject;
begin
  Result:= TJSONObject.Create;
  Result.AddPair('kind', pR.Kind);
  Result.AddPair('symbol', pR.Symbol);
  Result.AddPair('file', pR.FilePath);
  Result.AddPair('line', TJSONNumber.Create(pR.Line));
  Result.AddPair('reason', pR.Reason);
end;

function CycleToJson(const pView: TCyclePlanView; const pRefusals: TArray<TRefusal>;
  const pGraph: TCycleGraph; const pGate: TGateReport; const pApply: TApplyReport): TJSONObject;
var
  Arr: TJSONArray;
  O  : TJSONObject;
begin
  Result:= TJSONObject.Create;
  Result.AddPair('n', TJSONNumber.Create(pView.CycleIndex));
  Result.AddPair('units', StringsToJson(pView.Units));
  Result.AddPair('interface_edges', TJSONNumber.Create(IntfEdgeCount(pView.Units, pGraph, True)));
  Result.AddPair('edges', TJSONNumber.Create(IntfEdgeCount(pView.Units, pGraph, False)));
  Result.AddPair('part', LowerCase(pView.Part));
  Result.AddPair('verdict', if Length(pRefusals) = 0 then 'mechanical' else 'refused');
  Result.AddPair('recipe', pView.Recipe);
  Result.AddPair('edge', pView.Edge);
  Arr:= TJSONArray.Create;
  for var R in pRefusals do Arr.AddElement(RefusalToJson(R));
  Result.AddPair('refusals', Arr);
  Arr:= TJSONArray.Create;
  for var M in pView.Moves do
  begin
    O:= TJSONObject.Create;
    O.AddPair('symbol', M.Symbol);
    O.AddPair('kind', M.Kind);
    O.AddPair('recipe', M.Recipe);
    O.AddPair('from', M.FromFile);
    O.AddPair('lines', TJSONArray.Create.Add(M.First).Add(M.Last));
    O.AddPair('to_unit', M.ToUnit);
    Arr.AddElement(O);
  end;
  Result.AddPair('moves', Arr);
  Arr:= TJSONArray.Create;
  for var U in pView.UseDecisions do
  begin
    O:= TJSONObject.Create;
    O.AddPair('file', U.FilePath);
    O.AddPair('unit', U.UnitName);
    O.AddPair('section', U.Section);
    O.AddPair('action', U.Action);
    Arr.AddElement(O);
  end;
  Result.AddPair('uses', Arr);
  Arr:= TJSONArray.Create;
  for var N in pView.NewUnits do
  begin
    O:= TJSONObject.Create;
    O.AddPair('unit', N.UnitName);
    O.AddPair('path', N.Path);
    Arr.AddElement(O);
  end;
  Result.AddPair('new_units', Arr);
  Arr:= TJSONArray.Create;
  for var E in pView.Edits do
  begin
    O:= TJSONObject.Create;
    O.AddPair('file', E.FilePath);
    O.AddPair('kind', E.Kind);
    O.AddPair('first', TJSONNumber.Create(E.First));
    O.AddPair('last', TJSONNumber.Create(E.Last));
    Arr.AddElement(O);
  end;
  Result.AddPair('edits', Arr);
  O:= TJSONObject.Create;
  O.AddPair('status', pGate.AfterStatus);
  O.AddPair('files', TJSONNumber.Create(pGate.AfterFiles));
  O.AddPair('errors', DccErrorsToJson(pGate.After.Errors));
  O.AddPair('seconds', Seconds(pGate.After.Seconds));
  O.AddPair('builds', TJSONNumber.Create(pGate.After.Builds));
  Result.AddPair('compile', O);
  Result.AddPair('baseline', BaselineToJson(pGate));
  Arr:= TJSONArray.Create;
  for var R in pGate.After.Repairs do
  begin
    O:= TJSONObject.Create;
    O.AddPair('code', R.Code);
    O.AddPair('file', R.FilePath);
    O.AddPair('line', TJSONNumber.Create(R.Line));
    O.AddPair('action', R.Action);
    Arr.AddElement(O);
  end;
  Result.AddPair('repairs', Arr);
  Result.AddPair('written', StringsToJson(pApply.Tx.Written));
  Result.AddPair('new_files', StringsToJson(pApply.Tx.NewFiles));
  Arr:= TJSONArray.Create;
  for var B in pApply.Tx.Backups do
  begin
    var Parts:= B.Split([' -> ']);
    O:= TJSONObject.Create;
    O.AddPair('file', Parts[0]);
    O.AddPair('backup', if Length(Parts) > 1 then Parts[1] else '');
    Arr.AddElement(O);
  end;
  Result.AddPair('backups', Arr);
  Result.AddPair('rolled_back', TJSONBool.Create(pApply.RolledBack));
  O:= TJSONObject.Create;
  O.AddPair('status', if pApply.Verify.ReindexStatus = '' then 'dry-run' else pApply.Verify.ReindexStatus);
  O.AddPair('ms', TJSONNumber.Create(pApply.Verify.ReindexMs));
  O.AddPair('db', pApply.Verify.ReindexDb);
  O.AddPair('project', pApply.Verify.ReindexProject);
  O.AddPair('reason', pApply.Verify.ReindexReason);
  Result.AddPair('reindex', O);
  Result.AddPair('predicted', pView.Predicted);
  Result.AddPair('actual', pApply.Verify.Actual);
  Result.AddPair('verified', TJSONBool.Create(pApply.Verify.Verified));
  Result.AddPair('verify_reason', pApply.Verify.Reason);
end;

// The 1-based group holding pStem (with or without .pas), 0 when none does.
function GroupOfUnit(const pSccs: TList<TArray<string>>; const pStem: string): Integer;
begin
  var Stem:= LowerCase(ChangeFileExt(pStem, ''));
  for var I:= 0 to pSccs.Count - 1 do
    for var S in pSccs[I] do
      if S = Stem then Exit(I + 1);
  Result:= 0;
end;

// Checks the flags and resolves the group (0 = scan for the first mechanical one) and the
// project's own roots; returns the error text, '' when all is well.
function ResolveSelection(const pOpts: TCycleFixOptions; const pSccs: TList<TArray<string>>;
  out pOwn: TOwnRoots; out pOnly: Integer): string;
begin
  Result:= '';
  pOnly := 0;
  pOwn  := Default(TOwnRoots);
  if pOpts.Project = '' then Result:= CNeedsProject
  else if pOpts.Apply and pOpts.NoCompile then
    Result:= 'cycles --fix --apply always builds the project (baseline and after); --no-compile is for the dry run only'
  else if not MatchText(pOpts.Part, ['', 'a', 'b', 'all']) then
    Result:= 'cycles --fix --part must be a, b or all'
  else if SameText(pOpts.Part, CPartAll) and not pOpts.Apply then
    Result:= 'cycles --fix --part all needs --apply: a dry run of all parts would show stale line numbers after the first part'
  else if SameText(pOpts.Part, CPartAll) and pOpts.NoReindex then
    Result:= 'cycles --fix --part all cannot use --no-reindex: every iteration re-plans on the re-indexed project'
  else if pOpts.CycleGiven and (pOpts.CycleIndex < 1) then
    Result:= 'cycles --fix --cycle needs a group number of 1 or more (see `drag-lint cycles` for the groups)'
  else if (pOpts.RsVars <> '') and not FileExists(ExpandFileName(pOpts.RsVars)) then
    Result:= 'cycles --fix --rsvars: no such file: ' + ExpandFileName(pOpts.RsVars)
  else if (pOpts.BuildTimeout <> '') and not InRange(StrToIntDef(pOpts.BuildTimeout, -1), 0, CMaxBuildTimeoutS) then
    Result:= Format('cycles --fix --build-timeout needs whole seconds from 0 (no limit, the default) to %d, got: %s',
      [CMaxBuildTimeoutS, pOpts.BuildTimeout]);
  if Result = '' then GRsVars:= if pOpts.RsVars <> '' then ExpandFileName(pOpts.RsVars) else '';
  if Result = '' then
  begin
    var Secs:= StrToIntDef(pOpts.BuildTimeout, CDefaultBuildTimeoutS);
    GBuildTimeoutMs:= if Secs = 0 then INFINITE else Cardinal(Secs) * CMsPerSec;
  end;
  if Result <> '' then Exit;
  if (pOpts.ShadowOut <> '') and TDirectory.Exists(ExpandFileName(pOpts.ShadowOut)) and
     (Length(TDirectory.GetFileSystemEntries(ExpandFileName(pOpts.ShadowOut))) > 0) then
    Exit('cycles --fix: shadow-out dir not empty: ' + ExpandFileName(pOpts.ShadowOut) + ' (name an empty or new directory; nothing is deleted)');
  pOwn:= TOwnRoots.Load(ExtractFilePath(ExpandFileName(pOpts.Project)));
  if pOwn.Error <> '' then Exit(pOwn.Error);
  if pOpts.CycleGiven then pOnly:= pOpts.CycleIndex
  else if pOpts.UnitStem <> '' then
  begin
    pOnly:= GroupOfUnit(pSccs, pOpts.UnitStem);
    if pOnly = 0 then Exit('cycles --fix: unit ' + pOpts.UnitStem + ' is in no circular group');
  end;
  if (pOnly > pSccs.Count) then
    Result:= Format('cycles --fix: --cycle %d, but there are %d circular group(s)', [pOnly, pSccs.Count]);
end;

// Error path: a cycle-fix/1 object with "error" under --format json (as the other verbs'
// JSON reports do), else `ERROR: <message>`.
procedure ReportError(const pOpts: TCycleFixOptions; const pMessage: string);
begin
  if pOpts.Json then
  begin
    var Doc:= TJSONObject.Create;
    try
      Doc.AddPair('schema', CSchema);
      Doc.AddPair('error', pMessage);
      Doc.AddPair('ok', TJSONBool.Create(False));
      Doc.AddPair('exit_code', TJSONNumber.Create(CExitError));
      Writeln(Doc.ToJSON);
    finally
      Doc.Free;
    end;
  end
  else Writeln('ERROR: ', pMessage);
end;

procedure ReportCycleFixError(const pOpts: TCycleFixOptions; const pMessage: string);
begin
  ReportError(pOpts, pMessage);
end;

// A refusal of the whole run before any group is planned (dirty-baseline, no-compiler): exit 1,
// nothing staged. JSON: the top-level `refusals` and `baseline`, `cycles` empty.
// The platform the run builds for, lowercase: --platform, else the project's active Platform
// (PlatformOfDproj), else win32 -- owner ruling a3 (L-C20). Idempotent on a resolved pOpts.
function CycleFixPlatform(const pOpts: TCycleFixOptions): string;
begin
  Result:= pOpts.Platform;
  if Result = '' then Result:= PlatformOfDproj(pOpts.Project);
  Result:= if Result = '' then CNoPlatform else LowerCase(Result);
end;

// A cycle-fix/1 document holding the run's header pairs: schema, mode, project, db, platform.
function NewRunDoc(const pOpts: TCycleFixOptions): TJSONObject;
begin
  Result:= TJSONObject.Create;
  Result.AddPair('schema', CSchema);
  Result.AddPair('mode', if pOpts.Apply then 'apply' else 'dry-run');
  Result.AddPair('project', pOpts.Project);
  Result.AddPair('db', pOpts.Db);
  Result.AddPair('platform', CycleFixPlatform(pOpts));
end;

procedure ReportGateRefusal(const pOpts: TCycleFixOptions; const pGate: TGateReport; const pRefusal: TRefusal);
begin
  if pOpts.Json then
  begin
    var Doc:= NewRunDoc(pOpts);
    try
      Doc.AddPair('baseline', BaselineToJson(pGate));
      Doc.AddPair('refusals', TJSONArray.Create.Add(RefusalToJson(pRefusal)));
      Doc.AddPair('cycles', TJSONArray.Create);
      Doc.AddPair('ok', TJSONBool.Create(False));
      Doc.AddPair('exit_code', TJSONNumber.Create(CExitRefused));
      Writeln(Doc.ToJSON);
    finally
      Doc.Free;
    end;
  end
  else
  begin
    Writeln(CVerdictRefused);
    Writeln(RefusalLine(pRefusal));
    for var S in pGate.Baseline.Errors do Writeln('    ', S);
    var T:= TimingLine(pGate);
    if T <> '' then Writeln(T);
  end;
end;

// Prints the stderr notice of every active test seam; returns the BREAK mode (BreakSeam) and the probe (ProbeSpec).
function AnnounceSeams(const pOpts: TCycleFixOptions; out pProbe: Boolean; out pProbeTree, pProbeLines: string): Integer;
begin
  if TamperAllowed(pOpts) and (GetEnvironmentVariable('DRAGLINT_CYCLEFIX_TEST_TAMPER') <> '') then
    Writeln(ErrOutput, 'cycles --fix: TEST TAMPER active (dry run only)');
  Result:= BreakSeam(pOpts);
  if Result <> 0 then
    Writeln(ErrOutput, Format('cycles --fix: TEST BREAK active (DRAGLINT_CYCLEFIX_BREAK=%d; the project lies under TEMP)', [Result]));
  pProbe:= ProbeSpec(pOpts, pProbeTree, pProbeLines);
  if pProbe then Writeln(ErrOutput, 'cycles --fix: TEST REPAIR PROBE active (dry run only): ' + pProbeTree);
  if BuildTimeoutMs(pOpts.Project) <> GBuildTimeoutMs then
    Writeln(ErrOutput, Format('cycles --fix: TEST BUILD TIMEOUT active (DRAGLINT_CYCLEFIX_BUILD_TIMEOUT_MS=%d; the project lies under TEMP)', [BuildTimeoutMs(pOpts.Project)]));
end;

// A4 (owner ruling 2026-10-25, "plan anyway"): the unit every dcc error line of the baseline names as
// `F2047: Circular unit reference to 'X'` (dcc stops at that fatal error, so there is one unit, and
// msbuild may echo the line twice); '' for any other baseline (a different code, or a second unit).
function F2047OnlyUnit(const pErrors: TArray<string>): string;
begin
  Result:= '';
  for var Line in pErrors do
  begin
    var M:= TRegEx.Match(Line, '\bF2047:? Circular unit reference to ''([^'']+)''');
    if not M.Success then Exit('');
    if (Result <> '') and not SameText(Result, M.Groups[1].Value) then Exit('');
    Result:= M.Groups[1].Value;
  end;
end;

// A4: the baseline failed ONLY with F2047 (PassBaselineGate let the run through). The group being planned
// may go on when it is an interface-coupled Part A group that holds the F2047 unit: its after-build is then
// the proof. Any other group keeps today's `dirty-baseline` refusal. Sets the status the JSON and the
// text show for THIS group.
function BaselineGroupRefusals(var pGate: TGateReport; const pView: TCyclePlanView; const pProject: string): TArray<TRefusal>;
begin
  Result:= nil;
  if pGate.F2047Unit = '' then Exit;
  var Holds:= False;
  for var U in pView.Units do
    if SameText(U, pGate.F2047Unit) then Holds:= True;
  if pView.HasIntf and (pView.Part = 'A') and Holds then
  begin
    pGate.BaselineStatus:= CStatusF2047;
    Exit;
  end;
  pGate.BaselineStatus:= 'error';
  Result:= [MakeRefusal('dirty-baseline', '', pProject,
    Format('the project does not build before any edit (%d dcc error line(s), first: %s); the only error is an F2047 that ' +
      'lies outside this group, so the build after the edit could not prove it; fix it, then retry',
      [Length(pGate.Baseline.Errors), pGate.Baseline.Errors[0]]), 0)];
end;

// The baseline gate: the UNTOUCHED project must build before anything is planned or staged. False =
// refused (no-compiler / dirty-baseline), already reported. pGate is filled either way.
function PassBaselineGate(const pOpts: TCycleFixOptions; pAnyGroup: Boolean; out pGate: TGateReport): Boolean;
begin
  pGate:= Default(TGateReport);
  pGate.BaselineStatus:= CStatusSkipped;
  pGate.AfterStatus   := CStatusSkipped;
  Result:= True;
  if pOpts.NoCompile or not pAnyGroup then Exit;
  if not CompilerAvailable then
  begin
    pGate.BaselineStatus:= 'unavailable';
    ReportGateRefusal(pOpts, pGate, MakeRefusal('no-compiler', '', pOpts.Project,
      'the RAD Studio build environment was not found (' + BuildEnvBat + '): the compile gate cannot run; a dry run without ' +
      'it needs --no-compile', 0));
    Exit(False);
  end;
  pGate.Baseline:= BaselineCompile(pOpts, BuildScratchDir);
  pGate.BaselineStatus:= if pGate.Baseline.Ok then 'ok' else 'error';
  Result:= pGate.Baseline.Ok;
  if not (Result or pGate.Baseline.TimedOut) then pGate.F2047Unit:= F2047OnlyUnit(pGate.Baseline.Errors);
  if pGate.F2047Unit <> '' then Exit(True); // A4: each group decides (BaselineGroupRefusals)
  if pGate.Baseline.TimedOut then
    ReportGateRefusal(pOpts, pGate, MakeRefusal(CKindBuildTimeout, '', pOpts.Project,
      'the baseline build ' + pGate.Baseline.Errors[0], 0))
  else if not Result then
    ReportGateRefusal(pOpts, pGate, MakeRefusal('dirty-baseline', '', pOpts.Project,
      Format('the project does not build before any edit (%d dcc error line(s), first: %s); fix it, then retry',
        [Length(pGate.Baseline.Errors), pGate.Baseline.Errors[0]]), 0));
end;

// DRAGLINT_CYCLEFIX_REPAIR_PROBE (ProbeSpec): TryRepair on canned lines, or CompileAfter on the tree.
procedure RunRepairProbe(const pStaged: TCyclePlanView; const pOpts: TCycleFixOptions;
  const pProjectDir, pTree, pLinesFile: string; var pGate: TGateReport);
begin
  if pLinesFile <> '' then
  begin
    pGate.After.Repairs:= TryRepair(pStaged, TFile.ReadAllLines(pLinesFile), pProjectDir, pTree);
    Exit;
  end;
  pGate.After      := CompileAfter(pStaged, pProjectDir, pTree + ExtractFileName(pOpts.Project), pOpts.Platform, BuildScratchDir);
  pGate.AfterStatus:= if pGate.After.Ok then 'ok' else 'error';
  pGate.AfterFiles := Length(PlanFiles(pStaged));
end;


// A report for a run that wrote nothing (the dry run, or a group that was not applied).
function NoApply: TApplyReport;
begin
  Result:= Default(TApplyReport);
  Result.Verify.ReindexStatus:= 'dry-run';
end;

// A stand-down taken after WriteAll (lane X-BT): rolls pApply.Tx back. Exit 1 and the refusal `cancelled`
// ("cancelled -- rolled back") when the project is as before; exit 2 when the rollback failed.
function CancelledApply(const pApply: TApplyReport; const pOpts: TCycleFixOptions): TApplyReport;
begin
  Result:= pApply;
  var Failure:= RollBack(Result.Tx);
  Result.RolledBack:= Failure = '';
  Result.Verify.ReindexStatus:= CStatusSkipped;
  Result.Verify.Reason:= 'cancelled';
  Result.Refusals:= [MakeRefusal('cancelled', '', pOpts.Project,
    if Result.RolledBack then 'cancelled -- rolled back, project not changed'
    else 'cancelled, and the rollback FAILED: ' + Failure, 0)];
  Result.ExitCode:= if Result.RolledBack then CExitRefused else CExitError;
  if not Result.RolledBack then
    Result.Error:= 'cancelled and the rollback FAILED: ' + Failure + ' -- the project may be PARTLY changed; recovery.txt names the backups';
end;

// --apply of one mechanical group, after the baseline gate passed and pStaged was staged in pShadowDir:
// WriteAll, CompileAfter in place (one repair at most), then RollBack or VerifyAfter.
function ApplyGroup(const pStaged: TCyclePlanView; const pOpts: TCycleFixOptions; const pProjectDir, pShadowDir: string;
  const pStore: ISymbolStore; var pGate: TGateReport): TApplyReport;
begin
  Result:= NoApply;
  Result.Ran:= True;
  Result.Verify.ReindexStatus:= CStatusSkipped;
  Result.Verify.Reason:= 'not re-indexed';
  if not WriteAll(pStaged, pProjectDir, pShadowDir, pOpts.NoBackup, Result.Tx) then
  begin
    Result.RolledBack:= Result.Tx.RollbackFailure = '';
    Result.Refusals:= [MakeRefusal('write-failed', '', '', Result.Tx.Error, 0)];
    Result.ExitCode:= CExitError;
    Result.Error:= if Result.RolledBack then 'rolled back, project not changed: ' + Result.Tx.Error
                   else 'write failed (' + Result.Tx.Error + ') and the rollback FAILED: ' + Result.Tx.RollbackFailure +
                     ' -- the project may be PARTLY changed; recovery.txt names the backups';
    Exit;
  end;
  pGate.AfterFiles := Length(Result.Tx.Written);
  try
    if BreakSeam(pOpts) = CBreakRaise then
      raise EInOutError.Create('TEST BREAK 4: simulated failure of the after gate once the files are written');
    pGate.After:= CompileAfter(pStaged, pProjectDir, pOpts.Project, pOpts.Platform, BuildScratchDir);
  except
    on ECycleFixCancelled do
    begin
      pGate.AfterStatus:= 'cancelled';
      Result:= CancelledApply(Result, pOpts);
      Exit;
    end;
    on E: Exception do
    begin
      { the build could not even run (spawn, .bat, a repair's file edit): the tree is written but
        unproven -- roll it back like a compile error, but as an error (exit 2) }
      pGate.AfterStatus:= 'error';
      pGate.After.Errors:= [E.ClassName + ': ' + E.Message];
      var Failure:= RollBack(Result.Tx);
      Result.RolledBack:= Failure = '';
      Result.Refusals:= [MakeRefusal('build-error', '', pOpts.Project, 'the after gate failed: ' + E.Message, 0)];
      Result.ExitCode:= CExitError;
      Result.Error:= if Result.RolledBack then 'rolled back, project not changed: build error: ' + E.Message
                     else 'build error (' + E.Message + ') and the rollback FAILED: ' + Failure;
      Exit;
    end;
  end;
  pGate.AfterStatus:= if pGate.After.Ok then 'ok' else 'error';
  if not pGate.After.Ok then
  begin
    var Failure:= RollBack(Result.Tx);
    Result.RolledBack:= Failure = '';
    var Kind:= if pGate.After.TimedOut then CKindBuildTimeout else 'compile-error';
    var First:= if Length(pGate.After.Errors) > 0 then pGate.After.Errors[0] else '';
    Result.Refusals:= [MakeRefusal(Kind, '', pOpts.Project,
      Format('the project does not build after the edit (%d dcc line(s), first: %s); ', [Length(pGate.After.Errors), First]) +
      (if pGate.BaselineStatus = CStatusF2047 then 'the baseline already failed (F2047); a masked error may surface now -- fix it, then retry; ' else '') +
      (if Result.RolledBack then 'rolled back, project not changed' else 'the rollback FAILED: ' + Failure), 0)];
    Result.ExitCode:= if Result.RolledBack then CExitRefused else CExitError;
    if not Result.RolledBack then Result.Error:= 'compile error and the rollback FAILED: ' + Failure;
    Exit;
  end;
  try
    Result.Verify:= VerifyAfter(pStaged, pOpts, pStore);
  except
    on ECycleFixCancelled do
    begin
      { compiled, but the user asked to stop before the run ended: the owner ruling rolls EVERY file back }
      Result:= CancelledApply(Result, pOpts);
      Exit;
    end;
  end;
  Result.ExitCode:= if Result.Verify.Verified or pOpts.NoReindex then CExitMechanical else CExitApplyUnverified;
end;

// The text lines of an applied (or rolled-back) group.
procedure AddApplyLines(const pApply: TApplyReport; const pView: TCyclePlanView; pOut: TStrings);
begin
  if Length(pApply.Refusals) > 0 then
  begin
    pOut.Add(if pApply.RolledBack then 'rolled back, project not changed' else 'ERROR: ' + pApply.Error);
    for var R in pApply.Refusals do pOut.Add(RefusalLine(R));
    Exit;
  end;
  pOut.Add(Format('Applied: %d file(s) written, %d new; compile ok', [Length(pApply.Tx.Written), Length(pApply.Tx.NewFiles)]));
  for var B in pApply.Tx.Backups do pOut.Add('  backup: ' + B);
  pOut.Add(Format('Re-index: %s%s', [pApply.Verify.ReindexStatus,
    IfThen(pApply.Verify.ReindexReason <> '', ' (' + pApply.Verify.ReindexReason + ')')]));
  if pApply.Verify.Verified then
  begin
    pOut.Add('Verified: the re-indexed `cycles` output matches the prediction');
    Exit;
  end;
  pOut.Add('Not verified: ' + pApply.Verify.Reason);
  if pApply.Verify.Actual = '' then Exit;
  pOut.Add('Predicted:');
  pOut.AddStrings(pView.Predicted.Split([#10]));
  pOut.Add('Actual:');
  pOut.AddStrings(pApply.Verify.Actual.Split([#10]));
end;

// The text lines of a refused group: every refusal for an explicit group, the first one in a scan.
procedure AddRefusedLines(const pView: TCyclePlanView; const pVerdict: TArray<TRefusal>; pExplicit: Boolean; pOut: TStrings);
begin
  if pExplicit then
  begin
    pOut.Add(CVerdictRefused);
    for var R in pVerdict do pOut.Add(RefusalLine(R));
    Exit;
  end;
  pOut.Add(Format('Cycle %d: %s', [pView.CycleIndex, string.Join(' <-> ', pView.Units)]));
  pOut.Add(RefusalLine(pVerdict[0]));
end;

// Stages the plan in the shadow tree (StageShadow).
function StageFor(const pOpts: TCycleFixOptions; const pStaged: TCyclePlanView; const pProjectDir, pShadowDir: string): TArray<TRefusal>;
begin
  if pOpts.Apply then
    { WRITE PATH: --apply writes exactly this shadow into the project (WriteAll), so it is staged with
      pTamperAllowed = False -- the T9 tamper seam is dry-run only and must never reach a write }
    Result:= StageShadow(pStaged, pProjectDir, pShadowDir, False)
  else
    Result:= StageShadow(pStaged, pProjectDir, pShadowDir, TamperAllowed(pOpts));
end;

// The text lines of one visited group: applied / mechanical / refused.
procedure AddGroupLines(const pOpts: TCycleFixOptions; const pStaged: TCyclePlanView; const pVerdict: TArray<TRefusal>;
  pExplicit: Boolean; const pApplied: TApplyReport; const pShadowDir: string; pOut: TStrings);
begin
  if Length(pVerdict) > 0 then
    AddRefusedLines(pStaged, pVerdict, pExplicit, pOut)
  else if pOpts.Apply then
  begin
    { as the JSON's verdict: a run refused after the writes (cancelled, a compile error) is not mechanical }
    pOut.Add(if Length(pApplied.Refusals) > 0 then CVerdictRefused else 'Verdict: mechanical');
    AddApplyLines(pApplied, pStaged, pOut);
  end
  else
  begin
    pOut.Add(CVerdictOk);
    pOut.Add(CShadowLine + pShadowDir);
  end;
end;

const
  CDocMarker    = '{"schema":"' + CSchema + '"';
  CEdgeSection  = 3;                                // regex group of the edge's section in `cycles --edges`
  CEdgeIndent   = 6;                                // the indent of an edge line of `cycles --edges`
  CNoGroupsLine = 'No circular unit dependencies found.';
  CEnvAllChild  = 'DRAGLINT_CYCLEFIX_ALL_CHILD';   // test seam (project under TEMP): the exe the --part all children run
  CEnvAllPlant  = 'DRAGLINT_CYCLEFIX_ALL_PLANT';   // test seam (project under TEMP): a file copied over each child output file before the run

type
  // The state of one --part all run: the iterations' JSON, why it stopped, the exit code.
  TAllState = record
    Cycles    : TJSONArray;
    Baseline  : TJSONValue;
    Refusals  : TJSONValue;
    Error     : string;
    Stopped   : string;
    Code      : Integer;
    Iterations: Integer;
    Lines     : TStringList;
  end;

// A double-quoted command-line argument; trailing backslashes are dropped (they would escape the closing quote).
function Quoted(const pValue: string): string;
begin
  Result:= '"' + pValue.TrimRight(['\']) + '"';
end;

// The exe the --part all children run: this engine, or the DRAGLINT_CYCLEFIX_ALL_CHILD test seam.
function ChildExe(const pOpts: TCycleFixOptions): string;
begin
  Result:= ParamStr(0);
  if IsUnderTemp(pOpts.Project) and (GetEnvironmentVariable(CEnvAllChild) <> '') then
    Result:= GetEnvironmentVariable(CEnvAllChild);
end;

// Makes pOutFile ready for a child's output: deletes what an earlier run left (a failed launch must never
// make a stale file look like this run's result). Test seam CEnvAllPlant first plants a stale file there.
procedure PrepareChildOutput(const pOpts: TCycleFixOptions; const pOutFile: string);
begin
  ForceDirectories(ExtractFilePath(pOutFile));
  if IsUnderTemp(pOpts.Project) and (GetEnvironmentVariable(CEnvAllPlant) <> '') then
    TFile.Copy(GetEnvironmentVariable(CEnvAllPlant), pOutFile, True);
  if not Winapi.Windows.DeleteFile(PChar(pOutFile)) and (GetLastError <> ERROR_FILE_NOT_FOUND) then RaiseLastOSError;
end;

// The command line of one --part all iteration: a single-group --apply of the group holding pStem
// (its default part), as a child of this engine so it plans on the index the last iteration refreshed.
// Every target flag the parent received is forwarded (--library-db as often as given, --rules-dir).
function AllIterationCmd(const pOpts: TCycleFixOptions; const pStem: string): string;
begin
  Result:= Format('%s cycles --fix --apply --project %s --db %s --unit %s --format json',
    [Quoted(ChildExe(pOpts)), Quoted(pOpts.Project), Quoted(pOpts.Db), Quoted(pStem)]);
  if pOpts.Platform <> '' then Result:= Result + ' --platform ' + Quoted(pOpts.Platform);
  for var Lib in pOpts.LibraryDbs do Result:= Result + ' --library-db ' + Quoted(Lib);
  if pOpts.RulesDir <> '' then Result:= Result + ' --rules-dir ' + Quoted(pOpts.RulesDir);
  if pOpts.RsVars <> '' then Result:= Result + ' --rsvars ' + Quoted(pOpts.RsVars);
  if pOpts.NoBackup then Result:= Result + ' --no-backup';
  if pOpts.BuildTimeout <> '' then Result:= Result + ' --build-timeout ' + Quoted(pOpts.BuildTimeout);
end;

// pFile holds the child's stdout and stderr (merged); a stderr note can sit in front of the JSON on the same
// line, so the document is found by its opening marker. Parses from the last pMarker to the end of its line;
// nil when the marker is absent or the text is not JSON.
function ParseJsonFrom(const pFile, pMarker: string): TJSONValue;
begin
  Result:= nil;
  if not TFile.Exists(pFile) then Exit;
  var Text:= TFile.ReadAllText(pFile, TEncoding.ANSI);
  var From:= Text.LastIndexOf(pMarker);
  if From < 0 then Exit;
  var Stop:= Text.IndexOf(#10, From);
  Result:= TJSONObject.ParseJSONValue(Text.Substring(From, if Stop < 0 then MaxInt else Stop - From).Trim);
end;

type
  // One circular group as `cycles --edges` prints it.
  TListedGroup = record
    Units    : TArray<string>;
    Signature: string;   // sorted units + sorted `from>to:section` edges: equal = no edge was cut
  end;

// Closes pCur: fills its signature from pEdges, appends it to pOut, clears pEdges.
procedure FlushGroup(var pCur: TListedGroup; pEdges: TList<string>; pOut: TList<TListedGroup>);
begin
  var U:= Copy(pCur.Units);
  TArray.Sort<string>(U);
  pEdges.Sort;
  pCur.Signature:= string.Join(',', U) + '|' + string.Join(';', pEdges.ToArray);
  pOut.Add(pCur);
  pEdges.Clear;
  pCur:= Default(TListedGroup);
end;

// The groups of pText (`cycles --edges` output): units and edges, signature filled.
function ParseListedGroups(const pText: string): TArray<TListedGroup>;
begin
  var Edges:= TList<string>.Create;
  var Groups:= TList<TListedGroup>.Create;
  try
    var Cur: TListedGroup:= Default(TListedGroup);
    for var Line in pText.Split([#10]) do
    begin
      var H:= TRegEx.Match(Line, '^\s+\[\d+ units?\]\s+(.+?)\s{2,}\(');
      if H.Success then
      begin
        if Length(Cur.Units) > 0 then FlushGroup(Cur, Edges, Groups);
        Cur.Units:= LowerCase(H.Groups[1].Value).Split([' <-> ']);
        Continue;
      end;
      var E:= TRegEx.Match(Line, '^\s{' + IntToStr(CEdgeIndent) + '}(\S+) uses (\S+)\s+\[(interface|implementation)');
      if (Length(Cur.Units) > 0) and E.Success then
        Edges.Add(LowerCase(E.Groups[1].Value) + '>' + LowerCase(E.Groups[2].Value) + ':' + E.Groups[CEdgeSection].Value);
    end;
    if Length(Cur.Units) > 0 then FlushGroup(Cur, Edges, Groups);
    Result:= Groups.ToArray;
  finally
    Groups.Free;
    Edges.Free;
  end;
end;

// The first circular group of the (re-indexed) project DB that holds a unit of pMembers; False when none does.
// Raises when the child `cycles --edges` fails or its output is neither groups nor the no-groups line.
function NextGroup(const pOpts: TCycleFixOptions; const pMembers: TArray<string>; out pGroup: TListedGroup): Boolean;
begin
  Result:= False;
  pGroup:= Default(TListedGroup);
  var OutFile:= BuildScratchDir + 'all-groups.txt';
  PrepareChildOutput(pOpts, OutFile);
  var TimedOut:= False;
  var Code:= RunBounded('listing the circular groups', Format('%s cycles --db %s --edges', [Quoted(ChildExe(pOpts)), Quoted(pOpts.Db)]), OutFile, CReindexTimeoutMs, TimedOut);
  if TimedOut or (Code <> 0) or not TFile.Exists(OutFile) then
    raise EInvalidOperation.CreateFmt('could not list the circular groups of %s (exit %d)%s', [pOpts.Db, Code, CiteScratch(OutFile, ' (see %s)')]);
  var Text:= TFile.ReadAllText(OutFile, TEncoding.ANSI);
  var Groups:= ParseListedGroups(Text);
  if Length(Groups) = 0 then
  begin
    if not Text.Contains(CNoGroupsLine) then
      raise EInvalidOperation.CreateFmt('the group listing of %s is neither groups nor "%s"%s', [pOpts.Db, CNoGroupsLine, CiteScratch(OutFile, ' (see %s)')]);
    Exit;
  end;
  for var G in Groups do
    for var U in G.Units do
      if MatchText(U, pMembers) then
      begin
        pGroup:= G;
        Exit(True);
      end;
end;

// A child document without a cycles[] entry: a refusal before any group was planned (dirty-baseline, ...)
// keeps the child's exit code and gets a synthetic cycles[] entry carrying its refusals; exit 0 with no entry is a failure.
procedure EmptyIteration(const pObj: TJSONObject; const pStem: string; var S: TAllState);
begin
  if S.Code = CExitMechanical then
  begin
    S.Code   := CExitError;
    S.Error  := Format('iteration %d: the child run exited 0 but planned no group', [S.Iterations]);
    S.Stopped:= S.Error;
    Exit;
  end;
  var Entry:= TJSONObject.Create;
  Entry.AddPair('n', TJSONNumber.Create(0));
  Entry.AddPair('unit', pStem);
  Entry.AddPair('verdict', 'refused');
  if pObj.GetValue('refusals') <> nil then Entry.AddPair('refusals', pObj.GetValue('refusals').Clone as TJSONValue)
  else Entry.AddPair('refusals', TJSONArray.Create);
  Entry.AddPair('written', TJSONArray.Create);
  Entry.AddPair('rolled_back', TJSONBool.Create(False));
  Entry.AddPair('verified', TJSONBool.Create(False));
  S.Cycles.AddElement(Entry);
  S.Lines.Add(Format('Iteration %d: refused before a group was planned', [S.Iterations]));
  S.Stopped:= Format('iteration %d: refused before a group was planned (exit %d)', [S.Iterations, S.Code]);
end;

// One iteration: the child run for the group holding pStem; its cycle object is appended to S.Cycles.
// True = it applied something and exited 0; otherwise S.Code / S.Stopped / S.Error say why the loop ends.
function AllIteration(const pOpts: TCycleFixOptions; const pStem: string; var S: TAllState): Boolean;
begin
  Result:= False;
  Inc(S.Iterations);
  var OutFile:= BuildScratchDir + Format('all-iteration-%d.json', [S.Iterations]);
  var TimedOut:= False;
  PrepareChildOutput(pOpts, OutFile);
  S.Code:= RunBounded(Format('--part all iteration %d (%s)', [S.Iterations, pStem]), AllIterationCmd(pOpts, pStem), OutFile, ChildApplyLimitMs, TimedOut, {pEngineChild=}True);
  var Doc:= ParseJsonFrom(OutFile, CDocMarker);
  try
    if TimedOut or not (Doc is TJSONObject) then
    begin
      S.Code   := CExitError;
      S.Error  := Format('iteration %d: the child run printed no cycle-fix/1 document', [S.Iterations]) + CiteScratch(OutFile, ' (see %s)');
      S.Stopped:= S.Error;
      Exit;
    end;
    var Obj:= TJSONObject(Doc);
    if (S.Baseline = nil) and (Obj.GetValue('baseline') <> nil) then S.Baseline:= Obj.GetValue('baseline').Clone as TJSONValue;
    if Obj.GetValue('error') <> nil then S.Error:= Obj.GetValue('error').Value;
    var Arr:= Obj.GetValue('cycles') as TJSONArray;
    if (Arr = nil) or (Arr.Count = 0) then
    begin
      EmptyIteration(Obj, pStem, S);
      Exit;
    end;
    var Cy:= Arr.Items[0].Clone as TJSONObject;
    S.Cycles.AddElement(Cy);
    var Written:= Cy.GetValue('written') as TJSONArray;
    var WrittenCount:= if Written = nil then 0 else Written.Count;
    S.Lines.Add(Format('Iteration %d: part %s, edge %s: %d file(s) written, verified %s', [S.Iterations,
      Cy.GetValue('part').Value, Cy.GetValue('edge').Value, WrittenCount, Cy.GetValue('verified').ToString]));
    if S.Code <> CExitMechanical then
      S.Stopped:= Format('iteration %d ended with exit %d (%s)', [S.Iterations, S.Code,
        IfThen(Cy.GetValue('rolled_back').ToString = 'true', 'rolled back', 'see the cycle object')])
    else if WrittenCount = 0 then
    begin
      S.Code   := CExitRefused;
      S.Stopped:= Format('iteration %d: no edge is cuttable (nothing was cut)', [S.Iterations]);
    end
    else Result:= True;
  finally
    Doc.Free;
  end;
end;

// The --part all loop over the group pMembers: ApplyGroup, via one child `cycles --fix --apply --unit`
// per iteration, until the group is gone, an iteration fails, nothing is cuttable, or pBound (the group's
// edge count) is used up.
procedure LoopAll(const pOpts: TCycleFixOptions; const pMembers: TArray<string>; pBound: Integer; var S: TAllState);
begin
  var Group: TListedGroup;
  if not NextGroup(pOpts, pMembers, Group) then
  begin
    S.Stopped:= 'the selected group is not circular';
    Exit;
  end;
  while AllIteration(pOpts, Group.Units[0], S) do
  begin
    var Before:= Group.Signature;
    if not NextGroup(pOpts, pMembers, Group) then
    begin
      S.Stopped:= Format('the selected circular group is gone after %d iteration(s)', [S.Iterations]);
      Exit;
    end;
    if Group.Signature = Before then
    begin
      S.Code   := CExitRefused;
      S.Stopped:= Format('iteration %d: no edge is cuttable (the group is unchanged: same units, same edges)', [S.Iterations]);
      Exit;
    end;
    if S.Iterations >= pBound then
    begin
      S.Code   := CExitRefused;
      S.Stopped:= Format('stopped after %d iteration(s), the bound (the group had %d edge(s)); it is still circular', [S.Iterations, pBound]);
      Exit;
    end;
  end;
end;

// Prints the --part all result: the cycle-fix/1 document (cycles[] = every iteration) or the text lines.
procedure PrintAll(const pOpts: TCycleFixOptions; var S: TAllState);
begin
  if pOpts.Json then
  begin
    var Doc:= NewRunDoc(pOpts);
    try
      Doc.AddPair('part', CPartAll);
      Doc.AddPair('iterations', TJSONNumber.Create(S.Iterations));
      Doc.AddPair('stopped', S.Stopped);
      Doc.AddPair('cycles', S.Cycles);
      S.Cycles:= nil;
      if S.Baseline <> nil then Doc.AddPair('baseline', S.Baseline);
      S.Baseline:= nil;
      if S.Refusals <> nil then Doc.AddPair('refusals', S.Refusals)
      else Doc.AddPair('refusals', TJSONArray.Create);
      S.Refusals:= nil;
      if S.Error <> '' then Doc.AddPair('error', S.Error);
      Doc.AddPair('ok', TJSONBool.Create(S.Code = CExitMechanical));
      Doc.AddPair('exit_code', TJSONNumber.Create(S.Code));
      Writeln(Doc.ToJSON);
    finally
      Doc.Free;
    end;
  end
  else
  begin
    for var Line in S.Lines do Writeln(Line);
    Writeln(S.Stopped);
    if S.Error <> '' then Writeln('ERROR: ', S.Error);
  end;
end;

// `--part all --apply`: loops over the group selected by pOnly (0 = cycle 1). Every iteration is
// ApplyGroup in a child run (it re-plans on the refreshed index); the first failure ends the loop and
// keeps the earlier iterations applied (each one compiled and verified).
function RunAll(const pOpts: TCycleFixOptions; const pSccs: TList<TArray<string>>; const pGraph: TCycleGraph;
  pOnly: Integer): Integer;
var
  S: TAllState;
begin
  S:= Default(TAllState);
  S.Cycles:= TJSONArray.Create;
  S.Lines := TStringList.Create;
  try
    if pSccs.Count = 0 then
    begin
      S.Stopped:= CCycleNone;
      PrintAll(pOpts, S);
      Exit(CExitMechanical);
    end;
    var Members:= pSccs[Max(pOnly, 1) - 1];
    try
      LoopAll(pOpts, Members, Max(IntfEdgeCount(Members, pGraph, False), 1), S);
    except
      on ECycleFixCancelled do
      begin
        { taken between iterations (a `cycles --edges` child): nothing of the next iteration was written }
        S.Code   := CExitRefused;
        S.Stopped:= Format('cancelled -- after %d iteration(s); those stay applied, nothing else was written', [S.Iterations]);
      end;
      on E: Exception do
      begin
        S.Code   := CExitError;
        S.Error  := E.ClassName + ': ' + E.Message;
        S.Stopped:= 'the --part all loop could not continue';
      end;
    end;
    { a child that stood down itself ended its iteration with its own (rolled-back) result: say why }
    if GCancelTaken and not StartsText('cancelled', S.Stopped) then S.Stopped:= 'cancelled -- ' + S.Stopped;
    Result:= S.Code;
    PrintAll(pOpts, S);
  finally
    S.Lines.Free;
    S.Cycles.Free;
    S.Baseline.Free;
    S.Refusals.Free;
  end;
end;

// E18 T16: a run without --cycle / --unit (pOnly = 0) plans one group and stops; when there are
// several groups, prints one line naming those it did not plan (pPlanned: the visited groups'
// numbers), so they are never left implied. Prints nothing when every group was planned.
procedure WriteNotPlanned(pOnly, pCount: Integer; const pPlanned: TList<Integer>);
var
  Rest: TList<string>;
begin
  if (pOnly <> 0) or (pCount < 2) then Exit;
  Rest:= TList<string>.Create;
  try
    for var I:= 1 to pCount do
      if not pPlanned.Contains(I) then Rest.Add(IntToStr(I));
    if Rest.Count > 0 then
      Writeln('Not planned: cycle(s) ' + string.Join(', ', Rest.ToArray) + ' -- this run plans one group; add --cycle <n> to plan another');
  finally
    Rest.Free;
  end;
end;

// The dry run's `Shadow tree: <dir>` line, told what becomes of the dir at exit (E18 final review F5): a
// default dir is deleted at exit unless a message of the run cites a file in its scratch (CiteScratch,
// DeleteDefaultScratch); --shadow-out is never deleted and keeps the line as it is.
function ShadowLineAtExit(const pLine: string; const pOpts: TCycleFixOptions): string;
begin
  Result:= pLine;
  if (pOpts.ShadowOut <> '') or not StartsStr(CShadowLine, pLine) then Exit;
  Result:= pLine + (if GScratchCited then ' (kept: this run cites a file in its scratch)' else ' (deleted at exit; --shadow-out keeps it)');
end;

function RunCycleFixGroups(const pOpts: TCycleFixOptions; const pStore: ISymbolStore;
  const pSccs: TList<TArray<string>>; const pGraph: TCycleGraph; const pLibStore: ISymbolStore): Integer;
var
  Problem : string;
  Own     : TOwnRoots;
  Only    : Integer;
  Cycles  : TJSONArray;
  Playbook: TStringList;
  Summary : TStringList;
  Planned : TList<Integer>;
  Chosen  : Boolean;
  BadPart : string;
  ProjectDir: string;
  ShadowDir : string;
  ShadowUsed: string;
  Gate      : TGateReport;
  Brk       : Integer;
  Probe     : Boolean;
  ProbeTree : string;
  ProbeLines: string;
  Applied   : TApplyReport;
begin
  Problem:= ResolveSelection(pOpts, pSccs, Own, Only);
  if Problem <> '' then
  begin
    ReportError(pOpts, Problem);
    Exit(CExitError);
  end;

  Chosen  := False;
  BadPart := '';
  ShadowUsed:= '';
  Applied := NoApply;
  Brk:= AnnounceSeams(pOpts, Probe, ProbeTree, ProbeLines);
  if not PassBaselineGate(pOpts, pSccs.Count > 0, Gate) then Exit(CExitRefused);
  ProjectDir:= ExtractFilePath(ExpandFileName(pOpts.Project));
  ShadowDir := if pOpts.ShadowOut <> '' then IncludeTrailingPathDelimiter(ExpandFileName(pOpts.ShadowOut)) else DefaultShadowDir;
  Cycles  := TJSONArray.Create;
  Playbook:= TStringList.Create;
  Summary := TStringList.Create;
  Planned := TList<Integer>.Create;
  try
    VisitCyclePlans(pStore, pOpts.Db, pSccs, pGraph, pLibStore,
      function(const pView: TCyclePlanView; const pRender: TFunc<TArray<string>>): Boolean
      var
        All: TList<TRefusal>;
      begin
        { the after gate's results belong to ONE group: never carried into the next group's JSON }
        Gate.After      := Default(TCompileAfterResult);
        Gate.AfterStatus:= CStatusSkipped;
        Gate.AfterFiles := 0;
        All:= TList<TRefusal>.Create;
        try
          All.AddRange(pView.Refusals);
          All.AddRange(MechanisabilityGate(pView, Own));
          All.AddRange(StaleRefusals(pStore, pView));
          var Wanted:= pOpts.Part;
          if (Wanted <> '') and not SameText(Wanted, string(pView.Part)) then
          begin
            { an explicit group is an error; a scan just skips the groups of the other part }
            if Only > 0 then
              BadPart:= Format('cycles --fix: cycle %d is planned as part %s, not --part %s ' +
                '(the other part comes with --part all, E18 Task 12)', [pView.CycleIndex, LowerCase(pView.Part), Wanted]);
            Exit(Only = 0);
          end;
          { a plan the gate passes is staged in the shadow tree; an anchor mismatch refuses the group }
          { DRAGLINT_CYCLEFIX_BREAK (test seam, project under TEMP only) spoils the plan before staging }
          All.AddRange(BaselineGroupRefusals(Gate, pView, pOpts.Project));
          var Staged:= pView;
          if Brk <> 0 then Staged:= ApplyTestBreak(pView, Brk);
          if All.Count = 0 then All.AddRange(StageFor(pOpts, Staged, ProjectDir, ShadowDir));
          var Verdict:= All.ToArray;
          if Length(Verdict) = 0 then ShadowUsed:= ShadowDir;
          if (Length(Verdict) = 0) and Probe then RunRepairProbe(Staged, pOpts, ProjectDir, ProbeTree, ProbeLines, Gate);
          { --apply: write the shadow under backups, build in place (repair once), roll back or verify }
          if (Length(Verdict) = 0) and pOpts.Apply then
            Applied:= ApplyGroup(Staged, pOpts, ProjectDir, ShadowDir, pStore, Gate);
          var Report:= if Applied.Ran then Applied else NoApply;
          Cycles.AddElement(CycleToJson(pView, Verdict + Report.Refusals, pGraph, Gate, Report));
          Planned.Add(pView.CycleIndex);
          Chosen:= Length(Verdict) = 0;
          if (not pOpts.Json) and ((Only > 0) or Chosen) then Playbook.AddStrings(pRender());
          if not (Chosen and pOpts.Json) then AddGroupLines(pOpts, Staged, Verdict, Only > 0, Applied, ShadowDir, Summary);
          Exit(not Chosen);
        finally
          All.Free;
        end;
      end, Only);
    if BadPart <> '' then
    begin
      ReportError(pOpts, BadPart);
      Exit(CExitError);
    end;
    Result:= if Chosen or (pSccs.Count = 0) then CExitMechanical else CExitRefused;
    if Applied.Ran then Result:= Applied.ExitCode;
    if pOpts.Json then
    begin
      var Doc:= NewRunDoc(pOpts);
      try
        Doc.AddPair('cycles', Cycles);
        Cycles:= nil;
        if ShadowUsed <> '' then
        begin
          Doc.AddPair('shadow', ShadowUsed);
          { F5: the default shadow is deleted at exit unless the run cites a file in its scratch; --shadow-out is kept }
          Doc.AddPair('shadow_kept', TJSONBool.Create((pOpts.ShadowOut <> '') or GScratchCited));
        end;
        Doc.AddPair('baseline', BaselineToJson(Gate));
        Doc.AddPair('refusals', TJSONArray.Create);
        if Applied.Error <> '' then Doc.AddPair('error', Applied.Error);
        Doc.AddPair('ok', TJSONBool.Create(Result = CExitMechanical));
        Doc.AddPair('exit_code', TJSONNumber.Create(Result));
        Writeln(Doc.ToJSON);
      finally
        Doc.Free;
      end;
    end
    else
    begin
      if pSccs.Count = 0 then Writeln(CCycleNone);
      for var Line in Playbook do Writeln(Line);
      for var Line in Summary do Writeln(ShadowLineAtExit(Line, pOpts));
      if (pSccs.Count > 0) and (Only = 0) and not Chosen then Writeln(CVerdictRefused);
      WriteNotPlanned(Only, pSccs.Count, Planned);
      var Timing:= TimingLine(Gate);
      if Timing <> '' then Writeln(Timing);
    end;
  finally
    Planned.Free;
    Summary.Free;
    Playbook.Free;
    Cycles.Free;
  end;
end;

// `--part all`: select the group (the flags are checked as for the single run), then loop.
function RunAllSelected(const pOpts: TCycleFixOptions; const pSccs: TList<TArray<string>>; const pGraph: TCycleGraph): Integer;
var
  Own : TOwnRoots;
  Only: Integer;
begin
  var Problem:= ResolveSelection(pOpts, pSccs, Own, Only);
  if Problem <> '' then
  begin
    ReportError(pOpts, Problem);
    Result:= CExitError;
  end
  else Result:= RunAll(pOpts, pSccs, pGraph, Only);
end;

// E18 T13 fix round: the scratch THIS run created -- the default shadow dir (never a user's --shadow-out)
// and the compile gate's _build dir -- is deleted when the run ends. E18 final review F5 (amended): a run
// whose output cites a file in there (CiteScratch: a build log, reindex.log, all-iteration-<n>.json, ...)
// KEEPS it and names it on stderr, so the cited file exists; an ordinary refusal cites none and deletes it.
// DRAGLINT_CYCLEFIX_KEEP_SCRATCH=1 keeps it always, for a test that inspects it.
procedure DeleteDefaultScratch(const pOpts: TCycleFixOptions; pExitCode: Integer);
const
  CKeepScratchVar = 'DRAGLINT_CYCLEFIX_KEEP_SCRATCH';
begin
  if GetEnvironmentVariable(CKeepScratchVar) = '1' then Exit;
  { only the names this run picked (FreshScratchName: they did not exist then); a run that never needed
    a default dir picked none and deletes nothing }
  var Dirs: TArray<string>:= [GBuildPick];
  if pOpts.ShadowOut = '' then Dirs:= Dirs + [GShadowPick];
  if GScratchCited then
  begin
    for var D in Dirs do
      if (D <> '') and TDirectory.Exists(D) then
        Writeln(ErrOutput, Format('drag-lint: note: cycles --fix exited %d; its scratch is kept for the files it cites: %s', [pExitCode, D]));
    Exit;
  end;
  for var D in Dirs do
    if D <> '' then
    try
      if TDirectory.Exists(D) then TDirectory.Delete(D, True);
    except
      on EInOutError do Writeln(ErrOutput, 'drag-lint: note: scratch not deleted: ', D); // best effort: a locked file must not change the run's result
    end;
end;

const
  CReindexedEnv = 'DRAGLINT_CYCLEFIX_REINDEXED'; // set for the one re-run after the pre-plan re-index (A1)

// A1: the number of indexed .pas / .dpr files whose bytes changed since they were indexed.
function CountStaleFiles(const pStore: ISymbolStore): Integer;
begin
  Result:= 0;
  for var FS in pStore.GetAllFileStamps do
    if MatchText(ExtractFileExt(FS.Path), ['.pas', '.dpr']) and not FileStampIsCurrent(pStore, FS.Path) then Inc(Result);
end;

// A1 (stale-file / anchor-mismatch recipe): an --apply run that finds indexed files changed on disk
// re-indexes the project incrementally ONCE and runs itself again, so the plan, the unit set and the gate all
// start from the current text. The re-run carries CReindexedEnv: a file stale after that is another process
// writing it and keeps the stale-file refusal. Returns False when nothing was done (the run goes on as before).
function RerunAfterReindex(const pOpts: TCycleFixOptions; const pStore: ISymbolStore; out pExit: Integer): Boolean;
var
  Proj    : string;
  TimedOut: Boolean;
begin
  Result:= False;
  pExit := CExitError;
  if not pOpts.Apply or pOpts.NoReindex or SameText(pOpts.Part, CPartAll) or (GetEnvironmentVariable(CReindexedEnv) <> '') then Exit;
  var Stale:= CountStaleFiles(pStore);
  if Stale = 0 then Exit;
  if ReindexTargetProblem(Default(TCyclePlanView), pOpts, pStore, Proj) <> '' then Exit;
  var Dir:= BuildScratchDir;
  var Watch:= TStopwatch.StartNew;
  var Code:= -1;
  TimedOut:= False; { read below even when RunBounded raised before assigning its out param }
  try
    Code:= RunBounded('re-index of the stale files', Format('"%s" index --project "%s" --db "%s"', [ParamStr(0), Proj, pOpts.Db]),
      Dir + 'reindex-before.log', CReindexTimeoutMs, TimedOut);
  except
    on ECycleFixCancelled do raise; { nothing written yet: RunCycleFix reports it }
    on Exception do Code:= -1;
  end;
  if TimedOut or (Code <> 0) then Exit; // the stale-file refusal then says what is wrong, as before
  var Secs:= Watch.ElapsedMilliseconds / MSecsPerSec;
  Winapi.Windows.SetEnvironmentVariable(PChar(CReindexedEnv), '1');
  try
    var OutFile:= Dir + 'rerun.out';
    pExit:= RunBounded('re-run after the re-index', string(CmdLine), OutFile, ChildApplyLimitMs, TimedOut, {pEngineChild=}True);
    var Text:= if TFile.Exists(OutFile) then TFile.ReadAllText(OutFile, TEncoding.ANSI) else '';
    { the child's stderr notes share its capture file: they go back to stderr, the document stays on stdout }
    var Brace:= Pos('{"schema"', Text);
    if pOpts.Json and (Brace > 1) then
    begin
      Write(ErrOutput, Copy(Text, 1, Brace - 1));
      Text:= Copy(Text, Brace, MaxInt);
    end;
    { ...and a note the child flushed AFTER its document (stderr is unbuffered, stdout is not, so
      the order in the shared file is not the write order) goes back to stderr too. }
    var LastBrace:= LastDelimiter('}', Text);
    if pOpts.Json and (Brace > 0) and (LastBrace > 0) and (Trim(Copy(Text, LastBrace + 1, MaxInt)) <> '') then
    begin
      Write(ErrOutput, Copy(Text, LastBrace + 1, MaxInt));
      Text:= Copy(Text, 1, LastBrace);
    end;
    var Doc:= if pOpts.Json then TJSONObject.ParseJSONValue(Text) else nil;
    try
      if Doc is TJSONObject then
      begin
        var Info:= TJSONObject.Create;
        Info.AddPair('status', 'ok');
        Info.AddPair('files', TJSONNumber.Create(Stale));
        Info.AddPair('seconds', TJSONNumber.Create(RoundTo(Secs, CJsonDecimals)));
        TJSONObject(Doc).AddPair('reindex_before', Info);
        Writeln(Doc.ToJSON);
      end
      else
      begin
        if not pOpts.Json then Writeln(Format('re-indexed before planning (%d files, %.1f s)', [Stale, Secs]));
        Write(Text);
      end;
    finally
      Doc.Free;
    end;
  finally
    Winapi.Windows.SetEnvironmentVariable(PChar(CReindexedEnv), nil);
  end;
  Result:= True;
end;

// Opens the run's control channel (ControlChannelEnabledFor('cycles')), so `drag-lint shutdown` and the IDE's
// Cancel can ask the run to stand down; nil when it could not listen (said on stderr: a cancel then kills).
function StartStandDownChannel(const pOpts: TCycleFixOptions): TControlChannel;
begin
  Result:= nil;
  if not ControlChannelEnabledFor('cycles') then Exit;
  Result:= TControlChannel.Create([ExpandFileName(pOpts.Db)], DRAGLINT_VERSION, DRAGLINT_EXTRACTOR_VERSION, 'cycles');
  var Err: string;
  if not Result.Start(Err) then
  begin
    Writeln(ErrOutput, 'cycles --fix: control channel NOT started (' + Err + '); a cancel will kill this run instead of rolling it back');
    FreeAndNil(Result);
  end;
end;

// A stand-down taken before any file was written: the cycle-fix/1 error document (exit_code 1) or `ERROR:`.
procedure ReportCancelledBeforeWrite(const pOpts: TCycleFixOptions);
const
  CMessage = 'cancelled -- nothing written';
begin
  if not pOpts.Json then
  begin
    Writeln('ERROR: ', CMessage);
    Exit;
  end;
  var Doc:= NewRunDoc(pOpts);
  try
    Doc.AddPair('error', CMessage);
    Doc.AddPair('cancelled', TJSONBool.Create(True));
    Doc.AddPair('ok', TJSONBool.Create(False));
    Doc.AddPair('exit_code', TJSONNumber.Create(CExitRefused));
    Writeln(Doc.ToJSON);
  finally
    Doc.Free;
  end;
end;

function RunCycleFix(const pOpts: TCycleFixOptions; const pStore: ISymbolStore;
  const pSccs: TList<TArray<string>>; const pGraph: TCycleGraph; const pLibStore: ISymbolStore): Integer;
begin
  Result:= CExitError; { the exit code the kept-scratch note prints when an exception leaves this code }
  var Opts: TCycleFixOptions:= pOpts;
  Opts.Platform:= CycleFixPlatform(pOpts); { ruling a3: every build, child run and JSON echo use ONE platform }
  var Ctl:= StartStandDownChannel(Opts);
  GStandDown  := Ctl;
  GCancelTaken:= False;
  GProgressDb := ExpandFileName(Opts.Db);
  try
    try
      if RerunAfterReindex(Opts, pStore, Result) then Exit;
      try
        Result:= if SameText(Opts.Part, CPartAll) then RunAllSelected(Opts, pSccs, pGraph)
                 else RunCycleFixGroups(Opts, pStore, pSccs, pGraph, pLibStore);
      finally
        DeleteDefaultScratch(Opts, Result);
      end;
    except
      on ECycleFixCancelled do
      begin
        { taken before WriteAll (ApplyGroup handles every later one): the project was not touched }
        ReportCancelledBeforeWrite(Opts);
        Result:= CExitRefused;
      end;
    end;
  finally
    GStandDown:= nil;
    if Ctl <> nil then
    begin
      { the run is over -- rolled back, or finished with its own result: a pending or taken request gets `exiting` }
      Ctl.StandDownComplete;
      Ctl.Free;
    end;
  end;
end;

end.
