unit uFix2Hb;

{ Fixture of tests\autotest\run_v156_FIX2A.ps1 (F2): check-init must not prove YES through a var / out
  argument. One twin per kind: GVarW (var argument), GOutW (out argument), GAsgW (plain assignment, the
  positive control). All three are written and read in the initialization section (no routine body), so
  only the check-init solver can answer. }

interface

implementation

var
  GVarW: Integer;
  GOutW: Integer;
  GAsgW: Integer;

procedure Sink(pValue: Integer);
begin
  if pValue > 0 then Exit;
end;

procedure FillVar(var pX: Integer);
begin
  if Random(2) = 0 then pX:= 1;
end;

procedure FillOut(out pX: Integer);
begin
  pX:= 2;
end;

initialization
  FillVar(GVarW);
  Sink(GVarW);
  FillOut(GOutW);
  Sink(GOutW);
  GAsgW:= 5;
  Sink(GAsgW);

end.
