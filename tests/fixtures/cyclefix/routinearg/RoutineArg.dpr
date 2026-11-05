program RoutineArg;

// Plan fixture (lane cyc4): the consumer passes the routine as a procedural-type argument and as a
// method-reference argument; after the cut it passes the pointer and the output is the same.

{$APPTYPE CONSOLE}

uses
  RaA in 'RaA.pas',
  RaB in 'RaB.pas';

begin
  RaAShow;
end.
