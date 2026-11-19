unit DRagLint.Query.HappensBefore.Types;

{ drag-lint 1.52 -- lane HBSKEL: the check-init contract types.
  Scaffold created EMPTY by lane FRAME (listed in drag-lint.dpr / .dproj); lane HBSKEL owns it.

  Plan docs\superpowers\plans\2026-11-17-happens-before-phase1.md, lane SKEL as amended by the
  "Owner rulings 2026-11-17" block; spec docs\superpowers\specs\2026-11-17-happens-before-design.md
  sections 2.1 (answer shape), 5 (algorithm) and 6.4 (reason codes).

  FROZEN AT MERGE: every other HB lane (ROOTS, EVENTS, INTRA, SOLVER, FIELDS, RECV, EVORD, HOVER, MCP,
  IDE) compiles against this interface. Adding a member is cheap; renaming or reordering one is a
  cross-lane change. The literal strings (VerdictCode, ReasonCode, HowCode ...) are the JSON / text
  contract that tools branch on: never change a literal, only add one. }

interface

uses
  System.SysUtils
  ;

const
  /// <summary>Default `--max-routines` budget: the most CFGs one query builds (spec 5.4 step 6).</summary>
  HB_DEFAULT_MAX_ROUTINES = 2000;

  /// <summary>The `limits[]` code a scaffold answer carries until the solver lane lands.</summary>
  HB_LIMIT_NOT_IMPLEMENTED = 'not-implemented';

  /// <summary>Default `--max-seconds` wall-clock cap of one query (v152 HBFIX H3; HBMEASURE measured
  /// up to 669 s for one CLIENT global).</summary>
  HB_DEFAULT_MAX_SECONDS = 60;

  /// <summary>The `limits[]` code of an answer the wall-clock cap stopped: `stopped-after <N>s`.</summary>
  HB_LIMIT_STOPPED_AFTER = 'stopped-after';

  /// <summary>The `limits[]` code of an answer with no judged use (v152 HBFIX, HBMEASURE F5): a SET
  /// over zero uses is vacuous -- nothing reads the target, so nothing can read it unset.</summary>
  HB_LIMIT_NO_JUDGED_USE = 'no-judged-use';

type
  /// <summary>The verdicts of check-init (ruling HB2, plus the owner's UNKNOWN-CALLEE of 2026-11-17
  /// 13:56). Literals: VerdictCode.</summary>
  /// <remarks>
  /// hvSet = proven: every write-before-use path holds. hvNeverSet = proven absence of any
  /// writer (spec 6.2). hvMayBeUnset = everything else, "not proven safe", never a proof of a bad run.
  /// hvUnknownCallee = a MAY-BE-UNSET whose doubt includes the target passed to a callee with no
  /// source / no resolved signature (does it set it?); only the answer headline carries it, a judged
  /// use stays MAY-BE-UNSET. Exit 1 like every verdict but SET.
  /// Ordinal order is the badness order used by HbWorseVerdict: hvSet best, hvUnknownCallee worst.
  /// Append only: renderers and tools index arrays by this type.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Query.HappensBefore.Types.pas) ?, DRagLint.Query.HappensBefore.AnswerEveryUse (DRagLint.Query.HappensBefore.pas) ?, DRagLint.Query.HappensBefore.Render.HbAnswerText (DRagLint.Query.HappensBefore.Render.pas), DRagLint.Query.HappensBefore.Types.HbWorseVerdict (DRagLint.Query.HappensBefore.Types.pas) ?, DRagLint.Query.HappensBefore.Types.VerdictCode (DRagLint.Query.HappensBefore.Types.pas) ?</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  THbVerdict = (hvSet, hvNeverSet, hvMayBeUnset, hvUnknownCallee);

  /// <summary>Closed list of reason codes (spec 6.4, plus HB3 receiver-unproven, HB5
  /// relied-on-handler-order, the spec 5.1 guarded-test tag and the owner's unknown-callee: the answer
  /// holds the target passed to a callee with no source). Literals: ReasonCode.</summary>
  /// <remarks>
  /// Append only; tools and the surface runner branch on the literals.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Query.HappensBefore.Events.pas) ?, declaration (DRagLint.Query.HappensBefore.Fields.pas) ?, DRagLint.Query.HappensBefore.Events.HbIsNeverSet (DRagLint.Query.HappensBefore.Events.pas) ?, DRagLint.Query.HappensBefore.Fields.AddReason (DRagLint.Query.HappensBefore.Fields.pas) ?, DRagLint.Query.HappensBefore.SortedReasons (DRagLint.Query.HappensBefore.pas) (+18 more)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  THbReason = (
    hrUnorderedRoot, hrEscapedRoutine, hrWriterConditional, hrWriterLaterUnit, hrWriterAfterUseSameRoutine,  // dl:ok unused-enum-value@75ab -- REVIEWED 2026-11-17 v152 HBSKEL: frozen check-init contract; the engine lanes (EVENTS, SOLVER, FIELDS, RECV, EVORD) name these values
    hrCalleeNotMust, hrIndirectCall, hrVirtualFanout, hrInterfaceCall, hrSoftWriter, hrNilWriteOnly,  // dl:ok unused-enum-value@c81b -- REVIEWED 2026-11-17 v152 HBSKEL: frozen check-init contract; the engine lanes (EVENTS, SOLVER, FIELDS, RECV, EVORD) name these values
    hrCtorMissesField, hrNoDeclaredCtor, hrSubclassCtorSkips, hrVirtualCallInAncestorCtor, hrSelfEscapesInCtor,  // dl:ok unused-enum-value@7be7 -- REVIEWED 2026-11-17 v152 HBSKEL: frozen check-init contract; the engine lanes (EVENTS, SOLVER, FIELDS, RECV, EVORD) name these values
    hrUnreliableOrder, hrMultiProgram, hrWriterOnThread, hrCfgSkipped, hrBudget, hrIndexIncomplete,  // dl:ok unused-enum-value@d3c3 -- REVIEWED 2026-11-17 v152 HBSKEL: frozen check-init contract; the engine lanes (EVENTS, SOLVER, FIELDS, RECV, EVORD) name these values
    hrReliedOnHandlerOrder, hrReceiverUnproven, hrGuardedTest, hrUnknownCallee);  // dl:ok unused-enum-value@ac06 -- REVIEWED 2026-11-17 v152 HBSKEL: frozen check-init contract; the engine lanes (EVENTS, SOLVER, FIELDS, RECV, EVORD) name these values

  /// <summary>How a writer writes the target (spec 5.1, plan D5). Literals: HowCode.</summary>
  /// <remarks>
  /// hwAssign .. hwDfmStream are resolved writes; hwAssignNil never counts as initialization
  /// for class / interface / pointer / procedural targets (HB4). hwUnresolved, hwWithOpaque and
  /// hwAddressOf are SOFT writers: they never help prove SET and forbid NEVER-SET.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Query.HappensBefore.Events.pas), declaration (DRagLint.Query.HappensBefore.Types.pas), DRagLint.Query.HappensBefore.Events.TCollector.AddWriter (DRagLint.Query.HappensBefore.Events.pas), DRagLint.Query.HappensBefore.Events.TCollector.AssignHow (DRagLint.Query.HappensBefore.Events.pas), DRagLint.Query.HappensBefore.Types.HowCode (DRagLint.Query.HappensBefore.Types.pas)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  THbWriterHow = (hwAssign, hwAssignNil, hwVarArg, hwOutArg, hwCreateInto, hwDfmStream,
    hwUnresolved, hwWithOpaque, hwAddressOf);

  /// <summary>What the target is. Literals: TargetKindCode.</summary>
  /// <remarks>
  /// htkUnresolved only appears in a scaffold answer or before target resolution ran.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Query.HappensBefore.Types.pas), DRagLint.Query.HappensBefore.Types.TargetKindCode (DRagLint.Query.HappensBefore.Types.pas)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  THbTargetKind = (htkUnresolved, htkUnitVar, htkClassVar, htkInstanceField);  // dl:ok unused-enum-value@99d3 -- REVIEWED 2026-11-17 v152 HBSKEL: frozen check-init contract; the engine lanes (EVENTS, SOLVER, FIELDS, RECV, EVORD) name these values

  /// <summary>Proof scope: program order (unit / class vars, spec 5.4) or per instance (fields, 5.5).
  /// Literals: ScopeCode.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Query.HappensBefore.Types.pas), DRagLint.Query.HappensBefore.Types.ScopeCode (DRagLint.Query.HappensBefore.Types.pas)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  THbScope = (hsProgram, hsInstance);  // dl:ok unused-enum-value@923f -- REVIEWED 2026-11-17 v152 HBSKEL: frozen check-init contract; the engine lanes (EVENTS, SOLVER, FIELDS, RECV, EVORD) name these values

  /// <summary>One source position, optionally inside a routine.</summary>
  /// <remarks>
  /// Line and Col are 1-based; Col = 0 means "the whole line" (an `--at file:line` without
  /// a column). RoutineId = 0 when the site is not inside an indexed routine.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.CLI.CheckInit.RunCheckInit (DRagLint.CLI.CheckInit.pas), DRagLint.MCP.Server.TMCPServer.DispatchToolsCall (DRagLint.MCP.Server.pas), DRagLint.Query.HappensBefore.CheckInit (DRagLint.Query.HappensBefore.pas), DRagLint.Query.HappensBefore.Events.TCollector.MakeSite (DRagLint.Query.HappensBefore.Events.pas), DRagLint.Query.HappensBefore.Fields.SiteOf (DRagLint.Query.HappensBefore.Fields.pas) (+50 more)</para>
  /// <para>Used in units: DRagLint.CLI.CheckInit, DRagLint.MCP.Server, DRagLint.Query.HappensBefore, DRagLint.Query.HappensBefore.Events, DRagLint.Query.HappensBefore.Fields, DRagLint.Query.HappensBefore.Handlers, DRagLint.Query.HappensBefore.Intra, DRagLint.Query.HappensBefore.Receiver, DRagLint.Query.HappensBefore.Render, DRagLint.Query.HappensBefore.Types</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  THbSite = record
    FileName: string;
    Line: Integer;
    Col: Integer;
    /// <summary>Enclosing routine QName ('' when unknown).</summary>
    Routine: string;
    /// <summary>symbols.id of the enclosing routine; 0 when unknown.</summary>
    RoutineId: Int64;
  end;

  /// <summary>The variable / field asked about (JSON `target`).</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Query.HappensBefore.Events.pas), declaration (DRagLint.Query.HappensBefore.Types.pas), DRagLint.Query.HappensBefore.Render.TargetJson (DRagLint.Query.HappensBefore.Render.pas)</para>
  /// <para>Used in units: DRagLint.Query.HappensBefore.Events, DRagLint.Query.HappensBefore.Render, DRagLint.Query.HappensBefore.Types</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  THbTarget = record
    QName: string;
    Kind: THbTargetKind;
    /// <summary>symbols.id of the target; 0 when unresolved.</summary>
    SymbolId: Int64;
    /// <summary>Declaration file ('' when unresolved).</summary>
    FileName: string;
    /// <summary>Declaration line (0 when unresolved).</summary>
    Line: Integer;
    TypeName: string;
    /// <summary>The value the target holds until set: 'nil', '0', '''''', 'False' ... (spec 3).</summary>
    ZeroValue: string;
  end;

  /// <summary>One writer row (JSON `writers[]`, plan D5 / ruling HB2).</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Query.HappensBefore.Events.pas) ?, DRagLint.Query.HappensBefore.Events.TCollector.AddWriter (DRagLint.Query.HappensBefore.Events.pas), DRagLint.Query.HappensBefore.Events.TCollector.CallersOf (DRagLint.Query.HappensBefore.Events.pas) ?, DRagLint.Query.HappensBefore.Events.TCollector.Create (DRagLint.Query.HappensBefore.Events.pas) ?, DRagLint.Query.HappensBefore.Fields.TFieldSolver.LoadWrites (DRagLint.Query.HappensBefore.Fields.pas) (+5 more)</para>
  /// <para>Used in units: DRagLint.Query.HappensBefore, DRagLint.Query.HappensBefore.Events, DRagLint.Query.HappensBefore.Fields, DRagLint.Query.HappensBefore.Render, DRagLint.Query.HappensBefore.Types</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  THbWriter = record
    Site: THbSite;
    How: THbWriterHow;
    /// <summary>True when the write ref resolved to the target symbol; False for a soft writer.</summary>
    Resolved: Boolean;
    /// <summary>True when this write counts as initialization (False for assign-nil on a reference
    /// type and for every soft writer).</summary>
    Counts: Boolean;
    /// <summary>`Form.Control.Event` when Site.Routine is a DFM-bound handler; else ''.</summary>
    FiredBy: string;
    /// <summary>Number of routines that call Site.Routine (0 when FiredBy is set or unknown).</summary>
    CallerCount: Integer;
    /// <summary>Up to three caller QNames, most relevant first.</summary>
    TopCallers: TArray<string>;
  end;

  /// <summary>One witness hop, printed root-first (JSON `witness[]`).</summary>
  /// <remarks>
  /// Step is 1-based; the text renderer indents hop N by N-1 levels.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Query.HappensBefore.Fields.pas) ?, DRagLint.Query.HappensBefore.Fields.TFieldSolver.ClassBlockers (DRagLint.Query.HappensBefore.Fields.pas), DRagLint.Query.HappensBefore.Fields.TFieldSolver.MethodHop (DRagLint.Query.HappensBefore.Fields.pas), DRagLint.Query.HappensBefore.Fields.TFieldSolver.Run (DRagLint.Query.HappensBefore.Fields.pas), DRagLint.Query.HappensBefore.TSolver.JudgeUse (DRagLint.Query.HappensBefore.pas) (+4 more)</para>
  /// <para>Used in units: DRagLint.Query.HappensBefore, DRagLint.Query.HappensBefore.Fields, DRagLint.Query.HappensBefore.Types</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  THbHop = record
    Step: Integer;
    Routine: string;
    FileName: string;
    Line: Integer;
    Col: Integer;
    /// <summary>Free text: "reads GSettings", "init position 14 of 212 (App.dpr)" ...</summary>
    Note: string;
  end;

  /// <summary>The verdict for one judged use (JSON `uses[]`).</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Query.HappensBefore.Receiver.pas) ?, DRagLint.Query.HappensBefore.AnswerEveryUse (DRagLint.Query.HappensBefore.pas), DRagLint.Query.HappensBefore.Fields.NoteReason (DRagLint.Query.HappensBefore.Fields.pas) ?, DRagLint.Query.HappensBefore.Fields.TFieldSolver.Run (DRagLint.Query.HappensBefore.Fields.pas), DRagLint.Query.HappensBefore.TSolver.Run (DRagLint.Query.HappensBefore.pas) (+4 more)</para>
  /// <para>Used in units: DRagLint.Query.HappensBefore, DRagLint.Query.HappensBefore.Fields, DRagLint.Query.HappensBefore.Receiver, DRagLint.Query.HappensBefore.Render, DRagLint.Query.HappensBefore.Types</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  THbUseAnswer = record
    Site: THbSite;
    Verdict: THbVerdict;
    Reasons: TArray<THbReason>;
    Witness: TArray<THbHop>;
    /// <summary>One line "why not SET: ..." for the text output. A SET use carries '' unless it
    /// relies on DFM handler order (reason relied-on-handler-order, HBEVORD): then the line names the
    /// handler and why it runs after the writer.</summary>
    Why: string;
  end;

  /// <summary>Root summary of the answer (JSON `roots`).</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Query.HappensBefore.Types.pas)</para>
  /// <para>Used in units: DRagLint.Query.HappensBefore.Types</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  THbRootSummary = record
    /// <summary>Ordered root chain, display names in run order ("initialization of Boot", ...).</summary>
    Ordered: TArray<string>;
    /// <summary>Number of unordered (escaped) roots that reach a judged use.</summary>
    Unordered: Integer;
  end;

  /// <summary>Work spent on the answer (JSON `budget`).</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Query.HappensBefore.Types.pas)</para>
  /// <para>Used in units: DRagLint.Query.HappensBefore.Types</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  THbBudget = record
    /// <summary>CFGs built.</summary>
    Routines: Integer;
    Ms: Int64;
    /// <summary>True when --max-routines ran out or the --max-seconds cap stopped the query; the
    /// verdict is then never a proof.</summary>
    Exhausted: Boolean;
    /// <summary>True when the --max-seconds wall-clock cap stopped the query (Exhausted is then True).</summary>
    TimedOut: Boolean;
    /// <summary>The cap in seconds that was in force; 0 = no cap.</summary>
    MaxSeconds: Double;
  end;

  /// <summary>The whole check-init answer; Render turns it into JSON / text and an exit code.</summary>
  /// <remarks>
  /// Verdict is the headline: the worst verdict over JudgedUses (HbWorseVerdict), or the target's
  /// verdict when no use is judged. Proven is True only for SET / NEVER-SET backed by a proof.
  /// Reasons are answer-level codes (e.g. budget, multi-program) that belong to no single use.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Query.HappensBefore.Fields.pas) ?, DRagLint.CLI.CheckInit.RunCheckInit (DRagLint.CLI.CheckInit.pas) ?, DRagLint.Query.HappensBefore.CheckInit (DRagLint.Query.HappensBefore.pas), DRagLint.Query.HappensBefore.Fields.CheckInstanceField (DRagLint.Query.HappensBefore.Fields.pas), DRagLint.Query.HappensBefore.Fields.TFieldSolver.LoadWrites (DRagLint.Query.HappensBefore.Fields.pas) ? (+16 more)</para>
  /// <para>Used in units: DRagLint.CLI.CheckInit, DRagLint.Query.HappensBefore, DRagLint.Query.HappensBefore.Fields, DRagLint.Query.HappensBefore.Receiver, DRagLint.Query.HappensBefore.Render, DRagLint.Query.HoverModel</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  THbAnswer = record
    Target: THbTarget;
    Scope: THbScope;
    Verdict: THbVerdict;
    Proven: Boolean;
    /// <summary>One-line headline note printed after the verdict, e.g. "(every instance: both
    /// constructors assign it before they return)"; '' for none.</summary>
    Summary: string;
    Reasons: TArray<THbReason>;
    JudgedUses: TArray<THbUseAnswer>;
    Writers: TArray<THbWriter>;
    Roots: THbRootSummary;
    /// <summary>Limit codes that bound this answer ('not-implemented', 'use-after-free-not-judged' ...).</summary>
    Limits: TArray<string>;
    Budget: THbBudget;
  end;

  /// <summary>Query options from the CLI / MCP.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Query.HappensBefore.pas) ?, DRagLint.CLI.CheckInit.RunCheckInit (DRagLint.CLI.CheckInit.pas), DRagLint.MCP.Server.TMCPServer.DispatchToolsCall (DRagLint.MCP.Server.pas), DRagLint.Query.HappensBefore.CheckInit (DRagLint.Query.HappensBefore.pas) ?, DRagLint.Query.HoverModel.AttachHoverSetBy (DRagLint.Query.HoverModel.pas)</para>
  /// <para>Used in units: DRagLint.CLI.CheckInit, DRagLint.MCP.Server, DRagLint.Query.HappensBefore, DRagLint.Query.HoverModel</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  THbOptions = record
    /// <summary>Most CFGs per query; 0 = HB_DEFAULT_MAX_ROUTINES.</summary>
    MaxRoutines: Integer;
    /// <summary>--explain: the text output adds roots and per-use reasons.</summary>
    Explain: Boolean;
    /// <summary>--max-seconds wall-clock cap; 0 = HB_DEFAULT_MAX_SECONDS, negative = no cap.</summary>
    MaxSeconds: Double;
  end;

  /// <summary>A usage error found while answering (unknown / ambiguous target, a --at that names a
  /// different variable than the QName). The verb prints Message and Candidates and exits 2.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.CLI.CheckInit.RunCheckInit (DRagLint.CLI.CheckInit.pas) ?, DRagLint.Query.HappensBefore.CheckInit (DRagLint.Query.HappensBefore.pas), DRagLint.Query.HappensBefore.Events.TCollector.ResolveAt (DRagLint.Query.HappensBefore.Events.pas), DRagLint.Query.HappensBefore.Events.TCollector.ResolveName (DRagLint.Query.HappensBefore.Events.pas), DRagLint.Query.HappensBefore.Events.TCollector.ResolveTarget (DRagLint.Query.HappensBefore.Events.pas) (+2 more)</para>
  /// <para>Used in units: DRagLint.CLI.CheckInit, DRagLint.MCP.Server, DRagLint.Query.HappensBefore, DRagLint.Query.HappensBefore.Events, DRagLint.Query.HoverModel</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  EHbUsage = class(Exception)
  private
    FCandidates: TArray<string>;
  public
    /// <summary>Creates the error with the candidate QNames to show the user.</summary>
    /// <param name="pMsg">One-line message.</param>
    /// <param name="pCandidates">Candidate QNames (empty for an unknown target).</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Query.HappensBefore.CheckInit (DRagLint.Query.HappensBefore.pas), DRagLint.Query.HappensBefore.Events.TCollector.ResolveAt (DRagLint.Query.HappensBefore.Events.pas), DRagLint.Query.HappensBefore.Events.TCollector.ResolveName (DRagLint.Query.HappensBefore.Events.pas), DRagLint.Query.HappensBefore.Events.TCollector.ResolveTarget (DRagLint.Query.HappensBefore.Events.pas)</para>
    /// <para>Calls: Create</para>
    /// <para>constructor</para>
    /// <para>Writes: FCandidates</para>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    constructor CreateCandidates(const pMsg: string; const pCandidates: TArray<string>);
    /// <summary>Candidate QNames for an ambiguous target; empty otherwise.</summary>
    property Candidates: TArray<string> read FCandidates;
  end;

/// <summary>The verdict literal: SET, NEVER-SET, MAY-BE-UNSET (ruling HB2 / plan D4) or
/// UNKNOWN-CALLEE (owner ruling 2026-11-17 13:56).</summary>
/// <param name="pVerdict">The verdict.</param>
/// <returns>The literal used in JSON and text.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Query.HappensBefore.Render.HbAnswerJson (DRagLint.Query.HappensBefore.Render.pas), DRagLint.Query.HappensBefore.Render.HbAnswerText (DRagLint.Query.HappensBefore.Render.pas), DRagLint.Query.HappensBefore.Render.UseJson (DRagLint.Query.HappensBefore.Render.pas), DRagLint.Query.HoverModel.BuildSetBy (DRagLint.Query.HoverModel.pas)</para>
/// <para>Returns: VERDICT_CODES[pVerdict]</para>
/// <para>Effect-free (proven)</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function VerdictCode(pVerdict: THbVerdict): string;

/// <summary>The kebab-case literal of a reason (spec 6.4).</summary>
/// <param name="pReason">The reason.</param>
/// <returns>e.g. 'writer-later-unit'.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Query.HappensBefore.Render.ReasonsJson (DRagLint.Query.HappensBefore.Render.pas), DRagLint.Query.HappensBefore.Render.ReasonsText (DRagLint.Query.HappensBefore.Render.pas)</para>
/// <para>Returns: REASON_CODES[pReason]</para>
/// <para>Effect-free (proven)</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ReasonCode(pReason: THbReason): string;

/// <summary>The literal of a writer's `how`: assign, assign-nil, var-arg, out-arg, create-into,
/// dfm-stream, unresolved, with-opaque, address-of.</summary>
/// <param name="pHow">The writer kind.</param>
/// <returns>The literal.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Query.HappensBefore.Render.WriterJson (DRagLint.Query.HappensBefore.Render.pas), DRagLint.Query.HappensBefore.Render.WriterText (DRagLint.Query.HappensBefore.Render.pas)</para>
/// <para>Returns: HOW_CODES[pHow]</para>
/// <para>Effect-free (proven)</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function HowCode(pHow: THbWriterHow): string;

/// <summary>The literal of a target kind: unresolved, unit-variable, class-var, instance-field.</summary>
/// <param name="pKind">The kind.</param>
/// <returns>The literal.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Query.HappensBefore.Render.HbAnswerText (DRagLint.Query.HappensBefore.Render.pas), DRagLint.Query.HappensBefore.Render.TargetJson (DRagLint.Query.HappensBefore.Render.pas)</para>
/// <para>Returns: KIND_CODES[pKind]</para>
/// <para>Effect-free (proven)</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function TargetKindCode(pKind: THbTargetKind): string;

/// <summary>The literal of a scope: program or instance.</summary>
/// <param name="pScope">The scope.</param>
/// <returns>The literal.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Query.HappensBefore.Render.HbAnswerJson (DRagLint.Query.HappensBefore.Render.pas)</para>
/// <para>Returns: SCOPE_CODES[pScope]</para>
/// <para>Effect-free (proven)</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ScopeCode(pScope: THbScope): string;

/// <summary>The worse of two verdicts (hvSet &lt; hvNeverSet &lt; hvMayBeUnset &lt; hvUnknownCallee).</summary>
/// <param name="pA">First verdict.</param>
/// <param name="pB">Second verdict.</param>
/// <returns>The worse one.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Query.HappensBefore.Fields.TFieldSolver.Run (DRagLint.Query.HappensBefore.Fields.pas), DRagLint.Query.HappensBefore.Receiver.ApplyReceiverProof (DRagLint.Query.HappensBefore.Receiver.pas), DRagLint.Query.HappensBefore.TSolver.Run (DRagLint.Query.HappensBefore.pas)</para>
/// <para>Returns: if Ord(pA) &gt;= Ord(pB) then pA</para>
/// <para>Effect-free (proven)</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function HbWorseVerdict(pA, pB: THbVerdict): THbVerdict;

/// <summary>Parses `--at file:line[:col]`. A drive letter colon is part of the file name.</summary>
/// <param name="pAt">The flag value, e.g. `C:\src\Boot.pas:41:12` or `Boot.pas:41`.</param>
/// <param name="pSite">The parsed site (FileName, Line, Col; Col = 0 when absent; Routine empty).</param>
/// <returns>False when the file part is empty, the line is not a number &gt;= 1 or the column is
/// not a number &gt;= 1.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.CheckInit.RunCheckInit (DRagLint.CLI.CheckInit.pas), DRagLint.MCP.Server.TMCPServer.DispatchToolsCall (DRagLint.MCP.Server.pas), DRagLint.Query.HappensBefore.CheckInit (DRagLint.Query.HappensBefore.pas)</para>
/// <para>Calls: Default, DRagLint.Query.HappensBefore.Types.SplitLastColon, Trim, TryStrToInt</para>
/// <para>Returns: False; (pSite.FileName &lt;&gt; '') and (pSite.Line &gt;= 1)</para>
/// <para>Mutates: pSite (out)</para>
/// <seealso cref="DRagLint.Query.HappensBefore.Types.SplitLastColon"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function HbParseAt(const pAt: string; out pSite: THbSite): Boolean;

/// <summary>Starts the wall-clock cap of the query on this thread (v152 HBFIX H3).</summary>
/// <param name="pMaxSeconds">The cap in seconds; &lt;= 0 = no cap.</param>
/// <remarks>
/// Per thread (threadvar): one query at a time per thread. Every solver of check-init asks
/// HbTimeUp before it builds a CFG and treats True like a spent --max-routines budget.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Query.HappensBefore.CheckInit (DRagLint.Query.HappensBefore.pas)</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure HbStartClock(pMaxSeconds: Double);

/// <summary>True once the cap started by HbStartClock has run out; latches HbTimedOut.</summary>
/// <returns>False when no cap is in force.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Query.HappensBefore.Fields.TFieldSolver.Solve (DRagLint.Query.HappensBefore.Fields.pas), DRagLint.Query.HappensBefore.Receiver.TRecvSolver.Solve (DRagLint.Query.HappensBefore.Receiver.pas), DRagLint.Query.HappensBefore.TSolver.RawSolve (DRagLint.Query.HappensBefore.pas), DRagLint.Query.HappensBefore.TSolver.Run (DRagLint.Query.HappensBefore.pas)</para>
/// <para>Returns: (GHbDeadline &lt;&gt; 0) and (TStopwatch.GetTimeStamp &gt;= GHbDeadline)</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function HbTimeUp: Boolean;

/// <summary>True when HbTimeUp answered True since the last HbStartClock.</summary>
/// <returns>Whether the cap stopped the current query.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Query.HappensBefore.FinishLimits (DRagLint.Query.HappensBefore.pas)</para>
/// <para>Returns: GHbTimedOut</para>
/// <para>Effect-free (proven)</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function HbTimedOut: Boolean;

/// <summary>The why text of a use the budget left unproven: 'stopped after N s (--max-seconds)' when the
/// wall-clock cap ran out, else 'the --max-routines budget ran out'.</summary>
/// <returns>The text, without the 'why not SET: ' prefix.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Query.HappensBefore.Fields.TFieldSolver.Run (DRagLint.Query.HappensBefore.Fields.pas), DRagLint.Query.HappensBefore.Receiver.TRecvSolver.FailNotSolved (DRagLint.Query.HappensBefore.Receiver.pas), DRagLint.Query.HappensBefore.TSolver.Run (DRagLint.Query.HappensBefore.pas)</para>
/// <para>Calls: DRagLint.Query.HappensBefore.Types.HbCapText</para>
/// <para>Returns: if GHbTimedOut then 'stopped after ' + HbCapText + ' s (--max-seconds)'</para>
/// <para>Effect-free (proven)</para>
/// <seealso cref="DRagLint.Query.HappensBefore.Types.HbCapText"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function HbBudgetWhy: string;

/// <summary>`N` of 'stopped after N s': the cap in force, formatted with up to three decimals.</summary>
/// <returns>e.g. '60' or '0.001'; '0' when no cap is in force.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Query.HappensBefore.FinishLimits (DRagLint.Query.HappensBefore.pas), DRagLint.Query.HappensBefore.Types.HbBudgetWhy (DRagLint.Query.HappensBefore.Types.pas)</para>
/// <para>Calls: FormatFloat</para>
/// <para>Returns: FormatFloat('0.###', GHbCapSeconds, TFormatSettings.Invariant)</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function HbCapText: string;

/// <summary>v152 HOVERCACHE: starts a fresh DRAGLINT_PROFILE phase list for one check-init call.</summary>
/// <remarks>Off (every HbProfile* call a no-op) unless the environment variable DRAGLINT_PROFILE is set.
/// Diagnostic only: one process-wide list, so concurrent check-init calls would interleave their phases.</remarks>
procedure HbProfileReset;

/// <summary>v152 HOVERCACHE: appends one phase of the current check-init call to the profile list.</summary>
/// <param name="pPhase">Phase name, e.g. 'init-orders'.</param>
/// <param name="pMs">Its wall time in milliseconds.</param>
/// <param name="pNote">'' or a word shown in brackets after the time (cached, computed, stopped).</param>
procedure HbProfileAdd(const pPhase: string; pMs: Int64; const pNote: string = '');

/// <summary>v152 HOVERCACHE: the phases added since HbProfileReset, 'name N ms (note) | ...'.</summary>
/// <returns>'' when profiling is off or nothing was added.</returns>
function HbProfileText: string;

implementation

uses
  System.Diagnostics
  ;

threadvar
  GHbDeadline: Int64;   { TStopwatch ticks; 0 = no cap }
  GHbCapSeconds: Double;
  GHbTimedOut: Boolean;

const
  VERDICT_CODES: array[THbVerdict] of string = ('SET', 'NEVER-SET', 'MAY-BE-UNSET', 'UNKNOWN-CALLEE');
  REASON_CODES: array[THbReason] of string = (
    'unordered-root', 'escaped-routine', 'writer-conditional', 'writer-later-unit', 'writer-after-use-same-routine',
    'callee-not-must', 'indirect-call', 'virtual-fanout', 'interface-call', 'soft-writer', 'nil-write-only',
    'ctor-misses-field', 'no-declared-ctor', 'subclass-ctor-skips', 'virtual-call-in-ancestor-ctor', 'self-escapes-in-ctor',
    'unreliable-order', 'multi-program', 'writer-on-thread', 'cfg-skipped', 'budget', 'index-incomplete',
    'relied-on-handler-order', 'receiver-unproven', 'guarded-test', 'unknown-callee');
  HOW_CODES: array[THbWriterHow] of string = ('assign', 'assign-nil', 'var-arg', 'out-arg', 'create-into',
    'dfm-stream', 'unresolved', 'with-opaque', 'address-of');
  KIND_CODES: array[THbTargetKind] of string = ('unresolved', 'unit-variable', 'class-var', 'instance-field');
  SCOPE_CODES: array[THbScope] of string = ('program', 'instance');

constructor EHbUsage.CreateCandidates(const pMsg: string; const pCandidates: TArray<string>);
begin
  inherited Create(pMsg);
  FCandidates:= pCandidates;
end;

function VerdictCode(pVerdict: THbVerdict): string;
begin
  Result:= VERDICT_CODES[pVerdict];
end;

function ReasonCode(pReason: THbReason): string;
begin
  Result:= REASON_CODES[pReason];
end;

function HowCode(pHow: THbWriterHow): string;
begin
  Result:= HOW_CODES[pHow];
end;

function TargetKindCode(pKind: THbTargetKind): string;
begin
  Result:= KIND_CODES[pKind];
end;

function ScopeCode(pScope: THbScope): string;
begin
  Result:= SCOPE_CODES[pScope];
end;

function HbWorseVerdict(pA, pB: THbVerdict): THbVerdict;
begin
  Result:= if Ord(pA) >= Ord(pB) then pA else pB;
end;

{ Splits off the trailing `:<text>` of pS. False when pS has no colon past position 2 (a drive
  letter colon `C:` is never a separator). }
function SplitLastColon(const pS: string; out pHead, pTail: string): Boolean;
begin
  pHead:= '';
  pTail:= '';
  var P:= LastDelimiter(':', pS);
  Result:= P > 2;
  if not Result then Exit;
  pHead:= Copy(pS, 1, P - 1);
  pTail:= Copy(pS, P + 1, MaxInt);
end;

function HbParseAt(const pAt: string; out pSite: THbSite): Boolean;
var
  Head, Tail, Head2, Tail2: string;
  N, N2: Integer;
begin
  pSite:= Default(THbSite);
  Result:= False;
  if not SplitLastColon(Trim(pAt), Head, Tail) then Exit;
  if not TryStrToInt(Tail, N) then Exit;
  if SplitLastColon(Head, Head2, Tail2) then
  begin
    { file:line:col -- a Windows file name holds no colon past the drive, so a non-number is an error }
    if not TryStrToInt(Tail2, N2) then Exit;
    pSite.FileName:= Head2;
    pSite.Line:= N2;
    pSite.Col:= N;
    if N < 1 then Exit;
  end
  else
  begin
    { file:line }
    pSite.FileName:= Head;
    pSite.Line:= N;
  end;
  Result:= (pSite.FileName <> '') and (pSite.Line >= 1);
end;

procedure HbStartClock(pMaxSeconds: Double);
begin
  GHbTimedOut:= False;
  GHbCapSeconds:= if pMaxSeconds > 0 then pMaxSeconds else 0;
  GHbDeadline:= 0;
  if pMaxSeconds > 0 then
    GHbDeadline:= TStopwatch.GetTimeStamp + Round(pMaxSeconds * TStopwatch.Frequency);
end;

function HbTimeUp: Boolean;
begin
  if GHbTimedOut then Exit(True);
  Result:= (GHbDeadline <> 0) and (TStopwatch.GetTimeStamp >= GHbDeadline);
  if Result then GHbTimedOut:= True;
end;

function HbTimedOut: Boolean;
begin
  Result:= GHbTimedOut;
end;

var
  GHbProfileOn: Boolean;
  GHbProfile: string;

procedure HbProfileReset;
begin
  GHbProfileOn:= GetEnvironmentVariable('DRAGLINT_PROFILE') <> '';
  GHbProfile:= '';
end;

procedure HbProfileAdd(const pPhase: string; pMs: Int64; const pNote: string);
begin
  if not GHbProfileOn then Exit;
  var Item: string:= Format('%s %d ms', [pPhase, pMs]);
  if pNote <> '' then Item:= Item + ' (' + pNote + ')';
  GHbProfile:= if GHbProfile = '' then Item else GHbProfile + ' | ' + Item;
end;

function HbProfileText: string;
begin
  Result:= if GHbProfileOn then GHbProfile else '';
end;

function HbCapText: string;
begin
  Result:= FormatFloat('0.###', GHbCapSeconds, TFormatSettings.Invariant);
end;

function HbBudgetWhy: string;
begin
  Result:= if GHbTimedOut then 'stopped after ' + HbCapText + ' s (--max-seconds)'
    else 'the --max-routines budget ran out';
end;
end.
