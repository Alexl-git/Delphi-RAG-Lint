unit strip_static;

interface

/// <summary>Hand summary that survives.</summary>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// Some facts line here.
/// <!-- drag-lint:auto END -->
/// </remarks>
function FenceOnly: Integer;

/// <summary>Hand summary that survives too.</summary>
/// <remarks>
/// Hand prose that survives.
/// <!-- drag-lint:auto BEGIN -->
/// Some other facts line.
/// <!-- drag-lint:auto END -->
/// </remarks>
function FenceWithProse: Integer;

/// <summary>Hand summary.</summary>
/// <param name="AValue">Hand desc.</param> <!-- drag-lint:auto param -->
function LegacyParam(AValue: Integer): Integer;

/// <summary>Hand summary for multi-line returns.</summary>
/// <returns><!-- drag-lint:auto -->Observed: a mined case that
/// spans two physical lines.</returns>
function MultiLineReturns: Integer;

/// <summary>Hand summary only, untouched.</summary>
/// <remarks>
/// </remarks>
function UntouchedEmptyRemarks: Integer;

/// <summary>Hand summary only, untouched too.</summary>
/// <remarks>
///
/// </remarks>
function UntouchedBareLineRemarks: Integer;

/// <summary><!-- drag-lint:auto --></summary>
/// <param name="AValue"><!-- drag-lint:auto --></param>

function GapDoc(AValue: Integer): Integer;

implementation

function FenceOnly: Integer;
begin
  Result := 1;
end;

function FenceWithProse: Integer;
begin
  Result := 2;
end;

function LegacyParam(AValue: Integer): Integer;
begin
  Result := AValue;
end;

function MultiLineReturns: Integer;
begin
  Result := 3;
end;

function UntouchedEmptyRemarks: Integer;
begin
  Result := 4;
end;

function UntouchedBareLineRemarks: Integer;
begin
  Result := 5;
end;

function GapDoc(AValue: Integer): Integer;
begin
  Result := AValue + 1;
end;

end.
