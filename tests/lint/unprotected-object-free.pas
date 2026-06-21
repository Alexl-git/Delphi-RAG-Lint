unit FreeChk;

interface

uses System.SysUtils;

implementation

procedure Bad;
var
  X: TObject;
begin
  X := TObject.Create;
  X.ToString;
  X.Free;
end;

procedure Good;
var
  Y: TObject;
begin
  Y := TObject.Create;
  try
    Y.ToString;
  finally
    Y.Free;
  end;
end;

end.
