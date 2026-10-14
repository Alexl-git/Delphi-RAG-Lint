unit DRagLint.Charts.Q.TestedBy;

(* The `tested-by` question in-process: a port of charts\src\Emit-TestedBy.ps1 (spec s11;
  the PS output is the reference, P3). Which DUnitX tests reach a method or a type: a BFS
  UP the callers (call_edges -> refs.enclosing_symbol_id, the direction measured intact)
  from the selection -- a type is seeded with every member -- stopping at a test method.
  A test method is the nearest declaration at or after a [Test] / [TestCase] attribute in
  the same file. symbol_facts.covered_by is empty by design and is not read. One index:
  a test project's closure already holds the code under test. An index with no [Test]
  attribute is refused BEFORE the symbol is looked up; zero covering tests is drawn and
  said as "not untested".

  New-DiagramArtifact passes -Cap and not -Depth, so the walk is the emitter's own
  default of 6 hops.

  PS traps closed: `Sort-Object -Unique` over fixtures drops case-insensitive duplicates
  (SortUniqueNames); `Sort-Object { count } -Descending` and `Sort-Object Hop, Name` are
  NOT stable (TPsSort); `-eq` on fixture names is case-insensitive; Measure-Object
  -Maximum is a [double] (MaxHop 1.0) while the no-test branch's literal 0 is an [int];
  the PS's 180-row paging and 60-id chunks only bound one engine call each, so the walk
  here asks one query per frontier (the visited set, hence every count, is the same). *)

interface

const
  /// <summary>The registered question id.</summary>
  TESTED_BY_ID = 'tested-by';

implementation

uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.RegularExpressions,
  DRagLint.Charts.Question, DRagLint.Charts.Index, DRagLint.Charts.Text, DRagLint.Charts.Dot,
  DRagLint.Charts.Sql, DRagLint.Charts.PsSort;

const
  TEST_BORDER = '#0F766E';
  TEST_FILL = '#E2F1EF';
  TEST_HDR = '#0F766E';
  NONE_BORDER = '#9AA3AF';
  NONE_FILL = '#F3F4F6';
  NONE_HDR = '#6B7280';
  FOCUS_BORDER = '#B45309';
  FOCUS_FILL = '#FEF6EC';
  FOCUS_HDR = '#B45309';
  ROW_INK = '#1F2933';
  LINE_INK = '#8A94A6';
  FONT_MONO = 'Consolas';
  FONT_SANS = 'Segoe UI';
  DASHED_STYLE = 'rounded,filled,dashed';
  { Emit-TestedBy -Depth: tests sit several hops up; the bundler never passes it }
  WALK_DEPTH = 6;
  HINT = 'tested-by selects a METHOD or a TYPE';

type
  TCoveringTest = record
    Name, Q, Path, Fixture: string;
    Line, Hop: Integer;
  end;

function IdList(const pIds: TArray<Integer>): string;
begin
  var Parts: TArray<string>;
  SetLength(Parts, Length(pIds));
  for var K:= 0 to High(pIds) do
    Parts[K]:= IntToStr(pIds[K]);
  Result:= string.Join(',', Parts);
end;

{ steps 1-2: refuses an index with no [Test] attribute; the test methods are the nearest
  declaration at or after each attribute }
procedure LoadTestMethods(pIndex: TChartsIndex; pTestIds: TDictionary<Integer, Boolean>);
begin
  { ---- 1. is this a TEST index at all? (pre-check, before the symbol) ---- }
  var Rows:= pIndex.Query('SELECT COUNT(*) AS n FROM refs WHERE kind=''attribute'' AND name_text IN (''Test'',''TestCase'')');
  var NAttr:= 0;
  try
    if Rows.Count > 0 then
      NAttr:= Rows[0].I('n');
  finally
    Rows.Free;
  end;
  if NAttr = 0 then
    raise EChartsQuestion.Create('tested-by: this index carries no DUnitX [Test] attributes, so it is not a test project ' +
      'index. Point it at a test project DB -- the test closure already contains the code ' +
      'under test, so this is a single-DB question.');

  { ---- 2. the test methods: nearest following declaration ---- }
  Rows:= pIndex.Query(
    'SELECT DISTINCT' + sLineBreak +
    '       (SELECT m.id FROM symbols m' + sLineBreak +
    '         WHERE m.file_id = r.file_id AND m.kind IN (''method'',''procedure'',''function'')' + sLineBreak +
    '           AND m.start_line >= r.start_line' + sLineBreak +
    '         ORDER BY m.start_line LIMIT 1) AS mid' + sLineBreak +
    '  FROM refs r' + sLineBreak +
    ' WHERE r.kind = ''attribute'' AND r.name_text IN (''Test'',''TestCase'')');
  try
    for var T in Rows do
      if T.I('mid') <> 0 then
        pTestIds.AddOrSetValue(T.I('mid'), True);
  finally
    Rows.Free;
  end;
end;

function Emit(const pArgs: TQuestionArgs; const pOutDir: string): TChartResult;
var
  Found: Boolean;
  Tests: TArray<TCoveringTest>;
  Rows: TObjectList<TIndexRow>;
begin
  var Index:= TChartsIndex.Create(pArgs.GuardedDb);
  var TestIds:= TDictionary<Integer, Boolean>.Create;
  var Dist:= TDictionary<Integer, Integer>.Create;
  var Hits:= TDictionary<Integer, Integer>.Create;
  try
    { ---- 1-2. a TEST index, and its test methods ---- }
    LoadTestMethods(Index, TestIds);

    { ---- 3. the selection ---- }
    var Sel:= Index.ResolveMemberSelection(pArgs.Target,
      ['method', 'function', 'procedure', 'constructor', 'destructor', 'class', 'interface', 'record', 'type'], False, HINT, Found);
    var IsType:= SameText(Sel.Kind, 'class') or SameText(Sel.Kind, 'interface') or SameText(Sel.Kind, 'record') or SameText(Sel.Kind, 'type');
    var Seeds: TArray<Integer>:= [Sel.Id];
    if IsType then
    begin
      Rows:= Index.AllRows(Format('SELECT id FROM symbols WHERE parent_id = %d', [Sel.Id]), 'id');
      try
        for var M in Rows do
          Seeds:= Seeds + [M.I('id')];
      finally
        Rows.Free;
      end;
    end;

    { ---- 4. BFS over CALLERS, stopping at tests ---- }
    for var S in Seeds do
      Dist.AddOrSetValue(S, 0);
    var Frontier:= Seeds;
    var D:= 1;
    while (D <= WALK_DEPTH) and (Length(Frontier) > 0) do
    begin
      var Next: TArray<Integer>:= [];
      Rows:= Index.Query(
        'SELECT DISTINCT r.enclosing_symbol_id AS caller' + sLineBreak +
        '  FROM call_edges ce JOIN refs r ON r.id = ce.ref_id' + sLineBreak +
        ' WHERE ce.target_symbol_id IN (' + IdList(Frontier) + ') AND r.enclosing_symbol_id IS NOT NULL' + sLineBreak +
        ' ORDER BY r.enclosing_symbol_id');
      try
        for var P in Rows do
        begin
          var Cid:= P.I('caller');
          if Dist.ContainsKey(Cid) then
            Continue;
          Dist.Add(Cid, D);
          { a test method is a leaf of this walk }
          if TestIds.ContainsKey(Cid) then
            Hits.AddOrSetValue(Cid, D)
          else
            Next:= Next + [Cid];
        end;
      finally
        Rows.Free;
      end;
      Frontier:= Next;
      Inc(D);
    end;
    var Reached:= 0;
    for var P in Dist do
      if (P.Key <> 0) and (P.Value > 0) then
        Inc(Reached);

    { ---- 5. describe the covering tests ---- }
    Tests:= [];
    var MaxHop:= 0;
    if Hits.Count > 0 then
    begin
      var Ids:= Hits.Keys.ToArray;
      TArray.Sort<Integer>(Ids);
      Rows:= Index.Query(
        'SELECT s.id AS id, s.name AS nm, s.qualified_name AS q,' + sLineBreak +
        '       s.impl_start_line AS impl, s.start_line AS decl,' + sLineBreak +
        '       f.path AS path, p.name AS fixture' + sLineBreak +
        '  FROM symbols s JOIN files f ON f.id = s.file_id' + sLineBreak +
        '  LEFT JOIN symbols p ON p.id = s.parent_id' + sLineBreak +
        ' WHERE s.id IN (' + IdList(Ids) + ')');
      try
        for var R in Rows do
        begin
          var T:= Default(TCoveringTest);
          T.Name:= R.S('nm');
          T.Q:= R.S('q');
          T.Line:= if R.I('impl') <> 0 then R.I('impl') else R.I('decl');
          T.Path:= R.S('path');
          T.Fixture:= if R.S('fixture') <> '' then R.S('fixture') else UnitNameOf(T.Path);
          T.Hop:= Hits[R.I('id')];
          if T.Hop > MaxHop then
            MaxHop:= T.Hop;
          Tests:= Tests + [T];
        end;
      finally
        Rows.Free;
      end;
    end;
    var FixtureNames: TArray<string>:= [];
    for var T in Tests do
      FixtureNames:= FixtureNames + [T.Fixture];
    var Fixtures:= SortUniqueNames(FixtureNames);
    var TestsOf:= function(const pFixture: string): TArray<TCoveringTest>
      begin
        Result:= [];
        for var T in Tests do
          if SameText(T.Fixture, pFixture) then
            Result:= Result + [T];
      end;

    { ---- 6. dot ---- }
    var NodeId:= 1;
    var Clusters:= 1;
    var Anchored:= 1;
    var FNid:= 'n' + IntToStr(NodeId);
    var Sb:= TStringBuilder.Create;
    try
      Sb.AppendLine('digraph testedby {');
      Sb.AppendLine('  rankdir=LR; bgcolor="transparent"; compound=true;');
      Sb.AppendLine('  nodesep=0.35; ranksep=1.5; splines=spline;');
      Sb.AppendLine(Format('  graph [fontname="%s"];', [FONT_SANS]));
      Sb.AppendLine(Format('  node  [shape=plaintext, fontname="%s", fontsize=14];', [FONT_MONO]));
      Sb.AppendLine(Format('  edge  [fontname="%s", fontsize=11, color="%s", penwidth=1.4, arrowsize=0.7];', [FONT_MONO, LINE_INK]));
      Sb.AppendLine('');

      var FTbl:= TStringBuilder.Create;
      try
        FTbl.Append('<TABLE BORDER="0" CELLBORDER="0" CELLSPACING="3" CELLPADDING="5">');
        FTbl.Append(Format('<TR><TD ALIGN="LEFT" BGCOLOR="%s"><FONT COLOR="#FFFFFF" FACE="%s" POINT-SIZE="14"><B> %s </B></FONT></TD></TR>',
          [FOCUS_HDR, FONT_SANS, XmlText(Sel.Name)]));
        FTbl.Append(Format('<TR><TD PORT="p1" ALIGN="LEFT" HREF="%s" TITLE="%s">', [RowHref(Sel.Path, Sel.FocusLine), XmlText(Sel.QName)]));
        FTbl.Append(Format('<FONT COLOR="%s">%s</FONT>', [ROW_INK, XmlText(UnitNameOf(Sel.Path))]));
        FTbl.Append(Format('  <FONT COLOR="%s" POINT-SIZE="12">:%d</FONT></TD></TR>', [LINE_INK, Sel.FocusLine]));
        AddDisclosureRow(FTbl, Format('%d covering test(s) in %d fixture(s)', [Length(Tests), Length(Fixtures)]), LINE_INK);
        AddDisclosureRow(FTbl, Format('walked callers up to %d hop(s); this index has %d test method(s)', [WALK_DEPTH, TestIds.Count]), LINE_INK);
        AddDisclosureRow(FTbl, 'coverage is COMPUTED from call edges -- symbol_facts.covered_by is empty by design', LINE_INK);
        var EdgelessNote:= TChartsIndex.EdgelessDisclosure(Index.EdgelessFiles);
        if EdgelessNote <> '' then
          AddDisclosureRow(FTbl, EdgelessNote, LINE_INK);
        if Length(Tests) = 0 then
          AddDisclosureRow(FTbl, 'this is NOT "untested": a test reaching it through an unresolved edge is invisible here', LINE_INK);
        FTbl.Append('</TABLE>');
        Sb.AppendLine(Format('  subgraph cluster_focus_%d {', [NodeId]));
        Sb.AppendLine(Format('    style="rounded,filled"; color="%s"; fillcolor="%s"; penwidth=2;', [FOCUS_BORDER, FOCUS_FILL]));
        Sb.AppendLine('    label=""; margin=10;');
        Sb.AppendLine(Format('    %s [label=<%s>];', [FNid, FTbl.ToString]));
        Sb.AppendLine('  }');
      finally
        FTbl.Free;
      end;

      if Length(Tests) = 0 then
      begin
        Inc(NodeId);
        Inc(Clusters);
        var Style:= TClusterStyle.Make(NONE_BORDER, NONE_FILL, NONE_HDR);
        Style.RowInk:= ROW_INK;
        Style.LineInk:= LINE_INK;
        Style.FontSans:= FONT_SANS;
        Style.Style:= DASHED_STYLE;
        AddRowCluster(Sb, 'cluster_none_' + IntToStr(NodeId), 'n' + IntToStr(NodeId), 'no covering test', 'in this index',
          [NoteRow(Format('none of this index''s %d test methods reaches it', [TestIds.Count])),
           NoteRow('absence is not proof: an unresolved or cleared edge looks the same as no call')], Style);
        Sb.AppendLine(Format('  %s:p1 -> n%d [style=dashed];', [FNid, NodeId]));
      end
      else
      begin
        var Ranked:= Copy(Fixtures);
        TPsSort<string>.Sort(Ranked, function(const pL, pR: string): Integer
          begin Result:= Length(TestsOf(pR)) - Length(TestsOf(pL)); end);
        var Style:= TClusterStyle.Make(TEST_BORDER, TEST_FILL, TEST_HDR);
        Style.RowInk:= ROW_INK;
        Style.LineInk:= LINE_INK;
        Style.FontSans:= FONT_SANS;
        for var Fx in Ranked do
        begin
          var Ft:= TestsOf(Fx);
          TPsSort<TCoveringTest>.Sort(Ft, function(const pL, pR: TCoveringTest): Integer
            begin
              Result:= pL.Hop - pR.Hop;
              if Result = 0 then
                Result:= CompareGroupKeys(pL.Name, pR.Name);
            end);
          var Top:= TRanked<TCoveringTest>.TopRanked(Ft, pArgs.Cap, function(pT: TCoveringTest): Integer
            begin Result:= pT.Hop; end);
          var Cells: TArray<TDotRow>:= [];
          for var T in Top.Shown do
          begin
            Inc(Anchored);
            Cells:= Cells + [TDotRow.Anchored(T.Name, T.Line, RowHref(T.Path, T.Line),
              Format('%s -- reaches the selection in %d hop(s)', [T.Q, T.Hop]),
              Format('%d hop%s', [T.Hop, if T.Hop <> 1 then 's' else '']))];
          end;
          var Dt:= DisclosureText(Top.HiddenRows, 0, 'tests');
          if Dt <> '' then
            Cells:= Cells + [NoteRow(Dt)];
          Inc(NodeId);
          Inc(Clusters);
          var Nid:= 'n' + IntToStr(NodeId);
          AddRowCluster(Sb, 'cluster_fx_' + IntToStr(NodeId), Nid, Fx,
            Format('%d test%s', [Length(Ft), if Length(Ft) <> 1 then 's' else '']), Cells, Style);
          Sb.AppendLine(Format('  %s -> %s:p1 [color="%s"];', [Nid, FNid, TEST_BORDER]));
        end;
      end;
      Sb.AppendLine('}');

      var Msgs: TArray<string>;
      Result.Layout:= DotLayout(pArgs.Dot, Sb.ToString, pOutDir, 'testedby_' + TRegEx.Replace(Sel.QName, '[^A-Za-z0-9]', '_'), Msgs);
    finally
      Sb.Free;
    end;
    Result.LeftCount:= Length(Tests);
    Result.RightCount:= Length(Fixtures);
    Result.ClickTargets:= Result.Layout.Anchors;
    Result.AllClickable:= Result.Layout.Anchors >= Anchored;
    Result.Fields:= [TMetaField.Str('Qname', Sel.QName), TMetaField.Int('Tests', Length(Tests)),
      TMetaField.Int('Fixtures', Length(Fixtures)), TMetaField.Int('TestMethods', TestIds.Count),
      TMetaField.Int('Walked', Reached),
      if Length(Tests) > 0 then TMetaField.Real('MaxHop', MaxHop) else TMetaField.Int('MaxHop', 0),
      TMetaField.Int('Clusters', Clusters), TMetaField.Int('ClickTargets', Result.Layout.Anchors),
      TMetaField.Int('Expected', Anchored), TMetaField.Bool('AllClickable', Result.AllClickable)];
  finally
    Hits.Free;
    Dist.Free;
    TestIds.Free;
    Index.Free;
  end;
end;

initialization
  RegisterChartQuestion(TESTED_BY_ID, Emit);

end.
