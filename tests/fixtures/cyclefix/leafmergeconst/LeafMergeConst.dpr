program LeafMergeConst;

// Plan fixture (lane cyc4): the leaves are mutual and one of them moves a const, which breaks the one
// `type` block a forward declaration needs: refused coupling-remains, never a wrong "mechanical".

{$APPTYPE CONSOLE}

uses
  LcA in 'LcA.pas',
  LcB in 'LcB.pas';

begin
end.
