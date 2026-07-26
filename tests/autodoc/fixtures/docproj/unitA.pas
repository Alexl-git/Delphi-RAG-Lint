unit unitA;

interface

// Public routine that calls Beta(...) -> carries a Calls fact (facts-only keeps
// it) and gives Beta a Called-from fact.
function Alpha(A: Integer): Integer;

// Public helper Alpha calls; the call site Beta(...) gives it a Called-from
// fact -> facts-only keeps it.
function Beta(A: Integer): Integer;

// Bare public procedure: no params, no returns, no callers, no callees.
// It has NO derivable summary AND no facts, so the facts-only default SKIPS
// it. v(ADP3 T3): --stubs does NOT document it either -- omit-when-empty
// means MergeComment returns '' when there is genuinely nothing to say (no
// params/return/facts/summary), so no comment is ever written here,
// regardless of --stubs (ADP1: no placeholder stub text is ever emitted;
// T3 goes further and omits the tag entirely, not just its text).
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
