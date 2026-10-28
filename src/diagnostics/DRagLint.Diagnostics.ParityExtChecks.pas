unit DRagLint.Diagnostics.ParityExtChecks;

{ Gap-rules wave (plan 2026-10-27-rule-gaps-and-compliance-plan.md), lane G9.
  The ids are already in LINT_GATE_PARITY_EXT (CLI.pas) and in
  TRuleCatalog.BuiltinRegistry -- this lane registers nothing new in CLI.pas or
  RuleCatalog.pas.
  Rules (extensions emitting EXISTING ids):
    identical-then-else     : FixInsight W507 shapes the DeadCodeChecks single-assignment
                              check misses -- then/else that are token-identical begin..end
                              blocks, or identical call statements. Disjoint from the
                              single-assignment shape, so each if yields ONE finding.
    interface-object-mixing : FixInsight W534 -- a class-typed local passed to a SAME-FILE
                              routine whose matching parameter is an interface (I + capital),
                              then freed (X.Free / FreeAndNil(X)) in the same routine.
                              Cross-unit signatures are LATER. }

interface

uses
  System.SysUtils
  , System.StrUtils
  , System.Generics.Collections
  , TreeSitter
  , DRagLint.Diagnostics.ParseCache
  , DRagLint.Core.Model
  , DRagLint.Core.Interfaces
  , DRagLint.Lint.Config
  ;

type
  /// <summary>Checker for the ParityExtChecks rules of the gap-rules wave (G9).</summary>
  /// <remarks>
  /// Stateless; thread-safe. Called from DoLint and DoLintAll behind
  /// LintRuleWants(rule, LINT_GATE_PARITY_EXT).
  /// </remarks>
  TParityExtChecker = class
  public
    /// <summary>Runs the ParityExtChecks rules against one source file.</summary>
    /// <param name="AFile">Absolute path to the .pas/.inc source file.</param>
    /// <param name="ACfg">Effective lint configuration (unused by these rules).</param>
    /// <param name="AStore">Optional symbol store; unused (same-file signatures only).</param>
    /// <param name="AFileId">File id within AStore (ignored).</param>
    /// <returns>One finding per violation; empty when clean or unparsable. The CLI filters by --rule.</returns>
    class function Check(const AFile: string; const ACfg: TLintConfig;
      const AStore: ISymbolStore; AFileId: Integer): TArray<TLintFinding>; static;
  end;

implementation

uses
  System.Classes
  , DRagLint.Refactor.TextEdit
  , DRagLint.Lint.Autofix
  , DRagLint.Fix.Stmt
  ;

type
  { Per-call helper state; a fresh instance per Check call keeps the checker stateless. }
  TParityRun = class
  private
    FFile    : string;
    FSrc     : TBytes;
    FFindings: TList<TLintFinding>;
    FSigs    : TDictionary<string, TArray<string>>;
    FAmbig   : TDictionary<string, Boolean>;
    function NodeStr(const N: TTSNode): string;
    procedure Emit(const ARule, AMsg: string; const ANode: TTSNode; const ASev: string);
    procedure Tokens(const N: TTSNode; AOut: TStringList);
    function BranchNode(const N: TTSNode; AFrom, ATo: Integer): TTSNode;
    function IsCallish(const N: TTSNode): Boolean;
    procedure CheckIfElse(const N: TTSNode);
    procedure CollectSigs(const N: TTSNode);
    procedure AddSig(const AProc: TTSNode);
    procedure CollectArgTypes(const N: TTSNode; AOut: TList<string>);
    procedure CheckRoutine(const ADefProc: TTSNode);
    procedure Walk(const N: TTSNode);
  public
    constructor Create(const AFile: string; const ASrc: TBytes);
    destructor Destroy; override;
    procedure Run(const ARoot: TTSNode);
    function SameBranches(const N: TTSNode; out ATh, AEl: TTSNode): Boolean;
    function Findings: TArray<TLintFinding>;
  end;

const
  TYPE_PREFIX_LEN = 2;

{ I + capital: the interface naming convention (name heuristic, no store). }
function LooksInterface(const T: string): Boolean;
var S: string;
begin
  S:= Trim(T);
  Result:= (Length(S) >= TYPE_PREFIX_LEN) and (S[1] = 'I') and CharInSet(S[2], ['A'..'Z']);
end;

{ T + capital: the class naming convention (name heuristic, no store). }
function LooksClass(const T: string): Boolean;
var S: string;
begin
  S:= Trim(T);
  Result:= (Length(S) >= TYPE_PREFIX_LEN) and (S[1] = 'T') and CharInSet(S[2], ['A'..'Z']);
end;

constructor TParityRun.Create(const AFile: string; const ASrc: TBytes);
begin
  inherited Create;
  FFile    := AFile;
  FSrc     := ASrc;
  FFindings:= TList<TLintFinding>.Create;
  FSigs    := TDictionary<string, TArray<string>>.Create;
  FAmbig   := TDictionary<string, Boolean>.Create;
end;

destructor TParityRun.Destroy;
begin
  FAmbig.Free;
  FSigs.Free;
  FFindings.Free;
  inherited Destroy;
end;

{ Findings de-duplicated by (rule, line, col). }
function TParityRun.Findings: TArray<TLintFinding>;
var
  Seen: TDictionary<string, Boolean>;
  F   : TLintFinding;
  Key : string;
  Outp: TList<TLintFinding>;
begin
  Seen:= TDictionary<string, Boolean>.Create;
  Outp:= TList<TLintFinding>.Create;
  try
    for F in FFindings do
    begin
      Key:= F.RuleId + ':' + IntToStr(F.StartLine) + ':' + IntToStr(F.StartCol);
      if not Seen.ContainsKey(Key) then
      begin
        Seen.Add(Key, True);
        Outp.Add(F);
      end;
    end;
    Result:= Outp.ToArray;
  finally
    Outp.Free;
    Seen.Free;
  end;
end;

function TParityRun.NodeStr(const N: TTSNode): string;
var S, L: Integer;
begin
  Result:= '';
  if N.IsNull then Exit;
  S:= Integer(N.StartByte);
  L:= Integer(N.EndByte) - S;
  if (L <= 0) or (S < 0) or (S + L > Length(FSrc)) then Exit;
  Result:= TEncoding.UTF8.GetString(FSrc, S, L);
end;

procedure TParityRun.Emit(const ARule, AMsg: string; const ANode: TTSNode; const ASev: string);
var
  P: TTSPoint;
  F: TLintFinding;
begin
  P:= ANode.StartPoint;
  F:= Default(TLintFinding);
  F.RuleId   := ARule;
  F.Severity := ASev;
  F.Message  := AMsg;
  F.FilePath := FFile;
  F.StartLine:= Integer(P.Row) + 1;
  F.StartCol := Integer(P.Column) + 1;
  F.EndLine  := F.StartLine;
  F.EndCol   := F.StartCol + Length(Trim(NodeStr(ANode)));
  FFindings.Add(F);
end;

{ Leaf token texts of N in source order, comments dropped. }
procedure TParityRun.Tokens(const N: TTSNode; AOut: TStringList);
var I: Integer;
begin
  if N.IsNull or (N.NodeType = 'comment') then Exit;
  if N.ChildCount = 0 then
    AOut.Add(NodeStr(N))
  else
    for I:= 0 to N.ChildCount - 1 do Tokens(N.Child(I), AOut);
end;

{ The single statement node among N's children in [AFrom, ATo), ignoring comments and
  ';' tokens; a null node when there is none or more than one. }
function TParityRun.BranchNode(const N: TTSNode; AFrom, ATo: Integer): TTSNode;
var
  I    : Integer;
  C    : TTSNode;
  Count: Integer;
begin
  Result:= Default(TTSNode);
  Count:= 0;
  for I:= AFrom to ATo - 1 do
  begin
    C:= N.Child(I);
    if (C.NodeType = 'comment') or (C.NodeType = ';') then Continue;
    Inc(Count);
    Result:= C;
  end;
  if Count <> 1 then Result:= Default(TTSNode);
end;

function TParityRun.IsCallish(const N: TTSNode): Boolean;
begin
  Result:= False;
  if N.IsNull then Exit;
  if (N.NodeType = 'exprCall') or (N.NodeType = 'exprDot') or (N.NodeType = 'identifier') then
    Exit(True);
  if (N.NodeType = 'statement') and (N.NamedChildCount = 1) then
    Result:= IsCallish(N.NamedChild(0));
end;

{ True when N's then and else branches are token-identical (comments ignored) AND have
  one of the shapes this unit owns -- both begin..end blocks, or both call statements.
  ATh / AEl return the two branch nodes. }
function TParityRun.SameBranches(const N: TTSNode; out ATh, AEl: TTSNode): Boolean;
var
  I, KThen, KElse: Integer;
  TA, TB         : TStringList;
begin
  Result:= False;
  ATh:= Default(TTSNode);
  AEl:= Default(TTSNode);
  KThen:= -1;
  KElse:= -1;
  for I:= 0 to N.ChildCount - 1 do
  begin
    if (KThen < 0) and (N.Child(I).NodeType = 'kThen') then KThen:= I;
    if (KElse < 0) and (N.Child(I).NodeType = 'kElse') then KElse:= I;
  end;
  if (KThen < 0) or (KElse < KThen) then Exit;
  ATh:= BranchNode(N, KThen + 1, KElse);
  AEl:= BranchNode(N, KElse + 1, N.ChildCount);
  if ATh.IsNull or AEl.IsNull then Exit;
  if not (((ATh.NodeType = 'block') and (AEl.NodeType = 'block')) or (IsCallish(ATh) and IsCallish(AEl))) then Exit;
  TA:= TStringList.Create;
  TB:= TStringList.Create;
  try
    Tokens(ATh, TA);
    Tokens(AEl, TB);
    { the else branch's statement node swallows the statement's closing ';' }
    if (TA.Count > 0) and (TA[TA.Count - 1] = ';') then TA.Delete(TA.Count - 1);
    if (TB.Count > 0) and (TB[TB.Count - 1] = ';') then TB.Delete(TB.Count - 1);
    Result:= (TA.Count > 0) and (TA.Text = TB.Text);
  finally
    TB.Free;
    TA.Free;
  end;
end;

procedure TParityRun.CheckIfElse(const N: TTSNode);
var Th, El: TTSNode;
begin
  if SameBranches(N, Th, El) then
    Emit('identical-then-else', 'Both branches of this if-statement are identical', N, 'warning');
end;

{ Parameter type texts of a declProc's args, one entry per parameter NAME, in order
  (an empty string = untyped parameter). }
procedure TParityRun.CollectArgTypes(const N: TTSNode; AOut: TList<string>);
var
  I, J  : Integer;
  Ty, Id: TTSNode;
  TyTxt : string;
begin
  if N.IsNull or (N.NodeType = 'declProc') then Exit;
  if N.NodeType = 'declArg' then
  begin
    Ty:= N.ChildByField('type');
    TyTxt:= '';
    if not Ty.IsNull then TyTxt:= Trim(NodeStr(Ty));
    for J:= 0 to N.NamedChildCount - 1 do
    begin
      Id:= N.NamedChild(J);
      if (Id.NodeType = 'identifier') and (Ty.IsNull or (Integer(Id.StartByte) < Integer(Ty.StartByte))) then
        AOut.Add(TyTxt);
    end;
    Exit;
  end;
  for I:= 0 to N.NamedChildCount - 1 do CollectArgTypes(N.NamedChild(I), AOut);
end;

procedure TParityRun.AddSig(const AProc: TTSNode);
var
  Nm        : TTSNode;
  Key       : string;
  Types     : TList<string>;
  Arr, Prior: TArray<string>;
  I         : Integer;
begin
  Nm:= AProc.ChildByField('name');
  if Nm.IsNull then Exit;
  Key:= LowerCase(Trim(NodeStr(Nm)));
  if (Key = '') or Key.Contains('.') then Exit; { methods are not bare-name callees }
  Types:= TList<string>.Create;
  try
    CollectArgTypes(AProc.ChildByField('args'), Types);
    Arr:= Types.ToArray;
  finally
    Types.Free;
  end;
  if FSigs.TryGetValue(Key, Prior) then
  begin
    { an interface declaration + its implementation repeat ONE signature; a different one is an overload }
    if Length(Prior) <> Length(Arr) then
      FAmbig.AddOrSetValue(Key, True)
    else
      for I:= 0 to High(Arr) do
        if not SameText(Prior[I], Arr[I]) then FAmbig.AddOrSetValue(Key, True);
  end
  else
    FSigs.Add(Key, Arr);
end;

procedure TParityRun.CollectSigs(const N: TTSNode);
var
  I: Integer;
  H: TTSNode;
begin
  if N.IsNull then Exit;
  if N.NodeType = 'declProc' then
    AddSig(N)
  else if N.NodeType = 'defProc' then
  begin
    H:= N.ChildByField('header');
    if (not H.IsNull) and (H.NodeType = 'declProc') then AddSig(H);
  end;
  for I:= 0 to N.NamedChildCount - 1 do CollectSigs(N.NamedChild(I));
end;

{ W534: the locals of ADefProc (name -> type), the locals handed to a same-file
  interface parameter, and the free sites; a freed local that was handed over fires. }
procedure TParityRun.CheckRoutine(const ADefProc: TTSNode);
var
  Locals: TDictionary<string, string>;
  Passed: TDictionary<string, string>;
  Freed : TDictionary<string, TTSNode>;

  procedure ScanLocals(const N: TTSNode);
  var
    I, J  : Integer;
    Ty, Id: TTSNode;
  begin
    if N.IsNull or (N.NodeType = 'defProc') then Exit;
    if (N.NodeType = 'declVar') or (N.NodeType = 'varDef') or (N.NodeType = 'varAssignDef') then
    begin
      Ty:= N.ChildByField('type');
      if not Ty.IsNull then
        for J:= 0 to N.NamedChildCount - 1 do
        begin
          Id:= N.NamedChild(J);
          if (Id.NodeType = 'identifier') and (Integer(Id.StartByte) < Integer(Ty.StartByte)) then
            Locals.AddOrSetValue(LowerCase(NodeStr(Id)), Trim(NodeStr(Ty)));
        end;
    end;
    for I:= 0 to N.NamedChildCount - 1 do ScanLocals(N.NamedChild(I));
  end;

  procedure ScanCall(const N: TTSNode);
  var
    K, Idx      : Integer;
    Ent, Args, A: TTSNode;
    Sig         : TArray<string>;
    Key, Ty     : string;
  begin
    Ent := N.ChildByField('entity');
    Args:= N.ChildByField('args');
    if Ent.IsNull or (Ent.NodeType <> 'identifier') or Args.IsNull then Exit;
    Key:= LowerCase(NodeStr(Ent));
    if SameText(Key, 'freeandnil') then
    begin
      if (Args.NamedChildCount >= 1) and (Args.NamedChild(0).NodeType = 'identifier')
         and (not Freed.ContainsKey(LowerCase(NodeStr(Args.NamedChild(0))))) then
        Freed.Add(LowerCase(NodeStr(Args.NamedChild(0))), N);
      Exit;
    end;
    if (not FSigs.TryGetValue(Key, Sig)) or FAmbig.ContainsKey(Key) then Exit;
    Idx:= 0;
    for K:= 0 to Args.NamedChildCount - 1 do
    begin
      A:= Args.NamedChild(K);
      if A.NodeType = 'comment' then Continue;
      if (A.NodeType = 'identifier') and (Idx < Length(Sig)) and LooksInterface(Sig[Idx])
         and Locals.TryGetValue(LowerCase(NodeStr(A)), Ty) and LooksClass(Ty) then
        Passed.AddOrSetValue(LowerCase(NodeStr(A)), NodeStr(A));
      Inc(Idx);
    end;
  end;

  procedure ScanUse(const N: TTSNode);
  var
    I     : Integer;
    L, R  : TTSNode;
    IsFree: Boolean;
  begin
    if N.IsNull or (N.NodeType = 'defProc') then Exit;
    if N.NodeType = 'exprCall' then
      ScanCall(N)
    else if N.NodeType = 'exprDot' then
    begin
      L:= N.ChildByField('lhs');
      R:= N.ChildByField('rhs');
      IsFree:= (not L.IsNull) and (not R.IsNull) and (L.NodeType = 'identifier')
               and (R.NodeType = 'identifier') and SameText(NodeStr(R), 'Free');
      if IsFree and (not Freed.ContainsKey(LowerCase(NodeStr(L)))) then Freed.Add(LowerCase(NodeStr(L)), N);
    end;
    for I:= 0 to N.ChildCount - 1 do ScanUse(N.Child(I));
  end;

var
  Body: TTSNode;
  Pair: TPair<string, TTSNode>;
  Orig: string;
  I   : Integer;
begin
  Body:= ADefProc.ChildByField('body');
  if Body.IsNull then Exit;
  Locals:= TDictionary<string, string>.Create;
  Passed:= TDictionary<string, string>.Create;
  Freed := TDictionary<string, TTSNode>.Create;
  try
    for I:= 0 to ADefProc.NamedChildCount - 1 do ScanLocals(ADefProc.NamedChild(I));
    ScanUse(Body);
    for Pair in Freed do
      if Passed.TryGetValue(Pair.Key, Orig) then
        Emit('interface-object-mixing',
          Orig + ' is passed to a routine whose parameter is an interface (reference-counted lifetime) '
          + 'and is then manually freed in the same routine -- a dual handle risks a double free when '
          + 'the last interface reference drops. Keep it purely an object OR purely an interface.',
          Pair.Value, 'info');
  finally
    Freed.Free;
    Passed.Free;
    Locals.Free;
  end;
end;

procedure TParityRun.Walk(const N: TTSNode);
var I: Integer;
begin
  if N.IsNull then Exit;
  if N.NodeType = 'ifElse' then
    CheckIfElse(N)
  else if N.NodeType = 'defProc' then
    CheckRoutine(N);
  for I:= 0 to N.NamedChildCount - 1 do Walk(N.NamedChild(I));
end;

procedure TParityRun.Run(const ARoot: TTSNode);
begin
  CollectSigs(ARoot);
  Walk(ARoot);
end;

{ ---- autofix (G9) ------------------------------------------------------------- }

const
  STEP = '  '; { one indent level }

function Row0(const N: TTSNode): Integer;
begin
  Result:= Integer(N.StartPoint.Row);
end;

function EndRow0(const N: TTSNode): Integer;
begin
  Result:= Integer(N.EndPoint.Row);
end;

function IsPlainAscii(const S: string): Boolean;
var Ch: Char;
begin
  Result:= True;
  for Ch in S do
    if Ch > #127 then Exit(False);
end;

{ The ifElse whose kThen (AByThen) or own start (not AByThen) sits at ALine / ACol (1-based). }
function FindIfElse(const N: TTSNode; ALine, ACol: Integer; AByThen: Boolean): TTSNode;
var
  I    : Integer;
  Probe: TTSNode;
  P    : TTSPoint;
begin
  Result:= Default(TTSNode);
  if N.IsNull then Exit;
  if N.NodeType = 'ifElse' then
  begin
    Probe:= N;
    if AByThen then
      for I:= 0 to N.ChildCount - 1 do
        if N.Child(I).NodeType = 'kThen' then
        begin
          Probe:= N.Child(I);
          Break;
        end;
    P:= Probe.StartPoint;
    if (Integer(P.Row) + 1 = ALine) and (Integer(P.Column) + 1 = ACol) then Exit(N);
  end;
  for I:= 0 to N.NamedChildCount - 1 do
  begin
    Result:= FindIfElse(N.NamedChild(I), ALine, ACol, AByThen);
    if not Result.IsNull then Exit;
  end;
end;

function HasCall(const N: TTSNode): Boolean;
var I: Integer;
begin
  Result:= False;
  if N.IsNull then Exit;
  if (N.NodeType = 'exprCall') or (N.NodeType = 'inherited') or (N.NodeType = 'lambda') then Exit(True);
  for I:= 0 to N.NamedChildCount - 1 do
    if HasCall(N.NamedChild(I)) then Exit(True);
end;

{ True when no direct child of the ifElse is a comment (a fix would lose it). }
function NoDirectComment(const N: TTSNode): Boolean;
var I: Integer;
begin
  Result:= True;
  for I:= 0 to N.ChildCount - 1 do
    if N.Child(I).NodeType = 'comment' then Exit(False);
end;

{ The ifElse occupies whole lines: only blanks before it on its first line and only blanks
  or ';' after it on its last. AIndent is the first-line indent, ARest the text after it. }
function WholeLines(const N: TTSNode; ALines: TStringList; out AIndent: string; out ARest: string): Boolean;
var
  R0, R1: Integer;
  Pre   : string;
begin
  Result:= False;
  AIndent:= '';
  ARest:= '';
  R0:= Row0(N);
  R1:= EndRow0(N);
  if (R1 >= ALines.Count) or (not IsPlainAscii(ALines[R0])) or (not IsPlainAscii(ALines[R1])) then Exit;
  Pre:= Copy(ALines[R0], 1, Integer(N.StartPoint.Column));
  if Trim(Pre) <> '' then Exit;
  ARest:= Trim(Copy(ALines[R1], Integer(N.EndPoint.Column) + 1, MaxInt));
  if (ARest <> '') and (ARest <> ';') then Exit;
  AIndent:= Pre;
  Result:= True;
end;

function ReplaceEdit(const F: TLintFinding; const ANode: TTSNode; ALines: TStringList;
  const AText: string): TArray<TTextEdit>;
var E: TTextEdit;
begin
  E:= Default(TTextEdit);
  E.FilePath  := F.FilePath;
  E.Kind      := tekReplaceLines;
  E.Line      := Row0(ANode) + 1;
  E.EndLine   := EndRow0(ANode) + 1;
  E.Text      := AText;
  E.ExpectText:= ALines[Row0(ANode)];
  Result:= [E];
end;

{ A condition that 'not' binds to without parentheses. }
function IsAtomicCondition(const ACond: TTSNode): Boolean;
begin
  Result:= MatchStr(ACond.NodeType, ['identifier', 'exprCall', 'exprDot', 'exprParens', 'exprSubscript']);
end;

{ empty-conditional, shape 'if c then else s'  ->  'if not c then s'. Declines (no edits)
  for every other shape, when a comment would be lost, or when the if is the THEN branch
  of an if-else (the new, shorter if would capture that else). }
function FixEmptyThen(const F: TLintFinding; ALines: TStringList): TArray<TTextEdit>;  // dl:ok too-many-exit-points@3937 -- REVIEWED 2026-10-27: a guard-clause ladder; every Exit declines a shape the fix must not touch, and a flag would hide which guard fired
var
  PF          : TParsedFile;
  I, Par, Cond: TTSNode;
  E           : TTSNode;
  K, KElse    : Integer;
  R, R1       : Integer;
  Indent, Rest: string;
  CondTxt, Neg: string;
  Body        : TStringBuilder;
begin
  Result:= nil;
  PF:= TAstParseCache.Get(F.FilePath);
  if PF.Tree = nil then Exit;
  I:= FindIfElse(PF.Tree.RootNode, F.StartLine, F.StartCol, True);
  if I.IsNull or (not NoDirectComment(I)) then Exit;
  KElse:= -1;
  for K:= 0 to I.ChildCount - 1 do
    if I.Child(K).NodeType = 'kElse' then
    begin
      KElse:= K;
      Break;
    end;
  { kThen must be directly followed by kElse, and a statement must follow }
  if (KElse < 1) or (I.Child(KElse - 1).NodeType <> 'kThen') then Exit;
  E:= Default(TTSNode);
  for K:= KElse + 1 to I.ChildCount - 1 do
    if I.Child(K).NodeType <> ';' then
    begin
      E:= I.Child(K);
      Break;
    end;
  if E.IsNull then Exit;
  Par:= I.Parent;
  if (not Par.IsNull) and (Par.NodeType = 'ifElse') then
    for K:= 0 to Par.ChildCount - 1 do
      if (Par.Child(K).NodeType = 'kElse') and (Integer(I.StartByte) < Integer(Par.Child(K).StartByte)) then Exit;
  Cond:= I.ChildByField('condition');
  if Cond.IsNull or (Row0(Cond) <> EndRow0(Cond)) then Exit;
  if not WholeLines(I, ALines, Indent, Rest) then Exit;
  CondTxt:= Copy(ALines[Row0(Cond)], Integer(Cond.StartPoint.Column) + 1,
    Integer(Cond.EndPoint.Column) - Integer(Cond.StartPoint.Column));
  Neg:= if IsAtomicCondition(Cond) then 'not ' + CondTxt else 'not (' + CondTxt + ')';
  R1:= EndRow0(I);
  Body:= TStringBuilder.Create;
  try
    Body.Append(Indent + 'if ' + Neg + ' then');
    if Row0(E) > Row0(I.Child(KElse)) then
    begin
      { the statement starts its own line: keep its lines, and their layout, as they are }
      if Trim(Copy(ALines[Row0(E)], 1, Integer(E.StartPoint.Column))) <> '' then Exit;
      for R:= Row0(E) to R1 do Body.Append(sLineBreak + ALines[R]);
    end
    else
    begin
      { 'else s' on one line: move s down one level }
      if (Row0(E) <> R1) or (Row0(I.Child(KElse)) <> R1) then Exit;
      Body.Append(sLineBreak + Indent + STEP + Copy(ALines[R1], Integer(E.StartPoint.Column) + 1, MaxInt));
    end;
    Result:= ReplaceEdit(F, I, ALines, Body.ToString);
  finally
    Body.Free;
  end;
end;

{ identical-then-else, block / call shapes  ->  the then branch alone. Only when the
  condition holds no call (it could have a side effect). Registered RISKY: a bare
  identifier in the condition might still be a parameterless function. }
function FixIdenticalBlockBranches(const F: TLintFinding; ALines: TStringList): TArray<TTextEdit>;  // dl:ok too-many-exit-points@7e51 -- REVIEWED 2026-10-27: a guard-clause ladder; every Exit declines a shape the fix must not touch
var
  PF                : TParsedFile;
  Run               : TParityRun;
  I, Th, El         : TTSNode;
  Indent, Rest      : string;
  Body              : TStringBuilder;
  R, R0, R1, Delta  : Integer;
  K, TStartCol      : Integer;
  Line, Txt, LastTxt: string;
  HasSemi           : Boolean;
begin
  Result:= nil;
  PF:= TAstParseCache.Get(F.FilePath);
  if PF.Tree = nil then Exit;
  I:= FindIfElse(PF.Tree.RootNode, F.StartLine, F.StartCol, False);
  if I.IsNull or (not NoDirectComment(I)) or HasCall(I.ChildByField('condition')) then Exit;
  Run:= TParityRun.Create(F.FilePath, PF.Src);
  try
    if not Run.SameBranches(I, Th, El) then Exit;
  finally
    Run.Free;
  end;
  if not WholeLines(I, ALines, Indent, Rest) then Exit;
  R0:= Row0(Th);
  R1:= EndRow0(Th);
  TStartCol:= Integer(Th.StartPoint.Column);
  LastTxt:= Trim(Copy(ALines[EndRow0(I)], 1, Integer(I.EndPoint.Column)));
  HasSemi:= (Rest = ';') or ((LastTxt <> '') and (LastTxt[Length(LastTxt)] = ';'));
  Delta:= 0;
  if R0 > Row0(I) then
  begin
    if Trim(Copy(ALines[R0], 1, TStartCol)) <> '' then Exit;
    Delta:= TStartCol - Length(Indent);
    if Delta < 0 then Exit;
  end;
  Body:= TStringBuilder.Create;
  try
    for R:= R0 to R1 do
    begin
      Line:= ALines[R];
      if R = R1 then Line:= Copy(Line, 1, Integer(Th.EndPoint.Column));
      if R = R0 then
        Txt:= Indent + Copy(Line, TStartCol + 1, MaxInt)
      else
      begin
        for K:= 1 to Delta do
          if (Line <> '') and (Line[1] = ' ') then
            Delete(Line, 1, 1)
          else if Trim(Line) <> '' then
            Exit;
        Txt:= Line;
      end;
      if R > R0 then Body.Append(sLineBreak);
      Body.Append(Txt);
    end;
    Txt:= Body.ToString;
    while (Txt <> '') and (Txt[Length(Txt)] = ';') do Delete(Txt, Length(Txt), 1);
    if HasSemi then Txt:= Txt + ';';
    Result:= ReplaceEdit(F, I, ALines, Txt);
  finally
    Body.Free;
  end;
end;

{ identical-then-else, the registered entry point: block / call shapes first, then the
  single-assignment shape that FixIdenticalBlockBranches declines (lane A3's
  FixIdenticalAssignmentBranches). One RegisterFixer per rule id. }
function FixIdenticalBranches(const F: TLintFinding; ALines: TStringList): TArray<TTextEdit>;
begin
  Result:= FixIdenticalBlockBranches(F, ALines);
  if Result = nil then Result:= FixIdenticalAssignmentBranches(F, ALines);
end;

class function TParityExtChecker.Check(const AFile: string; const ACfg: TLintConfig;  // dl:ok unused-parameter@5fb0 -- REVIEWED 2026-10-27: fixed checker signature shared by every gate (CLI.pas); these rules are same-file and need neither config nor store
  const AStore: ISymbolStore; AFileId: Integer): TArray<TLintFinding>;  // dl:ok unused-parameter@9a67 -- REVIEWED 2026-10-27: fixed checker signature shared by every gate (CLI.pas)
var
  PF : TParsedFile;
  Run: TParityRun;
begin
  Result:= nil;
  PF:= TAstParseCache.Get(AFile);
  if PF.Tree = nil then Exit;
  Run:= TParityRun.Create(AFile, PF.Src);
  try
    Run.Run(PF.Tree.RootNode);
    Result:= Run.Findings;
  finally
    Run.Free;
  end;
end;

initialization
  RegisterFixer('empty-conditional', FixEmptyThen);
  RegisterFixer('identical-then-else', FixIdenticalBranches, True);

end.
