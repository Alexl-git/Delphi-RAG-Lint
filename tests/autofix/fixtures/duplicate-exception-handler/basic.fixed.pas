unit basic;

interface

uses
  System.SysUtils;

procedure P;

implementation

procedure P;
begin
  try
    Writeln('x');
  except
    on E: EConvertError do Writeln('a');
    on E: EAccessViolation do Writeln('b');
  end;
end;

end.
