unit DRagLint.V154.EXPR.Support;

{ Wave v154 lane EXPR -- helpers of DRagLint.V154.EXPR (private to the lane).
    duplicate-logical-operand  (G-07)  the same Boolean operand twice in one and / or chain
    contradictory-condition    (G-07)  comparisons of one variable with literals that cannot all hold in an `and` chain
    warnings-off-not-restored  (G-27)  a WARNINGS OFF switch with no WARNINGS ON after it in the file (raw bytes)
    function-name-reads-itself (G-28)  a function that assigns its own name reads it back (a recursive call, not the value)
    boolean-comparison-precedence (G-29) `Flag and Other = False` parses as (Flag and Other) = False
    homoglyph-identifier       (G-38)  a Latin identifier with a Cyrillic / Greek look-alike letter in it (raw bytes)
  Every check is conservative: a shape the lane cannot prove stays silent. }

interface

uses
  System.SysUtils
  , DRagLint.Core.Model
  , DRagLint.V151.Api
  ;

const
  RULE_DUP_OPERAND = 'duplicate-logical-operand';
  RULE_CONTRADICTION = 'contradictory-condition';
  RULE_WARNINGS_OFF = 'warnings-off-not-restored';
  RULE_NAME_READS_ITSELF = 'function-name-reads-itself';
  RULE_BOOL_PRECEDENCE = 'boolean-comparison-precedence';
  RULE_HOMOGLYPH = 'homoglyph-identifier';

/// <summary>duplicate-logical-operand and contradictory-condition of one unit.</summary>
/// <param name="ACtx">The file; the rules it does not want are not run.</param>
/// <returns>Findings in document order per rule; nil when none or the file does not parse.</returns>
/// <remarks>An operand counts only when it is a comparison, a `not`, a Boolean RTL function or an and / or of those, and
/// everything in it is effect-free (no call outside a short list of pure RTL routines).</remarks>
function CheckLogicalChains(const ACtx: TV151FileCtx): TArray<TLintFinding>;

/// <summary>function-name-reads-itself of one unit.</summary>
/// <param name="ACtx">The file.</param>
/// <returns>One finding per read of the function name; nil when none.</returns>
/// <remarks>Only a function without parameters whose body also ASSIGNS its own name is judged: that is the
/// shape of an author who treats the name as the result variable. A read that is a call with parentheses, a
/// member of another object, an address-of or inside a nested routine / anonymous method is left alone.</remarks>
function CheckFunctionNameReads(const ACtx: TV151FileCtx): TArray<TLintFinding>;

/// <summary>boolean-comparison-precedence of one unit.</summary>
/// <param name="ACtx">The file.</param>
/// <returns>Findings; nil when none.</returns>
/// <remarks>Fires only when a Boolean literal proves the operands Boolean: `A and B = False`, `A = True and B`.
/// `Flags and 4 = 0` (bitwise) and any parenthesised form stay silent.</remarks>
function CheckBooleanPrecedence(const ACtx: TV151FileCtx): TArray<TLintFinding>;

/// <summary>warnings-off-not-restored of one file's raw text.</summary>
/// <param name="AFilePath">The .pas / .dpr the bytes come from.</param>
/// <param name="ABytes">The file as on disk.</param>
/// <returns>At most one finding per unrestored switch-off, at the directive; nil when none.</returns>
/// <remarks>Directives inside strings and comments do not count. A switch-off followed by nothing but the final
/// `end.` is harmless and not reported. Include files are never linted on their own, so they are not judged here.</remarks>
function CheckWarningsRestored(const AFilePath: string; const ABytes: TBytes): TArray<TLintFinding>;

/// <summary>homoglyph-identifier of one file's raw text.</summary>
/// <param name="AFilePath">The .pas / .dpr the bytes come from.</param>
/// <param name="ABytes">The file as on disk; only valid UTF-8 with at least one non-ASCII byte is judged.</param>
/// <returns>One finding per identifier occurrence; nil when none.</returns>
/// <remarks>An identifier counts when it holds ASCII letters AND at least one Cyrillic / Greek letter, and every
/// non-ASCII letter in it looks like a Latin letter. A name written in one script, and strings and comments, are left alone.</remarks>
function CheckHomoglyphs(const AFilePath: string; const ABytes: TBytes): TArray<TLintFinding>;

implementation

uses
  System.Classes
  , System.Types
  , System.Character
  , System.StrUtils
  , System.Math
  , System.Generics.Collections
  , System.RegularExpressions
  , TreeSitter
  , DRagLint.Diagnostics.ParseCache
  ;

const
  SEVERITY_WARNING = 'warning';
  SEVERITY_HINT = 'hint';
  UTF8_CODEPAGE = 65001;
  STRICT_DECODE = 8;     { MB_ERR_INVALID_CHARS }
  ASCII_LIMIT = 128;
  BOM_LEN = 3;
  BOM_BYTES: array[0..2] of Byte = ($EF, $BB, $BF);
  CMP_OPS: array[0..7] of string = ('kEq', 'kNeq', 'kLt', 'kLte', 'kGt', 'kGte', 'kIn', 'kIs');
  LOGIC_OPS: array[0..2] of string = ('kAnd', 'kOr', 'kXor');
  { effect-free routines an operand may call }
  PURE_CALLS: array[0..40] of string = ('assigned', 'odd', 'length', 'high', 'low', 'ord', 'chr', 'abs', 'sqr', 'sqrt', 'trim',
    'trimleft', 'trimright', 'uppercase', 'lowercase', 'pos', 'copy', 'sametext', 'samestr', 'ansisametext', 'ansisamestr',
    'startstext', 'startsstr', 'endstext', 'endsstr', 'containstext', 'containsstr', 'inrange', 'integer', 'int64', 'cardinal',
    'byte', 'word', 'boolean', 'string', 'char', 'widechar', 'double', 'single', 'extended', 'round');
  { Boolean-valued ones among them }
  BOOL_CALLS: array[0..12] of string = ('assigned', 'odd', 'sametext', 'samestr', 'ansisametext', 'ansisamestr', 'startstext',
    'startsstr', 'endstext', 'endsstr', 'containstext', 'containsstr', 'inrange');
  { non-ASCII letters that look like a Latin letter: Cyrillic then Greek }
  CONFUSABLES = #$0430#$0435#$043E#$0440#$0441#$0443#$0445#$0456#$0458#$0455#$04BB#$0501#$051B#$051D +
    #$0410#$0412#$0415#$041A#$041C#$041D#$041E#$0420#$0421#$0422#$0425#$0406#$0408#$0405#$04AE#$04C0 +
    #$03B1#$03BF#$03BD#$03C1#$03C5#$03B9#$03BA#$03C7 +
    #$0391#$0392#$0395#$0396#$0397#$0399#$039A#$039C#$039D#$039F#$03A1#$03A4#$03A5#$03A7;

{ ---- tree helpers ---- }

function SrcText(const ANode: TTSNode; const ASrc: TBytes): string;
var
  First, Last: Integer;
begin
  Result:= '';
  if ANode.IsNull then Exit;
  First:= Integer(ANode.StartByte);
  Last := Integer(ANode.EndByte);
  if (Last > First) and (Last <= Length(ASrc)) then Result:= TEncoding.UTF8.GetString(ASrc, First, Last - First);
end;

function Squash(const AText: string): string;
var
  Ch: Char;
  Text: TStringBuilder;
  InLiteral: Boolean;
begin
  Text:= TStringBuilder.Create;
  InLiteral:= False;
  try
    for Ch in AText do
    begin
      if Ch = '''' then InLiteral:= not InLiteral;
      if InLiteral then Text.Append(Ch)   { a character literal keeps its case: 'A' and 'a' differ }
      else if not Ch.IsWhiteSpace then Text.Append(Ch.ToLower);
    end;
    Result:= Text.ToString;
  finally
    Text.Free;
  end;
end;

function OpOf(const ANode: TTSNode): string;
var
  Op: TTSNode;
begin
  Op:= ANode.ChildByField('operator');
  Result:= if Op.IsNull then '' else Op.NodeType;
end;

function Unwrap(const ANode: TTSNode): TTSNode;
begin
  Result:= ANode;
  while (not Result.IsNull) and (Result.NodeType = 'exprParens') and (Result.NamedChildCount > 0) do Result:= Result.NamedChild(0);
end;

function SameNode(const A, B: TTSNode): Boolean;
begin
  Result:= (not A.IsNull) and (not B.IsNull) and (A.StartByte = B.StartByte) and (A.EndByte = B.EndByte) and (A.NodeType = B.NodeType);
end;

procedure CollectNodes(const ANode: TTSNode; const ATypes: array of string; AList: TList<TTSNode>);
var
  I: Integer;
begin
  if ANode.IsNull then Exit;
  if MatchStr(ANode.NodeType, ATypes) then AList.Add(ANode);
  for I:= 0 to ANode.ChildCount - 1 do CollectNodes(ANode.Child(I), ATypes, AList);
end;

function NewFinding(const AFile, ARule, ASeverity, AMessage: string; ALine, ACol, AEndCol: Integer): TLintFinding;
begin
  Result:= Default(TLintFinding);
  Result.RuleId   := ARule;
  Result.Severity := ASeverity;
  Result.Message  := AMessage;
  Result.FilePath := AFile;
  Result.StartLine:= ALine;
  Result.StartCol := ACol;
  Result.EndLine  := ALine;
  Result.EndCol   := AEndCol;
end;

function NodeFinding(const AFile, ARule, ASeverity, AMessage: string; const ANode: TTSNode): TLintFinding;
begin
  Result:= NewFinding(AFile, ARule, ASeverity, AMessage, Integer(ANode.StartPoint.Row) + 1,
    TAstParseCache.CharCol(AFile, ANode.StartPoint), TAstParseCache.CharCol(AFile, ANode.EndPoint));
  Result.EndLine:= Integer(ANode.EndPoint.Row) + 1;
end;

function IsPure(const ANode: TTSNode; const ASrc: TBytes): Boolean; forward;

{ True when every child of ANode except ASkip is pure. }
function ChildrenPure(const ANode, ASkip: TTSNode; const ASrc: TBytes): Boolean;
var
  I: Integer;
begin
  Result:= True;
  for I:= 0 to ANode.ChildCount - 1 do
    if (not SameNode(ANode.Child(I), ASkip)) and (not IsPure(ANode.Child(I), ASrc)) then Result:= False;
end;

{ An expression with no call outside PURE_CALLS and no anonymous method. }
function IsPure(const ANode: TTSNode; const ASrc: TBytes): Boolean;
var
  Entity: TTSNode;
begin
  Result:= False;
  if ANode.IsNull or (ANode.NodeType = 'lambda') or ANode.IsError then Exit;
  if ANode.NodeType <> 'exprCall' then Exit(ChildrenPure(ANode, Default(TTSNode), ASrc));
  Entity:= ANode.ChildByField('entity');
  Result:= (not Entity.IsNull) and (Entity.NodeType = 'identifier') and MatchText(SrcText(Entity, ASrc), PURE_CALLS)
    and ChildrenPure(ANode, Entity, ASrc);
end;

{ A Boolean-valued, effect-free operand: comparison, not, Boolean RTL call, or and / or of those. }
function IsProvenBool(const ANode: TTSNode; const ASrc: TBytes): Boolean;
var
  N, Entity: TTSNode;
  Op: string;
begin
  Result:= False;
  N:= Unwrap(ANode);
  if N.IsNull then Exit;
  if N.NodeType = 'exprBinary' then
  begin
    Op:= OpOf(N);
    if MatchStr(Op, CMP_OPS) then Exit(IsPure(N, ASrc));
    if MatchStr(Op, LOGIC_OPS) then Exit(IsProvenBool(N.ChildByField('lhs'), ASrc) and IsProvenBool(N.ChildByField('rhs'), ASrc));
    Exit;
  end;
  if (N.NodeType = 'exprUnary') and (OpOf(N) = 'kNot') then Exit(IsProvenBool(N.ChildByField('operand'), ASrc));
  if N.NodeType = 'exprCall' then
  begin
    Entity:= N.ChildByField('entity');
    Result:= (not Entity.IsNull) and (Entity.NodeType = 'identifier') and MatchText(SrcText(Entity, ASrc), BOOL_CALLS) and IsPure(N, ASrc);
  end;
end;

procedure Flatten(const ANode: TTSNode; const AOp: string; AList: TList<TTSNode>);
begin
  if (ANode.NodeType = 'exprBinary') and (OpOf(ANode) = AOp) then
  begin
    Flatten(ANode.ChildByField('lhs'), AOp, AList);
    Flatten(ANode.ChildByField('rhs'), AOp, AList);
  end
  else AList.Add(ANode);
end;

function IsChainRoot(const ANode: TTSNode): Boolean;
var
  P: TTSNode;
begin
  P:= ANode.Parent;
  Result:= P.IsNull or (P.NodeType <> 'exprBinary') or (OpOf(P) <> OpOf(ANode));
end;

{ ---- contradictory-condition ---- }

type
  TBound = record
    HasLo, LoStrict, HasHi, HiStrict: Boolean;
    Lo, Hi: Double;
    Eq, Ne: TList<Double>;
  end;

function LiteralValue(const ANode: TTSNode; const ASrc: TBytes; out AValue: Double): Boolean;
var
  N: TTSNode;
  Text: string;
  Sign: Double;
  I64: Int64;
begin
  Result:= False;
  AValue:= 0;
  N:= Unwrap(ANode);
  Sign:= 1;
  if (N.NodeType = 'exprUnary') and MatchStr(OpOf(N), ['kSub', 'kAdd']) then
  begin
    if OpOf(N) = 'kSub' then Sign:= -1;
    N:= Unwrap(N.ChildByField('operand'));
  end;
  if N.IsNull or (N.NodeType <> 'literalNumber') then Exit;
  Text:= Trim(SrcText(N, ASrc)).Replace('_', '');
  if Text.StartsWith('$') then
  begin
    if not TryStrToInt64(Text, I64) then Exit;
    AValue:= Sign * I64;
    Exit(True);
  end;
  Result:= TryStrToFloat(Text, AValue, TFormatSettings.Invariant);
  if Result then AValue:= Sign * AValue;
end;

{ identifier or dotted identifiers, nothing else }
function IsPath(const ANode: TTSNode): Boolean;
var
  N: TTSNode;
begin
  N:= Unwrap(ANode);
  if N.IsNull then Exit(False);
  if N.NodeType = 'identifier' then Exit(True);
  Result:= (N.NodeType = 'exprDot') and IsPath(N.ChildByField('lhs')) and (N.ChildByField('rhs').NodeType = 'identifier');
end;

function Flip(const AOp: string): string;
begin
  if AOp = 'kLt' then Exit('kGt');
  if AOp = 'kGt' then Exit('kLt');
  if AOp = 'kLte' then Exit('kGte');
  if AOp = 'kGte' then Exit('kLte');
  Result:= AOp;
end;

{ A comparison of a path with a literal, normalised to path OP literal. }
function ParseBound(const ANode: TTSNode; const ASrc: TBytes; out APath, AOp: string; out AValue: Double): Boolean;
var
  N, L, R: TTSNode;
begin
  Result:= False;
  APath:= '';
  AOp:= '';
  AValue:= 0;
  N:= Unwrap(ANode);
  if (N.IsNull) or (N.NodeType <> 'exprBinary') then Exit;
  AOp:= OpOf(N);
  if not MatchStr(AOp, ['kEq', 'kNeq', 'kLt', 'kLte', 'kGt', 'kGte']) then Exit;
  L:= N.ChildByField('lhs');
  R:= N.ChildByField('rhs');
  if IsPath(L) and LiteralValue(R, ASrc, AValue) then APath:= Squash(SrcText(Unwrap(L), ASrc))
  else if IsPath(R) and LiteralValue(L, ASrc, AValue) then
  begin
    APath:= Squash(SrcText(Unwrap(R), ASrc));
    AOp  := Flip(AOp);
  end
  else Exit;
  Result:= True;
end;

{ exact equality of two literal values (CompareValue without an epsilon) }
function SameNum(A, B: Double): Boolean;
begin
  Result:= CompareValue(A, B) = EqualsValue;
end;

{ The interval of ABound holds no value. }
function RangeEmpty(const ABound: TBound): Boolean;
begin
  Result:= ABound.HasLo and ABound.HasHi and ((ABound.Lo > ABound.Hi)  // dl:ok boolean-expression-complexity@55a7 -- REVIEWED 2026-11-24 INT-W2: the definition of an empty interval in one expression
    or (SameNum(ABound.Lo, ABound.Hi) and (ABound.LoStrict or ABound.HiStrict)));
end;

{ One of the values a variable must equal lies outside the interval, is excluded or differs from another. }
function EqualsConflict(const ABound: TBound): Boolean;
var
  V: Double;
begin
  Result:= False;
  for V in ABound.Eq do
    if (ABound.HasLo and ((V < ABound.Lo) or (SameNum(V, ABound.Lo) and ABound.LoStrict)))  // dl:ok boolean-expression-complexity@d342 -- REVIEWED 2026-11-24 INT-W2: below lo, above hi, excluded or different: the four ways of one conflict
      or (ABound.HasHi and ((V > ABound.Hi) or (SameNum(V, ABound.Hi) and ABound.HiStrict)))
      or ABound.Ne.Contains(V) or (not SameNum(V, ABound.Eq[0])) then Result:= True;
end;

function Contradicts(const ABound: TBound): Boolean;
begin
  Result:= RangeEmpty(ABound) or EqualsConflict(ABound);
end;

procedure AddBound(var ABound: TBound; const AOp: string; AValue: Double);
begin
  if AOp = 'kEq' then ABound.Eq.Add(AValue)
  else if AOp = 'kNeq' then ABound.Ne.Add(AValue)
  else if (AOp = 'kGt') or (AOp = 'kGte') then
  begin
    if (not ABound.HasLo) or (AValue > ABound.Lo) or (SameNum(AValue, ABound.Lo) and (AOp = 'kGt')) then
    begin
      ABound.HasLo   := True;
      ABound.Lo      := AValue;
      ABound.LoStrict:= AOp = 'kGt';
    end;
  end
  else if (not ABound.HasHi) or (AValue < ABound.Hi) or (SameNum(AValue, ABound.Hi) and (AOp = 'kLt')) then
  begin
    ABound.HasHi   := True;
    ABound.Hi      := AValue;
    ABound.HiStrict:= AOp = 'kLt';
  end;
end;

procedure CheckContradictions(const ACtx: TV151FileCtx; const AChain: TList<TTSNode>; const ASrc: TBytes; AFound: TList<TLintFinding>);
var
  Held: TDictionary<string, TBound>;
  Reported: TDictionary<string, Boolean>;
  Item: TTSNode;
  Path, Op: string;
  Value: Double;
  B: TBound;
  Pair: TPair<string, TBound>;
begin
  Held    := TDictionary<string, TBound>.Create;
  Reported:= TDictionary<string, Boolean>.Create;
  try
    for Item in AChain do
    begin
      if not ParseBound(Item, ASrc, Path, Op, Value) then Continue;
      if not Held.TryGetValue(Path, B) then
      begin
        B:= Default(TBound);
        B.Eq:= TList<Double>.Create;
        B.Ne:= TList<Double>.Create;
      end;
      AddBound(B, Op, Value);
      Held.AddOrSetValue(Path, B);
      if (not Reported.ContainsKey(Path)) and Contradicts(B) then
      begin
        Reported.Add(Path, True);
        AFound.Add(NodeFinding(ACtx.Path, RULE_CONTRADICTION, SEVERITY_WARNING,
          Format('''%s'' contradicts an earlier condition on ''%s'' in the same and chain: the chain is always False',
            [Squash(SrcText(Unwrap(Item), ASrc)), Path]), Item));
      end;
    end;
  finally
    for Pair in Held do
    begin
      Pair.Value.Eq.Free;
      Pair.Value.Ne.Free;
    end;
    Held.Free;
    Reported.Free;
  end;
end;

procedure CheckDuplicates(const ACtx: TV151FileCtx; const AChain: TList<TTSNode>; const AOp: string; const ASrc: TBytes;
  AFound: TList<TLintFinding>);
var
  Seen: TDictionary<string, Boolean>;
  Told: TDictionary<string, Boolean>;
  Item: TTSNode;
  Key: string;
begin
  Seen:= TDictionary<string, Boolean>.Create;
  Told:= TDictionary<string, Boolean>.Create;
  try
    for Item in AChain do
    begin
      if not IsPure(Item, ASrc) then Seen.Clear;   { a call between two equal tests may change what they read }
      if not IsProvenBool(Item, ASrc) then Continue;
      Key:= Squash(SrcText(Unwrap(Item), ASrc));
      if not Seen.ContainsKey(Key) then
      begin
        Seen.Add(Key, True);
        Continue;
      end;
      if Told.ContainsKey(Key) then Continue;
      Told.Add(Key, True);
      AFound.Add(NodeFinding(ACtx.Path, RULE_DUP_OPERAND, SEVERITY_WARNING,
        Format('Operand ''%s'' appears twice in the same %s chain; the second one adds nothing (copy-paste error?)',
          [Trim(SrcText(Unwrap(Item), ASrc)), IfThen(AOp = 'kAnd', 'and', 'or')]), Item));
    end;
  finally
    Seen.Free;
    Told.Free;
  end;
end;

function CheckLogicalChains(const ACtx: TV151FileCtx): TArray<TLintFinding>;
var
  Parsed: TParsedFile;
  Nodes, Chain: TList<TTSNode>;
  Found: TList<TLintFinding>;
  N: TTSNode;
  Op: string;
  WantDup, WantContra: Boolean;
begin
  Result:= nil;
  WantDup   := ACtx.Wants(RULE_DUP_OPERAND);
  WantContra:= ACtx.Wants(RULE_CONTRADICTION);
  if not (WantDup or WantContra) then Exit;
  Parsed:= TAstParseCache.Get(ACtx.Path);
  if Parsed.Tree = nil then Exit;
  Nodes:= TList<TTSNode>.Create;
  Chain:= TList<TTSNode>.Create;
  Found:= TList<TLintFinding>.Create;
  try
    CollectNodes(Parsed.Tree.RootNode, ['exprBinary'], Nodes);
    for N in Nodes do
    begin
      Op:= OpOf(N);
      if (Op <> 'kAnd') and (Op <> 'kOr') then Continue;
      if not IsChainRoot(N) then Continue;
      Chain.Clear;
      Flatten(N, Op, Chain);
      if WantDup then CheckDuplicates(ACtx, Chain, Op, Parsed.Src, Found);
      if WantContra and (Op = 'kAnd') then CheckContradictions(ACtx, Chain, Parsed.Src, Found);
    end;
    Result:= Found.ToArray;
  finally
    Found.Free;
    Chain.Free;
    Nodes.Free;
  end;
end;

{ ---- boolean-comparison-precedence ---- }

function IsBoolLiteral(const ANode: TTSNode): Boolean;
begin
  Result:= (not ANode.IsNull) and ((ANode.NodeType = 'kTrue') or (ANode.NodeType = 'kFalse'));
end;

function CheckBooleanPrecedence(const ACtx: TV151FileCtx): TArray<TLintFinding>;
var
  Parsed: TParsedFile;
  Nodes: TList<TTSNode>;
  Found: TList<TLintFinding>;
  N, L, R, Logic, Other: TTSNode;
begin
  Result:= nil;
  if not ACtx.Wants(RULE_BOOL_PRECEDENCE) then Exit;
  Parsed:= TAstParseCache.Get(ACtx.Path);
  if Parsed.Tree = nil then Exit;
  Nodes:= TList<TTSNode>.Create;
  Found:= TList<TLintFinding>.Create;
  try
    CollectNodes(Parsed.Tree.RootNode, ['exprBinary'], Nodes);
    for N in Nodes do
    begin
      if not MatchStr(OpOf(N), ['kEq', 'kNeq']) then Continue;
      L:= N.ChildByField('lhs');
      R:= N.ChildByField('rhs');
      if (L.NodeType = 'exprBinary') and MatchStr(OpOf(L), LOGIC_OPS) then
      begin
        Logic:= L;
        Other:= R;
      end
      else if (R.NodeType = 'exprBinary') and MatchStr(OpOf(R), LOGIC_OPS) then
      begin
        Logic:= R;
        Other:= L;
      end
      else Continue;
      if not (IsBoolLiteral(Other) or IsBoolLiteral(Logic.ChildByField('lhs')) or IsBoolLiteral(Logic.ChildByField('rhs'))) then Continue;
      Found.Add(NodeFinding(ACtx.Path, RULE_BOOL_PRECEDENCE, SEVERITY_WARNING,
        Format('Precedence: ''%s'' binds tighter than ''%s'', so this reads (%s) %s ...; put parentheses around the comparison you mean',
          [LowerCase(Copy(OpOf(Logic), 2, MaxInt)), IfThen(OpOf(N) = 'kEq', '=', '<>'),
           Squash(SrcText(Logic, Parsed.Src)), IfThen(OpOf(N) = 'kEq', '=', '<>')]), N));
    end;
    Result:= Found.ToArray;
  finally
    Found.Free;
    Nodes.Free;
  end;
end;

{ ---- function-name-reads-itself ---- }

function RoutineName(const AHeader: TTSNode; const ASrc: TBytes): string;
var
  Name: TTSNode;
begin
  Name:= AHeader.ChildByField('name');
  while (not Name.IsNull) and (Name.NodeType = 'genericDot') do Name:= Name.ChildByField('rhs');
  Result:= Trim(SrcText(Name, ASrc));
end;

function IsFunctionHeader(const AHeader: TTSNode): Boolean;
var
  I: Integer;
begin
  Result:= False;
  for I:= 0 to AHeader.ChildCount - 1 do
    if AHeader.Child(I).NodeType = 'kFunction' then Exit(True);
end;

procedure WalkBody(const ANode: TTSNode; const AName: string; const ASrc: TBytes; AReads: TList<TTSNode>; var AAssigned: Boolean);
var
  I: Integer;
  P: TTSNode;
begin
  if ANode.IsNull then Exit;
  if (ANode.NodeType = 'defProc') or (ANode.NodeType = 'lambda') then Exit;
  if (ANode.NodeType = 'identifier') and SameText(Trim(SrcText(ANode, ASrc)), AName) then
  begin
    P:= ANode.Parent;
    if (P.NodeType = 'assignment') and SameNode(P.ChildByField('lhs'), ANode) then AAssigned:= True
    else if (P.NodeType = 'exprDot') and SameNode(P.ChildByField('rhs'), ANode) then { member of another object }
    else if (P.NodeType = 'exprCall') and SameNode(P.ChildByField('entity'), ANode) then { explicit call }
    else if (P.NodeType = 'exprUnary') and (OpOf(P) = 'kAt') then { address of }
    else AReads.Add(ANode);
    Exit;
  end;
  for I:= 0 to ANode.ChildCount - 1 do WalkBody(ANode.Child(I), AName, ASrc, AReads, AAssigned);
end;

function CheckFunctionNameReads(const ACtx: TV151FileCtx): TArray<TLintFinding>;
var
  Parsed: TParsedFile;
  Procs, Reads: TList<TTSNode>;
  Found: TList<TLintFinding>;
  Proc, Header, Body, Read: TTSNode;
  Name: string;
  Assigned: Boolean;
begin
  Result:= nil;
  if not ACtx.Wants(RULE_NAME_READS_ITSELF) then Exit;
  Parsed:= TAstParseCache.Get(ACtx.Path);
  if Parsed.Tree = nil then Exit;
  Procs:= TList<TTSNode>.Create;
  Reads:= TList<TTSNode>.Create;
  Found:= TList<TLintFinding>.Create;
  try
    CollectNodes(Parsed.Tree.RootNode, ['defProc'], Procs);
    for Proc in Procs do
    begin
      Header:= Proc.ChildByField('header');
      Body  := Proc.ChildByField('body');
      if Header.IsNull or Body.IsNull or (Header.NodeType <> 'declProc') or (not IsFunctionHeader(Header)) then Continue;
      if not Header.ChildByField('args').IsNull then Continue;   // a function with parameters: the name cannot be read bare
      Name:= RoutineName(Header, Parsed.Src);
      if Name = '' then Continue;
      Reads.Clear;
      Assigned:= False;
      WalkBody(Body, Name, Parsed.Src, Reads, Assigned);
      if not Assigned then Continue;
      for Read in Reads do
        Found.Add(NodeFinding(ACtx.Path, RULE_NAME_READS_ITSELF, SEVERITY_WARNING,
          Format('''%s'' is read inside the function that assigns it: this calls %s again, it does not read the result; use Result',
            [Name, Name]), Read));
    end;
    Result:= Found.ToArray;
  finally
    Found.Free;
    Reads.Free;
    Procs.Free;
  end;
end;

{ ---- raw text ---- }

type
  TDirective = record
    Line, Col, EndCol: Integer;
    Switch: string;     { 'warnings-on' | 'warnings-off' | '' }
    CodeMark: Integer;  { length of the code-only text when the directive was met }
  end;

  TIdent = record
    Line, Col: Integer;
    Text: string;
  end;

{ The file as text: strict UTF-8 when it is, else ANSI. AIsUtf8 tells which. }
function DecodeSource(const ABytes: TBytes; out AIsUtf8: Boolean): string;
var
  Enc: TEncoding;
  Start: Integer;
begin
  AIsUtf8:= True;
  Start:= 0;
  if (Length(ABytes) >= BOM_LEN) and (ABytes[0] = BOM_BYTES[0]) and (ABytes[1] = BOM_BYTES[1]) and (ABytes[2] = BOM_BYTES[2]) then Start:= BOM_LEN;
  Enc:= TUTF8Encoding.Create(UTF8_CODEPAGE, STRICT_DECODE, 0);
  try
    try
      Result:= Enc.GetString(ABytes, Start, Length(ABytes) - Start);
    except
      on EEncodingError do
      begin
        AIsUtf8:= False;
        Result := TEncoding.ANSI.GetString(ABytes, Start, Length(ABytes) - Start);
      end;
    end;
  finally
    Enc.Free;
  end;
end;

{ A WARNINGS ON / OFF switch in the comment text ABody (starting with the brace or paren-star): remembers it. }
procedure NoteDirective(const ABody: string; ALine, ACol, ACodeMark: Integer; ADirs: TList<TDirective>);
var
  Match: TMatch;
  Dir: TDirective;
begin
  if not (ABody.StartsWith('{$') or ABody.StartsWith('(*$')) then Exit;
  Match:= TRegEx.Match(ABody, '^(?:\{|\(\*)\$WARNINGS\s+(ON|OFF)\b', [roIgnoreCase]);
  if not Match.Success then Exit;
  Dir:= Default(TDirective);
  Dir.Line    := ALine;
  Dir.Col     := ACol;
  Dir.EndCol  := ACol + 1;
  Dir.Switch  := if SameText(Match.Groups[1].Value, 'ON') then 'warnings-on' else 'warnings-off';
  Dir.CodeMark:= ACodeMark;
  ADirs.Add(Dir);
end;

{ Walks S outside strings and comments; collects the WARNINGS switches and the identifiers that hold a non-ASCII letter. }
procedure LexSource(const S: string; ADirs: TList<TDirective>; AIdents: TList<TIdent>; ACode: TStringBuilder);
var
  I, N, Line, LineStart, J, Start: Integer;
  Ch: Char;
  Line0, Col0: Integer;
  Ident: TIdent;
  NonAscii: Boolean;

  procedure Skip(AUntil: string; AFrom: Integer);
  var
    K: Integer;
  begin
    K:= PosEx(AUntil, S, AFrom);
    K:= if K = 0 then N + 1 else K + Length(AUntil);
    while I < K - 1 do
    begin
      Inc(I);
      if (I <= N) and (S[I] = #10) then
      begin
        Inc(Line);
        LineStart:= I;
      end;
    end;
  end;

begin
  N:= Length(S);
  I:= 1;
  Line:= 1;
  LineStart:= 0;
  while I <= N do
  begin
    Ch:= S[I];
    if Ch = #10 then
    begin
      Inc(Line);
      LineStart:= I;
    end
    else if Ch = '''' then
    begin
      ACode.Append('s');
      J:= I + 1;
      while (J <= N) and (S[J] <> #10) do
      begin
        if S[J] = '''' then
        begin
          if (J < N) and (S[J + 1] = '''') then Inc(J) else Break;
        end;
        Inc(J);
      end;
      I:= if (J <= N) and (S[J] = '''') then J else J - 1;
    end
    else if (Ch = '/') and (I < N) and (S[I + 1] = '/') then
    begin
      while (I < N) and (S[I + 1] <> #10) do Inc(I);
    end
    else if (Ch = '{') or ((Ch = '(') and (I < N) and (S[I + 1] = '*')) then
    begin
      Start:= I;
      Line0:= Line;
      Col0 := I - LineStart;
      if Ch = '{' then Skip('}', I + 1) else Skip('*)', I + 2);
      NoteDirective(Copy(S, Start, I - Start + 1), Line0, Col0, ACode.Length, ADirs);
    end
    else if Ch.IsLetter or (Ch = '_') then
    begin
      J:= I;
      NonAscii:= False;
      while (J <= N) and (S[J].IsLetterOrDigit or (S[J] = '_')) do
      begin
        if Ord(S[J]) >= ASCII_LIMIT then NonAscii:= True;
        Inc(J);
      end;
      if NonAscii and (AIdents <> nil) then
      begin
        Ident.Line:= Line;
        Ident.Col := I - LineStart;
        Ident.Text:= Copy(S, I, J - I);
        AIdents.Add(Ident);
      end;
      ACode.Append('i');
      I:= J - 1;
    end
    else if not Ch.IsWhiteSpace then ACode.Append(Ch);
    Inc(I);
  end;
end;

function CheckWarningsRestored(const AFilePath: string; const ABytes: TBytes): TArray<TLintFinding>;
var
  IsUtf8: Boolean;
  Text: string;
  Dirs: TList<TDirective>;
  Code: TStringBuilder;
  Dir, Pending: TDirective;
  HasPending: Boolean;
  Tail: string;
begin
  Result:= nil;
  if (Length(ABytes) = 0) or (not MatchText(ExtractFileExt(AFilePath), ['.pas', '.dpr', '.dpk'])) then Exit;
  Text:= DecodeSource(ABytes, IsUtf8);
  if not ContainsText(Text, 'WARNINGS') then Exit;
  Dirs:= TList<TDirective>.Create;
  Code:= TStringBuilder.Create;
  try
    LexSource(Text, Dirs, nil, Code);
    HasPending:= False;
    Pending   := Default(TDirective);
    for Dir in Dirs do
      if Dir.Switch = 'warnings-off' then
      begin
        if not HasPending then
        begin
          Pending   := Dir;
          HasPending:= True;
        end;
      end
      else HasPending:= False;
    if not HasPending then Exit;
    Tail:= Code.ToString(Pending.CodeMark, Code.Length - Pending.CodeMark);
    if (Tail = 'i.') or (Tail = '') then Exit;   { nothing after the switch but the final "end." }
    Result:= [NewFinding(AFilePath, RULE_WARNINGS_OFF, SEVERITY_HINT,
      '{$WARNINGS OFF} is never switched back on in this file: every warning after it is hidden. Put {$WARNINGS ON} after the code that needs it',
      Pending.Line, Pending.Col, Pending.EndCol)];
  finally
    Code.Free;
    Dirs.Free;
  end;
end;

function IsLookAlike(ACh: Char): Boolean;
begin
  Result:= CONFUSABLES.Contains(ACh);
end;

function IsLatinLetter(ACh: Char): Boolean;
begin
  Result:= CharInSet(ACh, ['A'..'Z', 'a'..'z']);
end;

function MixesScripts(const AName: string): Boolean;
var
  Ch: Char;
  Latin, Confusable: Boolean;
begin
  Latin:= False;
  Confusable:= False;
  for Ch in AName do
  begin
    if Ord(Ch) < ASCII_LIMIT then
    begin
      if IsLatinLetter(Ch) then Latin:= True;
    end
    else if Ch.IsLetter then
    begin
      if not IsLookAlike(Ch) then Exit(False);   { a genuine word of another script: not a homoglyph }
      Confusable:= True;
    end;
  end;
  Result:= Latin and Confusable;
end;

function CheckHomoglyphs(const AFilePath: string; const ABytes: TBytes): TArray<TLintFinding>;
var
  IsUtf8, Any: Boolean;
  B: Byte;
  Text: string;
  Idents: TList<TIdent>;
  Code: TStringBuilder;
  Dirs: TList<TDirective>;
  Ident: TIdent;
  Found: TList<TLintFinding>;
begin
  Result:= nil;
  if (Length(ABytes) = 0) or (not MatchText(ExtractFileExt(AFilePath), ['.pas', '.dpr', '.dpk'])) then Exit;
  Any:= False;
  for B in ABytes do
    if B >= ASCII_LIMIT then
    begin
      Any:= True;
      Break;
    end;
  if not Any then Exit;
  Text:= DecodeSource(ABytes, IsUtf8);
  if not IsUtf8 then Exit;   { an ANSI file: bytes >= $80 are code-page letters, not look-alikes }
  Idents:= TList<TIdent>.Create;
  Dirs  := TList<TDirective>.Create;
  Code  := TStringBuilder.Create;
  Found := TList<TLintFinding>.Create;
  try
    LexSource(Text, Dirs, Idents, Code);
    for Ident in Idents do
      if MixesScripts(Ident.Text) then
        Found.Add(NewFinding(AFilePath, RULE_HOMOGLYPH, SEVERITY_WARNING,
          Format('Identifier ''%s'' mixes Latin letters with look-alike letters of another script (Cyrillic / Greek): it reads like a plain Latin name but is a different one',
            [Ident.Text]), Ident.Line, Ident.Col, Ident.Col + Length(Ident.Text)));
    Result:= Found.ToArray;
  finally
    Found.Free;
    Code.Free;
    Dirs.Free;
    Idents.Free;
  end;
end;

end.
