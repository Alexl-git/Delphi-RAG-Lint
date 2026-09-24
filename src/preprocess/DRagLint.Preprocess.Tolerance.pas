unit DRagLint.Preprocess.Tolerance;

// v1.2.1 port change #5 -- the dcc-tolerance pass (tolerance.js), the LAST
// piece of the JS preprocessor ported to Delphi. Two constructs that dcc32
// accepts with a missing ';' (both verified against dcc32, exit 0) are
// normalized BEFORE parsing so the grammar sees the ';' dcc imagines:
//
//   Rule A -- the FINAL routine-directive group without its ';':
//       function F(x: Integer): Integer; deprecated 'msg'
//       function IsEq(...): Boolean; overload
//       function G: LongWord; stdcall; external 'k32' name 'GetTickCount'
//     Anchors: an earlier ';' must exist on the SAME line (a declaration
//     tail, never a statement), and the NEXT code line must start with a
//     declaration keyword.
//
//   Rule B -- array[..] of T as the LAST record field without its ';':
//       padding: array [0 .. 83] of Byte // comment
//       end;
//     Anchor: the element type is a plain (dotted) identifier and the NEXT
//     code line starts with 'end'. This family CANNOT be fixed in the
//     grammar -- the '[N]' short-string element overlap is lexical and GLR
//     cannot split it (documented at declFieldNoSemi in grammar.js).
//
// REPLACEMENT, not insertion (the offset-identity invariant, trivially):
// the ';' (byte 59) REPLACES the first whitespace byte after the line's
// last code character -- a space (32), a tab (9), or the CR (13) of a CRLF
// ending. LF (10) is never touched, so line numbers and every following
// byte offset stay identical; Length(output) = Length(input) always. A line
// with no eligible byte (LF-only ending with no trailing whitespace) is
// deliberately left unfixed -- offsets always beat the fix; real Delphi
// sources are CRLF, so the CR is always available.
//
// Safety (why a false positive cannot corrupt valid code): in Pascal an
// extra ';' before 'end' is an empty statement, and none of the follower
// keywords can legally continue an expression -- so a ';' at a
// mis-identified site keeps valid code valid and invalid code invalid.
//
// The scanner is comment/string-aware line by line (brace and paren-star
// block comments persist state ACROSS lines; string literals are
// line-bounded and doubled-quote aware; // kills the rest of the line), so
// keywords inside strings or comments never match. Byte-level positions:
// each input byte maps to exactly one scanned character, so the edit
// position is byte-exact even when comments carry multi-byte UTF-8.
//
// ENCODING NOTE: brace literals in this unit are BYTE constants (123 = open
// brace, 125 = close brace) -- never a bare brace inside a comment.

interface

uses
  System.SysUtils;

/// <summary>Applies the dcc-tolerance pass IN PLACE over resolved
/// (preprocessed) UTF-8 bytes: where a dcc32-accepted construct omits its
/// terminating ';' (final routine-directive group; array[..]-of-T last
/// record field), the first whitespace byte after the line's last code
/// character (space/tab/CR, never LF) is REPLACED by ';'. Length(ABytes)
/// is unchanged -- the offset-identity invariant holds trivially.</summary>
/// <param name="ABytes">The preprocessed source bytes; edited in place.</param>
/// <returns>The number of ';' replacements performed (0 when nothing
/// matched or no line had an eligible whitespace byte).</returns>
/// <remarks>
/// Deliberately conservative: Rule A requires an earlier ';' on
/// the same line AND a declaration-keyword follower; Rule B requires an
/// 'end' follower. Lines already ending in ';' are never touched. Not
/// thread-safe with respect to ABytes (in-place edit); the compiled match
/// patterns are created once per process and are read-only thereafter.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Preprocess.Preprocess/2 (DRagLint.Preprocess.pas)</para>
/// <para>Calls: DRagLint.Preprocess.Tolerance.EnsureRegexes, DRagLint.Preprocess.Tolerance.StripCodeLine</para>
/// <para>Complexity: 27 (cyclomatic, outer body), 83 lines (full implementation)</para>
/// <para>Mutates: ABytes (var)</para>
/// <seealso cref="DRagLint.Preprocess.Tolerance.EnsureRegexes"/>
/// <seealso cref="DRagLint.Preprocess.Tolerance.StripCodeLine"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ApplyTolerances(var ABytes: TBytes): Integer;

/// <summary>P1 (extractor 1.19.0-alpha): neutralises every Delphi 12+
/// MULTI-LINE string literal in AUtf8 so that neither the directive lexer nor
/// the tree-sitter grammar mis-reads its body. A literal is an odd run of 3 or
/// more apostrophes (in code, not inside a comment or an ordinary string)
/// followed only by blanks up to the end of its line, closed by a line whose
/// first non-blank bytes are exactly the same number of apostrophes. Inside
/// it: every apostrophe, every open-brace, and the '(' of a '(*' in the BODY
/// become a space; a delimiter longer than three quotes keeps three quotes and
/// the rest become spaces. An opener with no matching closing line is left
/// alone.</summary>
/// <param name="AUtf8">The source file as UTF-8 bytes. Never modified.</param>
/// <returns>AUtf8 itself (the same array) when no multi-line literal was
/// found; otherwise a NEW array of the same length holding the rewritten
/// bytes. LF and CR bytes are never touched, so the offset-identity invariant
/// (same length, every line at the same byte offset) holds either way.</returns>
/// <remarks>
/// WHY BOTH LAYERS NEED IT. The grammar's own triple-quote token
/// /'''[\s\S]*?'''/ loses to its single-quote token /'([^']|'')*'/ (which
/// admits newlines) as soon as the body holds an odd number of apostrophes, and
/// it has no 5-quote form at all -- so the unit fails to parse at 1:1. The
/// directive lexer (DRagLint.Preprocess.Lexer) bounds a '-string at end of line,
/// so a body line is lexed as CODE and an IFDEF directive written in the text
/// becomes a live directive. Blanking those bytes before either layer runs lets the
/// grammar's triple-quote token match and leaves the lexer nothing to
/// misinterpret. The grammar fix proper belongs to tree-sitter-delphi13; this
/// is the in-repo neutralisation until it lands. The harvested literal text
/// loses exactly the blanked characters. Thread-safe (no shared state).
/// </remarks>
function NeutralizeMultilineStrings(const AUtf8: TBytes): TBytes;

implementation

uses
  System.RegularExpressions;

const
  // Pattern sources -- ported VERBATIM from tolerance.js (RULE_A / RULE_B and
  // their followers) so the Delphi pass is byte-for-byte parity-testable
  // against the frozen JS-rendered snapshots in tests/preprocess/fixtures.
  DIRWORD = '(?:stdcall|cdecl|safecall|pascal|register|winapi|inline'
          + '|overload|varargs|assembler|near|far|export|platform|experimental'
          + '|final|static|unsafe|reintroduce|virtual|dynamic|override|abstract)';
  STR_LIT = '''[^'']*''';
  DIRUNIT = '(?:' + DIRWORD
          + '|deprecated(?:\s+' + STR_LIT + ')?'
          + '|external(?:\s+' + STR_LIT + ')?(?:\s+name\s+' + STR_LIT + ')?(?:\s+index\s+\d+)?)';
  RULE_A_SRC          = ';\s*' + DIRUNIT + '(?:\s*;\s*' + DIRUNIT + ')*$';
  RULE_A_FOLLOWER_SRC = '^\s*(function|procedure|constructor|destructor|class|var|const|type'
                      + '|threadvar|resourcestring|property|implementation|interface'
                      + '|initialization|finalization|uses|begin|end|exports|label)\b';
  RULE_B_SRC          = ':\s*(?:packed\s+)?array\s*\[[^\]]*\]\s*of\s+[A-Za-z_][\w.]*$';
  RULE_B_FOLLOWER_SRC = '^\s*end\b';

var
  // Compiled once per process on first use (read-only afterwards).
  GRuleA        : TRegEx ;
  GRuleAFollower: TRegEx ;
  GRuleB        : TRegEx ;
  GRuleBFollower: TRegEx ;
  GRegexReady   : Boolean = False;

procedure EnsureRegexes;
begin
  if GRegexReady then Exit;
  GRuleA        := TRegEx.Create(RULE_A_SRC,          [roIgnoreCase, roCompiled]);
  GRuleAFollower:= TRegEx.Create(RULE_A_FOLLOWER_SRC, [roIgnoreCase, roCompiled]);
  GRuleB        := TRegEx.Create(RULE_B_SRC,          [roIgnoreCase, roCompiled]);
  GRuleBFollower:= TRegEx.Create(RULE_B_FOLLOWER_SRC, [roIgnoreCase, roCompiled]);
  GRegexReady   := True;
end;

type
  // Cross-line block-comment state for the code scanner (tolerance.js `st`).
  TScanState = record
    InBrace: Boolean; // inside a brace block comment
    InParen: Boolean; // inside a paren-star block comment
  end;

// The comment/string-aware code projection of ONE line (tolerance.js
// stripComments): comments are blanked to spaces column-for-column, string
// literals are kept verbatim (line-bounded, doubled-quote aware), everything
// else is copied. One input byte -> exactly one output character, so a
// character index in the result IS the byte offset within the line.
function StripCodeLine(const ABytes: TBytes; ALineStart, ALineEnd: Integer;
  var AState: TScanState): string;
var
  SB: TStringBuilder;
  I : Integer       ;
  J : Integer       ;
  B : Byte          ;
begin
  SB:= TStringBuilder.Create(ALineEnd - ALineStart);
  try
    I:= ALineStart;
    while I < ALineEnd do
    begin
      if AState.InBrace then
      begin
        // Blank until the closing brace (byte 125) inclusive, or line end.
        while (I < ALineEnd) and (ABytes[I] <> 125) do begin SB.Append(' '); Inc(I); end;
        if I < ALineEnd then begin SB.Append(' '); Inc(I); AState.InBrace:= False; end;
        Continue;
      end;
      if AState.InParen then
      begin
        // Blank until '*)' (bytes 42,41) inclusive, or line end.
        while (I < ALineEnd) and not ((ABytes[I] = 42) and (I + 1 < ALineEnd) and (ABytes[I + 1] = 41)) do
        begin SB.Append(' '); Inc(I); end;
        if I < ALineEnd then begin SB.Append('  '); Inc(I, 2); AState.InParen:= False; end;
        Continue;
      end;
      B:= ABytes[I];
      if B = 39 then // ' -- string literal: keep verbatim, doubled-quote aware, line-bounded
      begin
        SB.Append(''''); Inc(I);
        while I < ALineEnd do
        begin
          if ABytes[I] = 39 then
          begin
            if (I + 1 < ALineEnd) and (ABytes[I + 1] = 39) then
            begin SB.Append(''''''); Inc(I, 2); Continue; end;
            SB.Append(''''); Inc(I);
            Break;
          end;
          SB.Append(Char(ABytes[I])); Inc(I);
        end;
        Continue;
      end;
      if (B = 47) and (I + 1 < ALineEnd) and (ABytes[I + 1] = 47) then // '//'
      begin
        for J:= I to ALineEnd - 1 do SB.Append(' ');
        Break;
      end;
      if B = 123 then begin AState.InBrace:= True; Continue; end;  // open brace
      if (B = 40) and (I + 1 < ALineEnd) and (ABytes[I + 1] = 42) then // '(*'
      begin AState.InParen:= True; Continue; end;
      SB.Append(Char(B)); // 1 byte -> 1 char (>= 128 is an opaque placeholder)
      Inc(I);
    end;
    Result:= SB.ToString;
  finally
    SB.Free;
  end;
end;

function ApplyTolerances(var ABytes: TBytes): Integer;
var
  LineStarts: TArray<Integer>;
  Codes     : TArray<string> ;
  State     : TScanState     ;
  I         : Integer        ;
  N         : Integer        ;
  LineCount : Integer        ;
  LStart    : Integer        ;
  LEnd      : Integer        ;
  Trimmed   : string         ;
  Follower  : string         ;
  J         : Integer        ;
  Matched   : Boolean        ;
  EditPos   : Integer        ;
  B         : Byte           ;
begin
  Result:= 0;
  N:= Length(ABytes);
  if N = 0 then Exit;
  EnsureRegexes;

  // Pass 1: line starts (a line ends BEFORE its LF; CR stays inside the line
  // so the replacement below may consume it) + the code projection per line.
  LineCount:= 1;
  for I:= 0 to N - 1 do
    if ABytes[I] = 10 then Inc(LineCount);
  SetLength(LineStarts, LineCount + 1);
  LineStarts[0]:= 0;
  J:= 1;
  for I:= 0 to N - 1 do
    if ABytes[I] = 10 then begin LineStarts[J]:= I + 1; Inc(J); end;
  LineStarts[LineCount]:= N + 1; // sentinel: implied LF just past the buffer

  State.InBrace:= False;
  State.InParen:= False;
  SetLength(Codes, LineCount);
  for I:= 0 to LineCount - 1 do
  begin
    LStart:= LineStarts[I];
    LEnd  := LineStarts[I + 1] - 1; // exclude the LF (or the sentinel)
    if LEnd > N then LEnd:= N;
    Codes[I]:= StripCodeLine(ABytes, LStart, LEnd, State);
  end;

  // Pass 2: rule matching + in-place byte replacement.
  for I:= 0 to LineCount - 1 do
  begin
    Trimmed:= Codes[I].TrimRight;
    if Trimmed = '' then Continue;
    if Trimmed.EndsWith(';') then Continue;

    Matched:= False;
    if GRuleA.IsMatch(Trimmed) then
    begin
      Follower:= '';
      for J:= I + 1 to LineCount - 1 do
        if Codes[J].Trim <> '' then begin Follower:= Codes[J]; Break; end;
      if (Follower <> '') and GRuleAFollower.IsMatch(Follower) then Matched:= True;
    end;
    if (not Matched) and GRuleB.IsMatch(Trimmed) then
    begin
      Follower:= '';
      for J:= I + 1 to LineCount - 1 do
        if Codes[J].Trim <> '' then begin Follower:= Codes[J]; Break; end;
      if (Follower <> '') and GRuleBFollower.IsMatch(Follower) then Matched:= True;
    end;
    if not Matched then Continue;

    // REPLACE the first whitespace byte after the last code character with
    // ';' (byte 59) -- space (32), tab (9), or CR (13); NEVER LF (10). One
    // char of the code projection is one byte, so Length(Trimmed) IS the
    // byte offset of that first post-code byte within the line. No eligible
    // byte -> leave the line unfixed (offsets beat the fix).
    EditPos:= LineStarts[I] + Length(Trimmed);
    if EditPos >= N then Continue;
    B:= ABytes[EditPos];
    if (B = 32) or (B = 9) or (B = 13) then
    begin
      ABytes[EditPos]:= 59;
      Inc(Result);
    end;
  end;
end;

const
  // P1 byte vocabulary (the scanners above spell these as bare numbers; the
  // multi-line pass below names them).
  B_TAB    = 9;
  B_LF     = 10;
  B_CR     = 13;
  B_SPACE  = 32;
  B_DQUOTE = 34;
  B_QUOTE  = 39;
  B_LPAREN = 40;
  B_RPAREN = 41;
  B_STAR   = 42;
  B_SLASH  = 47;
  B_LBRACE = 123;
  B_RBRACE = 125;
  // A multi-line delimiter is an ODD run of at least this many apostrophes;
  // the grammar's own token recognises exactly this many.
  ML_DELIM = 3;

// Number of consecutive apostrophes starting at APos.
function QuoteRunAt(const ABytes: TBytes; APos: Integer): Integer;
begin
  Result:= 0;
  while (APos + Result < Length(ABytes)) and (ABytes[APos + Result] = B_QUOTE) do Inc(Result);
end;

// True when only spaces/tabs (and a CR) stand between APos and the next LF or
// the end of the buffer.
function RestOfLineBlank(const ABytes: TBytes; APos: Integer): Boolean;
begin
  while (APos < Length(ABytes)) and (ABytes[APos] <> B_LF) do
  begin
    if not (ABytes[APos] in [B_TAB, B_CR, B_SPACE]) then Exit(False);
    Inc(APos);
  end;
  Result:= True;
end;

// Byte offset of the closing delimiter of a multi-line literal whose opener
// line ends at the LF found from AFrom on: the first later line whose first
// non-blank bytes are EXACTLY ARun apostrophes. -1 when there is none.
function FindMultilineClose(const ABytes: TBytes; AFrom, ARun: Integer): Integer;
var
  N, P: Integer;
begin
  Result:= -1;
  N:= Length(ABytes);
  P:= AFrom;
  while (P < N) and (ABytes[P] <> B_LF) do Inc(P);
  while P < N do
  begin
    Inc(P); // past the LF: P is a line start
    while (P < N) and ((ABytes[P] = B_SPACE) or (ABytes[P] = B_TAB)) do Inc(P);
    if (P < N) and (QuoteRunAt(ABytes, P) = ARun) then Exit(P);
    while (P < N) and (ABytes[P] <> B_LF) do Inc(P);
  end;
end;

// When ABytes[AI] opens a comment, a directive or a double-quoted assembler
// operand, returns the offset just past it (the brace/paren-star forms may
// span lines; // and "..." stop at the LF, as the directive lexer does).
// Otherwise returns AI unchanged.
function SkipNonCode(const ABytes: TBytes; AI: Integer): Integer;
var
  N: Integer;
  B: Byte   ;
begin
  N:= Length(ABytes);
  B:= ABytes[AI];
  Result:= AI;
  if B = B_LBRACE then
  begin
    while (Result < N) and (ABytes[Result] <> B_RBRACE) do Inc(Result);
    Inc(Result);
  end
  else if (B = B_LPAREN) and (AI + 1 < N) and (ABytes[AI + 1] = B_STAR) then
  begin
    Inc(Result, 2);
    while (Result < N - 1) and not ((ABytes[Result] = B_STAR) and (ABytes[Result + 1] = B_RPAREN)) do Inc(Result);
    Inc(Result, 2);
  end
  else if (B = B_SLASH) and (AI + 1 < N) and (ABytes[AI + 1] = B_SLASH) then
  begin
    while (Result < N) and (ABytes[Result] <> B_LF) do Inc(Result);
  end
  else if B = B_DQUOTE then
  begin
    Inc(Result);
    while (Result < N) and (ABytes[Result] <> B_DQUOTE) and (ABytes[Result] <> B_LF) do Inc(Result);
    if (Result < N) and (ABytes[Result] = B_DQUOTE) then Inc(Result);
  end;
end;

// ABytes[AI] is an apostrophe opening an ORDINARY string: returns the offset
// just past it -- line-bounded and doubled-quote aware, mirroring the lexer.
function SkipOrdinaryString(const ABytes: TBytes; AI: Integer): Integer;
var
  N: Integer;
begin
  N:= Length(ABytes);
  Result:= AI + 1;
  while (Result < N) and (ABytes[Result] <> B_LF)
        and not ((ABytes[Result] = B_QUOTE) and ((Result + 1 >= N) or (ABytes[Result + 1] <> B_QUOTE))) do
  begin
    if (ABytes[Result] = B_QUOTE) and (Result + 1 < N) and (ABytes[Result + 1] = B_QUOTE) then Inc(Result);
    Inc(Result);
  end;
  if (Result < N) and (ABytes[Result] = B_QUOTE) then Inc(Result);
end;

// Rewrites ONE recognised literal in place: opener [AOpen, AOpen+ARun) keeps
// three quotes, the body blanks apostrophes, open-braces and the '(' of a
// '(*', the closer [AClose, AClose+ARun) keeps its LAST three quotes.
procedure BlankMultiline(var ABytes: TBytes; AOpen, AClose, ARun: Integer);
var
  K: Integer;
begin
  for K:= AOpen + ML_DELIM to AOpen + ARun - 1 do ABytes[K]:= B_SPACE;
  for K:= AOpen + ARun to AClose - 1 do
    if (ABytes[K] = B_QUOTE) or (ABytes[K] = B_LBRACE)
       or ((ABytes[K] = B_LPAREN) and (K + 1 < AClose) and (ABytes[K + 1] = B_STAR)) then
      ABytes[K]:= B_SPACE;
  for K:= AClose to AClose + ARun - ML_DELIM - 1 do ABytes[K]:= B_SPACE;
end;

function NeutralizeMultilineStrings(const AUtf8: TBytes): TBytes;
var
  N, I, Skipped, Run, CloseAt: Integer;
  Copied                     : Boolean;
begin
  Result:= AUtf8;
  Copied:= False;
  N:= Length(AUtf8);
  I:= 0;
  while I < N do
  begin
    Skipped:= SkipNonCode(AUtf8, I);
    if Skipped <> I then
      I:= Skipped
    else if AUtf8[I] <> B_QUOTE then
      Inc(I)
    else
    begin
      // An apostrophe in code: a multi-line opener, or an ordinary string.
      Run:= QuoteRunAt(AUtf8, I);
      CloseAt:= -1;
      if (Run >= ML_DELIM) and Odd(Run) and RestOfLineBlank(AUtf8, I + Run) then
        CloseAt:= FindMultilineClose(AUtf8, I + Run, Run);
      if CloseAt < 0 then
        I:= SkipOrdinaryString(AUtf8, I)
      else
      begin
        if not Copied then
        begin
          Result:= Copy(AUtf8);
          Copied:= True;
        end;
        BlankMultiline(Result, I, CloseAt, Run);
        I:= CloseAt + Run;
      end;
    end;
  end;
end;

end.
