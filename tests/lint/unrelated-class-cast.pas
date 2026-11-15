unit UnrelatedClassCastFixture;

{ unrelated-class-cast: a hard cast T(x) where the static class of x and T are on
  different branches of the class tree. HIT lines must fire, OK lines must not.
  Every class is declared here, so the whole tree is known without an index. }

interface

type
  TShape = class
  public
    FName: string;
  end;

  TCircle = class(TShape)
  public
    FRadius: Double;
  end;

  TSquare = class(TShape)
  public
    FSide: Double;
    procedure Grow; virtual;
  end;

  TBigSquare = class(TSquare)
  end;

  { accessor class: no field, no virtual method -- same layout as TShape }
  TShapeAccess = class(TShape)
  end;

  TOther = class
  public
    FValue: Integer;
  end;

  IShape = interface
    ['{6A1F6A44-5B33-4E7E-9E77-0C5E6A51B001}']
  end;

  TRec = record
    X: Integer;
  end;

  TDrawer = class
  private
    FCircle: TCircle;
  public
    procedure Run(ASquare: TSquare; AObj: TObject; AShape: TShape; const AIntf: IShape);
  end;

implementation

procedure TSquare.Grow;
begin
end;

procedure TDrawer.Run(ASquare: TSquare; AObj: TObject; AShape: TShape; const AIntf: IShape);
var
  C: TCircle;
  O: TOther;
  B: TBigSquare;
  P: Pointer;
begin
  C:= TCircle.Create;
  O:= TOther.Create;
  B:= TBigSquare.Create;
  P:= nil;
  TCircle(ASquare).FRadius:= 1; {HIT}
  TSquare(C).FSide:= 2; {HIT}
  TOther(B).FValue:= 3; {HIT}
  TBigSquare(FCircle).Grow; {HIT}
  TSquare(Self.FCircle).Grow; {HIT}
  TCircle(AShape).FRadius:= 4; {OK}
  TShape(C).FName:= 'x'; {OK}
  TCircle(AObj).FRadius:= 5; {OK}
  TSquare(B).Grow; {OK}
  TShapeAccess(C).FName:= 'y'; {OK}
  TCircle(P).FRadius:= 6; {OK}
  TCircle(TObject(O)).FRadius:= 7; {OK}
  TCircle(C).FRadius:= 8; {OK}
  if AIntf <> nil then TObject(O).Free; {OK}
  B.Free;
  O.Free;
  C.Free;
end;

end.
