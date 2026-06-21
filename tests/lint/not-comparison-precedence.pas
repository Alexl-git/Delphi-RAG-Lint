unit NotCmpPrec;

interface

implementation

procedure P(A, B: Integer);
begin
  if not A = B then
    WriteLn('x');
  if not (A = B) then
    WriteLn('y');
end;

end.
