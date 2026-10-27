unit basic;

interface

/// <summary>Adds.</summary>
/// <param name="A">First.</param>
/// <param name="Gone">Removed
/// across two lines.</param>
/// <returns>The sum.</returns>
function Add(A: Integer): Integer;

implementation

function Add(A: Integer): Integer;
begin
  Result := A;
end;

end.
