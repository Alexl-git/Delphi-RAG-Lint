unit PosForContains;

interface

implementation

procedure P(const S, T: string);
begin
  if Pos(T, S) > 0 then
    WriteLn('a');
  if Pos(T, S) <> 0 then
    WriteLn('b');
  if Pos(T, S) = 0 then
    WriteLn('c');
  if Pos(T, S) = 1 then
    WriteLn('d');
  if Pos(T, S) > 1 then
    WriteLn('e');
  if Pos(T, S) = 2 then
    WriteLn('f');
  if Length(S) > 0 then
    WriteLn('g');
  if S.Contains(T) then
    WriteLn('h');
  if Pos(T, S, 2) > 0 then
    WriteLn('i');
end;

end.
