unit FoUnit;

interface

procedure RunAll;

implementation

{ total is declared Total: only the spelling of the use changes }
function Twice(AValue: Integer): Integer;
var
  Total: Integer;
begin
  Total:= AValue * 2;
  Result:= Total;
end;

procedure RunAll;
begin
  WriteLn(Twice(2));
end;

end.
