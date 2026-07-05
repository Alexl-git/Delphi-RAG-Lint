unit boolean_comparison;

interface

implementation

procedure Demo;
var
  Flag, A, B: Boolean;
begin
  Flag := True; A := False; B := True;
  if Flag = True then Flag := False;
  if Flag <> False then Flag := False;
  if Flag = False then Flag := False;
  if Flag <> True then Flag := False;
  if (A and B) = False then Flag := False;
end;

end.
