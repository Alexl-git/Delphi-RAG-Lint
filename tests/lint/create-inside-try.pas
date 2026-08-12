unit createtry;
interface
uses System.Classes;
implementation
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

end.
