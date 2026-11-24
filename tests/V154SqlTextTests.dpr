program V154SqlTextTests;
{$APPTYPE CONSOLE}
{ Pins DRagLint.V154.SqlText (1.54 S1) without an index: one SQL text, and the datasets of one unit with the .dfm beside
  it. The index side (other units' datasets and constants) is pinned by run_v154_SQL.ps1.
  Runner: tests\autotest\run_v154_SQLTEXT.ps1. }
uses
  System.SysUtils,
  System.IOUtils,
  DRagLint.V154.SqlText;

var
  Failed: Integer = 0;
  Dir   : string;
  Count : Integer = 0;

procedure Check(const AName, AGot, AWant: string);
begin
  if AGot = AWant then Writeln('  [PASS] ', AName)
  else
  begin
    Writeln('  [FAIL] ', AName, '  got "', AGot, '" want "', AWant, '"');
    Inc(Failed);
  end;
end;

{ verb, parameters or ! reason, target(columns), tables }
function Dump(const ASql: string): string;
const
  VERBS: array[TSqlVerb] of string = ('none', 'select', 'insert', 'update', 'delete', 'merge', 'proc', 'other');
begin
  var F: TSqlTextFacts:= ReadSqlText(ASql);
  Result:= VERBS[F.Verb] + ' ' + (if F.ParamReason <> '' then '!' + F.ParamReason else string.Join(',', F.ParamNames));
  if F.TargetTable <> '' then Result:= Result + ' -> ' + F.TargetTable + '(' + string.Join(',', F.TargetColumns) + ')';
  if Length(F.Source.Tables) > 0 then Result:= Result + ' <- ' + F.Source.Tables[0].Name;
end;

procedure Sql(const ASql, AWant: string);
begin
  Check(ASql, Dump(ASql), AWant);
end;

{ Writes a unit TForm1 with ABody as its method text and returns one line for the dataset named AName. }
function Scan(const AName, ABody: string; const ADfm: string = ''; const ADecl: string = ''): string;
begin
  Inc(Count);
  var Pas: string:= TPath.Combine(Dir, Format('u%d.pas', [Count]));
  TFile.WriteAllText(Pas, Format('unit u%d;'#13#10'interface'#13#10'const'#13#10'  SQL_ALL = ''SELECT A FROM T WHERE ''+''ID = :ID'';'#13#10 +
    'type'#13#10'  TForm1 = class(TForm)'#13#10'    Q1: TFDQuery;'#13#10'    T1: TFDTable;'#13#10'  private'#13#10'    FQ: TFDQuery;'#13#10 +
    '    procedure Foo(P: TFDQuery);'#13#10'  end;'#13#10'implementation'#13#10'%s'#13#10'procedure TForm1.Foo(P: TFDQuery);'#13#10'%s'#13#10'end.'#13#10,
    [Count, ADecl, ABody]));
  if ADfm <> '' then TFile.WriteAllText(TPath.ChangeExtension(Pas, '.dfm'), 'object Form1: TForm1'#13#10 + ADfm + #13#10'end'#13#10);
  var S: TSqlTextScan:= TSqlTextScan.Create(Pas, nil, 0);
  try
    Result:= 'none';
    for var D: TSqlDataset in S.Datasets do
      if SameText(D.Name, AName) then
      begin
        Result:= D.DataClass + ' ' + (if D.Reason <> '' then '!' + D.Reason else string.Join(',', D.Facts.ParamNames)) +
          (if D.Table = '' then '' else ' ' + D.Table);
        var T, C, R: string;
        if S.ColumnOf(D, 'A', T, C, R) then Result:= Result + ' col ' + T + '.' + C;
        Exit;
      end;
  finally
    S.Free;
  end;
end;

{ Kinds of the sites of AName, in order. }
function Sites(const AName, ABody: string): string;
const
  KINDS: array[TSqlSiteKind] of string = ('set', 'add', 'clear', 'other', 'param', 'params', 'run', 'field', 'nopar', 'new', 'pass');
begin
  Result:= '';
  Inc(Count);
  var Pas: string:= TPath.Combine(Dir, Format('u%d.pas', [Count]));
  TFile.WriteAllText(Pas, Format('unit u%d;'#13#10'interface'#13#10'implementation'#13#10'procedure Foo(P: TFDQuery);'#13#10'%s'#13#10'end.'#13#10, [Count, ABody]));
  var S: TSqlTextScan:= TSqlTextScan.Create(Pas, nil, 0);
  try
    for var D: TSqlDataset in S.Datasets do
      if SameText(D.Name, AName) then
        for var X: TSqlSite in D.Sites do
          Result:= Result + (if Result = '' then '' else ' ') + KINDS[X.Kind] + (if X.Known then '=' + X.Text else '');
  finally
    S.Free;
  end;
end;

const
  NEWQ = 'var Q: TFDQuery; begin Q := TFDQuery.Create(nil); ';

begin
  Dir:= TPath.Combine(ExtractFilePath(ParamStr(0)), 'cases');
  TDirectory.CreateDirectory(Dir);

  Writeln('SQL TEXT');
  Sql('SELECT A FROM T WHERE B = :B AND C=:c AND :b > 0', 'select B,c <- T');
  Sql('SELECT CAST(A AS INT)::TEXT FROM T', 'select  <- T');
  Sql('SELECT '':NO'' FROM T WHERE X = '':a''', 'select  <- T');
  Sql('SELECT "X:Y" FROM T', 'select  <- T');
  Sql('SELECT A FROM T WHERE ID = :"My Id"', 'select My Id <- T');
  Sql('SELECT A -- note'#13#10' FROM T /* plain */ WHERE B=:B', 'select B <- T');
  Sql('SELECT A FROM T /* :X */', 'select !the SQL has a parameter in a comment <- T');
  Sql('SELECT A FROM &TAB WHERE X=:X', 'select !the SQL has a macro');
  Sql('SELECT A FROM T WHERE X != :X', 'select X <- T');
  Sql('SELECT A FROM T WHERE X = ?', 'select !the SQL has positional parameters <- T');
  Sql('SELECT A FROM T WHERE X = :1', 'select !the SQL has numbered parameters <- T');
  Sql('EXECUTE BLOCK (A INT = :A) AS BEGIN B = :B; END', 'proc !EXECUTE BLOCK: its colons are PSQL variables');
  Sql('CREATE TRIGGER X FOR T AS BEGIN IF (:A = 1) THEN EXIT; END', 'other !DDL: its colons are PSQL variables');
  Sql('EXECUTE PROCEDURE P(:A, :B)', 'proc A,B');
  Sql('insert into "T" (A, "B") values (:A, :B)', 'insert A,B -> T(A,B)');
  Sql('UPDATE OR INSERT INTO T (A) VALUES (:A) MATCHING (A)', 'insert A -> T(A)');
  Sql('INSERT INTO T SELECT A FROM U', 'insert  -> T()');
  Sql('UPDATE T SET A = :A', 'update A -> T()');
  Sql('DELETE FROM T WHERE A = :A', 'delete A -> T()');
  Sql('', 'none !there is no SQL text');
  Sql('SELECT A FROM T UNION SELECT B FROM U WHERE C=:C', 'select C');

  Writeln('DATASETS');
  Check('local, one literal', Scan('Q', NEWQ + 'Q.SQL.Text := ''SELECT A FROM T WHERE X=:X''; Q.Open; end;'), 'TFDQuery X T col T.A');
  Check('local, unit constant', Scan('Q', NEWQ + 'Q.SQL.Text := SQL_ALL; end;'), 'TFDQuery ID T col T.A');
  Check('local, routine constant', Scan('Q', 'const C = ''SELECT :Y FROM T''; ' + NEWQ + 'Q.SQL.Text := C; end;'), 'TFDQuery Y T');
  Check('inline variable', Scan('Q', 'begin var Q := TFDQuery.Create(nil); Q.SQL.Text := ''SELECT A FROM T''; end;'), 'TFDQuery  T col T.A');
  Check('a star lists nothing', Scan('Q', NEWQ + 'Q.SQL.Text := ''SELECT * FROM T''; end;'), 'TFDQuery  T col T.A');
  Check('an expression is no column', Scan('Q', NEWQ + 'Q.SQL.Text := ''SELECT B+1 A FROM T''; end;'), 'TFDQuery  T');
  Check('clear and add', Scan('Q', NEWQ + 'Q.SQL.Clear; Q.SQL.Add(''SELECT A''); Q.SQL.Add(''FROM T WHERE X=:X''); Q.Open; end;'), 'TFDQuery X T col T.A');
  Check('add in a branch', Scan('Q', NEWQ + 'Q.SQL.Add(''SELECT A FROM T''); if P = nil then Q.SQL.Add(''WHERE X=:X''); end;'), 'TFDQuery !the SQL is assigned in several places');
  Check('add in both branches', Scan('Q', NEWQ + 'if P = nil then Q.SQL.Add(''SELECT :X'') else Q.SQL.Add(''SELECT :Y''); end;'), 'TFDQuery !the SQL is assigned in several places');
  Check('two texts', Scan('Q', NEWQ + 'Q.SQL.Text := ''SELECT 1''; Q.Open; Q.SQL.Text := ''SELECT :X''; end;'), 'TFDQuery !the SQL is assigned in several places');
  Check('added after a run', Scan('Q', NEWQ + 'Q.SQL.Add(''SELECT 1''); Q.Open; Q.SQL.Add(''+ :X''); end;'), 'TFDQuery !the SQL is assigned in several places');
  Check('built SQL', Scan('Q', NEWQ + 'Q.SQL.Text := ''SELECT '' + P.Name; end;'), 'TFDQuery !the SQL is built by an expression');
  Check('Format', Scan('Q', NEWQ + 'Q.SQL.Text := Format(''SELECT %s'', [''X'']); end;'), 'TFDQuery !the SQL is built by an expression');
  Check('loaded from a file', Scan('Q', NEWQ + 'Q.SQL.LoadFromFile(''a''); end;'), 'TFDQuery !the SQL is changed in a way that is not read');
  Check('SQL handed out', Scan('Q', NEWQ + 'Q.SQL.Text := ''SELECT 1''; Fill(Q.SQL); end;'), 'TFDQuery !the SQL is changed in a way that is not read');
  Check('dataset passed on', Scan('Q', NEWQ + 'Q.SQL.Text := ''SELECT 1''; Fill(Q); end;'), 'TFDQuery !the dataset is passed on');
  Check('dataset aliased', Scan('Q', NEWQ + 'Q.SQL.Text := ''SELECT 1''; DS.DataSet := Q; end;'), 'TFDQuery !the dataset is passed on');
  Check('freed and tested is not passed on', Scan('Q', NEWQ + 'Q.SQL.Text := ''SELECT :X FROM T''; if Assigned(Q) then FreeAndNil(Q); end;'), 'TFDQuery X T');
  Check('parameter', Scan('P', 'begin P.SQL.Text := ''SELECT 1''; end;'), 'TFDQuery !the dataset is a parameter');
  Check('not created here', Scan('Q', 'var Q: TFDQuery; begin Q := GetQ; Q.SQL.Text := ''SELECT 1''; end;'), 'TFDQuery !the dataset is not created here');
  Check('created twice', Scan('Q', NEWQ + 'Q := TFDQuery.Create(nil); Q.SQL.Text := ''SELECT 1''; end;'), 'TFDQuery !the dataset is not created here');
  Check('ParamCheck', Scan('Q', NEWQ + 'Q.ParamCheck := False; Q.SQL.Text := ''SELECT 1''; end;'), 'TFDQuery !parameter checking is switched');
  Check('Open with a text', Scan('Q', NEWQ + 'Q.Open(''SELECT A FROM T WHERE X=:X''); end;'), 'TFDQuery X T col T.A');
  Check('with', Scan('Q', NEWQ + 'with Q do begin SQL.Text := ''SELECT :X FROM T''; Open; end; end;'), 'TFDQuery X T');
  Check('with two targets', Scan('Q', NEWQ + 'with Q, Other do begin SQL.Text := ''SELECT :X FROM T''; end; end;'), 'TFDQuery !the dataset is passed on');
  Check('multi-line literal', Scan('Q', NEWQ + 'Q.SQL.Text := '''''''#13#10'   SELECT A'#13#10'   FROM T WHERE X=:X'#13#10'   '''''';'#13#10' end;'), 'TFDQuery X T col T.A');
  Check('quote in a literal', Scan('Q', NEWQ + 'Q.SQL.Text := ''SELECT A FROM T WHERE X='''':N'''' AND Y=:Y''; end;'), 'TFDQuery Y T col T.A');
  Check('private field', Scan('FQ', 'begin FQ := TFDQuery.Create(nil); FQ.SQL.Text := ''SELECT :Z FROM T''; end;'), 'TFDQuery Z T');
  Check('field set by two methods', Scan('FQ', 'begin FQ.SQL.Text := ''SELECT :Z''; end;', '', 'procedure TForm1.Bar; begin FQ.SQL.Text := ''SELECT 1''; end;'),
    'TFDQuery !the SQL is assigned in several places');
  Check('Self.Q is the field', Scan('FQ', 'begin Self.FQ.SQL.Text := ''SELECT :Z FROM T''; FQ.Open; end;'), 'TFDQuery Z T');
  Check('local hides the field', Scan('Q1', 'var Q1: TFDQuery; begin Q1 := TFDQuery.Create(nil); Q1.SQL.Text := ''SELECT :L FROM T''; end;', '  object Q1: TFDQuery'#13#10'    SQL.Strings = ('#13#10'      ''SELECT 1'')'#13#10'  end'),
    'TFDQuery L T');

  Writeln('DFM');
  Check('SQL of the form', Scan('Q1', 'begin Q1.Open; end;', '  object Q1: TFDQuery'#13#10'    SQL.Strings = ('#13#10'      ''SELECT A FROM T'''#13#10'      ''WHERE X=:X'')'#13#10'  end'), 'TFDQuery X T col T.A');
  Check('SQL of the form and of the code', Scan('Q1', 'begin Q1.SQL.Text := ''SELECT 1''; Q1.Open; end;', '  object Q1: TFDQuery'#13#10'    SQL.Strings = ('#13#10'      ''SELECT 2'')'#13#10'  end'),
    'TFDQuery !the SQL is assigned in several places');
  Check('table', Scan('T1', 'begin T1.Open; end;', '  object T1: TFDTable'#13#10'    TableName = ''"Orders.DB"'''#13#10'  end'), 'TFDTable !no SQL text in the unit or its DFM ORDERS col ORDERS.A');
  Check('table set by code', Scan('T1', 'begin T1.TableName := ''X''; end;', '  object T1: TFDTable'#13#10'    TableName = ''ORDERS'''#13#10'  end'),
    'TFDTable !the SQL is changed in a way that is not read');
  Check('ParamCheck of the form', Scan('Q1', 'begin Q1.Open; end;', '  object Q1: TFDQuery'#13#10'    ParamCheck = False'#13#10'    SQL.Strings = ('#13#10'      ''SELECT 2'')'#13#10'  end'),
    'TFDQuery !parameter checking is switched');
  Check('inherited component', Scan('Q1', 'begin Q1.Open; end;', '  inherited Q1: TFDQuery'#13#10'    SQL.Strings = ('#13#10'      ''SELECT 2'')'#13#10'  end'),
    'TFDQuery !the component is inherited from another form');

  Writeln('SITES');
  Check('members', Sites('Q', NEWQ + 'Q.SQL.Text := ''S :A''; Q.ParamByName(''A'').AsInteger := 1; Q.Params.FindParam(''B''); Q.Params[0].Value := 1; Q.Open; ' +
    'Q.FieldByName(''F'').AsString; Q.Active := True; Q.Active := False; end;'), 'new=TFDQuery set=S :A param=A param=B params run field=F run');
  Check('values and arrays', Sites('Q', NEWQ + 'Q.Open(''S'', [1]); Q.Execute(10); Q.ExecSQL(True); end;'), 'new=TFDQuery set=S params run params run run');
  Check('passed before the first member', Sites('P', 'begin Fill(P); P.Open; end;'), 'pass run');
  Check('lambda sees the local', Sites('Q', NEWQ + 'Run(procedure begin Q.Open; end); end;'), 'new=TFDQuery run');
  Check('nested routine sees the local', Sites('Q', 'var Q: TFDQuery; procedure N; begin Q.Open; end; begin Q := TFDQuery.Create(nil); end;'), 'run new=TFDQuery');

  Writeln;
  if Failed = 0 then Writeln('ALL PASS') else Writeln(Failed, ' FAILED');
  ExitCode:= if Failed = 0 then 0 else 1;
end.
