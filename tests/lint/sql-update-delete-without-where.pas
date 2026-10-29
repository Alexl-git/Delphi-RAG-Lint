unit SqlUpdateDeleteWithoutWhere;

interface

implementation

uses
  FireDAC.Comp.Client;

procedure Bad(Q: TFDQuery; C: TFDConnection);
begin
  Q.SQL.Text := 'DELETE FROM CUSTOMER';
  Q.SQL.Text := 'update orders set status = 1';
  Q.ExecSQL('DELETE FROM CUSTOMER');
  C.ExecSQL('UPDATE T SET A = 1');
  C.ExecuteDirect('delete from t');
  Q.Command.CommandText := 'UPDATE T SET A = 1';
end;

procedure Good(Q: TFDQuery; C: TFDConnection; const ATable: string);
begin
  Q.SQL.Text := 'DELETE FROM CUSTOMER WHERE ID = :ID';
  Q.SQL.Text := 'SELECT * FROM CUSTOMER';
  Q.SQL.Text := 'TRUNCATE TABLE T';
  Q.SQL.Text := 'DELETE FROM ' + ATable;
  Q.SQL.Clear;
  Q.SQL.Add('DELETE FROM CUSTOMER');
  Q.SQL.Add('WHERE ID = 1');
  C.ExecSQL('UPDATE T SET A = 1 where B = 2');
  C.ExecSQL('INSERT INTO T VALUES (1)');
end;

end.
