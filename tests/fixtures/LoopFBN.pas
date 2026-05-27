unit LoopFBN;

interface

uses
  Data.DB;

type
  TBad = class
    procedure Scan(Q: TDataSet);
  end;

implementation

procedure TBad.Scan(Q: TDataSet);
var
  Total: Integer;
  i: Integer;
begin
  Total := 0;
  Q.First;
  while not Q.Eof do
  begin
    Total := Total + Q.FieldByName('AMOUNT').AsInteger;
    Q.Next;
  end;

  for i := 1 to 10 do
    WriteLn(Q.FieldByName('NAME').AsString);

  Q.First;
  repeat
    WriteLn(Q.FieldByName('CODE').AsString);
    Q.Next;
  until Q.Eof;

  Total := Q.FieldByName('FINAL_TOTAL').AsInteger;
end;

end.
