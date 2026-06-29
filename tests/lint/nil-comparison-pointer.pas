unit NilComparisonPointer;

interface

implementation

procedure P;
var
  Ptr: PByte;
begin
  { Comparing a pointer to nil might be acceptable since Assigned()
    is idiomatic for objects but pointers often use direct nil checks. }
  if Ptr = nil then
    WriteLn('null pointer');
  if Ptr <> nil then
    WriteLn('valid pointer');
end;

end.
