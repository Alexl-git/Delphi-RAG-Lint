unit unitb;

interface

implementation

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
