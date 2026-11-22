unit DRagLint.Fix.Hygiene;

{ Lane A6 -- hygiene fixers of the autofix wave
  (docs\superpowers\plans\2026-10-27-autofix-wave-plan.md): comments, whitespace,
  review markers and doc tags. Seven rules:
    commented-out-code                delete the comment (whole lines, or a trailing comment)
    doc-param-not-in-signature        delete the /// <param> tag the signature lacks
    line-too-long                     re-wrap an over-long /// line at blanks (added 2026-10-28, lane B-DOC)
    misleading-indentation            re-indent the statement to its controlling statement
    multiple-statements-per-line      split the line at the statement boundary
    review-marker-placeholder-hash    write the computed hash over the placeholder
    review-marker-unused              delete the dead dl:ok marker
  Every edit changes whitespace and comments only; the token stream is untouched.
  The unit registers itself from its OWN initialization; DRagLint.Lint.Autofix
  never uses a fixer unit, so no unit cycle forms. Each fixer DECLINES (returns
  nil) whenever the source shape is not the one it was written for. }

interface

implementation

uses
  System.SysUtils
  , System.Classes
  , System.RegularExpressions
  , System.StrUtils
  , System.Generics.Collections
  , DRagLint.Core.Model
  , DRagLint.Refactor.TextEdit
  , DRagLint.Lint.Autofix
  , DRagLint.Lint.ReviewMarker
  , DRagLint.Lint.RuleCatalog
  , DRagLint.Doc.Regions  { line-too-long: WrapFactLine + DOC_FACT_MAX_COLS, the managed-fact writer's own wrap }
  ;

const
  { line-too-long: the longest line dcc64 compiles at every file offset (DeadCodeChecks.MAX_SAFE_LINE_LEN). }
  MAX_SAFE_LINE_LEN = 1020;
  DOC_LINE_TOKEN    = '///';
  FENCE_BEGIN       = '<!-- drag-lint:auto BEGIN -->';
  FENCE_END         = '<!-- drag-lint:auto END -->';
  FACT_PARA         = '<para>';
  MARKER_TOKEN = 'dl:ok';
  PARAM_CLOSE  = '</param>';

{ 1-based column of the first `//` that really starts a line comment, scanning past string literals and
  single-line brace and paren-star comments; 0 when there is none or the line opens a comment this scan cannot close. }
function FindLineCommentCol(const ALine: string): Integer;
var
  I      : Integer;
  InStr  : Boolean;
  CloseAt: Integer;
begin
  Result:= 0;
  InStr := False;
  I:= 1;
  while I <= Length(ALine) do
  begin
    if InStr then
      InStr:= ALine[I] <> ''''
    else if ALine[I] = '''' then
      InStr:= True
    else if ALine[I] = '{' then
    begin
      CloseAt:= Pos('}', ALine, I);
      if CloseAt = 0 then Exit(0);
      I:= CloseAt;
    end
    else if (ALine[I] = '(') and (I < Length(ALine)) and (ALine[I + 1] = '*') then
    begin
      CloseAt:= Pos('*)', ALine, I + 2);
      if CloseAt = 0 then Exit(0);
      I:= CloseAt + 1;
    end
    else if (ALine[I] = '/') and (I < Length(ALine)) and (ALine[I + 1] = '/') then
      Exit(I);
    Inc(I);
  end;
end;

{ Leading whitespace of ALine. }
function LeadingWs(const ALine: string): string;
begin
  Result:= Copy(ALine, 1, Length(ALine) - Length(TrimLeft(ALine)));
end;

function NewEdit(const AFinding: TLintFinding; AKind: TTextEditKind): TTextEdit;
begin
  Result:= Default(TTextEdit);
  Result.FilePath:= AFinding.FilePath;
  Result.Kind    := AKind;
end;

{ A tekReplaceInLine edit that removes a trailing comment starting at ACommentCol together with the blanks
  before it. }
function DropTrailingComment(const AFinding: TLintFinding; ALineNo: Integer; const ALine: string;
  ACommentCol: Integer): TTextEdit;
var
  FromCol: Integer;
begin
  FromCol:= ACommentCol;
  while (FromCol > 1) and (ALine[FromCol - 1] = ' ') do Dec(FromCol);
  Result:= NewEdit(AFinding, tekReplaceInLine);
  Result.Line      := ALineNo;
  Result.Col       := FromCol;
  Result.EndCol    := Length(ALine) + 1;
  Result.ExpectText:= Copy(ALine, FromCol, MaxInt);
  Result.Text      := '';
end;

{ commented-out-code: a comment alone on its line(s) is deleted with them; a trailing `//` comment after code is
  cut off (with the blanks before it). Declines for a comment that shares a line with code on BOTH sides, and for a
  comment carrying a dl:ok marker (removing a marker is review-marker-unused's job). }
function FixCommentedOutCode(const AFinding: TLintFinding; ALines: TStringList): TArray<TTextEdit>;
var
  First: string;
  Last : string;
  Pre  : string;
  Post : string;
  Span : string;
  E    : TTextEdit;
begin
  Result:= nil;
  if (AFinding.StartLine < 1) or (AFinding.EndLine < AFinding.StartLine) or (AFinding.EndLine > ALines.Count) then Exit;
  First:= ALines[AFinding.StartLine - 1];
  Last := ALines[AFinding.EndLine - 1];
  if (AFinding.StartCol < 1) or (AFinding.StartCol > Length(First) + 1) or (AFinding.EndCol < 1)
     or (AFinding.EndCol > Length(Last) + 1) then Exit;
  Pre := Trim(Copy(First, 1, AFinding.StartCol - 1));
  Post:= Trim(Copy(Last, AFinding.EndCol, MaxInt));
  if (Pre <> '') and (Post <> '') then Exit;
  Span:= if AFinding.StartLine = AFinding.EndLine then Copy(First, AFinding.StartCol, AFinding.EndCol - AFinding.StartCol)
    else Copy(First, AFinding.StartCol, MaxInt);
  if Span.ToLower.Contains(MARKER_TOKEN) then Exit;
  if (Pre = '') and (Post = '') then
  begin
    E:= NewEdit(AFinding, tekDeleteLines);
    E.Line   := AFinding.StartLine;
    E.EndLine:= AFinding.EndLine;
    Result:= [E];
    Exit;
  end;
  { code on exactly one side: only a single-line trailing comment can be cut cleanly }
  if (Pre <> '') and (Post = '') and (AFinding.StartLine = AFinding.EndLine) then
    Result:= [DropTrailingComment(AFinding, AFinding.StartLine, First, AFinding.StartCol)];
end;

{ doc-param-not-in-signature: deletes the whole `/// <param name="X">...</param>` tag (one or several lines) from
  the doc block that documents the routine. Declines unless the tag opens and closes on `///` lines of its own, and
  declines while a signature parameter has no tag of its own: that is a RENAME, whose hand prose doc-drift keeps
  report-only (ADP3 T3) for a human to carry over. }
function FixDocParamNotInSignature(const AFinding: TLintFinding; ALines: TStringList): TArray<TTextEdit>;  // dl:ok too-many-exit-points@064f -- REVIEWED 2026-10-28: a fixer declines (Exit) on every source shape it was not written for (incl. a renamed param, INT); guard clauses by design
var
  Match : TMatch;
  Lo    : Integer;
  Hi    : Integer;
  I     : Integer;
  J     : Integer;
  Opener: string;
  E     : TTextEdit;

  function IsDoc(AIdx: Integer): Boolean;
  begin
    Result:= (AIdx >= 0) and (AIdx < ALines.Count) and TrimLeft(ALines[AIdx]).StartsWith('///');
  end;

  { True when a line of the doc block Lo..Hi matches APattern (case-insensitive). }
  function AnyLineMatches(const APattern: string): Boolean;
  begin
    Result:= False;
    for var L:= Lo to Hi do
      if TRegEx.IsMatch(ALines[L], APattern, [roIgnoreCase]) then Exit(True);
  end;

  { True when the declaration below the doc block (Hi + 1 ..) names a parameter no <param> tag in Lo..Hi
    documents. Reads up to the first ')' that closes the parameter list; no list = no parameters. }
  function SignatureHasUntaggedParam: Boolean;
  const
    MAX_SIG_LINES = 20;   { a parameter list longer than this is not worth a guess: read what fits }
  var
    Sig  : string;
    Open : Integer;
    Close: Integer;
    K    : Integer;
  begin
    Result:= False;
    Sig:= '';
    K:= Hi + 1;
    while (K < ALines.Count) and (K <= Hi + MAX_SIG_LINES) do
    begin
      Sig:= Sig + ' ' + ALines[K];
      if Sig.Contains(')') or (not Sig.Contains('(') and Sig.Contains(';')) then Break;
      Inc(K);
    end;
    Open:= Sig.IndexOf('(');
    Close:= Sig.IndexOf(')');
    if (Open < 0) or (Close < Open) then Exit;
    for var Group in Sig.Substring(Open + 1, Close - Open - 1).Split([';']) do
    begin
      var Names:= TRegEx.Replace(Group.Split([':'])[0], '\[[^\]]*\]', '');
      Names:= TRegEx.Replace(Names, '^\s*(const|var|out|constref)\s+', '', [roIgnoreCase]);
      for var N in Names.Split([',']) do
        if (Trim(N) <> '') and not AnyLineMatches('<param\s+name\s*=\s*"' + TRegEx.Escape(Trim(N)) + '"') then
          Exit(True);
    end;
  end;

begin
  Result:= nil;
  Match:= TRegEx.Match(AFinding.Message, '^documented param "([^"]+)" not in signature');
  if not Match.Success then Exit;
  if (AFinding.StartLine < 1) or (AFinding.StartLine > ALines.Count) then Exit;
  { the doc block: the contiguous /// lines holding the anchor, or ending right above it }
  Lo:= AFinding.StartLine - 1;
  if not IsDoc(Lo) then Dec(Lo);
  if not IsDoc(Lo) then Exit;
  Hi:= Lo;
  while IsDoc(Lo - 1) do Dec(Lo);
  while IsDoc(Hi + 1) do Inc(Hi);
  if SignatureHasUntaggedParam then Exit;
  Opener:= '^\s*///\s*<param\s+name\s*=\s*"' + TRegEx.Escape(Match.Groups[1].Value) + '"[^>]*>';
  for I:= Lo to Hi do
    if TRegEx.IsMatch(ALines[I], Opener, [roIgnoreCase]) then
    begin
      J:= I;
      while (J <= Hi) and not ALines[J].Contains(PARAM_CLOSE) do
      begin
        Inc(J);
        if (J <= Hi) and ALines[J].ToLower.Contains('<param') then Exit;
      end;
      if (J > Hi) or not Trim(ALines[J]).EndsWith(PARAM_CLOSE) then Exit;
      E:= NewEdit(AFinding, tekDeleteLines);
      E.Line   := I + 1;
      E.EndLine:= J + 1;
      Result:= [E];
      Exit;
    end;
end;

{ misleading-indentation: re-indents the flagged statement (all the lines of its span, by the same shift) to the
  indentation of the controlling statement named in the message. Spaces only: declines when either indentation holds
  a tab, or a continuation line is indented less than the shift. }
function FixMisleadingIndentation(const AFinding: TLintFinding; ALines: TStringList): TArray<TTextEdit>;
var
  Match : TMatch;
  CtlNo : Integer;
  Target: string;
  Cur   : string;
  Shift : Integer;
  I     : Integer;
  Text  : string;
  Cont  : string;
  E     : TTextEdit;
begin
  Result:= nil;
  Match:= TRegEx.Match(AFinding.Message, 'controlled by the \w+ at line (\d+)');
  if not Match.Success then Exit;
  CtlNo:= StrToIntDef(Match.Groups[1].Value, 0);
  if (CtlNo < 1) or (CtlNo > ALines.Count) or (AFinding.StartLine < 1) or (AFinding.EndLine < AFinding.StartLine)
     or (AFinding.EndLine > ALines.Count) then Exit;
  Target:= LeadingWs(ALines[CtlNo - 1]);
  Cur   := LeadingWs(ALines[AFinding.StartLine - 1]);
  if Target.Contains(#9) or Cur.Contains(#9) or (Length(Target) >= Length(Cur)) then Exit;
  Shift:= Length(Cur) - Length(Target);
  Text := Target + Copy(ALines[AFinding.StartLine - 1], Length(Cur) + 1, MaxInt);
  for I:= AFinding.StartLine + 1 to AFinding.EndLine do
  begin
    Cont:= ALines[I - 1];
    if Trim(Cont) = '' then
      Text:= Text + #13#10 + Cont
    else
    begin
      if LeadingWs(Cont).Contains(#9) or (Length(LeadingWs(Cont)) < Shift) then Exit;
      Text:= Text + #13#10 + Copy(Cont, Shift + 1, MaxInt);
    end;
  end;
  E:= NewEdit(AFinding, tekReplaceLines);
  E.Line      := AFinding.StartLine;
  E.EndLine   := AFinding.EndLine;
  E.ExpectText:= ALines[AFinding.StartLine - 1];
  E.Text      := Text;
  Result:= [E];
end;

const
  { multiple-statements-per-line: the block indent the re-layout writes, the repo's own. }
  MSP_INDENT_STEP = 2;

type
  { One output line of the multiple-statements-per-line re-layout: Key = its block level relative to the
    input line, Value = its text without indentation. }
  TMspPiece = TPair<Integer, string>;

{ ALine with every blank and control character removed: the token stream of a line, for the
  multiple-statements-per-line re-layout's "whitespace only" self-check. }
function StripBlanks(const ALine: string): string;
var
  Sb: TStringBuilder;
  C : Char;
begin
  Sb:= TStringBuilder.Create;
  try
    for C in ALine do
      if C > ' ' then Sb.Append(C);
    Result:= Sb.ToString;
  finally
    Sb.Free;
  end;
end;

{ True for a character that can continue a Delphi identifier. }
function IsIdentChar(AChar: Char): Boolean;
begin
  Result:= CharInSet(AChar, ['A'..'Z', 'a'..'z', '0'..'9', '_']) or (Ord(AChar) > Ord(High(AnsiChar)));
end;

{ True when a word (identifier or keyword) starts at AIdx of ABody: not a digit, not the tail of a
  longer word, and not a member (`.X`), an escaped identifier (`&end`), a char code or a hex literal. }
function IsWordStart(const ABody: string; AIdx: Integer): Boolean;
begin
  Result:= IsIdentChar(ABody[AIdx]) and not CharInSet(ABody[AIdx], ['0'..'9']) and
           ((AIdx = 1) or not (IsIdentChar(ABody[AIdx - 1]) or CharInSet(ABody[AIdx - 1], ['&', '.', '#', '$'])));
end;

{ Index of the last character of the string literal or comment that starts at AFrom in ABody;
  0 when none starts there; -1 when it is unterminated on the line or is a compiler directive. }
function OpaqueEnd(const ABody: string; AFrom: Integer): Integer;
var
  N: Integer;
begin
  N:= Length(ABody);
  Result:= 0;
  if ABody[AFrom] = '''' then
  begin
    Result:= AFrom + 1;
    while (Result <= N) and not ((ABody[Result] = '''') and ((Result = N) or (ABody[Result + 1] <> ''''))) do
      Inc(Result, if ABody[Result] = '''' then 2 else 1);
    if Result > N then Result:= -1;
  end
  else if ABody[AFrom] = '{' then
  begin
    Result:= Pos('}', ABody, AFrom + 1);
    if (Result = 0) or (Copy(ABody, AFrom, 2) = '{$') then Result:= -1;
  end
  else if Copy(ABody, AFrom, 2) = '(*' then
  begin
    Result:= Pos('*)', ABody, AFrom + 2);
    Result:= if Result = 0 then -1 else Result + 1;
  end;
end;

{ The re-laid-out text: one line per piece, indented AIndent plus MSP_INDENT_STEP per level (a negative
  level steps back out of AIndent), lines joined by CRLF; ATail (a // comment) ends the last line. }
function JoinPieces(const APieces: TArray<TMspPiece>; const AIndent, ATail: string): string;
var
  Sb: TStringBuilder;
  K : Integer;
begin
  Sb:= TStringBuilder.Create;
  try
    for K:= 0 to High(APieces) do
    begin
      if K > 0 then Sb.Append(#13#10);
      if APieces[K].Key >= 0 then Sb.Append(AIndent).Append(' ', APieces[K].Key * MSP_INDENT_STEP)
      else Sb.Append(Copy(AIndent, 1, Length(AIndent) + APieces[K].Key * MSP_INDENT_STEP));
      Sb.Append(APieces[K].Value);
    end;
    if ATail <> '' then Sb.Append(' ').Append(ATail);
    Result:= Sb.ToString;
  finally
    Sb.Free;
  end;
end;

{ Re-lays out ONE source line that packs several statements, in one pass (v1523 FIXER-2: the old fixer
  broke the line once, so `if C then begin A; B; end;` became `if C then begin A;` + `B; end;`).
  Every top-level `;` ends a statement; a top-level `begin` goes on its own line at the indentation of
  the statement that owns it and indents what follows by one step; a top-level `end` (with the `;` or
  `.` right after it) closes that step. An `end` that opens the line keeps the line's indentation; one
  closing a block opened on an EARLIER line steps back out of it. An `else` in the middle of the text
  that owns a `begin` (`if C then A else begin`) starts its own line, as `end else begin` does:
  `else` / `begin`. A trailing // comment stays on the last line. Strings, brace and paren-star
  comments and anything inside ( ) or [ ] are copied untouched.
  Declines (False) on what it cannot lay out without guessing: a compiler directive, an unterminated
  string or comment, brackets that do not balance on the line (a statement spanning lines), the
  block keywords case / try / repeat / until / except / finally / asm / record, or a result whose
  non-blank characters differ from the input's. }
function SplitStatementLine(const ALine: string; out AText: string): Boolean;
const
  DECLINE_WORDS: array[0..7] of string = ('case', 'try', 'repeat', 'until', 'except', 'finally', 'asm', 'record');
var
  Indent: string;
  Body  : string;
  Tail  : string;
  Word  : string;
  Cur   : TStringBuilder;
  Pieces: TArray<TMspPiece>;
  I     : Integer;
  J     : Integer;
  N     : Integer;
  Depth : Integer;
  Level : Integer;
  ElseAt: Integer;

  procedure Emit(ALevel: Integer; const AText: string);
  begin
    Pieces:= Pieces + [TMspPiece.Create(ALevel, AText)];
  end;

  procedure Flush;
  begin
    if Trim(Cur.ToString) <> '' then Emit(Level, Trim(Cur.ToString));
    Cur.Clear;
    ElseAt:= 0;
  end;

  { `end` and the `;` or `.` right after it close one block level. }
  procedure TakeEnd;
  begin
    Flush;
    if Length(Pieces) > 0 then Dec(Level);
    J:= I;
    while (J <= N) and (Body[J] = ' ') do Inc(J);
    if (J <= N) and CharInSet(Body[J], [';', '.']) then
    begin
      Word:= Word + Body[J];
      I:= J + 1;
    end;
    Emit(Level, Word);
  end;

  { A word at bracket depth 0; False = decline the line. }
  function TakeWord: Boolean;
  begin
    Result:= not MatchText(Word, DECLINE_WORDS);
    if not Result then Exit;
    if SameText(Word, 'begin') then
    begin
      if ElseAt > 0 then
      begin
        Emit(Level, Trim(Cur.ToString(0, ElseAt)));
        Cur.Remove(0, ElseAt);
      end;
      Flush;
      Emit(Level, Word);
      Inc(Level);
    end
    else if SameText(Word, 'end') then TakeEnd
    else
    begin
      if SameText(Word, 'else') and (Trim(Cur.ToString) <> '') then ElseAt:= Cur.Length;
      Cur.Append(Word);
    end;
  end;

begin
  Result:= False;
  AText:= '';
  Indent:= LeadingWs(ALine);
  Body:= TrimRight(Copy(ALine, Length(Indent) + 1, MaxInt));
  N:= Length(Body);
  Tail:= '';
  Depth:= 0;
  Level:= 0;
  ElseAt:= 0;
  Cur:= TStringBuilder.Create;
  try
    I:= 1;
    while I <= N do
    begin
      J:= OpaqueEnd(Body, I);
      if J < 0 then Exit;
      if J > 0 then
      begin
        Cur.Append(Body, I - 1, J - I + 1);
        I:= J + 1;
      end
      else if Copy(Body, I, 2) = '//' then
      begin
        Tail:= Copy(Body, I, MaxInt);
        Break;
      end
      else if IsWordStart(Body, I) then
      begin
        J:= I;
        while (J <= N) and IsIdentChar(Body[J]) do Inc(J);
        Word:= Copy(Body, I, J - I);
        I:= J;
        if Depth > 0 then Cur.Append(Word)
        else if not TakeWord then Exit;
      end
      else
      begin
        if CharInSet(Body[I], ['(', '[']) then Inc(Depth)
        else if CharInSet(Body[I], [')', ']']) then Dec(Depth);
        if Depth < 0 then Exit;
        Cur.Append(Body[I]);
        if (Depth = 0) and (Body[I] = ';') then Flush;
        Inc(I);
      end;
    end;
    if Depth <> 0 then Exit;
    Flush;
  finally
    Cur.Free;
  end;
  if Length(Pieces) < 2 then Exit;
  AText:= JoinPieces(Pieces, Indent, Tail);
  Result:= StripBlanks(AText) = StripBlanks(ALine);
end;

{ multiple-statements-per-line: re-lays out the flagged line so every statement stands on its own line,
  in ONE pass (SplitStatementLine). The rule flags the first extra statement of a line, so this sees each
  packed line once. Declines whenever SplitStatementLine does. }
function FixMultipleStatementsPerLine(const AFinding: TLintFinding; ALines: TStringList): TArray<TTextEdit>;
var
  Line: string;
  Text: string;
  E   : TTextEdit;
begin
  Result:= nil;
  if (AFinding.StartLine < 1) or (AFinding.StartLine > ALines.Count) then Exit;
  Line:= ALines[AFinding.StartLine - 1];
  if not SplitStatementLine(Line, Text) then Exit;
  E:= NewEdit(AFinding, tekReplaceLines);
  E.Line      := AFinding.StartLine;
  E.EndLine   := AFinding.StartLine;
  E.ExpectText:= Line;
  E.Text      := Text;
  Result:= [E];
end;

{ review-marker-placeholder-hash: replaces the placeholder or malformed @hash of the marker on the finding's line
  by the hash the engine computes for the marked finding (the line and rule the message names in its `allow
  --fix-line N --fix-rule R` advice). Declines for the block-comment and no-finding forms (no such advice), and for
  the routine-metric rules, whose hash also folds in a measured number the marker finding does not carry. }
function FixPlaceholderHash(const AFinding: TLintFinding; ALines: TStringList): TArray<TTextEdit>;  // dl:ok too-many-exit-points@8629 -- REVIEWED 2026-10-27: a fixer declines (Exit) on every source shape it was not written for; guard clauses by design
var
  Match   : TMatch;
  Rule    : string;
  FixLine : Integer;
  Line    : string;
  Hash    : TGroup;
  Plain   : TArray<string>;
  I       : Integer;
  Want    : string;
  E       : TTextEdit;
begin
  Result:= nil;
  Match:= TRegEx.Match(AFinding.Message, '--fix-line (\d+) --fix-rule ([A-Za-z0-9_-]+)$');
  if not Match.Success then Exit;
  FixLine:= StrToIntDef(Match.Groups[1].Value, 0);
  Rule   := Match.Groups[2].Value;
  if (FixLine < 1) or (FixLine > ALines.Count) or (AFinding.StartLine < 1) or (AFinding.StartLine > ALines.Count)
     or IsRoutineMetricRule(Rule) then Exit;
  Line:= ALines[AFinding.StartLine - 1];
  if FindLineCommentCol(Line) = 0 then Exit;
  Match:= TRegEx.Match(Copy(Line, FindLineCommentCol(Line), MaxInt),
    MARKER_TOKEN + '\s+(?:[^@]*?[\s,])?' + TRegEx.Escape(Rule) + '@([^\s,]*)', [roIgnoreCase]);
  if not Match.Success then Exit;
  Hash:= Match.Groups[1];
  if not (TReviewMarkers.IsPlaceholderHash(Hash.Value) or TReviewMarkers.IsMalformedHash(Hash.Value)) then Exit;
  SetLength(Plain, ALines.Count);
  for I:= 0 to ALines.Count - 1 do Plain[I]:= ALines[I];
  Want:= MarkerExpectedHash(Plain, Rule, FixLine, 0);
  if (Want = '') or SameText(Want, Hash.Value) then Exit;
  E:= NewEdit(AFinding, tekReplaceInLine);
  E.Line      := AFinding.StartLine;
  E.Col       := FindLineCommentCol(Line) - 1 + Hash.Index;
  E.EndCol    := E.Col + Hash.Length;
  E.ExpectText:= Hash.Value;
  E.Text      := Want;
  Result:= [E];
end;

{ review-marker-unused: deletes the dead marker -- the whole line when the `// dl:ok ...` comment stands alone,
  else just the trailing comment. Declines unless the comment starts with dl:ok and names exactly the one rule the
  message reports (a list `dl:ok a, b` would lose a live review with it). }
function FixUnusedMarker(const AFinding: TLintFinding; ALines: TStringList): TArray<TTextEdit>;  // dl:ok too-many-exit-points@2ddc -- REVIEWED 2026-10-27: a fixer declines (Exit) on every source shape it was not written for; guard clauses by design
var
  Match: TMatch;
  Line : string;
  CCol : Integer;
  Rules: string;
  E    : TTextEdit;
begin
  Result:= nil;
  Match:= TRegEx.Match(AFinding.Message, '^dl:ok marker for "([^"]+)" no longer matches');
  if not Match.Success then Exit;
  if (AFinding.StartLine < 1) or (AFinding.StartLine > ALines.Count) then Exit;
  Line:= ALines[AFinding.StartLine - 1];
  CCol:= FindLineCommentCol(Line);
  if CCol = 0 then Exit;
  Rules:= Copy(Line, CCol, MaxInt);
  Rules:= TRegEx.Match(Rules, '^//\s*' + MARKER_TOKEN + '\s+(.*)$', [roIgnoreCase]).Groups[1].Value;
  if Rules = '' then Exit;
  Rules:= Trim(Rules.Split([' -- '])[0]);
  if not TRegEx.IsMatch(Rules, '^' + TRegEx.Escape(Match.Groups[1].Value) + '(@[0-9A-Za-z]*|:.*)?$', [roIgnoreCase]) then Exit;
  if Trim(Copy(Line, 1, CCol - 1)) = '' then
  begin
    E:= NewEdit(AFinding, tekDeleteLines);
    E.Line   := AFinding.StartLine;
    E.EndLine:= AFinding.StartLine;
    Result:= [E];
    Exit;
  end;
  Result:= [DropTrailingComment(AFinding, AFinding.StartLine, Line, CCol)];
end;

{ True when line AIdx (0-based) of ALines lies inside a `drag-lint:auto BEGIN .. END` fence: the nearest fence
  marker above it, within the same run of /// lines, is a BEGIN. }
function InsideManagedFence(ALines: TStringList; AIdx: Integer): Boolean;
begin
  for var K:= AIdx - 1 downto 0 do
  begin
    var T: string:= TrimLeft(ALines[K]);
    if not T.StartsWith(DOC_LINE_TOKEN) then Exit(False);
    if T.Contains(FENCE_END) then Exit(False);
    if T.Contains(FENCE_BEGIN) then Exit(True);
  end;
  Result:= False;
end;

{ Breaks APrefix + AText into lines of at most DOC_FACT_MAX_COLS columns, each starting with APrefix: at the
  rightmost blank inside the budget that follows ',' or ';', else at the rightmost blank; one blank is dropped at
  each break. The managed-fact writer's own policy (WrapFactLine), applied to any doc text. nil when a single token
  is longer than the budget -- no break leaves every line under the limit. }
function WrapDocText(const APrefix, AText: string): TArray<string>;
var
  Rest  : string;
  Budget: Integer;
  B     : Integer;
  Top   : Integer;
begin
  Result:= nil;
  Rest  := AText;
  Budget:= DOC_FACT_MAX_COLS - Length(APrefix);
  if Budget < 2 then Exit;
  while Length(Rest) > Budget do
  begin
    Top:= Budget + 1;
    B:= 0;
    for var K:= Top downto 2 do
      if (Rest[K] = ' ') and CharInSet(Rest[K - 1], [',', ';']) then
      begin
        B:= K;
        Break;
      end;
    if B = 0 then
      for var K:= Top downto 2 do
        if Rest[K] = ' ' then
        begin
          B:= K;
          Break;
        end;
    if B = 0 then Exit(nil);
    Result:= Result + [APrefix + Copy(Rest, 1, B - 1)];
    Rest:= Copy(Rest, B + 1, MaxInt);
  end;
  Result:= Result + [APrefix + Rest];
end;

{ line-too-long: re-wraps an over-long `///` line at blanks so every line is under the compiler-safe limit. Inside
  the managed fence only a <para> fact line is wrapped, and exactly as the writer wraps it (WrapFactLine), because
  the fence readers fold a split <para> back and nothing else; a legacy fence line declines. Declines for any line
  that is not a `///` comment (code, `//`, braces) and when no break gets every line under the limit. }
function FixLineTooLong(const AFinding: TLintFinding; ALines: TStringList): TArray<TTextEdit>;
var
  Line  : string;
  Prefix: string;
  Text  : string;
  Wrap  : TArray<string>;
  E     : TTextEdit;
begin
  Result:= nil;
  if (AFinding.StartLine < 1) or (AFinding.StartLine > ALines.Count) then Exit;
  Line:= ALines[AFinding.StartLine - 1];
  if not TrimLeft(Line).StartsWith(DOC_LINE_TOKEN) then Exit;
  Prefix:= LeadingWs(Line) + DOC_LINE_TOKEN;
  if Copy(Line, Length(Prefix) + 1, 1) = ' ' then Prefix:= Prefix + ' ';
  Text:= Copy(Line, Length(Prefix) + 1, MaxInt);
  if InsideManagedFence(ALines, AFinding.StartLine - 1) then
  begin
    if not Text.StartsWith(FACT_PARA) then Exit;
    Wrap:= WrapFactLine(Prefix, Text);
  end
  else
    Wrap:= WrapDocText(Prefix, Text);
  if Length(Wrap) < 2 then Exit;
  for var W in Wrap do
    if Length(W) > MAX_SAFE_LINE_LEN then Exit;
  E:= NewEdit(AFinding, tekReplaceLines);
  E.Line      := AFinding.StartLine;
  E.EndLine   := AFinding.StartLine;
  E.ExpectText:= Line;
  E.Text      := string.Join(#13#10, Wrap);
  Result:= [E];
end;

initialization
  RegisterFixer('line-too-long', FixLineTooLong);
  RegisterFixer('commented-out-code', FixCommentedOutCode);
  RegisterFixer('doc-param-not-in-signature', FixDocParamNotInSignature);
  RegisterFixer('misleading-indentation', FixMisleadingIndentation);
  RegisterFixer('multiple-statements-per-line', FixMultipleStatementsPerLine);
  RegisterFixer('review-marker-placeholder-hash', FixPlaceholderHash, True);
  RegisterFixer('review-marker-unused', FixUnusedMarker);

end.
