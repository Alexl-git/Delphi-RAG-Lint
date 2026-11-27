unit UTight;

{ G-24 visibility-tightening fixture. (+) must be reported, (-) must not.
  Every (-) is one exemption of the rule; every (+) is its positive control. }

interface

uses
  UIfaceT;

type
  TMyAttr = class(TCustomAttribute);

  TBase = class(TInterfacedObject, IThingT)
  private
    FOnlyOwn: Integer; { (+) }
    FSeenByDesc: Integer; { (-) }
    FSeenByOther: Integer; { (-) }
    [TMyAttr]
    FTagged: Integer; { (-) }
    procedure OwnProc; { (+) }
    procedure DescProc; { (-) }
    [TMyAttr]
    procedure AttrProc; { (-) }
  strict private
    FAlready: Integer; { (-) }
  protected
    procedure ForKids; { (+) }
    procedure ForKidsOtherInstance; { (-) }
    procedure ForSameUnitOther; { (-) }
    procedure OnlyOwnProt; { (+) }
    procedure VirtProt; virtual; { (-) }
    procedure Execute; { (-) }
    procedure Unref; { (-) }
  public
    procedure ForKidsPublic; { (+) }
    procedure UsedByAll; { (-) }
    procedure OwnFilePublic; { (-) }
    procedure Run;
  published
    procedure PubProc; { (-) }
  end;

  TDescSame = class(TBase)
  public
    procedure Go;
  end;

  TOtherCls = class
  public
    procedure Touch(B: TBase);
  end;

implementation

procedure TBase.OwnProc;
begin
  FOnlyOwn:= FOnlyOwn + 1;
end;

procedure TBase.DescProc;
begin
end;

procedure TBase.AttrProc;
begin
  FTagged:= 1;
end;

procedure TBase.ForKids;
begin
end;

procedure TBase.ForKidsOtherInstance;
begin
end;

procedure TBase.ForSameUnitOther;
begin
end;

procedure TBase.OnlyOwnProt;
begin
end;

procedure TBase.VirtProt;
begin
end;

procedure TBase.Execute;
begin
end;

procedure TBase.Unref;
begin
end;

procedure TBase.ForKidsPublic;
begin
end;

procedure TBase.UsedByAll;
begin
end;

procedure TBase.OwnFilePublic;
begin
end;

procedure TBase.PubProc;
begin
end;

procedure TBase.Run;
begin
  OwnProc;
  OnlyOwnProt;
  VirtProt;
  Execute;
  AttrProc;
  OwnFilePublic;
  FAlready:= 1;
end;

procedure TDescSame.Go;
begin
  DescProc;
  FSeenByDesc:= 2;
end;

procedure TOtherCls.Touch(B: TBase);
begin
  B.FSeenByOther:= 3;
  B.ForSameUnitOther;
end;

end.
