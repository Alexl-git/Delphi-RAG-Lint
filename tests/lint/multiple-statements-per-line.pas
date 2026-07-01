unit MultipleStatementsPerLine;

interface

implementation

procedure TwoOnOneLine;
var
  a, b: Integer;
begin
  a := 1; b := 2;
  a := 3;
  b := 4;
end;

procedure OneEach;
var
  x: Integer;
begin
  x := 1;
  Inc(x);
end;

end.
