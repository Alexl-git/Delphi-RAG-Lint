unit uRndMay;

{ Fixture of run_v156_HB4.ps1, preset `randomize`: Randomize sits in one exported routine, Random in
  another; nothing in the index orders the two -> MAY. }

interface

procedure Seed;
function Roll: Integer;

implementation

procedure Seed;
begin
  Randomize;
end;

function Roll: Integer;
begin
  Result:= Random(6) + 1;
end;

end.
