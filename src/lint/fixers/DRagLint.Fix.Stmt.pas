unit DRagLint.Fix.Stmt;

{ Lane A3 -- statement / block fixers (17 ids) of the autofix wave
  (docs\superpowers\plans\2026-10-27-autofix-wave-plan.md, section 3 "A3").

  Every fixer here re-reads the finding's file through TAstParseCache, finds the
  statement the finding points at, and rewrites WHOLE LINES (tekReplaceLines /
  tekDeleteLines) or one guarded in-line span. A fixer DECLINES (returns no
  edits) whenever it cannot prove the rewrite keeps the code compiling and
  behaving as before: a statement that shares its line with other code, a
  conditional directive or a non-ASCII character in the touched lines, a
  dropped condition that may call something, a dangling else, a label in dead
  code ... -- tests\autofix\declines\ pins those shapes, tests\autofix\fixtures\
  the rewrites.

  The unit registers itself from its OWN initialization; DRagLint.Lint.Autofix
  never uses a fixer unit, so no unit cycle forms. }

interface

uses
  System.Classes
  , TreeSitter
  , DRagLint.Core.Model
  , DRagLint.Refactor.TextEdit
  ;

/// <summary>Is ANode an expression a fixer may drop or duplicate without
/// changing behaviour: identifiers, literals, field paths, subscripts,
/// operators and parentheses -- no call, no inherited, no anonymous method.</summary>
/// <param name="ANode">The expression node (an if condition, an assignment rhs).</param>
/// <returns>True when every node of the expression is on the allow-list; False
/// for a null node.</returns>
/// <remarks>A bare identifier (or a field path's last name) can be a
/// parameterless FUNCTION in Delphi; the AST cannot tell, so it counts as
/// side-effect free -- the same trade the autofix plan states for
/// identical-then-else. Shared with G9's block-shaped identical-then-else.</remarks>
function IsSideEffectFree(const ANode: TTSNode): Boolean;

/// <summary>The identical-then-else fix for the SINGLE-STATEMENT shape the
/// DeadCodeChecks finding reports (`if C then X := 1 else X := 1`): the if
/// becomes its then branch.</summary>
/// <param name="AFinding">An identical-then-else finding; its start is the if.</param>
/// <param name="ALines">The finding's file as the edit builder read it (borrowed).</param>
/// <returns>One edit, or none when the condition may have a side effect (see
/// IsSideEffectFree), the if is not a statement-list member spanning its own
/// lines, or the touched lines are not plain 7-bit text.</returns>
/// <remarks>NOT registered here: lane G9 owns the one registered
/// identical-then-else fixer (ParityExtChecks, block and call shapes) and
/// delegates the shape it declines to this function, so exactly one fixer per
/// rule id is registered.</remarks>
function FixIdenticalAssignmentBranches(const AFinding: TLintFinding; ALines: TStringList): TArray<TTextEdit>;

implementation

uses
  System.SysUtils
  , System.IOUtils
  , System.Math
  , System.StrUtils
  , System.RegularExpressions
  , DRagLint.Lint.Autofix
  , DRagLint.Diagnostics.ParseCache
  , DRagLint.Diagnostics.AstChecks
  ;

const
  { one indent level of the rewritten code }
  STEP = '  ';
  { the last 7-bit character: AST columns are byte columns, Lines are chars }
  MAX_ASCII = 127;

type
  { What follows a statement on its last line. }
  TTailKind = (tkNone, tkSemi, tkSemiComment, tkComment, tkOther);

  { One parsed file as a fixer sees it: the tree, the parsed bytes and the
    lines the edit builder read. Lines is borrowed, never freed here. }
  TFx = record
    Path : string     ;
    Src  : TBytes     ;
    Root : TTSNode    ;
    Lines: TStrings   ;
    function Txt(const N: TTSNode): string;
    function Line(ARow: Integer): string;
    function Indent(ARow: Integer): string;
    function Before(const N: TTSNode): string;
    function After(const N: TTSNode): string;
    function Tail(const N: TTSNode): TTailKind;
    function Clean(AFirstRow, ALastRow: Integer): Boolean;
    function NodeAt(ALine, ACol: Integer): TTSNode;
    function StmtAt(ALine, ACol: Integer): TTSNode;
  end;

{ ---- node geometry (0-based rows / columns) ---- }

function Row(const N: TTSNode): Integer;
begin
  Result:= Integer(N.StartPoint.Row);
end;

function ERow(const N: TTSNode): Integer;
begin
  Result:= Integer(N.EndPoint.Row);
end;

function Col(const N: TTSNode): Integer;
begin
  Result:= Integer(N.StartPoint.Column);
end;

function ECol(const N: TTSNode): Integer;
begin
  Result:= Integer(N.EndPoint.Column);
end;

function SameNode(const A, B: TTSNode): Boolean;
begin
  Result:= (not A.IsNull) and (not B.IsNull) and (A.StartByte = B.StartByte) and (A.EndByte = B.EndByte)
    and (A.NodeType = B.NodeType);
end;

function StartsAt(const N: TTSNode; ALine, ACol: Integer): Boolean;
begin
  Result:= (not N.IsNull) and (Row(N) = ALine - 1) and (Col(N) = ACol - 1);
end;

function IsTrivia(const N: TTSNode): Boolean;
var
  T: string;
begin
  T:= N.NodeType;
  Result:= (T = 'comment') or (T = 'pp') or ((Length(T) > 1) and (T[1] = 'k') and CharInSet(T[2], ['A'..'Z']));
end;

{ a begin..end block or a try / repeat / case-else statement list }
function IsList(const N: TTSNode): Boolean;
begin
  Result:= (not N.IsNull) and ((N.NodeType = 'block') or (N.NodeType = 'statements'));
end;

function ListStmts(const AList: TTSNode): TArray<TTSNode>;
var
  I: Integer;
begin
  Result:= nil;
  for I:= 0 to AList.NamedChildCount - 1 do
    if not IsTrivia(AList.NamedChild(I)) then Result:= Result + [AList.NamedChild(I)];
end;

function IndexIn(const AStmts: TArray<TTSNode>; const N: TTSNode): Integer;
var
  I: Integer;
begin
  Result:= -1;
  for I:= 0 to High(AStmts) do
    if SameNode(AStmts[I], N) then Exit(I);
end;

function Ancestor(const N: TTSNode; const AType: string): TTSNode;
begin
  Result:= N;
  while (not Result.IsNull) and (Result.NodeType <> AType) do Result:= Result.Parent;
end;

{ the nearest ancestor-or-self of type AType that starts at (ALine, ACol) }
function AncestorAt(const N: TTSNode; const AType: string; ALine, ACol: Integer): TTSNode;
begin
  Result:= Ancestor(N, AType);
  if not StartsAt(Result, ALine, ACol) then Result:= Default(TTSNode);
end;

function HasDescendant(const N: TTSNode; const AType: string): Boolean;
var
  I: Integer;
begin
  Result:= False;
  if N.IsNull then Exit;
  for I:= 0 to N.NamedChildCount - 1 do
    if (N.NamedChild(I).NodeType = AType) or HasDescendant(N.NamedChild(I), AType) then Exit(True);
end;

function ChildOfType(const N: TTSNode; const AType: string): TTSNode;
var
  I: Integer;
begin
  Result:= Default(TTSNode);
  for I:= 0 to N.NamedChildCount - 1 do
    if N.NamedChild(I).NodeType = AType then Exit(N.NamedChild(I));
end;

{ the assignment a statement-list member is, or a null node }
function AssignOf(const S: TTSNode): TTSNode;
begin
  Result:= Default(TTSNode);
  if S.NodeType = 'assignment' then Result:= S
  else if (S.NodeType = 'statement') and (S.NamedChildCount = 1) and (S.NamedChild(0).NodeType = 'assignment') then
    Result:= S.NamedChild(0);
end;

{ the statement-list member that holds node N: N itself, or its 'statement' wrapper }
function ListMember(const N: TTSNode): TTSNode;
begin
  Result:= N;
  if (not Result.IsNull) and (Result.Parent.NodeType = 'statement') then Result:= Result.Parent;
end;

{ S is exactly one comment opened by AOpen and closed by AClose -- not a directive }
function IsOneComment(const S, AOpen, AClose: string): Boolean;
begin
  Result:= S.StartsWith(AOpen) and (not S.StartsWith(AOpen + '$')) and S.EndsWith(AClose)
    and (Pos(AClose, S) = Length(S) - Length(AClose) + 1);
end;

function IsCommentText(const S: string): Boolean;
begin
  Result:= S.StartsWith('//') or IsOneComment(S, '{', '}') or IsOneComment(S, '(*', '*)');
end;

{ a statement's text, lower-cased, without blanks, a trailing ';' or a trailing '()' }
function NormStmt(const S: string): string;
begin
  Result:= LowerCase(TRegEx.Replace(S, '\s+', ''));
  while Result.EndsWith(';') do Result:= Copy(Result, 1, Length(Result) - 1);
  if Result.EndsWith('()') then Result:= Copy(Result, 1, Length(Result) - 2);
end;

{ whitespace collapsed, trailing ';' dropped: "token-identical" for two bodies }
function NormBody(const S: string): string;
begin
  Result:= Trim(TRegEx.Replace(S, '\s+', ' '));
  while Result.EndsWith(';') do Result:= TrimRight(Copy(Result, 1, Length(Result) - 1));
end;

function StripSemi(const S: string): string;
begin
  Result:= TrimRight(S);
  while Result.EndsWith(';') do Result:= TrimRight(Copy(Result, 1, Length(Result) - 1));
end;

function IsSimplePath(const S: string): Boolean;
begin
  Result:= TRegEx.IsMatch(S, '^[A-Za-z_]\w*(\.[A-Za-z_]\w*)*$');
end;

function WordIn(const AText, AWord: string): Boolean;
begin
  Result:= TRegEx.IsMatch(AText, '(?<![\w])' + TRegEx.Escape(AWord) + '(?![\w])', [roIgnoreCase]);
end;

{ S with ACount leading blanks removed (fewer when it has fewer), or -ACount added }
function ShiftLeft(const S: string; ACount: Integer): string;
var
  Lead: Integer;
begin
  if ACount < 0 then Exit(StringOfChar(' ', -ACount) + S);
  Lead:= 0;
  while (Lead < ACount) and (Lead < Length(S)) and (S[Lead + 1] = ' ') do Inc(Lead);
  Result:= Copy(S, Lead + 1, MaxInt);
end;

function IsKeywordType(const T: string): Boolean;
begin
  Result:= (Length(T) > 1) and (T[1] = 'k') and CharInSet(T[2], ['A'..'Z']);
end;

function IsSideEffectFree(const ANode: TTSNode): Boolean;
var
  T: string ;
  I: Integer;
begin
  if ANode.IsNull then Exit(False);
  T:= ANode.NodeType;
  if not (MatchStr(T, ['identifier', 'literalNumber', 'literalString', 'literalChar', 'exprBinary', 'exprUnary',
                       'exprParens', 'exprDot', 'exprSubscript', 'exprBrackets', 'exprArgs', 'range'])
          or IsKeywordType(T)) then Exit(False);
  for I:= 0 to ANode.NamedChildCount - 1 do
    if not IsSideEffectFree(ANode.NamedChild(I)) then Exit(False);
  Result:= True;
end;

{ ---- TFx ---- }

{ the parsed view of APath; False when it does not parse or ALines is nil }
function OpenFx(const APath: string; ALines: TStrings; out AFx: TFx): Boolean;
var
  PF: TParsedFile;
begin
  AFx:= Default(TFx);
  AFx.Path := APath;
  AFx.Lines:= ALines;
  PF:= TAstParseCache.Get(APath);
  Result:= (PF.Tree <> nil) and (ALines <> nil);
  if not Result then Exit;
  AFx.Src := PF.Src;
  AFx.Root:= PF.Tree.RootNode;
end;

function TFx.Txt(const N: TTSNode): string;  // dl:ok duplicate-code@6565 -- REVIEWED 2026-10-27: the per-unit raw node-text helper every checker carries; the one shared copy (Flow.Lattices.NodeStr) is implementation-only
var
  S, E: Integer;
begin
  Result:= '';
  if N.IsNull then Exit;
  S:= Integer(N.StartByte);
  E:= Integer(N.EndByte);
  if (E <= S) or (S < 0) or (E > Length(Src)) then Exit;
  Result:= TEncoding.UTF8.GetString(Src, S, E - S);
end;

function TFx.Line(ARow: Integer): string;
begin
  Result:= if (ARow >= 0) and (ARow < Lines.Count) then Lines[ARow] else '';
end;

function TFx.Indent(ARow: Integer): string;
var
  S: string ;
  I: Integer;
begin
  S:= Line(ARow);
  I:= 0;
  while (I < Length(S)) and CharInSet(S[I + 1], [' ', #9]) do Inc(I);
  Result:= Copy(S, 1, I);
end;

function TFx.Before(const N: TTSNode): string;
begin
  Result:= Copy(Line(Row(N)), 1, Col(N));
end;

function TFx.After(const N: TTSNode): string;
begin
  Result:= Copy(Line(ERow(N)), ECol(N) + 1, MaxInt);
end;

function TFx.Tail(const N: TTSNode): TTailKind;
var
  S: string;
begin
  S:= Trim(After(N));
  if S = '' then Exit(tkNone);
  if S[1] = ';' then
  begin
    S:= Trim(Copy(S, 2, MaxInt));
    if S = '' then Exit(tkSemi);
    if IsCommentText(S) then Exit(tkSemiComment);
    Exit(tkOther);
  end;
  Result:= if IsCommentText(S) then tkComment else tkOther;
end;

{ rows a fixer may rebuild from Lines: 7-bit text (AST columns are byte
  columns) and no conditional directive (the parse saw the active branch only) }
function TFx.Clean(AFirstRow, ALastRow: Integer): Boolean;
var
  R: Integer;
  S: string ;
  C: Char   ;
begin
  Result:= (AFirstRow >= 0) and (ALastRow >= AFirstRow) and (ALastRow < Lines.Count);
  if not Result then Exit;
  for R:= AFirstRow to ALastRow do
  begin
    S:= Lines[R];
    if S.Contains('{$') or S.Contains('(*$') then Exit(False);
    for C in S do
      if Ord(C) > MAX_ASCII then Exit(False);
  end;
end;

{ the deepest named node holding the 1-based point (ALine, ACol) }
function TFx.NodeAt(ALine, ACol: Integer): TTSNode;
var
  R, C : Integer;
  I    : Integer;
  Ch   : TTSNode;
  Found: Boolean;

  function StartsBy(const P: TTSPoint): Boolean;
  begin
    Result:= (Integer(P.Row) < R) or ((Integer(P.Row) = R) and (Integer(P.Column) <= C));
  end;

  function EndsAfter(const P: TTSPoint): Boolean;
  begin
    Result:= (Integer(P.Row) > R) or ((Integer(P.Row) = R) and (Integer(P.Column) > C));
  end;

begin
  R:= ALine - 1;
  C:= ACol - 1;
  Result:= Root;
  repeat
    Found:= False;
    for I:= 0 to Result.NamedChildCount - 1 do
    begin
      Ch:= Result.NamedChild(I);
      if StartsBy(Ch.StartPoint) and EndsAfter(Ch.EndPoint) then
      begin
        Result:= Ch;
        Found := True;
        Break;
      end;
    end;
  until not Found;
end;

{ the statement-list member that STARTS at (ALine, ACol), or a null node }
function TFx.StmtAt(ALine, ACol: Integer): TTSNode;
begin
  Result:= NodeAt(ALine, ACol);
  while (not Result.IsNull) and (not IsList(Result.Parent)) do Result:= Result.Parent;
  if not StartsAt(Result, ALine, ACol) then Result:= Default(TTSNode);
end;

{ ---- edits ---- }

function ReplaceRows(const AFx: TFx; AFirstRow, ALastRow: Integer; const ANew: TArray<string>): TTextEdit;
begin
  Result:= Default(TTextEdit);
  Result.FilePath  := AFx.Path;
  if Length(ANew) = 0 then
  begin
    Result.Kind   := tekDeleteLines;
    Result.Line   := AFirstRow + 1;
    Result.EndLine:= ALastRow + 1;
    Exit;
  end;
  Result.Kind      := tekReplaceLines;
  Result.Line      := AFirstRow + 1;
  Result.EndLine   := ALastRow + 1;
  Result.Text      := string.Join(sLineBreak, ANew);
  Result.ExpectText:= AFx.Line(AFirstRow);
end;

function ReplaceSpan(const AFx: TFx; const N: TTSNode; const AText: string): TTextEdit;
begin
  Result:= Default(TTextEdit);
  Result.FilePath  := AFx.Path;
  Result.Kind      := tekReplaceInLine;
  Result.Line      := Row(N) + 1;
  Result.Col       := Col(N) + 1;
  Result.EndCol    := ECol(N) + 1;
  Result.Text      := AText;
  Result.ExpectText:= Copy(AFx.Line(Row(N)), Col(N) + 1, ECol(N) - Col(N));
end;

{ deletes statement N when it owns its lines; a trailing comment survives on
  its own line at the statement's indent }
function DropStmt(const AFx: TFx; const N: TTSNode; out AEdit: TTextEdit): Boolean;
var
  S: string;
begin
  AEdit:= Default(TTextEdit);
  Result:= (Trim(AFx.Before(N)) = '') and AFx.Clean(Row(N), ERow(N));
  if not Result then Exit;
  case AFx.Tail(N) of
    tkNone, tkSemi: AEdit:= ReplaceRows(AFx, Row(N), ERow(N), nil);
    tkComment, tkSemiComment:
      begin
        S:= Trim(AFx.After(N));
        if S[1] = ';' then S:= Trim(Copy(S, 2, MaxInt));
        AEdit:= ReplaceRows(AFx, Row(N), ERow(N), [AFx.Indent(Row(N)) + S]);
      end;
  else
    Result:= False;
  end;
end;

{ rows AFirstRow..ALastRow with the smallest indent of their non-blank rows
  replaced by AIndent }
function Reindent(const AFx: TFx; AFirstRow, ALastRow: Integer; const AIndent: string): TArray<string>;
var
  R, MinI: Integer;
  S      : string ;
begin
  Result:= nil;
  MinI:= MaxInt;
  for R:= AFirstRow to ALastRow do
    if Trim(AFx.Line(R)) <> '' then MinI:= Min(MinI, Length(AFx.Indent(R)));
  for R:= AFirstRow to ALastRow do
  begin
    S:= AFx.Line(R);
    Result:= Result + [if Trim(S) = '' then '' else AIndent + Copy(S, MinI + 1, MaxInt)];
  end;
end;

{ node N's text as lines at AIndent: the first row cut at N's start, the last
  at its end, the rows between shifted left as far as the first one moved }
function NodeLines(const AFx: TFx; const N: TTSNode; const AIndent: string): TArray<string>;
var
  R, Delta: Integer;
  S       : string ;
begin
  if Row(N) = ERow(N) then
  begin
    Result:= [AIndent + Copy(AFx.Line(Row(N)), Col(N) + 1, ECol(N) - Col(N))];
    Exit;
  end;
  Result:= [AIndent + Copy(AFx.Line(Row(N)), Col(N) + 1, MaxInt)];
  Delta:= if Trim(AFx.Before(N)) = '' then Col(N) - Length(AIndent)
    else Length(AFx.Indent(Row(N))) + Length(STEP) - Length(AIndent);
  for R:= Row(N) + 1 to ERow(N) do
  begin
    S:= AFx.Line(R);
    if R = ERow(N) then S:= Copy(S, 1, ECol(N));
    Result:= Result + [if Trim(S) = '' then '' else ShiftLeft(S, Delta)];
  end;
end;

{ the statements of a begin..end block re-indented to AIndent; False unless
  begin ends its line and end starts its line }
function BlockInner(const AFx: TFx; const ABlock: TTSNode; const AIndent: string; out AOut: TArray<string>): Boolean;
var
  KB, KE: TTSNode;
begin
  AOut:= nil;
  Result:= False;
  if (ABlock.NodeType <> 'block') or (ABlock.NamedChildCount < 2) then Exit;
  KB:= ABlock.NamedChild(0);
  KE:= ABlock.NamedChild(ABlock.NamedChildCount - 1);
  if (KB.NodeType <> 'kBegin') or (KE.NodeType <> 'kEnd') then Exit;
  if (Trim(AFx.After(KB)) <> '') or (Trim(AFx.Before(KE)) <> '') then Exit;
  if not AFx.Clean(Row(KB), ERow(KE)) then Exit;
  if Row(KE) > Row(KB) + 1 then AOut:= Reindent(AFx, Row(KB) + 1, Row(KE) - 1, AIndent);
  Result:= True;
end;

{ ends the last non-blank line of AOut with ';' when ASemi; False when that
  line ends in a comment the ';' cannot follow }
function EnsureSemi(var AOut: TArray<string>; ASemi: Boolean): Boolean;
var
  I: Integer;
  S: string ;
begin
  Result:= True;
  if not ASemi then Exit;
  for I:= High(AOut) downto 0 do
  begin
    S:= TrimRight(AOut[I]);
    if S = '' then Continue;
    if S.EndsWith(';') then Exit;
    if S.Contains('//') or S.Contains('}') or S.Contains('*)') then Exit(False);
    AOut[I]:= S + ';';
    Exit;
  end;
end;

procedure StripLastSemi(var AOut: TArray<string>);
begin
  if Length(AOut) > 0 then AOut[High(AOut)]:= StripSemi(AOut[High(AOut)]);
end;

{ the text after N up to and including a ';' that directly follows it }
function SemiFollows(const AFx: TFx; const N: TTSNode): Boolean;
begin
  Result:= Trim(AFx.After(N)).StartsWith(';');
end;

{ ';' when node N's own span ends in one (an if / case statement node holds
  its terminator, an assignment does not), else '' }
function TrailSemi(const AFx: TFx; const N: TTSNode): string;
begin
  Result:= if TrimRight(AFx.Txt(N)).EndsWith(';') then ';' else '';
end;

{ is AName (case-insensitive) an identifier anywhere under N? }
function MentionsIdent(const AFx: TFx; const N: TTSNode; const AName: string): Boolean;
var
  I: Integer;
begin
  if N.IsNull then Exit(False);
  if (N.NodeType = 'identifier') and SameText(AFx.Txt(N), AName) then Exit(True);
  for I:= 0 to N.NamedChildCount - 1 do
    if MentionsIdent(AFx, N.NamedChild(I), AName) then Exit(True);
  Result:= False;
end;

procedure CollectIdents(const AFx: TFx; const N: TTSNode; const AName: string; var AOut: TArray<TTSNode>);
var
  I: Integer;
begin
  if N.IsNull then Exit;
  if (N.NodeType = 'identifier') and SameText(AFx.Txt(N), AName) then AOut:= AOut + [N];
  for I:= 0 to N.NamedChildCount - 1 do CollectIdents(AFx, N.NamedChild(I), AName, AOut);
end;

{ the declVar name node of a local AName declared in ADefProc's own var
  sections, or a null node }
function LocalDecl(const AFx: TFx; const ADefProc: TTSNode; const AName: string): TTSNode;
var
  I, J, K: Integer;
  DV, V  : TTSNode;
begin
  Result:= Default(TTSNode);
  if ADefProc.IsNull then Exit;
  for I:= 0 to ADefProc.NamedChildCount - 1 do
  begin
    DV:= ADefProc.NamedChild(I);
    if DV.NodeType <> 'declVars' then Continue;
    for J:= 0 to DV.NamedChildCount - 1 do
    begin
      V:= DV.NamedChild(J);
      if V.NodeType <> 'declVar' then Continue;
      for K:= 0 to V.NamedChildCount - 1 do
        if (V.NamedChild(K).NodeType = 'identifier') and SameText(AFx.Txt(V.NamedChild(K)), AName) then
          Exit(V.NamedChild(K));
    end;
  end;
end;

{ a synthetic unused-local finding on a declaration name, for the unused-local
  fixer that owns how a shared `var A, B: T;` line is spliced }
function UnusedLocalAt(const AFx: TFx; const ADeclName: TTSNode): TLintFinding;
begin
  Result:= Default(TLintFinding);
  Result.RuleId   := 'unused-local';
  Result.FilePath := AFx.Path;
  Result.StartLine:= Row(ADeclName) + 1;
  Result.StartCol := Col(ADeclName) + 1;
  Result.EndLine  := ERow(ADeclName) + 1;
  Result.EndCol   := ECol(ADeclName) + 1;
end;

{ one try / finally around the statements strictly after AOpen up to ABodyLast;
  a non-null AClose (a release statement after ABodyLast) is consumed -- its
  line becomes the finally, whose body is AFinally }
function WrapBetween(const AFx: TFx; const AOpen, ABodyFirst, ABodyLast, AClose: TTSNode;  // dl:ok too-many-exit-points@51ba -- REVIEWED 2026-10-27: a guard-clause ladder; every Exit declines a shape the fix must not rewrite
  const AFinally: string; out AEdit: TTextEdit): Boolean;
var
  LastRow: Integer;
  BodyEnd: Integer;
  R      : Integer;
  Consume: Boolean;
begin
  AEdit:= Default(TTextEdit);
  Result:= False;
  Consume:= not AClose.IsNull;
  if Row(ABodyFirst) <= ERow(AOpen) then Exit;                     { the body starts on a line of its own }
  if Trim(AFx.Before(ABodyFirst)) <> '' then Exit;
  if AFx.Tail(ABodyLast) = tkOther then Exit;
  LastRow:= ERow(ABodyLast);
  if Consume then
  begin
    if (Row(AClose) <= ERow(ABodyLast)) or (Trim(AFx.Before(AClose)) <> '') then Exit;
    if AFx.Tail(AClose) not in [tkNone, tkSemi] then Exit;
    LastRow:= ERow(AClose);
  end;
  if not AFx.Clean(Row(AOpen), LastRow) then Exit;
  BodyEnd:= if Consume then Row(AClose) else ERow(ABodyLast) + 1;
  if not WrapInTryFinally(AFx.Path, AFx.Lines, ERow(AOpen) + 2, BodyEnd, AFinally, AFx.Indent(Row(AOpen)), AEdit) then Exit;
  { the block starts at the opening statement (kept verbatim), so it covers the
    line a finding anchored on the open reports }
  for R:= ERow(AOpen) downto Row(AOpen) do AEdit.Text:= AFx.Line(R) + sLineBreak + AEdit.Text;
  AEdit.Line      := Row(AOpen) + 1;
  AEdit.ExpectText:= AFx.Line(Row(AOpen));
  AEdit.EndLine   := LastRow + 1;
  Result:= True;
end;

function WithSemi(const S: string): string;
begin
  Result:= StripSemi(Trim(S)) + ';';
end;

{ ==== the fixers ==== }

{ code-after-exit: an unconditional Exit / raise / Break / Continue / Halt
  mirrors TAstChecker's IsTerminator }
function IsTerminator(const AFx: TFx; const S: TTSNode): Boolean;
var
  Inner, Ent: TTSNode;
  Nm        : string ;
begin
  Result:= False;
  if S.NodeType = 'raise' then Exit(True);
  if (S.NodeType <> 'statement') or (S.NamedChildCount = 0) then Exit;
  Inner:= S.NamedChild(0);
  if Inner.NodeType = 'identifier' then
  begin
    Nm:= LowerCase(AFx.Txt(Inner));
    Result:= MatchStr(Nm, ['exit', 'break', 'continue', 'halt']);
  end
  else if Inner.NodeType = 'exprCall' then
  begin
    Ent:= Inner.ChildByField('entity');
    Result:= (not Ent.IsNull) and (Ent.NodeType = 'identifier') and MatchStr(LowerCase(AFx.Txt(Ent)), ['exit', 'halt']);
  end;
end;

{ code-after-exit: delete everything after the terminator to the end of the
  list. Only the FIRST finding of a list acts (it covers the later ones); a
  list whose dead part holds a goto label is reachable and left alone. }
function FixCodeAfterExit(const AFinding: TLintFinding; ALines: TStringList): TArray<TTextEdit>;  // dl:ok too-many-exit-points@356b -- REVIEWED 2026-10-27: a guard-clause ladder; every Exit declines a shape the fix must not rewrite
var
  Fx  : TFx            ;
  N   : TTSNode        ;
  Kids: TArray<TTSNode>;
  Idx : Integer        ;
  I   : Integer        ;
  Last: TTSNode        ;
begin
  Result:= nil;
  if not OpenFx(AFinding.FilePath, ALines, Fx) then Exit;
  N:= Fx.StmtAt(AFinding.StartLine, AFinding.StartCol);
  if N.IsNull then Exit;
  Kids:= ListStmts(N.Parent);
  Idx:= IndexIn(Kids, N);
  if (Idx < 1) or (not IsTerminator(Fx, Kids[Idx - 1])) then Exit;
  for I:= 0 to Idx - 2 do
    if IsTerminator(Fx, Kids[I]) then Exit;
  for I:= Idx to High(Kids) do
    if (Kids[I].NodeType = 'label') or HasDescendant(Kids[I], 'label') then Exit;
  Last:= Kids[High(Kids)];
  if (Trim(Fx.Before(N)) <> '') or (Fx.Tail(Last) = tkOther) or (not Fx.Clean(Row(N), ERow(Last))) then Exit;
  Result:= [ReplaceRows(Fx, Row(N), ERow(Last), nil)];
end;

{ redundant-continue-exit: delete the trailing Continue / Exit -- only from a
  statement list, never the lone body of a `for .. do Continue;` }
function FixRedundantContinueExit(const AFinding: TLintFinding; ALines: TStringList): TArray<TTextEdit>;
var
  Fx: TFx      ;
  N : TTSNode  ;
  E : TTextEdit;
begin
  Result:= nil;
  if not OpenFx(AFinding.FilePath, ALines, Fx) then Exit;
  N:= Fx.StmtAt(AFinding.StartLine, AFinding.StartCol);
  if (not N.IsNull) and DropStmt(Fx, N, E) then Result:= [E];
end;

{ the text between two nodes (end of A to start of B), joined over rows }
function Between(const AFx: TFx; const A, B: TTSNode): string;
var
  R: Integer;
begin
  if ERow(A) = Row(B) then Exit(Copy(AFx.Line(Row(B)), ECol(A) + 1, Col(B) - ECol(A)));
  Result:= AFx.After(A);
  for R:= ERow(A) + 1 to Row(B) - 1 do Result:= Result + ' ' + AFx.Line(R);
  Result:= Result + ' ' + AFx.Before(B);
end;

{ else-after-exit: `if C then Exit else S` -> `if C then Exit; S`, S moved out
  of the else (a begin..end is unwrapped). The if must be a member of a
  statement list -- inside another if's branch the split would change which
  statements the outer if guards. }
function FixElseAfterExit(const AFinding: TLintFinding; ALines: TStringList): TArray<TTextEdit>;  // dl:ok too-many-exit-points@fbe8 -- REVIEWED 2026-10-27: a guard-clause ladder; every Exit declines a shape the fix must not rewrite
var
  Fx           : TFx            ;
  K, N         : TTSNode        ;
  ThenN, ElseN : TTSNode        ;
  Ind          : string         ;
  Outp, Part   : TArray<string> ;
  R            : Integer        ;
begin
  Result:= nil;
  if not OpenFx(AFinding.FilePath, ALines, Fx) then Exit;
  K:= Fx.NodeAt(AFinding.StartLine, AFinding.StartCol);
  if K.NodeType <> 'kElse' then Exit;
  N:= K.Parent;
  if (N.NodeType <> 'ifElse') or (not IsList(N.Parent)) then Exit;
  ThenN:= N.ChildByField('then');
  ElseN:= N.ChildByField('else');
  if ThenN.IsNull or ElseN.IsNull then Exit;
  if (Trim(Fx.Before(N)) <> '') or (not Fx.Clean(Row(N), ERow(N))) then Exit;
  if not SameText(Trim(Between(Fx, ThenN, ElseN)), 'else') then Exit;   { a comment there would be lost }
  if Fx.Tail(ElseN) = tkOther then Exit;
  Ind:= Fx.Indent(Row(N));
  Outp:= nil;
  for R:= Row(N) to ERow(ThenN) - 1 do Outp:= Outp + [Fx.Line(R)];
  Outp:= Outp + [TrimRight(Copy(Fx.Line(ERow(ThenN)), 1, ECol(ThenN))) + ';'];
  if ElseN.NodeType = 'block' then
  begin
    if Fx.Tail(ElseN) not in [tkNone, tkSemi] then Exit;
    if not BlockInner(Fx, ElseN, Ind, Part) then Exit;
    if not EnsureSemi(Part, SemiFollows(Fx, ElseN) or (TrailSemi(Fx, N) <> '')) then Exit;
  end
  else
  begin
    Part:= NodeLines(Fx, ElseN, Ind);
    Part[High(Part)]:= Part[High(Part)] + Fx.After(ElseN);
  end;
  Result:= [ReplaceRows(Fx, Row(N), ERow(ElseN), Outp + Part)];
end;

{ identical-then-else: `if C then S else S` -> `S` when C has no call (the
  condition is dropped). A block branch is unwrapped. }
function FixIdenticalAssignmentBranches(const AFinding: TLintFinding; ALines: TStringList): TArray<TTextEdit>;  // dl:ok too-many-exit-points@d6c9 -- REVIEWED 2026-10-27: a guard-clause ladder; every Exit declines a shape the fix must not rewrite
var
  Fx          : TFx           ;
  N           : TTSNode       ;
  ThenN, ElseN: TTSNode       ;
  Part        : TArray<string>;
begin
  Result:= nil;
  if not OpenFx(AFinding.FilePath, ALines, Fx) then Exit;
  N:= AncestorAt(Fx.NodeAt(AFinding.StartLine, AFinding.StartCol), 'ifElse', AFinding.StartLine, AFinding.StartCol);
  if N.IsNull or (not IsSideEffectFree(N.ChildByField('condition'))) then Exit;
  ThenN:= N.ChildByField('then');
  ElseN:= N.ChildByField('else');
  if ThenN.IsNull or ElseN.IsNull or (not Fx.Clean(Row(N), ERow(N))) then Exit;
  if (Row(N) = ERow(N)) and (ThenN.NodeType <> 'block') then
  begin
    Result:= [ReplaceSpan(Fx, N, StripSemi(Fx.Txt(ThenN)) + TrailSemi(Fx, N))];
    Exit;
  end;
  if (Trim(Fx.Before(N)) <> '') or (not IsList(ListMember(N).Parent)) or (Fx.Tail(ElseN) = tkOther) then Exit;
  if ThenN.NodeType = 'block' then
  begin
    if Fx.Tail(ElseN) not in [tkNone, tkSemi] then Exit;
    if not BlockInner(Fx, ThenN, Fx.Indent(Row(N)), Part) then Exit;
    if not EnsureSemi(Part, SemiFollows(Fx, ElseN) or (TrailSemi(Fx, N) <> '')) then Exit;
  end
  else
  begin
    Part:= NodeLines(Fx, ThenN, Fx.Indent(Row(N)));
    Part[High(Part)]:= Part[High(Part)] + Fx.After(ElseN);
  end;
  Result:= [ReplaceRows(Fx, Row(N), ERow(ElseN), Part)];
end;

{ case-with-too-few-branches: one arm with ONE plain label -> an if. Ranges,
  label lists, comments inside the case, and an arm that holds an if while
  the case has an else part (dangling else) stay. }
function FixCaseFewBranches(const AFinding: TLintFinding; ALines: TStringList): TArray<TTextEdit>;  // dl:ok too-many-exit-points@57c1, cyclomatic-complexity@9649 -- REVIEWED 2026-10-27: a guard-clause ladder; every Exit declines a shape the fix must not rewrite
var
  Fx          : TFx            ;
  N, C, Sel   : TTSNode        ;
  Lbl, Body, V: TTSNode        ;
  Arms, Els   : TArray<TTSNode>;
  InElse      : Boolean        ;
  I           : Integer        ;
  SelTxt, Cond: string         ;
  Ind, S      : string         ;
  Outp, Part  : TArray<string> ;
begin
  Result:= nil;
  if not OpenFx(AFinding.FilePath, ALines, Fx) then Exit;
  N:= AncestorAt(Fx.NodeAt(AFinding.StartLine, AFinding.StartCol), 'case', AFinding.StartLine, AFinding.StartCol);
  if N.IsNull or HasDescendant(N, 'comment') or (not Fx.Clean(Row(N), ERow(N))) then Exit;
  Sel:= Default(TTSNode);
  Arms:= nil;
  Els := nil;
  InElse:= False;
  for I:= 0 to N.NamedChildCount - 1 do
  begin
    C:= N.NamedChild(I);
    if C.NodeType = 'kElse' then InElse:= True
    else if C.NodeType = 'caseCase' then Arms:= Arms + [C]
    else if IsTrivia(C) then Continue
    else if InElse then Els:= Els + [C]
    else if Sel.IsNull then Sel:= C;
  end;
  if (Length(Arms) <> 1) or Sel.IsNull or (Row(Sel) <> ERow(Sel)) then Exit;
  Lbl := Arms[0].ChildByField('label');
  Body:= Arms[0].ChildByField('body');
  if Lbl.IsNull or Body.IsNull or (Lbl.NamedChildCount <> 1) then Exit;
  V:= Lbl.NamedChild(0);
  if not (MatchStr(V.NodeType, ['literalNumber', 'literalString', 'literalChar', 'identifier', 'exprDot'])
          or ((V.NodeType = 'exprUnary') and IsSideEffectFree(V))) then Exit;
  if (Length(Els) > 0) and ((Body.NodeType = 'if') or HasDescendant(Body, 'if')) then Exit;
  if StripSemi(Fx.Txt(Body)) = '' then Exit;
  SelTxt:= Fx.Txt(Sel);
  if not MatchStr(Sel.NodeType, ['identifier', 'exprDot', 'exprCall', 'exprSubscript']) then SelTxt:= '(' + SelTxt + ')';
  Cond:= SelTxt + ' = ' + Fx.Txt(V);
  if Row(N) = ERow(N) then
  begin
    if Length(Els) > 1 then Exit;
    S:= 'if ' + Cond + ' then ' + StripSemi(Fx.Txt(Body));
    if Length(Els) = 1 then S:= S + ' else ' + StripSemi(Fx.Txt(Els[0]));
    Result:= [ReplaceSpan(Fx, N, S + TrailSemi(Fx, N))];
    Exit;
  end;
  if (Trim(Fx.Before(N)) <> '') or (Fx.Tail(N) = tkOther) then Exit;
  Ind:= Fx.Indent(Row(N));
  Outp:= [Ind + 'if ' + Cond + ' then'];
  Part:= NodeLines(Fx, Body, Ind + STEP);
  StripLastSemi(Part);
  Outp:= Outp + Part;
  if Length(Els) = 1 then
  begin
    Part:= NodeLines(Fx, Els[0], Ind + STEP);
    StripLastSemi(Part);
    Outp:= Outp + [Ind + 'else'] + Part;
  end
  else if Length(Els) > 1 then
  begin
    Outp:= Outp + [Ind + 'else', Ind + 'begin'];
    for I:= 0 to High(Els) do
    begin
      Part:= NodeLines(Fx, Els[I], Ind + STEP);
      if not EnsureSemi(Part, True) then Exit;
      Insert(Part, Outp, Length(Outp));   { append }
    end;
    Outp:= Outp + [Ind + 'end'];
  end;
  Outp[High(Outp)]:= Outp[High(Outp)] + TrailSemi(Fx, N) + Fx.After(N);
  Result:= [ReplaceRows(Fx, Row(N), ERow(N), Outp)];
end;

{ the assignment whose lhs starts at the finding, when it is a plain `:=`
  whose rhs has no call and which is a member of a statement list }
function DeadAssignment(const AFx: TFx; ALine, ACol: Integer; out AStmt: TTSNode): Boolean;
var
  A: TTSNode;
begin
  AStmt:= Default(TTSNode);
  A:= Ancestor(AFx.NodeAt(ALine, ACol), 'assignment');
  { `var X: T := V` is an assignment whose lhs is the declaration: dropping it drops X itself }
  Result:= (not A.IsNull) and StartsAt(A.ChildByField('lhs'), ALine, ACol)
    and (A.ChildByField('lhs').NodeType <> 'varAssignDef')
    and (A.ChildByField('operator').NodeType = 'kAssign') and IsSideEffectFree(A.ChildByField('rhs'));
  if not Result then Exit;
  AStmt:= ListMember(A);
  Result:= IsList(AStmt.Parent);
end;

{ overwrite-before-read: delete the first (dead) store when its rhs has no call }
function FixOverwriteBeforeRead(const AFinding: TLintFinding; ALines: TStringList): TArray<TTextEdit>;
var
  Fx: TFx      ;
  S : TTSNode  ;
  E : TTextEdit;
begin
  Result:= nil;
  if not OpenFx(AFinding.FilePath, ALines, Fx) then Exit;
  if DeadAssignment(Fx, AFinding.StartLine, AFinding.StartCol, S) and DropStmt(Fx, S, E) then Result:= [E];
end;

{ write-only-local, one finding: the deletions of every store to the local;
  False (nothing) unless EVERY mention of the name in the routine is the lhs
  of a call-free `:=` that can be deleted }
function WriteOnlyEdits(const AFx: TFx; const AFinding: TLintFinding; out AEdits: TArray<TTextEdit>): Boolean;  // dl:ok too-many-exit-points@f78a -- REVIEWED 2026-10-27: a guard-clause ladder; every Exit declines a shape the fix must not rewrite
var
  NameN, DefProc: TTSNode        ;
  Occ           : TArray<TTSNode>;
  O, S          : TTSNode        ;
  E             : TTextEdit      ;
  Nm            : string         ;
begin
  AEdits:= nil;
  Result:= False;
  NameN:= AFx.NodeAt(AFinding.StartLine, AFinding.StartCol);
  if (NameN.NodeType <> 'identifier') or (not StartsAt(NameN, AFinding.StartLine, AFinding.StartCol)) then Exit;
  if Ancestor(NameN, 'declVars').IsNull then Exit;           { an inline var: no section to splice }
  DefProc:= Ancestor(NameN, 'defProc');
  if DefProc.IsNull then Exit;
  Nm:= AFx.Txt(NameN);
  Occ:= nil;
  CollectIdents(AFx, DefProc, Nm, Occ);
  for O in Occ do
  begin
    if SameNode(O, NameN) then Continue;
    if not Ancestor(O, 'declVars').IsNull then Exit;         { a nested routine re-declares the name }
    if not DeadAssignment(AFx, Row(O) + 1, Col(O) + 1, S) then Exit;
    if not DropStmt(AFx, S, E) then Exit;
    AEdits:= AEdits + [E];
  end;
  Result:= True;
end;

{ write-only-local (per FILE): delete the stores, then the declarations
  through the unused-local fixer, which splices a shared `var A, B: T;` line }
function FixWriteOnlyLocals(const APath: string; const AFindings: TArray<TLintFinding>; out AFixed: Integer): TArray<TTextEdit>;
var
  SL       : TStringList        ;
  Fx       : TFx                ;
  F        : TLintFinding       ;
  Own      : TArray<TTextEdit>  ;
  Edits    : TArray<TTextEdit>  ;
  Decl     : TArray<TTextEdit>  ;
  Synth    : TArray<TLintFinding>;
  DeclFixed: Integer            ;
begin
  Result:= nil;
  AFixed:= 0;
  if not TFile.Exists(APath) then Exit;
  SL:= TStringList.Create;
  try
    SL.Text:= TEncoding.ANSI.GetString(TFile.ReadAllBytes(APath));
    if not OpenFx(APath, SL, Fx) then Exit;
    Edits:= nil;
    Synth:= nil;
    for F in AFindings do
    begin
      if not (SameText(F.RuleId, 'write-only-local') and SameText(F.FilePath, APath)) then Continue;
      if not WriteOnlyEdits(Fx, F, Own) then Continue;
      Insert(Own, Edits, Length(Edits));   { append }
      Synth:= Synth + [UnusedLocalAt(Fx, Fx.NodeAt(F.StartLine, F.StartCol))];
    end;
    if Length(Synth) = 0 then Exit;
    DeclFixed:= 0;
    Decl:= TAstChecker.BuildUnusedLocalFixEdits(APath, Synth, DeclFixed);
    if DeclFixed = 0 then Exit;                                 { no declaration to remove: leave it all }
    Result:= Edits + Decl;
    AFixed:= Length(Synth);
  finally
    SL.Free;
  end;
end;

{ swap-without-temp: `A := B; B := A;` -> `var LSwap := A; A := B; B := LSwap;` }
function FixSwapWithoutTemp(const AFinding: TLintFinding; ALines: TStringList): TArray<TTextEdit>;  // dl:ok too-many-exit-points@91d5 -- REVIEWED 2026-10-27: a guard-clause ladder; every Exit declines a shape the fix must not rewrite
var
  Fx            : TFx            ;
  A1, A2, S1, S2: TTSNode        ;
  Kids          : TArray<TTSNode>;
  Idx           : Integer        ;
  Rhs2          : TTSNode        ;
  L2            : string         ;
begin
  Result:= nil;
  if not OpenFx(AFinding.FilePath, ALines, Fx) then Exit;
  A2:= AncestorAt(Fx.NodeAt(AFinding.StartLine, AFinding.StartCol), 'assignment', AFinding.StartLine, AFinding.StartCol);
  if A2.IsNull then Exit;
  S2:= ListMember(A2);
  if not IsList(S2.Parent) then Exit;
  Kids:= ListStmts(S2.Parent);
  Idx:= IndexIn(Kids, S2);
  if Idx < 1 then Exit;
  S1:= Kids[Idx - 1];
  A1:= AssignOf(S1);
  if A1.IsNull then Exit;
  if not (SameText(Fx.Txt(A1.ChildByField('lhs')), Fx.Txt(A2.ChildByField('rhs')))
          and SameText(Fx.Txt(A1.ChildByField('rhs')), Fx.Txt(A2.ChildByField('lhs')))) then Exit;
  if WordIn(Fx.Txt(Ancestor(S2, 'defProc')), 'LSwap') then Exit;
  if (Row(S1) <> ERow(S1)) or (Row(S2) <> ERow(S2)) or (Row(S2) <> Row(S1) + 1) then Exit;
  if (Trim(Fx.Before(S1)) <> '') or (Trim(Fx.Before(S2)) <> '') then Exit;
  if (Fx.Tail(S1) = tkOther) or (Fx.Tail(S2) = tkOther) or (not Fx.Clean(Row(S1), Row(S2))) then Exit;
  Rhs2:= A2.ChildByField('rhs');
  L2:= Fx.Line(Row(S2));
  Result:= [ReplaceRows(Fx, Row(S1), Row(S2),
    [Fx.Indent(Row(S1)) + 'var LSwap := ' + Fx.Txt(A1.ChildByField('lhs')) + ';',
     Fx.Line(Row(S1)),
     Copy(L2, 1, Col(Rhs2)) + 'LSwap' + Copy(L2, ECol(Rhs2) + 1, MaxInt)])];
end;

{ exception-constructed-but-not-raised: prefix `raise ` to the statement }
function FixExceptionNotRaised(const AFinding: TLintFinding; ALines: TStringList): TArray<TTextEdit>;
var
  Fx: TFx      ;
  S : TTSNode  ;
  E : TTextEdit;
begin
  Result:= nil;
  if not OpenFx(AFinding.FilePath, ALines, Fx) then Exit;
  S:= AncestorAt(Fx.NodeAt(AFinding.StartLine, AFinding.StartCol), 'statement', AFinding.StartLine, AFinding.StartCol);
  if S.IsNull or (not Fx.Clean(Row(S), Row(S))) then Exit;
  E:= Default(TTextEdit);
  E.FilePath:= Fx.Path;
  E.Kind    := tekInsertInLine;
  E.Line    := AFinding.StartLine;
  E.Col     := AFinding.StartCol;
  E.Text    := 'raise ';
  Result:= [E];
end;

{ is System.SysUtils (or SysUtils) in a uses clause of the file? }
function UsesSysUtils(const AFx: TFx): Boolean;
begin
  Result:= TRegEx.IsMatch(AFx.Lines.Text, '\buses\b[^;]*\bSysUtils\b', [roIgnoreCase]);
end;

{ bare-except: `except S end` -> `except on E: Exception do begin S end; end`.
  Risky: a raised non-Exception object is no longer caught. Declines when the
  body already names an E (the handler variable would shadow it) or the unit
  does not use SysUtils (Exception would not resolve). }
function FixBareExcept(const AFinding: TLintFinding; ALines: TStringList): TArray<TTextEdit>;  // dl:ok too-many-exit-points@ff31 -- REVIEWED 2026-10-27: a guard-clause ladder; every Exit declines a shape the fix must not rewrite
var
  Fx           : TFx           ;
  K, T, Body   : TTSNode       ;
  KE           : TTSNode       ;
  R, R1, R2    : Integer       ;
  BI           : string        ;
  Outp         : TArray<string>;
begin
  Result:= nil;
  if not OpenFx(AFinding.FilePath, ALines, Fx) then Exit;
  K:= Fx.NodeAt(AFinding.StartLine, AFinding.StartCol);
  if K.NodeType <> 'kExcept' then Exit;
  T:= K.Parent;
  Body:= K.NextNamedSibling;
  if (T.NodeType <> 'try') or Body.IsNull or (Body.NodeType <> 'statements') then Exit;
  KE:= T.NamedChild(T.NamedChildCount - 1);
  if KE.NodeType <> 'kEnd' then Exit;
  if Fx.Tail(K) not in [tkNone, tkComment] then Exit;
  if (Row(Body) <= Row(K)) or (Trim(Fx.Before(Body)) <> '') or (Trim(Fx.Before(KE)) <> '') then Exit;
  if MentionsIdent(Fx, Body, 'E') or (not UsesSysUtils(Fx)) then Exit;
  R1:= Row(K) + 1;
  R2:= Row(KE) - 1;
  if not Fx.Clean(Row(K), R2) then Exit;
  BI:= Fx.Indent(Row(Body));
  Outp:= [Fx.Line(Row(K)), BI + 'on E: Exception do', BI + 'begin'];
  for R:= R1 to R2 do
    Outp:= Outp + [if Trim(Fx.Line(R)) = '' then '' else STEP + Fx.Line(R)];
  Outp:= Outp + [BI + 'end;'];
  Result:= [ReplaceRows(Fx, Row(K), R2, Outp)];
end;

{ duplicate-exception-handler: delete the shadowed `on E: X do ...` when its
  body is token-identical to the first handler for X (removal is then exactly
  what the code already does); differing bodies stay -- the author may have
  meant a different ORDER }
function FixDuplicateHandler(const AFinding: TLintFinding; ALines: TStringList): TArray<TTextEdit>;
var
  Fx      : TFx      ;
  N, T, H : TTSNode  ;
  First   : TTSNode  ;
  I       : Integer  ;
  E       : TTextEdit;
begin
  Result:= nil;
  if not OpenFx(AFinding.FilePath, ALines, Fx) then Exit;
  N:= AncestorAt(Fx.NodeAt(AFinding.StartLine, AFinding.StartCol), 'exceptionHandler', AFinding.StartLine, AFinding.StartCol);
  if N.IsNull then Exit;
  T:= N.Parent;
  First:= Default(TTSNode);
  for I:= 0 to T.NamedChildCount - 1 do
  begin
    H:= T.NamedChild(I);
    if SameNode(H, N) then Break;
    if (H.NodeType = 'exceptionHandler')
       and SameText(NormStmt(Fx.Txt(H.ChildByField('exception'))), NormStmt(Fx.Txt(N.ChildByField('exception')))) then
    begin
      First:= H;
      Break;
    end;
  end;
  if First.IsNull then Exit;
  if NormBody(Fx.Txt(First.ChildByField('body'))) <> NormBody(Fx.Txt(N.ChildByField('body'))) then Exit;
  if DropStmt(Fx, N, E) then Result:= [E];
end;

{ criticalsection-not-released: `Enter; S; Leave` in one list ->
  `Enter; try S finally Leave end`. A release inside S (an early Leave) or
  one in another routine stays. }
function FixCriticalSection(const AFinding: TLintFinding; ALines: TStringList): TArray<TTextEdit>;  // dl:ok too-many-exit-points@8e09 -- REVIEWED 2026-10-27: a guard-clause ladder; every Exit declines a shape the fix must not rewrite
var
  Fx       : TFx            ;
  S        : TTSNode        ;
  Kids     : TArray<TTSNode>;
  Idx, J, K: Integer        ;
  Key, Rel : string         ;
  M        : TMatch         ;
  E        : TTextEdit      ;
begin
  Result:= nil;
  if not OpenFx(AFinding.FilePath, ALines, Fx) then Exit;
  S:= Fx.StmtAt(AFinding.StartLine, AFinding.StartCol);
  if S.IsNull then Exit;
  Key:= NormStmt(Fx.Txt(S));
  Rel:= '';
  M:= TRegEx.Match(Key, '^(.+)\.enter$');
  if M.Success then Rel:= M.Groups[1].Value + '.leave';
  M:= TRegEx.Match(Key, '^(.+)\.acquire$');
  if M.Success then Rel:= M.Groups[1].Value + '.release';
  M:= TRegEx.Match(Key, '^tmonitor\.enter\((.+)\)$');
  if M.Success then Rel:= 'tmonitor.exit(' + M.Groups[1].Value + ')';
  M:= TRegEx.Match(Key, '^entercriticalsection\((.+)\)$');
  if M.Success then Rel:= 'leavecriticalsection(' + M.Groups[1].Value + ')';
  if Rel = '' then Exit;
  Kids:= ListStmts(S.Parent);
  Idx:= IndexIn(Kids, S);
  for J:= Idx + 1 to High(Kids) do
    if NormStmt(Fx.Txt(Kids[J])) = Rel then
    begin
      if J = Idx + 1 then Exit;                                   { nothing to protect }
      for K:= Idx + 1 to J - 1 do
        if NormStmt(Fx.Txt(Kids[K])).Contains(Rel) then Exit;     { an early release inside }
      if WrapBetween(Fx, S, Kids[Idx + 1], Kids[J - 1], Kids[J], WithSemi(Fx.Txt(Kids[J])), E) then Result:= [E];  // dl:ok used-before-assignment@f8e3 -- REVIEWED 2026-10-27: FP: E is WrapBetween's out AEdit (a signature split over two lines)
      Exit;
    end;
end;

{ is AStmt a release of AName: Free / DisposeOf / Destroy / FreeAndNil? }
function IsFreeOf(const AStmt, AName: string): Boolean;
var
  X: string;
begin
  X:= LowerCase(AName);
  Result:= MatchStr(AStmt, [X + '.free', X + '.disposeof', X + '.destroy', 'freeandnil(' + X + ')']);
end;

function MentionsFreeOf(const AStmt, AName: string): Boolean;
var
  X: string;
begin
  X:= LowerCase(AName);
  Result:= AStmt.Contains(X + '.free') or AStmt.Contains(X + '.disposeof') or AStmt.Contains(X + '.destroy')
    or AStmt.Contains('freeandnil(' + X) or AStmt.Contains(X + ':=');
end;

{ dataset-open-without-close: `Q.Open; S` -> `Q.Open; try S finally Q.Close end`
  for a LOCAL Q only (a shared field dataset is someone else's). The wrap ends
  before a statement that frees Q; an explicit Q.Close later in the list moves
  into the finally. }
function FixDatasetOpen(const AFinding: TLintFinding; ALines: TStringList): TArray<TTextEdit>;  // dl:ok too-many-exit-points@58b0 -- REVIEWED 2026-10-27: a guard-clause ladder; every Exit declines a shape the fix must not rewrite
var
  Fx      : TFx            ;
  S, CloseN: TTSNode       ;
  Kids    : TArray<TTSNode>;
  Idx, J  : Integer        ;
  Last    : Integer        ;
  Q, K    : string         ;
  M       : TMatch         ;
  E       : TTextEdit      ;
begin
  Result:= nil;
  if not OpenFx(AFinding.FilePath, ALines, Fx) then Exit;
  S:= Fx.StmtAt(AFinding.StartLine, AFinding.StartCol);
  if S.IsNull then Exit;
  M:= TRegEx.Match(StripSemi(Trim(Fx.Txt(S))), '^([A-Za-z_]\w*)\s*\.\s*Open\s*(\(\s*\))?$', [roIgnoreCase]);
  if not M.Success then Exit;
  Q:= M.Groups[1].Value;
  if LocalDecl(Fx, Ancestor(S, 'defProc'), Q).IsNull then Exit;
  Kids:= ListStmts(S.Parent);
  Idx:= IndexIn(Kids, S);
  CloseN:= Default(TTSNode);
  Last:= High(Kids);
  for J:= Idx + 1 to High(Kids) do
  begin
    K:= NormStmt(Fx.Txt(Kids[J]));
    if K = LowerCase(Q) + '.close' then
    begin
      CloseN:= Kids[J];
      Last:= J - 1;
      Break;
    end;
    if IsFreeOf(K, Q) then
    begin
      Last:= J - 1;
      Break;
    end;
    if MentionsFreeOf(K, Q) or K.Contains(LowerCase(Q) + '.close') then Exit;
  end;
  if Last <= Idx then Exit;
  if WrapBetween(Fx, S, Kids[Idx + 1], Kids[Last], CloseN, Q + '.Close;', E) then Result:= [E];  // dl:ok used-before-assignment@94fc -- REVIEWED 2026-10-27: FP: E is WrapBetween's out AEdit (a signature split over two lines)
end;

{ unprotected-object-free: `X := T.Create; S; X.Free` in one list ->
  `X := T.Create; try S finally X.Free end` }
function FixUnprotectedFree(const AFinding: TLintFinding; ALines: TStringList): TArray<TTextEdit>;
var
  Fx      : TFx            ;
  S, A    : TTSNode        ;
  Kids    : TArray<TTSNode>;
  Idx, J  : Integer        ;
  Open, K : Integer        ;
  X, Key  : string         ;
  M       : TMatch         ;
  E       : TTextEdit      ;
begin
  Result:= nil;
  if not OpenFx(AFinding.FilePath, ALines, Fx) then Exit;
  S:= Fx.StmtAt(AFinding.StartLine, AFinding.StartCol);
  if S.IsNull then Exit;
  Key:= NormStmt(Fx.Txt(S));
  M:= TRegEx.Match(Key, '^(.+)\.(free|disposeof)$');
  if M.Success then X:= M.Groups[1].Value
  else
  begin
    M:= TRegEx.Match(Key, '^freeandnil\((.+)\)$');
    if not M.Success then Exit;
    X:= M.Groups[1].Value;
  end;
  Kids:= ListStmts(S.Parent);
  Idx:= IndexIn(Kids, S);
  Open:= -1;
  for J:= Idx - 1 downto 0 do
  begin
    A:= AssignOf(Kids[J]);
    if (not A.IsNull) and (NormStmt(Fx.Txt(A.ChildByField('lhs'))) = X) then
    begin
      if TRegEx.IsMatch(Fx.Txt(A.ChildByField('rhs')), '\.\s*Create\b', [roIgnoreCase]) then Open:= J;
      Break;
    end;
  end;
  if (Open < 0) or (Open = Idx - 1) then Exit;
  for K:= Open + 1 to Idx - 1 do
    if MentionsFreeOf(NormStmt(Fx.Txt(Kids[K])), X) then Exit;
  if WrapBetween(Fx, Kids[Open], Kids[Open + 1], Kids[Idx - 1], S, WithSemi(Fx.Txt(S)), E) then Result:= [E];  // dl:ok used-before-assignment@076b -- REVIEWED 2026-10-27: FP: E is WrapBetween's out AEdit (a signature split over two lines)
end;

{ create-inside-try: move `X := T.Create(..)`, the first statement of a try
  whose finally ONLY frees X, above the try. A finally that frees more stays:
  a failed Create would then leak what the finally also releases. }
function FixCreateInsideTry(const AFinding: TLintFinding; ALines: TStringList): TArray<TTextEdit>;  // dl:ok too-many-exit-points@ca3f -- REVIEWED 2026-10-27: a guard-clause ladder; every Exit declines a shape the fix must not rewrite
var
  Fx              : TFx            ;
  A, S, Sts, T    : TTSNode        ;
  KF, FinSts      : TTSNode        ;
  Kids, Fin       : TArray<TTSNode>;
begin
  Result:= nil;
  if not OpenFx(AFinding.FilePath, ALines, Fx) then Exit;
  A:= AncestorAt(Fx.NodeAt(AFinding.StartLine, AFinding.StartCol), 'assignment', AFinding.StartLine, AFinding.StartCol);
  if A.IsNull then Exit;
  S:= ListMember(A);
  Sts:= S.Parent;
  T:= Sts.Parent;
  if (Sts.NodeType <> 'statements') or (T.NodeType <> 'try') or (not SameNode(T.ChildByField('try'), Sts)) then Exit;
  Kids:= ListStmts(Sts);
  if (Length(Kids) = 0) or (not SameNode(Kids[0], S)) then Exit;
  KF:= ChildOfType(T, 'kFinally');
  if KF.IsNull then Exit;
  FinSts:= KF.NextNamedSibling;
  if FinSts.IsNull or (FinSts.NodeType <> 'statements') then Exit;
  Fin:= ListStmts(FinSts);
  if (Length(Fin) <> 1) or (not IsFreeOf(NormStmt(Fx.Txt(Fin[0])), NormStmt(Fx.Txt(A.ChildByField('lhs'))))) then Exit;
  if (not SameText(Trim(Fx.Line(Row(T))), 'try')) or (Row(S) <> Row(T) + 1) then Exit;
  if (Trim(Fx.Before(S)) <> '') or (Fx.Tail(S) not in [tkNone, tkSemi, tkSemiComment]) then Exit;
  if not Fx.Clean(Row(T), ERow(S)) then Exit;
  Result:= [ReplaceRows(Fx, Row(T), ERow(S), Reindent(Fx, Row(S), ERow(S), Fx.Indent(Row(T))) + [Fx.Line(Row(T))])];
end;

{ the FieldByName('lit') call shape the rule counts (DRagLint.Lint.Linter) }
function IsFieldByNameCall(const AFx: TFx; const N: TTSNode): Boolean;
var
  Ent: TTSNode;
begin
  Result:= False;
  if N.NodeType <> 'exprCall' then Exit;
  Ent:= N.ChildByField('entity');
  Result:= (not Ent.IsNull) and (Ent.NodeType = 'exprDot') and SameText(AFx.Txt(Ent.ChildByField('rhs')), 'FieldByName');
end;

procedure CollectFieldByName(const AFx: TFx; const N: TTSNode; var AOut: TArray<TTSNode>);
var
  I: Integer;
begin
  if N.IsNull then Exit;
  if IsFieldByNameCall(AFx, N) then AOut:= AOut + [N];
  for I:= 0 to N.NamedChildCount - 1 do CollectFieldByName(AFx, N.NamedChild(I), AOut);
end;

{ `L<Name>Field` for a field name, free in the routine and among the names
  already taken }
function FieldVarName(const AField, ARoutine: string; ATaken: TStrings): string;
var
  Base: string ;
  K   : Integer;
begin
  Base:= TRegEx.Replace(AField, '[^A-Za-z0-9_]', '');
  Base:= if (Base = '') or CharInSet(Base[1], ['0'..'9']) then 'LField'
    else 'L' + UpperCase(Base[1]) + Copy(Base, 2, MaxInt) + 'Field';
  Result:= Base;
  K:= 1;
  while (ATaken.IndexOf(Result) >= 0) or WordIn(ARoutine, Result) do
  begin
    Inc(K);
    Result:= Base + IntToStr(K);
  end;
  ATaken.Add(Result);
end;

{ field-by-name-in-loop: hoist every `Q.FieldByName('x')` of the loop the rule
  reports (the OUTERMOST while / for / repeat) into `var LXField := ...;`
  above it. All or nothing: the rule reports the loop once, so a partial
  hoist would leave the finding. Declines when a dataset is reopened, closed,
  freed or reassigned in the loop (its TField objects may be recreated). }
function FixFieldByNameInLoop(const AFinding: TLintFinding; ALines: TStringList): TArray<TTextEdit>;  // dl:ok too-many-exit-points@3609 -- REVIEWED 2026-10-27: a guard-clause ladder; every Exit declines a shape the fix must not rewrite
var
  Fx         : TFx            ;
  N, Loop, P : TTSNode        ;
  DefProc    : TTSNode        ;
  Calls      : TArray<TTSNode>;
  C, Args    : TTSNode        ;
  Keys, Taken: TStringList    ;
  Decls, Rows: TArray<string> ;
  I, R       : Integer        ;
  QT, Lit    : string         ;
  Key, Nm    : string         ;
  Body, Rx   : string         ;
  NameOf     : TArray<string> ;
begin
  Result:= nil;
  if not OpenFx(AFinding.FilePath, ALines, Fx) then Exit;
  N:= Fx.NodeAt(AFinding.StartLine, AFinding.StartCol);
  Loop:= Default(TTSNode);
  P:= N;
  while (not P.IsNull) and (P.NodeType <> 'defProc') and (P.NodeType <> 'lambda') do
  begin
    if MatchStr(P.NodeType, ['while', 'for', 'repeat']) then Loop:= P;
    P:= P.Parent;
  end;
  DefProc:= P;
  if Loop.IsNull or DefProc.IsNull or (not IsList(ListMember(Loop).Parent)) then Exit;
  if (Trim(Fx.Before(Loop)) <> '') or (not Fx.Clean(Row(Loop), ERow(Loop))) then Exit;
  Calls:= nil;
  CollectFieldByName(Fx, Loop, Calls);
  if Length(Calls) = 0 then Exit;
  Body:= Fx.Txt(Loop);
  Keys := TStringList.Create;
  Taken:= TStringList.Create;
  try
    Taken.CaseSensitive:= False;
    Decls := nil;
    NameOf:= nil;
    for C in Calls do
    begin
      QT:= Fx.Txt(C.ChildByField('entity').ChildByField('lhs'));
      Args:= C.ChildByField('args');
      if (Row(C) <> ERow(C)) or (not IsSimplePath(QT)) then Exit;
      if Args.IsNull or (Args.NamedChildCount <> 1) or (Args.NamedChild(0).NodeType <> 'literalString') then Exit;
      Rx:= '(?<![\w.])' + TRegEx.Escape(QT);
      if TRegEx.IsMatch(Body, Rx + '\s*:=', [roIgnoreCase])
         or TRegEx.IsMatch(Body, Rx + '\s*\.\s*(Open|Close|Active|Free|DisposeOf|Destroy|Refresh|Requery|SQL|Fields|FieldDefs)\b', [roIgnoreCase])
         or TRegEx.IsMatch(Body, 'FreeAndNil\s*\(\s*' + TRegEx.Escape(QT) + '\s*\)', [roIgnoreCase]) then Exit;
      Lit:= Fx.Txt(Args.NamedChild(0));
      Key:= LowerCase(QT + '|' + Lit);
      I:= Keys.IndexOf(Key);
      if I < 0 then
      begin
        Nm:= FieldVarName(Copy(Lit, 2, Length(Lit) - 2), Fx.Txt(DefProc), Taken);
        Keys.Add(Key);
        Decls:= Decls + [Fx.Indent(Row(Loop)) + 'var ' + Nm + ' := ' + Fx.Txt(C) + ';'];
      end
      else Nm:= Taken[I];
      NameOf:= NameOf + [Nm];
    end;
    Rows:= nil;
    for R:= Row(Loop) to ERow(Loop) do Rows:= Rows + [Fx.Line(R)];
    for I:= High(Calls) downto 0 do
    begin
      C:= Calls[I];
      R:= Row(C) - Row(Loop);
      Rows[R]:= Copy(Rows[R], 1, Col(C)) + NameOf[I] + Copy(Rows[R], ECol(C) + 1, MaxInt);
    end;
  finally
    Keys.Free;
    Taken.Free;
  end;
  Result:= [ReplaceRows(Fx, Row(Loop), ERow(Loop), Decls + Rows)];
end;

{ is AName a `const` parameter of ADefProc? }
function IsConstParam(const AFx: TFx; const ADefProc: TTSNode; const AName: string): Boolean;
var
  Args, A: TTSNode;
  I      : Integer;
begin
  Result:= False;
  Args:= ADefProc.ChildByField('header').ChildByField('args');
  if Args.IsNull then Exit;
  for I:= 0 to Args.NamedChildCount - 1 do
  begin
    A:= Args.NamedChild(I);
    if (A.NodeType = 'declArg') and (not ChildOfType(A, 'kConst').IsNull)
       and SameText(AFx.Txt(A.ChildByField('name')), AName) then Exit(True);
  end;
end;

{ index-loop-to-for-in, the header: `for I := 0 to High(A) | Length(A) - 1 |
  L.Count - 1 do` (not downto). AArrForm is False for the Count form. }
function IndexLoopHeader(const AFx: TFx; const N: TTSNode; out AVar: TTSNode; out AInline: Boolean;
  out AColl: string; out AArrForm: Boolean): Boolean;
var
  St, EndN, L: TTSNode;
begin
  AColl   := '';
  AArrForm:= True;
  St      := N.ChildByField('start');
  EndN    := N.ChildByField('end');
  AVar    := St.ChildByField('lhs');
  AInline := AVar.NodeType = 'varAssignDef';
  if AInline then AVar:= ChildOfType(AVar, 'identifier');
  Result:= ChildOfType(N, 'kDownto').IsNull and (not EndN.IsNull) and (AFx.Txt(St.ChildByField('rhs')) = '0')
    and (not AVar.IsNull) and (AVar.NodeType = 'identifier');
  if not Result then Exit;
  if (EndN.NodeType = 'exprCall') and SameText(AFx.Txt(EndN.ChildByField('entity')), 'High') then
    AColl:= AFx.Txt(EndN.ChildByField('args')).Trim(['(', ')', ' '])
  else if (EndN.NodeType = 'exprBinary') and (EndN.ChildByField('operator').NodeType = 'kSub')
          and (AFx.Txt(EndN.ChildByField('rhs')) = '1') then
  begin
    L:= EndN.ChildByField('lhs');
    if (L.NodeType = 'exprCall') and SameText(AFx.Txt(L.ChildByField('entity')), 'Length') then
      AColl:= AFx.Txt(L.ChildByField('args')).Trim(['(', ')', ' '])
    else if (L.NodeType = 'exprDot') and SameText(AFx.Txt(L.ChildByField('rhs')), 'Count') then
    begin
      AColl   := AFx.Txt(L.ChildByField('lhs'));
      AArrForm:= False;
    end;
  end;
  Result:= IsSimplePath(AColl);
end;

{ index-loop-to-for-in, one mention O of the loop variable: the `C[I]` /
  `C.Items[I]` read it sits in, or False when it is anything else or a read
  that may be a write (an assignment target, an element field, @, or -- when
  not AAllowArg -- a call argument that may be a var parameter) }
function ElementRead(const AFx: TFx; const O: TTSNode; const AColl: string; AAllowArg: Boolean; out ASub: TTSNode): Boolean;
var
  PA, Ent, P: TTSNode;
begin
  PA  := O.Parent;
  ASub:= PA.Parent;
  Result:= (PA.NodeType = 'exprArgs') and (PA.NamedChildCount = 1) and (ASub.NodeType = 'exprSubscript')
    and SameNode(ASub.ChildByField('args'), PA) and (Row(ASub) = ERow(ASub));
  if not Result then Exit;
  Ent:= ASub.ChildByField('entity');
  Result:= SameText(AFx.Txt(Ent), AColl)
    or ((Ent.NodeType = 'exprDot') and SameText(AFx.Txt(Ent.ChildByField('lhs')), AColl)
        and SameText(AFx.Txt(Ent.ChildByField('rhs')), 'Items'));
  if not Result then Exit;
  P:= ASub.Parent;
  Result:= not ((((P.NodeType = 'assignment') or (P.NodeType = 'exprDot')) and SameNode(P.ChildByField('lhs'), ASub))  // dl:ok boolean-expression-complexity@27f9 -- REVIEWED 2026-10-27: the four may-be-a-write shapes of ONE element read, kept as one test
                or (P.NodeType = 'exprUnary')
                or ((P.NodeType = 'exprArgs') and (P.Parent.NodeType = 'exprCall') and not AAllowArg));
end;

{ index-loop-to-for-in: every element read of the body, or False when the
  loop variable or the collection is used any other way }
function ElementReads(const AFx: TFx; const ABody, AVar: TTSNode; const AColl: string; AAllowArg: Boolean;
  out ASubs: TArray<TTSNode>): Boolean;
var
  Occ    : TArray<TTSNode>;
  O, Sub : TTSNode        ;
begin
  ASubs:= nil;
  Occ  := nil;
  CollectIdents(AFx, ABody, AFx.Txt(AVar), Occ);
  for O in Occ do
  begin
    if not ElementRead(AFx, O, AColl, AAllowArg, Sub) then Exit(False);
    ASubs:= ASubs + [Sub];
  end;
  Result:= (Length(ASubs) > 0)
    and (TRegEx.Matches(AFx.Txt(ABody), '(?<![\w.])' + TRegEx.Escape(AColl) + '(?![\w])', [roIgnoreCase]).Count = Length(ASubs));
end;

{ index-loop-to-for-in: the edits that drop a routine-local loop variable the
  rewritten loop ALoop was the only user of }
function LoopVarDeclEdits(const AFx: TFx; const ADefProc, ALoop: TTSNode; const AVarName: string): TArray<TTextEdit>;
var
  Decl, O: TTSNode        ;
  Occ    : TArray<TTSNode>;
  Fixed  : Integer        ;
begin
  Result:= nil;
  Decl:= LocalDecl(AFx, ADefProc, AVarName);
  if Decl.IsNull then Exit;
  Occ:= nil;
  CollectIdents(AFx, ADefProc, AVarName, Occ);
  for O in Occ do
    if (not SameNode(O, Decl)) and ((O.StartByte < ALoop.StartByte) or (O.EndByte > ALoop.EndByte)) then Exit;
  Fixed:= 0;
  Result:= TAstChecker.BuildUnusedLocalFixEdits(AFx.Path, [UnusedLocalAt(AFx, Decl)], Fixed);
end;

{ index-loop-to-for-in: `for I := 0 to High(A) | Length(A) - 1 | L.Count - 1 do`
  whose body reads I ONLY as `A[I]` / `L.Items[I]` -> `for var LItem in A do`
  with every such read replaced by LItem. A read that may be a write declines
  (see ElementRead; a call argument is allowed for a class collection and a
  const array parameter only), as do a string (1-based) or unknown-typed
  array, nested loops and a routine that already has an LItem. A
  routine-local I used nowhere else is removed through the unused-local fixer. }
function FixIndexLoopToForIn(const AFinding: TLintFinding; ALines: TStringList): TArray<TTextEdit>;  // dl:ok too-many-exit-points@e687 -- REVIEWED 2026-10-27: a guard-clause ladder; every Exit declines a shape the fix must not rewrite
var
  Fx              : TFx            ;
  N, Body, V      : TTSNode        ;
  DefProc, KF, KD : TTSNode        ;
  Subs            : TArray<TTSNode>;
  Coll            : string         ;
  ArrForm, IsInl  : Boolean        ;
  AllowArg        : Boolean        ;
  Rows            : TArray<string> ;
  I, R            : Integer        ;
begin
  Result:= nil;
  if not OpenFx(AFinding.FilePath, ALines, Fx) then Exit;
  N:= AncestorAt(Fx.NodeAt(AFinding.StartLine, AFinding.StartCol), 'for', AFinding.StartLine, AFinding.StartCol);
  if N.IsNull or (not IndexLoopHeader(Fx, N, V, IsInl, Coll, ArrForm)) then Exit;
  Body   := N.ChildByField('body');
  DefProc:= Ancestor(N, 'defProc');
  if Body.IsNull or DefProc.IsNull or WordIn(Fx.Txt(DefProc), 'LItem') then Exit;
  if HasDescendant(Body, 'for') or HasDescendant(Body, 'foreach') then Exit;
  AllowArg:= not ArrForm;
  if ArrForm then
  begin
    if not LowerCase(DeclTypeOf(Fx.Path, Row(N) + 1, Coll)).Contains('array') then Exit;
    AllowArg:= IsConstParam(Fx, DefProc, Coll);
  end;
  if not ElementReads(Fx, Body, V, Coll, AllowArg, Subs) then Exit;
  KF:= ChildOfType(N, 'kFor');
  KD:= ChildOfType(N, 'kDo');
  if KF.IsNull or KD.IsNull or (Row(KF) <> Row(KD)) or (not Fx.Clean(Row(N), ERow(N))) then Exit;
  Rows:= nil;
  for R:= Row(N) to ERow(N) do Rows:= Rows + [Fx.Line(R)];
  for I:= High(Subs) downto 0 do
  begin
    R:= Row(Subs[I]) - Row(N);
    Rows[R]:= Copy(Rows[R], 1, Col(Subs[I])) + 'LItem' + Copy(Rows[R], ECol(Subs[I]) + 1, MaxInt);
  end;
  Rows[0]:= Copy(Rows[0], 1, Col(KF)) + 'for var LItem in ' + Coll + ' do' + Copy(Rows[0], ECol(KD) + 1, MaxInt);
  Result:= [ReplaceRows(Fx, Row(N), ERow(N), Rows)];
  if not IsInl then Result:= Result + LoopVarDeclEdits(Fx, DefProc, N, Fx.Txt(V));
end;

initialization
  RegisterFixer('code-after-exit', FixCodeAfterExit);
  RegisterFixer('redundant-continue-exit', FixRedundantContinueExit);
  RegisterFixer('else-after-exit', FixElseAfterExit);
  { identical-then-else: registered by lane G9 (DRagLint.Diagnostics.ParityExtChecks),
    which hands its declined single-statement shape to FixIdenticalAssignmentBranches }
  RegisterFixer('case-with-too-few-branches', FixCaseFewBranches);
  RegisterFixer('overwrite-before-read', FixOverwriteBeforeRead);
  RegisterFileFixer('write-only-local', FixWriteOnlyLocals);
  RegisterFixer('criticalsection-not-released', FixCriticalSection);
  RegisterFixer('dataset-open-without-close', FixDatasetOpen);
  RegisterFixer('unprotected-object-free', FixUnprotectedFree);
  RegisterFixer('create-inside-try', FixCreateInsideTry);
  RegisterFixer('index-loop-to-for-in', FixIndexLoopToForIn);
  { risky: behaviour-CHANGING fixes, applied and tagged risky:true }
  RegisterFixer('bare-except', FixBareExcept, True);
  RegisterFixer('duplicate-exception-handler', FixDuplicateHandler, True);
  RegisterFixer('exception-constructed-but-not-raised', FixExceptionNotRaised, True);
  RegisterFixer('field-by-name-in-loop', FixFieldByNameInLoop, True);
  RegisterFixer('swap-without-temp', FixSwapWithoutTemp, True);

end.
