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
    on E: Exception do
    begin
      Writeln('oops');
      raise;
    end;
  end;
end;

end.
