unit keep;
interface
uses
  System.Classes;
implementation
procedure P;
var
  SL, SL2: TStringList;
begin
  SL2 := TStringList.Create;
  try
    SL := TStringList.Create;
    SL.Add('x');
  finally
    SL.Free;
    SL2.Free;
  end;
end;
end.
