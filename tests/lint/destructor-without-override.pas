unit dtor;
interface
type
  TFoo = class
  public
    destructor Destroy;
  end;
  TBar = class
  public
    destructor Destroy; override;
  end;
implementation
destructor TFoo.Destroy;
begin
end;
destructor TBar.Destroy;
begin
  inherited;
end;
end.
