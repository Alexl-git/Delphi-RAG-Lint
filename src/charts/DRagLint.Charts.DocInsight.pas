unit DRagLint.Charts.DocInsight;

{ The DocInsight formatter of a dl-charts answer: Ask-Report.ps1's plain stdout
  as a /// <remarks> block ready to paste above a declaration.

  WHY IT IS ITS OWN UNIT. It used to live in the IDE plugin
  (DragLint.Plugin.ReportText). The engine (Update-doc, the renderers) needs the
  same bytes, and the engine must not link any src\delphi-plugin unit, so the
  formatter moved here: no ToolsAPI, no VCL, no question catalog. The plugin
  keeps FormatReportAsDocInsight as a thin forwarder that looks the caption up
  in its catalog and calls FormatAnswerAsDocInsight.

  charts\src\Report.DocInsight.ps1 is a line-for-line PowerShell port of this
  unit; charts\fixtures\docinsight holds the pairs both must reproduce byte for
  byte (tests\reportstext ReportTextTests and charts\src\Test-AskReport.ps1
  AR-DOC-PORT). }

interface

const
  /// <summary>Longest line FormatAnswerAsDocInsight emits, '/// ' included --
  /// except the one COMMAND line of a report header, which is never wrapped.
  /// Well under the 120-column ceiling so a pasted block never needs
  /// re-wrapping in an indented declaration.</summary>
  DOCINSIGHT_MAX_LINE = 100;

  /// <summary>The phrase used when the caller has no caption for the question
  /// (an unknown question id).</summary>
  DOCINSIGHT_UNKNOWN_PHRASE = 'Report';

/// <summary>Turns an Ask-Report.ps1 stdout answer into a DocInsight remarks
/// block ready to paste above a declaration.</summary>
/// <param name="pPhrase">The question's caption without its trailing '...',
/// e.g. 'Who writes this field'; '' means DOCINSIGHT_UNKNOWN_PHRASE.</param>
/// <param name="pQuestionId">The question that was asked, e.g. 'who-writes'.</param>
/// <param name="pTarget">The target that was sent.</param>
/// <param name="pDate">When it was asked; only the date part is printed, and
/// only for a legacy answer (see remarks).</param>
/// <param name="pAnswer">The captured output of a run that exited 0; CRLF, LF
/// or CR line ends.</param>
/// <returns>CRLF-separated lines, each starting with '///', opening with
/// '/// &lt;remarks&gt;' and closing with '/// &lt;/remarks&gt;' plus a final
/// CRLF. The first sentence names the question, the target and the date.</returns>
/// <remarks>Guarantees, each pinned by a test: strict 7-bit ASCII (dashes and
/// arrows become -- and ->, anything else unknown becomes '?'); no line longer
/// than DOCINSIGHT_MAX_LINE (an over-long token is split); the autodoc
/// provenance marker never appears; '&lt;' and '&amp;' are XML-escaped; a
/// row's '@File.pas:line' anchor is rendered '(File.pas:line)'; the
/// '... +N more ... not shown' disclosure is kept. Dropped: the BUNDLE and
/// top-level INDEX header lines, a trace's REGENERATE line, and any
/// 'ask-report:' or 'WARNING:' line that reached the shared stdout/stderr
/// pipe. An answer with nothing left says so in a sentence.
/// An answer whose first line is the report header sentence
/// (charts\src\Ask-Report.ps1, spec section 3) keeps it in place of the
/// composed '..., asked on yyyy-mm-dd.' sentence, and its COMMAND line is
/// emitted on ONE line, unwrapped -- the only line allowed past
/// DOCINSIGHT_MAX_LINE, because the line must rerun as typed. An answer without
/// the header lines is formatted exactly as before the header existed.
/// Pure function; thread-safe.</remarks>
function FormatAnswerAsDocInsight(const pPhrase, pQuestionId, pTarget: string; pDate: TDateTime;
  const pAnswer: string): string;

{ The building blocks FormatAnswerAsDocInsight applies to each answer line,
  public so the compare adapter (DRagLint.Charts.Adapter.Text) maps a plain
  answer EXACTLY as this formatter does instead of keeping a copy that drifts. }

/// <summary>Scrubs one line to strict 7-bit ASCII.</summary>
/// <param name="pLine">One line, no line end.</param>
/// <returns>pLine with the known dashes, arrows, quotes, bullets and the
/// no-break space replaced by ASCII stand-ins (-- -> ' " * and so on), any other
/// character outside 7-bit replaced by '?', and every control character (tab
/// included) replaced by a space. A character above U+FFFF is two UTF-16
/// surrogates and becomes '??'.</returns>
/// <remarks>Pure; thread-safe.</remarks>
function ScrubLine(const pLine: string): string;

/// <summary>Defuses the autodoc provenance marker.</summary>
/// <param name="pText">Any text.</param>
/// <returns>pText with every occurrence of the marker (matched
/// case-insensitively) replaced by 'drag-lint auto', so a pasted block is never
/// mistaken for generated documentation.</returns>
/// <remarks>Pure; thread-safe.</remarks>
function RemoveAutodocMarker(const pText: string): string;

/// <summary>Renders a row's file anchors the DocInsight way.</summary>
/// <param name="pLine">One answer line.</param>
/// <returns>pLine with each '@File.ext' or '@File.ext:12' token (preceded by
/// the line start or whitespace, followed by the line end, whitespace, ',' or
/// ';') rewritten as '(File.ext)' / '(File.ext:12)'.</returns>
/// <remarks>Case-sensitive TRegEx; [A-Za-z0-9] covers both cases of the
/// extension. Pure; thread-safe.</remarks>
function RenderAnchors(const pLine: string): string;

/// <summary>Counts the leading spaces of a line.</summary>
/// <param name="pLine">One line.</param>
/// <returns>The number of ' ' characters before the first other character
/// (tabs are not counted).</returns>
function LeadingSpaces(const pLine: string): Integer;

/// <summary>Splits a text into lines on CRLF, CR or LF.</summary>
/// <param name="pText">The text.</param>
/// <returns>The lines without their line ends; a final line end yields a final
/// empty element. A BOM is NOT removed.</returns>
function SplitAnswerLines(const pText: string): TArray<string>;

/// <summary>Maps ONE answer line to what the formatter emits for it, before
/// wrapping.</summary>
/// <param name="pRaw">The line, already scrubbed (ScrubLine) and right-trimmed;
/// its leading spaces are significant (see remarks).</param>
/// <param name="pIndent">Receives the row indent: two spaces when pRaw is
/// indented more than two spaces, else ''.</param>
/// <param name="pText">Receives the rendered text, trimmed, NOT XML-escaped and
/// with the autodoc marker NOT yet defused (the formatter does both on its
/// output).</param>
/// <returns>False when the line is dropped: an 'ask-report:' or 'WARNING:' line
/// (case-insensitive), an UNINDENTED 'BUNDLE ' or 'INDEX ' line, a 'REGENERATE '
/// line at any indent, a 'CHART ' line without ' -- ', or a line left empty.</returns>
/// <remarks>'CHART x -- rest' becomes 'Totals: rest.', 'TARGET x' becomes
/// 'Selected: x', and anchors are rendered by RenderAnchors. Pure; thread-safe.</remarks>
function RenderAnswerLine(const pRaw: string; out pIndent, pText: string): Boolean;

implementation

uses
  System.SysUtils
  , System.StrUtils
  , System.RegularExpressions
  ;

const
  DOC_PREFIX = '/// ';
  DOC_EMPTY = '///';
  CRLF = #13#10;
  { The autodoc provenance marker, assembled so this unit's own source never
    contains it as one literal. }
  AUTODOC_MARKER = 'drag-lint' + ':auto';
  AUTODOC_MARKER_SAFE = 'drag-lint auto';
  ASK_PREFIX = 'ask-report:';
  COMMAND_PREFIX = 'COMMAND ';
  { The header sentence of the report contract (spec section 3). Case-sensitive,
    as the PowerShell port's -cmatch (PS -match would not be). }
  HEADER_SENTENCE_RX = '^\S.* \(drag-lint report [a-z0-9-]+\) for .+, asked on \d{4}-\d{2}-\d{2} \d{2}:\d{2}, engine \S+\.$';
  { leading spaces above which a trace line is a continuation of the one above }
  CONTINUATION_INDENT = 2;
  WRAP_INDENT = '  ';
  ROW_INDENT = '  ';

type
  TCharSubst = record
    Code: Char;
    Text: string;
  end;

const
  { The non-ASCII characters an answer is known to carry (the chart labels and
    the trace use dashes, arrows and typographic quotes), each with a readable
    ASCII stand-in. Anything else outside 7-bit becomes '?'. }
  CHAR_SUBSTS: array[0..19] of TCharSubst = (
    (Code: #$00A0; Text: ' '  ), (Code: #$00B7; Text: '*'  ), (Code: #$2022; Text: '*'  ),
    (Code: #$00D7; Text: 'x'  ), (Code: #$2010; Text: '-'  ), (Code: #$2011; Text: '-'  ),
    (Code: #$2012; Text: '--' ), (Code: #$2013; Text: '--' ), (Code: #$2014; Text: '--' ),
    (Code: #$2015; Text: '--' ), (Code: #$2018; Text: '''' ), (Code: #$2019; Text: '''' ),
    (Code: #$201A; Text: '''' ), (Code: #$201C; Text: '"'  ), (Code: #$201D; Text: '"'  ),
    (Code: #$201E; Text: '"'  ), (Code: #$2026; Text: '...'), (Code: #$2190; Text: '<-' ),
    (Code: #$2192; Text: '->' ), (Code: #$21D2; Text: '=>' ));

function ScrubChar(pC: Char): string;
begin
  if (pC >= ' ') and (pC <= '~') then Exit(pC);
  if pC < ' ' then Exit(' '); { tab and any other control character }
  for var S: TCharSubst in CHAR_SUBSTS do
    if S.Code = pC then Exit(S.Text);
  Result:= '?';
end;

{ One line at a time, so the caller never has to think about CR/LF here. }
function ScrubLine(const pLine: string): string;
var
  SB: TStringBuilder;
begin
  SB:= TStringBuilder.Create;
  try
    for var C: Char in pLine do SB.Append(ScrubChar(C));
    Result:= SB.ToString;
  finally
    SB.Free;
  end;
end;

function RemoveAutodocMarker(const pText: string): string;
begin
  Result:= pText;
  while ContainsText(Result, AUTODOC_MARKER) do
    Result:= StringReplace(Result, AUTODOC_MARKER, AUTODOC_MARKER_SAFE, [rfReplaceAll, rfIgnoreCase]);
end;

function XmlEscape(const pText: string): string;
begin
  Result:= StringReplace(pText , '&', '&amp;', [rfReplaceAll]);
  Result:= StringReplace(Result, '<', '&lt;' , [rfReplaceAll]);
end;

{ ' @File.pas:12' -> ' (File.pas:12)'; only a token that looks like a file. }
function RenderAnchors(const pLine: string): string;
begin
  Result:= TRegEx.Replace(pLine, '(^|\s)@([^\s@]+\.[A-Za-z0-9]+(?::\d+)?)(?=$|[\s,;])', '$1($2)');
end;

function LeadingSpaces(const pLine: string): Integer;
begin
  Result:= 0;
  while (Result < Length(pLine)) and (pLine[Result + 1] = ' ') do Inc(Result);
end;

function SplitAnswerLines(const pText: string): TArray<string>;
begin
  Result:= StringReplace(StringReplace(pText, #13#10, #10, [rfReplaceAll]), #13, #10, [rfReplaceAll]).Split([#10]);
end;

{ Word-wraps one logical line into /// lines no longer than DOCINSIGHT_MAX_LINE.
  Continuation lines get two more spaces of indent; a token longer than the
  room left is cut, never dropped. }
procedure EmitWrapped(pOut: TStringBuilder; const pIndent, pText: string);
var
  Room   : Integer;
  Current: string;
  Lead   : string;

  procedure Flush;
  begin
    pOut.Append(DOC_PREFIX).Append(Lead).Append(Current).Append(CRLF);
    Current:= '';
    Lead:= pIndent + WRAP_INDENT;
  end;

begin
  Lead:= pIndent;
  Current:= '';
  for var Word0: string in pText.Split([' '], TStringSplitOptions.ExcludeEmpty) do
  begin
    var Word: string:= Word0;
    repeat
      Room:= DOCINSIGHT_MAX_LINE - Length(DOC_PREFIX) - Length(Lead);
      if Current = '' then
      begin
        if Length(Word) <= Room then
        begin
          Current:= Word;
          Word:= '';
        end
        else
        begin
          Current:= Copy(Word, 1, Room);
          Word:= Copy(Word, Room + 1, MaxInt);
          Flush;
        end;
      end
      else if Length(Current) + 1 + Length(Word) <= Room then
      begin
        Current:= Current + ' ' + Word;
        Word:= '';
      end
      else Flush;
    until Word = '';
  end;
  if Current <> '' then Flush;
end;

{ One answer line -> the text to emit for it, its indent, and whether it is
  kept at all. }
function RenderAnswerLine(const pRaw: string; out pIndent, pText: string): Boolean;
var
  Trimmed: string;
begin
  pIndent:= '';
  pText:= '';
  Trimmed:= Trim(pRaw);
  Result:= False;
  if StartsText(ASK_PREFIX, Trimmed) or StartsText('WARNING:', Trimmed) then Exit;
  { top-level BUNDLE / INDEX lines name Ask-Report's own temp folder and the
    databases -- provenance for a terminal, noise in a doc comment. A trace's
    OWN '  INDEX <names> AS OF' line is indented, and kept. }
  if StartsStr('BUNDLE ', pRaw) or StartsStr('INDEX ', pRaw) then Exit;
  if StartsStr('REGENERATE ', Trimmed) then Exit;
  if StartsStr('CHART ', pRaw) then
  begin
    var P: Integer:= Pos(' -- ', pRaw);
    if P = 0 then Exit;
    pText:= 'Totals: ' + Trim(Copy(pRaw, P + Length(' -- '), MaxInt)) + '.';
    Exit(True);
  end;
  if StartsStr('TARGET ', Trimmed) then
    pText:= 'Selected: ' + RenderAnchors(Trim(Copy(Trimmed, Length('TARGET ') + 1, MaxInt)))
  else
    pText:= RenderAnchors(Trimmed);
  if LeadingSpaces(pRaw) > CONTINUATION_INDENT then pIndent:= ROW_INDENT;
  Result:= pText <> '';
end;

function FormatAnswerAsDocInsight(const pPhrase, pQuestionId, pTarget: string; pDate: TDateTime;
  const pAnswer: string): string;
var
  SB       : TStringBuilder;
  Indent   : string;
  Text     : string;
  Findings : Integer;
  PendBreak: Boolean;
begin
  var Phrase: string:= if pPhrase = '' then DOCINSIGHT_UNKNOWN_PHRASE else pPhrase;
  SB:= TStringBuilder.Create;
  try
    SB.Append(DOC_PREFIX).Append('<remarks>').Append(CRLF);
    var Lines: TArray<string>:= SplitAnswerLines(pAnswer);
    var Skip: Integer:= 0;
    if (Length(Lines) > 0) and TRegEx.IsMatch(ScrubLine(Lines[0]), HEADER_SENTENCE_RX) then
    begin
      { the answer's own header sentence (it carries the time and the engine) }
      EmitWrapped(SB, '', XmlEscape(ScrubLine(Lines[0])));
      Skip:= 1;
      if (Length(Lines) > 1) and Lines[1].StartsWith(COMMAND_PREFIX) then
      begin
        { never wrapped: the line must rerun as typed (contract H3) }
        SB.Append(DOC_PREFIX).Append(XmlEscape(ScrubLine(Lines[1]))).Append(CRLF);
        Skip:= 2;
      end;
    end
    else
      EmitWrapped(SB, '', XmlEscape(ScrubLine(Format('%s (drag-lint report %s) for %s, asked on %s.',
        [Phrase, pQuestionId, pTarget, FormatDateTime('yyyy-mm-dd', pDate)]))));
    Findings:= 0;
    PendBreak:= True;
    for var I: Integer:= Skip to High(Lines) do
    begin
      var Line: string:= ScrubLine(TrimRight(Lines[I]));
      if Trim(Line) = '' then
      begin
        PendBreak:= True;
        Continue;
      end;
      if not RenderAnswerLine(Line, Indent, Text) then Continue;
      if PendBreak then SB.Append(DOC_EMPTY).Append(CRLF);
      PendBreak:= False;
      EmitWrapped(SB, Indent, XmlEscape(Text));
      Inc(Findings);
    end;
    if Findings = 0 then
    begin
      SB.Append(DOC_EMPTY).Append(CRLF);
      EmitWrapped(SB, '', 'The report returned no findings.');
    end;
    SB.Append(DOC_PREFIX).Append('</remarks>').Append(CRLF);
    Result:= RemoveAutodocMarker(SB.ToString);
  finally
    SB.Free;
  end;
end;

end.
