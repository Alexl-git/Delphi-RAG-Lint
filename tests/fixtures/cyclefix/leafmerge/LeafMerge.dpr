program LeafMerge;

// Plan fixture (lane cyc4): LmA and LmB use each other in their INTERFACES (F2047 until cut). Their
// moved classes need each other, so one leaf per source would be F2047 again: they share ONE leaf.

{$APPTYPE CONSOLE}

uses
  LmA in 'LmA.pas',
  LmB in 'LmB.pas';

begin
  Writeln(LmMakeName);
end.
