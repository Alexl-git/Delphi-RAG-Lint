unit Calls;

interface

type
  TWidget = class
  public
    procedure Init;
    function Compute(AValue: Integer): Integer;
  end;

implementation

procedure TWidget.Init;
begin
  Compute(10);
  Self.Compute(20);
end;

function TWidget.Compute(AValue: Integer): Integer;
var
  Tmp: Integer;
begin
  Tmp := AValue * 2;
  WriteLn('hi');
  Result := Tmp + Compute(0);
end;

end.
