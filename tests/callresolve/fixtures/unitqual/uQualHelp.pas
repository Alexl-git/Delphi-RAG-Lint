unit uQualHelp;

{ Fixture for run_unit_qualified_call_bind.ps1: a single-segment unit whose
  name a local variable in uQualUse deliberately reuses. }

interface

procedure DoIt(A: Integer);

implementation

procedure DoIt(A: Integer);
begin
end;

end.
