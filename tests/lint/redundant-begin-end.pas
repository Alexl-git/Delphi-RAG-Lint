unit RedundantBeginEnd;

interface

implementation

procedure P(X: Integer);
var
  I: Integer;
begin
  if X > 0 then
  begin
    Inc(X);
  end;
  for I := 1 to 3 do
  begin
    Inc(X);
  end;
  while X > 0 do
  begin
    Dec(X);
  end;
  if X > 1 then
  begin
    Inc(X);
  end
  else
  begin
    Dec(X);
  end;
  if X > 2 then
  begin
    Inc(X);
    Dec(X);
  end;
  if X > 3 then
  begin
    if X > 4 then
      Inc(X);
  end
  else
    Dec(X);
  if X > 5 then
    Inc(X);
end;

end.
