unit ChartsTests.Questions;  // dl:ok unit-too-large@75ce -- REVIEWED 2026-10-14: one fixture per ported question sharing TQuestionFixture and the clone constants; splitting it is a separate test-layout change, not part of the group C port

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
    function ArgsWithSql(const pQuestion, pTarget, pCloneName, pSqlClone: string; out pArgs: TQuestionArgs): Boolean;
    function Fields(const pChart: TChartResult): string;
    function EmitChart(const pQuestion, pTarget, pCloneName: string; out pChart: TChartResult): Boolean;
    function Refusal(const pQuestion, pTarget, pCloneName: string): string;
    function Answer(const pQuestion, pTarget, pCloneName: string; out pLines: TArray<string>): Boolean;
    procedure CheckAtDepth(const pQuestion, pTarget: string; pDepth: Integer; const pFields, pDotSha: string);
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
    [Test] procedure MissingSqlIndexRefusesAsTheBundlerDoes;
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
    [Test] procedure InterfacePropertyWithTwoTriggers;
    [Test] procedure ProceduresNamingTheColumnAreDrawn;
    [Test] procedure ThreeTriggersAndOnlyNoTableBindings;
    [Test] procedure OtherDataServiceRoutineIsItsOwnCluster;
    [Test] procedure AmbiguousChainStopsBeforeATable;
    [Test] procedure SelectionRefusalsMatchPowerShell;
    [Test] procedure IndexRolesAreChecked;
    [Test] procedure MissingIndexesRefuseAsTheBundlerDoes;
    [Test] procedure AnswerNamesTheServerAndSqlIndexes;
  end;

  [TestFixture]
  TConsumersTests = class(TQuestionFixture)
  private
    function CoArgs(const pTarget, pDb, pSql: string; out pArgs: TQuestionArgs): Boolean;
    procedure Check(const pDb, pTarget, pFields, pDotSha: string; pCap: Integer = 0);
    function CoRefusal(const pTarget, pDb: string; const pSql: string = ''): string;
  public
    [Test] procedure CertainReadersAndWritersOnServer;
    [Test] procedure InferredReadersWideTriggerAndIndexes;
    [Test] procedure CappedClustersDiscloseTheRest;
    [Test] procedure OtherTriggersNameTheTable;
    [Test] procedure ProcedureDeclaredTwiceSaysSo;
    [Test] procedure ClientWithoutFactsNamesCaseOnlyLiterals;
    [Test] procedure IndexWithoutAnySqlSaysSo;
    [Test] procedure InferredWriterWithoutAFact;
    [Test] procedure ColumnNamedByServerRoutines;
    [Test] procedure ColumnBindingsResolvingElsewhereAreCounted;
    [Test] procedure ColumnBindingsThatStopAreCounted;
    [Test] procedure ColumnOnlyTheServerSqlNames;
    [Test] procedure ColumnOnlyAnOlderDeclarationExtracts;
    [Test] procedure ColumnInAnIndexDefinition;
    [Test] procedure SelectionRefusalsMatchPowerShell;
    [Test] procedure IndexRolesAreChecked;
    [Test] procedure MissingSqlIndexRefusesAsTheBundlerDoes;
    [Test] procedure AnswerNamesTheSqlIndex;
  end;

  [TestFixture]
  TExceptionPathsTests = class(TQuestionFixture)
  private
    function FrozenDl(var pArgs: TQuestionArgs): Boolean;
    function FrozenDotSha(const pDot: string): string;
    procedure Check(const pDb, pTarget, pFields, pDotSha: string; pFrozenDl: Boolean = False);
  public
    [Test] procedure CaughtOnOneEdgeAndEscapingOnAnother;
    [Test] procedure CaughtTwoLevelsUp;
    [Test] procedure RecursiveRoutineEvaluatesOnlyItself;
    [Test] procedure StaleFocusIsNotClassified;
    [Test] procedure StaleCallersAndABareExcept;
    [Test] procedure ReRaiseIsWalkedAsItsOwnType;
    [Test] procedure HandlersInBodyAndCaughtByTheCaller;
    [Test] procedure HandlersThatGuardOtherStatements;
    [Test] procedure CaughtAtOnlySomeCallSites;
    [Test] procedure LinesPastTheIntegerRangeKeepTheirNumbers;
    [Test] procedure CallerWalkCappedAt150;
    [Test] procedure ReRaiseOfAVariableWithNoCaller;
    [Test] procedure HandlerClausesPastTheCapAreDisclosed;
    [Test] procedure MayCatchAndCannotCatch;
    [Test] procedure RefusalsMatchPowerShell;
    [Test] procedure WalksThreeLevelsByDefault;
    [Test] procedure HashtableKeyOrderMatchesPowerShell;
  end;

  [TestFixture]
  TWhoCallsTests = class(TQuestionFixture)
  private
    procedure CheckDepth(pDepth: Integer; const pFields, pDotSha: string);
  public
    [Test] procedure MethodMatchesPowerShell;
    [Test] procedure CycleRowAndNameOnlyMatchPowerShell;
    [Test] procedure DepthLimitTouchedIsTruncated;
    [Test] procedure AnswerMatchesPowerShell;
    [Test] procedure EventHandlerIsRefused;
    [Test] procedure UnknownTargetIsRefused;
    [Test] procedure AmbiguousTargetIsRefused;
  end;

  [TestFixture]
  TWhatItCallsTests = class(TQuestionFixture)
  private
    procedure CheckDepth(pDepth: Integer; const pFields, pDotSha: string);
  public
    [Test] procedure MethodMatchesPowerShell;
    [Test] procedure DepthOneIsTruncated;
    [Test] procedure CyclesAtDepthThreeMatchPowerShell;
    [Test] procedure EdgesLeaveTheFocus;
    [Test] procedure AnswerMatchesPowerShell;
    [Test] procedure LeafIsRefused;
    [Test] procedure UnknownTargetIsRefused;
  end;

  [TestFixture]
  TButterflyTests = class(TQuestionFixture)
  private
    function FieldsWithoutPdf(const pChart: TChartResult): string;
  public
    [Test] procedure MethodMatchesPowerShell;
    [Test] procedure DepthOneMatchesPowerShell;
    [Test] procedure ArrowsFollowTheTree;
    [Test] procedure NoDuplicateRowPerSide;
    [Test] procedure AnswerMatchesPowerShell;
    [Test] procedure UnknownTargetIsRefused;
  end;

  [TestFixture]
  THierarchyTests = class(TQuestionFixture)
  public
    [Test] procedure TypeMatchesPowerShell;
    [Test] procedure MissingFocusDrawsDescendants;
    [Test] procedure CollidingAncestorIsUnanchored;
    [Test] procedure AnswerMatchesPowerShell;
    [Test] procedure UnknownTypeIsRefused;
    [Test] procedure AmbiguousTypeIsRefused;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, System.Hash, System.RegularExpressions, DRagLint.Charts.ReportHeader, DRagLint.Charts.Ask,
  DRagLint.Charts.Index, DRagLint.Charts.Q.TouchesTables, DRagLint.Charts.Q.ClassSurface, DRagLint.Charts.Q.ExceptionPaths,
  DRagLint.Charts.Q.WhoCalls,
  DRagLint.Charts.Q.Butterfly, DRagLint.Charts.Q.Hierarchy, System.Generics.Collections,
  DRagLint.Charts.Exceptions, DRagLint.Charts.Text, DRagLint.Charts.Tools, FireDAC.Comp.Client, Winapi.Windows;

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
  WC_TARGET = 'Blueprint4.ViewModel.TBlueprint_ViewModel.SendDeltaOperation';
  WC_FIELDS = 'Direction="callers",Question="who-calls",Rows=9,Callers=9,Callees=0,NodeCount=10,Cycles=0,MaxDepth=1.0,Truncated=false,Clusters=1,NameMatches=9,NameOnly=0,NameRendered=false,ClickTargets=10,Expected=10,AllClickable=true';
  WC_DOT_SHA = 'db146e8ebfb5296a27fb16979197e7f9a1c865d9cd277edc255d69a3cf49fa24';
  WC_LINES = 15;
  WC_CYCLE_TARGET = 'Blueprint4.ViewModel.TBlueprint_ViewModel.ReserveNextID';
  WC_CYCLE_DEPTH = 3;
  WC_CYCLE_FIELDS = 'Direction="callers",Question="who-calls",Rows=10,Callers=10,Callees=0,NodeCount=11,Cycles=1,MaxDepth=2.0,Truncated=false,Clusters=2,NameMatches=18,NameOnly=9,NameRendered=false,ClickTargets=11,Expected=11,AllClickable=true';
  WC_CYCLE_DOT_SHA = 'a8c534920dc06417affc8254c33ec9a34e0b688ffdcac2f9544c8ba4e627c890';
  WC_D1_DEPTH = 1;
  WC_D1_FIELDS = 'Direction="callers",Question="who-calls",Rows=9,Callers=9,Callees=0,NodeCount=10,Cycles=0,MaxDepth=1.0,Truncated=true,Clusters=1,NameMatches=18,NameOnly=9,NameRendered=false,ClickTargets=10,Expected=10,AllClickable=true';
  WC_D1_DOT_SHA = 'a9fb422c9009732f94971e6d8fe88eefae41a82a8f3158c3df9650a734f0bbcc';
  WC_EVENT_TARGET = 'uMain.TfrmMAIN.FormCreate';
  WIC_TARGET = 'Blueprint4.ViewModel.TBlueprint_ViewModel.SendDeltaOperation';
  WIC_FIELDS = 'Direction="callees",Question="what-it-calls",Rows=9,Callers=0,Callees=9,NodeCount=10,Cycles=0,MaxDepth=2.0,Truncated=true,Clusters=5,NameMatches=null,NameOnly=null,NameRendered=false,ClickTargets=10,Expected=10,AllClickable=true';
  WIC_DOT_SHA = '44e51833342d4b21eaa858edae414c6f4786c886fc8f52856327f5000c6a99b9';
  WIC_LINES = 15;
  WIC_D1_DEPTH = 1;
  WIC_D1_FIELDS = 'Direction="callees",Question="what-it-calls",Rows=2,Callers=0,Callees=2,NodeCount=3,Cycles=0,MaxDepth=1.0,Truncated=true,Clusters=2,NameMatches=null,NameOnly=null,NameRendered=false,ClickTargets=3,Expected=3,AllClickable=true';
  WIC_D1_DOT_SHA = '6af60a47cd68157628ba8eb118af76eb33be2a742db4aaf54c859d682c9783b0';
  WIC_D3_DEPTH = 3;
  WIC_D3_FIELDS = 'Direction="callees",Question="what-it-calls",Rows=18,Callers=0,Callees=18,NodeCount=19,Cycles=5,MaxDepth=3.0,Truncated=true,Clusters=8,NameMatches=null,NameOnly=null,NameRendered=false,ClickTargets=19,Expected=19,AllClickable=true';
  WIC_D3_DOT_SHA = '267f441b767c6c5513cf9c8a66230286ea57869198052904b0b7b1b1ea1625e4';
  WIC_LEAF_TARGET = 'AssignGroups.ViewModel.TAssignGroupsViewModel.CanAddGroup';
  BF_TARGET = 'Blueprint4.ViewModel.TBlueprint_ViewModel.SendDeltaOperation';
  BF_FIELDS = 'Callers=9,Callees=9,Edges=18,FocusIn=9,FocusOut=2,ClickTargets=19,Expected=19,AllClickable=true,ExportSvg=25143,ExportPng=152765';
  BF_DOT_SHA = '9901072e0c3a63637d8f4834f555380b881e9406babe75e2eb2b5fcb62bc40a6';
  BF_LINES = 24;
  BF_D1_DEPTH = 1;
  BF_D1_FIELDS = 'Callers=9,Callees=2,Edges=11,FocusIn=9,FocusOut=2,ClickTargets=12,Expected=12,AllClickable=true,ExportSvg=15504,ExportPng=96589';
  BF_D1_DOT_SHA = 'fda13591d2006ad492c2565b3ec0b81473080a67505ac21762dbeedf5721a101';
  BF_D6_TARGET = 'DRagLint.Index.CallResolver.TCallResolver.ResolveEnumValueRead';
  BF_FOCUS_IN = 9;
  BF_FOCUS_OUT = 2;
  HI_TARGET = 'TBlueprint_ViewModel';
  HI_FIELDS = 'Resolved="Blueprint4.ViewModel.TBlueprint_ViewModel",Kind="class",FocusDeclared=true,Ancestors=2,UnresolvedAnc=1,Descendants=0,ShownAncestors=2,ShownDescendants=0,HiddenAncestors=0,HiddenDescendants=0,Collisions=0,Unlocatable=0,SelfRefs=0,ClickTargets=2,Expected=2,AllClickable=true';
  HI_DOT_SHA = 'ea5a318048c49d672f53eba8e08fcd106da0f4f5c2fffc546ebe30cbbdb71029';
  HI_LINES = 7;
  HI_TARGET_LINE = '  TARGET Blueprint4.ViewModel.TBlueprint_ViewModel @Blueprint4.ViewModel.pas:57';
  HI_RTL_TARGET = 'TInterfacedObject';
  HI_RTL_FIELDS = 'Resolved=null,Kind=null,FocusDeclared=false,Ancestors=0,UnresolvedAnc=0,Descendants=145,ShownAncestors=0,ShownDescendants=20,HiddenAncestors=0,HiddenDescendants=125,Collisions=0,Unlocatable=0,SelfRefs=0,ClickTargets=20,Expected=20,AllClickable=true';
  HI_RTL_DOT_SHA = 'fc98f8fd06dc072d29ca4abee9a37a6e19bf16f422d498dd8bfa0a7d01973ddd';
  HI_COLLIDE_TARGET = 'TDataService_DRA1_CLIENT';
  HI_COLLIDE_FIELDS = 'Resolved="uDRA1_CLIENT.TDataService_DRA1_CLIENT",Kind="class",FocusDeclared=true,Ancestors=2,UnresolvedAnc=1,Descendants=0,ShownAncestors=2,ShownDescendants=0,HiddenAncestors=0,HiddenDescendants=0,Collisions=1,Unlocatable=0,SelfRefs=0,ClickTargets=1,Expected=1,AllClickable=true';
  HI_UNKNOWN = 'NoSuchType';
  HI_AMBIGUOUS = 'IDataService';
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
  LW_TAIL = LW_CONV + ',' + LW_NEWEST_OF_TWO + LW_SRV;
  LW_IFACE = 'iCAUSFAIL.ImcCAUSFAIL.SYSTID';
  LW_IFACE_FIELDS = 'TestChart=false,ClientOutcomes="column",IndexBindColumn=443,Selection="iCAUSFAIL.ImcCAUSFAIL.SYSTID",Kind="orm",' +
    'Property="iCAUSFAIL.ImcCAUSFAIL.SYSTID",Table="CAUSFAIL",TableColumn="CAUSFAIL.SYSTID",ColumnState="yes",ChainOutcome="",StopReason="",' +
    'ServerClass="TDataService_CAUSFAIL_SERVER",ServerRows=4,ServerWrite="PrepareSaveQuery:124,Save:231",ServerRead="PrepareLoadQuery:109,Load:161",' +
    'ServerOther="",ServerElsewhere=1,Triggers=2,TriggerNames="CAUSFAIL_BIU5@MS5.SQL:15,CAUSFAIL_BUD0@MS6.SQL:44",TriggersStale=0,Procedures=0,' +
    'ProcedureNames="",ClientBindings=1,ClientRows="uCausFailForm.dfm:53:colSYSTID",ClientOther=4,' + LW_TAIL +
    ',ClickTargets=10,Expected=10,AllClickable=true';
  LW_IFACE_DOT_SHA = '2c076cc4ba47e28a36fb1779372ff6b05e6303911d46ff51d38346e6d649701e';
  LW_PROC = 'uCAUSFAIL.TmcCAUSFAIL.ID';
  LW_PROC_FIELDS = 'TestChart=false,ClientOutcomes="column",IndexBindColumn=443,Selection="uCAUSFAIL.TmcCAUSFAIL.ID",Kind="orm",' +
    'Property="uCAUSFAIL.TmcCAUSFAIL.ID",Table="CAUSFAIL",TableColumn="CAUSFAIL.ID",ColumnState="yes",ChainOutcome="",StopReason="",' +
    'ServerClass="TDataService_CAUSFAIL_SERVER",ServerRows=4,ServerWrite="PrepareSaveQuery:124,Save:227",ServerRead="PrepareLoadQuery:109,Load:152",' +
    'ServerOther="",ServerElsewhere=1,Triggers=1,TriggerNames="CAUSFAIL_BIU0@MS6.SQL:34",TriggersStale=0,Procedures=2,' +
    'ProcedureNames="SP_GET_CAUSFAIL_ID,SP_MAXID_FORALL_TABLES",ClientBindings=1,ClientRows="uCausFailForm.dfm:44:colID",ClientOther=34,' + LW_TAIL +
    ',ClickTargets=11,Expected=11,AllClickable=true';
  LW_PROC_DOT_SHA = '0d73975afba4ac1b222377c4f43c3777fcc75cde04a25e9ee485b3261a1f1951';
  LW_TRIGS = 'uMACHINES.TmcMACHINES.MACHINEID';
  LW_TRIGS_FIELDS = 'TestChart=false,ClientOutcomes="column",IndexBindColumn=443,Selection="uMACHINES.TmcMACHINES.MACHINEID",Kind="orm",' +
    'Property="uMACHINES.TmcMACHINES.MACHINEID",Table="MACHINES",TableColumn="MACHINES.MACHINEID",ColumnState="yes",ChainOutcome="",StopReason="",' +
    'ServerClass="TDataService_MACHINES_SERVER",ServerRows=4,ServerWrite="PrepareSaveQuery:132,Save:281",ServerRead="PrepareLoadQuery:113,Load:164",' +
    'ServerOther="",ServerElsewhere=1,Triggers=3,TriggerNames="MACHINES_AI10@MS5.SQL:620,MACHINES_AU10@MS5.SQL:629,MACHINES_BDU0@MS6.SQL:405",' +
    'TriggersStale=0,Procedures=2,ProcedureNames="MACHINESLASTSTOP,MACHINESLASTSTOP2",ClientBindings=1,ClientRows="uMachineListForm.dfm:43:colMACHINEID",' +
    'ClientOther=1,' + LW_TAIL + ',ClickTargets=13,Expected=13,AllClickable=true';
  LW_TRIGS_DOT_SHA = '11c1acf06f0c3d16ccffbb88d3ad6e411330e6b9807023015b9c782da898a124';
  LW_OTHER = 'uOPTRLIST.TmcOPTRLIST.XOPERATOR';
  LW_OTHER_FIELDS = 'TestChart=false,ClientOutcomes="column",IndexBindColumn=443,Selection="uOPTRLIST.TmcOPTRLIST.XOPERATOR",Kind="orm",' +
    'Property="uOPTRLIST.TmcOPTRLIST.XOPERATOR",Table="OPTRLIST",TableColumn="OPTRLIST.XOPERATOR",ColumnState="yes",ChainOutcome="",StopReason="",' +
    'ServerClass="TDataService_OPTRLIST_SERVER",ServerRows=5,ServerWrite="PrepareSaveQuery:132,Save:243",ServerRead="PrepareLoadQuery:115,Load:160",' +
    'ServerOther="FindOperatorName:364",ServerElsewhere=3,Triggers=1,TriggerNames="OPTRLIST_BDU0@MS6.SQL:548",TriggersStale=0,Procedures=0,' +
    'ProcedureNames="",ClientBindings=1,ClientRows="OperatorList.dfm:80:colXOPERATOR",ClientOther=1,' + LW_TAIL +
    ',ClickTargets=10,Expected=10,AllClickable=true';
  LW_OTHER_DOT_SHA = '22376e6af57281a3b8ff248a1a80aa3d6e3c6e43f21a1ffe5371096a4da93863';
  LW_AMBIG = 'frmDefineSerialNumbers.cxGrid1DBTableView1SID1';
  LW_AMBIG_FIELDS = 'TestChart=false,ClientOutcomes="",IndexBindColumn=443,Selection="frmDefineSerialNumbers.cxGrid1DBTableView1SID1",' +
    'Kind="dfm",Property="",Table=null,TableColumn="",ColumnState="n/a",ChainOutcome="ambiguous",StopReason="the chain stops before a ' +
    'table (many): uDefineSerialNumbers.ViewModel.pas names 3 tables in upper case; 3 of them hold all 2 bound column(s)",ServerClass=null,' +
    'ServerRows=0,ServerWrite="",ServerRead="",ServerOther="",ServerElsewhere=0,Triggers=0,TriggerNames="",TriggersStale=0,Procedures=0,' +
    'ProcedureNames="",ClientBindings=0,ClientRows="",ClientOther=0,' + LW_CONV + ',ColumnLabel="",' + LW_SRV +
    ',ClickTargets=5,Expected=5,AllClickable=true';
  LW_AMBIG_DOT_SHA = '647097e3b5d98896e178d81e61f37f2eb3ca7e73c44e695414b1127099412ad0';
  LW_NOT_ORM = 'not an ORM object property (class is not Tmc<T>) and not a DFM-bound field';
  LW_LINES = 17;
  LW_SERVER_INDEX_LINE = 4;
  LW_CHART = 'CHART lands-where uCAUSFAIL.TmcCAUSFAIL.REASON -- 4 server DataService rows / 1 triggers touching the column';
  LW_LAST_ROW = '  ... positional Fields[i] / Params[i] reads are not shown -- they never name the column';
  FF_LINES = 13;
  FF_SQL_INDEX_LINE = 4;
  FF_CHART_LINE = 5;
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
  CO_ID = 'consumers';
  CO_SMALL_CAP = 4;
  CO_NOSQL_CLONE = 'TESTS-PdfOcrImportTests.sqlite';
  CO_DL_CLONE = 'DL-drag-lint.sqlite';
  CO_SRV = 'CAUSFAIL';
  CO_SRV_FIELDS = 'TestChart=false,Table="CAUSFAIL",Column=null,ColumnOlderOnly=false,ColumnState="",ColumnLabel="",ColumnLine="",' +
    'Declarations=2,Columns=4,Readers=1,Writers=1,ReaderUnits=0,WriterUnits=0,CertainReaders=1,CertainWriters=1,' +
    'InferredReaders=0,InferredWriters=0,InferredReaderNames="",' +
    'CertainWriterNames="uCAUSFAIL_SERVER.TDataService_CAUSFAIL_SERVER.PrepareSaveQuery",UnitLevelUnits=0,ByNameUnits=1,' +
    'ByNameLiterals=6.0,ByNameCaseOnly="",ByNameLines="uCAUSFAIL_SERVER:71+134+188+211+252+283",Triggers=3,' +
    'TriggerNames="CAUSFAIL_BIU0@MS6.SQL:34,CAUSFAIL_BIU5@MS5.SQL:15,CAUSFAIL_BUD0@MS6.SQL:44",OtherTriggers=0,' +
    'Procedures=2,ProcedureNames="SP_GET_CAUSFAIL_ID,SP_MAXID_FORALL_TABLES",ProcsUnscanned=0,ProcBodies="168/168",' +
    'Indexes=0,ServerRoutines=0,ServerRoutineNames="",SilentRoutines=0,ColumnTriggers=0,ColumnTriggerNames="",' +
    'ColumnTriggersStale=0,ColumnTriggersNoBody=0,ColumnProcedures=0,ColumnIndexes=0,IndexBindings=0,DrawnBindings=0,' +
    'DrawnBindingRows="",BindingsElsewhere=0.0,BindingsUnresolved=0.0,BindingsStale=0,IndexReadFacts=112,' +
    'IndexWriteFacts=148,IndexFactSymbols=250,IndexFactReadTables=104,IndexVerbLiterals=791,IndexFromJoinTables=133,' +
    'NoSqlFacts=false,NoSql=false,Clusters=6,ClickTargets=9,Expected=9,AllClickable=true';
  CO_SRV_DOT_SHA = 'dbd3ed2ec3cb9793ac20ed7d95f72013cf106f32b9f39361e75e4a6cb288a6f2';
  CO_FOLDERS = 'FOLDERS';
  CO_FOLDERS_FIELDS = 'TestChart=false,Table="FOLDERS",Column=null,ColumnOlderOnly=false,ColumnState="",ColumnLabel="",ColumnLine="",' +
    'Declarations=2,Columns=79,Readers=4,Writers=2,ReaderUnits=0,WriterUnits=0,CertainReaders=1,CertainWriters=2,' +
    'InferredReaders=3,InferredWriters=0,InferredReaderNames="uFOLDERS_SERVER.TDataService_FOLDERS_SERVER.PrepareLoadQuery,' +
    'uPipeSessionBuilder.TPipeSessionBuilder.HandleCreateFolder,' +
    'uPipeSessionBuilder.TPipeSessionBuilder.HandlePrePlanPreset",' +
    'CertainWriterNames="uFOLDERS_SERVER.TDataService_FOLDERS_SERVER.PrepareSaveQuery,' +
    'uPipeSessionBuilder.TPipeSessionBuilder.HandleCreateFolder",UnitLevelUnits=0,ByNameUnits=2,ByNameLiterals=7.0,' +
    'ByNameCaseOnly="",ByNameLines="uFOLDERS_SERVER:72+156+285+308+424+455,uPipeSessionBuilder:747",Triggers=3,' +
    'TriggerNames="FOLDERS_BD0@MS6.SQL:276,FOLDERS_BIU0@MS6.SQL:285,FOLDERS_BIU5@MS5.SQL:269",OtherTriggers=0,Procedures=1,' +
    'ProcedureNames="SP_MAXID_FORALL_TABLES",ProcsUnscanned=0,ProcBodies="168/168",Indexes=2,ServerRoutines=0,' +
    'ServerRoutineNames="",SilentRoutines=0,ColumnTriggers=0,ColumnTriggerNames="",ColumnTriggersStale=0,' +
    'ColumnTriggersNoBody=0,ColumnProcedures=0,ColumnIndexes=0,IndexBindings=0,DrawnBindings=0,DrawnBindingRows="",' +
    'BindingsElsewhere=0.0,BindingsUnresolved=0.0,BindingsStale=0,IndexReadFacts=112,IndexWriteFacts=148,' +
    'IndexFactSymbols=250,IndexFactReadTables=104,IndexVerbLiterals=791,IndexFromJoinTables=133,NoSqlFacts=false,' +
    'NoSql=false,Clusters=8,ClickTargets=15,Expected=15,AllClickable=true';
  CO_FOLDERS_DOT_SHA = 'c1fb9dd5356efea894620104e40e8540ad84dfd6e4375c2e2c8725f03892f040';
  CO_CAPPED = 'MSCLIST';
  CO_CAPPED_FIELDS = 'TestChart=false,Table="MSCLIST",Column=null,ColumnOlderOnly=false,ColumnState="",ColumnLabel="",ColumnLine="",' +
    'Declarations=2,Columns=123,Readers=15,Writers=9,ReaderUnits=0,WriterUnits=0,CertainReaders=6,CertainWriters=5,' +
    'InferredReaders=9,InferredWriters=4,InferredReaderNames="uMSCLIST_SERVER.TDataService_MSCLIST_SERVER.PrepareLoadQuery,' +
    'uPipeSessionBuilder.TPipeSessionBuilder.HandleComputeSchedule.BuildFinalFamily,' +
    'uPipeSessionBuilder.TPipeSessionBuilder.HandleComputeSchedule.BuildSimpleKind,' +
    'uPipeSessionBuilder.TPipeSessionBuilder.HandleComputeSchedule.BuildSPC,' +
    'uPipeSessionBuilder.TPipeSessionBuilder.HandleComputeSchedule.RollUpGroupVisualFlags.RollOne,' +
    'uPipeSessionBuilder.TPipeSessionBuilder.HandleCopyOperation.ClonePlans,' +
    'uPipeSessionBuilder.TPipeSessionBuilder.HandleDeleteCharacteristic,' +
    'uPipeSessionBuilder.TPipeSessionBuilder.HandlePrePlanPreset,' +
    'uPipeSessionBuilder.TPipeSessionBuilder.HandleVerifyFolder",' +
    'CertainWriterNames="uMSCLIST_SERVER.TDataService_MSCLIST_SERVER.PrepareSaveQuery,' +
    'uPipeSessionBuilder.TPipeSessionBuilder.HandleComputeSchedule,' +
    'uPipeSessionBuilder.TPipeSessionBuilder.HandleComputeSchedule.BuildInProcess,' +
    'uPipeSessionBuilder.TPipeSessionBuilder.HandleDeleteCharacteristic,' +
    'uPipeSessionBuilder.TPipeSessionBuilder.HandleVerifyFolder",UnitLevelUnits=0,ByNameUnits=1,ByNameLiterals=6.0,' +
    'ByNameCaseOnly="",ByNameLines="uMSCLIST_SERVER:72+163+336+359+519+550",Triggers=2,' +
    'TriggerNames="MSCLIST_BIU0@MS6.SQL:467,MSCLIST_BIU5@MS5.SQL:696",OtherTriggers=0,Procedures=0,ProcedureNames="",' +
    'ProcsUnscanned=0,ProcBodies="168/168",Indexes=0,ServerRoutines=0,ServerRoutineNames="",SilentRoutines=0,' +
    'ColumnTriggers=0,ColumnTriggerNames="",ColumnTriggersStale=0,ColumnTriggersNoBody=0,ColumnProcedures=0,' +
    'ColumnIndexes=0,IndexBindings=0,DrawnBindings=0,DrawnBindingRows="",BindingsElsewhere=0.0,BindingsUnresolved=0.0,' +
    'BindingsStale=0,IndexReadFacts=112,IndexWriteFacts=148,IndexFactSymbols=250,IndexFactReadTables=104,' +
    'IndexVerbLiterals=791,IndexFromJoinTables=133,NoSqlFacts=false,NoSql=false,Clusters=7,ClickTargets=20,Expected=20,' +
    'AllClickable=true';
  CO_CAPPED_DOT_SHA = 'abf5d6e0f4d45306fba3ec61b456bbfe2536d5244b44cb690596d927e6c9ea91';
  CO_OTHER = 'MACHINESTAT';
  CO_OTHER_FIELDS = 'TestChart=false,Table="MACHINESTAT",Column=null,ColumnOlderOnly=false,ColumnState="",ColumnLabel="",ColumnLine="",' +
    'Declarations=2,Columns=97,Readers=1,Writers=1,ReaderUnits=0,WriterUnits=0,CertainReaders=0,CertainWriters=1,' +
    'InferredReaders=1,InferredWriters=0,' +
    'InferredReaderNames="uMACHINESTAT_SERVER.TDataService_MACHINESTAT_SERVER.PrepareLoadQuery",' +
    'CertainWriterNames="uMACHINESTAT_SERVER.TDataService_MACHINESTAT_SERVER.PrepareSaveQuery",UnitLevelUnits=0,' +
    'ByNameUnits=1,ByNameLiterals=6.0,ByNameCaseOnly="",ByNameLines="uMACHINESTAT_SERVER:72+157+304+327+464+495",' +
    'Triggers=0,TriggerNames="",OtherTriggers=2,Procedures=0,ProcedureNames="",ProcsUnscanned=0,ProcBodies="168/168",' +
    'Indexes=0,ServerRoutines=0,ServerRoutineNames="",SilentRoutines=0,ColumnTriggers=0,ColumnTriggerNames="",' +
    'ColumnTriggersStale=0,ColumnTriggersNoBody=0,ColumnProcedures=0,ColumnIndexes=0,IndexBindings=0,DrawnBindings=0,' +
    'DrawnBindingRows="",BindingsElsewhere=0.0,BindingsUnresolved=0.0,BindingsStale=0,IndexReadFacts=112,' +
    'IndexWriteFacts=148,IndexFactSymbols=250,IndexFactReadTables=104,IndexVerbLiterals=791,IndexFromJoinTables=133,' +
    'NoSqlFacts=false,NoSql=false,Clusters=5,ClickTargets=6,Expected=6,AllClickable=true';
  CO_OTHER_DOT_SHA = 'edcc7af7017e29513873437f506104ececa6f73a47406ed31ac5b5e460a415af';
  CO_TWICE = 'GONOFF';
  CO_TWICE_FIELDS = 'TestChart=false,Table="GONOFF",Column=null,ColumnOlderOnly=false,ColumnState="",ColumnLabel="",ColumnLine="",' +
    'Declarations=2,Columns=26,Readers=1,Writers=1,ReaderUnits=0,WriterUnits=0,CertainReaders=0,CertainWriters=1,' +
    'InferredReaders=1,InferredWriters=0,InferredReaderNames="uGONOFF_SERVER.TDataService_GONOFF_SERVER.PrepareLoadQuery",' +
    'CertainWriterNames="uGONOFF_SERVER.TDataService_GONOFF_SERVER.PrepareSaveQuery",UnitLevelUnits=0,ByNameUnits=1,' +
    'ByNameLiterals=6.0,ByNameCaseOnly="",ByNameLines="uGONOFF_SERVER:72+142+218+241+304+335",Triggers=2,' +
    'TriggerNames="GONOFF_BIU0@MS6.SQL:340,GONOFF_BIU5@MS5.SQL:413",OtherTriggers=0,Procedures=3,ProcedureNames="LASTSTOP,' +
    'SP_GET_GONOFF_ID,SP_MAXID_FORALL_TABLES",ProcsUnscanned=0,ProcBodies="168/168",Indexes=2,ServerRoutines=0,' +
    'ServerRoutineNames="",SilentRoutines=0,ColumnTriggers=0,ColumnTriggerNames="",ColumnTriggersStale=0,' +
    'ColumnTriggersNoBody=0,ColumnProcedures=0,ColumnIndexes=0,IndexBindings=0,DrawnBindings=0,DrawnBindingRows="",' +
    'BindingsElsewhere=0.0,BindingsUnresolved=0.0,BindingsStale=0,IndexReadFacts=112,IndexWriteFacts=148,' +
    'IndexFactSymbols=250,IndexFactReadTables=104,IndexVerbLiterals=791,IndexFromJoinTables=133,NoSqlFacts=false,' +
    'NoSql=false,Clusters=7,ClickTargets=11,Expected=11,AllClickable=true';
  CO_TWICE_DOT_SHA = '6c8e59c83e20060d7eb732fd9faffe6b89a11998408b953a2bd0076070cae900';
  CO_CLIENT = 'FOLDERS';
  CO_CLIENT_FIELDS = 'TestChart=false,Table="FOLDERS",Column=null,ColumnOlderOnly=false,ColumnState="",ColumnLabel="",ColumnLine="",' +
    'Declarations=2,Columns=79,Readers=0,Writers=0,ReaderUnits=0,WriterUnits=0,CertainReaders=0,CertainWriters=0,' +
    'InferredReaders=0,InferredWriters=0,InferredReaderNames="",CertainWriterNames="",UnitLevelUnits=0,ByNameUnits=6,' +
    'ByNameLiterals=7.0,ByNameCaseOnly="''Folders'' uJobList.pas:552",ByNameLines="Blueprint4:815,' +
    'Blueprint4.ViewModel:1221,uJobList:439,uJobList.ViewModel:288,uSetupDefaultsFrm:2413+2427,uFieldsInfoCache:158",' +
    'Triggers=3,TriggerNames="FOLDERS_BD0@MS6.SQL:276,FOLDERS_BIU0@MS6.SQL:285,FOLDERS_BIU5@MS5.SQL:269",OtherTriggers=0,' +
    'Procedures=1,ProcedureNames="SP_MAXID_FORALL_TABLES",ProcsUnscanned=0,ProcBodies="168/168",Indexes=2,ServerRoutines=0,' +
    'ServerRoutineNames="",SilentRoutines=0,ColumnTriggers=0,ColumnTriggerNames="",ColumnTriggersStale=0,' +
    'ColumnTriggersNoBody=0,ColumnProcedures=0,ColumnIndexes=0,IndexBindings=0,DrawnBindings=0,DrawnBindingRows="",' +
    'BindingsElsewhere=0.0,BindingsUnresolved=0.0,BindingsStale=0,IndexReadFacts=0,IndexWriteFacts=0,IndexFactSymbols=0,' +
    'IndexFactReadTables=0,IndexVerbLiterals=7,IndexFromJoinTables=0,NoSqlFacts=true,NoSql=false,Clusters=5,' +
    'ClickTargets=13,Expected=13,AllClickable=true';
  CO_CLIENT_DOT_SHA = '706aa0754a94b88a3defb68e0c98589e32f8b6af79fc97bc026127edd4bb431b';
  CO_NOSQL = 'CAUSFAIL';
  CO_NOSQL_FIELDS = 'TestChart=false,Table="CAUSFAIL",Column=null,ColumnOlderOnly=false,ColumnState="",ColumnLabel="",ColumnLine="",' +
    'Declarations=2,Columns=4,Readers=0,Writers=0,ReaderUnits=0,WriterUnits=0,CertainReaders=0,CertainWriters=0,' +
    'InferredReaders=0,InferredWriters=0,InferredReaderNames="",CertainWriterNames="",UnitLevelUnits=0,ByNameUnits=0,' +
    'ByNameLiterals=0,ByNameCaseOnly="",ByNameLines="",Triggers=3,TriggerNames="CAUSFAIL_BIU0@MS6.SQL:34,' +
    'CAUSFAIL_BIU5@MS5.SQL:15,CAUSFAIL_BUD0@MS6.SQL:44",OtherTriggers=0,Procedures=2,ProcedureNames="SP_GET_CAUSFAIL_ID,' +
    'SP_MAXID_FORALL_TABLES",ProcsUnscanned=0,ProcBodies="168/168",Indexes=0,ServerRoutines=0,ServerRoutineNames="",' +
    'SilentRoutines=0,ColumnTriggers=0,ColumnTriggerNames="",ColumnTriggersStale=0,ColumnTriggersNoBody=0,' +
    'ColumnProcedures=0,ColumnIndexes=0,IndexBindings=0,DrawnBindings=0,DrawnBindingRows="",BindingsElsewhere=0.0,' +
    'BindingsUnresolved=0.0,BindingsStale=0,IndexReadFacts=0,IndexWriteFacts=0,IndexFactSymbols=0,IndexFactReadTables=0,' +
    'IndexVerbLiterals=0,IndexFromJoinTables=0,NoSqlFacts=true,NoSql=true,Clusters=3,ClickTargets=6,Expected=6,' +
    'AllClickable=true';
  CO_NOSQL_DOT_SHA = '5558a4233e731661fa56ff69259fef891eb77601764f2186bda760a2de8d1b55';
  CO_DL = 'FIB$ENUMVALUES';
  CO_DL_FIELDS = 'TestChart=false,Table="FIB$ENUMVALUES",Column=null,ColumnOlderOnly=false,ColumnState="",ColumnLabel="",ColumnLine="",' +
    'Declarations=1,Columns=6,Readers=1,Writers=1,ReaderUnits=0,WriterUnits=0,CertainReaders=0,CertainWriters=0,' +
    'InferredReaders=1,InferredWriters=1,InferredReaderNames="DRagLint.Sql.FbSnapshot.TFbSnapshot.Run",' +
    'CertainWriterNames="",UnitLevelUnits=0,ByNameUnits=0,ByNameLiterals=0,ByNameCaseOnly="",ByNameLines="",Triggers=0,' +
    'TriggerNames="",OtherTriggers=0,Procedures=0,ProcedureNames="",ProcsUnscanned=0,ProcBodies="168/168",Indexes=0,' +
    'ServerRoutines=0,ServerRoutineNames="",SilentRoutines=0,ColumnTriggers=0,ColumnTriggerNames="",ColumnTriggersStale=0,' +
    'ColumnTriggersNoBody=0,ColumnProcedures=0,ColumnIndexes=0,IndexBindings=0,DrawnBindings=0,DrawnBindingRows="",' +
    'BindingsElsewhere=0.0,BindingsUnresolved=0.0,BindingsStale=0,IndexReadFacts=99,IndexWriteFacts=27,' +
    'IndexFactSymbols=113,IndexFactReadTables=20,IndexVerbLiterals=462,IndexFromJoinTables=3,NoSqlFacts=false,NoSql=false,' +
    'Clusters=3,ClickTargets=3,Expected=3,AllClickable=true';
  CO_DL_DOT_SHA = 'b685fa89511d7670f45aac41a49b72cec0ba972783bb92c47677458cfc31e996';
  CO_SRVCOL = 'CAUSFAIL.REASON';
  CO_SRVCOL_FIELDS = 'TestChart=false,Table="CAUSFAIL",Column="REASON",ColumnOlderOnly=false,ColumnState="yes",' +
    'ColumnLabel="[certain] a column of the newest of 2 declaration(s), MS1.SQL",ColumnLine="MS1.SQL:1411",Declarations=2,' +
    'Columns=4,Readers=1,Writers=1,ReaderUnits=0,WriterUnits=0,CertainReaders=1,CertainWriters=1,InferredReaders=0,' +
    'InferredWriters=0,InferredReaderNames="",' +
    'CertainWriterNames="uCAUSFAIL_SERVER.TDataService_CAUSFAIL_SERVER.PrepareSaveQuery",UnitLevelUnits=0,ByNameUnits=1,' +
    'ByNameLiterals=6.0,ByNameCaseOnly="",ByNameLines="uCAUSFAIL_SERVER:71+134+188+211+252+283",Triggers=3,' +
    'TriggerNames="CAUSFAIL_BIU0@MS6.SQL:34,CAUSFAIL_BIU5@MS5.SQL:15,CAUSFAIL_BUD0@MS6.SQL:44",OtherTriggers=0,' +
    'Procedures=2,ProcedureNames="SP_GET_CAUSFAIL_ID,SP_MAXID_FORALL_TABLES",ProcsUnscanned=0,ProcBodies="168/168",' +
    'Indexes=0,ServerRoutines=2,ServerRoutineNames="uCAUSFAIL_SERVER.TDataService_CAUSFAIL_SERVER.PrepareLoadQuery,' +
    'uCAUSFAIL_SERVER.TDataService_CAUSFAIL_SERVER.PrepareSaveQuery",SilentRoutines=0,ColumnTriggers=1,' +
    'ColumnTriggerNames="CAUSFAIL_BIU5",ColumnTriggersStale=0,ColumnTriggersNoBody=0,ColumnProcedures=0,ColumnIndexes=0,' +
    'IndexBindings=0,DrawnBindings=0,DrawnBindingRows="",BindingsElsewhere=0.0,BindingsUnresolved=0.0,BindingsStale=0,' +
    'IndexReadFacts=112,IndexWriteFacts=148,IndexFactSymbols=250,IndexFactReadTables=104,IndexVerbLiterals=791,' +
    'IndexFromJoinTables=133,NoSqlFacts=false,NoSql=false,Clusters=4,ClickTargets=4,Expected=4,AllClickable=true';
  CO_SRVCOL_DOT_SHA = '882f41545ee720889c23ed2707fe2166eb0b8ea0e401b93b59c756680cc4992f';
  CO_BIND = 'CAUSFAIL.REASON';
  CO_BIND_FIELDS = 'TestChart=false,Table="CAUSFAIL",Column="REASON",ColumnOlderOnly=false,ColumnState="yes",' +
    'ColumnLabel="[certain] a column of the newest of 2 declaration(s), MS1.SQL",ColumnLine="MS1.SQL:1411",Declarations=2,' +
    'Columns=4,Readers=0,Writers=0,ReaderUnits=0,WriterUnits=0,CertainReaders=0,CertainWriters=0,InferredReaders=0,' +
    'InferredWriters=0,InferredReaderNames="",CertainWriterNames="",UnitLevelUnits=0,ByNameUnits=1,ByNameLiterals=3.0,' +
    'ByNameCaseOnly="",ByNameLines="uCausFail.ViewModel:37+258+259",Triggers=3,TriggerNames="CAUSFAIL_BIU0@MS6.SQL:34,' +
    'CAUSFAIL_BIU5@MS5.SQL:15,CAUSFAIL_BUD0@MS6.SQL:44",OtherTriggers=0,Procedures=2,ProcedureNames="SP_GET_CAUSFAIL_ID,' +
    'SP_MAXID_FORALL_TABLES",ProcsUnscanned=0,ProcBodies="168/168",Indexes=0,ServerRoutines=0,ServerRoutineNames="",' +
    'SilentRoutines=0,ColumnTriggers=1,ColumnTriggerNames="CAUSFAIL_BIU5",ColumnTriggersStale=0,ColumnTriggersNoBody=0,' +
    'ColumnProcedures=0,ColumnIndexes=0,IndexBindings=7,DrawnBindings=1,DrawnBindingRows="uCausFailForm.dfm:60:colREASON",' +
    'BindingsElsewhere=6.0,BindingsUnresolved=0.0,BindingsStale=0,IndexReadFacts=0,IndexWriteFacts=0,IndexFactSymbols=0,' +
    'IndexFactReadTables=0,IndexVerbLiterals=7,IndexFromJoinTables=0,NoSqlFacts=true,NoSql=false,Clusters=3,ClickTargets=3,' +
    'Expected=3,AllClickable=true';
  CO_BIND_DOT_SHA = '75b81c2f033881604f4f933d3291a0e73503e5841068900a8840289a5396cdbb';
  CO_UNRES = 'CAUSFAIL.ID';
  CO_UNRES_FIELDS = 'TestChart=false,Table="CAUSFAIL",Column="ID",ColumnOlderOnly=false,ColumnState="yes",' +
    'ColumnLabel="[certain] a column of the newest of 2 declaration(s), MS1.SQL",ColumnLine="MS1.SQL:1409",Declarations=2,' +
    'Columns=4,Readers=0,Writers=0,ReaderUnits=0,WriterUnits=0,CertainReaders=0,CertainWriters=0,InferredReaders=0,' +
    'InferredWriters=0,InferredReaderNames="",CertainWriterNames="",UnitLevelUnits=0,ByNameUnits=1,ByNameLiterals=3.0,' +
    'ByNameCaseOnly="",ByNameLines="uCausFail.ViewModel:37+258+259",Triggers=3,TriggerNames="CAUSFAIL_BIU0@MS6.SQL:34,' +
    'CAUSFAIL_BIU5@MS5.SQL:15,CAUSFAIL_BUD0@MS6.SQL:44",OtherTriggers=0,Procedures=2,ProcedureNames="SP_GET_CAUSFAIL_ID,' +
    'SP_MAXID_FORALL_TABLES",ProcsUnscanned=0,ProcBodies="168/168",Indexes=0,ServerRoutines=0,ServerRoutineNames="",' +
    'SilentRoutines=0,ColumnTriggers=1,ColumnTriggerNames="CAUSFAIL_BIU0",ColumnTriggersStale=0,ColumnTriggersNoBody=0,' +
    'ColumnProcedures=2,ColumnIndexes=0,IndexBindings=72,DrawnBindings=2,' +
    'DrawnBindingRows="uCausFailForm.dfm:34:cxGrid1DBTableView1,uCausFailForm.dfm:44:colID",BindingsElsewhere=31.0,' +
    'BindingsUnresolved=39.0,BindingsStale=0,IndexReadFacts=0,IndexWriteFacts=0,IndexFactSymbols=0,IndexFactReadTables=0,' +
    'IndexVerbLiterals=7,IndexFromJoinTables=0,NoSqlFacts=true,NoSql=false,Clusters=4,ClickTargets=6,Expected=6,' +
    'AllClickable=true';
  CO_UNRES_DOT_SHA = 'f9133bac0b970c7b5c049b748c45a0016743051b0ffda94d54c55db670bddb35';
  CO_SRVSQL = 'STATIONS.GRIDS';
  CO_SRVSQL_FIELDS = 'TestChart=false,Table="STATIONS",Column="GRIDS",ColumnOlderOnly=false,ColumnState="server-sql",' +
    'ColumnLabel="[inferred] not extracted as a column by the SQL index (23 columns extracted from the newest of 2 declaration(s),' +
    ' MS1.SQL:3495); nor a quoted identifier in that declaration -- but the SQL for STATIONS in TDataService_STATIONS_SERVER.PrepareLoadQuery names it: the scripts lag the schema",' +
    'ColumnLine="uSTATIONS_SERVER.PAS:110",Declarations=2,Columns=23,Readers=4,Writers=4,ReaderUnits=0,WriterUnits=0,' +
    'CertainReaders=2,CertainWriters=4,InferredReaders=2,InferredWriters=0,' +
    'InferredReaderNames="uPipeSessionBuilder.TPipeSessionBuilder.HandlePrePlanPreset,' +
    'uSTATIONS_SERVER.TDataService_STATIONS_SERVER.PrepareLoadQuery",' +
    'CertainWriterNames="uPipeSessionBuilder.TPipeSessionBuilder.MarkStationActive,' +
    'uPipeSessionBuilder.TPipeSessionBuilder.MarkStationDropped,uPipeSessionBuilder.TPipeSessionBuilder.MarkStationIdle,' +
    'uSTATIONS_SERVER.TDataService_STATIONS_SERVER.PrepareSaveQuery",UnitLevelUnits=0,ByNameUnits=2,ByNameLiterals=7.0,' +
    'ByNameCaseOnly="",ByNameLines="uPipeSessionBuilder:746,uSTATIONS_SERVER:71+144+219+242+309+340",Triggers=2,' +
    'TriggerNames="STATIONS_BIU5@MS5.SQL:1118,STATIONS_BUD0@MS6.SQL:834",OtherTriggers=0,Procedures=0,ProcedureNames="",' +
    'ProcsUnscanned=0,ProcBodies="168/168",Indexes=0,ServerRoutines=2,' +
    'ServerRoutineNames="uSTATIONS_SERVER.TDataService_STATIONS_SERVER.PrepareLoadQuery,' +
    'uSTATIONS_SERVER.TDataService_STATIONS_SERVER.PrepareSaveQuery",SilentRoutines=6,ColumnTriggers=0,' +
    'ColumnTriggerNames="",ColumnTriggersStale=0,ColumnTriggersNoBody=0,ColumnProcedures=0,ColumnIndexes=0,IndexBindings=0,' +
    'DrawnBindings=0,DrawnBindingRows="",BindingsElsewhere=0.0,BindingsUnresolved=0.0,BindingsStale=0,IndexReadFacts=112,' +
    'IndexWriteFacts=148,IndexFactSymbols=250,IndexFactReadTables=104,IndexVerbLiterals=791,IndexFromJoinTables=133,' +
    'NoSqlFacts=false,NoSql=false,Clusters=3,ClickTargets=3,Expected=3,AllClickable=true';
  CO_SRVSQL_DOT_SHA = 'a8d913d7f0103551bf7fce6acf4435cf3e781075f1cde7e24bb6e9a7240dea12';
  CO_OLDER = 'MACHINES.OPTORID';
  CO_OLDER_FIELDS = 'TestChart=false,Table="MACHINES",Column="OPTORID",ColumnOlderOnly=true,ColumnState="older",' +
    'ColumnLabel="column extracted ONLY from an older declaration (MScript2.SQL:39); not extracted from the newest (45 columns extracted from the newest of 2 declaration(s),' +
    ' MS1.SQL:2409); nor a quoted identifier in that declaration",ColumnLine="MScript2.SQL:39",Declarations=2,Columns=45,' +
    'Readers=1,Writers=1,ReaderUnits=0,WriterUnits=0,CertainReaders=0,CertainWriters=1,InferredReaders=1,InferredWriters=0,' +
    'InferredReaderNames="uMACHINES_SERVER.TDataService_MACHINES_SERVER.PrepareLoadQuery",' +
    'CertainWriterNames="uMACHINES_SERVER.TDataService_MACHINES_SERVER.PrepareSaveQuery",UnitLevelUnits=0,ByNameUnits=1,' +
    'ByNameLiterals=6.0,ByNameCaseOnly="",ByNameLines="uMACHINES_SERVER:72+146+241+264+349+380",Triggers=4,' +
    'TriggerNames="MACHINES_AI10@MS5.SQL:620,MACHINES_AU10@MS5.SQL:629,MACHINES_BDU0@MS6.SQL:405,' +
    'MACHINES_BIU5@MS5.SQL:643",OtherTriggers=0,Procedures=2,ProcedureNames="MACHINESLASTSTOP,MACHINESLASTSTOP2",' +
    'ProcsUnscanned=0,ProcBodies="168/168",Indexes=0,ServerRoutines=0,ServerRoutineNames="",SilentRoutines=2,' +
    'ColumnTriggers=0,ColumnTriggerNames="",ColumnTriggersStale=0,ColumnTriggersNoBody=0,ColumnProcedures=0,' +
    'ColumnIndexes=0,IndexBindings=0,DrawnBindings=0,DrawnBindingRows="",BindingsElsewhere=0.0,BindingsUnresolved=0.0,' +
    'BindingsStale=0,IndexReadFacts=112,IndexWriteFacts=148,IndexFactSymbols=250,IndexFactReadTables=104,' +
    'IndexVerbLiterals=791,IndexFromJoinTables=133,NoSqlFacts=false,NoSql=false,Clusters=1,ClickTargets=1,Expected=1,' +
    'AllClickable=true';
  CO_OLDER_DOT_SHA = 'f43283832ad57e19226d90fb02d97795c526c77d937ff82b315d85196cb0d937';
  CO_IDX = 'FOLDERS.FLDRSTATUS_CODE';
  CO_IDX_FIELDS = 'TestChart=false,Table="FOLDERS",Column="FLDRSTATUS_CODE",ColumnOlderOnly=false,ColumnState="yes",' +
    'ColumnLabel="[certain] a column of the newest of 2 declaration(s), MS1.SQL",ColumnLine="MS1.SQL:1837",Declarations=2,' +
    'Columns=79,Readers=4,Writers=2,ReaderUnits=0,WriterUnits=0,CertainReaders=1,CertainWriters=2,InferredReaders=3,' +
    'InferredWriters=0,InferredReaderNames="uFOLDERS_SERVER.TDataService_FOLDERS_SERVER.PrepareLoadQuery,' +
    'uPipeSessionBuilder.TPipeSessionBuilder.HandleCreateFolder,' +
    'uPipeSessionBuilder.TPipeSessionBuilder.HandlePrePlanPreset",' +
    'CertainWriterNames="uFOLDERS_SERVER.TDataService_FOLDERS_SERVER.PrepareSaveQuery,' +
    'uPipeSessionBuilder.TPipeSessionBuilder.HandleCreateFolder",UnitLevelUnits=0,ByNameUnits=2,ByNameLiterals=7.0,' +
    'ByNameCaseOnly="",ByNameLines="uFOLDERS_SERVER:72+156+285+308+424+455,uPipeSessionBuilder:747",Triggers=3,' +
    'TriggerNames="FOLDERS_BD0@MS6.SQL:276,FOLDERS_BIU0@MS6.SQL:285,FOLDERS_BIU5@MS5.SQL:269",OtherTriggers=0,Procedures=1,' +
    'ProcedureNames="SP_MAXID_FORALL_TABLES",ProcsUnscanned=0,ProcBodies="168/168",Indexes=2,ServerRoutines=3,' +
    'ServerRoutineNames="uFOLDERS_SERVER.TDataService_FOLDERS_SERVER.PrepareLoadQuery,' +
    'uFOLDERS_SERVER.TDataService_FOLDERS_SERVER.PrepareSaveQuery,' +
    'uPipeSessionBuilder.TPipeSessionBuilder.HandleCreateFolder",SilentRoutines=2,ColumnTriggers=1,' +
    'ColumnTriggerNames="FOLDERS_BIU5",ColumnTriggersStale=0,ColumnTriggersNoBody=0,ColumnProcedures=0,ColumnIndexes=1,' +
    'IndexBindings=0,DrawnBindings=0,DrawnBindingRows="",BindingsElsewhere=0.0,BindingsUnresolved=0.0,BindingsStale=0,' +
    'IndexReadFacts=112,IndexWriteFacts=148,IndexFactSymbols=250,IndexFactReadTables=104,IndexVerbLiterals=791,' +
    'IndexFromJoinTables=133,NoSqlFacts=false,NoSql=false,Clusters=5,ClickTargets=7,Expected=7,AllClickable=true';
  CO_IDX_DOT_SHA = '87b813d412e8c2964debe14cb0dbfa1d4130085d519ba8f8db2d777f64707d8a';
  CO_ANSWER = 'MSCLIST';
  CO_LINES = 17;
  CO_SQL_INDEX_LINE = 4;
  CO_CHART = 'CHART consumers MSCLIST -- 0 reading routines / 0 writing routines';
  CO_LAST_ROW = '  ControlPlan2.ViewModel @ControlPlan2.ViewModel.pas:387 -- ControlPlan2.ViewModel.pas: ''MSCLIST'' at literal :387, literal :708, literal :851';
  EP_ID = 'exception-paths';
  EP_HT_FIRST = 4242;
  EP_HT_COUNT = 150;
  EP_HT_STEP = 37;
  EP_HT_OFFSET = 11;
  EP_HT_ORDER = '4303,3008,1713,418,5154,3859,2564,1269,4710,3415,2120,825,5561,4266,2971,1676,381,5117,3822,2527,123' +
    '2,4242,3378,2083,788,5524,4229,2934,1639,344,5080,3785,2490,1195,4636,3341,2046,751,5487,4192,2897,1' +
    '602,307,5043,3748,2453,1158,4599,3304,2009,714,5450,4155,2860,1565,270,5006,3711,2416,1121,4562,3267' +
    ',1972,677,5413,4118,2823,1528,233,196,4969,3674,2379,1084,4525,3230,1935,640,5376,4081,2786,1491,467' +
    '3,4932,3637,2342,1047,4488,3193,1898,603,5339,4044,2749,1454,159,4895,3600,2305,1010,4451,3156,1861,' +
    '566,5302,4007,2712,1417,122,4858,3563,2268,973,4414,3119,1824,529,5265,3970,2675,1380,85,4821,3526,2' +
    '231,936,4377,3082,1787,492,5228,3933,2638,1343,48,4784,3489,2194,899,4340,3045,1750,455,5191,3896,26' +
    '01,1306,4747,3452,2157,862';
  { two small key sets and the order pwsh 7 prints their hashtable keys in }
  EP_HT_MIXED_KEYS: TArray<Integer> = [5, 12, 3, 40, 7, 99, 1000, 17, 2, 64];
  EP_HT_MIXED_ORDER = '1000,99,64,12,7,40,5,3,2,17';
  EP_HT_HUNDREDS_KEYS: TArray<Integer> = [100, 200, 300, 400, 500, 600, 700];
  EP_HT_HUNDREDS_ORDER = '100,200,300,400,500,600,700';
  EP_DEPTH = 3;
  RT_DEPTH = 4;
  TEST_CLONE = 'TESTS-TestMicroniteObjects.sqlite';
  EP_RB = 'MStreams.TABZMemoryStream.ReadBuffer';
  EP_SCHEMA = 'uJobList.ViewModel.TJobListViewModel.BuildSchema';
  EP_NOCALL = 'BASICSF.Delete_DirTree';
  EP_STALE = 'Stats.Z19_LowerQI_KnownSigma';
  EP_BARE = 'uPipeClientConnection.TPipeClientConnection.Disconnect';
  EP_DDL = 'uOptrlistRoleSync.CreateDdlConnection';
  EP_RERAISE = 'uThreadStorageServer.TThreadStorageServer.OpenConnection';
  EP_WRITE = 'MStreams.TABZMemoryStream.WriteBuffer';
  EP_PARTIAL = 'DRagLint.Format.Yadf.TYadfFormatter.SpawnAndCapture';
  EP_WIDE = 'DRagLint.Sql.Guarded.TSqlGuard.Create';
  EP_CAP = 'MStreams.TABZMemoryStream.EnsureMoreCapacity';
  EP_RVAR = 'BASICSF.CopyRecords';
  EP_MANY = 'uAutoTest.RunAutoTest';
  EP_MAY = 'DUnitX.TestRunner.TDUnitXTestRunner.ExecuteTest';
  EP_UNITTESTS_CLONE = 'TESTS-MicroniteTests.sqlite';
  EP_PARTIAL_FIELDS = 'Qname="DRagLint.Format.Yadf.TYadfFormatter.SpawnAndCapture",Raises=2,RaiseTypes=1,RaiseTypeNames="EY' +
    'adfFormatError",RaiseLines="512,529",Handles=0,HandleLines="",Dropped=0,Inferred=0,InferredRaises=0,' +
    'BareExcepts=0,InferredLines="",StaleRows=0,FocusFresh=true,Callers=3,CallerLevels=3,CallerNames="d1:' +
    'Format,d2:DoFormat,d3:Run",CallersCapped=false,Caught=0,Escapes=0,NoCallerEnds=1.0,CappedCallers=0,C' +
    'atchAndPass=0,TypePaths="EYadfFormatError:0/0/1/3/0",SolidEdges=2,ReRaised=0,Partial=2,Unverified=0,' +
    'MayCatch=0,NotGuarding=2,NotGuardingUndrawn=2,NotEvaluated="",NoVerdicts=0,StaleCallers=2,Events="pa' +
    'rtial:Format:652,partial:Format:690",WalkSentence="no handler found within 3 caller levels (3 caller' +
    's evaluated); reaches 1 caller with no resolved caller of its own; 2 caught at only some call sites;' +
    ' 2 callers not read: source changed since indexing",FilesTouched=2,StaleFiles=1,IndexCandidates=152,' +
    'IndexRaise=40,IndexHandle=59,IndexDropped=10,IndexRaiseRoutines=30,IndexHandleRoutines=45,Clusters=5,' +
    'ClickTargets=8,Expected=8,AllClickable=true';
  EP_PARTIAL_DOT_SHA = 'c820e0c3c716c9416068e7e8576a05074d30f54207f60d9457cda8a3b524799f';
  EP_WIDE_FIELDS = 'Qname="DRagLint.Sql.Guarded.TSqlGuard.Create",Raises=5,RaiseTypes=1,RaiseTypeNames="ESqlGuardError",' +
    'RaiseLines="412,414,416,425,427",Handles=0,HandleLines="",Dropped=0,Inferred=0,InferredRaises=0,Bare' +
    'Excepts=0,InferredLines="",StaleRows=0,FocusFresh=true,Callers=2,CallerLevels=2,CallerNames="d1:DoSq' +
    'l,d2:Run",CallersCapped=false,Caught=0,Escapes=0,NoCallerEnds=1.0,CappedCallers=0,CatchAndPass=0,Typ' +
    'ePaths="ESqlGuardError:0/0/1/2/0",SolidEdges=0,ReRaised=0,Partial=0,Unverified=0,MayCatch=0,NotGuard' +
    'ing=0,NotGuardingUndrawn=0,NotEvaluated="",NoVerdicts=0,StaleCallers=2,Events="",WalkSentence="no ha' +
    'ndler found within 3 caller levels (2 callers evaluated); reaches 1 caller with no resolved caller o' +
    'f its own; 2 callers not read: source changed since indexing",FilesTouched=2,StaleFiles=1,IndexCandi' +
    'dates=152,IndexRaise=40,IndexHandle=59,IndexDropped=10,IndexRaiseRoutines=30,IndexHandleRoutines=45,C' +
    'lusters=4,ClickTargets=8,Expected=8,AllClickable=true';
  EP_WIDE_DOT_SHA = 'ad12b701629679fff6e951a09e4d6b9f88cf8a6d1f42ef15d1c50e63a4112635';
  { DL_CLONE's FROZEN source: every file of the clone at the sha256 it was indexed with (recovered
    from git by that sha; third_party\delphi-tree-sitter\TreeSitterLib.pas has no such blob and is
    absent, so stale). The live tree the clone indexed, EP_DL_INDEXED_ROOT, is edited and re-indexed
    all day, so its freshness is no fixture. EP_PARTIAL / EP_WIDE values: the PS bundler over the
    same rewritten copy (DRAGLINT_CHARTS_ALLOW_LIVE_DB=1), its graph.dot hashed as FrozenDotSha does. }
  EP_DL_SOURCE = 'charts\scratch\src\DL-drag-lint';
  EP_DL_INDEXED_ROOT = 'C:\Projects\Delphi-RAG-lint\';  // dl:ok hardcoded-absolute-path@d2c6 -- REVIEWED 2026-10-14: the root the FROZEN DL clone indexed, matched against its files table and never opened; the fixture re-roots it to EP_DL_SOURCE
  { stale BY CONSTRUCTION (its recorded sha256 replaced): the state the 2026-10-13 PS reference was
    printed in, and the one the PS can still answer -- with this file fresh the PS SpawnAndCapture
    walk dies on an Int32 -Pos (29385 * 100000 + 15) }
  EP_DL_STALE_UNIT = '%\src\cli\DRagLint.CLI.pas';
  EP_DL_STALE_SHA = 'stale-by-construction';
  EP_ALLOW_LIVE_ON = '1';
  EP_SQLITE_DRIVER = 'SQLite';
  EP_SQLITE_DATABASE = 'Database';
  EP_DL_REROOT_SQL = 'UPDATE files SET path = :root || substr(path, :cut) WHERE substr(path, 1, :len) = :old COLLATE NOCASE';
  EP_DL_FILES_SQL = 'SELECT count(*) FROM files';
  EP_DL_STALE_SQL ='UPDATE files SET sha256 = :sha WHERE path LIKE :unit';
  EP_CAP_FIELDS = 'Qname="MStreams.TABZMemoryStream.EnsureMoreCapacity",Raises=1,RaiseTypes=1,RaiseTypeNames="EStreamEr' +
    'ror",RaiseLines="2163",Handles=0,HandleLines="",Dropped=0,Inferred=0,InferredRaises=0,BareExcepts=0,' +
    'InferredLines="",StaleRows=0,FocusFresh=true,Callers=150,CallerLevels=2,CallerNames="d1:Read,d1:Writ' +
    'e,d1:WriteB,d1:WriteB,d1:WriteB,d1:WriteB,d1:WriteB,d1:WriteB,d2:WriteB,d2:WriteB,d2:WriteB,d2:Write' +
    'B,d2:WriteB,d2:WriteB,d2:WriteB,d2:WriteBuffer,d2:Writer,d2:Writer,d2:Writer,d2:Writer,d2:Writer,d2:' +
    'Writer,d2:Writer,d2:Writer,d2:Writer,d2:Writer,d2:Writer,d2:Writer,d2:Writer,d2:Writer,d2:Writer,d2:' +
    'Writer,d2:Writer,d2:Writer,d2:Writer,d2:Writer,d2:Writer,d2:Writer,d2:Writer,d2:Writer,d2:Writer,d2:' +
    'Writer,d2:Writer,d2:Writer,d2:Writer,d2:Writer,d2:Writer,d2:Writer,d2:Writer,d2:Writer,d2:Writer,d2:' +
    'Writer,d2:Writer,d2:Writer,d2:Writer,d2:Writer,d2:Writer,d2:Writer,d2:Writer,d2:Writer,d2:Writer,d2:' +
    'Writer,d2:Writer,d2:Writer,d2:Writer,d2:Writer,d2:Writer,d2:Writer,d2:Writer,d2:Writer,d2:Writer,d2:' +
    'Writer,d2:Writer,d2:Writer,d2:Writer,d2:Writer,d2:Writer,d2:Writer,d2:Writer,d2:Writer,d2:Writer,d2:' +
    'Writer,d2:Writer,d2:Writer,d2:Writer,d2:Writer,d2:Writer,d2:Writer,d2:Writer,d2:Writer,d2:Writer,d2:' +
    'Writer,d2:Writer,d2:Writer,d2:Writer,d2:Writer,d2:Writer,d2:Writer,d2:Writer,d2:Writer,d2:Writer,d2:' +
    'Writer,d2:Writer,d2:Writer,d2:Writer,d2:Writer,d2:Writer,d2:Writer,d2:Writer,d2:Writer,d2:Writer,d2:' +
    'Writer,d2:Writer,d2:Writer,d2:Writer,d2:Writer,d2:Writer,d2:Writer,d2:Writer,d2:Writer,d2:Writer,d2:' +
    'Writer,d2:Writer,d2:Writer,d2:Writer,d2:Writer,d2:Writer,d2:Writer,d2:Writer,d2:Writer,d2:Writer,d2:' +
    'Writer,d2:Writer,d2:Writer,d2:Writer,d2:Writer,d2:Writer,d2:Writer,d2:Writer,d2:Writer,d2:Writer,d2:' +
    'Writer,d2:Writer,d2:Writer,d2:Writer,d2:Writer,d2:Writer,d2:Writer,d2:Writer,d2:Writer",CallersCappe' +
    'd=true,Caught=0,Escapes=0,NoCallerEnds=144.0,CappedCallers=140.0,CatchAndPass=0,TypePaths="EStreamEr' +
    'ror:0/0/144/150/140",SolidEdges=0,ReRaised=0,Partial=0,Unverified=0,MayCatch=0,NotGuarding=0,NotGuar' +
    'dingUndrawn=0,NotEvaluated="",NoVerdicts=0,StaleCallers=0,Events="",WalkSentence="no handler found w' +
    'ithin 3 caller levels (150 callers evaluated); reaches 144 callers with no resolved caller of their ' +
    'own; 140 callers not walked (cap)",FilesTouched=135,StaleFiles=0,IndexCandidates=428,IndexRaise=168,' +
    'IndexHandle=177,IndexDropped=74,IndexRaiseRoutines=120,IndexHandleRoutines=101,Clusters=4,ClickTarge' +
    'ts=30,Expected=30,AllClickable=true';
  EP_CAP_DOT_SHA = '4485996b95b6ef142e3407c8f29089a450731a8a13dd2dfcc18014030e8e2459';
  EP_RVAR_FIELDS = 'Qname="BASICSF.CopyRecords",Raises=0,RaiseTypes=0,RaiseTypeNames="",RaiseLines="",Handles=1,HandleLi' +
    'nes="5037",Dropped=0,Inferred=5,InferredRaises=3,BareExcepts=2,InferredLines="raise-var@5046,bare-ex' +
    'cept@5053,reraise@5054,bare-except@5063,reraise@5064",StaleRows=0,FocusFresh=true,Callers=0,CallerLe' +
    'vels=0,CallerNames="",CallersCapped=false,Caught=0,Escapes=0,NoCallerEnds=0,CappedCallers=0,CatchAnd' +
    'Pass=0,TypePaths="(re-raise):0/0/0/0/0",SolidEdges=0,ReRaised=0,Partial=0,Unverified=0,MayCatch=0,No' +
    'tGuarding=0,NotGuardingUndrawn=0,NotEvaluated="",NoVerdicts=0,StaleCallers=0,Events="",WalkSentence=' +
    '"no resolved caller in this index",FilesTouched=1,StaleFiles=0,IndexCandidates=428,IndexRaise=168,In' +
    'dexHandle=177,IndexDropped=74,IndexRaiseRoutines=120,IndexHandleRoutines=101,Clusters=4,ClickTargets' +
    '=7,Expected=7,AllClickable=true';
  EP_RVAR_DOT_SHA = 'd1184e775a1cd2f3f7c83e8a90368041a7a966c6ee4a8eebd02b819d0e4f2ade';
  EP_MANY_FIELDS = 'Qname="uAutoTest.RunAutoTest",Raises=0,RaiseTypes=0,RaiseTypeNames="",RaiseLines="",Handles=41,Handl' +
    'eLines="698,709,733,775,834,890,972,984,1001,1022,1096,1117,1132,1170,1204,1233,1251,1275,1292,1326,' +
    '1350,1383,1497,1530,1591,1618,1646,1653,1660,1735,1765,1788,1845,1886,1912,1938,1967,1989,2006,2065,' +
    '2072",Dropped=0,Inferred=5,InferredRaises=0,BareExcepts=5,InferredLines="bare-except@770,bare-except' +
    '@829,bare-except@886,bare-except@967,bare-except@2081",StaleRows=0,FocusFresh=true,Callers=0,CallerL' +
    'evels=0,CallerNames="",CallersCapped=false,Caught=0,Escapes=0,NoCallerEnds=0,CappedCallers=0,CatchAn' +
    'dPass=0,TypePaths="",SolidEdges=0,ReRaised=0,Partial=0,Unverified=0,MayCatch=0,NotGuarding=0,NotGuar' +
    'dingUndrawn=0,NotEvaluated="",NoVerdicts=0,StaleCallers=0,Events="",WalkSentence=null,FilesTouched=1' +
    ',StaleFiles=0,IndexCandidates=428,IndexRaise=168,IndexHandle=177,IndexDropped=74,IndexRaiseRoutines=' +
    '120,IndexHandleRoutines=101,Clusters=3,ClickTargets=26,Expected=26,AllClickable=true';
  EP_MANY_DOT_SHA = 'a296fca968fb8872193d22e560b6f05ed89e292c926a463829e2a1d70e2e6b46';
  EP_MAY_FIELDS = 'Qname="DUnitX.TestRunner.TDUnitXTestRunner.ExecuteTest",Raises=2,RaiseTypes=2,RaiseTypeNames="ENoAss' +
    'ertionsMade,Exception",RaiseLines="788,801",Handles=0,HandleLines="",Dropped=0,Inferred=0,InferredRa' +
    'ises=0,BareExcepts=0,InferredLines="",StaleRows=0,FocusFresh=true,Callers=3,CallerLevels=3,CallerNam' +
    'es="d1:ExecuteTests,d2:ExecuteFixtures,d3:Execute",CallersCapped=false,Caught=2.0,Escapes=0,NoCaller' +
    'Ends=0,CappedCallers=0,CatchAndPass=0,TypePaths="ENoAssertionsMade:1/0/0/1/0,Exception:1/0/0/1/0",So' +
    'lidEdges=3,ReRaised=0,Partial=0,Unverified=0,MayCatch=3,NotGuarding=0,NotGuardingUndrawn=0,NotEvalua' +
    'ted="d2:ExecuteFixtures,d3:Execute",NoVerdicts=2,StaleCallers=0,Events="caught:ExecuteTests:853,caug' +
    'ht:ExecuteTests:857,may:ExecuteTests:851,may:ExecuteTests:853,may:ExecuteTests:855,caught:ExecuteTes' +
    'ts:857",WalkSentence="ENoAssertionsMade: caught on 1 call edge (ExecuteTests:853 on the call to Exec' +
    'uteTest) within 3 caller levels (1 caller evaluated); Exception: caught on 1 call edge (ExecuteTests' +
    ':857 on the call to ExecuteTest) within 3 caller levels (1 caller evaluated); 3 may catch",FilesTouc' +
    'hed=1,StaleFiles=0,IndexCandidates=85,IndexRaise=24,IndexHandle=23,IndexDropped=32,IndexRaiseRoutine' +
    's=16,IndexHandleRoutines=17,Clusters=5,ClickTargets=10,Expected=10,AllClickable=true';
  EP_MAY_DOT_SHA = '05744c36d614b339c1d1a407a70d450243f25acbc3fb84ac8050d1d4a28532dc';
  EP_RB_FIELDS = 'Qname="MStreams.TABZMemoryStream.ReadBuffer",Raises=1,RaiseTypes=1,RaiseTypeNames="EReadError",Raise' +
    'Lines="2173",Handles=0,HandleLines="",Dropped=0,Inferred=0,InferredRaises=0,BareExcepts=0,InferredLi' +
    'nes="",StaleRows=0,FocusFresh=true,Callers=140,CallerLevels=3,CallerNames="d1:Save,d1:AutoTestSetupD' +
    'efaults,d1:Save,d1:Save,d1:Save,d1:Save,d1:Save,d1:Save,d1:Save,d1:Save,d1:Save,d1:Save,d1:Save,d1:S' +
    'ave,d1:Save,d1:Save,d1:Save,d1:Save,d1:Save,d1:Save,d1:Save,d1:Save,d1:Save,d1:Save,d1:Save,d1:Save,' +
    'd1:Save,d1:Save,d1:Save,d1:Save,d1:Save,d1:Save,d1:Save,d1:Save,d1:Save,d1:Save,d1:Save,d1:Save,d1:S' +
    'ave,d1:Save,d1:Save,d1:Save,d1:Save,d1:Save,d1:Save,d1:Save,d1:Save,d1:Save,d1:Save,d1:Save,d1:Save,' +
    'd1:Save,d1:Save,d1:Save,d1:Save,d1:Save,d1:Save,d1:Save,d1:Save,d1:Save,d1:Save,d1:Save,d1:Save,d1:S' +
    'ave,d1:Save,d1:Save,d1:Save,d1:Save,d1:Save,d1:Save,d1:Save,d1:Save,d1:Save,d1:Save,d1:Save,d1:Save,' +
    'd1:Save,d1:Save,d1:Save,d1:Save,d1:Save,d1:Save,d1:Save,d1:Save,d1:Save,d1:Save,d1:Save,d1:Save,d1:S' +
    'ave,d1:Save,d1:Save,d1:Save,d1:Save,d1:Save,d1:Save,d1:Save,d1:Save,d1:Save,d1:Save,d1:Save,d1:Save,' +
    'd1:Save,d1:Save,d1:Save,d1:Save,d1:Save,d1:Save,d1:Save,d1:Save,d1:Save,d1:Save,d1:Save,d1:Save,d1:S' +
    'ave,d1:Save,d1:Save,d1:Save,d1:Save,d1:Save,d1:Save,d1:Save,d1:Save,d1:Save,d1:Save,d1:Save,d1:Save,' +
    'd1:Save,d1:Save,d1:Save,d1:Save,d1:Save,d1:Save,d1:Save,d1:Save,d2:RunAutoTest,d2:Save,d2:PostStatio' +
    'nToServer,d3:SaveDefaults,d3:AutoTestSetupBools,d3:FormCloseQuery",CallersCapped=false,Caught=2.0,Es' +
    'capes=3.0,NoCallerEnds=133.0,CappedCallers=0,CatchAndPass=1.0,TypePaths="EReadError:2/3/133/139/0",S' +
    'olidEdges=2,ReRaised=0,Partial=0,Unverified=0,MayCatch=0,NotGuarding=2,NotGuardingUndrawn=1,NotEvalu' +
    'ated="d2:RunAutoTest",NoVerdicts=0,StaleCallers=0,Events="caught:AutoTestSetupDefaults:466,caught:Au' +
    'toTestSetupDefaults:466",WalkSentence="caught on 2 call edges (AutoTestSetupDefaults:466 on the call' +
    ' to ReadBuffer, AutoTestSetupDefaults:466 on the call to Save) within 3 caller levels (139 callers e' +
    'valuated); 1 catching caller also lets it escape on another call; escapes the walk on 3 path ends af' +
    'ter 3 levels; reaches 133 callers with no resolved caller of their own",FilesTouched=139,StaleFiles=' +
    '0,IndexCandidates=428,IndexRaise=168,IndexHandle=177,IndexDropped=74,IndexRaiseRoutines=120,IndexHan' +
    'dleRoutines=101,Clusters=5,ClickTargets=31,Expected=31,AllClickable=true';
  EP_RB_DOT_SHA = '3ff01d4fd6b623f336c7f97303d318c28fe53d90d4267ad25f8724985226d64c';
  EP_SCHEMA_FIELDS = 'Qname="uJobList.ViewModel.TJobListViewModel.BuildSchema",Raises=1,RaiseTypes=1,RaiseTypeNames="EData' +
    'baseError",RaiseLines="289",Handles=0,HandleLines="",Dropped=0,Inferred=0,InferredRaises=0,BareExcep' +
    'ts=0,InferredLines="",StaleRows=0,FocusFresh=true,Callers=7,CallerLevels=3,CallerNames="d1:ApplyRawP' +
    'ayload,d1:LoadAll,d2:btnRefreshClick,d2:btnRefreshGridClick,d2:RefreshFolders,d2:LoadAllAsync,d3:DoI' +
    'nitLoad",CallersCapped=false,Caught=1.0,Escapes=0,NoCallerEnds=3.0,CappedCallers=0,CatchAndPass=0,Ty' +
    'pePaths="EDatabaseError:1/0/3/6/0",SolidEdges=1,ReRaised=0,Partial=0,Unverified=0,MayCatch=0,NotGuar' +
    'ding=3,NotGuardingUndrawn=3,NotEvaluated="d3:DoInitLoad",NoVerdicts=0,StaleCallers=0,Events="caught:' +
    'LoadAllAsync:632",WalkSentence="caught on 1 call edge (LoadAllAsync:632 on the call to ApplyRawPaylo' +
    'ad) within 3 caller levels (6 callers evaluated); reaches 3 callers with no resolved caller of their' +
    ' own",FilesTouched=2,StaleFiles=0,IndexCandidates=428,IndexRaise=168,IndexHandle=177,IndexDropped=74' +
    ',IndexRaiseRoutines=120,IndexHandleRoutines=101,Clusters=5,ClickTargets=10,Expected=10,AllClickable=' +
    'true';
  EP_SCHEMA_DOT_SHA = 'dbe8776b521a5c08c71dd62d12a2a92fe4bbe4506a121bec6070fce536b1ae1b';
  EP_NOCALL_FIELDS = 'Qname="BASICSF.Delete_DirTree",Raises=3,RaiseTypes=1,RaiseTypeNames="EFileError",RaiseLines="684,693' +
    ',698",Handles=1,HandleLines="715",Dropped=0,Inferred=0,InferredRaises=0,BareExcepts=0,InferredLines=' +
    '"",StaleRows=0,FocusFresh=true,Callers=0,CallerLevels=0,CallerNames="",CallersCapped=false,Caught=0,' +
    'Escapes=0,NoCallerEnds=0,CappedCallers=0,CatchAndPass=0,TypePaths="EFileError:0/0/0/1/0",SolidEdges=' +
    '0,ReRaised=0,Partial=0,Unverified=0,MayCatch=0,NotGuarding=0,NotGuardingUndrawn=0,NotEvaluated="",No' +
    'Verdicts=0,StaleCallers=0,Events="",WalkSentence="no handler found within 3 caller levels (1 caller ' +
    'evaluated)",FilesTouched=1,StaleFiles=0,IndexCandidates=428,IndexRaise=168,IndexHandle=177,IndexDrop' +
    'ped=74,IndexRaiseRoutines=120,IndexHandleRoutines=101,Clusters=3,ClickTargets=5,Expected=5,AllClicka' +
    'ble=true';
  EP_NOCALL_DOT_SHA = '25da5af3dffb2be1915c9ae7a6272b014a827bfb1340eaf0ab72553859279f8a';
  EP_STALE_FIELDS = 'Qname="Stats.Z19_LowerQI_KnownSigma",Raises=0,RaiseTypes=0,RaiseTypeNames="",RaiseLines="",Handles=0' +
    ',HandleLines="",Dropped=0,Inferred=0,InferredRaises=0,BareExcepts=0,InferredLines="",StaleRows=2,Foc' +
    'usFresh=false,Callers=8,CallerLevels=3,CallerNames="d1:Accept_Double_Known_CombinedAQL,d1:Accept_Dou' +
    'ble_Known_DiffAQLs,d1:Accept_SingleForm2_Known,d1:Accept_Double_Known_CombinedAQL,d1:Accept_Double_K' +
    'nown_DiffAQLs,d1:Accept_SingleForm2_Known,d2:IssueVerdict,d3:Update",CallersCapped=false,Caught=0,Es' +
    'capes=0,NoCallerEnds=0,CappedCallers=0,CatchAndPass=0,TypePaths="",SolidEdges=0,ReRaised=0,Partial=0' +
    ',Unverified=0,MayCatch=0,NotGuarding=0,NotGuardingUndrawn=0,NotEvaluated="d1:Accept_Double_Known_Com' +
    'binedAQL,d1:Accept_Double_Known_DiffAQLs,d1:Accept_SingleForm2_Known,d1:Accept_Double_Known_Combined' +
    'AQL,d1:Accept_Double_Known_DiffAQLs,d1:Accept_SingleForm2_Known,d2:IssueVerdict,d3:Update",NoVerdict' +
    's=0,StaleCallers=0,Events="",WalkSentence=null,FilesTouched=2,StaleFiles=1,IndexCandidates=428,Index' +
    'Raise=168,IndexHandle=177,IndexDropped=74,IndexRaiseRoutines=120,IndexHandleRoutines=101,Clusters=5,' +
    'ClickTargets=11,Expected=11,AllClickable=true';
  EP_STALE_DOT_SHA = '319120590752d4960a466959ed8793ece129e321c4d4ca707b84295b57728707';
  EP_BARE_FIELDS = 'Qname="uPipeClientConnection.TPipeClientConnection.Disconnect",Raises=0,RaiseTypes=0,RaiseTypeNames=' +
    '"",RaiseLines="",Handles=1,HandleLines="535",Dropped=0,Inferred=1,InferredRaises=0,BareExcepts=1,Inf' +
    'erredLines="bare-except@524",StaleRows=0,FocusFresh=true,Callers=6,CallerLevels=2,CallerNames="d1:Ru' +
    'nAdminBootstrap,d1:Connect,d1:Destroy,d1:Disconnect,d1:Destroy,d2:FormCreate",CallersCapped=false,Ca' +
    'ught=0,Escapes=0,NoCallerEnds=0,CappedCallers=0,CatchAndPass=0,TypePaths="",SolidEdges=0,ReRaised=0,' +
    'Partial=0,Unverified=0,MayCatch=0,NotGuarding=0,NotGuardingUndrawn=0,NotEvaluated="d1:RunAdminBootst' +
    'rap,d1:Connect,d1:Destroy,d1:Disconnect,d1:Destroy,d2:FormCreate",NoVerdicts=0,StaleCallers=3,Events' +
    '="",WalkSentence=null,FilesTouched=4,StaleFiles=1,IndexCandidates=428,IndexRaise=168,IndexHandle=177' +
    ',IndexDropped=74,IndexRaiseRoutines=120,IndexHandleRoutines=101,Clusters=5,ClickTargets=9,Expected=9' +
    ',AllClickable=true';
  EP_BARE_DOT_SHA = '852261dbada87c2c100b3ab8ae153e9195ac0e5604131626cb881b01f8286d50';
  EP_DDL_FIELDS = 'Qname="uOptrlistRoleSync.CreateDdlConnection",Raises=1,RaiseTypes=1,RaiseTypeNames="Exception",Raise' +
    'Lines="195",Handles=0,HandleLines="",Dropped=0,Inferred=2,InferredRaises=1,BareExcepts=1,InferredLin' +
    'es="bare-except@207,reraise@209",StaleRows=0,FocusFresh=true,Callers=7,CallerLevels=3,CallerNames="d' +
    '1:ApplyOptrlistSyncItems,d1:ResyncAllOptrlistFirebirdRoles,d1:SyncOptrlistFirebirdRoles,d2:HandleDel' +
    'ta,d2:RevokeAllOptrlistFirebirdRoles,d2:HandleRoleResync,d3:HandleDelta",CallersCapped=false,Caught=' +
    '4.0,Escapes=0,NoCallerEnds=2.0,CappedCallers=0,CatchAndPass=0,TypePaths="Exception:2/0/1/5/0,(re-rai' +
    'se):2/0/1/5/0",SolidEdges=4,ReRaised=0,Partial=0,Unverified=0,MayCatch=0,NotGuarding=2,NotGuardingUn' +
    'drawn=2,NotEvaluated="d2:HandleDelta,d3:HandleDelta",NoVerdicts=0,StaleCallers=0,Events="caught:Appl' +
    'yOptrlistSyncItems:394,caught:HandleRoleResync:4791,caught:ApplyOptrlistSyncItems:394,caught:HandleR' +
    'oleResync:4791",WalkSentence="Exception: caught on 2 call edges (ApplyOptrlistSyncItems:394 on the c' +
    'all to CreateDdlConnection, HandleRoleResync:4791 on the call to ResyncAllOptrlistFirebirdRoles) wit' +
    'hin 3 caller levels (5 callers evaluated); reaches 1 caller with no resolved caller of its own; (re-' +
    'raise): caught on 2 call edges (ApplyOptrlistSyncItems:394 on the call to CreateDdlConnection, Handl' +
    'eRoleResync:4791 on the call to ResyncAllOptrlistFirebirdRoles) within 3 caller levels (5 callers ev' +
    'aluated); reaches 1 caller with no resolved caller of its own",FilesTouched=3,StaleFiles=0,IndexCand' +
    'idates=2831,IndexRaise=282,IndexHandle=1693,IndexDropped=847,IndexRaiseRoutines=261,IndexHandleRouti' +
    'nes=469,Clusters=7,ClickTargets=13,Expected=13,AllClickable=true';
  EP_DDL_DOT_SHA = '8bcd584dbed6869c7fdd7a805d89f76ce563f037befd10dfcbd6bf1c62aa46e0';
  EP_RERAISE_FIELDS = 'Qname="uThreadStorageServer.TThreadStorageServer.OpenConnection",Raises=1,RaiseTypes=1,RaiseTypeName' +
    's="Exception",RaiseLines="335",Handles=2,HandleLines="325,340",Dropped=1,Inferred=1,InferredRaises=1' +
    ',BareExcepts=0,InferredLines="reraise@340",StaleRows=0,FocusFresh=true,Callers=1,CallerLevels=1,Call' +
    'erNames="d1:OpenConnectionForUser",CallersCapped=false,Caught=2.0,Escapes=0,NoCallerEnds=0,CappedCal' +
    'lers=0,CatchAndPass=0,TypePaths="Exception:1/0/0/1/0,(re-raise):1/0/0/1/0",SolidEdges=2,ReRaised=0,P' +
    'artial=0,Unverified=0,MayCatch=0,NotGuarding=0,NotGuardingUndrawn=0,NotEvaluated="",NoVerdicts=0,Sta' +
    'leCallers=0,Events="caught:OpenConnectionForUser:221,caught:OpenConnectionForUser:221",WalkSentence=' +
    '"Exception: caught on 1 call edge (OpenConnectionForUser:221 on the call to OpenConnection) within 3' +
    ' caller levels (1 caller evaluated); (re-raise): caught on 1 call edge (OpenConnectionForUser:221 on' +
    ' the call to OpenConnection) within 3 caller levels (1 caller evaluated)",FilesTouched=2,StaleFiles=' +
    '0,IndexCandidates=2831,IndexRaise=282,IndexHandle=1693,IndexDropped=847,IndexRaiseRoutines=261,Index' +
    'HandleRoutines=469,Clusters=5,ClickTargets=7,Expected=7,AllClickable=true';
  EP_RERAISE_DOT_SHA = 'cc0a5f7611d60f233c725204098e7defb436cc24a00d5544a70d163d5a8bc924';
  EP_WRITE_FIELDS = 'Qname="MStreams.TABZMemoryStream.WriteBuffer",Raises=1,RaiseTypes=1,RaiseTypeNames="EWriteError",Rai' +
    'seLines="2180",Handles=0,HandleLines="",Dropped=0,Inferred=0,InferredRaises=0,BareExcepts=0,Inferred' +
    'Lines="",StaleRows=0,FocusFresh=true,Callers=3,CallerLevels=2,CallerNames="d1:RouteOPTRLIST,d1:Route' +
    'STATIONS,d2:RouteTableCommand",CallersCapped=false,Caught=0,Escapes=0,NoCallerEnds=1.0,CappedCallers' +
    '=0,CatchAndPass=0,TypePaths="EWriteError:0/0/1/3/0",SolidEdges=0,ReRaised=0,Partial=0,Unverified=0,M' +
    'ayCatch=0,NotGuarding=3,NotGuardingUndrawn=3,NotEvaluated="",NoVerdicts=0,StaleCallers=0,Events="",W' +
    'alkSentence="no handler found within 3 caller levels (3 callers evaluated); reaches 1 caller with no' +
    ' resolved caller of its own",FilesTouched=2,StaleFiles=0,IndexCandidates=2831,IndexRaise=282,IndexHa' +
    'ndle=1693,IndexDropped=847,IndexRaiseRoutines=261,IndexHandleRoutines=469,Clusters=4,ClickTargets=5,' +
    'Expected=5,AllClickable=true';
  EP_WRITE_DOT_SHA = 'f930452844a5d66fae1af3017f2efda9a15d325e8ee8cf6db8499dc26f92faaf';

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

{ pPath exactly as RowHref escapes it into a draglint:// link (between "file=" and the "&") }
function HrefPath(const pPath: string): string;
begin
  var H:= RowHref(pPath, 0);
  var From:= Pos('=', H) + 1;
  Result:= Copy(H, From, Pos('&', H) - From);
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

{ Args plus the SQL-script clone (-SqlDbPath) beside it; pSqlClone '' = SQL_CLONE }
function TQuestionFixture.ArgsWithSql(const pQuestion, pTarget, pCloneName, pSqlClone: string;
  out pArgs: TQuestionArgs): Boolean;
begin
  Result:= Args(pQuestion, pTarget, pCloneName, pArgs);
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

{ a -Depth run on the CLIENT clone: through FindChartQuestion with the depth set, as Ask-Report passes it }
procedure TQuestionFixture.CheckAtDepth(const pQuestion, pTarget: string; pDepth: Integer; const pFields, pDotSha: string);
var
  A: TQuestionArgs;
  E: TChartEmitter;
begin
  if not Args(pQuestion, pTarget, CLIENT_CLONE, A) then
    Exit;
  A.Depth:= pDepth;
  Assert.IsTrue(FindChartQuestion(pQuestion, E), pQuestion + ' is not registered');
  var C:= E(A, FOutRoot);
  Assert.AreEqual(pFields, Fields(C));
  Assert.AreEqual(pDotSha, FileSha(C.Layout.Dot));
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
  Result:= ArgsWithSql(FEEDS_FROM_ID, pTarget, CLIENT_CLONE, pSqlClone, pArgs);
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

procedure TFeedsFromTests.MissingSqlIndexRefusesAsTheBundlerDoes;
var
  A: TQuestionArgs;
  E: TChartEmitter;
begin
  { New-DiagramArtifact refuses a blank -SqlDbPath before the emitter (or the clone guard) runs }
  if not SqlArgs(FF_ONE, '', A) then
    Exit;
  Assert.IsTrue(FindChartQuestion(FEEDS_FROM_ID, E));
  A.SqlDbPath:= '';
  Assert.WillRaiseWithMessage(
    procedure
    begin
      E(A, FOutRoot);
    end, EChartsQuestion, 'feeds-from needs -SqlDbPath: the SQL-script index clone (charts\scratch\db\SQL-drag-lint-sql.sqlite)');
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

procedure TLandsWhereTests.InterfacePropertyWithTwoTriggers;
begin
  { an Imc<T> property: "the interface the server reads"; two triggers name NEW./OLD.SYSTID }
  Check(LW_IFACE, LW_IFACE_FIELDS, LW_IFACE_DOT_SHA);
end;

procedure TLandsWhereTests.ProceduresNamingTheColumnAreDrawn;
begin
  { two procedure bodies name CAUSFAIL and ID; 34 other ID bindings, by table AND by outcome }
  Check(LW_PROC, LW_PROC_FIELDS, LW_PROC_DOT_SHA);
end;

procedure TLandsWhereTests.ThreeTriggersAndOnlyNoTableBindings;
begin
  { three triggers in two scripts, two procedures, and the one other binding reaches no table }
  Check(LW_TRIGS, LW_TRIGS_FIELDS, LW_TRIGS_DOT_SHA);
end;

procedure TLandsWhereTests.OtherDataServiceRoutineIsItsOwnCluster;
begin
  { FindOperatorName's ParamByName('XOPERATOR') is neither save nor load }
  Check(LW_OTHER, LW_OTHER_FIELDS, LW_OTHER_DOT_SHA);
end;

procedure TLandsWhereTests.AmbiguousChainStopsBeforeATable;
begin
  { an ambiguous chain: the default stop "the chain stops before a table (many): ..." }
  Check(LW_AMBIG, LW_AMBIG_FIELDS, LW_AMBIG_DOT_SHA);
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

{ ---- consumers ---- }

{ the Delphi clone pDb and the SQL clone ('' = SQL_CLONE), as the parity case passes them }
function TConsumersTests.CoArgs(const pTarget, pDb, pSql: string; out pArgs: TQuestionArgs): Boolean;
begin
  Result:= ArgsWithSql(CO_ID, pTarget, pDb, pSql, pArgs);
end;

{ pCap 0 = the default cap the bundler passes (20) }
procedure TConsumersTests.Check(const pDb, pTarget, pFields, pDotSha: string; pCap: Integer);
var
  A: TQuestionArgs;
  E: TChartEmitter;
begin
  if not CoArgs(pTarget, pDb, '', A) then
    Exit;
  if pCap > 0 then
    A.Cap:= pCap;
  Assert.IsTrue(FindChartQuestion(CO_ID, E));
  var C:= E(A, FOutRoot);
  Assert.AreEqual(pFields, Fields(C));
  Assert.AreEqual(pDotSha, FileSha(C.Layout.Dot));
end;

function TConsumersTests.CoRefusal(const pTarget, pDb, pSql: string): string;
var
  A: TQuestionArgs;
  E: TChartEmitter;
begin
  Result:= '';
  if not CoArgs(pTarget, pDb, pSql, A) then
    Exit;
  Assert.IsTrue(FindChartQuestion(CO_ID, E));
  try
    E(A, FOutRoot);
    Assert.Fail(pTarget + ' was not refused');
  except
    on X: EChartsQuestion do Result:= X.Message;
  end;
end;

procedure TConsumersTests.CertainReadersAndWritersOnServer;
begin
  { sql_reads / sql_writes facts anchored on a literal, [by name] mentions, triggers, procedures }
  Check(SERVER_CLONE, CO_SRV, CO_SRV_FIELDS, CO_SRV_DOT_SHA);
end;

procedure TConsumersTests.InferredReadersWideTriggerAndIndexes;
begin
  { verb-literal readers, a 70-column trigger cut to "+64 more", two indexes, a mention inside a drawn routine }
  Check(SERVER_CLONE, CO_FOLDERS, CO_FOLDERS_FIELDS, CO_FOLDERS_DOT_SHA);
end;

procedure TConsumersTests.CappedClustersDiscloseTheRest;
begin
  { cap 4: every reader / writer cluster past the cap says how many rows it did not draw }
  Check(SERVER_CLONE, CO_CAPPED, CO_CAPPED_FIELDS, CO_CAPPED_DOT_SHA, CO_SMALL_CAP);
end;

procedure TConsumersTests.OtherTriggersNameTheTable;
begin
  { two triggers FOR other tables name MACHINESTAT in their body; an older-only column on the focus }
  Check(SERVER_CLONE, CO_OTHER, CO_OTHER_FIELDS, CO_OTHER_DOT_SHA);
end;

procedure TConsumersTests.ProcedureDeclaredTwiceSaysSo;
begin
  { LASTSTOP is declared twice: one row, "(2 declarations)" }
  Check(SERVER_CLONE, CO_TWICE, CO_TWICE_FIELDS, CO_TWICE_DOT_SHA);
end;

procedure TConsumersTests.ClientWithoutFactsNamesCaseOnlyLiterals;
begin
  { CLIENT: no SQL facts; 'Folders' equals the table only case-insensitively and is named, not drawn }
  Check(CLIENT_CLONE, CO_CLIENT, CO_CLIENT_FIELDS, CO_CLIENT_DOT_SHA);
end;

procedure TConsumersTests.IndexWithoutAnySqlSaysSo;
begin
  { no facts and no upper-case SQL literal: "ask the SERVER index" }
  Check(CO_NOSQL_CLONE, CO_NOSQL, CO_NOSQL_FIELDS, CO_NOSQL_DOT_SHA);
end;

procedure TConsumersTests.InferredWriterWithoutAFact;
begin
  { drag-lint's own index: a reader and a writer by SQL literal only }
  Check(CO_DL_CLONE, CO_DL, CO_DL_FIELDS, CO_DL_DOT_SHA);
end;

procedure TConsumersTests.ColumnNamedByServerRoutines;
begin
  Check(SERVER_CLONE, CO_SRVCOL, CO_SRVCOL_FIELDS, CO_SRVCOL_DOT_SHA);
end;

procedure TConsumersTests.ColumnBindingsResolvingElsewhereAreCounted;
begin
  { one REASON binding resolves to CAUSFAIL; six resolve to other tables and are only counted }
  Check(CLIENT_CLONE, CO_BIND, CO_BIND_FIELDS, CO_BIND_DOT_SHA);
end;

procedure TConsumersTests.ColumnBindingsThatStopAreCounted;
begin
  { 72 ID bindings: 2 drawn, 31 elsewhere, 39 whose chain stops; two procedures name CAUSFAIL and ID }
  Check(CLIENT_CLONE, CO_UNRES, CO_UNRES_FIELDS, CO_UNRES_DOT_SHA);
end;

procedure TConsumersTests.ColumnOnlyTheServerSqlNames;
begin
  { STATIONS.GRIDS is in no script, but this index's SQL for STATIONS names it: server-sql }
  Check(SERVER_CLONE, CO_SRVSQL, CO_SRVSQL_FIELDS, CO_SRVSQL_DOT_SHA);
end;

procedure TConsumersTests.ColumnOnlyAnOlderDeclarationExtracts;
begin
  Check(SERVER_CLONE, CO_OLDER, CO_OLDER_FIELDS, CO_OLDER_DOT_SHA);
end;

procedure TConsumersTests.ColumnInAnIndexDefinition;
begin
  Check(SERVER_CLONE, CO_IDX, CO_IDX_FIELDS, CO_IDX_DOT_SHA);
end;

procedure TConsumersTests.SelectionRefusalsMatchPowerShell;
begin
  Assert.AreEqual('consumers: -Column takes TABLE.COLUMN, got ''a.b.c''', CoRefusal('a.b.c', SERVER_CLONE));
  Assert.AreEqual('consumers: no table PDF_SCAN in the SQL index (script-derived; the scripts may lag the live schema) -- nearest: ' +
    'PDF1. The index holds 135 table names from 252 declarations; 5 live tables are not in the scripts (2026-09-23).',
    CoRefusal('PDF_SCAN', SERVER_CLONE));
  Assert.AreEqual('consumers: no column NOPE in CAUSFAIL: not extracted as a column by the SQL index (4 columns extracted from the ' +
    'newest of 2 declaration(s), MS1.SQL:1408); nor a quoted identifier in that declaration; no SQL for CAUSFAIL in ' +
    'SERVER-MicroniteMW1Service.sqlite names it -- nearest: ID. Script-derived; the scripts may lag the live schema.',
    CoRefusal('CAUSFAIL.NOPE', SERVER_CLONE));
end;

procedure TConsumersTests.IndexRolesAreChecked;
begin
  { a swapped pair must refuse, never render an empty chart }
  Assert.EndsWith(SQL_CLONE + ' is a SQL-script index, not a Delphi project index. -DbPath takes the Delphi project clone ' +
    '(SERVER for the SQL half, CLIENT for bindings); the scripts go in -SqlDbPath.', CoRefusal(CO_SRV, SQL_CLONE));
  Assert.EndsWith(CLIENT_CLONE + ' is not a SQL index (0 sql_table symbols). -SqlDbPath takes the index of the .SQL scripts ' +
    '(SQL-drag-lint-sql.sqlite); the Delphi project index goes in -DbPath.', CoRefusal(CO_SRV, SERVER_CLONE, CLIENT_CLONE));
end;

procedure TConsumersTests.MissingSqlIndexRefusesAsTheBundlerDoes;
var
  A: TQuestionArgs;
  E: TChartEmitter;
begin
  { New-DiagramArtifact checks it before the emitter runs }
  if not CoArgs(CO_SRV, SERVER_CLONE, '', A) then
    Exit;
  Assert.IsTrue(FindChartQuestion(CO_ID, E));
  A.SqlDbPath:= '';
  Assert.WillRaiseWithMessage(
    procedure
    begin
      E(A, FOutRoot);
    end, EChartsQuestion, 'consumers needs -SqlDbPath: the SQL-script index clone (charts\scratch\db\SQL-drag-lint-sql.sqlite)');
end;

procedure TConsumersTests.AnswerNamesTheSqlIndex;
var
  A: TQuestionArgs;
begin
  if not CoArgs(CO_ANSWER, CLIENT_CLONE, '', A) then
    Exit;
  var L:= AskChartQuestion(A).Lines;
  Assert.AreEqual<Integer>(CO_LINES, Length(L));
  Assert.AreEqual('INDEX ' + A.SqlDbPath + ' (sql)', L[CO_SQL_INDEX_LINE]);
  Assert.AreEqual(CO_CHART, L[CO_SQL_INDEX_LINE + 1]);
  Assert.AreEqual(CO_LAST_ROW, L[High(L)]);
end;

{ ---- exception-paths ---- }

{ pArgs.DbPath (DL_CLONE) copied into this test's scratch with its files table re-rooted from
  EP_DL_INDEXED_ROOT to EP_DL_SOURCE and EP_DL_STALE_UNIT made stale, so nothing reads the live
  tree; False (with a passing note) when the frozen source is missing, as for a missing clone }
function TExceptionPathsTests.FrozenDl(var pArgs: TQuestionArgs): Boolean;
begin
  var Src:= TPath.Combine(RepoRoot, EP_DL_SOURCE);
  Result:= TDirectory.Exists(Src);
  if not Result then
  begin
    Assert.Pass('frozen source missing: ' + Src);
    Exit;
  end;
  TDirectory.CreateDirectory(FOutRoot);
  var Db:= TPath.Combine(FOutRoot, DL_CLONE);
  TFile.Copy(pArgs.DbPath, Db);
  var Conn:= TFDConnection.Create(nil);
  try
    Conn.DriverName:= EP_SQLITE_DRIVER;
    Conn.Params.Values[EP_SQLITE_DATABASE]:= Db;
    { every row re-rooted: not one file is left to be read from the live tree }
    var Files:= Integer(Conn.ExecSQLScalar(EP_DL_FILES_SQL));
    Assert.AreEqual(Files, Conn.ExecSQL(EP_DL_REROOT_SQL, [IncludeTrailingPathDelimiter(Src), Length(EP_DL_INDEXED_ROOT) + 1,
      Length(EP_DL_INDEXED_ROOT), EP_DL_INDEXED_ROOT]), EP_DL_INDEXED_ROOT);
    Assert.AreEqual(1, Conn.ExecSQL(EP_DL_STALE_SQL, [EP_DL_STALE_SHA, EP_DL_STALE_UNIT]), EP_DL_STALE_UNIT);
  finally
    Conn.Free;
  end;
  pArgs.DbPath:= Db;
end;

{ the sha256 of graph.dot as the clone would draw it in place: the frozen root in every escaped
  href read back as EP_DL_INDEXED_ROOT, so the hash does not depend on where the worktree is }
function TExceptionPathsTests.FrozenDotSha(const pDot: string): string;
begin
  var Dot:= TFile.ReadAllText(pDot, TEncoding.UTF8);
  Dot:= Dot.Replace(HrefPath(IncludeTrailingPathDelimiter(TPath.Combine(RepoRoot, EP_DL_SOURCE))),
    HrefPath(EP_DL_INDEXED_ROOT));
  Result:= THashSHA2.GetHashString(Dot);
end;

{ the bundler's -Depth for exception-paths (3) and -Cap (20), as New-DiagramArtifact passes them;
  pFrozenDl runs DL_CLONE against its frozen source (FrozenDl) }
procedure TExceptionPathsTests.Check(const pDb, pTarget, pFields, pDotSha: string; pFrozenDl: Boolean);
var
  A: TQuestionArgs;
  E: TChartEmitter;
begin
  if not Args(EP_ID, pTarget, pDb, A) then
    Exit;
  if pFrozenDl and not FrozenDl(A) then
    Exit;
  A.Depth:= QuestionDefaultDepth(EP_ID);
  Assert.IsTrue(FindChartQuestion(EP_ID, E));
  { the re-rooted copy sits outside the clone root: CloneDb admits it only under the override }
  var Prev:= GetEnvironmentVariable(ALLOW_LIVE_DB_ENV_VAR);
  if pFrozenDl then
    SetEnvironmentVariable(ALLOW_LIVE_DB_ENV_VAR, EP_ALLOW_LIVE_ON);
  var C: TChartResult;
  try
    C:= E(A, FOutRoot);
  finally
    if pFrozenDl then
      SetEnvironmentVariable(ALLOW_LIVE_DB_ENV_VAR, if Prev = '' then nil else PChar(Prev));
  end;
  Assert.AreEqual(pFields, Fields(C));
  Assert.AreEqual(pDotSha, if pFrozenDl then FrozenDotSha(C.Layout.Dot) else FileSha(C.Layout.Dot));
end;

procedure TExceptionPathsTests.CaughtOnOneEdgeAndEscapingOnAnother;
begin
  { 140 callers: AutoTestSetupDefaults catches EReadError on the call to ReadBuffer AND on the call to Save, and lets
    it escape through Save elsewhere; 133 ends, 3 escapes past the bound, a capped depth-1 cluster ("N more callers"),
    a not-guarding handler that is drawn on another edge }
  Check(CLIENT_CLONE, EP_RB, EP_RB_FIELDS, EP_RB_DOT_SHA);
end;

procedure TExceptionPathsTests.CaughtTwoLevelsUp;
begin
  { LoadAllAsync catches EDatabaseError at depth 2; three handlers guard other statements and are not drawn }
  Check(CLIENT_CLONE, EP_SCHEMA, EP_SCHEMA_FIELDS, EP_SCHEMA_DOT_SHA);
end;

procedure TExceptionPathsTests.RecursiveRoutineEvaluatesOnlyItself;
begin
  { no resolved caller but itself: no caller cluster, "no handler found ... (1 caller evaluated)" }
  Check(CLIENT_CLONE, EP_NOCALL, EP_NOCALL_FIELDS, EP_NOCALL_DOT_SHA);
end;

procedure TExceptionPathsTests.StaleFocusIsNotClassified;
begin
  { the frozen clone is stale for Stats.pas: [stale source] rows, nothing classified, WalkSentence null }
  Check(CLIENT_CLONE, EP_STALE, EP_STALE_FIELDS, EP_STALE_DOT_SHA);
end;

procedure TExceptionPathsTests.StaleCallersAndABareExcept;
begin
  { a bare except [inferred] in the body; three callers not read because their file is stale }
  Check(CLIENT_CLONE, EP_BARE, EP_BARE_FIELDS, EP_BARE_DOT_SHA);
end;

procedure TExceptionPathsTests.ReRaiseIsWalkedAsItsOwnType;
begin
  { raise Exception + bare except + raise; : two types walked, each sentence prefixed with its type }
  Check(SERVER_CLONE, EP_DDL, EP_DDL_FIELDS, EP_DDL_DOT_SHA);
end;

procedure TExceptionPathsTests.HandlersInBodyAndCaughtByTheCaller;
begin
  { two handler clauses in the body, a dropped declaration, the caller catches both types }
  Check(SERVER_CLONE, EP_RERAISE, EP_RERAISE_FIELDS, EP_RERAISE_DOT_SHA);
end;

procedure TExceptionPathsTests.HandlersThatGuardOtherStatements;
begin
  { matching handlers whose try holds none of the call sites: counted, not drawn }
  Check(SERVER_CLONE, EP_WRITE, EP_WRITE_FIELDS, EP_WRITE_DOT_SHA);
end;

procedure TExceptionPathsTests.CaughtAtOnlySomeCallSites;
begin
  { Format calls SpawnAndCapture twice, once inside its try: "caught ... for k of n call sites" (partial).
    Against the frozen source: the live tree drifts under every reindex and edit (FrozenDl) }
  Check(DL_CLONE, EP_PARTIAL, EP_PARTIAL_FIELDS, EP_PARTIAL_DOT_SHA, True);
end;

procedure TExceptionPathsTests.LinesPastTheIntegerRangeKeepTheirNumbers;
begin
  { a caller in DRagLint.CLI.pas calls at line 29442: line * 100000 overflows an Integer, the PS widens it.
    Against the frozen source: the live tree drifts under every reindex and edit (FrozenDl) }
  Check(DL_CLONE, EP_WIDE, EP_WIDE_FIELDS, EP_WIDE_DOT_SHA, True);
end;

procedure TExceptionPathsTests.CallerWalkCappedAt150;
begin
  { the walk stops at 150 callers: "caller walk CAPPED", capped callers counted, never "no resolved caller" }
  Check(CLIENT_CLONE, EP_CAP, EP_CAP_FIELDS, EP_CAP_DOT_SHA);
end;

procedure TExceptionPathsTests.ReRaiseOfAVariableWithNoCaller;
begin
  { raise <var>, raise; and bare excepts only: the (re-raise) type alone, no resolved caller }
  Check(CLIENT_CLONE, EP_RVAR, EP_RVAR_FIELDS, EP_RVAR_DOT_SHA);
end;

procedure TExceptionPathsTests.HandlerClausesPastTheCapAreDisclosed;
begin
  { 41 handler clauses: 20 drawn, "21 more handler clauses not shown" }
  Check(CLIENT_CLONE, EP_MANY, EP_MANY_FIELDS, EP_MANY_DOT_SHA);
end;

procedure TExceptionPathsTests.MayCatchAndCannotCatch;
begin
  { typed handlers whose relation to the raised type is unknown (dashed "may catch"), and two that provably cannot }
  Check(EP_UNITTESTS_CLONE, EP_MAY, EP_MAY_FIELDS, EP_MAY_DOT_SHA);
end;

procedure TExceptionPathsTests.RefusalsMatchPowerShell;
begin
  Assert.AreEqual('Blueprint4.ViewModel is a unit, not a method or procedure or function or constructor or destructor -- ' +
    'exception-paths selects a routine', Refusal(EP_ID, 'Blueprint4.ViewModel', CLIENT_CLONE));
  Assert.AreEqual('NoSuchRoutineXyz is not in this index', Refusal(EP_ID, 'NoSuchRoutineXyz', CLIENT_CLONE));
end;

procedure TExceptionPathsTests.WalksThreeLevelsByDefault;
begin
  { New-DiagramArtifact's $EffDepth }
  Assert.AreEqual<Integer>(EP_DEPTH, QuestionDefaultDepth(EP_ID));
  Assert.AreEqual<Integer>(RT_DEPTH, QuestionDefaultDepth('round-trip'));
  Assert.AreEqual<Integer>(DEFAULT_DEPTH, QuestionDefaultDepth('change-impact'));
end;

procedure TExceptionPathsTests.HashtableKeyOrderMatchesPowerShell;
begin
  (* $h = @{}; foreach ($k in ...) { $h[$k] = 1 }; $h.Keys -join ',' -- printed by pwsh 7 *)
  Assert.AreEqual(EP_HT_MIXED_ORDER, IntsText(PsHashtableOrder(EP_HT_MIXED_KEYS)));
  Assert.AreEqual(EP_HT_HUNDREDS_ORDER, IntsText(PsHashtableOrder(EP_HT_HUNDREDS_KEYS)));
  { 151 keys: the table grows 3 -> 7 -> 17 -> 37 -> 89 -> 197 -> 431 buckets, rehashing each time }
  var Keys: TArray<Integer>:= [EP_HT_FIRST];
  for var K:= 1 to EP_HT_COUNT do
    Keys:= Keys + [K * EP_HT_STEP + EP_HT_OFFSET];
  Assert.AreEqual(EP_HT_ORDER, IntsText(PsHashtableOrder(Keys)));
end;

{ ---- who-calls ---- }

{ the -Depth runs on ReserveNextID }
procedure TWhoCallsTests.CheckDepth(pDepth: Integer; const pFields, pDotSha: string);
begin
  CheckAtDepth(WHO_CALLS_ID, WC_CYCLE_TARGET, pDepth, pFields, pDotSha);
end;

procedure TWhoCallsTests.MethodMatchesPowerShell;
var
  C: TChartResult;
begin
  if not EmitChart(WHO_CALLS_ID, WC_TARGET, CLIENT_CLONE, C) then
    Exit;
  Assert.AreEqual(WC_FIELDS, Fields(C));
  Assert.AreEqual(WC_DOT_SHA, FileSha(C.Layout.Dot));
end;

procedure TWhoCallsTests.CycleRowAndNameOnlyMatchPowerShell;
begin
  { AddOperation is reached again at :4102 as a cycle row; 9 of the 18 name matches are sibling classes' own ReserveNextID }
  CheckDepth(WC_CYCLE_DEPTH, WC_CYCLE_FIELDS, WC_CYCLE_DOT_SHA);
end;

procedure TWhoCallsTests.DepthLimitTouchedIsTruncated;
begin
  { Truncated means the depth limit was TOUCHED by a node that has callers, not that rows were dropped }
  CheckDepth(WC_D1_DEPTH, WC_D1_FIELDS, WC_D1_DOT_SHA);
end;

procedure TWhoCallsTests.AnswerMatchesPowerShell;
var
  L: TArray<string>;
begin
  if not Answer(WHO_CALLS_ID, WC_TARGET, CLIENT_CLONE, L) then
    Exit;
  Assert.AreEqual<Integer>(WC_LINES, Length(L));
  Assert.AreEqual('CHART who-calls ' + WC_TARGET + ' -- 9 call sites / 0 cycle rows', L[CS_CHART_LINE]);
end;

procedure TWhoCallsTests.EventHandlerIsRefused;
begin
  Assert.StartsWith(WC_EVENT_TARGET + ' has 0 callers in call_edges (node_count 1). If it is an event handler the ' +
    'caller is the DFM -- ask event-wiring instead.', Refusal(WHO_CALLS_ID, WC_EVENT_TARGET, CLIENT_CLONE));
end;

procedure TWhoCallsTests.UnknownTargetIsRefused;
begin
  Assert.AreEqual('symbol not found: No.Such.Method', Refusal(WHO_CALLS_ID, 'No.Such.Method', CLIENT_CLONE));
end;

procedure TWhoCallsTests.AmbiguousTargetIsRefused;
begin
  { an overloaded routine: two declarations share this qualified name, so the root is not one symbol (D3) }
  Assert.AreEqual('MStreams.TABZMemoryStream.Seek resolves to 2 symbols in this index -- name one qualified routine',
    Refusal(WHO_CALLS_ID, 'MStreams.TABZMemoryStream.Seek', CLIENT_CLONE));
end;

{ ---- what-it-calls ---- }

{ the -Depth runs on SendDeltaOperation }
procedure TWhatItCallsTests.CheckDepth(pDepth: Integer; const pFields, pDotSha: string);
begin
  CheckAtDepth(WHAT_IT_CALLS_ID, WIC_TARGET, pDepth, pFields, pDotSha);
end;

procedure TWhatItCallsTests.MethodMatchesPowerShell;
var
  C: TChartResult;
begin
  { NameMatches / NameOnly are null walking callees: the name bucket answers the caller question only }
  if not EmitChart(WHAT_IT_CALLS_ID, WIC_TARGET, CLIENT_CLONE, C) then
    Exit;
  Assert.AreEqual(WIC_FIELDS, Fields(C));
  Assert.AreEqual(WIC_DOT_SHA, FileSha(C.Layout.Dot));
end;

procedure TWhatItCallsTests.DepthOneIsTruncated;
begin
  CheckDepth(WIC_D1_DEPTH, WIC_D1_FIELDS, WIC_D1_DOT_SHA);
end;

procedure TWhatItCallsTests.CyclesAtDepthThreeMatchPowerShell;
begin
  CheckDepth(WIC_D3_DEPTH, WIC_D3_FIELDS, WIC_D3_DOT_SHA);
end;

procedure TWhatItCallsTests.EdgesLeaveTheFocus;
var
  C: TChartResult;
begin
  { the arrow means "calls": walking callees the focus calls the row (Test-Emitters A-WIC3-EDGEDIR/EDGEDIR2) }
  if not EmitChart(WHAT_IT_CALLS_ID, WIC_TARGET, CLIENT_CLONE, C) then
    Exit;
  var Text:= TFile.ReadAllText(C.Layout.Dot);
  Assert.IsTrue(Text.Contains(' focus -> '), 'an edge leaves the focus');
  Assert.IsFalse(TRegEx.IsMatch(Text, '(?m)^\s+n\d+:p\d+ -> focus'), 'no edge enters the focus');
end;

procedure TWhatItCallsTests.AnswerMatchesPowerShell;
var
  L: TArray<string>;
begin
  if not Answer(WHAT_IT_CALLS_ID, WIC_TARGET, CLIENT_CLONE, L) then
    Exit;
  Assert.AreEqual<Integer>(WIC_LINES, Length(L));
  Assert.AreEqual('CHART what-it-calls ' + WIC_TARGET + ' -- 9 call sites / 0 cycle rows', L[CS_CHART_LINE]);
end;

procedure TWhatItCallsTests.LeafIsRefused;
begin
  { a leaf calls nothing; a DFM is never a callee, so the event-wiring hint must not appear (Test-Emitters N8-HINT) }
  var R:= Refusal(WHAT_IT_CALLS_ID, WIC_LEAF_TARGET, CLIENT_CLONE);
  Assert.StartsWith(WIC_LEAF_TARGET + ' calls nothing in call_edges (node_count 1).', R);
  Assert.IsFalse(R.Contains('event-wiring'), 'no event-wiring hint walking callees');
end;

procedure TWhatItCallsTests.UnknownTargetIsRefused;
begin
  Assert.AreEqual('symbol not found: No.Such.Method', Refusal(WHAT_IT_CALLS_ID, 'No.Such.Method', CLIENT_CLONE));
end;

{ ---- butterfly ---- }

{ ExportPdf is the size of a cairo PDF, which is not byte-stable between two runs (38862 / 38863 measured
  on one build), so it is checked as present and positive, not for equality; Test-Parity masks it likewise }
function TButterflyTests.FieldsWithoutPdf(const pChart: TChartResult): string;
begin
  var Parts: TArray<string>:= [];
  for var F in pChart.Fields do
    if F.Name = 'ExportPdf' then
      Assert.IsTrue(StrToIntDef(F.Json, 0) > 0, 'the PDF was written')
    else
      Parts:= Parts + [F.Name + '=' + F.Json];
  Result:= string.Join(',', Parts);
end;

procedure TButterflyTests.MethodMatchesPowerShell;
var
  C: TChartResult;
begin
  if not EmitChart(BUTTERFLY_ID, BF_TARGET, CLIENT_CLONE, C) then
    Exit;
  Assert.AreEqual(BF_FIELDS, FieldsWithoutPdf(C));
  Assert.AreEqual(BF_DOT_SHA, FileSha(C.Layout.Dot));
end;

procedure TButterflyTests.DepthOneMatchesPowerShell;
var
  A: TQuestionArgs;
  E: TChartEmitter;
begin
  if not Args(BUTTERFLY_ID, BF_TARGET, CLIENT_CLONE, A) then
    Exit;
  A.Depth:= BF_D1_DEPTH;
  Assert.IsTrue(FindChartQuestion(BUTTERFLY_ID, E), 'butterfly is not registered');
  var C:= E(A, FOutRoot);
  Assert.AreEqual(BF_D1_FIELDS, FieldsWithoutPdf(C));
  Assert.AreEqual(BF_D1_DOT_SHA, FileSha(C.Layout.Dot));
end;

procedure TButterflyTests.ArrowsFollowTheTree;
var
  C: TChartResult;
begin
  { only the engine's depth-1 children touch the focus box (Test-Emitters A-BF-FOCUSIN / A-BF-FOCUSOUT) }
  if not EmitChart(BUTTERFLY_ID, BF_TARGET, CLIENT_CLONE, C) then
    Exit;
  var Text:= TFile.ReadAllText(C.Layout.Dot);
  Assert.AreEqual<Integer>(BF_FOCUS_IN, TRegEx.Matches(Text, '(?m)^\s+\S+ -> focus \[').Count);
  Assert.AreEqual<Integer>(BF_FOCUS_OUT, TRegEx.Matches(Text, '(?m)^\s+focus -> \S+ \[').Count);
end;

procedure TButterflyTests.NoDuplicateRowPerSide;
var
  C: TChartResult;
begin
  { D6 (Test-Emitters E-BF-D6): a symbol is one row per side, an arrow one distinct pair }
  if not EmitChart(BUTTERFLY_ID, BF_D6_TARGET, DL_CLONE, C) then
    Exit;
  var Text:= TFile.ReadAllText(C.Layout.Dot);
  var Titles:= TDictionary<string, Boolean>.Create;
  try
    for var M in TRegEx.Matches(Text, '(?s)subgraph (cluster_(in|out)_\d+) \{.*?\n  \}') do
      for var T in TRegEx.Matches(M.Value, 'TITLE="([^"]*)"') do
      begin
        var Key:= M.Groups[2].Value + '|' + T.Groups[1].Value;
        Assert.IsFalse(Titles.ContainsKey(Key), 'duplicate row ' + Key);
        Titles.Add(Key, True);
      end;
  finally
    Titles.Free;
  end;
  var Edges:= TDictionary<string, Boolean>.Create;
  try
    for var E in TRegEx.Matches(Text, '(?m)^\s+(\S+ -> \S+) \[') do
    begin
      Assert.IsFalse(Edges.ContainsKey(E.Groups[1].Value), 'duplicate edge ' + E.Groups[1].Value);
      Edges.Add(E.Groups[1].Value, True);
    end;
  finally
    Edges.Free;
  end;
end;

procedure TButterflyTests.AnswerMatchesPowerShell;
var
  L: TArray<string>;
begin
  if not Answer(BUTTERFLY_ID, BF_TARGET, CLIENT_CLONE, L) then
    Exit;
  Assert.AreEqual<Integer>(BF_LINES, Length(L));
  Assert.AreEqual('CHART butterfly ' + BF_TARGET + ' -- 9 callers / 9 callees', L[CS_CHART_LINE]);
end;

procedure TButterflyTests.UnknownTargetIsRefused;
begin
  Assert.AreEqual('symbol not found: No.Such.Method', Refusal(BUTTERFLY_ID, 'No.Such.Method', CLIENT_CLONE));
end;

procedure THierarchyTests.TypeMatchesPowerShell;
begin
  var C: TChartResult;
  if not EmitChart(HIERARCHY_ID, HI_TARGET, CLIENT_CLONE, C) then
    Exit;
  Assert.AreEqual(HI_FIELDS, Fields(C));
  Assert.AreEqual(HI_DOT_SHA, FileSha(C.Layout.Dot));
  var Text:= TFile.ReadAllText(C.Layout.Dot);
  Assert.IsTrue(Text.Contains('TInterfacedObject'));
  Assert.IsTrue(Text.Contains('outside this project'));
end;

procedure THierarchyTests.MissingFocusDrawsDescendants;  // dl:ok duplicate-code@2bc1 -- REVIEWED 2026-10-16: fixture bodies repeat the EmitChart/Fields/FileSha shape of the sibling parity tests
begin
  var C: TChartResult;
  if not EmitChart(HIERARCHY_ID, HI_RTL_TARGET, CLIENT_CLONE, C) then
    Exit;
  Assert.AreEqual(HI_RTL_FIELDS, Fields(C));
  Assert.AreEqual(HI_RTL_DOT_SHA, FileSha(C.Layout.Dot));
  var Text:= TFile.ReadAllText(C.Layout.Dot);
  Assert.IsTrue(Text.Contains('+125 more descendants not shown'));
  Assert.IsTrue(Text.Contains('>TBlueprint_ViewModel<'));
end;

procedure THierarchyTests.CollidingAncestorIsUnanchored;
begin
  var C: TChartResult;
  if not EmitChart(HIERARCHY_ID, HI_COLLIDE_TARGET, CLIENT_CLONE, C) then
    Exit;
  Assert.AreEqual(HI_COLLIDE_FIELDS, Fields(C));
  Assert.IsTrue(TFile.ReadAllText(C.Layout.Dot).Contains('2 types share this name'));
end;

procedure THierarchyTests.AnswerMatchesPowerShell;
begin
  var L: TArray<string>;
  if not Answer(HIERARCHY_ID, HI_TARGET, CLIENT_CLONE, L) then
    Exit;
  Assert.AreEqual<Integer>(HI_LINES, Length(L));
  Assert.AreEqual('CHART hierarchy ' + HI_TARGET + ' -- 2 ancestors / 0 descendants', L[CS_CHART_LINE]);
  Assert.AreEqual(HI_TARGET_LINE, L[CS_CHART_LINE + 1]);
end;

procedure THierarchyTests.UnknownTypeIsRefused;
begin
  Assert.AreEqual(HI_UNKNOWN + ' is not in this index, and nothing in it inherits from or is inherited by that name',
    Refusal(HIERARCHY_ID, HI_UNKNOWN, CLIENT_CLONE));
end;

procedure THierarchyTests.AmbiguousTypeIsRefused;
begin
  var R:= Refusal(HIERARCHY_ID, HI_AMBIGUOUS, CLIENT_CLONE);
  Assert.StartsWith(HI_AMBIGUOUS + ' is ambiguous -- ', R);
  Assert.IsTrue(R.Contains('they differ by generic parameters'));
end;

end.
