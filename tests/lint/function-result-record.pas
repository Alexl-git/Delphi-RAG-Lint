unit functionresultrecord;
interface
type
  TPair = record A, B: Integer; end;
implementation
function MakePair: TPair;
begin
  Result.A := 1;
  Result.B := 2;
end;
end.
