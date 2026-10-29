unit basic;

interface

implementation

procedure P(C: Boolean);
begin
  if C then WriteLn('same') else WriteLn('same');
  if C then
  begin
    WriteLn('a');
    WriteLn('b');
  end
  else
  begin
    WriteLn('a');
    WriteLn('b');
  end;
end;

end.
