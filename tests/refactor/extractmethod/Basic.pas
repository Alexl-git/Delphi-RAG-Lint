unit Basic;
interface
procedure P(a: Integer);
implementation
procedure P(a: Integer);
var t: Integer;
begin
  t := a + 1;
  Writeln(t);
end;
end.
