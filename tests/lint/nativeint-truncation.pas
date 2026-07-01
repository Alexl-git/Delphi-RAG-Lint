unit NativeIntTruncation;

interface

implementation

procedure Truncates;
var
  n: NativeInt;
  p: NativeUInt;
  i: Integer;
begin
  n := 0;
  p := 0;
  i := Integer(n);
  i := Cardinal(p);
end;

procedure Fine;
var
  a: Integer;
  b: Integer;
begin
  a := 0;
  b := Integer(a);
end;

end.
