unit IllCustomers;

interface

uses
  IllOrders;

type
  TIllCustomer = class
  public
    Name: string;
    LastOrder: TIllOrder;
  end;

implementation

end.
