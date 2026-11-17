unit Suppression;

interface

implementation

procedure P(X: Integer);
var
  Y: Double;
begin
  Y := X / 0.0; // drag-lint:ignore division-by-zero-literal
  Y := X / 0.0; // drag-lint:ignore
  Y := X / 0.0;
  Y := X / 0.0; // drag-lint:ignore some-other-rule
end;

end.
