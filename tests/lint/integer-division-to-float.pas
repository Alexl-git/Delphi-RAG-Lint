unit IntDivFloat;

interface

implementation

procedure Bad(A, B: Integer);
var
  D: Double;
  S: Single;
  E: Extended;
  N: Integer;
  C: Currency;
begin
  D := A div B;
  S := A div 2;
  E := A div B;
  C := A div B;
  N := A div B;
  D := A / B;
  D := (A + B) / 2;
  D := A * B;
end;

end.
