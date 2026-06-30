unit DRagLint.Lint.Baseline;

interface

uses
  System.SysUtils, System.JSON, System.IOUtils, System.Hash,
  System.Generics.Collections, DRagLint.Core.Model;

type
  /// <summary>Line-shift-stable baseline: fingerprints findings by rule id +
  /// normalized path + a hash of the finding's (trimmed) source-line CONTENT, so
  /// inserting or removing unrelated lines does not invalidate a baselined
  /// finding. Used to report only NEW findings on a legacy codebase.</summary>
  TBaseline = class
  strict private
    /// <summary>Lowercased, backslash-normalized file path.</summary>
    class function NormPath(const APath: string): string; static;
    /// <summary>Reads (and caches in ACache) the trimmed text of line ALine
    /// (1-based) from AFile; '' if the file/line is unavailable.</summary>
    class function SourceLineText(const AFile: string; ALine: Integer;
      const ACache: TDictionary<string, TArray<string>>): string; static;
    /// <summary>Fingerprints with an occurrence ordinal appended pre-hash, so two
    /// findings on identical-text lines in the same (rule,file) disambiguate.</summary>
    class function FingerprintsOf(const AFindings: TArray<TLintFinding>): TArray<string>; static;
  public
    /// <summary>Fingerprint for one finding (occurrence ordinal 0). Stable across
    /// line-number shifts; changes only when rule, file, or the line text change.</summary>
    class function Fingerprint(const AFinding: TLintFinding): string; static;
    /// <summary>Writes the findings' fingerprints to APath as
    /// { "version":1, "fingerprints":[...] }.</summary>
    class procedure Write(const APath: string; const AFindings: TArray<TLintFinding>); static;
    /// <summary>Returns only findings whose fingerprint is absent from the
    /// baseline at APath. If APath is missing/unreadable, returns AFindings
    /// unchanged.</summary>
    class function Filter(const APath: string; const AFindings: TArray<TLintFinding>): TArray<TLintFinding>; static;
  end;

implementation

class function TBaseline.NormPath(const APath: string): string;
begin
  Result:= LowerCase(StringReplace(APath, '/', '\', [rfReplaceAll]));
end;

class function TBaseline.SourceLineText(const AFile: string; ALine: Integer;
  const ACache: TDictionary<string, TArray<string>>): string;
var
  Lines: TArray<string>;
begin
  Result:= '';
  if ALine < 1 then Exit;
  if not ACache.TryGetValue(AFile, Lines) then
  begin
    if TFile.Exists(AFile) then
      Lines:= TFile.ReadAllLines(AFile, TEncoding.UTF8)
    else
      Lines:= [];
    ACache.Add(AFile, Lines);
  end;
  if (ALine - 1) <= High(Lines) then Result:= Trim(Lines[ALine - 1]);
end;

class function TBaseline.FingerprintsOf(const AFindings: TArray<TLintFinding>): TArray<string>;
var
  Cache  : TDictionary<string, TArray<string>>;
  Counts : TDictionary<string, Integer>;
  F      : TLintFinding;
  LineTxt, BaseKey, Ord, Raw: string;
  N      : Integer;
begin
  Result:= nil;
  Cache := TDictionary<string, TArray<string>>.Create;
  Counts:= TDictionary<string, Integer>.Create;
  try
    for F in AFindings do
    begin
      LineTxt:= SourceLineText(F.FilePath, F.StartLine, Cache);
      BaseKey:= LowerCase(F.RuleId) + '|' + NormPath(F.FilePath) + '|' + LineTxt;
      if not Counts.TryGetValue(BaseKey, N) then N:= 0;
      Counts.AddOrSetValue(BaseKey, N + 1);
      if N = 0 then Ord:= '' else Ord:= #0 + IntToStr(N);
      Raw:= BaseKey + Ord;
      Result:= Result + [THashSHA2.GetHashString(Raw)];
    end;
  finally
    Counts.Free;
    Cache.Free;
  end;
end;

class function TBaseline.Fingerprint(const AFinding: TLintFinding): string;
var
  Fps: TArray<string>;
begin
  Fps:= FingerprintsOf([AFinding]);
  Result:= Fps[0];
end;

class procedure TBaseline.Write(const APath: string; const AFindings: TArray<TLintFinding>);
var
  Root: TJSONObject;
  Arr : TJSONArray ;
  Fp  : string     ;
begin
  Root:= TJSONObject.Create;
  try
    Root.AddPair('version', TJSONNumber.Create(1));
    Arr:= TJSONArray.Create;
    Root.AddPair('fingerprints', Arr);
    for Fp in FingerprintsOf(AFindings) do
      Arr.Add(Fp);
    TFile.WriteAllText(APath, Root.Format(2), TEncoding.UTF8);
  finally
    Root.Free;
  end;
end;

class function TBaseline.Filter(const APath: string; const AFindings: TArray<TLintFinding>): TArray<TLintFinding>;
var
  RootVal: TJSONValue;
  Arr    : TJSONArray;
  Known  : TDictionary<string, Boolean>;
  V      : TJSONValue;
  Fps    : TArray<string>;
  i      : Integer;
begin
  if not TFile.Exists(APath) then Exit(AFindings);

  RootVal:= TJSONObject.ParseJSONValue(TFile.ReadAllText(APath, TEncoding.UTF8));
  if not (RootVal is TJSONObject) then
  begin
    RootVal.Free;
    Exit(AFindings);
  end;

  Known:= TDictionary<string, Boolean>.Create;
  try
    if (RootVal as TJSONObject).GetValue('fingerprints') is TJSONArray then
    begin
      Arr:= (RootVal as TJSONObject).GetValue('fingerprints') as TJSONArray;
      for V in Arr do Known.AddOrSetValue(V.Value, True);
    end;

    Result:= nil;
    Fps:= FingerprintsOf(AFindings);
    for i:= 0 to High(AFindings) do
      if not Known.ContainsKey(Fps[i]) then
        Result:= Result + [AFindings[i]];
  finally
    RootVal.Free;
    Known.Free;
  end;
end;

end.
