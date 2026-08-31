unit DRagLint.Core.Model;

interface

const
  /// <summary>The engine version, in ONE place.</summary>
  /// <remarks>It used to be written twice: DRagLint.CLI's VERSION said
  /// '1.2.2-alpha' while the LSP handshake's serverInfo.version said
  /// '0.40.5-alpha', eleven releases behind. Editors surface serverInfo.version
  /// in their language-server logs, so anyone debugging the VS Code or Zed
  /// integration read a version that had not existed for months and could not
  /// tell which binary they were actually talking to. Reported from outside
  /// (tree-sitter-delphi13's editor-integration note, 2026-08-09).
  /// This unit is the right home because it is the one both sides already use:
  /// DRagLint.LSP.Server uses Core.Model, and CLI uses LSP.Server, so a
  /// constant here reaches both with no new dependency and no cycle.</remarks>
  DRAGLINT_VERSION = '1.8.0-alpha';

  /// <summary>The identity of what this build EXTRACTS from a byte sequence.
  /// Part of the indexer fingerprint; <see cref="DRAGLINT_VERSION"/> is not.
  /// Bump this ONLY when a re-parse is genuinely required.</summary>
  /// <remarks>
  /// WHY THIS IS SEPARATE FROM THE PRODUCT VERSION. The indexer fingerprint used
  /// DRAGLINT_VERSION, so EVERY release re-parsed EVERY database whether or not
  /// extraction had changed. Cutting v1.4.0-alpha -- two memos, an emit-order
  /// sort and some instrumentation, nothing that changes what the parser sees --
  /// forced a full re-parse of ~7,000 library files plus every project index.
  /// That is hours of machine time bought for nothing, and it recurs on every
  /// version bump.
  ///
  /// SEEDED TO '1.4.0-alpha' DELIBERATELY: it is the value DRAGLINT_VERSION had
  /// when this constant was introduced, so the fingerprint STRING IS UNCHANGED
  /// and no existing index is invalidated by the refactor itself. The very first
  /// benefit lands on the next product bump, which will now cost nothing.
  ///
  /// BUMP IT WHEN, AND ONLY WHEN, A RE-PARSE IS REQUIRED:
  ///   * the parser or grammar changes what it produces (tree-sitter version,
  ///     src\parser)
  ///   * an extractor emits new/different symbols, refs, uses or call edges
  ///     (src\index, src\storage's write side)
  ///   * the preprocessor changes which branches are parsed (src\preprocess)
  ///   * a schema change alters stored parse content -- though `schema` is
  ///     already its own component of the fingerprint
  ///
  /// DO NOT bump it for: performance work, lint rules, output formatting,
  /// documentation, the IDE plugin, the LSP, or anything downstream of the
  /// index. Those cannot make a stored parse wrong.
  ///
  /// THE FAILURE MODE THIS INTRODUCES, STATED PLAINLY: forgetting to bump it
  /// after a real extractor change leaves SILENTLY STALE PARSES -- strictly
  /// worse than a redundant re-parse, because the index then looks complete and
  /// answers confidently with fewer results. `--force-reparse` is the manual
  /// escape hatch. Guarded by tests\autotest\run_extractor_version_guard.ps1,
  /// which fails when extractor sources change without this constant moving.
  /// </remarks>
  DRAGLINT_EXTRACTOR_VERSION = '1.9.0-alpha';

  /// <summary>The identity of what this build DERIVES from parses it already
  /// has -- call_edges, type_ancestors, type_helpers and unit_uses targets.
  /// Deliberately SEPARATE from <see cref="DRAGLINT_EXTRACTOR_VERSION"/>.</summary>
  /// <remarks>
  /// WHY A SECOND STAMP. The extractor version answers "would this build PARSE a
  /// byte sequence differently?", and a bump costs a ~5 hour re-parse of every
  /// index. The resolve pass asks a different question -- "would this build
  /// derive different EDGES from parses it already has?" -- and its remedy is
  /// measured in minutes. One stamp cannot answer both, and measured against
  /// real history it got both wrong in opposite directions:
  /// <para>src\index\DRagLint.Index.CallResolver.pas sits INSIDE the extractor
  /// hash, so 19 resolve-only commits each demanded a full re-parse.</para>
  /// <para>src\storage's resolve writers sit OUTSIDE it: 42 resolve-write
  /// commits, one every 2.2 days, moved nothing and left indexes silently
  /// stale.</para>
  /// The defect is not theoretical. On 2026-08-30 the post-reindex sequence ran
  /// all 31 project sections specifically to pick up an enum-candidate resolve
  /// fix, and the calls resolve executed in THREE of them -- incremental scope
  /// is decided by changed FILES, and a changed resolver is not a changed file.
  /// <para>The surface is scoped BY FUNCTION, in tests\resolver-surface.txt, and
  /// guarded by tests\autotest\run_resolver_version_guard.ps1.</para>
  /// </remarks>
  DRAGLINT_RESOLVER_VERSION = '1.1.0-alpha';

  /// <summary>Hidden per-project folder holding everything drag-lint keeps for
  /// one Delphi project: its index, its drag-lint-project.json, its reports, and
  /// the ghost-compile journal that first created the folder.</summary>
  DRAG_HOME_DIR = '_D-RAG';

type
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Core.Model.pas), DRagLint.Core.Model.TSymbolKindHelper.FromText (DRagLint.Core.Model.pas), declaration (DRagLint.Doc.Facts.pas), declaration (DRagLint.Lint.DocRules.pas), DRagLint.Lint.DocRules.IsDocumentableKind (DRagLint.Lint.DocRules.pas) (+17 more)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TSymbolKind = (  // dl:ok duplicate-global-decl@b16d -- DragLint.Plugin.StructureCache deliberately re-declares this; it is a design-time BPL that shells out to the CLI and uses only System.* units, so depending on Core.Model would link the whole engine into the IDE package
    skUnit, skProgram, skPackage, skClass, skInterface, skRecord, skEnum, skEnumValue, skProcedure, skFunction, skMethod, skConstructor, skDestructor,
    skProperty, skField, skVarDecl, skConstDecl, skTypeAlias, skForm, skComponent,
    // v0.40.5 Tier 1: SQL DDL symbols extracted from MS*.SQL files.
    // Stored in the same symbols table so the existing query/hover/refs
    // infrastructure carries them transparently; the kind text
    // ('sql_table', 'sql_column', ...) is the disambiguator.
    skSqlTable, skSqlColumn, skSqlIndex, skSqlTrigger, skSqlGenerator, skSqlProcedure, skSqlView, skSqlException, skSqlDomain, skSqlConstraint,
    // v0.41: unit initialization / finalization sections (no name; one each
    // per unit at most).  Emitted as unit-child markers so the structure view
    // can list them.
    skInitialization, skFinalization,
    // v14 (D5): typed local vars + params, emitted so call-site receivers
    // can be resolved to a concrete type. Populated starting Task 2.
    skLocalVar, skParam);

  TSymbolKindHelper = record helper for TSymbolKind
    /// <returns><!-- drag-lint:auto -->string -- Observed: KindText[Self].</returns>
    function ToText: string                                          ;
    /// <param name="AText"><!-- drag-lint:auto type -->const string</param>
    /// <returns><!-- drag-lint:auto type -->TSymbolKind</returns>
    /// <exception cref="Exception"><!-- drag-lint:auto --></exception>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Calls: SameText</para>
    /// <para>Pure</para>
    /// <seealso cref="DRagLint.Core.Model.TSymbolKindHelper.ToText"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function FromText(const AText: string): TSymbolKind; static;
  end;

  /// <summary>v11 (M1): the broad category a declared/aliased type resolves to.
  /// Drives the type-aware rule family (float/string-equality, freeandnil-on-
  /// interface, win64-pointer-cast). tcUnknown = could not resolve.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Core.Interfaces.pas), declaration (DRagLint.Core.Model.pas), DRagLint.Diagnostics.FlowChecks.IsManagedType (DRagLint.Diagnostics.FlowChecks.pas), DRagLint.Diagnostics.FlowChecks.IsInterfaceType (DRagLint.Diagnostics.FlowChecks.pas), DRagLint.Lint.ClassMetrics.TClassMetrics.Run (DRagLint.Lint.ClassMetrics.pas) (+3 more)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TTypeCategory = (
    tcUnknown, tcFloat, tcString, tcChar, tcOrdinal, tcBoolean,
    tcInterface, tcClass, tcRecord, tcPointer, tcEnum);

  TTypeCategoryHelper = record helper for TTypeCategory
    /// <returns><!-- drag-lint:auto -->string -- Observed: 'float'; 'string'; 'char';
    /// 'ordinal'; 'boolean'; 'interface'.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Complexity: 11 (cyclomatic, outer body), 15 lines (full implementation)</para>
    /// <para>Pure</para>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function ToText: string;
  end;

  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.Core.Indexer.TIndexer.IndexFile (DRagLint.Core.Indexer.pas), declaration (DRagLint.Core.Interfaces.pas), declaration (DRagLint.Storage.SQLite.pas), DRagLint.Storage.SQLite.TSQLiteSymbolStore.OpenFileTx (DRagLint.Storage.SQLite.pas), DRagLint.Storage.SQLite.TSQLiteSymbolStore.UpsertSymbol (DRagLint.Storage.SQLite.pas) (+10 more)</para>
  /// <para>Used in units: DRagLint.Core.Indexer, DRagLint.Core.Interfaces, DRagLint.Storage.SQLite</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TFileTxToken = record
    FileId: Int64 ;
    Path  : string;
  end;

  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.CLI.PrintSymbols (DRagLint.CLI.pas), DRagLint.CLI.DoQueryFind (DRagLint.CLI.pas), DRagLint.CLI.DoResolveUses (DRagLint.CLI.pas), DRagLint.CLI.DoQueryUnitUsage (DRagLint.CLI.pas), DRagLint.CLI.PreferFrameworkFirst (DRagLint.CLI.pas) (+182 more)</para>
  /// <para>Used in units: DRagLint.CLI, DRagLint.Context.Bundler, DRagLint.Convert.Apply, DRagLint.Convert.PropTree, DRagLint.Core.Indexer, DRagLint.Core.Interfaces, DRagLint.Core.Model, DRagLint.Diagnostics.AstChecks, DRagLint.Diagnostics.FlowChecks, DRagLint.Doc.Batch (+28 more)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TSymbol = record
    Id           : Int64      ;
    FileId       : Int64      ;
    ParentId     : Int64      ;
    Kind         : TSymbolKind;
    Name         : string     ;
    QualifiedName: string     ;
    Signature    : string     ;
    Modifiers    : string     ;
    Section      : string     ; // 'interface' | 'implementation' | '' (usable-from-other-units)
    // v17 (proptree assignability engine, Task 6/R1): a PROPERTY's read/write
    // accessor shape, derived from the declProp getter/setter grammar fields --
    // 'ro' (read only), 'rw' (read+write), 'wo' (write only), or '' for a bare
    // redeclaration (`property Color;`) that inherits the ancestor's accessors.
    // ALWAYS '' for non-property symbols (fields/consts/methods/types). proptree
    // wires is_writable = (prop_access <> 'ro'); an empty value defaults writable
    // (back-compat + inheritance-resolved up-tree). Stored NULL when '' (see
    // UpsertSymbol) so an un-re-indexed pre-v17 DB reads back '' unchanged.
    PropAccess   : string     ;
    // v11 (M1): raw ancestor list text for class/interface symbols, e.g.
    // 'TBar, IBaz'. Empty for non-class/interface or no ancestors. The
    // resolve pass normalizes names + links them cross-unit (type_ancestors).
    Heritage     : string     ;
    // v12 (M1): True when this method is virtually dispatched (virtual/dynamic/
    // override). False for non-methods / static methods. Backs cross-unit
    // virtual-method-in-constructor.
    IsVirtual    : Boolean     ;
    // v15: True when this class/record symbol is a `record helper for T` /
    // `class helper for T` declaration (grammar node `declHelper`, distinct
    // from `declClass`). When True, Heritage carries the helper's TARGET type
    // name (e.g. 'TColor'), not an ancestor list (helpers have no ancestors).
    // The resolve pass (ResolveHelpers) reads this to populate type_helpers.
    IsHelper     : Boolean     ;
    StartLine    : Integer    ;
    StartCol     : Integer    ;
    EndLine      : Integer    ;
    EndCol       : Integer    ;
    // v9: the routine's implementation BODY span (header..final 'end'), so
    // "which routine contains line N" / context bundles don't need a text-scan.
    // 0 when the symbol has no body (types, fields, consts, abstract/interface
    // methods). StartLine/EndLine stay the DECLARATION range.
    ImplStartLine: Integer;
    ImplEndLine  : Integer;
  end; // record

  /// <summary>v(ADP2 T1): index-time ANALYSIS facts about one symbol -- as
  /// opposed to symbol_docs' hand/generated DOC-COMMENT text, these are
  /// derived purely from static analysis: field read/write sets, return
  /// ownership, cyclomatic complexity, body size, the DFM event handler it is
  /// wired to, SQL tables it touches, and covering test qnames. Persisted 1:1
  /// in the symbol_facts table (symbol_id is the PRIMARY KEY / FK to
  /// symbols(id) ON DELETE CASCADE). Task 1 only plumbs storage -- every
  /// analyzer that POPULATES these fields lands in a later Phase 2 task.
  /// CSV-typed fields (ReadsFields/WritesFields/SqlReads/SqlWrites/CoveredBy)
  /// use DRagLint.Doc.SymbolFacts' SymbolFactsCsvJoin/Split helpers.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.CLI.DoDocFactsSelfTest (DRagLint.CLI.pas), DRagLint.Core.Indexer.TIndexer.IndexFile (DRagLint.Core.Indexer.pas), declaration (DRagLint.Core.Interfaces.pas), DRagLint.Doc.Facts.TDocFactsBuilder.Build (DRagLint.Doc.Facts.pas), declaration (DRagLint.Doc.SymbolFacts.pas) (+4 more)</para>
  /// <para>Used in units: DRagLint.CLI, DRagLint.Core.Indexer, DRagLint.Core.Interfaces, DRagLint.Doc.Facts, DRagLint.Doc.SymbolFacts, DRagLint.Storage.SQLite</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TSymbolFacts = record
    SymbolId    : Int64  ;
    ReadsFields : string ;   // CSV of field names read
    WritesFields: string ;   // CSV of field names written
    ReturnsOwner: string ;   // '', 'new', 'borrowed', 'self'
    Cyclomatic  : Integer;   // 0 = not computed
    BodyLoc     : Integer;
    DfmEvent    : string ;   // 'Button1.OnClick' or ''
    SqlReads    : string ;   // CSV of tables read
    SqlWrites   : string ;   // CSV of tables written
    CoveredBy   : string ;   // CSV of test qnames (capped)
    /// <summary>v19 (ADP3 T11): var/out parameters the routine writes to,
    /// display-ready, e.g. 'pReason (out), pList (var)'. '' when none.</summary>
    MutatesParams: string;
    /// <summary>v19 (ADP3 T12): VCL/DevExpress controls or Application/Screen
    /// the routine touches, display-ready, e.g. 'cxGrid1, Application'. ''
    /// when none -- POSITIVE FINDINGS ONLY, never a thread-safety claim.</summary>
    UiAffinity   : string;
    /// <summary>v19 (ADP3 T13): CATEGORIES of external resource touched, plus
    /// transaction verbs, e.g. 'file system, registry|starts, commits'. The
    /// pipe separates the resource list from the transaction list; either side
    /// may be empty. '' when neither.</summary>
    Touches      : string;
    /// <summary>v19 (ADP3 T14): DI/ORM wiring joined from di_bindings /
    /// orm_links / fb_relations, e.g. 'di:IFolderService (singleton)' or
    /// 'ds:qryFolders -&gt; FOLDERS (ID, NAME)'. '' when none.</summary>
    Wiring       : string;
    /// <summary>False when no symbol_facts row exists for SymbolId -- the
    /// renderer's cue to omit every derived doc-comment line entirely.</summary>
    Present     : Boolean;
  end; // record

  /// <summary>v11 (M1): one resolved ancestor edge of a class/interface --
  /// either a direct heritage entry (type_ancestors row) or, in a transitive
  /// closure, a reachable ancestor. Name is the normalized ancestor type name;
  /// Kind is 'class'|'interface'|'?' ('?' when unresolved). Resolved is True
  /// when the ancestor was linked to a defining symbol (SymbolId/FileId set).</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Core.Interfaces.pas), DRagLint.Doc.Facts.TDocFactsBuilder.Build (DRagLint.Doc.Facts.pas), DRagLint.Doc.SymbolFacts.IsTestRoutine (DRagLint.Doc.SymbolFacts.pas), DRagLint.Index.CallResolver.TCallResolver.LookupMethodOnType (DRagLint.Index.CallResolver.pas), DRagLint.LSP.Completion.EnclosingTypeDescendsFrom (DRagLint.LSP.Completion.pas) (+7 more)</para>
  /// <para>Used in units: DRagLint.Core.Interfaces, DRagLint.Doc.Facts, DRagLint.Doc.SymbolFacts, DRagLint.Index.CallResolver, DRagLint.LSP.Completion, DRagLint.Resolver.TypeAt, DRagLint.Storage.SQLite</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TTypeAncestor = record
    Name    : string ;
    Kind    : string ;
    Resolved: Boolean;
    SymbolId: Int64  ;
    FileId  : Int64  ;
    Ordinal : Integer; // position in the declaring type's heritage list (direct edges)
  end;

  /// <summary>v15: one helper-target edge -- a `record helper for T` /
  /// `class helper for T` declaration linked to its target type T. Captured
  /// first-class so the enum-helper generator's create-only-if-missing guard
  /// and the enum-helper-separate-units lint rule never string-parse heritage.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.CLI.DoHelpersOf (DRagLint.CLI.pas), declaration (DRagLint.Core.Interfaces.pas), DRagLint.Lint.ProjectRules.CollectEnumHelperSeparateUnits (DRagLint.Lint.ProjectRules.pas), DRagLint.Refactor.EnumHelper.TEnumHelperRefactoring.Resolve (DRagLint.Refactor.EnumHelper.pas), declaration (DRagLint.Storage.SQLite.pas) (+3 more)</para>
  /// <para>Used in units: DRagLint.CLI, DRagLint.Core.Interfaces, DRagLint.Lint.ProjectRules, DRagLint.Refactor.EnumHelper, DRagLint.Storage.SQLite</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  THelperEdge = record
    HelperSymbolId: Int64 ;
    TargetName    : string;
    TargetSymbolId: Int64 ;
    TargetFileId  : Int64 ;
    HelperKind    : string; // 'record' | 'class'
  end;

  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.CLI.PrintReferences (DRagLint.CLI.pas), DRagLint.CLI.PrintReferencesWithContext (DRagLint.CLI.pas), DRagLint.CLI.DoQueryUnitUsage (DRagLint.CLI.pas), DRagLint.CLI.DoQueryTypeUsage (DRagLint.CLI.pas), DRagLint.CLI.DoQuery (DRagLint.CLI.pas) (+49 more)</para>
  /// <para>Used in units: DRagLint.CLI, DRagLint.Context.Bundler, DRagLint.Convert.Apply, DRagLint.Core.Interfaces, DRagLint.Doc.Facts, DRagLint.Index.CallResolver, DRagLint.Lint.ClassMetrics, DRagLint.Lint.ProjectRules, DRagLint.LSP.Server, DRagLint.MCP.Server (+8 more)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TReference = record
    Id         : Int64  ;
    SymbolId   : Int64  ;
    FileId     : Int64  ;
    Kind       : string ;
    NameText   : string ;
    StartLine  : Integer;
    StartCol   : Integer;
    EndLine    : Integer;
    EndCol     : Integer;
    ContextText: string ; // v0.17: surrounding source lines (find-callers --context N)
    // v13 (v0.82): DB id of the innermost routine whose impl body contains this
    // ref's StartLine; 0 when the ref is not inside any routine body. Set by the
    // indexer (per-file attribution) and read back by the ref-reading store
    // methods (NULL -> 0). Distinct from SymbolId (the ref's target slot).
    EnclosingSymbolId: Int64;
    // v(2026-08-16): the text before the dot at this ref's site -- 'Self' for
    // `Self.Run`, 'B' for `B.Run`, '' for a bare `Run` or for a routine passed
    // by name. The refs table has carried receiver_text since v20; TReference
    // simply never surfaced it, and that gap is not cosmetic: it is the only
    // thing distinguishing a QUALIFIED member access from a BARE pass, which is
    // what find-callers --resolved needs to report a callback reach without
    // mislabelling `Self.Run` as one. Populated by the ref-reading store
    // methods; '' when the column is absent (pre-v20 DB) or NULL.
    ReceiverText: string;
  end;

  /// <summary>v14 (D5): one resolved call-site edge, written by the
  /// ResolveCallTargets pass and read back by the Called-from / find-callees
  /// queries. Stored Confidence is ALWAYS 'certain' or 'ambiguous' (the two
  /// values the resolver writes to call_edges.confidence).</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.CLI.DoDumpCallEdges (DRagLint.CLI.pas), DRagLint.CLI.DoFindCallees (DRagLint.CLI.pas), DRagLint.CLI.DoCallPath (DRagLint.CLI.pas), DRagLint.CLI.RenderCallGraphText (DRagLint.CLI.pas), DRagLint.CLI.BuildCallGraphJson (DRagLint.CLI.pas) (+10 more)</para>
  /// <para>Used in units: DRagLint.CLI, DRagLint.Core.Interfaces, DRagLint.Doc.Drift, DRagLint.Doc.Facts, DRagLint.Index.CallResolver, DRagLint.Storage.SQLite</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TCallEdge = record
    RefId               : Int64 ;
    TargetSymbolId      : Int64 ;
    ReceiverTypeSymbolId: Int64 ;
    Confidence          : string;
    // v20: the call-site RECEIVER TEXT, verbatim as written left of the dot.
    // '' for a bare call AND for `inherited M` (neither has a dot before the
    // name); 'Self'; a bare type or variable name; the FULL dotted chain for a
    // qualified call ('System.JSON.TJSONArray'); or a cast expression, which
    // TryParseCastTarget reduces.
    //
    // Carried on the EDGE record but persisted for EVERY call ref, resolved or
    // not -- the unresolved ones are precisely the ones that need it, because
    // they are what the leaf-name caller bucket draws from. TargetSymbolId = 0
    // does not mean "no receiver to record".
    ReceiverText        : string;
    // v21: the qualified NAME of a target in ANOTHER index (RTL/VCL/DevExpress/
    // Spring), set only when TargetSymbolId = 0. A ref never carries both: a
    // local edge always wins, and cross-DB resolution runs last.
    ExternalTarget      : string;
    // v(2026-08-16): True when the receiver could NOT be derived from source
    // matching the index -- the file was edited since it was indexed, or could
    // not be read. It means "unknown", NEVER "no receiver", and the persistence
    // step must leave the stored receiver_text alone rather than write ''.
    // Defaults False so Default(TCallEdge) keeps the old meaning (known).
    // See TCallResolver.LinesOf and INBOX-whole-db-resolve-degrades-a-stale-index.
    ReceiverUnknown     : Boolean;
  end;

  /// <summary>v14 (D5): one resolved uses-scope edge -- file AFileId can see
  /// (has in its uses graph, directly) the unit whose file is ATargetFileId.
  /// Bulk-read by TCallResolver to build its per-file in-scope set, mirroring
  /// ResolveAncestry's FileScope map. Both ids are always &gt; 0 (the reader
  /// filters out unresolved uses rows).</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Core.Interfaces.pas), DRagLint.Index.CallResolver.TCallResolver.BuildMaps (DRagLint.Index.CallResolver.pas), declaration (DRagLint.Storage.SQLite.pas), DRagLint.Storage.SQLite.TSQLiteSymbolStore.GetUnitScopeEdges (DRagLint.Storage.SQLite.pas)</para>
  /// <para>Used in units: DRagLint.Core.Interfaces, DRagLint.Index.CallResolver, DRagLint.Storage.SQLite</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TFileScopeEdge = record
    FileId      : Int64;
    TargetFileId: Int64;
  end;

  /// <summary>v14 (D5): a RENDERING value for one resolved (or best-effort
  /// unresolved) caller of a target symbol. Confidence is 'certain' |
  /// 'ambiguous' | 'unverified' -- the last for the no-call_edges-row '?'
  /// bucket surfaced by FindUnresolvedNameCallers. Renderer: 'certain' ->
  /// plain; 'ambiguous'/'unverified' -> append ' ?'.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.CLI.DoAmbiguousCalls (DRagLint.CLI.pas), DRagLint.CLI.RenderCallGraphText (DRagLint.CLI.pas), DRagLint.CLI.BuildCallGraphJson (DRagLint.CLI.pas), declaration (DRagLint.Core.Interfaces.pas), DRagLint.Doc.Facts.TDocFactsBuilder.Build (DRagLint.Doc.Facts.pas) (+4 more)</para>
  /// <para>Used in units: DRagLint.CLI, DRagLint.Core.Interfaces, DRagLint.Doc.Facts, DRagLint.Storage.SQLite</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TResolvedCaller = record
    EnclosingSymbolId: Int64 ;
    EnclosingQName   : string;
    Location         : string; // filename only (unchanged; existing consumers rely on this)
    /// <summary>The same file, fully qualified.</summary>
    /// <remarks>Location is deliberately filename-only and must stay that way --
    /// the CLI's JSON is compared across machines, and an absolute path there
    /// would make every golden machine-specific. But a filename cannot be
    /// OPENED, and the hover popup both navigates to these rows and (since
    /// 2026-08-19) renders the source line at them, so the full path has to
    /// travel alongside rather than replace it.</remarks>
    FullPath         : string;
    /// <summary>1-based line of the call site in the caller's file; 0 when unknown.
    /// Added for reverse-calltree; other consumers may ignore it.</summary>
    CallSiteLine     : Integer;
    Confidence       : string;
  end;

  /// <summary>v8: one Spring4D DI registration (interface implemented by impl,
  /// with lifetime). Endpoint names are verbatim, including nested generics.
  /// FileId is filled by the store from the file transaction token.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.CLI.DoWiring (DRagLint.CLI.pas), declaration (DRagLint.Core.Interfaces.pas), DRagLint.Wiring.BuildWiringJson (DRagLint.Wiring.pas), DRagLint.Doc.SymbolFacts.ComputeWiring (DRagLint.Doc.SymbolFacts.pas), declaration (DRagLint.Parser.Delphi13.pas) (+6 more)</para>
  /// <para>Used in units: DRagLint.CLI, DRagLint.Core.Interfaces, DRagLint.Doc.SymbolFacts, DRagLint.Parser.Delphi13, DRagLint.Storage.SQLite, DRagLint.Wiring</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TDiBindingRow = record
    Id           : Int64  ;
    FileId       : Int64  ;
    InterfaceName: string ;
    ImplName     : string ;
    Lifetime     : string ;
    StartLine    : Integer;
    StartCol     : Integer;
    EndLine      : Integer;
    EndCol       : Integer;
  end;

  /// <summary>v(ADP3 T14): one ORM dataset link -- a Delphi symbol tied by the
  /// orm-link pass to a Firebird relation, with that relation's leading columns
  /// in declaration order. Backs the doc/hover 'Dataset: qryFolders -&gt;
  /// FOLDERS (ID, NAME)' line.</summary>
  /// <remarks>
  /// Columns is CAPPED by the reader, not by the renderer, so the row
  /// is display-ready in the same sense reads_fields is: the store decides how
  /// many columns are worth carrying, and every consumer shows the same set.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Core.Interfaces.pas), declaration (DRagLint.Storage.SQLite.pas), DRagLint.Storage.SQLite.TSQLiteSymbolStore.FindOrmDatasetLinks (DRagLint.Storage.SQLite.pas)</para>
  /// <para>Used in units: DRagLint.Core.Interfaces, DRagLint.Storage.SQLite</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TOrmDatasetLink = record
    RelationName: string        ;
    Columns     : TArray<string>;
  end;

  /// <summary>One indexed string-literal occurrence (a message, caption, or
  /// exception text). SymbolId is the enclosing routine/component, resolved by
  /// the indexer post-parse (0 in parser output). Text is the DECODED logical
  /// string (escapes/`#nn`/continuations resolved); never empty.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.Core.Indexer.TIndexer.IndexFile (DRagLint.Core.Indexer.pas), declaration (DRagLint.Core.Interfaces.pas), declaration (DRagLint.Parser.DFM.pas), DRagLint.Parser.DFM.TDfmState.Create (DRagLint.Parser.DFM.pas), DRagLint.Parser.DFM.WalkProperty (DRagLint.Parser.DFM.pas) (+7 more)</para>
  /// <para>Used in units: DRagLint.Core.Indexer, DRagLint.Core.Interfaces, DRagLint.Parser.Delphi13, DRagLint.Parser.DFM, DRagLint.Parser.Sql, DRagLint.Storage.SQLite</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TStringLiteral = record
    Id       : Int64  ;
    FileId   : Int64  ;
    /// <summary>Enclosing symbol; 0 until indexer resolves it.</summary>
    SymbolId : Int64  ;
    /// <summary>Source language: 'pas' | 'dfm' | 'sql'.</summary>
    Source   : string ;
    /// <summary>Literal kind: 'literal'|'const'|'resourcestring'|'format'|'dfm-prop'|'sql-exception'.</summary>
    Kind     : string ;
    /// <summary>Const name / DFM property / exception name; '' if n/a.</summary>
    OwnerName: string ;
    Text     : string ;
    StartLine: Integer;
    StartCol : Integer;
    EndLine  : Integer;
    EndCol   : Integer;
  end;

  /// <summary>A text-search hit returned by ISymbolStore.SearchText: a
  /// TStringLiteral enriched with the file path and enclosing qualified name.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.CLI.DoQueryText (DRagLint.CLI.pas), declaration (DRagLint.Core.Interfaces.pas), declaration (DRagLint.Storage.SQLite.pas), DRagLint.Storage.SQLite.TSQLiteSymbolStore.SearchText (DRagLint.Storage.SQLite.pas)</para>
  /// <para>Used in units: DRagLint.CLI, DRagLint.Core.Interfaces, DRagLint.Storage.SQLite</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TStringLitMatch = record
    FilePath      : string ;
    Source        : string ;
    Kind          : string ;
    OwnerName     : string ;
    Text          : string ;
    EnclosingQName: string ;
    StartLine     : Integer;
    StartCol      : Integer;
    EndLine       : Integer;
    EndCol        : Integer;
  end;

  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Core.Interfaces.pas), declaration (DRagLint.Storage.SQLite.pas), DRagLint.Storage.SQLite.TSQLiteSymbolStore.UpsertChunk (DRagLint.Storage.SQLite.pas)</para>
  /// <para>Used in units: DRagLint.Core.Interfaces, DRagLint.Storage.SQLite</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TChunk = record
    Id       : Int64  ;
    FileId   : Int64  ;
    SymbolId : Int64  ;
    Kind     : string ;
    StartLine: Integer;
    EndLine  : Integer;
    Text     : string ;
  end;

  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.CLI.ApplyLineMarkers (DRagLint.CLI.pas), DRagLint.CLI.ApplyLineMarkers.EmitHint (DRagLint.CLI.pas), DRagLint.CLI.BuildAutofixEdits (DRagLint.CLI.pas), DRagLint.CLI.FinalizeAndOutput (DRagLint.CLI.pas), DRagLint.CLI.DoLint (DRagLint.CLI.pas) (+128 more)</para>
  /// <para>Used in units: DRagLint.CLI, DRagLint.Core.Interfaces, DRagLint.Diagnostics.AstChecks, DRagLint.Diagnostics.CloneChecks, DRagLint.Diagnostics.DeadCodeChecks, DRagLint.Diagnostics.FlowChecks, DRagLint.Diagnostics.NamingChecks, DRagLint.Lint.Baseline, DRagLint.Lint.ClassMetrics, DRagLint.Lint.DocRules (+9 more)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TLintFinding = record
    Id       : Int64  ;
    RuleId   : string ;
    FileId   : Int64  ;
    FilePath : string ;
    StartLine: Integer;
    StartCol : Integer;
    EndLine  : Integer;
    EndCol   : Integer;
    Severity : string ;
    Message  : string ;
    { Short name of the declaration this finding is anchored to, when the rule
      knows it ('' otherwise -- most rules anchor to a position, not a symbol).
      Exists so a fixer can re-resolve the SAME declaration later instead of
      trusting (file, line) to identify it: a line number is not an identity, and
      a finding produced against an index that has since gone stale points at a
      line whose content has moved on. Set it in any rule whose findings feed a
      fixer. }
    SymbolName: string;
  end;

  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.Core.Indexer.FindDocRegionAbove (DRagLint.Core.Indexer.pas), DRagLint.Core.Indexer.TIndexer.IndexFile (DRagLint.Core.Indexer.pas), declaration (DRagLint.Core.Model.pas), DRagLint.Doc.Document.FindDocRegionAbove (DRagLint.Doc.Document.pas), DRagLint.Doc.Document.TDocumenter.ExistingDocFor (DRagLint.Doc.Document.pas) (+4 more)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TDocCommentKind = ( dckTripleSlash, dckDoubleSlashOne, dckTripleSlashOne, dckPasDocCurly, dckPasDocParen, dckLooseLine, dckLooseBlock );

  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Core.Model.pas)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TDocFormat = (dfXmlDoc, dfPasDoc, dfOneline, dfLoose);

  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.Core.Indexer.FindDocRegionAbove (DRagLint.Core.Indexer.pas), DRagLint.Core.Indexer.TIndexer.IndexFile (DRagLint.Core.Indexer.pas), DRagLint.Doc.Document.FindDocRegionAbove (DRagLint.Doc.Document.pas), DRagLint.Doc.Document.TDocumenter.ExistingDocFor (DRagLint.Doc.Document.pas), DRagLint.Doc.Document.TDocumenter.BuildForSymbol (DRagLint.Doc.Document.pas) (+3 more)</para>
  /// <para>Used in units: DRagLint.Core.Indexer, DRagLint.Doc.Document, DRagLint.Parser.DocComments</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TDocCommentRegion = record
    StartLine: Integer        ;
    EndLine  : Integer        ;
    StartCol : Integer        ;
    Kind     : TDocCommentKind;
    RawText  : string         ;
  end;

  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Core.Model.pas), DRagLint.Doc.Drift.TDocDrift.Analyze/4 (DRagLint.Doc.Drift.pas), DRagLint.Parser.DocComments.TDocCommentParser.ParseXmlDoc (DRagLint.Parser.DocComments.pas), DRagLint.Parser.DocComments.TDocCommentParser.ParsePasDoc (DRagLint.Parser.DocComments.pas)</para>
  /// <para>Used in units: DRagLint.Core.Model, DRagLint.Doc.Drift, DRagLint.Parser.DocComments</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TDocParam = record
    Name: string;
    Desc: string;
  end;

  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Core.Model.pas), DRagLint.Doc.Drift.TDocDrift.Analyze/4 (DRagLint.Doc.Drift.pas), DRagLint.Parser.DocComments.TDocCommentParser.ParseXmlDoc (DRagLint.Parser.DocComments.pas), DRagLint.Parser.DocComments.TDocCommentParser.ParsePasDoc (DRagLint.Parser.DocComments.pas)</para>
  /// <para>Used in units: DRagLint.Core.Model, DRagLint.Doc.Drift, DRagLint.Parser.DocComments</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TDocException = record
    TypeName: string;
    Desc    : string;
  end;

  // v0.40.4: captured from `uses` clauses to support circular-dep detection,
  // move-down (interface->implementation) suggestions, and unused-unit
  // analysis in graphing + lint utilities.
  /// <summary><!-- drag-lint:auto -->v0.40.4: captured from `uses` clauses to support
  /// circular-dep detection, move-down (interface-&gt;implementation) suggestions, and
  /// unused-unit analysis in graphing + lint utilities.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Core.Model.pas), declaration (DRagLint.Parser.Delphi13.pas), DRagLint.Parser.Delphi13.TWalkState.EmitUnitUse (DRagLint.Parser.Delphi13.pas), DRagLint.Refactor.TextEdit.TFindUnitRefactoring.Build/6 (DRagLint.Refactor.TextEdit.pas)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TUnitUseSection = (
    uusInterface, // `interface uses ...`
    uusImplementation, // `implementation uses ...`
    uusProgram, // top-level uses in a .dpr
    uusPackage // top-level uses in a .dpk
  );

  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.CLI.DoResolveUses (DRagLint.CLI.pas), DRagLint.CLI.SuggestUnitForSymbol (DRagLint.CLI.pas), DRagLint.CLI.DoCycles (DRagLint.CLI.pas), DRagLint.CLI.DoUsesAudit (DRagLint.CLI.pas), DRagLint.CLI.DoUsesFixSweep (DRagLint.CLI.pas) (+16 more)</para>
  /// <para>Used in units: DRagLint.CLI, DRagLint.Core.Interfaces, DRagLint.Lint.ProjectChecks, DRagLint.Lint.ProjectRules, DRagLint.Parser.Delphi13, DRagLint.Refactor.EnumHelper, DRagLint.Refactor.TextEdit, DRagLint.Storage.SQLite</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TUnitUse = record
    FileId   : Int64          ; // owning file (set by indexer post-parse; -1 in parser output)
    UnitName : string         ; // verbatim, with dots: 'System.SysUtils'
    Section  : TUnitUseSection;
    InPath   : string         ; // text inside `in '<path>'`; empty when absent
    StartLine: Integer        ; // 1-based
    StartCol : Integer        ;
    EndLine  : Integer        ;
    EndCol   : Integer        ;
  end;

  // One 'global-only' uses edge: ReaderFileId depends on DeclFileId for
  // NOTHING but the named interface-section global variable(s), so RELOCATING
  // them deletes the edge. Produced by
  // ISymbolStore.FindGlobalOnlyUsesEdges; consumed by global-only-uses-edge.
  // GlobalNames arrives comma-separated and in UNSPECIFIED order (SQLite's
  // GROUP_CONCAT gives no ordering guarantee) -- the rule sorts before it
  // renders, because an unstable message is an unstable diff.
  //
  // AllInterfaceTyped is TRUE only when EVERY carrying global's declared type
  // resolves, in this index, to a symbol of kind 'interface'. It is the sole
  // licence to say "inject" (owner ruling 2026-08-30): an interface can be
  // registered and resolved, a Boolean cannot. It is deliberately ALL and not
  // ANY -- injecting the interface half of a mixed edge leaves the other
  // global carrying it, so the edge survives and the advice would be false.
  // One uses edge weighed by how many of the target's globals the reader
  // actually touches -- the coupling census. Sibling of TGlobalOnlyEdge and
  // deliberately NOT the same question: that one asks whether the edge can be
  // DELETED, this one asks how heavy it is, and makes no only-link claim.
  //
  // Counts are REFERENCED names, not everything B exports. What B exports is a
  // property of B alone -- the same number on every edge into B -- so it cannot
  // rank edges or justify acknowledging one over another, which is the owner's
  // stated purpose ("must go together when separated for a test").
  //
  // Names arrive comma-separated and UNORDERED (GROUP_CONCAT gives no ordering
  // guarantee); the rule sorts before rendering, because an unstable message is
  // an unstable diff.
  TUsesCensusEdge = record
    ReaderFileId: Int64  ;
    DeclFileId  : Int64  ;
    VarCount    : Integer;
    ConstCount  : Integer;
    VarNames    : string ;
    ConstNames  : string ;
    { WHAT THE USED UNIT CONTAINS, added 2026-08-31 on the owner's request, as
      against the four fields above -- which say what the READER draws. The
      earlier note here argued a total "cannot rank edges or justify
      acknowledging one over another", and that is still true: it is the same
      number on every edge into B. But ranking was never the only question. The
      owner's is "consolidate, inject, or leave as is", and "you use 7 of
      BASICS's 143" decides that where either number alone does not.
      DeclDfmObjects is the .dfm object count -- NOT part of DeclVarTotal, since
      DFM components are published fields of the form CLASS, not unit-level
      globals. }
    DeclVarTotal  : Integer;
    DeclConstTotal: Integer;
    DeclDfmObjects: Integer;
    { The DFM root object's class, '' when the used unit has no .dfm. The rule
      skips a unit that HAS one unless this class descends from TDataModule --
      owner ruling: a form you open from a button cannot be injected without
      fighting RAD, so reporting it is noise, while a datamodule usually can be.
      Measured on ORM3 CLIENT: 61 DFM roots, exactly 2 datamodules -- and
      uStyles is one of them, so the canonical 26-finding case survives the
      exclusion while ~43 plain-form edges go quiet. }
    DeclDfmRootClass: string;
  end;

  // One DECLARING SITE of a name that is declared at interface unit level in
  // two or more indexed units. Rows arrive one per SITE, ordered by
  // (lower(name), lower(path), start_line), so the rule groups them in Delphi:
  // the whole result set is 22 rows on ORM3 and grouping in SQL would buy
  // nothing but a GROUP_CONCAT whose order is not guaranteed.
  //
  // Signature carries the DECLARATION TEXT INCLUDING THE INITIALIZER
  // ('Integer = 15', a whole TColor array), which is what makes the
  // identical-vs-differing verdict a query-time read rather than a re-parse.
  // Compare it NORMALIZED -- lowercased, whitespace runs collapsed: raw
  // comparison calls ORM3's tbltdistrcount a difference on 'integer' versus
  // 'Integer', and a case difference is not a semantic one.
  TDuplicateDeclSite = record
    Name     : string ;
    Kind     : string ; // 'const' | 'var'
    FileId   : Int64  ;
    StartLine: Integer;
    StartCol : Integer;
    Signature: string ;
  end;

  TGlobalOnlyEdge = record
    ReaderFileId    : Int64  ;
    DeclFileId      : Int64  ;
    GlobalNames     : string ;
    GlobalCount     : Integer;
    AllInterfaceTyped: Boolean;
  end;

  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.CLI.DoHover (DRagLint.CLI.pas), DRagLint.CLI.DoDocDrift (DRagLint.CLI.pas), declaration (DRagLint.Hover.Renderer.pas), DRagLint.Core.Indexer.TIndexer.IndexFile (DRagLint.Core.Indexer.pas), declaration (DRagLint.Core.Interfaces.pas) (+28 more)</para>
  /// <para>Used in units: DRagLint.CLI, DRagLint.Core.Indexer, DRagLint.Core.Interfaces, DRagLint.Core.Model, DRagLint.Doc.Document, DRagLint.Doc.Drift, DRagLint.Doc.Regions, DRagLint.Hover.Renderer, DRagLint.Lint.DocRules, DRagLint.LSP.Completion (+6 more)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TParsedDoc = record
    Format     : TDocFormat           ;
    RawBlock   : string               ;
    Summary    : string               ;
    Remarks    : string               ;
    ReturnsText: string               ;
    Params     : TArray<TDocParam>    ;
    Exceptions : TArray<TDocException>;
    ExampleText: string               ;
    SeeAlso    : TArray<string>       ;
    SinceText  : string               ;
    Deprecated : Boolean              ;
    StartLine  : Integer              ;
    EndLine    : Integer              ;
    HasContent : Boolean              ;
    // v(ADP3 T3): per-tag PRESENCE, independent of content. Summary/ReturnsText
    // parse to '' BOTH when the tag is genuinely absent AND when a human wrote
    // an explicitly empty tag (<summary></summary> / <returns></returns>) --
    // MergeComment's omit-when-empty repair logic needs to tell those two
    // apart (a human's deliberate blank slot is preserved verbatim; a truly
    // absent tag is filled from the harvest/mined facts, or left absent).
    // True whenever the parser matched the tag literally (dfXmlDoc), or found
    // any non-empty content for it (dfPasDoc/dfOneline, which have no
    // "explicitly empty tag" concept of their own). Params need no such flag:
    // a param's PRESENCE is already the fact that its TDocParam entry exists
    // in Params (by name), empty Desc or not.
    HasSummaryTag: Boolean;
    HasReturnsTag: Boolean;
    // v(ADP3 T3b review, Important/Minor 1): same PRESENCE-vs-content distinction
    // as HasSummaryTag/HasReturnsTag, for <example> -- ExampleText <> '' cannot
    // tell "no <example> tag" apart from a human's deliberate, empty
    // <example></example>, so MergeComment's omit-when-empty repair logic
    // needs this flag to preserve the latter instead of silently dropping it.
    HasExampleTag: Boolean;
    // v(ADP3 T3b review round 3, NEW IMPORTANT): same PRESENCE-vs-content
    // distinction as HasSummaryTag/HasReturnsTag/HasExampleTag, for <since>.
    // SinceText <> '' could not tell "no <since> tag" apart from a human's
    // deliberate, empty <since></since>, AND (the actual reported bug) it
    // meant MergeComment's repair path had no way to gate <since>'s PRESENCE
    // from a stripped ("is this genuinely standalone, not nested inside
    // <exception>/<example>/<deprecated>") view without ALSO reading its
    // CONTENT from that same stripped view -- which silently deleted
    // legitimately-nested content, and in one shape (<since><deprecated>...
    // </deprecated></since>) deleted the ENTIRE hand-written comment, because
    // both <since> and <deprecated> independently stripped each other out of
    // existence. See TDocRegions.MergeComment's own remarks for the fix.
    HasSinceTag: Boolean;
    // v(ADP3 T3b review round 3, STRUCTURAL 1): same PRESENCE-vs-content
    // distinction, for <remarks> -- added so MergeComment's remarks-prose
    // emission can also gate on a stripped ("genuinely standalone") view
    // instead of reading AExisting.Remarks unconditionally, which is exactly
    // what let a <remarks> nested inside <example>/<exception>/<deprecated>
    // become the engine's real remarks prose (with the facts fence wrongly
    // attaching to it) -- reported reproduction, see MergeComment's own
    // remarks. Remarks <> '' was ALREADY relied upon elsewhere (e.g.
    // HasAnyRecognizedTag in DRagLint.Parser.DocComments.pas) as a stand-in
    // for this exact flag, in the absence of one -- this field replaces that
    // stand-in with a real presence signal wherever it matters.
    HasRemarksTag: Boolean;
    // v(ADP3 T3b review, Important 2): the message text from a hand-written
    // <deprecated>message</deprecated> tag; '' for a bare <deprecated/> (or
    // <deprecated />), and '' when the tag is absent (test Deprecated itself
    // for presence, same as before -- this field only ever HOLDS a payload,
    // it does not replace the presence signal). Populated by ParseXmlDoc only
    // (dfXmlDoc); ParsePasDoc's own @deprecated has never captured a trailing
    // message either, before or after this change -- that is a separate,
    // pre-existing PasDoc gap, out of this task's scope.
    DeprecatedText: string;
    // v(ADP3 T3b review, Critical 1 fix): parallel to SeeAlso (same length,
    // same index correspondence) -- True when that entry's SOURCE tag was
    // bare '<see cref="X"/>', False when it was '<seealso cref="X"/>'. RxSee's
    // own (?:see|seealso) alternation conflates both spellings into ONE
    // SeeAlso array (correct for every OTHER consumer -- hover, the index --
    // which legitimately wants every related-symbol mention regardless of
    // which spelling the author used); MergeComment's repair path is the ONE
    // consumer that must round-trip the author's ORIGINAL tag spelling
    // verbatim (a <see> is an inline cross-reference, a <seealso> is a
    // separate top-level entry -- they render differently, so silently
    // rewriting one as the other is a fabrication as well as a destruction).
    // ParsePasDoc's own @see has no bare-<see>-vs-<seealso> distinction to
    // make (PasDoc has one @see tag, not two), so it always reports False
    // (rendered as <seealso>, matching this field's pre-existing behaviour).
    SeeAlsoIsInline: TArray<Boolean>;
    // Raw JSON strings from storage (populated by GetSymbolDoc for renderers).
    // FillChar zeroes these; empty means not stored or not retrieved.
    ParamsJsonRaw    : string;
    ExceptionsJsonRaw: string;
    SeeAlsoJsonRaw   : string;
  end; // record

  // v0.16 Task 13: .drag-lint.json "docs" section config.
  // CaptureLooseComments: when False (default), loose // and {..} regions
  //   preceding a symbol are ignored by FindDocRegionAbove.
  // ImplPrecedence: reserved for future use; 'interface' is the only
  //   behavior in v0.16.
  // AllowBlankLineGap: number of blank lines permitted between a doc region
  //   and the following symbol declaration. Default 1.
  /// <summary><!-- drag-lint:auto -->v0.16 Task 13: .drag-lint.json "docs" section
  /// config. CaptureLooseComments: when False (default), loose // and {..} regions
  /// preceding a symbol are ignored by FindDocRegionAbove. ImplPrecedence: reserved for
  /// future use; 'interface' is the only behavior in v0.16. AllowBlankLineGap: number of
  /// blank lines permitted between a doc region and the following symbol declaration.
  /// Default 1.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.CLI.pas), DRagLint.CLI.DoSelfTestRecreate (DRagLint.CLI.pas), declaration (DRagLint.Core.Indexer.pas), DRagLint.Core.Indexer.TIndexer.Create/3 (DRagLint.Core.Indexer.pas), declaration (DRagLint.Core.Model.pas)</para>
  /// <para>Used in units: DRagLint.CLI, DRagLint.Core.Indexer, DRagLint.Core.Model</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TDocConfig = record
    CaptureLooseComments: Boolean;
    ImplPrecedence      : string ;
    AllowBlankLineGap   : Integer;
  end;

  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.CLI.DoImpact (DRagLint.CLI.pas), DRagLint.CLI.DoUsages (DRagLint.CLI.pas), DRagLint.Context.Bundler.TContextBundler.RenderMarkdown (DRagLint.Context.Bundler.pas), declaration (DRagLint.Core.Interfaces.pas), declaration (DRagLint.Core.Model.pas) (+5 more)</para>
  /// <para>Used in units: DRagLint.CLI, DRagLint.Context.Bundler, DRagLint.Core.Interfaces, DRagLint.Core.Model, DRagLint.LSP.Server, DRagLint.MCP.Server, DRagLint.Storage.SQLite</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TImpactLevel = record
    Depth      : Integer       ;
    CallerCount: Integer       ;
    UnitCount  : Integer       ;
    Categories : TArray<string>;
  end;

  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.CLI.DoSurface (DRagLint.CLI.pas), DRagLint.Context.Bundler.StripDfmFields (DRagLint.Context.Bundler.pas), DRagLint.Context.Bundler.TContextBundler.Build (DRagLint.Context.Bundler.pas), DRagLint.Context.Bundler.TContextBundler.RenderMarkdown (DRagLint.Context.Bundler.pas), DRagLint.Context.Bundler.TContextBundler.RenderRaw (DRagLint.Context.Bundler.pas) (+6 more)</para>
  /// <para>Used in units: DRagLint.CLI, DRagLint.Context.Bundler, DRagLint.Core.Interfaces, DRagLint.Core.Model, DRagLint.MCP.Server, DRagLint.Storage.SQLite</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TSurfaceLine = record
    Kind     : string ;
    Text     : string ;
    StartLine: Integer;
    EndLine  : Integer;
  end;

  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.CLI.DoSlice (DRagLint.CLI.pas), DRagLint.Context.Bundler.TContextBundler.Build (DRagLint.Context.Bundler.pas), DRagLint.Context.Bundler.TContextBundler.RenderMarkdown (DRagLint.Context.Bundler.pas), DRagLint.Context.Bundler.TContextBundler.RenderRaw (DRagLint.Context.Bundler.pas), declaration (DRagLint.Core.Interfaces.pas) (+5 more)</para>
  /// <para>Used in units: DRagLint.CLI, DRagLint.Context.Bundler, DRagLint.Core.Interfaces, DRagLint.Core.Model, DRagLint.MCP.Server, DRagLint.Storage.SQLite</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TSliceChunk = record
    Kind     : string ;
    Text     : string ;
    StartLine: Integer;
    EndLine  : Integer;
  end;

  /// <summary>One concept topic parsed out of one symbol's doc comment.</summary>
  /// <remarks>A record, not a class: topics are produced in small arrays, read
  /// once and discarded, and every consumer so far wants value semantics.</remarks>
  TWikiTopic = record
    /// <summary>The human name from the header line, verbatim after trimming.
    /// Empty means a malformed `dl:wiki` line with no name -- kept rather than
    /// dropped so `wiki --check` can REPORT it. A silently ignored header is
    /// indistinguishable from a topic nobody wrote.</summary>
    Name      : string        ;
    Aliases   : TArray<string>;
    /// <summary>Bare or qualified identifiers naming the other participants of
    /// a multi-symbol concept. Unresolved here; `wiki --check` resolves them.</summary>
    SeeCode   : TArray<string>;
    /// <summary>The prose, lines joined with the platform line break. XML-only
    /// lines and anything between the engine's AUTO_BEGIN/AUTO_END fences are
    /// excluded.</summary>
    Body      : string        ;
    /// <summary>The symbol whose doc comment carried the topic. This is the
    /// IMPLICIT SeeCode entry -- the block's own location is a code location,
    /// so a single-owner topic needs no SeeCode line at all.</summary>
    OwnerQName: string        ;
    OwnerKind : string        ;
    FilePath  : string        ;
    /// <summary>1-based file line of the `dl:wiki` header itself, not of the
    /// comment. This is what the hover indicator navigates to (ruling R3).</summary>
    HeaderLine: Integer       ;
    /// <summary>Which index answered. Printed when the same alias resolves in
    /// more than one database, so the reader can tell them apart.</summary>
    DbPath    : string        ;
  end;

  /// <summary>One symbol_docs row whose raw_block carries a `dl:wiki` marker,
  /// joined to everything the wiki parser needs to place it.</summary>
  /// <remarks>Declared HERE rather than in DRagLint.Doc.Wiki so that
  /// DRagLint.Storage.SQLite can return it without src\storage acquiring a
  /// dependency on src\doc. This record adds no table and no column -- it is a
  /// projection of columns that already exist -- so neither
  /// DRAGLINT_EXTRACTOR_VERSION nor SCHEMA_VERSION moves for it.</remarks>
  TWikiDocRow = record
    SymbolId : Int64  ;
    QName    : string ;
    Kind     : string ;
    FilePath : string ;
    /// <summary>symbol_docs.start_line: the 1-based file line of the comment's
    /// FIRST line, which is the base the wiki header's own line is offset
    /// from.</summary>
    StartLine: Integer;
    RawBlock : string ;
  end;

  /// <summary>One indexed file's identity for a FRESHNESS comparison: the path
  /// exactly as stored, and the mtime recorded when that file was parsed.</summary>
  /// <remarks>
  /// Exists so a freshness sweep costs ONE query instead of two per file.
  /// GetAllFileIds + GetFilePath + GetFileMTime is the same information at
  /// 2N round trips, which is fine for a hundred-file project index and not
  /// fine for a library index of several thousand -- and a check that gets
  /// skipped because it is slow protects nothing.
  ///
  /// A projection of columns that already exist: no table, no column, so
  /// neither DRAGLINT_EXTRACTOR_VERSION nor SCHEMA_VERSION moves for it.
  /// </remarks>
  TFileStamp = record
    /// <summary>Path in the canonical stored form (see NormalizeStoredPath).</summary>
    Path     : string;
    /// <summary>files.mtime_unix as recorded at parse time.</summary>
    MTimeUnix: Int64 ;
  end;

  // v0.18: resolved caller entry for a context bundle (FilePath pre-resolved
  // from FileId so renderers don't need a store callback).
  /// <summary><!-- drag-lint:auto -->v0.18: resolved caller entry for a context bundle
  /// (FilePath pre-resolved from FileId so renderers don't need a store callback).</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.Context.Bundler.TContextBundler.Build (DRagLint.Context.Bundler.pas), DRagLint.Context.Bundler.TContextBundler.RenderMarkdown (DRagLint.Context.Bundler.pas), declaration (DRagLint.Core.Model.pas)</para>
  /// <para>Used in units: DRagLint.Context.Bundler, DRagLint.Core.Model</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TBundleCaller = record
    FilePath   : string ;
    Line       : Integer;
    Col        : Integer;
    ContextText: string ;
  end;

  // v0.26: compiler diagnostic finding (from dcc64 or msbuild output).
  /// <summary><!-- drag-lint:auto -->v0.26: compiler diagnostic finding (from dcc64 or
  /// msbuild output).</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.CLI.NormalizeFindings (DRagLint.CLI.pas), DRagLint.CLI.DoCompileCheck (DRagLint.CLI.pas), DRagLint.CLI.RefreshProjectFindingsCore (DRagLint.CLI.pas), DRagLint.CLI.DoGhostCheck (DRagLint.CLI.pas), DRagLint.CLI.DoCheckUnit (DRagLint.CLI.pas) (+13 more)</para>
  /// <para>Used in units: DRagLint.CLI, DRagLint.Core.Interfaces, DRagLint.Diagnostics.CompileCheck, DRagLint.LSP.Completion, DRagLint.MCP.Server, DRagLint.Storage.SQLite</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TCompilerFinding = record
    FileId  : Int64  ;
    RawPath : string ;
    Code    : string ; // e.g. 'W1002'
    Severity: string ; // 'Error' | 'Warning' | 'Hint' | 'Information'
    LineNo  : Integer;
    ColNo   : Integer;
    Message : string ;
  end;

  // v0.18: context bundle -- minimum AI-ready slice for a symbol.
  /// <summary><!-- drag-lint:auto -->v0.18: context bundle -- minimum AI-ready slice for
  /// a symbol.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.CLI.DoContext (DRagLint.CLI.pas), DRagLint.CLI.DoBenchContext (DRagLint.CLI.pas), declaration (DRagLint.Context.Bundler.pas), DRagLint.Context.Bundler.TContextBundler.Build (DRagLint.Context.Bundler.pas), DRagLint.Context.Bundler.TContextBundler.RenderMarkdown (DRagLint.Context.Bundler.pas) (+2 more)</para>
  /// <para>Used in units: DRagLint.CLI, DRagLint.Context.Bundler</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TContextBundle = record
    Task         : string               ;
    Verb         : string               ;
    QName        : string               ;
    GeneratedAt  : TDateTime            ;
    TokenEstimate: Integer              ;
    Doc          : TParsedDoc           ;
    HasDoc       : Boolean              ;
    ClassSurface : TArray<TSurfaceLine> ;
    ImplSlice    : TArray<TSliceChunk>  ;
    Callers      : TArray<TBundleCaller>;
    ImpactSummary: TArray<TImpactLevel> ;
    { dl:wiki concept topics whose NAME OR ALIAS the task phrase matched.
      Capped at two on purpose: a bundle exists to be small, and a third
      loosely-matching concept note costs more tokens than it repays. }
    WikiTopics   : TArray<TWikiTopic>   ;
    { True only when the qualified name actually resolved to a symbol.
      A caller CANNOT infer this from QName: Build stamps QName with what
      was asked for before it looks anything up, so the pre-existing
      `Bundle.QName = ''` not-found test was DEAD -- a nonexistent symbol
      rendered an empty bundle and exited 0, which is precisely the silent
      empty answer the bare-name fallback was added to stop. }
    Resolved     : Boolean              ;
  end;

/// <param name="AFormat"><!-- drag-lint:auto type -->TDocFormat</param>
/// <returns><!-- drag-lint:auto -->string -- Observed: 'xmldoc'; 'pasdoc'; 'oneline';
/// 'loose'; 'unknown'.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Hover.Renderer.RenderHoverJson/2 (DRagLint.Hover.Renderer.pas), DRagLint.MCP.Server.TMCPServer.FormatDocAsJson (DRagLint.MCP.Server.pas), DRagLint.Storage.SQLite.TSQLiteSymbolStore.UpsertSymbolDoc (DRagLint.Storage.SQLite.pas)</para>
/// <para>Pure</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function DocFormatToStr     (AFormat : TDocFormat     ): string;
/// <param name="ASection"><!-- drag-lint:auto type -->TUnitUseSection</param>
/// <returns><!-- drag-lint:auto -->string -- Observed: 'interface'; 'implementation';
/// 'program'; 'package'; 'unknown'.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Storage.SQLite.TSQLiteSymbolStore.UpsertUnitUse (DRagLint.Storage.SQLite.pas)</para>
/// <para>Pure</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function UnitUseSectionToStr(ASection: TUnitUseSection): string;
/// <param name="AStr"><!-- drag-lint:auto type -->const string</param>
/// <returns><!-- drag-lint:auto -->TUnitUseSection -- Observed: uusInterface;
/// uusImplementation; uusProgram; uusPackage.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Storage.SQLite.TSQLiteSymbolStore.FindUsersOfUnit (DRagLint.Storage.SQLite.pas), DRagLint.Storage.SQLite.TSQLiteSymbolStore.GetUnitUsesForFile (DRagLint.Storage.SQLite.pas)</para>
/// <para>Calls: SameText</para>
/// <para>Pure</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function StrToUnitUseSection(const AStr: string): TUnitUseSection          ;
/// <param name="S"><!-- drag-lint:auto type -->const string</param>
/// <returns><!-- drag-lint:auto type -->string</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.DoCheckUnit (DRagLint.CLI.pas), DRagLint.CLI.DoCompileCheck (DRagLint.CLI.pas), DRagLint.CLI.DoGhostCheck (DRagLint.CLI.pas), DRagLint.Core.Model.ExceptionsToJson (DRagLint.Core.Model.pas), DRagLint.Core.Model.ParamsToJson (DRagLint.Core.Model.pas) (+10 more)</para>
/// <para>Calls: Format</para>
/// <para>Pure</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function JsonEscape(const S: string): string                               ;
/// <param name="AParams"><!-- drag-lint:auto type -->const TArray&lt;TDocParam &gt;</param>
/// <returns><!-- drag-lint:auto -->string -- Observed: '[' + string.Join(',', Parts) +
/// ']'.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Storage.SQLite.TSQLiteSymbolStore.UpsertSymbolDoc (DRagLint.Storage.SQLite.pas)</para>
/// <para>Calls: DRagLint.Core.Model.JsonEscape, Format</para>
/// <para>Pure</para>
/// <seealso cref="DRagLint.Core.Model.JsonEscape"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ParamsToJson    (const AParams    : TArray<TDocParam    >): string;
/// <param name="AExceptions"><!-- drag-lint:auto type -->const TArray&lt;TDocException&gt;</param>
/// <returns><!-- drag-lint:auto -->string -- Observed: '[' + string.Join(',', Parts) +
/// ']'.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Storage.SQLite.TSQLiteSymbolStore.UpsertSymbolDoc (DRagLint.Storage.SQLite.pas)</para>
/// <para>Calls: DRagLint.Core.Model.JsonEscape, Format</para>
/// <para>Pure</para>
/// <seealso cref="DRagLint.Core.Model.JsonEscape"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ExceptionsToJson(const AExceptions: TArray<TDocException>): string;
/// <param name="ASeeAlso"><!-- drag-lint:auto type -->const TArray&lt;string&gt;</param>
/// <returns><!-- drag-lint:auto -->string -- Observed: '[' + string.Join(',', Parts) +
/// ']'.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Storage.SQLite.TSQLiteSymbolStore.UpsertSymbolDoc (DRagLint.Storage.SQLite.pas)</para>
/// <para>Calls: DRagLint.Core.Model.JsonEscape, Format</para>
/// <para>Pure</para>
/// <seealso cref="DRagLint.Core.Model.JsonEscape"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function SeeAlsoToJson(const ASeeAlso: TArray<string>): string             ;

function DefaultDocConfig: TDocConfig;

{ v(ADP3 T3j review round 1): THE doc-region/declaration attribution predicate.
  ONE declaration, read by all THREE places that decide whether a doc comment
  belongs to a given declaration:

    * DRagLint.Core.Indexer.FindDocRegionAbove   (index-time capture)
    * DRagLint.Doc.Document.FindDocRegionAbove   (the `document --apply` write path)
    * DRagLint.Doc.Strip.StripSymbolRegion       (the `document --strip` remove path)

  It lives HERE, in the lowest layer (this unit's own uses clause is
  System.SysUtils alone), because all three already depend on Core.Model and
  none of them can depend on each other -- Doc.Strip is deliberately
  index-free, and Doc.Document keeps its own copy of the region scan
  specifically so it does not pull in Indexer.

  WHY A SHARED PREDICATE AND NOT THREE CAREFUL COPIES. The Phase 3 T3j defect
  (register S1) was exactly this drift: Doc.Strip copied FindDocRegionAbove's
  WINDOW, claimed in a comment to tolerate "the same gap", and silently omitted
  its GUARD -- so `--strip` deleted a doc block belonging to a different
  symbol. Three copies with a comment asserting they agree is what failed; a
  single declaration both sides read makes that drift structurally impossible. }

const
  /// <summary>Intervening lines tolerated between a doc region's end and its
  /// declaration. Read by TDocumenter's two FindDocRegionAbove call sites and by
  /// TDocStripper.StripSymbolRegion (both branches), and DefaultDocConfig.
  /// AllowBlankLineGap defaults to it -- so the APPLY and STRIP paths cannot
  /// drift apart by way of a stray literal. Changing it moves both together.
  /// <para>ONE DELIBERATE EXCEPTION: index-time capture
  /// (DRagLint.Core.Indexer) passes FDocConfig.AllowBlankLineGap instead, which
  /// is user-settable from JSON, so that path honours the user's configured
  /// value rather than this constant. It merely DEFAULTS to it, via
  /// DefaultDocConfig.</para></summary>
  /// <remarks>v(ADP3 T3j review round 2, Important 2): this DocInsight
  /// previously asserted the no-drift invariant while three of the four sites
  /// still passed a literal 1 -- only StripSymbolRegion actually read the
  /// constant, so raising it to 2 would have widened `--strip` alone and
  /// silently reintroduced the apply/strip asymmetry the comment claimed to
  /// prevent. Fixed by changing the CODE to match the claim, not the claim to
  /// match the code: a comment describing a guard the code does not perform is
  /// the documented root cause of register S1 (see the block comment on
  /// DocRegionFitsDecl below).</remarks>
  DOC_ALLOW_GAP = 1;

/// <summary>True when a doc-comment region ending at 1-based line AEndLine is
/// close enough to a declaration at 1-based ADeclLine to be attributed to it:
/// the region must end within AAllowGap lines above the declaration.</summary>
/// <param name="AEndLine">1-based last line of the candidate doc region.</param>
/// <param name="ADeclLine">1-based declaration line the region might belong to.</param>
/// <param name="AAllowGap">Tolerated intervening lines; 1 everywhere today.</param>
/// <returns>True when AEndLine is in [ADeclLine - 1 - AAllowGap, ADeclLine - 1].</returns>
/// <remarks>
/// Proximity only. It says nothing about WHAT occupies the gap -- pair
/// it with NoDeclarationInGap (or use DocRegionFitsDecl, which is both).
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Core.Indexer.FindDocRegionAbove (DRagLint.Core.Indexer.pas), DRagLint.Core.Model.DocRegionFitsDecl (DRagLint.Core.Model.pas), DRagLint.Doc.Document.FindDocRegionAbove (DRagLint.Doc.Document.pas), DRagLint.Doc.Strip.TDocStripper.StripSymbolRegion (DRagLint.Doc.Strip.pas)</para>
/// <para>Returns: (AEndLine &gt;= ADeclLine - 1 - AAllowGap) and (AEndLine &lt;= ADeclLine - 1)</para>
/// <para>Pure</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function DocRegionInGapWindow(AEndLine, ADeclLine, AAllowGap: Integer): Boolean;

/// <summary>True when NO other declaration starts strictly between a doc
/// region's end line and ADeclLine -- i.e. the region is not separated from
/// ADeclLine by some other declaration that owns it instead.</summary>
/// <param name="AEndLine">1-based last line of the candidate doc region.</param>
/// <param name="ADeclLine">1-based declaration line the region might belong to.</param>
/// <param name="ASymStartLines">Every symbol's 1-based StartLine in the same
/// file, INCLUDING ADeclLine's own, sorted ASCENDING. The ascending order is
/// load-bearing: the scan stops at the first entry >= ADeclLine, which both
/// bounds the cost on symbol-heavy files and is what excludes ADeclLine's own
/// entry from consideration. An EMPTY array means "no symbol table available"
/// and the check is vacuously True -- a caller without one must add its own
/// safeguard (see DRagLint.Doc.Strip.StripSymbolRegion's blank-line fallback).</param>
/// <returns>True when the gap contains no other declaration.</returns>
/// <remarks>
/// Blank lines are never symbol start lines, so a region separated
/// from its declaration by blank lines alone always passes. This is the guard
/// added by adp2-docregion-fix, and it is deliberately about DECLARATIONS
/// rather than blankness: an ordinary comment in the gap is tolerated on
/// purpose, because the doc comment above it still belongs to ADeclLine.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Core.Indexer.FindDocRegionAbove (DRagLint.Core.Indexer.pas), DRagLint.Core.Model.DocRegionFitsDecl (DRagLint.Core.Model.pas), DRagLint.Doc.Document.FindDocRegionAbove (DRagLint.Doc.Document.pas)</para>
/// <para>Returns: True</para>
/// <para>Pure</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function NoDeclarationInGap(AEndLine, ADeclLine: Integer;
  const ASymStartLines: TArray<Integer>): Boolean;

/// <summary>The full attribution test: DocRegionInGapWindow AND
/// NoDeclarationInGap. Use this unless you need the two halves apart.</summary>
/// <param name="AEndLine">1-based last line of the candidate doc region.</param>
/// <param name="ADeclLine">1-based declaration line the region might belong to.</param>
/// <param name="AAllowGap">Tolerated intervening lines; 1 everywhere today.</param>
/// <param name="ASymStartLines">See NoDeclarationInGap -- sorted ascending, and
/// an empty array makes the declaration half vacuous.</param>
/// <returns>True when the region should be attributed to ADeclLine.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Doc.Strip.TDocStripper.StripSymbolRegion (DRagLint.Doc.Strip.pas)</para>
/// <para>Calls: DRagLint.Core.Model.DocRegionInGapWindow, DRagLint.Core.Model.NoDeclarationInGap</para>
/// <para>Returns: DocRegionInGapWindow(AEndLine, ADeclLine, AAllowGap)</para>
/// <para>Pure</para>
/// <seealso cref="DRagLint.Core.Model.DocRegionInGapWindow"/>
/// <seealso cref="DRagLint.Core.Model.NoDeclarationInGap"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function DocRegionFitsDecl(AEndLine, ADeclLine, AAllowGap: Integer;
  const ASymStartLines: TArray<Integer>): Boolean;

{ v(ADP3 T3i): THE CALL-SITE REF-KIND UNIVERSE. ONE declaration, read by the
  pass that WRITES resolved call edges and by both queries that read the
  UNRESOLVED complement of those edges.

  THIS LIST IS THE SINGLE SOURCE FOR WHO READS THE DECLARATION (round 4). Any
  other comment or test header that needs the readership points HERE and states
  no count of its own -- the count grew from three sites to six during review
  round 2, and a copy elsewhere would have been left asserting three.
  SIX SITES, NINE READ POINTS:

    * DRagLint.Parser.Delphi13                        (emits the kind; x3)
    * TSQLiteSymbolStore.ResolveCallTargets           (writes call_edges)
    * TSQLiteSymbolStore.FindUnresolvedNameCallers    (reads the complement)
    * TSQLiteSymbolStore.GetAmbiguousCalls            (reads the complement)
    * DRagLint.Lint.ClassMetrics (x2)                 (RFC / feature-envy)
    * DRagLint.FormsMap.FindFormViaHook               (proc-var hook call sites)

  WHY IT HAS TO BE ONE DECLARATION -- register item E1, the defect this fixes.
  ResolveCallTargets resolves ONLY kind='call' refs, so a ref of any other kind
  can never own a call_edges row. Both readers defined "unresolved" as "names a
  known routine AND has no certain call_edges row" WITHOUT restating the kind
  restriction, so their complement was taken against a WIDER universe than the
  writer's: every non-call ref that happens to carry a routine's name fell into
  the unresolved bucket. After 9d7e641 (member-access on typed receivers) that
  became systematic -- a dotted call emits BOTH a 'call' ref and a co-located
  'member-access' ref at the identical span, so EVERY resolved call was also
  reported as unverified. Symptoms: `ambiguous-calls` listed resolved sites and
  returned 4 rows for 3 sites; `document`'s Called-from listed a caller that
  provably calls a DIFFERENT same-named method. type_use refs leaked the same
  way, which is why a CLASS acquired a "Called from:" line built from mere type
  mentions -- a fact "Used in units:" already carries properly.

  The complement is only meaningful against the writer's own universe, so the
  universe is declared once here and every side reads it. This is the T3j/S1
  lesson applied: a single declaration both sides read removes the drift channel.

  EXACTLY WHAT IS PROVEN, and it is deliberately not phrased as "impossible"
  (T3i review round 2). Renaming REF_KIND_CALL and rebuilding leaves GREEN:
  run_ambiguous_calls, run_calledfrom_resolved, run_callsite_kind_universe,
  run_resolve_targets, run_doc_no_self_caller and run_store_tests -- i.e. the
  parser, the writer, both complement readers and BOTH ClassMetrics filters are
  demonstrated to move in lockstep (run_store_tests was independently shown to
  cover those filters: pointing them at a different literal reddens feature-envy
  and high-response).

  FormsMap.FindFormViaHook is covered too (T3i review round 3 -- an earlier
  revision of this comment claimed the opposite and was WRONG). Killing the hook
  route at the DATA level -- re-kinding the single 'call' ref to ThingHook that
  the query depends on -- turns run_formsmap's v4 navigation cell from
  "frmRoot4 -> 'Plan' -> frmHooked4" into "(no path from MAIN)", which its
  regex at :88 does not match, so the runner goes RED. The query is that route's
  only data source and the direct fan-in is designed to dead-end, so the check
  discriminates exactly as its name says.

  Why the earlier claim was wrong is worth keeping: the mutation that "proved"
  it was applied to a Win64 build, while run_formsmap.ps1 (and run_wiring.ps1)
  default to src\cli\Win32\Debug\drag-lint.exe, which no Win64 build refreshes.
  The mutated code was never executed. An under-claim is safer than an
  over-claim but it is not free -- as written it would have sent a later
  implementer to build a fixture for a non-problem. Verify a negative result
  reached the binary under test before recording it.

  DISCLOSED CONSEQUENCE -- CLOSED 2026-08-10 (v20b), but kept in full because the
  SHAPE of the fix is the point; see the closing note at the end of this block. A
  paren-less dotted invocation in EXPRESSION position -- `N:= Obj.Func;`,
  `T:= TThing.Create;` -- emits no 'call' ref at all, only 'member-access'.
  Such a site is therefore outside this universe, and it was already invisible
  to every other call-graph surface (Calls:, find-callers --resolved,
  call-path, call-tree) because ResolveCallTargets never walked it either. It
  leaked into exactly one bucket by accident, and unreliably: the same kind
  covers ordinary property and event access, so the leak carried far more
  noise than signal. Making those sites first-class means EMITTING a call ref
  for them, which changes what is INDEXED and fixes every surface at once.
  Name-based discovery (`query find-callers`, FindCallersByName) is kind-blind
  and still finds them. Pinned by tests/callresolve/run_callsite_kind_universe.ps1.

  HOW IT WAS CLOSED (v20b), and why NOT by the route named just above. Emitting a
  second 'call' ref for those sites would place a co-located TWIN beside the one a
  PARENTHESISED dotted call already emits, double-counting every such caller.
  Instead ResolveCallTargets widens only ITS OWN query to
  `kind = 'call' OR kind = 'member-access'`, while CallSiteRefKindSql -- the
  COMPLEMENT universe the unresolved-site queries read -- is left exactly as it
  was. Widening BOTH is precisely register item E1 above: every resolved call
  would be reported as unverified again.

  Two guards keep the widening honest, both in ResolveCallTargets:
    * a member-access ref earns an edge only when its target is a ROUTINE kind --
      ordinary property/field/event access shares this kind and must not become a
      fake call site; and
    * a member-access ref co-located with a real 'call' ref is skipped, so a
      parenthesised call still yields exactly one edge.

  run_callsite_kind_universe.ps1's ParenlessExpr assertion FLIPPED from EXCLUDES
  to INCLUDES, and its ambiguous-calls and ReadsProperty/CallsFire checks are the
  regression fence for the two guards. }

const
  /// <summary>The refs.kind value that denotes a CALL SITE, and thereby the
  /// universe ResolveCallTargets resolves and both unresolved-call queries take
  /// their complement against. Read it instead of writing the literal, so the
  /// writer and the readers can never disagree about what a call site is.
  /// <para>Other kinds ('read', 'write', 'type_use', 'member-access',
  /// 'event-binding', ...) are usage references. They are never resolved to a
  /// call target, so they must never be counted as unresolved calls either --
  /// see the block comment above.</para></summary>
  REF_KIND_CALL = 'call';

/// <summary>The SQL predicate selecting call-site refs, for the queries that
/// build their WHERE clause as text.</summary>
/// <param name="ARefAlias">Table alias (or table name) the predicate should
/// qualify, e.g. 'r' for 'FROM refs r'.</param>
/// <returns>A fragment of the form '&lt;alias&gt;.kind = ''call'''.</returns>
/// <exception cref="EArgumentException">Raised when ARefAlias is blank. An
/// empty alias would silently yield '.kind = ''call''', which is not valid SQL
/// and would surface as an opaque prepare failure far from the mistake.</exception>
/// <remarks>
/// Emits the value of REF_KIND_CALL, so the SQL sites and the Pascal
/// sites share one declaration. Returns a bare predicate with no AND/WHERE, so
/// the caller controls where it is spliced.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.FormsMap.FindFormViaHook (DRagLint.FormsMap.pas), DRagLint.Storage.SQLite.TSQLiteSymbolStore.CallEdgesNeedRebuild (DRagLint.Storage.SQLite.pas), DRagLint.Storage.SQLite.TSQLiteSymbolStore.FindUnresolvedNameCallers (DRagLint.Storage.SQLite.pas), DRagLint.Storage.SQLite.TSQLiteSymbolStore.GetAmbiguousCalls (DRagLint.Storage.SQLite.pas), DRagLint.Storage.SQLite.TSQLiteSymbolStore.ResolveCallTargets (DRagLint.Storage.SQLite.pas)</para>
/// <para>Calls: QuotedStr, Trim</para>
/// <para>Returns: ARefAlias + '.kind = ' + QuotedStr(REF_KIND_CALL)</para>
/// <para>Pure</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function CallSiteRefKindSql(const ARefAlias: string): string;

/// <summary>Can a symbol of this kind ever be the TARGET of a call? True for
/// exactly the five ROUTINE kinds.</summary>
/// <param name="AKind">The symbol's kind.</param>
/// <returns>True for skProcedure/skFunction/skMethod/skConstructor/skDestructor.</returns>
/// <remarks>
/// THE SINGLE SOURCE for this question. Do not write the five kinds out
/// again anywhere, and do not describe the complement by listing kinds -- the
/// exempt set is the WHOLE complement, and a comment that enumerates it is
/// wrong the moment a kind is added. That is not hypothetical: T3i's review
/// found two comments describing the complement as "class, interface, record,
/// enum or type alias", a boundary drawn from one caller's coverage rather than
/// from the semantics, which is the same mistake that had already silently
/// deleted the Called-from fact for skEnum and skTypeAlias.
/// It holds because TCallResolver only ever writes a routine into
/// call_edges.target_symbol_id, so for any other kind "names a known routine but
/// has no certain call edge" is not evidence of an unresolved call -- it is
/// evidence the question does not apply.
/// v(ADP3 T3k, Group 2c item 1): MOVED HERE from DRagLint.Doc.Facts'
/// implementation section, where it could not be shared. T3i left this open
/// deliberately -- collapsing the duplicate needed a code change and that round
/// was comments-only -- and named DRagLint.Doc.SymbolFacts' ComputeCoveredBy as
/// the one remaining literal copy of the same five kinds asking the same
/// question. Core.Model rather than Doc.Facts because Doc.Facts already uses
/// Doc.SymbolFacts (in its implementation section), so exporting from there
/// would have made the dependency mutual and pointed the lower-level unit at
/// the higher one. Core.Model owns TSymbolKind, has no uses clause of its own,
/// and is already where this phase put its other shared declarations
/// (REF_KIND_CALL, DocRegionFitsDecl, DOC_ALLOW_GAP) for the same reason: a
/// single declaration read by both sides makes the drift structurally
/// impossible.
/// NOT to be confused with the type-like gate that gives a class/interface/
/// record its "Used in units:" line. Those are two questions and two
/// declarations on purpose -- sharing one set would ADD a brand-new
/// "Used in units:" line to every enum and alias. See Doc.Facts' own comment at
/// that gate.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Diagnostics.FlowChecks.TFlowChecker.Check (DRagLint.Diagnostics.FlowChecks.pas), DRagLint.Doc.Facts.LeafNameIsUnambiguous (DRagLint.Doc.Facts.pas), DRagLint.Doc.Facts.LeafNameNotAmbiguous (DRagLint.Doc.Facts.pas), DRagLint.Doc.Facts.TDocFactsBuilder.Build (DRagLint.Doc.Facts.pas), DRagLint.Doc.Regions.TDocRegions.RenderFactsBlock (DRagLint.Doc.Regions.pas) (+2 more)</para>
/// <para>Returns: AKind in [skProcedure, skFunction, skMethod, skConstructor, skDestructor]</para>
/// <para>Pure</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function CanBeCallTarget(AKind: TSymbolKind): Boolean;

/// <summary>The System-unit declaration of a Delphi COMPILER INTRINSIC, for
/// display; '' when AName is not a recognized intrinsic.</summary>
/// <param name="AName">A called identifier as written at the call site.
/// Matched case-insensitively.</param>
/// <returns><!-- drag-lint:auto -->string -- Observed: 'function System.Assigned(var P):
/// Boolean'; 'function System.Length(const S): Integer'; 'procedure System.SetLength(var
/// S; NewLength: Integer)'; 'procedure System.Inc(var X [; N: Integer])'; 'procedure
/// System.Dec(var X [; N: Integer])'; 'function System.Ord(X): Integer'.</returns>
/// <remarks>
/// The set is deliberately RESTRICTED to names virtually never chosen
/// for a user-defined routine, which is why Copy / Insert / Delete / Pos are
/// absent despite being intrinsics: a real method of that name must not be
/// mislabeled. Widening this list is not a free improvement -- every added name
/// is a name some project may legitimately declare.
/// Lives HERE, in the shared base unit, so the hover renderer and the
/// documentation facts builder share ONE list. It was previously private to
/// DRagLint.LSP.Server, and a second copy in the doc layer would have been a
/// second answer to one question -- exactly the drift channel this repo keeps
/// closing.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Core.Model.IsCompilerIntrinsic (DRagLint.Core.Model.pas), DRagLint.LSP.Server.TLSPServer.ComputeHover (DRagLint.LSP.Server.pas)</para>
/// <para>Calls: SameText</para>
/// <para>Complexity: 25 (cyclomatic, outer body), 27 lines (full implementation)</para>
/// <para>Pure</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function IntrinsicSignature(const AName: string): string;

/// <summary>True when AName is a Delphi compiler intrinsic -- a built-in the
/// compiler recognizes by name and compiles inline, which is therefore never a
/// symbol in any index.</summary>
/// <param name="AName"><!-- drag-lint:auto type -->const string</param>
/// <returns><!-- drag-lint:auto -->Boolean -- Observed: IntrinsicSignature(AName)
/// &lt;&gt; ''.</returns>
/// <remarks>
/// Callers use this to keep intrinsics out of derived facts. It is
/// SAFE to drop a bare call to one of these from a "Calls:" list even though a
/// project could declare a routine of the same name: a real project routine
/// resolves through call_edges and is rendered QUALIFIED from the resolved
/// set, so only the unresolved bare-name fallback is filtered here. Since the
/// unit-level rung landed, a bare call to a project routine resolves across a
/// uses edge as well, which narrows that gap further.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Doc.Facts.TDocFactsBuilder.Build (DRagLint.Doc.Facts.pas), DRagLint.LSP.Server.TLSPServer.ComputeHover (DRagLint.LSP.Server.pas)</para>
/// <para>Calls: DRagLint.Core.Model.IntrinsicSignature</para>
/// <para>Pure</para>
/// <seealso cref="DRagLint.Core.Model.IntrinsicSignature"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function IsCompilerIntrinsic(const AName: string): Boolean;

/// <summary>Unit-qualified prefix of a qualified symbol name
/// ('Vcl.Controls.TWinControl' -&gt; 'Vcl.Controls'); '' when the name carries no
/// dotted prefix at all.</summary>
/// <param name="AQName"><!-- drag-lint:auto type -->const string</param>
/// <returns><!-- drag-lint:auto -->string -- Observed: ''; Copy(AQName, 1, P - 1).</returns>
/// <remarks>
/// Known limitation: splits on the LAST dot, so a NESTED type
/// ('Vcl.Controls.TOuter.TInner') yields 'Vcl.Controls.TOuter' rather than the
/// declaring unit. Harmless for the leading-namespace question
/// (UnitFrameworkPrefix still returns 'Vcl'); it does mean a nested type's
/// declaring "unit" never matches a plain unit name in a uses set.
/// Lives HERE, in the shared base unit, so the query-time resolver
/// (DRagLint.Storage.SQLite) and the proptree ancestor climb
/// (DRagLint.Convert.PropTree) share ONE definition of "which unit declares
/// this" instead of each hand-rolling its own.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.PreferFrameworkFirst (DRagLint.CLI.pas), DRagLint.Core.Model.CrossesGuiFramework (DRagLint.Core.Model.pas), DRagLint.Storage.SQLite.PickAncestorCandidateByScope (DRagLint.Storage.SQLite.pas), DRagLint.Storage.SQLite.TSQLiteSymbolStore.FrameworkAnchorForFile (DRagLint.Storage.SQLite.pas)</para>
/// <para>Calls: Copy, LastDelimiter</para>
/// <para>Pure</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function DeclaringUnitOfQName(const AQName: string): string;

/// <summary>The leading NAMESPACE SEGMENT of a dotted unit name -- the
/// substring before the FIRST '.' ('Vcl.Controls' -&gt; 'Vcl'; 'Vcl.StdCtrls'
/// -&gt; 'Vcl'; 'FMX.Controls.Win' -&gt; 'FMX'; 'Winapi.Windows' -&gt;
/// 'Winapi').</summary>
/// <param name="AUnitName"><!-- drag-lint:auto type -->const string</param>
/// <returns>The segment, or '' when AUnitName carries no dot at all.</returns>
/// <remarks>
/// An UNDOTTED unit name -- a hermetic-test unit ('VclKit') or real
/// third-party code ('cxButtons', 'Abcbtn') -- has NO namespace segment, and
/// must never be treated as sharing one with a dotted name like 'Vcl.Controls'.
/// Returning '' is what makes BOTH sides skip it rather than substring-match:
/// the SELECT side (PickAncestorCandidateByScope rule 3, which needs a unique
/// same-segment candidate) and the REFUSE side (the proptree climb's
/// cross-GUI-framework guard, CrossesGuiFramework, which refuses only when BOTH
/// segments are GUI frameworks -- see IsGuiFrameworkPrefix -- and differ). This
/// is the single definition of that notion; do not re-derive it.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.PreferFrameworkFirst (DRagLint.CLI.pas), DRagLint.Core.Model.CrossesGuiFramework (DRagLint.Core.Model.pas), DRagLint.Storage.SQLite.PickAncestorCandidateByScope (DRagLint.Storage.SQLite.pas), DRagLint.Storage.SQLite.PickAncestorCandidateByScope.WeakHitFrameworkUnconfirmed (DRagLint.Storage.SQLite.pas), DRagLint.Storage.SQLite.TSQLiteSymbolStore.FrameworkAnchorForFile (DRagLint.Storage.SQLite.pas) (+2 more)</para>
/// <para>Calls: Copy, Pos</para>
/// <para>Returns: ''; Copy(AUnitName, 1, P - 1)</para>
/// <para>Pure</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function UnitFrameworkPrefix(const AUnitName: string): string;

/// <summary>True when ANamespaceSegment is one of Delphi's two MUTUALLY
/// EXCLUSIVE GUI framework namespaces -- 'Vcl' or 'FMX' (case-insensitive
/// compare; '' is never one).</summary>
/// <param name="ANamespaceSegment">A LEADING namespace segment as returned by
/// UnitFrameworkPrefix -- not a whole unit name. 'Vcl.Graphics' is NOT a GUI
/// framework prefix; 'Vcl' is.</param>
/// <returns><!-- drag-lint:auto -->Boolean -- Observed: SameText(ANamespaceSegment,
/// 'Vcl') or SameText(ANamespaceSegment, 'FMX').</returns>
/// <remarks>
/// A Delphi class surface is either VCL or FireMonkey; the two are
/// parallel, never interchangeable, and a type from one is never a valid
/// stand-in for a same-named type from the other. Everything else a GUI unit
/// legitimately reaches -- 'System.*', 'Winapi.*', 'Data.*', 'Soap.*', a
/// project's own namespace, an undotted legacy unit -- is SHARED ground, not a
/// competing framework, and is deliberately NOT listed here.
/// The pair is named explicitly rather than derived, because "which namespaces
/// are mutually exclusive" is a fact about Delphi's two GUI frameworks, not
/// something the shape of a unit name can tell you. This is the ONLY place in
/// src/ that names them: the REFUSE side (DRagLint.Convert.PropTree's
/// CrossesGuiFramework, design criterion 5) and the SELECT side
/// (DRagLint.Storage.SQLite's ancestry-derived framework anchor and its
/// last-segment `uses` guard) both call in here rather than each carrying a
/// literal. NOT a general "same namespace?" test -- it answers only "is this
/// segment one of the two conflicting GUI frameworks?".
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.PreferFrameworkFirst (DRagLint.CLI.pas), DRagLint.Core.Model.CrossesGuiFramework (DRagLint.Core.Model.pas), DRagLint.Storage.SQLite.PickAncestorCandidateByScope.WeakHitFrameworkUnconfirmed (DRagLint.Storage.SQLite.pas), DRagLint.Storage.SQLite.TSQLiteSymbolStore.FrameworkAnchorForFile (DRagLint.Storage.SQLite.pas), DRagLint.Storage.SQLite.TSQLiteSymbolStore.GuiFrameworkInUse (DRagLint.Storage.SQLite.pas) (+1 more)</para>
/// <para>Calls: SameText</para>
/// <para>Pure</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function IsGuiFrameworkPrefix(const ANamespaceSegment: string): Boolean;

/// <summary>True when AInheritor and ACandidate are declared in units belonging
/// to DIFFERENT Delphi GUI frameworks -- one Vcl.*, the other FMX.* -- i.e. the
/// candidate is never a legitimate ancestor/type for the inheritor.</summary>
/// <param name="AInheritor">The class the answer would be grafted ONTO.</param>
/// <param name="ACandidate">The class being considered for it.</param>
/// <returns>True only when BOTH declaring units carry a GUI framework segment
/// AND those segments differ. False whenever either side is undotted, is a
/// shared namespace (System.*, Winapi.*, Data.*), or is the same framework --
/// so an ordinary RTL reference is never refused.</returns>
/// <remarks>
/// v(merge main -&gt; autodoc-phase3): PROMOTED here from a local
/// function inside DRagLint.Convert.PropTree, because a SECOND site turned out
/// to need it and a copy is how these two drift. That second site is the
/// storage-layer late-ancestor resolution in
/// TSQLiteSymbolStore.GetTransitiveAncestors, which exists only on this branch:
/// PropTree guarded its OWN walk, so when the branch's late resolution began
/// answering names PropTree's walk never asked about, criterion 5 was enforced
/// on one path and not the other. Measured, not theorised -- it reddened
/// run_proptree_ancestor_climb and run_proptree_prop_type_scope, both of which
/// pass on main, the moment the two branches met.
/// <para>Why the refusal is needed at all even though a scope rule exists:
/// PickCandidate short-circuits on a LONE candidate before any scope rule runs,
/// so a type name with exactly one -- possibly wrong-framework -- definition is
/// returned with no scope check. This is the backstop for precisely that.</para>
/// <para>A Delphi class surface is either VCL or FireMonkey; the two are
/// parallel, and a type from one is never a stand-in for a same-named type from
/// the other. The pair itself is named in IsGuiFrameworkPrefix, which is the one
/// place it is written down.</para>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Convert.PropTree.BuildPropTree.ClassChain.ClimbFrom (DRagLint.Convert.PropTree.pas), DRagLint.Convert.PropTree.BuildPropTree.ResolveViaBridgedAncestry.Climb (DRagLint.Convert.PropTree.pas), DRagLint.Convert.PropTree.BuildPropTree.Walk (DRagLint.Convert.PropTree.pas), DRagLint.Storage.SQLite.TSQLiteSymbolStore.GetTransitiveAncestors (DRagLint.Storage.SQLite.pas)</para>
/// <para>Calls: DRagLint.Core.Model.DeclaringUnitOfQName, DRagLint.Core.Model.IsGuiFrameworkPrefix, DRagLint.Core.Model.UnitFrameworkPrefix, SameText</para>
/// <para>Pure</para>
/// <seealso cref="DRagLint.Core.Model.DeclaringUnitOfQName"/>
/// <seealso cref="DRagLint.Core.Model.IsGuiFrameworkPrefix"/>
/// <seealso cref="DRagLint.Core.Model.UnitFrameworkPrefix"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function CrossesGuiFramework(const AInheritor, ACandidate: TSymbol): Boolean;

implementation

uses
  System.SysUtils
  ;

function IntrinsicSignature(const AName: string): string;
begin
  if SameText(AName, 'Assigned') then Result:= 'function System.Assigned(var P): Boolean'
  else if SameText(AName, 'Length'   ) then Result:= 'function System.Length(const S): Integer'
  else if SameText(AName, 'SetLength') then Result:= 'procedure System.SetLength(var S; NewLength: Integer)'
  else if SameText(AName, 'Inc'      ) then Result:= 'procedure System.Inc(var X [; N: Integer])'
  else if SameText(AName, 'Dec'      ) then Result:= 'procedure System.Dec(var X [; N: Integer])'
  else if SameText(AName, 'Ord'      ) then Result:= 'function System.Ord(X): Integer'
  else if SameText(AName, 'Chr'      ) then Result:= 'function System.Chr(B: Byte): AnsiChar'
  else if SameText(AName, 'High'     ) then Result:= 'function System.High(X): <ordinal>'
  else if SameText(AName, 'Low'      ) then Result:= 'function System.Low(X): <ordinal>'
  else if SameText(AName, 'SizeOf'   ) then Result:= 'function System.SizeOf(X): Integer'
  else if SameText(AName, 'TypeInfo' ) then Result:= 'function System.TypeInfo(X): Pointer'
  else if SameText(AName, 'Succ'     ) then Result:= 'function System.Succ(X): <ordinal>'
  else if SameText(AName, 'Pred'     ) then Result:= 'function System.Pred(X): <ordinal>'
  else if SameText(AName, 'Trunc'    ) then Result:= 'function System.Trunc(X: Extended): Int64'
  else if SameText(AName, 'Round'    ) then Result:= 'function System.Round(X: Extended): Int64'
  else if SameText(AName, 'Frac'     ) then Result:= 'function System.Frac(X: Extended): Extended'
  else if SameText(AName, 'Abs'      ) then Result:= 'function System.Abs(X): <numeric>'
  else if SameText(AName, 'Sqr'      ) then Result:= 'function System.Sqr(X): <numeric>'
  else if SameText(AName, 'Sqrt'     ) then Result:= 'function System.Sqrt(X: Extended): Extended'
  else if SameText(AName, 'Exit'     ) then Result:= 'procedure System.Exit [(Result)]'
  else if SameText(AName, 'Break'    ) then Result:= 'procedure System.Break'
  else if SameText(AName, 'Continue' ) then Result:= 'procedure System.Continue'
  else if SameText(AName, 'Halt'     ) then Result:= 'procedure System.Halt [(ExitCode: Integer)]'
  else if SameText(AName, 'Assert'   ) then Result:= 'procedure System.Assert(expr: Boolean [; const msg: string])'
  else Result:= '';
end; // function

function IsCompilerIntrinsic(const AName: string): Boolean;
begin
  Result:= IntrinsicSignature(AName) <> '';
end;

function DeclaringUnitOfQName(const AQName: string): string;
var P: Integer;
begin
  Result:= '';
  P:= LastDelimiter('.', AQName);
  if P > 1 then Result:= Copy(AQName, 1, P - 1);
end;

function UnitFrameworkPrefix(const AUnitName: string): string;
var P: Integer;
begin
  Result:= '';
  P:= Pos('.', AUnitName);
  if P > 0 then Result:= Copy(AUnitName, 1, P - 1);
end;

function IsGuiFrameworkPrefix(const ANamespaceSegment: string): Boolean;
begin
  Result:= SameText(ANamespaceSegment, 'Vcl') or SameText(ANamespaceSegment, 'FMX');
end;

function CrossesGuiFramework(const AInheritor, ACandidate: TSymbol): Boolean;
var
  InhPrefix : string;
  CandPrefix: string;
begin
  InhPrefix := UnitFrameworkPrefix(DeclaringUnitOfQName(AInheritor.QualifiedName));
  CandPrefix:= UnitFrameworkPrefix(DeclaringUnitOfQName(ACandidate.QualifiedName));
  Result    := IsGuiFrameworkPrefix(InhPrefix) and IsGuiFrameworkPrefix(CandPrefix) and
               not SameText(InhPrefix, CandPrefix);
end;

const
  KindText: array[TSymbolKind] of string = (
    'unit', 'program', 'package', 'class', 'interface', 'record', 'enum', 'enum_value', 'procedure', 'function', 'method', 'constructor', 'destructor', 'property', 'field', 'var',
    'const', 'type', 'form', 'component', 'sql_table', 'sql_column', 'sql_index', 'sql_trigger', 'sql_generator', 'sql_procedure', 'sql_view', 'sql_exception', 'sql_domain',
    'sql_constraint', 'initialization', 'finalization',
    'local_var', 'param');   // v14 (D5)

function TSymbolKindHelper.ToText: string;
begin
  Result:= KindText[Self];
end;

function TTypeCategoryHelper.ToText: string;
begin
  case Self of
    tcFloat    : Result:= 'float';
    tcString   : Result:= 'string';
    tcChar     : Result:= 'char';
    tcOrdinal  : Result:= 'ordinal';
    tcBoolean  : Result:= 'boolean';
    tcInterface: Result:= 'interface';
    tcClass    : Result:= 'class';
    tcRecord   : Result:= 'record';
    tcPointer  : Result:= 'pointer';
    tcEnum     : Result:= 'enum';
    else         Result:= 'unknown';
  end;
end;

class function TSymbolKindHelper.FromText(const AText: string): TSymbolKind;
var
  K: TSymbolKind;
begin
  for K:= Low(TSymbolKind) to High(TSymbolKind) do
    if SameText(KindText[K], AText) then Exit(K);
  raise Exception.CreateFmt('Unknown symbol kind: "%s"', [AText]);
end;

function UnitUseSectionToStr(ASection: TUnitUseSection): string;
begin
  case ASection of
    uusInterface     : Result:= 'interface';
    uusImplementation: Result:= 'implementation';
    uusProgram       : Result:= 'program';
    uusPackage       : Result:= 'package';
    else Result:= 'unknown';
  end;
end;

function StrToUnitUseSection(const AStr: string): TUnitUseSection;
begin
  if SameText(AStr, 'interface') then Result:= uusInterface
  else if SameText(AStr, 'implementation') then Result:= uusImplementation
  else if SameText(AStr, 'program'       ) then Result:= uusProgram
  else if SameText(AStr, 'package'       ) then Result:= uusPackage
  else Result:= uusImplementation;
end;

function DocFormatToStr(AFormat: TDocFormat): string;
begin
  case AFormat of
    dfXmlDoc : Result:= 'xmldoc';
    dfPasDoc : Result:= 'pasdoc';
    dfOneline: Result:= 'oneline';
    dfLoose  : Result:= 'loose';
    else Result:= 'unknown';
  end;
end;

function JsonEscape(const S: string): string;
var
  I: Integer;
  C: Char   ;
begin
  Result:= '';
  for I:= 1 to Length(S) do
  begin
    C:= S[I];
    case C of
      '"': Result:= Result + '\"';
      '\': Result:= Result + '\\';
      #8 : Result:= Result + '\b';
      #9 : Result:= Result + '\t';
      #10: Result:= Result + '\n';
      #13: Result:= Result + '\r';
      else if C < #32 then Result:= Result + Format('\u%.4x', [Ord(C)])
      else Result:= Result + C;
    end;
  end; // for
end; // function

function ParamsToJson(const AParams: TArray<TDocParam>): string;
var
  Parts: TArray<string>;
  I    : Integer       ;
begin
  if Length(AParams) = 0 then Exit('');
  SetLength(Parts, Length(AParams));
  for I:= 0 to High(AParams) do Parts[I]:= Format('{"name":"%s","desc":"%s"}', [JsonEscape(AParams[I].Name), JsonEscape(AParams[I].Desc)]);
  Result:= '[' + string.Join(',', Parts) + ']';
end;

function ExceptionsToJson(const AExceptions: TArray<TDocException>): string;
var
  Parts: TArray<string>;
  I    : Integer       ;
begin
  if Length(AExceptions) = 0 then Exit('');
  SetLength(Parts, Length(AExceptions));
  for I:= 0 to High(AExceptions) do Parts[I]:= Format('{"type":"%s","desc":"%s"}', [JsonEscape(AExceptions[I].TypeName), JsonEscape(AExceptions[I].Desc)]);
  Result:= '[' + string.Join(',', Parts) + ']';
end;

function SeeAlsoToJson(const ASeeAlso: TArray<string>): string;
var
  Parts: TArray<string>;
  I    : Integer       ;
begin
  if Length(ASeeAlso) = 0 then Exit('');
  SetLength(Parts, Length(ASeeAlso));
  for I:= 0 to High(ASeeAlso) do Parts[I]:= Format('"%s"', [JsonEscape(ASeeAlso[I])]);
  Result:= '[' + string.Join(',', Parts) + ']';
end;

function DefaultDocConfig: TDocConfig;
begin
  Result.CaptureLooseComments:= False;
  Result.ImplPrecedence      := 'interface';
  // v(ADP3 T3j review round 2, Important 2): DOC_ALLOW_GAP, not a literal --
  // this is the default the index-time path uses when no JSON override is set,
  // so a literal here is one more way the sites could drift apart.
  Result.AllowBlankLineGap   := DOC_ALLOW_GAP;
end;

// v(ADP3 T3j review round 1): see the block comment on these three in the
// interface section for why they live here rather than in any of the three
// units that call them.
function DocRegionInGapWindow(AEndLine, ADeclLine, AAllowGap: Integer): Boolean;
begin
  Result:= (AEndLine >= ADeclLine - 1 - AAllowGap) and (AEndLine <= ADeclLine - 1);
end;

function NoDeclarationInGap(AEndLine, ADeclLine: Integer;
  const ASymStartLines: TArray<Integer>): Boolean;
var
  L: Integer;
begin
  Result:= True;
  for L in ASymStartLines do
  begin
    // Sorted ascending, so nothing further can qualify -- and this is also what
    // excludes ADeclLine's OWN entry, which the array includes.
    if L >= ADeclLine then Break;
    if L > AEndLine then Exit(False);
  end;
end;

function DocRegionFitsDecl(AEndLine, ADeclLine, AAllowGap: Integer;
  const ASymStartLines: TArray<Integer>): Boolean;
begin
  Result:= DocRegionInGapWindow(AEndLine, ADeclLine, AAllowGap)
           and NoDeclarationInGap(AEndLine, ADeclLine, ASymStartLines);
end;

function CallSiteRefKindSql(const ARefAlias: string): string;
{ QuotedStr doubles any embedded apostrophe, so the emitted fragment stays
  well-formed no matter what REF_KIND_CALL is set to.
  v(ADP3 T3i review round 2): the blank-alias guard is real, not decorative --
  without it an empty alias yields '.kind = ''call''', which is invalid SQL that
  fails at prepare time with a message pointing at the whole query rather than
  at the caller that forgot its alias. }
begin
  if Trim(ARefAlias) = '' then
    raise EArgumentException.Create('CallSiteRefKindSql: ARefAlias must name a table or alias');
  Result:= ARefAlias + '.kind = ' + QuotedStr(REF_KIND_CALL);
end;

function CanBeCallTarget(AKind: TSymbolKind): Boolean;
begin
  Result:= AKind in [skProcedure, skFunction, skMethod, skConstructor, skDestructor];
end;

end.
