unit NotInPrecedence;

interface

implementation

procedure P(X: Integer);
begin
  if not X in [1, 2] then
    WriteLn('a');
end;

procedure Q(X: Integer);
begin
  if not (X in [1, 2]) then
    WriteLn('b');
end;

end.
