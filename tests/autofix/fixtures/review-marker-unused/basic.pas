unit basic;

interface

implementation

procedure Q(var X: Integer);
begin
  X := 1; // dl:ok bare-except@1234 -- stale
  // dl:ok deep-nesting@1234 -- stale too
  X := 2;
end;
end.
