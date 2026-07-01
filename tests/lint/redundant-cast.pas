unit redcast;
interface
implementation
uses System.Classes;
procedure P;
var
  SL: TStringList;
  N : Integer;
begin
  SL := TStringList.Create;
  TStringList(SL).Add('x');
  SL.Add('y');
  N := Integer(N);
  SL.Free;
end;
end.
