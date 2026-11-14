unit component_palette_icon_none;

{ Fixture for component-palette-icon (hint): the unit includes no resource and
  no .dcr sits beside it, so every registered class fires. (+) must fire. }

interface

uses
  Classes;

type
  TLonely = class(TComponent);

procedure Register;

implementation

procedure Register;
begin
  RegisterComponents('Fixture', [TLonely]); { (+) }
end;

end.
