unit EmptyLoops;

interface

implementation

procedure P(X: Integer);
begin
  while X > 0 do ;
  for X := 1 to 3 do ;
  repeat until X > 0;
end;

procedure Q(X: Integer);
begin
  while X > 0 do
    Dec(X);
end;

end.
