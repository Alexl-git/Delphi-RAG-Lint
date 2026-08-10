unit callerline_mixed;

interface

// Auto-Document Phase 3, Task 4 -- the MIXED caller-list fixture.
//
// Ping is called twice. NearCaller sits in THIS unit and the call resolver
// writes a real call_edges row for that site, so it reaches the caller list
// 'certain'. FarCaller sits in callerline_mixedcross.pas and reaches Ping
// through a receiver whose type is declared in no unit at all, so that site
// can have no target and gets no call_edges row, reaching the list
// 'unverified'. One list, two different Confidence values.
//
// FarCaller was originally a plain cross-unit BARE call, unresolved only
// because the resolver could not cross a uses edge. Option 4 removed that
// limitation and this fixture's precondition failed by name, as designed. The
// unverified half now rests on an untypable receiver instead -- something no
// resolver improvement can dissolve. See callerline_mixedcross.pas.
//
// This shape is the only one that can tell "the marker is correctly
// SUPPRESSED on a uniform list" apart from "the marker is never EMITTED at
// all". A test built solely from all-uncertain lists passes identically
// under both, which is why the mixed case is not optional.
//
// The runner does not take the split on trust. It re-derives it from the
// index itself -- dump-call-edges must show one resolved edge into Ping, and
// ambiguous-calls must show the other site as unresolved -- before it asserts
// anything about the rendered line. If the resolver ever learns to resolve
// the cross-unit site, that precondition fails loudly and names the fixture,
// instead of leaving the mixed assertion quietly vacuous.

procedure Ping;
procedure NearCaller;

implementation

procedure Ping;
begin
  Writeln('ping');
end;

procedure NearCaller;
begin
  Ping;
end;

end.
