unit dupcodeend;

{ v152 FPS: a clone whose first matching token is the closing `end;` of a preceding,
  different statement must be anchored on the first statement of the copied block,
  not on that `end;`. }

interface

implementation

procedure AlphaSum(const A: array of Integer; Flag: Boolean; out R: Integer);
var
  i, acc: Integer;
begin
  if Flag then
  begin
    R := 0
  end;
  acc := 0;
  for i := 0 to High(A) do
    if A[i] > 0 then
      acc := acc + A[i]
    else
      acc := acc - A[i];
  R := acc;
end;

procedure BetaSum(const B: array of Integer; out S: Integer);
var
  k, tot: Integer;
begin
  while S < 0 do
  begin
    Inc(S)
  end;
  tot := 0;
  for k := 0 to High(B) do
    if B[k] > 0 then
      tot := tot + B[k]
    else
      tot := tot - B[k];
  S := tot;
end;

end.