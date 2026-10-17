unit ChartsTests.Question;

{ Cases for DRagLint.Charts.Question (the question tables, the registry, the JSON text)
  and DRagLint.Charts.Ask (the parts of Ask-Report / New-DiagramArtifact that need no
  index). Expected texts were printed by the PowerShell scripts themselves on 2026-10-13:
  the dot read-back by Ask-Report.ps1's own loop (lines 314-355) over the same dot lines. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TQuestionTests = class
  public
    [Test] procedure PhraseAndVocabFollowTheScripts;
    [Test] procedure JsonStringEscapesAsConvertToJson;
    [Test] procedure MetaFieldsEncodeTheirType;
    [Test] procedure UnportedQuestionIsRefused;
    [Test] procedure DotIsFoundBesideTheInstalledScripts;
    [Test] procedure OtherIndexesFollowAskReport;
  end;

  [TestFixture]
  TAskTests = class
  public
    [Test] procedure SlugKeepsOnlyLettersAndDigits;
    [Test] procedure CommandLineNamesOnlyGivenArguments;
    [Test] procedure RegenerateNamesTheIndexesAQuestionReads;
    [Test] procedure IndexLinesNameTheIndexesAQuestionReads;
    [Test] procedure HtmlDecodeAsWebUtility;
    [Test] procedure UnescapeDataStringAsUri;
    [Test] procedure DotRowsAsAskReport;
    [Test] procedure DotRowsWithNoAnchoredRow;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, DRagLint.Charts.ReportHeader, DRagLint.Charts.Question, DRagLint.Charts.Ask;

const
  MAX_ROWS_TWO = 2;
  BIG_INT = 41;
  SHOWN_SUM = 24;
  HALF_SUM = 2.5;
  FIELD_COUNT = 174;
  METHOD_COUNT = 101;

function Cmd(const pQuestion: string; const pPairs: array of string): TReportCommand;
begin
  Result:= Default(TReportCommand);
  Result.Question:= pQuestion;
  var K:= 0;
  while K < High(pPairs) do
  begin
    var A: TCommandArg;
    A.Name:= pPairs[K];
    A.Value:= pPairs[K + 1];
    Result.Args:= Result.Args + [A];
    Inc(K, 2);
  end;
end;

procedure TQuestionTests.PhraseAndVocabFollowTheScripts;
var
  L, R: string;
begin
  Assert.AreEqual('Which tables this routine touches', QuestionPhrase('touches-tables'));
  Assert.AreEqual('Where this database column is shown', QuestionPhrase('Shown-Where'));
  Assert.AreEqual('Report', QuestionPhrase('no-such-question'));
  Assert.IsTrue(QuestionVocab('deps', L, R));
  Assert.AreEqual('used by', L);
  Assert.AreEqual('uses', R);
  Assert.IsFalse(QuestionVocab('nope', L, R));
  Assert.AreEqual('', L + R);
end;

procedure TQuestionTests.JsonStringEscapesAsConvertToJson;
begin
  Assert.AreEqual('"p\\a \"b\"\r\n\t\u0001<&>''"', PsJsonString('p\a "b"'#13#10#9#1'<&>'''));
end;

procedure TQuestionTests.MetaFieldsEncodeTheirType;
begin
  Assert.AreEqual('41', TMetaField.Int('Uses', BIG_INT).Json);
  Assert.AreEqual('true', TMetaField.Bool('AllClickable', True).Json);
  Assert.AreEqual('"FTRNAMESTR"', TMetaField.Str('Column', 'FTRNAMESTR').Json);
  { a Measure-Object sum is a [double]: ConvertTo-Json keeps the '.0' (Emit-ClassSurface Shown) }
  Assert.AreEqual('24.0', TMetaField.Real('Shown', SHOWN_SUM).Json);
  Assert.AreEqual('2.5', TMetaField.RealJson(HALF_SUM));
  { an [ordered] dictionary nested in the emitter object, as ConvertTo-Json -Depth 4 indents it }
  Assert.AreEqual('{' + sLineBreak + '      "field": 174,' + sLineBreak + '      "method": 101' + sLineBreak + '    }',
    TMetaField.Obj('ByKind', [TMetaField.Int('field', FIELD_COUNT), TMetaField.Int('method', METHOD_COUNT)]).Json);
  Assert.AreEqual('{}', TMetaField.Obj('ByKind', []).Json);
  { a [string[]] in the emitter object (Emit-Cycles EdgeList): elements at six spaces, the bracket at four }
  Assert.AreEqual('[' + sLineBreak + '      "a"' + ',' + sLineBreak + '      "b"' + sLineBreak + '    ]', TMetaField.StrList('EdgeList', ['a', 'b']).Json);
  Assert.AreEqual('[' + sLineBreak + '      "a"' + sLineBreak + '    ]', TMetaField.StrList('EdgeList', ['a']).Json);
  Assert.AreEqual('[]', TMetaField.StrList('EdgeList', []).Json);
  { the PS wrote $null: the value was not asked (Emit-WhoCalls NameMatches walking callees) }
  Assert.AreEqual('null', TMetaField.Null('NameMatches').Json);
end;

procedure TQuestionTests.UnportedQuestionIsRefused;
var
  E: TChartEmitter;
begin
  Assert.IsFalse(FindChartQuestion('no-such-question', E));
  var Args:= Default(TQuestionArgs);
  Args.Question:= 'no-such-question';
  Assert.WillRaise(procedure begin AskChartQuestion(Args); end, EChartsQuestion);
end;

procedure TQuestionTests.OtherIndexesFollowAskReport;
begin
  { Ask-Report.ps1's $needServer and $needSql }
  for var Id in ['round-trip', 'Lands-Where'] do
    Assert.IsTrue(QuestionReadsServerIndex(Id), Id);
  for var Id in ['round-trip', 'lands-where', 'consumers', 'FEEDS-FROM'] do
    Assert.IsTrue(QuestionReadsSqlIndex(Id), Id);
  for var Id in ['consumers', 'feeds-from', 'crosses-boundary', 'touches-tables'] do
    Assert.IsFalse(QuestionReadsServerIndex(Id), Id);
  for var Id in ['crosses-boundary', 'touches-tables', 'exception-paths'] do
    Assert.IsFalse(QuestionReadsSqlIndex(Id), Id);
end;

function QArgs(const pQuestion: string): TQuestionArgs;
begin
  Result:= Default(TQuestionArgs);
  Result.Question:= pQuestion;
  Result.Target:= 'T.X';
  Result.DbPath:= 'C:\d.sqlite';  // dl:ok hardcoded-absolute-path@4ee4 -- REVIEWED 2026-10-14: a fixture value, never opened: QArgs only proves which index paths a question carries
  Result.ServerDbPath:= 'C:\s.sqlite';  // dl:ok hardcoded-absolute-path@16b8 -- REVIEWED 2026-10-14: a fixture value, never opened: QArgs only proves which index paths a question carries
  Result.SqlDbPath:= 'C:\q.sqlite';  // dl:ok hardcoded-absolute-path@ba73 -- REVIEWED 2026-10-14: a fixture value, never opened: QArgs only proves which index paths a question carries
  Result.CounterpartDb:= 'C:\c.sqlite';  // dl:ok hardcoded-absolute-path@d268 -- REVIEWED 2026-10-14: a fixture value, never opened: QArgs only proves which index paths a question carries
  Result.Cap:= DEFAULT_CAP;
  Result.Depth:= DEFAULT_DEPTH;
  Result.SurfaceCap:= DEFAULT_SURFACE_CAP;
end;

procedure TAskTests.RegenerateNamesTheIndexesAQuestionReads;
begin
  { New-DiagramArtifact.ps1 $meta.regenerate: -SqlDbPath before -ServerDbPath, both after -Cap }
  Assert.AreEqual('New-DiagramArtifact.ps1 -Question feeds-from -Target T.X -DbPath "C:\d.sqlite" -Cap 20 -SqlDbPath "C:\q.sqlite"',
    RegenerateText(QArgs('feeds-from')));
  Assert.AreEqual('New-DiagramArtifact.ps1 -Question lands-where -Target T.X -DbPath "C:\d.sqlite" -Cap 20 -SqlDbPath "C:\q.sqlite"' +
    ' -ServerDbPath "C:\s.sqlite"', RegenerateText(QArgs('lands-where')));
  Assert.AreEqual('New-DiagramArtifact.ps1 -Question round-trip -Target T.X -DbPath "C:\d.sqlite" -Depth 2 -SqlDbPath "C:\q.sqlite"' +
    ' -ServerDbPath "C:\s.sqlite"', RegenerateText(QArgs('round-trip')));
  { a question that does not read them never names them, even when they are carried }
  Assert.AreEqual('New-DiagramArtifact.ps1 -Question deps -Target T.X -DbPath "C:\d.sqlite"', RegenerateText(QArgs('deps')));
  { the script names them unconditionally for a question that reads them }
  var A:= QArgs('consumers');
  A.SqlDbPath:= '';
  Assert.AreEqual('New-DiagramArtifact.ps1 -Question consumers -Target T.X -DbPath "C:\d.sqlite" -Cap 20 -SqlDbPath ""', RegenerateText(A));
end;

procedure TAskTests.IndexLinesNameTheIndexesAQuestionReads;
begin
  { Ask-Report.ps1: INDEX db, then (server), (sql), (counterpart) }
  Assert.AreEqual('INDEX C:\d.sqlite|INDEX C:\s.sqlite (server)|INDEX C:\q.sqlite (sql)',
    string.Join('|', AnswerIndexLines(QArgs('round-trip'))));
  Assert.AreEqual('INDEX C:\d.sqlite|INDEX C:\q.sqlite (sql)', string.Join('|', AnswerIndexLines(QArgs('feeds-from'))));
  Assert.AreEqual('INDEX C:\d.sqlite|INDEX C:\c.sqlite (counterpart)', string.Join('|', AnswerIndexLines(QArgs('crosses-boundary'))));
  Assert.AreEqual('INDEX C:\d.sqlite', string.Join('|', AnswerIndexLines(QArgs('touches-tables'))));
end;

procedure TAskTests.SlugKeepsOnlyLettersAndDigits;
begin
  Assert.AreEqual('uPipe_T_Handle_x_y', BundleSlug('uPipe.T.Handle x-y'));
end;

procedure TAskTests.CommandLineNamesOnlyGivenArguments;
begin
  Assert.AreEqual('COMMAND deps -Target "DRagLint.CLI"', ReportCommandText(Cmd('deps', ['Target', 'DRagLint.CLI'])));
  Assert.AreEqual('COMMAND path -Target "A.B" -To "C.D" -Depth 3 -Cap 5 -Mode read -MaxRows 9',
    ReportCommandText(Cmd('path', ['MaxRows', '9', 'Mode', 'read', 'Cap', '5', 'Depth', '3', 'To', 'C.D', 'Target', 'A.B'])));
  { an empty -To is left out }
  Assert.AreEqual('COMMAND x -Target "t"', ReportCommandText(Cmd('x', ['Target', 't', 'To', ''])));
end;

procedure TAskTests.HtmlDecodeAsWebUtility;
begin
  Assert.AreEqual('a & b <c> "d" ''e'' '#$00B7' f', HtmlDecode('a &amp; b &lt;c&gt; &quot;d&quot; &#39;e&#x27; &#183; f'));
  Assert.AreEqual('&amp;lt; stays one pass', HtmlDecode('&amp;amp;lt; stays one pass'));
  Assert.AreEqual('&nosuch; & &#; &#xZZ;', HtmlDecode('&nosuch; & &#; &#xZZ;'));
end;

procedure TAskTests.UnescapeDataStringAsUri;
begin
  Assert.AreEqual('x\a b\U+.pas', UnescapeDataString('x%5Ca%20b%5CU+.pas'));
  Assert.AreEqual('100% sure %2', UnescapeDataString('100% sure %2'));
  Assert.AreEqual(#$00E9, UnescapeDataString('%C3%A9'));
end;

procedure TAskTests.DotRowsAsAskReport;
begin
  var Lines: TArray<string>:= [
    'digraph x {',
    '  subgraph cluster_focus_1 {',
    '    n1 [label=<<TABLE><TR><TD HREF="draglint://open?file=C%3A%5Ca%20b%5CU.pas&amp;line=12" TITLE="U.TFoo.Bar  --  U.pas:12"><FONT COLOR="#1">Bar</FONT></TD></TR><TR><TD ALIGN="LEFT"><FONT COLOR="#8">+3 more routines (+5 more sites) not shown</FONT></TD></TR></TABLE>>];',
    '  }',
    '  n2 [label=<<TABLE><TR><TD PORT="p1" HREF="draglint://open?file=C%3A%5Cx%5CV.pas&amp;line=7" TITLE="V.Baz"><FONT COLOR="#1">Baz</FONT>  <FONT COLOR="#8">:7</FONT></TD></TR>' +
      '<TR><TD PORT="p2" HREF="draglint://open?file=C%3A%5Cx%5CV.pas&amp;line=0" TITLE="a &amp; b &lt;c&gt;"><FONT COLOR="#1">Q &#183; R</FONT></TD></TR>' +
      '<TR><TD PORT="p3" HREF="draglint://open?file=C%3A%5Cx%5CW.dfm&amp;line=9" TITLE="ctl.Prop = &#39;Z&#39; -- W.dfm:9"><FONT>ctl</FONT></TD></TR>' +
      '<TR><TD HREF="draglint://open?file=C%3A%5Cx%5CV.pas&amp;line=7" TITLE="V.Baz"><FONT>Baz</FONT></TD></TR>' +
      '<TR><TD ALIGN="LEFT"><FONT>Code-driven display is NOT SHOWN &#183; here</FONT></TD></TR><TR><TD ALIGN="LEFT"><FONT>nothing hidden</FONT></TD></TR></TABLE>>];',
    '}'];
  var Rows:= DotAnswerRows(Lines, 'New-DiagramArtifact.ps1 -Question shown-where -Target X -DbPath "d" -Cap 20', MAX_ROWS_TWO,
    'b\graph.dot', 'b\index.html');
  Assert.AreEqual(
    '  TARGET U.TFoo.Bar @U.pas:12|' +
    '  V.Baz @V.pas:7|' +
    '  Q   R @V.pas -- a & b <c>|' +
    '  ... +3 more routines (+5 more sites) not shown (-Cap 20; raise -Cap to see them)|' +
    '  ... Code-driven display is NOT SHOWN   here|' +
    '  ... 1 more row(s) not printed here (-MaxRows 2): b\graph.dot', string.Join('|', Rows));
end;

procedure TAskTests.DotRowsWithNoAnchoredRow;
begin
  var Rows:= DotAnswerRows(['  n [label=<<TABLE><TR><TD><FONT>+2 more units not shown</FONT></TD></TR></TABLE>>];'],
    'New-DiagramArtifact.ps1 -Question deps', DEFAULT_MAX_ROWS, 'g.dot', 'b\index.html');
  Assert.AreEqual('  (no anchored result rows -- open b\index.html)|  ... +2 more units not shown (raise -Cap to see them)',
    string.Join('|', Rows));
end;

procedure TQuestionTests.DotIsFoundBesideTheInstalledScripts;
begin
  { the installed layout: scripts in <app>\bin, Graphviz in <app>\bin\graphviz\bin. An explicit
    DRAGLINT_DOT or a settings.json "dot" would win over this step, so the case only runs where
    neither is set (it is the machine's choice, not this code's). }
  if GetEnvironmentVariable('DRAGLINT_DOT') <> '' then
    Assert.Pass('DRAGLINT_DOT is set on this machine');
  if TFile.Exists(TPath.Combine(TPath.Combine(TPath.GetHomePath, 'drag-lint'), 'settings.json')) then
    Assert.Pass('a settings.json exists on this machine');
  var App:= TPath.Combine(TPath.GetTempPath, 'dl-dot-' + TGUID.NewGuid.ToString);
  var Bin:= TPath.Combine(App, 'bin');
  var DotDir:= TPath.Combine(TPath.Combine(Bin, 'graphviz'), 'bin');
  TDirectory.CreateDirectory(DotDir);
  try
    TFile.WriteAllText(TPath.Combine(DotDir, 'dot.exe'), '');
    var Args:= Default(TQuestionArgs);
    Args.ChartsRoot:= App;
    Args.ScriptDir:= Bin;
    Assert.AreEqual(TPath.Combine(DotDir, 'dot.exe'), Args.Dot);
  finally
    TDirectory.Delete(App, True);
  end;
end;
end.
