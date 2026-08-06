unit UCmp;

interface

implementation

procedure P(S: string);
begin
  if UpperCase(S) = 'ABC' then
    WriteLn('a');
  if S = 'ABC' then
    WriteLn('b');
  if UpperCase(S) = 'abc' then
    WriteLn('c');
  if LowerCase(S) = 'ABC' then
    WriteLn('d');
  if UpperCase(S) = '+' then
    WriteLn('e');
  if LowerCase(S) = 'abc' then
    WriteLn('f');
end;

end.
