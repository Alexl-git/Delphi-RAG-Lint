unit basic;

interface

implementation

uses
  FireDAC.Comp.Client;

procedure Run(Q: TFDQuery);
begin
  Q.SQL.Text:= 'UPDATE t SET x = 1';
  Q.ExecSQL;
  Q.SQL.Text:= 'SELECT * FROM t';
  Q.Open;
end;

end.
