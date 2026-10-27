unit basic;

interface

implementation

function P(X: Double): Double;
var
  Y: Double;
begin
  Y := Power(X, 2);
  Result := Power(Y, 0.5);
end;

end.
