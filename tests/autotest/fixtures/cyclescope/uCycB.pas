unit uCycB;

{ Declaring half. `SharedName` here collides with a routine-LOCAL of the same
  name in uCycA, and `RealThing` is the genuine cross-unit coupling.

  uCycA is used from the IMPLEMENTATION section on both sides, so the cycle is
  implementation-only -- which is the branch `cycles --causes` explains with
  "Why it cycles (implementation-section edges)". }

interface

var
  SharedName: string;

procedure RealThing;

implementation

uses
  uCycA;

procedure RealThing;
begin
  TouchA;
end;

end.
