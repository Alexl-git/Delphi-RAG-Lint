unit FreeChk;

interface

uses System.SysUtils;

type
  TFoo = class
    FDoc: TObject;
    procedure Load;
  end;

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

procedure TFoo.Load;
begin
  FDoc := TObject.Create;
  FDoc.ToString;
  FDoc.Free;
end;

function MakeIt: TObject;
begin
  Result := TObject.Create;
  if Result <> nil then
    Result.Free;
end;

procedure WithExcept;
var
  Z: TObject;
begin
  Z := TObject.Create;
  try
    Z.ToString;
  except
    Z.Free;
    raise;
  end;
end;

end.
