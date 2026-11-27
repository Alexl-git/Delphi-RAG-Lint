program BarNo;

{ Fixture of run_v156_HB5.ps1, R2: the twin of bar-yes with the two statements swapped -> NO (b-first). }

uses
  Vcl.Forms,
  uCfg in 'uCfg.pas';

begin
  Application.Initialize;
  Application.Run;
  LoadConfig;
end.
