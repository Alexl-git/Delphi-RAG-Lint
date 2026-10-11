unit ChartsTests.DocInsight;

{ Cases for DRagLint.Charts.DocInsight, the IDE-free DocInsight formatter of a
  dl-charts answer. The byte-for-byte cross-check against the PowerShell port
  (charts\fixtures\docinsight) runs in tests\reportstext through the plugin's
  forwarder; these cases pin what the ENGINE calls directly: the caller's
  phrase, the unknown-question fallback, and the two header lines. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDocInsightTests = class
  public
    [Test] procedure PhraseIsTheCallersCaption;
    [Test] procedure EmptyPhraseFallsBackToReport;
    [Test] procedure HeaderLinesReplaceComposedSentence;
    [Test] procedure CommandWithoutHeaderSentenceIsABodyLine;
  end;

implementation

uses
  System.SysUtils, System.StrUtils, System.Classes, DRagLint.Charts.DocInsight;

const
  CRLF = #13#10;
  ASKED_Y = 2026;
  ASKED_M = 10;
  ASKED_D = 6;
  SENTENCE = 'Who writes this field (drag-lint report who-writes) for OPERAT.NAME, asked on 2026-10-10 14:32, engine 1.27.0.';
  COMMAND = 'COMMAND who-writes -Target "OPERAT.NAME" -Project "C:\Projects\R&D\Client Folder With A Long Name\Micronite2027.dproj" -Depth 3';
  BODY = 'CHART who-writes OPERAT.NAME -- 2 write sites / 1 routines';
  { output line indexes: 0 is '/// <remarks>', 1 the first sentence line }
  L_SENTENCE = 1;
  { legacy: sentence, blank, first finding }
  L_LEGACY_BODY = 3;
  { header: sentence (two lines), COMMAND, blank, first finding }
  L_SENTENCE_WRAP = 2;
  L_COMMAND = 3;
  L_BREAK = 4;
  L_HEADER_BODY = 5;

function Asked: TDateTime;
begin
  Result:= EncodeDate(ASKED_Y, ASKED_M, ASKED_D);
end;

function Lines(const pText: string): TArray<string>;
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

procedure TDocInsightTests.PhraseIsTheCallersCaption;
begin
  var L:= Lines(FormatAnswerAsDocInsight('Who writes this field', 'who-writes', 'X.Y', Asked, BODY));
  Assert.AreEqual('/// <remarks>', L[0]);
  Assert.AreEqual('/// Who writes this field (drag-lint report who-writes) for X.Y, asked on 2026-10-06.', L[L_SENTENCE]);
  Assert.AreEqual('/// Totals: 2 write sites / 1 routines.', L[L_LEGACY_BODY]);
  Assert.AreEqual('/// </remarks>', L[High(L)]);
end;

procedure TDocInsightTests.EmptyPhraseFallsBackToReport;
begin
  var L:= Lines(FormatAnswerAsDocInsight('', 'no-such-question', 'X', Asked, ''));
  Assert.AreEqual('/// ' + DOCINSIGHT_UNKNOWN_PHRASE + ' (drag-lint report no-such-question) for X, asked on 2026-10-06.', L[L_SENTENCE]);
  Assert.Contains(L[L_LEGACY_BODY], 'no findings');
end;

procedure TDocInsightTests.HeaderLinesReplaceComposedSentence;
begin
  var Text:= FormatAnswerAsDocInsight('Who writes this field', 'who-writes', 'OPERAT.NAME', Asked,
    SENTENCE + CRLF + COMMAND + CRLF + 'BUNDLE C:\x' + CRLF + BODY);
  var L:= Lines(Text);
  Assert.AreEqual('/// Who writes this field (drag-lint report who-writes) for OPERAT.NAME, asked on 2026-10-10 14:32,', L[L_SENTENCE]);
  Assert.AreEqual('///   engine 1.27.0.', L[L_SENTENCE_WRAP]);
  Assert.AreEqual('/// ' + StringReplace(COMMAND, '&', '&amp;', [rfReplaceAll]), L[L_COMMAND], 'one line, escaped, unwrapped');
  Assert.IsTrue(Length(L[L_COMMAND]) > DOCINSIGHT_MAX_LINE, 'the fixture COMMAND is longer than the wrap width');
  Assert.AreEqual('///', L[L_BREAK]);
  Assert.AreEqual('/// Totals: 2 write sites / 1 routines.', L[L_HEADER_BODY]);
  Assert.AreEqual(0, Pos('2026-10-06', Text), 'no composed sentence besides the header');
end;

procedure TDocInsightTests.CommandWithoutHeaderSentenceIsABodyLine;
begin
  { a COMMAND line counts only right after a header sentence; elsewhere it is an
    ordinary answer line: wrapped, after the composed sentence }
  var L:= Lines(FormatAnswerAsDocInsight('Who writes this field', 'who-writes', 'OPERAT.NAME', Asked, COMMAND));
  Assert.Contains(L[L_SENTENCE], 'asked on 2026-10-06.');
  for var S: string in L do
    Assert.IsTrue(Length(S) <= DOCINSIGHT_MAX_LINE, 'wrapped: ' + S);
end;

initialization
  TDUnitX.RegisterTestFixture(TDocInsightTests);

end.
