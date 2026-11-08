unit CfAlpha;

// E18 T3a fixture: the partner entry sits inside a conditional region WITH an ELSE branch
// (lane 148 CY: only a single-branch region goes whole) of the implementation uses clause.
// Removing it cannot be mechanical: the planner must refuse the whole cycle with `directive`.

interface

/// <summary>Twice CfBeta's limit.</summary>
function AlphaTotal: Integer;

implementation

uses
  System.SysUtils
  {$IFDEF MSWINDOWS} , CfBeta {$ELSE} , CfBeta {$ENDIF}; // why: the limit lives there

function AlphaTotal: Integer;
begin
  Result:= CBetaLimit * 2;
end;

end.