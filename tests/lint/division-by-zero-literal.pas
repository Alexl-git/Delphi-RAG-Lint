unit DivZero;

interface

implementation

procedure P(X: Integer; D: Double);
var
  Y: Integer;
begin
  Y := X div 0;
  Y := X mod 0;
  Y := X div 2;
  D := D / 0;
  D := D / 0.0;
  D := D / 2;
end;

end.
