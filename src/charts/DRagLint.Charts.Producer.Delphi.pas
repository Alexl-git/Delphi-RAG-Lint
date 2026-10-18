unit DRagLint.Charts.Producer.Delphi;

(* The report producer (spec P2/P5): answers every chart question in-process
  (DRagLint.Charts.Question's registry) without starting pwsh or drag-lint.exe. Since
  2026-10-18 it is the ONLY producer: the PowerShell fallback (TPowerShellProducer, which ran
  Ask-Report.ps1 -Plain) was removed once all 26 questions were ported, so a command this
  producer cannot answer is REFUSED with the reason, never handed on. The charts\src\*.ps1
  scripts stay in the repo only as the frozen parity reference (Test-Parity.ps1).

  WHAT IT ANSWERS: a registered question whose index is given (TProduceOptions.DbOverride,
  the S4 / test path) or whose -Project is named (what drag-lint compare passes): the
  project's index is the one the engine's own resolve-dbs --project names, asked through
  DRagLint.Charts.Pairs.ResolveProjectIndex -- Ask-Report's step 1 and the ask verb's, so the
  three cannot resolve a project differently. A command naming only -In (no project, no index)
  is refused with exit 2. Freshness IS checked in-process, through the engine's own
  DRagLint.Index.Freshness: a stale index refuses with exit 3 unless AllowStale. The SERVER and SQL
  indexes a question reads, when not given, are paired from report-pairs.json in-process, through the
  same DRagLint.Charts.Pairs the ask verb uses (Ask-Report's step 2, its refusals included).

  LIVE INDEXES (owner ruling 2026-10-14). In real use -- `drag-lint compare` and `drag-lint ask` --
  this producer answers from the live index, protected by the staleness refusal (exit 3, AllowStale
  to override); it is constructed with pAllowLiveDb True. The frozen-clone guard (CloneDb in
  DRagLint.Charts.Tools) stays ON only where pAllowLiveDb is False: the parity harness and the
  tests. ProducerForCompare is the one place compare's choice is made. *)

interface

uses
  DRagLint.Charts.ReportHeader
  , DRagLint.Charts.Producer // dl:unit DRagLint.Charts.Producer accepted -- the producer exit-code constant travels with the seam it belongs to
  ;

type
  /// <summary>Answers every chart question in-process; refuses what it cannot answer.</summary>
  /// <remarks>Holds the description of the last call. Not thread-safe: with AllowLiveDb set, an
  /// answer sets and restores a process environment variable around the emitter, exactly as
  /// Ask-Report did around the bundler.</remarks>
  TDelphiProducer = class(TInterfacedObject, IReportProducer)
  private
    FAllowLiveDb: Boolean;
    FOutRoot    : string;
    FLast       : string;
    function Refuse(pCode: Integer; const pWhy: string): TProduceResult;
  public
    /// <summary>Whether a non-clone (live) index is let through the clone guard.</summary>
    property AllowLiveDb: Boolean read FAllowLiveDb;
    /// <summary>Creates the producer.</summary>
    /// <param name="pAllowLiveDb">Let a non-clone index through the clone guard for the emitter call
    /// (what Ask-Report does). False keeps the guard: only charts\scratch\db clones are answered.</param>
    /// <param name="pOutRoot">The bundle root; '' means %TEMP%\drag-lint-reports (Ask-Report's -OutRoot default).
    /// TProduceOptions.OutRoot, when set, wins over it for one call.</param>
    constructor Create(pAllowLiveDb: Boolean; const pOutRoot: string = '');
    /// <summary>Whether a command can be answered at all.</summary>
    /// <param name="pCommand">The question.</param>
    /// <param name="pOptions">The options; DbOverride, or the command's Project argument, names the index.</param>
    /// <returns>True for a registered question with an index given or a project named (its index is
    /// resolved in Produce, which refuses when it cannot be). crosses-boundary's counterpart is
    /// TProduceOptions.CounterpartDbOverride, else paired from report-pairs.json as Ask-Report pairs it;
    /// with no pair it draws one side, as Ask-Report does. False means Produce refuses with exit 2.</returns>
    function AnswersInProcess(const pCommand: TReportCommand; const pOptions: TProduceOptions): Boolean;
    /// <summary>Answers one question in-process.</summary>
    /// <param name="pCommand">The question and its explicit arguments.</param>
    /// <param name="pOptions">Index override, staleness policy, engine, charts folder.</param>
    /// <returns>As IReportProducer.Produce: exit 0 answered (plain text, CRLF lines, header first),
    /// 1 refused (the emitter's message, or an unexpected failure of the in-process answer, named
    /// with its exception class), 2 setup (an unknown question; no index given and no project named;
    /// index missing; a named project whose file is missing, that no manifest section owns, or whose
    /// resolved index has not been built; a SERVER / SQL index the question reads neither given nor
    /// paired by report-pairs.json -- Ask-Report's own message --; an explicit charts folder that does
    /// not exist), 3 stale.</returns>
    /// <remarks>Never raises.</remarks>
    function Produce(const pCommand: TReportCommand; const pOptions: TProduceOptions): TProduceResult;
    /// <summary>Says what answered the last call.</summary>
    /// <returns>'Delphi in-process (&lt;id&gt;)', 'Delphi in-process, refused: &lt;why&gt;' or
    /// 'Delphi in-process failed (&lt;class&gt;: &lt;message&gt;)'; before any call, the registered ids.</returns>
    function Describe: string;
  end;

/// <summary>The producer `drag-lint compare` uses: the ONE place that choice is made.</summary>
/// <returns>A TDelphiProducer with live indexes allowed (owner ruling 2026-10-14).</returns>
/// <remarks>Live indexes are protected by the staleness refusal, not by the clone guard; the
/// clone guard stays on only in the parity harness and the tests. The CLI's compare verb obtains
/// its producer from this function.</remarks>
function ProducerForCompare: IReportProducer;

implementation

uses
  System.SysUtils, System.IOUtils, DRagLint.Core.Interfaces, DRagLint.Storage.SQLite, DRagLint.Index.Freshness
  , DRagLint.Core.Model // dl:unit DRagLint.Core.Model accepted -- the engine version the header names is the product constant itself
  , DRagLint.Charts.Question // dl:unit DRagLint.Charts.Question accepted -- the bundler defaults and Ask-Report's refusal code travel with the question types
  , DRagLint.Charts.Ask, DRagLint.Charts.Index, DRagLint.Charts.Tools, DRagLint.Charts.Pairs
  , DRagLint.Charts.Q.TouchesTables  // dl:ok unused-unit-in-uses@5c7b -- REVIEWED 2026-10-13: linked for its initialization section, which registers the ported question this producer answers; no symbol is referenced on purpose
  , DRagLint.Charts.Q.ShownWhere  // dl:ok unused-unit-in-uses@62b1 -- REVIEWED 2026-10-13: linked for its initialization section, which registers the ported question this producer answers; no symbol is referenced on purpose
  , DRagLint.Charts.Q.Deps  // dl:ok unused-unit-in-uses@6504 -- REVIEWED 2026-10-13: linked for its initialization section, which registers the ported question this producer answers; no symbol is referenced on purpose
  , DRagLint.Charts.Q.ClassSurface  // dl:ok unused-unit-in-uses@239f -- REVIEWED 2026-10-14: linked for its initialization section, which registers the ported question this producer answers; no symbol is referenced on purpose
  , DRagLint.Charts.Q.EventWiring  // dl:ok unused-unit-in-uses@60ca -- REVIEWED 2026-10-14: linked for its initialization section, which registers the ported question this producer answers; no symbol is referenced on purpose
  , DRagLint.Charts.Q.TestedBy  // dl:ok unused-unit-in-uses@e105 -- REVIEWED 2026-10-14: linked for its initialization section, which registers the ported question this producer answers; no symbol is referenced on purpose
  , DRagLint.Charts.Q.ChangeImpact  // dl:ok unused-unit-in-uses@c0e0 -- REVIEWED 2026-10-14: linked for its initialization section, which registers the ported question this producer answers; no symbol is referenced on purpose
  , DRagLint.Charts.Q.CrossesBoundary  // dl:ok unused-unit-in-uses@0508 -- REVIEWED 2026-10-14: linked for its initialization section, which registers the ported question this producer answers; no symbol is referenced on purpose
  , DRagLint.Charts.Q.ProtocolTrace  // dl:ok unused-unit-in-uses@a865 -- REVIEWED 2026-10-14: linked for its initialization section, which registers the ported question this producer answers; no symbol is referenced on purpose
  , DRagLint.Charts.Q.Lifecycle  // dl:ok unused-unit-in-uses@6e60 -- REVIEWED 2026-10-14: linked for its initialization section, which registers the ported question this producer answers; no symbol is referenced on purpose
  , DRagLint.Charts.Q.Effects  // dl:ok unused-unit-in-uses@db90 -- REVIEWED 2026-10-14: linked for its initialization section, which registers the ported question this producer answers; no symbol is referenced on purpose
  , DRagLint.Charts.Q.FeedsFrom  // dl:ok unused-unit-in-uses@e7ae -- REVIEWED 2026-10-14: linked for its initialization section, which registers the ported question this producer answers; no symbol is referenced on purpose
  , DRagLint.Charts.Q.LandsWhere  // dl:ok unused-unit-in-uses@43f8 -- REVIEWED 2026-10-14: linked for its initialization section, which registers the ported question this producer answers; no symbol is referenced on purpose
  , DRagLint.Charts.Q.Consumers  // dl:ok unused-unit-in-uses@e7fa -- REVIEWED 2026-10-14: linked for its initialization section, which registers the ported question this producer answers; no symbol is referenced on purpose
  , DRagLint.Charts.Q.ExceptionPaths  // dl:ok unused-unit-in-uses@4e99 -- REVIEWED 2026-10-14: linked for its initialization section, which registers the ported question this producer answers; no symbol is referenced on purpose
  , DRagLint.Charts.Q.WhoCalls  // dl:ok unused-unit-in-uses@eb43 -- REVIEWED 2026-10-15: linked for its initialization section, which registers the ported question this producer answers; no symbol is referenced on purpose
  , DRagLint.Charts.Q.Butterfly  // dl:ok unused-unit-in-uses@b637 -- REVIEWED 2026-10-16: linked for its initialization section, which registers the ported question this producer answers; no symbol is referenced on purpose
  , DRagLint.Charts.Q.Hierarchy  // dl:ok unused-unit-in-uses@fe1d -- REVIEWED 2026-10-16: linked for its initialization section, which registers the ported question this producer answers; no symbol is referenced on purpose
  , DRagLint.Charts.Q.Wiring  // dl:ok unused-unit-in-uses@3045 -- REVIEWED 2026-10-16: linked for its initialization section, which registers the ported question this producer answers; no symbol is referenced on purpose
  , DRagLint.Charts.Q.Path  // dl:ok unused-unit-in-uses@4462 -- REVIEWED 2026-10-17: linked for its initialization section, which registers the ported question this producer answers; no symbol is referenced on purpose
  , DRagLint.Charts.Q.Architecture  // dl:ok unused-unit-in-uses@5f81 -- REVIEWED 2026-10-17: linked for its initialization section, which registers the ported question this producer answers; no symbol is referenced on purpose
  , DRagLint.Charts.Q.Cycles  // dl:ok unused-unit-in-uses@c264 -- REVIEWED 2026-10-17: linked for its initialization section, which registers the ported question this producer answers; no symbol is referenced on purpose
  , DRagLint.Charts.Q.MemberAccess  // dl:ok unused-unit-in-uses@a96a -- REVIEWED 2026-10-17: linked for its initialization section, which registers the ported questions this producer answers; no symbol is referenced on purpose
  , DRagLint.Charts.Q.RoundTrip  // dl:ok unused-unit-in-uses@8ca7 -- REVIEWED 2026-10-18: linked for its initialization section, which registers the round-trip question this producer answers; no symbol is referenced on purpose
  ;

const
  EXIT_OK = 0;
  EXIT_SETUP = 2;
  REPORTS_SUBDIR = 'drag-lint-reports';
  CROSSES_BOUNDARY = 'crosses-boundary';
  PROJECT_ARG = 'Project';
  { Ask-Report's own override flags, named in its pairing refusals }
  ASK_REPORT_SERVER_FLAG = '-ServerDbPath';
  ASK_REPORT_SQL_FLAG = '-SqlDbPath';
  CRLF = #13#10;

function ProducerForCompare: IReportProducer;
begin
  Result:= TDelphiProducer.Create(True);
end;

constructor TDelphiProducer.Create(pAllowLiveDb: Boolean; const pOutRoot: string);
begin
  inherited Create;
  FAllowLiveDb:= pAllowLiveDb;
  FOutRoot:= if pOutRoot <> '' then pOutRoot else TPath.Combine(TPath.GetTempPath, REPORTS_SUBDIR);
end;

function TDelphiProducer.AnswersInProcess(const pCommand: TReportCommand; const pOptions: TProduceOptions): Boolean;
var
  E: TChartEmitter;
begin
  Result:= ((pOptions.DbOverride <> '') or (pCommand.Get(PROJECT_ARG) <> '')) and FindChartQuestion(pCommand.Question, E);
end;

function Fail(pCode: Integer; const pReason: string): TProduceResult;
begin
  Result:= Default(TProduceResult);
  Result.ExitCode:= pCode;
  Result.Reason:= pReason;
end;

{ True when pDb is already in pList (paths compared as Windows compares them) }
function InIndexList(const pDb: string; const pList: TArray<string>): Boolean;
begin
  Result:= False;
  for var D in pList do
    if SameText(D, pDb) then
      Exit(True);
end;

{ Ask-Report's step 3, through the engine's own sweep; the store is closed before the emitter opens the index }
function Freshness(const pDb: string): TFreshnessReport;
begin
  var Store: ISymbolStore:= TSQLiteSymbolStore.Create(pDb, True);
  Result:= ProbeIndexFreshness(Store);
end;

{ An explicit numeric argument when given, else the bundler's default. }
function NumArg(const pCommand: TReportCommand; const pName: string; pDefault: Integer): Integer;
begin
  Result:= if pCommand.Has(pName) then StrToIntDef(pCommand.Get(pName), pDefault) else pDefault;
end;

{ The SERVER and SQL indexes, only for a question that reads them (Ask-Report's $needServer /
  $needSql), and crosses-boundary's counterpart ($wantOther): as given, else paired from
  report-pairs.json exactly as Ask-Report's step 2 pairs them -- compare passes only --db (R5).
  Raises EReportPairStop with Ask-Report's code and message.
  crosses-boundary with no pair keeps Other '' and goes on, as Ask-Report does (Ask-Report.ps1:262):
  one side drawn. }
function PairedIndexes(const pCommand: TReportCommand; const pOptions: TProduceOptions): TPairedIndexes;
begin
  Result:= Default(TPairedIndexes);
  var Req:= Default(TPairRequest);
  Req.Question:= pCommand.Question.ToLower;
  Req.Db:= pOptions.DbOverride;
  Req.Engine:= pOptions.EnginePath;
  Req.NeedServer:= QuestionReadsServerIndex(Req.Question);
  Req.NeedSql:= QuestionReadsSqlIndex(Req.Question);
  Req.WantOther:= SameText(Req.Question, CROSSES_BOUNDARY);
  Req.ServerFlag:= ASK_REPORT_SERVER_FLAG;
  Req.SqlFlag:= ASK_REPORT_SQL_FLAG;
  if Req.NeedServer then Result.Server:= pOptions.ServerDbOverride;
  if Req.NeedSql then Result.Sql:= pOptions.SqlDbOverride;
  if Req.WantOther then Result.Other:= pOptions.CounterpartDbOverride;
  var Missing:= (Req.NeedServer and (Result.Server = '')) or (Req.NeedSql and (Result.Sql = ''));
  if Missing or (Req.WantOther and (Result.Other = '')) then
    PairOtherIndexes(LoadReportPairs(pOptions.PairsFile, pOptions.ScriptPath), Req, Result);
end;

{ Ask-Report's step 1: the index given, else -- a command naming only a project, as compare passes
  it -- the one the engine's resolve-dbs --project names (DRagLint.Charts.Pairs.ResolveProjectIndex,
  the ask verb's resolver). Raises EReportPairStop with Ask-Report's setup code when the engine
  names none, or names one that has not been built. }
function ProjectIndex(const pCommand: TReportCommand; const pOptions: TProduceOptions): string;
begin
  Result:= pOptions.DbOverride;
  if Result <> '' then Exit;
  var Pj:= pCommand.Get(PROJECT_ARG);
  var Why: string;
  if not ResolveProjectIndex(pOptions.EnginePath, Pj, Result, Why) then
    raise EReportPairStop.CreateCode(EXIT_SETUP, Why);
  if not TFile.Exists(Result) then
    raise EReportPairStop.CreateCode(EXIT_SETUP, Format('index not found: %s -- resolve-dbs --project %s names it, but it ' +
      'has not been built; index the project first', [Result, ExpandFileName(Pj)]));
end;

{ A command this producer cannot answer: there is no other producer to hand it to (2026-10-18),
  so it is refused with the reason, and Describe says so. }
function TDelphiProducer.Refuse(pCode: Integer; const pWhy: string): TProduceResult;
begin
  FLast:= 'Delphi in-process, refused: ' + pWhy;
  Result:= Fail(pCode, pWhy);
end;

function TDelphiProducer.Produce(const pCommand: TReportCommand; const pOptions: TProduceOptions): TProduceResult;
var
  Em: TChartEmitter;
begin
  if not FindChartQuestion(pCommand.Question, Em) then
    Exit(Refuse(EXIT_SETUP, Format('unknown question ''%s'' -- one of: %s', [pCommand.Question, string.Join(', ', PortedQuestionIds)])));
  if not AnswersInProcess(pCommand, pOptions) then
    Exit(Refuse(EXIT_SETUP, 'no index given (--db / -Db) and no project named (--project / -Project); name the project ' +
      'whose index answers the question'));
  FLast:= 'Delphi in-process (' + pCommand.Question.ToLower + ')';
  var O:= pOptions;
  var Ix: TPairedIndexes;
  try
    O.DbOverride:= ProjectIndex(pCommand, pOptions);
    Ix:= PairedIndexes(pCommand, O);
  except
    on E: EReportPairStop do
      Exit(Fail(E.Code, E.Message));
  end;
  var Db:= ExpandFileName(O.DbOverride);
  var Server:= if Ix.Server <> '' then ExpandFileName(Ix.Server) else '';
  var Sql:= if Ix.Sql <> '' then ExpandFileName(Ix.Sql) else '';
  var Other:= if Ix.Other <> '' then ExpandFileName(Ix.Other) else '';
  { a missing index, then a missing charts folder: either is a setup refusal (exit 2) }
  var Setup:= '';
  for var D in TArray<string>.Create(Db, Server, Sql, Other) do
    if (Setup = '') and (D <> '') and not TFile.Exists(D) then
      Setup:= 'index not found: ' + D;
  var ChartsRoot, ScriptDir, Why: string;
  if (Setup = '') and not ResolveChartsHome(pOptions.ScriptPath, ChartsRoot, ScriptDir, Why) then
    Setup:= 'the charts folder was not found (it holds the clone root and the dot settings): ' + Why;
  if Setup <> '' then
    Exit(Fail(EXIT_SETUP, Setup));

  var Q:= Default(TQuestionArgs);
  Q.Question:= pCommand.Question.ToLower;
  Q.Target:= pCommand.Get('Target');
  Q.DbPath:= Db;
  Q.CounterpartDb:= Other;
  Q.ServerDbPath:= Server;
  Q.SqlDbPath:= Sql;
  Q.OutRoot:= if pOptions.OutRoot <> '' then pOptions.OutRoot else FOutRoot;
  Q.ChartsRoot:= ChartsRoot;
  Q.ScriptDir:= ScriptDir;  { installed copy: <app>\bin, where graphviz\bin sits beside the engine }
  Q.Cap:= NumArg(pCommand, 'Cap', DEFAULT_CAP);
  Q.Depth:= NumArg(pCommand, 'Depth', QuestionDefaultDepth(Q.Question));
  Q.SurfaceCap:= NumArg(pCommand, 'SurfaceCap', DEFAULT_SURFACE_CAP);
  Q.MaxRows:= NumArg(pCommand, 'MaxRows', DEFAULT_MAX_ROWS);
  Q.Command:= pCommand;
  Q.Command.Question:= Q.Question;
  Q.AllowLiveDb:= FAllowLiveDb;
  Q.AskedOn:= Now;
  Q.EngineVersion:= DRAGLINT_VERSION;
  { FAILURE POLICY (engine review 2026-10-13; fallback removed 2026-10-18). A refusal
    Ask-Report.ps1 would ALSO give stays a refusal with Ask-Report's exit code: index missing /
    no charts folder -> 2 (above), stale -> 3, question or index-lookup refusal -> 1, tool or
    clone-guard refusal -> 2. ANY OTHER exception -- including one from the freshness probe,
    which is therefore inside this try -- is a failure of the in-process answer: exit 1, named
    with its exception class so it reads as a defect and not as a verdict about the question.
    Nothing escapes Produce. }
  try
    { every index the question reads, once each, in Ask-Report's order: project, server, sql, counterpart }
    var StaleLines:= '';
    var Read: TArray<string>:= [Db];
    for var D in TArray<string>.Create(Server, Sql, Other) do
      if (D <> '') and not InIndexList(D, Read) then
        Read:= Read + [D];
    for var D in Read do
    begin
      var Rep:= Freshness(D);
      if Rep.Verdict = fvStale then
        StaleLines:= StaleLines + sLineBreak + Format('  %s: %d file(s) changed since it was indexed', [D, Rep.Changed]);
    end;
    if (StaleLines <> '') and not pOptions.AllowStale then
      Exit(Fail(PRODUCER_EXIT_STALE, 'stale index -- the answer would be short or wrong. Reindex incrementally, then ask again:' + StaleLines));
    var Answer:= AskChartQuestion(Q);
    Result:= Default(TProduceResult);
    Result.Ok:= True;
    Result.ExitCode:= EXIT_OK;
    Result.Text:= string.Join(CRLF, Answer.Lines) + CRLF;
    Result.IndexPaths:= Read;
    Result.BundlePath:= Answer.BundleDir;
  except
    on E: EChartsQuestion do
      Result:= Fail(ASK_EXIT_REFUSED, E.Message);
    on E: EChartsIndex do
      Result:= Fail(ASK_EXIT_REFUSED, E.Message);
    on E: EChartsTool do
      Result:= Fail(EXIT_SETUP, E.Message);
    on E: Exception do
    begin
      FLast:= Format('Delphi in-process failed (%s: %s)', [E.ClassName, E.Message]);
      Result:= Fail(ASK_EXIT_REFUSED, Format('the in-process answer failed (%s: %s)', [E.ClassName, E.Message]));
    end;
  end;
end;

function TDelphiProducer.Describe: string;
begin
  Result:= if FLast <> '' then FLast else 'Delphi in-process (' + string.Join(', ', PortedQuestionIds) + ')';
end;

end.
