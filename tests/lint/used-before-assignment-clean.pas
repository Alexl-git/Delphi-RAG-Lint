unit usedbeforeassignmentclean;
interface
implementation
function F3(b: Boolean): Integer;
var x: Integer;
begin
  if b then x := 1 else x := 2;
  Result := x;
end;
function F4: string;
var s: string;
begin
  Result := s;
end;
end.
