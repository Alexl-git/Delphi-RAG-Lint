unit managedclass;

interface

type
  IThing = class
  public
    Value: Integer;
  end;

implementation

function P: Integer;
var x: IThing;
begin
  Result := 0;
  if x.Value > 0 then Result := 1;
end;

end.
