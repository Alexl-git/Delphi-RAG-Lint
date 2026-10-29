unit basic;

interface

implementation

procedure P(var Flag: Boolean; A, B: Boolean);
begin
  if Flag then Flag := False;
  if not (A and B) then Flag := True;
end;

end.
