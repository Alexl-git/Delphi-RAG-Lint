unit DRagLint.Charts.Q.Risk;

{ drag-lint 1.56 -- lane G51 (gap G-51): the chart question `risk` (`ask risk`).
  Complex, untested routines first: a CRAP-style score per routine from the cyclomatic complexity of the
  index (DRagLint.Query.Metrics, MET-1) and the coverage imported by `import-coverage` (the sidecar
  <db>.coverage.json, DRagLint.CLI.Coverage).
    score = cc^2 * (1 - coverage)^3 + cc        coverage = covered lines / counted lines of the routine, 0..1
  A routine with no coverage record scores as coverage 0 (the worst case) and is counted as "without
  coverage data"; with no import at all every routine does, and the meta says so. Nothing is dropped from the
  CSV; the chart shows the top N (the question's Cap).
  The id, its menu caption and its two count labels are a row of V156_QUESTIONS in DRagLint.Charts.Question.
  Output: risk.dot (a ranked column of boxes) plus risk.csv (rank,routine,file,line,cc,coverage,has_data,score).
  Counts: LeftCount = routines drawn, RightCount = routines (of all scored) without coverage data. }

interface

const
  /// <summary>The registered question id.</summary>
  RISK_ID = 'risk';

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Generics.Collections, System.Generics.Defaults,
  System.Math, DRagLint.Charts.Question, DRagLint.Charts.Text, DRagLint.Charts.Dot,
  DRagLint.Query.Metrics, DRagLint.CLI.Coverage;

const
  DEFAULT_CAP = 20;
  FULL_RATIO = 1.0;
  NO_RATIO = 0.0;
  NO_COVERAGE_NOTE = 'no coverage imported -- complexity only'; // said in the chart and in the meta when import-coverage was never run
  PERCENT = 100;
  GAP_EXPONENT = 3;
  HOT_FILL = '#FDECEE';
  COOL_FILL = '#E2F1EF';
  HOT_SCORE = 30.0;

{ The CRAP-style risk score of one routine: cc^2 * (1 - coverage)^3 + cc, coverage clamped to 0..1; unit-private (the report rows call it). }
function RiskScore(pCyclomatic: Integer; pCoverage: Double): Double;
begin
  var Cov:= EnsureRange(pCoverage, NO_RATIO, FULL_RATIO);
  Result:= Sqr(pCyclomatic) * Power(FULL_RATIO - Cov, GAP_EXPONENT) + pCyclomatic;
end;

type
  /// <summary>One scored routine.</summary>
  TRisk = record
    Name: string;
    Path: string;
    Line: Integer;
    Cyclomatic: Integer;
    Coverage: Double;
    HasData: Boolean;
    Score: Double;
  end;

function Num(pValue: Double): string;
begin
  Result:= Format('%.3f', [pValue], TFormatSettings.Invariant);
end;

function Pct(pValue: Double): string;
begin
  Result:= Format('%.1f', [pValue * PERCENT], TFormatSettings.Invariant);
end;

function CsvCell(const pText: string): string;
begin
  Result:= '"' + pText.Replace('"', '""') + '"';
end;

/// <summary>Answers `risk`: the routines ranked by complexity times missing coverage.</summary>
/// <param name="pArgs">The question arguments; Target is ignored (project-wide); Cap bounds the routines drawn (the highest scores win).</param>
/// <param name="pOutDir">Where dot, svg, plain, png, pdf and the csv are written.</param>
/// <returns>The chart result: LeftCount = routines drawn, RightCount = scored routines without coverage data.</returns>
/// <remarks>Read-only. Meta fields: Scored, Shown, WithCoverage, WithoutCoverage, UnmatchedRecords, UnmatchedFiles,
/// CoverageImported, CoverageSource, ClickTargets, Expected, AllClickable.</remarks>
function Emit(const pArgs: TQuestionArgs; const pOutDir: string): TChartResult;
begin
  var Report:= LoadMetrics(pArgs.GuardedDb, DefaultMetricsOptions);
  var Cov: TCoverageData;
  var Imported:= LoadCoverageSidecar(pArgs.DbPath, Cov);
  var Files: TArray<string>:= [];
  for var U in Report.Units do
    Files:= Files + [U.FilePath];
  var Match:= MatchCoverage(Report.Routines, Files, Cov);
  var All: TArray<TRisk>:= [];
  var WithData:= 0;
  for var M in Match.Routines do
  begin
    var R:= Default(TRisk);
    R.Name:= M.Row.Name;
    R.Path:= M.Row.FilePath;
    R.Line:= M.Row.Line;
    R.Cyclomatic:= Max(M.Row.Cyclomatic, 1);
    R.HasData:= M.HasData;
    R.Coverage:= if M.HasData and (M.Total > 0) then M.Covered / M.Total else NO_RATIO;
    R.Score:= RiskScore(R.Cyclomatic, R.Coverage);
    if R.HasData then
      Inc(WithData);
    All:= All + [R];
  end;
  TArray.Sort<TRisk>(All, TComparer<TRisk>.Construct(
    function(const pA, pB: TRisk): Integer
    begin
      Result:= CompareValue(pB.Score, pA.Score);
      if Result = 0 then
        Result:= CompareText(pA.Name, pB.Name);
      if Result = 0 then
        Result:= CompareText(pA.Path, pB.Path);
    end));
  var Cap:= if pArgs.Cap > 0 then pArgs.Cap else DEFAULT_CAP;
  var Shown:= Min(Cap, Length(All));
  var Sb:= TStringBuilder.Create;
  var Csv:= TStringBuilder.Create;
  try
    Sb.AppendLine('digraph risk {');
    if not Imported then
      Sb.AppendLine('  label="' + NO_COVERAGE_NOTE + '"; labelloc=t;');
    Sb.AppendLine('  rankdir=TB; bgcolor="transparent"; nodesep=0.1; ranksep=0.15;');
    Sb.AppendLine('  node [shape=box, style="rounded,filled", fontname="Consolas", fontsize=12];');
    Csv.AppendLine('rank,routine,file,line,cc,coverage,has_data,score');
    var Expected:= 0;
    for var K:= 0 to High(All) do
    begin
      var R:= All[K];
      Csv.AppendLine(Format('%d,%s,%s,%d,%d,%s,%s,%s', [K + 1, CsvCell(R.Name), CsvCell(R.Path), R.Line, R.Cyclomatic,
        Num(R.Coverage), if R.HasData then 'true' else 'false', Num(R.Score)]));
      if K >= Shown then
        Continue;
      var Url:= '';
      if R.Path <> '' then
      begin
        Inc(Expected);
        Url:= Format(', URL="%s"', [RowHref(R.Path, R.Line)]);
      end;
      Sb.AppendLine(Format('  r%d [fillcolor="%s", label="%s\ncc %d  coverage %s%%%s  risk %s", tooltip="%s"%s];',
        [K, if R.Score >= HOT_SCORE then HOT_FILL else COOL_FILL, XmlText(R.Name), R.Cyclomatic, if Imported then Pct(R.Coverage) else 'n/a',
         if R.HasData or not Imported then '' else ' (no data)', Num(R.Score), XmlText(R.Name), Url]));
      if K > 0 then
        Sb.AppendLine(Format('  r%d -> r%d [style=invis];', [K - 1, K]));
    end;
    Sb.AppendLine('}');
    TDirectory.CreateDirectory(pOutDir);
    TFile.WriteAllText(TPath.Combine(pOutDir, 'risk.csv'), Csv.ToString, TEncoding.UTF8);
    var Msgs: TArray<string>;
    Result.Layout:= DotLayout(pArgs.Dot, Sb.ToString, pOutDir, 'risk', Msgs);
    Result.LeftCount:= Shown;
    Result.RightCount:= Length(All) - WithData;
    Result.ClickTargets:= Result.Layout.Anchors;
    Result.AllClickable:= Result.Layout.Anchors >= Expected;
    Result.Fields:= [TMetaField.Int('Scored', Length(All)), TMetaField.Int('Shown', Shown),
      TMetaField.Int('WithCoverage', WithData), TMetaField.Int('WithoutCoverage', Length(All) - WithData),
      TMetaField.Int('UnmatchedRecords', Length(Match.UnmatchedRoutines)), TMetaField.Int('UnmatchedFiles', Length(Match.UnmatchedFiles)),
      TMetaField.Bool('CoverageImported', Imported), TMetaField.Str('CoverageSource', Cov.Source),
      TMetaField.Str('Note', if Imported then '' else NO_COVERAGE_NOTE),
      TMetaField.Int('ClickTargets', Result.Layout.Anchors), TMetaField.Int('Expected', Expected),
      TMetaField.Bool('AllClickable', Result.AllClickable)];
  finally
    Csv.Free;
    Sb.Free;
  end;
end;

initialization
  RegisterChartQuestion(RISK_ID, Emit);

end.
