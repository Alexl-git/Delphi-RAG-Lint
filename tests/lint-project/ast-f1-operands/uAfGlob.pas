unit uAfGlob;

{ Fixture of run_ast_f1_operands.ps1, row 21 (mutable-global-variable, OFF; index fact F2).
  CONTROL-GLOB: written only inside the initialization section, so it is set once before the
  program runs. With the section attribution the rule skips it; without it (an older index, or
  no index) it still reports it. TRIGGER-GLOB: written by a routine, never written, and written
  both in the section and by a routine: reported in every run. }

interface

procedure AfSetLate;

implementation

var
  GOnce   : Integer; // CONTROL-GLOB-1
  GLate   : Integer; // TRIGGER-GLOB-1
  GNever  : Integer; // TRIGGER-GLOB-2
  GBoth   : Integer; // TRIGGER-GLOB-3

procedure AfSetLate;
begin
  GLate:= 1;
  GBoth:= 2;
end;

initialization
  GOnce:= 1;
  GBoth:= 3;

end.
