unit DRagLint.Core.UsageLog;

{ Counted savings: a best-effort per-user usage log for the READER verbs
  (context, query, find-callers) and the `gain` report that sums it.

  WHY. Until now the only record of what the index saved was a hand-written
  stats\draglint-usage.log. A saving nobody counts is a claim, not a number.
  Every reader verb that answers from the index appends ONE tab-separated line
  here; `drag-lint gain` sums the file per verb and per day.

  LINE FORMAT (tab separated, one line per verb run):
    ISO8601-UTC  verb  db_tag  tokens_returned  units_avoided  bytes_avoided
  tokens_avoided is DERIVED, never stored: bytes_avoided / 4, the same formula
  the hand-written CLAUDE.md log uses.

  NEVER FATAL. Writing the log is a side channel: no failure (read-only or
  missing LOCALAPPDATA, a locked file, a full disk) may change a verb's output
  or exit code. DRAGLINT_USAGE_LOG=0 turns the log off entirely. }

interface

uses
  System.SysUtils;

const
  /// <summary>Environment switch: the value '0' disables the usage log.</summary>
  USAGE_LOG_ENV = 'DRAGLINT_USAGE_LOG';
  /// <summary>Bytes-per-token used to derive tokens_avoided from bytes_avoided.</summary>
  USAGE_BYTES_PER_TOKEN = 4;

/// <summary>True unless DRAGLINT_USAGE_LOG=0.</summary>
function UsageLogEnabled: Boolean;

/// <summary>Full path of the per-user usage log: %LOCALAPPDATA%\drag-lint\usage.log.</summary>
/// <returns>The path, or '' when no per-user folder can be determined.</returns>
function UsageLogPath: string;

/// <summary>Sums the sizes of the distinct, existing files in APaths.</summary>
/// <param name="APaths">Absolute file paths; duplicates (case-insensitive) count once.</param>
/// <param name="AUnits">Out: how many distinct existing files were counted.</param>
/// <returns>Total bytes of those files; 0 when none exist.</returns>
/// <remarks>Never raises; an unreadable path is skipped.</remarks>
function SumDistinctFileBytes(const APaths: TArray<string>; out AUnits: Integer): Int64;

/// <summary>Appends one usage line. Best effort: never raises, writes nothing when disabled.</summary>
/// <param name="AVerb">Verb that answered, e.g. 'context' or 'query'.</param>
/// <param name="ADbTag">Database the answer came from (file name without extension).</param>
/// <param name="ATokensReturned">Estimated tokens the verb printed.</param>
/// <param name="ASourceBytesAvoided">Bytes of source the reader would otherwise have read.</param>
/// <param name="AUnitsAvoided">Number of distinct source files those bytes span.</param>
/// <remarks>Not thread-safe across processes beyond the OS append atomicity of one short line.</remarks>
procedure RecordUsage(const AVerb, ADbTag: string; ATokensReturned, ASourceBytesAvoided: Int64; AUnitsAvoided: Integer);

/// <summary>Renders the `gain` report from a usage log.</summary>
/// <param name="ALogPath">Usage log to sum; a missing file yields an all-zero report.</param>
/// <param name="ASince">Optional date prefix (yyyy-mm-dd); lines older than it are skipped.</param>
/// <param name="AAsJson">True for the JSON form, false for the text table.</param>
/// <returns>The report text, without a trailing newline.</returns>
function BuildGainReport(const ALogPath, ASince: string; AAsJson: Boolean): string;

implementation

uses
  System.DateUtils, System.Generics.Collections, System.IOUtils, System.JSON, System.Math;

const
  FIELD_COUNT   = 6;
  FIELD_TOKENS  = 3; { index of tokens_returned in a log line }
  FIELD_UNITS   = 4;
  FIELD_BYTES   = 5;
  DAY_CHARS     = 10;
  RATIO_DECIMAL = -2;
  AUDIT_DIR     = 'drag-lint';
  AUDIT_FILE    = 'usage.log';

type
  TGainTotals = record
    Calls         : Integer;
    TokensReturned: Int64  ;
    UnitsAvoided  : Int64  ;
    BytesAvoided  : Int64  ;
  end;

function UsageLogEnabled: Boolean;
begin
  Result:= GetEnvironmentVariable(USAGE_LOG_ENV) <> '0';
end;

function UsageLogPath: string;
var
  Base: string;
begin
  Base:= GetEnvironmentVariable('LOCALAPPDATA');
  if Base = '' then Base:= TPath.GetCachePath;
  if Base = '' then Exit('');
  Result:= TPath.Combine(TPath.Combine(Base, AUDIT_DIR), AUDIT_FILE);
end;

function SumDistinctFileBytes(const APaths: TArray<string>; out AUnits: Integer): Int64;
var
  Seen: TDictionary<string, Boolean>;
  P   : string;
begin
  Result:= 0;
  AUnits:= 0;
  Seen:= TDictionary<string, Boolean>.Create;
  try
    for P in APaths do
    begin
      if (P = '') or Seen.ContainsKey(LowerCase(P)) then Continue;
      Seen.Add(LowerCase(P), True);
      try
        if TFile.Exists(P) then
        begin
          Inc(Result, TFile.GetSize(P));
          Inc(AUnits);
        end;
      except
        { an unreadable path is simply not counted }
      end;
    end;
  finally
    Seen.Free;
  end; // try
end; // function

function Clean(const S: string): string;
begin
  Result:= StringReplace(StringReplace(S, #9, ' ', [rfReplaceAll]), #10, ' ', [rfReplaceAll]);
  Result:= StringReplace(Result, #13, ' ', [rfReplaceAll]);
end;

procedure RecordUsage(const AVerb, ADbTag: string; ATokensReturned, ASourceBytesAvoided: Int64; AUnitsAvoided: Integer);
var
  Path: string;
  Line: string;
begin
  if not UsageLogEnabled then Exit;
  try
    Path:= UsageLogPath;
    if Path = '' then Exit;
    if not ForceDirectories(ExtractFilePath(Path)) then Exit;
    Line:= Format('%s'#9'%s'#9'%s'#9'%d'#9'%d'#9'%d', [
      FormatDateTime('yyyy-mm-dd"T"hh:nn:ss"Z"', TTimeZone.Local.ToUniversalTime(Now)),
      Clean(AVerb), Clean(ADbTag), ATokensReturned, AUnitsAvoided, ASourceBytesAvoided]) + sLineBreak;
    TFile.AppendAllText(Path, Line, TEncoding.ASCII);
  except
    { best effort by contract: the usage log must never change a verb's result }
  end;
end; // procedure

procedure AddTo(var ATotals: TGainTotals; const AFields: TArray<string>);
begin
  Inc(ATotals.Calls);
  Inc(ATotals.TokensReturned, StrToInt64Def(AFields[FIELD_TOKENS], 0));
  Inc(ATotals.UnitsAvoided  , StrToInt64Def(AFields[FIELD_UNITS], 0));
  Inc(ATotals.BytesAvoided  , StrToInt64Def(AFields[FIELD_BYTES], 0));
end;

function TokensAvoided(const ATotals: TGainTotals): Int64;
begin
  Result:= ATotals.BytesAvoided div USAGE_BYTES_PER_TOKEN;
end;

function RatioOf(const ATotals: TGainTotals): Double;
begin
  Result:= if ATotals.TokensReturned > 0 then TokensAvoided(ATotals) / ATotals.TokensReturned else 0;
end;

function TotalsToJson(const ATotals: TGainTotals; const AKeyName, AKeyValue: string): TJSONObject;
begin
  Result:= TJSONObject.Create;
  if AKeyName <> '' then Result.AddPair(AKeyName, AKeyValue);
  Result.AddPair('calls'          , TJSONNumber.Create(ATotals.Calls));
  Result.AddPair('tokens_returned', TJSONNumber.Create(ATotals.TokensReturned));
  Result.AddPair('units_avoided'  , TJSONNumber.Create(ATotals.UnitsAvoided));
  Result.AddPair('bytes_avoided'  , TJSONNumber.Create(ATotals.BytesAvoided));
  Result.AddPair('tokens_avoided' , TJSONNumber.Create(TokensAvoided(ATotals)));
  Result.AddPair('ratio'          , TJSONNumber.Create(RoundTo(RatioOf(ATotals), RATIO_DECIMAL)));
end;

function TotalsToRow(const AName: string; const ATotals: TGainTotals): string;
begin
  Result:= Format('%-14s %6d %16d %15d %8.1fx', [AName, ATotals.Calls, ATotals.TokensReturned, TokensAvoided(ATotals), RatioOf(ATotals)]);
end;

function BuildGainReport(const ALogPath, ASince: string; AAsJson: Boolean): string;
var
  Lines : TArray<string>;
  Line  : string;
  F     : TArray<string>;
  Total : TGainTotals;
  ByVerb: TDictionary<string, TGainTotals>;
  ByDay : TDictionary<string, TGainTotals>;
  T     : TGainTotals;
  Keys  : TArray<string>;
  K     : string;
  JRoot : TJSONObject;
  JVerbs: TJSONArray;
  JDays : TJSONArray;
  SB    : TStringBuilder;
begin
  Total:= Default(TGainTotals);
  ByVerb:= TDictionary<string, TGainTotals>.Create;
  ByDay := TDictionary<string, TGainTotals>.Create;
  try
    if (ALogPath <> '') and TFile.Exists(ALogPath) then
    begin
      try
        Lines:= TFile.ReadAllLines(ALogPath, TEncoding.ASCII);
      except
        Lines:= nil; { unreadable log reads as an empty one }
      end;
      for Line in Lines do
      begin
        F:= Line.Split([#9]);
        if Length(F) < FIELD_COUNT then Continue;
        if (ASince <> '') and (Copy(F[0], 1, Length(ASince)) < ASince) then Continue;
        AddTo(Total, F);
        if not ByVerb.TryGetValue(F[1], T) then T:= Default(TGainTotals);
        AddTo(T, F);
        ByVerb.AddOrSetValue(F[1], T);
        K:= Copy(F[0], 1, DAY_CHARS);
        if not ByDay.TryGetValue(K, T) then T:= Default(TGainTotals);
        AddTo(T, F);
        ByDay.AddOrSetValue(K, T);
      end;
    end;

    if AAsJson then
    begin
      JRoot:= TJSONObject.Create;
      try
        JRoot.AddPair('log'  , ALogPath);
        JRoot.AddPair('since', ASince );
        JRoot.AddPair('total', TotalsToJson(Total, '', ''));
        JVerbs:= TJSONArray.Create;
        JRoot.AddPair('by_verb', JVerbs);
        Keys:= ByVerb.Keys.ToArray;
        TArray.Sort<string>(Keys);
        for K in Keys do JVerbs.AddElement(TotalsToJson(ByVerb[K], 'verb', K));
        JDays:= TJSONArray.Create;
        JRoot.AddPair('by_day', JDays);
        Keys:= ByDay.Keys.ToArray;
        TArray.Sort<string>(Keys);
        for K in Keys do JDays.AddElement(TotalsToJson(ByDay[K], 'day', K));
        Result:= JRoot.Format(2);
      finally
        JRoot.Free;
      end; // try
    end // if
    else
    begin
      SB:= TStringBuilder.Create;
      try
        SB.AppendLine('drag-lint gain -- counted savings from ' + ALogPath);
        if ASince <> '' then SB.AppendLine('since ' + ASince);
        SB.AppendLine(Format('%-14s %6s %16s %15s %9s', ['verb', 'calls', 'tokens_returned', 'tokens_avoided', 'ratio']));
        Keys:= ByVerb.Keys.ToArray;
        TArray.Sort<string>(Keys);
        for K in Keys do SB.AppendLine(TotalsToRow(K, ByVerb[K]));
        SB.AppendLine(TotalsToRow('TOTAL', Total));
        SB.AppendLine('by day:');
        Keys:= ByDay.Keys.ToArray;
        TArray.Sort<string>(Keys);
        for K in Keys do SB.AppendLine('  ' + TotalsToRow(K, ByDay[K]));
        Result:= TrimRight(SB.ToString);
      finally
        SB.Free;
      end; // try
    end; // else
  finally
    ByDay.Free;
    ByVerb.Free;
  end; // try
end; // function

end.
