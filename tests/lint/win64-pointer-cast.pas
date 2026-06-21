unit W64;

interface

implementation

procedure P(Ptr: Pointer; I: Integer);
var
  N: Integer;
begin
  N := Integer(Ptr);
  N := Integer(I);
end;

end.
