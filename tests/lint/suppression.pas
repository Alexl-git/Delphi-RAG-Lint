unit Suppression;

interface

implementation

procedure P(X: Integer);
var
  Y: Integer;
begin
  Y := X div 0; // drag-lint:ignore division-by-zero-literal
  Y := X div 0; // drag-lint:ignore
  Y := X div 0;
  Y := X mod 0; // drag-lint:ignore some-other-rule
end;

end.
