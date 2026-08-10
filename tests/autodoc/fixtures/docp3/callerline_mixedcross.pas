unit callerline_mixedcross;

interface

// Auto-Document Phase 3, Task 4 -- see callerline_mixed.pas for the whole
// story. This unit exists for one reason: to contribute the UNVERIFIED half
// of that fixture's caller list, via a call site for which the index holds no
// call_edges row.
//
// WHY THIS IS A DOTTED CALL ON AN UNDECLARED TYPE, AND NOT A BARE ONE
// --------------------------------------------------------------------------
// It used to be a bare `Ping;`, unresolved only because the resolver could not
// follow a bare call across a uses edge. Option 4 taught it to, and this
// fixture's precondition failed loudly and named the file -- exactly as its
// header promised it would. That is the runner working, not a regression.
//
// A limitation is the wrong thing to build a fixture on: the next improvement
// dissolves it. So the unverified half now rests on something no resolver
// improvement can take away. `Probe` is declared as TNowhereDeclared, a type no
// unit in this index declares, so the receiver cannot be typed, and a call
// through an untypable receiver has no target by construction. It is also the
// most REPRESENTATIVE unresolved shape there is: the bulk of the real remainder
// is exactly this -- calls through RTL and VCL types that live in the separate
// library index and are not representable as an edge in a project DB.
//
// The `uses callerline_mixed` clause below is deliberately KEPT even though it
// no longer affects the outcome. It is what proves the non-resolution comes
// from the untypable RECEIVER and not merely from Ping being out of scope: with
// the unit used, a bare call here would now resolve.

procedure FarCaller;

implementation

uses
  callerline_mixed;

procedure FarCaller;
var
  Probe: TNowhereDeclared;
begin
  Probe.Ping;
end;

end.
