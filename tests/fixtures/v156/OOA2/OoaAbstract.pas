unit OoaAbstract;

interface

uses
  System.Classes;

type
  TShape = class
  public
    procedure Area; virtual; abstract;
    procedure Describe; virtual; abstract;
  end;

  TCircle = class(TShape)  // FIRE abstract-method-not-overridden
  public
    procedure Area; override;
  end;

  TNothing = class(TShape)  // FIRE abstract-method-not-overridden
  end;

  TSquare = class(TShape)
  public
    procedure Area; override;
    procedure Describe; override;
  end;

  TMidway = class(TShape)
  public
    procedure Area; override;
  end;

  TMidwayLeaf = class(TMidway)
  public
    procedure Describe; override;
  end;

  TOpenMid = class(TShape)
  end;

  TOpenMidLeaf = class(TOpenMid)
  public
    procedure Area; override;
    procedure Describe; override;
  end;

  TStillAbstract = class abstract(TShape)
  end;

  TPlain = class
  public
    procedure Work; virtual;
  end;

  TPlainLeaf = class(TPlain)
  end;

  TListLeaf = class(TStringList)
  end;

  TOver = class
  public
    procedure Put(AValue: Integer); overload; virtual; abstract;
    procedure Put(const AValue: string); overload; virtual; abstract;
  end;

  TOverLeaf = class(TOver)
  public
    procedure Put(AValue: Integer); override;
  end;

implementation

procedure TCircle.Area;
begin
end;

procedure TSquare.Area;
begin
end;

procedure TSquare.Describe;
begin
end;

procedure TMidway.Area;
begin
end;

procedure TMidwayLeaf.Describe;
begin
end;

procedure TOpenMidLeaf.Area;
begin
end;

procedure TOpenMidLeaf.Describe;
begin
end;

procedure TPlain.Work;
begin
end;

procedure TOverLeaf.Put(AValue: Integer);
begin
end;

end.
