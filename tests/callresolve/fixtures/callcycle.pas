unit callcycle;

// D5 Task 11 fixture: a RESOLVABLE call CYCLE so callgraph's cycle guard is
// checkable (traversal must TERMINATE, not hang). TCyc.PingP calls PongQ; PongQ
// calls PingP -- a two-hop cycle PingP -> PongQ -> PingP, both hops resolved
// via Self (receiver type = the enclosing class TCyc), so both call_edges
// resolve certain and the back-edge to PingP closes the loop.
//
// (A two-CLASS mutual cycle A.M -> B.N -> A.M is NOT used here: it requires a
// forward class declaration, and the resolver does not type a field whose
// declared type is a forward-declared class, so one hop would stay unresolved.
// A same-class Self cycle sidesteps that and still exercises the exact guard.)

interface

type
  TCyc = class
  public
    procedure PingP;
    procedure PongQ;
  end;

implementation

procedure TCyc.PingP;
begin
  Self.PongQ;        // Self receiver -> certain TCyc.PongQ
end;

procedure TCyc.PongQ;
begin
  Self.PingP;        // Self receiver -> certain TCyc.PingP (closes the cycle)
end;

end.
