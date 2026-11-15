unit component_default_mismatch;

{ Fixture for component-default-mismatch (warning).
  Fires at the default value when a constructor sets the property or its field
  to another literal of the same kind, and when a non-zero / True default is
  never set by anything but the setter. Silent: equal values ($10 = 16), a
  default of 0, a field set by a helper the constructor calls, a conditional
  assignment, a different kind of literal, a value set through the property
  name (ByName := 2) rather than the field. (+) must fire, (-) must not. }

interface

uses
  Classes, Controls, Graphics;

type
  TStyleKind = (skFlat, skRaised);

  TDefaults = class(TCustomControl)
  private
    FSize: Integer;
    FWide: Integer;
    FKind: TStyleKind;
    FShown: Boolean;
    FZero: Integer;
    FNever: Integer;
    FFlag: Boolean;
    FViaInit: Integer;
    FCond: Integer;
    FMixed: Integer;
    FByName: Integer;
    procedure SetNever(AValue: Integer);
    procedure SetByName(AValue: Integer);
    procedure InitDefaults;
  public
    constructor Create(AOwner: TComponent); override;
  published
    property Size: Integer read FSize write FSize default 5; { (+) }
    property Wide: Integer read FWide write FWide default $10; { (-) }
    property Kind: TStyleKind read FKind write FKind default skFlat; { (+) }
    property Shown: Boolean read FShown write FShown default True; { (-) }
    property Zero: Integer read FZero write FZero default 0; { (-) }
    property Never: Integer read FNever write SetNever default 3; { (+) }
    property Flag: Boolean read FFlag write FFlag default True; { (+) }
    property ViaInit: Integer read FViaInit write FViaInit default 7; { (-) }
    property Cond: Integer read FCond write FCond default 2; { (-) }
    property Mixed: Integer read FMixed write FMixed default 1; { (-) }
    property Color default clWhite; { (+) }
    property ParentColor default False; { (-) }
    property ByName: Integer read FByName write SetByName default 2; { (-) }
  end;

implementation

const
  MIXED_START = 4;

constructor TDefaults.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FSize := 10;
  FWide := 16;
  FKind := skRaised;
  FShown := True;
  Color := clBlack;
  ParentColor := False;
  FMixed := MIXED_START;
  ByName := 2;
  InitDefaults;
  if AOwner = nil then
    FCond := 4;
end;

procedure TDefaults.InitDefaults;
begin
  FViaInit := 7;
end;

procedure TDefaults.SetByName(AValue: Integer);
begin
  FByName := AValue;
end;

procedure TDefaults.SetNever(AValue: Integer);
begin
  FNever := AValue;
end;

end.
