unit DRagLint.Doc.SymbolFacts;

// v(ADP3 T11-T14): FOUR MORE ANALYSES, and one rule that governs all of them.
//
//   Mutates      (T11, column mutates_params) -- the var/out PARAMETERS a
//                routine writes through. Closes the Phase-2 T4 gap, which
//                resolved against the owning class's FIELDS only, so a free
//                procedure that existed solely to fill an `out` parameter said
//                nothing at all. Parameter MODES come from TRoutineVarTable,
//                the one place that already parses var/out/const off a declArg.
//   UI affinity  (T12, column ui_affinity) -- identifiers whose declared type
//                is, or descends from, a curated VCL/DevExpress base type, plus
//                the curated globals Application/Screen.
//   Touches      (T13, column touches) -- external surfaces (file system /
//                registry / network) and transaction verbs, as CATEGORIES, not
//                call sites; the call site is already in 'Calls:'.
//   Wiring       (T14, column wiring, RESERVED) -- DI registrations and
//                dataset->relation links. A pure JOIN over already-indexed
//                tables, no AST at all, and computed at RENDER time like
//                ComputeCoveredBy -- see ComputeWiring's own header for why an
//                index-time value could only ever be empty or wrong.
//
// THE CURATED LISTS (UI_BASE_TYPES / UI_GLOBALS for T12, the TOUCH_* family for
// T13) ARE ENGINE KNOWLEDGE, NOT USER CONFIGURATION. They live here, beside the
// analysis that consumes them, and never in the manifest. The property that
// makes that safe is asymmetric and is the reason these facts are stated as
// POSITIVE FINDINGS ONLY: a STALE LIST UNDER-REPORTS -- the fact is simply
// omitted -- IT NEVER EMITS A FALSE CLAIM. Growing a list later is therefore
// always safe and never breaking. The corollary is binding on every consumer:
// an empty ui_affinity means "no UI touch was DETECTED", never "this routine is
// thread-safe", and nothing may render it as the latter.
//
// The T13 lists are additionally split BY MATCH SHAPE, not just by category
// (type receiver / bare intrinsic with arguments / dot member), because Reset
// and Commit are among the commonest method names in any Delphi codebase and a
// bare name match would manufacture a false claim on both. See the const block.
//
// Auto-Document Phase 2, Task 1: the analysis-facts layer. TSymbolFacts
// itself lives in DRagLint.Core.Model (so ISymbolStore.Get/PutSymbolFacts can
// reference it without a circular interface-uses -- see Core.Interfaces).
// This unit holds the record<->DB-column serialize helpers for symbol_facts'
// CSV TEXT columns (reads_fields, writes_fields, sql_reads, sql_writes,
// covered_by); Storage.SQLite stores/reads those columns verbatim as plain
// text, and callers (T2's analyzer, later renderers) use these helpers to
// move between a TArray<string> and that stored CSV form.
//
// Task 2 adds TSymbolFactsAnalyzer, the index-time entry point that produces
// one TSymbolFacts row per routine symbol. Its Analyze signature is final as
// of Task 2 -- Tasks 3-8 each fill in one group of fields inside the SAME
// function body (Cyclomatic/BodyLoc, ReadsFields/WritesFields, ReturnsOwner,
// DfmEvent, SqlReads/SqlWrites, CoveredBy respectively) without ever changing
// the signature, so the indexer's call site (DRagLint.Core.Indexer.IndexFile)
// is written once, here, and never touched again. This unit intentionally
// does NOT uses DRagLint.Core.Indexer: the Indexer uses THIS unit, so a
// back-reference would be a circular unit dependency.
//
// TASK 5 OVERRIDE (CoveredBy): unlike every other fact group listed above,
// CoveredBy is NOT filled by Analyze/the indexer -- Analyze never touches
// Result.CoveredBy, so symbol_facts.covered_by stays RESERVED/UNWRITTEN
// ('' as read back from storage, always). Covered-by is a REVERSE edge (a
// TEST calls the target), so index-time population would be ORDER-DEPENDENT/
// non-deterministic: if Foo.pas is indexed before FooTests.pas (the usual
// alphabetical order), the test->code call edge is not yet in call_edges
// when Foo's row is written, so CoveredBy comes out empty; index the other
// order and it is populated -- a real determinism violation the design's
// "same DB -> same facts" mandate cannot tolerate. Instead ComputeCoveredBy
// (below) computes it LAZILY at doc/hover RENDER time, exactly how Phase 1's
// 'Called from:' fact already works (DRagLint.Doc.Facts.TDocFactsBuilder.
// Build calls it directly, not through symbol_facts), which is always
// correct because it queries the full CURRENT call graph.
//
// IMPLEMENTATION NOTE -- NOT DRagLint.Report.RCallTree: the design brief
// suggested reusing TRCallTree's BuildReverseCallTree for the bounded reverse
// closure, but that walks ONLY AStore.FindResolvedCallers (certain call_edges
// rows). EMPIRICALLY CONFIRMED (a live RED/GREEN cycle against this Task's
// own fixtures) that this is NOT sufficient: DRagLint.Index.CallResolver's
// TCallResolver.TypeReceiver types every BARE (non-dotted) call site to the
// CALLING routine's OWN enclosing class/unit (kind 1: 'bare M / Self.M ->
// the enclosing routine's owning class') -- it never considers a target in a
// DIFFERENT unit. A DUnitX '[Test]'-style method calling a free-function (or
// another class's method) under test is exactly this bare-call shape, so
// that call NEVER gets a call_edges row, resolved or not -- it only ever
// surfaces via the NAME-based FindUnresolvedNameCallers bucket. A reverse
// walk built purely on FindResolvedCallers would therefore see the target's
// SAME-UNIT/SAME-CLASS callers only and silently miss essentially every real
// test caller. ComputeCoveredBy instead hand-rolls a bounded BFS that unions
// FindResolvedCallers + FindUnresolvedNameCallers at EVERY hop -- the exact
// two-bucket union DRagLint.Doc.Facts' own 'Called from:' gather already
// uses for the SAME reason -- per the task brief's own documented fallback
// ("if TRCallTree doesn't expose a bounded reverse walk cleanly, fall back
// to direct callers ... plus one or two manual reverse hops").
//
// Task 4 (ADP2) implements the ReadsFields/WritesFields group: a focused,
// single-pass AST walk (WalkFieldRW, implementation section) over the
// routine's OWN body -- deliberately NOT the shared TDataFlowSolver/
// IDataFlowAnalysis lattice machinery (DRagLint.Analysis.DataFlow/
// .Flow.Lattices) that Cyclomatic's neighboring CFG walk might suggest:
// field read/write is a bounded classification, not a fixpoint dataflow
// property. It DOES reuse DRagLint.Analysis.Flow.Lattices' TRoutineVarTable,
// purely to know which bare names are the routine's OWN locals/params/Result
// (so a same-named one SHADOWS an owning-class field, never misclassified as
// a read/write of it). See AnalyzeReadsWrites' header comment for the full
// field-set + classification ruleset (bare ':=' lhs / Inc-Dec first-arg =
// write; every other occurrence = read), and JoinCappedDisplay for the
// storage format -- already display-ready (', '-joined, capped at 8, a
// ' (+N more)' suffix when truncated), since these two columns have no
// companion *Total field to defer the cap decision to render time.
//
// Task 6 (ADP2) implements the DfmEvent group: which control/event a
// published method is wired to as a handler (e.g. 'Button1.OnClick'),
// mined from the .pas file's OWN paired .dfm sibling (ChangeFileExt(
// AFilePath, '.dfm')). Unlike ReturnsOwner/SqlReads/SqlWrites (still
// unimplemented placeholders as of this task) and UNLIKE Task 5's CoveredBy
// override above, DfmEvent IS filled by Analyze/stored in symbol_facts --
// the .dfm is a deterministic, same-file-pair sibling (no reverse-edge
// ordering problem the way a test->target call is), so index-time
// computation is safe and matches Cyclomatic/ReadsFields/WritesFields'
// discipline exactly (see the TASK 5 OVERRIDE comment above for the
// contrast). The existing 'event-binding' Reference DRagLint.Parser.DFM's
// WalkProperty already emits (consumed by DRagLint.Wiring's
// FindEventHandlersForForm) carries ONLY the handler's bare name -- it
// cannot answer "which object/property is THIS handler wired to" -- so this
// task adds a second, focused extractor (DRagLint.Parser.DFM.
// ExtractDfmEventBindings) that reuses the SAME WalkObject/WalkProperty tree
// walk but also threads the enclosing object's own name down to the
// property scan, yielding the full (ObjectName, EventProp, HandlerName)
// triple. See DfmEventMapFor's header comment (implementation section) for
// the per-.dfm memoization (mirrors TAstParseCache's per-file memoization,
// but deliberately a SINGLE-entry cache, not a growing dictionary -- see
// its own comment for why that is both sufficient and safe) and
// AnalyzeDfmEvent for how a routine's own Name is looked up against it.
//
// Task 7 (ADP2) implements the SqlReads/SqlWrites group: for a routine that
// builds a SQL statement via string literals (a common FireDAC/BDE pattern),
// which tables it READS (FROM/JOIN) vs. WRITES (INSERT INTO/UPDATE/DELETE
// FROM), mined purely from those literals. CONTROLLER CORRECTION to the
// original task brief: DRagLint.Parser.Sql is NOT reused here -- it is
// TFirebirdSqlParser, a DDL parser for *.sql SCHEMA-MIGRATION files (CREATE
// TABLE/PROCEDURE/TRIGGER/...); its own header comment states plainly that a
// trigger/procedure BODY is never parsed for INSERT/UPDATE/SELECT references
// in this repo's current version, so it has nothing a .pas routine's DML
// string could reuse. This task instead adds a small, NET-NEW, deliberately-
// NOT-a-SQL-parser extractor, entirely local to this unit: WalkSqlLiterals
// walks the SAME matched defProc/body node Cyclomatic/AnalyzeReadsWrites
// already found (no 2nd AST scan), finding each maximal string-literal
// CONCATENATION RUN exactly once; CollectConcatRun best-effort folds a run of
// adjacent '...' + '...' literals into one string, marking the WHOLE run
// DYNAMIC (dropped, never guessed at) the moment any operand is not itself a
// literal/'+'/parens; ClassifySqlText keeps only a run whose trimmed text
// starts with SELECT/INSERT/UPDATE/DELETE/WITH; ExtractSqlTables then runs a
// small, bounded, keyword-anchored scan for exactly the four clause shapes
// the task brief specifies (see its own header comment) -- deliberately NOT
// a SQL grammar: a subquery, a derived table, or a WITH's own CTE body
// contribute nothing, ever (absence over a wrong table). See
// AnalyzeSqlTables' header comment (this unit's implementation section, just
// above TSymbolFactsAnalyzer.Analyze) for the full pipeline and how the
// final CSVs are capped/deduped/sorted.
//
// Task 8 (ADP2) implements the ReturnsOwner group: does a function return a
// freshly-constructed object the caller must free ('new'), a borrowed
// reference ('borrowed'), or Self ('self') -- '' (never guessed) whenever
// there is ANY doubt. THE GOVERNING PRINCIPLE (per the task brief, the
// highest-stakes fact this phase adds): ABSENCE OVER A WRONG VERDICT -- a
// wrong 'new' tells a reader to Free the result; if it was actually
// borrowed, that is a double-free / freeing-what-you-do-not-own, a crash.
// So AnalyzeReturnsOwner (this unit's implementation section, just above
// TSymbolFactsAnalyzer.Analyze) emits a verdict ONLY when EVERY 'Result :='
// / 'Exit(<rhs>)' return site in the routine's OWN body -- collected by
// WalkReturnsOwnerSites, a single-pass walk over the SAME matched Proc/Body
// node Cyclomatic/AnalyzeReadsWrites/AnalyzeSqlTables already found, no 2nd
// AST scan -- unanimously classifies (ClassifyReturnSite) into the SAME one
// of {new, borrowed, self}; a single 'unknown' site (a call to another
// function, a local var, an index/deref expression, a with-block var, a
// ternary, ...) or ANY mix of categories omits the fact entirely, and so
// does a body that disposes of Result anywhere (Result.Free/DisposeOf/
// FreeAndNil(Result), detected by reusing DRagLint.Analysis.Flow.Lattices'
// DetectFreedVar -- the SAME '.Free'/'.DisposeOf'/'FreeAndNil' shape-matcher
// the double-free lattice (TFreedState) already relies on). 'new' is
// detected via that SAME unit's ExprIsConstructor (a 'T.Create'/'T.Create()'
// member-access call, reused as-is from the object-leak escape analysis
// (TEscape) this codebase already ships -- NOT reinvented here; it already
// handles BOTH the paren-less and parenthesized constructor-call shapes).
// 'borrowed' is a bare identifier resolving to a routine PARAMETER (any
// mode) or an OWN-CLASS field (the SAME FindAllChildSymbols(ASym.ParentId)
// field-name resolver AnalyzeReadsWrites, above, already builds) -- a LOCAL
// variable of the same name is explicitly NOT borrowed (Pascal scoping
// shadows the field, and the task brief names a local var as an 'unknown'
// example directly). 'self' is a bare 'Self' or 'Self as <Type>'. A
// 'borrowed'/'self' verdict is ADDITIONALLY gated (IsReferenceTypeName) on
// the function's OWN return type actually being a reference (class/
// interface) type -- else 'function Count: Integer; begin Result := FCount;
// end;' would nonsensically render 'borrowed' for a plain Integer; 'new'
// needs no such gate ('T.Create' already guarantees an object).
//
// GATE (function-shaped only): unlike every fact group above, this one is
// Kind-SENSITIVE (a procedure has nothing to return) -- but ASym.Kind ALONE
// cannot tell a function-method from a procedure-method: a CLASS method
// always carries Kind=skMethod regardless of the function/procedure keyword
// (confirmed by DRagLint.Doc.Document's own "class functions carry kind
// skMethod, not skFunction" comment, and by DRagLint.Parser.Delphi13.
// WalkDeclProc's unconditional 'if AAsMethod then Kind:= skMethod') -- so a
// literal 'ASym.Kind = skFunction' gate (the task brief's own literal
// wording) would silently exclude EVERY function declared as a class
// method, i.e. almost every real-world case, including this task's own
// fixture. AnalyzeReturnsOwner instead mirrors TDocFactsBuilder.Build's OWN
// Kind-agnostic approach: parse the return type straight from
// ASym.Signature (ParseReturnType, duplicated locally in this unit's
// implementation section -- Doc.Facts already `uses` THIS unit for
// ComputeCoveredBy, so the reverse direction would be a real circular unit
// dependency, the SAME reason FieldNodeStr/LastSegment above are duplicated
// rather than shared) -- '' for a procedure (whether Kind=skProcedure or a
// procedure declared as a method, Kind=skMethod) or a constructor/destructor
// (neither ever carries a ': Type' suffix in its signature), so the
// Kind-agnostic empty-check alone already excludes every non-function
// routine correctly; ASym.Kind in [skFunction, skMethod] is still checked
// FIRST as a cheap defensive pre-filter.
//
// FIX WAVE (Phase 2 T8 review, both EMPIRICALLY reproduced against the built
// exe): two gaps in the classification ruleset above, both tightening in the
// SAME safe direction this fact's own governing principle already demands
// (absence over a wrong verdict) -- neither touches the unanimity/site-
// collection machinery, only two of the per-site/per-type CLASSIFICATION
// checks:
//   Fix 1 -- 'new' no longer accepts ExprIsConstructor's verdict blindly.
//     ExprIsConstructor (DRagLint.Analysis.Flow.Lattices) matches PURELY on
//     the member-access text 'create', never the RECEIVER it is called ON,
//     so a plain instance method merely NAMED Create (e.g. a pool object's
//     own non-allocating 'function Create: TWidget' that just returns a
//     shared field) used to read back as 'new' from any caller doing
//     'Result := APool.Create;'. ClassifyReturnSite now additionally
//     requires the call's own receiver (ConstructorReceiverNode, below) to
//     pass ConstructorReceiverIsTypeName -- confidently a bare/qualified
//     TYPE reference, never a var/param/field/Self the routine already
//     holds an instance of -- see that function's own header comment for
//     the full rule and its accepted recall-narrowing tradeoff.
//   Fix 2 -- IsReferenceTypeName's tier-1 store-resolved loop now rejects a
//     resolved skRecord/skEnum OUTRIGHT (Exit(False)) instead of silently
//     falling through to the tier-2 T/I-prefix heuristic, which would
//     otherwise wrongly accept an indexed value-type record/enum whose name
//     happens to start with 'T'/'I' (e.g. 'TMyRec = record ... end;') as a
//     reference type, letting a record-returning getter render a nonsense
//     'borrowed'/'self' line.

interface

uses
  DRagLint.Core.Model
  , DRagLint.Core.Interfaces
  ;

/// <summary>Joins AItems into the CSV text form stored in one of
/// symbol_facts' TEXT columns (ReadsFields, WritesFields, SqlReads,
/// SqlWrites, CoveredBy). Returns '' for an empty array. No escaping is
/// applied: entries are Pascal identifiers / qualified names, which never
/// contain a comma.</summary>
/// <param name="AItems">Field/table/test qualified names, in display order.</param>
/// <returns><!-- drag-lint:auto -->string -- Observed: string.Join(',', AItems).</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.DoDocFactsSelfTest (DRagLint.CLI.pas)</para>
/// <para>Pure</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function SymbolFactsCsvJoin(const AItems: TArray<string>): string;

/// <summary>Splits a symbol_facts CSV TEXT column back into its entries.
/// Inverse of SymbolFactsCsvJoin. '' (or a blank/whitespace-only string)
/// yields an empty array (never a 1-element array holding '').</summary>
/// <param name="ACsv">A raw symbol_facts TEXT column value, e.g. as returned
/// by ISymbolStore.GetSymbolFacts.</param>
/// <returns><!-- drag-lint:auto -->TArray&lt;string&gt; -- Observed: SplitString(ACsv,
/// ',').</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Calls: SplitString, Trim</para>
/// <para>Pure</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function SymbolFactsCsvSplit(const ACsv: string): TArray<string>;

/// <summary>LAZILY computes the 'Covered by:' fact for ASym at DOC/HOVER
/// RENDER time -- Phase 2 Task 5's CONTROLLER OVERRIDE to the index-time
/// brief (see this unit's banner comment, "TASK 5 OVERRIDE", for why a
/// reverse test-&gt;target edge cannot be filled deterministically at index
/// time). NEVER called from TSymbolFactsAnalyzer.Analyze; symbol_facts.
/// covered_by stays unwritten/reserved. Shared by DRagLint.Doc.Facts'
/// TDocFactsBuilder.Build and (Phase 2 Task 9) the hover renderer, so both
/// surfaces agree on the same fact.</summary>
/// <param name="AStore">Open symbol store to query; not owned.</param>
/// <param name="ASym">The routine whose test coverage is being reported.
/// Non-routine kinds (types/fields/consts/units/...) always yield ''.</param>
/// <returns>Already DISPLAY-READY (', '-joined, capped at COVERED_BY_CAP
/// entries, a ' (+N more)' suffix when truncated -- the SAME passthrough
/// contract as ReadsFields/WritesFields, see JoinCappedDisplay) CSV of
/// qualified TEST-method names that call ASym, directly or transitively
/// within COVERED_BY_DEPTH reverse call-graph hops. Walked via a bounded,
/// hand-rolled BFS over ISymbolStore.FindResolvedCallers +
/// FindUnresolvedNameCallers (NOT DRagLint.Report.RCallTree -- see this
/// unit's banner "IMPLEMENTATION NOTE" for the empirically-confirmed reason
/// a resolved-only reverse tree misses the realistic DUnitX case). '' when
/// ASym.Id &lt;= 0, ASym is not routine-like, or no caller (at any hop) is
/// detected as a test -- see IsTestRoutine for the two detection rules.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Doc.Facts.TDocFactsBuilder.Build (DRagLint.Doc.Facts.pas)</para>
/// <para>Calls: DRagLint.Core.Interfaces.ISymbolStore.HasTestRoutineMarkers, DRagLint.Core.Model.CanBeCallTarget, DRagLint.Doc.SymbolFacts.ComputeCoveredBy.Walk, DRagLint.Doc.SymbolFacts.JoinCappedDisplay, IsTestRoutine, LastSegment</para>
/// <para>Returns: ''; JoinCappedDisplay(Capped, COVERED_BY_CAP)</para>
/// <para>Pure</para>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.HasTestRoutineMarkers"/>
/// <seealso cref="DRagLint.Core.Model.CanBeCallTarget"/>
/// <seealso cref="DRagLint.Doc.SymbolFacts.ComputeCoveredBy.Walk"/>
/// <seealso cref="DRagLint.Doc.SymbolFacts.JoinCappedDisplay"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ComputeCoveredBy(const AStore: ISymbolStore; const ASym: TSymbol): string;

/// <summary>v(ADP3 T14): the DI/ORM wiring string for ASym -- '; '-joined
/// entries, each &lt;c&gt;di:&lt;interface&gt; (&lt;lifetime&gt;)&lt;/c&gt; or
/// &lt;c&gt;ds:&lt;symbol&gt; -&gt; &lt;RELATION&gt; (&lt;COL&gt;, &lt;COL&gt;)&lt;/c&gt;. '' when the
/// symbol is neither registered nor linked.</summary>
/// <param name="AStore">Open symbol store; not owned. Must not be nil.</param>
/// <param name="ASym">The symbol to describe. A method is wired through its
/// owning class, so ASym.ParentId is followed for the DI lookup.</param>
/// <returns>The stored wire string, or ''.</returns>
/// <remarks>
/// A pure JOIN over already-indexed tables -- no AST analysis at all,
/// so a failed parse cannot suppress it. CONTROLLER OVERRIDE, computed lazily
/// at render time like ComputeCoveredBy and for the same class of reason:
/// orm_links is written by a separate post-index pass, so an index-time column
/// would be empty on every first index and stale-by-dead-id afterwards. See the
/// implementation's own header for the full argument.
/// <!-- drag-lint:auto -->COMPUTED AT RENDER TIME, NOT INDEX TIME -- a deliberate deviation from
/// the plan, and the SECOND fact to need it after ADP2 T5's CoveredBy, for the same class of
/// reason: the data does not exist yet when the facts loop runs. * orm_links is written by a
/// SEPARATE pass (DRagLint.Sql.OrmLinker, the `orm-link` command), which starts with `DELETE FROM
/// orm_links` and rebuilds. It is not part of `index` at all. An index-time wiring column would
/// therefore be EMPTY on every first index, and could only pick the links up on a later reindex --
/// which re-inserts the Delphi symbols with NEW ids, leaving the orm_links rows (whose
/// delphi_symbol_id has no FK and so is never cascaded) pointing at symbols that no longer exist.
/// The fact would be reliably wrong rather than occasionally stale. * di_bindings IS written during
/// the same index pass, so that half could have been index-time; splitting one fact across two
/// computation times to save one query would be a worse trade than the query. symbol_facts.wiring
/// therefore stays UNWRITTEN/RESERVED, exactly as symbol_facts.covered_by does -- see
/// TDocFacts.CoveredBy's own field comment.
///
/// A METHOD IS WIRED THROUGH ITS CLASS. `Registered as:` is a property of the registered type, so
/// for a method the lookup uses the owning class's name (ASym.ParentId); for a class symbol it uses
/// its own. The dataset link is looked up for both the symbol and its parent, since orm-link may
/// attach either.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Doc.Facts.TDocFactsBuilder.Build (DRagLint.Doc.Facts.pas)</para>
/// <para>Calls: DRagLint.Core.Interfaces.ISymbolStore.FindDiBindingsForImpl, DRagLint.Core.Interfaces.ISymbolStore.GetSymbolById, DRagLint.Doc.SymbolFacts.ComputeWiring.AddDatasetLinks, Format, Trim</para>
/// <para>Returns: ''; string.Join('; ', Entries.ToStringArray)</para>
/// <para>Complexity: 11 (cyclomatic, outer body), 71 lines (full implementation)</para>
/// <para>Pure</para>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindDiBindingsForImpl"/>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetSymbolById"/>
/// <seealso cref="DRagLint.Doc.SymbolFacts.ComputeWiring.AddDatasetLinks"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ComputeWiring(const AStore: ISymbolStore; const ASym: TSymbol): string;

type
  /// <summary>Index-time analyzer that derives a TSymbolFacts row for one
  /// routine symbol -- the single call site the indexer uses for every fact
  /// group Phase 2 will ever add (see the unit banner comment).</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.Core.Indexer.TIndexer.IndexFile (DRagLint.Core.Indexer.pas)</para>
  /// <para>Used in units: DRagLint.Core.Indexer</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TSymbolFactsAnalyzer = class
    public
      /// <summary>Analyzes ASym's body and returns the TSymbolFacts row to
      /// persist for it. Task 2 returned an EMPTY-but-Present record; Task 3
      /// (ADP2) filled in Cyclomatic/BodyLoc; Task 4 (ADP2) fills in
      /// ReadsFields/WritesFields (see below); Task 6 (ADP2) fills in
      /// DfmEvent (see below); Tasks 7-8 populate the remaining groups one
      /// at a time. Never returns Present=False (the indexer only calls
      /// this for a symbol it is about to write a row for).</summary>
      /// <param name="ASym">The routine symbol being analyzed. ADP2 T4 fix
      /// wave: the caller (the indexer's facts loop) now resolves ASym's real
      /// identity BEFORE calling Analyze -- Id/FileId are the just-inserted DB
      /// values and ParentId is already translated to the real owning
      /// symbol's id (or -1 for a free routine / unresolved parent), never a
      /// pre-insert in-array index or placeholder. Result.SymbolId is seeded
      /// from ASym.Id and the caller still overwrites it with the same
      /// just-inserted DB id afterward, defensively.</param>
      /// <param name="AFilePath">Path to ASym's source file (ADP2 T3) -- the
      /// indexer's own IndexFile parameter, passed through unchanged. Needed
      /// because the indexer's TParseResult carries no tree-sitter tree (only
      /// extracted symbols/refs); this is how Analyze reaches the AST (via
      /// TAstParseCache.Get, memoized per file) for Cyclomatic.</param>
      /// <param name="ABody">The routine's implementation body, one source
      /// line per array entry (ASym.ImplStartLine..ImplEndLine, 1-based),
      /// already bounds-clipped by the caller. Unused by Task 3 (BodyLoc is
      /// pure symbol-range arithmetic, not a text scan); a later fact group
      /// may use it.</param>
      /// <param name="AStore">Read-only access to the rest of the index, for
      /// facts that need a cross-symbol lookup (e.g. DFM event bindings, SQL
      /// table references). Unused by Task 3.</param>
      /// <returns>A TSymbolFacts record with Present=True.</returns>
      /// <remarks>
      /// ADP2 T3: Cyclomatic is 0 when no defProc in AFilePath's tree
      /// starts at ASym.ImplStartLine (e.g. AFilePath unreadable/unparseable) --
      /// absence over a wrong number, never fabricated. BodyLoc is always
      /// ImplEndLine - ImplStartLine (clamped to >= 0), independent of the AST.
      /// ADP2 T4: ReadsFields/WritesFields are '' under the SAME no-defProc
      /// condition, plus whenever ASym has no owning class or that owning
      /// class has no field children -- see AnalyzeReadsWrites' header
      /// comment (this unit's implementation section) for the full field-set
      /// + read/write classification rules. ADP2 T6: DfmEvent is '' whenever
      /// ASym has no owning class (a free routine can never be a DFM event
      /// handler), the paired .dfm (ChangeFileExt(AFilePath, '.dfm')) does
      /// not exist on disk (most units are not forms), or no On*-property in
      /// that .dfm is wired to ASym.Name -- see AnalyzeDfmEvent/
      /// DfmEventMapFor (this unit's implementation section) for the
      /// memoized per-.dfm parse and the first-wiring-wins tie-break
      /// rule. ADP2 T7: SqlReads/SqlWrites are '' under the SAME no-defProc
      /// condition, plus whenever the routine builds no string that looks
      /// like SQL, or every SQL-shaped literal run it builds turns out to be
      /// dynamically assembled (a non-literal operand inside a '+'
      /// concatenation) -- see AnalyzeSqlTables/WalkSqlLiterals/
      /// ExtractSqlTables (this unit's implementation section) for the full
      /// extraction pipeline; DRagLint.Parser.Sql is deliberately NOT reused
      /// (Firebird DDL over *.sql files only -- it never parses a routine
      /// body). ADP2 T8: ReturnsOwner is '' under the SAME no-defProc
      /// condition, plus whenever ASym is not function-shaped (a procedure,
      /// constructor, or destructor -- see AnalyzeReturnsOwner's own header
      /// comment for why this is decided from the parsed return type, not
      /// ASym.Kind alone), the body has no 'Result :='/'Exit(&lt;rhs&gt;)'
      /// site at all, Result is disposed anywhere in the body (Result.Free/
      /// DisposeOf/FreeAndNil(Result)), any site's RHS is not confidently
      /// one of {new, borrowed, self}, or the sites disagree with each other
      /// -- ABSENCE OVER A WRONG VERDICT, this fact's own governing
      /// principle (a wrong 'new' invites a double-free) -- see
      /// AnalyzeReturnsOwner/WalkReturnsOwnerSites/ClassifyReturnSite (this
      /// unit's implementation section) for the full site-collection +
      /// unanimity + object-type-gate ruleset.
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.Core.Indexer.TIndexer.IndexFile (DRagLint.Core.Indexer.pas)</para>
      /// <para>Calls: Default, DRagLint.Diagnostics.AstChecks.TAstChecker.CyclomaticOf, DRagLint.Diagnostics.ParseCache.TAstParseCache.Get, DRagLint.Doc.SymbolFacts.AnalyzeDfmEvent, DRagLint.Doc.SymbolFacts.AnalyzeMutatesParams, DRagLint.Doc.SymbolFacts.AnalyzeReadsWrites, DRagLint.Doc.SymbolFacts.AnalyzeReturnsOwner, DRagLint.Doc.SymbolFacts.AnalyzeSqlTables, DRagLint.Doc.SymbolFacts.AnalyzeTouches, DRagLint.Doc.SymbolFacts.AnalyzeUiAffinity, DRagLint.Doc.SymbolFacts.ProcsForFile, Integer</para>
      /// <para>Returns: Default(TSymbolFacts)</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Diagnostics.AstChecks.TAstChecker.CyclomaticOf"/>
      /// <seealso cref="DRagLint.Diagnostics.ParseCache.TAstParseCache.Get"/>
      /// <seealso cref="DRagLint.Doc.SymbolFacts.AnalyzeDfmEvent"/>
      /// <seealso cref="DRagLint.Doc.SymbolFacts.AnalyzeMutatesParams"/>
      /// <seealso cref="DRagLint.Doc.SymbolFacts.AnalyzeReadsWrites"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function Analyze(const ASym: TSymbol; const AFilePath: string; const ABody: TArray<string>; const AStore: ISymbolStore): TSymbolFacts; static;
  end;

implementation

uses
  System.SysUtils
  , System.StrUtils
  , System.IOUtils                    { ADP2 T6: TFile.Exists/ReadAllBytes -- the paired .dfm sibling read }
  , System.Classes                    { ADP2 T5: TStringList for the sorted/deduped test-name set }
  , System.Generics.Collections       { ADP2 T4: TDictionary/TList for the field-name set + ordered read/write lists }
  , TreeSitter                        { ADP2 T3: TTSNode for the AST-derived Cyclomatic fact }
  , DRagLint.Diagnostics.ParseCache    { ADP2 T3: TAstParseCache -- memoized per-file tree, owned by the cache }
  , DRagLint.Analysis.Cfg              { ADP2 T3: CfgFindProcs -- collect every defProc in the file's tree }
  , DRagLint.Analysis.Flow.Lattices    { ADP2 T4: TRoutineVarTable -- a same-named local/param/Result shadows a field, never misclassified as one }
  , DRagLint.Diagnostics.AstChecks     { ADP2 T3: TAstChecker.CyclomaticOf -- ONE shared formula with the lint rule }
  , DRagLint.Parser.DFM                { ADP2 T6: TDfmEventBinding/ExtractDfmEventBindings -- the paired-.dfm event-wiring extractor }
  ;

{ v0.85 PERF -- memoize FindAllChildSymbols(ParentId).

  Three separate fact analyses (AnalyzeReadsWrites, AnalyzeUiAffinity and the
  ownership pass) ask the store for the owning class's children, and each runs
  once per ROUTINE. Every method of a class therefore re-issues the same query
  and re-materialises the same rows: a 100-method class costs 100 identical
  round-trips per analysis.

  The rows cannot change underneath us during a file's facts pass -- OpenFileTx
  has already rewritten this file's symbols and the facts pass runs inside that
  same still-open transaction -- so caching per parent id is safe.

  Single-entry by design: routines of one class are analysed consecutively, which
  is exactly the access pattern. NOT THREAD-SAFE -- see the note on GProcsCache;
  parallel indexing must give each worker its own cache. }
var
  GKidsCacheParent: Int64 = -1;
  GKidsCache      : TArray<TSymbol>;

function ChildSymbolsCached(const AStore: ISymbolStore; AParentId: Int64): TArray<TSymbol>;
begin
  if (AParentId > 0) and (AParentId = GKidsCacheParent) then Exit(GKidsCache);
  GKidsCache      := AStore.FindAllChildSymbols(AParentId);
  GKidsCacheParent:= AParentId;
  Result          := GKidsCache;
end;

function SymbolFactsCsvJoin(const AItems: TArray<string>): string;
begin
  if Length(AItems) = 0 then Exit('');
  Result:= string.Join(',', AItems);
end;

function SymbolFactsCsvSplit(const ACsv: string): TArray<string>;
begin
  if Trim(ACsv) = '' then Exit(nil);
  Result:= SplitString(ACsv, ',');
end;

// ADP2 T4: display cap for the Reads:/Writes: fields fact -- 8 names shown,
// then a ' (+N more)' suffix (the Phase 1 cap convention DRagLint.Doc.Regions'
// MoreSuffix already uses for Calls/CalledFrom/etc.). Unlike those fields,
// ReadsFields/WritesFields have no companion *Total column (see TSymbolFacts,
// DRagLint.Core.Model), so the cap decision is made ONCE here, at analysis
// time, and the resulting string is stored -- and later rendered -- verbatim.
const
  FIELD_RW_CAP = 8;

// Byte-slice text of N out of ASrc (UTF-8), mirroring the private NodeStr
// helper every AST-walking unit (DRagLint.Analysis.Cfg, .Flow.Lattices,
// DRagLint.Diagnostics.AstChecks) keeps its own copy of: none of them export
// it, so it is duplicated here rather than reaching across units for a
// three-line helper.
function FieldNodeStr(const N: TTSNode; const ASrc: TBytes): string;
var S, E, L: Integer;
begin
  Result:= '';
  if N.IsNull then Exit;
  S:= Integer(N.StartByte); E:= Integer(N.EndByte); L:= E - S;
  if (L <= 0) or (S < 0) or (E > Length(ASrc)) then Exit;
  Result:= TEncoding.UTF8.GetString(ASrc, S, L);
end;

// True when AEnt is the bare identifier 'Inc' or 'Dec' (case-insensitive) --
// the two mutating RTL intrinsics whose FIRST argument is a WRITE target
// (see WalkFieldRW's header comment for the full classification ruleset).
function IsIncOrDecEntity(const AEnt: TTSNode; const ASrc: TBytes): Boolean;
var T: string;
begin
  Result:= False;
  if AEnt.IsNull or (AEnt.NodeType <> 'identifier') then Exit;
  T:= LowerCase(Trim(FieldNodeStr(AEnt, ASrc)));
  Result:= (T = 'inc') or (T = 'dec');
end;

// Single-pass classification walk over one routine body (or any subtree of
// it) for the Reads/Writes fields fact. Every bare identifier that resolves
// (case-insensitively) to a key of AFields -- and is NOT shadowed by a
// same-named local/param/Result in AVars (a local declaration shadows a
// field of the same name in Pascal scoping -- AVars is the routine's OWN
// TRoutineVarTable, built once by the caller via DRagLint.Analysis.
// Flow.Lattices' TRoutineVarTable.Build, the exact same var table the
// dataflow lattices themselves use) -- is recorded into AReads/AWrites
// (TList<string>, ORIGINAL-CASE display spelling, first-occurrence order,
// each deduped independently so a field re-read/re-written many times
// appears once per list).
//
// Node-shape rules reuse the SAME grammar knowledge DRagLint.Analysis.
// Flow.Lattices' CollectReadsAndCallDefs / TLiveness.Transfer already encode
// (an 'assignment' node's lhs/rhs fields; 'exprDot' splitting a receiver from
// its member name; 'exprCall' splitting a callee entity from its args) -- see
// this unit's Analyze remarks for the pointer to that reference reading.
// This walk is deliberately NOT the shared TDataFlowSolver/IDataFlowAnalysis
// lattice machinery (field read/write is a focused AST classification here,
// not a fixpoint dataflow property):
//   - 'assignment': a BARE-IDENTIFIER lhs is a WRITE. Any other lhs shape (an
//     indexed/qualified write, e.g. `a[i] :=` / `x.f :=`) is walked as a READ
//     of its own subtree instead -- absence over guessing a field write for
//     a shape this fact does not attempt to resolve.
//   - 'exprCall' whose entity is 'Inc'/'Dec': the first argument, if a bare
//     identifier, is a WRITE (the mutating-intrinsic rule); any further
//     argument (Inc/Dec's optional step N) and the callee identifier itself
//     are reads.
//   - any OTHER 'exprCall': the entity and every argument are reads -- the
//     brief's documented choice. Resolving whether an ordinary callee's
//     parameter is var/out (so a field passed to it might be written) is
//     cross-referenced/expensive and explicitly OPTIONAL/not attempted here;
//     an unresolved possible write is never guessed, so such a field is
//     simply counted as read (absence of a write fact, never a wrong one).
//   - 'exprDot': only the lhs (receiver) is walked. The rhs is the MEMBER
//     NAME, never itself a var/field reference (e.g. in `FLogger.Log(...)`,
//     'Log' must never be checked against the field-name set).
//   - anything else (if/while/for/case/block/binary-expr/statement
//     wrappers/...): recurse into every named child.
//
// KNOWN GRAMMAR GOTCHA (found empirically during T4's own RED/GREEN cycle,
// NOT a bug in this walk): a BARE (no begin/end) `if C then Inc(X) else
// Y := Z;` -- an Inc/Dec call as the un-braced 'then' arm, immediately
// followed by an un-braced assignment 'else' arm -- is misparsed by
// tree-sitter-delphi13: the WHOLE construct comes back as one 'assignment'
// node whose lhs is an 'exprIf' (covering "if C then Inc(X)") and whose rhs
// is the bare identifier Y (with the ':= Z' part orphaned) -- so Y reads
// back as a READ, not a WRITE. Confirmed via temporary AST tracing; wrapping
// EITHER arm in begin/end avoids it entirely (the fixture and this repo's
// own style always brace multi-branch bodies, so it is not expected to bite
// real code, but it is a real, pre-existing parser gap -- out of scope for
// this fact to fix -- worth a grammar-side ticket).
procedure WalkFieldRW(const N: TTSNode; const ASrc: TBytes; AFields: TDictionary<string, string>;
  AVars: TRoutineVarTable; AReads, AWrites: TList<string>);

  function ResolveField(const AIdent: TTSNode; out ADisplay: string): Boolean;
  var Key: string;
  begin
    Result:= False;
    if AIdent.IsNull or (AIdent.NodeType <> 'identifier') then Exit;
    Key:= LowerCase(Trim(FieldNodeStr(AIdent, ASrc)));
    if (AVars <> nil) and (AVars.IndexOf(Key) >= 0) then Exit; // shadowed by a local/param/Result
    Result:= AFields.TryGetValue(Key, ADisplay);
  end;

  procedure MarkRead(const AIdent: TTSNode);
  var Disp: string;
  begin
    if ResolveField(AIdent, Disp) and (AReads.IndexOf(Disp) < 0) then AReads.Add(Disp);
  end;

  procedure MarkWrite(const AIdent: TTSNode);
  var Disp: string;
  begin
    if ResolveField(AIdent, Disp) and (AWrites.IndexOf(Disp) < 0) then AWrites.Add(Disp);
  end;

var
  I         : Integer;
  Lhs, Rhs  : TTSNode ;
  Ent, ArgsN: TTSNode ;
begin
  if N.IsNull then Exit;

  if N.NodeType = 'assignment' then
  begin
    Lhs:= N.ChildByField('lhs');
    Rhs:= N.ChildByField('rhs');
    if (not Lhs.IsNull) and (Lhs.NodeType = 'identifier') then
      MarkWrite(Lhs)
    else
      WalkFieldRW(Lhs, ASrc, AFields, AVars, AReads, AWrites);
    WalkFieldRW(Rhs, ASrc, AFields, AVars, AReads, AWrites);
    Exit;
  end;

  if N.NodeType = 'identifier' then begin MarkRead(N); Exit; end;

  if N.NodeType = 'exprDot' then
  begin
    WalkFieldRW(N.ChildByField('lhs'), ASrc, AFields, AVars, AReads, AWrites);
    Exit; // rhs = member name, never itself a field reference
  end;

  if N.NodeType = 'exprCall' then
  begin
    Ent  := N.ChildByField('entity');
    ArgsN:= N.ChildByField('args');
    if IsIncOrDecEntity(Ent, ASrc) and (not ArgsN.IsNull) and (ArgsN.NamedChildCount > 0) then
    begin
      if ArgsN.NamedChild(0).NodeType = 'identifier' then MarkWrite(ArgsN.NamedChild(0))
      else WalkFieldRW(ArgsN.NamedChild(0), ASrc, AFields, AVars, AReads, AWrites);
      for I:= 1 to ArgsN.NamedChildCount - 1 do
        WalkFieldRW(ArgsN.NamedChild(I), ASrc, AFields, AVars, AReads, AWrites);
    end
    else if not ArgsN.IsNull then
      for I:= 0 to ArgsN.NamedChildCount - 1 do
        WalkFieldRW(ArgsN.NamedChild(I), ASrc, AFields, AVars, AReads, AWrites);
    WalkFieldRW(Ent, ASrc, AFields, AVars, AReads, AWrites); // a field holding a callback (FOnChange()) reads FOnChange
    Exit;
  end;

  for I:= 0 to N.NamedChildCount - 1 do
    WalkFieldRW(N.NamedChild(I), ASrc, AFields, AVars, AReads, AWrites);
end;

// Joins up to ACap entries of AItems with ', ', appending the Phase 1
// ' (+N more)' suffix when AItems holds more than ACap. '' for an empty
// AItems. This IS the final, display-ready string stored verbatim in
// symbol_facts.reads_fields/writes_fields (see FIELD_RW_CAP's comment for
// why the cap can't be deferred to render time for these two columns).
function JoinCappedDisplay(AItems: TList<string>; ACap: Integer): string;
var Shown, I: Integer;
begin
  Result:= '';
  if (AItems = nil) or (AItems.Count = 0) then Exit;
  if AItems.Count > ACap then Shown:= ACap else Shown:= AItems.Count;
  for I:= 0 to Shown - 1 do
  begin
    if I > 0 then Result:= Result + ', ';
    Result:= Result + AItems[I];
  end;
  if AItems.Count > ACap then
    Result:= Result + Format(' (+%d more)', [AItems.Count - ACap]);
end;

// ADP2 T4: fills AReadsCsv/AWritesCsv (capped, display-ready strings) for one
// routine. AProc/ABody are the SAME defProc/body nodes Analyze already
// matched for Cyclomatic -- no second AST scan.
//
// FINDING THE OWNING CLASS -- ASym.ParentId IS usable here (ADP2 T4 fix wave:
// root-cause identity resolution). It used to NOT be: ASym was the caller's
// PRE-INSERT ParseRes.Symbols[I], so ASym.Id/.FileId were not yet assigned and
// ASym.ParentId was still an untranslated IN-ARRAY INDEX (DRagLint.Core.
// Indexer.IndexFile's symbols loop only translated parent_id to the real
// symbols.id on its OWN local copy, immediately before that loop's own
// FStore.UpsertSymbol call -- the facts loop, which calls Analyze, used to
// re-read the SAME untranslated ParseRes.Symbols[I] afterwards). This
// function used to work around that by re-resolving the routine's ALREADY-
// INSERTED row via AStore.FindFileIdByPath(AFilePath) + AStore.
// FindEnclosingRoutineByImpl(FileId, ASym.ImplStartLine) -- three SQL
// round-trips per routine, always-on, corpus-wide. The indexer's facts loop
// now resolves identity BEFORE calling Analyze instead (Id := the
// just-inserted DB id, FileId := the open file-tx's FileId, ParentId :=
// translated from its in-array index via the same IdxToId map the symbols
// loop uses) -- a pure in-memory fixup, no DB round-trip -- so ASym.ParentId
// (and .Id/.FileId) can be trusted directly here, and by every later fact
// group (T5-T8) that needs the owning symbol's identity: just read
// ASym.ParentId, do not re-resolve it via FindFileIdByPath/
// FindEnclosingRoutineByImpl.
//
// Fields considered are the resolved owning class's DIRECT children
// (AStore.FindAllChildSymbols) filtered to Kind = skField: OWN-CLASS fields
// only. Inherited-field resolution (walking ancestor classes for a field
// declared higher up) is explicitly OUT OF SCOPE for T4 (the brief marks it
// OPTIONAL/bounded; own-class fields are the high-signal core) -- an
// identifier that does not resolve to a DIRECT field of the owning class is
// simply never reported (absence over noise), even if it happens to be an
// inherited field. A free routine (ASym.ParentId <= 0) or an owning class
// with no field children both yield '' for both -- the renderer then omits
// the whole Reads/Writes line.
procedure AnalyzeReadsWrites(const AProc, ABody: TTSNode; const ASrc: TBytes;
  const ASym: TSymbol; const AFilePath: string; const AStore: ISymbolStore; out AReadsCsv, AWritesCsv: string);
var
  Fields       : TDictionary<string, string>;
  Kids         : TArray<TSymbol>;
  Kid          : TSymbol;
  LKey         : string;
  Vars         : TRoutineVarTable;
  Reads, Writes: TList<string>;
begin
  AReadsCsv := '';
  AWritesCsv:= '';
  if ABody.IsNull then Exit;
  // ADP2 T4 fix wave: ASym's identity is resolved by the caller (the
  // indexer's facts loop) before Analyze is called -- see this function's
  // header comment above -- so ASym.ParentId is read directly here, no
  // FindFileIdByPath/FindEnclosingRoutineByImpl re-resolution needed.
  // AFilePath is now unused by this function; left in the signature
  // unchanged (mechanical plumbing fix, not a signature change).
  if ASym.ParentId <= 0 then Exit; // free routine (no owning class) -- nothing to classify

  Fields:= TDictionary<string, string>.Create;
  Reads := TList<string>.Create;
  Writes:= TList<string>.Create;
  Vars  := nil;
  try
    Kids:= ChildSymbolsCached(AStore, ASym.ParentId); { was a per-routine store round-trip }
    for Kid in Kids do
      if Kid.Kind = skField then
      begin
        LKey:= LowerCase(Kid.Name);
        if not Fields.ContainsKey(LKey) then Fields.Add(LKey, Kid.Name);
      end;
    if Fields.Count = 0 then Exit; // no owning-class fields -> nothing to classify

    Vars:= TRoutineVarTable.Build(AProc, ASrc); // params/locals/Result shadow same-named fields
    WalkFieldRW(ABody, ASrc, Fields, Vars, Reads, Writes);

    AReadsCsv := JoinCappedDisplay(Reads, FIELD_RW_CAP);
    AWritesCsv:= JoinCappedDisplay(Writes, FIELD_RW_CAP);
  finally
    Vars.Free;
    Writes.Free;
    Reads.Free;
    Fields.Free;
  end;
end;

// v(ADP3 T11): the var/out parameters this routine writes THROUGH, as a
// display-ready 'AList (var), AReason (out)' string. '' when the routine
// mutates none, which is what makes the renderer omit the whole line.
//
// This closes the gap ADP2 T4 left open by design: AnalyzeReadsWrites resolves
// identifiers against the owning class's FIELDS, so a free procedure whose
// entire job is to fill an `out` parameter reported nothing at all.
//
// NO SECOND PARSE, NO SECOND VAR TABLE PASS. AProc/ABody are the SAME nodes
// Analyze already matched for Cyclomatic/AnalyzeReadsWrites, and the parameter
// MODES come from DRagLint.Analysis.Flow.Lattices' TRoutineVarTable -- the one
// place in this codebase that already parses `var`/`out`/`const` modifiers off
// a declArg (see its AddArgs). ASym.Signature was the alternative the plan
// offered; it was read and rejected: it is a re-serialized string that would
// need a SECOND modifier parser, and the indexed Signature is empty often
// enough (see AnalyzeReadsWrites' own HasReturn note in Doc.Drift) that the
// fact would silently go missing. The var table is AST-grounded and already
// built for every routine this walk runs on. TRoutineVar.Display -- added by
// this task -- carries the DECLARATION spelling, so the rendered name is the
// one the author wrote, not the (possibly differently-cased) use site.
//
// WHAT COUNTS AS A MUTATION. Deliberately the same shapes WalkFieldRW already
// treats as writes, plus one:
//   - 'assignment' with a BARE-IDENTIFIER lhs        -> mutation.
//   - 'assignment' with an INDEXED lhs (`AList[0] :=`) whose base resolves to
//     a bare identifier -> mutation. This one is NEW relative to WalkFieldRW,
//     and it is not a guess: `A[i] := v` cannot execute without writing through
//     A. WalkFieldRW declines it because for a FIELD the indexed base may be
//     an unrelated expression; here the base must resolve to a var/out
//     parameter of THIS routine or nothing is reported.
//   - 'exprCall' on Inc/Dec, first argument a bare identifier -> mutation.
//
// WHAT IS DELIBERATELY NOT DETECTED, absence over a wrong fact:
//   - an ordinary call's var argument, `SetLength(AList, N)` most notably.
//     Resolving whether an arbitrary callee's parameter is var/out is the
//     cross-referenced work ADP2 T4 explicitly declined, and SetLength is not
//     special-cased because a curated intrinsic list is a maintenance surface
//     that silently under-reports everything not on it. tests\autodoc\
//     fixtures\docp3\mutates.pas carries the SetLength form next to a real
//     indexed write precisely so the case is on file if this is ever revisited.
//   - a DOT lhs, `AObj.Field := X`. For a record parameter that IS a mutation;
//     for a class-typed one it mutates the POINTEE, not the parameter, and the
//     two are indistinguishable here without type resolution. Reporting both
//     would make 'Mutates:' mean two different things.
//
// Capped at FIELD_RW_CAP with the same ' (+N more)' suffix as Reads/Writes, via
// the shared JoinCappedDisplay -- one cap rule for every display-ready column.
procedure WalkMutatedParams(const N: TTSNode; const ASrc: TBytes;
  AVars: TRoutineVarTable; AOut: TList<string>);

  // The bare identifier an assignment LHS ultimately writes through, or a null
  // node when the shape is one this fact does not claim. Descends through
  // indexing/call-shaped wrappers (`A[i]`, `A[i][j]`) via the entity/lhs field
  // or the first named child, and STOPS DEAD at an 'exprDot' -- see the header.
  // The iteration cap is a cheap guard against a pathological/malformed tree,
  // never a semantic limit: real LHS nesting is one or two levels.
  function BaseIdentOfLhs(const ALhs: TTSNode): TTSNode;
  var Cur, Nxt: TTSNode; Guard: Integer;
  begin
    Result:= Default(TTSNode);
    Cur   := ALhs;
    for Guard:= 0 to 7 do
    begin
      if Cur.IsNull then Exit;
      if Cur.NodeType = 'identifier' then Exit(Cur);
      if Cur.NodeType = 'exprDot' then Exit;      // mutates the pointee, not the param
      Nxt:= Cur.ChildByField('entity');
      if Nxt.IsNull then Nxt:= Cur.ChildByField('lhs');
      if Nxt.IsNull and (Cur.NamedChildCount > 0) then Nxt:= Cur.NamedChild(0);
      if Nxt.IsNull then Exit;
      Cur:= Nxt;
    end;
  end;

  // Records AIdent when it resolves to a var/out parameter of this routine.
  // Deduped on the DISPLAY string, so a parameter written many times appears
  // once, in first-write order.
  procedure MarkMutation(const AIdent: TTSNode);
  var Idx: Integer; RV: TRoutineVar; Disp: string;
  begin
    if AIdent.IsNull or (AIdent.NodeType <> 'identifier') or (AVars = nil) then Exit;
    Idx:= AVars.IndexOf(LowerCase(Trim(FieldNodeStr(AIdent, ASrc))));
    if Idx < 0 then Exit;
    RV:= AVars.Get(Idx);
    if not (RV.Kind in [vkParamVar, vkParamOut]) then Exit;
    if RV.Kind = vkParamVar then Disp:= RV.Display + ' (var)'
    else Disp:= RV.Display + ' (out)';
    if AOut.IndexOf(Disp) < 0 then AOut.Add(Disp);
  end;

var
  I       : Integer;
  Lhs, Rhs: TTSNode ;
  Ent, Arg: TTSNode ;
begin
  if N.IsNull then Exit;

  if N.NodeType = 'assignment' then
  begin
    Lhs:= N.ChildByField('lhs');
    Rhs:= N.ChildByField('rhs');
    if (not Lhs.IsNull) and (Lhs.NodeType = 'identifier') then
      MarkMutation(Lhs)
    else
      MarkMutation(BaseIdentOfLhs(Lhs));
    // The LHS subtree is still walked: an index expression can itself contain
    // a nested assignment/Inc in exotic code, and the RHS always can.
    WalkMutatedParams(Lhs, ASrc, AVars, AOut);
    WalkMutatedParams(Rhs, ASrc, AVars, AOut);
    Exit;
  end;

  if N.NodeType = 'exprCall' then
  begin
    Ent:= N.ChildByField('entity');
    Arg:= N.ChildByField('args');
    if IsIncOrDecEntity(Ent, ASrc) and (not Arg.IsNull) and (Arg.NamedChildCount > 0) then
      MarkMutation(Arg.NamedChild(0));
    // Fall through to the generic recursion below rather than returning: an
    // ordinary call's arguments can hold assignments (an inline lambda body).
  end;

  for I:= 0 to N.NamedChildCount - 1 do
    WalkMutatedParams(N.NamedChild(I), ASrc, AVars, AOut);
end;

// v(ADP3 T11): fills the display-ready `Mutates:` string for one routine. See
// WalkMutatedParams' header (immediately above) for the derivation rules and
// for what is deliberately not detected. AProc/ABody are the SAME nodes Analyze
// already matched -- no second AST scan.
function AnalyzeMutatesParams(const AProc, ABody: TTSNode; const ASrc: TBytes): string;
var
  Vars: TRoutineVarTable;
  Hits: TList<string>   ;
begin
  Result:= '';
  if ABody.IsNull then Exit;
  Vars:= nil;
  Hits:= TList<string>.Create;
  try
    Vars:= TRoutineVarTable.Build(AProc, ASrc);
    WalkMutatedParams(ABody, ASrc, Vars, Hits);
    Result:= JoinCappedDisplay(Hits, FIELD_RW_CAP);
  finally
    Vars.Free;
    Hits.Free;
  end;
end;

const
  // v(ADP3 T12): curated UI base types + globals. ENGINE KNOWLEDGE, not user
  // configuration -- it lives here, next to the analysis that consumes it, not
  // in the manifest. A STALE list UNDER-reports (the fact is simply omitted),
  // it never emits a false claim, so growing it later is safe and
  // non-breaking. That asymmetry is the whole reason the fact is
  // positive-findings-only: see AnalyzeUiAffinity's header.
  UI_BASE_TYPES: array[0..9] of string = (
    'TControl', 'TWinControl', 'TForm', 'TFrame', 'TCustomForm',
    'TGraphicControl', 'TcxControl', 'TcxCustomGrid', 'TdxBar', 'TCustomPanel');
  UI_GLOBALS: array[0..1] of string = ('Application', 'Screen');

// v(ADP3 T12): strips a unit qualifier and any generic argument list from a
// declared-type text, leaving the bare type name. '' when there is none.
function BareTypeName(const ATypeName: string): string;
var P: Integer;
begin
  Result:= Trim(ATypeName);
  if Result = '' then Exit;
  P:= Pos('<', Result);
  if P > 0 then Result:= Trim(Copy(Result, 1, P - 1));
  P:= Result.LastDelimiter('.'); // Vcl.Forms.TForm -> TForm
  if P >= 0 then Result:= Trim(Copy(Result, P + 2, MaxInt));
end;

// v(ADP3 T12): True when ATypeName is, or descends from, a curated UI base
// type. Two arms, in cost order:
//   1. DIRECT NAME -- the (qualifier-stripped) type name is itself on
//      UI_BASE_TYPES. No store access at all.
//   2. ANCESTRY -- the name resolves to a class symbol whose ancestor CHAIN
//      reaches a curated name. This is what catches the shape real code is
//      actually made of: `TMyPanel = class(TCustomPanel)`, or any generated
//      form class, whose OWN name will never be on any list.
// Unresolvable -> False. Absence over a wrong claim, the same stance
// IsReferenceTypeName takes for its own tier-1 ground truth.
//
// THE CHAIN IS WALKED VIA TSymbol.Heritage, NOT GetTransitiveAncestors, and
// that is a hard requirement of running at INDEX time rather than render time.
// type_ancestors is populated by the RESOLVE pass, which runs AFTER the
// per-file facts loop; re-indexing a file cascades its old rows away first, so
// during Analyze that table is reliably EMPTY for the very file being analyzed.
// Reproduced directly: the direct-name arm passed while the ancestry arm
// returned nothing, on a first index AND on a forced re-index. Heritage is the
// parser's raw ancestor text and is written with the symbol row itself, one
// loop earlier, so it is the only ancestry signal that exists this early.
//
// Consequences, both accepted and both in the "under-report, never mis-report"
// direction: a cross-unit ancestor whose unit has not been indexed yet is
// invisible until the next run, and an ancestor named only through an alias the
// resolve pass would have followed is not followed here.
//
// ACache memoizes per lowercased bare name for the lifetime of ONE routine's
// analysis: a form method touches the same few control types repeatedly.
function IsUiTypeName(const AStore: ISymbolStore; const ATypeName: string;
  ACache: TDictionary<string, Boolean>): Boolean;

  // Walks the Heritage chain upward from a type NAME. Bounded by ADepth and by
  // ASeen (a cycle guard -- malformed/mutually-referencing heritage text must
  // not spin here, since this runs per identifier per routine, corpus-wide).
  function ChainReachesUi(const AName: string; ASeen: TStringList; ADepth: Integer): Boolean;
  var
    Cands: TArray<TSymbol>;
    Cand : TSymbol        ;
    Part : string         ;
    Bare : string         ;
  begin
    Result:= False;
    if (ADepth <= 0) or (AName = '') then Exit;
    if ASeen.IndexOf(LowerCase(AName)) >= 0 then Exit;
    ASeen.Add(LowerCase(AName));
    if MatchText(AName, UI_BASE_TYPES) then Exit(True);

    Cands:= AStore.FindSymbolsByExactName(AName);
    for Cand in Cands do
    begin
      if not (Cand.Kind in [skClass, skInterface]) then Continue;
      if Trim(Cand.Heritage) = '' then Continue;
      // Heritage is a raw 'TBar, IBaz' list: an ancestor class plus any
      // implemented interfaces. Every entry is followed -- a control type can
      // sit behind either position depending on how the class was declared.
      for Part in Cand.Heritage.Split([',']) do
      begin
        Bare:= BareTypeName(Part);
        if Bare = '' then Continue;
        if ChainReachesUi(Bare, ASeen, ADepth - 1) then Exit(True);
      end;
    end;
  end;

var
  Bare : string     ;
  Key  : string     ;
  Seen : TStringList;
begin
  Result:= False;
  Bare:= BareTypeName(ATypeName);
  if Bare = '' then Exit;

  Key:= LowerCase(Bare);
  if (ACache <> nil) and ACache.TryGetValue(Key, Result) then Exit;

  Seen:= TStringList.Create;
  try
    Seen.CaseSensitive:= False;
    Result:= ChainReachesUi(Bare, Seen, 16);
  finally
    Seen.Free;
  end;

  if ACache <> nil then ACache.AddOrSetValue(Key, Result);
end;

// v(ADP3 T12): collects the UI-typed identifiers one routine body touches.
// Node-shape rules are WalkFieldRW's, for the same reasons -- in particular
// 'exprDot' walks its LHS ONLY, because the RHS is a member NAME: without that,
// a method or property called `Application` would be counted as the VCL global.
//
// Resolution order per bare identifier, and the order is Pascal's own scoping:
//   1. a routine-scoped local/parameter (TRoutineVarTable) -> its declared type;
//   2. otherwise an own-class FIELD -> its declared type (a field symbol's
//      Signature column carries it, verified against a scratch index);
//   3. otherwise a curated GLOBAL name (Application/Screen), which a local or
//      field of the same name therefore correctly shadows.
// Anything that resolves to none of those is not reported.
procedure WalkUiTouches(const N: TTSNode; const ASrc: TBytes; const AStore: ISymbolStore;
  AVars: TRoutineVarTable; AFieldTypes: TDictionary<string, TPair<string, string>>;
  ACache: TDictionary<string, Boolean>; AOut: TList<string>);

  procedure MarkIdent(const AIdent: TTSNode);
  var
    Raw, Key, Disp, TypeName: string;
    Idx : Integer;
    RV  : TRoutineVar;
    Pair: TPair<string, string>;
  begin
    if AIdent.IsNull or (AIdent.NodeType <> 'identifier') then Exit;
    Raw:= Trim(FieldNodeStr(AIdent, ASrc));
    if Raw = '' then Exit;
    Key:= LowerCase(Raw);

    Disp:= ''; TypeName:= '';
    if AVars <> nil then
    begin
      Idx:= AVars.IndexOf(Key);
      if Idx >= 0 then
      begin
        RV:= AVars.Get(Idx);
        Disp:= RV.Display; TypeName:= RV.TypeText;
      end;
    end;
    if (Disp = '') and (AFieldTypes <> nil) and AFieldTypes.TryGetValue(Key, Pair) then
    begin
      Disp:= Pair.Key; TypeName:= Pair.Value;
    end;

    if Disp = '' then
    begin
      // Neither a routine var nor an own-class field: the curated globals are
      // the only remaining way an identifier can be a UI touch.
      if not MatchText(Raw, UI_GLOBALS) then Exit;
      if AOut.IndexOf(Raw) < 0 then AOut.Add(Raw);
      Exit;
    end;

    if not IsUiTypeName(AStore, TypeName, ACache) then Exit;
    if AOut.IndexOf(Disp) < 0 then AOut.Add(Disp);
  end;

var
  I  : Integer;
  Ent: TTSNode;
begin
  if N.IsNull then Exit;

  if N.NodeType = 'identifier' then begin MarkIdent(N); Exit; end;

  if N.NodeType = 'exprDot' then
  begin
    WalkUiTouches(N.ChildByField('lhs'), ASrc, AStore, AVars, AFieldTypes, ACache, AOut);
    Exit; // rhs = member name, never itself a variable reference
  end;

  if N.NodeType = 'exprCall' then
  begin
    Ent:= N.ChildByField('entity');
    WalkUiTouches(Ent, ASrc, AStore, AVars, AFieldTypes, ACache, AOut);
    var ArgsN: TTSNode:= N.ChildByField('args');
    if not ArgsN.IsNull then
      for I:= 0 to ArgsN.NamedChildCount - 1 do
        WalkUiTouches(ArgsN.NamedChild(I), ASrc, AStore, AVars, AFieldTypes, ACache, AOut);
    Exit;
  end;

  for I:= 0 to N.NamedChildCount - 1 do
    WalkUiTouches(N.NamedChild(I), ASrc, AStore, AVars, AFieldTypes, ACache, AOut);
end;

// v(ADP3 T12): fills the display-ready UI-affinity string for one routine --
// the controls/globals it touches, e.g. 'FPanel, Application'. '' when none was
// detected. AProc/ABody are the SAME nodes Analyze already matched.
//
// POSITIVE FINDINGS ONLY. This fact can say "a UI touch WAS detected"; it can
// never say the converse. An empty result means "nothing was detected", NOT
// "this routine is thread-safe", and no caller may render it as the latter --
// the curated list under-reports by construction (a control type nobody has
// added yet is invisible), so a thread-safety claim built on it would be false
// exactly when it mattered most. tests\autodoc\run_doc_p3_ui.ps1 asserts the
// words 'thread-safe'/'thread safe' appear in no generated block, permanently.
function AnalyzeUiAffinity(const AProc, ABody: TTSNode; const ASrc: TBytes;
  const ASym: TSymbol; const AStore: ISymbolStore): string;
var
  Vars  : TRoutineVarTable                        ;
  Fields: TDictionary<string, TPair<string, string>>;
  Cache : TDictionary<string, Boolean>            ;
  Hits  : TList<string>                           ;
  Kids  : TArray<TSymbol>                         ;
  Kid   : TSymbol                                 ;
  LKey  : string                                  ;
begin
  Result:= '';
  if ABody.IsNull then Exit;
  Vars  := nil;
  Fields:= TDictionary<string, TPair<string, string>>.Create;
  Cache := TDictionary<string, Boolean>.Create;
  Hits  := TList<string>.Create;
  try
    // Own-class fields only, the same scope AnalyzeReadsWrites uses (see its
    // header for why inherited fields are out of scope): display name + the
    // declared type text, which for a field symbol lives in Signature.
    if ASym.ParentId > 0 then
    begin
      Kids:= ChildSymbolsCached(AStore, ASym.ParentId); { was a per-routine store round-trip }
      for Kid in Kids do
        if Kid.Kind = skField then
        begin
          LKey:= LowerCase(Kid.Name);
          if not Fields.ContainsKey(LKey) then
            Fields.Add(LKey, TPair<string, string>.Create(Kid.Name, Kid.Signature));
        end;
    end;

    Vars:= TRoutineVarTable.Build(AProc, ASrc);
    WalkUiTouches(ABody, ASrc, AStore, Vars, Fields, Cache, Hits);
    Result:= JoinCappedDisplay(Hits, FIELD_RW_CAP);
  finally
    Hits.Free;
    Cache.Free;
    Fields.Free;
    Vars.Free;
  end;
end;

const
  // v(ADP3 T13): curated external-surface lists. Same discipline as
  // UI_BASE_TYPES (T12): engine knowledge, positive findings only, a stale list
  // under-reports and never lies.
  //
  // THE LISTS ARE SPLIT BY MATCH SHAPE, not just by category, and that split is
  // load-bearing. A bare name match would manufacture false claims on two of
  // the commonest identifiers in any Delphi codebase:
  //   * TYPE receivers ('TFile', 'TRegistry', ...) are matched ANYWHERE an
  //     identifier appears. They are type names, so a collision is unlikely and
  //     a `TFile` in the body means the RTL type in practice.
  //   * BARE INTRINSICS ('Reset', 'Rewrite', ...) are matched ONLY as the
  //     entity of a call that HAS ARGUMENTS. `Reset` and `CloseFile` are
  //     perfectly ordinary method names; the intrinsics always take a file
  //     variable, so requiring an argument list separates them from a user's
  //     own parameterless `Reset;` without needing type resolution.
  //   * TRANSACTION VERBS ('Commit', 'Rollback', ...) are matched ONLY as a DOT
  //     MEMBER name -- `ATxn.Commit`. A free routine called Commit is not a
  //     transaction, and the verbs are always invoked on a connection object.
  // Residual, accepted, and in the under-report direction: a file variable
  // opened through a helper this list does not name is invisible.
  TOUCH_TYPE_FILE    : array[0..3] of string = ('TFile', 'TDirectory', 'TPath', 'TStreamWriter');
  TOUCH_BARE_FILE    : array[0..3] of string = ('AssignFile', 'Rewrite', 'Reset', 'CloseFile');
  TOUCH_TYPE_REGISTRY: array[0..1] of string = ('TRegistry', 'TRegistryIniFile');
  TOUCH_TYPE_NETWORK : array[0..3] of string = ('THTTPClient', 'TIdHTTP', 'TNetHTTPClient', 'TIdTCPClient');
  TOUCH_TXN_START    : array[0..0] of string = ('StartTransaction');
  TOUCH_TXN_COMMIT   : array[0..1] of string = ('Commit', 'CommitRetaining');
  TOUCH_TXN_ROLLBACK : array[0..1] of string = ('Rollback', 'RollbackRetaining');

type
  // v(ADP3 T13): what one body was observed to reach. Booleans, not lists: the
  // fact renders CATEGORIES, never call sites -- the call site is already in
  // 'Calls:', and repeating it here would be two facts that can disagree.
  TTouchFlags = record
    FileSys : Boolean;
    Registry: Boolean;
    Network : Boolean;
    TxnStart: Boolean;
    TxnCommit  : Boolean;
    TxnRollback: Boolean;
  end;

// v(ADP3 T13): single classification walk for the Touches fact. See the const
// block above for the match-shape rules, which this function is the executable
// form of. Recurses into every named child; the shape tests are applied at the
// 'exprCall'/'exprDot' nodes where the distinction is actually visible.
procedure WalkTouches(const N: TTSNode; const ASrc: TBytes; var AFlags: TTouchFlags);

  function IdentText(const ANode: TTSNode): string;
  begin
    Result:= '';
    if (not ANode.IsNull) and (ANode.NodeType = 'identifier') then
      Result:= Trim(FieldNodeStr(ANode, ASrc));
  end;

  // A TYPE receiver can appear anywhere; classify on the bare name alone.
  procedure MarkTypeName(const AName: string);
  begin
    if AName = '' then Exit;
    if MatchText(AName, TOUCH_TYPE_FILE    ) then AFlags.FileSys := True;
    if MatchText(AName, TOUCH_TYPE_REGISTRY) then AFlags.Registry:= True;
    if MatchText(AName, TOUCH_TYPE_NETWORK ) then AFlags.Network := True;
  end;

  // A dot MEMBER name -- the only shape a transaction verb is accepted in.
  procedure MarkMember(const AName: string);
  begin
    if AName = '' then Exit;
    if MatchText(AName, TOUCH_TXN_START   ) then AFlags.TxnStart   := True;
    if MatchText(AName, TOUCH_TXN_COMMIT  ) then AFlags.TxnCommit  := True;
    if MatchText(AName, TOUCH_TXN_ROLLBACK) then AFlags.TxnRollback:= True;
  end;

var
  I        : Integer;
  Ent, Args: TTSNode;
begin
  if N.IsNull then Exit;

  if N.NodeType = 'identifier' then begin MarkTypeName(IdentText(N)); Exit; end;

  if N.NodeType = 'exprDot' then
  begin
    MarkMember(IdentText(N.ChildByField('rhs')));
    WalkTouches(N.ChildByField('lhs'), ASrc, AFlags);
    Exit;
  end;

  if N.NodeType = 'exprCall' then
  begin
    Ent := N.ChildByField('entity');
    Args:= N.ChildByField('args');
    // The bare intrinsics, and ONLY with an argument list -- see the const
    // block for why the argument requirement is what keeps `Reset;` out.
    if (not Args.IsNull) and (Args.NamedChildCount > 0) then
      if MatchText(IdentText(Ent), TOUCH_BARE_FILE) then AFlags.FileSys:= True;
    WalkTouches(Ent, ASrc, AFlags);
    if not Args.IsNull then
      for I:= 0 to Args.NamedChildCount - 1 do
        WalkTouches(Args.NamedChild(I), ASrc, AFlags);
    Exit;
  end;

  for I:= 0 to N.NamedChildCount - 1 do
    WalkTouches(N.NamedChild(I), ASrc, AFlags);
end;

// v(ADP3 T13): the external surfaces and transaction verbs one routine body
// reaches, as the stored wire string 'resources|transactions' -- for example
// 'file system, registry|starts, commits'. EITHER SIDE MAY BE EMPTY and the
// separator is always present when anything was found ('file system|',
// '|starts, commits'); '' when nothing was. The renderer splits on '|' and
// omits an empty side, so the two display lines stay independent while the
// column stays single. Categories and verbs are emitted in a FIXED order, never
// discovery order, so the same code always produces the same bytes.
function AnalyzeTouches(const ABody: TTSNode; const ASrc: TBytes): string;
var
  Flags: TTouchFlags;
  Res  : string     ;
  Txn  : string     ;

  procedure AddTo(var ATarget: string; const AWord: string);
  begin
    if ATarget <> '' then ATarget:= ATarget + ', ';
    ATarget:= ATarget + AWord;
  end;

begin
  Result:= '';
  if ABody.IsNull then Exit;
  Flags:= Default(TTouchFlags);
  WalkTouches(ABody, ASrc, Flags);

  Res:= '';
  if Flags.FileSys  then AddTo(Res, 'file system');
  if Flags.Registry then AddTo(Res, 'registry');
  if Flags.Network  then AddTo(Res, 'network');

  Txn:= '';
  if Flags.TxnStart    then AddTo(Txn, 'starts');
  if Flags.TxnCommit   then AddTo(Txn, 'commits');
  if Flags.TxnRollback then AddTo(Txn, 'rolls back');

  if (Res = '') and (Txn = '') then Exit;
  Result:= Res + '|' + Txn;
end;

// ADP2 T6: process-wide, SINGLE-ENTRY memoized cache of one .dfm's parsed
// event-binding map: HandlerName (lowercased key) -> display 'ObjectName.
// EventProp'. Re-parses ONLY when GDfmCachePath differs from the requested
// ADfmPath -- deliberately NOT a per-path TDictionary (unlike TAstParseCache,
// DRagLint.Diagnostics.ParseCache, which keeps one entry PER FILE until its
// own Clear is called): a routine's own .dfm sibling never changes mid-file,
// and the indexer's facts loop (DRagLint.Core.Indexer.IndexFile) processes
// one file's routines CONSECUTIVELY before moving to the next file's ('--jobs'
// parallelizes across whole SECTIONS/DBs, never within one file's own
// sequential symbol loop -- the SAME sequential-processing assumption
// TAstParseCache's per-process cache already relies on, see its own header
// comment), so in practice this parses each distinct .dfm exactly ONCE per
// index run: every OTHER routine in the SAME unit reuses the cached map: the
// analyzer moves on to a DIFFERENT file's .dfm only after the current file's
// last routine, at which point the single entry is simply overwritten (never
// grows, so no per-file Clear is needed to bound memory -- unlike
// TAstParseCache, which DOES accumulate one tree per file until the indexer
// calls Clear after each file's facts pass).
//
// Reads the .dfm's bytes directly (TFile.ReadAllBytes, UNTRANSCODED) rather
// than via EnsureUtf8Bytes (DRagLint.Core.Encoding, what the indexer's OWN
// generic IndexFile pipeline applies before handing bytes to ANY IParser,
// including TDFMParser): EnsureUtf8Bytes' UTF-16-BOM sniff treats a leading
// $FF as a (possible) UTF-16LE BOM marker, which would risk mis-transcoding
// -- and so defeating -- a REAL binary DFM's own leading-$FF signature before
// ExtractDfmEventBindings ever gets to check it. This analyzer's .dfm read is
// independent of that pipeline (the .dfm may not even be a walked/indexed
// file in this run at all -- it is read purely as ASym's sibling), so
// reading raw bytes and letting ExtractDfmEventBindings apply its own
// binary-DFM guard on the UNMODIFIED first byte is the safer choice; event-
// binding identifiers are always plain ASCII regardless, so no real-world
// text DFM loses fidelity here.
var
  GDfmCachePath: string                    ;
  GDfmCacheMap : TDictionary<string,string>;

function DfmEventMapFor(const ADfmPath: string): TDictionary<string,string>;
var
  Bindings: TArray<TDfmEventBinding>;
  EB      : TDfmEventBinding        ;
  Key     : string                  ;
begin
  if (GDfmCacheMap <> nil) and SameText(GDfmCachePath, ADfmPath) then Exit(GDfmCacheMap);

  FreeAndNil(GDfmCacheMap);
  GDfmCachePath:= ADfmPath;
  GDfmCacheMap := TDictionary<string,string>.Create;

  Bindings:= nil;
  try
    Bindings:= ExtractDfmEventBindings(TFile.ReadAllBytes(ADfmPath));
  except
    Bindings:= nil; // unreadable/unparseable .dfm -- absence over a wrong fact
  end;
  for EB in Bindings do
  begin
    Key:= LowerCase(EB.HandlerName);
    // First wiring wins: deterministic (ExtractDfmEventBindings returns
    // bindings in DOCUMENT order), matches this task's documented tie-break
    // for the rare case of one handler shared by multiple controls/events.
    if not GDfmCacheMap.ContainsKey(Key) then
      GDfmCacheMap.Add(Key, EB.ObjectName + '.' + EB.EventProp);
  end;
  Result:= GDfmCacheMap;
end;

// ADP2 T6: the DfmEvent fact for ASym -- '' when ASym has no owning class (a
// free routine can never be a DFM event handler: the .dfm always wires a
// handler to a METHOD of the form/frame class), the paired .dfm does not
// exist on disk (most units are not forms), or no On*-property in that .dfm
// happens to be wired to a method named ASym.Name. NAME-BASED (like
// DRagLint.Wiring's FindEventHandlersForForm/the underlying 'event-binding'
// reference): the owning class is not cross-checked against the .dfm's own
// root object's declared type, so two DIFFERENT classes in the same unit
// sharing a same-named method would both read back the same wiring -- an
// accepted, documented heuristic limitation (real forms declare each event
// handler once; this mirrors the existing event-binding mechanism's own
// scope, not a NEW gap this task introduces).
function AnalyzeDfmEvent(const ASym: TSymbol; const AFilePath: string): string;
var
  DfmPath: string;
  Map    : TDictionary<string,string>;
begin
  Result:= '';
  if ASym.ParentId <= 0 then Exit;
  DfmPath:= ChangeFileExt(AFilePath, '.dfm');
  if not TFile.Exists(DfmPath) then Exit;
  Map:= DfmEventMapFor(DfmPath);
  if Map = nil then Exit;
  Map.TryGetValue(LowerCase(ASym.Name), Result);
end;

// ADP2 T7: SQL tables touched -- for a routine whose body builds a SQL
// statement via string literals (a common FireDAC/BDE pattern: 'SqlText :=
// ''SELECT * FROM OPTRLIST WHERE ...'';' or 'Query.SQL.Add(''UPDATE
// PDF_SCAN SET ...'');'), which tables it READS (FROM/JOIN) vs. WRITES
// (INSERT INTO/UPDATE/DELETE FROM), mined purely from those literals -- no
// SQL index cross-reference, no DRagLint.Parser.Sql (see this unit's
// banner comment's Task 7 paragraph for why that parser cannot be reused:
// it is Firebird DDL over *.sql SCHEMA-MIGRATION files, and its own header
// states plainly that a trigger/procedure BODY is never parsed for INSERT/
// UPDATE/SELECT references). This is instead a small, NET-NEW, entirely
// local extractor -- deliberately NOT a SQL grammar/parser.
//
// PIPELINE (see each function's own header comment for the full rules):
//   1. WalkSqlLiterals -- walks ONE routine's body (the SAME matched
//      defProc/body node Cyclomatic/AnalyzeReadsWrites already found, no
//      2nd AST scan), finding each maximal string-literal CONCATENATION RUN
//      exactly once (IsTopOfConcatRun avoids re-visiting an already-
//      consumed run's own literal children as spurious separate
//      candidates) and folding it into one string via CollectConcatRun.
//   2. CollectConcatRun best-effort concatenates a run of adjacent
//      '...' + '...' + ... string literals (left-to-right, matching '+'
//      itself being left-associative) into one candidate SQL string. ANY
//      non-literal operand anywhere in the run (a variable, a function
//      call, a typecast -- dynamically-built SQL) marks the WHOLE run
//      dynamic; WalkSqlLiterals then discards it entirely rather than
//      guessing at a partial table list -- "absence over a wrong fact" per
//      the task brief, and the single most important discipline of this
//      whole feature.
//   3. ClassifySqlText -- a run is only even CONSIDERED as SQL when its
//      trimmed text starts (case-insensitively) with SELECT/INSERT/UPDATE/
//      DELETE/WITH AND -- FINAL REVIEW FIX WAVE -- (SELECT/INSERT/UPDATE/
//      DELETE only) passes its own statement type's companion-keyword gate
//      (a top-level FROM for SELECT/DELETE, SET/INTO for UPDATE, INTO for
//      INSERT; see SelectFromIsSqlShaped's banner comment); anything else
//      (a caption, a log message, an unrelated literal -- including an
//      English sentence that merely starts with one of these five words)
//      is silently ignored.
//   4. ExtractSqlTables -- a conservative, keyword-anchored scan for
//      EXACTLY the four clause shapes the task brief specifies (see its own
//      header comment) -- deliberately NOT a SQL grammar/parser: a
//      subquery, a derived table, or a WITH's own CTE body contribute
//      nothing, ever (skip rather than guess). FINAL REVIEW FIX WAVE: every
//      extracted name, reads AND writes, is also dropped when it is a
//      common English stopword/article (IsEnglishStopwordTable) -- catches
//      the residual case where prose happens to be shaped just enough to
//      reach a table token (e.g. 'Select a file from the list' passes the
//      FROM gate above, but the word right after FROM is 'THE').
// AnalyzeSqlTables (below) is the entry point that ties the pipeline
// together and produces the final capped/deduped/sorted display CSVs,
// exactly like JoinCappedDisplay already does for ReadsFields/WritesFields/
// CoveredBy.

// SQL_TABLE_CAP: display cap for the SQL reads/writes fact -- mirrors
// FIELD_RW_CAP's convention (a dedicated const per fact group, not shared)
// at the SAME value (8): the task brief's own "(e.g. 8)" suggestion.
const
  SQL_TABLE_CAP = 8;

// Whole-word SQL clause keywords that can legitimately follow a table
// reference in a FROM/JOIN/UPDATE/INSERT-INTO clause -- used by
// ScanTableRef to tell a genuine bare alias ('FROM OPTRLIST o') apart from
// the START OF THE NEXT CLAUSE ('FROM OPTRLIST WHERE ...', where 'WHERE' is
// never an alias). AWord must already be uppercase (every function in this
// pipeline works on an upper-cased copy of the SQL text throughout -- see
// ExtractSqlTables). Deliberately a small, fixed, deterministic list (no
// attempt at full SQL-keyword coverage) -- mirrors DRagLint.Doc.Facts.
// IsCallSkipWord's own local-const keyword-list pattern: this extractor is
// a bounded heuristic, not a grammar.
function IsSqlClauseStopword(const AWord: string): Boolean;
const
  STOP: array[0..18] of string = (
    'WHERE', 'JOIN', 'INNER', 'LEFT', 'RIGHT', 'OUTER', 'FULL', 'CROSS',
    'ON', 'GROUP', 'ORDER', 'HAVING', 'UNION', 'SET', 'VALUES',
    'RETURNING', 'INTO', 'FOR', 'WITH');
begin
  Result:= False;
  for var W in STOP do
    if AWord = W then Exit(True);
end;

// True when C can continue a SQL identifier token on the ALREADY-UPPERCASED
// text this whole extractor works on (see ExtractSqlTables): letters/
// digits/underscore. '.' (a schema-qualified name's separator) is handled
// separately by ScanSqlIdent, not here, since it is valid mid-token but
// never as the first character.
function IsSqlIdentChar(C: Char): Boolean;
begin
  Result:= (C = '_') or ((C >= 'A') and (C <= 'Z')) or ((C >= '0') and (C <= '9'));
end;

// Reads one identifier token -- letters/digits/underscore, '.' allowed
// MID-token for a 'schema.table' reference (kept whole; see ExtractSqlTables'
// header comment for why the whole dotted name is the chosen convention) --
// starting at S[APos] after skipping leading spaces; advances APos past it.
// Returns '' (APos left just past any skipped spaces, at the first non-
// identifier-start character) when nothing identifier-shaped is there -- a
// subquery's '(', end of string, a stray comma -- the caller's cue to stop
// rather than guess (absence over a wrong table).
function ScanSqlIdent(const S: string; var APos: Integer): string;
var Start, N: Integer;
begin
  N:= Length(S);
  while (APos <= N) and (S[APos] = ' ') do Inc(APos);
  Result:= '';
  if (APos > N) or not ((S[APos] = '_') or ((S[APos] >= 'A') and (S[APos] <= 'Z'))) then Exit;
  Start:= APos;
  while (APos <= N) and (IsSqlIdentChar(S[APos]) or (S[APos] = '.')) do Inc(APos);
  Result:= Copy(S, Start, APos - Start);
end;

// Reads ONE table reference at APos (already positioned right after a
// FROM/JOIN/INTO/UPDATE keyword + whitespace): the identifier itself, plus
// an optional single trailing alias word -- bare ('FROM OPTRLIST o') or
// 'AS'-prefixed ('FROM OPTRLIST AS o') -- consumed and discarded UNLESS
// that word is itself a recognized SQL clause keyword (IsSqlClauseStopword),
// in which case APos is rolled back to just past the table identifier so
// the caller's own clause-boundary scan sees it untouched (it is the START
// of the NEXT clause, e.g. 'WHERE', not an alias). Returns '' (APos
// unchanged from entry, aside from a leading-space skip) when no identifier
// follows at all -- e.g. a derived table '(SELECT ...)' -- the caller
// simply skips this occurrence; never guesses.
function ScanTableRef(const S: string; var APos: Integer): string;
var Saved: Integer; Word1: string;
begin
  Result:= ScanSqlIdent(S, APos);
  if Result = '' then
  begin
    Exit;
  end;
  Saved:= APos;
  Word1:= ScanSqlIdent(S, APos);
  if Word1 = '' then
  begin
    APos:= Saved;
    Exit;
  end;
  if Word1 = 'AS' then
  begin
    Saved:= APos;
    if ScanSqlIdent(S, APos) = '' then
    begin
      APos:= Saved; // bare 'AS' with nothing after -- harmless no-op
    end;
  end
  else
  begin
    if IsSqlClauseStopword(Word1) then
    begin
      APos:= Saved; // Word1 starts the NEXT clause -- not an alias, leave it unconsumed
    end;
    // else: a bare alias -- ScanSqlIdent already advanced APos past it, nothing more to do
  end;
end;

// Reads a comma-separated list of table refs starting at APos (right after
// a FROM keyword's own whitespace): each entry is ScanTableRef (identifier +
// optional alias). Stops -- keeping whatever was already collected -- at the
// first position that is not a valid table ref, or once no further comma
// follows. AAllowList=False reads AT MOST one entry: a JOIN/INSERT-INTO/
// UPDATE/DELETE-FROM target is always singular; only a FROM clause's
// comma-list shorthand ('FROM A, B') needs more than one.
function ScanTableRefList(const S: string; var APos: Integer; AAllowList: Boolean): TArray<string>;
var Acc: TStringList; Tbl: string; Saved, N: Integer;
begin
  Acc:= TStringList.Create;
  try
    Tbl:= ScanTableRef(S, APos);
    if Tbl <> '' then Acc.Add(Tbl);
    N:= Length(S);
    while AAllowList and (Tbl <> '') do
    begin
      Saved:= APos;
      while (APos <= N) and (S[APos] = ' ') do Inc(APos);
      if (APos <= N) and (S[APos] = ',') then
      begin
        Inc(APos);
        Tbl:= ScanTableRef(S, APos);
        if Tbl <> '' then Acc.Add(Tbl) else begin APos:= Saved; Break; end;
      end
      else begin APos:= Saved; Break; end;
    end;
    Result:= Acc.ToStringArray;
  finally
    Acc.Free;
  end;
end;

// Finds the next WHOLE-WORD occurrence of AWord (both AText and AWord
// assumed already uppercased by the caller -- see ExtractSqlTables -- so
// this is a plain ordinal search, no case-folding/regex engine involved) in
// AText at or after AFrom (1-based). A match's immediate neighbor
// characters (if any) must NOT themselves be identifier characters, so
// 'FROM' does not match inside 'XFROM' or 'FROMAGE'. Returns 0 when not
// found.
function FindSqlKeyword(const AText, AWord: string; AFrom: Integer): Integer;
var P, L, TL: Integer; Before, After: Char;
begin
  Result:= 0;
  L:= Length(AWord);
  TL:= Length(AText);
  P:= AFrom;
  if P < 1 then P:= 1;
  while P <= TL - L + 1 do
  begin
    if Copy(AText, P, L) = AWord then
    begin
      if P = 1 then Before:= #0 else Before:= AText[P - 1];
      if P + L > TL then After:= #0 else After:= AText[P + L];
      if (not IsSqlIdentChar(Before)) and (not IsSqlIdentChar(After)) then Exit(P);
    end;
    Inc(P);
  end;
end;

// FIX (Phase 2 T7 review): returns the parenthesis nesting depth at 1-based
// position APos in AText -- the count of '(' not yet closed by a ')'
// anywhere in AText[1..APos-1]. Used by ExtractSqlTables' SELECT branch and
// SelectFromIsSqlShaped (below) to tell a TOP-LEVEL FROM/JOIN (a real table
// source) apart from one nested inside a function call's argument list --
// Firebird's EXTRACT(part FROM value), SUBSTRING(value FROM start [FOR
// len]), TRIM([...] FROM value) all take a FROM keyword that names an
// EXPRESSION, never a table -- or inside a subquery/derived table. A plain
// left-to-right count, not string-literal-aware: well-formed SQL is always
// paren-balanced, so this is exact for every real query; a malformed/
// unbalanced input is out of scope for this bounded heuristic (best-effort,
// same "absence over a wrong table" discipline as the rest of this unit).
function ParenDepthAt(const AText: string; APos: Integer): Integer;
var I: Integer;
begin
  Result:= 0;
  for I:= 1 to APos - 1 do
  begin
    if AText[I] = '(' then Inc(Result)
    else if AText[I] = ')' then Dec(Result);
  end;
end;

// FIX (Phase 2 T7 review): True when, at 1-based position APos in the
// already-uppercased AText, the remainder is a genuine SQL CLAUSE BOUNDARY:
// end of string, a statement terminator (';'), a closing paren (')' -- a
// derived table/subquery/function-call argument list ending), a list
// separator (','), or a recognized clause keyword (IsSqlClauseStopword) --
// NOT more ordinary words. Used by SelectFromIsSqlShaped's prose gate
// (below) to tell a genuine table reference's tail apart from a sentence
// that merely happens to look SQL-shaped up to that point.
function AtSqlClauseBoundary(const AText: string; APos: Integer): Boolean;
var N, P: Integer; Word: string;
begin
  N:= Length(AText);
  P:= APos;
  while (P <= N) and (AText[P] = ' ') do Inc(P);
  if P > N then Exit(True);
  if (AText[P] = ';') or (AText[P] = ')') or (AText[P] = ',') then Exit(True);
  Word:= ScanSqlIdent(AText, P);
  Result:= (Word <> '') and IsSqlClauseStopword(Word);
end;

// FINAL REVIEW FIX WAVE banner (both gaps EMPIRICALLY reproduced against the
// built exe -- reviewer's own repro strings quoted throughout below): the
// companion-keyword gates SelectFromIsSqlShaped/UpdateIsSqlShaped/
// InsertIntoIsSqlShaped/DeleteFromIsSqlShaped (this function and the three
// immediately after it) are the CLASSIFICATION-time half of a two-part fix;
// IsEnglishStopwordTable (see ExtractSqlTables' own header comment, below)
// is the EXTRACTION-time other half. Symmetric, conservative, per-statement
// -type requirement: a literal is only ever classified as SQL when it ALSO
// contains its statement type's own mandatory companion clause keyword --
// SELECT needs a top-level FROM, UPDATE needs a top-level SET (or, for the
// Firebird 'UPDATE OR INSERT' UPSERT form, a top-level INTO), INSERT needs
// a top-level INTO, DELETE needs a top-level FROM -- exactly the clause
// every REAL Firebird statement of that shape always has. An ordinary
// English sentence that merely starts with one of these five verbs (a UI
// status message/prompt -- e.g. 'Update complete for your profile', 'Delete
// the old record') essentially never also happens to contain its own verb's
// companion keyword, so requiring it rejects the whole literal outright --
// the SAME "absence over a wrong fact" discipline this whole extractor
// already follows, now applied to the CLASSIFICATION step, not just
// extraction. WITH (a CTE) is deliberately UNCHANGED (still a bare leading-
// verb check, see ClassifySqlText below) -- out of scope for this fix wave.
//
// FIX (Phase 2 final review): SELECT's own gate, tightened from the
// original Phase 2 T7 review version -- a MISSING top-level FROM used to be
// treated as "inconclusive, let it through" (see the removed Exit(True) this
// replaces, below). Per the companion-keyword rule above, a SELECT with no
// top-level FROM at all is now a hard REJECT (Firebird's own SELECT syntax
// always requires FROM) -- e.g. an English sentence that starts with
// 'Select' but never contains the word 'from' at all is rejected right
// here, before the table-boundary check even runs. When a top-level FROM
// DOES exist, the ORIGINAL T7-review boundary check still applies
// unchanged: AUpper is an already Trim+UpperCase'd candidate ALREADY
// confirmed to start with SELECT; True when the first top-level FROM's own
// table-ref-list (the SAME ScanTableRefList scan ExtractSqlTables' SELECT
// branch performs) is immediately followed by a genuine SQL clause boundary
// (AtSqlClauseBoundary). False -- REJECT the whole literal as SQL -- when a
// top-level FROM IS found but what follows its target is more prose: e.g.
// 'SELECT AN ITEM FROM THE CATALOG BEFORE CONTINUING' scans 'THE' as the
// table (bare alias 'CATALOG' absorbed, exactly as real SQL's own 'FROM
// OPTRLIST o' would be), and the NEXT word is 'BEFORE' -- neither a clause
// keyword nor end-of-string/punctuation -- so the whole literal is
// rejected.
function SelectFromIsSqlShaped(const AUpper: string): Boolean;
var KwPos, Pos: Integer;
begin
  KwPos:= FindSqlKeyword(AUpper, 'FROM', 1);
  while (KwPos <> 0) and (ParenDepthAt(AUpper, KwPos) <> 0) do
    KwPos:= FindSqlKeyword(AUpper, 'FROM', KwPos + Length('FROM'));
  // FIX (Phase 2 final review): no top-level FROM at all -- SELECT REQUIRES
  // one (see the companion-keyword banner above) -- REJECT. Was Exit(True)
  // ("inconclusive, let it through") under the original T7 review version.
  if KwPos = 0 then Exit(False);
  Pos:= KwPos + Length('FROM');
  ScanTableRefList(AUpper, Pos, True); // advance Pos past the FROM-target(s) -- the names themselves are unused here
  Result:= AtSqlClauseBoundary(AUpper, Pos);
end;

// FIX (Phase 2 final review): UPDATE's own companion-keyword gate -- see the
// banner comment above SelectFromIsSqlShaped for the shared rule. Mirrors
// ExtractSqlTables' own UPDATE branch's UPSERT sniff exactly (the word
// immediately after 'UPDATE'): when it is 'OR' (the Firebird 'UPDATE OR
// INSERT INTO <table> ...' UPSERT form), the companion keyword is a
// top-level INTO instead of SET; otherwise a plain UPDATE requires a
// top-level SET. Unlike SELECT's FROM gate, no further "what follows the
// table" boundary check is layered on top: the companion keyword's mere
// PRESENCE at top level is already a strong enough signal on its own here
// -- a genuine English sentence essentially never contains the bare word
// 'SET' or 'INTO' immediately after an update-shaped opener the way 'FROM'
// can appear in casual prose ('an item FROM the catalog'). Reproduced
// against the real built exe: 'Update complete for your profile' has
// neither SET nor INTO anywhere -- rejected.
function UpdateIsSqlShaped(const AUpper: string): Boolean;
var P, KwPos: Integer; Next1: string;
begin
  P:= 1 + Length('UPDATE');
  Next1:= ScanSqlIdent(AUpper, P); // SAME UPSERT sniff as ExtractSqlTables' UPDATE branch
  if Next1 = 'OR' then
  begin
    KwPos:= FindSqlKeyword(AUpper, 'INTO', 1);
    while (KwPos <> 0) and (ParenDepthAt(AUpper, KwPos) <> 0) do
      KwPos:= FindSqlKeyword(AUpper, 'INTO', KwPos + Length('INTO'));
    Exit(KwPos <> 0);
  end;
  KwPos:= FindSqlKeyword(AUpper, 'SET', 1);
  while (KwPos <> 0) and (ParenDepthAt(AUpper, KwPos) <> 0) do
    KwPos:= FindSqlKeyword(AUpper, 'SET', KwPos + Length('SET'));
  Result:= KwPos <> 0;
end;

// FIX (Phase 2 final review): INSERT's own companion-keyword gate, mirroring
// UpdateIsSqlShaped/SelectFromIsSqlShaped above -- see the shared banner
// comment. A real Firebird INSERT statement always has a top-level INTO
// (there is no bare 'INSERT VALUES (...)' form); its absence rejects the
// literal outright.
function InsertIntoIsSqlShaped(const AUpper: string): Boolean;
var KwPos: Integer;
begin
  KwPos:= FindSqlKeyword(AUpper, 'INTO', 1);
  while (KwPos <> 0) and (ParenDepthAt(AUpper, KwPos) <> 0) do
    KwPos:= FindSqlKeyword(AUpper, 'INTO', KwPos + Length('INTO'));
  Result:= KwPos <> 0;
end;

// FIX (Phase 2 final review): DELETE's own companion-keyword gate, mirroring
// the three gates above -- see the shared banner comment. A real Firebird
// DELETE statement always has a top-level FROM (there is no bare 'DELETE
// <table>' form); its absence rejects the literal outright. Reproduced
// against the real built exe: 'Delete the old record', a UI confirmation
// prompt, has no FROM anywhere.
function DeleteFromIsSqlShaped(const AUpper: string): Boolean;
var KwPos: Integer;
begin
  KwPos:= FindSqlKeyword(AUpper, 'FROM', 1);
  while (KwPos <> 0) and (ParenDepthAt(AUpper, KwPos) <> 0) do
    KwPos:= FindSqlKeyword(AUpper, 'FROM', KwPos + Length('FROM'));
  Result:= KwPos <> 0;
end;

// True when, after trimming, AText (case-insensitively) begins with one of
// the five recognized SQL statement keywords -- the PRIMARY signal used to
// decide "this concatenated literal run is SQL" (task brief item 2). FIX
// (Phase 2 T7 review): a leading SELECT is no longer sufficient on its own
// -- it must additionally pass SelectFromIsSqlShaped's prose gate (above),
// since 'SELECT' also opens an ordinary English sentence (e.g. 'SELECT AN
// ITEM FROM THE CATALOG BEFORE CONTINUING', a UI prompt, not SQL) in a way
// none of the other four verbs realistically do. FIX (Phase 2 final
// review): INSERT/UPDATE/DELETE are NO LONGER a bare start-of-string check
// either -- each now additionally passes its OWN companion-keyword gate
// (InsertIntoIsSqlShaped/UpdateIsSqlShaped/DeleteFromIsSqlShaped, above; see
// their shared banner comment above SelectFromIsSqlShaped) for the SAME
// reason SELECT needed one: an ordinary English sentence can start with
// 'Update'/'Insert'/'Delete' too (e.g. 'Update complete for your profile',
// 'Delete the old record' -- both proven WRONG against the real built exe
// before this fix wave). WITH (a CTE) is the only one of the five still a
// bare start-of-string check -- out of scope for this fix wave (see
// ExtractSqlTables' header comment for why a CTE's own body is skipped
// entirely at the extraction step regardless).
function ClassifySqlText(const AText: string): Boolean;
var T, U: string;
begin
  T:= Trim(AText);
  U:= UpperCase(T);
  Result:= (StartsText('SELECT', T) and SelectFromIsSqlShaped(U)) or
           (StartsText('INSERT', T) and InsertIntoIsSqlShaped(U)) or
           (StartsText('UPDATE', T) and UpdateIsSqlShaped(U)) or
           (StartsText('DELETE', T) and DeleteFromIsSqlShaped(U)) or
           StartsText('WITH', T);
end;

// FIX (Phase 2 final review): the EXTRACTION-time half of the two-part fix
// (see SelectFromIsSqlShaped's banner comment, above, for the CLASSIFICATION
// -time half) -- common English stopwords/articles/prepositions that must
// NEVER be treated as a real table name, even though ScanSqlIdent happily
// returns them as syntactically-valid identifiers (plain A-Z tokens). No
// genuine Firebird table in this codebase is ever named THE, A, IS, etc.
// Reproduced against the real built exe: 'Select a file from the list' has
// a genuine top-level FROM (so SelectFromIsSqlShaped's gate lets it
// through), but the word right after FROM is 'THE' -- an article, not a
// table -- which used to render 'SQL: reads THE'. AWord must already be
// uppercase, matching every other helper in this pipeline. Deliberately a
// small, fixed, deterministic list (no attempt at exhaustive English
// coverage) -- mirrors IsSqlClauseStopword's own local-const pattern above.
function IsEnglishStopwordTable(const AWord: string): Boolean;
const
  STOP: array[0..24] of string = (
    'THE', 'A', 'AN', 'AND', 'OR', 'ALL', 'ANY', 'SOME', 'EACH', 'EVERY',
    'YOUR', 'MY', 'OUR', 'THIS', 'THAT', 'THESE', 'THOSE', 'IT', 'IS',
    'ARE', 'TO', 'OF', 'IN', 'ON', 'FOR');
begin
  Result:= False;
  for var W in STOP do
    if AWord = W then Exit(True);
end;

// FIX (Phase 2 final review): the single choke point every Add call in
// ExtractSqlTables (below) routes through, on BOTH the reads and writes
// side, for EVERY statement type -- drops ATbl instead of adding it to
// AList when IsEnglishStopwordTable (above) says it is a common English
// word, never a real table. Centralizing the check here (rather than
// repeating an 'if not IsEnglishStopwordTable(...) then' six times inline)
// means the drop rule cannot accidentally be applied to some call sites and
// missed on others.
procedure AddSqlTable(AList: TStringList; const ATbl: string);
begin
  if not IsEnglishStopwordTable(ATbl) then AList.Add(ATbl);
end;

// ADP2 T7: extracts table references from ASql (an ALREADY-CONFIRMED-SQL
// string, per ClassifySqlText) into AReads/AWrites (UPPERCASED; caller
// dedupes/sorts/caps). Deliberately NOT a SQL grammar: exactly the four
// clause shapes the task brief lists, each a bounded keyword-anchored scan
// -- anything else (a subquery, a CTE body, an identifier this cannot
// resolve) contributes nothing, never a guessed table:
//   FROM <table>[, <table>...] / JOIN <table> -> AReads (a SELECT-like
//     statement), but ONLY at parenthesis depth 0 (FIX, Phase 2 T7 review --
//     see ParenDepthAt's header comment): a FROM/JOIN nested inside a
//     function call's argument list (Firebird's EXTRACT(part FROM value),
//     SUBSTRING(value FROM start [FOR len]), TRIM([...] FROM value)) or
//     inside a subquery/derived table is never treated as a table source.
//     A comma-list after FROM is supported (ScanTableRefList's AAllowList);
//     JOIN never takes one (real SQL doesn't allow it there).
//   INSERT INTO <table> -> AWrites.
//   Firebird 'UPDATE OR INSERT INTO <table>' (the UPSERT statement this
//     Firebird 4.0 codebase's own stack uses -- see C:\Projects\CLAUDE.md)
//     -> AWrites, via the SAME INTO-anchored scan as plain INSERT. Detected
//     by checking whether the WORD IMMEDIATELY after 'UPDATE' is literally
//     'OR' (a precise, adjacent check -- NOT "does the string contain
//     INSERT anywhere", which would misfire on an ordinary UPDATE whose
//     WHERE/SET values happen to mention the word 'insert').
//   UPDATE <table> -> AWrites.
//   DELETE FROM <table> -> AWrites.
//   (UPDATE/INSERT/DELETE, unlike SELECT's FROM/JOIN loop above, are NOT
//     vulnerable to the same nesting issue -- sanity-checked, Phase 2 T7
//     review, not just assumed: each anchors on the FIRST occurrence of its
//     own target keyword, found starting AT/right after the routine's own
//     leading verb -- itself at position 1, i.e. already depth 0 -- then
//     Exits immediately. None of the three ever loops to find EVERY
//     occurrence the way the SELECT branch's FROM/JOIN scan does, so a
//     deeper-nested FROM/INTO elsewhere in the same string, e.g. inside a
//     WHERE/SET clause's own subquery, is never reached.)
// A leading 'WITH' (a CTE) is recognized as SQL by ClassifySqlText but
// deliberately SKIPPED here entirely: a CTE's own named subqueries are not
// real tables, and telling a CTE alias apart from a genuine table reference
// in the statement's trailing body would need real parsing -- out of scope
// for a "simple, conservative" extractor; absence over a wrong table.
// EVERY captured name is kept as the WHOLE matched token (schema.table
// stays dotted, never truncated to its final segment -- the task brief's
// "pick one, be consistent" choice) and normalized upper-case (this
// extractor works entirely on an upper-cased copy of ASql throughout, so
// every captured substring is already upper-case with no separate
// normalization step needed). FIX (Phase 2 final review): every captured
// name, reads AND writes, additionally passes through AddSqlTable (above),
// which silently drops it instead when it is a common English stopword/
// article (IsEnglishStopwordTable) -- see AddSqlTable's own header comment.
procedure ExtractSqlTables(const ASql: string; AReads, AWrites: TStringList);
var
  Upper : string;
  Pos   : Integer;
  KwPos : Integer;
  Tbl   : string;
  P     : Integer;
  Next1 : string;
  Refs  : TArray<string>;
begin
  Upper:= UpperCase(Trim(ASql));
  if Upper = '' then Exit;

  if FindSqlKeyword(Upper, 'WITH', 1) = 1 then Exit; // CTE -- conservative skip, see header comment

  if FindSqlKeyword(Upper, 'UPDATE', 1) = 1 then
  begin
    P:= 1 + Length('UPDATE');
    Next1:= ScanSqlIdent(Upper, P); // may be 'OR' (Firebird UPSERT) or the plain UPDATE target
    if Next1 = 'OR' then
    begin
      KwPos:= FindSqlKeyword(Upper, 'INTO', P);
      if KwPos > 0 then
      begin
        Pos:= KwPos + Length('INTO');
        for Tbl in ScanTableRefList(Upper, Pos, False) do AddSqlTable(AWrites, Tbl);
      end;
    end
    else
    begin
      Pos:= 1 + Length('UPDATE');
      for Tbl in ScanTableRefList(Upper, Pos, False) do AddSqlTable(AWrites, Tbl);
    end;
    Exit;
  end;

  if FindSqlKeyword(Upper, 'INSERT', 1) = 1 then
  begin
    KwPos:= FindSqlKeyword(Upper, 'INTO', 1);
    if KwPos > 0 then
    begin
      Pos:= KwPos + Length('INTO');
      for Tbl in ScanTableRefList(Upper, Pos, False) do AddSqlTable(AWrites, Tbl);
    end;
    Exit;
  end;

  if FindSqlKeyword(Upper, 'DELETE', 1) = 1 then
  begin
    KwPos:= FindSqlKeyword(Upper, 'FROM', 1);
    if KwPos > 0 then
    begin
      Pos:= KwPos + Length('FROM');
      for Tbl in ScanTableRefList(Upper, Pos, False) do AddSqlTable(AWrites, Tbl);
    end;
    Exit;
  end;

  if FindSqlKeyword(Upper, 'SELECT', 1) = 1 then
  begin
    KwPos:= 1;
    repeat
      KwPos:= FindSqlKeyword(Upper, 'FROM', KwPos);
      if KwPos = 0 then Break;
      Pos:= KwPos + Length('FROM');
      Refs:= ScanTableRefList(Upper, Pos, True);
      // FIX (Phase 2 T7 review): only a TOP-LEVEL (paren-depth 0) FROM is a
      // real table source -- see ParenDepthAt's header comment. A nested one
      // (EXTRACT/SUBSTRING/TRIM's own FROM argument, or a subquery's FROM)
      // still advances Pos (above) so the outer search resumes past it, but
      // never contributes a table.
      if ParenDepthAt(Upper, KwPos) = 0 then
        for Tbl in Refs do AddSqlTable(AReads, Tbl);
      KwPos:= Pos; // resume the keyword search right after this FROM's own list
    until False;

    KwPos:= 1;
    repeat
      KwPos:= FindSqlKeyword(Upper, 'JOIN', KwPos);
      if KwPos = 0 then Break;
      Pos:= KwPos + Length('JOIN');
      Refs:= ScanTableRefList(Upper, Pos, False);
      if ParenDepthAt(Upper, KwPos) = 0 then // FIX: same top-level guard as FROM, above
        for Tbl in Refs do AddSqlTable(AReads, Tbl);
      KwPos:= Pos;
    until False;
  end;
end;

// Unescapes a literalString's raw source text (outer quotes stripped,
// doubled '''' unescaped to '). Duplicated from DRagLint.Parser.Delphi13's
// own private HarvestStringLiterals.DecodeLiteral (not exported -- this
// unit already keeps its own small AST-text helpers rather than reaching
// into another unit for a three-line function; see FieldNodeStr's header
// comment for the same "keep this unit standalone" precedent). #nn escapes
// and string continuations are OUT OF SCOPE, exactly like the parser's own
// decoder -- a SQL literal built with either is rare and this fact is
// best-effort.
function DecodeSqlLiteral(const ARaw: string): string;
begin
  Result:= ARaw;
  if (Length(Result) >= 2) and (Result[1] = '''') and (Result[Length(Result)] = '''') then
    Result:= Copy(Result, 2, Length(Result) - 2);
  Result:= StringReplace(Result, '''''', '''', [rfReplaceAll]);
end;

// True when N is an 'exprBinary' node whose operator TEXT is literally '+'
// (string/set/number concatenation-or-addition -- this extractor only ever
// keeps the result when it turns out to be pure string literals, via
// CollectConcatRun, so a numeric '+' simply yields ADynamic=True there and
// is harmlessly discarded).
function IsPlusBinary(const N: TTSNode; const ASrc: TBytes): Boolean;
var Op: TTSNode;
begin
  Result:= False;
  if N.IsNull or (N.NodeType <> 'exprBinary') then Exit;
  Op:= N.ChildByField('operator');
  if Op.IsNull then Exit;
  Result:= Trim(FieldNodeStr(Op, ASrc)) = '+';
end;

// True when N is the TOP of a string-literal concatenation run -- the one
// point in the tree WalkSqlLiterals should process it from (see that
// procedure's header comment for why the run's own descendants must not be
// separately re-visited): either a bare 'literalString' whose parent is NOT
// a '+' exprBinary (a standalone literal argument/assignment RHS, e.g.
// Query.SQL.Add('SELECT ...')), or an exprBinary('+') whose parent is NOT
// ALSO a '+' exprBinary (the head of an 'a' + 'b' + 'c' chain -- a NESTED
// '+' node, reached only from inside that same chain, answers False here:
// it is consumed when CollectConcatRun walks down from its parent instead).
function IsTopOfConcatRun(const N: TTSNode; const ASrc: TBytes): Boolean;
var Par: TTSNode;
begin
  Result:= False;
  if N.NodeType = 'literalString' then
  begin
    Par:= N.Parent;
    Result:= Par.IsNull or not IsPlusBinary(Par, ASrc);
    Exit;
  end;
  if IsPlusBinary(N, ASrc) then
  begin
    Par:= N.Parent;
    Result:= Par.IsNull or not IsPlusBinary(Par, ASrc);
  end;
end;

// Recursively collects a string-literal CONCATENATION RUN under N (a
// 'literalString' leaf, an exprBinary('+') chain, or an exprParens wrapping
// either) into AText, IN LEFT-TO-RIGHT ORDER (lhs visited before rhs,
// matching '+''s own left-associative grammar). Sets ADynamic:=True the
// moment ANY operand anywhere in the run is not itself a plain string
// literal, a further '+' node, or a parenthesized wrapper of one -- a
// variable, a function call, a typecast, a number, any other operator --
// "a non-literal operand -> DYNAMIC sql, skip the run, do not guess" per
// the task brief. Recursion does not short-circuit the instant a dynamic
// operand is found (harmless extra work bounded by one routine body's own
// size) -- simpler than plumbing an early-exit through the two-sided
// recursive descent, and AText is only ever consulted by the caller
// (WalkSqlLiterals) once ADynamic comes back False.
procedure CollectConcatRun(const N: TTSNode; const ASrc: TBytes; var AText: string; var ADynamic: Boolean);
begin
  if N.IsNull then begin ADynamic:= True; Exit; end;
  if N.NodeType = 'literalString' then
  begin
    AText:= AText + DecodeSqlLiteral(FieldNodeStr(N, ASrc));
    Exit;
  end;
  if N.NodeType = 'exprParens' then
  begin
    if N.NamedChildCount >= 1 then
      CollectConcatRun(N.NamedChild(0), ASrc, AText, ADynamic)
    else
      ADynamic:= True;
    Exit;
  end;
  if IsPlusBinary(N, ASrc) then
  begin
    CollectConcatRun(N.ChildByField('lhs'), ASrc, AText, ADynamic);
    CollectConcatRun(N.ChildByField('rhs'), ASrc, AText, ADynamic);
    Exit;
  end;
  ADynamic:= True; // an identifier, exprCall, exprDot, a number, a non-'+' exprBinary, ...
end;

// Walks ABody top-down, finding each maximal string-literal-concatenation
// RUN (IsTopOfConcatRun) exactly once and -- when its assembled text
// (CollectConcatRun) is not dynamic and looks like SQL (ClassifySqlText) --
// extracting its table references (ExtractSqlTables) into AReads/AWrites.
// Never re-descends into an already-processed run's own children (a run is
// handled in full, then this procedure Exits for that subtree) -- so a
// nested literal fragment (e.g. just ' FROM ' on its own, part of a bigger
// run) is never independently mis-treated as a second, unrelated
// candidate. Mirrors DRagLint.Diagnostics.AstChecks.CyclomaticCountDecisions'
// own 'defProc' guard: a NESTED local routine's own body is analyzed
// separately (when IT is indexed as its own symbol), never folded into the
// ENCLOSING routine's SQL facts. Uses ChildCount/Child (ALL children, not
// just named), matching HarvestStringLiterals' (DRagLint.Parser.Delphi13)
// own proven-safe traversal for finding every literalString regardless of
// its ancestor node shape (assignment/exprCall/args/...).
procedure WalkSqlLiterals(const N: TTSNode; const ASrc: TBytes; AReads, AWrites: TStringList);
var
  Text     : string ;
  { Named IsDynamic, not Dynamic. `dynamic` is a Delphi CONTEXT-SENSITIVE
    keyword -- legal as an identifier, and a method directive elsewhere -- and
    the vendored tree-sitter grammar treats it as reserved outright. So this one
    declaration made drag-lint fail to parse its OWN source, and it was the
    source of 2 of the 3 error-severity findings in the entire self-lint.

    This is a WORKAROUND, not the fix. The grammar is the thing that is wrong,
    and it stays wrong for every other codebase that names a variable Dynamic;
    the parser is shipped here as a prebuilt library with no grammar sources in
    the tree, so correcting it needs an upstream regeneration this repo cannot
    currently do. Logged as an `unsupported` gap. Renaming buys drag-lint a
    clean parse of itself and buys nothing for anyone else. }
  IsDynamic: Boolean;
  I        : Integer;
begin
  if N.IsNull then Exit;
  if N.NodeType = 'defProc' then Exit; // nested routine -- analyzed separately, on its own
  if IsTopOfConcatRun(N, ASrc) then
  begin
    Text:= '';
    IsDynamic:= False;
    CollectConcatRun(N, ASrc, Text, IsDynamic);
    if (not IsDynamic) and ClassifySqlText(Text) then
      ExtractSqlTables(Text, AReads, AWrites);
    Exit; // never re-descend into an already-consumed run
  end;
  for I:= 0 to N.ChildCount - 1 do
    WalkSqlLiterals(N.Child(I), ASrc, AReads, AWrites);
end;

// ADP2 T7: fills ASqlReadsCsv/ASqlWritesCsv (capped, display-ready CSV
// strings -- the SAME JoinCappedDisplay format ReadsFields/WritesFields/
// CoveredBy already use) for one routine: table names mined from SQL
// string literals built in its OWN body. ABody is the SAME defProc.body
// node Analyze already matched for Cyclomatic/AnalyzeReadsWrites -- no
// second AST scan; ASrc is the file's own byte buffer from TAstParseCache
// (UTF-8, matching every other AST-text helper in this unit).
//
// Deduped + SORTED (TStringList Sorted/CaseInsensitive/dupIgnore, mirroring
// ComputeCoveredBy's Names list) for deterministic output regardless of
// literal encounter order or which run found a table first, then capped at
// SQL_TABLE_CAP via JoinCappedDisplay. '' for both when ABody is null (no
// matching defProc -- same "absence over a wrong fact" contract Cyclomatic/
// ReadsFields already follow) or the routine simply builds no recognizable
// SQL at all.
procedure AnalyzeSqlTables(const ABody: TTSNode; const ASrc: TBytes; out ASqlReadsCsv, ASqlWritesCsv: string);
var
  ReadSet, WriteSet    : TStringList  ;
  ReadsList, WritesList: TList<string>;
begin
  ASqlReadsCsv := '';
  ASqlWritesCsv:= '';
  if ABody.IsNull then Exit;

  ReadSet := TStringList.Create;
  WriteSet:= TStringList.Create;
  try
    ReadSet.Sorted := True; ReadSet.Duplicates := dupIgnore; ReadSet.CaseSensitive := False;
    WriteSet.Sorted:= True; WriteSet.Duplicates:= dupIgnore; WriteSet.CaseSensitive:= False;

    WalkSqlLiterals(ABody, ASrc, ReadSet, WriteSet);

    if (ReadSet.Count = 0) and (WriteSet.Count = 0) then Exit;

    ReadsList := TList<string>.Create;
    WritesList:= TList<string>.Create;
    try
      ReadsList.AddRange(ReadSet.ToStringArray);
      WritesList.AddRange(WriteSet.ToStringArray);
      ASqlReadsCsv := JoinCappedDisplay(ReadsList, SQL_TABLE_CAP);
      ASqlWritesCsv:= JoinCappedDisplay(WritesList, SQL_TABLE_CAP);
    finally
      WritesList.Free;
      ReadsList.Free;
    end;
  finally
    WriteSet.Free;
    ReadSet.Free;
  end;
end;

// ADP2 T8: returned-object ownership -- see this unit's banner comment
// (Task 8 paragraph) for the full ruleset/rationale. Duplicated locally
// (NOT reused from DRagLint.Doc.Facts' own private ParseReturnType, which
// is the IDENTICAL algorithm): Doc.Facts already `uses` THIS unit (for
// ComputeCoveredBy), so the reverse direction would be a real circular unit
// dependency -- the same "keep this unit standalone" precedent FieldNodeStr/
// LastSegment (above) already follow for the identical reason. Parses the
// return type from a signature of the form '(args): RetType' or ': RetType'
// (ProcSignatureOf's own format, DRagLint.Parser.Delphi13) -- the text after
// the LAST ':' that is outside the parameter parentheses. '' for a
// procedure/constructor/destructor signature (no such trailing ': Type').
function ParseReturnType(const ASig: string): string;
var CloseP, Colon: Integer;
begin
  Result:= '';
  CloseP:= ASig.LastDelimiter(')');
  Colon := ASig.LastDelimiter(':');
  if (Colon > CloseP) and (Colon >= 0) then
    Result:= Trim(Copy(ASig, Colon + 2, MaxInt)).TrimRight([';']);
end;

// ADP2 T8: object-type gate for the 'borrowed'/'self' verdicts (task brief
// step 5) -- a wrong 'borrowed'/'self' on a VALUE-returning function (e.g.
// 'function Count: Integer; begin Result := FCount; end;') is nonsense, so
// those two verdicts additionally require the function's OWN return type
// (ATypeName, already parsed via ParseReturnType) to be a REFERENCE type.
// 'new' needs no such gate -- 'T.Create' already guarantees an object.
// TWO-TIER check, per the task brief's own documented conservative
// heuristic:
//   1. STORE-RESOLVED (preferred): ATypeName's bare, unqualified segment
//      names a class or interface symbol somewhere in the index -- ground
//      truth, no guessing. FIX (Phase 2 T8 review, Fix 2): a store-resolved
//      skRecord/skEnum is likewise ground truth, but a NEGATIVE -- a Pascal
//      record/enum is a value type, so 'borrowed'/'self' would be just as
//      nonsensical for it as for Integer. The ORIGINAL loop only ever
//      short-circuited on the POSITIVE match (skClass/skInterface), so a
//      resolved skRecord fell through unnoticed to tier 2's T/I-prefix
//      heuristic below and could be wrongly accepted there (e.g. 'TMyRec =
//      record ... end;' starts with 'T'); the loop now Exits(False)
//      immediately on skRecord/skEnum too, so tier 2 is reached ONLY when
//      the store did not resolve the name to any of these four kinds at all
//      (a genuinely un-indexed type, e.g. a built-in TObject/TStream).
//   2. CHEAP FALLBACK (only when (1) finds nothing at all -- e.g. a
//      built-in/un-indexed system type like TObject/TStream, never declared
//      anywhere in THIS corpus): the Delphi class/interface NAMING
//      CONVENTION (starts with 'T' or 'I') -- EXCLUDING a fixed, documented
//      set of well-known VALUE types that also happen to start with one of
//      those letters (Integer, TDateTime, TGUID, ...), checked FIRST via
//      MatchText so e.g. 'Integer' is never misread as an object merely
//      because it starts with 'I'. Not exhaustive (a conservative, bounded
//      heuristic, exactly per the task brief's own example list) -- just the
//      common cases; an obscure un-indexed value-type name that is not on
//      this list and happens to start with T/I would still be (wrongly)
//      accepted here, an accepted residual imprecision of a "cheap fallback"
//      that only even runs when the store has NOTHING to say about the type.
//      FIX (Phase 2 final review, empirically reproduced against the built
//      exe): the exclusion list originally named only PRIMITIVE value types
//      (Integer/string/TDateTime/...), omitting common RTL VALUE-RECORD
//      names (System.Types/System.UITypes: TRect, TPoint, TSize, TRectF,
//      TPointF, TSizeF, TSmallPoint; System.Rtti: TValue; TColor/
//      TGraphicsColor: device/device-independent color values) -- every one
//      copy-by-value, never a class/interface, yet all start with 'T'. When
//      the unit declaring one of these is NOT itself present in the index
//      (System.Types is RTL, commonly not re-indexed as part of an
//      application corpus), tier 1 finds nothing and falls through to tier
//      2, which used to accept the bare 'T'-prefix and wrongly render e.g.
//      'function TWidget.GetBounds: TRect; begin Result := FBounds; end;'
//      as 'Owns returned: borrowed' -- nonsense for a value type no caller
//      could legitimately Free. Now added to the SAME exclusion list,
//      checked the SAME way (MatchText, before the T/I-prefix fallback) --
//      safe-direction only: this can only ever SUPPRESS a fact (Exit(False)
//      drops 'Owns returned:' entirely, the SAME omission tier 1's
//      skRecord/skEnum ground-truth negative above already produces when
//      the type IS indexed), never fabricate one.
function IsReferenceTypeName(const AStore: ISymbolStore; const ATypeName: string): Boolean;
var
  Bare : string         ;
  P    : Integer        ;
  Cands: TArray<TSymbol>;
  Cand : TSymbol        ;
begin
  Result:= False;
  Bare:= Trim(ATypeName);
  if Bare = '' then Exit;
  P:= Bare.LastDelimiter('.'); // strip a unit qualifier if present (Unit.TFoo -> TFoo)
  if P >= 0 then Bare:= Trim(Copy(Bare, P + 2, MaxInt));
  if Bare = '' then Exit;

  Cands:= AStore.FindSymbolsByExactName(Bare);
  for Cand in Cands do
  begin
    if Cand.Kind in [skClass, skInterface] then Exit(True);
    // FIX (Phase 2 T8 review, Fix 2): ground-truth NEGATIVE -- see this
    // function's header comment, tier 1, for why the ORIGINAL code's
    // silence here (no negative check at all) let a resolved value-typed
    // record/enum fall through to the T/I-prefix heuristic below and be
    // wrongly accepted as a reference type.
    if Cand.Kind in [skRecord, skEnum] then Exit(False);
  end;

  if MatchText(Bare, [
    'Integer', 'Int64', 'UInt64', 'Cardinal', 'Byte', 'Word',
    'SmallInt', 'ShortInt', 'LongInt', 'LongWord', 'NativeInt', 'NativeUInt',
    'Boolean', 'ByteBool', 'WordBool', 'LongBool',
    'string', 'AnsiString', 'WideString', 'UnicodeString', 'ShortString',
    'Char', 'AnsiChar', 'WideChar',
    'Double', 'Single', 'Extended', 'Currency', 'Comp', 'Real', 'Real48',
    'TDateTime', 'TDate', 'TTime', 'TGUID', 'Variant', 'OleVariant',
    'Pointer', 'TBytes',
    // FIX (Phase 2 final review): common RTL VALUE-RECORD names -- see the
    // header comment above for the full rationale.
    'TRect', 'TPoint', 'TSize', 'TRectF', 'TPointF', 'TSizeF', 'TSmallPoint',
    'TValue', 'TColor', 'TGraphicsColor']) then Exit(False);

  Result:= (Length(Bare) >= 2) and CharInSet(Bare[1], ['T', 'I']);
end;

// FIX (Phase 2 T8 review, Fix 1): the constructor-call's own RECEIVER node --
// the exprDot's 'lhs', i.e. what 'T.Create'/'APool.Create' is CALLED ON. N is
// whichever shape ExprIsConstructor (DRagLint.Analysis.Flow.Lattices) itself
// already matched: a bare 'exprDot' ('T.Create'), or an 'exprCall' whose
// 'entity' is that same 'exprDot' ('T.Create()'). IsNull (Default(TTSNode))
// when N matches neither shape -- defensive only; every real call site is
// guarded by ExprIsConstructor(N, ASrc) having already returned True first
// (see ClassifyReturnSite's 'new' check, below).
function ConstructorReceiverNode(const N: TTSNode): TTSNode;
var DotN: TTSNode;
begin
  Result:= Default(TTSNode);
  DotN  := Default(TTSNode);
  if N.NodeType = 'exprDot' then DotN:= N
  else if N.NodeType = 'exprCall' then DotN:= N.ChildByField('entity');
  if DotN.IsNull or (DotN.NodeType <> 'exprDot') then Exit;
  Result:= DotN.ChildByField('lhs');
end;

// FIX (Phase 2 T8 review, Fix 1): True only when ARecv (a constructor-call's
// receiver expression, from ConstructorReceiverNode) is confidently a
// bare/qualified TYPE reference -- e.g. 'TFoo' in 'TFoo.Create' -- and NOT an
// existing instance. Guards the false 'new' ClassifyReturnSite used to
// accept unconditionally from ExprIsConstructor, which matches PURELY on the
// member-access text 'create' and never inspects the receiver at all -- so a
// plain instance method merely NAMED Create (e.g. 'function TWidgetPool.
// Create: TWidget' that just returns a shared field, never allocating) used
// to read back as 'new' from ANY call site, e.g. 'Result := APool.Create;'.
//
// Walks ARecv's own leftmost/base identifier via the SAME lhs/entity/first-
// named-child descent DRagLint.Analysis.Flow.Lattices' LeftmostBaseVar
// already performs for the identical "find the base var of x / x.f / x.f.g"
// need (the descent shape is reused; LeftmostBaseVar itself is not, since it
// returns an AVars-only index and this needs the identifier's TEXT to
// additionally test against AFields) -- bounded to 32 hops against a
// malformed/cyclic tree, matching LeftmostBaseVar's own guard. The head
// identifier is rejected (Result:=False, i.e. NOT a type reference) when:
//   - no identifier is found at all within the hop bound (a receiver
//     bottoming out in a call result, an index expression, ... -- "cannot be
//     determined to be a type name" -- absence over a wrong verdict);
//   - it is literally 'self' (Self.Create is ambiguous: on a class method
//     Self is a metaclass and .Create allocates fresh, but on an ordinary
//     instance method Self IS the current instance and .Create reinitializes
//     it in place -- indistinguishable here, so never accepted as 'new');
//   - it resolves in AVars (ANY kind: a parameter, a local, Result itself)
//     -- an existing instance the routine already holds a reference to, e.g.
//     'APool.Create' where APool: TWidgetPool is a parameter;
//   - it resolves in AFields (an own-class field) -- e.g. 'FFactory.Create'.
// AVars/AFields are the SAME per-routine var table and own-class field-name
// set ClassifyReturnSite's OTHER branches (borrowed/self) already use.
//
// This narrows RECALL, never precision: a real class-reference-typed
// variable's '.Create' (e.g. 'AFactoryClass: TWidgetPoolClass; ... Result :=
// AFactoryClass.Create;' -- a genuine fresh allocation via a metaclass
// variable) is indistinguishable from an existing-instance receiver here, so
// it is rejected too (falls to 'unknown') -- an accepted, documented SAFE-
// direction imprecision: ABSENCE OVER A WRONG VERDICT, this fact's own
// governing principle, values a missed 'new' far below a wrong one (a wrong
// 'new' invites a double-free; a missed 'new' just omits a line).
function ConstructorReceiverIsTypeName(const ARecv: TTSNode; const ASrc: TBytes;
  AVars: TRoutineVarTable; AFields: TDictionary<string, string>): Boolean;
var Cur, Nxt: TTSNode; Guard: Integer; Head: string;
begin
  Result:= False;
  Head:= '';
  Cur:= ARecv; Guard:= 0;
  while (not Cur.IsNull) and (Guard < 32) do
  begin
    Inc(Guard);
    if Cur.NodeType = 'identifier' then begin Head:= NodeText(Cur, ASrc); Break; end;
    Nxt:= Cur.ChildByField('lhs');
    if Nxt.IsNull then Nxt:= Cur.ChildByField('entity');
    if Nxt.IsNull and (Cur.NamedChildCount > 0) then Nxt:= Cur.NamedChild(0);
    if Nxt.IsNull then Exit; // bottomed out on something other than an identifier -- undetermined, reject
    Cur:= Nxt;
  end;
  if Head = '' then Exit;                 // not found within the hop bound either -- undetermined, reject
  if Head = 'self' then Exit;             // Self.Create -- ambiguous instance receiver, reject
  if AVars.IndexOf(Head) >= 0 then Exit;  // a param/local/Result -- existing instance
  if AFields.ContainsKey(Head) then Exit; // an own-class field -- existing instance
  Result:= True;
end;

// ADP2 T8: classifies ONE return-site's RHS node N into exactly one of
// {new, borrowed, self, unknown} -- see this unit's banner comment (Task 8
// paragraph) for the full ruleset. AVars/AFields are the SAME per-routine
// var table and own-class field-name set AnalyzeReadsWrites (above)
// already builds (params/locals/Result; own-class field DISPLAY names,
// keyed lowercase) -- reused here for the 'borrowed' classification (a
// parameter or an own-class field), and to correctly EXCLUDE a LOCAL
// variable of the same name (explicitly 'unknown' per the task brief, even
// though it also resolves in AVars) from ever being misread as a field/
// param handle -- Pascal scoping: a local/Result SHADOWS a same-named
// field, the exact same precedence AnalyzeReadsWrites' own ResolveField
// already enforces.
function ClassifyReturnSite(const N: TTSNode; const ASrc: TBytes;
  AVars: TRoutineVarTable; AFields: TDictionary<string, string>): string;
var
  Op    : TTSNode;
  Lhs   : TTSNode;
  Key   : string ;
  VarIdx: Integer;
  V     : TRoutineVar;
begin
  Result:= 'unknown';
  if N.IsNull then Exit;

  // new: 'T.Create' (paren-less) / 'T.Create(...)' -- reuses DRagLint.
  // Analysis.Flow.Lattices' ExprIsConstructor AS-IS: the SAME 'exprDot' /
  // 'exprCall'-wrapping-'exprDot' rhs='create' shape-matcher the object-leak
  // escape analysis (TEscape) already relies on -- handles BOTH the
  // paren-less and parenthesized constructor-call shapes identically, so
  // this fact and the leak-detection lattice can never disagree about what
  // "looks like a constructor call". FIX (Phase 2 T8 review, Fix 1):
  // ExprIsConstructor matches PURELY on the member-access text 'create' and
  // NEVER inspects what it is called ON, so a plain instance method simply
  // NAMED Create (e.g. 'function TWidgetPool.Create: TWidget' that just
  // returns a shared field, never allocating) used to read back as 'new'
  // from ANY call site, e.g. 'Result := APool.Create;' where APool is an
  // existing instance. 'new' is now additionally gated on the call's own
  // RECEIVER (ConstructorReceiverNode) confidently being a bare/qualified
  // TYPE reference, not an existing instance -- see
  // ConstructorReceiverIsTypeName's own header comment for the full rule and
  // its accepted recall-narrowing tradeoff.
  if ExprIsConstructor(N, ASrc)
     and ConstructorReceiverIsTypeName(ConstructorReceiverNode(N), ASrc, AVars, AFields) then
    Exit('new');

  // self: bare 'Self', or 'Self as <Type>' (an 'exprBinary' whose operator
  // node-type is literally 'kAs' -- the SAME shape DRagLint.Parser.
  // Delphi13's own is/as ref-gap E check already keys on).
  if (N.NodeType = 'identifier') and (NodeText(N, ASrc) = 'self') then Exit('self');
  if N.NodeType = 'exprBinary' then
  begin
    Op:= N.ChildByField('operator');
    if (not Op.IsNull) and (Op.NodeType = 'kAs') then
    begin
      Lhs:= N.ChildByField('lhs');
      if (not Lhs.IsNull) and (Lhs.NodeType = 'identifier') and (NodeText(Lhs, ASrc) = 'self') then
        Exit('self');
    end;
  end;

  // borrowed: a BARE identifier resolving to a routine PARAMETER (any mode)
  // or an own-class FIELD. A var-table hit that is NOT a parameter kind
  // (vkLocal, or vkResult -- e.g. a degenerate 'Result := Result') is
  // 'unknown', full stop -- it is NEVER also looked up in AFields, since a
  // local/Result of the same name as a field SHADOWS the field.
  if N.NodeType = 'identifier' then
  begin
    Key:= NodeText(N, ASrc);
    VarIdx:= AVars.IndexOf(Key);
    if VarIdx >= 0 then
    begin
      V:= AVars.Get(VarIdx);
      if V.Kind in [vkParamVar, vkParamOut, vkParamConst, vkParamValue] then Exit('borrowed');
      Exit('unknown'); // vkLocal / vkResult -- shadows any same-named field
    end;
    if AFields.ContainsKey(Key) then Exit('borrowed');
  end;

  // anything else (a call to another function, a local var that fell
  // through above, an index/deref expression, a with-block var, a ternary,
  // ...) -- never guessed.
  Result:= 'unknown';
end;

// ADP2 T8: single-pass walk collecting every 'Result :=' / 'Exit(<rhs>)'
// return-value site under N into ASites (each entry the site's OWN RHS
// node, for ClassifyReturnSite to inspect later) and detecting whether
// Result is EVER disposed (Result.Free / Result.DisposeOf / FreeAndNil
// (Result)) anywhere in the body (ADisposed) -- reuses DRagLint.Analysis.
// Flow.Lattices' DetectFreedVar (the SAME '.Free'/'.DisposeOf'/'FreeAndNil'
// shape-matcher the double-free lattice (TFreedState) already relies on),
// checked at every node, exactly like TEscape.Transfer's own per-CFG-item
// call. Mirrors WalkFieldRW's traversal shape (assignment/exprCall
// special-cased, everything else a generic named-child recursion) but for a
// DIFFERENT purpose (collecting return sites + a disposal flag, not field
// reads/writes). Skips a NESTED 'defProc' entirely (a local/nested
// routine's own Result belongs to IT, never the enclosing routine being
// analyzed here -- same guard WalkSqlLiterals already applies, for the
// identical reason -- see its own header comment). Stops recursing the
// moment ADisposed becomes True: once Result is known to be disposed
// somewhere, the overall verdict is OMIT regardless of what else is found,
// so there is nothing left worth collecting.
//
// AResultIdx MUST be >= 0 (the caller only calls this after confirming
// AVars.IndexOf('result') resolved) -- an assignment's lhs identifier is
// matched against AResultIdx via AVars.IndexOf too, so if Result were ever
// NOT found in AVars (AResultIdx = -1), an untranslatable/unrelated
// identifier that ALSO fails to resolve (-1) would wrongly compare equal;
// gating AResultIdx >= 0 at the call site avoids that entirely.
procedure WalkReturnsOwnerSites(const N: TTSNode; const ASrc: TBytes;
  AVars: TRoutineVarTable; AResultIdx: Integer; ASites: TList<TTSNode>; var ADisposed: Boolean);
var
  Lhs, Rhs, Ent, ArgsN: TTSNode;
  I: Integer;
begin
  if N.IsNull or ADisposed then Exit;
  if N.NodeType = 'defProc' then Exit; // nested routine -- its own Result, not this one's

  if DetectFreedVar(N, ASrc, AVars) = AResultIdx then
  begin
    ADisposed:= True;
    Exit;
  end;

  if N.NodeType = 'assignment' then
  begin
    Lhs:= N.ChildByField('lhs');
    Rhs:= N.ChildByField('rhs');
    if (not Lhs.IsNull) and (Lhs.NodeType = 'identifier') and (AVars.IndexOf(NodeText(Lhs, ASrc)) = AResultIdx) then
      ASites.Add(Rhs) // a 'Result :=' (or aliased '<FunctionName> :=') site -- record the RHS
    else
      WalkReturnsOwnerSites(Lhs, ASrc, AVars, AResultIdx, ASites, ADisposed);
    WalkReturnsOwnerSites(Rhs, ASrc, AVars, AResultIdx, ASites, ADisposed);
    Exit;
  end;

  if N.NodeType = 'exprCall' then
  begin
    Ent  := N.ChildByField('entity');
    ArgsN:= N.ChildByField('args');
    if (not Ent.IsNull) and (Ent.NodeType = 'identifier') and (NodeText(Ent, ASrc) = 'exit')
       and (not ArgsN.IsNull) and (ArgsN.NamedChildCount = 1) then
    begin
      ASites.Add(ArgsN.NamedChild(0)); // value-form 'Exit(<rhs>)' -- record the sole argument
      Exit;
    end;
    WalkReturnsOwnerSites(Ent, ASrc, AVars, AResultIdx, ASites, ADisposed);
    if not ArgsN.IsNull then
      for I:= 0 to ArgsN.NamedChildCount - 1 do
        WalkReturnsOwnerSites(ArgsN.NamedChild(I), ASrc, AVars, AResultIdx, ASites, ADisposed);
    Exit;
  end;

  for I:= 0 to N.NamedChildCount - 1 do
    WalkReturnsOwnerSites(N.NamedChild(I), ASrc, AVars, AResultIdx, ASites, ADisposed);
end;

// ADP2 T8: the ReturnsOwner fact for ASym -- '' (absence over a wrong
// verdict, this fact's own governing principle) unless EVERY return site
// unanimously classifies as the SAME high-confidence category. See this
// unit's banner comment (Task 8 paragraph) for the full rationale; see
// ClassifyReturnSite/WalkReturnsOwnerSites/IsReferenceTypeName (above) for
// each step's own rules. AProc/ABody are the SAME defProc/body nodes
// Analyze already matched for Cyclomatic/AnalyzeReadsWrites/
// AnalyzeSqlTables -- no second AST scan.
function AnalyzeReturnsOwner(const AProc, ABody: TTSNode; const ASrc: TBytes;
  const ASym: TSymbol; const AStore: ISymbolStore): string;
var
  RetTypeName: string             ;
  Vars       : TRoutineVarTable    ;
  ResultIdx  : Integer             ;
  Sites      : TList<TTSNode>      ;
  Disposed   : Boolean             ;
  Fields     : TDictionary<string, string>;
  Kids       : TArray<TSymbol>     ;
  Kid        : TSymbol             ;
  LKey       : string              ;
  Verdict    : string              ;
  Cat        : string              ;
  I          : Integer             ;
begin
  Result:= '';
  if ABody.IsNull then Exit;

  // GATE (function-shaped only) -- see this unit's banner comment (Task 8
  // paragraph, "GATE") for why this is Kind-agnostic (ASym.Kind in
  // [skFunction, skMethod] is a cheap defensive pre-filter only; the REAL
  // signal is the parsed return type, exactly like TDocFactsBuilder.Build's
  // OWN Result.ReturnType). '' here means a procedure (incl. a procedure
  // declared as a method) or a constructor/destructor -- none of them ever
  // carry a ': Type' suffix in their signature.
  if not (ASym.Kind in [skFunction, skMethod]) then Exit;
  RetTypeName:= ParseReturnType(ASym.Signature);
  if RetTypeName = '' then Exit;

  Vars  := TRoutineVarTable.Build(AProc, ASrc);
  Fields:= TDictionary<string, string>.Create;
  Sites := TList<TTSNode>.Create;
  try
    ResultIdx:= Vars.IndexOf('result');
    if ResultIdx < 0 then Exit; // cannot reliably identify Result-sites at all -- abstain

    Disposed:= False;
    WalkReturnsOwnerSites(ABody, ASrc, Vars, ResultIdx, Sites, Disposed);

    if Disposed then Exit;        // Result.Free/DisposeOf/FreeAndNil(Result) seen -- does not cleanly escape
    if Sites.Count = 0 then Exit; // no 'Result :='/'Exit(<rhs>)' site found at all

    // Own-class fields (for the 'borrowed' classification) -- the SAME
    // FindAllChildSymbols(ASym.ParentId) own-class-only field resolver
    // AnalyzeReadsWrites (above) already uses. A free routine (ASym.ParentId
    // <= 0) simply has no fields to borrow from -- every bare-identifier
    // site then classifies 'unknown' (not a field, and if also not a
    // parameter) and the unanimity check below naturally omits.
    if ASym.ParentId > 0 then
    begin
      Kids:= ChildSymbolsCached(AStore, ASym.ParentId); { was a per-routine store round-trip }
      for Kid in Kids do
        if Kid.Kind = skField then
        begin
          LKey:= LowerCase(Kid.Name);
          if not Fields.ContainsKey(LKey) then Fields.Add(LKey, Kid.Name);
        end;
    end;

    // Unanimity: every site must classify to the SAME non-'unknown'
    // category. A single 'unknown' site, or ANY disagreement between two
    // otherwise-confident sites (the task brief's own 'Amb' fixture: one
    // 'new' site + one 'borrowed' site), omits the fact entirely -- never
    // guessed.
    Verdict:= '';
    for I:= 0 to Sites.Count - 1 do
    begin
      Cat:= ClassifyReturnSite(Sites[I], ASrc, Vars, Fields);
      if Cat = 'unknown' then Exit;
      if Verdict = '' then Verdict:= Cat
      else if Verdict <> Cat then Exit;
    end;

    // Object-type gate (task brief step 5): 'new' is already
    // object-guaranteed ('T.Create'), no gate needed. 'borrowed'/'self'
    // additionally require the FUNCTION'S OWN return type to be a reference
    // type -- else a value-returning function (e.g. Count: Integer above)
    // would wrongly render 'borrowed'/'self' for a plain value type.
    if (Verdict = 'borrowed') or (Verdict = 'self') then
      if not IsReferenceTypeName(AStore, RetTypeName) then Exit;

    Result:= Verdict;
  finally
    Sites.Free;
    Fields.Free;
    Vars.Free;
  end;
end;

{ v0.85 PERF -- memoize CfgFindProcs per file.

  Analyze is called once per ROUTINE, and it called CfgFindProcs(RootNode) each
  time. CfgFindProcs walks the WHOLE tree to collect every defProc, so a file with
  N routines walked its entire AST N times: O(routines x AST nodes) per file.
  The comment below correctly notes the O(routines) linear MATCH, but the
  COLLECTION it scans was being rebuilt on every call.

  Measured before this change, with the per-phase profiler (DRAGLINT_PROFILE=1) on
  Studio\37.0\source\Internet (54 files): facts = 32.56 s of a 47.60 s accounted
  total -- 68%, against parse 1.34 s and commit 6.73 s.

  A single-entry cache is enough and is the safest possible shape: the indexer
  processes one file at a time and calls Analyze for all of that file's routines
  consecutively, which is precisely the lifetime TAstParseCache already assumes.
  The tree pointer is part of the key, so a re-parse (new tree, same path) cannot
  hand back TTSNodes belonging to a freed tree.

  NOT THREAD-SAFE, deliberately -- it inherits the shared-parse-cache constraint
  stated in this unit's banner. Parallel indexing must give each worker its own
  cache (or key this per thread) before using it. }
var
  GProcsCacheFile: string          ;
  GProcsCacheTree: Pointer         ;
  GProcsCache    : TArray<TTSNode> ;


function ProcsForFile(const AFilePath: string; const APF: TParsedFile): TArray<TTSNode>;
begin
  if (GProcsCacheFile = AFilePath) and (GProcsCacheTree = Pointer(APF.Tree)) then Exit(GProcsCache);
  GProcsCache    := CfgFindProcs(APF.Tree.RootNode);
  GProcsCacheFile:= AFilePath;
  GProcsCacheTree:= Pointer(APF.Tree);
  Result         := GProcsCache;
end;

class function TSymbolFactsAnalyzer.Analyze(const ASym: TSymbol; const AFilePath: string; const ABody: TArray<string>; const AStore: ISymbolStore): TSymbolFacts;
var
  PF   : TParsedFile     ;
  Procs: TArray<TTSNode> ;
  Proc : TTSNode         ;
  Body : TTSNode         ;
begin
  // Every fact field starts at Default(TSymbolFacts)'s zero value; Task 3
  // (ADP2) fills in Cyclomatic/BodyLoc below. Tasks 4/6 (ADP2) fill in
  // ReadsFields/WritesFields/DfmEvent (see below); Tasks 7-8 populate the
  // remaining groups -- ABody stays unused until then.
  Result:= Default(TSymbolFacts);
  Result.SymbolId:= ASym.Id;
  Result.Present := True;

  // BodyLoc: pure symbol-range arithmetic, no AST needed. Clamped to >= 0 as
  // a defensive guard (mirrors TIndexer.SliceBodyLines' Lo/Hi clip) though
  // ImplEndLine >= ImplStartLine always holds for a real routine body.
  Result.BodyLoc:= ASym.ImplEndLine - ASym.ImplStartLine;
  if Result.BodyLoc < 0 then Result.BodyLoc:= 0;

  // ADP2 T6: DfmEvent -- deliberately computed HERE, independent of the
  // Cyclomatic/ReadsWrites block below: unlike those two, this fact does not
  // need ASym's OWN .pas file AST at all (it needs the SIBLING .dfm's own
  // tree, via AnalyzeDfmEvent/DfmEventMapFor), so it must not be skipped
  // just because AFilePath's OWN parse happens to fail (PF.Tree = nil).
  Result.DfmEvent:= AnalyzeDfmEvent(ASym, AFilePath);

  // Cyclomatic: find the defProc node whose OWN StartPoint matches
  // ASym.ImplStartLine -- the EXACT provenance the parser used to stamp
  // ImplStartLine in the first place (DRagLint.Parser.Delphi13's defProc walk
  // calls SetRoutineImplRange(..., Integer(ANode.StartPoint.row) + 1, ...)
  // where ANode IS the defProc), so this lookup is guaranteed to find the
  // right routine whenever the same source parses the same way twice.
  // TAstParseCache.Get is memoized per file (see this unit's banner comment
  // and the indexer's facts-pass comment): the FIRST Analyze call for a file
  // parses it; every other routine in the SAME file reuses the cached tree --
  // one extra parse PER FILE (on top of the indexer's own parse), not per
  // routine. CfgFindProcs (DRagLint.Analysis.Cfg) collects every defProc in
  // the tree; an O(routines-in-file) linear scan then matches by line -- no
  // positional (point-based) node lookup is exposed by the TTSNode API, and
  // this walk is accepted as index-time cost (see the Phase 2 design).
  PF:= TAstParseCache.Get(AFilePath);
  if PF.Tree <> nil then
  begin
    Procs:= ProcsForFile(AFilePath, PF); { was CfgFindProcs(PF.Tree.RootNode) per routine }
    for Proc in Procs do
      if Integer(Proc.StartPoint.Row) + 1 = ASym.ImplStartLine then
      begin
        Body:= Proc.ChildByField('body');
        Result.Cyclomatic:= TAstChecker.CyclomaticOf(Body);
        // ADP2 T4: Reads/Writes fields -- the SAME matched Proc/Body, no 2nd
        // AST scan. See AnalyzeReadsWrites' header comment (above, this
        // unit's implementation section) for the field-set + classification
        // rules.
        AnalyzeReadsWrites(Proc, Body, PF.Src, ASym, AFilePath, AStore, Result.ReadsFields, Result.WritesFields);
        // v(ADP3 T11): var/out parameter writes -- same matched Proc/Body, no
        // 2nd AST scan. Complements the line above: that one resolves against
        // the owning class's FIELDS, this one against the routine's own
        // parameter list, so a free routine is covered too. See
        // WalkMutatedParams' header for the classification rules.
        Result.MutatesParams:= AnalyzeMutatesParams(Proc, Body, PF.Src);
        // v(ADP3 T12): UI affinity -- same matched Proc/Body, no 2nd AST scan.
        // POSITIVE FINDINGS ONLY; see AnalyzeUiAffinity's header for why the
        // empty result must never be rendered as a thread-safety claim.
        Result.UiAffinity:= AnalyzeUiAffinity(Proc, Body, PF.Src, ASym, AStore);
        // v(ADP3 T13): external surfaces + transaction verbs -- same matched
        // Body, no 2nd AST scan. Stored as 'resources|transactions'; see
        // AnalyzeTouches' header for the wire format and the match-shape rules.
        Result.Touches:= AnalyzeTouches(Body, PF.Src);
        // ADP2 T7: SQL tables touched -- same matched Body node, no 2nd AST
        // scan. See AnalyzeSqlTables' header comment (above, this unit's
        // implementation section) for the full literal-concatenation +
        // conservative FROM/JOIN/INSERT/UPDATE/DELETE table-name extraction
        // pipeline.
        AnalyzeSqlTables(Body, PF.Src, Result.SqlReads, Result.SqlWrites);
        // ADP2 T8: returned-object ownership -- same matched Proc/Body, no
        // 2nd AST scan. See AnalyzeReturnsOwner's header comment (above,
        // this unit's implementation section) for the full site-collection
        // + unanimity + object-type-gate ruleset.
        Result.ReturnsOwner:= AnalyzeReturnsOwner(Proc, Body, PF.Src, ASym, AStore);
        Break;
      end;
    // No matching defProc: Cyclomatic stays 0 and Reads/WritesFields/
    // SqlReads/SqlWrites stay '' (absence over a wrong number/fact -- e.g. a
    // stale/mismatched parse, or ASym's file changed between the indexer's
    // own parse and this cache lookup).
  end;
end;

// ADP2 T5: display cap + bounded reverse-hop depth/walk-size for the
// Covered-by-tests fact -- see ComputeCoveredBy's own header comment
// (interface section) and this unit's banner "TASK 5 OVERRIDE" +
// "IMPLEMENTATION NOTE" for the full rationale. COVERED_BY_CAP mirrors
// FIELD_RW_CAP's convention (a dedicated const per fact, not shared) but is
// deliberately smaller (5, not 8): CalledFrom's own display cap (DRagLint.
// Doc.Facts, docs.max_callers) already defaults to 5, and Covered-by is
// conceptually a FILTERED view of the same caller set, so matching that
// default keeps the two lines visually consistent.
const
  COVERED_BY_CAP     = 5;   // display cap + '(+N more)' threshold
  COVERED_BY_DEPTH   = 3;   // reverse hops walked (brief's suggested "<= 3")
  COVERED_BY_MAXWALK = 200; // hard cap on distinct caller routines expanded per render (see ComputeCoveredBy's remarks)

// LastSegment: "Unit.TClass.Method" -> "Method"; "Unit.Method" -> "Method";
// a bare name -> itself. Duplicated locally (mirrors DRagLint.Refactor.
// TestStub's own TSG_LastSegment, whose header comment states the same
// "keep this unit standalone" reasoning) rather than reaching into
// DRagLint.Doc.Facts' private, non-exported LastSeg -- which would also
// require Doc.Facts to export it, and Doc.Facts already `uses` THIS unit
// (for ComputeCoveredBy), so pulling the other way would be a real circular
// unit dependency.
function LastSegment(const S: string): string;
var P: Integer;
begin
  P:= S.LastDelimiter('.');
  if P >= 0 then Result:= Copy(S, P + 2, MaxInt) else Result:= S;
end;

// True when the caller routine identified by (ASymbolId, AQName, ALocation)
// -- one row of a FindResolvedCallers/FindUnresolvedNameCallers result -- is
// a TEST routine, by either of two GROUND-TRUTH rules:
//   (a) its DECLARING FILE's basename matches the '*Test'/'Test*' naming
//       convention, case-insensitive (the DUnitX corpus-wide convention --
//       e.g. 'UWidgetTests.pas' or 'TestWidget.pas'), AND the routine ITSELF
//       looks like a test by (a1) its own name carrying the 'Test' prefix, or
//       (a2) being a method of a class whose name matches the same '*Test'/
//       '*Tests'/'Test*' fixture convention.
//
//       v(B10): the file check ALONE used to be sufficient, and that was the
//       defect YADF filed. A test file holds helpers as well as tests --
//       `CodeChars` and `Check` in YADF's Test\GuardTest.dpr are plain local
//       helpers, and `CodeChars` was rendered as a coverer of three
//       YADF.LineScan symbols. The file rule is now NECESSARY but not
//       SUFFICIENT. It is still checked first and still query-free.
//
//       (a1) is the load-bearing half and it covers every shape in the corpora
//       this engine is used on: YADF's tests are free `Test*` procedures in a
//       .dpr, drag-lint's own StorageHelperEdgesTests.dpr is the same shape,
//       and DRagLint.Refactor.TestStub GENERATES `Test_<Method>_HappyPath`.
//       (a2) exists for the attribute-driven DUnitX fixture whose methods need
//       NOT carry the prefix (`[Test] procedure RoundTrips` on a TFooTests
//       class); the attribute itself is unreadable here, see the route-(c)
//       note below, so the FIXTURE CLASS's name stands in for it.
//
//       RESIDUAL, disclosed rather than implied: (a2) still admits a non-test
//       HELPER METHOD declared on a fixture class. That is a much narrower
//       leak than the file rule (it must be a method, on a test-named class,
//       in a test-named file) and it is not reachable without the attribute
//       route; a free helper -- the shape actually filed -- is now excluded.
//   (b) INDEPENDENT of both file and routine naming: its ENCLOSING CLASS transitively
//       descends from a class literally named 'TTestCase' (a legacy-DUnit-
//       style fixture) -- AStore.GetTransitiveAncestors, the SAME ancestry
//       walk DRagLint.Doc.Facts' Overrides/Implements gather already uses.
//       ASymbolId is the caller ROUTINE's own id (TResolvedCaller.
//       EnclosingSymbolId, already resolved by the caller), so no further
//       name-based re-resolution is needed here. GetTransitiveAncestors
//       returns UNRESOLVED heritage edges too (name-only leaves -- see its
//       own header comment), so this fires even when TTestCase itself (e.g.
//       DUnit's TestFramework.pas) is outside the indexed corpus, which is
//       the realistic case.
//
// A [Test]/[TestCase] CUSTOM ATTRIBUTE is deliberately NOT checked as a
// third rule (route (c) in the task brief): CONFIRMED by reading
// TIndexer.ResolveEnclosingSymbolId (DRagLint.Core.Indexer) that a
// reference's EnclosingSymbolId is resolved ONLY by testing the reference's
// line against a ROUTINE'S IMPLEMENTATION range (ImplStartLine..
// ImplEndLine). A custom attribute like '[Test]' decorates the BARE
// INTERFACE-SECTION declaration one or more lines above the routine's own
// body -- outside any routine's impl range -- so the 'attribute' reference
// the parser DOES emit (DRagLint.Parser.Delphi13's Walk, NodeType =
// 'attribute') always comes back with EnclosingSymbolId = 0 (unenclosed).
// No store primitive answers "does method M carry attribute X" any other
// way, so route (c) is skipped per the task's own documented contingency
// (route (a)/(b) are the "high-signal core"; attributes would be a bonus
// this index cannot currently support).
function IsTestRoutine(const AStore: ISymbolStore; ASymbolId: Int64; const ALocation: string): Boolean;
var
  BaseName : string;
  Sym      : TSymbol;
  ParentSym: TSymbol;
  Anc      : TTypeAncestor;
begin
  Result:= False;
  if ASymbolId <= 0 then Exit;
  Sym:= AStore.GetSymbolById(ASymbolId);

  // (a) file-name convention -- query-free, and NECESSARY-not-sufficient
  //     (B10). One of (a1)/(a2) must corroborate it.
  BaseName:= ChangeFileExt(ALocation, '');
  if StartsText('Test', BaseName) or EndsText('Test', BaseName) then
  begin
    // (a1) the routine's own name carries the convention.
    if StartsText('Test', Sym.Name) then Exit(True);
    // (a2) or it is a method of a fixture-named class.
    if Sym.ParentId > 0 then
    begin
      ParentSym:= AStore.GetSymbolById(Sym.ParentId);
      if (ParentSym.Kind = skClass)
         and (StartsText('Test', ParentSym.Name)
              or EndsText('Test', ParentSym.Name)
              or EndsText('Tests', ParentSym.Name)) then Exit(True);
    end;
  end;

  // (b) TTestCase ancestry -- reached whenever (a) did not already conclude.
  if Sym.ParentId <= 0 then Exit;
  ParentSym:= AStore.GetSymbolById(Sym.ParentId);
  if ParentSym.Kind <> skClass then Exit;
  for Anc in AStore.GetTransitiveAncestors(ParentSym.Id) do
    if SameText(Anc.Name, 'TTestCase') then Exit(True);
end;

// v(ADP3 T14): DI/ORM wiring for one symbol, as the stored wire string --
// '; '-joined entries, each 'di:<interface> (<lifetime>)' or
// 'ds:<symbol> -> <RELATION> (<COL>, <COL>)'. '' when the symbol is neither
// registered nor linked. NO NEW AST ANALYSIS: this is a pure join over tables
// the index already carries (di_bindings, orm_links, fb_relations, fb_columns).
//
// COMPUTED AT RENDER TIME, NOT INDEX TIME -- a deliberate deviation from the
// plan, and the SECOND fact to need it after ADP2 T5's CoveredBy, for the same
// class of reason: the data does not exist yet when the facts loop runs.
//   * orm_links is written by a SEPARATE pass (DRagLint.Sql.OrmLinker, the
//     `orm-link` command), which starts with `DELETE FROM orm_links` and
//     rebuilds. It is not part of `index` at all. An index-time wiring column
//     would therefore be EMPTY on every first index, and could only pick the
//     links up on a later reindex -- which re-inserts the Delphi symbols with
//     NEW ids, leaving the orm_links rows (whose delphi_symbol_id has no FK and
//     so is never cascaded) pointing at symbols that no longer exist. The fact
//     would be reliably wrong rather than occasionally stale.
//   * di_bindings IS written during the same index pass, so that half could
//     have been index-time; splitting one fact across two computation times to
//     save one query would be a worse trade than the query.
// symbol_facts.wiring therefore stays UNWRITTEN/RESERVED, exactly as
// symbol_facts.covered_by does -- see TDocFacts.CoveredBy's own field comment.
//
// A METHOD IS WIRED THROUGH ITS CLASS. `Registered as:` is a property of the
// registered type, so for a method the lookup uses the owning class's name
// (ASym.ParentId); for a class symbol it uses its own. The dataset link is
// looked up for both the symbol and its parent, since orm-link may attach
// either.
function ComputeWiring(const AStore: ISymbolStore; const ASym: TSymbol): string;
var
  Entries : TStringList        ;
  TypeName: string             ;
  OwnerId : Int64              ;
  Parent  : TSymbol            ;
  B       : TDiBindingRow      ;

  procedure AddDatasetLinks(ASymbolId: Int64; const ADisplay: string);
  var Lk: TOrmDatasetLink; Cols: string; I: Integer;
  begin
    if ASymbolId <= 0 then Exit;
    for Lk in AStore.FindOrmDatasetLinks(ASymbolId) do
    begin
      Cols:= '';
      for I:= 0 to High(Lk.Columns) do
      begin
        if I > 0 then Cols:= Cols + ', ';
        Cols:= Cols + Lk.Columns[I];
      end;
      if Cols <> '' then
        Entries.Add(Format('ds:%s -> %s (%s)', [ADisplay, Lk.RelationName, Cols]))
      else
        Entries.Add(Format('ds:%s -> %s', [ADisplay, Lk.RelationName]));
    end;
  end;

begin
  Result:= '';
  if ASym.Id <= 0 then Exit;

  Entries:= TStringList.Create;
  try
    Entries.Duplicates:= dupIgnore; // the same registration can be reachable twice
    // --- DI: what is this type registered as? -------------------------------
    TypeName:= '';
    OwnerId := 0;
    if ASym.Kind = skClass then
    begin
      TypeName:= ASym.Name;
      OwnerId := ASym.Id;
    end
    else if ASym.ParentId > 0 then
    begin
      Parent:= AStore.GetSymbolById(ASym.ParentId);
      if Parent.Kind = skClass then
      begin
        TypeName:= Parent.Name;
        OwnerId := Parent.Id;
      end;
    end;
    if TypeName <> '' then
      for B in AStore.FindDiBindingsForImpl(TypeName) do
        if Trim(B.InterfaceName) <> '' then
        begin
          if Trim(B.Lifetime) <> '' then
            Entries.Add(Format('di:%s (%s)', [B.InterfaceName, B.Lifetime]))
          else
            Entries.Add(Format('di:%s', [B.InterfaceName]));
        end;

    // --- ORM: which relation does this symbol read/write? -------------------
    AddDatasetLinks(ASym.Id, ASym.Name);
    if (OwnerId > 0) and (OwnerId <> ASym.Id) then
      AddDatasetLinks(OwnerId, TypeName);

    if Entries.Count = 0 then Exit;
    Result:= string.Join('; ', Entries.ToStringArray);
  finally
    Entries.Free;
  end;
end;

function ComputeCoveredBy(const AStore: ISymbolStore; const ASym: TSymbol): string;
var
  Names  : TStringList;
  Visited: TDictionary<Int64, Boolean>; // caller-routine ids already expanded, across the WHOLE walk (cycle guard + the render-size cap)
  { lowercased test qname -> was it reached by at least one VERIFIED path.
    See the classification block inside Walk for what verified means here. }
  VerifiedName: TDictionary<string, Boolean>;

  { True when ASymbolId names a method -- i.e. its parent is a class, interface
    or record rather than a unit. Only for such a target is a MISSING receiver
    evidence of anything; for a free routine an unqualified call is ordinary
    Delphi. Returns False for an unknown id, which keeps an unresolvable target
    on the permissive side. }
  function TargetIsMethodOf(ASymbolId: Int64): Boolean;
  var
    S, P: TSymbol;
  begin
    Result:= False;
    if ASymbolId <= 0 then Exit;
    S:= AStore.GetSymbolById(ASymbolId);
    if (S.Id <= 0) or (S.ParentId <= 0) then Exit;
    P:= AStore.GetSymbolById(S.ParentId);
    Result:= P.Kind in [skClass, skInterface, skRecord];
  end;

  // Finds every caller of (ASymbolId as a resolved call_edges target) UNION
  // (AQName's last segment as a NAME match with no call_edges row) -- the
  // SAME two-bucket union DRagLint.Doc.Facts' 'Called from:' gather uses,
  // required here for the identical reason (see this unit's banner
  // "IMPLEMENTATION NOTE"): TCallResolver never resolves a bare call from a
  // method to a DIFFERENT unit's routine, so the DUnitX test->target edge
  // only ever shows up in the unresolved/name-based bucket. Recurses one
  // hop per call, up to ADepth, expanding EVERY newly-discovered caller
  // exactly once (Visited, shared across the whole walk) and stopping once
  // COVERED_BY_MAXWALK distinct callers have been expanded (a render-time
  // safety net against a pathologically hot symbol).
  procedure Walk(ASymbolId: Int64; const AQName: string; ADepth: Integer; AVerified: Boolean);
  var
    RC       : TResolvedCaller;
    Combined : TArray<TResolvedCaller>;
    HopSeen  : TDictionary<Int64, Boolean>; // dedupes a caller seen in BOTH buckets at THIS hop
    NResolved: Integer                    ; // how many of Combined came from the RESOLVED bucket
  begin
    if ADepth <= 0 then Exit;
    Combined:= nil;
    NResolved:= 0;
    if ASymbolId > 0 then
    begin
      Combined:= Combined + AStore.FindResolvedCallers(ASymbolId);
      NResolved:= Length(Combined);
    end;
    // v(ADP3 T3i, register E1): takes FindUnresolvedNameCallers' DEFAULT
    // (call sites only) DELIBERATELY -- this is a consumer of the
    // "is this call site resolved?" notion, and the default is the right answer
    // for it. It matters more here than for a rendered caller list: a phantom
    // name-match inside a *Test.pas file would make IsTestRoutine below assert
    // "Covered by: <that test>" for a symbol the test never calls.
    // v(ADP3 T3i review round 4): no consumer COUNT is stated here -- the count
    // moved between rounds and this comment would have been the copy left
    // asserting the old one. The parameter's contract, including the list of
    // callers that pass it explicitly, is on the ISymbolStore declaration in
    // DRagLint.Core.Interfaces. ComputeCoveredBy's own early-out at the tail
    // below restricts it to routine kinds, so the non-routine exemption
    // DRagLint.Doc.Facts needs cannot arise here at all.
    if AQName <> '' then
      Combined:= Combined + AStore.FindUnresolvedNameCallers(LastSegment(AQName));
    if Length(Combined) = 0 then Exit;

    { IS THIS HOP'S TARGET A METHOD? Only then can a missing receiver be evidence
      of anything. Computed once per hop rather than per caller. }
    var TargetIsMethod: Boolean:= TargetIsMethodOf(ASymbolId);

    HopSeen:= TDictionary<Int64, Boolean>.Create;
    try
      var Idx: Integer:= -1;
      for RC in Combined do
      begin
        Inc(Idx);
        if RC.EnclosingSymbolId <= 0 then Continue; // no enclosing routine -- nothing to attribute the call to
        if HopSeen.ContainsKey(RC.EnclosingSymbolId) then Continue;
        HopSeen.Add(RC.EnclosingSymbolId, True);
        if Visited.ContainsKey(RC.EnclosingSymbolId) then Continue; // already expanded (earlier hop, or another branch) -- cycle guard
        if Visited.Count >= COVERED_BY_MAXWALK then Exit; // hard walk-size cap reached
        Visited.Add(RC.EnclosingSymbolId, True);

        { WHEN IS THIS EDGE PROOF, AND WHEN IS IT ONLY A NAME MATCH?

          * RESOLVED bucket (the first NResolved entries): a call_edges row IS
            the resolver's proof that this call reaches THIS symbol. Verified.
          * NAME bucket, target is a FREE ROUTINE: an unqualified call to a
            routine in scope has no receiver and needs none. Verified. Treating
            these as suspect is what turned a real handful of untypable
            receivers into a reported "3,882".
          * NAME bucket, target is a METHOD, receiver recorded: the receiver
            names something, so the match is anchored. Verified. (Typing that
            receiver to the owner is a further tightening, deliberately NOT done
            here -- the ruling was to MARK, not to drop, and a name that types to
            an interface is a genuinely undecidable case, not a bad match.)
          * NAME bucket, target is a METHOD, receiver EMPTY: nothing ties the
            call to this method rather than a same-named one in another class.
            This is the reported defect -- one such site attributed a DPP test to
            all eight TransferFile symbols within three hops.

          Verification does not survive a weak hop: a test reached THROUGH an
          unproven edge is no better established than that edge. }
        var EdgeVerified: Boolean:=
          (Idx < NResolved) or (not TargetIsMethod) or (Trim(RC.ReceiverText) <> '');
        var PathVerified: Boolean:= AVerified and EdgeVerified;

        if IsTestRoutine(AStore, RC.EnclosingSymbolId, RC.Location) then
        begin
          Names.Add(RC.EnclosingQName);
          { A test reachable by ANY verified path is verified, however many
            unverified paths also reach it. Recording the best evidence, not the
            last seen. }
          var Was: Boolean;
          if not VerifiedName.TryGetValue(LowerCase(RC.EnclosingQName), Was) then Was:= False;
          VerifiedName.AddOrSetValue(LowerCase(RC.EnclosingQName), Was or PathVerified);
        end;
        Walk(RC.EnclosingSymbolId, RC.EnclosingQName, ADepth - 1, PathVerified);
      end;
    finally
      HopSeen.Free;
    end;
  end;

begin
  Result:= '';
  if ASym.Id <= 0 then Exit;
  // Only routine-like symbols can be "covered by tests" -- a type/field/
  // const/unit can never be a call target, so FindResolvedCallers et al.
  // would trivially return nothing for them anyway; this early-out just
  // skips the (otherwise harmless but wasted) walk for `document --project`'s
  // many non-routine symbols.
  //
  // v(ADP3 T3k, Group 2c item 1): this used to be a LITERAL COPY of the same
  // five kinds -- the one real remaining duplicate after T3i's single-source
  // sweep, left open there because collapsing it needed a code change. It now
  // reads DRagLint.Core.Model.CanBeCallTarget, the single declaration the doc
  // facts gate reads too. See that function's header; do not restate the set.
  if not CanBeCallTarget(ASym.Kind) then Exit;

  // SECOND EARLY-OUT, AND THE ONE THAT MATTERS AT SCALE: if the index holds no
  // test markers at all, IsTestRoutine cannot return True for any caller, so the
  // whole reverse walk below is provably incapable of adding a name. Measured on
  // YADF (188 decls, no tests): the walk was 8.76 s of a 15.55 s facts rebuild --
  // 56% of it -- to produce '' every single time. COVERED_BY_MAXWALK is 200 and
  // the walk fires up to two caller queries per expanded node, so the cost is
  // ~decls x nodes x queries; this collapses it to ONE query per run.
  //
  // It is a gate on the WALK, not on the fact: an index that does contain tests
  // takes exactly the path it always took, so no "Covered by:" line can change.
  // Cheap to call per declaration -- the store caches its own answer.
  if not AStore.HasTestRoutineMarkers then Exit;

  Names  := TStringList.Create;
  Visited:= TDictionary<Int64, Boolean>.Create;
  VerifiedName:= TDictionary<string, Boolean>.Create;
  try
    Names.Sorted      := True;      // DETERMINISTIC order regardless of walk/encounter order
    Names.Duplicates  := dupIgnore; // the SAME test can be reached via >1 reverse path/hop
    Names.CaseSensitive:= False;
    Visited.Add(ASym.Id, True); // seed with the root itself -- a (mutually) recursive target must never be re-attributed as its own "covered by" caller
    Walk(ASym.Id, ASym.QualifiedName, COVERED_BY_DEPTH, True);

    if Names.Count = 0 then Exit;

    // JoinCappedDisplay (above, this unit) applies the SAME cap+'(+N more)'
    // convention ReadsFields/WritesFields already use -- reused rather than
    // re-implemented. It wants a TList<string>; Names is a sorted/deduped
    // TStringList, so its (already-ordered) contents are copied across.
    var Capped: TList<string>:= TList<string>.Create;
    try
      { MARK WHAT COULD NOT BE VERIFIED, RATHER THAN DROPPING IT OR ASSERTING IT
        (owner ruling 2026-09-03).

        Dropping was the recommendation and was not taken: an unverified fact is
        still a lead, and the owner wants the underlying question -- how an
        interface-dispatched call should be attributed at all -- brainstormed
        rather than pre-empted by a filter. Asserting it is what produced the
        report: `uMahrRoutines.pas:219` carried a `Covered by:` naming a DPP test
        that never touches it.

        The suffix rides on the ENTRY, so the ', '-joined + capped contract every
        other fact uses is unchanged, and each name carries its own confidence
        even after '(+N more)' truncates the list. }
      var Was: Boolean;
      for var N: string in Names.ToStringArray do
        if VerifiedName.TryGetValue(LowerCase(N), Was) and Was then Capped.Add(N)
        else Capped.Add(N + ' (unverified)');
      Result:= JoinCappedDisplay(Capped, COVERED_BY_CAP);
    finally
      Capped.Free;
    end;
  finally
    VerifiedName.Free;
    Visited.Free;
    Names.Free;
  end;
end;

end.
