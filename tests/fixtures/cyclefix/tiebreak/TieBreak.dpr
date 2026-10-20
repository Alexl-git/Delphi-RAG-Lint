program TieBreak;

// E18 T7 fixture: a 3-unit implementation-only cycle whose three edges can all
// move globals; only the R3 tie-break (fewest members, then fewest refs) picks
// TieB -> TieC.

{$APPTYPE CONSOLE}

uses
  TieA in 'TieA.pas',
  TieB in 'TieB.pas',
  TieC in 'TieC.pas';

begin
  TieARun;
  TieBRun;
  TieCRun;
end.