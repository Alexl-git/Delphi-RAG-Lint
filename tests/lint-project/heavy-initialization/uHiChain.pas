unit uHiChain;

interface

function LoadFromRegistry: string;

implementation

uses
  System.Win.Registry;

function LoadFromRegistry: string;
var
  Reg: TRegistry;
begin
  Reg:= TRegistry.Create;
  try
    Result:= Reg.ReadString('x');
  finally
    Reg.Free;
  end;
end;

procedure Boot;
begin
  LoadFromRegistry;
end;

initialization
  Boot; // TRIGGER-CHAIN
end.