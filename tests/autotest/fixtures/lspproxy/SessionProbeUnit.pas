unit SessionProbeUnit;

interface

type
  TProbe = class
  public
    procedure DoThing;
    function  Value: Integer;
  end;

implementation

procedure TProbe.DoThing;
begin
end;

function TProbe.Value: Integer;
begin
  Result := 1;
end;

end.