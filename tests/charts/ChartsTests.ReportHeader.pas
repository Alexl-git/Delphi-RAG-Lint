unit ChartsTests.ReportHeader;

{ Cases for DRagLint.Charts.ReportHeader: the header contract of a dl-charts answer --
  the sentence line, the COMMAND line, their DocInsight forms, the legacy header and
  the same-question rule (H1-H4).

  Fixtures are CRLF-joined strings exactly as Ask-Report.ps1 -Plain and
  Format-ReportAsDocInsight write them; Lines() splits them back into lines. }

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
    [Test] procedure FormatSentenceMatchesContract;
    [Test] procedure XmlUnescapeHandlesEntities;
  end;

implementation

uses
  System.SysUtils, System.DateUtils, DRagLint.Charts.ReportHeader;

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
  NOT_A_REPORT = 'unit Foo;' + CRLF + CRLF + 'interface' + CRLF;

  ASKED_YEAR = 2026;
  ASKED_MONTH = 10;
  ASKED_DAY = 10;
  ASKED_HOUR = 14;
  ASKED_MINUTE = 32;

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
  Assert.AreEqual('who-writes -Target "frmX.ctl" -Project "C:\My Projects\A.dproj"', BuildCommandLine(C));
end;

procedure TReportHeaderTests.BuildUsesCanonicalOrder;
begin
  Assert.AreEqual('q -Target "t" -Project "p" -Depth 3', BuildCommandLine(Cmd('q -Depth 3 -Project "p" -Target "t"')));
  Assert.AreEqual('q -Target "t" -Extra "a b" -Other x', BuildCommandLine(Cmd('q -Extra "a b" -Target "t" -Other x')),
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

procedure TReportHeaderTests.FormatSentenceMatchesContract;
begin
  var AskedAt:= EncodeDateTime(ASKED_YEAR, ASKED_MONTH, ASKED_DAY, ASKED_HOUR, ASKED_MINUTE, 0, 0);
  Assert.AreEqual(PLAIN_SENTENCE, FormatHeaderSentence('Who writes this field', 'who-writes', 'OPERAT.NAME', AskedAt, '1.27.0'));
end;

procedure TReportHeaderTests.XmlUnescapeHandlesEntities;
begin
  Assert.AreEqual('<T> & "', XmlUnescape('&lt;T&gt; &amp; &quot;'));
  Assert.AreEqual('&lt;', XmlUnescape('&amp;lt;'), 'one pass: &amp;lt; is the text &lt;, not <');
end;

initialization
  TDUnitX.RegisterTestFixture(TReportHeaderTests);

end.
