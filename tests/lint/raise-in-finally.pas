unit RaiseInFinally;

interface

uses System.SysUtils;

implementation

procedure P;
begin
  try
    WriteLn('x');
  finally
    raise Exception.Create('boom');
  end;
end;

procedure R;
begin
  try
    raise Exception.Create('in try');
  finally
    WriteLn('z');
  end;
end;

end.
