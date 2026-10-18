unit ChartsTests.CoreTraceChart;

(* Cases for DRagLint.Charts.Trace.Chart, the round-trip chart (a port of charts\src\Trace.Chart.ps1).
  The expected dot hashes, node / lane / merged / unlinked / shortened totals and Legend rows are what
  ConvertTo-TraceChart printed for the same trace text and anchor-path map (task-7-harvest.md of the d1
  ledger; the h1..h6 shas equal the bundles' graph.dot of Task 1). The renderer is a pure function of
  the Form A text, so the cases read only the committed fixtures under tests\charts\fixtures\roundtrip
  (the repo root is DRAGLINT_REPO_ROOT, else the first parent of the working directory holding them)
  or build a synthetic model in memory. *)

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TCoreTraceChartTests = class
  public
    [Test] procedure HoldoutDotMatchesPowerShell;
    [Test] procedure GoldenDotMatchesPowerShell;
    [Test] procedure CalcDotHasTheDerivedCard;
    [Test] procedure OneStepTraceIsOneNode;
    [Test] procedure OperatAndTFieldDotsMatchPowerShell;
    [Test] procedure DotFromTextEqualsDotFromModel;
    [Test] procedure FoldLadderIsNeverSilent;
    [Test] procedure SmallFoldsKeepOneLegendRowEach;
    [Test] procedure ChartBreaksAreGreedyAndVerbatim;
    [Test] procedure FormatChartNumbersFoldsRuns;
    [Test] procedure UnknownSectionThrows;
    [Test] procedure ActorOutsideTiersThrows;
    [Test] procedure UnnumberedItemThrows;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, System.Hash, System.Generics.Collections, DRagLint.Charts.Trace.FormA,
  DRagLint.Charts.Trace.Chart;

const
  REPO_ROOT_ENV = 'DRAGLINT_REPO_ROOT';
  FIXTURE_DIR = 'tests\charts\fixtures\roundtrip\';
  CRLF = #13#10;
  TIERS = 'client -> pipe -> server -> database';
  H1_LEAF = 'frmBlueprint4_dxDBGrid1FtrsVNum';
  H2_LEAF = 'frmBlueprint4_dxDBGrid1OperationVName';
  H3_LEAF = 'frmBlueprint4_dxDBGrid1FtrsVFtrName';
  H4_LEAF = 'frmBlueprint4_cxGroupBox16';
  H5_LEAF = 'OPERAT_NAME';
  H6_LEAF = 'Blueprint4_ViewModel_TBlueprint_ViewModel_FfFtrs_USLLSLName';
  H1_SHA = 'a70c3f3555e20a9e7561c73dc64a8e0f3a5845638813c9f8c03620e70ab01425';
  H2_SHA = 'a143756bd8c829dc430331b01b2ed2a552eae13e5b92d3f4a8db8d4fb6a78b49';
  H3_SHA = '3979eeb73a0c4da49393086efa8254f0c5bc3e2692da86f2c52e418bc9347c87';
  H4_SHA = '5145dd9668917a8f628bd8d72f688a9f6f39147507f2b9d4b104cf7b260274fb';
  H5_SHA = 'b9ad423fbeca30bc3dcdb83a345437c79c449091a08bb0fd1a19e4d8cc371f78';
  H6_SHA = '175f77161b0df988485d95c09059c931c0c554bcd29d3a727076ac0a339047e0';
  SUM_SHA = '3e0395c374e40b220b9cc283f9ca317224f80f0332849490dc4a6d9304a35378';
  SUMC_SHA = '90425338adef5bb26fe3db487f9efc5d98355dbf4f2dd259bb5b79884b5f63a4';
  F6_SHA = '5a456787aa4e6584d7103f5236ebce5f665f0401e79c22e5475d623f378e1628';
  F5_SHA = '54051ed3293690bc1e3c2ad32c8d41e167c43677469deadb4b883e29b128c27c';
  H1_MERGED = '[09]/[64],[20]/[54],[21]/[55],[22]/[56],[23]/[57],[24]/[58]';
  H2_MERGED = '[09]/[60],[20]/[50],[21]/[51],[22]/[52],[23]/[53],[24]/[54]';
  H1_COLLAPSE = '+17 more routes not shown in ALSO -- [87]-[103], full text in trace.dlgraph';
  H3_COLLAPSE = '+4 more steps not shown in DERIVED -- the fields the calculation reads -- [24]-[27], full text in trace.dlgraph';
  SUM_ROW = '100 cards folded (300 rows not shown) -- [01]-[300] -- the full trace is in the text answer';
  SUMC_ROW = '60 cards folded (180 rows not shown) -- 180 steps -- the full trace is in the text answer';
  F6_ROW = '6 cards folded (18 rows not shown) -- 18 steps -- the full trace is in the text answer';
  CLIENT_DIR = 'C:\Projects\DB\ORM3\CLIENT\';  // dl:ok hardcoded-absolute-path@d23c -- REVIEWED 2026-10-18: a map VALUE of the PowerShell emitter's anchor-path table (the harvest's text), only formatted into links, never opened
  COMMON_DIR = 'C:\Projects\DB\ORM3\COMMON\';  // dl:ok hardcoded-absolute-path@33c4 -- REVIEWED 2026-10-18: a map VALUE of the PowerShell emitter's anchor-path table (the harvest's text), only formatted into links, never opened
  SERVER_DIR = 'C:\Projects\DB\ORM3\SERVER\';  // dl:ok hardcoded-absolute-path@a1aa -- REVIEWED 2026-10-18: a map VALUE of the PowerShell emitter's anchor-path table (the harvest's text), only formatted into links, never opened
  SQL_DIR = 'C:\Projects\DB\SQL\';  // dl:ok hardcoded-absolute-path@0428 -- REVIEWED 2026-10-18: a map VALUE of the PowerShell emitter's anchor-path table (the harvest's text), only formatted into links, never opened
  ANCHOR_STRIDE = 10;
  SYN_ROWS = 3;
  H2_STEPS = 76;
  H5_STEPS = 1;
  H6_STEPS = 10;
  CUT_LAST_FIT = 9;
  CUT_AFTER_WIDTH = 10;
  CUT_LONG_TOKEN = 20;
  FONT_SIZE = 11;
  RUN_INPUT: array[0..4] of Integer = (80, 74, 75, 76, 75);
  PAIR_INPUT: array[0..1] of Integer = (10, 9);
  NOT_WALKED = '-- not walked: the trace stopped at [01]';
  SUM_ROUTINES = 100;
  SUMC_ROUTINES = 120;
  F6_ROUTINES = 6;
  F5_ROUTINES = 5;
  SUM_STEPS = 300;
  H1_STEPS = 103;
  SIX_SECTIONS = 6;
  FOLD_ROW_CAP = 2;
  FIVE_FOLDS = 5;
  H1_NODES = 25;
  H2_NODES = 24;
  H3_NODES = 3;
  H6_NODES = 3;
  H1_SHORTENED = 2;
  HEAD_TEXT_LEN = 7;
  BREAK_WIDTH = 10;
  NARROW_WIDTH = 8;
  H1_LANES = '7/2/13/3';
  H2_LANES = '7/2/12/3';
  H3_LANES = '3/0/0/0';
  ONE_LANE = '1/0/0/0';
  H1_FOLD_TOTAL = 17;

type
  TFx = (fxH1, fxH2, fxH3, fxH4, fxH5, fxH6);
  TFxWant = record
    Sha      : string;
    Nodes    : Integer;
    Lanes    : string;
    Merged   : string;
    Shortened: Integer;
    Steps    : Integer;
  end;

function FindUp(const pRel: string): string;
begin
  Result:= '';
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
end;

function FixtureText(const pLeaf: string): string;
begin
  var Path:= FindUp(FIXTURE_DIR + pLeaf + '.dlgraph');
  Assert.IsTrue(Path <> '', 'fixture ' + pLeaf + ' not found under the repo root');
  Result:= TFile.ReadAllText(Path, TEncoding.ASCII);
end;

function Sha(const pDot: string): string;
begin
  Result:= LowerCase(THashSHA2.GetHashString(pDot, THashSHA2.TSHA2Version.SHA256));
end;

procedure CheckCount(pExpected: NativeInt; pActual: NativeInt; const pMsg: string = '');
begin
  Assert.IsTrue(pExpected = pActual, pMsg + ' (expected ' + IntToStr(pExpected) + ', got ' + IntToStr(pActual) + ')');
end;

{ the anchor-path maps the PowerShell emitter built (task-1-harvest.md, per fixture) }
function MapOf(pFx: TFx): TDictionary<string, string>;
begin
  Result:= TDictionary<string, string>.Create;
  if pFx = fxH5 then
    Result.Add('AssignGroups.ViewModel.pas', CLIENT_DIR + 'AssignGroups.ViewModel.pas')
  else if pFx = fxH6 then
    Result.Add('Blueprint4.ViewModel.pas', CLIENT_DIR + 'Blueprint4.ViewModel.pas')
  else if pFx = fxH4 then
    Result.Add('Blueprint4.dfm', CLIENT_DIR + 'Blueprint4.dfm')
  else
    for var Leaf in ['Blueprint4.dfm', 'Blueprint4.Interfaces.pas', 'Blueprint4.pas', 'Blueprint4.ViewModel.pas'] do
      Result.Add(Leaf, CLIENT_DIR + Leaf);
  if pFx = fxH3 then
    Result.Add('MSCTYPES.PAS', COMMON_DIR + 'MSCTYPES.PAS');
  if (pFx = fxH1) or (pFx = fxH2) then
  begin
    Result.Add('MS1.SQL', SQL_DIR + 'MS1.SQL');
    Result.Add('Pipes.Commands.pas', COMMON_DIR + 'Pipes.Commands.pas');
    Result.Add('Pipes.Protocol.pas', COMMON_DIR + 'Pipes.Protocol.pas');
    Result.Add('uBroadcastServer.pas', SERVER_DIR + 'uBroadcastServer.pas');
    Result.Add('uDatasetsDef.pas', SERVER_DIR + 'uDatasetsDef.pas');
    Result.Add('uGenericTableRoute.pas', SERVER_DIR + 'uGenericTableRoute.pas');
    Result.Add('uPipeClientConnection.pas', CLIENT_DIR + 'uPipeClientConnection.pas');
    Result.Add('uPipeSessionBuilder.pas', SERVER_DIR + 'uPipeSessionBuilder.pas');
  end;
end;

{ one fixture through the renderer; the manifest is returned for the caller to check and free }
function Render(const pLeaf: string; pFx: TFx; out pManifest: TChartManifest): string;
begin
  var Trace:= ReadFormA(FixtureText(pLeaf));
  var Map:= MapOf(pFx);
  try
    var Chart:= TraceChart(Trace, Map, TChartCaps.Default);
    Result:= Chart.Dot;
    pManifest:= Chart.Manifest;
  finally
    Map.Free;
    Trace.Free;
  end;
end;

procedure CheckTotals(const pManifest: TChartManifest; const pWant: TFxWant);
begin
  Assert.AreEqual(pWant.Nodes, pManifest.Nodes, 'Nodes');
  Assert.AreEqual(pWant.Lanes, pManifest.Lanes, 'Lanes');
  Assert.AreEqual(pWant.Merged, pManifest.Merged, 'Merged');
  Assert.AreEqual(0, pManifest.Unlinked, 'Unlinked');
  Assert.AreEqual(pWant.Shortened, pManifest.Shortened, 'Shortened');
  Assert.AreEqual('', pManifest.Ladder, 'Ladder');
end;

{ ReadFormA(h) -> chart, checking the sha and the totals }
procedure CheckFixture(const pLeaf: string; pFx: TFx; const pWant: TFxWant);
begin
  var Manifest: TChartManifest;
  var Dot:= Render(pLeaf, pFx, Manifest);
  try
    Assert.AreEqual(pWant.Sha, Sha(Dot), pLeaf + ' dot sha256');
    CheckTotals(Manifest, pWant);
    CheckCount(pWant.Steps, Manifest.Steps.Count, pLeaf + ' every step is placed');
  finally
    Manifest.Free;
  end;
end;

function Want(const pSha: string; pNodes: Integer; const pLanes, pMerged: string; pShortened, pSteps: Integer): TFxWant;
begin
  Result.Sha:= pSha;
  Result.Nodes:= pNodes;
  Result.Lanes:= pLanes;
  Result.Merged:= pMerged;
  Result.Shortened:= pShortened;
  Result.Steps:= pSteps;
end;

function Nums(const pNums: array of Integer): TArray<Integer>;
begin
  SetLength(Result, Length(pNums));
  for var I:= 0 to High(pNums) do
    Result[I]:= pNums[I];
end;

{ the synthetic size traces of Test-RoundTripHelpers.ps1 (New-SynthSizeTrace): routine q holds pRows(q) steps }
function SynthTrace(const pName: string; pRoutines: Integer; const pRows: TFunc<Integer, Integer>): TTrace;
begin
  Result:= NewTrace(pName, 'a synthetic trace (' + pName + ')', 'X.Y', 'A', '2026-10-06', 'x', TIERS);
  var Sec:= AddTraceSection(Result, 'WRITE');
  for var Q:= 1 to pRoutines do
  begin
    Sec.Items.Add(NewTraceStep('step', 'CALLS TSyn.R' + IntToStr(Q), 'uSyn.pas:' + IntToStr(Q * ANCHOR_STRIDE), '',
      'TSyn.R' + IntToStr(Q - 1)));
    for var J:= 2 to pRows(Q) do
      Sec.Items.Add(NewTraceStep('step', 'READS F' + IntToStr(Q) + 'x' + IntToStr(J),
        'uSyn.pas:' + IntToStr(Q * ANCHOR_STRIDE + J), '', 'TSyn.R' + IntToStr(Q)));
  end;
  WriteFormA(Result);
end;

function Synth(const pName: string; pRoutines: Integer; pRowsEach: Integer; pCaps: TChartCaps;
  out pManifest: TChartManifest; pAlternate: Boolean = False): string;
begin
  var Trace:= SynthTrace(pName, pRoutines, function(pQ: Integer): Integer
    begin
      Result:= if pAlternate and (pQ mod 2 = 0) then pRowsEach - 1 else pRowsEach;
    end);
  try
    var Chart:= TraceChart(Trace, nil, pCaps);
    Result:= Chart.Dot;
    pManifest:= Chart.Manifest;
  finally
    Trace.Free;
  end;
end;

function CountOf(const pNeedle, pHay: string): Integer;
begin
  Result:= 0;
  var At:= Pos(pNeedle, pHay);
  while At > 0 do
  begin
    Inc(Result);
    At:= Pos(pNeedle, pHay, At + Length(pNeedle));
  end;
end;

function Raised(const pProc: TProc): string;
begin
  Result:= '';
  try
    pProc();
  except
    on E: EChartsTrace do
      Result:= E.Message;
  end;
end;

{ TCoreTraceChartTests }

procedure TCoreTraceChartTests.HoldoutDotMatchesPowerShell;
begin
  var Manifest: TChartManifest;
  var Dot:= Render(H1_LEAF, fxH1, Manifest);
  try
    Assert.AreEqual(H1_SHA, Sha(Dot), 'h1 dot sha256');
    CheckTotals(Manifest, Want(H1_SHA, H1_NODES, H1_LANES, H1_MERGED, H1_SHORTENED, H1_STEPS));
    CheckCount(H1_STEPS, Manifest.Steps.Count, 'every one of the 103 steps is placed');
    CheckCount(1, Manifest.Collapses.Count, 'one fold');
    Assert.AreEqual(H1_COLLAPSE, Manifest.Collapses[0], 'the ALSO fold row');
    var Disclosed:= 0;
    for var V in Manifest.Steps.Values do
      if V.StartsWith('disclosed:') then
        Inc(Disclosed);
    Assert.AreEqual(H1_FOLD_TOTAL, Disclosed, 'the 17 folded steps are disclosed, the rest drawn');
    Assert.AreEqual(1, CountOf('converges outside the drawn path', Dot), 'the one ALSO row with no card');
  finally
    Manifest.Free;
  end;
end;

procedure TCoreTraceChartTests.GoldenDotMatchesPowerShell;
begin
  CheckFixture(H2_LEAF, fxH2, Want(H2_SHA, H2_NODES, H2_LANES, H2_MERGED, H1_SHORTENED, H2_STEPS));
end;

procedure TCoreTraceChartTests.CalcDotHasTheDerivedCard;
begin
  var Manifest: TChartManifest;
  var Dot:= Render(H3_LEAF, fxH3, Manifest);
  try
    Assert.AreEqual(H3_SHA, Sha(Dot), 'h3 dot sha256');
    CheckTotals(Manifest, Want(H3_SHA, H3_NODES, H3_LANES, '', 0, 0));
    Assert.IsTrue(Pos('DERIVED -- the fields the calculation reads', Dot) > 0, 'the DERIVED card title');
    CheckCount(1, Manifest.Collapses.Count);
    Assert.AreEqual(H3_COLLAPSE, Manifest.Collapses[0], 'the DERIVED row cap fold');
  finally
    Manifest.Free;
  end;
end;

procedure TCoreTraceChartTests.OneStepTraceIsOneNode;
begin
  var Manifest: TChartManifest;
  var Dot:= Render(H4_LEAF, fxH4, Manifest);
  try
    Assert.AreEqual(H4_SHA, Sha(Dot), 'h4 dot sha256');
    CheckTotals(Manifest, Want(H4_SHA, 1, ONE_LANE, '', 0, 1));
    Assert.AreEqual(SIX_SECTIONS, CountOf(NOT_WALKED, Dot), 'the Legend names the six not-walked sections');
    Assert.AreEqual('drawn:n1:p1', Manifest.Steps['1']);
  finally
    Manifest.Free;
  end;
end;

procedure TCoreTraceChartTests.OperatAndTFieldDotsMatchPowerShell;
begin
  CheckFixture(H5_LEAF, fxH5, Want(H5_SHA, 1, ONE_LANE, '', 1, H5_STEPS));
  CheckFixture(H6_LEAF, fxH6, Want(H6_SHA, H6_NODES, H3_LANES, '', 0, H6_STEPS));
end;

procedure TCoreTraceChartTests.DotFromTextEqualsDotFromModel;
begin
  // A-R5-FROMTEXT: the chart of the text read back equals the chart of the numbered model
  var Model:= SynthTrace('SYN.F5', F5_ROUTINES, function(pQ: Integer): Integer
    begin
      Result:= F5_ROUTINES;
    end);
  var Text:= WriteFormA(Model);
  var Read:= ReadFormA(Text);
  var Caps:= TChartCaps.Default;
  Caps.Rows:= FOLD_ROW_CAP;
  try
    var A:= TraceChart(Model, nil, Caps);
    var B:= TraceChart(Read, nil, Caps);
    try
      Assert.AreEqual(A.Dot, B.Dot, 'model vs text');
      Assert.AreEqual(F5_SHA, Sha(A.Dot), 'f5 dot sha256');
    finally
      B.Manifest.Free;
      A.Manifest.Free;
    end;
  finally
    Read.Free;
    Model.Free;
  end;
end;

procedure TCoreTraceChartTests.FoldLadderIsNeverSilent;
begin
  var Manifest: TChartManifest;
  var Dot:= Synth('SYN.SUM', SUM_ROUTINES, SYN_ROWS, TChartCaps.Default, Manifest);
  try
    Assert.AreEqual(SUM_SHA, Sha(Dot), 'sum dot sha256');
    Assert.AreEqual('cards', Manifest.Ladder, 'the ladder folded the cards');
    CheckCount(1, Manifest.Collapses.Count, 'one summary row replaces 100 fold rows');
    Assert.AreEqual(SUM_ROW, Manifest.Collapses[0]);
    Assert.IsTrue(Pos('100 nodes, above the 45-node readability cap: drawn anyway, nothing dropped', Dot) > 0,
      'the cap row');
    CheckCount(SUM_STEPS, Manifest.Steps.Count);
    for var V in Manifest.Steps.Values do
      Assert.AreEqual('disclosed:' + SUM_ROW, V, 'every step names the summary row');
  finally
    Manifest.Free;
  end;
  Dot:= Synth('SYN.SUMC', SUMC_ROUTINES, SYN_ROWS, TChartCaps.Default, Manifest, True);
  try
    Assert.AreEqual(SUMC_SHA, Sha(Dot), 'sumc dot sha256');
    Assert.AreEqual(SUMC_ROW, Manifest.Collapses[0], 'ranges do not fit one row: the count');
  finally
    Manifest.Free;
  end;
end;

procedure TCoreTraceChartTests.SmallFoldsKeepOneLegendRowEach;
begin
  var Caps:= TChartCaps.Default;
  Caps.Rows:= FOLD_ROW_CAP;
  var Manifest: TChartManifest;
  var Dot:= Synth('SYN.F5', F5_ROUTINES, F5_ROUTINES, Caps, Manifest);
  try
    Assert.AreEqual(F5_SHA, Sha(Dot), 'f5 dot sha256');
    CheckCount(FIVE_FOLDS, Manifest.Collapses.Count, 'five folds: one row each');
    Assert.AreEqual('+3 more steps not shown in TSyn.R1 -- [03]-[05], full text in trace.dlgraph', Manifest.Collapses[0]);
  finally
    Manifest.Free;
  end;
  Dot:= Synth('SYN.F6', F6_ROUTINES, F5_ROUTINES, Caps, Manifest);
  try
    Assert.AreEqual(F6_SHA, Sha(Dot), 'f6 dot sha256');
    CheckCount(1, Manifest.Collapses.Count, 'six folds: one summary row');
    Assert.AreEqual(F6_ROW, Manifest.Collapses[0]);
  finally
    Manifest.Free;
  end;
end;

procedure TCoreTraceChartTests.ChartBreaksAreGreedyAndVerbatim;
begin
  CheckCount(0, Length(ChartBreaks('short text', BREAK_WIDTH + 1)), 'within the width: no break');
  var B:= ChartBreaks('aaaa bbbb cccc dddd', BREAK_WIDTH);
  CheckCount(1, Length(B));
  Assert.AreEqual(CUT_LAST_FIT, B[0], 'the last breakable space inside the width');
  // two spaces are kept: a space beside another space is not breakable
  B:= ChartBreaks('aaaa  bbbb cccc', NARROW_WIDTH);
  CheckCount(1, Length(B));
  Assert.AreEqual(CUT_AFTER_WIDTH, B[0], 'the first single space after the width');
  // a token longer than the width stays whole
  B:= ChartBreaks('aaaaaaaaaaaaaaaaaaaa bb', BREAK_WIDTH);
  CheckCount(1, Length(B));
  Assert.AreEqual(CUT_LONG_TOKEN, B[0]);
  var Html:= ChartCellHtml([TChartSeg.Make('ab  cd ef', '#000000', 0, False)], HEAD_TEXT_LEN);
  Assert.AreEqual('<FONT COLOR="#000000">ab  cd<BR ALIGN="LEFT"/>ef</FONT>', Html, 'two spaces survive, the break is a BR');
  Assert.AreEqual('<FONT POINT-SIZE="11"><B>x &amp; y</B></FONT>',
    ChartCellHtml([TChartSeg.Make('', '#111111', 0, False), TChartSeg.Make('x & y', '', FONT_SIZE, True)]), 'empty run skipped');
end;

procedure TCoreTraceChartTests.FormatChartNumbersFoldsRuns;
begin
  Assert.AreEqual('[74]-[76], [80]', FormatChartNumbers(Nums(RUN_INPUT)));
  Assert.AreEqual('[01]', FormatChartNumbers(Nums([1])));
  Assert.AreEqual('[09]-[10]', FormatChartNumbers(Nums(PAIR_INPUT)));
  Assert.AreEqual('', FormatChartNumbers(nil));
end;

procedure TCoreTraceChartTests.UnknownSectionThrows;
begin
  var T:= NewTrace('U', 'u', 'x', 'A', '2026-10-06', 'x', 'client');
  try
    AddTraceSection(T, 'LATER').Items.Add(NewTraceStep('step', 'CALLS X', 'X.pas:1'));
    WriteFormA(T);
    var Msg:= Raised(procedure begin TraceChart(T, nil, TChartCaps.Default).Manifest.Free; end);
    Assert.AreEqual('ConvertTo-TraceChart: unknown section ''LATER'' -- a grammar that grows must grow the renderer (R19)', Msg);
  finally
    T.Free;
  end;
end;

procedure TCoreTraceChartTests.ActorOutsideTiersThrows;
begin
  var T:= NewTrace('U', 'u', 'x', 'A', '2026-10-06', 'x', 'client -> pipe');
  try
    AddTraceSection(T, 'READ').Items.Add(NewTraceStep('step', 'CALLS X', 'X.pas:1', '', '', '', '', 'SERVER'));
    WriteFormA(T);
    var Msg:= Raised(procedure begin TraceChart(T, nil, TChartCaps.Default).Manifest.Free; end);
    Assert.AreEqual('ConvertTo-TraceChart: step [01] belongs in lane SERVER, which the TIERS header (CLIENT -> PIPE) does not name (R19)',
      Msg);
  finally
    T.Free;
  end;
end;

procedure TCoreTraceChartTests.UnnumberedItemThrows;
begin
  var T:= NewTrace('U', 'u', 'x', 'A', '2026-10-06', 'x', 'client');
  try
    AddTraceSection(T, 'WRITE').Items.Add(NewTraceStep('step', 'CALLS X', 'X.pas:1'));
    var Msg:= Raised(procedure begin TraceChart(T, nil, TChartCaps.Default).Manifest.Free; end);
    Assert.AreEqual('ConvertTo-TraceChart: an item has no step number -- render Read-FormA''s model, or the model after Write-FormA', Msg);
  finally
    T.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TCoreTraceChartTests);

end.
