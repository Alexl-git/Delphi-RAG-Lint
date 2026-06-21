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

end.
