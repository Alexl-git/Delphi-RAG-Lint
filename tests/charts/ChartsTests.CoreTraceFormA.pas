unit ChartsTests.CoreTraceFormA;

(* Cases for DRagLint.Charts.Trace.FormA, the Form A model of the round-trip question (a port of
  charts\src\Trace.FormA.ps1). The expected texts and refusal messages are what the PowerShell
  printed for the same calls in Test-RoundTripHelpers.ps1 section 2 (task-2-harvest.md of the d1
  ledger); the PS output is the reference. The model is pure; only the round trip over the committed
  fixtures under tests\charts\fixtures\roundtrip reads files (the repo root is DRAGLINT_REPO_ROOT,
  else the first parent of the working directory holding them). *)

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TCoreTraceFormATests = class
  public
    [Test] procedure SyntheticModelWritesThePowerShellText;
    [Test] procedure WrittenTextReadsBackByteIdentical;
    [Test] procedure CommittedFixturesRoundTrip;
    [Test] procedure ReadRecomputesTheCounts;
    [Test] procedure StepWithoutAnchorIsRefused;
    [Test] procedure NonAsciiIsRefused;
    [Test] procedure NoteWithSemicolonSpaceIsRefused;
    [Test] procedure ConditionsAreVerbatimAndUnquoted;
    [Test] procedure TitleQuoteIsRefusedTwice;
    [Test] procedure TextGuardRefusesTheSixteenAndAcceptsTheThree;
    [Test] procedure StopsIsUnresolvedInEverySection;
    [Test] procedure SectionNoteOnlyOnAnEmptySection;
    [Test] procedure UnclickableFindsTheIndexZeroAnchor;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, DRagLint.Charts.Trace.FormA;

const
  REPO_ROOT_ENV = 'DRAGLINT_REPO_ROOT';
  FIXTURE_REL = 'tests\charts\fixtures\roundtrip\OPERAT_NAME.dlgraph';
  CRLF = #13#10;
  MIN_FIXTURES = 6;
  { section 2: the model of Test-RoundTripHelpers.ps1:136-157 }
  SYN_STEPS = 7;
  SYN_CONDS = 2;
  SYN_CROSSINGS = 1;
  SYN_UNRESOLVED = 1;
  SYN_ANCHORS = 12;
  SYN_END = 'END TRACE  7 steps, 2 conditions, 1 crossings, 1 unresolved.';
  { the model-stops text: 7 sections }
  STOPS_STEPS = 8;
  STOPS_CONDS = 1;
  STOPS_UNRESOLVED = 7;
  STOPS_SECTIONS = 7;
  STOPS_SERVER_LINES = 2;
  STOPS_VERBATIM = 'UNLESS SQL = '''' @uGenericTableRoute.pas:196';
  GUARD_CASE_COUNT = 16;
  GUARD_REFUSED = 16;
  GUARD_ACCEPTED_COUNT = 3;
  HUNDRED = 100;
  E_ACUTE = $E9;
  UNCLICKABLE_COUNT = 3;

function FindUp(const pRel: string): string;
begin
  Result:= '';
  var Root:= GetEnvironmentVariable(REPO_ROOT_ENV);
  if (Root <> '') and TFile.Exists(TPath.Combine(Root, pRel)) then
    Exit(TPath.Combine(Root, pRel));
  var Dir:= GetCurrentDir;
  while Dir <> '' do
  begin
    if TFile.Exists(TPath.Combine(Dir, pRel)) then
      Exit(TPath.Combine(Dir, pRel));
    var Up:= ExtractFileDir(ExcludeTrailingPathDelimiter(Dir));
    if SameText(Up, Dir) then
      Break;
    Dir:= Up;
  end;
end;

function Lines(const pLines: array of string): string;
begin
  Result:= '';
  for var L in pLines do
    Result:= Result + L + CRLF;
end;

{ the section-2 model, built exactly as the script builds it }
function BuildSynthetic: TTrace;
begin
  Result:= NewTrace('OPERAT.NAME', 'How OPERAT.NAME reaches frmBlueprint4.dxDBGrid1OperationVName and goes back',
    'frmBlueprint4.dxDBGrid1OperationVName', 'Micronite2027 + MicroniteMW1Service + SQL', '2026-09-24',
    'drag-lint ask round-trip --target frmBlueprint4.dxDBGrid1OperationVName', 'client -> pipe -> server -> database');
  var SecA:= AddTraceSection(Result, 'ANCHOR');
  var S1:= NewTraceStep('step', 'BINDS dxDBGrid1OperationVName : TcxGridDBColumn ONTO Name', 'Blueprint4.dfm:4534', '', '', 'DataBinding.FieldName');
  SecA.Items.Add(S1);
  S1.Children.Add(NewTraceFacet('VIA', 'dxDBGrid1OperationV.DataController.DataSource = Blueprint4_Model.dsrOperation',
    'Blueprint4.dfm:4497', 'dangling: module Blueprint4_Model is declared nowhere in this index'));
  SecA.Items.Add(NewTraceStep('step', 'CALLS GetpdsrOperation', 'Blueprint4.ViewModel.pas:1263', 'by name', 'TBlueprint_ViewModel', '',
    'in-class-field-reads'));
  var SecW:= AddTraceSection(Result, 'WRITE');
  var S3:= NewTraceStep('step', 'CALLS DoAfterPostOperation', 'Blueprint4.ViewModel.pas:3948', '', 'Create', 'from :639');
  SecW.Items.Add(S3);
  S3.Children.Add(NewTraceCond('UNLESS', 'FSuppressEvents', 'Blueprint4.ViewModel.pas:3950', '', 'E1'));
  var S4:= NewTraceStep('step', 'RECEIVES rspOK', 'Blueprint4.ViewModel.pas:3990', '', 'SendDeltaOperation');
  SecW.Items.Add(S4);
  S4.Children.Add(NewTraceCond('UNLESS', '(GLE <> ERROR_SUCCESS) or (TCommandID(RspHdr.CommandID) <> rspOK)',
    'Blueprint4.ViewModel.pas:3990', 'else FMTOperation.CancelUpdates @Blueprint4.ViewModel.pas:3999', 'E1'));
  var X:= NewTraceStep('crosses', 'process boundary', 'Blueprint4.ViewModel.pas:3985', '', 'SendDeltaOperation');
  SecW.Items.Add(X);
  X.Children.Add(NewTraceFacet('FROM', 'Micronite2027', '', 'the index this side was read from'));
  X.Children.Add(NewTraceFacet('WITH', 'cmdDelta "TABLE=OPERAT|" + sfBinary stream', 'Blueprint4.ViewModel.pas:3985'));
  X.Children.Add(NewTraceFacet('CONTRACT', 'Pipes.Protocol.TCommandID.cmdDelta', 'Pipes.Protocol.pas:55'));
  var SecD:= AddTraceSection(Result, 'DATABASE');
  SecD.Items.Add(NewTraceStep('stops',
    'the UPDATE statement for OPERAT is FDef.UpdateSQL, loaded from FIB$DATASETS_INFO rows the clone does not hold (fb_datasets is empty)',
    'uGenericTableRoute.pas:210', '', 'HandleUpdateRecord', '', 'E4'));
  SecD.Items.Add(NewTraceStep('step', 'WRITES OPERAT.NAME', 'MS1.SQL:2808', 'inferred', '',
    'column NAME of OPERAT in the newest declaration', 'E4', 'SERVER'));
end;

function SyntheticText: string;
begin
  Result:= Lines([
    'TRACE OPERAT.NAME',
    '  TITLE "How OPERAT.NAME reaches frmBlueprint4.dxDBGrid1OperationVName and goes back"',
    '  FROM frmBlueprint4.dxDBGrid1OperationVName',
    '  INDEX Micronite2027 + MicroniteMW1Service + SQL AS OF 2026-09-24',
    '  REGENERATE drag-lint ask round-trip --target frmBlueprint4.dxDBGrid1OperationVName',
    '  TIERS client -> pipe -> server -> database',
    '',
    'ANCHOR',
    '[01] BINDS dxDBGrid1OperationVName : TcxGridDBColumn ONTO Name @Blueprint4.dfm:4534 -- DataBinding.FieldName',
    '       VIA dxDBGrid1OperationV.DataController.DataSource = Blueprint4_Model.dsrOperation @Blueprint4.dfm:4497 -- ' +
      'dangling: module Blueprint4_Model is declared nowhere in this index',
    '[02] CALLS GetpdsrOperation [by name] @Blueprint4.ViewModel.pas:1263 -- in TBlueprint_ViewModel; ask in-class-field-reads',
    '',
    'WRITE',
    '[03] CALLS DoAfterPostOperation @Blueprint4.ViewModel.pas:3948 -- in Create; from :639',
    '       UNLESS FSuppressEvents @Blueprint4.ViewModel.pas:3950 -- ask E1',
    '[04] RECEIVES rspOK @Blueprint4.ViewModel.pas:3990 -- in SendDeltaOperation',
    '       UNLESS (GLE <> ERROR_SUCCESS) or (TCommandID(RspHdr.CommandID) <> rspOK) @Blueprint4.ViewModel.pas:3990 -- ' +
      'else FMTOperation.CancelUpdates @Blueprint4.ViewModel.pas:3999; ask E1',
    '[05] CROSSES process boundary @Blueprint4.ViewModel.pas:3985 -- in SendDeltaOperation',
    '       FROM Micronite2027 -- the index this side was read from',
    '       WITH cmdDelta "TABLE=OPERAT|" + sfBinary stream @Blueprint4.ViewModel.pas:3985',
    '       CONTRACT Pipes.Protocol.TCommandID.cmdDelta @Pipes.Protocol.pas:55',
    '',
    'DATABASE',
    '[06] STOPS the UPDATE statement for OPERAT is FDef.UpdateSQL, loaded from FIB$DATASETS_INFO rows the clone does not hold ' +
      '(fb_datasets is empty) @uGenericTableRoute.pas:210 -- in HandleUpdateRecord; ask E4',
    '[07] SERVER WRITES OPERAT.NAME [inferred] @MS1.SQL:2808 -- column NAME of OPERAT in the newest declaration; ask E4',
    '',
    SYN_END]);
end;

{ the model-stops model: a numbered STOPS in every section, with and without an actor word }
function BuildStops: TTrace;
const
  SEC_NAMES: array[0..6] of string = ('ANCHOR', 'READ', 'WRITE', 'SERVER', 'DATABASE', 'RESPONSE', 'ALSO');
  ACTORS   : array[0..6] of string = ('', 'CLIENT', 'SERVER', 'DATABASE', 'SERVER', 'USER', '');
begin
  Result:= NewTrace('X', 'x', 'x', 'A', '2026-09-28', 'x', 'client -> server');
  for var Q:= 0 to High(SEC_NAMES) do
  begin
    var Sec:= AddTraceSection(Result, SEC_NAMES[Q]);
    Sec.Items.Add(NewTraceStep('stops', 'no fact carries hop ' + IntToStr(Q + 1), 'X.pas:' + IntToStr(Q + 1), '', '', '', '', ACTORS[Q]));
    if SEC_NAMES[Q] = 'SERVER' then
    begin
      var Sq:= NewTraceStep('step', 'CALLS HandleUpdateRecord', 'uGenericTableRoute.pas:208', '', 'HandleUpdateRecord');
      Sec.Items.Add(Sq);
      Sq.Children.Add(NewTraceCond('UNLESS', 'SQL = ''''', 'uGenericTableRoute.pas:196'));
    end;
  end;
end;

function StopsText: string;
begin
  Result:= Lines([
    'TRACE X', '  TITLE "x"', '  FROM x', '  INDEX A AS OF 2026-09-28', '  REGENERATE x', '  TIERS client -> server', '',
    'ANCHOR', '[01] STOPS no fact carries hop 1 @X.pas:1', '',
    'READ', '[02] CLIENT STOPS no fact carries hop 2 @X.pas:2', '',
    'WRITE', '[03] SERVER STOPS no fact carries hop 3 @X.pas:3', '',
    'SERVER', '[04] DATABASE STOPS no fact carries hop 4 @X.pas:4',
    '[05] CALLS HandleUpdateRecord @uGenericTableRoute.pas:208 -- in HandleUpdateRecord',
    '       ' + STOPS_VERBATIM, '',
    'DATABASE', '[06] SERVER STOPS no fact carries hop 5 @X.pas:5', '',
    'RESPONSE', '[07] USER STOPS no fact carries hop 6 @X.pas:6', '',
    'ALSO', '[08] STOPS no fact carries hop 7 @X.pas:7', '',
    'END TRACE  8 steps, 1 conditions, 0 crossings, 7 unresolved.']);
end;

{ the message of the EChartsTrace pProc raises ('' when it raises none) }
function RefusalOf(pProc: TProc): string;
begin
  Result:= '';
  try
    pProc();
  except
    on E: EChartsTrace do
      Result:= E.Message;
  end;
end;

function StepRefusal(const pKind, pText, pAnchor: string): string;
begin
  Result:= RefusalOf(procedure
    begin
      NewTraceStep(pKind, pText, pAnchor).Free;
    end);
end;

function FacetRefusal(const pText: string): string;
begin
  Result:= RefusalOf(procedure
    begin
      NewTraceFacet('VIA', pText, 'X.pas:1').Free;
    end);
end;

function CondRefusal(const pCondition: string): string;
begin
  Result:= RefusalOf(procedure
    begin
      NewTraceCond('WHEN', pCondition, 'X.pas:1').Free;
    end);
end;

function WriteRefusal(pTrace: TTrace): string;
begin
  Result:= RefusalOf(procedure
    begin
      WriteFormA(pTrace);
    end);
end;

function ReadRefusal(const pText: string): string;
begin
  Result:= RefusalOf(procedure
    begin
      ReadFormA(pText).Free;
    end);
end;

function RoundTrip(const pText: string): string;
begin
  var Back:= ReadFormA(pText);
  try
    Result:= WriteFormA(Back);
  finally
    Back.Free;
  end;
end;

function OneStepTrace(out pItem: TTraceItem): TTrace;
begin
  Result:= NewTrace('X', 'x', 'x', 'A', '2026-09-27', 'x', 'client');
  pItem:= NewTraceStep('step', 'CALLS X', 'X.pas:1');
  AddTraceSection(Result, 'WRITE').Items.Add(pItem);
end;

procedure TCoreTraceFormATests.SyntheticModelWritesThePowerShellText;
begin
  var T:= BuildSynthetic;
  try
    Assert.AreEqual(SyntheticText, WriteFormA(T), 'Write-FormA text');
    var C:= TraceCounts(T);
    Assert.AreEqual(SYN_STEPS, C.Steps, 'steps');
    Assert.AreEqual(SYN_CONDS, C.Conditions, 'conditions');
    Assert.AreEqual(SYN_CROSSINGS, C.Crossings, 'crossings');
    Assert.AreEqual(SYN_UNRESOLVED, C.Unresolved, 'unresolved');
    Assert.AreEqual(SYN_END, FormatTraceEndLine(C), 'END TRACE line');
    Assert.AreEqual(SYN_ANCHORS, TraceAnchors(T), 'anchors');
    Assert.AreEqual(SYN_STEPS, T.Sections[2].Items[1].Number, 'numbers assigned in place');
  finally
    T.Free;
  end;
end;

procedure TCoreTraceFormATests.WrittenTextReadsBackByteIdentical;
begin
  var T:= BuildSynthetic;
  try
    var Text:= WriteFormA(T);
    Assert.AreEqual(Text, RoundTrip(Text), 'synthetic model');
  finally
    T.Free;
  end;
end;

procedure TCoreTraceFormATests.CommittedFixturesRoundTrip;
begin
  var First:= FindUp(FIXTURE_REL);
  if First = '' then
  begin
    Assert.Pass('fixtures missing');
    Exit;
  end;
  var Files:= TDirectory.GetFiles(ExtractFilePath(First), '*.dlgraph');
  Assert.IsTrue(Length(Files) >= MIN_FIXTURES, 'the committed round-trip fixtures: ' + IntToStr(Length(Files)));
  for var F in Files do
  begin
    var Text:= TFile.ReadAllText(F, TEncoding.ASCII);
    Assert.AreEqual(Text, RoundTrip(Text), 'round trip of ' + ExtractFileName(F));
  end;
end;

procedure TCoreTraceFormATests.ReadRecomputesTheCounts;
begin
  var T:= BuildSynthetic;
  try
    var Text:= WriteFormA(T);
    Assert.IsTrue(ReadRefusal(Text.Replace('2 conditions', '9 conditions')).Contains('E-COUNTS'), 'declared 9 conditions');
    Assert.IsTrue(ReadRefusal(Text.Replace(CRLF, #10)).Contains('E-EOL'), 'bare LF');
    Assert.IsTrue(ReadRefusal(Copy(Text, 1, Pos('END TRACE', Text) - 1)).Contains('E-NO-END'), 'no END TRACE');
    Assert.IsTrue(ReadRefusal(Text.Replace('END TRACE', 'garbage line' + CRLF + 'END TRACE')).Contains('unparseable line: garbage line'),
      'unparseable line');
  finally
    T.Free;
  end;
end;

procedure TCoreTraceFormATests.StepWithoutAnchorIsRefused;
begin
  Assert.IsTrue(StepRefusal('step', 'CALLS X', '').Contains('AC-11'), 'AC-11');
end;

procedure TCoreTraceFormATests.NonAsciiIsRefused;
begin
  var Item: TTraceItem;
  var T:= OneStepTrace(Item);
  try
    Item.Children.Add(NewTraceCond('UNLESS', 'a ' + Char(E_ACUTE) + ' b', 'X.pas:2'));
    Assert.IsTrue(WriteRefusal(T).Contains('not 7-bit ASCII'), 'non-ASCII condition');
  finally
    T.Free;
  end;
end;

procedure TCoreTraceFormATests.NoteWithSemicolonSpaceIsRefused;
begin
  var Item: TTraceItem;
  var T:= OneStepTrace(Item);
  try
    Item.Note:= 'a; b';
    Assert.AreNotEqual('', WriteRefusal(T), 'note with "; "');
  finally
    T.Free;
  end;
end;

procedure TCoreTraceFormATests.ConditionsAreVerbatimAndUnquoted;
begin
  var Item: TTraceItem;
  var T:= OneStepTrace(Item);
  try
    Item.Children.Add(NewTraceCond('WHEN', 'S = "x"', 'X.pas:2'));
    Item.Children.Add(NewTraceCond('UNLESS', 'I--1 > 0', 'X.pas:3', 'else Exit'));
    var Text:= WriteFormA(T);
    Assert.IsTrue(Text.Contains('       WHEN S = "x" @X.pas:2' + CRLF + '       UNLESS I--1 > 0 @X.pas:3 -- else Exit' + CRLF), 'verbatim lines');
    Assert.AreEqual(Text, RoundTrip(Text), 'round trip');
    var Back:= ReadFormA(Text);
    try
      Assert.AreEqual('S = "x"', Back.Sections[0].Items[0].Children[0].Condition, 'condition read back');
    finally
      Back.Free;
    end;
  finally
    T.Free;
  end;
  Assert.IsTrue(CondRefusal('A @X.pas:3').Contains('reads as its anchor'), 'anchor shape');
  Assert.IsTrue(CondRefusal('A -- B').Contains('reads as its note'), 'inner note separator');
  Assert.IsTrue(CondRefusal('A --').Contains('reads as its note'), 'trailing note separator');
end;

procedure TCoreTraceFormATests.TitleQuoteIsRefusedTwice;
begin
  Assert.IsTrue(RefusalOf(procedure
    begin
      NewTrace('X', 'a"b', 'x', 'A', '2026-09-28', 'x', 'client').Free;
    end).Contains('double-quote'), 'NewTrace');
  var T:= NewTrace('X', 'ab', 'x', 'A', '2026-09-28', 'x', 'client');
  try
    T.Title:= 'a""b';
    AddTraceSection(T, 'WRITE').Items.Add(NewTraceStep('step', 'CALLS X', 'X.pas:1'));
    Assert.IsTrue(WriteRefusal(T).Contains('double-quote'), 'WriteFormA');
  finally
    T.Free;
  end;
end;

procedure TCoreTraceFormATests.TextGuardRefusesTheSixteenAndAcceptsTheThree;
const
  STEP_CASES: array[0..13] of string = ('SERVER', 'STOPS', 'CROSSES', 'user', 'CALLS x --', 'WHEN x', 'UNLESS', 'GUARD x',
    'UNRESOLVED x', 'READ STOPS x', 'ALSO CROSSES x', '-- x', '[inferred]', '@X.pas:1');
  FACET_CASES: array[0..1] of string = ('x --', '-- x');
begin
  var Refused:= 0;
  var Accepted:= '';
  for var S in STEP_CASES do
    if StepRefusal('step', S, 'X.pas:1') <> '' then Inc(Refused) else Accepted:= Accepted + ',step:' + S;
  for var S in FACET_CASES do
    if FacetRefusal(S) <> '' then Inc(Refused) else Accepted:= Accepted + ',facet:' + S;
  Assert.AreEqual(GUARD_CASE_COUNT, Length(STEP_CASES) + Length(FACET_CASES), 'case count');
  Assert.AreEqual(GUARD_REFUSED, Refused, 'refused; accepted [' + Accepted + ']');
  { what the guard must NOT refuse: a facet naming a tier, a step text with a -- inside a word }
  var Wrong:= 0;
  if FacetRefusal('SERVER') <> '' then Inc(Wrong);
  if StepRefusal('step', 'CALLS a--b', 'X.pas:1') <> '' then Inc(Wrong);
  if StepRefusal('step', 'READS WHEN_FLAG', 'X.pas:1') <> '' then Inc(Wrong);
  Assert.AreEqual(0, Wrong, 'wrongly refused of ' + IntToStr(GUARD_ACCEPTED_COUNT));
end;

procedure TCoreTraceFormATests.StopsIsUnresolvedInEverySection;
begin
  var T:= BuildStops;
  try
    var Text:= WriteFormA(T);
    Assert.AreEqual(StopsText, Text, 'model-stops text');
    var C:= TraceCounts(T);
    Assert.AreEqual(STOPS_STEPS, C.Steps, 'steps');
    Assert.AreEqual(STOPS_CONDS, C.Conditions, 'conditions');
    Assert.AreEqual(0, C.Crossings, 'crossings');
    Assert.AreEqual(STOPS_UNRESOLVED, C.Unresolved, 'unresolved');
    Assert.AreEqual<Integer>(STOPS_SECTIONS, T.Sections.Count, 'sections');
    Assert.IsTrue(Text.Contains(STOPS_VERBATIM), 'Pascal condition with empty string is verbatim');
    var Server:= 0;
    for var L in Text.Split([CRLF]) do
      if (L <> '') and (L[1] = '[') and L.Contains('] SERVER STOPS ') then Inc(Server);
    Assert.AreEqual(STOPS_SERVER_LINES, Server, 'SERVER STOPS lines');
    Assert.AreEqual(Text, RoundTrip(Text), 'round trip');
  finally
    T.Free;
  end;
end;

procedure TCoreTraceFormATests.SectionNoteOnlyOnAnEmptySection;
begin
  var Item: TTraceItem;
  var T:= OneStepTrace(Item);
  try
    T.Sections[0].Note:= 'not walked';
    Assert.IsTrue(WriteRefusal(T).Contains('steps AND a note'), 'steps and a note');
    T.Sections[0].Name:= 'DERIVED';
    Assert.AreEqual('', WriteRefusal(T), 'DERIVED may lead its rows with a note');
    T.Sections[0].Name:= 'WRITE';
    T.Sections[0].Items.Clear;
    var Text:= WriteFormA(T);
    Assert.IsTrue(Text.Contains('WRITE' + CRLF + '  -- not walked' + CRLF), 'empty section note');
    Assert.AreEqual(Text, RoundTrip(Text), 'round trip');
  finally
    T.Free;
  end;
end;

procedure TCoreTraceFormATests.UnclickableFindsTheIndexZeroAnchor;
begin
  var Bad:= TraceUnclickable(Lines([
    '[01] CALLS a @index:0',
    '[02] CALLS b @B.pas:5 -- see @C.pas:6',
    '[03] CALLS c -- see @C.pas:6',
    '[04] CALLS d @D.pas:0',
    '[' + IntToStr(HUNDRED) + '] CALLS e @E.dfm:7',
    'not a numbered line @index:0']));
  Assert.AreEqual<Integer>(UNCLICKABLE_COUNT, Length(Bad), 'unclickable lines');
  Assert.AreEqual('[01] CALLS a @index:0', Bad[0], 'index:0');
  Assert.AreEqual('[03] CALLS c -- see @C.pas:6', Bad[1], 'anchor only in the note');
  Assert.AreEqual('[04] CALLS d @D.pas:0', Bad[2], 'line 0');
end;

end.
