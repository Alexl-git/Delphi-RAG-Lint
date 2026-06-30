unit pipeline_fixture;
interface
function Compute: Integer;
implementation
function Compute: Integer;
var n: Integer;
begin
  Result:= n + 1;   // used-before-assignment: n read before any write
end;
end.
