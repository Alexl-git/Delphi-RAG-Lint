unit EmptyHandler;

interface

uses System.SysUtils;

implementation

procedure P;
begin
  try
    WriteLn('x');
  except
    on E: Exception do ;
  end;
end;

procedure Q;
begin
  try
    WriteLn('y');
  except
    on E: Exception do
      WriteLn('handled');
  end;
end;

end.
