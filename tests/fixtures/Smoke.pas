unit Smoke;

interface

type
  TFoo = class
  public
    procedure DoBar;
    function GetBaz: Integer;
  end;

implementation

procedure TFoo.DoBar;
begin
  // body
end;

function TFoo.GetBaz: Integer;
begin
  Result := 42;
end;

end.
