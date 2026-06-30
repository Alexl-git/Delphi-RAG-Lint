unit Dead;
interface
procedure NeverCalled;
implementation
procedure NeverCalled;
begin
  Writeln('dead');
end;
end.
