unit LoopOffByOne;

interface

implementation

procedure P(const A: array of Integer; L: TStringList);
var
  I: Integer;
begin
  for I := 0 to High(A) + 1 do
    Use(A[I]);
  for I := 0 to L.Count + 1 do
    Use(I);
  for I := Low(A) to Length(A) do
    Use(A[I]);
  for I := L.Count downto 0 do
    Use(I);
  for I := Length(A) downto 0 do
    Use(I);
  for I := 0 to High(A) do
    Use(A[I]);
  for I := 0 to L.Count - 1 do
    Use(I);
  for I := L.Count - 1 downto 0 do
    Use(I);
  for I := Low(A) to High(A) do
    Use(A[I]);
end;

procedure Q(const S: string);
var
  I: Integer;
begin
  for I := Length(S) downto 1 do
    Use(I);
end;

end.
