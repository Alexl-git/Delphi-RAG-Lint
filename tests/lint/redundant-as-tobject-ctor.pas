unit AsObjCtor;

interface

implementation

uses
  System.Classes;

type
  IFoo = interface
  end;

procedure P;
var
  O: TObject;
begin
  O := TStringList.Create as TObject;
  O := TStringList.Create() as TObject;
  O := Factory.Make as TObject;
  O := IFoo(nil) as TObject;
end;

end.
