unit uUnitVarArr;

{ Item 4 (f): a selector-chain HEAD that is a UNIT-LEVEL var. GArr[1].K must
  read the element type from the var's declaration text; GOne.K binds as
  before; GArr.K (no selector) declines. TOther.K makes a wrong edge visible. }

interface

type
  TLeaf = class
  public
    procedure K;
  end;

  TOther = class
  public
    procedure K;
  end;

var
  GArr: array [0 .. 3] of TLeaf;
  GOne: TLeaf;

procedure Go;

implementation

procedure TLeaf.K; begin end;
procedure TOther.K; begin end;

procedure Go;
begin
  GArr[1].K; // U1
  GOne.K;    // U2
  GArr.K;    // U3
end;

end.