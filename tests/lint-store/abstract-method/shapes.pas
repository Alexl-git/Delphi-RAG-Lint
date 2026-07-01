unit shapes;

interface

type
  TShape = class
  public
    function Area: Double; virtual; abstract;
    procedure Describe;
  end;

  TCircle = class(TShape)
  public
    function Area: Double; override;
  end;

implementation

procedure TShape.Describe;
begin
end;

function TCircle.Area: Double;
begin
  Result := 3.14;
end;

end.
