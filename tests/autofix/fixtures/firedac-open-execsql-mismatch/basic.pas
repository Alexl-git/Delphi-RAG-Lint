unit basic;

interface

implementation

uses
  FireDAC.Comp.Client;

procedure Run(Q: TFDQuery);
begin
  Q.SQL.Text:= 'UPDATE t SET x = 1';
  Q.Open;
  Q.SQL.Text:= 'SELECT * FROM t';
  Q.ExecSQL;
end;

end.
