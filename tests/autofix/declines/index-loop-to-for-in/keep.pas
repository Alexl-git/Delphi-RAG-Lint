unit keep;
interface
implementation
procedure Bump(var X: Integer);
begin
  Inc(X);
end;
procedure P(var A: TArray<Integer>);
var
  I: Integer;
begin
  for I := 0 to High(A) do
    Bump(A[I]);
end;
procedure Q(const A: TArray<Integer>);
var
  I, LItem: Integer;
begin
  LItem := 0;
  for I := 0 to High(A) do
    Writeln(A[I]);
  Writeln(LItem);
end;
end.
