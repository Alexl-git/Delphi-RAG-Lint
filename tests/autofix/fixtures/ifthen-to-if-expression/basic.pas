unit basic;

interface

implementation

procedure Run(C: Boolean);
var
  X: Integer;
begin
  if C then X:= 1 else X:= 2;
  if C then
    X:= 3
  else
    X:= 4;
end;

end.
