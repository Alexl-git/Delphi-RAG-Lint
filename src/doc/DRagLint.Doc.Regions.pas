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
    /// <summary>Removes every well-formed &lt;ATagName ...&gt;...&lt;/ATagName&gt;
    /// span from S (non-greedy, case-insensitive, tolerates attributes on the
    /// opening tag, e.g. &lt;param name="X"&gt;; ALL occurrences are removed, not
    /// just the first).</summary>
    /// <remarks>v(ADP3 T3b review, Critical 1 fix): used to determine which raw
    /// content sits OUTSIDE the containers MergeComment already preserves
    /// verbatim (&lt;summary&gt;/&lt;param&gt;/&lt;returns&gt;/&lt;remarks&gt;/&lt;exception&gt;/
    /// &lt;example&gt;/&lt;deprecated&gt;/&lt;since&gt;), so an inline tag NESTED inside one
    /// of them (e.g. a hand-written &lt;see cref="X"/&gt; that is part of a
    /// human's &lt;summary&gt; prose) is not ALSO captured as if it were a
    /// standalone sibling tag and duplicated on re-emit -- see MergeComment's
    /// own remarks for the full defect this closes.</remarks>
    class function StripElement(const S, ATagName: string): string;
    /// <summary>Reparses ARawBlock with every container in
    /// PRESERVED_VERBATIM_CONTAINERS stripped EXCEPT AOwnTagName (pass '' to
    /// strip all of them), then returns TDocCommentParser.ParseXmlDoc's
    /// result on that stripped copy.</summary>
    /// <param name="AOwnTagName">The ONE container type NOT to strip -- the
    /// caller is about to read that field from the result. Must be excluded
    /// from its own strip pass: stripping '<exception>' before reading
    /// Result.Exceptions would remove every exception, including genuinely
    /// standalone ones, which is the exact content this call is trying to
    /// recover -- see MergeComment's own remarks for why "strip everything"
    /// is wrong and "strip everything else" is required instead.</param>
    /// <remarks>v(ADP3 T3b review round 2, Critical 1 still-open fix): a tag
    /// from ANY of the five preserved-verbatim fields (exception/example/
    /// deprecated/since -- seealso/see are never stripped by StripElement at
    /// all, since RxSee never captures a body, so they need no self-exclusion)
    /// can nest inside ANY OTHER one of them, not only inside &lt;summary&gt;
    /// (confirmed empirically: &lt;since&gt; inside &lt;exception&gt;, &lt;seealso&gt; inside
    /// &lt;example&gt;/&lt;deprecated&gt;/&lt;exception&gt;, &lt;exception&gt; inside &lt;example&gt;) --
    /// a single shared "Standalone" that strips a FIXED list can never be
    /// correct for more than one of the five fields at once, because
    /// whichever field's own tag type is in that fixed list is thereby
    /// erased before it can be read back. MergeComment therefore calls this
    /// once per field, each time excluding that field's own container.</remarks>
    class function BuildStandaloneFor(const ARawBlock, AOwnTagName: string): TParsedDoc;
    /// <summary>Partitions ARawBlock's LINES into the ones the engine can
    /// fully account for (returned, joined, in AAccountedRaw) and the ones it
    /// cannot (returned verbatim, in AResidualLines). True when at least one
    /// residual line was found; when False, AAccountedRaw is ARawBlock
    /// unchanged and AResidualLines is empty, so the caller can skip the whole
    /// mechanism and behave exactly as it did before v(ADP3 T3f).</summary>
    /// <param name="ARawBlock">The region's raw text, as
    /// TDocCommentScanner.Scan produced it: one entry per source line, the
    /// leading /// already removed by the scanner, every other character --
    /// INCLUDING the interior indentation of a code sample -- intact.</param>
    /// <param name="AAccountedRaw">The accounted lines, joined with sLineBreak.
    /// Parse THIS, not ARawBlock, to drive the repair path: a tag sitting on a
    /// residual line is thereby invisible to the emitter, so it can never be
    /// re-emitted a second time alongside the verbatim line that already
    /// carries it.</param>
    /// <param name="AResidualLines">The residual lines, in source order, right-
    /// trimmed, still without their /// prefix. The caller re-prefixes and
    /// emits them verbatim.</param>
    /// <remarks>The rule is LINE-LEVEL OWNERSHIP: the engine owns a line only
    /// when it can represent EVERYTHING on it. A line carrying any non-
    /// whitespace the engine cannot re-emit is handed back to the author whole,
    /// and every span that touches such a line is retracted (transitively, to a
    /// fixed point) so the emitter forgets about it. Splitting a mixed line
    /// into "the bits the engine knows" plus "the bits it does not" was
    /// rejected: re-emitting only the unaccounted CHARACTERS mangles the
    /// author's prose exactly the way reading &lt;deprecated&gt;'s message from a
    /// stripped view once did ("Added in  and still valid."), and emitting the
    /// whole line WITHOUT retracting its spans duplicates every tag on it --
    /// unboundedly for &lt;see&gt;/&lt;seealso&gt;, whose parser regex is a plural
    /// .Matches. A multi-line &lt;example&gt; that is not nested inside another
    /// container is deliberately treated as unaccounted: it IS modeled, but the
    /// engine cannot re-serialize a code sample without destroying its interior
    /// indentation, so handing it back verbatim is the only faithful option.
    /// Accounted spans are the eight PRESERVED_VERBATIM_CONTAINERS -- matched
    /// with THE PARSER's own strict patterns, never StripElement's
    /// attribute-tolerant ones, so a tag the parser cannot represent (an
    /// attributed &lt;remarks xml:lang="en"&gt;, a cref-less &lt;exception&gt;) falls to
    /// residual instead of being accounted and then silently dropped -- plus
    /// the self-closing &lt;see&gt;/&lt;seealso&gt;/&lt;deprecated/&gt; forms, the engine's own
    /// drag-lint HTML markers, and the untagged leading run that
    /// ParseXmlDoc's own fallback turns into the summary. Two shapes FAIL
    /// CLOSED and abort the whole mechanism for the region (this returns False,
    /// so the caller behaves exactly as it did before v(ADP3 T3f)): a residual
    /// line overlapping a span whose content the engine REGENERATES rather than
    /// round-trips (any &lt;remarks&gt;, or any span carrying an engine marker), and
    /// an AUTO_BEGIN with no matching AUTO_END. Lines inside a well-formed
    /// fence are never residual at all -- they are re-derived every run.</remarks>
    class function SplitResidualLines(const ARawBlock: string;
      out AAccountedRaw: string; out AResidualLines: TArray<string>): Boolean;
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
    /// present in the signature. v(ADP3 T3f): repair also CARRIES THROUGH,
    /// verbatim, every line of the existing region it cannot fully account
    /// for -- an unmodeled tag (&lt;value&gt;/&lt;para&gt;/&lt;list&gt;/...), author prose
    /// sitting beside a modeled tag on the same line, and a multi-line
    /// &lt;example&gt; whose interior indentation the emitter cannot reproduce.
    /// Those lines are re-emitted with their original indentation, in source
    /// order, after every modeled tag and before the facts &lt;remarks&gt; block,
    /// and nothing on such a line is ALSO re-emitted from the model (see
    /// SplitResidualLines). When the carried-through lines are the ONLY thing
    /// there would be to write, this returns '' instead and the region is
    /// left untouched.</summary>
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

uses
  // v(ADP3 T3b): MergeComment's exception/example/seealso/since preserve
  // logic re-parses a copy of the existing raw comment block, stripped of
  // the containers it already preserves verbatim, via the SAME
  // TDocCommentParser.ParseXmlDoc already used to parse it the first time --
  // reused as-is (no duplicated regex, no parser change), never a new
  // heuristic. No circularity: this unit does not depend on DRagLint.Doc.Regions.
  DRagLint.Parser.DocComments,
  // v(ADP3 T3b review, Critical 1 fix): StripElement's TRegEx.
  System.RegularExpressions;

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

class function TDocRegions.StripElement(const S, ATagName: string): string;
var
  Re: TRegEx;
begin
  // Non-greedy content match ([\s\S]*?), an optional attribute list on the
  // opening tag ((?:\s[^>]*)?, e.g. ' name="X"' for <param>), ALL occurrences
  // removed (TRegEx.Replace with no count limit replaces every match) -- see
  // this function's own interface remarks for why "every occurrence, not
  // just the first" matters (a hand-typed <param> repeats once per
  // parameter; each is ALREADY preserved individually by MergeComment's own
  // param loop, so each must also be excluded here).
  Re:= TRegEx.Create('<' + ATagName + '(?:\s[^>]*)?>[\s\S]*?</' + ATagName + '>', [roIgnoreCase]);
  Result:= Re.Replace(S, '');
end;

// v(ADP3 T3b review round 2, Critical 1 still-open fix): the SINGLE canonical
// enumeration of every tag MergeComment re-emits verbatim (the author's own
// raw captured text, unparsed) -- BOTH the emitter (each tag's own emission
// in MergeComment, below) and BuildStandaloneFor (which strips this exact
// list, minus the one field being computed) must agree on this set, so it
// cannot silently drift the way the round-1 fix's hand-written 4-item list
// did (it named only summary/param/returns/remarks and silently missed
// exception/example/deprecated/since, all four of which are ALSO preserved
// verbatim and can ALSO contain further nested tags -- confirmed
// empirically: <since> inside <exception>, <seealso> inside <example>/
// <deprecated>/<exception>, <exception> inside <example>). 'seealso'/'see'
// are DELIBERATELY excluded from this list: they are always self-closing
// (RxSee never captures a body -- its own pattern ends at the opening tag,
// '\s*/?>'), so StripElement (which requires an explicit closing tag) can
// never match them regardless of what list it is given -- including them
// would be a guaranteed no-op, not a needed protection, and they never need
// "exclude self" treatment in BuildStandaloneFor for the same reason.
const
  PRESERVED_VERBATIM_CONTAINERS: array[0..7] of string = (
    'summary', 'param', 'returns', 'remarks',
    'exception', 'example', 'deprecated', 'since'
  );

class function TDocRegions.BuildStandaloneFor(const ARawBlock, AOwnTagName: string): TParsedDoc;
var
  Text: string;
  Tag : string;
begin
  Text:= ARawBlock;
  for Tag in PRESERVED_VERBATIM_CONTAINERS do
    if not SameText(Tag, AOwnTagName) then
      Text:= StripElement(Text, Tag);
  Result:= TDocCommentParser.ParseXmlDoc(Text);
end;

// v(ADP3 T3f): SplitResidualLines' regex set, hoisted to file scope and built
// once, lazily -- the same idiom, for the same reason, as
// DRagLint.Parser.DocComments' EnsureParserRegexes: SplitResidualLines runs on
// EVERY repaired comment, and constructing a dozen TRegEx per symbol on a
// whole-project run is exactly the per-call cost that unit already removed
// from ParseXmlDoc. Not thread-guarded, same as that cache and for the same
// reason (doc parsing is single-threaded in this codebase).
//
// v(ADP3 T3f review, IMPORTANT 1): RxResContainer mirrors THE PARSER's own
// per-tag patterns, character for character, NOT StripElement's
// attribute-tolerant form. The mask decides what the emitter will re-emit, and
// the emitter can only re-emit what the parser REPRESENTED -- so the two must
// agree or the gap between them is silently deleted.
//
// The first cut of this used StripElement's '<TAG(?:\s[^>]*)?>...</TAG>' on the
// reasoning that BuildStandaloneFor strips with that pattern, so the two "must
// agree on what a container occupies". That reasoning was wrong: the strip set
// and the REPRESENTATION set are different questions, and four shapes fell in
// the gap and were destroyed by a single `document --apply` -- '<exception>'
// with no cref, '<param>' with no name, and the perfectly VALID attributed
// forms '<remarks xml:lang="en">' and '<example lang="pascal">'. None of them
// is captured by the parser, so none is ever re-emitted; accounting for them
// meant they were not carried through either. With the strict patterns they
// fall to residual and survive verbatim.
//
// There is no interaction with BuildStandaloneFor's looser strip: a line the
// mask does not account for is REMOVED from the accounted text before
// BuildStandaloneFor ever sees it, so StripElement is never handed the shape
// the two patterns disagree about.
//
// INDEX-ALIGNED with PRESERVED_VERBATIM_CONTAINERS, entry for entry. Adding a
// container name there requires adding its pattern here at the same index.
const
  PRESERVED_CONTAINER_PATTERNS: array[0..7] of string = (
    '<summary>[\s\S]*?</summary>',
    '<param\s+name="[^"]+">[\s\S]*?</param>',
    '<returns>[\s\S]*?</returns>',
    '<remarks>[\s\S]*?</remarks>',
    '<exception\s+cref="[^"]+">[\s\S]*?</exception>',
    '<example>[\s\S]*?</example>',
    '<deprecated>[\s\S]*?</deprecated>',
    '<since>[\s\S]*?</since>'
  );

var
  ResidualRegexesReady: Boolean = False;
  RxResContainer      : array[0..7] of TRegEx;
  RxResSummaryBody    : TRegEx;
  RxResSee            : TRegEx;
  RxResDeprecatedBare : TRegEx;
  RxResEngineMarker   : TRegEx;

procedure EnsureResidualRegexes;
var
  I: Integer;
begin
  if ResidualRegexesReady then Exit;
  for I:= Low(PRESERVED_CONTAINER_PATTERNS) to High(PRESERVED_CONTAINER_PATTERNS) do
    RxResContainer[I]:= TRegEx.Create(PRESERVED_CONTAINER_PATTERNS[I], [roIgnoreCase]);
  // Deliberately the PARSER's own <summary> pattern, character for character
  // (no attribute tolerance): this one is used only to decide whether
  // ParseXmlDoc's untagged-prefix fallback would fire, so it has to answer
  // that question the way ParseXmlDoc itself answers it -- the fallback runs
  // whenever Result.Summary is still '', which is exactly "RxSummary did not
  // match, or matched a body that Trim()s away to nothing".
  RxResSummaryBody   := TRegEx.Create('<summary>([\s\S]*?)</summary>', [roIgnoreCase]);
  RxResSee           := TRegEx.Create('<(?:see|seealso)\s+cref="[^"]+"\s*/?>', [roIgnoreCase]);
  RxResDeprecatedBare:= TRegEx.Create('<deprecated\s*/>', [roIgnoreCase]);
  // Every HTML comment the engine itself writes: AUTO_MARK, AUTO_BEGIN,
  // AUTO_END, the legacy AUTO_PARAM sentinel, and the stale-param note
  // MergeComment appends after a no-longer-existing '<param>'. Without this,
  // that stale-param note would be unaccounted text on an otherwise accounted
  // line, which would reclassify the whole line as residual and quietly move
  // it out of the param slot.
  RxResEngineMarker  := TRegEx.Create('<!--\s*drag-lint\b[\s\S]*?-->', [roIgnoreCase]);
  ResidualRegexesReady:= True;
end;

class function TDocRegions.SplitResidualLines(const ARawBlock: string;
  out AAccountedRaw: string; out AResidualLines: TArray<string>): Boolean;
type
  // One span of ARawBlock the engine can re-emit on its own. Dropped spans are
  // retracted: the emitter must NOT see them, because the line carrying them
  // is being handed back to the author verbatim instead.
  TResSpan = record
    Lo, Hi        : Integer;
    IsExample     : Boolean;
    // v(ADP3 T3f review, IMPORTANT 2 and 3): True when the engine REGENERATES
    // this span's content rather than round-tripping it -- any <remarks> (the
    // facts fence is rebuilt every run), and any span carrying an engine
    // marker (a marked <summary>/<param>/<returns>, whose content is refilled
    // from the harvest or the mined return cases). Such a span must never be
    // retracted: handing it back verbatim would freeze engine-generated text
    // as un-maintained, un-strippable author content AND leave the engine to
    // emit a SECOND <remarks>/<returns> beside the frozen copy -- a one-way
    // ratchet from engine content to author content.
    NonRetractable: Boolean;
    Dropped       : Boolean;
  end;
var
  RawLines : TArray<string> ;
  Joined   : string         ;
  LineLo   : TArray<Integer>;
  LineHi   : TArray<Integer>;
  Accounted: TArray<Boolean>;
  Residual : TArray<Boolean>;
  InFence  : TArray<Boolean>;
  Spans    : TArray<TResSpan>;
  Sb       : TStringBuilder ;
  I, J, K  : Integer        ;
  Changed  : Boolean        ;
  First    : Boolean        ;
  ResCount : Integer        ;

  procedure AddSpan(APos, ALen: Integer; AIsExample, AIsRemarks: Boolean);
  begin
    if ALen <= 0 then Exit;
    SetLength(Spans, Length(Spans) + 1);
    Spans[High(Spans)].Lo            := APos;
    Spans[High(Spans)].Hi            := APos + ALen - 1;
    Spans[High(Spans)].IsExample     := AIsExample;
    // Tested with RxResEngineMarker itself rather than a second, literal
    // spelling of the marker text -- one definition of "an engine marker",
    // so this test can never drift from what the mask accounts for.
    Spans[High(Spans)].NonRetractable:= AIsRemarks or
      RxResEngineMarker.IsMatch(Copy(Joined, APos, ALen));
    Spans[High(Spans)].Dropped       := False;
  end;

  procedure AddMatches(const ARe: TRegEx; AIsExample, AIsRemarks: Boolean);
  var
    MC: TMatchCollection;
    M : Integer         ;
  begin
    MC:= ARe.Matches(Joined);
    for M:= 0 to MC.Count - 1 do
      AddSpan(MC[M].Index, MC[M].Length, AIsExample, AIsRemarks);
  end;

begin
  AAccountedRaw := ARawBlock;
  AResidualLines:= nil;
  Result        := False;
  Spans         := nil;

  RawLines:= ARawBlock.Split([sLineBreak, #10, #13]);
  if Length(RawLines) = 0 then Exit;

  // An LF-joined copy of the same lines: identical to ARawBlock as far as tag
  // matching is concerned (a line break is a line break to every pattern
  // here), but with trivially computable 1-based per-line offsets -- exactly
  // one separator character per break. Line I occupies [LineLo[I]..LineHi[I]];
  // an EMPTY line yields Hi = Lo - 1, an empty range, which every loop below
  // simply skips.
  SetLength(LineLo, Length(RawLines));
  SetLength(LineHi, Length(RawLines));
  Sb:= TStringBuilder.Create;
  try
    for I:= 0 to High(RawLines) do
    begin
      if I > 0 then Sb.Append(#10);
      LineLo[I]:= Sb.Length + 1;
      Sb.Append(RawLines[I]);
      LineHi[I]:= Sb.Length;
    end;
    Joined:= Sb.ToString;
  finally
    Sb.Free;
  end;
  if Joined = '' then Exit;

  EnsureResidualRegexes;

  for I:= Low(PRESERVED_VERBATIM_CONTAINERS) to High(PRESERVED_VERBATIM_CONTAINERS) do
    AddMatches(RxResContainer[I],
      SameText(PRESERVED_VERBATIM_CONTAINERS[I], 'example'),
      SameText(PRESERVED_VERBATIM_CONTAINERS[I], 'remarks'));
  // <see>/<seealso>/<deprecated/> are round-tripped verbatim, so they ARE
  // retractable -- that is what lets an inline <see cref> inside an unmodeled
  // <para> stay on the author's own line instead of being hoisted out.
  AddMatches(RxResSee           , False, False);
  AddMatches(RxResDeprecatedBare, False, False);
  // Engine markers carry AUTO_MARKER_LEAD by construction, so AddSpan marks
  // every one of them non-retractable: a line mixing the engine's own
  // bookkeeping with author content is ambiguous, and this whole mechanism
  // fails closed on ambiguity.
  AddMatches(RxResEngineMarker  , False, False);

  // ParseXmlDoc's untagged-prefix fallback: when no <summary> body survives,
  // the run before the first '<' (or the WHOLE text, when there is no '<' at
  // all) becomes the summary -- so the engine does re-emit it, and it is
  // accounted for. When a real <summary> body IS present the fallback never
  // fires, so leading prose there is genuinely unrepresented and must stay
  // residual.
  var SumM: TMatch:= RxResSummaryBody.Match(Joined);
  if (not SumM.Success) or (Trim(SumM.Groups[1].Value) = '') then
  begin
    var LtPos: Integer:= Pos('<', Joined);
    if LtPos = 0 then AddSpan(1, Length(Joined), False, False)
    else if LtPos > 1 then AddSpan(1, LtPos - 1, False, False);
  end;

  // v(ADP3 T3f review, IMPORTANT 2): lines inside an AUTO_BEGIN..AUTO_END fence
  // are ENGINE-GENERATED and re-derived on every run, so they can never be
  // author content and must never be carried through -- not even when the
  // <remarks> element around them has been retracted, and not when the fence is
  // orphaned outside any <remarks> at all. Carrying them through freezes a fact
  // the engine should keep maintaining, and strips its markers off so
  // `document --strip` can no longer remove it.
  //
  // An AUTO_BEGIN with no matching AUTO_END is ambiguous corruption: abort the
  // whole mechanism and leave the region exactly as it is, the same way
  // RegionFullyEngineOwned and StripRegion both already fail closed on it.
  SetLength(InFence, Length(RawLines));
  I:= 0;
  while I <= High(RawLines) do
    if Pos(AUTO_BEGIN, RawLines[I]) > 0 then
    begin
      J:= I;
      while (J <= High(RawLines)) and (Pos(AUTO_END, RawLines[J]) = 0) do Inc(J);
      if J > High(RawLines) then Exit; // unterminated fence -- fail closed
      for K:= I to J do InFence[K]:= True;
      I:= J + 1;
    end
    else Inc(I);

  // A multi-line <example> that is not nested inside another container is
  // retracted up front: see this function's interface remarks for why the
  // engine cannot faithfully re-serialize a code sample. Nested ones are left
  // accounted, so shapes where <example> sits inside <remarks>/<since>/... keep
  // behaving exactly as they did before.
  for I:= 0 to High(Spans) do
    if Spans[I].IsExample
       and (Pos(#10, Copy(Joined, Spans[I].Lo, Spans[I].Hi - Spans[I].Lo + 1)) > 0) then
    begin
      var Nested: Boolean:= False;
      for J:= 0 to High(Spans) do
        if (J <> I) and (Spans[J].Lo <= Spans[I].Lo) and (Spans[I].Hi <= Spans[J].Hi) then
        begin
          Nested:= True;
          Break;
        end;
      if not Nested then Spans[I].Dropped:= True;
    end;

  // Fixed-point closure. Retracting a span can leave a line that was accounted
  // only BECAUSE of it newly residual, which can in turn retract further
  // spans; the loop is monotone (spans are only ever dropped, residual lines
  // only ever added), so it terminates in at most Length(Spans) rounds.
  SetLength(Accounted, Length(Joined) + 1);
  SetLength(Residual , Length(RawLines));
  repeat
    for J:= 1 to Length(Joined) do Accounted[J]:= False;
    for I:= 0 to High(Spans) do
      if not Spans[I].Dropped then
        for J:= Spans[I].Lo to Spans[I].Hi do Accounted[J]:= True;

    for I:= 0 to High(RawLines) do
    begin
      Residual[I]:= False;
      if InFence[I] then Continue; // engine-generated, re-derived: never author content
      for J:= LineLo[I] to LineHi[I] do
        if (not Accounted[J]) and (Joined[J] > ' ') then
        begin
          Residual[I]:= True;
          Break;
        end;
    end;

    Changed:= False;
    for I:= 0 to High(Spans) do
      if not Spans[I].Dropped then
        for K:= 0 to High(RawLines) do
          if Residual[K] and (Spans[I].Lo <= LineHi[K]) and (LineLo[K] <= Spans[I].Hi) then
          begin
            // v(ADP3 T3f review, IMPORTANT 2 and 3): a span whose content the
            // engine regenerates cannot be handed back. There is no third
            // option here -- emitting the line verbatim WITHOUT retracting the
            // span duplicates the tag (measured: two <returns>, one
            // permanently stale), and retracting it freezes engine content.
            // So the whole carry-through aborts and the region falls back to
            // the pre-v(ADP3 T3f) behaviour, which drops the unmodeled text on
            // that line. That is a real, disclosed non-improvement for this
            // shape, chosen deliberately over a malformed comment carrying a
            // fact the engine has silently stopped maintaining.
            if Spans[I].NonRetractable then Exit;
            Spans[I].Dropped:= True;
            Changed:= True;
            Break;
          end;
  until not Changed;

  ResCount:= 0;
  for I:= 0 to High(RawLines) do if Residual[I] then Inc(ResCount);
  if ResCount = 0 then Exit; // nothing unrepresented: caller stays on the pre-v(ADP3 T3f) path

  SetLength(AResidualLines, ResCount);
  K    := 0;
  First:= True;
  Sb   := TStringBuilder.Create;
  try
    for I:= 0 to High(RawLines) do
      if Residual[I] then
      begin
        // Right-trimmed only: leading whitespace IS the indentation this
        // whole mechanism exists to preserve. Trailing whitespace would
        // otherwise be written back into the source, and (being idempotent
        // to remove) costs nothing to drop.
        AResidualLines[K]:= TrimRight(RawLines[I]);
        Inc(K);
      end
      else
      begin
        if not First then Sb.Append(sLineBreak);
        Sb.Append(RawLines[I]);
        First:= False;
      end;
    AAccountedRaw:= Sb.ToString;
  finally
    Sb.Free;
  end;
  Result:= True;
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
    // v(ADP3 T3f): FIRST, split the region into the lines this function can
    // fully account for and the ones it cannot (SplitResidualLines -- see its
    // own remarks for the line-level-ownership rule and why splitting a MIXED
    // line by characters instead was rejected). Everything downstream then
    // reads Eff, the unstripped parse of the ACCOUNTED lines, in place of
    // AExisting.
    //
    // This does NOT disturb the presence/content split; it re-bases it. The
    // rule was, and remains: PRESENCE from a filtered view (BuildStandaloneFor,
    // which answers "is this tag genuinely standalone, or merely nested inside
    // another container"), CONTENT from the unstripped parse of the same text.
    // Eff IS that unstripped parse -- of the region the engine owns. Reading
    // content from AExisting instead, while gating presence off Eff, would
    // reintroduce the very class of bug this file has been fixing since round
    // 2: with two <since> tags, one on a residual line and one accounted,
    // AExisting.SinceText is the RESIDUAL one's text (RxSinceTag is a singular
    // .Match, first occurrence wins), so the emitter would write out the
    // residual tag's text at the <since> slot AND emit the residual line
    // carrying it verbatim -- a duplication, from exactly the sort of
    // mismatched pair of views that deleted whole comments before.
    //
    // INERT BY CONSTRUCTION when there is nothing residual: SplitResidualLines
    // returns False, Eff stays AExisting byte-for-byte (never a re-parse), and
    // every line below runs on precisely the value it ran on before this
    // change. Gated on AExistingHasAnyTag so the fresh path pays nothing, and
    // on dfXmlDoc because Eff is rebuilt with ParseXmlDoc specifically --
    // TDocCommentParser.Dispatch routes a malformed or tagless /// region to
    // ParseOneline/ParseLoose instead, and re-parsing one of those as XML
    // would change its meaning wholesale.
    var Eff: TParsedDoc:= AExisting;
    var Residual: TArray<string>:= nil;
    if AExistingHasAnyTag and (AExisting.Format = dfXmlDoc) then
    begin
      var AccountedRaw: string;
      if SplitResidualLines(AExisting.RawBlock, AccountedRaw, Residual) then
        Eff:= TDocCommentParser.ParseXmlDoc(AccountedRaw);
    end;
    // Residual lines are re-emitted with the comment marker ONLY -- never
    // APrefix's trailing space -- because the scanner strips exactly the three
    // slashes and leaves everything after them, the leading space included. So
    // '///' + ' <example>' reproduces '/// <example>' and '///' + '   Foo;'
    // reproduces '///   Foo;', both byte-exact, which is what makes the
    // carry-through a fixed point instead of a slow re-indent on every run.
    var LinePrefix: string:= TrimRight(APrefix);

    // v(ADP3 T3b review, Critical 1 fix; round 2 -- STILL-OPEN GAP CLOSED;
    // round 3 -- STRUCTURAL 1, moved to the TOP of the function and expanded
    // to all eight containers): every container in PRESERVED_VERBATIM_
    // CONTAINERS (<summary>/<param>/<returns>/<remarks>/<exception>/
    // <example>/<deprecated>/<since>) is preserved verbatim below (its own
    // raw text, unparsed) -- but AExisting's fields for ALL of them come from
    // regexes that match ANYWHERE in the raw block, so a tag genuinely
    // nested inside ONE of the eight can ALSO be captured as if it were a
    // second, separate, standalone sibling and re-emitted a second time.
    // Round 2 wired this protection into only FOUR of the eight emission
    // sites (exception/example/deprecated/since); STRUCTURAL 1 (round 3)
    // found the other four (summary/param/returns/remarks) still read
    // AExisting directly, unconditionally, so e.g. a <summary> nested inside
    // <exception>'s own desc still fabricated a standalone sibling
    // (reproduced: '<exception cref="E1">exc text <summary>nested summary
    // </summary> tail</exception>' emitted a standalone '<summary>nested
    // summary</summary>' in addition to the exception's own, unmangled,
    // verbatim desc). Moved here (was previously computed just before the
    // <deprecated/> emission, deep in this function) because
    // ReturnsHandWritten, just below, now needs StandaloneReturns before it
    // is computed -- Object Pascal has no forward-reference problem with
    // this (it is one flat function body), but the OLD position textually
    // preceded ReturnsHandWritten's own USE two hundred lines apart, which
    // made the dependency easy to miss; now they are adjacent.
    //
    // A SINGLE shared "Standalone" cannot be correct for more than one field
    // at once: stripping <exception> before reading Standalone.Exceptions
    // would erase every exception, genuinely standalone ones included --
    // exactly the content this is trying to recover. BuildStandaloneFor (see
    // its own remarks) is called ONCE PER FIELD, each time excluding that
    // field's own container from the strip list -- so a tag nested inside
    // any OTHER preserved container never survives to be (re-)captured,
    // while a field's own genuinely top-level occurrences always do (their
    // container was never stripped for their own computation). Gated on
    // AExisting.Format = dfXmlDoc (the eight containers are XML-DocInsight
    // syntax; PasDoc's own @tag recognition is anchored to the START of a
    // trimmed line -- RxTag's own '(?m)^\s*@(\w+)' -- so it has no
    // equivalent match-anywhere nesting risk).
    //
    // v(ADP3 T3b review round 3, STRUCTURAL 1): HasAnySignal's OR-chain is
    // UNCHANGED from round 2 -- it still tests only the four "rich-body"
    // containers (exception/example/deprecated/since) plus seealso, NOT
    // summary/param/returns/remarks themselves. This is deliberate, not an
    // oversight: nesting REQUIRES an outer container and a distinct inner
    // one, so a <summary>/<param>/<returns>/<remarks> can only be
    // fabricated from something nested INSIDE one of these five -- if NONE
    // of them are present, there is nothing for any of the four "plain"
    // fields to be nested inside (short of nesting inside EACH OTHER --
    // <summary> inside <param>, say -- which every one of the review's own
    // reproductions leaves untested, and which this fix does NOT protect
    // against; disclosed as a bounded residual in this task's report).
    // Reusing this same narrow gate for the four NEW fields keeps the
    // expensive path exactly as rare as round 2 left it: a plain,
    // thoroughly-documented function (<summary>+<param>s+<returns>+a
    // <remarks> facts block, no exotic tag at all) is the overwhelming
    // common case in any real codebase, and must NOT pay for nine extra
    // ParseXmlDoc calls on every single one of them -- it still does not,
    // here, since HasAnySignal stays False for exactly that shape, same as
    // before this round.
    //
    // v(ADP3 T3b review round 4, MINOR): AExistingHasAnyTag is now the FIRST
    // conjunct. Round 3 moved this block to the top of the function (it has
    // to be here: ReturnsHandWritten, just below, needs StandaloneReturns) --
    // which also moved it ABOVE the fresh path's own Exit, so nine
    // BuildStandaloneFor calls (nine ParseXmlDoc parses plus their ~63
    // StripElement regex constructions) ran on every FRESH comment and were
    // then discarded unread. Verified behaviour-neutral by reading every
    // Standalone* use in this function: the ONLY one textually before the
    // fresh path's Exit is ReturnsHandWritten's own
    // "AExistingHasAnyTag and StandaloneReturns.HasReturnsTag", whose value is
    // already False whenever AExistingHasAnyTag is False regardless of what
    // StandaloneReturns holds (and IncludeReturns/RenderFactsBlock derive from
    // it, so they are unaffected too); every other read -- <summary>,
    // <deprecated>, both <param> loops, <exception>, <example>,
    // <seealso>/<see>, <since>, <remarks> -- sits AFTER that Exit, on the
    // repair path, where AExistingHasAnyTag is True by construction and this
    // conjunct is therefore always satisfied. A revert-to-RED check is
    // impossible for this one BY CONSTRUCTION (a behaviour-neutral change has
    // no failing state to revert to); it is evidenced instead by the whole
    // idempotency sweep producing byte-identical md5s before and after.
    var HasAnySignal: Boolean:=
      AExistingHasAnyTag and
      (Eff.Format = dfXmlDoc) and
      ((Length(Eff.Exceptions) > 0) or Eff.HasExampleTag or
       (Length(Eff.SeeAlso) > 0) or Eff.HasSinceTag or Eff.Deprecated);
    var StandaloneExc     : TParsedDoc;
    var StandaloneExample : TParsedDoc;
    var StandaloneDep     : TParsedDoc;
    var StandaloneSee     : TParsedDoc;
    var StandaloneSince   : TParsedDoc;
    // v(ADP3 T3b review round 3, STRUCTURAL 1): the four fields round 2 left
    // unprotected -- see each one's own emission site, below, for how its
    // presence gate now reads from these instead of from AExisting directly.
    var StandaloneSummary : TParsedDoc;
    var StandaloneParam   : TParsedDoc;
    var StandaloneReturns : TParsedDoc;
    var StandaloneRemarks : TParsedDoc;
    if HasAnySignal then
    begin
      // v(ADP3 T3f): every one of these nine reads Eff.RawBlock, the ACCOUNTED
      // lines -- not AExisting.RawBlock. A tag sitting on a residual line is
      // therefore invisible to the presence views too, which is what keeps the
      // verbatim line the sole emitter of that tag (see the Eff computation at
      // the top of this function). Eff.RawBlock IS AExisting.RawBlock whenever
      // nothing is residual.
      StandaloneExc     := BuildStandaloneFor(Eff.RawBlock, 'exception');
      StandaloneExample := BuildStandaloneFor(Eff.RawBlock, 'example');
      StandaloneDep     := BuildStandaloneFor(Eff.RawBlock, 'deprecated');
      // seealso/see never need self-exclusion (StripElement can never match
      // their always-self-closing form -- see PRESERVED_VERBATIM_CONTAINERS'
      // own comment), so '' (strip everything) is correct and simplest.
      StandaloneSee     := BuildStandaloneFor(Eff.RawBlock, '');
      StandaloneSince   := BuildStandaloneFor(Eff.RawBlock, 'since');
      StandaloneSummary := BuildStandaloneFor(Eff.RawBlock, 'summary');
      StandaloneParam   := BuildStandaloneFor(Eff.RawBlock, 'param');
      StandaloneReturns := BuildStandaloneFor(Eff.RawBlock, 'returns');
      StandaloneRemarks := BuildStandaloneFor(Eff.RawBlock, 'remarks');
    end
    else
    begin
      StandaloneExc     := Eff;
      StandaloneExample := Eff;
      StandaloneDep     := Eff;
      StandaloneSee     := Eff;
      StandaloneSince   := Eff;
      StandaloneSummary := Eff;
      StandaloneParam   := Eff;
      StandaloneReturns := Eff;
      StandaloneRemarks := Eff;
    end;

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
    // v(ADP3 T3b review round 3, STRUCTURAL 1): reads StandaloneReturns.
    // HasReturnsTag, not AExisting.HasReturnsTag -- a <returns> genuinely
    // nested inside e.g. <deprecated>'s own text (reproduced: '<deprecated>
    // dep <returns>nested returns text</returns> tail</deprecated>') must
    // not ALSO be treated as this symbol's own hand-written returns tag.
    var ReturnsHandWritten: Boolean:=
      AExistingHasAnyTag and StandaloneReturns.HasReturnsTag
      and (not IsEngineOwnedRegardlessOfContent(Eff.ReturnsText));
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
    // v(ADP3 T3b review round 3, STRUCTURAL 1): reads StandaloneSummary.
    // HasSummaryTag, not AExisting.HasSummaryTag -- a <summary> genuinely
    // nested inside e.g. <exception>'s own desc (reproduced: '<exception
    // cref="E1">exc text <summary>nested summary</summary> tail</exception>')
    // must not ALSO be treated as this symbol's own hand-written summary.
    // Content (SummaryRaw) still reads AExisting.Summary, not
    // StandaloneSummary.Summary: computing StandaloneSummary strips
    // <exception>/<example>/<deprecated>/<since> from the WHOLE block, which
    // would ALSO strip anything legitimately nested INSIDE a genuinely
    // standalone summary's own prose (e.g. NestedTagsInSummary's inline
    // <exception cref> -- see that fixture's own comment) -- HasSummaryTag
    // only needs to answer "is there a genuine, standalone summary at all",
    // never "what does it say".
    var SummaryRaw: string:= Eff.Summary;
    if StandaloneSummary.HasSummaryTag and (not IsEngineOwnedRegardlessOfContent(SummaryRaw)) then
      Sb.AppendLine(EmitTagged('<summary>', SummaryRaw, '</summary>'))
    else if AFacts.HarvestedSummary <> '' then
      Sb.AppendLine(EmitTagged('<summary>' + AUTO_MARK, AFacts.HarvestedSummary, '</summary>'));
    // else: engine-owned-and-empty, or genuinely absent, and nothing
    // harvested -- omit the tag entirely (v(ADP3 T3)).

    // <deprecated/>: v(ADP3 T3b; review Important 2 -- message preserved).
    // Fixed order (see this function's own header remarks): <summary> ->
    // <deprecated/> -> <param>s -> <returns> -> <exception>s -> <example> ->
    // <seealso>s -> <since> -> <remarks>. Never engine-owned -- MergeComment
    // has never generated this XML tag (the ground-truth 'Deprecated: msg'/
    // 'Deprecated.' PLAIN-TEXT fact line inside the AUTO_BEGIN..AUTO_END
    // fence is a DIFFERENT thing: the Pascal `deprecated` directive, not
    // this doc-comment tag -- see RenderFactsBlock's own comment), so there
    // is nothing to classify: whenever a human wrote it, it is preserved;
    // nothing ever refills it, same as <param>. A message is re-emitted
    // verbatim (no re-escaping -- opaque hand-written XML text, same
    // reasoning as <exception>/<example> below); a bare tag has no
    // message-text spelling to preserve regardless (self-closing vs. an
    // explicit close tag with empty content both collapse to '', so the
    // canonical bare '<deprecated/>' is emitted either way).
    //
    // v(ADP3 T3b review round 2, Critical 1 -- SECOND bug found while fixing
    // the first): StandaloneDep is used ONLY to decide WHETHER a <deprecated>
    // is genuinely standalone (not nested inside something else) -- its OWN
    // DeprecatedText must NEVER be read for the actual message, because
    // BuildStandaloneFor('deprecated') strips example/exception/since FROM
    // THE WHOLE RAW BLOCK, including from WITHIN this <deprecated>'s own
    // body -- a message that legitimately contains e.g. "<see cref=.../>...
    // <since>2.0</since>" would have that '<since>' silently deleted, not
    // merely excluded from double-counting (reproduced empirically: without
    // this fix, "Added in <since>2.0</since> and still valid." mangled down
    // to "Added in  and still valid."). AExisting.DeprecatedText -- the
    // ORIGINAL, entirely unstripped parse -- is always the correct source
    // for the message text; only presence/absence needs the filtered view.
    if StandaloneDep.Deprecated then
    begin
      if Eff.DeprecatedText <> '' then
        Sb.AppendLine(EmitTagged('<deprecated>', Eff.DeprecatedText, '</deprecated>'))
      else
        Sb.AppendLine(APrefix + '<deprecated/>');
    end;

    // <param>: v(ADP3 T3 review round 2, Finding 1 -- the ONE tag where
    // marked+content is preserved rather than treated as engine-owned; see
    // ClassifyParamAction's own comment for why params differ from
    // summary/returns.
    // v(ADP3 T3b review round 3, STRUCTURAL 1): presence now DOES need a
    // separate check -- a matching EP existing in AExisting.Params is no
    // longer sufficient proof of standalone presence, since AExisting.Params
    // also captures a <param name="X"> genuinely nested inside e.g.
    // <example>'s own body (reproduced: '<example>Ex <param name="AV">
    // nested param desc</param> body.</example>' fabricated a standalone
    // '<param name="AV">nested param desc</param>' for a signature parameter
    // named AV, even though the author never wrote a top-level <param> for
    // it at all). A matching entry must ALSO exist in StandaloneParam.Params
    // (built by stripping every OTHER preserved container first) before this
    // is treated as hand-written. Content (EP.Desc) still comes from
    // AExisting -- the correlation is by NAME (params have a natural key,
    // same pattern as <exception>'s cref-based correlation below), so there
    // is no risk of reading the wrong occurrence's text the way an unkeyed,
    // single-match field would have.
    // existing params first, in signature order where possible
    for P in ASigParams do
    begin
      for var EP in Eff.Params do
        if SameText(EP.Name, P) then
        begin
          var IsStandaloneParam: Boolean:= False;
          for var SP in StandaloneParam.Params do
            if SameText(SP.Name, P) then begin IsStandaloneParam:= True; Break; end;
          if IsStandaloneParam then
          begin
            case ClassifyParamAction(EP.Desc, True) of
              taPreserveStripped: Sb.AppendLine(EmitTagged('<param name="' + P + '">', StripMark(EP.Desc), '</param>'));
              taPreserveVerbatim: Sb.AppendLine(EmitTagged('<param name="' + P + '">', EP.Desc, '</param>'));
              taEngineOwned: ; // no harvester for params -- always drop, never regenerate
            end;
          end;
          Break;
        end;
      // If no EP matched P at all (the inner loop found nothing), or the
      // match was not genuinely standalone: no <param> tag exists for this
      // sig param -- nothing hand-written to preserve and no harvester to
      // fill it, so nothing is emitted for it either (v(ADP3 T3): fresh/
      // missing params never get a skeleton).
    end;
    // stale hand-typed params: in the comment but not the signature -> flag, keep.
    // v(ADP3 T3b review round 3, STRUCTURAL 1): same standalone-presence
    // check as the loop above -- a nested-elsewhere <param> for a name that
    // does not even match a current signature parameter must not be flagged
    // as a "stale" leftover either (same fabrication risk, for a name with
    // no real sig-param counterpart at all).
    for var EP in Eff.Params do
    begin
      var StillThere: Boolean:= False;
      for P in ASigParams do if SameText(EP.Name, P) then begin StillThere:= True; Break; end;
      var IsStandaloneParam: Boolean:= False;
      for var SP in StandaloneParam.Params do
        if SameText(SP.Name, EP.Name) then begin IsStandaloneParam:= True; Break; end;
      if (not StillThere) and (not IsManagedDesc(EP.Desc)) and IsStandaloneParam then
        Sb.AppendLine(EmitTagged('<param name="' + EP.Name + '">', EP.Desc, '</param> <!-- drag-lint: param no longer exists -->'));
    end;

    if AHasReturn then
    begin
      if ReturnsHandWritten then
        // hand-written, including a deliberate blank slot -- preserved
        // verbatim; its mined cases (if any) went into the 'Returns:' fact
        // line above (IncludeReturns) instead of disturbing this text.
        Sb.AppendLine(EmitTagged('<returns>', Eff.ReturnsText, '</returns>'))
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

    // <exception>: v(ADP3 T3b). Never engine-owned -- MergeComment has never
    // generated this tag, so, like <param> and <deprecated/>, there is
    // nothing to classify: every <exception> found is hand-written,
    // preserved verbatim (mirrors the <param> loop's shape above). TypeName
    // (the cref) and Desc are re-emitted EXACTLY as parsed, with NO
    // re-escaping: they were captured raw out of already-valid XML text (the
    // author's own source), so they are opaque strings to round-trip, not
    // fresh content to escape -- exactly like Desc in the <param> loop above
    // and SummaryRaw/AExisting.ReturnsText below. Escaping them again here
    // would double-escape any entity the author's text already carries
    // (e.g. a hand-written '&amp;' would become '&amp;amp;') and would not
    // be idempotent -- EscXml/EscXmlAttr are reserved in this function for
    // MINED content only (RenderFactsBlock/ObservedSuffix), never for a
    // verbatim hand-written passthrough. Multiple <exception> tags keep
    // their relative SOURCE order (Excs is populated in regex-match order
    // by the parser; the parser does not track cross-TYPE tag order, hence
    // this function's fixed emission order -- see its own header remarks).
    //
    // v(ADP3 T3b review round 2, Critical 1 -- SECOND bug, same class as
    // <deprecated>'s own fix just above): StandaloneExc.Exceptions is used
    // ONLY to determine WHICH cref values are genuinely standalone (not
    // nested inside example/deprecated/summary/etc.) -- its OWN Desc text
    // must NOT be re-emitted directly, because BuildStandaloneFor
    // ('exception') strips example/deprecated/since from the WHOLE raw
    // block, including from WITHIN this exception's own desc (reproduced:
    // "Added in <since>2.0</since> and still valid." mangled down to
    // "Added in  and still valid." before this fix). For each standalone
    // cref, look up the MATCHING entry in AExisting.Exceptions (the
    // ORIGINAL, entirely unstripped parse) by TypeName, and re-emit ITS
    // Desc -- unmangled, whatever it contains. (Two <exception> tags
    // sharing the identical cref is the one case this cannot disambiguate;
    // out of scope, same as the pre-existing "keeps only the first
    // <deprecated>/<since>" limitation.)
    for var StandaloneExcItem in StandaloneExc.Exceptions do
      for var OrigExc in Eff.Exceptions do
        if SameText(OrigExc.TypeName, StandaloneExcItem.TypeName) then
        begin
          Sb.AppendLine(EmitTagged('<exception cref="' + OrigExc.TypeName + '">', OrigExc.Desc, '</exception>'));
          Break;
        end;

    // <example>: v(ADP3 T3b; review Minor 1 -- gated on HasExampleTag, not
    // ExampleText <> '', so a deliberate, empty <example></example> is
    // preserved rather than silently dropped -- consistent with <summary>'s
    // own HasSummaryTag gate, and required for the strip round-trip to be
    // byte-exact on that shape). Same reasoning as <exception> -- never
    // engine-owned, always hand-written when present, preserved verbatim
    // (no re-escaping, see above).
    //
    // v(ADP3 T3b review round 2, Critical 1 -- same "presence vs. content"
    // split as <deprecated>/<exception> above): StandaloneExample.
    // HasExampleTag decides WHETHER this is genuinely standalone; the TEXT
    // always comes from AExisting.ExampleText (the original, unmangled
    // parse), never from StandaloneExample.ExampleText, which could have a
    // legitimately-nested tag (e.g. a nested <exception>) stripped out from
    // within it by BuildStandaloneFor('example')'s own exception/deprecated/
    // since strip.
    if StandaloneExample.HasExampleTag then
      Sb.AppendLine(EmitTagged('<example>', Eff.ExampleText, '</example>'));

    // <seealso>/<since>: v(ADP3 T3b) -- UNLIKE exception/example/deprecated,
    // these two DO have an engine-generated counterpart: RenderFactsBlock
    // emits an opt-in auto '<seealso cref=.../>' per related symbol and an
    // opt-in auto '<since>date</since>' fact, both INSIDE the AUTO_BEGIN..
    // AUTO_END fence (see its own comment) when the caller opted in via
    // --seealso/--since. StandaloneSee's/StandaloneSince's own strip
    // (BuildStandaloneFor, above) removes the <remarks> element wholesale,
    // which is where the fence always lives, so an auto-generated line from
    // a PRIOR run is excluded the same way any other remarks-nested content
    // is (the Task 3b brief's own "Trap 1", confirmed empirically before
    // this fix).
    //
    // v(ADP3 T3b review, Critical 1 fix, second symptom): RxSee's own
    // '(?:see|seealso)' alternation means SeeAlso conflates a hand-written
    // bare '<see cref="X"/>' (an inline cross-reference) with '<seealso
    // cref="X"/>' (a separate, top-level "also see" entry) -- two DIFFERENT
    // DocInsight tags that render differently. Re-emitting every entry as
    // '<seealso ...>' would silently rewrite an author's '<see>' into a
    // '<seealso>' -- a destruction (the '<see>' is gone) AND a fabrication
    // (a '<seealso>' the author never wrote appears), both violating
    // "preserve verbatim, never fabricate". SeeAlsoIsInline (parallel to
    // SeeAlso, same index correspondence, set by the parser -- see
    // TParsedDoc's own field comment) records which spelling the author
    // actually used, so the ORIGINAL tag name is what gets re-emitted.
    //
    // v(ADP3 T3b review round 2, Minor): FAIL LOUDLY on a length mismatch
    // rather than silently defaulting every out-of-range entry to
    // '<seealso>' (a silent default is exactly how the very rewrite this
    // field exists to prevent could reappear unnoticed -- e.g. a future
    // producer that fills SeeAlso without ALSO filling SeeAlsoIsInline, such
    // as a rehydrate from SeeAlsoJsonRaw). Both current producers
    // (ParseXmlDoc, ParsePasDoc) always size them equal, so this can only
    // fire if a THIRD producer is added later without updating this
    // invariant -- exactly the case worth a loud, immediate failure over a
    // silently-wrong tag name.
    if Length(StandaloneSee.SeeAlso) <> Length(StandaloneSee.SeeAlsoIsInline) then
      raise Exception.CreateFmt(
        'TDocRegions.MergeComment: SeeAlso/SeeAlsoIsInline length mismatch (%d vs %d) -- ' +
        'every TParsedDoc producer must size SeeAlsoIsInline to match SeeAlso.',
        [Length(StandaloneSee.SeeAlso), Length(StandaloneSee.SeeAlsoIsInline)]);
    for var SeeIx:= 0 to High(StandaloneSee.SeeAlso) do
    begin
      var SeeTag: string:= 'seealso';
      if StandaloneSee.SeeAlsoIsInline[SeeIx] then SeeTag:= 'see';
      Sb.AppendLine(APrefix + '<' + SeeTag + ' cref="' + StandaloneSee.SeeAlso[SeeIx] + '"/>');
    end;
    // v(ADP3 T3b review round 3, NEW IMPORTANT): reads StandaloneSince.
    // HasSinceTag for PRESENCE (not the old SinceText <> '' content test,
    // and NOT StandaloneSince.SinceText for the actual text). The old
    // content-test gate was doubly wrong: (1) SinceText <> '' cannot tell
    // "no <since> at all" apart from a human's deliberate, empty
    // <since></since> -- the same presence-vs-content gap HasSummaryTag/
    // HasReturnsTag/HasExampleTag/HasRemarksTag already closed for their own
    // tags; (2) far worse, reading the CONTENT from StandaloneSince (built by
    // stripping <exception>/<example>/<deprecated>/<summary>/etc. from the
    // WHOLE block) silently deleted anything legitimately nested inside a
    // genuinely standalone <since>'s own body -- reproduced: '<since>1.0
    // <exception cref="EInSince">x</exception></since>' emitted only
    // '<since>1.0</since>', and '<since>2.0 <example>see the sample below
    // </example> onwards</since>' emitted '<since>2.0 onwards</since>' (the
    // nested tag's own text silently gone, not merely excluded from
    // double-counting). The WORST shape combined this with <deprecated>'s
    // OWN self-exclusion: '<since><deprecated>2.0-beta</deprecated></since>'
    // deleted the ENTIRE hand-written comment, because StandaloneSince
    // strips 'deprecated' (so SinceText became '', failing the old gate) AND
    // StandaloneDep strips 'since' (so Deprecated became False, failing
    // ITS gate) -- both tags vanished simultaneously, worse than round 1's
    // duplication and round 2's line-deletion defect, both of which at
    // least left something behind. AExisting.SinceText (the ORIGINAL,
    // entirely unstripped parse) is always the correct source for the text,
    // exactly like DeprecatedText/exception Desc/ExampleText above; only
    // presence/absence needed the filtered view.
    if StandaloneSince.HasSinceTag then
      Sb.AppendLine(EmitTagged('<since>', Eff.SinceText, '</since>'));

    // v(ADP3 T3f): the carried-through residual -- every line of the original
    // region this function could not fully account for, verbatim, in source
    // order, re-prefixed with LinePrefix -- the comment marker WITHOUT
    // APrefix's trailing space, so the INTERIOR indentation the scanner left
    // after the slashes survives byte-exact (see LinePrefix, above).
    // v(ADP3 T3g): APrefix now carries the declaration's own indentation, so
    // LinePrefix is that indentation plus the marker, not a bare marker; the
    // line therefore lands where its indented siblings do while everything the
    // scanner handed back is still reproduced character for character.
    //
    // Position: AFTER every modeled tag, BEFORE the <remarks> facts block.
    // The engine's own fixed emission order already reorders modeled tags
    // relative to the source, so "the author's original relative position"
    // is not on offer for anything here -- what IS load-bearing is that the
    // position be DERIVED (so it is the same on every run, hence a fixed
    // point) and that it not be FIRST. Emitting residual prose ahead of every
    // tag would put it before the first '<' in the region, where ParseXmlDoc's
    // untagged-prefix fallback would adopt it as the summary on the NEXT run
    // and re-emit it inside a <summary> the author never wrote -- a
    // fabrication AND a non-idempotent one. Keeping the facts block last also
    // preserves the convention every other shape in this codebase already
    // follows.
    var LenBeforeResidual: Integer:= Sb.Length;
    for var ResidualLine in Residual do
      Sb.AppendLine(LinePrefix + ResidualLine);
    var LenAfterResidual: Integer:= Sb.Length;

    // remarks: keep hand prose (AExisting.Remarks) OUTSIDE the fence, then a fresh
    // managed block. Strip any old fenced block from the prose before re-emitting
    // so a second run does not nest blocks.
    // v(ADP3 T3b review round 3, STRUCTURAL 1): only reads AExisting.Remarks
    // when StandaloneRemarks.HasRemarksTag confirms a genuinely standalone
    // <remarks> exists -- a <remarks> nested inside e.g. <example>'s own
    // body (reproduced: '<example>ex <remarks>nested remarks</remarks> tail
    // </example>') used to become the engine's real remarks prose, with the
    // facts fence wrongly attaching to it. When not standalone, Prose stays
    // '' regardless of what AExisting.Remarks captured -- there is nothing
    // genuine to preserve from a fabricated match, so (unlike summary/
    // returns/since/param above) there is no unstripped content to read
    // instead; the whole point is that this text was never the author's
    // real remarks prose to begin with.
    var Prose: string:= '';
    if StandaloneRemarks.HasRemarksTag then
      Prose:= StripManagedBlock(Eff.Remarks);
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
    // v(ADP3 T3f): carried-through residual ALONE is not output. When the
    // engine modeled nothing and generated nothing, the only thing it could
    // write is a copy of lines that are already sitting in the file -- so it
    // writes NOTHING instead, reports Merged='' to BuildForSymbol, and the
    // region is left exactly as the author has it. That is strictly more
    // conservative than rewriting it (no reordering, no dropped engine-owned
    // empty tag, no delete+insert at all), and it keeps the Merged='' branch's
    // own RegionFullyEngineOwned guard reachable and exercised by the fixture
    // that covers it (unhandledtags.HasValueTag) instead of quietly bypassing
    // it. Identical to the pre-v(ADP3 T3f) expression whenever Residual is
    // empty: both conditions then reduce to "Sb is empty", which TrimRight
    // would have returned as '' anyway.
    if (LenBeforeResidual = 0) and (Sb.Length = LenAfterResidual) then
      Result:= ''
    else
      Result:= Sb.ToString.TrimRight([#13, #10]);
  finally
    Sb.Free;
  end;
end;

end.
