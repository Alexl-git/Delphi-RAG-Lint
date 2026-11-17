program RootsOrder;

{ v152 HBROOTS roots-order: uses OrdA (OrdA -> OrdB -> OrdC; OrdC implementation-uses OrdB, OrdB
  implementation-uses OrdA), then OrdD. Computed order OrdC, OrdB, OrdA, OrdD; then the program block.
  OrdC's initialization reads OrdB.GB and OrdB's reads OrdA.GA, so init-order-hazard names both
  inversions -- the second engine call the runner checks the chain against. }

{$APPTYPE CONSOLE}

uses
  OrdA in 'OrdA.pas',
  OrdD in 'OrdD.pas';

begin
  Writeln('MAIN');
end.