unit basic;

interface

implementation

procedure P(Sender: TObject; var Obj: TObject);
begin
  Obj := Sender as TObject;
end;

end.
