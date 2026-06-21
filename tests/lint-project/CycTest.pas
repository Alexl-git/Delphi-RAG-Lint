unit CycTest;
interface
type
  IAlpha = interface
    procedure A;
  end;
  IBeta = interface
    procedure B;
  end;
  TAlpha = class(TInterfacedObject, IAlpha)
  private
    FBeta: IBeta;
  public
    procedure A;
  end;
  TBeta = class(TInterfacedObject, IBeta)
  private
    FAlpha: IAlpha;
  public
    procedure B;
  end;
implementation
procedure TAlpha.A; begin end;
procedure TBeta.B; begin end;
end.
