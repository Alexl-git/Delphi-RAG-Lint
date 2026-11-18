unit App.Orders.Api;

interface

type
  IOrders = interface
    ['{4F7A1E0C-2B3D-4C5E-8F90-1A2B3C4D5E6F}']
    function Count: Integer;
  end;

  TOrderList = class
  end;

  EOrderError = class(Exception);

  TOrderClass = class of TOrderList;

implementation

end.