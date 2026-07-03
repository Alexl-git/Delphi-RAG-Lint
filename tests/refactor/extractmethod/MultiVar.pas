unit MultiVar;
interface
procedure P(a: Integer);
implementation
procedure P(a: Integer);
var
  t: Integer;
  u: Integer;
begin
  t := a + 1;
  u := t + 1;
  Writeln(u);
end;
end.
