unit ConvRules.Engine;

{ Engine adapter: the ONLY boundary between the editor and drag-lint.

  All semantic knowledge (property trees, scaffold drafts, validation) comes from
  shelling the drag-lint CLI and parsing its output. The editor never parses DFMs
  or Pascal itself. Two layers:

    - PURE parsers (ParseProptreeJson, ...) -- testable against captured fixtures,
      no process spawn.
    - I/O wrappers (RunProptree, RunScaffold, RunValidate) -- spawn drag-lint and
      feed the output to the pure parsers.

  Keeping the parsers pure means the JSON handling is unit-tested without needing
  the exe or an index at test time. }

interface

uses
  System.SysUtils
  , System.Classes
  , System.JSON
  , System.Generics.Collections
  , ConvRules.EngineProgress  // dl:unit ConvRules.EngineProgress accepted -- the exit codes and PROGRESS_INTERVAL_S are the engine-call contract this adapter implements, so they travel with it
  ;

const
  /// <summary>Watchdog for ONE drag-lint invocation, in milliseconds. On expiry
  /// RunCapture terminates the child and returns 3.</summary>
  /// <remarks>A guard against a pathological (effectively unbounded) walk hanging
  /// the editor's main thread -- NOT a latency budget, so it is set well above
  /// every legitimate call rather than close to one. It was 30000, which was below
  /// legitimate work on TWO different paths. Measured 2026-07-29 against
  /// library-Win64 + ORM3, per verb:
  ///   ValidateText  (convert-validate)                      29.83 s  &lt;-- slowest
  ///   GetProptree   (no --min-visibility, --refs-as-leaves)   7.82 s
  ///   GetProptree   (--min-visibility published, refs)        6.96 s
  ///   ListDescendantsOf / ListProjectUnits                &lt;= 0.50 s
  /// So a 30 s bound sat essentially ON TOP of ValidateText, and the pre-fix
  /// proptree call (20.11 s warm here, 74-79 s recorded on a colder index) could
  /// exceed it outright -- the editor reported a timeout for work that would have
  /// succeeded. 180 s is ~6x the slowest call above.</remarks>
  /// <remarks>CONDITION, since this bound does not cover everything: Scaffold
  /// (convert-scaffold) measured 346 s for one Vcl.StdCtrls.TButton -&gt;
  /// cxButtons.TcxButton scaffold, emitting 6.7 MB, and WOULD time out here. That
  /// is currently harmless only because Scaffold has no caller in the editor. Give
  /// it one and this bound must be revisited -- or better, find out why it is 44x
  /// the equivalent proptree call (convert-scaffold takes no --refs-as-leaves, so
  /// it is likely expanding component references the way proptree used to).
  /// Note also that RunCapture drains on the calling thread, so this bound is also
  /// the longest the UI can be frozen.</remarks>
  ENGINE_TIMEOUT_MS = 180000;
  /// <summary>Watchdog for ONE conversion-path call (convert-apply, index
  /// --project), in milliseconds.</summary>
  CONVERT_TIMEOUT_MS = 600000; // conversions: a 3-file fixture dry-run measured 106 s (2026-09-29)
  /// <summary>Watchdog for the start-up capability probe (`info --json`, see
  /// TEngineAdapter.CapabilityNames), in milliseconds.</summary>
  /// <remarks>The probe runs in TConvRulesForm.Create on the UI thread, so this
  /// bound is how long a hung engine can freeze start-up. `info` reads no index;
  /// 15 s is generous. On expiry the probe reports NO capabilities, which is the
  /// behaviour of an engine older than 1.20.6.</remarks>
  INFO_TIMEOUT_MS = 15000;
  /// <summary>info --json capability: the #depth book directive plus --depth on
  /// proptree / convert-scaffold (engine 1.20.6).</summary>
  CAPABILITY_BOOK_DEPTH = 'book_depth';
  /// <summary>info --json capability: --progress-interval and the stderr progress
  /// lines (engine 1.20.6). An engine WITHOUT it exits 3 on the flag.</summary>
  CAPABILITY_PROGRESS_LINES = 'progress_lines';
  /// <summary>info --json capability: convert-apply converts a unit's own part when it
  /// holds inherited / inline instances and reports them in apply/1 inherited[] (C8,
  /// engine N1 + N5, 1.22.0). Without it the engine refuses such a unit.</summary>
  CAPABILITY_INHERITED_INSTANCES = 'inherited_instances';
  /// <summary>info --json capability: convert-apply RETYPES a descendant's inherited
  /// instance once its declaring ancestor has the To type (C8 engine N2). PROPOSED key --
  /// the engine stream confirms or renames it; this constant is the one place it lives.
  /// Without it (1.22.0) an inherited instance under a converted ancestor stays the From
  /// type, so the descendant may fail to compile or load.</summary>
  CAPABILITY_INHERITED_RETYPE = 'inherited_retype';
  /// <summary>The words every C8 read's failure text carries when the engine marked
  /// its answer "stale" (a file changed on disk since it was indexed).</summary>
  /// <remarks>ConvRules.InheritanceEngine.IsStaleIndexError matches on it to decide
  /// that ONE incremental reindex may fix the read.</remarks>
  INDEX_STALE_MARKER = 'the index is stale';
  /// <summary>info --json capability: convert-apply realises #link glyph expressions
  /// (C10, engine ask N1). Without it a G-link book is refused by the engine, so the
  /// Convert tab greys such a book instead of running it.</summary>
  CAPABILITY_GLYPH_STITCH = 'glyph_stitch';

type
  /// <summary>One flattened property leaf from `proptree --format json`
  /// (schema proptree/1).</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: ConvRules.Engine.ParseProptreeJson (ConvRules.Engine.pas), ConvRules.MainForm.TConvRulesForm.LeafType (ConvRules.MainForm.pas), ConvRules.MainForm.TConvRulesForm.LeafWritable (ConvRules.MainForm.pas), ConvRules.MainForm.TConvRulesForm.RefreshGrid (ConvRules.MainForm.pas), declaration (ConvRules.Engine.pas) (+6 more)</para>
  /// <para>Used in units: ConvRules.Engine, ConvRules.MainForm, ConvRules.MappingForm, ConvRules.Mappings</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TPropLeaf = record
    Path       : string ; // dotted path, e.g. 'Style.Font.Size'
    TypeName   : string ; // declared type, e.g. 'Integer'
    DeclaredIn : string ; // owning unit.class, e.g. 'Vcl.Graphics.TFont'
    Kind       : string ; // 'scalar' | 'class' | 'unknown'
    IsClassType: Boolean; // recursion descended into it
    // proptree/2 (engine schema v17): assignability of this leaf as a TARGET.
    IsWritable : Boolean; // False = read-only (ro prop / typed const): not a valid target
    Visibility : string ; // 'published' | 'public' | ... ('' when absent)
    MemberKind : string ; // 'property' | 'field'  ('property' when absent)
  end; // record

  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: ConvRules.Engine.ParseProptreeJson (ConvRules.Engine.pas), ConvRules.Engine.TEngineAdapter.GetProptree (ConvRules.Engine.pas), ConvRules.MainForm.TConvRulesForm.LeafType (ConvRules.MainForm.pas), declaration (ConvRules.Engine.pas), declaration (ConvRules.MainForm.pas) (+6 more)</para>
  /// <para>Used in units: ConvRules.Engine, ConvRules.MainForm, ConvRules.MappingForm, ConvRules.Mappings</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TProptree = record
    Qname    : string           ;
    RootType : string           ;
    Truncated: Boolean          ;
    Leaves   : TArray<TPropLeaf>;
  end;

  /// <summary>Result of running convert-validate: OK plus an optional first-error
  /// line (as the CLI reports it, e.g. "line 4: link ToPath not found ...").</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: ConvRules.Engine.TEngineAdapter.ValidateText (ConvRules.Engine.pas), ConvRules.MainForm.TConvRulesForm.DoValidate (ConvRules.MainForm.pas), ConvRules.MainForm.TConvRulesForm.SaveBook (ConvRules.MainForm.pas), declaration (ConvRules.Engine.pas)</para>
  /// <para>Used in units: ConvRules.Engine, ConvRules.MainForm</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TValidateResult = record
    OK        : Boolean;
    FirstError: string ; // '' when OK
    /// <summary>The engine's whole reply -- stdout, then stderr's lines whole after
    /// it (never interleaved mid-line) -- for
    /// ConvRules.ValidateScope.ParseValidateOutput: warnings never change the exit
    /// code, so OK / FirstError alone lose every one of them.</summary>
    Output    : string ;
  end;

/// <summary>PURE: parse `proptree/1` JSON into a TProptree. Raises on malformed
/// JSON; returns an empty Leaves array when the "properties" array is absent.</summary>
/// <param name="AJson"><!-- drag-lint:auto type -->const string</param>
/// <returns><!-- drag-lint:auto -->TProptree -- Observed: Default(TProptree).</returns>
/// <exception cref="Exception"><!-- drag-lint:auto exc -->proptree: response is not a JSON object</exception>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: ConvRules.Engine.TEngineAdapter.GetProptree (ConvRules.Engine.pas)</para>
/// <para>Calls: ConvRules.Engine.SliceJsonObject, Default</para>
/// <para>Pure</para>
/// <seealso cref="ConvRules.Engine.SliceJsonObject"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ParseProptreeJson(const AJson: string): TProptree;

type
  /// <summary>One row of `drag-lint query --name X --json` -- the fields this
  /// editor needs out of the engine's symbol record.</summary>
  /// <remarks>
  /// Measured against the shipped exe on 2026-07-30: the payload is a
  /// BARE top-level JSON array of these records (there is no enclosing "results"
  /// object), and the declaration line is spelled "start_line", NOT "line".
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: ConvRules.Engine.ParseQueryLocation (ConvRules.Engine.pas), ConvRules.Engine.ParseQuerySymbols (ConvRules.Engine.pas), ConvRules.Engine.SelectQuerySymbol (ConvRules.Engine.pas), ConvRules.Engine.TEngineAdapter.ResolveClassQName/3 (ConvRules.Engine.pas), declaration (ConvRules.Engine.pas) (+1 more)</para>
  /// <para>Used in units: ConvRules.Engine</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TQuerySymbol = record
    Kind         : string ; // 'class'|'record'|'interface'|'enum'|'type'|'field'|'local_var'|...
    Name         : string ; // bare identifier
    QualifiedName: string ; // e.g. 'System.Classes.TAlignment'
    FilePath     : string ; // absolute path of the declaring file
    StartLine    : Integer; // 1-based first line of the declaration ("start_line")
    EndLine      : Integer; // 1-based last  line of the declaration ("end_line")
  end;

/// <summary>PURE: parse the JSON array `query --json` prints into symbol rows.</summary>
/// <param name="AJson">Raw captured output. A "(loaded defaults ...)" note before or
/// after the array is tolerated: RunCapture merges the child's stderr into stdout,
/// and the exe writes that note to stderr on every call.</param>
/// <returns>One entry per array element. [] when the text contains no JSON array --
/// garbage in, empty out. Never raises.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: ConvRules.Engine.ParseQueryLocation (ConvRules.Engine.pas), ConvRules.Engine.TEngineAdapter.EnumMembersOf/4 (ConvRules.Engine.pas), ConvRules.Engine.TEngineAdapter.ResolveClassQName/3 (ConvRules.Engine.pas)</para>
/// <para>Calls: ConvRules.Engine.SliceJsonArray, Default</para>
/// <para>Returns: nil; List.ToArray</para>
/// <para>Catches: Exception (swallowed)</para>
/// <para>Pure</para>
/// <seealso cref="ConvRules.Engine.SliceJsonArray"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ParseQuerySymbols(const AJson: string): TArray<TQuerySymbol>;

/// <summary>PURE: pick the row that actually IS AWantedName.</summary>
/// <param name="ASyms">Rows as returned by ParseQuerySymbols.</param>
/// <param name="AWantedName">Bare ('TAlignment') or unit-qualified
/// ('Abcbtn.TabcButtonStyle'). The part after the last dot is compared to each
/// row's Name; a qualified request must additionally match QualifiedName.</param>
/// <param name="ASym">The chosen row. Untouched (Default) when the result is False.</param>
/// <param name="AAmbiguity">How many exact-name rows shared the WINNING tier. 1 means
/// the answer was forced; &gt; 1 means ASym is one of several equally-ranked candidates
/// and was chosen by the tie-break in the remarks. 0 when the result is False. The
/// caller MUST surface a value &gt; 1 -- the tie-break makes the pick less often wrong,
/// it does not make the tie disappear.</param>
/// <returns>False when no row carries that exact name.</returns>
/// <remarks>
/// `--name` is a SUBSTRING match, so the reply routinely contains unrelated
/// symbols: `--name TNotifyEvent` returns local variables called ANotifyEvent and
/// nothing named TNotifyEvent at all, and `--name TThread` returns an unrelated FIELD
/// named TThread BEFORE System.Classes.TThread. Taking the first row is therefore
/// wrong.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: ConvRules.Engine.ParseQueryLocation (ConvRules.Engine.pas), ConvRules.Engine.TEngineAdapter.EnumMembersOf/4 (ConvRules.Engine.pas), ConvRules.Engine.TEngineAdapter.ResolveClassQName/3 (ConvRules.Engine.pas)</para>
/// <para>Calls: ConvRules.Engine.TieBreakRank, ConvRules.Engine.TypeKindTier, Copy, Default, LastDelimiter, SameText</para>
/// <para>Returns: False; True</para>
/// <para>Complexity: 14 (cyclomatic, outer body), 66 lines (full implementation)</para>
/// <para>Mutates: ASym (out), AAmbiguity (out)</para>
/// <seealso cref="ConvRules.Engine.TieBreakRank"/>
/// <seealso cref="ConvRules.Engine.TypeKindTier"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function SelectQuerySymbol(const ASyms: TArray<TQuerySymbol>; const AWantedName: string; out ASym: TQuerySymbol; out AAmbiguity: Integer): Boolean;

/// <summary>PURE: the declaration site of AWantedName in `query --json` output.</summary>
/// <param name="AJson">Raw captured output (stderr preamble tolerated).</param>
/// <param name="AWantedName">The type the caller asked about; see SelectQuerySymbol
/// for how a row is matched and ranked.</param>
/// <param name="AFile">Absolute path of the declaring file; '' when False.</param>
/// <param name="ALine">1-based declaration line, read from "start_line". 0 when False.
/// CLAMPED to a minimum of 1 on success: the wire contract says a missing or garbled
/// line is to be treated as 1, so a chosen row whose "start_line" is absent or &lt; 1
/// still resolves -- to line 1 of the right file, never to line 0.</param>
/// <param name="AAmbiguity">How many rows tied at the winning tier; see
/// SelectQuerySymbol. 1 = forced, &gt; 1 = the caller must say so, 0 when False.</param>
/// <returns>False for garbage, for an empty array (the real zero-hit reply), for a
/// chosen row with no "file", and -- importantly -- when every row is only a SUBSTRING
/// match on the requested name.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: ConvRules.Engine.TEngineAdapter.ResolveTypeLocation/5 (ConvRules.Engine.pas)</para>
/// <para>Calls: ConvRules.Engine.ParseQuerySymbols, ConvRules.Engine.SelectQuerySymbol</para>
/// <para>Returns: False; True</para>
/// <para>Mutates: AFile (out), ALine (out), AAmbiguity (out)</para>
/// <seealso cref="ConvRules.Engine.ParseQuerySymbols"/>
/// <seealso cref="ConvRules.Engine.SelectQuerySymbol"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ParseQueryLocation(const AJson, AWantedName: string; out AFile: string; out ALine: Integer; out AAmbiguity: Integer): Boolean;

/// <summary>PURE: the member identifiers of an enum, read from its DECLARATION
/// SOURCE TEXT.</summary>
/// <param name="ADeclText">The source lines start_line..end_line of an enum row --
/// e.g. 'TAlignment = (taLeftJustify, taRightJustify, taCenter);'.</param>
/// <param name="AMembers">Members in declaration order; [] when False.</param>
/// <returns>False when ADeclText is not an enum declaration (no '=' immediately
/// followed by a '(' -- which is what rejects 'TFoo = class(TBar)') or when the
/// list is empty.</returns>
/// <remarks>
/// The source text is the ONLY place these live: an enum row in the index
/// carries no members field, `query --qname` returns just the enum itself, and
/// `surface --qname` refuses anything that is not a class/record/interface. Members
/// ARE indexed individually as kind='enum_value' rows, but there is no
/// children-of-a-parent query to reach them.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: ConvRules.Engine.TEngineAdapter.EnumMembersOf/4 (ConvRules.Engine.pas)</para>
/// <para>Calls: CharInSet, ConvRules.Engine.LeadingIdentifier, ConvRules.Engine.StripEnumNoise, Copy, Pos</para>
/// <para>Returns: False; List.Count &gt; 0</para>
/// <para>Complexity: 21 (cyclomatic, outer body), 88 lines (full implementation)</para>
/// <para>Mutates: AMembers (out)</para>
/// <seealso cref="ConvRules.Engine.LeadingIdentifier"/>
/// <seealso cref="ConvRules.Engine.StripEnumNoise"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ParseEnumMembers(const ADeclText: string; out AMembers: TArray<string>): Boolean;

type
  /// <summary>TEngineAdapter.LookupClass's answer.</summary>
  /// <remarks>cloAmbiguous: two or more files declare the name -- never guessed.
  /// cloFailed: the engine could not answer (non-zero exit -- a missing, locked or
  /// stale-schema index -- unparseable or truncated output); unknown, never absent.</remarks>
  TClassLookupOutcome = (cloFound, cloAbsent, cloAmbiguous, cloFailed);

  /// <summary>One field row from TEngineAdapter.ListClassFields.</summary>
  TEngineField = record
    /// <summary>symbols.name.</summary>
    Name    : string;
    /// <summary>symbols.signature -- the declared type as written.</summary>
    TypeName: string;
  end;

  /// <summary>One refs row from TEngineAdapter.ListCodeRefs.</summary>
  TEngineCodeRef = record
    /// <summary>refs.name_text.</summary>
    Name    : string;
    /// <summary>refs.receiver_text; '' for an implicit-Self use.</summary>
    Receiver: string;
    /// <summary>refs.start_line (1-based .pas line).</summary>
    Line    : Integer;
  end;

  /// <summary>Adapter over a drag-lint executable + a set of index DBs.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: ConvRules.ConvertRunner.RunConversionUnits/6 (ConvRules.ConvertRunner.pas), ConvRules.ConvertTab.TConvertTab.ConvertClick (ConvRules.ConvertTab.pas), ConvRules.ConvertTab.TConvertTab.Create (ConvRules.ConvertTab.pas), declaration (ConvRules.ConvertRunner.pas), declaration (ConvRules.ConvertTab.pas) (+5 more)</para>
  /// <para>Used in units: ConvRules.ConvertRunner, ConvRules.ConvertTab, ConvRules.InheritanceEngine, ConvRules.MainForm, ConvRules.MappingForm</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TEngineAdapter = class
    private
      type
        /// <summary>One cached ResolveClassQName answer.</summary>
        TResolvedClass = record
          QName    : string ; // the qualified name, or the bare one for "no such class"
          Ambiguity: Integer;
        end;
    private
      /// <summary>ResolveClassQName answers for this session, keyed on the upper-cased
      /// name + #0 + DbArgs. Negative answers included; failures never. Guarded by
      /// TMonitor on itself: lookups run on the progress window's worker.</summary>
      FResolveCache: TDictionary<string, TResolvedClass>;
      FExePath: string        ;
      FDbList : TArray<string>;
      FTreeDepth     : Integer        ;
      FCastLibFile   : string         ;
      FProgressLines : Boolean        ;
      FLongCallRunner: TLongCallRunner;
      FLastCancelled : Boolean        ;
      FInfoTimeoutMs : Cardinal       ;
      /// <param name="AArgs"><!-- drag-lint:auto type -->const string</param>
      /// <param name="AOutput"><!-- drag-lint:auto type -->out string</param>
      /// <returns><!-- drag-lint:auto -->Integer -- Observed: RunCaptureTimed(AArgs,
      /// ENGINE_TIMEOUT_MS, AOutput).</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: ConvRules.Engine.TEngineAdapter.ListDescendantsOf/4 (ConvRules.Engine.pas), ConvRules.Engine.TEngineAdapter.OutlineClasses (ConvRules.Engine.pas), ConvRules.Engine.TEngineAdapter.QueryJsonFor/4 (ConvRules.Engine.pas), ConvRules.Engine.TEngineAdapter.ResolveUnitFile (ConvRules.Engine.pas), ConvRules.Engine.TEngineAdapter.Scaffold (ConvRules.Engine.pas) (+2 more)</para>
      /// <para>Calls: ConvRules.Engine.TEngineAdapter.RunCaptureTimed</para>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.RunCaptureTimed"/>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.AddSqlColumnOfDb"/>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.AddUnitsOfDb"/>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.ApplyConversion"/>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.CacheResolved"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function RunCapture(const AArgs: string; out AOutput: string): Integer;
      /// <summary>`query --name AName --json` -> raw output, or '' + a reason.
      /// AName must be BARE: a dotted name matches nothing.</summary>
      /// <param name="AName"><!-- drag-lint:auto type -->const string</param>
      /// <param name="AJson"><!-- drag-lint:auto type -->out string</param>
      /// <param name="AError"><!-- drag-lint:auto type -->out string</param>
      /// <returns><!-- drag-lint:auto -->Boolean -- Observed: QueryJsonFor(AName, AJson,
      /// AError, Ignored).</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: ConvRules.Engine.TEngineAdapter.EnumMembersOf/4 (ConvRules.Engine.pas), ConvRules.Engine.TEngineAdapter.ResolveTypeLocation/5 (ConvRules.Engine.pas)</para>
      /// <para>Calls: ConvRules.Engine.TEngineAdapter.QueryJsonFor/4</para>
      /// <para>Overload 1 of 2</para>
      /// <para>Directives: overload</para>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.QueryJsonFor"/>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.AddSqlColumnOfDb"/>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.AddUnitsOfDb"/>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.ApplyConversion"/>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.CacheResolved"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function QueryJsonFor(const AName: string; out AJson, AError: string): Boolean; overload;
      /// <summary>As above, also reporting the engine's EXIT CODE.</summary>
      /// <param name="AName"><!-- drag-lint:auto type -->const string</param>
      /// <param name="AJson"><!-- drag-lint:auto type -->out string</param>
      /// <param name="AError"><!-- drag-lint:auto type -->out string</param>
      /// <param name="ACode">0 ok; 1 zero hits (not a fault); anything else is a
      /// HARD failure -- 2 is an unusable --db list. Callers that treat a miss as
      /// benign must still not treat a hard failure that way.</param>
      /// <returns><!-- drag-lint:auto -->Boolean -- Observed: False.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: ConvRules.Engine.TEngineAdapter.QueryJsonFor/3 (ConvRules.Engine.pas), ConvRules.Engine.TEngineAdapter.ResolveClassQName/3 (ConvRules.Engine.pas)</para>
      /// <para>Calls: ConvRules.Engine.TEngineAdapter.DbArgs, ConvRules.Engine.TEngineAdapter.RunCapture, Format, Trim</para>
      /// <para>Overload 2 of 2</para>
      /// <para>Mutates: AError (out), ACode (out), AJson (out)</para>
      /// <para>Directives: overload</para>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.DbArgs"/>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.RunCapture"/>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.AddSqlColumnOfDb"/>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.AddUnitsOfDb"/>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.ApplyConversion"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function QueryJsonFor(const AName: string; out AJson, AError: string; out ACode: Integer): Boolean; overload;
      /// <param name="ADbs"><!-- drag-lint:auto type -->const TArray&lt;string&gt;</param>
      /// <returns><!-- drag-lint:auto type -->string</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: ConvRules.Engine.TEngineAdapter.ApplyConversion (ConvRules.Engine.pas), ConvRules.Engine.TEngineAdapter.DbArgs (ConvRules.Engine.pas), ConvRules.Engine.TEngineAdapter.ListDescendantsOf/4 (ConvRules.Engine.pas)</para>
      /// <para>Calls: Format, Trim</para>
      /// <para>Directives: overload</para>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.AddSqlColumnOfDb"/>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.AddUnitsOfDb"/>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.ApplyConversion"/>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.CacheResolved"/>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.CapabilityNames"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function DbArgsFor(const ADbs: TArray<string>): string; overload;
      /// <returns><!-- drag-lint:auto type -->string</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: ConvRules.Engine.TEngineAdapter.GetProptree (ConvRules.Engine.pas), ConvRules.Engine.TEngineAdapter.OutlineClasses (ConvRules.Engine.pas), ConvRules.Engine.TEngineAdapter.QueryJsonFor/4 (ConvRules.Engine.pas), ConvRules.Engine.TEngineAdapter.ResolveClassQName/3 (ConvRules.Engine.pas), ConvRules.Engine.TEngineAdapter.ResolveUnitFile (ConvRules.Engine.pas) (+2 more)</para>
      /// <para>Calls: ConvRules.Engine.TEngineAdapter.DbArgsFor</para>
      /// <para>Reads: FDbList</para>
      /// <para>Directives: overload</para>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.DbArgsFor"/>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.AddSqlColumnOfDb"/>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.AddUnitsOfDb"/>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.ApplyConversion"/>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.CacheResolved"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function DbArgs: string; overload;
      /// <summary>The --castlib argument for convert-apply / convert-validate.</summary>
      /// <returns>' --castlib "&lt;file&gt;"' when CastLibFile names an existing file, else ''.</returns>
      function CastLibArgs: string;
      /// <summary>Qualify a bare class name to its unit-qualified form (TcxButton ->
      /// cxButtons.TcxButton) via `query --name`, which is what `proptree --qname`
      /// requires. Discards the tie count; see the overload below.</summary>
      /// <param name="AName"><!-- drag-lint:auto type -->const string</param>
      /// <returns><!-- drag-lint:auto -->string -- Observed: ResolveClassQName(AName,
      /// Ambiguity).</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: ConvRules.Engine.TEngineAdapter.DeclaringUnitOf (ConvRules.Engine.pas)</para>
      /// <para>Calls: ConvRules.Engine.TEngineAdapter.ResolveClassQName/2</para>
      /// <para>Overload 1 of 3</para>
      /// <para>Directives: overload</para>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.ResolveClassQName"/>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.AddSqlColumnOfDb"/>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.AddUnitsOfDb"/>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.ApplyConversion"/>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.CacheResolved"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function ResolveClassQName(const AName: string): string; overload;

      /// <summary>As the two-argument form, but REPORTS a hard engine failure
      /// instead of silently returning the bare name.</summary>
      /// <param name="AName"><!-- drag-lint:auto type -->const string</param>
      /// <param name="AAmbiguity"><!-- drag-lint:auto type -->out Integer</param>
      /// <param name="AError">'' when the name resolved OR when the index simply
      /// holds no such class (both are ordinary outcomes). Non-empty only when the
      /// query could not be answered at all -- an unusable --db list above all.</param>
      /// <returns><!-- drag-lint:auto -->string -- Observed: AName; LHit.QName;
      /// Sym.QualifiedName.</returns>
      /// <remarks>
      /// The distinction is load-bearing. Without it a dead --db path and an
      /// unknown type are the same event to the caller, the bare name flows on to
      /// proptree (which, unlike query, tolerates a missing --db and answers from the
      /// rest), and a CONFIGURATION fault is reported as "class not found" -- blaming
      /// the type for a broken index list. That cost a full debugging session on
      /// 2026-09-09; pinned by resolve.harderror.* in ConvRulesModelTests.
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: ConvRules.Engine.TEngineAdapter.GetProptree (ConvRules.Engine.pas), ConvRules.Engine.TEngineAdapter.ResolveClassQName/2 (ConvRules.Engine.pas)</para>
      /// <para>Calls: ConvRules.Engine.ParseQuerySymbols, ConvRules.Engine.SelectQuerySymbol, ConvRules.Engine.TEngineAdapter.CacheResolved, ConvRules.Engine.TEngineAdapter.DbArgs, ConvRules.Engine.TEngineAdapter.QueryJsonFor/4, Pos, SameText, UpperCase</para>
      /// <para>Overload 2 of 3</para>
      /// <para>Reads: FResolveCache</para>
      /// <para>Mutates: AAmbiguity (out), AError (out)</para>
      /// <para>Directives: overload</para>
      /// <seealso cref="ConvRules.Engine.ParseQuerySymbols"/>
      /// <seealso cref="ConvRules.Engine.SelectQuerySymbol"/>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.CacheResolved"/>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.DbArgs"/>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.QueryJsonFor"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function ResolveClassQName(const AName: string; out AAmbiguity: Integer; out AError: string): string; overload;

      /// <summary>As above, reporting how many CLASS rows carried EXACTLY this
      /// name.</summary>
      /// <param name="AName">Bare class name. Returned unchanged (with AAmbiguity 0)
      /// when it already contains a '.', when it is empty, or when no class row
      /// carries it.</param>
      /// <param name="AAmbiguity">1 when exactly one class is named AName. &gt; 1 when
      /// several are and the result is one of them, chosen by SelectQuerySymbol's
      /// VCL-preferred tie-break -- the caller must still SAY SO. 0 when nothing
      /// resolved.</param>
      /// <returns>The chosen row's qualified_name, or AName unchanged.</returns>
      /// <remarks>
      /// Selection goes through the same ParseQuerySymbols/SelectQuerySymbol
      /// pair the go-to-definition path uses, narrowed to kind='class' first (proptree
      /// wants the class, and a same-named enum or record would otherwise win the tier-0
      /// tie). The rows are pre-filtered rather than ranked because `--name` is a
      /// SUBSTRING match: measured against library-Win64 on 2026-08-02, `--name TLabel`
      /// returns 34 rows of which most are kind='component' DFM instances. Ties between
      /// frameworks are the normal case, not the exotic one -- TEdit has two classes
      /// (FMX.Edit and Vcl.StdCtrls) and TButton four -- so the VCL-preferred tie-break
      /// inherited from SelectQuerySymbol is what stops a bare VCL control name resolving
      /// to a FireMonkey property tree, and the count is what keeps that choice visible
      /// rather than silent.
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: ConvRules.Engine.TEngineAdapter.ResolveClassQName/1 (ConvRules.Engine.pas)</para>
      /// <para>Calls: ConvRules.Engine.TEngineAdapter.ResolveClassQName/3</para>
      /// <para>Returns: ResolveClassQName(AName, AAmbiguity, Ignored)</para>
      /// <para>Overload 3 of 3</para>
      /// <para>Directives: overload</para>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.ResolveClassQName"/>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.AddSqlColumnOfDb"/>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.AddUnitsOfDb"/>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.ApplyConversion"/>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.CacheResolved"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function ResolveClassQName(const AName: string; out AAmbiguity: Integer): string; overload;
      /// <summary>Adds every unit name indexed in ADb to ASeen (ListUnits' per-DB step).</summary>
      /// <param name="ADb">One index path.</param>
      /// <param name="ASeen">Receives the names; the caller owns it and sets its dedup rules.</param>
      /// <param name="AError">Receives the failure text; '' on success.</param>
      /// <returns>False when the engine could not answer from ADb.</returns>
      function AddUnitsOfDb(const ADb: string; ASeen: TStringList; out AError: string): Boolean;
      /// <summary>Runs ASql against ADb alone: one read-only `sql --json` call with a
      /// row cap of SQL_ROW_CAP (the verb's default cap is 200) and an engine-side
      /// timeout of SQL_TIMEOUT_MS. The one runner every `sql` read here goes through;
      /// the answer is read with ParseSqlRows into POSITIONAL rows of strings.</summary>
      /// <param name="ADb">One index path.</param>
      /// <param name="ASql">A SELECT; no double quote (it is passed inside one).</param>
      /// <param name="AWhat">Names the read in AError ('class lookup of TFoo').</param>
      /// <param name="ARequireFresh">True: an answer the engine marks "stale" (a file
      /// changed on disk since it was indexed) is a failure -- a stale DB is not
      /// authoritative. False: a stale answer is used as is (listings).</param>
      /// <param name="ARows">Receives the rows; [] on failure.</param>
      /// <param name="AError">Receives the failure text naming ADb; '' on success.</param>
      /// <returns>False on a non-zero exit (2: missing --db or stale schema, "Nothing was
      /// answered"; 3: FATAL or the watchdog), unparseable or truncated output, or a
      /// stale answer when ARequireFresh.</returns>
      function SqlRowsOfDb(const ADb, ASql, AWhat: string; ARequireFresh: Boolean; out ARows: TArray<TArray<string>>; out AError: string): Boolean;
      /// <summary>Adds the FIRST column of every row ASql returns from ADb to
      /// ASeen, via SqlRowsOfDb (a stale answer is accepted).</summary>
      /// <param name="ADb">One index path.</param>
      /// <param name="ASql">A one-column SELECT.</param>
      /// <param name="AWhat">Names the listing in AError ('unit listing').</param>
      /// <param name="ASeen">Receives the values; the caller owns it and sets its dedup rules.</param>
      /// <param name="AError">Receives the failure text; '' on success.</param>
      /// <returns>False when the engine could not answer from ADb.</returns>
      function AddSqlColumnOfDb(const ADb, ASql, AWhat: string; ASeen: TStringList; out AError: string): Boolean;
      /// <summary>Store one ResolveClassQName answer under AKey (thread-safe).</summary>
      /// <param name="AKey">Upper-cased name + #0 + DbArgs.</param>
      /// <param name="AQName">The answer.</param>
      /// <param name="AAmbiguity">How many classes carry the name.</param>
      procedure CacheResolved(const AKey, AQName: string; AAmbiguity: Integer);
    public
      /// <summary>The .pas file that declares unit AUnit, via `query --name AUnit
      /// --json` (the kind=unit row's "file"). '' if the unit is not indexed.</summary>
      /// <param name="AUnit"><!-- drag-lint:auto type -->const string</param>
      /// <returns><!-- drag-lint:auto -->string -- Observed: ''; AUnit; FileP.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: ConvRules.Engine.TEngineAdapter.ListControlTypesInUnit (ConvRules.Engine.pas), ConvRules.MainForm.TConvRulesForm.HarvestUnitFile (ConvRules.MainForm.pas)</para>
      /// <para>Calls: ConvRules.Engine.TEngineAdapter.DbArgs, ConvRules.Engine.TEngineAdapter.RunCapture, Copy, Format, Pos, SameText</para>
      /// <para>Complexity: 13 (cyclomatic, outer body), 55 lines (full implementation)</para>
      /// <para>Touches: file system</para>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.DbArgs"/>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.RunCapture"/>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.AddSqlColumnOfDb"/>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.AddUnitsOfDb"/>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.ApplyConversion"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function ResolveUnitFile(const AUnit: string): string;
      /// <summary><!-- drag-lint:auto sum -->TEngineAdapter</summary>
      /// <param name="AExePath"><!-- drag-lint:auto type -->const string</param>
      /// <param name="ADbList"><!-- drag-lint:auto type -->const TArray&lt;string&gt;</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: ConvRules.ConvertTab.TConvertTab.ConvertClick (ConvRules.ConvertTab.pas), ConvRules.ConvertTab.TConvertTab.Create (ConvRules.ConvertTab.pas), ConvRules.MainForm.TConvRulesForm.Create (ConvRules.MainForm.pas)</para>
      /// <para>constructor</para>
      /// <para>Writes: FExePath, FDbList, FInfoTimeoutMs</para>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.AddSqlColumnOfDb"/>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.AddUnitsOfDb"/>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.ApplyConversion"/>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.CapabilityNames"/>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.DbArgs"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      constructor Create(const AExePath: string; const ADbList: TArray<string>);

      /// <summary>Replace the adapter's default DB list (used by proptree /
      /// scaffold / validate / class-name resolution). Called when the editor's
      /// FROM or TO platform changes so type resolution targets the new
      /// libraries.</summary>
      /// <param name="ADbs"><!-- drag-lint:auto type -->const TArray&lt;string&gt;</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: ConvRules.MainForm.TConvRulesForm.PlatformChanged (ConvRules.MainForm.pas)</para>
      /// <para>Writes: FDbList</para>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.AddSqlColumnOfDb"/>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.AddUnitsOfDb"/>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.ApplyConversion"/>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.CapabilityNames"/>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.Create"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure SetDbs(const ADbs: TArray<string>);
      /// <summary>Forget every cached class-name resolution.</summary>
      /// <remarks>ResolveClassQName caches its answers for the session -- each rule
      /// click used to pay a 0.5-1.2 s `query` per class and flash the progress
      /// window. SetDbs and IndexProject clear the cache themselves; call this when
      /// the index changed some other way (the Convert tab's own adapter reindexed).</remarks>
      procedure ClearResolveCache;
      /// <summary>Frees the resolution cache.</summary>
      destructor Destroy; override;
      /// <summary>The adapter's current default DB list (read-only view).</summary>
      /// <returns><!-- drag-lint:auto -->TArray&lt;string&gt; -- Observed: FDbList.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Reads: FDbList</para>
      /// <para>Owns returned: borrowed</para>
      /// <para>Effect-free (proven)</para>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.AddSqlColumnOfDb"/>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.AddUnitsOfDb"/>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.ApplyConversion"/>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.CapabilityNames"/>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.Create"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function DbList: TArray<string>;

      /// <summary>proptree --qname X [--min-visibility V] --refs-as-leaves --format
      /// json. AMinVisibility ('published'|'public'|'') selects the target surface
      /// (engine schema v17); '' emits every leaf. Returns False + empty tree if the
      /// type does not resolve (exit 1), the exe/db is unusable (exit 2, or the engine's
      /// FATAL exit 3 -- reported with its output, never as a timeout), the call
      /// exceeded CONVERT_TIMEOUT_MS (ENGINE_OUTCOME_TIMEOUT), or the user cancelled it
      /// (ENGINE_OUTCOME_CANCELLED; LastCancelled is then True). Appends
      /// DepthArgs(TreeDepth, ProgressLines) and runs through LongCallRunner when one is
      /// set (inline, uncancellable, otherwise).</summary>
      /// <param name="AQname">Bare ('TcxButton') or unit-qualified
      /// ('cxButtons.TcxButton'); a bare name is qualified first via
      /// ResolveClassQName.</param>
      /// <param name="ATree"><!-- drag-lint:auto type -->out TProptree</param>
      /// <param name="AError"><!-- drag-lint:auto type -->out string</param>
      /// <param name="ANote">'' unless a BARE name matched several classes, in which
      /// case it says how many and which one was used -- e.g. 'TEdit: 2 classes carry
      /// that name; used FMX.Edit.TEdit.'. The tree that comes back is then only one of
      /// the candidates, so the caller MUST show this even though the call succeeded.
      /// Never a reason to treat the result as a failure.</param>
      /// <param name="AMinVisibility"><!-- drag-lint:auto type -->const string = ''</param>
      /// <returns><!-- drag-lint:auto -->Boolean -- Observed: False; True.</returns>
      /// <exception cref="Exception"><!-- drag-lint:auto exc -->via ConvRules.Engine.ParseProptreeJson: proptree: response is not a JSON object</exception>
      /// <remarks>
      /// --refs-as-leaves is ALWAYS passed, so a TComponent-typed property
      /// appears as a single leaf and is NOT recursed into. Callers therefore do not
      /// see paths through a component reference (no 'Action.Owner.Name'); those are
      /// references, not owned sub-objects, and are not assignable targets. Leaves
      /// through owned TPersistent sub-objects ('Colors.Button.FormattedText.*') are
      /// still returned in full. ATree.Truncated reports the engine's own cap and is
      /// True even for a bounded call on a large DevExpress control.
      /// LastCancelled is reset at the START of every call, so it never carries a
      /// previous cancel through a later failure. An exception from LongCallRunner
      /// (the progress window re-raises its worker's) is returned as False with the
      /// message in AError, never raised to the caller.
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: ConvRules.MainForm.TConvRulesForm.DoNewConversion (ConvRules.MainForm.pas), ConvRules.MainForm.TConvRulesForm.LoadGridForBlock (ConvRules.MainForm.pas)</para>
      /// <para>Calls: ConvRules.Engine.DepthArgs, ConvRules.Engine.ParseProptreeJson, ConvRules.Engine.TEngineAdapter.DbArgs, ConvRules.Engine.TEngineAdapter.ResolveClassQName/3, ConvRules.Engine.TEngineAdapter.RunCaptureStreaming, Default, FLongCallRunner, Format, LWork, Trim</para>
      /// <para>Reads: FTreeDepth, FProgressLines, FLongCallRunner   Writes: FLastCancelled</para>
      /// <para>Catches: Exception (swallowed)</para>
      /// <para>Mutates: AError (out), ANote (out), ATree (out)</para>
      /// <seealso cref="ConvRules.Engine.DepthArgs"/>
      /// <seealso cref="ConvRules.Engine.ParseProptreeJson"/>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.DbArgs"/>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.ResolveClassQName"/>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.RunCaptureStreaming"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function GetProptree(const AQname: string; out ATree: TProptree; out AError: string; out ANote: string; const AMinVisibility: string = ''): Boolean;

      /// <summary>The unit that declares ATypeName, derived by resolving it to its
      /// unit-qualified form (ResolveClassQName) and taking the part before the LAST
      /// dot (so 'Vcl.Graphics.TFont' -> 'Vcl.Graphics', 'cxButtons.TcxButton' ->
      /// 'cxButtons'). '' when the type does not resolve (no dot in the qname). Used
      /// by the editor's "derive units from conversions".</summary>
      /// <param name="ATypeName"><!-- drag-lint:auto type -->const string</param>
      /// <returns><!-- drag-lint:auto -->string -- Observed: QN.Substring(0, DotPos); ''.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: ConvRules.MainForm.TConvRulesForm.AddDerivedUnitRules (ConvRules.MainForm.pas), ConvRules.MainForm.TConvRulesForm.DeclaringUnitCached (ConvRules.MainForm.pas)</para>
      /// <para>Calls: ConvRules.Engine.TEngineAdapter.ResolveClassQName/1</para>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.ResolveClassQName"/>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.AddSqlColumnOfDb"/>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.AddUnitsOfDb"/>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.ApplyConversion"/>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.CapabilityNames"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function DeclaringUnitOf(const ATypeName: string): string;

      /// <summary>List every class that transitively descends from AAncestor (e.g.
      /// 'TControl' -> all visual controls: TEdit, TLabel, TcxTextEdit, ...), deduped
      /// + sorted. Backed by the `query descendants --of &lt;A>` verb. Returns False +
      /// AError on failure.</summary>
      /// <param name="AAncestor"><!-- drag-lint:auto type -->const string</param>
      /// <param name="ANames"><!-- drag-lint:auto type -->out TArray&lt;string&gt;</param>
      /// <param name="AError"><!-- drag-lint:auto type -->out string</param>
      /// <returns><!-- drag-lint:auto -->Boolean -- Observed:
      /// ListDescendantsOf(AAncestor, FDbList, ANames, AError).</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: ConvRules.MainForm.TConvRulesForm.LoadDescendantSet (ConvRules.MainForm.pas)</para>
      /// <para>Calls: ConvRules.Engine.TEngineAdapter.ListDescendantsOf/4</para>
      /// <para>Overload 1 of 2</para>
      /// <para>Reads: FDbList</para>
      /// <para>Directives: overload</para>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.ListDescendantsOf"/>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.AddSqlColumnOfDb"/>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.AddUnitsOfDb"/>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.ApplyConversion"/>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.CacheResolved"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function ListDescendantsOf(const AAncestor: string; out ANames: TArray<string>; out AError: string): Boolean; overload;

      /// <summary>As ListDescendantsOf, but queries an EXPLICIT db set (ADbs) instead
      /// of the adapter's default, so each picker side can scope to its own platform
      /// library. Names from all listed DBs are merged + deduped, so listing several
      /// DBs can only add names, never remove them.</summary>
      /// <param name="AAncestor"><!-- drag-lint:auto type -->const string</param>
      /// <param name="ADbs"><!-- drag-lint:auto type -->const TArray&lt;string&gt;</param>
      /// <param name="ANames"><!-- drag-lint:auto type -->out TArray&lt;string&gt;</param>
      /// <param name="AError"><!-- drag-lint:auto type -->out string</param>
      /// <returns><!-- drag-lint:auto -->Boolean -- Observed: False; True.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: ConvRules.Engine.TEngineAdapter.ListDescendantsOf/3 (ConvRules.Engine.pas), ConvRules.MainForm.TConvRulesForm.LoadAllClasses (ConvRules.MainForm.pas), TestPickerDatasource (ConvRulesModelTests.dpr), TestPlatformRescope (ConvRulesModelTests.dpr)</para>
      /// <para>Calls: ConvRules.Engine.TEngineAdapter.DbArgsFor, ConvRules.Engine.TEngineAdapter.RunCapture, Format, Pos, Trim</para>
      /// <para>Overload 2 of 2</para>
      /// <para>Mutates: AError (out), ANames (out)</para>
      /// <para>Directives: overload</para>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.DbArgsFor"/>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.RunCapture"/>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.AddSqlColumnOfDb"/>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.AddUnitsOfDb"/>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.ApplyConversion"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function ListDescendantsOf(const AAncestor: string; const ADbs: TArray<string>; out ANames: TArray<string>; out AError: string): Boolean; overload;

      /// <summary>Every unit name (kind=unit) in the adapter's own DB set --
      /// library and project alike -- sorted: ListUnits over DbList. Returns
      /// False + AError on failure.</summary>
      /// <param name="ANames"><!-- drag-lint:auto type -->out TArray&lt;string&gt;</param>
      /// <param name="AError"><!-- drag-lint:auto type -->out string</param>
      /// <returns><!-- drag-lint:auto -->Boolean -- Observed: ListUnits(FDbList, ANames,
      /// AError).</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: ConvRules.MainForm.TConvRulesForm.CbLoadUnits (ConvRules.MainForm.pas)</para>
      /// <para>Calls: ConvRules.Engine.TEngineAdapter.ListUnits</para>
      /// <para>Reads: FDbList</para>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.ListUnits"/>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.AddSqlColumnOfDb"/>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.AddUnitsOfDb"/>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.ApplyConversion"/>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.CapabilityNames"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function ListProjectUnits(out ANames: TArray<string>; out AError: string): Boolean;

      /// <summary>List the unit names (kind=unit) indexed in exactly the DBs
      /// given, sorted and de-duplicated case-insensitively. Backed by one
      /// read-only `sql` query per DB (see AddUnitsOfDb for why not a listing
      /// verb).</summary>
      /// <param name="ADbs">The DB set to ask, independent of the adapter's own
      /// set -- the unit picker asks the project DB and each library DB
      /// separately so it can list them in separate columns.</param>
      /// <param name="ANames">Receives the unit names; empty on failure.</param>
      /// <param name="AError">Receives the failure text; '' on success.</param>
      /// <returns>False as soon as one DB cannot be read; ANames is then empty.</returns>
      function ListUnits(const ADbs: TArray<string>; out ANames: TArray<string>; out AError: string): Boolean;

      /// <summary>The paths of every file indexed in exactly the DBs given (the
      /// `files` table), de-duplicated case-insensitively. Backed by one
      /// read-only `sql` query per DB, like ListUnits.</summary>
      /// <param name="ADbs">The DB set to ask; the Convert tab passes the project
      /// DB alone.</param>
      /// <param name="APaths">Receives the paths as the engine stored them (full
      /// paths); empty on failure.</param>
      /// <param name="AError">Receives the failure text; '' on success.</param>
      /// <returns>False as soon as one DB cannot be read; APaths is then empty.</returns>
      /// <remarks>convert-apply finds a unit's .dfm block by PATH, so the Convert
      /// tab's pre-flight and row flags match these paths, not unit names
      /// (ConvRules.ConvertRun.UnitInIndex).</remarks>
      function ListIndexedFiles(const ADbs: TArray<string>; out APaths: TArray<string>; out AError: string): Boolean;

      /// <summary>The unit that declares class AClassName in ADb, and the class's first
      /// ancestor -- one read-only `sql` over symbols (kind class), files and
      /// type_ancestors (ordinal 0), the class name matched COLLATE NOCASE.</summary>
      /// <param name="ADb">The PROJECT index (the authority for project classes).</param>
      /// <param name="AClassName">A bare class name from a .dfm.</param>
      /// <param name="APasPath">Receives the declaring unit's path as indexed; '' unless cloFound.</param>
      /// <param name="AParentClass">Receives the first ancestor's name as written; '' when none.</param>
      /// <param name="AError">Receives the failure text; '' unless cloFailed.</param>
      /// <returns>See TClassLookupOutcome. A name that is not a plain identifier is
      /// cloAbsent without an engine call (it came from .dfm text). A missing,
      /// locked or stale-schema ADb (engine exit 2 / 3), or an answer the engine marks
      /// stale, is cloFailed, never cloAbsent.</returns>
      function LookupClass(const ADb, AClassName: string; out APasPath, AParentClass, AError: string): TClassLookupOutcome;
      /// <summary>The fields class AClassName ITSELF declares in APasPath whose type is
      /// one of AFromTypes (symbols kind field, parent_id = the class row, signature
      /// compared COLLATE NOCASE) -- one read-only `sql`.</summary>
      /// <param name="ADb">The PROJECT index.</param>
      /// <param name="AClassName">A plain-identifier class name.</param>
      /// <param name="APasPath">The declaring unit as LookupClass returned it; pins the
      /// class row to that file (compared COLLATE NOCASE).</param>
      /// <param name="AFromTypes">Bare From types; only plain identifiers are used.</param>
      /// <param name="AFields">Receives the fields; [] on failure.</param>
      /// <param name="AError">Receives the failure text; '' on success.</param>
      /// <returns>False when the engine could not answer or the answer is stale. True
      /// with [] and no engine call when AClassName is not a plain identifier or no
      /// From type is.</returns>
      /// <remarks>A field declared with a unit-qualified type ('DBTables.TTable') is
      /// not matched: signature is compared whole.</remarks>
      function ListClassFields(const ADb, AClassName, APasPath: string; const AFromTypes: TArray<string>; out AFields: TArray<TEngineField>; out AError: string): Boolean;
      /// <summary>The identifiers used inside AClassName's methods in AUnitPas: refs of
      /// kind read / write / member-access / call whose enclosing routine's qualified
      /// name contains '.AClassName.', and whose symbol is unresolved or a FIELD -- a
      /// resolved local or parameter is not a field use, and neither is an unresolved
      /// ref whose name (implicit-Self) or receiver is a local / parameter of the
      /// enclosing routine -- one read-only `sql`.</summary>
      /// <param name="ADb">The PROJECT index.</param>
      /// <param name="AUnitPas">The unit's path as indexed (compared COLLATE NOCASE).</param>
      /// <param name="AClassName">The unit's form / data-module class.</param>
      /// <param name="ARefs">Receives [name, receiver, line] rows; [] on failure.</param>
      /// <param name="AError">Receives the failure text; '' on success.</param>
      /// <returns>False when the engine could not answer, the answer is stale, or
      /// AUnitPas is not in ADb's files (a second read, made only when no ref matched:
      /// an unindexed unit is unknown, never "no uses"). True with [] and no engine
      /// call when AClassName is not a plain identifier.</returns>
      /// <remarks>Implicit-Self uses inside the class's own methods are UNRESOLVED in
      /// the index (symbol_id NULL), so the filter is by enclosing class and name, not
      /// by member_accesses (measured on DMTEST 2026-10-05).</remarks>
      function ListCodeRefs(const ADb, AUnitPas, AClassName: string; out ARefs: TArray<TEngineCodeRef>; out AError: string): Boolean;

      /// <summary>The distinct component TYPES placed on AUnit's form, read from the
      /// unit's companion .dfm (`object &lt;Name&gt;: &lt;TType&gt;` lines) -- the
      /// authoritative list of what the designer actually dropped on the form. Used
      /// to pre-fill the grid's From column from a project unit. AControlSet is
      /// accepted for signature compatibility but NOT used to filter: a real DFM
      /// component (Orpheus TOvc*, Raize TRz*, DevExpress Tcx*) is kept even when its
      /// ancestry to TComponent is unresolved in the library index. Returns [] (not
      /// an error) when the unit has no .dfm or is not indexed.</summary>
      /// <param name="AUnit"><!-- drag-lint:auto type -->const string</param>
      /// <param name="AControlSet"><!-- drag-lint:auto type -->const TArray&lt;string&gt;</param>
      /// <param name="ATypes"><!-- drag-lint:auto type -->out TArray&lt;string&gt;</param>
      /// <param name="AError"><!-- drag-lint:auto type -->out string</param>
      /// <returns><!-- drag-lint:auto -->Boolean -- Observed: False; True.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: ConvRules.MainForm.TConvRulesForm.DoLoadUnit (ConvRules.MainForm.pas)</para>
      /// <para>Calls: ChangeFileExt, CharInSet, ConvRules.Engine.TEngineAdapter.ResolveUnitFile, Copy, Pos, Trim, TrimLeft</para>
      /// <para>Complexity: 11 (cyclomatic, outer body), 70 lines (full implementation)</para>
      /// <para>Catches: Exception (swallowed)</para>
      /// <para>Mutates: AError (out), ATypes (out)</para>
      /// <para>Touches: file system</para>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.ResolveUnitFile"/>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.AddSqlColumnOfDb"/>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.AddUnitsOfDb"/>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.ApplyConversion"/>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.CapabilityNames"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function ListControlTypesInUnit(const AUnit: string; const AControlSet: TArray<string>; out ATypes: TArray<string>; out AError: string): Boolean;

      /// <summary>Where AType is declared: `query --name AType --json`, narrowed to an
      /// exact-name, type-like row (see SelectQuerySymbol -- `--name` is a substring
      /// match, so the first row is regularly the wrong symbol).</summary>
      /// <param name="AType">Bare ('TabcButtonStyle') or unit-qualified type name, as it
      /// appears in a grid/pool cell.</param>
      /// <param name="AFile">Absolute path of the declaring file; '' when False.</param>
      /// <param name="ALine">1-based declaration line; 0 when False. Clamped to a
      /// minimum of 1 on success -- see ParseQueryLocation.</param>
      /// <param name="AError">Why it failed; '' on success.</param>
      /// <returns>False when the type is not in the configured indexes, when the exe or
      /// a DB is unusable, or when the call exceeded ENGINE_TIMEOUT_MS.</returns>
      /// <remarks>
      /// Exit 1 from the engine means "no hits", NOT a broken call -- it is
      /// reported as a not-indexed message, not an engine failure. Method-pointer types
      /// (TNotifyEvent and friends) are among the things the index does not carry, so a
      /// perfectly ordinary event property resolves to nothing here.
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Calls: ConvRules.Engine.TEngineAdapter.ResolveTypeLocation/5</para>
      /// <para>Returns: ResolveTypeLocation(AType, AFile, ALine, AError, Ambiguity)</para>
      /// <para>Overload 1 of 2</para>
      /// <para>Directives: overload</para>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.ResolveTypeLocation"/>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.AddSqlColumnOfDb"/>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.AddUnitsOfDb"/>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.ApplyConversion"/>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.CapabilityNames"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function ResolveTypeLocation(const AType: string; out AFile: string; out ALine: Integer; out AError: string): Boolean; overload;

      /// <summary>As above, but also reports how many equally-ranked declarations carried
      /// the name.</summary>
      /// <param name="AType">Bare or unit-qualified type name.</param>
      /// <param name="AFile">Absolute path of the declaring file; '' when False.</param>
      /// <param name="ALine">1-based declaration line; 0 when False.</param>
      /// <param name="AError">Why it failed; '' on success.</param>
      /// <param name="AAmbiguity">1 when the answer was forced. &gt; 1 when AFile is one
      /// of several tied candidates, chosen by SelectQuerySymbol's VCL-preferred
      /// tie-break -- the caller must still SAY SO rather than present it as the only
      /// answer. 0 when False.</param>
      /// <returns>As the overload above.</returns>
      /// <remarks>
      /// Ties are ordinary, not exotic: `TAlignment` has three (an RTL enum and
      /// two types nested in DevExpress form classes) and `TColor` has two
      /// (Vcl.Graphics and Spring.Logging). See SelectQuerySymbol for why no row
      /// attribute can separate them.
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: ConvRules.Engine.TEngineAdapter.ResolveTypeLocation/4 (ConvRules.Engine.pas), ConvRules.MainForm.TConvRulesForm.DoGoToDefinition (ConvRules.MainForm.pas)</para>
      /// <para>Calls: ConvRules.Engine.BareTypeName, ConvRules.Engine.ParseQueryLocation, ConvRules.Engine.TEngineAdapter.QueryJsonFor/3, Format, Trim</para>
      /// <para>Returns: False; ParseQueryLocation(JSON, AType, AFile, ALine, AAmbiguity)</para>
      /// <para>Overload 2 of 2</para>
      /// <para>Mutates: AFile (out), ALine (out), AAmbiguity (out), AError (out)</para>
      /// <para>Directives: overload</para>
      /// <seealso cref="ConvRules.Engine.BareTypeName"/>
      /// <seealso cref="ConvRules.Engine.ParseQueryLocation"/>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.QueryJsonFor"/>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.AddSqlColumnOfDb"/>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.AddUnitsOfDb"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function ResolveTypeLocation(const AType: string; out AFile: string; out ALine: Integer; out AError: string; out AAmbiguity: Integer): Boolean; overload;

      /// <summary>The member identifiers of AType when it is an enum.</summary>
      /// <param name="AType">Bare or unit-qualified type name.</param>
      /// <param name="AMembers">Members in declaration order; [] when False.</param>
      /// <param name="AError">Why it failed; '' on success.</param>
      /// <returns>False when AType is not indexed, is not an enum, or its declaring
      /// file is not readable from this machine.</returns>
      /// <remarks>
      /// Two steps, because the index has no members field and no
      /// children-of query: resolve the enum row to file + start_line..end_line, then
      /// READ those source lines and hand them to ParseEnumMembers. That makes this the
      /// one adapter verb that needs the library SOURCE on disk, not just the DB.
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: ConvRules.MainForm.TConvRulesForm.DoGoToDefinition (ConvRules.MainForm.pas), ConvRules.MappingForm.TMappingForm.DoSuggestValues.Blocked (ConvRules.MappingForm.pas)</para>
      /// <para>Calls: ConvRules.Engine.TEngineAdapter.EnumMembersOf/4</para>
      /// <para>Returns: EnumMembersOf(AType, AMembers, AError, Ambiguity)</para>
      /// <para>Overload 1 of 2</para>
      /// <para>Directives: overload</para>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.EnumMembersOf"/>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.AddSqlColumnOfDb"/>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.AddUnitsOfDb"/>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.ApplyConversion"/>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.CapabilityNames"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function EnumMembersOf(const AType: string; out AMembers: TArray<string>; out AError: string): Boolean; overload;

      /// <summary>As above, but also reports how many equally-ranked declarations carried
      /// the name.</summary>
      /// <param name="AType">Bare or unit-qualified type name.</param>
      /// <param name="AMembers">Members in declaration order; [] when False.</param>
      /// <param name="AError">Why it failed; '' on success.</param>
      /// <param name="AAmbiguity">1 when the answer was forced. &gt; 1 when AMembers came
      /// from one of several tied declarations, chosen only by the engine's row order --
      /// the caller must SAY SO rather than present the list as authoritative. 0 when
      /// False.</param>
      /// <returns>As the overload above.</returns>
      /// <remarks>
      /// Ties are ordinary, not exotic -- see ResolveTypeLocation. A tied enum
      /// matters more than a tied jump: the wrong member list turns every literal check
      /// and the exhaustiveness pass into confident nonsense.
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: ConvRules.Engine.TEngineAdapter.EnumMembersOf/3 (ConvRules.Engine.pas), ConvRules.MappingForm.TMappingForm.LoadMembers (ConvRules.MappingForm.pas)</para>
      /// <para>Calls: ConvRules.Engine.BareTypeName, ConvRules.Engine.ParseEnumMembers, ConvRules.Engine.ParseQuerySymbols, ConvRules.Engine.SelectQuerySymbol, ConvRules.Engine.TEngineAdapter.QueryJsonFor/3, Format, SameText, Trim</para>
      /// <para>Returns: False; ParseEnumMembers(Decl, AMembers)</para>
      /// <para>Overload 2 of 2</para>
      /// <para>Complexity: 12 (cyclomatic, outer body), 70 lines (full implementation)</para>
      /// <para>Catches: Exception (swallowed)</para>
      /// <para>Mutates: AMembers (out), AAmbiguity (out), AError (out)</para>
      /// <para>Touches: file system</para>
      /// <para>Directives: overload</para>
      /// <seealso cref="ConvRules.Engine.BareTypeName"/>
      /// <seealso cref="ConvRules.Engine.ParseEnumMembers"/>
      /// <seealso cref="ConvRules.Engine.ParseQuerySymbols"/>
      /// <seealso cref="ConvRules.Engine.SelectQuerySymbol"/>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.QueryJsonFor"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function EnumMembersOf(const AType: string; out AMembers: TArray<string>; out AError: string; out AAmbiguity: Integer): Boolean; overload;

      /// <summary>convert-scaffold --from F --to T. Returns the raw .rules text the
      /// scaffolder emits (to be loaded into a TRuleBook), or '' + AError on failure.</summary>
      /// <param name="AFrom"><!-- drag-lint:auto type -->const string</param>
      /// <param name="ATo"><!-- drag-lint:auto type -->const string</param>
      /// <param name="ARules"><!-- drag-lint:auto type -->out string</param>
      /// <param name="AError"><!-- drag-lint:auto type -->out string</param>
      /// <returns><!-- drag-lint:auto -->Boolean -- Observed: False; True.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Calls: ConvRules.Engine.DepthArgs, ConvRules.Engine.TEngineAdapter.DbArgs, ConvRules.Engine.TEngineAdapter.RunCapture, Format, Trim</para>
      /// <para>Reads: FTreeDepth</para>
      /// <para>Mutates: AError (out), ARules (out)</para>
      /// <seealso cref="ConvRules.Engine.DepthArgs"/>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.DbArgs"/>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.RunCapture"/>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.AddSqlColumnOfDb"/>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.AddUnitsOfDb"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function Scaffold(const AFrom, ATo: string; out ARules: string; out AError: string): Boolean;

      /// <summary>convert-validate --rules FILE [--from F --to T]. Writes ARulesText
      /// to a temp file, validates, returns the parsed outcome.</summary>
      /// <param name="ARulesText">The book text to validate.</param>
      /// <param name="AFrom">From type; with ATo, every #convert block is checked
      /// against this ONE pair. '' (both) = syntax only.</param>
      /// <param name="ATo">To type; see AFrom.</param>
      /// <param name="ACancel">When set, the engine run is terminated (Output is then
      /// partial; callers must discard it); nil = not cancellable.</param>
      /// <returns>OK = exit code 0, FirstError = the first output line on failure, and
      /// Output = the whole reply for ConvRules.ValidateScope, which decides on the
      /// diagnostics rather than the exit code.</returns>
      /// <remarks>
      /// Runs with separate stdout / stderr pipes (RunCaptureStreaming), bounded by
      /// ENGINE_TIMEOUT_MS, so Output's lines are never cut by interleaving.
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: ConvRules.MainForm.TConvRulesForm.RunScopedValidate (ConvRules.MainForm.pas), TestComposedFileValidates (ConvRulesModelTests.dpr), TestValidateTextStreams (ConvRulesModelTests.dpr)</para>
      /// <para>Calls: ConvRules.Engine.TEngineAdapter.DbArgs, ConvRules.Engine.TEngineAdapter.RunCaptureStreaming, Format, Pos, Trim</para>
      /// <para>Catches: Exception (empty)</para>
      /// <para>Touches: file system</para>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.DbArgs"/>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.RunCaptureStreaming"/>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.AddSqlColumnOfDb"/>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.AddUnitsOfDb"/>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.ApplyConversion"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function ValidateText(const ARulesText, AFrom, ATo: string; const ACancel: TCancelToken = nil): TValidateResult;

      /// <summary>Every class the unit declares, from the engine's `outline`.</summary>
      /// <param name="APasFile">Full path to the .pas.</param>
      /// <param name="AClasses">Out: the class names, document order.</param>
      /// <param name="AIndexedNow">Out: True when this call had to build a scratch
      /// index first (the cold path, ~28 s). False on the warm and the
      /// already-covered paths.</param>
      /// <param name="AError">Out: why it failed; '' on success.</param>
      /// <returns>True on success. False leaves AClasses empty and AError set --
      /// the caller falls back to the text scan AND says so, because a silently
      /// short class list is the failure this feature exists to remove.</returns>
      /// <remarks>
      /// Tries `outline` against the configured DBs first: it resolves
      /// its own covering DB and exits 2 with a named ERROR when none does, so a
      /// covered unit is never indexed. When no configured DB covers it, this
      /// tries the unit's persistent scratch DB (if one already exists from a
      /// prior call) BEFORE indexing, so a warm second call never re-indexes.
      /// The index target is the single FILE -- NEVER a folder, which would
      /// widen the DB into a directory DB.
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: ConvRules.MainForm.TConvRulesForm.HarvestUnitClasses (ConvRules.MainForm.pas)</para>
      /// <para>Calls: ConvRules.Engine.ScratchDbPath, ConvRules.Engine.TEngineAdapter.DbArgs, ConvRules.Engine.TEngineAdapter.OutlineClasses.FirstLine, ConvRules.Engine.TEngineAdapter.OutlineClasses.TryOutline, ConvRules.Engine.TEngineAdapter.RunCapture, Copy, ExtractFilePath, ForceDirectories, Format, ParseOutlineClassNames, Pos, Trim</para>
      /// <para>Returns: False; True</para>
      /// <para>Catches: Exception (swallowed)</para>
      /// <para>Mutates: AClasses (out), AIndexedNow (out), AError (out)</para>
      /// <para>Touches: file system</para>
      /// <seealso cref="ConvRules.Engine.ScratchDbPath"/>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.DbArgs"/>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.OutlineClasses.FirstLine"/>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.OutlineClasses.TryOutline"/>
      /// <seealso cref="ConvRules.Engine.TEngineAdapter.RunCapture"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function OutlineClasses(const APasFile: string; out AClasses: TArray<string>;
        out AIndexedNow: Boolean; out AError: string): Boolean;

      /// <summary>Runs `drag-lint AArgs` with its own watchdog; RunCapture is this
      /// with ENGINE_TIMEOUT_MS.</summary>
      /// <param name="AArgs">The command line after the exe path.</param>
      /// <param name="ATimeoutMs">Watchdog; on expiry the child is terminated.</param>
      /// <param name="AOutput">stdout, then stderr's lines after it -- separate pipes, so a
      /// stderr line can never land inside a stdout line.</param>
      /// <returns>The engine's exit code; -1 when it could not be started; 3 on
      /// timeout.</returns>
      /// <remarks>Drains on the calling thread: from the UI thread the UI is
      /// frozen for up to ATimeoutMs.</remarks>
      function RunCaptureTimed(const AArgs: string; ATimeoutMs: Cardinal; out AOutput: string): Integer;
      /// <summary>`convert-apply --unit AUnitPas --rules ARulesFile [--castlib CastLibFile]
      /// --apply --no-backup --format json` against ADbs, bounded by CONVERT_TIMEOUT_MS.</summary>
      /// <param name="AUnitPas">The .pas to convert in place (its .dfm goes with it).</param>
      /// <param name="ARulesFile">The .rules book.</param>
      /// <param name="ADbs">--db list; the unit must be indexed in one of them.</param>
      /// <param name="AJson">The engine's output (apply/1 JSON, plus any stderr
      /// line such as a FATAL: message) -- feed it to ParseApplyJson.</param>
      /// <returns>The engine's exit code (see RunCaptureTimed).</returns>
      /// <remarks>--no-backup: the caller (ConvRules.ConvertRunner) owns the
      /// .BCK&lt;N&gt; restore point.</remarks>
      function ApplyConversion(const AUnitPas, ARulesFile: string; const ADbs: TArray<string>; out AJson: string): Integer; overload;
      /// <summary>ApplyConversion with `--only a,b` appended: convert-apply then
      /// touches only the named component instances (unit rules still run).</summary>
      /// <param name="AUnitPas">The .pas to convert in place (its .dfm goes with it).</param>
      /// <param name="ARulesFile">The .rules book.</param>
      /// <param name="ADbs">--db list; the unit must be indexed in one of them.</param>
      /// <param name="AOnly">Component names; [] = the plain call (no --only).</param>
      /// <param name="AJson">The engine's output -- feed it to ParseApplyJson.</param>
      /// <returns>The engine's exit code (see RunCaptureTimed).</returns>
      /// <remarks>With --only, a #unuse / #useswap that would leave an instance of the
      /// unit's From type unconverted makes the engine REFUSE the unit (apply/1
      /// refused=true, 'would leave N unconverted instance(s) of T'). A name that matches
      /// no instance: see the C12 Task 3 report (measured on 1.22.0).</remarks>
      function ApplyConversion(const AUnitPas, ARulesFile: string; const ADbs: TArray<string>; const AOnly: TArray<string>; out AJson: string): Integer; overload;
      /// <summary>`index --project AProjectFile --db AProjectDb` (incremental),
      /// bounded by CONVERT_TIMEOUT_MS.</summary>
      /// <param name="AProjectFile">The .dpr / .dproj that owns AProjectDb.</param>
      /// <param name="AProjectDb">The project index to refresh.</param>
      /// <param name="AOutput">The engine's output.</param>
      /// <returns>The engine's exit code (see RunCaptureTimed).</returns>
      /// <remarks>Never a folder target: that widens a project DB into a
      /// directory DB.</remarks>
      function IndexProject(const AProjectFile, AProjectDb: string; out AOutput: string): Integer;
      /// <summary>True when `info --json` reports capabilities.AName = true. The key
      /// is matched case-insensitively (MatchText over CapabilityNames).</summary>
      /// <param name="AName">Capability key, e.g. apply_unit_rules; any letter case.</param>
      /// <returns>False when the engine fails, the output is unparseable, the key
      /// is absent or not a boolean true.</returns>
      /// <remarks>The JSON is sliced from the first '{' to the last '}': the
      /// engine's "(loaded defaults from ...)" stderr line shares the pipe. Each call
      /// is one CapabilityNames probe, so it has the same InfoTimeoutMs bound (the
      /// Convert tab's apply_unit_rules check included); a timeout answers False.</remarks>
      function HasCapability(const AName: string): Boolean;
      /// <summary>One `info --json` call: every capability the engine reports as true.</summary>
      /// <returns>[] when the engine fails, its output is unparseable, or the call
      /// exceeds InfoTimeoutMs.</returns>
      /// <remarks>Bounded by InfoTimeoutMs (INFO_TIMEOUT_MS), not ENGINE_TIMEOUT_MS: the
      /// editor probes once in TConvRulesForm.Create, on the UI thread. A timeout reads
      /// as no capabilities -- the behaviour of an engine older than 1.20.6.</remarks>
      function CapabilityNames: TArray<string>;
      /// <summary>Runs `exe AArgs` with stdout and stderr on SEPARATE pipes, both drained
      /// while it runs. Progress lines on stderr go to AOnProgress; everything else on
      /// stderr is appended to AOutput after stdout.</summary>
      /// <param name="AArgs">The command line after the exe path.</param>
      /// <param name="ATimeoutMs">Watchdog; on expiry the child is terminated.</param>
      /// <param name="AOnProgress">Progress sink, called on THIS thread; may be nil.</param>
      /// <param name="ACancel">Polled every ~40 ms; when set the child is terminated; may be nil.</param>
      /// <param name="AOutput">stdout, then the non-progress stderr lines.</param>
      /// <returns>The child's own exit code (the engine's 3 = FATAL comes back as 3);
      /// -1 when it could not start; ENGINE_OUTCOME_TIMEOUT or ENGINE_OUTCOME_CANCELLED
      /// (both negative, so never mistaken for an exit code).</returns>
      /// <remarks>Blocks the calling thread. Run it on a worker (LongCallRunner) to keep
      /// the UI alive. Every exit -- normal, cancel, timeout or an exception raised by
      /// AOnProgress -- leaves no child running: a live child is terminated and its
      /// handles closed before the call returns or the exception propagates. On cancel
      /// or timeout an unterminated last stderr line is dropped, not appended.</remarks>
      function RunCaptureStreaming(const AArgs: string; ATimeoutMs: Cardinal; const AOnProgress: TProgressProc; const ACancel: TCancelToken; out AOutput: string): Integer;

      property ExePath: string read FExePath;
      /// <summary>--depth for proptree / convert-scaffold; 0 = omit (engine without book_depth).</summary>
      property TreeDepth: Integer read FTreeDepth write FTreeDepth;
      /// <summary>The .castlib handed to convert-apply and convert-validate as
      /// --castlib (C10 E11). '' or a missing file = no argument: the engine exits 2 on
      /// a file it cannot read, which would fail every validate.</summary>
      property CastLibFile: string read FCastLibFile write FCastLibFile;
      /// <summary>True = pass --progress-interval on proptree (engine reports progress_lines).</summary>
      property ProgressLines: Boolean read FProgressLines write FProgressLines;
      /// <summary>Runs proptree behind a progress window; nil = run inline, no cancel
      /// (the model tests, and any caller without a UI).</summary>
      property LongCallRunner: TLongCallRunner read FLongCallRunner write FLongCallRunner;
      /// <summary>True when the LAST GetProptree was cancelled by the user.</summary>
      property LastCancelled: Boolean read FLastCancelled;
      /// <summary>CapabilityNames' watchdog; INFO_TIMEOUT_MS after Create.</summary>
      /// <remarks>Writable so the model tests can use a short bound with a
      /// sleeping stand-in engine; the editor never changes it.</remarks>
      property InfoTimeoutMs: Cardinal read FInfoTimeoutMs write FInfoTimeoutMs;
  end;

/// <summary>PURE: the engine flags for tree depth and progress.</summary>
/// <param name="ADepth">--depth value; 0 or less omits the flag.</param>
/// <param name="AProgress">True adds --progress-interval PROGRESS_INTERVAL_S.</param>
/// <returns>'' or a string starting with a space, ready to append to a command line.</returns>
/// <remarks>Pass ADepth &gt; 0 only when the engine reports book_depth and AProgress only
/// when it reports progress_lines: an older engine rejects either flag.</remarks>
function DepthArgs(ADepth: Integer; AProgress: Boolean): string;

/// <summary>PURE: the capability keys whose value is the JSON literal true.</summary>
/// <param name="AInfoOutput">Raw `info --json` output; text before the first '{' and after
/// the last '}' (the "(loaded defaults ...)" line) is ignored.</param>
/// <returns>The keys, in document order; [] when unparseable or no capabilities object.</returns>
function ParseCapabilityNames(const AInfoOutput: string): TArray<string>;

/// <summary>PURE: True for [A-Za-z_][A-Za-z0-9_]* -- the only class and type names
/// LookupClass / ListClassFields / ListCodeRefs put into SQL.</summary>
/// <param name="AName">Candidate class name.</param>
/// <returns>False for '', dotted, quoted or otherwise decorated text.</returns>
function IsPlainIdentifier(const AName: string): Boolean;

/// <summary>PURE: reads LookupClass's `sql --json` output (rows [path, parent]).</summary>
/// <param name="ASqlJson">Raw output; text around the JSON object is ignored.</param>
/// <param name="APasPath">Receives the single declaring file; '' unless cloFound.</param>
/// <param name="AParentClass">Receives the first non-empty parent among that file's
/// rows; '' unless cloFound.</param>
/// <returns>cloFound, cloAbsent (no row), cloAmbiguous (rows from two files) or
/// cloFailed (unparseable, "truncated": true, or "stale": true).</returns>
function ParseClassLookupRows(const ASqlJson: string; out APasPath, AParentClass: string): TClassLookupOutcome;  // dl:ok unused-public-symbol@8e9e -- REVIEWED 2026-10-05 the pure JSON entry point the model tests pin (lookup.rows.*, fields.rows*, refs.rows*); the adapter reaches the same row mapper through SqlRowsOfDb

/// <summary>PURE: AText as a single-quoted SQL literal (embedded quotes doubled).</summary>
/// <param name="AText">Any text (a path).</param>
/// <returns>'...' ready to splice into a query.</returns>
function SqlQuoted(const AText: string): string;

/// <summary>PURE: ListClassFields' positional rows [name, type].</summary>
/// <param name="ASqlJson">Raw `sql --json` output.</param>
/// <param name="AFields">Receives the rows; [] when unparseable.</param>
/// <returns>False when unparseable, truncated or stale.</returns>
function ParseFieldRows(const ASqlJson: string; out AFields: TArray<TEngineField>): Boolean;  // dl:ok unused-public-symbol@16ac -- REVIEWED 2026-10-05 the pure JSON entry point the model tests pin (lookup.rows.*, fields.rows*, refs.rows*); the adapter reaches the same row mapper through SqlRowsOfDb

/// <summary>PURE: ListCodeRefs' positional rows [name, receiver, line]; a JSON null
/// reads as ''.</summary>
/// <param name="ASqlJson">Raw `sql --json` output.</param>
/// <param name="ARefs">Receives the rows; [] when unparseable.</param>
/// <returns>False when unparseable, truncated or stale.</returns>
function ParseCodeRefRows(const ASqlJson: string; out ARefs: TArray<TEngineCodeRef>): Boolean;  // dl:ok unused-public-symbol@9748 -- REVIEWED 2026-10-05 the pure JSON entry point the model tests pin (lookup.rows.*, fields.rows*, refs.rows*); the adapter reaches the same row mapper through SqlRowsOfDb

/// <summary>PURE: the distinct class names in a `drag-lint outline --format json`
/// payload, in document order.</summary>
/// <param name="AJson">The raw CLI output. A '(loaded defaults ...)' preamble or a
/// trailing 'note:' line is tolerated -- the text is sliced from the first '[' to
/// the last ']' before parsing, exactly as the IDE plugin's ParseOutlineJson does.</param>
/// <returns>One entry per distinct `"kind":"class"` name, de-duplicated
/// case-insensitively so a forward-declaration stub does not produce a second
/// row. Unparseable input returns an empty array; this never raises.</returns>
/// <remarks>
/// PURE: no process spawn, no I/O. Never raises -- malformed JSON
/// inside a well-formed pair of brackets is caught and treated as no classes,
/// same as input with no brackets at all. The "kind" match is also
/// case-insensitive (`SameText`), though the real payload only ever emits it
/// lowercase; the leniency costs nothing and matches the name dedupe.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: ConvRules.Engine.TEngineAdapter.OutlineClasses.TryOutline (ConvRules.Engine.pas)</para>
/// <para>Calls: Copy, LastDelimiter, Pos, SameText, TJSONArray, TJSONObject, Trim</para>
/// <para>Catches: Exception (swallowed)</para>
/// <para>Pure</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ParseOutlineClassNames(const AJson: string): TArray<string>;

/// <summary>The persistent per-unit scratch index for a unit no configured DB
/// covers.</summary>
/// <param name="APasFile">Full path to the .pas; '' returns ''.</param>
/// <returns>%LOCALAPPDATA%\DragLint\ConvRulesEditor\scratch\&lt;stem&gt;-&lt;hash&gt;.sqlite,
/// or %APPDATA% (TPath.GetHomePath) under the same DragLint\ConvRulesEditor\scratch
/// subpath when %LOCALAPPDATA% is blank -- still per-user, still writable.
/// ONE DB PER UNIT: an orphan form never contributes rows to any project's index
/// and never becomes an unasked-for --db in someone else's query. The hash is of
/// the upper-cased full path, so two units with the same stem cannot collide and
/// the same unit always resolves to the same DB -- which is what makes the second
/// pick cost 0.13 s instead of 27 s.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: ConvRules.Engine.TEngineAdapter.OutlineClasses (ConvRules.Engine.pas)</para>
/// <para>Calls: Cardinal, Format, GetEnvironmentVariable, Trim, UpperCase</para>
/// <para>Returns: ''; TPath.Combine(Dir, Format('%s-%.8x.sqlite', [TPath.GetFileNameWithoutExtension(Key), Hash]))</para>
/// <para>Touches: file system</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ScratchDbPath(const APasFile: string): string;

implementation

uses
  System.IOUtils
  , System.StrUtils
        {$IFDEF MSWINDOWS}
  , Winapi.Windows {$ENDIF}
  ;

// Slice the first balanced brace-object out of AText, ignoring any preamble or
// trailing lines the CLI may print around the JSON (e.g. a loaded-defaults note).
// Returns empty if no object is found. A string-literal-aware brace scanner, so
// braces inside JSON string values do not throw off the depth count.
function SliceJsonObject(const AText: string): string;
var
  i       : Integer;
  depth   : Integer;
  startIdx: Integer;
  inStr   : Boolean;
  esc     : Boolean;
begin
  Result:= '';
  startIdx:= 0; depth:= 0; inStr:= False; esc:= False;
  for i:= 1 to Length(AText) do
  begin
    if inStr then
    begin
      if esc then
        esc:= False
      else if AText[i] = '\' then
        esc:= True
      else if AText[i] = '"' then
        inStr:= False;
      Continue;
    end;
    case AText[i] of
      '"': inStr:= True;
      '{':
      begin
        if depth = 0 then
          startIdx:= i;
        Inc(depth);
      end;
      '}':
      begin
        Dec(depth);
        if depth = 0 then
          Exit(Copy(AText, startIdx, i - startIdx + 1));
      end;
    end; // case
  end; // for
end; // function

function ParseProptreeJson(const AJson: string): TProptree;
var
  Root  : TJSONObject     ;
  Arr   : TJSONArray      ;
  V     : TJSONValue      ;
  Obj   : TJSONObject     ;
  List  : TList<TPropLeaf>;
  Leaf  : TPropLeaf       ;
  BVal  : Boolean         ;
  Sliced: string          ;
begin
  Result:= Default(TProptree);
  // Tolerate CLI preamble/trailing noise by extracting just the JSON object.
  Sliced:= SliceJsonObject(AJson);
  if Sliced = '' then Sliced:= AJson; // fall back to whole text
  Root:= TJSONObject.ParseJSONValue(Sliced) as TJSONObject;
  if Root = nil then
    raise Exception.Create('proptree: response is not a JSON object');
  try
    Root.TryGetValue<string>('qname'    , Result.Qname   );
    Root.TryGetValue<string>('root_type', Result.RootType);
    if not Root.TryGetValue<Boolean>('truncated', Result.Truncated) then
      Result.Truncated:= False;

    List:= TList<TPropLeaf>.Create;
    try
      if Root.TryGetValue<TJSONArray>('properties', Arr) then
        for V in Arr do
          if V is TJSONObject then
          begin
            Obj:= V as TJSONObject;
            Leaf:= Default(TPropLeaf);
            // proptree/1 back-compat defaults: an OLD exe omits these fields, and the
            // editor must then degrade to "show everything" (writable), never hide all.
            // NB: TryGetValue's 2nd arg is `out` -- it CLEARS the target even when the
            // key is absent, so a non-empty default (member_kind) must be applied ONLY
            // when the read returns False; is_writable is read via BVal so its default
            // survives.
            Leaf.IsWritable:= True;
            Obj.TryGetValue<string>('path'       , Leaf.Path      );
            Obj.TryGetValue<string>('type'       , Leaf.TypeName  );
            Obj.TryGetValue<string>('declared_in', Leaf.DeclaredIn);
            Obj.TryGetValue<string>('kind'       , Leaf.Kind      );
            if Obj.TryGetValue<Boolean>('is_class_typed', BVal) then
              Leaf.IsClassType:= BVal;
            if Obj.TryGetValue<Boolean>('is_writable', BVal) then
              Leaf.IsWritable:= BVal;
            Obj.TryGetValue<string>('visibility', Leaf.Visibility);
            if not Obj.TryGetValue<string>('member_kind', Leaf.MemberKind) then
              Leaf.MemberKind:= 'property';
            List.Add(Leaf);
          end; // if
      Result.Leaves:= List.ToArray;
    finally
      List.Free;
    end; // try
  finally
    Root.Free;
  end; // try
end; // function

{ TEngineAdapter }

constructor TEngineAdapter.Create(const AExePath: string; const ADbList: TArray<string>);
begin
  inherited Create;
  FExePath:= AExePath;
  FDbList := ADbList;
  FInfoTimeoutMs:= INFO_TIMEOUT_MS;
  FResolveCache:= TDictionary<string, TResolvedClass>.Create;
end;

destructor TEngineAdapter.Destroy;
begin
  FResolveCache.Free;
  inherited Destroy;
end;

procedure TEngineAdapter.SetDbs(const ADbs: TArray<string>);
begin
  FDbList:= ADbs;
  ClearResolveCache; // the answers were given by the OLD database set
end;

procedure TEngineAdapter.ClearResolveCache;
begin
  TMonitor.Enter(FResolveCache);
  try
    FResolveCache.Clear;
  finally
    TMonitor.Exit(FResolveCache);
  end;
end;

function TEngineAdapter.DbList: TArray<string>;
begin
  Result:= FDbList;
end;

function TEngineAdapter.DbArgsFor(const ADbs: TArray<string>): string;
var
  Db: string;
begin
  Result:= '';
  for Db in ADbs do
    if Trim(Db) <> '' then
      Result:= Result + Format(' --db "%s"', [Db]);
end;

function TEngineAdapter.DbArgs: string;
begin
  Result:= DbArgsFor(FDbList);
end;

function TEngineAdapter.RunCapture(const AArgs: string; out AOutput: string): Integer;
begin
  Result:= RunCaptureTimed(AArgs, ENGINE_TIMEOUT_MS, AOutput);
end;

function TEngineAdapter.CastLibArgs: string;
begin
  if (FCastLibFile <> '') and TFile.Exists(FCastLibFile) then
    Result:= Format(' --castlib "%s"', [FCastLibFile])
  else
    Result:= '';
end;

function TEngineAdapter.ApplyConversion(const AUnitPas, ARulesFile: string; const ADbs: TArray<string>; out AJson: string): Integer;
begin
  Result:= ApplyConversion(AUnitPas, ARulesFile, ADbs, nil, AJson);
end;

function TEngineAdapter.ApplyConversion(const AUnitPas, ARulesFile: string; const ADbs: TArray<string>; const AOnly: TArray<string>; out AJson: string): Integer;
var
  LOnly: string;
begin
  LOnly:= '';
  if Length(AOnly) > 0 then
    LOnly:= Format(' --only "%s"', [string.Join(',', AOnly)]);
  Result:= RunCaptureTimed(Format('convert-apply --unit "%s" --rules "%s"%s%s%s --apply --no-backup --format json',
    [AUnitPas, ARulesFile, DbArgsFor(ADbs), LOnly, CastLibArgs]), CONVERT_TIMEOUT_MS, AJson);
end;

function TEngineAdapter.IndexProject(const AProjectFile, AProjectDb: string; out AOutput: string): Integer;
begin
  // --project, never a folder: a folder target widens a project DB into a directory DB.
  Result:= RunCaptureTimed(Format('index --project "%s" --db "%s"', [AProjectFile, AProjectDb]), CONVERT_TIMEOUT_MS, AOutput);
  ClearResolveCache; // the index may now declare (or no longer declare) a class
end;

function DepthArgs(ADepth: Integer; AProgress: Boolean): string;
begin
  Result:= '';
  if ADepth > 0 then
    Result:= Format(' --depth %d', [ADepth]);
  if AProgress then
    Result:= Result + Format(' --progress-interval %d', [PROGRESS_INTERVAL_S]);
end;

function ParseCapabilityNames(const AInfoOutput: string): TArray<string>;
var
  Root: TJSONValue ;
  Caps: TJSONObject;
begin
  Result:= nil;
  // The "(loaded defaults from ...)" stderr line shares the pipe, before or after.
  var LFirst: Integer:= Pos('{', AInfoOutput);
  var LLast : Integer:= LastDelimiter('}', AInfoOutput);
  if (LFirst = 0) or (LLast < LFirst) then
    Exit;
  Root:= TJSONObject.ParseJSONValue(Copy(AInfoOutput, LFirst, LLast - LFirst + 1));
  try
    if (Root is TJSONObject) and TJSONObject(Root).TryGetValue<TJSONObject>('capabilities', Caps) then
      for var LPair: TJSONPair in Caps do
        if LPair.JsonValue is TJSONTrue then
          Result:= Result + [LPair.JsonString.Value];
  finally
    Root.Free;
  end; // try
end; // function

function TEngineAdapter.HasCapability(const AName: string): Boolean;
begin
  Result:= MatchText(AName, CapabilityNames);
end;

function TEngineAdapter.CapabilityNames: TArray<string>;
var
  Output: string;
begin
  Result:= nil;
  // Its own short bound, not ENGINE_TIMEOUT_MS: this runs during start-up.
  if RunCaptureTimed('info --json', FInfoTimeoutMs, Output) = 0 then
    Result:= ParseCapabilityNames(Output);
end;

const
  MS_PER_SECOND = 1000;

{$IFDEF MSWINDOWS}
// Starts ACmdLine hidden with AStdOut / AStdErr as its output handles (pass the same
// handle twice for one merged pipe). Handles are inherited, so the caller closes its
// copies of the write ends once this returns True, and API's two handles when done.
function StartHiddenProcess(const ACmdLine: string; AStdOut, AStdErr: THandle; out API: TProcessInformation): Boolean;
var
  SI  : TStartupInfoW    ;
  CmdW: array of WideChar;
begin
  FillChar(SI, SizeOf(SI), 0);
  SI.cb:= SizeOf(SI);
  SI.dwFlags:= STARTF_USESTDHANDLES or STARTF_USESHOWWINDOW;
  SI.wShowWindow:= SW_HIDE;
  SI.hStdOutput:= AStdOut;
  SI.hStdError := AStdErr;
  SI.hStdInput := GetStdHandle(STD_INPUT_HANDLE);
  // CreateProcessW may write into its command-line buffer: hand it a private copy.
  SetLength(CmdW, Length(ACmdLine) + 1);
  Move(PChar(ACmdLine)^, CmdW[0], (Length(ACmdLine) + 1) * SizeOf(WideChar));
  FillChar(API, SizeOf(API), 0);
  Result:= CreateProcessW(nil, @CmdW[0], nil, nil, True, CREATE_NO_WINDOW, nil, nil, SI, API);
end;

function TEngineAdapter.RunCaptureTimed(const AArgs: string; ATimeoutMs: Cardinal; out AOutput: string): Integer;
const
  RUN_CAPTURE_TIMEOUT_CODE = 3; // this routine's own timeout code; its callers test for 3
begin
  // SEPARATE pipes (job C6, 2026-10-05). This used to hand the child ONE pipe for
  // both streams, which interleaves them by CHUNK: a stderr line could land inside
  // a stdout line and break the JSON / sql / query text every caller parses (seen
  // on convert-validate as "Validate: s, not a re-parse). (+3 more)"). Now stdout
  // comes first, whole, and stderr's lines follow it.
  Result:= RunCaptureStreaming(AArgs, ATimeoutMs, nil, nil, AOutput);
  if Result = ENGINE_OUTCOME_TIMEOUT then
  begin
    AOutput:= AOutput + sLineBreak + Format('[timeout: engine call exceeded %d s]', [ATimeoutMs div MS_PER_SECOND]);
    Result:= RUN_CAPTURE_TIMEOUT_CODE;
  end;
end; // function
function TEngineAdapter.RunCaptureStreaming(const AArgs: string; ATimeoutMs: Cardinal; const AOnProgress: TProgressProc; const ACancel: TCancelToken; out AOutput: string): Integer;
const
  POLL_MS   = 40;
  REAP_MS   = 2000;
  BUF_BYTES = 4096;
  // Reads per Drain call: a child that writes without pause cannot keep the loop
  // from reaching the cancel / deadline check (16 x 4 KB per pipe per turn).
  MAX_READS_PER_DRAIN = 16;
var
  SA       : TSecurityAttributes;
  OutRead  : THandle;
  OutWrite : THandle;
  ErrRead  : THandle;
  ErrWrite : THandle;
  PI       : TProcessInformation;
  Started  : Boolean;
  ExitCode : DWORD;
  StdOut   : TStringBuilder;
  ErrText  : TStringBuilder;
  Splitter : TLineSplitter;
  OnErrLine: TProc<string>;
  Outcome  : Integer;

  // Reads what APipe has ready right now, at most MAX_READS_PER_DRAIN chunks;
  // True when anything was read.
  function Drain(APipe: THandle; const AInto: TProc<string>): Boolean;
  var
    Buf      : array[0..BUF_BYTES - 1] of AnsiChar;
    Avail    : DWORD;
    BytesRead: DWORD;
    Reads    : Integer;
  begin
    Result:= False;
    Avail:= 0;
    Reads:= 0;
    while (Reads < MAX_READS_PER_DRAIN) and PeekNamedPipe(APipe, nil, 0, nil, @Avail, nil) and (Avail > 0) do
    begin
      Inc(Reads);
      BytesRead:= 0;
      if not ReadFile(APipe, Buf, SizeOf(Buf), BytesRead, nil) or (BytesRead = 0) then
        Exit;
      AInto(string(AnsiString(Copy(Buf, 0, BytesRead))));
      Result:= True;
    end;
  end;

  // Terminates the child when it is still running, then closes both of its handles.
  procedure ReapChild(const AInfo: TProcessInformation);
  begin
    if WaitForSingleObject(AInfo.hProcess, 0) <> WAIT_OBJECT_0 then
    begin
      TerminateProcess(AInfo.hProcess, DWORD(-1));
      WaitForSingleObject(AInfo.hProcess, REAP_MS);
    end;
    CloseHandle(AInfo.hProcess);
    CloseHandle(AInfo.hThread);
  end;

  // Closes AHandle when it is open and zeroes it, so the finally can call it on all four.
  procedure CloseIfOpen(var AHandle: THandle);
  begin
    if AHandle <> 0 then
      CloseHandle(AHandle);
    AHandle:= 0;
  end;

begin
  Result:= -1;
  AOutput:= '';
  OutRead:= 0;
  OutWrite:= 0;
  ErrRead:= 0;
  ErrWrite:= 0;
  Started:= False;
  PI:= Default(TProcessInformation);
  FillChar(SA, SizeOf(SA), 0);
  SA.nLength:= SizeOf(SA);
  SA.bInheritHandle:= True;
  StdOut  := TStringBuilder.Create;
  ErrText := TStringBuilder.Create;
  Splitter:= TLineSplitter.Create;
  try
    if not CreatePipe(OutRead, OutWrite, @SA, 0) or not CreatePipe(ErrRead, ErrWrite, @SA, 0) then
      Exit;
    // The child inherits only the WRITE ends; an inherited read end keeps a pipe
    // open after the child exits and the drain never sees EOF.
    SetHandleInformation(OutRead, HANDLE_FLAG_INHERIT, 0);
    SetHandleInformation(ErrRead, HANDLE_FLAG_INHERIT, 0);
    if not StartHiddenProcess(Format('"%s" %s', [FExePath, AArgs]), OutWrite, ErrWrite, PI) then
      Exit;
    Started:= True;
    CloseIfOpen(OutWrite);
    CloseIfOpen(ErrWrite);

    OnErrLine:= procedure(ALine: string)
      var
        LP: TEngineProgress;
      begin
        if TryParseProgressLine(ALine, LP) then
        begin
          if Assigned(AOnProgress) then
            AOnProgress(LP);
        end
        else
          ErrText.Append(ALine).Append(sLineBreak);
      end;
    var ToOut: TProc<string>:= procedure(S: string)
      begin
        StdOut.Append(S);
      end;
    var ToErr: TProc<string>:= procedure(S: string)
      begin
        Splitter.Feed(S, OnErrLine);
      end;

    Outcome:= 0;
    var Deadline: UInt64:= GetTickCount64 + ATimeoutMs;
    repeat
      var Got: Boolean:= Drain(OutRead, ToOut);
      Got:= Drain(ErrRead, ToErr) or Got;
      if WaitForSingleObject(PI.hProcess, if Got then 0 else POLL_MS) = WAIT_OBJECT_0 then
      begin
        // Exited: its output is finite now, so drain both pipes until both are empty.
        var More: Boolean;
        repeat
          More:= Drain(OutRead, ToOut);
          More:= Drain(ErrRead, ToErr) or More;
        until not More;
        Break;
      end;
      if (ACancel <> nil) and ACancel.IsCancelled then
        Outcome:= ENGINE_OUTCOME_CANCELLED
      else if GetTickCount64 >= Deadline then
        Outcome:= ENGINE_OUTCOME_TIMEOUT;
    until Outcome <> 0; // the finally terminates a child that is still running
    // A cancelled or timed-out run's last stderr line may be cut mid-write: drop it.
    if Outcome = 0 then
      Splitter.Flush(OnErrLine);
    AOutput:= StdOut.ToString + ErrText.ToString;
    case Outcome of
      ENGINE_OUTCOME_TIMEOUT:
        AOutput:= AOutput + sLineBreak + Format('[timeout: engine call exceeded %d s]', [ATimeoutMs div MS_PER_SECOND]);
      ENGINE_OUTCOME_CANCELLED:
        AOutput:= AOutput + sLineBreak + '[cancelled by the user]';
    end;
    if Outcome <> 0 then
      Result:= Outcome
    else if GetExitCodeProcess(PI.hProcess, ExitCode) then
      Result:= Integer(ExitCode);
  finally
    // Every way out -- cancel, timeout, or an exception from a sink, the splitter or
    // an Append -- kills a child that is still running and releases its handles, so
    // no orphaned engine is left holding the index.
    if Started then
      ReapChild(PI);
    CloseIfOpen(OutRead);
    CloseIfOpen(OutWrite);
    CloseIfOpen(ErrRead);
    CloseIfOpen(ErrWrite);
    Splitter.Free;
    ErrText.Free;
    StdOut.Free;
  end; // try
end; // function
{$ELSE}
function TEngineAdapter.RunCaptureTimed(const AArgs: string; ATimeoutMs: Cardinal; out AOutput: string): Integer;
begin
  // Editor is Windows-only (VCL); non-Windows stub keeps the unit compilable.
  AOutput:= '';
  Result:= -1;
end;

function TEngineAdapter.RunCaptureStreaming(const AArgs: string; ATimeoutMs: Cardinal; const AOnProgress: TProgressProc; const ACancel: TCancelToken; out AOutput: string): Integer;
begin
  // Editor is Windows-only (VCL); non-Windows stub keeps the unit compilable.
  AOutput:= '';
  Result:= -1;
end;
{$ENDIF}

function TEngineAdapter.GetProptree(const AQname: string; out ATree: TProptree; out AError: string; out ANote: string; const AMinVisibility: string): Boolean;
var
  Output: string ;
  Code  : Integer;
  QN    : string ;
  VisArg: string ;
  Ambig : Integer;
  ResErr: string ;
begin
  AError:= '';
  ANote := '';
  ATree:= Default(TProptree);
  // First, before any early Exit: LastCancelled describes THIS call only. A reset
  // further down left a previous cancel standing through a resolve failure.
  FLastCancelled:= False;
  QN    := AQname;
  Ambig := 0;
  ResErr:= '';
  // Target surface (engine schema v17): --min-visibility published (DFM-streamable
  // props only) or public (adds public props + public fields); '' emits all leaves.
  // --refs-as-leaves IS on main (parsed in DRagLint.CLI.pas) and is passed on every
  // call: a TComponent-typed property is a REFERENCE to another component, not an
  // owned sub-object, so expanding it (Action.Owner.Name, DropDownMenu.Tag) invents
  // targets that cannot be assigned. Leaving such properties unexpanded is both the
  // correct target surface and what bounds the walk. Measured on cxButtons.TcxButton
  // against library-Win64 + ORM3, 3 runs each, 2026-07-29:
  //   --min-visibility published              2936 leaves, mean 18.22 s
  //   ... plus --refs-as-leaves                696 leaves, mean  6.96 s
  //   no --min-visibility                    36795 leaves, mean 20.11 s
  //   ... plus --refs-as-leaves              11692 leaves, mean  7.82 s
  // Name, Tag, Left and Top are present in all four. --min-visibility filters at
  // OUTPUT time and does not shorten the walk (hence ~2 s), whereas
  // --refs-as-leaves prunes the walk itself (~11 s).
  VisArg:= '';
  if AMinVisibility <> '' then
    VisArg:= ' --min-visibility ' + AMinVisibility;
  var LTail: string:= Format('%s --refs-as-leaves --format json%s%s', [VisArg, DepthArgs(FTreeDepth, FProgressLines), DbArgs]);
  // The resolve AND the proptree run inside the long-call runner (job C6): the
  // resolve is a `query` of 0.5-1 s that used to block the UI thread with no Cancel.
  // Now the progress window covers both, its Cancel is honoured before either call
  // starts, and the editor's runner counts FTreeLoads around the whole of it.
  var LWork: TStreamingWork:= function(const AOnProgress: TProgressProc; const ACancel: TCancelToken): Integer
    begin
      Result:= ENGINE_OUTCOME_CANCELLED;
      if (ACancel = nil) or not ACancel.IsCancelled then
      begin
        // The pickers hand us a BARE class name (TcxButton); proptree --qname needs the
        // unit-qualified form (cxButtons.TcxButton). No-op if already qualified.
        QN:= ResolveClassQName(AQname, Ambig, ResErr);
        if ResErr <> '' then
          Result:= 0 // reported after the runner returns
        else if (ACancel = nil) or not ACancel.IsCancelled then
          // CONVERT_TIMEOUT_MS: the user can Cancel now, so the watchdog is a backstop only.
          Result:= RunCaptureStreaming(Format('proptree --qname "%s"', [QN]) + LTail, CONVERT_TIMEOUT_MS, AOnProgress, ACancel, Output);
      end;
    end;
  try
    if Assigned(FLongCallRunner) then
      Code:= FLongCallRunner(Format('Loading property tree for %s', [AQname]), LWork)
    else
      Code:= LWork(nil, nil);
  except
    // A proptree failure is a status message, not the application's crash dialog:
    // RunWithProgressDialog re-raises the worker's exception on this thread.
    on E: Exception do
    begin
      AError:= Format('proptree failed for %s: %s', [AQname, E.Message]);
      Exit(False);
    end;
  end; // try
  if Code = ENGINE_OUTCOME_CANCELLED then
  begin
    FLastCancelled:= True;
    AError:= Format('proptree cancelled for %s -- no tree loaded.', [AQname]);
    Exit(False);
  end;
  // A hard resolution failure is a fault in the ENGINE CALL, not in the type.
  // Report it here: proptree tolerates a --db that does not exist and answers
  // from the remaining indexes, so letting the unqualified name through would
  // produce a confident "class not found" about a perfectly real class.
  if ResErr <> '' then
  begin
    AError:= Format('cannot resolve "%s": %s', [AQname, ResErr]);
    Exit(False);
  end;
  // Several classes carry that bare name -- TEdit, TButton and TLabel all have both an
  // FMX and a VCL declaration -- and only the engine's row order chose between them.
  // Silently returning an FMX property tree for a VCL form is the failure this reports.
  if Ambig > 1 then
    ANote:= Format('%s: %d classes carry that name; used %s.', [AQname, Ambig, QN]);
  if Code = ENGINE_OUTCOME_TIMEOUT then
  begin
    // Name the Depth box only when it is usable: TreeDepth > 0 means the engine
    // reports book_depth; an older engine's box is disabled and --depth is not sent.
    var LAdvice: string:= if FTreeDepth > 0 then
      'Lower the book''s depth (Depth box, top right) or report the qname'
    else
      'Report the qname';
    AError:= Format(
      'proptree TIMED OUT for %s after %d s. %s; the index may also be being written by another process.',
      [AQname, CONVERT_TIMEOUT_MS div MS_PER_SECOND, LAdvice]);
    Exit(False);
  end;
  if Code <> 0 then
  begin
    AError:= Format('proptree failed (exit %d) for %s. The type may not be indexed, ' + 'or the index DB may be stale. Output: %s', [Code, AQname, Trim(Output)]);
    Exit(False);
  end;
  try
    ATree:= ParseProptreeJson(Output);
    Result:= True;
  except
    on E: Exception do
    begin
      AError:= 'proptree JSON parse failed: ' + E.Message;
      Result:= False;
    end;
  end;
end; // function

function TEngineAdapter.ListDescendantsOf(const AAncestor: string; out ANames: TArray<string>; out AError: string): Boolean;
begin
  Result:= ListDescendantsOf(AAncestor, FDbList, ANames, AError);
end;

function TEngineAdapter.ListDescendantsOf(const AAncestor: string; const ADbs: TArray<string>; out ANames: TArray<string>; out AError: string): Boolean;
var
  Output: string     ;
  Code  : Integer    ;
  SL    : TStringList;
  Seen  : TStringList;
  Ln    : string     ;
begin
  AError:= '';
  SetLength(ANames, 0);
  // `query descendants --of <A>` -> one bare class name per line (plus a possible
  // "(loaded defaults ...)" / "(none)" trailer we skip). Passing several --db
  // unions the results; we dedupe so a class in more than one DB appears once.
  Code:= RunCapture(Format('query descendants --of "%s"%s', [AAncestor, DbArgsFor(ADbs)]), Output);
  if Code = 2 then
  begin
    AError:= Format('query descendants failed (exit %d)', [Code]);
    Exit(False);
  end;
  SL  := TStringList.Create;
  Seen:= TStringList.Create;
  try
    Seen.Sorted:= True; Seen.Duplicates:= dupIgnore; Seen.CaseSensitive:= False;
    SL.Text:= Output;
    for Ln in SL do
    begin
      var T: string:= Trim(Ln);
      if T = '' then
        Continue;
      if T = '(none)' then
        Continue;
      if Pos('loaded defaults', T) > 0 then
        Continue;
      // a class name is a single identifier token (no spaces, no ':')
      if (Pos(' ', T) > 0) or (Pos(':', T) > 0) then
        Continue;
      Seen.Add(T);
    end; // for
    ANames:= Seen.ToStringArray;
    Result:= True;
  finally
    Seen.Free;
    SL.Free;
  end; // try
end; // function

function TEngineAdapter.ListProjectUnits(out ANames: TArray<string>; out AError: string): Boolean;
begin
  Result:= ListUnits(FDbList, ANames, AError);
end;

{ Every unit name in ONE index, added to ASeen. `sql` is used because no listing
  verb answers this: `query find` demands a doc clause, and the `--no-docs` one
  this used to pass is a FILTER -- it returned only the UNDOCUMENTED units
  (measured 2026-09-24: 2,103 of library-Win64's 5,646; System.SysUtils and all
  but 3 of 395 cx* units missing). The row cap defaults to 200, hence --limit. }
function TEngineAdapter.AddUnitsOfDb(const ADb: string; ASeen: TStringList; out AError: string): Boolean;
const
  UNIT_SQL = 'SELECT DISTINCT name FROM symbols WHERE kind=''unit''';
begin
  Result:= AddSqlColumnOfDb(ADb, UNIT_SQL, 'unit listing', ASeen, AError);
end; // function

const
  // Row cap of every `sql` read (the verb's default is 200).
  SQL_ROW_CAP = 1000000;
  // The engine-side query timeout of every `sql` read, in milliseconds.
  SQL_TIMEOUT_MS = 120000;
  // How much of a failed call's output an error text quotes.
  SQL_ERROR_HEAD_CHARS = 400;
  // The failure text of a read that needs a fresh index and got a stale one.
  SQL_STALE_TEXT = '%s failed for %s: ' + INDEX_STALE_MARKER + ' (%d file(s) changed since it was indexed) -- reindex the project first';

type
  { One `sql --json` answer: its POSITIONAL rows as strings, and the engine's own
    freshness verdict ("stale": a file changed on disk since it was indexed). }
  TSqlAnswer = record
    Rows      : TArray<TArray<string>>;
    Stale     : Boolean;
    StaleFiles: Integer;
  end;

{ `sql --json`'s rows, POSITIONAL arrays one per row ([["Ap"], ["uMain"], ...]),
  as strings; a JSON null reads as ''. False for unparseable output and for an
  answer the engine marked "truncated" (an incomplete answer is not an answer).
  "stale" is reported, not judged: the caller decides whether it may use it. }
function ParseSqlRows(const ASqlJson: string; out AAnswer: TSqlAnswer): Boolean;
var
  LRoot     : TJSONValue;
  LRows     : TJSONArray;
  LTruncated: Boolean;
  LCells    : TArray<string>;
begin
  AAnswer:= Default(TSqlAnswer);
  LRoot:= TJSONObject.ParseJSONValue(SliceJsonObject(ASqlJson));
  try
    Result:= (LRoot is TJSONObject) and TJSONObject(LRoot).TryGetValue<TJSONArray>('rows', LRows)
      and not (TJSONObject(LRoot).TryGetValue<Boolean>('truncated', LTruncated) and LTruncated);
    if not Result then
      Exit;
    if not TJSONObject(LRoot).TryGetValue<Boolean>('stale', AAnswer.Stale) then
      AAnswer.Stale:= False;
    if not TJSONObject(LRoot).TryGetValue<Integer>('stale_files', AAnswer.StaleFiles) then
      AAnswer.StaleFiles:= 0;
    for var LRow: TJSONValue in LRows do
      if LRow is TJSONArray then
      begin
        LCells:= nil;
        for var LCell: TJSONValue in TJSONArray(LRow) do
          LCells:= LCells + [if LCell is TJSONNull then '' else LCell.Value];
        AAnswer.Rows:= AAnswer.Rows + [LCells];
      end;
  finally
    LRoot.Free;
  end; // try
end;

{ The failure text of one `sql` read: what, which DB, the exit code and the head of
  the engine's output. }
function SqlFailureText(const AWhat, ADb: string; ACode: Integer; const AOutput: string): string;
begin
  Result:= Format('%s failed for %s (exit %d): %s', [AWhat, ADb, ACode, Copy(Trim(AOutput), 1, SQL_ERROR_HEAD_CHARS)]);
end;

function TEngineAdapter.SqlRowsOfDb(const ADb, ASql, AWhat: string; ARequireFresh: Boolean; out ARows: TArray<TArray<string>>; out AError: string): Boolean;
var
  LOutput: string;
  LCode  : Integer;
  LAnswer: TSqlAnswer;
begin
  ARows := nil;
  AError:= '';
  LCode:= RunCapture(Format('sql --query "%s" --db "%s" --json --limit %d --timeout-ms %d', [ASql, ADb, SQL_ROW_CAP, SQL_TIMEOUT_MS]), LOutput);
  if (LCode <> 0) or not ParseSqlRows(LOutput, LAnswer) then
  begin
    AError:= SqlFailureText(AWhat, ADb, LCode, LOutput);
    Exit(False);
  end;
  if ARequireFresh and LAnswer.Stale then
  begin
    AError:= Format(SQL_STALE_TEXT, [AWhat, ADb, LAnswer.StaleFiles]);
    Exit(False);
  end;
  ARows := LAnswer.Rows;
  Result:= True;
end;

function TEngineAdapter.AddSqlColumnOfDb(const ADb, ASql, AWhat: string; ASeen: TStringList; out AError: string): Boolean;
var
  LRows: TArray<TArray<string>>;
begin
  // A listing for a picker or a pre-flight tolerates a stale index (as before C8).
  Result:= SqlRowsOfDb(ADb, ASql, AWhat, False, LRows, AError);
  if Result then
    for var LRow: TArray<string> in LRows do
      if Length(LRow) > 0 then
        ASeen.Add(LRow[0]);
end; // function

function TEngineAdapter.ListUnits(const ADbs: TArray<string>; out ANames: TArray<string>; out AError: string): Boolean;
var
  Seen: TStringList;
  Db  : string     ;
begin
  AError:= '';
  SetLength(ANames, 0);
  Seen:= TStringList.Create;
  try
    Seen.CaseSensitive:= False;
    Seen.Sorted       := True;
    Seen.Duplicates   := dupIgnore;
    for Db in ADbs do
      if (Trim(Db) <> '') and not AddUnitsOfDb(Db, Seen, AError) then
        Exit(False);
    ANames:= Seen.ToStringArray;
    Result:= True;
  finally
    Seen.Free;
  end; // try
end; // function

function TEngineAdapter.ListIndexedFiles(const ADbs: TArray<string>; out APaths: TArray<string>; out AError: string): Boolean;
const
  FILES_SQL = 'SELECT path FROM files';
var
  Seen: TStringList;
begin
  AError:= '';
  APaths:= nil;
  Seen:= TStringList.Create;
  try
    Seen.CaseSensitive:= False;
    Seen.Sorted       := True;
    Seen.Duplicates   := dupIgnore;
    for var LDb: string in ADbs do
      if (Trim(LDb) <> '') and not AddSqlColumnOfDb(LDb, FILES_SQL, 'file listing', Seen, AError) then
        Exit(False);
    APaths:= Seen.ToStringArray;
    Result:= True;
  finally
    Seen.Free;
  end; // try
end; // function

const
  // C8 reads (measured on DMTEST 2026-10-05, see the C8 plan's "Measured index
  // shape"). Only IsPlainIdentifier names and SqlQuoted paths are spliced in.
  CLASS_LOOKUP_SQL = 'SELECT f.path, COALESCE(a.ancestor_name, '''') FROM symbols s JOIN files f ON f.id = s.file_id '
    + 'LEFT JOIN type_ancestors a ON a.symbol_id = s.id AND a.ordinal = 0 '
    + 'WHERE s.kind = ''class'' AND s.name = ''%s'' COLLATE NOCASE';
  FIELDS_SQL = 'SELECT fs.name, fs.signature FROM symbols c JOIN files f ON f.id = c.file_id JOIN symbols fs ON fs.parent_id = c.id '
    + 'WHERE f.path = %s COLLATE NOCASE AND c.kind = ''class'' AND c.name = ''%s'' COLLATE NOCASE '
    + 'AND fs.kind = ''field'' AND fs.signature COLLATE NOCASE IN (%s)';
  CODE_REFS_SQL = 'SELECT r.name_text, COALESCE(r.receiver_text, ''''), r.start_line FROM refs r JOIN files f ON f.id = r.file_id '
    + 'JOIN symbols es ON es.id = r.enclosing_symbol_id LEFT JOIN symbols rs ON rs.id = r.symbol_id '
    + 'WHERE f.path = %s COLLATE NOCASE AND es.qualified_name LIKE ''%%.%s.%%'' '
    + 'AND r.kind IN (''read'', ''write'', ''member-access'', ''call'') AND (r.symbol_id IS NULL OR rs.kind = ''field'') '
    // The index leaves SOME uses of a local unresolved (1.21.1: `Tag:= Label2` reads a
    // local Label2 with symbol_id NULL while `Label2:= 0` resolves), so a name the
    // enclosing routine declares as a local or parameter is dropped by name too.
    + 'AND NOT EXISTS (SELECT 1 FROM symbols l WHERE l.parent_id = r.enclosing_symbol_id AND l.kind IN (''local_var'', ''param'') '
    + 'AND ((COALESCE(r.receiver_text, '''') = '''' AND l.name = r.name_text COLLATE NOCASE) OR l.name = r.receiver_text COLLATE NOCASE))';
  FILE_INDEXED_SQL = 'SELECT COUNT(*) FROM files WHERE path = %s COLLATE NOCASE';
  NOT_INDEXED_TEXT = '%s failed for %s: %s is not in the index';
  // Column positions in the C8 reads' positional rows.
  COL_FIRST  = 0;
  COL_SECOND = 1;
  COL_THIRD  = 2;

function IsPlainIdentifier(const AName: string): Boolean;
begin
  Result:= (AName <> '') and CharInSet(AName[1], ['A'..'Z', 'a'..'z', '_']);
  for var I: Integer:= 2 to Length(AName) do
    if Result and not CharInSet(AName[I], ['A'..'Z', 'a'..'z', '0'..'9', '_']) then
      Result:= False;
end;

{ ParseSqlRows for a C8 read: a stale answer is no answer (DB authority). }
function ParseFreshRows(const ASqlJson: string; out ARows: TArray<TArray<string>>): Boolean;
var
  LAnswer: TSqlAnswer;
begin
  Result:= ParseSqlRows(ASqlJson, LAnswer) and not LAnswer.Stale;
  ARows := if Result then LAnswer.Rows else nil;
end;

{ LookupClass's rows [path, parent] -> outcome; never cloFailed. }
function ClassLookupOfRows(const ARows: TArray<TArray<string>>; out APasPath, AParentClass: string): TClassLookupOutcome;
begin
  APasPath    := '';
  AParentClass:= '';
  Result      := cloAbsent;
  for var LRow: TArray<string> in ARows do
  begin
    if Length(LRow) <= COL_SECOND then
      Continue;
    if Result = cloAbsent then
    begin
      APasPath:= LRow[COL_FIRST];
      Result  := cloFound;
    end
    else if not SameText(LRow[COL_FIRST], APasPath) then
    begin
      APasPath    := '';
      AParentClass:= '';
      Exit(cloAmbiguous);
    end;
    if AParentClass = '' then
      AParentClass:= LRow[COL_SECOND];
  end;
end;

{ ListClassFields' rows [name, type]. }
function FieldsOfRows(const ARows: TArray<TArray<string>>): TArray<TEngineField>;
var
  LField: TEngineField;
begin
  Result:= nil;
  for var LRow: TArray<string> in ARows do
    if Length(LRow) > COL_SECOND then
    begin
      LField.Name    := LRow[COL_FIRST];
      LField.TypeName:= LRow[COL_SECOND];
      Result         := Result + [LField];
    end;
end;

{ ListCodeRefs' rows [name, receiver, line]. }
function CodeRefsOfRows(const ARows: TArray<TArray<string>>): TArray<TEngineCodeRef>;
var
  LRef: TEngineCodeRef;
begin
  Result:= nil;
  for var LRow: TArray<string> in ARows do
    if Length(LRow) > COL_THIRD then
    begin
      LRef.Name    := LRow[COL_FIRST];
      LRef.Receiver:= LRow[COL_SECOND];
      LRef.Line    := StrToIntDef(LRow[COL_THIRD], 0);
      Result       := Result + [LRef];
    end;
end;

function ParseClassLookupRows(const ASqlJson: string; out APasPath, AParentClass: string): TClassLookupOutcome;
var
  LRows: TArray<TArray<string>>;
begin
  APasPath    := '';
  AParentClass:= '';
  Result:= if ParseFreshRows(ASqlJson, LRows) then ClassLookupOfRows(LRows, APasPath, AParentClass) else cloFailed;
end;

function SqlQuoted(const AText: string): string;
begin
  Result:= '''' + StringReplace(AText, '''', '''''', [rfReplaceAll]) + '''';
end;

function ParseFieldRows(const ASqlJson: string; out AFields: TArray<TEngineField>): Boolean;
var
  LRows: TArray<TArray<string>>;
begin
  Result := ParseFreshRows(ASqlJson, LRows);
  AFields:= FieldsOfRows(LRows);
end;

function ParseCodeRefRows(const ASqlJson: string; out ARefs: TArray<TEngineCodeRef>): Boolean;
var
  LRows: TArray<TArray<string>>;
begin
  Result:= ParseFreshRows(ASqlJson, LRows);
  ARefs := CodeRefsOfRows(LRows);
end;

function TEngineAdapter.LookupClass(const ADb, AClassName: string; out APasPath, AParentClass, AError: string): TClassLookupOutcome;
var
  LRows: TArray<TArray<string>>;
begin
  APasPath    := '';
  AParentClass:= '';
  AError      := '';
  if not IsPlainIdentifier(AClassName) then
    Exit(cloAbsent);
  if not SqlRowsOfDb(ADb, Format(CLASS_LOOKUP_SQL, [AClassName]), 'class lookup of ' + AClassName, True, LRows, AError) then
    Exit(cloFailed);
  Result:= ClassLookupOfRows(LRows, APasPath, AParentClass);
end;

function TEngineAdapter.ListClassFields(const ADb, AClassName, APasPath: string; const AFromTypes: TArray<string>; out AFields: TArray<TEngineField>; out AError: string): Boolean;
var
  LTypes: TArray<string>;
  LRows : TArray<TArray<string>>;
begin
  AFields:= nil;
  AError := '';
  LTypes := nil;
  for var LType: string in AFromTypes do
    if IsPlainIdentifier(LType) then
      LTypes:= LTypes + [SqlQuoted(LType)];
  if not IsPlainIdentifier(AClassName) or (Length(LTypes) = 0) then
    Exit(True);
  Result:= SqlRowsOfDb(ADb, Format(FIELDS_SQL, [SqlQuoted(APasPath), AClassName, string.Join(', ', LTypes)]), 'field listing of ' + AClassName, True, LRows, AError);
  AFields:= FieldsOfRows(LRows);
end;

function TEngineAdapter.ListCodeRefs(const ADb, AUnitPas, AClassName: string; out ARefs: TArray<TEngineCodeRef>; out AError: string): Boolean;
var
  LWhat : string;
  LRows : TArray<TArray<string>>;
  LCount: TArray<TArray<string>>;
begin
  ARefs := nil;
  AError:= '';
  if not IsPlainIdentifier(AClassName) then
    Exit(True);
  LWhat:= 'code-ref listing of ' + AClassName;
  if not SqlRowsOfDb(ADb, Format(CODE_REFS_SQL, [SqlQuoted(AUnitPas), AClassName]), LWhat, True, LRows, AError) then
    Exit(False);
  ARefs:= CodeRefsOfRows(LRows);
  if Length(ARefs) > 0 then
    Exit(True);
  // No rows: "no uses" only when the unit IS indexed; otherwise the index cannot say.
  if not SqlRowsOfDb(ADb, Format(FILE_INDEXED_SQL, [SqlQuoted(AUnitPas)]), LWhat, True, LCount, AError) then
    Exit(False);
  Result:= (Length(LCount) > 0) and (Length(LCount[0]) > 0) and (StrToIntDef(LCount[0][COL_FIRST], 0) > 0);
  if not Result then
    AError:= Format(NOT_INDEXED_TEXT, [LWhat, ADb, AUnitPas]);
end;

function TEngineAdapter.ResolveUnitFile(const AUnit: string): string;
var
  Output: string     ;
  Code  : Integer    ;
  Root  : TJSONValue ;
  Arr   : TJSONArray ;
  V     : TJSONValue ;
  Obj   : TJSONObject;
  Kind  : string     ;
  FileP : string     ;
begin
  Result:= '';
  // A BROWSED unit is not in any index, and never will be. The From Unit box
  // accepts an absolute path to a .pas/.dfm outside the project, and
  // `query --name` cannot resolve one: a project DB holds only that project's
  // members. The lookup would return nothing, the caller would read that as
  // "this form has no components", and the fault would present as a property of
  // the FORM instead of of the lookup.
  //
  // An existing FILE is its own answer, so short-circuit before the engine call.
  // Returning AUnit unchanged is correct for either half of the pair: the caller
  // derives the .dfm with ChangeFileExt, which is a no-op when the user picked
  // the .dfm and the sibling lookup when they picked the .pas.
  if TFile.Exists(AUnit) then
    Exit(AUnit);
  Code:= RunCapture(Format('query --name "%s" --json%s', [AUnit, DbArgs]), Output);
  if Code = 2 then
    Exit;
  // `query --json` prints a JSON array; it may be followed by a "(loaded
  // defaults ...)" trailer, so slice from the first '[' to its matching ']'.
  var lb: Integer:= Pos('[', Output);
  var rb: Integer:= 0               ;
  for var i:= Length(Output) downto 1 do
    if Output[i] = ']' then begin rb:= i; Break; end;
  if (lb <= 0) or (rb <= lb) then
    Exit;
  Root:= TJSONObject.ParseJSONValue(Copy(Output, lb, rb - lb + 1));
  if not (Root is TJSONArray) then begin Root.Free; Exit; end;
  try
    Arr:= Root as TJSONArray;
    // Prefer the kind=unit row; fall back to the first row that has a file.
    for V in Arr do
      if V is TJSONObject then
      begin
        Obj:= V as TJSONObject;
        Obj.TryGetValue<string>('kind', Kind);
        if SameText(Kind, 'unit') and Obj.TryGetValue<string>('file', FileP) then
          Exit(FileP);
      end;
    for V in Arr do
      if (V is TJSONObject) and (V as TJSONObject).TryGetValue<string>('file', FileP) then
        Exit(FileP);
  finally
    Root.Free;
  end; // try
end; // function

function TEngineAdapter.ResolveClassQName(const AName: string): string;
var
  Ambiguity: Integer;
begin
  Result:= ResolveClassQName(AName, Ambiguity);
end;

function TEngineAdapter.ResolveClassQName(const AName: string; out AAmbiguity: Integer): string;
var
  Ignored: string;
begin
  Result:= ResolveClassQName(AName, AAmbiguity, Ignored);
end;

function TEngineAdapter.ResolveClassQName(const AName: string; out AAmbiguity: Integer; out AError: string): string;
var
  JSON   : string              ;
  Err    : string              ;
  Syms   : TArray<TQuerySymbol>;
  Code   : Integer             ;
  Classes: TArray<TQuerySymbol>;
  S      : TQuerySymbol        ;
  Sym    : TQuerySymbol        ;
  n      : Integer             ;
begin
  Result    := AName;
  AAmbiguity:= 0;
  AError    := '';
  // Already qualified (has a '.') or empty -> nothing to do.
  if (AName = '') or (Pos('.', AName) > 0) then
    Exit;
  var LKey: string:= UpperCase(AName) + #0 + DbArgs;
  var LHit: TResolvedClass;
  TMonitor.Enter(FResolveCache);
  try
    if FResolveCache.TryGetValue(LKey, LHit) then
    begin
      AAmbiguity:= LHit.Ambiguity;
      Exit(LHit.QName);
    end;
  finally
    TMonitor.Exit(FResolveCache);
  end;
  if not QueryJsonFor(AName, JSON, Err, Code) then
  begin
    // Exit 1 is "no such class" -- an ordinary answer, so leave AError empty and
    // hand back the bare name as before (and cache it: it IS the answer). Any
    // OTHER code means the query did not run; that must not masquerade as a miss,
    // and it is not cached, so the next call asks again.
    if Code <> 1 then
      AError:= Err
    else
      CacheResolved(LKey, AName, 0);
    Exit;
  end;
  Syms:= ParseQuerySymbols(JSON);
  // Keep only class rows, then let the SHARED selector do the exact-name match and
  // the tie count. Taking "the first kind=class row" without comparing the name is
  // what this replaces: `--name` is a substring match, so that row is regularly a
  // different class whose name merely contains the request.
  SetLength(Classes, Length(Syms));
  n:= 0;
  for S in Syms do
    if SameText(S.Kind, 'class') then
    begin
      Classes[n]:= S;
      Inc(n);
    end;
  SetLength(Classes, n);
  if not SelectQuerySymbol(Classes, AName, Sym, AAmbiguity) then
  begin
    AAmbiguity:= 0;
    CacheResolved(LKey, AName, 0); // rows, but no class of that exact name: an answer
    Exit;
  end;
  if Sym.QualifiedName <> '' then
    Result:= Sym.QualifiedName
  else AAmbiguity:= 0; // a row with no qualified_name qualifies nothing
  CacheResolved(LKey, Result, AAmbiguity);
end; // function

procedure TEngineAdapter.CacheResolved(const AKey, AQName: string; AAmbiguity: Integer);
var
  E: TResolvedClass;
begin
  E.QName    := AQName;
  E.Ambiguity:= AAmbiguity;
  TMonitor.Enter(FResolveCache);
  try
    FResolveCache.AddOrSetValue(AKey, E);
  finally
    TMonitor.Exit(FResolveCache);
  end;
end;

function TEngineAdapter.DeclaringUnitOf(const ATypeName: string): string;
var
  QN    : string ;
  DotPos: Integer;
begin
  QN:= ResolveClassQName(ATypeName);
  DotPos:= QN.LastIndexOf('.');
  if DotPos > 0 then
    Result:= QN.Substring(0, DotPos)
  else
    Result:= '';
end;

function TEngineAdapter.ListControlTypesInUnit(const AUnit: string; const AControlSet: TArray<string>; out ATypes: TArray<string>; out AError: string): Boolean;
var
  PasFile : string     ;
  DfmFile : string     ;
  SL      : TStringList;
  Seen    : TStringList;
  Ln      : string     ;
  T       : string     ;
  TypeName: string     ;
  p       : Integer    ;
  q       : Integer    ;
begin
  // The components on a form are exactly the top-level + nested DFM objects, each
  // declared `object <Name>: <TType>` (or `inline <Name>: <TType>`). Read the
  // unit's companion .dfm and collect the distinct <TType> tokens. This is the
  // authoritative source -- it does not depend on class-ancestry resolution in
  // the library index, so legacy components (Orpheus/Raize/DevExpress) whose
  // ancestry is unresolved are still listed. Best-effort: [] when there is no dfm.
  AError:= '';
  SetLength(ATypes, 0);

  PasFile:= ResolveUnitFile(AUnit);
  if PasFile = '' then Exit(True); // unit not indexed -> nothing to fill
  DfmFile:= ChangeFileExt(PasFile, '.dfm');
  if not TFile.Exists(DfmFile) then
    DfmFile:= ChangeFileExt(PasFile, '.DFM'); // some trees store upper-case ext
  if not TFile.Exists(DfmFile) then Exit(True); // non-form unit -> [] (best-effort)

  SL  := TStringList.Create;
  Seen:= TStringList.Create;
  try
    Seen.Sorted:= True; Seen.Duplicates:= dupIgnore; Seen.CaseSensitive:= False;
    try
      SL.LoadFromFile(DfmFile);
    except
      on E: Exception do
      begin
        AError:= 'could not read ' + DfmFile + ': ' + E.Message;
        Exit(False);
      end;
    end;
    for Ln in SL do
    begin
      T:= TrimLeft(Ln);
      // Match a DFM object header: 'object <Name>: <TType>' or 'inline <Name>: <TType>'.
      if T.StartsWith('object ', True) then
        p:= 8
      else if T.StartsWith('inline ', True) then
        p:= 8
      else
        Continue;
      q:= Pos(':', T);
      if q <= p then
        Continue;
      TypeName:= Trim(Copy(T, q + 1, MaxInt));
      // The type token is a bare identifier; strip any trailing '[..]' index and
      // whitespace/comment. Keep only a leading T-prefixed identifier.
      var k: Integer:= 1;
      while (k <= Length(TypeName)) and (CharInSet(TypeName[k], ['A'..'Z','a'..'z','0'..'9','_'])) do
        Inc(k);
      TypeName:= Copy(TypeName, 1, k - 1);
      if (TypeName <> '') and CharInSet(TypeName[1], ['T','t']) then
        Seen.Add(TypeName);
    end; // for
    ATypes:= Seen.ToStringArray;
    Result:= True;
  finally
    SL.Free;
    Seen.Free;
  end; // try
end; // function

// Slice the first balanced bracket-ARRAY out of AText. The sibling of
// SliceJsonObject above, for the verbs that print a bare top-level array
// (`query --json`) rather than an object. Same string-literal-aware scan, so a
// '[' inside a JSON string value cannot open a phantom array, and the same
// reason for existing: RunCapture merges the child's stderr into stdout and the
// exe writes "(loaded defaults from ...)" to stderr on every call.
function SliceJsonArray(const AText: string): string;
var
  i       : Integer;
  depth   : Integer;
  startIdx: Integer;
  inStr   : Boolean;
  esc     : Boolean;
begin
  Result:= '';
  startIdx:= 0; depth:= 0; inStr:= False; esc:= False;
  for i:= 1 to Length(AText) do
  begin
    if inStr then
    begin
      if esc then
        esc:= False
      else if AText[i] = '\' then
        esc:= True
      else if AText[i] = '"' then
        inStr:= False;
      Continue;
    end;
    case AText[i] of
      '"': inStr:= True;
      '[':
      begin
        if depth = 0 then
          startIdx:= i;
        Inc(depth);
      end;
      ']':
        // depth > 0 guard: a stray ']' in the preamble must not be read as a close.
        if depth > 0 then
        begin
          Dec(depth);
          if depth = 0 then
            Exit(Copy(AText, startIdx, i - startIdx + 1));
        end;
    end; // case
  end; // for
end; // function

function ParseQuerySymbols(const AJson: string): TArray<TQuerySymbol>;
var
  Sliced: string             ;
  Root  : TJSONValue         ;
  V     : TJSONValue         ;
  Obj   : TJSONObject        ;
  List  : TList<TQuerySymbol>;
  Sym   : TQuerySymbol       ;
  n     : Integer            ;
begin
  Result:= nil;
  Sliced:= SliceJsonArray(AJson);
  if Sliced = '' then Exit; // no array in the text -> no rows
  try
    Root:= TJSONObject.ParseJSONValue(Sliced);
  except
    Root:= nil; // malformed -> [] , never an exception
  end;
  if not (Root is TJSONArray) then
  begin
    Root.Free; // nil-safe
    Exit;
  end;
  List:= TList<TQuerySymbol>.Create;
  try
    for V in (Root as TJSONArray) do
      if V is TJSONObject then
      begin
        Obj:= V as TJSONObject;
        Sym:= Default(TQuerySymbol);
        Obj.TryGetValue<string>('kind'          , Sym.Kind         );
        Obj.TryGetValue<string>('name'          , Sym.Name         );
        Obj.TryGetValue<string>('qualified_name', Sym.QualifiedName);
        Obj.TryGetValue<string>('file'          , Sym.FilePath     );
        // "start_line" / "end_line" -- there is no "line" field.
        if Obj.TryGetValue<Integer>('start_line', n) then
          Sym.StartLine:= n;
        if Obj.TryGetValue<Integer>('end_line', n) then
          Sym.EndLine:= n;
        List.Add(Sym);
      end; // if
    Result:= List.ToArray;
  finally
    List.Free;
    Root.Free;
  end; // try
end; // function

// How good an answer a row's kind is to "go to the definition of this TYPE".
// Lower is better.
//   0  a CONCRETE declaration -- the thing itself.
//   1  kind='type', which covers an ALIAS ('Vcl.Graphics.TFontPitch =
//      System.UITypes.TFontPitch') as well as sets and subranges. A real
//      declaration outranks an alias to it: it is what the user wanted to read,
//      and it is the only one EnumMembersOf can read members out of. Both rows
//      genuinely occur for the same name -- TFontPitch and TFontQuality each
//      have an enum in System.UITypes and an alias in Vcl.Graphics -- and the
//      engine's row order between them is not contractual, so ranking rather
//      than order has to decide.
//   2  anything else (property/field/param/local_var). A symbol that merely
//      shares the name is a poor answer, but still better than none.
function TypeKindTier(const AKind: string): Integer;
begin
  if SameText(AKind, 'class') or SameText(AKind, 'record')
     or SameText(AKind, 'interface') or SameText(AKind, 'enum') then Exit(0);
  if SameText(AKind, 'type') then
    Exit(1);
  Result:= 2;
end;

// ---------------------------------------------------------------------------
// The VCL-PREFERRED TIE-BREAK. Kind tiering settles concrete-vs-alias and
// nothing else, so a bare `TEdit` still reached two tier-0 class rows and took
// whichever the engine listed first -- FMX.Edit.TEdit. This is a VCL tool: an
// FMX property tree for a VCL form is a wrong answer, not a taste. Measured
// against C:\Projects\.drag-lint\library-Win64.sqlite on 2026-08-02, 298 names
// resolved FireMonkey-first, TEdit / TButton / TLabel / TForm / TPanel / TMemo /
// TComboBox among them.
//
// Which library a row's declaration comes from. Lower is better.
//   0  System.* -- the RTL. Measured: in ALL 35 names where a System.* and a
//      Vcl.* declaration tie at one kind tier, the System row is the real
//      declaration and the Vcl row a re-export or a unit-local copy
//      (Vcl.OleAuto.EOleError of System.Win.ComObj.EOleError,
//      Vcl.Graphics.PColor of System.UITypes.PColor, Vcl.Imaging.jpeg.INT32 of
//      System.Int32). Ranking the RTL first therefore never fights the
//      "a real declaration outranks an alias to it" rule TypeKindTier encodes.
//   1  Vcl.*    -- this tool's target framework.
//   2  anything else -- third-party, Winapi.*, Spring.*, dx*, cx*.
//   3  FMX.*    -- the FireMonkey twin of a VCL control. Never the answer here.
const
  FAM_SYSTEM = 0;
  FAM_VCL    = 1;
  FAM_OTHER  = 2;
  FAM_FMX    = 3;

function UnitFamilyRank(const AQualifiedName: string): Integer;
begin
  if SameText(Copy(AQualifiedName, 1, 4), 'FMX.') then
    Exit(FAM_FMX);
  if SameText(Copy(AQualifiedName, 1, 4), 'Vcl.') then
    Exit(FAM_VCL);
  if SameText(Copy(AQualifiedName, 1, 7), 'System.') then
    Exit(FAM_SYSTEM);
  Result:= FAM_OTHER;
end;

// True when the row's type is declared INSIDE another type -- the
// dxSplashForms.TdxSplashFormBase.TAlignment shape. The unit name is the
// declaring file's base name, so whatever the qualified name carries BETWEEN
// the unit and the symbol is an owning class or record. A nested type is rarely
// what a bare name means: another unit cannot even refer to it by the bare name.
// With no file we cannot tell, and answer False -- a missing field must not
// demote a row.
function IsNestedDecl(const ASym: TQuerySymbol): Boolean;
var
  DotPos: Integer;
begin
  Result:= False;
  if (ASym.FilePath = '') or (ASym.QualifiedName = '') then
    Exit;
  DotPos:= LastDelimiter('.', ASym.QualifiedName);
  if DotPos <= 1 then Exit; // no owner segment at all
  Result:= not SameText(Copy(ASym.QualifiedName, 1, DotPos - 1), ChangeFileExt(ExtractFileName(ASym.FilePath), ''));
end;

// The whole tie-break as ONE sort key, lower is better, so the caller keeps a
// single strictly-less comparison and stays STABLE: equal keys leave the earlier
// row in place, which is both today's behaviour and the documented fallback.
//   1. not FireMonkey, before FMX.*        (weight 8)
//   2. top-level, before nested-in-a-type  (weight 4)
//   3. System.* then Vcl.* then the rest   (weight 1, values 0..2)
// The family only reaches 3 for an FMX row, which already carries the 8, so the
// three levels cannot bleed into one another.
function TieBreakRank(const ASym: TQuerySymbol): Integer;
var
  Fam: Integer;
begin
  Fam:= UnitFamilyRank(ASym.QualifiedName);
  Result:= Fam;
  if IsNestedDecl(ASym) then
    Inc(Result, 4);
  if Fam = FAM_FMX then
    Inc(Result, 8);
end;

function SelectQuerySymbol(const ASyms: TArray<TQuerySymbol>; const AWantedName: string; out ASym: TQuerySymbol; out AAmbiguity: Integer): Boolean;
var
  Bare     : string      ;
  Qualified: Boolean     ;
  S        : TQuerySymbol;
  Best     : Integer     ;
  BestRank : Integer     ;
  Tier     : Integer     ;
  Rank     : Integer     ;
  DotPos   : Integer     ;
begin
  ASym:= Default(TQuerySymbol);
  AAmbiguity:= 0;
  Result    := False;
  if AWantedName = '' then
    Exit;

  Bare:= AWantedName;
  DotPos:= LastDelimiter('.', Bare);
  Qualified:= DotPos > 0;
  if Qualified then
    Bare:= Copy(Bare, DotPos + 1, MaxInt);

  // Two passes over the same filter. The first finds the best tier present and the
  // best-ranked row in it; the second counts how many rows tied at that TIER.
  // Counting cannot be folded into the first pass without knowing the winning tier up
  // front -- and the count is the whole point: it is what stops a tie being reported
  // as a certainty. It deliberately ignores the tie-break: picking a side does not
  // make the ambiguity go away, and the caller still has to say N.
  Best    := MaxInt;
  BestRank:= MaxInt;
  for S in ASyms do
  begin
    // Exact name only: `--name` matched a SUBSTRING, so most rows are other symbols.
    if not SameText(S.Name, Bare) then
      Continue;
    // A qualified request additionally pins the unit/owner, so 'Abcbtn.TabcButtonStyle'
    // cannot be answered by a same-named type from some other unit.
    if Qualified and not SameText(S.QualifiedName, AWantedName) then
      Continue;
    Tier:= TypeKindTier(S.Kind);
    if Tier > Best then Continue; // the tie-break never crosses a tier
    Rank:= TieBreakRank(S);
    // A better tier always wins; within one tier the tie-break decides, and a row
    // that only EQUALS the incumbent's rank loses -- so the first row still wins an
    // exhausted order, exactly as before.
    if (Tier < Best) or (Rank < BestRank) then
    begin
      Best    := Tier;
      BestRank:= Rank;
      ASym    := S;
      Result  := True;
    end;
  end; // for
  if not Result then
    Exit;

  for S in ASyms do
  begin
    if not SameText(S.Name, Bare) then
      Continue;
    if Qualified and not SameText(S.QualifiedName, AWantedName) then
      Continue;
    if TypeKindTier(S.Kind) = Best then
      Inc(AAmbiguity);
  end;
end; // function

function ParseQueryLocation(const AJson, AWantedName: string; out AFile: string; out ALine: Integer; out AAmbiguity: Integer): Boolean;
var
  Sym: TQuerySymbol;
begin
  AFile:= ''; ALine:= 0;
  if not SelectQuerySymbol(ParseQuerySymbols(AJson), AWantedName, Sym, AAmbiguity) then
    Exit(False);
  if Sym.FilePath = '' then
  begin
    AAmbiguity:= 0;
    Exit(False); // a row with no file is not a location
  end;
  AFile:= Sym.FilePath;
  // The wire contract says a missing/garbled line is 1, so never emit 0: the file is
  // still the right answer and opening it at the top beats reporting nothing.
  if Sym.StartLine >= 1 then
    ALine:= Sym.StartLine
  else
    ALine:= 1;
  Result := True;
end; // function

// Replaces every brace comment / compiler directive, (* *) comment and // line
// comment with a COMMA -- not a space. A comma, because in an enum body the
// removed span is frequently an $IFDEF/$ELSE arm boundary sitting between two
// members that have no comma of their own:
//   RIO_IOCP_COMPLETION = 2 {$ELSE} rnctUnused,
// Blanking that to a space would fuse the two into one element and silently drop
// rnctUnused; a comma separates them, and empty elements are skipped anyway.
function StripEnumNoise(const AText: string): string;
var
  SB: TStringBuilder;
  i : Integer       ;
  n : Integer       ;
begin
  SB:= TStringBuilder.Create;
  try
    i:= 1; n:= Length(AText);
    while i <= n do
    begin
      if AText[i] = '{' then
      begin
        while (i <= n) and (AText[i] <> '}') do
          Inc(i);
        Inc  (i); // past the '}' (or past the end)
        SB.Append(',');
      end
      else if (i < n) and (AText[i] = '(') and (AText[i + 1] = '*') then
      begin
        Inc(i, 2);
        while (i < n) and not ((AText[i] = '*') and (AText[i + 1] = ')')) do
          Inc(i);
        Inc(i, 2);
        SB.Append(',');
      end
      else if (i < n) and (AText[i] = '/') and (AText[i + 1] = '/') then
      begin
        while (i <= n) and not CharInSet(AText[i], [#13, #10]) do
          Inc(i);
        SB.Append(',');
      end
      else
      begin
        SB.Append(AText[i]);
        Inc(i);
      end;
    end; // while
    Result:= SB.ToString;
  finally
    SB.Free;
  end; // try
end; // function

// The identifier an enum element starts with: 'RIO_EVENT_COMPLETION = 1' ->
// 'RIO_EVENT_COMPLETION'. '' when the element does not start with one (a bare
// ordinal, or an element left empty by StripEnumNoise).
function LeadingIdentifier(const AText: string): string;
var
  i: Integer;
  n: Integer;
  S: Integer;
begin
  Result:= '';
  n:= Length(AText);
  i:= 1;
  while (i <= n) and CharInSet(AText[i], [#9, #10, #13, ' ']) do
    Inc(i);
  if (i > n) or not CharInSet(AText[i], ['A'..'Z', 'a'..'z', '_']) then
    Exit;
  S:= i;
  while (i <= n) and CharInSet(AText[i], ['A'..'Z', 'a'..'z', '0'..'9', '_']) do
    Inc(i);
  Result:= Copy(AText, S, i - S);
end; // function

function ParseEnumMembers(const ADeclText: string; out AMembers: TArray<string>): Boolean;
var
  T    : string     ;
  i    : Integer    ;
  n    : Integer    ;
  eq   : Integer    ;
  depth: Integer    ;
  Inner: string     ;
  Elem : string     ;
  Ident: string     ;
  List : TStringList;
  Seen : TStringList;
  Start: Integer    ;
begin
  AMembers:= nil;
  Result:= False;
  T:= StripEnumNoise(ADeclText);

  // An enum body is the '(' that follows the '=' with only whitespace between the
  // two. That single rule is what rejects 'TabcPicBtn = class(TButton)' (the word
  // 'class' sits in between) without needing to know every other type form.
  eq:= Pos('=', T);
  if eq <= 0 then
    Exit;
  n:= Length(T);
  i:= eq + 1;
  while (i <= n) and CharInSet(T[i], [#9, #10, #13, ' ']) do
    Inc(i);
  if (i > n) or (T[i] <> '(') then
    Exit;

  Inc(i); // past the '('
  Start:= i;
  depth:= 1;
  while i <= n do
  begin
    if T[i] = '(' then
      Inc(depth)
    else if T[i] = ')' then
    begin
      Dec(depth);
      if depth = 0 then
        Break;
    end;
    Inc(i);
  end; // while
  if depth <> 0 then Exit; // unbalanced -> not a declaration we understand
  Inner:= Copy(T, Start, i - Start);

  List:= TStringList.Create;
  Seen:= TStringList.Create;
  try
    Seen.Sorted:= True; Seen.Duplicates:= dupIgnore; Seen.CaseSensitive:= False;
    // Split on TOP-LEVEL commas; a nested '(...)' (an ordinal expression) is opaque.
    Elem := '';
    depth:= 0;
    for i:= 1 to Length(Inner) do
    begin
      if (Inner[i] = ',') and (depth = 0) then
      begin
        Ident:= LeadingIdentifier(Elem);
        if (Ident <> '') and (Seen.IndexOf(Ident) < 0) then
        begin
          Seen.Add(Ident);
          List.Add(Ident);
        end;
        Elem:= '';
        Continue;
      end;
      if Inner[i] = '(' then
        Inc(depth)
      else if (Inner[i] = ')') and (depth > 0) then
        Dec(depth);
      Elem:= Elem + Inner[i];
    end; // for
    Ident:= LeadingIdentifier(Elem); // the last element has no trailing comma
    if (Ident <> '') and (Seen.IndexOf(Ident) < 0) then
    begin
      Seen.Add(Ident);
      List.Add(Ident);
    end;

    AMembers:= List.ToStringArray;
    Result:= List.Count > 0;
  finally
    Seen.Free;
    List.Free;
  end; // try
end; // function

{ Shared front half of ResolveTypeLocation / EnumMembersOf: run `query --name`
  and turn the engine's exit code into either usable JSON or a sentence the
  status bar can show. ANAME must be BARE -- `--name Abcbtn.TabcButtonStyle`
  matches nothing (measured), so the dotted form is stripped by the callers. }
function TEngineAdapter.QueryJsonFor(const AName: string; out AJson, AError: string): Boolean;
var
  Ignored: Integer;
begin
  Result:= QueryJsonFor(AName, AJson, AError, Ignored);
end;

function TEngineAdapter.QueryJsonFor(const AName: string; out AJson, AError: string; out ACode: Integer): Boolean;
var
  Code: Integer;
begin
  AError:= '';
  Code:= RunCapture(Format('query --name "%s" --json%s', [AName, DbArgs]), AJson);
  ACode:= Code;
  case Code of
    0: Exit(True);
    // Exit 1 is "zero hits", NOT a broken call -- say so plainly rather than
    // reporting an engine failure for a type that is simply not indexed.
    1: AError:= Format(
      '"%s" is not in the current index set. Method-pointer types '
        + '(TNotifyEvent and friends) are among the declarations the index does not '
        + 'carry, and a type from an unindexed library will not be here either.',
      [AName]);
    3: AError:= Format('query for "%s" timed out after %d s -- the index may be ' + 'being written by another process.', [AName, ENGINE_TIMEOUT_MS div 1000]);
    else
      AError:= Format('query failed (exit %d) for "%s": %s', [Code, AName, Trim(AJson)]);
  end; // case
  AJson := '';
  Result:= False;
end; // function

{ The bare identifier of a possibly unit-qualified type name. }
function BareTypeName(const AType: string): string;
var
  DotPos: Integer;
begin
  Result:= AType;
  DotPos:= LastDelimiter('.', Result);
  if DotPos > 0 then
    Result:= Copy(Result, DotPos + 1, MaxInt);
end;

function TEngineAdapter.ResolveTypeLocation(const AType: string; out AFile: string; out ALine: Integer; out AError: string): Boolean;
var
  Ambiguity: Integer;
begin
  Result:= ResolveTypeLocation(AType, AFile, ALine, AError, Ambiguity);
end;

function TEngineAdapter.ResolveTypeLocation(const AType: string; out AFile: string; out ALine: Integer; out AError: string; out AAmbiguity: Integer): Boolean;
var
  JSON: string;
begin
  AFile:= ''; ALine:= 0; AAmbiguity:= 0;
  if Trim(AType) = '' then
  begin
    AError:= 'No type to resolve.';
    Exit(False);
  end;
  if not QueryJsonFor(BareTypeName(AType), JSON, AError) then
    Exit(False);
  Result:= ParseQueryLocation(JSON, AType, AFile, ALine, AAmbiguity);
  if not Result then
    AError:= Format(
      'No declaration named "%s" came back. `query --name` matches a ' + 'SUBSTRING, so the index answered with other symbols whose names merely ' + 'contain it.', [AType]);
end; // function

function TEngineAdapter.EnumMembersOf(const AType: string; out AMembers: TArray<string>; out AError: string): Boolean;
var
  Ambiguity: Integer;
begin
  Result:= EnumMembersOf(AType, AMembers, AError, Ambiguity);
end;

function TEngineAdapter.EnumMembersOf(const AType: string; out AMembers: TArray<string>; out AError: string; out AAmbiguity: Integer): Boolean;
var
  JSON : string      ;
  Sym  : TQuerySymbol;
  SL   : TStringList ;
  Decl : string      ;
  i    : Integer     ;
begin
  AMembers:= nil;
  AAmbiguity:= 0;
  if Trim(AType) = '' then
  begin
    AError:= 'No type to inspect.';
    Exit(False);
  end;
  if not QueryJsonFor(BareTypeName(AType), JSON, AError) then
    Exit(False);
  if not SelectQuerySymbol(ParseQuerySymbols(JSON), AType, Sym, AAmbiguity) then
  begin
    AError:= Format('No declaration named "%s" came back.', [AType]);
    Exit(False);
  end;
  if not SameText(Sym.Kind, 'enum') then
  begin
    AError:= Format('%s is a %s, not an enum.', [AType, Sym.Kind]);
    AAmbiguity:= 0;
    Exit(False);
  end;
  // The index holds no member list and offers no children-of query, so the members
  // have to be read from the declaration the row points at.
  if (Sym.FilePath = '') or not TFile.Exists(Sym.FilePath) then
  begin
    AError:= Format('%s is declared in %s, which is not readable from this machine.', [AType, Sym.FilePath]);
    AAmbiguity:= 0;
    Exit(False);
  end;
  SL:= TStringList.Create;
  try
    try
      SL.LoadFromFile(Sym.FilePath);
    except
      on E: Exception do
      begin
        AError:= Format('could not read %s: %s', [Sym.FilePath, E.Message]);
        AAmbiguity:= 0;
        Exit(False);
      end;
    end;
    if (Sym.StartLine < 1) or (Sym.StartLine > SL.Count) then
    begin
      AError:= Format('%s: the index points at %s line %d, which that file does not ' + 'have -- the index is stale relative to the source.', [AType, Sym.FilePath, Sym.StartLine]);
      AAmbiguity:= 0;
      Exit(False);
    end;
    Decl:= '';
    for i:= Sym.StartLine to Sym.EndLine do
    begin
      if i > SL.Count then
        Break;
      Decl:= Decl + SL[i - 1] + sLineBreak; // SL is 0-based; the index is 1-based
    end;
    Result:= ParseEnumMembers(Decl, AMembers);
    if not Result then
    begin
      AError:= Format('%s is indexed as an enum, but no members could be read from ' + '%s lines %d-%d.', [AType, Sym.FilePath, Sym.StartLine, Sym.EndLine]);
      AAmbiguity:= 0;
    end;
  finally
    SL.Free;
  end; // try
end; // function

function TEngineAdapter.Scaffold(const AFrom, ATo: string; out ARules: string; out AError: string): Boolean;
var
  Code: Integer;
begin
  AError:= '';
  Code:= RunCapture(Format('convert-scaffold --from "%s" --to "%s"%s%s', [AFrom, ATo, DepthArgs(FTreeDepth, False), DbArgs]), ARules);
  if Code <> 0 then
  begin
    AError:= Format('convert-scaffold failed (exit %d): %s', [Code, Trim(ARules)]);
    ARules:= '';
    Exit(False);
  end;
  Result:= True;
end; // function

function TEngineAdapter.ValidateText(const ARulesText, AFrom, ATo: string; const ACancel: TCancelToken): TValidateResult;
var
  Tmp   : string     ;
  Output: string     ;
  Code  : Integer    ;
  Args  : string     ;
  SL    : TStringList;
  Ln    : string     ;
begin
  Result.OK        := False;
  Result.FirstError:= '';
  Result.Output    := '';
  Tmp:= TPath.Combine(TPath.GetTempPath, 'convrules-validate-' + TPath.GetGUIDFileName + '.rules');
  try
    TFile.WriteAllText(Tmp, ARulesText, TEncoding.ASCII);
    Args:= Format('convert-validate --rules "%s"', [Tmp]);
    if (AFrom <> '') and (ATo <> '') then
      Args:= Args + Format(' --from "%s" --to "%s"', [AFrom, ATo]);
    Args:= Args + DbArgs + CastLibArgs;
    // SEPARATE pipes, not RunCapture's merged one: the diagnostics are read line by
    // line, and a merged pipe interleaves stdout and stderr by CHUNK -- a driven Save
    // showed the tail of stderr's "resolver: ..." advisory, cut off from its head,
    // parsed as an error. RunCaptureStreaming puts whole stderr lines after stdout.
    Code:= RunCaptureStreaming(Args, ENGINE_TIMEOUT_MS, nil, ACancel, Output);
    Result.Output:= Output;
    Result.OK:= Code = 0;
    if not Result.OK then
    begin
      // surface the first non-empty, non-"loaded defaults" line
      SL:= TStringList.Create;
      try
        SL.Text:= Output;
        for Ln in SL do
          if (Trim(Ln) <> '') and (Pos('loaded defaults', Ln) = 0) then
          begin
            Result.FirstError:= Trim(Ln);
            Break;
          end;
      finally
        SL.Free;
      end; // try
    end; // if
  finally
    if TFile.Exists(Tmp) then
    try TFile.Delete(Tmp); except end;
  end; // try
end; // function

function TEngineAdapter.OutlineClasses(const APasFile: string; out AClasses: TArray<string>;
  out AIndexedNow: Boolean; out AError: string): Boolean;
var
  Outp    : string ;
  Code    : Integer;
  Db      : string ;
  CanIndex: Boolean;

  function FirstLine(const AText: string): string;
  var
    p: Integer;
  begin
    Result:= Trim(AText);
    p     := Pos(#10, Result);
    if p > 0 then
      Result:= Trim(Copy(Result, 1, p - 1));
  end;

  // Runs `outline` with the given extra --db argument text; on success parses
  // AClasses (the enclosing out param) and reports True. Factored out so the
  // 3-attempt structure (configured DB / warm scratch DB / cold index) below
  // reads as single-exit control flow (if/else assigning Result) rather than
  // three copies of Exit(True) on success.
  function TryOutline(const AExtraDbArgs: string): Boolean;
  var
    O: string ;
    C: Integer;
  begin
    C     := RunCapture(Format('outline --file "%s" --format json%s', [APasFile, AExtraDbArgs]), O);
    Result:= C = 0;
    if Result then
      AClasses:= ParseOutlineClassNames(O);
  end;

begin
  AClasses   := nil;
  AIndexedNow:= False;
  AError     := '';
  Result     := False;

  if Trim(APasFile) = '' then
    AError:= 'no unit file'
  else if TryOutline(DbArgs) then
    Result:= True // 1) a configured DB already covers this unit -- never index for it
  else
  begin
    // 2) the unit's own persistent scratch DB may already exist from a prior
    // pick -- try it BEFORE indexing, or every warm call would pay the index
    // cost again (the configured DB list never gains the scratch DB itself).
    Db:= ScratchDbPath(APasFile);
    if TFile.Exists(Db) and TryOutline(Format(' --db "%s"', [Db])) then
      Result:= True // AIndexedNow stays False: warm path, no index call made
    else
    begin
      // 3) cold: build the scratch index, then outline it.
      CanIndex:= True;
      try
        ForceDirectories(ExtractFilePath(Db));
      except
        on E: Exception do
        begin
          AError  := 'could not create the scratch index folder: ' + E.Message;
          CanIndex:= False;
        end;
      end;
      if CanIndex then
      begin
        Code:= RunCapture(Format('index "%s" --db "%s"', [APasFile, Db]), Outp);
        if Code <> 0 then
          AError:= 'index failed: ' + FirstLine(Outp)
        else
        begin
          AIndexedNow:= True;
          if TryOutline(Format(' --db "%s"', [Db])) then
            Result:= True
          else
            AError:= 'outline failed after indexing';
        end; // if
      end; // if
    end; // else
  end; // else
end; // function

function ParseOutlineClassNames(const AJson: string): TArray<string>;
var
  a   : Integer      ;
  b   : Integer      ;
  Body: string       ;
  V   : TJSONValue   ;
  Arr : TJSONArray   ;
  Obj : TJSONObject  ;
  i   : Integer      ;
  Kind: string       ;
  Nm  : string       ;
  Seen: TStringList  ;
begin
  Result:= nil;
  a:= Pos('[', AJson);
  b:= LastDelimiter(']', AJson);
  if (a <= 0) or (b <= a) then
    Exit;
  Body:= Copy(AJson, a, b - a + 1);

  try
    V:= TJSONObject.ParseJSONValue(Body);
  except // dl:ok try-except-swallowed@6149 -- deliberate: malformed JSON must yield [] not raise, per this function's docstring contract and test outline.classes.garbage
    on E: Exception do
      V:= nil;
  end;
  if not (V is TJSONArray) then
  begin
    V.Free;
    Exit;
  end;

  Seen:= TStringList.Create;
  try
    Seen.Sorted:= True;
    Seen.Duplicates:= dupIgnore;
    Seen.CaseSensitive:= False;
    Arr:= TJSONArray(V);
    for i:= 0 to Arr.Count - 1 do
    begin
      if not (Arr.Items[i] is TJSONObject) then
        Continue;
      Obj := TJSONObject(Arr.Items[i]);
      Kind:= '';
      Nm  := '';
      Obj.TryGetValue<string>('kind', Kind);
      Obj.TryGetValue<string>('name', Nm  );
      if not SameText(Kind, 'class') then
        Continue;
      if Trim(Nm) = '' then
        Continue;
      if Seen.IndexOf(Nm) >= 0 then
        Continue;
      Seen.Add(Nm);
      Result:= Result + [Nm];
    end; // for
  finally
    Seen.Free;
    V.Free;
  end; // try
end; // function

function ScratchDbPath(const APasFile: string): string;
const
  FNV_OFFSET_BASIS: Cardinal = 2166136261; // FNV-1a 32-bit initial hash value
  FNV_PRIME       : Cardinal = 16777619  ; // FNV-1a 32-bit prime multiplier
var
  Key : string  ;
  Hash: Cardinal;
  i   : Integer ;
  Dir : string  ;
begin
  if Trim(APasFile) = '' then
    Exit('');
  // FNV-1a over the upper-cased path: short, stable across runs, and it does not
  // drag in a hashing unit for eight hex digits.
  Key := UpperCase(APasFile);
  Hash:= FNV_OFFSET_BASIS;
  for i:= 1 to Length(Key) do
  begin
    Hash:= Hash xor Cardinal(Ord(Key[i]));
    // The FNV-1a multiply relies on Cardinal wrap-around, which is the whole
    // algorithm -- under {$Q+} it raises EIntOverflow instead (A7, 2026-09-20
    // whole-branch review, Minor 11). Works today only because the local build
    // scripts leave overflow checking off; guarded locally so a {$Q+} build
    // elsewhere cannot break the one caller (HarvestUnitClasses) that reaches it.
    {$IFOPT Q+}{$Q-}{$DEFINE QWASON}{$ENDIF}
    Hash:= Hash * FNV_PRIME;
    {$IFDEF QWASON}{$Q+}{$UNDEF QWASON}{$ENDIF}
  end;
  Dir:= GetEnvironmentVariable('LOCALAPPDATA');
  if Trim(Dir) = '' then
    Dir:= TPath.GetHomePath; // %APPDATA% -- still per-user, still writable
  Dir:= TPath.Combine(TPath.Combine(Dir, 'DragLint'), 'ConvRulesEditor');
  Dir:= TPath.Combine(Dir, 'scratch');
  // Stem taken from the already-upper-cased Key, not the raw-case APasFile: the
  // hash was case-insensitive, and the stem must be too, or scratchdb.ci fails --
  // 'VARINSP.PAS' and 'varinsp.pas' must resolve to the byte-identical path.
  Result:= TPath.Combine(Dir, Format('%s-%.8x.sqlite', [TPath.GetFileNameWithoutExtension(Key), Hash]));
end; // function

end.
