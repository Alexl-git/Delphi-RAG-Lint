unit basic;

interface

implementation

procedure P(A, B: Integer);
var
  Ok, Flag: Boolean;
begin
  if A > B then Ok := True else Ok := False;
  if A > B then Flag := False else Flag := True;
  if (A > B) and (A > 0) then Ok := True else Ok := False;
  if Ok then
    Flag := True
  else
    Flag := False;
  if Flag then Writeln(Ok);
end;

end.
