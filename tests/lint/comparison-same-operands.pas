unit SameOps;

interface

implementation

procedure P(X, Y: Integer);
begin
  if X = X then
    WriteLn('a');
  if X < Y then
    WriteLn('b');
end;

end.
