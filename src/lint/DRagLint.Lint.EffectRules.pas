unit DRagLint.Lint.EffectRules;

{ Three store-backed rules that read the STORED purity facts (effect_free /
  effect_summary / effect_witness) and the ui_affinity fact, and re-derive
  nothing (backlog 1.37.0 lane B-EFFECT; INBOX-lint-rules-from-new-facts-
  2026-09-23 rules 5, 6 and 7):

    side-effect-in-short-circuit    a proven-effect call in the right operand
                                    of a Boolean `and` / `or`;
    property-getter-with-effect     a read accessor method with a proven self-
                                    field or global write that is not a lazy
                                    initialiser or memo;
    ui-access-in-thread-transitive  a TThread.Execute that reaches, through
                                    resolved call edges, a routine whose
                                    ui_affinity is non-empty.

  All three follow assert-with-side-effect's stance: ABSENCE OVER A WRONG
  FINDING. A '?' summary is a gap in the proof, not an effect; an unbound or
  ambiguous call never fires; source that does not parse yields nothing. }

interface

uses
  System.SysUtils
  , System.Generics.Collections
  , DRagLint.Core.Model
  , DRagLint.Core.Interfaces
  ;

const
  /// <summary>Rule id: a proven-effect call in a short-circuited operand.</summary>
  SIDE_EFFECT_IN_SHORT_CIRCUIT_RULE = 'side-effect-in-short-circuit';
  /// <summary>Rule id: a property read accessor with a proven state change.</summary>
  PROPERTY_GETTER_WITH_EFFECT_RULE = 'property-getter-with-effect';
  /// <summary>Rule id: a thread body that reaches UI-touching code.</summary>
  UI_ACCESS_IN_THREAD_TRANSITIVE_RULE = 'ui-access-in-thread-transitive';
  /// <summary>Rule id: an effect-free call a loop could make once, before it starts.</summary>
  EFFECT_FREE_IN_LOOP_INVARIANT_RULE = 'effect-free-in-loop-invariant';

/// <summary>Finds resolved calls to a routine with a PROVEN effect that sit in
/// the RIGHT operand of a Boolean <c>and</c> / <c>or</c>, so they run only when
/// the left operand does not decide the result.</summary>
/// <param name="AStore">The project index; must carry the purity columns.</param>
/// <param name="AOnlyFileId">0 for every file; otherwise only findings in that
/// file are returned.</param>
/// <returns>One info finding per (call line, callee), anchored at the call line;
/// the message names the callee, its effect summary and its witness.</returns>
/// <remarks>
/// A proven effect is <c>effect_free = 0</c> with a stored summary
/// carrying <c>g</c>, <c>h</c>, <c>s</c> or <c>p&lt;k&gt;</c>; '?' alone never
/// fires, nor does an unbound or non-certain edge. The call line is parsed and
/// the call fires only when EVERY occurrence of the callee's name on that line is
/// in such a right operand. The operator must be PROVEN Boolean (an integer
/// <c>and</c> is bitwise and evaluates both sides): it is the condition of an
/// if / while / until / inline if, or one operand is a comparison, <c>not</c> of a
/// Boolean, True/False, <c>Assigned(..)</c>, another proven Boolean and/or, or
/// the call itself to a callee whose signature returns a Boolean type. A file
/// that contains <c>{$B+}</c> or <c>{$BOOLEVAL ON}</c> anywhere is skipped
/// whole. <c>xor</c> evaluates both sides and never counts.
/// DELIBERATE SHORT-CIRCUITS are exempt (1.42 tuning, 0 of 16 sampled findings
/// were actionable): a Boolean callee named <c>Try&lt;Word&gt;</c>; a Boolean
/// callee whose only proven effect is writing its own parameters (the fetch
/// shape); a parameterless memoizing callee (every write sits under an if that
/// tests nil, Assigned or what the body assigns); a callee whose proven effect is only a stored
/// SQL read; and a <c>Rcv.F</c> whose left operands include
/// <c>Assigned(Rcv)</c> or <c>Rcv &lt;&gt; nil</c>. NONE of these exempts an
/// ACCUMULATOR, <c>X:= X or F(..)</c>: there the call is lost once X is decided,
/// which is the bug this rule exists for. Never raises.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Lint.ProjectRules.TProjectLintRules.Run (DRagLint.Lint.ProjectRules.pas)</para>
/// <para>Calls: Default, DRagLint.Analysis.Purity.TEffectSummary.Decode, DRagLint.Core.Interfaces.ISymbolStore.FindResolvedCallers, DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsWithFacts, DRagLint.Core.Interfaces.ISymbolStore.GetAllFileIds, DRagLint.Core.Interfaces.ISymbolStore.GetAllSymbolFacts, DRagLint.Core.Interfaces.ISymbolStore.GetFilePath, DRagLint.Diagnostics.ParseCache.TAstParseCache.Get, DRagLint.Lint.EffectRules.AcceptCallSite, DRagLint.Lint.EffectRules.AndOrNear (+10 more)</para>
/// <para>Returns: Findings.ToArray</para>
/// <para>Complexity: 16 (cyclomatic, outer body), 82 lines (full implementation)</para>
/// <seealso cref="DRagLint.Analysis.Purity.TEffectSummary.Decode"/>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindResolvedCallers"/>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsWithFacts"/>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetAllFileIds"/>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetAllSymbolFacts"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function CollectSideEffectInShortCircuit(const AStore: ISymbolStore;
  AOnlyFileId: Int64): TArray<TLintFinding>;

/// <summary>Finds properties whose READ accessor is a method with a PROVEN
/// self-field (<c>s</c>) or global (<c>g</c>) write.</summary>
/// <param name="AStore">The project index; must carry the purity columns.</param>
/// <param name="AOnlyFileId">0 for every file; otherwise only findings in that
/// file are returned.</param>
/// <returns>One info finding per property, anchored at its declaration; the
/// message names the getter, its effect summary and its witness.</returns>
/// <remarks>
/// The getter is matched by name inside the property's own class in
/// the same file (<c>Unit.TClass.Getter</c>); an inherited getter, a field
/// accessor and an indexed or dotted accessor expression are not judged.
/// LAZY-INIT / MEMO EXEMPTION: a getter whose body has an if / while condition
/// that tests <c>nil</c>, calls <c>Assigned</c>, or names a variable the getter
/// itself assigns (other than Result) is exempt. Never raises.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Lint.ProjectRules.TProjectLintRules.Run (DRagLint.Lint.ProjectRules.pas)</para>
/// <para>Calls: Default, DRagLint.Analysis.Purity.TEffectSummary.Decode, DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsWithFacts, DRagLint.Core.Interfaces.ISymbolStore.GetAllSymbolFacts, DRagLint.Core.Interfaces.ISymbolStore.GetFilePath, DRagLint.Diagnostics.ParseCache.TAstParseCache.Get, DRagLint.Lint.EffectRules.CollectNodesOfType, DRagLint.Lint.EffectRules.IsLazyInitGetter, DRagLint.Lint.EffectRules.NodeText, DRagLint.Lint.EffectRules.OwningTypeName (+7 more)</para>
/// <para>Returns: Findings.ToArray</para>
/// <para>Complexity: 15 (cyclomatic, outer body), 76 lines (full implementation)</para>
/// <seealso cref="DRagLint.Analysis.Purity.TEffectSummary.Decode"/>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsWithFacts"/>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetAllSymbolFacts"/>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetFilePath"/>
/// <seealso cref="DRagLint.Diagnostics.ParseCache.TAstParseCache.Get"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function CollectPropertyGetterWithEffect(const AStore: ISymbolStore;
  AOnlyFileId: Int64): TArray<TLintFinding>;

/// <summary>Finds call sites inside a <c>TThread</c> descendant's
/// <c>Execute</c> that reach, over at most CMaxHops resolved call edges, a
/// routine whose stored ui_affinity is non-empty.</summary>
/// <param name="AStore">The project index; must carry symbol_facts.</param>
/// <param name="AOnlyFileId">0 for every file; otherwise only findings in that
/// file are returned.</param>
/// <returns>One warning per Execute call line, anchored there; the message
/// prints the shortest call path and the UI names the last routine touches.</returns>
/// <remarks>
/// Only certain call_edges rows are walked (backwards, from each
/// UI-touching routine). An edge whose callee name sits inside the arguments of
/// a <c>Synchronize</c>, <c>Queue</c> or <c>ForceQueue</c> call is not walked,
/// and a UI routine whose own body mentions Synchronize, Queue, MainThreadID or
/// CurrentThread is taken to marshal itself. The thread class is recognised by
/// the store's descendant closure of the name <c>TThread</c>. Direct UI access
/// in Execute's own body stays the job of the AST rule
/// <c>ui-access-in-thread</c>; this rule reports hops >= 1 only. Never raises.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Lint.ProjectRules.TProjectLintRules.Run (DRagLint.Lint.ProjectRules.pas)</para>
/// <para>Calls: Default, DRagLint.Core.Interfaces.ISymbolStore.FindDescendantNames, DRagLint.Core.Interfaces.ISymbolStore.GetAllFileIds, DRagLint.Core.Interfaces.ISymbolStore.GetAllSymbolFacts, DRagLint.Core.Interfaces.ISymbolStore.GetFilePath, DRagLint.Lint.EffectRules.CollectUiAccessInThreadTransitive.CallersOf, DRagLint.Lint.EffectRules.CollectUiAccessInThreadTransitive.IsThreadExecute, DRagLint.Lint.EffectRules.CollectUiAccessInThreadTransitive.SymOf, DRagLint.Lint.EffectRules.EdgeMarshalled, DRagLint.Lint.EffectRules.MarshalsItself, DRagLint.Lint.EffectRules.ShortName, Format, LowerCase, SameText</para>
/// <para>Returns: Findings.ToArray</para>
/// <para>Complexity: 19 (cyclomatic, outer body), 137 lines (full implementation)</para>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindDescendantNames"/>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetAllFileIds"/>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetAllSymbolFacts"/>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetFilePath"/>
/// <seealso cref="DRagLint.Lint.EffectRules.CollectUiAccessInThreadTransitive.CallersOf"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function CollectUiAccessInThreadTransitive(const AStore: ISymbolStore;
  AOnlyFileId: Int64): TArray<TLintFinding>;

/// <summary>Finds resolved calls to a value-returning, PROVEN effect-free routine
/// inside a loop that would answer the same on every iteration, so the call can
/// move before the loop.</summary>
/// <param name="AStore">The project index; must carry the purity columns.</param>
/// <param name="AOnlyFileId">0 for every file; otherwise only findings in that
/// file are returned.</param>
/// <returns>One info finding per (call line, callee), anchored at the call line;
/// the message names the callee, the loop's line and which proof holds.</returns>
/// <remarks>
/// ABSENCE OVER A WRONG FINDING. Inside a loop means its body or a
/// while / until condition; a for bound and a for-in enumerable run once and do
/// not count. Every overload and override of the name must be proven effect-free.
/// ARGUMENTS and RECEIVER are invariant when each name is a by-value local or
/// parameter the loop neither assigns, steps nor hands to a call not proven
/// effect-free, or a constant or type; anything reaching through a dot, subscript
/// or call needs the first proof below.
/// STATE is invariant by one of two proofs: (1) the loop writes only local
/// variables and every call in it is proven effect-free, or one of a short list of
/// RTL routines of their arguments alone, so nothing the callee reads can change
/// (a <c>.Count</c> read is taken as a read); or (2) the callee itself
/// reads no state, its body naming only its own by-value locals, constants and those
/// routines. A name a nested routine or closure mentions, or whose address is taken,
/// is no local; a with or asm around or inside the loop silences it. A one-line accessor is
/// not worth hoisting and never fires. Assumes no other thread writes what the
/// callee reads, and that a property getter has no effect (see
/// property-getter-with-effect). Never raises.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Lint.ProjectRules.TProjectLintRules.Run (DRagLint.Lint.ProjectRules.pas)</para>
/// <para>Calls: Default, DRagLint.Core.Interfaces.ISymbolStore.FindResolvedCallers, DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsWithFacts, DRagLint.Core.Interfaces.ISymbolStore.GetAllFileIds, DRagLint.Core.Interfaces.ISymbolStore.GetFilePath, DRagLint.Diagnostics.ParseCache.TAstParseCache.Get, DRagLint.Lint.EffectRules.AcceptCallSite, DRagLint.Lint.EffectRules.CallNodeOf, DRagLint.Lint.EffectRules.CollectIdentsOnRow, DRagLint.Lint.EffectRules.EnclosingIteratedLoop (+15 more)</para>
/// <para>Returns: Findings.ToArray</para>
/// <para>Complexity: 18 (cyclomatic, outer body), 87 lines (full implementation)</para>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindResolvedCallers"/>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsWithFacts"/>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetAllFileIds"/>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetFilePath"/>
/// <seealso cref="DRagLint.Diagnostics.ParseCache.TAstParseCache.Get"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function CollectEffectFreeInLoopInvariant(const AStore: ISymbolStore;
  AOnlyFileId: Int64): TArray<TLintFinding>;

implementation

uses
  System.Classes
  , System.IOUtils
  , System.StrUtils
  , System.Generics.Defaults
  , TreeSitter
  , DRagLint.Diagnostics.ParseCache
  , DRagLint.Analysis.Purity
  ;

const
  CEffectFreeNotProven = 0;
  CEffectFreeProven    = 1;
  CConfidenceCertain   = 'certain';
  CSeverityInfo        = 'info';
  CSeverityWarning     = 'warning';
  { How many resolved call hops ui-access-in-thread-transitive walks back from a
    UI-touching routine before it gives up. }
  CMaxHops             = 5;

{ ---- shared helpers -------------------------------------------------------- }

{ The file's lines, read once per path; nil when it cannot be read. }
function LinesOf(const APath: string; ACache: TDictionary<string, TArray<string>>): TArray<string>;
begin
  if not ACache.TryGetValue(APath, Result) then
  begin
    try
      Result:= TFile.ReadAllLines(APath, TEncoding.ANSI);
    except  // dl:ok bare-except@8ac3 -- one unreadable file must cost its own findings, never abort the lint run
      Result:= nil;
    end;
    ACache.Add(APath, Result);
  end;
end;

function NodeText(const N: TTSNode; const ASrc: TBytes): string;
begin
  Result:= '';
  if N.IsNull then Exit;
  var S: Integer:= Integer(N.StartByte);
  var L: Integer:= Integer(N.EndByte) - S;
  if (L <= 0) or (S < 0) or (S + L > Length(ASrc)) then Exit;
  Result:= TEncoding.UTF8.GetString(ASrc, S, L);
end;

function SameNode(const A, B: TTSNode): Boolean;
begin
  Result:= (not A.IsNull) and (not B.IsNull) and (A.StartByte = B.StartByte) and
    (A.EndByte = B.EndByte) and (A.NodeType = B.NodeType);
end;

function OperatorOf(const N: TTSNode): string;
begin
  var Op: TTSNode:= N.ChildByField('operator');
  Result:= if Op.IsNull then '' else Op.NodeType;
end;

function Unparen(const N: TTSNode): TTSNode;
begin
  Result:= N;
  while (not Result.IsNull) and (Result.NodeType = 'exprParens') and (Result.NamedChildCount > 0) do
    Result:= Result.NamedChild(0);
end;

{ The identifier that NAMES what an operand calls or reads: `F`, `X.F`,
  `F(..)`, `X.F(..)`. A null node for anything else. }
function CalleeIdentOf(const N: TTSNode): TTSNode;
begin
  Result:= Default(TTSNode);
  if N.IsNull then Exit;
  if N.NodeType = 'identifier' then Exit(N);
  if N.NodeType = 'exprDot' then
  begin
    var R: TTSNode:= N.ChildByField('rhs');
    if (not R.IsNull) and (R.NodeType = 'identifier') then Result:= R;
  end
  else if N.NodeType = 'exprCall' then
    Result:= CalleeIdentOf(N.ChildByField('entity'));
end;

{ Every identifier node on 0-based row ARow whose text is AName. }
procedure CollectIdentsOnRow(const N: TTSNode; ARow: Integer; const AName: string;
  const ASrc: TBytes; AOut: TList<TTSNode>);
begin
  if N.IsNull then Exit;
  if (Integer(N.StartPoint.Row) > ARow) or (Integer(N.EndPoint.Row) < ARow) then Exit;
  if N.NodeType = 'identifier' then
  begin
    if (Integer(N.StartPoint.Row) = ARow) and SameText(NodeText(N, ASrc), AName) then AOut.Add(N);
    Exit;
  end;
  for var I:= 0 to N.NamedChildCount - 1 do
    CollectIdentsOnRow(N.NamedChild(I), ARow, AName, ASrc, AOut);
end;

function IsExprNode(const N: TTSNode): Boolean;
begin
  Result:= StartsStr('expr', N.NodeType) or (N.NodeType = 'identifier');
end;

{ A method's stored signature declares a return type after its parameter list,
  also when it has none (`: Integer`). }
function SignatureReturnsValue(const ASignature: string): Boolean;
begin
  var S: string:= Trim(ASignature);
  var P: Integer:= LastDelimiter(':)', S);
  Result:= (P > 0) and (S[P] = ':');
end;

{ One certain routine call worth judging, seen for the first time and in the
  file asked for. Both call-site rules start here. }
function AcceptCallSite(const AC: TResolvedCaller; ASymId, AOnlyFileId: Int64;
  AFileIdOf: TDictionary<string, Int64>; ASeen: TDictionary<string, Boolean>; out AFileId: Int64): Boolean;
begin
  Result:= False;
  AFileId:= 0;
  if (AC.Mode <> '') or (AC.Confidence <> CConfidenceCertain) then Exit;
  if (AC.FullPath = '') or (AC.CallSiteLine <= 0) then Exit;
  if not AFileIdOf.TryGetValue(AC.FullPath, AFileId) then AFileId:= 0;
  if (AOnlyFileId <> 0) and (AFileId <> AOnlyFileId) then Exit;
  var Key: string:= Format('%s|%d|%d', [AC.FullPath, AC.CallSiteLine, ASymId]);
  if ASeen.ContainsKey(Key) then Exit;
  ASeen.Add(Key, True);
  Result:= True;
end;

function IsBooleanReturn(const ASignature: string): Boolean;
const
  CBoolTypes: array[0..3] of string = ('Boolean', 'ByteBool', 'WordBool', 'LongBool');
begin
  var S: string:= Trim(ASignature);
  if EndsStr(';', S) then S:= Trim(Copy(S, 1, Length(S) - 1));
  var P: Integer:= LastDelimiter(':)', S);
  if (P = 0) or (S[P] <> ':') then Exit(False);
  var T: string:= Trim(Copy(S, P + 1, MaxInt));
  Result:= MatchText(T, CBoolTypes);
end;

{ Is the 0-based parameter AOrdinal of a stored signature declared BY VALUE with a scalar or string type? Writing
  such a parameter (Inc(AIdx)) changes a local copy: the caller never sees it, so it is no effect. var, out and
  const are never by-value here; an array, class, pointer or untyped parameter is not judged (False). }
function IsByValueScalarParam(const ASignature: string; AOrdinal: Integer): Boolean;
const
  CScalarTypes: array[0..21] of string = ('Integer', 'Cardinal', 'Int64', 'UInt64', 'NativeInt', 'NativeUInt',
    'SmallInt', 'ShortInt', 'Byte', 'Word', 'LongInt', 'LongWord', 'Boolean', 'Char', 'string', 'Double',
    'Single', 'Extended', 'Real', 'Currency', 'AnsiChar', 'WideChar');
begin
  Result:= False;
  var S: string:= Trim(ASignature);
  var Open: Integer:= Pos('(', S);
  if Open = 0 then Exit;
  var Depth: Integer:= 0;
  var Groups: TArray<string>:= nil;
  var Cur: string:= '';
  for var I:= Open + 1 to Length(S) do
  begin
    var C: Char:= S[I];
    if (C = '(') or (C = '<') or (C = '[') then Inc(Depth)
    else if ((C = ')') or (C = '>') or (C = ']')) and (Depth > 0) then Dec(Depth)
    else if (C = ')') then
    begin
      Groups:= Groups + [Cur];
      Break;
    end
    else if (C = ';') and (Depth = 0) then
    begin
      Groups:= Groups + [Cur];
      Cur:= '';
      Continue;
    end;
    Cur:= Cur + C;
  end;
  var Index: Integer:= 0;
  for var G in Groups do
  begin
    var Colon: Integer:= Pos(':', G);
    if Colon = 0 then Exit;
    var Names: TArray<string>:= Trim(Copy(G, 1, Colon - 1)).Split([',']);
    var TypeName: string:= Trim(Copy(G, Colon + 1, MaxInt));
    if AOrdinal < Index + Length(Names) then
    begin
      var First: string:= Trim(Names[0]);
      if StartsText('var ', First) or StartsText('out ', First) or StartsText('const ', First) then Exit;
      Exit(MatchText(TypeName, CScalarTypes));
    end;
    Inc(Index, Length(Names));
  end;
end;

{ ---- side-effect-in-short-circuit ------------------------------------------ }

type
  TShortCircuitJudge = record
    Src       : TBytes;
    Callee    : TTSNode;
    BoolCallee: Boolean;
    Binary    : TTSNode;
    function BoolOperand(const N: TTSNode): Boolean;
    function IsCondition(const N: TTSNode): Boolean;
    function BoolProven(const B: TTSNode): Boolean;
    function Guarded: Boolean;
    function IsAccumulator: Boolean;
    function NilGuardsReceiver: Boolean;
  end;

function TShortCircuitJudge.BoolOperand(const N: TTSNode): Boolean;
const
  CRelational: array[0..7] of string = ('kEq', 'kNeq', 'kLt', 'kGt', 'kLte', 'kGte', 'kIn', 'kIs');
  CLogical   : array[0..2] of string = ('kAnd', 'kOr', 'kXor');
begin
  var X: TTSNode:= Unparen(N);
  var T: string:= if X.IsNull then '' else X.NodeType;
  if T = 'exprBinary' then
    Exit(MatchStr(OperatorOf(X), CRelational) or
      (MatchStr(OperatorOf(X), CLogical) and
       (BoolOperand(X.ChildByField('lhs')) or BoolOperand(X.ChildByField('rhs')))));
  if T = 'exprUnary' then
    Exit((OperatorOf(X) = 'kNot') and BoolOperand(X.ChildByField('operand')));
  var IsLiteral : Boolean:= (T = 'kTrue') or (T = 'kFalse');
  var IsAssigned: Boolean:= (T = 'exprCall') and SameText(NodeText(X.ChildByField('entity'), Src), 'Assigned');
  var IsCallee  : Boolean:= (T <> '') and BoolCallee and SameNode(CalleeIdentOf(X), Callee);
  Result:= IsLiteral or IsAssigned or IsCallee;
end;

function TShortCircuitJudge.IsCondition(const N: TTSNode): Boolean;
begin
  var C: TTSNode:= N;
  var P: TTSNode:= C.Parent;
  while (not P.IsNull) and (P.NodeType = 'exprParens') do
  begin
    C:= P;
    P:= P.Parent;
  end;
  if P.IsNull then Exit(False);
  if not MatchStr(P.NodeType, ['if', 'ifElse', 'while', 'repeat', 'exprIf']) then Exit(False);
  Result:= SameNode(P.ChildByField('condition'), C);
end;

function TShortCircuitJudge.BoolProven(const B: TTSNode): Boolean;
begin
  if IsCondition(B) then Exit(True);
  if BoolOperand(B.ChildByField('lhs')) or BoolOperand(B.ChildByField('rhs')) then Exit(True);
  { An operand of an enclosing and/or/xor that is itself proven Boolean. }
  var P: TTSNode:= B.Parent;
  while (not P.IsNull) and (P.NodeType = 'exprParens') do P:= P.Parent;
  Result:= (not P.IsNull) and (P.NodeType = 'exprBinary') and
    MatchStr(OperatorOf(P), ['kAnd', 'kOr', 'kXor']) and BoolProven(P);
end;

function TShortCircuitJudge.Guarded: Boolean;
begin
  Result:= False;
  var N: TTSNode:= Callee;
  var P: TTSNode:= N.Parent;
  while not P.IsNull do
  begin
    if (P.NodeType = 'exprBinary') and MatchStr(OperatorOf(P), ['kAnd', 'kOr']) and
       SameNode(P.ChildByField('rhs'), N) and BoolProven(P) then
    begin
      Binary:= P;
      Exit(True);
    end;
    if not IsExprNode(P) then Exit;
    N:= P;
    P:= N.Parent;
  end;
end;

{ True for `X:= X or F(..)`, also over a chain or in parentheses: the leftmost
  operand of the assigned and/or tree IS the assignment target. Binary is the
  operator Guarded proved. }
function TShortCircuitJudge.IsAccumulator: Boolean;
begin
  var Top: TTSNode:= Binary;
  var P  : TTSNode:= Top.Parent;
  while (not P.IsNull) and ((P.NodeType = 'exprParens') or
        ((P.NodeType = 'exprBinary') and MatchStr(OperatorOf(P), ['kAnd', 'kOr']))) do
  begin
    Top:= P;
    P:= Top.Parent;
  end;
  if P.IsNull or (P.NodeType <> 'assignment') then Exit(False);
  var Left: TTSNode:= Unparen(Top);
  while (not Left.IsNull) and (Left.NodeType = 'exprBinary') and
        MatchStr(OperatorOf(Left), ['kAnd', 'kOr']) do
    Left:= Unparen(Left.ChildByField('lhs'));
  Result:= (not Left.IsNull) and
    SameText(Trim(NodeText(P.ChildByField('lhs'), Src)), Trim(NodeText(Left, Src)));
end;

{ True for `Assigned(R) and .. R.F`, `(R <> nil) and .. R.F`: one of the `and`
  operands left of the call tests the very receiver it is called on. }
function TShortCircuitJudge.NilGuardsReceiver: Boolean;
begin
  Result:= False;
  var Dot: TTSNode:= Callee.Parent;
  if Dot.IsNull or (Dot.NodeType <> 'exprDot') or not SameNode(Dot.ChildByField('rhs'), Callee) then Exit;
  var Rcv: string:= Trim(NodeText(Dot.ChildByField('lhs'), Src));
  if Rcv = '' then Exit;
  var B: TTSNode:= Binary;
  while (not B.IsNull) and (B.NodeType = 'exprBinary') and (OperatorOf(B) = 'kAnd') do
  begin
    var L: TTSNode:= Unparen(B.ChildByField('lhs'));
    var Conj: TTSNode:= L;
    if (not L.IsNull) and (L.NodeType = 'exprBinary') and (OperatorOf(L) = 'kAnd') then
      Conj:= Unparen(L.ChildByField('rhs'));
    if not Conj.IsNull then
    begin
      if (Conj.NodeType = 'exprCall') and SameText(NodeText(Conj.ChildByField('entity'), Src), 'Assigned') then
      begin
        var A: string:= Trim(NodeText(Conj.ChildByField('args'), Src));
        if A.StartsWith('(') and A.EndsWith(')') then A:= Trim(Copy(A, 2, Length(A) - 2));
        if SameText(A, Rcv) then Exit(True);
      end
      else if (Conj.NodeType = 'exprBinary') and (OperatorOf(Conj) = 'kNeq') and
              (Conj.ChildByField('rhs').NodeType = 'kNil') and
              SameText(Trim(NodeText(Conj.ChildByField('lhs'), Src)), Rcv) then
        Exit(True);
    end;
    B:= L;
  end;
end;

{ True for `TryFoo`, not for `Tryst`: the word after Try starts a new word. }
function IsTryName(const AName: string): Boolean;
const
  CTryLen = Length('Try');
begin
  Result:= StartsText('Try', AName) and (Length(AName) > CTryLen) and
    CharInSet(AName[CTryLen + 1], ['A'..'Z', '_']);
end;

function IsMemoRoutine(const ARoot: TTSNode; const ASrc: TBytes; const ARoutine: TSymbol): Boolean; forward;

{ The callee-level half of the deliberate-short-circuit exemption; see the
  remarks on CollectSideEffectInShortCircuit. The parse happens last and only
  for a callee that could be a memo. }
function CalleeIsDeliberate(const AStore: ISymbolStore; const ASym: TSymbol; const ASum: TEffectSummary;
  const AWitness: string; ABoolRet: Boolean): Boolean;
const
  CSqlReadWitness = 'reads SQL ';
begin
  if ABoolRet and (IsTryName(ASym.Name) or (ASum.Flags * [efGlobal, efHeap, efSelfFields] = [])) then Exit(True);
  var StateOnly: Boolean:= (Length(ASum.Params) = 0) and (efHeap not in ASum.Flags);
  if StateOnly and (efSelfFields not in ASum.Flags) and StartsStr(CSqlReadWitness, AWitness) then Exit(True);
  if (not StateOnly) or (ASym.ImplStartLine <= 0) or ASym.Signature.Contains('(') then Exit(False);
  var PF: TParsedFile:= TAstParseCache.Get(AStore.GetFilePath(ASym.FileId));
  Result:= (PF.Tree <> nil) and IsMemoRoutine(PF.Tree.RootNode, PF.Src, ASym);
end;

{ Cheap pre-filter before any parse: the word `and` or `or` on the call line
  or the CWrapLines above it (a wrapped condition). False = cannot fire. }
function AndOrNear(const ALines: TArray<string>; ALine: Integer): Boolean;
const
  CWrapLines = 3;
  CWordChars: TSysCharSet = ['A'..'Z', 'a'..'z', '0'..'9', '_'];
begin
  if (ALines = nil) or (ALine > Length(ALines)) then Exit(False);
  for var Ln:= (if ALine > CWrapLines then ALine - CWrapLines else 1) to ALine do
  begin
    var S: string:= ALines[Ln - 1];
    var I: Integer:= 1;
    while I <= Length(S) do
    begin
      if not CharInSet(S[I], CWordChars) then
      begin
        Inc(I);
        Continue;
      end;
      var W: Integer:= I;
      while (I <= Length(S)) and CharInSet(S[I], CWordChars) do Inc(I);
      var Word: string:= Copy(S, W, I - W);
      if SameText(Word, 'and') or SameText(Word, 'or') then Exit(True);
    end;
  end;
  Result:= False;
end;

function HasCompleteBoolEval(const ARaw: TBytes): Boolean;
begin
  var S: string:= UpperCase(TEncoding.ANSI.GetString(ARaw));
  Result:= ContainsStr(S, '{$B+') or ContainsStr(S, '{$BOOLEVAL ON');
end;

function CollectSideEffectInShortCircuit(const AStore: ISymbolStore;
  AOnlyFileId: Int64): TArray<TLintFinding>;
var
  Findings: TList<TLintFinding>;
  Facts   : TDictionary<Int64, TSymbolFacts>;
  FileIdOf: TDictionary<string, Int64>;
  Seen    : TDictionary<string, Boolean>;
  Idents  : TList<TTSNode>;
  LineCache: TDictionary<string, TArray<string>>;
begin
  Findings:= TList<TLintFinding>.Create;
  Facts   := TDictionary<Int64, TSymbolFacts>.Create;
  FileIdOf:= TDictionary<string, Int64>.Create(TIStringComparer.Ordinal);
  Seen    := TDictionary<string, Boolean>.Create;
  Idents  := TList<TTSNode>.Create;
  LineCache:= TDictionary<string, TArray<string>>.Create;
  try
    for var Fi in AStore.GetAllFileIds do
      FileIdOf.AddOrSetValue(AStore.GetFilePath(Fi), Fi);
    for var F in AStore.GetAllSymbolFacts do Facts.AddOrSetValue(F.SymbolId, F);
    for var Sym in AStore.FindSymbolsWithFacts do
    begin
      var SF: TSymbolFacts;
      if (not Facts.TryGetValue(Sym.Id, SF)) or (SF.EffectFree <> CEffectFreeNotProven) then Continue;
      var Sum: TEffectSummary:= TEffectSummary.Decode(SF.EffectSummary);
      { A write to a by-value scalar parameter is local (Inc(AIdx)); a heap flag beside a '?' is a gap in the
        proof, not a proven effect. Neither alone is an effect worth a finding. }
      var Written: TArray<Integer>:= nil;
      for var PIdx in Sum.Params do
        if not IsByValueScalarParam(Sym.Signature, PIdx) then Written:= Written + [PIdx];
      if (Sum.Flags * [efGlobal, efSelfFields] = []) and (Length(Written) = 0)
        and ((efHeap not in Sum.Flags) or (efUnknown in Sum.Flags)) then Continue;
      var BoolRet: Boolean:= IsBooleanReturn(Sym.Signature);
      var Deliberate: Boolean:= CalleeIsDeliberate(AStore, Sym, Sum, SF.EffectWitness, BoolRet);
      for var C in AStore.FindResolvedCallers(Sym.Id) do
      begin
        var FileId: Int64;
        if not AcceptCallSite(C, Sym.Id, AOnlyFileId, FileIdOf, Seen, FileId) then Continue;
        if not AndOrNear(LinesOf(C.FullPath, LineCache), C.CallSiteLine) then Continue;
        { Get answers Tree = nil for a missing or unreadable file. }
        var PF: TParsedFile:= TAstParseCache.Get(C.FullPath);
        if (PF.Tree = nil) or HasCompleteBoolEval(PF.RawSrc) then Continue;
        Idents.Clear;
        CollectIdentsOnRow(PF.Tree.RootNode, C.CallSiteLine - 1, Sym.Name, PF.Src, Idents);
        if Idents.Count = 0 then Continue;
        var AllGuarded: Boolean:= True;
        var AnyAccidental: Boolean:= False;
        for var Id in Idents do
        begin
          var J: TShortCircuitJudge;
          J.Src       := PF.Src;
          J.Callee    := Id;
          J.BoolCallee:= BoolRet;
          if not J.Guarded then
          begin
            AllGuarded:= False;
            Break;
          end;
          if J.IsAccumulator or ((not Deliberate) and (not J.NilGuardsReceiver)) then
            AnyAccidental:= True;
        end;
        if (not AllGuarded) or (not AnyAccidental) then Continue;
        var Fd: TLintFinding:= Default(TLintFinding);
        Fd.RuleId    := SIDE_EFFECT_IN_SHORT_CIRCUIT_RULE;
        Fd.FilePath  := C.FullPath;
        Fd.FileId    := FileId;
        Fd.StartLine := C.CallSiteLine;
        Fd.EndLine   := C.CallSiteLine;
        Fd.StartCol  := Integer(Idents[0].StartPoint.Column) + 1;
        Fd.EndCol    := Fd.StartCol + Length(Sym.Name);
        Fd.Severity  := CSeverityInfo;
        Fd.SymbolName:= Sym.Name;
        Fd.Message   := Format(
          '%s is called in the right operand of a short-circuit and/or and has an effect ' +
          '(effect_summary ''%s'': %s) -- it runs only when the left operand does not decide the result',
          [Sym.QualifiedName, SF.EffectSummary, SF.EffectWitness]);
        Findings.Add(Fd);
      end;
    end;
    Result:= Findings.ToArray;
  finally
    LineCache.Free;
    Idents.Free;
    Seen.Free;
    FileIdOf.Free;
    Facts.Free;
    Findings.Free;
  end;
end; // function

{ ---- property-getter-with-effect ------------------------------------------- }

{ The class a declProp belongs to: the name of its nearest declType ancestor,
  generic argument list stripped. '' when there is none. }
function OwningTypeName(const AProp: TTSNode; const ASrc: TBytes): string;
begin
  Result:= '';
  var P: TTSNode:= AProp.Parent;
  while not P.IsNull do
  begin
    if P.NodeType = 'declType' then
    begin
      Result:= Trim(NodeText(P.ChildByField('name'), ASrc));
      var Lt: Integer:= Pos('<', Result);
      if Lt > 0 then Result:= Trim(Copy(Result, 1, Lt - 1));
      Exit;
    end;
    P:= P.Parent;
  end;
end;

procedure CollectNodesOfType(const N: TTSNode; const AType: string; AOut: TList<TTSNode>);
begin
  if N.IsNull then Exit;
  if N.NodeType = AType then AOut.Add(N);
  for var I:= 0 to N.NamedChildCount - 1 do
    CollectNodesOfType(N.NamedChild(I), AType, AOut);
end;

function FindDefProcAt(const ARoot: TTSNode; ARow: Integer): TTSNode;
begin
  Result:= Default(TTSNode);
  if ARoot.IsNull then Exit;
  if (Integer(ARoot.StartPoint.Row) > ARow) or (Integer(ARoot.EndPoint.Row) < ARow) then Exit;
  if (ARoot.NodeType = 'defProc') and (Integer(ARoot.StartPoint.Row) = ARow) then Exit(ARoot);
  for var I:= 0 to ARoot.NamedChildCount - 1 do
  begin
    Result:= FindDefProcAt(ARoot.NamedChild(I), ARow);
    if not Result.IsNull then Exit;
  end;
end;

{ True when the condition subtree tests nil, calls Assigned, or names one of
  AAssigned (lowercase). }
function ConditionGuards(const N: TTSNode; const ASrc: TBytes; AAssigned: TDictionary<string, Boolean>): Boolean;
begin
  if N.IsNull then Exit(False);
  if N.NodeType = 'kNil' then Exit(True);
  if N.NodeType = 'identifier' then
  begin
    var T: string:= LowerCase(NodeText(N, ASrc));
    Exit((T = 'assigned') or AAssigned.ContainsKey(T));
  end;
  for var I:= 0 to N.NamedChildCount - 1 do
    if ConditionGuards(N.NamedChild(I), ASrc, AAssigned) then Exit(True);
  Result:= False;
end;

function IsLazyInitGetter(const ARoot: TTSNode; const ASrc: TBytes; const AGetter: TSymbol): Boolean;
const
  CCondNodes: array[0..3] of string = ('if', 'ifElse', 'while', 'repeat');
var
  AssignedNames: TDictionary<string, Boolean>;
  Nodes    : TList<TTSNode>;
begin
  Result:= False;
  var Proc: TTSNode:= FindDefProcAt(ARoot, AGetter.ImplStartLine - 1);
  if Proc.IsNull then Exit;
  var Body: TTSNode:= Proc.ChildByField('body');
  if Body.IsNull then Exit;
  AssignedNames:= TDictionary<string, Boolean>.Create;
  Nodes    := TList<TTSNode>.Create;
  try
    CollectNodesOfType(Body, 'assignment', Nodes);
    for var A in Nodes do
    begin
      var L: string:= LowerCase(Trim(NodeText(A.ChildByField('lhs'), ASrc)));
      if StartsStr('self.', L) then L:= Copy(L, Length('self.') + 1, MaxInt);
      if (L <> '') and (L <> 'result') and not SameText(L, AGetter.Name) then
        AssignedNames.AddOrSetValue(L, True);
    end;
    for var T in CCondNodes do
    begin
      Nodes.Clear;
      CollectNodesOfType(Body, T, Nodes);
      for var C in Nodes do
        if ConditionGuards(C.ChildByField('condition'), ASrc, AssignedNames) then Exit(True);
    end;
  finally
    Nodes.Free;
    AssignedNames.Free;
  end;
end;

{ Stricter than IsLazyInitGetter, for a routine that is NOT a getter: besides the
  guarding condition, EVERY assignment other than to Result sits under an `if`
  that tests nil, Assigned or what the body assigns. A stream's Write tests the
  size it grows but moves its position unconditionally, so it is no memo. }
function IsMemoRoutine(const ARoot: TTSNode; const ASrc: TBytes; const ARoutine: TSymbol): Boolean;
var
  AssignedNames: TDictionary<string, Boolean>;
  Nodes        : TList<TTSNode>;
begin
  Result:= False;
  if not IsLazyInitGetter(ARoot, ASrc, ARoutine) then Exit;
  var Proc: TTSNode:= FindDefProcAt(ARoot, ARoutine.ImplStartLine - 1);
  var Body: TTSNode:= Proc.ChildByField('body');
  AssignedNames:= TDictionary<string, Boolean>.Create;
  Nodes        := TList<TTSNode>.Create;
  try
    CollectNodesOfType(Body, 'assignment', Nodes);
    var Writes: TArray<TTSNode>:= nil;
    for var A in Nodes do
    begin
      var L: string:= LowerCase(Trim(NodeText(A.ChildByField('lhs'), ASrc)));
      if StartsStr('self.', L) then L:= Copy(L, Length('self.') + 1, MaxInt);
      if (L = '') or (L = 'result') or SameText(L, ARoutine.Name) then Continue;
      AssignedNames.AddOrSetValue(L, True);
      Writes:= Writes + [A];
    end;
    for var W in Writes do
    begin
      var Guarded: Boolean:= False;
      var P: TTSNode:= W.Parent;
      while (not P.IsNull) and (not SameNode(P, Body)) and not Guarded do
      begin
        Guarded:= MatchStr(P.NodeType, ['if', 'ifElse']) and
          ConditionGuards(P.ChildByField('condition'), ASrc, AssignedNames);
        P:= P.Parent;
      end;
      if not Guarded then Exit;
    end;
    Result:= True;
  finally
    Nodes.Free;
    AssignedNames.Free;
  end;
end;

function CollectPropertyGetterWithEffect(const AStore: ISymbolStore;
  AOnlyFileId: Int64): TArray<TLintFinding>;
var
  Findings: TList<TLintFinding>;
  Facts   : TDictionary<Int64, TSymbolFacts>;
  ByFile  : TObjectDictionary<Int64, TDictionary<string, TSymbol>>;
  Props   : TList<TTSNode>;
begin
  Findings:= TList<TLintFinding>.Create;
  Facts   := TDictionary<Int64, TSymbolFacts>.Create;
  ByFile  := TObjectDictionary<Int64, TDictionary<string, TSymbol>>.Create([doOwnsValues]);
  Props   := TList<TTSNode>.Create;
  try
    for var F in AStore.GetAllSymbolFacts do Facts.AddOrSetValue(F.SymbolId, F);
    { Candidate getters: a proven s or g write, keyed per file by the
      lowercase `TClass.Getter` tail of their qualified name. }
    for var Sym in AStore.FindSymbolsWithFacts do
    begin
      if (AOnlyFileId <> 0) and (Sym.FileId <> AOnlyFileId) then Continue;
      var SF: TSymbolFacts;
      if not Facts.TryGetValue(Sym.Id, SF) or (SF.EffectFree <> CEffectFreeNotProven) then Continue;
      if TEffectSummary.Decode(SF.EffectSummary).Flags * [efGlobal, efSelfFields] = [] then Continue;
      var Parts: TArray<string>:= Sym.QualifiedName.Split(['.']);
      if Length(Parts) < 2 then Continue;
      var Map: TDictionary<string, TSymbol>;
      if not ByFile.TryGetValue(Sym.FileId, Map) then
      begin
        Map:= TDictionary<string, TSymbol>.Create;
        ByFile.Add(Sym.FileId, Map);
      end;
      Map.AddOrSetValue(LowerCase(Parts[High(Parts) - 1] + '.' + Parts[High(Parts)]), Sym);
    end;
    for var Pair in ByFile do
    begin
      var Path: string:= AStore.GetFilePath(Pair.Key);
      if Path = '' then Continue;
      var PF: TParsedFile:= TAstParseCache.Get(Path);
      if PF.Tree = nil then Continue;
      Props.Clear;
      CollectNodesOfType(PF.Tree.RootNode, 'declProp', Props);
      for var P in Props do
      begin
        var G: TTSNode:= P.ChildByField('getter');
        if G.IsNull or (G.NodeType <> 'identifier') then Continue;
        var GName: string:= NodeText(G, PF.Src);
        var Cls  : string:= OwningTypeName(P, PF.Src);
        if Cls = '' then Continue;
        var Getter: TSymbol;
        if not Pair.Value.TryGetValue(LowerCase(Cls + '.' + GName), Getter) then Continue;
        if IsLazyInitGetter(PF.Tree.RootNode, PF.Src, Getter) then Continue;
        var SF: TSymbolFacts:= Facts[Getter.Id];
        var PName: string:= NodeText(P.ChildByField('name'), PF.Src);
        var Fd: TLintFinding:= Default(TLintFinding);
        Fd.RuleId    := PROPERTY_GETTER_WITH_EFFECT_RULE;
        Fd.FilePath  := Path;
        Fd.FileId    := Pair.Key;
        Fd.StartLine := Integer(P.StartPoint.Row) + 1;
        Fd.EndLine   := Fd.StartLine;
        Fd.StartCol  := Integer(P.StartPoint.Column) + 1;
        Fd.EndCol    := Fd.StartCol + Length(PName);
        Fd.Severity  := CSeverityInfo;
        Fd.SymbolName:= PName;
        Fd.Message   := Format(
          'property %s.%s reads through %s, which changes state (effect_summary ''%s'': %s) ' +
          '-- reading a property should not have an effect',
          [Cls, PName, GName, SF.EffectSummary, SF.EffectWitness]);
        Findings.Add(Fd);
      end;
    end;
    Result:= Findings.ToArray;
  finally
    Props.Free;
    ByFile.Free;
    Facts.Free;
    Findings.Free;
  end;
end; // function

{ ---- effect-free-in-loop-invariant ------------------------------------------ }

type
  { What a bare name can be, from every symbol the project declares under it. }
  TLoopNameClass = (
    lncUnknown,   { no symbol: RTL, library, inherited -- could be anything }
    lncConstant,  { const, enum value, type or unit: cannot change }
    lncData,      { field, var, property: state a write can change }
    lncProven,    { every routine of the name is proven effect-free }
    lncOther);    { a routine not proven, or a mix }

  { What one loop can change. }
  TLoopChanges = record
    Written : TDictionary<string, Boolean>; { lowercase; caller owns }
    Frozen  : Boolean;                      { writes only locals, calls only proven routines }
    Rejected: Boolean;                      { with / asm: nothing is known }
  end;

  TLoopInvariantRun = class
  strict private
    FStore    : ISymbolStore;
    FFacts    : TDictionary<Int64, TSymbolFacts>;
    FNames    : TDictionary<string, TLoopNameClass>;
    FStateless: TDictionary<Int64, Boolean>;
    function ReadsNoState(const N: TTSNode; const ASrc: TBytes; ALocals: TDictionary<string, Boolean>): Boolean;
    procedure WalkLoop(const N: TTSNode; const ASrc: TBytes; ALocals: TDictionary<string, Boolean>; var AChanges: TLoopChanges);
    procedure WalkCall(const AIdent, ANode: TTSNode; const ASrc: TBytes; ALocals: TDictionary<string, Boolean>; var AChanges: TLoopChanges);
  public
    constructor Create(const AStore: ISymbolStore);
    destructor Destroy; override;
    procedure LoadFacts;
    function SymbolFacts(AId: Int64; out AFacts: TSymbolFacts): Boolean;
    function ClassifyName(const ALowerName: string): TLoopNameClass;
    procedure CollectLocals(const AProc: TTSNode; const ASrc: TBytes; ALocals: TDictionary<string, Boolean>);
    function AnalyzeLoop(const ALoop: TTSNode; const ASrc: TBytes; ALocals: TDictionary<string, Boolean>; AWritten: TDictionary<string, Boolean>): TLoopChanges;
    function CalleeReadsNoState(const ASym: TSymbol): Boolean;
    function NameInvariant(const ALc: string; ALocals: TDictionary<string, Boolean>; const AChanges: TLoopChanges): Boolean;
    function Invariant(const N, ACallee, ACall, AOwnDot: TTSNode; const ASrc: TBytes; ALocals: TDictionary<string, Boolean>; const AChanges: TLoopChanges): Boolean;
  end;

{ Intrinsics and RTL routines that depend on their arguments alone and write no
  parameter. ClassifyName lets a project routine of the same name win. }
function IsStatelessRtl(const AName: string): Boolean;
const
  CStateless: array[0..31] of string = ('abs', 'assigned', 'ceil', 'charinset', 'chr', 'comparestr',
    'comparetext', 'copy', 'floor', 'high', 'inttostr', 'length', 'low', 'lowercase', 'max', 'min',
    'odd', 'ord', 'pos', 'pred', 'round', 'samestr', 'sametext', 'sizeof', 'sqr', 'succ', 'trim',
    'trimleft', 'trimright', 'trunc', 'uppercase', 'startstext');
begin
  Result:= MatchStr(AName, CStateless);
end;

function HasAddressOf(const N: TTSNode): Boolean;
begin
  Result:= False;
  if N.NodeType <> 'exprUnary' then Exit;
  for var I:= 0 to N.ChildCount - 1 do
    if N.Child(I).NodeType = 'kAt' then Exit(True);
end;

procedure MarkAll(const N: TTSNode; const ASrc: TBytes; AOut: TDictionary<string, Boolean>);
begin
  if N.IsNull then Exit;
  if N.NodeType = 'identifier' then AOut.AddOrSetValue(LowerCase(NodeText(N, ASrc)), True);
  for var I:= 0 to N.NamedChildCount - 1 do MarkAll(N.NamedChild(I), ASrc, AOut);
end;

procedure RemoveAddressTaken(const N: TTSNode; const ASrc: TBytes; ALocals: TDictionary<string, Boolean>);
begin
  if N.IsNull then Exit;
  if HasAddressOf(N) then
  begin
    var Taken: TDictionary<string, Boolean>:= TDictionary<string, Boolean>.Create;
    try
      MarkAll(N, ASrc, Taken);
      for var K in Taken.Keys do ALocals.Remove(K);
    finally
      Taken.Free;
    end;
  end;
  for var I:= 0 to N.NamedChildCount - 1 do RemoveAddressTaken(N.NamedChild(I), ASrc, ALocals);
end;

{ A bare local, or a subscript of one: no dot, deref or call in the store. }
function LocalStore(const N: TTSNode; const ASrc: TBytes; ALocals: TDictionary<string, Boolean>): Boolean;
begin
  var X: TTSNode:= Unparen(N);
  if X.IsNull then Exit(False);
  if X.NodeType = 'identifier' then Exit(ALocals.ContainsKey(LowerCase(NodeText(X, ASrc))));
  Result:= (X.NodeType = 'exprSubscript') and LocalStore(X.ChildByField('entity'), ASrc, ALocals);
end;

constructor TLoopInvariantRun.Create(const AStore: ISymbolStore);
begin
  inherited Create;
  FStore    := AStore;
  FFacts    := TDictionary<Int64, TSymbolFacts>.Create;
  FNames    := TDictionary<string, TLoopNameClass>.Create;
  FStateless:= TDictionary<Int64, Boolean>.Create;
end;

destructor TLoopInvariantRun.Destroy;
begin
  FStateless.Free;
  FNames.Free;
  FFacts.Free;
  inherited Destroy;
end;

procedure TLoopInvariantRun.LoadFacts;
begin
  for var F in FStore.GetAllSymbolFacts do FFacts.AddOrSetValue(F.SymbolId, F);
end;

function TLoopInvariantRun.SymbolFacts(AId: Int64; out AFacts: TSymbolFacts): Boolean;
begin
  Result:= FFacts.TryGetValue(AId, AFacts);
end;

function TLoopInvariantRun.ClassifyName(const ALowerName: string): TLoopNameClass;
begin
  if FNames.TryGetValue(ALowerName, Result) then Exit;
  Result:= lncUnknown;
  for var S in FStore.FindSymbolsByExactName(ALowerName) do
    begin
      var One: TLoopNameClass;
      case S.Kind of
        skUnit, skClass, skInterface, skRecord, skEnum, skEnumValue, skConstDecl, skTypeAlias: One:= lncConstant;
        skField, skVarDecl, skProperty, skComponent: One:= lncData;
        skFunction, skMethod:
          begin
            var F: TSymbolFacts;
            One:= if FFacts.TryGetValue(S.Id, F) and (F.EffectFree = CEffectFreeProven) then lncProven else lncOther;
          end;
        skProcedure, skConstructor, skDestructor: One:= lncOther;
      else
        Continue; { a local or parameter of some other routine says nothing here }
      end;
      if Result = lncUnknown then Result:= One
      else if Result <> One then
        { Constant beside data is data; a routine beside anything else is not proven. }
        Result:= if (Result in [lncConstant, lncData]) and (One in [lncConstant, lncData]) then lncData else lncOther;
    end;
  { A field called Pos does not stop Pos(..) being the RTL's; a routine called Pos does. }
  if (Result in [lncUnknown, lncData, lncConstant]) and IsStatelessRtl(ALowerName) then Result:= lncProven;
  FNames.Add(ALowerName, Result);
end;

{ Fills ALocals with the routine's by-value parameters, its variables, Result and
  Self. A name a nested routine or closure mentions is left out, because a call
  in the loop can write it there, and so is a var / out parameter: it may alias
  state. }
procedure TLoopInvariantRun.CollectLocals(const AProc: TTSNode; const ASrc: TBytes; ALocals: TDictionary<string, Boolean>);
var
  Nested: TDictionary<string, Boolean>;

  procedure Walk(const N: TTSNode);
  begin
    if N.IsNull then Exit;
    var T: string:= N.NodeType;
    if (T = 'lambda') or ((T = 'defProc') and not SameNode(N, AProc)) then
    begin
      MarkAll(N, ASrc, Nested);
      Exit;
    end;
    if (T = 'declArg') or (T = 'declVar') then
    begin
      var ByRef: Boolean:= False;
      for var I:= 0 to N.ChildCount - 1 do
        if (N.Child(I).NodeType = 'kVar') or (N.Child(I).NodeType = 'kOut') then ByRef:= True;
      var Ty: TTSNode:= N.ChildByField('type');
      if (not ByRef) and (not Ty.IsNull) then
        for var I:= 0 to N.NamedChildCount - 1 do
        begin
          var Ch: TTSNode:= N.NamedChild(I);
          if (Ch.NodeType = 'identifier') and (Ch.StartByte < Ty.StartByte) then
            ALocals.AddOrSetValue(LowerCase(NodeText(Ch, ASrc)), True);
        end;
      Exit;
    end;
    if (T = 'varDef') or (T = 'varAssignDef') then
      for var I:= 0 to N.NamedChildCount - 1 do
        if N.NamedChild(I).NodeType = 'identifier' then
        begin
          ALocals.AddOrSetValue(LowerCase(NodeText(N.NamedChild(I), ASrc)), True);
          Break;
        end;
    for var I:= 0 to N.NamedChildCount - 1 do Walk(N.NamedChild(I));
  end;

begin
  Nested:= TDictionary<string, Boolean>.Create;
  try
    Walk(AProc);
    for var K in Nested.Keys do ALocals.Remove(K);
  finally
    Nested.Free;
  end;
  ALocals.AddOrSetValue('result', True);
  ALocals.AddOrSetValue('self', True);
  RemoveAddressTaken(AProc, ASrc, ALocals);
end;

{ One call in the loop, with or without an argument list. }
procedure TLoopInvariantRun.WalkCall(const AIdent, ANode: TTSNode; const ASrc: TBytes;
  ALocals: TDictionary<string, Boolean>; var AChanges: TLoopChanges);
const
  CStepRoutines: array[0..3] of string = ('dec', 'exclude', 'inc', 'include');
  CFlow        : array[0..2] of string = ('break', 'continue', 'exit');
begin
  var Name: string:= if AIdent.IsNull then '' else LowerCase(NodeText(AIdent, ASrc));
  var Args: TTSNode:= if ANode.NodeType = 'exprCall' then ANode.ChildByField('args') else Default(TTSNode);
  if MatchStr(Name, CFlow) and (ANode.NodeType <> 'exprDot') then
  begin
    WalkLoop(Args, ASrc, ALocals, AChanges);
    Exit;
  end;
  if MatchStr(Name, CStepRoutines) and (not Args.IsNull) and (Args.NamedChildCount > 0) then
  begin
    MarkAll(Args, ASrc, AChanges.Written);
    if not LocalStore(Args.NamedChild(0), ASrc, ALocals) then AChanges.Frozen:= False;
    WalkLoop(Args, ASrc, ALocals, AChanges);
    Exit;
  end;
  var Proven: Boolean:= (Name <> '') and (not ALocals.ContainsKey(Name)) and
    (ClassifyName(Name) in [lncProven, lncConstant]);
  if not Proven then
  begin
    AChanges.Frozen:= False;
    { Maybe a var parameter, maybe a record method: its receiver and arguments may change. }
    MarkAll(ANode, ASrc, AChanges.Written);
  end;
  { The name itself was judged here; only what surrounds it is left to walk. }
  var Ent: TTSNode:= if ANode.NodeType = 'exprCall' then ANode.ChildByField('entity') else ANode;
  if Ent.NodeType = 'exprDot' then WalkLoop(Ent.ChildByField('lhs'), ASrc, ALocals, AChanges);
  WalkLoop(Args, ASrc, ALocals, AChanges);
end;

procedure TLoopInvariantRun.WalkLoop(const N: TTSNode; const ASrc: TBytes;
  ALocals: TDictionary<string, Boolean>; var AChanges: TLoopChanges);
begin
  if N.IsNull or AChanges.Rejected then Exit;
  var T: string:= N.NodeType;
  if (T = 'with') or (T = 'asm') then AChanges.Rejected:= True
  else if T = 'assignment' then
  begin
    var Lhs: TTSNode:= N.ChildByField('lhs');
    MarkAll(Lhs, ASrc, AChanges.Written);
    if not LocalStore(Lhs, ASrc, ALocals) then AChanges.Frozen:= False;
    if Unparen(Lhs).NodeType = 'exprSubscript' then
      WalkLoop(Unparen(Lhs).ChildByField('args'), ASrc, ALocals, AChanges);
    WalkLoop(N.ChildByField('rhs'), ASrc, ALocals, AChanges);
  end
  else if T = 'exprCall' then WalkCall(CalleeIdentOf(N), N, ASrc, ALocals, AChanges)
  else if (T = 'statement') and (N.NamedChildCount = 1) and
          MatchStr(N.NamedChild(0).NodeType, ['identifier', 'exprDot']) then
    { A statement that is only a name is a parenless call. }
    WalkCall(CalleeIdentOf(N.NamedChild(0)), N.NamedChild(0), ASrc, ALocals, AChanges)
  else if (T = 'exprDot') and SameText(NodeText(N.ChildByField('rhs'), ASrc), 'Count') then
    { List.Count is a read in every library this code sees; only what it is read from is left. }
    WalkLoop(N.ChildByField('lhs'), ASrc, ALocals, AChanges)
  else if T = 'identifier' then
  begin
    var Lc: string:= LowerCase(NodeText(N, ASrc));
    { A name that may be a parenless call the index did not bind stops the proof. }
    if (not ALocals.ContainsKey(Lc)) and (ClassifyName(Lc) not in [lncConstant, lncData, lncProven]) then
      AChanges.Frozen:= False;
  end
  else
  begin
    if HasAddressOf(N) then
    begin
      AChanges.Frozen:= False;
      MarkAll(N, ASrc, AChanges.Written);
    end;
    if (T = 'foreach') or (T = 'varDef') or (T = 'varAssignDef') then
      for var I:= 0 to N.NamedChildCount - 1 do
        if N.NamedChild(I).NodeType = 'identifier' then
        begin
          var Lc: string:= LowerCase(NodeText(N.NamedChild(I), ASrc));
          AChanges.Written.AddOrSetValue(Lc, True);
          if not ALocals.ContainsKey(Lc) then AChanges.Frozen:= False;
        end;
    if T = 'for' then
    begin
      var LoopVar: TTSNode:= N.ChildByField('start').ChildByField('lhs');
      MarkAll(LoopVar, ASrc, AChanges.Written);
      if not LocalStore(LoopVar, ASrc, ALocals) then AChanges.Frozen:= False;
    end;
    for var I:= 0 to N.NamedChildCount - 1 do
      WalkLoop(N.NamedChild(I), ASrc, ALocals, AChanges);
  end;
end;
function TLoopInvariantRun.AnalyzeLoop(const ALoop: TTSNode; const ASrc: TBytes;
  ALocals: TDictionary<string, Boolean>; AWritten: TDictionary<string, Boolean>): TLoopChanges;
begin
  Result:= Default(TLoopChanges);
  Result.Written:= AWritten;
  Result.Frozen := True;
  WalkLoop(ALoop, ASrc, ALocals, Result);
end;

{ True when no name under N is anything but a by-value local, a constant or a
  stateless intrinsic, and nothing reaches through a dot, subscript or deref. }
function TLoopInvariantRun.ReadsNoState(const N: TTSNode; const ASrc: TBytes; ALocals: TDictionary<string, Boolean>): Boolean;
begin
  Result:= True;
  if N.IsNull then Exit;
  var T: string:= N.NodeType;
  if (T = 'exprDot') or (T = 'exprSubscript') or (T = 'with') or (T = 'asm') or HasAddressOf(N) then Exit(False);
  if (T = 'exprUnary') and not MatchStr(OperatorOf(N), ['kNot', 'kSub', 'kAdd']) then Exit(False);
  if T = 'identifier' then
  begin
    var Lc: string:= LowerCase(NodeText(N, ASrc));
    Exit(ALocals.ContainsKey(Lc) or IsStatelessRtl(Lc) or (ClassifyName(Lc) = lncConstant));
  end;
  for var I:= 0 to N.NamedChildCount - 1 do
    if not ReadsNoState(N.NamedChild(I), ASrc, ALocals) then Exit(False);
end;

function TLoopInvariantRun.CalleeReadsNoState(const ASym: TSymbol): Boolean;
var
  Locals: TDictionary<string, Boolean>;
begin
  if FStateless.TryGetValue(ASym.Id, Result) then Exit;
  Result:= False;
  var PF: TParsedFile:= TAstParseCache.Get(FStore.GetFilePath(ASym.FileId));
  if (PF.Tree <> nil) and (ASym.ImplStartLine > 0) then
  begin
    var Proc: TTSNode:= FindDefProcAt(PF.Tree.RootNode, ASym.ImplStartLine - 1);
    Locals:= TDictionary<string, Boolean>.Create;
    try
      if not Proc.IsNull then
      begin
        CollectLocals(Proc, PF.Src, Locals);
        Locals.AddOrSetValue(LowerCase(ASym.Name), True);
        Locals.Remove('self');
        Result:= ReadsNoState(Proc.ChildByField('body'), PF.Src, Locals);
      end;
    finally
      Locals.Free;
    end;
  end;
  FStateless.Add(ASym.Id, Result);
end;

{ A name under the call: not changed by the loop, and a local or a constant --
  or, in a frozen loop, anything the proof already vouched for. }
function TLoopInvariantRun.NameInvariant(const ALc: string; ALocals: TDictionary<string, Boolean>;
  const AChanges: TLoopChanges): Boolean;
begin
  if AChanges.Written.ContainsKey(ALc) then Exit(False);
  if ALocals.ContainsKey(ALc) then Exit(True);
  var Cl: TLoopNameClass:= ClassifyName(ALc);
  Result:= (Cl = lncConstant) or (AChanges.Frozen and (Cl in [lncData, lncProven]));
end;

{ True for the expression shapes that read nothing but their own operands. }
function ReadsOperandsOnly(const N: TTSNode): Boolean;
begin
  var T: string:= N.NodeType;
  if T = 'exprUnary' then Exit(MatchStr(OperatorOf(N), ['kNot', 'kSub', 'kAdd']));
  Result:= (N.NamedChildCount = 0) or MatchStr(T, ['exprBinary', 'exprParens', 'exprArgs']);
end;

{ True when the subtree of the call (arguments and receiver) cannot answer
  differently on a later iteration. ACallee is the callee's own identifier;
  ACall / AOwnDot are the call's own nodes, which any proof may pass through. }
function TLoopInvariantRun.Invariant(const N, ACallee, ACall, AOwnDot: TTSNode; const ASrc: TBytes;
  ALocals: TDictionary<string, Boolean>; const AChanges: TLoopChanges): Boolean;
begin
  if N.IsNull or SameNode(N, ACallee) then Exit(True);
  if HasAddressOf(N) then Exit(False);
  if N.NodeType = 'identifier' then Exit(NameInvariant(LowerCase(NodeText(N, ASrc)), ALocals, AChanges));
  if not (AChanges.Frozen or SameNode(N, ACall) or SameNode(N, AOwnDot) or ReadsOperandsOnly(N)) then Exit(False);
  Result:= True;
  for var I:= 0 to N.NamedChildCount - 1 do
    if not Invariant(N.NamedChild(I), ACallee, ACall, AOwnDot, ASrc, ALocals, AChanges) then Exit(False);
end;
{ The nearest loop whose every iteration runs N; null when there is none or a
  `with` sits anywhere around it (it may rebind any name). }
function EnclosingIteratedLoop(const N: TTSNode; out AProc: TTSNode): TTSNode;
begin
  Result:= Default(TTSNode);
  AProc := Default(TTSNode);
  var C: TTSNode:= N;
  var P: TTSNode:= N.Parent;
  while not P.IsNull do
  begin
    var T: string:= P.NodeType;
    if T = 'with' then Exit(Default(TTSNode));
    if T = 'lambda' then Exit(Default(TTSNode));
    if T = 'defProc' then
    begin
      AProc:= P;
      Exit;
    end;
    if Result.IsNull then
    begin
      if (T = 'while') or (T = 'repeat') then Result:= P
      else if ((T = 'for') or (T = 'foreach')) and SameNode(P.ChildByField('body'), C) then Result:= P;
    end;
    C:= P;
    P:= C.Parent;
  end;
  Result:= Default(TTSNode);
end;

{ The whole call an identifier names: `F`, `X.F`, `F(..)`, `X.F(..)`. AOwnDot is
  the dot of `X.F`, null without a receiver. }
function CallNodeOf(const AIdent: TTSNode; out AOwnDot: TTSNode): TTSNode;
begin
  AOwnDot:= AIdent.Parent;
  if AOwnDot.IsNull or (AOwnDot.NodeType <> 'exprDot') or not SameNode(AOwnDot.ChildByField('rhs'), AIdent) then
    AOwnDot:= Default(TTSNode);
  var Inner: TTSNode:= if AOwnDot.IsNull then AIdent else AOwnDot;
  Result:= Inner.Parent;
  if Result.IsNull or (Result.NodeType <> 'exprCall') or not SameNode(Result.ChildByField('entity'), Inner) then
    Result:= Inner;
end;

{ `Result:= FField` and the like: the hoist would save nothing. }
function IsOneLineAccessor(const ARoot: TTSNode; const ASym: TSymbol): Boolean;
var
  Nodes: TList<TTSNode>;
begin
  Result:= False;
  if ASym.ImplStartLine <= 0 then Exit;
  var Proc: TTSNode:= FindDefProcAt(ARoot, ASym.ImplStartLine - 1);
  if Proc.IsNull then Exit;
  Nodes:= TList<TTSNode>.Create;
  try
    CollectNodesOfType(Proc.ChildByField('body'), 'assignment', Nodes);
    if Nodes.Count <> 1 then Exit;
    Result:= MatchStr(Unparen(Nodes[0].ChildByField('rhs')).NodeType, ['identifier', 'exprDot']);
  finally
    Nodes.Free;
  end;
end;

function CollectEffectFreeInLoopInvariant(const AStore: ISymbolStore;
  AOnlyFileId: Int64): TArray<TLintFinding>;
var
  Run     : TLoopInvariantRun;
  Findings: TList<TLintFinding>;
  FileIdOf: TDictionary<string, Int64>;
  Seen    : TDictionary<string, Boolean>;
  Idents  : TList<TTSNode>;
  Locals  : TDictionary<string, Boolean>;
  Written : TDictionary<string, Boolean>;
begin
  Run     := TLoopInvariantRun.Create(AStore);
  Findings:= TList<TLintFinding>.Create;
  FileIdOf:= TDictionary<string, Int64>.Create(TIStringComparer.Ordinal);
  Seen    := TDictionary<string, Boolean>.Create;
  Idents  := TList<TTSNode>.Create;
  Locals  := TDictionary<string, Boolean>.Create;
  Written := TDictionary<string, Boolean>.Create;
  try
    for var Fi in AStore.GetAllFileIds do
      FileIdOf.AddOrSetValue(AStore.GetFilePath(Fi), Fi);
    Run.LoadFacts;
    for var Sym in AStore.FindSymbolsWithFacts do
    begin
      var SF: TSymbolFacts;
      if (not Run.SymbolFacts(Sym.Id, SF)) or (SF.EffectFree <> CEffectFreeProven) then Continue;
      if not ((Sym.Kind = skFunction) or ((Sym.Kind = skMethod) and SignatureReturnsValue(Sym.Signature))) then Continue;
      if Run.ClassifyName(LowerCase(Sym.Name)) <> lncProven then Continue;
      var Accessor: Integer:= -1; { unknown until a call site makes it worth a parse }
      for var C in AStore.FindResolvedCallers(Sym.Id) do
      begin
        var FileId: Int64;
        if not AcceptCallSite(C, Sym.Id, AOnlyFileId, FileIdOf, Seen, FileId) then Continue;
        var PF: TParsedFile:= TAstParseCache.Get(C.FullPath);
        if PF.Tree = nil then Continue;
        Idents.Clear;
        CollectIdentsOnRow(PF.Tree.RootNode, C.CallSiteLine - 1, Sym.Name, PF.Src, Idents);
        for var Id in Idents do
        begin
          var Proc: TTSNode;
          var Loop: TTSNode:= EnclosingIteratedLoop(Id, Proc);
          if Loop.IsNull or Proc.IsNull then Continue;
          if Accessor < 0 then
          begin
            var Own: TParsedFile:= TAstParseCache.Get(AStore.GetFilePath(Sym.FileId));
            Accessor:= Ord((Own.Tree <> nil) and IsOneLineAccessor(Own.Tree.RootNode, Sym));
          end;
          if Accessor = 1 then Break;
          Locals.Clear;
          Run.CollectLocals(Proc, PF.Src, Locals);
          Written.Clear;
          var Changes: TLoopChanges:= Run.AnalyzeLoop(Loop, PF.Src, Locals, Written);
          if Changes.Rejected then Continue;
          if not (Changes.Frozen or Run.CalleeReadsNoState(Sym)) then Continue;
          var OwnDot: TTSNode;
          var Call: TTSNode:= CallNodeOf(Id, OwnDot);
          if not Run.Invariant(Call, Id, Call, OwnDot, PF.Src, Locals, Changes) then Continue;
          var Fd: TLintFinding:= Default(TLintFinding);
          Fd.RuleId    := EFFECT_FREE_IN_LOOP_INVARIANT_RULE;
          Fd.FilePath  := C.FullPath;
          Fd.FileId    := FileId;
          Fd.StartLine := C.CallSiteLine;
          Fd.EndLine   := C.CallSiteLine;
          Fd.StartCol  := Integer(Id.StartPoint.Column) + 1;
          Fd.EndCol    := Fd.StartCol + Length(Sym.Name);
          Fd.Severity  := CSeverityInfo;
          Fd.SymbolName:= Sym.Name;
          Fd.Message   := Format(
            '%s is effect-free and answers the same on every iteration of the loop at line %d ' +
            '(%s) -- call it once before the loop',
            [Sym.QualifiedName, Integer(Loop.StartPoint.Row) + 1,
             if Changes.Frozen then 'the loop writes only local variables' else 'it reads no state']);
          Findings.Add(Fd);
          Break;
        end;
      end;
    end;
    Result:= Findings.ToArray;
  finally
    Written.Free;
    Locals.Free;
    Idents.Free;
    Seen.Free;
    FileIdOf.Free;
    Findings.Free;
    Run.Free;
  end;
end; // function

{ ---- ui-access-in-thread-transitive ---------------------------------------- }

const
  CMarshalNames: array[0..2] of string = ('Synchronize', 'Queue', 'ForceQueue');

{ True when the identifier lies inside the ARGUMENTS of a Synchronize / Queue /
  ForceQueue call (bare or dotted) within its routine. }
function InsideMarshalCall(const AIdent: TTSNode; const ASrc: TBytes): Boolean;
begin
  var Prev: TTSNode:= AIdent;
  var P   : TTSNode:= AIdent.Parent;
  while (not P.IsNull) and (P.NodeType <> 'defProc') do
  begin
    if (P.NodeType = 'exprCall') and SameNode(P.ChildByField('args'), Prev) and
       MatchText(NodeText(CalleeIdentOf(P), ASrc), CMarshalNames) then
      Exit(True);
    Prev:= P;
    P   := P.Parent;
  end;
  Result:= False;
end;

{ True when every occurrence of ACallee on the call line is marshalled -- or
  when the line no longer names it (a stale index: say nothing). }
function EdgeMarshalled(const APath: string; ALine: Integer; const ACallee: string): Boolean;
var
  Idents: TList<TTSNode>;
begin
  { A missing or unreadable file (Tree = nil) counts as marshalled: absence over a wrong finding. }
  var PF: TParsedFile:= TAstParseCache.Get(APath);
  if PF.Tree = nil then Exit(True);
  Idents:= TList<TTSNode>.Create;
  try
    CollectIdentsOnRow(PF.Tree.RootNode, ALine - 1, ACallee, PF.Src, Idents);
    if Idents.Count = 0 then Exit(True);
    for var Id in Idents do
      if not InsideMarshalCall(Id, PF.Src) then Exit(False);
    Result:= True;
  finally
    Idents.Free;
  end;
end;

{ True when the routine's own body text mentions a marshalling or main-thread
  check -- it is taken to protect its own UI access. }
function MarshalsItself(const AStore: ISymbolStore; const ASym: TSymbol;
  ALineCache: TDictionary<string, TArray<string>>): Boolean;
const
  CMarkers: array[0..3] of string = ('SYNCHRONIZE', 'QUEUE', 'MAINTHREADID', 'CURRENTTHREAD');
begin
  var L: TArray<string>:= LinesOf(AStore.GetFilePath(ASym.FileId), ALineCache);
  { Unreadable source counts as marshalling: absence over a wrong finding. }
  if (L = nil) or (ASym.ImplStartLine <= 0) or (ASym.ImplEndLine > Length(L)) then Exit(True);
  for var I:= ASym.ImplStartLine to ASym.ImplEndLine do
  begin
    var U: string:= UpperCase(L[I - 1]);
    for var M in CMarkers do
      if ContainsStr(U, M) then Exit(True);
  end;
  Result:= False;
end;

function ShortName(const AQName: string): string;
begin
  var Parts: TArray<string>:= AQName.Split(['.']);
  Result:= if Length(Parts) >= 2 then Parts[High(Parts) - 1] + '.' + Parts[High(Parts)] else AQName;
end;

function CollectUiAccessInThreadTransitive(const AStore: ISymbolStore;
  AOnlyFileId: Int64): TArray<TLintFinding>;
type
  TStep = record
    SymId: Int64;
    Name : string;
    Path : string;
  end;
var
  Findings : TList<TLintFinding>;
  Threads  : TDictionary<string, Boolean>;
  FileIdOf : TDictionary<string, Int64>;
  Emitted  : TDictionary<string, Boolean>;
  LineCache: TDictionary<string, TArray<string>>;
  Callers  : TDictionary<Int64, TArray<TResolvedCaller>>;
  Syms     : TDictionary<Int64, TSymbol>;
  Visited  : TDictionary<Int64, Boolean>;
  Frontier : TList<TStep>;
  Next     : TList<TStep>;

  function CallersOf(AId: Int64): TArray<TResolvedCaller>;
  begin
    if not Callers.TryGetValue(AId, Result) then
    begin
      Result:= AStore.FindResolvedCallers(AId);
      Callers.Add(AId, Result);
    end;
  end;

  function SymOf(AId: Int64): TSymbol;
  begin
    if not Syms.TryGetValue(AId, Result) then
    begin
      Result:= AStore.GetSymbolById(AId);
      Syms.Add(AId, Result);
    end;
  end;

  function IsThreadExecute(const S: TSymbol): Boolean;
  begin
    if not SameText(S.Name, 'Execute') then Exit(False);
    var Parts: TArray<string>:= S.QualifiedName.Split(['.']);
    Result:= (Length(Parts) >= 2) and Threads.ContainsKey(LowerCase(Parts[High(Parts) - 1]));
  end;

begin
  Findings := TList<TLintFinding>.Create;
  Threads  := TDictionary<string, Boolean>.Create;
  FileIdOf := TDictionary<string, Int64>.Create(TIStringComparer.Ordinal);
  Emitted  := TDictionary<string, Boolean>.Create;
  LineCache:= TDictionary<string, TArray<string>>.Create;
  Callers  := TDictionary<Int64, TArray<TResolvedCaller>>.Create;
  Syms     := TDictionary<Int64, TSymbol>.Create;
  Visited  := TDictionary<Int64, Boolean>.Create;
  Frontier := TList<TStep>.Create;
  Next     := TList<TStep>.Create;
  try
    for var D in AStore.FindDescendantNames('TThread') do Threads.AddOrSetValue(LowerCase(D), True);
    if Threads.Count = 0 then Exit(nil);
    for var Fi in AStore.GetAllFileIds do
      FileIdOf.AddOrSetValue(AStore.GetFilePath(Fi), Fi);
    for var SF in AStore.GetAllSymbolFacts do
    begin
      if SF.UiAffinity = '' then Continue;
      var U: TSymbol:= SymOf(SF.SymbolId);
      if (U.Id = 0) or MarshalsItself(AStore, U, LineCache) then Continue;
      Visited.Clear;
      Visited.Add(U.Id, True);
      Frontier.Clear;
      var First: TStep;
      First.SymId:= U.Id;
      First.Name := U.Name;
      First.Path := ShortName(U.QualifiedName);
      Frontier.Add(First);
      for var Hop:= 1 to CMaxHops do
      begin
        Next.Clear;
        for var St in Frontier do
          for var C in CallersOf(St.SymId) do
          begin
            if (C.Mode <> '') or (C.Confidence <> CConfidenceCertain) then Continue;
            if (C.FullPath = '') or (C.CallSiteLine <= 0) or (C.EnclosingSymbolId = 0) then Continue;
            if Visited.ContainsKey(C.EnclosingSymbolId) then Continue;
            if EdgeMarshalled(C.FullPath, C.CallSiteLine, St.Name) then Continue;
            var Caller: TSymbol:= SymOf(C.EnclosingSymbolId);
            { A thread body is a terminal: never marked visited, so EACH of its
              call sites that reaches U is reported (Emitted dedupes a line). }
            if not IsThreadExecute(Caller) then Visited.Add(C.EnclosingSymbolId, True)
            else
            begin
              var FileId: Int64;
              if not FileIdOf.TryGetValue(C.FullPath, FileId) then FileId:= 0;
              if (AOnlyFileId <> 0) and (FileId <> AOnlyFileId) then Continue;
              var Key: string:= Format('%s|%d', [C.FullPath, C.CallSiteLine]);
              if Emitted.ContainsKey(Key) then Continue;
              Emitted.Add(Key, True);
              var Fd: TLintFinding:= Default(TLintFinding);
              Fd.RuleId    := UI_ACCESS_IN_THREAD_TRANSITIVE_RULE;
              Fd.FilePath  := C.FullPath;
              Fd.FileId    := FileId;
              Fd.StartLine := C.CallSiteLine;
              Fd.EndLine   := C.CallSiteLine;
              Fd.StartCol  := 1;
              Fd.EndCol    := Fd.StartCol + Length(St.Name);
              Fd.Severity  := CSeverityWarning;
              Fd.SymbolName:= St.Name;
              Fd.Message   := Format(
                '%s runs on a worker thread and reaches UI code: %s -> %s, which touches %s ' +
                '-- marshal the call through Synchronize or Queue',
                [ShortName(Caller.QualifiedName), ShortName(Caller.QualifiedName), St.Path, SF.UiAffinity]);
              Findings.Add(Fd);
              Continue;
            end;
            var Step: TStep;
            Step.SymId:= Caller.Id;
            Step.Name := Caller.Name;
            Step.Path := ShortName(Caller.QualifiedName) + ' -> ' + St.Path;
            Next.Add(Step);
          end;
        if Next.Count = 0 then Break;
        Frontier.Clear;
        Frontier.AddRange(Next);
      end;
    end;
    Result:= Findings.ToArray;
  finally
    Next.Free;
    Frontier.Free;
    Visited.Free;
    Syms.Free;
    Callers.Free;
    LineCache.Free;
    Emitted.Free;
    FileIdOf.Free;
    Threads.Free;
    Findings.Free;
  end;
end; // function

end.
