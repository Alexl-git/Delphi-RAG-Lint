unit DRagLint.Doc.Harvest;

// AutoDocument Phase 3 Task 6: the comment HARVESTER's boundary scan and its
// acceptance guards.
//
// THIS HEADER IS DELIBERATELY // AND NOT A BRACE COMMENT. It has to spell the
// brace and paren-star delimiters, and a brace comment ends at the FIRST close
// brace inside it -- which is the whole reason the hrNestedBrace guard below
// exists. The first draft of this unit was written as a brace comment and did
// not compile: it demonstrated its own defect. A // comment runs to
// end-of-line, so it can name any delimiter safely, directives included.
//
// Harvesting promotes a comment a human already wrote into that symbol's
// DocInsight documentation. It is a WRITE into the user's source, so a false
// accept publishes someone else's words as an API contract -- a banner rule, a
// chunk of commented-out code, or a note that was closing the routine ABOVE.
// Everything in this unit exists to make that decision conservatively, and to
// name the reason when it declines.
//
// DELIBERATELY LEXICAL, AND DELIBERATELY PURE. No tree-sitter parse, no index,
// no I/O: the scan must work on a file the parser cannot resolve a symbol in,
// which is exactly the file whose comments are worth harvesting. The stop-set is
// unambiguous at line granularity, so line-lexical is sufficient -- with one
// thing that is NOT decidable line-by-line, the block comment. That is why the
// scan runs a downward lexer pre-pass over the whole file before it walks
// upward: a line's kind depends on what state the lexer was in when it arrived
// there.
//
// GUARD PRECEDENCE. Several guards can be true of the same block; the plan does
// not order them, so this unit fixes an order and states it, because the REASON
// is a diagnostic that callers and tests read:
//
//   1. hrNone         no candidate at all, or the block above is already
//                     DocInsight (///). Precedence between engine-written and
//                     hand-written DocInsight is Task 8's question, not this
//                     scan's -- here it is simply not a harvest candidate.
//   2. hrTrailer      decided by LAYOUT, before any content is inspected: a
//                     trailer is rejected for WHERE it sits, and inspecting its
//                     words first would report the wrong reason for it.
//   3. hrEmpty        whitespace-only content. Checked before hrBanner because
//                     an empty string also satisfies the banner pattern, and
//                     "empty" is the more specific answer.
//   4. hrNonAscii     any byte >= 128 in the raw lines. .pas files here are
//                     strict 7-bit ASCII; promoting a Latin-1 byte into a ///
//                     line would break that invariant at the write.
//   5. hrNestedBrace  a brace-sourced block whose promoted text itself contains
//                     a brace. Pascal comments do not nest, so re-emitting that
//                     text between braces would terminate the comment early.
//   6. hrCommentedCode
//   7. hrBanner       decoration is the weakest claim: a block that is BOTH
//                     dead code and dashes is better reported as dead code.
//   8. hrAccepted
//
// TWO ADDITIONS TO THE PLAN'S STOP-SET, both because the plan's rule as written
// would otherwise harvest something that is not prose:
//
// * A COMPILER DIRECTIVE IS CODE, NOT A COMMENT. {$IFDEF X} and (*$R+*) are
//   spelled with comment delimiters but are instructions to the compiler. Read
//   as comments they are harvestable -- "$R *.res" passes every content guard --
//   so the scan stops at one, exactly as it stops at any other line of code.
//
// * BLANK LINES ARE TRIMMED FROM BOTH ENDS OF THE ACCUMULATED BLOCK, not only
//   from the top. The blank line between a comment and the declaration below it
//   is no more part of the comment than the one above it is, and leaving it in
//   would hand Task 7 a trailing empty paragraph to split off. Blank COMMENT
//   lines (a bare `//`) between paragraphs are kept, which is what Task 7
//   splits on -- see the boundary rule below for why a blank SOURCE line inside
//   a block can no longer occur.
//
// THE BOUNDARY RULE (2026-08-06, plan item A1/1). A BLANK SOURCE LINE ENDS THE
// BLOCK. The upward walk tolerates at most BLANK_GAP_MAX blank lines BELOW the
// comment (the gap between it and the declaration, matching
// FindDocRegionAbove's AllowGap = 1); once a comment line has been seen, the
// next blank line is a boundary and the walk stops there.
//
// Before this rule the walk crossed blank lines without limit, so two SEPARATE
// comment blocks -- a banner, a blank line, then eleven lines of real prose --
// were accumulated as ONE block and the banner became paragraph 1, hence the
// <summary>. That is `docs/INBOX-harvest-swallows-preceding-banner-comment.md`.
// HarvestText's leading-banner drop (step 2b) was the first repair and it stays:
// it catches a banner that leads a block with NO blank line after it, which this
// rule cannot see. This rule is the more general one -- a preceding block is not
// this declaration's comment whatever it contains, banner or prose.
//
// The same walk also stopped tolerating an UNBOUNDED gap below. A comment three
// blank lines above a declaration is not that declaration's comment, and
// FindDocRegionAbove -- whose window this scan's header has always claimed to
// match -- would not have attributed it either.

interface

uses
  System.SysUtils;

type
  /// <summary>Why a candidate comment block was rejected, or hrAccepted.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// Used by: declaration (DRagLint.Doc.Harvest.pas)
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  THarvestReason = (hrAccepted, hrNone, hrBanner, hrCommentedCode, hrTrailer,
                    hrEmpty, hrNonAscii, hrNestedBrace);

  /// <summary>One boundary scan's verdict and the block it found.</summary>
  /// <remarks>
  /// RawLines / StartLine / EndLine describe the block for EVERY
  /// verdict except hrNone, which reports an empty block and zeroed line
  /// numbers -- there was nothing to describe. A rejected-but-present block
  /// still reports its extent so a caller can say WHICH comment it declined,
  /// and so Task 9's strip round-trip has the range to delete.
  /// <!-- drag-lint:auto BEGIN -->
  /// Used by: DRagLint.CLI.DoSelfTestHarvest (DRagLint.CLI.pas), DRagLint.Doc.Facts.HarvestInterfaceComment (DRagLint.Doc.Facts.pas), declaration (DRagLint.Doc.Harvest.pas)
  /// Used in units: DRagLint.CLI, DRagLint.Doc.Facts, DRagLint.Doc.Harvest
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  THarvestResult = record
    Reason   : THarvestReason;
    RawLines : TArray<string>;  // the candidate comment lines, markers still on
    StartLine: Integer;         // 1-based first line of the block, 0 when none
    EndLine  : Integer;         // 1-based last line of the block, 0 when none
  end;

/// <summary>Scans UPWARD from ADeclLine (1-based, the declaration's own line)
/// over ASrcLines, accumulating comment and blank lines, and returns the
/// candidate block with an accept/reject verdict. Pure: no I/O, no index.</summary>
/// <param name="ASrcLines">The whole file's lines, 0-based, as read by the doc
/// path's ANSI reader. The WHOLE file is required, not just the lines above
/// ADeclLine: a { } comment's extent is only decidable from the lexer state
/// accumulated from the start of the file.</param>
/// <param name="ADeclLine">1-based line of the declaration whose documentation
/// is being sought. Out-of-range values (0, negative, past end-of-file, or 1 --
/// nothing can be above the first line) yield hrNone rather than an error:
/// callers pass line numbers from an index that may lag the file on disk.</param>
/// <returns>The verdict and the accumulated block. Never raises.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// Called from: DRagLint.CLI.DoSelfTestHarvest (DRagLint.CLI.pas), DRagLint.Doc.Facts.HarvestInterfaceComment (DRagLint.Doc.Facts.pas)
/// Calls: DRagLint.Doc.Harvest.ClassifyLine, DRagLint.Doc.Harvest.ContainsEndSemi, DRagLint.Doc.Harvest.ContainsWord, DRagLint.Doc.Harvest.IsEndStop, DRagLint.Doc.Harvest.IsSeparatorOnly, DRagLint.Doc.Harvest.SeparatorShare, Pos, Trim
/// Complexity: 43 (cyclomatic, outer body), 135 lines (full implementation)
/// Pure
/// <seealso cref="DRagLint.Doc.Harvest.ClassifyLine"/>
/// <seealso cref="DRagLint.Doc.Harvest.ContainsEndSemi"/>
/// <seealso cref="DRagLint.Doc.Harvest.ContainsWord"/>
/// <seealso cref="DRagLint.Doc.Harvest.IsEndStop"/>
/// <seealso cref="DRagLint.Doc.Harvest.IsSeparatorOnly"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function HarvestScan(const ASrcLines: TArray<string>; ADeclLine: Integer): THarvestResult;

/// <summary>Transforms an ACCEPTED THarvestResult into DocInsight-ready text:
/// the first paragraph as the summary, the remainder as remarks prose.</summary>
/// <param name="AResult">A scan result. Any Reason other than hrAccepted yields
/// two empty strings -- the guards are the whole point, so a rejected block must
/// never reach a caller as text it could emit by mistake.</param>
/// <param name="ASummary">The first paragraph: comment markers stripped, wrapped
/// lines joined with single spaces, XML-escaped.</param>
/// <param name="ARemarks">The remaining paragraphs, one per line, separated by a
/// blank line (#10#10). '' when the block is a single paragraph.</param>
/// <remarks>
/// Returns PLAIN TEXT with #10 separators and does NOT re-prefix
/// anything with '///'. That is deliberate: TDocRegions.MergeComment's
/// EmitTagged already splits on newlines and re-prefixes every continuation line
/// (the 5ebde68 corruption fix), and a second prefixer would either double the
/// marker or fight it.
/// Escaping uses DRagLint.Doc.Regions.EscXml -- the same escaper every mined
/// fact goes through -- rather than a local copy, so the ampersand-first pass
/// order cannot drift between the two. Harvested prose needs it MORE than mined
/// identifiers do: it is arbitrary human text.
/// <!-- drag-lint:auto BEGIN -->
/// Called from: DRagLint.Doc.Facts.HarvestInterfaceComment (DRagLint.Doc.Facts.pas)
/// Calls: CharInSet, Copy, DRagLint.Doc.Harvest.CollapseSpaces, DRagLint.Doc.Harvest.SeparatorShare, DRagLint.Doc.Harvest.StripMarkers, DRagLint.Doc.Regions.EscXml, Trim
/// Complexity: 25 (cyclomatic, outer body), 107 lines (full implementation)
/// Mutates: ASummary (out), ARemarks (out)
/// <seealso cref="DRagLint.Doc.Harvest.CollapseSpaces"/>
/// <seealso cref="DRagLint.Doc.Harvest.SeparatorShare"/>
/// <seealso cref="DRagLint.Doc.Harvest.StripMarkers"/>
/// <seealso cref="DRagLint.Doc.Regions.EscXml"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure HarvestText(const AResult: THarvestResult; out ASummary, ARemarks: string);

/// <summary>The stable uppercase spelling of a reason, as printed by
/// `selftest harvest` and asserted by tests/autodoc/run_doc_p3_harvest_scan.ps1.
/// Lives here rather than at the print site so the enum and its wire form
/// cannot drift apart.</summary>
/// <param name="AReason"><!-- drag-lint:auto type -->const THarvestReason</param>
/// <returns><!-- drag-lint:auto -->Observed: 'ACCEPTED'; 'NONE'; 'BANNER';
/// 'COMMENTEDCODE'; 'TRAILER'; 'EMPTY'.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// Called from: DRagLint.CLI.DoSelfTestHarvest (DRagLint.CLI.pas)
/// Pure
/// <!-- drag-lint:auto END -->
/// </remarks>
function HarvestReasonToString(const AReason: THarvestReason): string;

implementation

uses
  // v(ADP3 T7): EscXml only. Taken here rather than in the interface so the
  // cycle DRagLint.Doc.Regions -> DRagLint.Doc.Facts -> DRagLint.Doc.Harvest ->
  // DRagLint.Doc.Regions never closes through three interface sections, which
  // Delphi rejects. This unit's INTERFACE stays dependency-free apart from the
  // RTL, which is also what "deliberately pure" in the header is worth.
  DRagLint.Doc.Regions;

type
  // Lexer state carried ACROSS lines. A string literal never spans a line in
  // Pascal, so it needs no state; a { } or (* *) comment does.
  TLexState = (lsNormal, lsBrace, lsParenStar);

  TLineKind = (lkBlank, lkComment, lkDoc, lkCode);

  TLineInfo = record
    Kind    : TLineKind;
    Text    : string;   // comment content with markers stripped (lkComment/lkDoc), or the code text (lkCode)
    HasBrace: Boolean;  // some part of this line's comment came from a { } block
  end;

const
  SEPARATOR_CHARS = ['-', '=', '*', '_', '#'];
  // The share of a line's non-space characters that must be separators before
  // it counts as decoration rather than prose. ONE home, TWO readers: hrBanner's
  // single-line arm (which rejects a block that is ONLY a rule) and HarvestText's
  // leading-banner drop (which removes a rule that merely LEADS real prose).
  // Promoted from a bare 0.6 literal when the second reader was added -- two
  // copies of a tuning threshold is how they drift apart.
  SEPARATOR_SHARE_MIN = 0.6;
  // How many blank SOURCE lines may sit between the comment block and the
  // declaration below it. 1, deliberately: it is FindDocRegionAbove's AllowGap
  // default, and the two must agree on where a region begins or the harvest
  // reads a comment the doc-region attribution would never have claimed.
  BLANK_GAP_MAX = 1;

// Classifies one line, advancing AState across it. A line is CODE the moment it
// carries a single non-whitespace character outside a comment -- `end; // done`
// is a code line whose text is `end;`, which is what the trailer tie-breaker
// then reads.
procedure ClassifyLine(const ALine: string; var AState: TLexState; out AInfo: TLineInfo);
var
  i, N      : Integer;
  HasCode   : Boolean;
  HasComment: Boolean;
  IsDoc     : Boolean;
  Brace     : Boolean;
  Content   : string ;
  Code      : string ;
begin
  N         := Length(ALine);
  HasCode   := False;
  HasComment:= False;
  IsDoc     := False;
  Brace     := False;
  Content   := '';
  Code      := '';
  i         := 1;
  while i <= N do
  begin
    case AState of
      lsBrace:
        begin
          HasComment:= True;
          Brace     := True;
          if ALine[i] = '}' then begin AState:= lsNormal; Inc(i); end
          else begin Content:= Content + ALine[i]; Inc(i); end;
        end;
      lsParenStar:
        begin
          HasComment:= True;
          if (ALine[i] = '*') and (i < N) and (ALine[i + 1] = ')') then begin AState:= lsNormal; Inc(i, 2); end
          else begin Content:= Content + ALine[i]; Inc(i); end;
        end;
    else // lsNormal
      if CharInSet(ALine[i], [' ', #9]) then Inc(i)
      else if (ALine[i] = '/') and (i < N) and (ALine[i + 1] = '/') then
      begin
        HasComment:= True;
        if (i + 2 <= N) and (ALine[i + 2] = '/') then
        begin
          IsDoc  := True;
          Content:= Content + Copy(ALine, i + 3, MaxInt);
        end
        else Content:= Content + Copy(ALine, i + 2, MaxInt);
        i:= N + 1; // a // comment runs to end-of-line
      end
      else if ALine[i] = '{' then
      begin
        if (i < N) and (ALine[i + 1] = '$') then
        begin // {$...} is a compiler directive: code, and a stop line.
          HasCode:= True;
          Code   := Code + Copy(ALine, i, MaxInt);
          i      := N + 1;
        end
        else
        begin
          AState    := lsBrace;
          Brace     := True;
          HasComment:= True;
          Inc(i);
        end;
      end
      else if (ALine[i] = '(') and (i < N) and (ALine[i + 1] = '*') then
      begin
        if (i + 2 <= N) and (ALine[i + 2] = '$') then
        begin // (*$...*) is a compiler directive: code, and a stop line.
          HasCode:= True;
          Code   := Code + Copy(ALine, i, MaxInt);
          i      := N + 1;
        end
        else
        begin
          AState    := lsParenStar;
          HasComment:= True;
          Inc(i, 2);
        end;
      end
      else if ALine[i] = '''' then
      begin // A string literal is code, and its content must not be read as one.
        HasCode:= True;
        Code   := Code + ALine[i];
        Inc(i);
        while i <= N do
        begin
          Code:= Code + ALine[i];
          if ALine[i] = '''' then begin Inc(i); Break; end;
          Inc(i);
        end;
      end
      else begin HasCode:= True; Code:= Code + ALine[i]; Inc(i); end;
    end; // case
  end; // while

  AInfo.HasBrace:= Brace;
  if HasCode then begin AInfo.Kind:= lkCode; AInfo.Text:= Trim(Code); end
  else if IsDoc then begin AInfo.Kind:= lkDoc; AInfo.Text:= Trim(Content); end
  else if HasComment then begin AInfo.Kind:= lkComment; AInfo.Text:= Trim(Content); end
  else begin AInfo.Kind:= lkBlank; AInfo.Text:= ''; end;
end; // procedure

// True when AText is `end;` or `end.` -- the only stop lines that arm the
// trailer tie-breaker. A bare `end` is deliberately excluded: the tie-breaker
// asks "did a ROUTINE just close above this comment", and the terminated forms
// are what answer it.
function IsEndStop(const AText: string): Boolean;
var
  T: string;
begin
  T     := LowerCase(Trim(AText));
  Result:= (T = 'end;') or (T = 'end.');
end;

// True when ACh starts (or continues) an identifier -- used for the word
// boundary the `begin` / `end;` tests need, so `recommend;` is not `end;`.
function IsWordChar(const ACh: Char): Boolean;
begin
  Result:= CharInSet(ACh, ['A'..'Z', 'a'..'z', '0'..'9', '_']);
end;

// True when AWord occurs in AText delimited by non-word characters on both
// sides. Case-insensitive; AWord must be lowercase.
function ContainsWord(const AText, AWord: string): Boolean;
var
  L    : string ;
  P, WL: Integer;
begin
  Result:= False;
  L     := LowerCase(AText);
  WL    := Length(AWord);
  P     := Pos(AWord, L);
  while P > 0 do
  begin
    if ((P = 1) or (not IsWordChar(L[P - 1]))) and
       ((P + WL > Length(L)) or (not IsWordChar(L[P + WL]))) then Exit(True);
    P:= Pos(AWord, L, P + 1);
  end;
end;

// True when `end;` occurs in AText with a word boundary before it. The trailing
// ';' is its own right-hand boundary.
function ContainsEndSemi(const AText: string): Boolean;
var
  L: string ;
  P: Integer;
begin
  Result:= False;
  L     := LowerCase(AText);
  P     := Pos('end;', L);
  while P > 0 do
  begin
    if (P = 1) or (not IsWordChar(L[P - 1])) then Exit(True);
    P:= Pos('end;', L, P + 1);
  end;
end;

// True when every character of AText is whitespace or one of the separator
// characters -- i.e. the line is a rule, not prose. An empty string satisfies
// this, which is why hrEmpty is decided first.
function IsSeparatorOnly(const AText: string): Boolean;
var
  Ch: Char;
begin
  for Ch in AText do
    if not (CharInSet(Ch, [' ', #9]) or CharInSet(Ch, SEPARATOR_CHARS)) then Exit(False);
  Result:= True;
end;

// The share of AText's non-space characters that are separator characters, as a
// fraction. 0 when there are no non-space characters at all.
function SeparatorShare(const AText: string): Double;
var
  Ch     : Char   ;
  Total  : Integer;
  Sepdown: Integer;
begin
  Total  := 0;
  Sepdown:= 0;
  for Ch in AText do
  begin
    if CharInSet(Ch, [' ', #9]) then Continue;
    Inc(Total);
    if CharInSet(Ch, SEPARATOR_CHARS) then Inc(Sepdown);
  end;
  if Total = 0 then Exit(0);
  Result:= Sepdown / Total;
end;

// Removes the comment delimiters from one raw source line and returns what was
// inside, with the content's OWN leading whitespace preserved so the caller can
// compute the block's common indentation.
//
// The leading whitespace BEFORE the marker is not content and is dropped;
// `//   foo` yields `   foo`, not `  //   foo`. Both delimiter styles are
// handled at both ends because a block comment's opener and closer sit on
// different lines of a multi-line block.
function StripMarkers(const ALine: string): string;
var
  T: string;
begin
  T:= TrimLeft(ALine);
  if T.StartsWith('///') then T:= Copy(T, 4, MaxInt)
  else if T.StartsWith('//') then T:= Copy(T, 3, MaxInt)
  else
  begin
    if T.StartsWith('(*') then T:= Copy(T, 3, MaxInt)
    else if T.StartsWith('{') then T:= Copy(T, 2, MaxInt);
    T:= TrimRight(T);
    if T.EndsWith('*)') then T:= Copy(T, 1, Length(T) - 2)
    else if T.EndsWith('}') then T:= Copy(T, 1, Length(T) - 1);
  end;
  Result:= TrimRight(T);
end;

// Collapses every run of whitespace in AText to a single space and trims. The
// lines of a paragraph are a WRAPPED SENTENCE, not separate statements, so they
// are rejoined with one space rather than preserved as written.
function CollapseSpaces(const AText: string): string;
var
  i   : Integer;
  Prev: Boolean;
  Sb  : TStringBuilder;
begin
  Sb  := TStringBuilder.Create;
  try
    Prev:= False;
    for i:= 1 to Length(AText) do
    begin
      if CharInSet(AText[i], [' ', #9]) then
      begin
        if not Prev then Sb.Append(' ');
        Prev:= True;
      end
      else
      begin
        Sb.Append(AText[i]);
        Prev:= False;
      end;
    end;
    Result:= Trim(Sb.ToString);
  finally
    Sb.Free;
  end;
end;

procedure HarvestText(const AResult: THarvestResult; out ASummary, ARemarks: string);
var
  Content : TArray<string>;
  Paras   : TArray<string>;
  i, Ind  : Integer       ;
  MinInd  : Integer       ;
  Cur     : string        ;
  Sb      : TStringBuilder;
begin
  ASummary:= '';
  ARemarks:= '';
  if (AResult.Reason <> hrAccepted) or (Length(AResult.RawLines) = 0) then Exit;

  // (1a) Strip the comment delimiters.
  SetLength(Content, Length(AResult.RawLines));
  for i:= Low(AResult.RawLines) to High(AResult.RawLines) do
    Content[i]:= StripMarkers(AResult.RawLines[i]);

  // (1b) Normalise indentation: remove the COMMON leading-whitespace prefix,
  // measured over the non-blank lines only (a blank line has no indentation to
  // contribute and would drive the minimum to zero).
  MinInd:= MaxInt;
  for i:= Low(Content) to High(Content) do
  begin
    if Trim(Content[i]) = '' then Continue;
    Ind:= 0;
    while (Ind < Length(Content[i])) and CharInSet(Content[i][Ind + 1], [' ', #9]) do Inc(Ind);
    if Ind < MinInd then MinInd:= Ind;
  end;
  if (MinInd > 0) and (MinInd < MaxInt) then
    for i:= Low(Content) to High(Content) do
      if Length(Content[i]) >= MinInd then Content[i]:= Copy(Content[i], MinInd + 1, MaxInt);

  // (2) Split into paragraphs on blank comment lines, and (5) join each
  // paragraph's wrapped lines with a single space.
  Paras:= nil;
  Cur  := '';
  for i:= Low(Content) to High(Content) do
  begin
    if Trim(Content[i]) = '' then
    begin
      if Trim(Cur) <> '' then
      begin
        SetLength(Paras, Length(Paras) + 1);
        Paras[High(Paras)]:= CollapseSpaces(Cur);
      end;
      Cur:= '';
    end
    else Cur:= Cur + ' ' + Content[i];
  end;
  if Trim(Cur) <> '' then
  begin
    SetLength(Paras, Length(Paras) + 1);
    Paras[High(Paras)]:= CollapseSpaces(Cur);
  end;
  if Length(Paras) = 0 then Exit;

  // (2b) DROP LEADING BANNER PARAGRAPHS. Found on real code during the Phase 3
  // rollout, not on a fixture: YADFOT.Wizard.pas's `Register` came out with the
  // summary '--- Register ---------------------------...'.
  //
  // The source there is a SEPARATE banner comment, ONE blank line, then eleven
  // lines of real prose. FindDocRegionAbove tolerates exactly one blank line
  // (AllowGap = 1), so the boundary scan crosses the gap and swallows the
  // banner; the paragraph split then does precisely what it is specified to do
  // and makes the banner paragraph 1, hence the <summary> -- the one line that
  // shows in a Help Insight tooltip and in every hover. Neither the scan nor
  // the split is individually wrong; the INTERACTION is, so the repair belongs
  // here, where both have already happened.
  //
  // The test is the SAME one hrBanner's own single-line arm uses --
  // SeparatorShare >= SEPARATOR_SHARE_MIN -- not a second, parallel notion of
  // "looks like a rule". hrBanner rejects a block that is ONLY decoration; this
  // drops decoration that merely LEADS a block with real prose in it, which is
  // the case hrBanner cannot see because the block as a whole is legitimate.
  //
  // Dropped, not demoted: moving the banner into <remarks> instead would just
  // relocate the noise. If every paragraph is decoration there is nothing to
  // harvest and the caller gets '' for both -- which cannot normally happen,
  // since hrBanner would already have rejected such a block, but the loop is
  // written not to depend on that.
  var FirstReal: Integer:= 0;
  while (FirstReal <= High(Paras)) and (SeparatorShare(Paras[FirstReal]) >= SEPARATOR_SHARE_MIN) do
    Inc(FirstReal);
  if FirstReal > High(Paras) then Exit;
  if FirstReal > 0 then Paras:= Copy(Paras, FirstReal, Length(Paras) - FirstReal);

  // (3) + (4) First paragraph is the summary, the rest are remarks prose,
  // separated by a blank line. Escaped with the ONE escaper (see the header).
  // The AUTO_MARK volatility marker is added at EMIT time (when the tag is
  // written to XML), not here, so that the harvested text itself stays pure.
  // v(PHASE A1): dropping leading banner paragraphs has already happened above.
  ASummary:= EscXml(Paras[0]);
  if Length(Paras) > 1 then
  begin
    Sb:= TStringBuilder.Create;
    try
      for i:= 1 to High(Paras) do
      begin
        if i > 1 then Sb.Append(#10#10);
        Sb.Append(EscXml(Paras[i]));
      end;
      ARemarks:= Sb.ToString;
    finally
      Sb.Free;
    end;
  end;
end; // procedure

function HarvestReasonToString(const AReason: THarvestReason): string;
begin
  case AReason of
    hrAccepted     : Result:= 'ACCEPTED';
    hrNone         : Result:= 'NONE';
    hrBanner       : Result:= 'BANNER';
    hrCommentedCode: Result:= 'COMMENTEDCODE';
    hrTrailer      : Result:= 'TRAILER';
    hrEmpty        : Result:= 'EMPTY';
    hrNonAscii     : Result:= 'NONASCII';
    hrNestedBrace  : Result:= 'NESTEDBRACE';
  else
    Result:= 'UNKNOWN';
  end;
end;

function HarvestScan(const ASrcLines: TArray<string>; ADeclLine: Integer): THarvestResult;
var
  Infos    : TArray<TLineInfo>;
  State    : TLexState        ;
  i, N     : Integer          ;
  Top      : Integer          ; // 0-based first line of the accumulated block
  Bottom   : Integer          ; // 0-based last line of the accumulated block
  StopIdx  : Integer          ; // 0-based index of the stop line, -1 at start-of-file
  HitDoc   : Boolean          ;
  AnyBrace : Boolean          ;
  AllBlank : Boolean          ;
  Joined   : string           ;
  Ch       : Char             ;
  HugsEnd  : Boolean          ;
  GapBelow : Boolean          ;
  AllSep   : Boolean          ;
  SeenText : Boolean          ; // a comment line has been accumulated already
  Blanks   : Integer          ; // blank lines crossed BELOW the block so far
begin
  Result.Reason   := hrNone;
  Result.RawLines := nil;
  Result.StartLine:= 0;
  Result.EndLine  := 0;

  N:= Length(ASrcLines);
  // Out of range in either direction: nothing above line 1, and nothing at all
  // past end-of-file. Both are hrNone, never an error -- see the doc comment.
  if (N = 0) or (ADeclLine <= 1) or (ADeclLine > N) then Exit;

  // Downward lexer pre-pass. A { } / (* *) comment spans lines, so a line's
  // kind is not decidable from the line alone.
  SetLength(Infos, N);
  State:= lsNormal;
  for i:= 0 to N - 1 do ClassifyLine(ASrcLines[i], State, Infos[i]);

  // Upward walk from the line above the declaration. See THE BOUNDARY RULE in
  // this unit's header: at most BLANK_GAP_MAX blank lines below the block, and
  // the first blank line AFTER a comment line has been seen ends the block.
  //
  // Breaking on that blank leaves StopIdx at -1, which is correct rather than
  // merely convenient: the trailer tie-breaker asks "did a routine close
  // IMMEDIATELY above this comment", and a blank-line boundary means the walk
  // never reached whatever is above it, so there is no stop line to reason about.
  Bottom := ADeclLine - 2;
  Top    := Bottom + 1;  // empty range until something is accumulated
  StopIdx:= -1;
  HitDoc := False;
  SeenText:= False;
  Blanks  := 0;
  i       := Bottom;
  while i >= 0 do
  begin
    if Infos[i].Kind = lkDoc then begin HitDoc:= True; Break; end;
    if Infos[i].Kind = lkBlank then
    begin
      if SeenText then Break;              // a blank line ENDS the block
      Inc(Blanks);
      if Blanks > BLANK_GAP_MAX then Break; // ... and the gap below is bounded
    end
    else if Infos[i].Kind <> lkComment then begin StopIdx:= i; Break; end
    else SeenText:= True;
    Top:= i;
    Dec(i);
  end;
  if HitDoc then Exit;   // already DocInsight -- not a harvest candidate
  if Top > Bottom then Exit;

  // Trim blank lines from BOTH ends; interior blanks are kept (Task 7 splits
  // paragraphs on them).
  while (Top <= Bottom) and (Infos[Top].Kind = lkBlank) do Inc(Top);
  while (Bottom >= Top) and (Infos[Bottom].Kind = lkBlank) do Dec(Bottom);
  if Top > Bottom then Exit;  // blanks only: there was no comment at all

  SetLength(Result.RawLines, Bottom - Top + 1);
  for i:= Top to Bottom do Result.RawLines[i - Top]:= ASrcLines[i];
  Result.StartLine:= Top + 1;
  Result.EndLine  := Bottom + 1;

  // (2) TRAILER -- layout, decided before any content is read.
  if (StopIdx >= 0) and IsEndStop(Infos[StopIdx].Text) then
  begin
    HugsEnd := (Top = StopIdx + 1);          // no blank between end; and the comment
    GapBelow:= (Bottom < ADeclLine - 2);     // a blank between the comment and the declaration
    if HugsEnd and GapBelow then begin Result.Reason:= hrTrailer; Exit; end;
  end;

  // (3) EMPTY -- before BANNER, which an empty string also satisfies.
  AllBlank:= True;
  Joined  := '';
  AnyBrace:= False;
  for i:= Top to Bottom do
  begin
    if Trim(Infos[i].Text) <> '' then AllBlank:= False;
    Joined:= Joined + Infos[i].Text;
    if Infos[i].HasBrace then AnyBrace:= True;
  end;
  if AllBlank then begin Result.Reason:= hrEmpty; Exit; end;

  // (4) NONASCII -- over the RAW lines, so a byte outside the comment markers
  // counts too.
  for i:= Low(Result.RawLines) to High(Result.RawLines) do
    for Ch in Result.RawLines[i] do
      if Ord(Ch) >= 128 then begin Result.Reason:= hrNonAscii; Exit; end;

  // (5) NESTEDBRACE -- a { }-sourced block whose own text carries a brace.
  if AnyBrace and ((Pos('{', Joined) > 0) or (Pos('}', Joined) > 0)) then
  begin
    Result.Reason:= hrNestedBrace;
    Exit;
  end;

  // (6) COMMENTEDCODE.
  for i:= Top to Bottom do
  begin
    if Infos[i].Kind <> lkComment then Continue;
    if (Pos(':=', Infos[i].Text) > 0) or ContainsWord(Infos[i].Text, 'begin') or
       ContainsEndSemi(Infos[i].Text) or Infos[i].Text.EndsWith(';') then
    begin
      Result.Reason:= hrCommentedCode;
      Exit;
    end;
  end;

  // (7) BANNER -- every line is a rule, or the block is a single line that is
  // mostly rule.
  AllSep:= True;
  for i:= Top to Bottom do
    if not IsSeparatorOnly(Infos[i].Text) then begin AllSep:= False; Break; end;
  if AllSep or ((Bottom = Top) and (SeparatorShare(Infos[Top].Text) >= SEPARATOR_SHARE_MIN)) then
  begin
    Result.Reason:= hrBanner;
    Exit;
  end;

  Result.Reason:= hrAccepted;
end; // function

end.
