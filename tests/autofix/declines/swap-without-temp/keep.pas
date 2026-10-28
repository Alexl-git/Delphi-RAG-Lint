unit keep;
interface
implementation
procedure P(var A, B: Integer);
var
  LSwap: Integer;
begin
  LSwap := 0;
  A := B;
  B := A;
  Writeln(LSwap);
end;
end.
