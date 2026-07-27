unit tagoccurrence;

interface

// v(ADP3 T3h) fixture for register item N2 + D11: the SINGULAR-MATCH tag reads.
//
// ParseXmlDoc reads <summary>/<returns>/<remarks>/<example>/<deprecated>/
// <since> with a singular .Match, so TParsedDoc holds exactly ONE body per
// tag -- the textually FIRST occurrence in the region, nested or not. Two
// symptoms follow, and both are here:
//
//   (a) WRONG OCCURRENCE. The emitter takes PRESENCE from a filtered view
//       (BuildStandaloneFor, which removes nested look-alikes) but CONTENT
//       from the unfiltered singular field -- so presence can describe one
//       occurrence and content a different one. The nested look-alike's text
//       is then written out at the genuine, standalone tag's slot, UNMARKED,
//       so `document --strip` cannot remove it. NestedReturnsInDeprecated /
//       NestedRemarksInExample.
//
//   (b) SURPLUS OCCURRENCE. Occurrences past the first are silently deleted:
//       T3f's residual mask accounts for EVERY match of a container pattern
//       while the parse represents only ONE, so the second one is accounted
//       (hence not carried through verbatim) and then never emitted.
//       TwoSinceTags (register D11) / TwoSummaryTags / TwoReturnsTags.
//
// Note (b) needs NO MergeAdjacentSameKind fold: both tags sit in ONE authored
// region. That is what rules the fold out as the fix site -- it multiplies
// instances of the defect, it does not cause it.
//
// The last three shapes are CONTROLS for the two directions a fix can be
// wrong in. NestedTagsInSummary guards the LOSSY direction (reading content
// from the stripped view mangles anything legitimately nested inside a
// genuinely standalone tag); PrefixProseEmptySummary guards ParseXmlDoc's own
// untagged-prefix fallback (an empty located body must defer to it, not
// blank the summary); PlainDocumented guards the ordinary shape against churn.

// --- (a) WRONG OCCURRENCE --------------------------------------------------

/// <deprecated>dep <returns>nested returns text</returns> tail</deprecated>
function NestedReturnsInDeprecated: Integer;

procedure CallsNestedReturnsInDeprecated;

/// <example>ex <remarks>nested remarks</remarks> tail</example>
procedure NestedRemarksInExample;

procedure CallsNestedRemarksInExample;

// --- (b) SURPLUS OCCURRENCE ------------------------------------------------

/// <since>1.0</since>
/// <since>2.0</since>
procedure TwoSinceTags;

procedure CallsTwoSinceTags;

/// <summary>First summary.</summary>
/// <summary>Second summary the author also wrote.</summary>
procedure TwoSummaryTags;

procedure CallsTwoSummaryTags;

/// <returns>First returns.</returns>
/// <returns>Second returns the author also wrote.</returns>
function TwoReturnsTags: Integer;

procedure CallsTwoReturnsTags;

// TWO different tags each with a surplus, in ONE comment. The occurrence counter
// must reset per tag: if it carried over, the second tag's FIRST occurrence
// would be miscounted as surplus and retracted -- which still preserves the text
// (it comes back verbatim), so the damage would be a silent position change
// rather than a loss, and a per-tag fixture is the only thing that sees it.

/// <since>1.0</since>
/// <since>2.0</since>
/// <summary>First summary here.</summary>
/// <summary>Second summary here.</summary>
procedure TwoSinceAndTwoSummary;

procedure CallsTwoSinceAndTwoSummary;

// <remarks> is the ONE singular container whose surplus occurrence is NOT
// handed back, and these two shapes pin that -- with facts and without, so the
// outcome is visibly uniform rather than looking facts-dependent.
//
// The reason is structural: <remarks> is the only modeled tag MergeComment emits
// AFTER the carried-through residual block, so retracting a surplus <remarks>
// moves it AHEAD of the occurrence that keeps the slot, the next scan reads the
// OTHER one as occurrence 1, and the two swap on every run. That was MEASURED
// here first -- these two shapes oscillated md5 A/B/A across three cycles while
// the retraction set was still every singular container -- and a period-2
// permutation is a hard violation of the branch's zero-byte-diff criterion. So a
// surplus <remarks> stays accounted and its text is still lost, exactly as
// before Task 3h: no better, no worse, and no longer able to oscillate.
// See DRagLint.Doc.Regions.pas' IsRetractableSurplusContainer.

/// <remarks>First remarks.</remarks>
/// <remarks>Second remarks the author also wrote.</remarks>
procedure TwoRemarksNoFacts;

/// <remarks>First remarks.</remarks>
/// <remarks>Second remarks the author also wrote.</remarks>
procedure TwoRemarksWithFacts;

procedure CallsTwoRemarksWithFacts;

// --- CONTROLS -------------------------------------------------------------

/// <summary>Body with an inline <exception cref="EIn">inline desc</exception> tail.</summary>
procedure NestedTagsInSummary;

procedure CallsNestedTagsInSummary;

/// Leading prose the fallback adopts.
/// <summary></summary>
procedure PrefixProseEmptySummary;

procedure CallsPrefixProseEmptySummary;

// The same control ON the filtered-view path, which is where the located read
// actually runs: the <since> trips MergeComment's HasAnySignal gate, so content
// comes from StandaloneBodyOf rather than straight off the parse. The <summary>
// body is WHITESPACE, not empty -- an empty one is caught by the length guard
// before normalization, so only a whitespace body reaches the rule that an empty
// located body must DEFER to ParseXmlDoc's untagged-prefix fallback instead of
// overriding it. Drop that rule and this shape's prose is replaced by an empty
// <summary> the author never wrote.
/// Leading prose beside an exotic tag.
/// <summary>  </summary>
/// <since>3.0</since>
procedure PrefixProseBlankSummaryExotic;

procedure CallsPrefixProseBlankSummaryExotic;

// The <remarks> is written MULTI-LINE deliberately: with facts to fence, the
// emitter always takes the multi-line path, so a single-line author <remarks>
// would be reformatted and could not round-trip through --strip (a documented,
// pre-existing v(ADP3 T2) behaviour, not this task's subject).
/// <summary>Plain documented routine; nothing exotic.</summary>
/// <param name="AValue">The value.</param>
/// <returns>Twice AValue.</returns>
/// <remarks>
/// Hand prose.
/// </remarks>
function PlainDocumented(AValue: Integer): Integer;

procedure CallsPlainDocumented;

implementation

function NestedReturnsInDeprecated: Integer;
begin
  Result:= 1;
end;

procedure CallsNestedReturnsInDeprecated;
begin
  NestedReturnsInDeprecated;
end;

procedure NestedRemarksInExample;
begin
end;

procedure CallsNestedRemarksInExample;
begin
  NestedRemarksInExample;
end;

procedure TwoSinceTags;
begin
end;

procedure CallsTwoSinceTags;
begin
  TwoSinceTags;
end;

procedure TwoSummaryTags;
begin
end;

procedure CallsTwoSummaryTags;
begin
  TwoSummaryTags;
end;

function TwoReturnsTags: Integer;
begin
  Result:= 7;
end;

procedure CallsTwoReturnsTags;
begin
  TwoReturnsTags;
end;

procedure TwoSinceAndTwoSummary;
begin
end;

procedure CallsTwoSinceAndTwoSummary;
begin
  TwoSinceAndTwoSummary;
end;

procedure TwoRemarksNoFacts;
begin
end;

procedure TwoRemarksWithFacts;
begin
end;

procedure CallsTwoRemarksWithFacts;
begin
  TwoRemarksWithFacts;
end;

procedure NestedTagsInSummary;
begin
end;

procedure CallsNestedTagsInSummary;
begin
  NestedTagsInSummary;
end;

procedure PrefixProseEmptySummary;
begin
end;

procedure CallsPrefixProseEmptySummary;
begin
  PrefixProseEmptySummary;
end;

procedure PrefixProseBlankSummaryExotic;
begin
end;

procedure CallsPrefixProseBlankSummaryExotic;
begin
  PrefixProseBlankSummaryExotic;
end;

function PlainDocumented(AValue: Integer): Integer;
begin
  Result:= AValue * 2;
end;

procedure CallsPlainDocumented;
begin
  PlainDocumented(1);
end;

end.
