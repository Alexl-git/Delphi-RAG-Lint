unit unhandledtags;

interface

/// <exception cref="EFoo">Boom.</exception>
procedure HasException;

// NOTE on this one comment combining FOUR tags: SinceText/SeeAlso/
// ExampleText alone do NOT set TParsedDoc.HasContent (a separate, pre-
// existing gap outside Finding 3/4's exact scope -- HasContent's OR-chain
// never included them, and the review round 2 fix only widened a LOCAL
// BuildForSymbol predicate, never HasContent itself). Pairing them with
// <deprecated/> (which DOES set HasContent, via Result.Deprecated) is what
// actually routes this comment through the repair path so the empty-merge
// delete guard is genuinely exercised for all four fields at once, rather
// than being trivially safe via HasContent already being False (the
// vacuous-test bug review round 2 flagged for a bare HasExample case: it
// passed identically with or without the guard, because the guard's OUTER
// precondition -- Existing.HasContent -- was never even satisfied, so
// RegionFullyEngineOwned was never exercised). The empty <remarks></remarks>
// is ALSO required for <since>/<seealso> specifically: a separate
// workaround for a SEPARATE, pre-existing, unfixed defect (flagged in the
// Task 3 fix report, not fixed here) -- TDocCommentParser.Dispatch's
// HasXmlTags sniff does not recognize <since>/<seealso>/<deprecated> as XML
// tags on their own, so a comment containing ONLY those mis-dispatches to
// ParseOneline (which reads the whole raw tag text as literal summary
// prose -- a nonsensical re-wrap, not a deletion, so a DIFFERENT bug from
// the delete guard). <remarks> and <example> are BOTH already in the
// HasXmlTags sniff, so <example> dispatches correctly on its own; it is
// paired here purely to reach HasContent=True, not to fix a dispatch gap.
/// <since>2020-01-01</since>
/// <seealso cref="Other.Thing"/>
/// <example>Example text.</example>
/// <deprecated/>
/// <remarks></remarks>
procedure HasSinceSeeAlsoExampleDeprecated;

// v(ADP3 T3 review round 2, point 3): <value> is not modeled by the parser
// AT ALL -- unlike Exceptions/ExampleText/SeeAlso/SinceText/Deprecated
// (which at least have a TParsedDoc field, even if HasContent ignores some
// of them), a <value> tag's text is captured NOWHERE. Paired here with a
// MARKED, EMPTY <returns> (correctly dispatched via ParseXmlDoc -- <returns>
// IS in the HasXmlTags sniff -- and HasReturnsTag/ReturnsText set
// HasContent=True) so Merged comes out '' (the returns tag drops itself,
// nothing else to say) and the delete guard is reached with a genuinely
// UNMODELED tag present -- exactly the scenario a field-by-field whitelist
// (this task's Finding 2, pre-round-2) could never protect, no matter how
// many fields it enumerated.
/// <value>Hand-written; must survive.</value>
/// <returns><!-- drag-lint:auto --></returns>
function HasValueTag: Integer;

implementation

procedure HasException;
begin
end;

procedure HasSinceSeeAlsoExampleDeprecated;
begin
end;

function HasValueTag: Integer;
begin
end;

end.
