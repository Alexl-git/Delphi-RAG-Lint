unit fsTree;

interface

type
  TParent = class
  private
    FName: TObject;
  public
    constructor Create;
    procedure Show;
  end;

  TGood = class(TParent)
  public
    constructor Create;
  end;

  TParent2 = class
  private
    FName: TObject;
  public
    constructor Create;
    procedure Show;
  end;

  TSkip = class(TParent2)
  public
    constructor CreateSkip;
  end;

implementation

constructor TParent.Create;
begin
  inherited Create;
  FName:= TObject.Create;
end;

procedure TParent.Show;
begin
  FName.ToString;     // USE-GOOD
end;

constructor TGood.Create;
begin
  inherited Create;
end;

constructor TParent2.Create;
begin
  inherited Create;
  FName:= TObject.Create;
end;

procedure TParent2.Show;
begin
  FName.ToString;     // USE-SKIP
end;

constructor TSkip.CreateSkip;
begin
end;

end.