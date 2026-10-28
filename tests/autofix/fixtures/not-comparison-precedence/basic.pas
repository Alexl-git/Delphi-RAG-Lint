unit basic;

interface

implementation

function P(A, B: Integer): Boolean;
begin
  Result := not A = B;
  Result := not A <> B;
end;

end.
