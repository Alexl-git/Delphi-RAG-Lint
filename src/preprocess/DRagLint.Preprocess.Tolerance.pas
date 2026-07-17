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
/// <remarks>Deliberately conservative: Rule A requires an earlier ';' on
/// the same line AND a declaration-keyword follower; Rule B requires an
/// 'end' follower. Lines already ending in ';' are never touched. Not
/// thread-safe with respect to ABytes (in-place edit); the compiled match
/// patterns are created once per process and are read-only thereafter.</remarks>
function ApplyTolerances(var ABytes: TBytes): Integer;

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

end.
