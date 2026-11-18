unit UDiReg;

{ Self-registering DI unit: listed only by App.dpr, registers itself in the container. }

interface

type
  IGreeter = interface
    ['{3C1B0D2E-6E77-4C55-9C0F-2F0A7C9D1A01}']
    procedure Greet;
  end;

  TGreeter = class(TInterfacedObject, IGreeter)
  public
    procedure Greet;
  end;

implementation

uses
  Spring.Container;

procedure TGreeter.Greet;
begin
end;

initialization
  GlobalContainer.RegisterType<TGreeter>.Implements<IGreeter>;

end.