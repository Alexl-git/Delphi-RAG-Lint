unit basic;

interface

implementation

function P(A, B: Integer; C: Boolean): Boolean;
begin
  Result := (A <> B);
  Result := C and (A = B);
end;

end.
