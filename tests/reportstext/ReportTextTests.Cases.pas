unit ReportTextTests.Cases;

{ DUnitX cases for DragLint.Plugin.ReportText -- the IDE-free half of the
  drag-lint > Reports submenu.

  WHAT IS PINNED, AND WHY EACH ONE IS A SILENT FAILURE IF IT BREAKS:

    the DocInsight block must never contain the autodoc provenance marker.
      Autodoc preserves UNMARKED content byte-for-byte; a pasted report that
      carried the marker would be treated as generated and rewritten or
      dropped on the next Auto Doc run, with nothing to say it happened.

    "+N more ... not shown" must survive the conversion. A count in the
      header that is larger than the rows printed is only honest while the
      disclosure line is there.

    the target sent for a DFM control must be <FormInstance>.<Control>.
      typeat answers Unit.TForm.Control; feeds-from and lands-where refuse
      that form (measured 2026-10-05 against the frozen ORM3 clones: exit 1,
      "no form or data module named Blueprint4"), and accept the instance
      form (exit 0).

    a stale-index reindex offered by the menu must be incremental and never a
      folder target. ParseReindexCommands accepts exactly the two shapes
      Ask-Report.ps1 prints and nothing else. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TReportCatalogTests = class
  public
    [Test] procedure CatalogHasEveryQuestionOnce;
    [Test] procedure CaptionsAreMenuSafe;
    [Test] procedure EveryKindHasAGroupCaption;
    [Test] procedure FindByIdWorks;
  end;

  [TestFixture]
  TReportFormatterTests = class
  public
    [Test] procedure BlockIsRemarksWithTripleSlashLines;
    [Test] procedure FirstSentenceNamesQuestionTargetAndDate;
    [Test] procedure LongLinesAreWrapped;
    [Test] procedure NonAsciiIsScrubbed;
    [Test] procedure NeverEmitsAutodocMarker;
    [Test] procedure MoreNotShownIsPreserved;
    [Test] procedure EmptyAnswerSaysSo;
    [Test] procedure RowsRenderFileInParentheses;
    [Test] procedure HeaderAndNoiseLinesAreDropped;
    [Test] procedure XmlSpecialCharsAreEscaped;
    [Test] procedure RoundTripTraceStaysReadable;
  end;

  [TestFixture]
  TReportGlueTests = class
  public
    [Test] procedure TypeAtResolvedIsRead;
    [Test] procedure TypeAtGarbageGivesEmpty;
    [Test] procedure DfmRootObjectIsParsed;
    [Test] procedure FormControlTargetUsesInstanceName;
    [Test] procedure FormControlTargetLeavesOthersAlone;
    [Test] procedure UnitNameOfMemberQName;
    [Test] procedure OnlyControlQuestionsConvert;
    [Test] procedure TargetValidation;
    [Test] procedure CmdLineCarriesEveryArgument;
    [Test] procedure ReasonStripsPrefix;
    [Test] procedure ReindexCommandsAreParsed;
    [Test] procedure FolderTargetIndexIsNeverAccepted;
  end;

implementation

uses
  System.SysUtils
  , System.StrUtils
  , System.Classes
  , DragLint.Plugin.ReportText
  ;

const
  CRLF = #13#10;
  TEST_DATE_Y = 2026;
  TEST_DATE_M = 10;
  TEST_DATE_D = 5;
  { opener + first sentence + closer: a block with findings has more }
  MIN_BLOCK_LINES = 3;
  { enough words to need several wrapped lines }
  FILLER_WORDS = 80;
  { a token longer than two whole lines, so it must be cut }
  LONG_TOKEN_LEN = 250;
  LONG_TOKEN_PROBE = 40;

function TestDate: TDateTime;
begin
  Result:= EncodeDate(TEST_DATE_Y, TEST_DATE_M, TEST_DATE_D);
end;

function SplitOut(const pText: string): TArray<string>;
var
  SL: TStringList;
begin
  SL:= TStringList.Create;
  try
    SL.Text:= pText;
    Result:= SL.ToStringArray;
  finally
    SL.Free;
  end;
end;

{ ---- catalog ---- }

procedure TReportCatalogTests.CatalogHasEveryQuestionOnce;
const
  { The ValidateSet of charts\src\New-DiagramArtifact.ps1, 2026-10-05. The
    runner (tests\plugin\run_reports_text.ps1) re-reads the ValidateSet itself
    and compares it two-way against `ReportTextTests --ids`, so a question added
    to the script without a menu item fails there even if this list is stale. }
  EXPECTED: array[0..REPORT_QUESTION_COUNT - 1] of string = (
    'butterfly', 'deps', 'who-calls', 'what-it-calls', 'who-writes', 'who-reads',
    'hierarchy', 'class-surface', 'event-wiring', 'touches-tables', 'lifecycle',
    'cycles', 'wiring', 'effects', 'architecture', 'protocol-trace',
    'crosses-boundary', 'shown-where', 'change-impact', 'tested-by',
    'exception-paths', 'consumers', 'feeds-from', 'lands-where', 'round-trip');
var
  Q: TReportQuestion;
begin
  Assert.AreEqual(REPORT_QUESTION_COUNT, Length(REPORT_QUESTIONS));
  for var Id: string in EXPECTED do
  begin
    var N: Integer:= 0;
    for Q in REPORT_QUESTIONS do
      if Q.Id = Id then Inc(N);
    Assert.AreEqual(1, N, 'question ' + Id);
  end;
end;

procedure TReportCatalogTests.CaptionsAreMenuSafe;
var
  Q: TReportQuestion;
begin
  for Q in REPORT_QUESTIONS do
  begin
    Assert.IsTrue(EndsStr('...', Q.Caption), Q.Id + ': caption ends with ...');
    Assert.AreEqual(0, Pos('&', Q.Caption), Q.Id + ': no accelerator ampersand');
    Assert.AreNotEqual(Q.Id + '...', Q.Caption, Q.Id + ': a human phrase, not the id');
  end;
end;

procedure TReportCatalogTests.EveryKindHasAGroupCaption;
begin
  for var K: TReportTargetKind:= Low(TReportTargetKind) to High(TReportTargetKind) do
    Assert.IsTrue(ReportGroupCaption(K) <> '', 'group caption');
end;

procedure TReportCatalogTests.FindByIdWorks;
var
  Q: TReportQuestion;
begin
  Assert.IsTrue(FindReportQuestion('round-trip', Q));
  Assert.AreEqual('Field round-trip (grid -> server -> SQL)...', Q.Caption);
  Assert.IsTrue(Q.Kind = rtkMember, 'round-trip is asked of a field or column');
  Assert.IsFalse(FindReportQuestion('no-such-question', Q));
end;

{ ---- formatter ---- }

const
  CHART_ANSWER =
    'BUNDLE C:\Temp\drag-lint-reports\who-writes-X' + CRLF +
    'INDEX C:\Projects\DB\ORM3\CLIENT\_D-RAG\Micronite2027.sqlite' + CRLF +
    'CHART who-writes Unit.TFoo.FBar -- 14 writers / 3 readers' + CRLF +
    '  TARGET Unit.TFoo.FBar @Unit.pas:99' + CRLF +
    '  TFoo.SendDelta @Unit.pas:3747 -- 4 write sites: 3747:5, 3753:7' + CRLF +
    '  TFoo.AddOperation @Unit.pas:4086 -- 2 write sites: 4086:3, 4097:5' + CRLF +
    '  ... +4 more ... not shown (-Cap 20; raise -Cap to see them)';

procedure TReportFormatterTests.BlockIsRemarksWithTripleSlashLines;
var
  Lines: TArray<string>;
begin
  Lines:= SplitOut(FormatReportAsDocInsight('who-writes', 'Unit.TFoo.FBar', TestDate, CHART_ANSWER));
  Assert.IsTrue(Length(Lines) > MIN_BLOCK_LINES, 'opener, first sentence, findings, closer');
  Assert.AreEqual('/// <remarks>', Lines[0]);
  Assert.AreEqual('/// </remarks>', Lines[High(Lines)]);
  for var L: string in Lines do
    Assert.IsTrue(StartsStr('///', L), 'every line is a /// line: ' + L);
end;

procedure TReportFormatterTests.FirstSentenceNamesQuestionTargetAndDate;
var
  Lines: TArray<string>;
begin
  Lines:= SplitOut(FormatReportAsDocInsight('who-writes', 'Unit.TFoo.FBar', TestDate, CHART_ANSWER));
  Assert.Contains(Lines[1], 'Who writes this field');
  Assert.Contains(Lines[1], 'who-writes');
  Assert.Contains(Lines[1] + Lines[2], 'Unit.TFoo.FBar');
  Assert.Contains(Lines[1] + Lines[2], '2026-10-05');
end;

procedure TReportFormatterTests.LongLinesAreWrapped;
var
  Answer: string;
  Text  : string;
begin
  Answer:= '  TFoo.Long @Unit.pas:1 -- ' + DupeString('word ', FILLER_WORDS) + StringOfChar('x', LONG_TOKEN_LEN);
  Text:= FormatReportAsDocInsight('who-calls', 'Unit.TFoo.Long', TestDate, Answer);
  for var L: string in SplitOut(Text) do
    Assert.IsTrue(Length(L) <= REPORT_DOC_MAX_LINE, Format('line of %d chars: %s', [Length(L), L]));
  Assert.Contains(Text, StringOfChar('x', LONG_TOKEN_PROBE), 'the long token is split, not dropped');
end;

procedure TReportFormatterTests.NonAsciiIsScrubbed;
var
  Text: string;
begin
  Text:= FormatReportAsDocInsight('who-calls', 'Unit.F', TestDate,
    '  A' + #$2014 + 'B ' + #$2192 + ' C' + #9 + 'caf' + #$00E9 + ' ' + #$2026 + ' ' + #$201C + 'q' + #$201D);
  for var C: Char in Text do
    Assert.IsTrue((C = #13) or (C = #10) or ((C >= ' ') and (C <= '~')),
                  Format('non-ASCII char U+%.4x survived', [Ord(C)]));
  Assert.Contains(Text, 'A--B');
  Assert.Contains(Text, '-> C');
  Assert.Contains(Text, '...');
  Assert.Contains(Text, '"q"');
end;

procedure TReportFormatterTests.NeverEmitsAutodocMarker;
var
  Text: string;
begin
  Text:= FormatReportAsDocInsight('who-calls', 'drag-lint:auto', TestDate,
    '  // drag-lint:auto @Unit.pas:1' + CRLF + '  DRAG-LINT:AUTO again' + CRLF + '  drag-lint:drag-lint:autoauto');
  Assert.AreEqual(0, Pos('DRAG-LINT:AUTO', UpperCase(Text)), Text);
end;

procedure TReportFormatterTests.MoreNotShownIsPreserved;
var
  Text: string;
begin
  Text:= FormatReportAsDocInsight('who-writes', 'Unit.TFoo.FBar', TestDate, CHART_ANSWER);
  Assert.Contains(Text, '+4 more');
  Assert.Contains(Text, 'not shown');
  Assert.Contains(Text, 'raise -Cap to see them');
end;

procedure TReportFormatterTests.EmptyAnswerSaysSo;
var
  Lines: TArray<string>;
  Text : string;
begin
  for var Answer: string in ['', 'BUNDLE C:\x' + CRLF + 'INDEX C:\y.sqlite' + CRLF] do
  begin
    Text:= FormatReportAsDocInsight('cycles', 'project', TestDate, Answer);
    Lines:= SplitOut(Text);
    Assert.AreEqual('/// <remarks>', Lines[0]);
    Assert.AreEqual('/// </remarks>', Lines[High(Lines)]);
    Assert.Contains(Text, 'no findings');
  end;
end;

procedure TReportFormatterTests.RowsRenderFileInParentheses;
var
  Text: string;
begin
  Text:= FormatReportAsDocInsight('who-writes', 'Unit.TFoo.FBar', TestDate, CHART_ANSWER);
  Assert.Contains(Text, 'TFoo.SendDelta (Unit.pas:3747) -- 4 write sites');
  Assert.Contains(Text, 'Unit.TFoo.FBar (Unit.pas:99)');
  Assert.AreEqual(0, Pos('@Unit.pas', Text), 'no @File anchors left');
  Assert.Contains(Text, '14 writers / 3 readers');
end;

procedure TReportFormatterTests.HeaderAndNoiseLinesAreDropped;
var
  Text: string;
begin
  Text:= FormatReportAsDocInsight('who-writes', 'Unit.TFoo.FBar', TestDate,
    'ask-report: note -- the engine reports no freshness for x; answering unchecked' + CRLF +
    'WARNING: something from a script' + CRLF + CHART_ANSWER);
  Assert.AreEqual(0, Pos('BUNDLE', Text));
  Assert.AreEqual(0, Pos('Micronite2027.sqlite', Text), 'INDEX header line dropped');
  Assert.AreEqual(0, Pos('ask-report', Text));
  Assert.AreEqual(0, Pos('WARNING', Text));
end;

procedure TReportFormatterTests.XmlSpecialCharsAreEscaped;
var
  Text: string;
begin
  Text:= FormatReportAsDocInsight('class-surface', 'Unit.TBox<T>', TestDate,
    '  Items: TList<T> & more @Unit.pas:5');
  Assert.Contains(Text, 'TList&lt;T> &amp; more');
  Assert.AreEqual(0, Pos('TList<T>', Text));
  Assert.Contains(Text, 'Unit.TBox&lt;T>');
end;

procedure TReportFormatterTests.RoundTripTraceStaysReadable;
const
  RT =
    'BUNDLE C:\Temp\r' + CRLF +
    'INDEX C:\a.sqlite' + CRLF +
    'INDEX C:\b.sqlite (server)' + CRLF +
    'TRACE OPERAT.NAME' + CRLF +
    '  TITLE "How OPERAT.NAME reaches frmBlueprint4.dxDBGrid1OperationVName and goes back"' + CRLF +
    '  INDEX Micronite2027 + MicroniteMW1Service + SQL AS OF 2026-09-28T22:19Z' + CRLF +
    '  REGENERATE & ''C:\x\New-DiagramArtifact.ps1'' -Question round-trip -Target x' + CRLF +
    '  TIERS client -> pipe -> server -> database' + CRLF +
    '' + CRLF +
    'ANCHOR' + CRLF +
    '[01] BINDS dxDBGrid1OperationVName : TcxGridDBColumn ONTO Name @Blueprint4.dfm:4534 -- DataBinding.FieldName' + CRLF +
    '       VIA dxDBGrid1OperationV.DataController.DataSource = Blueprint4_Model.dsrOperation @Blueprint4.dfm:4497' + CRLF +
    '' + CRLF +
    'WRITE' + CRLF +
    '[10] FIRES FMTOperation.AfterPost -> DoAfterPostOperation [by name] @Blueprint4.ViewModel.pas:639 -- in Create';
var
  Lines: TArray<string>;
  Text : string;
begin
  Text:= FormatReportAsDocInsight('round-trip', 'frmBlueprint4.dxDBGrid1OperationVName', TestDate, RT);
  Lines:= SplitOut(Text);
  Assert.Contains(Text, 'TRACE OPERAT.NAME');
  Assert.Contains(Text, '/// ANCHOR');
  Assert.Contains(Text, '/// WRITE');
  Assert.Contains(Text, '[01] BINDS dxDBGrid1OperationVName');
  Assert.Contains(Text, '(Blueprint4.dfm:4534)');
  Assert.Contains(Text, 'Micronite2027 + MicroniteMW1Service + SQL AS OF', 'the trace''s own INDEX line is kept');
  Assert.Contains(Text, '///   VIA dxDBGrid1OperationV', 'a continuation line keeps a visible indent');
  Assert.AreEqual(0, Pos('REGENERATE', Text));
  Assert.AreEqual(0, Pos('C:\a.sqlite', Text));  // dl:ok hardcoded-absolute-path@7b38 -- synthetic test input: names no real location and reaches no filesystem call
  { paragraphs: the blank line before ANCHOR survives as an empty /// line }
  var SawBlankBeforeAnchor: Boolean:= False;
  for var I: Integer:= 1 to High(Lines) do
    if (Lines[I] = '/// ANCHOR') and (Lines[I - 1] = '///') then SawBlankBeforeAnchor:= True;
  Assert.IsTrue(SawBlankBeforeAnchor, 'paragraph break before ANCHOR');
end;

{ ---- glue ---- }

procedure TReportGlueTests.TypeAtResolvedIsRead;
const
  OUT_JSON =
    '{"file":"C:/Projects/DB/ORM3/CLIENT/Blueprint4.pas","line":414,"col":10,' +
    '"token":"dxDBGrid1OperationVName","containing":"Blueprint4.TfrmBlueprint4.dxDBGrid1OperationVName",' +
    '"resolved":"Blueprint4.TfrmBlueprint4.dxDBGrid1OperationVName","signature":"TcxGridDBColumn",' +
    '"note":"","owner_type_fallback":false}(loaded defaults from C:\Projects\.drag-lint.json)';
begin
  Assert.AreEqual('Blueprint4.TfrmBlueprint4.dxDBGrid1OperationVName', ParseTypeAtResolved(OUT_JSON));
  Assert.AreEqual('A.B', ParseTypeAtResolved('drag-lint: note: stale' + CRLF + '{"resolved":"A.B"}'));
end;

procedure TReportGlueTests.TypeAtGarbageGivesEmpty;
begin
  Assert.AreEqual('', ParseTypeAtResolved(''));
  Assert.AreEqual('', ParseTypeAtResolved('ERROR: no index'));
  Assert.AreEqual('', ParseTypeAtResolved('{"token":"x","resolved":""}'));
  Assert.AreEqual('', ParseTypeAtResolved('{not json'));
end;

procedure TReportGlueTests.DfmRootObjectIsParsed;
var
  N, C: string;
begin
  Assert.IsTrue(ParseDfmRootObject('object frmBlueprint4: TfrmBlueprint4', N, C));
  Assert.AreEqual('frmBlueprint4', N);
  Assert.AreEqual('TfrmBlueprint4', C);
  Assert.IsTrue(ParseDfmRootObject('  inherited frmChild : TfrmChild', N, C));
  Assert.AreEqual('frmChild', N);
  Assert.IsFalse(ParseDfmRootObject('TPF0'#0'binary', N, C));
  Assert.IsFalse(ParseDfmRootObject('', N, C));
end;

procedure TReportGlueTests.FormControlTargetUsesInstanceName;
begin
  Assert.AreEqual('frmBlueprint4.dxDBGrid1OperationVName',
    FormControlTarget('Blueprint4.TfrmBlueprint4.dxDBGrid1OperationVName', 'frmBlueprint4', 'TfrmBlueprint4'));
  Assert.AreEqual('frmX.Edit1',
    FormControlTarget('My.Dotted.Unit.TfrmX.Edit1', 'frmX', 'tfrmx'), 'class compare ignores case');
end;

procedure TReportGlueTests.FormControlTargetLeavesOthersAlone;
begin
  { an ORM property: the class is not the form's root class }
  Assert.AreEqual('uCAUSFAIL.TmcCAUSFAIL.REASON',
    FormControlTarget('uCAUSFAIL.TmcCAUSFAIL.REASON', 'frmCausFail', 'TfrmCausFail'));
  { already an instance target }
  Assert.AreEqual('frmBlueprint4.dxDBGrid1OperationVName',
    FormControlTarget('frmBlueprint4.dxDBGrid1OperationVName', 'frmBlueprint4', 'TfrmBlueprint4'));
  { no DFM root known }
  Assert.AreEqual('U.TfrmA.Edit1', FormControlTarget('U.TfrmA.Edit1', '', ''));
end;

procedure TReportGlueTests.UnitNameOfMemberQName;
begin
  Assert.AreEqual('Blueprint4', QNameUnitName('Blueprint4.TfrmBlueprint4.dxDBGrid1OperationVName'));
  Assert.AreEqual('My.Dotted.Unit', QNameUnitName('My.Dotted.Unit.TfrmX.Edit1'));
  Assert.AreEqual('', QNameUnitName('frmX.Edit1'), 'an instance target names no unit');
  Assert.AreEqual('', QNameUnitName(''));
end;

procedure TReportGlueTests.OnlyControlQuestionsConvert;
begin
  Assert.IsTrue(QuestionTakesFormControl('feeds-from'));
  Assert.IsTrue(QuestionTakesFormControl('lands-where'));
  Assert.IsTrue(QuestionTakesFormControl('round-trip'));
  Assert.IsFalse(QuestionTakesFormControl('who-writes'));
  Assert.IsFalse(QuestionTakesFormControl('butterfly'));
end;

procedure TReportGlueTests.TargetValidation;
begin
  Assert.IsTrue(IsValidReportTarget('Unit.TFoo.Bar'));
  Assert.IsFalse(IsValidReportTarget(''));
  Assert.IsFalse(IsValidReportTarget('   '));
  Assert.IsFalse(IsValidReportTarget('Unit."Bad'));
end;

procedure TReportGlueTests.CmdLineCarriesEveryArgument;
var
  Cmd: string;
begin
  Cmd:= BuildAskReportCmdLine('C:\PS\pwsh.exe', 'C:\R\charts\src\Ask-Report.ps1', 'who-writes',  // dl:ok hardcoded-absolute-path@a8ba -- synthetic test input: names no real location and reaches no filesystem call
                              'Unit.TFoo.FBar', 'C:\P\Unit.pas', 'C:\E\drag-lint.exe');  // dl:ok hardcoded-absolute-path@1799 -- synthetic test input: names no real location and reaches no filesystem call
  Assert.IsTrue(StartsStr('"C:\PS\pwsh.exe" -NoProfile', Cmd), Cmd);
  Assert.Contains(Cmd, '-File "C:\R\charts\src\Ask-Report.ps1"');
  Assert.Contains(Cmd, '-Question who-writes');
  Assert.Contains(Cmd, '-Target "Unit.TFoo.FBar"');
  Assert.Contains(Cmd, '-In "C:\P\Unit.pas"');
  Assert.Contains(Cmd, '-Engine "C:\E\drag-lint.exe"');
  Assert.Contains(Cmd, '-Open');
end;

procedure TReportGlueTests.ReasonStripsPrefix;
begin
  Assert.AreEqual('lands-where: X is on TfrmBlueprint4 -- not an ORM object property.',
    AskReportReason('ask-report: lands-where: X is on TfrmBlueprint4 -- not an ORM object property.' + CRLF));
  Assert.AreEqual('plain text', AskReportReason('  plain text  '));
end;

const
  STALE_ERR =
    'ask-report: stale index -- the answer would be short or wrong. Reindex incrementally, then ask again:' + CRLF +
    '  C:\Projects\DB\ORM3\CLIENT\_D-RAG\Micronite2027.sqlite: 3 file(s) changed since it was indexed' + CRLF +
    '    & ''C:\E\drag-lint.exe'' index --project ''C:\Projects\DB\ORM3\CLIENT\Micronite2027.dproj'' --db ''C:\Projects\DB\ORM3\CLIENT\_D-RAG\Micronite2027.sqlite''' + CRLF +
    '  C:\Projects\DB\SQL\drag-lint-sql.sqlite: 1 file(s) changed since it was indexed' + CRLF +
    '    & ''C:\E\drag-lint.exe'' index --all --only SQL' + CRLF;

procedure TReportGlueTests.ReindexCommandsAreParsed;
var
  Cmds: TArray<TReindexCommand>;
begin
  Cmds:= ParseReindexCommands(STALE_ERR);
  Assert.AreEqual(2, Integer(Length(Cmds)));
  Assert.IsTrue(Cmds[0].Kind = rikProject);
  Assert.AreEqual('C:\Projects\DB\ORM3\CLIENT\Micronite2027.dproj', Cmds[0].ProjectFile);  // dl:ok hardcoded-absolute-path@cd1a -- synthetic test input: names no real location and reaches no filesystem call
  Assert.AreEqual('C:\Projects\DB\ORM3\CLIENT\_D-RAG\Micronite2027.sqlite', Cmds[0].Db);  // dl:ok hardcoded-absolute-path@9464 -- synthetic test input: names no real location and reaches no filesystem call
  Assert.IsTrue(Cmds[1].Kind = rikSection);
  Assert.AreEqual('SQL', Cmds[1].Section);
end;

procedure TReportGlueTests.FolderTargetIndexIsNeverAccepted;
begin
  Assert.AreEqual(0, Integer(Length(ParseReindexCommands(
    '    & ''C:\E\drag-lint.exe'' index ''C:\Projects\DB\ORM3\CLIENT'' --db ''C:\x.sqlite'''))));
  Assert.AreEqual(0, Integer(Length(ParseReindexCommands(
    '    & ''C:\E\drag-lint.exe'' index --project ''C:\P\A.dproj'' --db ''C:\x.sqlite'' --rebuild'))),
    'a rebuild is not the incremental job');
  Assert.AreEqual(0, Integer(Length(ParseReindexCommands(''))));
end;

initialization
  TDUnitX.RegisterTestFixture(TReportCatalogTests);
  TDUnitX.RegisterTestFixture(TReportFormatterTests);
  TDUnitX.RegisterTestFixture(TReportGlueTests);

end.
