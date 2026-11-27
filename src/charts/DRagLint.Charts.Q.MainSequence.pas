unit DRagLint.Charts.Q.MainSequence;

{ drag-lint 1.56 -- lane CHA-1: the chart question `main-sequence` (`ask main-sequence`).
  G-40: abstractness against instability per unit, the distance from the main sequence (R. Martin).
  The id, its menu caption and its two count labels are a row of V156_QUESTIONS in DRagLint.Charts.Question
  (written by W2FRAME; another wording is a request to INT).

  Definitions (every number is computed from the index, none estimated):
    Ca  afferent coupling  = distinct INDEXED units that name this unit in a uses clause.
    Ce  efferent coupling  = distinct INDEXED units this unit names in a uses clause. Library units (RTL, VCL,
                             third party: no indexed unit) are NOT counted, so the RTL does not flatten every I.
    I   instability        = Ce / (Ca + Ce); a unit with Ca + Ce = 0 has I = 0.
    A   abstractness       = abstract types / types, over the unit's class and interface symbols. An interface is
                             abstract; a class is abstract when its declaration line reads `class abstract` or one of
                             its methods' declaration lines carries the `abstract` directive (the index stores no
                             modifier for either, so the unit's source line is read; an unreadable file counts as
                             concrete and is reported as SourcesMissing). Records are not counted. A unit with no
                             class or interface has A = 0.
    D   distance           = |A + I - 1|. A unit is "off the main sequence" when D > OFF_DISTANCE (0.5).
  Output: main_sequence.dot (A on the vertical, I on the horizontal axis, units pinned at their coordinates, the
  main sequence A + I = 1 dashed) plus main_sequence_metrics.csv (unit,Ca,Ce,I,A,D) beside it.
  Counts: LeftCount = units drawn, RightCount = units off the main sequence. }

interface

const
  /// <summary>The registered question id.</summary>
  MAIN_SEQUENCE_ID = 'main-sequence';
  /// <summary>A unit whose distance from the main sequence is greater than this is counted as off it.</summary>
  OFF_DISTANCE = 0.5;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Generics.Collections, System.Generics.Defaults,
  System.RegularExpressions, System.Math, DRagLint.Charts.Question, DRagLint.Charts.Index, DRagLint.Charts.Text,
  DRagLint.Charts.Dot;

const
  DEFAULT_CAP = 60;
  PLOT_SIZE = 8.0;
  NO_RATIO = 0.0;
  FULL_RATIO = 1.0;
  OFF_FILL = '#FDECEE';
  ON_FILL = '#E2F1EF';
  AXIS_INK = '#8A94A6';
  MAIN_INK = '#B02A37';
  RE_CLASS_ABSTRACT = '\bclass\s+abstract\b';
  RE_METHOD_ABSTRACT = ';\s*abstract\s*;';

type
  /// <summary>One indexed unit and its measures.</summary>
  TUnitMetrics = record
    Name: string;
    Path: string;
    Line: Integer;
    Ca: Integer;
    Ce: Integer;
    Types: Integer;
    AbstractTypes: Integer;
    function Instability: Double;
    function Abstractness: Double;
    function Distance: Double;
  end;

function TUnitMetrics.Instability: Double;
begin
  Result:= if Ca + Ce = 0 then NO_RATIO else Ce / (Ca + Ce);
end;

function TUnitMetrics.Abstractness: Double;
begin
  Result:= if Types = 0 then NO_RATIO else AbstractTypes / Types;
end;

function TUnitMetrics.Distance: Double;
begin
  Result:= Abs(Abstractness + Instability - FULL_RATIO);
end;

function Num(pValue: Double): string;
begin
  Result:= Format('%.3f', [pValue], TFormatSettings.Invariant);
end;

function NodeId(pIndex: Integer): string;
begin
  Result:= 'u' + pIndex.ToString;
end;

function Coord(pValue: Double): string;
begin
  Result:= Format('%.4f', [pValue * PLOT_SIZE], TFormatSettings.Invariant);
end;

function SourceLines(const pPath: string; const pCache: TDictionary<string, TArray<string>>; var pMissing: Integer): TArray<string>;
begin
  if pCache.TryGetValue(pPath, Result) then
    Exit;
  Result:= [];
  try
    Result:= TFile.ReadAllLines(pPath, TEncoding.ANSI);
  except  // dl:ok try-except-swallowed@90db -- REVIEWED 2026-11-27 CHA-1: an unreadable source file only means its classes read as concrete; the count is reported as SourcesMissing
    on Exception do
      Inc(pMissing);  // an unreadable source: its classes count as concrete, SourcesMissing says how often
  end;
  pCache.Add(pPath, Result);
end;

function LineOf(const pLines: TArray<string>; pLine: Integer): string;
begin
  Result:= if InRange(pLine, 1, Length(pLines)) then pLines[pLine - 1] else '';
end;

/// <summary>Answers `main-sequence`: abstractness against instability for every unit.</summary>
/// <param name="pArgs">The question arguments; Target is ignored (project-wide); Cap bounds the units drawn (the ones farthest from the main sequence win).</param>
/// <param name="pOutDir">Where dot, svg, plain, png, pdf and the metrics csv are written.</param>
/// <returns>The chart result: LeftCount = units drawn, RightCount = units with a distance above OFF_DISTANCE.</returns>
/// <remarks>Read-only. Meta fields: Units, OffSequence, Threshold, Hidden, SourcesMissing, ClickTargets, Expected, AllClickable.</remarks>
function Emit(const pArgs: TQuestionArgs; const pOutDir: string): TChartResult;
begin
  var Index:= TChartsIndex.Create(pArgs.GuardedDb);
  var Units: TArray<TUnitMetrics>:= [];
  var Known:= TDictionary<string, Integer>.Create;
  var ByFile:= TDictionary<Integer, Integer>.Create;
  var Pairs:= TDictionary<string, Boolean>.Create;
  var Cache:= TDictionary<string, TArray<string>>.Create;
  var Missing:= 0;
  try
    var UnitRows:= Index.Query('SELECT s.qualified_name AS q, s.file_id AS fid, f.path AS path, s.start_line AS line' + sLineBreak +
      '  FROM symbols s JOIN files f ON f.id = s.file_id WHERE s.kind = ''unit'' ORDER BY LOWER(s.qualified_name), s.id');
    try
      for var R in UnitRows do
        if not Known.ContainsKey(R.S('q').ToLowerInvariant) then
        begin
          var U:= Default(TUnitMetrics);
          U.Name:= R.S('q');
          U.Path:= R.S('path');
          U.Line:= R.I('line');
          Known.Add(U.Name.ToLowerInvariant, Length(Units));
          ByFile.AddOrSetValue(R.I('fid'), Length(Units));
          Units:= Units + [U];
        end;
    finally
      UnitRows.Free;
    end;

    var EdgeRows:= Index.Query('SELECT LOWER(su.qualified_name) AS src, LOWER(uu.unit_name) AS dst' + sLineBreak +
      '  FROM unit_uses uu JOIN symbols su ON su.file_id = uu.file_id AND su.kind = ''unit''');
    try
      for var E in EdgeRows do
      begin
        var Src:= E.S('src');
        var Dst:= E.S('dst');
        var SrcAt, DstAt: Integer;
        if (Src <> Dst) and Known.TryGetValue(Src, SrcAt) and Known.TryGetValue(Dst, DstAt) and not Pairs.ContainsKey(Src + '|' + Dst) then
        begin
          Pairs.Add(Src + '|' + Dst, True);
          Inc(Units[SrcAt].Ce);
          Inc(Units[DstAt].Ca);
        end;
      end;
    finally
      EdgeRows.Free;
    end;

    // abstractness: interfaces, `class abstract`, and classes with an `abstract;` method
    var AbstractClass:= TDictionary<Integer, Boolean>.Create;
    try
      var TypeRows:= Index.Query('SELECT s.id AS id, s.kind AS kind, s.file_id AS fid, s.start_line AS line, f.path AS path' + sLineBreak +
        '  FROM symbols s JOIN files f ON f.id = s.file_id WHERE s.kind IN (''class'', ''interface'') ORDER BY s.id');
      var MethodRows:= Index.Query('SELECT m.parent_id AS pid, m.start_line AS line, f.path AS path' + sLineBreak +
        '  FROM symbols m JOIN files f ON f.id = m.file_id JOIN symbols p ON p.id = m.parent_id' + sLineBreak +
        ' WHERE m.kind = ''method'' AND p.kind = ''class'' ORDER BY m.id');
      try
        for var M in MethodRows do
          if TRegEx.IsMatch(LineOf(SourceLines(M.S('path'), Cache, Missing), M.I('line')), RE_METHOD_ABSTRACT, [roIgnoreCase]) then
            AbstractClass.AddOrSetValue(M.I('pid'), True);
        for var T in TypeRows do
        begin
          var Owner: Integer;
          if not ByFile.TryGetValue(T.I('fid'), Owner) then
            Continue;
          Inc(Units[Owner].Types);
          var IsAbstract:= SameText(T.S('kind'), 'interface') or AbstractClass.ContainsKey(T.I('id'))
            or TRegEx.IsMatch(LineOf(SourceLines(T.S('path'), Cache, Missing), T.I('line')), RE_CLASS_ABSTRACT, [roIgnoreCase]);
          if IsAbstract then
            Inc(Units[Owner].AbstractTypes);
        end;
      finally
        MethodRows.Free;
        TypeRows.Free;
      end;
    finally
      AbstractClass.Free;
    end;

    var Cap:= if pArgs.Cap > 0 then pArgs.Cap else DEFAULT_CAP;
    var Order: TArray<Integer>:= [];
    for var K:= 0 to High(Units) do
      Order:= Order + [K];
    if Length(Units) > Cap then
    begin
      TArray.Sort<Integer>(Order, TComparer<Integer>.Construct(
        function(const pA, pB: Integer): Integer
        begin
          Result:= CompareValue(Units[pB].Distance, Units[pA].Distance);
          if Result = 0 then
            Result:= CompareText(Units[pA].Name, Units[pB].Name);
        end));
      SetLength(Order, Cap);
      TArray.Sort<Integer>(Order, TComparer<Integer>.Construct(
        function(const pA, pB: Integer): Integer
        begin
          Result:= CompareText(Units[pA].Name, Units[pB].Name);
        end));
    end;

    var Sb:= TStringBuilder.Create;
    var Csv:= TStringBuilder.Create;
    try
      Sb.AppendLine('digraph main_sequence {');
      Sb.AppendLine('  layout=neato; bgcolor="transparent"; splines=line; overlap=true;');
      Sb.AppendLine('  node [fontname="Consolas", fontsize=12];');
      Sb.AppendLine('  edge [fontname="Consolas", fontsize=11];');
      Sb.AppendLine('  c00 [shape=point, width=0.05, pos="0,0!", xlabel="I=0 A=0", fontcolor="' + AXIS_INK + '"];');
      Sb.AppendLine('  c10 [shape=point, width=0.05, pos="' + Coord(1) + ',0!", xlabel="I=1 A=0", fontcolor="' + AXIS_INK + '"];');
      Sb.AppendLine('  c01 [shape=point, width=0.05, pos="0,' + Coord(1) + '!", xlabel="I=0 A=1", fontcolor="' + AXIS_INK + '"];');
      Sb.AppendLine('  c11 [shape=point, width=0.05, pos="' + Coord(1) + ',' + Coord(1) + '!", xlabel="I=1 A=1", fontcolor="' + AXIS_INK + '"];');
      Sb.AppendLine('  c00 -> c10 [dir=none, color="' + AXIS_INK + '"]; c10 -> c11 [dir=none, color="' + AXIS_INK + '"];');
      Sb.AppendLine('  c11 -> c01 [dir=none, color="' + AXIS_INK + '"]; c01 -> c00 [dir=none, color="' + AXIS_INK + '"];');
      Sb.AppendLine('  c01 -> c10 [dir=none, style=dashed, color="' + MAIN_INK + '", label="main sequence", fontcolor="' + MAIN_INK + '"];');
      Csv.AppendLine('unit,Ca,Ce,I,A,D');
      var Off:= 0;
      var Expected:= 0;
      for var K:= 0 to High(Order) do
      begin
        var U:= Units[Order[K]];
        var IsOff:= U.Distance > OFF_DISTANCE;
        if IsOff then
          Inc(Off);
        var Url:= '';
        if U.Path <> '' then
        begin
          Inc(Expected);
          Url:= Format(', URL="%s"', [RowHref(U.Path, U.Line)]);
        end;
        Sb.AppendLine(Format('  %s [shape=box, style="rounded,filled", fillcolor="%s", label="%s", pos="%s,%s!", ' +
          'tooltip="%s I=%s A=%s D=%s Ca=%d Ce=%d"%s];',
          [NodeId(K), if IsOff then OFF_FILL else ON_FILL, XmlText(U.Name), Coord(U.Instability), Coord(U.Abstractness),
           XmlText(U.Name), Num(U.Instability), Num(U.Abstractness), Num(U.Distance), U.Ca, U.Ce, Url]));
        Csv.AppendLine(Format('%s,%d,%d,%s,%s,%s', [U.Name, U.Ca, U.Ce, Num(U.Instability), Num(U.Abstractness), Num(U.Distance)]));
      end;
      Sb.AppendLine('}');
      TDirectory.CreateDirectory(pOutDir);
      TFile.WriteAllText(TPath.Combine(pOutDir, 'main_sequence_metrics.csv'), Csv.ToString, TEncoding.UTF8);
      var Msgs: TArray<string>;
      Result.Layout:= DotLayout(pArgs.Dot, Sb.ToString, pOutDir, 'main_sequence', Msgs);
      Result.LeftCount:= Length(Order);
      Result.RightCount:= Off;
      Result.ClickTargets:= Result.Layout.Anchors;
      Result.AllClickable:= Result.Layout.Anchors >= Expected;
      Result.Fields:= [TMetaField.Int('Units', Length(Order)), TMetaField.Int('OffSequence', Off),
        TMetaField.Str('Threshold', Num(OFF_DISTANCE)), TMetaField.Int('Hidden', Length(Units) - Length(Order)),
        TMetaField.Int('SourcesMissing', Missing), TMetaField.Int('ClickTargets', Result.Layout.Anchors),
        TMetaField.Int('Expected', Expected), TMetaField.Bool('AllClickable', Result.AllClickable)];
    finally
      Csv.Free;
      Sb.Free;
    end;
  finally
    Cache.Free;
    Pairs.Free;
    ByFile.Free;
    Known.Free;
    Index.Free;
  end;
end;

initialization
  RegisterChartQuestion(MAIN_SEQUENCE_ID, Emit);

end.
