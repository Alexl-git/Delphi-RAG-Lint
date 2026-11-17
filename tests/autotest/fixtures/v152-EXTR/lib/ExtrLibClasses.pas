unit ExtrLibClasses;

interface

type
  TStringList = class
  public
    constructor Create;
    procedure Add(const pText: string);
    function Count: Integer;
  end;

  TCustomStyleServices = class
  public
    function GetSystemColor(pColor: Integer): Integer;
  end;

  TObjectList<T: class> = class
  public
    constructor Create(pOwns: Boolean);
    procedure Add(pItem: T);
  end;

function StyleServices(pOwner: TObject = nil): TCustomStyleServices;

implementation

constructor TStringList.Create;
begin
end;

procedure TStringList.Add(const pText: string);
begin
end;

function TStringList.Count: Integer;
begin
  Result := 0;
end;

function TCustomStyleServices.GetSystemColor(pColor: Integer): Integer;
begin
  Result := pColor;
end;

constructor TObjectList<T>.Create(pOwns: Boolean);
begin
end;

procedure TObjectList<T>.Add(pItem: T);
begin
end;

function StyleServices(pOwner: TObject): TCustomStyleServices;
begin
  Result := nil;
end;

end.