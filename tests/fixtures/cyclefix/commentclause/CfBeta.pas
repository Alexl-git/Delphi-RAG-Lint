unit CfBeta;

// E18 T3a fixture: half of a two-unit implementation-only cycle.

interface

const
  /// <summary>The limit CfAlpha reads; the planner moves it to a leaf unit.</summary>
  CBetaLimit = 10;

/// <summary>Twice the limit plus CfAlpha's total.</summary>
function BetaTwice: Integer;

implementation

uses
  CfAlpha;

function BetaTwice: Integer;
begin
  Result:= AlphaTotal + CBetaLimit;
end;

end.