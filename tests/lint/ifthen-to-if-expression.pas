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

procedure Chain(A, B: Boolean; var X: Integer);
begin
  if A then
    X := 1
  else if B then
    X := 2
  else
    X := 3;
end;

procedure NestedInBranch(A, B: Boolean; var X, Y: Integer);
begin
  if A then
  begin
    if B then
      Y := 1
    else
      Y := 2;
  end
  else
    X := 3;
end;

end.