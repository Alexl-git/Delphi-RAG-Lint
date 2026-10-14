unit DRagLint.Charts.AskVerb;

(* `drag-lint ask` -- ONE command that asks a report question and prints the answer as text:
  the engine's own twin of charts\src\Ask-Report.ps1, with the same arguments, the same
  output and the same exit codes.

  WHAT IT DOES, IN Ask-Report's ORDER.
    1. the question: one of the 26 ids (case-insensitive, then lower-cased, Ask-Report R13).
    2. the PROJECT index: --db as given, else the engine's own `resolve-dbs --project` /
       `--in` (when --in names several indexes, the one report-pairs.json pairs is taken).
       The engine is asked as a child process, exactly as Ask-Report asks it, so the --in
       membership probe and its ordering are the CLI's own and are not copied here.
    3. the SERVER / SQL / counterpart indexes the question reads come from report-pairs.json
       unless --server-db / --sql-db / --counterpart-db name them; a pairing-file path must
       still be one the manifest configures.
    4. freshness: every index it will read is probed (DRagLint.Index.Freshness); a stale one
       stops the run with exit 3 and the exact incremental reindex command, unless
       --allow-stale. It never indexes anything itself.
    5. the answer comes from a producer: TDelphiProducer (in-process for the ported
       questions, on the LIVE index -- owner ruling 2026-10-14) with TPowerShellProducer
       (Ask-Report.ps1 -Plain) as its fallback for every other question.
    6. stdout: --plain prints exactly what Ask-Report -Plain prints; the default prints the
       DocInsight remarks block (DRagLint.Charts.DocInsight), exactly what Ask-Report's
       default mode printed. --open opens the bundle's index.html.

  Exit codes (Ask-Report's): 0 answered; 1 the question refused or failed; 2 setup (usage,
  the indexes could not be resolved); 3 an index is stale. Every refusal is ONE stderr text
  starting 'ask-report: ' -- the prefix the IDE plugin and the DocInsight formatter key on --
  and nothing is printed on stdout for it. *)

interface

uses
  DRagLint.Charts.ReportHeader, DRagLint.Charts.Producer;

const
  /// <summary>Exit code: answered.</summary>
  ASK_VERB_EXIT_ANSWERED = 0;
  /// <summary>Exit code: the question refused or failed (Ask-Report's 1).</summary>
  ASK_VERB_EXIT_REFUSED = 1;
  /// <summary>Exit code: usage or setup -- the indexes could not be resolved (Ask-Report's 2).</summary>
  ASK_VERB_EXIT_SETUP = 2;
  /// <summary>Exit code: an index is stale (Ask-Report's 3).</summary>
  ASK_VERB_EXIT_STALE = 3;
  /// <summary>The prefix of every refusal and note on stderr, shared with Ask-Report.ps1.</summary>
  ASK_VERB_ERR_PREFIX = 'ask-report: ';

type
  /// <summary>The parsed arguments of `drag-lint ask`.</summary>
  /// <remarks>A value record. A numeric argument is kept as typed ('' = not given), so the
  /// COMMAND line names exactly what was asked; ParseAskArgs has already checked it is an
  /// integer.</remarks>
  TAskVerbArgs = record
    /// <summary>The question id as typed (positional, or --question).</summary>
    Question     : string;
    /// <summary>--target: the selection.</summary>
    Target       : string;
    /// <summary>--to: routine B of the path question.</summary>
    ToRoutine    : string;
    /// <summary>--project: the project file whose index answers.</summary>
    Project      : string;
    /// <summary>--in: any unit or form of the project.</summary>
    InFile       : string;
    /// <summary>--db: the project index, skipping resolution (never its freshness check).</summary>
    DbPath       : string;
    /// <summary>--server-db: the SERVER index of round-trip / lands-where.</summary>
    ServerDb     : string;
    /// <summary>--sql-db: the SQL-script index.</summary>
    SqlDb        : string;
    /// <summary>--counterpart-db: the other side of crosses-boundary.</summary>
    CounterpartDb: string;
    /// <summary>--control: event-wiring's control.</summary>
    Control      : string;
    /// <summary>--mode: member access mode (write, read, both).</summary>
    Mode         : string;
    /// <summary>--depth, as typed.</summary>
    Depth        : string;
    /// <summary>--cap, as typed.</summary>
    Cap          : string;
    /// <summary>--surface-cap, as typed.</summary>
    SurfaceCap   : string;
    /// <summary>--max-rows, as typed.</summary>
    MaxRows      : string;
    /// <summary>--out-root: where the bundle folder is made; '' = %TEMP%\drag-lint-reports.</summary>
    OutRoot      : string;
    /// <summary>--pairs-file: the report-pairs.json; '' = ResolveReportPairsFile.</summary>
    PairsFile    : string;
    /// <summary>The engine asked for resolve-dbs and named in a reindex command; '' = the
    /// running executable. Not a command-line flag (tests set it).</summary>
    Engine       : string;
    /// <summary>--allow-stale: answer from a stale index, with a note.</summary>
    AllowStale   : Boolean;
    /// <summary>--plain: the plain answer instead of the DocInsight block.</summary>
    Plain        : Boolean;
    /// <summary>--open: open the bundle's index.html.</summary>
    Open         : Boolean;
    /// <summary>--resolve-only: print the indexes it would use and stop.</summary>
    ResolveOnly  : Boolean;
    /// <summary>--help / -h.</summary>
    Help         : Boolean;
  end;

  /// <summary>Receives one output line (no line end).</summary>
  /// <param name="pLine">The line.</param>
  TAskWriter = reference to procedure(const pLine: string);

/// <summary>Parses the arguments that follow the verb.</summary>
/// <param name="pArgv">The tokens after `ask`, in order.</param>
/// <param name="pArgs">The parsed arguments; Default(TAskVerbArgs) plus what was given.</param>
/// <param name="pError">'' on success; otherwise what is wrong, in one line.</param>
/// <returns>False for an unknown flag, a flag without its value, a second positional token,
/// or a --depth / --cap / --surface-cap / --max-rows that is not an integer.</returns>
/// <remarks>The first token that is not a flag is the question; --question names it too.
/// Flags are case-sensitive, as every other engine flag. Pure; thread-safe.</remarks>
function ParseAskArgs(const pArgv: TArray<string>; out pArgs: TAskVerbArgs; out pError: string): Boolean;

/// <summary>Matches a typed question id against the 26 the chart pipeline accepts.</summary>
/// <param name="pTyped">The id as typed, any case.</param>
/// <param name="pId">The matched id, lower case; '' when there is none.</param>
/// <returns>True when the id is known.</returns>
function NormaliseAskQuestion(const pTyped: string; out pId: string): Boolean;

/// <summary>The question and its explicit arguments, as the answer's COMMAND line names them.</summary>
/// <param name="pArgs">The parsed arguments; Question must already be normalised.</param>
/// <returns>Target, To, Project (full path) or else In (full path), Depth, Cap, SurfaceCap,
/// Control, Mode, MaxRows -- each only when given. Never an index override or a display
/// switch (Ask-Report's Get-ReportCommandLine, header contract H2).</returns>
function AskCommandOf(const pArgs: TAskVerbArgs): TReportCommand;

/// <summary>The text `drag-lint ask` prints for an answer.</summary>
/// <param name="pQuestion">The normalised question id.</param>
/// <param name="pShownTarget">The target; 'A -> B' for path.</param>
/// <param name="pPlainText">The producer's plain answer (CRLF, LF or CR line ends).</param>
/// <param name="pPlain">True: the plain answer itself. False: its DocInsight block.</param>
/// <param name="pAskedOn">When it was asked; the DocInsight form prints it only for a legacy
/// answer without a header.</param>
/// <returns>The lines to print, without line ends; a final empty line of the input is
/// dropped.</returns>
/// <remarks>The DocInsight form is FormatAnswerAsDocInsight with the question's caption
/// phrase -- the bytes Ask-Report's default mode and the IDE's Reports menu produce. Pure.</remarks>
function FormatAskAnswer(const pQuestion, pShownTarget, pPlainText: string; pPlain: Boolean;
  pAskedOn: TDateTime): TArray<string>;

/// <summary>Runs `drag-lint ask`.</summary>
/// <param name="pArgs">The parsed arguments.</param>
/// <param name="pProducer">The producer to answer with; nil = TDelphiProducer (live indexes
/// allowed, bundle under pArgs.OutRoot) with a TPowerShellProducer fallback.</param>
/// <param name="pOut">Receives each stdout line.</param>
/// <param name="pErr">Receives each stderr line.</param>
/// <returns>0 answered, 1 refused or failed, 2 usage or setup, 3 stale index.</returns>
/// <remarks>Never raises: an unexpected exception is a refusal (exit 1) with its message.
/// The producer is called with every index resolved and AllowStale True (freshness is checked
/// here first). Not thread-safe: the in-process producer touches the process environment.</remarks>
function RunAsk(const pArgs: TAskVerbArgs; const pProducer: IReportProducer;
  const pOut, pErr: TAskWriter): Integer;

/// <summary>The engine entry point: parses ParamStr(2..) and runs the verb on the console.</summary>
/// <returns>The exit code RunAsk returns; 2 for a usage error, 0 for --help.</returns>
function RunAskVerbFromCommandLine: Integer;

/// <summary>The verb's usage text.</summary>
/// <returns>The lines --help prints for `ask`.</returns>
function AskUsage: TArray<string>;

implementation

uses
  System.SysUtils, System.IOUtils, System.JSON, System.StrUtils
  , DRagLint.Core.Interfaces, DRagLint.Storage.SQLite, DRagLint.Index.Freshness
  , DRagLint.Charts.DocInsight, DRagLint.Charts.Process, DRagLint.Charts.Render
  , DRagLint.Charts.Question  // dl:unit DRagLint.Charts.Question accepted -- the question catalog and its caption phrase travel with the question types
  , DRagLint.Charts.Producer.PowerShell, DRagLint.Charts.Producer.Delphi
  ;

const
  CRLF = #13#10;
  ENGINE_TIMEOUT_MS = 120000;
  PAIRS_FILE_NAME = 'report-pairs.json';
  USER_PAIRS_REL = 'drag-lint\' + PAIRS_FILE_NAME;
  DRAG_DIR = '_D-RAG';
  SHELL_HTML = 'index.html';
  Q_ROUND_TRIP = 'round-trip';
  Q_LANDS_WHERE = 'lands-where';
  Q_CONSUMERS = 'consumers';
  Q_FEEDS_FROM = 'feeds-from';
  Q_CROSSES = 'crosses-boundary';
  Q_PATH = 'path';

type
  { One entry of report-pairs.json. }
  TReportPair = record
    Name, Client, Server, Sql, SqlSection: string;
  end;

  { Every refusal: the exit code travels with the message, as Ask-Report's Stop-Ask. }
  EAskStop = class(Exception)
  private
    FCode: Integer;
  public
    constructor CreateCode(pCode: Integer; const pMessage: string);
    property Code: Integer read FCode;
  end;

constructor EAskStop.CreateCode(pCode: Integer; const pMessage: string);
begin
  inherited Create(pMessage);
  FCode:= pCode;
end;

function AskUsage: TArray<string>;
begin
  Result:= [
    'Usage: drag-lint ask <question> --target <T> [--project <P.dproj> | --in <U.pas> | --db <index>]',
    '         [--to <routine B>] [--server-db <idx>] [--sql-db <idx>] [--counterpart-db <idx>]',
    '         [--depth N] [--cap N] [--surface-cap N] [--control <C>] [--mode write|read|both] [--max-rows N]',
    '         [--out-root <dir>] [--pairs-file <report-pairs.json>] [--allow-stale] [--plain] [--open] [--resolve-only]',
    '  <question>: ' + string.Join(', ', QuestionIds),
    '  Default output: the DocInsight /// <remarks> block; --plain: the plain answer (header, COMMAND, BUNDLE, INDEX, text).',
    '  Exit: 0 answered, 1 refused, 2 usage/setup, 3 stale index (stderr names the reindex command).'];
end;

{ ---- parsing ---- }

type
  { Every flag `ask` takes; FLAG_NAMES spells them. }
  TAskFlag = (afQuestion, afTarget, afTo, afProject, afIn, afDb, afServerDb, afSqlDb, afCounterpartDb, afControl,
    afMode, afDepth, afCap, afSurfaceCap, afMaxRows, afOutRoot, afPairsFile, afAllowStale, afPlain, afOpen,
    afResolveOnly, afHelp, afHelpShort);

const
  FLAG_NAMES: array[TAskFlag] of string = ('--question', '--target', '--to', '--project', '--in', '--db', '--server-db',
    '--sql-db', '--counterpart-db', '--control', '--mode', '--depth', '--cap', '--surface-cap', '--max-rows', '--out-root',
    '--pairs-file', '--allow-stale', '--plain', '--open', '--resolve-only', '--help', '-h');
  INT_FLAGS = [afDepth, afCap, afSurfaceCap, afMaxRows];
  SWITCH_FLAGS = [afAllowStale, afPlain, afOpen, afResolveOnly, afHelp, afHelpShort];

function FindFlag(const pText: string; out pFlag: TAskFlag): Boolean;
begin
  for var F:= Low(TAskFlag) to High(TAskFlag) do
    if FLAG_NAMES[F] = pText then
    begin
      pFlag:= F;
      Exit(True);
    end;
  pFlag:= afHelp;
  Result:= False;
end;

procedure ApplySwitch(var pArgs: TAskVerbArgs; pFlag: TAskFlag);
begin
  case pFlag of
    afAllowStale : pArgs.AllowStale:= True;
    afPlain      : pArgs.Plain:= True;
    afOpen       : pArgs.Open:= True;
    afResolveOnly: pArgs.ResolveOnly:= True;
  else
    pArgs.Help:= True;
  end;
end;

procedure ApplyValue(var pArgs: TAskVerbArgs; pFlag: TAskFlag; const pValue: string);
begin
  case pFlag of
    afQuestion     : pArgs.Question:= pValue;
    afTarget       : pArgs.Target:= pValue;
    afTo           : pArgs.ToRoutine:= pValue;
    afProject      : pArgs.Project:= pValue;
    afIn           : pArgs.InFile:= pValue;
    afDb           : pArgs.DbPath:= pValue;
    afServerDb     : pArgs.ServerDb:= pValue;
    afSqlDb        : pArgs.SqlDb:= pValue;
    afCounterpartDb: pArgs.CounterpartDb:= pValue;
    afControl      : pArgs.Control:= pValue;
    afMode         : pArgs.Mode:= pValue;
    afDepth        : pArgs.Depth:= pValue;
    afCap          : pArgs.Cap:= pValue;
    afSurfaceCap   : pArgs.SurfaceCap:= pValue;
    afMaxRows      : pArgs.MaxRows:= pValue;
    afOutRoot      : pArgs.OutRoot:= pValue;
  else
    pArgs.PairsFile:= pValue;
  end;
end;

function ParseAskArgs(const pArgv: TArray<string>; out pArgs: TAskVerbArgs; out pError: string): Boolean;
var
  F: TAskFlag;
  N: Integer;
begin
  pArgs:= Default(TAskVerbArgs);
  pError:= '';
  var I:= 0;
  while I <= High(pArgv) do
  begin
    var A:= pArgv[I];
    if FindFlag(A, F) and (F in SWITCH_FLAGS) then
      ApplySwitch(pArgs, F)
    else if FindFlag(A, F) then
    begin
      if I = High(pArgv) then pError:= A + ' needs a value'
      else if (F in INT_FLAGS) and not TryStrToInt(pArgv[I + 1], N) then pError:= A + ' needs an integer, got "' + pArgv[I + 1] + '"'
      else ApplyValue(pArgs, F, pArgv[I + 1]);
      Inc(I);
    end
    else if A.StartsWith('-') then pError:= 'unknown argument: ' + A
    else if pArgs.Question = '' then pArgs.Question:= A
    else pError:= 'unexpected argument: ' + A + ' (the question is already ' + pArgs.Question + ')';
    if pError <> '' then Exit(False);
    Inc(I);
  end;
  Result:= True;
end;

function NormaliseAskQuestion(const pTyped: string; out pId: string): Boolean;
begin
  pId:= '';
  for var Id in QuestionIds do
    if SameText(Id, pTyped) then
    begin
      pId:= Id.ToLower;
      Exit(True);
    end;
  Result:= False;
end;

procedure AddArg(var pCmd: TReportCommand; const pName, pValue: string);
var
  A: TCommandArg;
begin
  if pValue = '' then Exit;
  A.Name:= pName;
  A.Value:= pValue;
  pCmd.Args:= pCmd.Args + [A];
end;

function AskCommandOf(const pArgs: TAskVerbArgs): TReportCommand;
begin
  Result:= Default(TReportCommand);
  Result.Question:= pArgs.Question;
  AddArg(Result, 'Target', pArgs.Target);
  AddArg(Result, 'To', pArgs.ToRoutine);
  if pArgs.Project <> '' then AddArg(Result, 'Project', ExpandFileName(pArgs.Project))
  else if pArgs.InFile <> '' then AddArg(Result, 'In', ExpandFileName(pArgs.InFile));
  AddArg(Result, 'Depth', pArgs.Depth);
  AddArg(Result, 'Cap', pArgs.Cap);
  AddArg(Result, 'SurfaceCap', pArgs.SurfaceCap);
  AddArg(Result, 'Control', pArgs.Control);
  AddArg(Result, 'Mode', pArgs.Mode);
  AddArg(Result, 'MaxRows', pArgs.MaxRows);
end;

function AnswerLines(const pText: string): TArray<string>;
begin
  Result:= SplitAnswerLines(pText);
  if (Length(Result) > 0) and (Result[High(Result)] = '') then SetLength(Result, Length(Result) - 1);
end;

function FormatAskAnswer(const pQuestion, pShownTarget, pPlainText: string; pPlain: Boolean;
  pAskedOn: TDateTime): TArray<string>;
begin
  if pPlain then Exit(AnswerLines(pPlainText));
  Result:= AnswerLines(FormatAnswerAsDocInsight(QuestionPhrase(pQuestion), pQuestion, pShownTarget, pAskedOn, pPlainText));
end;

{ ---- the engine as a child process (resolve-dbs), as Ask-Report asks it ---- }

{ The JSON document of an engine answer: the first LINE from which the rest parses (a note line
  such as '[note] ...' also starts with '['). nil when there is none; the caller frees it. }
function EngineJson(const pText: string): TJSONValue;
begin
  var Lines:= SplitAnswerLines(pText);
  for var I:= 0 to High(Lines) do
  begin
    var T:= Lines[I].TrimLeft;
    if not (T.StartsWith('{') or T.StartsWith('[')) then Continue;
    var Rest:= string.Join(#10, Lines, I, Length(Lines) - I);
    Result:= TJSONObject.ParseJSONValue(Rest);
    if Result <> nil then Exit;
  end;
  Result:= nil;
end;

{ Runs `<engine> <args>` and returns its JSON document (nil on a non-zero exit or no JSON). }
function AskEngine(const pEngine: string; const pArgs: array of string; out pExit: Integer): TJSONValue;
var
  Run: TProcessResult;
begin
  Result:= nil;
  pExit:= -1;
  var Line:= QuoteArg(pEngine);
  for var A in pArgs do Line:= Line + ' ' + QuoteArg(A);
  if not RunCapture(Line, '', ENGINE_TIMEOUT_MS, Run) then Exit;
  pExit:= Run.ExitCode;
  if Run.TimedOut or (Run.ExitCode <> 0) then Exit;
  Result:= EngineJson(Run.StdOut);
end;

function JsonStrings(const pValue: TJSONValue): TArray<string>;
begin
  Result:= nil;
  if not (pValue is TJSONArray) then Exit;
  for var V in TJSONArray(pValue) do
    if (V is TJSONString) and (V.Value <> '') then Result:= Result + [V.Value];
end;

function SamePath(const pA, pB: string): Boolean;
begin
  Result:= (pA <> '') and (pB <> '') and SameText(ExpandFileName(pA), ExpandFileName(pB));
end;

{ ---- the pairing file ---- }

function ResolveReportPairsFile: string;
begin
  var AppData:= GetEnvironmentVariable('APPDATA');
  var User:= if AppData <> '' then TPath.Combine(AppData, USER_PAIRS_REL) else '';
  var Why: string;
  var Script:= ResolveAskReportScript('', Why);
  var Repo:= if Script <> '' then TPath.Combine(ExtractFileDir(ExtractFileDir(Script)), PAIRS_FILE_NAME) else '';
  if (User <> '') and TFile.Exists(User) then Exit(User);
  if (Repo <> '') and (TFile.Exists(Repo) or (User = '')) then Exit(Repo);
  Result:= User;
end;

function LoadPairs(const pFile: string): TArray<TReportPair>;
begin
  Result:= nil;
  var Doc:= TJSONObject.ParseJSONValue(TFile.ReadAllText(pFile));
  if Doc = nil then
    raise EAskStop.CreateCode(ASK_VERB_EXIT_REFUSED, pFile + ' is not valid JSON');
  try
    var Arr: TJSONArray;
    if not ((Doc is TJSONObject) and TJSONObject(Doc).TryGetValue<TJSONArray>('pairs', Arr)) then Exit;
    for var V in Arr do
    begin
      if not (V is TJSONObject) then Continue;
      var O:= TJSONObject(V);
      var P:= Default(TReportPair);
      P.Name:= O.GetValue<string>('name', '');
      P.Client:= O.GetValue<string>('client', '');
      P.Server:= O.GetValue<string>('server', '');
      P.Sql:= O.GetValue<string>('sql', '');
      P.SqlSection:= O.GetValue<string>('sqlSection', '');
      Result:= Result + [P];
    end;
  finally
    Doc.Free;
  end;
end;

function FindPair(const pPairs: TArray<TReportPair>; const pDb: string; out pPair: TReportPair): Boolean;
begin
  for var P in pPairs do
    if SamePath(P.Client, pDb) or SamePath(P.Server, pDb) then
    begin
      pPair:= P;
      Exit(True);
    end;
  pPair:= Default(TReportPair);
  Result:= False;
end;

{ ---- the run ---- }

type
  { One run's state: what Ask-Report keeps in script variables. }
  TAskRun = record
    Args      : TAskVerbArgs;
    Engine    : string;
    PairsFile : string;
    Pairs     : TArray<TReportPair>;
    PairsFound: Boolean;
    NeedServer: Boolean;
    NeedSql   : Boolean;
    WantOther : Boolean;
    procedure Stop(pCode: Integer; const pMessage: string);
    procedure ResolveProject;
    procedure ResolveOthers;
    function ReindexCommand(const pDb: string): string;
    procedure CheckFreshness(const pErr: TAskWriter);
  end;

procedure TAskRun.Stop(pCode: Integer; const pMessage: string);
begin
  raise EAskStop.CreateCode(pCode, pMessage);
end;

procedure TAskRun.ResolveProject;
var
  Code: Integer;
  P   : TReportPair;
begin
  if Args.DbPath <> '' then Exit;
  if Args.Project <> '' then
  begin
    if not TFile.Exists(Args.Project) then Stop(ASK_VERB_EXIT_SETUP, 'project file not found: ' + Args.Project);
    var Pj:= ExpandFileName(Args.Project);
    var J:= AskEngine(Engine, ['resolve-dbs', '--project', Pj, '--json'], Code);
    try
      var Db:= '';
      if J is TJSONObject then Db:= TJSONObject(J).GetValue<string>('db', '');
      if Db = '' then
        Stop(ASK_VERB_EXIT_SETUP, Format('resolve-dbs --project %s found no index (exit %d) -- the project is not in the engine''s index manifest', [Pj, Code]));
      Args.DbPath:= Db;
    finally
      J.Free;
    end;
  end
  else if Args.InFile <> '' then
  begin
    if not TFile.Exists(Args.InFile) then Stop(ASK_VERB_EXIT_SETUP, 'file not found: ' + Args.InFile);
    var InFull:= ExpandFileName(Args.InFile);
    var J:= AskEngine(Engine, ['resolve-dbs', '--in', InFull, '--json'], Code);
    var Cands: TArray<string>;
    try
      Cands:= JsonStrings(J);
    finally
      J.Free;
    end;
    if Length(Cands) = 0 then
      Stop(ASK_VERB_EXIT_SETUP, Format('no index covers %s (resolve-dbs --in, exit %d) -- pass --project <x.dproj>', [InFull, Code]));
    if Length(Cands) = 1 then Args.DbPath:= Cands[0]
    else
    begin
      { several projects hold this unit: the one report-pairs.json names is the declared choice }
      var Paired: TArray<string>:= nil;
      for var C in Cands do
        if FindPair(Pairs, C, P) then Paired:= Paired + [C];
      if Length(Paired) <> 1 then
        Stop(ASK_VERB_EXIT_SETUP, Format('%d indexes cover %s: %s -- pass --project <x.dproj> to pick one',
          [Length(Cands), InFull, string.Join(', ', Cands)]));
      Args.DbPath:= Paired[0];
    end;
  end
  else
    Stop(ASK_VERB_EXIT_SETUP, 'name the project: --project <x.dproj> or --in <any .pas/.dfm of it>. The target alone does not ' +
      'name a file -- a form instance, class or field maps to a unit only through an index, and ' +
      'choosing that index is the step being asked for.');
end;

procedure TAskRun.ResolveOthers;
var
  Pair: TReportPair;
  Code: Integer;
begin
  var FromPairs: TArray<string>:= nil;
  var MissServer:= NeedServer and (Args.ServerDb = '');
  var MissSql:= NeedSql and (Args.SqlDb = '');
  var MissOther:= WantOther and (Args.CounterpartDb = '');
  if MissServer or MissSql or MissOther then
  begin
    if not FindPair(Pairs, Args.DbPath, Pair) then
    begin
      if NeedServer or NeedSql then
      begin
        var Reads:= if NeedServer then 'the SERVER index and ' else '';
        var OrPass:= 'or pass ' + (if NeedServer then '--server-db and ' else '') + '--sql-db';
        if not PairsFound then
          Stop(ASK_VERB_EXIT_SETUP, Format('%s also reads %sthe SQL-script index, and %s not found at %s, so no pairs are configured -- copy ' +
            'charts\report-pairs.example.json to that path and fill in client, server and sql (each checked with resolve-dbs), %s',
            [Args.Question, Reads, ExtractFileName(PairsFile), PairsFile, OrPass]));
        Stop(ASK_VERB_EXIT_SETUP, Format('%s also reads %sthe SQL-script index, and %s has no entry for %s -- add one (client, server, sql; ' +
          'check each with resolve-dbs), %s', [Args.Question, Reads, PairsFile, Args.DbPath, OrPass]));
      end;
      { crosses-boundary without a counterpart draws one side and says so (the bundler's own behaviour) }
    end
    else
    begin
      if NeedServer and (Args.ServerDb = '') then
      begin
        if not SamePath(Pair.Client, Args.DbPath) then
          Stop(ASK_VERB_EXIT_SETUP, Format('%s starts from the CLIENT index; %s is the SERVER of pair ''%s'' in %s -- pass the client project',
            [Args.Question, Args.DbPath, Pair.Name, PairsFile]));
        Args.ServerDb:= Pair.Server;
        FromPairs:= FromPairs + [Args.ServerDb];
      end;
      if NeedSql and (Args.SqlDb = '') then
      begin
        Args.SqlDb:= Pair.Sql;
        FromPairs:= FromPairs + [Args.SqlDb];
      end;
      if WantOther and (Args.CounterpartDb = '') then
      begin
        Args.CounterpartDb:= if SamePath(Pair.Client, Args.DbPath) then Pair.Server else Pair.Client;
        FromPairs:= FromPairs + [Args.CounterpartDb];
      end;
    end;
  end;
  { a pairing-file path must still be one the manifest configures }
  if Length(FromPairs) = 0 then Exit;
  var J:= AskEngine(Engine, ['resolve-dbs', '--json'], Code);
  var Known: TArray<string>;
  try
    Known:= JsonStrings(J);
  finally
    J.Free;
  end;
  for var F in FromPairs do
  begin
    var Found:= False;
    for var K in Known do
      if SamePath(K, F) then Found:= True;
    if not Found then
      Stop(ASK_VERB_EXIT_SETUP, Format('%s names %s, which the engine''s manifest no longer configures (resolve-dbs) -- fix the pair', [PairsFile, F]));
  end;
end;

function TAskRun.ReindexCommand(const pDb: string): string;
var
  Code: Integer;
begin
  for var P in Pairs do
    if SamePath(P.Sql, pDb) and (P.SqlSection <> '') then
      Exit(Format('& ''%s'' index --all --only %s', [Engine, P.SqlSection]));
  Result:= '';
  var Dir:= ExtractFileDir(pDb);
  if not SameText(ExtractFileName(Dir), DRAG_DIR) then Exit;
  var ProjDir:= ExtractFileDir(Dir);
  var Base:= ChangeFileExt(ExtractFileName(pDb), '');
  for var Ext in TArray<string>.Create('.dproj', '.dpr') do
  begin
    var Pf:= TPath.Combine(ProjDir, Base + Ext);
    if not TFile.Exists(Pf) then Continue;
    var J:= AskEngine(Engine, ['resolve-dbs', '--project', Pf, '--json'], Code);
    try
      if (J is TJSONObject) and SamePath(TJSONObject(J).GetValue<string>('db', ''), pDb) then
        Exit(Format('& ''%s'' index --project ''%s'' --db ''%s''', [Engine, Pf, pDb]));
    finally
      J.Free;
    end;
  end;
end;

{ The engine's own freshness sweep; the store is closed before the producer opens the index. }
function ProbeDb(const pDb: string): TFreshnessReport;
begin
  var Store: ISymbolStore:= TSQLiteSymbolStore.Create(pDb, True);
  Result:= ProbeIndexFreshness(Store);
end;

{ Ask-Report's step 3: every index this question reads, through the engine's own sweep. }
procedure TAskRun.CheckFreshness(const pErr: TAskWriter);
var
  Rep: TFreshnessReport;
begin
  var Dbs: TArray<string>:= [Args.DbPath];
  for var D in TArray<string>.Create(if NeedServer then Args.ServerDb else '', if NeedSql then Args.SqlDb else '',
                                     if WantOther then Args.CounterpartDb else '') do
  begin
    if D = '' then Continue;
    var Seen:= False;
    for var S in Dbs do
      if SameText(S, D) then Seen:= True;
    if not Seen then Dbs:= Dbs + [D];
  end;
  var Lines: TArray<string>:= nil;
  var Allowed: TArray<string>:= nil;
  for var Db in Dbs do
  begin
    if not TFile.Exists(Db) then Stop(ASK_VERB_EXIT_SETUP, 'index not found: ' + Db);
    try
      Rep:= ProbeDb(Db);
    except
      on E: Exception do
        Stop(ASK_VERB_EXIT_REFUSED, Format('the engine could not open %s (%s: %s)', [Db, E.ClassName, E.Message]));
    end;
    if Rep.Verdict = fvUnknown then
      pErr(ASK_VERB_ERR_PREFIX + 'note -- the engine reports no freshness for ' + Db + '; answering unchecked')
    else if Rep.Verdict = fvStale then
    begin
      var Cmd:= ReindexCommand(Db);
      Lines:= Lines + [Format('  %s: %d file(s) changed since it was indexed', [Db, Rep.Changed]),
        if Cmd <> '' then '    ' + Cmd
        else '    no reindex command can be derived for it (not a <project>\_D-RAG\<name>.sqlite the manifest resolves; ' +
          'a clone under charts\scratch\db is re-taken, not reindexed)'];
      Allowed:= Allowed + [Format('%s: %d file(s)', [Db, Rep.Changed])];
    end;
  end;
  if Length(Lines) = 0 then Exit;
  if Args.AllowStale then
    pErr(ASK_VERB_ERR_PREFIX + 'note -- stale index allowed by --allow-stale: ' + string.Join('; ', Allowed))
  else
    Stop(ASK_VERB_EXIT_STALE, 'stale index -- the answer would be short or wrong. Reindex incrementally, then ask again:' +
      CRLF + string.Join(CRLF, Lines));
end;

procedure WriteText(const pWriter: TAskWriter; const pText: string);
begin
  for var L in AnswerLines(pText) do pWriter(L);
end;

{ The producer of real use: ported questions in-process on the live index, the rest through Ask-Report.ps1. }
function DefaultAskProducer(const pOutRoot: string): IReportProducer;
begin
  Result:= TDelphiProducer.Create(TPowerShellProducer.Create, True, pOutRoot);
end;

function RunAskCore(const pArgs: TAskVerbArgs; const pProducer: IReportProducer;
  const pOut, pErr: TAskWriter): Integer;
var
  Id: string;
  R : TAskRun;
begin
  if pArgs.Help then
  begin
    for var L in AskUsage do pOut(L);
    Exit(ASK_VERB_EXIT_ANSWERED);
  end;
  if pArgs.Question = '' then
    raise EAskStop.CreateCode(ASK_VERB_EXIT_SETUP, 'name the question: drag-lint ask <question> --target <T> ...' + CRLF +
      string.Join(CRLF, AskUsage));
  if not NormaliseAskQuestion(pArgs.Question, Id) then
    raise EAskStop.CreateCode(ASK_VERB_EXIT_SETUP, Format('unknown question ''%s'' -- one of: %s', [pArgs.Question, string.Join(', ', QuestionIds)]));
  if Trim(pArgs.Target) = '' then
    raise EAskStop.CreateCode(ASK_VERB_EXIT_SETUP, 'name the target: --target <T>');

  R:= Default(TAskRun);
  R.Args:= pArgs;
  R.Args.Question:= Id;
  R.Engine:= if pArgs.Engine <> '' then pArgs.Engine else ParamStr(0);
  R.NeedServer:= MatchStr(Id, [Q_ROUND_TRIP, Q_LANDS_WHERE]);
  R.NeedSql:= MatchStr(Id, [Q_ROUND_TRIP, Q_LANDS_WHERE, Q_CONSUMERS, Q_FEEDS_FROM]);
  R.WantOther:= Id = Q_CROSSES;
  R.PairsFile:= if pArgs.PairsFile <> '' then pArgs.PairsFile else ResolveReportPairsFile;
  R.PairsFound:= (R.PairsFile <> '') and TFile.Exists(R.PairsFile);
  if R.PairsFound then R.Pairs:= LoadPairs(R.PairsFile);

  R.ResolveProject;
  R.ResolveOthers;
  { full paths from here on: messages name the index exactly as the engine and the bundle will }
  R.Args.DbPath:= ExpandFileName(R.Args.DbPath);
  if R.Args.ServerDb <> '' then R.Args.ServerDb:= ExpandFileName(R.Args.ServerDb);
  if R.Args.SqlDb <> '' then R.Args.SqlDb:= ExpandFileName(R.Args.SqlDb);
  if R.Args.CounterpartDb <> '' then R.Args.CounterpartDb:= ExpandFileName(R.Args.CounterpartDb);
  if pArgs.ResolveOnly then
  begin
    pOut('PROJECT ' + R.Args.DbPath);
    if R.NeedServer then pOut('SERVER ' + R.Args.ServerDb);
    if R.NeedSql then pOut('SQL ' + R.Args.SqlDb);
    if R.WantOther and (R.Args.CounterpartDb <> '') then pOut('COUNTERPART ' + R.Args.CounterpartDb);
    Exit(ASK_VERB_EXIT_ANSWERED);
  end;
  R.CheckFreshness(pErr);

  var Opts:= DefaultProduceOptions;
  Opts.EnginePath:= R.Engine;
  Opts.DbOverride:= R.Args.DbPath;
  Opts.AllowStale:= True;   { checked above, for every index the question reads }
  if R.NeedServer then Opts.ServerDbOverride:= R.Args.ServerDb;
  if R.NeedSql then Opts.SqlDbOverride:= R.Args.SqlDb;
  if R.WantOther then Opts.CounterpartDbOverride:= R.Args.CounterpartDb;
  Opts.OutRoot:= pArgs.OutRoot;
  Opts.PairsFile:= pArgs.PairsFile;
  var Producer:= if pProducer <> nil then pProducer else DefaultAskProducer(pArgs.OutRoot);
  var Prod:= Producer.Produce(AskCommandOf(R.Args), Opts);
  if not Prod.Ok then
    raise EAskStop.CreateCode(if Prod.ExitCode = ASK_VERB_EXIT_ANSWERED then ASK_VERB_EXIT_REFUSED else Prod.ExitCode, Prod.Reason);
  if pArgs.Open and (Prod.BundlePath <> '') and TFile.Exists(TPath.Combine(Prod.BundlePath, SHELL_HTML)) then
    OpenInBrowser(TPath.Combine(Prod.BundlePath, SHELL_HTML));
  var Shown:= if (Id = Q_PATH) and (pArgs.ToRoutine <> '') then pArgs.Target + ' -> ' + pArgs.ToRoutine else pArgs.Target;
  for var L in FormatAskAnswer(Id, Shown, Prod.Text, pArgs.Plain, Now) do pOut(L);
  Result:= ASK_VERB_EXIT_ANSWERED;
end;

function RunAsk(const pArgs: TAskVerbArgs; const pProducer: IReportProducer;
  const pOut, pErr: TAskWriter): Integer;
begin
  try
    Result:= RunAskCore(pArgs, pProducer, pOut, pErr);
  except
    on E: EAskStop do
    begin
      WriteText(pErr, ASK_VERB_ERR_PREFIX + E.Message);
      Result:= E.Code;
    end;
    on E: Exception do
    begin
      WriteText(pErr, ASK_VERB_ERR_PREFIX + E.ClassName + ': ' + E.Message);
      Result:= ASK_VERB_EXIT_REFUSED;
    end;
  end;
end;

function RunAskVerbFromCommandLine: Integer;
var
  Args : TAskVerbArgs;
  Error: string;
begin
  var Argv: TArray<string>:= nil;
  for var I:= 2 to ParamCount do Argv:= Argv + [ParamStr(I)];
  if not ParseAskArgs(Argv, Args, Error) then
  begin
    Writeln(ErrOutput, ASK_VERB_ERR_PREFIX + Error);
    for var L in AskUsage do Writeln(ErrOutput, L);
    Exit(ASK_VERB_EXIT_SETUP);
  end;
  Result:= RunAsk(Args, nil,
    procedure(const pLine: string)
    begin
      Writeln(pLine);
    end,
    procedure(const pLine: string)
    begin
      Writeln(ErrOutput, pLine);
    end);
end;

end.
