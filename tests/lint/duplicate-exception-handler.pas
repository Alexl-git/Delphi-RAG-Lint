unit dupexc;
interface
uses System.SysUtils;
implementation
procedure P;
begin
  try
    Writeln('x');
  except
    on E: EConvertError do Writeln('a');
    on E: EAccessViolation do Writeln('b');
    on E: EConvertError do Writeln('c');
  end;
end;
end.
