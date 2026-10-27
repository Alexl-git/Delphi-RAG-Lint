unit basic;

interface

type
  TBase = class
  public
    constructor Create;
  end;

  TFoo = class(TBase)
  private
    FCount: Integer;
  public
    constructor Create;
  end;

implementation

constructor TBase.Create;
begin
  inherited Create;
end;

constructor TFoo.Create;
var
  Seed: Integer;
begin
  inherited;
  Seed := 1;
  FCount := Seed;
end;

end.
