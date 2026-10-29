unit basic;

interface

implementation

const
  Mask = $AbCd;
  Plain = $ABCD;

procedure Run;
var
  X: Integer;
begin
  X:= $12aB + $FF;
end;

end.
