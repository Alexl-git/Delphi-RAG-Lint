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
//   would hand Task 7 a trailing empty paragraph to split off. Blank lines
//   BETWEEN comment paragraphs are kept, which is what Task 7 splits on.

interface

uses
  System.SysUtils;

type
  /// <summary>Why a candidate comment block was rejected, or hrAccepted.</summary>
  THarvestReason = (hrAccepted, hrNone, hrBanner, hrCommentedCode, hrTrailer,
                    hrEmpty, hrNonAscii, hrNestedBrace);

  /// <summary>One boundary scan's verdict and the block it found.</summary>
  /// <remarks>RawLines / StartLine / EndLine describe the block for EVERY
  /// verdict except hrNone, which reports an empty block and zeroed line
  /// numbers -- there was nothing to describe. A rejected-but-present block
  /// still reports its extent so a caller can say WHICH comment it declined,
  /// and so Task 9's strip round-trip has the range to delete.</remarks>
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
function HarvestScan(const ASrcLines: TArray<string>; ADeclLine: Integer): THarvestResult;

/// <summary>The stable uppercase spelling of a reason, as printed by
/// `selftest harvest` and asserted by tests/autodoc/run_doc_p3_harvest_scan.ps1.
/// Lives here rather than at the print site so the enum and its wire form
/// cannot drift apart.</summary>
function HarvestReasonToString(const AReason: THarvestReason): string;

implementation

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

  // Upward walk from the line above the declaration.
  Bottom := ADeclLine - 2;
  Top    := Bottom + 1;  // empty range until something is accumulated
  StopIdx:= -1;
  HitDoc := False;
  i      := Bottom;
  while i >= 0 do
  begin
    if Infos[i].Kind = lkDoc then begin HitDoc:= True; Break; end;
    if not (Infos[i].Kind in [lkBlank, lkComment]) then begin StopIdx:= i; Break; end;
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
  if AllSep or ((Bottom = Top) and (SeparatorShare(Infos[Top].Text) >= 0.6)) then
  begin
    Result.Reason:= hrBanner;
    Exit;
  end;

  Result.Reason:= hrAccepted;
end; // function

end.
