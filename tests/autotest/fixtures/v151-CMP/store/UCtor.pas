unit UCtor;

{ hides-ancestor-virtual on the component constructor, ancestor in another unit:
  TBaseComp (UBaseComp) overrides TComponent's virtual Create. (+) must fire,
  (-) must not. }

interface

uses
  Classes, UBaseComp;

type
  TMyPanel = class(TBaseComp)
  public
    constructor Create(AOwner: TComponent); { (+) }
  end;

  TMyPanelOk = class(TBaseComp)
  public
    constructor Create(AOwner: TComponent); override; { (-) }
  end;

implementation

constructor TMyPanel.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
end;

constructor TMyPanelOk.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
end;

end.
