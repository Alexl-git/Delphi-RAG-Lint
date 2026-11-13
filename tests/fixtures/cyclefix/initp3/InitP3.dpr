program InitP3;

// Plan fixture (lane CYC3): the .dpr order decides whether IP3B initializes before IP3A. The guard
// run_cyclefix_initorder_proof_dcc.ps1 rewrites this uses list for the other two orders.

{$APPTYPE CONSOLE}

uses
  IP3A in 'IP3A.pas',
  IP3B in 'IP3B.pas',
  IP3C in 'IP3C.pas';

begin
  Writeln('main');
end.
