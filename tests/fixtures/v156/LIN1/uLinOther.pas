unit uLinOther;

{ Fixture of tests\autotest\run_v156_LIN1.ps1 (1.56 lane LIN-1; SPEC-LIN 5.2 "uLinWhere + uLinOther"): a write
  of a field of ANOTHER unit's form. Never compiled: it is indexed. }

interface

procedure Poke;

implementation

uses
  uLinWhere;

procedure Poke;
begin
  fLinWhere.tblOrdersX.AsFloat := fLinWhere.tblOrdersQTY.AsFloat; { M-X }
end;

end.
