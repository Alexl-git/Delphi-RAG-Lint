unit doc_stale_param;

interface

/// <summary>Handler summary.</summary>
/// <param name="X">The kept param.</param>
/// <param name="Old">TODO: describe.</param><!-- drag-lint:auto param -->
/// <param name="Gone">Real desc.</param>
function Handle(X: Integer): Integer;
function UseHandle: Integer;

implementation

function Handle(X: Integer): Integer;
begin
  Result := X;
end;

function UseHandle: Integer;
begin
  Result := Handle(7);
end;

end.
