unit DRagLint.Charts.Q.Hotspots;

{ drag-lint 1.56 -- lane G41: the chart question `hotspots` (`ask hotspots`), gap G-41.
  A treemap of the units of the index: the area of a rectangle is the unit's size, its colour the worst
  complexity found in it. Complex code that is also big is the code to repair first.
  The id, its menu caption and its two count labels are a row of V156_QUESTIONS in DRagLint.Charts.Question.

  Nothing is recomputed: every number is a field of the frozen metrics rows of DRagLint.Query.Metrics
  (LoadMetrics), read from the same index file the question was asked on.
    size    = the unit row's Lines (last line of the unit), at least 1.
    colour  = the unit row's CyclomaticMax, the largest cyclomatic complexity of one routine of the unit:
              up to 10 low, 11..20 moderate, 21..50 high, above 50 very high.
    hottest = the routine with the largest cyclomatic complexity of the unit (first by line on a tie).
  Lint findings are NOT stored in an index (a finding exists only while `lint` runs), so the chart carries no
  per-unit finding count; it says so ("no findings in this DB") and the meta field Findings says `not stored`.
  Nothing is invented.
  Layout: a deterministic balanced treemap (units by size, then name; the list is cut where the running sum
  passes half of the total, the cut along the longer side). Output: hotspots.dot (neato, every rectangle pinned
  at its position with a fixed size) plus hotspots_metrics.csv (unit,lines,body_loc,cyclomatic,cyclomatic_max,
  hottest_routine,hottest_cyclomatic) beside it.
  Counts: LeftCount = units drawn, RightCount = units whose worst routine is above HOT_COMPLEXITY (20). }

interface

const
  /// <summary>The registered question id.</summary>
  HOTSPOTS_ID = 'hotspots';
  /// <summary>A unit whose largest routine complexity is above this is counted as a hotspot.</summary>
  HOT_COMPLEXITY = 20;

implementation

uses
  System.SysUtils, System.IOUtils, System.Generics.Collections, System.Generics.Defaults,
  System.Math, DRagLint.Charts.Question, DRagLint.Charts.Text, DRagLint.Charts.Dot, DRagLint.Query.Metrics;

const
  DEFAULT_CAP = 60;
  CANVAS_W = 14.0;
  CANVAS_H = 8.0;
  GAP = 0.03;
  HALF = 2;
  LOW_COMPLEXITY = 10;
  HIGH_COMPLEXITY = 50;
  LOW_FILL = '#E2F1EF';
  MODERATE_FILL = '#FFF4CC';
  HIGH_FILL = '#FBD9B5';
  VERY_HIGH_FILL = '#F4B6BC';
  NOTE_INK = '#5B6674';
  FINDINGS_NOTE = 'lint findings are not stored in an index: no findings in this DB';

type
  /// <summary>One unit and the place its rectangle takes.</summary>
  TTile = record
    Row: TMetricRow;
    Hottest: string;
    HottestCc: Integer;
    Size: Int64;
    X, Y, W, H: Double;
  end;

function Num(pValue: Double): string;
begin
  Result:= Format('%.4f', [pValue], TFormatSettings.Invariant);
end;

function FillOf(pComplexity: Integer): string;
begin
  if pComplexity > HIGH_COMPLEXITY then
    Result:= VERY_HIGH_FILL
  else if pComplexity > HOT_COMPLEXITY then
    Result:= HIGH_FILL
  else if pComplexity > LOW_COMPLEXITY then
    Result:= MODERATE_FILL
  else
    Result:= LOW_FILL;
end;

function CsvText(const pS: string): string;
begin
  Result:= if pS.Contains(',') or pS.Contains('"') then '"' + pS.Replace('"', '""') + '"' else pS;
end;

{ Cuts tiles pLo..pHi (sorted by size, largest first) into the rectangle: the list is split where the running
  sum first reaches half of the total, the rectangle along its longer side in that proportion. }
procedure Slice(var pTiles: TArray<TTile>; pLo, pHi: Integer; pX, pY, pW, pH: Double);
begin
  if pLo = pHi then
  begin
    pTiles[pLo].X:= pX;  // dl:ok index-possibly-out-of-range@51bc -- REVIEWED 2026-11-27 G41: Slice is only called with 0 <= pLo <= pHi <= High(pTiles); Emit skips the call for an empty list
    pTiles[pLo].Y:= pY;
    pTiles[pLo].W:= pW;
    pTiles[pLo].H:= pH;
    Exit;
  end;
  var Total: Int64:= 0;
  for var K:= pLo to pHi do
    Inc(Total, pTiles[K].Size);
  var Acc: Int64:= pTiles[pLo].Size;
  var Cut:= pLo;
  while (Cut < pHi - 1) and (Acc * HALF < Total) do
  begin
    Inc(Cut);  // dl:ok index-possibly-out-of-range@dc5c -- REVIEWED 2026-11-27 G41: the loop condition keeps Cut < pHi, so Cut stays inside pLo..pHi
    Inc(Acc, pTiles[Cut].Size);
  end;
  var Frac:= Acc / Total;
  if pW >= pH then
  begin
    Slice(pTiles, pLo, Cut, pX, pY, pW * Frac, pH);
    Slice(pTiles, Cut + 1, pHi, pX + pW * Frac, pY, pW - pW * Frac, pH);
  end
  else
  begin
    Slice(pTiles, pLo, Cut, pX, pY, pW, pH * Frac);
    Slice(pTiles, Cut + 1, pHi, pX, pY + pH * Frac, pW, pH - pH * Frac);
  end;
end;

/// <summary>Answers `hotspots`: a treemap of the units by size, coloured by their worst routine complexity.</summary>
/// <param name="pArgs">The question arguments; Target is ignored (project-wide); Cap bounds the units drawn (the largest win).</param>
/// <param name="pOutDir">Where dot, svg, plain, png, pdf and the metrics csv are written.</param>
/// <returns>The chart result: LeftCount = units drawn, RightCount = units whose largest routine complexity is above HOT_COMPLEXITY.</returns>
/// <exception cref="EMetricsError">The index cannot be read as a metrics source.</exception>
/// <remarks>Read-only. Meta fields: Units, Hot, Hidden, HotThreshold, Findings, ClickTargets, Expected, AllClickable.</remarks>
function Emit(const pArgs: TQuestionArgs; const pOutDir: string): TChartResult;
begin
  var Report:= LoadMetrics(pArgs.GuardedDb, DefaultMetricsOptions);
  var Worst:= TDictionary<string, TPair<Integer, string>>.Create;
  try
    for var R in Report.Routines do
    begin
      var Key:= R.FilePath.ToLowerInvariant;
      var Cur: TPair<Integer, string>;
      if not Worst.TryGetValue(Key, Cur) or (R.Cyclomatic > Cur.Key) then
        Worst.AddOrSetValue(Key, TPair<Integer, string>.Create(R.Cyclomatic, R.Name));
    end;
    var Tiles: TArray<TTile>:= [];
    for var U in Report.Units do
    begin
      var T:= Default(TTile);
      T.Row:= U;
      T.Size:= Max(U.Lines, 1);
      var Hot: TPair<Integer, string>;
      if Worst.TryGetValue(U.FilePath.ToLowerInvariant, Hot) then
      begin
        T.HottestCc:= Hot.Key;
        T.Hottest:= Hot.Value;
      end;
      Tiles:= Tiles + [T];
    end;
    TArray.Sort<TTile>(Tiles, TComparer<TTile>.Construct(
      function(const pA, pB: TTile): Integer
      begin
        Result:= CompareValue(pB.Size, pA.Size);
        if Result = 0 then
          Result:= CompareText(pA.Row.Name, pB.Row.Name);
      end));
    var Total:= Length(Tiles);
    var Cap:= if pArgs.Cap > 0 then pArgs.Cap else DEFAULT_CAP;
    if Total > Cap then
      SetLength(Tiles, Cap);
    if Length(Tiles) > 0 then
      Slice(Tiles, 0, High(Tiles), 0, 0, CANVAS_W, CANVAS_H);

    var Sb:= TStringBuilder.Create;
    var Csv:= TStringBuilder.Create;
    try
      Sb.AppendLine('digraph hotspots {');
      Sb.AppendLine('  layout=neato; bgcolor="transparent"; overlap=true; labelloc=b;');
      Sb.AppendLine('  label="' + XmlText(FINDINGS_NOTE) + '"; fontname="Consolas"; fontsize=11; fontcolor="' + NOTE_INK + '";');
      Sb.AppendLine('  node [shape=box, style=filled, fixedsize=true, fontname="Consolas", fontsize=10];');
      Csv.AppendLine('unit,lines,body_loc,cyclomatic,cyclomatic_max,hottest_routine,hottest_cyclomatic');
      var Hot:= 0;
      var Expected:= 0;
      for var K:= 0 to High(Tiles) do
      begin
        var T:= Tiles[K];
        if T.Row.CyclomaticMax > HOT_COMPLEXITY then
          Inc(Hot);
        var Url:= '';
        if T.Row.FilePath <> '' then
        begin
          Inc(Expected);
          Url:= Format(', URL="%s"', [RowHref(T.Row.FilePath, T.Row.Line)]);
        end;
        Sb.AppendLine(Format('  u%d [label="%s\n%d lines  cc %d", fillcolor="%s", width=%s, height=%s, pos="%s,%s!", ' +
          'tooltip="%s: %d lines, %d body lines, largest routine complexity %d, hottest %s"%s];',
          [K, XmlText(T.Row.Name), T.Row.Lines, T.Row.CyclomaticMax, FillOf(T.Row.CyclomaticMax),
           Num(Max(T.W - GAP, GAP)), Num(Max(T.H - GAP, GAP)), Num(T.X + T.W / HALF), Num(CANVAS_H - T.Y - T.H / HALF),
           XmlText(T.Row.Name), T.Row.Lines, T.Row.BodyLoc, T.Row.CyclomaticMax, XmlText(T.Hottest), Url]));
        Csv.AppendLine(Format('%s,%d,%d,%d,%d,%s,%d', [CsvText(T.Row.Name), T.Row.Lines, T.Row.BodyLoc, T.Row.Cyclomatic,
          T.Row.CyclomaticMax, CsvText(T.Hottest), T.HottestCc]));
      end;
      Sb.AppendLine('}');
      TDirectory.CreateDirectory(pOutDir);
      TFile.WriteAllText(TPath.Combine(pOutDir, 'hotspots_metrics.csv'), Csv.ToString, TEncoding.UTF8);
      var Msgs: TArray<string>;
      Result.Layout:= DotLayout(pArgs.Dot, Sb.ToString, pOutDir, 'hotspots', Msgs);
      Result.LeftCount:= Length(Tiles);
      Result.RightCount:= Hot;
      Result.ClickTargets:= Result.Layout.Anchors;
      Result.AllClickable:= Result.Layout.Anchors >= Expected;
      Result.Fields:= [TMetaField.Int('Units', Length(Tiles)), TMetaField.Int('Hot', Hot),
        TMetaField.Int('Hidden', Total - Length(Tiles)), TMetaField.Int('HotThreshold', HOT_COMPLEXITY),
        TMetaField.Str('Findings', 'not stored'), TMetaField.Int('ClickTargets', Result.Layout.Anchors),
        TMetaField.Int('Expected', Expected), TMetaField.Bool('AllClickable', Result.AllClickable)];
    finally
      Csv.Free;
      Sb.Free;
    end;
  finally
    Worst.Free;
  end;
end;

initialization
  RegisterChartQuestion(HOTSPOTS_ID, Emit);

end.
