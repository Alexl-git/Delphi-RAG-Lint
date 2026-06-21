unit OffByOneCount;

interface

implementation

procedure P;
var
  I: Integer;
  L: TStringList;
begin
  for I := 0 to L.Count do
    WriteLn(I);
  for I := 0 to Length(L) do
    WriteLn(I);
  for I := 0 to L.Count - 1 do
    WriteLn(I);
end;

end.
