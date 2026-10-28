unit IfThenToIfExpr;

interface

implementation

procedure Bad(C: Boolean; var X: Integer);
begin
  if C then
    X := 1
  else
    X := 2;
end;

procedure CallForm(C: Boolean; var X: Integer);
begin
  X := IfThen(C, 1, 2);
  X := IfThen(C, Compute, 2);
end;

procedure Good(C: Boolean; var X, Y: Integer);
begin
  X := if C then 1 else 2;
  if C then
    X := 1
  else
    Y := 2;
  if C then
    X := 1;
  if C then
    X := 1
  else
    Exit;
end;

end.
