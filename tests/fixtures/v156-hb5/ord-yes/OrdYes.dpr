program OrdYes;

{ Fixture of run_v156_HB5.ps1, O1: Randomize is a top-level statement of the program block BEFORE the
  call that reaches the one Random -> YES (program-order). }

uses
  uOrdGame in 'uOrdGame.pas';

begin
  Randomize;
  RunGame;
end.
