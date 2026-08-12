unit fieldbynameloop;

interface

implementation

uses
  Data.DB;

procedure ReadRows(AQuery: TDataSet; out ATotal: Integer);
var
  Sum: Integer;
begin
  Sum := 0;
  while not AQuery.Eof do
  begin
    Sum := Sum + AQuery.FieldByName('amount').AsInteger;
    Sum := Sum + AQuery.FieldByName('tax').AsInteger;
    Sum := Sum + AQuery.FieldByName('fee').AsInteger;
    AQuery.Next;
  end;
  ATotal := Sum;
end;

end.
