unit ParamCases;
interface
uses SqlStubs;
procedure Wrong;
procedure Missing;
procedure Silent(AName: string; P: TFDQuery);
implementation

procedure Wrong;
var
  Q: TFDQuery;
begin
  Q := TFDQuery.Create(nil);
  try
    Q.SQL.Text := 'SELECT A FROM T WHERE ID = :ID';
    Q.ParamByName('ID2').AsInteger := 1; // FIRE sql-param-mismatch
    Q.ParamByName('id').AsInteger := 1;
    Q.Open;
  finally
    Q.Free;
  end;
end;

procedure Missing;
var
  Q, W, E: TFDQuery;
begin
  Q := TFDQuery.Create(nil);
  Q.SQL.Text := 'SELECT A FROM T WHERE ID = :ID AND NAME = :NAME';
  Q.ParamByName('ID').AsInteger := 1;
  Q.Open; // FIRE sql-param-mismatch
  W := TFDQuery.Create(nil);
  with W do
  begin
    SQL.Clear;
    SQL.Add('UPDATE T SET A = :A');
    SQL.Add('WHERE ID = :ID');
    ParamByName('A').AsInteger := 1;
    Params.ParamByName('IDX').AsInteger := 1; // FIRE sql-param-mismatch
    ExecSQL; // FIRE sql-param-mismatch
  end;
  E := TFDQuery.Create(nil);
  E.SQL.Text := SQL_SHARED;
  E.ParamByName('SHARD').AsInteger := 1; // FIRE sql-param-mismatch
  E.ParamByName('SHARED').AsInteger := 1;
  E.Open;
end;

procedure Fill(Q: TFDQuery);
begin
  Q.ParamByName('NOPE').AsInteger := 1;
end;

procedure Silent(AName: string; P: TFDQuery);
var
  Built, Macro, Twice, Off, Passed, Block, Cast, Got, Posit, Found, Alias, Master, Lit: TFDQuery;
begin
  Built := TFDQuery.Create(nil);
  Built.SQL.Text := 'SELECT A FROM T WHERE ' + AName;
  Built.ParamByName('X').AsInteger := 1;
  Macro := TFDQuery.Create(nil);
  Macro.SQL.Text := 'SELECT A FROM T WHERE &COND';
  Macro.ParamByName('X').AsInteger := 1;
  Twice := TFDQuery.Create(nil);
  Twice.SQL.Text := 'SELECT 1 FROM T WHERE A = :A';
  Twice.ParamByName('A').AsInteger := 1;
  Twice.Open;
  Twice.SQL.Text := 'SELECT 1 FROM T WHERE B = :B';
  Twice.ParamByName('B').AsInteger := 1;
  Off := TFDQuery.Create(nil);
  Off.ParamCheck := False;
  Off.SQL.Text := 'SELECT A FROM T';
  Off.ParamByName('X').AsInteger := 1;
  Passed := TFDQuery.Create(nil);
  Passed.SQL.Text := 'SELECT A FROM T WHERE B = :B';
  Fill(Passed);
  Passed.Open;
  Block := TFDQuery.Create(nil);
  Block.SQL.Text := 'EXECUTE BLOCK AS DECLARE X INT; BEGIN X = :Y; END';
  Block.ParamByName('Z').AsInteger := 1;
  Block.ExecSQL;
  Cast := TFDQuery.Create(nil);
  Cast.SQL.Text := 'SELECT A::TEXT, '':N'' FROM T';
  Cast.Open;
  Got := GetQ;
  Got.SQL.Text := 'SELECT A FROM T';
  Got.ParamByName('X').AsInteger := 1;
  Posit := TFDQuery.Create(nil);
  Posit.SQL.Text := 'SELECT A FROM T WHERE B = :B';
  Posit.Params[0].AsInteger := 1;
  Posit.Open;
  Found := TFDQuery.Create(nil);
  Found.SQL.Text := 'SELECT A FROM T';
  if Found.FindParam('X') <> nil then Found.FindParam('X').AsInteger := 1;
  Alias := TFDQuery.Create(nil);
  Alias.SQL.Text := 'SELECT A FROM T WHERE B = :B';
  P := Alias;
  Alias.Open;
  Master := TFDQuery.Create(nil);
  Master.MasterSource := P;
  Master.SQL.Text := 'SELECT A FROM T WHERE B = :B';
  Master.Open;
  Lit := TFDQuery.Create(nil);
  Lit.SQL.Text := 'SELECT A FROM T WHERE B = :B';
  Lit.ParamByName(AName).AsInteger := 1;
  Lit.Open;
  P.SQL.Text := 'SELECT A FROM T';
  P.ParamByName('X').AsInteger := 1;
end;

end.