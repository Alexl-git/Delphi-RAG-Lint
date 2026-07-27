unit preserve_tags;

interface

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

// ONLY <exception>, WITH a caller: Facts.CalledFrom is non-empty, so Merged
// is forced non-empty by the facts alone and the UNGUARDED delete+insert
// repair branch runs directly (not the Merged='' branch RegionFullyEngineOwned
// guards) -- this is "Task 3's delete branch made destructive", reproduced.
/// <exception cref="EBar">Raised on bad input.</exception>
procedure ExceptionOnlyHasCaller;

procedure CallsExceptionOnly;

// No fabrication: a plain hand-written summary, none of the five tags. The
// hand-written summary alone already routes this through the repair path
// (ExistingHasAnyTag is True from HasSummaryTag), so this proves the repair
// path does not fabricate any of the five even when it genuinely runs.
/// <summary>Plain summary; no exotic tags here.</summary>
procedure NoExoticTags;

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
/// <deprecated/>
procedure BareDeprecatedOnly;

procedure CallsBareDeprecatedOnly;

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
/// <summary>Uses <see cref="Other.RelatedThing"/> for related lookups and
/// can raise <exception cref="ENested">a nested, inline description</exception>
/// in edge cases.</summary>
procedure NestedTagsInSummary;

procedure CallsNestedTagsInSummary;

// Review round 1, Important 2: the MESSAGE on a hand-written
// <deprecated>message</deprecated> must survive, not collapse to a bare
// <deprecated/>. Also exercises the GAPPED comment shape (a blank line
// between the comment and the declaration) -- every OTHER symbol in this
// fixture abuts its declaration, and the brief's own table names both
// shapes.
/// <deprecated>Use Rev instead; this will be removed in 2.0.</deprecated>

procedure GappedDeprecatedMessage;

procedure CallsGappedDeprecatedMessage;

// Review round 1, Critical 1 (second symptom): a BARE, standalone
// <see cref="X"/> (NOT nested inside anything, NOT <seealso>) must
// round-trip as <see>, never silently rewritten to <seealso> -- RxSee's
// own (?:see|seealso) alternation conflates both spellings into one
// SeeAlso array; re-emitting every entry as <seealso> would destroy the
// author's <see> and fabricate a <seealso> they never wrote (a destruction
// AND a fabrication, since the two tags render differently).
/// <see cref="Other.RelatedThing"/>
procedure BareSeeOnly;

procedure CallsBareSeeOnly;

// Review round 1, Important 3: Dispatch's tightened sniff must not
// over-match plain prose that merely resembles a tag -- these three mirror
// the review's own near-miss table exactly. NO caller: HasSummaryTag alone
// (from the oneline/prose parse) already forces the repair path when the
// sniff correctly leaves these as plain prose; a caller would only add an
// unrelated facts block and dilute what the assertion is checking (whether
// the FULL original text survives, untruncated).
/// Plain prose that mentions <seealso> without any cref, plus trailing words.
procedure ProseMentionsSeeAlso;
/// Grows the <seed> lookup table by one bucket.
procedure ProseMentionsSeed;
/// Marks the routine <deprecatedSoon> but not really.
procedure ProseMentionsDeprecatedSoon;

// Review round 1, Minor 1: a deliberately EMPTY <example></example> (a
// human's blank slot, the same concept <summary></summary> already
// preserves) must survive, not be dropped -- the old gate (ExampleText <>
// '') could not distinguish "the tag is absent" from "present but empty";
// HasExampleTag (mirroring HasSummaryTag) makes that distinction. WITH a
// caller so the repair path genuinely runs.
/// <summary>Has a deliberately blank example slot.</summary>
/// <example></example>
procedure EmptyExampleSurvives;

procedure CallsEmptyExampleSurvives;

type
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
