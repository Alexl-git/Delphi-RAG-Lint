unit MissingInherited;

interface

type
  TFoo = class
    constructor Create;
    destructor Destroy; override;
  end;

  TBar = class
    constructor Create;
    destructor Destroy; override;
  end;

implementation

constructor TFoo.Create;
begin
  WriteLn('no inherited');
end;

destructor TFoo.Destroy;
begin
  WriteLn('no inherited');
end;

constructor TBar.Create;
begin
  inherited Create;
  WriteLn('ok');
end;

destructor TBar.Destroy;
begin
  inherited;
  WriteLn('ok');
end;

end.
