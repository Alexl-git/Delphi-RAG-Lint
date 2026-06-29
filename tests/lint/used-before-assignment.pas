unit usedbeforeassignment;
interface
implementation
function F1: Integer;
var x, y: Integer;
begin
  y := x;
  Result := y;
end;
function F2(b: Boolean): Integer;
var x: Integer;
begin
  if b then x := 1;
  Result := x;
end;
end.
