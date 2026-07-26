unit unhandledtags;

interface

/// <exception cref="EFoo">Boom.</exception>
procedure HasException;

/// <example>Example text.</example>
procedure HasExample;

// NOTE on this one comment combining three tags: SinceText/SeeAlso alone do
// NOT set TParsedDoc.HasContent (a separate, pre-existing gap outside
// Finding 3's exact scope -- HasContent's OR-chain never included them, and
// Finding 3 only added HasSummaryTag/HasReturnsTag). Pairing them with
// <deprecated/> (which DOES set HasContent, via Result.Deprecated) is what
// actually routes this comment through the repair path so Finding 2's
// HasUnhandledTagContent guard is genuinely exercised for all three fields
// at once, rather than being trivially safe via HasContent already being
// False. The empty <remarks></remarks> is ALSO required: it is a separate
// workaround for a SEPARATE, pre-existing, unfixed defect (flagged in the
// Task 3 fix report, not fixed here) -- TDocCommentParser.Dispatch's
// HasXmlTags sniff does not recognize <since>/<seealso>/<deprecated> as XML
// tags on their own, so a comment containing ONLY those mis-dispatches to
// ParseOneline (which reads the whole raw tag text as literal summary
// prose -- a nonsensical re-wrap, not a deletion, so a DIFFERENT bug from
// Finding 2's delete branch). <remarks> IS in the HasXmlTags sniff and
// itself contributes nothing to Merged when empty, so it forces correct
// ParseXmlDoc dispatch without adding any content of its own.
/// <since>2020-01-01</since>
/// <seealso cref="Other.Thing"/>
/// <deprecated/>
/// <remarks></remarks>
procedure HasSinceSeeAlsoDeprecated;

implementation

procedure HasException;
begin
end;

procedure HasExample;
begin
end;

procedure HasSinceSeeAlsoDeprecated;
begin
end;

end.
