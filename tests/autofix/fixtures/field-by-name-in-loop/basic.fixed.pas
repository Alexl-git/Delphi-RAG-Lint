unit basic;

interface

uses
  Data.DB;

procedure ReadRows(AQuery: TDataSet; out ATotal: Integer);

implementation

procedure ReadRows(AQuery: TDataSet; out ATotal: Integer);
var
  Sum: Integer;
begin
  Sum := 0;
  var LAmountField := AQuery.FieldByName('amount');
  var LTaxField := AQuery.FieldByName('tax');
  while not AQuery.Eof do
  begin
    Sum := Sum + LAmountField.AsInteger;
    Sum := Sum + LTaxField.AsInteger + LAmountField.AsInteger;
    AQuery.Next;
  end;
  ATotal := Sum;
end;

end.
