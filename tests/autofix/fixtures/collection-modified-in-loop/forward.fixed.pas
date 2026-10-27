unit forward;

interface

implementation

uses
  System.Classes;

procedure P(L: TStringList);
var
  I: Integer;
begin
  for I := L.Count - 1 downto 0 do if L[I] = '' then
      L.Delete(I);
  for I := L.Count - 1 downto 0 do begin
    if L[I] = 'x' then
      L.Delete(I);
  end;
end;

end.
