program BarYes;

{ Fixture of run_v156_HB5.ps1, R1: LoadConfig is a top-level statement before Application.Run -> YES. }

uses
  Vcl.Forms,
  uCfg in 'uCfg.pas';

begin
  Application.Initialize;
  LoadConfig;
  Application.Run;
end.
