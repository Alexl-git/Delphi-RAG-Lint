unit IdentityOp;

interface

implementation

procedure P(X: Integer);
var
  R: Integer;
begin
  WriteLn(X + 0);
  WriteLn(X - 0);
  WriteLn(X * 1);
  WriteLn(X div 1);
  WriteLn(X mod 1);
  WriteLn(X shl 0);
  WriteLn(X shr 0);
  WriteLn(X or 0);
  WriteLn(X and 0);
  WriteLn(X + 1);
  WriteLn(X * 2);
  WriteLn(X * 10);
  WriteLn(X + 10);
  WriteLn(X - 100);
  WriteLn(X div 10);
end;

end.
