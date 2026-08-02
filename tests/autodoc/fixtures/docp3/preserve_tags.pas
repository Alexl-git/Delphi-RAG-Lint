unit preserve_tags;

// ===========================================================================
// CASE NOTES -- why each shape below exists.
//
// These notes used to sit directly above their own declarations. They cannot
// live there any more: v(ADP3 T7) harvests an interface-side // comment that is
// adjacent-above a declaration into that symbol's <summary>, so test COMMENTARY
// became test DATA -- it was published as documentation, and it broke every
// assertion phrased as "no <summary> was fabricated here". They were deleted
// outright to get the suites green; that discarded the rationale for ~30 subtle
// cases, so they are restored here instead.
//
// This position is harvest-proof BY CONSTRUCTION, not by luck: HarvestScan walks
// UP from a declaration and stops at the first line of code, and the `interface`
// keyword below is code. Blank lines do NOT stop it (they are accumulated and
// then trimmed), which is why merely spacing the comments out did not work.
// ===========================================================================
// Phase 3, Task 3b: MergeComment's repair path re-emitted only <summary>/
// <param>/<returns> and hand-written <remarks> prose -- every OTHER
// hand-written tag it parsed (<exception>/<example>/<since>/<deprecated/>/
// <seealso>) was silently dropped the moment the repair path ran for any
// reason (see task-3b-brief.md). Each symbol below is given a CALLER so
// Facts is non-empty and Merged is forced non-empty too -- a fact-FREE
// comment carrying only one of these tags is already left untouched by
// Task 3's RegionFullyEngineOwned guard (daUnchanged), so a fact-free test
// would pass whether or not this fix exists (verified empirically against
// the pre-fix exe: run_doc_p3_unhandledtags.ps1's HasException case).
//
// Tags are written in the SAME fixed order TDocRegions.MergeComment's
// repair path emits them in (see its own code comment): <summary> ->
// <deprecated/> -> <param>s -> <returns> -> <exception>s -> <example> ->
// <seealso>s -> <since> -> <remarks>. This is required for the strip
// round-trip scenario in the runner: `document --apply` reorders everything
// into this fixed order, so the fixture must already be written in it for
// `document --strip --apply` to recover these EXACT original bytes.

// ONLY <exception>, WITH a caller: Facts.CalledFrom is non-empty, so Merged
// is forced non-empty by the facts alone and the UNGUARDED delete+insert
// repair branch runs directly (not the Merged='' branch RegionFullyEngineOwned
// guards) -- this is "Task 3's delete branch made destructive", reproduced.
// No fabrication: a plain hand-written summary, none of the five tags. The
// hand-written summary alone already routes this through the repair path
// (ExistingHasAnyTag is True from HasSummaryTag), so this proves the repair
// path does not fabricate any of the five even when it genuinely runs.
// Dispatch-sniff isolation (Task 3b brief's "second known trap"): every
// OTHER symbol above ALSO carries <summary> or <exception>, both of which
// were ALREADY in HasXmlTags' sniff before this task, so none of them
// actually exercise the sniff fix on their own -- a comment whose ONLY tag
// is <deprecated/> (bare, no <summary>/<param>/<returns>/<remarks>/
// <exception>/<example> alongside it) is the genuinely isolating case:
// pre-fix, Dispatch mis-routes this to ParseOneline (the literal text
// '<deprecated/>' becomes a bogus "summary"), so a repair pass would wrap
// it as '<summary><deprecated/></summary>' -- nonsensical, and NOT the
// same failure as the tag simply being dropped. WITH a caller so the
// repair path has something else to say too (proving this is a genuine
// merge, matching ExceptionOnlyHasCaller's own reasoning above).
// Review round 1, Critical 1: an inline <see cref="X"/> AND an inline
// <exception cref="Y">desc</exception>, BOTH nested inside <summary> prose
// (not top-level siblings) -- reproduces the defect found on this repo's
// own src/report/DRagLint.Convert.Rules.pas (TConversionRule's <summary>
// carries an inline <see cref="Kind"/>). MergeComment preserves <summary>
// verbatim (including these inline mentions, exactly as authored); neither
// inline tag may ALSO be re-emitted as a standalone <seealso>/<exception>
// sibling, and the count must not grow across a THIRD apply cycle (see the
// runner's PART 3 for the byte-identity check from cycle 2 on -- unlike
// every other symbol above, this is the ONE case where growth, not
// disappearance, was the failure mode, so idempotency itself is the
// regression test here). WITH a caller so the repair path genuinely runs.
// Review round 2, Critical 1 STILL OPEN: round 1 only protected nesting
// inside <summary>/<param>/<returns>/<remarks> -- <exception>/<example>/
// <deprecated> ALSO preserve their own content verbatim and were left
// unprotected, so a tag nested inside ANY of THOSE was still captured
// twice (confirmed: 4 apply cycles growing unbounded on this repo's own
// review-supplied repro). These three cover exception/example/deprecated
// as the OUTER container (the review's own minimum ask); <since> nested
// inside <exception> (the ONE ".Match-backed", stabilizes-at-2-not-N
// signature, rather than unbounded growth) is ALSO covered here since it
// behaves differently from the others. <seealso> nested inside <example>
// and inside <deprecated> were ALSO verified fixed, empirically, against a
// throwaway scratch fixture (not enshrined as separate rows here since the
// underlying mechanism -- BuildStandaloneFor's canonical container list --
// is the same one already exercised by the three rows below; see the task
// report for that verification).
// Review round 1, Important 2: the MESSAGE on a hand-written
// <deprecated>message</deprecated> must survive, not collapse to a bare
// <deprecated/>. Also exercises the GAPPED comment shape (a blank line
// between the comment and the declaration) -- every OTHER symbol in this
// fixture abuts its declaration, and the brief's own table names both
// shapes.
// Review round 1, Critical 1 (second symptom): a BARE, standalone
// <see cref="X"/> (NOT nested inside anything, NOT <seealso>) must
// round-trip as <see>, never silently rewritten to <seealso> -- RxSee's
// own (?:see|seealso) alternation conflates both spellings into one
// SeeAlso array; re-emitting every entry as <seealso> would destroy the
// author's <see> and fabricate a <seealso> they never wrote (a destruction
// AND a fabrication, since the two tags render differently).
// Review round 1, Important 3: Dispatch's tightened sniff must not
// over-match plain prose that merely resembles a tag -- these three mirror
// the review's own near-miss table exactly. NO caller: HasSummaryTag alone
// (from the oneline/prose parse) already forces the repair path when the
// sniff correctly leaves these as plain prose; a caller would only add an
// unrelated facts block and dilute what the assertion is checking (whether
// the FULL original text survives, untruncated).
// Review round 1, Minor 1: a deliberately EMPTY <example></example> (a
// human's blank slot, the same concept <summary></summary> already
// preserves) must survive, not be dropped -- the old gate (ExampleText <>
// '') could not distinguish "the tag is absent" from "present but empty";
// HasExampleTag (mirroring HasSummaryTag) makes that distinction. WITH a
// caller so the repair path genuinely runs.
// Review round 2, NEW IMPORTANT: a comment Dispatch routes to XML parsing
// (because it LOOKS tag-shaped) can still resolve to NO recognized tag at
// all, when the shape is malformed in a way neither the sniff nor the
// underlying regex tolerates. Before this fix, ParseXmlDoc's own untagged-
// prefix-becomes-summary fallback then read '' for Summary too (nothing
// precedes a malformed tag that opens the comment), HasContent came back
// False, and MergeComment/BuildForSymbol emitted NOTHING -- silently
// DELETING the entire hand-written /// line the moment a facts block later
// merged adjacent to it (confirmed empirically: this needs a SECOND apply
// cycle to surface, since MergeAdjacentSameKind is what first folds the
// freshly-inserted facts block into the same scanned region, which is what
// flips HasContent to True and routes the comment into the unconditional
// repair-delete-insert branch -- worse than Task 3's OWN known growth-only
// trap, since here cycle 1 looks completely safe). Each row below is WITH a
// caller, matching every other load-bearing case in this fixture.
// Pos() is case-sensitive; every regex in this unit carries roIgnoreCase --
// the OLD hand-maintained sniff mismatched on this axis too. Correctly
// recognized, this round-trips as a genuine <deprecated/> (canonical
// lowercase spelling, NOT wrapped in a fabricated <summary>).
// RxException requires cref="..."; the bare '<exception' prefix sniff (pre-
// dating this task) does not, so this was ALREADY a sniff/parse mismatch
// before round 2 -- the general "no recognized tag at all" fallback closes
// it as a side effect, without needing an exception-specific sniff change.
// A malformed <seealso> with no cref, SITTING ALONGSIDE a real, well-formed
// <summary> -- the summary (and the whole comment) is NOT deleted. The
// malformed seealso fragment is captured by nothing (RxSee requires
// cref="..." too), so it is "unmodeled tag" territory -- Task 3b left it out
// of scope and its non-round-trip was pinned as an accepted gap.
// v(ADP3 T3f): closed. The emitter accounts for nothing on that line, so the
// residual carry-through hands the whole line back verbatim, exactly as it
// does for <value>.
// A TAB (not a space) between the tag name and its cref attribute -- RxSee's
// own '\s+' already tolerates this (a real regex-vs-sniff mismatch: the OLD
// sniff's literal '<seealso '  -- one literal space -- did not). SeeAlso
// presence alone does not satisfy Document.pas' ExistingHasAnyTag (same
// narrow OR-chain BareSeeOnly above already exercises), so cycle 1 takes the
// fresh/additive path and leaves this line untouched; cycle 2 is where
// MergeAdjacentSameKind folds the facts block in and the repair path
// actually normalizes the tab to a canonical single space.
// Review round 3, NEW IMPORTANT: <since> read its body from a STRIPPED
// parse, so nested content was silently deleted -- and one shape deleted the
// ENTIRE hand-written comment (<since> strips 'deprecated' so SinceText
// became '' and failed the old content-based gate; <deprecated> strips
// 'since' so Deprecated became False and failed ITS gate -- both tags
// vanished simultaneously). Each row below reads back correctly and never
// loses content: SinceWithNestedException/SinceWithNestedDeprecated ALSO
// force the repair path immediately (the nested tag makes Exceptions.
// Length>0/Deprecated true, both already part of Document.pas'
// ExistingHasAnyTag via HasContent), so they are stable byte-for-byte from
// cycle 1. SinceWithNestedExample is the one exception: HasExampleTag is
// NOT part of HasContent's OR-chain (same narrow-by-design exclusion
// TabSeparatedSeeAlso's own bare <seealso/> hits above), so cycle 1 takes
// the fresh/additive path (the original line untouched, a facts block
// merely added beside it) -- Test-ThreeCycleNesting's "cycle 1" assertion
// still holds (the untouched original trivially contains the expected
// text), and cycles 2/3 confirm the SAME content survives once
// MergeAdjacentSameKind folds the two into one region and the repair path
// genuinely runs on it.
// Review round 3, STRUCTURAL 1: round 2 wired the "presence from a stripped
// view, content from AExisting" protection into only FOUR of the eight
// preserved containers (exception/example/deprecated/since) -- the emitters
// for the other four (summary/param/returns/remarks) still read AExisting
// directly, unconditionally, so a nested occurrence of ONE of those four
// inside one of the rich-body four still fabricated a standalone sibling
// tag the author never wrote. Each row below is stable, byte-identical, from
// the FIRST apply cycle.
// v(ADP3 T3b review round 3, STRUCTURAL 1 -- was a DISCLOSED RESIDUAL, FIXED
// by v(ADP3 T3h) / register N2). T3b fixed the FIRST apply cycle -- the nested
// <returns> text survives verbatim inside <deprecated>, unmangled, and no
// standalone <returns> is fabricated from it -- but a deeper issue surfaced from
// the SECOND cycle on: this function's AHasReturn=True means the "engine-owned,
// refill from mined cases" branch ALSO adds a genuine, standalone, auto-marked
// <returns> tag on cycle 1 (a real, separate signal, correctly independent of
// the deprecated tag). MergeAdjacentSameKind then folds that freshly-inserted
// tag into the SAME scanned region on cycle 2's scan, so the comment holds TWO
// <returns>-shaped spans (the nested one textually FIRST, the new standalone one
// SECOND) -- and RxReturns' '.Match()' takes the first. The presence gate
// correctly described the standalone occurrence while the content read described
// the nested one, so the nested text was emitted at the standalone slot,
// UNMARKED, where `document --strip` could never remove it.
//
// T3h did NOT teach the parser to return offsets (TParsedDoc is index-facing;
// its consumers are the indexer, LSP/MCP hover, the context bundler and drift).
// Instead MergeComment locates the occurrence its OWN presence gate is True
// about, by masking the other containers LENGTH-PRESERVINGLY -- the same spans
// BuildStandaloneFor already strips, so "nested look-alike" keeps exactly the
// definition every presence gate here already uses -- and reads the body back
// out of the ORIGINAL text at that occurrence's offsets, so a tag legitimately
// nested inside a genuinely standalone one still survives verbatim. See
// TDocRegions.StandaloneBodyOf. This row now asserts 3-cycle stability AND the
// strip round-trip, like every other nesting row.
// v(ADP3 T3b review round 3, STRUCTURAL 1 -- was a DISCLOSED RESIDUAL, same
// class as DeprecatedWithNestedReturns above, FIXED by v(ADP3 T3h)): cycle 1 was
// already stable (no fabrication -- "nested remarks" stays inside <example>, and
// a SEPARATE, genuine <remarks> facts block is added, not conflated with it).
// From cycle 2 on, the same MergeAdjacentSameKind-induced compounding applied:
// the freshly-inserted facts <remarks> block folds into the same region,
// <remarks> has no natural key either, and RxRemarks' '.Match()' picked the
// textually-first <remarks> span (the one nested inside <example>) as the prose,
// so "nested remarks" got duplicated above the fence -- unmarked, so a strip left
// a <remarks> element the author never wrote. See DeprecatedWithNestedReturns'
// own comment for how T3h closed it.
  // Hand-written <since>/<seealso> COEXISTING with the opt-in auto-generated
  // <since>/<seealso> RenderFactsBlock emits INSIDE the AUTO_BEGIN..AUTO_END
  // fence (see its own comment): the parser's regexes do not respect the
  // fence boundary (Task 3b brief's Trap 1), so a naive preserve-loop would
  // re-emit the fence-internal auto lines a SECOND time outside the fence,
  // and since RenderFactsBlock regenerates the same auto lines inside the
  // fence every run regardless, the duplicate would grow without bound.
  // DoB/DoC are DoA's resolved callees AND its siblings, so --seealso gives
  // DoA an auto <seealso> set of its own; DoA's declaration line, once
  // committed to git, gives --since a real commit date to derive.

interface

/// <summary>Doubles AValue; hand-written summary must survive.</summary>
/// <deprecated/>
/// <param name="AValue">Hand-written param desc; must survive.</param>
/// <returns>The doubled value.</returns>
/// <exception cref="EFoo">Raised when AValue is negative.</exception>
/// <example>AllTags(21) returns 42.</example>
/// <seealso cref="Other.RelatedThing"/>
/// <since>1.2</since>
function AllTags(AValue: Integer): Integer;

procedure CallsAllTags;

/// <exception cref="EBar">Raised on bad input.</exception>
procedure ExceptionOnlyHasCaller;

procedure CallsExceptionOnly;

/// <summary>Plain summary; no exotic tags here.</summary>
procedure NoExoticTags;

/// <deprecated/>
procedure BareDeprecatedOnly;

procedure CallsBareDeprecatedOnly;

/// <summary>Uses <see cref="Other.RelatedThing"/> for related lookups and
/// can raise <exception cref="ENested">a nested, inline description</exception>
/// in edge cases.</summary>
procedure NestedTagsInSummary;

procedure CallsNestedTagsInSummary;

/// <deprecated>Use <see cref="Other.RelatedThing"/> instead of this old thing.</deprecated>
procedure NestedInDeprecated;

procedure CallsNestedInDeprecated;

/// <exception cref="EOuter">Added in <since>2.0</since> and still raised today.</exception>
procedure NestedSinceInException;

procedure CallsNestedSinceInException;

/// <example>Sample usage. <exception cref="EInExample">boom</exception> can happen.</example>
procedure NestedExceptionInExample;

procedure CallsNestedExceptionInExample;

/// <deprecated>Use Rev instead; this will be removed in 2.0.</deprecated>

procedure GappedDeprecatedMessage;

procedure CallsGappedDeprecatedMessage;

/// <see cref="Other.RelatedThing"/>
procedure BareSeeOnly;

procedure CallsBareSeeOnly;

/// Plain prose that mentions <seealso> without any cref, plus trailing words.
procedure ProseMentionsSeeAlso;
/// Grows the <seed> lookup table by one bucket.
procedure ProseMentionsSeed;
/// Marks the routine <deprecatedSoon> but not really.
procedure ProseMentionsDeprecatedSoon;

/// <summary>Has a deliberately blank example slot.</summary>
/// <example></example>
procedure EmptyExampleSurvives;

procedure CallsEmptyExampleSurvives;

/// <deprecated >Space before the closing angle bracket.</deprecated>
procedure SpaceBeforeCloseDeprecated;

procedure CallsSpaceBeforeCloseDeprecated;

/// <deprecated>No closing tag at all, just trailing words
procedure UnclosedDeprecated;

procedure CallsUnclosedDeprecated;

/// <DEPRECATED>Recognized case-insensitively.</DEPRECATED>
procedure AllCapsDeprecatedTag;

procedure CallsAllCapsDeprecatedTag;

/// <exception>Missing the required cref attribute.</exception>
procedure ExceptionNoCrefAttr;

procedure CallsExceptionNoCrefAttr;

/// <summary>Has a real, well-formed summary.</summary>
/// <seealso>Missing the required cref, sitting alongside a real tag.</seealso>
procedure SeeAlsoNoCrefWithSummary;

procedure CallsSeeAlsoNoCrefWithSummary;

/// <example>Unclosed example body, no closing tag
procedure UnclosedExampleTag;

procedure CallsUnclosedExampleTag;

/// <seealso	cref="Other.RelatedThing"/>
procedure TabSeparatedSeeAlso;

procedure CallsTabSeparatedSeeAlso;

/// <since>1.0 <exception cref="EInSince">x</exception></since>
procedure SinceWithNestedException;

procedure CallsSinceWithNestedException;

/// <since>2.0 <example>see the sample below</example> onwards</since>
procedure SinceWithNestedExample;

procedure CallsSinceWithNestedExample;

/// <since><deprecated>2.0-beta</deprecated></since>
procedure SinceWithNestedDeprecated;

procedure CallsSinceWithNestedDeprecated;

/// <exception cref="E1">exc text <summary>nested summary</summary> tail</exception>
procedure ExceptionWithNestedSummary;

procedure CallsExceptionWithNestedSummary;

/// <example>Ex <param name="AV">nested param desc</param> body.</example>
procedure ExampleWithNestedParam(AV: Integer);

procedure CallsExampleWithNestedParam;

/// <deprecated>dep <returns>nested returns text</returns> tail</deprecated>
function DeprecatedWithNestedReturns: Integer;

procedure CallsDeprecatedWithNestedReturns;

/// <example>ex <remarks>nested remarks</remarks> tail</example>
procedure ExampleWithNestedRemarks;

procedure CallsExampleWithNestedRemarks;

type
  TSeeAlsoHost = class
  public
    /// <summary>Does A.</summary>
    /// <since>1.0-hand</since>
    /// <seealso cref="Unrelated.HandWritten"/>
    procedure DoA;
    procedure DoB(AValue: Integer);
    procedure DoC(AText: string);
  end;

implementation

function AllTags(AValue: Integer): Integer;
begin
  Result := AValue * 2;
end;

procedure CallsAllTags;
begin
  AllTags(21);
end;

procedure ExceptionOnlyHasCaller;
begin
end;

procedure CallsExceptionOnly;
begin
  ExceptionOnlyHasCaller;
end;

procedure NoExoticTags;
begin
end;

procedure BareDeprecatedOnly;
begin
end;

procedure CallsBareDeprecatedOnly;
begin
  BareDeprecatedOnly;
end;

procedure NestedTagsInSummary;
begin
end;

procedure CallsNestedTagsInSummary;
begin
  NestedTagsInSummary;
end;

procedure NestedInDeprecated;
begin
end;

procedure CallsNestedInDeprecated;
begin
  NestedInDeprecated;
end;

procedure NestedSinceInException;
begin
end;

procedure CallsNestedSinceInException;
begin
  NestedSinceInException;
end;

procedure NestedExceptionInExample;
begin
end;

procedure CallsNestedExceptionInExample;
begin
  NestedExceptionInExample;
end;

procedure GappedDeprecatedMessage;
begin
end;

procedure CallsGappedDeprecatedMessage;
begin
  GappedDeprecatedMessage;
end;

procedure BareSeeOnly;
begin
end;

procedure CallsBareSeeOnly;
begin
  BareSeeOnly;
end;

procedure ProseMentionsSeeAlso;
begin
end;

procedure ProseMentionsSeed;
begin
end;

procedure ProseMentionsDeprecatedSoon;
begin
end;

procedure EmptyExampleSurvives;
begin
end;

procedure CallsEmptyExampleSurvives;
begin
  EmptyExampleSurvives;
end;

procedure SpaceBeforeCloseDeprecated;
begin
end;

procedure CallsSpaceBeforeCloseDeprecated;
begin
  SpaceBeforeCloseDeprecated;
end;

procedure UnclosedDeprecated;
begin
end;

procedure CallsUnclosedDeprecated;
begin
  UnclosedDeprecated;
end;

procedure AllCapsDeprecatedTag;
begin
end;

procedure CallsAllCapsDeprecatedTag;
begin
  AllCapsDeprecatedTag;
end;

procedure ExceptionNoCrefAttr;
begin
end;

procedure CallsExceptionNoCrefAttr;
begin
  ExceptionNoCrefAttr;
end;

procedure SeeAlsoNoCrefWithSummary;
begin
end;

procedure CallsSeeAlsoNoCrefWithSummary;
begin
  SeeAlsoNoCrefWithSummary;
end;

procedure UnclosedExampleTag;
begin
end;

procedure CallsUnclosedExampleTag;
begin
  UnclosedExampleTag;
end;

procedure TabSeparatedSeeAlso;
begin
end;

procedure CallsTabSeparatedSeeAlso;
begin
  TabSeparatedSeeAlso;
end;

procedure SinceWithNestedException;
begin
end;

procedure CallsSinceWithNestedException;
begin
  SinceWithNestedException;
end;

procedure SinceWithNestedExample;
begin
end;

procedure CallsSinceWithNestedExample;
begin
  SinceWithNestedExample;
end;

procedure SinceWithNestedDeprecated;
begin
end;

procedure CallsSinceWithNestedDeprecated;
begin
  SinceWithNestedDeprecated;
end;

procedure ExceptionWithNestedSummary;
begin
end;

procedure CallsExceptionWithNestedSummary;
begin
  ExceptionWithNestedSummary;
end;

procedure ExampleWithNestedParam(AV: Integer);
begin
end;

procedure CallsExampleWithNestedParam;
begin
  ExampleWithNestedParam(1);
end;

function DeprecatedWithNestedReturns: Integer;
begin
  Result:= 1;
end;

procedure CallsDeprecatedWithNestedReturns;
begin
  DeprecatedWithNestedReturns;
end;

procedure ExampleWithNestedRemarks;
begin
end;

procedure CallsExampleWithNestedRemarks;
begin
  ExampleWithNestedRemarks;
end;

procedure TSeeAlsoHost.DoA;
begin
  DoB(1);
  DoC('x');
end;

procedure TSeeAlsoHost.DoB(AValue: Integer);
begin
  Writeln(AValue);
end;

procedure TSeeAlsoHost.DoC(AText: string);
begin
  Writeln(AText);
end;

end.
