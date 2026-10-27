unit ManualInrange;

interface

implementation

procedure P(X, Y, A, B: Integer);
begin
  if (X >= A) and (X <= B) then
    WriteLn('a');
  if (X <= B) and (X >= A) then
    WriteLn('b');
  if (A <= X) and (X <= B) then
    WriteLn('c');
  if (X <= B) and (A <= X) then
    WriteLn('d');
  if (X > A) and (X < B) then
    WriteLn('e');
  if (X >= A) and (A <= B) then
    WriteLn('f');
  if (X >= A) or (X <= B) then
    WriteLn('g');
  if (X >= A) and (Y <= B) then
    WriteLn('h');
end;

end.
