unit fvShapes;

interface

type
  TBase = class
  public
    constructor Create;
    procedure Setup; virtual;
  end;

  TDerived = class(TBase)
  private
    FItems: TObject;
  public
    constructor Create;
    procedure Setup; override;
    procedure Use;
  end;

  TBase2 = class
  public
    constructor Create;
    procedure Setup; virtual;
  end;

  TDerived2 = class(TBase2)
  private
    FItems: TObject;
  public
    constructor Create;
    procedure Setup; override;
  end;

implementation

constructor TBase.Create;
begin
  inherited Create;
  Setup;
end;

procedure TBase.Setup;
begin
end;

constructor TDerived.Create;
begin
  inherited Create;
  FItems:= TObject.Create;
end;

procedure TDerived.Setup;
begin
  FItems.ToString;    // USE-VIRT
end;

procedure TDerived.Use;
begin
  FItems.ToString;    // USE-PLAIN
end;

constructor TBase2.Create;
begin
  inherited Create;
end;

procedure TBase2.Setup;
begin
end;

constructor TDerived2.Create;
begin
  inherited Create;
  FItems:= TObject.Create;
end;

procedure TDerived2.Setup;
begin
  FItems.ToString;    // USE-VIRT2
end;

end.