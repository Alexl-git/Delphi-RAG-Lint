unit uPre;

{ Fixture of run_v156_HB5.ps1, pre-check: SeedIt (Randomize) is reached from Boot only, Roll (Random) from Other only: no routine that
  performs A reaches B -> MAY, answered by the pre-check with no routine body solved. }

interface

var
  GLast: Integer;

procedure Boot;
procedure Other;

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
end;

procedure Other;
begin
  GLast:= Roll;
end;

end.
