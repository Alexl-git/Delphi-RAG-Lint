unit DRagLint.Charts.Source;

{ Freshness-gated source text for the ported chart emitters (spec P1, P5). Each
  routine ports the named function in charts\src\Emit-Common.ps1 (line numbers of
  2026-10-10). THE RULE they carry (R11 of PLAN-last-four-verbs): nothing reads a
  source line BY COLUMN without first proving the file on disk is the file that
  was indexed -- a stale file is reported as Stale, never read. The exception
  texts are the PS `throw` texts, verbatim. }

interface

uses
  System.SysUtils
  , System.Generics.Collections
  , System.RegularExpressions
  , DRagLint.Charts.Index
  ;

type
  /// <summary>The comment-stripped text around ONE ref. Port of the Get-SourceContext result.</summary>
  /// <remarks>
  /// STALE IS A RESULT, NOT AN ERROR: when the file fails the freshness gate every
  /// text field is '' (the PS `$null`), Following is empty and Stale is True. A caller renders
  /// `[stale source]` and must not classify. PS trap closed: `$null` has no Delphi string
  /// counterpart, so Stale -- not an empty Token -- is the only test for staleness (a fresh
  /// ref inside a comment also reads a blank Token).
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Charts.Exceptions.pas) ?, declaration (DRagLint.Charts.Source.pas) ?, DRagLint.Charts.Exceptions.ExceptionRefClass (DRagLint.Charts.Exceptions.pas) ?, DRagLint.Charts.Source.TSourceReader.ContextOfLines (DRagLint.Charts.Source.pas), DRagLint.Charts.Source.TSourceReader.SourceContext (DRagLint.Charts.Source.pas)</para>
  /// <para>Used in units: DRagLint.Charts.Exceptions, DRagLint.Charts.Source</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TSourceContext = record
    /// <summary>The indexed path asked about (never the override target).</summary>
    Path      : string;
    /// <summary>The 1-based line asked about.</summary>
    Line      : Integer;
    /// <summary>True when the file on disk does not hash to the indexed sha256.</summary>
    Stale     : Boolean;
    /// <summary>Stripped text left of the ref, untrimmed.</summary>
    Before    : string;
    /// <summary>Stripped text AT the ref; blank when the ref sits inside a comment or string.</summary>
    Token     : string;
    /// <summary>Stripped text right of the ref, untrimmed.</summary>
    After     : string;
    /// <summary>The previous non-blank stripped line, trimmed; '' when none.</summary>
    PrevLine  : string;
    /// <summary>PrevLine's 1-based number; 0 when none.</summary>
    PrevLineNo: Integer;
    /// <summary>The next pFollowing stripped lines, untrimmed, for a statement that continues.</summary>
    Following : TArray<string>;
  end;

  /// <summary>Reads indexed source files only after proving they are the files the index saw.</summary>
  /// <remarks>
  /// Holds per-run caches (file shas, freshness verdicts, stripped lines) exactly as the
  /// PS held them in $script: variables, so one reader answers for one index and one run: a test
  /// that manufactures a changed file must use a fresh read path (or a fresh reader). The index
  /// is NOT owned. Not thread-safe; one owning thread.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.Charts.Q.Consumers.TConsumersChart.Create (DRagLint.Charts.Q.Consumers.pas), DRagLint.Charts.Q.ExceptionPaths.TExceptionPathsChart.Create (DRagLint.Charts.Q.ExceptionPaths.pas), DRagLint.Charts.Q.FeedsFrom.TFeedsFromChart.Create (DRagLint.Charts.Q.FeedsFrom.pas), DRagLint.Charts.Q.LandsWhere.TLandsWhereChart.Create (DRagLint.Charts.Q.LandsWhere.pas), DRagLint.Charts.Q.RoundTrip.TRoundTripRun.Create (DRagLint.Charts.Q.RoundTrip.pas) (+18 more)</para>
  /// <para>Used in units: DRagLint.Charts.Chain, DRagLint.Charts.Exceptions, DRagLint.Charts.Q.Consumers, DRagLint.Charts.Q.ExceptionPaths, DRagLint.Charts.Q.FeedsFrom, DRagLint.Charts.Q.LandsWhere, DRagLint.Charts.Q.RoundTrip, DRagLint.Charts.Sql, DRagLint.Charts.Trace.Anchor, DRagLint.Charts.Trace.Calc, DRagLint.Charts.Trace.Walk</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TSourceReader = class
  private
    FIndex    : TChartsIndex;
    FShas     : TDictionary<string, string>;
    FIds      : TDictionary<string, Integer>;
    FPaths    : TDictionary<string, string>;
    FOverrides: TDictionary<string, string>;
    FFresh    : TDictionary<string, Boolean>;
    FStripped : TDictionary<string, TArray<string>>;
    /// <returns><!-- drag-lint:auto -->string -- Observed: ''; R.S('file').</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Charts.Source.TSourceReader.SourceFresh (DRagLint.Charts.Source.pas)</para>
    /// <para>Calls: DRagLint.Charts.Index.TChartsIndex.Query, DRagLint.Charts.Index.TIndexRow.S, SameText</para>
    /// <para>Reads: FIndex</para>
    /// <seealso cref="DRagLint.Charts.Index.TChartsIndex.Query"/>
    /// <seealso cref="DRagLint.Charts.Index.TIndexRow.S"/>
    /// <seealso cref="DRagLint.Charts.Source.TSourceReader.AddOverride"/>
    /// <seealso cref="DRagLint.Charts.Source.TSourceReader.BlankMatch"/>
    /// <seealso cref="DRagLint.Charts.Source.TSourceReader.ContextOfLines"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function DbPathText: string;
    /// <param name="pMatch"><!-- drag-lint:auto type -->const TMatch</param>
    /// <returns><!-- drag-lint:auto -->string -- Observed: StringOfChar(' ', Length(V));
    /// V.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Calls: CharInSet, Pos, StringOfChar</para>
    /// <seealso cref="DRagLint.Charts.Source.TSourceReader.AddOverride"/>
    /// <seealso cref="DRagLint.Charts.Source.TSourceReader.ContextOfLines"/>
    /// <seealso cref="DRagLint.Charts.Source.TSourceReader.Create"/>
    /// <seealso cref="DRagLint.Charts.Source.TSourceReader.DbPathText"/>
    /// <seealso cref="DRagLint.Charts.Source.TSourceReader.Destroy"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function BlankMatch(const pMatch: TMatch): string;
  public
    /// <summary>Creates a reader over one index.</summary>
    /// <param name="pIndex">The index whose files table is the freshness reference; not owned,
    /// must outlive the reader. nil is accepted for the index-free members
    /// (StrippedSourceLines, ContextOfLines); anything that needs a sha then raises.</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Charts.Q.Consumers.TConsumersChart.Create (DRagLint.Charts.Q.Consumers.pas), DRagLint.Charts.Q.ExceptionPaths.TExceptionPathsChart.Create (DRagLint.Charts.Q.ExceptionPaths.pas), DRagLint.Charts.Q.FeedsFrom.TFeedsFromChart.Create (DRagLint.Charts.Q.FeedsFrom.pas), DRagLint.Charts.Q.LandsWhere.TLandsWhereChart.Create (DRagLint.Charts.Q.LandsWhere.pas), DRagLint.Charts.Q.RoundTrip.TRoundTripRun.Create (DRagLint.Charts.Q.RoundTrip.pas)</para>
    /// <para>constructor</para>
    /// <para>Writes: FIndex, FOverrides, FFresh, FStripped</para>
    /// <seealso cref="DRagLint.Charts.Source.TSourceReader.AddOverride"/>
    /// <seealso cref="DRagLint.Charts.Source.TSourceReader.BlankMatch"/>
    /// <seealso cref="DRagLint.Charts.Source.TSourceReader.ContextOfLines"/>
    /// <seealso cref="DRagLint.Charts.Source.TSourceReader.DbPathText"/>
    /// <seealso cref="DRagLint.Charts.Source.TSourceReader.Destroy"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    constructor Create(pIndex: TChartsIndex);
    /// <summary>Frees the caches (never the index).</summary>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Reads: FStripped, FFresh, FOverrides, FShas, FIds, FPaths</para>
    /// <para>Directives: override</para>
    /// <seealso cref="DRagLint.Charts.Source.TSourceReader.AddOverride"/>
    /// <seealso cref="DRagLint.Charts.Source.TSourceReader.BlankMatch"/>
    /// <seealso cref="DRagLint.Charts.Source.TSourceReader.ContextOfLines"/>
    /// <seealso cref="DRagLint.Charts.Source.TSourceReader.Create"/>
    /// <seealso cref="DRagLint.Charts.Source.TSourceReader.DbPathText"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    destructor Destroy; override;
    /// <summary>path -> sha256 for every file of the index, loaded once.</summary>
    /// <returns>The reader's own dictionary -- do not free or modify it. Keys are case-insensitive.</returns>
    /// <exception cref="EChartsIndex">When the reader was created without an index.</exception>
    /// <remarks>
    /// Port of Get-IndexedFileShas (Emit-Common.ps1:794). PS trap closed: a plain @{}
    /// hashtable is case-insensitive, like the Windows paths it holds, so the dictionary uses
    /// TIStringComparer.Ordinal. The PS paging (CLIENT has 625 files) is gone: AllRows has no cap.
    /// The parallel path -> id map the PS also built is not ported (nothing here reads it).
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Charts.Q.FeedsFrom.TFeedsFromChart.ReadBinding (DRagLint.Charts.Q.FeedsFrom.pas), DRagLint.Charts.Source.TSourceReader.FileId (DRagLint.Charts.Source.pas), DRagLint.Charts.Source.TSourceReader.IndexedPath (DRagLint.Charts.Source.pas), DRagLint.Charts.Source.TSourceReader.SourceFresh (DRagLint.Charts.Source.pas)</para>
    /// <para>Calls: DRagLint.Charts.Index.TChartsIndex.AllRows, DRagLint.Charts.Index.TIndexRow.I, DRagLint.Charts.Index.TIndexRow.S</para>
    /// <para>Returns: FShas</para>
    /// <para>Reads: FShas, FIndex, FIds, FPaths   Writes: FShas, FIds, FPaths</para>
    /// <para>Owns returned: borrowed</para>
    /// <para>SQL: reads FILES</para>
    /// <seealso cref="DRagLint.Charts.Index.TChartsIndex.AllRows"/>
    /// <seealso cref="DRagLint.Charts.Index.TIndexRow.I"/>
    /// <seealso cref="DRagLint.Charts.Index.TIndexRow.S"/>
    /// <seealso cref="DRagLint.Charts.Source.TSourceReader.AddOverride"/>
    /// <seealso cref="DRagLint.Charts.Source.TSourceReader.BlankMatch"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function IndexedFileShas: TDictionary<string, string>;
    /// <summary>files.id of an indexed path (any case); 0 when it is not a file of the index.</summary>
    /// <param name="pPath">A path.</param>
    /// <returns>The id, or 0.</returns>
    /// <exception cref="EChartsIndex"><!-- drag-lint:auto exc -->via DRagLint.Charts.Source.TSourceReader.IndexedFileShas: TSourceReader: no index to read file shas from</exception>
    /// <remarks>
    /// The $script:DlFileIds[] map Get-IndexedFileShas builds (Emit-Common.ps1:812),
    /// ported in step 2 for the datasource chain; loaded with the shas, case-insensitive.
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Charts.Chain.PickRootDecl (DRagLint.Charts.Chain.pas), DRagLint.Charts.Chain.StepLocateForm (DRagLint.Charts.Chain.pas), DRagLint.Charts.Chain.TChainWalker.DataSetSites (DRagLint.Charts.Chain.pas), DRagLint.Charts.Chain.TChainWalker.RePointChain (DRagLint.Charts.Chain.pas), DRagLint.Charts.Chain.TChainWalker.RePointSites (DRagLint.Charts.Chain.pas)</para>
    /// <para>Calls: DRagLint.Charts.Source.TSourceReader.IndexedFileShas</para>
    /// <para>Returns: 0</para>
    /// <para>Reads: FIds</para>
    /// <seealso cref="DRagLint.Charts.Source.TSourceReader.IndexedFileShas"/>
    /// <seealso cref="DRagLint.Charts.Source.TSourceReader.AddOverride"/>
    /// <seealso cref="DRagLint.Charts.Source.TSourceReader.BlankMatch"/>
    /// <seealso cref="DRagLint.Charts.Source.TSourceReader.ContextOfLines"/>
    /// <seealso cref="DRagLint.Charts.Source.TSourceReader.Create"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function FileId(const pPath: string): Integer;
    /// <summary>The path exactly as the index stores it, for a path matched case-insensitively.</summary>
    /// <param name="pPath">A path (any case).</param>
    /// <param name="pStored">The stored spelling.</param>
    /// <returns>False when pPath is not a file of the index.</returns>
    /// <exception cref="EChartsIndex"><!-- drag-lint:auto exc -->via DRagLint.Charts.Source.TSourceReader.IndexedFileShas: TSourceReader: no index to read file shas from</exception>
    /// <remarks>
    /// Stands in for the PS @(.Keys | Where-Object { Equals(OrdinalIgnoreCase) }).
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Charts.Chain.StepDataSource (DRagLint.Charts.Chain.pas), DRagLint.Charts.Chain.StepLocateForm (DRagLint.Charts.Chain.pas)</para>
    /// <para>Calls: DRagLint.Charts.Source.TSourceReader.IndexedFileShas</para>
    /// <para>Returns: FPaths.TryGetValue(pPath, pStored)</para>
    /// <para>Reads: FPaths</para>
    /// <seealso cref="DRagLint.Charts.Source.TSourceReader.IndexedFileShas"/>
    /// <seealso cref="DRagLint.Charts.Source.TSourceReader.AddOverride"/>
    /// <seealso cref="DRagLint.Charts.Source.TSourceReader.BlankMatch"/>
    /// <seealso cref="DRagLint.Charts.Source.TSourceReader.ContextOfLines"/>
    /// <seealso cref="DRagLint.Charts.Source.TSourceReader.Create"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function IndexedPath(const pPath: string; out pStored: string): Boolean;
    /// <summary>Reads pReadPath whenever pIndexedPath is asked about.</summary>
    /// <param name="pIndexedPath">A path of the index; matched case-insensitively.</param>
    /// <param name="pReadPath">The file to read (and hash) instead.</param>
    /// <remarks>
    /// Port of -SourceOverride / Resolve-SourceReadPath (Emit-Common.ps1:781): it exists
    /// so a test can manufacture a stale file deterministically. PS trap closed: the keys are
    /// compared OrdinalIgnoreCase, so the dictionary is case-insensitive.
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Reads: FOverrides</para>
    /// <seealso cref="DRagLint.Charts.Source.TSourceReader.BlankMatch"/>
    /// <seealso cref="DRagLint.Charts.Source.TSourceReader.ContextOfLines"/>
    /// <seealso cref="DRagLint.Charts.Source.TSourceReader.Create"/>
    /// <seealso cref="DRagLint.Charts.Source.TSourceReader.DbPathText"/>
    /// <seealso cref="DRagLint.Charts.Source.TSourceReader.Destroy"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure AddOverride(const pIndexedPath, pReadPath: string);
    /// <summary>The file to read for an indexed path: its override, else the path itself.</summary>
    /// <param name="pPath">A path of the index.</param>
    /// <returns>The override target, or pPath.</returns>
    /// <remarks>
    /// Port of Resolve-SourceReadPath (Emit-Common.ps1:799); public since step 2 so the SQL
    /// readers (DRagLint.Charts.Sql) read the same file this reader hashes.
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Charts.Chain.PropertyField (DRagLint.Charts.Chain.pas), DRagLint.Charts.Columns.FindQuotedColumn (DRagLint.Charts.Columns.pas), DRagLint.Charts.Exceptions.TExceptionIndex.SourceRows (DRagLint.Charts.Exceptions.pas), DRagLint.Charts.Q.Consumers.TConsumersChart.SqlLineText (DRagLint.Charts.Q.Consumers.pas), DRagLint.Charts.Q.ExceptionPaths.TExceptionPathsChart.ReadCallers (DRagLint.Charts.Q.ExceptionPaths.pas) (+6 more)</para>
    /// <para>Returns: pPath</para>
    /// <para>Reads: FOverrides</para>
    /// <seealso cref="DRagLint.Charts.Source.TSourceReader.AddOverride"/>
    /// <seealso cref="DRagLint.Charts.Source.TSourceReader.BlankMatch"/>
    /// <seealso cref="DRagLint.Charts.Source.TSourceReader.ContextOfLines"/>
    /// <seealso cref="DRagLint.Charts.Source.TSourceReader.Create"/>
    /// <seealso cref="DRagLint.Charts.Source.TSourceReader.DbPathText"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function ReadPath(const pPath: string): string;
    /// <summary>Whether the file that would be READ for pPath hashes to the sha256 the index recorded.</summary>
    /// <param name="pPath">A path of the index (any case).</param>
    /// <returns>True when the hashes match; False when they differ or the read file is missing.</returns>
    /// <exception cref="EChartsIndex">'Test-SourceFresh: &lt;path&gt; is not a file of this index (&lt;db&gt;)'
    /// when pPath is not a file of the index -- a caller bug, not a staleness verdict.</exception>
    /// <remarks>
    /// Port of Test-SourceFresh (Emit-Common.ps1:815). Cached per pPath and read path.
    /// PS traps closed: Get-FileHash answers UPPER-case hex and THashSHA2 lower-case, and the PS
    /// compare is OrdinalIgnoreCase, so SameText; the cache hashtable key is case-insensitive.
    /// &lt;db&gt; is the file SQLite reports for the main database (the PS printed $DbPath as given).
    /// A directory at the read path reads as missing (False) where the PS Get-FileHash would fail.
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Charts.Chain.PropertyField (DRagLint.Charts.Chain.pas), DRagLint.Charts.Chain.TChainWalker.RePointPick (DRagLint.Charts.Chain.pas), DRagLint.Charts.Columns.FindQuotedColumn (DRagLint.Charts.Columns.pas), DRagLint.Charts.Exceptions.TExceptionIndex.FactIndexStats (DRagLint.Charts.Exceptions.pas), DRagLint.Charts.Exceptions.TExceptionIndex.IndexStats (DRagLint.Charts.Exceptions.pas) (+9 more)</para>
    /// <para>Calls: DRagLint.Charts.Source.TSourceReader.DbPathText, DRagLint.Charts.Source.TSourceReader.IndexedFileShas, DRagLint.Charts.Source.TSourceReader.ReadPath, SameText</para>
    /// <para>Returns: False; SameText(THashSHA2.GetHashStringFromFile(Read), Sha)</para>
    /// <para>Reads: FFresh</para>
    /// <para>Touches: file system</para>
    /// <seealso cref="DRagLint.Charts.Source.TSourceReader.DbPathText"/>
    /// <seealso cref="DRagLint.Charts.Source.TSourceReader.IndexedFileShas"/>
    /// <seealso cref="DRagLint.Charts.Source.TSourceReader.ReadPath"/>
    /// <seealso cref="DRagLint.Charts.Source.TSourceReader.AddOverride"/>
    /// <seealso cref="DRagLint.Charts.Source.TSourceReader.BlankMatch"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function SourceFresh(const pPath: string): Boolean;
    /// <summary>Pascal source with every comment, string and directive replaced by spaces.</summary>
    /// <param name="pReadPath">The file to read.</param>
    /// <returns>The lines, each exactly as long as the original, newlines dropped; a final line
    /// break yields a final '' element. Cached per read path; the array is shared, do not modify it.</returns>
    /// <remarks>
    /// Port of Get-StrippedSourceLines (Emit-Common.ps1:840): ONE regex over the whole
    /// file, leftmost match wins (so `'{'` is a string and `{ ' }` a comment), regex verbatim:
    /// '[^'\r\n]*'|\{[^}]*\}|\(\*[\s\S]*?\*\)|//[^\r\n]* -- a match without LF becomes that many
    /// spaces, one with LF keeps every CR and LF and blanks the rest. Directives are blanked, not
    /// evaluated (R13). PS traps closed: the file is read as Latin-1 so one byte is one char, BUT
    /// .NET ReadAllText still honours a UTF-8 / UTF-16 byte-order mark, so a BOM is detected and
    /// decoded the same way (a UTF-32 BOM is not); `-split "\r?\n"` splits on LF and drops one CR
    /// before it, keeping a lone CR in the text; the cache hashtable key is case-insensitive.
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Charts.Chain.PropertyField (DRagLint.Charts.Chain.pas), DRagLint.Charts.Exceptions.TExceptionIndex.SourceRows (DRagLint.Charts.Exceptions.pas), DRagLint.Charts.Q.ExceptionPaths.TExceptionPathsChart.ReadCallers (DRagLint.Charts.Q.ExceptionPaths.pas), DRagLint.Charts.Source.TSourceReader.SourceContext (DRagLint.Charts.Source.pas), DRagLint.Charts.Trace.Anchor.TTraceAnchorResolver.PropertyReadField (DRagLint.Charts.Trace.Anchor.pas) (+2 more)</para>
    /// <para>Calls: DRagLint.Charts.Source.ReadLatin1, DRagLint.Charts.Source.SplitLines</para>
    /// <para>Returns: SplitLines(TRegEx.Replace(ReadLatin1(pReadPath), STRIP_PATTERN, BlankMatch))</para>
    /// <para>Reads: FStripped</para>
    /// <seealso cref="DRagLint.Charts.Source.ReadLatin1"/>
    /// <seealso cref="DRagLint.Charts.Source.SplitLines"/>
    /// <seealso cref="DRagLint.Charts.Source.TSourceReader.AddOverride"/>
    /// <seealso cref="DRagLint.Charts.Source.TSourceReader.BlankMatch"/>
    /// <seealso cref="DRagLint.Charts.Source.TSourceReader.ContextOfLines"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function StrippedSourceLines(const pReadPath: string): TArray<string>;
    /// <summary>The comment-stripped text around ONE ref, gated on freshness.</summary>
    /// <param name="pPath">A path of the index.</param>
    /// <param name="pLine">1-based line (refs.line).</param>
    /// <param name="pCol">1-based column (refs.start_col).</param>
    /// <param name="pLen">end_col - start_col (end_col is exclusive -- P10).</param>
    /// <param name="pFollowing">How many following lines to return.</param>
    /// <returns>The context; Stale True with no text when the file is not fresh.</returns>
    /// <exception cref="EChartsIndex">pPath is not a file of the index (from SourceFresh), or
    /// pLine is outside a fresh file (from ContextOfLines).</exception>
    /// <remarks>
    /// Port of Get-SourceContext (Emit-Common.ps1:868): SourceFresh, then
    /// StrippedSourceLines of the read path, then ContextOfLines.
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Charts.Chain.TChainWalker.DataSetSites (DRagLint.Charts.Chain.pas), DRagLint.Charts.Chain.TChainWalker.RePointSites (DRagLint.Charts.Chain.pas), DRagLint.Charts.Exceptions.TExceptionIndex.IndexStats (DRagLint.Charts.Exceptions.pas), DRagLint.Charts.Q.ExceptionPaths.TExceptionPathsChart.BodyExceptions (DRagLint.Charts.Q.ExceptionPaths.pas)</para>
    /// <para>Calls: Default, DRagLint.Charts.Source.TSourceReader.ContextOfLines, DRagLint.Charts.Source.TSourceReader.ReadPath, DRagLint.Charts.Source.TSourceReader.SourceFresh, DRagLint.Charts.Source.TSourceReader.StrippedSourceLines</para>
    /// <para>Returns: Default(TSourceContext); ContextOfLines(pPath, StrippedSourceLines(ReadPath(pPath)), pLine, pCol, pLen, pFollowing)</para>
    /// <seealso cref="DRagLint.Charts.Source.TSourceReader.ContextOfLines"/>
    /// <seealso cref="DRagLint.Charts.Source.TSourceReader.ReadPath"/>
    /// <seealso cref="DRagLint.Charts.Source.TSourceReader.SourceFresh"/>
    /// <seealso cref="DRagLint.Charts.Source.TSourceReader.StrippedSourceLines"/>
    /// <seealso cref="DRagLint.Charts.Source.TSourceReader.AddOverride"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function SourceContext(const pPath: string; pLine, pCol, pLen: Integer; pFollowing: Integer = 0): TSourceContext;
    /// <summary>The non-stale half of SourceContext, over lines already stripped.</summary>
    /// <param name="pPath">Path to report in the result.</param>
    /// <param name="pLines">StrippedSourceLines' result.</param>
    /// <param name="pLine">1-based line.</param>
    /// <param name="pCol">1-based column; clamped to the line.</param>
    /// <param name="pLen">Token length; a negative length counts as 0, and the end clamps to the line.</param>
    /// <param name="pFollowing">How many following lines to return (fewer at the end of the file).</param>
    /// <returns>A fresh (Stale False) context.</returns>
    /// <exception cref="EChartsIndex">'Get-SourceContext: line &lt;n&gt; is outside &lt;path&gt;
    /// (&lt;count&gt; lines) although the file is fresh'.</exception>
    /// <remarks>
    /// Split out of Get-SourceContext (Emit-Common.ps1:878-893) so the geometry is testable
    /// without an index. PS trap closed: String.Trim trims Char.IsWhiteSpace characters (which in
    /// Latin-1 include #$85 and #$A0), not Delphi Trim's "everything up to #32", so PrevLine is
    /// trimmed and tested for blankness with the Unicode whitespace rule.
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Charts.Source.TSourceReader.SourceContext (DRagLint.Charts.Source.pas)</para>
    /// <para>Calls: Copy, Default, DRagLint.Charts.Source.PsTrim, Integer, Max, Min</para>
    /// <para>Returns: Default(TSourceContext)</para>
    /// <seealso cref="DRagLint.Charts.Source.PsTrim"/>
    /// <seealso cref="DRagLint.Charts.Source.TSourceReader.AddOverride"/>
    /// <seealso cref="DRagLint.Charts.Source.TSourceReader.BlankMatch"/>
    /// <seealso cref="DRagLint.Charts.Source.TSourceReader.Create"/>
    /// <seealso cref="DRagLint.Charts.Source.TSourceReader.DbPathText"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function ContextOfLines(const pPath: string; const pLines: TArray<string>; pLine, pCol, pLen: Integer;
      pFollowing: Integer = 0): TSourceContext;
  end;

/// <summary>[IO.File]::ReadAllText(path, Latin-1): a UTF-8 or UTF-16 BOM still wins, else one byte is one char.</summary>
/// <param name="pPath">The file.</param>
/// <returns>The decoded text.</returns>
/// <remarks>
/// Shared by the Pascal and SQL strippers (public since step 2). A UTF-32 BOM is not detected.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Charts.Source.TSourceReader.StrippedSourceLines (DRagLint.Charts.Source.pas), DRagLint.Charts.Sql.TSqlCatalog.StrippedSqlLines (DRagLint.Charts.Sql.pas), DRagLint.Charts.Trace.Calc.TCalcFactsReader.ReadHandler (DRagLint.Charts.Trace.Calc.pas), DRagLint.Charts.Trace.Walk.TTraceWalker.TraceSource (DRagLint.Charts.Trace.Walk.pas)</para>
/// <para>Calls: Char</para>
/// <para>Complexity: 12 (cyclomatic, outer body), 13 lines (full implementation)</para>
/// <para>Touches: file system</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ReadLatin1(const pPath: string): string;

/// <summary>$s -split "\r?\n": split on LF, dropping one CR right before it.</summary>
/// <param name="pS">The text.</param>
/// <returns>The lines; a final line break yields a final '' element; a lone CR stays in the text.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Charts.Source.TSourceReader.StrippedSourceLines (DRagLint.Charts.Source.pas), DRagLint.Charts.Sql.TSqlCatalog.StrippedSqlLines (DRagLint.Charts.Sql.pas), DRagLint.Charts.Trace.Calc.TCalcFactsReader.ReadHandler (DRagLint.Charts.Trace.Calc.pas), DRagLint.Charts.Trace.Walk.TTraceWalker.TraceSource (DRagLint.Charts.Trace.Walk.pas)</para>
/// <para>Calls: Copy</para>
/// <para>Returns: Parts.ToArray</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function SplitLines(const pS: string): TArray<string>;

/// <summary>PS String.Trim: strips Char.IsWhiteSpace characters (not Delphi Trim's &lt;= #32) from both ends.</summary>
/// <param name="pS">The text.</param>
/// <returns>The trimmed text.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Charts.Chain.BareRhsStop (DRagLint.Charts.Chain.pas), DRagLint.Charts.Chain.MemberIsDataSourceField (DRagLint.Charts.Chain.pas), DRagLint.Charts.Chain.PropertyField (DRagLint.Charts.Chain.pas), DRagLint.Charts.Chain.RePointControl (DRagLint.Charts.Chain.pas), DRagLint.Charts.Chain.RePointDataSet (DRagLint.Charts.Chain.pas) (+25 more)</para>
/// <para>Calls: Copy</para>
/// <para>Returns: Copy(pS, First, Last - First + 1)</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function PsTrim(const pS: string): string;

implementation

uses
  System.Classes
  , System.IOUtils
  , System.Hash
  , System.Math
  , System.Character
  , System.Generics.Defaults
  ;

const
  { Get-StrippedSourceLines' regex, verbatim }
  STRIP_PATTERN = '''[^''\r\n]*''|\{[^}]*\}|\(\*[\s\S]*?\*\)|//[^\r\n]*';
  BOM_UTF8: array[0..2] of Byte = ($EF, $BB, $BF);
  BOM_UTF16_LEN = 2;
  BYTE_FF = $FF;
  BYTE_FE = $FE;

function PsTrim(const pS: string): string;
begin
  var First:= 1;
  var Last:= Length(pS);
  while (First <= Last) and pS[First].IsWhiteSpace do
    Inc(First);
  while (Last >= First) and pS[Last].IsWhiteSpace do
    Dec(Last);
  Result:= Copy(pS, First, Last - First + 1);
end;

function ReadLatin1(const pPath: string): string;
begin
  var Bytes:= TFile.ReadAllBytes(pPath);
  var N:= Length(Bytes);
  if (N >= Length(BOM_UTF8)) and (Bytes[0] = BOM_UTF8[0]) and (Bytes[1] = BOM_UTF8[1]) and (Bytes[2] = BOM_UTF8[2]) then
    Exit(TEncoding.UTF8.GetString(Bytes, Length(BOM_UTF8), N - Length(BOM_UTF8)));
  if (N >= BOM_UTF16_LEN) and (Bytes[0] = BYTE_FF) and (Bytes[1] = BYTE_FE) then
    Exit(TEncoding.Unicode.GetString(Bytes, BOM_UTF16_LEN, N - BOM_UTF16_LEN));
  if (N >= BOM_UTF16_LEN) and (Bytes[0] = BYTE_FE) and (Bytes[1] = BYTE_FF) then
    Exit(TEncoding.BigEndianUnicode.GetString(Bytes, BOM_UTF16_LEN, N - BOM_UTF16_LEN));
  SetLength(Result, N);
  for var K:= 0 to N - 1 do
    Result[K + 1]:= Char(Bytes[K]);
end;

function SplitLines(const pS: string): TArray<string>;
begin
  var Parts:= TList<string>.Create;
  try
    var Start:= 1;
    for var K:= 1 to Length(pS) + 1 do
      if (K > Length(pS)) or (pS[K] = #10) then
      begin
        var Stop:= K;
        if (K <= Length(pS)) and (Stop > Start) and (pS[Stop - 1] = #13) then
          Dec(Stop);
        Parts.Add(Copy(pS, Start, Stop - Start));
        Start:= K + 1;
      end;
    Result:= Parts.ToArray;
  finally
    Parts.Free;
  end;
end;

{ ---- TSourceReader ---- }

constructor TSourceReader.Create(pIndex: TChartsIndex);
begin
  inherited Create;
  FIndex:= pIndex;
  FOverrides:= TDictionary<string, string>.Create(TIStringComparer.Ordinal);
  FFresh:= TDictionary<string, Boolean>.Create(TIStringComparer.Ordinal);
  FStripped:= TDictionary<string, TArray<string>>.Create(TIStringComparer.Ordinal);
end;

destructor TSourceReader.Destroy;
begin
  FStripped.Free;
  FFresh.Free;
  FOverrides.Free;
  FShas.Free;
  FIds.Free;
  FPaths.Free;
  inherited Destroy;
end;

function TSourceReader.IndexedFileShas: TDictionary<string, string>;
begin
  if FShas = nil then
  begin
    if FIndex = nil then
      raise EChartsIndex.Create('TSourceReader: no index to read file shas from');
    var Rows:= FIndex.AllRows('SELECT id, path, sha256 FROM files', 'id');
    try
      FShas:= TDictionary<string, string>.Create(TIStringComparer.Ordinal);
      FIds:= TDictionary<string, Integer>.Create(TIStringComparer.Ordinal);
      FPaths:= TDictionary<string, string>.Create(TIStringComparer.Ordinal);
      for var R in Rows do
      begin
        FShas.AddOrSetValue(R.S('path'), R.S('sha256'));
        FIds.AddOrSetValue(R.S('path'), R.I('id'));
        FPaths.AddOrSetValue(R.S('path'), R.S('path'));
      end;
    finally
      Rows.Free;
    end;
  end;
  Result:= FShas;
end;

function TSourceReader.FileId(const pPath: string): Integer;
begin
  IndexedFileShas;
  if not FIds.TryGetValue(pPath, Result) then
    Result:= 0;
end;

function TSourceReader.IndexedPath(const pPath: string; out pStored: string): Boolean;
begin
  IndexedFileShas;
  Result:= FPaths.TryGetValue(pPath, pStored);
end;

procedure TSourceReader.AddOverride(const pIndexedPath, pReadPath: string);
begin
  FOverrides.AddOrSetValue(pIndexedPath, pReadPath);
end;

function TSourceReader.ReadPath(const pPath: string): string;
begin
  if not FOverrides.TryGetValue(pPath, Result) then
    Result:= pPath;
end;

function TSourceReader.DbPathText: string;
begin
  Result:= '';
  var Rows:= FIndex.Query('PRAGMA database_list');
  try
    for var R in Rows do
      if SameText(R.S('name'), 'main') then
        Exit(R.S('file'));
  finally
    Rows.Free;
  end;
end;

function TSourceReader.SourceFresh(const pPath: string): Boolean;
var
  Sha: string;
begin
  if not IndexedFileShas.TryGetValue(pPath, Sha) then
    raise EChartsIndex.Create('Test-SourceFresh: ' + pPath + ' is not a file of this index (' + DbPathText + ')');
  var Read:= ReadPath(pPath);
  if not TFile.Exists(Read) then
    Exit(False);
  var Key:= pPath + '|' + Read;
  if not FFresh.TryGetValue(Key, Result) then
  begin
    Result:= SameText(THashSHA2.GetHashStringFromFile(Read), Sha);
    FFresh.Add(Key, Result);
  end;
end;

function TSourceReader.BlankMatch(const pMatch: TMatch): string;
begin
  var V:= pMatch.Value;
  if Pos(#10, V) = 0 then
    Exit(StringOfChar(' ', Length(V)));
  Result:= V;
  for var K:= 1 to Length(Result) do
    if not CharInSet(Result[K], [#13, #10]) then
      Result[K]:= ' ';
end;

function TSourceReader.StrippedSourceLines(const pReadPath: string): TArray<string>;
begin
  if not FStripped.TryGetValue(pReadPath, Result) then
  begin
    Result:= SplitLines(TRegEx.Replace(ReadLatin1(pReadPath), STRIP_PATTERN, BlankMatch));
    FStripped.Add(pReadPath, Result);
  end;
end;

function TSourceReader.SourceContext(const pPath: string; pLine, pCol, pLen: Integer;
  pFollowing: Integer): TSourceContext;
begin
  if not SourceFresh(pPath) then
  begin
    Result:= Default(TSourceContext);
    Result.Path:= pPath;
    Result.Line:= pLine;
    Result.Stale:= True;
    Exit;
  end;
  Result:= ContextOfLines(pPath, StrippedSourceLines(ReadPath(pPath)), pLine, pCol, pLen, pFollowing);
end;

class function TSourceReader.ContextOfLines(const pPath: string; const pLines: TArray<string>;
  pLine, pCol, pLen: Integer; pFollowing: Integer): TSourceContext;
begin
  var Count:= Integer(Length(pLines));
  if (pLine < 1) or (pLine > Count) then
    raise EChartsIndex.CreateFmt('Get-SourceContext: line %d is outside %s (%d lines) although the file is fresh',
      [pLine, pPath, Count]);
  var T:= pLines[pLine - 1];
  var C0:= Min(Max(pCol - 1, 0), Length(T));
  var C1:= Min(C0 + Max(pLen, 0), Length(T));
  Result:= Default(TSourceContext);
  Result.Path:= pPath;
  Result.Line:= pLine;
  Result.Stale:= False;
  Result.Before:= Copy(T, 1, C0);
  Result.Token:= Copy(T, C0 + 1, C1 - C0);
  Result.After:= Copy(T, C1 + 1, MaxInt);
  for var K:= pLine - 2 downto 0 do
    if PsTrim(pLines[K]) <> '' then
    begin
      Result.PrevLine:= PsTrim(pLines[K]);
      Result.PrevLineNo:= K + 1;
      Break;
    end;
  var Last:= Min(pLine + pFollowing, Count);
  if Last > pLine then
    Result.Following:= Copy(pLines, pLine, Last - pLine);
end;

end.
