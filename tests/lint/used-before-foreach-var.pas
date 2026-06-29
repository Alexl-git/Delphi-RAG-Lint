unit usedbeforeforeachvar;
interface
uses System.Generics.Collections;
implementation
function SumAll(L: TList<Integer>): Integer;
var s: Integer;
begin
  s := 0;
  for var x in L do s := s + x;
  Result := s;
end;
end.
