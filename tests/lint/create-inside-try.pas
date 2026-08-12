unit createtry;
interface
uses System.Classes;
implementation

// Fix 4 (2026-08-11 review) fixtures use these for the multi-level ('A.B.C')
// qualified-lhs cases below.
type
  TInner = record
    Obj: TObject;
  end;
  TOuter = record
    Inner: TInner;
  end;

procedure P;
var
  SL: TStringList;
begin
  try
    SL := TStringList.Create;
    SL.Add('x');
  finally
    SL.Free;
  end;
  SL := TStringList.Create;
  try
    SL.Add('y');
  finally
    SL.Free;
  end;
end;

// Task 9a shape 1 (YADF.Layout.pas:5481-5484): Root is assigned before the
// outer try, whose finally frees Root -- NOT Sb. Sb is constructed as the
// first statement inside that try, but Sb gets its OWN nested try..finally
// on the very next line (finally Sb.Free). No finding: the outer finally
// does not touch an undefined Sb if Sb's constructor raises.
procedure Q;
var
  Root: TObject;
  Sb  : TObject;
begin
  Root := TObject.Create;
  try
    Sb := TObject.Create;
    try
      Sb.Add('x');
    finally
      Sb.Free;
    end;
  finally
    Root.Free;
  end;
end;

// Task 9a shape 3: the try's finally frees B, a DIFFERENT variable already
// assigned before the try -- not A, the one just constructed. No finding:
// if A's constructor raises, the finally's B.Free does not touch A.
procedure R;
var
  A, B: TObject;
begin
  B := TObject.Create;
  try
    A := TObject.Create;
    A.Free;
  finally
    B.Free;
  end;
end;

// Fix 4 (2026-08-11 review): the lhs gate used to require a bare identifier
// node, so a qualified or indexed target's create-inside-try hazard was
// silently dropped even when the SAME finally demonstrably freed that exact
// target -- the real hazard the rule exists for. Widened to compare the
// lhs's own source text instead.
//
// S (indexed lhs, finally frees the SAME element -- fires): Arr[0] is
// constructed as the try's first statement, and the try's own finally frees
// Arr[0] via Arr[0].Free.
procedure S;
var
  Arr: array[0..2] of TObject;
begin
  try
    Arr[0] := TObject.Create;
  finally
    Arr[0].Free;
  end;
end;

// T (indexed lhs, finally frees a DIFFERENT element -- no finding): Arr[1] is
// already assigned before the try; Arr[0] is constructed as the try's first
// statement, but the try's finally frees Arr[1], not Arr[0].
procedure T;
var
  Arr: array[0..2] of TObject;
begin
  Arr[1] := TObject.Create;
  try
    Arr[0] := TObject.Create;
  finally
    Arr[1].Free;
  end;
end;

// U (multi-level lhs 'A.B.C', finally frees the SAME target -- fires):
// Outer.Inner.Obj is constructed as the try's first statement, and the same
// try's finally frees Outer.Inner.Obj via the identical qualified path.
procedure U;
var
  Outer: TOuter;
begin
  try
    Outer.Inner.Obj := TObject.Create;
  finally
    Outer.Inner.Obj.Free;
  end;
end;

// V (multi-level lhs, finally frees a DIFFERENT qualified target -- no
// finding): Outer2.Inner.Obj is already assigned before the try;
// Outer1.Inner.Obj is constructed as the try's first statement, but the
// try's finally frees Outer2.Inner.Obj -- textually different.
procedure V;
var
  Outer1, Outer2: TOuter;
begin
  Outer2.Inner.Obj := TObject.Create;
  try
    Outer1.Inner.Obj := TObject.Create;
  finally
    Outer2.Inner.Obj.Free;
  end;
end;

end.
