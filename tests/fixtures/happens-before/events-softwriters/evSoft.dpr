program evSoft;

{ check-init fixture events-softwriters (lane HBEVENTS): soft writers (address taken, with-opaque,
  unresolved, DFM streaming, absolute alias) and the NEVER-SET twin GPlain / GPlainTwin.
  Positions are asserted by tests\autotest\run_check_init_events.ps1. }

uses
  Vcl.Forms,
  evsData in 'evsData.pas',
  evsForm in 'evsForm.pas' {SoftForm};

begin
  Application.Initialize;
  Application.CreateForm(TSoftForm, SoftForm);
  Application.Run;
end.
