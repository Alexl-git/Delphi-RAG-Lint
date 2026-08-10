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
    /// <param name="APath"><!-- drag-lint:auto type -->const string</param>
    /// <returns><!-- drag-lint:auto -->Observed: LowerCase(StringReplace(APath, '/', '\',
    /// [rfReplaceAll])).</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.Lint.Baseline.TBaseline.FingerprintsOf (DRagLint.Lint.Baseline.pas)
    /// Calls: LowerCase, StringReplace
    /// Pure
    /// <seealso cref="DRagLint.Lint.Baseline.TBaseline.Filter"/>
    /// <seealso cref="DRagLint.Lint.Baseline.TBaseline.Fingerprint"/>
    /// <seealso cref="DRagLint.Lint.Baseline.TBaseline.FingerprintsOf"/>
    /// <seealso cref="DRagLint.Lint.Baseline.TBaseline.SourceLineText"/>
    /// <seealso cref="DRagLint.Lint.Baseline.TBaseline.Write"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function NormPath(const APath: string): string; static;
    /// <summary>Reads (and caches in ACache) the trimmed text of line ALine
    /// (1-based) from AFile; '' if the file/line is unavailable.</summary>
    /// <param name="AFile"><!-- drag-lint:auto type -->const string</param>
    /// <param name="ALine"><!-- drag-lint:auto type -->Integer</param>
    /// <param name="ACache"><!-- drag-lint:auto type -->const TDictionary&lt;string, TArray&lt;string&gt;&gt;</param>
    /// <returns><!-- drag-lint:auto -->Observed: ''; Trim(Lines[ALine - 1]).</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.Lint.Baseline.TBaseline.FingerprintsOf (DRagLint.Lint.Baseline.pas)
    /// Calls: Trim
    /// Touches: file system
    /// <seealso cref="DRagLint.Lint.Baseline.TBaseline.Filter"/>
    /// <seealso cref="DRagLint.Lint.Baseline.TBaseline.Fingerprint"/>
    /// <seealso cref="DRagLint.Lint.Baseline.TBaseline.FingerprintsOf"/>
    /// <seealso cref="DRagLint.Lint.Baseline.TBaseline.NormPath"/>
    /// <seealso cref="DRagLint.Lint.Baseline.TBaseline.Write"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function SourceLineText(const AFile: string; ALine: Integer;
      const ACache: TDictionary<string, TArray<string>>): string; static;
    /// <summary>Fingerprints with an occurrence ordinal appended pre-hash, so two
    /// findings on identical-text lines in the same (rule,file) disambiguate.</summary>
    /// <param name="AFindings"><!-- drag-lint:auto type -->const TArray&lt;TLintFinding&gt;</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.Lint.Baseline.TBaseline.Filter (DRagLint.Lint.Baseline.pas), DRagLint.Lint.Baseline.TBaseline.Fingerprint (DRagLint.Lint.Baseline.pas), DRagLint.Lint.Baseline.TBaseline.Write (DRagLint.Lint.Baseline.pas)
    /// Calls: DRagLint.Lint.Baseline.TBaseline.NormPath, DRagLint.Lint.Baseline.TBaseline.SourceLineText, IntToStr, LowerCase
    /// Pure
    /// <seealso cref="DRagLint.Lint.Baseline.TBaseline.NormPath"/>
    /// <seealso cref="DRagLint.Lint.Baseline.TBaseline.SourceLineText"/>
    /// <seealso cref="DRagLint.Lint.Baseline.TBaseline.Filter"/>
    /// <seealso cref="DRagLint.Lint.Baseline.TBaseline.Fingerprint"/>
    /// <seealso cref="DRagLint.Lint.Baseline.TBaseline.Write"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function FingerprintsOf(const AFindings: TArray<TLintFinding>): TArray<string>; static;
  public
    /// <summary>Fingerprint for one finding (occurrence ordinal 0). Stable across
    /// line-number shifts; changes only when rule, file, or the line text change.</summary>
    /// <param name="AFinding"><!-- drag-lint:auto type -->const TLintFinding</param>
    /// <returns><!-- drag-lint:auto -->Observed: Fps[0].</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Calls: DRagLint.Lint.Baseline.TBaseline.FingerprintsOf
    /// Pure
    /// <seealso cref="DRagLint.Lint.Baseline.TBaseline.FingerprintsOf"/>
    /// <seealso cref="DRagLint.Lint.Baseline.TBaseline.Filter"/>
    /// <seealso cref="DRagLint.Lint.Baseline.TBaseline.NormPath"/>
    /// <seealso cref="DRagLint.Lint.Baseline.TBaseline.SourceLineText"/>
    /// <seealso cref="DRagLint.Lint.Baseline.TBaseline.Write"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function Fingerprint(const AFinding: TLintFinding): string; static;
    /// <summary>Writes the findings' fingerprints to APath as
    /// { "version":1, "fingerprints":[...] }.</summary>
    /// <param name="APath"><!-- drag-lint:auto type -->const string</param>
    /// <param name="AFindings"><!-- drag-lint:auto type -->const TArray&lt;TLintFinding&gt;</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.CLI.FinalizeAndOutput (DRagLint.CLI.pas), DRagLint.CLI.DoExportEnums (DRagLint.CLI.pas) ?, DRagLint.CLI.DoHover (DRagLint.CLI.pas) ?, DRagLint.CLI.DoTypeAt (DRagLint.CLI.pas) ?, DRagLint.CLI.DoCycles (DRagLint.CLI.pas) ? (+4 more)
    /// Calls: DRagLint.Lint.Baseline.TBaseline.FingerprintsOf
    /// Touches: file system
    /// <seealso cref="DRagLint.Lint.Baseline.TBaseline.FingerprintsOf"/>
    /// <seealso cref="DRagLint.Lint.Baseline.TBaseline.Filter"/>
    /// <seealso cref="DRagLint.Lint.Baseline.TBaseline.Fingerprint"/>
    /// <seealso cref="DRagLint.Lint.Baseline.TBaseline.NormPath"/>
    /// <seealso cref="DRagLint.Lint.Baseline.TBaseline.SourceLineText"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class procedure Write(const APath: string; const AFindings: TArray<TLintFinding>); static;
    /// <summary>Returns only findings whose fingerprint is absent from the
    /// baseline at APath. If APath is missing/unreadable, returns AFindings
    /// unchanged.</summary>
    /// <param name="APath"><!-- drag-lint:auto type -->const string</param>
    /// <param name="AFindings"><!-- drag-lint:auto type -->const TArray&lt;TLintFinding&gt;</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.CLI.FinalizeAndOutput (DRagLint.CLI.pas)
    /// Calls: DRagLint.Lint.Baseline.TBaseline.FingerprintsOf
    /// Touches: file system
    /// <seealso cref="DRagLint.Lint.Baseline.TBaseline.FingerprintsOf"/>
    /// <seealso cref="DRagLint.Lint.Baseline.TBaseline.Fingerprint"/>
    /// <seealso cref="DRagLint.Lint.Baseline.TBaseline.NormPath"/>
    /// <seealso cref="DRagLint.Lint.Baseline.TBaseline.SourceLineText"/>
    /// <seealso cref="DRagLint.Lint.Baseline.TBaseline.Write"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
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
