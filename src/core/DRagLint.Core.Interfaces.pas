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
  /// <remarks>
  /// Use TWalkFilter.Create to obtain the safe default (SqlOnlyMS=True,
  /// all other fields empty/False). A bare Default(TWalkFilter) zero-inits the
  /// record and leaves SqlOnlyMS=False, which indexes every .sql file --
  /// callers must not rely on Default(TWalkFilter) for the safe default.
  /// <!-- drag-lint:auto BEGIN -->
  /// Used by: DRagLint.CLI.DoIndex (DRagLint.CLI.pas), DRagLint.CLI.DoSelfTestRecreate (DRagLint.CLI.pas), declaration (DRagLint.Core.Indexer.pas), DRagLint.Core.Indexer.TIndexer.Create/3 (DRagLint.Core.Indexer.pas), DRagLint.Core.Indexer.TIndexer.SetWalkFilter (DRagLint.Core.Indexer.pas) (+3 more)
  /// Used in units: DRagLint.CLI, DRagLint.Core.Indexer, DRagLint.Core.Interfaces, DRagLint.Index.Plan
  /// <!-- drag-lint:auto END -->
  /// </remarks>
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
    /// <returns><!-- drag-lint:auto -->Observed: Default(TWalkFilter).</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.CLI.DoIndex (DRagLint.CLI.pas), DRagLint.CLI.DoSelfTestRecreate (DRagLint.CLI.pas), DRagLint.Core.Indexer.TIndexer.Create/3 (DRagLint.Core.Indexer.pas), DRagLint.Index.Plan.BuildFilter (DRagLint.Index.Plan.pas)
    /// Calls: Default
    /// Pure
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function Create: TWalkFilter; static;
  end; // record

  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// Used by: DRagLint.CLI.OpenExtraStores (DRagLint.CLI.pas), declaration (DRagLint.CLI.pas), DRagLint.CLI.BuildPlanItem (DRagLint.CLI.pas), DRagLint.CLI.OpenLibraryStores (DRagLint.CLI.pas), DRagLint.CLI.DoIndex (DRagLint.CLI.pas) (+150 more)
  /// Used in units: DRagLint.CLI, DRagLint.Context.Bundler, DRagLint.Convert.Apply, DRagLint.Convert.PropTree, DRagLint.Core.Indexer, DRagLint.Diagnostics.AstChecks, DRagLint.Diagnostics.CompileCheck, DRagLint.Diagnostics.FlowChecks, DRagLint.Diagnostics.NamingChecks, DRagLint.Doc.Batch (+25 more)
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  ISymbolStore = interface
    ['{6B9F8AC4-3F19-4E1A-9D38-1A2C3B7EF501}']
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.CLI.BuildPlanItem (DRagLint.CLI.pas), DRagLint.CLI.DoBenchContext (DRagLint.CLI.pas), DRagLint.CLI.DoCheckAst (DRagLint.CLI.pas), DRagLint.CLI.DoCheckUnit (DRagLint.CLI.pas), DRagLint.CLI.DoCompileCheck (DRagLint.CLI.pas) (+28 more)
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearAllFiles"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCallEdges"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindings"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindingsForFile"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.CommitFileTx"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure Migrate;
    // v0.86 Task 4: read-only, no-DDL schema-version probe. AFound receives the
    // DB's stored schema_version (0 when absent); AExpected receives the engine's
    // SCHEMA_VERSION. Returns AFound >= AExpected. Read verbs call this after a
    // read-only open to emit the actionable stale-schema message instead of
    // running a query against a pre-current schema.
    /// <summary><!-- drag-lint:auto -->v0.86 Task 4: read-only, no-DDL schema-version
    /// probe. AFound receives the DB's stored schema_version (0 when absent); AExpected
    /// receives the engine's SCHEMA_VERSION. Returns AFound &gt;= AExpected. Read verbs
    /// call this after a read-only open to emit the actionable stale-schema message
    /// instead of running a query against a pre-current schema.</summary>
    /// <param name="AFound"><!-- drag-lint:auto type -->out Integer</param>
    /// <param name="AExpected"><!-- drag-lint:auto type -->out Integer</param>
    /// <returns><!-- drag-lint:auto type -->Boolean</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.CLI.IndexerFingerprint (DRagLint.CLI.pas)
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearAllFiles"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCallEdges"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindings"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindingsForFile"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.CommitFileTx"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function IsSchemaCurrent(out AFound, AExpected: Integer): Boolean;
    // v0.4: returns True if this file is already indexed at exactly this
    // mtime AND sha256 - so the indexer can skip re-parsing it.
    /// <summary><!-- drag-lint:auto -->v0.4: returns True if this file is already indexed
    /// at exactly this mtime AND sha256 - so the indexer can skip re-parsing it.</summary>
    /// <param name="APath"><!-- drag-lint:auto type -->const string</param>
    /// <param name="AMtimeUnix"><!-- drag-lint:auto type -->Int64</param>
    /// <param name="ASha"><!-- drag-lint:auto type -->const string</param>
    /// <returns><!-- drag-lint:auto type -->Boolean</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.Convert.Apply.CheckTypeFreshness (DRagLint.Convert.Apply.pas), DRagLint.Core.Indexer.TIndexer.IndexFile (DRagLint.Core.Indexer.pas)
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearAllFiles"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCallEdges"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindings"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindingsForFile"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.CommitFileTx"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function FileIsUpToDate(const APath: string; AMtimeUnix: Int64; const ASha: string): Boolean                          ;
    // INBOX 2.2/2.3 (converter-editor team, 2026-08-02): read/write an arbitrary
    // schema_meta key. Used to carry the INDEXER FINGERPRINT -- see
    // TIndexer.ForceReparse -- so an engine upgrade can invalidate an otherwise
    // byte-identical file. '' when the key (or the table) is absent.
    /// <summary><!-- drag-lint:auto -->INBOX 2.2/2.3 (converter-editor team, 2026-08-02):
    /// read/write an arbitrary schema_meta key. Used to carry the INDEXER FINGERPRINT --
    /// see TIndexer.ForceReparse -- so an engine upgrade can invalidate an otherwise
    /// byte-identical file. '' when the key (or the table) is absent.</summary>
    /// <param name="AKey"><!-- drag-lint:auto type -->const string</param>
    /// <returns><!-- drag-lint:auto type -->string</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.CLI.ApplyIndexerFingerprint (DRagLint.CLI.pas)
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearAllFiles"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCallEdges"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindings"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindingsForFile"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.CommitFileTx"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function GetMetaValue(const AKey: string): string                                                                     ;
    /// <param name="AKey"><!-- drag-lint:auto type -->const string</param>
    /// <param name="AValue"><!-- drag-lint:auto type -->const string</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.CLI.ApplyIndexerFingerprint (DRagLint.CLI.pas)
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearAllFiles"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCallEdges"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindings"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindingsForFile"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.CommitFileTx"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure SetMetaValue(const AKey, AValue: string)                                                                    ;
    /// <param name="APath"><!-- drag-lint:auto type -->const string</param>
    /// <param name="AMtimeUnix"><!-- drag-lint:auto type -->Int64</param>
    /// <param name="ASha"><!-- drag-lint:auto type -->const string</param>
    /// <param name="ALanguage"><!-- drag-lint:auto type -->const string</param>
    /// <returns><!-- drag-lint:auto type -->TFileTxToken</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.Core.Indexer.TIndexer.IndexFile (DRagLint.Core.Indexer.pas)
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearAllFiles"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCallEdges"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindings"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindingsForFile"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.CommitFileTx"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function OpenFileTx(const APath: string; AMtimeUnix: Int64; const ASha: string; const ALanguage: string): TFileTxToken;
    /// <param name="AToken"><!-- drag-lint:auto type -->const TFileTxToken</param>
    /// <param name="ASymbol"><!-- drag-lint:auto type -->const TSymbol</param>
    /// <returns><!-- drag-lint:auto type -->Int64</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.Core.Indexer.TIndexer.IndexFile (DRagLint.Core.Indexer.pas)
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearAllFiles"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCallEdges"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindings"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindingsForFile"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.CommitFileTx"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function UpsertSymbol(const AToken: TFileTxToken; const ASymbol: TSymbol): Int64                                      ;
    /// <param name="AToken"><!-- drag-lint:auto type -->const TFileTxToken</param>
    /// <param name="ARef"><!-- drag-lint:auto type -->const TReference</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.Core.Indexer.TIndexer.IndexFile (DRagLint.Core.Indexer.pas)
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearAllFiles"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCallEdges"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindings"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindingsForFile"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.CommitFileTx"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure UpsertReference(const AToken: TFileTxToken; const ARef  : TReference);
    procedure UpsertChunk    (const AToken: TFileTxToken; const AChunk: TChunk    );
    /// <param name="AToken"><!-- drag-lint:auto type -->const TFileTxToken</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.Core.Indexer.TIndexer.IndexFile (DRagLint.Core.Indexer.pas)
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearAllFiles"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCallEdges"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindings"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindingsForFile"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.CountCallEdges"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure CommitFileTx  (const AToken: TFileTxToken);
    /// <param name="AToken"><!-- drag-lint:auto type -->const TFileTxToken</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.Core.Indexer.TIndexer.IndexFile (DRagLint.Core.Indexer.pas)
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearAllFiles"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCallEdges"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindings"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindingsForFile"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.CommitFileTx"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure RollbackFileTx(const AToken: TFileTxToken);

    /// <param name="AName"><!-- drag-lint:auto type -->const string</param>
    /// <returns><!-- drag-lint:auto type -->TArray&lt;TSymbol&gt;</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.CLI.DoCycles (DRagLint.CLI.pas), DRagLint.CLI.DoDocFactsSelfTest (DRagLint.CLI.pas), DRagLint.CLI.DoQuery (DRagLint.CLI.pas), DRagLint.CLI.DoResolveUses (DRagLint.CLI.pas), DRagLint.CLI.DoUsages (DRagLint.CLI.pas) (+26 more)
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearAllFiles"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCallEdges"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindings"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindingsForFile"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.CommitFileTx"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function FindSymbolsByExactName    (const AName : string): TArray<TSymbol>;
    /// <summary>Every symbol whose qualified_name equals <paramref name="AQName"/>
    /// exactly. A qualified name is NOT unique, so this routinely returns several
    /// rows.</summary>
    /// <param name="AQName"><!-- drag-lint:auto type -->const string</param>
    /// <returns>Rows ordered: a real declaration before a forward-declaration
    /// stub (class/interface, empty heritage, end_line &lt;= start_line -- the same
    /// predicate ResolveTypeNameToClass's IsStub and PropTree's
    /// IsForwardDeclClass apply after the fact), then a row carrying an
    /// implementation body, then file_id/start_line/id. Empty array when the name
    /// is not indexed.</returns>
    /// <remarks>
    /// The order is TOTAL -- id is unique, so no two rows can tie and one
    /// database always answers the same Result[0]. NOT guaranteed stable across a
    /// REBUILD: file_id and id are reassigned when the index is rebuilt, so two
    /// rows separated only by those can swap. It also does NOT decide which of two
    /// duplicate full definitions in two different files is the RIGHT one -- only
    /// which one comes first. Callers needing the right one must disambiguate by
    /// scope themselves.
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.CLI.DoDocumentStripQName (DRagLint.CLI.pas), DRagLint.CLI.DoFindCallees (DRagLint.CLI.pas), DRagLint.CLI.DoHover (DRagLint.CLI.pas), DRagLint.CLI.DoQuery (DRagLint.CLI.pas), DRagLint.CLI.DoSurface (DRagLint.CLI.pas) (+12 more)
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearAllFiles"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCallEdges"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindings"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindingsForFile"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.CommitFileTx"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function FindSymbolsByQualifiedName(const AQName: string): TArray<TSymbol>;
    // v0.42: file outline - every symbol declared in one file, ordered by
    // position. Backs the Structure form (was mis-using class-scoped surface).
    /// <summary><!-- drag-lint:auto -->v0.42: file outline - every symbol declared in one
    /// file, ordered by position. Backs the Structure form (was mis-using class-scoped
    /// surface).</summary>
    /// <param name="APath"><!-- drag-lint:auto type -->const string</param>
    /// <returns><!-- drag-lint:auto type -->TArray&lt;TSymbol&gt;</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.CLI.DoDocumentStripQName (DRagLint.CLI.pas), DRagLint.CLI.DoOutline (DRagLint.CLI.pas), DRagLint.Convert.Apply.BuildApplyPlan (DRagLint.Convert.Apply.pas), DRagLint.Doc.Batch.TDocBatch.DocumentUnit (DRagLint.Doc.Batch.pas), DRagLint.Doc.Document.TDocumenter.BuildForSymbol (DRagLint.Doc.Document.pas) (+11 more)
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearAllFiles"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCallEdges"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindings"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindingsForFile"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.CommitFileTx"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function FindSymbolsByFile(const APath: string): TArray<TSymbol>                       ;
    /// <param name="ASymbolId"><!-- drag-lint:auto type -->Int64</param>
    /// <returns><!-- drag-lint:auto type -->TArray&lt;TReference&gt;</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.Lint.ProjectRules.TProjectLintRules.Run (DRagLint.Lint.ProjectRules.pas)
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearAllFiles"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCallEdges"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindings"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindingsForFile"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.CommitFileTx"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function FindReferencesTo(ASymbolId: Int64): TArray<TReference>                        ;
    /// <param name="ACalleeName"><!-- drag-lint:auto type -->const string</param>
    /// <returns><!-- drag-lint:auto type -->TArray&lt;TReference&gt;</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.CLI.DoQuery (DRagLint.CLI.pas), DRagLint.CLI.DoUsages (DRagLint.CLI.pas), DRagLint.Doc.Facts.TDocFactsBuilder.Build (DRagLint.Doc.Facts.pas), DRagLint.Lint.ProjectRules.TProjectLintRules.Run (DRagLint.Lint.ProjectRules.pas), DRagLint.MCP.Server.TMCPServer.HandleToolsCall (DRagLint.MCP.Server.pas) (+2 more)
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearAllFiles"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCallEdges"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindings"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindingsForFile"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.CommitFileTx"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function FindCallersByName(const ACalleeName: string): TArray<TReference>              ;
    /// <summary>Every symbol id that appears as the target of at least one reference.</summary>
    /// <returns>Distinct non-zero refs.symbol_id values; empty if the index has no refs.</returns>
    /// <remarks>The set form of FindReferencesTo for callers that only ask "is this
    /// referenced AT ALL?" of many symbols. One scan answers the question for every
    /// symbol, where the per-symbol call costs one query each.</remarks>
    function GetReferencedSymbolIds: TArray<Int64>                                         ;
    /// <summary>Every distinct reference name in the index, lowercased.</summary>
    /// <returns>Distinct LowerCase(refs.name_text); empty if the index has no refs.</returns>
    /// <remarks>The set form of FindCallersByName, for the same reason. Lowercased
    /// because the query it replaces matches COLLATE NOCASE, and both that collation
    /// and Delphi's default LowerCase fold ASCII only -- so a lookup on
    /// LowerCase(Name) accepts exactly the rows the query would have returned.
    /// refs.name_text carries NO index, so FindCallersByName is a full table scan
    /// EVERY call: replacing N of those with one scan is the whole point.</remarks>
    function GetReferencedNamesLower: TArray<string>                                       ;
    /// <summary>True if this index could contain a test routine at all -- a
    /// once-per-run precondition for the per-symbol "Covered by:" walk.</summary>
    /// <returns>False only when NO file path contains 'Test' AND no recorded type
    /// ancestor is named 'TTestCase'. False is a PROOF that
    /// DRagLint.Doc.SymbolFacts.IsTestRoutine cannot return True for any symbol.</returns>
    /// <remarks>Deliberately a SUPERSET of the real test: it matches 'Test' anywhere
    /// in the path, not just in the file's base name, so it can only ever be too
    /// permissive. A gate that over-answers True costs one wasted walk; one that
    /// under-answers False would silently drop a real fact.
    /// Same shape as GetReferencedSymbolIds/GetReferencedNamesLower above -- a
    /// question asked once per run instead of once per symbol. Implementations
    /// MUST cache the answer per store: callers invoke it once per declaration
    /// and neither underlying column is indexed.</remarks>
    function HasTestRoutineMarkers: Boolean                                                ;
    /// <param name="APattern"><!-- drag-lint:auto type -->const string</param>
    /// <param name="ATopK"><!-- drag-lint:auto type -->Integer = 10</param>
    /// <returns><!-- drag-lint:auto type -->TArray&lt;TSymbol&gt;</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.CLI.DoQuery (DRagLint.CLI.pas), DRagLint.LSP.Server.TLSPServer.HandleWorkspaceSymbol (DRagLint.LSP.Server.pas), DRagLint.MCP.Server.TMCPServer.HandleToolsCall (DRagLint.MCP.Server.pas)
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearAllFiles"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCallEdges"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindings"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindingsForFile"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.CommitFileTx"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function FindSymbolsFuzzy(const APattern: string; ATopK: Integer = 10): TArray<TSymbol>;
    /// <param name="AFileId"><!-- drag-lint:auto type -->Int64</param>
    /// <returns><!-- drag-lint:auto type -->string</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.CLI.DoBenchContext (DRagLint.CLI.pas), DRagLint.CLI.DoCycles (DRagLint.CLI.pas), DRagLint.CLI.DoDocumentStripQName (DRagLint.CLI.pas), DRagLint.CLI.DoHelpersOf (DRagLint.CLI.pas), DRagLint.CLI.DoHover (DRagLint.CLI.pas) (+58 more)
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearAllFiles"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCallEdges"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindings"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindingsForFile"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.CommitFileTx"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function GetFilePath(AFileId: Int64): string                                           ;
    /// <returns><!-- drag-lint:auto type -->TArray&lt;Int64&gt;</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.CLI.DoCycles (DRagLint.CLI.pas), DRagLint.CLI.DoLintAll (DRagLint.CLI.pas), DRagLint.CLI.DoLintProject (DRagLint.CLI.pas), DRagLint.CLI.DoSelfTestFiles (DRagLint.CLI.pas), DRagLint.CLI.DoTestStoreFreshness (DRagLint.CLI.pas) (+12 more)
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearAllFiles"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCallEdges"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindings"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindingsForFile"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.CommitFileTx"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function GetAllFileIds: TArray<Int64>                                                  ; { v0.43: for cycles / cross-file scans }
    /// <param name="AFileId"><!-- drag-lint:auto type -->Int64</param>
    /// <returns><!-- drag-lint:auto type -->TArray&lt;TReference&gt;</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.CLI.DoCycles (DRagLint.CLI.pas), DRagLint.CLI.DoDumpRefs (DRagLint.CLI.pas), DRagLint.CLI.DoUsesAudit (DRagLint.CLI.pas), DRagLint.CLI.DoUsesFix (DRagLint.CLI.pas), DRagLint.CLI.DoUsesFixSweep (DRagLint.CLI.pas) (+4 more)
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearAllFiles"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCallEdges"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindings"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindingsForFile"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.CommitFileTx"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function GetReferencesFromFile(AFileId: Int64): TArray<TReference>                     ; { v0.43: uses-audit }
    /// <returns><!-- drag-lint:auto type -->Int64</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.CLI.BuildPlanItem (DRagLint.CLI.pas), DRagLint.CLI.DoIndex (DRagLint.CLI.pas), DRagLint.CLI.DoSelfTestRecreate (DRagLint.CLI.pas), DRagLint.CLI.IndexDictionary (DRagLint.CLI.pas)
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearAllFiles"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCallEdges"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindings"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindingsForFile"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.CommitFileTx"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function CountSymbols   : Int64;
    /// <returns><!-- drag-lint:auto type -->Int64</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.CLI.DoIndex (DRagLint.CLI.pas), DRagLint.CLI.IndexDictionary (DRagLint.CLI.pas)
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearAllFiles"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCallEdges"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindings"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindingsForFile"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.CommitFileTx"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function CountReferences: Int64;
    /// <returns><!-- drag-lint:auto type -->Int64</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.CLI.BuildPlanItem (DRagLint.CLI.pas), DRagLint.CLI.DoIndex (DRagLint.CLI.pas), DRagLint.CLI.IndexDictionary (DRagLint.CLI.pas)
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearAllFiles"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCallEdges"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindings"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindingsForFile"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.CommitFileTx"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function CountFiles     : Int64;

    /// <summary>Deletes every indexed file whose path lies under one of ARoots
    /// and NO LONGER EXISTS on disk, together with everything that hangs off it
    /// (symbols, refs, uses, docs, DI bindings, string literals, ...).</summary>
    /// <param name="ARoots">The roots just walked. A file outside all of them is
    /// left alone no matter what: indexing one subfolder must never purge the
    /// rest of the DB. An empty array prunes NOTHING.</param>
    /// <param name="ADryRun">True COMPUTES the sweep and deletes NOTHING: the
    /// same paths come back, the index is left exactly as it was. This is what
    /// makes `--no-prune` a preview rather than a silent no-op -- a caller about
    /// to sweep a multi-gigabyte corpus can see the list first.</param>
    /// <returns>The paths removed -- or, under ADryRun, the paths that WOULD be
    /// removed -- in the order encountered; empty if none.</returns>
    /// <remarks>
    /// An incremental walk adds new files and refreshes changed ones but
    /// has no notion of a file that went away, so rows for deleted/moved/renamed
    /// source outlive it and keep feeding the linter -- findings get reported
    /// against paths that do not exist, and the totals used to judge a cleanup are
    /// wrong. "Does not exist on disk" is the only deletion predicate; a file that
    /// is merely out of the walk's filter is never touched.
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.CLI.DoIndex (DRagLint.CLI.pas)
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearAllFiles"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCallEdges"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindings"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindingsForFile"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.CommitFileTx"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function PruneMissingFiles(const ARoots: TArray<string>; ADryRun: Boolean = False): TArray<string>;

    /// <summary>Deletes every indexed file whose path lies under one of ARoots
    /// and is NOT named in AInScopeAbsPaths, together with everything that hangs
    /// off it (symbols, refs, uses, docs, DI bindings, string literals and their
    /// FTS5 shadow rows).</summary>
    /// <param name="ARoots">The roots this run walked. A file outside all of
    /// them is left alone whatever the scope says: indexing one project must
    /// never purge another's rows from a shared DB. An empty array evicts
    /// NOTHING.</param>
    /// <param name="AInScopeAbsPaths">Every file the run considers in scope --
    /// for a PROJECT scan the expanded compile closure, for a LIBRARY scan the
    /// files the walk admitted after its excludes and ignore rules. Absolute
    /// paths; matched case-insensitively on the same canonical spelling as
    /// files.path. An EMPTY array evicts NOTHING (see remarks).</param>
    /// <param name="ADryRun">True COMPUTES the sweep and deletes NOTHING: the
    /// same paths come back, the index is left exactly as it was. `--no-prune`
    /// passes it, which is what turns that flag from a silent no-op into the
    /// preview the CLI help promises -- eviction over the shared Library
    /// corpora is otherwise unreviewable before the fact.</param>
    /// <returns>The paths removed -- or, under ADryRun, the paths that WOULD be
    /// removed -- in the order encountered; empty if none.</returns>
    /// <exception cref="EDatabaseError">Raised when the delete cannot be applied
    /// (a read-only or locked DB). The sweep is one transaction, so the index is
    /// left exactly as it was.</exception>
    /// <remarks>
    /// The counterpart to PruneMissingFiles, and the one it cannot
    /// stand in for: prune deletes a file that has left the DISK, this deletes a
    /// file that still EXISTS and has left the SCOPE. Nothing did that before,
    /// so a unit dropped from a .dproj, an archive copy under an ignored folder,
    /// or a tree a newly added `exclude` glob now covers kept answering queries
    /// forever -- from source the project does not compile. Measured: the YADF
    /// index carried 5 `.private\` copies and 104 files from a sibling repo
    /// through every reindex, and one stale archived copy of a single unit
    /// accounted for 157 of 321 apparently-unresolved call refs.
    /// AN EMPTY IN-SCOPE SET EVICTS NOTHING, deliberately. "The walk admitted no
    /// file" is far more often a mistyped root, an unreadable directory or a
    /// half-failed run than a genuine "everything left scope", and the cost of
    /// the two readings is not symmetric: guessing wrong here empties a corpus.
    /// A caller that really means "drop everything" has ClearAllFiles.
    /// Call it AFTER the walk and BEFORE the resolve passes, the ordering
    /// PruneMissingFiles uses, so unit_uses.target_file_id and the ancestry /
    /// helper / call edges are recomputed against the survivors instead of being
    /// left pointing at rows that just went away.
    /// Not thread-safe; call on the indexing thread with no walk in flight.
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.CLI.BuildPlanItem (DRagLint.CLI.pas), DRagLint.CLI.DoIndex (DRagLint.CLI.pas)
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearAllFiles"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCallEdges"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindings"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindingsForFile"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.CommitFileTx"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function EvictOutOfScopeFiles(const ARoots, AInScopeAbsPaths: TArray<string>;
      ADryRun: Boolean = False): TArray<string>;

    /// <summary>Deletes EVERY row in `files` and everything that hangs off it
    /// (symbols, refs, uses, docs, DI bindings, string literals and their FTS5
    /// shadow rows, ...), leaving an index that holds no source at all.</summary>
    /// <returns>The number of `files` rows removed; 0 when the DB was already
    /// empty.</returns>
    /// <exception cref="EDatabaseError">Raised when the delete cannot be
    /// applied (a read-only or locked DB). The caller must NOT then proceed to
    /// index: a half-cleared DB is worse than either mode.</exception>
    /// <remarks>
    /// The MODE axis of indexing: `--rebuild` calls this before the
    /// walk so the run starts from nothing, which is the only way a file that
    /// has LEFT the scope (as opposed to left the disk -- that is
    /// PruneMissingFiles) can be got rid of.
    /// ROWS, NOT THE FILE. Deleting the .sqlite would be simpler and is wrong
    /// twice over: the schema, its applied migrations and any settings stored
    /// beside them would go with it, and the file handle would be dropped
    /// underneath whoever else has the DB open -- the IDE design-time plugin
    /// holds one for the whole session.
    /// Tables that do not descend from `files` (the fb_* Firebird metadata
    /// snapshot, orm_links, schema_meta/meta) are NOT touched: they were not
    /// produced by a source walk, so a source rebuild has no business
    /// discarding them.
    /// Not thread-safe; call on the indexing thread with no walk in flight.
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.CLI.BuildPlanItem (DRagLint.CLI.pas), DRagLint.CLI.DoIndex (DRagLint.CLI.pas)
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCallEdges"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindings"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindingsForFile"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.CommitFileTx"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.CountCallEdges"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function ClearAllFiles: Integer;

    // v0.17: blast-radius pack
    /// <summary><!-- drag-lint:auto -->v0.17: blast-radius pack</summary>
    /// <param name="ASymbolName"><!-- drag-lint:auto type -->const string</param>
    /// <param name="ADepth"><!-- drag-lint:auto type -->Integer</param>
    /// <returns><!-- drag-lint:auto type -->TArray&lt;TImpactLevel&gt;</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.CLI.DoImpact (DRagLint.CLI.pas), DRagLint.CLI.DoUsages (DRagLint.CLI.pas), DRagLint.Context.Bundler.TContextBundler.Build (DRagLint.Context.Bundler.pas)
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearAllFiles"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCallEdges"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindings"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindingsForFile"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.CommitFileTx"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function FindTransitiveCallers(const ASymbolName: string; ADepth: Integer): TArray<TImpactLevel>            ;
    /// <param name="AQName"><!-- drag-lint:auto type -->const string</param>
    /// <param name="AIncludeImpl"><!-- drag-lint:auto type -->Boolean</param>
    /// <param name="AAllVisibility"><!-- drag-lint:auto type -->Boolean</param>
    /// <returns><!-- drag-lint:auto type -->TArray&lt;TSurfaceLine&gt;</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.CLI.DoSurface (DRagLint.CLI.pas), DRagLint.Context.Bundler.TContextBundler.Build (DRagLint.Context.Bundler.pas)
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearAllFiles"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCallEdges"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindings"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindingsForFile"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.CommitFileTx"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function GetClassSurface(const AQName: string; AIncludeImpl, AAllVisibility: Boolean): TArray<TSurfaceLine> ;
    /// <param name="AQName"><!-- drag-lint:auto type -->const string</param>
    /// <returns><!-- drag-lint:auto type -->TArray&lt;TSliceChunk&gt;</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.CLI.DoSlice (DRagLint.CLI.pas), DRagLint.Context.Bundler.TContextBundler.Build (DRagLint.Context.Bundler.pas)
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearAllFiles"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCallEdges"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindings"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindingsForFile"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.CommitFileTx"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function GetSymbolSlice(const AQName: string): TArray<TSliceChunk>                                          ;
    /// <param name="ACalleeName"><!-- drag-lint:auto type -->const string</param>
    /// <param name="AContextLines"><!-- drag-lint:auto type -->Integer</param>
    /// <returns><!-- drag-lint:auto type -->TArray&lt;TReference&gt;</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.CLI.DoQuery (DRagLint.CLI.pas), DRagLint.Context.Bundler.TContextBundler.Build (DRagLint.Context.Bundler.pas), DRagLint.MCP.Server.TMCPServer.HandleToolsCall (DRagLint.MCP.Server.pas)
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearAllFiles"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCallEdges"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindings"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindingsForFile"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.CommitFileTx"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function FindCallersByNameWithContext(const ACalleeName: string; AContextLines: Integer): TArray<TReference>;

    /// <param name="AToken"><!-- drag-lint:auto type -->const TFileTxToken</param>
    /// <param name="ASymbolId"><!-- drag-lint:auto type -->Int64</param>
    /// <param name="ADoc"><!-- drag-lint:auto type -->const TParsedDoc</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.Core.Indexer.TIndexer.IndexFile (DRagLint.Core.Indexer.pas)
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearAllFiles"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCallEdges"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindings"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindingsForFile"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.CommitFileTx"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure UpsertSymbolDoc(const AToken: TFileTxToken; ASymbolId: Int64; const ADoc: TParsedDoc);
    /// <param name="ASymbolId"><!-- drag-lint:auto type -->Int64</param>
    /// <returns><!-- drag-lint:auto type -->TParsedDoc</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.CLI.DoHover (DRagLint.CLI.pas), DRagLint.Context.Bundler.TContextBundler.Build (DRagLint.Context.Bundler.pas), DRagLint.LSP.Completion.TLspCompletion.MakeCompletionItem (DRagLint.LSP.Completion.pas)
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearAllFiles"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCallEdges"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindings"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindingsForFile"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.CommitFileTx"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function GetSymbolDoc(ASymbolId: Int64): TParsedDoc;

    // v0.40.4: uses-clause persistence + queries.
    /// <summary><!-- drag-lint:auto -->v0.40.4: uses-clause persistence + queries.</summary>
    /// <param name="AToken"><!-- drag-lint:auto type -->const TFileTxToken</param>
    /// <param name="AUse"><!-- drag-lint:auto type -->const TUnitUse</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.Core.Indexer.TIndexer.IndexFile (DRagLint.Core.Indexer.pas)
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearAllFiles"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCallEdges"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindings"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindingsForFile"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.CommitFileTx"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure UpsertUnitUse(const AToken: TFileTxToken; const AUse: TUnitUse);
    /// <param name="AFileId"><!-- drag-lint:auto type -->Int64</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.Core.Indexer.TIndexer.IndexFile (DRagLint.Core.Indexer.pas)
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearAllFiles"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCallEdges"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindings"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindingsForFile"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.CommitFileTx"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure DeleteUnitUsesForFile(AFileId: Int64);
    /// <param name="AFileId"><!-- drag-lint:auto type -->Int64</param>
    /// <returns><!-- drag-lint:auto type -->TArray&lt;TUnitUse&gt;</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.CLI.DoCycles (DRagLint.CLI.pas), DRagLint.CLI.DoResolveUses (DRagLint.CLI.pas), DRagLint.CLI.DoUsesAudit (DRagLint.CLI.pas), DRagLint.CLI.DoUsesFix (DRagLint.CLI.pas), DRagLint.CLI.DoUsesFixSweep (DRagLint.CLI.pas) (+7 more)
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearAllFiles"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCallEdges"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindings"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindingsForFile"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.CommitFileTx"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function GetUnitUsesForFile(AFileId: Int64): TArray<TUnitUse>          ;
    function FindUsersOfUnit(const AUnitNameNorm: string): TArray<TUnitUse>;
    /// <summary>Whole-DB post-index pass: RECOMPUTES unit_uses.target_file_id
    /// for every row, from the used unit's name and the set of indexed file
    /// names. Idempotent.</summary>
    /// <remarks>
    /// Two rules, in order: (A) the used unit's name equals a file's
    /// lowercased basename stem ('Vcl.Controls' -&gt; Vcl.Controls.pas); or
    /// (B) for a BARE name only, exactly one indexed stem carries that name as
    /// its last dotted segment AND that stem is not in a GUI framework
    /// namespace ('Grids' -&gt; Data.Grids.pas -- Delphi's unit scope names).
    /// Anything else is left NULL.
    /// CLEARS THE COLUMN FIRST, so it REPAIRS a stale or wrong value instead of
    /// only filling gaps -- an incremental re-index that does not re-parse a
    /// file would otherwise preserve that file's old targets forever. Runs in
    /// one transaction, so a failure rolls back to the previous values. Any
    /// caller holding a target_file_id across this call must re-read it.
    /// GUARANTEES that rule B never resolves a row to a Vcl.* or FMX.* file
    /// (criterion 5, structural -- not a property of what happens to be
    /// indexed). Rule A is a name equality the unit itself stated and is
    /// deliberately not restricted that way.
    /// GUARANTEES that a resolved target is a <c>.pas</c> file, and NOTHING
    /// beyond that: any other extension is excluded (.dfm, .dpr, .dpk and .inc
    /// among them) before a stem is computed. The test is case-insensitive, so an
    /// uppercase <c>.PAS</c> path is still a candidate.
    /// It is an EXTENSION test and no more. It does NOT guarantee that the target
    /// declares a unit at all, let alone a unit of that name: a .pas holding only
    /// a <c>program</c> or <c>library</c> header, an include-style fragment
    /// named .pas, or one the parser failed on all satisfy it.
    /// GUARANTEES ONLY that some indexed .pas is named after the used unit --
    /// NOT that it is the file the compiler would have picked. Two indexed
    /// copies of one unit collide on a stem and an arbitrary one wins.
    /// ANCESTOR RESOLUTION DOES NOT READ THIS COLUMN (ResolveAncestry scopes
    /// textually), so an index predating this pass is not thereby wrong about
    /// ancestry. ResolveHelpers, the call resolver and the deps report do read
    /// it.
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.CLI.BuildPlanItem (DRagLint.CLI.pas), DRagLint.CLI.DoIndex (DRagLint.CLI.pas), DRagLint.CLI.DoReconcileProject (DRagLint.CLI.pas), DRagLint.CLI.IndexDictionary (DRagLint.CLI.pas)
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearAllFiles"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCallEdges"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindings"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindingsForFile"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.CommitFileTx"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure ResolveUnitUseTargets;
    // v11 (M1): type & hierarchy resolution. ResolveAncestry is a whole-DB
    // post-index pass (run after ResolveUnitUseTargets) that splits each
    // class/interface's `heritage` text, resolves each ancestor to a defining
    // symbol in the scope of the declaring unit -- textually, by the shared
    // rule PickAncestorCandidateByScope, so it needs no resolved uses graph --
    // and writes type_ancestors edges. An ancestor it cannot disambiguate is
    // written unresolved (ancestor_kind '?'), never guessed.
    /// <summary><!-- drag-lint:auto -->v11 (M1): type &amp; hierarchy resolution.
    /// ResolveAncestry is a whole-DB post-index pass (run after ResolveUnitUseTargets)
    /// that splits each class/interface's `heritage` text, resolves each ancestor to a
    /// defining symbol in the scope of the declaring unit -- textually, by the shared
    /// rule PickAncestorCandidateByScope, so it needs no resolved uses graph -- and
    /// writes type_ancestors edges. An ancestor it cannot disambiguate is written
    /// unresolved (ancestor_kind '?'), never guessed.</summary>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.CLI.BuildPlanItem (DRagLint.CLI.pas), DRagLint.CLI.DoIndex (DRagLint.CLI.pas), DRagLint.CLI.DoReconcileProject (DRagLint.CLI.pas), DRagLint.CLI.IndexDictionary (DRagLint.CLI.pas)
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearAllFiles"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCallEdges"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindings"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindingsForFile"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.CommitFileTx"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure ResolveAncestry;
    /// <summary>v15: whole-DB helper-resolution pass (run after ResolveAncestry).
    /// Links each record/class helper's target type name to its defining symbol,
    /// resolving cross-unit via the units-in-scope graph. Committed to
    /// type_helpers table.</summary>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.CLI.BuildPlanItem (DRagLint.CLI.pas), DRagLint.CLI.DoIndex (DRagLint.CLI.pas), DRagLint.CLI.DoReconcileProject (DRagLint.CLI.pas), DRagLint.CLI.IndexDictionary (DRagLint.CLI.pas)
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearAllFiles"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCallEdges"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindings"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindingsForFile"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.CommitFileTx"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure ResolveHelpers;
    /// <summary>v14 (D5): whole-DB call-resolution pass (run after ResolveAncestry,
    /// which it depends on for the ancestor chain). Wipes call_edges, then types
    /// the receiver of every 'call' ref and writes a resolved edge (target symbol +
    /// 'certain'|'ambiguous' confidence) for each site it can resolve; unresolved
    /// sites get no row (FP-conservative). Rebuilds all edges each run.</summary>
    /// <param name="AExtraStores">v21: other open indexes -- the platform
    /// LIBRARY db in practice -- consulted ONLY for calls this index cannot
    /// resolve. A hit is recorded as a qualified NAME on refs.external_target,
    /// never as a call_edges row, because target_symbol_id is a NOT NULL FK
    /// into THIS db. Empty (the default) keeps the pre-v21 behaviour exactly.</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.CLI.BuildPlanItem (DRagLint.CLI.pas), DRagLint.CLI.DoIndex (DRagLint.CLI.pas), DRagLint.CLI.DoReconcileProject (DRagLint.CLI.pas), DRagLint.CLI.IndexDictionary (DRagLint.CLI.pas)
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearAllFiles"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCallEdges"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindings"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindingsForFile"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.CommitFileTx"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure ResolveCallTargets(const AExtraStores: TArray<ISymbolStore> = nil);
    /// <summary>True when call_edges holds no rows although the index does hold
    /// call-site refs -- i.e. the edge set is missing rather than genuinely
    /// empty.</summary>
    /// <returns>True for a pre-D5 index, one whose call_edges a schema migration
    /// just recreated, or one an interrupted pass emptied. False for a healthy
    /// index and for a corpus with no call sites at all.</returns>
    /// <remarks>Callers that skip ResolveCallTargets because nothing changed ON
    /// DISK must consult this first: "no file changed" only implies "every edge
    /// still holds" if the edges were there to begin with. Without it such a
    /// database stays broken across every future reindex, and
    /// `find-callers --resolved` answers nothing without erroring.
    /// Errs towards True -- rebuilding costs time, not correctness.</remarks>
    function CallEdgesNeedRebuild: Boolean;
    /// <summary>Transitive ancestor closure of the symbol (resolved edges are
    /// walked recursively; unresolved ones are name-only leaves). Cycle-safe,
    /// hop-capped.</summary>
    /// <param name="ASymbolId"><!-- drag-lint:auto type -->Int64</param>
    /// <returns><!-- drag-lint:auto type -->TArray&lt;TTypeAncestor&gt;</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.CLI.DoQuery (DRagLint.CLI.pas), DRagLint.Doc.Facts.TDocFactsBuilder.Build (DRagLint.Doc.Facts.pas), DRagLint.Doc.SymbolFacts.IsTestRoutine (DRagLint.Doc.SymbolFacts.pas), DRagLint.Index.CallResolver.TCallResolver.LookupMethodOnType (DRagLint.Index.CallResolver.pas), DRagLint.Resolver.TypeAt.ResolveMemberOnType (DRagLint.Resolver.TypeAt.pas) (+10 more)
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearAllFiles"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCallEdges"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindings"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindingsForFile"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.CommitFileTx"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function GetTransitiveAncestors(ASymbolId: Int64): TArray<TTypeAncestor>;
    /// <summary>True when class/interface AClassName (resolved in-scope of
    /// AFileId) has AAncestorName anywhere in its transitive ancestor closure.</summary>
    /// <param name="AClassName"><!-- drag-lint:auto type -->const string</param>
    /// <param name="AAncestorName"><!-- drag-lint:auto type -->const string</param>
    /// <param name="AFileId"><!-- drag-lint:auto type -->Int64</param>
    /// <returns><!-- drag-lint:auto type -->Boolean</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.CLI.DoQuery (DRagLint.CLI.pas), DRagLint.Diagnostics.FlowChecks.ConstructorTransfersOwnership (DRagLint.Diagnostics.FlowChecks.pas), DRagLint.Refactor.NamingFix.BuildNamingFixEdits (DRagLint.Refactor.NamingFix.pas), DRagLint.Diagnostics.NamingChecks.TNamingChecker.Check.Visit (DRagLint.Diagnostics.NamingChecks.pas) ?
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearAllFiles"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCallEdges"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindings"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindingsForFile"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.CommitFileTx"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function IsDescendantOf(const AClassName, AAncestorName: string; AFileId: Int64): Boolean;
    /// <summary>Every class whose transitive ancestor set includes AAncestorName
    /// (the reverse of IsDescendantOf). Distinct class names, sorted. Backed by a
    /// single indexed lookup on type_ancestors.ancestor_name.</summary>
    /// <param name="AAncestorName"><!-- drag-lint:auto type -->const string</param>
    /// <returns><!-- drag-lint:auto type -->TArray&lt;string&gt;</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.CLI.DoQuery (DRagLint.CLI.pas), DRagLint.Doc.Facts.TDocFactsBuilder.Build (DRagLint.Doc.Facts.pas), DRagLint.Convert.PropTree.BuildPropTree.ClosureClassIds (DRagLint.Convert.PropTree.pas) ?
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearAllFiles"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCallEdges"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindings"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindingsForFile"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.CommitFileTx"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function FindDescendantNames(const AAncestorName: string): TArray<string>;
    /// <summary>True when AClassName's transitive closure reaches AInterfaceName
    /// via an interface-kind edge (i.e. AClassName implements that interface).</summary>
    /// <param name="AClassName"><!-- drag-lint:auto type -->const string</param>
    /// <param name="AInterfaceName"><!-- drag-lint:auto type -->const string</param>
    /// <param name="AFileId"><!-- drag-lint:auto type -->Int64</param>
    /// <returns><!-- drag-lint:auto type -->Boolean</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.CLI.DoQuery (DRagLint.CLI.pas)
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearAllFiles"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCallEdges"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindings"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindingsForFile"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.CommitFileTx"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function ImplementsInterface(const AClassName, AInterfaceName: string; AFileId: Int64): Boolean;
    /// <summary>Resolve a type name to its broad category: intrinsics by name
    /// first, then a declared class/interface/enum/record symbol's kind, chasing
    /// `type X = Y` aliases to a fixpoint. AFileId disambiguates same-named types
    /// (prefer the one declared in that file). tcUnknown when unresolvable.</summary>
    /// <param name="ATypeName"><!-- drag-lint:auto type -->const string</param>
    /// <param name="AFileId"><!-- drag-lint:auto type -->Int64</param>
    /// <returns><!-- drag-lint:auto type -->TTypeCategory</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.CLI.DoQuery (DRagLint.CLI.pas), DRagLint.Diagnostics.FlowChecks.IsInterfaceType (DRagLint.Diagnostics.FlowChecks.pas), DRagLint.Diagnostics.FlowChecks.IsManagedType (DRagLint.Diagnostics.FlowChecks.pas), DRagLint.Diagnostics.AstChecks.TAstChecker.CheckTypeAware.CatOf (DRagLint.Diagnostics.AstChecks.pas) ?, DRagLint.Lint.ClassMetrics.TClassMetrics.Run.ResolveParents (DRagLint.Lint.ClassMetrics.pas) ? (+2 more)
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearAllFiles"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCallEdges"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindings"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindingsForFile"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.CommitFileTx"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function ResolveTypeCategory(const ATypeName: string; AFileId: Int64): TTypeCategory;
    /// <summary>Lowercased names of every virtually-dispatched method visible on
    /// AClassName -- its own virtuals plus those inherited from resolved ancestors
    /// (cross-unit). Backs cross-unit virtual-method-in-constructor.</summary>
    /// <param name="AClassName"><!-- drag-lint:auto type -->const string</param>
    /// <param name="AFileId"><!-- drag-lint:auto type -->Int64</param>
    /// <returns><!-- drag-lint:auto type -->TArray&lt;string&gt;</returns>
    function GetVirtualMethodsIncludingAncestors(const AClassName: string; AFileId: Int64): TArray<string>;
    /// <summary>v15: all helpers (record/class) whose target type name matches
    /// ATargetName (whole-DB). Empty when no helper targets that type.
    /// NAME-ONLY match: two unrelated same-named types in different units
    /// (e.g. two distinct `TColor` enums) are indistinguishable to this call
    /// -- prefer FindHelpersOfTypeSymbol when the candidate's own symbol id
    /// is known, to avoid cross-linking unrelated same-named types.</summary>
    /// <param name="ATargetName"><!-- drag-lint:auto type -->const string</param>
    /// <returns><!-- drag-lint:auto type -->TArray&lt;THelperEdge&gt;</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.CLI.DoHelpersOf (DRagLint.CLI.pas)
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearAllFiles"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCallEdges"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindings"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindingsForFile"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.CommitFileTx"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
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
    /// <param name="ATargetSymbolId"><!-- drag-lint:auto type -->Int64</param>
    /// <returns><!-- drag-lint:auto type -->TArray&lt;THelperEdge&gt;</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.Lint.ProjectRules.CollectEnumHelperSeparateUnits (DRagLint.Lint.ProjectRules.pas), DRagLint.Refactor.EnumHelper.TEnumHelperRefactoring.Resolve (DRagLint.Refactor.EnumHelper.pas)
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearAllFiles"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCallEdges"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindings"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindingsForFile"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.CommitFileTx"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function FindHelpersOfTypeSymbol(ATargetSymbolId: Int64): TArray<THelperEdge>;
    /// <param name="ATag"><!-- drag-lint:auto type -->const string</param>
    /// <returns><!-- drag-lint:auto type -->TArray&lt;TSymbol&gt;</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.CLI.DoQueryFind (DRagLint.CLI.pas)
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearAllFiles"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCallEdges"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindings"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindingsForFile"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.CommitFileTx"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function FindByDocTag(const ATag: string): TArray<TSymbol>                           ;
    /// <param name="AKind"><!-- drag-lint:auto type -->const string</param>
    /// <param name="APublicOnly"><!-- drag-lint:auto type -->Boolean</param>
    /// <returns><!-- drag-lint:auto type -->TArray&lt;TSymbol&gt;</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.CLI.DoQueryFind (DRagLint.CLI.pas), DRagLint.Lint.DocRules.TDocLintRules.RunMissingDoc (DRagLint.Lint.DocRules.pas)
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearAllFiles"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCallEdges"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindings"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindingsForFile"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.CommitFileTx"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function FindUndocumented(const AKind: string; APublicOnly: Boolean): TArray<TSymbol>;
    /// <param name="ASubstring"><!-- drag-lint:auto type -->const string</param>
    /// <returns><!-- drag-lint:auto type -->TArray&lt;TSymbol&gt;</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.CLI.DoQueryFind (DRagLint.CLI.pas)
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearAllFiles"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCallEdges"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindings"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindingsForFile"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.CommitFileTx"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function FindByDocContains(const ASubstring: string): TArray<TSymbol>                ;
    /// <param name="AFileId"><!-- drag-lint:auto type -->Int64</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.Core.Indexer.TIndexer.IndexFile (DRagLint.Core.Indexer.pas)
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearAllFiles"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCallEdges"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindings"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindingsForFile"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.CommitFileTx"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure DeleteFileDocs(AFileId: Int64);

    // v0.18: bench-context. v(ADP3 T3d, register D4): "documented" here means
    // "has a symbol_docs row", the exact complement of FindUndocumented -- NOT
    // the old "has a non-null summary", which silently excluded a comment made
    // only of <remarks>/<param>/<returns>/<example>/<seealso>/<since> and left
    // it reported by NEITHER missing-doc nor doc-drift.
    /// <summary><!-- drag-lint:auto -->v0.18: bench-context. v(ADP3 T3d, register D4):
    /// "documented" here means "has a symbol_docs row", the exact complement of
    /// FindUndocumented -- NOT the old "has a non-null summary", which silently excluded
    /// a comment made only of
    /// &lt;remarks&gt;/&lt;param&gt;/&lt;returns&gt;/&lt;example&gt;/&lt;seealso&gt;/&lt;since&gt;
    /// and left it reported by NEITHER missing-doc nor doc-drift.</summary>
    /// <param name="ALimit"><!-- drag-lint:auto type -->Integer</param>
    /// <returns><!-- drag-lint:auto type -->TArray&lt;TSymbol&gt;</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.CLI.DoBenchContext (DRagLint.CLI.pas), DRagLint.Lint.DocRules.DocumentedPublicDecls (DRagLint.Lint.DocRules.pas)
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearAllFiles"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCallEdges"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindings"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindingsForFile"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.CommitFileTx"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function ListDocumentedSymbols(ALimit: Integer): TArray<TSymbol>;

    // v0.19: type-at-position helpers
    /// <summary><!-- drag-lint:auto -->v0.19: type-at-position helpers</summary>
    /// <param name="AFileId"><!-- drag-lint:auto type -->Int64</param>
    /// <param name="ALine"><!-- drag-lint:auto type -->Integer</param>
    /// <returns><!-- drag-lint:auto type -->TSymbol</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.Core.Indexer.TIndexer.IndexFile (DRagLint.Core.Indexer.pas), DRagLint.Resolver.TypeAt.TTypeAtResolver.Resolve/4 (DRagLint.Resolver.TypeAt.pas)
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearAllFiles"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCallEdges"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindings"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindingsForFile"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.CommitFileTx"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function FindContainingSymbol(AFileId: Int64; ALine: Integer): TSymbol        ;
    /// <param name="AId"><!-- drag-lint:auto type -->Int64</param>
    /// <returns><!-- drag-lint:auto type -->TSymbol</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.CLI.BuildCallGraphJson (DRagLint.CLI.pas), DRagLint.CLI.DoCallPath (DRagLint.CLI.pas), DRagLint.CLI.DoDumpCallEdges (DRagLint.CLI.pas), DRagLint.CLI.DoDumpRefs (DRagLint.CLI.pas), DRagLint.CLI.DoFindCallees (DRagLint.CLI.pas) (+20 more)
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearAllFiles"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCallEdges"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindings"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindingsForFile"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.CommitFileTx"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function GetSymbolById(AId: Int64): TSymbol                                   ;
    /// <param name="APath"><!-- drag-lint:auto type -->const string</param>
    /// <returns><!-- drag-lint:auto type -->Int64</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.CLI.DoCheckAst (DRagLint.CLI.pas), DRagLint.CLI.DoDumpRefs (DRagLint.CLI.pas), DRagLint.CLI.DoLintAll (DRagLint.CLI.pas), DRagLint.CLI.DoResolveUses (DRagLint.CLI.pas), DRagLint.CLI.RefreshProjectFindingsCore (DRagLint.CLI.pas) (+8 more)
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearAllFiles"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCallEdges"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindings"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindingsForFile"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.CommitFileTx"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function FindFileIdByPath             (const APath: string): Int64;
    function FindSymbolByExactNameAnywhere(const AName: string): TSymbol;
    /// <param name="AParentId"><!-- drag-lint:auto type -->Int64</param>
    /// <param name="AName"><!-- drag-lint:auto type -->const string</param>
    /// <returns><!-- drag-lint:auto type -->TSymbol</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.Doc.Facts.TDocFactsBuilder.Build (DRagLint.Doc.Facts.pas), DRagLint.Refactor.Rename.TRenameRefactoring.ConflictReason (DRagLint.Refactor.Rename.pas), DRagLint.Resolver.TypeAt.ResolveMemberOnType (DRagLint.Resolver.TypeAt.pas), DRagLint.Resolver.TypeAt.TTypeAtResolver.Resolve/4 (DRagLint.Resolver.TypeAt.pas), DRagLint.Convert.PropTree.BuildPropTree.ResolveInheritedType (DRagLint.Convert.PropTree.pas) ? (+4 more)
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearAllFiles"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCallEdges"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindings"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindingsForFile"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.CommitFileTx"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function FindChildSymbolByName(AParentId: Int64; const AName: string): TSymbol;
    /// <summary>Resolve a type NAME to its defining class/interface/record symbol
    /// AS SEEN FROM AScopeFileId, FOLLOWING type-alias chains (type X = Y) to the
    /// underlying declared type. Mirrors ResolveAncestry's resolution policy -- a
    /// unique in-scope candidate wins, else a single global definition -- but adds
    /// two things ResolveAncestry cannot: (a) it accepts a type-alias candidate and
    /// chases it to the real class (ResolveAncestry's candidate set is
    /// class/interface only, so an alias ancestor such as
    /// 'cxButtons.TcxBaseButton = Vcl.StdCtrls.TCustomButton' is left unresolved),
    /// and (b) scope is matched by the reference file's uses-clause UNIT NAMES
    /// (textual, resolved or not) against each candidate's unit-qualified prefix, so
    /// two same-named types in different frameworks (e.g. Vcl.StdCtrls.TCustomButton
    /// vs FMX.StdCtrls.TCustomButton) are disambiguated even when the uses target
    /// file never resolved. Forward-declaration stubs are dropped when a real body
    /// exists. Returns a class/interface/record symbol (Id&gt;0) or Default (Id=0)
    /// when it cannot be resolved unambiguously (no worse than an unresolved edge).
    /// Cross-unit safe; the alias chain is cycle-guarded and hop-capped.</summary>
    /// <param name="ATypeName">Bare type name to resolve (e.g. 'TCustomButton').</param>
    /// <param name="AScopeFileId">File whose uses-clause disambiguates same-named
    /// candidates; 0 disables scope preference (single-global fallback only).</param>
    /// <returns><!-- drag-lint:auto type -->TSymbol</returns>
    function ResolveTypeNameToClass(const ATypeName: string; AScopeFileId: Int64): TSymbol;
    /// <summary>Memoize a resolved property type by writing ': '+ATypeName as the
    /// signature of property symbol ASymbolId (which previously carried an
    /// empty/typeless signature -- a bare inherited redeclaration such as
    /// 'property Align;'). Lets a later proptree/type query read the type as a plain
    /// hit instead of re-walking (and re-bridging) the ancestry every time.
    /// No-op returning False on a read-only (query_only) handle, when ASymbolId&lt;=0,
    /// when ATypeName is blank, or when the row is not a property. Idempotent: once
    /// written, ParseTypeToken(signature) yields a type so the resolver never
    /// recomputes it. Best-effort: a write failure is swallowed (returns False) so a
    /// query never fails merely because the index could not be updated.</summary>
    /// <param name="ASymbolId"><!-- drag-lint:auto type -->Int64</param>
    /// <param name="ATypeName"><!-- drag-lint:auto type -->const string</param>
    /// <returns>True when exactly one property row was updated; False otherwise.</returns>
    /// <remarks>Not thread-safe; call from the owning thread on a writable store.</remarks>
    function MemoizePropertyType(ASymbolId: Int64; const ATypeName: string): Boolean;
    /// <summary>The innermost routine (procedure/function/method/constructor/
    /// destructor) whose IMPLEMENTATION BODY span (impl_start_line..impl_end_line)
    /// contains ALine in AFileId. Empty (Id=0) when the line is in no routine body.
    /// Unlike FindContainingSymbol (which matches the DECLARATION span), this finds
    /// the routine you are standing INSIDE -- needed to scope a bare identifier to
    /// that routine's params/locals.</summary>
    /// <param name="AFileId"><!-- drag-lint:auto type -->Int64</param>
    /// <param name="ALine"><!-- drag-lint:auto type -->Integer</param>
    /// <returns><!-- drag-lint:auto type -->TSymbol</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.Resolver.TypeAt.TTypeAtResolver.Resolve/4 (DRagLint.Resolver.TypeAt.pas)
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearAllFiles"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCallEdges"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindings"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindingsForFile"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.CommitFileTx"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function FindEnclosingRoutineByImpl(AFileId: Int64; ALine: Integer): TSymbol;

    // v0.20: completion helpers
    /// <summary><!-- drag-lint:auto -->v0.20: completion helpers</summary>
    /// <param name="APrefix"><!-- drag-lint:auto type -->const string</param>
    /// <param name="ALimit"><!-- drag-lint:auto type -->Integer</param>
    /// <returns><!-- drag-lint:auto type -->TArray&lt;TSymbol&gt;</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.LSP.Completion.TLspCompletion.BuildCompletionItems (DRagLint.LSP.Completion.pas)
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearAllFiles"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCallEdges"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindings"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindingsForFile"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.CommitFileTx"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function FindSymbolsByPrefix(const APrefix: string; ALimit: Integer): TArray<TSymbol>;
    /// <param name="AParentId"><!-- drag-lint:auto type -->Int64</param>
    /// <returns><!-- drag-lint:auto type -->TArray&lt;TSymbol&gt;</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.CLI.DoSurface (DRagLint.CLI.pas), DRagLint.Convert.Apply.GetConstructorNames (DRagLint.Convert.Apply.pas), DRagLint.Convert.Apply.ToTypeHasGenericCreate (DRagLint.Convert.Apply.pas), DRagLint.Doc.Facts.OverloadArityTag (DRagLint.Doc.Facts.pas), DRagLint.Doc.Facts.TDocFactsBuilder.Build (DRagLint.Doc.Facts.pas) (+14 more)
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearAllFiles"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCallEdges"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindings"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindingsForFile"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.CommitFileTx"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function FindAllChildSymbols(AParentId: Int64): TArray<TSymbol>                      ;

    // v0.25: dead-code finder
    /// <summary><!-- drag-lint:auto -->v0.25: dead-code finder</summary>
    /// <param name="AKind"><!-- drag-lint:auto type -->const string</param>
    /// <param name="AIncludePrivate"><!-- drag-lint:auto type -->Boolean</param>
    /// <returns><!-- drag-lint:auto type -->TArray&lt;TSymbol&gt;</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.Refactor.DeadCode.TDeadCodeFinder.Find (DRagLint.Refactor.DeadCode.pas)
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearAllFiles"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCallEdges"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindings"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindingsForFile"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.CommitFileTx"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function FindSymbolsWithNoCallers(const AKind: string; AIncludePrivate: Boolean): TArray<TSymbol>;

    // v0.26: compiler diagnostics
    /// <summary><!-- drag-lint:auto -->v0.26: compiler diagnostics</summary>
    /// <param name="AFileId"><!-- drag-lint:auto type -->Int64</param>
    /// <returns><!-- drag-lint:auto type -->TArray&lt;TCompilerFinding&gt;</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.CLI.DoTestStoreFreshness (DRagLint.CLI.pas), DRagLint.LSP.Completion.TLspCompletion.BuildDiagnostics (DRagLint.LSP.Completion.pas)
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearAllFiles"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCallEdges"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindings"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindingsForFile"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.CommitFileTx"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function FindCompilerFindingsForFile(AFileId: Int64): TArray<TCompilerFinding>;
    procedure ClearCompilerFindings;
    /// <param name="AFinding"><!-- drag-lint:auto type -->const TCompilerFinding</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.CLI.DoTestStoreFreshness (DRagLint.CLI.pas), DRagLint.CLI.RefreshProjectFindingsCore (DRagLint.CLI.pas), DRagLint.Diagnostics.CompileCheck.TCompileChecker.InsertFindings (DRagLint.Diagnostics.CompileCheck.pas)
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearAllFiles"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCallEdges"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindings"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindingsForFile"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.CommitFileTx"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure InsertCompilerFinding(const AFinding: TCompilerFinding);
    /// <summary>Deletes only the compiler_findings rows for one file, so a
    /// single-unit recompile can replace that file's findings without touching
    /// others. (Whole-DB ClearCompilerFindings is unchanged.)</summary>
    /// <param name="AFileId"><!-- drag-lint:auto type -->Int64</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.CLI.DoTestStoreFreshness (DRagLint.CLI.pas), DRagLint.CLI.RefreshProjectFindingsCore (DRagLint.CLI.pas)
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearAllFiles"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCallEdges"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindings"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.CommitFileTx"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.CountCallEdges"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure ClearCompilerFindingsForFile(AFileId: Int64);
    /// <summary>Stamps files.last_compiled_unix for one file (Unix seconds).</summary>
    /// <param name="AFileId"><!-- drag-lint:auto type -->Int64</param>
    /// <param name="AUnix"><!-- drag-lint:auto type -->Int64</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.CLI.DoTestStoreFreshness (DRagLint.CLI.pas), DRagLint.CLI.RefreshProjectFindingsCore (DRagLint.CLI.pas)
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearAllFiles"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCallEdges"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindings"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindingsForFile"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.CommitFileTx"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure SetFileCompiledAt(AFileId: Int64; AUnix: Int64);
    /// <summary>Returns files.last_compiled_unix for one file, or 0 when NULL.</summary>
    /// <param name="AFileId"><!-- drag-lint:auto type -->Int64</param>
    /// <returns><!-- drag-lint:auto type -->Int64</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.CLI.DoTestStoreFreshness (DRagLint.CLI.pas), DRagLint.Project.Coherence.ComputeCoherence (DRagLint.Project.Coherence.pas)
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearAllFiles"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCallEdges"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindings"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindingsForFile"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.CommitFileTx"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function GetFileCompiledAt(AFileId: Int64): Int64;
    /// <summary>Returns files.mtime_unix for one file, or 0 when NULL/absent.</summary>
    /// <param name="AFileId"><!-- drag-lint:auto type -->Int64</param>
    /// <returns><!-- drag-lint:auto type -->Int64</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.Project.Coherence.ComputeCoherence (DRagLint.Project.Coherence.pas)
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearAllFiles"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCallEdges"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindings"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindingsForFile"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.CommitFileTx"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function GetFileMTime(AFileId: Int64): Int64;
    /// <summary>Returns file_ids whose findings are STALE: last_compiled_unix is
    /// NULL or older than mtime_unix. Pascal source files only.</summary>
    /// <returns><!-- drag-lint:auto type -->TArray&lt;Int64&gt;</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.CLI.DoRefreshFindings (DRagLint.CLI.pas), DRagLint.CLI.DoTestStoreFreshness (DRagLint.CLI.pas)
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearAllFiles"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCallEdges"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindings"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindingsForFile"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.CommitFileTx"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function GetStaleFileIds: TArray<Int64>;

    // v8: Spring4D DI edges.
    /// <summary><!-- drag-lint:auto -->v8: Spring4D DI edges.</summary>
    /// <param name="AToken"><!-- drag-lint:auto type -->const TFileTxToken</param>
    /// <param name="ABinding"><!-- drag-lint:auto type -->const TDiBindingRow</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.Core.Indexer.TIndexer.IndexFile (DRagLint.Core.Indexer.pas)
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearAllFiles"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCallEdges"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindings"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindingsForFile"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.CommitFileTx"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure UpsertDiBinding(const AToken: TFileTxToken; const ABinding: TDiBindingRow);
    procedure DeleteDiBindingsForFile(AFileId: Int64);
    /// <param name="AInterfaceName"><!-- drag-lint:auto type -->const string</param>
    /// <returns><!-- drag-lint:auto type -->TArray&lt;TDiBindingRow&gt;</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.CLI.DoWiring (DRagLint.CLI.pas), DRagLint.Wiring.BuildWiringJson (DRagLint.Wiring.pas)
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearAllFiles"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCallEdges"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindings"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindingsForFile"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.CommitFileTx"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function FindImplementationsOf( const AInterfaceName: string): TArray<TDiBindingRow>;
    /// <summary>v(ADP3 T14): the DI registrations whose IMPL type is AImplName,
    /// i.e. the reverse of FindImplementationsOf. Answers "what is this class
    /// registered as, and with what lifetime" for the doc/hover
    /// 'Registered as:' line. Empty when the class is not registered.</summary>
    /// <param name="AImplName"><!-- drag-lint:auto type -->const string</param>
    /// <returns><!-- drag-lint:auto type -->TArray&lt;TDiBindingRow&gt;</returns>
    /// <remarks>
    /// Matched case-insensitively on impl_name, which idx_di_impl
    /// already indexes. Ordered by file_id then start_line so a class
    /// registered more than once renders in a stable order.
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.Doc.SymbolFacts.ComputeWiring (DRagLint.Doc.SymbolFacts.pas)
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearAllFiles"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCallEdges"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindings"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindingsForFile"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.CommitFileTx"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function FindDiBindingsForImpl(const AImplName: string): TArray<TDiBindingRow>;
    /// <summary>v(ADP3 T14): the Firebird relations the orm-link pass tied to
    /// ASymbolId, each with up to AMaxColumns leading columns in declaration
    /// order. Empty when the symbol has no orm_links row, which is the normal
    /// case for any index the orm-link pass has not been run against.</summary>
    /// <param name="ASymbolId">The Delphi symbol (orm_links.delphi_symbol_id).</param>
    /// <param name="AMaxColumns">Column cap per relation; the row is
    /// display-ready, so the cap lives here rather than in the renderer.</param>
    /// <returns><!-- drag-lint:auto type -->TArray&lt;TOrmDatasetLink&gt;</returns>
    function FindOrmDatasetLinks(ASymbolId: Int64; AMaxColumns: Integer = 4): TArray<TOrmDatasetLink>;
    /// <param name="AInterfaceName"><!-- drag-lint:auto type -->const string</param>
    /// <returns><!-- drag-lint:auto type -->TArray&lt;TReference &gt;</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.CLI.DoWiring (DRagLint.CLI.pas), DRagLint.Wiring.BuildWiringJson (DRagLint.Wiring.pas)
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearAllFiles"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCallEdges"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindings"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindingsForFile"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.CommitFileTx"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function FindDiResolveSites   ( const AInterfaceName: string): TArray<TReference   >;
    /// <returns><!-- drag-lint:auto type -->TArray&lt;TReference&gt;</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.CLI.DoWiring (DRagLint.CLI.pas)
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearAllFiles"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCallEdges"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindings"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindingsForFile"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.CommitFileTx"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function FindDiUnresolved: TArray<TReference>                                       ;
    /// <summary>DFM event handlers of a form/class: its child methods bound to a
    /// component event (kind='event-binding'). NameText is the handler method;
    /// FileId/StartLine point at the .dfm OnXxx line.</summary>
    /// <param name="AFormName"><!-- drag-lint:auto type -->const string</param>
    /// <returns><!-- drag-lint:auto type -->TArray&lt;TReference&gt;</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.CLI.DoWiring (DRagLint.CLI.pas), DRagLint.Wiring.BuildWiringJson (DRagLint.Wiring.pas)
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearAllFiles"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCallEdges"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindings"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindingsForFile"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.CommitFileTx"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function FindEventHandlersForForm( const AFormName: string): TArray<TReference>;

    // v10: string-content (text) index.
    /// <summary>Insert one string-literal occurrence into the text index for
    /// the file identified by AToken. AToken.FileId must already exist.</summary>
    /// <param name="AToken"><!-- drag-lint:auto type -->const TFileTxToken</param>
    /// <param name="ALit"><!-- drag-lint:auto type -->const TStringLiteral</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.Core.Indexer.TIndexer.IndexFile (DRagLint.Core.Indexer.pas)
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearAllFiles"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCallEdges"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindings"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindingsForFile"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.CommitFileTx"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure UpsertStringLiteral(const AToken: TFileTxToken; const ALit: TStringLiteral);
    /// <summary>Remove all string-literal rows (and their FTS entries) for the
    /// given file. Call before re-indexing a file to avoid duplicates.</summary>
    /// <param name="AFileId"><!-- drag-lint:auto type -->Int64</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.Core.Indexer.TIndexer.IndexFile (DRagLint.Core.Indexer.pas)
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearAllFiles"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCallEdges"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindings"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindingsForFile"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.CommitFileTx"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure DeleteStringLiteralsForFile(AFileId: Int64);
    /// <summary>Full-text search over indexed string literals. AMode selects the
    /// FTS strategy: 'phrase' (default, exact order), 'anyorder' (all words any
    /// order), 'substring' (trigram-based). ASource filters by source language
    /// ('pas'|'dfm'|'sql'); '' = all. Returns up to ALimit hits.</summary>
    /// <param name="AQuery"><!-- drag-lint:auto type -->const string</param>
    /// <param name="AMode"><!-- drag-lint:auto type -->string</param>
    /// <param name="ASource"><!-- drag-lint:auto type -->const string</param>
    /// <param name="ALimit"><!-- drag-lint:auto type -->Integer</param>
    /// <returns><!-- drag-lint:auto type -->TArray&lt;TStringLitMatch&gt;</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.CLI.DoQueryText (DRagLint.CLI.pas)
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearAllFiles"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCallEdges"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindings"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindingsForFile"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.CommitFileTx"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function SearchText(const AQuery: string; AMode: string; const ASource: string; ALimit: Integer): TArray<TStringLitMatch>;

    // v14 (D5): resolved call-target edges (call_edges table).
    /// <summary>Insert or replace the resolved call edge for one ref (ref_id is
    /// the natural key -- a ref resolves to at most one target). NULLs
    /// ReceiverTypeSymbolId when it is &lt;= 0 (unknown receiver type).</summary>
    /// <param name="AToken"><!-- drag-lint:auto type -->const TFileTxToken</param>
    /// <param name="AEdge"><!-- drag-lint:auto type -->const TCallEdge</param>
    procedure UpsertCallEdge(const AToken: TFileTxToken; const AEdge: TCallEdge);
    /// <summary>Wipes the entire call_edges table. Called once at the start of
    /// the whole-DB ResolveCallTargets pass, which then rebuilds every edge.</summary>
    procedure ClearCallEdges;
    /// <summary>The Called-from query: every resolved caller of ATargetSymbolId,
    /// most-confident first. Backs the AutoDocument Called-from facts block.</summary>
    /// <param name="ATargetSymbolId"><!-- drag-lint:auto type -->Int64</param>
    /// <returns><!-- drag-lint:auto type -->TArray&lt;TResolvedCaller&gt;</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.CLI.BuildCallGraphJson (DRagLint.CLI.pas), DRagLint.CLI.DoQuery (DRagLint.CLI.pas), DRagLint.CLI.RenderCallGraphText (DRagLint.CLI.pas), DRagLint.Doc.Facts.TDocFactsBuilder.Build (DRagLint.Doc.Facts.pas), DRagLint.Doc.SymbolFacts.ComputeCoveredBy.Walk (DRagLint.Doc.SymbolFacts.pas) ? (+1 more)
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearAllFiles"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCallEdges"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindings"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindingsForFile"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.CommitFileTx"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function FindResolvedCallers(ATargetSymbolId: Int64): TArray<TResolvedCaller>;
    /// <summary>v14 (D5): the AutoDocument '?' bucket -- every CALL-SITE ref
    /// (kind = REF_KIND_CALL) whose name_text = AName AND that has NO call_edges
    /// row (its receiver could not be typed, so the resolver emitted no edge).
    /// Each returned TResolvedCaller carries Confidence = 'unverified' so the
    /// renderer marks it ' ?' (honest: might or might not be the documented
    /// symbol). Ordered by file path then start line to mirror
    /// FindCallersByName's first-seen ordering. Location is file-name-only
    /// (idempotency: no volatile ':line'); EnclosingQName is '' when the ref has
    /// no enclosing routine.</summary>
    /// <param name="AName"><!-- drag-lint:auto type -->const string</param>
    /// <param name="ACallSitesOnly">True (the default, and what every
    /// call-graph consumer wants) restricts the scan to CALL-SITE refs. False
    /// restores the historic kind-blind scan -- see the remarks.</param>
    /// <param name="AReachableToFileId">USES-SCOPE FILTER (INBOX-datacopy
    /// 2026-08-06 section 7). Pass the file id of the file DECLARING the symbol
    /// being asked about and only refs made from a file that can reach it
    /// through the uses graph -- itself, a direct user, or a transitive one --
    /// are returned. 0 (the default) disables the filter and restores the
    /// historic whole-DB scan. The rule it encodes is a Delphi language rule,
    /// not a heuristic: a call from unit U to a symbol declared in unit T
    /// requires T in U's uses, directly or (for an inherited member) through
    /// the unit that does. Without it a bare-name bucket attributes every
    /// unresolved <c>Create</c> in the index to every constructor in it, which
    /// is what section 7 measured -- 28 unresolved 'Create' call refs, 0
    /// call_edges rows, one Called-from list naming five routines in units that
    /// CANNOT use the target (uZeissRoutines' implementation uses uFileUtils, so
    /// uFileUtils cannot use uZeissRoutines). Only the '?' bucket is affected;
    /// resolved call_edges callers never pass through here. PASS 0 FOR AN EXTRA
    /// (cross-DB) STORE: file ids are per-DB keys, so a primary-store id names a
    /// different file -- usually none -- in another store's files table, and the
    /// reachable set would collapse to empty. See the extra-store loop in
    /// DRagLint.Doc.Facts.</param>
    /// <param name="AOwnerTypeName">v20: the LEAF NAME of the type that owns the
    /// target ('TOnlyOnce' for TOnlyOnce.Create), or '' for a free routine and
    /// for any caller that cannot supply it. Non-empty enables the RECEIVER
    /// filter: a ref is kept only when its call site was written against this
    /// type, was unqualified, or was `Self`.
    /// 
    /// '' preserves the pre-v20 behaviour exactly, so an existing caller is not
    /// silently changed by adding the parameter. Rows whose receiver_text is
    /// NULL are ALWAYS kept: NULL means the DB has never been resolved by a v20
    /// engine, and treating "not recorded" as "no receiver" would drop every
    /// genuine caller on a stale index. Reindex to make the filter effective --
    /// do not loosen the predicate, the same rule the uses-scope filter carries
    /// a few lines below.</param>
    /// <returns><!-- drag-lint:auto type -->TArray&lt;TResolvedCaller&gt;</returns>
    /// <remarks>
    /// v(ADP3 T3i review round 4): THIS DECLARATION IS THE SINGLE
    /// SOURCE for what ACallSitesOnly means and for who may pass it. The
    /// implementation's own header and block comment in
    /// DRagLint.Storage.SQLite, and the two call sites in DRagLint.Doc.Facts,
    /// POINT HERE and state no version of the contract themselves -- because
    /// three consecutive T3i review rounds each corrected one copy of this text
    /// and left another asserting the retired wording. A comment that defers to
    /// another comment while also paraphrasing it is worse than either being
    /// stale alone. If the contract changes it changes HERE, and the pointers
    /// stay pointers.
    /// <para>v(ADP3 T3i, register E1): with ACallSitesOnly the kind
    /// restriction is part of the CONTRACT, not an optimisation -- this bucket
    /// is the complement of FindResolvedCallers within the universe
    /// ResolveCallTargets walks, and that universe is call-site refs alone. A
    /// usage ref (read/write/type_use/member-access) can never own a call_edges
    /// row, so counting one here would report it as an unresolved call forever.
    /// Consequently a paren-less dotted invocation in EXPRESSION position,
    /// which today emits no call ref at all, is not reached; see the block
    /// comment above REF_KIND_CALL in DRagLint.Core.Model. Name-based discovery
    /// (FindCallersByName) is kind-blind and still finds it.</para>
    /// <para>ACallSitesOnly=False is NOT a general escape hatch. The parameter
    /// is passed EXPLICITLY at exactly TWO call sites, both in
    /// DRagLint.Doc.Facts' CalledFrom gather -- the primary store and the
    /// extra-store fan-out -- and both pass the SAME expression,
    /// <c>CanBeCallTarget(ASym.Kind)</c>, so False is reached exactly when the
    /// documented symbol is of a NON-ROUTINE kind. Every OTHER caller takes the
    /// default, including DRagLint.Doc.SymbolFacts' ComputeCoveredBy, which
    /// records that it does so deliberately. The two explicit sites must stay in
    /// step, or a symbol's fact would depend on which DB a reference happened to
    /// live in. Do not add callers.</para>
    /// <para>No kind list appears here ON PURPOSE. "Which kinds are exempt, and
    /// why" is owned by CanBeCallTarget's own header in DRagLint.Doc.Facts;
    /// every enumeration of that set written anywhere else has so far been
    /// wrong -- as a code literal in T3i review round 1, and as a five-kind
    /// paraphrase in this very block until round 4, which was narrower than the
    /// predicate because hover resolves properties, fields, locals and SQL
    /// symbols into the same branch.</para>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.Doc.Facts.TDocFactsBuilder.Build (DRagLint.Doc.Facts.pas), DRagLint.Doc.SymbolFacts.ComputeCoveredBy.Walk (DRagLint.Doc.SymbolFacts.pas) ?
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearAllFiles"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCallEdges"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindings"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindingsForFile"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.CommitFileTx"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function FindUnresolvedNameCallers(const AName: string;
      ACallSitesOnly: Boolean = True;
      AReachableToFileId: Int64 = 0;
      const AOwnerTypeName: string = ''): TArray<TResolvedCaller>;
    /// <summary>Find-callees: every call edge whose ref is enclosed by
    /// AEnclosingSymbolId (i.e. every resolved call made from inside that
    /// routine's body).</summary>
    /// <param name="AEnclosingSymbolId"><!-- drag-lint:auto type -->Int64</param>
    /// <returns><!-- drag-lint:auto type -->TArray&lt;TCallEdge&gt;</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.CLI.BuildCallGraphJson (DRagLint.CLI.pas), DRagLint.CLI.DoCallPath (DRagLint.CLI.pas), DRagLint.CLI.DoFindCallees (DRagLint.CLI.pas), DRagLint.CLI.RenderCallGraphText (DRagLint.CLI.pas), DRagLint.Doc.Facts.TDocFactsBuilder.Build (DRagLint.Doc.Facts.pas) (+1 more)
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearAllFiles"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCallEdges"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindings"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindingsForFile"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.CommitFileTx"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function GetCallEdgesFromSymbol(AEnclosingSymbolId: Int64): TArray<TCallEdge>;
    /// <summary>Total row count in call_edges. Diagnostic/test probe.</summary>
    /// <returns><!-- drag-lint:auto type -->Int64</returns>
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
    /// <remarks>
    /// Not thread-safe; call from the owning thread on a writable store.
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.CLI.DoPurgeLocals (DRagLint.CLI.pas)
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearAllFiles"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCallEdges"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindings"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindingsForFile"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.CommitFileTx"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function PurgeLocals: Int64;
    /// <summary>v14 (D5): every class/interface/record symbol (id, file_id, kind,
    /// name populated). Bulk read that backs TCallResolver's name-candidate map
    /// for receiver typing -- the same candidate set ResolveAncestry builds
    /// inline, exposed so the resolver can prepare it once.</summary>
    /// <returns><!-- drag-lint:auto type -->TArray&lt;TSymbol&gt;</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.Index.CallResolver.TCallResolver.BuildMaps (DRagLint.Index.CallResolver.pas)
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearAllFiles"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCallEdges"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindings"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindingsForFile"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.CommitFileTx"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function GetTypeCandidates: TArray<TSymbol>;
    /// <summary>v14 (D5): every resolved uses-scope edge (file_id -&gt;
    /// target_file_id) from unit_uses where the target is resolved. Backs
    /// TCallResolver's per-file in-scope set (mirrors ResolveAncestry's
    /// FileScope). Unresolved uses rows (NULL target) are excluded.</summary>
    /// <returns><!-- drag-lint:auto type -->TArray&lt;TFileScopeEdge&gt;</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.Index.CallResolver.TCallResolver.BuildMaps (DRagLint.Index.CallResolver.pas)
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearAllFiles"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCallEdges"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindings"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindingsForFile"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.CommitFileTx"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function GetUnitScopeEdges: TArray<TFileScopeEdge>;
    /// <summary>Option 4: every UNIT-LEVEL routine -- a procedure/function whose
    /// parent symbol is the unit itself (id, file_id, name, signature, section
    /// populated). Backs TCallResolver's unit-level rung for a BARE call, which
    /// is the step Delphi takes after the lexical scopes and the enclosing
    /// class's methods, and which no other candidate set covers.</summary>
    /// <returns>Empty when the index holds no unit-level routines. Methods
    /// (parent = a class/record/interface) and nested routines (parent = a
    /// routine) are excluded by construction -- those rungs belong to
    /// LookupMethodOnType and LookupInLexicalScopes respectively.</returns>
    /// <remarks>
    /// Section is load-bearing for the caller, not decoration: an
    /// implementation-section routine is reachable only from its OWN unit,
    /// while a bare call from another unit may bind only to an interface-section
    /// one. Returning both and letting the caller filter keeps that visibility
    /// rule in one place.
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.Index.CallResolver.TCallResolver.BuildMaps (DRagLint.Index.CallResolver.pas)
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearAllFiles"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCallEdges"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindings"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindingsForFile"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.CommitFileTx"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function GetUnitLevelRoutines: TArray<TSymbol>;
    /// <summary>v14 (D5): every call_edges row (ref_id, target_symbol_id,
    /// confidence, receiver_type_symbol_id), unordered. Diagnostic dump backing
    /// the dump-call-edges verb / tests; not for production queries (use
    /// FindResolvedCallers / GetCallEdgesFromSymbol for those).</summary>
    /// <returns><!-- drag-lint:auto type -->TArray&lt;TCallEdge&gt;</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.CLI.DoDumpCallEdges (DRagLint.CLI.pas)
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearAllFiles"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCallEdges"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindings"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindingsForFile"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.CommitFileTx"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function DumpAllCallEdges: TArray<TCallEdge>;
    /// <summary>v14 (D5 T9): the ambiguous-calls resolver-coverage diagnostic --
    /// every CALL-SITE ref (kind = REF_KIND_CALL, i.e. exactly what
    /// ResolveCallTargets walks -- v(ADP3 T3i), register E1) that NAMES a known
    /// routine/method symbol (kind IN procedure,
    /// function, method, constructor, destructor) AND that the resolver did NOT
    /// pin to a single certain target: either it has a call_edges row with
    /// confidence='ambiguous', or it has NO call_edges row at all (untypable
    /// receiver). Confidence on the returned TResolvedCaller is 'ambiguous' or
    /// 'unverified' respectively. Optionally scoped to AQName&lt;>'' (the calling
    /// routine's qualified name) or AFilePath&lt;>'' (refs in that file); pass both
    /// '' for the whole-DB coverage view. Location is file-name-only;
    /// EnclosingQName is '' when the ref has no enclosing routine.</summary>
    /// <param name="AQName"><!-- drag-lint:auto type -->const string</param>
    /// <param name="AFilePath"><!-- drag-lint:auto type -->const string</param>
    /// <returns><!-- drag-lint:auto type -->TArray&lt;TResolvedCaller&gt;</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.CLI.DoAmbiguousCalls (DRagLint.CLI.pas)
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearAllFiles"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCallEdges"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindings"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindingsForFile"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.CommitFileTx"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function GetAmbiguousCalls(const AQName, AFilePath: string): TArray<TResolvedCaller>;

    // v(ADP2 T1): index-time analysis facts (symbol_facts table).
    /// <summary>Reads back the analysis-facts row for ASymbolId. Present=False
    /// (all other fields zeroed) when no symbol_facts row exists for
    /// ASymbolId -- the renderer's cue to omit every derived doc-comment
    /// line.</summary>
    /// <param name="ASymbolId"><!-- drag-lint:auto type -->Int64</param>
    /// <returns><!-- drag-lint:auto type -->TSymbolFacts</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.CLI.DoDocFactsSelfTest (DRagLint.CLI.pas), DRagLint.Doc.Facts.TDocFactsBuilder.Build (DRagLint.Doc.Facts.pas)
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearAllFiles"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCallEdges"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindings"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindingsForFile"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.CommitFileTx"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function GetSymbolFacts(ASymbolId: Int64): TSymbolFacts;
    /// <summary>Inserts or replaces the analysis-facts row for
    /// AFacts.SymbolId (UPSERT keyed on symbol_id -- at most one row per
    /// symbol).</summary>
    /// <param name="AFacts"><!-- drag-lint:auto type -->const TSymbolFacts</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.CLI.DoDocFactsSelfTest (DRagLint.CLI.pas), DRagLint.Core.Indexer.TIndexer.IndexFile (DRagLint.Core.Indexer.pas)
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearAllFiles"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCallEdges"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindings"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.ClearCompilerFindingsForFile"/>
    /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.CommitFileTx"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure PutSymbolFacts(const AFacts: TSymbolFacts);
  end;

  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// Used by: DRagLint.Core.Indexer.TIndexer.IndexFile (DRagLint.Core.Indexer.pas), declaration (DRagLint.Core.Interfaces.pas), declaration (DRagLint.Parser.DFM.pas), DRagLint.Parser.DFM.TDFMParser.Parse (DRagLint.Parser.DFM.pas), declaration (DRagLint.Parser.Delphi13.pas) (+3 more)
  /// Used in units: DRagLint.Core.Indexer, DRagLint.Core.Interfaces, DRagLint.Parser.Delphi13, DRagLint.Parser.DFM, DRagLint.Parser.Sql
  /// <!-- drag-lint:auto END -->
  /// </remarks>
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

  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// Used by: DRagLint.CLI.DoIndex (DRagLint.CLI.pas), declaration (DRagLint.Core.Indexer.pas), DRagLint.Core.Indexer.TIndexer.Create/3 (DRagLint.Core.Indexer.pas), DRagLint.Core.Indexer.TIndexer.ParserFor (DRagLint.Core.Indexer.pas), DRagLint.Core.Indexer.TIndexer.IndexFile (DRagLint.Core.Indexer.pas) (+3 more)
  /// Used in units: DRagLint.CLI, DRagLint.Core.Indexer, DRagLint.Parser.Delphi13, DRagLint.Parser.DFM, DRagLint.Parser.Sql
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  IParser = interface
    ['{8C45D5A2-1B6E-4C2D-A3E8-9F0E7B41E612}']
    /// <returns><!-- drag-lint:auto type -->string</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.Core.Indexer.TIndexer.IndexFile (DRagLint.Core.Indexer.pas)
    /// <seealso cref="DRagLint.Core.Interfaces.IParser.FileExtensions"/>
    /// <seealso cref="DRagLint.Core.Interfaces.IParser.Parse"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function LanguageName: string                                               ;
    /// <returns><!-- drag-lint:auto type -->TArray&lt;string&gt;</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.Core.Indexer.TIndexer.ParserFor (DRagLint.Core.Indexer.pas)
    /// <seealso cref="DRagLint.Core.Interfaces.IParser.LanguageName"/>
    /// <seealso cref="DRagLint.Core.Interfaces.IParser.Parse"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function FileExtensions: TArray<string>                                     ;
    /// <param name="ASource"><!-- drag-lint:auto type -->const TBytes</param>
    /// <param name="AFilePath"><!-- drag-lint:auto type -->const string</param>
    /// <returns><!-- drag-lint:auto type -->TParseResult</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.Core.Indexer.TIndexer.IndexFile (DRagLint.Core.Indexer.pas)
    /// <seealso cref="DRagLint.Core.Interfaces.IParser.FileExtensions"/>
    /// <seealso cref="DRagLint.Core.Interfaces.IParser.LanguageName"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function Parse(const ASource: TBytes; const AFilePath: string): TParseResult;
  end;

  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// Used by: declaration (DRagLint.CLI.pas), DRagLint.CLI.BuildPlanItem (DRagLint.CLI.pas), DRagLint.CLI.DoIndex (DRagLint.CLI.pas), DRagLint.CLI.IndexDictionary (DRagLint.CLI.pas), declaration (DRagLint.Core.Indexer.pas)
  /// Used in units: DRagLint.CLI, DRagLint.Core.Indexer
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  IIndexer = interface
    ['{2D8E7AC5-0F33-4B19-B25A-83C176D8EE7C}']
    /// <param name="APath"><!-- drag-lint:auto type -->const string</param>
    /// <param name="ARecursive"><!-- drag-lint:auto type -->Boolean = True</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.CLI.BuildPlanItem (DRagLint.CLI.pas), DRagLint.CLI.DoIndex (DRagLint.CLI.pas), DRagLint.CLI.IndexDictionary (DRagLint.CLI.pas)
    /// <seealso cref="DRagLint.Core.Interfaces.IIndexer.AddExcludeRoot"/>
    /// <seealso cref="DRagLint.Core.Interfaces.IIndexer.IndexFile"/>
    /// <seealso cref="DRagLint.Core.Interfaces.IIndexer.SetForceReparse"/>
    /// <seealso cref="DRagLint.Core.Interfaces.IIndexer.SetPreprocess"/>
    /// <seealso cref="DRagLint.Core.Interfaces.IIndexer.SetWalkFilter"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure IndexFolder(const APath: string; ARecursive: Boolean = True);
    /// <param name="AFilePath"><!-- drag-lint:auto type -->const string</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.CLI.DoIndex (DRagLint.CLI.pas), DRagLint.CLI.IndexDictionary (DRagLint.CLI.pas), DRagLint.CLI.IndexOneFileTolerant (DRagLint.CLI.pas)
    /// <seealso cref="DRagLint.Core.Interfaces.IIndexer.AddExcludeRoot"/>
    /// <seealso cref="DRagLint.Core.Interfaces.IIndexer.IndexFolder"/>
    /// <seealso cref="DRagLint.Core.Interfaces.IIndexer.SetForceReparse"/>
    /// <seealso cref="DRagLint.Core.Interfaces.IIndexer.SetPreprocess"/>
    /// <seealso cref="DRagLint.Core.Interfaces.IIndexer.SetWalkFilter"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure IndexFile(const AFilePath: string);
    /// <returns><!-- drag-lint:auto type -->Integer</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.CLI.DoIndex (DRagLint.CLI.pas)
    /// <seealso cref="DRagLint.Core.Interfaces.IIndexer.AddExcludeRoot"/>
    /// <seealso cref="DRagLint.Core.Interfaces.IIndexer.IndexFile"/>
    /// <seealso cref="DRagLint.Core.Interfaces.IIndexer.IndexFolder"/>
    /// <seealso cref="DRagLint.Core.Interfaces.IIndexer.SetForceReparse"/>
    /// <seealso cref="DRagLint.Core.Interfaces.IIndexer.SetPreprocess"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function SkippedUpToDate: Integer;
    /// <summary>How many files this indexer got PAST the incremental
    /// up-to-date skip for -- i.e. an upper bound on the files whose rows it may
    /// have rewritten.</summary>
    /// <returns>0 when every walked file was already current, so the database
    /// this indexer writes to is provably unchanged by it.</returns>
    /// <remarks>Exists so a caller can decide whether the four whole-database
    /// resolve passes (ISymbolStore.ResolveUnitUseTargets / ResolveAncestry /
    /// ResolveHelpers / ResolveCallTargets) are worth running at all. Those
    /// passes are pure functions of the stored corpus, so on an unchanged
    /// corpus they rewrite the identical rows -- and on a multi-gigabyte index
    /// that costs minutes of silent full-table scanning per pass. A
    /// <c>--recompile</c> run where nothing had changed paid all four for
    /// nothing, which is what was mistaken for a livelock across two sessions.
    /// DELIBERATELY AN UPPER BOUND, counted before the parse rather than after
    /// the commit: over-counting wastes a pass, under-counting serves stale
    /// ancestry and call edges. It is NOT the whole precondition -- a caller
    /// that also prunes or evicts rows must include those counts, and a
    /// <c>--rebuild</c> has cleared the corpus before the walk even starts.
    /// CUMULATIVE over the indexer's lifetime, matching VisitedFiles.</remarks>
    function ParsedFiles: Integer;
    /// <summary>Every file this indexer ADMITTED since it was created -- the
    /// walk's in-scope set, in the spelling the walk produced.</summary>
    /// <returns>The admitted paths, in visit order, with duplicates collapsed.</returns>
    /// <remarks>
    /// Feeds ISymbolStore.EvictOutOfScopeFiles for a LIBRARY scan,
    /// where "in scope" is not a list the caller has -- it is whatever survived
    /// the exclude globs, the include-only allow-list, the .gitignore/.hgignore
    /// stack and the built-in directory prunes. Recomputing that outside the
    /// walk would mean a second copy of every one of those rules; asking the
    /// walk what it admitted cannot disagree with itself.
    /// ADMITTED, NOT PARSED. A file skipped by the incremental up-to-date check
    /// is still in scope (that is the whole point of an incremental run), and so
    /// is one skipped by the file-size guard: it is in the project, merely too
    /// big to parse, and evicting it would silently delete a unit's symbols
    /// because the unit grew. A file no PARSER claims is not listed -- it never
    /// had a row to lose.
    /// CUMULATIVE over the indexer's lifetime, so a --watch loop's later ticks
    /// see the union of every tick. That errs toward keeping rows, which is the
    /// safe direction for a deletion predicate.
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.CLI.BuildPlanItem (DRagLint.CLI.pas), DRagLint.CLI.DoIndex (DRagLint.CLI.pas)
    /// <seealso cref="DRagLint.Core.Interfaces.IIndexer.AddExcludeRoot"/>
    /// <seealso cref="DRagLint.Core.Interfaces.IIndexer.IndexFile"/>
    /// <seealso cref="DRagLint.Core.Interfaces.IIndexer.IndexFolder"/>
    /// <seealso cref="DRagLint.Core.Interfaces.IIndexer.SetForceReparse"/>
    /// <seealso cref="DRagLint.Core.Interfaces.IIndexer.SetPreprocess"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function VisitedFiles: TArray<string>;
    // v0.42: register a directory whose subtree must NOT be scanned (used for
    // cross-dictionary dedup -- e.g. exclude folders already covered by the
    // library or active-project indexes). Repeatable.
    /// <summary><!-- drag-lint:auto -->v0.42: register a directory whose subtree must NOT
    /// be scanned (used for cross-dictionary dedup -- e.g. exclude folders already
    /// covered by the library or active-project indexes). Repeatable.</summary>
    /// <param name="APath"><!-- drag-lint:auto type -->const string</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.CLI.BuildPlanItem (DRagLint.CLI.pas), DRagLint.CLI.DoIndex (DRagLint.CLI.pas), DRagLint.CLI.IndexDictionary (DRagLint.CLI.pas)
    /// <seealso cref="DRagLint.Core.Interfaces.IIndexer.IndexFile"/>
    /// <seealso cref="DRagLint.Core.Interfaces.IIndexer.IndexFolder"/>
    /// <seealso cref="DRagLint.Core.Interfaces.IIndexer.SetForceReparse"/>
    /// <seealso cref="DRagLint.Core.Interfaces.IIndexer.SetPreprocess"/>
    /// <seealso cref="DRagLint.Core.Interfaces.IIndexer.SetWalkFilter"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure AddExcludeRoot(const APath: string);
    /// <summary>INBOX 2.3: bypass the incremental up-to-date skip for this whole
    /// run, re-parsing every walked file even when path+mtime+sha are unchanged.
    /// Set when the caller detects an indexer-fingerprint change (a different
    /// engine build, schema, platform or preprocess profile would extract
    /// different symbols from identical bytes) or when the user passes
    /// --force-reparse.</summary>
    /// <param name="AValue"><!-- drag-lint:auto type -->Boolean</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.CLI.ApplyIndexerFingerprint (DRagLint.CLI.pas)
    /// <seealso cref="DRagLint.Core.Interfaces.IIndexer.AddExcludeRoot"/>
    /// <seealso cref="DRagLint.Core.Interfaces.IIndexer.IndexFile"/>
    /// <seealso cref="DRagLint.Core.Interfaces.IIndexer.IndexFolder"/>
    /// <seealso cref="DRagLint.Core.Interfaces.IIndexer.SetPreprocess"/>
    /// <seealso cref="DRagLint.Core.Interfaces.IIndexer.SetWalkFilter"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure SetForceReparse(AValue: Boolean);
    /// <summary>Apply glob-based file/dir filtering to subsequent IndexFolder
    /// calls. Must be called before the first IndexFolder; has no effect on
    /// IndexFile. SqlOnlyMS defaults to True if never called.</summary>
    /// <param name="AFilter">Filter settings; caller may leave unused fields
    /// at their zero-value defaults.</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.CLI.BuildPlanItem (DRagLint.CLI.pas), DRagLint.CLI.DoIndex (DRagLint.CLI.pas)
    /// <seealso cref="DRagLint.Core.Interfaces.IIndexer.AddExcludeRoot"/>
    /// <seealso cref="DRagLint.Core.Interfaces.IIndexer.IndexFile"/>
    /// <seealso cref="DRagLint.Core.Interfaces.IIndexer.IndexFolder"/>
    /// <seealso cref="DRagLint.Core.Interfaces.IIndexer.SetForceReparse"/>
    /// <seealso cref="DRagLint.Core.Interfaces.IIndexer.SetPreprocess"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
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
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.CLI.BuildPlanItem (DRagLint.CLI.pas), DRagLint.CLI.DoIndex (DRagLint.CLI.pas)
    /// <seealso cref="DRagLint.Core.Interfaces.IIndexer.AddExcludeRoot"/>
    /// <seealso cref="DRagLint.Core.Interfaces.IIndexer.IndexFile"/>
    /// <seealso cref="DRagLint.Core.Interfaces.IIndexer.IndexFolder"/>
    /// <seealso cref="DRagLint.Core.Interfaces.IIndexer.SetForceReparse"/>
    /// <seealso cref="DRagLint.Core.Interfaces.IIndexer.SetWalkFilter"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
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
