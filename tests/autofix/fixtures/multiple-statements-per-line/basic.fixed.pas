unit basic;

interface

implementation

procedure Q(var X, Y: Integer);
begin
  X := 1;
  Y := 2;
  if X = 1 then
  begin
    Y := 3;
    X := 4;
  end;
end;
end.
