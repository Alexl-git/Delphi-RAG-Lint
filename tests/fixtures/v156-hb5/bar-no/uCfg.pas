unit uCfg;

{ Fixture of run_v156_HB5.ps1 (preset before-app-run): the configuration load the program must run
  before Application.Run. }

interface

var
  GCfg: Integer;

procedure LoadConfig;

implementation

procedure LoadConfig;
begin
  GCfg:= 1;
end;

end.
