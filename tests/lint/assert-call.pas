unit AssertCall;

interface

implementation

procedure P;
var
  X: Integer;
begin
  Assert(X > 0);
  Assert(X > 0, 'must be positive');
end;

end.
