unit feEsc;

interface

type
  TEsc = class
  private
    FData: TObject;
  public
    constructor Create;
    procedure Show;
  end;

  TEsc2 = class
  private
    FData: TObject;
  public
    constructor Create;
    procedure Show;
  end;

  TOver = class
  private
    FN: TObject;
  public
    constructor Create(pN: Integer); overload;
    procedure Show;
  end;

  TOver2 = class
  private
    FN: TObject;
  public
    constructor Create(pN: Integer);
    procedure Show;
  end;

procedure Register(pObj: TObject);

implementation

var
  GLast: TObject;

procedure Register(pObj: TObject);
begin
  GLast:= pObj;
end;

constructor TEsc.Create;
begin
  inherited Create;
  Register(Self);
  FData:= TObject.Create;
end;

procedure TEsc.Show;
begin
  FData.ToString;     // USE-ESC
end;

constructor TEsc2.Create;
begin
  inherited Create;
  FData:= TObject.Create;
  Register(Self);
end;

procedure TEsc2.Show;
begin
  FData.ToString;     // USE-ESC2
end;

constructor TOver.Create(pN: Integer);
begin
  inherited Create;
  FN:= TObject.Create;
end;

procedure TOver.Show;
begin
  FN.ToString;        // USE-OVER
end;

constructor TOver2.Create(pN: Integer);
begin
  inherited Create;
  FN:= TObject.Create;
end;

procedure TOver2.Show;
begin
  FN.ToString;        // USE-OVER2
end;

end.