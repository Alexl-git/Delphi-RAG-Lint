unit rwc;
interface
Const
  A = 1;
implementation
procedure P;
Var
  B: Integer;
begin
  if A = 1 then B := True;
  B := A And 1;
end;
end.
