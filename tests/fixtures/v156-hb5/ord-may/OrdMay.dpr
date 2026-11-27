program OrdMay;

{ Fixture of run_v156_HB5.ps1, O3: the twin of ord-yes with Randomize under a condition -> MAY. }

uses
  uOrdGame in 'uOrdGame.pas';

begin
  if ParamCount > 0 then Randomize;
  RunGame;
end.
