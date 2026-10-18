unit ChartsTests.CoreMemberAccess;

{ Cases for DRagLint.Charts.MemberAccess, the data layer of who-writes / who-reads (a port of
  charts\src\Emit-MemberAccess.ps1, steps 1-5 and the measurement functions). The constants are the
  PS emitter's RESULT OBJECT measured on the frozen clone charts\scratch\db\CLIENT-Micronite2027.sqlite
  (task-2-harvest.md of the b5 ledger); the PS output is the reference. Every case passes with
  'clone missing' when the clone is absent. The repo root is DRAGLINT_REPO_ROOT, else the first
  parent of the working directory holding the clone. }

interface

uses
  DUnitX.TestFramework, DRagLint.Core.Interfaces, DRagLint.Charts.Index, DRagLint.Charts.MemberAccess;

type
  [TestFixture]
  TMemberAccessDataTests = class
  private
    FIndex: TChartsIndex;
    FStore: ISymbolStore;
    FData : TMemberAccessData;
    function Collect(const pTarget, pMode: string; pCap: Integer): Boolean;
    function RefusalOf(const pTarget: string): string;
  public
    [TearDown] procedure TearDown;
    [Test] procedure RFieldBothWings;
    [Test] procedure VerdictPropertyNamesItsAccessors;
    [Test] procedure FConnectedWritesAnchorEverySite;
    [Test] procedure FNoRecursionReadsAreUnbound;
    [Test] procedure FLotsizeWithBodyWriteIsByName;
    [Test] procedure ResultZeroNoteNamesEveryPopulation;
    [Test] procedure ConnectedReadsAreCapped;
    [Test] procedure MethodIsRefused;
    [Test] procedure MissingIsRefused;
    [Test] procedure AmbiguousIsRefused;
    [Test] procedure UnknownModeIsRefused;
    [Test] procedure SortIsThePowerShellOrder;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, DRagLint.Storage.SQLite, DRagLint.Charts.Question;

const
  REPO_ROOT_ENV = 'DRAGLINT_REPO_ROOT';
  CLONE_REL = 'charts\scratch\db\CLIENT-Micronite2027.sqlite';
  DEFAULT_CAP = 20;
  CAP_25 = 25;
  { d1: both wings, three accesses on one line }
  R_QNAME = 'MSCTYPES.RChartSampleData.R';
  R_WRITES = 7;
  R_READS = 13;
  R_ROUTINES = 4;
  R_SITES = 20;
  R_SHOWN_WRITERS = 3;
  R_SHOWN_READERS = 4;
  R_ELSEWHERE_WRITES = 1;
  R_DRAW_SAMPLE = 'BASICSF.DrawSample';
  R_LINE = 4072;
  R_COL_READ_1 = 34;
  R_COL_READ_2 = 51;
  R_COL_WRITE = 63;
  R_DRAW_SAMPLE_WRITES = 3;
  { d2 }
  VERDICT_QNAME = 'iINSPRSLT.ImcINSPRSLT.VERDICT';
  VERDICT_WRITES = 34;
  VERDICT_READS = 12;
  VERDICT_ROUTINES = 30;
  VERDICT_SITES = 46;
  { d3 }
  FCONN_QNAME = 'uPipeClientConnection.TPipeClientConnection.FConnected';
  FCONN_CONNECT = 'uPipeClientConnection.TPipeClientConnection.Connect';
  FCONN_WRITES = 4;
  FCONN_ROUTINES = 3;
  FCONN_LINE_1 = 320;
  FCONN_LINE_2 = 455;
  FCONN_COL = 3;
  FCONN_READ_COUNT = 602;
  FCONN_READS_SAME = 3;
  FCONN_READ_COUNT_TEXT = '602 resolved read(s) reported by find-callers + 3 unbound read(s) named FConnected in uPipeClientConnection.pas';
  { d4 }
  NOREC_QNAME = 'Blueprint4.TfrmBlueprint4.FNoRecursion';
  NOREC_WRITES = 48;
  NOREC_READS_SAME = 9;
  NOREC_READ_LINES = ':1950,:2084,:2113,:2138,:2163,:2179,:2238,:3142,:3546';
  NOREC_ZERO_NOTE = '0 resolved read(s) reported by find-callers + 9 unbound read(s) named FNoRecursion in Blueprint4.pas (48 writes)';
  NOREC_READS_LABEL = 'resolved read sites reported by find-callers + 9 unbound read(s) named FNoRecursion in Blueprint4.pas';
  NOREC_ROUTINES_LABEL = 'routines reported by find-callers';
  { d5 }
  LOT_QNAME = 'uPLANLIST.TmcPLANLIST.fLOTSIZE';
  LOT_WRITES = 5;
  LOT_LINE = ':2547';
  { d6 }
  RESULT_QNAME = 'INSPFLDR.Messages.TTabSwitchMessage.Result';
  RESULT_WRITES_SAME = 7;
  RESULT_WRITES_ELSEWHERE = 10474;
  RESULT_READS_ELSEWHERE = 4888;
  RESULT_ZERO_NOTE = '0 resolved write(s) reported by find-callers + 7 unbound write(s) named Result in INSPFLDR.Messages.pas + ' +
    '10474 unbound same-name write(s) in other files (may be other symbols) (0 resolved read(s) reported by find-callers + ' +
    '4888 unbound same-name read(s) in other files (may be other symbols))';
  { d7 }
  CONN_QNAME = 'uPipeClientConnection.TPipeClientConnection.Connected';
  CONN_READS = 602;
  CONN_ROUTINES = 598;
  CONN_HIDDEN_ROUTINES = 573;
  CONN_HIDDEN_SITES = 573;
  { refusals (Test-Emitters N9, N10, N10b) }
  METHOD_QNAME = 'Blueprint4.ViewModel.TBlueprint_ViewModel.SendDeltaOperation';
  AMBIGUOUS_NAME = 'ID';

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

{ Opens the clone and collects one selection; False (after Assert.Pass) when the clone is missing. }
function TMemberAccessDataTests.Collect(const pTarget, pMode: string; pCap: Integer): Boolean;
begin
  var Clone:= FindUp(CLONE_REL);
  Result:= Clone <> '';
  if not Result then
  begin
    Assert.Pass('clone missing');
    Exit;
  end;
  if FIndex = nil then
  begin
    FStore:= TSQLiteSymbolStore.Create(Clone, True);
    FIndex:= TChartsIndex.Create(Clone);
  end;
  FreeAndNil(FData);
  FData:= CollectMemberAccess(FIndex, FStore, pTarget, pMode, pCap);
end;

{ The text of the refusal CollectMemberAccess raises for pTarget; '' when it raises nothing. }
function TMemberAccessDataTests.RefusalOf(const pTarget: string): string;
begin
  Result:= '';
  try
    if not Collect(pTarget, MODE_WRITE, DEFAULT_CAP) then
      Result:= '<clone missing>';
  except
    on E: EChartsIndex do Result:= E.Message;
  end;
end;

procedure TMemberAccessDataTests.TearDown;
begin
  FreeAndNil(FData);
  FreeAndNil(FIndex);
  FStore:= nil;
end;

procedure TMemberAccessDataTests.RFieldBothWings;
begin
  if not Collect(R_QNAME, MODE_BOTH, DEFAULT_CAP) then Exit;
  Assert.AreEqual('field', FData.Sel.Kind);
  Assert.AreEqual(R_WRITES, FData.TotalWrites);
  Assert.AreEqual(R_READS, FData.TotalReads);
  Assert.AreEqual(R_ROUTINES, FData.DistinctRoutines);
  Assert.AreEqual(R_SITES, FData.TotalSites);
  Assert.AreEqual(R_SHOWN_WRITERS, Integer(Length(FData.WTop.Shown)));
  Assert.AreEqual(R_SHOWN_READERS, Integer(Length(FData.RTop.Shown)));
  Assert.AreEqual(0, FData.WTop.HiddenRows + FData.RTop.HiddenRows);
  Assert.AreEqual('agree', FData.CrossCheck);
  Assert.AreEqual(0, FData.WU.Same);
  Assert.AreEqual(R_ELSEWHERE_WRITES, FData.WU.Elsewhere);
  { a site is a line AND a column: three accesses on one line stay three facts }
  var Reads:= FData.SitesOf(R_DRAW_SAMPLE, MODE_READ);
  var Writes:= FData.SitesOf(R_DRAW_SAMPLE, MODE_WRITE);
  Assert.AreEqual(2, Integer(Length(Reads)));
  Assert.AreEqual(R_DRAW_SAMPLE_WRITES, Integer(Length(Writes)));
  Assert.AreEqual(R_LINE, Reads[0].Line);
  Assert.AreEqual(R_COL_READ_1, Reads[0].Col);
  Assert.AreEqual(R_LINE, Reads[1].Line);
  Assert.AreEqual(R_COL_READ_2, Reads[1].Col);
  Assert.AreEqual(R_LINE, Writes[0].Line);
  Assert.AreEqual(R_COL_WRITE, Writes[0].Col);
end;

procedure TMemberAccessDataTests.VerdictPropertyNamesItsAccessors;
begin
  if not Collect(VERDICT_QNAME, MODE_BOTH, DEFAULT_CAP) then Exit;
  Assert.AreEqual('property', FData.Sel.Kind);
  Assert.AreEqual(VERDICT_WRITES, FData.TotalWrites);
  Assert.AreEqual(VERDICT_READS, FData.TotalReads);
  Assert.AreEqual(VERDICT_ROUTINES, FData.DistinctRoutines);
  Assert.AreEqual(VERDICT_SITES, FData.TotalSites);
  Assert.AreEqual('agree', FData.CrossCheck);
  Assert.AreEqual(2, Integer(Length(FData.Backing)));
  Assert.AreEqual('GetVERDICT', FData.Backing[0].Name);
  Assert.AreEqual('method', FData.Backing[0].Kind);
  Assert.AreEqual('SetVERDICT', FData.Backing[1].Name);
  Assert.AreEqual('method', FData.Backing[1].Kind);
  Assert.AreEqual(0, FData.WU.Total);
  Assert.AreEqual(0, FData.RU.Total);
end;

procedure TMemberAccessDataTests.FConnectedWritesAnchorEverySite;
begin
  if not Collect(FCONN_QNAME, MODE_WRITE, DEFAULT_CAP) then Exit;
  Assert.AreEqual(FCONN_WRITES, FData.TotalWrites);
  Assert.AreEqual(FCONN_ROUTINES, FData.DistinctRoutines);
  Assert.AreEqual('agree', FData.CrossCheck);
  var Sites:= FData.SitesOf(FCONN_CONNECT, MODE_WRITE);
  Assert.AreEqual(2, Integer(Length(Sites)));
  Assert.AreEqual(FCONN_LINE_1, Sites[0].Line);
  Assert.AreEqual(FCONN_COL, Sites[0].Col);
  Assert.AreEqual(FCONN_LINE_2, Sites[1].Line);
  Assert.AreEqual(FCONN_COL, Sites[1].Col);
  Assert.AreEqual(FCONN_READS_SAME, FData.RU.Same);
  Assert.AreEqual(0, FData.RU.Elsewhere);
  Assert.AreEqual(FCONN_READ_COUNT_TEXT, FormatAccessCount(FCONN_READ_COUNT, FData.RU, FData.Sel));
  Assert.AreEqual('', FData.CountLabel(FData.WU));
end;

procedure TMemberAccessDataTests.FNoRecursionReadsAreUnbound;
begin
  if not Collect(NOREC_QNAME, MODE_READ, DEFAULT_CAP) then Exit;
  Assert.AreEqual(NOREC_WRITES, FData.TotalWrites);
  Assert.AreEqual(0, FData.TotalReads);
  Assert.AreEqual(0, FData.DistinctRoutines);
  Assert.IsFalse(FData.ShowWrite);
  Assert.IsTrue(FData.ShowRead);
  Assert.AreEqual(0, FData.WU.Total);
  Assert.AreEqual(NOREC_READS_SAME, FData.RU.Same);
  Assert.AreEqual(0, FData.RU.Elsewhere);
  Assert.AreEqual(NOREC_READ_LINES, string.Join(',', FData.RU.SameLines));
  Assert.AreEqual(NOREC_ZERO_NOTE, ZeroNote(MODE_READ, FData.RU, NOREC_WRITES, FData.WU, FData.Sel));
  Assert.AreEqual(NOREC_READS_LABEL, FData.CountLabel(FData.RU));
  Assert.AreEqual(NOREC_ROUTINES_LABEL, FData.RoutinesLabel);
  Assert.AreEqual('', FData.CountLabel(FData.WU));
end;

procedure TMemberAccessDataTests.FLotsizeWithBodyWriteIsByName;
begin
  if not Collect(LOT_QNAME, MODE_WRITE, DEFAULT_CAP) then Exit;
  Assert.AreEqual(LOT_WRITES, FData.TotalWrites);
  Assert.AreEqual(1, FData.WU.Same);
  Assert.AreEqual(1, Integer(Length(FData.WU.SameLines)));
  Assert.AreEqual(LOT_LINE, FData.WU.SameLines[0]);
  Assert.AreEqual('agree', FData.CrossCheck);
end;

procedure TMemberAccessDataTests.ResultZeroNoteNamesEveryPopulation;
begin
  if not Collect(RESULT_QNAME, MODE_WRITE, DEFAULT_CAP) then Exit;
  Assert.AreEqual(0, FData.TotalWrites);
  Assert.AreEqual(RESULT_WRITES_SAME, FData.WU.Same);
  Assert.AreEqual(RESULT_WRITES_ELSEWHERE, FData.WU.Elsewhere);
  Assert.AreEqual(0, FData.RU.Same);
  Assert.AreEqual(RESULT_READS_ELSEWHERE, FData.RU.Elsewhere);
  Assert.AreEqual(RESULT_ZERO_NOTE, ZeroNote(MODE_WRITE, FData.WU, 0, FData.RU, FData.Sel));
  Assert.AreEqual(RESULT_WRITES_SAME, Integer(Length(FData.WU.SameLines)));
end;

procedure TMemberAccessDataTests.ConnectedReadsAreCapped;
begin
  if not Collect(CONN_QNAME, MODE_READ, CAP_25) then Exit;
  Assert.AreEqual('property', FData.Sel.Kind);
  Assert.AreEqual(CONN_READS, FData.TotalReads);
  Assert.AreEqual(CONN_ROUTINES, FData.DistinctRoutines);
  Assert.AreEqual(CAP_25, Integer(Length(FData.RTop.Shown)));
  Assert.AreEqual(CONN_HIDDEN_ROUTINES, FData.RTop.HiddenRows);
  Assert.AreEqual(CONN_HIDDEN_SITES, FData.RTop.HiddenSites);
  Assert.AreEqual('agree', FData.CrossCheck);
  Assert.AreEqual(1, Integer(Length(FData.Backing)));
  Assert.AreEqual('FConnected', FData.Backing[0].Name);
  Assert.AreEqual('field', FData.Backing[0].Kind);
end;

procedure TMemberAccessDataTests.MethodIsRefused;
begin
  var Msg:= RefusalOf(METHOD_QNAME);
  if Msg = '<clone missing>' then Exit;
  Assert.AreEqual(METHOD_QNAME + ' is a method, not a field or property -- ask who-calls instead', Msg);
end;

procedure TMemberAccessDataTests.MissingIsRefused;
begin
  var Msg:= RefusalOf('No.Such.Field');
  if Msg = '<clone missing>' then Exit;
  Assert.AreEqual('No.Such.Field is not in this index', Msg);
end;

procedure TMemberAccessDataTests.AmbiguousIsRefused;
begin
  var Msg:= RefusalOf(AMBIGUOUS_NAME);
  if Msg = '<clone missing>' then Exit;
  Assert.StartsWith(AMBIGUOUS_NAME + ' is ambiguous -- ', Msg);
  Assert.Contains(Msg, ' symbols share that name: ');
end;

procedure TMemberAccessDataTests.UnknownModeIsRefused;
begin
  var Clone:= FindUp(CLONE_REL);
  if Clone = '' then
  begin
    Assert.Pass('clone missing');
    Exit;
  end;
  var Msg:= '';
  try
    Collect(R_QNAME, 'sideways', DEFAULT_CAP);
  except
    on E: EChartsQuestion do Msg:= E.Message;
  end;
  Assert.AreEqual('sideways is not a mode', Msg);
end;

procedure TMemberAccessDataTests.SortIsThePowerShellOrder;
begin
  if not Collect(R_QNAME, MODE_BOTH, DEFAULT_CAP) then Exit;
  { Sites descending, then CompareGroupKeys: the three 2-site readers tie and are decided by name }
  Assert.AreEqual(R_SHOWN_READERS, Integer(Length(FData.RTop.Shown)));
  Assert.AreEqual('BASICSF.DrawSampleChartHoriz', FData.RTop.Shown[0].Routine);
  Assert.AreEqual('BASICSF.DrawChartCol', FData.RTop.Shown[1].Routine);
  Assert.AreEqual('BASICSF.DrawChartColSampleRec', FData.RTop.Shown[2].Routine);
  Assert.AreEqual(R_DRAW_SAMPLE, FData.RTop.Shown[R_SHOWN_READERS - 1].Routine);
  Assert.AreEqual(R_SHOWN_WRITERS, Integer(Length(FData.WTop.Shown)));
  Assert.AreEqual(R_DRAW_SAMPLE, FData.WTop.Shown[0].Routine);
  Assert.AreEqual('BASICSF.DrawChartCol', FData.WTop.Shown[1].Routine);
  Assert.AreEqual('BASICSF.DrawChartColSampleRec', FData.WTop.Shown[2].Routine);
end;

end.
