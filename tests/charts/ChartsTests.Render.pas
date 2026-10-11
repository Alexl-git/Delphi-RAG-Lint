unit ChartsTests.Render;

(* Cases for DRagLint.Charts.Render (spec O1-O3, D7, F4): the text, JSON 'compare/1' and
  HTML renderings of a TCompareResult, and the show-as-page rendering of one report.

  The results are built by hand from texts (no producer, no pwsh): the diff core runs for
  real, so a hunk the renderer prints is a hunk MyersDiff/BuildHunks made. The chart cases
  use tests\charts\fixtures\graph\who-writes-a.dot/-b.dot and who-writes-a.svg.
  PS trap handled: the JSON is read back through a parser, so a key the PowerShell side
  would read as $null (a missing property) fails here as a missing key. *)

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TRenderTests = class
  public
    [Test] procedure TextShowsWarningsFirstThenHeadersThenHunks;
    [Test] procedure TextCountsLineMatchesEdits;
    [Test] procedure TextRefusalShowsWarningsThenError;
    [Test] procedure JsonHasEveryKeyEvenWhenEmpty;
    [Test] procedure JsonHunkLinesCarryOps;
    [Test] procedure HtmlIsSelfContained;
    [Test] procedure HtmlMarksAddedNodeAndEdgeInSvg;
    [Test] procedure HtmlFadesRemovedNodeInOldSvg;
    [Test] procedure HtmlEscapesReportText;
    [Test] procedure ShowAsPageRendersPlainReport;
    [Test] procedure HostileSvgIsDefusedOnBothPages;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.JSON, System.RegularExpressions,
  DRagLint.Charts.Diff, DRagLint.Charts.ReportHeader, DRagLint.Charts.Adapters,
  DRagLint.Charts.Adapter.Graph, DRagLint.Charts.DocInsight, DRagLint.Charts.Compare,
  DRagLint.Charts.Render;

const
  CRLF = #13#10;
  FIXTURE_DIR = 'tests\charts\fixtures';
  FIXTURE_PROBE = 'graph\who-writes-a.svg';
  REPO_ROOT_ENV = 'DRAGLINT_REPO_ROOT';
  LEGACY_HEADER = 'Who writes this field (drag-lint report who-writes) for OPERAT.NAME, asked on 2026-10-06.';
  NEW_HEADER = 'Who writes this field (drag-lint report who-writes) for OPERAT.NAME, asked on 2026-10-10 14:32, engine 1.27.0.';
  NEW_COMMAND = 'COMMAND who-writes -Target "OPERAT.NAME" -Project "C:\P\A.dproj" -Depth 3';
  ROW_ONE = 'Row one';
  ROW_TWO = 'Row two';
  ROW_THREE = 'Row three';
  ROW_FOUR = 'Row four';
  ROW_CHANGED = 'Row two changed';
  TOP_KEY_COUNT: Integer = 12;
  ANCHOR_REACH = 600;
  EDGE_REACH = 200;
  OLD_PATH = 'reports\old.txt';
  INDEX_DB = 'idx\Micronite2027.sqlite';
  ADDED_NODE = 'TfrmBlueprint4.btnAddOperationClick';
  ADDED_EDGE_TITLE = 'nw:p3&#45;&gt;focus';
  CLASS_ADDED = 'class="dl-added"';
  CLASS_REMOVED = 'class="dl-removed"';
  EDGE_ADDED = 'class="edge dl-added"';
  EDGE_REMOVED = 'class="edge dl-removed"';
  HOSTILE_SVG = 'hostile.svg';
  KEEP_TEXT = 'KEEP-NODE';
  RE_HANDLER_ATTR = '\son\w+\s*=';
  PAYLOAD_REACH = 80;
  CSP_META = '<meta http-equiv="Content-Security-Policy" content="default-src ''none''; style-src ''unsafe-inline''; img-src data:">';

{ The fixture folder: $DRAGLINT_REPO_ROOT, else the first ancestor of the current
  directory that holds it. '' when not found. }
function FixtureDir: string;
begin
  var Root:= GetEnvironmentVariable(REPO_ROOT_ENV);
  if (Root <> '') and TFile.Exists(TPath.Combine(TPath.Combine(Root, FIXTURE_DIR), FIXTURE_PROBE)) then
    Exit(TPath.Combine(Root, FIXTURE_DIR));
  var Dir:= GetCurrentDir;
  while Dir <> '' do
  begin
    if TFile.Exists(TPath.Combine(TPath.Combine(Dir, FIXTURE_DIR), FIXTURE_PROBE)) then
      Exit(TPath.Combine(Dir, FIXTURE_DIR));
    var Up:= ExtractFileDir(ExcludeTrailingPathDelimiter(Dir));
    if SameText(Up, Dir) then
      Break;
    Dir:= Up;
  end;
  Result:= '';
end;

function GraphFixture(const pName: string): string;
begin
  var Dir:= FixtureDir;
  Assert.IsTrue(Dir <> '', 'fixture folder ' + FIXTURE_DIR + ' not found from ' + GetCurrentDir);
  Result:= TPath.Combine(TPath.Combine(Dir, 'graph'), pName);
end;

{ A report compare built from two texts: items, edit script and hunks as RunCompare makes them. }
function ReportResult(const pOld, pNew: string): TCompareResult;
begin
  Result:= Default(TCompareResult);
  Result.Format:= cfReportText;
  Result.OldText:= pOld;
  Result.NewText:= pNew;
  if not ParseReportHeader(SplitAnswerLines(pOld), Result.OldHeader) then
    Result.OldHeader:= Default(TReportHeader);
  if not ParseReportHeader(SplitAnswerLines(pNew), Result.NewHeader) then
    Result.NewHeader:= Default(TReportHeader);
  Result.OldItems:= ItemsFor(cfReportText, pOld);
  Result.NewItems:= ItemsFor(cfReportText, pNew);
  Result.Edits:= MyersDiff(Result.OldItems, Result.NewItems);
  Result.Hunks:= BuildHunks(Result.Edits, COMPARE_CONTEXT);
  var Eq, Del, Ins: Integer;
  Result.ExitCode:= if CountEdits(Result.Edits, Eq, Del, Ins) then COMPARE_EXIT_DIFFERENT else COMPARE_EXIT_SAME;
  Result.OldSource:= csFile;
  Result.OldPath:= OLD_PATH;
end;

function OldReport(const pRows: array of string): string;
begin
  Result:= LEGACY_HEADER + CRLF;
  for var Row in pRows do
    Result:= Result + Row + CRLF;
end;

function NewReport(const pRows: array of string): string;
begin
  Result:= NEW_HEADER + CRLF + NEW_COMMAND + CRLF;
  for var Row in pRows do
    Result:= Result + Row + CRLF;
end;

{ A chart compare from the two DOT fixtures; pSvg goes to the NEW side when pNewSvg, else to the OLD. }
function GraphResult(const pOldDot, pNewDot, pSvg: string; pNewSvg: Boolean): TCompareResult;
begin
  Result:= Default(TCompareResult);
  Result.Format:= cfGraph;
  Result.OldText:= TFile.ReadAllText(GraphFixture(pOldDot));
  Result.NewText:= TFile.ReadAllText(GraphFixture(pNewDot));
  Result.OldGraph:= ParseDot(Result.OldText);
  Result.NewGraph:= ParseDot(Result.NewText);
  Result.OldItems:= GraphItems(Result.OldGraph);
  Result.NewItems:= GraphItems(Result.NewGraph);
  Result.Edits:= MyersDiff(Result.OldItems, Result.NewItems);
  Result.Hunks:= BuildHunks(Result.Edits, COMPARE_CONTEXT);
  Result.ExitCode:= COMPARE_EXIT_DIFFERENT;
  if pNewSvg then
    Result.NewSvgPath:= GraphFixture(pSvg)
  else
    Result.OldSvgPath:= GraphFixture(pSvg);
  Result.OldSource:= csTwoFiles;
  Result.OldPath:= GraphFixture(pOldDot);
end;

function ObjOf(const pParent: TJSONObject; const pKey: string): TJSONObject;
begin
  var V:= pParent.GetValue(pKey);
  Assert.IsTrue(V is TJSONObject, pKey + ' is not an object');
  Result:= TJSONObject(V);
end;

function ArrOf(const pParent: TJSONObject; const pKey: string): TJSONArray;
begin
  var V:= pParent.GetValue(pKey);
  Assert.IsTrue(V is TJSONArray, pKey + ' is not an array');
  Result:= TJSONArray(V);
end;

procedure TRenderTests.TextShowsWarningsFirstThenHeadersThenHunks;
begin
  var R:= ReportResult(OldReport([ROW_ONE, ROW_TWO, ROW_THREE]), NewReport([ROW_ONE, ROW_CHANGED, ROW_THREE]));
  R.Warnings:= ['first warning', 'second warning'];
  var T:= RenderCompareText(R);
  var W1:= Pos('WARNING: first warning', T);
  var W2:= Pos('WARNING: second warning', T);
  var OldAt:= Pos('OLD  who-writes OPERAT.NAME  asked 2026-10-06 (no time)  engine (unknown)  source ' + OLD_PATH, T);
  var NewAt:= Pos('NEW  who-writes OPERAT.NAME  asked 2026-10-10 14:32  engine 1.27.0', T);
  var HunkAt:= Pos('@@ -', T);
  Assert.AreEqual(1, W1, 'warnings come first');
  Assert.IsTrue((W2 > W1) and (OldAt > W2), 'OLD after the warnings: ' + T);
  Assert.IsTrue(NewAt > OldAt, 'NEW after OLD: ' + T);
  Assert.IsTrue(HunkAt > NewAt, 'hunks after the headers: ' + T);
  Assert.IsTrue(Pos('result: differences found (exit 1)', T) > HunkAt, 'result line last: ' + T);
end;

procedure TRenderTests.TextCountsLineMatchesEdits;
begin
  var R:= ReportResult(OldReport([ROW_ONE, ROW_TWO, ROW_THREE, ROW_FOUR]), NewReport([ROW_ONE, ROW_CHANGED, ROW_THREE, ROW_FOUR]));
  var Eq, Del, Ins: Integer;
  CountEdits(R.Edits, Eq, Del, Ins);
  var T:= RenderCompareText(R);
  Assert.IsTrue(Pos(Format('--- before (%d lines)', [Length(R.OldItems)]), T) > 0, T);
  Assert.IsTrue(Pos(Format('+++ after (%d lines)', [Length(R.NewItems)]), T) > 0, T);
  Assert.IsTrue(Pos(Format('= %d unchanged, - %d removed, + %d added', [Eq, Del, Ins]), T) > 0, T);
  Assert.IsTrue(Pos('= 3 unchanged, - 1 removed, + 1 added', T) > 0, 'the fixture is one changed row of four: ' + T);
  Assert.IsTrue(Pos(CRLF + '- ' + ROW_TWO, T) > 0, 'removed row: ' + T);
  Assert.IsTrue(Pos(CRLF + '+ ' + ROW_CHANGED, T) > 0, 'added row: ' + T);
  Assert.IsTrue(Pos(CRLF + '= ' + ROW_ONE, T) > 0, 'context row: ' + T);
end;

procedure TRenderTests.TextRefusalShowsWarningsThenError;
begin
  var R:= Default(TCompareResult);
  R.ExitCode:= COMPARE_EXIT_STALE;
  R.Warnings:= ['careful'];
  R.Message:= 'the index is stale';
  var T:= RenderCompareText(R);
  Assert.IsTrue(Pos('WARNING: careful', T) = 1, T);
  Assert.IsTrue(Pos('ERROR: the index is stale', T) > Pos('WARNING: careful', T), T);
  Assert.AreEqual(0, Pos('@@', T), 'no diff on a refusal');
end;

procedure TRenderTests.JsonHasEveryKeyEvenWhenEmpty;
begin
  var R:= Default(TCompareResult);
  R.Format:= cfReportText;
  var Root:= TJSONObject.ParseJSONValue(RenderCompareJson(R));
  try
    Assert.IsTrue(Root is TJSONObject, 'not an object');
    var O:= TJSONObject(Root);
    Assert.AreEqual(TOP_KEY_COUNT, O.Count, 'top-level key count');
    for var Key in ['schema', 'exit_code', 'format', 'warnings', 'old', 'new', 'counts', 'hunks',
      'graph', 'snapshot', 'updated_file', 'message'] do
      Assert.IsNotNull(O.GetValue(Key), 'missing key ' + Key);
    Assert.AreEqual('compare/1', O.GetValue<string>('schema'));
    Assert.AreEqual('report', O.GetValue<string>('format'));
    Assert.AreEqual(0, ArrOf(O, 'warnings').Count);
    Assert.AreEqual(0, ArrOf(O, 'hunks').Count);
    var G:= ObjOf(O, 'graph');
    for var Key in ['nodes_added', 'nodes_removed', 'edges_added', 'edges_removed'] do
      Assert.AreEqual(0, ArrOf(G, Key).Count, Key);
    var Old:= ObjOf(O, 'old');
    for var Key in ['source', 'path', 'form', 'question', 'target', 'asked_on', 'engine', 'command'] do
      Assert.IsNotNull(Old.GetValue(Key), 'missing old.' + Key);
    var New:= ObjOf(O, 'new');
    for var Key in ['asked_on', 'engine', 'command'] do
      Assert.IsNotNull(New.GetValue(Key), 'missing new.' + Key);
    Assert.AreEqual(0, ArrOf(New, 'indexes').Count);
    var C:= ObjOf(O, 'counts');
    for var Key in ['equal', 'removed', 'added'] do
      Assert.IsNotNull(C.GetValue(Key), 'missing counts.' + Key);
  finally
    Root.Free;
  end;
end;

procedure TRenderTests.JsonHunkLinesCarryOps;
begin
  var R:= ReportResult(OldReport([ROW_ONE, ROW_TWO, ROW_THREE]), NewReport([ROW_ONE, ROW_CHANGED, ROW_THREE]));
  R.Warnings:= ['w'];
  var Fact: TIndexFact;
  Fact.Db:= INDEX_DB;
  Fact.Stale:= False;
  Fact.StaleFiles:= 0;
  Fact.IndexedAt:= '2026-10-10 09:01';
  R.NewIndexes:= [Fact];
  var Root:= TJSONObject.ParseJSONValue(RenderCompareJson(R));
  try
    var O:= TJSONObject(Root);
    Assert.AreEqual(1, O.GetValue<Integer>('exit_code'));
    Assert.AreEqual('w', TJSONString(ArrOf(O, 'warnings').Items[0]).Value);
    var Old:= ObjOf(O, 'old');
    Assert.AreEqual('file', Old.GetValue<string>('source'));
    Assert.AreEqual(OLD_PATH, Old.GetValue<string>('path'));
    Assert.AreEqual('2026-10-06', Old.GetValue<string>('asked_on'));
    Assert.AreEqual('who-writes', Old.GetValue<string>('question'));
    var New:= ObjOf(O, 'new');
    Assert.AreEqual('1.27.0', New.GetValue<string>('engine'));
    Assert.AreEqual('who-writes -Target "OPERAT.NAME" -Project "C:\P\A.dproj" -Depth 3', New.GetValue<string>('command'));
    var Ix:= TJSONObject(ArrOf(New, 'indexes').Items[0]);
    Assert.AreEqual('2026-10-10 09:01', Ix.GetValue<string>('indexed_at'));
    Assert.IsFalse(Ix.GetValue<Boolean>('stale'));
    var C:= ObjOf(O, 'counts');
    Assert.AreEqual(1, C.GetValue<Integer>('removed'));
    Assert.AreEqual(1, C.GetValue<Integer>('added'));
    var Hunks:= ArrOf(O, 'hunks');
    Assert.AreEqual(1, Hunks.Count);
    var H:= TJSONObject(Hunks.Items[0]);
    Assert.AreEqual(R.Hunks[0].OldStart, H.GetValue<Integer>('old_start'));
    Assert.AreEqual(R.Hunks[0].NewCount, H.GetValue<Integer>('new_count'));
    var Lines:= ArrOf(H, 'lines');
    var Ops:= TStringBuilder.Create;
    try
    for var I:= 0 to Lines.Count - 1 do
    begin
      var L:= TJSONObject(Lines.Items[I]);
      var Op:= L.GetValue<string>('op');
      Ops.Append(Op);
      if Op = '-' then
        Assert.AreEqual(ROW_TWO, L.GetValue<string>('old'));
      if Op = '+' then
        Assert.AreEqual(ROW_CHANGED, L.GetValue<string>('new'));
      if Op = '=' then
        Assert.AreEqual(L.GetValue<string>('old'), L.GetValue<string>('new'));
    end;
    Assert.AreEqual('=-+=', Ops.ToString, 'one equal, the removed row, the added row, one equal');
    finally
      Ops.Free;
    end;
  finally
    Root.Free;
  end;
end;

procedure TRenderTests.HtmlIsSelfContained;
begin
  var R:= ReportResult(OldReport([ROW_ONE, ROW_TWO]), NewReport([ROW_ONE, ROW_CHANGED]));
  R.Warnings:= ['one warning'];
  var H:= RenderCompareHtml(R);
  Assert.AreEqual(0, Pos('http://', H), 'no network reference');
  Assert.AreEqual(0, Pos('https://', H), 'no network reference');
  Assert.AreEqual(0, Pos('<script', LowerCase(H)), 'no script');
  Assert.IsTrue(Pos('prefers-color-scheme: dark', H) > 0, 'dark theme');
  Assert.IsTrue(Pos('<table class="sxs">', H) > 0, 'side-by-side table');
  Assert.IsTrue(Pos('<td class="old del">' + ROW_TWO + '</td>', H) > 0, 'removed row highlighted');
  Assert.IsTrue(Pos('<td class="new ins">' + ROW_CHANGED + '</td>', H) > 0, 'added row highlighted');
  Assert.IsTrue(Pos('one warning', H) > 0, 'warning shown');
  Assert.AreEqual(0, Pos('{{', H), 'every template marker is filled');
end;

procedure TRenderTests.HtmlMarksAddedNodeAndEdgeInSvg;
begin
  // old = b (no btnAddOperationClick), new = a: the node and its edge nw:p3 -> focus are ADDED.
  var R:= GraphResult('who-writes-b.dot', 'who-writes-a.dot', 'who-writes-a.svg', True);
  var H:= RenderCompareHtml(R);
  Assert.AreEqual(0, Pos('http://', H), 'the inlined SVG carries no xmlns URL');
  Assert.AreEqual(0, Pos('<?xml', H), 'prolog stripped');
  Assert.AreEqual(0, Pos('<!DOCTYPE svg', H), 'svg doctype stripped');
  Assert.IsTrue(Pos('<section class="chart">', H) > 0, 'chart section');
  Assert.IsTrue(Pos('.dl-added text{font-weight:bold}', H) > 0, 'marking CSS');
  var Anchor:= Pos(CLASS_ADDED, H);
  Assert.IsTrue(Anchor > 0, 'a node anchor is marked');
  var NodeText:= Pos(ADDED_NODE, H);
  Assert.IsTrue((NodeText > Anchor) and (NodeText - Anchor < ANCHOR_REACH), 'the marked anchor is the added node: ' + Copy(H, Anchor, ANCHOR_REACH));
  var EdgeAt:= Pos(EDGE_ADDED, H);
  Assert.IsTrue(EdgeAt > 0, 'an edge group is marked');
  Assert.IsTrue(Pos('<title>' + ADDED_EDGE_TITLE + '</title>', Copy(H, EdgeAt, EDGE_REACH)) > 0, 'the marked edge is nw:p3->focus: ' + Copy(H, EdgeAt, EDGE_REACH));
  // exactly one node and one edge are added, so exactly one of each marking is in the NEW chart
  var Count:= 0;
  var From:= 1;
  while True do
  begin
    var At:= Pos(EDGE_ADDED, H, From);
    if At = 0 then Break;
    Inc(Count);
    From:= At + 1;
  end;
  Assert.AreEqual(1, Count, 'one added edge');
  Assert.IsTrue(Pos('Edges added (1)', H) > 0, 'text list of changes: edges');
  Assert.IsTrue(Pos('Nodes added (1)', H) > 0, 'text list of changes: nodes');
end;

procedure TRenderTests.HtmlFadesRemovedNodeInOldSvg;
begin
  // old = a with its SVG, new = b: btnAddOperationClick and nw:p3 -> focus are REMOVED.
  var R:= GraphResult('who-writes-a.dot', 'who-writes-b.dot', 'who-writes-a.svg', False);
  var H:= RenderCompareHtml(R);
  var Det:= Pos('<details>', H);
  Assert.IsTrue(Det > 0, 'old chart in a details element');
  Assert.IsTrue(Pos('Before (removed shown faded)', H) > Det, 'summary text');
  Assert.IsTrue(Pos(CLASS_REMOVED, H) > Det, 'removed anchor faded inside the details: ');
  Assert.IsTrue(Pos(EDGE_REMOVED, H) > Det, 'removed edge faded');
  Assert.IsTrue(Pos('.dl-removed{opacity:.35}', H) > 0, 'fade CSS');
  Assert.AreEqual(0, Pos(CLASS_ADDED, H), 'no new svg, nothing added is drawn: ');
  Assert.IsTrue(Pos('Nodes removed (1)', H) > 0, 'text list of changes');
end;

procedure TRenderTests.HtmlEscapesReportText;
begin
  var R:= ReportResult(OldReport(['a < b & c']), NewReport(['x > "y"']));
  var H:= RenderCompareHtml(R);
  Assert.IsTrue(Pos('a &lt; b &amp; c', H) > 0, 'old row escaped');
  Assert.IsTrue(Pos('x &gt; &quot;y&quot;', H) > 0, 'new row escaped');
  Assert.AreEqual(0, Pos('a < b', H), 'raw < never reaches the page');
end;

procedure TRenderTests.ShowAsPageRendersPlainReport;
begin
  var H:= RenderReportHtml('A saved report', NewReport(['Row <one>', ROW_TWO]), cfReportText, '');
  Assert.IsTrue(Pos('<title>A saved report</title>', H) > 0, 'title');
  Assert.IsTrue(Pos('<pre class="report">', H) > 0, 'report block');
  Assert.IsTrue(Pos('Row &lt;one&gt;', H) > 0, 'text escaped');
  Assert.IsTrue(Pos(ROW_TWO, H) > 0, 'second row');
  Assert.AreEqual(0, Pos('<script', LowerCase(H)), 'no script');
  Assert.IsTrue(Pos('prefers-color-scheme: dark', H) > 0, 'same template as compare');
  var G:= RenderReportHtml('A chart', TFile.ReadAllText(GraphFixture('who-writes-a.dot')), cfGraph, GraphFixture('who-writes-a.svg'));
  Assert.IsTrue(Pos('<section class="chart">', G) > 0, 'graph page carries the chart');
  Assert.AreEqual(0, Pos(CLASS_ADDED, G), 'a plain chart is not marked');
  var C:= RenderReportHtml('A csv', 'a,b' + CRLF + '"1,5","x ""q"""' + CRLF, cfFormsCsv, '');
  Assert.IsTrue(Pos('<table class="csv">', C) > 0, 'csv table');
  Assert.IsTrue(Pos('<td>1,5</td>', C) > 0, 'quoted comma stays one cell');
end;

procedure TRenderTests.HostileSvgIsDefusedOnBothPages;
begin
  // hostile.svg: script elements, on* handlers, javascript: links, a foreignObject, markup
  // after </svg>, and surrogate entities (&#xD800;) in the titles MarkSvg decodes.
  var R:= GraphResult('who-writes-a.dot', 'who-writes-b.dot', HOSTILE_SVG, True);
  var Pages: TArray<string>:= [RenderCompareHtml(R),
    RenderReportHtml('A chart', TFile.ReadAllText(GraphFixture('who-writes-a.dot')), cfGraph, GraphFixture(HOSTILE_SVG))];
  for var H in Pages do
  begin
    var L:= LowerCase(H);
    Assert.IsTrue(Pos(CSP_META, H) > 0, 'CSP meta in the head');
    Assert.IsTrue(Pos(KEEP_TEXT, H) > 0, 'the chart itself is kept');
    Assert.AreEqual(0, Pos('<script', L), 'no script element');
    Assert.AreEqual(0, Pos('<foreignobject', L), 'no foreignObject');
    Assert.AreEqual(0, Pos('javascript:', L), 'no javascript: URL');
    Assert.AreEqual(0, Pos('alert(', L), 'no payload survives: ' + Copy(H, Pos('alert(', L) - PAYLOAD_REACH, 2 * PAYLOAD_REACH));
    var Handler:= TRegEx.Match(H, RE_HANDLER_ATTR, [roIgnoreCase]);
    Assert.IsFalse(Handler.Success, 'no on* handler attribute: ' + Handler.Value);
    Assert.AreEqual(0, Pos('<img', L), 'nothing after </svg>');
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TRenderTests);

end.
