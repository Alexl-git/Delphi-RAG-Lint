program QualPartA;

// Plan fixture (lane cyc4): Part A moves CQpTop into the leaf; QpA and QpC (outside the cycle) name it
// qualified by its old unit, and that text must follow the move or neither compiles.

{$APPTYPE CONSOLE}

uses
  QpB in 'QpB.pas',
  QpA in 'QpA.pas',
  QpC in 'QpC.pas';

begin
  QpAShow;
  QpCShow;
end.
