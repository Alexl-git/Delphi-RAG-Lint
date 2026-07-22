unit p2index;

// Fixture for Auto-Document Phase 2 Task 2 (index-time symbol_facts wiring).
// One function, DoWork, gives the indexer a routine-with-a-body to write a
// symbol_facts row for. run_doc_p2_index.ps1 edits this file (adds a blank
// line before the implementation body) to shift DoWork's impl span and force
// a reindex, proving the facts row is invalidated (ON DELETE CASCADE) and
// re-created against the new symbol id.

interface

function DoWork(A: Integer): Integer;

implementation

function DoWork(A: Integer): Integer;
begin
  Result := A * 2;
end;

end.
