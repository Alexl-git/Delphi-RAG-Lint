unit UFoo;

interface

type
  IFoo = interface
    ['{5A1B0D2E-6E77-4C55-9C0F-2F0A7C9D1A02}']
    procedure Go;
  end;

  TFoo = class(TInterfacedObject, IFoo)
  public
    procedure Go;
  end;

implementation

procedure TFoo.Go;
begin
end;

end.