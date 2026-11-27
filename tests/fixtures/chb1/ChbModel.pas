unit ChbModel;

interface

type
  TPart = class
  end;

  TBase = class
  public
    procedure Touch;
  end;

  TOwner = class(TBase)
  private
    FBase: TBase;
    FPart: TPart;
    FCount: Integer;
  public
    procedure Run;
  end;

implementation

procedure TBase.Touch;
begin
end;

procedure TOwner.Run;
begin
  FBase.Touch;
  Touch;
  FPart.Free;
  Self.Touch;
end;

end.
