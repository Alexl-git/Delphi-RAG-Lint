unit SizeofPointer;

interface

implementation

procedure Bad;
var
  N: Integer;
begin
  if SizeOf(Pointer) = 4 then
    N := 1;
  if SizeOf(Pointer) = 8 then
    N := 2;
end;

procedure Good;
var
  N: Integer;
begin
  if SizeOf(Pointer) = SizeOf(NativeInt) then
    N := 3;
end;

end.
