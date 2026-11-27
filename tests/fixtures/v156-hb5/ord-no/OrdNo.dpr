program OrdNo;

{ Fixture of run_v156_HB5.ps1, O2: the twin of ord-yes with the two statements swapped -- the Random
  inside RunGame runs before the one Randomize -> NO (b-first, program-order). }

uses
  uOrdGame in 'uOrdGame.pas';

begin
  RunGame;
  Randomize;
end.
