unit complexity;

// Fixture for Auto-Document Phase 2 Task 3 (Complexity fact: cyclomatic +
// body LOC). ComplexFn mixes if/ifElse/for/case/and/or so its cyclomatic
// complexity is >= 10 (docs.complexity_min default) -- its managed block MUST
// carry a 'Complexity: N (cyclomatic), M lines' line. TrivialFn has a single
// decision point (CC well under the threshold) -- NO Complexity line, even
// though it still gets a managed block of its own (ComplexFn calls it, so it
// has a Called-from fact to render).

interface

function ComplexFn(A, B, C: Integer): Integer;
function TrivialFn(A: Integer): Integer;

implementation

function ComplexFn(A, B, C: Integer): Integer;
var
  I: Integer;
begin
  Result := 0;
  if (A > 0) and (B > 0) then Result := 1;
  if (A < 0) or (B < 0) then Result := 2;
  for I := 1 to 10 do
  begin
    if I = A then Result := Result + 1;
  end;
  case A of
    1: Result := Result + 1;
    2: Result := Result + 2;
    3: Result := Result + 3;
  end;
  if C > 0 then Result := Result + 1
  else Result := Result - 1;
  while C > 0 do
  begin
    Dec(C);
  end;
  if (A = B) and (B = C) then Result := Result + 100;
  Result := Result + TrivialFn(A);
end;

function TrivialFn(A: Integer): Integer;
begin
  if A > 0 then Result := 1
  else Result := 0;
end;

end.
