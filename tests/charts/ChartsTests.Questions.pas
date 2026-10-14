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

  [TestFixture]
  TCrossesBoundaryTests = class(TQuestionFixture)
  private
    function Emit(const pTarget, pCounterpart: string; out pChart: TChartResult): Boolean;
  public
    [Test] procedure WithCounterpartMatchesPowerShell;
    [Test] procedure WithoutCounterpartMatchesPowerShell;
    [Test] procedure TransportMethodIsTheBoundary;
    [Test] procedure NoEvidenceIsNotDoesNotCross;
    [Test] procedure AnswerNamesTheCounterpart;
  end;

  [TestFixture]
  TProtocolTraceTests = class(TQuestionFixture)
  public
    [Test] procedure CommandMatchesPowerShell;
    [Test] procedure MethodMatchesPowerShell;
    [Test] procedure MethodWithManyConstantsCountsThem;
    [Test] procedure WireFieldMatchesPowerShell;
    [Test] procedure AnswerMatchesPowerShell;
  end;

  [TestFixture]
  TLifecycleTests = class(TQuestionFixture)
  public
    [Test] procedure MainFormMatchesPowerShell;
    [Test] procedure TwoUnwiredStagesMatchPowerShell;
    [Test] procedure AnswerMatchesPowerShell;
    [Test] procedure PlainClassIsRefusedByHeritage;
  end;

  [TestFixture]
  TEffectsTests = class(TQuestionFixture)
  private
    procedure Check(const pTarget, pFields, pDotSha: string);
  public
    [Test] procedure EffectsAndAnAdmissionMatchPowerShell;
    [Test] procedure ParameterNamedByOrdinal;
    [Test] procedure GroupedParametersCountAsOrdinals;
    [Test] procedure PureIsEffectFreeNotNullSummary;
    [Test] procedure NullVerdictIsNotAnalysed;
    [Test] procedure AnswerMatchesPowerShell;
  end;

  [TestFixture]
  TFeedsFromTests = class(TQuestionFixture)
  private
    function SqlArgs(const pTarget, pSqlClone: string; out pArgs: TQuestionArgs): Boolean;
    procedure Check(const pTarget, pFields, pDotSha: string);
    function FeedsRefusal(const pTarget: string; const pSqlClone: string = ''): string;
  public
    [Test] procedure OneTableMatchesPowerShell;
    [Test] procedure TieBrokenByBoundColumns;
    [Test] procedure InterfaceTypedViewModelStops;
    [Test] procedure AmbiguousPrintsCandidatesAndNoColumn;
    [Test] procedure DanglingRePointFollowedToTable;
    [Test] procedure DanglingRePointStopsAtAWalkLimit;
    [Test] procedure DataSourceAndPersistentFieldAreRefused;
    [Test] procedure SelectionAndSqlIndexRoleAreChecked;
    [Test] procedure AnswerNamesTheSqlIndex;
  end;

  [TestFixture]
  TLandsWhereTests = class(TQuestionFixture)
  private
    function LwArgs(const pTarget, pDb, pServer, pSql: string; out pArgs: TQuestionArgs): Boolean;
    procedure Check(const pTarget, pFields, pDotSha: string);
    function LwRefusal(const pTarget: string; const pDb: string = ''; const pServer: string = ''; const pSql: string = ''): string;
  public
    [Test] procedure OrmPropertyMatchesPowerShell;
    [Test] procedure BackingFieldResolvesToItsProperty;
    [Test] procedure DfmControlFollowsTheFeedsFromChain;
    [Test] procedure ServerSqlNamesAColumnTheScriptsLack;
    [Test] procedure PropertyThatIsNoColumnSaysSo;
    [Test] procedure ComputedFieldOfAControlIsNoColumn;
    [Test] procedure DanglingChainStopsBeforeATable;
    [Test] procedure RePointedChainReachesTheTable;
    [Test] procedure SelectionRefusalsMatchPowerShell;
    [Test] procedure IndexRolesAreChecked;
    [Test] procedure MissingIndexesRefuseAsTheBundlerDoes;
    [Test] procedure AnswerNamesTheServerAndSqlIndexes;
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
  CROSSES_BOUNDARY_ID = 'crosses-boundary';
  CB_FIELDS = 'Qname="Blueprint4.ViewModel.TBlueprint_ViewModel.SendDeltaOperation",Zone="CLIENT",Verdict="crosses",Commands=2,PipeCalls=1,FarSide=18,SelfIsPipe=false,Clusters=4,ClickTargets=22,Expected=22,AllClickable=true';
  CB_DOT_SHA = '0d482728de30edf6f8541da9996c9310189995f4aff584f4d6065afd181353fb';
  CB_ALONE_FIELDS = 'Qname="Blueprint4.ViewModel.TBlueprint_ViewModel.SendDeltaOperation",Zone="CLIENT",Verdict="crosses",Commands=2,PipeCalls=1,FarSide=0,SelfIsPipe=false,Clusters=3,ClickTargets=4,Expected=4,AllClickable=true';
  CB_ALONE_DOT_SHA = 'bc4fe076532b5b36296f891d88ed114a404c8c8ef532fc3b9bae5eb57174e0b9';
  CB_SELF_FIELDS = 'Qname="uPipeClientConnection.TPipeClientConnection.NextSeq",Zone="CLIENT",Verdict="is the boundary",Commands=0,PipeCalls=0,FarSide=0,SelfIsPipe=true,Clusters=1,ClickTargets=1,Expected=1,AllClickable=true';
  CB_SELF_DOT_SHA = '0141a2f37ecfaa0a568a3b3cc8e8e0f2a1d26de4142b71ac334b4186aa744678';
  CB_NONE = 'uMain.TfrmMAIN.CauseListClick';
  CB_NONE_FIELDS = 'Qname="uMain.TfrmMAIN.CauseListClick",Zone="CLIENT",Verdict="no evidence in this index",Commands=0,PipeCalls=0,FarSide=0,SelfIsPipe=false,Clusters=2,ClickTargets=1,Expected=1,AllClickable=true';
  CB_NONE_DOT_SHA = '002ece2c52f5f564c02e7522b05b5dc06857b316d4139e17588f346d7b4ed375';
  CB_LINES = 28;
  PROTOCOL_TRACE_ID = 'protocol-trace';
  PT_CMD = 'cmdDelta';
  PT_CMD_FIELDS = 'Qname="Pipes.Protocol.TCommandID.cmdDelta",Mode="command",Refs=38,Zones=2,Routines=38,Commands=1,Unattributed=0,Kinds="read",Clusters=3,ClickTargets=22,Expected=22,AllClickable=true';
  PT_CMD_DOT_SHA = 'f92d7c0911d43b40efa1913793688fa99293a00d0e5a366fa46df7211f8b0a76';
  PT_METHOD_FIELDS = 'Qname="Blueprint4.ViewModel.TBlueprint_ViewModel.SendDeltaOperation",Mode="method",Refs=2,Zones=1,Routines=1,Commands=2,Unattributed=0,Kinds="read",Clusters=2,ClickTargets=2,Expected=2,AllClickable=true';
  PT_METHOD_DOT_SHA = 'e7cc7dd4aa39c0263b1c954c4949e378f5c5ad25df6fa9e7698cddb814830738';
  PT_MANY = 'Pipes.Protocol.CommandIDToStr';
  PT_MANY_FIELDS = 'Qname="Pipes.Protocol.CommandIDToStr",Mode="method",Refs=42,Zones=1,Routines=1,Commands=42,Unattributed=0,Kinds="read",Clusters=2,ClickTargets=2,Expected=2,AllClickable=true';
  PT_MANY_DOT_SHA = '98c792edb324ad1211a75794dcd817ac0b7103d730819196fdf4026094befd8d';
  PT_FIELD = 'Pipes.Protocol.TPipeMessageHeader.CommandID';
  PT_FIELD_FIELDS = 'Qname="Pipes.Protocol.TPipeMessageHeader.CommandID",Mode="field",Refs=1047,Zones=2,Routines=728,Commands=0,Unattributed=0,Kinds="member-access",Clusters=3,ClickTargets=24,Expected=24,AllClickable=true';
  PT_FIELD_DOT_SHA = '59c852de5a908751fbaed70674ca0f212439daa88a61303359043495a020dcf9';
  PT_LINES = 28;
  LIFECYCLE_ID = 'lifecycle';
  LC_MAIN_FIELDS = 'Form="uMain.TfrmMAIN",Heritage="TdxRibbonForm",Wired=2,NotWired=1,Absent=4,Stages=7,Oddities=0,Clusters=8,ClickTargets=3,Expected=3,AllClickable=true';
  LC_MAIN_DOT_SHA = '174f18d2acbd0a974f07d0cc9e561f94571063e8535dd576c13fb38e7f42baee';
  LC_SERIAL = 'DefineSerialNumbers.TfrmDefineSerialNumbers';
  LC_SERIAL_FIELDS = 'Form="DefineSerialNumbers.TfrmDefineSerialNumbers",Heritage="TForm",Wired=1,NotWired=2,Absent=4,Stages=7,Oddities=0,Clusters=8,ClickTargets=3,Expected=3,AllClickable=true';
  LC_SERIAL_DOT_SHA = 'e8d2936283a74340639c7c9ba806f7e8fa06101bd9c1e9a29aa75e6ac9b3021e';
  LC_LINES = 8;
  EFFECTS_ID = 'effects';
  EF_FIELDS = 'TestChart=false,Qname="Blueprint4.ViewModel.TBlueprint_ViewModel.SendDeltaOperation",Outcome="effects",EffectFree="0",Summary="g,s,?",Effects=2,Unknown=1,Unnamed=0,D12Suspect=false,ParamCount=1,Witness="writes field FLastPersistError",Clusters=3,ClickTargets=1,Expected=1,AllClickable=true';
  EF_DOT_SHA = '799de0250335f8d0854ab21560a6403d1e45b59bb6188ca3c4301ef85aa7bcb0';
  EF_AP = 'Ap.APVDotProduct';
  EF_AP_FIELDS = 'TestChart=false,Qname="Ap.APVDotProduct",Outcome="effects",EffectFree="0",Summary="p0,p3,?",Effects=2,Unknown=1,Unnamed=0,D12Suspect=false,ParamCount=6,Witness="calls Assert (unbound)",Clusters=3,ClickTargets=1,Expected=1,AllClickable=true';
  EF_AP_DOT_SHA = 'e8e82e413a7bf9c037c50bfa08c51e9b98345b7b3e8f2a35c31e45f194251ca4';
  EF_Z14 = 'Stats.Z14_LookupAcRe';
  EF_Z14_FIELDS = 'TestChart=false,Qname="Stats.Z14_LookupAcRe",Outcome="effects",EffectFree="0",Summary="p3,p4,p5,?",Effects=3,Unknown=1,Unnamed=0,D12Suspect=false,ParamCount=6,Witness="writes through parameter #3 (p_AcNmbr)",Clusters=3,ClickTargets=1,Expected=1,AllClickable=true';
  EF_Z14_DOT_SHA = '2c8c128da06e9829817c40e3d4efc365a6ede60455a62800e70d32082f8f1e12';
  EF_PURE = 'BASICSF.BoolToStr';
  EF_PURE_FIELDS = 'TestChart=false,Qname="BASICSF.BoolToStr",Outcome="pure",EffectFree="1",Summary="",Effects=0,Unknown=0,Unnamed=0,D12Suspect=false,ParamCount=1,Witness="",Clusters=2,ClickTargets=1,Expected=1,AllClickable=true';
  EF_PURE_DOT_SHA = '1d7ab810b4ec07f7e00870e77e172dbb32d4654f321e4d3f67981d87a67554db';
  EF_NA = 'uSetupDefaults.TGlobalSetupDefaults.GetDebug1';
  EF_NA_FIELDS = 'TestChart=false,Qname="uSetupDefaults.TGlobalSetupDefaults.GetDebug1",Outcome="not-analysed",EffectFree="NULL",Summary="",Effects=0,Unknown=0,Unnamed=0,D12Suspect=false,ParamCount=0,Witness="",Clusters=2,ClickTargets=1,Expected=1,AllClickable=true';
  EF_NA_DOT_SHA = 'de3e372524e883ca452e15acb8aa5191fe0b2ed56575926b411520b66c33b73f';
  EF_LINES = 7;
  FEEDS_FROM_ID = 'feeds-from';
  SQL_CLONE = 'SQL-drag-lint-sql.sqlite';
  FF_STATS = 'IndexDs=54,IndexDsDfm=5,IndexDsCode=49,IndexDsOne=22,IndexDsMany=17,IndexDsByCol=6,IndexDsNone=9,IndexDsOther=6,' +
    'Controls=808,CtlTable=471,CtlColumn=443,CtlNotColumn=28,CtlAmbiguous=37,CtlStops=77,CtlDangling=222,CtlNoDs=1,CtlStale=0,CoveragePct=58.3';
  FF_ONE = 'frmCausFail.colREASON';
  FF_ONE_FIELDS = 'Control="frmCausFail.cxGrid1.cxGrid1DBTableView1.colREASON",ControlType="TcxGridDBColumn",Field="REASON",DataSource="dsrCausFail",' +
    'DsOwner="cxGrid1DBTableView1",Grade="one-table",HopGrades="certain>certain>certain>by name>inferred",ChainRows=5,ResolvedTable="CAUSFAIL",' +
    'RePoint="",CtlDanglingAll=426,CtlRePoint="204/0/18/197/3/4/0/0",TableColumn="CAUSFAIL.REASON",ColumnExists="yes",Candidates="CAUSFAIL",' +
    'AfterTieBreak=0,BoundColumns=4,StopReason="",Dangling=false,RePointed=0,RePointedAt="",Rebound=0,' + FF_STATS +
    ',ClickTargets=7,Expected=7,AllClickable=true';
  FF_ONE_DOT_SHA = 'c891bf3b0b838dffba8fcd5b504caeea37b59c5aced7ab4b620adbb21f1c6398';
  FF_TIE = 'frmMachineList.colMACHINEID';
  FF_TIE_FIELDS = 'Control="frmMachineList.cxGrid1.cxGrid1DBTableView1.colMACHINEID",ControlType="TcxGridDBColumn",Field="MACHINEID",' +
    'DataSource="dsrMachines",DsOwner="cxGrid1DBTableView1",Grade="by-columns",HopGrades="certain>certain>certain>by name>inferred",ChainRows=5,' +
    'ResolvedTable="MACHINES",RePoint="",CtlDanglingAll=426,CtlRePoint="204/0/18/197/3/4/0/0",TableColumn="MACHINES.MACHINEID",ColumnExists="yes",' +
    'Candidates="MACHINES,STATIONS,PLANT,DEPARTTBL",AfterTieBreak=1,BoundColumns=6,StopReason="",Dangling=false,RePointed=0,RePointedAt="",Rebound=0,' +
    FF_STATS + ',ClickTargets=7,Expected=7,AllClickable=true';
  FF_TIE_DOT_SHA = '417820b87be165051d0900892631cc3d12cac871b3ec4d2bbacefb59d51a00ee';
  FF_INTF = 'frmBlueprintCADImport.grdBalsViewNUM';
  FF_INTF_FIELDS = 'Control="frmBlueprintCADImport.pnlGrids.grdBalloons.grdBalsView.grdBalsViewNUM",ControlType="TcxGridDBBandedColumn",Field="NUM",' +
    'DataSource="dsrBals",DsOwner="grdBalsView",Grade="none",HopGrades="certain>certain>certain>by name>stop",ChainRows=5,ResolvedTable=null,' +
    'RePoint="",CtlDanglingAll=426,CtlRePoint="204/0/18/197/3/4/0/0",TableColumn="",ColumnExists="n/a",Candidates="",AfterTieBreak=0,BoundColumns=1,' +
    'StopReason="[unresolved -- interface-typed view-model] Blueprint4.CADImport.Interfaces.pas holds no upper-case string literal naming a table ' +
    '(IBlueprintCADImport_ViewModel is an interface; its implementation is not followed)",Dangling=false,RePointed=0,RePointedAt="",Rebound=0,' +
    FF_STATS + ',ClickTargets=5,Expected=5,AllClickable=true';
  FF_INTF_DOT_SHA = '1f196a6a9481321e92585286ff8f395bece269dce56e99e5f5e3678744364256';
  FF_AMBIG = 'frmDefineSerialNumbers.cxGrid1DBTableView1SID1';
  FF_AMBIG_FIELDS = 'Control="frmDefineSerialNumbers.cxGrid1.cxGrid1DBTableView1.cxGrid1DBTableView1SID1",ControlType="TcxGridDBColumn",Field="SID",' +
    'DataSource="dsrPList",DsOwner="cxGrid1DBTableView1",Grade="many",HopGrades="certain>certain>certain>by name>stop",ChainRows=5,ResolvedTable=null,' +
    'RePoint="",CtlDanglingAll=426,CtlRePoint="204/0/18/197/3/4/0/0",TableColumn="",ColumnExists="n/a",Candidates="SERID,SERREAD,SERPART",' +
    'AfterTieBreak=3,BoundColumns=2,StopReason="ambiguous: SERID, SERREAD, SERPART share every bound column (ID, SID)",Dangling=false,RePointed=0,' +
    'RePointedAt="",Rebound=0,' + FF_STATS + ',ClickTargets=8,Expected=8,AllClickable=true';
  FF_AMBIG_DOT_SHA = '9678b2bddf65b9731173da7817ed4f76f1cf449a96292e65de85f66ea7f33e7e';
  FF_RP = 'frmBlueprint4.dxDBGrid1OperationVName';
  FF_RP_FIELDS = 'Control="frmBlueprint4.cxGroupBox16.cxPageControl1.tabRouter.cxGroupBox6.pnlOperationList.cxGrid1.dxDBGrid1OperationV.' +
    'dxDBGrid1OperationVName",ControlType="TcxGridDBColumn",Field="Name",DataSource="Blueprint4_Model.dsrOperation",DsOwner="dxDBGrid1OperationV",' +
    'Grade="dangling",HopGrades="certain>dangling>certain>certain>by name>by name>certain>certain>inferred",ChainRows=9,ResolvedTable="OPERAT",' +
    'RePoint="table",CtlDanglingAll=426,CtlRePoint="204/0/18/197/3/4/0/0",TableColumn="OPERAT.NAME",ColumnExists="yes",Candidates="",' +
    'AfterTieBreak=0,BoundColumns=0,StopReason="",Dangling=true,RePointed=2,RePointedAt="Blueprint4.pas:2282,Blueprint4.pas:3213",Rebound=0,' +
    FF_STATS + ',ClickTargets=13,Expected=13,AllClickable=true';
  FF_RP_DOT_SHA = 'b536d3c544a4b15c79dc3a02a7c4a6cd78b987efa3a1832e4f4c51c2977b80fd';
  FF_WALK = 'frmBlueprint4.edtF1';
  FF_WALK_FIELDS = 'Control="frmBlueprint4.cxGroupBox16.cxPageControl1.tabHeader.dxLayoutControl1.edtF1",ControlType="TcxDBTextEdit",' +
    'Field="WrkOrdrNmbr",DataSource="dmlSystem2.dsrFolder",DsOwner="edtF1",Grade="dangling",HopGrades="certain>dangling>certain>stop",ChainRows=4,' +
    'ResolvedTable=null,RePoint="walk-limit",CtlDanglingAll=426,CtlRePoint="204/0/18/197/3/4/0/0",TableColumn="",ColumnExists="n/a",Candidates="",' +
    'AfterTieBreak=0,BoundColumns=0,StopReason="the code re-point was followed to a shape this walk does not follow: DS is a local variable of ' +
    'RepointJobHeaderToFolder (TDataSource, :984) -- the value assigned to it there is not followed",Dangling=true,RePointed=1,' +
    'RePointedAt="Blueprint4.pas:1015",Rebound=1,' + FF_STATS + ',ClickTargets=6,Expected=6,AllClickable=true';
  FF_WALK_DOT_SHA = '0215ef526350760930dbc8f5b667b251b15c9b6421dbe078689c67cdef0186bb';
  LANDS_WHERE_ID = 'lands-where';
  LW_CONV = 'ConvProps=2063,ConvOnTable=1997,ConvColumn=1992,' +
    'ConvNonColumn="INSPRSLT.DistHist,INSPRSLT.DistHistLim,INSPRSLT.f_tb,STATIONS.GRIDS,STATIONS.MENUS",ConvQuoted="",ConvStale=""';
  LW_SRV = 'DsClasses=133,ParamByNameAll=383,ParamByNameDs=189,ParamByNameCol=183,OrmLinksCli=0,OrmLinksSrv=0';
  LW_CAUSFAIL_SRV = 'ServerClass="TDataService_CAUSFAIL_SERVER",ServerRows=4,ServerWrite="PrepareSaveQuery:124,Save:229",' +
    'ServerRead="PrepareLoadQuery:109,Load:159",ServerOther="",ServerElsewhere=1,Triggers=1,TriggerNames="CAUSFAIL_BIU5@MS5.SQL:15",' +
    'TriggersStale=0,Procedures=0,ProcedureNames="",ClientBindings=1,ClientRows="uCausFailForm.dfm:60:colREASON",ClientOther=6,';
  LW_NEWEST_OF_TWO = 'ColumnLabel="[certain] a column of the newest of 2 declaration(s), MS1.SQL",';
  LW_ORM = 'uCAUSFAIL.TmcCAUSFAIL.REASON';
  LW_ORM_FIELDS = 'TestChart=false,ClientOutcomes="column",IndexBindColumn=443,Selection="uCAUSFAIL.TmcCAUSFAIL.REASON",Kind="orm",' +
    'Property="uCAUSFAIL.TmcCAUSFAIL.REASON",Table="CAUSFAIL",TableColumn="CAUSFAIL.REASON",ColumnState="yes",ChainOutcome="",StopReason="",' +
    LW_CAUSFAIL_SRV + LW_CONV + ',' + LW_NEWEST_OF_TWO + LW_SRV + ',ClickTargets=9,Expected=9,AllClickable=true';
  LW_ORM_DOT_SHA = 'dc7570812275c8b70d5b4aa2c406fe1ec9c1cf9ccced3dfb14ffe421231fbecb';
  LW_FIELD = 'uCAUSFAIL.TmcCAUSFAIL.fREASON';
  LW_FIELD_FIELDS = 'TestChart=false,ClientOutcomes="column",IndexBindColumn=443,Selection="uCAUSFAIL.TmcCAUSFAIL.fREASON",Kind="orm",' +
    'Property="uCAUSFAIL.TmcCAUSFAIL.REASON",Table="CAUSFAIL",TableColumn="CAUSFAIL.REASON",ColumnState="yes",ChainOutcome="",StopReason="",' +
    LW_CAUSFAIL_SRV + LW_CONV + ',' + LW_NEWEST_OF_TWO + LW_SRV + ',ClickTargets=10,Expected=10,AllClickable=true';
  LW_FIELD_DOT_SHA = '518f6d2bdb4bbbd997f8aca013c95020f0383600702c211ff107faf2e543e171';
  LW_DFM = 'frmCausFail.colREASON';
  LW_DFM_FIELDS = 'TestChart=false,ClientOutcomes="column",IndexBindColumn=443,Selection="frmCausFail.colREASON",Kind="dfm",' +
    'Property="uCAUSFAIL.TmcCAUSFAIL.REASON",Table="CAUSFAIL",TableColumn="CAUSFAIL.REASON",ColumnState="yes",ChainOutcome="column",StopReason="",' +
    LW_CAUSFAIL_SRV + LW_CONV + ',' + LW_NEWEST_OF_TWO + LW_SRV + ',ClickTargets=14,Expected=14,AllClickable=true';
  LW_DFM_DOT_SHA = '2d6a5510d95efaa25728eb354c9f3565c408eb0a742514db60326d9947375ad3';
  LW_GRIDS = 'uSTATIONS.TmcSTATIONS.GRIDS';
  LW_GRIDS_FIELDS = 'TestChart=false,ClientOutcomes="",IndexBindColumn=443,Selection="uSTATIONS.TmcSTATIONS.GRIDS",Kind="orm",' +
    'Property="uSTATIONS.TmcSTATIONS.GRIDS",Table="STATIONS",TableColumn="STATIONS.GRIDS",ColumnState="server-sql",ChainOutcome="",StopReason="",' +
    'ServerClass="TDataService_STATIONS_SERVER",ServerRows=4,ServerWrite="PrepareSaveQuery:129,Save:271",ServerRead="PrepareLoadQuery:110,Load:176",' +
    'ServerOther="",ServerElsewhere=1,Triggers=0,TriggerNames="",TriggersStale=0,Procedures=0,ProcedureNames="",ClientBindings=0,ClientRows="",' +
    'ClientOther=0,' + LW_CONV + ',ColumnLabel="[inferred] not extracted as a column by the SQL index (23 columns extracted from the newest of 2 ' +
    'declaration(s), MS1.SQL:3495); nor a quoted identifier in that declaration -- but the SQL for STATIONS in ' +
    'TDataService_STATIONS_SERVER.PrepareLoadQuery names it: the scripts lag the schema",' + LW_SRV + ',ClickTargets=7,Expected=7,AllClickable=true';
  LW_GRIDS_DOT_SHA = '0a138efab154408cc58578e96e2c27b946174cd19043d8968de16ffb63def3c4';
  LW_NOCOL = 'uINSPRSLT.TmcINSPRSLT.DistHist';
  LW_NOCOL_FIELDS = 'TestChart=false,ClientOutcomes="",IndexBindColumn=443,Selection="uINSPRSLT.TmcINSPRSLT.DistHist",Kind="orm",' +
    'Property="uINSPRSLT.TmcINSPRSLT.DistHist",Table="INSPRSLT",TableColumn="",ColumnState="no",ChainOutcome="",StopReason="",' +
    'ServerClass="TDataService_INSPRSLT_SERVER",ServerRows=0,ServerWrite="",ServerRead="",ServerOther="",ServerElsewhere=0,Triggers=0,' +
    'TriggerNames="",TriggersStale=0,Procedures=0,ProcedureNames="",ClientBindings=0,ClientRows="",ClientOther=0,' + LW_CONV +
    ',ColumnLabel="not extracted as a column by the SQL index (144 columns extracted from the newest of 2 declaration(s), MS1.SQL:2073); ' +
    'nor a quoted identifier in that declaration; no SQL for INSPRSLT in the server''s TDataService_INSPRSLT_SERVER names it",' + LW_SRV +
    ',ClickTargets=2,Expected=2,AllClickable=true';
  LW_NOCOL_DOT_SHA = 'e116eba552c85f35e56439df77789a707c3ab61f302fd15d4885867223b3ac8b';
  LW_COMPUTED = 'frmJobList.cxGrid1DBTableView1DueInStr1';
  LW_COMPUTED_FIELDS = 'TestChart=false,ClientOutcomes="not-column",IndexBindColumn=443,Selection="frmJobList.cxGrid1DBTableView1DueInStr1",' +
    'Kind="dfm",Property="",Table="FOLDERS",TableColumn="",ColumnState="no",ChainOutcome="not-column",StopReason="",' +
    'ServerClass="TDataService_FOLDERS_SERVER",ServerRows=0,ServerWrite="",ServerRead="",ServerOther="",ServerElsewhere=0,Triggers=0,' +
    'TriggerNames="",TriggersStale=0,Procedures=0,ProcedureNames="",ClientBindings=1,ClientRows="uJobList.dfm:480:cxGrid1DBTableView1DueInStr1",' +
    'ClientOther=0,' + LW_CONV + ',ColumnLabel="not extracted as a column by the SQL index (79 columns extracted from the newest of 2 ' +
    'declaration(s), MS1.SQL:1834); nor a quoted identifier in that declaration; no SQL for FOLDERS in the server''s TDataService_FOLDERS_SERVER ' +
    'names it",' + LW_SRV + ',ClickTargets=7,Expected=7,AllClickable=true';
  LW_COMPUTED_DOT_SHA = '9c9fa02b7e0a28b798d6b8c3cd6e8948cbcd2eaaed0bd20f867f6d7841ea6ced';
  LW_DANGLING = 'frmBlueprint4.edtF1';
  LW_DANGLING_FIELDS = 'TestChart=false,ClientOutcomes="",IndexBindColumn=443,Selection="frmBlueprint4.edtF1",Kind="dfm",Property="",Table=null,' +
    'TableColumn="",ColumnState="n/a",ChainOutcome="dangling",StopReason="the designer datasource dmlSystem2.dsrFolder is dangling (module ' +
    'dmlSystem2 is declared nowhere in this index (no form, var or symbol) -- a dangling designer reference) -- no table; the code re-point: DS ' +
    'is a local variable of RepointJobHeaderToFolder (TDataSource, :984) -- the value assigned to it there is not followed",ServerClass=null,' +
    'ServerRows=0,ServerWrite="",ServerRead="",ServerOther="",ServerElsewhere=0,Triggers=0,TriggerNames="",TriggersStale=0,Procedures=0,' +
    'ProcedureNames="",ClientBindings=0,ClientRows="",ClientOther=0,' + LW_CONV + ',ColumnLabel="",' + LW_SRV +
    ',ClickTargets=3,Expected=3,AllClickable=true';
  LW_DANGLING_DOT_SHA = '7927c0c3e18486a72c4f19cdb6b85ce68a84b3799c4b409abcc1bfc6c27e4657';
  LW_RP = 'frmBlueprint4.dxDBGrid1OperationVName';
  LW_RP_FIELDS = 'TestChart=false,ClientOutcomes="column",IndexBindColumn=443,Selection="frmBlueprint4.dxDBGrid1OperationVName",Kind="dfm",' +
    'Property="uOPERAT.TmcOPERAT.NAME",Table="OPERAT",TableColumn="OPERAT.NAME",ColumnState="yes",ChainOutcome="column",StopReason="",' +
    'ServerClass="TDataService_OPERAT_SERVER",ServerRows=4,ServerWrite="PrepareSaveQuery:134,Save:338",ServerRead="PrepareLoadQuery:114,Load:209",' +
    'ServerOther="",ServerElsewhere=1,Triggers=0,TriggerNames="",TriggersStale=0,Procedures=0,ProcedureNames="",ClientBindings=1,' +
    'ClientRows="Blueprint4.dfm:4534:dxDBGrid1OperationVName",ClientOther=25,' + LW_CONV + ',' + LW_NEWEST_OF_TWO + LW_SRV +
    ',ClickTargets=17,Expected=17,AllClickable=true';
  LW_RP_DOT_SHA = '63d846867e5cf864b07352dd1c8ef08af7a6f2d2e8affcbb9457eb192b871be9';
  LW_NOT_ORM = 'not an ORM object property (class is not Tmc<T>) and not a DFM-bound field';
  LW_LINES = 17;
  LW_SERVER_INDEX_LINE = 4;
  LW_CHART = 'CHART lands-where uCAUSFAIL.TmcCAUSFAIL.REASON -- 4 server DataService rows / 1 triggers touching the column';
  LW_LAST_ROW = '  ... positional Fields[i] / Params[i] reads are not shown -- they never name the column';
  FF_LINES = 13;
  FF_SQL_INDEX_LINE = 4;
  FF_CHART_LINE = 5;  DEPS_CHART_LINE = 4;
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

{ ---- crosses-boundary ---- }

function TCrossesBoundaryTests.Emit(const pTarget, pCounterpart: string; out pChart: TChartResult): Boolean;
var
  A: TQuestionArgs;
  E: TChartEmitter;
begin
  pChart:= Default(TChartResult);
  Result:= Args(CROSSES_BOUNDARY_ID, pTarget, CLIENT_CLONE, A);
  if not Result then
    Exit;
  if pCounterpart <> '' then
    A.CounterpartDb:= TPath.Combine(ExtractFileDir(A.DbPath), pCounterpart);
  Assert.IsTrue(FindChartQuestion(CROSSES_BOUNDARY_ID, E), 'crosses-boundary is not registered');
  pChart:= E(A, FOutRoot);
end;

procedure TCrossesBoundaryTests.WithCounterpartMatchesPowerShell;
var
  C: TChartResult;
begin
  if not Emit(CI_TARGET, SERVER_CLONE, C) then
    Exit;
  Assert.AreEqual(CB_FIELDS, Fields(C));
  Assert.AreEqual(CB_DOT_SHA, FileSha(C.Layout.Dot));
end;

procedure TCrossesBoundaryTests.WithoutCounterpartMatchesPowerShell;
var
  C: TChartResult;
begin
  if not Emit(CI_TARGET, '', C) then
    Exit;
  Assert.AreEqual(CB_ALONE_FIELDS, Fields(C));
  Assert.AreEqual(CB_ALONE_DOT_SHA, FileSha(C.Layout.Dot));
end;

procedure TCrossesBoundaryTests.TransportMethodIsTheBoundary;
var
  C: TChartResult;
begin
  if not Emit(CI_CAPPED, '', C) then
    Exit;
  Assert.AreEqual(CB_SELF_FIELDS, Fields(C));
  Assert.AreEqual(CB_SELF_DOT_SHA, FileSha(C.Layout.Dot));
end;

procedure TCrossesBoundaryTests.NoEvidenceIsNotDoesNotCross;
var
  C: TChartResult;
begin
  if not Emit(CB_NONE, '', C) then
    Exit;
  Assert.AreEqual(CB_NONE_FIELDS, Fields(C));
  Assert.AreEqual(CB_NONE_DOT_SHA, FileSha(C.Layout.Dot));
end;

procedure TCrossesBoundaryTests.AnswerNamesTheCounterpart;
var
  A: TQuestionArgs;
begin
  if not Args(CROSSES_BOUNDARY_ID, CI_TARGET, CLIENT_CLONE, A) then
    Exit;
  A.CounterpartDb:= TPath.Combine(ExtractFileDir(A.DbPath), SERVER_CLONE);
  var L:= AskChartQuestion(A).Lines;
  Assert.AreEqual<Integer>(CB_LINES, Length(L));
  Assert.AreEqual('INDEX ' + A.CounterpartDb + ' (counterpart)', L[CS_CHART_LINE]);
  Assert.AreEqual('  uPipeSessionBuilder.TPipeSessionBuilder.RouteSTATIONS handles rspOK @uPipeSessionBuilder.pas:902', L[High(L)]);
end;

{ ---- protocol-trace ---- }

procedure TProtocolTraceTests.CommandMatchesPowerShell;
var
  C: TChartResult;
begin
  if not EmitChart(PROTOCOL_TRACE_ID, PT_CMD, CLIENT_CLONE, C) then
    Exit;
  Assert.AreEqual(PT_CMD_FIELDS, Fields(C));
  Assert.AreEqual(PT_CMD_DOT_SHA, FileSha(C.Layout.Dot));
end;

procedure TProtocolTraceTests.MethodMatchesPowerShell;
var
  C: TChartResult;
begin
  if not EmitChart(PROTOCOL_TRACE_ID, CI_TARGET, CLIENT_CLONE, C) then
    Exit;
  Assert.AreEqual(PT_METHOD_FIELDS, Fields(C));
  Assert.AreEqual(PT_METHOD_DOT_SHA, FileSha(C.Layout.Dot));
end;

procedure TProtocolTraceTests.MethodWithManyConstantsCountsThem;
var
  C: TChartResult;
begin
  if not EmitChart(PROTOCOL_TRACE_ID, PT_MANY, CLIENT_CLONE, C) then
    Exit;
  Assert.AreEqual(PT_MANY_FIELDS, Fields(C));
  Assert.AreEqual(PT_MANY_DOT_SHA, FileSha(C.Layout.Dot));
end;

procedure TProtocolTraceTests.WireFieldMatchesPowerShell;
var
  C: TChartResult;
begin
  if not EmitChart(PROTOCOL_TRACE_ID, PT_FIELD, CLIENT_CLONE, C) then
    Exit;
  Assert.AreEqual(PT_FIELD_FIELDS, Fields(C));
  Assert.AreEqual(PT_FIELD_DOT_SHA, FileSha(C.Layout.Dot));
end;

procedure TProtocolTraceTests.AnswerMatchesPowerShell;
var
  L: TArray<string>;
begin
  if not Answer(PROTOCOL_TRACE_ID, PT_CMD, CLIENT_CLONE, L) then
    Exit;
  Assert.AreEqual<Integer>(PT_LINES, Length(L));
  Assert.AreEqual('CHART protocol-trace cmdDelta -- 38 references / 2 zones', L[CS_CHART_LINE]);
  Assert.AreEqual('  ... +17 more routines (+17 more sites) not shown (-Cap 20; raise -Cap to see them)', L[High(L)]);
end;

{ ---- lifecycle ---- }

procedure TLifecycleTests.MainFormMatchesPowerShell;
var
  C: TChartResult;
begin
  if not EmitChart(LIFECYCLE_ID, EW_TARGET, CLIENT_CLONE, C) then
    Exit;
  Assert.AreEqual(LC_MAIN_FIELDS, Fields(C));
  Assert.AreEqual(LC_MAIN_DOT_SHA, FileSha(C.Layout.Dot));
end;

procedure TLifecycleTests.TwoUnwiredStagesMatchPowerShell;
var
  C: TChartResult;
begin
  if not EmitChart(LIFECYCLE_ID, LC_SERIAL, CLIENT_CLONE, C) then
    Exit;
  Assert.AreEqual(LC_SERIAL_FIELDS, Fields(C));
  Assert.AreEqual(LC_SERIAL_DOT_SHA, FileSha(C.Layout.Dot));
end;

procedure TLifecycleTests.AnswerMatchesPowerShell;
var
  L: TArray<string>;
begin
  if not Answer(LIFECYCLE_ID, EW_TARGET, CLIENT_CLONE, L) then
    Exit;
  Assert.AreEqual<Integer>(LC_LINES, Length(L));
  Assert.AreEqual('CHART lifecycle uMain.TfrmMAIN -- 2 stages wired / 1 implemented, not wired', L[CS_CHART_LINE]);
  Assert.AreEqual('  uMain.TfrmMAIN.FormDestroy @uMain.pas:422', L[High(L)]);
end;

procedure TLifecycleTests.PlainClassIsRefusedByHeritage;
begin
  Assert.AreEqual(CS_TARGET + ' is not a form: its heritage is TInterfacedObject, and none of ' +
    'TForm/TCustomForm/TdxRibbonForm/TDataModule/TFrame/TCustomFrame appears in it. Note this is a HERITAGE check -- ' +
    'a real form that wires nothing is a different answer and still renders.', Refusal(LIFECYCLE_ID, CS_TARGET, CLIENT_CLONE));
end;

{ ---- effects ---- }

procedure TEffectsTests.Check(const pTarget, pFields, pDotSha: string);
var
  C: TChartResult;
begin
  if not EmitChart(EFFECTS_ID, pTarget, CLIENT_CLONE, C) then
    Exit;
  Assert.AreEqual(pFields, Fields(C));
  Assert.AreEqual(pDotSha, FileSha(C.Layout.Dot));
end;

procedure TEffectsTests.EffectsAndAnAdmissionMatchPowerShell;
begin
  Check(CI_TARGET, EF_FIELDS, EF_DOT_SHA);
end;

procedure TEffectsTests.ParameterNamedByOrdinal;
begin
  Check(EF_Z14, EF_Z14_FIELDS, EF_Z14_DOT_SHA);
end;

procedure TEffectsTests.GroupedParametersCountAsOrdinals;
begin
  { APVDotProduct(V1; I11, I12; V2; ...): grouped names are separate ordinals, p3 is V2 }
  Check(EF_AP, EF_AP_FIELDS, EF_AP_DOT_SHA);
end;

procedure TEffectsTests.PureIsEffectFreeNotNullSummary;
begin
  Check(EF_PURE, EF_PURE_FIELDS, EF_PURE_DOT_SHA);
end;

procedure TEffectsTests.NullVerdictIsNotAnalysed;
begin
  Check(EF_NA, EF_NA_FIELDS, EF_NA_DOT_SHA);
end;

procedure TEffectsTests.AnswerMatchesPowerShell;
var
  L: TArray<string>;
begin
  if not Answer(EFFECTS_ID, CI_TARGET, CLIENT_CLONE, L) then
    Exit;
  Assert.AreEqual<Integer>(EF_LINES, Length(L));
  Assert.AreEqual('CHART effects ' + CI_TARGET + ' -- 2 effects / 1 unclassified tokens', L[CS_CHART_LINE]);
  Assert.StartsWith('  (no anchored result rows -- open ', L[High(L)]);
end;

{ ---- feeds-from ---- }

{ the fixture's arguments plus the SQL-script clone (-SqlDbPath); pSqlClone '' = the SQL clone }
function TFeedsFromTests.SqlArgs(const pTarget, pSqlClone: string; out pArgs: TQuestionArgs): Boolean;
begin
  Result:= Args(FEEDS_FROM_ID, pTarget, CLIENT_CLONE, pArgs);
  if not Result then
    Exit;
  var Sql:= TPath.Combine(ExtractFileDir(pArgs.DbPath), if pSqlClone = '' then SQL_CLONE else pSqlClone);
  Result:= TFile.Exists(Sql);
  if not Result then
  begin
    Assert.Pass('clone missing: ' + Sql);
    Exit;
  end;
  pArgs.SqlDbPath:= Sql;
end;

procedure TFeedsFromTests.Check(const pTarget, pFields, pDotSha: string);
var
  A: TQuestionArgs;
  E: TChartEmitter;
begin
  if not SqlArgs(pTarget, '', A) then
    Exit;
  Assert.IsTrue(FindChartQuestion(FEEDS_FROM_ID, E));
  var C:= E(A, FOutRoot);
  Assert.AreEqual(pFields, Fields(C));
  Assert.AreEqual(pDotSha, FileSha(C.Layout.Dot));
end;

function TFeedsFromTests.FeedsRefusal(const pTarget, pSqlClone: string): string;
var
  A: TQuestionArgs;
  E: TChartEmitter;
begin
  Result:= '';
  if not SqlArgs(pTarget, pSqlClone, A) then
    Exit;
  Assert.IsTrue(FindChartQuestion(FEEDS_FROM_ID, E));
  try
    E(A, FOutRoot);
    Assert.Fail(pTarget + ' was not refused');
  except
    on X: EChartsQuestion do Result:= X.Message;
  end;
end;

procedure TFeedsFromTests.OneTableMatchesPowerShell;
begin
  Check(FF_ONE, FF_ONE_FIELDS, FF_ONE_DOT_SHA);
end;

procedure TFeedsFromTests.TieBrokenByBoundColumns;
begin
  { P33: four candidate tables in literal order, six bound columns, one survivor }
  Check(FF_TIE, FF_TIE_FIELDS, FF_TIE_DOT_SHA);
end;

procedure TFeedsFromTests.InterfaceTypedViewModelStops;
begin
  Check(FF_INTF, FF_INTF_FIELDS, FF_INTF_DOT_SHA);
end;

procedure TFeedsFromTests.AmbiguousPrintsCandidatesAndNoColumn;
begin
  { three tables share every bound column: the candidates are drawn, never a TABLE.COLUMN }
  Check(FF_AMBIG, FF_AMBIG_FIELDS, FF_AMBIG_DOT_SHA);
end;

procedure TFeedsFromTests.DanglingRePointFollowedToTable;
begin
  { past the dangling Blueprint4_Model.dsrOperation the code re-point is walked to OPERAT }
  Check(FF_RP, FF_RP_FIELDS, FF_RP_DOT_SHA);
end;

procedure TFeedsFromTests.DanglingRePointStopsAtAWalkLimit;
begin
  { re-pointed AND re-bound in code (the side cluster), the walk stops at a local variable }
  Check(FF_WALK, FF_WALK_FIELDS, FF_WALK_DOT_SHA);
end;

procedure TFeedsFromTests.DataSourceAndPersistentFieldAreRefused;
begin
  Assert.AreEqual('feeds-from selects a data-aware CONTROL, not a datasource -- ask consumers/shown-where. frmCausFail.dsrCausFail is a ' +
    'TDataSource; pick a control bound to it (a grid column, an edit) to see its chain.', FeedsRefusal('frmCausFail.dsrCausFail'));
  Assert.AreEqual('feeds-from: frmCompGroupSetup2.tblCompTree.tblCompTreeName is a persistent FIELD (TStringField) of the dataset tblCompTree, ' +
    'not a control -- its FieldName names the dataset column it maps. Ask shown-where for the controls that display that column.',
    FeedsRefusal('frmCompGroupSetup2.tblCompTreeName'));
end;

procedure TFeedsFromTests.SelectionAndSqlIndexRoleAreChecked;
begin
  Assert.AreEqual('feeds-from: -Control takes <Form>.<Control> (e.g. frmCausFail.colREASON), got ''colREASON''', FeedsRefusal('colREASON'));
  { a swapped pair must not render: the Delphi clone has no sql_table symbol }
  Assert.EndsWith(CLIENT_CLONE + ' is not a SQL index (0 sql_table symbols) -- -SqlDbPath takes the SQL-script clone, -DbPath the Delphi ' +
    'project clone', FeedsRefusal(FF_ONE, CLIENT_CLONE));
end;

procedure TFeedsFromTests.AnswerNamesTheSqlIndex;
var
  A: TQuestionArgs;
begin
  if not SqlArgs(FF_ONE, '', A) then
    Exit;
  var L:= AskChartQuestion(A).Lines;
  Assert.AreEqual<Integer>(FF_LINES, Length(L));
  Assert.AreEqual('INDEX ' + A.SqlDbPath + ' (sql)', L[FF_SQL_INDEX_LINE]);
  Assert.AreEqual('CHART feeds-from ' + FF_ONE + ' -- 5 chain rows / 471 controls in the index that resolve to one table', L[FF_CHART_LINE]);
  Assert.AreEqual('  CAUSFAIL.REASON @MS1.SQL:1411', L[High(L)]);
end;

{ ---- lands-where ---- }

{ the three clones lands-where reads; '' = CLIENT / SERVER / SQL, as the parity case passes them }
function TLandsWhereTests.LwArgs(const pTarget, pDb, pServer, pSql: string; out pArgs: TQuestionArgs): Boolean;
begin
  Result:= Args(LANDS_WHERE_ID, pTarget, if pDb = '' then CLIENT_CLONE else pDb, pArgs);
  if not Result then
    Exit;
  var Dir:= ExtractFileDir(pArgs.DbPath);
  var Server:= TPath.Combine(Dir, if pServer = '' then SERVER_CLONE else pServer);
  var Sql:= TPath.Combine(Dir, if pSql = '' then SQL_CLONE else pSql);
  Result:= TFile.Exists(Server) and TFile.Exists(Sql);
  if not Result then
  begin
    Assert.Pass('clone missing: ' + Server + ' or ' + Sql);
    Exit;
  end;
  pArgs.ServerDbPath:= Server;
  pArgs.SqlDbPath:= Sql;
end;

procedure TLandsWhereTests.Check(const pTarget, pFields, pDotSha: string);
var
  A: TQuestionArgs;
  E: TChartEmitter;
begin
  if not LwArgs(pTarget, '', '', '', A) then
    Exit;
  Assert.IsTrue(FindChartQuestion(LANDS_WHERE_ID, E));
  var C:= E(A, FOutRoot);
  Assert.AreEqual(pFields, Fields(C));
  Assert.AreEqual(pDotSha, FileSha(C.Layout.Dot));
end;

function TLandsWhereTests.LwRefusal(const pTarget, pDb, pServer, pSql: string): string;
var
  A: TQuestionArgs;
  E: TChartEmitter;
begin
  Result:= '';
  if not LwArgs(pTarget, pDb, pServer, pSql, A) then
    Exit;
  Assert.IsTrue(FindChartQuestion(LANDS_WHERE_ID, E));
  try
    E(A, FOutRoot);
    Assert.Fail(pTarget + ' was not refused');
  except
    on X: EChartsQuestion do Result:= X.Message;
  end;
end;

procedure TLandsWhereTests.OrmPropertyMatchesPowerShell;
begin
  { write path, read path, a trigger naming NEW.REASON, one bound control: every cluster }
  Check(LW_ORM, LW_ORM_FIELDS, LW_ORM_DOT_SHA);
end;

procedure TLandsWhereTests.BackingFieldResolvesToItsProperty;
begin
  { fREASON -> REASON [by name]: one more anchored row on the property box }
  Check(LW_FIELD, LW_FIELD_FIELDS, LW_FIELD_DOT_SHA);
end;

procedure TLandsWhereTests.DfmControlFollowsTheFeedsFromChain;
begin
  Check(LW_DFM, LW_DFM_FIELDS, LW_DFM_DOT_SHA);
end;

procedure TLandsWhereTests.ServerSqlNamesAColumnTheScriptsLack;
begin
  { STATIONS.GRIDS is in no script, yet the server's own SQL names it: server-sql, never "not a column" }
  Check(LW_GRIDS, LW_GRIDS_FIELDS, LW_GRIDS_DOT_SHA);
end;

procedure TLandsWhereTests.PropertyThatIsNoColumnSaysSo;
begin
  { searched in TDataService_INSPRSLT_SERVER and named by nothing: "computed or UI-only" }
  Check(LW_NOCOL, LW_NOCOL_FIELDS, LW_NOCOL_DOT_SHA);
end;

procedure TLandsWhereTests.ComputedFieldOfAControlIsNoColumn;
begin
  { R17: a uJobList control bound to a computed FOLDERS field; no Tmc property of that name }
  Check(LW_COMPUTED, LW_COMPUTED_FIELDS, LW_COMPUTED_DOT_SHA);
end;

procedure TLandsWhereTests.DanglingChainStopsBeforeATable;
begin
  { a null Table and ServerClass, and the code re-point's stop in the stop reason }
  Check(LW_DANGLING, LW_DANGLING_FIELDS, LW_DANGLING_DOT_SHA);
end;

procedure TLandsWhereTests.RePointedChainReachesTheTable;
begin
  { past the dangling Blueprint4_Model.dsrOperation: the re-point hops on the control box, OPERAT.NAME }
  Check(LW_RP, LW_RP_FIELDS, LW_RP_DOT_SHA);
end;

procedure TLandsWhereTests.SelectionRefusalsMatchPowerShell;
begin
  Assert.AreEqual('lands-where: -Field takes <Unit>.<Tmc class>.<property> or <Form>.<Control>, got ''bad name''', LwRefusal('bad name'));
  Assert.AreEqual('lands-where: uFOLDERS.TmcFOLDERS.TABLE resolves to no property or field in this index and uFOLDERS is no form -- ' +
    LW_NOT_ORM + '.', LwRefusal('uFOLDERS.TmcFOLDERS.TABLE'));
  Assert.AreEqual('lands-where: uPipeClientConnection.TPipeClientConnection.Connected is on TPipeClientConnection -- ' + LW_NOT_ORM + '.',
    LwRefusal('uPipeClientConnection.TPipeClientConnection.Connected'));
  Assert.AreEqual('lands-where: no table named FIB_FIELDS_INFO in the SQL index (the scripts declare FIB$FIELDS_INFO) -- the name was ' +
    'derived from TmcFIB_FIELDS_INFO by the Tmc<T> / Imc<T> naming convention. 5 live tables are not in the scripts (2026-09-23).',
    LwRefusal('uFIB_FIELDS_INFO.TmcFIB_FIELDS_INFO.FIELD_NAME'));
  Assert.AreEqual('lands-where: no table named MEMCONTROLPLANNINGPRESETS in the SQL index (script-derived; the scripts may lag the live ' +
    'schema) -- the name was derived from TmcMEMCONTROLPLANNINGPRESETS by the Tmc<T> / Imc<T> naming convention. 5 live tables are not ' +
    'in the scripts (2026-09-23).', LwRefusal('uMEMCONTROLPLANNINGPRESETS.TmcMEMCONTROLPLANNINGPRESETS.OLDID'));
  Assert.AreEqual('lands-where: frmCompGroupSetup2.tblCompTree.tblCompTreeName is a persistent FIELD (TStringField) of the dataset ' +
    'tblCompTree, not a data-aware control -- its dataset is not a datasource chain. Ask lands-where of the ORM property, or of a control ' +
    'bound to that column.', LwRefusal('frmCompGroupSetup2.tblCompTreeName'));
end;

procedure TLandsWhereTests.IndexRolesAreChecked;
begin
  { a swapped pair must refuse, never render an empty chart }
  Assert.EndsWith(CLIENT_CLONE + ' holds no TDataService_<T>_SERVER class -- -ServerDbPath takes the SERVER clone ' +
    '(SERVER-MicroniteMW1Service.sqlite), where the write and read path live', LwRefusal(LW_ORM, '', CLIENT_CLONE));
  Assert.EndsWith(SERVER_CLONE + ' holds TDataService_<T>_SERVER classes, so it is a SERVER index -- -DbPath takes the CLIENT clone ' +
    '(the ORM classes and the DFM bindings); the SERVER clone goes in -ServerDbPath', LwRefusal(LW_ORM, SERVER_CLONE));
  Assert.EndsWith(CLIENT_CLONE + ' is not a SQL index (0 sql_table symbols) -- -SqlDbPath takes the SQL-script clone',
    LwRefusal(LW_ORM, '', '', CLIENT_CLONE));
  Assert.AreEqual('lands-where: a SQL-script index was passed as a Delphi clone -- -DbPath takes CLIENT, -ServerDbPath SERVER, ' +
    '-SqlDbPath the scripts', LwRefusal(LW_ORM, '', SQL_CLONE));
end;

procedure TLandsWhereTests.MissingIndexesRefuseAsTheBundlerDoes;
var
  A: TQuestionArgs;
  E: TChartEmitter;
begin
  { New-DiagramArtifact checks both before the emitter runs, the SQL index first }
  if not LwArgs(LW_ORM, '', '', '', A) then
    Exit;
  Assert.IsTrue(FindChartQuestion(LANDS_WHERE_ID, E));
  var NoServer:= A;
  NoServer.ServerDbPath:= '';
  Assert.WillRaiseWithMessage(
    procedure
    begin
      E(NoServer, FOutRoot);
    end, EChartsQuestion, 'lands-where needs -ServerDbPath: the SERVER clone (charts\scratch\db\SERVER-MicroniteMW1Service.sqlite); ' +
    '-DbPath is the CLIENT clone');
  var Neither:= NoServer;
  Neither.SqlDbPath:= '';
  Assert.WillRaiseWithMessage(
    procedure
    begin
      E(Neither, FOutRoot);
    end, EChartsQuestion, 'lands-where needs -SqlDbPath: the SQL-script index clone (charts\scratch\db\SQL-drag-lint-sql.sqlite)');
end;

procedure TLandsWhereTests.AnswerNamesTheServerAndSqlIndexes;
var
  A: TQuestionArgs;
begin
  if not LwArgs(LW_ORM, '', '', '', A) then
    Exit;
  var L:= AskChartQuestion(A).Lines;
  Assert.AreEqual<Integer>(LW_LINES, Length(L));
  Assert.AreEqual('INDEX ' + A.ServerDbPath + ' (server)', L[LW_SERVER_INDEX_LINE]);
  Assert.AreEqual('INDEX ' + A.SqlDbPath + ' (sql)', L[LW_SERVER_INDEX_LINE + 1]);
  Assert.AreEqual(LW_CHART, L[LW_SERVER_INDEX_LINE + 2]);
  Assert.AreEqual(LW_LAST_ROW, L[High(L)]);
end;

end.