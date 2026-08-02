unit harvest_scan;

{ Fixture for Auto-Document Phase 3 Task 6 -- HarvestScan's boundary scan and
  its acceptance guards. One declaration per verdict; the comment on each names
  the outcome it must produce, so a fixture edit that changes the shape is
  visible next to the expectation the runner asserts.

  Nothing here is compiled. CaseTrailer and CaseAfterEnd are IMPLEMENTATION-ONLY
  on purpose: the two layouts the trailer tie-breaker must tell apart both need
  a preceding `end;`, which only exists in the implementation section. }

interface

// Accepted: a plain adjacent header comment.
function CaseAdjacent: Integer;

// Accepted: separated from the declaration by a blank line.

function CaseBlankGap: Integer;

// -----------------------------------------------------------------
function CaseBanner: Integer;

// Result := ComputeSomething(A, B);
function CaseCommentedCode: Integer;

function CaseNoComment: Integer;

//
function CaseEmptyComment: Integer;

{ Legacy note: an unbalanced { brace
  survived a copy-paste and is still in here. }
function CaseNestedBrace: Integer;

/// <summary>Already DocInsight -- not a harvest candidate.</summary>
function CaseAlreadyDoc: Integer;

implementation

function CaseAdjacent: Integer;
begin
  Result := 1;
end;

function CaseBlankGap: Integer;
begin
  Result := 2;
end;

function CaseBanner: Integer;
begin
  Result := 3;
end;

function CaseCommentedCode: Integer;
begin
  Result := 4;
end;
// Trailer: this note closes CaseCommentedCode above.

function CaseTrailer: Integer;
begin
  Result := 5;
end;

// Accepted: a note that introduces CaseAfterEnd. Its scan stops at the same
// closing keyword CaseTrailer's does, with the opposite layout -- a blank line
// after that keyword, and this comment adjacent to the declaration -- so the
// tie-breaker must accept here where it rejected there.
function CaseAfterEnd: Integer;
begin
  Result := 10;
end;

function CaseNoComment: Integer;
begin
  Result := 6;
end;

function CaseEmptyComment: Integer;
begin
  Result := 7;
end;

function CaseNestedBrace: Integer;
begin
  Result := 8;
end;

function CaseAlreadyDoc: Integer;
begin
  Result := 9;
end;

end.
