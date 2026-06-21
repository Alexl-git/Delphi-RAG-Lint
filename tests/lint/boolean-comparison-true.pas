unit BoolCmp;

interface

implementation

procedure P;
var
  B: Boolean;
begin
  if B = True then
    WriteLn('a');
  if B <> False then
    WriteLn('b');
end;

end.
