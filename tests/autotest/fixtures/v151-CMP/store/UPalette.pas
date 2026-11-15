unit UPalette;

{ component-palette-icon against a COMPILED resource: the runner writes
  UPalette.dcr (32-bit resource format) with one bitmap, TPALOK, next to this
  unit before it lints. (+) must fire, (-) must not. }

interface

uses
  Classes;

type
  TPalOk = class(TComponent);
  TPalMissing = class(TComponent);

procedure Register;

implementation

{$R *.dcr}

procedure Register;
begin
  RegisterComponents('Fixture', [
    TPalOk, { (-) }
    TPalMissing { (+) }
  ]);
end;

end.
