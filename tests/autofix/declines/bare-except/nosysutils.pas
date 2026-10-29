unit nosysutils;
interface
implementation
procedure P;
begin
  try
    Writeln('x');
  except
    Writeln('y');
  end;
end;
end.
