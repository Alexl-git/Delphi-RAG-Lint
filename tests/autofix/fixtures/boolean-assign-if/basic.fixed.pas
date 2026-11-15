unit basic;

interface

implementation

procedure P(A, B: Integer);
var
  Ok, Flag: Boolean;
begin
  Ok := A > B;
  Flag := not (A > B);
  Ok := (A > B) and (A > 0);
  Flag := Ok;
  if Flag then Writeln(Ok);
end;

end.
