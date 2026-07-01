unit dupcode;

interface

implementation

procedure AlphaSum(const A: array of Integer; out R: Integer);
var
  i, acc: Integer;
begin
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
  tot := 0;
  for k := 0 to High(B) do
    if B[k] > 0 then
      tot := tot + B[k]
    else
      tot := tot - B[k];
  S := tot;
end;

end.
