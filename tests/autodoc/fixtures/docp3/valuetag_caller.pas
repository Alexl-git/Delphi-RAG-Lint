unit valuetag_caller;

interface

// v(ADP3 T3 review round 3, Regression 1 -- coordinator's own repro): the
// committed HasValueTag case in unhandledtags.pas pairs <value> with a
// MARKED, EMPTY <returns> specifically so the region reaches the Merged=''
// empty-delete branch (Existing.HasReturnsTag alone already routes it through
// the repair path, on its own, independent of Regression 1). THIS fixture is
// deliberately different: <value> + <example> ONLY -- no <summary>, no
// <returns>, no <param> -- so NONE of ExistingHasAnyTag's narrow disjuncts
// (HasSummaryTag/HasReturnsTag/Params/HasContent) fire on their own. Giving
// HasValueAndExample a caller (CallsHasValueAndExample) makes Facts non-empty
// (a "Called from:" line), so Merged is non-empty too -- exercising the
// REPAIR-vs-FRESH branch decision, not the Merged='' branch. Before this
// round's fix, ExistingHasAnyTag ALSO had an "(Trim(Region.RawText) <> '')"
// disjunct, which fired here (raw text is non-blank) and routed this region
// into the repair branch, which deletes [StartLine..EndLine] and inserts
// ONLY Merged -- destroying <value> and <example> since Merged cannot
// represent either. Dropping that disjunct routes this case through the
// "no prior comment" fresh-insert branch instead: the existing lines are
// left completely alone, and Merged is inserted as an ADDITIONAL block
// immediately above the declaration.
/// <value>Hand-written; must survive.</value>
/// <example>Example text.</example>
procedure HasValueAndExample;

procedure CallsHasValueAndExample;

implementation

procedure HasValueAndExample;
begin
end;

procedure CallsHasValueAndExample;
begin
  HasValueAndExample;
end;

end.
