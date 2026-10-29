unit basic;

interface

implementation

procedure P;
var
  Obj: TObject;
begin
  Obj := TObject.Create;
  Obj.Free;
end;

end.
