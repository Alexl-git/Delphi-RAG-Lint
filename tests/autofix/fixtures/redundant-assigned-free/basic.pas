unit basic;

interface

implementation

procedure P;
var
  Obj: TObject;
begin
  Obj := TObject.Create;
  if Assigned(Obj) then Obj.Free;
end;

end.
