unit UnknownCols;

{ schema-unknown-column: datasets created in code. Every line with a FIRE mark must report, all others stay silent. }

interface

procedure Known(const AName: string);
procedure Joins;
procedure Dynamic(const ATable: string);
procedure Stated;
procedure Runtime;
procedure Macros;
procedure OtherDatabase;

implementation

uses
  FireDAC.Comp.Client, Data.DB, Bde.DBTables, Data.Win.ADODB;

var
  S: string;

procedure Known(const AName: string);
var
  Q: TFDQuery;
begin
  Q := TFDQuery.Create(nil);
  try
    Q.SQL.Text := 'SELECT * FROM ORDERS WHERE ID = 1';
    Q.Open;
    Q.FieldByName('NOTEX').AsString := 'a'; // FIRE schema-unknown-column
    Q.FieldByName('notey').AsString := 'a'; // FIRE schema-unknown-column
    Q.FieldByName('NOTE').AsString := 'a';
    Q.FieldByName('note').AsString := 'a';
    Q.FieldByName('TOTALCALC').AsString := 'a';
    S := Q.FieldByName('RDB$DB_KEY').AsString;
    Q.FieldByName(AName).AsString := 'a';
    if Q.FindField('NOTEX') <> nil then
      Exit;
  finally
    Q.Free;
  end;
end;

procedure Joins;
var
  Q, U, A: TFDQuery;
begin
  Q := TFDQuery.Create(nil);
  Q.SQL.Text := 'SELECT O.ID, C.NAMEX, O.NOTE N2, MISSING, O.NOPE FROM ORDERS O JOIN CUSTOMER C ON C.ID = O.ID'; // FIRE schema-unknown-column
  Q.Open;
  S := Q.FieldByName('NAMEX').AsString;
  S := Q.FieldByName('N2').AsString;
  S := Q.FieldByName('ANYTHING').AsString;
  U := TFDQuery.Create(nil);
  U.SQL.Text := 'SELECT * FROM NOSUCHTABLE';
  U.Open;
  S := U.FieldByName('NOTEX').AsString;
  U.Close;
  A := TFDQuery.Create(nil);
  A.SQL.Text := 'SELECT QTY * 2 AS DOUBLED, COUNT(*) AS CNT, CURRENT_CONNECTION, RDB$DB_KEY FROM ORDERS';
  A.Open;
  S := A.FieldByName('DOUBLED').AsString;
  S := A.FieldByName('CNT').AsString;
end;

procedure Dynamic(const ATable: string);
var
  Q, P, R: TFDQuery;
begin
  Q := TFDQuery.Create(nil);
  Q.SQL.Text := 'SELECT * FROM ' + ATable;
  Q.Open;
  S := Q.FieldByName('NOTEX').AsString;
  P := TFDQuery.Create(nil);
  P.SQL.Text := 'SELECT * FROM ORDERS';
  P.Open;
  S := P.FieldByName('NOTEZ').AsString; // FIRE schema-unknown-column
  P.Close;
  R := TFDQuery.Create(nil);
  R.SQL.Text := 'SELECT * FROM ORDERS';
  R.Open;
  S := R.FieldByName('NOTEZ').AsString;
  R.SQL.Text := 'SELECT * FROM NOSUCHTABLE';
  R.Open;
  S := R.FieldByName('NOTEZ').AsString;
  Q.SQL.Text := 'SELECT * FROM UNREAD';
  Q.Open;
end;

procedure Stated;
var
  Q, I: TFDQuery;
begin
  Q := TFDQuery.Create(nil);
  Q.SQL.Text := 'SELECT ID, BADCOL FROM ORDERS'; // FIRE schema-unknown-column
  Q.Open;
  S := Q.FieldByName('BADCOL').AsString;
  I := TFDQuery.Create(nil);
  I.SQL.Text := 'INSERT INTO ORDERS (ID, QTY, CODE, BADINS) VALUES (1, 2, ''x'', 3)'; // FIRE schema-unknown-column
  I.ExecSQL;
  Q.ExecSQL('INSERT INTO UNREAD (NOTEX) VALUES (1)');
end;

procedure Runtime;
var
  Q: TFDQuery;
  F: TStringField;
begin
  Q := TFDQuery.Create(nil);
  Q.SQL.Text := 'SELECT * FROM ORDERS';
  F := TStringField.Create(nil);
  F.FieldName := 'MADE';
  Q.Open;
  S := Q.FieldByName('MADE').AsString;
end;

procedure Macros;
var
  Q, M, B: TFDQuery;
begin
  Q := TFDQuery.Create(nil);
  Q.SQL.Text := 'SELECT CUSTNAME FROM ORDERS &JOINS';
  Q.SQL.Text := 'SELECT CUSTNAME FROM ORDERS !JOINS';
  Q.SQL.Text := 'SELECT CUSTNAME FROM ORDERS O &JOINS WHERE O.ID = 1';
  Q.SQL.Text := 'SELECT FIRST &N NAME FROM ORDERS';
  Q.SQL.Text := 'SELECT FIRST !N NAME FROM ORDERS';
  Q.SQL.Text := 'SELECT NOT ACTIVE FROM ORDERS';
  Q.SQL.Text := 'SELECT BADM FROM ORDERS WHERE &COND'; // FIRE schema-unknown-column
  Q.SQL.Text := 'SELECT BADM FROM ORDERS WHERE QTY != 1'; // FIRE schema-unknown-column
  Q.SQL.Text := 'SELECT NOTE, BADM FROM ORDERS ORDER BY !ORD'; // FIRE schema-unknown-column
  Q.Open;
  M := TFDQuery.Create(nil);
  M.SQL.Text := 'SELECT * FROM ORDERS &JOINS';
  M.Open;
  S := M.FieldByName('CUSTNAME').AsString;
  B := TFDQuery.Create(nil);
  B.SQL.Text := 'SELECT FIRST &N * FROM ORDERS';
  B.Open;
  S := B.FieldByName('CUSTNAME').AsString;
end;

procedure OtherDatabase;
var
  Q: TQuery;
  A: TADOQuery;
begin
  Q := TQuery.Create(nil);
  Q.SQL.Text := 'SELECT * FROM ORDERS';
  Q.Open;
  S := Q.FieldByName('PARADOXONLY').AsString;
  A := TADOQuery.Create(nil);
  A.SQL.Text := 'INSERT INTO ORDERS (NOTE, ACCESSONLY) VALUES (1, 2)';
  A.ExecSQL;
end;

end.