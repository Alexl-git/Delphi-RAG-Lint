unit EmptyConditional;

interface

implementation

procedure P;
var
  X: Integer;
begin
  if X > 0 then ;
  if X > 0 then
    WriteLn('a')
  else ;
end;

procedure P3(X: Integer);
begin
  if X > 0 then
  else
    WriteLn('p3');
  if X > 1 then
  begin
  end
  else
    WriteLn('p4');
  if X > 2 then
  begin
  end;
  if X > 3 then
    WriteLn('non-hit: real then branch');
  if X > 4 then
  begin
    WriteLn('non-hit: non-empty block');
  end
  else
    WriteLn('non-hit');
end;

end.
