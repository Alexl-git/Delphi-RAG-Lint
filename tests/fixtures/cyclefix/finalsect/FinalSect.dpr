program FinalSect;

// Plan fixture (lane cyc4): FsA's finalization section runs FsAShutdown, which calls FsBStop. No
// initialization names it, so the pointer is assigned long before: not an init-order case.

{$APPTYPE CONSOLE}

uses
  FsA in 'FsA.pas',
  FsB in 'FsB.pas';

begin
  Writeln('main');
end.
