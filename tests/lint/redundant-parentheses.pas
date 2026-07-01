unit redparen;
interface
implementation

const
  PRUNE: array[0..0] of string = ('x');

procedure P(var X: Integer);
begin
  X := (X);
  X := ((X + 1));
  X := (X + 1);
  X := X + 1;
end;
end.
