unit lossy;
interface
implementation
procedure P;
var
  U: string;
  A: AnsiString;
begin
  A := AnsiString(U);
  U := string(A);
end;
end.
