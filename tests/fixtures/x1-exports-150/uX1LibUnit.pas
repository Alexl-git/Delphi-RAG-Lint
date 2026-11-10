unit uX1LibUnit;

interface

function X1Twice(A: Integer): Integer; stdcall;
function X1Unused(A: Integer): Integer;

implementation

function X1Twice(A: Integer): Integer;
begin
  Result:= A * 2;
end;

function X1Unused(A: Integer): Integer;
begin
  Result:= A * 3;
end;

end.