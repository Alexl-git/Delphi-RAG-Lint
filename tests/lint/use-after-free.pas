unit UAF;

interface

uses System.SysUtils;

implementation

procedure Bad;
var
  X: TObject;
begin
  X := TObject.Create;
  X.Free;
  X.ToString;
end;

procedure Good;
var
  Y: TObject;
begin
  Y := TObject.Create;
  Y.ToString;
  FreeAndNil(Y);
end;

end.
