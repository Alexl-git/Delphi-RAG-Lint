unit basic;

interface

implementation

function F(A, B: Integer): Boolean;
begin
  if A > B then Result := True else Result := False;
end;

function G(A, B: Integer): Boolean;
begin
  if A > B then Result := False else Result := True;
end;

end.
