unit DefB;

// E18 T15b fixture incuses: the closing edge DefB -> DefA sits inside an {$IFDEF}.

{$DEFINE DL_CYCLE_EDGE}

interface

/// <summary>Calls back into DefA.</summary>
function ValueDefB: Integer;

implementation

{$IFDEF DL_CYCLE_EDGE}
uses
  DefA;
{$ENDIF}

function ValueDefB: Integer;
begin
  Result:= ValueDefA + 1;
end;

end.