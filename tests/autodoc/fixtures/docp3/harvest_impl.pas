unit harvest_impl;

interface

function ImplOnly(AValue: Integer): Integer;

// Interface-side prose wins.
function BothSides(AValue: Integer): Integer;

/// <summary>Hand-written and authoritative.</summary>
function HandWins(AValue: Integer): Integer;

function Driver: Integer;

implementation

// Implementation-side prose for ImplOnly.
function ImplOnly(AValue: Integer): Integer;
begin
  Result := AValue;
end;

// Implementation-side prose that must LOSE to the interface side.
function BothSides(AValue: Integer): Integer;
begin
  Result := AValue + 1;
end;

// Implementation-side prose that must lose to the hand-written summary.
function HandWins(AValue: Integer): Integer;
begin
  Result := AValue + 2;
end;

// Calls the other three so each one has a CALLER fact. Without at least one
// fact the engine writes no doc block at all ("nothing to document"), and a
// harvested summary would have nowhere to land -- so every assertion about the
// harvest would be vacuous. The same device is used in harvest_text.pas.
function Driver: Integer;
begin
  Result := ImplOnly(1) + BothSides(2) + HandWins(3);
end;

end.