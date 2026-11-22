unit DRagLint.Fix.Expr;

{ Lane A2 -- expression-level code fixers (16 ids) of the autofix wave
  (docs\superpowers\plans\2026-10-27-autofix-wave-plan.md). Created EMPTY by lane
  A0 and already listed in drag-lint.dpr / .dproj, so lane A2 edits only this
  unit.

  Most checkers behind these ids report a ONE-CHARACTER span at the start of the
  construct (their F.EndCol is StartCol + 1), so every fixer re-reads the
  construct from the finding's start column in the file's own text and DECLINES
  (returns no edits) whenever the text is not exactly the shape it was written
  for. Every edit carries an ExpectText guard.

  Ids and what each one declines:
    mixed-case-hex, unreadable-literal  never (pure literal respelling)
    deprecated-rtl-function             everything but StrPas(X) -> string(X); OemToAnsi / AnsiToOem
                                        have no one-to-one replacement and stay
    gettickcount-wraparound             unless the call is assigned to an Int64 / UInt64 variable
    ifthen-to-if-expression             comments in the statement, nested if / begin / case, an array arm,
                                        a bare `[..]` constructor arm (E2010 / F2084), and in a generic
                                        routine any non-plain arm unless the target is a built-in type
    nonminimal-bool (veto only)         a record operand, or no operand proven to have built-in equality;
                                        the accepted shapes go through DRagLint.Fix.Templates
    useless-format                      unless the element is a string literal or a string-typed local
    locale-sensitive-conversion (risky) unless the call sits in a persistence sink (WriteString, AddPair,
                                        SetValue, .Values[..], .AsString :=) and is a Float / Currency call
    float-equality-comparison           an operand it cannot delimit (unary minus, a larger expression)
    length-zero-compare                 Length(S) < 0 / 0 > Length(S) (always false: not a rewrite)
    win64-pointer-cast                  an assignment of the cast (the target's type is the real fix)
    freeandnil-on-interface (risky)     never
    unsafe-typecast-without-is (risky)  a cast that is itself an assignment target
    firedac-open-execsql-mismatch (risky) never
    double-dictionary-lookup (risky)    any condition but the bare ContainsKey call; any body whose first
                                        statement is not `V := D[K];`; an else branch
    case-same-branches                  multi-line arms, quoted labels, arms at different indents
    enum-bare-read-scoped               the BOUND warning (a different symbol is meant there) and any
                                        finding naming more than one candidate enum

  The unit registers itself from its OWN initialization; DRagLint.Lint.Autofix
  never uses a fixer unit, so no unit cycle forms. }

interface

implementation

uses
  System.SysUtils
  , System.Classes
  , System.StrUtils
  , System.Math
  , System.RegularExpressions
  , DRagLint.Core.Model
  , DRagLint.Core.Interfaces
  , DRagLint.Refactor.TextEdit
  , DRagLint.Lint.Autofix
  , DRagLint.Fix.Templates
  ;

const
  STRPAS_NAME       = 'StrPas';
  DIGIT_GROUP       = 3;
  HEX_ALPHABET      = '0123456789abcdefABCDEF_';
  INVARIANT_ARG     = ', TFormatSettings.Invariant)';
  SAMEVALUE_UNIT    = 'System.Math';
  INT64_TYPES       = '|int64|uint64|';
  STRING_TYPES      = '|string|unicodestring|ansistring|widestring|';
  LOCALE_CALLS      = '|strtofloat|floattostr|strtocurr|currtostr|';
  END_WORDS         = '|then|do|else|of|to|downto|until|';
  SINK_RE           = '\.(WriteString|AddPair|SetValue)\s*\(|\.Values\s*\[|\.AsString\s*:=';
  IDENT_RE          = '[A-Za-z_]\w*';
  NEQ_TOKEN         = '<>';
  SPACES_RE         = '\s+';
  SEARCH_LINE_GROUP = 3;
  LEGACY_TAIL_GROUP = 3;   // shared-marker-legacy-shape: the optional trailing `// note` group
  PAST_CR_COL       = 2;   // EndCol of a comment node that carries the CR: Length(line) + 2
  MAX_ALIAS_HOPS    = 3;   // TypeSafety follows `T = U;` aliases this deep
  LITERAL_RE        = '^(nil|true|false|-?\d[\w.]*|\$[0-9a-f]+|''([^'']|'''')*''|#\d+)$';
  ROUTINE_HEAD_RE   = '^(?<ind>\s*)(class\s+)?(function|procedure|constructor|destructor|operator)\s+(?<n>[\w.<>, ]+)';
  BUILTIN_TYPES     = '|integer|cardinal|shortint|smallint|longint|int8|int16|int32|int64|byte|word|longword|' +
    'uint8|uint16|uint32|uint64|nativeint|nativeuint|fixedint|fixeduint|boolean|bytebool|wordbool|longbool|' +
    'char|ansichar|widechar|string|unicodestring|ansistring|widestring|shortstring|rawbytestring|utf8string|' +
    'single|double|extended|real|currency|comp|tdatetime|tdate|ttime|pointer|pchar|pansichar|pwidechar|' +
    'variant|olevariant|tobject|tclass|iinterface|iunknown|';

{ ---- shared helpers ---- }

{ The finding's line, when StartLine is inside the file. }
function LineOf(const AFinding: TLintFinding; ALines: TStringList; out ALine: string): Boolean;
begin
  Result:= InRange(AFinding.StartLine, 1, ALines.Count);
  ALine := if Result then ALines[AFinding.StartLine - 1] else '';
end;

{ One guarded in-line replacement of [ACol, ACol + Length(AExpect)) by AText. }
function ReplaceEdit(const APath: string; ALine, ACol: Integer; const AExpect, AText: string): TTextEdit;
begin
  Result:= Default(TTextEdit);
  Result.FilePath  := APath;
  Result.Kind      := tekReplaceInLine;
  Result.Line      := ALine;
  Result.Col       := ACol;
  Result.EndCol    := ACol + Length(AExpect);
  Result.Text      := AText;
  Result.ExpectText:= AExpect;
end;

{ The text of the finding's own single-line span ('' when it is not one). A comment node on a CRLF file
  ends one column past the line text (it carries the CR); that one column is clamped, any larger overshoot
  still declines. }
function SpanText(const AFinding: TLintFinding; const ALine: string): string;
var
  EndCol: Integer;
begin
  Result:= '';
  EndCol:= AFinding.EndCol;
  if EndCol = Length(ALine) + PAST_CR_COL then EndCol:= Length(ALine) + 1; // the CR of a CRLF row
  if (AFinding.StartLine <> AFinding.EndLine) or (AFinding.StartCol < 1) or
     (EndCol <= AFinding.StartCol) or (EndCol > Length(ALine) + 1) then Exit;
  Result:= Copy(ALine, AFinding.StartCol, EndCol - AFinding.StartCol);
end;

{ Leading whitespace of ALine. }
function IndentOf(const ALine: string): string;
begin
  Result:= Copy(ALine, 1, Length(ALine) - Length(TrimLeft(ALine)));
end;

{ Is the lower-cased, trimmed AType one of the `|a|b|` list? }
function TypeIn(const AType, AList: string): Boolean;
begin
  Result:= AList.Contains('|' + LowerCase(Trim(AType)) + '|');
end;

{ ---- mixed-case-hex, unreadable-literal ---- }

{ mixed-case-hex: the literal's hex digits all upper case. }
function FixMixedCaseHex(const AFinding: TLintFinding; ALines: TStringList): TArray<TTextEdit>;
var
  Line: string;
  Span: string;
  C   : Char  ;
begin
  Result:= nil;
  if not LineOf(AFinding, ALines, Line) then Exit;
  Span:= SpanText(AFinding, Line);
  if (Length(Span) < 2) or (Span[1] <> '$') then Exit;
  for C in Copy(Span, 2, MaxInt) do
    if not HEX_ALPHABET.Contains(C) then Exit;
  if Span = UpperCase(Span) then Exit;
  Result:= [ReplaceEdit(AFinding.FilePath, AFinding.StartLine, AFinding.StartCol, Span, UpperCase(Span))];
end;

{ unreadable-literal: an `_` between every three digits, counted from the right. }
function FixUnreadableLiteral(const AFinding: TLintFinding; ALines: TStringList): TArray<TTextEdit>;
var
  Line: string ;
  Span: string ;
  Spelt: string;
  I   : Integer;
  SB  : TStringBuilder;
begin
  Result:= nil;
  if not LineOf(AFinding, ALines, Line) then Exit;
  Span:= SpanText(AFinding, Line);
  if not TRegEx.IsMatch(Span, '^[0-9]+$') then Exit;
  SB:= TStringBuilder.Create;
  try
    for I:= 1 to Length(Span) do
    begin
      if (I > 1) and ((Length(Span) - I + 1) mod DIGIT_GROUP = 0) then SB.Append('_');
      SB.Append(Span[I]);
    end;
    Spelt:= SB.ToString;
  finally
    SB.Free;
  end;
  Result:= [ReplaceEdit(AFinding.FilePath, AFinding.StartLine, AFinding.StartCol, Span, Spelt)];
end;

{ ---- deprecated-rtl-function, gettickcount-wraparound ---- }

{ deprecated-rtl-function: StrPas(X) -> string(X); only the callee identifier is replaced. }
function FixDeprecatedRtl(const AFinding: TLintFinding; ALines: TStringList): TArray<TTextEdit>;
var
  Line: string;
  Name: string;
begin
  Result:= nil;
  if not LineOf(AFinding, ALines, Line) then Exit;
  Name:= Copy(Line, AFinding.StartCol, Length(STRPAS_NAME));
  if not SameText(Name, STRPAS_NAME) then Exit;
  if not TRegEx.IsMatch(Copy(Line, AFinding.StartCol + Length(STRPAS_NAME), MaxInt), '^\s*\(') then Exit;
  Result:= [ReplaceEdit(AFinding.FilePath, AFinding.StartLine, AFinding.StartCol, Name, 'string')];
end;

{ gettickcount-wraparound: GetTickCount -> GetTickCount64 where the call is assigned to a
  declared Int64 / UInt64 variable (`V := GetTickCount ...`); Cardinal arithmetic stays. }
function FixGetTickCount(const AFinding: TLintFinding; ALines: TStringList): TArray<TTextEdit>;
var
  Line  : string;
  Name  : string;
  Prefix: string;
  Match : TMatch;
begin
  Result:= nil;
  if not LineOf(AFinding, ALines, Line) then Exit;
  Name:= SpanText(AFinding, Line);
  if not SameText(Name, 'GetTickCount') then Exit;
  Prefix:= Copy(Line, 1, AFinding.StartCol - 1);
  Match:= TRegEx.Match(Prefix, '^\s*(' + IDENT_RE + ')\s*:=\s*$');
  if not Match.Success then Exit;
  if not TypeIn(DeclTypeOf(AFinding.FilePath, AFinding.StartLine, Match.Groups[1].Value), INT64_TYPES) then Exit;
  Result:= [ReplaceEdit(AFinding.FilePath, AFinding.StartLine, AFinding.StartCol, Name, Name + '64')];
end;

{ ---- operand typing shared by ifthen-to-if-expression and nonminimal-bool ---- }

type
  { What a fixer can prove about one operand of the expression it rewrites. }
  TOperandSafety = (osUnknown, osSafe, osUnsafe);

{ True when AOperand is a literal: a number, a quoted string, a #char, nil, True or False. }
function IsLiteralOperand(const AOperand: string): Boolean;
begin
  Result:= TRegEx.IsMatch(Trim(AOperand), LITERAL_RE, [roIgnoreCase]);
end;

{ True when AOperand is one bare identifier. }
function IsBareIdent(const AOperand: string): Boolean;
begin
  Result:= TRegEx.IsMatch(Trim(AOperand), '^' + IDENT_RE + '$');
end;

{ The last segment of a dotted name, without a generic argument list. }
function TypeBaseName(const AType: string): string;
var
  P: Integer;
begin
  Result:= Trim(AType);
  P:= Pos('<', Result);
  if P > 0 then Result:= Copy(Result, 1, P - 1);
  P:= LastDelimiter('.', Result);
  if P > 0 then Result:= Copy(Result, P + 1, MaxInt);
end;

{ osUnsafe when AType is (an alias of) a record -- its = / <> exist only as declared operators, and
  a record helper may declare Equal without NotEqual (TTSNode); osSafe for a built-in scalar or string
  type, a pointer, a class, an interface, an enum or a set; osUnknown otherwise. Reads the fix run's
  store when one is open, else the file's own type declarations. }
function TypeSafety(const AType: string; ALines: TStringList; ADepth: Integer): TOperandSafety;  // dl:ok too-many-exit-points@a212 -- REVIEWED 2026-11-21 FIXER-COMPILE: one guard clause per type shape (built-in, record, class, alias, file fallback); declining early is the fixer contract
var
  T    : string     ;
  S    : TSymbol    ;
  Store: ISymbolStore;
  Sub  : TOperandSafety;
  Match: TMatch     ;
begin
  Result:= osUnknown;
  T:= Trim(AType);
  if (T = '') or (ADepth > MAX_ALIAS_HOPS) then Exit;
  if TypeIn(T, BUILTIN_TYPES) or T.StartsWith('^') then Exit(osSafe);
  T:= TypeBaseName(T);
  if not TRegEx.IsMatch(T, '^' + IDENT_RE + '$') then Exit;
  Store:= AutofixStore;
  if Store <> nil then
    for S in Store.FindSymbolsByExactName(T) do
      case S.Kind of
        skRecord:
          Exit(osUnsafe);   { a record helper is skRecord too: both mean "operators decide" }
        skClass, skInterface, skEnum, skClassRef, skForm:
          Result:= osSafe;
        skTypeAlias:
          begin
            Sub:= TypeSafety(S.Signature, ALines, ADepth + 1);
            if Sub = osUnsafe then Exit(osUnsafe);
            if Sub = osSafe then Result:= osSafe;
          end;
      end;
  if Result <> osUnknown then Exit;
  { no store, or the store does not know the name: the file's own declaration }
  if TRegEx.IsMatch(ALines.Text, '(?im)^\s*' + T + '\s*=\s*(packed\s+)?record\b') then Exit(osUnsafe);
  if TRegEx.IsMatch(ALines.Text, '(?im)^\s*' + T + '\s*=\s*(class|interface|dispinterface|set\s+of)\b|^\s*' + T + '\s*=\s*\(') then
    Exit(osSafe);
  Match:= TRegEx.Match(ALines.Text, '(?im)^\s*' + T + '\s*=\s*(type\s+)?(?<a>[\w.]+)\s*;');
  if Match.Success then Result:= TypeSafety(Match.Groups['a'].Value, ALines, ADepth + 1);
end;

{ What can be proven about AOperand at AFinding's line: a literal is safe, a bare identifier is as safe
  as its declared type (an enum value found in the store is safe), anything else is unknown. }
function OperandSafety(const AFinding: TLintFinding; ALines: TStringList; const AOperand: string): TOperandSafety;
var
  O    : string     ;
  S    : TSymbol    ;
  Store: ISymbolStore;
begin
  Result:= osUnknown;
  O:= Trim(AOperand);
  if IsLiteralOperand(O) then Exit(osSafe);
  if not IsBareIdent(O) then Exit;
  Result:= TypeSafety(DeclTypeOf(AFinding.FilePath, AFinding.StartLine, O), ALines, 0);
  if Result <> osUnknown then Exit;
  Store:= AutofixStore;
  if Store <> nil then
    for S in Store.FindSymbolsByExactName(O) do
      if S.Kind = skEnumValue then Exit(osSafe);
end;

{ ---- ifthen-to-if-expression ---- }

{ True when AOperand is a bare identifier whose declared type is an array (so it cannot join an if-expression). }
function IsArrayOperand(const AFinding: TLintFinding; const AOperand: string): Boolean;
begin
  Result:= IsBareIdent(AOperand) and
    TRegEx.IsMatch(Trim(DeclTypeOf(AFinding.FilePath, AFinding.StartLine, Trim(AOperand))), '^array\b', [roIgnoreCase]);
end;

{ True when AOperand holds an array or set constructor `[..]` outside any parentheses (an indexer
  `A[I]` and an open-array argument `F(X, [Y])` do not count). dcc 37 rejects `A + [X]` as an
  if-expression arm with E2010, and a longer one stops it with internal error F2084. }
function HasBareConstructor(const AOperand: string): Boolean;
var
  I    : Integer;
  P    : Integer;
  Depth: Integer;
  InStr: Boolean;
begin
  Result:= False;
  Depth:= 0;
  InStr:= False;
  for I:= 1 to Length(AOperand) do
  begin
    if AOperand[I] = '''' then InStr:= not InStr;
    if InStr then Continue;
    case AOperand[I] of
      '(': Inc(Depth);
      ')': Dec(Depth);
      '[':
        if Depth = 0 then
        begin
          P:= I - 1;
          while (P >= 1) and (AOperand[P] = ' ') do Dec(P);
          if (P < 1) or not CharInSet(AOperand[P], ['A'..'Z', 'a'..'z', '0'..'9', '_', ')', ']', '^']) then Exit(True);
        end;
    end;
  end;
end;

{ True when the routine around line ALine (or a routine it is nested in) is generic: a header
  `TFoo<T>.Bar` or `function Bar<T>`. Scans up to the nearest routine header in column 1. }
function InGenericRoutine(ALines: TStringList; ALine: Integer): Boolean;
var
  I    : Integer;
  Match: TMatch ;
begin
  Result:= False;
  for I:= Min(ALine, ALines.Count) - 1 downto 0 do
  begin
    Match:= TRegEx.Match(ALines[I], ROUTINE_HEAD_RE, [roIgnoreCase]);
    if not Match.Success then Continue;
    if Match.Groups['n'].Value.Contains('<') then Exit(True);
    if Match.Groups['ind'].Value = '' then Exit;
  end;
end;

{ True when an if-expression with arms AA / AB assigned to ATarget is proven to compile. Declines
  (False) on a bare array/set constructor arm (E2010 / F2084), and, inside a generic routine, on any
  arm that is not a literal or a declared local unless the target has a built-in type: dcc 37 types a
  method call of a generic-typed result there as a procedure value (E2010 'procedure, untyped
  pointer or untyped parameter'). }
function IfExprArmsCompile(const AFinding: TLintFinding; ALines: TStringList; const ATarget, AA, AB: string): Boolean;

  function PlainArm(const AArm: string): Boolean;
  begin
    Result:= IsLiteralOperand(AArm) or
      (IsBareIdent(AArm) and (DeclTypeOf(AFinding.FilePath, AFinding.StartLine, Trim(AArm)) <> ''));
  end;

begin
  Result:= False;
  if HasBareConstructor(AA) or HasBareConstructor(AB) then Exit;
  if InGenericRoutine(ALines, AFinding.StartLine) and
     not (IsBareIdent(ATarget) and TypeIn(DeclTypeOf(AFinding.FilePath, AFinding.StartLine, Trim(ATarget)), BUILTIN_TYPES)) and
     not (PlainArm(AA) and PlainArm(AB)) then Exit;
  Result:= True;
end;

{ ifthen-to-if-expression: `if C then X := A else X := B;` -> `X := if C then A else B;`,
  one line, in the statement's own indent. }
function FixIfThenToIfExpr(const AFinding: TLintFinding; ALines: TStringList): TArray<TTextEdit>;
const
  SHAPE = '^if\s+(?<c>.+?)\s+then\s+(?<l>[\w.]+)(?<op>\s*:=\s*)(?<a>.+?)\s+else\s+\k<l>\s*:=\s*(?<b>.+?)\s*(?<semi>;?)$';
  NESTED= '\b(if|then|else|begin|end|case|try)\b|//|\{|\(\*';
var
  I     : Integer;
  First : string ;
  Last  : string ;
  Text  : string ;
  Match : TMatch ;
  NewTxt: string ;
  E     : TTextEdit;
begin
  Result:= nil;
  if (AFinding.StartLine < 1) or (AFinding.EndLine < AFinding.StartLine) or (AFinding.EndLine > ALines.Count) then Exit;
  First:= ALines[AFinding.StartLine - 1];
  Last := ALines[AFinding.EndLine - 1];
  if Trim(Copy(First, 1, AFinding.StartCol - 1)) <> '' then Exit;
  if (AFinding.EndCol < 1) or (AFinding.EndCol > Length(Last) + 1) or (Trim(Copy(Last, AFinding.EndCol, MaxInt)) <> '') then Exit;
  Text:= Copy(First, AFinding.StartCol, MaxInt);
  if AFinding.EndLine = AFinding.StartLine then Text:= Copy(First, AFinding.StartCol, AFinding.EndCol - AFinding.StartCol)
  else
  begin
    for I:= AFinding.StartLine + 1 to AFinding.EndLine - 1 do Text:= Text + ' ' + Trim(ALines[I - 1]);
    Text:= Text + ' ' + Trim(Copy(Last, 1, AFinding.EndCol - 1));
  end;
  Match:= TRegEx.Match(Trim(Text), SHAPE, [roIgnoreCase, roSingleLine]);
  if not Match.Success then Exit;
  if TRegEx.IsMatch(Match.Groups['c'].Value + ' ' + Match.Groups['a'].Value + ' ' + Match.Groups['b'].Value,
    NESTED, [roIgnoreCase]) then Exit;
  { a bare array-typed operand (array of Char beside a string) is not an if-expression operand: E2010 }
  if IsArrayOperand(AFinding, Match.Groups['a'].Value) or IsArrayOperand(AFinding, Match.Groups['b'].Value) then Exit;
  if not IfExprArmsCompile(AFinding, ALines, Match.Groups['l'].Value, Match.Groups['a'].Value, Match.Groups['b'].Value) then Exit;
  NewTxt:= Match.Groups['l'].Value + Match.Groups['op'].Value + 'if ' + Match.Groups['c'].Value + ' then ' +
    Match.Groups['a'].Value + ' else ' + Match.Groups['b'].Value + Match.Groups['semi'].Value;
  E:= Default(TTextEdit);
  E.FilePath:= AFinding.FilePath;
  if AFinding.EndLine = AFinding.StartLine then
    E:= ReplaceEdit(AFinding.FilePath, AFinding.StartLine, AFinding.StartCol, Text, NewTxt)
  else
  begin
    E.Kind      := tekReplaceLines;
    E.Line      := AFinding.StartLine;
    E.EndLine   := AFinding.EndLine;
    E.Text      := IndentOf(First) + NewTxt;
    E.ExpectText:= First;
  end;
  Result:= [E];
end;

{ ---- useless-format, locale-sensitive-conversion ---- }

{ useless-format: Format('%s', [X]) -> X, for a string literal or a string-typed declared local. }
function FixUselessFormat(const AFinding: TLintFinding; ALines: TStringList): TArray<TTextEdit>;
var
  Line: string;
  Span: string;
  Arg : string;
  Match: TMatch;
begin
  Result:= nil;
  if not LineOf(AFinding, ALines, Line) then Exit;
  Span:= SpanText(AFinding, Line);
  Match:= TRegEx.Match(Span, '^Format\s*\(\s*''%s''\s*,\s*\[\s*(.+?)\s*\]\s*\)$', [roIgnoreCase]);
  if not Match.Success then Exit;
  Arg:= Match.Groups[1].Value;
  if not TRegEx.IsMatch(Arg, '^''(?:[^'']|'''')*''$') then
  begin
    if not TRegEx.IsMatch(Arg, '^' + IDENT_RE + '$') then Exit;
    if not TypeIn(DeclTypeOf(AFinding.FilePath, AFinding.StartLine, Arg), STRING_TYPES) then Exit;
  end;
  Result:= [ReplaceEdit(AFinding.FilePath, AFinding.StartLine, AFinding.StartCol, Span, Arg)];
end;

{ locale-sensitive-conversion: StrToFloat / FloatToStr / StrToCurr / CurrToStr in a persistence sink
  gain `, TFormatSettings.Invariant` as the last argument. The rule fires only for a call without a comma. }
function FixLocaleConversion(const AFinding: TLintFinding; ALines: TStringList): TArray<TTextEdit>;
var
  Line : string;
  Span : string;
  Match: TMatch;
begin
  Result:= nil;
  if not LineOf(AFinding, ALines, Line) then Exit;
  Span:= SpanText(AFinding, Line);
  Match:= TRegEx.Match(Span, '^(' + IDENT_RE + ')\s*\(.*\)$');
  if (not Match.Success) or not TypeIn(Match.Groups[1].Value, LOCALE_CALLS) then Exit;
  if not TRegEx.IsMatch(Line, SINK_RE, [roIgnoreCase]) then Exit;
  Result:= [ReplaceEdit(AFinding.FilePath, AFinding.StartLine, AFinding.EndCol - 1, ')', INVARIANT_ARG)];
end;

{ ---- float-equality-comparison (per file: one `uses` edit for all findings) ---- }

{ Skips a balanced (...) or [...] group starting at S[P]; strings are skipped whole. }
function SkipGroup(const S: string; var P: Integer): Boolean;
var
  Depth: Integer;
begin
  Result:= False;
  Depth:= 0;
  while P <= Length(S) do
  begin
    if S[P] = '''' then
    begin
      Inc(P);
      while (P <= Length(S)) and (S[P] <> '''') do Inc(P);
    end
    else if CharInSet(S[P], ['(', '[']) then Inc(Depth)
    else if CharInSet(S[P], [')', ']']) then
    begin
      Dec(Depth);
      if Depth = 0 then
      begin
        Inc(P);
        Exit(True);
      end;
    end;
    Inc(P);
  end;
end;

{ Scans one operand (identifier / number / dotted path with call and index groups, or a
  parenthesised group) at S[P]; P ends just after it. False when none starts here. }
function ScanOperand(const S: string; var P: Integer): Boolean;
begin
  Result:= False;
  if P > Length(S) then Exit;
  if S[P] = '(' then Exit(SkipGroup(S, P));
  if not CharInSet(S[P], ['A'..'Z', 'a'..'z', '0'..'9', '_']) then Exit;
  while P <= Length(S) do
  begin
    if CharInSet(S[P], ['A'..'Z', 'a'..'z', '0'..'9', '_', '.']) then Inc(P)
    else if CharInSet(S[P], ['(', '[']) then
    begin
      if not SkipGroup(S, P) then Exit(False);
    end
    else Break;
  end;
  Result:= True;
end;

{ The edit for one float-equality finding: `A = B` -> `SameValue(A, B)`, `A <> B` -> `not SameValue(A, B)`;
  declined unless both operands delimit cleanly and the right one ends the expression. }
function FloatEqualityEdit(const AFinding: TLintFinding; ALines: TStringList; out AEdit: TTextEdit): Boolean;
var
  Line   : string ;
  P, A0  : Integer;
  B0     : Integer;
  LhsEnd : Integer;
  Lhs    : string ;
  Rhs    : string ;
  Neq    : Boolean;
  Tail   : string ;
  Word   : string ;
begin
  Result:= False;
  AEdit:= Default(TTextEdit);
  if not LineOf(AFinding, ALines, Line) then Exit;
  P:= AFinding.StartCol;
  A0:= P;
  if not ScanOperand(Line, P) then Exit;
  LhsEnd:= P;
  Lhs:= Copy(Line, A0, LhsEnd - A0);
  while (P <= Length(Line)) and (Line[P] = ' ') do Inc(P);
  Neq:= Copy(Line, P, NEQ_TOKEN.Length) = NEQ_TOKEN;
  if Neq then Inc(P, NEQ_TOKEN.Length)
  else if Copy(Line, P, 1) = '=' then Inc(P)
  else Exit;
  while (P <= Length(Line)) and (Line[P] = ' ') do Inc(P);
  B0:= P;
  if not ScanOperand(Line, P) then Exit;
  Rhs:= Copy(Line, B0, P - B0);
  Tail:= TrimLeft(Copy(Line, P, MaxInt));
  if (Tail <> '') and not CharInSet(Tail[1], [')', ';', ',', ']']) then
  begin
    Word:= LowerCase(TRegEx.Match(Tail, '^[A-Za-z]+').Value);
    if (Word = '') or not END_WORDS.Contains('|' + Word + '|') then Exit;
  end;
  AEdit:= ReplaceEdit(AFinding.FilePath, AFinding.StartLine, A0, Copy(Line, A0, P - A0),
    IfThen(Neq, 'not ', '') + 'System.Math.SameValue(' + Lhs + ', ' + Rhs + ')');
  Result:= True;
end;

{ float-equality-comparison, once per file: the edits for every finding in APath plus ONE
  `uses System.Math` insertion (SameValue lives there). }
function FixFloatEqualityFile(const APath: string; const AFindings: TArray<TLintFinding>; out AFixed: Integer): TArray<TTextEdit>;
var
  Lines: TStringList;
  F    : TLintFinding;
  E    : TTextEdit   ;
begin
  Result:= nil;
  AFixed:= 0;
  Lines:= TStringList.Create;
  try
    Lines.LoadFromFile(APath);
    { a unit declaring its own SameValue hides System.Math's: the rewrite would call the wrong overload set }
    if TRegEx.IsMatch(Lines.Text, '^\s*(?:function|procedure)\s+SameValue\b', [roIgnoreCase, roMultiLine]) then Exit;
    for F in AFindings do
      if SameText(F.RuleId, 'float-equality-comparison') and SameText(F.FilePath, APath) and
         FloatEqualityEdit(F, Lines, E) then
      begin
        Result:= Result + [E];
        Inc(AFixed);
      end;
    if (AFixed > 0) and EnsureImplUses(APath, Lines, SAMEVALUE_UNIT, E) then Result:= Result + [E];
  finally
    Lines.Free;
  end;
end;

{ ---- length-zero-compare, win64-pointer-cast ---- }

{ length-zero-compare: Length(S) = 0 -> S = '', Length(S) > 0 / <> 0 -> S <> '' (either operand order).
  The rule fires only for a string-typed identifier. `< 0` is always false and is left alone. }
function FixLengthZero(const AFinding: TLintFinding; ALines: TStringList): TArray<TTextEdit>;
const
  LEN_FIRST = '^Length\s*\(\s*(' + IDENT_RE + ')\s*\)\s*(=|<>|>)\s*0(?![\w.])';
  ZERO_FIRST= '^0\s*(=|<>|<)\s*Length\s*\(\s*(' + IDENT_RE + ')\s*\)';
var
  Line : string ;
  Rest : string ;
  Match: TMatch ;
  Name : string ;
  Op   : string ;
begin
  Result:= nil;
  if not LineOf(AFinding, ALines, Line) then Exit;
  Rest:= Copy(Line, AFinding.StartCol, MaxInt);
  Match:= TRegEx.Match(Rest, LEN_FIRST, [roIgnoreCase]);
  if Match.Success then
  begin
    Name:= Match.Groups[1].Value;
    Op  := Match.Groups[2].Value;
  end
  else
  begin
    Match:= TRegEx.Match(Rest, ZERO_FIRST, [roIgnoreCase]);
    if not Match.Success then Exit;
    Name:= Match.Groups[2].Value;
    Op  := Match.Groups[1].Value;
  end;
  Result:= [ReplaceEdit(AFinding.FilePath, AFinding.StartLine, AFinding.StartCol, Match.Value,
    Name + IfThen(Op = '=', ' = ', ' <> ') + '''''')];
end;

{ win64-pointer-cast: Integer(P) -> NativeInt(P), Cardinal(P) -> NativeUInt(P) (LongInt / LongWord alike),
  in an expression; the direct right-hand side of `:=` stays (the target's type is the real fix). }
function FixWin64Cast(const AFinding: TLintFinding; ALines: TStringList): TArray<TTextEdit>;
var
  Line  : string;
  Match : TMatch;
  Native: string;
begin
  Result:= nil;
  if not LineOf(AFinding, ALines, Line) then Exit;
  Match:= TRegEx.Match(Copy(Line, AFinding.StartCol, MaxInt), '^(Integer|LongInt|Cardinal|LongWord)\s*\(', [roIgnoreCase]);
  if not Match.Success then Exit;
  if TrimRight(Copy(Line, 1, AFinding.StartCol - 1)).EndsWith(':=') then Exit;
  Native:= IfThen(MatchText(Match.Groups[1].Value, ['Integer', 'LongInt']), 'NativeInt', 'NativeUInt');
  Result:= [ReplaceEdit(AFinding.FilePath, AFinding.StartLine, AFinding.StartCol, Match.Groups[1].Value, Native)];
end;

{ ---- freeandnil-on-interface, unsafe-typecast-without-is, firedac-open-execsql-mismatch ---- }

{ freeandnil-on-interface: FreeAndNil(I) -> I := nil. }
function FixFreeAndNilInterface(const AFinding: TLintFinding; ALines: TStringList): TArray<TTextEdit>;
var
  Line : string;
  Match: TMatch;
begin
  Result:= nil;
  if not LineOf(AFinding, ALines, Line) then Exit;
  Match:= TRegEx.Match(Copy(Line, AFinding.StartCol, MaxInt), '^FreeAndNil\s*\(\s*(' + IDENT_RE + '(?:\.' + IDENT_RE + ')*)\s*\)', [roIgnoreCase]);
  if not Match.Success then Exit;
  Result:= [ReplaceEdit(AFinding.FilePath, AFinding.StartLine, AFinding.StartCol, Match.Value, Match.Groups[1].Value + ' := nil')];
end;

{ unsafe-typecast-without-is: TFoo(X) -> (X as TFoo): an EInvalidCast instead of silent corruption. }
function FixUnsafeTypecast(const AFinding: TLintFinding; ALines: TStringList): TArray<TTextEdit>;
var
  Line : string;
  Rest : string;
  Match: TMatch;
begin
  Result:= nil;
  if not LineOf(AFinding, ALines, Line) then Exit;
  Rest := Copy(Line, AFinding.StartCol, MaxInt);
  Match:= TRegEx.Match(Rest, '^(' + IDENT_RE + ')\s*\(\s*(' + IDENT_RE + ')\s*\)');
  if not Match.Success then Exit;
  if TRegEx.IsMatch(Copy(Rest, Match.Length + 1, MaxInt), '^\s*:=') then Exit;
  Result:= [ReplaceEdit(AFinding.FilePath, AFinding.StartLine, AFinding.StartCol, Match.Value,
    '(' + Match.Groups[2].Value + ' as ' + Match.Groups[1].Value + ')')];
end;

{ firedac-open-execsql-mismatch: Q.Open on a data-modifying statement -> Q.ExecSQL, and the reverse
  (the finding's message names which one it is). }
function FixFireDacMismatch(const AFinding: TLintFinding; ALines: TStringList): TArray<TTextEdit>;
var
  Line  : string;
  Match : TMatch;
  Target: string;
begin
  Result:= nil;
  if not LineOf(AFinding, ALines, Line) then Exit;
  Match:= TRegEx.Match(Copy(Line, AFinding.StartCol, MaxInt), '^' + IDENT_RE + '\.(Open|ExecSQL)\b', [roIgnoreCase]);
  if not Match.Success then Exit;
  Target:= IfThen(AFinding.Message.StartsWith('Open on'), 'ExecSQL', 'Open');
  if SameText(Match.Groups[1].Value, Target) then Exit;
  Result:= [ReplaceEdit(AFinding.FilePath, AFinding.StartLine, AFinding.StartCol + Match.Groups[1].Index - 1,
    Match.Groups[1].Value, Target)];
end;

{ ---- double-dictionary-lookup ---- }

{ double-dictionary-lookup: `if D.ContainsKey(K) then V := D[K];` -> `D.TryGetValue(K, V);`, and for a
  begin..end body whose FIRST statement is `V := D[K];` the header becomes `if D.TryGetValue(K, V) then`
  and that statement is deleted. Any other shape stays. }
function FixDoubleDictionary(const AFinding: TLintFinding; ALines: TStringList): TArray<TTextEdit>;
const
  HEADER = '^if\s+(' + IDENT_RE + '(?:\.' + IDENT_RE + ')*)\.ContainsKey\s*\(\s*(' + IDENT_RE + '(?:\.' + IDENT_RE +
    ')*|''[^'']*''|\d+)\s*\)\s+then\b\s*(.*)$';
var
  Line, Rest, Recv, Key, Stmt: string;
  Head   : TMatch;
  StmtM  : TMatch;
  I      : Integer;
  FirstL : Integer;
  Indent : string;
  Edits  : TArray<TTextEdit>;
  E      : TTextEdit;

  { `V := D[K];` (or D.Items[K]) with V neither the receiver nor the key; the match carries V in group 1. }
  function StmtShape(const AText: string; out AMatch: TMatch): Boolean;
  begin
    AMatch:= TRegEx.Match(Trim(AText), '^(' + IDENT_RE + ')\s*:=\s*' + TRegEx.Escape(Recv) + '(?:\.Items)?\[' +
      TRegEx.Escape(Key) + '\]\s*;?$', [roIgnoreCase]);
    Result:= AMatch.Success and not (SameText(AMatch.Groups[1].Value, Key) or SameText(AMatch.Groups[1].Value, Recv));
  end;

begin
  Result:= nil;
  if not LineOf(AFinding, ALines, Line) then Exit;
  Indent:= Copy(Line, 1, AFinding.StartCol - 1);
  if Trim(Indent) <> '' then Exit;
  Rest:= Copy(Line, AFinding.StartCol, MaxInt);
  Head:= TRegEx.Match(Rest, HEADER, [roIgnoreCase]);
  if not Head.Success then Exit;
  Recv:= Head.Groups[1].Value;
  Key := Head.Groups[2].Value;
  Stmt:= Trim(Head.Groups[SEARCH_LINE_GROUP].Value);
  if Stmt <> '' then
  begin
    { one line: if D.ContainsKey(K) then V := D[K]; }
    if (AFinding.EndLine <> AFinding.StartLine) or (AFinding.EndCol <> Length(Line) + 1) then Exit;
    if StmtShape(Stmt, StmtM) then
      Result:= [ReplaceEdit(AFinding.FilePath, AFinding.StartLine, AFinding.StartCol, Rest,
        Recv + '.TryGetValue(' + Key + ', ' + StmtM.Groups[1].Value + ');')];
    Exit;
  end;
  if AFinding.StartLine >= ALines.Count then Exit;
  if StmtShape(ALines[AFinding.StartLine], StmtM) then
  begin
    { header, then a single statement line }
    if AFinding.EndLine <> AFinding.StartLine + 1 then Exit;
    E:= Default(TTextEdit);
    E.FilePath  := AFinding.FilePath;
    E.Kind      := tekReplaceLines;
    E.Line      := AFinding.StartLine;
    E.EndLine   := AFinding.StartLine + 1;
    E.Text      := Indent + Recv + '.TryGetValue(' + Key + ', ' + StmtM.Groups[1].Value + ');';
    E.ExpectText:= Line;
    Result:= [E];
    Exit;
  end;
  { begin on its own line, then the statement }
  if not SameText(Trim(ALines[AFinding.StartLine]), 'begin') then Exit;
  FirstL:= AFinding.StartLine + 2;
  if FirstL > ALines.Count then Exit;
  if not StmtShape(ALines[FirstL - 1], StmtM) then Exit;
  for I:= AFinding.StartLine + 1 to AFinding.EndLine - 1 do
    if (IndentOf(ALines[I]) = Indent) and TRegEx.IsMatch(Trim(ALines[I]), '^(end\s+)?else\b', [roIgnoreCase]) then Exit;
  Edits:= [ReplaceEdit(AFinding.FilePath, AFinding.StartLine, AFinding.StartCol, Rest,
    'if ' + Recv + '.TryGetValue(' + Key + ', ' + StmtM.Groups[1].Value + ') then')];
  E:= Default(TTextEdit);
  E.FilePath  := AFinding.FilePath;
  E.Kind      := tekDeleteLines;
  E.Line      := FirstL;
  E.EndLine   := FirstL;
  E.ExpectLine:= FirstL;
  E.ExpectText:= Trim(ALines[FirstL - 1]);
  Result:= Edits + [E];
end;

{ ---- case-same-branches, enum-bare-read-scoped ---- }

{ case-same-branches: `1: S; 2: S;` -> `1, 2: S;`. Both arms must be one line, unquoted labels, same indent,
  the same body; the later arm line is deleted and its labels join the earlier arm. }
function FixCaseSameBranches(const AFinding: TLintFinding; ALines: TStringList): TArray<TTextEdit>;
const
  ARM = '^(\s*)([^:''"{}/]+?)\s*:\s*(\S.*?)\s*;?\s*$';
var
  Line  : string;
  First : Integer;
  Match : TMatch;
  A, B  : TMatch;
  Insrt : TTextEdit;
  Del   : TTextEdit;
begin
  Result:= nil;
  if not LineOf(AFinding, ALines, Line) then Exit;
  Match:= TRegEx.Match(AFinding.Message, 'line (\d+)');
  if not Match.Success then Exit;
  First:= StrToIntDef(Match.Groups[1].Value, 0);
  if (First < 1) or (First >= AFinding.StartLine) then Exit;
  if (AFinding.EndLine <> AFinding.StartLine) then Exit;
  A:= TRegEx.Match(ALines[First - 1], ARM);
  B:= TRegEx.Match(Line, ARM);
  if (not A.Success) or (not B.Success) then Exit;
  if (A.Groups[1].Value <> B.Groups[1].Value) or (AFinding.StartCol <> Length(B.Groups[1].Value) + 1) then Exit;
  if TRegEx.Replace(A.Groups[SEARCH_LINE_GROUP].Value, SPACES_RE, ' ') <> TRegEx.Replace(B.Groups[SEARCH_LINE_GROUP].Value, SPACES_RE, ' ') then Exit;
  Insrt:= Default(TTextEdit);
  Insrt.FilePath:= AFinding.FilePath;
  Insrt.Kind    := tekInsertInLine;
  Insrt.Line    := First;
  Insrt.Col     := Length(A.Groups[1].Value) + Length(A.Groups[2].Value) + 1;
  Insrt.Text    := ', ' + B.Groups[2].Value;
  Del:= Default(TTextEdit);
  Del.FilePath  := AFinding.FilePath;
  Del.Kind      := tekDeleteLines;
  Del.Line      := AFinding.StartLine;
  Del.EndLine   := AFinding.StartLine;
  Del.ExpectLine:= AFinding.StartLine;
  Del.ExpectText:= Trim(Line);
  Result:= [Insrt, Del];
end;

{ enum-bare-read-scoped: the UNBOUND hint (`write TEnum.Value (else E2003)`) names exactly one
  spelling; the bare name is replaced by it. The BOUND warning (another symbol is read there) is a
  judgment call and stays. }
function FixEnumBareRead(const AFinding: TLintFinding; ALines: TStringList): TArray<TTextEdit>;
var
  Line : string;
  Span : string;
  Match: TMatch;
begin
  Result:= nil;
  if not SameText(AFinding.Severity, 'hint') then Exit;
  if not LineOf(AFinding, ALines, Line) then Exit;
  Span:= SpanText(AFinding, Line);
  if (Span = '') or not SameText(Span, AFinding.SymbolName) then Exit;
  Match:= TRegEx.Match(AFinding.Message, ' write (' + IDENT_RE + '\.' + IDENT_RE + ') \(else E2003\)');
  if not Match.Success then Exit;
  Result:= [ReplaceEdit(AFinding.FilePath, AFinding.StartLine, AFinding.StartCol, Span, Match.Groups[1].Value)];
end;

{ ---- empty-finally, format-string-not-formatted, shared-marker-legacy-shape (v151 WID-SCM) ---- }

{ A source line holding only AWord (trailing `;` and a // comment tolerated). }
function IsWordLine(const ALine, AWord: string): Boolean;
begin
  Result:= TRegEx.IsMatch(ALine, '^\s*' + AWord + '\s*;?\s*(//.*)?$', [roIgnoreCase]);
end;

{ One whole-line delete guarded by the line's current trimmed text. }
function DeleteLineEdit(const APath: string; ALine: Integer; const AText: string): TTextEdit;
begin
  Result:= Default(TTextEdit);
  Result.FilePath  := APath;
  Result.Kind      := tekDeleteLines;
  Result.Line      := ALine;
  Result.EndLine   := ALine;
  Result.ExpectLine:= ALine;
  Result.ExpectText:= Trim(AText);
end;

{ empty-finally: the aligned shape
      try
        <statements>;
      finally
      end;
  is unwrapped -- the `try`, `finally` and `end;` lines are deleted and the body stays. The nearest
  `try` line with the finding's indent must be reached through strictly deeper lines only; the line
  before `try` must end a statement (`;`) or open a block (`begin`), so a `try` that is the body of
  `if .. then` / `else` / `do` is left alone; the last body line must end in `;`. }
function FixEmptyFinally(const AFinding: TLintFinding; ALines: TStringList): TArray<TTextEdit>;  // dl:ok too-many-exit-points@7c3d -- REVIEWED 2026-11-13: a fixer declines (Exit) on every source shape it was not written for; guard clauses by design
var
  Line  : string;
  Ind   : Integer;
  I     : Integer;
  TryAt : Integer;
  Prev  : string;
  Body  : string;
begin
  Result:= nil;
  if not LineOf(AFinding, ALines, Line) then Exit;
  if (AFinding.StartLine >= ALines.Count) or not IsWordLine(Line, 'finally') then Exit;
  if not TRegEx.IsMatch(ALines[AFinding.StartLine], '^\s*end\s*;\s*(//.*)?$', [roIgnoreCase]) then Exit;
  Ind:= Length(IndentOf(Line));
  if Length(IndentOf(ALines[AFinding.StartLine])) <> Ind then Exit;
  TryAt:= 0;
  for I:= AFinding.StartLine - 2 downto 0 do
  begin
    if Trim(ALines[I]) = '' then Continue;
    if Length(IndentOf(ALines[I])) < Ind then Exit;
    if Length(IndentOf(ALines[I])) = Ind then
    begin
      if IsWordLine(ALines[I], 'try') and (not Trim(ALines[I]).Contains(';')) then TryAt:= I + 1;
      Break;
    end;
  end;
  if (TryAt < 2) or (TryAt >= AFinding.StartLine - 1) then Exit;
  Prev:= Trim(ALines[TryAt - 2]);
  if not (Prev.EndsWith(';') or SameText(Prev, 'begin')) then Exit;
  Body:= Trim(ALines[AFinding.StartLine - 2]);
  if (Body = '') or not Body.EndsWith(';') or Body.Contains('//') or Body.Contains('{') then Exit;
  Result:= [DeleteLineEdit(AFinding.FilePath, AFinding.StartLine + 1, ALines[AFinding.StartLine]),
            DeleteLineEdit(AFinding.FilePath, AFinding.StartLine, Line),
            DeleteLineEdit(AFinding.FilePath, TryAt, ALines[TryAt - 1])];
end;

{ format-string-not-formatted: Format('literal', []) with an EMPTY argument array becomes the literal.
  Any non-empty array is left alone (its arguments may have side effects or be a real mistake). }
function FixFormatNotFormatted(const AFinding: TLintFinding; ALines: TStringList): TArray<TTextEdit>;
var
  Line : string;
  Span : string;
  Match: TMatch;
begin
  Result:= nil;
  if not LineOf(AFinding, ALines, Line) then Exit;
  Span:= SpanText(AFinding, Line);
  Match:= TRegEx.Match(Span, '^(?:Wide)?Format\s*\(\s*(''(?:[^'']|'''')*'')\s*,\s*\[\s*\]\s*\)$', [roIgnoreCase]);
  if (not Match.Success) or Match.Groups[1].Value.Contains('%') then Exit;
  Result:= [ReplaceEdit(AFinding.FilePath, AFinding.StartLine, AFinding.StartCol, Span, Match.Groups[1].Value)];
end;

{ shared-marker-legacy-shape: `// note // dl:shared A, B` is rewritten to `// dl:shared A, B // note`.
  RISKY (opt-in): the rule cannot tell this from prose such as `// see // dl:shared below` (R12), and the
  rewrite would turn that prose into a marker naming `below`. }
function FixSharedMarkerLegacy(const AFinding: TLintFinding; ALines: TStringList): TArray<TTextEdit>;
var
  Line : string;
  Span : string;
  Match: TMatch;
  Note : string;
  Tail : string;
begin
  Result:= nil;
  if not LineOf(AFinding, ALines, Line) then Exit;
  Span:= Copy(Line, AFinding.StartCol, MaxInt); // a line comment runs to the end of the line (grammar v1.4.14: the node no longer carries the CR)
  Match:= TRegEx.Match(Span, '^//\s*(.*?)\s*//\s*(dl:shared\s+\S[^/]*?)\s*(//.*)?$', [roIgnoreCase]);
  if (not Match.Success) or (Match.Groups[1].Value = '') then Exit;
  Note:= Match.Groups[1].Value;
  Tail:= if Match.Groups.Count > LEGACY_TAIL_GROUP then Match.Groups[LEGACY_TAIL_GROUP].Value else ''; // an unmatched trailing group may be absent
  Result:= [ReplaceEdit(AFinding.FilePath, AFinding.StartLine, AFinding.StartCol, Span,
    '// ' + Match.Groups[2].Value + ' // ' + Note + (if Tail <> '' then ' ' + Tail else ''))];
end;

{ ---- nonminimal-bool ---- }

{ The pieces of AText split at every `=` / `<>` outside parentheses and string literals. }
function SplitAtEquality(const AText: string): TArray<string>;
var
  I    : Integer;
  From : Integer;
  Depth: Integer;
  InStr: Boolean;
begin
  Result:= nil;
  Depth:= 0;
  InStr:= False;
  From:= 1;
  I:= 1;
  while I <= Length(AText) do
  begin
    if AText[I] = '''' then InStr:= not InStr;
    if not InStr then
      case AText[I] of
        '(', '[': Inc(Depth);
        ')', ']': Dec(Depth);
        '=', '<':
          if (Depth = 0) and ((AText[I] = '=') or (Copy(AText, I, NEQ_TOKEN.Length) = NEQ_TOKEN)) and
             ((I = 1) or not CharInSet(AText[I - 1], [':', '<', '>'])) then
          begin
            Result:= Result + [Copy(AText, From, I - From)];
            if AText[I] = '<' then Inc(I);
            From:= I + 1;
          end;
      end;
    Inc(I);
  end;
  Result:= Result + [Copy(AText, From, MaxInt)];
end;

{ nonminimal-bool: the rule's sidecar template rewrites `not (A = B)` to `(A <> B)` and `not (A <> B)`
  to `(A = B)`. That compiles only when the type HAS the other operator: a record declares = / <> as
  operators, and TTSNode's helper declares Equal without NotEqual (E2015). The fix is offered only
  when no operand is (an alias of) a record and at least one operand is proven to have built-in
  equality (a literal, a declared local of a scalar / string / class / interface / enum type, an
  enum value); otherwise the finding stays, unfixed. `not (A in S)` has no such hazard. }
function FixNonminimalBool(const AFinding: TLintFinding; ALines: TStringList): TArray<TTextEdit>;
var
  Inner: string        ;
  Parts: TArray<string>;
  Part : string        ;
  Safe : Boolean       ;
  Sf   : TOperandSafety;
begin
  Result:= nil;
  if AFinding.FixKind <> lfkReplace then Exit;
  Inner:= Trim(AFinding.FixText);
  if (Length(Inner) < 2) or (Inner[1] <> '(') or (Inner[Length(Inner)] <> ')') then Exit;
  Inner:= Copy(Inner, 2, Length(Inner) - 2);
  if not TRegEx.IsMatch(Inner, '\snot\s+in\s', [roIgnoreCase]) then
  begin
    Parts:= SplitAtEquality(Inner);
    if Length(Parts) <> 2 then Exit;
    Safe:= False;
    for Part in Parts do
    begin
      Sf:= OperandSafety(AFinding, ALines, Part);
      if Sf = osUnsafe then Exit;
      if Sf = osSafe then Safe:= True;
    end;
    if not Safe then Exit;
  end;
  Result:= BuildSidecarFixEdits(AFinding, ALines);
end;

initialization
  RegisterFixer('nonminimal-bool', FixNonminimalBool);
  RegisterFixer('mixed-case-hex', FixMixedCaseHex);
  RegisterFixer('unreadable-literal', FixUnreadableLiteral);
  RegisterFixer('deprecated-rtl-function', FixDeprecatedRtl);
  RegisterFixer('gettickcount-wraparound', FixGetTickCount);
  RegisterFixer('ifthen-to-if-expression', FixIfThenToIfExpr);
  RegisterFixer('useless-format', FixUselessFormat);
  RegisterFixer('locale-sensitive-conversion', FixLocaleConversion, True);
  RegisterFileFixer('float-equality-comparison', FixFloatEqualityFile);
  RegisterFixer('length-zero-compare', FixLengthZero);
  RegisterFixer('win64-pointer-cast', FixWin64Cast);
  RegisterFixer('freeandnil-on-interface', FixFreeAndNilInterface, True);
  RegisterFixer('unsafe-typecast-without-is', FixUnsafeTypecast, True);
  RegisterFixer('firedac-open-execsql-mismatch', FixFireDacMismatch, True);
  RegisterFixer('double-dictionary-lookup', FixDoubleDictionary, True);
  RegisterFixer('case-same-branches', FixCaseSameBranches);
  RegisterFixer('enum-bare-read-scoped', FixEnumBareRead);
  RegisterFixer('empty-finally', FixEmptyFinally);
  RegisterFixer('format-string-not-formatted', FixFormatNotFormatted);
  RegisterFixer('shared-marker-legacy-shape', FixSharedMarkerLegacy, True);

end.
