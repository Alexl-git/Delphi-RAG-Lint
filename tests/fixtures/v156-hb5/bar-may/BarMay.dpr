program BarMay;

{ Fixture of run_v156_HB5.ps1, R3: the twin of bar-yes with LoadConfig under a condition -> MAY. }

uses
  Vcl.Forms,
  uCfg in 'uCfg.pas';

begin
  Application.Initialize;
  if ParamCount > 0 then LoadConfig;
  Application.Run;
end.
