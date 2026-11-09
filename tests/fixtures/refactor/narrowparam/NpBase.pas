unit NpBase;

// TLeaf -> TMid -> TBase -> TRoot, with the traps narrow-param must see.

interface

uses
  NpRoot;

type
  TBase = class(TRoot)
  public
    BaseField: Integer;
    procedure BaseOnly;
    procedure Hidden;
    procedure Over(pA: Integer); overload;
    procedure Over(const pA: string); overload;
    procedure VirtualM; virtual;
    function GetSelf: TBase;
    property BaseProp: Integer read BaseField write BaseField;
  end;

  TMid = class(TBase)
  public
    MidField: Integer;
    procedure MidOnly;
    procedure Hidden;
    procedure VirtualM; override;
  end;

  TLeaf = class(TMid)
  public
    procedure LeafOnly;
  end;

  TGenBase<T> = class(TRoot)
  public
    GenField: Integer;
  end;

  TGenLeaf = class(TGenBase<Integer>)
  public
    procedure GenLeafOnly;
  end;

  ICounted = interface
    procedure Consume(pValue: TLeaf);
  end;

procedure TakeBase(pValue: TBase);
procedure TakeLeaf(pValue: TLeaf);

implementation

procedure TBase.BaseOnly;
begin
end;

procedure TBase.Hidden;
begin
end;

procedure TBase.Over(pA: Integer);
begin
end;

procedure TBase.Over(const pA: string);
begin
end;

procedure TBase.VirtualM;
begin
end;

function TBase.GetSelf: TBase;
begin
  Result:= Self;
end;

procedure TMid.MidOnly;
begin
end;

procedure TMid.Hidden;
begin
end;

procedure TMid.VirtualM;
begin
end;

procedure TLeaf.LeafOnly;
begin
end;

procedure TGenLeaf.GenLeafOnly;
begin
end;

procedure TakeBase(pValue: TBase);
begin
end;

procedure TakeLeaf(pValue: TLeaf);
begin
end;

end.