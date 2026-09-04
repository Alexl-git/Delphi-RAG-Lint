unit uUuLib;

{ Fixture for run_unit_usage_degrades.ps1 -- the LOCAL unit, whose export
  surface IS in the fixture index. It is the control: the full breakdown must
  keep working exactly as before. }

interface

type
  TUuThing = class
  public
    procedure Poke;
  end;

function UuCompute(const AValue: Integer): Integer;

implementation

procedure TUuThing.Poke;
begin
end;

function UuCompute(const AValue: Integer): Integer;
begin
  Result:= AValue * 2;
end;

end.
