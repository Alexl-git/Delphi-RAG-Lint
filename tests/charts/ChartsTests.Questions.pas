unit ChartsTests.Questions;

{ Cases for the ported chart questions (DRagLint.Charts.Q.*), each run in-process against
  its FROZEN clone under charts\scratch\db (never a live index; a missing clone passes with
  a note, as the other clone-backed fixtures do). Every expected value -- the emitter's
  counts, the sha256 of graph.dot, the answer lines -- was printed by the PowerShell
  question itself (Ask-Report.ps1 -Plain over New-DiagramArtifact.ps1 and the emitter) on
  2026-10-13 against the same clone (spec P3: the PS output is the reference). dot.exe runs:
  ResolveGraphvizDot finds it as the PS does. }

interface

uses
  DUnitX.TestFramework, DRagLint.Charts.Question;

type
  /// <summary>Shared setup: the repo, a scratch bundle root, a question's arguments.</summary>
  TQuestionFixture = class
  protected
    FOutRoot: string;
    function Args(const pQuestion, pTarget, pCloneName: string; out pArgs: TQuestionArgs): Boolean;
    function Fields(const pChart: TChartResult): string;
    function EmitChart(const pQuestion, pTarget, pCloneName: string; out pChart: TChartResult): Boolean;
    function Refusal(const pQuestion, pTarget, pCloneName: string): string;
    function Answer(const pQuestion, pTarget, pCloneName: string; out pLines: TArray<string>): Boolean;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
  end;

  [TestFixture]
  TTouchesTablesTests = class(TQuestionFixture)
  public
    [Test] procedure EmitterMatchesPowerShell;
    [Test] procedure AnswerMatchesPowerShell;
    [Test] procedure ClientIndexIsRefused;
  end;

  [TestFixture]
  TShownWhereTests = class(TQuestionFixture)
  private
    function Emit(const pColumn: string; out pChart: TChartResult): Boolean;
  public
    [Test] procedure FewFormsMatchPowerShell;
    [Test] procedure TiedFormsKeepSortObjectOrder;
    [Test] procedure CappedFormsMatchPowerShell;
    [Test] procedure AnswerMatchesPowerShell;
    [Test] procedure UnboundColumnIsRefused;
    [Test] procedure ServerIndexIsRefused;
  end;

  [TestFixture]
  TDepsTests = class(TQuestionFixture)
  private
    function Emit(const pUnit: string; out pChart: TChartResult): Boolean;
  public
    [Test] procedure UsesCappedMatchPowerShell;
    [Test] procedure UsersOverNineFoldersMatchPowerShell;
    [Test] procedure AnswerMatchesPowerShell;
  end;

  [TestFixture]
  TClassSurfaceTests = class(TQuestionFixture)
  public
    [Test] procedure EmitterMatchesPowerShell;
    [Test] procedure AnswerMatchesPowerShell;
    [Test] procedure UnitIsRefused;
  end;

  [TestFixture]
  TEventWiringTests = class(TQuestionFixture)
  public
    [Test] procedure EmitterMatchesPowerShell;
    [Test] procedure ControlFilterMatchesPowerShell;
    [Test] procedure AnswerMatchesPowerShell;
    [Test] procedure NonFormIsRefused;
  end;

  [TestFixture]
  TTestedByTests = class(TQuestionFixture)
  public
    [Test] procedure MethodMatchesPowerShell;
    [Test] procedure TypeSeedsItsMembers;
    [Test] procedure NoCoveringTestSaysSo;
    [Test] procedure AnswerMatchesPowerShell;
    [Test] procedure ProductIndexIsRefused;
  end;

  [TestFixture]
  TChangeImpactTests = class(TQuestionFixture)
  public
    [Test] procedure MethodMatchesPowerShell;
    [Test] procedure TypeSeedsMembersAndTypeUses;
    [Test] procedure CappedWalkMatchesPowerShell;
    [Test] procedure AnswerMatchesPowerShell;
    [Test] procedure LeafIsRefused;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, System.Hash, DRagLint.Charts.ReportHeader, DRagLint.Charts.Ask,
  DRagLint.Charts.Index, DRagLint.Charts.Q.TouchesTables, DRagLint.Charts.Q.ClassSurface;

const
  REPO_ROOT_ENV = 'DRAGLINT_REPO_ROOT';
  CHARTS_MARK = 'charts\src\Ask-Report.ps1';
  CLONE_DIR = 'charts\scratch\db';
  SERVER_CLONE = 'SERVER-MicroniteMW1Service.sqlite';
  CLIENT_CLONE = 'CLIENT-Micronite2027.sqlite';
  TT_TARGET = 'uPipeSessionBuilder.TPipeSessionBuilder.HandleCopyOperation';
  TT_FIELDS = 'Reads=5,Writes=5,Both=2,Distinct=8,Unresolved=0,IndexSqlSymbols=250,ClickTargets=11,Expected=11,AllClickable=true';
  TT_DOT_SHA = '01544eda433cfd8e44ad60c662e7f515dc54fe9561c4be0e4aa27d3b316b48b5';
  TT_ANCHORS = 11;
  TT_READS = 5;
  { the answer after the header sentence, with the BUNDLE line left out (it names the root) }
  TT_ANSWER =
    'COMMAND touches-tables -Target "uPipeSessionBuilder.TPipeSessionBuilder.HandleCopyOperation"|' +
    'INDEX <db>|' +
    'CHART touches-tables uPipeSessionBuilder.TPipeSessionBuilder.HandleCopyOperation -- 5 tables read / 5 tables written|' +
    '  TARGET uPipeSessionBuilder.TPipeSessionBuilder.HandleCopyOperation @uPipeSessionBuilder.pas:1381|' +
    '  COMPGRP (read) @uPipeSessionBuilder.pas:1600|' +
    '  DRA1 (read) @uPipeSessionBuilder.pas:1654|' +
    '  MSCLIST (read) @uPipeSessionBuilder.pas:1563|' +
    '  PROCPARO (read) @uPipeSessionBuilder.pas:1697|' +
    '  PROCPART (read) @uPipeSessionBuilder.pas:1700|' +
    '  DRA2 (written) @uPipeSessionBuilder.pas:1649|' +
    '  PROCPARO (written) @uPipeSessionBuilder.pas:1697|' +
    '  PROCPART (written) @uPipeSessionBuilder.pas:1700|' +
    '  TOOLASSG (written) @uPipeSessionBuilder.pas:1675|' +
    '  TOOLFLDR (written) @uPipeSessionBuilder.pas:1681';
  BUNDLE_LINE = 2;
  SHOWN_WHERE_ID = 'shown-where';
  SW_FEW = 'FTRNAMESTR';
  SW_FEW_FIELDS = 'Column="FTRNAMESTR",Bindings=4,Forms=2,Unresolved=0,IndexRows=903,IndexColumns=459,Clusters=3,ClickTargets=4,Expected=4,AllClickable=true';
  SW_FEW_DOT_SHA = 'de495b04d4817cb19b2ce5c315f53c30a930b6033829bf4287a899f881ac5442';
  { 18 forms: more than 16, so Sort-Object's introsort orders the tied counts }
  SW_TIED = 'NAME';
  SW_TIED_FIELDS = 'Column="NAME",Bindings=41,Forms=18,Unresolved=0,IndexRows=903,IndexColumns=459,Clusters=19,ClickTargets=41,Expected=41,AllClickable=true';
  SW_TIED_DOT_SHA = 'eab91899d8d38c53f500156850021b335a361633397c30cdebbff402b7f82269';
  { 25 forms over the cap of 20: five are disclosed in a 'not shown' cluster }
  SW_CAPPED = 'ID';
  SW_CAPPED_FIELDS = 'Column="ID",Bindings=72,Forms=25,Unresolved=0,IndexRows=903,IndexColumns=459,Clusters=22,ClickTargets=67,Expected=67,AllClickable=true';
  SW_CAPPED_DOT_SHA = '7747fbc6a62ee382da46687f980377b9ce0877d4447d0e7d3714a1bc58b18f58';
  DEPS_ID = 'deps';
  DL_CLONE = 'DL-drag-lint.sqlite';
  DEPS_CLI = 'DRagLint.CLI';
  DEPS_CLI_FIELDS = 'UsedBy=1,Uses=40,UsedByTotal=1,UsesTotal=110,UsedByHidden=0,UsesHidden=70,ImplementationUses=40,ClickTargets=41,Expected=41,AllClickable=true';
  DEPS_CLI_DOT_SHA = '5ef4c130d1c2eef9274c240970b42a9aa9b7f0ce88a045c40352aaff8b463846';
  { 68 users in nine folders: Group-Object Dir | Sort-Object Name orders the clusters }
  DEPS_MODEL = 'DRagLint.Core.Model';
  DEPS_MODEL_FIELDS = 'UsedBy=40,Uses=0,UsedByTotal=68,UsesTotal=0,UsedByHidden=28,UsesHidden=0,ImplementationUses=0,ClickTargets=40,Expected=40,AllClickable=true';
  DEPS_MODEL_DOT_SHA = '479e9a4e53c10963e604153ba5cbf67bcf3e0ca826cd782137d2bebbc6efd26b';
  DEPS_CLI_LINES = 47;
  CS_TARGET = 'Blueprint4.ViewModel.TBlueprint_ViewModel';
  { ByKind / ByVisibility sit between these two: nested objects, checked in ChartsTests.Question }
  CS_FIELDS_HEAD = 'Resolved="Blueprint4.ViewModel.TBlueprint_ViewModel",Kind="class",Members=392,ByKind={';
  CS_FIELDS_TAIL = 'Shown=24.0,Hidden=368.0,Clusters=2,ClickTargets=25,Expected=25.0,AllClickable=true';
  CS_DOT_SHA = '58ed8c4fc1489b24c8d85c5b455b5a7213c36db7d85585db3a3ca0e5f1135ed3';
  CS_LINES = 32;
  CS_CHART_LINE = 4;
  EVENT_WIRING_ID = 'event-wiring';
  EW_TARGET = 'uMain.TfrmMAIN';
  EW_FIELDS = 'Events=43,Handlers=43,Components=41,EventKinds=5,DfmResolved=43,DfmFallback=0,Edges=43,Clusters=6,ClickTargets=86,Expected=86,AllClickable=true';
  EW_DOT_SHA = 'fc3fe4545efeeb4b0fb872f21a0fe45480107ebb8bd025a86be300749f8a7074';
  EW_CONTROL = 'CauseList';
  EW_CONTROL_FIELDS = 'Events=1,Handlers=1,Components=1,EventKinds=1,DfmResolved=1,DfmFallback=0,Edges=1,Clusters=2,ClickTargets=2,Expected=2,AllClickable=true';
  EW_CONTROL_DOT_SHA = '42866c97d39012f0ad8a7bf28ac924f82e17304ce3ed7b556f4309cab8e878bb';
  EW_LINES = 86;
  EW_FIRST_ROW = 5;
  TESTED_BY_ID = 'tested-by';
  TESTS_CLONE = 'TESTS-MicroniteTests.sqlite';
  TB_TARGET = 'uCompGroupTree.TCompGroupTree.Build';
  TB_FIELDS = 'Qname="uCompGroupTree.TCompGroupTree.Build",Tests=11,Fixtures=1,TestMethods=71,Walked=11,MaxHop=1.0,Clusters=2,ClickTargets=12,Expected=12,AllClickable=true';
  TB_DOT_SHA = '01d8c52f4b6555a594ba34aaebb065dba3e84225feb5b084ea7d563a1828600a';
  TB_TYPE = 'uCompGroupTree.TCompGroupTree';
  TB_TYPE_FIELDS = 'Qname="uCompGroupTree.TCompGroupTree",Tests=13,Fixtures=1,TestMethods=71,Walked=13,MaxHop=1.0,Clusters=2,ClickTargets=14,Expected=14,AllClickable=true';
  TB_TYPE_DOT_SHA = '2b2174a8afb085a3be55df2e9ed1dbb6ee2cdc76efbec19d56d8500dac0e98eb';
  TB_NONE = 'Test.CompGroupTree.TCompGroupTreeTests.Flush_after_clean_build_is_noop';
  TB_NONE_FIELDS = 'Qname="Test.CompGroupTree.TCompGroupTreeTests.Flush_after_clean_build_is_noop",Tests=0,Fixtures=0,TestMethods=71,Walked=0,MaxHop=0,Clusters=2,ClickTargets=1,Expected=1,AllClickable=true';
  TB_NONE_DOT_SHA = '85218cabc300d99d88af6c8010d28a07edd1481dfcec1e2c7ceea7c536f30288';
  TB_LINES = 17;
  CHANGE_IMPACT_ID = 'change-impact';
  CI_TARGET = 'Blueprint4.ViewModel.TBlueprint_ViewModel.SendDeltaOperation';
  CI_FIELDS = 'Qname="Blueprint4.ViewModel.TBlueprint_ViewModel.SendDeltaOperation",IsType=false,Members=0,Affected=9,Units=1,Zones=1,MaxHop=1.0,Capped=false,Clusters=2,ClickTargets=9,Expected=9,AllClickable=true';
  CI_DOT_SHA = '3e57099569edc0120de83859f59c67700657c009449c52b6446bb45929a7a36a';
  CI_TYPE_FIELDS = 'Qname="Blueprint4.ViewModel.TBlueprint_ViewModel",IsType=true,Members=392,Affected=3,Units=3,Zones=1,MaxHop=2.0,Capped=false,Clusters=2,ClickTargets=4,Expected=4,AllClickable=true';
  CI_TYPE_DOT_SHA = '01aa6faa064198a807b62073f5f18aab2ae422244c1ab29e64b1c1b100a2823f';
  { 595 routines over the 400-node frontier cap, 175 units in two zones }
  CI_CAPPED = 'uPipeClientConnection.TPipeClientConnection.NextSeq';
  CI_CAPPED_FIELDS = 'Qname="uPipeClientConnection.TPipeClientConnection.NextSeq",IsType=false,Members=0,Affected=595,Units=175,Zones=2,MaxHop=2.0,Capped=true,Clusters=3,ClickTargets=11,Expected=11,AllClickable=true';
  CI_CAPPED_DOT_SHA = '0ca5bb5addfb872e94165e014e184facf1a2d5ebae74ec6c8a06f5fd59c5f019';
  CI_LINES = 15;
  DEPS_CHART_LINE = 4;
  DEPS_FIRST_ROW = 5;
  SW_ANSWER =
    'COMMAND shown-where -Target "FTRNAMESTR"|' +
    'INDEX <db>|' +
    'CHART shown-where FTRNAMESTR -- 4 data bindings / 2 forms|' +
    '  grdFtrsColFtrName.DataBinding.FieldName = ''FTRNAMESTR'' @AssignGroups.dfm:59|' +
    '  grdAssignedColFtrName.DataBinding.FieldName = ''FTRNAMESTR'' @AssignGroups.dfm:156|' +
    '  grdFtrsColFtrName.DataBinding.FieldName = ''FTRNAMESTR'' @AssignTools2.dfm:67|' +
    '  grdAssignedColFtrName.DataBinding.FieldName = ''FTRNAMESTR'' @AssignTools2.dfm:213|' +
    '  ... DFM data bindings only -- code-driven display is not indexed and is not shown';

function RepoRoot: string;
begin
  var Root:= GetEnvironmentVariable(REPO_ROOT_ENV);
  if (Root <> '') and TFile.Exists(TPath.Combine(Root, CHARTS_MARK)) then
    Exit(Root);
  var Dir:= GetCurrentDir;
  while Dir <> '' do
  begin
    if TFile.Exists(TPath.Combine(Dir, CHARTS_MARK)) then
      Exit(Dir);
    var Up:= ExtractFileDir(ExcludeTrailingPathDelimiter(Dir));
    if SameText(Up, Dir) then
      Break;
    Dir:= Up;
  end;
  Result:= '';
end;

function FileSha(const pPath: string): string;
begin
  var H:= THashSHA2.Create(THashSHA2.TSHA2Version.SHA256); // dl:ok object-leak@2527 -- THashSHA2 is a record, not a class: nothing to free
  H.Update(TFile.ReadAllBytes(pPath));
  Result:= H.HashAsString;
end;

procedure TQuestionFixture.Setup;
begin
  FOutRoot:= TPath.Combine(TPath.GetTempPath, 'drag-lint-charts-q-' + TGUID.NewGuid.ToString);
end;

procedure TQuestionFixture.TearDown;
begin
  if TDirectory.Exists(FOutRoot) then
    TDirectory.Delete(FOutRoot, True);
end;

function TQuestionFixture.Args(const pQuestion, pTarget, pCloneName: string; out pArgs: TQuestionArgs): Boolean;
begin
  pArgs:= Default(TQuestionArgs);
  var Root:= RepoRoot;
  var Db:= if Root = '' then '' else TPath.Combine(TPath.Combine(Root, CLONE_DIR), pCloneName);
  Result:= (Db <> '') and TFile.Exists(Db);
  if not Result then
  begin
    Assert.Pass('clone missing: ' + pCloneName);
    Exit;
  end;
  pArgs.Question:= pQuestion;
  pArgs.Target:= pTarget;
  pArgs.DbPath:= Db;
  pArgs.OutRoot:= FOutRoot;
  pArgs.ChartsRoot:= TPath.Combine(Root, 'charts');
  pArgs.Cap:= DEFAULT_CAP;
  pArgs.Depth:= DEFAULT_DEPTH;
  pArgs.SurfaceCap:= DEFAULT_SURFACE_CAP;
  pArgs.MaxRows:= DEFAULT_MAX_ROWS;
  pArgs.Command.Question:= pQuestion;
  var A: TCommandArg;
  A.Name:= 'Target';
  A.Value:= pTarget;
  pArgs.Command.Args:= [A];
  pArgs.AskedOn:= Now;
  pArgs.EngineVersion:= 'test';
end;

function TQuestionFixture.Fields(const pChart: TChartResult): string;
begin
  var Parts: TArray<string>:= [];
  for var F in pChart.Fields do
    Parts:= Parts + [F.Name + '=' + F.Json];
  Result:= string.Join(',', Parts);
end;

function TQuestionFixture.EmitChart(const pQuestion, pTarget, pCloneName: string; out pChart: TChartResult): Boolean;
var
  A: TQuestionArgs;
  E: TChartEmitter;
begin
  pChart:= Default(TChartResult);
  Result:= Args(pQuestion, pTarget, pCloneName, A);
  if not Result then
    Exit;
  Assert.IsTrue(FindChartQuestion(pQuestion, E), pQuestion + ' is not registered');
  pChart:= E(A, FOutRoot);
end;

function TQuestionFixture.Refusal(const pQuestion, pTarget, pCloneName: string): string;
var
  A: TQuestionArgs;
  E: TChartEmitter;
begin
  Result:= '';
  if not Args(pQuestion, pTarget, pCloneName, A) then
    Exit;
  Assert.IsTrue(FindChartQuestion(pQuestion, E), pQuestion + ' is not registered');
  try
    E(A, FOutRoot);
    Assert.Fail(pQuestion + ' was not refused');
  except
    on X: EChartsQuestion do Result:= X.Message;
    on X: EChartsIndex do Result:= X.Message;
  end;
end;

function TQuestionFixture.Answer(const pQuestion, pTarget, pCloneName: string; out pLines: TArray<string>): Boolean;
var
  A: TQuestionArgs;
begin
  pLines:= nil;
  Result:= Args(pQuestion, pTarget, pCloneName, A);
  if Result then
    pLines:= AskChartQuestion(A).Lines;
end;

{ ---- touches-tables ---- }

procedure TTouchesTablesTests.EmitterMatchesPowerShell;
var
  A: TQuestionArgs;
  E: TChartEmitter;
begin
  if not Args(TOUCHES_TABLES_ID, TT_TARGET, SERVER_CLONE, A) then
    Exit;
  Assert.IsTrue(FindChartQuestion(TOUCHES_TABLES_ID, E));
  var C:= E(A, FOutRoot);
  Assert.AreEqual(TT_FIELDS, Fields(C));
  Assert.AreEqual(Int64(TT_READS), C.LeftCount);
  Assert.AreEqual(TT_ANCHORS, C.Layout.Anchors);
  Assert.AreEqual(TT_DOT_SHA, FileSha(C.Layout.Dot));
end;

procedure TTouchesTablesTests.AnswerMatchesPowerShell;
var
  A: TQuestionArgs;
begin
  if not Args(TOUCHES_TABLES_ID, TT_TARGET, SERVER_CLONE, A) then
    Exit;
  var Answer:= AskChartQuestion(A);
  Assert.AreEqual('Which tables this routine touches (drag-lint report touches-tables) for ' + TT_TARGET + ', asked on ' +
    FormatDateTime('yyyy"-"mm"-"dd hh":"nn', A.AskedOn) + ', engine test.', Answer.Lines[0]);
  Assert.AreEqual('BUNDLE ' + Answer.BundleDir, Answer.Lines[BUNDLE_LINE]);
  var Rest:= Copy(Answer.Lines, 1, MaxInt);
  Delete(Rest, BUNDLE_LINE - 1, 1);
  Assert.AreEqual(TT_ANSWER.Replace('<db>', A.DbPath), string.Join('|', Rest));
  for var F in ['graph.dot', 'graph.svg', 'graph.plain', 'graph.png', 'graph.pdf', 'meta.json', 'index.html', 'xref.txt'] do
    Assert.IsTrue(TFile.Exists(TPath.Combine(Answer.BundleDir, F)), F);
end;

procedure TTouchesTablesTests.ClientIndexIsRefused;
var
  A: TQuestionArgs;
  E: TChartEmitter;
begin
  if not Args(TOUCHES_TABLES_ID, TT_TARGET, CLIENT_CLONE, A) then
    Exit;
  FindChartQuestion(TOUCHES_TABLES_ID, E);
  var Msg:= '';
  try
    E(A, FOutRoot);
  except
    on X: EChartsQuestion do Msg:= X.Message;
  end;
  Assert.StartsWith('touches-tables: this index has NO SQL facts at all (0 sql_reads, 0 sql_writes across ', Msg);
end;

{ ---- shown-where ---- }

function TShownWhereTests.Emit(const pColumn: string; out pChart: TChartResult): Boolean;
var
  A: TQuestionArgs;
  E: TChartEmitter;
begin
  pChart:= Default(TChartResult);
  Result:= Args(SHOWN_WHERE_ID, pColumn, CLIENT_CLONE, A);
  if not Result then
    Exit;
  Assert.IsTrue(FindChartQuestion(SHOWN_WHERE_ID, E), 'shown-where is not registered');
  pChart:= E(A, FOutRoot);
end;

procedure TShownWhereTests.FewFormsMatchPowerShell;
var
  C: TChartResult;
begin
  if not Emit(SW_FEW, C) then
    Exit;
  Assert.AreEqual(SW_FEW_FIELDS, Fields(C));
  Assert.AreEqual(SW_FEW_DOT_SHA, FileSha(C.Layout.Dot));
end;

procedure TShownWhereTests.TiedFormsKeepSortObjectOrder;
var
  C: TChartResult;
begin
  if not Emit(SW_TIED, C) then
    Exit;
  Assert.AreEqual(SW_TIED_FIELDS, Fields(C));
  Assert.AreEqual(SW_TIED_DOT_SHA, FileSha(C.Layout.Dot));
end;

procedure TShownWhereTests.CappedFormsMatchPowerShell;
var
  C: TChartResult;
begin
  if not Emit(SW_CAPPED, C) then
    Exit;
  Assert.AreEqual(SW_CAPPED_FIELDS, Fields(C));
  Assert.AreEqual(SW_CAPPED_DOT_SHA, FileSha(C.Layout.Dot));
end;

procedure TShownWhereTests.AnswerMatchesPowerShell;
var
  A: TQuestionArgs;
begin
  if not Args(SHOWN_WHERE_ID, SW_FEW, CLIENT_CLONE, A) then
    Exit;
  var Answer:= AskChartQuestion(A);
  var Rest:= Copy(Answer.Lines, 1, MaxInt);
  Delete(Rest, BUNDLE_LINE - 1, 1);
  Assert.AreEqual(SW_ANSWER.Replace('<db>', A.DbPath), string.Join('|', Rest));
end;

procedure TShownWhereTests.UnboundColumnIsRefused;
var
  A: TQuestionArgs;
  E: TChartEmitter;
begin
  if not Args(SHOWN_WHERE_ID, 'NO_SUCH_COLUMN_X', CLIENT_CLONE, A) then
    Exit;
  Assert.IsTrue(FindChartQuestion(SHOWN_WHERE_ID, E), 'shown-where is not registered');
  var Msg:= '';
  try
    E(A, FOutRoot);
  except
    on X: EChartsQuestion do Msg:= X.Message;
  end;
  Assert.AreEqual('no DFM in this index binds a column called ''NO_SUCH_COLUMN_X''. This chart reads DFM data bindings ' +
    '(903 in this index over 459 columns); it cannot see code-driven display such as Label.Caption := Field.AsString, and ' +
    'symbol_facts.ui_affinity does NOT answer this question -- it is a thread-affinity hint carried by routines, with zero ' +
    'coverage on fields and properties.', Msg);
end;

procedure TShownWhereTests.ServerIndexIsRefused;
var
  A: TQuestionArgs;
  E: TChartEmitter;
begin
  if not Args(SHOWN_WHERE_ID, SW_FEW, SERVER_CLONE, A) then
    Exit;
  Assert.IsTrue(FindChartQuestion(SHOWN_WHERE_ID, E), 'shown-where is not registered');
  var Msg:= '';
  try
    E(A, FOutRoot);
  except
    on X: EChartsQuestion do Msg:= X.Message;
  end;
  Assert.StartsWith('shown-where: this index contains NO DFM data bindings at all', Msg);
end;

{ ---- deps ---- }

function TDepsTests.Emit(const pUnit: string; out pChart: TChartResult): Boolean;
var
  A: TQuestionArgs;
  E: TChartEmitter;
begin
  pChart:= Default(TChartResult);
  Result:= Args(DEPS_ID, pUnit, DL_CLONE, A);
  if not Result then
    Exit;
  Assert.IsTrue(FindChartQuestion(DEPS_ID, E), 'deps is not registered');
  pChart:= E(A, FOutRoot);
end;

procedure TDepsTests.UsesCappedMatchPowerShell;
var
  C: TChartResult;
begin
  if not Emit(DEPS_CLI, C) then
    Exit;
  Assert.AreEqual(DEPS_CLI_FIELDS, Fields(C));
  Assert.AreEqual(DEPS_CLI_DOT_SHA, FileSha(C.Layout.Dot));
end;

procedure TDepsTests.UsersOverNineFoldersMatchPowerShell;
var
  C: TChartResult;
begin
  if not Emit(DEPS_MODEL, C) then
    Exit;
  Assert.AreEqual(DEPS_MODEL_FIELDS, Fields(C));
  Assert.AreEqual(DEPS_MODEL_DOT_SHA, FileSha(C.Layout.Dot));
end;

procedure TDepsTests.AnswerMatchesPowerShell;
var
  A: TQuestionArgs;
begin
  if not Args(DEPS_ID, DEPS_CLI, DL_CLONE, A) then
    Exit;
  var Answer:= AskChartQuestion(A);
  Assert.AreEqual<Integer>(DEPS_CLI_LINES, Length(Answer.Lines));
  Assert.AreEqual('CHART deps DRagLint.CLI -- 1 used by / 40 uses', Answer.Lines[DEPS_CHART_LINE]);
  Assert.AreEqual('  drag-lint @drag-lint.dpr:195', Answer.Lines[DEPS_FIRST_ROW]);
  Assert.AreEqual('  ... +70 more units this uses not shown -- 40 of 110 drawn (display cap 40) (raise -Cap to see them)',
    Answer.Lines[High(Answer.Lines)]);
end;

{ ---- class-surface ---- }

procedure TClassSurfaceTests.EmitterMatchesPowerShell;
var
  C: TChartResult;
begin
  if not EmitChart(CLASS_SURFACE_ID, CS_TARGET, CLIENT_CLONE, C) then
    Exit;
  Assert.StartsWith(CS_FIELDS_HEAD, Fields(C));
  Assert.EndsWith(CS_FIELDS_TAIL, Fields(C));
  Assert.AreEqual('24.0', C.RightJson);
  Assert.AreEqual(CS_DOT_SHA, FileSha(C.Layout.Dot));
end;

procedure TClassSurfaceTests.AnswerMatchesPowerShell;
var
  L: TArray<string>;
begin
  if not Answer(CLASS_SURFACE_ID, CS_TARGET, CLIENT_CLONE, L) then
    Exit;
  Assert.AreEqual<Integer>(CS_LINES, Length(L));
  Assert.AreEqual('CHART class-surface ' + CS_TARGET + ' -- 392 members / 24 shown', L[CS_CHART_LINE]);
  Assert.AreEqual('  TARGET ' + CS_TARGET + ' @Blueprint4.ViewModel.pas:57', L[CS_CHART_LINE + 1]);
  Assert.AreEqual('  ... +189 more members not shown (-SurfaceCap 12; raise -SurfaceCap to see them)', L[High(L)]);
end;

procedure TClassSurfaceTests.UnitIsRefused;
begin
  Assert.Contains(Refusal(CLASS_SURFACE_ID, 'Blueprint4.ViewModel', CLIENT_CLONE),
    'class-surface needs a type; a unit has no members to expose');
end;

{ ---- event-wiring ---- }

procedure TEventWiringTests.EmitterMatchesPowerShell;
var
  C: TChartResult;
begin
  if not EmitChart(EVENT_WIRING_ID, EW_TARGET, CLIENT_CLONE, C) then
    Exit;
  Assert.AreEqual(EW_FIELDS, Fields(C));
  Assert.AreEqual(EW_DOT_SHA, FileSha(C.Layout.Dot));
end;

procedure TEventWiringTests.ControlFilterMatchesPowerShell;
var
  A: TQuestionArgs;
  E: TChartEmitter;
begin
  if not Args(EVENT_WIRING_ID, EW_TARGET, CLIENT_CLONE, A) then
    Exit;
  var Ctl: TCommandArg;
  Ctl.Name:= 'Control';
  Ctl.Value:= EW_CONTROL;
  A.Command.Args:= A.Command.Args + [Ctl];
  Assert.IsTrue(FindChartQuestion(EVENT_WIRING_ID, E), 'event-wiring is not registered');
  var C:= E(A, FOutRoot);
  Assert.AreEqual(EW_CONTROL_FIELDS, Fields(C));
  Assert.AreEqual(EW_CONTROL_DOT_SHA, FileSha(C.Layout.Dot));
  { New-DiagramArtifact's slug takes the -Control too }
  var Answer:= AskChartQuestion(A);
  Assert.EndsWith('\event-wiring-uMain_TfrmMAIN_CauseList', Answer.BundleDir);
  Assert.AreEqual('COMMAND event-wiring -Target "uMain.TfrmMAIN" -Control "CauseList"', Answer.Lines[1]);
end;

procedure TEventWiringTests.AnswerMatchesPowerShell;
var
  L: TArray<string>;
begin
  if not Answer(EVENT_WIRING_ID, EW_TARGET, CLIENT_CLONE, L) then
    Exit;
  Assert.AreEqual<Integer>(EW_LINES, Length(L));
  Assert.AreEqual('  CauseList.OnClick = CauseListClick @uMain.dfm:3065', L[EW_FIRST_ROW]);
  Assert.StartsWith('  ... 6 more row(s) not printed here (-MaxRows 80): ', L[High(L)]);
end;

procedure TEventWiringTests.NonFormIsRefused;
begin
  Assert.StartsWith('no dfm_event facts under ' + CS_TARGET + ' (index has ',
    Refusal(EVENT_WIRING_ID, CS_TARGET, CLIENT_CLONE));
end;

{ ---- tested-by ---- }

procedure TTestedByTests.MethodMatchesPowerShell;
var
  C: TChartResult;
begin
  if not EmitChart(TESTED_BY_ID, TB_TARGET, TESTS_CLONE, C) then
    Exit;
  Assert.AreEqual(TB_FIELDS, Fields(C));
  Assert.AreEqual(TB_DOT_SHA, FileSha(C.Layout.Dot));
end;

procedure TTestedByTests.TypeSeedsItsMembers;
var
  C: TChartResult;
begin
  if not EmitChart(TESTED_BY_ID, TB_TYPE, TESTS_CLONE, C) then
    Exit;
  Assert.AreEqual(TB_TYPE_FIELDS, Fields(C));
  Assert.AreEqual(TB_TYPE_DOT_SHA, FileSha(C.Layout.Dot));
end;

procedure TTestedByTests.NoCoveringTestSaysSo;
var
  C: TChartResult;
begin
  if not EmitChart(TESTED_BY_ID, TB_NONE, TESTS_CLONE, C) then
    Exit;
  Assert.AreEqual(TB_NONE_FIELDS, Fields(C));
  Assert.AreEqual(TB_NONE_DOT_SHA, FileSha(C.Layout.Dot));
end;

procedure TTestedByTests.AnswerMatchesPowerShell;
var
  L: TArray<string>;
begin
  if not Answer(TESTED_BY_ID, TB_TARGET, TESTS_CLONE, L) then
    Exit;
  Assert.AreEqual<Integer>(TB_LINES, Length(L));
  Assert.AreEqual('CHART tested-by ' + TB_TARGET + ' -- 11 covering tests / 1 fixtures', L[CS_CHART_LINE]);
  Assert.AreEqual('  Test.CompGroupTree.TCompGroupTreeTests.Flush_unchanged_group_stays_unmodified @Test.CompGroupTree.pas:348', L[High(L)]);
end;

procedure TTestedByTests.ProductIndexIsRefused;
begin
  Assert.StartsWith('tested-by: this index carries no DUnitX [Test] attributes, so it is not a test project index.',
    Refusal(TESTED_BY_ID, EW_TARGET, CLIENT_CLONE));
end;

{ ---- change-impact ---- }

procedure TChangeImpactTests.MethodMatchesPowerShell;
var
  C: TChartResult;
begin
  if not EmitChart(CHANGE_IMPACT_ID, CI_TARGET, CLIENT_CLONE, C) then
    Exit;
  Assert.AreEqual(CI_FIELDS, Fields(C));
  Assert.AreEqual(CI_DOT_SHA, FileSha(C.Layout.Dot));
end;

procedure TChangeImpactTests.TypeSeedsMembersAndTypeUses;
var
  C: TChartResult;
begin
  if not EmitChart(CHANGE_IMPACT_ID, CS_TARGET, CLIENT_CLONE, C) then
    Exit;
  Assert.AreEqual(CI_TYPE_FIELDS, Fields(C));
  Assert.AreEqual(CI_TYPE_DOT_SHA, FileSha(C.Layout.Dot));
end;

procedure TChangeImpactTests.CappedWalkMatchesPowerShell;
var
  C: TChartResult;
begin
  if not EmitChart(CHANGE_IMPACT_ID, CI_CAPPED, CLIENT_CLONE, C) then
    Exit;
  Assert.AreEqual(CI_CAPPED_FIELDS, Fields(C));
  Assert.AreEqual(CI_CAPPED_DOT_SHA, FileSha(C.Layout.Dot));
end;

procedure TChangeImpactTests.AnswerMatchesPowerShell;
var
  L: TArray<string>;
begin
  if not Answer(CHANGE_IMPACT_ID, CI_TARGET, CLIENT_CLONE, L) then
    Exit;
  Assert.AreEqual<Integer>(CI_LINES, Length(L));
  Assert.AreEqual('CHART change-impact ' + CI_TARGET + ' -- 9 routines affected / 1 units', L[CS_CHART_LINE]);
  Assert.AreEqual('  ... +1 more routines not shown (raise -Cap to see them)', L[High(L)]);
end;

procedure TChangeImpactTests.LeafIsRefused;
begin
  Assert.StartsWith('nothing in this index depends on uMain.TfrmMAIN.CauseListClick -- 0 callers at any depth.',
    Refusal(CHANGE_IMPACT_ID, 'uMain.TfrmMAIN.CauseListClick', CLIENT_CLONE));
end;

end.