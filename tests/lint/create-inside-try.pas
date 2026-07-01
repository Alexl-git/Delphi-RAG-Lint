unit createtry;
interface
uses System.Classes;
implementation
procedure P;
var
  SL: TStringList;
begin
  try
    SL := TStringList.Create;
    SL.Add('x');
  finally
    SL.Free;
  end;
  SL := TStringList.Create;
  try
    SL.Add('y');
  finally
    SL.Free;
  end;
end;
end.
