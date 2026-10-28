unit DRagLint.Diagnostics.SizeChecks;

{ Clippy-parity wave (plan 2026-10-27-clippy-rules-plan.md), lane L8.
  L0 shipped this unit as a STUB: Check returns nil. The lane replaces the body
  and adds the emitted ids to LINT_GATE_SIZE's checker (the ids are already
  in the gate list and in TRuleCatalog.BuiltinRegistry -- a lane registers
  nothing new in CLI.pas or RuleCatalog.pas).
  Rules: large-stack-local, too-many-bool-fields, inline-on-large-routine. }

interface

uses
  DRagLint.Core.Model
  , DRagLint.Core.Interfaces
  , DRagLint.Lint.Config
  ;

type
  /// <summary>Checker for the large-stack-local, too-many-bool-fields, inline-on-large-routine rules. Thresholds come from the rule params.</summary>
  /// <remarks>
  /// Stateless; thread-safe. Called from DoLint and DoLintAll behind
  /// LintRuleWants(rule, LINT_GATE_SIZE).
  /// </remarks>
  TSizeChecker = class
  public
    /// <summary>Runs the SizeChecks rules against one source file.</summary>
    /// <param name="AFile">Absolute path to the .pas/.inc source file.</param>
    /// <param name="ACfg">Effective lint configuration (thresholds via ThresholdFor).</param>
    /// <param name="AStore">Optional symbol store; nil when the run has no index.</param>
    /// <param name="AFileId">File id within AStore (ignored when AStore is nil).</param>
    /// <returns>One finding per violation; empty when clean or unparsable. The CLI filters by --rule.</returns>
    class function Check(const AFile: string; const ACfg: TLintConfig;
      const AStore: ISymbolStore; AFileId: Integer): TArray<TLintFinding>; static;
  end;

implementation

uses
  System.SysUtils
  , System.StrUtils
  , System.Generics.Collections
  , TreeSitter
  , DRagLint.Diagnostics.ParseCache
  ;

const
  RULE_STACK  = 'large-stack-local';
  RULE_BOOLS  = 'too-many-bool-fields';
  RULE_INLINE = 'inline-on-large-routine';
  DEFAULT_STACK_BYTES      = 65536;
  DEFAULT_MAX_BOOLS        = 5;
  DEFAULT_MAX_INLINE_LINES = 20;
  SHORTSTRING_BYTES        = 256;
  BYTES_UNKNOWN            = 1;
  SIZE_1                   = 1;
  SIZE_2                   = 2;
  SIZE_4                   = 4;
  SIZE_8                   = 8;
  SIZE_16                  = 16;
  STRING_OPEN              = 'string[';
  BYTES_MAX                = High(Int64) div 4;

{ Byte size of a scalar element type by lower-cased name; BYTES_UNKNOWN for a
  name the checker does not know (records, classes, aliases) -- under-reporting
  is the safe direction. Win64 sizes. }
function ScalarBytes(const ALow: string): Int64;
begin
  if MatchStr(ALow, ['byte', 'shortint', 'boolean', 'bytebool', 'char', 'ansichar', 'utf8char']) then
    Result:= SIZE_1
  else if MatchStr(ALow, ['word', 'smallint', 'widechar', 'wordbool']) then
    Result:= SIZE_2
  else if MatchStr(ALow, ['integer', 'cardinal', 'longint', 'longword', 'single', 'longbool',
    'uint32', 'int32', 'dword', 'tdatetime']) then
    Result:= SIZE_4
  else if MatchStr(ALow, ['int64', 'uint64', 'double', 'real', 'currency', 'pointer', 'string',
    'ansistring', 'unicodestring', 'widestring', 'nativeint', 'nativeuint', 'tobject', 'comp']) then
    Result:= SIZE_8
  else if MatchStr(ALow, ['extended', 'variant']) then
    Result:= SIZE_16
  else
    Result:= BYTES_UNKNOWN;
end;

{ Element count of a dimension list `lo..hi,lo..hi` (whitespace removed); -1 when
  a bound is not a plain integer literal, BYTES_MAX on overflow. }
function DimCount(const ADims: string): Int64;
var
  D: string;
  P, Q, Lo, Hi: Integer;
begin
  Result:= 1;
  for D in SplitString(ADims, ',') do
  begin
    P:= Pos('..', D);
    Lo:= StrToIntDef(Copy(D, 1, P - 1), MaxInt);
    Hi:= StrToIntDef(Copy(D, P + 2, MaxInt), MaxInt);
    if (P = 0) or (Lo = MaxInt) or (Hi = MaxInt) or (Hi < Lo) then Exit(-1);
    Q:= Hi - Lo + 1;
    if Result > BYTES_MAX div Q then Exit(BYTES_MAX);
    Result:= Result * Q;
  end;
end;

{ Static byte size of a type text (whitespace already removed, lower-cased):
  `string[N]`, `shortstring`, `array[lo..hi,...]of Elem` (nested allowed) or a
  scalar. Returns -1 when a bound is not a plain integer literal. }
function TypeBytes(const AText: string): Int64;
var
  Dims: string;
  P: Integer;
  Count, ElemBytes: Int64;
begin
  if StartsStr(STRING_OPEN, AText) and EndsStr(']', AText) then
  begin
    Result:= StrToIntDef(Copy(AText, Length(STRING_OPEN) + 1, Length(AText) - Length(STRING_OPEN) - 1), -1);
    if Result >= 0 then Inc(Result);
  end
  else if AText = 'shortstring' then
    Result:= SHORTSTRING_BYTES
  else if StartsStr('array[', AText) or StartsStr('packedarray[', AText) then
  begin
    Dims:= Copy(AText, Pos('[', AText) + 1, MaxInt);
    P:= Pos(']of', Dims);
    Count:= -1;
    ElemBytes:= -1;
    if P > 0 then
    begin
      Count:= DimCount(Copy(Dims, 1, P - 1));
      ElemBytes:= TypeBytes(Copy(Dims, P + Length(']of'), MaxInt));
    end;
    if (Count < 0) or (ElemBytes < 0) then
      Result:= -1
    else if (ElemBytes > 0) and (Count > BYTES_MAX div ElemBytes) then
      Result:= BYTES_MAX
    else
      Result:= Count * ElemBytes;
  end
  else
    Result:= ScalarBytes(AText);
end;
class function TSizeChecker.Check(const AFile: string; const ACfg: TLintConfig;
  const AStore: ISymbolStore; AFileId: Integer): TArray<TLintFinding>; // dl:ok unused-parameter@9a67 -- AStore and AFileId are fixed by the shared checker-gate signature; this AST-only checker needs no index
var
  PF         : TParsedFile                 ;
  Findings   : TList<TLintFinding>         ;
  InlineNames: TDictionary<string, Boolean>;
  DefCounts  : TDictionary<string, Integer>;
  StackMax   : Int64                       ;
  BoolMax    : Integer                     ;
  InlineMax  : Integer                     ;

  function NodeStr(const N: TTSNode): string;
  var
    S, L: Integer;
  begin
    Result:= '';
    if N.IsNull then Exit;
    S:= Integer(N.StartByte);
    L:= Integer(N.EndByte) - S;
    if (L <= 0) or (S < 0) or (S + L > Length(PF.Src)) then Exit;
    Result:= TEncoding.UTF8.GetString(PF.Src, S, L);
  end;

  procedure EmitAt(const ANode: TTSNode; const ARuleId, AMessage, ASeverity: string);
  var
    P: TTSPoint    ;
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
    F.EndLine  := F.StartLine;
    F.EndCol   := F.StartCol + Length(Trim(NodeStr(ANode)));
    Findings.Add(F);
  end;

  { Lower-cased type text with all whitespace removed. }
  function CompactType(const N: TTSNode): string;
  var
    SB: TStringBuilder;
    C : Char          ;
  begin
    SB:= TStringBuilder.Create;
    try
      for C in LowerCase(NodeStr(N)) do
        if not CharInSet(C, [' ', #9, #10, #13]) then SB.Append(C);
      Result:= SB.ToString;
    finally
      SB.Free;
    end;
  end;

  function HasKind(const N: TTSNode; const AKind: string): Boolean;
  var
    I: Integer;
  begin
    Result:= False;
    if N.IsNull then Exit;
    if N.NodeType = AKind then Exit(True);
    for I:= 0 to Integer(N.ChildCount) - 1 do
      if HasKind(N.Child(I), AKind) then Exit(True);
  end;

  { Bare lower-cased routine name of a declProc/defProc-header name node. }
  function BareName(const ANameNode: TTSNode): string;
  var
    T: string;
  begin
    T:= LowerCase(Trim(NodeStr(ANameNode)));
    Result:= Copy(T, LastDelimiter('.', T) + 1, MaxInt);
  end;

  { Pass 1: bare names of routines carrying the `inline` directive on a declProc
    (interface/class declaration) or on a defProc header / trailing attribute. }
  procedure CollectInline(const N: TTSNode);
  var
    I, Cnt: Integer;
    H: TTSNode;
    Key: string;
  begin
    if N.IsNull then Exit;
    if N.NodeType = 'declProc' then
    begin
      if HasKind(N, 'kInline') then InlineNames.AddOrSetValue(BareName(N.ChildByField('name')), True);
    end
    else if N.NodeType = 'defProc' then
    begin
      H:= N.ChildByField('header');
      Key:= BareName(H.ChildByField('name'));
      DefCounts.TryGetValue(Key, Cnt);
      DefCounts.AddOrSetValue(Key, Cnt + 1);
      if HasKind(H, 'kInline') or HasKind(N.ChildByField('trailingAttr'), 'kInline') then
        InlineNames.AddOrSetValue(BareName(H.ChildByField('name')), True);
    end;
    for I:= 0 to Integer(N.NamedChildCount) - 1 do CollectInline(N.NamedChild(I));
  end;

  procedure CheckVar(const N: TTSNode);
  var
    TypeN, IdN: TTSNode;
    I         : Integer;
    Bytes     : Int64;
  begin
    TypeN:= N.ChildByField('type');
    if TypeN.IsNull then Exit;
    Bytes:= TypeBytes(CompactType(TypeN));
    if Bytes <= StackMax then Exit;
    for I:= 0 to Integer(N.NamedChildCount) - 1 do
    begin
      IdN:= N.NamedChild(I);
      if IdN.NodeType <> 'identifier' then Continue;
      if IdN.StartByte >= TypeN.StartByte then Break;
      EmitAt(IdN, RULE_STACK, Format('Local variable "%s" occupies about %d bytes of stack (threshold %d); allocate it on the heap',
        [Trim(NodeStr(IdN)), Bytes, StackMax]), 'info');
    end;
  end;

  { Number of Boolean-typed names declared by one declField (0 when not Boolean). }
  function BoolNames(const F: TTSNode): Integer;
  var
    K: Integer;
    IdN, TypeN: TTSNode;
  begin
    Result:= 0;
    TypeN:= F.ChildByField('type');
    if TypeN.IsNull then Exit;
    if not MatchStr(CompactType(TypeN), ['boolean', 'bytebool', 'wordbool', 'longbool']) then Exit;
    for K:= 0 to Integer(F.NamedChildCount) - 1 do
    begin
      IdN:= F.NamedChild(K);
      if IdN.NodeType <> 'identifier' then Continue;
      if IdN.StartByte >= TypeN.StartByte then Break;
      Inc(Result);
    end;
  end;

  procedure CheckBoolClass(const AClass: TTSNode);
  var
    Count, I, J: Integer;
    Sec, Anchor: TTSNode;
  begin
    for I:= 0 to Integer(AClass.ChildCount) - 1 do
      if AClass.Child(I).NodeType = 'kRecord' then Exit;
    Count:= 0;
    for I:= 0 to Integer(AClass.NamedChildCount) - 1 do
    begin
      Sec:= AClass.NamedChild(I);
      if Sec.NodeType = 'declField' then
        Inc(Count, BoolNames(Sec))
      else if Sec.NodeType = 'declSection' then
        for J:= 0 to Integer(Sec.NamedChildCount) - 1 do
          if Sec.NamedChild(J).NodeType = 'declField' then Inc(Count, BoolNames(Sec.NamedChild(J)));
    end;
    if Count <= BoolMax then Exit;
    Anchor:= AClass.Parent;
    Anchor:= if (not Anchor.IsNull) and (Anchor.NodeType = 'declType') then Anchor.ChildByField('name') else AClass;
    EmitAt(Anchor, RULE_BOOLS, Format('Class has %d Boolean fields (threshold %d) -- consider a set of flags or a state enum',
      [Count, BoolMax]), 'info');
  end;

  procedure CheckInlineProc(const N: TTSNode);
  var
    NameN : TTSNode;
    Lines : Integer;
    HasTry: Boolean;
  begin
    NameN:= N.ChildByField('header').ChildByField('name');
    if NameN.IsNull or not InlineNames.ContainsKey(BareName(NameN)) then Exit;
    { overloaded name: the declProc/defProc pairing is ambiguous -- stay silent }
    if DefCounts[BareName(NameN)] > 1 then Exit;
    Lines:= Integer(N.EndPoint.Row) - Integer(N.StartPoint.Row) + 1;
    HasTry:= HasKind(N, 'try');
    if (Lines <= InlineMax) and not HasTry then Exit;
    EmitAt(NameN, RULE_INLINE, Format('inline routine "%s" is %d lines%s -- the compiler will not inline it or code bloat outweighs the gain',
      [Trim(NodeStr(NameN)), Lines, IfThen(HasTry, ' and contains try', '')]), 'hint');
  end;

  procedure Visit(const N: TTSNode; AInProc: Boolean);
  var
    I   : Integer;
    Kind: string;
  begin
    if N.IsNull then Exit;
    Kind:= N.NodeType;
    if Kind = 'defProc' then
    begin
      CheckInlineProc(N);
      AInProc:= True;
    end
    else if ((Kind = 'declVar') or (Kind = 'varDef') or (Kind = 'varAssignDef')) and AInProc then
      CheckVar(N)
    else if Kind = 'declClass' then
      CheckBoolClass(N);
    for I:= 0 to Integer(N.NamedChildCount) - 1 do Visit(N.NamedChild(I), AInProc);
  end;

begin
  Result:= nil;
  PF:= TAstParseCache.Get(AFile);
  if PF.Tree = nil then Exit;
  StackMax := ACfg.ThresholdFor(RULE_STACK, DEFAULT_STACK_BYTES);
  BoolMax  := ACfg.ThresholdFor(RULE_BOOLS, DEFAULT_MAX_BOOLS);
  InlineMax:= ACfg.ThresholdFor(RULE_INLINE, DEFAULT_MAX_INLINE_LINES);
  Findings:= TList<TLintFinding>.Create;
  InlineNames:= TDictionary<string, Boolean>.Create;
  DefCounts:= TDictionary<string, Integer>.Create;
  try
    CollectInline(PF.Tree.RootNode);
    Visit(PF.Tree.RootNode, False);
    Result:= Findings.ToArray;
  finally
    DefCounts.Free;
    InlineNames.Free;
    Findings.Free;
  end;
end;

end.
