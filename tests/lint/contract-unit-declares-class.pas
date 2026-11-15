unit Shop.Contracts;

interface

type
  IOrderService = interface
    ['{11111111-2222-3333-4444-555555555555}']
    procedure Place;
  end;

  TOrderDto = record
    Id: Integer;
  end;

  EOrderError = class(Exception);

  TOrderServiceImpl = class(TInterfacedObject, IOrderService)
    procedure Place;
  end;

  TOrderClass = class of TOrderServiceImpl;

implementation

procedure TOrderServiceImpl.Place;
begin
end;

end.
