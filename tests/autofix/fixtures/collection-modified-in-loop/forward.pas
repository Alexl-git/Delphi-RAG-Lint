unit forward;

interface

implementation

uses
  System.Classes;

procedure P(L: TStringList);
var
  I: Integer;
begin
  for I := 0 to L.Count - 1 do
    if L[I] = '' then
      L.Delete(I);
  for I := 0 to L.Count - 1 do
  begin
    if L[I] = 'x' then
      L.Delete(I);
  end;
end;

end.
