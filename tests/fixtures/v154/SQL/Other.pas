unit Other;
interface
uses SqlStubs, DataMod;
procedure Use;
implementation
procedure Use;
begin
  DM.qTwo.ParamByName('K').AsInteger := 1;
  DM.qTwo.ParamByName('KK').AsInteger := 1; // FIRE sql-param-mismatch
  DM.qTwo.Open;
  DM.qOut.SQL.Text := 'SELECT A FROM T WHERE X = :X';
end;
end.