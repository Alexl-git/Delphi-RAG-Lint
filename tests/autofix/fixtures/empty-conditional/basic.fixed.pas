unit basic;

interface

implementation

procedure P(X: Integer; Flag: Boolean);
begin
  if not (X > 0) then
    WriteLn('p');
  if not Flag then
    WriteLn('q');
  if not (X > 1) then
  begin
    WriteLn('r');
    WriteLn('s');
  end;
end;

end.
