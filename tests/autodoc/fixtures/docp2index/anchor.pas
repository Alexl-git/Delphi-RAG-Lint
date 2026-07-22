unit anchor;

// Sibling fixture for Auto-Document Phase 2 Task 2's reindex-invalidation
// test (run_doc_p2_index.ps1). Indexed ONCE, then never touched again, so
// its symbol ids stay put in the DB while p2index.pas's DoWork is edited and
// reindexed -- this keeps the symbols table non-empty across that reindex, so
// SQLite must hand DoWork's re-inserted row a brand-new (higher) rowid rather
// than reusing its old one. That, in turn, makes "no symbol_facts row still
// references DoWork's OLD id" an actual proof that ON DELETE CASCADE fired,
// not a coincidence of rowid reuse on an emptied table.

interface

function AnchorFunc: Integer;

implementation

function AnchorFunc: Integer;
begin
  Result := 1;
end;

end.
