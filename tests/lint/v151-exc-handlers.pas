unit v151_exc_handlers;

interface

implementation

uses
  System.SysUtils;

procedure Order1;
begin
  try
    DoIt;
  except
    on E: Exception do
      Log(E.Message);
    on E: EConvertError do
      Log('x');
  end;
end;

procedure Order2;
begin
  try
    DoIt;
  except
    on E: EAccessViolation do
      Log('a');
    on E: EDivByZero do
      Log('b');
    on E: Exception do
      Log('c');
  end;
end;

procedure Order3;
begin
  try
    DoIt;
  except
    on E: EExternal do
      Log('a');
    on E: EAccessViolation do
      Log('b');
  end;
end;

procedure Freed1;
begin
  try
    DoIt;
  except
    on E: Exception do
    begin
      Log(E.Message);
      E.Free;
    end;
  end;
end;

procedure Freed2;
begin
  try
    DoIt;
  except
    on E: Exception do
      FreeAndNil(E);
  end;
end;

procedure FreedOk;
var
  L: TObject;
begin
  try
    DoIt;
  except
    on E: Exception do
    begin
      L.Free;
      Log(E.Message);
    end;
  end;
end;

procedure Direct1(X: TObject);
begin
  X.Destroy;
end;

procedure DirectOk(X: TObject);
begin
  X.Free;
end;

end.
