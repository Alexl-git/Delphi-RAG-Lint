unit CfAlpha;

// N-06 T6 fixture: the implementation uses clause lives in CfAlpha.Uses.inc.
// cycles --fix must REFUSE (uses-in-include) rather than edit either file.

interface

/// <summary>Twice CfBeta's limit.</summary>
function AlphaTotal: Integer;

implementation

{$I CfAlpha.Uses.inc}

function AlphaTotal: Integer;
begin
  Result:= CBetaLimit * 2;
end;

end.