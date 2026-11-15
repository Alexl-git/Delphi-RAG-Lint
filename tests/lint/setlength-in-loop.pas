unit SetLengthInLoop;

interface

implementation

procedure P(const L: array of string);
var
  I: Integer;
  A: TArray<string>;
begin
  for I := 0 to High(L) do
  begin
    SetLength(A, Length(A) + 1);
    A[High(A)] := L[I];
  end;
  I := 0;
  while I < 3 do
  begin
    SetLength(A, Length(A) + 1);
    Inc(I);
  end;
  SetLength(A, Length(A) + 1);
  for I := 0 to 2 do
    SetLength(A, 10);
  for I := 0 to 2 do
    SetLength(A, Length(L) + 1);
end;

end.
