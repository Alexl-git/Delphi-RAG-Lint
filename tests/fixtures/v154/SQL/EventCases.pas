unit EventCases;
interface
uses SqlStubs;
procedure EventSet(DataSet: TObject);
procedure LocalEvent;
implementation
procedure EventSet(DataSet: TObject);
begin
  TFDQuery(DataSet).ParamByName('B').AsInteger := 1;
end;
procedure LocalEvent;
var
  Q: TFDQuery;
begin
  Q := TFDQuery.Create(nil);
  try
    Q.SQL.Text := 'SELECT A FROM T WHERE A = :A AND B = :B';
    Q.ParamByName('A').AsInteger := 1;
    Q.BeforeOpen := EventSet;
    Q.Open;
  finally
    Q.Free;
  end;
end;
end.
