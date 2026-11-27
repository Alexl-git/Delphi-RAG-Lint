unit ChartsTests.ReportHeader;

{ Cases for DRagLint.Charts.ReportHeader: the header contract of a dl-charts answer --
  the sentence line, the COMMAND line, their DocInsight forms, the legacy header and
  the same-question rule (H1-H4).

  1.56 QE-1.1: BuildCommandLine prints CLI style ('--target "t" --surface-cap 40');
  ParseCommandLine reads that AND the PowerShell style written up to 1.55
  ('-Target "t" -SurfaceCap 40'), and both give the same command. The fixtures below that
  carry the PowerShell style are KEPT as they are: they are the old form a saved report holds.

  Fixtures are CRLF-joined strings exactly as Ask-Report.ps1 -Plain and
  DRagLint.Charts.DocInsight write them; Lines() splits them back into lines. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TReportHeaderTests = class
  public
    [Test] procedure PlainHeaderParses;
    [Test] procedure DocInsightHeaderParsesAcrossWrap;
    [Test] procedure LegacyHeaderParsesWithoutCommand;
    [Test] procedure NotAReportReturnsFalse;
    [Test] procedure WrappedCommandLineIsJoined;          // Review Focus 2
    [Test] procedure QuotedValuesWithSpacesRoundTrip;     // Review Focus 3
    [Test] procedure BuildUsesCanonicalOrder;
    [Test] procedure SameQuestionIgnoresOrderQuotingAndCase;
    [Test] procedure SameQuestionNamesEachDifference;
    [Test] procedure DifferentQuestionIdIsNotSame;
    [Test] procedure XmlUnescapeHandlesEntities;
    [Test] procedure BuildPrintsCliStyle;                  // 1.56 QE-1.1
    [Test] procedure CliStyleLineParses;
    [Test] procedure CliStyleHeaderParsesPlainAndDocInsight;
    [Test] procedure OldAndNewStyleAreTheSameQuestion;
    [Test] procedure BuiltLineRoundTripsFromBothStyles;
    [Test] procedure UnknownNamesAreWrittenKebab;
    [Test] procedure RepeatedNameAcrossStylesKeepsOneArgument;
    [Test] procedure NegativeNumberIsAValueInBothStyles;
    [Test] procedure DetectCommandStyleTellsTheStylesApart;
  end;

implementation

uses
  System.SysUtils, DRagLint.Charts.ReportHeader;

const
  CRLF = #13#10;
  PLAIN_SENTENCE = 'Who writes this field (drag-lint report who-writes) for OPERAT.NAME, asked on 2026-10-10 14:32, engine 1.27.0.';
  PLAIN_NEW = PLAIN_SENTENCE + CRLF +
              'COMMAND who-writes -Target "OPERAT.NAME" -Project "C:\P\A.dproj" -Depth 3' + CRLF + 'BUNDLE x' + CRLF;
  DOC_NEW   = '/// <remarks>' + CRLF +
              '/// Who writes this field (drag-lint report who-writes) for OPERAT.NAME, asked on 2026-10-10 14:32,' + CRLF +
              '///   engine 1.27.0.' + CRLF +
              '/// COMMAND who-writes -Target "OPERAT.NAME" -Project "C:\P\A.dproj" -Depth 3' + CRLF +
              '///' + CRLF + '/// Totals: 1 x.' + CRLF + '/// </remarks>' + CRLF;
  DOC_LEGACY= '/// <remarks>' + CRLF +
              '/// Who writes this field (drag-lint report who-writes) for Blueprint4.TfrmBlueprint4.FNoRecursion,' + CRLF +
              '///   asked on 2026-10-06.' + CRLF + '///' + CRLF + '/// Totals: 26 write sites / 26 routines.' + CRLF + '/// </remarks>' + CRLF;
  DOC_WRAPPED_COMMAND = '/// <remarks>' + CRLF +
              '/// Who writes this field (drag-lint report who-writes) for OPERAT.NAME, asked on 2026-10-10 14:32,' + CRLF +
              '///   engine 1.27.0.' + CRLF +
              '/// COMMAND who-writes -Target "OPERAT.NAME"' + CRLF +
              '///   -Project "C:\P\A.dproj"' + CRLF +
              '///' + CRLF + '/// </remarks>' + CRLF;
  FIXTURE_PROJECT = 'C:\P\A.dproj'; // dl:ok hardcoded-absolute-path@88fb -- synthetic test input: names no real location and reaches no filesystem call
  SPACED_PROJECT = 'C:\My Projects\A.dproj'; // dl:ok hardcoded-absolute-path@e1c9 -- synthetic test input: names no real location and reaches no filesystem call
  WRAPPED_SENTENCE_HEADER_LINES = 3;
  WRAPPED_COMMAND_HEADER_LINES = 4;
  OLD_LINE = 'COMMAND class-surface -Target "U.TFoo" -To "U.TBar.Baz" -Project "C:\P\A.dproj" -Depth 3 -Cap 40 ' +
             '-SurfaceCap 25 -Control "frmX.ctl" -Mode write -MaxRows 7';
  NEW_LINE = 'COMMAND class-surface --target "U.TFoo" --to "U.TBar.Baz" --project "C:\P\A.dproj" --depth 3 --cap 40 ' +
             '--surface-cap 25 --control "frmX.ctl" --mode write --max-rows 7';
  NEW_BUILT = 'class-surface --target "U.TFoo" --to "U.TBar.Baz" --project "C:\P\A.dproj" --depth 3 --cap 40 ' +
             '--surface-cap 25 --control "frmX.ctl" --mode write --max-rows 7';
  PLAIN_CLI = PLAIN_SENTENCE + CRLF +
              'COMMAND who-writes --target "OPERAT.NAME" --project "C:\P\A.dproj" --depth 3' + CRLF + 'BUNDLE x' + CRLF;
  DOC_CLI_WRAPPED = '/// <remarks>' + CRLF +
              '/// Who writes this field (drag-lint report who-writes) for OPERAT.NAME, asked on 2026-10-10 14:32,' + CRLF +
              '///   engine 1.27.0.' + CRLF +
              '/// COMMAND who-writes --target "OPERAT.NAME"' + CRLF +
              '///   --project "C:\P\A.dproj" --surface-cap 25' + CRLF +
              '///' + CRLF + '/// </remarks>' + CRLF;
  KNOWN_ARG_COUNT = 9;
  NOT_A_REPORT = 'unit Foo;' + CRLF + CRLF + 'interface' + CRLF;

function Lines(const pText: string): TArray<string>;
begin
  Result:= pText.Split([CRLF]);
end;

function Cmd(const pText: string): TReportCommand;
begin
  Assert.IsTrue(ParseCommandLine(pText, Result), 'ParseCommandLine failed on: ' + pText);
end;

procedure TReportHeaderTests.PlainHeaderParses;
begin
  var H: TReportHeader;
  Assert.IsTrue(ParseReportHeader(Lines(PLAIN_NEW), H));
  Assert.AreEqual(Ord(rfPlain), Ord(H.Form));
  Assert.AreEqual('Who writes this field', H.Phrase);
  Assert.AreEqual('who-writes', H.QuestionId);
  Assert.AreEqual('OPERAT.NAME', H.Target);
  Assert.AreEqual('2026-10-10 14:32', H.AskedOn);
  Assert.AreEqual('1.27.0', H.EngineVersion);
  Assert.IsTrue(H.HasCommand);
  Assert.AreEqual('who-writes', H.Command.Question);
  Assert.AreEqual(FIXTURE_PROJECT, H.Command.Get('Project'));
  Assert.AreEqual('3', H.Command.Get('depth'));
  Assert.AreEqual(2, H.HeaderLines);
end;

procedure TReportHeaderTests.DocInsightHeaderParsesAcrossWrap;
begin
  var H: TReportHeader;
  Assert.IsTrue(ParseReportHeader(Lines(DOC_NEW), H));
  Assert.AreEqual(Ord(rfDocInsight), Ord(H.Form));
  Assert.AreEqual('who-writes', H.QuestionId);
  Assert.AreEqual('OPERAT.NAME', H.Target);
  Assert.AreEqual('2026-10-10 14:32', H.AskedOn);
  Assert.AreEqual('1.27.0', H.EngineVersion);
  Assert.AreEqual(FIXTURE_PROJECT, H.Command.Get('Project'));
  Assert.AreEqual(WRAPPED_SENTENCE_HEADER_LINES, H.HeaderLines, 'wrapped sentence (2) + COMMAND (1); <remarks> not counted');
end;

procedure TReportHeaderTests.LegacyHeaderParsesWithoutCommand;
begin
  var H: TReportHeader;
  Assert.IsTrue(ParseReportHeader(Lines(DOC_LEGACY), H));
  Assert.AreEqual(Ord(rfDocInsight), Ord(H.Form));
  Assert.AreEqual('Blueprint4.TfrmBlueprint4.FNoRecursion', H.Target);
  Assert.AreEqual('2026-10-06', H.AskedOn);
  Assert.AreEqual('', H.EngineVersion);
  Assert.IsFalse(H.HasCommand);
  Assert.IsTrue(H.Command.IsEmpty);
  Assert.AreEqual(2, H.HeaderLines);
end;

procedure TReportHeaderTests.NotAReportReturnsFalse;
begin
  var H: TReportHeader;
  Assert.IsFalse(ParseReportHeader(Lines(NOT_A_REPORT), H));
  Assert.IsFalse(ParseReportHeader(nil, H));
end;

procedure TReportHeaderTests.WrappedCommandLineIsJoined;
begin
  var H: TReportHeader;
  Assert.IsTrue(ParseReportHeader(Lines(DOC_WRAPPED_COMMAND), H));
  Assert.AreEqual('OPERAT.NAME', H.Command.Get('Target'));
  Assert.AreEqual(FIXTURE_PROJECT, H.Command.Get('Project'));
  Assert.AreEqual(WRAPPED_COMMAND_HEADER_LINES, H.HeaderLines, 'sentence (2) + COMMAND and its continuation (2)');
end;

procedure TReportHeaderTests.QuotedValuesWithSpacesRoundTrip;
begin
  var C:= Cmd('COMMAND who-writes -Project "C:\My Projects\A.dproj" -Target "frmX.ctl"');
  Assert.AreEqual(SPACED_PROJECT, C.Get('Project'));
  Assert.AreEqual('who-writes --target "frmX.ctl" --project "C:\My Projects\A.dproj"', BuildCommandLine(C));
end;

procedure TReportHeaderTests.BuildUsesCanonicalOrder;
begin
  Assert.AreEqual('q --target "t" --project "p" --depth 3', BuildCommandLine(Cmd('q -Depth 3 -Project "p" -Target "t"')));
  Assert.AreEqual('q --target "t" --extra "a b" --other x', BuildCommandLine(Cmd('q -Extra "a b" -Target "t" -Other x')),
    'unknown names go last in input order, quoted only when the value has a space');
end;

procedure TReportHeaderTests.SameQuestionIgnoresOrderQuotingAndCase;
begin
  var Differing: TArray<string>;
  Assert.IsTrue(SameQuestion(Cmd('who-writes -target "a" -DEPTH 03'), Cmd('WHO-WRITES -Depth 3 -Target "A"'), Differing));
  Assert.AreEqual(0, Integer(Length(Differing)));
end;

procedure TReportHeaderTests.SameQuestionNamesEachDifference;
begin
  var Differing: TArray<string>;
  Assert.IsFalse(SameQuestion(Cmd('q -Depth 3'), Cmd('q -Depth 5 -Cap 40'), Differing));
  Assert.AreEqual('Cap: (absent) vs 40|Depth: 3 vs 5', string.Join('|', Differing));
end;

procedure TReportHeaderTests.DifferentQuestionIdIsNotSame;
begin
  var Differing: TArray<string>;
  Assert.IsFalse(SameQuestion(Cmd('who-writes -Target "a"'), Cmd('who-reads -Target "a"'), Differing));
end;

procedure TReportHeaderTests.XmlUnescapeHandlesEntities;
begin
  Assert.AreEqual('<T> & "', XmlUnescape('&lt;T&gt; &amp; &quot;'));
  Assert.AreEqual('&lt;', XmlUnescape('&amp;lt;'), 'one pass: &amp;lt; is the text &lt;, not <');
end;

procedure TReportHeaderTests.BuildPrintsCliStyle;
begin
  Assert.AreEqual(NEW_BUILT, BuildCommandLine(Cmd(OLD_LINE)), 'every known argument, CLI spelling, canonical order');
  Assert.IsFalse(BuildCommandLine(Cmd(OLD_LINE)).Contains(' -T'), 'the PowerShell style is never written');
end;

procedure TReportHeaderTests.CliStyleLineParses;
begin
  var C:= Cmd(NEW_LINE);
  Assert.AreEqual('class-surface', C.Question);
  Assert.AreEqual(KNOWN_ARG_COUNT, Integer(Length(C.Args)));
  Assert.AreEqual('U.TFoo', C.Get('Target'));
  Assert.AreEqual('U.TBar.Baz', C.Get('To'));
  Assert.AreEqual(FIXTURE_PROJECT, C.Get('Project'));
  Assert.AreEqual('3', C.Get('Depth'));
  Assert.AreEqual('40', C.Get('Cap'));
  Assert.AreEqual('25', C.Get('SurfaceCap'), 'the canonical name finds --surface-cap');
  Assert.AreEqual('25', C.Get('surface-cap'), 'and so does the CLI spelling');
  Assert.AreEqual('frmX.ctl', C.Get('Control'));
  Assert.AreEqual('write', C.Get('Mode'));
  Assert.AreEqual('7', C.Get('MaxRows'));
  Assert.IsTrue(C.Has('max-rows'));
  Assert.IsFalse(C.Has('In'));
  // a known argument is STORED under its canonical name whichever style wrote it
  Assert.AreEqual('Target', C.Args[0].Name);
  Assert.AreEqual('SurfaceCap', C.Args[5].Name);
  Assert.AreEqual('MaxRows', C.Args[8].Name);
  Assert.AreEqual('SurfaceCap', Cmd(OLD_LINE).Args[5].Name);
  Assert.AreEqual('Target', Cmd('q -target "t"').Args[0].Name);
end;

procedure TReportHeaderTests.CliStyleHeaderParsesPlainAndDocInsight;
begin
  var H: TReportHeader;
  Assert.IsTrue(ParseReportHeader(Lines(PLAIN_CLI), H));
  Assert.IsTrue(H.HasCommand);
  Assert.AreEqual('OPERAT.NAME', H.Command.Get('Target'));
  Assert.AreEqual(FIXTURE_PROJECT, H.Command.Get('Project'));
  Assert.AreEqual('3', H.Command.Get('Depth'));
  Assert.AreEqual(2, H.HeaderLines);
  Assert.IsTrue(ParseReportHeader(Lines(DOC_CLI_WRAPPED), H));
  Assert.AreEqual('OPERAT.NAME', H.Command.Get('Target'));
  Assert.AreEqual(FIXTURE_PROJECT, H.Command.Get('Project'), 'a re-wrapped CLI-style COMMAND line is joined');
  Assert.AreEqual('25', H.Command.Get('SurfaceCap'));
  Assert.AreEqual(WRAPPED_COMMAND_HEADER_LINES, H.HeaderLines);
end;

procedure TReportHeaderTests.OldAndNewStyleAreTheSameQuestion;
begin
  var Differing: TArray<string>;
  Assert.IsTrue(SameQuestion(Cmd(OLD_LINE), Cmd(NEW_LINE), Differing), string.Join('|', Differing));
  Assert.AreEqual(0, Integer(Length(Differing)));
  Assert.IsTrue(SameQuestion(Cmd('q -FooBar x -Depth 03'), Cmd('q --depth 3 --foo-bar X'), Differing),
    'an unknown name too: FooBar = foo-bar');
  Assert.IsFalse(SameQuestion(Cmd('q -SurfaceCap 25'), Cmd('q --surface-cap 30 --max-rows 5'), Differing));
  Assert.AreEqual('MaxRows: (absent) vs 5|SurfaceCap: 25 vs 30', string.Join('|', Differing),
    'one line per argument, never one per spelling');
end;

procedure TReportHeaderTests.BuiltLineRoundTripsFromBothStyles;
begin
  var FromOld:= BuildCommandLine(Cmd(OLD_LINE));
  var FromNew:= BuildCommandLine(Cmd(NEW_LINE));
  Assert.AreEqual(FromOld, FromNew, 'the old and the new line build the same text');
  Assert.AreEqual(FromNew, BuildCommandLine(Cmd(FromNew)), 'building what was built changes nothing');
  Assert.AreEqual(FromNew, BuildCommandLine(Cmd('COMMAND ' + FromNew)));
end;

procedure TReportHeaderTests.UnknownNamesAreWrittenKebab;
begin
  Assert.AreEqual('q --target "t" --foo-bar "a b" --other x --flag',
    BuildCommandLine(Cmd('q -FooBar "a b" -Target "t" -Other x -Flag')));
  Assert.AreEqual('q --foo-bar x --abc 1 --a2-b y', BuildCommandLine(Cmd('q --foo-bar x -ABC 1 -A2B y')));
  Assert.AreEqual('FooBar', Cmd('q -FooBar x').Args[0].Name, 'an unknown name is stored as written');
  Assert.AreEqual('foo-bar', Cmd('q --foo-bar x').Args[0].Name);
end;

procedure TReportHeaderTests.RepeatedNameAcrossStylesKeepsOneArgument;
begin
  var C:= Cmd('q -SurfaceCap 25 --target "t" --surface-cap 30');
  Assert.AreEqual(2, Integer(Length(C.Args)));
  Assert.AreEqual('SurfaceCap', C.Args[0].Name, 'first position');
  Assert.AreEqual('30', C.Get('SurfaceCap'), 'last value');
end;

procedure TReportHeaderTests.NegativeNumberIsAValueInBothStyles;
begin
  Assert.AreEqual('-3', Cmd('q -Depth -3').Get('Depth'));
  Assert.AreEqual('-3', Cmd('q --depth -3').Get('Depth'));
  Assert.AreEqual('--x', Cmd('q --mode "--x"').Get('Mode'), 'a quoted token is a value');
  Assert.AreEqual('q --mode "--x"', BuildCommandLine(Cmd('q --mode "--x"')), 'and is quoted again so it re-parses as one');
  Assert.AreEqual('', Cmd('q --flag --depth 2').Get('flag'), 'a name followed by a name has no value');
end;

procedure TReportHeaderTests.DetectCommandStyleTellsTheStylesApart;
begin
  Assert.AreEqual(Ord(csPowerShell), Ord(DetectCommandStyle(OLD_LINE)));
  Assert.AreEqual(Ord(csCli), Ord(DetectCommandStyle(NEW_LINE)));
  Assert.AreEqual(Ord(csCli), Ord(DetectCommandStyle(NEW_BUILT)), 'with or without the COMMAND prefix');
  Assert.AreEqual(Ord(csMixed), Ord(DetectCommandStyle('COMMAND q -Target "t" --depth 3')));
  Assert.AreEqual(Ord(csNone), Ord(DetectCommandStyle('COMMAND q')));
  Assert.AreEqual(Ord(csNone), Ord(DetectCommandStyle('')));
  Assert.AreEqual(Ord(csPowerShell), Ord(DetectCommandStyle('q -Target "--to" -Depth -3')),
    'a quoted token and a negative number are values, not names');
  Assert.AreEqual(Ord(csCli), Ord(DetectCommandStyle('q --target "-To"')));
end;

initialization
  TDUnitX.RegisterTestFixture(TReportHeaderTests);

end.
