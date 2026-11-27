unit DRagLint.V156.MEMA.Support;

{ Wave v156 lane MEM-A -- helpers of DRagLint.V156.MEMA (private to the lane).

  container-items-leak (G-01): a LOCAL container that does not own its items (TList<T>, TStack<T>,
  TQueue<T>, TThreadList<T>, TDictionary<K, V>, the non-generic TList, and TObjectList / TObjectStack /
  TObjectQueue created with Create(False)) receives a FRESH instance of a class -- X.Add(TFoo.Create), or a
  local that only ever holds a TFoo.Create -- and nothing in the routine frees an item, hands an item on,
  or hands the container on. Only the container is released then, so every item leaks.

  Silent (each one is a fixture control):
    the container owns its items (TObjectList<T>.Create, OwnsObjects touched anywhere in the routine);
    an item is freed anywhere in the routine -- a loop over the container, X[I].Free, a cast of it;
    the container is returned, assigned to anything, passed to a routine, captured by "with";
    an item is passed to a routine or assigned to something that is not a local;
    the element type is an interface or a record, or the created type is not KNOWN to be a class
    (the file, then the project index, then the library index: an unknown type never reports);
    the constructor gets an owner (Self, Owner, AOwner, Application, ..);
    the added value is not fresh (a parameter, a field, a function result). }

interface

uses
  System.SysUtils
  , System.Generics.Collections
  , TreeSitter
  , DRagLint.Core.Model
  , DRagLint.Core.Interfaces
  ;

type
  /// <summary>What the lane knows about a type name.</summary>
  /// <remarks>mtkUnknown = declared nowhere the run can see, or declared with two different kinds.</remarks>
  TMemaTypeKind = (mtkUnknown, mtkClass, mtkInterface, mtkRecord, mtkOther);

  /// <summary>One run of container-items-leak over one parsed file.</summary>
  /// <remarks>Create, Run once, Free. Not thread-safe; the owner is TV156MEMARules.CheckFile.
  /// The stores may be nil: a type the file does not declare is unknown then, and an unknown type
  /// never reports.</remarks>
  TMemaRun = class  // dl:ok god-class@e76b, high-response@e76b -- REVIEWED 2026-11-26 v156 MEM-A: one walker per file run; the classifiers share its tree helpers and the per-candidate state, splitting it would only pass that state around
  strict private
    FFile     : string;
    FSrc      : TBytes;
    FStore    : ISymbolStore;
    FLib      : ISymbolStore;
    FFindings : TList<TLintFinding>;
    FTypeDecls: TDictionary<string, TMemaTypeKind>;   // lower type name -> kind, file declarations
    FKindCache: TDictionary<string, TMemaTypeKind>;   // lower type name -> kind, store answers
    { state of the routine / candidate being judged }
    FLocals   : TDictionary<string, Boolean>;         // lower names of the routine's locals
    FAliases  : TDictionary<string, Boolean>;         // lower names of locals that hold an item
    FRoutine  : TTSNode;
    FName     : string;                               // lower name of the candidate container
    FAssigns  : Integer;
    FEscaped  : Boolean;
    FChanged  : Boolean;
    FHasAdd   : Boolean;
    FFirstAdd : TTSNode;
    FItemText : string;
    function NodeStr(const N: TTSNode): string;
    function Squeezed(const N: TTSNode): string;
    function LowerText(const N: TTSNode): string;
    function IsIdent(const N: TTSNode): Boolean;
    function FirstIdent(const N: TTSNode): TTSNode;
    function SameNode(const A, B: TTSNode): Boolean;
    function IsRoutineNode(const N: TTSNode): Boolean;
    function CallArgs(const ACall: TTSNode): TArray<TTSNode>;
    function AssignTarget(const AAssign: TTSNode): TTSNode;
    function DeclKind(const ADecl: TTSNode): TMemaTypeKind;
    function StoreKind(const AStore: ISymbolStore; const AName: string): TMemaTypeKind;
    function KindOf(const ATypeName: string): TMemaTypeKind;
    function SplitCreate(const AText: string; out AHead, AArgs: string): Boolean;
    function ContainerElement(const ACreateText: string; out AElem: string): Boolean;
    function FreshClassCreate(const AText: string): Boolean;
    function FreshLocal(const ALowerName: string): Boolean;
    function FreshItem(const AArg: TTSNode): Boolean;
    function ElementMayLeak(const AElem: string): Boolean;
    procedure AddAlias(const ALowerName: string);
    procedure CollectTypeDecls(const N: TTSNode);
    procedure CollectLocals(const N: TTSNode; ATop: Boolean);
    procedure CollectCandidates(const N: TTSNode; ATop: Boolean; const ANames: TList<string>);
    procedure ClassifyItem(const AExpr: TTSNode);
    procedure ClassifyContainer(const N: TTSNode);
    procedure ClassifyValue(const N: TTSNode);
    procedure ClassifyMember(const ADot: TTSNode);
    function ArgsOfCall(const AArgs: TTSNode; out ACall: TTSNode): Boolean;
    procedure ClassifyAlias(const N: TTSNode);
    procedure WalkUses(const N: TTSNode);
    procedure JudgeCandidate(const ALowerName: string);
    procedure CheckRoutine(const ADef: TTSNode);
    procedure Visit(const N: TTSNode);
    procedure Emit(const ASite: TTSNode; const AMsg: string);
  public
    /// <summary>Binds the run to one file.</summary>
    /// <param name="AFile">Path of the .pas, as findings report it.</param>
    /// <param name="ASrc">The file's bytes, the ones the tree was parsed from.</param>
    /// <param name="AStore">Project index or nil.</param>
    /// <param name="ALib">Library index or nil.</param>
    constructor Create(const AFile: string; const ASrc: TBytes; const AStore, ALib: ISymbolStore);
    /// <summary>Frees the run's lists.</summary>
    destructor Destroy; override;
    /// <summary>Checks every routine of the tree.</summary>
    /// <param name="ARoot">Root node of the file's parse tree.</param>
    /// <returns>One finding per leaking container, at its first fresh addition; nil when none.</returns>
    function Run(const ARoot: TTSNode): TArray<TLintFinding>;
  end;

implementation

uses
  System.StrUtils
  , DRagLint.Diagnostics.ParseCache
  ;

const
  RULE_ID     = 'container-items-leak';
  SEV_WARNING = 'warning';
  NODE_TYPE   = 'type';
  NODE_INTF   = 'declIntf';
  NODE_CLASS  = 'declClass';
  CAST_ANY: array[0..1] of string = ('tobject', 'pointer');
  MAX_PASSES  = 6;
  CREATE_WORD = '.create';
  NODE_ASSIGN = 'assignment';
  NODE_CALL   = 'exprCall';
  NODE_DOT    = 'exprDot';
  NODE_SUB    = 'exprSubscript';
  NODE_EACH   = 'foreach';
  NODE_WITH   = 'with';
  EXPR_PREFIX = 'expr';
  { a parent that takes the container itself: an assignment, a with, a call or a member of a wrapped value }
  VALUE_TAKERS: array[0..4] of string = ('assignment', 'with', 'exprCall', 'exprSubscript', 'exprDot');
  FIELD_LHS   = 'lhs';
  FIELD_RHS   = 'rhs';
  FIELD_ENTITY= 'entity';
  FIELD_ARGS  = 'args';
  FIELD_NAME  = 'name';
  FIELD_TYPE  = 'type';
  FIELD_ITERATOR = 'iterator';
  ROUTINE_NODES: array[0..1] of string = ('defProc', 'lambda');
  DECL_NODES   : array[0..2] of string = ('declVar', 'varDef', 'varAssignDef');
  { containers that never own their items }
  PLAIN_CONTAINERS: array[0..4] of string = ('tlist', 'tstack', 'tqueue', 'tthreadlist', 'tdictionary');
  { containers that own their items unless created with Create(False) }
  OWNING_CONTAINERS: array[0..2] of string = ('tobjectlist', 'tobjectstack', 'tobjectqueue');
  ADD_MEMBERS: array[0..5] of string = ('add', 'insert', 'push', 'enqueue', 'addorsetvalue', 'tryadd');
  FREE_MEMBERS: array[0..2] of string = ('free', 'disposeof', 'destroy');
  { members of the container that neither read an item nor change who owns one }
  QUIET_MEMBERS: array[0..17] of string = ('count', 'clear', 'sort', 'capacity', 'delete', 'remove', 'trimexcess',
    'pack', 'reverse', 'indexof', 'lastindexof', 'contains', 'containskey', 'containsvalue', 'isempty',
    'binarysearch', 'exchange', 'move');
  { calls that take the container or an item without taking it over }
  QUIET_CALLS: array[0..0] of string = ('assigned');
  CONTAINER_FREE_CALL = 'freeandnil';
  OWNS_MEMBER = 'ownsobjects';
  { first constructor argument that names an owner: the owner frees the instance }
  OWNER_ARGS: array[0..4] of string = ('self', 'owner', 'aowner', 'application', 'parent');
  OWNER_SUFFIX = 'owner';
  NOT_OWNING_ARG = 'false';
  DICTIONARY = 'tdictionary';

{ plumbing }

constructor TMemaRun.Create(const AFile: string; const ASrc: TBytes; const AStore, ALib: ISymbolStore);
begin
  inherited Create;
  FFile     := AFile;
  FSrc      := ASrc;
  FStore    := AStore;
  FLib      := ALib;
  FFindings := TList<TLintFinding>.Create;
  FTypeDecls:= TDictionary<string, TMemaTypeKind>.Create;
  FKindCache:= TDictionary<string, TMemaTypeKind>.Create;
  FLocals   := TDictionary<string, Boolean>.Create;
  FAliases  := TDictionary<string, Boolean>.Create;
end;

destructor TMemaRun.Destroy;
begin
  FAliases.Free;
  FLocals.Free;
  FKindCache.Free;
  FTypeDecls.Free;
  FFindings.Free;
  inherited Destroy;
end;

function TMemaRun.NodeStr(const N: TTSNode): string;
var
  S, L: Integer;
begin
  Result:= '';
  if N.IsNull then Exit;
  S:= Integer(N.StartByte);
  L:= Integer(N.EndByte) - S;
  if (L > 0) and (S >= 0) and (S + L <= Length(FSrc)) then
    Result:= TEncoding.UTF8.GetString(FSrc, S, L);
end;

{ The node's text without white space, case kept. }
function TMemaRun.Squeezed(const N: TTSNode): string;
var
  B: TStringBuilder;
  C: Char;
begin
  B:= TStringBuilder.Create;
  try
    for C in NodeStr(N) do
      if not CharInSet(C, [' ', #9, #10, #13]) then
        B.Append(C);
    Result:= B.ToString;
  finally
    B.Free;
  end;
end;

function TMemaRun.LowerText(const N: TTSNode): string;
begin
  Result:= LowerCase(Squeezed(N));
end;

function TMemaRun.IsIdent(const N: TTSNode): Boolean;
begin
  Result:= (not N.IsNull) and (N.NodeType = 'identifier');
end;

{ The first identifier at or under N, in source order; null when there is none. }
function TMemaRun.FirstIdent(const N: TTSNode): TTSNode;
var
  I: Integer;
begin
  Result:= N;
  if N.IsNull or IsIdent(N) then Exit;
  for I:= 0 to N.NamedChildCount - 1 do
  begin
    Result:= FirstIdent(N.NamedChild(I));
    if not Result.IsNull then Exit;
  end;
  Result:= Default(TTSNode);
end;

function TMemaRun.SameNode(const A, B: TTSNode): Boolean;
begin
  Result:= (not A.IsNull) and (not B.IsNull) and (A.StartByte = B.StartByte) and (A.EndByte = B.EndByte) and
    (A.NodeType = B.NodeType);
end;

function TMemaRun.IsRoutineNode(const N: TTSNode): Boolean;
begin
  Result:= MatchStr(N.NodeType, ROUTINE_NODES);
end;

function TMemaRun.CallArgs(const ACall: TTSNode): TArray<TTSNode>;
var
  A: TTSNode;
  I: Integer;
begin
  Result:= nil;
  A:= ACall.ChildByField(FIELD_ARGS);
  if A.IsNull then Exit;
  for I:= 0 to A.NamedChildCount - 1 do
    if not A.NamedChild(I).IsExtra then
      Result:= Result + [A.NamedChild(I)];
end;

{ The identifier an assignment writes: X := .. and var X := .. ; null for any other target. }
function TMemaRun.AssignTarget(const AAssign: TTSNode): TTSNode;
var
  I: Integer;
  L: TTSNode;
begin
  L:= AAssign.ChildByField(FIELD_LHS);
  Result:= L;
  if L.IsNull or IsIdent(L) then Exit;
  Result:= Default(TTSNode);
  if not MatchStr(L.NodeType, DECL_NODES) then Exit;
  for I:= 0 to L.NamedChildCount - 1 do
    if IsIdent(L.NamedChild(I)) then
      Exit(L.NamedChild(I));
end;

procedure TMemaRun.Emit(const ASite: TTSNode; const AMsg: string);
var
  P, Q: TTSPoint;
  F   : TLintFinding;
begin
  P:= ASite.StartPoint;
  Q:= ASite.EndPoint;
  F:= Default(TLintFinding);
  F.RuleId   := RULE_ID;
  F.Severity := SEV_WARNING;
  F.Message  := AMsg;
  F.FilePath := FFile;
  F.StartLine:= Integer(P.Row) + 1;
  F.StartCol := TAstParseCache.CharCol(F.FilePath, P);
  F.EndLine  := Integer(Q.Row) + 1;
  F.EndCol   := TAstParseCache.CharCol(F.FilePath, Q);
  FFindings.Add(F);
end;

{ type knowledge }

function TMemaRun.DeclKind(const ADecl: TTSNode): TMemaTypeKind;
var
  T, Inner: TTSNode;
  I       : Integer;
begin
  Result:= mtkOther;
  T:= ADecl.ChildByField(FIELD_TYPE);
  if T.IsNull then Exit(mtkUnknown);
  Inner:= T;
  if (T.NodeType = NODE_TYPE) and (T.NamedChildCount = 1) then
    Inner:= T.NamedChild(0);
  if Inner.NodeType = NODE_INTF then
    Result:= mtkInterface
  else if Inner.NodeType = NODE_CLASS then
    for I:= 0 to Inner.ChildCount - 1 do
      if Inner.Child(I).NodeType = 'kRecord' then
        Result:= mtkRecord
      else if (Inner.Child(I).NodeType = 'kClass') and (Result = mtkOther) then
        Result:= mtkClass;
end;

{ Every type declaration of the file, any scope; a name declared twice with two kinds is unknown. }
procedure TMemaRun.CollectTypeDecls(const N: TTSNode);
var
  I   : Integer;
  Nm  : TTSNode;
  K, O: TMemaTypeKind;
  Key : string;
begin
  if N.IsNull then Exit;
  if N.NodeType = 'declType' then
  begin
    Nm:= N.ChildByField(FIELD_NAME);
    if not Nm.IsNull then
    begin
      Key:= LowerText(Nm);
      I:= Pos('<', Key);
      if I > 0 then
        Key:= Copy(Key, 1, I - 1);
      K:= DeclKind(N);
      if FTypeDecls.TryGetValue(Key, O) and (O <> K) then
        K:= mtkUnknown;
      FTypeDecls.AddOrSetValue(Key, K);
    end;
  end;
  for I:= 0 to N.NamedChildCount - 1 do
    CollectTypeDecls(N.NamedChild(I));
end;

{ The kind every type row of that name agrees on; mtkUnknown when there is none or they disagree. }
function TMemaRun.StoreKind(const AStore: ISymbolStore; const AName: string): TMemaTypeKind;
var
  S   : TSymbol;
  One : TMemaTypeKind;
  Seen: Boolean;
begin
  Result:= mtkUnknown;
  if AStore = nil then Exit;
  Seen:= False;
  for S in AStore.FindSymbolsByExactName(AName) do
  begin
    case S.Kind of
      skClass    : One:= mtkClass;
      skInterface: One:= mtkInterface;
      skRecord   : One:= mtkRecord;
      skEnum, skTypeAlias: One:= mtkOther;
    else
      Continue;
    end;
    if Seen and (One <> Result) then Exit(mtkUnknown);
    Seen:= True;
    Result:= One;
  end;
end;

{ ATypeName: a type as written, white space removed; a unit prefix and generic arguments are dropped. }
function TMemaRun.KindOf(const ATypeName: string): TMemaTypeKind;
var
  Name, Key: string;
  P        : Integer;
begin
  Name:= ATypeName;
  P:= Pos('<', Name);
  if P > 0 then
    Name:= Copy(Name, 1, P - 1);
  P:= LastDelimiter('.', Name);
  if P > 0 then
    Name:= Copy(Name, P + 1, MaxInt);
  Key:= LowerCase(Name);
  if Key = '' then Exit(mtkUnknown);
  if FTypeDecls.TryGetValue(Key, Result) then Exit;
  if FKindCache.TryGetValue(Key, Result) then Exit;
  Result:= StoreKind(FStore, Name);
  if Result = mtkUnknown then
    Result:= StoreKind(FLib, Name);
  FKindCache.AddOrSetValue(Key, Result);
end;

{ text shapes }

{ AText = <head>.Create or <head>.Create(<args>), the .Create outside every bracket. }
function TMemaRun.SplitCreate(const AText: string; out AHead, AArgs: string): Boolean;
var
  I, Depth: Integer;
  Low, Tail: string;
begin
  AHead:= '';
  AArgs:= '';
  Result:= False;
  Low:= LowerCase(AText);
  Depth:= 0;
  for I:= 1 to Length(Low) do
  begin
    if CharInSet(Low[I], ['(', '<', '[']) then
      Inc(Depth)
    else if CharInSet(Low[I], [')', '>', ']']) then
      Dec(Depth)
    else if (Depth = 0) and (Low[I] = '.') and (Copy(Low, I, Length(CREATE_WORD)) = CREATE_WORD) then
    begin
      Tail:= Copy(AText, I + Length(CREATE_WORD), MaxInt);
      if (Tail <> '') and not (StartsStr('(', Tail) and EndsStr(')', Tail)) then Exit;
      AHead:= Copy(AText, 1, I - 1);
      if Tail <> '' then
        AArgs:= Copy(Tail, 2, Length(Tail) - 2);
      Exit(AHead <> '');
    end;
  end;
end;

{ ACreateText creates a container that does not own its items; AElem = its element type as written
  ('' for a non-generic container). }
function TMemaRun.ContainerElement(const ACreateText: string; out AElem: string): Boolean;
var
  Head, Args, Base, TypeArgs: string;
  P, I, Depth               : Integer;
begin
  AElem:= '';
  Result:= False;
  if not SplitCreate(ACreateText, Head, Args) then Exit;
  TypeArgs:= '';
  P:= Pos('<', Head);
  if P > 0 then
  begin
    if not EndsStr('>', Head) then Exit;
    TypeArgs:= Copy(Head, P + 1, Length(Head) - P - 1);
    Head:= Copy(Head, 1, P - 1);
  end;
  Base:= LowerCase(Copy(Head, LastDelimiter('.', Head) + 1, MaxInt));
  if MatchStr(Base, OWNING_CONTAINERS) then
  begin
    if LowerCase(Args) <> NOT_OWNING_ARG then Exit;
  end
  else if not MatchStr(Base, PLAIN_CONTAINERS) then
    Exit;
  if (Base = DICTIONARY) and (TypeArgs = '') then Exit;
  { the element is the last type argument: the value type of a dictionary }
  AElem:= TypeArgs;
  Depth:= 0;
  for I:= 1 to Length(TypeArgs) do
    if TypeArgs[I] = '<' then
      Inc(Depth)
    else if TypeArgs[I] = '>' then
      Dec(Depth)
    else if (Depth = 0) and (TypeArgs[I] = ',') then
      AElem:= Copy(TypeArgs, I + 1, MaxInt);
  Result:= True;
end;

{ AText = TFoo.Create / TFoo.Create(..) of a type KNOWN to be a class, with no owner argument. }
function TMemaRun.FreshClassCreate(const AText: string): Boolean;
var
  Head, Args, First: string;
  P                : Integer;
begin
  Result:= False;
  if not SplitCreate(AText, Head, Args) then Exit;
  if KindOf(Head) <> mtkClass then Exit;
  First:= LowerCase(Args);
  P:= Pos(',', First);
  if P > 0 then
    First:= Copy(First, 1, P - 1);
  Result:= not (MatchStr(First, OWNER_ARGS) or EndsStr(OWNER_SUFFIX, First));
end;

{ A local of the routine that is assigned at least once and only ever a fresh class instance. }
function TMemaRun.FreshLocal(const ALowerName: string): Boolean;
var
  Seen, Other: Boolean;

  procedure Scan(const N: TTSNode);
  var
    I: Integer;
    T: TTSNode;
  begin
    if N.IsNull or Other then Exit;
    if N.NodeType = NODE_ASSIGN then
    begin
      T:= AssignTarget(N);
      if IsIdent(T) and (LowerCase(NodeStr(T)) = ALowerName) then
      begin
        if FreshClassCreate(Squeezed(N.ChildByField(FIELD_RHS))) then
          Seen:= True
        else
          Other:= True;
      end;
    end;
    for I:= 0 to N.NamedChildCount - 1 do
      Scan(N.NamedChild(I));
  end;

begin
  Seen:= False;
  Other:= False;
  Scan(FRoutine);
  Result:= Seen and not Other;
end;

function TMemaRun.FreshItem(const AArg: TTSNode): Boolean;
var
  Name: string;
begin
  if IsIdent(AArg) then
  begin
    Name:= LowerCase(NodeStr(AArg));
    Result:= (Name <> FName) and FLocals.ContainsKey(Name) and FreshLocal(Name);
    if Result then
      AddAlias(Name);
  end
  else
    Result:= FreshClassCreate(Squeezed(AArg));
end;

{ False when the element type cannot leak: an interface (counted), a record, or -- undeclared anywhere the
  run sees -- a name that follows the interface convention (I + capital). }
function TMemaRun.ElementMayLeak(const AElem: string): Boolean;
var
  Name: string;
begin
  Result:= True;
  if AElem = '' then Exit;
  case KindOf(AElem) of
    mtkInterface, mtkRecord, mtkOther: Result:= False;
    mtkUnknown:
      begin
        Name:= Copy(AElem, LastDelimiter('.', AElem) + 1, MaxInt);
        Result:= not ((Length(Name) > 1) and (Name[1] = 'I') and CharInSet(Name[2], ['A'..'Z']));
      end;
  end;
end;

procedure TMemaRun.AddAlias(const ALowerName: string);
begin
  if (ALowerName = FName) or FAliases.ContainsKey(ALowerName) then Exit;
  FAliases.Add(ALowerName, True);
  FChanged:= True;
end;

{ per routine }

procedure TMemaRun.CollectLocals(const N: TTSNode; ATop: Boolean);
var
  I: Integer;
  C: TTSNode;
begin
  if N.IsNull then Exit;
  if (not ATop) and IsRoutineNode(N) then Exit;
  if MatchStr(N.NodeType, DECL_NODES) then
    for I:= 0 to N.NamedChildCount - 1 do
    begin
      C:= N.NamedChild(I);
      if IsIdent(C) then
        FLocals.AddOrSetValue(LowerCase(NodeStr(C)), True);
    end;
  if N.NodeType = DECL_NODES[0] then Exit;
  for I:= 0 to N.NamedChildCount - 1 do
    CollectLocals(N.NamedChild(I), False);
end;

{ Locals of the routine that are assigned a non-owning container, in source order. }
procedure TMemaRun.CollectCandidates(const N: TTSNode; ATop: Boolean; const ANames: TList<string>);
var
  I   : Integer;
  T   : TTSNode;
  Name: string;
  Elem: string;
begin
  if N.IsNull then Exit;
  if (not ATop) and IsRoutineNode(N) then Exit;
  if N.NodeType = NODE_ASSIGN then
  begin
    T:= AssignTarget(N);
    if IsIdent(T) then
    begin
      Name:= LowerCase(NodeStr(T));
      if FLocals.ContainsKey(Name) and (not ANames.Contains(Name)) and
         ContainerElement(Squeezed(N.ChildByField(FIELD_RHS)), Elem) and ElementMayLeak(Elem) then
        ANames.Add(Name);
    end;
  end;
  for I:= 0 to N.NamedChildCount - 1 do
    CollectCandidates(N.NamedChild(I), False, ANames);
end;

{ AArgs is the argument list of a call; ACall = that call. }
function TMemaRun.ArgsOfCall(const AArgs: TTSNode; out ACall: TTSNode): Boolean;
begin
  ACall:= AArgs.Parent;
  Result:= (not ACall.IsNull) and (ACall.NodeType = NODE_CALL) and SameNode(ACall.ChildByField(FIELD_ARGS), AArgs);
end;

{ AExpr is an item of the container (X[I], X.First, a local that holds one, a cast of one): decide from
  where it stands whether the routine frees it or hands it on. }
procedure TMemaRun.ClassifyItem(const AExpr: TTSNode);
var
  E, P, Call, T: TTSNode;
  Name         : string;
  Done         : Boolean;
begin
  E:= AExpr;
  Done:= False;
  while not Done do
  begin
    Done:= True;
    P:= E.Parent;
    if P.IsNull then Exit;
    if P.NodeType = NODE_DOT then
    begin
      { a member of the item: only a destructor call changes who owns it }
      if SameNode(P.ChildByField(FIELD_LHS), E) and MatchStr(LowerText(P.ChildByField(FIELD_RHS)), FREE_MEMBERS) then
        FEscaped:= True;
    end
    else if ArgsOfCall(P, Call) then
    begin
      T:= Call.ChildByField(FIELD_ENTITY);
      Name:= LowerText(T);
      if (T.NodeType = NODE_DOT) and (LowerText(T.ChildByField(FIELD_LHS)) = FName) and
         MatchStr(LowerText(T.ChildByField(FIELD_RHS)), ADD_MEMBERS) then
        { the addition itself }
      else if IsIdent(T) and (P.NamedChildCount = 1) and ((KindOf(NodeStr(T)) <> mtkUnknown) or MatchStr(Name, CAST_ANY)) then
      begin
        { a cast: judge the cast expression instead }
        E:= Call;
        Done:= False;
      end
      else if not MatchStr(Name, QUIET_CALLS) then
        FEscaped:= True;
    end
    else if P.NodeType = NODE_ASSIGN then
    begin
      if SameNode(P.ChildByField(FIELD_RHS), E) then
      begin
        T:= AssignTarget(P);
        Name:= if IsIdent(T) then LowerCase(NodeStr(T)) else '';
        if (Name <> '') and (Name <> FName) and FLocals.ContainsKey(Name) then
          AddAlias(Name)
        else
          FEscaped:= True;
      end;
    end
    else if P.NodeType = NODE_WITH then
      FEscaped:= True
    else if StartsStr(EXPR_PREFIX, P.NodeType) and (P.NodeType <> NODE_CALL) and (P.NodeType <> NODE_SUB) then
    begin
      { parentheses, "as", an operator: the value is still the item }
      E:= P;
      Done:= False;
    end;
  end;
end;

{ ADot = X.Member with the container X as the receiver. }
procedure TMemaRun.ClassifyMember(const ADot: TTSNode);
var
  Member: string;
  Up, E : TTSNode;
  Args  : TArray<TTSNode>;
begin
  Member:= LowerText(ADot.ChildByField(FIELD_RHS));
  Up:= ADot.Parent;
  if MatchStr(Member, ADD_MEMBERS) then
  begin
    if (not Up.IsNull) and (Up.NodeType = NODE_CALL) and SameNode(Up.ChildByField(FIELD_ENTITY), ADot) then
    begin
      Args:= CallArgs(Up);
      if (Length(Args) > 0) and FreshItem(Args[High(Args)]) and not FHasAdd then
      begin
        FHasAdd:= True;
        FFirstAdd:= Up;
        FItemText:= Squeezed(Args[High(Args)]);
      end;
    end;
  end
  else if Member = OWNS_MEMBER then
    FEscaped:= True
  else if not (MatchStr(Member, QUIET_MEMBERS) or MatchStr(Member, FREE_MEMBERS)) then
  begin
    { Items, First, Last, Pop, Values, ToArray, .. : an item, or all of them }
    E:= ADot;
    if (not Up.IsNull) and (Up.NodeType = NODE_CALL) and SameNode(Up.ChildByField(FIELD_ENTITY), E) then
      E:= Up;
    Up:= E.Parent;
    if (not Up.IsNull) and (Up.NodeType = NODE_SUB) and SameNode(Up.ChildByField(FIELD_ENTITY), E) then
      E:= Up;
    ClassifyItem(E);
  end;
end;

{ N = one use of the container's name. }
procedure TMemaRun.ClassifyContainer(const N: TTSNode);
var
  P, V: TTSNode;
begin
  P:= N.Parent;
  if P.IsNull then Exit;
  if MatchStr(P.NodeType, DECL_NODES) then
  begin
    if (not P.Parent.IsNull) and (P.Parent.NodeType = NODE_ASSIGN) then
      Inc(FAssigns);
  end
  else if (P.NodeType = NODE_ASSIGN) and SameNode(P.ChildByField(FIELD_LHS), N) then
    Inc(FAssigns)
  else if (P.NodeType = NODE_DOT) and SameNode(P.ChildByField(FIELD_LHS), N) then
    ClassifyMember(P)
  else if (P.NodeType = NODE_SUB) and SameNode(P.ChildByField(FIELD_ENTITY), N) then
    ClassifyItem(P)
  else if P.NodeType = NODE_EACH then
  begin
    { for V in X do: V holds an item }
    V:= FirstIdent(P.ChildByField(FIELD_ITERATOR));
    if IsIdent(V) and not SameNode(V, N) then
      AddAlias(LowerCase(NodeStr(V)))
    else
      FEscaped:= True;
  end
  else
    ClassifyValue(N);
end;

{ N = the container's name used as a value: assigned, passed, returned, captured by "with". }
procedure TMemaRun.ClassifyValue(const N: TTSNode);
var
  P, E, Call: TTSNode;
  Name      : string;
  Done      : Boolean;
begin
  E:= N;
  Done:= False;
  while not Done do
  begin
    Done:= True;
    P:= E.Parent;
    if P.IsNull then
      { top of the tree }
    else if ArgsOfCall(P, Call) then
    begin
      Name:= LowerText(Call.ChildByField(FIELD_ENTITY));
      if (Name <> CONTAINER_FREE_CALL) and not MatchStr(Name, QUIET_CALLS) then
        FEscaped:= True;
    end
    else if MatchStr(P.NodeType, VALUE_TAKERS) then
      FEscaped:= True
    else if StartsStr(EXPR_PREFIX, P.NodeType) then
    begin
      E:= P;
      Done:= False;
    end;
  end;
end;

{ N = one use of a local that holds an item. }
procedure TMemaRun.ClassifyAlias(const N: TTSNode);
var
  P: TTSNode;
begin
  P:= N.Parent;
  if P.IsNull or MatchStr(P.NodeType, DECL_NODES) or (P.NodeType = NODE_EACH) then Exit;
  if (P.NodeType = NODE_ASSIGN) and SameNode(P.ChildByField(FIELD_LHS), N) then Exit;
  ClassifyItem(N);
end;

{ Every use of the container and of the item locals in the routine, nested routines included. }
procedure TMemaRun.WalkUses(const N: TTSNode);
var
  I   : Integer;
  P   : TTSNode;
  Name: string;
begin
  if N.IsNull or FEscaped then Exit;
  if IsIdent(N) then
  begin
    P:= N.Parent;
    { the member name of X.Member and the name of a named argument are not uses of a local }
    if (not P.IsNull) and (P.NodeType = NODE_DOT) and SameNode(P.ChildByField(FIELD_RHS), N) then Exit;
    Name:= LowerCase(NodeStr(N));
    if Name = FName then
      ClassifyContainer(N)
    else if FAliases.ContainsKey(Name) then
      ClassifyAlias(N);
    Exit;
  end;
  for I:= 0 to N.NamedChildCount - 1 do
    WalkUses(N.NamedChild(I));
end;

procedure TMemaRun.JudgeCandidate(const ALowerName: string);
var
  Pass: Integer;
begin
  FName:= ALowerName;
  FAliases.Clear;
  Pass:= 0;
  repeat
    Inc(Pass);
    FChanged:= False;
    FEscaped:= False;
    FHasAdd := False;
    FAssigns:= 0;
    WalkUses(FRoutine);
  until FEscaped or (not FChanged) or (Pass >= MAX_PASSES);
  if FEscaped or FChanged or (not FHasAdd) or (FAssigns <> 1) then Exit;
  Emit(FFirstAdd, Format('Items of ''%s'' are never freed: the container does not own them, and the routine ' +
    'frees only the container (%s is added here). Free the items in a loop before the container, or use a ' +
    'container that owns them (TObjectList<T>, TObjectDictionary with doOwnsValues).',
    [NodeStr(FFirstAdd.ChildByField(FIELD_ENTITY).ChildByField(FIELD_LHS)), FItemText]));
end;

procedure TMemaRun.CheckRoutine(const ADef: TTSNode);
var
  Names: TList<string>;
  Name : string;
begin
  FRoutine:= ADef;
  FLocals.Clear;
  CollectLocals(ADef, True);
  if FLocals.Count = 0 then Exit;
  Names:= TList<string>.Create;
  try
    CollectCandidates(ADef, True, Names);
    for Name in Names do
      JudgeCandidate(Name);
  finally
    Names.Free;
  end;
end;

procedure TMemaRun.Visit(const N: TTSNode);
var
  I: Integer;
begin
  if N.IsNull then Exit;
  if N.NodeType = ROUTINE_NODES[0] then
    CheckRoutine(N);
  for I:= 0 to N.NamedChildCount - 1 do
    Visit(N.NamedChild(I));
end;

function TMemaRun.Run(const ARoot: TTSNode): TArray<TLintFinding>;
begin
  CollectTypeDecls(ARoot);
  Visit(ARoot);
  Result:= FFindings.ToArray;
end;

end.
