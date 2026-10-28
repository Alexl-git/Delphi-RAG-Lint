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
  X := F();
  X := 2;
  Writeln(X);
end;
end.
