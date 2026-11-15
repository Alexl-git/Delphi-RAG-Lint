unit FoUnit;

interface

procedure RunAll;

implementation

procedure GetValue(out AValue: Integer);
begin
  AValue:= 42;
end;

{ V:= 0 is overwritten by the out argument before anything reads it }
function UseOut: Integer;
var
  V: Integer;
begin
  V:= 0;
  GetValue(V);
  Result:= V;
end;

procedure RunAll;
begin
  WriteLn(UseOut);
end;

end.
