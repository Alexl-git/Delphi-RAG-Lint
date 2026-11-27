unit HB;

interface

procedure WorkHB(A: Integer);

implementation

procedure WorkHB(A: Integer);
var
  N: Integer;
begin
  N:= 0;
  if A = 1 then Inc(N);
  if A = 2 then Inc(N);
end;

end.
