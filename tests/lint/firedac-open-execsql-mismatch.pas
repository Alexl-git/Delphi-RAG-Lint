unit FireDac;

interface

implementation

procedure P(Q: TFDQuery);
begin
  Q.SQL.Text := 'UPDATE t SET x=1';
  Q.Open;
  Q.SQL.Text := 'SELECT * FROM t';
  Q.ExecSQL;
  Q.SQL.Text := 'SELECT * FROM t';
  Q.Open;
end;

end.
