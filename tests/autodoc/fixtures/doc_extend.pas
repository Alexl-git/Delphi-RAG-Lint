unit doc_extend;

interface

/// <summary>Real prose.</summary>
/// <param name="X">Real param desc.</param>
/// <remarks>
/// First remark line.
/// Second remark line.
/// </remarks>
function Compute(X, Y: Integer): Integer;
function UseCompute: Integer;

implementation

function Compute(X, Y: Integer): Integer;
begin
  Result := X + Y;
end;

function UseCompute: Integer;
begin
  Result := Compute(1, 2);
end;

end.
