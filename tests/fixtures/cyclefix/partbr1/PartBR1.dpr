program PartBR1;

// E18 T7 fixture: Part B of the interface cycle PartBA <-> PartBB must predict
// a routine-call inversion cut (R3), not "no edge can be cut".

{$APPTYPE CONSOLE}

uses
  PartBB in 'PartBB.pas',
  PartBA in 'PartBA.pas';

begin
  PartBAShow(pbkTwo);
end.