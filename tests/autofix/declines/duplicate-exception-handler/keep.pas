unit keep;
interface
uses
  System.SysUtils;
implementation
procedure P;
begin
  try
    Writeln('x');
  except
    on E: EConvertError do Writeln('a');
    on E: EConvertError do Writeln('different');
  end;
end;
end.
