unit HiLibUnit;

interface

procedure HiLibReadSettings;
procedure HiLibQuiet;

implementation

uses
  System.Win.Registry;

procedure HiLibStep;
var
  Reg: TRegistry;
begin
  Reg:= TRegistry.Create;
  try
    Reg.ReadString('x');
  finally
    Reg.Free;
  end;
end;

procedure HiLibReadSettings;
begin
  HiLibStep;
end;

procedure HiLibQuiet;
begin
end;

end.
