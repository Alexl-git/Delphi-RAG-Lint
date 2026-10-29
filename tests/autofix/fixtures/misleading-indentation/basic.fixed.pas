unit basic;

interface

implementation

procedure Q(var X, Y: Integer);
begin
  if X = 1 then
    Y := 3;
  X := 4;
  Y := 5;
end;
end.
