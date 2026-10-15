unit DRagLint.Charts.Producer.Delphi;

(* The in-process report producer (spec P2/P5): answers the questions ported to Delphi
  (DRagLint.Charts.Question's registry) without starting pwsh or drag-lint.exe, and hands
  every other question to a fallback producer -- the PowerShell one.

  WHAT IT ANSWERS IN-PROCESS: a ported question whose index is given (TProduceOptions.
  DbOverride, the S4 / test path). Resolving -Project / -In to an index is the engine's
  resolve-dbs (manifest, pairing file), which lives in DRagLint.CLI and is not linked from
  src\charts, so a command that names only a project goes to the fallback, which resolves
  it exactly as Ask-Report does. Freshness IS checked in-process, through the engine's own
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
  /// <summary>Answers ported questions in-process; delegates the rest.</summary>
  /// <remarks>Holds its fallback (reference-counted) and the description of the last call.
  /// Not thread-safe: with AllowLiveDb set, an answer sets and restores a process environment
  /// variable around the emitter, exactly as Ask-Report does around the bundler.</remarks>
  TDelphiProducer = class(TInterfacedObject, IReportProducer)
  private
    FFallback   : IReportProducer;
    FAllowLiveDb: Boolean;
    FOutRoot    : string;
    FLast       : string;
    function FallBack(const pCommand: TReportCommand; const pOptions: TProduceOptions; const pWhy: string): TProduceResult;
  public
    /// <summary>Whether a non-clone (live) index is let through the clone guard.</summary>
    property AllowLiveDb: Boolean read FAllowLiveDb;
    /// <summary>Creates the producer.</summary>
    /// <param name="pFallback">Answers every question this producer does not; must not be nil.</param>
    /// <param name="pAllowLiveDb">Let a non-clone index through the clone guard for the emitter call
    /// (what Ask-Report does). False keeps the guard: only charts\scratch\db clones are answered.</param>
    /// <param name="pOutRoot">The bundle root; '' means %TEMP%\drag-lint-reports (Ask-Report's -OutRoot default).
    /// TProduceOptions.OutRoot, when set, wins over it for one call.</param>
    constructor Create(const pFallback: IReportProducer; pAllowLiveDb: Boolean; const pOutRoot: string = '');
    /// <summary>Whether a command would be answered in-process.</summary>
    /// <param name="pCommand">The question.</param>
    /// <param name="pOptions">The options; DbOverride must be set.</param>
    /// <returns>True for a ported question with an index given. crosses-boundary's counterpart is
    /// TProduceOptions.CounterpartDbOverride, else paired from report-pairs.json as Ask-Report pairs it;
    /// with no pair it draws one side, as Ask-Report does.</returns>
    function AnswersInProcess(const pCommand: TReportCommand; const pOptions: TProduceOptions): Boolean;
    /// <summary>Answers one question, in-process when ported, else through the fallback.</summary>
    /// <param name="pCommand">The question and its explicit arguments.</param>
    /// <param name="pOptions">Index override, staleness policy, engine, script, timeout.</param>
    /// <returns>As IReportProducer.Produce: exit 0 answered (plain text, CRLF lines, header first),
    /// 1 refused (the emitter's message), 2 setup (index missing, a SERVER / SQL index the question
    /// reads neither given nor paired by report-pairs.json -- Ask-Report's own message --, charts folder not found, or a
    /// PORTED question that has to fall back while its Emit-*.ps1 is not beside Ask-Report.ps1 --
    /// an installed copy, which does not ship the ported scripts), 3 stale.</returns>
    function Produce(const pCommand: TReportCommand; const pOptions: TProduceOptions): TProduceResult;
    /// <summary>Says what answered the last call.</summary>
    /// <returns>'Delphi in-process (&lt;ids&gt;)' or 'Delphi in-process, fell back to: &lt;fallback&gt;'.</returns>
    function Describe: string;
  end;

/// <summary>The producer `drag-lint compare` uses: the ONE place that choice is made.</summary>
/// <returns>A TDelphiProducer with live indexes allowed (owner ruling 2026-10-14) and a
/// TPowerShellProducer as its fallback for every question not ported to Delphi.</returns>
/// <remarks>Live indexes are protected by the staleness refusal, not by the clone guard; the
/// clone guard stays on only in the parity harness and the tests. The CLI's compare verb obtains
/// its producer from this function.</remarks>
function ProducerForCompare: IReportProducer;

/// <summary>The file name of a question's PowerShell emitter, beside Ask-Report.ps1.</summary>
/// <param name="pId">A question id, e.g. crosses-boundary.</param>
/// <returns>'Emit-' + the id in PascalCase + '.ps1', e.g. Emit-CrossesBoundary.ps1. Every ported
/// id follows this convention (guarded by a test against charts\src).</returns>
function EmitterScriptName(const pId: string): string;
implementation

uses
  System.SysUtils, System.IOUtils, DRagLint.Core.Interfaces, DRagLint.Storage.SQLite, DRagLint.Index.Freshness
  , DRagLint.Core.Model // dl:unit DRagLint.Core.Model accepted -- the engine version the header names is the product constant itself
  , DRagLint.Charts.Question // dl:unit DRagLint.Charts.Question accepted -- the bundler defaults and Ask-Report's refusal code travel with the question types
  , DRagLint.Charts.Ask, DRagLint.Charts.Producer.PowerShell, DRagLint.Charts.Index, DRagLint.Charts.Tools, DRagLint.Charts.Pairs
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
  ;

const
  EXIT_OK = 0;
  EXIT_SETUP = 2;
  REPORTS_SUBDIR = 'drag-lint-reports';
  CROSSES_BOUNDARY = 'crosses-boundary';
  { Ask-Report's own override flags, named in its pairing refusals }
  ASK_REPORT_SERVER_FLAG = '-ServerDbPath';
  ASK_REPORT_SQL_FLAG = '-SqlDbPath';
  CRLF = #13#10;

function ProducerForCompare: IReportProducer;
begin
  Result:= TDelphiProducer.Create(TPowerShellProducer.Create, True);
end;

function EmitterScriptName(const pId: string): string;
begin
  Result:= 'Emit-';
  for var Part in pId.ToLower.Split(['-']) do
    if Part <> '' then
      Result:= Result + UpperCase(Part.Chars[0]) + Part.Substring(1);
  Result:= Result + '.ps1';
end;

constructor TDelphiProducer.Create(const pFallback: IReportProducer; pAllowLiveDb: Boolean; const pOutRoot: string);
begin
  inherited Create;
  FFallback:= pFallback;
  FAllowLiveDb:= pAllowLiveDb;
  FOutRoot:= if pOutRoot <> '' then pOutRoot else TPath.Combine(TPath.GetTempPath, REPORTS_SUBDIR);
end;

function TDelphiProducer.AnswersInProcess(const pCommand: TReportCommand; const pOptions: TProduceOptions): Boolean;
var
  E: TChartEmitter;
begin
  Result:= (pOptions.DbOverride <> '') and FindChartQuestion(pCommand.Question, E);
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

{ Hands a question to the fallback. A PORTED question falls back only when its PowerShell emitter
  is beside the resolved Ask-Report.ps1: the installer does not ship the ported Emit-*.ps1 (owner
  ruling), so in an installed copy the fallback would fail obscurely -- refuse with pWhy instead.
  An unresolvable Ask-Report.ps1 is left to the fallback, which reports it itself. }
function TDelphiProducer.FallBack(const pCommand: TReportCommand; const pOptions: TProduceOptions; const pWhy: string): TProduceResult;
var
  E: TChartEmitter;
begin
  if FindChartQuestion(pCommand.Question, E) then
  begin
    var NotFound: string;
    var Script:= ResolveAskReportScript(pOptions.ScriptPath, NotFound);
    if (Script <> '') and not TFile.Exists(TPath.Combine(ExtractFileDir(Script), EmitterScriptName(pCommand.Question))) then
    begin
      FLast:= 'Delphi in-process, no fallback installed: ' + pWhy;
      Exit(Fail(EXIT_SETUP, Format('%s is answered by the engine in this install, and its PowerShell fallback is not installed: %s',
        [pCommand.Question.ToLower, pWhy])));
    end;
  end;
  Result:= FFallback.Produce(pCommand, pOptions);
end;

function TDelphiProducer.Produce(const pCommand: TReportCommand; const pOptions: TProduceOptions): TProduceResult;
begin
  if not AnswersInProcess(pCommand, pOptions) then
  begin
    FLast:= 'Delphi in-process, fell back to: ' + FFallback.Describe;
    var WhyNot:= 'no index given (--db / -Db); naming only a project needs the PowerShell fallback';
    Exit(FallBack(pCommand, pOptions, WhyNot));
  end;
  FLast:= 'Delphi in-process (' + pCommand.Question.ToLower + ')';
  var Ix: TPairedIndexes;
  try
    Ix:= PairedIndexes(pCommand, pOptions);
  except
    on E: EReportPairStop do
      Exit(Fail(E.Code, E.Message));
  end;
  var Db:= ExpandFileName(pOptions.DbOverride);
  var Server:= if Ix.Server <> '' then ExpandFileName(Ix.Server) else '';
  var Sql:= if Ix.Sql <> '' then ExpandFileName(Ix.Sql) else '';
  var Other:= if Ix.Other <> '' then ExpandFileName(Ix.Other) else '';
  for var D in TArray<string>.Create(Db, Server, Sql, Other) do
    if (D <> '') and not TFile.Exists(D) then
      Exit(Fail(EXIT_SETUP, 'index not found: ' + D));
  var Why: string;
  var Script:= ResolveAskReportScript(pOptions.ScriptPath, Why);
  if Script = '' then
    Exit(Fail(EXIT_SETUP, 'the charts folder was not found (it holds the clone root and the dot settings); looked for Ask-Report.ps1 at' +
      sLineBreak + Why));

  var Q:= Default(TQuestionArgs);
  Q.Question:= pCommand.Question.ToLower;
  Q.Target:= pCommand.Get('Target');
  Q.DbPath:= Db;
  Q.CounterpartDb:= Other;
  Q.ServerDbPath:= Server;
  Q.SqlDbPath:= Sql;
  Q.OutRoot:= if pOptions.OutRoot <> '' then pOptions.OutRoot else FOutRoot;
  Q.ChartsRoot:= ExtractFileDir(ExtractFileDir(Script));
  Q.ScriptDir:= ExtractFileDir(Script);  { installed copy: <app>\bin, where graphviz\bin sits beside the scripts }
  Q.Cap:= NumArg(pCommand, 'Cap', DEFAULT_CAP);
  Q.Depth:= NumArg(pCommand, 'Depth', QuestionDefaultDepth(Q.Question));
  Q.SurfaceCap:= NumArg(pCommand, 'SurfaceCap', DEFAULT_SURFACE_CAP);
  Q.MaxRows:= NumArg(pCommand, 'MaxRows', DEFAULT_MAX_ROWS);
  Q.Command:= pCommand;
  Q.Command.Question:= Q.Question;
  Q.AllowLiveDb:= FAllowLiveDb;
  Q.AskedOn:= Now;
  Q.EngineVersion:= DRAGLINT_VERSION;
  { FAILURE POLICY (engine review 2026-10-13). A refusal Ask-Report.ps1 would ALSO give stays
    a refusal with Ask-Report's exit code, so the two producers agree: index missing / no
    charts folder -> 2 (above), stale -> 3, question or index-lookup refusal -> 1, tool or
    clone-guard refusal -> 2. ANY OTHER exception -- including one from the freshness probe,
    which is therefore inside this try -- is not a verdict about the question but a failure
    of the in-process path, so the question is handed to the fallback producer and Describe
    says why. Nothing escapes Produce. }
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
      FLast:= Format('Delphi in-process failed (%s: %s), fell back to: %s', [E.ClassName, E.Message, FFallback.Describe]);
      Result:= FallBack(pCommand, pOptions, Format('the in-process answer failed (%s: %s)', [E.ClassName, E.Message]));
    end;
  end;
end;
function TDelphiProducer.Describe: string;
begin
  Result:= if FLast <> '' then FLast else 'Delphi in-process (' + string.Join(', ', PortedQuestionIds) + ')';
end;

end.
