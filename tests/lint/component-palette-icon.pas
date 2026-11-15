unit component_palette_icon;

{ Fixture for component-palette-icon (hint).
  The unit includes component_palette_icon_fx.res, which does not exist; the
  rule then reads the .rc script beside it, which names TICONOK and
  TICONSIZED_24. Fires for a registered class with no resource of its name.
  Silent: a resource named like the class, or that name plus a size suffix,
  and a class passed to RegisterNoIcon. (+) must fire, (-) must not. }

interface

uses
  Classes;

type
  TIconOk = class(TComponent);
  TIconSized = class(TComponent);
  TIconMissing = class(TComponent);
  TNoIconWanted = class(TComponent);

procedure Register;

implementation

{$R component_palette_icon_fx.res component_palette_icon_fx.rc}

procedure Register;
begin
  RegisterComponents('Fixture', [
    TIconOk, { (-) }
    TIconSized, { (-) }
    TIconMissing { (+) }
  ]);
  RegisterNoIcon([TNoIconWanted]);
  RegisterComponents('Fixture', [TNoIconWanted]); { (-) }
end;

end.
