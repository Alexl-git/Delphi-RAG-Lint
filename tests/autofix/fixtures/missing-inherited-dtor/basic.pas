unit basic;

interface

type
  TBase = class
  public
    destructor Destroy; override;
  end;

  TFoo = class(TBase)
  private
    FCount: Integer;
  public
    destructor Destroy; override;
  end;

implementation

destructor TBase.Destroy;
begin
  inherited Destroy;
end;

destructor TFoo.Destroy;
begin
  FCount := 0;
end;

end.
