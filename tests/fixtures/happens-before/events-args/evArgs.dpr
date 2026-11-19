program evArgs;

{ check-init fixture events-args (lane HBEVENTS): var / out argument writes and their
  controls (const and value parameters do not write). Positions are asserted by
  tests\autotest\run_check_init_events.ps1. }

uses
  evaData in 'evaData.pas';

begin
  Fill(GDpr);
  Run;
end.
