unit uPreCtl;

{ Fixture of run_v156_HB5.ps1, pre-check: the twin of pre -- Boot calls SeedIt and then Roll, so the pre-check must NOT refute
  -> YES (callers). }

interface

var
  GLast: Integer;

procedure Boot;

implementation

procedure SeedIt;
begin
  Randomize;
end;

function Roll: Integer;
begin
  Result:= Random(6);
end;

procedure Boot;
begin
  SeedIt;
  GLast:= Roll;
end;

end.
