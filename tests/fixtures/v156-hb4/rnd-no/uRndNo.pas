unit uRndNo;

{ Fixture of run_v156_HB4.ps1, preset `randomize`: Random is called, Randomize never -> NO. }

interface

function Roll: Integer;

implementation

function Roll: Integer;
begin
  Result:= Random(6) + 1;
end;

end.
