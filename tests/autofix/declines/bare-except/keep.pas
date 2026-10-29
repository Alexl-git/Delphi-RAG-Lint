unit keep;
interface
uses
  System.SysUtils;
implementation
procedure P(E: Integer);
begin
  try
    Writeln('x');
  except
    Writeln(E);
  end;
end;
end.
