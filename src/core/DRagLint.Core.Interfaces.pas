unit DRagLint.Core.Interfaces;

interface

uses
  System.SysUtils
  , DRagLint.Core.Model
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
    /// <summary>Transitive ancestor closure of the symbol (resolved edges are
    /// walked recursively; unresolved ones are name-only leaves). Cycle-safe,
    /// hop-capped.</summary>
    function GetTransitiveAncestors(ASymbolId: Int64): TArray<TTypeAncestor>;
    /// <summary>True when class/interface AClassName (resolved in-scope of
    /// AFileId) has AAncestorName anywhere in its transitive ancestor closure.</summary>
    function IsDescendantOf(const AClassName, AAncestorName: string; AFileId: Int64): Boolean;
    /// <summary>True when AClassName's transitive closure reaches AInterfaceName
    /// via an interface-kind edge (i.e. AClassName implements that interface).</summary>
    function ImplementsInterface(const AClassName, AInterfaceName: string; AFileId: Int64): Boolean;
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

    // v0.20: completion helpers
    function FindSymbolsByPrefix(const APrefix: string; ALimit: Integer): TArray<TSymbol>;
    function FindAllChildSymbols(AParentId: Int64): TArray<TSymbol>                      ;

    // v0.25: dead-code finder
    function FindSymbolsWithNoCallers(const AKind: string; AIncludePrivate: Boolean): TArray<TSymbol>;

    // v0.26: compiler diagnostics
    function FindCompilerFindingsForFile(AFileId: Int64): TArray<TCompilerFinding>;
    procedure ClearCompilerFindings;
    procedure InsertCompilerFinding(const AFinding: TCompilerFinding);

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
