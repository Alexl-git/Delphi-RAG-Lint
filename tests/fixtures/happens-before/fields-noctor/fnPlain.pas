unit fnPlain;

interface

type
  TPlain = class
  private
    FValue: TObject;
    FNever: TObject;
  public
    procedure Load;
    procedure Show;
  end;

  TPlain2 = class
  private
    FValue: TObject;
  public
    constructor Create;
    procedure Show;
  end;

implementation

procedure TPlain.Load;
begin
  FValue:= TObject.Create;
end;

procedure TPlain.Show;
begin
  FValue.ToString;    // USE-NOCTOR
  FNever.ToString;    // USE-NEVER
end;

constructor TPlain2.Create;
begin
  inherited Create;
  FValue:= TObject.Create;
end;

procedure TPlain2.Show;
begin
  FValue.ToString;    // USE-CTOR
end;

end.