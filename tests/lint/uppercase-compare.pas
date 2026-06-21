unit UCmp;

interface

implementation

procedure P(S: string);
begin
  if UpperCase(S) = 'ABC' then
    WriteLn('a');
  if S = 'ABC' then
    WriteLn('b');
end;

end.
