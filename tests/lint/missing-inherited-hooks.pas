unit MissingInheritedHooks;
{ missing-inherited-ctor / -dtor, v151 widening: AfterConstruction and
  BeforeDestruction overrides that never call inherited. The second class calls
  it in both and stays quiet (missing-inherited-hooks-clean). }
interface
type
  TWatcher = class(TObject)
  public
    procedure AfterConstruction; override;
    procedure BeforeDestruction; override;
  end;

implementation

procedure TWatcher.AfterConstruction;
begin
  Register(Self);
end;

procedure TWatcher.BeforeDestruction;
begin
  Unregister(Self);
end;

end.
