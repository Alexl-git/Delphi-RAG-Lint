unit objectleak;
interface
uses System.Classes;
implementation
procedure P1;
var o: TStringList;
begin
  o := TStringList.Create;
  o.Add('x');
end;
procedure P2;
var o: TStringList;
begin
  o := TStringList.Create;
  try o.Add('x'); finally o.Free; end;
end;
function P3: TStringList;
begin
  Result := TStringList.Create;
end;
procedure P4(aList: TStrings);
var o: TStringList;
begin
  o := TStringList.Create;
  aList.AddObject('x', o);
end;
end.
