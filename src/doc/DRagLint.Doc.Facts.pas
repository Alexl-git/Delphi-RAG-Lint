unit DRagLint.Doc.Facts;

interface

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Math,
  System.Generics.Collections, System.RegularExpressions,
  DRagLint.Core.Model, DRagLint.Core.Interfaces, DRagLint.Doc.GitSince,
  DRagLint.Hover.Returns;

const
  // Display cap for the <seealso> related-symbol list (ADF T4). At most this many
  // <seealso cref> lines are emitted, keeping the managed block terse.
  SEEALSO_CAP = 5;
  // v(ADP1 T3): display cap for the 'Overridden by:' descendant-method list --
  // at most this many are shown; OverriddenByTotal carries the true count so the
  // renderer can add '(+N more)', mirroring CalledFrom's cap discipline.
  OVERRIDDENBY_CAP = 6;

type
  /// <summary>One signature parameter's harvested MEANING (ruling D-3): the
  /// text of a comment written beside that parameter INSIDE the parameter
  /// list.</summary>
  /// <remarks>
  /// A parameter with no such comment gets NO entry here. That is the
  /// whole of D-3's split: an automatic generator supplies STRUCTURE for every
  /// parameter (the emitter writes a &lt;param&gt; tag regardless) and MEANING
  /// only where the source states it. Nothing in this record is ever
  /// invented.
  /// <!-- drag-lint:auto BEGIN -->
  /// Used by: DRagLint.Doc.Facts.MineParamTypes (DRagLint.Doc.Facts.pas), DRagLint.Doc.Facts.MineParamNotes (DRagLint.Doc.Facts.pas)
  /// Used in units: DRagLint.Doc.Facts
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TDocParamNote = record
    Name: string;
    Text: string;
  end;

  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// Used by: DRagLint.Doc.Facts.TDocFactsBuilder.Build (DRagLint.Doc.Facts.pas), DRagLint.Doc.Facts.TDocFactsBuilder.Build.ToFactRef (DRagLint.Doc.Facts.pas)
  /// Used in units: DRagLint.Doc.Facts
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TDocFactRef = record
    Display   : string;   { e.g. 'Unit1.DoThing' }
    Location  : string;   { file name only, e.g. 'U1.pas' -- NO :line (volatile) }
    // v14 (D5): 'certain' | 'ambiguous' | 'unverified' | ''. The renderer marks
    // any value OTHER than 'certain'/'' with a trailing ' ?' (honest uncertainty):
    // 'ambiguous' = resolved to this symbol but >1 candidate on the type chain;
    // 'unverified' = a CALL SITE whose name matches but which has NO call_edges
    // row (receiver untypable). v(ADP3 T3i): "call site" is load-bearing -- a
    // usage ref (read/write/type_use/member-access) is not one, see
    // REF_KIND_CALL in DRagLint.Core.Model.
    Confidence: string;
  end;

  /// <summary>Index-grounded facts about one symbol, for the managed
  /// DocInsight remarks block. All lists are capped for display; the *Total
  /// fields carry the true count so the renderer can add '(+N more)'.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// Used by: DRagLint.CLI.DoHover (DRagLint.CLI.pas), DRagLint.Doc.Document.TDocumenter.BuildForSymbol (DRagLint.Doc.Document.pas), DRagLint.Doc.Drift.TDocDrift.Analyze (DRagLint.Doc.Drift.pas), declaration (DRagLint.Doc.Facts.pas), DRagLint.Doc.Facts.TDocFactsBuilder.Build (DRagLint.Doc.Facts.pas) (+5 more)
  /// Used in units: DRagLint.CLI, DRagLint.Doc.Document, DRagLint.Doc.Drift, DRagLint.Doc.Facts, DRagLint.Doc.Regions, DRagLint.LSP.Server
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TDocFacts = record
    CalledFrom     : TArray<TDocFactRef>;
    Calls          : TArray<string>     ;
    UsedInUnits    : TArray<string>     ;
    Raises         : TArray<string>     ;
    ReturnType     : string             ;
    // v(item1 T8): distinct return-expression RHS strings mined from the
    // function's body via the hover MineReturnExpressions miner (DRagLint.
    // Hover.Returns) -- the SAME pure miner the hover popup uses, so hover
    // and autodoc's <returns> agree. RAW (XML-unescaped); Task 9's emit
    // escapes at render time. Capped at Build's AMaxReturnCases (first-seen
    // order, truncated). Empty for procedures (ReturnType = '') and whenever
    // AMaxReturnCases <= 0 (enumeration disabled -> bare TODO at emit).
    ReturnCases    : TArray<string>     ;
    CalledFromTotal: Integer            ;
    CallsTotal     : Integer            ;
    UsedInTotal    : Integer            ;
    // v(ADF T3): ground-truth from the Pascal 'deprecated' DIRECTIVE on the decl
    // (NOT the <deprecated/> doc-comment TAG -- see DRagLint.Parser.DocComments'
    // TParsedDoc.Deprecated for that unrelated concept). Neither Signature nor
    // Modifiers captures the directive (Modifiers is visibility-only, Signature is
    // args+return-type only -- confirmed empirically), so Build falls back to a
    // source-line read at the declaration's StartLine. Deprecated=True whenever the
    // directive is present; DeprecatedMsg holds the optional message string
    // (quotes stripped), '' for a bare 'deprecated;'.
    Deprecated     : Boolean            ;
    DeprecatedMsg  : string             ;
    // v(ADF T4): OPT-IN <seealso> doc-source. The RELATED symbols for the decl,
    // each a REAL indexed qualified name (a resolved outgoing callee UNION a
    // sibling member of the same parent type), deduped, sorted, and capped at
    // SEEALSO_CAP. Populated ONLY when Build's AIncludeSeeAlso is True (the
    // --seealso opt-in); empty otherwise, so RenderFactsBlock emits no <seealso>
    // lines by default. NEVER holds a '?'-tagged/unverified/fabricated name --
    // "related" is a heuristic, but every entry is ground-truth.
    SeeAlso        : TArray<string>     ;
    // v(ADF T5): OPT-IN <since> doc-source. The git commit date (YYYY-MM-DD) of
    // the declaration line, derived via TGitSince.FirstCommitDate. Populated ONLY
    // when Build's AIncludeSince is True (the --since opt-in) AND git CONFIDENTLY
    // attributes the line; '' in every failure mode (no git, untracked file,
    // non-zero exit, unparseable output, exception). NEVER a guessed/stale date
    // -- absence over a wrong fact. Empty by default, so RenderFactsBlock emits no
    // <since> line unless --since was passed and git succeeded.
    Since          : string             ;
    // v(ADP1 T3): cheap fact group -- overrides / overridden-by / implements /
    // overload / virtual+abstract markers. Gathered UNCONDITIONALLY (no opt-in
    // flag, like Deprecated) whenever ASym is method-like (skMethod/
    // skConstructor/skDestructor) with a parent (ASym.ParentId > 0); empty/False
    // for everything else (free routines, types, fields, ...).
    //
    // Overrides: the QUALIFIED NAME of the same-named method on the NEAREST
    // resolved CLASS ancestor (via GetTransitiveAncestors + FindChildSymbolByName
    // -- the same helpers PropTree's ResolveInheritedType uses), or '' when ASym
    // does not override an ancestor method.
    Overrides        : string           ;
    // Overridden by: QUALIFIED NAMES of same-named methods on TRANSITIVE
    // DESCENDANT classes (via FindDescendantNames), capped at OVERRIDDENBY_CAP;
    // OverriddenByTotal carries the true distinct count for the renderer's
    // '(+N more)' suffix (mirrors CalledFrom/CalledFromTotal). Empty when no
    // descendant redeclares the method.
    OverriddenBy     : TArray<string>   ;
    OverriddenByTotal: Integer          ;
    // Implements: the QUALIFIED NAME of a same-named member on a resolved
    // INTERFACE ancestor (NAME-BASED ONLY -- no signature-match helper exists in
    // the index, so this is a heuristic, not a verified interface-method proof;
    // see DetectMethodDirectives'/the gather block's header comment). '' when
    // ASym's class implements no interface declaring the same member name.
    Implements       : string           ;
    // Overload k of n: ASym's 1-based position (by declaration StartLine order)
    // among its same-named siblings under the same parent (via
    // FindAllChildSymbols -- the same helper SeeAlso's sibling walk already
    // uses), and the sibling-set size. OverloadCount stays 0/1 (never rendered,
    // RenderFactsBlock requires > 1) when ASym has no same-named sibling.
    OverloadOrdinal  : Integer          ;
    OverloadCount    : Integer          ;
    // virtual / abstract directive markers: GROUND-TRUTH from a bounded SOURCE
    // PROBE (see DetectMethodDirectives) -- the index has NO abstract signal at
    // all, and TSymbol.IsVirtual (Model.pas) COLLAPSES virtual/dynamic/override
    // into one flag, so neither can be read back from stored symbol data. IsVirtual
    // here is True only for a ROOT virtual/dynamic declaration (the override
    // directive is ALSO present -> Overrides is populated instead, so the two
    // lines are never both emitted for the same decl). IsAbstract is True
    // whenever the 'abstract' directive is present, independent of override.
    IsAbstract       : Boolean          ;
    IsVirtual        : Boolean          ;
    // v(ADP2 T3): the routine's McCabe cyclomatic complexity and implementation
    // body line count, read back verbatim from the index-time symbol_facts row
    // (ISymbolStore.GetSymbolFacts -- see DRagLint.Doc.SymbolFacts.
    // TSymbolFactsAnalyzer.Analyze for how they were computed at index time).
    // RAW values, UNTHRESHOLDED here: Build never drops/zeroes Cyclomatic based
    // on docs.complexity_min -- RenderFactsBlock applies that threshold at
    // RENDER time (see its own comment), so changing complexity_min needs no
    // reindex. Cyclomatic = 0 when the symbol has no symbol_facts row (older
    // index, pre-Phase-2) or the analyzer found no matching defProc; either
    // way RenderFactsBlock's >= threshold naturally omits the line (0 is never
    // >= a positive complexity_min) -- absence over a wrong number.
    Cyclomatic       : Integer          ;
    BodyLoc          : Integer          ;
    // v(ADP2 T4): which of the owning class's OWN (non-inherited) instance
    // fields this routine reads vs. writes, read back verbatim from the
    // index-time symbol_facts row (ISymbolStore.GetSymbolFacts -- see
    // DRagLint.Doc.SymbolFacts.TSymbolFactsAnalyzer.Analyze /
    // AnalyzeReadsWrites for the classification rules). RAW PASSTHROUGH, like
    // Cyclomatic/BodyLoc above: the value is ALREADY display-ready (', '-
    // joined, capped at 8 entries, a ' (+N more)' suffix appended when
    // truncated -- see JoinCappedDisplay) because these two columns carry no
    // companion *Total field to defer the cap decision to render time. '' for
    // a free routine (no owning class), an owning class/record with no field
    // children, or an older index with no symbol_facts row -- RenderFactsBlock
    // omits the corresponding side (or the whole line) exactly as it does for
    // every other absent fact.
    ReadsFields      : string           ;
    WritesFields     : string           ;
    /// <summary>v(ADP3 T11): the var/out parameters the routine writes THROUGH,
    /// display-ready as 'AList (var), AReason (out)'. '' when it mutates none,
    /// which is what makes the renderer omit the whole Mutates: line.</summary>
    /// <remarks>RAW PASSTHROUGH of symbol_facts.mutates_params, the same
    /// contract as ReadsFields/WritesFields above -- already ', '-joined, capped
    /// at 8 with a ' (+N more)' suffix (JoinCappedDisplay), so nothing is
    /// re-decided at render time. Complements ReadsFields/WritesFields rather
    /// than overlapping them: those resolve identifiers against the OWNING
    /// CLASS's fields, this one against the routine's own parameter list, so a
    /// free routine is covered too. See DRagLint.Doc.SymbolFacts'
    /// WalkMutatedParams for exactly which write shapes are claimed and which
    /// are deliberately not (an ordinary call's var argument, e.g. SetLength,
    /// and a dot LHS are both absent by design).</remarks>
    MutatesParams    : string           ;
    /// <summary>v(ADP3 T12): the UI controls/globals the routine touches,
    /// display-ready as 'FPanel, Application'. '' when none was DETECTED.</summary>
    /// <remarks>POSITIVE FINDINGS ONLY. An empty value means "no UI touch was
    /// detected", never "this routine is thread-safe", and no surface may
    /// render it as the latter: the curated base-type list in
    /// DRagLint.Doc.SymbolFacts under-reports by construction, so a
    /// thread-safety claim built on it would be false exactly when it mattered.
    /// RAW PASSTHROUGH of symbol_facts.ui_affinity, the same contract as
    /// ReadsFields/MutatesParams above.</remarks>
    UiAffinity       : string           ;
    /// <summary>v(ADP3 T13): the external surfaces and transaction verbs the
    /// routine reaches, as the stored wire string 'resources|transactions' --
    /// e.g. 'file system, registry|starts, commits'. Either side may be empty
    /// ('file system|', '|starts, commits'); '' when nothing was detected.</summary>
    /// <remarks>CATEGORIES, NEVER CALL SITES: the call site is already in
    /// Calls:, and repeating it here would be two facts that can disagree. RAW
    /// PASSTHROUGH of symbol_facts.touches -- the renderer splits on '|' and
    /// omits an empty side, so the two display lines stay independent while the
    /// column stays single. Positive findings only, like UiAffinity above: '' is
    /// "nothing detected", not "no side effects". It is ALSO one of the five
    /// inputs to the derived Pure line -- see
    /// TDocRegions.FormatPhase2FactLines.</remarks>
    Touches          : string           ;
    /// <summary>v(ADP3 T14): DI/ORM wiring -- '; '-joined 'di:'/'ds:' entries,
    /// e.g. 'di:IFolderService (singleton)'. '' when the symbol is neither
    /// registered nor linked to a relation.</summary>
    /// <remarks>CONTROLLER OVERRIDE, exactly like CoveredBy above: computed
    /// LAZILY here in Build via DRagLint.Doc.SymbolFacts.ComputeWiring, NOT read
    /// back from symbol_facts.wiring, which stays unwritten/reserved. orm_links
    /// is produced by a separate post-index pass, so an index-time value would
    /// be empty on every first index and would afterwards point at symbol ids
    /// that no longer exist -- see ComputeWiring's own header. A pure join over
    /// already-indexed tables; no AST analysis, so a failed parse cannot
    /// suppress it.</remarks>
    Wiring           : string           ;
    // v(ADP2 T5): Covered-by-tests -- CONTROLLER OVERRIDE, computed LAZILY
    // here in Build (NOT read back from symbol_facts.covered_by, which stays
    // unwritten/reserved -- see DRagLint.Doc.SymbolFacts' unit banner "TASK 5
    // OVERRIDE" comment for why a reverse test->target edge cannot be filled
    // deterministically at index time). Via DRagLint.Doc.SymbolFacts.
    // ComputeCoveredBy: a bounded reverse call-graph closure -- a hand-rolled
    // BFS over FindResolvedCallers+FindUnresolvedNameCallers, NOT DRagLint.
    // Report.RCallTree (see that unit's banner "IMPLEMENTATION NOTE" for the
    // empirically-confirmed reason a resolved-only reverse tree misses the
    // realistic DUnitX case) -- filtered to routines detected as TESTS (unit/
    // file '*Test' naming convention, or TTestCase ancestry -- see
    // ComputeCoveredBy/IsTestRoutine for the full ruleset and the confirmed
    // reason a [Test] attribute cannot be used as a third rule). Already
    // DISPLAY-READY (', '-joined, capped, a ' (+N more)' suffix when
    // truncated) -- the SAME raw-passthrough contract as ReadsFields/
    // WritesFields above. '' when ASym is not routine-like or no caller, at
    // any bounded hop, is detected as a test.
    CoveredBy        : string           ;
    // v(ADP2 T6): DFM event-wiring -- 'ObjectName.EventProp' (e.g.
    // 'Button1.OnClick') when ASym is a published method wired as an event
    // handler in its OWN .pas file's paired .dfm sibling, read back verbatim
    // from the index-time symbol_facts row (ISymbolStore.GetSymbolFacts --
    // see DRagLint.Doc.SymbolFacts.TSymbolFactsAnalyzer.Analyze /
    // AnalyzeDfmEvent for how it was computed at index time: a focused
    // extractor, DRagLint.Parser.DFM.ExtractDfmEventBindings, parses the
    // paired .dfm and matches ASym.Name against its (object, event-property,
    // handler) triples). RAW PASSTHROUGH, like Cyclomatic/BodyLoc/
    // ReadsFields/WritesFields above -- already the final display string, no
    // cap/threshold logic needed. '' when ASym has no owning class, has no
    // paired .dfm on disk, is not wired to any On*-property in it, or the
    // index predates Phase 2 Task 6 (no symbol_facts row / older column) --
    // absence over a guessed fact.
    DfmEvent         : string           ;
    // v(ADP2 T7): SQL tables touched -- which tables a routine that builds
    // SQL (string literals) reads (FROM/JOIN) vs. writes (INSERT INTO/
    // UPDATE/'UPDATE OR INSERT INTO'/DELETE FROM), read back verbatim from
    // the index-time symbol_facts row (ISymbolStore.GetSymbolFacts -- see
    // DRagLint.Doc.SymbolFacts.TSymbolFactsAnalyzer.Analyze/
    // AnalyzeSqlTables for the extraction pipeline: a NET-NEW, deliberately-
    // not-a-parser literal-concatenation + keyword-anchored table scan --
    // NOT DRagLint.Parser.Sql, which is Firebird DDL over *.sql schema-
    // migration files only and never parses a trigger/procedure body for
    // DML references). RAW PASSTHROUGH, like Cyclomatic/BodyLoc/
    // ReadsFields/WritesFields/DfmEvent above -- already the final display
    // CSVs (', '-joined, capped at 8, a ' (+N more)' suffix when
    // truncated), no cap/threshold logic needed here. '' for either/both
    // when the routine builds no recognizable SQL, its SQL is dynamically
    // assembled (a non-literal operand anywhere in a '+' concatenation), or
    // the index predates Phase 2 Task 7 -- absence over a guessed table.
    SqlReads         : string           ;
    SqlWrites        : string           ;
    // v(ADP2 T8): returned-object ownership -- 'new' (a freshly-constructed
    // object the caller must free), 'borrowed' (a reference the routine does
    // NOT own -- an own-class field or a parameter), 'self', or '' (ABSENCE
    // OVER A WRONG VERDICT: no return site, a disposed Result, ANY
    // unresolved/'unknown' site, a mix of categories across sites, or a
    // 'borrowed'/'self' verdict on a non-reference return type all yield '')
    // -- read back verbatim from the index-time symbol_facts row
    // (ISymbolStore.GetSymbolFacts -- see DRagLint.Doc.SymbolFacts.
    // TSymbolFactsAnalyzer.Analyze/AnalyzeReturnsOwner for the full
    // site-collection + unanimity + object-type-gate ruleset). RAW
    // PASSTHROUGH, like Cyclomatic/BodyLoc/ReadsFields/WritesFields/
    // DfmEvent/SqlReads/SqlWrites above -- already the final stored word, no
    // cap/threshold logic needed; RenderFactsBlock maps 'new' to the fuller
    // 'new (caller owns)' display text at render time.
    ReturnsOwner     : string           ;
    // True when the routine calls ITSELF -- a call_edges self-loop, i.e. an
    // edge out of this symbol whose target is this same symbol id.
    //
    // This is the one caller/callee fact the Calls list DELIBERATELY throws
    // away. That list drops the symbol's own name, for two good reasons stated
    // at its own site: the impl span includes the routine header, whose
    // `Name(` reads as a call to itself, and "Calls: self" says nothing useful
    // anyway. The consequence was that genuine recursion -- which a reader
    // very much wants to know about, because it bounds stack depth and
    // termination -- was invisible in the docs. Stating it as its own fact
    // gives the reader the information without putting a meaningless entry in
    // a list of collaborators.
    //
    // SELF-loops only. MUTUAL recursion (A calls B calls A) needs a cycle walk
    // over call_edges and is deliberately out of scope: this fact is exactly
    // as strong as one edge lookup, and claiming more than that is the kind of
    // over-reach the "absence over wrong" policy exists to prevent.
    //
    // Trustworthy only because B1 landed first. Before arity-aware overload
    // resolution a 2-arg delegator calling its own 3-arg overload produced an
    // edge to ITSELF, so a self-loop meant "recursive OR an overload pair" and
    // this fact would have been wrong on every such pair.
    IsRecursive      : Boolean          ;
    // v(ADP3 T3): the harvested summary text (Task 7 fills this in by mining
    // an adjacent hand-written // comment; until then it is ALWAYS ''). Added
    // in T3 so MergeComment's omit-when-empty guards are real and compile
    // against a genuine field rather than a placeholder -- a fresh/managed
    // <summary> is emitted ONLY when this is non-empty; '' means "nothing to
    // say", so the tag is omitted entirely rather than emitted blank.
    HarvestedSummary : string           ;
    // v(ADP3 T7): the harvested comment's SECOND and later paragraphs, joined
    // by a blank line, already XML-escaped by HarvestText. '' when the source
    // comment was a single paragraph, which is the common case.
    //
    // Rendered inside <remarks> and ABOVE the AUTO_BEGIN facts fence, with
    // AUTO_MARK on its first line so --strip and the drift check can identify
    // exactly these lines. Above the fence, not inside it: the fence is
    // regenerated wholesale every run, and prose sitting inside it would be
    // destroyed by the next regeneration.
    HarvestedRemarks : string           ;
    // v(PHASE A3, ruling D-3): per-parameter MEANING mined from comments inside
    // the declaration's own parameter list. Sparse -- a parameter the source
    // says nothing about simply has no entry, and the emitter then writes its
    // <param> tag with an empty body. See TDocParamNote and MineParamNotes.
    ParamNotes       : TArray<TDocParamNote>;
    // v(2026-08-10, owner ruling): per-parameter DECLARED TYPE, from the indexed
    // signature -- 'const string', 'Boolean = True', 'var TShape'. Text is the
    // rendered qualifier+type, VERBATIM (see TParamDecl in DRagLint.Refactor.
    // DocStub for why it is never re-formatted).
    //
    // Unlike ParamNotes this is DENSE: every declared parameter has an entry,
    // because every declared parameter HAS a type. It is the baseline body of an
    // otherwise-undocumented <param>, so the tag reflects the current situation
    // instead of being an empty shell.
    //
    // The ruling that put it here: "We document all params and documentation has
    // to be current, i.e. delete docs on deleted params, insert on new params
    // with correct types. If any additional prose is present we can include it,
    // but at least we must reflect the current situation." -- and the reason the
    // type is NOT redundant with the declaration one line below is that these
    // comments are also generated into doc/HTML help files, where the parameter
    // table is the deliverable and the signature is not adjacent.
    //
    // ParamNotes still WINS where it has an entry: a human's mined meaning is
    // never replaced by a type name (ruling D-3's "meaning only where the source
    // states it").
    ParamTypes       : TArray<TDocParamNote>;
    // v(ADP3 T4): the documented symbol's OWN kind, copied verbatim from
    // ASym.Kind by Build. Exactly ONE consumer: RenderFactsBlock selects the
    // reference line's VERB from it, via DRagLint.Core.Model.CanBeCallTarget --
    // a callable reads 'Called from:', everything else reads 'Used by:',
    // because a record/class/interface/constant is USED, not called. Nothing
    // else keys off this field, and nothing here restates the kind set: which
    // kinds are callable is owned by CanBeCallTarget's header, the same
    // declaration the CalledFrom gather below already reads.
    //
    // It has to travel on TDocFacts because the renderer is handed AFacts and
    // nothing else -- RenderFactsBlock has no TSymbol, and giving it one would
    // widen a signature four call sites deep for a single enum.
    SymbolKind       : TSymbolKind      ;
  end;

  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// Used by: DRagLint.CLI.DoHover (DRagLint.CLI.pas), DRagLint.Doc.Document.TDocumenter.BuildForSymbol (DRagLint.Doc.Document.pas), DRagLint.Doc.Drift.TDocDrift.Analyze (DRagLint.Doc.Drift.pas), DRagLint.LSP.Server.TLSPServer.HandleHover (DRagLint.LSP.Server.pas)
  /// Used in units: DRagLint.CLI, DRagLint.Doc.Document, DRagLint.Doc.Drift, DRagLint.LSP.Server
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TDocFactsBuilder = class
  public
    /// <summary>Builds the grounded facts for ASym from the index. When
    /// AIncludeSeeAlso is True (the --seealso opt-in), also populates
    /// Result.SeeAlso with the capped related-symbol crefs (resolved callees +
    /// siblings); when False, SeeAlso is left empty. When AIncludeSince is True
    /// (the --since opt-in), populates Result.Since with the git commit date of
    /// the declaration line (via TGitSince, using ABaseDir as the repo root);
    /// '' when git is absent / the line can't be attributed. NO git subprocess
    /// runs unless AIncludeSince is True. Also UNCONDITIONALLY populates the
    /// cheap Overrides/OverriddenBy/Implements/Overload/IsAbstract/IsVirtual
    /// fact group (v(ADP1 T3)) whenever ASym is method-like (skMethod/
    /// skConstructor/skDestructor) with a parent; see each TDocFacts field's own
    /// comment for how it is derived.</summary>
    /// <param name="AStore">Open symbol store to query; not owned. Must not be nil.</param>
    /// <param name="ASym">The symbol to document.</param>
    /// <param name="AIncludeSeeAlso">Opt-in: compute the &lt;seealso&gt; related set. Default False.</param>
    /// <param name="AIncludeSince">Opt-in: derive the git &lt;since&gt; date. Default False.</param>
    /// <param name="ABaseDir">Repo root for the git &lt;since&gt; lookup; '' -&gt; the file's own directory. Default ''.</param>
    /// <param name="AExtraStores">Additional index stores searched ONLY for name-based
    /// callers/used-in units, so cross-DB callers surface; nil/empty = single-store. Default nil.</param>
    /// <param name="AMaxReturnCases">Cap on Result.ReturnCases (v(item1 T8)): at most
    /// this many distinct mined return expressions are kept (first-seen order,
    /// truncated). 0 or negative disables enumeration entirely (ReturnCases stays
    /// empty). Default 20.</param>
    /// <param name="AMaxCallers">Cap on Result.CalledFrom (v(ADP1 T1)): at most
    /// this many distinct resolved/unverified callers are kept (same first-seen
    /// order as the underlying dedupe), truncated; Result.CalledFromTotal always
    /// carries the true distinct count so the renderer can add '(+N more)'. 0 or
    /// negative shows no callers (CalledFrom stays empty, total unaffected).
    /// Default 5.</param>
    /// <returns><!-- drag-lint:auto -->Observed: Default(TDocFacts).</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.CLI.DoHover (DRagLint.CLI.pas), DRagLint.Doc.Document.TDocumenter.BuildForSymbol (DRagLint.Doc.Document.pas), DRagLint.Doc.Drift.TDocDrift.Analyze (DRagLint.Doc.Drift.pas), DRagLint.LSP.Server.TLSPServer.HandleHover (DRagLint.LSP.Server.pas)
    /// Calls: ChangeFileExt, Default, DRagLint.Core.Interfaces.ISymbolStore.FindAllChildSymbols, DRagLint.Core.Interfaces.ISymbolStore.FindCallersByName, DRagLint.Core.Interfaces.ISymbolStore.FindChildSymbolByName, DRagLint.Core.Interfaces.ISymbolStore.FindDescendantNames, DRagLint.Core.Interfaces.ISymbolStore.FindResolvedCallers, DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsByExactName, DRagLint.Core.Interfaces.ISymbolStore.FindUnresolvedNameCallers, DRagLint.Core.Interfaces.ISymbolStore.GetCallEdgesFromSymbol (+28 more)
    /// Complexity: 75 (cyclomatic, outer body), 840 lines (full implementation)
    /// Pure
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindAllChildSymbols"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindCallersByName"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindChildSymbolByName"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindDescendantNames"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindResolvedCallers"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function Build(const AStore: ISymbolStore; const ASym: TSymbol;
      AIncludeSeeAlso: Boolean = False; AIncludeSince: Boolean = False;
      const ABaseDir: string = ''; const AExtraStores: TArray<ISymbolStore> = nil;
      AMaxReturnCases: Integer = 20; AMaxCallers: Integer = 5): TDocFacts;
  end;

  /// <summary>Applies the display cap: a list of ATotal items shows all of them
  /// UNLESS ATotal > 15, in which case only the first 10 are kept and the caller
  /// appends '(+N more)' with N = ATotal - 10. Returns how many to display.</summary>
  /// <param name="ATotal"><!-- drag-lint:auto type -->Integer</param>
  /// <returns><!-- drag-lint:auto -->Observed: 10.</returns>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// Called from: DRagLint.Doc.Facts.TDocFactsBuilder.Build (DRagLint.Doc.Facts.pas)
  /// Pure
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  function DocDisplayCount(ATotal: Integer): Integer;

implementation

uses
  DRagLint.Doc.SymbolFacts, // v(ADP2 T5): ComputeCoveredBy -- see TDocFacts.CoveredBy's comment
  // v(ADP3 T7): HarvestScan / HarvestText, called from Build via
  // HarvestInterfaceComment. IMPLEMENTATION-side because Doc.Harvest reaches
  // Doc.Regions, which uses THIS unit in its interface -- the cycle is legal
  // only while at least one hop goes through an implementation section.
  DRagLint.Doc.Harvest,
  // v(PHASE A3): ExtractParamList only -- MineParamNotes parses the SAME
  // parameter-list text ParseParamNames already splits for the emitter, so both
  // read one extraction rather than two that can disagree about where the list
  // begins and ends.
  DRagLint.Refactor.DocStub,
  // PHASE C B2: SignatureArityRange only. The declared parameter count is
  // already parsed there for B1's overload resolution, and a second parser here
  // would be a second answer to one question -- the drift channel this repo
  // keeps paying for. CallResolver reaches only Core.Model / Core.Interfaces,
  // so this adds no cycle.
  DRagLint.Index.CallResolver;

// PHASE C B2: '/N' when ASymbolId is one of several routines that share a name
// under the same parent -- i.e. an OVERLOAD SET -- where N is its DECLARED
// parameter count. '' otherwise, so every non-overloaded edge renders exactly
// as before and the tag appears only where it settles a real ambiguity.
//
// The count is the DECLARED one, not the required one: a reader matching this
// against a signature on screen is counting the parameters they can see.
function OverloadArityTag(const AStore: ISymbolStore; ASymbolId: Int64): string;
const
  ROUTINE_KINDS = [skMethod, skConstructor, skDestructor, skFunction, skProcedure];
var
  Sym    : TSymbol;
  Sibs   : TArray<TSymbol>;
  Same   : Integer;
  Lo, Hi : Integer;
begin
  Result:= '';
  if (AStore = nil) or (ASymbolId <= 0) then Exit;
  Sym:= AStore.GetSymbolById(ASymbolId);
  if (Sym.Id <= 0) or not (Sym.Kind in ROUTINE_KINDS) then Exit;
  { Same container, same name -- the sibling test 'Overload k of n' already uses
    (FindAllChildSymbols scopes to a class for methods and to the unit symbol for
    free routines), so the two facts cannot disagree about what an overload is. }
  Sibs:= AStore.FindAllChildSymbols(Sym.ParentId);
  Same:= 0;
  for var S in Sibs do
    if (S.Kind in ROUTINE_KINDS) and SameText(S.Name, Sym.Name) then Inc(Same);
  if Same <= 1 then Exit;
  if not SignatureArityRange(Sym.Signature, Lo, Hi) then Exit;
  Result:= '/' + IntToStr(Hi);
end;

function DocDisplayCount(ATotal: Integer): Integer;
begin
  if ATotal > 15 then Result:= 10 else Result:= ATotal;
end;

function LastSeg(const S: string): string;
var P: Integer;
begin
  P:= S.LastDelimiter('.');
  if P >= 0 then Result:= Copy(S, P + 2, MaxInt) else Result:= S;
end;

{ True when ALeaf names exactly ONE call-target symbol in the index, i.e. when an
  unresolved call ref carrying that name can only have meant this one.

  This is the missing precondition of the unresolved-NAME caller bucket. That
  bucket exists so a call the resolver could not bind still shows up somewhere,
  and marks it uncertain -- an honest trade WHEN the name identifies something.
  It does not when the name is shared: `Create` is declared by 35 symbols in
  drag-lint's own index, so attributing an unresolved `Create(` site to any one
  constructor is a 1-in-35 guess repeated across the whole corpus. TQueryRule.
  Create, constructed in exactly ONE place, documented itself with 107 callers.

  The uses-REACHABILITY filter already applied at the call site is necessary and
  was added for this same symptom, but it is not sufficient: within one codebase
  almost everything can reach almost everything through the uses graph, so it
  removed the impossible callers and left the merely-wrong ones.

  UNIQUENESS, not a threshold. 1,501 of this index's callable leaf names are
  unique and 221 are shared, so the bucket keeps working for the large majority
  while the shared names -- exactly the ones a guess cannot distinguish -- stop
  claiming callers. Overload sets count as shared, which is correct: an
  unresolved `Foo(` cannot be attributed to a particular overload either.

  Counts only CALL-TARGET kinds, so a local variable or field that happens to
  share a method's name does not make that method look ambiguous. }
function LeafNameIsUnambiguous(const AStore: ISymbolStore; const ALeaf: string): Boolean;
var
  Cands: TArray<TSymbol>;
  S    : TSymbol        ;
  N    : Integer        ;
begin
  if ALeaf = '' then Exit(False);
  N:= 0;
  Cands:= AStore.FindSymbolsByExactName(ALeaf);
  for S in Cands do
    if CanBeCallTarget(S.Kind) then
    begin
      Inc(N);
      if N > 1 then Exit(False);
    end;
  Result:= N = 1;
end;

{ The EXTRA-STORE form of the same gate, and the difference is load-bearing.

  LeafNameIsUnambiguous asks "does this name identify exactly ONE call target
  here?", which is right for the PRIMARY store -- the symbol being documented is
  declared there, so exactly one means the name is unique.

  It is WRONG for an extra store, where N = 0 is the NORMAL case: an extra DB is
  consulted for CALLERS, not for the declaration. `Compute` declared in uLib's DB
  and called from uApp's DB is the whole point of multi-db, and it has zero
  `Compute` declarations in uApp's store. Requiring exactly one there skipped the
  cross-DB bucket entirely and silently dropped every cross-DB caller.

  Absent is not ambiguous. Ambiguous is TWO OR MORE, so the extra-store test is
  N <= 1. Regression introduced with the leaf-name uniqueness gate (the fix for
  a constructor claiming 107 callers) and caught by tests/autotest/
  run_doc_multidb.ps1 the next time the full battery ran -- which is the argument
  for running it before shipping, not after. }
function LeafNameNotAmbiguous(const AStore: ISymbolStore; const ALeaf: string): Boolean;
var
  Cands: TArray<TSymbol>;
  S    : TSymbol        ;
  N    : Integer        ;
begin
  if ALeaf = '' then Exit(False);
  N:= 0;
  Cands:= AStore.FindSymbolsByExactName(ALeaf);
  for S in Cands do
    if CanBeCallTarget(S.Kind) then
    begin
      Inc(N);
      if N > 1 then Exit(False);
    end;
  Result:= True; { 0 = not declared here (normal for an extra store); 1 = unique }
end;

// v(ADP1 Bug D): True when ARef is a class's OWN self-reference -- a qualified
// implementation header (e.g. 'function TThing.Add: Integer;') emits a
// type_use ref of NameText='TThing' whose EnclosingSymbolId is the method
// itself (TThing.Add). Such a ref is not a genuine "TThing is used here"
// site; it is the class referencing its own name in its own member header.
// Only the "Used in units" gather (below) calls this -- it is a LOCAL
// post-filter, not a change to the shared FindCallersByName query (see that
// block's comment for why FindCallersByName itself must keep matching
// self-refs).
//
// CRITICAL (carried from the twin Bug C fix): a ref with EnclosingSymbolId
// <= 0 is OUTSIDE any routine body (e.g. a unit-scope 'var GThing: TThing;')
// and is NOT a self-reference -- it must be KEPT. Only a ref enclosed by a
// MEMBER of a type SAME-NAMED as ATypeName is a self-reference. AStore.
// GetSymbolById returns a zero/empty TSymbol (Id=0, ParentId=0) for a
// not-found id, so the ParentId<=0 guard also fails safe (keeps the ref)
// when a lookup can't find the enclosing symbol.
function RefIsOwnMemberSelfRef(const AStore: ISymbolStore; const ARef: TReference;
  const ATypeName: string): Boolean;
var Encl, Parent: TSymbol;
begin
  Result:= False;
  if ARef.EnclosingSymbolId <= 0 then Exit;
  Encl:= AStore.GetSymbolById(ARef.EnclosingSymbolId);
  if Encl.ParentId <= 0 then Exit;
  Parent:= AStore.GetSymbolById(Encl.ParentId);
  Result:= SameText(Parent.Name, ATypeName) and (Parent.Kind in [skClass, skInterface, skRecord]);
end;

// v(ADP3 T3i review round 2): can a symbol of this kind ever BE a call target?
// Only a routine can: TCallResolver resolves a call ref to a routine symbol, so
// call_edges.target_symbol_id is always a routine and FindResolvedCallers can
// never return a row for anything else.
//
// v(ADP3 T3i review round 4): THIS HEADER IS THE SINGLE SOURCE for "which kinds
// are exempt from the call-site restriction, and why". The two CalledFrom call
// sites below, the ISymbolStore declaration in DRagLint.Core.Interfaces and the
// store implementation in DRagLint.Storage.SQLite all POINT HERE and write no
// kind list of their own -- because every hand-written enumeration of this set
// has so far been WRONG: once as a code literal (round 1, below) and twice as a
// five-kind paraphrase in comments, retired by round 4.
//
// THE EXEMPT SET IS THE WHOLE COMPLEMENT, NOT A SHORTLIST OF TYPE KINDS. Do not
// write the complement out. Build (this unit) has four callers -- the `document`
// path, doc drift, the CLI `hover` verb and the LSP hover -- and the CalledFrom
// gather has no kind gate of its own, so the two hover callers reach the exempt
// branch with whatever kind the cursor resolved to: skProperty, skField,
// skVarDecl, skConstDecl, skEnumValue, skForm, skUnit, the skSql* kinds and even
// skLocalVar / skParam, not merely the five documentable type kinds
// Doc.Batch.IsDocumentableKind admits.
//
// This -- not a list of "type-like" kinds -- is the correct gate for the
// CalledFrom gather's call-sites-only restriction. For a NON-routine symbol the
// unresolved bucket has never held call sites at all: it holds plain references
// to the symbol's NAME, which the renderer then labels "Called from:". The label
// is the defect; relabelling it (the planned "Used by:" for types) is owned by
// the render workstream. Restricting a non-routine to call sites therefore does
// not correct a caller list, it DELETES a reference list -- so we restrict
// exactly when the symbol could genuinely have callers, and the non-routine path
// stays byte-identical to pre-T3i for EVERY kind.
//
// ROUND 1 GOT THIS WRONG, and the way it was wrong is the lesson: the gate was a
// literal [skClass, skInterface, skRecord], which is the set
// run_doc_no_self_caller.ps1 happens to pin -- the boundary was drawn by what a
// test covered rather than by the semantics. skEnum and skTypeAlias are equally
// documentable (see Doc.Batch.IsDocumentableKind) and silently lost their line.
// PINNED BY tests/autotest/run_doc_no_self_caller.ps1 (a class, including the
// NULL-enclosing unit-scope reference a Bug C regression once dropped) and
// tests/callresolve/run_callsite_kind_universe.ps1 (a class AND an enum).
//
// v(ADP3 T3k, Group 2c item 1): THE DECLARATION MOVED. It now lives in
// DRagLint.Core.Model, exported, and its full rationale lives on its DocInsight
// header there -- do not restate it here or anywhere else. T3i left this open on
// purpose: DRagLint.Doc.SymbolFacts' ComputeCoveredBy held a literal copy of the
// same five kinds asking the same question, and collapsing it needed a code
// change that a comments-only round could not make. Both sites now read the one
// declaration. Core.Model rather than this unit because this unit already uses
// Doc.SymbolFacts in its implementation section, so exporting from here would
// have made the dependency mutual.

// Parses the return type from a signature: the text after the LAST ':' that is
// outside the parameter parentheses. '' when none (a procedure).
function ParseReturnType(const ASig: string): string;
var CloseP, Colon: Integer;
begin
  Result:= '';
  CloseP:= ASig.LastDelimiter(')');
  Colon := ASig.LastDelimiter(':');
  if (Colon > CloseP) and (Colon >= 0) then
    Result:= Trim(Copy(ASig, Colon + 2, MaxInt)).TrimRight([';']);
end;

// True for identifiers that appear as 'Word(' but are Pascal reserved words /
// control-flow / typecasts, not real call targets. Kept out of the Calls list.
//
// v(ADP3 T4f, register K24): the four ROUTINE keywords are here now. The Calls
// body-scan matches `Identifier(`, and an anonymous method or a procedural type
// writes exactly that -- `F := function(A: Integer): Integer` -- so every
// routine holding one rendered a callee literally named 'function'. Visible in
// T4b's own fixture output: AnonHost and InlineProcVar both emitted
// `/// Calls: F, function`. A word that is a reserved word cannot be a call
// target, which is the same reason the other fourteen are here; these four were
// simply never added because nothing in the corpora that built this list had an
// anonymous method in it.
function IsCallSkipWord(const AWord: string): Boolean;
const
  SKIP: array[0..17] of string = (
    'if', 'while', 'for', 'case', 'with', 'and', 'or', 'not', 'in',
    'array', 'set', 'string', 'to', 'downto',
    'function', 'procedure', 'constructor', 'destructor');
var W: string;
begin
  W:= LowerCase(AWord);
  for var S in SKIP do
    if W = S then Exit(True);
  Result:= False;
end;

// True when C can start a Pascal identifier: letter or underscore.
function IsIdentStart(C: Char): Boolean;
begin
  Result:= (C = '_') or ((C >= 'A') and (C <= 'Z')) or ((C >= 'a') and (C <= 'z'));
end;

// True when C can continue a Pascal identifier: letter, digit, or underscore.
function IsIdentPart(C: Char): Boolean;
begin
  Result:= IsIdentStart(C) or ((C >= '0') and (C <= '9'));
end;

// Scans ONE source line for call sites: an identifier immediately followed by
// '(' (allowing spaces before the paren). Adds each captured name to AAcc.
// Lexer-aware within the single line: skips '...' string literals (Pascal
// doubles '' for an embedded quote), stops at a // line comment, and tracks
// { } brace-comment depth. LIMITATION: a { } comment that OPENS on an earlier
// line is not seen here (we scan one line at a time) -- accepted best-effort
// for Chunk 1. Reserved words (if/while/etc.) are dropped via IsCallSkipWord.
procedure CollectCallIdents(const ALine: string; AAcc: TStringList);
var
  I, N, J, K   : Integer;
  InBrace      : Integer; // { } comment nesting depth on this line
  Ident        : string ;
begin
  I:= 1;
  N:= Length(ALine);
  InBrace:= 0;
  while I <= N do
  begin
    if InBrace > 0 then
    begin
      if ALine[I] = '}' then Dec(InBrace);
      Inc(I);
      Continue;
    end;
    if ALine[I] = '{' then begin Inc(InBrace); Inc(I); Continue; end;
    if (ALine[I] = '/') and (I < N) and (ALine[I + 1] = '/') then Break; // line comment
    if ALine[I] = '''' then
    begin
      // Skip a single-quoted string; '' inside stays in-string.
      Inc(I);
      while I <= N do
      begin
        if ALine[I] = '''' then
        begin
          if (I < N) and (ALine[I + 1] = '''') then Inc(I, 2) // escaped quote
          else begin Inc(I); Break; end;
        end
        else Inc(I);
      end;
      Continue;
    end;
    if IsIdentStart(ALine[I]) then
    begin
      J:= I;
      while (J <= N) and IsIdentPart(ALine[J]) do Inc(J);
      Ident:= Copy(ALine, I, J - I);
      // Peek past spaces for a '(' -> this is a call site.
      K:= J;
      while (K <= N) and (ALine[K] = ' ') do Inc(K);
      // A DOTTED call contributes NOTHING to the bare-name bucket. This scan
      // matches `Identifier(`, so it captured only the LAST SEGMENT of a dotted
      // call: `raise EFreshError.Create('boom')` produced a callee literally
      // named `Create`, and every `Obj.Free` / `Q.Open` in the corpus did the
      // same. Those entries are not merely useless, they are WRONG -- a bare
      // `Create` in a Calls list reads as a call to some routine named Create,
      // when what the source says is "a method named Create on some type".
      //
      // The bucket exists for calls the RESOLVER could not bind. For a dotted
      // call the resolver had a receiver and failed to type it, so the honest
      // answer is silence, not a method name detached from its receiver -- the
      // same "absence over wrong" rule the resolver itself follows when it
      // refuses to bind a dotted call to a unit-level routine. A dotted call
      // that DOES resolve is unaffected: it is added, qualified, by the
      // call_edges pass before this fallback runs.
      var PrevCh: Char:= ' ';
      if I > 1 then PrevCh:= ALine[I - 1];
      if (K <= N) and (ALine[K] = '(') and (PrevCh <> '.') and not IsCallSkipWord(Ident) then
        AAcc.Add(Ident);
      I:= J;
      Continue;
    end;
    Inc(I);
  end;
end;

// Scans ONE source line for 'raise <Ident>' -- the whole-word keyword 'raise'
// followed by an identifier (the exception class). Adds the class name to AAcc.
// Same string/comment skipping and single-line limitation as CollectCallIdents.
procedure CollectRaiseClass(const ALine: string; AAcc: TStringList);
var
  I, N, J, K : Integer;
  InBrace    : Integer;
  Ident      : string ;
begin
  I:= 1;
  N:= Length(ALine);
  InBrace:= 0;
  while I <= N do
  begin
    if InBrace > 0 then
    begin
      if ALine[I] = '}' then Dec(InBrace);
      Inc(I);
      Continue;
    end;
    if ALine[I] = '{' then begin Inc(InBrace); Inc(I); Continue; end;
    if (ALine[I] = '/') and (I < N) and (ALine[I + 1] = '/') then Break;
    if ALine[I] = '''' then
    begin
      Inc(I);
      while I <= N do
      begin
        if ALine[I] = '''' then
        begin
          if (I < N) and (ALine[I + 1] = '''') then Inc(I, 2)
          else begin Inc(I); Break; end;
        end
        else Inc(I);
      end;
      Continue;
    end;
    if IsIdentStart(ALine[I]) then
    begin
      J:= I;
      while (J <= N) and IsIdentPart(ALine[J]) do Inc(J);
      Ident:= Copy(ALine, I, J - I);
      if SameText(Ident, 'raise') then
      begin
        // Skip spaces, then capture the next identifier = exception class.
        K := J;
        while (K <= N) and (ALine[K] = ' ') do Inc(K);
        if (K <= N) and IsIdentStart(ALine[K]) then
        begin
          var E: Integer:= K;
          while (E <= N) and IsIdentPart(ALine[E]) do Inc(E);
          AAcc.Add(Copy(ALine, K, E - K));
          I:= E;
          Continue;
        end;
      end;
      I:= J;
      Continue;
    end;
    Inc(I);
  end;
end;

// Reads the 1-based ALine of AFilePath, trimmed. '' on any error (missing
// file, out-of-range line) -- same tolerant pattern the Calls/Raises sections
// above use for their own TFile.ReadAllLines(..., TEncoding.ANSI) reads (source
// is strict ANSI/CRLF per repo convention).
function ReadDeclLine(const AFilePath: string; ALine: Integer): string;
var Lines: TArray<string>;
begin
  Result:= '';
  if (AFilePath = '') or (ALine <= 0) then Exit;
  try
    Lines:= System.IOUtils.TFile.ReadAllLines(AFilePath, TEncoding.ANSI);
  except
    Exit;
  end;
  if ALine <= Length(Lines) then Result:= Trim(Lines[ALine - 1]);
end;

// v(ADP3 T7): fills AFacts.HarvestedSummary / .HarvestedRemarks from the
// hand-written comment above ASym's INTERFACE declaration, or leaves both '' when
// there is nothing acceptable there. Never raises: an unreadable file, a stale
// line number, or a rejected block all mean "no harvested text", which is the
// same absent-not-wrong stance the rest of this unit takes.
//
// See the call site in Build for WHY the scan starts above the existing doc
// region rather than at the declaration line.
// The line a harvest scan should actually start from, given a 1-based
// declaration/definition line: walk UP over any doc region already sitting
// there, so the candidate is the comment ABOVE it.
//
// Load-bearing for idempotency, and it is the T7 fix: MergeComment writes its
// `///` block immediately above the declaration, i.e. BETWEEN the harvested
// comment and the declaration. A second run scanning from the declaration would
// meet `///` first, get hrNone (Task 6's already-DocInsight rule), find
// HarvestedSummary empty, and DROP the summary the first run wrote.
function HarvestStartLine(const ALines: TArray<string>; ADeclLine: Integer): Integer;
var i: Integer;
begin
  Result:= ADeclLine;
  i     := Result - 2;                                     // 0-based, the line above
  if (i >= 0) and (Trim(ALines[i]) = '') then Dec(i);      // FindDocRegionAbove's AllowGap = 1
  while (i >= 0) and Trim(ALines[i]).StartsWith('///') do
  begin
    Result:= i + 1;
    Dec(i);
  end;
end;

// v(PHASE A3, ruling D-3): mines each parameter's MEANING from comments written
// inside the declaration's own parameter list.
//
// WHERE THE TEXT COMES FROM, and why no file is read. The INDEXED signature
// preserves the parameter list VERBATIM, comments and all -- confirmed against a
// real index:
//
//   "(AFirst: Integer { how many times to repeat }; ASecond: string): Integer"
//
// so the meaning is already in hand wherever the author wrote it, with no second
// source read and no dependency on line numbers that go stale.
//
// THE ATTACHMENT RULE, from D-3's own words -- a comment "sitting next to that
// parameter inside the parameter list, between the commas / parentheses that
// separate it from its neighbours":
//
//   * a comment beside ONE NAME belongs to that name alone
//         (ALeft { the left edge }, ARight: Integer)
//   * a comment after the shared TYPE belongs to every name in that group
//         (ALeft, ARight: Integer { a coordinate, in pixels })
//   * a name's own comment WINS over its group's, being the more specific of
//     the two statements about it.
//
// Never invents: a parameter the source says nothing about yields no entry at
// all, which is what leaves its emitted <param> body empty.
// Strips a leading const/var/out/in qualifier from one name chunk.
function StripParamQualifier(const AChunk: string): string;
const
  QUALIFIERS: array[0..3] of string = ('const ', 'var ', 'out ', 'in ');
var
  Q: string;
begin
  Result:= Trim(AChunk);
  for Q in QUALIFIERS do
    if LowerCase(Result).StartsWith(Q) then
    begin
      Result:= Trim(Copy(Result, Length(Q) + 1, MaxInt));
      Break;
    end;
end;

// Splits AText on ASep at bracket depth 0. Braces are deliberately NOT depth --
// ExtractPascalComments removes every comment from a part before any name is read.
function SplitTopLevel(const AText: string; ASep: Char): TArray<string>;
var
  J, D: Integer;
  Acc : string ;
begin
  Result:= nil;
  Acc   := '';
  D     := 0;
  for J:= 1 to Length(AText) do
  begin
    if CharInSet(AText[J], ['(', '[']) then Inc(D)
    else if CharInSet(AText[J], [')', ']']) then Dec(D);
    if (AText[J] = ASep) and (D <= 0) then
    begin
      Result:= Result + [Acc];
      Acc   := '';
    end
    else Acc:= Acc + AText[J];
  end;
  Result:= Result + [Acc];
end;

// v(2026-08-10): the DENSE companion to MineParamNotes -- every declared
// parameter's qualifier+type, rendered for a <param> body. Reads the SAME
// ExtractParamList text MineParamNotes reads and delegates the split to
// ParseParamDecls, so the meaning half and the type half cannot disagree about
// where a parameter ends.
//
// A parameter with no ': Type' at all (untyped var/const) yields NO entry rather
// than an empty one: the emitter must fall through to leaving the tag empty, and
// a blank string here would look like a type that rendered to nothing.
function MineParamTypes(const ASig: string): TArray<TDocParamNote>;
var
  D  : TParamDecl   ;
  Ent: TDocParamNote;
  Txt: string       ;
begin
  Result:= nil;
  for D in ParseParamDecls(ExtractParamList(ASig)) do
  begin
    if Trim(D.TypeText) = '' then Continue;
    if D.Qualifier <> '' then Txt:= D.Qualifier + ' ' + D.TypeText
    else Txt:= D.TypeText;
    Ent.Name:= D.Name;
    Ent.Text:= Txt;
    Result:= Result + [Ent];
  end;
end;

function MineParamNotes(const ASig: string): TArray<TDocParamNote>;
var
  ParamList: string        ;
  Grp      : string        ;
  NamesPart: string        ;
  TypePart : string        ;
  GroupNote: string        ;
  OwnNote  : string        ;
  NameText : string        ;
  Chunk    : string        ;
  Discard  : string        ;
  Note     : TDocParamNote ;
  i, Depth, ColonAt: Integer;
begin
  Result   := nil;
  ParamList:= ExtractParamList(ASig);
  if Trim(ParamList) = '' then Exit;
  for Grp in SplitTopLevel(ParamList, ';') do
  begin
    if Trim(Grp) = '' then Continue;
    // Names / type split at the first top-level ':'. An untyped parameter
    // (`var X`) has none, and then the whole group is names.
    Depth  := 0;
    ColonAt:= 0;
    for i:= 1 to Length(Grp) do
    begin
      if CharInSet(Grp[i], ['(', '[']) then Inc(Depth)
      else if CharInSet(Grp[i], [')', ']']) then Dec(Depth)
      else if (Grp[i] = ':') and (Depth <= 0) then begin ColonAt:= i; Break; end;
    end;
    if ColonAt > 0 then
    begin
      NamesPart:= Copy(Grp, 1, ColonAt - 1);
      TypePart := Copy(Grp, ColonAt + 1, MaxInt);
    end
    else
    begin
      NamesPart:= Grp;
      TypePart := '';
    end;
    GroupNote:= ExtractPascalComments(TypePart, Discard);
    for Chunk in SplitTopLevel(NamesPart, ',') do
    begin
      OwnNote := ExtractPascalComments(Chunk, NameText);
      NameText:= StripParamQualifier(NameText);
      if NameText = '' then Continue;
      if OwnNote = '' then OwnNote:= GroupNote;   // the name's own statement wins
      if OwnNote = '' then Continue;              // structure only: nothing to say
      Note.Name:= NameText;
      Note.Text:= OwnNote;
      Result   := Result + [Note];
    end;
  end;
end;

// v(A1, ruling D-5): a harvested summary whose FIRST SENTENCE names a FOREIGN
// symbol is DEMOTED into the remarks, never discarded.
//
// THE SHAPE, from a real corpus (INBOX-datacopy-2026-08-06, defect 8). An orphan
// note documenting a REMOVAL --
//
//   // SourceStampString used to live here. It MOVED to uFileUtils ...
//
// sat above the next declaration, `TZEISSTransfer.Create`, and the harvester made
// it that constructor's <summary>. The prose is TRUE, just not about this
// declaration; what makes it harmful is that the <summary> is the ONE line a
// Help Insight tooltip shows. So it is moved to <remarks>, where it is still
// available to a reader and no longer claims to be the symbol's contract.
//
// THREE CONDITIONS, all narrow on purpose -- a false demotion loses a good
// summary, and "the summary mentions a helper it calls" is an extremely common
// and entirely legitimate shape:
//
//   1. the identifier must LOOK LIKE a symbol reference, not an English word.
//      The test is a compound-case spelling (an uppercase letter somewhere after
//      the first character, plus at least one lowercase) or a dotted qualifier:
//      SourceStampString, uFileUtils, CSVRoutines.BackupFile all pass; Register,
//      Create, HTML, "the" do not. Without this filter every capitalised English
//      word that happens to be a method name somewhere in a 1.5M-symbol index
//      would demote a perfectly good summary.
//   2. it must RESOLVE in the index. An identifier that names nothing is prose.
//   3. it must be FOREIGN -- EVERY declaration of that name lives in another
//      FILE. A name declared in this unit (or naming this very declaration) is
//      the ordinary "summary mentions its neighbours" case and stays put.
//
// Only the first sentence is inspected: a summary that OPENS on another symbol
// is about that symbol, whereas a later mention is a cross-reference.
function LooksLikeSymbolRef(const AWord: string): Boolean;
var
  i       : Integer;
  HasUpper: Boolean;
  HasLower: Boolean;
begin
  Result:= False;
  if Length(AWord) < 3 then Exit;
  HasUpper:= False;
  HasLower:= False;
  for i:= 2 to Length(AWord) do
    if CharInSet(AWord[i], ['A'..'Z']) then begin HasUpper:= True; Break; end;
  for i:= 1 to Length(AWord) do
    if CharInSet(AWord[i], ['a'..'z']) then begin HasLower:= True; Break; end;
  Result:= HasUpper and HasLower;
end;

// The candidate identifiers of ASummary's first sentence, in order, capped so a
// pathological comment cannot turn one harvest into hundreds of index queries.
// A sentence ends at '. ' (or a terminal '.'); dotted qualifiers are split on
// the dot and each segment offered separately, which is what makes
// 'uFileUtils.SourceStampString' resolvable segment by segment.
function FirstSentenceIdents(const ASummary: string): TArray<string>;
const
  MAX_CANDIDATES = 8;
var
  i, N, J: Integer;
  Sent   : string ;
  Word   : string ;
begin
  Result:= nil;
  N     := Length(ASummary);
  // Terminate the sentence at the first '.' that is followed by whitespace or
  // end-of-string -- so 'uFileUtils.SourceStampString' does not end it.
  Sent:= ASummary;
  for i:= 1 to N do
    if (ASummary[i] = '.') and ((i = N) or CharInSet(ASummary[i + 1], [' ', #9])) then
    begin
      Sent:= Copy(ASummary, 1, i - 1);
      Break;
    end;
  i:= 1;
  N:= Length(Sent);
  while i <= N do
  begin
    if not IsIdentStart(Sent[i]) then begin Inc(i); Continue; end;
    J:= i;
    while (J <= N) and IsIdentPart(Sent[J]) do Inc(J);
    Word:= Copy(Sent, i, J - i);
    i   := J;
    if not LooksLikeSymbolRef(Word) then Continue;
    if Length(Result) >= MAX_CANDIDATES then Break;
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)]:= Word;
  end;
end;

// True when AName resolves in the index and EVERY declaration of it sits in a
// file other than ASym's. Unresolvable -> False (prose, not a symbol reference);
// declared here as well as elsewhere -> False (not foreign).
function NamesForeignSymbol(const AStore: ISymbolStore; const ASym: TSymbol;
  const AName: string): Boolean;
var
  Hits: TArray<TSymbol>;
  H   : TSymbol        ;
begin
  Result:= False;
  if SameText(AName, ASym.Name) or SameText(AName, LastSeg(ASym.QualifiedName)) then Exit;
  Hits:= AStore.FindSymbolsByExactName(AName);
  if Length(Hits) = 0 then Exit;
  for H in Hits do
    if H.FileId = ASym.FileId then Exit;
  Result:= True;
end;

procedure DemoteForeignSummary(const AStore: ISymbolStore; const ASym: TSymbol;
  var AFacts: TDocFacts);
var
  Cand: string;
begin
  if AFacts.HarvestedSummary = '' then Exit;
  for Cand in FirstSentenceIdents(AFacts.HarvestedSummary) do
  begin
    if not NamesForeignSymbol(AStore, ASym, Cand) then Continue;
    // Demote, never discard. The prose keeps its provenance marker via
    // EmitHarvestedRemarks, so a later run re-promotes it automatically once the
    // comment or the declaration changes -- nothing here is a one-way door.
    if AFacts.HarvestedRemarks = '' then
      AFacts.HarvestedRemarks:= AFacts.HarvestedSummary
    else
      AFacts.HarvestedRemarks:= AFacts.HarvestedSummary + #10#10 + AFacts.HarvestedRemarks;
    AFacts.HarvestedSummary:= '';
    Exit;
  end;
end;

procedure HarvestInterfaceComment(const AStore: ISymbolStore; const ASym: TSymbol;
  var AFacts: TDocFacts);
var
  Lines: TArray<string>;
  Res  : THarvestResult;
begin
  if ASym.StartLine <= 0 then Exit;
  try
    Lines:= System.IOUtils.TFile.ReadAllLines(AStore.GetFilePath(ASym.FileId), TEncoding.ANSI);
  except
    Exit; // unreadable -> no harvested text, exactly as if there were no comment
  end;
  if ASym.StartLine > Length(Lines) then Exit;

  // v(ADP3 T8): search order -- INTERFACE declaration first, then the
  // IMPLEMENTATION definition; the first ACCEPTED hit wins and the search stops.
  //
  // Interface-side is preferred because a comment there is unambiguously about
  // the declaration. Implementation-side is where the VOLUME is: on the YADF
  // corpus 120 of 121 harvestable comments sit above the BODY, because authors
  // comment the code they are writing while DocInsight renders the declaration.
  // Promoting onto the declaration is the whole point -- the original comment
  // stays exactly where it is (COPY, never move).
  Res:= HarvestScan(Lines, HarvestStartLine(Lines, ASym.StartLine));

  // Only when the interface side declined, and only when there is a DISTINCT
  // body to look at: for an implementation-only routine the two lines coincide
  // and re-scanning is wasted work rather than wrong.
  if (Res.Reason <> hrAccepted) and (ASym.ImplStartLine > 0) and
     (ASym.ImplStartLine <> ASym.StartLine) and (ASym.ImplStartLine <= Length(Lines)) then
    Res:= HarvestScan(Lines, HarvestStartLine(Lines, ASym.ImplStartLine));

  if Res.Reason <> hrAccepted then Exit;
  HarvestText(Res, AFacts.HarvestedSummary, AFacts.HarvestedRemarks);
  // v(PHASE A1, ruling D-5): last, and on the TEXT rather than on the scan -- the
  // question "is this prose about another symbol" is only answerable once the
  // block has become a summary and a remainder.
  DemoteForeignSummary(AStore, ASym, AFacts);
end;

// Detects a Pascal 'deprecated' DIRECTIVE on ASym's declaration and, when
// present, extracts its optional trailing message string literal. This is
// GROUND-TRUTH ONLY: called just once per Build and the caller sets
// Result.Deprecated/DeprecatedMsg strictly from what this function finds --
// no fabrication when the directive is absent.
//
// SOURCE: empirically confirmed (probe fixture, 'query --name X --json' on a
// scratch DB) that NEITHER TSymbol.Signature (args+return-type only) NOR
// TSymbol.Modifiers (visibility only, e.g. 'public') captures the directive --
// both are '' for a routine regardless of a trailing 'deprecated' clause. The
// parser (DRagLint.Parser.Delphi13.EmitProc et al.) never inspects the
// procAttribute directive nodes for 'deprecated' at all. Fallback: read the
// raw declaration line at ASym.StartLine (ReadDeclLine, above -- the same
// tolerant ANSI-read idiom this unit already uses for Calls/Raises) and
// regex-match the directive there.
//
// Matches (case-insensitive, whole-word 'deprecated'):
//   procedure OldWay; deprecated 'use NewWay';   -> Deprecated=True,  Msg='use NewWay'
//   procedure OldBare; deprecated;               -> Deprecated=True,  Msg=''
//   procedure Fine;                              -> Deprecated=False, Msg=''
function DetectDeprecated(const AStore: ISymbolStore; const ASym: TSymbol; out AMsg: string): Boolean;
var
  Line : string;
  M    : TMatch;
begin
  Result:= False;
  AMsg  := '';
  if ASym.StartLine <= 0 then Exit;
  Line:= ReadDeclLine(AStore.GetFilePath(ASym.FileId), ASym.StartLine);
  if Line = '' then Exit;
  // 'deprecated' as a whole word, optionally followed by a single-quoted
  // message string, up to the terminating ';'. The message capture tolerates
  // a Pascal-escaped '' (embedded quote) via the non-greedy .*? + literal ''.
  M:= TRegEx.Match(Line, '\bdeprecated\b\s*(?:''(.*?)'')?\s*;', [roIgnoreCase]);
  if not M.Success then Exit;
  Result:= True;
  if M.Groups.Count > 1 then
    if M.Groups[1].Success then
      AMsg:= StringReplace(M.Groups[1].Value, '''''', '''', [rfReplaceAll]);
end;

// v(ADP1 T3): detects the virtual / abstract / override / dynamic DIRECTIVES on
// ASym's declaration line. SOURCE PROBE, mirroring DetectDeprecated above --
// the index has NO abstract signal at all (never persisted anywhere), and
// TSymbol.IsVirtual (Model.pas) COLLAPSES virtual/dynamic/override into a
// single flag (cannot tell WHICH directive is present), so the declaration
// TEXT is the only ground truth for these three. Reuses ReadDeclLine (the same
// tolerant ANSI-read idiom DetectDeprecated already uses).
//
// KNOWN BOUND (same as DetectDeprecated): reads ONLY ASym.StartLine. A
// directive written on a LATER line of a WRAPPED multi-line signature (e.g. a
// long param list with 'virtual;' on the line after the closing paren) is
// MISSED -- Phase 1 does not expand to multi-line scanning; single-line
// declarations (as produced by this repo's formatting conventions and the
// task's test fixtures) are the supported case.
//
// Matches whole-word, case-insensitive; a bare declaration with none of these
// words yields all three False (never fabricated).
procedure DetectMethodDirectives(const AStore: ISymbolStore; const ASym: TSymbol;
  out AVirtual, AAbstract, AOverride: Boolean);
var
  Line: string;
begin
  AVirtual := False;
  AAbstract:= False;
  AOverride:= False;
  if ASym.StartLine <= 0 then Exit;
  Line:= ReadDeclLine(AStore.GetFilePath(ASym.FileId), ASym.StartLine);
  if Line = '' then Exit;
  AVirtual := TRegEx.IsMatch(Line, '\b(virtual|dynamic)\b', [roIgnoreCase]);
  AAbstract:= TRegEx.IsMatch(Line, '\babstract\b', [roIgnoreCase]);
  AOverride:= TRegEx.IsMatch(Line, '\boverride\b', [roIgnoreCase]);
end;

class function TDocFactsBuilder.Build(const AStore: ISymbolStore; const ASym: TSymbol;
  AIncludeSeeAlso: Boolean; AIncludeSince: Boolean; const ABaseDir: string;
  const AExtraStores: TArray<ISymbolStore>; AMaxReturnCases: Integer; AMaxCallers: Integer): TDocFacts;
var
  ResCallers: TArray<TResolvedCaller>;
  RC        : TResolvedCaller        ;
  FR        : TDocFactRef            ;
  Distinct  : TList<TDocFactRef>     ;
  Seen      : TDictionary<string, Boolean>;
  Key       : string                 ;
  Shown     : Integer                ;
  I         : Integer                ;

  // Map one resolved-caller row to a display ref. Display is the enclosing
  // routine's qualified name (or the same fallback the name-based path used when
  // the ref has no enclosing symbol); Location is already file-name-only.
  function ToFactRef(const ARC: TResolvedCaller): TDocFactRef;
  begin
    Result:= Default(TDocFactRef);
    Result.Display:= ARC.EnclosingQName;
    // PHASE C B11: a ref with NO enclosing routine is a DECLARATION-position
    // mention -- a field's type, a parameter type, a return type. It used to be
    // rendered as '<TypeName> caller', which names a symbol that does not exist
    // and conveys nothing: 'Used by: TYadfEncoding caller (YADF.Options.pas)'
    // was the WHOLE fact for a type whose every use is a declaration. Say what
    // it is instead. The file is already carried in Location, so the entry reads
    // 'declaration (YADF.Options.pas)' -- and several declaration-position refs
    // in one file now fold into that single honest entry rather than repeating a
    // fabricated one.
    if Result.Display = '' then Result.Display:= 'declaration';
    // PHASE C B2: an overload set shares ONE qualified name, so a rendered edge
    // that names only that name cannot say WHICH overload -- and on a delegating
    // pair (the shape B1 fixes) it reads as self-recursion.
    if Result.Display <> 'declaration' then
      Result.Display:= Result.Display + OverloadArityTag(AStore, ARC.EnclosingSymbolId);
    Result.Location  := ARC.Location;
    Result.Confidence:= ARC.Confidence;
  end;

  // Add FR to Distinct unless a caller with the SAME 'Display|Location' key has
  // already been added. First-seen wins -> resolved bucket (added first) beats a
  // later unverified name-match for the same caller, so a caller that DID resolve
  // to this symbol is never re-marked '?'.
  procedure AddDistinct(const AFR: TDocFactRef);
  begin
    Key:= AFR.Display + '|' + AFR.Location;
    if Seen.ContainsKey(Key) then Exit;
    Seen.Add(Key, True);
    Distinct.Add(AFR);
  end;

begin
  Result:= Default(TDocFacts);

  // v(ADP3 T4): carry the symbol's OWN kind to the renderer, which selects the
  // reference line's verb from it (see TDocFacts.SymbolKind). Set FIRST, before
  // any early-exit path can be added below it: Default(TDocFacts) leaves this at
  // Ord 0, and a wrong kind renders a wrong CLAIM rather than an absent one.
  //
  // v(ADP3 T4f, register K16): the failure mode stated here until 2026-07-29 was
  // backwards, and the identical wrong premise reached T4's brief AND its review
  // prompt because all three inherited it instead of reading the enum. Ord 0 is
  // skUnit (DRagLint.Core.Model.TSymbolKind), which is NOT a call target, so
  // CanBeCallTarget is False for it: an unset field renders 'Used by:' ON A
  // ROUTINE -- not "'Called from:' about a record". The mitigation is unchanged
  // and the field is provably always assigned; only the stated consequence was
  // wrong. Ord 0 being the harmless-looking skUnit is exactly why: the wrong
  // verb appears on the callable half, where it reads most like a bug in the
  // resolver rather than an unset field.
  Result.SymbolKind:= ASym.Kind;

  // v(ADP3 T7): HARVEST the hand-written comment above this symbol's INTERFACE
  // declaration into HarvestedSummary / HarvestedRemarks. Copy, never move --
  // nothing here edits the source; MergeComment writes a separate /// region and
  // the original // comment stays exactly where its author put it.
  //
  // THE SCAN DOES NOT START AT THE DECLARATION LINE, and that is load-bearing.
  // MergeComment writes its /// region immediately ABOVE the declaration, i.e.
  // BETWEEN the harvested comment and the declaration. A second run scanning up
  // from ASym.StartLine would therefore meet /// first, get hrNone (Task 6's
  // already-DocInsight rule), find HarvestedSummary empty, and DROP the summary
  // the first run had just written -- `document --apply` would rewrite the file
  // on every run. So the existing doc region is skipped and the candidate is
  // whatever sits above IT. Anchored on run_doc_p3_harvest_text.ps1's
  // idempotency pair; the blank-line tolerance matches FindDocRegionAbove's own
  // AllowGap=1, so both agree on where a region begins.
  //
  // A HAND-WRITTEN /// block is skipped by the same walk, so a // comment above
  // one is harvested while the hand-written tags are preserved by MergeComment's
  // existing precedence. Which of the two wins when they disagree is Task 8's
  // question, not this call site's.
  HarvestInterfaceComment(AStore, ASym, Result);

  // v(PHASE A3, ruling D-3): per-parameter MEANING, mined from the comments the
  // author wrote inside the parameter list. STRUCTURE is the emitter's job and
  // does not depend on this: a parameter with no note still gets a <param> tag,
  // with an empty body.
  Result.ParamNotes:= MineParamNotes(ASym.Signature);
  Result.ParamTypes:= MineParamTypes(ASym.Signature);

  // Called from: RESOLVED caller refs -> display 'EnclosingQName (file)'.
  // v14 (D5) -- THE BUG FIX. Previously this was name-based
  // (FindCallersByName(LastSeg)), so it listed callers of EVERY same-named method
  // in the codebase. It is now grounded in call_edges (per-site resolved targets):
  //   1. FindResolvedCallers(ASym.Id) -- callers whose resolved call target IS
  //      this symbol. Confidence 'certain' -> plain; 'ambiguous' (>1 candidate on
  //      the type chain) -> ' ?'. A caller resolved CERTAIN to a DIFFERENT symbol
  //      is simply absent here -- that is the exclusion, automatic.
  //   2. FindUnresolvedNameCallers(LastSeg) -- name-matching refs with NO
  //      call_edges row (receiver untypable). These are 'unverified' -> ' ?'
  //      (honest: might or might not be this symbol).
  // The renderer (JoinRefs) appends ' ?' to any Confidence not 'certain'/''.
  //
  // IDEMPOTENCY: the Location is the caller FILE NAME ONLY -- deliberately NO
  // ':line'. A line number is VOLATILE: applying this managed comment inserts N
  // lines above every caller that sits below the insertion point, so on the next
  // index+run the caller's StartLine has shifted and the regenerated facts block
  // would differ from what is on disk -- 'document' would re-write the file every
  // run, breaking the managed-region idempotency promise. TResolvedCaller.Location
  // is already ExtractFileName'd, preserving this invariant on the resolved path.
  //
  // DEDUPE: a caller routine that references the target 2+ times yields multiple
  // rows that -- now that the volatile ':line' is dropped -- collapse to IDENTICAL
  // (Display, Location) pairs. AddDistinct folds them to a single entry keyed on
  // 'Display|Location' (both line-free). Resolved rows are added BEFORE unverified
  // rows, so first-seen dedupe also keeps a caller in the STRONGER bucket (a
  // resolved caller never re-appears as an unverified '?' for the same site).
  // CalledFromTotal is the DISTINCT count and the display cap applies to it.
  //
  // ORDER: FindResolvedCallers orders 'certain' before 'ambiguous', so plain
  // entries precede ' ?' entries within the resolved bucket; the unverified '?'
  // bucket follows -- overall plain-before-'?' as the spec requires.
  Distinct:= TList<TDocFactRef>.Create;
  Seen    := TDictionary<string, Boolean>.Create;
  try
    ResCallers:= AStore.FindResolvedCallers(ASym.Id);
    for RC in ResCallers do
    begin
      FR:= ToFactRef(RC);
      AddDistinct(FR);
    end;
    // Unverified name-match bucket: CALL-SITE refs whose name matches but that
    // have no call_edges row (untypable receiver). v(ADP3 T3i, register E1):
    // until this bucket was restricted to call-site refs it also collected the
    // co-located 'member-access' ref every dotted call emits since 9d7e641 --
    // so a caller that resolved CERTAIN to a DIFFERENT same-named method still
    // appeared here with a ' ?'.
    //
    // NON-ROUTINE KINDS ARE DELIBERATELY EXEMPT, and this is a scope boundary,
    // not an oversight. WHICH kinds and WHY are stated once, on
    // CanBeCallTarget's own header above; the parameter's contract is stated
    // once, on the ISymbolStore declaration in DRagLint.Core.Interfaces.
    // v(ADP3 T3i review round 4): neither is paraphrased here, and no kind list
    // is written here -- the paraphrase that used to sit at this spot named five
    // type kinds and was narrower than the predicate it described.
    //
    // USES-SCOPE (INBOX-datacopy 2026-08-06 section 7): ASym.FileId scopes the
    // bucket to refs made from a file that can REACH this declaration through
    // the uses graph. A bare name is not evidence on its own -- 'Create' matched
    // 28 unresolved call refs in one small project and every constructor in the
    // index claimed all of them, naming routines whose units cannot use the
    // target at all. Reachability is a Delphi rule, not a guess, so what it
    // removes is not merely improbable but impossible. Contract + the
    // NULL-target and per-DB-file-id caveats: the ISymbolStore declaration.
    //
    // AMBIGUOUS LEAF NAME -> NO BUCKET AT ALL. Reachability (above) removes the
    // callers that are IMPOSSIBLE; it cannot remove the ones that are merely
    // WRONG, and within a single codebase almost everything reaches almost
    // everything. `Create` is declared by 35 symbols here, so every unresolved
    // `Create(` site was being claimed by every constructor in the index --
    // TQueryRule.Create, constructed in ONE place, listed 107 callers.
    // See LeafNameIsUnambiguous for why the test is uniqueness and not a
    // threshold.
    //
    // THE GATE APPLIES TO CALL TARGETS ONLY. For a TYPE (class/record/enum/
    // alias) this bucket is not a fallback -- it is the ONLY source of the
    // "Used in units:" / "Used by:" facts, because a type is never a call target
    // and so has no resolved edges to fall back to. Gating it there does not
    // remove a guess, it deletes the fact outright: three suites said so
    // immediately (a RECORD stopped rendering "Used by:" at all).
    //
    // CanBeCallTarget is the same predicate already passed to
    // FindUnresolvedNameCallers below to choose the ref-kind restriction, so the
    // two halves of this decision cannot drift apart.
    // AND THE GATE NEEDS A RESOLVED-ANCHOR ESCAPE. Ambiguity alone is not the
    // danger; ambiguity with NOTHING to compare against is. When at least one
    // caller resolved, adding a guess makes the list MIXED -- and the ' ?'
    // marker renders on a mixed list, so the reader is told which entries are
    // weak. That is the honest trade the bucket was designed for, and
    // calledfrom.pas exercises it deliberately (TAlpha.Run / TBeta.Run share a
    // name; the untypable U.Run site must still surface, marked).
    //
    // The 107-caller case had NO resolved caller, so every entry was uncertain,
    // the marker was suppressed as uniform, and a wholly-guessed list rendered
    // exactly like a verified one. That is the combination this suppresses:
    // ambiguous name AND no resolved anchor.
    var NameUnambiguous: Boolean:=
      (not CanBeCallTarget(ASym.Kind))
      or (Distinct.Count > 0)
      or LeafNameIsUnambiguous(AStore, LastSeg(ASym.QualifiedName));
    if NameUnambiguous then
    begin
      ResCallers:= AStore.FindUnresolvedNameCallers(LastSeg(ASym.QualifiedName),
                                                   CanBeCallTarget(ASym.Kind),
                                                   ASym.FileId);
      for RC in ResCallers do
      begin
        FR:= ToFactRef(RC);
        FR.Confidence:= 'unverified'; // enforce the '?' marker regardless of store value
        AddDistinct(FR);
      end;
    end;

    // Extra stores (multi-DB fan-out): NAME-BASED bucket only. ASym.Id is a
    // PRIMARY-store-only key -- in an extra store the same symbol has a
    // different Id (or isn't defined there at all), so FindResolvedCallers
    // would be meaningless there. FindUnresolvedNameCallers is Id-independent
    // (keys on the qualified name's last segment), so it is exactly how a
    // cross-DB caller (e.g. a COMMON reference) surfaces. Every extra-store hit
    // is marked 'unverified' -- AddDistinct's Display|Location dedupe folds a
    // caller seen in both the primary and an extra store into one entry.
    for var ExStore in AExtraStores do
    begin
      if ExStore = nil then Continue;
      // AMBIGUITY GATE, and it matters MORE here than on the primary store: the
      // note below records that this path has no uses-scope filter at all, so
      // this is the one bucket where section 7's noise could still arrive. The
      // name must identify one call target in BOTH stores -- shared in either
      // means an unresolved ref naming it cannot be attributed to this symbol,
      // and a fact must not depend on which DB a reference happened to live in.
      if not (NameUnambiguous and LeafNameNotAmbiguous(ExStore, LastSeg(ASym.QualifiedName))) then Continue;
      // Same kind gate as the primary store above -- the two must agree, or a
      // symbol's fact would depend on which DB a reference happened to live in.
      // The expression is repeated because it is CODE; the reasoning is not, and
      // lives on CanBeCallTarget's header.
      // NO uses-scope here, and that is not an oversight: ASym.FileId is a
      // PRIMARY-store key, and file ids are per-DB, so handing it to another
      // store would seed the reachable set from an unrelated file (or none) and
      // silently drop every cross-DB caller. The scope filter is only sound
      // where the id and the uses graph come from the same DB. The consequence
      // is that section 7's noise can still arrive from an EXTRA store; fixing
      // that needs the target unit resolved BY NAME inside each extra store,
      // which is a separate change.
      ResCallers:= ExStore.FindUnresolvedNameCallers(LastSeg(ASym.QualifiedName),
                                                    CanBeCallTarget(ASym.Kind));
      for RC in ResCallers do
      begin
        FR:= ToFactRef(RC);
        FR.Confidence:= 'unverified';
        AddDistinct(FR);
      end;
    end;

    // v(ADP1 T1): CalledFrom's display cap is the CONFIG-DRIVEN AMaxCallers
    // (manifest docs.max_callers, default 5 -- see LoadDocMaxCallers), NOT the
    // shared DocDisplayCount helper (that >15-total-\>10-shown rule still
    // governs Calls:/Used in units: below, unchanged). Simple threshold: show
    // AMaxCallers when the distinct count exceeds it, else show all; the
    // renderer's MoreSuffix appends '(+N more)' from CalledFromTotal.
    Result.CalledFromTotal:= Distinct.Count;
    if Distinct.Count > AMaxCallers then Shown:= AMaxCallers else Shown:= Distinct.Count;
    if Shown < 0 then Shown:= 0;
    SetLength(Result.CalledFrom, Shown);
    for I:= 0 to Shown - 1 do Result.CalledFrom[I]:= Distinct[I];
  finally
    Seen.Free;
    Distinct.Free;
  end;

  // Returns: type from the signature, else '' (procedures).
  Result.ReturnType:= ParseReturnType(ASym.Signature);

  // ReturnCases: v(item1 T8) -- enumerate distinct return cases for a function's
  // <returns> doc (Task 9 emits them). Reuses MineReturnExpressions (DRagLint.
  // Hover.Returns) -- the SAME pure miner the hover popup already uses, so hover
  // and autodoc agree on what a routine returns. Guarded so PROCEDURES (no
  // return type) never get ReturnCases, AMaxReturnCases <= 0 disables mining
  // entirely (bare TODO at emit), and only a valid impl-line span is scanned.
  // The body is re-read here (tolerant ANSI read, same idiom as Calls/Raises
  // below) rather than reusing their Src arrays, since this block runs before
  // either of those reads and keeping it self-contained avoids coupling three
  // unrelated Result fields to one shared local.
  if (Result.ReturnType <> '') and (AMaxReturnCases > 0)
     and (ASym.ImplStartLine > 0) and (ASym.ImplEndLine >= ASym.ImplStartLine) then
  begin
    var RSrc: TArray<string>;
    try RSrc:= System.IOUtils.TFile.ReadAllLines(AStore.GetFilePath(ASym.FileId), TEncoding.ANSI);
    except RSrc:= nil; end;
    if Length(RSrc) > 0 then
    begin
      var BodyLines: TArray<string>; SetLength(BodyLines, 0);
      for var Ln:= ASym.ImplStartLine to Min(ASym.ImplEndLine, Length(RSrc)) do
        BodyLines:= BodyLines + [RSrc[Ln - 1]];
      // ASym.QualifiedName is passed so the miner can tell "this span starts a
      // line early at MY header" from "this span starts inside SOMEBODY ELSE'S
      // routine" -- a stale index produces both, and only the first is
      // recoverable. The QUALIFIED name, because the simple one cannot separate
      // TAlpha.Same from TBeta.Same and such pairs are adjacent in the
      // implementation section, which is where a stale span lands.
      var Mined: TArray<string>:= MineReturnExpressions(BodyLines, ASym.QualifiedName);
      if Length(Mined) > AMaxReturnCases then SetLength(Mined, AMaxReturnCases);
      Result.ReturnCases:= Mined;
    end;
  end;

  // Calls (outgoing): v14 (D5 T10) -- PREFER RESOLVED callees, body-scan FALLBACK.
  // T3's original decision (t3-calls-spike-decision.md) still holds for sites
  // call_edges cannot resolve: there is no store method filtering refs by
  // enclosing_symbol_id, and GetReferencesFromFile emits EVERY identifier ref
  // (locals, params, Result, Exit) with ref.Kind not discriminating calls, so a
  // bounded body TEXT-SCAN ('Identifier(' call sites, lexer-skipping strings/
  // comments) is still how UNRESOLVED sites are found. But now that
  // ResolveCallTargets (T5/T6) populates call_edges, resolved sites can show the
  // QUALIFIED callee (e.g. 'receivers.TAlpha.Run') instead of the bare, possibly
  // ambiguous identifier ('Run').
  //
  // UNION WITHOUT DOUBLE-LISTING: a naive union of (resolved qualified names) +
  // (body-scan bare names) would list the SAME call twice (once qualified, once
  // bare) whenever a site resolved. Instead:
  //   1. Pull GetCallEdgesFromSymbol(ASym.Id); for each edge with a resolved
  //      target, add the target's QualifiedName to the final set AND record its
  //      LAST SEGMENT (leaf, e.g. 'Run') in ResolvedLeaves (case-insensitive).
  //   2. Run the existing body-scan into a bare-name set, as before.
  //   3. Add each bare name to the final set UNLESS its leaf is already covered
  //      by ResolvedLeaves -- that bare mention is the SAME call site already
  //      shown qualified, so it is suppressed (not lost: still counted via the
  //      qualified entry). A bare name whose leaf was never resolved (SetLength,
  //      a typecast, an unresolved receiver) still appears -- nothing is lost.
  // Example: TCaller calls TAlpha.Run (resolves) and TBeta.Run (resolves) and a
  // bare 'B.Free' (does not resolve) in the same body -> final set shows BOTH
  // qualified Run callees plus bare 'Free'; the bare 'Run' text is suppressed.
  //
  // IDEMPOTENCY: the final set is built into a Sorted/CaseInsensitive/dupIgnore
  // TStringList (same discipline as the old CallSet), so the displayed order is
  // deterministic regardless of GetCallEdgesFromSymbol's row order or body-scan
  // encounter order. Qualified names carry no line numbers, so re-running
  // document --apply after a reindex reproduces the identical list.
  if (ASym.ImplStartLine > 0) and (ASym.ImplEndLine >= ASym.ImplStartLine) then
  begin
    var FinalSet: TStringList:= TStringList.Create;
    var ResolvedLeaves: TStringList:= TStringList.Create;
    try
      FinalSet.Sorted:= True;
      FinalSet.Duplicates:= dupIgnore;
      FinalSet.CaseSensitive:= False;
      ResolvedLeaves.Sorted:= True;
      ResolvedLeaves.Duplicates:= dupIgnore;
      ResolvedLeaves.CaseSensitive:= False;

      // 1. Resolved callees (qualified), via call_edges.
      var Edges: TArray<TCallEdge>:= AStore.GetCallEdgesFromSymbol(ASym.Id);
      for var Edge in Edges do
        if Edge.TargetSymbolId > 0 then
        begin
          // The self-loop IS the recursion fact. Detected on the edge set that
          // is already being walked, so it costs nothing extra, and detected on
          // the SYMBOL ID rather than the name -- a name test would call an
          // overload pair recursive, which is precisely the shape B1 had to fix
          // in the resolver.
          if Edge.TargetSymbolId = ASym.Id then Result.IsRecursive:= True;
          var TargetQName: string:= AStore.GetSymbolById(Edge.TargetSymbolId).QualifiedName;
          if TargetQName <> '' then
          begin
            // PHASE C B2: tag the ARITY when this name is shared by an overload
            // set. Before B1 the edge itself was wrong (a 3-arg call bound to
            // the 2-arg overload); now that it is right, the RENDERING is what
            // still hides it -- 'Calls: YADF.Layout.FormatSource' on a routine
            // of that very name is a correct edge that reads as recursion.
            //
            // ResolvedLeaves keeps the UNSUFFIXED leaf on purpose: it exists to
            // suppress the body-scan's bare-name duplicate, and the body scan
            // sees 'FormatSource', not 'FormatSource/3'. Tagging it here would
            // have re-admitted every resolved callee a second time as a bare
            // name.
            FinalSet.Add(TargetQName + OverloadArityTag(AStore, Edge.TargetSymbolId));
            ResolvedLeaves.Add(LastSeg(TargetQName));
          end;
        end;

      // 2. Body-scan fallback (bare names), unchanged mechanism.
      var CallSet: TStringList:= TStringList.Create;
      try
        CallSet.Sorted:= True;
        CallSet.Duplicates:= dupIgnore;
        CallSet.CaseSensitive:= False;
        var Src: TArray<string>;
        try
          Src:= System.IOUtils.TFile.ReadAllLines(AStore.GetFilePath(ASym.FileId), TEncoding.ANSI);
        except
          Src:= nil;
        end;
        for var Ln:= ASym.ImplStartLine to Min(ASym.ImplEndLine, Length(Src)) do
          CollectCallIdents(Src[Ln - 1], CallSet);

        // 3. Add a bare name only when its leaf is NOT already covered by a
        // resolved qualified callee (suppress the duplicate, keep the unresolved).
        // Also drop the symbol's OWN name: the impl span includes the routine
        // header line (`Name(...)`), whose `Name(` reads as a call to itself --
        // a spurious self-`Calls:` (seen on free-function overloads). Genuine
        // self-recursion renders nothing useful as "Calls: self" either.
        //
        // COMPILER INTRINSICS are dropped here too. A routine that increments a
        // counter and measures an array rendered
        // `Calls: Assigned, High, Inc, intr.Helper, Low, SetLength` -- five of
        // six entries carrying no information about what the routine does, with
        // the one real callee buried among them. Inc and SetLength are not
        // collaborators; they are syntax.
        //
        // It is safe even though a project MAY declare a routine named High or
        // Abs: a real project routine resolves through call_edges and is added
        // QUALIFIED by step 1, so only the unresolved bare-name fallback is
        // filtered. The unit-level rung widened that safety further -- a bare
        // call to a project routine now resolves across a uses edge as well.
        // The name list itself (DRagLint.Core.Model.IsCompilerIntrinsic) is
        // deliberately restricted to names virtually never user-defined, which
        // is why Copy / Insert / Delete are absent from it.
        for var K:= 0 to CallSet.Count - 1 do
          if (ResolvedLeaves.IndexOf(CallSet[K]) < 0) and (not SameText(CallSet[K], ASym.Name))
             and (not IsCompilerIntrinsic(CallSet[K])) then
            FinalSet.Add(CallSet[K]);
      finally
        CallSet.Free;
      end;

      Result.CallsTotal:= FinalSet.Count;
      var ShownC: Integer:= DocDisplayCount(FinalSet.Count);
      SetLength(Result.Calls, ShownC);
      for var J:= 0 to ShownC - 1 do Result.Calls[J]:= FinalSet[J];
    finally
      ResolvedLeaves.Free;
      FinalSet.Free;
    end;
  end;

  // Used in units: only for type-like kinds. Distinct owning units of refs to
  // the type name (FindCallersByName over its last segment), EXCLUDING each
  // type's own self-references (see RefIsOwnMemberSelfRef, below the fix note).
  // v14 (D5) NOTE -- DELIBERATELY still name-based (NOT call_edges resolved). This
  // counts distinct units that reference a TYPE NAME; those are TYPE references,
  // not method call sites, so they are NOT in call_edges at all (call_edges only
  // holds resolved METHOD calls). The Called-from name-collision bug that D5 fixes
  // does not exist here in the same form -- a type-name collision is far rarer and
  // out of this milestone's scope -- so resolving UsedIn via call_edges does not
  // apply and would break a working feature for zero bug-fix benefit.
  // v(ADP1 Bug D) NOTE -- SELF-REFERENCE FIX (twin of Bug C's Called-from fix,
  // different fact + different function): FindCallersByName is SHARED by
  // rename/refactor, dead-code/unused lint, the context bundler, LSP/MCP
  // references, and `query find-callers` -- all of them STRUCTURALLY need it
  // to keep matching a class's own qualified impl-header refs (e.g.
  // 'function TThing.Add' must resolve as a TThing self-reference for rename
  // to rewrite it to 'TRenamed.Add'), so self-refs must stay in
  // FindCallersByName itself. Excluding them there would break those callers.
  // Instead each ref returned here is screened LOCALLY via
  // RefIsOwnMemberSelfRef before being added to UnitSet: previously every
  // class with an implemented method acquired a spurious "Used in units:
  // <own unit>" fact purely from its own method headers (the class always
  // "uses itself"), so EVERY such class was wrongly "documented" under the
  // facts-only gate. A ref with no enclosing symbol (a unit-scope 'var G: T;')
  // is NOT a self-reference and is always kept -- see RefIsOwnMemberSelfRef's
  // header comment for the NULL-enclosing lesson carried from Bug C.
  // v(ADP3 T3i review round 2): DELIBERATELY ITS OWN SET, NOT CanBeCallTarget's
  // complement, and round 1's attempt to share one declaration between this gate
  // and the CalledFrom gate was the error that hid the skEnum/skTypeAlias bug.
  // The two decisions look alike but their correct sets DIFFER: "which kinds are
  // exempt from the call-site restriction" is every non-routine kind, whereas
  // "which kinds get a Used in units: fact" is these three and always has been.
  // Widening this one to match would ADD a brand-new fact line to every enum and
  // alias -- a behaviour change nobody asked for, in the opposite direction to
  // the one being fixed. Sharing is only safe when two sites answer the SAME
  // question; here they do not, so they get one declaration each.
  //
  // The identical set also appears in RefIsOwnMemberSelfRef above, and is
  // deliberately NOT folded in with this one either: that one asks "is the
  // ENCLOSING symbol's parent a named type, so this ref is a self-reference",
  // which is a property of the ref's neighbourhood rather than of the symbol
  // being documented. Three coincident literals would be worth collapsing; two
  // sites answering two different questions is the same trap in miniature.
  if ASym.Kind in [skClass, skInterface, skRecord] then
  begin
    var URefs: TArray<TReference>:= AStore.FindCallersByName(LastSeg(ASym.QualifiedName));
    var UnitSet: TStringList:= TStringList.Create;
    try
      UnitSet.Sorted:= True;
      UnitSet.Duplicates:= dupIgnore;
      UnitSet.CaseSensitive:= False;
      for var UR in URefs do
        if not RefIsOwnMemberSelfRef(AStore, UR, LastSeg(ASym.QualifiedName)) then
          UnitSet.Add(ChangeFileExt(ExtractFileName(AStore.GetFilePath(UR.FileId)), ''));
      // Extra stores (multi-DB fan-out): same name-based query, but resolve
      // each ref's file path -- and screen self-refs -- via the EXTRA store's
      // OWN FileId/symbol-id maps (ExStore.GetFilePath / ExStore passed into
      // RefIsOwnMemberSelfRef) -- FileIds AND symbol ids are per-DB, so using
      // AStore for an extra store's ref would read the wrong (or a
      // coincidentally valid but wrong) path/symbol. UnitSet is
      // case-insensitive dupIgnore, so a unit name seen in both stores
      // collapses to one entry.
      for var ExStore in AExtraStores do
      begin
        if ExStore = nil then Continue;
        var ExURefs: TArray<TReference>:= ExStore.FindCallersByName(LastSeg(ASym.QualifiedName));
        for var EUR in ExURefs do
          if not RefIsOwnMemberSelfRef(ExStore, EUR, LastSeg(ASym.QualifiedName)) then
            UnitSet.Add(ChangeFileExt(ExtractFileName(ExStore.GetFilePath(EUR.FileId)), ''));
      end;
      Result.UsedInTotal:= UnitSet.Count;
      var ShownU: Integer:= DocDisplayCount(UnitSet.Count);
      SetLength(Result.UsedInUnits, ShownU);
      for var K:= 0 to ShownU - 1 do Result.UsedInUnits[K]:= UnitSet[K];
    finally
      UnitSet.Free;
    end;
  end;

  // Raises: 'raise <Ident>' exception class names in the body, deduped.
  if (ASym.ImplStartLine > 0) and (ASym.ImplEndLine >= ASym.ImplStartLine) then
  begin
    var RaiseSet: TStringList:= TStringList.Create;
    try
      RaiseSet.Sorted:= True;
      RaiseSet.Duplicates:= dupIgnore;
      RaiseSet.CaseSensitive:= False;
      var Src2: TArray<string>;
      try
        Src2:= System.IOUtils.TFile.ReadAllLines(AStore.GetFilePath(ASym.FileId), TEncoding.ANSI);
      except
        Src2:= nil;
      end;
      for var Ln2:= ASym.ImplStartLine to Min(ASym.ImplEndLine, Length(Src2)) do
        CollectRaiseClass(Src2[Ln2 - 1], RaiseSet);
      Result.Raises:= RaiseSet.ToStringArray;
    finally
      RaiseSet.Free;
    end;
  end;

  // Deprecated: ground-truth 'deprecated' directive detection (see
  // DetectDeprecated's header comment for the source/probe rationale).
  var DepMsg: string;
  Result.Deprecated:= DetectDeprecated(AStore, ASym, DepMsg);
  Result.DeprecatedMsg:= DepMsg;

  // v(ADP1 T3): cheap fact group -- overrides / overridden-by / implements /
  // overload / virtual+abstract markers. GROUND-TRUTH via the SAME mapped
  // ancestry/descendant/sibling helpers already used elsewhere in this unit and
  // in PropTree (GetTransitiveAncestors, FindDescendantNames,
  // FindChildSymbolByName, FindAllChildSymbols) -- not reinvented. virtual/
  // abstract have no index signal at all, so they come from the bounded source
  // probe DetectMethodDirectives (see its header comment for the rationale and
  // the known StartLine-only bound).
  //
  // CHEAP EARLY-OUT: only routine-like symbols with a parent (ASym.ParentId > 0)
  // can carry any of these facts -- a type, a field, a const, etc. has none, so
  // the whole block is skipped for every other kind/parentless symbol. Free
  // (unit-level) functions/procedures ARE included because they can be OVERLOADED
  // (the Overload k of n line below); the method-only facts (Overrides /
  // Implements / Overridden by / virtual+abstract) naturally resolve to EMPTY for
  // them -- a unit parent has no class ancestry/descendants and a free routine
  // carries no virtual/abstract directive -- so including them is correct, not
  // just harmless.
  if (ASym.Kind in [skMethod, skConstructor, skDestructor, skFunction, skProcedure]) and (ASym.ParentId > 0) then
  begin
    var ParentSym: TSymbol:= AStore.GetSymbolById(ASym.ParentId);
    if ParentSym.Id > 0 then
    begin
      // Overrides / Implements: walk the parent's TRANSITIVE ancestor closure
      // (GetTransitiveAncestors -- BFS, nearest-first, resolved edges only).
      // A 'class' ancestor declaring the SAME method name -> Overrides (first/
      // nearest match wins, mirrors PropTree's ResolveInheritedType). An
      // 'interface' ancestor declaring the same member name -> Implements
      // (NAME-BASED ONLY: no signature-match helper exists in the index, so an
      // unrelated same-named method that happens to sit under an implemented
      // interface would also match here -- accepted as a documented heuristic
      // for this cheap fact group, not a verified interface-implementation
      // proof).
      var Ancestors: TArray<TTypeAncestor>:= AStore.GetTransitiveAncestors(ParentSym.Id);
      for var Anc in Ancestors do
      begin
        if not (Anc.Resolved and (Anc.SymbolId > 0)) then Continue;
        if SameText(Anc.Kind, 'class') and (Result.Overrides = '') then
        begin
          var BaseMethod: TSymbol:= AStore.FindChildSymbolByName(Anc.SymbolId, ASym.Name);
          if (BaseMethod.Id > 0) and (BaseMethod.Kind in [skMethod, skConstructor, skDestructor]) then
            Result.Overrides:= BaseMethod.QualifiedName;
        end
        else if SameText(Anc.Kind, 'interface') and (Result.Implements = '') then
        begin
          var IfaceMember: TSymbol:= AStore.FindChildSymbolByName(Anc.SymbolId, ASym.Name);
          if IfaceMember.Id > 0 then
            Result.Implements:= IfaceMember.QualifiedName;
        end;
      end;

      // Overridden by: every TRANSITIVE DESCENDANT class of the parent
      // (FindDescendantNames -- distinct, sorted class NAMES only) that
      // redeclares the same method name. Each name is re-resolved to a symbol
      // via FindSymbolsByExactName, trying candidates in order and keeping the
      // FIRST one that actually owns a same-named method-like child -- guards
      // against an unrelated same-named class in a different unit shadowing the
      // real descendant. Capped at OVERRIDDENBY_CAP; OverriddenByTotal carries
      // the true distinct count (mirrors CalledFrom's cap discipline).
      if ParentSym.Kind = skClass then
      begin
        var DescNames: TArray<string>:= AStore.FindDescendantNames(ParentSym.Name);
        var OB: TStringList:= TStringList.Create;
        try
          for var DName in DescNames do
          begin
            var Cands: TArray<TSymbol>:= AStore.FindSymbolsByExactName(DName);
            for var Cand in Cands do
            begin
              if Cand.Kind <> skClass then Continue;
              var DescMethod: TSymbol:= AStore.FindChildSymbolByName(Cand.Id, ASym.Name);
              if (DescMethod.Id > 0) and (DescMethod.Kind in [skMethod, skConstructor, skDestructor]) then
              begin
                OB.Add(DescMethod.QualifiedName);
                Break; // first candidate that owns the method wins; stop scanning this name
              end;
            end;
          end;
          Result.OverriddenByTotal:= OB.Count;
          var ShownOB: Integer:= OB.Count;
          if ShownOB > OVERRIDDENBY_CAP then ShownOB:= OVERRIDDENBY_CAP;
          SetLength(Result.OverriddenBy, ShownOB);
          for var K:= 0 to ShownOB - 1 do Result.OverriddenBy[K]:= OB[K];
        finally
          OB.Free;
        end;
      end;
    end;

    // Overload k of n: siblings under the SAME parent (FindAllChildSymbols --
    // the same helper SeeAlso's sibling walk above already uses) sharing
    // ASym's Name, in the query's start_line order. ASym's own 1-based
    // position within that same-named subset is its ordinal; the subset size
    // is the count. A lone (non-overloaded) method yields Count <= 1 (never
    // rendered -- RenderFactsBlock requires > 1).
    var Siblings: TArray<TSymbol>:= AStore.FindAllChildSymbols(ASym.ParentId);
    var SameName: TList<TSymbol>:= TList<TSymbol>.Create;
    try
      for var Sib in Siblings do
        // Include free (unit-level) functions/procedures, not just methods:
        // FindAllChildSymbols(ParentId) already scopes to the right container
        // (a class for methods, the unit symbol for free routines), so an
        // overloaded free function -- e.g. two `Combine`s at unit scope -- gets
        // its "Overload k of n" line too.
        if (Sib.Kind in [skMethod, skConstructor, skDestructor, skFunction, skProcedure]) and SameText(Sib.Name, ASym.Name) then
          SameName.Add(Sib);
      if SameName.Count > 1 then
      begin
        Result.OverloadCount:= SameName.Count;
        for var OI:= 0 to SameName.Count - 1 do
          if SameName[OI].Id = ASym.Id then
          begin
            Result.OverloadOrdinal:= OI + 1;
            Break;
          end;
      end;
    finally
      SameName.Free;
    end;

    // virtual / abstract / override directive markers (source probe). IsVirtual
    // is suppressed when AOverride is also present -- an override is already
    // (implicitly) virtual, and Overrides is the more informative line, so the
    // two are never both rendered for the same decl (per the task's design
    // decision).
    var DVirtual, DAbstract, DOverride: Boolean;
    DetectMethodDirectives(AStore, ASym, DVirtual, DAbstract, DOverride);
    Result.IsAbstract:= DAbstract;
    Result.IsVirtual := DVirtual and not DOverride;
  end;

  // SeeAlso (opt-in): related-symbol crefs for the <seealso> doc-source. Only
  // computed when AIncludeSeeAlso (the --seealso flag) -- otherwise SeeAlso stays
  // empty and RenderFactsBlock emits nothing, so the default (no --seealso) facts
  // block is byte-for-byte what it was before this doc-source existed.
  //
  // "Related" = RESOLVED outgoing callees UNION sibling members of the same parent
  // type. GROUND-TRUTH: every entry is a REAL indexed qualified name --
  //   1. Resolved callees: GetCallEdgesFromSymbol -> each edge's target
  //      QualifiedName. This is the call_edges truth (D5), so it is NEVER a
  //      '?'-tagged/unverified guess and NEVER a bare body-scan name -- an
  //      UNRESOLVED site (TargetSymbolId <= 0) is simply skipped, so no unverified
  //      name can leak in. (Result.Calls deliberately mixes in body-scan bare
  //      names for the human 'Calls:' line; SeeAlso must not, hence we re-read the
  //      edges here rather than reuse Result.Calls.)
  //   2. Siblings: FindAllChildSymbols(ASym.ParentId) -- other members of the same
  //      parent type -- EXCLUDING ASym itself (by Id). Each contributes its own
  //      QualifiedName. ParentId <= 0 (a unit-level routine, no parent) yields no
  //      siblings; that is fine, the callees still stand.
  // DEDUPE + SORT + CAP: fold into a Sorted/CaseInsensitive/dupIgnore TStringList
  // (deterministic order regardless of edge/sibling encounter order), then take
  // the first SEEALSO_CAP entries. Qualified names carry no line numbers, so a
  // re-run after reindex reproduces the identical list (idempotent).
  if AIncludeSeeAlso then
  begin
    // TWO SETS, NOT ONE, AND CALLEES WIN THE CAP.
    //
    // These were a single sorted set, which meant the cap was decided
    // ALPHABETICALLY across both categories -- and siblings outnumber callees,
    // so on a class with many members the genuinely useful entries (what this
    // routine actually calls) were crowded out by whichever member names happen
    // to sort first. Both defects were invisible while <seealso> was opt-in;
    // turning it on by default is what surfaced them.
    var CalleeSet : TStringList:= TStringList.Create;
    var SiblingSet: TStringList:= TStringList.Create;
    try
      for var L in [CalleeSet, SiblingSet] do
      begin
        L.Sorted:= True;
        L.Duplicates:= dupIgnore;
        L.CaseSensitive:= False;
      end;

      // 1. Resolved callees (qualified, ground-truth via call_edges).
      var SeeEdges: TArray<TCallEdge>:= AStore.GetCallEdgesFromSymbol(ASym.Id);
      for var SE in SeeEdges do
        if (SE.TargetSymbolId > 0) and (SE.TargetSymbolId <> ASym.Id) then
        begin
          var CalleeQName: string:= AStore.GetSymbolById(SE.TargetSymbolId).QualifiedName;
          if CalleeQName <> '' then CalleeSet.Add(CalleeQName);
        end;

      // 2. Sibling members of the same parent TYPE (excluding ASym itself).
      //
      // "Type" is now enforced rather than assumed. The previous comment here
      // read "ParentId <= 0 (a unit-level routine, no parent) yields no
      // siblings" -- that premise is FALSE: a unit-level routine's parent is the
      // UNIT symbol, so this harvested every other routine in the file and
      // called them related. On this repo's own fixture that produced five
      // alphabetically-first unit-mates with no relationship to the documented
      // routine whatsoever.
      //
      // A class's other methods ARE a defensible "see also"; a unit's other
      // routines are just a file listing.
      if ASym.ParentId > 0 then
      begin
        var Parent: TSymbol:= AStore.GetSymbolById(ASym.ParentId);
        if Parent.Kind in [skClass, skInterface, skRecord] then
        begin
          var Siblings: TArray<TSymbol>:= AStore.FindAllChildSymbols(ASym.ParentId);
          for var Sib in Siblings do
            { ROUTINE siblings only. A class's children include its FIELDS, and
              the first run with <seealso> on by default emitted
              `<seealso cref="...FEnabled"/>` and `...FExcludeAncestors` -- a
              cross-reference to a private field is not somewhere a reader can
              usefully be sent, and because the list is capped those entries
              displaced real ones. "See also" means another CALLABLE. }
            if (Sib.Id <> ASym.Id) and (Sib.QualifiedName <> '')
               and (Sib.Kind in [skMethod, skProcedure, skFunction, skConstructor, skDestructor])
               and (CalleeSet.IndexOf(Sib.QualifiedName) < 0) then
              SiblingSet.Add(Sib.QualifiedName);
        end;
      end;

      // Callees first, then siblings; each category sorted, so the whole list is
      // still deterministic and therefore still idempotent across re-runs.
      var Merged: TArray<string>:= nil;
      for var C:= 0 to CalleeSet.Count - 1 do Merged:= Merged + [CalleeSet[C]];
      for var S:= 0 to SiblingSet.Count - 1 do Merged:= Merged + [SiblingSet[S]];
      var ShownS: Integer:= Min(Length(Merged), SEEALSO_CAP);
      SetLength(Result.SeeAlso, ShownS);
      for var S:= 0 to ShownS - 1 do Result.SeeAlso[S]:= Merged[S];
    finally
      SiblingSet.Free;
      CalleeSet .Free;
    end;
  end;

  // Since (opt-in): git commit date of the declaration line. Computed ONLY when
  // AIncludeSince (the --since flag) -- so a batch run WITHOUT --since never
  // spawns git per decl (TGitSince.FirstCommitDate is the only git subprocess and
  // it is behind this guard). GROUND-TRUTH: TGitSince returns 'YYYY-MM-DD' only on
  // a confident git attribution and '' in every failure mode (no git, untracked,
  // non-zero exit, unparseable, exception), so Result.Since is either a real
  // commit date or '' -- never a guessed/stale date. Set only when non-empty, so
  // RenderFactsBlock emits a <since> line only for a real date. ABaseDir is the
  // repo root (TDocBatchOptions.BaseDir); '' -> the file's own directory.
  if AIncludeSince then
  begin
    var SinceDate: string:= TGitSince.FirstCommitDate(
      ABaseDir, AStore.GetFilePath(ASym.FileId), ASym.StartLine);
    if SinceDate <> '' then Result.Since:= SinceDate;
  end;

  // v(ADP2 T3): Complexity fact -- the RAW index-time symbol_facts values,
  // read back verbatim (no threshold applied here: RenderFactsBlock gates the
  // 'Complexity:' line on docs.complexity_min at RENDER time -- see
  // TDocFacts.Cyclomatic's field comment for why). Unconditional, like
  // Deprecated above: a symbol with no symbol_facts row (a non-routine kind,
  // or an index built before Phase 2) reads back Present=False with both
  // fields already zeroed by Default(TSymbolFacts) -- exactly the "no fact"
  // state, never fabricated.
  var SFacts: TSymbolFacts:= AStore.GetSymbolFacts(ASym.Id);
  Result.Cyclomatic:= SFacts.Cyclomatic;
  Result.BodyLoc   := SFacts.BodyLoc;
  // v(ADP2 T4): Reads/Writes fields -- same raw-passthrough contract as
  // Cyclomatic/BodyLoc above (already capped/formatted at analysis time).
  Result.ReadsFields := SFacts.ReadsFields;
  Result.WritesFields:= SFacts.WritesFields;
  // v(ADP3 T11): var/out parameter writes -- same raw-passthrough contract
  // again (capped and formatted at analysis time by AnalyzeMutatesParams).
  Result.MutatesParams:= SFacts.MutatesParams;
  // v(ADP3 T12): UI affinity -- same raw-passthrough contract.
  Result.UiAffinity:= SFacts.UiAffinity;
  // v(ADP3 T13): external surfaces + transaction verbs -- same contract.
  Result.Touches:= SFacts.Touches;
  // v(ADP2 T6): DFM event-wiring -- same raw-passthrough contract as
  // Cyclomatic/BodyLoc/ReadsFields/WritesFields above (already the final
  // display string, computed at index time by DRagLint.Doc.SymbolFacts.
  // TSymbolFactsAnalyzer.Analyze/AnalyzeDfmEvent -- see TDocFacts.DfmEvent's
  // own field comment).
  Result.DfmEvent:= SFacts.DfmEvent;
  // v(ADP2 T7): SQL tables touched -- same raw-passthrough contract as
  // Cyclomatic/BodyLoc/ReadsFields/WritesFields/DfmEvent above (already the
  // final display CSVs, computed at index time by DRagLint.Doc.SymbolFacts.
  // TSymbolFactsAnalyzer.Analyze/AnalyzeSqlTables).
  Result.SqlReads := SFacts.SqlReads;
  Result.SqlWrites:= SFacts.SqlWrites;
  // v(ADP2 T8): returned-object ownership -- same raw-passthrough contract
  // as Cyclomatic/BodyLoc/ReadsFields/WritesFields/DfmEvent/SqlReads/
  // SqlWrites above (already the final stored word, computed at index time
  // by DRagLint.Doc.SymbolFacts.TSymbolFactsAnalyzer.Analyze/
  // AnalyzeReturnsOwner).
  Result.ReturnsOwner:= SFacts.ReturnsOwner;

  // v(ADP2 T5): Covered-by-tests -- CONTROLLER OVERRIDE: computed LAZILY
  // here (NOT read back from SFacts.CoveredBy, which stays unwritten/
  // reserved) via a bounded reverse call-graph closure -- see TDocFacts.
  // CoveredBy's own field comment and DRagLint.Doc.SymbolFacts'
  // ComputeCoveredBy for the full rationale/ruleset. Unconditional call,
  // like Cyclomatic/ReadsFields above: ComputeCoveredBy itself early-outs
  // to '' for a non-routine ASym, so no kind-guard is duplicated here.
  Result.CoveredBy:= ComputeCoveredBy(AStore, ASym);

  // v(ADP3 T14): DI/ORM wiring -- the SECOND controller override, for the same
  // class of reason as CoveredBy above (the data is not in place when the facts
  // loop runs). A pure join over di_bindings/orm_links/fb_relations/fb_columns;
  // symbol_facts.wiring stays unwritten/reserved. See ComputeWiring's header.
  Result.Wiring:= ComputeWiring(AStore, ASym);
end;

end.
