unit ConstructorCallOnInstance;

interface

type
  TFoo = class
    constructor Create(AValue: Integer = 0);
  end;

  TBar = class(TFoo)
  private
    FOther: TFoo;
  public
    constructor Create;
    procedure Reset;
  end;

implementation

constructor TFoo.Create(AValue: Integer);
begin
  inherited Create;
end;

constructor TBar.Create;
begin
  inherited Create(1);
  FOther.Create;
end;

procedure TBar.Reset;
begin
  FOther.Create(2);
end;

procedure Bad;
var
  X: TFoo;
begin
  X.Create;
  X.Create(5);
end;

procedure Good(P: TFoo);
var
  X: TFoo;
begin
  X := TFoo.Create;
  X := TFoo.Create(5);
  TFoo.Create;
  P.Create(3);
end;

end.
