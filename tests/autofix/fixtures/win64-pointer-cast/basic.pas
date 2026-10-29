unit basic;

interface

implementation

procedure Run(P: Pointer);
begin
  if Integer(P) = 0 then Exit;
  if Cardinal(P) <> 0 then Exit;
end;

end.
