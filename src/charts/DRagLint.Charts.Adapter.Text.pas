unit DRagLint.Charts.Adapter.Text;

{ The text adapter of `drag-lint compare` (spec N1-N5): a dl-charts report, in
  its plain form (Ask-Report.ps1 -Plain stdout) or its DocInsight form (the
  /// <remarks> block DRagLint.Charts.DocInsight makes of it), becomes the
  TDiffItem list the diff core compares. Text is what was on the page; Key is
  the answer with everything that does not change the answer taken out (step
  numbers, anchor line numbers, the header, provenance lines, wrapping,
  trailing whitespace, blank-line runs), so plain and DocInsight copies of one
  answer compare equal and the same question asked twice diffs empty.

  The ASCII scrub, the plain-line mapping, the anchor rewrite and the line
  split are the FORMATTER'S OWN (DRagLint.Charts.DocInsight: ScrubLine,
  RenderAnswerLine, RenderAnchors, RemoveAutodocMarker, SplitAnswerLines), so
  a plain answer is mapped here exactly as the formatter renders it and the two
  cannot drift.

  Pure string work: no IO, no VCL, no engine dependency. }

interface

uses
  DRagLint.Charts.Diff, DRagLint.Charts.ReportHeader;

/// <summary>Tells a DocInsight report from a plain one.</summary>
/// <param name="pText">The whole report; CRLF, LF or CR line ends; a leading UTF-8 BOM
/// (U+FEFF) is ignored.</param>
/// <returns>rfDocInsight when the first non-blank line is a '///' comment (leading
/// whitespace allowed); rfPlain otherwise, an empty text included.</returns>
function DetectReportForm(const pText: string): TReportForm;

/// <summary>The report's logical lines: what a reader would call one line of the
/// answer, in the DocInsight rendering.</summary>
/// <param name="pText">The whole report; CRLF, LF or CR line ends; a leading BOM is
/// ignored; trailing whitespace on any line is ignored.</param>
/// <param name="pForm">Receives DetectReportForm(pText).</param>
/// <returns>One string per logical line, trimmed, in order. Never included: the header
/// sentence and COMMAND line ParseReportHeader consumes, the '&lt;remarks&gt;' and
/// '&lt;/remarks&gt;' lines, blank lines, and the plain lines the formatter drops.</returns>
/// <remarks>DocInsight: the '///' prefix is removed and a wrapped line is joined back. A
/// physical line indented exactly two spaces past the logical line's first physical line
/// continues it: ALWAYS when that first line is itself indented (a row: the formatter's
/// rows sit at two spaces and a continuation's indent never accumulates, so nothing else
/// can sit at four); for an unindented first line only when the first word would not have
/// fitted on the line above, or the line is itself a cut (the inverse of EmitWrapped,
/// because an unindented line followed by a two-space row is a real shape). A line holding
/// one token of exactly the room is taken to be a cut and is joined WITHOUT a space. The
/// joined line is then XML-unescaped. A line outside the comment is kept as plain text. Plain: each line is
/// ASCII-scrubbed and mapped as the formatter maps it (CHART -> 'Totals: ...', TARGET ->
/// 'Selected: ...', '@File.pas:12' -> '(File.pas:12)', the autodoc marker defused;
/// BUNDLE / INDEX / REGENERATE / 'ask-report:' / 'WARNING:' lines dropped).
/// Known limits (each pinned by a test): a token of exactly the room that fitted whole,
/// followed by a wrapped word, is rejoined without a space; an UNINDENTED line re-wrapped
/// at a NARROWER column than the formatter's is not joined (the first word of the
/// continuation would have fitted), so it diffs. Pure; thread-safe.</remarks>
function ReportLogicalLines(const pText: string; out pForm: TReportForm): TArray<string>;

/// <summary>The adapter: a report as diff items.</summary>
/// <param name="pText">The whole report, plain or DocInsight (see ReportLogicalLines).</param>
/// <returns>One item per logical line whose key is not '': Text is the original physical
/// line(s) exactly as read (a wrapped DocInsight line's physical lines joined with CRLF,
/// line ends normalised, BOM removed), Key is NormaliseKey of the logical line.</returns>
/// <remarks>A 'The report returned no findings.' line is an item like any other, so an
/// empty answer against a full one is one delete and N inserts. Pure; thread-safe.</remarks>
function ReportItems(const pText: string): TArray<TDiffItem>;

/// <summary>Reduces ONE logical line to its comparison key (spec N1 + N4).</summary>
/// <param name="pLogicalLine">A logical line, plain or already in the DocInsight
/// rendering.</param>
/// <returns>The key; '' means the line is dropped.</returns>
/// <remarks>In order: (1) ASCII scrub (the formatter's dash / arrow / quote table, other
/// non-ASCII -> '?', controls -> space) and TrimRight; (2) the plain-line mapping of
/// ReportLogicalLines, which drops BUNDLE / INDEX / REGENERATE / 'ask-report:' /
/// 'WARNING:' lines, plus any line holding ' AS OF '; (3) '(File.ext:123)' -> '(File.ext)';
/// (4) step numbers: a leading '[12]' or '12. ', a FIRST table cell '| 12 |' -> '|' (a number
/// in a later cell is data and stays), 'step 12' -> 'step N'; (5) whitespace runs collapsed to one space, trimmed. Pure; thread-safe.</remarks>
function NormaliseKey(const pLogicalLine: string): string;

implementation

uses
  System.SysUtils, System.StrUtils, System.Generics.Collections, System.RegularExpressions,
  DRagLint.Charts.DocInsight;

const
  CRLF = #13#10;
  BOM = #$FEFF;
  DOC_PREFIX_LEN = 4;
  { EmitWrapped's room on an unindented line: the 100-column limit minus '/// ' }
  WRAP_ROOM = DOCINSIGHT_MAX_LINE - DOC_PREFIX_LEN;
  { EmitWrapped indents a continuation two spaces past the logical line's own indent }
  WRAP_INDENT = 2;
  REMARKS_OPEN = '<remarks>';
  REMARKS_CLOSE = '</remarks>';
  AS_OF = ' AS OF ';

type
  { One logical line and the physical lines it came from (0-based, inclusive). }
  TLogicalLine = record
    Text : string;
    First: Integer;
    Last : Integer;
  end;

var
  { Unit-level singletons, built once in initialization. PS trap handled: PS
    -match / -replace are case-INSENSITIVE, TRegEx is case-sensitive by default.
    'step N' is new and takes roIgnoreCase so 'Step 12' reduces like 'step 12';
    the others match digits and punctuation only. }
  RxAnchorLine : TRegEx;
  RxStepBracket: TRegEx;
  RxStepDot    : TRegEx;
  RxStepCell   : TRegEx;
  RxStepWord   : TRegEx;
  RxSpaces     : TRegEx;

function FirstWord(const pText: string): string;
begin
  var T:= pText.Trim;
  var P:= Pos(' ', T);
  Result:= if P = 0 then T else Copy(T, 1, P - 1);
end;

{ BOM removed, then CRLF / CR / LF all split. PS trap handled: Get-Content splits
  on all three silently; String.Split does not, hence SplitAnswerLines. }
function SplitPhysical(const pText: string): TArray<string>;
begin
  Result:= SplitAnswerLines(if pText.StartsWith(BOM) then pText.Substring(1) else pText);
end;

{ The formatter's own line mapping, indent ignored, plus the marker defusing it
  applies to its whole output. }
function MapPlainLine(const pRaw: string; out pText: string): Boolean;
begin
  var Indent: string;
  Result:= RenderAnswerLine(pRaw, Indent, pText);
  if Result then
    pText:= RemoveAutodocMarker(pText);
end;

{ A physical line EmitWrapped filled by cutting a token: one token, exactly the room. }
function IsCut(const pLine: string): Boolean;
begin
  var T:= pLine.Trim;
  Result:= (Pos(' ', T) = 0) and (Length(T) = WRAP_ROOM - LeadingSpaces(pLine));
end;

{ Whether EmitWrapped broke between pLine and pNext: it does only when the next
  word does not fit in the room left on pLine. When pNext is itself a cut, the
  word EmitWrapped tested was longer than the fragment seen on pNext, so the
  break is certain whatever pLine holds. }
function WrapHappened(const pLine, pNext: string): Boolean;
begin
  var Room:= WRAP_ROOM - LeadingSpaces(pLine);
  Result:= IsCut(pNext) or (Length(pLine.Trim) + 1 + Length(FirstWord(pNext)) > Room);
end;

{ Whether pNext continues the logical line whose first physical line sits at
  pBase and whose last physical line is pLine (controller ruling R11): under an
  indented row the continuation indent is unambiguous; under an unindented line
  a two-space row is also possible, so the inverse wrap rule decides. }
function Continues(pBase: Integer; const pLine, pNext: string): Boolean;
begin
  Result:= (pNext.Trim <> '') and (LeadingSpaces(pNext) = pBase + WRAP_INDENT)
    and ((pBase >= WRAP_INDENT) or WrapHappened(pLine, pNext));
end;

{ The physical range the header occupies, [pFirst, pFirst + pCount). }
procedure HeaderRange(const pLines: TArray<string>; out pFirst, pCount: Integer);
begin
  pFirst:= 0;
  pCount:= 0;
  var Header: TReportHeader;
  if not ParseReportHeader(pLines, Header) then
    Exit;
  { the same skip ParseReportHeader makes: leading blanks, then a '<remarks>' line }
  while (pFirst < Length(pLines)) and (pLines[pFirst].Trim = '') do
    Inc(pFirst);
  var Body: string;
  if (pFirst < Length(pLines)) and StripDocPrefix(pLines[pFirst], Body) and (Body.Trim = REMARKS_OPEN) then
    Inc(pFirst);
  pCount:= Header.HeaderLines;
end;

function MakeLogical(const pText: string; pFirst, pLast: Integer): TLogicalLine;
begin
  Result.Text:= pText;
  Result.First:= pFirst;
  Result.Last:= pLast;
end;

procedure CollectPlain(const pLines: TArray<string>; pSkipFrom, pSkipTo: Integer;
  pOut: TList<TLogicalLine>);
begin
  for var I:= 0 to High(pLines) do
  begin
    if (I >= pSkipFrom) and (I < pSkipTo) then
      Continue;
    var Raw:= ScrubLine(pLines[I]).TrimRight;
    var Text: string;
    if (Raw.Trim <> '') and MapPlainLine(Raw, Text) then
      pOut.Add(MakeLogical(Text, I, I));
  end;
end;

procedure CollectDocInsight(const pLines: TArray<string>; pSkipFrom, pSkipTo: Integer;
  pOut: TList<TLogicalLine>);
begin
  var I:= 0;
  while I < Length(pLines) do
  begin
    var Body: string;
    if (I >= pSkipFrom) and (I < pSkipTo) then
    begin
      Inc(I);
      Continue;
    end;
    if not StripDocPrefix(pLines[I], Body) then
    begin
      { a line outside the comment: kept as written, never joined }
      var Outside:= pLines[I].Trim;
      if Outside <> '' then
        pOut.Add(MakeLogical(Outside, I, I));
      Inc(I);
      Continue;
    end;
    var Trimmed:= Body.Trim;
    if (Trimmed = '') or (Trimmed = REMARKS_OPEN) or (Trimmed = REMARKS_CLOSE) then
    begin
      Inc(I);
      Continue;
    end;
    var Base:= LeadingSpaces(Body);
    var Current:= Body;
    var SB:= TStringBuilder.Create(Trimmed);
    try
      var J:= I + 1;
      var Next: string;
      while (J < Length(pLines)) and StripDocPrefix(pLines[J], Next) and Continues(Base, Current, Next) do
      begin
        if not IsCut(Current) then
          SB.Append(' ');
        SB.Append(Next.Trim);
        Current:= Next;
        Inc(J);
      end;
      { joined on the ESCAPED text: EmitWrapped measured the escaped line }
      pOut.Add(MakeLogical(XmlUnescape(SB.ToString), I, J - 1));
      I:= J;
    finally
      SB.Free;
    end;
  end;
end;

function DetectFormOf(const pLines: TArray<string>): TReportForm;
begin
  for var Line in pLines do
    if Line.Trim <> '' then
    begin
      var Body: string;
      Exit(if StripDocPrefix(Line, Body) then rfDocInsight else rfPlain);
    end;
  Result:= rfPlain;
end;

function BuildLogical(const pLines: TArray<string>; out pForm: TReportForm): TArray<TLogicalLine>;
begin
  pForm:= DetectFormOf(pLines);
  var First, Count: Integer;
  HeaderRange(pLines, First, Count);
  var List:= TList<TLogicalLine>.Create;
  try
    if pForm = rfDocInsight then
      CollectDocInsight(pLines, First, First + Count, List)
    else
      CollectPlain(pLines, First, First + Count, List);
    Result:= List.ToArray;
  finally
    List.Free;
  end;
end;

function DetectReportForm(const pText: string): TReportForm;
begin
  Result:= DetectFormOf(SplitPhysical(pText));
end;

function ReportLogicalLines(const pText: string; out pForm: TReportForm): TArray<string>;
begin
  var Logical:= BuildLogical(SplitPhysical(pText), pForm);
  SetLength(Result, Length(Logical));
  for var I:= 0 to High(Logical) do
    Result[I]:= Logical[I].Text;
end;

function ReportItems(const pText: string): TArray<TDiffItem>;
begin
  var Lines:= SplitPhysical(pText);
  var Form: TReportForm;
  var Logical:= BuildLogical(Lines, Form);
  var List:= TList<TDiffItem>.Create;
  try
    for var L in Logical do
    begin
      var Key:= NormaliseKey(L.Text);
      if Key = '' then
        Continue;
      var Shown:= Lines[L.First];
      for var I:= L.First + 1 to L.Last do
        Shown:= Shown + CRLF + Lines[I];
      List.Add(TDiffItem.Make(Shown, Key));
    end;
    Result:= List.ToArray;
  finally
    List.Free;
  end;
end;

function NormaliseKey(const pLogicalLine: string): string;
begin
  var Scrubbed:= ScrubLine(pLogicalLine).TrimRight;
  var S: string;
  { never MapPlainLine(S, S): an out string is cleared before the const one is read }
  if (Scrubbed.Trim = '') or not MapPlainLine(Scrubbed, S) then
    Exit('');
  if ContainsStr(S, AS_OF) then
    Exit('');
  S:= RxAnchorLine.Replace(S, '($1)');
  S:= RxStepBracket.Replace(S, '');
  S:= RxStepDot.Replace(S, '');
  S:= RxStepCell.Replace(S, '|');
  S:= RxStepWord.Replace(S, 'step N');
  Result:= RxSpaces.Replace(S, ' ').Trim;
end;

initialization
  RxAnchorLine:= TRegEx.Create('\(([^()\s]+\.[A-Za-z0-9]+):\d+\)', [roCompiled]);
  RxStepBracket:= TRegEx.Create('^\s*\[\d+\]\s*', [roCompiled]);
  RxStepDot:= TRegEx.Create('^\s*\d+\.\s+', [roCompiled]);
  { ruling R12: only the FIRST cell is a step number; a later cell is data }
  RxStepCell:= TRegEx.Create('^\s*\|\s*\d+\s*\|', [roCompiled]);
  RxStepWord:= TRegEx.Create('\bstep \d+\b', [roCompiled, roIgnoreCase]);
  RxSpaces:= TRegEx.Create('\s+', [roCompiled]);

end.
