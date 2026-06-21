unit CleanCode;

interface

uses System.SysUtils;

implementation

procedure P;
var
  X: Integer;
  L: TStringList;
begin
  try
    X := 1;
  except
    on E: Exception do
      raise;
  end;
  try
    X := 2;
  finally
    X := 0;
  end;
  if X > 0 then
    WriteLn('pos')
  else
    WriteLn('neg');
  for X := 0 to L.Count - 1 do
    WriteLn(X);
end;

end.
