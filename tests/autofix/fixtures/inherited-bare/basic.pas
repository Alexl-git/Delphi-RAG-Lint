unit basic;

interface

type
  TBase = class
  public
    constructor Create;
    destructor Destroy; override;
    procedure Run(const A: Integer; var B: string; C: Integer = 3); virtual;
    procedure Pair(X, Y: Integer); virtual;
  end;

  TFoo = class(TBase)
  public
    constructor Create;
    destructor Destroy; override;
    procedure Run(const A: Integer; var B: string; C: Integer = 3); override;
    procedure Pair(X, Y: Integer); override;
  end;

implementation

constructor TBase.Create;
begin
  inherited;
end;

destructor TBase.Destroy;
begin
  inherited;
end;

procedure TBase.Run(const A: Integer; var B: string; C: Integer);
begin
  B := 'x';
end;

procedure TBase.Pair(X, Y: Integer);
begin
  X := Y;
end;

constructor TFoo.Create;
begin
  inherited;
end;

destructor TFoo.Destroy;
begin
  inherited;
end;

procedure TFoo.Run(const A: Integer; var B: string; C: Integer);
begin
  inherited;
end;

procedure TFoo.Pair(X, Y: Integer);
begin
  inherited;
end;

end.
