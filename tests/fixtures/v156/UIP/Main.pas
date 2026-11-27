unit Main;

interface

uses
  Data.DB;

type
  TForm1 = class
    qCust: TDataSet;
    procedure Run;
  end;

implementation

procedure TForm1.Run;
begin
  qCust.FieldByName('CUSTNAME').AsString := 'x';
end;

end.
