unit IllOrders;

interface

uses
  IllCustomers;

type
  TIllOrder = class
  public
    Buyer: TIllCustomer;
    Total: Currency;
  end;

implementation

end.
