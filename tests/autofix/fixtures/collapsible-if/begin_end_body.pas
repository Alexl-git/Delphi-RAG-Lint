unit begin_end_body;

interface

implementation

procedure P(A, B: Boolean; var N: Integer);
begin
  if A then
  if B then
    begin
      N := 1;
      Inc(N);
    end;
  N := 0;
end;

end.
