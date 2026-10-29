unit UnreadableLit;

interface

implementation

procedure Bad(var N: Int64);
begin
  N := 1000000;
  N := 12345678901;
end;

procedure Good(var N: Int64);
begin
  N := 100000;
  N := 1_000_000;
  N := $FFFFFFFF;
  N := 42;
end;

end.
