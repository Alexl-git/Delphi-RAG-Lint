unit basic;

interface

procedure P;

implementation

procedure P;
var
  X, Y: Integer;
  Z: string;
begin
  X := 1;
  Y := 2;
  Z := 'a';
  Writeln(Y);
  X := Y + 1;
end;

end.
