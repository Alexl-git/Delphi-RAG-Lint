unit SeparateQueryFromModifier;

interface

type
  TCounter = class
  private
    FCount: Integer;
  public
    function BumpAndGet: Integer;
    function Peek: Integer;
    procedure Reset;
  end;

implementation

{ FIRES: a value-returning function that ALSO mutates a field (command-query
  separation violation). Fire at the function header. }
function TCounter.BumpAndGet: Integer;
begin
  FCount := FCount + 1;
  Result := FCount;
end;

{ NOT: a pure query -- returns a value, no state mutation. }
function TCounter.Peek: Integer;
begin
  Result := FCount;
end;

{ NOT: a procedure (no Result) that mutates -- only value-returning FUNCTIONS
  are the CQS target. }
procedure TCounter.Reset;
begin
  FCount := 0;
end;

end.
