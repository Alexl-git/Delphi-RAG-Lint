unit Orders;

interface

type
  /// <summary>An order. Its Describe method needs a customer's details, so the
  /// implementation section reaches back into Customers -- closing a dependency
  /// cycle (Customers -> Orders in the interface, Orders -> Customers in the
  /// implementation).</summary>
  TOrder = class
  private
    FId         : Integer;
    FCustomerRef: TObject;   { the placing customer, held loosely to avoid an
                               interface-section dependency on Customers }
  public
    constructor Create(AId: Integer; const ACustomerRef: TObject);
    function Describe: string;
    property Id: Integer read FId;
  end;

implementation

uses
  System.SysUtils,
  Customers;   { <-- implementation-section use of Customers: closes the cycle,
                 but is legal Delphi (the compiler only forbids a mutual
                 INTERFACE-section cycle). This is exactly the kind of edge
                 `drag-lint cycles` finds and helps you keep or break. }

constructor TOrder.Create(AId: Integer; const ACustomerRef: TObject);
begin
  inherited Create;
  FId          := AId;
  FCustomerRef := ACustomerRef;
end;

function TOrder.Describe: string;
begin
  { reaches back into Customers to read the customer's name }
  if FCustomerRef is TCustomer then
    Result := Format('Order %d for %s', [FId, TCustomer(FCustomerRef).Name])
  else
    Result := Format('Order %d (no customer)', [FId]);
end;

end.
