unit upure;

interface

function Twice(A: Integer): Integer;
procedure Run;

implementation

function Twice(A: Integer): Integer;
begin
  Result:= A * 2;
end;

procedure Run;
var
  X: Integer;
begin
  X:= Twice(4);
  if X > 0 then Exit;
end;

end.