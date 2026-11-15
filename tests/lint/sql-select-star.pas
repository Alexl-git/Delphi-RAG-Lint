unit SqlSelectStar;

interface

implementation

uses
  FireDAC.Comp.Client;

procedure Bad(Q: TFDQuery; C: TFDConnection);
begin
  Q.SQL.Text := 'SELECT * FROM CUSTOMER WHERE CITY = :CITY';
  Q.SQL.Text := 'select c.*, o.ID from customer c join orders o on o.cid = c.id';
  Q.SQL.Add('SELECT *');
  Q.SQL.Add('select distinct * from orders');
  Q.Open('SELECT * FROM T');
  C.ExecSQL('select a, * from t');
  Q.Command.CommandText := 'SELECT t.* FROM T t';
end;

procedure Good(Q: TFDQuery; C: TFDConnection; const ATable: string);
begin
  Q.SQL.Text := 'SELECT ID, NAME FROM CUSTOMER';
  Q.SQL.Text := 'SELECT COUNT(*) FROM CUSTOMER';
  Q.SQL.Text := 'SELECT PRICE * QTY AS TOTAL FROM ORDERS';
  Q.SQL.Text := 'SELECT a*b FROM T';
  Q.SQL.Text := 'SELECT * FROM ' + ATable;
  Q.SQL.Add('UPDATE T SET A = 1');
  Q.SQL.Add('/* select * is only a comment word */ DELETE FROM T WHERE X = 1');
  Q.SQL.Text := 'DELETE FROM T WHERE ID IN (SELECT ID FROM U)';
  Q.SQL.Text := 'SELECT MAX(*) FROM T';
end;

end.
