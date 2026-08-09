unit DRagLint.Doc.Regions;

// THE PROVENANCE CONTRACT -- this unit's governing invariant (v(ADP3) T1/T15).
//
// Every tag this engine owns carries the marker AUTO_MARK
// (`<!-- drag-lint:auto -->`) immediately after its opening tag, and the facts
// block is fenced by AUTO_BEGIN..AUTO_END. Ownership is decided BY THAT MARKER
// AND BY NOTHING ELSE:
//
//   * A tag WITHOUT the marker belongs to the human. It is preserved verbatim
//     -- its text, its whitespace, whatever it says -- and MergeComment must
//     never rewrite, reflow or delete it. A tag this unit does not even model
//     is carried through byte-for-byte (v(ADP3 T3f)/T9).
//   * A tag WITH the marker is engine-owned and its contents are regenerated on
//     every run, regardless of what now sits between the markers.
//   * Ownership changes hands ONLY by REMOVING the marker. It never changes by
//     the engine sniffing content -- the pre-v(ADP3) StartsText('Observed:')
//     sniff, which silently adopted any human sentence beginning that way, was
//     deleted in T1 and must not come back in any form. An exact-string compare
//     against generated text is the same mistake by the back door.
//
// The consequence, stated rather than hidden: a human edit made INSIDE a marked
// tag is overwritten on the next run. It has to be -- "a human edited inside
// the markers" and "the source comment this was harvested from changed" are the
// same string comparison, so both refresh. What the engine owes in exchange is
// VISIBILITY, not silence: Doc.Drift's ddHarvestDrift reports the overwrite,
// naming the symbol and both texts. Documented for users in docs/AI-USAGE.md.
//
// This contract is also exactly what makes `document --strip` (Doc.Strip) an
// EXACT inverse rather than a heuristic: the marker says what to remove.
//
// One more invariant lives here: FormatPhase2FactLines is the SINGLE home for
// the fact lines of BOTH surfaces, the managed doc block and the hover popup,
// so the two can never show different facts for the same TDocFacts. The order
// of the lines is part of that contract -- appending is safe, inserting in the
// middle rewrites every already-documented block in the corpus.

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
    /// <summary>Body text of the FIRST GENUINELY STANDALONE occurrence of
    /// ATagName in ARawBlock -- read verbatim out of the original text at that
    /// occurrence's own offsets, then normalized exactly as
    /// TDocCommentParser.ParseXmlDoc normalizes that tag. AFallback when there
    /// is no standalone occurrence, or when the one found has an empty
    /// body.</summary>
    /// <param name="ATagName">One of PRESERVED_VERBATIM_CONTAINERS, and one of
    /// the SINGULAR-MATCH ones (a bare &lt;tag&gt; opening form); raises
    /// otherwise. &lt;param&gt;/&lt;exception&gt; are refused deliberately -- their
    /// opening tag carries the attribute holding their natural key, so it is not
    /// fixed-length and the body arithmetic here would read past it.</param>
    /// <param name="AFallback">What to return when this function cannot improve
    /// on the caller's own value -- always the caller's corresponding
    /// TParsedDoc field, so the result is byte-identical to the pre-v(ADP3 T3h)
    /// behaviour on every shape with at most one occurrence.</param>
    /// <returns>The chosen occurrence's normalized body, or AFallback.</returns>
    /// <remarks>v(ADP3 T3h, register N2). The COMPANION to BuildStandaloneFor:
    /// that one answers PRESENCE ("is there a genuine, standalone tag of this
    /// kind at all"), this one answers CONTENT ("and what does THAT occurrence
    /// say"). MergeComment took presence from the filtered view and content from
    /// the unfiltered singular field, so the two could describe DIFFERENT
    /// occurrences -- and a nested look-alike's text was then written out at the
    /// genuine tag's slot, unmarked, where `document --strip` could not remove
    /// it.
    /// A tag OCCURRENCE is identified by its character span in the cleaned text
    /// (TDocCommentParser.BuildCleaned), obtained by masking every OTHER
    /// container LENGTH-PRESERVINGLY instead of deleting it -- see MaskMatches.
    /// "Nested look-alike" versus "genuine sibling" is therefore NOT a new
    /// judgment: it is BuildStandaloneFor's existing one (the same
    /// ContainerLoosePattern spans), now able to report WHERE as well as
    /// WHETHER. Getting that distinction wrong in the permissive direction
    /// destroys author content and in the conservative direction leaves the
    /// defect, so it is deliberately not re-derived here.
    /// NOT a fix for a tag nested inside ANOTHER unkeyed tag (a &lt;returns&gt;
    /// inside a &lt;summary&gt;): MergeComment's HasAnySignal gate leaves the
    /// filtered views switched off for that shape, which is the bounded residual
    /// T3b round 3 disclosed and deliberately did not widen (it would put nine
    /// extra parses on every plainly-documented symbol).</remarks>
    class function StandaloneBodyOf(const ARawBlock, ATagName, AFallback: string): string;
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
    /// <param name="AEngineEmitsOwnRemarks">v(ADP3 T3d, T3f minor 1): True
    /// when the caller will emit its OWN &lt;remarks&gt; element for this symbol
    /// (RenderFactsBlock produces something). Only then is an author
    /// &lt;remarks&gt; span non-retractable on that ground alone -- retracting it
    /// would leave the author's element sitting verbatim beside the engine's.
    /// When the engine will emit none, an unmarked, unfenced author
    /// &lt;remarks&gt; is retractable like any other round-tripped container, so a
    /// tail beside it is preserved instead of dropped. A &lt;remarks&gt; that
    /// carries a fence or a marker stays non-retractable regardless.</param>
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
    /// ParseXmlDoc's own fallback turns into the summary. An AUTO_BEGIN with
    /// no matching AUTO_END FAILS CLOSED and aborts the whole mechanism for
    /// the region (this returns False, so the caller behaves exactly as it did
    /// before v(ADP3 T3f)) -- a region whose engine/author boundary cannot be
    /// established is a statement about the region, not about one line. Lines
    /// inside a well-formed fence are never residual at all: they are
    /// re-derived every run.
    /// v(ADP3 T3d, T3f minor 3): a residual line overlapping a span whose
    /// content the engine REGENERATES no longer aborts the region. That line
    /// alone loses its carry-through (it is forced back to accounted, so its
    /// spans are still emitted exactly once); every OTHER residual line in the
    /// same region still comes back verbatim. A span retracted earlier in the
    /// closure, whose only residual line is then BLOCKED, is not a loss: the
    /// Dropped flag governs the residual partition alone, and AAccountedRaw is
    /// built from the residual flags, so a blocked line is still handed to the
    /// parser and its tag is still emitted.</remarks>
    class function SplitResidualLines(const ARawBlock: string;
      AEngineEmitsOwnRemarks: Boolean;
      out AAccountedRaw: string; out AResidualLines: TArray<string>): Boolean;
  public
    /// <summary>Renders the fenced facts-block body lines (each prefixed
    /// APrefix), from AFacts. Sections: Called from (or Used by, see below) /
    /// Calls / Used in units /
    /// Raises / Deprecated / Overrides / Overridden by / Implements / Overload
    /// k of n / abstract / virtual / Complexity / Reads/Writes fields / Owns
    /// returned / Handles / SQL tables touched / Covered by / Since / SeeAlso.
    /// Empty sections omitted; '' when there are no facts. Displayed
    /// counts below
    /// the true *Total get a ' (+N more)' suffix.
    /// <para>v(ADP3 T4) -- TWO RULES GOVERN THE REFERENCE LINE
    /// (AFacts.CalledFrom), and both are about honesty rather than content.
    /// (1) THE VERB IS KIND-SELECTED, from AFacts.SymbolKind via
    /// DRagLint.Core.Model.CanBeCallTarget: a callable renders 'Called from:',
    /// every other kind renders 'Used by:', because a record/class/interface/
    /// constant is USED, not called -- its entries are type mentions that reach
    /// the list through DRagLint.Doc.Facts' non-routine path. No kind list is
    /// written here; CanBeCallTarget owns that question. (2) THE ' ?'
    /// UNCERTAINTY MARKER IS EMITTED ONLY ON A MIXED LIST. An entry whose
    /// Confidence is neither '' nor 'certain' gets a trailing ' ?' iff the list
    /// ALSO holds at least one certain entry; a uniformly uncertain list renders
    /// plain, exactly as a uniformly certain one does. A marker on every entry
    /// distinguishes nothing, and most lists are uniform (measured: 70.7% of
    /// YADF's caller entries and 85.4% of drag-lint's own carried it). List
    /// CONTENTS, the certain-before-uncertain ordering, the display cap and the
    /// '(+N more)' suffix are unchanged by both rules.</para>
    /// Deprecated is ground-truth
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
    /// <param name="AHasOtherContent">v(ADP3 T13): True when the caller's block
    /// ALREADY carries content from outside this helper (the Phase-1 lines).
    /// Governs the derived &lt;c&gt;Pure&lt;/c&gt; line ONLY: Pure never creates a block of
    /// its own, because a doc block is a file edit and 'Pure' alone is a
    /// statement about the ABSENCE of findings -- see the emit site for the full
    /// reasoning. Defaults True so a read-only surface (hover), which is not
    /// writing anything to disk, keeps showing it.</param>
    class function FormatPhase2FactLines(const AFacts: TDocFacts; AComplexityMin: Integer = 10;
      AHasOtherContent: Boolean = True): TArray<string>;
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
    /// <summary>True when S is engine-owned tag text WITHOUT regard to
    /// emptiness: it carries AUTO_MARK (IsManagedText), or it is the legacy
    /// 'TODO: describe.' sentinel. This is the ownership test for
    /// &lt;summary&gt; and &lt;returns&gt; ONLY -- marked there means engine-owned,
    /// full stop, whatever follows the marker.</summary>
    /// <remarks>Deliberately NOT IsManagedDesc: that one also answers True for
    /// EMPTY text, which is right for a &lt;param&gt; slot and wrong here -- a
    /// human's blank, unmarked &lt;summary&gt;&lt;/summary&gt; is hand-written and
    /// must be preserved verbatim, not adopted.
    ///
    /// v(ADP3 T9): PROMOTED from a nested function inside MergeComment to a
    /// class function, for the same reason IsManagedDesc was promoted in
    /// v(ADP3 T1) -- the Task 9 harvest-drift check in DRagLint.Doc.Drift needs
    /// this EXACT test, and hand-expanding its two arms a second time is how
    /// that unit silently drifted out of sync with MergeComment once already.
    /// One executable home; both callers read it.</remarks>
    class function IsEngineOwnedTagText(const S: string): Boolean;
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
/// idempotent strip-and-regenerate depends.
///
/// v(ADP3 T7): PROMOTED from this unit's implementation section to its
/// interface. The harvester (DRagLint.Doc.Harvest.HarvestText) escapes the prose
/// it promotes out of a hand-written comment, and that prose is arbitrary human
/// text -- far likelier to carry an ampersand or an angle bracket than a mined
/// identifier ever was. One escaper, one behaviour: Doc.Harvest calls THIS
/// rather than carrying a second copy that could drift in its pass order.
/// Doc.Harvest reaches it through its IMPLEMENTATION uses clause, so the
/// dependency cycle this unit's interface would otherwise close
/// (Regions -&gt; Facts -&gt; Harvest -&gt; Regions) never forms.</remarks>
function EscXml(const S: string): string;

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

// v(ADP3 T7): emits AHarvested (harvested prose beyond the first paragraph)
// into an already-open <remarks> element, one APrefix-prefixed line per line,
// with AUTO_MARK on the FIRST line so `document --strip` and the drift check
// can identify exactly these lines as engine-owned. No-op when AHarvested is ''.
//
// ONE emitter for BOTH of MergeComment's paths (fresh and repair). They had
// drifted apart before -- see the residual/prose handling either side of this
// call -- and harvested prose that appeared on only one of them would look like
// a harvester bug rather than a wiring one.
//
// Emitted ABOVE the AUTO_BEGIN fence by both callers, never inside it: the
// fence's contents are regenerated wholesale on every run, so prose placed
// inside would be destroyed by the next regeneration.
//
// Every line carries APrefix, never a bare embedded newline -- the 5ebde68
// corruption was exactly an unprefixed interior line turning the rest of a doc
// block into code.
procedure EmitHarvestedRemarks(ASb: TStringBuilder; const APrefix, AHarvested: string);
var
  Norm : string        ;
  Parts: TArray<string>;
  i    : Integer       ;
begin
  if AHarvested = '' then Exit;
  Norm := StringReplace(AHarvested, #13#10, #10, [rfReplaceAll]);
  Norm := StringReplace(Norm, #13, #10, [rfReplaceAll]);
  Parts:= Norm.Split([#10]);
  for i:= 0 to High(Parts) do
    if i = 0 then ASb.AppendLine(APrefix + AUTO_MARK + Trim(Parts[i]))
    else ASb.AppendLine((APrefix + Trim(Parts[i])).TrimRight);
end;

// v(PHASE A1, ruling D-1): drops from AHarvested every line whose text is
// ALREADY present in APresent, so a re-run cannot accumulate the same prose
// twice. Returns what is left, or '' when everything was a duplicate.
//
// THE DUPLICATION IS REAL AND IT IS THE OWNERSHIP HANDOVER. Marked lines are
// engine-owned and regenerated; ownership passes to a human by DELETING the
// marker (v(ADP3 T3)), after which MergeComment preserves the line as hand
// prose. But the harvest is recomputed from a SOURCE comment that is still
// sitting in the file, so EmitHarvestedRemarks re-emits its own copy beneath
// the human's -- and the paragraph appears twice, for good, with no marker on
// the first copy for `--strip` to find. The truncate-at-first-marker rule below
// cannot see this: by then the line no longer carries a marker.
//
// Ruling D-1 is what this implements -- "textually compare and delete identical
// phrases so the summary does not explode on re-runs" -- and it is deliberately
// TEXTUAL and deliberately EXACT. Comparison is on whitespace-collapsed,
// case-folded text; a paraphrase is NOT a duplicate, because dropping prose a
// human might have edited on purpose would be a silent destruction of their
// words. Only a line the reader would see twice is removed.
function DropAlreadyPresentPhrases(const AHarvested, APresent: string): string;

  // Whitespace-collapsed, case-folded view. One reader per side, so the two
  // cannot normalise differently.
  function Norm(const S: string): string;
  var
    i   : Integer       ;
    Prev: Boolean       ;
    Sb  : TStringBuilder;
  begin
    Sb:= TStringBuilder.Create;
    try
      Prev:= False;
      for i:= 1 to Length(S) do
        if CharInSet(S[i], [' ', #9, #10, #13]) then
        begin
          if not Prev then Sb.Append(' ');
          Prev:= True;
        end
        else
        begin
          Sb.Append(S[i]);
          Prev:= False;
        end;
      Result:= LowerCase(Trim(Sb.ToString));
    finally
      Sb.Free;
    end;
  end;

var
  Present: string        ;
  Line   : string        ;
  L      : string        ;
  Kept   : TStringBuilder;
begin
  Result:= AHarvested;
  if (AHarvested = '') or (Trim(APresent) = '') then Exit;
  Present:= Norm(APresent);
  if Present = '' then Exit;
  Kept:= TStringBuilder.Create;
  try
    for Line in StringReplace(StringReplace(AHarvested, #13#10, #10, [rfReplaceAll]),
                              #13, #10, [rfReplaceAll]).Split([#10]) do
    begin
      L:= Norm(Line);
      // A blank separator line carries no text to duplicate; it is kept only
      // when something survives around it, which the final Trim takes care of.
      if (L <> '') and (Pos(L, Present) > 0) then Continue;
      if Kept.Length > 0 then Kept.Append(#10);
      Kept.Append(Line);
    end;
    Result:= Trim(Kept.ToString);
  finally
    Kept.Free;
  end;
end;

// v(ADP3 T7): the DocInsight contract for this function now lives on its
// INTERFACE declaration, which is the surface Doc.Harvest compiles against.
// Restated here it would be a second copy free to drift from the one callers
// read.
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

// The ONE spelling of the attribute-tolerant container pattern: non-greedy
// content ([\s\S]*?), an optional attribute list on the opening tag
// ((?:\s[^>]*)?, e.g. ' name="X"' for <param>). v(ADP3 T3h): factored out
// because MaskMatches (see StandaloneBodyOf) must remove EXACTLY the spans
// StripElement removes -- BuildStandaloneFor's strip is what defines "nested
// inside another preserved container" for every presence gate in MergeComment,
// and a mask built from a second, independently-maintained pattern string could
// answer that question differently for content than the presence gate answered
// it, which is the very class of presence/content disagreement this task fixes.
// DELIBERATELY NOT the parser's stricter PRESERVED_CONTAINER_PATTERNS: those
// answer "what can the emitter represent" (T3f's residual mask), a different
// question -- see PRESERVED_CONTAINER_PATTERNS' own comment.
function ContainerLoosePattern(const ATagName: string): string;
begin
  Result:= '<' + ATagName + '(?:\s[^>]*)?>[\s\S]*?</' + ATagName + '>';
end;

class function TDocRegions.StripElement(const S, ATagName: string): string;
var
  Re: TRegEx;
begin
  // ALL occurrences removed (TRegEx.Replace with no count limit replaces every
  // match) -- see this function's own interface remarks for why "every
  // occurrence, not just the first" matters (a hand-typed <param> repeats once
  // per parameter; each is ALREADY preserved individually by MergeComment's own
  // param loop, so each must also be excluded here).
  Re:= TRegEx.Create(ContainerLoosePattern(ATagName), [roIgnoreCase]);
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
  // v(ADP3 T3h): the attribute-tolerant twin of RxResContainer, index-aligned
  // with it and with PRESERVED_VERBATIM_CONTAINERS. Built from
  // ContainerLoosePattern, the same function StripElement uses, so a mask and a
  // strip can never disagree about what a container occupies.
  RxLooseContainer    : array[0..7] of TRegEx;
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
  for I:= Low(PRESERVED_VERBATIM_CONTAINERS) to High(PRESERVED_VERBATIM_CONTAINERS) do
    RxLooseContainer[I]:= TRegEx.Create(ContainerLoosePattern(PRESERVED_VERBATIM_CONTAINERS[I]), [roIgnoreCase]);
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

// v(ADP3 T3h): position of ATagName within the two index-aligned container
// arrays. Raises rather than returning -1: every caller passes a literal from
// PRESERVED_VERBATIM_CONTAINERS, so a miss can only mean the arrays and a call
// site have drifted apart, and a silent -1 would degrade into "no filtering at
// all" -- exactly the pre-T3b behaviour these arrays exist to replace.
function ContainerIndexOf(const ATagName: string): Integer;
var
  I: Integer;
begin
  for I:= Low(PRESERVED_VERBATIM_CONTAINERS) to High(PRESERVED_VERBATIM_CONTAINERS) do
    if SameText(PRESERVED_VERBATIM_CONTAINERS[I], ATagName) then Exit(I);
  raise Exception.CreateFmt(
    'TDocRegions: "%s" is not one of PRESERVED_VERBATIM_CONTAINERS -- the ' +
    'container arrays and a call site have drifted apart.', [ATagName]);
end;

// v(ADP3 T3h): True for the containers TDocCommentParser.ParseXmlDoc reads with
// a SINGULAR .Match, so TParsedDoc holds exactly ONE body for them however many
// the author wrote. MIRRORS that unit's own .Match-vs-.Matches choice, tag for
// tag: summary/remarks/returns/example/since/deprecated are singular; <param>
// (correlated by name) and <exception> (by cref) are plural .Matches and are
// therefore NOT listed -- each of their occurrences gets its own emission and
// none of them is ever surplus.
//
// Expressed as one function rather than a third array index-aligned with the
// other two: the register already warns that the two parallel arrays are a
// drift surface, and this predicate has to be READ next to the parser's
// behaviour to be checked at all, which a bare column of Booleans would not be.
function IsSingularMatchContainer(const ATagName: string): Boolean;
begin
  Result:=
    SameText(ATagName, 'summary' ) or SameText(ATagName, 'remarks') or
    SameText(ATagName, 'returns' ) or SameText(ATagName, 'example') or
    SameText(ATagName, 'since'   ) or SameText(ATagName, 'deprecated');
end;

// v(ADP3 T3h): may a SURPLUS occurrence of this container be RETRACTED (handed
// back to the author verbatim by SplitResidualLines)? Every singular-match
// container EXCEPT <remarks>.
//
// <remarks> is excluded for a STRUCTURAL reason, not a cautionary one: it is the
// only modeled tag MergeComment emits AFTER the carried-through residual block.
// (Read that function's emission order: summary, deprecated, param, returns,
// exception, example, seealso, since, THEN the residual lines, THEN <remarks>.)
// So retracting a surplus <remarks> moves it AHEAD of the occurrence that keeps
// the slot; the next scan therefore reads the OTHER one as occurrence 1, and the
// two swap places on every run -- a period-2 permutation that never reaches a
// fixed point. MEASURED, not hypothesized: a two-<remarks> shape oscillated
// md5 A/B/A across three cycles when this predicate was still
// IsSingularMatchContainer, which is a hard violation of the branch's binding
// zero-byte-diff criterion.
//
// So while the residual block sits where T3f deliberately put it, the engine
// simply cannot represent "a second <remarks> after the first"; a surplus
// <remarks> stays accounted and its text is still lost -- exactly as before this
// task, no better and no worse. Both tagoccurrence.TwoRemarks* shapes pin that,
// so the outcome is uniform and visible instead of depending on whether the
// symbol happens to have facts.
function IsRetractableSurplusContainer(const ATagName: string): Boolean;
begin
  Result:= IsSingularMatchContainer(ATagName) and (not SameText(ATagName, 'remarks'));
end;

// v(ADP3 T3h): ParseXmlDoc's own per-tag normalization of a captured body, in
// ONE place so a located body is normalized EXACTLY as the parsed one was --
// <example> is Trim (a code sample's interior spacing is content), every other
// container is CollapseWhitespace. Reading these apart would make the fix
// visible as whitespace churn on shapes it is supposed to leave alone.
function NormalizeContainerBody(const ATagName, ABody: string): string;
begin
  if SameText(ATagName, 'example') then Result:= Trim(ABody)
  else Result:= TDocCommentParser.CollapseWhitespace(ABody);
end;

// v(ADP3 T3h): every match of ARe replaced by an EQUAL-LENGTH run of spaces
// (line breaks kept as they are, so the masked copy has the same line structure
// as well as the same length). That is the whole trick this task turns on: a
// DELETING strip -- StripElement, hence BuildStandaloneFor -- destroys offsets,
// so a match found in a stripped copy cannot be read back out of the original;
// a length-preserving mask keeps every offset valid in BOTH, which makes "which
// occurrence is genuinely standalone" and "what does that occurrence say" the
// same question, answered once, instead of two answers that can disagree.
function MaskMatches(const S: string; const ARe: TRegEx): string;
var
  MC: TMatchCollection;
  I : Integer         ;
  J : Integer         ;
begin
  Result:= S;
  MC:= ARe.Matches(S);
  for I:= 0 to MC.Count - 1 do
    for J:= MC[I].Index to MC[I].Index + MC[I].Length - 1 do
      if (Result[J] <> #13) and (Result[J] <> #10) then Result[J]:= ' ';
end;

class function TDocRegions.StandaloneBodyOf(const ARawBlock, ATagName, AFallback: string): string;
var
  Cleaned : string ;
  Masked  : string ;
  Own     : Integer;
  I       : Integer;
  M       : TMatch ;
  OpenLen : Integer;
  CloseLen: Integer;
  BodyLen : Integer;
  Body    : string ;
begin
  Result:= AFallback;
  Own:= ContainerIndexOf(ATagName);
  // The body arithmetic below assumes a FIXED-LENGTH, attribute-free opening tag
  // ('<tag>'), which is true of exactly the singular-match containers -- and not
  // by coincidence: <param>/<exception> are plural PRECISELY because they have a
  // natural key, the key lives in an attribute, and the attribute is what makes
  // their opening tag variable-length. Passing one of those would silently read
  // the wrong characters (off by the length of ' name="..."'), so it is refused
  // loudly instead. They need nothing from this function anyway: their emitters
  // correlate occurrences by name/cref and already read the right body.
  if not IsSingularMatchContainer(ATagName) then
    raise Exception.CreateFmt(
      'TDocRegions.StandaloneBodyOf: "%s" is not a singular-match container. ' +
      'Only tags whose opening form is a bare <tag> can have their body located ' +
      'by offset here; <param>/<exception> carry an attribute and are correlated ' +
      'by key at their own emission sites instead.', [ATagName]);
  // The SAME text ParseXmlDoc matches against, so an offset means the same
  // thing here as it does there (see BuildCleaned's own remarks).
  Cleaned:= TDocCommentParser.BuildCleaned(ARawBlock);
  if Cleaned = '' then Exit;
  EnsureResidualRegexes;
  Masked:= Cleaned;
  for I:= Low(PRESERVED_VERBATIM_CONTAINERS) to High(PRESERVED_VERBATIM_CONTAINERS) do
    if I <> Own then Masked:= MaskMatches(Masked, RxLooseContainer[I]);
  // The parser's OWN strict pattern for this tag, on the masked copy: the
  // occurrence found is therefore both (a) genuinely standalone, by
  // BuildStandaloneFor's definition, and (b) exactly the span ParseXmlDoc would
  // have captured, so the arithmetic below lands on the parser's own body.
  M:= RxResContainer[Own].Match(Masked);
  if not M.Success then Exit;
  // Every one of the six singular containers has a FIXED-LENGTH opening tag
  // (no attributes in the strict pattern), and roIgnoreCase cannot change a
  // length -- so the body is the match minus '<tag>' and '</tag>', with no
  // capture group needed.
  OpenLen := Length(ATagName) + 2;
  CloseLen:= Length(ATagName) + 3;
  // v(ADP3 T3k, T3h minor 1): FAIL-CLOSED CHECK ON THE PATTERN, not just on the
  // caller. The refusal above guards the tag NAME; this guards the thing the
  // arithmetic actually depends on -- that the matched opening really is the
  // bare literal '<tag>'. Both facts hold today, but they are held by DIFFERENT
  // declarations: IsSingularMatchContainer names the tags, while the opening
  // form lives in PRESERVED_CONTAINER_PATTERNS, and only the second one makes
  // OpenLen correct.
  //
  // Those pattern arrays get edited whenever tag handling changes, and the
  // harvester tasks that change tag handling run next. If a pattern ever gains
  // attribute tolerance, Copy() below starts at the wrong offset, the body is
  // read past the attribute, and the emitter writes CORRUPTED TEXT -- silently,
  // because nothing downstream can tell a mis-offset body from a real one.
  // T3h's own self-review raised exactly this hazard for the caller dimension
  // and left the pattern dimension open; the pattern dimension is the door far
  // more likely to be opened.
  //
  // Degrading to AFallback is strictly safe: it is the value the parser already
  // produced for this tag, i.e. the behaviour of every build before
  // StandaloneBodyOf existed.
  if not SameText(Copy(Masked, M.Index, OpenLen), '<' + ATagName + '>') then Exit;
  BodyLen := M.Length - OpenLen - CloseLen;
  if BodyLen <= 0 then Exit;
  // Read out of the UNMASKED text: anything legitimately nested inside this
  // genuinely-standalone occurrence comes back verbatim. Reading the masked (or
  // stripped) copy instead is what mangled '<deprecated>Added in <since>2.0
  // </since> and still valid.' down to 'Added in  and still valid.' in an
  // earlier round -- the reason every content read in MergeComment was moved off
  // the filtered views in the first place.
  Body:= NormalizeContainerBody(ATagName, Copy(Cleaned, M.Index + OpenLen, BodyLen));
  // An EMPTY located body defers to AFallback rather than overriding it, which
  // reproduces ParseXmlDoc's own 'if Result.Summary = '' then <untagged-prefix
  // fallback>' semantics: for <summary> specifically, a present-but-empty tag is
  // exactly when the parser adopts the region's leading prose, and returning ''
  // here would blank a summary the parser had legitimately filled. For every
  // other container the fallback is that container's own parsed value, which is
  // '' too on this shape, so deferring changes nothing.
  if Body = '' then Exit;
  Result:= Body;
end;

class function TDocRegions.SplitResidualLines(const ARawBlock: string;
  AEngineEmitsOwnRemarks: Boolean;
  out AAccountedRaw: string; out AResidualLines: TArray<string>): Boolean;
type
  // One span of ARawBlock the engine can re-emit on its own. Dropped spans are
  // retracted: the emitter must NOT see them, because the line carrying them
  // is being handed back to the author verbatim instead.
  TResSpan = record
    Lo, Hi        : Integer;
    // v(ADP3 T3h): index into PRESERVED_VERBATIM_CONTAINERS, or -1 for a span
    // that is not a container at all (a <see>/<seealso>, a bare <deprecated/>,
    // an engine marker, the untagged summary prefix). Needed to count a
    // container's occurrences separately per tag, and to tell "nested inside
    // ANOTHER container" from "nested inside itself".
    TagIx         : Integer;
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
  // v(ADP3 T3d, T3f minor 3): a line that overlaps a NON-RETRACTABLE span.
  // It can never be carried through (that would duplicate the tag), so it is
  // forced back to accounted -- but ONLY it, not the rest of the region.
  Blocked  : TArray<Boolean>;
  InFence  : TArray<Boolean>;
  Spans    : TArray<TResSpan>;
  Sb       : TStringBuilder ;
  I, J, K  : Integer        ;
  Changed  : Boolean        ;
  First    : Boolean        ;
  ResCount : Integer        ;
  // v(ADP3 T3h): occurrence counter for the surplus pass. Declared HERE, and
  // reset explicitly per tag, rather than as an inline `var Ordinal: Integer:= 0`
  // inside the loop body -- an inline declaration in a loop is a footgun worth
  // avoiding in a function this delicate, and "reset once per tag" is the whole
  // correctness condition when a region carries surplus occurrences of TWO
  // different tags (covered by tagoccurrence.TwoSinceAndTwoSummary).
  Ordinal  : Integer        ;

  procedure AddSpan(APos, ALen, ATagIx: Integer; AIsExample, AIsRemarks: Boolean);
  var
    Body: string;
  begin
    if ALen <= 0 then Exit;
    Body:= Copy(Joined, APos, ALen);
    SetLength(Spans, Length(Spans) + 1);
    Spans[High(Spans)].Lo            := APos;
    Spans[High(Spans)].Hi            := APos + ALen - 1;
    Spans[High(Spans)].TagIx         := ATagIx;
    Spans[High(Spans)].IsExample     := AIsExample;
    // Tested with RxResEngineMarker itself rather than a second, literal
    // spelling of the marker text -- one definition of "an engine marker",
    // so this test can never drift from what the mask accounts for.
    //
    // v(ADP3 T3d, T3f minor 1): the <remarks> arm is now CONDITIONAL. It used
    // to be an unconditional AIsRemarks, which is broader than its own
    // justification: the rule exists to stop the engine freezing its OWN
    // regenerated text and to stop it emitting a SECOND <remarks> beside a
    // frozen copy, and NEITHER hazard exists for a <remarks> that carries no
    // fence and no marker when the engine is going to emit no <remarks> at
    // all. On that shape the unconditional rule aborted the carry-through and
    // dropped the tail with no duplicate to avoid and no stale fact to trade
    // against -- a strict regression against the first cut of this mechanism,
    // which preserved it. The two real hazards are tested directly instead:
    //   * AEngineEmitsOwnRemarks -- the caller has already established that
    //     RenderFactsBlock produces something, so a retracted author
    //     <remarks> would sit verbatim beside the engine's own. Computed by
    //     the caller because only it holds AFacts (see MergeComment's call).
    //   * a fence inside the span -- its lines are engine-generated and
    //     re-derived every run. The marker test below would ALSO catch this
    //     (AUTO_BEGIN is itself a drag-lint HTML marker), but relying on that
    //     coincidence would make the fence's protection depend on the fence's
    //     spelling continuing to match a generic pattern, so it is asserted
    //     here in its own right.
    Spans[High(Spans)].NonRetractable:=
      (AIsRemarks and (AEngineEmitsOwnRemarks or (Pos(AUTO_BEGIN, Body) > 0)))
      or RxResEngineMarker.IsMatch(Body);
    Spans[High(Spans)].Dropped       := False;
  end;

  procedure AddMatches(const ARe: TRegEx; ATagIx: Integer; AIsExample, AIsRemarks: Boolean);
  var
    MC: TMatchCollection;
    M : Integer         ;
  begin
    MC:= ARe.Matches(Joined);
    for M:= 0 to MC.Count - 1 do
      AddSpan(MC[M].Index, MC[M].Length, ATagIx, AIsExample, AIsRemarks);
  end;

  // v(ADP3 T3h): True when span AIx sits entirely inside the span of a
  // DIFFERENT container -- i.e. it is a nested look-alike, whose line the OUTER
  // container already accounts for, so it never needs a slot of its own and can
  // never be "surplus". Same containment shape as the multi-line-<example>
  // nesting test below; TagIx is what makes "a different container" expressible
  // (a span can only ever be compared against another CONTAINER, never against
  // a marker or a <see>, and never against itself).
  function NestedInOtherContainer(AIx: Integer): Boolean;
  var
    K2: Integer;
  begin
    Result:= False;
    for K2:= 0 to High(Spans) do
      if (Spans[K2].TagIx >= 0) and (Spans[K2].TagIx <> Spans[AIx].TagIx)
         and (Spans[K2].Lo <= Spans[AIx].Lo) and (Spans[AIx].Hi <= Spans[K2].Hi) then
        Exit(True);
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
    AddMatches(RxResContainer[I], I,
      SameText(PRESERVED_VERBATIM_CONTAINERS[I], 'example'),
      SameText(PRESERVED_VERBATIM_CONTAINERS[I], 'remarks'));
  // <see>/<seealso>/<deprecated/> are round-tripped verbatim, so they ARE
  // retractable -- that is what lets an inline <see cref> inside an unmodeled
  // <para> stay on the author's own line instead of being hoisted out.
  AddMatches(RxResSee           , -1, False, False);
  AddMatches(RxResDeprecatedBare, -1, False, False);
  // Engine markers carry AUTO_MARKER_LEAD by construction, so AddSpan marks
  // every one of them non-retractable: a line mixing the engine's own
  // bookkeeping with author content is ambiguous, and this whole mechanism
  // fails closed on ambiguity.
  AddMatches(RxResEngineMarker  , -1, False, False);

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
    if LtPos = 0 then AddSpan(1, Length(Joined), -1, False, False)
    else if LtPos > 1 then AddSpan(1, LtPos - 1, -1, False, False);
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

  // v(ADP3 T3h, register N2/D11): SURPLUS occurrences of a SINGULAR-MATCH
  // container are retracted, so their lines come back verbatim.
  //
  // This is THIS FUNCTION's own rule -- "the engine owns a line only when it can
  // represent EVERYTHING on it" -- applied to a capacity the mask was not
  // testing. The mask accounted for every MATCH of a container pattern, while
  // TParsedDoc holds exactly ONE body for these six tags (ParseXmlDoc reads them
  // with .Match, not .Matches); so an author who wrote two <since> tags had the
  // second one accounted -- hence NOT carried through -- and then never emitted,
  // i.e. silently deleted. Counting occurrences here is what makes the mask
  // agree with the parser's actual capacity rather than with its patterns.
  //
  // Ordinal 1 is the occurrence the emitter will use, and it is chosen by the
  // SAME rule StandaloneBodyOf uses: the first one that is not nested inside
  // another container. (A nested look-alike is skipped, not counted: its line is
  // accounted by the OUTER container regardless, and it competes for no slot.)
  // Spans for one tag are appended in match order, so ordinal order is source
  // order.
  //
  // A NonRetractable surplus is deliberately LEFT ACCOUNTED -- the conservative
  // direction. Retracting it would freeze engine-regenerated text (a marked
  // <summary>/<returns>, say, which only a corrupted or hand-duplicated file can
  // carry twice) as un-maintained, un-strippable author content, which this
  // function already argues is the worse failure; the surplus text is then still
  // lost, exactly as before this task, rather than newly damaged.
  //
  // <remarks> is excluded from the whole pass for a separate, structural reason
  // -- see IsRetractableSurplusContainer, and the TwoRemarks* fixture shapes
  // that pin the outcome.
  //
  // v(ADP3 T3k, Group 2b item 5): ON PURPOSE, this pass cannot see the BARE
  // self-closing '<deprecated/>' form. That span is added with TagIx = -1 (it is
  // not one of the paired containers this loop indexes by), so `Spans[J].TagIx =
  // I` never selects it and a SURPLUS bare <deprecated/> is still silently
  // dropped rather than retracted to its line. Harmless -- the form carries no
  // text, so nothing an author wrote is lost, which is the only reason it is
  // acceptable to leave. But it IS an uncovered instance of the class this pass
  // exists to handle, and stating that here is the difference between a
  // deliberate exclusion and an oversight nobody rediscovers.
  for I:= Low(PRESERVED_VERBATIM_CONTAINERS) to High(PRESERVED_VERBATIM_CONTAINERS) do
  begin
    if not IsRetractableSurplusContainer(PRESERVED_VERBATIM_CONTAINERS[I]) then Continue;
    Ordinal:= 0;
    for J:= 0 to High(Spans) do
      if (Spans[J].TagIx = I) and (not Spans[J].Dropped) and (not NestedInOtherContainer(J)) then
      begin
        Inc(Ordinal);
        if (Ordinal > 1) and (not Spans[J].NonRetractable) then Spans[J].Dropped:= True;
      end;
  end;

  // Fixed-point closure. Retracting a span can leave a line that was accounted
  // only BECAUSE of it newly residual, which can in turn retract further
  // spans; the loop is monotone (spans are only ever dropped, residual lines
  // only ever added, lines only ever blocked), so it terminates in at most
  // Length(Spans) + Length(RawLines) rounds.
  SetLength(Accounted, Length(Joined) + 1);
  SetLength(Residual , Length(RawLines));
  SetLength(Blocked  , Length(RawLines));
  repeat
    for J:= 1 to Length(Joined) do Accounted[J]:= False;
    for I:= 0 to High(Spans) do
      if not Spans[I].Dropped then
        for J:= Spans[I].Lo to Spans[I].Hi do Accounted[J]:= True;

    for I:= 0 to High(RawLines) do
    begin
      Residual[I]:= False;
      if InFence[I] then Continue; // engine-generated, re-derived: never author content
      if Blocked[I] then Continue; // see the NonRetractable arm below
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
            // option for THAT LINE -- emitting it verbatim WITHOUT retracting
            // the span duplicates the tag (measured: two <returns>, one
            // permanently stale), and retracting the span freezes engine
            // content. So the line loses its carry-through and falls back to
            // the pre-v(ADP3 T3f) behaviour, which drops the unmodeled text on
            // it. That is a real, disclosed non-improvement for this shape,
            // chosen deliberately over a malformed comment carrying a fact the
            // engine has silently stopped maintaining.
            //
            // v(ADP3 T3d, T3f minor 3): the blast radius is now THE OFFENDING
            // LINE, not the whole region. This used to Exit outright, which
            // aborted the mechanism for every OTHER line too -- so an innocent
            // <value> sitting on its own line, overlapping nothing
            // non-retractable, was deleted because a DIFFERENT line elsewhere
            // in the same comment happened to mix author text into an
            // engine-marked tag. Nothing about that innocent line is
            // ambiguous, and the fail-closed argument above says nothing about
            // it. Blocking just this line keeps the argument exactly as narrow
            // as its own justification: the line stays accounted (so its spans
            // are still emitted, unduplicated) and every other residual line
            // still carries through.
            //
            // Note the two OTHER fail-closed exits in this function still
            // abort the WHOLE region, and correctly so: an unterminated fence
            // means the region's engine/author boundary cannot be established
            // at all, which is a statement about the region, not a line.
            if Spans[I].NonRetractable then
            begin
              if not Blocked[K] then
              begin
                Blocked[K] := True;
                Residual[K]:= False;
                Changed    := True;
              end;
              Continue;
            end;
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

// v(ADP3 T3, promoted to a class function in v(ADP3 T9)): True when S is
// engine-owned WITHOUT regard to emptiness -- carries AUTO_MARK, or is the
// legacy 'TODO: describe.' sentinel (the pre-v(ADP3) format; still self-heals
// here). Used for <summary> and <returns> ONLY: marked there means engine-owned,
// full stop, regardless of what follows the marker -- see the plan's own
// recorded deviation (a human edit inside the markers is not separable from "the
// source comment changed", so both refresh; ownership changes hands only by
// REMOVING the marker, never by the engine sniffing content). v(ADP3 T3 review
// round 2): a content-keyed exception was tried here and reverted -- an exact-
// string compare against generated text is content-keyed ownership by the back
// door, MORE brittle than the StartsText('Observed:') sniff Task 1 deleted
// (exact equality survives neither whitespace normalization nor legitimate
// drift, where a prefix match would have survived both) -- see MergeComment's
// own remarks for the reproduced breakage.
class function TDocRegions.IsEngineOwnedTagText(const S: string): Boolean;
begin
  Result:= IsManagedText(S) or SameText(Trim(S), 'TODO: describe.');
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
class function TDocRegions.FormatPhase2FactLines(const AFacts: TDocFacts; AComplexityMin: Integer = 10;
  AHasOtherContent: Boolean = True): TArray<string>;
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
    // PHASE C B4: the two numbers on this line MEASURE DIFFERENT SCOPES, and
    // saying so is the whole fix. CyclomaticCountDecisions returns at a nested
    // `defProc` ("nested routine counted separately"), so the count covers the
    // OUTER body only; BodyLoc is impl_end - impl_start, the whole
    // implementation including every nested routine. Presented as a bare pair
    // they read as one measurement of one thing, and on YADF's FormatSource that
    // is 'Complexity: 24 (cyclomatic), 603 lines' for a range holding 109
    // decision keywords across 15 nested routines -- a reader can only conclude
    // the numbers are wrong.
    //
    // Labelled, the SAME pair becomes the useful signal the review pointed at:
    // a low outer complexity over a long implementation says the work sits in
    // nested scopes. The labels are unconditional because they are always true;
    // suppressing them when the body has no nested routine would need a nested
    // count the index does not record (that is B3's boundary work), and a label
    // that appears only sometimes is a worse contract than one that always does.
    if (AFacts.Cyclomatic > 0) and (AFacts.Cyclomatic >= AComplexityMin) then
      Lines.Add(Format('Complexity: %d (cyclomatic, outer body), %d lines (full implementation)',
                       [AFacts.Cyclomatic, AFacts.BodyLoc]));
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
    // v(ADP3 T11): Mutates -- the var/out parameters the routine writes
    // through. Closes the Phase-2 T4 deferred gap (that fact covered the owning
    // class's FIELDS only, so a free procedure that exists solely to fill an
    // `out` parameter said nothing). Display-ready at index time, so this is a
    // passthrough; omitted entirely when empty, like every other fact line.
    //
    // POSITION IS PART OF THE CONTRACT. The Phase 3 lines are appended AFTER
    // the existing six, in the plan's fixed order -- Mutates: (T11), UI thread
    // only (T12), Touches:/Transaction: (T13), Registered as:/Dataset: (T14),
    // Pure last (T13). Fixing the order here is what keeps the doc/hover
    // consistency lock meaningful and regeneration byte-idempotent: this ONE
    // function is the single home for both surfaces, so a line inserted in the
    // middle would rewrite every already-documented block in the corpus.
    if AFacts.MutatesParams <> '' then
      Lines.Add('Mutates: ' + EscXml(AFacts.MutatesParams));
    // v(ADP3 T12): UI affinity -- POSITIVE FINDINGS ONLY. The absence of this
    // line means "no UI touch was DETECTED", never "this routine is
    // thread-safe": a stale curated list under-reports, and a thread-safety
    // claim cannot be proven by this analysis. Nothing here may ever grow an
    // `else` arm that says the opposite.
    if AFacts.UiAffinity <> '' then
      Lines.Add('UI thread only -- touches ' + EscXml(AFacts.UiAffinity));
    // v(ADP3 T13): external surfaces touched, as CATEGORIES (not call sites)
    // and transaction verbs. Stored as 'resources|transactions'; either side
    // may be empty, and the whole line pair is omitted when both are.
    if AFacts.Touches <> '' then
    begin
      var TouchParts: TArray<string>:= AFacts.Touches.Split(['|']);
      if (Length(TouchParts) > 0) and (TouchParts[0] <> '') then
        Lines.Add('Touches: ' + EscXml(TouchParts[0]));
      if (Length(TouchParts) > 1) and (TouchParts[1] <> '') then
        Lines.Add('Transaction: ' + EscXml(TouchParts[1]));
    end;
    // v(ADP3 T14): DI/ORM wiring -- a JOIN over already-indexed tables
    // (di_bindings / orm_links / fb_relations / fb_columns), NOT a new
    // analysis. Stored as '; '-joined 'di:'/'ds:' entries; split into two
    // display lines here so each can be omitted independently.
    if AFacts.Wiring <> '' then
    begin
      var DiPart: string:= ''; var DsPart: string:= '';
      for var WEntry in AFacts.Wiring.Split(['; ']) do
        if StartsStr('di:', WEntry) then
        begin
          if DiPart <> '' then DiPart:= DiPart + ', ';
          DiPart:= DiPart + Copy(WEntry, 4, MaxInt);
        end
        else if StartsStr('ds:', WEntry) then
        begin
          if DsPart <> '' then DsPart:= DsPart + ', ';
          DsPart:= DsPart + Copy(WEntry, 4, MaxInt);
        end;
      if DiPart <> '' then Lines.Add('Registered as: ' + EscXml(DiPart));
      if DsPart <> '' then Lines.Add('Dataset: ' + EscXml(DsPart));
    end;
    // v(ADP3 T13): 'Pure' is DERIVED at render time from the other facts and
    // has NO column of its own -- so it can never disagree with them. Emitted
    // for a routine WITH A BODY that writes no field, mutates no var/out
    // parameter, touches no external surface and reads/writes no SQL. It is a
    // CONCLUSION, not an observation: it says "none of the effects this engine
    // can detect were detected", which is exactly as strong as the facts
    // beneath it -- and no stronger, which is why it is not called
    // 'side-effect free'. Emitted LAST, per the fixed Phase 3 line order.
    //
    // BodyLoc > 0 is the with-a-body gate: an interface-only declaration, or a
    // symbol with no symbol_facts row at all, reads 0 and must not be called
    // Pure on the strength of five facts that were never computed.
    //
    // PURE NEVER CREATES A BLOCK OF ITS OWN -- the AHasOtherContent gate. This
    // is a DEVIATION from the plan's snippet, taken deliberately after the
    // literal version was implemented and run. `Pure` is true of a very large
    // fraction of any real codebase, so an unconditional emit gives a managed
    // block to nearly every trivial effect-free routine -- reversing the
    // long-standing "omit when empty" contract corpus-wide, and silently: five
    // existing suites assert in so many words that a symbol with nothing to say
    // gets NO managed block at all (run_doc_p2_sql's 'NoSql has NO managed
    // block at all (no fact fires)' and its four siblings), and every one of
    // them went red on the literal version. Writing a doc block into a file is
    // an EDIT; the bar for creating one is "there was something to say", and
    // 'Pure' alone is a statement about the absence of findings. It still
    // appears on every block that exists for any other reason, which is where
    // it is actually useful. Widening this later is one condition; unwinding a
    // corpus-wide block explosion is not.
    if (AFacts.BodyLoc > 0)
       and (AFacts.WritesFields = '') and (AFacts.MutatesParams = '')
       and (AFacts.Touches = '') and (AFacts.SqlWrites = '') and (AFacts.SqlReads = '')
       and ((Lines.Count > 0) or AHasOtherContent) then
      Lines.Add('Pure');
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
  // Is this entry a CERTAIN one? '' and 'certain' are the two certain spellings
  // (the store leaves Confidence empty on a path that never had a doubt);
  // 'ambiguous' and 'unverified' are the uncertain ones. ONE declaration, read
  // by both the survey pass and the emit pass below -- the two must agree about
  // every entry or the survey could report "mixed" while the emit marks all or
  // none, which is a shape no test would obviously name.
  function IsCertain(const R: TDocFactRef): Boolean;
  begin
    Result:= (R.Confidence = '') or SameText(R.Confidence, 'certain');
  end;
  // v(ADP3 T4): the ' ?' uncertainty marker is emitted ONLY when the list is
  // MIXED. A marker on EVERY entry distinguishes nothing, and that is the state
  // most lists were measured to be in on the pre-T4 tree, on both a real
  // consumer corpus and this repo's own source. So a uniformly uncertain list
  // now renders plain, exactly as a uniformly certain one always has, and what
  // survives is the COMPARATIVE information: within one list, which entries are
  // the weaker ones. Mixed lists were not rare enough in that measurement for
  // this to be an empty promise.
  //
  // THE FIGURES THAT USED TO BE HERE ARE GONE, DELIBERATELY (register K18).
  // Four percentages and two counts sat in this comment, produced by
  // scratchpad\measure_markers.ps1, which was never committed and no longer
  // exists. They were dated and attributed -- the mitigation the stale "49 of
  // 49" lacked -- but that is not enough, and here it cannot be repaired the way
  // T4b repaired its own numbers by committing tools\measure\returns_blast.py:
  // the quantity is a property of the PRE-T4 RENDERING, produced by a binary
  // (f5fc66e's) that no longer exists, of output this engine no longer emits.
  // No commit of this repo after T4 can re-derive it. A number nobody can check
  // reads as a current property of the code and slowly stops being one -- so it
  // belongs in a DATED record, and it has one: the phase ledger's T17 section
  // ("FOUR ONE-TIME REWRITES TO EXPECT", cause 2) and the T4 report carry the
  // measurement with its date and corpora. What belongs HERE is the rule.
  //
  // The rule's ORIGINAL justification in the plan ("it fired 49 times out of
  // 49") was itself stale and was re-measured rather than inherited: it predates
  // T3i, which stopped counting 'member-access' refs as unresolved call sites
  // and so removed one cause of the saturation. The rule survived that
  // correction. That is the part worth keeping, and it needs no percentage.
  //
  // This is a RENDERING change and nothing more. The root cause -- weak
  // call_edges resolution in project DBs, which is why so many lists are
  // uniformly uncertain in the first place -- is the D5 follow-up; Confidence
  // itself, the Facts builder's certain-before-uncertain ORDERING, the display
  // cap and the '(+N more)' suffix are all untouched.
  function JoinRefs(const A: TArray<TDocFactRef>): string;
  var i: Integer; AnyCertain, AnyUncertain, Mixed: Boolean;
  begin
    Result:= '';
    AnyCertain  := False;
    AnyUncertain:= False;
    for i:= 0 to High(A) do
      if IsCertain(A[i]) then AnyCertain:= True else AnyUncertain:= True;
    Mixed:= AnyCertain and AnyUncertain;
    for i:= 0 to High(A) do
    begin
      if i > 0 then Result:= Result + ', ';
      Result:= Result + EscXml(A[i].Display) + ' (' + EscXml(A[i].Location) + ')';
      if Mixed and not IsCertain(A[i]) then
        Result:= Result + ' ?';
    end;
  end;
begin
  Sb:= TStringBuilder.Create;
  try
    if Length(AFacts.CalledFrom) > 0 then
    begin
      // v(ADP3 T4): 'Called from:' is a claim that the symbol is CALLED, and it
      // is only true of a callable. A record/class/interface/constant is USED --
      // its entries reach this list through the non-routine path in
      // DRagLint.Doc.Facts (CanBeCallTarget is False, so the name-match bucket
      // is not restricted to call sites) and are type mentions, not call sites.
      // The YADF rollout rendered 'Called from:' over exactly those. Same list,
      // same cap, same '(+N more)', same marker rule -- only the verb is
      // kind-selected.
      //
      // CanBeCallTarget is THE declaration for this question (Core.Model); the
      // kind set is deliberately not restated here. DRagLint.Doc.Facts' gather
      // reads the same one to decide what goes INTO this list, so the label and
      // the contents cannot drift apart into disagreeing about what a callable
      // is -- which is the whole reason T3i/T3k collapsed the copies.
      var RefVerb: string;
      if CanBeCallTarget(AFacts.SymbolKind) then RefVerb:= 'Called from: '
      else RefVerb:= 'Used by: ';
      Sb.AppendLine(APrefix + RefVerb + JoinRefs(AFacts.CalledFrom) + MoreSuffix(Length(AFacts.CalledFrom), AFacts.CalledFromTotal));
    end;
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
    // AHasOtherContent: Sb already holds every Phase-1 line for this symbol, so
    // its emptiness IS the test for 'this block would not exist but for Pure'.
    for var P2Line in FormatPhase2FactLines(AFacts, AComplexityMin, Sb.Length > 0) do
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
  // v(ADP3 T9): the body of this test now lives on TDocRegions itself, as
  // IsEngineOwnedTagText -- Doc.Drift's harvest-drift check needs the SAME
  // ownership test, and a second hand-expansion of its two arms is exactly how
  // that unit desynced from MergeComment before (see IsManagedDesc's own
  // remarks). This local name is kept only so the call sites and the comments
  // that cite them read unchanged.
  function IsEngineOwnedRegardlessOfContent(const S: string): Boolean;
  begin
    Result:= IsEngineOwnedTagText(S);
  end;
  // v(PHASE A3, ruling D-3): the MEANING mined for parameter AName, or '' when
  // the source states none. '' is not a failure -- it is the ordinary case, and
  // it produces a <param> tag with an empty body: structure without meaning.
  function ParamNoteFor(const AName: string): string;
  var PN: TDocParamNote;
  begin
    Result:= '';
    for PN in AFacts.ParamNotes do
      if SameText(PN.Name, AName) then Exit(EscXml(PN.Text));
  end;
  // The engine-owned <param> emit. ONE writer for both MergeComment paths (the
  // fresh insert and the repair), because a <param> that appeared on only one of
  // them would look like a mining bug rather than a wiring one -- the same
  // reasoning EmitHarvestedRemarks records for itself.
  //
  // Marked, so `document --strip` and the drift check can tell this tag is the
  // engine's. ClassifyParamAction then reads that marker on the NEXT run:
  // marked-and-empty is engine-owned (regenerated), marked-with-text is
  // preserved -- which is exactly ruling D-4's "regenerate the structure, leave
  // the meaning alone", including a meaning a human typed INSIDE the tag without
  // removing the marker.
  function EmitEngineParam(const AName: string): string;
  begin
    // PHASE C B7, as CLARIFIED by the user 2026-08-09: "Autodocument has to
    // produce the param section among other things if it does not reflect the
    // correct situation. Warnings and errors is what Linter produces."
    //
    // So <param> is STRUCTURAL and ruling D-3 stands: the tag set mirrors the
    // signature, always, because the documenter's job is to make the block
    // reflect the code. It is NOT one of the "empty sections are omitted" cases
    // -- those are <summary> and <returns>, elements that carry prose and
    // nothing else, where a blank one is purely a blank tooltip.
    //
    // An undocumented parameter is therefore reported by the LINTER, not
    // silently dropped here: ddParamNoDescription at WARNING (severity set by
    // the same 2026-08-09 ruling, in DRagLint.Lint.DocRules).
    Result:= EmitTagged('<param name="' + AName + '">' + AUTO_MARK, ParamNoteFor(AName), '</param>');
  end;

  // PHASE C B7: an element whose body is blank once its marker is removed. Such
  // an element carries NOTHING TO PRESERVE, so the ownership question that
  // governs every other merge decision simply does not arise -- dropping it
  // cannot lose a human's words, because there are none. That is what lets this
  // clear tags the engine did not write: YADF's corpus holds 78 empty elements
  // that carry no marker at all, are therefore treated as hand-written, and
  // survived every regeneration precisely because the merge was protecting them.
  function IsBlankBody(const AText: string): Boolean;
  begin
    Result:= Trim(StripMark(AText)) = '';
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
      // v(ADP3 T3d, T3f minor 1): "will the engine emit a <remarks> of its
      // own?", answered by RENDERING rather than by guessing at AFacts'
      // fields -- RenderFactsBlock applies its own gating (the complexity
      // threshold, per-section emptiness), so rendering is the only test that
      // cannot disagree with what actually gets emitted below.
      //
      // AIncludeReturns is passed True, the MAXIMAL render, because the real
      // IncludeReturns is not computable yet: it derives from Eff, which is
      // what this call produces. Maximal is the SAFE direction -- it can only
      // say "the engine may emit a <remarks>" when the truth is "it will not",
      // which keeps an author <remarks> non-retractable, which is exactly the
      // pre-v(ADP3 T3d) behaviour. It can never say "no remarks" when one is
      // coming. The one shape where the two answers differ is a symbol whose
      // ONLY fact is the mined 'Returns:' line AND whose <returns> is not
      // hand-written; that shape keeps the old, conservative outcome.
      //
      // COST, stated honestly rather than waved away: this renders ONCE PER
      // REPAIRED XML doc comment, residual lines or not -- it cannot be made
      // lazy, because SplitResidualLines takes it as an argument and needs it
      // inside AddSpan. It is a string build over facts this call site has
      // already computed, on a path that may also run nine BuildStandaloneFor
      // re-parses, and Facts is rendered again a few hundred lines below
      // anyway; so the added work is one more render on a path that already
      // does far more than that, not a new order of cost.
      var EngineEmitsOwnRemarks: Boolean:=
        RenderFactsBlock(AFacts, APrefix, True, AComplexityMin) <> '';
      if SplitResidualLines(AExisting.RawBlock, EngineEmitsOwnRemarks, AccountedRaw, Residual) then
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
    // v(ADP3 T3h, register N2): the CONTENT half of the presence/content split
    // for the six SINGULAR-MATCH containers -- the body of the occurrence the
    // matching Standalone* view found PRESENT, rather than of whichever
    // occurrence happened to come first in the region. <param> and <exception>
    // need no equivalent: they are plural .Matches and correlate by name/cref,
    // so they already read the right occurrence's text (see their own loops).
    //
    // Computed in THIS block, on THIS gate, deliberately: presence and content
    // must describe the SAME occurrence, so wherever presence falls back to the
    // unfiltered Eff (HasAnySignal False -- no exotic container present to hide
    // anything behind) content must fall back with it. Each call's fallback is
    // the very field it replaces, so this is a byte-for-byte no-op on every
    // shape with at most one occurrence of the tag -- see StandaloneBodyOf.
    var BodySummary : string;
    var BodyReturns : string;
    var BodyRemarks : string;
    var BodySince   : string;
    var BodyDep     : string;
    var BodyExample : string;
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
      BodySummary       := StandaloneBodyOf(Eff.RawBlock, 'summary'   , Eff.Summary       );
      BodyReturns       := StandaloneBodyOf(Eff.RawBlock, 'returns'   , Eff.ReturnsText   );
      BodyRemarks       := StandaloneBodyOf(Eff.RawBlock, 'remarks'   , Eff.Remarks       );
      BodySince         := StandaloneBodyOf(Eff.RawBlock, 'since'     , Eff.SinceText     );
      BodyDep           := StandaloneBodyOf(Eff.RawBlock, 'deprecated', Eff.DeprecatedText);
      BodyExample       := StandaloneBodyOf(Eff.RawBlock, 'example'   , Eff.ExampleText   );
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
      BodySummary       := Eff.Summary       ;
      BodyReturns       := Eff.ReturnsText   ;
      BodyRemarks       := Eff.Remarks       ;
      BodySince         := Eff.SinceText     ;
      BodyDep           := Eff.DeprecatedText;
      BodyExample       := Eff.ExampleText   ;
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
    // v(ADP3 T3h): the ownership test reads BodyReturns -- the body of the
    // occurrence StandaloneReturns.HasReturnsTag is True ABOUT -- not Eff's
    // first-occurrence-anywhere body. With a <returns> nested inside
    // <deprecated> and the engine's OWN marked <returns> beside it, Eff's body
    // is the nested (unmarked) one, so this read said "hand-written" about a tag
    // that is engine-owned: the engine then re-emitted the nested text at its own
    // slot, unmarked -- an unstrippable fabrication -- AND duplicated the mined
    // case into a 'Returns:' fact line, breaking "never both".
    var ReturnsHandWritten: Boolean:=
      AExistingHasAnyTag and StandaloneReturns.HasReturnsTag
      and (not IsEngineOwnedRegardlessOfContent(BodyReturns));
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
      // v(PHASE A3, ruling D-3): STRUCTURE ALWAYS. The comment above used to
      // read "and <param> never", on the ground that no harvester for parameter
      // descriptions existed. One does now, and more importantly the omission
      // was itself a defect: `doc-drift` reported every one of these tags as
      // missing while `document` refused to write any, so the two halves could
      // never converge -- 22 unclearable findings on one corpus
      // (INBOX-datacopy-2026-08-06, section 3). An automatic generator supplies
      // structure, not meaning; the body is filled only where the source states
      // it, and is otherwise empty.
      for P in ASigParams do
        Sb.AppendLine(EmitEngineParam(P));
      if AHasReturn then
      begin
        var Obs: string:= Trim(ObservedSuffix(AFacts.ReturnCases));
        if Obs <> '' then
          Sb.AppendLine(APrefix + '<returns>' + AUTO_MARK + Obs + '</returns>');
      end;
      // v(ADP3 T7): the <remarks> element is now also warranted by harvested
      // prose alone -- a symbol can have a second paragraph worth promoting and
      // no facts at all -- so the condition is widened past `Facts <> ''`.
      if (Facts <> '') or (AFacts.HarvestedRemarks <> '') then
      begin
        Sb.AppendLine(APrefix + '<remarks>');
        EmitHarvestedRemarks(Sb, APrefix, AFacts.HarvestedRemarks);
        if Facts <> '' then
        begin
          Sb.AppendLine(APrefix + AUTO_BEGIN);
          Sb.AppendLine(Facts);
          Sb.AppendLine(APrefix + AUTO_END);
        end;
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
    // v(ADP3 T3h): BodySummary, not Eff.Summary -- the body of the occurrence
    // StandaloneSummary.HasSummaryTag is True ABOUT. The reasoning above still
    // holds in full (a STRIPPED view's Summary would lose anything nested inside
    // a genuinely standalone summary's own prose); StandaloneBodyOf reads the
    // located occurrence out of the UNSTRIPPED text precisely so both properties
    // hold at once.
    var SummaryRaw: string:= BodySummary;
    // PHASE C B7: `and not IsBlankBody` is the added clause. An UNMARKED empty
    // <summary> used to satisfy the preserve arm and be re-emitted verbatim
    // forever -- 39 of them in YADF, every one a blank DocInsight tooltip that no
    // regeneration could clear. Empty means there is nothing to preserve, so the
    // harvested summary (if any) gets its chance below, and otherwise no tag is
    // written at all.
    if StandaloneSummary.HasSummaryTag and (not IsEngineOwnedRegardlessOfContent(SummaryRaw))
       and (not IsBlankBody(SummaryRaw)) then
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
    // v(ADP3 T3h): BodyDep, the located standalone occurrence's own message --
    // still the UNSTRIPPED text, so the '"Added in <since>2.0</since> and still
    // valid." -> "Added in  and still valid."' mangling this comment describes
    // stays fixed; what changes is only WHICH <deprecated> supplies it.
    if StandaloneDep.Deprecated then
    begin
      if BodyDep <> '' then
        Sb.AppendLine(EmitTagged('<deprecated>', BodyDep, '</deprecated>'))
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
      // v(PHASE A3): tracks whether the HAND-WRITTEN arm already emitted this
      // param, so the structural arm below does not write a second tag for it.
      var ParamEmitted: Boolean:= False;
      for var EP in Eff.Params do
        if SameText(EP.Name, P) then
        begin
          var IsStandaloneParam: Boolean:= False;
          for var SP in StandaloneParam.Params do
            if SameText(SP.Name, P) then begin IsStandaloneParam:= True; Break; end;
          if IsStandaloneParam then
          begin
            // v(PHASE A3): IS THIS MARKED BODY THE ENGINE'S OWN HARVEST, OR A
            // HUMAN'S EDIT INSIDE THE ENGINE'S TAG? Before A3 the question could
            // not arise -- nothing ever filled a <param>, so marked-with-content
            // could only be a human (Finding 1's taPreserveStripped rule). Now
            // the miner fills one, and taPreserveStripped applied to ITS OWN
            // output strips the marker on the second run: the block changes
            // every cycle (measured: cycle 2 removed four markers) and the
            // engine quietly hands ownership of its own text to the human.
            //
            // The question is answerable EXACTLY rather than by heuristic:
            // compare the marked body with what the miner produces from the
            // CURRENT source. Equal means the engine wrote it and the source
            // still says so -- regenerate, and the run is a fixed point. Not
            // equal means a human typed something else there, or the source
            // comment changed under a body someone has since adjusted; ruling
            // D-4 says leave that meaning alone, so it falls through to the
            // preserve arm exactly as before.
            var MinedNow: string:= Trim(ParamNoteFor(P));
            if (MinedNow <> '') and IsManagedDesc(EP.Desc)
               and SameText(Trim(StripMark(EP.Desc)), MinedNow) then
            begin
              Sb.AppendLine(EmitEngineParam(P));
              ParamEmitted:= True;
              Break;
            end;
            // PHASE C B7: an UNMARKED empty tag falls through to be REGENERATED
            // rather than preserved verbatim. It carries nothing to protect (see
            // IsBlankBody), and regenerating re-marks it as the engine's, so a
            // description mined later can fill it. Marked-and-empty already fell
            // through; this only adds the unmarked case, which the preserve arms
            // below would otherwise freeze forever -- the property that kept
            // YADF's empty tags alive through every regeneration.
            if IsBlankBody(EP.Desc) then
            begin
              Sb.AppendLine(EmitEngineParam(P));
              ParamEmitted:= True;
              Break;
            end;
            case ClassifyParamAction(EP.Desc, True) of
              // RULING D-4, the meaning half: a body a human wrote is never
              // overwritten -- including one typed INSIDE the engine's own tag
              // without removing the marker (taPreserveStripped).
              taPreserveStripped: begin Sb.AppendLine(EmitTagged('<param name="' + P + '">', StripMark(EP.Desc), '</param>')); ParamEmitted:= True; end;
              taPreserveVerbatim: begin Sb.AppendLine(EmitTagged('<param name="' + P + '">', EP.Desc, '</param>')); ParamEmitted:= True; end;
              taEngineOwned: ;  // engine-owned and empty: fall through and REGENERATE
            end;
          end;
          Break;
        end;
      // v(PHASE A3, ruling D-3), replacing "fresh/missing params never get a
      // skeleton": no hand-written tag exists for this signature parameter (no
      // match at all, a non-standalone match, or an engine-owned empty one), so
      // the STRUCTURE is (re)generated here. That is D-4's other half -- the
      // structure part is regenerated on every run, which is what makes a
      // renamed parameter's tag follow the signature instead of rotting.
      if not ParamEmitted then Sb.AppendLine(EmitEngineParam(P));
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
      // PHASE C B7: the "deliberate blank slot" is no longer honoured. The user's
      // 2026-08-09 ruling is that an empty section is omitted, and a blank
      // <returns> is a blank tooltip like any other -- 2 of them in YADF, frozen
      // by exactly this preserve arm. A hand-written blank falls through to the
      // engine arm, which refills it from the mined cases or writes nothing.
      if ReturnsHandWritten and (not IsBlankBody(BodyReturns)) then
        // hand-written, with content -- preserved verbatim; its mined cases (if
        // any) went into the 'Returns:' fact line above (IncludeReturns) instead
        // of disturbing this text.
        Sb.AppendLine(EmitTagged('<returns>', BodyReturns, '</returns>'))
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
    // v(ADP3 T3h): BodyExample, the located standalone occurrence's own text
    // (still unstripped, for the reason just above).
    if StandaloneExample.HasExampleTag then
      Sb.AppendLine(EmitTagged('<example>', BodyExample, '</example>'));

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
    // v(ADP3 T3h): BodySince, the located standalone occurrence's own text. Note
    // this is also where register D11 stops being a loss: a SECOND <since> is now
    // a surplus occurrence, retracted by SplitResidualLines and carried through
    // verbatim below, instead of being accounted for and then never emitted.
    if StandaloneSince.HasSinceTag then
      Sb.AppendLine(EmitTagged('<since>', BodySince, '</since>'));

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
    // v(ADP3 T9): note whether the carried-through residual ALREADY contains a
    // <remarks> element of the author's. See ResidualCarriesRemarks' use below.
    var ResidualCarriesRemarks: Boolean:= False;
    for var ResidualLine in Residual do
    begin
      Sb.AppendLine(LinePrefix + ResidualLine);
      if not ResidualCarriesRemarks then
        ResidualCarriesRemarks:= ContainsText(ResidualLine, '<remarks');
    end;
    var LenAfterResidual: Integer:= Sb.Length;

    // v(ADP3 T9): DO NOT FABRICATE A SECOND <remarks> BESIDE THE AUTHOR'S.
    //
    // The shape (fixtures/docp3/guards.pas, UnfencedRemarksTail):
    //   /// <remarks>Plain hand prose, no fence, no marker.</remarks> <value>tail value</value>
    // T3f carries that whole line through VERBATIM, because the author's prose
    // shares the line with an unmodeled <value> tail. Carrying it through also
    // removes it from AccountedRaw, so Eff parses no remarks and Prose is ''
    // (which is why the author's prose is correctly emitted exactly once).
    // The harvester then had HarvestedRemarks <> '' with nowhere to put it, so
    // the emitter below opened a <remarks> of its OWN -- and the region ended
    // up with two sibling <remarks> elements, which is not well-formed
    // DocInsight. run_doc_p3_guards' "no <remarks> was fabricated beside the
    // author's" check names exactly this.
    //
    // The rule applied here is T8's, not a new one: HAND-WRITTEN WINS.
    // Harvested prose is the fallback for a symbol whose author wrote none --
    // an author who HAS written <remarks> outranks it. Nothing is destroyed by
    // dropping it either: the harvest is derived from a source comment that is
    // still sitting in the file, so it is recomputed, not lost.
    //
    // NARROW ON PURPOSE -- gated on Facts = ''. When there ARE facts, the fence
    // genuinely needs a <remarks> container and suppressing it would drop real
    // engine output; that case keeps its own element and is covered by the
    // idempotency sweep's NON-DESTRUCTIVE checks. This gate only removes an
    // element whose ENTIRE contents would have been the harvested paragraph.
    var HarvestedForEmit: string:= AFacts.HarvestedRemarks;
    if ResidualCarriesRemarks and (Facts = '') then
      HarvestedForEmit:= '';

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
    // v(ADP3 T3h): BodyRemarks, the located standalone occurrence's own prose.
    // The gate alone was not enough: on the SECOND apply cycle the region holds
    // BOTH the nested <remarks> and the engine's own (folded in by
    // MergeAdjacentSameKind), so the gate correctly said "a standalone <remarks>
    // exists" while Eff.Remarks still returned the NESTED one's text -- and
    // 'nested remarks' was duplicated into the engine's prose slot, above the
    // fence, unmarked, where --strip left it forever.
    var Prose: string:= '';
    if StandaloneRemarks.HasRemarksTag then
      Prose:= StripManagedBlock(BodyRemarks);
    var NormProse: string:= StringReplace(Trim(Prose), #13#10, #10, [rfReplaceAll]);
    NormProse:= StringReplace(NormProse, #13, #10, [rfReplaceAll]);
    // v(ADP3 T7): DROP AUTO_MARK-carrying lines from the preserved-prose slot.
    // Harvested remarks live inside <remarks> ABOVE the fence, so
    // StripManagedBlock -- which removes the AUTO_BEGIN..AUTO_END fence and
    // nothing else -- leaves them behind and they arrive here looking exactly
    // like hand-written prose. Re-emitted as prose AND regenerated by
    // EmitHarvestedRemarks below, the harvested paragraph DOUBLED on every
    // apply cycle: measured, cycle 2 of run_doc_p3_harvest_text.ps1 carried the
    // paragraph twice.
    //
    // This is the same defect shape the comment above describes for nested
    // <remarks>, and it takes the same marker-keyed answer the rest of this
    // unit uses: marked means engine-owned, so it is regenerated, never
    // preserved. Ownership changes hands by REMOVING the marker (v(ADP3 T3)) --
    // a human who deletes it keeps the line as their own prose, and the
    // harvester will not put it back because MergeComment no longer recognises
    // it as its own.
    if NormProse <> '' then
    begin
      // The harvested block is a RUN, not a set of individually marked lines.
      // EmitHarvestedRemarks marks only its FIRST line (so the emitted prose is
      // not littered with one HTML comment per line), which means a per-line
      // marker test kept paragraphs 2..N -- they arrived here looking
      // hand-written, were re-emitted as prose AND regenerated below, and the
      // block grew by its own length on EVERY apply cycle. Measured on
      // fixtures/docp3/tagoccurrence.pas: a constant +1501 bytes per cycle,
      // never converging. The original T7 fix was verified only against
      // harvest_text.pas, whose harvest is a single line, so it could not
      // surface this.
      //
      // Truncating at the first marked line is what TDocStripper's rule 1b
      // already does (delete from the marked line to the next tag/fence), and
      // the two verbs MUST agree or apply and strip diverge again. It is safe
      // for the same reason rule 1b states: MergeComment emits preserved
      // hand-written prose ABOVE this block and never below it, so everything
      // from the marker onward is engine-written continuation.
      var Kept: TStringBuilder:= TStringBuilder.Create;
      try
        for var PL in NormProse.Split([#10]) do
        begin
          if Pos(AUTO_MARK, PL) > 0 then Break;
          if Kept.Length > 0 then Kept.Append(#10);
          Kept.Append(PL);
        end;
        NormProse:= Trim(Kept.ToString);
      finally
        Kept.Free;
      end;
      Prose:= NormProse; // keep the two views in step -- both branches below read them
    end;
    // v(PHASE A1, ruling D-1): ... and now drop any harvested line the reader
    // would otherwise see TWICE -- once as preserved hand prose (or in the
    // hand-written summary), once regenerated below. See
    // DropAlreadyPresentPhrases for why the truncate-at-first-marker rule above
    // cannot catch this: the duplicate copy is the one whose marker a human
    // removed to take ownership of it.
    //
    // Placed AFTER the truncation, deliberately: the two rules compose in one
    // direction only. Truncation removes the engine's own still-marked tail, and
    // this then compares what a human genuinely owns against what is about to be
    // regenerated. Reversed, it would compare against text the truncation was
    // going to delete anyway and drop harvested prose that had no duplicate.
    HarvestedForEmit:= DropAlreadyPresentPhrases(HarvestedForEmit,
                                                 NormProse + #10 + SummaryRaw);
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
    // v(ADP3 T7): ... and no harvested prose to place above a fence. The
    // one-line form has nowhere to put a second, marked paragraph, so harvested
    // remarks take the multi-line path below exactly as Facts already do.
    if (Trim(Prose) <> '') and (Facts = '') and (HarvestedForEmit = '') and (not NormProse.Contains(#10)) then
      Sb.AppendLine(APrefix + '<remarks>' + Trim(Prose) + '</remarks>')
    else if (Trim(Prose) <> '') or (Facts <> '') or (HarvestedForEmit <> '') then
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
      // v(ADP3 T7): after the preserved hand prose, before the fence.
      // v(ADP3 T9): HarvestedForEmit, not AFacts.HarvestedRemarks -- see the
      // "DO NOT FABRICATE A SECOND <remarks>" comment above.
      EmitHarvestedRemarks(Sb, APrefix, HarvestedForEmit);
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
