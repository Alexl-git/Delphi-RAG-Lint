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

/// <summary>Finds resolved calls to a routine with a PROVEN effect that sit in
/// the RIGHT operand of a Boolean <c>and</c> / <c>or</c>, so they run only when
/// the left operand does not decide the result.</summary>
/// <param name="AStore">The project index; must carry the purity columns.</param>
/// <param name="AOnlyFileId">0 for every file; otherwise only findings in that
/// file are returned.</param>
/// <returns>One info finding per (call line, callee), anchored at the call line;
/// the message names the callee, its effect summary and its witness.</returns>
/// <remarks>A proven effect is <c>effect_free = 0</c> with a stored summary
/// carrying <c>g</c>, <c>h</c>, <c>s</c> or <c>p&lt;k&gt;</c>; '?' alone never
/// fires, nor does an unbound or non-certain edge. The call line is parsed and
/// the call fires only when EVERY occurrence of the callee's name on that line is
/// in such a right operand. The operator must be PROVEN Boolean (an integer
/// <c>and</c> is bitwise and evaluates both sides): it is the condition of an
/// if / while / until / inline if, or one operand is a comparison, <c>not</c> of a
/// Boolean, True/False, <c>Assigned(..)</c>, another proven Boolean and/or, or
/// the call itself to a callee whose signature returns a Boolean type. A file
/// that contains <c>{$B+}</c> or <c>{$BOOLEVAL ON}</c> anywhere is skipped
/// whole. <c>xor</c> evaluates both sides and never counts. Never raises.</remarks>
function CollectSideEffectInShortCircuit(const AStore: ISymbolStore;
  AOnlyFileId: Int64): TArray<TLintFinding>;

/// <summary>Finds properties whose READ accessor is a method with a PROVEN
/// self-field (<c>s</c>) or global (<c>g</c>) write.</summary>
/// <param name="AStore">The project index; must carry the purity columns.</param>
/// <param name="AOnlyFileId">0 for every file; otherwise only findings in that
/// file are returned.</param>
/// <returns>One info finding per property, anchored at its declaration; the
/// message names the getter, its effect summary and its witness.</returns>
/// <remarks>The getter is matched by name inside the property's own class in
/// the same file (<c>Unit.TClass.Getter</c>); an inherited getter, a field
/// accessor and an indexed or dotted accessor expression are not judged.
/// LAZY-INIT / MEMO EXEMPTION: a getter whose body has an if / while condition
/// that tests <c>nil</c>, calls <c>Assigned</c>, or names a variable the getter
/// itself assigns (other than Result) is exempt. Never raises.</remarks>
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
/// <remarks>Only certain call_edges rows are walked (backwards, from each
/// UI-touching routine). An edge whose callee name sits inside the arguments of
/// a <c>Synchronize</c>, <c>Queue</c> or <c>ForceQueue</c> call is not walked,
/// and a UI routine whose own body mentions Synchronize, Queue, MainThreadID or
/// CurrentThread is taken to marshal itself. The thread class is recognised by
/// the store's descendant closure of the name <c>TThread</c>. Direct UI access
/// in Execute's own body stays the job of the AST rule
/// <c>ui-access-in-thread</c>; this rule reports hops >= 1 only. Never raises.</remarks>
function CollectUiAccessInThreadTransitive(const AStore: ISymbolStore;
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

{ ---- side-effect-in-short-circuit ------------------------------------------ }

type
  TShortCircuitJudge = record
    Src       : TBytes;
    Callee    : TTSNode;
    BoolCallee: Boolean;
    function BoolOperand(const N: TTSNode): Boolean;
    function IsCondition(const N: TTSNode): Boolean;
    function BoolProven(const B: TTSNode): Boolean;
    function Guarded: Boolean;
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
      Exit(True);
    if not IsExprNode(P) then Exit;
    N:= P;
    P:= N.Parent;
  end;
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
      if not Facts.TryGetValue(Sym.Id, SF) or (SF.EffectFree <> CEffectFreeNotProven) then Continue;
      var Sum: TEffectSummary:= TEffectSummary.Decode(SF.EffectSummary);
      if (Sum.Flags * [efGlobal, efHeap, efSelfFields] = []) and (Length(Sum.Params) = 0) then Continue;
      var BoolRet: Boolean:= IsBooleanReturn(Sym.Signature);
      for var C in AStore.FindResolvedCallers(Sym.Id) do
      begin
        if (C.Mode <> '') or (C.Confidence <> CConfidenceCertain) then Continue;
        if (C.FullPath = '') or (C.CallSiteLine <= 0) then Continue;
        var FileId: Int64;
        if not FileIdOf.TryGetValue(C.FullPath, FileId) then FileId:= 0;
        if (AOnlyFileId <> 0) and (FileId <> AOnlyFileId) then Continue;
        var Key: string:= Format('%s|%d|%d', [C.FullPath, C.CallSiteLine, Sym.Id]);
        if Seen.ContainsKey(Key) then Continue;
        Seen.Add(Key, True);
        if not AndOrNear(LinesOf(C.FullPath, LineCache), C.CallSiteLine) then Continue;
        { Get answers Tree = nil for a missing or unreadable file. }
        var PF: TParsedFile:= TAstParseCache.Get(C.FullPath);
        if (PF.Tree = nil) or HasCompleteBoolEval(PF.RawSrc) then Continue;
        Idents.Clear;
        CollectIdentsOnRow(PF.Tree.RootNode, C.CallSiteLine - 1, Sym.Name, PF.Src, Idents);
        if Idents.Count = 0 then Continue;
        var AllGuarded: Boolean:= True;
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
        end;
        if not AllGuarded then Continue;
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
