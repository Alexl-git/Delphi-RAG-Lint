unit hides_ancestor_virtual_component_ctor;

{ Fixture for hides-ancestor-virtual (warning) on the component constructor:
  `constructor Create(AOwner: TComponent);` without override in a descendant of
  a class whose constructor Create is virtual -- the shape the form loader calls
  through the class reference, so the descendant's constructor never runs for a
  component created from a form file. The ancestor stands in for TComponent
  here, in the same file, because this harness runs without an index; the
  cross-unit case is in tests\autotest\run_v151_CMP_store_rules.ps1.
  (+) must fire, (-) must not. }

interface

type
  TComponentLike = class
  public
    constructor Create(AOwner: TComponentLike); virtual;
  end;

  TMyPanel = class(TComponentLike)
  public
    constructor Create(AOwner: TComponentLike); { (+) }
  end;

  TMyPanelOk = class(TComponentLike)
  public
    constructor Create(AOwner: TComponentLike); override; { (-) }
  end;

  TMyPanelNew = class(TComponentLike)
  public
    constructor Create(AOwner: TComponentLike); reintroduce; { (-) }
  end;

  TMyPanelMore = class(TComponentLike)
  public
    constructor Create(AOwner: TComponentLike; ATag: Integer); overload; { (-) }
  end;

implementation

constructor TComponentLike.Create(AOwner: TComponentLike);
begin
  inherited Create;
end;

constructor TMyPanel.Create(AOwner: TComponentLike);
begin
  inherited Create(AOwner);
end;

constructor TMyPanelOk.Create(AOwner: TComponentLike);
begin
  inherited Create(AOwner);
end;

constructor TMyPanelNew.Create(AOwner: TComponentLike);
begin
  inherited Create(AOwner);
end;

constructor TMyPanelMore.Create(AOwner: TComponentLike; ATag: Integer);
begin
  inherited Create(AOwner);
end;

end.
