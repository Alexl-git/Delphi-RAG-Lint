unit store19;

// Fixture for Auto-Document Phase 3, Task 10 (schema v19 -- four additive columns).
// Uses ComputeTotal to match the doc-facts-selftest verb's hardcoded lookup.

interface

function ComputeTotal(A, B: Integer): Integer;

implementation

function ComputeTotal(A, B: Integer): Integer;
begin
  Result := A + B;
end;

end.
