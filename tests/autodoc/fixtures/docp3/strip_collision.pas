unit strip_collision;

interface

function Combine(A: Integer): Integer; overload;
function Combine(A, B: Integer): Integer; overload;

implementation

function Combine(A: Integer): Integer;
begin
  Result := A;
end;

function Combine(A, B: Integer): Integer;
begin
  Result := A + B;
end;

end.
