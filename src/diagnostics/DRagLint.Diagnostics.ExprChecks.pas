unit DRagLint.Diagnostics.ExprChecks;

{ Clippy-parity wave (plan 2026-10-27-clippy-rules-plan.md), lane L6.
  Pure AST rules (no symbol store needed); AStore is accepted for the uniform
  checker signature and ignored.
  Rules:
    bad-bit-mask            : (X and M) = V with V holding a bit outside M (never true),
                              (X or M) = V with M holding a bit outside V (never true);
                              both literals, either side of the comparison, = and <>.
    invalid-regex-literal   : TRegEx.Create / IsMatch / Match / Matches / Replace / Split
                              given a PURE string-literal pattern that System.RegularExpressions
                              refuses to compile (checked by compiling it).
    double-dictionary-lookup: if D.ContainsKey(K) [and ...] then ... D[K] / D.Items[K] read ...
                              -- two hash lookups, TryGetValue does one. Only reads count;
                              key expressions containing a call are skipped.
    case-same-branches      : two arms of one case statement with the same non-empty body
                              (whitespace-insensitive); reported on the later arm.
    misleading-indentation  : if / while / for / foreach / with whose body is ONE simple
                              statement, followed by a statement on its own line indented
                              deeper than the construct: it reads as guarded but is not.
                              Indentation is compared tabs-vs-tabs or spaces-vs-spaces; MIXED indentation is skipped. }

interface

uses
  DRagLint.Core.Model
  , DRagLint.Core.Interfaces
  , DRagLint.Lint.Config
  ;

type
  /// <summary>Checker for the bad-bit-mask, invalid-regex-literal, double-dictionary-lookup, case-same-branches and misleading-indentation rules.</summary>
  /// <remarks>
  /// Stateless; thread-safe. Called from DoLint and DoLintAll behind
  /// LintRuleWants(rule, LINT_GATE_EXPR). Parses through TAstParseCache, so the
  /// preprocessed (dead-branch-blanked) text is what is analysed.
  /// </remarks>
  TExprChecker = class
  public
    /// <summary>Runs the ExprChecks rules against one source file.</summary>
    /// <param name="AFile">Absolute path to the .pas/.inc source file.</param>
    /// <param name="ACfg">Effective lint configuration (unused by these rules; no thresholds).</param>
    /// <param name="AStore">Optional symbol store; nil when the run has no index. Not consulted.</param>
    /// <param name="AFileId">File id within AStore (ignored when AStore is nil).</param>
    /// <returns>One finding per violation; empty when clean or unparsable. The CLI filters by --rule.</returns>
    class function Check(const AFile: string; const ACfg: TLintConfig;
      const AStore: ISymbolStore; AFileId: Integer): TArray<TLintFinding>; static;
  end;

implementation

uses
  System.SysUtils
  , System.Classes
  , System.Generics.Collections
  , System.RegularExpressions
  , TreeSitter
  , DRagLint.Diagnostics.ParseCache
  ;

const
  SIMPLE_BODY_BLOCKERS = 'block;if;ifElse;while;for;foreach;with;repeat;case;try;';
  BYTE_LF              = 10;
  BYTE_SPACE           = 32;
  BYTE_TAB             = 9;
  FOLLOW_STATEMENTS    = 'assignment;statement;if;ifElse;while;for;foreach;repeat;case;try;with;raise;block;';

function NodeText(const N: TTSNode; const ASrc: TBytes): string;
var
  S, E: Integer;
begin
  Result:= '';
  if N.IsNull then Exit;
  S:= Integer(N.StartByte);
  E:= Integer(N.EndByte);
  if (E <= S) or (S < 0) or (E > Length(ASrc)) then Exit;
  Result:= TEncoding.UTF8.GetString(ASrc, S, E - S);
end;

{ Collapse every whitespace run to one blank and trim. }
function Squash(const S: string): string;
var
  I: Integer;
  B: TStringBuilder;
  InBlank: Boolean;
begin
  B:= TStringBuilder.Create;
  try
    InBlank:= True;
    for I:= 1 to Length(S) do
      if CharInSet(S[I], [' ', #9, #10, #13]) then
      begin
        if not InBlank then B.Append(' ');
        InBlank:= True;
      end
      else
      begin
        B.Append(S[I]);
        InBlank:= False;
      end;
    Result:= Trim(B.ToString);
  finally
    B.Free;
  end;
end;

{ First named child that is not a comment; a null node when there is none. }
function FirstReal(const N: TTSNode): TTSNode;
var
  I: Integer;
begin
  Result:= Default(TTSNode);
  for I:= 0 to N.NamedChildCount - 1 do
    if N.NamedChild(I).NodeType <> 'comment' then
      Exit(N.NamedChild(I));
end;

{ Strips redundant parentheses: (((E))) -> E. }
function Unparen(const N: TTSNode): TTSNode;
begin
  Result:= N;
  while (not Result.IsNull) and (Result.NodeType = 'exprParens') and (Result.NamedChildCount >= 1) do
    Result:= FirstReal(Result);
end;

{ Integer value of a literalNumber (decimal, $hex, %binary). False when it is not a plain integer. }
function LiteralValue(const N: TTSNode; const ASrc: TBytes; out AValue: Int64): Boolean;
var
  T: string;
begin
  Result:= False;
  AValue:= 0;
  if N.IsNull or (N.NodeType <> 'literalNumber') then Exit;
  T:= Trim(NodeText(N, ASrc));
  if T = '' then Exit;
  Result:= if T[1] = '%' then TryStrToInt64('0b' + Copy(T, 2, MaxInt), AValue) else TryStrToInt64(T, AValue);
  if (not Result) and (T[1] = '%') then
  begin
    // TryStrToInt64 has no 0b prefix on every RTL; parse by hand.
    var I: Integer;
    AValue:= 0;
    Result:= Length(T) > 1;
    for I:= 2 to Length(T) do
      if CharInSet(T[I], ['0', '1']) then AValue:= AValue * 2 + (Ord(T[I]) - Ord('0'))
      else Result:= False;
  end;
end;

{ Decodes a Pascal string literal that is ONE quoted run ('..' with '' escapes).
  False for #nn pieces, concatenations or anything else that is not a pure literal. }
function PureStringLiteral(const N: TTSNode; const ASrc: TBytes; out AText: string): Boolean;
var
  T: string;
  I: Integer;
  B: TStringBuilder;
begin
  Result:= False;
  AText:= '';
  if N.IsNull or (N.NodeType <> 'literalString') then Exit;
  T:= Trim(NodeText(N, ASrc));
  if (Length(T) < 2) or (T[1] <> '''') or (T[Length(T)] <> '''') then Exit;
  B:= TStringBuilder.Create;
  try
    I:= 2;
    while I < Length(T) do
    begin
      if T[I] = '''' then
      begin
        if (I + 1 < Length(T)) and (T[I + 1] = '''') then
        begin
          B.Append('''');
          Inc(I, 2);
          Continue;
        end;
        Exit;
      end;
      B.Append(T[I]);
      Inc(I);
    end;
    AText:= B.ToString;
    Result:= True;
  finally
    B.Free;
  end;
end;

{ Text between the outer brackets/parens of an exprArgs node, squashed and lower-cased. '' when absent. }
function ArgsKey(const AArgs: TTSNode; const ASrc: TBytes): string;
begin
  Result:= Squash(NodeText(AArgs, ASrc));
  if (Length(Result) >= 2) and CharInSet(Result[1], ['(', '[']) then
    Result:= Trim(Copy(Result, 2, Length(Result) - 2));
  Result:= LowerCase(Result);
end;

{ Indentation of the line holding AByte: the blank count, with AKind = space or tab. -1 when AByte is
  not the first non-blank on its line, or the run MIXES tabs and spaces. }
function LeadingIndent(const ASrc: TBytes; AByte: Integer; out AKind: Char): Integer;
var
  LineStart, P: Integer;
begin
  LineStart:= AByte;
  while (LineStart > 0) and (ASrc[LineStart - 1] <> BYTE_LF) do Dec(LineStart);
  Result:= 0;
  AKind:= ' ';
  P:= LineStart;
  while (P < AByte) and (Result >= 0) do
  begin
    if (ASrc[P] <> BYTE_SPACE) and (ASrc[P] <> BYTE_TAB) then Result:= -1
    else
    begin
      if Result = 0 then AKind:= Chr(ASrc[P]);
      if Chr(ASrc[P]) = AKind then Inc(Result) else Result:= -1;
    end;
    Inc(P);
  end;
end;

{ True when the indents are comparable (same kind, or one is empty) and AInner is deeper than AOuter. }
function IndentDeeper(AOuter: Integer; AOuterKind: Char; AInner: Integer; AInnerKind: Char): Boolean;
begin
  Result:= (AOuter >= 0) and (AInner > AOuter)
    and ((AOuterKind = AInnerKind) or (AOuter = 0));
end;

{ Operands of a constant bit-mask comparison: ((X and|or Mask) =|<> V) with both literals. }
function BitMaskPieces(const N: TTSNode; const ASrc: TBytes; out AV, AM: Int64; out AIsAnd: Boolean): Boolean;
var
  Op, L, R, Inner, Inside, A, B: TTSNode;
  OpTxt: string;
begin
  Result:= False;
  AV:= 0;
  AM:= 0;
  AIsAnd:= False;
  Op:= N.ChildByField('operator');
  OpTxt:= Trim(NodeText(Op, ASrc));
  L:= Unparen(N.ChildByField('lhs'));
  R:= Unparen(N.ChildByField('rhs'));
  if (not Op.IsNull) and ((OpTxt = '=') or (OpTxt = '<>')) and (not L.IsNull) and (not R.IsNull) then
  begin
    if L.NodeType = 'literalNumber' then
    begin
      Inner:= R;
      Inside:= L;
    end
    else
    begin
      Inner:= L;
      Inside:= R;
    end;
    Op:= Inner.ChildByField('operator');
    if (Inner.NodeType = 'exprBinary') and LiteralValue(Inside, ASrc, AV) and (not Op.IsNull) then
    begin
      OpTxt:= LowerCase(Trim(NodeText(Op, ASrc)));
      A:= Unparen(Inner.ChildByField('lhs'));
      B:= Unparen(Inner.ChildByField('rhs'));
      AIsAnd:= OpTxt = 'and';
      Result:= ((OpTxt = 'and') or (OpTxt = 'or'))
        and (LiteralValue(A, ASrc, AM) or LiteralValue(B, ASrc, AM));
    end;
  end;
end;

class function TExprChecker.Check(const AFile: string; const ACfg: TLintConfig;  // dl:ok unused-parameter@ae41 -- REVIEWED 2026-10-27: gate-fixed checker signature shared by all LINT_GATE_* checkers; these rules need no config
  const AStore: ISymbolStore; AFileId: Integer): TArray<TLintFinding>;  // dl:ok unused-parameter@9a67 -- REVIEWED 2026-10-27: gate-fixed checker signature; pure-AST rules need no symbol store
var
  PF      : TParsedFile;
  Src     : TBytes;
  Findings: TList<TLintFinding>;

  procedure EmitAt(const ANode: TTSNode; const ARuleId, AMessage, ASeverity: string);
  var
    P: TTSPoint;
    F: TLintFinding;
  begin
    P:= ANode.StartPoint;
    F:= Default(TLintFinding);
    F.RuleId   := ARuleId;
    F.Severity := ASeverity;
    F.Message  := AMessage;
    F.FilePath := AFile;
    F.StartLine:= Integer(P.Row) + 1;
    F.StartCol := Integer(P.Column) + 1;
    F.EndLine  := Integer(ANode.EndPoint.Row) + 1;
    F.EndCol   := Integer(ANode.EndPoint.Column) + 1;
    Findings.Add(F);
  end;

  { ---- bad-bit-mask ---- }
  procedure CheckBitMask(const N: TTSNode);
  var
    V, M: Int64;
    IsAnd, Bad: Boolean;
  begin
    if not BitMaskPieces(N, Src, V, M, IsAnd) then Exit;
    Bad:= if IsAnd then (V and (not M)) <> 0 else (M and (not V)) <> 0;
    if Bad then
      EmitAt(N, 'bad-bit-mask',
        'Bit-mask comparison is constant: the compared value has bits the mask can never produce',
        'warning');
  end;

  { ---- invalid-regex-literal ---- }
  procedure CheckRegex(const N: TTSNode);
  var
    Ent, Args, Arg: TTSNode;
    EntTxt, Pat: string;
    PatIdx, I, K: Integer;
    Bad: Boolean;
  begin
    Ent:= N.ChildByField('entity');
    Args:= N.ChildByField('args');
    if Ent.IsNull or Args.IsNull then Exit;
    EntTxt:= LowerCase(StringReplace(Squash(NodeText(Ent, Src)), ' ', '', [rfReplaceAll]));
    if EntTxt.EndsWith('tregex.create') then PatIdx:= 0
    else if EntTxt.EndsWith('tregex.ismatch') or EntTxt.EndsWith('tregex.match')
         or EntTxt.EndsWith('tregex.matches') or EntTxt.EndsWith('tregex.replace')
         or EntTxt.EndsWith('tregex.split') then PatIdx:= 1
    else Exit;
    K:= 0;
    Arg:= Default(TTSNode);
    for I:= 0 to Args.NamedChildCount - 1 do
      if Args.NamedChild(I).NodeType <> 'comment' then
      begin
        if K = PatIdx then
        begin
          Arg:= Args.NamedChild(I);
          Break;
        end;
        Inc(K);
      end;
    if (not PureStringLiteral(Arg, Src, Pat)) or (Pat = '') then Exit;
    Bad:= False;
    try
      // TRegEx.Create is lazy; the pattern compiles on first use, so force it.
      TRegEx.Create(Pat).IsMatch('');
    except
      on Exception do Bad:= True;
    end;
    if Bad then
      EmitAt(Arg, 'invalid-regex-literal',
        'Regular-expression literal does not compile; the call raises at run time', 'warning');
  end;

  { ---- double-dictionary-lookup ---- }
  { Collect the ContainsKey calls that must hold for ACond to be true (the condition itself,
    or any operand of an `and` chain). }
  procedure CollectContainsKey(const ACond: TTSNode; const AOut: TList<TTSNode>);
  var
    C, Op: TTSNode;
  begin
    C:= Unparen(ACond);
    if C.IsNull then Exit;
    if C.NodeType = 'exprCall' then
      AOut.Add(C)
    else if C.NodeType = 'exprBinary' then
    begin
      Op:= C.ChildByField('operator');
      if (not Op.IsNull) and SameText(Trim(NodeText(Op, Src)), 'and') then
      begin
        CollectContainsKey(C.ChildByField('lhs'), AOut);
        CollectContainsKey(C.ChildByField('rhs'), AOut);
      end;
    end;
  end;

  function ReadsSubscript(const ABody: TTSNode; const ARecv, AKey: string): Boolean;
  var
    I: Integer;
    Ent, Par, Lhs: TTSNode;
    EntTxt: string;
  begin
    Result:= False;
    if ABody.IsNull then Exit;
    if ABody.NodeType = 'exprSubscript' then
    begin
      Ent:= ABody.ChildByField('entity');
      EntTxt:= LowerCase(Squash(NodeText(Ent, Src)));
      if ((EntTxt = ARecv) or (EntTxt = ARecv + '.items')) and (ArgsKey(ABody.ChildByField('args'), Src) = AKey) then
      begin
        Par:= ABody.Parent;
        Lhs:= Default(TTSNode);
        if (not Par.IsNull) and (Par.NodeType = 'assignment') then Lhs:= Par.ChildByField('lhs');
        // a write (the node IS the assignment target) is not a read
        if Lhs.IsNull or (Lhs.StartByte <> ABody.StartByte) or (Lhs.EndByte <> ABody.EndByte) then
          Exit(True);
      end;
    end;
    for I:= 0 to ABody.NamedChildCount - 1 do
      if ReadsSubscript(ABody.NamedChild(I), ARecv, AKey) then Exit(True);
  end;

  procedure CheckDoubleLookup(const N: TTSNode);
  var
    Calls: TList<TTSNode>;
    Call, Ent, Args, ThenN: TTSNode;
    EntTxt, Recv, Key: string;
    I: Integer;
  begin
    ThenN:= N.ChildByField('then');
    if ThenN.IsNull then Exit;
    Calls:= TList<TTSNode>.Create;
    try
      CollectContainsKey(N.ChildByField('condition'), Calls);
      for I:= 0 to Calls.Count - 1 do
      begin
        Call:= Calls[I];
        Ent:= Call.ChildByField('entity');
        Args:= Call.ChildByField('args');
        if Ent.IsNull or Args.IsNull then Continue;
        EntTxt:= LowerCase(Squash(NodeText(Ent, Src)));
        if not EntTxt.EndsWith('.containskey') then Continue;
        Recv:= Trim(Copy(EntTxt, 1, Length(EntTxt) - Length('.containskey')));
        Key := ArgsKey(Args, Src);
        if (Recv = '') or (Key = '') or (Key.Contains('(')) or (Key.Contains(',')) then Continue;
        if ReadsSubscript(ThenN, Recv, Key) then
        begin
          EmitAt(N, 'double-dictionary-lookup',
            'ContainsKey followed by an indexed read looks the key up twice; use TryGetValue', 'info');
          Exit;
        end;
      end;
    finally
      Calls.Free;
    end;
  end;

  { ---- case-same-branches ---- }
  procedure CheckCase(const N: TTSNode);
  var
    I: Integer;
    Arm, Body: TTSNode;
    Txt: string;
    Seen: TDictionary<string, Integer>;
    FirstLine: Integer;
  begin
    Seen:= TDictionary<string, Integer>.Create;
    try
      for I:= 0 to N.NamedChildCount - 1 do
      begin
        Arm:= N.NamedChild(I);
        if Arm.NodeType <> 'caseCase' then Continue;
        Body:= Arm.ChildByField('body');
        if Body.IsNull then Continue;
        Txt:= Squash(NodeText(Body, Src));
        while (Txt <> '') and (Txt[Length(Txt)] = ';') do Txt:= Trim(Copy(Txt, 1, Length(Txt) - 1));
        if Txt = '' then Continue;
        if Seen.TryGetValue(Txt, FirstLine) then
          EmitAt(Arm, 'case-same-branches',
            Format('Case branch has the same body as the branch at line %d; merge the labels', [FirstLine]),
            'info')
        else
          Seen.Add(Txt, Integer(Arm.StartPoint.Row) + 1);
      end;
    finally
      Seen.Free;
    end;
  end;

  { ---- misleading-indentation ---- }
  procedure CheckIndent(const AParent: TTSNode);
  var
    I, J, Indent, NextIndent: Integer;
    IKind, NKind: Char;
    Stmt, Body, Nxt: TTSNode;
    T: string;
  begin
    for I:= 0 to AParent.NamedChildCount - 1 do
    begin
      Stmt:= AParent.NamedChild(I);
      T:= Stmt.NodeType;
      if (T <> 'if') and (T <> 'while') and (T <> 'for') and (T <> 'foreach') and (T <> 'with') then Continue;
      if T = 'if' then Body:= Stmt.ChildByField('then') else Body:= Stmt.ChildByField('body');
      if Body.IsNull or (Pos(Body.NodeType + ';', SIMPLE_BODY_BLOCKERS) > 0) then Continue;
      Nxt:= Default(TTSNode);
      for J:= I + 1 to AParent.NamedChildCount - 1 do
        if AParent.NamedChild(J).NodeType <> 'comment' then
        begin
          Nxt:= AParent.NamedChild(J);
          Break;
        end;
      if Nxt.IsNull or (Pos(Nxt.NodeType + ';', FOLLOW_STATEMENTS) = 0) then Continue;
      if Nxt.StartPoint.Row <= Stmt.EndPoint.Row then Continue;
      Indent    := LeadingIndent(PF.RawSrc, Integer(Stmt.StartByte), IKind);
      NextIndent:= LeadingIndent(PF.RawSrc, Integer(Nxt.StartByte), NKind);
      if (Indent < 0) or (NextIndent < 0) then Continue;
      if IndentDeeper(Indent, IKind, NextIndent, NKind) then
        EmitAt(Nxt, 'misleading-indentation',
          Format('Statement is indented as if controlled by the %s at line %d, but it is not',
            [T, Integer(Stmt.StartPoint.Row) + 1]), 'warning');
    end;
  end;

  procedure Visit(const N: TTSNode);
  var
    I: Integer;
    T: string;
  begin
    T:= N.NodeType;
    if T = 'exprBinary' then CheckBitMask(N)
    else if T = 'exprCall' then CheckRegex(N)
    else if (T = 'if') or (T = 'ifElse') then CheckDoubleLookup(N)
    else if T = 'case' then CheckCase(N);
    CheckIndent(N);
    for I:= 0 to N.NamedChildCount - 1 do Visit(N.NamedChild(I));
  end;

begin
  Result:= nil;
  PF:= TAstParseCache.Get(AFile);
  if PF.Tree = nil then Exit;
  Src:= PF.Src;
  Findings:= TList<TLintFinding>.Create;
  try
    Visit(PF.Tree.RootNode);
    Result:= Findings.ToArray;
  finally
    Findings.Free;
  end;
end;

end.
