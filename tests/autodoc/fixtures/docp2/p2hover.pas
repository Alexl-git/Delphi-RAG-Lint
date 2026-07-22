unit p2hover;

// Fixture for Auto-Document Phase 2 Task 9 (hover surfaces the analysis
// facts + doc/hover consistency lock). TBusy.Complex deliberately combines
// TWO Phase-2 facts in ONE routine so the hover<->doc consistency assertion
// has more than one line to compare:
//   * Cyclomatic complexity >= docs.complexity_min (10) -- the SAME
//     if/ifElse/for/case/and/or/while mix as fixtures\docp2\complexity.pas's
//     ComplexFn (proven >= 10 there), reused here as a class method.
//   * Reads AND writes FCount (an own-class field) via the trailing
//     'FCount := FCount + Result; Result := FCount;' pair -- mirrors
//     fixtures\docp2\fields.pas's AddN shape ('FCount := FCount + N') --
//     so the managed block carries 'Reads: FCount   Writes: FCount'.
//
// Task 9 asserts `hover --qname p2hover.TBusy.Complex --format md` renders
// BOTH the Complexity and the Reads/Writes lines, and that they are
// BYTE-IDENTICAL to the same two lines in the managed doc block for the
// SAME symbol -- proving hover and `document` flow through the identical
// shared FormatPhase2FactLines helper and can never drift apart.

interface

type
  TBusy = class
  private
    FCount: Integer;
  public
    function Complex(A, B, C: Integer): Integer;
  end;

implementation

function TBusy.Complex(A, B, C: Integer): Integer;
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
  FCount := FCount + Result;
  Result := FCount;
end;

end.
