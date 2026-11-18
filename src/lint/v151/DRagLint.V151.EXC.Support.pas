unit DRagLint.V151.EXC.Support;

{ Wave v151 lane EXC -- the AST walker behind DRagLint.V151.EXC (private to the lane).
  Rules emitted: except-handler-order, exception-freed, inherited-order,
  inherited-wrong-method, message-handler-without-inherited, inherited-without-ancestor,
  override-only-inherited, destroy-called-directly, missing-inherited-call.
  Pure AST over the shared parse cache; the symbol stores are consulted only for
  ancestors that are not declared in the file, and every question the stores cannot
  answer completely is answered "unknown" (no finding): absence over wrong. }

interface

uses
  System.SysUtils
  , System.Classes
  , System.Generics.Collections
  , TreeSitter
  , DRagLint.Core.Model
  , DRagLint.Core.Interfaces
  ;

type
  /// <summary>Directive and position facts of one method declared in a class body of the file.</summary>
  TExcMethodInfo = record
    Name       : string;          // lower case, no generics
    IsOverride : Boolean;
    IsReintro  : Boolean;
    IsMessage  : Boolean;
    IsVirtual  : Boolean;         // virtual, dynamic or abstract
    IsOverload : Boolean;
    IsCtorDtor : Boolean;
    IsClassProc: Boolean;
    Ambiguous  : Boolean;         // two declarations of the name in one class
    MessageId  : string;          // lower case identifier after `message`
    Vis        : string;          // 'private' | 'protected' | 'public' | 'published'
    ArgNames   : TArray<string>;  // lower case parameter names in order
  end;

  /// <summary>Per-class facts of the file: heritage list and declared methods.</summary>
  TExcClassInfo = class
  public
    Parents: TArray<string>;      // lower case, last segment, no generics  // dl:ok public-field@2d0d -- REVIEWED 2026-11-14 v151 INT: plain data holder owned by one scan
    Methods: TDictionary<string, TExcMethodInfo>;  // dl:ok public-field@955a -- REVIEWED 2026-11-14 v151 INT: plain data holder owned by one scan
    constructor Create;
    destructor Destroy; override;
  end;

  /// <summary>One run of the lane over one parsed file.</summary>
  /// <remarks>Create, Run once, Free. Not thread-safe; the owner is the checker in DRagLint.V151.EXC.</remarks>
  TExcRun = class  // dl:ok high-response@f6cf -- REVIEWED 2026-11-14 v151 INT: one scanner class holding the per-rule checks of one lane; a split is beyond 1.51
  strict private
    FFile    : string;
    FSrc     : TBytes;
    FStore   : ISymbolStore;
    FLib     : ISymbolStore;
    FFileId  : Int64;
    FFindings: TList<TLintFinding>;
    FClasses : TObjectDictionary<string, TExcClassInfo>;
    FWants   : TFunc<string, Boolean>;
    function NodeStr(const N: TTSNode): string;
    function LowerText(const N: TTSNode): string;
    procedure EmitAt(const N: TTSNode; const ARule, AMsg, ASev: string);
    class function StripGeneric(const S: string): string; static;
    class function LastSegment(const S: string): string; static;
    class function HasKeyword(const N: TTSNode; const AKinds: array of string): Boolean; static;
    procedure GatherMembers(const N: TTSNode; AList: TList<TPair<TTSNode, string>>; const AVis: string);
    procedure CollectClasses(const N: TTSNode);
    procedure CollectClass(const ACls: TTSNode; const AName: string);
    function MethodArgs(const AHdr: TTSNode): TArray<string>;
    function ProcOwner(const ADef: TTSNode; out AClass, AMethod: string): Boolean;
    function ProcInfo(const ADef: TTSNode; out AInfo: TExcMethodInfo; out AClass: string): Boolean;
    function IsDtorProc(const ADef: TTSNode): Boolean;
    function ContainsNode(const N: TTSNode; const AType: string): Boolean;
    function ContainsIdent(const N: TTSNode; const ANames: array of string): Boolean;
    function ContainsFreeOfMember(const N: TTSNode): Boolean;
    function ContainsResultAssign(const N: TTSNode): Boolean;
    function IsBareInherited(const AStmt: TTSNode): Boolean;
    function InheritedTarget(const AStmt: TTSNode; out AArgs: TTSNode): string;
    function BodyStatements(const ABody: TTSNode): TList<TTSNode>;
    function ExcIsA(const AClass, AAncestor: string; const AClassOrig, AAncOrig: string): Boolean;
    function StoreDescends(const AClassOrig, AAncOrig: string): Boolean;
    function AncestorMember(const AClass, AMethod: string; out AVis: string): Integer;
    function StoreMember(const AClassOrig, AMethod: string; out AVis: string): Integer;
    procedure CheckTry(const N: TTSNode);
    procedure ScanHandlerFree(const N: TTSNode; const AVar: string);
    procedure CheckDestroyDirect(const N: TTSNode);
    procedure CheckProc(const ADef: TTSNode);
    procedure CheckDtorOrder(const ADef: TTSNode);
    procedure CheckWrongMethod(const ADef: TTSNode; const AInfo: TExcMethodInfo);
    procedure ScanWrongMethod(const N: TTSNode; const AInfo: TExcMethodInfo);
    procedure CheckMessageHandler(const ADef: TTSNode; const AInfo: TExcMethodInfo);
    procedure CheckNoAncestor(const ADef: TTSNode; const AInfo: TExcMethodInfo; const AClass: string);
    procedure CheckOnlyInherited(const ADef: TTSNode; const AInfo: TExcMethodInfo; const AClass: string);
    procedure CheckMissingInherited(const ADef: TTSNode; const AInfo: TExcMethodInfo; const AClass: string);
    procedure Visit(const N: TTSNode);
  public
    constructor Create(const AFile: string; const ASrc: TBytes; const AStore, ALib: ISymbolStore;
      AFileId: Int64; const AWants: TFunc<string, Boolean>);
    destructor Destroy; override;
    function Run(const ARoot: TTSNode): TArray<TLintFinding>;
  end;

implementation

uses
  DRagLint.Diagnostics.ParseCache { 1.52 BK-COLS2: TAstParseCache.CharCol }
  , System.StrUtils
  ;

const
  MAX_CHAIN = 24;
  { Methods of TObject: an ancestor chain that ends at the implicit TObject declares these. }
  OBJECT_METHODS: array[0..21] of string = (
    'create', 'destroy', 'free', 'classtype', 'classname', 'classnameis', 'classparent',
    'instancesize', 'inheritsfrom', 'methodaddress', 'methodname', 'fieldaddress',
    'getinterface', 'unitname', 'afterconstruction', 'beforedestruction', 'dispatch',
    'defaulthandler', 'newinstance', 'freeinstance', 'safecallexception', 'tostring');
  { Child -> parent edges of the exception classes of the RTL, enough to order handlers. }
  RTL_EXC: array[0..47] of string = (
    'eabort=exception', 'eaccessviolation=eexternal', 'eexternal=exception',
    'eintererror=eexternal', 'eintoverflow=eintererror', 'edivbyzero=eintererror',
    'erangeerror=eintererror', 'emutherror=eexternal', 'emath=eexternal',
    'emathererror=eexternal', 'ezerodivide=emathererror', 'eoverflow=emathererror',
    'eunderflow=emathererror', 'einvalidop=emathererror', 'econverterror=exception',
    'eoutofmemory=exception', 'einoutError=exception', 'einouterror=exception',
    'eosError=exception', 'eoserror=exception', 'estreamerror=exception',
    'efopenerror=estreamerror', 'efcreateerror=estreamerror', 'efilestreamerror=estreamerror',
    'elisterror=exception', 'estringlisterror=exception', 'einvalidpointer=exception',
    'einvalidcast=exception', 'epropertyerror=exception', 'ecomponenterror=exception',
    'eassertionfailed=exception', 'eintfcasterror=exception', 'eabstracterror=exception',
    'evarianterror=exception', 'evarianttypecasterror=evarianterror',
    'eargumentexception=exception', 'eargumentoutofrangeexception=eargumentexception',
    'eargumentnilexception=eargumentexception', 'enotimplemented=exception',
    'enotsupportedexception=exception', 'eformaterror=exception',
    'eparseerror=exception', 'ethreaderror=exception', 'eprivilege=eexternal',
    'estackoverflow=eexternal', 'econtrolc=eexternal', 'einvalidoperation=exception',
    'ejsonexception=exception');

{ TExcClassInfo }

constructor TExcClassInfo.Create;
begin
  inherited Create;
  Methods:= TDictionary<string, TExcMethodInfo>.Create;
end;

destructor TExcClassInfo.Destroy;
begin
  Methods.Free;
  inherited Destroy;
end;

{ TExcRun: plumbing }

constructor TExcRun.Create(const AFile: string; const ASrc: TBytes; const AStore, ALib: ISymbolStore;
  AFileId: Int64; const AWants: TFunc<string, Boolean>);
begin
  inherited Create;
  FFile    := AFile;
  FSrc     := ASrc;
  FStore   := AStore;
  FLib     := ALib;
  FFileId  := AFileId;
  FWants   := AWants;
  FFindings:= TList<TLintFinding>.Create;
  FClasses := TObjectDictionary<string, TExcClassInfo>.Create([doOwnsValues]);
end;

destructor TExcRun.Destroy;
begin
  FClasses.Free;
  FFindings.Free;
  inherited Destroy;
end;

function TExcRun.NodeStr(const N: TTSNode): string;  // dl:ok duplicate-code@b658 -- REVIEWED 2026-11-14 v151 INT: same shape over different fields; a helper would need more parameters than it saves
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

function TExcRun.LowerText(const N: TTSNode): string;
begin
  Result:= LowerCase(StringReplace(Trim(NodeStr(N)), ' ', '', [rfReplaceAll]));
end;

procedure TExcRun.EmitAt(const N: TTSNode; const ARule, AMsg, ASev: string);
var
  P, Q: TTSPoint;
  F   : TLintFinding;
begin
  if not FWants(ARule) then Exit;
  P:= N.StartPoint;
  Q:= N.EndPoint;
  F:= Default(TLintFinding);
  F.RuleId   := ARule;
  F.Severity := ASev;
  F.Message  := AMsg;
  F.FilePath := FFile;
  F.StartLine:= Integer(P.Row) + 1;
  F.StartCol := TAstParseCache.CharCol(F.FilePath, P); { 1.52 BK-COLS2: character column }
  F.EndLine  := Integer(Q.Row) + 1;
  F.EndCol   := TAstParseCache.CharCol(F.FilePath, Q); { 1.52 BK-COLS2: character column }
  FFindings.Add(F);
end;

class function TExcRun.StripGeneric(const S: string): string;
var
  I, Depth: Integer;
begin
  Result:= '';
  Depth:= 0;
  for I:= 1 to Length(S) do
    if S[I] = '<' then Inc(Depth)
    else if S[I] = '>' then begin if Depth > 0 then Dec(Depth); end
    else if Depth = 0 then Result:= Result + S[I];  // dl:ok concat-in-loop@76bc -- REVIEWED 2026-11-14 v151 INT: a few short pieces per call, not an accumulating large string
end;

class function TExcRun.LastSegment(const S: string): string;
var
  P: Integer;
begin
  P:= LastDelimiter('.', S);
  Result:= if P > 0 then Copy(S, P + 1, MaxInt) else S;
end;

class function TExcRun.HasKeyword(const N: TTSNode; const AKinds: array of string): Boolean;  // dl:ok duplicate-code@0777 -- REVIEWED 2026-11-14 v151 INT: same shape over different fields; a helper would need more parameters than it saves
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

function TExcRun.ContainsNode(const N: TTSNode; const AType: string): Boolean;
var
  I: Integer;
begin
  Result:= False;
  if N.IsNull then Exit;
  if N.NodeType = AType then Exit(True);
  if N.NodeType = 'defProc' then Exit(False);
  for I:= 0 to N.NamedChildCount - 1 do
    if ContainsNode(N.NamedChild(I), AType) then Exit(True);
end;

{ True when an identifier (case-insensitive, not a member after a dot) named one of ANames occurs. }
function TExcRun.ContainsIdent(const N: TTSNode; const ANames: array of string): Boolean;
var
  I: Integer;
begin
  Result:= False;
  if N.IsNull then Exit;
  if (N.NodeType = 'identifier') and MatchText(Trim(NodeStr(N)), ANames) then Exit(True);
  if N.NodeType = 'asm' then Exit(True);
  for I:= 0 to N.NamedChildCount - 1 do
    if ContainsIdent(N.NamedChild(I), ANames) then Exit(True);
end;

{ ------------------------------------------------------------ class facts }

procedure TExcRun.GatherMembers(const N: TTSNode; AList: TList<TPair<TTSNode, string>>; const AVis: string);
var
  I, J: Integer;
  C   : TTSNode;
  Vis : string;
begin
  for I:= 0 to N.NamedChildCount - 1 do
  begin
    C:= N.NamedChild(I);
    if C.NodeType = 'declProc' then AList.Add(TPair<TTSNode, string>.Create(C, AVis))
    else if C.NodeType = 'declSection' then
    begin
      Vis:= AVis;
      for J:= 0 to C.NamedChildCount - 1 do
        if C.NamedChild(J).NodeType = 'kPrivate' then Vis:= 'private'
        else if C.NamedChild(J).NodeType = 'kProtected' then Vis:= 'protected'
        else if C.NamedChild(J).NodeType = 'kPublic' then Vis:= 'public'
        else if C.NamedChild(J).NodeType = 'kPublished' then Vis:= 'published';
      GatherMembers(C, AList, Vis);
    end;
  end;
end;

function TExcRun.MethodArgs(const AHdr: TTSNode): TArray<string>;
var
  Args, Arg, C: TTSNode;
  I, K, TyStart: Integer;
  Ty: TTSNode;
begin
  Result:= nil;
  Args:= AHdr.ChildByField('args');  // dl:ok duplicate-code@f47c -- REVIEWED 2026-11-14 v151 INT: same shape over different fields; a helper would need more parameters than it saves
  if Args.IsNull then Exit;
  for I:= 0 to Args.NamedChildCount - 1 do
  begin
    Arg:= Args.NamedChild(I);
    if Arg.NodeType <> 'declArg' then Continue;
    Ty:= Arg.ChildByField('type');
    TyStart:= if Ty.IsNull then MaxInt else Integer(Ty.StartByte);
    for K:= 0 to Arg.NamedChildCount - 1 do
    begin
      C:= Arg.NamedChild(K);
      if (C.NodeType = 'identifier') and (Integer(C.StartByte) < TyStart) then
        Result:= Result + [LowerText(C)];
    end;
  end;
end;

procedure TExcRun.CollectClass(const ACls: TTSNode; const AName: string);
var
  Info   : TExcClassInfo;
  Members: TList<TPair<TTSNode, string>>;
  I      : Integer;
  C, M, Nm, Attr: TTSNode;
  P      : TPair<TTSNode, string>;
  MI     : TExcMethodInfo;
  Old    : TExcMethodInfo;
begin
  Info:= TExcClassInfo.Create;
  FClasses.AddOrSetValue(AName, Info);
  for I:= 0 to ACls.NamedChildCount - 1 do
  begin
    C:= ACls.NamedChild(I);
    if C.NodeType = 'typeref' then Info.Parents:= Info.Parents + [LastSegment(StripGeneric(LowerText(C)))];
  end;
  Members:= TList<TPair<TTSNode, string>>.Create;
  try
    GatherMembers(ACls, Members, 'public');
    for P in Members do
    begin
      M:= P.Key;
      Nm:= M.ChildByField('name');
      if Nm.IsNull then Continue;
      MI:= Default(TExcMethodInfo);
      MI.Name       := LastSegment(StripGeneric(LowerText(Nm)));
      MI.IsOverride := HasKeyword(M, ['kOverride']);
      MI.IsReintro  := HasKeyword(M, ['kReintroduce']);
      MI.IsMessage  := HasKeyword(M, ['kMessage']);
      MI.IsVirtual  := HasKeyword(M, ['kVirtual', 'kDynamic', 'kAbstract']);
      MI.IsOverload := HasKeyword(M, ['kOverload']);
      MI.IsCtorDtor := HasKeyword(M, ['kConstructor', 'kDestructor']);
      MI.IsClassProc:= HasKeyword(M, ['kClass']);
      MI.Vis        := P.Value;
      MI.ArgNames   := MethodArgs(M);
      if MI.IsMessage then
        for I:= 0 to M.NamedChildCount - 1 do
        begin
          Attr:= M.NamedChild(I);
          if (Attr.NodeType = 'procAttribute') and HasKeyword(Attr, ['kMessage']) then  // dl:ok collapsible-if@98a1 -- REVIEWED 2026-11-14 v151 INT: outer test guards a distinct shape; kept separate for the comment and later branches
            if Attr.NamedChildCount > 1 then MI.MessageId:= LowerText(Attr.NamedChild(Attr.NamedChildCount - 1));
        end;
      if Info.Methods.TryGetValue(MI.Name, Old) then
      begin
        Old.Ambiguous:= True;
        Info.Methods.AddOrSetValue(MI.Name, Old);
      end
      else
        Info.Methods.Add(MI.Name, MI);
    end;
  finally
    Members.Free;
  end;
end;

procedure TExcRun.CollectClasses(const N: TTSNode);
var
  I, J: Integer;
  C, Cls: TTSNode;
  Name: string;
begin
  if N.IsNull then Exit;
  if N.NodeType = 'declType' then
  begin
    Cls:= Default(TTSNode);
    for J:= 0 to N.NamedChildCount - 1 do
    begin
      C:= N.NamedChild(J);
      if C.NodeType = 'declClass' then Cls:= C;
      if (C.NodeType = 'type') and (C.NamedChildCount > 0) and (C.NamedChild(0).NodeType = 'declClass') then
        Cls:= C.NamedChild(0);
    end;
    if not Cls.IsNull then
    begin
      Name:= LastSegment(StripGeneric(LowerText(N.ChildByField('name'))));
      if (Name <> '') and (not FClasses.ContainsKey(Name)) then CollectClass(Cls, Name);
    end;
  end;
  for I:= 0 to N.NamedChildCount - 1 do CollectClasses(N.NamedChild(I));
end;

{ Class and method of an implementation header `TFoo.Bar`; False for a plain routine. }
function TExcRun.ProcOwner(const ADef: TTSNode; out AClass, AMethod: string): Boolean;
var
  Hdr  : TTSNode;
  Full : string;
  P    : Integer;
begin
  AClass:= '';
  AMethod:= '';
  Hdr:= ADef.ChildByField('header');
  if Hdr.IsNull then Exit(False);
  Full:= StripGeneric(LowerText(Hdr.ChildByField('name')));
  P:= LastDelimiter('.', Full);
  if P = 0 then Exit(False);
  AMethod:= Copy(Full, P + 1, MaxInt);
  AClass:= LastSegment(Copy(Full, 1, P - 1));
  Result:= (AClass <> '') and (AMethod <> '');
end;

function TExcRun.ProcInfo(const ADef: TTSNode; out AInfo: TExcMethodInfo; out AClass: string): Boolean;
var
  Meth: string;
  Cls : TExcClassInfo;
begin
  AInfo:= Default(TExcMethodInfo);
  Result:= False;
  if not ProcOwner(ADef, AClass, Meth) then Exit;
  if not FClasses.TryGetValue(AClass, Cls) then Exit;
  if not Cls.Methods.TryGetValue(Meth, AInfo) then Exit;
  Result:= not AInfo.Ambiguous;
end;

function TExcRun.IsDtorProc(const ADef: TTSNode): Boolean;
var
  Hdr: TTSNode;
begin
  Hdr:= ADef.ChildByField('header');
  Result:= (not Hdr.IsNull) and HasKeyword(Hdr, ['kDestructor']);
end;

{ A member (F... field or Self.X) freed in the subtree: .Free / .Destroy / .DisposeOf / FreeAndNil. }
function TExcRun.ContainsFreeOfMember(const N: TTSNode): Boolean;
var
  I        : Integer;
  Lhs, Rhs, Ent, Args: TTSNode;

  function IsMemberText(const S: string): Boolean;
  begin
    Result:= StartsText('self.', S) or ((Length(S) > 2) and (S[1] = 'f') and (S[2] >= 'a') and (S[2] <= 'z'))  // dl:ok boolean-expression-complexity@657c -- REVIEWED 2026-11-14 v151 INT: one flat predicate over fixed values; splitting it does not make it clearer
      or ((Length(S) > 2) and (S[1] = 'F') and (S[2] >= 'A') and (S[2] <= 'Z'));
  end;

begin
  Result:= False;
  if N.IsNull or (N.NodeType = 'defProc') or (N.NodeType = 'lambda') then Exit;
  if N.NodeType = 'exprDot' then
  begin
    Lhs:= N.ChildByField('lhs');
    Rhs:= N.ChildByField('rhs');
    if (not Lhs.IsNull) and (not Rhs.IsNull) and MatchText(Trim(NodeStr(Rhs)), ['Free', 'Destroy', 'DisposeOf'])
       and IsMemberText(Trim(NodeStr(Lhs))) then Exit(True);
  end
  else if N.NodeType = 'exprCall' then
  begin
    Ent:= N.ChildByField('entity');
    Args:= N.ChildByField('args');
    if (not Ent.IsNull) and (not Args.IsNull) and (Args.NamedChildCount = 1)
       and SameText(Trim(NodeStr(Ent)), 'FreeAndNil') and IsMemberText(Trim(NodeStr(Args.NamedChild(0)))) then Exit(True);
  end;
  for I:= 0 to N.NamedChildCount - 1 do
    if ContainsFreeOfMember(N.NamedChild(I)) then Exit(True);
end;

{ An assignment to `<x>.Result` in the subtree: a message handler that answers the message itself. }
function TExcRun.ContainsResultAssign(const N: TTSNode): Boolean;
var
  I  : Integer;
  Lhs: TTSNode;
begin
  Result:= False;
  if N.IsNull then Exit;
  if N.NodeType = 'assignment' then
  begin
    Lhs:= N.ChildByField('lhs');
    if (not Lhs.IsNull) and EndsText('.result', LowerText(Lhs)) then Exit(True);
  end;
  for I:= 0 to N.NamedChildCount - 1 do
    if ContainsResultAssign(N.NamedChild(I)) then Exit(True);
end;

{ ------------------------------------------------------- statement helpers }

function TExcRun.BodyStatements(const ABody: TTSNode): TList<TTSNode>;
var
  I: Integer;
  C: TTSNode;
begin
  Result:= TList<TTSNode>.Create;
  for I:= 0 to ABody.NamedChildCount - 1 do
  begin
    C:= ABody.NamedChild(I);
    if (C.NodeType = 'kBegin') or (C.NodeType = 'kEnd') then Continue;
    Result.Add(C);
  end;
end;

function TExcRun.IsBareInherited(const AStmt: TTSNode): Boolean;
begin
  Result:= (AStmt.NodeType = 'statement') and (AStmt.NamedChildCount = 1)
    and (AStmt.NamedChild(0).NodeType = 'inherited') and (AStmt.NamedChild(0).NamedChildCount = 1);
end;

{ Lower-case method name an `inherited` statement names ('' for the bare form); AArgs = call args or null. }
function TExcRun.InheritedTarget(const AStmt: TTSNode; out AArgs: TTSNode): string;
var
  Inh, Ent: TTSNode;
begin
  Result:= '';
  AArgs:= Default(TTSNode);
  Inh:= Default(TTSNode);
  if (AStmt.NodeType = 'statement') and (AStmt.NamedChildCount = 1) then
  begin
    Ent:= AStmt.NamedChild(0);
    if Ent.NodeType = 'inherited' then Inh:= Ent
    else if Ent.NodeType = 'exprCall' then
    begin
      Inh:= Ent.ChildByField('entity');
      AArgs:= Ent.ChildByField('args');
      if Inh.IsNull or (Inh.NodeType <> 'inherited') then Exit('?');
    end;
  end;
  if Inh.IsNull then Exit('?');
  if Inh.NamedChildCount > 1 then Result:= LowerText(Inh.NamedChild(1));
end;

{ ------------------------------------------------------ ancestry questions }

function TExcRun.StoreDescends(const AClassOrig, AAncOrig: string): Boolean;
var
  Anc: string;
begin
  Result:= False;
  if FStore <> nil then
  begin
    if FStore.IsDescendantOf(AClassOrig, AAncOrig, FFileId) then Exit(True);
    if FLib <> nil then
      for Anc in FStore.UnresolvedAncestorNames(AClassOrig, FFileId) do
        if SameText(Anc, AAncOrig) or FLib.IsDescendantOf(Anc, AAncOrig, 0) then Exit(True);
  end;
  if (FLib <> nil) and FLib.IsDescendantOf(AClassOrig, AAncOrig, 0) then Exit(True);
end;

{ True when exception class AClass is, or descends from, AAncestor (lower-case names plus
  the original-case spellings the store needs). False also means "not proven". }
function TExcRun.ExcIsA(const AClass, AAncestor: string; const AClassOrig, AAncOrig: string): Boolean;
var
  Cur, Par, E: string;
  Depth, Eq: Integer;
  Cls: TExcClassInfo;
  Found: Boolean;
begin
  Cur:= AClass;
  Depth:= 0;
  while (Cur <> '') and (Depth < MAX_CHAIN) do
  begin
    if Cur = AAncestor then Exit(True);
    Par:= '';
    if FClasses.TryGetValue(Cur, Cls) then
    begin
      if Length(Cls.Parents) > 0 then Par:= Cls.Parents[0];
    end
    else
    begin
      Found:= False;
      for E in RTL_EXC do
      begin
        Eq:= Pos('=', E);
        if SameText(Copy(E, 1, Eq - 1), Cur) then
        begin
          Par:= LowerCase(Copy(E, Eq + 1, MaxInt));
          Found:= True;
          Break;
        end;
      end;
      if not Found then Exit(StoreDescends(AClassOrig, AAncOrig));
    end;
    Cur:= Par;
    Inc(Depth);
  end;
  Result:= False;
end;

{ 1 = a (transitive) store ancestor declares AMethod (AVis = its visibility text), 0 = the
  chain is complete and none does, -1 = unknown (an ancestor is missing from both stores). }
function TExcRun.StoreMember(const AClassOrig, AMethod: string; out AVis: string): Integer;  // dl:ok too-many-exit-points@c346 -- REVIEWED 2026-11-14 v151 INT: guard clauses per syntax shape; each early exit is a classification
var
  Sy    : TSymbol;
  Cls   : TSymbol;
  Anc   : TTypeAncestor;
  St    : ISymbolStore;
  Todo  : TList<TPair<ISymbolStore, Int64>>;
  I     : Integer;
  Lib   : TArray<TSymbol>;
  Fresh : TSymbol;
  Seen  : Boolean;

  function Scan(const AS_: ISymbolStore; AId: Int64): Boolean;
  begin
    Result:= False;
    for var Mem in AS_.FindAllChildSymbols(AId) do
      if SameText(Mem.Name, AMethod) and (Mem.Kind in [skMethod, skProcedure, skFunction, skConstructor, skDestructor]) then
      begin
        AVis:= LowerCase(Mem.Modifiers);
        Exit(True);
      end;
  end;

begin
  AVis:= '';
  Result:= -1;
  if FStore = nil then Exit;
  Seen:= False;
  for Sy in FStore.FindSymbolsByExactName(AClassOrig) do
    if Sy.Kind = skClass then begin
      Cls:= Sy;
      Seen:= True;
      Break;
    end;
  if not Seen then Exit;
  Todo:= TList<TPair<ISymbolStore, Int64>>.Create;
  try
    Result:= 0;
    for Anc in FStore.GetTransitiveAncestors(Cls.Id) do  // dl:ok used-before-assignment@4d95 -- REVIEWED 2026-11-14 v151 INT: assigned on the path where the Seen flag is set; the Exit on not Seen guards the use
    begin
      if Anc.Resolved and (Anc.SymbolId > 0) then
      begin
        if SameText(Anc.Kind, 'class') then Todo.Add(TPair<ISymbolStore, Int64>.Create(FStore, Anc.SymbolId));
      end
      else if SameText(Anc.Name, 'TObject') then
      begin
        if MatchText(AMethod, OBJECT_METHODS) then begin
          AVis:= 'public';
          Exit(1);
        end;
      end
      else
      begin
        { name-only leaf: climb it in the library index }
        if FLib = nil then Exit(-1);
        Seen:= False;
        Lib:= FLib.FindSymbolsByExactName(Anc.Name);
        for Fresh in Lib do
          if Fresh.Kind = skClass then begin
            Todo.Add(TPair<ISymbolStore, Int64>.Create(FLib, Fresh.Id));
            Seen:= True;
            Break;
          end;
        if not Seen then Exit(-1);
        for var LA in FLib.GetTransitiveAncestors(Fresh.Id) do  // dl:ok used-before-assignment@ca2d -- REVIEWED 2026-11-14 v151 INT: assigned on the path where the Seen flag is set; the Exit on not Seen guards the use
          if LA.Resolved and (LA.SymbolId > 0) then
          begin
            if SameText(LA.Kind, 'class') then Todo.Add(TPair<ISymbolStore, Int64>.Create(FLib, LA.SymbolId));
          end
          else if SameText(LA.Name, 'TObject') then
          begin
            if MatchText(AMethod, OBJECT_METHODS) then begin
              AVis:= 'public';
              Exit(1);
            end;
          end
          else Exit(-1);
      end;
    end;
    for I:= 0 to Todo.Count - 1 do
    begin
      St:= Todo[I].Key;
      if Scan(St, Todo[I].Value) then Exit(1);
    end;
  finally
    Todo.Free;
  end;
end;

{ Does a (transitive) ancestor of lower-case class AClass declare AMethod?
  1 yes (AVis set when known), 0 no (chain complete), -1 unknown. Same-file classes first;
  the first ancestor outside the file hands the rest of the chain to the stores. }
function TExcRun.AncestorMember(const AClass, AMethod: string; out AVis: string): Integer;  // dl:ok too-many-exit-points@1dde -- REVIEWED 2026-11-14 v151 INT: guard clauses per syntax shape; each early exit is a classification
var
  Cls  : TExcClassInfo;
  MI   : TExcMethodInfo;
  Par  : string;
  Depth: Integer;
begin
  AVis:= '';
  if not FClasses.TryGetValue(AClass, Cls) then Exit(-1);
  Depth:= 0;
  while Depth < MAX_CHAIN do
  begin
    if Length(Cls.Parents) = 0 then
    begin
      if MatchText(AMethod, OBJECT_METHODS) then begin
        AVis:= 'public';
        Exit(1);
      end;
      Exit(0);
    end;
    Par:= Cls.Parents[0];
    if Par = 'tobject' then
    begin
      if MatchText(AMethod, OBJECT_METHODS) then begin
        AVis:= 'public';
        Exit(1);
      end;
      Exit(0);
    end;
    if not FClasses.TryGetValue(Par, Cls) then
    begin
      Result:= StoreMember(UpperCase(Copy(Par, 1, 1)) + Copy(Par, 2, MaxInt), AMethod, AVis);
      if Result < 0 then Result:= StoreMember(Par, AMethod, AVis);
      Exit;
    end;
    if Cls.Methods.TryGetValue(AMethod, MI) then begin
      AVis:= MI.Vis;
      Exit(1);
    end;
    Inc(Depth);
  end;
  Result:= -1;
end;

{ ------------------------------------------------------------------ rules }

{ except-handler-order: a later `on E: C` whose class an earlier handler already catches. }
procedure TExcRun.CheckTry(const N: TTSNode);
var
  I, J    : Integer;
  C       : TTSNode;
  Handlers: TList<TTSNode>;
  H, E    : TTSNode;
  HOrig, EOrig, HL, EL: string;
begin
  Handlers:= TList<TTSNode>.Create;
  try
    for I:= 0 to N.NamedChildCount - 1 do
    begin
      C:= N.NamedChild(I);
      if C.NodeType = 'exceptionHandler' then Handlers.Add(C);
    end;
    for I:= 1 to Handlers.Count - 1 do
    begin
      H:= Handlers[I];
      HOrig:= StripGeneric(Trim(NodeStr(H.ChildByField('exception'))));
      HOrig:= Copy(HOrig, LastDelimiter('.', HOrig) + 1, MaxInt);
      HL:= LowerCase(HOrig);
      if HL = '' then Continue;
      for J:= 0 to I - 1 do
      begin
        E:= Handlers[J];
        EOrig:= StripGeneric(Trim(NodeStr(E.ChildByField('exception'))));
        EOrig:= Copy(EOrig, LastDelimiter('.', EOrig) + 1, MaxInt);
        EL:= LowerCase(EOrig);
        if (EL = '') or (EL = HL) then Continue; { equal classes: duplicate-exception-handler }
        if ExcIsA(HL, EL, HOrig, EOrig) then
        begin
          EmitAt(H, 'except-handler-order',
            Format('Handler for %s can never run: the earlier handler for %s already catches it; put the specific handler first',
              [HOrig, EOrig]), 'warning');
          Break;
        end;
      end;
    end;
  finally
    Handlers.Free;
  end;
end;

{ exception-freed: the handler variable freed by hand (E.Free, E.Destroy, E.DisposeOf, FreeAndNil(E)). }
procedure TExcRun.ScanHandlerFree(const N: TTSNode; const AVar: string);
var
  I       : Integer;
  Lhs, Rhs, Ent, Args, A0: TTSNode;
  Callee  : string;
begin
  if N.IsNull or (N.NodeType = 'defProc') or (N.NodeType = 'lambda') then Exit;
  if N.NodeType = 'exprDot' then
  begin
    Lhs:= N.ChildByField('lhs');
    Rhs:= N.ChildByField('rhs');
    if (not Lhs.IsNull) and (not Rhs.IsNull) and (LowerText(Lhs) = AVar)
       and MatchText(Trim(NodeStr(Rhs)), ['Free', 'Destroy', 'DisposeOf']) then
    begin
      EmitAt(N, 'exception-freed',
        Format('Exception object "%s" is freed by hand: the RTL frees it after the handler, so this is a double free', [Trim(NodeStr(Lhs))]),
        'warning');
      Exit;
    end;
  end
  else if N.NodeType = 'exprCall' then
  begin
    Ent:= N.ChildByField('entity');
    Args:= N.ChildByField('args');
    if (not Ent.IsNull) and (not Args.IsNull) and (Args.NamedChildCount = 1) then
    begin
      Callee:= Trim(NodeStr(Ent));
      A0:= Args.NamedChild(0);
      if MatchText(Callee, ['FreeAndNil', 'System.SysUtils.FreeAndNil']) and (LowerText(A0) = AVar) then
      begin
        EmitAt(N, 'exception-freed',
          Format('Exception object "%s" is released with FreeAndNil: the RTL frees it after the handler, so this is a double free', [Trim(NodeStr(A0))]),
          'warning');
        Exit;
      end;
    end;
  end;
  for I:= 0 to N.NamedChildCount - 1 do ScanHandlerFree(N.NamedChild(I), AVar);
end;

{ destroy-called-directly: `X.Destroy;` as a statement on anything but Self / inherited. }
procedure TExcRun.CheckDestroyDirect(const N: TTSNode);  // dl:ok too-many-exit-points@eac9 -- REVIEWED 2026-11-14 v151 INT: guard clauses per syntax shape; each early exit is a classification
var
  Ent, Lhs, Rhs: TTSNode;
begin
  if N.NamedChildCount <> 1 then Exit;
  Ent:= N.NamedChild(0);
  if Ent.NodeType = 'exprCall' then
  begin
    if (Ent.ChildByField('args').IsNull) or (Ent.ChildByField('args').NamedChildCount > 0) then Exit;
    Ent:= Ent.ChildByField('entity');
  end;
  if Ent.IsNull or (Ent.NodeType <> 'exprDot') then Exit;
  Lhs:= Ent.ChildByField('lhs');
  Rhs:= Ent.ChildByField('rhs');
  if Lhs.IsNull or Rhs.IsNull then Exit;
  if not SameText(Trim(NodeStr(Rhs)), 'Destroy') then Exit;
  if MatchText(Trim(NodeStr(Lhs)), ['Self', 'inherited']) or (Lhs.NodeType = 'inherited') then Exit;
  EmitAt(Ent, 'destroy-called-directly',
    Format('"%s.Destroy" is called directly: it crashes when the reference is nil; use Free (or FreeAndNil)',
      [Trim(NodeStr(Lhs))]), 'warning');
end;

{ inherited-order: a destructor whose bare inherited precedes a statement that frees a member. }
procedure TExcRun.CheckDtorOrder(const ADef: TTSNode);
var
  Body  : TTSNode;
  Stmts : TList<TTSNode>;
  I, J  : Integer;
  Free  : Boolean;
begin
  Body:= ADef.ChildByField('body');
  if Body.IsNull or (Body.NodeType <> 'block') then Exit;
  Stmts:= BodyStatements(Body);
  try
    for I:= 0 to Stmts.Count - 2 do
    begin
      if not IsBareInherited(Stmts[I]) then
      begin
        { `inherited Destroy;` names the method: also an inherited call }
        var Ign: TTSNode;
        if InheritedTarget(Stmts[I], Ign) <> 'destroy' then Continue;
      end;
      Free:= False;
      for J:= I + 1 to Stmts.Count - 1 do
        if ContainsFreeOfMember(Stmts[J]) then begin
          Free:= True;
          Break;
        end;
      if Free then
        EmitAt(Stmts[I], 'inherited-order',
          'In a destructor inherited runs before the members are freed: call inherited last, after the cleanup',
          'warning');
      Break;
    end;
  finally
    Stmts.Free;
  end;
end;

{ inherited-wrong-method: an override whose `inherited` names another method. }
procedure TExcRun.ScanWrongMethod(const N: TTSNode; const AInfo: TExcMethodInfo);
var
  I   : Integer;
  Name: string;
begin
  if N.IsNull or (N.NodeType = 'defProc') or (N.NodeType = 'lambda') then Exit;
  if (N.NodeType = 'inherited') and (N.NamedChildCount > 1) then
  begin
    Name:= LowerText(N.NamedChild(1));
    if (Name <> '') and (Name <> AInfo.Name) then
      EmitAt(N, 'inherited-wrong-method',
        Format('Override of "%s" calls "inherited %s": the ancestor method of the same name is not called',
          [AInfo.Name, Trim(NodeStr(N.NamedChild(1)))]), 'warning');
  end;
  for I:= 0 to N.NamedChildCount - 1 do ScanWrongMethod(N.NamedChild(I), AInfo);
end;

procedure TExcRun.CheckWrongMethod(const ADef: TTSNode; const AInfo: TExcMethodInfo);
begin
  if (not AInfo.IsOverride) or AInfo.IsCtorDtor then Exit;
  ScanWrongMethod(ADef.ChildByField('body'), AInfo);
end;

{ message-handler-without-inherited. }
procedure TExcRun.CheckMessageHandler(const ADef: TTSNode; const AInfo: TExcMethodInfo);  // dl:ok too-many-exit-points@2a82 -- REVIEWED 2026-11-14 v151 INT: guard clauses per syntax shape; each early exit is a classification
var
  Body, Hdr: TTSNode;
  Stmts    : TList<TTSNode>;
  Empty    : Boolean;
begin
  if (not AInfo.IsMessage) or (AInfo.MessageId = '') then Exit;
  if not (StartsText('wm_', AInfo.MessageId) or StartsText('cm_', AInfo.MessageId)
          or StartsText('cn_', AInfo.MessageId)) then Exit;
  Body:= ADef.ChildByField('body');
  if Body.IsNull or (Body.NodeType <> 'block') then Exit;
  Stmts:= BodyStatements(Body);
  try
    Empty:= Stmts.Count = 0;
  finally
    Stmts.Free;
  end;
  if Empty then Exit; { an empty handler swallows the message on purpose }
  if ContainsNode(Body, 'inherited') then Exit;
  if ContainsIdent(Body, ['DefaultHandler', 'DefWindowProc', 'CallWindowProc', 'Default', 'DefFrameProc',
       'DefMDIChildProc', 'WndProc', 'Dispatch']) then Exit;
  if ContainsResultAssign(Body) then Exit; { the handler answers the message itself }
  Hdr:= ADef.ChildByField('header');
  EmitAt(Hdr.ChildByField('name'), 'message-handler-without-inherited',
    Format('Message handler "%s" neither calls inherited nor a default handler: the default processing of %s is lost',
      [AInfo.Name, UpperCase(AInfo.MessageId)]), 'warning');
end;

{ inherited-without-ancestor: bare inherited in a plain new method no ancestor declares. }
procedure TExcRun.CheckNoAncestor(const ADef: TTSNode; const AInfo: TExcMethodInfo; const AClass: string);
var
  Body    : TTSNode;
  Stmts    : TList<TTSNode>;
  S        : TTSNode;
  Vis      : string;
  Bare     : TTSNode;
  Found    : Boolean;
begin
  if AInfo.IsOverride or AInfo.IsReintro or AInfo.IsMessage or AInfo.IsVirtual or AInfo.IsCtorDtor  // dl:ok boolean-expression-complexity@bd59 -- REVIEWED 2026-11-14 v151 INT: one flat predicate over fixed values; splitting it does not make it clearer
     or AInfo.IsClassProc then Exit;
  Body:= ADef.ChildByField('body');
  if Body.IsNull or (Body.NodeType <> 'block') then Exit;
  Found:= False;
  Bare:= Default(TTSNode);
  Stmts:= BodyStatements(Body);
  try
    for S in Stmts do
      if IsBareInherited(S) then begin
        Bare:= S;
        Found:= True;
        Break;
      end;
  finally
    Stmts.Free;
  end;
  if not Found then Exit;
  if AncestorMember(AClass, AInfo.Name, Vis) <> 0 then Exit;
  EmitAt(Bare, 'inherited-without-ancestor',
    Format('"inherited" in "%s" does nothing: no ancestor of %s declares a method of that name (forgotten override?)',
      [AInfo.Name, AClass]), 'warning');
end;

{ override-only-inherited: an override whose whole body forwards to the ancestor. }
procedure TExcRun.CheckOnlyInherited(const ADef: TTSNode; const AInfo: TExcMethodInfo; const AClass: string);  // dl:ok too-many-exit-points@1959 -- REVIEWED 2026-11-14 v151 INT: guard clauses per syntax shape; each early exit is a classification
var
  Body, Args: TTSNode;
  Stmts     : TList<TTSNode>;
  Tgt, Vis  : string;
  I         : Integer;
  Forward   : Boolean;
  Hdr       : TTSNode;
begin
  if not AInfo.IsOverride then Exit;
  if AInfo.IsOverload then Exit;
  Body:= ADef.ChildByField('body');
  if Body.IsNull or (Body.NodeType <> 'block') then Exit;
  Stmts:= BodyStatements(Body);
  try
    if Stmts.Count <> 1 then Exit;
    Tgt:= InheritedTarget(Stmts[0], Args);
    if Tgt = '?' then Exit;
    if (Tgt <> '') and (Tgt <> AInfo.Name) then Exit;
    Forward:= True;
    if (not Args.IsNull) and (Args.NamedChildCount > 0) then
    begin
      if Args.NamedChildCount <> Length(AInfo.ArgNames) then Forward:= False
      else
        for I:= 0 to Args.NamedChildCount - 1 do
          if LowerText(Args.NamedChild(I)) <> AInfo.ArgNames[I] then Forward:= False;
    end
    else if (Tgt <> '') and (Length(AInfo.ArgNames) > 0) and Args.IsNull then
      Forward:= True; { `inherited Name;` passes the current arguments }
    if not Forward then Exit;
  finally
    Stmts.Free;
  end;
  { an override in a more visible section may widen the visibility: only flag when the ancestor
    method is known to be at least as visible }
  if (AInfo.Vis = 'public') or (AInfo.Vis = 'published') then
  begin
    if AncestorMember(AClass, AInfo.Name, Vis) <> 1 then Exit;
    if not (ContainsText(Vis, 'public') or ContainsText(Vis, 'published')) then Exit;
  end;
  Hdr:= ADef.ChildByField('header');
  EmitAt(Hdr.ChildByField('name'), 'override-only-inherited',
    Format('Override "%s" only calls inherited: delete it, it changes nothing', [AInfo.Name]), 'hint');
end;

{ missing-inherited-call: an override of a component method that must chain to the ancestor. }
procedure TExcRun.CheckMissingInherited(const ADef: TTSNode; const AInfo: TExcMethodInfo; const AClass: string);
var
  Body, Hdr: TTSNode;
  Cls      : TExcClassInfo;
begin
  if (not AInfo.IsOverride) or AInfo.IsCtorDtor then Exit;
  if not MatchText(AInfo.Name, ['loaded', 'createparams', 'createwnd', 'notification', 'setparent', 'paint']) then Exit;
  if (AInfo.Name = 'paint') and FClasses.TryGetValue(AClass, Cls) and (Length(Cls.Parents) > 0)
     and MatchText(Cls.Parents[0], ['tcustomcontrol', 'tgraphiccontrol', 'tcontrol', 'twincontrol']) then Exit;
  Body:= ADef.ChildByField('body');
  if Body.IsNull or (Body.NodeType <> 'block') then Exit;
  if ContainsNode(Body, 'inherited') or ContainsNode(Body, 'asm') then Exit;
  Hdr:= ADef.ChildByField('header');
  EmitAt(Hdr.ChildByField('name'), 'missing-inherited-call',
    Format('Override "%s" does not call inherited: the ancestor''s own work for this hook is skipped', [AInfo.Name]),
    'warning');
end;

procedure TExcRun.CheckProc(const ADef: TTSNode);
var
  Info : TExcMethodInfo;
  Cls  : string;
begin
  if IsDtorProc(ADef) and FWants('inherited-order') then CheckDtorOrder(ADef);
  if not ProcInfo(ADef, Info, Cls) then Exit;
  if FWants('inherited-wrong-method') then CheckWrongMethod(ADef, Info);
  if FWants('message-handler-without-inherited') then CheckMessageHandler(ADef, Info);
  if FWants('inherited-without-ancestor') then CheckNoAncestor(ADef, Info, Cls);
  if FWants('override-only-inherited') then CheckOnlyInherited(ADef, Info, Cls);
  if FWants('missing-inherited-call') then CheckMissingInherited(ADef, Info, Cls);
end;

procedure TExcRun.Visit(const N: TTSNode);
var
  I, J: Integer;
  C   : TTSNode;
  Vr  : string;
begin
  if N.IsNull then Exit;
  if N.NodeType = 'defProc' then CheckProc(N)
  else if N.NodeType = 'try' then
  begin
    if FWants('except-handler-order') then CheckTry(N);
  end
  else if N.NodeType = 'exceptionHandler' then
  begin
    if FWants('exception-freed') then
    begin
      Vr:= '';
      for J:= 0 to N.NamedChildCount - 1 do
        if N.NamedChild(J).NodeType = 'identifier' then
        begin
          if N.NamedChild(J).StartByte < N.ChildByField('exception').StartByte then
            Vr:= LowerText(N.NamedChild(J));
          Break;
        end;
      if (Vr <> '') and (not ContainsIdent(N, ['AcquireExceptionObject', 'RaiseOuterException'])) then
        for J:= 0 to N.NamedChildCount - 1 do
        begin
          C:= N.NamedChild(J);
          if C.StartByte > N.ChildByField('exception').StartByte then ScanHandlerFree(C, Vr);
        end;
    end;
  end
  else if N.NodeType = 'statement' then  // dl:ok collapsible-if@0cce -- REVIEWED 2026-11-14 v151 INT: outer test guards a distinct shape; kept separate for the comment and later branches
  begin
    if FWants('destroy-called-directly') then CheckDestroyDirect(N);
  end;
  for I:= 0 to N.NamedChildCount - 1 do Visit(N.NamedChild(I));
end;

function TExcRun.Run(const ARoot: TTSNode): TArray<TLintFinding>;
begin
  CollectClasses(ARoot);
  Visit(ARoot);
  Result:= FFindings.ToArray;
end;

end.
