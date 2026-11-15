unit MissingBeginEnd;

interface

implementation

procedure P(X: Integer);
var
  I: Integer;
begin
  if X > 0 then
    Inc(X);
  if X > 1 then
    Inc(X)
  else
    Dec(X);
  for I := 1 to 3 do
    Inc(X);
  while X > 0 do
    Dec(X);
  if X > 2 then
  begin
    Inc(X);
  end
  else if X > 3 then
  begin
    Dec(X);
  end;
  for I := 1 to 3 do
  begin
    Inc(X);
  end;
  while X > 5 do
  begin
    Dec(X);
  end;
  if X > 9 then
  begin
    Inc(X);
  end
  else
    Dec(X);
end;

end.
