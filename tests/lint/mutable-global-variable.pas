unit mutableglobalvariable;

interface

var
  G: Integer;

const
  K = 5;

implementation

procedure P;
var
  Local: Integer;
begin
  Local := 0;
  G := Local;
end;

end.
