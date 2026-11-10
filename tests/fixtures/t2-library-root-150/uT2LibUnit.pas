unit uT2LibUnit;

interface

function T2Twice(A: Integer): Integer; stdcall;

implementation

function T2Twice(A: Integer): Integer;
begin
  Result:= A * 2;
end;

end.