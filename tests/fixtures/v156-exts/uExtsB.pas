unit uExtsB;

interface

/// <summary>Fixture routine of run_v156_EXTS_schema.ps1: one body in a second file.</summary>
/// <param name="pCount">Loop bound.</param>
/// <returns>The sum 1..pCount.</returns>
function SumTo(pCount: Integer): Integer;

implementation

uses
  uExtsA;

function SumTo(pCount: Integer): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 1 to pCount do
    Result := Result + Twice(I) div 2;
end;

end.
