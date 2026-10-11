unit ChartsTests.CoreIndex;

{ Cases for DRagLint.Charts.Index, the in-process index queries ported from
  charts\src\Emit-Common.ps1 (spec P5: no drag-lint.exe is started). They run
  against the FROZEN clone charts\scratch\db\DL-drag-lint.sqlite -- never a live
  index -- and pass with 'clone missing' when the clone is absent. The repo root
  is DRAGLINT_REPO_ROOT, else the first parent of the working directory holding
  the clone. }

interface

uses
  DUnitX.TestFramework, DRagLint.Charts.Index;

type
  [TestFixture]
  TCoreIndexTests = class
  private
    FIndex: TChartsIndex;
    function Open: Boolean;
  public
    [TearDown] procedure TearDown;
    [Test] procedure QueryReturnsNamedColumns;
    [Test] procedure SymbolLocationPrefersImplLine;
    [Test] procedure ResolveQualifiedWins;
    [Test] procedure ResolveAmbiguousBareNameThrowsWithCandidates;
    [Test] procedure ResolveWrongKindThrowsWithHint;
    [Test] procedure ResolveMissingAllowedReturnsNotFound;
    [Test] procedure ForwardDeclarationsCollapse;
    [Test] procedure AllRowsOrderIsStable;
    [Test] procedure EdgelessDisclosureSentence;
    [Test] procedure SqlQuotingHelpers;
    [Test] procedure NoProcessSpawnInUses;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.StrUtils, System.IOUtils, System.Generics.Collections;

const
  REPO_ROOT_ENV = 'DRAGLINT_REPO_ROOT';
  CLONE_REL = 'charts\scratch\db\DL-drag-lint.sqlite';
  INDEX_UNIT_REL = 'src\charts\DRagLint.Charts.Index.pas';
  { a method whose body is far below its interface declaration in the clone }
  IMPL_METHOD = 'DRagLint.Core.Model.TSymbol.DisplayName';
  IMPL_DECL = 441;
  IMPL_START = 2228;
  IMPL_END = 2232;
  CANDIDATE_CAP = 6;
  EDGELESS_THREE = 3;
  EDGELESS_FOUR = 4;
  EDGELESS_N = 99;
  SEVEN = 7;
  EDGELESS_MIN = 50;  { Get-EdgelessFiles default -MinCallRefs }

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

{ The message of the EChartsIndex pAction raises; '' when it raises nothing. }
function RaisedMessage(const pAction: TProc): string;
begin
  Result:= '';
  try
    pAction;
  except
    on E: EChartsIndex do Result:= E.Message;
  end;
end;

function TCoreIndexTests.Open: Boolean;
begin
  var Clone:= FindUp(CLONE_REL);
  Result:= Clone <> '';
  if not Result then
  begin
    Assert.Pass('clone missing');
    Exit;
  end;
  FIndex:= TChartsIndex.Create(Clone);
end;

procedure TCoreIndexTests.TearDown;
begin
  FreeAndNil(FIndex);
end;

procedure TCoreIndexTests.QueryReturnsNamedColumns;
begin
  if not Open then Exit;
  var Rows:= FIndex.Query('SELECT ' + IntToStr(SEVEN) + ' AS Seven, NULL AS gap, ''x'' AS txt, ''12a'' AS bad');
  try
    Assert.AreEqual(1, Integer(Rows.Count));
    { PS property access is case-insensitive }
    Assert.AreEqual(SEVEN, Rows[0].I('SEVEN'));
    Assert.AreEqual('7', Rows[0].S('seven'));
    { NULL reads '' and 0 ([string]$null / [int]$null) }
    Assert.AreEqual('', Rows[0].S('gap'));
    Assert.AreEqual(0, Rows[0].I('gap'));
    Assert.AreEqual(0, Rows[0].I('bad'));
    Assert.IsTrue(Rows[0].Has('GAP'));
    Assert.IsFalse(Rows[0].Has('absent'));
    Assert.AreEqual('', Rows[0].S('absent'));
  finally
    Rows.Free;
  end;
  var None:= FIndex.Query('SELECT id FROM symbols WHERE 1 = 0');
  try
    Assert.AreEqual(0, Integer(None.Count));
  finally
    None.Free;
  end;
end;

procedure TCoreIndexTests.SymbolLocationPrefersImplLine;
begin
  if not Open then Exit;
  var L:= FIndex.SymbolLocation(IMPL_METHOD);
  Assert.AreEqual('method', L.Kind);
  Assert.AreEqual(IMPL_DECL, L.DeclLine);
  Assert.AreEqual(IMPL_START, L.ImplStart);
  Assert.AreEqual(IMPL_END, L.ImplEnd);
  Assert.AreEqual(IMPL_START, L.FocusLine);
  Assert.IsTrue(EndsText('DRagLint.Core.Model.pas', L.Path));
  Assert.AreEqual('No.Such.Symbol is not in this index',
    RaisedMessage(procedure begin FIndex.SymbolLocation('No.Such.Symbol'); end));
end;

procedure TCoreIndexTests.ResolveQualifiedWins;
var
  Found: Boolean;
begin
  if not Open then Exit;
  { `Create` alone is ambiguous; the qualified name is the precise question }
  var M:= FIndex.ResolveMemberSelection(IMPL_METHOD, ['method'], False, RESOLVE_HINT_DEFAULT, Found);
  Assert.IsTrue(Found);
  Assert.AreEqual(IMPL_METHOD, M.QName);
  Assert.AreEqual('DisplayName', M.Name);
  Assert.AreEqual(IMPL_START, M.FocusLine);
end;

procedure TCoreIndexTests.ResolveAmbiguousBareNameThrowsWithCandidates;
var
  Found: Boolean;
  Msg  : string;
begin
  if not Open then Exit;
  Msg:= '';
  try
    FIndex.ResolveMemberSelection('Create', [], False, RESOLVE_HINT_DEFAULT, Found);
  except
    on E: EChartsIndex do Msg:= E.Message;
  end;
  Assert.StartsWith('Create is ambiguous -- ', Msg);
  Assert.Contains(Msg, ' symbols share that name: ');
  Assert.Contains(Msg, ' more. Pass a fully qualified name.');
  { Select-Object -First 6 -> six '; '-separated candidates before the tail }
  var Head:= Copy(Msg, Pos(': ', Msg) + 2, MaxInt);
  Head:= Copy(Head, 1, Pos('; +', Head) - 1);
  Assert.AreEqual(CANDIDATE_CAP, Integer(Length(Head.Split(['; ']))));
end;

procedure TCoreIndexTests.ResolveWrongKindThrowsWithHint;
var
  Found: Boolean;
begin
  if not Open then Exit;
  Assert.AreEqual(IMPL_METHOD + ' is a method, not a field or PROPERTY -- try X',
    RaisedMessage(procedure
      var F: Boolean;
      begin
        FIndex.ResolveMemberSelection(IMPL_METHOD, ['field', 'PROPERTY'], False, 'try X', F);
      end));
  { -contains is case-insensitive: 'METHOD' accepts kind 'method' }
  FIndex.ResolveMemberSelection(IMPL_METHOD, ['METHOD'], False, 'try X', Found);
  Assert.IsTrue(Found);
end;

procedure TCoreIndexTests.ResolveMissingAllowedReturnsNotFound;
var
  Found: Boolean;
begin
  if not Open then Exit;
  var M:= FIndex.ResolveMemberSelection('No.Such.Symbol', [], True, RESOLVE_HINT_DEFAULT, Found);
  Assert.IsFalse(Found);
  Assert.AreEqual(0, M.Id);
  Assert.AreEqual('No.Such.Symbol is not in this index',
    RaisedMessage(procedure
      var F: Boolean;
      begin
        FIndex.ResolveMemberSelection('No.Such.Symbol', [], False, RESOLVE_HINT_DEFAULT, F);
      end));
end;

procedure TCoreIndexTests.ForwardDeclarationsCollapse;
var
  Found: Boolean;
begin
  if not Open then Exit;
  var Twice:= FIndex.Query('SELECT qualified_name FROM symbols WHERE kind IN (''class'',''interface'') ' +
    'GROUP BY qualified_name, generic_params HAVING COUNT(*) > 1 LIMIT 1');
  try
    if Twice.Count = 0 then
    begin
      Assert.Pass('no forward-declared type in the clone');
      Exit;
    end;
    var Q:= Twice[0].S('qualified_name');
    var Widest:= FIndex.Query('SELECT s.id AS id FROM symbols s WHERE s.qualified_name = ''' +
      TChartsIndex.SqlText(Q) + ''' ORDER BY s.end_line - s.start_line DESC, s.start_line LIMIT 1');
    try
      var M:= FIndex.ResolveMemberSelection(Q, ['class', 'interface'], False, RESOLVE_HINT_DEFAULT, Found);
      Assert.IsTrue(Found, 'two rows of one type are not an ambiguity');
      Assert.AreEqual(Widest[0].I('id'), M.Id, 'the widest span (the body) wins');
    finally
      Widest.Free;
    end;
  finally
    Twice.Free;
  end;
end;

procedure TCoreIndexTests.AllRowsOrderIsStable;
begin
  if not Open then Exit;
  var Sql:= 'SELECT f.id AS id, f.path AS path FROM files f';
  var A:= FIndex.AllRows(Sql, 'f.path, f.id');
  var B:= FIndex.AllRows(Sql, 'f.path, f.id');
  try
    var Count:= FIndex.Query('SELECT COUNT(*) AS n FROM files');
    try
      { no 180-row paging and no 200-row cap: every row comes back }
      Assert.AreEqual(Count[0].I('n'), Integer(A.Count));
    finally
      Count.Free;
    end;
    Assert.AreEqual(Integer(A.Count), Integer(B.Count));
    for var K:= 0 to A.Count - 1 do
      Assert.AreEqual(A[K].I('id'), B[K].I('id'));
    for var K:= 1 to A.Count - 1 do
      Assert.IsTrue(CompareStr(A[K - 1].S('path'), A[K].S('path')) <= 0, 'ORDER BY appended');
  finally
    B.Free;
    A.Free;
  end;
end;

procedure TCoreIndexTests.EdgelessDisclosureSentence;
begin
  Assert.AreEqual('', TChartsIndex.EdgelessDisclosure([]));
  var Rows: TArray<TPair<string, Integer>>:= [
    TPair<string, Integer>.Create('C:\a\One.pas', EDGELESS_N), // dl:ok hardcoded-absolute-path@ad66 -- synthetic test input: never touches the filesystem
    TPair<string, Integer>.Create('C:\a\Two.pas', EDGELESS_N), // dl:ok hardcoded-absolute-path@913c -- synthetic test input: never touches the filesystem
    TPair<string, Integer>.Create('C:/a/Three.pas', EDGELESS_N), // dl:ok hardcoded-absolute-path@abf8 -- synthetic test input: never touches the filesystem
    TPair<string, Integer>.Create('C:\a\Four.pas', EDGELESS_N)]; // dl:ok hardcoded-absolute-path@7a06 -- synthetic test input: never touches the filesystem
  Assert.AreEqual('4 file(s) here have call references but NO call edges (One.pas, Two.pas, Three.pas +1 more) ' +
    '-- either their calls all target code outside this index, or a partial resolve cleared them; either way, ' +
    'edges out of symbols in those files are missing', TChartsIndex.EdgelessDisclosure(Rows));
  Assert.AreEqual(EDGELESS_FOUR, Integer(Length(Rows)));
  Assert.Contains(TChartsIndex.EdgelessDisclosure(Copy(Rows, 0, EDGELESS_THREE)), '(One.pas, Two.pas, Three.pas) --');
  if not Open then Exit;
  { the detector runs in-process against the clone; whatever it finds, each row clears the threshold }
  for var P in FIndex.EdgelessFiles do
    Assert.IsTrue(P.Value >= EDGELESS_MIN, P.Key);
end;

procedure TCoreIndexTests.SqlQuotingHelpers;
begin
  Assert.AreEqual('O''''Brien', TChartsIndex.SqlText('O''Brien'));
  Assert.AreEqual('''a'',''b''''c''', TChartsIndex.SqlInList(['a', 'b''c']));
  Assert.AreEqual('', TChartsIndex.SqlInList([]));
  Assert.AreEqual('LEFT JOIN symbols encl ON encl.id = r.enclosing_symbol_id', TChartsIndex.EnclosingRoutineJoin('r'));
  Assert.AreEqual('LEFT JOIN symbols e2 ON e2.id = ma.enclosing_symbol_id', TChartsIndex.EnclosingRoutineJoin('ma', 'e2'));
end;

procedure TCoreIndexTests.NoProcessSpawnInUses;
begin
  { P5 static check: the unit that answers index questions must not be able to
    start a process -- no shell/process unit in any uses clause, no spawn call. }
  var Src:= FindUp(INDEX_UNIT_REL);
  Assert.IsTrue(Src <> '', INDEX_UNIT_REL + ' not found from ' + GetCurrentDir);
  var Text:= TFile.ReadAllText(Src);
  var UsesText:= '';
  var At:= 1;
  repeat
    At:= PosEx('uses', Text, At);
    if At > 0 then
    begin
      var Stop:= PosEx(';', Text, At);
      UsesText:= UsesText + Copy(Text, At, Stop - At) + #10;
      At:= Stop;
    end;
  until At = 0;
  Assert.IsTrue(UsesText <> '', 'no uses clause read');
  for var Banned in ['Winapi.ShellAPI', 'DRagLint.Charts.Process', 'DRagLint.Charts.Producer', 'Winapi.Windows'] do
    Assert.IsFalse(ContainsText(UsesText, Banned), 'uses ' + Banned);
  for var Call in ['CreateProcess', 'ShellExecute', 'WinExec'] do
    Assert.IsFalse(ContainsText(Text, Call), 'calls ' + Call);
end;

end.
