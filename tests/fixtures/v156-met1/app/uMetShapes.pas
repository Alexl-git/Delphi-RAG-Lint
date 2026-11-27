unit uMetShapes;

{ Fixture of tests\autotest\run_v156_MET1.ps1 (1.56 lane MET-1), G-59:
  IShape has two implementors (not listed), IOnly has one (listed);
  TBase has one descendant (listed), TMulti has two (not listed). }

interface

uses
  uMetUtil, uMetCalc;

type
  IShape = interface
    ['{8C0B4B0E-6B0B-4E0B-9D3A-0A1B2C3D4E01}']
    function Area: Integer;
  end;

  IOnly = interface
    ['{8C0B4B0E-6B0B-4E0B-9D3A-0A1B2C3D4E02}']
    function Name: string;
  end;

  TCircle = class(TInterfacedObject, IShape)
  private
    FRadius: Integer;
  public
    constructor Create(pRadius: Integer);
    function Area: Integer;
  end;

  TSquare = class(TInterfacedObject, IShape)
  private
    FSide: Integer;
  public
    constructor Create(pSide: Integer);
    function Area: Integer;
  end;

  TOnlyImpl = class(TInterfacedObject, IOnly)
  public
    function Name: string;
  end;

  TBase = class
  public
    function Weight: Integer; virtual;
  end;

  TLeaf = class(TBase)
  public
    function Weight: Integer; override;
  end;

  TMulti = class
  end;

  TMultiA = class(TMulti)
  end;

  TMultiB = class(TMulti)
  end;

implementation

constructor TCircle.Create(pRadius: Integer);
begin
  inherited Create;
  FRadius:= Clamp(pRadius, 0, 1000);
end;

function TCircle.Area: Integer;
begin
  // pi is 3 here
  Result:= 3 * FRadius * FRadius;
end;

constructor TSquare.Create(pSide: Integer);
begin
  inherited Create;
  FSide:= pSide;
end;

function TSquare.Area: Integer;
begin
  if FSide > 0 then
    Result:= RectArea(0, 0, FSide, FSide)
  else
    Result:= 0;
end;

function TOnlyImpl.Name: string;
begin
  Result:= 'only';
end;

function TBase.Weight: Integer;
begin
  Result:= 1;
end;

function TLeaf.Weight: Integer;
begin
  Result:= inherited Weight + 1;
end;

end.
