program OrdInit;

{ Fixture of run_v156_HB5.ps1, O4: Randomize is in the initialization section of uSeed, which runs
  before the program block that reaches the one Random -> YES (program-order). }

uses
  uSeed in 'uSeed.pas',
  uOrdGame in 'uOrdGame.pas';

begin
  RunGame;
end.
