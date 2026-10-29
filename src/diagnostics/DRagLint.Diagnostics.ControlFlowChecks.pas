unit DRagLint.Diagnostics.ControlFlowChecks;

{ Clippy-parity wave (plan 2026-10-27-clippy-rules-plan.md), lane L5.
  Pure-AST checks over loops, early exits and self-recursion. No symbol store is
  needed; the store parameter of Check is accepted for the shared checker shape.
  Rules: loop-condition-invariant, for-bound-modified-in-body, infinite-loop-no-exit,
  redundant-continue-exit, else-after-exit, unconditional-recursion.
  Every rule is conservative: it fires only on shapes where the verdict does not
  depend on facts the AST cannot see (field values, var parameters, callee bodies).
  Fixtures: tests\lint\<id>.pas. }

interface

uses
  DRagLint.Core.Model
  , DRagLint.Core.Interfaces
  , DRagLint.Lint.Config
  ;

type
  /// <summary>Checker for the loop-condition-invariant, for-bound-modified-in-body, infinite-loop-no-exit, redundant-continue-exit, else-after-exit, unconditional-recursion rules.</summary>
  /// <remarks>
  /// Stateless; thread-safe. Called from DoLint and DoLintAll behind
  /// LintRuleWants(rule, LINT_GATE_CONTROL_FLOW). All six rules are emitted on every
  /// call; the CLI filters by --rule and by the enabled set (else-after-exit is OFF by default).
  /// </remarks>
  TControlFlowChecker = class
  public
    /// <summary>Runs the ControlFlowChecks rules against one source file.</summary>
    /// <param name="AFile">Absolute path to the .pas/.inc source file.</param>
    /// <param name="ACfg">Effective lint configuration (thresholds via ThresholdFor).</param>
    /// <param name="AStore">Optional symbol store; nil when the run has no index. Unused: the rules are store-free.</param>
    /// <param name="AFileId">File id within AStore (ignored when AStore is nil).</param>
    /// <returns>One finding per violation; empty when clean or unparsable. The CLI filters by --rule.</returns>
    class function Check(const AFile: string; const ACfg: TLintConfig;
      const AStore: ISymbolStore; AFileId: Integer): TArray<TLintFinding>; static;
  end;

implementation

uses
  System.SysUtils
  , System.Generics.Collections
  , TreeSitter
  , DRagLint.Diagnostics.ParseCache
  ;

const
  { RTL routines whose arguments are read, never written: passing a local to one of
    these does not count as a possible modification (loop-condition-invariant). }
  PURE_ARG_ROUTINES: array[0..16] of string = (
    'writeln', 'write', 'inttostr', 'format', 'length', 'ord', 'chr', 'abs', 'sqr',
    'odd', 'min', 'max', 'copy', 'pos', 'uppercase', 'lowercase', 'trim'
  );

type
  { One walk over one parsed file. Private to this unit. }
  TCfRun = class
  strict private
    FSrc      : TBytes;
    FFile     : string;
    FFindings : TList<TLintFinding>;
    FLocals   : TDictionary<string, Boolean>;
    FNested   : Boolean;
    FProcCount: TDictionary<string, Integer>;
    function Txt(const N: TTSNode): string;
    function IsTrivia(const N: TTSNode): Boolean;
    function IsLoop(const N: TTSNode): Boolean;
    procedure EmitAt(const ANode: TTSNode; const ARuleId, AMessage, ASeverity: string);
    procedure Stmts(const N: TTSNode; AList: TList<TTSNode>);
    function LastStmt(const N: TTSNode): TTSNode;
    function BareWord(const S: TTSNode; const AWord: string): Boolean;
    function CallNameOf(const S: TTSNode): string;
    function HasNested(const N: TTSNode): Boolean;
    function HasExit(const N: TTSNode; AInner: Integer): Boolean;
    function RootIdent(const N: TTSNode): string;
    function MentionsAny(const N: TTSNode; ANames: TDictionary<string, Boolean>): Boolean;
    function BodyModifies(const N: TTSNode; ANames: TDictionary<string, Boolean>; AStrictCalls: Boolean): Boolean;
    function BodyIncDec(const N: TTSNode; ANames: TDictionary<string, Boolean>): Boolean;
    function CollectCondIdents(const N: TTSNode; ANames: TDictionary<string, Boolean>): Boolean;
    procedure CollectLocals(const N: TTSNode);
    procedure CountProcs(const N: TTSNode);
    function ProcKey(const AHeader: TTSNode; out AMethod: string): string;
    function IsExitStmt(const S: TTSNode): Boolean;
    function ExprCallsSelf(const N: TTSNode; const AName: string; AIsFunc: Boolean): TTSNode;
    procedure CheckWhile(const N: TTSNode);
    procedure CheckRepeat(const N: TTSNode);
    procedure CheckFor(const N: TTSNode);
    procedure CheckLoopTail(const N: TTSNode);
    procedure CheckIfElse(const N: TTSNode);
    procedure CheckProc(const N: TTSNode);
    procedure Visit(const N: TTSNode);
  public
    constructor Create(const AFile: string; const ASrc: TBytes);
    destructor Destroy; override;
    function Run(const ARoot: TTSNode): TArray<TLintFinding>;
  end;

constructor TCfRun.Create(const AFile: string; const ASrc: TBytes);
begin
  inherited Create;
  FFile:= AFile;
  FSrc := ASrc;
  FFindings := TList<TLintFinding>.Create;
  FLocals   := TDictionary<string, Boolean>.Create;
  FProcCount:= TDictionary<string, Integer>.Create;
end;

destructor TCfRun.Destroy;
begin
  FProcCount.Free;
  FLocals.Free;
  FFindings.Free;
  inherited Destroy;
end;

function TCfRun.Txt(const N: TTSNode): string;
var
  S, E: Integer;
begin
  Result:= '';
  if N.IsNull then Exit;
  S:= Integer(N.StartByte);
  E:= Integer(N.EndByte);
  if (E <= S) or (S < 0) or (E > Length(FSrc)) then Exit;
  Result:= TEncoding.UTF8.GetString(FSrc, S, E - S);
end;

function TCfRun.IsTrivia(const N: TTSNode): Boolean;
var
  T: string;
begin
  T:= N.NodeType;
  Result:= (T = 'comment') or (T = 'pp')
    or ((Length(T) > 1) and (T[1] = 'k') and CharInSet(T[2], ['A'..'Z']));
end;

function TCfRun.IsLoop(const N: TTSNode): Boolean;
var
  T: string;
begin
  T:= N.NodeType;
  Result:= (T = 'while') or (T = 'repeat') or (T = 'for') or (T = 'foreach');
end;

procedure TCfRun.EmitAt(const ANode: TTSNode; const ARuleId, AMessage, ASeverity: string);
var
  P: TTSPoint;
  F: TLintFinding;
begin
  P:= ANode.StartPoint;
  F:= Default(TLintFinding);
  F.RuleId   := ARuleId;
  F.Severity := ASeverity;
  F.Message  := AMessage;
  F.FilePath := FFile;
  F.StartLine:= Integer(P.Row) + 1;
  F.StartCol := Integer(P.Column) + 1;
  F.EndLine  := F.StartLine;
  F.EndCol   := F.StartCol + Length(Trim(Txt(ANode)));
  FFindings.Add(F);
end;

{ The statements of a block / statements node, or the node itself when it is a lone statement. }
procedure TCfRun.Stmts(const N: TTSNode; AList: TList<TTSNode>);
var
  I: Integer;
begin
  if N.IsNull then Exit;
  if (N.NodeType = 'block') or (N.NodeType = 'statements') then
  begin
    for I:= 0 to N.NamedChildCount - 1 do
      if not IsTrivia(N.NamedChild(I)) then AList.Add(N.NamedChild(I));
  end
  else
    AList.Add(N);
end;

function TCfRun.LastStmt(const N: TTSNode): TTSNode;
var
  L: TList<TTSNode>;
begin
  L:= TList<TTSNode>.Create;
  try
    Stmts(N, L);
    Result:= if L.Count > 0 then L[L.Count - 1] else Default(TTSNode);
  finally
    L.Free;
  end;
end;

{ A statement that is exactly the bare identifier AWord (Exit, Break, Continue, ...). }
function TCfRun.BareWord(const S: TTSNode; const AWord: string): Boolean;
begin
  Result:= (not S.IsNull) and (S.NodeType = 'statement') and (S.NamedChildCount = 1)
    and (S.NamedChild(0).NodeType = 'identifier') and SameText(Trim(Txt(S.NamedChild(0))), AWord);
end;

{ Lower-cased callee of a statement-level call `Name(...)`, or '' for any other statement. }
function TCfRun.CallNameOf(const S: TTSNode): string;
var
  C, Ent: TTSNode;
begin
  Result:= '';
  if S.IsNull or (S.NodeType <> 'statement') or (S.NamedChildCount <> 1) then Exit;
  C:= S.NamedChild(0);
  if C.NodeType <> 'exprCall' then Exit;
  Ent:= C.ChildByField('entity');
  if (not Ent.IsNull) and (Ent.NodeType = 'identifier') then Result:= LowerCase(Trim(Txt(Ent)));
end;

{ True when a descendant of N (not N itself) is a nested routine or an anonymous method. }
function TCfRun.HasNested(const N: TTSNode): Boolean;
var
  I: Integer;
  C: TTSNode;
begin
  Result:= False;
  for I:= 0 to N.NamedChildCount - 1 do
  begin
    C:= N.NamedChild(I);
    if (C.NodeType = 'defProc') or (C.NodeType = 'lambda') or HasNested(C) then Exit(True);
  end;
end;

{ True when the code under N can leave the enclosing loop: a Break that belongs to
  it (AInner = 0), Exit, raise, goto, asm, Halt / Abort / RunError. Nested routines
  and anonymous methods are not entered; a Break inside an inner loop only leaves that loop. }
function TCfRun.HasExit(const N: TTSNode; AInner: Integer): Boolean;  // dl:ok too-many-exit-points@201c -- REVIEWED 2026-10-27: early-out guards of a recursive tree search; a single exit would nest every guard
var
  I    : Integer;
  T, Cn: string;
  Inner: Integer;
begin
  Result:= False;
  if N.IsNull then Exit;
  T:= N.NodeType;
  if (T = 'defProc') or (T = 'lambda') then Exit;
  if (T = 'raise') or (T = 'goto') or (T = 'asm') then Exit(True);
  if T = 'statement' then
  begin
    if BareWord(N, 'Exit') then Exit(True);
    if BareWord(N, 'Break') and (AInner = 0) then Exit(True);
    Cn:= CallNameOf(N);
    if (Cn = 'exit') or (Cn = 'halt') or (Cn = 'abort') or (Cn = 'runerror') or (Cn = 'exitprocess') then
      Exit(True);
  end;
  Inner:= AInner;
  if IsLoop(N) then Inc(Inner);
  for I:= 0 to N.NamedChildCount - 1 do
    if HasExit(N.NamedChild(I), Inner) then Exit(True);
end;

{ Leftmost identifier of an assignment target (`A`, `A.B`, `A[I]`), lower-cased; '' otherwise. }
function TCfRun.RootIdent(const N: TTSNode): string;
var
  C: TTSNode;
begin
  Result:= '';
  C:= N;
  while not C.IsNull do
  begin
    if C.NodeType = 'identifier' then Exit(LowerCase(Trim(Txt(C))));
    if C.NodeType = 'exprDot' then C:= C.ChildByField('lhs')
    else if (C.NodeType = 'exprSubscript') or (C.NodeType = 'exprCall') then C:= C.ChildByField('entity')
    else if (C.NodeType = 'exprParens') and (C.NamedChildCount = 1) then C:= C.NamedChild(0)
    else Exit;
  end;
end;

function TCfRun.MentionsAny(const N: TTSNode; ANames: TDictionary<string, Boolean>): Boolean;
var
  I: Integer;
begin
  Result:= False;
  if N.IsNull then Exit;
  if (N.NodeType = 'identifier') and ANames.ContainsKey(LowerCase(Trim(Txt(N)))) then Exit(True);
  for I:= 0 to N.NamedChildCount - 1 do
    if MentionsAny(N.NamedChild(I), ANames) then Exit(True);
end;

{ True when the code under N may change one of ANames: assignment, for-loop variable,
  foreach variable, address-of, with / asm, or (AStrictCalls) handing the name to a call
  whose callee is not a known read-only RTL routine (a possible var / out argument). }
function TCfRun.BodyModifies(const N: TTSNode; ANames: TDictionary<string, Boolean>; AStrictCalls: Boolean): Boolean;  // dl:ok too-many-exit-points@ac76 -- REVIEWED 2026-10-27: early-out guards of a recursive tree search; a single exit would nest every guard
var
  I      : Integer;
  T, Cn  : string;
  Ent    : TTSNode;
  Safe   : Boolean;
  Pure   : string;
begin
  Result:= False;
  if N.IsNull then Exit;
  T:= N.NodeType;
  if (T = 'with') or (T = 'asm') then Exit(True);
  if T = 'assignment' then
  begin
    if ANames.ContainsKey(RootIdent(N.ChildByField('lhs'))) then Exit(True);
  end
  else if T = 'foreach' then
  begin
    if (N.NamedChildCount > 1) and (N.NamedChild(1).NodeType = 'identifier')
       and ANames.ContainsKey(LowerCase(Trim(Txt(N.NamedChild(1))))) then Exit(True);
  end
  else if T = 'exprUnary' then
  begin
    for I:= 0 to N.ChildCount - 1 do
      if (N.Child(I).NodeType = 'kAt') and MentionsAny(N, ANames) then Exit(True);
  end
  else if (T = 'exprCall') and AStrictCalls then
  begin
    Ent:= N.ChildByField('entity');
    Safe:= False;
    if (not Ent.IsNull) and (Ent.NodeType = 'identifier') then
    begin
      Cn:= LowerCase(Trim(Txt(Ent)));
      for Pure in PURE_ARG_ROUTINES do
        if Pure = Cn then Safe:= True;
    end;
    if (not Safe) and MentionsAny(N.ChildByField('args'), ANames) then Exit(True);
  end;
  for I:= 0 to N.NamedChildCount - 1 do
    if BodyModifies(N.NamedChild(I), ANames, AStrictCalls) then Exit(True);
end;

{ True when the code under N holds Inc / Dec / Include / Exclude whose first argument is one of ANames. }
function TCfRun.BodyIncDec(const N: TTSNode; ANames: TDictionary<string, Boolean>): Boolean;
var
  I      : Integer;
  Cn     : string;
  Args   : TTSNode;
begin
  Result:= False;
  if N.IsNull then Exit;
  Cn:= CallNameOf(N);
  if (Cn = 'inc') or (Cn = 'dec') or (Cn = 'include') or (Cn = 'exclude') then
  begin
    Args:= N.NamedChild(0).ChildByField('args');
    if (not Args.IsNull) and (Args.NamedChildCount > 0)
       and ANames.ContainsKey(RootIdent(Args.NamedChild(0))) then Exit(True);
  end;
  for I:= 0 to N.NamedChildCount - 1 do
    if BodyIncDec(N.NamedChild(I), ANames) then Exit(True);
end;

{ Collects the identifiers of a side-effect-free condition into ANames. Returns False
  as soon as the condition holds anything but identifiers, literals and operators
  (calls, member access, subscripts and so on may read changing state). }
function TCfRun.CollectCondIdents(const N: TTSNode; ANames: TDictionary<string, Boolean>): Boolean;
var
  I: Integer;
  T: string;
begin
  Result:= True;
  T:= N.NodeType;
  if T = 'identifier' then
    ANames.AddOrSetValue(LowerCase(Trim(Txt(N))), True)
  else if (T = 'exprBinary') or (T = 'exprUnary') or (T = 'exprParens')  // dl:ok boolean-expression-complexity@eef4 -- REVIEWED 2026-10-27: flat node-type whitelist, each operand independent
          or (T = 'literalNumber') or (T = 'literalString') or IsTrivia(N) then
  begin
    for I:= 0 to N.NamedChildCount - 1 do
      if not CollectCondIdents(N.NamedChild(I), ANames) then Exit(False);
  end
  else
    Result:= False;
end;

{ Names declared by the routine N (parameters, var blocks, inline vars) into FLocals. }
procedure TCfRun.CollectLocals(const N: TTSNode);
var
  I, J: Integer;
  C   : TTSNode;
begin
  for I:= 0 to N.NamedChildCount - 1 do
  begin
    C:= N.NamedChild(I);
    if (C.NodeType = 'declVar') or (C.NodeType = 'declArg') then
    begin
      for J:= 0 to C.NamedChildCount - 1 do
        if C.NamedChild(J).NodeType = 'identifier' then
          FLocals.AddOrSetValue(LowerCase(Trim(Txt(C.NamedChild(J)))), True);
    end
    else
      CollectLocals(C);
  end;
end;

{ Method name (text after the last dot) of a routine header, and the lower-cased
  whole name used as the overload key. }
function TCfRun.ProcKey(const AHeader: TTSNode; out AMethod: string): string;
var
  Nm: TTSNode;
  P : Integer;
begin
  AMethod:= '';
  Result := '';
  if AHeader.IsNull then Exit;
  Nm:= AHeader.ChildByField('name');
  if Nm.IsNull then Exit;
  Result:= LowerCase(StringReplace(Trim(Txt(Nm)), ' ', '', [rfReplaceAll]));
  P:= LastDelimiter('.', Result);
  AMethod:= Copy(Result, P + 1, MaxInt);
end;

procedure TCfRun.CountProcs(const N: TTSNode);
var
  I   : Integer;
  Key : string;
  M   : string;
  Cnt : Integer;
begin
  if N.NodeType = 'defProc' then
  begin
    Key:= ProcKey(N.ChildByField('header'), M);
    if Key <> '' then
    begin
      if not FProcCount.TryGetValue(Key, Cnt) then Cnt:= 0;
      FProcCount.AddOrSetValue(Key, Cnt + 1);
    end;
  end;
  for I:= 0 to N.NamedChildCount - 1 do CountProcs(N.NamedChild(I));
end;

{ Bare Exit / Halt / Abort / raise: nothing after it in the routine runs. }
function TCfRun.IsExitStmt(const S: TTSNode): Boolean;
var
  Cn: string;
begin
  Cn:= CallNameOf(S);
  Result:= (S.NodeType = 'raise') or BareWord(S, 'Exit') or BareWord(S, 'Abort')  // dl:ok boolean-expression-complexity@ae0e -- REVIEWED 2026-10-27: flat list of routine-leaving statement shapes
    or (Cn = 'exit') or (Cn = 'halt') or (Cn = 'abort') or (Cn = 'runerror');
end;

{ The first call to AName (bare or via Self) that is evaluated unconditionally
  inside expression N, or a null node. Short-circuit operands and the ternary are not entered. }
function TCfRun.ExprCallsSelf(const N: TTSNode; const AName: string; AIsFunc: Boolean): TTSNode;  // dl:ok too-many-exit-points@3e12 -- REVIEWED 2026-10-27: early-out guards of a recursive tree search; a single exit would nest every guard
var
  I      : Integer;
  Ent, R : TTSNode;
  Op     : string;
begin
  Result:= Default(TTSNode);
  if N.IsNull then Exit;
  if N.NodeType = 'identifier' then
  begin
    if AIsFunc and (LowerCase(Trim(Txt(N))) = AName) then Exit(N);
    Exit;
  end;
  if N.NodeType = 'exprCall' then
  begin
    Ent:= N.ChildByField('entity');
    if (not Ent.IsNull) and (Ent.NodeType = 'identifier') and (LowerCase(Trim(Txt(Ent))) = AName) then Exit(N);
    if (not Ent.IsNull) and (Ent.NodeType = 'exprDot')
       and SameText(Trim(Txt(Ent.ChildByField('lhs'))), 'Self')
       and (LowerCase(Trim(Txt(Ent.ChildByField('rhs')))) = AName) then Exit(N);
    Result:= ExprCallsSelf(N.ChildByField('args'), AName, AIsFunc);
    Exit;
  end;
  if N.NodeType = 'exprBinary' then
  begin
    Op:= LowerCase(Trim(Txt(N.ChildByField('operator'))));
    if (Op = 'and') or (Op = 'or') then Exit;
  end
  else if (N.NodeType <> 'exprUnary') and (N.NodeType <> 'exprParens') and (N.NodeType <> 'exprArgs') then
    Exit;
  for I:= 0 to N.NamedChildCount - 1 do
  begin
    R:= ExprCallsSelf(N.NamedChild(I), AName, AIsFunc);
    if not R.IsNull then Exit(R);
  end;
end;

{ loop-condition-invariant (while) and infinite-loop-no-exit (while True). }
procedure TCfRun.CheckWhile(const N: TTSNode);
var
  Cond, Body: TTSNode;
  Names     : TDictionary<string, Boolean>;
  Nm        : string;
  AllLocal  : Boolean;
begin
  Cond:= N.ChildByField('condition');
  Body:= N.ChildByField('body');
  if Cond.IsNull or Body.IsNull then Exit;
  if Cond.NodeType = 'kTrue' then
  begin
    if not HasExit(Body, 0) then
      EmitAt(N, 'infinite-loop-no-exit',
        'while True loop has no Break, Exit, raise or Halt -- it can never end', 'warning');
    Exit;
  end;
  if FNested or HasExit(Body, 0) then Exit;
  Names:= TDictionary<string, Boolean>.Create;
  try
    if (not CollectCondIdents(Cond, Names)) or (Names.Count = 0) then Exit;
    AllLocal:= True;
    for Nm in Names.Keys do
      if not FLocals.ContainsKey(Nm) then AllLocal:= False;
    if AllLocal and (not BodyModifies(Body, Names, True)) then
      EmitAt(N, 'loop-condition-invariant',
        'Loop condition only reads variables the loop body never changes -- the loop never ends or never runs',
        'warning');
  finally
    Names.Free;
  end;
end;

{ infinite-loop-no-exit (repeat ... until False). }
procedure TCfRun.CheckRepeat(const N: TTSNode);
var
  Cond, Body: TTSNode;
begin
  Cond:= N.ChildByField('condition');
  Body:= N.ChildByField('body');
  if Cond.IsNull or (Cond.NodeType <> 'kFalse') then Exit;
  if not HasExit(Body, 0) then
    EmitAt(N, 'infinite-loop-no-exit',
      'repeat ... until False loop has no Break, Exit, raise or Halt -- it can never end', 'warning');
end;

{ for-bound-modified-in-body: the loop variable or a plain-identifier bound is changed in the body. }
procedure TCfRun.CheckFor(const N: TTSNode);
var
  Start, EndE, Body: TTSNode;
  Loopvar          : string;
  Names            : TDictionary<string, Boolean>;
  Bounds           : TDictionary<string, Boolean>;
  Nm               : string;
begin
  Start:= N.ChildByField('start');
  EndE := N.ChildByField('end');
  Body := N.ChildByField('body');
  if Start.IsNull or EndE.IsNull or Body.IsNull or (Start.NodeType <> 'assignment') then Exit;
  Loopvar:= RootIdent(Start.ChildByField('lhs'));
  Names := TDictionary<string, Boolean>.Create;
  Bounds:= TDictionary<string, Boolean>.Create;
  try
    if Loopvar <> '' then Names.AddOrSetValue(Loopvar, True);
    if CollectCondIdents(EndE, Bounds) then
      for Nm in Bounds.Keys do Names.AddOrSetValue(Nm, True);
    { Same shape as the invariant rule: assignments, address-of, with. A call that merely
      receives the name is NOT a finding here (Inc / Dec are handled below). }
    if (Names.Count > 0) and (BodyModifies(Body, Names, False) or BodyIncDec(Body, Names)) then
      EmitAt(N, 'for-bound-modified-in-body',
        'The for-loop variable or its upper/lower bound is changed in the body -- the bounds are evaluated once, so the change does not alter the iteration count',
        'warning');
  finally
    Bounds.Free;
    Names.Free;
  end;
end;

{ redundant-continue-exit (loop part): Continue as the last statement of a loop body. }
procedure TCfRun.CheckLoopTail(const N: TTSNode);
var
  Last: TTSNode;
begin
  Last:= LastStmt(N.ChildByField('body'));
  if BareWord(Last, 'Continue') then
    EmitAt(Last, 'redundant-continue-exit', 'Continue as the last statement of the loop body does nothing', 'hint');
end;

{ else-after-exit: then-branch ends in Exit / Break / Continue / raise, so the else is needless nesting. }
procedure TCfRun.CheckIfElse(const N: TTSNode);
var
  Last, C: TTSNode;
  I      : Integer;
  Cn     : string;
begin
  Last:= LastStmt(N.ChildByField('then'));
  if Last.IsNull then Exit;
  Cn:= CallNameOf(Last);
  if not (BareWord(Last, 'Exit') or BareWord(Last, 'Break') or BareWord(Last, 'Continue')
          or (Last.NodeType = 'raise') or (Cn = 'exit')) then Exit;
  for I:= 0 to N.ChildCount - 1 do
  begin
    C:= N.Child(I);
    if C.NodeType = 'kElse' then
    begin
      EmitAt(C, 'else-after-exit',
        'The then-branch always leaves (Exit / Break / Continue / raise) -- the else is unnecessary nesting', 'hint');
      Exit;
    end;
  end;
end;

{ redundant-continue-exit (routine part) and unconditional-recursion. }
procedure TCfRun.CheckProc(const N: TTSNode);
var
  Header, Body, Hit, S, C: TTSNode;
  Key, Method            : string;
  IsFunc                 : Boolean;
  L                      : TList<TTSNode>;
  Last                   : TTSNode;
  Cnt                    : Integer;
begin
  Header:= N.ChildByField('header');
  Body  := N.ChildByField('body');
  if Body.IsNull or (Body.NodeType <> 'block') then Exit;
  L:= TList<TTSNode>.Create;
  try
    Stmts(Body, L);
    if L.Count = 0 then Exit;
    Last:= L[L.Count - 1];
    if BareWord(Last, 'Exit') then
      EmitAt(Last, 'redundant-continue-exit', 'Exit as the last statement of the routine does nothing', 'hint');

    Key:= ProcKey(Header, Method);
    if (Key = '') or (not FProcCount.TryGetValue(Key, Cnt)) or (Cnt <> 1) then Exit;
    IsFunc:= (not Header.IsNull) and (not Header.ChildByField('type').IsNull);
    Hit:= Default(TTSNode);
    for S in L do
    begin
      if (S.NodeType = 'statement') and (S.NamedChildCount > 0) then
      begin
        C:= S.NamedChild(0);
        if (C.NodeType = 'identifier') and (not IsFunc) and (LowerCase(Trim(Txt(C))) = Method) then
          Hit:= C
        else if (C.NodeType = 'exprDot') and SameText(Trim(Txt(C.ChildByField('lhs'))), 'Self')
                and (LowerCase(Trim(Txt(C.ChildByField('rhs')))) = Method) and (not IsFunc) then
          Hit:= C
        else if IsExitStmt(S) then Break
        else
          Hit:= ExprCallsSelf(C, Method, IsFunc);
      end
      else if S.NodeType = 'assignment' then
        Hit:= ExprCallsSelf(S.ChildByField('rhs'), Method, IsFunc)
      else
        Break;
      if not Hit.IsNull then Break;
    end;
    if not Hit.IsNull then
      EmitAt(Hit, 'unconditional-recursion',
        Format('"%s" calls itself on every path through its body -- the recursion has no base case', [Method]),
        'warning');
  finally
    L.Free;
  end;
end;

procedure TCfRun.Visit(const N: TTSNode);
var
  I        : Integer;
  T        : string;
  SavedNest: Boolean;
  Saved    : TDictionary<string, Boolean>;
begin
  if N.IsNull then Exit;
  T:= N.NodeType;
  SavedNest:= FNested;
  Saved    := nil;
  if T = 'defProc' then
  begin
    Saved  := FLocals;
    FLocals:= TDictionary<string, Boolean>.Create;
    CollectLocals(N);
    FNested:= HasNested(N);
    CheckProc(N);
  end
  else if T = 'while' then
  begin
    CheckWhile(N);
    CheckLoopTail(N);
  end
  else if T = 'repeat' then
  begin
    CheckRepeat(N);
    CheckLoopTail(N);
  end
  else if T = 'for' then
  begin
    CheckFor(N);
    CheckLoopTail(N);
  end
  else if T = 'foreach' then
    CheckLoopTail(N)
  else if T = 'ifElse' then
    CheckIfElse(N);
  try
    for I:= 0 to N.NamedChildCount - 1 do Visit(N.NamedChild(I));
  finally
    if Saved <> nil then
    begin
      FLocals.Free;
      FLocals:= Saved;
    end;
    FNested:= SavedNest;
  end;
end;

function TCfRun.Run(const ARoot: TTSNode): TArray<TLintFinding>;
begin
  CountProcs(ARoot);
  Visit(ARoot);
  Result:= FFindings.ToArray;
end;

class function TControlFlowChecker.Check(const AFile: string; const ACfg: TLintConfig;  // dl:ok unused-parameter@27ab -- REVIEWED 2026-10-27: signature fixed by the shared checker shape (LINT_GATE_CONTROL_FLOW call sites); the rules are store-free and threshold-free
  const AStore: ISymbolStore; AFileId: Integer): TArray<TLintFinding>;  // dl:ok unused-parameter@9a67 -- REVIEWED 2026-10-27: signature fixed by the shared checker shape; the rules are store-free
var
  PF : TParsedFile;
  Run: TCfRun;
begin
  Result:= nil;
  PF:= TAstParseCache.Get(AFile);
  if PF.Tree = nil then Exit;
  Run:= TCfRun.Create(AFile, PF.Src);
  try
    Result:= Run.Run(PF.Tree.RootNode);
  finally
    Run.Free;
  end;
end;

end.
