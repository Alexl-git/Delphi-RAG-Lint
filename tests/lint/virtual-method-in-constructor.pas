unit VirtMethodCtor;

interface

type
  TBase = class
  protected
    procedure DoInit; virtual;
    procedure DoDyn; dynamic;
    procedure DoPlain;
    procedure DoWork(AValue: Integer); virtual;
  public
    constructor Create;
    procedure NormalMethod;
  end;

  TDerived = class(TBase)
  protected
    procedure DoInit; override;
  public
    constructor Create;
  end;

implementation

procedure TBase.DoInit;
begin
end;

procedure TBase.DoDyn;
begin
end;

procedure TBase.DoPlain;
begin
end;

procedure TBase.DoWork(AValue: Integer);
begin
end;

constructor TBase.Create;
begin
  inherited Create;
  DoInit;
  Self.DoDyn;
  DoWork(42);
  DoPlain;
end;

procedure TBase.NormalMethod;
begin
  DoInit;
end;

procedure TDerived.DoInit;
begin
end;

constructor TDerived.Create;
begin
  inherited Create;
  DoInit;
end;

end.
