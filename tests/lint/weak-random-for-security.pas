unit weakrand;
interface
implementation
procedure P;
var
  SessionToken: Integer;
  X: Integer;
begin
  SessionToken := Random(999999);
  X := Random(10);
end;
end.
