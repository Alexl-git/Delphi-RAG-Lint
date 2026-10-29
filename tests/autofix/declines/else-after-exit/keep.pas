unit keep;
interface
implementation
procedure P(A, B: Boolean);
begin
  if A then if B then Exit else Writeln('x');
end;
procedure Q(A: Boolean);
begin
  if A then
    Exit
  else // keep this note
    Writeln('x');
end;
end.
