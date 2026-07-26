unit emptytags;

interface

function NoDocs(AValue: Integer): Integer;

/// <summary></summary>
/// <param name="AValue"></param>
function HumanBlanks(AValue: Integer): Integer;

implementation

function NoDocs(AValue: Integer): Integer;
begin
  Result := AValue;
end;

function HumanBlanks(AValue: Integer): Integer;
begin
  Result := AValue;
  NoDocs(AValue);
end;

end.
