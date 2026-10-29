unit AsObjPos;

interface

implementation

procedure P(Sender: TObject);
var
  O: TObject;
begin
  O := Sender as TObject;
end;

end.
