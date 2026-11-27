unit DRagLint.CLI.Coverage;

{ drag-lint 1.56 -- lane G51 (gap G-51): the `import-coverage` verb and the coverage store `ask risk` reads.
  Reads a Delphi code-coverage report and keeps, per file and routine, how many lines ran.
  Formats (detected from the content, no flag):
    emma       DelphiCodeCoverage's XML report: <srcfile name=".."> / <class name=".."> / <method name="..">
               with <coverage type="line, %" value="75% (3/4)"/> (the "(covered/total)" part is the data;
               a "line" figure wins over "block", which wins over "method").
    cobertura  <class filename=".." name=".."> / <method name=".."> with <line number=".." hits=".."/> children
               (one line = one unit; hits > 0 = covered).
  STORAGE (decision, lane G51): a sidecar file <db>.coverage.json beside the index, NOT a table. Every table
  of the index is created by Storage.Schema and a new one is a SCHEMA_VERSION bump (it would re-open every
  library index); the history file of `metrics` (<db>.metrics.jsonl) is the precedent for derived data that
  is not part of the index. The index is opened read-only and never written. A re-import replaces the file.
  Matching a record to an indexed routine: same file base name (case-insensitive) AND the record's
  Class.Method equals the routine's qualified name or one is a dotted suffix of the other. Nothing is
  dropped: records that match no routine and files that match no indexed file are listed, and the indexed
  routines without a record are counted. }

interface

uses
  DRagLint.Query.Metrics;

type
  /// <summary>One routine record of a coverage report.</summary>
  TCoverageRoutine = record
    /// <summary>The source file as the report writes it (base name or path).</summary>
    FileName: string;
    /// <summary>Class.Method, or the unit-qualified routine name.</summary>
    Name: string;
    /// <summary>Lines that ran.</summary>
    Covered: Integer;
    /// <summary>Lines counted; always greater than 0 in a stored record.</summary>
    Total: Integer;
  end;

  /// <summary>A parsed coverage report.</summary>
  TCoverageData = record
    /// <summary>The report file that was imported.</summary>
    Source: string;
    /// <summary>'emma' or 'cobertura'.</summary>
    Format: string;
    Routines: TArray<TCoverageRoutine>;
  end;

  /// <summary>An indexed routine and the coverage record matched to it.</summary>
  TRoutineCoverage = record
    /// <summary>The metrics row of the routine.</summary>
    Row: TMetricRow;
    /// <summary>True when a coverage record matched.</summary>
    HasData: Boolean;
    Covered: Integer;
    Total: Integer;
  end;

  /// <summary>The result of matching a report against an index.</summary>
  TCoverageMatch = record
    /// <summary>Every indexed routine, in the order given, with its record when one matched.</summary>
    Routines: TArray<TRoutineCoverage>;
    /// <summary>Report records that matched no indexed routine, as "file: name".</summary>
    UnmatchedRoutines: TArray<string>;
    /// <summary>Report files that match no indexed file (distinct, as the report writes them).</summary>
    UnmatchedFiles: TArray<string>;
    /// <summary>How many report records matched a routine.</summary>
    MatchedCount: Integer;
  end;

/// <summary>Runs the `import-coverage` verb from the process command line (ParamStr(2) onwards).</summary>
/// <returns>0 = imported (unmatched records are reported, not an error); 1 = the sidecar could not be
/// written; 2 = usage error or refusal (no --file / --db, a missing file, an unreadable index, a report
/// with no routine records); 3 = an unknown flag.</returns>
/// <remarks>Writes only <db>.coverage.json. The summary goes to stdout (text, or one JSON document with --json).</remarks>
function RunCoverageVerb: Integer;

/// <summary>Reads the sidecar of an index.</summary>
/// <param name="pDbPath">The index file.</param>
/// <param name="pData">The stored records on success.</param>
/// <returns>False when there is no sidecar or it is not a coverage/1 document.</returns>
function LoadCoverageSidecar(const pDbPath: string; out pData: TCoverageData): Boolean;

/// <summary>Matches report records to indexed routines.</summary>
/// <param name="pRoutines">The routine rows of the index (LoadMetrics).</param>
/// <param name="pIndexedFiles">The file paths of the index, for the unmatched-file list.</param>
/// <param name="pData">The report.</param>
/// <returns>One entry per routine plus the lists of what did not match; no record is dropped.</returns>
/// <remarks>A record is used at most once; the first routine in order wins an ambiguous name.</remarks>
function MatchCoverage(const pRoutines: TArray<TMetricRow>; const pIndexedFiles: TArray<string>;
  const pData: TCoverageData): TCoverageMatch;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.JSON, System.StrUtils,
  System.RegularExpressions, System.Generics.Collections,
  DRagLint.Core.CliError; // dl:unit DRagLint.Core.CliError accepted -- the verb reports an unknown flag with the shared cli_err_unknown_flag text every verb uses; the other CliError consts are other verbs' errors

const
  CVerb = 'import-coverage';
  CExitOk = 0;
  CExitFailure = 1;
  CExitUsage = 2;
  CExitUnknownFlag = 3;
  CFirstArg = 2; { ParamStr(1) is the verb }
  CSidecarSuffix = '.coverage.json';
  CSchema = 'coverage/1';
  CFormatEmma = 'emma';
  CFormatCobertura = 'cobertura';
  CPrioLine = 3;
  CPrioBlock = 2;
  CPrioOther = 1;
  CPrioNone = 0;
  CUsageLine = 'usage: drag-lint import-coverage --in <report.xml> --db <file.sqlite> [--json]';
  RE_TAG = '<(/?)([A-Za-z_][\w:.\-]*)((?:\s[^>]*?)?)(/?)>';
  RE_ATTR = '([\w:.\-]+)\s*=\s*(?:"([^"]*)"|''([^'']*)'')';
  RE_COUNTS = '\((\d+)\s*/\s*(\d+)\)';

type
  /// <summary>The flags import-coverage accepts.</summary>
  TCoverageFlag = (cfFile, cfDb, cfJson, cfHelp, cfOutputEncoding, cfIn);

const
  /// <summary>The spelling of each flag; the docs-sync guard reads this table.</summary>
  COVERAGE_FLAG_NAMES: array[TCoverageFlag] of string = ('--file', '--db', '--json', '--help', '--output-encoding', '--in');
  COVERAGE_VALUE_FLAGS = [cfFile, cfDb, cfOutputEncoding, cfIn];

type
  TCoverageOptions = record
    FilePath: string;
    DbPath: string;
    AsJson: Boolean;
    ShowHelp: Boolean;
  end;

/// <summary>The sidecar file that holds the imported coverage of an index.</summary>
/// <param name="pDbPath">The index file.</param>
/// <returns>pDbPath + '.coverage.json'.</returns>
function CoverageSidecarPath(const pDbPath: string): string;
begin
  Result:= pDbPath + CSidecarSuffix;
end;

function Unescape(const pText: string): string;
begin
  Result:= pText.Replace('&lt;', '<').Replace('&gt;', '>').Replace('&quot;', '"').Replace('&apos;', '''').Replace('&amp;', '&');
end;

function AttrOf(const pAttrs, pName: string): string;
begin
  Result:= '';
  for var M in TRegEx.Matches(pAttrs, RE_ATTR) do
    if SameText(M.Groups[1].Value, pName) then
      Exit(Unescape(if M.Groups[2].Success then M.Groups[2].Value else M.Groups[3].Value));
end;

function PriorityOf(const pType: string): Integer;
begin
  if pType.ToLowerInvariant.StartsWith('line') then
    Result:= CPrioLine
  else if pType.ToLowerInvariant.StartsWith('block') then
    Result:= CPrioBlock
  else
    Result:= CPrioOther;
end;

type
  /// <summary>The method being read while the report is walked.</summary>
  TMethodState = record
    Open: Boolean;
    Name: string;
    Prio: Integer;
    Covered: Integer;
    Total: Integer;
    LineCovered: Integer;
    LineTotal: Integer;
  end;

procedure FinishMethod(var pMethod: TMethodState; const pFile, pClass: string; var pRoutines: TArray<TCoverageRoutine>);
begin
  if pMethod.Open then
  begin
    var Rec: TCoverageRoutine;
    Rec.FileName:= pFile;
    Rec.Name:= if pClass = '' then pMethod.Name else pClass + '.' + pMethod.Name;
    Rec.Covered:= if pMethod.Prio > CPrioNone then pMethod.Covered else pMethod.LineCovered;
    Rec.Total:= if pMethod.Prio > CPrioNone then pMethod.Total else pMethod.LineTotal;
    if (Rec.Total > 0) and (pFile <> '') then
      pRoutines:= pRoutines + [Rec];
  end;
  pMethod:= Default(TMethodState);
end;

/// <summary>Reads a coverage report (emma or cobertura XML).</summary>
/// <param name="pFile">The report; read as text.</param>
/// <param name="pData">The records on success.</param>
/// <param name="pError">Why it failed; '' on success.</param>
/// <returns>True when at least one routine record was found.</returns>
function ParseCoverageReport(const pFile: string; out pData: TCoverageData; out pError: string): Boolean;
begin
  pData:= Default(TCoverageData);
  pError:= '';
  var Text:= '';
  try
    Text:= TFile.ReadAllText(pFile);
  except
    on E: Exception do
    begin
      pError:= 'cannot read ' + pFile + ': ' + E.Message;
      Exit(False);
    end;
  end;
  var CurFile:= '';
  var CurClass:= '';
  var Method:= Default(TMethodState);
  var SawSrcFile:= False;
  var SawLine:= False;
  for var Tag in TRegEx.Matches(Text, RE_TAG) do
  begin
    var Closing:= Tag.Groups[1].Value = '/';
    var Name:= Tag.Groups[2].Value.ToLowerInvariant;
    var Attrs:= Tag.Groups[3].Value;
    var SelfClosing:= Tag.Groups[4].Value = '/';
    if Closing then
    begin
      if Name = 'method' then
        FinishMethod(Method, CurFile, CurClass, pData.Routines)
      else if Name = 'class' then
        CurClass:= ''
      else if Name = 'srcfile' then
        CurFile:= '';
      Continue;
    end;
    if Name = 'srcfile' then
    begin
      SawSrcFile:= True;
      CurFile:= AttrOf(Attrs, 'name');
    end
    else if Name = 'class' then
    begin
      CurClass:= AttrOf(Attrs, 'name');
      if AttrOf(Attrs, 'filename') <> '' then
        CurFile:= AttrOf(Attrs, 'filename');
      if SelfClosing then
        CurClass:= '';
    end
    else if Name = 'method' then
    begin
      FinishMethod(Method, CurFile, CurClass, pData.Routines);
      Method.Open:= True;
      Method.Name:= AttrOf(Attrs, 'name');
      if SelfClosing then
        FinishMethod(Method, CurFile, CurClass, pData.Routines);
    end
    else if Method.Open and (Name = 'coverage') then
    begin
      var Prio:= PriorityOf(AttrOf(Attrs, 'type'));
      var Counts:= TRegEx.Match(AttrOf(Attrs, 'value'), RE_COUNTS);
      if Counts.Success and (Prio > Method.Prio) then
      begin
        Method.Prio:= Prio;
        Method.Covered:= StrToIntDef(Counts.Groups[1].Value, 0);
        Method.Total:= StrToIntDef(Counts.Groups[2].Value, 0);
      end;
    end
    else if Method.Open and (Name = 'line') then
    begin
      SawLine:= True;
      Inc(Method.LineTotal);
      var Hits:= if AttrOf(Attrs, 'hits') <> '' then AttrOf(Attrs, 'hits') else AttrOf(Attrs, 'hit');
      if StrToIntDef(Hits, 0) > 0 then
        Inc(Method.LineCovered);
    end;
  end;
  FinishMethod(Method, CurFile, CurClass, pData.Routines);
  pData.Source:= ExpandFileName(pFile);
  pData.Format:= if SawSrcFile then CFormatEmma else CFormatCobertura;
  Result:= Length(pData.Routines) > 0;
  if (not Result) and (not SawSrcFile) and (not SawLine) then
    pError:= 'no coverage records in ' + pFile + ' (expected a DelphiCodeCoverage EMMA XML or a Cobertura XML report)'
  else if not Result then
    pError:= 'no routine with counted lines in ' + pFile;
end;

function SaveCoverageSidecar(const pDbPath: string; const pData: TCoverageData; out pError: string): Boolean;
begin
  pError:= '';
  var Root:= TJSONObject.Create;
  try
    Root.AddPair('schema', CSchema);
    Root.AddPair('source', pData.Source);
    Root.AddPair('format', pData.Format);
    var Arr:= TJSONArray.Create;
    Root.AddPair('routines', Arr);
    for var R in pData.Routines do
    begin
      var O:= TJSONObject.Create;
      O.AddPair('file', R.FileName);
      O.AddPair('name', R.Name);
      O.AddPair('covered', TJSONNumber.Create(R.Covered));
      O.AddPair('total', TJSONNumber.Create(R.Total));
      Arr.AddElement(O);
    end;
    try
      TFile.WriteAllText(CoverageSidecarPath(pDbPath), Root.ToJSON, TEncoding.UTF8);
    except
      on E: Exception do
      begin
        pError:= 'cannot write ' + CoverageSidecarPath(pDbPath) + ': ' + E.Message;
        Exit(False);
      end;
    end;
  finally
    Root.Free;
  end;
  Result:= True;
end;

function LoadCoverageSidecar(const pDbPath: string; out pData: TCoverageData): Boolean;
begin
  pData:= Default(TCoverageData);
  Result:= False;
  if not FileExists(CoverageSidecarPath(pDbPath)) then
    Exit;
  var Root:= TJSONObject.ParseJSONValue(TFile.ReadAllText(CoverageSidecarPath(pDbPath), TEncoding.UTF8)) as TJSONObject;
  try
    if (Root = nil) or (Root.GetValue<string>('schema', '') <> CSchema) then
      Exit;
    pData.Source:= Root.GetValue<string>('source', '');
    pData.Format:= Root.GetValue<string>('format', '');
    var Arr:= Root.GetValue('routines') as TJSONArray;
    if Arr = nil then
      Exit;
    for var V in Arr do
    begin
      var O:= V as TJSONObject;
      var Rec: TCoverageRoutine;
      Rec.FileName:= O.GetValue<string>('file', '');
      Rec.Name:= O.GetValue<string>('name', '');
      Rec.Covered:= O.GetValue<Integer>('covered', 0);
      Rec.Total:= O.GetValue<Integer>('total', 0);
      pData.Routines:= pData.Routines + [Rec];
    end;
    Result:= True;
  finally
    Root.Free;
  end;
end;

function BaseKey(const pPath: string): string;
begin
  Result:= ExtractFileName(pPath.Replace('/', '\')).ToLowerInvariant;
end;

function NamesMatch(const pRoutine, pRecord: string): Boolean;
begin
  var A:= pRoutine.ToLowerInvariant;
  var B:= pRecord.ToLowerInvariant;
  Result:= (A = B) or A.EndsWith('.' + B) or B.EndsWith('.' + A);
end;

function MatchCoverage(const pRoutines: TArray<TMetricRow>; const pIndexedFiles: TArray<string>;
  const pData: TCoverageData): TCoverageMatch;
begin
  Result:= Default(TCoverageMatch);
  var Used: TArray<Boolean>:= [];
  SetLength(Used, Length(pData.Routines));
  SetLength(Result.Routines, Length(pRoutines));
  for var K:= 0 to High(pRoutines) do
  begin
    Result.Routines[K].Row:= pRoutines[K];
    var Key:= BaseKey(pRoutines[K].FilePath);
    for var J:= 0 to High(pData.Routines) do
      if (not Used[J]) and (BaseKey(pData.Routines[J].FileName) = Key) and NamesMatch(pRoutines[K].Name, pData.Routines[J].Name) then
      begin
        Used[J]:= True;
        Result.Routines[K].HasData:= True;
        Result.Routines[K].Covered:= pData.Routines[J].Covered;
        Result.Routines[K].Total:= pData.Routines[J].Total;
        Inc(Result.MatchedCount);
        Break;
      end;
  end;
  var Known:= TDictionary<string, Boolean>.Create;
  var Seen:= TDictionary<string, Boolean>.Create;
  try
    for var F in pIndexedFiles do
      Known.AddOrSetValue(BaseKey(F), True);
    for var J:= 0 to High(pData.Routines) do
    begin
      if not Used[J] then
        Result.UnmatchedRoutines:= Result.UnmatchedRoutines + [pData.Routines[J].FileName + ': ' + pData.Routines[J].Name];
      var Key:= BaseKey(pData.Routines[J].FileName);
      if (not Known.ContainsKey(Key)) and (not Seen.ContainsKey(Key)) then
      begin
        Seen.Add(Key, True);
        Result.UnmatchedFiles:= Result.UnmatchedFiles + [pData.Routines[J].FileName];
      end;
    end;
  finally
    Seen.Free;
    Known.Free;
  end;
end;

{ ---- the verb ---- }

function Usage(const pWhy: string): Integer;
begin
  Writeln(ErrOutput, 'ERROR: ' + CVerb + ': ' + pWhy);
  Writeln(ErrOutput, CUsageLine);
  Result:= CExitUsage;
end;

function ParseArgs(const pArgs: TArray<string>; out pOpts: TCoverageOptions; out pError, pBadFlag: string): Boolean;
begin
  pOpts:= Default(TCoverageOptions);
  pError:= '';
  pBadFlag:= '';
  var I:= 0;
  while I <= High(pArgs) do
  begin
    var Tok:= pArgs[I];
    var Flag:= cfFile;
    var Known:= False;
    for var F:= Low(TCoverageFlag) to High(TCoverageFlag) do
      if Tok = COVERAGE_FLAG_NAMES[F] then
      begin
        Flag:= F;
        Known:= True;
      end;
    if (not Known) and ((Tok = '-h') or (Tok = '/?')) then
    begin
      Flag:= cfHelp;
      Known:= True;
    end;
    if not Known then
    begin
      pBadFlag:= Tok;
      pError:= 'Unknown argument: ' + Tok;
      Exit(False);
    end;
    var Value:= '';
    if Flag in COVERAGE_VALUE_FLAGS then
    begin
      if (I + 1 > High(pArgs)) or pArgs[I + 1].StartsWith('--') then
      begin
        pError:= Tok + ' needs a value';
        Exit(False);
      end;
      Inc(I);
      Value:= pArgs[I];
    end;
    case Flag of
      cfFile, cfIn: pOpts.FilePath:= ExpandFileName(Value);
      cfDb: pOpts.DbPath:= ExpandFileName(Value);
      cfJson: pOpts.AsJson:= True;
      cfHelp: pOpts.ShowHelp:= True;
      cfOutputEncoding: ; { consumed before the dispatch; accepted so it is not "unknown" }
    end;
    Inc(I);
  end;
  Result:= True;
end;

function ListJson(const pItems: TArray<string>): TJSONArray;
begin
  Result:= TJSONArray.Create;
  for var S in pItems do
    Result.Add(S);
end;

procedure WriteSummary(const pOpts: TCoverageOptions; const pData: TCoverageData; const pMatch: TCoverageMatch; pIndexedRoutines: Integer);
begin
  var Uncovered:= pIndexedRoutines - pMatch.MatchedCount;
  if pOpts.AsJson then
  begin
    var O:= TJSONObject.Create;
    try
      O.AddPair('format', pData.Format);
      O.AddPair('sidecar', CoverageSidecarPath(pOpts.DbPath));
      O.AddPair('records', TJSONNumber.Create(Length(pData.Routines)));
      O.AddPair('matched', TJSONNumber.Create(pMatch.MatchedCount));
      O.AddPair('unmatched_records', TJSONNumber.Create(Length(pMatch.UnmatchedRoutines)));
      O.AddPair('indexed_routines_without_record', TJSONNumber.Create(Uncovered));
      O.AddPair('unmatched_files', ListJson(pMatch.UnmatchedFiles));
      O.AddPair('unmatched_routines', ListJson(pMatch.UnmatchedRoutines));
      Writeln(O.ToJSON);
    finally
      O.Free;
    end;
    Exit;
  end;
  Writeln(Format('import-coverage: %d routine record(s) read (%s) -> %s', [Length(pData.Routines), pData.Format, CoverageSidecarPath(pOpts.DbPath)]));
  Writeln(Format('matched: %d of %d record(s); indexed routines without a record: %d of %d',
    [pMatch.MatchedCount, Length(pData.Routines), Uncovered, pIndexedRoutines]));
  Writeln(Format('unmatched file(s): %d', [Length(pMatch.UnmatchedFiles)]));
  for var F in pMatch.UnmatchedFiles do
    Writeln('  file ' + F);
  Writeln(Format('unmatched record(s): %d', [Length(pMatch.UnmatchedRoutines)]));
  for var R in pMatch.UnmatchedRoutines do
    Writeln('  record ' + R);
end;

function Execute(const pOpts: TCoverageOptions): Integer;
begin
  var Data: TCoverageData;
  var Err: string;
  if not ParseCoverageReport(pOpts.FilePath, Data, Err) then
    Exit(Usage(Err));
  var Report: TMetricsReport;
  try
    Report:= LoadMetrics(pOpts.DbPath, DefaultMetricsOptions);
  except
    on E: EMetricsError do
      Exit(Usage(E.Message));
  end;
  var Files: TArray<string>:= [];
  for var U in Report.Units do
    Files:= Files + [U.FilePath];
  var Match:= MatchCoverage(Report.Routines, Files, Data);
  if not SaveCoverageSidecar(pOpts.DbPath, Data, Err) then
  begin
    Writeln(ErrOutput, 'ERROR: ' + CVerb + ': ' + Err);
    Exit(CExitFailure);
  end;
  WriteSummary(pOpts, Data, Match, Length(Report.Routines));
  Result:= CExitOk;
end;

function RunCoverageVerb: Integer;
begin
  var Args: TArray<string>:= [];
  for var I:= CFirstArg to ParamCount do
    Args:= Args + [ParamStr(I)];
  var Opts: TCoverageOptions;
  var Err, Bad: string;
  if not ParseArgs(Args, Opts, Err, Bad) then
  begin
    if Bad <> '' then
    begin
      WriteCliError(CLI_ERR_UNKNOWN_FLAG, Err, CommandLineWantsJson, 'flag', Bad);
      Result:= CExitUnknownFlag;
    end
    else
      Result:= Usage(Err);
  end
  else if Opts.ShowHelp then
  begin
    Writeln(CUsageLine);
    Result:= CExitOk;
  end
  else if Opts.FilePath = '' then
    Result:= Usage('give --in <report.xml>')
  else if Opts.DbPath = '' then
    Result:= Usage('give --db <file.sqlite>')
  else if not FileExists(Opts.FilePath) then
    Result:= Usage('report not found: ' + Opts.FilePath)
  else
    Result:= Execute(Opts);
end;

end.
