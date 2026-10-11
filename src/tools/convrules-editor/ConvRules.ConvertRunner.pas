unit ConvRules.ConvertRunner;

{ Executes a Convert run (spec 2026-09-29, part 2, "Run flow"): reindex the
  project before a unit's first book and after every book (convert-apply finds
  and patches .dfm blocks at the index's line ranges), back every unit up ONCE
  (.pas and .dfm share one .BCK<N> number), apply each runnable book in order,
  and restore a unit from
  its backup the moment a unit-level step fails -- a unit is never left
  half-converted, and the rows say so. A book whose rules fail the engine's
  own validation (its rule_errors) is skipped for the rest of the run:
  convert-validate without a From/To pair checks syntax only (measured
  2026-09-29), so it cannot be the pre-check. Runs on a worker thread; no VCL. }

interface

uses
  System.SysUtils
  , ConvRules.Engine
  , ConvRules.ConvertRun
  , ConvRules.ConvertRequest
  , ConvRules.WorkList
  ;

const
  /// <summary>The run report's Status column on an E10 `inherited left` line
  /// (InheritedReportLines).</summary>
  REPORT_STATUS_INHERITED_LEFT = 'inherited left';
  /// <summary>The run report's Status column on a glyph outcome line
  /// (GlyphReportLines).</summary>
  REPORT_STATUS_GLYPH = 'glyph';
  /// <summary>The run report's Status column on a cast-not-applied line (ApplyItemReportLines).</summary>
  REPORT_STATUS_CAST_SITE = 'cast site';
  /// <summary>The run report's Status column on a value-cast-applied line.</summary>
  REPORT_STATUS_VALUE_CAST = 'value cast';
  /// <summary>The run report's Status column on a value-cast-check line.</summary>
  REPORT_STATUS_VALUE_CHECK = 'value check';
  /// <summary>The run report's Status column on a uses[] line is this + the row's action
  /// ('uses add', 'uses kept', ...); an unresolved entry is 'uses unresolved'.</summary>
  REPORT_STATUS_USES = 'uses ';
  /// <summary>convert-apply's exit code for a CONFIGURATION error -- an unusable cast
  /// library (engine 1.28.0; 2 stays write failure / rollback, 1 a unit failure). It
  /// stops the whole run: every later apply would fail the same way.</summary>
  ENGINE_EXIT_CONFIG = 6;

type
  /// <summary>Outcome of one results-grid row.</summary>
  /// <remarks>
  /// csConverted: the book converted the unit and the reindex after it succeeded.
  /// csFailedRestored: the book's apply (or the reindex after it) failed -- a
  ///   half-written apply (ApplyHalfWritten: ok=true, but one file's edits refused)
  ///   counts as failed; the unit and its .dfm were restored from this run's
  ///   backup and the unit's remaining books did not run. An engine 1.25.1+
  ///   edit-set refusal (ApplyEditSetRefused: nothing written) is csRefused.
  /// csBookSkipped: the book failed the engine's validation (rule_errors) and the
  ///   reply is not a refusal; the unit is untouched by it and the book is not
  ///   tried on any later unit.
  /// csUnitSkipped: the unit was not run at all -- not found on disk, the
  ///   reindex before its first book failed (no backup is taken, the engine is
  ///   not called), or its backup could not be taken (any .BCK already made for
  ///   it is removed).
  /// csRolledBack: the book HAD converted the unit, but a later book failed on
  ///   the same unit and the restore undid this book's change too.
  /// csRestoreFailed: a book failed AND the restore from the backup raised; the
  ///   unit may be half-converted, the Note names the backups (.pas and .dfm)
  ///   to restore by hand.
  /// csRefused: the engine refused this book on the unit (TApplyRow.Refused, or
  ///   an engine 1.25.1+ edit-set refusal, ApplyEditSetRefused), whether or not the reply also lists rule_errors; the book stays valid for
  ///   later units. The unit's remaining books do not run and it ends unchanged. When an
  ///   earlier book had converted the unit, it is restored like a failure (those
  ///   rows become csRolledBack) and the backup is kept and named. When nothing
  ///   had changed it (the refused book was its first, or every earlier one was
  ///   skipped), nothing is restored and the unneeded backup is DROPPED, as for
  ///   csBookSkipped: Backup / BackupDfm are '' on the row.
  /// csOutOfScope: a scoped run (IDE request) found no selected instance of this
  ///   book's From types on the unit; no engine call, no backup kept for it, the
  ///   unit's later books still run.
  /// csConfigError: convert-apply exited ENGINE_EXIT_CONFIG (the cast library is
  ///   unusable). The RUN stops: no later book or unit is tried. The unit is restored
  ///   only when an earlier book had changed it (its rows become csRolledBack); else
  ///   nothing is restored and the backup is dropped, as for a first-book refusal.
  ///   Note = the engine's error text. TConvertRow.StoppedRun marks the stop, also when a
///   failed restore turns the row into csRestoreFailed.
  /// </remarks>
  TConvertStatus = (csConverted, csFailedRestored, csBookSkipped, csUnitSkipped, csRolledBack, csRestoreFailed, csRefused, csOutOfScope, csConfigError);

  /// <summary>One results-grid row: a book x unit, or a unit-level skip.</summary>
  TConvertRow = record
    /// <summary>The .rules path; '' on a csUnitSkipped row.</summary>
    Book   : string;
    /// <summary>The .pas path; on a csBookSkipped row, the unit whose apply
    /// found the book invalid (that unit is untouched by it).</summary>
    UnitPas: string;
    /// <summary>The .pas backup this run made; '' when none, and '' on a
    /// csBookSkipped row (the book did not touch the unit).</summary>
    Backup : string;
    /// <summary>The .dfm backup this run made, numbered like Backup (one shared
    /// N per unit, SharedBackupPaths); '' when the unit has no .dfm, and
    /// wherever Backup is ''.</summary>
    BackupDfm: string;
    /// <summary>Human-readable reason / summary. Also records an unneeded
    /// backup that could not be deleted (it is then kept).</summary>
    Note   : string;
    /// <summary>What happened.</summary>
    Status : TConvertStatus;
    /// <summary>The engine's report when convert-apply ran.</summary>
    Apply  : TApplyRow;
    /// <summary>True on the row whose apply exited ENGINE_EXIT_CONFIG: the RUN stopped
    /// here. Set whatever the restore did -- the row is csConfigError, or
    /// csRestoreFailed when the restore of an earlier book's change failed.</summary>
    StoppedRun: Boolean;
  end;

  /// <summary>Everything a run needs; built by the Convert tab.</summary>
  TConvertJob = record
    /// <summary>Runnable books (Preflight.Runnable), application order.</summary>
    Books      : TArray<string>;
    /// <summary>Source units (.pas).</summary>
    Units      : TArray<string>;
    /// <summary>--db list: project DB FIRST, then the libraries.</summary>
    Dbs        : TArray<string>;
    /// <summary>The project DB reindexed before each unit and after each book.</summary>
    ProjectDb  : string;
    /// <summary>The .dproj/.dpr that owns ProjectDb -- always the DB's own
    /// project file (ProjectFileForDb), never the Unit Rules Destination: an
    /// `index --project` of another project would re-scope this DB.</summary>
    ProjectFile: string;
    /// <summary>The engine reports inherited_instances (C8): a converted row's note then
    /// lists the inherited instances it left (apply/1 inherited[]). False = today's
    /// handling (the engine refuses such a unit).</summary>
    InheritedSupported: Boolean;
    /// <summary>The engine reports inherited_retype (C8 N2): an inherited instance under a
    /// converted ancestor is retyped. False = the notes say the unit still has the From
    /// type there and may not compile or load.</summary>
    RetypeSupported: Boolean;
    /// <summary>The IDE request's scope; Kind = skWholeUnit for an ordinary run. It
    /// binds Scope.UnitPas only (ScopedNamesForUnit): any other unit is converted
    /// whole.</summary>
    Scope: TConvertScope;
    /// <summary>The engine's 1.27.0 apply/1 features (ApplyFeaturesOf the tab's
    /// capability probe); [] = an older engine, read as before.</summary>
    ApplyFeatures: TApplyFeatures;
    /// <summary>The Convert tab's run counter (1, 2, ...); the run's Work list rows
    /// carry it (WorkRunOf), so a new run replaces the list and never mixes with it.</summary>
    RunId: Integer;
  end;

  /// <summary>Called once per row (worker thread!). A unit's rows arrive
  /// together when that unit has finished, already in their final status.</summary>
  TConvertProgress = reference to procedure(const ARow: TConvertRow; ADone, ATotal: Integer);

  /// <summary>Applies one book to one unit in place; the shape of
  /// TEngineAdapter.ApplyConversion with the --db list bound.</summary>
  TApplyFn = reference to function(const AUnitPas, ARulesFile: string; out AJson: string): Integer;

  /// <summary>Refreshes the project index; the shape of
  /// TEngineAdapter.IndexProject with the project bound. 0 = success.</summary>
  TIndexFn = reference to function(out AOutput: string): Integer;

  /// <summary>TApplyFn with the --only names: the shape of the AOnly overload of
  /// TEngineAdapter.ApplyConversion with the --db list bound.</summary>
  /// <remarks>AOnly = [] means the plain call, with no --only.</remarks>
  TApplyOnlyFn = reference to function(const AUnitPas, ARulesFile: string; const AOnly: TArray<string>; out AJson: string): Integer;

  /// <summary>The scope decision for one unit x book (ScopedNamesForUnit with the
  /// job's scope bound). True = scoped: ANames go to --only, and [] means the book
  /// has nothing in scope on the unit (csOutOfScope, no engine call). False = the
  /// whole unit, no --only.</summary>
  TScopeFn = reference to function(const AUnitPas, ABook: string; out ANames: TArray<string>): Boolean;

  /// <summary>The note tail for a scoped apply that failed with no refusal and no edit
  /// (UnmatchedOnlyHintFor with the job's scope bound).</summary>
  TOnlyHintFn = reference to function(const AOnly: TArray<string>): string;

  /// <summary>What a Convert run is doing right now (C16).</summary>
  /// <remarks>Per unit: rpReindexBefore, rpBackup, then per book rpApply and, after a
  /// successful apply, rpReindexAfter; rpRestore follows the step that failed when the
  /// unit is copied back from its backup. rpFinalReindex is the closing refresh the
  /// Convert tab runs after the unit loop -- the runner never emits it.</remarks>
  TRunPhase = (rpReindexBefore, rpBackup, rpApply, rpReindexAfter, rpRestore, rpFinalReindex);

  /// <summary>One progress step of a run: emitted as the phase STARTS.</summary>
  TRunStep = record
    /// <summary>The phase starting now.</summary>
    Phase         : TRunPhase;
    /// <summary>1-based position of the unit in the job; 0 on rpFinalReindex.</summary>
    UnitNo        : Integer;
    /// <summary>Units in the job.</summary>
    UnitCount     : Integer;
    /// <summary>The unit's .pas path; '' on rpFinalReindex.</summary>
    UnitPas       : string;
    /// <summary>1-based position of the book in the job's book list; 0 on a unit-level
    /// phase (rpReindexBefore, rpBackup) and on rpFinalReindex.</summary>
    BookNo        : Integer;
    /// <summary>Books in the job.</summary>
    BookCount     : Integer;
    /// <summary>The book's .rules path; '' when BookNo = 0.</summary>
    Book          : string;
    /// <summary>Milliseconds since the unit's first step.</summary>
    UnitElapsedMs : Int64;
    /// <summary>Milliseconds since the run started; never less than UnitElapsedMs.</summary>
    TotalElapsedMs: Int64;
  end;

  /// <summary>Receives each TRunStep (worker thread!).</summary>
  TRunStepFn = reference to procedure(const AStep: TRunStep);

/// <summary>Runs a whole job (AJob.Books over AJob.Units).</summary>
/// <param name="AJob">The job.</param>
/// <param name="AEngine">An adapter owned by the caller's thread.</param>
/// <param name="AProgress">May be nil.</param>
/// <param name="ACancelled">May be nil; polled exactly once just before each unit (never between two books of one unit); True stops the run there.</param>
/// <param name="AOnStep">May be nil; receives every TRunStep (C16).</param>
/// <returns>One row per unit x book attempted; an invalid book yields one
/// csBookSkipped row (on the first unit that tried it) and is not tried again.</returns>
function RunConversion(const AJob: TConvertJob; AEngine: TEngineAdapter; const AProgress: TConvertProgress; const ACancelled: TFunc<Boolean>; const AOnStep: TRunStepFn): TArray<TConvertRow>;

/// <summary>The unit loop of RunConversion, for books already validated,
/// against the real engine (AJob.Dbs, AJob.ProjectFile, AJob.ProjectDb).</summary>
/// <param name="AUnits">Source units.</param>
/// <param name="ABooks">Validated books, application order.</param>
/// <param name="AJob">Supplies Dbs, ProjectDb, ProjectFile.</param>
/// <param name="AEngine">Engine adapter.</param>
/// <param name="AProgress">May be nil.</param>
/// <param name="ACancelled">May be nil; polled exactly once just before each unit; True stops the run there.</param>
/// <returns>See the TApplyFn overload.</returns>
function RunConversionUnits(const AUnits, ABooks: TArray<string>; const AJob: TConvertJob; AEngine: TEngineAdapter; const AProgress: TConvertProgress; const ACancelled: TFunc<Boolean>): TArray<TConvertRow>; overload;

/// <summary>The unit loop with the engine calls injected.</summary>
/// <param name="AUnits">Source units.</param>
/// <param name="ABooks">Validated books, application order.</param>
/// <param name="AApply">Applies one book to one unit.</param>
/// <param name="AIndex">Reindexes before each unit's first book and after each
/// successful apply.</param>
/// <param name="AProgress">May be nil.</param>
/// <param name="ACancelled">May be nil; polled exactly once just before each unit; True stops the run there.</param>
/// <param name="AInheritedSupported">See TConvertJob.InheritedSupported.</param>
/// <param name="ARetypeSupported">See TConvertJob.RetypeSupported.</param>
/// <returns>One row per unit x book attempted (a missing, not-reindexed or
/// un-backed-up unit: one csUnitSkipped row); a unit whose books were all found
/// invalid on earlier units gets no row, no reindex and no backup.</returns>
/// <remarks>Before a unit's first book the index is refreshed (a .dfm edited
/// since the last index would otherwise be patched at stale line ranges); a
/// failed refresh skips the unit untouched and the run continues. Each unit
/// then gets ONE restore point, .BCK&lt;N&gt; for the .pas and the SAME N for
/// its .dfm (SharedBackupPaths), deleted again when no book changed the unit.
/// A failed or refused apply, or a failed reindex, restores the unit, rewrites its earlier
/// csConverted rows to csRolledBack and stops its remaining books -- except a refusal
/// on a unit nothing has changed yet, which restores nothing and drops the backup. An
/// apply returning ENGINE_EXIT_CONFIG gives a csConfigError row and stops the RUN (no
/// later book or unit). This test seam reads the apply/1 output with every 1.27.0
/// feature (ParseApplyJson's default); the TConvertJob overload uses
/// TConvertJob.ApplyFeatures. Never raises: file I/O failures and exceptions from
/// AApply / AIndex become row outcomes (see TConvertStatus).</remarks>
function RunConversionUnits(const AUnits, ABooks: TArray<string>; const AApply: TApplyFn; const AIndex: TIndexFn; const AProgress: TConvertProgress; const ACancelled: TFunc<Boolean>; AInheritedSupported: Boolean = False; ARetypeSupported: Boolean = False): TArray<TConvertRow>; overload;

/// <summary>The TApplyFn overload with a step callback (C16): the test seam of the
/// progress sequence; RunConversion uses the same loop.</summary>
/// <param name="AUnits">Source units.</param>
/// <param name="ABooks">Validated books, application order.</param>
/// <param name="AApply">Applies one book to one unit.</param>
/// <param name="AIndex">As in the TApplyFn overload.</param>
/// <param name="AProgress">May be nil.</param>
/// <param name="ACancelled">May be nil; polled exactly once just before each unit; True stops the run there.</param>
/// <param name="AOnStep">May be nil; receives every TRunStep (C16), in run order and
/// before the step's work: per unit rpReindexBefore, rpBackup, then per book rpApply,
/// rpReindexAfter after a successful apply, and rpRestore when the unit is copied back.
/// A unit's rows reach AProgress before the next unit's first step. No step for a unit
/// a cancel kept from running, for a missing unit beyond its check, or for an
/// out-of-scope book (no engine call).</param>
/// <param name="AInheritedSupported">See TConvertJob.InheritedSupported.</param>
/// <param name="ARetypeSupported">See TConvertJob.RetypeSupported.</param>
/// <returns>As the TApplyFn overload of RunConversionUnits.</returns>
/// <remarks>A separate name, not one more default parameter: a defaulted anonymous-method
/// parameter on these overloads made dcc64 reject existing calls (E2250).</remarks>
function RunConversionUnitsStepped(const AUnits, ABooks: TArray<string>; const AApply: TApplyFn; const AIndex: TIndexFn; const AProgress: TConvertProgress; const ACancelled: TFunc<Boolean>; const AOnStep: TRunStepFn; AInheritedSupported: Boolean = False; ARetypeSupported: Boolean = False): TArray<TConvertRow>;

/// <summary>The unit loop with the engine calls AND the scope injected (C12, spec
/// E9-E11); the TApplyFn overload is this one with a whole-unit scope.</summary>
/// <param name="AUnits">Source units.</param>
/// <param name="ABooks">Validated books, application order.</param>
/// <param name="AApply">Applies one book to one unit, with the --only names.</param>
/// <param name="AIndex">As in the TApplyFn overload.</param>
/// <param name="AScope">Asked once per unit x book, before the engine call.</param>
/// <param name="AProgress">May be nil.</param>
/// <param name="ACancelled">May be nil; polled exactly once just before each unit; True stops the run there.</param>
/// <param name="AInheritedSupported">See TConvertJob.InheritedSupported.</param>
/// <param name="ARetypeSupported">See TConvertJob.RetypeSupported.</param>
/// <param name="AOnlyHint">The unmatched-name note tail; nil = UnmatchedOnlyHint (the
/// TConvertJob overload binds UnmatchedOnlyHintFor to the job's scope).</param>
/// <returns>As the TApplyFn overload, plus csOutOfScope rows.</returns>
/// <remarks>Everything the TApplyFn overload says holds. In addition: a book AScope
/// scopes to NO name gets a csOutOfScope row with no engine call and no backup named,
/// and the unit's next book still runs (a unit whose every book is out of scope keeps
/// no backup). A scoped converted row's note is ScopedConvertedNote; a scoped refusal's
/// note gets RefusalHint appended; a scoped apply that fails with no refusal and no edit
/// (an --only name that matched nothing) stays a failure (restored) and its note gets
/// AOnlyHint's tail. AScope raising counts as out of scope.</remarks>
function RunConversionUnits(const AUnits, ABooks: TArray<string>; const AApply: TApplyOnlyFn; const AIndex: TIndexFn; const AScope: TScopeFn; const AProgress: TConvertProgress; const ACancelled: TFunc<Boolean>; AInheritedSupported: Boolean = False; ARetypeSupported: Boolean = False; const AOnlyHint: TOnlyHintFn = nil): TArray<TConvertRow>; overload;

/// <summary>PURE: the progress line for one step (status bar and the Convert tab).</summary>
/// <param name="AStep">The step.</param>
/// <returns>'Unit 2 of 5: SystemData2 -- book 1 of 2 BDE-to-FireDAC: applying (0:42,
/// total 3:10)' for a book-level phase; 'Unit 2 of 5: SystemData2: backing up (0:03, total
/// 3:10)' for a unit-level one; 'Final reindex (total 3:10)' for rpFinalReindex. Unit and
/// book are file names without extension. Phase words: reindexing before apply, backing
/// up, applying, reindexing after apply, restoring from backup.</returns>
function RunStepText(const AStep: TRunStep): string;

/// <summary>PURE: AStep with AMs added to both elapsed fields -- the tab's once-a-second
/// refresh while one phase runs.</summary>
/// <param name="AStep">The step as the runner emitted it.</param>
/// <param name="AMs">Milliseconds since it was received.</param>
/// <returns>The advanced copy.</returns>
function AdvanceStep(const AStep: TRunStep; AMs: Int64): TRunStep;

/// <summary>Display text for a status.</summary>
/// <param name="AStatus">The status.</param>
/// <returns>'converted', 'FAILED -- restored', 'book skipped', 'unit skipped',
/// 'rolled back', 'FAILED -- NOT restored', 'refused -- not changed',
/// 'skipped -- not in scope', 'stopped -- cast library unusable'.</returns>
function ConvertStatusText(AStatus: TConvertStatus): string;

type
  /// <summary>A finished run's rows counted by status (the Convert tab's summary).</summary>
  TRunTally = record
    /// <summary>csConverted rows.</summary>
    Converted  : Integer;
    /// <summary>csFailedRestored rows.</summary>
    Restored   : Integer;
    /// <summary>csRolledBack rows.</summary>
    RolledBack : Integer;
    /// <summary>csBookSkipped rows.</summary>
    BookSkips  : Integer;
    /// <summary>csUnitSkipped rows.</summary>
    UnitSkips  : Integer;
    /// <summary>csRefused rows.</summary>
    Refused    : Integer;
    /// <summary>csOutOfScope rows: unit x book pairs a scoped run never applied.</summary>
    OutOfScope : Integer;
    /// <summary>File names of the csRestoreFailed rows' units, row order.</summary>
    NotRestored: TArray<string>;
    /// <summary>csConfigError rows (0 or 1: the first one stops the run).</summary>
    ConfigErrors: Integer;
  end;

/// <summary>PURE: counts ARows by status.</summary>
/// <param name="ARows">A run's rows.</param>
/// <returns>The tally; every row lands in exactly one count (or NotRestored).</returns>
function TallyRows(const ARows: TArray<TConvertRow>): TRunTally;

/// <summary>PURE: the summary's lead sentence (C12 Task 3 carry): out-of-scope pairs
/// are counted on their own and are NOT part of the "of M" denominator.</summary>
/// <param name="ATally">TallyRows of the run.</param>
/// <param name="APairs">Books x units of the job.</param>
/// <returns>'Converted N of M unit x book pair(s); R failed and were restored.' with
/// M = APairs - OutOfScope, plus ' K pair(s) skipped -- not in scope.' when K &gt; 0.</returns>
function ConvertedSummaryText(const ATally: TRunTally; APairs: Integer): string;

/// <summary>PURE: the units ARows converted (C8 R4: an ancestor converted EARLIER IN THE
/// SAME RUN converts its descendants' code uses too, so the editor-side code-use note
/// omits it; the engine's inherited[] is never filtered by this).</summary>
/// <param name="ARows">A run's rows so far.</param>
/// <returns>Unit names (file name without extension) of the csConverted rows, first-seen
/// order, once each.</returns>
/// <remarks>A unit whose conversion a later book on it rolled back is csRolledBack, not
/// csConverted, so it is not listed.</remarks>
function UnitsConvertedIn(const ARows: TArray<TConvertRow>): TArray<string>;

/// <summary>PURE: True when ARow should carry the editor-side code-use "left" note:
/// it is csConverted and no EARLIER csConverted row is for the same unit (one note per
/// unit, not one per book), and the run's engine does NOT report inherited_retype.</summary>
/// <param name="ARow">The row about to be shown.</param>
/// <param name="AEarlier">The run's rows before it.</param>
/// <param name="ARetypeSupported">The run's engine reports inherited_retype (1.26.0 on):
/// its inherited[] then lists code-only uses itself (action 'code', authoritative,
/// ruling C8 M4), so the editor-side note would say the same thing twice.</param>
/// <returns>See summary; units compared by path, case-insensitively.</returns>
function CodeUseNoteDue(const ARow: TConvertRow; const AEarlier: TArray<TConvertRow>; ARetypeSupported: Boolean): Boolean;

/// <summary>PURE: the run report's E10 lines for one row: one per inherited instance
/// the engine says the converted unit left, UNFILTERED (controller ruling M4: the
/// engine reports after the runner's reindex and is authoritative; R4 is the code-use
/// note's alone). Same 8 tab-separated columns as every report row: Book, Unit,
/// REPORT_STATUS_INHERITED_LEFT, four empty cells, InheritedReportNote. An instance the
/// engine RETYPED (IsRetypedInstance) was not left and gets no line.</summary>
/// <param name="ARow">A run row.</param>
/// <param name="AInheritedSupported">The engine reported inherited_instances when the
/// run started; False = no lines (an older engine's output is not this contract).</param>
/// <param name="ARetypeSupported">The engine reported inherited_retype when the run
/// started (passed to InheritedReportNote).</param>
/// <returns>[] unless ARow is csConverted and AInheritedSupported.</returns>
function InheritedReportLines(const ARow: TConvertRow; AInheritedSupported, ARetypeSupported: Boolean): TArray<string>;

/// <summary>PURE: the run report's glyph lines for one row (spec E13, amended to the
/// report's one shape): one per engine glyphs[] outcome, in the same 8 tab-separated
/// columns as every report row -- Book, Unit, REPORT_STATUS_GLYPH, four empty cells,
/// GlyphReportNote.</summary>
/// <param name="ARow">A run row.</param>
/// <returns>[] unless ARow is csConverted: a rolled-back row's to-do markers were
/// restored away (the same rule as GlyphTodoUnitCount).</returns>
function GlyphReportLines(const ARow: TConvertRow): TArray<string>;

/// <summary>PURE: the run report's engine 1.27.0 lines for one row, in the same 8
/// tab-separated columns as every report row -- Book, Unit, Status, four empty cells,
/// Note: one per CastSites entry (REPORT_STATUS_CAST_SITE), ValueCasts entry
/// (REPORT_STATUS_VALUE_CAST) and ValueChecks entry (REPORT_STATUS_VALUE_CHECK), Note
/// ApplyItemReportNote; then one per UsesRows row (REPORT_STATUS_USES + its action, Note
/// UsesReportNote) and one per UsesUnresolved entry ('uses unresolved', Note the
/// entry).</summary>
/// <param name="ARow">A run row.</param>
/// <returns>[] unless ARow is csConverted (a rolled-back row's changes were restored
/// away, as for GlyphReportLines).</returns>
function ApplyItemReportLines(const ARow: TConvertRow): TArray<string>;

/// <summary>PURE: the run-level error of a run a cast library stopped (exit
/// ENGINE_EXIT_CONFIG).</summary>
/// <param name="ARows">The run's rows.</param>
/// <param name="ACastLib">The cast library the run passed ('' = none).</param>
/// <returns>'' when no row has StoppedRun; else 'Convert stopped: the cast library
/// &lt;path&gt; is unusable -- &lt;engine text&gt;', the text being that row's Apply.Error (also
/// when its restore failed and it is csRestoreFailed) and the path '(none)' when ACastLib
/// is ''.</returns>
function CastLibStopText(const ARows: TArray<TConvertRow>; const ACastLib: string): string;

/// <summary>PURE: the units a configuration stop kept from running.</summary>
/// <param name="ARows">The run's rows.</param>
/// <param name="AUnits">The job's units, run order.</param>
/// <returns>The units after the StoppedRun row's unit, in AUnits order; [] when no row has
/// StoppedRun (or its unit is not in AUnits).</returns>
function NotReachedAfterStop(const ARows: TArray<TConvertRow>; const AUnits: TArray<string>): TArray<string>;

/// <summary>How many UNITS a run left with glyph to-do outcomes (spec E14).</summary>
/// <param name="ARows">The run's rows.</param>
/// <returns>The number of distinct UnitPas (compared case-insensitively) with at least
/// one csConverted row whose Apply.Glyphs holds a to-do (GlyphTodoCount &gt; 0). A unit
/// two books converted counts once; a csRolledBack row counts nowhere -- its change,
/// and the to-do marker it wrote, were restored away.</returns>
function GlyphTodoUnitCount(const ARows: TArray<TConvertRow>): Integer;

/// <summary>The run summary's leading sentences, most severe first.</summary>
/// <param name="ANotRestored">Units whose restore failed (may be half-converted); [] = none.</param>
/// <param name="AGlyphSummary">GlyphRunSummary of the run; '' = no glyph to-dos.</param>
/// <param name="ABody">The ordinary summary (counts, problems, report path).</param>
/// <returns>'RESTORE FAILED for &lt;units&gt; -- may be half-converted; restore by hand from the
/// backups its row names. ' when ANotRestored is not empty, then AGlyphSummary + two spaces
/// when it is set, then ABody. A half-converted unit always leads; the glyph to-dos come
/// next.</returns>
function RunStatusLead(const ANotRestored: TArray<string>; const AGlyphSummary, ABody: string): string;

/// <summary>PURE: a finished run's Work list (engine 1.27.0 pas_uses[]).</summary>
/// <param name="ARows">The run's rows.</param>
/// <param name="ARunId">The run's id (TConvertJob.RunId).</param>
/// <param name="APasUses">The run's engine reports pas_uses (afPasUses in the job's
/// ApplyFeatures).</param>
/// <returns>State wlsNoCapability without APasUses; else wlsNoConverted when no row is
/// csConverted; else wlsRows with the Apply.PasUses of every csConverted row, each
/// stamped with ARunId and that row's full UnitPas. A row repeated exactly (two books on
/// one unit reporting the same global) is kept once. A csRolledBack row counts nowhere:
/// its change was restored away.</returns>
function WorkRunOf(const ARows: TArray<TConvertRow>; ARunId: Integer; APasUses: Boolean): TWorkRun;

implementation

uses
  System.IOUtils
  , System.StrUtils
  , System.Diagnostics
  , ConvRules.Glyph
  , ConvRules.UnitStatus  // dl:ok unused-unit-in-uses@ec0d -- REVIEWED 2026-09-29 false positive: TFileProbe (FileProbe's return type) is declared here; removing the unit fails with E2003
  ;

const
  OUTPUT_HEAD_CHARS = 200;
  NOTE_OUT_OF_SCOPE = 'no in-scope instance of this book''s From types on the unit';

function ConvertStatusText(AStatus: TConvertStatus): string;
begin
  case AStatus of
    csConverted     : Result:= 'converted';
    csFailedRestored: Result:= 'FAILED -- restored';
    csBookSkipped   : Result:= 'book skipped';
    csUnitSkipped   : Result:= 'unit skipped';
    csRolledBack    : Result:= 'rolled back';
    csRestoreFailed : Result:= 'FAILED -- NOT restored';
    csRefused       : Result:= 'refused -- not changed';
    csOutOfScope    : Result:= 'skipped -- not in scope';
    csConfigError   : Result:= 'stopped -- cast library unusable';
    else              Result:= 'FAILED -- NOT restored';
  end;
end;

function TallyRows(const ARows: TArray<TConvertRow>): TRunTally;
begin
  Result:= Default(TRunTally);
  for var LRow: TConvertRow in ARows do
    case LRow.Status of
      csConverted     : Inc(Result.Converted);
      csFailedRestored: Inc(Result.Restored);
      csRolledBack    : Inc(Result.RolledBack);
      csBookSkipped   : Inc(Result.BookSkips);
      csUnitSkipped   : Inc(Result.UnitSkips);
      csRestoreFailed : Result.NotRestored:= Result.NotRestored + [ExtractFileName(LRow.UnitPas)];
      csRefused       : Inc(Result.Refused);
      csOutOfScope    : Inc(Result.OutOfScope);
      csConfigError   : Inc(Result.ConfigErrors);
    end; // case
end;

function ConvertedSummaryText(const ATally: TRunTally; APairs: Integer): string;
begin
  Result:= Format('Converted %d of %d unit x book pair(s); %d failed and were restored.', [ATally.Converted, APairs - ATally.OutOfScope, ATally.Restored]);
  if ATally.OutOfScope > 0 then
    Result:= Result + Format(' %d pair(s) skipped -- not in scope.', [ATally.OutOfScope]);
end;

function UnitsConvertedIn(const ARows: TArray<TConvertRow>): TArray<string>;
var
  LName: string;
begin
  Result:= nil;
  for var LRow: TConvertRow in ARows do
    if LRow.Status = csConverted then
    begin
      LName:= ChangeFileExt(ExtractFileName(LRow.UnitPas), '');
      if not MatchText(LName, Result) then
        Result:= Result + [LName];
    end;
end;

function CodeUseNoteDue(const ARow: TConvertRow; const AEarlier: TArray<TConvertRow>; ARetypeSupported: Boolean): Boolean;
begin
  Result:= (ARow.Status = csConverted) and not ARetypeSupported;
  for var LRow: TConvertRow in AEarlier do
    if Result and (LRow.Status = csConverted) and SameText(LRow.UnitPas, ARow.UnitPas) then
      Result:= False;
end;

function InheritedReportLines(const ARow: TConvertRow; AInheritedSupported, ARetypeSupported: Boolean): TArray<string>;
begin
  Result:= nil;
  if not AInheritedSupported or (ARow.Status <> csConverted) then
    Exit;
  for var LLeft: TInheritedLeft in ARow.Apply.InheritedLeft do
    if not IsRetypedInstance(LLeft) then
      Result:= Result + [string.Join(#9, [ARow.Book, ARow.UnitPas, REPORT_STATUS_INHERITED_LEFT, '', '', '', '', InheritedReportNote(LLeft, ARetypeSupported)])];
end;

function GlyphReportLines(const ARow: TConvertRow): TArray<string>;
begin
  Result:= nil;
  if ARow.Status <> csConverted then
    Exit;
  for var LG: TGlyphOutcome in ARow.Apply.Glyphs do
    Result:= Result + [string.Join(#9, [ARow.Book, ARow.UnitPas, REPORT_STATUS_GLYPH, '', '', '', '', GlyphReportNote(LG)])];
end;

function ApplyItemReportLines(const ARow: TConvertRow): TArray<string>;

  function Line(const AStatus, ANote: string): string;
  begin
    Result:= string.Join(#9, [ARow.Book, ARow.UnitPas, AStatus, '', '', '', '', ANote]);
  end;

begin
  Result:= nil;
  if ARow.Status <> csConverted then
    Exit;
  for var LItem: TApplyItem in ARow.Apply.CastSites do
    Result:= Result + [Line(REPORT_STATUS_CAST_SITE, ApplyItemReportNote(LItem))];
  for var LItem: TApplyItem in ARow.Apply.ValueCasts do
    Result:= Result + [Line(REPORT_STATUS_VALUE_CAST, ApplyItemReportNote(LItem))];
  for var LItem: TApplyItem in ARow.Apply.ValueChecks do
    Result:= Result + [Line(REPORT_STATUS_VALUE_CHECK, ApplyItemReportNote(LItem))];
  for var LUses: TUsesRow in ARow.Apply.UsesRows do
    Result:= Result + [Line(REPORT_STATUS_USES + LUses.Action, UsesReportNote(LUses))];
  for var LText: string in ARow.Apply.UsesUnresolved do
    Result:= Result + [Line(REPORT_STATUS_USES + 'unresolved', LText)];
end;

// The index of the row that stopped the run (StoppedRun); -1 when there is none.
function ConfigErrorAt(const ARows: TArray<TConvertRow>): Integer;
begin
  for var I: Integer:= 0 to High(ARows) do
    if ARows[I].StoppedRun then
      Exit(I);
  Result:= -1;
end;

function CastLibStopText(const ARows: TArray<TConvertRow>; const ACastLib: string): string;
var
  LAt: Integer;
begin
  LAt:= ConfigErrorAt(ARows);
  if LAt < 0 then
    Exit('');
  Result:= Format('Convert stopped: the cast library %s is unusable -- %s', [if ACastLib = '' then '(none)' else ACastLib, ARows[LAt].Apply.Error]);
end;

function NotReachedAfterStop(const ARows: TArray<TConvertRow>; const AUnits: TArray<string>): TArray<string>;
var
  LAt: Integer;
begin
  Result:= nil;
  LAt:= ConfigErrorAt(ARows);
  if LAt < 0 then
    Exit;
  for var I: Integer:= 0 to High(AUnits) do
    if SameText(AUnits[I], ARows[LAt].UnitPas) then
      Exit(Copy(AUnits, I + 1, Length(AUnits) - I - 1));
end;

function GlyphTodoUnitCount(const ARows: TArray<TConvertRow>): Integer;
var
  LUnits: TArray<string>;
begin
  LUnits:= nil;
  for var LRow: TConvertRow in ARows do
    if (LRow.Status = csConverted) and (GlyphTodoCount(LRow.Apply.Glyphs) > 0) and not MatchText(LRow.UnitPas, LUnits) then
      LUnits:= LUnits + [LRow.UnitPas];
  Result:= Length(LUnits);
end;

function RunStatusLead(const ANotRestored: TArray<string>; const AGlyphSummary, ABody: string): string;
begin
  Result:= ABody;
  if AGlyphSummary <> '' then
    Result:= AGlyphSummary + '  ' + Result;
  if Length(ANotRestored) > 0 then
    Result:= Format('RESTORE FAILED for %s -- may be half-converted; restore by hand from the backups its row names. ', [string.Join(', ', ANotRestored)]) + Result;
end;

function RunStepText(const AStep: TRunStep): string;
const
  PHASE_WORDS: array[TRunPhase] of string = ('reindexing before apply', 'backing up', 'applying',
    'reindexing after apply', 'restoring from backup', 'final reindex');
begin
  if AStep.Phase = rpFinalReindex then
    Exit(Format('Final reindex (total %s)', [FormatElapsed(AStep.TotalElapsedMs)]));
  Result:= Format('Unit %d of %d: %s', [AStep.UnitNo, AStep.UnitCount, ChangeFileExt(ExtractFileName(AStep.UnitPas), '')]);
  if AStep.BookNo > 0 then
    Result:= Result + Format(' -- book %d of %d %s', [AStep.BookNo, AStep.BookCount, ChangeFileExt(ExtractFileName(AStep.Book), '')]);
  Result:= Result + Format(': %s (%s, total %s)', [PHASE_WORDS[AStep.Phase], FormatElapsed(AStep.UnitElapsedMs), FormatElapsed(AStep.TotalElapsedMs)]);
end;

function AdvanceStep(const AStep: TRunStep; AMs: Int64): TRunStep;
begin
  Result:= AStep;
  Inc(Result.UnitElapsedMs, AMs);
  Inc(Result.TotalElapsedMs, AMs);
end;

function FileProbe: TFileProbe;
begin
  Result:= function(const APath: string): Boolean
    begin
      Result:= TFile.Exists(APath);
    end;
end;

// The ONE unit loop (the public TApplyOnlyFn overload is it without a step callback).
function RunUnitLoop(const AUnits, ABooks: TArray<string>; const AApply: TApplyOnlyFn; const AIndex: TIndexFn; const AScope: TScopeFn; const AProgress: TConvertProgress; const ACancelled: TFunc<Boolean>; AInheritedSupported, ARetypeSupported: Boolean; const AOnlyHint: TOnlyHintFn; const AOnStep: TRunStepFn; AFeatures: TApplyFeatures): TArray<TConvertRow>; forward;

// The TConvertJob overload's body, with the step callback.
function RunJobUnits(const AUnits, ABooks: TArray<string>; const AJob: TConvertJob; AEngine: TEngineAdapter; const AProgress: TConvertProgress; const ACancelled: TFunc<Boolean>; const AOnStep: TRunStepFn): TArray<TConvertRow>; forward;

function RunConversion(const AJob: TConvertJob; AEngine: TEngineAdapter; const AProgress: TConvertProgress; const ACancelled: TFunc<Boolean>; const AOnStep: TRunStepFn): TArray<TConvertRow>;
begin
  Result:= RunJobUnits(AJob.Units, AJob.Books, AJob, AEngine, AProgress, ACancelled, AOnStep);
end;

function RunConversionUnits(const AUnits, ABooks: TArray<string>; const AJob: TConvertJob; AEngine: TEngineAdapter; const AProgress: TConvertProgress; const ACancelled: TFunc<Boolean>): TArray<TConvertRow>;
begin
  Result:= RunJobUnits(AUnits, ABooks, AJob, AEngine, AProgress, ACancelled, nil);
end;

function RunJobUnits(const AUnits, ABooks: TArray<string>; const AJob: TConvertJob; AEngine: TEngineAdapter; const AProgress: TConvertProgress; const ACancelled: TFunc<Boolean>; const AOnStep: TRunStepFn): TArray<TConvertRow>;
var
  LJob   : TConvertJob;
  LEngine: TEngineAdapter;
  LScope : TScopeFn;
begin
  LJob   := AJob;
  LEngine:= AEngine;
  // The book is read on the worker thread; an unreadable one is out of scope.
  LScope:= function(const AUnitPas, ABook: string; out ANames: TArray<string>): Boolean
    begin
      Result:= ScopedNamesForBookFile(LJob.Scope, AUnitPas, ABook, ANames);
    end;
  Result:= RunUnitLoop(AUnits, ABooks,
    function(const AUnitPas, ARulesFile: string; const AOnly: TArray<string>; out AJson: string): Integer
    begin
      Result:= LEngine.ApplyConversion(AUnitPas, ARulesFile, LJob.Dbs, AOnly, AJson);
    end,
    function(out AOutput: string): Integer
    begin
      Result:= LEngine.IndexProject(LJob.ProjectFile, LJob.ProjectDb, AOutput);
    end,
    LScope, AProgress, ACancelled, LJob.InheritedSupported, LJob.RetypeSupported,
    // No "re-send it" when every --only name is inherited/inline (fix wave Minor 2).
    function(const AOnly: TArray<string>): string
    begin
      Result:= UnmatchedOnlyHintFor(LJob.Scope, AOnly);
    end, AOnStep, LJob.ApplyFeatures);
end;

function RunConversionUnits(const AUnits, ABooks: TArray<string>; const AApply: TApplyFn; const AIndex: TIndexFn; const AProgress: TConvertProgress; const ACancelled: TFunc<Boolean>; AInheritedSupported, ARetypeSupported: Boolean): TArray<TConvertRow>;  // dl:ok too-many-parameters@8e04 -- REVIEWED 2026-10-06 the test-injection twin of the TConvertJob overload: two engine seams plus the job's two capability flags (InheritedSupported, RetypeSupported); a record for the two flags would be one more type used only here
begin
  Result:= RunConversionUnitsStepped(AUnits, ABooks, AApply, AIndex, AProgress, ACancelled, nil, AInheritedSupported, ARetypeSupported);
end;

function RunConversionUnitsStepped(const AUnits, ABooks: TArray<string>; const AApply: TApplyFn; const AIndex: TIndexFn; const AProgress: TConvertProgress; const ACancelled: TFunc<Boolean>; const AOnStep: TRunStepFn; AInheritedSupported, ARetypeSupported: Boolean): TArray<TConvertRow>;  // dl:ok too-many-parameters@4138 -- REVIEWED 2026-10-10 the TApplyFn test seam plus the C16 step callback: the same seams as its twin, one more
var
  LApply: TApplyFn;
begin
  LApply:= AApply;
  Result:= RunUnitLoop(AUnits, ABooks,
    function(const AUnitPas, ARulesFile: string; const AOnly: TArray<string>; out AJson: string): Integer
    begin
      Result:= LApply(AUnitPas, ARulesFile, AJson);
    end,
    AIndex,
    function(const AUnitPas, ABook: string; out ANames: TArray<string>): Boolean
    begin
      ANames:= nil;
      Result:= False;
    end,
    AProgress, ACancelled, AInheritedSupported, ARetypeSupported, nil, AOnStep, [Low(TApplyFeature)..High(TApplyFeature)]);
end;

function RunConversionUnits(const AUnits, ABooks: TArray<string>; const AApply: TApplyOnlyFn; const AIndex: TIndexFn; const AScope: TScopeFn; const AProgress: TConvertProgress; const ACancelled: TFunc<Boolean>; AInheritedSupported, ARetypeSupported: Boolean; const AOnlyHint: TOnlyHintFn): TArray<TConvertRow>;  // dl:ok too-many-parameters@092f -- REVIEWED 2026-10-10 the public scope-seam entry point, unchanged since C12 (its 2026-10-06 review moved with the body to RunUnitLoop)
begin
  Result:= RunUnitLoop(AUnits, ABooks, AApply, AIndex, AScope, AProgress, ACancelled, AInheritedSupported, ARetypeSupported, AOnlyHint, nil, [Low(TApplyFeature)..High(TApplyFeature)]);
end;

function RunUnitLoop(const AUnits, ABooks: TArray<string>; const AApply: TApplyOnlyFn; const AIndex: TIndexFn; const AScope: TScopeFn; const AProgress: TConvertProgress; const ACancelled: TFunc<Boolean>; AInheritedSupported, ARetypeSupported: Boolean; const AOnlyHint: TOnlyHintFn; const AOnStep: TRunStepFn; AFeatures: TApplyFeatures): TArray<TConvertRow>;  // dl:ok too-many-parameters@5a9d -- REVIEWED 2026-10-11 (C16: + the step callback; editor-1270: + the apply/1 feature set) the ONE unit loop: four engine/scope seams (apply, index, scope, unmatched-name hint), progress, cancel and the job's capability flags and feature set; the TConvertJob overload is the record-shaped entry point
var
  Rows    : TArray<TConvertRow>;
  UnitRows: TArray<TConvertRow>; // the current unit's rows, emitted when it finishes
  Row     : TConvertRow;
  Total   : Integer;
  CurUnit : string;
  BakPas  : string;
  BakDfm  : string;
  Dfm     : string;
  Invalid : TArray<string>; // books whose rules failed the engine's validation this run
  Changed : Boolean;        // the unit's backup is still needed (a change, or a failed book)
  Watch   : TStopwatch;     // since the run started (C16 step elapsed)
  UnitNo  : Integer;        // 1-based position of CurUnit in AUnits
  UnitAt  : Int64;          // Watch's milliseconds when CurUnit started
  BookNo  : Integer;        // 1-based position in ABooks of the book running now; 0 = none
  StepsOff: Boolean;        // AOnStep raised once: no further steps this run
  Stopped : Boolean;        // an apply exited ENGINE_EXIT_CONFIG: no further unit runs

  // C16: tells AOnStep that APhase starts now. Advisory: a raising callback never
  // stops the run (this routine never raises, see the declaration).
  procedure Step(APhase: TRunPhase);
  var
    LStep: TRunStep;
  begin
    if not Assigned(AOnStep) or StepsOff then
      Exit;
    LStep:= Default(TRunStep);
    LStep.Phase    := APhase;
    LStep.UnitNo   := UnitNo;
    LStep.UnitCount:= Length(AUnits);
    LStep.UnitPas  := CurUnit;
    LStep.BookCount:= Length(ABooks);
    if APhase in [rpApply, rpReindexAfter, rpRestore] then
    begin
      LStep.BookNo:= BookNo;
      LStep.Book  := ABooks[BookNo - 1];
    end;
    LStep.TotalElapsedMs:= Watch.ElapsedMilliseconds;
    LStep.UnitElapsedMs := LStep.TotalElapsedMs - UnitAt;
    try
      AOnStep(LStep);
    except  // dl:ok try-except-swallowed@76ff -- REVIEWED 2026-10-10 progress is advisory: a display callback that raises must not turn into a unit failure or escape a routine documented as never raising; it is not asked again
      on Exception do
        StepsOff:= True;
    end; // try
  end;

  procedure Add;
  begin
    UnitRows:= UnitRows + [Row];
  end;

  procedure Flush;
  begin
    for var LRow: TConvertRow in UnitRows do
    begin
      Rows:= Rows + [LRow];
      if Assigned(AProgress) then
        AProgress(LRow, Length(Rows), Total);
    end;
    UnitRows:= nil;
  end;

  function AllInvalid: Boolean;
  begin
    Result:= True;
    for var LBook: string in ABooks do
      if not MatchText(LBook, Invalid) then
        Exit(False);
  end;

  // '' when ABak ('' = none made) is gone; else a note that it was kept.
  function DropBackup(const ABak: string): string;
  begin
    Result:= '';
    if ABak = '' then
      Exit;
    try
      TFile.Delete(ABak);
    except
      on E: Exception do
        Result:= Format('; unneeded backup kept (delete failed: %s): %s', [E.Message, ABak]);
    end; // try
  end;

  // '' when every backup this run made for the unit is gone; else what was kept.
  function DropBackups: string;
  begin
    Result:= DropBackup(BakPas) + DropBackup(BakDfm);
  end;

  // The unit's backups for a Note: both when it has a .dfm; file names only
  // unless AFullPaths.
  function BackupNames(AFullPaths: Boolean): string;
  begin
    Result:= if AFullPaths then BakPas else ExtractFileName(BakPas);
    if BakDfm <> '' then
      Result:= Result + ' and ' + (if AFullPaths then BakDfm else ExtractFileName(BakDfm));
  end;

  // BakPas / BakDfm are set only once their copy has been made, so a failure
  // leaves them naming exactly the backups DropBackups must remove.
  function TakeBackups(out AError: string): Boolean;
  begin
    AError:= '';
    BakPas:= '';
    BakDfm:= '';
    Dfm   := ChangeFileExt(CurUnit, '.dfm');
    try
      // ONE number for the unit: a stale X.dfm.BCK<N> counts even when the .dfm is gone.
      var LPaths: TArray<string>:= SharedBackupPaths([CurUnit, Dfm], FileProbe());
      TFile.Copy(CurUnit, LPaths[0]);
      BakPas:= LPaths[0];
      if TFile.Exists(Dfm) then
      begin
        TFile.Copy(Dfm, LPaths[1]);
        BakDfm:= LPaths[1];
      end;
      Result:= True;
    except
      on E: Exception do
      begin
        AError:= E.Message;
        Result:= False;
      end;
    end; // try
  end;

  function TryRestore(out AError: string): Boolean;
  begin
    AError:= '';
    try
      TFile.Copy(BakPas, CurUnit, True);
      if BakDfm <> '' then
        TFile.Copy(BakDfm, Dfm, True);
      Result:= True;
    except
      on E: Exception do
      begin
        AError:= E.Message;
        Result:= False;
      end;
    end; // try
  end;

  // Row is the failing book's row; restore the unit and account for its earlier rows.
  // AStatus is the failing row's status: csFailedRestored, csRefused or csConfigError.
  procedure FailUnit(const AReason: string; AStatus: TConvertStatus);
  var
    LError: string;
    LVerb : string;
  begin
    // The run stop is recorded on the row whatever the restore below does: a failed
    // restore makes the row csRestoreFailed, and the stop must not be lost with it.
    Row.StoppedRun:= AStatus = csConfigError;
    // A refusal leaves the file untouched (engine contract), and so does a castlib
    // configuration error (the engine stops before it plans an edit). When no earlier
    // book changed the unit either, there is nothing to restore and the backup is not
    // needed: RunUnit drops it, as for a skipped book (owner decision, 2026-10-04).
    if (AStatus in [csRefused, csConfigError]) and not Changed then
    begin
      Row.Backup   := '';
      Row.BackupDfm:= '';
      Row.Status   := AStatus;
      Row.Note     := AReason;
      Add;
      Exit;
    end;
    Changed:= True; // the backup is the restore point the rows name -- keep it
    Step(rpRestore);
    if not TryRestore(LError) then
    begin
      // Earlier csConverted rows stay: their change may still be on disk.
      Row.Status:= csRestoreFailed;
      Row.Note  := Format('restore failed: %s; the unit may be half-converted -- backup at %s', [LError, BackupNames(True)]);
      Add;
      Exit;
    end;
    case AStatus of
      csRefused    : LVerb:= 'was refused';
      csConfigError: LVerb:= 'stopped the run (cast library unusable)';
      else           LVerb:= 'failed';
    end; // case
    for var I: Integer:= 0 to High(UnitRows) do
      if UnitRows[I].Status = csConverted then
      begin
        UnitRows[I].Status:= csRolledBack;
        UnitRows[I].Note  := Format('undone: %s %s on this unit; restored from %s', [ExtractFileName(Row.Book), LVerb, BackupNames(False)]);
      end;
    Row.Status:= AStatus;
    Row.Note  := AReason;
    Add;
  end;

  // True = AIndex reported success; else AError is the head of its output.
  function TryReindex(out AError: string): Boolean;
  var
    LOutput: string;
    LCode  : Integer;
  begin
    try
      LCode:= AIndex(LOutput);
    except  // dl:ok try-except-swallowed@6298 -- REVIEWED 2026-09-29 not swallowed: becomes a failed reindex, so the unit is restored (or skipped) and the row carries the message
      on E: Exception do
      begin
        LOutput:= 'reindex raised: ' + E.Message;
        LCode  := -1;
      end;
    end; // try
    AError:= Copy(Trim(LOutput), 1, OUTPUT_HEAD_CHARS);
    Result:= LCode = 0;
  end;

  // True = the book is scoped on this unit (ANames may be []). A raising AScope
  // scopes it to no name: no apply, never a whole-unit one.
  function AskScope(const ABook: string; out ANames: TArray<string>): Boolean;
  begin
    try
      Result:= AScope(CurUnit, ABook, ANames);
    except // an out-of-scope row for the book (no engine call): the safe side of a failed decision
      on Exception do
      begin
        ANames:= nil;
        Result:= True;
      end;
    end; // try
    if not Result then
      ANames:= nil;
  end;

  // False = the unit failed; its remaining books must not run.
  function RunBook(const ABook: string): Boolean;
  var
    LJson  : string;
    LError : string;
    LOnly  : TArray<string>;
    LScoped: Boolean;
    LReason: string;
    LCode  : Integer;
  begin
    Result:= True;
    Row:= Default(TConvertRow);
    Row.UnitPas  := CurUnit;
    Row.Book     := ABook;
    Row.Backup   := BakPas;
    Row.BackupDfm:= BakDfm;
    LScoped:= AskScope(ABook, LOnly);
    if LScoped and (Length(LOnly) = 0) then
    begin
      Row.Backup   := ''; // the book made no change; the backups may yet be dropped
      Row.BackupDfm:= '';
      Row.Status   := csOutOfScope;
      Row.Note     := NOTE_OUT_OF_SCOPE;
      Add;
      Exit; // Result = True: the unit's next book still runs
    end;
    Step(rpApply);
    LCode:= -1;
    try
      // A non-zero exit shows up as ok=false or unparseable text in ParseApplyJson;
      // only ENGINE_EXIT_CONFIG is read from the code itself.
      LCode:= AApply(CurUnit, ABook, LOnly, LJson);
    except  // dl:ok try-except-swallowed@3c3c -- REVIEWED 2026-09-29 not swallowed: the message becomes unparseable apply output, so the unit is restored and the row names it
      on E: Exception do
        LJson:= 'engine call raised: ' + E.Message; // unparseable -> the unit is restored
    end; // try
    Row.Apply:= ParseApplyJson(LJson, AFeatures);
    // A refusal is about THIS unit, even when it also lists rule_errors: it takes the
    // refused path below and leaves the book valid for the next unit.
    // An edit-set refusal (engine 1.25.1+) is a unit failure, never a book error.
    // Engine 1.28.0 exit ENGINE_EXIT_CONFIG outranks both (see below).
    if (LCode <> ENGINE_EXIT_CONFIG) and (not Row.Apply.Ok) and (Row.Apply.RuleErrorCount > 0) and not Row.Apply.Refused and not ApplyEditSetRefused(Row.Apply) then
    begin
      // The BOOK is invalid; the engine validates before writing, so this unit
      // is untouched by it. Skip the book for the rest of the run.
      Invalid:= Invalid + [ABook];
      Row.Backup   := ''; // the book made no change; the backups may yet be dropped
      Row.BackupDfm:= '';
      Row.Status:= csBookSkipped;
      Row.Note  := 'rules failed the engine''s validation: ' + Row.Apply.Error;
      Add;
      Exit;
    end;
    if (LCode = ENGINE_EXIT_CONFIG) or not Row.Apply.Ok then
    begin
      if LCode = ENGINE_EXIT_CONFIG then
      begin
        // Engine 1.28.0: an unusable cast library is the RUN's configuration error,
        // never a unit or book error -- the next apply would fail the same way.
        Stopped:= True;
        FailUnit(Row.Apply.Error, csConfigError);
      end
      else
      begin
        // The E10 hint only on a scoped run: an unscoped run never asked for --only.
        LReason:= if ApplyEditSetRefused(Row.Apply) then EditSetRefusedNote(Row.Apply) else Row.Apply.Error;
        if LScoped and Row.Apply.Refused then
          LReason:= LReason + RefusalHint(LReason)
        else if LScoped and (Row.Apply.EditsCount = 0) and not ApplyEditSetRefused(Row.Apply) then
          LReason:= LReason + (if Assigned(AOnlyHint) then AOnlyHint(LOnly) else UnmatchedOnlyHint(LOnly)); // measured shape of an --only name that matches nothing
        // An edit-set refusal (1.25.1+) wrote nothing, like a refusal: FailUnit's
        // csRefused path restores only when an earlier book changed the unit.
        FailUnit(LReason, if Row.Apply.Refused or ApplyEditSetRefused(Row.Apply) then csRefused else csFailedRestored);
      end;
      Exit(False);
    end;
    // ok=true and exit 0, but the engine refused one file's edit set and wrote the
    // other: a half-converted unit is a failure, never a conversion (stop-gap until
    // the engine applies all-or-nothing; see ApplyHalfWritten).
    if ApplyHalfWritten(Row.Apply) then
    begin
      FailUnit(HalfWrittenNote(Row.Apply), csFailedRestored);
      Exit(False);
    end;
    Step(rpReindexAfter);
    if not TryReindex(LError) then
    begin
      FailUnit('reindex after apply failed: ' + LError, csFailedRestored);
      Exit(False);
    end;
    Changed   := True;
    Row.Status:= csConverted;
    // The engine's inherited[] is shown unfiltered (ruling M4): the unit was reindexed
    // before its first book, so the engine already knows which ancestors this run converted.
    Row.Note  := ConvertedRowNote(Row.Apply, AInheritedSupported, ARetypeSupported) + GlyphNoteSuffix(Row.Apply.Glyphs);
    if LScoped then
      Row.Note:= ScopedConvertedNote(LOnly, Row.Note);
    Add;
  end;

  procedure RunUnit;
  var
    LError: string;
  begin
    Row:= Default(TConvertRow);
    Row.UnitPas:= CurUnit;
    if not TFile.Exists(CurUnit) then
    begin
      Row.Status:= csUnitSkipped;
      Row.Note  := 'source unit not found on disk';
      Add;
      Exit;
    end;
    if AllInvalid then
      Exit; // every book already failed validation on an earlier unit: nothing to run, no backup
    // convert-apply patches the .dfm at the index's line ranges: a unit edited
    // (in the IDE, say) since the last index must be re-read first. A failed
    // refresh touches nothing -- no backup, no apply -- and the run goes on.
    UnitAt:= Watch.ElapsedMilliseconds;
    Step(rpReindexBefore);
    if not TryReindex(LError) then
    begin
      Row.Status:= csUnitSkipped;
      Row.Note  := 'reindex before apply failed: ' + LError;
      Add;
      Exit;
    end;
    // One restore point per unit per run, taken before the first book touches it.
    Step(rpBackup);
    if not TakeBackups(LError) then
    begin
      Row.Status:= csUnitSkipped;
      Row.Note  := 'backup failed: ' + LError + DropBackups;
      Add;
      Exit;
    end;
    Changed:= False;
    for var I: Integer:= 0 to High(ABooks) do
    begin
      BookNo:= I + 1;
      if not MatchText(ABooks[I], Invalid) and not RunBook(ABooks[I]) then
        Break;
    end;
    BookNo:= 0;
    if Changed then
      Exit;
    // Nothing touched the unit (every book invalid or out of scope, or refused before any change): the fresh copies are
    // identical to it and would only litter the folder.
    LError:= DropBackups;
    if (LError <> '') and (Length(UnitRows) > 0) then
      UnitRows[High(UnitRows)].Note:= UnitRows[High(UnitRows)].Note + LError;
  end;

begin
  Rows    := nil;
  UnitRows:= nil;
  Invalid := nil;
  if Length(ABooks) = 0 then
    Exit(nil); // no book, no backup
  Total:= Length(AUnits) * Length(ABooks);
  Watch := TStopwatch.StartNew;
  UnitNo:= 0;
  UnitAt:= 0;
  BookNo:= 0;
  StepsOff:= False;
  Stopped := False;
  for CurUnit in AUnits do
  begin
    Inc(UnitNo);
    // Cancel is honoured BETWEEN units only: a unit is never left with some of
    // its books applied and the rest not.
    if Assigned(ACancelled) and ACancelled() then
      Break;
    RunUnit;
    Flush;
    if Stopped then
      Break; // a castlib configuration error: every later apply would fail the same way
  end; // for units
  Result:= Rows;
end;

// WorkRunOf's identity of a row: the unit and every pas_uses field, so only an exact
// repeat is dropped (compared case-insensitively, as Pascal names are).
function PasUseKey(const ARow: TPasUseRow; const ALines: string): string;
begin
  Result:= string.Join(#9, [ARow.UnitPas, ARow.Instance, ARow.FromType, ARow.ToType, ARow.Member, ARow.Kind,
    ARow.Visibility, ARow.Status, ARow.DeclaringUnit, ARow.DeclaredIn, ALines]);
end;

function WorkRunOf(const ARows: TArray<TConvertRow>; ARunId: Integer; APasUses: Boolean): TWorkRun;
var
  LSeen : TArray<string>;
  LKey  : string;
  LLines: string;
  LUse  : TPasUseRow;
begin
  Result:= Default(TWorkRun);
  Result.RunId:= ARunId;
  if not APasUses then
  begin
    Result.State:= wlsNoCapability;
    Exit;
  end;
  Result.State:= wlsNoConverted;
  LSeen:= nil;
  for var LRow: TConvertRow in ARows do
  begin
    if LRow.Status <> csConverted then
      Continue;
    Result.State:= wlsRows;
    for var LParsed: TPasUseRow in LRow.Apply.PasUses do
    begin
      LUse:= LParsed;
      LUse.RunId  := ARunId;
      LUse.UnitPas:= LRow.UnitPas;
      LLines:= '';
      for var LLine: Integer in LUse.Lines do
        LLines:= LLines + IntToStr(LLine) + ',';
      LKey:= PasUseKey(LUse, LLines);
      if MatchText(LKey, LSeen) then
        Continue;
      LSeen:= LSeen + [LKey];
      Result.Rows:= Result.Rows + [LUse];
    end;
  end;
end;

end.
