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
    Writeln('oops');
  end;
end;

end.
