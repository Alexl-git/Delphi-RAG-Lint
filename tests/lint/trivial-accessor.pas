unit TrivialAccessor;

interface

type
  TCustomer = class
  private
    FName: string;
    FCity: string;
    function GetName: string;
    procedure SetName(const Value: string);
    function GetCity: string;
    procedure SetCity(const Value: string);
  public
    property Name: string read GetName write SetName;
    property City: string read GetCity write SetCity;
  end;

implementation

function TCustomer.GetName: string;
begin
  Result := FName;
end;

procedure TCustomer.SetName(const Value: string);
begin
  FName := Value;
end;

function TCustomer.GetCity: string;
begin
  Result := Trim(FCity);
end;

procedure TCustomer.SetCity(const Value: string);
begin
  if Value <> FCity then
    FCity := Value;
end;

end.
