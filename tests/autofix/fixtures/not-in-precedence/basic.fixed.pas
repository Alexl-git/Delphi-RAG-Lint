unit basic;

interface

implementation

function P(A: Integer; S: set of Byte): Boolean;
begin
  Result := not (A in S);
end;

end.
