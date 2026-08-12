unit CyclomaticComplexity;

interface

implementation

{ Complexity ~35, comfortably over the default threshold of 30.
  It used to sit at ~20, which cleared the OLD default of 15. That default was
  retuned to 30 on 2026-08-10 after measuring drag-lint's own corpus, where the
  MEDIAN flagged routine scored 22 -- a threshold below the median of what it
  flags is describing the codebase, not selecting outliers.
  This fixture exists to prove the rule FIRES, so it is raised above the new
  default rather than pinning the old number. The threshold itself is pinned by
  DEFAULT_CYCLOMATIC_THRESHOLD in DRagLint.Lint.RuleCatalog. }
procedure Complex(A, B, C, D: Boolean; N: Integer);
begin
  if A and B or C and D then ;
  if A and B or C and D then ;
  if A and B or C and D then ;
  if A and B or C and D then ;
  if A and B or C and D then ;
  if A and B or C and D then ;
  if A and B or C and D then ;
  while A and B do ;
  while C or D do ;
  for N := 1 to 10 do ;
  case N of
    1: ;
    2: ;
    3: ;
    4: ;
    5: ;
    6: ;
  end;
end;

procedure Simple(A: Boolean);
begin
  if A then ;
end;

end.
