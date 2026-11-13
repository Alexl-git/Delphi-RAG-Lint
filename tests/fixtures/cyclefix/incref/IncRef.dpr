program IncRef;

// Plan fixture (lane CYC3, item 2): a reference a cut would redirect lives in an include.

{$APPTYPE CONSOLE}

uses
  IncRefA in 'IncRefA.pas',
  IncRefB in 'IncRefB.pas';

begin
  IncRefAStart;
end.
