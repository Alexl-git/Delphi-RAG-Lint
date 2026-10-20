unit IncB;

// E18 T15b fixture incuses: the closing edge IncB -> IncA lives in IncB.Uses.inc.

interface

/// <summary>Calls back into IncA.</summary>
function ValueB: Integer;

implementation

{$I IncB.Uses.inc}

function ValueB: Integer;
begin
  Result:= ValueA + 1;
end;

end.