unit basic;

interface

implementation

const
  Mask = $ABCD;
  Plain = $ABCD;

procedure Run;
var
  X: Integer;
begin
  X:= $12AB + $FF;
end;

end.
