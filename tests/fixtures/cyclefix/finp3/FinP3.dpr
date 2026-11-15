program FinP3;

// Plan fixture (lane FINPROOF): the .dpr order decides whether FP3B is finalized after FP3A. The guard
// run_cyclefix_final_order_proof_dcc.ps1 rewrites this uses list for the other two orders.

{$APPTYPE CONSOLE}

uses
  FP3A in 'FP3A.pas',
  FP3B in 'FP3B.pas',
  FP3C in 'FP3C.pas';

begin
  Writeln('main');
end.
