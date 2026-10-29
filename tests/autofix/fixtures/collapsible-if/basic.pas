unit basic;

interface

implementation

procedure P(A, B: Boolean; var N: Integer);
begin
  if A then if B then N := 1;
  if A then
    begin
      if B then N := 2;
    end;
end;

end.
