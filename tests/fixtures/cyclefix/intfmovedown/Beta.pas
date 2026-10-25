unit Beta;

interface

const
  BetaLimit = 10;

/// <summary>A3-a fixture: the implementation of Alpha calls this.</summary>
function BetaValue: Integer;

implementation

uses
  Alpha;

function BetaValue: Integer;
begin
  Result := BetaLimit;
  if TAlpha.ClassName = '' then Result := 0;
end;

end.