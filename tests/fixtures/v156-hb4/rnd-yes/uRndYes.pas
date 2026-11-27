unit uRndYes;

{ Fixture of run_v156_HB4.ps1, preset `randomize`: the one Random call runs after Randomize in the
  same routine -> YES. }

interface

function Roll: Integer;

implementation

function Roll: Integer;
begin
  Randomize;
  Result:= Random(6) + 1;
end;

end.
