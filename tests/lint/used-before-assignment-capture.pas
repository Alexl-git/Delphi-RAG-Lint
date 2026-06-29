unit usedbeforeassignmentcapture;
interface
implementation
function Outer: Integer;
var x: Integer;
  procedure Inner;
  begin
    x := 1;
  end;
begin
  Inner;
  Result := x;
end;
end.
