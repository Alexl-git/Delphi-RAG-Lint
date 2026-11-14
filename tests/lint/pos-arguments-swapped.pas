unit pos_arguments_swapped;

interface

implementation

uses
  System.SysUtils, System.StrUtils;

procedure Swapped(Zeile: string);
begin
  if Pos(Zeile, ';') > 0 then Exit;
  if PosEx(Zeile, ',', 2) > 0 then Exit;
  if StartsText(Zeile, '#') then Exit;
  if EndsStr(Zeile, 'x') then Exit;
  if Pos(Zeile, 'abcdef') > 0 then Exit;
end;

procedure Fine(Zeile: string; Ch: Char);
begin
  if Pos(';', Zeile) > 0 then Exit;
  if PosEx(',', Zeile, 2) > 0 then Exit;
  if Pos(Ch, 'aeiou') > 0 then Exit;
  if Pos('a', 'abc') > 0 then Exit;
  if StartsText('#', Zeile) then Exit;
end;

end.
