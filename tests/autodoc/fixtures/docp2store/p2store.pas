unit p2store;

// Fixture for Auto-Document Phase 2 Task 1 (symbol_facts storage plumbing).
// One function, ComputeTotal, gives the doc-facts-selftest verb a real
// symbol_id to round-trip a TSymbolFacts row against.

interface

function ComputeTotal(A, B: Integer): Integer;

implementation

function ComputeTotal(A, B: Integer): Integer;
begin
  Result := A + B;
end;

end.
