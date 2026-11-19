unit begin_end_body;

interface

implementation

procedure P(A, B: Boolean; var N: Integer);
begin
  if (A) and (B) then begin
      N := 1;
      Inc(N);
    end;
  N := 0;
end;

end.
