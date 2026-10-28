unit basic;

interface

implementation

procedure Run(P: Pointer);
begin
  if NativeInt(P) = 0 then Exit;
  if NativeUInt(P) <> 0 then Exit;
end;

end.
