unit cogcx;
interface
implementation
procedure Complex(A, B, C: Boolean);
begin
  if A then
    if B then
      if C then
        Writeln('deep');
end;
procedure Simple(A: Boolean);
begin
  if A then Writeln('flat');
end;
end.
