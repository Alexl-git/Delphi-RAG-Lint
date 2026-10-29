unit keep;
interface
implementation
function F: Boolean;
begin
  Result := True;
end;
procedure P(var X: Integer);
begin
  if F() then X := 1 else X := 1;
end;
end.
