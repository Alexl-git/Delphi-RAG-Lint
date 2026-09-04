unit uUuConsumer;

{ Fixture for run_unit_usage_degrades.ps1 -- the IMPORTER.

  It imports two units on purpose:
    uUuLib          -- present in the fixture index, so its export surface
                       resolves and the full reference breakdown runs;
    ZzAbsentLibUnit -- NOT present, standing in for an RTL/VCL/third-party unit
                       whose exports live in the platform library index. Its
                       `uses` row exists; its symbols do not. That is the exact
                       shape that used to make the verb exit 2 with nothing. }

interface

uses
  uUuLib, ZzAbsentLibUnit;

procedure DoWork;

implementation

procedure DoWork;
var
  T: TUuThing;
begin
  T:= TUuThing.Create;
  try
    T.Poke;
    if UuCompute(2) > 0 then Exit;
  finally
    T.Free;
  end;
end;

end.
