unit missfix;

// THIS BLOCK MUST STAY ABOVE `interface`, NOT ABOVE THE DECLARATION.
// v(ADP3 T7) taught `document` to HARVEST a plain // comment sitting above a
// declaration into a managed <summary>. This file's own explanatory header used
// to sit directly above `function Undocumented`, so the harvester correctly
// promoted it -- and assertion A3, which asserts the fix emits NO <summary>
// when there is nothing to say, had been red ever since. The engine was right;
// the fixture was wrong. Keeping the prose up here leaves the declaration with
// no harvestable comment above it, which is the state A3 is about.
//
// Fixture for the missing-doc "Fix it" single-fix test (ADF Task 11c).
//   Undocumented -- public, NO doc comment, HAS a param + a caller -> the
//                   missing-doc finding whose Fix-it inserts a document-qname
//                   DocInsight comment: a returns tag mined from Result, plus
//                   the managed Called-from facts block.
//   CallsIt      -- public, NO doc, calls Undocumented (so Called-from is
//                   non-empty). Also a missing-doc finding, but never targeted.
// No documented decl here on purpose: nothing for doc-drift to touch, so the
// blanket-batch-exclusion check proves the file is byte-identical after a
// no-narrowing `lint-all --fix` (missing-doc is single-fix-only -> excluded).

interface

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
