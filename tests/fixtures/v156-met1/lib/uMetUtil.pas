unit uMetUtil;

{ Fixture of tests\autotest\run_v156_MET1.ps1 (1.56 lane MET-1). The runner pins counts
  from this file: edit both together. }

interface

/// <summary>Clamps a value into a range.</summary>
function Clamp(pValue, pLow, pHigh: Integer): Integer;

/// <summary>True for an even value.</summary>
function IsEven(pValue: Integer): Boolean;

implementation

function Clamp(pValue, pLow, pHigh: Integer): Integer;
begin
  // two branches
  if pValue < pLow then
    Result:= pLow
  else if pValue > pHigh then
    Result:= pHigh
  else
    Result:= pValue;
end;

function IsEven(pValue: Integer): Boolean;
begin
  Result:= (pValue mod 2) = 0;
end;

end.
