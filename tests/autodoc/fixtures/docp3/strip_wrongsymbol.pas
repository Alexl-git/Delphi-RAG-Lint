unit strip_wrongsymbol;

{ AutoDocument Phase 3 Task 3j (register S1) fixture. Four window shapes for
  TDocStripper.StripSymbolRegion's ADeclLine gap arithmetic. Every /// block
  below is engine-owned BY CONSTRUCTION -- the marker is baked in by hand, the
  same way strip_static.pas does it -- so no `document --apply` run is needed
  and each block's strippability does not depend on what the miner happens to
  find for these trivial routines.

  SHAPE 1 (Alpha / Beta) -- the defect. Alpha is documented; Beta is
  UNdocumented and sits on the very NEXT line. Beta's tolerated window is
  [BetaLine-2, BetaLine-1] and Alpha's block ends at BetaLine-2, so the
  intervening line is Alpha's own DECLARATION rather than a blank.

  SHAPE 2 (Gamma) -- the legitimate gap the window exists for: exactly ONE
  BLANK line between the block and the declaration.

  SHAPE 3 (Epsilon) -- a TWO-blank-line gap, already outside the window and
  required to stay outside.

  SHAPE 4 (Zeta) -- one intervening line that is neither blank NOR a
  declaration (an ordinary comment). The apply path tolerates this on purpose,
  so the strip path must too, or an engine block could be written and never
  removed. This is the shape that distinguishes "the gap is blank" from "no
  other declaration is in the gap" -- see the runner's SCENARIO E and the
  apply/strip agreement table in SCENARIO F. }

interface

/// <summary><!-- drag-lint:auto -->Engine summary for Alpha.</summary>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// Complexity: 1
/// <!-- drag-lint:auto END -->
/// </remarks>
function Alpha(AValue: Integer): Integer;
function Beta(AValue: Integer): Integer;

/// <summary><!-- drag-lint:auto -->Engine summary for Gamma.</summary>

function Gamma(AValue: Integer): Integer;

/// <summary><!-- drag-lint:auto -->Engine summary for Epsilon.</summary>


function Epsilon(AValue: Integer): Integer;

/// <summary><!-- drag-lint:auto -->Engine summary for Zeta.</summary>
// an ordinary comment line -- not blank, and not a declaration
function Zeta(AValue: Integer): Integer;

implementation

function Alpha(AValue: Integer): Integer;
begin
  Result := AValue + 1;
end;

function Beta(AValue: Integer): Integer;
begin
  Result := AValue + 2;
end;

function Gamma(AValue: Integer): Integer;
begin
  Result := AValue + 3;
end;

function Epsilon(AValue: Integer): Integer;
begin
  Result := AValue + 4;
end;

function Zeta(AValue: Integer): Integer;
begin
  Result := AValue + 5;
end;

end.
