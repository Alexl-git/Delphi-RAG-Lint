unit ChartsTests.CoreChain;

(* Cases for DRagLint.Charts.Chain. The small helpers run on synthetic input; the chain and
  the binding population run against the FROZEN clones charts\scratch\db\CLIENT-Micronite2027
  and SQL-drag-lint-sql. Every expected value is what Emit-Common.ps1 printed for the same
  call on 2026-10-13 (spec P3/P4). *)

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TCoreChainTests = class
  public
    [Test] procedure ReceiverMatchIsAnExactSuffix;
    [Test] procedure RePointControlFromReceiverOrSource;
    [Test] procedure RhsRootReasons;
    [Test] procedure ChainKeyAndDataSourceSql;
    [Test] procedure ClientPopulationMatchesPowerShell;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, System.Generics.Collections, DRagLint.Charts.Index, DRagLint.Charts.Source, DRagLint.Charts.Sql,
  DRagLint.Charts.Chain;

const
  REPO_ROOT_ENV = 'DRAGLINT_REPO_ROOT';
  CLIENT_REL = 'charts\scratch\db\CLIENT-Micronite2027.sqlite';
  SQL_REL = 'charts\scratch\db\SQL-drag-lint-sql.sqlite';
  { Get-FieldBindingChains on CLIENT against the SQL clone }
  DATASOURCES = 54;
  BINDINGS = 808;
  CHAINS = 69;
  REPOINTS = 65;
  OUTCOMES = 'ambiguous=37 column=443 dangling=222 no-ds=1 not-column=28 stops=77';
  REPOINT_STATUSES = 'multi-rhs=1 no-site=2 stops=3 table=22 walk-limit=37';
  JOBLIST_HOPS = 4;
  HOP_DATASET = 1;
  HOP_RHS_TYPE = 2;
  HOP_TABLE = 3;

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

{ "name=count" for each distinct value, sorted ordinally (Group-Object's order for these keys). }
function Tally(const pValues: TArray<string>): string;
begin
  var Sorted:= Copy(pValues);
  TArray.Sort<string>(Sorted);
  var Parts: TArray<string>:= [];
  var K:= 0;
  while K < Length(Sorted) do
  begin
    var N:= 1;
    while (K + N < Length(Sorted)) and (Sorted[K + N] = Sorted[K]) do
      Inc(N);
    Parts:= Parts + [Format('%s=%d', [Sorted[K], N])];
    Inc(K, N);
  end;
  Result:= string.Join(' ', Parts);
end;

procedure TCoreChainTests.ReceiverMatchIsAnExactSuffix;
begin
  Assert.AreEqual('(UPPER(r.receiver_text) = UPPER(''dsr_A''''x'') OR (LENGTH(r.receiver_text) > 8 AND ' +
    'UPPER(SUBSTR(r.receiver_text, -8)) = UPPER(''.dsr_A''''x'')))', ReceiverMatchSql('r.receiver_text', 'dsr_A''x'));
end;

procedure TCoreChainTests.RePointControlFromReceiverOrSource;

  function Show(const pR: TRePointControl): string;
  begin
    Result:= pR.Control + '|' + pR.From;
  end;

begin
  Assert.AreEqual('edtA|receiver', Show(RePointControl('Self.edtA.DataBinding', '', True)));
  Assert.AreEqual('x|receiver', Show(RePointControl('self.x', '', True)), '-eq ''Self'' is case-insensitive');
  Assert.AreEqual('|', Show(RePointControl('.DataBinding', '  frm . edtF2 .  DataBinding  .', True)), 'a qualifier is not a control');
  Assert.AreEqual('grdX|source', Show(RePointControl('.DataBinding', 'Self.grdX.DataController.', True)));
  Assert.AreEqual('|', Show(RePointControl('', '', False)), 'a stale file has no Before');
end;

procedure TCoreChainTests.RhsRootReasons;
begin
  Assert.AreEqual('FVM', RhsRoot('Self.FVM.MemTable').Root);
  Assert.AreEqual('FVM', RhsRoot('  self . FVM.T').Root, '-replace ''^Self\s*\.'' is case-insensitive');
  Assert.AreEqual('RHS (VM as IFoo).MT is a cast expression -- its type is not followed', RhsRoot('(VM as IFoo).MT').Reason);
  Assert.AreEqual('RHS TFoo(X).Y starts with a call or hard cast (TFoo(...)) -- its result type is not followed', RhsRoot('TFoo(X).Y').Reason);
  Assert.AreEqual('RHS is empty -- nothing to follow', RhsRoot('Self.').Reason);
  Assert.AreEqual('RHS 123 has no identifier root -- nothing to follow', RhsRoot('123').Reason);
end;

procedure TCoreChainTests.ChainKeyAndDataSourceSql;
begin
  Assert.AreEqual('C:\A\FORM1.DFM|DSRX', ChainKey('c:\a\Form1.dfm', 'dsrX')); // dl:ok hardcoded-absolute-path@a185 -- synthetic key text: never touches the filesystem
  Assert.StartsWith('COALESCE((SELECT d.text FROM string_literals d WHERE d.kind = ''dfm-prop'' AND d.file_id = sl.file_id', ControlDataSourceSql);
  Assert.EndsWith('AND d.symbol_id = (SELECT g.parent_id FROM symbols g WHERE g.id = c.parent_id) ORDER BY d.start_line LIMIT 1))',
    ControlDataSourceSql);
end;

procedure TCoreChainTests.ClientPopulationMatchesPowerShell;
begin
  var ClientDb:= FindUp(CLIENT_REL);
  var SqlDb:= FindUp(SQL_REL);
  if (ClientDb = '') or (SqlDb = '') then
  begin
    Assert.Pass('clones missing');
    Exit;
  end;
  var Client:= TChartsIndex.Create(ClientDb);
  var SqlIndex:= TChartsIndex.Create(SqlDb);
  var ClientReader:= TSourceReader.Create(Client);
  var SqlReader:= TSourceReader.Create(SqlIndex);
  var Catalog:= TSqlCatalog.Create(SqlIndex, SqlReader);
  var Walker:= TChainWalker.Create(Client, ClientReader, Catalog, Catalog.TableSet);
  try
    var Fb:= Walker.FieldBindingChains;
    Assert.AreEqual(DATASOURCES, Integer(Length(Fb.DataSources)));
    Assert.AreEqual(BINDINGS, Integer(Length(Fb.Bindings)));
    Assert.AreEqual(CHAINS, Integer(Length(Fb.Chains)));
    Assert.AreEqual(REPOINTS, Integer(Length(Fb.RePoints)));
    var Seen: TArray<string>:= [];
    for var B in Fb.Bindings do
      Seen:= Seen + [B.Outcome];
    Assert.AreEqual(OUTCOMES, Tally(Seen));
    var Statuses: TArray<string>:= [];
    for var R in Fb.RePoints do
      Statuses:= Statuses + [R.Status];
    Assert.AreEqual(REPOINT_STATUSES, Tally(Statuses));
    var Found:= False;
    for var C in Fb.DataSources do
      if (C.DsName = 'dsrFolder') and C.FormFile.EndsWith('uJobList.dfm') then
      begin
        Found:= True;
        Assert.AreEqual('one-table|FOLDERS', C.Grade + '|' + C.ResolvedTable);
        Assert.AreEqual(JOBLIST_HOPS, Integer(Length(C.Hops)));
        Assert.AreEqual('dsrFolder.DataSet := FViewModel.MemTable', C.Hops[HOP_DATASET].Caption);
        Assert.AreEqual('FViewModel: TJobListViewModel', C.Hops[HOP_RHS_TYPE].Caption);
        Assert.AreEqual('the only upper-case table-name literal in uJobList.ViewModel.pas; 1 literal(s) equal a table name only ' +
          'case-insensitively and are not taken as one: ''DueIN'' :301', C.Hops[HOP_TABLE].Reason);
        Break;
      end;
    Assert.IsTrue(Found, 'uJobList dsrFolder chain');
  finally
    Walker.Free;
    Catalog.Free;
    SqlReader.Free;
    ClientReader.Free;
    SqlIndex.Free;
    Client.Free;
  end;
end;

end.
