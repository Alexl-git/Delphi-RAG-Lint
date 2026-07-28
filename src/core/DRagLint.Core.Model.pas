unit DRagLint.Core.Model;

interface

type
  TSymbolKind = (
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
    function ToText: string                                          ;
    class function FromText(const AText: string): TSymbolKind; static;
  end;

  /// <summary>v11 (M1): the broad category a declared/aliased type resolves to.
  /// Drives the type-aware rule family (float/string-equality, freeandnil-on-
  /// interface, win64-pointer-cast). tcUnknown = could not resolve.</summary>
  TTypeCategory = (
    tcUnknown, tcFloat, tcString, tcChar, tcOrdinal, tcBoolean,
    tcInterface, tcClass, tcRecord, tcPointer, tcEnum);

  TTypeCategoryHelper = record helper for TTypeCategory
    function ToText: string;
  end;

  TFileTxToken = record
    FileId: Int64 ;
    Path  : string;
  end;

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
    /// <summary>False when no symbol_facts row exists for SymbolId -- the
    /// renderer's cue to omit every derived doc-comment line entirely.</summary>
    Present     : Boolean;
  end; // record

  /// <summary>v11 (M1): one resolved ancestor edge of a class/interface --
  /// either a direct heritage entry (type_ancestors row) or, in a transitive
  /// closure, a reachable ancestor. Name is the normalized ancestor type name;
  /// Kind is 'class'|'interface'|'?' ('?' when unresolved). Resolved is True
  /// when the ancestor was linked to a defining symbol (SymbolId/FileId set).</summary>
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
  THelperEdge = record
    HelperSymbolId: Int64 ;
    TargetName    : string;
    TargetSymbolId: Int64 ;
    TargetFileId  : Int64 ;
    HelperKind    : string; // 'record' | 'class'
  end;

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
  end;

  /// <summary>v14 (D5): one resolved call-site edge, written by the
  /// ResolveCallTargets pass and read back by the Called-from / find-callees
  /// queries. Stored Confidence is ALWAYS 'certain' or 'ambiguous' (the two
  /// values the resolver writes to call_edges.confidence).</summary>
  TCallEdge = record
    RefId               : Int64 ;
    TargetSymbolId      : Int64 ;
    ReceiverTypeSymbolId: Int64 ;
    Confidence          : string;
  end;

  /// <summary>v14 (D5): one resolved uses-scope edge -- file AFileId can see
  /// (has in its uses graph, directly) the unit whose file is ATargetFileId.
  /// Bulk-read by TCallResolver to build its per-file in-scope set, mirroring
  /// ResolveAncestry's FileScope map. Both ids are always &gt; 0 (the reader
  /// filters out unresolved uses rows).</summary>
  TFileScopeEdge = record
    FileId      : Int64;
    TargetFileId: Int64;
  end;

  /// <summary>v14 (D5): a RENDERING value for one resolved (or best-effort
  /// unresolved) caller of a target symbol. Confidence is 'certain' |
  /// 'ambiguous' | 'unverified' -- the last for the no-call_edges-row '?'
  /// bucket surfaced by FindUnresolvedNameCallers. Renderer: 'certain' ->
  /// plain; 'ambiguous'/'unverified' -> append ' ?'.</summary>
  TResolvedCaller = record
    EnclosingSymbolId: Int64 ;
    EnclosingQName   : string;
    Location         : string; // filename only (unchanged; existing consumers rely on this)
    /// <summary>1-based line of the call site in the caller's file; 0 when unknown.
    /// Added for reverse-calltree; other consumers may ignore it.</summary>
    CallSiteLine     : Integer;
    Confidence       : string;
  end;

  /// <summary>v8: one Spring4D DI registration (interface implemented by impl,
  /// with lifetime). Endpoint names are verbatim, including nested generics.
  /// FileId is filled by the store from the file transaction token.</summary>
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

  /// <summary>One indexed string-literal occurrence (a message, caption, or
  /// exception text). SymbolId is the enclosing routine/component, resolved by
  /// the indexer post-parse (0 in parser output). Text is the DECODED logical
  /// string (escapes/`#nn`/continuations resolved); never empty.</summary>
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

  TChunk = record
    Id       : Int64  ;
    FileId   : Int64  ;
    SymbolId : Int64  ;
    Kind     : string ;
    StartLine: Integer;
    EndLine  : Integer;
    Text     : string ;
  end;

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
  end;

  TDocCommentKind = ( dckTripleSlash, dckDoubleSlashOne, dckTripleSlashOne, dckPasDocCurly, dckPasDocParen, dckLooseLine, dckLooseBlock );

  TDocFormat = (dfXmlDoc, dfPasDoc, dfOneline, dfLoose);

  TDocCommentRegion = record
    StartLine: Integer        ;
    EndLine  : Integer        ;
    StartCol : Integer        ;
    Kind     : TDocCommentKind;
    RawText  : string         ;
  end;

  TDocParam = record
    Name: string;
    Desc: string;
  end;

  TDocException = record
    TypeName: string;
    Desc    : string;
  end;

  // v0.40.4: captured from `uses` clauses to support circular-dep detection,
  // move-down (interface->implementation) suggestions, and unused-unit
  // analysis in graphing + lint utilities.
  TUnitUseSection = (
    uusInterface, // `interface uses ...`
    uusImplementation, // `implementation uses ...`
    uusProgram, // top-level uses in a .dpr
    uusPackage // top-level uses in a .dpk
  );

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
  TDocConfig = record
    CaptureLooseComments: Boolean;
    ImplPrecedence      : string ;
    AllowBlankLineGap   : Integer;
  end;

  TImpactLevel = record
    Depth      : Integer       ;
    CallerCount: Integer       ;
    UnitCount  : Integer       ;
    Categories : TArray<string>;
  end;

  TSurfaceLine = record
    Kind     : string ;
    Text     : string ;
    StartLine: Integer;
    EndLine  : Integer;
  end;

  TSliceChunk = record
    Kind     : string ;
    Text     : string ;
    StartLine: Integer;
    EndLine  : Integer;
  end;

  // v0.18: resolved caller entry for a context bundle (FilePath pre-resolved
  // from FileId so renderers don't need a store callback).
  TBundleCaller = record
    FilePath   : string ;
    Line       : Integer;
    Col        : Integer;
    ContextText: string ;
  end;

  // v0.26: compiler diagnostic finding (from dcc64 or msbuild output).
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
  end;

function DocFormatToStr     (AFormat : TDocFormat     ): string;
function UnitUseSectionToStr(ASection: TUnitUseSection): string;
function StrToUnitUseSection(const AStr: string): TUnitUseSection          ;
function JsonEscape(const S: string): string                               ;
function ParamsToJson    (const AParams    : TArray<TDocParam    >): string;
function ExceptionsToJson(const AExceptions: TArray<TDocException>): string;
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
/// <remarks>Proximity only. It says nothing about WHAT occupies the gap -- pair
/// it with NoDeclarationInGap (or use DocRegionFitsDecl, which is both).</remarks>
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
/// <remarks>Blank lines are never symbol start lines, so a region separated
/// from its declaration by blank lines alone always passes. This is the guard
/// added by adp2-docregion-fix, and it is deliberately about DECLARATIONS
/// rather than blankness: an ordinary comment in the gap is tolerated on
/// purpose, because the doc comment above it still belongs to ADeclLine.</remarks>
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
function DocRegionFitsDecl(AEndLine, ADeclLine, AAllowGap: Integer;
  const ASymStartLines: TArray<Integer>): Boolean;

{ v(ADP3 T3i): THE CALL-SITE REF-KIND UNIVERSE. ONE declaration, read by the
  pass that WRITES resolved call edges and by both queries that read the
  UNRESOLVED complement of those edges:

    * DRagLint.Parser.Delphi13                        (emits the kind)
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

  DISCLOSED CONSEQUENCE (a writer-side gap, deliberately NOT fixed here). A
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
  and still finds them. Pinned by tests/callresolve/run_callsite_kind_universe.ps1. }

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
/// <remarks>Emits the value of REF_KIND_CALL, so the SQL sites and the Pascal
/// sites share one declaration. Returns a bare predicate with no AND/WHERE, so
/// the caller controls where it is spliced.</remarks>
function CallSiteRefKindSql(const ARefAlias: string): string;

implementation

uses
  System.SysUtils
  ;

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

end.
