unit IncRefA;

// Plan fixture (lane CYC3, item 2): IncRefA's call to IncRefBWrite sits in an include of its implementation.

interface

/// <summary>Writes through IncRefB.</summary>
procedure IncRefAStart;

/// <summary>A fixed value.</summary>
/// <returns>5.</returns>
function IncRefAValue: Integer;

implementation

uses
  IncRefB;

{$I IncRefCalls.inc}

function IncRefAValue: Integer;
begin
  Result:= 5;
end;

end.
