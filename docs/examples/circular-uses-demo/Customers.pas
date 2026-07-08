unit Customers;

interface

uses
  Orders;   { <-- interface-section use of Orders: half of the cycle }

type
  /// <summary>A customer, which holds a list of the orders it has placed.</summary>
  TCustomer = class
  private
    FName  : string;
    FOrders: TArray<TOrder>;   { references TOrder from Orders -> forces the uses }
  public
    constructor Create(const AName: string);
    procedure AddOrder(const AOrder: TOrder);
    function OrderCount: Integer;
    property Name: string read FName;
  end;

implementation

constructor TCustomer.Create(const AName: string);
begin
  inherited Create;
  FName := AName;
  SetLength(FOrders, 0);
end;

procedure TCustomer.AddOrder(const AOrder: TOrder);
begin
  SetLength(FOrders, Length(FOrders) + 1);
  FOrders[High(FOrders)] := AOrder;
end;

function TCustomer.OrderCount: Integer;
begin
  Result := Length(FOrders);
end;

end.
