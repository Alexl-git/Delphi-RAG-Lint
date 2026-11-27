unit ChbFlow;

interface

procedure Work(pCount: Integer);

implementation

procedure Work(pCount: Integer);
var
  I: Integer;
begin
  if pCount < 0 then
    Exit;
  for I:= 1 to pCount do
    Inc(pCount);
  Writeln(pCount);
end;

end.
