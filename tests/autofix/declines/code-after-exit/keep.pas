unit keep;
interface
implementation
procedure P;
label L1;
begin
  Exit;
  L1: Writeln('reachable by goto');
end;
procedure Q;
begin
  Exit; Writeln('same line');
end;
end.
