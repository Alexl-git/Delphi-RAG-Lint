unit basic;

interface

implementation

procedure P(var Flag: Boolean; A, B: Boolean);
begin
  if Flag = True then Flag := False;
  if (A and B) = False then Flag := True;
end;

end.
