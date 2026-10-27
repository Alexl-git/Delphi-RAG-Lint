unit DRagLint.Diagnostics.DeclParityChecks;

{ Gap-rules wave (plan 2026-10-27-rule-gaps-and-compliance-plan.md), lane G7.
  The ids are in LINT_GATE_DECL_PARITY (CLI.pas) and in TRuleCatalog.BuiltinRegistry.
  Rules:
    hides-ancestor-virtual   : a method without override / reintroduce / overload / message
                               whose name is a virtual / dynamic / override method of an
                               ancestor (same file; plus cross-unit through the store).
    needless-exit            : Exit; / Exit(Result) as the last statement of a routine body.
    free-of-parameter        : P.Free / P.DisposeOf / FreeAndNil(P) on a by-value or const
                               parameter of the enclosing routine.
    property-accessor-name   : read / write accessor that is neither F<Prop> nor
                               Get<Prop> / Set<Prop>.
    unused-loop-variable     : for I := a to b do ... where I is not used in the body (OFF).
    property-references-itself (extension, accessor-body shape): a read accessor whose body
                               reads its own property, a write accessor that assigns it.
  Pure AST; AStore is consulted only by hides-ancestor-virtual for ancestors that are not
  declared in the file. }

interface

uses
  DRagLint.Core.Model
  , DRagLint.Core.Interfaces
  , DRagLint.Lint.Config
  ;

type
  /// <summary>Checker for the DeclParityChecks rules of the gap-rules wave (G7).</summary>
  /// <remarks>
  /// Stateless; thread-safe. Called from DoLint and DoLintAll behind
  /// LintRuleWants(rule, LINT_GATE_DECL_PARITY).
  /// </remarks>
  TDeclParityChecker = class
  public
    /// <summary>Runs the DeclParityChecks rules against one source file.</summary>
    /// <param name="AFile">Absolute path to the .pas/.inc source file.</param>
    /// <param name="ACfg">Effective lint configuration (unused by these rules).</param>
    /// <param name="AStore">Optional symbol store; nil when the run has no index. Used by hides-ancestor-virtual for ancestors declared in other units.</param>
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
  MAX_CHAIN = 16;

type
  TParityRun = class
  strict private
    FFile    : string;
    FSrc     : TBytes;
    FStore   : ISymbolStore;
    FFileId  : Integer;
    FFindings: TList<TLintFinding>;
    FParents : TDictionary<string, TArray<string>>;
    FVirt    : TObjectDictionary<string, TDictionary<string, Boolean>>;
    FReadAcc : TDictionary<string, string>;
    FWriteAcc: TDictionary<string, string>;
    FStoreVirt: TObjectDictionary<string, TDictionary<string, Boolean>>;
    function NodeStr(const N: TTSNode): string;
    function LowerText(const N: TTSNode): string;
    procedure EmitSpan(const AFrom, ATo: TTSNode; const ARule, AMsg, ASev: string);
    procedure EmitAt(const N: TTSNode; const ARule, AMsg, ASev: string);
    class function StripGeneric(const S: string): string; static;
    class function LastSegment(const S: string): string; static;
    class function HasKeyword(const N: TTSNode; const AKinds: array of string): Boolean; static;
    function IsDotRhs(const N: TTSNode): Boolean;
    function IsAssignLhs(const N: TTSNode): Boolean;
    function ClassNameOf(const ADeclType: TTSNode; out ACls: TTSNode): string;
    procedure GatherMembers(const N: TTSNode; AList: TList<TTSNode>);
    procedure CollectClass(const ACls: TTSNode; const AName: string);
    procedure CollectClasses(const N: TTSNode);
    function StoreVirtOf(const AParent: string): TDictionary<string, Boolean>;
    function InheritsVirtual(const AClass, AName: string; ADepth: Integer): Boolean;
    procedure CheckHides(const ACls: TTSNode; const AName: string);
    procedure CheckAccessorNames(const ACls: TTSNode);
    procedure CheckClasses(const N: TTSNode);
    procedure CheckNeedlessExit(const ADef: TTSNode);
    function IsParamIdent(const N: TTSNode; AParams: TDictionary<string, Boolean>): Boolean;
    procedure ScanFree(const N: TTSNode; AParams: TDictionary<string, Boolean>);
    procedure CheckFreeOfParam(const ADef: TTSNode);
    procedure ScanSelfRead(const N: TTSNode; const AProp: string);
    procedure ScanSelfWrite(const N: TTSNode; const AProp: string);
    procedure CheckAccessorBody(const ADef: TTSNode);
    function UsesName(const N: TTSNode; const AName: string): Boolean;
    procedure CheckLoop(const AFor: TTSNode);
    procedure VisitRoutines(const N: TTSNode);
  public
    constructor Create(const AFile: string; const ASrc: TBytes; const AStore: ISymbolStore; AFileId: Integer);
    destructor Destroy; override;
    function Run(const ARoot: TTSNode): TArray<TLintFinding>;
  end;

{ ---------------------------------------------------------------- plumbing }

constructor TParityRun.Create(const AFile: string; const ASrc: TBytes; const AStore: ISymbolStore;
  AFileId: Integer);
begin
  inherited Create;
  FFile     := AFile;
  FSrc      := ASrc;
  FStore    := AStore;
  FFileId   := AFileId;
  FFindings := TList<TLintFinding>.Create;
  FParents  := TDictionary<string, TArray<string>>.Create;
  FVirt     := TObjectDictionary<string, TDictionary<string, Boolean>>.Create([doOwnsValues]);
  FReadAcc  := TDictionary<string, string>.Create;
  FWriteAcc := TDictionary<string, string>.Create;
  FStoreVirt:= TObjectDictionary<string, TDictionary<string, Boolean>>.Create([doOwnsValues]);
end;

destructor TParityRun.Destroy;
begin
  FFindings.Free;
  FParents.Free;
  FVirt.Free;
  FReadAcc.Free;
  FWriteAcc.Free;
  FStoreVirt.Free;
  inherited Destroy;
end;

function TParityRun.NodeStr(const N: TTSNode): string;
var
  S, L: Integer;
begin
  Result:= '';
  if N.IsNull then Exit;
  S:= Integer(N.StartByte);
  L:= Integer(N.EndByte) - S;
  if (L <= 0) or (S < 0) or (S + L > Length(FSrc)) then Exit;
  Result:= TEncoding.UTF8.GetString(FSrc, S, L);
end;

function TParityRun.LowerText(const N: TTSNode): string;
begin
  Result:= LowerCase(StringReplace(Trim(NodeStr(N)), ' ', '', [rfReplaceAll]));
end;

{ Finding spanning AFrom..ATo (start of AFrom to the end of ATo). }
procedure TParityRun.EmitSpan(const AFrom, ATo: TTSNode; const ARule, AMsg, ASev: string);
var
  P, Q: TTSPoint;
  F   : TLintFinding;
begin
  P:= AFrom.StartPoint;
  Q:= ATo.EndPoint;
  F:= Default(TLintFinding);
  F.RuleId   := ARule;
  F.Severity := ASev;
  F.Message  := AMsg;
  F.FilePath := FFile;
  F.StartLine:= Integer(P.Row) + 1;
  F.StartCol := Integer(P.Column) + 1;
  F.EndLine  := Integer(Q.Row) + 1;
  F.EndCol   := Integer(Q.Column) + 1;
  FFindings.Add(F);
end;

procedure TParityRun.EmitAt(const N: TTSNode; const ARule, AMsg, ASev: string);
begin
  EmitSpan(N, N, ARule, AMsg, ASev);
end;

class function TParityRun.StripGeneric(const S: string): string;
var
  P: Integer;
begin
  P:= Pos('<', S);
  Result:= if P > 0 then Copy(S, 1, P - 1) else S;
end;

class function TParityRun.LastSegment(const S: string): string;
var
  P: Integer;
begin
  P:= LastDelimiter('.', S);
  Result:= if P > 0 then Copy(S, P + 1, MaxInt) else S;
end;

class function TParityRun.HasKeyword(const N: TTSNode; const AKinds: array of string): Boolean;
var
  I, J: Integer;
  C   : TTSNode;
begin
  Result:= False;
  for I:= 0 to N.NamedChildCount - 1 do
  begin
    C:= N.NamedChild(I);
    if MatchStr(C.NodeType, AKinds) then Exit(True);
    if C.NodeType = 'procAttribute' then
      for J:= 0 to C.NamedChildCount - 1 do
        if MatchStr(C.NamedChild(J).NodeType, AKinds) then Exit(True);
  end;
end;

function TParityRun.IsDotRhs(const N: TTSNode): Boolean;
var
  P, R: TTSNode;
begin
  P:= N.Parent;
  if P.IsNull or (P.NodeType <> 'exprDot') then Exit(False);
  R:= P.ChildByField('rhs');
  Result:= (not R.IsNull) and (R.StartByte = N.StartByte) and (R.EndByte = N.EndByte);
end;

function TParityRun.IsAssignLhs(const N: TTSNode): Boolean;
var
  P, L: TTSNode;
begin
  P:= N.Parent;
  if P.IsNull or (P.NodeType <> 'assignment') then Exit(False);
  L:= P.ChildByField('lhs');
  Result:= (not L.IsNull) and (L.StartByte = N.StartByte) and (L.EndByte = N.EndByte);
end;

{ ------------------------------------------------------------ class facts }

{ The declClass node of a declType (direct child or under its type node); lower class name. }
function TParityRun.ClassNameOf(const ADeclType: TTSNode; out ACls: TTSNode): string;
var
  J: Integer;
  C: TTSNode;
begin
  ACls:= Default(TTSNode);
  Result:= '';
  for J:= 0 to ADeclType.NamedChildCount - 1 do
  begin
    C:= ADeclType.NamedChild(J);
    if C.NodeType = 'declClass' then ACls:= C;
    if (C.NodeType = 'type') and (C.NamedChildCount > 0) and (C.NamedChild(0).NodeType = 'declClass') then
      ACls:= C.NamedChild(0);
  end;
  if not ACls.IsNull then
    Result:= LastSegment(StripGeneric(LowerText(ADeclType.ChildByField('name'))));
end;

{ Class members (declProc / declProp), looking through visibility sections. }
procedure TParityRun.GatherMembers(const N: TTSNode; AList: TList<TTSNode>);
var
  I: Integer;
  C: TTSNode;
begin
  for I:= 0 to N.NamedChildCount - 1 do
  begin
    C:= N.NamedChild(I);
    if MatchStr(C.NodeType, ['declProc', 'declProp']) then AList.Add(C)
    else if C.NodeType = 'declSection' then GatherMembers(C, AList);
  end;
end;

procedure TParityRun.CollectClass(const ACls: TTSNode; const AName: string);
var
  I       : Integer;
  C       : TTSNode;
  Parents : TList<string>;
  Members : TList<TTSNode>;
  Virt    : TDictionary<string, Boolean>;
  M, Acc  : TTSNode;
  Nm, Prop: string;
  Key     : string;
begin
  Parents:= TList<string>.Create;
  Members:= TList<TTSNode>.Create;
  Virt:= TDictionary<string, Boolean>.Create;
  try
    for I:= 0 to ACls.NamedChildCount - 1 do
    begin
      C:= ACls.NamedChild(I);
      if C.NodeType = 'typeref' then Parents.Add(LastSegment(StripGeneric(LowerText(C))));
    end;
    GatherMembers(ACls, Members);
    for M in Members do
      if M.NodeType = 'declProc' then
      begin
        if HasKeyword(M, ['kVirtual', 'kDynamic', 'kOverride']) then
          Virt.AddOrSetValue(LastSegment(LowerText(M.ChildByField('name'))), True);
      end
      else
      begin
        Prop:= LowerText(M.ChildByField('name'));
        Acc:= M.ChildByField('getter');
        if (not Acc.IsNull) and (Acc.NodeType = 'identifier') then
        begin
          Key:= AName + '|' + LowerText(Acc);
          if FReadAcc.ContainsKey(Key) and (FReadAcc[Key] <> Prop) then FReadAcc.AddOrSetValue(Key, '')
          else FReadAcc.AddOrSetValue(Key, Prop);
        end;
        Acc:= M.ChildByField('setter');
        if (not Acc.IsNull) and (Acc.NodeType = 'identifier') then
        begin
          Nm:= LowerText(Acc);
          Key:= AName + '|' + Nm;
          if FWriteAcc.ContainsKey(Key) and (FWriteAcc[Key] <> Prop) then FWriteAcc.AddOrSetValue(Key, '')
          else FWriteAcc.AddOrSetValue(Key, Prop);
        end;
      end;
    FParents.AddOrSetValue(AName, Parents.ToArray);
    FVirt.AddOrSetValue(AName, Virt);
    Virt:= nil;
  finally
    Virt.Free;
    Members.Free;
    Parents.Free;
  end;
end;

procedure TParityRun.CollectClasses(const N: TTSNode);
var
  I   : Integer;
  Cls : TTSNode;
  Name: string;
begin
  if N.IsNull then Exit;
  if N.NodeType = 'declType' then
  begin
    Name:= ClassNameOf(N, Cls);
    if (Name <> '') and (not FParents.ContainsKey(Name)) then CollectClass(Cls, Name);
  end;
  for I:= 0 to N.NamedChildCount - 1 do CollectClasses(N.NamedChild(I));
end;

{ ------------------------------------------------------ hides-ancestor-virtual }

{ Virtual methods the store knows for an ancestor declared in another unit (cached); never nil. }
function TParityRun.StoreVirtOf(const AParent: string): TDictionary<string, Boolean>;
var
  Names: TArray<string>;
  S    : string;
begin
  if FStoreVirt.TryGetValue(AParent, Result) then Exit;
  Result:= TDictionary<string, Boolean>.Create;
  FStoreVirt.Add(AParent, Result);
  if FStore = nil then Exit;
  Names:= FStore.GetVirtualMethodsIncludingAncestors(AParent, FFileId);
  for S in Names do Result.AddOrSetValue(LowerCase(S), True);
end;

{ True when a (transitive) ancestor of AClass declares AName virtual / dynamic / override. }
function TParityRun.InheritsVirtual(const AClass, AName: string; ADepth: Integer): Boolean;
var
  Parents: TArray<string>;
  P      : string;
  Virt   : TDictionary<string, Boolean>;
begin
  Result:= False;
  if (ADepth > MAX_CHAIN) or (not FParents.TryGetValue(AClass, Parents)) then Exit;
  for P in Parents do
  begin
    if FVirt.TryGetValue(P, Virt) then
    begin
      if Virt.ContainsKey(AName) or InheritsVirtual(P, AName, ADepth + 1) then Exit(True);
    end
    else if StoreVirtOf(P).ContainsKey(AName) then Exit(True);
  end;
end;

procedure TParityRun.CheckHides(const ACls: TTSNode; const AName: string);
var
  Members: TList<TTSNode>;
  M, Nm  : TTSNode;
  Method : string;
begin
  Members:= TList<TTSNode>.Create;
  try
    GatherMembers(ACls, Members);
    for M in Members do
    begin
      if M.NodeType <> 'declProc' then Continue;
      if HasKeyword(M, ['kOverride', 'kReintroduce', 'kOverload', 'kMessage']) then Continue;
      Nm:= M.ChildByField('name');
      Method:= LastSegment(LowerText(Nm));
      if (Method <> '') and InheritsVirtual(AName, Method, 0) then
        EmitAt(Nm, 'hides-ancestor-virtual',
          Format('Method "%s" hides a virtual method of an ancestor: add override (or reintroduce)',
            [Trim(NodeStr(Nm))]), 'warning');
    end;
  finally
    Members.Free;
  end;
end;

{ ---------------------------------------------------- property-accessor-name }

procedure TParityRun.CheckAccessorNames(const ACls: TTSNode);
var
  Members : TList<TTSNode>;
  AccUses    : TDictionary<string, Integer>;
  M, Acc  : TTSNode;
  Prop, A : string;
  Cnt     : Integer;

  procedure Count(const AAcc: TTSNode);
  var
    K: string;
  begin
    if AAcc.IsNull or (AAcc.NodeType <> 'identifier') then Exit;
    K:= LowerText(AAcc);
    AccUses.TryGetValue(K, Cnt);
    AccUses.AddOrSetValue(K, Cnt + 1);
  end;

  procedure Verify(const AAcc: TTSNode; const APrefix: string);
  begin
    if AAcc.IsNull or (AAcc.NodeType <> 'identifier') then Exit;
    A:= LowerText(AAcc);
    if (A = 'f' + Prop) or (A = LowerCase(APrefix) + Prop) then Exit;
    if AccUses.TryGetValue(A, Cnt) and (Cnt > 1) then Exit;
    EmitAt(AAcc, 'property-accessor-name',
      Format('Accessor "%s" of property "%s" should be named F%s or %s%s',
        [Trim(NodeStr(AAcc)), Trim(NodeStr(M.ChildByField('name'))),
         Trim(NodeStr(M.ChildByField('name'))), APrefix, Trim(NodeStr(M.ChildByField('name')))]), 'info');
  end;

begin
  Members:= TList<TTSNode>.Create;
  AccUses:= TDictionary<string, Integer>.Create;
  try
    GatherMembers(ACls, Members);
    for M in Members do
      if M.NodeType = 'declProp' then
      begin
        Count(M.ChildByField('getter'));
        if LowerText(M.ChildByField('setter')) <> LowerText(M.ChildByField('getter')) then
          Count(M.ChildByField('setter'));
      end;
    for M in Members do
    begin
      if M.NodeType <> 'declProp' then Continue;
      if (not M.ChildByField('index').IsNull) or HasKeyword(M, ['kIndex']) then Continue;
      Prop:= LowerText(M.ChildByField('name'));
      Acc:= M.ChildByField('getter');
      Verify(Acc, 'Get');
      Acc:= M.ChildByField('setter');
      Verify(Acc, 'Set');
    end;
  finally
    AccUses.Free;
    Members.Free;
  end;
end;

procedure TParityRun.CheckClasses(const N: TTSNode);
var
  I   : Integer;
  Cls : TTSNode;
  Name: string;
begin
  if N.IsNull then Exit;
  if N.NodeType = 'declType' then
  begin
    Name:= ClassNameOf(N, Cls);
    if Name <> '' then
    begin
      CheckHides(Cls, Name);
      CheckAccessorNames(Cls);
    end;
  end;
  for I:= 0 to N.NamedChildCount - 1 do CheckClasses(N.NamedChild(I));
end;

{ ------------------------------------------------------------ needless-exit }

procedure TParityRun.CheckNeedlessExit(const ADef: TTSNode);
var
  Body, Last: TTSNode;
  I         : Integer;
  T         : string;
begin
  Body:= ADef.ChildByField('body');
  if Body.IsNull or (Body.NodeType <> 'block') then Exit;
  Last:= Default(TTSNode);
  for I:= Body.NamedChildCount - 1 downto 0 do
    if not MatchStr(Body.NamedChild(I).NodeType, ['kEnd', 'comment', 'pp']) then
    begin
      Last:= Body.NamedChild(I);
      Break;
    end;
  if Last.IsNull or (Last.NodeType = 'kBegin') then Exit;
  T:= LowerText(Last);
  if EndsStr(';', T) then T:= Copy(T, 1, Length(T) - 1);
  if (T = 'exit') or (T = 'exit(result)') then
    EmitAt(Last, 'needless-exit', 'Exit as the last statement of the routine does nothing: remove it', 'hint');
end;

{ ------------------------------------------------------- free-of-parameter }

function TParityRun.IsParamIdent(const N: TTSNode; AParams: TDictionary<string, Boolean>): Boolean;
begin
  Result:= (N.NodeType = 'identifier') and AParams.ContainsKey(LowerText(N));
end;

procedure TParityRun.ScanFree(const N: TTSNode; AParams: TDictionary<string, Boolean>);
var
  I        : Integer;
  Lhs, Rhs : TTSNode;
  Ent, Args: TTSNode;
  Msg      : string;
begin
  if N.IsNull or (N.NodeType = 'defProc') then Exit;
  Msg:= 'Parameter "%s" is freed by the routine that received it: the caller''s reference now dangles';
  if N.NodeType = 'exprDot' then
  begin
    Lhs:= N.ChildByField('lhs');
    Rhs:= N.ChildByField('rhs');
    if (not Lhs.IsNull) and (not Rhs.IsNull) and (Lhs.NodeType = 'identifier')
       and MatchStr(LowerText(Rhs), ['free', 'disposeof']) and AParams.ContainsKey(LowerText(Lhs)) then
      EmitAt(N, 'free-of-parameter', Format(Msg, [Trim(NodeStr(Lhs))]), 'warning');
  end
  else if N.NodeType = 'exprCall' then
  begin
    Ent:= N.ChildByField('entity');
    Args:= N.ChildByField('args');
    if (not Ent.IsNull) and (not Args.IsNull) and (Args.NamedChildCount > 0)
       and SameText(LastSegment(Trim(NodeStr(Ent))), 'FreeAndNil')
       and IsParamIdent(Args.NamedChild(0), AParams) then
      EmitAt(N, 'free-of-parameter', Format(Msg, [Trim(NodeStr(Args.NamedChild(0)))]), 'warning');
  end;
  for I:= 0 to N.NamedChildCount - 1 do ScanFree(N.NamedChild(I), AParams);
end;

procedure TParityRun.CheckFreeOfParam(const ADef: TTSNode);
var
  Hdr, Args, Arg, Ty, C, Body: TTSNode;
  Params                     : TDictionary<string, Boolean>;
  I, J, K, TyStart           : Integer;
  ByValue                    : Boolean;
begin
  Hdr:= ADef.ChildByField('header');
  Body:= ADef.ChildByField('body');
  if Hdr.IsNull or Body.IsNull then Exit;
  Args:= Hdr.ChildByField('args');
  if Args.IsNull then Exit;
  Params:= TDictionary<string, Boolean>.Create;
  try
    for I:= 0 to Args.NamedChildCount - 1 do
    begin
      Arg:= Args.NamedChild(I);
      if Arg.NodeType <> 'declArg' then Continue;
      ByValue:= True;
      for K:= 0 to Arg.NamedChildCount - 1 do
        if MatchStr(Arg.NamedChild(K).NodeType, ['kVar', 'kOut']) then ByValue:= False;
      if not ByValue then Continue;
      Ty:= Arg.ChildByField('type');
      TyStart:= if Ty.IsNull then MaxInt else Integer(Ty.StartByte);
      for J:= 0 to Arg.NamedChildCount - 1 do
      begin
        C:= Arg.NamedChild(J);
        if (C.NodeType = 'identifier') and (Integer(C.StartByte) < TyStart) then
          Params.AddOrSetValue(LowerText(C), True);
      end;
    end;
    if Params.Count > 0 then ScanFree(Body, Params);
  finally
    Params.Free;
  end;
end;

{ ------------------------------------------ property-references-itself (body) }

procedure TParityRun.ScanSelfRead(const N: TTSNode; const AProp: string);
var
  I        : Integer;
  Lhs, Rhs : TTSNode;
begin
  if N.IsNull or (N.NodeType = 'defProc') then Exit;
  if N.NodeType = 'exprDot' then
  begin
    Lhs:= N.ChildByField('lhs');
    Rhs:= N.ChildByField('rhs');
    if (not Lhs.IsNull) and (not Rhs.IsNull) and SameText(Trim(NodeStr(Lhs)), 'Self')
       and (LowerText(Rhs) = AProp) and (not IsAssignLhs(N)) then
      EmitAt(N, 'property-references-itself',
        Format('Read accessor reads its own property "%s": infinite recursion; read the backing field',
          [Trim(NodeStr(Rhs))]), 'warning');
  end
  else if (N.NodeType = 'identifier') and (LowerText(N) = AProp) and (not IsDotRhs(N))
          and (not IsAssignLhs(N)) then
    EmitAt(N, 'property-references-itself',
      Format('Read accessor reads its own property "%s": infinite recursion; read the backing field',
        [Trim(NodeStr(N))]), 'warning');
  for I:= 0 to N.NamedChildCount - 1 do ScanSelfRead(N.NamedChild(I), AProp);
end;

procedure TParityRun.ScanSelfWrite(const N: TTSNode; const AProp: string);
var
  I  : Integer;
  Lhs: TTSNode;
  Txt: string;
begin
  if N.IsNull or (N.NodeType = 'defProc') then Exit;
  if N.NodeType = 'assignment' then
  begin
    Lhs:= N.ChildByField('lhs');
    Txt:= LowerText(Lhs);
    if (not Lhs.IsNull) and ((Txt = AProp) or (Txt = 'self.' + AProp)) then
      EmitAt(Lhs, 'property-references-itself',
        Format('Write accessor assigns its own property "%s": infinite recursion; assign the backing field',
          [Trim(NodeStr(Lhs))]), 'warning');
  end;
  for I:= 0 to N.NamedChildCount - 1 do ScanSelfWrite(N.NamedChild(I), AProp);
end;

procedure TParityRun.CheckAccessorBody(const ADef: TTSNode);
var
  Hdr, Body: TTSNode;
  Full, Cls, Method, Key, Prop: string;
  P: Integer;
begin
  Hdr:= ADef.ChildByField('header');
  Body:= ADef.ChildByField('body');
  if Hdr.IsNull or Body.IsNull then Exit;
  Full:= StripGeneric(LowerText(Hdr.ChildByField('name')));
  P:= LastDelimiter('.', Full);
  if P = 0 then Exit;
  Method:= Copy(Full, P + 1, MaxInt);
  Cls:= LastSegment(Copy(Full, 1, P - 1));
  Key:= Cls + '|' + Method;
  if FReadAcc.TryGetValue(Key, Prop) and (Prop <> '') then ScanSelfRead(Body, Prop);
  if FWriteAcc.TryGetValue(Key, Prop) and (Prop <> '') then ScanSelfWrite(Body, Prop);
end;

{ --------------------------------------------------------- unused-loop-variable }

function TParityRun.UsesName(const N: TTSNode; const AName: string): Boolean;
var
  I: Integer;
begin
  Result:= False;
  if N.IsNull then Exit;
  if N.NodeType = 'asm' then Exit(True);
  if (N.NodeType = 'identifier') and (LowerText(N) = AName) and (not IsDotRhs(N)) then Exit(True);
  for I:= 0 to N.NamedChildCount - 1 do
    if UsesName(N.NamedChild(I), AName) then Exit(True);
end;

procedure TParityRun.CheckLoop(const AFor: TTSNode);
var
  Start, Lhs, Body, VarNode: TTSNode;
  I                       : Integer;
begin
  Start:= AFor.ChildByField('start');
  Body:= AFor.ChildByField('body');
  if Start.IsNull or Body.IsNull then Exit;
  Lhs:= Start.ChildByField('lhs');
  if Lhs.IsNull then Exit;
  VarNode:= Default(TTSNode);
  if Lhs.NodeType = 'identifier' then VarNode:= Lhs
  else
    for I:= 0 to Lhs.NamedChildCount - 1 do
      if Lhs.NamedChild(I).NodeType = 'identifier' then
      begin
        VarNode:= Lhs.NamedChild(I);
        Break;
      end;
  if VarNode.IsNull then Exit;
  if not UsesName(Body, LowerText(VarNode)) then
    EmitAt(VarNode, 'unused-loop-variable',
      Format('Loop variable "%s" is never used in the loop body', [Trim(NodeStr(VarNode))]), 'hint');
end;

{ ------------------------------------------------------------------- driver }

procedure TParityRun.VisitRoutines(const N: TTSNode);
var
  I: Integer;
begin
  if N.IsNull then Exit;
  if N.NodeType = 'defProc' then
  begin
    CheckNeedlessExit(N);
    CheckFreeOfParam(N);
    CheckAccessorBody(N);
  end
  else if N.NodeType = 'for' then CheckLoop(N);
  for I:= 0 to N.NamedChildCount - 1 do VisitRoutines(N.NamedChild(I));
end;

function TParityRun.Run(const ARoot: TTSNode): TArray<TLintFinding>;
var
  Seen: TDictionary<string, Boolean>;
  Res : TList<TLintFinding>;
  F   : TLintFinding;
  Key : string;
begin
  CollectClasses(ARoot);
  CheckClasses(ARoot);
  VisitRoutines(ARoot);
  Seen:= TDictionary<string, Boolean>.Create;
  Res:= TList<TLintFinding>.Create;
  try
    for F in FFindings do
    begin
      Key:= F.RuleId + ':' + IntToStr(F.StartLine) + ':' + IntToStr(F.StartCol);
      if Seen.ContainsKey(Key) then Continue;
      Seen.Add(Key, True);
      Res.Add(F);
    end;
    Result:= Res.ToArray;
  finally
    Res.Free;
    Seen.Free;
  end;
end;

{ ------------------------------------------------------- TDeclParityChecker }

class function TDeclParityChecker.Check(const AFile: string; const ACfg: TLintConfig;  // dl:ok unused-parameter@5416 -- fixed checker signature shared by every gate unit
  const AStore: ISymbolStore; AFileId: Integer): TArray<TLintFinding>;
var
  PF : TParsedFile;
  Run: TParityRun;
begin
  Result:= nil;
  PF:= TAstParseCache.Get(AFile);
  if (PF.Tree = nil) or (PF.Src = nil) then Exit;
  Run:= TParityRun.Create(AFile, PF.Src, AStore, AFileId);
  try
    Result:= Run.Run(PF.Tree.RootNode);
  finally
    Run.Free;
  end;
end;

end.
