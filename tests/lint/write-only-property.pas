unit write_only_property;

{ Fixture for write-only-property (hint, OFF by default; the .config.json
  enables it). Fires on a typed property with write and no read, in a class or
  an interface. Silent: read / write, read-only, the dispinterface writeonly
  form. (+) must fire, (-) must not. }

interface

type
  TCredentials = class
  private
    FPassword: string;
    FName: string;
    procedure SetPassword(const Value: string);
    function GetName: string;
    procedure SetName(const Value: string);
  public
    property Password: string write SetPassword; { (+) }
    property Name: string read GetName write SetName; { (-) }
    property Stored: string read FPassword; { (-) }
  end;

  IWriter = interface
    ['{6E1E5B2C-3C1F-4A39-9C0E-2B7F1D2A4C11}']
    procedure SetLevel(AValue: Integer);
    property Level: Integer write SetLevel; { (+) }
  end;

  ISink = dispinterface
    ['{7F2F6C3D-4D2A-4B4A-8D1F-3C8A2E3B5D22}']
    property Sink: Integer writeonly dispid 1; { (-) }
  end;

implementation

procedure TCredentials.SetPassword(const Value: string);
begin
  FPassword := Value;
end;

function TCredentials.GetName: string;
begin
  Result := FName;
end;

procedure TCredentials.SetName(const Value: string);
begin
  FName := Value;
end;

end.
