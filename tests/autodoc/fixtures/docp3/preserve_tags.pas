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
