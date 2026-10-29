unit basic;

interface

implementation

function F(A, B: Integer): Boolean;
begin
  Result := A > B;
end;

function G(A, B: Integer): Boolean;
begin
  Result := not (A > B);
end;

end.
