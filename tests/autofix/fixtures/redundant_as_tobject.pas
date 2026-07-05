unit redundant_as_tobject;

interface

uses
  System.Classes;

implementation

procedure Demo(Sender: TObject);
var
  Obj: TObject;
begin
  Obj := Sender as TObject;
end;

end.
