unit basic;

interface

implementation

function P(X: Double): Double;
var
  Y: Double;
begin
  Y := Sqr(X);
  Result := Sqrt(Y);
end;

end.
