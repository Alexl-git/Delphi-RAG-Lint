unit BoolResultDirect;

interface

function IsPositive(N: Integer): Boolean;
function IsNegative(N: Integer): Boolean;
function IsZero(N: Integer): Boolean;

implementation

function IsPositive(N: Integer): Boolean;
begin
  if N > 0 then
    Result := True
  else
    Result := False;
end;

function IsNegative(N: Integer): Boolean;
begin
  if N < 0 then
    Result := False
  else
    Result := True;
end;

function IsZero(N: Integer): Boolean;
begin
  Result := N = 0;
end;

end.
