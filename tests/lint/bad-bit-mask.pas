unit BadBitMask;

interface

implementation

procedure P(X: Integer);
begin
  if (X and $F0) = $0F then X:= 1;
  if (X and $FF) = $0F then X:= 2;
  if (X or $01) = $00 then X:= 3;
  if (X or $0F) = $FF then X:= 4;
  if (X and 255) <> 1 then X:= 5;
  if (X and 8) = 1 then X:= 6;
  if $0F = (X and $F0) then X:= 7;
  if (X and Y) = 1 then X:= 8;
  if (X and %1100) = %0011 then X:= 9;
end;

end.
