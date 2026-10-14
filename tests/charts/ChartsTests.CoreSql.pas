unit ChartsTests.CoreSql;

(* Cases for DRagLint.Charts.Sql. The pure scanners run on synthetic lines; the sets run
  against the FROZEN clone charts\scratch\db\SQL-drag-lint-sql.sqlite. Every expected
  value is what Emit-Common.ps1 printed for the same input on 2026-10-13 (spec P3/P4). *)

interface

uses
  DUnitX.TestFramework, DRagLint.Charts.Index, DRagLint.Charts.Source, DRagLint.Charts.Sql;

type
  [TestFixture]
  TCoreSqlTests = class
  private
    FIndex  : TChartsIndex;
    FReader : TSourceReader;
    FCatalog: TSqlCatalog;
    function Open: Boolean;
  public
    [TearDown] procedure TearDown;
    [Test] procedure BodyEndFindsTerminator;
    [Test] procedure BodyEndStopsAtNextStatement;
    [Test] procedure TermInForceIsCaseSensitive;
    [Test] procedure TableSetCollapsesOnNewest;
    [Test] procedure VerbScanIsCaseSensitive;
    [Test] procedure ProcedureAndTriggerSets;
  end;

implementation

uses
  System.SysUtils, System.IOUtils;

const
  REPO_ROOT_ENV = 'DRAGLINT_REPO_ROOT';
  CLONE_REL = 'charts\scratch\db\SQL-drag-lint-sql.sqlite';
  MAX_TWO = 2;
  { the synthetic trigger lines: X ends at END^ (line 4), Y at a bare ^ (line 8) }
  TRIG_Y_LINE = 5;
  TRIG_X_END = 4;
  TRIG_Y_END = 8;
  { the SET TERM lines: ^ after line 1, ; after line 3, a lower-case switch at line 5 }
  AFTER_CARET = 3;
  AFTER_SEMI = 5;
  AFTER_LOWER = 7;
  { Get-SqlTableSet on the SQL clone }
  TABLES = 135;
  DECLARATIONS = 252;
  COLLAPSED = 117;
  PROC_DECLS = 168;
  IPCHART_LINE = 2220;
  IPCHART_COLUMNS = 137;
  { Get-SqlProcedureSet / Get-SqlTriggerSet }
  PROC_WITH_TABLES = 74;
  TRIGGERS = 183;
  TRIG_WITH_OTHER = 4;
  BIU5_END = 202;
  VERB_AT_FROM = 9;
  VERB_AT_DELETE = 42;

function FindUp(const pRel: string): string;
begin
  var Root:= GetEnvironmentVariable(REPO_ROOT_ENV);
  if (Root <> '') and TFile.Exists(TPath.Combine(Root, pRel)) then
    Exit(TPath.Combine(Root, pRel));
  var Dir:= GetCurrentDir;
  while Dir <> '' do
  begin
    if TFile.Exists(TPath.Combine(Dir, pRel)) then
      Exit(TPath.Combine(Dir, pRel));
    var Up:= ExtractFileDir(ExcludeTrailingPathDelimiter(Dir));
    if SameText(Up, Dir) then
      Break;
    Dir:= Up;
  end;
  Result:= '';
end;

function TCoreSqlTests.Open: Boolean;
begin
  var Clone:= FindUp(CLONE_REL);
  Result:= Clone <> '';
  if not Result then
  begin
    Assert.Pass('clone missing');
    Exit;
  end;
  FIndex:= TChartsIndex.Create(Clone);
  FReader:= TSourceReader.Create(FIndex);
  FCatalog:= TSqlCatalog.Create(FIndex, FReader);
end;

procedure TCoreSqlTests.TearDown;
begin
  FreeAndNil(FCatalog);
  FreeAndNil(FReader);
  FreeAndNil(FIndex);
end;

procedure TCoreSqlTests.BodyEndFindsTerminator;
var
  L: TArray<string>;
begin
  L:= ['CREATE TRIGGER X FOR T', 'AS BEGIN', '  NEW.A = 1;', 'END^', 'CREATE TRIGGER Y FOR T', 'AS', 'END', '^'];
  var E:= FindSqlBodyEnd(L, 1, '^', False);
  Assert.IsTrue(E.Found);
  Assert.AreEqual(TRIG_X_END, E.EndLine, 'a line that ENDS in the terminator');
  E:= FindSqlBodyEnd(L, TRIG_Y_LINE, '^', True);
  Assert.AreEqual(TRIG_Y_END, E.EndLine, 'BareTerm: a line that IS the terminator');
  E:= FindSqlBodyEnd(['A', 'b', 'c'], 1, '^', False, MAX_TWO);
  Assert.IsFalse(E.Found);
  Assert.AreEqual('no ^ terminator within 2 lines', E.Reason);
end;

procedure TCoreSqlTests.BodyEndStopsAtNextStatement;
begin
  var E:= FindSqlBodyEnd(['A', 'b', 'alter x', '^'], 1, '^', False);
  Assert.IsFalse(E.Found);
  Assert.AreEqual('reached the next statement at line 3 before a ^ terminator', E.Reason, '-match is case-insensitive');
  E:= FindSqlBodyEnd(['A', 'set term ; ^', '^'], 1, '^', False);
  Assert.AreEqual('reached the next statement at line 2 before a ^ terminator', E.Reason);
end;

procedure TCoreSqlTests.TermInForceIsCaseSensitive;
var
  L: TArray<string>;
begin
  L:= ['SET TERM ^ ;', 'x', 'SET TERM ;^', 'y', 'set term # ;', 'z'];
  Assert.AreEqual('^', SqlTermAt(L, AFTER_CARET));
  Assert.AreEqual(';', SqlTermAt(L, AFTER_SEMI));
  Assert.AreEqual(';', SqlTermAt(L, AFTER_LOWER), '[regex]::Match is case-sensitive: "set term" switches nothing');
end;

procedure TCoreSqlTests.TableSetCollapsesOnNewest;
begin
  if not Open then
    Exit;
  var S:= FCatalog.TableSet;
  Assert.AreEqual(TABLES, Integer(Length(S.Names)));
  Assert.AreEqual(DECLARATIONS, S.DeclarationCount);
  Assert.AreEqual(COLLAPSED, S.CollapsedNames);
  Assert.AreEqual(PROC_DECLS, S.ProcedureDeclCount);
  Assert.AreEqual('AREAOFINTEREST', S.Names[0]);
  Assert.AreEqual('WORORDERS', S.Names[High(S.Names)]);
  var T:= S.Table('ipchart');
  Assert.IsNotNull(T, 'the table set is keyed case-insensitively');
  Assert.AreEqual('IPCHART', T.Name);
  Assert.AreEqual(IPCHART_LINE, T.Line);
  Assert.AreEqual('MS1.SQL', ExtractFileName(T.Path));
  Assert.AreEqual(2, Integer(Length(T.Declarations)));
  Assert.AreEqual(IPCHART_COLUMNS, Integer(Length(T.ColumnNames)));
  Assert.AreEqual('OPTRID', string.Join(',', T.OlderKeys), 'extracted only from the older MScript2.SQL');
end;

procedure TCoreSqlTests.VerbScanIsCaseSensitive;
begin
  if not Open then
    Exit;
  var Hits:= SqlVerbTables('SELECT x FROM CAUSFAIL c JOIN  ipchart i, DELETE   FROM FOLDERS; Cannot Load from CAUSFAIL; ' +
    'EXECUTE PROCEDURE NOPE; INTO RDB$DATABASE', FCatalog.TableSet);
  Assert.AreEqual(2, Integer(Length(Hits)));
  Assert.AreEqual('FROM|CAUSFAIL|table|9', Format('%s|%s|%s|%d', [Hits[0].Verb, Hits[0].Name, Hits[0].Kind, Hits[0].Index]));
  Assert.AreEqual(VERB_AT_FROM, Hits[0].Index);
  Assert.AreEqual('DELETE FROM|FOLDERS|table', Format('%s|%s|%s', [Hits[1].Verb, Hits[1].Name, Hits[1].Kind]));
  Assert.AreEqual(VERB_AT_DELETE, Hits[1].Index);
end;

procedure TCoreSqlTests.ProcedureAndTriggerSets;
begin
  if not Open then
    Exit;
  var Procs:= FCatalog.ProcedureSet;
  Assert.AreEqual(PROC_DECLS, Integer(Length(Procs)));
  var Found:= 0;
  var WithTables:= 0;
  for var P in Procs do
  begin
    if P.Body.Found then
      Inc(Found);
    if Length(P.Tables) > 0 then
      Inc(WithTables);
  end;
  Assert.AreEqual(PROC_DECLS, Found, 'every procedure body found');
  Assert.AreEqual(PROC_WITH_TABLES, WithTables);
  var Trigs:= FCatalog.TriggerSet;
  Assert.AreEqual(TRIGGERS, Integer(Length(Trigs)));
  var Other:= 0;
  for var T in Trigs do
  begin
    if Length(T.OtherTables) > 0 then
      Inc(Other);
    if T.Name = 'DATACHAN_BIU5' then
    begin
      Assert.AreEqual('DATACHAN', T.Table);
      Assert.AreEqual(BIU5_END, T.Body.EndLine);
      Assert.AreEqual('CHANNEL,DATASOURCE,DEVICE,PORTS', string.Join(',', T.Columns));
    end;
  end;
  Assert.AreEqual(TRIG_WITH_OTHER, Other);
end;

end.
