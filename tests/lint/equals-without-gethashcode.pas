unit EqualsWithoutGetHashCode;

interface

type
  TKundenNr = class
  public
    function Equals(Obj: TObject): Boolean; override;
  end;

  THashOnly = class
  public
    function GetHashCode: Integer; override;
  end;

  TBoth = class
  public
    function Equals(Obj: TObject): Boolean; override;
    function GetHashCode: Integer; override;
  end;

  TOtherEquals = class
  public
    function Equals(A, B: TObject): Boolean; reintroduce;
  end;

implementation

function TKundenNr.Equals(Obj: TObject): Boolean;
begin
  Result := Obj = Self;
end;

function THashOnly.GetHashCode: Integer;
begin
  Result := 1;
end;

function TBoth.Equals(Obj: TObject): Boolean;
begin
  Result := Obj = Self;
end;

function TBoth.GetHashCode: Integer;
begin
  Result := 1;
end;

function TOtherEquals.Equals(A, B: TObject): Boolean;
begin
  Result := A = B;
end;

end.
