unit missfix;

interface

// Fixture for the missing-doc "Fix it" single-fix test (ADF Task 11c).
//   Undocumented -- public, NO doc comment, HAS a param + a caller -> the
//                   missing-doc finding (line 16) whose Fix-it inserts a
//                   document-qname DocInsight comment: a returns tag mined
//                   from Result, plus the managed Called-from facts block.
//   CallsIt      -- public, NO doc, calls Undocumented (so Called-from is
//                   non-empty). Also a missing-doc finding, but never targeted.
// No documented decl here on purpose: nothing for doc-drift to touch, so the
// blanket-batch-exclusion check proves the file is byte-identical after a
// no-narrowing `lint-all --fix` (missing-doc is single-fix-only -> excluded).

function Undocumented(Value: Integer): Integer;

implementation

function Undocumented(Value: Integer): Integer;
begin
  Result := Value + 1;
end;

function CallsIt: Integer;
begin
  Result := Undocumented(41);
end;

end.
