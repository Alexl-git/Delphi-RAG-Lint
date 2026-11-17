program evGlobal;

{ check-init fixture events-global (lane HBEVENTS): writers with `how`, assign-nil twins,
  guarded tests, callers and a DFM-bound handler. Positions are asserted by
  tests\autotest\run_check_init_events.ps1 -- do not reflow this program or its units. }

uses
  Vcl.Forms,
  evgData in 'evgData.pas',
  evgMain in 'evgMain.pas' {MainForm},
  evgOther in 'evgOther.pas';

begin
  Application.Initialize;
  Application.CreateForm(TMainForm, MainForm);
  Application.Run;
end.
