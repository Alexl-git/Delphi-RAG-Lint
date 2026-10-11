unit ChartsTests.AdapterText;

(* Cases for DRagLint.Charts.Adapter.Text: a report (plain Ask-Report.ps1 stdout
  or its DocInsight remarks block) turned into diff items whose Key ignores
  what does not change the answer (spec N1-N5) and whose Text is what was on
  the page.

  Fixtures live in tests\charts\fixtures\reports and stay 7-bit ASCII: a
  '{U+XXXX}' in a plain fixture stands for that character and is expanded here,
  as charts\fixtures\docinsight\cases.txt says. *)

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAdapterTextTests = class
  public
    [Test] procedure PlainAndDocInsightOfSameAnswerAreEqual;
    [Test] procedure RewrappedDocInsightIsEqual;
    [Test] procedure NarrowerRewrapOfIndentedRowIsEqual;
    [Test] procedure NarrowerRewrapOfTopLevelLineIsAKnownLimit;
    [Test] procedure LegacyAndNewHeaderBodiesAreEqual;
    [Test] procedure LineEndsAndBomDoNotDiff;
    [Test] procedure TrailingSpaceHeaderSentenceIsNotAnItem;
    [Test] procedure CommandWithoutBlankLineAfterItIsNotOverJoined;
    [Test] procedure AnchorLineNumbersAreIgnored;
    [Test] procedure StepNumbersAreIgnored;
    [Test] procedure LaterTableCellNumberIsAChange;
    [Test] procedure VolatileLinesAreDropped;
    [Test] procedure BlankRunsCollapse;
    [Test] procedure ShownTextIsOriginal;
    [Test] procedure EmptyBodyVersusFullBodyIsOneInsertHunk;
    [Test] procedure TraceReportRoundTrips;
    [Test] procedure CutLongTokenIsAKnownLimit;
    [Test] procedure FormIsDetected;
  end;

implementation

uses
  System.SysUtils, System.StrUtils, System.IOUtils, System.Character, System.RegularExpressions,
  DRagLint.Charts.Diff, DRagLint.Charts.ReportHeader, DRagLint.Charts.DocInsight,
  DRagLint.Charts.Adapter.Text;

const
  CRLF = #13#10;
  LF = #10;
  CR = #13;
  BOM = #$FEFF;
  FIXTURE_DIR = 'tests\charts\fixtures\reports';
  FIXTURE_PROBE = 'who-writes.plain.txt';
  REPO_ROOT_ENV = 'DRAGLINT_REPO_ROOT';
  HEX_BASE = '$';
  SENTENCE = 'Who writes this field (drag-lint report who-writes) for OPERAT.NAME, asked on 2026-10-10 14:32, engine 1.27.0.';
  COMMAND = 'COMMAND who-writes -Target "OPERAT.NAME" -Project "C:\x\Micronite2027.dproj" -Depth 3';
  NO_FINDINGS = '/// The report returned no findings.';
  { EmitWrapped's room on a line with no indent: 100 columns minus '/// ' }
  ROOM = 96;
  { a token far past the room, so the formatter must cut it }
  LONG_TOKEN_LEN = 142;
  ONE_ITEM = 1;
  { who-writes.doc.txt logical lines: Totals, Selected, FormShow, then the wrapped Grid->Post row }
  L_GRID_POST = 3;
  { a column a wiki or an editor might re-wrap a block at, narrower than the formatter's 100 }
  NARROW_WIDTH = 72;
  ROW_TEXT = 'TfrmBlueprint4.Grid->Post (Blueprint4.pas:3001) -- a note that is long enough ' +
    'to wrap twice at seventy-two columns, and then a little more so the third line is there too';
  { the two forms an old report may have been saved in }
  FOREIGN_FIXTURES: array[0..1] of string = ('who-writes.doc.txt', 'who-writes.plain.txt');

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

(* '{U+XXXX}' (4 or 5 hex digits) -> that character; above U+FFFF a surrogate pair. *)
function ExpandCodePoints(const pText: string): string;
begin
  var SB:= TStringBuilder.Create;
  try
    var Last:= 0;
    for var M in TRegEx.Matches(pText, '\{U\+([0-9A-F]{4,5})\}') do
    begin
      SB.Append(Copy(pText, Last + 1, M.Index - 1 - Last));
      SB.Append(Char.ConvertFromUtf32(StrToInt(HEX_BASE + M.Groups[1].Value)));
      Last:= M.Index - 1 + M.Length;
    end;
    SB.Append(Copy(pText, Last + 1, MaxInt));
    Result:= SB.ToString;
  finally
    SB.Free;
  end;
end;

function Fixture(const pName: string): string;
begin
  var Dir:= FixtureDir;
  if Dir = '' then
    Assert.Fail('fixture folder ' + FIXTURE_DIR + ' not found (run from the repo or set ' + REPO_ROOT_ENV + ')');
  Result:= ExpandCodePoints(TFile.ReadAllText(TPath.Combine(Dir, pName), TEncoding.ASCII));
end;

function KeysOf(const pItems: TArray<TDiffItem>): string;
begin
  Result:= '';
  for var Item in pItems do
    Result:= Result + Item.Key + LF;
end;

{ Diffs two reports and fails with both key lists when any edit is not equal. }
procedure AssertSameAnswer(const pOld, pNew, pWhat: string);
begin
  var A:= ReportItems(pOld);
  var B:= ReportItems(pNew);
  var Eq, Del, Ins: Integer;
  var Changed:= CountEdits(MyersDiff(A, B), Eq, Del, Ins);
  Assert.IsFalse(Changed, Format('%s: %d deleted, %d inserted' + LF + 'OLD:' + LF + '%s' + 'NEW:' + LF + '%s',
    [pWhat, Del, Ins, KeysOf(A), KeysOf(B)]));
  Assert.IsTrue(Eq > 0, pWhat + ': nothing compared');
end;

{ Greedy word wrap of one logical line into '///' lines of at most pWidth columns;
  continuation lines get two more spaces, as EmitWrapped does (no token cutting). }
function WrapDoc(const pText, pIndent: string; pWidth: Integer): string;
begin
  Result:= '';
  var Lead:= pIndent;
  var Current:= '';
  for var Word in pText.Split([' '], TStringSplitOptions.ExcludeEmpty) do
    if Current = '' then
      Current:= Word
    else if Length('/// ' + Lead + Current + ' ' + Word) <= pWidth then
      Current:= Current + ' ' + Word
    else
    begin
      Result:= Result + '/// ' + Lead + Current + CRLF;
      Lead:= pIndent + '  ';
      Current:= Word;
    end;
  Result:= Result + '/// ' + Lead + Current + CRLF;
end;

function HasKeyContaining(const pItems: TArray<TDiffItem>; const pPart: string): Boolean;
begin
  for var Item in pItems do
    if ContainsStr(Item.Key, pPart) then
      Exit(True);
  Result:= False;
end;

function WithTrailingSpaces(const pText: string): string;
begin
  Result:= StringReplace(pText, CRLF, '  ' + CRLF, [rfReplaceAll]);
end;

procedure TAdapterTextTests.PlainAndDocInsightOfSameAnswerAreEqual;
begin
  AssertSameAnswer(Fixture('who-writes.plain.txt'), Fixture('who-writes.doc.txt'), 'plain vs DocInsight');
end;

procedure TAdapterTextTests.RewrappedDocInsightIsEqual;
begin
  { the rewrapped copy moved one word UP per wrapped line (a wider wrap column) }
  AssertSameAnswer(Fixture('who-writes.doc.txt'), Fixture('who-writes.doc.rewrapped.txt'), 'rewrapped');
end;

procedure TAdapterTextTests.NarrowerRewrapOfIndentedRowIsEqual;
begin
  { ruling R11: under an indented row a four-space line is always a continuation }
  var Plain:= 'TOP line' + CRLF + '    ' + ROW_TEXT + CRLF;
  var Doc:= FormatAnswerAsDocInsight('P', 'who-writes', 'T', Date, Plain);
  var Narrow:= '/// TOP line' + CRLF + WrapDoc(ROW_TEXT, '  ', NARROW_WIDTH);
  Assert.IsTrue(Pos('///     ', Narrow) > 0, 'the narrow copy really wraps: ' + Narrow);
  AssertSameAnswer(Doc, Narrow, 'indented row at 72 columns');
  AssertSameAnswer(Plain, Narrow, 'plain vs indented row at 72 columns');
end;

procedure TAdapterTextTests.NarrowerRewrapOfTopLevelLineIsAKnownLimit;
begin
  { accepted limit: an unindented line re-wrapped narrower is not joined, because a
    two-space row under an unindented line is a real shape; the inverse wrap rule decides }
  var Plain:= ROW_TEXT + CRLF;
  var Narrow:= WrapDoc(ROW_TEXT, '', NARROW_WIDTH);
  var Eq, Del, Ins: Integer;
  Assert.IsTrue(CountEdits(MyersDiff(ReportItems(Plain), ReportItems(Narrow)), Eq, Del, Ins),
    'known limit: a top-level narrower re-wrap diffs');
  { the formatter's own wrap of the same line still compares equal }
  AssertSameAnswer(Plain, FormatAnswerAsDocInsight('P', 'who-writes', 'T', Date, Plain), 'formatter wrap');
end;

procedure TAdapterTextTests.LegacyAndNewHeaderBodiesAreEqual;
begin
  AssertSameAnswer(Fixture('who-writes.legacy.doc.txt'), Fixture('who-writes.doc.txt'), 'legacy vs header');
end;

procedure TAdapterTextTests.LineEndsAndBomDoNotDiff;
begin
  { Review Focus 1: an old report saved by a foreign editor }
  for var Name in FOREIGN_FIXTURES do
  begin
    var Original:= Fixture(Name);
    var Spaced:= WithTrailingSpaces(Original);
    AssertSameAnswer(Original, BOM + StringReplace(Spaced, CRLF, LF, [rfReplaceAll]), Name + ' LF + BOM + spaces');
    AssertSameAnswer(Original, BOM + StringReplace(Spaced, CRLF, CR, [rfReplaceAll]), Name + ' CR + BOM + spaces');
    var Items:= ReportItems(BOM + StringReplace(Spaced, CRLF, LF, [rfReplaceAll]));
    Assert.IsFalse(HasKeyContaining(Items, 'drag-lint report'), Name + ': the header sentence became an item');
    Assert.IsFalse(HasKeyContaining(Items, 'COMMAND'), Name + ': the COMMAND line became an item');
  end;
end;

procedure TAdapterTextTests.TrailingSpaceHeaderSentenceIsNotAnItem;
begin
  { Task 4: the formatter falls back to the legacy sentence on a trailing space; the key must not care }
  var Spaced:= SENTENCE + '   ' + CRLF + COMMAND + ' ' + CRLF + 'CHART who-writes X -- 1 write sites / 1 routines' + CRLF;
  var Clean:= SENTENCE + CRLF + COMMAND + CRLF + 'CHART who-writes X -- 1 write sites / 1 routines' + CRLF;
  var Items:= ReportItems(Spaced);
  Assert.AreEqual(ONE_ITEM, Integer(Length(Items)), KeysOf(Items));
  Assert.AreEqual('Totals: 1 write sites / 1 routines.', Items[0].Key);
  AssertSameAnswer(Clean, Spaced, 'trailing-space header');
end;

procedure TAdapterTextTests.CommandWithoutBlankLineAfterItIsNotOverJoined;
begin
  { a foreign edit removed the blank '///' after COMMAND; the next line sits at the
    sentence's indent, so ParseReportHeader must not swallow it into the command }
  var Doc:= Fixture('who-writes.doc.txt');
  var Edited:= StringReplace(Doc, '-Depth 3' + CRLF + '///' + CRLF, '-Depth 3' + CRLF, []);
  Assert.AreNotEqual(Doc, Edited, 'fixture shape changed');
  AssertSameAnswer(Doc, Edited, 'no blank after COMMAND');
end;

procedure TAdapterTextTests.AnchorLineNumbersAreIgnored;
begin
  Assert.AreEqual(NormaliseKey('TfrmX.Foo (A.pas:12)'), NormaliseKey('TfrmX.Foo (A.pas:99)'));
  Assert.AreEqual('TfrmX.Foo (A.pas)', NormaliseKey('TfrmX.Foo (A.pas:12)'));
  Assert.AreEqual('TfrmX.Foo (A.pas)', NormaliseKey('  TfrmX.Foo @A.pas:12'), 'plain anchor form');
  Assert.AreEqual('see :12 (A.pas)', NormaliseKey('see :12 (A.pas:7)'), 'only the line inside an anchor goes');
  AssertSameAnswer('  TfrmX.Foo @A.pas:12' + CRLF, '/// TfrmX.Foo (A.pas:99)' + CRLF, 'plain vs doc anchors');
end;

procedure TAdapterTextTests.StepNumbersAreIgnored;
begin
  Assert.AreEqual('x', NormaliseKey('[01] x'));
  Assert.AreEqual('x', NormaliseKey('  [12] x'));
  Assert.AreEqual('x', NormaliseKey('12. x'));
  Assert.AreEqual('| x', NormaliseKey('| 12 | x'));
  Assert.AreEqual(NormaliseKey('| 3 | x'), NormaliseKey('| 12 | x'));
  Assert.AreEqual('see step N', NormaliseKey('see step 12'));
  Assert.AreEqual(NormaliseKey('see step 3 then'), NormaliseKey('see step 12 then'));
  Assert.AreEqual('engine 1.27.0', NormaliseKey('engine 1.27.0'), 'a version is not a step number');
end;

procedure TAdapterTextTests.LaterTableCellNumberIsAChange;
begin
  { ruling R12: only the first cell is a step number }
  Assert.AreNotEqual(NormaliseKey('| 1 | write sites | 26 |'), NormaliseKey('| 1 | write sites | 27 |'));
  Assert.AreEqual(NormaliseKey('| 3 | write sites | 26 |'), NormaliseKey('| 12 | write sites | 26 |'));
  Assert.AreEqual('| write sites | 26 |', NormaliseKey('| 12 | write sites | 26 |'));
end;

procedure TAdapterTextTests.VolatileLinesAreDropped;
begin
  Assert.AreEqual('', NormaliseKey('BUNDLE C:\Temp\x'));
  Assert.AreEqual('', NormaliseKey('INDEX C:\x\a.sqlite'));
  Assert.AreEqual('', NormaliseKey('  INDEX A + B AS OF 2026-10-05T16:25Z'));
  Assert.AreEqual('', NormaliseKey('X AS OF 2026-10-05T16:25Z'));
  Assert.AreEqual('', NormaliseKey('  REGENERATE & ''x.ps1'' -Question who-writes'));
  Assert.AreEqual('', NormaliseKey('WARNING: something'));
  Assert.AreEqual('', NormaliseKey('ask-report: refused'));
  var Items:= ReportItems('BUNDLE C:\a' + CRLF + 'INDEX C:\b' + CRLF + 'kept line' + CRLF +
    '  REGENERATE & x' + CRLF);
  Assert.AreEqual(ONE_ITEM, Integer(Length(Items)), KeysOf(Items));
  Assert.AreEqual('kept line', Items[0].Key);
end;

procedure TAdapterTextTests.BlankRunsCollapse;
begin
  Assert.AreEqual('', NormaliseKey('   '));
  Assert.AreEqual('a b', NormaliseKey('  a  '#9'  b   '));
  AssertSameAnswer('a' + CRLF + 'b' + CRLF, 'a' + CRLF + CRLF + CRLF + '   ' + CRLF + 'b' + CRLF + CRLF, 'plain blanks');
  AssertSameAnswer('/// a' + CRLF + '/// b' + CRLF, '/// a' + CRLF + '///' + CRLF + '///' + CRLF + '/// b' + CRLF,
    'doc blanks');
end;

procedure TAdapterTextTests.ShownTextIsOriginal;
begin
  var Items:= ReportItems('  TfrmX.Foo @A.pas:12' + CRLF);
  Assert.AreEqual(ONE_ITEM, Integer(Length(Items)));
  Assert.AreEqual('  TfrmX.Foo @A.pas:12', Items[0].Text);
  Assert.AreEqual('TfrmX.Foo (A.pas)', Items[0].Key);
  { a wrapped DocInsight line shows every physical line it came from }
  var Doc:= '/// ' + StringOfChar('w', ROOM - 2) + ' x' + CRLF + '///   tail' + CRLF;
  Items:= ReportItems(Doc);
  Assert.AreEqual(ONE_ITEM, Integer(Length(Items)), KeysOf(Items));
  Assert.AreEqual('/// ' + StringOfChar('w', ROOM - 2) + ' x' + CRLF + '///   tail', Items[0].Text);
end;

procedure TAdapterTextTests.EmptyBodyVersusFullBodyIsOneInsertHunk;
begin
  var Full:= Fixture('who-writes.doc.txt');
  var HeaderEnd:= Pos('-Depth 3' + CRLF, Full) + Length('-Depth 3' + CRLF);
  var Empty:= Copy(Full, 1, HeaderEnd - 1) + '///' + CRLF + NO_FINDINGS + CRLF + '/// </remarks>' + CRLF;
  var A:= ReportItems(Empty);
  var B:= ReportItems(Full);
  Assert.AreEqual(ONE_ITEM, Integer(Length(A)), KeysOf(A));
  Assert.AreEqual('The report returned no findings.', A[0].Key);
  var Edits:= MyersDiff(A, B);
  var Eq, Del, Ins: Integer;
  Assert.IsTrue(CountEdits(Edits, Eq, Del, Ins), 'a change (exit 1)');
  Assert.AreEqual(0, Eq);
  Assert.AreEqual(1, Del);
  Assert.AreEqual(Integer(Length(B)), Ins);
  Assert.AreEqual(ONE_ITEM, Integer(Length(BuildHunks(Edits))));
end;

procedure TAdapterTextTests.TraceReportRoundTrips;
begin
  AssertSameAnswer(Fixture('trace.plain.txt'), Fixture('trace.doc.txt'), 'trace');
end;

procedure TAdapterTextTests.CutLongTokenIsAKnownLimit;
var
  Plain, Doc: string;
begin
  { a token longer than the room IS cut by the formatter; the cut line holds
    exactly the room and is rejoined WITHOUT a space -> equal }
  Plain:= 'x ' + StringOfChar('A', LONG_TOKEN_LEN) + ' end' + CRLF;
  Doc:= FormatAnswerAsDocInsight('P', 'who-writes', 'T', Date, Plain);
  AssertSameAnswer(Plain, Doc, 'genuine cut' + LF + Doc);
  { the known limit: a word of EXACTLY the room fitted whole, the next word wrapped,
    and the physical line is indistinguishable from a cut -> rejoined without a
    space -> unequal to its plain form }
  Plain:= StringOfChar('B', ROOM) + ' end' + CRLF;
  Doc:= FormatAnswerAsDocInsight('P', 'who-writes', 'T', Date, Plain);
  var A:= ReportItems(Plain);
  var B:= ReportItems(Doc);
  Assert.AreEqual(StringOfChar('B', ROOM) + ' end', A[0].Key);
  Assert.AreEqual(StringOfChar('B', ROOM) + 'end', B[0].Key, 'known limit: rejoined without a space');
end;

procedure TAdapterTextTests.FormIsDetected;
var
  Form: TReportForm;
begin
  Assert.AreEqual(Ord(rfDocInsight), Ord(DetectReportForm(BOM + CRLF + '  /// <remarks>' + CRLF)));
  Assert.AreEqual(Ord(rfPlain), Ord(DetectReportForm('BUNDLE x' + CRLF + '/// y')));
  Assert.AreEqual(Ord(rfPlain), Ord(DetectReportForm('')));
  var L:= ReportLogicalLines(Fixture('who-writes.doc.txt'), Form);
  Assert.AreEqual(Ord(rfDocInsight), Ord(Form));
  Assert.AreEqual('Totals: 26 write sites / 26 routines.', L[0], 'header and remarks are not logical lines');
  Assert.AreEqual('TfrmBlueprint4.Grid->Post (Blueprint4.pas:3001) -- a note with <angle> & ampersand, ' +
    'drag-lint auto marker', L[L_GRID_POST], 'joined and unescaped');
end;

initialization
  TDUnitX.RegisterTestFixture(TAdapterTextTests);

end.
