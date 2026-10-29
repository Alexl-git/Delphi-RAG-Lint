unit FixedSeed;

interface

implementation

procedure Seed;
begin
  RandSeed := 42;
  Randomize;
  RandSeed := GetTickCount;
end;

end.
