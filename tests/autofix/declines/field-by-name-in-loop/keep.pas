unit keep;
interface
uses
  Data.DB;
implementation
procedure P(AQuery: TDataSet; const AName: string);
var
  Sum: Integer;
begin
  Sum := 0;
  while not AQuery.Eof do
  begin
    Sum := Sum + AQuery.FieldByName('amount').AsInteger;
    Sum := Sum + AQuery.FieldByName(AName).AsInteger;
    AQuery.Next;
  end;
  AQuery.First;
  while not AQuery.Eof do
  begin
    Sum := Sum + AQuery.FieldByName('amount').AsInteger;
    AQuery.Close;
  end;
  Writeln(Sum);
end;
end.
