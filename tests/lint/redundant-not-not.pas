unit NotNot;

interface

implementation

procedure P(X: Boolean);
begin
  if not not X then
    WriteLn('x');
  if not X then
    WriteLn('y');
end;

end.
