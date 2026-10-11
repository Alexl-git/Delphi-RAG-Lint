unit ChartsTests.Adapters;

(* Cases for DRagLint.Charts.Adapter.FormsCsv, DRagLint.Charts.Adapter.Graph and the
  format dispatcher DRagLint.Charts.Adapters (spec 6a, D5-D8): a forms CSV and a chart
  graph.dot are compared as SETS keyed by identity -- never by row order, drawing order
  or a :line suffix.

  Fixtures live in tests\charts\fixtures\forms (a.csv, b.csv) and \graph
  (who-writes-a.dot / -b.dot / -a.svg) and stay 7-bit ASCII. b.csv is a.csv with the
  rows reordered, one Handler changed, one row removed, one row added (its Notes cell
  is "Click ""Save"", then wait"). who-writes-b.dot is who-writes-a.dot with one
  routine row (and its edge) removed, one added, the :line suffix of one changed, and
  two rows swapped.

  PS trap handled: the item keys compare ORDINALLY; see the units' headers. *)

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAdaptersTests = class
  public
    [Test] procedure FormsHeaderIsDetected;
    [Test] procedure ReorderedRowsAreNoChange;
    [Test] procedure ChangedHandlerIsDeletePlusInsert;
    [Test] procedure AddedAndRemovedRowsAreCounted;
    [Test] procedure ContentColumnChangeIsDeletePlusInsert;
    [Test] procedure VolatileColumnChangesAreNoChange;
    [Test] procedure QuotedCellsWithCommasAndQuotes;
    [Test] procedure DotNodesAreKeyedByIdentityNotLine;
    [Test] procedure DotRemovedAndAddedNodesAndEdges;
    [Test] procedure DotReorderIsNoChange;
    [Test] procedure DotQuotedIdsParseNodesAndEdges;
    [Test] procedure DotSurrogateEntityDoesNotRaise;
    [Test] procedure BundleFolderResolvesGraphDotAndSvg;
    [Test] procedure DetectFormatByContentAndExtension;
    [Test] procedure DifferentFormatsAreRefusedByName;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Generics.Collections,
  DRagLint.Charts.Diff, DRagLint.Charts.Adapter.FormsCsv, DRagLint.Charts.Adapter.Graph,
  DRagLint.Charts.Adapters;

const
  CRLF = #13#10;
  FIXTURE_DIR = 'tests\charts\fixtures';
  FIXTURE_PROBE = 'forms\a.csv';
  REPO_ROOT_ENV = 'DRAGLINT_REPO_ROOT';
  DATA_ROWS_A: Integer = 5;
  DATA_ROWS_B: Integer = 5;
  OLD_HANDLER = 'TfrmMAIN.btnCustomersClick';
  NEW_HANDLER = 'TfrmMAIN.btnCustomersOpenClick';
  QUOTED_NOTE = '"Click ""Save"", then wait"';
  NODE_REMOVED = 'N TfrmBlueprint4.btnAddOperationClick';
  NODE_ADDED = 'N TfrmBlueprint4.btnBrandNewClick';
  QUOTED_DOT = 'digraph G {' + CRLF +
    '  "nw box" [label=<<TABLE><TR><TD PORT="p1" HREF="h" TITLE="X.Y -- 1 site"><FONT>X.Y</FONT></TD></TR></TABLE>>];' + CRLF +
    '  "A" -> "B";' + CRLF +
    '  "nw box":"p1" -> "B" [color=red];' + CRLF +
    '  B -> "C D":p2;' + CRLF +
    '}' + CRLF;
  SURROGATE_DOT = 'digraph G {' + CRLF +
    '  nw [label=<<TABLE><TR><TD PORT="p1" HREF="h&#xD800;" TITLE="&#xD800;&#56320;&#x110000; -- t"><FONT>A</FONT></TD></TR></TABLE>>];' + CRLF +
    '  nw:p1 -> b;' + CRLF +
    '}' + CRLF;
  NODE_LINE_CHANGED = 'N TfrmBlueprint4.btnApplyActiveFieldClick';
  NODE_FOCUS = 'N Blueprint4.TfrmBlueprint4.FNoRecursion';
  EDGE_PREFIX_NW = '  nw:p';
  GRAPH_NODES_A: Integer = 21;
  GRAPH_EDGES_A: Integer = 20;
  UNCHANGED_ROWS: Integer = 3;
  ONE: Integer = 1;
  TWO: Integer = 2;
  QUOTED_NODES: Integer = 4;

{ The fixture folder: $DRAGLINT_REPO_ROOT, else the first ancestor of the current
  directory that holds it (the ReportTextTests convention). '' when not found. }
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

function Fixture(const pSub, pName: string): string;
begin
  var Dir:= FixtureDir;
  Assert.IsTrue(Dir <> '', 'fixture folder ' + FIXTURE_DIR + ' not found from ' + GetCurrentDir);
  Result:= TPath.Combine(TPath.Combine(Dir, pSub), pName);
end;

function ReadFixture(const pSub, pName: string): string;
begin
  Result:= TFile.ReadAllText(Fixture(pSub, pName));
end;

(* Edit counts between two item lists. *)
procedure Counts(const pOld, pNew: TArray<TDiffItem>; out pEqual, pDeleted, pInserted: Integer);
begin
  CountEdits(MyersDiff(pOld, pNew), pEqual, pDeleted, pInserted);
end;

(* The Text of every deleted (pDeleted True) or inserted item. *)
function ChangedTexts(const pOld, pNew: TArray<TDiffItem>; pDeleted: Boolean): TArray<string>;
begin
  var Edits:= MyersDiff(pOld, pNew);
  var Found:= TList<string>.Create;
  try
    for var E in Edits do
      if pDeleted and (E.Op = doDelete) then Found.Add(pOld[E.OldIndex].Text)
      else if (not pDeleted) and (E.Op = doInsert) then Found.Add(pNew[E.NewIndex].Text);
    Result:= Found.ToArray;
  finally
    Found.Free;
  end;
end;

function Contains(const pTexts: TArray<string>; const pText: string): Boolean;
begin
  Result:= False;
  for var T in pTexts do
    if (string.CompareOrdinal(T, pText) = 0) then Exit(True);
end;

function CountWithPrefix(const pTexts: TArray<string>; const pPrefix: string): Integer;
begin
  Result:= 0;
  for var T in pTexts do
    if T.StartsWith(pPrefix, False) then Inc(Result);
end;

function GraphItemsOf(const pDot: string): TArray<TDiffItem>;
begin
  Result:= GraphItems(ParseDot(pDot));
end;

procedure TAdaptersTests.FormsHeaderIsDetected;
begin
  var A:= ReadFixture('forms', 'a.csv');
  Assert.IsTrue(IsFormsCsv(A), 'a.csv');
  Assert.IsTrue(IsFormsCsv(ReadFixture('forms', 'b.csv')), 'b.csv');
  Assert.IsTrue(IsFormsCsv(#$FEFF + A), 'a BOM in front');
  Assert.IsTrue(IsFormsCsv(StringReplace(A, CRLF, #10, [rfReplaceAll])), 'LF line ends');
  Assert.IsFalse(IsFormsCsv(''), 'empty');
  Assert.IsFalse(IsFormsCsv('Form,Unit,Handler' + CRLF + 'x,y,z'), 'another CSV');
  Assert.IsFalse(IsFormsCsv(LowerCase(A)), 'the header is compared ordinally');
  Assert.IsFalse(IsFormsCsv('digraph g {}'), 'a DOT');
  Assert.AreEqual(FORMS_CSV_HEADER, Copy(A, 1, Length(FORMS_CSV_HEADER)), 'the fixture carries the real header');
end;

procedure TAdaptersTests.ReorderedRowsAreNoChange;
begin
  var Rows:= ReadFixture('forms', 'a.csv').Split([CRLF], TStringSplitOptions.ExcludeEmpty);
  var Reordered:= TStringBuilder.Create;
  try
    Reordered.Append(Rows[0]).Append(CRLF);
    for var I:= High(Rows) downto 1 do
      Reordered.Append(Rows[I]).Append(CRLF);
    var Eq, Del, Ins: Integer;
    Counts(FormsCsvItems(ReadFixture('forms', 'a.csv')), FormsCsvItems(Reordered.ToString), Eq, Del, Ins);
    Assert.AreEqual(0, Del, 'deleted');
    Assert.AreEqual(0, Ins, 'inserted');
    Assert.AreEqual(DATA_ROWS_A, Eq, 'every data row is equal; the footer is not an item');
  finally
    Reordered.Free;
  end;
end;

procedure TAdaptersTests.ChangedHandlerIsDeletePlusInsert;
begin
  var A:= ReadFixture('forms', 'a.csv');
  var Changed:= StringReplace(A, OLD_HANDLER, NEW_HANDLER, []);
  Assert.AreNotEqual(A, Changed, 'the fixture holds the handler to change');
  var Eq, Del, Ins: Integer;
  Counts(FormsCsvItems(A), FormsCsvItems(Changed), Eq, Del, Ins);
  Assert.AreEqual(ONE, Del, 'deleted');
  Assert.AreEqual(ONE, Ins, 'inserted');
  Assert.AreEqual(DATA_ROWS_A - ONE, Eq, 'equal');
  Assert.IsTrue(ChangedTexts(FormsCsvItems(A), FormsCsvItems(Changed), True)[0].Contains(OLD_HANDLER), 'the old row is the deleted one');
end;

procedure TAdaptersTests.AddedAndRemovedRowsAreCounted;
begin
  // a -> b: row 2 removed, row 6 added, row 3's Handler changed (delete + insert); the
  // main, reports and settings rows are equal however they were reordered.
  var Eq, Del, Ins: Integer;
  Counts(FormsCsvItems(ReadFixture('forms', 'a.csv')), FormsCsvItems(ReadFixture('forms', 'b.csv')), Eq, Del, Ins);
  Assert.AreEqual(UNCHANGED_ROWS, Eq, 'equal');
  Assert.AreEqual(TWO, Del, 'deleted: the removed row and the old-handler row');
  Assert.AreEqual(TWO, Ins, 'inserted: the added row and the new-handler row');
end;

procedure TAdaptersTests.ContentColumnChangeIsDeletePlusInsert;
  procedure ExpectOneChange(const pFrom, pTo: string);
  begin
    var A:= ReadFixture('forms', 'a.csv');
    var Changed:= StringReplace(A, pFrom, pTo, []);
    Assert.AreNotEqual(A, Changed, 'the fixture holds ' + pFrom);
    var Eq, Del, Ins: Integer;
    Counts(FormsCsvItems(A), FormsCsvItems(Changed), Eq, Del, Ins);
    Assert.AreEqual(ONE, Del, 'deleted: ' + pFrom);
    Assert.AreEqual(ONE, Ins, 'inserted: ' + pFrom);
    Assert.AreEqual(DATA_ROWS_A - ONE, Eq, 'equal: ' + pFrom);
  end;
begin
  // Modal, Before you start and Control type, each on one row
  ExpectOneChange('"TfrmMAIN.btnOrdersClick","TfrmMAIN","modal"', '"TfrmMAIN.btnOrdersClick","TfrmMAIN",""');
  ExpectOneChange('"Pick a customer first"', '"Pick a vendor first"');
  ExpectOneChange('"TdxBarButton","TfrmMAIN.btnCustomersClick"', '"TButton","TfrmMAIN.btnCustomersClick"');
end;

procedure TAdaptersTests.VolatileColumnChangesAreNoChange;
begin
  var A:= ReadFixture('forms', 'a.csv');
  // Notes of the Main row, the '#' of the Orders row, the Tester result of the Main row
  var Changed:= StringReplace(A, 'main form of the application', 'a tester wrote this', []);
  Changed:= StringReplace(Changed, CRLF + '2,"TfrmOrders"', CRLF + '9,"TfrmOrders"', []);
  Changed:= StringReplace(Changed, '"root",,"a tester', '"root","passed","a tester', []);
  Assert.IsTrue(Changed.Contains('"passed"') and Changed.Contains('9,"TfrmOrders"'), 'the fixture was edited');
  var Eq, Del, Ins: Integer;
  Counts(FormsCsvItems(A), FormsCsvItems(Changed), Eq, Del, Ins);
  Assert.AreEqual(0, Del, 'deleted');
  Assert.AreEqual(0, Ins, 'inserted');
  Assert.AreEqual(DATA_ROWS_A, Eq, 'equal');
end;

procedure TAdaptersTests.QuotedCellsWithCommasAndQuotes;
begin
  var Items:= FormsCsvItems(ReadFixture('forms', 'b.csv'));
  Assert.AreEqual(DATA_ROWS_B, Integer(Length(Items)), 'one row stays one item');
  var Help: TDiffItem;
  var Found:= False;
  for var Item in Items do
    if Item.Key.StartsWith('TfrmHelp|', False) then
    begin
      Help:= Item;
      Found:= True;
    end;
  Assert.IsTrue(Found, 'the TfrmHelp row is an item');
  Assert.IsTrue(Help.Text.EndsWith(QUOTED_NOTE, False), 'Text is the raw row, quotes and all: ' + Help.Text);
  Assert.AreEqual('TfrmHelp|Help.pas|Help > About|About|TfrmMAIN.miAboutClick|TMenuItem|TfrmMAIN|||0|traced', Help.Key);
  // a quoted cell holding a line break is still one row of one item
  var Multi:= FORMS_CSV_HEADER + CRLF +
    '1,"TfrmA","A.pas","open","","","TfrmA.H","","","",0,"traced",,"line one' + CRLF + 'line two, with a comma"' + CRLF;
  var MultiItems:= FormsCsvItems(Multi);
  Assert.AreEqual(ONE, Integer(Length(MultiItems)), 'a quoted line break does not split the row');
  Assert.AreEqual('TfrmA|A.pas|open||TfrmA.H|||||0|traced', MultiItems[0].Key);
  // ordinal: two forms differing only by case are two items
  var Cased:= FormsCsvItems(FORMS_CSV_HEADER + CRLF + '1,"TfrmA","A.pas","o","","","H"' + CRLF + '2,"tfrma","A.pas","o","","","H"' + CRLF);
  Assert.AreEqual(TWO, Integer(Length(Cased)), 'case matters');
end;

procedure TAdaptersTests.DotNodesAreKeyedByIdentityNotLine;
begin
  var DotA:= ReadFixture('graph', 'who-writes-a.dot');
  var Model:= ParseDot(DotA);
  Assert.AreEqual(GRAPH_NODES_A, Integer(Length(Model.Nodes)), 'nodes: 20 routines + the focus; "+6 more" and header cells are not nodes');
  Assert.AreEqual(GRAPH_EDGES_A, Integer(Length(Model.Edges)), 'edges');
  Assert.AreEqual(GRAPH_EDGES_A, Integer(Length(Model.PortToId)), 'ports');
  var ItemsA:= GraphItems(Model);
  var ItemsB:= GraphItemsOf(ReadFixture('graph', 'who-writes-b.dot'));
  var TextsA: TArray<string>;
  SetLength(TextsA, Length(ItemsA));
  for var I:= 0 to High(ItemsA) do
    TextsA[I]:= ItemsA[I].Text;
  Assert.IsTrue(Contains(TextsA, NODE_FOCUS), 'the focus node is identified by the part of its TITLE before " -- "');
  Assert.IsTrue(Contains(TextsA, NODE_LINE_CHANGED), 'a routine is identified without its :line');
  // b changes this row's :line suffix and swaps two rows: neither is a change
  Assert.IsFalse(Contains(ChangedTexts(ItemsA, ItemsB, True), NODE_LINE_CHANGED), 'not deleted');
  Assert.IsFalse(Contains(ChangedTexts(ItemsA, ItemsB, False), NODE_LINE_CHANGED), 'not inserted');
  Assert.AreEqual(ItemsA[0].Key, ItemsA[0].Text, 'Key = Text');
end;

procedure TAdaptersTests.DotRemovedAndAddedNodesAndEdges;
begin
  var ItemsA:= GraphItemsOf(ReadFixture('graph', 'who-writes-a.dot'));
  var ItemsB:= GraphItemsOf(ReadFixture('graph', 'who-writes-b.dot'));
  var Eq, Del, Ins: Integer;
  Counts(ItemsA, ItemsB, Eq, Del, Ins);
  Assert.AreEqual(TWO, Del, 'deleted: one node + one edge');
  Assert.AreEqual(TWO, Ins, 'inserted: one node + one edge');
  var Deleted:= ChangedTexts(ItemsA, ItemsB, True);
  var Inserted:= ChangedTexts(ItemsA, ItemsB, False);
  Assert.AreEqual(ONE, CountWithPrefix(Deleted, 'N '), 'one node removed');
  Assert.AreEqual(ONE, CountWithPrefix(Deleted, 'E '), 'one edge removed');
  Assert.AreEqual(ONE, CountWithPrefix(Inserted, 'N '), 'one node added');
  Assert.AreEqual(ONE, CountWithPrefix(Inserted, 'E '), 'one edge added');
  Assert.IsTrue(Contains(Deleted, NODE_REMOVED), 'the removed routine');
  Assert.IsTrue(Contains(Deleted, 'E TfrmBlueprint4.btnAddOperationClick -> Blueprint4.TfrmBlueprint4.FNoRecursion'), 'its edge, resolved through the port map');
  Assert.IsTrue(Contains(Inserted, NODE_ADDED), 'the added routine');
end;

procedure TAdaptersTests.DotQuotedIdsParseNodesAndEdges;
begin
  // quoted ids are DOT's other id form: the quotes are not part of the identity
  var Model:= ParseDot(QUOTED_DOT);
  var Texts: TArray<string>;
  for var Item in GraphItems(Model) do
    Texts:= Texts + [Item.Text];
  Assert.IsTrue(Contains(Texts, 'N X.Y'), 'quoted HTML-label node: ' + string.Join('|', Texts));
  Assert.IsTrue(Contains(Texts, 'E A -> B'), 'quoted ends: ' + string.Join('|', Texts));
  Assert.IsTrue(Contains(Texts, 'E X.Y -> B'), 'quoted id and quoted port resolve through the port map: ' + string.Join('|', Texts));
  Assert.IsTrue(Contains(Texts, 'E B -> C D'), 'bare to quoted with a port: ' + string.Join('|', Texts));
  Assert.AreEqual(QUOTED_NODES, Integer(Length(Model.Nodes)), 'X.Y, A, B, C D');
end;

procedure TAdaptersTests.DotSurrogateEntityDoesNotRaise;
begin
  // a lone surrogate (or a code point past U+10FFFF) is not a character: kept as written, never raised
  var Model:= ParseDot(SURROGATE_DOT);
  Assert.AreEqual(TWO, Integer(Length(Model.Nodes)), 'the cell node and b');
  Assert.AreEqual('&#xD800;&#56320;&#x110000;', Model.Nodes[0].Id, 'the entities stay as written');
  Assert.AreEqual('h&#xD800;', Model.Nodes[0].Href, 'href entity stays as written');
end;

procedure TAdaptersTests.DotReorderIsNoChange;
begin
  var DotA:= ReadFixture('graph', 'who-writes-a.dot');
  var Lines:= DotA.Split([CRLF], TStringSplitOptions.None);
  var EdgeAt:= TList<Integer>.Create;
  try
    for var I:= 0 to High(Lines) do
      if Lines[I].StartsWith(EDGE_PREFIX_NW, False) then EdgeAt.Add(I);
    Assert.IsTrue(EdgeAt.Count > ONE, 'the fixture has edges to reorder');
    var Reordered:= Copy(Lines);
    for var J:= 0 to EdgeAt.Count - 1 do
      Reordered[EdgeAt[J]]:= Lines[EdgeAt[EdgeAt.Count - 1 - J]];
    var Eq, Del, Ins: Integer;
    Counts(GraphItemsOf(DotA), GraphItemsOf(string.Join(CRLF, Reordered)), Eq, Del, Ins);
    Assert.AreEqual(0, Del, 'deleted');
    Assert.AreEqual(0, Ins, 'inserted');
    Assert.AreEqual(GRAPH_NODES_A + GRAPH_EDGES_A, Eq, 'every node and edge is equal');
  finally
    EdgeAt.Free;
  end;
end;

procedure TAdaptersTests.BundleFolderResolvesGraphDotAndSvg;
begin
  var Dot, Svg: string;
  var Dir:= TPath.Combine(TPath.GetTempPath, 'ChartsTests.Adapters-' + TPath.GetGUIDFileName);
  TDirectory.CreateDirectory(Dir);
  try
    Assert.IsFalse(LoadGraphSource(Dir, Dot, Svg), 'an empty folder holds no chart');
    Assert.AreEqual('', Dot, 'no dot text');
    Assert.AreEqual('', Svg, 'no svg');
    TFile.Copy(Fixture('graph', 'who-writes-a.dot'), TPath.Combine(Dir, 'graph.dot'));
    Assert.IsTrue(LoadGraphSource(Dir, Dot, Svg), 'folder with graph.dot');
    Assert.IsTrue(Dot.StartsWith('digraph', False), 'the dot text was read');
    Assert.AreEqual('', Svg, 'no graph.svg yet');
    TFile.Copy(Fixture('graph', 'who-writes-a.svg'), TPath.Combine(Dir, 'graph.svg'));
    Assert.IsTrue(LoadGraphSource(Dir, Dot, Svg), 'folder with graph.dot + graph.svg');
    Assert.AreEqual(TPath.Combine(Dir, 'graph.svg'), Svg, 'the bundle svg');
  finally
    TDirectory.Delete(Dir, True);
  end;
  Assert.IsTrue(LoadGraphSource(Fixture('graph', 'who-writes-a.dot'), Dot, Svg), 'a .dot file');
  Assert.AreEqual(Fixture('graph', 'who-writes-a.svg'), Svg, 'its sibling svg');
  Assert.IsTrue(LoadGraphSource(Fixture('graph', 'who-writes-b.dot'), Dot, Svg), 'a .dot file without an svg');
  Assert.AreEqual('', Svg, 'no sibling svg');
  Assert.IsFalse(LoadGraphSource(Fixture('graph', 'nope.dot'), Dot, Svg), 'a missing file');
end;

procedure TAdaptersTests.DetectFormatByContentAndExtension;
begin
  Assert.AreEqual(Ord(cfFormsCsv), Ord(DetectFormat(ReadFixture('forms', 'a.csv'), False)), 'csv text');
  Assert.AreEqual(Ord(cfGraph), Ord(DetectFormat(ReadFixture('graph', 'who-writes-a.dot'), False)), 'dot text');
  Assert.AreEqual(Ord(cfGraph), Ord(DetectFormat(CRLF + '  DiGraph g {}', False)), 'dot text, blank lead and any case');
  Assert.AreEqual(Ord(cfReportText), Ord(DetectFormat('Totals: 3 sites' + CRLF, False)), 'report text');
  Assert.AreEqual(Ord(cfReportText), Ord(DetectFormat('digraphy is a word', False)), 'a word that merely starts like digraph');
  Assert.AreEqual(Ord(cfReportText), Ord(DetectFormat('Graph of callers for OPERAT.NAME' + CRLF + 'Totals: 3', False)), 'prose starting with Graph');
  Assert.AreEqual(Ord(cfGraph), Ord(DetectFormat('graph g {' + CRLF + '}', False)), 'an undirected DOT');
  Assert.AreEqual(Ord(cfReportText), Ord(DetectFormat('', False)), 'an empty report is a report');
  Assert.AreEqual(Ord(cfFormsCsv), Ord(DetectFormat('Forms.CSV', True)), 'csv path, any case');
  Assert.AreEqual(Ord(cfGraph), Ord(DetectFormat('x.dot', True)), 'dot path');
  Assert.AreEqual(Ord(cfReportText), Ord(DetectFormat('who-writes.txt', True)), 'txt path');
  Assert.AreEqual(Ord(cfReportText), Ord(DetectFormat('Unit1.pas', True)), 'pas path (a DocInsight block)');
  Assert.AreEqual(Ord(cfUnknown), Ord(DetectFormat('picture.png', True)), 'png path');
  var Dir:= TPath.Combine(TPath.GetTempPath, 'ChartsTests.Adapters.Detect-' + TPath.GetGUIDFileName);
  TDirectory.CreateDirectory(Dir);
  try
    Assert.AreEqual(Ord(cfUnknown), Ord(DetectFormat(Dir, True)), 'a folder without graph.dot');
    TFile.WriteAllText(TPath.Combine(Dir, 'graph.dot'), 'digraph g {}');
    Assert.AreEqual(Ord(cfGraph), Ord(DetectFormat(Dir, True)), 'a bundle folder');
  finally
    TDirectory.Delete(Dir, True);
  end;
end;

procedure TAdaptersTests.DifferentFormatsAreRefusedByName;
begin
  var Report:= DetectFormat('Totals: 3 sites' + CRLF, False);
  var Csv:= DetectFormat(ReadFixture('forms', 'a.csv'), False);
  var Graph:= DetectFormat(ReadFixture('graph', 'who-writes-a.dot'), False);
  Assert.AreNotEqual(Ord(Report), Ord(Csv), 'report vs forms csv differ');
  Assert.AreNotEqual(Ord(Csv), Ord(Graph), 'forms csv vs graph differ');
  Assert.AreEqual('report', FormatName(Report));
  Assert.AreEqual('forms-csv', FormatName(Csv));
  Assert.AreEqual('chart-graph', FormatName(Graph));
  Assert.AreEqual('unknown', FormatName(cfUnknown));
  // the dispatcher routes each format to its own adapter
  Assert.AreEqual(DATA_ROWS_A, Integer(Length(ItemsFor(cfFormsCsv, ReadFixture('forms', 'a.csv')))), 'csv items');
  Assert.AreEqual(GRAPH_NODES_A + GRAPH_EDGES_A, Integer(Length(ItemsFor(cfGraph, ReadFixture('graph', 'who-writes-a.dot')))), 'graph items');
  Assert.AreEqual(ONE, Integer(Length(ItemsFor(cfReportText, 'Totals: 3 sites'))), 'report items');
  Assert.AreEqual(0, Integer(Length(ItemsFor(cfUnknown, 'x'))), 'unknown gives no items');
end;

initialization
  TDUnitX.RegisterTestFixture(TAdaptersTests);

end.
