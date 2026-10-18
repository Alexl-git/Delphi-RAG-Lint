unit DRagLint.Charts.Trace.Shim;

(* The round-trip CONDITION SHIM and the statement readers (a port of charts\src\Trace.Walk.ps1
  Part 2 and the helpers lines 16-36, 827-892, 1098-1121 and 2025-2070; the PS output is the
  reference). The index holds tokens, not conditions. For an Exit the index ALREADY anchored (a call
  ref named Exit inside the routine) the branch around it is read from the source and its condition
  quoted VERBATIM from the RAW text -- never negated or rewritten. Everything here is PURE over two
  line arrays (raw, and comment/string-stripped with the same columns), so synthetic cases test it.
  The FRESH check (AC-14: a stale file is refused by name) is the caller's: Trace.Walk's TraceSource
  checks TSourceReader.SourceFresh and reads the lines, then calls in here.

  The branch is found on KEYWORD TOKENS of the stripped text, read backwards from the Exit (a line
  count cannot see `end else begin`, whose begin is the opener, nor an `if .. then .. else` NESTED
  inside the exit block). The token just before a statement says where it stands: `then` -> the
  if's then branch; `else` -> the else of the if (or case) it pairs with; `on .. do` -> an except
  handler; `;` / `begin` / `try` -> a statement of the enclosing block, whose opener is then read
  the same way. Forms:
    inline   the `if` and the Exit share a line  -> UNLESS C (then branch), WHEN C (else branch)
    block    the `if` is on an earlier line      -> the same keywords
    except   `try S .. except .. Exit`           -> UNLESS S raises; a body of several statements is
                                                    quoted "S1 ... Sn raises" (' ... ', never ' .. ',
                                                    Pascal's range operator -- ruling T4-R3)
    case     `case X of .. else .. Exit`         -> UNLESS case X of (ruling T4-C3)
    unknown  anything else: a loop, a case arm, no branch, a condition Form A cannot write
             unquoted, two Exits on the anchored line, a comment wrapping across the quoted
             lines, a conditional-compilation directive between the guard and the Exit. The Reason
             is plain GENERATED text the walker writes as a STOPS naming engine ask E1; never a
             guess, never an exception.

  KNOWN LIMIT (ruling T4-R4): the INNERMOST guard only. `if A then begin if B then Exit end` quotes
  B; that A also guards the Exit is not reported. Engine ask E1 (branch and condition facts from
  the syntax tree) retires this unit.

  Quoting (P16): a condition is the raw text between `if` and `then`. A wrapped one is JOINED: each
  line's piece runs from its first to its last code or string character (a comment at either END of
  a piece is dropped, as it would swallow the join; one inside is kept as written) and the pieces
  are joined with ONE space. Nothing inside a piece changes. A condition Form A cannot write
  unquoted (TraceCondProblem) comes back as a named unknown.

  PowerShell traps closed here: the token regex carries (?i) inline, so it is ONE case-insensitive
  regex and the tokens are lower-cased; lines are 1-based and columns 0-based, as in the PS (the
  Delphi string indexes are shifted inside); a PS statement-token ArrayList.GetRange(0, n) is a
  prefix count over the shared token array; Math.Min / Max become clamps; the unary-comma array
  returns are plain arrays; the PS object that Add-Member extends with the condition span is the
  fixed record TShimResult (CondL2 = 0 reads as 'no span'). *)

interface

const
  /// <summary>TraceWord's default length cap (the PS $Max = 72).</summary>
  TRACE_WORD_MAX = 72;

type
  /// <summary>One keyword token of the stripped source (a keyword of the shim's set, `;` or a `:` that is not `:=`).</summary>
  TShimToken = record
    /// <summary>1-based line.</summary>
    L: Integer;
    /// <summary>0-based start column.</summary>
    C: Integer;
    /// <summary>0-based end column, exclusive.</summary>
    E: Integer;
    /// <summary>The token, lower-cased.</summary>
    T: string;
  end;

  /// <summary>What the shim read around an Exit or a statement.</summary>
  /// <remarks>Form 'unknown' has Keyword, Condition '' and Reason set. SpanLine / SpanFrom / SpanTo are NOT
  /// here: Trace.Walk sets them on its own record. A value record; copy freely.</remarks>
  TShimResult = record
    /// <summary>'inline', 'block', 'except', 'case' or 'unknown'.</summary>
    Form: string;
    /// <summary>'UNLESS' or 'WHEN' ('' for unknown).</summary>
    Keyword: string;
    /// <summary>The condition, quoted verbatim from the raw text ('' for unknown).</summary>
    Condition: string;
    /// <summary>The if / except / case line: the condition's anchor (0 for unknown).</summary>
    IfLine: Integer;
    /// <summary>First line of the branch holding the Exit (0 for unknown).</summary>
    BlockStart: Integer;
    /// <summary>Last line of the branch holding the Exit (0 for unknown).</summary>
    BlockEnd: Integer;
    /// <summary>The raw text inside `Exit(...)` on the anchored line ('' when there is none).</summary>
    ExitArg: string;
    /// <summary>For unknown: the generated reason, naming the shape the shim does not read.</summary>
    Reason: string;
    /// <summary>Line where the statement that owns the branch starts (its if / try / case token); 0 for unknown.</summary>
    StmtLine: Integer;
    /// <summary>0-based column of that token.</summary>
    StmtCol: Integer;
    /// <summary>if-form only: line of the `if` token's end (the condition's start); 0 when there is no span.</summary>
    CondL1: Integer;
    /// <summary>0-based column where the condition text starts (just after `if`).</summary>
    CondC1: Integer;
    /// <summary>The `then` token's line (0 = no condition span, the result is not an if-form).</summary>
    CondL2: Integer;
    /// <summary>0-based column of the `then` token.</summary>
    CondC2: Integer;
  end;

  /// <summary>The failure branch of an if-form guard on its `then` line, as 0-based columns [FromCol, ToCol).</summary>
  TGuardSpan = record
    /// <summary>False when the guard has no such span on the line.</summary>
    Found: Boolean;
    /// <summary>The `then` line.</summary>
    Line: Integer;
    /// <summary>First column of the failure branch.</summary>
    FromCol: Integer;
    /// <summary>End column, exclusive.</summary>
    ToCol: Integer;
  end;

  /// <summary>A statement's extent in the stripped source; end exclusive, columns 0-based, lines 1-based.</summary>
  TStatementSpan = record
    /// <summary>Start line.</summary>
    L1: Integer;
    /// <summary>Start column.</summary>
    C1: Integer;
    /// <summary>End line.</summary>
    L2: Integer;
    /// <summary>End column (exclusive).</summary>
    C2: Integer;
    /// <summary>Line of the first depth-0 `:=` (0: none).</summary>
    AssignLine: Integer;
    /// <summary>Column of that `:=` (-1: none).</summary>
    AssignCol: Integer;
  end;

/// <summary>The keyword tokens of lines pFrom..pTo of the stripped source, once per routine.</summary>
/// <param name="pStripped">The comment/string-stripped lines; line N is element N-1.</param>
/// <param name="pFrom">First line (clamped to 1).</param>
/// <param name="pTo">Last line (clamped to the line count).</param>
/// <returns>The tokens in source order (line, column); empty when the range is empty.</returns>
/// <remarks>Port of Get-ShimTokens. Pure. Every step line of a routine asks for its enclosing chain; passing these tokens down avoids re-tokenizing per ask.</remarks>
function ShimTokens(const pStripped: TArray<string>; pFrom, pTo: Integer): TArray<TShimToken>;

/// <summary>The guard condition around the Exit on one line (the branch holding it, read from the source).</summary>
/// <param name="pRaw">The raw lines.</param>
/// <param name="pStripped">The stripped lines (same count and columns).</param>
/// <param name="pExitLine">1-based line of the Exit the index anchored.</param>
/// <param name="pRoutineStart">1-based first line of the routine (tokens are read from there).</param>
/// <returns>The result; Form 'unknown' with a Reason for anything the shim cannot read. Never raises.</returns>
/// <remarks>Port of Get-GuardConditionFromLines. Pure; the caller checks freshness (AC-14). Innermost guard only (T4-R4).</remarks>
function GuardConditionFromLines(const pRaw, pStripped: TArray<string>; pExitLine, pRoutineStart: Integer): TShimResult;

/// <summary>The ENCLOSING condition of the statement that starts at (pLine, pCol) -- ruling T5-R1.</summary>
/// <param name="pRaw">The raw lines.</param>
/// <param name="pStripped">The stripped lines.</param>
/// <param name="pLine">1-based line of the statement.</param>
/// <param name="pCol">0-based column of its first token (clamped to the line).</param>
/// <param name="pRoutineStart">1-based first line of the routine.</param>
/// <param name="pAllTok">The routine's tokens (ShimTokens); nil or empty: read here.</param>
/// <returns>The nearest if whose branch holds the statement; Keyword says when the STATEMENT runs: WHEN C in the then branch, UNLESS C in the else branch (the reverse of a guard's). Form 'unknown' when it sits in no branch, a loop, a case arm or under a directive.</returns>
/// <remarks>Port of Get-EnclosingConditionFromLines. Innermost if only (T4-R4). Pure.</remarks>
function EnclosingConditionFromLines(const pRaw, pStripped: TArray<string>; pLine, pCol, pRoutineStart: Integer;
  const pAllTok: TArray<TShimToken> = nil): TShimResult;

/// <summary>The CHAIN of enclosing conditions of the statement at (pLine, pCol), innermost first.</summary>
/// <param name="pRaw">The raw lines.</param>
/// <param name="pStripped">The stripped lines.</param>
/// <param name="pLine">1-based line.</param>
/// <param name="pCol">0-based column.</param>
/// <param name="pRoutineStart">1-based first line of the routine.</param>
/// <param name="pAllTok">The routine's tokens; nil or empty: read here.</param>
/// <returns>At most 12 results: each branch's owning statement (its if / try / case token) is asked in turn until one sits in no branch.</returns>
/// <remarks>Port of Get-EnclosingChainFromLines. Pure.</remarks>
function EnclosingChainFromLines(const pRaw, pStripped: TArray<string>; pLine, pCol, pRoutineStart: Integer;
  const pAllTok: TArray<TShimToken> = nil): TArray<TShimResult>;

/// <summary>The FAILURE branch of an if-form Exit guard on its `then` line.</summary>
/// <param name="pG">A result of GuardConditionFromLines.</param>
/// <param name="pStripped">The stripped `then` line (line pG.CondL2).</param>
/// <returns>Found False for a result with no condition span, or when UNLESS/WHEN has no such span on the line (a WHEN whose else is not on the line: its lines are the guard's block). UNLESS: from the `then` to the if's own `else` or `;` on the line, else to the line end; WHEN: from that `else` to the `;` that ends it, else to the line end.</returns>
/// <remarks>Port of Get-GuardFailSpan (final-review I1). Tokens are read from the stripped line: begin / try / case .. end nests, and an `if` nested in the branch takes the next `else` for itself. Pure.</remarks>
function GuardFailSpan(const pG: TShimResult; const pStripped: string): TGuardSpan;

/// <summary>Is the ref at (pLine, 1-based pCol) inside the CONDITION of pG (between its `if` and `then`)?</summary>
/// <param name="pG">A result of GuardConditionFromLines or EnclosingConditionFromLines.</param>
/// <param name="pLine">1-based line.</param>
/// <param name="pCol">1-based column (a refs.start_col).</param>
/// <returns>True inside the condition; False for any other form (no span) and outside.</returns>
/// <remarks>Port of Test-InShimCondition. Pure.</remarks>
function InShimCondition(const pG: TShimResult; pLine, pCol: Integer): Boolean;

/// <summary>The extent of the statement that starts at (pLine, pCol).</summary>
/// <param name="pStripped">The stripped lines.</param>
/// <param name="pLine">1-based start line.</param>
/// <param name="pCol">0-based start column.</param>
/// <param name="pLastLine">The routine's last line (clamped to the line count).</param>
/// <returns>The span, ending at the first depth-0 `;`, or `end` / `until` / `else` / `except` / `finally` (a statement that is a branch, or the last of a block, has no `;` of its own), else at the end of the last line. Depth counts ( ) [ ] and begin/try/case/record/repeat .. end/until; an `if` after the `:=` is a Delphi 13 conditional expression, whose `else` stays inside.</returns>
/// <remarks>Port of Get-StatementSpan. Pure.</remarks>
function StatementSpan(const pStripped: TArray<string>; pLine, pCol, pLastLine: Integer): TStatementSpan;

/// <summary>Is (pLine, 0-based pCol0) on the right-hand side of pSp -- after its `:=`, before its end?</summary>
/// <param name="pSp">A StatementSpan.</param>
/// <param name="pLine">1-based line.</param>
/// <param name="pCol0">0-based column.</param>
/// <returns>True on the right-hand side; False when the span has no `:=`.</returns>
/// <remarks>Port of Test-InStatementRhs. Pure.</remarks>
function InStatementRhs(const pSp: TStatementSpan; pLine, pCol0: Integer): Boolean;

/// <summary>The 0-based column where the receiver of the member at 0-based pMemberCol starts.</summary>
/// <param name="pS">The stripped line.</param>
/// <param name="pMemberCol">0-based column of the member name.</param>
/// <returns>Back over blanks, the dot, blanks, then the (possibly dotted) identifier; -1 when the member has no dotted receiver.</returns>
/// <remarks>Port of Get-ReceiverStart. Pure.</remarks>
function ReceiverStart(const pS: string; pMemberCol: Integer): Integer;

/// <summary>The right-hand side of the assignment whose target starts at the 1-based column pCol, as the source writes it.</summary>
/// <param name="pRaw">The line as written.</param>
/// <param name="pStripped">The same line, literals and comments blanked column for column.</param>
/// <param name="pCol">1-based column of the assignment target.</param>
/// <returns>The text up to the `;` that ends it on this line, trimmed; '' when the line holds no `:=` there or the statement runs on.</returns>
/// <remarks>Port of Get-AssignExprAt. Pure.</remarks>
function AssignExprAt(const pRaw, pStripped: string; pCol: Integer): string;

/// <summary>The right-hand side of a ONE-line assignment `X:= expr;` whose expression concatenates, as written.</summary>
/// <param name="pRaw">The line as written.</param>
/// <param name="pStripped">The same line with literals and comments blanked.</param>
/// <returns>The expression (a `+` outside any literal or comment); '' for any other line.</returns>
/// <remarks>Port of Get-ConcatAssignExpr. Pure.</remarks>
function ConcatAssignExpr(const pRaw, pStripped: string): string;

/// <summary>A string literal exactly as the source writes it, quotes and doubled '' included (ruling T5-R3).</summary>
/// <param name="pText">The index's literal value (UNESCAPED and TRIMMED).</param>
/// <param name="pCol">1-based start column (literals.col).</param>
/// <param name="pEcol">1-based end column, exclusive.</param>
/// <param name="pRawLine">The raw source line of the literal.</param>
/// <param name="pHasRaw">False when the line is not available (no fresh source).</param>
/// <returns>The token read from the line when that span is one quoted token, else pText re-escaped and quoted.</returns>
/// <remarks>Port of Get-LiteralSourceText. Pure.</remarks>
function LiteralSourceText(const pText: string; pCol, pEcol: Integer; const pRawLine: string; pHasRaw: Boolean): string;

/// <summary>A branch for ANOTHER table (T5-R1): the statement runs WHEN pCondition and pCondition compares a value with `=` to a string literal that is a known table other than the anchor's.</summary>
/// <param name="pKeyword">The guard keyword; only 'WHEN' (case-sensitive) can qualify.</param>
/// <param name="pCondition">The verbatim condition.</param>
/// <param name="pAnchorTable">The anchor's table.</param>
/// <param name="pTables">The known tables.</param>
/// <returns>True when the branch cannot let the anchor's table through: no `or` / `xor` / `not` / `&lt;&gt;`, no literal naming the anchor table; anything else keeps the step.</returns>
/// <remarks>Port of Test-OtherTableBranch. Pure.</remarks>
function OtherTableBranch(const pKeyword, pCondition, pAnchorTable: string; const pTables: TArray<string>): Boolean;

/// <summary>'&lt;file leaf&gt;:&lt;line&gt;' of a path.</summary>
/// <param name="pPath">A path (either separator).</param>
/// <param name="pLine">The line.</param>
/// <returns>The anchor text.</returns>
/// <remarks>Port of Get-TraceAnchorText.</remarks>
function TraceAnchorText(const pPath: string; pLine: Integer): string;

/// <summary>The locator a generated NOTE writes for a line of pRefFile (FW-R2).</summary>
/// <param name="pAnchorFile">The step's own anchor file.</param>
/// <param name="pRefFile">The file the referenced line lives in.</param>
/// <param name="pRefLine">The line.</param>
/// <returns>':N' when both leaf names are equal (case-insensitive), else 'File.pas:N', so the locator is never ambiguous.</returns>
/// <remarks>Port of Get-TraceNoteLocator.</remarks>
function TraceNoteLocator(const pAnchorFile, pRefFile: string; pRefLine: Integer): string;

/// <summary>Literal-derived text made safe for a step line or a note.</summary>
/// <param name="pS">The text.</param>
/// <param name="pMax">The length cap (72 by default).</param>
/// <returns>Whitespace runs collapsed and trimmed, then ' -- ' to ' - ', ' @' to ' at ', ' [' to ' (', '"' to a single quote, '; ' to ', '; longer than pMax: cut to pMax-3 plus '...'. SPACE-ANCHORED on purpose: an indexer `Fields[0]` is quoted as written (ruling T3-M1).</returns>
/// <remarks>Port of ConvertTo-TraceWord.</remarks>
function TraceWord(const pS: string; pMax: Integer = TRACE_WORD_MAX): string;

/// <summary>A hop's reason as a step note: the note separator '; ' cannot appear inside one.</summary>
/// <param name="pS">The reason.</param>
/// <returns>pS with '; ' replaced by ', '.</returns>
/// <remarks>Port of ConvertTo-TraceNoteText.</remarks>
function TraceNoteText(const pS: string): string;

/// <summary>A GENERATED stop reason made safe for a STOPS step (ruling T3-M2).</summary>
/// <param name="pS">The reason.</param>
/// <returns>Whitespace collapsed and trimmed, a bracket PAIR read as parentheses, ' -- ' to ' - ', ' @' to ' at ', ' [' to ' (', '; ' to ', '. Nothing is truncated: a stop that names every candidate keeps them all. Never applied to source-derived text.</returns>
/// <remarks>Port of ConvertTo-TraceStopText.</remarks>
function TraceStopText(const pS: string): string;

implementation

uses
  System.SysUtils
  , System.Math
  , System.Character
  , System.Generics.Collections
  , System.RegularExpressions
  , DRagLint.Charts.Source
  , DRagLint.Charts.Trace.FormA
  ;

const
  RE_TOKEN = '(?i)\b(begin|end|try|case|record|except|finally|if|then|else|do|on|with|while|for|of|repeat|until|procedure|function)\b|;|:(?!=)';
  RE_STMT = '(?i)\b(begin|end|try|case|record|repeat|until|else|except|finally|if)\b|:=|[()\[\];]';
  RE_EXIT = '(?i)\bExit\b';
  RE_DIRECTIVE = '(?i)(\{|\(\*)\$(IF|ELSE|ENDIF)';
  RE_QUOTED = '^''(?:[^'']|'''')*''$';
  RE_ASSIGN_AT = '^[A-Za-z_][\w.]*\s*:=';
  RE_ASSIGN_LINE = '^\s*[A-Za-z_][\w.]*\s*:=';
  RE_OP_WORDS = '(?i)\b(or|xor|not)\b|<>';
  RE_LITERAL = '''((?:[^'']|'''')*)''';
  RE_EQ_LITERAL = '(?<![<>:])=\s*''((?:[^'']|'''')*)''|''((?:[^'']|'''')*)''\s*=';
  { shim result forms and keywords }
  FORM_UNKNOWN = 'unknown';
  KW_UNLESS = 'UNLESS';
  KW_WHEN = 'WHEN';
  { Get-EnclosingChainFromLines' cap }
  MAX_CHAIN = 12;
  { a statement of more than this many code lines is a compound block, not a quotable statement (Task 5 fix round 1) }
  MAX_QUOTED_LINES = 3;
  THEN_LEN = 4;
  ELLIPSIS = '...';
  OPENERS: array[0..4] of string = ('begin', 'try', 'case', 'record', 'repeat');
  CLOSERS: array[0..1] of string = ('end', 'until');
  { the tokens that bound a statement when looking for the if of a then }
  IF_STOPS: array[0..14] of string = (';', 'begin', 'end', 'then', 'else', 'do', 'try', 'except', 'finally', 'of', 'repeat', 'until', 'case', 'procedure', 'function');
  DO_STOPS: array[0..12] of string = (';', 'begin', 'end', 'then', 'else', 'do', 'try', 'except', 'finally', 'of', 'repeat', 'until', 'case');
  BRANCH_OPENERS: array[0..3] of string = ('then', 'else', 'do', ':');

type
  { the reader's working state: the lines, the Exit (or statement) position and the tokens before it }
  TShimContext = record
    Raw     : TArray<string>;
    Stripped: TArray<string>;
    ExitLine: Integer;
    ExitCol : Integer;
    ExitArg : string;
    What    : string;
    Tok     : TArray<TShimToken>;
    TokCount: Integer;
  end;

  TElseOwnerKind = (eoNone, eoIf, eoCase);

  TElseOwner = record
    Kind   : TElseOwnerKind;
    Idx    : Integer;
    ThenIdx: Integer;
  end;

var
  GTokenRx: TRegEx;
  GStmtRx : TRegEx;

function IsIn(const pS: string; const pSet: array of string): Boolean;
begin
  Result:= False;
  for var I:= 0 to High(pSet) do
    if SameStr(pS, pSet[I]) then
      Exit(True);
end;

{ a group value; PCRE reports fewer groups when the trailing optional ones did not take part }
function Grp(const pMatch: TMatch; pIndex: Integer): string;
begin
  if pIndex < pMatch.Groups.Count then
    Result:= pMatch.Groups[pIndex].Value
  else
    Result:= '';
end;

{ String.IndexOf(pSub, pStart0): 0-based, -1 when absent }
function IndexOfFrom(const pS, pSub: string; pStart0: Integer): Integer;
begin
  Result:= Pos(pSub, pS, pStart0 + 1) - 1;
end;

{ [IO.Path]::GetFileName for the separators the index stores }
function LeafOf(const pPath: string): string;
begin
  var P:= Length(pPath);
  while (P > 0) and (pPath[P] <> '\') and (pPath[P] <> '/') do
    Dec(P);
  Result:= Copy(pPath, P + 1, MaxInt);
end;

function JoinStrings(const pList: TList<string>; const pSep: string): string;
begin
  Result:= string.Join(pSep, pList.ToArray);
end;

procedure AddTokens(const pList: TList<TShimToken>; const pText: string; pLine: Integer);
begin
  for var M in GTokenRx.Matches(pText) do
  begin
    var Tk: TShimToken;
    Tk.L:= pLine;
    Tk.C:= M.Index - 1;
    Tk.E:= Tk.C + M.Length;
    Tk.T:= M.Value.ToLowerInvariant;
    pList.Add(Tk);
  end;
end;

function ShimTokens(const pStripped: TArray<string>; pFrom, pTo: Integer): TArray<TShimToken>;
begin
  var List:= TList<TShimToken>.Create;
  try
    for var L:= Max(pFrom, 1) to Min(pTo, Length(pStripped)) do
      AddTokens(List, pStripped[L - 1], L);
    Result:= List.ToArray;
  finally
    List.Free;
  end;
end;

{ the line on which the block opened by the begin/try/case at (pOpenerLine, pOpenerCol) is closed by its end }
function FindBlockEnd(const pStripped: TArray<string>; pOpenerLine, pOpenerCol: Integer): Integer;
begin
  var Depth:= 0;
  for var I:= pOpenerLine - 1 to High(pStripped) do
  begin
    var T:= pStripped[I];
    if I = pOpenerLine - 1 then
      T:= Copy(T, Min(pOpenerCol, Length(T)) + 1, MaxInt);
    for var M in GTokenRx.Matches(T) do
    begin
      var K:= M.Value.ToLowerInvariant;
      if IsIn(K, OPENERS) then
        Inc(Depth)
      else if IsIn(K, CLOSERS) then
      begin
        Dec(Depth);
        if Depth <= 0 then
          Exit(I + 1);
      end;
    end;
  end;
  Result:= Length(pStripped);
end;

{ One line's piece of a quoted span: the raw text from the first to the last code or string character in
  columns pA..pB-1 of pR (pS is the stripped copy). pHas False: the line holds no code there. The result False is
  the PS $null: a comment that does not close on its own line, or a raw character the stripped copy blanked that
  opens neither a string nor a comment (fix round 1). Columns 0-based. }
function ShimLinePiece(const pR, pS: string; pA, pB: Integer; out pPiece: string; out pHas: Boolean): Boolean;
begin
  pPiece:= '';
  pHas:= False;
  var First:= -1;
  var Last:= -1;
  var I:= pA;
  while I < pB do
  begin
    var Ch:= pR[I + 1];
    if (I < Length(pS)) and not pS[I + 1].IsWhiteSpace then
    begin
      if First < 0 then
        First:= I;
      Last:= I;
      Inc(I);
    end
    else if Ch.IsWhiteSpace then
      Inc(I)
    else if Ch = '''' then
    begin
      { a string the stripped copy blanked: it runs to its closing quote }
      var J:= IndexOfFrom(pR, '''', I + 1);
      if (J < 0) or (J >= pB) then
        J:= pB - 1;
      if First < 0 then
        First:= I;
      Last:= J;
      I:= J + 1;
    end
    else if (Ch = '/') and (I + 1 < pB) and (pR[I + 2] = '/') then
      Break
    else if (Ch = '{') or ((Ch = '(') and (I + 1 < pB) and (pR[I + 2] = '*')) then
    begin
      var Close:= if Ch = '{' then '}' else '*)';
      var J:= IndexOfFrom(pR, Close, I + Length(Close));
      if J < 0 then
        Exit(False);
      I:= J + Length(Close);
    end
    else
      Exit(False);
  end;
  pHas:= First >= 0;
  if pHas then
    pPiece:= Copy(pR, First + 1, Last - First + 1);
  Result:= True;
end;

{ The raw text from (pL1, pC1) to (pL2, pC2), one piece per line, joined with one space; False is the PS $null
  (see ShimLinePiece). Lines 1-based, columns 0-based, end exclusive. }
function ShimSpanText(const pRaw, pStripped: TArray<string>; pL1, pC1, pL2, pC2: Integer; out pText: string): Boolean;
begin
  pText:= '';
  Result:= False;
  var Pieces:= TList<string>.Create;
  try
    for var L:= pL1 to pL2 do
    begin
      var R:= pRaw[L - 1];
      var A:= if L = pL1 then pC1 else 0;
      var B:= if L = pL2 then Min(pC2, Length(R)) else Length(R);
      var Piece: string;
      var Has: Boolean;
      if not ShimLinePiece(R, pStripped[L - 1], A, B, Piece, Has) then
        Exit;
      if Has then
        Pieces.Add(Piece);
    end;
    pText:= JoinStrings(Pieces, ' ');
    Result:= True;
  finally
    Pieces.Free;
  end;
end;

{ how many lines of the span carry code (the stripped copy is non-blank there) }
function ShimCodeLineCount(const pStripped: TArray<string>; pL1, pC1, pL2, pC2: Integer): Integer;
begin
  Result:= 0;
  for var L:= pL1 to pL2 do
  begin
    var S:= pStripped[L - 1];
    var A:= if L = pL1 then Min(pC1, Length(S)) else 0;
    var B:= if L = pL2 then Min(pC2, Length(S)) else Length(S);
    if (B > A) and (PsTrim(Copy(S, A + 1, B - A)) <> '') then
      Inc(Result);
  end;
end;

function NewShimResult(const pX: TShimContext; const pForm, pKeyword, pCondition: string;  // dl:ok too-many-parameters@182e -- REVIEWED 2026-10-17: mirrors New-ShimResult's ten values; every caller names each position, and a grouping record would only rename the same values at ten call sites
  pIfLine, pBlockStart, pBlockEnd: Integer; const pReason: string; pStmtLine, pStmtCol: Integer): TShimResult;
begin
  if pForm <> FORM_UNKNOWN then
  begin
    var Why:= TraceCondProblem(pCondition);
    if Why <> '' then
      Exit(NewShimResult(pX, FORM_UNKNOWN, '', '', 0, 0, 0,
        'the condition over the ' + pX.What + ' at :' + IntToStr(pX.ExitLine) + ' ' + Why
          + ' -- a Form A condition cannot carry it verbatim', 0, 0));
  end;
  Result:= Default(TShimResult);
  Result.Form:= pForm;
  Result.Keyword:= pKeyword;
  Result.Condition:= pCondition;
  Result.IfLine:= pIfLine;
  Result.BlockStart:= pBlockStart;
  Result.BlockEnd:= pBlockEnd;
  Result.ExitArg:= pX.ExitArg;
  Result.Reason:= pReason;
  Result.StmtLine:= pStmtLine;
  Result.StmtCol:= pStmtCol;
end;

function NewShimUnknown(const pX: TShimContext; const pWhy: string): TShimResult;
begin
  Result:= NewShimResult(pX, FORM_UNKNOWN, '', '', 0, 0, 0,
    'the ' + pX.What + ' at :' + IntToStr(pX.ExitLine) + ' ' + pWhy + ', a shape the source shim does not read', 0, 0);
end;

{ the `if` token owning the `then` at token pThenIdx (-1: none before a statement boundary) }
function FindShimIf(const pX: TShimContext; pThenIdx: Integer): Integer;
begin
  for var Q:= pThenIdx - 1 downto 0 do
  begin
    var K:= pX.Tok[Q].T;
    if K = 'if' then
      Exit(Q);
    if IsIn(K, IF_STOPS) then
      Exit(-1);
  end;
  Result:= -1;
end;

{ What the `else` at token pElseIdx pairs with: back over balanced blocks, an inner if's own `else` absorbs the
  next `then`; the first free `then` before any `;` is the if's; a `case` opener is the case's. eoNone: neither. }
function FindShimElseOwner(const pX: TShimContext; pElseIdx: Integer): TElseOwner;
begin
  Result:= Default(TElseOwner);
  var Depth:= 0;
  var Semi:= False;
  var Pend:= 0;
  for var Q:= pElseIdx - 1 downto 0 do
  begin
    var K:= pX.Tok[Q].T;
    if IsIn(K, CLOSERS) then
    begin
      Inc(Depth);
      Continue;
    end;
    if IsIn(K, OPENERS) then
    begin
      if Depth > 0 then
      begin
        Dec(Depth);
        Continue;
      end;
      if K = 'case' then
      begin
        Result.Kind:= eoCase;
        Result.Idx:= Q;
      end;
      Exit;
    end;
    if Depth > 0 then
      Continue;
    if K = ';' then
      Semi:= True
    else if K = 'else' then
      Inc(Pend)
    else if (K = 'then') and not Semi then
    begin
      if Pend > 0 then
      begin
        Dec(Pend);
        Continue;
      end;
      var I:= FindShimIf(pX, Q);
      if I >= 0 then
      begin
        Result.Kind:= eoIf;
        Result.Idx:= I;
        Result.ThenIdx:= Q;
      end;
      Exit;
    end
    else if (K = 'procedure') or (K = 'function') then
      Exit;
  end;
end;

{ the depth-0 tokens in pWant strictly between token indexes pFrom and pTo }
function ShimLevelTokens(const pX: TShimContext; pFrom, pTo: Integer; const pWant: array of string): TArray<Integer>;
begin
  var Hits:= TList<Integer>.Create;
  try
    var Depth:= 0;
    for var Q:= pFrom + 1 to pTo - 1 do
    begin
      var K:= pX.Tok[Q].T;
      if IsIn(K, OPENERS) then
        Inc(Depth)
      else if IsIn(K, CLOSERS) then
        Dec(Depth)
      else if (Depth = 0) and IsIn(K, pWant) then
        Hits.Add(Q);
    end;
    Result:= Hits.ToArray;
  finally
    Hits.Free;
  end;
end;

{ Ruling T4-R1: a conditional-compilation directive between the guard's token and the Exit means the stripped copy
  shows ONE branch of a choice the compiler makes -- True, and the caller returns a named unknown. }
function ShimDirectiveBetween(const pX: TShimContext; const pTok: TShimToken): Boolean;
begin
  var Sb:= TStringBuilder.Create;
  try
    for var L:= pTok.L to pX.ExitLine do
    begin
      var R:= pX.Raw[L - 1];
      var A:= if L = pTok.L then pTok.C else 0;
      var B:= if L = pX.ExitLine then Min(pX.ExitCol, Length(R)) else Length(R);
      if B > A then
        Sb.Append(Copy(R, A + 1, B - A)).Append(#10);
    end;
    Result:= TRegEx.IsMatch(Sb.ToString, RE_DIRECTIVE);
  finally
    Sb.Free;
  end;
end;

function ResolveShimStatement(const pX: TShimContext; pP, pBlkStart, pBlkEnd: Integer): TShimResult; forward;

function NewShimIfResult(const pX: TShimContext; pThenIdx: Integer; const pKeyword: string; pBlkStart, pBlkEnd: Integer): TShimResult;
begin
  var I:= FindShimIf(pX, pThenIdx);
  if I < 0 then
    Exit(NewShimUnknown(pX, 'follows a then with no if before it'));
  var It:= pX.Tok[I];
  var Th:= pX.Tok[pThenIdx];
  if ShimDirectiveBetween(pX, It) then
    Exit(NewShimUnknown(pX, 'sits under a conditional-compilation directive'));
  var Cond: string;
  if not ShimSpanText(pX.Raw, pX.Stripped, It.L, It.E, Th.L, Th.C, Cond) then
    Exit(NewShimUnknown(pX, 'has a condition that wraps a comment across lines'));
  var Form:= if It.L = pX.ExitLine then 'inline' else 'block';
  Result:= NewShimResult(pX, Form, pKeyword, Cond, It.L, pBlkStart, pBlkEnd, '', It.L, It.C);
  { Task 6 fix round 1: where the condition's text lies -- after the `if` token, before the `then` (0-based columns,
    the tokens' own), so a caller can tell a ref IN the condition from one in the branch }
  if Result.Form <> FORM_UNKNOWN then
  begin
    Result.CondL1:= It.L;
    Result.CondC1:= It.E;
    Result.CondL2:= Th.L;
    Result.CondC2:= Th.C;
  end;
end;

function InShimCondition(const pG: TShimResult; pLine, pCol: Integer): Boolean;
begin
  if pG.CondL2 = 0 then
    Exit(False);
  var C:= pCol - 1;
  var After:= (pLine > pG.CondL1) or ((pLine = pG.CondL1) and (C >= pG.CondC1));
  var Before:= (pLine < pG.CondL2) or ((pLine = pG.CondL2) and (C < pG.CondC2));
  Result:= After and Before;
end;

function GuardFailSpan(const pG: TShimResult; const pStripped: string): TGuardSpan;
begin
  Result:= Default(TGuardSpan);
  if pG.CondL2 = 0 then
    Exit;
  var C0:= pG.CondC2;
  if C0 >= Length(pStripped) then
    Exit;
  var Depth:= 0;
  var Pend:= 0;
  var Els:= -1;
  var EndAt:= Length(pStripped);
  for var M in GTokenRx.Matches(Copy(pStripped, Min(C0 + THEN_LEN, Length(pStripped)) + 1, MaxInt)) do
  begin
    var K:= M.Value.ToLowerInvariant;
    var ColAt:= C0 + THEN_LEN + M.Index - 1;
    if IsIn(K, OPENERS) then
    begin
      Inc(Depth);
      Continue;
    end;
    if IsIn(K, CLOSERS) then
    begin
      Dec(Depth);
      Continue;
    end;
    if Depth <> 0 then
      Continue;
    if K = 'if' then
    begin
      Inc(Pend);
      Continue;
    end;
    if K = 'else' then
    begin
      if Pend > 0 then
      begin
        Dec(Pend);
        Continue;
      end;
      if Els < 0 then
      begin
        Els:= ColAt;
        Continue;
      end;
    end;
    if K = ';' then
    begin
      EndAt:= ColAt + 1;
      Break;
    end;
  end;
  Result.Line:= pG.CondL2;
  if SameStr(pG.Keyword, KW_UNLESS) then
  begin
    Result.Found:= True;
    Result.FromCol:= C0;
    Result.ToCol:= if Els >= 0 then Els else EndAt;
    Exit;
  end;
  if Els < 0 then
    Exit;
  Result.Found:= True;
  Result.FromCol:= Els;
  Result.ToCol:= EndAt;
end;

function NewShimCaseResult(const pX: TShimContext; pCaseIdx, pElseIdx: Integer): TShimResult;
begin
  var Ca:= pX.Tok[pCaseIdx];
  var OfIdx:= -1;
  for var Q:= pCaseIdx + 1 to pX.TokCount - 1 do
    if pX.Tok[Q].T = 'of' then
    begin
      OfIdx:= Q;
      Break;
    end;
  if OfIdx < 0 then
    Exit(NewShimUnknown(pX, 'sits in a case with no of'));
  if ShimDirectiveBetween(pX, Ca) then
    Exit(NewShimUnknown(pX, 'sits under a conditional-compilation directive'));
  var Sel: string;
  if not ShimSpanText(pX.Raw, pX.Stripped, Ca.L, Ca.C, pX.Tok[OfIdx].L, pX.Tok[OfIdx].E, Sel) then
    Exit(NewShimUnknown(pX, 'has a condition that wraps a comment across lines'));
  { T4-C3: VERBATIM through `of`; that the Exit is in the else arm is the condition's generated note }
  Result:= NewShimResult(pX, 'case', KW_UNLESS, Sel, Ca.L, pX.Tok[pElseIdx].L, FindBlockEnd(pX.Stripped, Ca.L, Ca.C), '', Ca.L, Ca.C);
end;

{ The Exit sits in the handler of the try at token pTryIdx (its `except` at pExIdx): the protected statements are
  the depth-0 `;`-separated spans of the try body. }
function NewShimExceptResult(const pX: TShimContext; pTryIdx, pExIdx: Integer): TShimResult;
begin
  var Tr:= pX.Tok[pTryIdx];
  var Ex:= pX.Tok[pExIdx];
  if ShimDirectiveBetween(pX, Tr) then
    Exit(NewShimUnknown(pX, 'sits under a conditional-compilation directive'));
  var Stm:= TList<string>.Create;
  var Lines:= TList<Integer>.Create;
  try
    var Sl:= Tr.L;
    var Sc:= Tr.E;
    var Stops:= TList<Integer>.Create;
    try
      Stops.AddRange(ShimLevelTokens(pX, pTryIdx, pExIdx, [';']));
      Stops.Add(pExIdx);
      for var Q in Stops do
      begin
        var E:= pX.Tok[Q];
        var Txt: string;
        if not ShimSpanText(pX.Raw, pX.Stripped, Sl, Sc, E.L, E.C, Txt) then
          Exit(NewShimUnknown(pX, 'has a try body that wraps a comment across lines'));
        if Txt <> '' then
        begin
          Stm.Add(Txt);
          Lines.Add(ShimCodeLineCount(pX.Stripped, Sl, Sc, E.L, E.C));
        end;
        Sl:= E.L;
        Sc:= E.E;
      end;
    finally
      Stops.Free;
    end;
    if Stm.Count = 0 then
      Exit(NewShimUnknown(pX, 'sits in the handler of an empty try'));
    { ruling T4-R3: ' ... ', not ' .. ' (Pascal's range operator). Fix round 1 (Task 5): a statement of more than
      three code lines is a compound block, not a quotable statement: a LAST one is left out, and a FIRST (or only)
      one makes the form a named unknown }
    if Lines[0] > MAX_QUOTED_LINES then
      Exit(NewShimUnknown(pX, 'sits in the handler of a try whose body opens with a compound statement'));
    var S: string;
    if Stm.Count = 1 then
      S:= Stm[0]
    else if Lines[Lines.Count - 1] > MAX_QUOTED_LINES then
      S:= Stm[0] + ' ...'
    else
      S:= Stm[0] + ' ... ' + Stm[Stm.Count - 1];
    Result:= NewShimResult(pX, 'except', KW_UNLESS, S + ' raises', Ex.L, Ex.L, FindBlockEnd(pX.Stripped, Tr.L, Tr.C), '', Tr.L, Tr.C);
  finally
    Lines.Free;
    Stm.Free;
  end;
end;

function ResolveShimEnclosing(const pX: TShimContext; pP: Integer): TShimResult; forward;

{ The statement holding the Exit starts at token pP (TokCount: the Exit itself); pBlkStart..pBlkEnd is that
  statement's first and last line. }
function ResolveShimStatement(const pX: TShimContext; pP, pBlkStart, pBlkEnd: Integer): TShimResult;  // dl:ok too-many-exit-points@2cfd -- REVIEWED 2026-10-17: one Exit per source shape (then, else, do, case arm), each returning its own named result as the PS returns do; a single exit would only add a Result variable and else-chains
begin
  if pP <= 0 then
    Exit(NewShimUnknown(pX, 'is not inside a branch'));
  var K:= pX.Tok[pP - 1].T;
  if K = 'then' then
    Exit(NewShimIfResult(pX, pP - 1, KW_UNLESS, pBlkStart, pBlkEnd));
  if K = 'else' then
  begin
    var Ow:= FindShimElseOwner(pX, pP - 1);
    if Ow.Kind = eoNone then
      Exit(NewShimUnknown(pX, 'follows an else the shim cannot pair'));
    if Ow.Kind = eoCase then
      Exit(NewShimCaseResult(pX, Ow.Idx, pP - 1));
    Exit(NewShimIfResult(pX, Ow.ThenIdx, KW_WHEN, pBlkStart, pBlkEnd));
  end;
  if K = 'do' then
  begin
    { the statement head: an `on` right after `except` or `;` is a handler; else with / while / for }
    for var Q:= pP - 2 downto 0 do
    begin
      var H:= pX.Tok[Q].T;
      if (H = 'on') and (Q > 0) and ((pX.Tok[Q - 1].T = 'except') or (pX.Tok[Q - 1].T = ';')) then
        Exit(ResolveShimEnclosing(pX, Q));
      if (H = 'with') or (H = 'while') or (H = 'for') then
        Exit(NewShimUnknown(pX, 'sits under a ' + H + ' statement'));
      if IsIn(H, DO_STOPS) then
        Break;
    end;
    Exit(NewShimUnknown(pX, 'sits under a do the shim cannot place'));
  end;
  if K = ':' then
    Exit(NewShimUnknown(pX, 'sits in a case arm'));
  Result:= ResolveShimEnclosing(pX, pP);
end;

{ The Exit (or the statement at token pP) is one statement of a block: find the block's opener and read IT as the
  statement that holds the Exit. }
function ResolveShimEnclosing(const pX: TShimContext; pP: Integer): TShimResult;  // dl:ok too-many-exit-points@6c4b -- REVIEWED 2026-10-17: one Exit per opener kind (begin, try, case, other) and per no-branch case, each a distinct named result as in the PS; collapsing them hides which shape was refused
begin
  var Depth:= 0;
  for var Q:= pP - 1 downto 0 do
  begin
    var K:= pX.Tok[Q].T;
    if IsIn(K, CLOSERS) then
    begin
      Inc(Depth);
      Continue;
    end;
    if IsIn(K, OPENERS) then
    begin
      if Depth > 0 then
      begin
        Dec(Depth);
        Continue;
      end;
      var O:= pX.Tok[Q];
      var BlkEnd:= FindBlockEnd(pX.Stripped, O.L, O.C);
      if K = 'begin' then
      begin
        { a begin after then / else / do / a case label is a branch; any other is the routine body (or a bare block) }
        if (Q > 0) and IsIn(pX.Tok[Q - 1].T, BRANCH_OPENERS) then
          Exit(ResolveShimStatement(pX, Q, O.L, BlkEnd));
        Exit(NewShimUnknown(pX, 'is not inside a branch'));
      end;
      if K = 'try' then
      begin
        var Mk:= ShimLevelTokens(pX, Q, pP, ['except', 'finally']);
        if (Length(Mk) > 0) and (pX.Tok[Mk[High(Mk)]].T = 'except') then
          Exit(NewShimExceptResult(pX, Q, Mk[High(Mk)]));
        { in the try body or the finally: the try is the statement }
        Exit(ResolveShimStatement(pX, Q, O.L, BlkEnd));
      end;
      if K = 'case' then
      begin
        for var E in ShimLevelTokens(pX, Q, pP, ['else']) do
        begin
          var Ow:= FindShimElseOwner(pX, E);
          if (Ow.Kind = eoCase) and (Ow.Idx = Q) then
            Exit(NewShimCaseResult(pX, Q, E));
        end;
        Exit(NewShimUnknown(pX, 'sits in a case arm'));
      end;
      Exit(NewShimUnknown(pX, 'sits inside a ' + K));
    end;
    if (Depth = 0) and ((K = 'procedure') or (K = 'function')) then
      Exit(NewShimUnknown(pX, 'is not inside a branch'));
  end;
  Result:= NewShimUnknown(pX, 'is not inside a branch');
end;

function GuardConditionFromLines(const pRaw, pStripped: TArray<string>; pExitLine, pRoutineStart: Integer): TShimResult;
begin
  var X:= Default(TShimContext);
  X.Raw:= pRaw;
  X.Stripped:= pStripped;
  X.ExitLine:= pExitLine;
  X.What:= 'Exit';
  if (pExitLine < 1) or (pExitLine > Length(pStripped)) then
    Exit(NewShimUnknown(X, 'is outside the file'));
  var S:= pStripped[pExitLine - 1];
  var Ems:= TRegEx.Matches(S, RE_EXIT);
  if Ems.Count = 0 then
    Exit(NewShimUnknown(X, 'is not an Exit in this copy of the file'));
  { fix round 1: the index anchors a LINE; with two Exits on it the shim cannot tell which one it was asked about --
    named, never the first one's branch by default }
  if Ems.Count > 1 then
    Exit(NewShimUnknown(X, 'shares its line with another Exit'));
  var Em:= Ems[0];
  var EmAt:= Em.Index - 1;
  X.ExitCol:= EmAt;
  { Exit(<arg>): the raw text inside the balanced parentheses }
  var P:= EmAt + Em.Length;
  while (P < Length(S)) and S[P + 1].IsWhiteSpace do
    Inc(P);
  if (P < Length(S)) and (S[P + 1] = '(') then
  begin
    var D:= 0;
    for var J:= P to Length(S) - 1 do
    begin
      if S[J + 1] = '(' then
        Inc(D)
      else if S[J + 1] = ')' then
      begin
        Dec(D);
        if D = 0 then
        begin
          X.ExitArg:= PsTrim(Copy(pRaw[pExitLine - 1], P + 2, J - P - 1));
          Break;
        end;
      end;
    end;
  end;
  var List:= TList<TShimToken>.Create;
  try
    for var L:= Max(pRoutineStart, 1) to pExitLine do
    begin
      var T:= if L = pExitLine then Copy(S, 1, EmAt) else pStripped[L - 1];
      AddTokens(List, T, L);
    end;
    X.Tok:= List.ToArray;
  finally
    List.Free;
  end;
  X.TokCount:= Length(X.Tok);
  Result:= ResolveShimStatement(X, X.TokCount, pExitLine, pExitLine);
end;

function EnclosingConditionFromLines(const pRaw, pStripped: TArray<string>; pLine, pCol, pRoutineStart: Integer;
  const pAllTok: TArray<TShimToken> = nil): TShimResult;
begin
  var X:= Default(TShimContext);
  X.Raw:= pRaw;
  X.Stripped:= pStripped;
  X.ExitLine:= pLine;
  X.What:= 'statement';
  if (pLine < 1) or (pLine > Length(pStripped)) then
    Exit(NewShimUnknown(X, 'is outside the file'));
  X.ExitCol:= Min(Max(pCol, 0), Length(pStripped[pLine - 1]));
  X.Tok:= pAllTok;
  if Length(X.Tok) = 0 then
    X.Tok:= ShimTokens(pStripped, pRoutineStart, pLine);
  { the tokens that END before (pLine, ExitCol): a binary search over the (line, end) order }
  var Lo:= 0;
  var Hi:= Length(X.Tok);
  while Lo < Hi do
  begin
    var Mid:= (Lo + Hi) div 2;
    var M:= X.Tok[Mid];
    if (M.L < pLine) or ((M.L = pLine) and (M.E <= X.ExitCol)) then
      Lo:= Mid + 1
    else
      Hi:= Mid;
  end;
  X.TokCount:= Lo;
  Result:= ResolveShimStatement(X, X.TokCount, pLine, pLine);
  if Result.Form <> FORM_UNKNOWN then
    Result.Keyword:= if SameStr(Result.Keyword, KW_UNLESS) then KW_WHEN else KW_UNLESS;
end;

function EnclosingChainFromLines(const pRaw, pStripped: TArray<string>; pLine, pCol, pRoutineStart: Integer;
  const pAllTok: TArray<TShimToken> = nil): TArray<TShimResult>;
begin
  var All:= pAllTok;
  if Length(All) = 0 then
    All:= ShimTokens(pStripped, pRoutineStart, pLine);
  var List:= TList<TShimResult>.Create;
  try
    var L:= pLine;
    var C:= pCol;
    for var I:= 0 to MAX_CHAIN - 1 do
    begin
      var E:= EnclosingConditionFromLines(pRaw, pStripped, L, C, pRoutineStart, All);
      if E.Form = FORM_UNKNOWN then
        Break;
      List.Add(E);
      if (E.StmtLine = 0) or ((E.StmtLine = L) and (E.StmtCol >= C)) then
        Break;
      L:= E.StmtLine;
      C:= E.StmtCol;
    end;
    Result:= List.ToArray;
  finally
    List.Free;
  end;
end;

function StatementSpan(const pStripped: TArray<string>; pLine, pCol, pLastLine: Integer): TStatementSpan;
begin
  var Pd:= 0;
  var Bd:= 0;
  var Ifs:= 0;
  Result:= Default(TStatementSpan);
  Result.L1:= pLine;
  Result.C1:= pCol;
  Result.AssignCol:= -1;
  var Last:= Min(pLastLine, Length(pStripped));
  for var L:= pLine to Last do
  begin
    var S:= pStripped[L - 1];
    var From:= if L = pLine then Min(pCol, Length(S)) else 0;
    for var M in GStmtRx.Matches(Copy(S, From + 1, MaxInt)) do
    begin
      var K:= M.Value.ToLowerInvariant;
      var ColAt:= From + M.Index - 1;
      if (K = '(') or (K = '[') then
      begin
        Inc(Pd);
        Continue;
      end;
      if (K = ')') or (K = ']') then
      begin
        Dec(Pd);
        Continue;
      end;
      if Pd > 0 then
        Continue;
      if K = ':=' then
      begin
        if (Result.AssignCol < 0) and (Bd = 0) then
        begin
          Result.AssignLine:= L;
          Result.AssignCol:= ColAt;
        end;
        Continue;
      end;
      if IsIn(K, OPENERS) then
      begin
        Inc(Bd);
        Continue;
      end;
      if IsIn(K, CLOSERS) then
      begin
        if Bd > 0 then
        begin
          Dec(Bd);
          Continue;
        end;
        Result.L2:= L;
        Result.C2:= ColAt;
        Exit;
      end;
      if Bd > 0 then
        Continue;
      if K = 'if' then
      begin
        if Result.AssignCol >= 0 then
          Inc(Ifs);
        Continue;
      end;
      if (K = 'else') and (Ifs > 0) then
      begin
        Dec(Ifs);
        Continue;
      end;
      if (K = ';') or (K = 'else') or (K = 'except') or (K = 'finally') then
      begin
        Result.L2:= L;
        Result.C2:= ColAt;
        Exit;
      end;
    end;
  end;
  Result.L2:= Last;
  Result.C2:= if Last >= 1 then Length(pStripped[Last - 1]) else 0;
end;

function InStatementRhs(const pSp: TStatementSpan; pLine, pCol0: Integer): Boolean;
begin
  if pSp.AssignCol < 0 then
    Exit(False);
  var After:= (pLine > pSp.AssignLine) or ((pLine = pSp.AssignLine) and (pCol0 > pSp.AssignCol));
  var Before:= (pLine < pSp.L2) or ((pLine = pSp.L2) and (pCol0 < pSp.C2));
  Result:= After and Before;
end;

function ReceiverStart(const pS: string; pMemberCol: Integer): Integer;
begin
  var P:= pMemberCol - 1;
  while (P >= 0) and pS[P + 1].IsWhiteSpace do
    Dec(P);
  if (P < 0) or (pS[P + 1] <> '.') then
    Exit(-1);
  Dec(P);
  while (P >= 0) and pS[P + 1].IsWhiteSpace do
    Dec(P);
  var E:= P;
  while (P >= 0) and CharInSet(pS[P + 1], ['A'..'Z', 'a'..'z', '0'..'9', '_', '.']) do
    Dec(P);
  Result:= if P < E then P + 1 else -1;
end;

function AssignExprAt(const pRaw, pStripped: string; pCol: Integer): string;
begin
  Result:= '';
  var C0:= pCol - 1;
  if (C0 < 0) or (C0 >= Length(pStripped)) then
    Exit;
  var M:= TRegEx.Match(Copy(pStripped, C0 + 1, MaxInt), RE_ASSIGN_AT);
  if not M.Success then
    Exit;
  var B:= C0 + M.Length;
  var E:= IndexOfFrom(pStripped, ';', B);
  if (E < 0) or (Length(pRaw) < E) then
    Exit;
  Result:= PsTrim(Copy(pRaw, B + 1, E - B));
end;

function ConcatAssignExpr(const pRaw, pStripped: string): string;
begin
  Result:= '';
  var M:= TRegEx.Match(pStripped, RE_ASSIGN_LINE);
  var E:= LastDelimiter(';', pStripped) - 1;
  if not M.Success or (E <= M.Length) or (PsTrim(Copy(pStripped, E + 2, MaxInt)) <> '') or (Length(pRaw) < E) then
    Exit;
  if not Copy(pStripped, M.Length + 1, E - M.Length).Contains('+') then
    Exit;
  Result:= PsTrim(Copy(pRaw, M.Length + 1, E - M.Length));
end;

function LiteralSourceText(const pText: string; pCol, pEcol: Integer; const pRawLine: string; pHasRaw: Boolean): string;
begin
  var C0:= pCol - 1;
  var C1:= pEcol - 1;
  if pHasRaw and (C0 >= 0) and (C1 > C0 + 1) and (C1 <= Length(pRawLine)) then
  begin
    var Tk:= Copy(pRawLine, C0 + 1, C1 - C0);
    if TRegEx.IsMatch(Tk, RE_QUOTED) then
      Exit(Tk);
  end;
  Result:= '''' + pText.Replace('''', '''''') + '''';
end;

function OtherTableBranch(const pKeyword, pCondition, pAnchorTable: string; const pTables: TArray<string>): Boolean;
begin
  Result:= False;
  if not SameStr(pKeyword, KW_WHEN) then
    Exit;
  if TRegEx.IsMatch(pCondition, RE_OP_WORDS) then
    Exit;
  var Anchor:= pAnchorTable.ToUpperInvariant;
  for var M in TRegEx.Matches(pCondition, RE_LITERAL) do
    if SameStr(M.Groups[1].Value.Replace('''''', '''').ToUpperInvariant, Anchor) then
      Exit;
  for var M in TRegEx.Matches(pCondition, RE_EQ_LITERAL) do
  begin
    var V:= (Grp(M, 1) + Grp(M, 2)).Replace('''''', '''').ToUpperInvariant;
    for var T in pTables do
      if SameStr(T.ToUpperInvariant, V) then
        Exit(True);
  end;
end;

function TraceAnchorText(const pPath: string; pLine: Integer): string;
begin
  Result:= LeafOf(pPath) + ':' + IntToStr(pLine);
end;

function TraceNoteLocator(const pAnchorFile, pRefFile: string; pRefLine: Integer): string;
begin
  if SameText(LeafOf(pAnchorFile), LeafOf(pRefFile)) then
    Result:= ':' + IntToStr(pRefLine)
  else
    Result:= TraceAnchorText(pRefFile, pRefLine);
end;

function TraceWord(const pS: string; pMax: Integer = TRACE_WORD_MAX): string;
begin
  var T:= PsTrim(TRegEx.Replace(pS, '\s+', ' '));
  T:= T.Replace(' -- ', ' - ').Replace(' @', ' at ').Replace(' [', ' (').Replace('"', '''').Replace('; ', ', ');
  if Length(T) > pMax then
    Result:= Copy(T, 1, pMax - Length(ELLIPSIS)) + ELLIPSIS
  else
    Result:= T;
end;

function TraceNoteText(const pS: string): string;
begin
  Result:= pS.Replace('; ', ', ');
end;

function TraceStopText(const pS: string): string;
begin
  var T:= PsTrim(TRegEx.Replace(pS, '\s+', ' '));
  T:= TRegEx.Replace(T, ' \[([^\]]*)\]', ' ($1)');
  Result:= T.Replace(' -- ', ' - ').Replace(' @', ' at ').Replace(' [', ' (').Replace('; ', ', ');
end;

initialization
  GTokenRx:= TRegEx.Create(RE_TOKEN, [roCompiled]);
  GStmtRx:= TRegEx.Create(RE_STMT, [roCompiled]);

end.
