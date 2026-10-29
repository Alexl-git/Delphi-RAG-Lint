unit renamed;

interface

/// <summary>Adds. OldB was renamed to NewB: its hand prose must survive (doc-drift ADP3 T3:
/// a rename is report-only), so the fixer DECLINES while a signature param has no tag.</summary>
/// <param name="A">First.</param>
/// <param name="OldB">Hand prose for the parameter that was since renamed to NewB.</param>
/// <returns>The sum.</returns>
function Add(A: Integer; const NewB: Integer = 0): Integer;

/// <summary>Negates. Control: every signature param is tagged, so the stale tag goes.</summary>
/// <param name="X">The value.</param>
function Neg(X: Integer): Integer;

implementation

function Add(A: Integer; const NewB: Integer): Integer;
begin
  Result := A + NewB;
end;

function Neg(X: Integer): Integer;
begin
  Result := -X;
end;

end.