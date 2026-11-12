program MetaInit;

// Plan fixture (lane CYC3 finisher, FOUND-152c a): the metaclass hand-over of MiA -> MiB with an init-order
// proof (MiA listed first: MiB initializes before MiA). run_cyclefix_metaclass_initorder.ps1 rewrites the
// uses list for the MiB-first order, where the same edge is refused `init-order`.

{$APPTYPE CONSOLE}

uses
  MiA in 'MiA.pas',
  MiB in 'MiB.pas',
  MiC in 'MiC.pas';

begin
  Writeln('main');
end.
