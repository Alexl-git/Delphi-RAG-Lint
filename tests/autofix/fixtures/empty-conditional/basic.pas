unit basic;

interface

implementation

procedure P(X: Integer; Flag: Boolean);
begin
  if X > 0 then
  else
    WriteLn('p');
  if Flag then else WriteLn('q');
  if X > 1 then
  else
  begin
    WriteLn('r');
    WriteLn('s');
  end;
end;

end.
