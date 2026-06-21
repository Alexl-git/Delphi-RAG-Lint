unit NilComparison;

interface

implementation

procedure P;
var
  X: TObject;
begin
  if X = nil then
    WriteLn('a');
  if X <> nil then
    WriteLn('b');
end;

end.
