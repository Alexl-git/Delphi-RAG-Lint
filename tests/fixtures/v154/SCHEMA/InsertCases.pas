unit InsertCases;

{ schema-required-not-set: INSERT statements that leave out a column the table requires. }

interface

procedure Inserts(const AColumns: string);

implementation

uses
  FireDAC.Comp.Client;

const
  SQL_SHORT = 'INSERT INTO ORDERS (NOTE, CODE) VALUES (:NOTE, :CODE)';

procedure Inserts(const AColumns: string);
var
  Q, C, D, E, F, G, H, J: TFDQuery;
begin
  Q := TFDQuery.Create(nil);
  Q.SQL.Text := 'INSERT INTO ORDERS (NOTE) VALUES (:NOTE)'; // FIRE schema-required-not-set
  Q.ExecSQL;
  C := TFDQuery.Create(nil);
  C.SQL.Text := SQL_SHORT; // FIRE schema-required-not-set
  C.ExecSQL;
  D := TFDQuery.Create(nil);
  D.SQL.Text := 'INSERT INTO ORDERS (QTY, CODE) VALUES (:QTY, :CODE)';
  D.ExecSQL;
  E := TFDQuery.Create(nil);
  E.SQL.Text := 'INSERT INTO ORDERS VALUES (1, 2, 3)';
  E.ExecSQL;
  F := TFDQuery.Create(nil);
  F.SQL.Text := 'INSERT INTO CUSTOMER (NAME) VALUES (:NAME)';
  F.ExecSQL;
  G := TFDQuery.Create(nil);
  G.SQL.Text := 'INSERT INTO ORDERS (' + AColumns + ') VALUES (1)';
  G.ExecSQL;
  H := TFDQuery.Create(nil);
  H.SQL.Text := 'UPDATE ORDERS SET NOTE = 1';
  H.ExecSQL;
  H.ExecSQL('INSERT INTO UNREAD (A) VALUES (1)');
  J := TFDQuery.Create(nil);
  J.SQL.Text := 'UPDATE OR INSERT INTO ORDERS (NOTE) VALUES (:NOTE) MATCHING (NOTE)'; // FIRE schema-required-not-set
  J.ExecSQL;
end;

end.