unit unitA;

interface

// Public routine that calls Beta(...) -> carries a Calls fact (facts-only keeps
// it) and gives Beta a Called-from fact.
function Alpha(A: Integer): Integer;

// Public helper Alpha calls; the call site Beta(...) gives it a Called-from
// fact -> facts-only keeps it.
function Beta(A: Integer): Integer;

// Bare public procedure: no params, no returns, no callers, no callees.
// It has NO derivable summary AND no facts, so the facts-only default SKIPS it;
// --stubs opts in and documents it with a TODO summary.
procedure Noop;

implementation

function Beta(A: Integer): Integer;
begin
  Result := A + 1;
end;

function Alpha(A: Integer): Integer;
begin
  Result := Beta(A) + 1;
end;

procedure Noop;
begin
end;

end.
