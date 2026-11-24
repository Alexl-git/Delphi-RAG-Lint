unit OtherUnit;

{ Takes datasets of DataMod over from outside: their facts are not certain any more. }

interface

procedure Change;

implementation

uses
  DataMod;

procedure Change;
begin
  dmMain.qryLive.SQL.Text := 'SELECT 1 NOTE, 2 LIVEX FROM CUSTOMER';
  dmMain.tblLive.TableName := 'CUSTOMER';
end;

end.