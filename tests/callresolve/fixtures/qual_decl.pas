unit qual_decl;

{ Declaring half of run_receiver_qualified_cross_unit.ps1.

  The same-unit case (receiver_bucket.pas) was the only qualified-receiver shape
  under test. CROSS-unit qualification is the one that actually matters: Delphi
  FORCES `UnitName.TType.Create` whenever two used units export the same type
  name, so this is where a developer meets it. }

interface

type
  TOnlyOnce = class
    constructor Create(AValue: Integer);
  end;

implementation

constructor TOnlyOnce.Create(AValue: Integer);
begin
end;

end.
