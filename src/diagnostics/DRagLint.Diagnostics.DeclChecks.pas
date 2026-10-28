unit DRagLint.Diagnostics.DeclChecks;

{ Clippy-parity wave (plan 2026-10-27-clippy-rules-plan.md), lane L7.
  Rules (all OFF by default; ids/catalog/gate registered by L0):
    missing-const-param   : a by-value parameter of a managed type (string, interface,
                            dynamic array, Variant) that the routine never assigns,
                            never hands to a modifying intrinsic / same-unit routine
                            with a var parameter, and never takes the address of.
    local-shadows-field   : a local (or inline) var, or a parameter, named like a field of the method's
                            own class or of an ancestor declared in the same file.
    method-could-be-static: a plain method whose body touches nothing of its class.
  Pure AST, same-file class knowledge. AStore is accepted for the common checker
  signature but not consulted: a class whose ancestry leaves the file is skipped by
  method-could-be-static instead of guessed at. }

interface

uses
  DRagLint.Core.Model
  , DRagLint.Core.Interfaces
  , DRagLint.Lint.Config
  ;

type
  /// <summary>Checker for the missing-const-param, local-shadows-field and method-could-be-static rules.</summary>
  /// <remarks>
  /// Stateless; thread-safe. Called from DoLint and DoLintAll behind
  /// LintRuleWants(rule, LINT_GATE_DECL). Skips (never reports) virtual, override,
  /// dynamic, message, abstract and external methods, event handlers (first parameter
  /// named Sender) and methods whose address is taken anywhere in the file.
  /// </remarks>
  TDeclChecker = class
  public
    /// <summary>Runs the DeclChecks rules against one source file.</summary>
    /// <param name="AFile">Absolute path to the .pas/.inc source file.</param>
    /// <param name="ACfg">Effective lint configuration (unused by these rules).</param>
    /// <param name="AStore">Optional symbol store; nil when the run has no index. Not consulted.</param>
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
  { Intrinsics / RTL routines that write through a var parameter. }
  MODIFYING_CALLS: array[0..21] of string = (
    'inc', 'dec', 'setlength', 'delete', 'insert', 'include', 'exclude', 'val', 'move',
    'fillchar', 'read', 'readln', 'str', 'uniquestring', 'setstring', 'swap', 'exchange',
    'zeromemory', 'fillmemory', 'copymemory', 'sort', 'reverse');
  { Members every class inherits from TObject / TPersistent / TInterfacedObject. }
  ROOT_MEMBERS: array[0..28] of string = (
    'free', 'classname', 'classtype', 'inheritsfrom', 'tostring', 'destroy', 'create',
    'gethashcode', 'equals', 'fieldaddress', 'methodaddress', 'dispatch', 'disposeof',
    'beforedestruction', 'afterconstruction', 'classparent', 'instancesize', 'classnameis',
    'unitname', 'getinterface', 'safecallexception', 'newinstance', 'freeinstance',
    'cleanupinstance', 'defaulthandler', 'assign', 'assignto', 'getowner', 'queryinterface');
  ROOT_CLASSES: array[0..2] of string = ('tobject', 'tinterfacedobject', 'tpersistent');
  MANAGED_TYPES: array[0..10] of string = (
    'string', 'ansistring', 'unicodestring', 'widestring', 'rawbytestring', 'utf8string',
    'variant', 'olevariant', 'tbytes', 'tstringdynarray', 'iinterface');
  MAX_CHAIN = 16;

type
  TClassInfo = class
  public
    Parents : TList<string>;  // dl:ok public-field@f304 -- plain data holder private to this unit
    HasIntf : Boolean;  // dl:ok public-field@446f -- plain data holder private to this unit
    Members : TDictionary<string, Boolean>;  // dl:ok public-field@690a -- plain data holder private to this unit
    Fields  : TDictionary<string, Boolean>;  // dl:ok public-field@f78b -- plain data holder private to this unit
    NoStatic: TDictionary<string, Boolean>;  // dl:ok public-field@886b -- plain data holder private to this unit
    NoConst : TDictionary<string, Boolean>;  // dl:ok public-field@ec89 -- plain data holder private to this unit
    constructor Create;
    destructor Destroy; override;
  end;

  TDeclRun = class
  strict private
    FFile      : string;
    FSrc       : TBytes;
    FFindings  : TList<TLintFinding>;
    FClasses   : TObjectDictionary<string, TClassInfo>;
    FAddrTaken : TDictionary<string, Boolean>;
    FVarRoutine: TDictionary<string, Boolean>;
    function NodeStr(const N: TTSNode): string;
    procedure EmitAt(const N: TTSNode; const ARule, AMsg, ASev: string);
    function LowerText(const N: TTSNode): string;
    function IsDotRhs(const N: TTSNode): Boolean;
    function RootName(const N: TTSNode): string;
    function IsLeafSelf(const N: TTSNode): Boolean;
    class function StripGeneric(const S: string): string; static;
    class function LastSegment(const S: string): string; static;
    class function IsManagedType(const AType: string): Boolean; static;
    class function IsInterfaceName(const S: string): Boolean; static;
    class function HasKeyword(const N: TTSNode; const AKinds: array of string): Boolean; static;
    procedure NoteAddr(const N: TTSNode);
    procedure CollectAddrTaken(const N: TTSNode);
    procedure CollectVarRoutines(const N: TTSNode);
    procedure CollectClasses(const N: TTSNode);
    procedure ReadClass(const ACls: TTSNode; AInfo: TClassInfo);
    procedure ReadMember(const N: TTSNode; AInfo: TClassInfo; APublished: Boolean);
    procedure AddVarNames(const N: TTSNode; AInfo: TClassInfo);
    function ClassOf(const AHdr: TTSNode; out AMethod: string): TClassInfo;
    function ChainKnown(AInfo: TClassInfo; ADepth: Integer): Boolean;
    procedure ChainCollect(AInfo: TClassInfo; ADepth: Integer;
      AMembers, AFields: TDictionary<string, Boolean>);
    procedure ScanUse(const N: TTSNode; AHdrStart: Cardinal; AMod, AUsed: TDictionary<string, Boolean>);
    procedure ScanStatic(const N: TTSNode; AMembers: TDictionary<string, Boolean>;
      var ABad: Boolean; var AIds: Integer);
    procedure ScanLocals(const N: TTSNode; AFields: TDictionary<string, Boolean>);
    function FirstArgIsSender(const AArgs: TTSNode): Boolean;
    procedure CheckConst(const ADef, AHdr: TTSNode; AInfo: TClassInfo; const AMethod: string);
    procedure ScanParams(const AHdr: TTSNode; AFields: TDictionary<string, Boolean>);
    procedure CheckShadow(const ADef: TTSNode; AInfo: TClassInfo);
    procedure CheckStatic(const ADef, AHdr: TTSNode; AInfo: TClassInfo; const AMethod: string);
    procedure Visit(const N: TTSNode; AOuter: TClassInfo);
  public
    constructor Create(const AFile: string; const ASrc: TBytes);
    destructor Destroy; override;
    function Run(const ARoot: TTSNode): TArray<TLintFinding>;
  end;

{ ---------------------------------------------------------------- TClassInfo }

constructor TClassInfo.Create;
begin
  inherited Create;
  Parents := TList<string>.Create;
  Members := TDictionary<string, Boolean>.Create;
  Fields  := TDictionary<string, Boolean>.Create;
  NoStatic:= TDictionary<string, Boolean>.Create;
  NoConst := TDictionary<string, Boolean>.Create;
end;

destructor TClassInfo.Destroy;
begin
  Parents.Free;
  Members.Free;
  Fields.Free;
  NoStatic.Free;
  NoConst.Free;
  inherited Destroy;
end;

{ ------------------------------------------------------------------ TDeclRun }

constructor TDeclRun.Create(const AFile: string; const ASrc: TBytes);
begin
  inherited Create;
  FFile      := AFile;
  FSrc       := ASrc;
  FFindings  := TList<TLintFinding>.Create;
  FClasses   := TObjectDictionary<string, TClassInfo>.Create([doOwnsValues]);
  FAddrTaken := TDictionary<string, Boolean>.Create;
  FVarRoutine:= TDictionary<string, Boolean>.Create;
end;

destructor TDeclRun.Destroy;
begin
  FFindings.Free;
  FClasses.Free;
  FAddrTaken.Free;
  FVarRoutine.Free;
  inherited Destroy;
end;

function TDeclRun.NodeStr(const N: TTSNode): string;
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

function TDeclRun.LowerText(const N: TTSNode): string;
begin
  Result:= LowerCase(StringReplace(Trim(NodeStr(N)), ' ', '', [rfReplaceAll]));
end;

procedure TDeclRun.EmitAt(const N: TTSNode; const ARule, AMsg, ASev: string);
var
  P: TTSPoint;
  F: TLintFinding;
begin
  P:= N.StartPoint;
  F:= Default(TLintFinding);
  F.RuleId   := ARule;
  F.Severity := ASev;
  F.Message  := AMsg;
  F.FilePath := FFile;
  F.StartLine:= Integer(P.Row) + 1;
  F.StartCol := Integer(P.Column) + 1;
  F.EndLine  := F.StartLine;
  F.EndCol   := F.StartCol + Length(Trim(NodeStr(N)));
  FFindings.Add(F);
end;

class function TDeclRun.StripGeneric(const S: string): string;
var
  P: Integer;
begin
  P:= Pos('<', S);
  Result:= if P > 0 then Copy(S, 1, P - 1) else S;
end;

class function TDeclRun.LastSegment(const S: string): string;
var
  P: Integer;
begin
  P:= LastDelimiter('.', S);
  Result:= if P > 0 then Copy(S, P + 1, MaxInt) else S;
end;

{ I + uppercase letter + identifier characters: the Delphi interface naming convention. }
class function TDeclRun.IsInterfaceName(const S: string): Boolean;
var
  T: string;
  I: Integer;
begin
  T:= LastSegment(StripGeneric(S));
  Result:= (Length(T) > 1) and (T[1] = 'I') and CharInSet(T[2], ['A'..'Z']);
  if not Result then Exit;
  for I:= 2 to Length(T) do
    if not CharInSet(T[I], ['A'..'Z', 'a'..'z', '0'..'9', '_']) then Exit(False);
end;

class function TDeclRun.IsManagedType(const AType: string): Boolean;
var
  T: string;
begin
  T:= LowerCase(StringReplace(Trim(AType), ' ', '', [rfReplaceAll]));
  if T = '' then Exit(False);
  if StartsStr('string[', T) then Exit(False);
  Result:= MatchStr(LastSegment(T), MANAGED_TYPES) or StartsStr('arrayof', T)
    or StartsStr('tarray<', T) or StartsStr('ansistring(', T)
    or IsInterfaceName(Trim(AType));
end;

class function TDeclRun.HasKeyword(const N: TTSNode; const AKinds: array of string): Boolean;
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

function TDeclRun.IsDotRhs(const N: TTSNode): Boolean;
var
  P, R: TTSNode;
begin
  P:= N.Parent;
  if P.IsNull or (P.NodeType <> 'exprDot') then Exit(False);
  R:= P.ChildByField('rhs');
  Result:= (not R.IsNull) and (R.StartByte = N.StartByte) and (R.EndByte = N.EndByte);
end;

function TDeclRun.IsLeafSelf(const N: TTSNode): Boolean;
begin
  Result:= (N.ChildCount = 0) and SameText(Trim(NodeStr(N)), 'self');
end;

{ Root identifier of an lvalue/operand path: S, S[i], S.F, S^, (S). Lower case, or ''. }
function TDeclRun.RootName(const N: TTSNode): string;
var
  C: TTSNode;
begin
  Result:= '';
  C:= N;
  while not C.IsNull do
  begin
    if C.NodeType = 'identifier' then Exit(LowerText(C));
    if C.NodeType = 'exprDot' then C:= C.ChildByField('lhs')
    else if C.NodeType = 'exprUnary' then C:= C.ChildByField('operand')
    else if C.NodeType = 'exprCall' then C:= C.ChildByField('entity')
    else if MatchStr(C.NodeType, ['exprSubscript', 'exprBrackets', 'exprParens']) then
    begin
      if C.NamedChildCount = 0 then Exit;
      C:= C.NamedChild(0);
    end
    else Exit;
  end;
end;

{ ------------------------------------------------------------- pass 1: facts }

procedure TDeclRun.NoteAddr(const N: TTSNode);
var
  Nm: string;
begin
  if N.IsNull then Exit;
  Nm:= LastSegment(LowerText(N));
  if Nm <> '' then FAddrTaken.AddOrSetValue(Nm, True);
end;

{ Names handed around as values: @X, bare identifier arguments, rhs of an assignment. }
procedure TDeclRun.CollectAddrTaken(const N: TTSNode);
var
  I   : Integer;
  Node: TTSNode;
begin
  if N.IsNull then Exit;
  if N.NodeType = 'exprCall' then
  begin
    Node:= N.ChildByField('args');
    if not Node.IsNull then
      for I:= 0 to Node.NamedChildCount - 1 do
        if MatchStr(Node.NamedChild(I).NodeType, ['identifier', 'exprDot']) then
          NoteAddr(Node.NamedChild(I));
  end
  else if N.NodeType = 'assignment' then
  begin
    Node:= N.ChildByField('rhs');
    if (not Node.IsNull) and MatchStr(Node.NodeType, ['identifier', 'exprDot']) then
      NoteAddr(Node);
  end
  else if (N.NodeType = 'exprUnary') and (N.NamedChildCount > 1)
          and (N.NamedChild(0).NodeType = 'kAt') then
    NoteAddr(N.NamedChild(1));
  for I:= 0 to N.NamedChildCount - 1 do CollectAddrTaken(N.NamedChild(I));
end;

{ True when any declArg of AArgs carries a var/out modifier. }
function HasVarParam(const AArgs: TTSNode): Boolean;
var
  I, J: Integer;
  Arg : TTSNode;
begin
  Result:= False;
  if AArgs.IsNull then Exit;
  for I:= 0 to AArgs.NamedChildCount - 1 do
  begin
    Arg:= AArgs.NamedChild(I);
    if Arg.NodeType <> 'declArg' then Continue;
    for J:= 0 to Arg.NamedChildCount - 1 do
      if MatchStr(Arg.NamedChild(J).NodeType, ['kVar', 'kOut']) then Exit(True);
  end;
end;

{ Bare names of routines that declare a var/out parameter: passing a value
  parameter to one of them is a modification. }
procedure TDeclRun.CollectVarRoutines(const N: TTSNode);
var
  I : Integer;
  Nm: string;
begin
  if N.IsNull then Exit;
  if (N.NodeType = 'declProc') and HasVarParam(N.ChildByField('args')) then
  begin
    Nm:= LastSegment(LowerText(N.ChildByField('name')));
    if Nm <> '' then FVarRoutine.AddOrSetValue(Nm, True);
  end;
  for I:= 0 to N.NamedChildCount - 1 do CollectVarRoutines(N.NamedChild(I));
end;

procedure TDeclRun.AddVarNames(const N: TTSNode; AInfo: TClassInfo);
var
  I: Integer;
  C: TTSNode;
begin
  for I:= 0 to N.NamedChildCount - 1 do
  begin
    C:= N.NamedChild(I);
    if C.NodeType <> 'identifier' then Break;
    AInfo.Members.AddOrSetValue(LowerText(C), True);
    AInfo.Fields.AddOrSetValue(LowerText(C), True);
  end;
end;

procedure TDeclRun.ReadMember(const N: TTSNode; AInfo: TClassInfo; APublished: Boolean);
var
  I   : Integer;
  Nm  : string;
  Contract: Boolean;
begin
  if N.NodeType = 'declSection' then
  begin
    APublished:= False;
    for I:= 0 to N.NamedChildCount - 1 do
      if N.NamedChild(I).NodeType = 'kPublished' then APublished:= True;
    for I:= 0 to N.NamedChildCount - 1 do ReadMember(N.NamedChild(I), AInfo, APublished);
  end
  else if MatchStr(N.NodeType, ['declField', 'declFieldNoSemi']) then
    AddVarNames(N, AInfo)
  else if N.NodeType = 'declVars' then
  begin
    for I:= 0 to N.NamedChildCount - 1 do
      if N.NamedChild(I).NodeType = 'declVar' then AddVarNames(N.NamedChild(I), AInfo);
  end
  else if N.NodeType = 'declProc' then
  begin
    Nm:= LastSegment(LowerText(N.ChildByField('name')));
    if Nm = '' then Exit;
    AInfo.Members.AddOrSetValue(Nm, True);
    Contract:= HasKeyword(N, ['kVirtual', 'kDynamic', 'kOverride', 'kMessage', 'kAbstract',
      'kExternal', 'kStatic', 'kReintroduce']);
    if Contract then AInfo.NoConst.AddOrSetValue(Nm, True);
    if Contract or APublished or HasKeyword(N, ['kClass', 'kConstructor', 'kDestructor', 'kOperator']) then
      AInfo.NoStatic.AddOrSetValue(Nm, True);
  end
  else if N.NodeType = 'declProp' then
    for I:= 0 to N.NamedChildCount - 1 do
      if N.NamedChild(I).NodeType = 'identifier' then
      begin
        Nm:= LowerText(N.NamedChild(I));
        AInfo.Members.AddOrSetValue(Nm, True);
        AInfo.NoStatic.AddOrSetValue(Nm, True);
      end;
end;

procedure TDeclRun.ReadClass(const ACls: TTSNode; AInfo: TClassInfo);
var
  I: Integer;
  C: TTSNode;
  T: string;
begin
  for I:= 0 to ACls.NamedChildCount - 1 do
  begin
    C:= ACls.NamedChild(I);
    if C.NodeType = 'typeref' then
    begin
      T:= Trim(NodeStr(C));
      AInfo.Parents.Add(LastSegment(StripGeneric(LowerCase(T))));
      if IsInterfaceName(T) then AInfo.HasIntf:= True;
    end
    else ReadMember(C, AInfo, False);
  end;
  if AInfo.Parents.Count > 1 then AInfo.HasIntf:= True;
end;

procedure TDeclRun.CollectClasses(const N: TTSNode);
var
  I, J: Integer;
  Cls : TTSNode;
  Info: TClassInfo;
begin
  if N.IsNull then Exit;
  if N.NodeType = 'declType' then
  begin
    Cls:= Default(TTSNode);
    for J:= 0 to N.NamedChildCount - 1 do
    begin
      if N.NamedChild(J).NodeType = 'declClass' then Cls:= N.NamedChild(J);
      if (N.NamedChild(J).NodeType = 'type') and (N.NamedChild(J).NamedChildCount > 0)
         and (N.NamedChild(J).NamedChild(0).NodeType = 'declClass') then
        Cls:= N.NamedChild(J).NamedChild(0);
    end;
    if not Cls.IsNull then
    begin
      Info:= TClassInfo.Create;
      ReadClass(Cls, Info);
      FClasses.AddOrSetValue(LastSegment(StripGeneric(LowerText(N.ChildByField('name')))), Info);
    end;
  end;
  for I:= 0 to N.NamedChildCount - 1 do CollectClasses(N.NamedChild(I));
end;

{ ---------------------------------------------------------- class resolution }

function TDeclRun.ClassOf(const AHdr: TTSNode; out AMethod: string): TClassInfo;
var
  Full, Cls: string;
  P        : Integer;
begin
  Result:= nil;
  AMethod:= '';
  Full:= LowerText(AHdr.ChildByField('name'));
  P:= LastDelimiter('.', StripGeneric(Full));
  if P = 0 then Exit;
  AMethod:= Copy(Full, P + 1, MaxInt);
  Cls:= LastSegment(StripGeneric(Copy(Full, 1, P - 1)));
  if not FClasses.TryGetValue(Cls, Result) then Result:= nil;
end;

{ True when every ancestor of AInfo is declared in this file or is a root class. }
function TDeclRun.ChainKnown(AInfo: TClassInfo; ADepth: Integer): Boolean;
var
  P   : string;
  Next: TClassInfo;
begin
  Result:= False;
  if ADepth > MAX_CHAIN then Exit;
  Result:= True;
  for P in AInfo.Parents do
  begin
    if MatchStr(P, ROOT_CLASSES) then Continue;
    if IsInterfaceName(P) then Continue;
    if not FClasses.TryGetValue(P, Next) then Exit(False);
    if not ChainKnown(Next, ADepth + 1) then Exit(False);
  end;
end;

procedure TDeclRun.ChainCollect(AInfo: TClassInfo; ADepth: Integer;
  AMembers, AFields: TDictionary<string, Boolean>);
var
  P   : string;
  K   : string;
  Next: TClassInfo;
begin
  if ADepth > MAX_CHAIN then Exit;
  for K in AInfo.Members.Keys do AMembers.AddOrSetValue(K, True);
  for K in AInfo.Fields.Keys do AFields.AddOrSetValue(K, True);
  for P in AInfo.Parents do
    if FClasses.TryGetValue(P, Next) and (Next <> AInfo) then
      ChainCollect(Next, ADepth + 1, AMembers, AFields);
end;

function TDeclRun.FirstArgIsSender(const AArgs: TTSNode): Boolean;
var
  I   : Integer;
  Arg : TTSNode;
begin
  Result:= False;
  if AArgs.IsNull then Exit;
  for I:= 0 to AArgs.NamedChildCount - 1 do
  begin
    Arg:= AArgs.NamedChild(I);
    if Arg.NodeType <> 'declArg' then Continue;
    Exit((Arg.NamedChildCount > 0) and (Arg.NamedChild(0).NodeType = 'identifier')
      and SameText(Trim(NodeStr(Arg.NamedChild(0))), 'Sender'));
  end;
end;

{ ------------------------------------------------------- missing-const-param }

{ One walk of the routine (header excluded): which names are modified, which used. }
procedure TDeclRun.ScanUse(const N: TTSNode; AHdrStart: Cardinal;
  AMod, AUsed: TDictionary<string, Boolean>);
var
  I, J  : Integer;
  Callee: string;
  Args  : TTSNode;
  Ent   : TTSNode;
  Nm    : string;
begin
  if N.IsNull then Exit;
  if (N.NodeType = 'declProc') and (N.StartByte = AHdrStart) then Exit;
  if (N.NodeType = 'identifier') and (not IsDotRhs(N)) then AUsed.AddOrSetValue(LowerText(N), True);
  if N.NodeType = 'assignment' then
  begin
    Nm:= RootName(N.ChildByField('lhs'));
    if Nm <> '' then AMod.AddOrSetValue(Nm, True);
  end
  else if (N.NodeType = 'exprUnary') and (N.NamedChildCount > 1)
          and (N.NamedChild(0).NodeType = 'kAt') then
  begin
    Nm:= RootName(N.NamedChild(1));
    if Nm <> '' then AMod.AddOrSetValue(Nm, True);
  end
  else if N.NodeType = 'with' then
  begin
    for I:= 0 to N.NamedChildCount - 1 do
    begin
      Nm:= RootName(N.NamedChild(I));
      if Nm <> '' then AMod.AddOrSetValue(Nm, True);
    end;
  end
  else if N.NodeType = 'exprCall' then
  begin
    Ent:= N.ChildByField('entity');
    Callee:= LastSegment(LowerText(Ent));
    Args:= N.ChildByField('args');
    if (not Args.IsNull) and (MatchStr(Callee, MODIFYING_CALLS) or FVarRoutine.ContainsKey(Callee)) then
      for J:= 0 to Args.NamedChildCount - 1 do
      begin
        Nm:= RootName(Args.NamedChild(J));
        if Nm <> '' then AMod.AddOrSetValue(Nm, True);
      end;
  end;
  for I:= 0 to N.NamedChildCount - 1 do ScanUse(N.NamedChild(I), AHdrStart, AMod, AUsed);
end;

procedure TDeclRun.CheckConst(const ADef, AHdr: TTSNode; AInfo: TClassInfo; const AMethod: string);
var
  Args, Arg, Ty, Nm: TTSNode;
  I, J, TyStart: Integer;
  Modified, Used: TDictionary<string, Boolean>;
  K: Integer;
  ByValue: Boolean;
  Lower: string;
begin
  Args:= AHdr.ChildByField('args');
  if Args.IsNull or FirstArgIsSender(Args) then Exit;
  if (AMethod <> '') and ((AInfo = nil) or AInfo.NoConst.ContainsKey(AMethod)) then Exit;
  if FAddrTaken.ContainsKey(LastSegment(LowerText(AHdr.ChildByField('name')))) then Exit;
  Modified:= TDictionary<string, Boolean>.Create;
  Used:= TDictionary<string, Boolean>.Create;
  try
    ScanUse(ADef, AHdr.StartByte, Modified, Used);
    for I:= 0 to Args.NamedChildCount - 1 do
    begin
      Arg:= Args.NamedChild(I);
      if Arg.NodeType <> 'declArg' then Continue;
      ByValue:= True;
      for K:= 0 to Arg.NamedChildCount - 1 do
        if MatchStr(Arg.NamedChild(K).NodeType, ['kConst', 'kConstref', 'kVar', 'kOut']) then
          ByValue:= False;
      if not ByValue then Continue;
      Ty:= Arg.ChildByField('type');
      if Ty.IsNull or (not IsManagedType(NodeStr(Ty))) then Continue;
      TyStart:= Integer(Ty.StartByte);
      for J:= 0 to Arg.NamedChildCount - 1 do
      begin
        Nm:= Arg.NamedChild(J);
        if (Nm.NodeType <> 'identifier') or (Integer(Nm.StartByte) >= TyStart) then Continue;
        Lower:= LowerText(Nm);
        if (Lower = 'self') or Modified.ContainsKey(Lower) or (not Used.ContainsKey(Lower)) then Continue;
        EmitAt(Nm, 'missing-const-param',
          Format('Parameter "%s" is never modified: declare it "const" to avoid the copy / reference count',
            [Trim(NodeStr(Nm))]), 'hint');
      end;
    end;
  finally
    Used.Free;
    Modified.Free;
  end;
end;

{ ---------------------------------------------------------- local-shadows-field }

procedure TDeclRun.ScanLocals(const N: TTSNode; AFields: TDictionary<string, Boolean>);
var
  I, TyStart: Integer;
  C, Ty     : TTSNode;
begin
  if N.IsNull then Exit;
  if N.NodeType = 'defProc' then Exit; { nested routines are visited on their own }
  if MatchStr(N.NodeType, ['declVar', 'varDef', 'varAssignDef']) then
  begin
    Ty:= N.ChildByField('type');
    TyStart:= if Ty.IsNull then MaxInt else Integer(Ty.StartByte);
    for I:= 0 to N.NamedChildCount - 1 do
    begin
      C:= N.NamedChild(I);
      if C.NodeType <> 'identifier' then Continue;
      if Integer(C.StartByte) >= TyStart then Break;
      if AFields.ContainsKey(LowerText(C)) then
        EmitAt(C, 'local-shadows-field',
          Format('Local "%s" shadows a field of the enclosing class', [Trim(NodeStr(C))]), 'info');
      if Ty.IsNull and (N.NodeType = 'declVar') then Break; { `X := Y` default: only the first identifier is a name }
    end;
  end;
  for I:= 0 to N.NamedChildCount - 1 do ScanLocals(N.NamedChild(I), AFields);
end;

{ Parameters of the method header whose name equals a field (gap-rules wave G7, FI W517). }
procedure TDeclRun.ScanParams(const AHdr: TTSNode; AFields: TDictionary<string, Boolean>);
var
  Args, Arg, Ty, C: TTSNode;
  I, J, TyStart   : Integer;
begin
  Args:= AHdr.ChildByField('args');
  if Args.IsNull then Exit;
  for I:= 0 to Args.NamedChildCount - 1 do
  begin
    Arg:= Args.NamedChild(I);
    if Arg.NodeType <> 'declArg' then Continue;
    Ty:= Arg.ChildByField('type');
    TyStart:= if Ty.IsNull then MaxInt else Integer(Ty.StartByte);
    for J:= 0 to Arg.NamedChildCount - 1 do
    begin
      C:= Arg.NamedChild(J);
      if (C.NodeType = 'identifier') and (Integer(C.StartByte) < TyStart)
         and AFields.ContainsKey(LowerText(C)) then
        EmitAt(C, 'local-shadows-field',
          Format('Parameter "%s" hides a field of the enclosing class', [Trim(NodeStr(C))]), 'info');
    end;
  end;
end;

procedure TDeclRun.CheckShadow(const ADef: TTSNode; AInfo: TClassInfo);
var
  Members, Fields: TDictionary<string, Boolean>;
  I: Integer;
  C: TTSNode;
begin
  Members:= TDictionary<string, Boolean>.Create;
  Fields:= TDictionary<string, Boolean>.Create;
  try
    ChainCollect(AInfo, 0, Members, Fields);
    if Fields.Count = 0 then Exit;
    ScanParams(ADef.ChildByField('header'), Fields);
    for I:= 0 to ADef.NamedChildCount - 1 do
    begin
      C:= ADef.NamedChild(I);
      if C.NodeType <> 'declProc' then ScanLocals(C, Fields);
    end;
  finally
    Fields.Free;
    Members.Free;
  end;
end;

{ ------------------------------------------------------ method-could-be-static }

procedure TDeclRun.ScanStatic(const N: TTSNode; AMembers: TDictionary<string, Boolean>;
  var ABad: Boolean; var AIds: Integer);
var
  I: Integer;
begin
  if ABad or N.IsNull then Exit;
  if MatchStr(N.NodeType, ['inherited', 'with', 'asm']) or IsLeafSelf(N) then
  begin
    ABad:= True;
    Exit;
  end;
  if (N.NodeType = 'identifier') and (not IsDotRhs(N)) then
  begin
    Inc(AIds);
    if AMembers.ContainsKey(LowerText(N)) then
    begin
      ABad:= True;
      Exit;
    end;
  end;
  for I:= 0 to N.NamedChildCount - 1 do ScanStatic(N.NamedChild(I), AMembers, ABad, AIds);
end;

procedure TDeclRun.CheckStatic(const ADef, AHdr: TTSNode; AInfo: TClassInfo; const AMethod: string);
var
  Members, Fields: TDictionary<string, Boolean>;
  Body           : TTSNode;
  Bad            : Boolean;
  Ids, I         : Integer;
begin
  if (AInfo = nil) or (not AInfo.Members.ContainsKey(AMethod)) or AInfo.NoStatic.ContainsKey(AMethod) then Exit;
  if FAddrTaken.ContainsKey(AMethod) or AInfo.HasIntf or (not ChainKnown(AInfo, 0)) then Exit;
  if HasKeyword(AHdr, ['kClass', 'kConstructor', 'kDestructor', 'kOperator', 'kVirtual', 'kOverride']) then Exit;
  if FirstArgIsSender(AHdr.ChildByField('args')) then Exit;
  Body:= ADef.ChildByField('body');
  if Body.IsNull then Exit;
  Members:= TDictionary<string, Boolean>.Create;
  Fields:= TDictionary<string, Boolean>.Create;
  try
    ChainCollect(AInfo, 0, Members, Fields);
    for I:= 0 to High(ROOT_MEMBERS) do Members.AddOrSetValue(ROOT_MEMBERS[I], True);
    Bad:= False;
    Ids:= 0;
    ScanStatic(Body, Members, Bad, Ids);
    if (not Bad) and (Ids > 0) then
      EmitAt(AHdr.ChildByField('name'), 'method-could-be-static',
        Format('Method "%s" uses nothing of its class: make it a class method or a standalone routine',
          [Trim(NodeStr(AHdr.ChildByField('name')))]), 'hint');
  finally
    Fields.Free;
    Members.Free;
  end;
end;

{ ------------------------------------------------------------------- driver }

procedure TDeclRun.Visit(const N: TTSNode; AOuter: TClassInfo);
var
  I      : Integer;
  Hdr    : TTSNode;
  Body   : TTSNode;
  Info   : TClassInfo;
  Method : string;
begin
  if N.IsNull then Exit;
  Info:= AOuter;
  if N.NodeType = 'defProc' then
  begin
    Hdr:= N.ChildByField('header');
    Body:= N.ChildByField('body');
    if (not Hdr.IsNull) and (not Body.IsNull) then
    begin
      Method:= '';
      Info:= ClassOf(Hdr, Method);
      if Method = '' then
      begin
        Info:= AOuter; { nested routine: the enclosing method's class still applies for shadowing }
        CheckConst(N, Hdr, nil, '');
      end
      else
      begin
        CheckConst(N, Hdr, Info, Method);
        if Info <> nil then
        begin
          CheckShadow(N, Info);
          CheckStatic(N, Hdr, Info, Method);
        end;
      end;
    end;
  end;
  for I:= 0 to N.NamedChildCount - 1 do Visit(N.NamedChild(I), Info);
end;

function TDeclRun.Run(const ARoot: TTSNode): TArray<TLintFinding>;
var
  Seen: TDictionary<string, Boolean>;
  Res : TList<TLintFinding>;
  F   : TLintFinding;
  Key : string;
begin
  CollectClasses(ARoot);
  CollectAddrTaken(ARoot);
  CollectVarRoutines(ARoot);
  Visit(ARoot, nil);
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

{ ------------------------------------------------------------- TDeclChecker }

class function TDeclChecker.Check(const AFile: string; const ACfg: TLintConfig;  // dl:ok unused-parameter@7a51 -- fixed checker signature shared by every gate unit
  const AStore: ISymbolStore; AFileId: Integer): TArray<TLintFinding>;  // dl:ok unused-parameter@9a67 -- AStore/AFileId reserved: rules are same-file AST only
var
  PF : TParsedFile;
  Run: TDeclRun;
begin
  Result:= nil;
  PF:= TAstParseCache.Get(AFile);
  if (PF.Tree = nil) or (PF.Src = nil) then Exit;
  Run:= TDeclRun.Create(AFile, PF.Src);
  try
    Result:= Run.Run(PF.Tree.RootNode);
  finally
    Run.Free;
  end;
end;

end.
