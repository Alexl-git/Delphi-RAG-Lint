unit DRagLint.Doc.Regions;

interface

uses
  System.SysUtils, System.Classes, System.StrUtils,
  DRagLint.Core.Model, DRagLint.Doc.Facts;

const
  AUTO_BEGIN = '<!-- drag-lint:auto BEGIN -->';
  AUTO_END   = '<!-- drag-lint:auto END -->';
  /// Uniform provenance marker (v(ADP3 T1)). Emitted immediately after the
  /// OPENING tag of every &lt;summary&gt;/&lt;param&gt;/&lt;returns&gt; the engine writes, so
  /// the marker becomes the first characters of the tag's text content and
  /// survives the doc parser's round-trip (unlike the legacy trailing
  /// AUTO_PARAM, which the parser stripped). It is an HTML comment, so
  /// DocInsight tooltips do not render it. A tag WITHOUT this marker is
  /// hand-written, full stop -- there is no content-based fallback (the
  /// pre-v(ADP3) StartsText('Observed:') sniff is deleted, see MergeComment).
  /// READ PATH ONLY: MergeComment/IsManagedDesc/the doc-drift comparison need
  /// to see this marker to know what the engine owns, so it is never stripped
  /// on read. Human-facing surfaces call StripForDisplay, never this constant
  /// directly, to hide it (see that function's own comment).
  AUTO_MARK  = '<!-- drag-lint:auto -->';
  /// Legacy trailing param marker TEXT. DECLARATION-ONLY as of v(ADP3 T1): no
  /// code reads or writes this constant anymore (the engine never emits it;
  /// IsManagedText/IsManagedDesc never test for it). A pre-v(ADP3) file still
  /// self-heals, but not by recognizing this literal string -- the doc parser
  /// strips a trailing sentinel like this one (plus the /// prefix) BEFORE
  /// TParsedDoc.Params is populated, so the desc MergeComment actually sees is
  /// already EMPTY; it is IsManagedDesc's empty-desc arm that then classifies
  /// the param as managed. Retained only as a record of the legacy format.
  AUTO_PARAM = '<!-- drag-lint:auto param -->';

type
  TDocRegions = class
  private
    /// <summary>Removes any managed fenced block from S: everything from the
    /// first AUTO_BEGIN occurrence through the end of the line containing the
    /// following AUTO_END (inclusive). Prose before/after the fence is kept.
    /// Idempotent regeneration relies on this so re-runs never nest blocks.</summary>
    class function StripManagedBlock(const S: string): string;
  public
    /// <summary>Renders the fenced facts-block body lines (each prefixed
    /// APrefix), from AFacts. Sections: Called from / Calls / Used in units /
    /// Raises / Deprecated / Overrides / Overridden by / Implements / Overload
    /// k of n / abstract / virtual / Complexity / Reads/Writes fields / Owns
    /// returned / Handles / SQL tables touched / Covered by / Since / SeeAlso.
    /// Empty sections omitted; '' when there are no facts. Displayed
    /// counts below
    /// the true *Total get a ' (+N more)' suffix. Deprecated is ground-truth
    /// from the Pascal 'deprecated' directive (not the unrelated
    /// &lt;deprecated/&gt; doc-comment tag) -- emitted only when the directive
    /// was found on the declaration. The cheap fact group (v(ADP1 T3):
    /// Overrides/Overridden by/Implements/Overload/abstract/virtual) is
    /// gathered unconditionally for method-like symbols -- see TDocFacts'
    /// field comments for how each is derived and
    /// DRagLint.Doc.Facts.DetectMethodDirectives for the virtual/abstract
    /// source probe. Reads/Writes fields (v(ADP2 T4)) is ONE line, 'Reads: a,
    /// b   Writes: c' (three spaces between the two sides) -- either side is
    /// omitted when empty, and the WHOLE line is omitted when both are empty;
    /// AFacts.ReadsFields/WritesFields are already display-ready (capped,
    /// formatted) so this is a plain passthrough, like Complexity's raw
    /// values. Owns returned (v(ADP2 T8), 'Owns returned: new (caller owns)'
    /// / 'Owns returned: borrowed' / 'Owns returned: self') is ONE line,
    /// emitted only when AFacts.ReturnsOwner is non-empty -- deliberately a
    /// DISTINCT label from the Phase 1.x mined return-cases 'Returns:' line
    /// above (a different concept: who owns the returned reference, not what
    /// expression computed it) so the two can never collide. ABSENCE OVER A
    /// WRONG VERDICT is this fact's own governing principle (a wrong 'new'
    /// invites a double-free), so '' -- the line omitted -- is the routine
    /// default whenever the analysis has any doubt at all; see
    /// TDocFacts.ReturnsOwner's own field comment for the full list of
    /// absence conditions. Handles (v(ADP2 T6), 'Handles: Button1.OnClick') is ONE line,
    /// emitted only when AFacts.DfmEvent is non-empty -- the routine is a
    /// published method wired as an event handler in its own paired .dfm;
    /// AFacts.DfmEvent is already the final display string (computed at
    /// index time), so this too is a plain passthrough. SQL tables touched
    /// (v(ADP2 T7), 'SQL: reads A, B; writes C') is ONE line -- unlike
    /// Reads/Writes fields above, the two sides here are joined with
    /// '; ' (semicolon-space), not three literal spaces, matching the
    /// design spec's own rendering example -- either side omitted when
    /// empty, and the WHOLE line omitted when both are empty;
    /// AFacts.SqlReads/SqlWrites are already display-ready, so this too is a
    /// plain passthrough. Covered by (v(ADP2 T5), 'Covered by: A, B (+N more)') is the
    /// SAME kind of already-display-ready passthrough -- AFacts.CoveredBy is
    /// computed LAZILY by DRagLint.Doc.SymbolFacts.ComputeCoveredBy (a
    /// bounded reverse call-graph closure filtered to test callers), never
    /// read back from the index; omitted when empty (no detected test
    /// caller). SeeAlso emits one &lt;seealso cref&gt; line per entry; it is
    /// populated only when the facts were built with the --seealso opt-in, so
    /// by default no &lt;seealso&gt; line appears.</summary>
    /// <param name="AComplexityMin">v(ADP2 T3): the docs.complexity_min
    /// threshold (manifest-configured; default 10). 'Complexity: N
    /// (cyclomatic), M lines' is emitted ONLY when AFacts.Cyclomatic &gt;=
    /// AComplexityMin -- so a trivial routine's block stays lean. Applied HERE
    /// (at render time), not when AFacts was built, so changing
    /// docs.complexity_min takes effect on the next `document` run with NO
    /// reindex (the raw Cyclomatic/BodyLoc values are already in the index;
    /// only the display gate changes).</param>
    class function RenderFactsBlock(const AFacts: TDocFacts; const APrefix: string;
      AIncludeReturns: Boolean = False; AComplexityMin: Integer = 10): string;
    /// <summary>Formats the SIX Phase-2 index-time analysis facts (v(ADP2
    /// T3/T4/T5/T6/T7/T8)) as bare, omit-when-empty display lines, in the
    /// SAME fixed order RenderFactsBlock emits them in the managed doc
    /// block: Complexity / Reads-Writes fields / Owns returned / Handles /
    /// SQL tables touched / Covered by. Each returned line is UNPREFIXED (no
    /// '/// ', no leading indentation) -- RenderFactsBlock prepends its own
    /// APrefix per line when it calls this helper; a hover renderer appends
    /// the lines as-is. This is the v(ADP2 T9) DOC/HOVER CONSISTENCY LOCK:
    /// the ONE place either surface computes what a Phase-2 fact line says,
    /// so `document`'s managed block and `hover`'s markdown -- both built
    /// from the SAME TDocFactsBuilder.Build(AStore, ASym) result -- can
    /// never drift apart on the same symbol. Every OTHER fact
    /// RenderFactsBlock renders (Called from / Calls / Used in units /
    /// Raises / Deprecated / the ADP1 T3 cheap group / Since / SeeAlso) is
    /// Phase 1.x or opt-in doc-only content, deliberately out of scope for
    /// this helper and for hover.</summary>
    /// <param name="AComplexityMin">Same threshold/semantics as
    /// RenderFactsBlock's own AComplexityMin param (see its comment): the
    /// 'Complexity:' line is emitted only when AFacts.Cyclomatic &gt;=
    /// AComplexityMin (and Cyclomatic &gt; 0, ruling out the "never
    /// analyzed" sentinel).</param>
    /// <returns>Zero or more display lines, in Complexity / Reads-Writes /
    /// Owns returned / Handles / SQL / Covered-by order; empty when AFacts
    /// carries none of the six.</returns>
    class function FormatPhase2FactLines(const AFacts: TDocFacts; AComplexityMin: Integer = 10): TArray<string>;
    /// <summary>Produces the full merged DocInsight comment text (///-prefixed
    /// lines joined by CRLF): preserved hand-written prose + a regenerated
    /// managed facts block (fenced inside remarks) + managed param/summary/
    /// returns tags. v(ADP3 T1): every managed tag this function emits carries
    /// AUTO_MARK as the FIRST characters of its text content, immediately
    /// after the opening tag -- summary/param(s) get the bare marker; a
    /// managed/empty returns gets the marker followed by the mined 'Observed:
    /// ...' suffix, if any. Ownership is marker-keyed ONLY: a tag without
    /// AUTO_MARK is hand-written, full stop. The pre-v(ADP3)
    /// StartsText('Observed:', ...) content sniff that used to misclassify a
    /// hand-written returns starting with that word as managed is DELETED --
    /// see IsManagedDesc / TDocRegions.IsManagedText for the marker-keyed test
    /// that replaces it. Fresh comments emit marker-only managed placeholders
    /// (summary/param carry just AUTO_MARK; returns carries AUTO_MARK plus the
    /// mined 'Observed: ...' facts, if any) -- never "TODO" text, so generated
    /// docs never trip drag-lint's own TODO rule. Repair preserves Summary/
    /// Remarks prose and hand-typed param descriptions verbatim (no marker),
    /// adds/removes managed param tags, and flags hand-typed params no longer
    /// present in the signature.</summary>
    /// <param name="AComplexityMin">v(ADP2 T3): forwarded to RenderFactsBlock
    /// as-is; see its own param comment. Default 10 matches the manifest
    /// default (docs.complexity_min).</param>
    /// <param name="AExistingHasAnyTag">v(ADP3 T3 review round 2, Finding 4):
    /// True when the EXISTING doc region carries any tag at all --
    /// HasSummaryTag/HasReturnsTag/a non-empty Params array/an unmodeled tag
    /// found in the raw region -- computed by the caller (BuildForSymbol),
    /// NOT read off TParsedDoc.HasContent (which stays narrower, for its
    /// OTHER consumers -- the indexer's symbol_docs write, context
    /// bundling, TypeAt, MCP, LSP hover -- that correctly treat a blank-
    /// slot-only comment as "not documented"). Used ONLY to decide the
    /// repair-vs-fresh branch below: a comment consisting solely of a
    /// human's blank &lt;summary&gt;&lt;/summary&gt; (HasContent False, no
    /// &lt;param&gt;) must still take the REPAIR path, not insert a second,
    /// separate block below it. Default False preserves prior behavior for
    /// any caller that has no such region to report.</param>
    class function MergeComment(const AExisting: TParsedDoc;
      const ASigParams: TArray<string>; const AFacts: TDocFacts;
      AHasReturn: Boolean; const APrefix: string; AComplexityMin: Integer = 10;
      AExistingHasAnyTag: Boolean = False): string;
    /// <summary>True when S is engine-emitted (managed) tag content: its text
    /// begins with AUTO_MARK. This is the ONLY managed test as of v(ADP3 T1) --
    /// ownership is marker-keyed, never content-keyed, so a human whose prose
    /// happens to start with 'Observed:' or read 'TODO: describe.' is no longer
    /// silently adopted.</summary>
    class function IsManagedText(const S: string): Boolean;
    /// <summary>Removes a leading AUTO_MARK, if present, from S -- and, either
    /// way, also removes any leading whitespace: the TrimLeft this performs is
    /// UNCONDITIONAL, not gated on the marker being found, so S is NOT
    /// returned byte-for-byte unchanged when it carries no marker (only its
    /// leading whitespace changes). Used to recover the previously-emitted
    /// text for a drift comparison.</summary>
    class function StripMark(const S: string): string;
    /// <summary>True when S is MANAGED (auto-generated/regenerable) content,
    /// as opposed to hand-typed prose: S begins with AUTO_MARK (IsManagedText),
    /// or S is empty, or S is exactly the legacy 'TODO: describe.' sentinel.
    /// The two legacy arms exist ONLY so a file written by a pre-v(ADP3) build
    /// self-heals on its next run; new output always carries AUTO_MARK. This
    /// is the SAME three-way test MergeComment's own IncludeReturns condition
    /// uses -- exposed publicly (v(ADP3 T1) review fix) so every OTHER
    /// consumer that needs this exact test (the doc-drift ddFactsBlockStale
    /// comparison today; the Task 9 drift compare next) calls this ONE
    /// implementation instead of hand-expanding the three arms again, which is
    /// how 'TODO: describe.' ends up with two homes and drifts out of
    /// sync.</summary>
    class function IsManagedDesc(const S: string): Boolean;
    /// <summary>Strips human-invisible engine bookkeeping from S for DISPLAY
    /// ONLY: a leading AUTO_MARK (via StripMark) plus any AUTO_BEGIN/AUTO_END
    /// facts-fence marker text found anywhere in S -- the facts LINES between
    /// a fence pair are left untouched, only the two fence marker strings
    /// themselves are removed. Trims the result, so a field that was ONLY the
    /// marker (or the fence with no facts) becomes '', letting a caller's
    /// existing `if X &lt;&gt; '' then` guard keep suppressing the line exactly as
    /// it did before the marker existed. v(ADP3 T1) review fix: every surface
    /// that renders Summary/ReturnsText/a &lt;param&gt; desc/Remarks to a HUMAN
    /// (hover's CLI/LSP/JSON renderers, the context bundle, MCP's doc JSON, LSP
    /// completion/signature-help, TypeAt's plain-text render) must call THIS,
    /// and only this, to clean the text -- never open-code a second
    /// Replace('&lt;!-- drag-lint:auto --&gt;', ''). The READ path (MergeComment,
    /// IsManagedDesc, the doc-drift comparison) must NEVER call this: it needs
    /// the raw marker to know what the engine owns.</summary>
    class function StripForDisplay(const S: string): string;
  end;

implementation

/// <summary>XML-escapes S for use as ELEMENT TEXT content: ampersand, less-than
/// and greater-than become their XML entity references. The ampersand pass runs
/// first so the ampersand it introduces for a later entity is not re-escaped.</summary>
/// <remarks>Applied to EVERY mined value emitted into the managed facts block
/// (caller/callee names, unit names, raised/overridden/implemented types,
/// deprecated messages, return cases). Mined content is NOT guaranteed to be a
/// bare identifier -- a generic type, an operator method, or an arbitrary
/// deprecated message can carry angle brackets or an ampersand. Without this the
/// generated DocInsight XML is ill-formed ("Bad XML documentation comment"), and
/// a literal remarks close tag inside a fact additionally breaks the regex-based
/// re-parse (the non-greedy match stops at the injected close tag) on which the
/// idempotent strip-and-regenerate depends.</remarks>
function EscXml(const S: string): string;
begin
  Result:= StringReplace(S, '&', '&amp;', [rfReplaceAll]);
  Result:= StringReplace(Result, '<', '&lt;', [rfReplaceAll]);
  Result:= StringReplace(Result, '>', '&gt;', [rfReplaceAll]);
end;

/// <summary>XML-escapes S for use inside a double-quoted ATTRIBUTE value: as
/// EscXml, plus the double-quote character becomes its XML entity, so a mined
/// cref containing a quote (or a generic type's angle brackets) can never
/// terminate the cref attribute early.</summary>
function EscXmlAttr(const S: string): string;
begin
  Result:= StringReplace(EscXml(S), '"', '&quot;', [rfReplaceAll]);
end;

/// <summary>Builds the " Observed: a; b." suffix (XML-escaped) from mined return
/// cases, or '' when none. Used to fill a managed/empty &lt;returns&gt; tag.</summary>
function ObservedSuffix(const ACases: TArray<string>): string;
var i: Integer; Sb: TStringBuilder;
begin
  Result:= '';
  if Length(ACases) = 0 then Exit;
  Sb:= TStringBuilder.Create;
  try
    Sb.Append(' Observed: ');
    for i:= 0 to High(ACases) do
    begin
      if i > 0 then Sb.Append('; ');
      Sb.Append(EscXml(ACases[i]));
    end;
    Sb.Append('.');
    Result:= Sb.ToString;
  finally Sb.Free; end;
end;

// Module-level forwarder (v(ADP3 T1) review fix): the real implementation is
// now the public TDocRegions.IsManagedDesc, exposed so consumers OUTSIDE this
// unit (Doc.Drift's ddFactsBlockStale check today) share the exact same
// three-way test instead of hand-expanding it again. Kept as a bare function
// so every EXISTING call site inside this unit (MergeComment) needs no edit.
function IsManagedDesc(const S: string): Boolean;
begin
  Result:= TDocRegions.IsManagedDesc(S);
end;

class function TDocRegions.StripManagedBlock(const S: string): string;
var
  BeginPos: Integer;
  EndPos  : Integer;
  EolPos  : Integer;
  Head    : string ;
  Tail    : string ;
begin
  // Input is POST-PARSER: the XML doc parser has already stripped the /// prefix
  // and joined lines, so S is the bare Remarks prose (no leading ///). Find the
  // fenced block by the sentinel SUBSTRINGS. The TrimRight over '/'/space below is
  // a harmless safety net for a hypothetical raw-block caller that still carries a
  // /// prefix; it is a no-op on parser-supplied input.
  BeginPos:= Pos(AUTO_BEGIN, S);
  if BeginPos = 0 then Exit(S);
  EndPos:= PosEx(AUTO_END, S, BeginPos);
  if EndPos = 0 then
  begin
    // Malformed: BEGIN with no END. Drop from BEGIN's line start to end.
    Result:= Copy(S, 1, BeginPos - 1).TrimRight([#13, #10, ' ', '/']);
    Exit;
  end;
  // Head = text before the BEGIN. Trim trailing newline/space (the '/' in the set
  // is the safety net noted above; no /// arrives via the parser path).
  Head:= Copy(S, 1, BeginPos - 1).TrimRight([#13, #10, ' ', '/']);
  // Tail = text after the line that contains AUTO_END.
  EolPos:= EndPos + Length(AUTO_END);
  while (EolPos <= Length(S)) and (S[EolPos] <> #13) and (S[EolPos] <> #10) do
    Inc(EolPos);
  Tail:= Copy(S, EolPos, MaxInt).TrimLeft([#13, #10]);
  if (Head <> '') and (Tail <> '') then
    Result:= Head + sLineBreak + Tail
  else
    Result:= Head + Tail;
end;

class function TDocRegions.IsManagedText(const S: string): Boolean;
begin
  Result:= StartsStr(AUTO_MARK, TrimLeft(S));
end;

class function TDocRegions.StripMark(const S: string): string;
begin
  Result:= TrimLeft(S);
  if StartsStr(AUTO_MARK, Result) then
    Result:= Copy(Result, Length(AUTO_MARK) + 1, MaxInt);
end;

class function TDocRegions.IsManagedDesc(const S: string): Boolean;
begin
  Result:= IsManagedText(S) or (Trim(S) = '')
        or SameText(Trim(S), 'TODO: describe.');
end;

// v(ADP3 T1) review fix: the ONE presentation-layer stripper. StripMark (the
// primitive) handles the LEADING marker + the unconditional TrimLeft; this
// layers on top of it a global removal of any EMBEDDED AUTO_MARK occurrence
// (needed for a compound raw blob like MCP's params_json, where the marker
// sits mid-string inside a per-param "desc" value, not at string position 1)
// plus the AUTO_BEGIN/AUTO_END fence marker TEXT wherever it appears in S --
// the facts LINES a fence wraps are left completely untouched, only the two
// marker strings themselves are removed. Swept for fence-PARSING consumers
// before writing this: every consumer that locates content BY the fence
// (StripManagedBlock, Doc.Drift's ExtractManagedBlockBody, Doc.Batch's
// HasManagedBlock) operates on the RAW read-path value, never on this
// function's output, so stripping the fence here for display cannot break
// any of them.
class function TDocRegions.StripForDisplay(const S: string): string;
begin
  Result:= StripMark(S);
  Result:= StringReplace(Result, AUTO_MARK,  '', [rfReplaceAll]);
  Result:= StringReplace(Result, AUTO_BEGIN, '', [rfReplaceAll]);
  Result:= StringReplace(Result, AUTO_END,   '', [rfReplaceAll]);
  Result:= Trim(Result);
end;

// v(ADP2 T9): the DOC/HOVER CONSISTENCY LOCK -- see this function's own
// DocInsight comment (interface section) for the full rationale. Logic here
// is a byte-for-byte lift of the six Phase-2 blocks RenderFactsBlock used to
// inline directly: same guards, same EscXml calls, same separators (three
// literal spaces for Reads/Writes, semicolon-space for SQL), same order.
// Lines are UNPREFIXED -- callers (RenderFactsBlock, hover) each apply
// whatever leading text their own surface needs.
class function TDocRegions.FormatPhase2FactLines(const AFacts: TDocFacts; AComplexityMin: Integer = 10): TArray<string>;
var
  Lines: TStringList;
begin
  Lines:= TStringList.Create;
  try
    // v(ADP2 T3): Complexity -- THRESHOLD APPLIED HERE (render time), not when
    // AFacts was built: AFacts.Cyclomatic/BodyLoc are the RAW index-time
    // values, so a routine at or above AComplexityMin (docs.complexity_min,
    // default 10) gets the line and everything else stays lean -- changing
    // the threshold takes effect on the very next `document`/`hover` call
    // with NO reindex. 'Cyclomatic > 0' guards the AComplexityMin <= 0 edge
    // case: a REAL analyzed routine's cyclomatic complexity is
    // architecturally always >= 1, so 0 is an UNAMBIGUOUS "not computed"
    // sentinel (no symbol_facts row, or no matching defProc at index time).
    if (AFacts.Cyclomatic > 0) and (AFacts.Cyclomatic >= AComplexityMin) then
      Lines.Add(Format('Complexity: %d (cyclomatic), %d lines', [AFacts.Cyclomatic, AFacts.BodyLoc]));
    // v(ADP2 T4): Reads/Writes fields -- ONE line, each side omitted when
    // empty, the WHOLE line omitted when both are empty. AFacts.ReadsFields/
    // WritesFields are ALREADY display-ready (capped, ', '-joined, a
    // ' (+N more)' suffix when truncated), so this is a passthrough. Three
    // literal spaces separate the two sides, per the design spec's own
    // rendering example.
    if (AFacts.ReadsFields <> '') or (AFacts.WritesFields <> '') then
    begin
      var RWLine: string:= '';
      if AFacts.ReadsFields <> '' then RWLine:= 'Reads: ' + EscXml(AFacts.ReadsFields);
      if AFacts.WritesFields <> '' then
      begin
        if RWLine <> '' then RWLine:= RWLine + '   ';
        RWLine:= RWLine + 'Writes: ' + EscXml(AFacts.WritesFields);
      end;
      Lines.Add(RWLine);
    end;
    // v(ADP2 T8): Returned-object ownership -- ONE line, omitted entirely
    // when AFacts.ReturnsOwner = '' (no unanimous, high-confidence verdict --
    // absence over a wrong verdict, since a wrong 'new' invites a
    // double-free). 'new' expands to the fuller 'new (caller owns)' display
    // text here (at render time); 'borrowed'/'self' are already the final
    // display word.
    if AFacts.ReturnsOwner <> '' then
    begin
      var OwnsWord: string;
      if AFacts.ReturnsOwner = 'new' then OwnsWord:= 'new (caller owns)'
      else OwnsWord:= AFacts.ReturnsOwner;
      Lines.Add('Owns returned: ' + EscXml(OwnsWord));
    end;
    // v(ADP2 T6): DFM event-wiring -- ONE line, 'Handles: Button1.OnClick',
    // omitted entirely when AFacts.DfmEvent = ''. Already the final display
    // string (index-time), so no cap/threshold logic is needed here.
    if AFacts.DfmEvent <> '' then
      Lines.Add('Handles: ' + EscXml(AFacts.DfmEvent));
    // v(ADP2 T7): SQL tables touched -- ONE line, 'SQL: reads A, B; writes
    // C', either side omitted when empty, the WHOLE line omitted when both
    // sides are empty. Semicolon-SPACE separates the two sides here (NOT the
    // three-literal-space separator Reads/Writes fields uses above -- this
    // line's own format per the design spec's rendering example).
    if (AFacts.SqlReads <> '') or (AFacts.SqlWrites <> '') then
    begin
      var SqlLine: string:= '';
      if AFacts.SqlReads <> '' then SqlLine:= 'reads ' + EscXml(AFacts.SqlReads);
      if AFacts.SqlWrites <> '' then
      begin
        if SqlLine <> '' then SqlLine:= SqlLine + '; ';
        SqlLine:= SqlLine + 'writes ' + EscXml(AFacts.SqlWrites);
      end;
      Lines.Add('SQL: ' + SqlLine);
    end;
    // v(ADP2 T5): Covered-by-tests -- CONTROLLER OVERRIDE: AFacts.CoveredBy
    // is computed LAZILY by the caller (DRagLint.Doc.SymbolFacts.
    // ComputeCoveredBy), never read back from the index -- see TDocFacts.
    // CoveredBy's own field comment for the full rationale. Already
    // DISPLAY-READY, so this is a one-line omit-when-empty emit.
    if AFacts.CoveredBy <> '' then
      Lines.Add('Covered by: ' + EscXml(AFacts.CoveredBy));
    Result:= Lines.ToStringArray;
  finally
    Lines.Free;
  end;
end;

class function TDocRegions.RenderFactsBlock(const AFacts: TDocFacts; const APrefix: string;
  AIncludeReturns: Boolean = False; AComplexityMin: Integer = 10): string;
var
  Sb: TStringBuilder;
  function MoreSuffix(AShown, ATotal: Integer): string;
  begin
    if ATotal > AShown then Result:= Format(' (+%d more)', [ATotal - AShown]) else Result:= '';
  end;
  // Escapes each element then joins with ', '. Used for every mined name list
  // emitted as element text (Calls / Used in units / Raises / Overridden by).
  function JoinEsc(const A: TArray<string>): string;
  var i: Integer;
  begin
    Result:= '';
    for i:= 0 to High(A) do
    begin
      if i > 0 then Result:= Result + ', ';
      Result:= Result + EscXml(A[i]);
    end;
  end;
  function JoinRefs(const A: TArray<TDocFactRef>): string;
  var i: Integer;
  begin
    Result:= '';
    for i:= 0 to High(A) do
    begin
      if i > 0 then Result:= Result + ', ';
      Result:= Result + EscXml(A[i].Display) + ' (' + EscXml(A[i].Location) + ')';
      // v14 (D5): mark honest uncertainty. A caller whose Confidence is anything
      // OTHER than 'certain'/'' ('ambiguous' = >1 candidate on the type chain;
      // 'unverified' = a name-match with no resolved call_edge) gets a trailing
      // ' ?'. The Facts builder already orders plain (certain) callers before the
      // '?' ones, so the rendered line reads plain-first.
      if not ((A[i].Confidence = '') or SameText(A[i].Confidence, 'certain')) then
        Result:= Result + ' ?';
    end;
  end;
begin
  Sb:= TStringBuilder.Create;
  try
    if Length(AFacts.CalledFrom) > 0 then
      Sb.AppendLine(APrefix + 'Called from: ' + JoinRefs(AFacts.CalledFrom) + MoreSuffix(Length(AFacts.CalledFrom), AFacts.CalledFromTotal));
    if Length(AFacts.Calls) > 0 then
      Sb.AppendLine(APrefix + 'Calls: ' + JoinEsc(AFacts.Calls) + MoreSuffix(Length(AFacts.Calls), AFacts.CallsTotal));
    // Mined Result:=/Exit() return cases as a FACT line -- emitted ONLY when the
    // caller asks (AIncludeReturns), which MergeComment sets solely for a symbol
    // that ALREADY has a HAND-WRITTEN <returns>. For a managed/empty <returns>
    // the observed cases go in the tag itself (ObservedSuffix), so the two never
    // duplicate. Off by default so the drift engine's Fresh render is unchanged.
    // Same mined set the hover popup surfaces, unifying the two views. Semicolon-
    // joined + XML-escaped (a return expression can carry < > &).
    if AIncludeReturns and (Length(AFacts.ReturnCases) > 0) then
    begin
      var Rc: string:= '';
      for var Ri:= 0 to High(AFacts.ReturnCases) do
      begin
        if Ri > 0 then Rc:= Rc + '; ';
        Rc:= Rc + EscXml(AFacts.ReturnCases[Ri]);
      end;
      Sb.AppendLine(APrefix + 'Returns: ' + Rc);
    end;
    if Length(AFacts.UsedInUnits) > 0 then
      Sb.AppendLine(APrefix + 'Used in units: ' + JoinEsc(AFacts.UsedInUnits) + MoreSuffix(Length(AFacts.UsedInUnits), AFacts.UsedInTotal));
    if Length(AFacts.Raises) > 0 then
      Sb.AppendLine(APrefix + 'Raises: ' + JoinEsc(AFacts.Raises));
    // v(ADF T3): ground-truth 'deprecated' directive line. Emitted only when
    // AFacts.Deprecated (the directive was actually found on the decl -- see
    // TDocFactsBuilder.DetectDeprecated). A message renders 'Deprecated: <msg>';
    // a bare directive (no message string) renders the bare 'Deprecated.' line.
    if AFacts.Deprecated then
    begin
      if AFacts.DeprecatedMsg <> '' then
        Sb.AppendLine(APrefix + 'Deprecated: ' + EscXml(AFacts.DeprecatedMsg))
      else
        Sb.AppendLine(APrefix + 'Deprecated.');
    end;
    // v(ADP1 T3): cheap fact group -- each line omit-when-empty, same discipline
    // as the sections above. Overrides/Implements are plain qualified names
    // (never '?'-tagged -- Overrides is ancestry-grounded, Implements is a
    // documented name-based heuristic per TDocFacts.Implements' comment, not an
    // uncertain/ambiguous match in the CalledFrom sense). Overridden by mirrors
    // CalledFrom's cap-plus-'(+N more)' pattern. Overload is a single 'k of n'
    // line, only when n > 1. abstract/virtual are bare one-word marker lines
    // and are INDEPENDENT facts -- a virtual; abstract method correctly
    // renders BOTH (abstract implies virtual). The mutual exclusion that IS
    // enforced is virtual-vs-Overrides: an override suppresses the virtual
    // marker, emitting Overrides instead (see TDocFacts.IsVirtual).
    if AFacts.Overrides <> '' then
      Sb.AppendLine(APrefix + 'Overrides: ' + EscXml(AFacts.Overrides));
    if Length(AFacts.OverriddenBy) > 0 then
      Sb.AppendLine(APrefix + 'Overridden by: ' + JoinEsc(AFacts.OverriddenBy) + MoreSuffix(Length(AFacts.OverriddenBy), AFacts.OverriddenByTotal));
    if AFacts.Implements <> '' then
      Sb.AppendLine(APrefix + 'Implements: ' + EscXml(AFacts.Implements));
    if AFacts.OverloadCount > 1 then
      Sb.AppendLine(APrefix + Format('Overload %d of %d', [AFacts.OverloadOrdinal, AFacts.OverloadCount]));
    if AFacts.IsAbstract then
      Sb.AppendLine(APrefix + 'abstract');
    if AFacts.IsVirtual then
      Sb.AppendLine(APrefix + 'virtual');
    // v(ADP2 T9): the six Phase-2 fact lines (Complexity / Reads-Writes
    // fields / Owns returned / Handles / SQL tables touched / Covered by)
    // are rendered by the SHARED FormatPhase2FactLines helper -- the SAME
    // helper `hover` calls (DRagLint.Hover.Renderer.RenderHoverMarkdown's
    // AFactLines param, threaded in from DoHover/HandleHover) -- so the
    // managed doc block and the hover popup can NEVER show different facts
    // for the same AFacts value (the doc/hover consistency lock). See
    // FormatPhase2FactLines' own comment for what each line means, where its
    // value comes from, and the per-line omit-when-empty/threshold rules --
    // this call site only adds APrefix per line, byte-identical to the
    // pre-extraction output.
    for var P2Line in FormatPhase2FactLines(AFacts, AComplexityMin) do
      Sb.AppendLine(APrefix + P2Line);
    // v(ADF T5): OPT-IN git <since> line. AFacts.Since is '' unless the caller
    // built the facts with --since (TDocFactsBuilder.Build's AIncludeSince) AND
    // git confidently attributed the declaration line, so this renders NOTHING by
    // default and NOTHING on any git failure (absence over a wrong fact) -- the
    // non-since managed block is unchanged. The date is a real git commit date
    // (YYYY-MM-DD), never a guess; one line so the block regenerates idempotently.
    if AFacts.Since <> '' then
      Sb.AppendLine(APrefix + '<since>' + EscXml(AFacts.Since) + '</since>');
    // v(ADF T4): OPT-IN <seealso> cref lines. AFacts.SeeAlso is EMPTY unless the
    // caller built the facts with --seealso (TDocFactsBuilder.Build's
    // AIncludeSeeAlso), so this section renders NOTHING by default -- the
    // non-seealso managed block is unchanged. Each entry is a real indexed
    // qualified name (a resolved callee or a sibling), so no '?'-tagged cref is
    // ever emitted. The list is pre-sorted+capped by Build; one cref per line so
    // the block regenerates idempotently.
    for var SeeI:= 0 to High(AFacts.SeeAlso) do
      Sb.AppendLine(APrefix + '<seealso cref="' + EscXmlAttr(AFacts.SeeAlso[SeeI]) + '"/>');
    Result:= Sb.ToString.TrimRight([#13, #10]);
  finally
    Sb.Free;
  end;
end;

class function TDocRegions.MergeComment(const AExisting: TParsedDoc;
  const ASigParams: TArray<string>; const AFacts: TDocFacts;
  AHasReturn: Boolean; const APrefix: string; AComplexityMin: Integer;
  AExistingHasAnyTag: Boolean): string;
type
  // v(ADP3 T3 review round 2, Finding 1 -- PARAM ONLY): the action the
  // repair path takes for one existing <param>'s raw parsed text -- see
  // ClassifyParamAction's own comment (below) for the full per-arm
  // rationale. <summary>/<returns> do NOT use this: per the coordinator's
  // reversal of their own original Finding-1 ruling, the PLAN had already
  // adjudicated marked+content for those two, deliberately: a human edit
  // inside the markers is NOT separable from "the source comment changed"
  // by the plan's own string comparison, so BOTH refresh, and a human takes
  // ownership by REMOVING the marker -- Task 9's drift report is the
  // documented, future safeguard, not a Task-3 content compare. <param> is
  // the one narrow exception: harvesting is explicitly out of scope for it
  // forever, so "engine-owned, dropped" there is PERMANENT loss with no
  // refresh mechanism and no drift report to ever surface it -- a decision
  // the plan never made, unlike summary/returns.
  TTagAction = (taEngineOwned, taPreserveStripped, taPreserveVerbatim);
var
  Sb   : TStringBuilder;
  P    : string        ;
  Facts: string        ;
  // Emits APrefix + AOpen + AValue + AClose as one or more ///-prefixed lines.
  // A hand-written summary/param/returns description may span several source
  // lines -- the parser preserves the interior #10 line breaks -- so each
  // continuation line MUST be re-prefixed (like the remarks-prose path below).
  // Emitting a multi-line value on a single AppendLine would leave the interior
  // lines WITHOUT a /// prefix: that both corrupts the source and breaks the
  // ///-comment block, so a later run mis-parses the fragment and injects/
  // duplicates managed blocks. Single-line values are emitted unchanged.
  function EmitTagged(const AOpen, AValue, AClose: string): string;
  var Norm: string; Parts: TArray<string>; i: Integer;
  begin
    Norm:= StringReplace(AValue, #13#10, #10, [rfReplaceAll]);
    Norm:= StringReplace(Norm, #13, #10, [rfReplaceAll]);
    Parts:= Norm.Split([#10]);
    Result:= APrefix + AOpen;
    for i:= 0 to High(Parts) do
      if i = 0 then Result:= Result + Parts[i]
      else Result:= Result + sLineBreak + APrefix + Trim(Parts[i]);
    Result:= Result + AClose;
  end;
  // v(ADP3 T3): True when S is engine-owned WITHOUT regard to emptiness --
  // carries AUTO_MARK, or is the legacy 'TODO: describe.' sentinel (the
  // pre-v(ADP3) format; still self-heals here). Used for <summary> and
  // <returns> ONLY: marked there means engine-owned, full stop, regardless
  // of what follows the marker -- see the plan's own recorded deviation
  // (a human edit inside the markers is not separable from "the source
  // comment changed", so both refresh; ownership changes hands only by
  // REMOVING the marker, never by the engine sniffing content). v(ADP3 T3
  // review round 2): a content-keyed exception was tried here and reverted
  // -- an exact-string compare against generated text is content-keyed
  // ownership by the back door, MORE brittle than the StartsText('Observed:')
  // sniff Task 1 deleted (exact equality survives neither whitespace
  // normalization nor legitimate drift, where a prefix match would have
  // survived both) -- see MergeComment's own remarks for the reproduced
  // breakage.
  function IsEngineOwnedRegardlessOfContent(const S: string): Boolean;
  begin
    Result:= IsManagedText(S) or SameText(Trim(S), 'TODO: describe.');
  end;
  // v(ADP3 T3 review round 2, Finding 1 -- PARAM ONLY): classifies
  // ownership of one existing <param>'s raw parsed text (S) for the repair
  // path, given whether the tag is literally present at all (AHasTag) --
  //   - marked (AUTO_MARK) + EMPTY post-marker body -> taEngineOwned: DROP
  //     entirely (v(ADP3 T3)'s omit-when-empty rule; no harvester for
  //     params exists, or ever will, so there is no "regenerate" arm).
  //   - marked + NON-EMPTY post-marker body -> taPreserveStripped: a human
  //     added real text INSIDE the tag WITHOUT removing the marker. Unlike
  //     <summary>/<returns>, the plan's "both refresh" deviation does not
  //     reach params (harvesting is explicitly out of scope for <param>
  //     forever), so "engine-owned, dropped" here would be PERMANENT,
  //     unrecoverable loss with no refresh and no drift report ever able to
  //     surface it -- preserved instead, marker stripped (the human is now
  //     the de facto owner).
  //   - the legacy pre-v(ADP3) 'TODO: describe.'/trailing-AUTO_PARAM
  //     sentinel -> taEngineOwned UNCONDITIONALLY: the sentinel carries no
  //     real information regardless of its own non-empty text, so it always
  //     self-heals away.
  //   - unmarked, tag literally present (AHasTag), not the legacy sentinel
  //     -> taPreserveVerbatim: hand-written, preserved exactly as parsed,
  //     including a deliberately blank slot.
  //   - unmarked, no tag at all -> taEngineOwned (nothing to preserve).
  function ClassifyParamAction(const S: string; AHasTag: Boolean): TTagAction;
  begin
    if IsManagedText(S) then
    begin
      if Trim(StripMark(S)) = '' then Result:= taEngineOwned
      else Result:= taPreserveStripped;
    end
    else if SameText(Trim(S), 'TODO: describe.') then Result:= taEngineOwned
    else if AHasTag then Result:= taPreserveVerbatim
    else Result:= taEngineOwned;
  end;
begin
  Sb:= TStringBuilder.Create;
  try
    // The mined return cases surface in exactly ONE place. For a symbol whose
    // existing <returns> is HAND-WRITTEN (a real tag, not engine-owned) they go
    // in a managed 'Returns:' fact line (so they show alongside the author's
    // prose); for an engine-owned <returns> they fill the tag itself
    // (ObservedSuffix, below). Never both. v(ADP3 T3): "hand-written" now
    // requires AExisting.HasReturnsTag (the tag literally exists) as well as
    // not-engine-owned -- so a human's deliberately EMPTY <returns></returns>
    // is ALSO hand-written (gets a Returns: fact line, exactly like non-empty
    // prose), whereas NO tag at all (HasReturnsTag False) is never
    // "hand-written": its mined cases go straight into the (possibly
    // newly-added) tag instead of ALSO duplicating into a fact line. v(ADP3
    // T1): ownership is otherwise marker-keyed; the pre-v(ADP3)
    // StartsText('Observed:', ...) content sniff stays deleted -- and (v(ADP3
    // T3 review round 2)) stays deleted for good reason: a marked <returns>
    // is ALWAYS engine-owned regardless of content (see
    // IsEngineOwnedRegardlessOfContent's own comment).
    // v(ADP3 T3 review round 2, Finding 4 interaction): gated on
    // AExistingHasAnyTag, not AExisting.HasContent -- since AExistingHasAnyTag
    // (not just HasContent) is what now decides whether the repair path runs
    // at all (see below), gating "hand-written" on the narrower HasContent
    // here would be internally inconsistent: a comment consisting ONLY of an
    // unmarked, blank <returns></returns> (HasReturnsTag True, HasContent
    // False) correctly enters the repair path via AExistingHasAnyTag, and
    // must ALSO be recognized as hand-written there (preserved verbatim) --
    // not silently regenerated because a narrower, pre-Finding-4 gate never
    // anticipated reaching this code with HasContent still False.
    var ReturnsHandWritten: Boolean:=
      AExistingHasAnyTag and AExisting.HasReturnsTag
      and (not IsEngineOwnedRegardlessOfContent(AExisting.ReturnsText));
    var IncludeReturns: Boolean:=
      ReturnsHandWritten and AHasReturn and (Length(AFacts.ReturnCases) > 0);
    Facts:= RenderFactsBlock(AFacts, APrefix, IncludeReturns, AComplexityMin);
    // v(ADP3 T3 review round 2, Finding 4): AExistingHasAnyTag is a SEPARATE
    // signal from AExisting.HasContent, computed by the caller (BuildForSymbol)
    // from HasSummaryTag/HasReturnsTag/Params/AExisting.HasContent itself/an
    // unmodeled-tag check over the raw region -- NOT a widening of
    // TParsedDoc.HasContent itself (reverted; other consumers -- the
    // indexer's symbol_docs write, context bundling, TypeAt, MCP, LSP hover
    // -- correctly treat a blank-slot-only comment as "not documented", and
    // that must stay true). Only THIS repair-vs-fresh decision needs "does a
    // comment region exist at all", so only this decision gets the wider
    // signal (AExistingHasAnyTag already subsumes AExisting.HasContent --
    // see BuildForSymbol's own computation -- so testing it alone suffices).
    if not AExistingHasAnyTag then
    begin
      // v(ADP3 T3): omit-when-empty. A tag with nothing to say is not written
      // at all -- an empty <summary> renders as a BLANK DocInsight tooltip,
      // which is strictly worse than no tooltip. The FRESH path has no
      // hand-written content by definition, so <summary> is emitted only when
      // the harvester (v(ADP3 T7)) supplied text, and <param> never (see the
      // spec's out-of-scope note on <param> harvesting -- a fresh comment
      // never carries a <param> skeleton at all).
      if AFacts.HarvestedSummary <> '' then
        Sb.AppendLine(EmitTagged('<summary>' + AUTO_MARK, AFacts.HarvestedSummary, '</summary>'));
      if AHasReturn then
      begin
        var Obs: string:= Trim(ObservedSuffix(AFacts.ReturnCases));
        if Obs <> '' then
          Sb.AppendLine(APrefix + '<returns>' + AUTO_MARK + Obs + '</returns>');
      end;
      if Facts <> '' then
      begin
        Sb.AppendLine(APrefix + '<remarks>');
        Sb.AppendLine(APrefix + AUTO_BEGIN);
        Sb.AppendLine(Facts);
        Sb.AppendLine(APrefix + AUTO_END);
        Sb.AppendLine(APrefix + '</remarks>');
      end;
      Result:= Sb.ToString.TrimRight([#13, #10]);
      Exit;
    end;

    // Existing comment: preserve prose, regenerate managed regions. Rebuild
    // from the parsed model: keep Summary (or drop it when it is engine-
    // owned and the harvest has nothing to say), keep hand-typed params +
    // descs (including a MARKED <param> with real post-marker text --
    // Finding 1, param-only), never add a <param> skeleton for a sig param
    // with nothing hand-written (no harvester, ever), flag hand-typed stale
    // params, then the returns tag, then a fresh <remarks> managed block.
    //
    // v(ADP3 T3): three-way rule for <summary> --
    //   unmarked + the tag is LITERALLY PRESENT (HasSummaryTag), empty or
    //     not -> a HUMAN wrote it: preserve verbatim, whatever it says.
    //   marked (or legacy self-heal), or no tag at all -> ENGINE-owned:
    //     refill from the harvest, or omit entirely when there is nothing
    //     to refill with (v(ADP3 T3)'s omit-when-empty rule) -- v(ADP3 T3
    //     review round 2): marked ALWAYS means engine-owned here regardless
    //     of post-marker content, same as <returns> -- see
    //     IsEngineOwnedRegardlessOfContent's own comment.
    var SummaryRaw: string:= AExisting.Summary;
    if AExisting.HasSummaryTag and (not IsEngineOwnedRegardlessOfContent(SummaryRaw)) then
      Sb.AppendLine(EmitTagged('<summary>', SummaryRaw, '</summary>'))
    else if AFacts.HarvestedSummary <> '' then
      Sb.AppendLine(EmitTagged('<summary>' + AUTO_MARK, AFacts.HarvestedSummary, '</summary>'));
    // else: engine-owned-and-empty, or genuinely absent, and nothing
    // harvested -- omit the tag entirely (v(ADP3 T3)).

    // <param>: v(ADP3 T3 review round 2, Finding 1 -- the ONE tag where
    // marked+content is preserved rather than treated as engine-owned; see
    // ClassifyParamAction's own comment for why params differ from
    // summary/returns. Presence for a param needs no separate flag: the EP
    // entry existing in AExisting.Params already IS that signal (AHasTag is
    // True whenever a matching EP is found below).
    // existing params first, in signature order where possible
    for P in ASigParams do
    begin
      for var EP in AExisting.Params do
        if SameText(EP.Name, P) then
        begin
          case ClassifyParamAction(EP.Desc, True) of
            taPreserveStripped: Sb.AppendLine(EmitTagged('<param name="' + P + '">', StripMark(EP.Desc), '</param>'));
            taPreserveVerbatim: Sb.AppendLine(EmitTagged('<param name="' + P + '">', EP.Desc, '</param>'));
            taEngineOwned: ; // no harvester for params -- always drop, never regenerate
          end;
          Break;
        end;
      // If no EP matched P at all (the inner loop found nothing): no <param>
      // tag exists for this sig param -- nothing hand-written to preserve
      // and no harvester to fill it, so nothing is emitted for it either
      // (v(ADP3 T3): fresh/missing params never get a skeleton).
    end;
    // stale hand-typed params: in the comment but not the signature -> flag, keep
    for var EP in AExisting.Params do
    begin
      var StillThere: Boolean:= False;
      for P in ASigParams do if SameText(EP.Name, P) then begin StillThere:= True; Break; end;
      if (not StillThere) and (not IsManagedDesc(EP.Desc)) then
        Sb.AppendLine(EmitTagged('<param name="' + EP.Name + '">', EP.Desc, '</param> <!-- drag-lint: param no longer exists -->'));
    end;

    if AHasReturn then
    begin
      if ReturnsHandWritten then
        // hand-written, including a deliberate blank slot -- preserved
        // verbatim; its mined cases (if any) went into the 'Returns:' fact
        // line above (IncludeReturns) instead of disturbing this text.
        Sb.AppendLine(EmitTagged('<returns>', AExisting.ReturnsText, '</returns>'))
      else
      begin
        // engine-owned (marked -- ALWAYS, regardless of post-marker content,
        // v(ADP3 T3 review round 2) -- or the legacy TODO self-heal) or no
        // tag at all: refill from the mined cases, or omit entirely when
        // there is nothing mined to say (v(ADP3 T3): a managed/empty
        // <returns> is never written).
        var Obs: string:= Trim(ObservedSuffix(AFacts.ReturnCases));
        if Obs <> '' then
          Sb.AppendLine(APrefix + '<returns>' + AUTO_MARK + Obs + '</returns>');
      end;
    end;

    // remarks: keep hand prose (AExisting.Remarks) OUTSIDE the fence, then a fresh
    // managed block. Strip any old fenced block from the prose before re-emitting
    // so a second run does not nest blocks.
    var Prose: string:= StripManagedBlock(AExisting.Remarks);
    var NormProse: string:= StringReplace(Trim(Prose), #13#10, #10, [rfReplaceAll]);
    NormProse:= StringReplace(NormProse, #13, #10, [rfReplaceAll]);
    // v(ADP3 T2 adjacent fix): a SINGLE-LINE hand-written remarks with NO
    // facts to add is re-emitted on ONE line -- '<remarks>prose</remarks>' --
    // exactly like EmitTagged already does for a single-line summary/param/
    // returns value, instead of the unconditional open-tag-alone / prose-
    // alone / close-tag-alone split below. Without this, merely touching a
    // comment that has an UNTOUCHED single-line <remarks> (e.g. adding a
    // managed <returns> tag elsewhere in the SAME comment) forces that
    // remarks tag to expand into three lines even though nothing about it
    // needed to change -- churn a marker-keyed `document --strip` can never
    // undo, since there is no marker distinguishing "the engine reformatted
    // this" from "a human genuinely wrote three lines" (see TDocStripper's
    // own marker-only ownership rule). Multi-line prose, or any Facts to
    // fence, still take the multi-line path below unchanged -- a fence
    // always needs its own lines.
    if (Trim(Prose) <> '') and (Facts = '') and (not NormProse.Contains(#10)) then
      Sb.AppendLine(APrefix + '<remarks>' + Trim(Prose) + '</remarks>')
    else if (Trim(Prose) <> '') or (Facts <> '') then
    begin
      Sb.AppendLine(APrefix + '<remarks>');
      if Trim(Prose) <> '' then
      begin
        // Hand-written remarks prose may contain multiple lines (the parser joins
        // them with bare #10). Emit EACH line APrefix-prefixed so every output line
        // carries /// and the final CRLF join stays valid -- never one line with an
        // embedded bare LF.
        for var ProseLine in NormProse.Split([#10]) do
          if Trim(ProseLine) <> '' then
            Sb.AppendLine(APrefix + Trim(ProseLine));
      end;
      if Facts <> '' then
      begin
        Sb.AppendLine(APrefix + AUTO_BEGIN);
        Sb.AppendLine(Facts);
        Sb.AppendLine(APrefix + AUTO_END);
      end;
      Sb.AppendLine(APrefix + '</remarks>');
    end;
    Result:= Sb.ToString.TrimRight([#13, #10]);
  finally
    Sb.Free;
  end;
end;

end.
