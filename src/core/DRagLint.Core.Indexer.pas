unit DRagLint.Core.Indexer;

interface

uses
  System.SysUtils
  , System.Classes
  , System.StrUtils
  , System.IOUtils
  , System.Hash
  , System.DateUtils
  , System.Diagnostics          { v0.85: per-phase indexing profiler (DRAGLINT_PROFILE) }
  , System  .Generics.Collections
  , DRagLint.Core    .Model
  , DRagLint.Core    .Interfaces
  , DRagLint.Core    .Encoding
  , DRagLint.Index   .Glob
  , DRagLint.Index   .IgnoreFiles
  , DRagLint.Parser  .DocComments
  , DRagLint.Preprocess         { PP-Task-9: in-process directive preprocessor }
  , DRagLint.Preprocess.Types   { TDefineProfile }
  ;

type
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// Used by: DRagLint.CLI.BuildPlanItem (DRagLint.CLI.pas), DRagLint.CLI.DoIndex (DRagLint.CLI.pas), DRagLint.CLI.IndexDictionary (DRagLint.CLI.pas), DRagLint.CLI.DoReconcileProject (DRagLint.CLI.pas)
  /// Used in units: DRagLint.CLI
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TIndexer = class(TInterfacedObject, IIndexer)
    strict private
      FStore          : ISymbolStore                       ;
      FParsers        : TList<IParser>                     ;
      FSkippedUpToDate: Integer                            ;
      { Files this indexer got PAST the up-to-date skip for, i.e. every file it
        may have written rows for. Backs IIndexer.ParsedFiles -- see there. }
      FParsedFiles    : Integer                            ;
      { The walk's in-scope set: every file a parser claimed, whether or not it
        was then parsed. Backs IIndexer.VisitedFiles -- see there for why the
        list is what it is. FVisitedKeys is the lowercase de-dup guard; the same
        file is reached twice whenever two walked roots overlap. }
      FVisited        : TList<string>                      ;
      FVisitedKeys    : TDictionary<string, Boolean>       ;
      FDocConfig      : TDocConfig                         ;
      FExcludeRoots   : TList<string>                      ; { v0.42: normalized lowercase, trailing-sep }
      FWalkFilter     : TWalkFilter                        ; { v0.45: glob/ignore filtering }
      FIgnoreStack    : TIgnoreStack                       ; { v0.45: .gitignore/.hgignore stack; nil when not UseIgnoreFiles }
      FPreprocessEnabled: Boolean                          ; { PP-Task-9: run Preprocess before parsing }
      FProfile        : TDefineProfile                     ; { PP-Task-9: active define profile when preprocessing }
      FPreprocessFellBack: Boolean                         ; { PP-Task-9: one-shot fallback-log latch }
      FForceReparse   : Boolean                            ; { INBOX 2.3: bypass the incremental skip for this whole run }
      { PER-FILE RESUME (INBOX-index-runs-are-not-resumable). '' = off.

        NOT a second name for FForceReparse, and the difference is load-bearing.
        FForceReparse is set for THREE different reasons and only one of them may
        resume:
          * the indexer FINGERPRINT changed  -> resumable. A file already parsed
            by THIS engine is genuinely up to date and re-parsing it is pure
            waste. This is the case that costs hours.
          * --force-reparse                  -> NOT resumable. The flag means
            "ignore the skip"; honouring a stamp would silently disobey it.
          * --rebuild                        -> NOT resumable, and moot: the
            index is wiped first, so no stamp survives to match.
        Only the caller can tell these apart, so it says so explicitly here
        rather than this unit inferring it from FForceReparse. }
      FResumeFingerprint: string                           ;
      { Walk progress (2026-08-16). A per-file line with no counter makes an
        hours-long library reindex indistinguishable from a hang, which is
        exactly the confusion that made the Win32 rebuild abort hard to diagnose.
        IndexFolder therefore walks TWICE: once in count-only mode to learn the
        denominator, then for real.

        The count pass runs the SAME WalkAndIndex with the SAME filters and the
        SAME ignore-stack, and that is load-bearing -- a pre-count that globbed
        the tree itself would disagree with what actually gets indexed and would
        report a total the run never reaches. It is cheap: directory enumeration
        and glob tests, no parsing, no store access. }
      FCountOnly      : Boolean                            ;
      FProgressTotal  : Integer                            ;
      FProgressDone   : Integer                            ;
      FProgressWatch  : TStopwatch                         ;
      /// <summary>PP-Task-9: log a per-file preprocess fallback the FIRST time it
      /// happens in this run, then stay silent so a bad batch does not flood the
      /// output with one line per file. The file is still indexed from its RAW
      /// UTF-8 bytes (old behaviour) -- a preprocess exception never hard-fails
      /// the run.</summary>
      /// <param name="AFilePath"><!-- drag-lint:auto type -->const string</param>
      /// <param name="AError"><!-- drag-lint:auto type -->const Exception</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Called from: DRagLint.Core.Indexer.TIndexer.IndexFile (DRagLint.Core.Indexer.pas)
      /// Calls: Format, Writeln
      /// Reads: FPreprocessFellBack   Writes: FPreprocessFellBack
      /// <seealso cref="DRagLint.Core.Indexer.TIndexer.AddExcludeRoot"/>
      /// <seealso cref="DRagLint.Core.Indexer.TIndexer.Create"/>
      /// <seealso cref="DRagLint.Core.Indexer.TIndexer.Destroy"/>
      /// <seealso cref="DRagLint.Core.Indexer.TIndexer.IndexFile"/>
      /// <seealso cref="DRagLint.Core.Indexer.TIndexer.IndexFolder"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure LogPreprocessFallbackOnce(const AFilePath: string; const AError: Exception);
      /// <param name="AExtension"><!-- drag-lint:auto type -->const string</param>
      /// <returns><!-- drag-lint:auto -->Observed: nil.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Called from: DRagLint.Core.Indexer.TIndexer.IndexFile (DRagLint.Core.Indexer.pas), DRagLint.Core.Indexer.TIndexer.WalkAndIndex (DRagLint.Core.Indexer.pas)
      /// Calls: DRagLint.Core.Interfaces.IParser.FileExtensions, LowerCase, SameText
      /// Reads: FParsers
      /// Pure
      /// <seealso cref="DRagLint.Core.Interfaces.IParser.FileExtensions"/>
      /// <seealso cref="DRagLint.Core.Indexer.TIndexer.AddExcludeRoot"/>
      /// <seealso cref="DRagLint.Core.Indexer.TIndexer.Create"/>
      /// <seealso cref="DRagLint.Core.Indexer.TIndexer.Destroy"/>
      /// <seealso cref="DRagLint.Core.Indexer.TIndexer.IndexFile"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function ParserFor(const AExtension: string): IParser;
      /// <param name="APath"><!-- drag-lint:auto type -->const string</param>
      /// <param name="ASymbols"><!-- drag-lint:auto type -->Integer</param>
      /// <param name="ARefs"><!-- drag-lint:auto type -->Integer</param>
      /// <param name="AErrors"><!-- drag-lint:auto type -->Integer</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Called from: DRagLint.Core.Indexer.TIndexer.IndexFile (DRagLint.Core.Indexer.pas)
      /// Calls: Format, Writeln
      /// Pure
      /// <seealso cref="DRagLint.Core.Indexer.TIndexer.AddExcludeRoot"/>
      /// <seealso cref="DRagLint.Core.Indexer.TIndexer.Create"/>
      /// <seealso cref="DRagLint.Core.Indexer.TIndexer.Destroy"/>
      /// <seealso cref="DRagLint.Core.Indexer.TIndexer.IndexFile"/>
      /// <seealso cref="DRagLint.Core.Indexer.TIndexer.IndexFolder"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure ReportProgress(const APath: string; ASymbols, ARefs, AErrors: Integer);
      /// <param name="APath"><!-- drag-lint:auto type -->const string</param>
      /// <returns><!-- drag-lint:auto -->Observed: False.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Called from: DRagLint.Core.Indexer.TIndexer.ShouldPruneDir (DRagLint.Core.Indexer.pas)
      /// Calls: LowerCase, StartsStr
      /// Reads: FExcludeRoots
      /// Pure
      /// <seealso cref="DRagLint.Core.Indexer.TIndexer.AddExcludeRoot"/>
      /// <seealso cref="DRagLint.Core.Indexer.TIndexer.Create"/>
      /// <seealso cref="DRagLint.Core.Indexer.TIndexer.Destroy"/>
      /// <seealso cref="DRagLint.Core.Indexer.TIndexer.IndexFile"/>
      /// <seealso cref="DRagLint.Core.Indexer.TIndexer.IndexFolder"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function IsUnderExcludeRoot  (const APath: string): Boolean;
      /// <param name="ADir"><!-- drag-lint:auto type -->const string</param>
      /// <returns><!-- drag-lint:auto -->Observed: True; False.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Called from: DRagLint.Core.Indexer.TIndexer.WalkAndIndex (DRagLint.Core.Indexer.pas)
      /// Calls: DRagLint.Core.Indexer.TIndexer.IsUnderExcludeRoot, DRagLint.Index.Glob.TGlob.MatchesAny, ExcludeTrailingPathDelimiter, ExtractFileName, IncludeTrailingPathDelimiter, LowerCase, Pos
      /// Reads: FWalkFilter
      /// Touches: file system
      /// <seealso cref="DRagLint.Core.Indexer.TIndexer.IsUnderExcludeRoot"/>
      /// <seealso cref="DRagLint.Index.Glob.TGlob.MatchesAny"/>
      /// <seealso cref="DRagLint.Core.Indexer.TIndexer.AddExcludeRoot"/>
      /// <seealso cref="DRagLint.Core.Indexer.TIndexer.Create"/>
      /// <seealso cref="DRagLint.Core.Indexer.TIndexer.Destroy"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function ShouldPruneDir      (const ADir : string): Boolean;
      /// <summary><!-- drag-lint:auto -->v0.42: SQL files are scanned only when they
      /// match the MS*.SQL convention (the Micronite Firebird DDL scripts) -- per user,
      /// those are the only SQL files worth indexing. Every other .sql is skipped so the
      /// index isn't polluted by ad-hoc query scripts. Non-.sql files always pass this
      /// gate. v0.45: gate is conditional on FWalkFilter.SqlOnlyMS; when False all SQL
      /// pass.</summary>
      /// <param name="APath"><!-- drag-lint:auto type -->const string</param>
      /// <returns><!-- drag-lint:auto -->Observed: StartsText('MS', Name).</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Called from: DRagLint.Core.Indexer.TIndexer.WalkAndIndex (DRagLint.Core.Indexer.pas)
      /// Calls: ExtractFileExt, ExtractFileName, SameText, StartsText
      /// Reads: FWalkFilter
      /// Pure
      /// <seealso cref="DRagLint.Core.Indexer.TIndexer.AddExcludeRoot"/>
      /// <seealso cref="DRagLint.Core.Indexer.TIndexer.Create"/>
      /// <seealso cref="DRagLint.Core.Indexer.TIndexer.Destroy"/>
      /// <seealso cref="DRagLint.Core.Indexer.TIndexer.IndexFile"/>
      /// <seealso cref="DRagLint.Core.Indexer.TIndexer.IndexFolder"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function SqlFileAllowedFilter(const APath: string): Boolean;
      /// <summary>v13 (v0.82): resolve a ref's innermost enclosing routine.
      /// Among ASymbols of routine kind (method/function/procedure/constructor/
      /// destructor) with ImplStartLine &gt; 0 whose [ImplStartLine..ImplEndLine]
      /// contains ALine, pick the one with the LARGEST ImplStartLine (innermost --
      /// so a nested procedure wins over its outer routine), then map its array
      /// index to its DB id via AIdxToId.</summary>
      /// <param name="ASymbols">The file's just-parsed symbols (index i == the key used in AIdxToId).</param>
      /// <param name="AIdxToId">Array-index -&gt; inserted DB id map built by the symbols loop.</param>
      /// <param name="ALine">The ref's StartLine.</param>
      /// <returns>The enclosing routine's DB id, or 0 when the line is in no routine body.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Called from: DRagLint.Core.Indexer.TIndexer.IndexFile (DRagLint.Core.Indexer.pas)
      /// Returns: 0; DbId
      /// Pure
      /// <seealso cref="DRagLint.Core.Indexer.TIndexer.AddExcludeRoot"/>
      /// <seealso cref="DRagLint.Core.Indexer.TIndexer.Create"/>
      /// <seealso cref="DRagLint.Core.Indexer.TIndexer.Destroy"/>
      /// <seealso cref="DRagLint.Core.Indexer.TIndexer.IndexFile"/>
      /// <seealso cref="DRagLint.Core.Indexer.TIndexer.IndexFolder"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function ResolveEnclosingSymbolId(const ASymbols: TArray<TSymbol>;
        const AIdxToId: TDictionary<Integer, Int64>; ALine: Integer): Int64;
      /// <summary>v(ADP2 T2): 1-based, inclusive line-range slice of ALines
      /// (the file's SourceText, already split once per IndexFile call),
      /// clipped to ALines' actual bounds. Feeds a routine symbol's impl body
      /// to TSymbolFactsAnalyzer.Analyze without a per-symbol re-read/re-split
      /// of the file.</summary>
      /// <param name="ALines">The file's source lines (index 0 == line 1).</param>
      /// <param name="AFromLine">First body line, 1-based (Sym.ImplStartLine).</param>
      /// <param name="AToLine">Last body line, 1-based (Sym.ImplEndLine).</param>
      /// <returns>ALines[AFromLine..AToLine] clipped to bounds; nil when the
      /// clipped range is empty (e.g. ALines is empty).</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Called from: DRagLint.Core.Indexer.TIndexer.IndexFile (DRagLint.Core.Indexer.pas)
      /// Pure
      /// <seealso cref="DRagLint.Core.Indexer.TIndexer.AddExcludeRoot"/>
      /// <seealso cref="DRagLint.Core.Indexer.TIndexer.Create"/>
      /// <seealso cref="DRagLint.Core.Indexer.TIndexer.Destroy"/>
      /// <seealso cref="DRagLint.Core.Indexer.TIndexer.IndexFile"/>
      /// <seealso cref="DRagLint.Core.Indexer.TIndexer.IndexFolder"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function SliceBodyLines(const ALines: TArray<string>; AFromLine, AToLine: Integer): TArray<string>;
      /// <param name="ADir"><!-- drag-lint:auto type -->const string</param>
      /// <param name="ARecursive"><!-- drag-lint:auto type -->Boolean</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Called from: DRagLint.Core.Indexer.TIndexer.IndexFolder (DRagLint.Core.Indexer.pas), DRagLint.Core.Indexer.TIndexer.WalkAndIndex (DRagLint.Core.Indexer.pas)
      /// Calls: DRagLint.Core.Indexer.TIndexer.IndexFile, DRagLint.Core.Indexer.TIndexer.ParserFor, DRagLint.Core.Indexer.TIndexer.ShouldPruneDir, DRagLint.Core.Indexer.TIndexer.SqlFileAllowedFilter, DRagLint.Core.Indexer.TIndexer.WalkAndIndex, DRagLint.Index.Glob.TGlob.MatchesAny, DRagLint.Index.IgnoreFiles.TIgnoreStack.IsIgnored, DRagLint.Index.IgnoreFiles.TIgnoreStack.PopDir, DRagLint.Index.IgnoreFiles.TIgnoreStack.PushDir, ExcludeTrailingPathDelimiter, ExtractFileExt, ExtractFileName, Format, Writeln
      /// Complexity: 15 (cyclomatic, outer body), 64 lines (full implementation)
      /// Reads: FIgnoreStack, FWalkFilter
      /// Recursive
      /// Touches: file system
      /// <seealso cref="DRagLint.Core.Indexer.TIndexer.IndexFile"/>
      /// <seealso cref="DRagLint.Core.Indexer.TIndexer.ParserFor"/>
      /// <seealso cref="DRagLint.Core.Indexer.TIndexer.ShouldPruneDir"/>
      /// <seealso cref="DRagLint.Core.Indexer.TIndexer.SqlFileAllowedFilter"/>
      /// <seealso cref="DRagLint.Index.Glob.TGlob.MatchesAny"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure WalkAndIndex(const ADir: string; ARecursive: Boolean);
    public
      /// <param name="AStore"><!-- drag-lint:auto type -->const ISymbolStore</param>
      /// <param name="AParsers"><!-- drag-lint:auto type -->const TArray&lt;IParser&gt;</param>
      /// <param name="ADocConfig"><!-- drag-lint:auto type -->const TDocConfig</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Called from: DRagLint.CLI.BuildPlanItem (DRagLint.CLI.pas), DRagLint.CLI.DoIndex (DRagLint.CLI.pas), DRagLint.CLI.DoReconcileProject (DRagLint.CLI.pas), DRagLint.CLI.IndexDictionary (DRagLint.CLI.pas), DRagLint.Core.Indexer.TIndexer.Create/2 (DRagLint.Core.Indexer.pas)
      /// Calls: DRagLint.Core.Interfaces.TWalkFilter.Create
      /// Overload 1 of 2
      /// constructor
      /// Reads: FParsers   Writes: FStore, FDocConfig, FParsers, FExcludeRoots, FVisited, FVisitedKeys, FIgnoreStack, FPreprocessEnabled (+2 more)
      /// <seealso cref="DRagLint.Core.Interfaces.TWalkFilter.Create"/>
      /// <seealso cref="DRagLint.Core.Indexer.TIndexer.AddExcludeRoot"/>
      /// <seealso cref="DRagLint.Core.Indexer.TIndexer.Create"/>
      /// <seealso cref="DRagLint.Core.Indexer.TIndexer.Destroy"/>
      /// <seealso cref="DRagLint.Core.Indexer.TIndexer.IndexFile"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      constructor Create(const AStore: ISymbolStore; const AParsers: TArray<IParser>; const ADocConfig: TDocConfig); overload;
      /// <param name="AStore"><!-- drag-lint:auto type -->const ISymbolStore</param>
      /// <param name="AParsers"><!-- drag-lint:auto type -->const TArray&lt;IParser&gt;</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Calls: DRagLint.Core.Indexer.TIndexer.Create/3
      /// Overload 2 of 2
      /// constructor
      /// Pure
      /// <seealso cref="DRagLint.Core.Indexer.TIndexer.Create"/>
      /// <seealso cref="DRagLint.Core.Indexer.TIndexer.AddExcludeRoot"/>
      /// <seealso cref="DRagLint.Core.Indexer.TIndexer.Destroy"/>
      /// <seealso cref="DRagLint.Core.Indexer.TIndexer.IndexFile"/>
      /// <seealso cref="DRagLint.Core.Indexer.TIndexer.IndexFolder"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      constructor Create(const AStore: ISymbolStore; const AParsers: TArray<IParser>); overload;
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Reads: FParsers, FExcludeRoots, FVisited, FVisitedKeys, FIgnoreStack   Writes: FStore
      /// <seealso cref="DRagLint.Core.Indexer.TIndexer.AddExcludeRoot"/>
      /// <seealso cref="DRagLint.Core.Indexer.TIndexer.Create"/>
      /// <seealso cref="DRagLint.Core.Indexer.TIndexer.IndexFile"/>
      /// <seealso cref="DRagLint.Core.Indexer.TIndexer.IndexFolder"/>
      /// <seealso cref="DRagLint.Core.Indexer.TIndexer.IsUnderExcludeRoot"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      destructor Destroy; override;
      /// <param name="APath"><!-- drag-lint:auto type -->const string</param>
      /// <param name="ARecursive"><!-- drag-lint:auto type -->Boolean = True</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Calls: DRagLint.Core.Indexer.TIndexer.WalkAndIndex
      /// Implements: DRagLint.Core.Interfaces.IIndexer.IndexFolder
      /// Pure
      /// <seealso cref="DRagLint.Core.Indexer.TIndexer.WalkAndIndex"/>
      /// <seealso cref="DRagLint.Core.Indexer.TIndexer.AddExcludeRoot"/>
      /// <seealso cref="DRagLint.Core.Indexer.TIndexer.Create"/>
      /// <seealso cref="DRagLint.Core.Indexer.TIndexer.Destroy"/>
      /// <seealso cref="DRagLint.Core.Indexer.TIndexer.IndexFile"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure IndexFolder(const APath: string; ARecursive: Boolean = True);
      /// <param name="AFilePath"><!-- drag-lint:auto type -->const string</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Called from: DRagLint.CLI.DoReconcileProject (DRagLint.CLI.pas), DRagLint.Core.Indexer.TIndexer.WalkAndIndex (DRagLint.Core.Indexer.pas)
      /// Calls: DateTimeToUnix, DRagLint.Core.Encoding.EnsureUtf8Bytes, DRagLint.Core.Indexer.BuildEnclosingLineMap, DRagLint.Core.Indexer.FindDocRegionAbove, DRagLint.Core.Indexer.TIndexer.LogPreprocessFallbackOnce, DRagLint.Core.Indexer.TIndexer.ParserFor, DRagLint.Core.Indexer.TIndexer.ReportProgress, DRagLint.Core.Indexer.TIndexer.ResolveEnclosingSymbolId, DRagLint.Core.Indexer.TIndexer.SliceBodyLines, DRagLint.Core.Interfaces.IParser.LanguageName (+29 more)
      /// Implements: DRagLint.Core.Interfaces.IIndexer.IndexFile
      /// Complexity: 27 (cyclomatic, outer body), 351 lines (full implementation)
      /// Reads: FVisitedKeys, FVisited, FWalkFilter, FForceReparse, FStore, FPreprocessEnabled, FProfile, FDocConfig   Writes: FSkippedUpToDate, FParsedFiles
      /// Touches: file system
      /// <seealso cref="DRagLint.Core.Encoding.EnsureUtf8Bytes"/>
      /// <seealso cref="DRagLint.Core.Indexer.BuildEnclosingLineMap"/>
      /// <seealso cref="DRagLint.Core.Indexer.FindDocRegionAbove"/>
      /// <seealso cref="DRagLint.Core.Indexer.TIndexer.LogPreprocessFallbackOnce"/>
      /// <seealso cref="DRagLint.Core.Indexer.TIndexer.ParserFor"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure IndexFile(const AFilePath: string);
      /// <returns><!-- drag-lint:auto -->Observed: FSkippedUpToDate.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Implements: DRagLint.Core.Interfaces.IIndexer.SkippedUpToDate
      /// Reads: FSkippedUpToDate
      /// Pure
      /// <seealso cref="DRagLint.Core.Indexer.TIndexer.AddExcludeRoot"/>
      /// <seealso cref="DRagLint.Core.Indexer.TIndexer.Create"/>
      /// <seealso cref="DRagLint.Core.Indexer.TIndexer.Destroy"/>
      /// <seealso cref="DRagLint.Core.Indexer.TIndexer.IndexFile"/>
      /// <seealso cref="DRagLint.Core.Indexer.TIndexer.IndexFolder"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function SkippedUpToDate: Integer;
      /// <summary>How many files this indexer got past the incremental
      /// up-to-date skip for -- see IIndexer.ParsedFiles.</summary>
      /// <returns><!-- drag-lint:auto -->Observed: FParsedFiles.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Implements: DRagLint.Core.Interfaces.IIndexer.ParsedFiles
      /// Reads: FParsedFiles
      /// Pure
      /// <seealso cref="DRagLint.Core.Indexer.TIndexer.AddExcludeRoot"/>
      /// <seealso cref="DRagLint.Core.Indexer.TIndexer.Create"/>
      /// <seealso cref="DRagLint.Core.Indexer.TIndexer.Destroy"/>
      /// <seealso cref="DRagLint.Core.Indexer.TIndexer.IndexFile"/>
      /// <seealso cref="DRagLint.Core.Indexer.TIndexer.IndexFolder"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function ParsedFiles: Integer;
      /// <returns><!-- drag-lint:auto -->Observed: FVisited.ToArray.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Implements: DRagLint.Core.Interfaces.IIndexer.VisitedFiles
      /// Reads: FVisited
      /// Pure
      /// <seealso cref="DRagLint.Core.Indexer.TIndexer.AddExcludeRoot"/>
      /// <seealso cref="DRagLint.Core.Indexer.TIndexer.Create"/>
      /// <seealso cref="DRagLint.Core.Indexer.TIndexer.Destroy"/>
      /// <seealso cref="DRagLint.Core.Indexer.TIndexer.IndexFile"/>
      /// <seealso cref="DRagLint.Core.Indexer.TIndexer.IndexFolder"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function VisitedFiles: TArray<string>;
      /// <param name="APath"><!-- drag-lint:auto type -->const string</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Calls: ExcludeTrailingPathDelimiter, IncludeTrailingPathDelimiter, LowerCase
      /// Implements: DRagLint.Core.Interfaces.IIndexer.AddExcludeRoot
      /// Reads: FExcludeRoots
      /// Pure
      /// <seealso cref="DRagLint.Core.Indexer.TIndexer.Create"/>
      /// <seealso cref="DRagLint.Core.Indexer.TIndexer.Destroy"/>
      /// <seealso cref="DRagLint.Core.Indexer.TIndexer.IndexFile"/>
      /// <seealso cref="DRagLint.Core.Indexer.TIndexer.IndexFolder"/>
      /// <seealso cref="DRagLint.Core.Indexer.TIndexer.IsUnderExcludeRoot"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure AddExcludeRoot(const APath: string);
      /// <param name="AValue"><!-- drag-lint:auto type -->Boolean</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Implements: DRagLint.Core.Interfaces.IIndexer.SetForceReparse
      /// Writes: FForceReparse
      /// <seealso cref="DRagLint.Core.Indexer.TIndexer.AddExcludeRoot"/>
      /// <seealso cref="DRagLint.Core.Indexer.TIndexer.Create"/>
      /// <seealso cref="DRagLint.Core.Indexer.TIndexer.Destroy"/>
      /// <seealso cref="DRagLint.Core.Indexer.TIndexer.IndexFile"/>
      /// <seealso cref="DRagLint.Core.Indexer.TIndexer.IndexFolder"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure SetForceReparse(AValue: Boolean);
      /// <remarks>
      /// Implements: DRagLint.Core.Interfaces.IIndexer.SetResumeFingerprint
      /// Writes: FResumeFingerprint
      /// </remarks>
      procedure SetResumeFingerprint(const AFingerprint: string);
      /// <param name="AFilter"><!-- drag-lint:auto type -->const TWalkFilter</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Calls: DRagLint.Index.IgnoreFiles.TIgnoreStack.Create, FreeAndNil
      /// Implements: DRagLint.Core.Interfaces.IIndexer.SetWalkFilter
      /// Reads: FIgnoreStack, FWalkFilter   Writes: FWalkFilter, FIgnoreStack
      /// <seealso cref="DRagLint.Index.IgnoreFiles.TIgnoreStack.Create"/>
      /// <seealso cref="DRagLint.Core.Indexer.TIndexer.AddExcludeRoot"/>
      /// <seealso cref="DRagLint.Core.Indexer.TIndexer.Create"/>
      /// <seealso cref="DRagLint.Core.Indexer.TIndexer.Destroy"/>
      /// <seealso cref="DRagLint.Core.Indexer.TIndexer.IndexFile"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure SetWalkFilter(const AFilter: TWalkFilter);
      /// <param name="AEnabled"><!-- drag-lint:auto type -->Boolean</param>
      /// <param name="AProfile"><!-- drag-lint:auto type -->const TDefineProfile</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Called from: DRagLint.CLI.DoReconcileProject (DRagLint.CLI.pas), DRagLint.CLI.DoIndex (DRagLint.CLI.pas)
      /// Implements: DRagLint.Core.Interfaces.IIndexer.SetPreprocess
      /// Writes: FPreprocessEnabled, FProfile, FPreprocessFellBack
      /// <seealso cref="DRagLint.Core.Indexer.TIndexer.AddExcludeRoot"/>
      /// <seealso cref="DRagLint.Core.Indexer.TIndexer.Create"/>
      /// <seealso cref="DRagLint.Core.Indexer.TIndexer.Destroy"/>
      /// <seealso cref="DRagLint.Core.Indexer.TIndexer.IndexFile"/>
      /// <seealso cref="DRagLint.Core.Indexer.TIndexer.IndexFolder"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure SetPreprocess(AEnabled: Boolean; const AProfile: TDefineProfile);
  end;

implementation

uses
  DRagLint.Doc.SymbolFacts        { v(ADP2 T2): TSymbolFactsAnalyzer -- index-time symbol_facts pass }
  , DRagLint.Diagnostics.ParseCache { v(ADP2 T3): TAstParseCache.Clear -- bound the per-file tree cache }
  ;

constructor TIndexer.Create(const AStore: ISymbolStore; const AParsers: TArray<IParser>; const ADocConfig: TDocConfig);
var
  P: IParser;
begin
  inherited Create;
  FStore    := AStore;
  FDocConfig:= ADocConfig;
  FParsers:= TList<IParser>.Create;
  FExcludeRoots:= TList<string>.Create;
  FVisited     := TList<string>.Create;
  FVisitedKeys := TDictionary<string, Boolean>.Create;
  FIgnoreStack:= nil;
  { PP-Task-9: safe default -- preprocessing OFF until a caller opts in via
    SetPreprocess. A bare TIndexer (tests, embedders) keeps the pre-Task-9 raw
    all-branch behaviour; the CLI enables it by default (--no-preprocess opts
    out). FProfile stays empty (an empty profile = no seeded defines). }
  FPreprocessEnabled := False;
  FPreprocessFellBack:= False;
  { v0.45: default filter preserves prior behaviour -- only MS*.SQL indexed. }
  FWalkFilter:= TWalkFilter.Create;
  for P in AParsers do FParsers.Add(P);
end;

constructor TIndexer.Create(const AStore: ISymbolStore; const AParsers: TArray<IParser>);
begin
  Create(AStore, AParsers, DefaultDocConfig);
end;

destructor TIndexer.Destroy;
begin
  FParsers.Free;
  FExcludeRoots.Free;
  FVisited.Free;
  FVisitedKeys.Free;
  FIgnoreStack.Free;
  FStore:= nil;
  inherited;
end;

function TIndexer.SkippedUpToDate: Integer;
begin
  Result:= FSkippedUpToDate;
end;

function TIndexer.ParsedFiles: Integer;
begin
  Result:= FParsedFiles;
end;

function TIndexer.VisitedFiles: TArray<string>;
begin
  Result:= FVisited.ToArray;
end;

procedure TIndexer.AddExcludeRoot(const APath: string);
var
  Norm: string;
begin
  if APath = '' then Exit;
  Norm:= LowerCase(IncludeTrailingPathDelimiter( ExcludeTrailingPathDelimiter(APath)));
  if not FExcludeRoots.Contains(Norm) then FExcludeRoots.Add(Norm);
end;

procedure TIndexer.SetForceReparse(AValue: Boolean);
begin
  FForceReparse:= AValue;
end;

procedure TIndexer.SetResumeFingerprint(const AFingerprint: string);
begin
  FResumeFingerprint:= AFingerprint;
end;

function TIndexer.IsUnderExcludeRoot(const APath: string): Boolean;
var
  L   : string;
  Root: string;
begin
  Result:= False;
  if FExcludeRoots.Count = 0 then Exit;
  L:= LowerCase(APath);
  for Root in FExcludeRoots do
    if StartsStr(Root, L) then Exit(True);
end;

procedure TIndexer.SetWalkFilter(const AFilter: TWalkFilter);
begin
  FWalkFilter:= AFilter;
  { (Re)create the ignore stack when UseIgnoreFiles is toggled. }
  FreeAndNil(FIgnoreStack);
  if FWalkFilter.UseIgnoreFiles then FIgnoreStack:= TIgnoreStack.Create;
end;

procedure TIndexer.SetPreprocess(AEnabled: Boolean; const AProfile: TDefineProfile);
begin
  { PP-Task-9: latch the per-run flag + profile. Reset the one-shot fallback
    latch so each run gets its own first-fallback log line. }
  FPreprocessEnabled := AEnabled;
  FProfile           := AProfile;
  FPreprocessFellBack:= False;
end;

procedure TIndexer.LogPreprocessFallbackOnce(const AFilePath: string; const AError: Exception);
begin
  { PP-Task-9: never hard-fail an index run because one file's preprocess threw
    -- the file is still indexed from its RAW UTF-8 bytes (old behaviour). Log
    only the FIRST fallback so a bad batch does not flood stderr with one line
    per file. }
  if FPreprocessFellBack then Exit;
  FPreprocessFellBack:= True;
  Writeln(ErrOutput, Format(
    '  PREPROCESS FALLBACK: %s -- %s: %s (indexing raw; further fallbacks silent)',
    [AFilePath, AError.ClassName, AError.Message]));
end;

function TIndexer.ParserFor(const AExtension: string): IParser;
var
  P    : IParser;
  E    : string ;
  Lower: string ;
begin
  Lower:= LowerCase(AExtension);
  for P in FParsers do
    for E in P.FileExtensions do
      if SameText(E, Lower) then Exit(P);
  Result:= nil;
end;

{ Renders a coarse duration. Deliberately coarse: an ETA accurate to the second
  invites the reader to believe it, and this one is a straight-line extrapolation
  from the mean so far, which a directory of large units will falsify. }
function HumanDuration(ASeconds: Double): string;
var
  S: Int64;
begin
  if ASeconds < 0 then ASeconds:= 0;
  S:= Round(ASeconds);
  if S < 60 then Exit(Format('%ds', [S]));
  if S < 3600 then Exit(Format('%dm%02ds', [S div 60, S mod 60]));
  Result:= Format('%dh%02dm', [S div 3600, (S mod 3600) div 60]);
end;

procedure TIndexer.ReportProgress(const APath: string; ASymbols, ARefs, AErrors: Integer);
var
  Elapsed: Double;
  Eta    : Double;
begin
  { The stdout line is UNCHANGED and must stay so -- several suites regex it
    (run_index_fingerprint_commit.ps1 among them), and breaking them to add a
    counter would be a poor trade. The counter goes to stderr instead, where it
    reaches a human watching the run without entering any suite's captured
    stdout. }
  Writeln(Format('  %s -> %d symbols, %d refs, %d errors', [APath, ASymbols, ARefs, AErrors]));

  { No denominator means no counter, and that is not an oversight. Only the
    FOLDER walk (IndexFolder -- i.e. smFolderTree/smLibrary sections, and an
    ad-hoc `index <dir>`) sets a total. A single-file index and a PROJECT
    section, which indexes its members through IndexFile directly, never walk
    and so never announce one. That matches the need: the counter exists for
    hours-long library reindexes, and a project's compile closure is tens of
    files. Say so here so the next reader does not read the silence as a bug. }
  if FProgressTotal <= 0 then Exit;
  Inc(FProgressDone);
  Elapsed:= FProgressWatch.Elapsed.TotalSeconds;
  if (FProgressDone > 0) and (Elapsed > 0) then
  begin
    Eta:= Elapsed / FProgressDone * (FProgressTotal - FProgressDone);
    Writeln(ErrOutput, Format('  [%d/%d] %.0f%%  elapsed %s  ~%s left',
      [FProgressDone, FProgressTotal,
       FProgressDone / FProgressTotal * 100,
       HumanDuration(Elapsed), HumanDuration(Eta)]));
  end
  else
    Writeln(ErrOutput, Format('  [%d/%d]', [FProgressDone, FProgressTotal]));
end;

// Returns the TDocCommentRegion immediately preceding ASymStartLine
// (EndLine in [SymStartLine - 1 - AllowGap, SymStartLine - 1]), REJECTING that
// candidate when another declaration's StartLine sits strictly BETWEEN the
// region and ASymStartLine (Best.EndLine < L < ASymStartLine for some L in
// ASymStartLines) -- such a region belongs to the INTERVENING declaration,
// not this one. Without this check, two back-to-back declarations with no
// blank line between them (A documented, B immediately after) both matched
// A's doc-comment against the line-distance window alone, so `document
// --apply` treated A's block as B's *existing* doc and rewrote/duplicated it
// -- corrupting A's comment and stamping A's prose onto B (see
// adp2-docregion-fix-report.md). ASymStartLines must be sorted ascending
// (every symbol's StartLine in the file, including ASymStartLine's own); the
// scan below early-exits once L >= ASymStartLine, keeping the cost bounded
// even on files with many symbols. A region separated from ASymStartLine by
// only blank lines (no intervening declaration) is unaffected -- blank lines
// are never symbol start-lines.
// When ACaptureLoose is False, regions with Kind in [dckLooseLine, dckLooseBlock]
// are skipped entirely.
// Sentinel: Result.Kind = TDocCommentKind(-1) means no region found.
// v(ADP3 T3j review round 1): the window and the guard described above are no
// longer implemented here -- both delegate to DRagLint.Core.Model's
// DocRegionInGapWindow + NoDeclarationInGap, shared with the twin copy in
// DRagLint.Doc.Document and with DRagLint.Doc.Strip's `--strip` path, so the
// three attribution sites cannot drift. See the block comment on those
// functions for why that mattered (register S1).
function FindDocRegionAbove(ADocRegions: TList<TDocCommentRegion>; ASymStartLine: Integer;
  AAllowGap: Integer; ACaptureLoose: Boolean; const ASymStartLines: TArray<Integer>): TDocCommentRegion;
var
  I      : Integer          ;
  Best   : TDocCommentRegion;
  HasBest: Boolean          ;
begin
  HasBest:= False;
  // ADocRegions is sorted by StartLine ascending.
  for I:= 0 to ADocRegions.Count - 1 do
  begin
    // Skip loose regions when captureLooseComments is disabled.
    if (not ACaptureLoose) and (ADocRegions[I].Kind in [dckLooseLine, dckLooseBlock]) then Continue;
    // v(ADP3 T3j review round 1): the window is now the SHARED
    // DocRegionInGapWindow (DRagLint.Core.Model) -- same arithmetic, one
    // declaration. Control flow deliberately unchanged: pick the last region
    // satisfying the window, THEN apply the declaration guard to it below.
    if DocRegionInGapWindow(ADocRegions[I].EndLine, ASymStartLine, AAllowGap) then
    begin
      Best:= ADocRegions[I];
      HasBest:= True;
    end;
    if ADocRegions[I].StartLine > ASymStartLine then Break;
  end;
  // Intervening-declaration check: reject Best when some OTHER symbol starts
  // strictly between Best.EndLine and ASymStartLine. v(ADP3 T3j review round 1):
  // now the SHARED NoDeclarationInGap, which `document --strip` reads too -- the
  // T3j defect was Doc.Strip copying the window above without this guard.
  if HasBest and (not NoDeclarationInGap(Best.EndLine, ASymStartLine, ASymStartLines)) then
    HasBest:= False;
  if HasBest then Result:= Best
  else
  begin
    FillChar(Result, SizeOf(Result), 0);
    Result.Kind:= TDocCommentKind(-1);
  end;
end; // function

function TIndexer.ResolveEnclosingSymbolId(const ASymbols: TArray<TSymbol>;
  const AIdxToId: TDictionary<Integer, Int64>; ALine: Integer): Int64;
var
  I         : Integer;
  BestIdx   : Integer;
  BestStart : Integer;
  DbId      : Int64  ;
begin
  Result   := 0 ;
  BestIdx  := -1;
  BestStart:= 0 ; // any real ImplStartLine is > 0, so the first hit always wins
  for I:= 0 to High(ASymbols) do
  begin
    case ASymbols[I].Kind of
      skMethod, skFunction, skProcedure, skConstructor, skDestructor: ; // routine kinds
    else
      Continue;
    end;
    if ASymbols[I].ImplStartLine <= 0 then Continue;
    if (ALine >= ASymbols[I].ImplStartLine) and (ALine <= ASymbols[I].ImplEndLine) then
    begin
      // Innermost wins: a nested routine has a LARGER ImplStartLine than the
      // outer routine whose body encloses it.
      if ASymbols[I].ImplStartLine > BestStart then
      begin
        BestStart:= ASymbols[I].ImplStartLine;
        BestIdx  := I;
      end;
    end;
  end;
  if (BestIdx >= 0) and AIdxToId.TryGetValue(BestIdx, DbId) then Result:= DbId;
end; // function

{ v0.85 PERF INSTRUMENTATION -- set DRAGLINT_PROFILE=1 to get a per-phase
  breakdown on stderr at process exit. Diagnostic only: the counters cost two
  QueryPerformanceCounter reads per phase per file and are never printed unless
  the variable is set. Added because THREE successive guesses about where a
  library reindex spends its time (fsync, FK-cascade scans, the O(refs x symbols)
  enclosing-symbol scan) were each measured and each turned out not to be the
  dominant cost. Guessing was more expensive than measuring. }
var
  GProfParse, GProfDocScan, GProfSymbols, GProfRefs,
  GProfUses, GProfLiterals, GProfFacts, GProfCommit, GProfFiles,
  GProfPre, GProfOpenTx: Int64;

function ProfNow: Int64; inline;
begin
  Result:= TStopwatch.GetTimeStamp;
end;

{ v0.85 PERF -- the O(refs x symbols) fix.

  ResolveEnclosingSymbolId scans every symbol in the file to attribute ONE
  reference, and it is called once per reference. Across the Win32 library index
  that is sum(symbols x refs) = 13,034,967,133 unit operations, which at the
  measured 1.34 us/unit accounts for essentially the whole 17,493 s run. The same
  corpus PARSES in ~0.4% of that time, and the identical row volume INSERTS into
  SQLite in ~0.1% -- so this loop, not tree-sitter and not the database, is what
  a library reindex spends its life doing.

  This paints a line -> enclosing-symbol-id map once per file instead. Building it
  costs the sum of routine body lengths (O(file lines x nesting depth)); each
  reference then costs one array index.

  Semantics are preserved exactly, including the tie-break: the original takes a
  new best only on a STRICTLY greater ImplStartLine, so among routines sharing a
  start line the first in array order wins. Tracking BestStart per line and
  comparing with '>' while iterating symbols in their original order reproduces
  that, and needs no sort. A symbol missing from AIdxToId maps to 0, exactly as
  the original's failed TryGetValue did. }
function BuildEnclosingLineMap(const ASymbols: TArray<TSymbol>;
  const AIdxToId: TDictionary<Integer, Int64>; ALineCount: Integer): TArray<Int64>;
var
  BestStart: TArray<Integer>;
  I, L, Hi : Integer       ;
  DbId     : Int64         ;
begin
  if ALineCount < 1 then ALineCount:= 1;
  SetLength(Result   , ALineCount + 1); { SetLength zero-fills: 0 = "in no routine" }
  SetLength(BestStart, ALineCount + 1);
  Hi:= High(Result);
  for I:= 0 to High(ASymbols) do
  begin
    case ASymbols[I].Kind of
      skMethod, skFunction, skProcedure, skConstructor, skDestructor: ; // routine kinds
    else
      Continue;
    end;
    if ASymbols[I].ImplStartLine <= 0 then Continue;
    if not AIdxToId.TryGetValue(I, DbId) then DbId:= 0;
    L:= ASymbols[I].ImplStartLine;
    while (L <= ASymbols[I].ImplEndLine) and (L <= Hi) do
    begin
      if ASymbols[I].ImplStartLine > BestStart[L] then
      begin
        BestStart[L]:= ASymbols[I].ImplStartLine;
        Result   [L]:= DbId;
      end;
      Inc(L);
    end;
  end;
end; // function

function TIndexer.SliceBodyLines(const ALines: TArray<string>; AFromLine, AToLine: Integer): TArray<string>;
var
  Lo, Hi, J: Integer;
begin
  Result:= nil;
  if Length(ALines) = 0 then Exit;
  Lo:= AFromLine;
  Hi:= AToLine;
  if Lo < 1 then Lo:= 1;
  if Hi > Length(ALines) then Hi:= Length(ALines);
  if Hi < Lo then Exit; // empty (or inverted) range after clipping
  SetLength(Result, Hi - Lo + 1);
  for J:= Lo to Hi do Result[J - Lo]:= ALines[J - 1];
end; // function

procedure TIndexer.IndexFile(const AFilePath: string);
var
  Parser        : IParser                    ;
  Source        : TBytes                     ; { raw on-disk bytes: sha/mtime/up-to-date }
  Utf8          : TBytes                     ; { v0.86: transcoded UTF-8 fed to parser/slices }
  ParseBytes    : TBytes                     ; { PP-Task-9: bytes actually parsed (preprocessed when enabled, else = Utf8) }
  SourceText    : string                     ;
  Sha           : string                     ;
  Mtime         : Int64                      ;
  ParseRes      : TParseResult               ;
  Token         : TFileTxToken               ;
  Sym           : TSymbol                    ;
  IdxToId       : TDictionary<Integer, Int64>;
  I             : Integer                    ;
  ResolvedParent: Int64                      ;
  NewSymId      : Int64                      ;
  DocRegions    : TList<TDocCommentRegion>   ;
  DocRegion     : TDocCommentRegion          ;
  ParsedDoc     : TParsedDoc                 ;
  Lit           : TStringLiteral             ;
  Encl          : TSymbol                    ;
  SourceLines   : TArray<string>             ; { v(ADP2 T2): SourceText split once, reused per routine's facts pass }
  Facts         : TSymbolFacts               ; { v(ADP2 T2) }
  FactsBody     : TArray<string>             ; { v(ADP2 T2) }
  SymStartLines : TArray<Integer>            ; { adp2-docregion-fix: every symbol's StartLine, sorted ascending -- lets FindDocRegionAbove reject a region separated from its symbol by an intervening declaration }
  EnclosingByLine: TArray<Int64>             ; { v0.85 perf: line -> enclosing routine's db id, built once per file (see BuildEnclosingLineMap) }
begin
  Parser:= ParserFor(ExtractFileExt(AFilePath));
  if Parser = nil then Exit;
  { The file is IN SCOPE from here on, and recorded as such BEFORE any of the
    skips below. Out-of-scope eviction deletes indexed files that are not in this
    list, so every reason to skip a file that is nonetheless part of the scope --
    the size guard, the incremental up-to-date check, a parse failure -- must be
    on this side of the record, or refreshing an index would delete the very
    files it declined to re-parse. Only "no parser claims this extension" stays
    out, and such a file never had a row to lose. }
  if not FVisitedKeys.ContainsKey(LowerCase(AFilePath)) then
  begin
    FVisitedKeys.Add(LowerCase(AFilePath), True);
    FVisited.Add(AFilePath);
  end;
  { v0.46: file-size guard -- skip files that would overflow the tree-sitter
    native stack. The segfault is not catchable by Delphi (it is a native
    stack overflow, not an OS exception the RTL wraps). Default: 2048 KB.
    0 = unlimited (caller explicitly opted out). }
  if FWalkFilter.MaxFileKB > 0 then
  begin
    var FileSize: Int64;
    try
      FileSize:= TFile.GetSize(AFilePath);
    except
      FileSize:= 0;
    end;
    if FileSize > Int64(FWalkFilter.MaxFileKB) * 1024 then
    begin
      Writeln(Format('  SKIP %s: %d KB exceeds parse limit (%d KB)', [AFilePath, FileSize div 1024, FWalkFilter.MaxFileKB]));
      Exit;
    end;
  end;
  var TPre: Int64:= ProfNow;
  Source:= TFile.ReadAllBytes(AFilePath);
  // Sha/Mtime/up-to-date stay computed over the RAW on-disk bytes so file
  // identity + the incremental-skip contract are byte-identical to before the
  // v0.86 encoding fix (changing the sha basis would invalidate every already
  // indexed file's stored sha -> forced mass reindex).
  Sha:= THashSHA2.GetHashString(TEncoding.ANSI.GetString(Source));
  Mtime:= DateTimeToUnix(TFile.GetLastWriteTime(AFilePath), False);
  // v0.4: incremental skip. If the file's already in the DB with the same
  // mtime and sha256, nothing to do - the parser would emit the same
  // symbols. Saves a parse + the per-file transaction.
  //
  // INBOX 2.3: "the parser would emit the same symbols" is only true while the
  // PARSER is the same. The test above keys on FILE identity (path+mtime+sha)
  // and knows nothing about what this build would produce, so after an engine
  // upgrade an unchanged file was skipped FOREVER and kept its older, poorer
  // parse -- a stale 0-match that is indistinguishable from "this symbol does
  // not exist". Reported against a procedure the index had never seen because
  // the DB predated the parser that could extract it; `touch` was the only
  // known workaround. FForceReparse is set for the whole run when the caller
  // detects an indexer-fingerprint change (or passes --force-reparse).
  { PER-FILE RESUME. When the run was forced ONLY because the engine fingerprint
    changed, a file already stamped with the CURRENT fingerprint has already been
    re-parsed by this engine -- by an earlier, interrupted run -- so the ordinary
    up-to-date test is trustworthy again for it. FResumeFingerprint is '' for
    --force-reparse and --rebuild, which therefore skip nothing, and '' can never
    equal a stored stamp because FileIndexedFingerprint returns '' for
    "unknown". Both halves fail toward re-parsing. }
  var MayResume: Boolean:= (FResumeFingerprint <> '') and
                           SameStr(FStore.FileIndexedFingerprint(AFilePath), FResumeFingerprint);
  if ((not FForceReparse) or MayResume) and FStore.FileIsUpToDate(AFilePath, Mtime, Sha) then
  begin
    Inc(FSkippedUpToDate);
    Exit;
  end;
  { COUNTED HERE, BEFORE THE PARSE, not at the commit. This counter's only job is
    to answer "could the database have changed?", and the caller uses a zero to
    SKIP the four whole-DB resolve passes. Over-counting costs a wasted pass;
    under-counting silently serves stale ancestry / call edges. Every exit below
    this line -- a parse failure, a rolled-back file transaction -- has already
    opened the door to a write, so the increment belongs above all of them. }
  Inc(FParsedFiles);
  // v0.86 (Task 3): transcode ANSI/UTF-16 sources to valid UTF-8 before the
  // parse/slice pipeline (which assumes UTF-8). A valid CP1252 file (0xAE/0xA9
  // in a resourcestring -- the SOFTWID.PAS class) was SKIPPED here with
  // EEncodingError; now it parses. Downstream slice helpers see UTF-8.
  Utf8:= EnsureUtf8Bytes(Source);
  // PP-Task-9: when preprocessing is enabled, resolve compiler-directive
  // branches per the active define profile BEFORE parsing. Preprocess blanks
  // inactive-branch and directive bytes to spaces (LF preserved) and returns a
  // buffer of IDENTICAL byte length -- the offset-identity invariant -- so every
  // symbol/ref span the parser emits still maps 1:1 back to the original file
  // with NO source map. A per-file exception must NOT hard-fail the whole run:
  // log once, then index the RAW UTF-8 for that file (pre-Task-9 behaviour).
  if FPreprocessEnabled then
  begin
    try
      // v(2026-08-16, INBOX-parse-error-shellshock-units): 'defines-only', NOT
      // the 2-arg overload. That overload uses IncludeMode 'off', which blanks
      // an {$I} include AND discards its {$DEFINE}s -- so a unit taking its
      // feature switches from a shared .inc (the standard legacy Delphi idiom)
      // evaluated its own {$IFDEF}s against defines it never received, and
      // silently indexed the WRONG BRANCH. It surfaced as a parse error only in
      // the three ShellShock units, whose dead branch happens to contain a
      // deliberate `!! Error:` breaker; everywhere else it was invisible.
      //
      // BaseDir is the unit's own directory so {$I SsDefine.inc} resolves as a
      // sibling; NearSearch stays on for the widened search. Include text is
      // still never spliced -- 'defines-only' contributes defines only, so the
      // offset-identity invariant is untouched.
      var PpOpts: TPPOptions:= TPPOptionsDefault;
      PpOpts.Profile    := FProfile;
      PpOpts.IncludeMode:= 'defines-only';
      PpOpts.BaseDir    := TPath.GetDirectoryName(AFilePath);
      ParseBytes:= Preprocess(Utf8, PpOpts);
    except
      on E: Exception do
      begin
        LogPreprocessFallbackOnce(AFilePath, E);
        ParseBytes:= Utf8;
      end;
    end;
  end
  else
    ParseBytes:= Utf8;
  Inc(GProfPre, ProfNow - TPre);
  var TProf: Int64:= ProfNow;
  ParseRes:= Parser.Parse(ParseBytes, AFilePath);
  Inc(GProfParse, ProfNow - TProf); Inc(GProfFiles);
  // v0.16: scan doc-comment regions from the source text once per file
  // so we can associate them with symbols by line proximity below.
  // Decode from the bytes the PARSER ACTUALLY SAW (ParseBytes -- preprocessed
  // when enabled, else the transcoded UTF-8) so doc-comment text and symbol line
  // positions agree. Blanking preserves byte length + LF, so the line structure
  // is identical to the raw file; blanked regions carry no doc-comments. For
  // pure-ASCII files with preprocessing off this is the prior UTF-8 decode.
  SourceText:= TEncoding.UTF8.GetString(ParseBytes);
  { Split ONCE here rather than just before the facts pass: BuildEnclosingLineMap
    (called earlier, in the refs loop) needs the line count to size its map, and
    the facts pass below reuses the same array. }
  SourceLines:= SourceText.Split([#10]);
  TProf:= ProfNow;
  DocRegions:= TDocCommentScanner.Scan(SourceText);
  Inc(GProfDocScan, ProfNow - TProf);
  try
    TProf:= ProfNow;
    Token:= FStore.OpenFileTx(AFilePath, Mtime, Sha, Parser.LanguageName);
    // v0.16: clear stale doc rows for this file before emitting fresh ones
    // (OpenFileTx already cleared symbols and refs).
    FStore.DeleteFileDocs(Token.FileId);
    Inc(GProfOpenTx, ProfNow - TProf);
    IdxToId:= TDictionary<Integer, Int64>.Create;
    try
      try
        // adp2-docregion-fix: every symbol's StartLine in this file, sorted
        // ascending, so FindDocRegionAbove can reject a doc region that
        // actually belongs to an INTERVENING declaration (see its header
        // comment). Built once per file, not once per symbol.
        SetLength(SymStartLines, Length(ParseRes.Symbols));
        for I:= 0 to High(ParseRes.Symbols) do
          SymStartLines[I]:= ParseRes.Symbols[I].StartLine;
        TArray.Sort<Integer>(SymStartLines);
        TProf:= ProfNow;
        for I:= 0 to High(ParseRes.Symbols) do
        begin
          Sym:= ParseRes.Symbols[I];
          // Translate in-array parent index to actual DB id
          if (Sym.ParentId >= 0) and IdxToId.TryGetValue(Integer(Sym.ParentId), ResolvedParent) then Sym.ParentId:= ResolvedParent
          else Sym.ParentId:= -1;
          NewSymId:= FStore.UpsertSymbol(Token, Sym);
          IdxToId.Add(I, NewSymId);
          // v0.16: associate doc comment region to this symbol.
          // Task 13: AllowBlankLineGap and CaptureLooseComments come from
          // .drag-lint.json "docs" section via FDocConfig.
          DocRegion:= FindDocRegionAbove(DocRegions, Sym.StartLine, FDocConfig.AllowBlankLineGap, FDocConfig.CaptureLooseComments, SymStartLines);
          if DocRegion.Kind <> TDocCommentKind(-1) then
          begin
            ParsedDoc:= TDocCommentParser.Dispatch(DocRegion);
            if ParsedDoc.HasContent then FStore.UpsertSymbolDoc(Token, NewSymId, ParsedDoc);
          end;
        end; // for
        Inc(GProfSymbols, ProfNow - TProf);
        TProf:= ProfNow;
        // v13 (v0.82): attribute each ref to the innermost routine whose impl
        // body contains its StartLine (0 when in no body). IdxToId is in scope
        // (symbols already inserted with real ids), so this is a pure in-memory
        // resolution -- no DB round-trips.
        //
        // v0.85 PERF: build a LINE -> enclosing-symbol-id map once per file and
        // index into it, instead of calling ResolveEnclosingSymbolId per ref.
        // That call scanned EVERY symbol in the file for EVERY reference, i.e.
        // O(refs x symbols) per file. Measured over the whole Win32 library run:
        // sum(symbols x refs) = 13,034,967,133 units against a 17,493 s wall
        // clock -- 1.34 us per unit, which accounts for essentially the entire
        // run. For scale, parsing the same corpus costs ~0.4% of that, and
        // inserting the same row volume into SQLite costs ~0.1%. The map is
        // O(sum of routine body lengths) to build and O(1) per ref.
        EnclosingByLine:= BuildEnclosingLineMap(ParseRes.Symbols, IdxToId, Length(SourceLines) + 2);
        for I:= 0 to High(ParseRes.References) do
        begin
          var Ref := ParseRes.References[I];
          if (Ref.StartLine >= 0) and (Ref.StartLine <= High(EnclosingByLine)) then
            Ref.EnclosingSymbolId:= EnclosingByLine[Ref.StartLine]
          else
            { Out of the mapped range (a ref past the last source line -- should not
              happen, but the old path handled any line, so keep that contract). }
            Ref.EnclosingSymbolId:= ResolveEnclosingSymbolId(ParseRes.Symbols, IdxToId, Ref.StartLine);
          FStore.UpsertReference(Token, Ref);
        end;
        Inc(GProfRefs, ProfNow - TProf);
        TProf:= ProfNow;
        for I:= 0 to High(ParseRes.DiBindings) do FStore.UpsertDiBinding(Token, ParseRes.DiBindings[I]);
        { v0.40.4: wipe-and-rewrite uses for this file so we never carry
          stale rows. DeleteUnitUsesForFile must run inside the open
          transaction to ensure consistency on rollback. }
        FStore.DeleteUnitUsesForFile(Token.FileId);
        for I:= 0 to High(ParseRes.UsesEntries) do FStore.UpsertUnitUse(Token, ParseRes.UsesEntries[I]);
        // v10: text-content index. Resolve each literal's enclosing symbol by line,
        // then persist. Per-file delete keeps re-index idempotent (FTS cascades via triggers).
        Inc(GProfUses, ProfNow - TProf);
        TProf:= ProfNow;
        FStore.DeleteStringLiteralsForFile(Token.FileId);
        for I:= 0 to High(ParseRes.Literals) do
        begin
          Lit:= ParseRes.Literals[I];
          Lit.FileId:= Token.FileId;
          Encl:= FStore.FindContainingSymbol(Token.FileId, Lit.StartLine);
          if Encl.Id > 0 then Lit.SymbolId:= Encl.Id;
          FStore.UpsertStringLiteral(Token, Lit);
        end;
        // v(ADP2 T2): index-time analysis facts -- one symbol_facts row per
        // routine-kind symbol that HAS a body (ImplStartLine > 0). Runs last
        // (after refs/di-bindings/uses/literals) but still inside the open
        // file transaction, so a facts-pass failure rolls back atomically
        // with the rest of the file instead of leaving a half-written row.
        // SourceLines is split ONCE per file (on #10 only, matching
        // TDocCommentScanner's own line-counting convention, so 1-based
        // ImplStartLine/ImplEndLine index it correctly) and reused for every
        // symbol -- no per-symbol re-parse, no per-symbol disk re-read.
        // Task 2 writes an EMPTY-but-Present row; Tasks 3-8 fill in each fact
        // field inside TSymbolFactsAnalyzer.Analyze. (ADP2 T4 fix wave: the
        // facts loop below is the one exception to "never touching this call
        // site" -- it now resolves each Sym's real Id/FileId/ParentId in
        // place, just before calling Analyze, so Analyze/AnalyzeReadsWrites no
        // longer re-resolve identity via 3 DB round-trips per routine; no
        // fact-computation logic changed -- see the comment at the mutation
        // site below.) Invalidation is automatic: OpenFileTx (above) already
        // DELETEd this file's OLD symbol rows, and symbol_facts.symbol_id
        // REFERENCES symbols(id) ON DELETE CASCADE with FK enforcement ON
        // (see TSQLiteSymbolStore.Create), so a stale facts row can never
        // outlive its symbol.
        { SourceLines was split once, right after SourceText was decoded. }
        Inc(GProfLiterals, ProfNow - TProf);
        TProf:= ProfNow;
        for I:= 0 to High(ParseRes.Symbols) do
        begin
          Sym:= ParseRes.Symbols[I];
          if not (Sym.Kind in [skFunction, skProcedure, skMethod, skConstructor, skDestructor]) then Continue;
          if Sym.ImplStartLine <= 0 then Continue;
          if not IdxToId.TryGetValue(I, NewSymId) then Continue;
          // v(ADP2 T4 fix wave): resolve Sym's real identity BEFORE handing it
          // to Analyze, root-causing the 3-DB-round-trip workaround
          // AnalyzeReadsWrites used to need (see its header comment, unit
          // DRagLint.Doc.SymbolFacts.pas). Sym is a RECORD (value type)
          // freshly reloaded from ParseRes.Symbols[I] two lines up, so
          // mutating it here only affects this local copy passed to Analyze --
          // it never writes back into ParseRes.Symbols and cannot corrupt any
          // other pass (the ref-resolution loop above already finished with
          // ParseRes.Symbols by this point). ParentId is translated from its
          // in-array index using the SAME pattern the symbols loop above uses
          // (IdxToId is fully populated by now, so this is a pure in-memory
          // lookup, never a DB round-trip) -- Tasks 5-8 can trust
          // Sym.Id/.FileId/.ParentId directly, the same way this fix lets T4
          // trust them.
          Sym.Id:= NewSymId;
          Sym.FileId:= Token.FileId;
          if (Sym.ParentId >= 0) and IdxToId.TryGetValue(Integer(Sym.ParentId), ResolvedParent) then Sym.ParentId:= ResolvedParent
          else Sym.ParentId:= -1;
          FactsBody:= SliceBodyLines(SourceLines, Sym.ImplStartLine, Sym.ImplEndLine);
          Facts:= TSymbolFactsAnalyzer.Analyze(Sym, AFilePath, FactsBody, FStore);
          Facts.SymbolId:= NewSymId;
          FStore.PutSymbolFacts(Facts);
        end;
        Inc(GProfFacts, ProfNow - TProf);
        TProf:= ProfNow;
        FStore.CommitFileTx(Token);
        Inc(GProfCommit, ProfNow - TProf);
        ReportProgress(AFilePath, Length(ParseRes.Symbols), Length(ParseRes.References), Length(ParseRes.Diagnostics));
        for var Diag in ParseRes.Diagnostics do
          Writeln('    DIAG: ' + Diag);
      except
        on E: Exception do
        begin
          FStore.RollbackFileTx(Token);
          Writeln(Format('  ERROR indexing %s: %s', [AFilePath, E.Message]));
        end;
      end; // try
    finally
      // v(ADP2 T3): bound the AST-parse-cache's memory across a large corpus.
      // TSymbolFactsAnalyzer.Analyze (called once per routine, above) reads
      // AFilePath's tree via TAstParseCache.Get, which memoizes per file --
      // the FIRST routine in this file parses it, every later routine in the
      // SAME file reuses the cached tree (one parse per FILE, not per
      // routine). Clearing here, AFTER the facts loop has finished with every
      // routine in ParseRes.Symbols (success or rollback), releases that
      // tree before the walk moves to the next file, so a whole-tree index
      // run never accumulates one tree per file. Safe even on the exception
      // path above: Clear only frees cached trees, it does not touch FStore.
      TAstParseCache.Clear;
      IdxToId.Free;
      // v(ADP3 T4e): flush the progress stream once per file, so an abnormal
      // termination cannot swallow COMPLETED lines from the tail of this log.
      //
      // PRECONDITION, and it is not decorative (register K54): what this buys
      // is "no completed line is lost", NOT "the file always ends on a line
      // terminator". The RTL still empties the 128-byte buffer the instant it
      // fills, so a SINGLE emitted line longer than 128 bytes reaches disk in
      // 128-byte pieces and an outside reader can see it cut mid-line no matter
      // how often this flushes -- and the `DIAG:` lines of the very corpus this
      // was diagnosed on DO exceed 128 (`    DIAG: ` + a DevExpress or Raize
      // source path + a parser message). The same holds for one file emitting a
      // progress line plus enough DIAG lines to total over 128 bytes between
      // two flushes. What the flush guarantees unconditionally is that a
      // completed burst is not still SITTING in the buffer when the process
      // dies -- which is what destroyed the evidence below.
      //
      // Delphi buffers `Output` through TTextRec.BufPtr, and TTextBuf is
      // `array[0..127]` -- 128 bytes. A buffered stream reaches the disk only
      // when that buffer FILLS, or when the RTL closes Output during a normal
      // _Halt0. A process that dies WITHOUT _Halt0 (TerminateProcess,
      // ExitProcess, a fault) therefore loses whatever is still in the buffer,
      // and the log ends wherever the last 128-byte boundary fell -- mid-line,
      // usually mid-token.
      //
      // That is not hypothetical: it destroyed the evidence in
      // docs\INBOX-index-all-win32-library-rebuild-aborts.md. All three
      // surviving logs of that report's five aborted runs stop mid-token, and
      // the drag-lint-written byte count of each is an EXACT multiple of 128
      // (120448 = 941*128, 413312 = 3229*128, 23936 = 187*128). The report
      // read its last visible line as the crash site; it was only the last
      // full buffer. Up to 127 bytes -- one to two whole files' worth of
      // progress -- were silently discarded on every run.
      //
      // Flushing HERE rather than inside ReportProgress is deliberate: this
      // finally is the single per-file exit point, so it covers the success
      // path (progress line + its DIAG lines) and the `ERROR indexing` path
      // alike, exactly once per file, and it cannot be bypassed by the except
      // branch above. Cost is one <=128-byte WriteFile per file, which is
      // nothing beside parsing it. Unguarded, matching the existing Flush
      // sites (DRagLint.CLI.pas, DRagLint.MCP.Server.pas): a stdout that
      // cannot be written is not a condition this loop can meaningfully
      // continue through.
      // Guarded by tests\autotest\run_index_progress_flush.ps1.
      Flush(Output);
    end; // try
  finally
    DocRegions.Free;
  end; // try
end; // procedure

// v0.42: SQL files are scanned only when they match the MS*.SQL convention
// (the Micronite Firebird DDL scripts) -- per user, those are the only SQL
// files worth indexing. Every other .sql is skipped so the index isn't
// polluted by ad-hoc query scripts. Non-.sql files always pass this gate.
// v0.45: gate is conditional on FWalkFilter.SqlOnlyMS; when False all SQL pass.
function TIndexer.SqlFileAllowedFilter(const APath: string): Boolean;
var
  Name: string;
begin
  if not SameText(ExtractFileExt(APath), '.sql') then Exit(True);
  if not FWalkFilter.SqlOnlyMS then Exit(True);
  Name:= ExtractFileName(APath);
  Result:= StartsText('MS', Name);
end;

function TIndexer.ShouldPruneDir(const ADir: string): Boolean;
{ v0.42: directory-level pruning -- decided BEFORE we descend, so an excluded
  subtree is never enumerated. This is what makes a full C:\Projects scan
  practical: __history / BACKUP_ALL / .git / node_modules / .scanignore'd and
  already-indexed (--exclude-under) trees are skipped wholesale rather than
  walked and then filtered file-by-file (which took ~8.7h over C:\Projects).
  v0.45: after built-in checks, also prune dirs whose base name matches any
  GlobalExclude or SectionExclude glob from the walk filter. }
const
  PRUNE_NAMES: array[0..5] of string = ( '__history', '__recovery', '.git', '.svn', '.hg', 'node_modules');
var
  Name: string;
  PN  : string;
begin
  Result:= True;
  Name:= LowerCase(ExtractFileName(ExcludeTrailingPathDelimiter(ADir)));
  for PN in PRUNE_NAMES do
    if Name = PN then Exit;
  if Pos('backup', Name) > 0 then Exit; { *BACKUP* folders }
  if IsUnderExcludeRoot(IncludeTrailingPathDelimiter(ADir)) then Exit;
  if TFile.Exists(TPath.Combine(ADir, '.scanignore')) then Exit; { marker file }
  { v0.45: glob-based directory exclusion (uses base name only, case-insensitive).
    Re-use Name (already lower-cased above); TGlob.MatchesAny is case-insensitive. }
  if TGlob.MatchesAny(Name, FWalkFilter.GlobalExclude ) then Exit;
  if TGlob.MatchesAny(Name, FWalkFilter.SectionExclude) then Exit;
  Result:= False;
end;

procedure TIndexer.WalkAndIndex(const ADir: string; ARecursive: Boolean);
{ v0.45: precedence order for filtering:
    1. Built-in dir prunes (ShouldPruneDir -- __history, .git, backup, etc.)
    2. GlobalExclude / SectionExclude globs on dir names (inside ShouldPruneDir)
    3. File-level glob excludes (GlobalExclude + SectionExclude on file base name)
    4. IncludeOnly allow-list on file base name
    5. .gitignore/.hgignore rules via FIgnoreStack (highest precedence)
  PushDir/PopDir symmetry: we ONLY push when we are about to descend
  (i.e. ShouldPruneDir returned False). Pruned dirs are never pushed. }
var
  Files    : TArray<string>;
  SubDirs  : TArray<string>;
  F        : string        ;
  D        : string        ;
  FBaseName: string        ;
  DBaseName: string        ;
begin
  if ShouldPruneDir(ADir) then Exit;

  { v0.45: load ignore files for this directory before listing its contents. }
  if FIgnoreStack <> nil then FIgnoreStack.PushDir(ADir);
  try
    { Files directly in this directory whose extension a parser handles. }
    try
      Files:= TDirectory.GetFiles(ADir, '*', TSearchOption.soTopDirectoryOnly);
    except
      SetLength(Files, 0);
    end;
    for F in Files do
    begin
      if ParserFor(ExtractFileExt(F)) = nil then Continue;
      if not SqlFileAllowedFilter(F) then Continue;
      FBaseName:= ExtractFileName(F);
      { v0.45: GlobalExclude + SectionExclude on file base name. }
      if TGlob.MatchesAny(FBaseName, FWalkFilter.GlobalExclude ) then Continue;
      if TGlob.MatchesAny(FBaseName, FWalkFilter.SectionExclude) then Continue;
      { v0.45: IncludeOnly allow-list -- skip if non-empty and no match. }
      if (Length(FWalkFilter.IncludeOnly) > 0) and (not TGlob.MatchesAny(FBaseName, FWalkFilter.IncludeOnly)) then Continue;
      { v0.45: ignore-file gate (highest precedence). }
      if (FIgnoreStack <> nil) and FIgnoreStack.IsIgnored(F, False) then Continue;
      { Count-only pass: this file passed every admission rule above, so it is
        exactly one unit of the denominator. Counting HERE rather than at the
        top of the loop is the whole point -- a file excluded by a glob or an
        ignore rule has already been skipped by a Continue and must not count. }
      if FCountOnly then
      begin
        Inc(FProgressTotal);
        Continue;
      end;
      try
        IndexFile(F);
      except
        on E: Exception do Writeln(Format('  SKIP %s: %s: %s', [F, E.ClassName, E.Message]));
      end;
    end; // for

    if not ARecursive then Exit;

    try
      SubDirs:= TDirectory.GetDirectories(ADir, '*', TSearchOption.soTopDirectoryOnly);
    except
      SetLength(SubDirs, 0);
    end;
    for D in SubDirs do
    begin
      { v0.45: ignore-file gate for dirs (before descending). }
      DBaseName:= ExtractFileName(ExcludeTrailingPathDelimiter(D));
      if (FIgnoreStack <> nil) and FIgnoreStack.IsIgnored(DBaseName, True) then Continue;
      WalkAndIndex(D, True); { ShouldPruneDir gate is applied per subdir }
    end;
  finally
    if FIgnoreStack <> nil then FIgnoreStack.PopDir;
  end; // try
end; // procedure

procedure TIndexer.IndexFolder(const APath: string; ARecursive: Boolean);
begin
  { Pass 1 -- count only, to learn the denominator. }
  FProgressTotal:= 0;
  FProgressDone := 0;
  FCountOnly    := True;
  try
    WalkAndIndex(APath, ARecursive);
  finally
    FCountOnly:= False;   { in a finally: an exception mid-count must not leave
                            the indexer in a mode where it silently indexes
                            nothing on the next call }
  end;
  if FProgressTotal > 0 then
    Writeln(ErrOutput, Format('  walking %d file(s) under %s', [FProgressTotal, APath]));
  FProgressWatch:= TStopwatch.StartNew;
  { Pass 2 -- index for real. }
  WalkAndIndex(APath, ARecursive);
end;

{ Prints the per-phase breakdown collected above. Opt-in via DRAGLINT_PROFILE so
  a normal run is byte-identical on stdout; the report goes to stderr. }
procedure WriteIndexProfile;
var
  Freq: Double;
  procedure Line(const AName: string; ATicks: Int64);
  begin
    Writeln(ErrOutput, Format('  %-14s %8.2f s', [AName, ATicks / Freq]));
  end;
begin
  if GetEnvironmentVariable('DRAGLINT_PROFILE') = '' then Exit;
  if GProfFiles = 0 then Exit;
  Freq:= TStopwatch.Frequency;
  Writeln(ErrOutput, Format('INDEX PROFILE (%d files)', [GProfFiles]));
  Line('read/pre'  , GProfPre     );
  Line('parse'     , GProfParse   );
  Line('open-tx'   , GProfOpenTx  );
  Line('doc-scan'  , GProfDocScan );
  Line('symbols'   , GProfSymbols );
  Line('refs'      , GProfRefs    );
  Line('uses/di'   , GProfUses    );
  Line('literals'  , GProfLiterals);
  Line('facts'     , GProfFacts   );
  Line('commit'    , GProfCommit  );
  Line('TOTAL'     , GProfPre + GProfOpenTx + GProfParse + GProfDocScan + GProfSymbols + GProfRefs +
                     GProfUses + GProfLiterals + GProfFacts + GProfCommit);
end;

initialization

finalization
  WriteIndexProfile;

end.
