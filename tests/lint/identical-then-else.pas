unit ite;
interface
implementation
procedure P(C: Boolean; var X: Integer);
begin
  if C then X := 1 else X := 1;
  if C then X := 1 else X := 2;
end;
end.
