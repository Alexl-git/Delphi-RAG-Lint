unit basic;

interface

implementation

procedure P(Obj: TObject);
begin
  if Obj = nil then Exit;
  if Obj <> nil then Obj.Free;
end;

end.
