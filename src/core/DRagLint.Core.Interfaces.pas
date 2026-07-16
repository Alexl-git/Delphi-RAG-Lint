unit DRagLint.Core.Interfaces;

interface

uses
  System.SysUtils
  , DRagLint.Core.Model
  , DRagLint.Preprocess.Types
  ;

type
  /// <summary>Walk-filter settings passed to IIndexer.SetWalkFilter.
  /// Controls which files and directories are included or excluded during
  /// a folder-tree index walk.</summary>
  /// <remarks>Use TWalkFilter.Create to obtain the safe default (SqlOnlyMS=True,
  /// all other fields empty/False). A bare Default(TWalkFilter) zero-inits the
  /// record and leaves SqlOnlyMS=False, which indexes every .sql file --
  /// callers must not rely on Default(TWalkFilter) for the safe default.</remarks>
  TWalkFilter = record
    /// <summary>Glob patterns applied to both file names and directory names.
    /// Any file or dir whose name matches is skipped globally.</summary>
    GlobalExclude: TArray<string>;
    /// <summary>Additional glob patterns for files and dirs to skip in this
    /// particular index section (union with GlobalExclude).</summary>
    SectionExclude: TArray<string>;
    /// <summary>Allow-list of glob patterns. When non-empty, only files whose
    /// name matches at least one pattern are indexed; non-matching files are
    /// skipped. Directories are not affected by this filter.</summary>
    IncludeOnly: TArray<string>;
    /// <summary>When True, .gitignore and .hgignore files found while
    /// descending the tree are loaded and honoured.</summary>
    UseIgnoreFiles: Boolean;
    /// <summary>When True (the default via Create), .sql files must match the
    /// MS*.SQL naming convention to be indexed. Set to False to index all SQL
    /// files regardless of name.</summary>
    SqlOnlyMS: Boolean;
    /// <summary>Maximum file size in KB that the indexer will hand to the
    /// tree-sitter parser. Files exceeding this threshold are silently skipped
    /// with a SKIP warning to stdout. 0 = no limit (unlimited).
    /// Default via Create: 2048 (2 MB). Applies to all parsed extensions
    /// (.pas, .inc, .dfm, .sql).</summary>
    /// <remarks>The guard exists because tree-sitter recurses on large flat
    /// literals and can overflow the native stack (segfault, not catchable by
    /// Delphi's EExternal handler). 2 MB is well above any hand-written
    /// source file and safely below the files that trigger the crash.</remarks>
    MaxFileKB: Integer;
    /// <summary>Returns a TWalkFilter with the safe defaults: SqlOnlyMS=True,
    /// MaxFileKB=2048, all other fields empty/False. Prefer this over
    /// Default(TWalkFilter), which leaves SqlOnlyMS=False and MaxFileKB=0.</summary>
    class function Create: TWalkFilter; static;
  end; // record

  ISymbolStore = interface
    ['{6B9F8AC4-3F19-4E1A-9D38-1A2C3B7EF501}']
    procedure Migrate;
    // v0.86 Task 4: read-only, no-DDL schema-version probe. AFound receives the
    // DB's stored schema_version (0 when absent); AExpected receives the engine's
    // SCHEMA_VERSION. Returns AFound >= AExpected. Read verbs call this after a
    // read-only open to emit the actionable stale-schema message instead of
    // running a query against a pre-current schema.
    function IsSchemaCurrent(out AFound, AExpected: Integer): Boolean;
    // v0.4: returns True if this file is already indexed at exactly this
    // mtime AND sha256 - so the indexer can skip re-parsing it.
    function FileIsUpToDate(const APath: string; AMtimeUnix: Int64; const ASha: string): Boolean                          ;
    function OpenFileTx(const APath: string; AMtimeUnix: Int64; const ASha: string; const ALanguage: string): TFileTxToken;
    function UpsertSymbol(const AToken: TFileTxToken; const ASymbol: TSymbol): Int64                                      ;
    procedure UpsertReference(const AToken: TFileTxToken; const ARef  : TReference);
    procedure UpsertChunk    (const AToken: TFileTxToken; const AChunk: TChunk    );
    procedure CommitFileTx  (const AToken: TFileTxToken);
    procedure RollbackFileTx(const AToken: TFileTxToken);

    function FindSymbolsByExactName    (const AName : string): TArray<TSymbol>;
    function FindSymbolsByQualifiedName(const AQName: string): TArray<TSymbol>;
    // v0.42: file outline - every symbol declared in one file, ordered by
    // position. Backs the Structure form (was mis-using class-scoped surface).
    function FindSymbolsByFile(const APath: string): TArray<TSymbol>                       ;
    function FindReferencesTo(ASymbolId: Int64): TArray<TReference>                        ;
    function FindCallersByName(const ACalleeName: string): TArray<TReference>              ;
    function FindSymbolsFuzzy(const APattern: string; ATopK: Integer = 10): TArray<TSymbol>;
    function GetFilePath(AFileId: Int64): string                                           ;
    function GetAllFileIds: TArray<Int64>                                                  ; { v0.43: for cycles / cross-file scans }
    function GetReferencesFromFile(AFileId: Int64): TArray<TReference>                     ; { v0.43: uses-audit }
    function CountSymbols   : Int64;
    function CountReferences: Int64;
    function CountFiles     : Int64;

    // v0.17: blast-radius pack
    function FindTransitiveCallers(const ASymbolName: string; ADepth: Integer): TArray<TImpactLevel>            ;
    function GetClassSurface(const AQName: string; AIncludeImpl, AAllVisibility: Boolean): TArray<TSurfaceLine> ;
    function GetSymbolSlice(const AQName: string): TArray<TSliceChunk>                                          ;
    function FindCallersByNameWithContext(const ACalleeName: string; AContextLines: Integer): TArray<TReference>;

    procedure UpsertSymbolDoc(const AToken: TFileTxToken; ASymbolId: Int64; const ADoc: TParsedDoc);
    function GetSymbolDoc(ASymbolId: Int64): TParsedDoc;

    // v0.40.4: uses-clause persistence + queries.
    procedure UpsertUnitUse(const AToken: TFileTxToken; const AUse: TUnitUse);
    procedure DeleteUnitUsesForFile(AFileId: Int64);
    function GetUnitUsesForFile(AFileId: Int64): TArray<TUnitUse>          ;
    function FindUsersOfUnit(const AUnitNameNorm: string): TArray<TUnitUse>;
    procedure ResolveUnitUseTargets;
    // v11 (M1): type & hierarchy resolution. ResolveAncestry is a whole-DB
    // post-index pass (run after ResolveUnitUseTargets) that splits each
    // class/interface's `heritage` text, resolves each ancestor to a defining
    // symbol via the file's in-scope uses graph, and writes type_ancestors edges.
    procedure ResolveAncestry;
    /// <summary>v15: whole-DB helper-resolution pass (run after ResolveAncestry).
    /// Links each record/class helper's target type name to its defining symbol,
    /// resolving cross-unit via the units-in-scope graph. Committed to
    /// type_helpers table.</summary>
    procedure ResolveHelpers;
    /// <summary>v14 (D5): whole-DB call-resolution pass (run after ResolveAncestry,
    /// which it depends on for the ancestor chain). Wipes call_edges, then types
    /// the receiver of every 'call' ref and writes a resolved edge (target symbol +
    /// 'certain'|'ambiguous' confidence) for each site it can resolve; unresolved
    /// sites get no row (FP-conservative). Rebuilds all edges each run.</summary>
    procedure ResolveCallTargets;
    /// <summary>Transitive ancestor closure of the symbol (resolved edges are
    /// walked recursively; unresolved ones are name-only leaves). Cycle-safe,
    /// hop-capped.</summary>
    function GetTransitiveAncestors(ASymbolId: Int64): TArray<TTypeAncestor>;
    /// <summary>True when class/interface AClassName (resolved in-scope of
    /// AFileId) has AAncestorName anywhere in its transitive ancestor closure.</summary>
    function IsDescendantOf(const AClassName, AAncestorName: string; AFileId: Int64): Boolean;
    /// <summary>Every class whose transitive ancestor set includes AAncestorName
    /// (the reverse of IsDescendantOf). Distinct class names, sorted. Backed by a
    /// single indexed lookup on type_ancestors.ancestor_name.</summary>
    function FindDescendantNames(const AAncestorName: string): TArray<string>;
    /// <summary>True when AClassName's transitive closure reaches AInterfaceName
    /// via an interface-kind edge (i.e. AClassName implements that interface).</summary>
    function ImplementsInterface(const AClassName, AInterfaceName: string; AFileId: Int64): Boolean;
    /// <summary>Resolve a type name to its broad category: intrinsics by name
    /// first, then a declared class/interface/enum/record symbol's kind, chasing
    /// `type X = Y` aliases to a fixpoint. AFileId disambiguates same-named types
    /// (prefer the one declared in that file). tcUnknown when unresolvable.</summary>
    function ResolveTypeCategory(const ATypeName: string; AFileId: Int64): TTypeCategory;
    /// <summary>Lowercased names of every virtually-dispatched method visible on
    /// AClassName -- its own virtuals plus those inherited from resolved ancestors
    /// (cross-unit). Backs cross-unit virtual-method-in-constructor.</summary>
    function GetVirtualMethodsIncludingAncestors(const AClassName: string; AFileId: Int64): TArray<string>;
    /// <summary>v15: all helpers (record/class) whose target type name matches
    /// ATargetName (whole-DB). Empty when no helper targets that type.
    /// NAME-ONLY match: two unrelated same-named types in different units
    /// (e.g. two distinct `TColor` enums) are indistinguishable to this call
    /// -- prefer FindHelpersOfTypeSymbol when the candidate's own symbol id
    /// is known, to avoid cross-linking unrelated same-named types.</summary>
    function FindHelpersOfType(const ATargetName: string): TArray<THelperEdge>;
    /// <summary>Task 9b (FP fix): all helpers (record/class) whose edge
    /// resolved its target to the EXACT symbol ATargetSymbolId (identity
    /// match via type_helpers.target_symbol_id, not the target's bare name).
    /// Only edges with a RESOLVED target_symbol_id can match -- an edge whose
    /// target never resolved at index time (heritage name didn't uniquely
    /// resolve in scope) is excluded, since it cannot be proven to target
    /// ATargetSymbolId rather than some other same-named type. Use this
    /// instead of FindHelpersOfType(name) whenever the candidate type's own
    /// symbol id is known and false cross-links between same-named types in
    /// different units must be avoided (enum-helper-separate-units lint rule,
    /// enum-helper generator's existing-helper guard).</summary>
    function FindHelpersOfTypeSymbol(ATargetSymbolId: Int64): TArray<THelperEdge>;
    function FindByDocTag(const ATag: string): TArray<TSymbol>                           ;
    function FindUndocumented(const AKind: string; APublicOnly: Boolean): TArray<TSymbol>;
    function FindByDocContains(const ASubstring: string): TArray<TSymbol>                ;
    procedure DeleteFileDocs(AFileId: Int64);

    // v0.18: bench-context — symbols that have at least one non-null summary
    function ListDocumentedSymbols(ALimit: Integer): TArray<TSymbol>;

    // v0.19: type-at-position helpers
    function FindContainingSymbol(AFileId: Int64; ALine: Integer): TSymbol        ;
    function GetSymbolById(AId: Int64): TSymbol                                   ;
    function FindFileIdByPath             (const APath: string): Int64;
    function FindSymbolByExactNameAnywhere(const AName: string): TSymbol;
    function FindChildSymbolByName(AParentId: Int64; const AName: string): TSymbol;
    /// <summary>The innermost routine (procedure/function/method/constructor/
    /// destructor) whose IMPLEMENTATION BODY span (impl_start_line..impl_end_line)
    /// contains ALine in AFileId. Empty (Id=0) when the line is in no routine body.
    /// Unlike FindContainingSymbol (which matches the DECLARATION span), this finds
    /// the routine you are standing INSIDE -- needed to scope a bare identifier to
    /// that routine's params/locals.</summary>
    function FindEnclosingRoutineByImpl(AFileId: Int64; ALine: Integer): TSymbol;

    // v0.20: completion helpers
    function FindSymbolsByPrefix(const APrefix: string; ALimit: Integer): TArray<TSymbol>;
    function FindAllChildSymbols(AParentId: Int64): TArray<TSymbol>                      ;

    // v0.25: dead-code finder
    function FindSymbolsWithNoCallers(const AKind: string; AIncludePrivate: Boolean): TArray<TSymbol>;

    // v0.26: compiler diagnostics
    function FindCompilerFindingsForFile(AFileId: Int64): TArray<TCompilerFinding>;
    procedure ClearCompilerFindings;
    procedure InsertCompilerFinding(const AFinding: TCompilerFinding);
    /// <summary>Deletes only the compiler_findings rows for one file, so a
    /// single-unit recompile can replace that file's findings without touching
    /// others. (Whole-DB ClearCompilerFindings is unchanged.)</summary>
    procedure ClearCompilerFindingsForFile(AFileId: Int64);
    /// <summary>Stamps files.last_compiled_unix for one file (Unix seconds).</summary>
    procedure SetFileCompiledAt(AFileId: Int64; AUnix: Int64);
    /// <summary>Returns files.last_compiled_unix for one file, or 0 when NULL.</summary>
    function GetFileCompiledAt(AFileId: Int64): Int64;
    /// <summary>Returns file_ids whose findings are STALE: last_compiled_unix is
    /// NULL or older than mtime_unix. Pascal source files only.</summary>
    function GetStaleFileIds: TArray<Int64>;

    // v8: Spring4D DI edges.
    procedure UpsertDiBinding(const AToken: TFileTxToken; const ABinding: TDiBindingRow);
    procedure DeleteDiBindingsForFile(AFileId: Int64);
    function FindImplementationsOf( const AInterfaceName: string): TArray<TDiBindingRow>;
    function FindDiResolveSites   ( const AInterfaceName: string): TArray<TReference   >;
    function FindDiUnresolved: TArray<TReference>                                       ;
    /// <summary>DFM event handlers of a form/class: its child methods bound to a
    /// component event (kind='event-binding'). NameText is the handler method;
    /// FileId/StartLine point at the .dfm OnXxx line.</summary>
    function FindEventHandlersForForm( const AFormName: string): TArray<TReference>;

    // v10: string-content (text) index.
    /// <summary>Insert one string-literal occurrence into the text index for
    /// the file identified by AToken. AToken.FileId must already exist.</summary>
    procedure UpsertStringLiteral(const AToken: TFileTxToken; const ALit: TStringLiteral);
    /// <summary>Remove all string-literal rows (and their FTS entries) for the
    /// given file. Call before re-indexing a file to avoid duplicates.</summary>
    procedure DeleteStringLiteralsForFile(AFileId: Int64);
    /// <summary>Full-text search over indexed string literals. AMode selects the
    /// FTS strategy: 'phrase' (default, exact order), 'anyorder' (all words any
    /// order), 'substring' (trigram-based). ASource filters by source language
    /// ('pas'|'dfm'|'sql'); '' = all. Returns up to ALimit hits.</summary>
    function SearchText(const AQuery: string; AMode: string; const ASource: string; ALimit: Integer): TArray<TStringLitMatch>;

    // v14 (D5): resolved call-target edges (call_edges table).
    /// <summary>Insert or replace the resolved call edge for one ref (ref_id is
    /// the natural key -- a ref resolves to at most one target). NULLs
    /// ReceiverTypeSymbolId when it is &lt;= 0 (unknown receiver type).</summary>
    procedure UpsertCallEdge(const AToken: TFileTxToken; const AEdge: TCallEdge);
    /// <summary>Wipes the entire call_edges table. Called once at the start of
    /// the whole-DB ResolveCallTargets pass, which then rebuilds every edge.</summary>
    procedure ClearCallEdges;
    /// <summary>The Called-from query: every resolved caller of ATargetSymbolId,
    /// most-confident first. Backs the AutoDocument Called-from facts block.</summary>
    function FindResolvedCallers(ATargetSymbolId: Int64): TArray<TResolvedCaller>;
    /// <summary>v14 (D5): the AutoDocument '?' bucket -- every ref whose
    /// name_text = AName AND that has NO call_edges row (its receiver could not be
    /// typed, so the resolver emitted no edge). Each returned TResolvedCaller
    /// carries Confidence = 'unverified' so the renderer marks it ' ?' (honest:
    /// might or might not be the documented symbol). Ordered by file path then
    /// start line to mirror FindCallersByName's first-seen ordering. Location is
    /// file-name-only (idempotency: no volatile ':line'); EnclosingQName is '' when
    /// the ref has no enclosing routine.</summary>
    function FindUnresolvedNameCallers(const AName: string): TArray<TResolvedCaller>;
    /// <summary>Find-callees: every call edge whose ref is enclosed by
    /// AEnclosingSymbolId (i.e. every resolved call made from inside that
    /// routine's body).</summary>
    function GetCallEdgesFromSymbol(AEnclosingSymbolId: Int64): TArray<TCallEdge>;
    /// <summary>Total row count in call_edges. Diagnostic/test probe.</summary>
    function CountCallEdges: Int64;
    /// <summary>v14 (D5): SIZE ESCAPE HATCH -- delete every skLocalVar/skParam
    /// symbol (kind IN 'local_var','param') then VACUUM to reclaim the freed
    /// pages. Returns the number of local/param symbols removed. Once
    /// ResolveCallTargets has populated call_edges, these numerous per-local /
    /// per-param symbols have done their job (they let the resolver type
    /// call-site receivers); purging them slims the index. SAFETY: call_edges
    /// references call TARGETS (methods -&gt; ON DELETE CASCADE) and receiver
    /// TYPES (classes -&gt; ON DELETE SET NULL), NEVER a local/param, so no
    /// call_edges row can cascade-delete; the resolved call graph is unchanged.
    /// A ref that pointed at a purged local's declaration gets its symbol_id
    /// NULLed (refs.symbol_id ON DELETE SET NULL) -- the ref row survives, so
    /// call_edges.ref_id is intact too. NOT part of any auto-index path -- a
    /// reindex re-emits locals/params and rebuilds call_edges; this is a
    /// manual, point-in-time slim only. Idempotent: a second call removes 0.
    /// Must run OUTSIDE a transaction (SQLite rejects VACUUM in a tx); the
    /// bare autocommit ExecSQL path satisfies this.</summary>
    /// <returns>Count of local_var/param symbols deleted (0 if none remained).</returns>
    /// <remarks>Not thread-safe; call from the owning thread on a writable store.</remarks>
    function PurgeLocals: Int64;
    /// <summary>v14 (D5): every class/interface/record symbol (id, file_id, kind,
    /// name populated). Bulk read that backs TCallResolver's name-candidate map
    /// for receiver typing -- the same candidate set ResolveAncestry builds
    /// inline, exposed so the resolver can prepare it once.</summary>
    function GetTypeCandidates: TArray<TSymbol>;
    /// <summary>v14 (D5): every resolved uses-scope edge (file_id -&gt;
    /// target_file_id) from unit_uses where the target is resolved. Backs
    /// TCallResolver's per-file in-scope set (mirrors ResolveAncestry's
    /// FileScope). Unresolved uses rows (NULL target) are excluded.</summary>
    function GetUnitScopeEdges: TArray<TFileScopeEdge>;
    /// <summary>v14 (D5): every call_edges row (ref_id, target_symbol_id,
    /// confidence, receiver_type_symbol_id), unordered. Diagnostic dump backing
    /// the dump-call-edges verb / tests; not for production queries (use
    /// FindResolvedCallers / GetCallEdgesFromSymbol for those).</summary>
    function DumpAllCallEdges: TArray<TCallEdge>;
    /// <summary>v14 (D5 T9): the ambiguous-calls resolver-coverage diagnostic --
    /// every ref that NAMES a known routine/method symbol (kind IN procedure,
    /// function, method, constructor, destructor) AND that the resolver did NOT
    /// pin to a single certain target: either it has a call_edges row with
    /// confidence='ambiguous', or it has NO call_edges row at all (untypable
    /// receiver). Confidence on the returned TResolvedCaller is 'ambiguous' or
    /// 'unverified' respectively. Optionally scoped to AQName<>'' (the calling
    /// routine's qualified name) or AFilePath<>'' (refs in that file); pass both
    /// '' for the whole-DB coverage view. Location is file-name-only;
    /// EnclosingQName is '' when the ref has no enclosing routine.</summary>
    function GetAmbiguousCalls(const AQName, AFilePath: string): TArray<TResolvedCaller>;
  end;

  TParseResult = record
    Symbols    : TArray<TSymbol>   ;
    References : TArray<TReference>;
    Chunks     : TArray<TChunk>    ;
    Diagnostics: TArray<string>    ;
    // v0.40.4: uses-clause entries captured per file. Section disambiguates
    // interface vs implementation vs program/package; FileId is filled by
    // the indexer post-parse from the files table.
    UsesEntries: TArray<TUnitUse>     ;
    DiBindings : TArray<TDiBindingRow>; // v8: Spring4D DI registrations
    Literals   : TArray<TStringLiteral>; // v10: indexed string content (text search)
  end;

  IParser = interface
    ['{8C45D5A2-1B6E-4C2D-A3E8-9F0E7B41E612}']
    function LanguageName: string                                               ;
    function FileExtensions: TArray<string>                                     ;
    function Parse(const ASource: TBytes; const AFilePath: string): TParseResult;
  end;

  IIndexer = interface
    ['{2D8E7AC5-0F33-4B19-B25A-83C176D8EE7C}']
    procedure IndexFolder(const APath: string; ARecursive: Boolean = True);
    procedure IndexFile(const AFilePath: string);
    function SkippedUpToDate: Integer;
    // v0.42: register a directory whose subtree must NOT be scanned (used for
    // cross-dictionary dedup -- e.g. exclude folders already covered by the
    // library or active-project indexes). Repeatable.
    procedure AddExcludeRoot(const APath: string);
    /// <summary>Apply glob-based file/dir filtering to subsequent IndexFolder
    /// calls. Must be called before the first IndexFolder; has no effect on
    /// IndexFile. SqlOnlyMS defaults to True if never called.</summary>
    /// <param name="AFilter">Filter settings; caller may leave unused fields
    /// at their zero-value defaults.</param>
    procedure SetWalkFilter(const AFilter: TWalkFilter);
    /// <summary>PP-Task-9: enable/disable the in-process compiler-directive
    /// preprocessor for subsequent IndexFile/IndexFolder calls, and set the
    /// active define profile. When enabled, each file's UTF-8 bytes are passed
    /// through Preprocess(bytes, AProfile) before parsing, so inactive
    /// conditional branches (per config) are blanked and the parser sees only
    /// the live branch. Offsets stay 1:1 (blanking preserves byte length), so
    /// symbol/ref spans map back to the original file with no remapping. A
    /// per-file preprocess exception falls back to the RAW UTF-8 for that file
    /// (logged once). Must be called before the first IndexFile/IndexFolder to
    /// take effect for that run.</summary>
    /// <param name="AEnabled">True enables preprocessing (default indexing
    /// path); False reverts to the prior raw all-branch behaviour.</param>
    /// <param name="AProfile">The active define profile (platform built-ins or
    /// a .dproj-derived config); ignored when AEnabled is False.</param>
    procedure SetPreprocess(AEnabled: Boolean; const AProfile: TDefineProfile);
  end;

  ILinter = interface
    ['{F1C7E8D6-9A24-4F08-B7D2-46AC0E532D89}']
    function Run(const ARuleId: string = ''): TArray<TLintFinding>;
  end;

  IQueryEngine = interface
    ['{4A30E1B9-8F25-46D7-BCE1-2D5B97A4C4E0}']
    function FindCallers  (const ASymbolName: string): TArray<TReference>;
    function FindOverrides(const ASymbolName: string): TArray<TSymbol   >;
    function FindByName(const AName: string; AFuzzy: Boolean = False): TArray<TSymbol>;
  end;

implementation

class function TWalkFilter.Create: TWalkFilter;
begin
  Result:= Default(TWalkFilter);
  Result.SqlOnlyMS:= True;
  Result.MaxFileKB:= 2048;
end;

end.
