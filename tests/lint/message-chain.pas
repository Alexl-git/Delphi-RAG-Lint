unit msgchain;
interface
implementation

procedure Foo;
var
  X: Integer;
  S: string;
begin
  X := Order.Customer.Address.City.Zip.Length;
  S := Order.Customer.Name;
  X := Order.Customer.Address.Zip.Value.Digits.Count;
end;

end.
