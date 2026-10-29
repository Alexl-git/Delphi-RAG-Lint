unit basic;

interface

implementation

function P(A, B: Integer; C: Boolean): Boolean;
begin
  Result := not (A = B);
  Result := C and not (A <> B);
end;

end.
