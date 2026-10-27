unit basic;

interface

implementation

procedure Run(C: Boolean);
var
  X: Integer;
begin
  X:= if C then 1 else 2;
  X:= if C then 3 else 4;
end;

end.
