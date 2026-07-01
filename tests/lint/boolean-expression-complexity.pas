unit boolcx;
interface
implementation
procedure P(a, b, c, d, e, f: Boolean);
begin
  if a and b and c and d and e and f then
    Writeln('x');
  if a and b then
    Writeln('y');
end;
end.
