unit DRagLint.Charts.Pairs;

(* report-pairs.json: which SERVER and SQL-script index belong with a CLIENT project index, and
  the engine asked as a child process (resolve-dbs) to check what the pairing file names.

  ONE implementation of Ask-Report.ps1's step 2 ("the other indexes, from the pairing file"),
  shared by the two engine paths that must answer exactly as Ask-Report does: `drag-lint ask`
  (DRagLint.Charts.AskVerb) and the in-process producer `drag-lint compare` uses
  (DRagLint.Charts.Producer.Delphi). Every refusal is an EReportPairStop carrying Ask-Report's
  exit code and message. *)

interface

uses
  System.SysUtils, System.JSON;

type
  /// <summary>One entry of report-pairs.json.</summary>
  /// <remarks>A value record; every path is as written in the file.</remarks>
  TReportPair = record
    /// <summary>The pair's name, for messages.</summary>
    Name      : string;
    /// <summary>The CLIENT project index.</summary>
    Client    : string;
    /// <summary>The SERVER project index.</summary>
    Server    : string;
    /// <summary>The SQL-script index.</summary>
    Sql       : string;
    /// <summary>The manifest section that indexes Sql ('' = none named).</summary>
    SqlSection: string;
  end;

  /// <summary>A loaded pairing file.</summary>
  /// <remarks>A value record. Found False means FileName does not exist and Pairs is empty.</remarks>
  TReportPairs = record
    /// <summary>The report-pairs.json looked at (named in every message).</summary>
    FileName: string;
    /// <summary>True when FileName exists.</summary>
    Found   : Boolean;
    /// <summary>Its entries, in file order.</summary>
    Pairs   : TArray<TReportPair>;
  end;

  /// <summary>A refusal of Ask-Report's: the exit code travels with the message (Stop-Ask).</summary>
  EReportPairStop = class(Exception)
  private
    FCode: Integer;
  public
    /// <summary>Creates the refusal.</summary>
    /// <param name="pCode">Ask-Report's exit code: 1 refused, 2 setup, 3 stale.</param>
    /// <param name="pMessage">The message, without the 'ask-report: ' prefix.</param>
    constructor CreateCode(pCode: Integer; const pMessage: string);
    /// <summary>Ask-Report's exit code.</summary>
    property Code: Integer read FCode;
  end;

/// <summary>Whether two index paths name the same file, as Windows compares them.</summary>
/// <param name="pA">A path, relative or full.</param>
/// <param name="pB">A path, relative or full.</param>
/// <returns>False when either is ''. Pure.</returns>
function SameIndexPath(const pA, pB: string): Boolean;

/// <summary>The default report-pairs.json (Emit-Common's Resolve-ReportPairsFile).</summary>
/// <param name="pScriptPath">The Ask-Report.ps1 to locate the charts folder from; '' resolves it
/// (ResolveAskReportScript).</param>
/// <returns>%APPDATA%\drag-lint\report-pairs.json when it exists, else charts\report-pairs.json
/// when that exists (or APPDATA is unset), else the APPDATA path.</returns>
function ResolveReportPairsFile(const pScriptPath: string = ''): string;

/// <summary>Loads a pairing file.</summary>
/// <param name="pFile">The report-pairs.json; '' = ResolveReportPairsFile(pScriptPath).</param>
/// <param name="pScriptPath">Passed to ResolveReportPairsFile when pFile is ''.</param>
/// <returns>The file name looked at, whether it exists, and its 'pairs' entries.</returns>
/// <exception cref="EReportPairStop">Code 1 when the file exists and is not valid JSON.</exception>
function LoadReportPairs(const pFile: string; const pScriptPath: string = ''): TReportPairs;

/// <summary>The first pair that names an index as its client or its server.</summary>
/// <param name="pPairs">The entries.</param>
/// <param name="pDb">The index.</param>
/// <param name="pPair">The pair found; Default(TReportPair) when none.</param>
/// <returns>True when one names it. Pure.</returns>
function FindReportPair(const pPairs: TArray<TReportPair>; const pDb: string; out pPair: TReportPair): Boolean;

/// <summary>Runs the engine as a child process and returns its JSON document.</summary>
/// <param name="pEngine">The engine executable.</param>
/// <param name="pArgs">Its arguments, each quoted as needed.</param>
/// <param name="pExit">Its exit code; -1 when it could not be started.</param>
/// <returns>nil on a non-zero exit, a timeout or no JSON; otherwise a document the caller frees.</returns>
function AskEngine(const pEngine: string; const pArgs: array of string; out pExit: Integer): TJSONValue;

/// <summary>The non-empty strings of a JSON array.</summary>
/// <param name="pValue">Any JSON value, or nil.</param>
/// <returns>Empty for anything but an array. Pure.</returns>
function JsonStrings(const pValue: TJSONValue): TArray<string>;

type
  /// <summary>What one question needs paired, and how its caller names its own flags.</summary>
  /// <remarks>A value record.</remarks>
  TPairRequest = record
    /// <summary>The normalised question id (named in messages).</summary>
    Question  : string;
    /// <summary>The project index as given (named in messages).</summary>
    Db        : string;
    /// <summary>The engine asked `resolve-dbs --json` to check a path taken from the file.</summary>
    Engine    : string;
    /// <summary>The question reads the SERVER index (round-trip, lands-where).</summary>
    NeedServer: Boolean;
    /// <summary>The question reads the SQL-script index.</summary>
    NeedSql   : Boolean;
    /// <summary>The question draws a counterpart (crosses-boundary).</summary>
    WantOther : Boolean;
    /// <summary>The caller's server override flag, named in a refusal: '-ServerDbPath' (Ask-Report)
    /// or '--server-db' (the ask verb).</summary>
    ServerFlag: string;
    /// <summary>The caller's SQL override flag, named in a refusal: '-SqlDbPath' (Ask-Report) or
    /// '--sql-db' (the ask verb).</summary>
    SqlFlag   : string;
  end;

  /// <summary>The other indexes of one question: as given, then as paired.</summary>
  /// <remarks>A value record; '' = not given.</remarks>
  TPairedIndexes = record
    /// <summary>The SERVER index.</summary>
    Server: string;
    /// <summary>The SQL-script index.</summary>
    Sql   : string;
    /// <summary>The crosses-boundary counterpart.</summary>
    Other : string;
  end;

/// <summary>Ask-Report's step 2: fills the SERVER / SQL / counterpart index a question reads from
/// the pairing file, when it was not given.</summary>
/// <param name="pPairs">The loaded pairing file.</param>
/// <param name="pRequest">The question, its project index, the engine and the caller's flag names.</param>
/// <param name="pIndexes">The indexes given; on return each empty one the question needs is filled
/// from the pair that names pRequest.Db (Server and Sql from the pair, Other from its far side).</param>
/// <exception cref="EReportPairStop">Code 2 -- a server or SQL index is needed and no pair names
/// the project index (the file is missing, or has no entry); a server is needed and the project
/// index is the pair's SERVER; or a path taken from the file is not one resolve-dbs lists.</exception>
/// <remarks>A crosses-boundary question with no pair keeps Other '' and does not refuse (the
/// bundler draws one side and says so). Asks the engine only when a path came from the file.</remarks>
procedure PairOtherIndexes(const pPairs: TReportPairs; const pRequest: TPairRequest; var pIndexes: TPairedIndexes);

implementation

uses
  System.IOUtils, DRagLint.Charts.Process, DRagLint.Charts.DocInsight, DRagLint.Charts.Producer.PowerShell;

const
  PAIRS_FILE_NAME = 'report-pairs.json';
  USER_PAIRS_REL = 'drag-lint\' + PAIRS_FILE_NAME;
  ENGINE_TIMEOUT_MS = 120000;
  EXIT_REFUSED = 1;
  EXIT_SETUP = 2;

constructor EReportPairStop.CreateCode(pCode: Integer; const pMessage: string);
begin
  inherited Create(pMessage);
  FCode:= pCode;
end;

function SameIndexPath(const pA, pB: string): Boolean;
begin
  Result:= (pA <> '') and (pB <> '') and SameText(ExpandFileName(pA), ExpandFileName(pB));
end;

function ResolveReportPairsFile(const pScriptPath: string): string;
begin
  var AppData:= GetEnvironmentVariable('APPDATA');
  var User:= if AppData <> '' then TPath.Combine(AppData, USER_PAIRS_REL) else '';
  var Why: string;
  var Script:= ResolveAskReportScript(pScriptPath, Why);
  var Repo:= if Script <> '' then TPath.Combine(ExtractFileDir(ExtractFileDir(Script)), PAIRS_FILE_NAME) else '';
  if (User <> '') and TFile.Exists(User) then Exit(User);
  if (Repo <> '') and (TFile.Exists(Repo) or (User = '')) then Exit(Repo);
  Result:= User;
end;

function LoadReportPairs(const pFile: string; const pScriptPath: string): TReportPairs;
begin
  Result:= Default(TReportPairs);
  Result.FileName:= if pFile <> '' then pFile else ResolveReportPairsFile(pScriptPath);
  Result.Found:= (Result.FileName <> '') and TFile.Exists(Result.FileName);
  if not Result.Found then Exit;
  var Doc:= TJSONObject.ParseJSONValue(TFile.ReadAllText(Result.FileName));
  if Doc = nil then
    raise EReportPairStop.CreateCode(EXIT_REFUSED, Result.FileName + ' is not valid JSON');
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
      Result.Pairs:= Result.Pairs + [P];
    end;
  finally
    Doc.Free;
  end;
end;

function FindReportPair(const pPairs: TArray<TReportPair>; const pDb: string; out pPair: TReportPair): Boolean;
begin
  for var P in pPairs do
    if SameIndexPath(P.Client, pDb) or SameIndexPath(P.Server, pDb) then
    begin
      pPair:= P;
      Exit(True);
    end;
  pPair:= Default(TReportPair);
  Result:= False;
end;

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

{ No pair names the project index and a server or SQL index is needed: Ask-Report's two refusals. }
procedure RefuseUnpaired(const pPairs: TReportPairs; const pRequest: TPairRequest);
begin
  var Reads:= if pRequest.NeedServer then 'the SERVER index and ' else '';
  var OrPass:= 'or pass ' + (if pRequest.NeedServer then pRequest.ServerFlag + ' and ' else '') + pRequest.SqlFlag;
  if not pPairs.Found then
    raise EReportPairStop.CreateCode(EXIT_SETUP, Format('%s also reads %sthe SQL-script index, and %s not found at %s, so no pairs are configured -- copy ' +
      'charts\report-pairs.example.json to that path and fill in client, server and sql (each checked with resolve-dbs), %s',
      [pRequest.Question, Reads, ExtractFileName(pPairs.FileName), pPairs.FileName, OrPass]));
  raise EReportPairStop.CreateCode(EXIT_SETUP, Format('%s also reads %sthe SQL-script index, and %s has no entry for %s -- add one (client, server, sql; ' +
    'check each with resolve-dbs), %s', [pRequest.Question, Reads, pPairs.FileName, pRequest.Db, OrPass]));
end;

{ A pairing-file path must still be one the manifest configures. }
procedure CheckConfigured(const pPairs: TReportPairs; const pEngine: string; const pFromPairs: TArray<string>);
var
  Code: Integer;
begin
  var J:= AskEngine(pEngine, ['resolve-dbs', '--json'], Code);
  var Known: TArray<string>;
  try
    Known:= JsonStrings(J);
  finally
    J.Free;
  end;
  for var F in pFromPairs do
  begin
    var Found:= False;
    for var K in Known do
      if SameIndexPath(K, F) then Found:= True;
    if not Found then
      raise EReportPairStop.CreateCode(EXIT_SETUP, Format('%s names %s, which the engine''s manifest no longer configures (resolve-dbs) -- fix the pair',
        [pPairs.FileName, F]));
  end;
end;

procedure PairOtherIndexes(const pPairs: TReportPairs; const pRequest: TPairRequest; var pIndexes: TPairedIndexes);
var
  Pair: TReportPair;
begin
  var MissServer:= pRequest.NeedServer and (pIndexes.Server = '');
  var MissSql:= pRequest.NeedSql and (pIndexes.Sql = '');
  var MissOther:= pRequest.WantOther and (pIndexes.Other = '');
  if not (MissServer or MissSql or MissOther) then Exit;
  if not FindReportPair(pPairs.Pairs, pRequest.Db, Pair) then
  begin
    if pRequest.NeedServer or pRequest.NeedSql then
      RefuseUnpaired(pPairs, pRequest);
    { crosses-boundary without a counterpart draws one side and says so (the bundler's own behaviour) }
    Exit;
  end;
  var FromPairs: TArray<string>:= nil;
  if MissServer then
  begin
    if not SameIndexPath(Pair.Client, pRequest.Db) then
      raise EReportPairStop.CreateCode(EXIT_SETUP, Format('%s starts from the CLIENT index; %s is the SERVER of pair ''%s'' in %s -- pass the client project',
        [pRequest.Question, pRequest.Db, Pair.Name, pPairs.FileName]));
    pIndexes.Server:= Pair.Server;
    FromPairs:= FromPairs + [Pair.Server];
  end;
  if MissSql then
  begin
    pIndexes.Sql:= Pair.Sql;
    FromPairs:= FromPairs + [Pair.Sql];
  end;
  if MissOther then
  begin
    pIndexes.Other:= if SameIndexPath(Pair.Client, pRequest.Db) then Pair.Server else Pair.Client;
    FromPairs:= FromPairs + [pIndexes.Other];
  end;
  CheckConfigured(pPairs, pRequest.Engine, FromPairs);
end;

end.
