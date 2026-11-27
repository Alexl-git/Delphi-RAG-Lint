unit HC;

interface

procedure WorkHC(A: Integer);

implementation

procedure WorkHC(A: Integer);
var
  N: Integer;
begin
  N:= 0;
  if A = 1 then Inc(N);
  if A = 2 then Inc(N);
  if A = 3 then Inc(N);
  if A = 4 then Inc(N);
  if A = 5 then Inc(N);
  if A = 6 then Inc(N);
  if A = 7 then Inc(N);
  if A = 8 then Inc(N);
  if A = 9 then Inc(N);
  if A = 10 then Inc(N);
  if A = 11 then Inc(N);
end;

end.
