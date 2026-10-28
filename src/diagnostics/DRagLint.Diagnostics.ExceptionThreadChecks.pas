unit DRagLint.Diagnostics.ExceptionThreadChecks;

{ Gap-rules wave (plan 2026-10-27-rule-gaps-and-compliance-plan.md), lane G6.
  G6 implements the four rules (AST walk only; no index needed).
  The ids are already in LINT_GATE_EXCEPTION_THREAD (CLI.pas) and in
  TRuleCatalog.BuiltinRegistry -- a lane registers nothing new in CLI.pas or
  RuleCatalog.pas.
  Rules: exception-escapes-thread, raise-in-destructor, network-client-without-timeout, closure-captures-loop-local. }

interface

uses
  DRagLint.Core.Model
  , DRagLint.Core.Interfaces
  , DRagLint.Lint.Config
  ;

type
  /// <summary>Checker for the ExceptionThreadChecks rules of the gap-rules wave (G6).</summary>
  /// <remarks>
  /// Stateless; thread-safe. Called from DoLint and DoLintAll behind
  /// LintRuleWants(rule, LINT_GATE_EXCEPTION_THREAD).
  /// </remarks>
  TExceptionThreadChecker = class
  public
    /// <summary>Runs the ExceptionThreadChecks rules against one source file.</summary>
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
  RULE_THREAD   = 'exception-escapes-thread';
  RULE_DTOR     = 'raise-in-destructor';
  RULE_NET      = 'network-client-without-timeout';
  RULE_CLOSURE  = 'closure-captures-loop-local';
  NET_CLIENTS: array[0..8] of string = (
    'tidhttp', 'tidtcpclient', 'tidsmtp', 'tidpop3', 'tidftp', 'tidimap4',
    'tnethttpclient', 'thttpclient', 'trestclient');
  ASYNC_CALLS: array[0..4] of string = (
    'tthread.queue', 'tthread.forcequeue', 'ttask.run', 'tthread.createanonymousthread', 'ttask.future');
  GUARDED_CALLS: array[0..1] of string = ('tthread.createanonymousthread', 'ttask.run');
  LOOP_NODES: array[0..3] of string = ('for', 'foreach', 'while', 'repeat');
  MAX_ANCESTRY = 16;

class function TExceptionThreadChecker.Check(const AFile: string; const ACfg: TLintConfig;  // dl:ok unused-parameter@5857 -- signature fixed by the shared checker gate; no thresholds
  const AStore: ISymbolStore; AFileId: Integer): TArray<TLintFinding>;  // dl:ok unused-parameter@9a67 -- AST-only checker, needs no index
var
  Src      : TBytes;
  PF       : TParsedFile;
  Findings : TList<TLintFinding>;
  ParentOf : TDictionary<string, string>;
  ExecOvr  : TDictionary<string, Boolean>;
  AllNodes : TList<TTSNode>;
  Node     : TTSNode;

  function NodeStr(const N: TTSNode): string;
  var
    S, E, L: Integer;
  begin
    Result:= '';
    if N.IsNull then Exit;
    S:= Integer(N.StartByte);
    E:= Integer(N.EndByte);
    L:= E - S;
    if (L <= 0) or (S < 0) or (E > Length(Src)) then Exit;
    Result:= TEncoding.UTF8.GetString(Src, S, L);
  end;

  { Lower-cased text, blanks removed, a leading 'self.' dropped. }
  function Canon(const AText: string): string;
  begin
    Result:= LowerCase(StringReplace(StringReplace(StringReplace(Trim(AText), ' ', '', [rfReplaceAll]),
      #13, '', [rfReplaceAll]), #10, '', [rfReplaceAll]));
    if StartsText('self.', Result) then Delete(Result, 1, Length('self.'));
  end;

  function InList(const AValue: string; const AList: array of string): Boolean;
  var
    I: Integer;
  begin
    Result:= False;
    for I:= Low(AList) to High(AList) do
      if AValue = AList[I] then Exit(True);
  end;

  procedure Emit(const ANode: TTSNode; const ARule, AMsg: string);
  var
    P: TTSPoint;
    F: TLintFinding;
  begin
    P:= ANode.StartPoint;
    F:= Default(TLintFinding);
    F.RuleId   := ARule;
    F.Severity := 'warning';
    F.Message  := AMsg;
    F.FilePath := AFile;
    F.StartLine:= Integer(P.Row) + 1;
    F.StartCol := Integer(P.Column) + 1;
    F.EndLine  := F.StartLine;
    F.EndCol   := F.StartCol;
    Findings.Add(F);
  end;

  { Appends N and every named descendant (document order) to AList. }
  procedure Flatten(const N: TTSNode; const AList: TList<TTSNode>);
  var
    I: Integer;
  begin
    if N.IsNull then Exit;
    AList.Add(N);
    for I:= 0 to N.NamedChildCount - 1 do Flatten(N.NamedChild(I), AList);
  end;

  function Nodes(const N: TTSNode): TList<TTSNode>;
  begin
    Result:= TList<TTSNode>.Create;
    Flatten(N, Result);
  end;

  function HasExcept(const ATry: TTSNode): Boolean;
  var
    I: Integer;
  begin
    Result:= False;
    for I:= 0 to ATry.ChildCount - 1 do
      if ATry.Child(I).NodeType = 'kExcept' then Exit(True);
  end;

  { True when ANode holds a try..except outside any nested routine or lambda. }
  function ContainsTryExcept(const ANode: TTSNode): Boolean;
  var
    I: Integer;
  begin
    Result:= False;
    if ANode.IsNull then Exit;
    if (ANode.NodeType = 'lambda') or (ANode.NodeType = 'defProc') then Exit;
    if (ANode.NodeType = 'try') and HasExcept(ANode) then Exit(True);
    for I:= 0 to ANode.NamedChildCount - 1 do
      if ContainsTryExcept(ANode.NamedChild(I)) then Exit(True);
  end;

  { An Execute / thread body is guarded when a try..except is a direct statement
    of it (possibly inside a nested begin..end) or sits inside a top-level loop. }
  function Guarded(const ABody: TTSNode): Boolean;
  var
    I  : Integer;
    Kid: TTSNode;
  begin
    Result:= False;
    if ABody.IsNull then Exit;
    for I:= 0 to ABody.NamedChildCount - 1 do
    begin
      Kid:= ABody.NamedChild(I);
      if (Kid.NodeType = 'try') and HasExcept(Kid) then Exit(True);
      if Kid.NodeType = 'block' then
      begin
        if Guarded(Kid) then Exit(True);
      end
      else if InList(Kid.NodeType, LOOP_NODES) and ContainsTryExcept(Kid) then
        Exit(True);
    end;
  end;

  function IsThreadClass(const AName: string): Boolean;
  var
    Cur, Par: string;
    Depth   : Integer;
  begin
    Result:= False;
    Cur:= AName;
    for Depth:= 1 to MAX_ANCESTRY do
    begin
      if not ParentOf.TryGetValue(Cur, Par) then Exit;
      if (Length(Par) >= Length('tthread')) and StartsText('t', Par) and EndsText('thread', Par) then Exit(True);
      Cur:= Par;
    end;
  end;

  procedure CollectClass(const N: TTSNode);
  var
    Cls, TypeN, Sect, Proc: TTSNode;
    Name, Par, MethName, Attr: string;
    I, J, K: Integer;
  begin
    Name:= Canon(NodeStr(N.ChildByField('name')));
    Cls:= Default(TTSNode);
    TypeN:= N.ChildByField('type');
    for I:= 0 to TypeN.NamedChildCount - 1 do
      if TypeN.NamedChild(I).NodeType = 'declClass' then Cls:= TypeN.NamedChild(I);
    if Cls.IsNull or (Name = '') then Exit;
    Par:= '';
    for I:= 0 to Cls.NamedChildCount - 1 do
      if (Par = '') and (Cls.NamedChild(I).NodeType = 'typeref') then Par:= Canon(NodeStr(Cls.NamedChild(I)));
    K:= LastDelimiter('.', Par);
    if K > 0 then Par:= Copy(Par, K + 1, MaxInt);
    if Par <> '' then ParentOf.AddOrSetValue(Name, Par);
    for I:= 0 to Cls.NamedChildCount - 1 do
    begin
      Sect:= Cls.NamedChild(I);
      if Sect.NodeType <> 'declSection' then Continue;
      for J:= 0 to Sect.NamedChildCount - 1 do
      begin
        Proc:= Sect.NamedChild(J);
        if Proc.NodeType <> 'declProc' then Continue;
        MethName:= Canon(NodeStr(Proc.ChildByField('name')));
        Attr:= Canon(NodeStr(Proc.ChildByField('attribute')));
        if (MethName = 'execute') and ContainsText(Attr, 'override') then ExecOvr.AddOrSetValue(Name, True);
      end;
    end;
  end;

  procedure CheckExecute(const ADefProc: TTSNode);
  var
    Hdr, NameN: TTSNode;
    Cls, Meth : string;
  begin
    Hdr:= ADefProc.ChildByField('header');
    NameN:= Hdr.ChildByField('name');
    if NameN.IsNull or (NameN.NodeType <> 'genericDot') then Exit;
    Cls := Canon(NodeStr(NameN.ChildByField('lhs')));
    Meth:= Canon(NodeStr(NameN.ChildByField('rhs')));
    if (Meth <> 'execute') or (not ExecOvr.ContainsKey(Cls)) or (not IsThreadClass(Cls)) then Exit;
    if not Guarded(ADefProc.ChildByField('body')) then
      Emit(Hdr, RULE_THREAD, Format('%s.Execute has no top-level try..except -- an exception escaping a TThread ' +
        'terminates the thread silently (or the process); catch it and report it', [NodeStr(NameN.ChildByField('lhs'))]));
  end;

  procedure CheckAsyncLambda(const ALambda: TTSNode);
  var
    Args, Call: TTSNode;
  begin
    Args:= ALambda.Parent;
    if Args.IsNull or (Args.NodeType <> 'exprArgs') then Exit;
    Call:= Args.Parent;
    if Call.IsNull or (Call.NodeType <> 'exprCall') then Exit;
    if not InList(Canon(NodeStr(Call.ChildByField('entity'))), GUARDED_CALLS) then Exit;
    if not Guarded(ALambda.ChildByField('body')) then
      Emit(ALambda, RULE_THREAD, Format('anonymous method passed to %s has no top-level try..except -- an exception ' +
        'escaping it is lost or kills the worker; catch it inside', [NodeStr(Call.ChildByField('entity'))]));
  end;

  { Walks a destructor body; AProtected = inside the try part of a try..except. }
  procedure ScanRaise(const N: TTSNode; AProtected: Boolean);
  var
    I      : Integer;
    HasExc : Boolean;
    InTry  : Boolean;
    Kid    : TTSNode;
  begin
    if N.IsNull then Exit;
    if (N.NodeType = 'lambda') or (N.NodeType = 'defProc') then Exit;
    if N.NodeType = 'raise' then
    begin
      if not AProtected then
        Emit(N, RULE_DTOR, 'raise in a destructor -- an exception leaving Destroy skips the remaining cleanup ' +
          'and aborts unwinding; swallow or log it instead');
      Exit;
    end;
    if N.NodeType = 'try' then
    begin
      HasExc:= HasExcept(N);
      InTry := True;
      for I:= 0 to N.ChildCount - 1 do
      begin
        Kid:= N.Child(I);
        if (Kid.NodeType = 'kExcept') or (Kid.NodeType = 'kFinally') then InTry:= False;
        if Kid.IsNamed then ScanRaise(Kid, AProtected or (HasExc and InTry));
      end;
      Exit;
    end;
    for I:= 0 to N.NamedChildCount - 1 do ScanRaise(N.NamedChild(I), AProtected);
  end;

  procedure CheckDestructor(const ADefProc: TTSNode);
  var
    Hdr: TTSNode;
  begin
    Hdr:= ADefProc.ChildByField('header');
    if Hdr.IsNull or (Hdr.ChildCount = 0) or (Hdr.Child(0).NodeType <> 'kDestructor') then Exit;
    ScanRaise(ADefProc.ChildByField('body'), False);
  end;

  { ---- network-client-without-timeout ---- }

  function SetsTimeout(const ARoot: TTSNode; const ATarget: string): Boolean;
  var
    All: TList<TTSNode>;
    N  : TTSNode;
    L  : string;
  begin
    Result:= False;
    All:= Nodes(ARoot);
    try
      for N in All do
      begin
        if N.NodeType <> 'assignment' then Continue;
        L:= Canon(NodeStr(N.ChildByField('lhs')));
        if StartsText(ATarget + '.', L) and EndsText('timeout', L) then Exit(True);
      end;
    finally
      All.Free;
    end;
  end;

  { The object is handed to some other routine (which may configure it); Free / FreeAndNil do not count. }
  function PassedAsArgument(const ARoot: TTSNode; const ATarget: string): Boolean;
  var
    All   : TList<TTSNode>;
    N     : TTSNode;
    I     : Integer;
    Callee: string;
  begin
    Result:= False;
    All:= Nodes(ARoot);
    try
      for N in All do
      begin
        if (N.NodeType <> 'exprArgs') or N.Parent.IsNull or (N.Parent.NodeType <> 'exprCall') then Continue;
        Callee:= Canon(NodeStr(N.Parent.ChildByField('entity')));
        if EndsText('free', Callee) or EndsText('freeandnil', Callee) then Continue;
        for I:= 0 to N.NamedChildCount - 1 do
          if Canon(NodeStr(N.NamedChild(I))) = ATarget then Exit(True);
      end;
    finally
      All.Free;
    end;
  end;

  { Lower-cased names declared in the routine's own var section. }
  function LocalNames(const ADefProc: TTSNode): TList<string>;
  var
    All: TList<TTSNode>;
    N  : TTSNode;
  begin
    Result:= TList<string>.Create;
    All:= Nodes(ADefProc.ChildByField('local'));
    try
      for N in All do
        if N.NodeType = 'declVar' then Result.Add(Canon(NodeStr(N.ChildByField('name'))));
    finally
      All.Free;
    end;
  end;

  procedure CheckNetworkIn(const ADefProc, ARoot: TTSNode);
  var
    Locals: TList<string>;
    All   : TList<TTSNode>;
    N, Rhs, Scope: TTSNode;
    Target, Ctor : string;
  begin
    Locals:= LocalNames(ADefProc);
    All   := Nodes(ADefProc.ChildByField('body'));
    try
      for N in All do
      begin
        if N.NodeType <> 'assignment' then Continue;
        Rhs:= N.ChildByField('rhs');
        if Rhs.IsNull then Continue;
        Ctor:= Canon(NodeStr(if Rhs.NodeType = 'exprCall' then Rhs.ChildByField('entity') else Rhs));
        if not EndsText('.create', Ctor) then Continue;
        if not InList(Copy(Ctor, 1, Length(Ctor) - Length('.create')), NET_CLIENTS) then Continue;
        Target:= Canon(NodeStr(N.ChildByField('lhs')));
        Scope:= if Locals.IndexOf(Target) >= 0 then ADefProc else ARoot;
        if not (SetsTimeout(Scope, Target) or PassedAsArgument(Scope, Target)) then
          Emit(N, RULE_NET, Format('%s is created without any timeout being set on it -- a stalled peer blocks ' +
            'the call forever; assign ReadTimeout / ConnectTimeout (or the client''s equivalent)',
            [NodeStr(N.ChildByField('lhs'))]));
      end;
    finally
      All.Free;
      Locals.Free;
    end;
  end;

  { ---- closure-captures-loop-local ---- }

  function IsAsyncContext(const ALambda: TTSNode): Boolean;
  var
    Par, Gp: TTSNode;
    Callee, Lhs: string;
    K: Integer;
  begin
    Result:= False;
    Par:= ALambda.Parent;
    if Par.IsNull then Exit;
    Gp:= Par.Parent;
    if (Par.NodeType = 'exprArgs') and (not Gp.IsNull) and (Gp.NodeType = 'exprCall') then
    begin
      Callee:= Canon(NodeStr(Gp.ChildByField('entity')));
      if InList(Callee, ASYNC_CALLS) then Exit(True);
      K:= LastDelimiter('.', Callee);
      if (K > 0) and (Copy(Callee, K + 1, MaxInt) = 'add') then Exit(True);
    end
    else if Par.NodeType = 'assignment' then
    begin
      Lhs:= Canon(NodeStr(Par.ChildByField('lhs')));
      K:= LastDelimiter('.', Lhs);
      if (K > 0) and StartsText('on', Copy(Lhs, K + 1, MaxInt)) then Exit(True);
    end;
  end;

  { Adds to AAssigned every routine local assigned in ALoop's body before byte AUntil. }
  procedure AddLoopAssigned(const ALoop: TTSNode; AUntil: Cardinal; const ALocals, AAssigned: TList<string>);
  var
    Body, N  : TTSNode;
    All      : TList<TTSNode>;
    BodyStart: Cardinal;
    Nm       : string;
  begin
    Body:= ALoop.ChildByField('body');
    BodyStart:= if Body.IsNull then ALoop.StartByte else Body.StartByte;
    All:= Nodes(ALoop);
    try
      for N in All do
      begin
        if (N.NodeType <> 'assignment') or (N.StartByte < BodyStart) or (N.EndByte > AUntil) then Continue;
        Nm:= Canon(NodeStr(N.ChildByField('lhs')));
        if (ALocals.IndexOf(Nm) >= 0) and (AAssigned.IndexOf(Nm) < 0) then AAssigned.Add(Nm);
      end;
    finally
      All.Free;
    end;
  end;

  procedure CheckClosure(const ALambda: TTSNode);
  var
    Anc, Routine, N: TTSNode;
    Locals   : TList<string>;
    Assigned : TList<string>;
    Params   : TList<string>;
    All      : TList<TTSNode>;
    LamStart : Cardinal;
    Nm       : string;
  begin
    if not IsAsyncContext(ALambda) then Exit;
    Routine:= ALambda.Parent;
    while (not Routine.IsNull) and (Routine.NodeType <> 'defProc') do Routine:= Routine.Parent;
    if Routine.IsNull then Exit;
    Locals  := LocalNames(Routine);
    Assigned:= TList<string>.Create;
    Params  := TList<string>.Create;
    try
      All:= Nodes(ALambda.ChildByField('args'));
      try
        for N in All do
          if N.NodeType = 'declArg' then Params.Add(Canon(NodeStr(N.ChildByField('name'))));
      finally
        All.Free;
      end;
      LamStart:= ALambda.StartByte;
      Anc:= ALambda.Parent;
      while (not Anc.IsNull) and (Anc.StartByte <> Routine.StartByte) do
      begin
        if InList(Anc.NodeType, LOOP_NODES) then
        begin
          AddLoopAssigned(Anc, LamStart, Locals, Assigned);
        end;
        Anc:= Anc.Parent;
      end;
      if Assigned.Count = 0 then Exit;
      All:= Nodes(ALambda.ChildByField('body'));
      try
        for N in All do
        begin
          if N.NodeType <> 'identifier' then Continue;
          if (not N.Parent.IsNull) and (N.Parent.NodeType = 'exprDot')
            and (N.Parent.ChildByField('rhs').StartByte = N.StartByte) then Continue;
          Nm:= Canon(NodeStr(N));
          if (Assigned.IndexOf(Nm) >= 0) and (Params.IndexOf(Nm) < 0) then
          begin
            Emit(ALambda, RULE_CLOSURE, Format('anonymous method captures ''%s'', which is assigned inside the ' +
              'enclosing loop -- it runs later and sees the variable''s last value, not this iteration''s; pass it ' +
              'through a per-iteration copy', [NodeStr(N)]));
            Break;
          end;
        end;
      finally
        All.Free;
      end;
    finally
      Params.Free;
      Assigned.Free;
      Locals.Free;
    end;
  end;

begin
  Result:= nil;
  PF:= TAstParseCache.Get(AFile);
  if PF.Tree = nil then Exit;
  Src:= PF.Src;
  Findings:= TList<TLintFinding>.Create;
  ParentOf:= TDictionary<string, string>.Create;
  ExecOvr := TDictionary<string, Boolean>.Create;
  try
    AllNodes:= Nodes(PF.Tree.RootNode);
    try
      for Node in AllNodes do
        if Node.NodeType = 'declType' then CollectClass(Node);
      for Node in AllNodes do
        if Node.NodeType = 'defProc' then
        begin
          CheckExecute(Node);
          CheckDestructor(Node);
          CheckNetworkIn(Node, PF.Tree.RootNode);
        end
        else if Node.NodeType = 'lambda' then
        begin
          CheckAsyncLambda(Node);
          CheckClosure(Node);
        end;
    finally
      AllNodes.Free;
    end;
    Result:= Findings.ToArray;
  finally
    ExecOvr.Free;
    ParentOf.Free;
    Findings.Free;
  end;
end;

end.
