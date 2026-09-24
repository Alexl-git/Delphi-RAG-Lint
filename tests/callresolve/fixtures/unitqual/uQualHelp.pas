unit uQualHelp;

{ Fixture for run_unit_qualified_call_bind.ps1: a single-segment unit whose
  name a local variable in uQualUse deliberately reuses. }

interface

procedure DoIt(A: Integer);

{ D22: a unit var spelled like Qual.Lib's, so a local named uQualHelp has a
  wrong target to be bound to if the unit rung ignores the shadow. }
var
  GLimit: Integer;

implementation

procedure DoIt(A: Integer);
begin
end;

end.
