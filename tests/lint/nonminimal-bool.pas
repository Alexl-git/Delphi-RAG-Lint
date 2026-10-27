unit NonminimalBool;

interface

implementation

procedure P(A, B: Integer; S: set of Byte);
begin
  if not (A = B) then
    WriteLn('a');
  if not (A <> B) then
    WriteLn('b');
  if not (A in S) then
    WriteLn('c');
  if not (A < B) then
    WriteLn('d');
  if not (A = B) and (A > 0) then
    WriteLn('e');
  if A <> B then
    WriteLn('f');
  if not Odd(A) then
    WriteLn('g');
  if not ((A > 0) or (B > 0)) then
    WriteLn('h');
end;

end.
