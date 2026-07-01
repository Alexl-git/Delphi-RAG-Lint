unit unita;

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

end.
