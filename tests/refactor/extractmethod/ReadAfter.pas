unit ReadAfter;
interface
procedure P(a: Integer);
implementation
procedure P(a: Integer);
var sum, t: Integer;
begin
  sum := a + 1;
  t := a + 2;
  Writeln(sum);
  t := 99;
  Writeln(t);
end;
end.
