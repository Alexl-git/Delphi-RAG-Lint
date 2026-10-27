unit basic;

interface

implementation

procedure Q(var X: Integer);
begin
  X := 7; // dl:ok magic-literal@HASH -- REVIEWED 2026-10-27 seven is the limit
end;
end.
