unit basic;

interface

implementation

procedure P(Obj: TObject);
begin
  if not Assigned(Obj) then Exit;
  if Assigned(Obj) then Obj.Free;
end;

end.
