unit Kinds;

interface

type
  TColor = (clRed, clGreen, clBlue);

  TPoint = record
    X: Integer;
    Y: Integer;
    procedure Reset;
  end;

  IShape = interface(IUnknown)
    ['{F1E2D3C4-B5A6-4978-A0B1-C2D3E4F5A6B7}']
    function Area: Double;
    property Name: string read GetName;
  end;

  TShape = class(TInterfacedObject, IShape)
  strict private
    FName: string;
    FColor: TColor;
  public
    constructor Create(const AName: string);
    function Area: Double; virtual; abstract;
    property Name: string read FName write FName;
    property Color: TColor read FColor;
  end;

implementation

procedure TPoint.Reset;
begin
  X := 0;
  Y := 0;
end;

constructor TShape.Create(const AName: string);
begin
  inherited Create;
  FName := AName;
end;

end.
