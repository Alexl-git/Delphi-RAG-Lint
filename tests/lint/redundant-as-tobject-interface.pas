unit AsObjNeg;

interface

implementation

type
  IFoo = interface
  end;

procedure P(const AIntf: IFoo);
var
  O: TObject;
begin
  O := AIntf as TObject;
  O := Unknown as TObject;
end;

end.
