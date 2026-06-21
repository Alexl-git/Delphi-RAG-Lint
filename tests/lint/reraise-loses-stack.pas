unit ReraiseLosesStack;

interface

uses System.SysUtils;

implementation

procedure P;
begin
  try
    WriteLn('x');
  except
    on E: Exception do
      raise E;
  end;
end;

end.
