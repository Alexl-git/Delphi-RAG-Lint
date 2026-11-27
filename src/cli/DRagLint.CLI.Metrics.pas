unit DRagLint.CLI.Metrics;

{ drag-lint 1.56 -- lane MET-1: the `metrics` verb (gap-plan S3 + G-48, sections G-58 / G-59).
  Prints the rows of DRagLint.Query.Metrics: a total, then folder / unit / class / routine tables,
  then repeated parameter groups and one implementor / one descendant.
  --save appends one snapshot line (total + unit rows) to the history file beside the index,
  <db>.metrics.jsonl; the index itself is opened read-only and never written. --trend compares the
  last two snapshots of that file and refuses when there are fewer than two.
  Parses its own flags (like uses-recover and syntax-count): DRagLint.CLI.ParseArgs returns before
  its flag loop for this verb, so the flags, the database argument and the usage text all live
  here. The accepted flags are in ONE table, METRICS_FLAG_NAMES (docs-sync guard, check 9). }

interface

/// <summary>Runs the `metrics` verb from the process command line (ParamStr(2) onwards).</summary>
/// <returns>0 = answered; 1 = the history file could not be read or written; 2 = usage error or
/// refusal (no --db, an index that is missing or unreadable, an unknown --level, --save / --trend
/// together with --in, --trend with fewer than two snapshots); 3 = an unknown flag.</returns>
/// <remarks>Rows go to stdout (text, or one JSON document with --json); every refusal is one
/// line on stderr and nothing on stdout. Only --save writes, and only the history file.</remarks>
function RunMetricsVerb: Integer;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.JSON, System.DateUtils, System.Math,
  System.Generics.Collections, System.Generics.Defaults,
  DRagLint.Core.CliError, DRagLint.CLI.HelpText, DRagLint.Query.Metrics;

const
  CVerb = 'metrics';
  CExitOk = 0;
  CExitFailure = 1;
  CExitUsage = 2;
  CExitUnknownFlag = 3;
  CFirstArg = 2; { ParamStr(1) is the verb }
  CDefaultTop = 20;
  CHistorySuffix = '.metrics.jsonl';
  CSnapshotSchema = 'metrics-snapshot/1';
  CTrendSchema = 'metrics-trend/1';
  CTrendMinSnapshots = 2;
  CLevelAll = 'all';
  CUsageLine = 'usage: drag-lint metrics --db <file.sqlite> [--level routine,class,unit,folder|all] ' +
    '[--in <path prefix>] [--top <n>] [--save] [--trend] [--json]';

type
  /// <summary>The flags metrics accepts.</summary>
  TMetricsFlag = (mfDb, mfLevel, mfIn, mfTop, mfSave, mfTrend, mfJson, mfHelp, mfOutputEncoding);

const
  /// <summary>The spelling of each flag; the docs-sync guard reads this table as the verb's
  /// accepted-flag set.</summary>
  METRICS_FLAG_NAMES: array[TMetricsFlag] of string = ('--db', '--level', '--in', '--top', '--save',
    '--trend', '--json', '--help', '--output-encoding');
  /// <summary>The flags that take the next token as their value.</summary>
  METRICS_VALUE_FLAGS = [mfDb, mfLevel, mfIn, mfTop, mfOutputEncoding];
  { The numbers a snapshot keeps per row and a trend compares, by JSON member name. }
  TREND_MEMBERS: array[0..6] of string = ('units', 'classes', 'routines', 'cyclomatic',
    'cyclomatic_max', 'body_loc', 'comment_lines');

type
  /// <summary>The parsed flags of one metrics run.</summary>
  TMetricsCliOptions = record
    DbPath    : string;
    Levels    : TMetricLevels;
    PathPrefix: string;
    Top       : Integer;
    Save      : Boolean;
    Trend     : Boolean;
    AsJson    : Boolean;
    ShowHelp  : Boolean;
  end;

function Usage(const pWhy: string; pAsJson: Boolean): Integer;
begin
  Writeln(ErrOutput, 'ERROR: metrics: ' + pWhy);
  if not pAsJson then
    Writeln(ErrOutput, CUsageLine);
  Result:= CExitUsage;
end;

{ 'routine,unit' or 'all' -> the set; False names the token that is no level. }
function TryParseLevels(const pText: string; out pLevels: TMetricLevels; out pBad: string): Boolean;
var
  LLevel: TMetricLevel;
begin
  pLevels:= [];
  pBad:= '';
  for var LToken in pText.Split([',']) do
    if SameText(Trim(LToken), CLevelAll) then
      pLevels:= [mlRoutine, mlClass, mlUnit, mlFolder]
    else if TryParseMetricLevel(Trim(LToken), LLevel) and (LLevel <> mlTotal) then
      Include(pLevels, LLevel)
    else
    begin
      pBad:= LToken;
      Exit(False);
    end;
  Result:= pLevels <> [];
end;

/// <summary>Parses the metrics flags.</summary>
/// <param name="pArgs">The tokens after the verb.</param>
/// <param name="pOpts">The options; partly filled on failure.</param>
/// <param name="pError">Why parsing failed; '' on success.</param>
/// <param name="pBadFlag">The unknown flag when that is the failure (exit 3); '' otherwise (exit 2).</param>
/// <returns>True when every token is a known flag with a valid value.</returns>
function ParseMetricsArgs(const pArgs: TArray<string>; out pOpts: TMetricsCliOptions;
  out pError, pBadFlag: string): Boolean;
var
  I: Integer;
  LTok, LValue, LBad: string;
  LFlag: TMetricsFlag;
  LKnown: Boolean;
begin
  pOpts:= Default(TMetricsCliOptions);
  pOpts.Levels:= [mlRoutine, mlClass, mlUnit, mlFolder];
  pOpts.Top:= CDefaultTop;
  pError:= '';
  pBadFlag:= '';
  I:= 0;
  while I <= High(pArgs) do
  begin
    LTok:= pArgs[I];
    LKnown:= False;
    LFlag:= Low(TMetricsFlag);
    for var F:= Low(TMetricsFlag) to High(TMetricsFlag) do
      if LTok = METRICS_FLAG_NAMES[F] then
      begin
        LFlag:= F;
        LKnown:= True;
      end;
    if (not LKnown) and ((LTok = '-h') or (LTok = '/?')) then
    begin
      LFlag:= mfHelp;
      LKnown:= True;
    end;
    if not LKnown then
    begin
      pBadFlag:= LTok;
      pError:= 'Unknown argument: ' + LTok;
      Exit(False);
    end;
    LValue:= '';
    if LFlag in METRICS_VALUE_FLAGS then
    begin
      if (I + 1 > High(pArgs)) or pArgs[I + 1].StartsWith('--') then
      begin
        pError:= LTok + ' needs a value';
        Exit(False);
      end;
      Inc(I);
      LValue:= pArgs[I];
    end;
    case LFlag of
      mfDb   : pOpts.DbPath:= LValue;
      mfLevel:
        if not TryParseLevels(LValue, pOpts.Levels, LBad) then
        begin
          pError:= Format('unknown --level "%s" (routine, class, unit, folder, all)', [LBad]);
          Exit(False);
        end;
      mfIn   : pOpts.PathPrefix:= ExpandFileName(LValue);
      mfTop  :
        if (not TryStrToInt(LValue, pOpts.Top)) or (pOpts.Top < 0) then
        begin
          pError:= Format('--top needs a number of rows, 0 = all (got "%s")', [LValue]);
          Exit(False);
        end;
      mfSave : pOpts.Save:= True;
      mfTrend: pOpts.Trend:= True;
      mfJson : pOpts.AsJson:= True;
      mfHelp : pOpts.ShowHelp:= True;
      mfOutputEncoding: ; { consumed by Run before the dispatch; accepted so it is not "unknown" }
    end;
    Inc(I);
  end;
  Result:= True;
end;

{ ---- text output ---- }

function FanText(pValue: Integer): string;
begin
  Result:= if pValue = METRIC_NOT_MEASURED then '-' else IntToStr(pValue);
end;

function CompareByCyclomatic(const pLeft, pRight: TMetricRow): Integer;
begin
  Result:= pRight.Cyclomatic - pLeft.Cyclomatic;
  if Result = 0 then
    Result:= CompareText(pLeft.Name, pRight.Name);
  if Result = 0 then
    Result:= CompareText(pLeft.FilePath, pRight.FilePath);
  if Result = 0 then
    Result:= pLeft.Line - pRight.Line;
end;

procedure WriteRowLine(const pRow: TMetricRow);
var
  LPlace: string;
begin
  LPlace:= '';
  if pRow.Level in [mlRoutine, mlClass] then
    LPlace:= Format('  %s:%d', [pRow.FilePath, pRow.Line]);
  Writeln(Format('  %8d %6d %6d %8d %7d %8d %6d %6s %7s  %s%s', [pRow.Cyclomatic, pRow.CyclomaticMax,
    pRow.Routines, pRow.BodyLoc, pRow.Lines, pRow.CommentLines, pRow.Params, FanText(pRow.FanIn),
    FanText(pRow.FanOut), pRow.Name, LPlace]));
end;

procedure WriteHeaderLine;
begin
  Writeln(Format('  %8s %6s %6s %8s %7s %8s %6s %6s %7s  %s', ['cyclo', 'max', 'rtns', 'body_loc',
    'lines', 'comments', 'params', 'fan_in', 'fan_out', 'name']));
end;

{ One table: the rows with the highest cyclomatic value first, cut at pTop (0 = all). }
procedure WriteTable(const pTitle: string; const pRows: TArray<TMetricRow>; pTop: Integer);
var
  LRows: TArray<TMetricRow>;
  LShown: Integer;
begin
  LRows:= Copy(pRows);
  TArray.Sort<TMetricRow>(LRows, TComparer<TMetricRow>.Construct(CompareByCyclomatic));
  LShown:= if pTop = 0 then Length(LRows) else Min(pTop, Length(LRows));
  Writeln;
  if LShown < Length(LRows) then
    Writeln(Format('%s: %d, the %d with the highest cyclomatic value (--top 0 lists all)',
      [pTitle, Length(LRows), LShown]))
  else
    Writeln(Format('%s: %d', [pTitle, Length(LRows)]));
  if LShown > 0 then
    WriteHeaderLine;
  for var I:= 0 to LShown - 1 do
    WriteRowLine(LRows[I]);
end;

procedure WriteSections(const pReport: TMetricsReport; pTop: Integer);
var
  LShown: Integer;
begin
  Writeln;
  Writeln(Format('repeated parameter groups (%d or more parameters shared by %d or more differently named routines): %d',
    [PARAM_GROUP_MIN_PARAMS, PARAM_GROUP_MIN_ROUTINES, Length(pReport.ParamGroups)]));
  LShown:= if pTop = 0 then Length(pReport.ParamGroups) else Min(pTop, Length(pReport.ParamGroups));
  for var I:= 0 to LShown - 1 do
  begin
    Writeln(Format('  (%s)  in %d routine(s)', [string.Join('; ', pReport.ParamGroups[I].Params),
      Length(pReport.ParamGroups[I].Routines)]));
    for var LSite in pReport.ParamGroups[I].Routines do
      Writeln(Format('      %s  %s:%d', [LSite.Name, LSite.FilePath, LSite.Line]));
  end;
  if LShown < Length(pReport.ParamGroups) then
    Writeln(Format('  ... %d more (--top 0 lists all)', [Length(pReport.ParamGroups) - LShown]));
  Writeln;
  Writeln(Format('one implementor / one descendant (counted inside this index): %d', [Length(pReport.SingleHeirs)]));
  LShown:= if pTop = 0 then Length(pReport.SingleHeirs) else Min(pTop, Length(pReport.SingleHeirs));
  for var I:= 0 to LShown - 1 do
    Writeln(Format('  %-9s %s  %s:%d  <- %s  %s:%d', [pReport.SingleHeirs[I].Kind,
      pReport.SingleHeirs[I].Base.Name, pReport.SingleHeirs[I].Base.FilePath, pReport.SingleHeirs[I].Base.Line,
      pReport.SingleHeirs[I].Heir.Name, pReport.SingleHeirs[I].Heir.FilePath, pReport.SingleHeirs[I].Heir.Line]));
  if LShown < Length(pReport.SingleHeirs) then
    Writeln(Format('  ... %d more (--top 0 lists all)', [Length(pReport.SingleHeirs) - LShown]));
end;

procedure WriteText(const pReport: TMetricsReport; const pOpts: TMetricsCliOptions);
begin
  Writeln('metrics: ' + pReport.DbPath);
  Writeln(Format('total: %d unit(s), %d class(es) of which %d interface(s), %d routine(s); cyclomatic %d (max %d), ' +
    'body_loc %d (max %d), lines %d, comment lines %d', [pReport.Total.Units, pReport.Total.Classes,
    pReport.Total.Interfaces, pReport.Total.Routines, pReport.Total.Cyclomatic, pReport.Total.CyclomaticMax,
    pReport.Total.BodyLoc, pReport.Total.BodyLocMax, pReport.Total.Lines, pReport.Total.CommentLines]));
  if mlFolder in pOpts.Levels then
    WriteTable('folders', pReport.Folders, pOpts.Top);
  if mlUnit in pOpts.Levels then
    WriteTable('units', pReport.Units, pOpts.Top);
  if mlClass in pOpts.Levels then
    WriteTable('classes', pReport.Classes, pOpts.Top);
  if mlRoutine in pOpts.Levels then
    WriteTable('routines', pReport.Routines, pOpts.Top);
  WriteSections(pReport, pOpts.Top);
end;

{ ---- history (--save / --trend) ---- }

function HistoryPath(const pDbPath: string): string;
begin
  Result:= pDbPath + CHistorySuffix;
end;

{ The numbers of one row a snapshot keeps. }
function SnapshotRow(const pRow: TMetricRow): TJSONObject;
var
  LFull: TJSONObject;
  LValue: TJSONValue;
begin
  Result:= TJSONObject.Create;
  LFull:= MetricRowToJson(pRow);
  try
    Result.AddPair('name', pRow.Name);
    Result.AddPair('file', pRow.FilePath);
    for var LMember in TREND_MEMBERS do
    begin
      LValue:= LFull.GetValue(LMember);
      Result.AddPair(LMember, LValue.Clone as TJSONValue);
    end;
  finally
    LFull.Free;
  end;
end;

{ Appends one snapshot line; returns how many snapshots the file holds afterwards. }
function SaveSnapshot(const pReport: TMetricsReport; out pCount: Integer; out pError: string): Boolean;
var
  LSnap: TJSONObject;
  LUnits: TJSONArray;
  LBytes: TBytes;
  LStream: TFileStream;
  LPath: string;
  LMode: Word;
begin
  pError:= '';
  pCount:= 0;
  LPath:= HistoryPath(pReport.DbPath);
  LSnap:= TJSONObject.Create;
  try
    LSnap.AddPair('schema', CSnapshotSchema);
    LSnap.AddPair('saved_at', DateToISO8601(TTimeZone.Local.ToUniversalTime(Now), True));
    LSnap.AddPair('indexed_at_unix', TJSONNumber.Create(pReport.IndexedAtUnix));
    LSnap.AddPair('total', SnapshotRow(pReport.Total));
    LUnits:= TJSONArray.Create;
    LSnap.AddPair('units', LUnits);
    for var LUnit in pReport.Units do
      LUnits.AddElement(SnapshotRow(LUnit));
    LBytes:= TEncoding.UTF8.GetBytes(LSnap.ToJSON + sLineBreak);
  finally
    LSnap.Free;
  end;
  try
    LMode:= if FileExists(LPath) then fmOpenReadWrite or fmShareDenyWrite else fmCreate;
    LStream:= TFileStream.Create(LPath, LMode);
    try
      LStream.Seek(0, soEnd);
      LStream.WriteBuffer(LBytes, Length(LBytes));
    finally
      LStream.Free;
    end;
    for var LLine in TFile.ReadAllLines(LPath, TEncoding.UTF8) do
      if Trim(LLine) <> '' then
        Inc(pCount);
    Result:= True;
  except
    on E: Exception do
    begin
      pError:= 'cannot write the history file ' + LPath + ': ' + E.Message;
      Result:= False;
    end;
  end;
end;

{ Every snapshot of the history file, oldest first; the caller frees the list (it owns the
  objects). False with pError set when the file is unreadable or a line is no snapshot. }
function LoadSnapshots(const pPath: string; pInto: TObjectList<TJSONObject>; out pError: string): Boolean;
var
  LLines: TArray<string>;
  LValue: TJSONValue;
begin
  pError:= '';
  if not FileExists(pPath) then
    Exit(True);
  try
    LLines:= TFile.ReadAllLines(pPath, TEncoding.UTF8);
  except
    on E: Exception do
    begin
      pError:= 'cannot read the history file ' + pPath + ': ' + E.Message;
      Exit(False);
    end;
  end;
  for var I:= 0 to High(LLines) do
    if Trim(LLines[I]) <> '' then
    begin
      LValue:= TJSONObject.ParseJSONValue(LLines[I]);
      if (LValue is TJSONObject) and
         (TJSONObject(LValue).GetValue<string>('schema', '') = CSnapshotSchema) and
         (TJSONObject(LValue).GetValue('total') is TJSONObject) and
         (TJSONObject(LValue).GetValue('units') is TJSONArray) then
        pInto.Add(TJSONObject(LValue))
      else
      begin
        LValue.Free;
        pError:= Format('line %d of the history file %s is not a %s snapshot', [I + 1, pPath, CSnapshotSchema]);
        Exit(False);
      end;
    end;
  Result:= True;
end;

function NumberOf(pRow: TJSONObject; const pMember: string): Integer;
begin
  Result:= if pRow = nil then 0 else pRow.GetValue<Integer>(pMember, 0);
end;

{ member -> (from, to, delta) for every TREND_MEMBERS number; pFrom / pTo may be nil (a unit
  that exists on one side only). pChanged says whether any number differs. }
function DeltaJson(pFrom, pTo: TJSONObject; out pChanged: Boolean): TJSONObject;
var
  LOne: TJSONObject;
  LBefore, LAfter: Integer;
begin
  Result:= TJSONObject.Create;
  pChanged:= False;
  for var LMember in TREND_MEMBERS do
  begin
    LBefore:= NumberOf(pFrom, LMember);
    LAfter:= NumberOf(pTo, LMember);
    pChanged:= pChanged or (LBefore <> LAfter);
    LOne:= TJSONObject.Create;
    Result.AddPair(LMember, LOne);
    LOne.AddPair('from', TJSONNumber.Create(LBefore));
    LOne.AddPair('to', TJSONNumber.Create(LAfter));
    LOne.AddPair('delta', TJSONNumber.Create(LAfter - LBefore));
  end;
end;

{ The unit rows of a snapshot by lower-case file path (the name when the path is empty). }
procedure IndexUnits(pSnap: TJSONObject; pInto: TDictionary<string, TJSONObject>; pKeys: TStringList);
var
  LKey: string;
begin
  for var LItem in pSnap.GetValue('units') as TJSONArray do
    if LItem is TJSONObject then
    begin
      LKey:= LowerCase(TJSONObject(LItem).GetValue<string>('file', ''));
      if LKey = '' then
        LKey:= LowerCase(TJSONObject(LItem).GetValue<string>('name', ''));
      pInto.AddOrSetValue(LKey, TJSONObject(LItem));
      pKeys.Add(LKey);
    end;
end;

{ The trend document between two snapshots: total deltas and every unit that was added, removed
  or changed (unchanged units are counted, not listed). }
function BuildTrend(pFrom, pTo: TJSONObject; pSnapshots: Integer): TJSONObject;
var
  LBefore, LAfter: TDictionary<string, TJSONObject>;
  LKeys: TStringList;
  LUnits: TJSONArray;
  LUnit, LOld, LNew, LShown, LDelta: TJSONObject;
  LChanged: Boolean;
  LUnchanged: Integer;
  LStatus: string;
begin
  Result:= TJSONObject.Create;
  Result.AddPair('schema', CTrendSchema);
  Result.AddPair('snapshots', TJSONNumber.Create(pSnapshots));
  Result.AddPair('from', pFrom.GetValue<string>('saved_at', ''));
  Result.AddPair('to', pTo.GetValue<string>('saved_at', ''));
  Result.AddPair('total', DeltaJson(pFrom.GetValue('total') as TJSONObject, pTo.GetValue('total') as TJSONObject, LChanged));
  LUnits:= TJSONArray.Create;
  Result.AddPair('units', LUnits);
  LUnchanged:= 0;
  LBefore:= TDictionary<string, TJSONObject>.Create;
  LAfter:= TDictionary<string, TJSONObject>.Create;
  LKeys:= TStringList.Create;
  try
    LKeys.Sorted:= True;
    LKeys.Duplicates:= dupIgnore;
    IndexUnits(pFrom, LBefore, LKeys);
    IndexUnits(pTo, LAfter, LKeys);
    for var LKey in LKeys do
    begin
      LBefore.TryGetValue(LKey, LOld);
      LAfter.TryGetValue(LKey, LNew);
      LDelta:= DeltaJson(LOld, LNew, LChanged);
      LShown:= if LNew <> nil then LNew else LOld;
      if LOld = nil then
        LStatus:= 'added'
      else if LNew = nil then
        LStatus:= 'removed'
      else
        LStatus:= 'changed';
      if (LOld <> nil) and (LNew <> nil) and not LChanged then
      begin
        Inc(LUnchanged);
        LDelta.Free;
        Continue;
      end;
      LUnit:= TJSONObject.Create;
      LUnits.AddElement(LUnit);
      LUnit.AddPair('status', LStatus);
      LUnit.AddPair('name', LShown.GetValue<string>('name', ''));
      LUnit.AddPair('file', LShown.GetValue<string>('file', ''));
      LUnit.AddPair('numbers', LDelta);
    end;
  finally
    LKeys.Free;
    LAfter.Free;
    LBefore.Free;
  end;
  Result.AddPair('units_unchanged', TJSONNumber.Create(LUnchanged));
end;

function DeltaText(pNumbers: TJSONObject; const pMember: string): string;
var
  LOne: TJSONObject;
  LDelta: Integer;
  LSign: string;
begin
  LOne:= pNumbers.GetValue(pMember) as TJSONObject;
  LDelta:= LOne.GetValue<Integer>('delta', 0);
  LSign:= if LDelta >= 0 then '+' else '';
  Result:= Format('%s %d -> %d (%s%d)', [pMember, LOne.GetValue<Integer>('from', 0),
    LOne.GetValue<Integer>('to', 0), LSign, LDelta]);
end;

procedure WriteTrendText(pTrend: TJSONObject);
var
  LNumbers: TJSONObject;
  LParts: TArray<string>;
begin
  Writeln(Format('metrics trend: %s -> %s (the last two of %d snapshots)', [pTrend.GetValue<string>('from'),
    pTrend.GetValue<string>('to'), pTrend.GetValue<Integer>('snapshots')]));
  LNumbers:= pTrend.GetValue('total') as TJSONObject;
  for var LMember in TREND_MEMBERS do
    Writeln('  total ' + DeltaText(LNumbers, LMember));
  for var LItem in pTrend.GetValue('units') as TJSONArray do
  begin
    LNumbers:= (LItem as TJSONObject).GetValue('numbers') as TJSONObject;
    LParts:= nil;
    for var LMember in TREND_MEMBERS do
      if (LNumbers.GetValue(LMember) as TJSONObject).GetValue<Integer>('delta', 0) <> 0 then
        LParts:= LParts + [DeltaText(LNumbers, LMember)];
    Writeln(Format('  %-7s %s: %s', [LItem.GetValue<string>('status'), LItem.GetValue<string>('name'),
      string.Join(', ', LParts)]));
  end;
  Writeln(Format('  unchanged units: %d', [pTrend.GetValue<Integer>('units_unchanged')]));
end;

{ --trend: the last two snapshots of the history file, or the refusal. }
function RunTrend(const pOpts: TMetricsCliOptions): Integer;
var
  LSnaps: TObjectList<TJSONObject>;
  LTrend: TJSONObject;
  LError, LPath: string;
begin
  LPath:= HistoryPath(pOpts.DbPath);
  LSnaps:= TObjectList<TJSONObject>.Create(True);
  try
    if not LoadSnapshots(LPath, LSnaps, LError) then
    begin
      Writeln(ErrOutput, 'ERROR: metrics: ' + LError);
      Exit(CExitFailure);
    end;
    if LSnaps.Count < CTrendMinSnapshots then
      Exit(Usage(Format('--trend needs two saved snapshots, %s holds %d: run "metrics --save" after each index run',
        [LPath, LSnaps.Count]), True));
    LTrend:= BuildTrend(LSnaps[LSnaps.Count - CTrendMinSnapshots], LSnaps[LSnaps.Count - 1], LSnaps.Count);
    try
      if pOpts.AsJson then
        Writeln(LTrend.ToJSON)
      else
        WriteTrendText(LTrend);
    finally
      LTrend.Free;
    end;
    Result:= CExitOk;
  finally
    LSnaps.Free;
  end;
end;

{ The rows (and --save); with --trend the saved snapshot is compared instead of the rows printed. }
function Execute(const pOpts: TMetricsCliOptions): Integer;
var
  LOptions: TMetricsOptions;
  LReport: TMetricsReport;
  LJson: TJSONObject;
  LCount: Integer;
  LError: string;
begin
  if pOpts.Trend and not pOpts.Save then
    Exit(RunTrend(pOpts));
  LOptions:= DefaultMetricsOptions;
  LOptions.PathPrefix:= pOpts.PathPrefix;
  try
    LReport:= LoadMetrics(pOpts.DbPath, LOptions);
  except
    on E: EMetricsError do
      Exit(Usage(E.Message, pOpts.AsJson));
  end;
  if pOpts.Save then
  begin
    if not SaveSnapshot(LReport, LCount, LError) then
    begin
      Writeln(ErrOutput, 'ERROR: metrics: ' + LError);
      Exit(CExitFailure);
    end;
    Writeln(ErrOutput, Format('metrics: saved snapshot %d to %s', [LCount, HistoryPath(pOpts.DbPath)]));
  end;
  if pOpts.Trend then
    Exit(RunTrend(pOpts));
  if pOpts.AsJson then
  begin
    LJson:= MetricsToJson(LReport, pOpts.Levels);
    try
      Writeln(LJson.ToJSON);
    finally
      LJson.Free;
    end;
  end
  else
    WriteText(LReport, pOpts);
  Result:= CExitOk;
end;

function RunMetricsVerb: Integer;
var
  LArgs: TArray<string>;
  LOpts: TMetricsCliOptions;
  LError, LBadFlag: string;
  I: Integer;
begin
  LArgs:= nil;
  for I:= CFirstArg to ParamCount do
    LArgs:= LArgs + [ParamStr(I)];
  if not ParseMetricsArgs(LArgs, LOpts, LError, LBadFlag) then
  begin
    if LBadFlag <> '' then
    begin
      WriteCliError(CLI_ERR_UNKNOWN_FLAG, LError, CommandLineWantsJson, 'flag', LBadFlag);
      Result:= CExitUnknownFlag;
    end
    else
      Result:= Usage(LError, CommandLineWantsJson);
  end
  else if LOpts.ShowHelp then
  begin
    WriteVerbHelp(CVerb);
    Result:= CExitOk;
  end
  else if LOpts.DbPath = '' then
    Result:= Usage('give --db <file.sqlite>', LOpts.AsJson)
  else if (LOpts.Save or LOpts.Trend) and (LOpts.PathPrefix <> '') then
    Result:= Usage('--save and --trend record the whole index: drop --in', LOpts.AsJson)
  else
    Result:= Execute(LOpts);
end;

end.
