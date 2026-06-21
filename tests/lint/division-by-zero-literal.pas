unit DivZero;

interface

implementation

procedure P(X: Integer);
var
  Y: Integer;
begin
  Y := X div 0;
  Y := X mod 0;
  Y := X div 2;
end;

end.
