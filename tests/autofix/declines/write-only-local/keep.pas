unit keep;
interface
implementation
function F: Integer;
begin
  Result := 1;
end;
procedure P;
var
  X: Integer;
begin
  X := 1;
  X := F();
end;
end.
