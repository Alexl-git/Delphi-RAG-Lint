unit propself;
interface
type
  TFoo = class
  private
    FBar: Integer;
  public
    property Bar: Integer read Bar;
    property Baz: Integer read FBar write FBar;
  end;

  TAcc = class
  private
    FX: Integer;
    FY: Integer;
    function GetX: Integer;
    procedure SetX(AValue: Integer);
    function GetY: Integer;
    procedure SetY(AValue: Integer);
    function GetZ: Integer;
  public
    property X: Integer read GetX write SetX;
    property Y: Integer read GetY write SetY;
    property Z: Integer read GetZ;
  end;
implementation

function TAcc.GetX: Integer;
begin
  Result:= X;
end;

procedure TAcc.SetX(AValue: Integer);
begin
  X:= AValue;
end;

function TAcc.GetY: Integer;
begin
  Result:= FY;
end;

procedure TAcc.SetY(AValue: Integer);
begin
  FY:= AValue;
end;

function TAcc.GetZ: Integer;
begin
  Result:= Self.Z + 1;
end;

end.