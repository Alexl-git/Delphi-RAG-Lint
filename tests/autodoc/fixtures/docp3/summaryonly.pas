unit summaryonly;

interface

/// <summary></summary>
function Echo3(AValue: Integer): Integer;

function UseEcho3: Integer;

implementation

function Echo3(AValue: Integer): Integer;
begin
  Result := AValue;
end;

function UseEcho3: Integer;
begin
  Result := Echo3(5);
end;

end.
