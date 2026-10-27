unit IdentityOp;

interface

implementation

procedure P(X: Integer);
var
  R: Integer;
begin
  R := X + 0;
  R := X - 0;
  R := X * 1;
  R := X div 1;
  R := X mod 1;
  R := X shl 0;
  R := X shr 0;
  R := X or 0;
  R := X and 0;
  R := X + 1;
  R := X * 2;
  R := X * 10;
  R := X + 10;
  R := X - 100;
  R := X div 10;
end;

end.
