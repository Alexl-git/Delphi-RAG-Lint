unit DRagLint.Doc.SharedFacts;

{ Shared-unit facts: the ONE place that knows how an inbound fact line is split
  into entries, which entries a project cannot see, and how two projects' views
  of the same block are reconciled.

  THE PROBLEM, measured 2026-08-13 on YADF/YADFOT/YADFSetup. A unit compiled by
  three projects has three indexes, and each index truthfully holds only its own
  closure. `YADF.Options.ParseEncoding` stores

      Called from: YADF.Options.OptionTable (YADF.Options.pas), YadfMain.ParseFlags (YadfMain.pas)

  and renders, under YADFOT's index, the same block WITHOUT the YadfMain entry --
  every other line byte-identical, because YADFOT does not compile YadfMain.pas.
  `TDocDrift` byte-compared, called the block stale, and the repair dropped the
  entry; YADF then called it stale in the other direction. YADFOT reported 31
  such findings and YADFSetup 34, while YADF reported 0 on the very same files.

  TWO HALVES, AND NEITHER WORKS ALONE.

  * The CHECKER forgives a stored entry missing from the fresh render when the
    unit is marked `dl:shared`, the entry names a unit outside this closure, and
    the entry is not flagged uncertain. Without this the narrow project calls the
    union stale forever.
  * The WRITER unions those same entries back in, so a write from ANY project
    preserves what the others contributed instead of replacing it. Without this
    the first write from a narrow project destroys the wide project's entries,
    and the wide project re-adds them on its next run -- which is drift under the
    rule that an entry in FRESH and not in STORED is always drift. That rule
    stays: it is what records a genuinely NEW caller.

  Together the block converges to the UNION across every project that compiles
  the unit, which is what a reader of a shared unit actually wants.

  ENTRIES ONLY ACCUMULATE, AND THAT IS THE PRICE. A caller deleted in ANOTHER
  project's source is indistinguishable, from here, from a caller this project
  simply cannot see -- both are "in stored, not in fresh, unit not in my
  closure". So this design never reaps such an entry. Reaping belongs to a
  command that can open every index at once; until one exists, a stale entry on a
  shared unit outlives the code it names. Do not describe this as a limitation
  that might not matter: it is the direct cost of the ruling.

  FAIL-SAFE DIRECTION. Every uncertainty here resolves toward DRIFT, never toward
  silence. If a block cannot be parsed confidently, if a list is truncated, if a
  label is unrecognised, the answer is the byte compare that shipped before this
  unit existed. A false "stale" costs a rewrite; a false "current" leaves a lie
  in the source and is the failure this whole seam has now produced five times.

  WHY TRUNCATED LISTS ARE EXCLUDED. Inbound lists are capped (`docs.max_callers`,
  5 in the manifest) and the overflow renders as a `(+N more)` suffix. The
  visible entries are then a WINDOW onto the list, not the list: an entry can
  leave the window because the cap fell differently, and a real deletion can hide
  inside the count. Set difference over a window is unsound in both directions,
  so a truncated line keeps the byte compare and is never merged. Measured cost:
  6 of 55 inbound lines on the real shared units, none of them in
  YADF.Options.pas, which is 21 of the 31 findings.

  ...AND WHY THAT COST IS NOW ZERO, 2026-08-14 (Q0). The exclusion above was the
  only thing keeping the family from converging, so DRagLint.Doc.Facts stopped
  producing the window: a `dl:shared` unit's inbound lists are rendered UNCAPPED,
  at both cap sites (CalledFrom's `docs.max_callers` and UsedInUnits'
  DocDisplayCount). The rule here is UNCHANGED and still live -- a STORED line
  can carry `(+N more)` because it was written before that change or by hand, and
  it is no more set-differenceable for having aged. What changed is that the
  engine no longer creates such lines.

  That also means this guard had NO TEST COVERAGE until 2026-08-14. The fixture
  that claimed to cover it exercised the residual compare below instead (its
  narrow project renders no block at all, so `SRes <> FRes` decides first and
  IsTruncated is never reached). tests\autotest\run_shared_unit_staleness.ps1's
  `MarkTrunc` case is the first that actually reaches it.

  THE EMPTY-RENDER HOLE, closed 2026-08-14. It was DESTRUCTIVE: when the narrow
  project's fresh render is EMPTY -- it compiles the unit but calls nothing in it
  -- the residual compare below exited on 'Pure' vs '' before any inbound label
  was consulted, and TDocumenter then emitted a pure tekDeleteLines over the wide
  project's block, which the wide project rewrote on its next run.

  NEITHER HALF ABOVE COULD PREVENT IT, which is the part worth remembering:
  MergeInboundFacts merges INTO a rendered block and there was none, and the
  checker's forgiveness rule sits BELOW a byte compare that had already decided.
  A rule placed under an earlier decision is not a rule. Both halves now call
  HoldsForeignInboundEntries FIRST -- "does the stored block carry entries only
  another project could have written" -- and preserve when it says yes.

  Note that predicate treats a TRUNCATED line as foreign-bearing, which is the
  opposite polarity to the truncation rule above. Both are the same instinct:
  fail toward PRESERVING the source, because a `(+N more)` window may hide
  exactly such an entry.

  WHY `seealso` IS NOT IN SCOPE, despite being listed as inbound in the plan.
  Its crefs are derived from CALLEES and same-unit siblings, both of which are
  properties of this unit's own code, so every project that compiles the unit
  computes the same set. A cref also carries no file location, so the closure
  test would have to guess where a dotted name splits into unit and symbol.
  Nothing to forgive and no sound way to forgive it. }

interface

uses
  DRagLint.Core.Interfaces;

type
  /// <summary>Reconciles a managed facts block across the projects that compile
  /// a `dl:shared` unit.</summary>
  /// <remarks>
  /// Both entry points are no-ops on an unmarked unit, so nothing
  /// changes for anyone who has not opted in. Not thread-safe: the closure set
  /// is cached in class state, keyed on the store it was built from.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: [drag-lint]DRagLint.CLI.DoDocument (DRagLint.CLI.pas), [drag-lint]DRagLint.CLI.DoDocumentAll (DRagLint.CLI.pas), [drag-lint]DRagLint.CLI.Run (DRagLint.CLI.pas), [drag-lint]DRagLint.Doc.Document.SameButForLegacyPure (DRagLint.Doc.Document.pas), [drag-lint]DRagLint.Doc.Document.TDocumenter.BuildForSymbol (DRagLint.Doc.Document.pas), [drag-lint]DRagLint.Doc.Drift.TDocDrift.Analyze/4 (DRagLint.Doc.Drift.pas), [drag-lint]DRagLint.Doc.Regions.TDocRegions.RenderFactsBlock.JoinRefs (DRagLint.Doc.Regions.pas), [drag-lint]DRagLint.Doc.SharedFacts.ReconcileContent (DRagLint.Doc.SharedFacts.pas), [drag-lint]DRagLint.Doc.SharedFacts.ReconcileContent.SortedJoin (DRagLint.Doc.SharedFacts.pas), [drag-lint]DRagLint.Doc.SharedFacts.WithoutLegacyPure (DRagLint.Doc.SharedFacts.pas)</para>
  /// <para>Used in units: [drag-lint]DRagLint.CLI, [drag-lint]DRagLint.Doc.Document, [drag-lint]DRagLint.Doc.Drift, [drag-lint]DRagLint.Doc.Regions, [drag-lint]DRagLint.Doc.SharedFacts</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TSharedFacts = class
  public
    /// <summary>True when the stored block differs from a fresh render in a way
    /// that counts as drift.</summary>
    /// <param name="AStored">The managed block body as it stands in the source.
    /// The doc parser flattens newlines to spaces, so this arrives as one
    /// line.</param>
    /// <param name="AFresh">The freshly rendered block, still multi-line.</param>
    /// <param name="AStore">The current project's index. Not owned.</param>
    /// <param name="AUnitPath">Absolute path of the declaring unit; decides
    /// whether the unit is marked.</param>
    /// <returns>True to report `doc-drift`.</returns>
    /// <remarks>
    /// <para>An INBOUND list (`Called from:`, `Used by:`, `Used in units:`) is
    /// compared as a SET for EVERY unit -- owner ruling 2026-09-06, "order is
    /// not important, we should compare parts". Reordering entries is therefore
    /// not drift. Everything else in the block keeps the whitespace-collapsed
    /// byte compare, as does a TRUNCATED list (a `(+N more)` window is not the
    /// list, so set difference over it is unsound in both directions) and any
    /// block this unit cannot confidently parse.</para>
    /// <para>An entry the FRESH render found and the source does not record is
    /// drift for every unit -- that is how a new caller gets written down. The
    /// reverse, an entry only the SOURCE records, is forgiven only on a unit
    /// marked `dl:shared`, where another project may legitimately have written
    /// it; on an unmarked unit it is a stale entry and still drift.</para>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Doc.Drift.TDocDrift.Analyze/4 (DRagLint.Doc.Drift.pas)</para>
    /// <para>Calls: DRagLint.Doc.ProjectTags.SplitEntries, DRagLint.Doc.SharedFacts.CollapseWs, DRagLint.Doc.SharedFacts.IsTruncated, DRagLint.Doc.SharedFacts.IsUncertainEntry, DRagLint.Doc.SharedFacts.LabelContent, DRagLint.Doc.SharedFacts.ParaLabelCount, DRagLint.Doc.SharedFacts.ParseBlock, DRagLint.Doc.SharedFacts.Participates, DRagLint.Doc.SharedFacts.ReconciledDrift, DRagLint.Doc.SharedFacts.TSharedFacts.HoldsForeignInboundEntries, DRagLint.Doc.SharedFacts.UnitVouchable, DRagLint.Doc.SharedFacts.WithoutLegacyPure, DRagLint.Doc.SharedFacts.WithoutParaLabel, LowerCase</para>
    /// <para>Returns: CollapseWs(StoredCmp) &lt;&gt; CollapseWs(FreshCmp); False</para>
    /// <para>Complexity: 30 (cyclomatic, outer body), 185 lines (full implementation)</para>
    /// <seealso cref="DRagLint.Doc.ProjectTags.SplitEntries"/>
    /// <seealso cref="DRagLint.Doc.SharedFacts.CollapseWs"/>
    /// <seealso cref="DRagLint.Doc.SharedFacts.IsTruncated"/>
    /// <seealso cref="DRagLint.Doc.SharedFacts.IsUncertainEntry"/>
    /// <seealso cref="DRagLint.Doc.SharedFacts.LabelContent"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function BlockDrifted(const AStored, AFresh: string;
      const AStore: ISymbolStore; const AUnitPath: string): Boolean;

    /// <summary>Unions the stored inbound entries this project cannot see into a
    /// freshly built doc comment.</summary>
    /// <param name="ADocText">The whole comment MergeComment just produced,
    /// `///`-prefixed, containing the managed block.</param>
    /// <param name="AStoredRemarks">The existing parsed remarks, holding the old
    /// managed block.</param>
    /// <param name="AStore"><!-- drag-lint:auto type -->const ISymbolStore</param>
    /// <param name="AUnitPath"><!-- drag-lint:auto type -->const string</param>
    /// <returns>ADocText unchanged on an unmarked unit or when there is nothing
    /// to preserve; otherwise the same text with its inbound fact lines replaced
    /// by the sorted union.</returns>
    /// <remarks>
    /// Sorting is what makes this idempotent. Without a canonical order
    /// the preserved entry appends after A's own entries under A and after B's
    /// under B, so each project would rewrite the line the other just wrote.
    /// Order changes only on marked units.
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Doc.Document.TDocumenter.BuildForSymbol (DRagLint.Doc.Document.pas)</para>
    /// <para>Calls: Copy, DRagLint.Doc.SharedFacts.BlockHoldsUnvouchable, DRagLint.Doc.SharedFacts.FenceBounds, DRagLint.Doc.SharedFacts.IsTruncated, DRagLint.Doc.SharedFacts.LabelContent, DRagLint.Doc.SharedFacts.ParseBlock, DRagLint.Doc.SharedFacts.Participates, DRagLint.Doc.SharedFacts.ReconcileContent, DRagLint.Doc.SharedFacts.TSharedFacts.StoredBlockBody, EndsText, Pos, Trim, TrimRight</para>
    /// <para>Returns: ADocText; Lines.Text</para>
    /// <para>Complexity: 26 (cyclomatic, outer body), 154 lines (full implementation)</para>
    /// <seealso cref="DRagLint.Doc.SharedFacts.BlockHoldsUnvouchable"/>
    /// <seealso cref="DRagLint.Doc.SharedFacts.FenceBounds"/>
    /// <seealso cref="DRagLint.Doc.SharedFacts.IsTruncated"/>
    /// <seealso cref="DRagLint.Doc.SharedFacts.LabelContent"/>
    /// <seealso cref="DRagLint.Doc.SharedFacts.ParseBlock"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function MergeInboundFacts(const ADocText, AStoredRemarks: string;
      const AStore: ISymbolStore; const AUnitPath: string): string;

    /// <summary>True when the stored block holds inbound entries this project
    /// cannot see, so deleting or replacing it would destroy another project's
    /// contribution.</summary>
    /// <param name="AStoredBody"><!-- drag-lint:auto type -->const string</param>
    /// <param name="AStore">The current project's index. Not owned. Nil
    /// answers False.</param>
    /// <returns>True when an inbound line is a truncated `(+N more)` window, when
    /// an entry carries a project tag other than ProjectTag, or when an UNTAGGED
    /// entry names a unit this index cannot vouch for and is not flagged
    /// uncertain -- i.e. only when there is something here that ANOTHER project
    /// wrote. An entry tagged with this project alone is not foreign: it is this
    /// project's to reap.</returns>
    /// <remarks>
    /// Exists because a narrow project that compiles a shared unit but
    /// CALLS nothing in it renders an empty block, and both halves of this unit
    /// are downstream of decisions taken before they are consulted: the checker
    /// exits on the residual compare ('Pure' vs '') and the writer emits a pure
    /// tekDeleteLines. Both now ask this first.
    /// <!-- drag-lint:auto -->It cannot extract for itself, because its two callers hold different
    /// things: TDocumenter has the whole stored remarks, while BlockDrifted has already extracted a
    /// body. A StoredBlockBody call in here returns '' for the second one -- silently switching OFF
    /// the empty-render forgiveness, so a block naming a unit the index cannot see starts reporting
    /// drift. Caught by run_doc_drift_unseen_units (CASE-A) and run_doc_drift_extra_stores (#3).
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Doc.Document.TDocumenter.BuildForSymbol (DRagLint.Doc.Document.pas), DRagLint.Doc.SharedFacts.TSharedFacts.BlockDrifted (DRagLint.Doc.SharedFacts.pas)</para>
    /// <para>Calls: DRagLint.Doc.ProjectTags.SplitEntries, DRagLint.Doc.ProjectTags.SplitTagged, DRagLint.Doc.ProjectTags.WithoutTag, DRagLint.Doc.SharedFacts.IsTruncated, DRagLint.Doc.SharedFacts.IsUncertainEntry, DRagLint.Doc.SharedFacts.ParseBlock, DRagLint.Doc.SharedFacts.UnitVouchable</para>
    /// <para>Returns: False</para>
    /// <para>Complexity: 10 (cyclomatic, outer body), 52 lines (full implementation)</para>
    /// <seealso cref="DRagLint.Doc.ProjectTags.SplitEntries"/>
    /// <seealso cref="DRagLint.Doc.ProjectTags.SplitTagged"/>
    /// <seealso cref="DRagLint.Doc.ProjectTags.WithoutTag"/>
    /// <seealso cref="DRagLint.Doc.SharedFacts.IsTruncated"/>
    /// <seealso cref="DRagLint.Doc.SharedFacts.IsUncertainEntry"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function HoldsForeignInboundEntries(const AStoredBody: string;
      const AStore: ISymbolStore): Boolean;

    /// <summary>True when regenerating this block would DELETE stored fact
    /// content that this index cannot vouch for -- which makes the drift
    /// finding unsafe to advertise as an automatic repair.</summary>
    /// <param name="AStored">The managed block body as it stands in the source,
    /// flattened by the doc parser.</param>
    /// <param name="AFresh">The freshly rendered block this index would write in
    /// its place.</param>
    /// <param name="AStore">The current project's index. Not owned. Nil answers
    /// False: with no index there is nothing to vouch with, and the caller's
    /// existing behaviour stands.</param>
    /// <param name="AUnitPath"><!-- drag-lint:auto type -->const string</param>
    /// <returns>True to withhold the `fixable` flag.</returns>
    /// <remarks>
    /// <para>THIS ANSWERS "CAN I VOUCH FOR THE DELETION", NOT "IS THERE DRIFT".
    /// The finding is still reported either way; only the offer to fix it
    /// automatically is withdrawn. Reporting a real difference is always right.
    /// Deleting a true fact on the strength of an index that structurally
    /// cannot hold it is not.</para>
    /// <para>WHY A PROJECT INDEX CANNOT VOUCH. Under the one-DB-per-project
    /// layout a production project index is exactly the compile closure, so it
    /// can never hold a test caller. A block written when one database covered
    /// production AND tests therefore regenerates to a strict subset, for ever,
    /// with no code change involved.</para>
    /// <para>TWO SHAPES, MEASURED, and the second is the larger loss.
    /// `Called from:` / `Used by:` / `Used in units:` are NARROWED entry by
    /// entry. `Covered by:` is DELETED WHOLE -- it names tests by definition, so
    /// a closure index reproduces none of it, and it is not in INBOUND_LABELS,
    /// so the entry-level forgiveness never sees it. On DataCopy one such line
    /// named 41 tests and the regeneration proposed no line at all.</para>
    /// <para>DELIBERATELY CONSERVATIVE IN ONE DIRECTION ONLY. An entry whose
    /// unit IS in the closure and is genuinely gone stays fixable -- the index
    /// can vouch for that absence, and withholding it would disable the feature
    /// rather than protect it. That case is the positive control in
    /// run_doc_drift_unseen_units.ps1 and it is what stops this predicate from
    /// degenerating into "never fixable".</para>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Doc.Drift.TDocDrift.Analyze/4 (DRagLint.Doc.Drift.pas)</para>
    /// <para>Calls: DRagLint.Doc.ProjectTags.SplitEntries, DRagLint.Doc.SharedFacts.LabelContent, DRagLint.Doc.SharedFacts.ParseBlock, DRagLint.Doc.SharedFacts.Participates, DRagLint.Doc.SharedFacts.ReconcileDropsUnvouchable, DRagLint.Doc.SharedFacts.UnitVouchable, DRagLint.Lint.SharedUnit.TSharedUnit.IsShared, LowerCase, Trim</para>
    /// <para>Returns: False; ReconcileDropsUnvouchable(AStore, AStored, AFresh); True</para>
    /// <para>Complexity: 13 (cyclomatic, outer body), 93 lines (full implementation)</para>
    /// <seealso cref="DRagLint.Doc.ProjectTags.SplitEntries"/>
    /// <seealso cref="DRagLint.Doc.SharedFacts.LabelContent"/>
    /// <seealso cref="DRagLint.Doc.SharedFacts.ParseBlock"/>
    /// <seealso cref="DRagLint.Doc.SharedFacts.Participates"/>
    /// <seealso cref="DRagLint.Doc.SharedFacts.ReconcileDropsUnvouchable"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function RegenerationDropsUnvouchable(const AStored, AFresh: string;
      const AStore: ISymbolStore; const AUnitPath: string): Boolean;

    /// <summary>Orders one rendered inbound entry against another.</summary>
    /// <param name="X">A rendered entry, e.g. 'A.B.Foo (A.B.pas)'.</param>
    /// <param name="Y">The entry to compare it against.</param>
    /// <returns>&lt;0, 0 or &gt;0, as CompareText.</returns>
    /// <remarks>
    /// THE writer's order and THE merge's order must be one function.
    /// While the render joined in store order and the merge re-joined sorted,
    /// every type block was written once one way and once the other -- a
    /// one-time reorder of ~130 inbound lines in this repo that looked like
    /// non-determinism. Two comparators is the mirrored-predicate trap; there
    /// is deliberately only one, and both callers route through it.
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: [drag-lint]DRagLint.Doc.Regions.TDocRegions.RenderFactsBlock.JoinRefs (DRagLint.Doc.Regions.pas), [drag-lint]DRagLint.Doc.SharedFacts.ReconcileContent.SortedJoin (DRagLint.Doc.SharedFacts.pas)</para>
    /// <para>Calls: CompareText, DRagLint.Doc.ProjectTags.BareEntry</para>
    /// <para>Returns: CompareText(BareEntry(X), BareEntry(Y)); CompareText(X, Y)</para>
    /// <para>Directives: static</para>
    /// <seealso cref="DRagLint.Doc.ProjectTags.BareEntry"/>
    /// <seealso cref="DRagLint.Doc.SharedFacts.TSharedFacts.BlockDrifted"/>
    /// <seealso cref="DRagLint.Doc.SharedFacts.TSharedFacts.HoldsForeignInboundEntries"/>
    /// <seealso cref="DRagLint.Doc.SharedFacts.TSharedFacts.IsLegacyPureOnlyBody"/>
    /// <seealso cref="DRagLint.Doc.SharedFacts.TSharedFacts.LegacyPureViews"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function CompareInboundEntries(const X, Y: string): Integer; static;

    /// <summary>The engine-owned body of a STORED doc block: the text strictly
    /// between the BEGIN and END markers, or '' when there is no such pair.</summary>
    /// <param name="AText">Stored remarks, exactly as they appear in source.</param>
    /// <returns>The fenced body, or '' when the block has never been written.</returns>
    /// <remarks>
    /// Exposed because the CALLER must decide whether it holds whole
    /// remarks or an already-extracted body -- see HoldsForeignInboundEntries.
    /// Returning '' for unfenced text is the point, not an edge case: it is what
    /// stops a human's prose from being parsed as facts.
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: [drag-lint]DRagLint.Doc.Document.TDocumenter.BuildForSymbol (DRagLint.Doc.Document.pas), [drag-lint]DRagLint.Doc.Drift.TDocDrift.Analyze/4 (DRagLint.Doc.Drift.pas), [drag-lint]DRagLint.Doc.SharedFacts.TSharedFacts.MergeInboundFacts (DRagLint.Doc.SharedFacts.pas)</para>
    /// <para>Returns: DRagLint.Doc.SharedFacts.StoredBlockBody(AText)</para>
    /// <para>Directives: static</para>
    /// <seealso cref="DRagLint.Doc.SharedFacts.TSharedFacts.BlockDrifted"/>
    /// <seealso cref="DRagLint.Doc.SharedFacts.TSharedFacts.CompareInboundEntries"/>
    /// <seealso cref="DRagLint.Doc.SharedFacts.TSharedFacts.HoldsForeignInboundEntries"/>
    /// <seealso cref="DRagLint.Doc.SharedFacts.TSharedFacts.IsLegacyPureOnlyBody"/>
    /// <seealso cref="DRagLint.Doc.SharedFacts.TSharedFacts.LegacyPureViews"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function StoredBlockBody(const AText: string): string; static;

    /// <summary>True when a declaration's inbound lists (`Called from:`,
    /// `Used by:`, `Used in units:`) must be rendered WHOLE -- no
    /// `docs.max_callers` cap, no `(+N more)` window -- because its stored block
    /// takes part in cross-project reconciliation.</summary>
    /// <param name="AStoredBody">The stored managed block body (see
    /// StoredBlockBody); '' for a declaration with no block.</param>
    /// <param name="AStore">The current project's index. Not owned. Nil answers
    /// False.</param>
    /// <param name="AUnitPath">Absolute path of the declaring unit.</param>
    /// <returns>True for a unit marked `dl:shared`, a block that already carries
    /// project tags, or a block holding facts this index cannot vouch for.</returns>
    /// <remarks>
    /// THE WRITER AND THE CHECKER MUST BOTH ASK THIS, before building facts:
    /// reconciliation is a set operation and a window onto a list is not the
    /// list, so a capped render would make every merge unsound. Asking it in one
    /// place and not the other is the drift channel this unit exists to close.
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Doc.Document.TDocumenter.BuildForSymbol (DRagLint.Doc.Document.pas), DRagLint.Doc.Drift.TDocDrift.Analyze/4 (DRagLint.Doc.Drift.pas)</para>
    /// <para>Calls: DRagLint.Doc.SharedFacts.Participates</para>
    /// <para>Returns: Participates(AStore, AUnitPath, AStoredBody)</para>
    /// <seealso cref="DRagLint.Doc.SharedFacts.Participates"/>
    /// <seealso cref="DRagLint.Doc.SharedFacts.TSharedFacts.BlockDrifted"/>
    /// <seealso cref="DRagLint.Doc.SharedFacts.TSharedFacts.CompareInboundEntries"/>
    /// <seealso cref="DRagLint.Doc.SharedFacts.TSharedFacts.HoldsForeignInboundEntries"/>
    /// <seealso cref="DRagLint.Doc.SharedFacts.TSharedFacts.IsLegacyPureOnlyBody"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function WantsWholeInboundLists(const AStoredBody: string;
      const AStore: ISymbolStore; const AUnitPath: string): Boolean;

    /// <summary>The stored and fresh comment texts with the purity line taken
    /// out, for the writer's "is anything else different" test.</summary>
    /// <param name="AStored">The comment as it stands in the source.</param>
    /// <param name="AFresh">The comment the writer would put there.</param>
    /// <param name="AStoredView">AStored without its legacy `Pure` fact line.</param>
    /// <param name="AFreshView">AFresh without its `Effect-free (proven)` fact
    /// line.</param>
    /// <returns>False -- views undefined -- when MigrateLegacyPure is set or
    /// AStored carries no legacy `Pure` fact line inside its managed fence.</returns>
    /// <remarks>
    /// Purity v2 stopped emitting `Pure` and the owner deferred migrating
    /// the stored lines (they are to be regenerated ONCE, later). So a block
    /// whose only difference from a fresh render is that line -- relabelled or
    /// retracted -- is left byte-identical, and doc-drift agrees (BlockDrifted
    /// applies the same exemption). A block that differs in anything else is
    /// regenerated in full, and loses the legacy line with it.
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: [drag-lint]DRagLint.Doc.Document.SameButForLegacyPure (DRagLint.Doc.Document.pas)</para>
    /// <para>Calls: DRagLint.Doc.SharedFacts.WithoutFenceLine</para>
    /// <para>Returns: True</para>
    /// <para>Mutates: AStoredView (out), AFreshView (out)</para>
    /// <seealso cref="DRagLint.Doc.SharedFacts.WithoutFenceLine"/>
    /// <seealso cref="DRagLint.Doc.SharedFacts.TSharedFacts.BlockDrifted"/>
    /// <seealso cref="DRagLint.Doc.SharedFacts.TSharedFacts.CompareInboundEntries"/>
    /// <seealso cref="DRagLint.Doc.SharedFacts.TSharedFacts.HoldsForeignInboundEntries"/>
    /// <seealso cref="DRagLint.Doc.SharedFacts.TSharedFacts.IsLegacyPureOnlyBody"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function LegacyPureViews(const AStored, AFresh: string;
      out AStoredView, AFreshView: string): Boolean;

    /// <summary>True when a stored managed block body says nothing but the
    /// legacy `Pure` fact.</summary>
    /// <param name="AStoredBody">The stored managed block body.</param>
    /// <returns>False when MigrateLegacyPure is set.</returns>
    /// <remarks>
    /// The writer's empty-render branch asks this before it deletes a block:
    /// with the legacy line exempt, such a block is unchanged, not decayed.
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Doc.Document.TDocumenter.BuildForSymbol (DRagLint.Doc.Document.pas)</para>
    /// <para>Calls: DRagLint.Doc.SharedFacts.CollapseWs</para>
    /// <para>Returns: (not MigrateLegacyPure) and (CollapseWs(AStoredBody) = LEGACY_PURE_PARA)</para>
    /// <seealso cref="DRagLint.Doc.SharedFacts.CollapseWs"/>
    /// <seealso cref="DRagLint.Doc.SharedFacts.TSharedFacts.BlockDrifted"/>
    /// <seealso cref="DRagLint.Doc.SharedFacts.TSharedFacts.CompareInboundEntries"/>
    /// <seealso cref="DRagLint.Doc.SharedFacts.TSharedFacts.HoldsForeignInboundEntries"/>
    /// <seealso cref="DRagLint.Doc.SharedFacts.TSharedFacts.LegacyPureViews"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function IsLegacyPureOnlyBody(const AStoredBody: string): Boolean;

    /// <summary>The project name this run writes into inbound fact tags --
    /// `DataCopy` in `Called from: [DataCopy]uFoo.Bar (uFoo.pas)`.</summary>
    /// <remarks>
    /// Set once per process by the CLI from the primary database's base name
    /// (`_D-RAG\DataCopy.sqlite` gives `DataCopy`), and left EMPTY when more
    /// than one database is in play or no CLI ran (LSP, MCP): an empty name
    /// writes no new tag and removes none. Tags only ever appear in a block that
    /// takes part in reconciliation (see WantsWholeInboundLists); a private
    /// unit's blocks are unchanged. Process-wide and not thread-safe, like the
    /// closure cache.
    /// </remarks>
    class var ProjectTag: string;

    /// <summary>True lets `document --migrate-pure` regenerate a stored legacy
    /// `Pure` fact; False (the default) keeps such a block byte-identical when
    /// that line is its only difference.</summary>
    class var MigrateLegacyPure: Boolean;
  end;

implementation

uses
  System.SysUtils
  , System.Classes
  , System.StrUtils
  , System.IOUtils
  , System.Generics.Collections
  , System.Generics.Defaults
  , DRagLint.Doc.Regions
  , DRagLint.Doc.ProjectTags { SplitEntries, the [A,B]entry tag grammar, INBOUND_LABELS }
  , DRagLint.Lint.SharedUnit
  ;

const
  { INBOUND_LABELS -- the three labels whose entries depend on WHICH project is
    looking -- moved to DRagLint.Doc.ProjectTags with the tag grammar (2026-09-23),
    together with the history of why 'Used in units:' belongs in it. }

  { THE CONTRACT, stated exactly (review-task-1 I1, 2026-09-22): every PREFIXED
    label RenderFactsBlock and FormatPhase2FactLines can emit -- a label ending
    in ':' or '.', or a fixed word followed by a space -- plus the bare-word
    markers 'Recursive', 'UI thread only' and 'Effect-free (proven)'. It is NOT
    every label: the three bare-word markers 'abstract', 'virtual' and
    'constructor' are deliberately absent, see below, and 'Pure' is present but
    no longer EMITTED (purity v2, 2026-09-22 -- see its own note by the array).
    tests\autotest\
    run_autodoc_all_labels_covers_renderer.ps1 holds this list, that
    exemption list and that legacy list against Doc.Regions two-way and fails on
    any drift.

    WHAT THE LIST IS FOR. NextLabelPos/FactContentEnd use it to find where one
    fact ENDS inside stored text -- but ONLY for an UNWRAPPED fact. Since P8
    (2026-08-24) every fact the renderer emits is wrapped in its own <para>,
    ParseBlock/LabelContent slice BEFORE stripping that wrapper, and
    FactContentEnd bounds a fact that starts inside a <para> by the next '<'
    alone (InsidePara); this list is NOT consulted for such a fact (re-review
    N1, 2026-09-22 -- before that it WAS, and a bare word matching inside an
    entry's name cut a wrapped inbound list short, see FactContentEnd). The
    list decides the boundary only in a pre-P8 block (or a hand-written one)
    whose facts carry no wrapper; a missing entry there makes an inbound slice
    swallow the fact that follows -- which the residual compare reports as
    drift (fail-safe) and MergeInboundFacts feeds back as entries (not
    fail-safe: that was the v23 defect below).

    WHY THE THREE BARE WORDS STAY OUT. NextLabelPos is a raw PosEx, so on an
    UNWRAPPED block an entry here matches ANYWHERE in the text, entry names
    included: 'virtual' would terminate a fact at `Directives: virtual;
    overload` and 'constructor' at any caller named `...Constructor...`,
    cutting a real inbound list short -- and a short stored list is the one
    direction this unit must never fail in (a dropped entry is a caller only
    another project can see). Those markers only ever sit after 'Overrides:'/
    'Overridden by:'/'Implements:'/'Overload ' or at the end of the block,
    where the wrapper or the block end bounds them anyway. 'Pure',
    'Recursive', 'Deprecated.' and 'Overload ' carry that same substring
    hazard, and on an unwrapped block it is REAL (a caller named `TFoo.Pure`
    or a unit `uLeakPure` is cut there); they stay registered because they
    are the ONLY terminator an unwrapped block has for the fact before them.
    On a wrapped block none of this applies: the para bounds the fact. }
  { v22: 'Directives:' joins the list. Registering it is not optional bookkeeping
    -- this array is how a fact's text is bounded in the FLATTENED stored form,
    so an unregistered label makes the PRECEDING fact's slice swallow it, and the
    residual compare then reports drift on a block that is perfectly correct. }
  { gap 3: 'Catches:' joins the list, for the reason 'Directives:' did. }
  { v23 (INBOX-2026-09-17-autodoc-used-in-units-gains-class-names): 'Implemented
    by:'/'Extended by:' join the list, for the reason 'Directives:' did. Their
    absence here was the actual defect: RenderFactsBlock started emitting them
    for interfaces on 2026-09-16 (an interface's reverse edge), but nobody
    updated this array, so NextLabelPos could not find the boundary between an
    interface's 'Used in units:' line and the 'Implemented by:' line right
    after it. FactContentEnd then ran the 'Used in units:' slice on into the
    implementor class list, and MergeInboundFacts's accumulate-only
    reconciliation -- believing those class names were caller-visible units
    this project's index could not vouch for -- fed the plausible ones straight
    back into the freshly rendered 'Used in units:' line on every subsequent
    `document` run. Not a missing-drift-report this time: a UNIT list gaining
    CLASS names, and never converging. }
  { 2026-09-22 (review-task-1 I1): the six prefixed labels the v23 fix left
    out join the list -- 'Deprecated:', 'Deprecated.', 'Overrides:',
    'Overridden by:', 'Implements:', 'Overload ' (the 'Overload %d of %d' line,
    up to its first number). 'Overridden by:' was the live leak: a comma list
    of qualified names directly after 'Called from:' yielded `P.TC2.M` as a
    plausible entry no closure lacking unit P could vouch for, and
    MergeInboundFacts fed it back into 'Called from:' forever;
    `Deprecated: use X, Y` leaked the bare token `Y` in the own project.
    Pinned by run_autodoc_document_is_fixed_point.ps1's second fixture. }
  { purity v2 (2026-09-22): 'Effect-free (proven)' joins the list as the label
    the renderer now emits in the slot 'Pure' held, read from
    symbol_facts.effect_free instead of derived from five local facts.

    'Pure' STAYS REGISTERED, and it is the first entry here that is a LEGACY
    PARSE LABEL: the engine never writes it again, but every block already
    stored in every indexed corpus still carries it, and in an UNWRAPPED
    (pre-P8 or hand-written) block that word is the only terminator the fact
    ABOVE it has. De-registering it would make the preceding inbound slice
    swallow it -- the exact v22/v23 defect the rest of this array's history
    records. It costs nothing to keep: NextLabelPos only ever LOOKS for these,
    so an entry the renderer no longer produces can only ever bound something,
    never manufacture it.
    tests\autotest\run_autodoc_all_labels_covers_renderer.ps1 holds that split
    two-way -- 'Pure' must be registered and NOT emitted, 'Effect-free
    (proven)' must be both -- so neither half can rot silently. }
  ALL_LABELS: array[0..30] of string = (
    'Called from:', 'Used by:', 'Calls:', 'Returns:', 'Used in units:',
    'Complexity:', 'Owns returned:', 'Handles:', 'Catches:', 'SQL:', 'Covered by:',
    'Mutates:', 'Touches:', 'Transaction:', 'Registered as:', 'Dataset:',
    'Reads:', 'Writes:', 'Recursive', 'UI thread only', 'Pure',
    'Effect-free (proven)',
    'Directives:', 'Implemented by:', 'Extended by:',
    'Deprecated:', 'Deprecated.', 'Overrides:', 'Overridden by:', 'Implements:',
    'Overload ');

  MORE_MARK = '(+';
  UNCERTAIN_SUFFIX = ' ?';
  { A project tag set opens and closes an entry: `[A,B]X.Y (X.pas)`. }
  TAG_OPEN  = '[';
  { The purity fact purity v1 wrote and v2 no longer does, and the one v2 writes
    in its slot. Whole elements, because the renderer wraps every fact (P8). }
  LEGACY_PURE_PARA = '<para>Pure</para>';
  EFFECT_FREE_PARA = '<para>Effect-free (proven)</para>';
  { The doc-comment line prefix, stripped before a fence line is compared. }
  DOC_SLASHES = '///';
  { The per-fact wrapper the renderer has emitted since P8 (2026-08-24). }
  PARA_OPEN  = '<para>';
  PARA_CLOSE = '</para>';

  { Labels whose content is derived from OTHER units and which a compile-closure
    index therefore cannot reproduce at all -- as opposed to the inbound labels,
    which it reproduces PARTIALLY and which are screened entry by entry.

    `Covered by:` names tests. A production project index is exactly the compile
    closure, so it holds no test unit, so it renders no `Covered by:` line for
    any symbol, ever. The regeneration does not narrow the label; it deletes it.
    Measured on DataCopy 2026-09-02: a line naming 41 tests against a proposed
    text with no such line, on a finding marked [FIXABLE].

    Kept SEPARATE from INBOUND_LABELS on purpose. Adding it there would put it
    through ParseBlock's entry-level set difference, whose entries carry a
    `(file.pas)` part this label does not have -- the keys would not resolve and
    the screening would be nominal. Whole-label absence is the right test for a
    whole-label loss. }
  UNVOUCHABLE_LABELS: array[0..0] of string = ('Covered by:');

type
  TFactMap = TDictionary<string, string>;

var
  { Cache of the closure set, keyed on the store it was built from. Analyze runs
    once per documented decl and this is a whole-table read, so it is built once
    per run; a different store rebuilds rather than answering for the wrong
    project. Single-threaded by assumption, like the rest of the lint pass. }
  FClosureKey  : Pointer                   = nil;
  FClosureNames: TDictionary<string, Byte> = nil;


{ ---------------------------------------------------------------------------
  Small text helpers
  --------------------------------------------------------------------------- }

function CollapseWs(const S: string): string;
var
  Sb  : TStringBuilder;
  I   : Integer;
  Prev: Boolean;
begin
  Sb:= TStringBuilder.Create;
  try
    Prev:= False;
    for I:= 1 to Length(S) do
      if CharInSet(S[I], [' ', #9, #13, #10]) then
      begin
        if not Prev then Sb.Append(' ');
        Prev:= True;
      end
      else
      begin
        Sb.Append(S[I]);
        Prev:= False;
      end;
    Result:= Trim(Sb.ToString);
  finally
    Sb.Free;
  end;
end;

{ The text with every <para>/</para> wrapper removed. Applied to a RESIDUAL
  after the inbound facts have been sliced out of it (see ParseBlock) -- never
  to text that still has to be sliced, because the wrapper is what bounds a
  fact whose successor label the ALL_LABELS array does not know. }
function StripPara(const S: string): string;
begin
  Result:= S.Replace(PARA_OPEN, '').Replace(PARA_CLOSE, '');
end;

{ The managed block's body as it exists in ALREADY STORED text -- and '' when
  there is no BEGIN..END pair at all.

  IT REPLACED A FORGIVING TWIN. The previous ExtractBlockBody returned AText
  unchanged when there were no markers -- right for a freshly RENDERED block that
  has not been wrapped yet, and exactly wrong applied to STORED text, which was
  its only remaining caller: a declaration that has never been documented
  has no fence, so the whole of the human's remarks was handed to the fact
  parser, and a human's backticked MENTION of a label -- '(`Called from:`,
  `Used by:`)' -- was read as a fact and merged in as real entries. That reaches
  a FIXED POINT on the first apply and never heals, and it wrote three junk fact
  lines into this repo's own source in the b42a7e7 sweep.

  THE FENCE IS THE SCOPE. It is the same lexical-ownership rule AUTO_SUM /
  AUTO_TYPE / AUTO_EXC apply to tags: inside the markers is the engine's, outside
  is the human's, and a label outside them is prose. }
function StoredBlockBody(const AText: string): string;
var
  B, E: Integer;
begin
  Result:= '';
  B:= Pos(AUTO_BEGIN, AText);
  if B = 0 then Exit;
  Inc(B, Length(AUTO_BEGIN));
  E:= PosEx(AUTO_END, AText, B);
  if E = 0 then Exit;
  Result:= Copy(AText, B, E - B);
end;

{ Could this text BE the name of a caller in some other project?

  A foreign entry is preserved precisely because THIS index cannot check it, so
  the default is to keep it -- but that fail-safe only makes sense for text that
  could be a name at all. 'Used by: `' cannot be a caller in any project, in any
  language, ever; preserving it forever is not caution, it is a fixed point that
  never heals. Three such lines reached this repo's own committed source.

  DELIBERATELY A REJECTION TEST, NOT AN ACCEPTANCE TEST, and that asymmetry is
  the whole design. A wrong REJECT silently deletes a caller only another
  project can see, which nothing can recover; a wrong ACCEPT preserves one junk
  line, which the fence scoping already stops being created. So this asks only
  'could this be a name', and an acceptance whitelist was tried first and
  discarded: it spelled out the character set of a qualified name and thereby
  rejected the OVERLOAD form this repo renders in its own source --
  'DRagLint.Doc.Drift.TDocDrift.Analyze/4 (DRagLint.Doc.Drift.pas)'. Escaped
  generics ('TFoo&lt;T&gt;') would have been the next casualty.

  A name is therefore anything that STARTS like an identifier and contains no
  whitespace and no backtick. Every junk entry observed fails on the first
  character or on a space; every real entry passes. }
function PlausibleEntry(const AEntry: string): Boolean;
var
  S: string ;
  I: Integer;
  P: Integer;
begin
  Result:= False;
  S:= BareEntry(AEntry);
  if EndsText(UNCERTAIN_SUFFIX, S) then
    S:= TrimRight(Copy(S, 1, Length(S) - Length(UNCERTAIN_SUFFIX)));

  { drop the parenthesised location, which legitimately holds no spaces either }
  P:= LastDelimiter('(', S);
  if (P > 0) and (LastDelimiter(')', S) > P) then S:= TrimRight(Copy(S, 1, P - 1));

  if S = '' then Exit;
  if not CharInSet(S[1], ['A'..'Z', 'a'..'z', '_']) then Exit;
  for I:= 1 to Length(S) do
    if CharInSet(S[I], [#9, #10, #13, ' ', '`']) then Exit;
  Result:= True;
end;

{ The line indexes of the managed fence in ALines: the first line holding the
  BEGIN marker and the first line at or after it holding END, or -1 for either
  when absent.

  THE FENCE IS THE SCOPE, on the text being written as well as on the text
  already stored. Rewriting a line merely because it CONTAINS a label is what
  put a space inside a human's backticks -- '`Called from: `' -- when their
  prose only MENTIONED one. Outside the markers a label is text.

  Extracted rather than inlined because MergeInboundFacts is already at the
  cyclomatic and cognitive limits, and this scan pushed it over both (33/30 and
  67/65, measured). }
procedure FenceBounds(const ALines: TStrings; out ABeginAt, AEndAt: Integer);
var
  I: Integer;
begin
  ABeginAt:= -1;
  AEndAt  := -1;
  for I:= 0 to ALines.Count - 1 do
    if (ABeginAt < 0) and (Pos(AUTO_BEGIN, ALines[I]) > 0) then ABeginAt:= I
    else if (ABeginAt >= 0) and (AEndAt < 0) and (Pos(AUTO_END, ALines[I]) > 0) then AEndAt:= I;
end;

function IsTruncated(const AContent: string): Boolean;
begin
  Result:= Pos(MORE_MARK, AContent) > 0;
end;

function IsUncertainEntry(const AEntry: string): Boolean;
begin
  Result:= EndsText(UNCERTAIN_SUFFIX, TrimRight(AEntry));
end;

{ The identity of an entry for set purposes: its bare text without the ' ?'
  marker, lower-cased. Two spellings of one caller -- tagged or not, certain or
  not -- are one entry; the TEXT the writer keeps is decided separately. }
function EntryKey(const AEntry: string): string;
begin
  Result:= Trim(BareEntry(AEntry));
  if EndsText(UNCERTAIN_SUFFIX, Result) then
    Result:= TrimRight(Copy(Result, 1, Length(Result) - Length(UNCERTAIN_SUFFIX)));
  Result:= LowerCase(Result);
end;

{ Normalised full text, for multiset comparison: canonical tag order, lower-case. }
function EntryNorm(const AEntry: string): string;
var
  Tags: TArray<string>;
  Bare: string;
begin
  SplitTagged(AEntry, Tags, Bare);
  Result:= LowerCase(FormatTagged(Tags, Bare));
end;

function SameEntryMultiset(const A, B: TArray<string>): Boolean;
var
  NA, NB: TArray<string>;
  I     : Integer;
begin
  if Length(A) <> Length(B) then Exit(False);
  SetLength(NA, Length(A));
  SetLength(NB, Length(B));
  for I:= 0 to High(A) do NA[I]:= EntryNorm(A[I]);
  for I:= 0 to High(B) do NB[I]:= EntryNorm(B[I]);
  TArray.Sort<string>(NA);
  TArray.Sort<string>(NB);
  for I:= 0 to High(NA) do
    if NA[I] <> NB[I] then Exit(False);
  Result:= True;
end;

{ The unit an entry names. 'AOnly.CallFromA (AOnly.pas)' -> 'aonly';
  'DRagLint.CLI' (a Used-in-units entry, which has no parentheses) ->
  'draglint.cli'. Lowercased, extension dropped, so it can be matched against
  the closure set either way round. }
function EntryUnitKey(const AEntry: string): string;
var
  P, Q: Integer;
begin
  Result:= BareEntry(AEntry);
  if EndsText(UNCERTAIN_SUFFIX, Result) then
    Result:= TrimRight(Copy(Result, 1, Length(Result) - Length(UNCERTAIN_SUFFIX)));
  P:= LastDelimiter('(', Result);
  if P > 0 then
  begin
    Q:= LastDelimiter(')', Result);
    if Q > P then Result:= Copy(Result, P + 1, Q - P - 1);
  end;
  Result:= LowerCase(Trim(Result));
  if EndsText('.pas', Result) then Result:= Copy(Result, 1, Length(Result) - 4)
  else if EndsText('.dpr', Result) then Result:= Copy(Result, 1, Length(Result) - 4)
  else if EndsText('.dfm', Result) then Result:= Copy(Result, 1, Length(Result) - 4);
end;

{ ---------------------------------------------------------------------------
  The closure set
  --------------------------------------------------------------------------- }

{ Every unit this index holds, keyed by lowercased base name without extension.
  Cached because Analyze runs once per documented decl and this is a whole-table
  read; the cache is keyed on the store instance, so handing in a different store
  rebuilds rather than answering from the wrong project. }
function ClosureNames(const AStore: ISymbolStore): TDictionary<string, Byte>;
var
  Ids: TArray<Int64>;
  I  : Integer;
  Key: string;
begin
  if (FClosureNames <> nil) and (FClosureKey = Pointer(AStore)) then
    Exit(FClosureNames);

  FreeAndNil(FClosureNames);
  FClosureNames:= TDictionary<string, Byte>.Create;
  FClosureKey  := Pointer(AStore);

  Ids:= AStore.GetAllFileIds;
  for I:= 0 to High(Ids) do
  begin
    Key:= LowerCase(TPath.GetFileNameWithoutExtension(AStore.GetFilePath(Ids[I])));
    if Key <> '' then FClosureNames.AddOrSetValue(Key, 1);
  end;
  Result:= FClosureNames;
end;

function UnitInClosure(const AStore: ISymbolStore; const AEntry: string): Boolean;
var
  Key: string;
begin
  Key:= EntryUnitKey(AEntry);
  Result:= (Key = '') or ClosureNames(AStore).ContainsKey(Key);
end;

{ ---------------------------------------------------------------------------
  Parsing a block into facts
  --------------------------------------------------------------------------- }

{ The 1-based position of the next label at or after AFrom, or 0. }
function NextLabelPos(const AText: string; AFrom: Integer): Integer;
var
  I, P: Integer;
begin
  Result:= 0;
  for I:= Low(ALL_LABELS) to High(ALL_LABELS) do
  begin
    P:= PosEx(ALL_LABELS[I], AText, AFrom);
    if (P > 0) and ((Result = 0) or (P < Result)) then Result:= P;
  end;
end;

{ FactContentEnd (below InsidePara): where a fact's content ENDS. For an
  UNWRAPPED fact it is the earlier of the next label and the next tag; for a
  WRAPPED one (AFrom inside a <para>) it is the next tag ONLY -- see the N1 note
  on FactContentEnd itself. One past the end of AFlat when there is neither.

  For the unwrapped case BOTH terminators are required, and this is the third
  time this repo has had to
  promote a hand-expanded twin into a shared function. A fact's content is plain
  text: JoinRefs and JoinEsc escape every rendered entry, so a stored inbound
  line can carry '&lt;' but never a raw '<' outside a tag. A '<' after a label
  therefore ALWAYS begins the next element -- most often a <seealso .../>, which
  survives the <para> strip and is not in ALL_LABELS. Stopping only at the next
  label made a label followed by crefs run to the end of the block and swallow
  them, and the swallowed blob then read as an entry no index could vouch for.
  That one over-long slice was four filed defects: the growing
  `<para>Used in units: X, X <seealso/>...</para>`, a decayed type's facts block
  that could never be reaped, a phantom block the checker could not even see,
  and the one-time reordering of every inbound list. See
  tests\autodoc\run_doc_fact_terminator.ps1. }
{ True when position APos of AFlat lies inside a <para>...</para> element: the
  nearest wrapper tag before APos is an opening one. A fact sliced from such a
  position is WRAPPED and its own '</para>' is its terminator. }
function InsidePara(const AFlat: string; APos: Integer): Boolean;
var
  OpenAt, CloseAt, P: Integer;
begin
  OpenAt:= 0;
  P:= Pos(PARA_OPEN, AFlat);
  while (P > 0) and (P < APos) do
  begin
    OpenAt:= P;
    P:= PosEx(PARA_OPEN, AFlat, P + 1);
  end;
  CloseAt:= 0;
  P:= Pos(PARA_CLOSE, AFlat);
  while (P > 0) and (P < APos) do
  begin
    CloseAt:= P;
    P:= PosEx(PARA_CLOSE, AFlat, P + 1);
  end;
  Result:= (OpenAt > 0) and (OpenAt > CloseAt);
end;

{ Re-review N1 (2026-09-22): a WRAPPED fact -- AFrom inside a <para> -- is
  bounded by the next '<' ONLY, and the label list is not consulted for it.
  NextLabelPos is a raw substring search, so with the list in play a bare-word
  label matched INSIDE an entry's own name: the stored
  `<para>Called from: uLeakPure.TRecursiveHelper.Drive (uLeakPure.pas)</para>`
  was cut at `uLeak` (the 'Pure' in the unit name) before its own '</para>',
  and MergeInboundFacts fed `uLeak` back on every run. Every block the renderer
  has written since P8 is wrapped, so for those the list is irrelevant; it
  remains the terminator only for an UNWRAPPED (pre-P8 or hand-written) block,
  where nothing else marks where one fact ends. Pinned by
  run_autodoc_document_is_fixed_point.ps1's third fixture. }
function FactContentEnd(const AFlat: string; AFrom: Integer): Integer;
var
  TagAt: Integer;
begin
  if InsidePara(AFlat, AFrom) then Result:= 0
  else Result:= NextLabelPos(AFlat, AFrom);
  if Result = 0 then Result:= Length(AFlat) + 1;
  TagAt:= PosEx('<', AFlat, AFrom);
  if (TagAt > 0) and (TagAt < Result) then Result:= TagAt;
end;

{ Splits a block -- flattened or multi-line, both work -- into the three inbound
  facts plus a RESIDUAL holding everything else, collapsed. The residual is what
  keeps intrinsic facts on byte-compare semantics. }
procedure ParseBlock(const ABlock: string; out AInbound: TFactMap; out AResidual: string);
var
  Text  : string;
  Sb    : TStringBuilder;
  Pos1  : Integer;
  I, LP : Integer;
  Lab   : string;
  Stop  : Integer;
begin
  AInbound := TFactMap.Create;
  { v(P8, 2026-08-24): the <para> wrapper is PRESENTATION and must not reach the
    parse. Labels are located by position, not by line anchor, so a wrapped
    block still finds 'Called from:' -- but the fact's VALUE then carries a
    trailing '</para>' and the next one's leading '<para>'. The merged render
    differs from the stored text on every run, and `document` edits the same
    unit forever. Caught by run_shared_unit_staleness's idempotency check, which
    is the only assertion in the battery that exercises this merge path.

    2026-09-22 (review-task-1 I1): the wrapper is stripped AFTER slicing, not
    before. FactContentEnd stops at the next '<', so with the wrapper still in
    place every fact ends at its own '</para>' -- whatever label, or no label
    at all, follows it. Stripping first (what P8 did) threw that boundary away
    and left ALL_LABELS as the only terminator, so every label the array had
    not learned made the preceding inbound slice swallow the next fact
    ('Implemented by:' in v23, 'Overridden by:'/'Deprecated:' next). Re-review
    N1 (same day): for a wrapped fact FactContentEnd now stops at '<' ONLY --
    a registered bare word inside an entry's own name ('Pure' in `uLeakPure`)
    had still cut the fact before its '</para>'. The value never carries a
    tag either way: '<' ends it. The RESIDUAL is stripped once the inbound
    facts are out, so a wrapped and an unwrapped block still collapse to the
    same residual text and the byte compare is unchanged. }
  Text     := CollapseWs(ABlock);
  Sb       := TStringBuilder.Create;
  try
    Pos1:= 1;
    while Pos1 <= Length(Text) do
    begin
      LP:= 0;
      Lab:= '';
      for I:= Low(INBOUND_LABELS) to High(INBOUND_LABELS) do
      begin
        var P: Integer:= PosEx(INBOUND_LABELS[I], Text, Pos1);
        if (P > 0) and ((LP = 0) or (P < LP)) then
        begin
          LP := P;
          Lab:= INBOUND_LABELS[I];
        end;
      end;
      if LP = 0 then
      begin
        Sb.Append(Copy(Text, Pos1, MaxInt));
        Break;
      end;
      Sb.Append(Copy(Text, Pos1, LP - Pos1));
      Stop:= FactContentEnd(Text, LP + Length(Lab));
      AInbound.AddOrSetValue(Lab, Trim(Copy(Text, LP + Length(Lab), Stop - LP - Length(Lab))));
      Pos1:= Stop;
    end;
    AResidual:= CollapseWs(StripPara(Sb.ToString));
  finally
    Sb.Free;
  end;
end;

{ Declared here rather than moved: UnitVouchable and LabelContent live further
  down beside RegenerationDropsUnvouchable, which is where they were introduced,
  and the reconciliation below needs both. A forward declaration keeps the
  ordering legal without relocating working code. }
function UnitVouchable(const AStore: ISymbolStore; const AEntry: string): Boolean; forward;
function LabelContent(const AText, ALabel: string): string; forward;
function ParaLabelCount(const AText, ALabel: string): Integer; forward;

{ The raw block text with ALabel's whole <para> element removed.

  WHY THE RAW TEXT AND NOT THE COLLAPSED RESIDUAL, which is what this did first:
  the residual has already lost its <para> boundaries, so the end of a fact has
  to be GUESSED from the next label or the next tag -- and that guess turned out
  to be position-dependent. Measured: a `Covered by:` sitting LAST round-tripped
  cleanly while the identical label sitting BEFORE two <seealso> crefs did not.
  A rule that depends on where in the block a label happens to sit is not a rule.

  The raw text still carries the delimiters, so removing the element is exact,
  and the residual is then computed from text that never held the label at all.

  NO WRAPPER -> NO CHANGE, deliberately. A hand-written block with a bare
  `Covered by:` and no <para> is left alone, so the compare still fires and the
  finding is still reported. That is this unit's fail-safe direction: report,
  never hide. }
function WithoutParaLabel(const AText, ALabel: string): string;
var
  P, Open, Close: Integer;
begin
  Result:= AText;
  P     := Pos(ALabel, Result);
  if P = 0 then Exit;

  Open:= P;
  while (Open > 1) and (Copy(Result, Open, 6) <> '<para>') do Dec(Open);
  Close:= PosEx('</para>', Result, P);

  if (Copy(Result, Open, 6) = '<para>') and (Close > 0) then
    Delete(Result, Open, Close + Length('</para>') - Open);
end;

{ Does the stored block carry anything this index cannot vouch for -- an inbound
  entry naming a unit it does not hold, or a whole label it cannot produce? }
function BlockHoldsUnvouchable(const AStore: ISymbolStore; const ABlock: string): Boolean;
var
  SIn : TFactMap;
  SRes: string;
  Lab, SC, E: string;
  I   : Integer;
begin
  Result:= False;
  if (AStore = nil) or (ABlock = '') then Exit;

  for I:= Low(UNVOUCHABLE_LABELS) to High(UNVOUCHABLE_LABELS) do
    if LabelContent(ABlock, UNVOUCHABLE_LABELS[I]) <> '' then Exit(True);

  ParseBlock(ABlock, SIn, SRes);
  try
    for I:= Low(INBOUND_LABELS) to High(INBOUND_LABELS) do
    begin
      Lab:= INBOUND_LABELS[I];
      if not SIn.TryGetValue(Lab, SC) then Continue;
      { The window marker is not an entry. Split in as one, `X (+3 more)` read
        as naming a unit called '+3 more' that no index holds -- so every
        truncated block counted as evidence, and (since participation now
        renders lists whole) would have been rewritten uncapped for nothing. }
      for E in SplitEntries(WithoutMoreSuffix(SC)) do
        if (not UnitVouchable(AStore, E)) and (not IsUncertainEntry(E)) then Exit(True);
    end;
  finally
    SIn.Free;
  end;
end;

{ Does the stored block carry any project tag on an inbound entry? A tag is
  written only into a block that took part in reconciliation, so its presence
  IS the evidence -- the "shared" property derived from the block's own content,
  with nothing for anyone to remember to mark. }
function BlockCarriesTags(const ABlock: string): Boolean;
var
  SIn : TFactMap;
  SRes: string;
  SC  : string;
begin
  Result:= False;
  if Pos(TAG_OPEN, ABlock) = 0 then Exit;
  ParseBlock(ABlock, SIn, SRes);
  try
    for SC in SIn.Values do
      if AnyTagged(SplitEntries(SC)) then Exit(True);
  finally
    SIn.Free;
  end;
end;

{ ONE inbound label's content as the writer will leave it, given what is stored
  and what this project rendered. The checker compares the stored content with
  this; the writer writes it. One function, so the two cannot disagree.

  The rules, per entry (identity = EntryKey: bare text, no ' ?', any case):

    RENDERED by this project -> kept, with this project's tag added to whatever
      set the stored entry carried. The rendered text wins for the bare part.
    STORED ONLY, tagged      -> this project's tag removed if present; the entry
      goes when its set empties, and is otherwise kept as it stands. Another
      project's entry is never judged here.
    STORED ONLY, untagged    -> the legacy rule, unchanged: kept when it names a
      unit this index cannot vouch for (and is plausible and certain), dropped
      when this index CAN vouch for its absence.

  LAZY ADOPTION. An untagged stored entry this project renders is NOT tagged
  merely because tagging is possible: while the line carries no tag at all and
  nothing ELSE about it changes, the line is left as it stands. Only a line that changes for a real reason --
  an entry gained or lost, a tag set changed, a truncated window replaced --
  is written in full with this project's tags. Otherwise every shared block in
  every corpus would be rewritten, and doc-drift would flag it, on the first run
  of an engine that knows about tags: churn in untouched code, which the owner
  ruled against for the purity migration and which applies here for the same
  reason.

  A STORED `(+N more)` WINDOW is reconciled on its VISIBLE entries and the marker
  dropped. The entries it hid are not in the source anywhere, so nothing is lost
  that was recorded; before this, the whole line was replaced by the fresh
  render and the visible foreign entries went with it -- the `Called from:` loss
  measured on DataCopy (docs\INBOX-document-apply-drops-facts-outside-the-db.md).
  AFresh must be WHOLE (see TSharedFacts.WantsWholeInboundLists); the caller
  checks. }
function ReconcileContent(const AStore: ISymbolStore; const AStored, AFresh: string): string;
var
  Own       : string;
  StoredTags: TDictionary<string, TArray<string>>;
  StoredBare: TDictionary<string, string>;
  Order     : TList<string>;
  FreshKeys : TDictionary<string, Byte>;
  Lazy      : TList<string>;
  Eager     : TList<string>;
  SE        : TArray<string>;
  E, K, Bare: string;
  Tags, Old : TArray<string>;
  X         : string;
  Legacy    : Boolean;

  function SortedJoin(const L: TList<string>): string;
  var
    A: TArray<string>;
  begin
    A:= L.ToArray;
    TArray.Sort<string>(A, TComparer<string>.Construct(
      function(const P, Q: string): Integer
      begin
        Result:= TSharedFacts.CompareInboundEntries(P, Q);
      end));
    Result:= string.Join(', ', A);
  end;

begin
  Own       := TSharedFacts.ProjectTag;
  StoredTags:= TDictionary<string, TArray<string>>.Create;
  StoredBare:= TDictionary<string, string>.Create;
  Order     := TList<string>.Create;
  FreshKeys := TDictionary<string, Byte>.Create;
  Lazy      := TList<string>.Create;
  Eager     := TList<string>.Create;
  try
    SE:= SplitEntries(WithoutMoreSuffix(AStored));
    for E in SE do
    begin
      SplitTagged(E, Tags, Bare);
      K:= EntryKey(Bare);
      if StoredTags.TryGetValue(K, Old) then StoredTags[K]:= Old + Tags
      else
      begin
        StoredTags.Add(K, Tags);
        StoredBare.Add(K, Bare);
        Order.Add(K);
      end;
    end;

    for E in SplitEntries(AFresh) do
    begin
      Bare:= BareEntry(E);
      K   := EntryKey(Bare);
      if FreshKeys.ContainsKey(K) then Continue;
      FreshKeys.Add(K, 1);
      if not StoredTags.TryGetValue(K, Tags) then Tags:= nil;
      { An untagged stored entry keeps its untagged spelling in the lazy view. }
      Legacy:= StoredTags.ContainsKey(K) and (Length(Tags) = 0);
      if Own <> '' then Tags:= Tags + [Own];
      X:= FormatTagged(Tags, Bare);
      Eager.Add(X);
      if Legacy then Lazy.Add(Bare) else Lazy.Add(X);
    end;

    for K in Order do
    begin
      if FreshKeys.ContainsKey(K) then Continue;
      Tags:= StoredTags[K];
      Bare:= StoredBare[K];
      if Length(Tags) > 0 then
      begin
        if Own <> '' then Tags:= WithoutTag(Tags, Own);
        if Length(Tags) = 0 then Continue;
        X:= FormatTagged(Tags, Bare);
      end
      else if PlausibleEntry(Bare) and (not UnitVouchable(AStore, Bare)) and
              (not IsUncertainEntry(Bare)) then X:= Bare
      else Continue;
      Lazy.Add(X);
      Eager.Add(X);
    end;

    { Lazy only while the line is still wholly LEGACY. Once any project has
      tagged it the line is in the tagged regime, adopting costs no churn that
      has not already happened, and an entry left untagged there could never be
      reaped by the project that rendered it (run_doc_project_tags REAP). }
    if (not IsTruncated(AStored)) and (not AnyTagged(SE)) and
       SameEntryMultiset(Lazy.ToArray, SE) then
      Result:= SortedJoin(Lazy)
    else
      Result:= SortedJoin(Eager);
  finally
    Eager.Free;
    Lazy.Free;
    FreshKeys.Free;
    Order.Free;
    StoredBare.Free;
    StoredTags.Free;
  end;
end;

{ The pair with the legacy purity element taken out of the stored side and the
  v2 one out of the fresh side -- a no-op when MigrateLegacyPure is set or the
  stored text carries no legacy line. See BlockDrifted for the ruling. }
procedure WithoutLegacyPure(var AStored, AFresh: string);
begin
  if TSharedFacts.MigrateLegacyPure or (Pos(LEGACY_PURE_PARA, AStored) = 0) then Exit;
  AStored:= StringReplace(AStored, LEGACY_PURE_PARA, '', [rfReplaceAll]);
  AFresh := StringReplace(AFresh,  EFFECT_FREE_PARA, '', [rfReplaceAll]);
end;

{ Would the writer change this participating label? A stored window always
  changes (it is replaced by the reconciled whole list); otherwise compare the
  stored entries with ReconcileContent's, as a multiset -- order is not drift
  (owner ruling 2026-09-06), a tag set is. }
function ReconciledDrift(const AStore: ISymbolStore; const AStored, AFresh: string): Boolean;
begin
  Result:= IsTruncated(AStored) or
           not SameEntryMultiset(SplitEntries(ReconcileContent(AStore, AStored, AFresh)),
                                 SplitEntries(AStored));
end;

{ Does this unit take part in fact reconciliation at all?

  UNTIL 2026-09-02 THE ANSWER WAS "ONLY IF MARKED `dl:shared`", and that is what
  let DataCopy's 43 findings destroy true facts. The one-DB-per-project layout
  made every production project a compile closure, so a test caller became
  invisible to the project that owns the code -- without anybody marking
  anything, and with no way for a reader to know it had happened.

  Marking every such unit by hand is not an answer: the condition is a property
  of the INDEX LAYOUT, not of the unit, and it now applies to essentially every
  project with a sibling test project.

  So an unmarked unit participates too -- but ONLY ON EVIDENCE, never by
  default. The stored block must actually carry something this index cannot
  vouch for. That distinction is the whole design:

    * it keeps ordinary blocks on their existing semantics, so a stale entry
      whose unit IS indexed is still reported and still reaped -- no silent
      accumulation, and run_docdrift_fix_removal still passes;
    * it engages exactly where deletion would destroy information.

  A marked unit still participates unconditionally: it opted into the
  accumulate-only contract described at the top of this unit. }
function Participates(const AStore: ISymbolStore; const AUnitPath, ABlock: string): Boolean;
begin
  { v(2026-09-23, project tags): a block that already carries a tag took part
    before, and must keep doing so -- otherwise the first run after every entry
    became vouchable would fall back to the plain render and strip the tags. }
  Result:= (AStore <> nil) and
           (TSharedUnit.IsShared(AUnitPath) or BlockHoldsUnvouchable(AStore, ABlock) or
            BlockCarriesTags(ABlock));
end;

{ ---------------------------------------------------------------------------
  TSharedFacts
  --------------------------------------------------------------------------- }

class function TSharedFacts.BlockDrifted(const AStored, AFresh: string;
  const AStore: ISymbolStore; const AUnitPath: string): Boolean;
var
  SIn, FIn      : TFactMap;
  SRes, FRes    : string;
  Lab           : string;
  SC, FC        : string;
  SE, FE        : TArray<string>;
  FreshSet      : TDictionary<string, Byte>;
  StoredSet     : TDictionary<string, Byte>;
  E             : string;
  I             : Integer;
  StoredCmp     : string;
  FreshCmp      : string;
  IsShared      : Boolean;
begin
  { OWNER RULING 2026-09-06: "Order is not important. We should compare parts.
    I.e. all parts (lines) are there and not missing, then the Documentation is
    OK. If unit is used by several projects then the order might change and
    this is OK."

    So an INBOUND list is compared as a SET for EVERY unit, not only for one
    that opted into `dl:shared`. This routine already knew how -- the
    StoredSet/FreshSet comparison below has been doing exactly that for shared
    units since 2026-08-13 -- and the only thing that kept an ordinary unit on a
    whole-block byte compare was the early Exit that used to stand here.

    WHAT PROMPTED IT, measured 2026-09-06: `document --apply` rewrote
    TDocParamNote's block by SWAPPING TWO `Used by:` entries and changing
    nothing else. doc-drift then called the block stale and FIXABLE while
    `document --qname` said "up to date (no change)" -- the checker and the
    writer disagreeing about a block whose CONTENT was never wrong. Restoring
    the original order by hand cleared the finding, which is what proves the
    order was the whole of it.

    WHAT DOES NOT CHANGE, and must not:
      * the RESIDUAL (Calls:, Complexity:, everything that is not an inbound
        label) keeps byte-compare semantics -- order-insensitivity was ruled for
        used-by, and nothing about it makes a wrong Calls: line right;
      * an entry the FRESH render found and the source does not record is still
        drift, unconditionally, for every unit. That asymmetry is how a
        genuinely new caller gets written down;
      * the forgiveness for an entry the SOURCE records and this index cannot
        see stays gated on `dl:shared` participation. A unit that never opted in
        has no cross-project story, so a stored-only entry there is a stale
        entry, not a foreign one -- graded strictly, exactly as the byte compare
        graded it before. }
  IsShared:= Participates(AStore, AUnitPath, AStored);

  { THE LEGACY PURITY LINE IS NOT DRIFT ON ITS OWN (2026-09-23). Purity v2
    stopped emitting `Pure`; the owner deferred migrating the stored lines and
    will regenerate them ONCE. So the stored `Pure` element and the fresh
    `Effect-free (proven)` element are both taken out before any compare, and a
    block differing in nothing else is current. TDocumenter.BuildForSymbol makes
    the same exemption through LegacyPureViews, so the writer leaves exactly the
    blocks this calls current. `document --migrate-pure` turns both off. }
  StoredCmp:= AStored;
  FreshCmp := AFresh;
  WithoutLegacyPure(StoredCmp, FreshCmp);

  { A DUPLICATED INBOUND LABEL CANNOT BE SET-COMPARED, so it keeps the byte
    compare -- the fail-safe direction this unit's header requires ("if a block
    cannot be parsed confidently ... the answer is the byte compare").

    ParseBlock keys its map by LABEL, so a block carrying two `Called from:`
    <para> elements collapses to ONE entry set and the other simply disappears
    from the comparison. Under a whole-block byte compare that never mattered;
    under a set compare it means an entire injected line can go unreported.

    NOT hypothetical: run_doc_drift_unseen_units' CONTROL-1 plants exactly this
    shape -- a second `Called from:` para naming an in-scope ghost -- and it
    went green against the set compare until this guard was added. That control
    exists because the surrounding forgiveness rules are easy to widen into
    "reports nothing", and it caught this on the first battery. }
  for I:= Low(INBOUND_LABELS) to High(INBOUND_LABELS) do
    if (ParaLabelCount(StoredCmp, INBOUND_LABELS[I]) > 1) or
       (ParaLabelCount(FreshCmp,  INBOUND_LABELS[I]) > 1) then
      Exit(CollapseWs(StoredCmp) <> CollapseWs(FreshCmp));

  { TAKE OUT ANY LABEL THIS INDEX CANNOT PRODUCE, BEFORE THE PARSE.

    `Covered by:` is not an inbound label, so ParseBlock leaves it in the
    RESIDUAL -- and the residual is byte-compared. A compile-closure index
    renders no such line for any symbol, so stored-has / fresh-lacks is
    GUARANTEED, and the compare fired on every one of DataCopy's 42 blocks:
    drift that no code change caused and no repair could ever settle. Step 2a's
    inbound reconciliation could not reach it, because it never looked at the
    residual.

    Its absence from the fresh render is not evidence about the source; it is
    the same blind spot as an unseen caller. A label BOTH sides render is still
    compared normally, and every other residual fact is untouched. }
  if IsShared then
  for I:= Low(UNVOUCHABLE_LABELS) to High(UNVOUCHABLE_LABELS) do
    if (LabelContent(StoredCmp, UNVOUCHABLE_LABELS[I]) <> '') and
       (LabelContent(FreshCmp,  UNVOUCHABLE_LABELS[I]) =  '') then
      StoredCmp:= WithoutParaLabel(StoredCmp, UNVOUCHABLE_LABELS[I]);

  ParseBlock(StoredCmp, SIn, SRes);
  try
    ParseBlock(FreshCmp, FIn, FRes);
    try
      { v(2026-08-14): the fresh render produced NO managed block AT ALL -- this
        project compiles the unit but calls nothing in it. The residual compare
        below would then decide on 'Pure' vs '' and report drift on a block this
        project must not touch, which is the checker's half of the pure-deletion
        defect (the writer's half is guarded in TDocumenter). Only forgiven when
        the stored block carries entries that ONLY another project could have
        written; a block with nothing foreign in it is still graded normally. }
      if IsShared and (FRes = '') and (FIn.Count = 0) and (SIn.Count > 0)
         and HoldsForeignInboundEntries(AStored, AStore) then Exit(False);

      { Everything that is not an inbound fact keeps byte-compare semantics --
        nothing about sharing makes a wrong Calls: or Complexity: line right. }
      if SRes <> FRes then Exit(True);

      for I:= Low(INBOUND_LABELS) to High(INBOUND_LABELS) do
      begin
        Lab:= INBOUND_LABELS[I];
        if not SIn.TryGetValue(Lab, SC) then SC:= '';
        if not FIn.TryGetValue(Lab, FC) then FC:= '';
        if (SC = '') and (FC = '') then Continue;

        { v(2026-09-23): a PARTICIPATING block is compared against exactly what
          the writer will write -- ReconcileContent, the one function both use.
          The fresh render is whole here (WantsWholeInboundLists), so the
          window rule below no longer applies to it; a STORED window is drift
          because the writer replaces it with the reconciled whole list. A
          capped fresh line can still reach this point from a caller that did
          not ask for whole lists, and keeps the old rule. }
        if IsShared and not IsTruncated(FC) then
        begin
          if ReconciledDrift(AStore, SC, FC) then Exit(True);
          Continue;
        end;

        { A window onto the list is not the list. }
        if IsTruncated(SC) or IsTruncated(FC) then
        begin
          if SC <> FC then Exit(True);
          Continue;
        end;

        SE:= SplitEntries(SC);
        FE:= SplitEntries(FC);

        StoredSet:= TDictionary<string, Byte>.Create;
        FreshSet := TDictionary<string, Byte>.Create;
        try
          for E in SE do StoredSet.AddOrSetValue(LowerCase(E), 1);
          for E in FE do FreshSet .AddOrSetValue(LowerCase(E), 1);

          { An entry the fresh render found and the source does not record is
            ALWAYS drift: that is how a genuinely new caller gets written down. }
          for E in FE do
            if not StoredSet.ContainsKey(LowerCase(E)) then Exit(True);

          { An entry the source records and this project cannot see is forgiven
            only when it names a unit outside this closure and is not flagged
            uncertain. The '?' test is sound in ONE direction only -- JoinRefs
            emits the marker solely on a MIXED list, so its ABSENCE proves
            nothing -- which is why the closure test carries the decision. }
          for E in SE do
            if not FreshSet.ContainsKey(LowerCase(E)) then
            begin
              { A unit that never opted into `dl:shared` has no cross-project
                story, so a stored-only entry is a STALE entry, not a foreign
                one -- graded strictly, exactly as the byte compare graded it
                before the ruling generalised the set comparison. }
              if not IsShared then Exit(True);
              if UnitVouchable(AStore, E) or IsUncertainEntry(E) then Exit(True);
            end;
        finally
          FreshSet.Free;
          StoredSet.Free;
        end;
      end;

      Result:= False;
    finally
      FIn.Free;
    end;
  finally
    SIn.Free;
  end;
end;

{ TAKES THE BLOCK BODY, NOT THE WHOLE REMARKS -- the CALLER extracts.

  It cannot extract for itself, because its two callers hold different things:
  TDocumenter has the whole stored remarks, while BlockDrifted has already
  extracted a body. A StoredBlockBody call in here returns '' for the second
  one -- silently switching OFF the empty-render forgiveness, so a block naming
  a unit the index cannot see starts reporting drift. Caught by
  run_doc_drift_unseen_units (CASE-A) and run_doc_drift_extra_stores (#3). }
class function TSharedFacts.HoldsForeignInboundEntries(const AStoredBody: string;
  const AStore: ISymbolStore): Boolean;
var
  SIn : TFactMap;
  SRes: string  ;
  Lab : string  ;
  SC  : string  ;
  E   : string  ;
  I   : Integer ;
  Tags: TArray<string>;
  Bare: string  ;
begin
  Result:= False;
  { NO PARTICIPATION GATE, deliberately (2026-09-23). The gate used to be
    Participates, and an unmarked block with a truncated line passed it only
    because the `(+N more)` marker read as an unvouchable ENTRY. That marker is
    no longer an entry (WithoutMoreSuffix), so the gate would now shut out the
    truncated block this routine exists to protect. Without the gate the answer
    is unchanged everywhere else: a non-participating block by definition holds
    no tag and no certain unvouchable entry, so the loop answers False for it. }
  if AStore = nil then Exit;

  ParseBlock(AStoredBody, SIn, SRes);
  try
    for I:= Low(INBOUND_LABELS) to High(INBOUND_LABELS) do
    begin
      Lab:= INBOUND_LABELS[I];
      if not SIn.TryGetValue(Lab, SC) then Continue;
      if SC = '' then Continue;
      { A TRUNCATED line is deliberately treated as foreign-bearing. The window
        may hide an entry only another project can see, and the whole point here
        is to refuse to destroy what cannot be reasoned about. This is the
        opposite polarity to BlockDrifted's truncation guard and for the same
        reason: both fail toward PRESERVING the source. }
      if IsTruncated(SC) then Exit(True);
      for E in SplitEntries(SC) do
      begin
        { A tagged entry is foreign when ANOTHER project claims it. One carrying
          only this project's tag is this project's to reap -- that is the
          whole point of the tag. With no project name, every tag is foreign. }
        SplitTagged(E, Tags, Bare);
        if Length(Tags) > 0 then
        begin
          if Length(WithoutTag(Tags, ProjectTag)) > 0 then Exit(True);
          Continue;
        end;
        if (not UnitVouchable(AStore, E)) and (not IsUncertainEntry(E)) then Exit(True);
      end;
    end;
  finally
    SIn.Free;
  end;
end;

class function TSharedFacts.MergeInboundFacts(const ADocText, AStoredRemarks: string;
  const AStore: ISymbolStore; const AUnitPath: string): string;
var
  SIn       : TFactMap;
  SRes      : string;
  Lines     : TStringList;
  Handled   : TDictionary<string, Byte>;
  I, J, P   : Integer;
  Line, Body: string;
  Lab, SC   : string;
  Prefix    : string;
  Suffix    : string;   { the fact line's closing </para>, if P8 wrapped it }
  Changed   : Boolean;
  BeginAt   : Integer;
  EndAt     : Integer;
  LastAt    : Integer;
  FirstAt   : Integer;

  { The per-label merge is ReconcileContent -- the SAME function BlockDrifted
    compares against, so the writer cannot rewrite a block the checker just
    called current (incident five on this seam). }

begin
  Result:= ADocText;
  if (AStore = nil) or (AStoredRemarks = '') then Exit;
  if not Participates(AStore, AUnitPath, StoredBlockBody(AStoredRemarks)) then Exit;

  { PARSE THE BLOCK BODY, NOT THE WHOLE REMARKS. The remarks continue past
    AUTO_END, and ParseBlock ends a fact at the next LABEL -- so when the last
    fact in the block is an inbound one, its slice ran to the end of the remarks
    and swallowed the END marker into an entry. That wrote

        /// Used in units: ..., YadfMain, YadfMain <!-- drag-lint:auto END -->
        /// <!-- drag-lint:auto END -->

    into YADF.Tokens.pas on the first run against real code: a duplicated entry,
    a marker inside a fact line, and a doubled terminator. BlockDrifted never had
    the bug because its caller hands it ExtractManagedBlockBody's output already.
    The unit test missed it because every fixture block ended with 'Pure', which
    IS a label, so the slice stopped in time -- see the regression fixture whose
    block ends on the inbound line itself. }
  ParseBlock(StoredBlockBody(AStoredRemarks), SIn, SRes);
  try
    { A block may carry NOTHING but an unvouchable label -- a `Covered by:` with
      no inbound entries at all -- and that block still has something to
      preserve, so the inbound count alone cannot decide there is no work. }
    if (SIn.Count = 0) and
       (not BlockHoldsUnvouchable(AStore, StoredBlockBody(AStoredRemarks))) then Exit;

    Changed:= False;
    Lines  := TStringList.Create;
    Handled:= TDictionary<string, Byte>.Create;
    try
      Lines.Text:= ADocText;   { TStringList round-trips the trailing EOL state }
      FenceBounds(Lines, BeginAt, EndAt);
      { An EMPTY RANGE rather than a guarded loop: wrapping the loop in
        'if BeginAt >= 0' costs a nesting level, and this routine is at the
        deep-nesting limit. No fence -> FirstAt 0, LastAt -1 -> nothing runs. }
      if BeginAt >= 0 then FirstAt:= BeginAt + 1 else FirstAt:= 0;
      if EndAt >= 0 then LastAt:= EndAt - 1
      else if BeginAt >= 0 then LastAt:= Lines.Count - 1
      else LastAt:= -1;

      for I:= FirstAt to LastAt do
      begin
        Line:= Lines[I];

        for J:= Low(INBOUND_LABELS) to High(INBOUND_LABELS) do
        begin
          Lab:= INBOUND_LABELS[J];
          P  := Pos(Lab, Line);
          if P = 0 then Continue;
          Handled.AddOrSetValue(Lab, 1);
          if not SIn.TryGetValue(Lab, SC) then Break;

          Body  := Trim(Copy(Line, P + Length(Lab), MaxInt));
          Prefix:= Copy(Line, 1, P + Length(Lab) - 1);

          { v(P8, 2026-08-24): everything after the label is treated as the entry
            list, so a wrapped line handed '</para>' to SplitEntries as part of
            the last entry -- and the rebuilt line put the merged-in entry AFTER
            the closing tag:

              /// <para>Called from: A.CallFromA (A.pas)</para>, B.CallFromB (B.pas)

            which differs from the stored text on every run, so `document` edited
            the same unit forever. The closing tag is held aside and restored
            after the join; a line without one yields '' and is unaffected. }
          Suffix:= '';
          if EndsText('</para>', Body) then
          begin
            Suffix:= '</para>';
            Body  := TrimRight(Copy(Body, 1, Length(Body) - Length(Suffix)));
          end;

          { Never merge INTO a truncated fresh window. A STORED window is merged
            on its visible entries since 2026-09-23 -- see ReconcileContent; the
            caller renders whole lists for every block that gets this far. }
          if IsTruncated(Body) then Break;

          Lines[I]:= Prefix + ' ' + ReconcileContent(AStore, SC, Body) + Suffix;
          if Lines[I] <> Line then Changed:= True;
          Break;
        end;
      end;

      { A label the stored block carries and this project does not render AT ALL
        -- every caller of this symbol lives in another project. Without this the
        write drops the line outright and the other project re-adds it forever.
        It goes directly after the BEGIN marker because 'Called from:'/'Used by:'
        is the first line RenderFactsBlock emits. }
      if BeginAt >= 0 then
        for J:= Low(INBOUND_LABELS) to High(INBOUND_LABELS) do
        begin
          Lab:= INBOUND_LABELS[J];
          if Handled.ContainsKey(Lab) then Continue;
          if not SIn.TryGetValue(Lab, SC) then Continue;
          Body:= ReconcileContent(AStore, SC, '');
          if Body = '' then Continue;
          Prefix:= Copy(Lines[BeginAt], 1, Pos(AUTO_BEGIN, Lines[BeginAt]) - 1);
          Lines.Insert(BeginAt + 1, Prefix + Lab + ' ' + Body);
          Changed:= True;
        end;

      { CARRY OVER A LABEL THIS INDEX CANNOT PRODUCE AT ALL.

        The loop above only re-inserts INBOUND labels, which is where ParseBlock
        puts its three. `Covered by:` names TESTS, so a compile-closure index
        renders none of it for any symbol -- and it lives in the residual, so
        without this the write drops it outright. 23 such lines across 3 units in
        DataCopy, one of them naming 41 tests.

        Only when the fresh text does not already carry the label: a project that
        CAN see the tests renders its own, and that one wins. }
      if BeginAt >= 0 then
        for J:= Low(UNVOUCHABLE_LABELS) to High(UNVOUCHABLE_LABELS) do
        begin
          Lab:= UNVOUCHABLE_LABELS[J];
          SC := LabelContent(StoredBlockBody(AStoredRemarks), Lab);
          if SC = '' then Continue;
          if LabelContent(ADocText, Lab) <> '' then Continue;
          Prefix:= Copy(Lines[BeginAt], 1, Pos(AUTO_BEGIN, Lines[BeginAt]) - 1);
          Lines.Insert(BeginAt + 1, Prefix + '<para>' + Lab + ' ' + SC + '</para>');
          Changed:= True;
        end;

      if Changed then Result:= Lines.Text;
    finally
      Handled.Free;
      Lines.Free;
    end;
  finally
    SIn.Free;
  end;
end;

{ Can this index VOUCH for the unit an entry names -- i.e. does it hold that
  unit, so that the entry's absence from a fresh render is a fact rather than a
  blind spot?

  WHY NOT JUST UnitInClosure. That reads the unit out of the '(file.pas)' part
  and, when there is none, falls back to the WHOLE qualified name -- which can
  never match a file base name, so every parenthesis-less entry would read as
  unvouchable. Two real shapes have no file part: a hand-written
  `Called from: driftfixable.NoSuchCallerAnyMore` (the D4 fixture, whose unit IS
  indexed) and `Covered by: Test.Prod.TProdTests.Ping_works` (whose unit is NOT).
  Treating both the same way is wrong in opposite directions.

  So: try the parenthesised form first, then every DOTTED PREFIX of the name.
  Unit names in this codebase are themselves dotted (`Test.Prod`,
  `DRagLint.Doc.Facts`), so the prefix walk is what makes those resolvable at
  all; `Test.Prod` matches a `Test.Prod.pas` row, while a prefix of a test name
  matches nothing in a closure index -- which is exactly the distinction wanted. }
function UnitVouchable(const AStore: ISymbolStore; const AEntry: string): Boolean;
var
  Names: TDictionary<string, Byte>;
  S    : string;
  P, I : Integer;
begin
  if UnitInClosure(AStore, AEntry) then Exit(True);

  S:= BareEntry(AEntry);
  P:= Pos('(', S);

  { A '(file.pas)' part is BETTER EVIDENCE than any prefix guess, so when one is
    present the answer above is final. Letting the prefix walk run on anyway
    would let `Test.Prod.TProdTests.X (Test.Prod.pas)` vouch through a closure
    that merely holds `Test.pas` -- overriding an explicit, correct "not mine"
    with a coincidence, and permitting the very deletion this guards. }
  if P > 0 then Exit(False);
  if EndsText(UNCERTAIN_SUFFIX, S) then
    S:= TrimRight(Copy(S, 1, Length(S) - Length(UNCERTAIN_SUFFIX)));
  S:= LowerCase(Trim(S));

  Names:= ClosureNames(AStore);
  for I:= 1 to Length(S) do
    if S[I] = '.' then
      if Names.ContainsKey(Copy(S, 1, I - 1)) then Exit(True);

  Result:= False;
end;

{ How many times ALabel occurs in AText.

  EXISTS FOR ONE JOB: telling BlockDrifted that a block carries the SAME inbound
  label twice, which ParseBlock cannot represent -- its map is keyed by label, so
  the second <para> silently replaces or drops the first. A whole-block byte
  compare never cared; a SET compare would quietly stop seeing one of them.

  Deliberately counts the LABEL TEXT rather than parsing <para> elements: the
  stored block arrives flattened (the doc parser turns newlines into spaces), so
  element boundaries are exactly what is not reliable here. Over-counting is the
  safe direction anyway -- it costs a byte compare, which is this unit's
  documented fallback for anything it cannot read confidently. }
function ParaLabelCount(const AText, ALabel: string): Integer;
var P: Integer;
begin
  Result:= 0;
  if (AText = '') or (ALabel = '') then Exit;
  P:= Pos(ALabel, AText);
  while P > 0 do
  begin
    Inc(Result);
    P:= PosEx(ALabel, AText, P + Length(ALabel));
  end;
end;

{ The content a label carries in a flattened block, or '' when the label is
  absent. Slices with FactContentEnd, exactly as ParseBlock does, so a label
  sitting between two others -- or followed by crefs -- is not swallowed.

  This function carried the tag-stop clause privately for a while and ParseBlock
  did not, which is precisely how the two drifted apart. They now share it --
  including the 2026-09-22 rule that the <para> wrapper stays in the text
  until AFTER the slice, so the fact's own '</para>' bounds it (see ParseBlock). }
function LabelContent(const AText, ALabel: string): string;
var
  P, Stop: Integer;
  Flat   : string;
begin
  Result:= '';
  Flat  := CollapseWs(AText);
  P     := Pos(ALabel, Flat);
  if P = 0 then Exit;
  Stop:= FactContentEnd(Flat, P + Length(ALabel));
  Result:= Trim(Copy(Flat, P + Length(ALabel), Stop - P - Length(ALabel)));
end;

class function TSharedFacts.StoredBlockBody(const AText: string): string;
begin
  Result:= DRagLint.Doc.SharedFacts.StoredBlockBody(AText);
end;

class function TSharedFacts.WantsWholeInboundLists(const AStoredBody: string;
  const AStore: ISymbolStore; const AUnitPath: string): Boolean;
begin
  Result:= Participates(AStore, AUnitPath, AStoredBody);
end;

{ AText with every line inside a managed fence whose content -- after the `///`
  and surrounding blanks -- is exactly AElement removed. AFound says whether one
  was. Lines outside a fence are never touched: the fence is the scope. }
function WithoutFenceLine(const AText, AElement: string; out AFound: Boolean): string;
var
  Kept   : TList<string>;
  S, C   : string;
  InFence: Boolean;
begin
  AFound := False;
  InFence:= False;
  Kept   := TList<string>.Create;
  try
    for S in AText.Replace(#13#10, #10).Split([#10]) do
    begin
      if Pos(AUTO_BEGIN, S) > 0 then InFence:= True
      else if Pos(AUTO_END, S) > 0 then InFence:= False
      else if InFence then
      begin
        C:= Trim(S);
        if C.StartsWith(DOC_SLASHES) then C:= Trim(Copy(C, Length(DOC_SLASHES) + 1, MaxInt));
        if C = AElement then
        begin
          AFound:= True;
          Continue;
        end;
      end;
      Kept.Add(S);
    end;
    Result:= string.Join(#13#10, Kept.ToArray);
  finally
    Kept.Free;
  end;
end;

class function TSharedFacts.LegacyPureViews(const AStored, AFresh: string;
  out AStoredView, AFreshView: string): Boolean;
var
  Found, Ignored: Boolean;
begin
  AStoredView:= AStored;
  AFreshView := AFresh;
  if MigrateLegacyPure then Exit(False);
  AStoredView:= WithoutFenceLine(AStored, LEGACY_PURE_PARA, Found);
  if not Found then Exit(False);
  AFreshView:= WithoutFenceLine(AFresh, EFFECT_FREE_PARA, Ignored);
  Result:= True;
end;

class function TSharedFacts.IsLegacyPureOnlyBody(const AStoredBody: string): Boolean;
begin
  Result:= (not MigrateLegacyPure) and (CollapseWs(AStoredBody) = LEGACY_PURE_PARA);
end;

class function TSharedFacts.CompareInboundEntries(const X, Y: string): Integer;
begin
  { By the BARE entry first, so a tag never decides where a caller sits: the
    list reads alphabetically by name whoever claims each entry. For two
    untagged entries this is exactly the CompareText it always was. }
  Result:= CompareText(BareEntry(X), BareEntry(Y));
  if Result = 0 then Result:= CompareText(X, Y);
end;

{ For a block the writer MERGES: does the merge drop an UNTAGGED entry naming a
  unit this index cannot vouch for? That is the one deletion a merge can still
  make without evidence -- ReconcileContent does not keep an uncertain ' ?'
  entry it cannot see. A tagged entry dropped because this project removed its
  own tag is not counted: the tag is the vouching. A capped fresh line cannot be
  merged at all, so it answers True, the conservative direction. }
function ReconcileDropsUnvouchable(const AStore: ISymbolStore; const AStored, AFresh: string): Boolean;
var
  StoredIn, FreshIn: TFactMap;
  StoredRes, FreshRes: string;
  Lab       : string;
  SC, Fresh, E: string;
  Kept      : TDictionary<string, Byte>;
  Tags      : TArray<string>;
  Bare      : string;
begin
  Result:= False;
  ParseBlock(AStored, StoredIn, StoredRes);
  try
    ParseBlock(AFresh, FreshIn, FreshRes);
    Kept:= TDictionary<string, Byte>.Create;
    try
      for Lab in INBOUND_LABELS do
      begin
        if not StoredIn.TryGetValue(Lab, SC) then Continue;
        if not FreshIn.TryGetValue(Lab, Fresh) then Fresh:= '';
        if IsTruncated(Fresh) then Exit(True);
        Kept.Clear;
        for E in SplitEntries(ReconcileContent(AStore, SC, Fresh)) do Kept.AddOrSetValue(EntryKey(E), 1);
        for E in SplitEntries(WithoutMoreSuffix(SC)) do
        begin
          SplitTagged(E, Tags, Bare);
          if (Length(Tags) > 0) or Kept.ContainsKey(EntryKey(Bare)) then Continue;
          if not UnitVouchable(AStore, Bare) then Exit(True);
        end;
      end;
    finally
      Kept.Free;
      FreshIn.Free;
    end;
  finally
    StoredIn.Free;
  end;
end;

class function TSharedFacts.RegenerationDropsUnvouchable(const AStored, AFresh: string;
  const AStore: ISymbolStore; const AUnitPath: string): Boolean;
var
  SIn, FreshIn: TFactMap;
  SRes, FreshRes: string;
  Lab, SC, FreshContent, E: string;
  FreshSet: TDictionary<string, Byte>;
  I: Integer;
begin
  Result:= False;
  if AStore = nil then Exit;

  { A MARKED UNIT IS ALREADY SAFE, AND SAYING OTHERWISE BREAKS IT.

    On a dl:shared unit the WRITER merges: MergeInboundFacts keeps the inbound
    entries this index cannot see and adds the ones it can. So the regeneration
    does not drop them, and the repair is exactly the accumulation the feature
    exists to perform.

    This predicate compares the stored block against the FRESH RENDER, which is
    pre-merge and therefore narrow on any project that cannot see the other's
    callers. Reading that as a loss withdraws `fixable` from the one path that
    was already handling this correctly -- measured: it took the whole --fix arm
    of run_shared_unit_staleness red, on a project whose only job there is to
    ADD its own caller to a shared block.

    The unmarked case is the defect; the marked case is the cure. }
  if TSharedUnit.IsShared(AUnitPath) then Exit(False);

  { AN UNMARKED BLOCK THAT PARTICIPATES IS MERGED TOO (2026-09-23), so the
    question is what the MERGE drops, not what the fresh render lacks. }
  if Participates(AStore, AUnitPath, AStored) then
    Exit(ReconcileDropsUnvouchable(AStore, AStored, AFresh));

  { 1. A WHOLE LABEL this index cannot reproduce, present then gone. }
  for I:= Low(UNVOUCHABLE_LABELS) to High(UNVOUCHABLE_LABELS) do
    if (LabelContent(AStored, UNVOUCHABLE_LABELS[I]) <> '') and
       (LabelContent(AFresh,  UNVOUCHABLE_LABELS[I]) =  '') then
      Exit(True);

  { 2. Inbound labels, entry by entry. }
  ParseBlock(AStored, SIn, SRes);
  try
    ParseBlock(AFresh, FreshIn, FreshRes);
    try
      for I:= Low(INBOUND_LABELS) to High(INBOUND_LABELS) do
      begin
        Lab:= INBOUND_LABELS[I];
        if not SIn.TryGetValue(Lab, SC) then Continue;
        if Trim(SC) = '' then Continue;

        { TRUNCATION ALONE DOES NOT WITHHOLD, and an earlier draft that made it
          do so was a silent, unmeasured regression across every project.

          Inbound lists cap at docs.max_callers (5 by default), so ANY symbol
          with more than five callers renders a `(+N more)` window. Withholding
          on the window itself therefore took `fixable` away from most
          facts-block findings everywhere -- including the commonest and most
          harmless one, a new in-closure caller, where nothing is deleted at all.

          The window is a real limit on what can be known, but it is not
          evidence of loss. What withholds is evidence: a VISIBLE entry this
          index cannot vouch for, or a whole unvouchable label going missing.
          Both are tested below and neither is weakened by a cap.

          ACCEPTED RESIDUAL, stated rather than hidden: an entry hiding BEYOND
          the window on an unmarked unit is still reapable. It is the same
          window-unsoundness this unit's header documents, it is the behaviour
          that shipped before this predicate existed, and closing it needs the
          uncapped render that `dl:shared` units already get. }

        if not FreshIn.TryGetValue(Lab, FreshContent) then FreshContent:= '';

        FreshSet:= TDictionary<string, Byte>.Create;
        try
          for E in SplitEntries(FreshContent) do FreshSet.AddOrSetValue(LowerCase(Trim(E)), 1);
          for E in SplitEntries(SC) do
          begin
            if FreshSet.ContainsKey(LowerCase(Trim(E))) then Continue;
            { Dropped. Vouchable ONLY if this index actually holds the unit the
              entry names -- then its absence is a fact, not a blind spot. }
            if not UnitVouchable(AStore, E) then Exit(True);
          end;
        finally
          FreshSet.Free;
        end;
      end;
    finally
      FreshIn.Free;
    end;
  finally
    SIn.Free;
  end;
end;

initialization

finalization
  FreeAndNil(FClosureNames);

end.
