unit LZCA;

interface

implementation

procedure P;
var
  B: TBytes;
begin
  SetLength(B, 2);
  if Length(B) > 0 then   // ARRAY operand: length-zero-compare must NOT fire (X='' advice is wrong)
    WriteLn('b');
end;

end.
