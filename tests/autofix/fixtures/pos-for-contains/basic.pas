unit basic;

interface

implementation

function P(S, T: string): Boolean;
begin
  Result := Pos(T, S) > 0;
  Result := Pos(T, S) = 0;
  Result := Pos(T, S) <> 0;
end;

end.
