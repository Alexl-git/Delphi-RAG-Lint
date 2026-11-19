unit DRagLint.V151.TYP.Support;

{ Wave v151 lane TYP -- helpers of DRagLint.V151.TYP (private to the lane).
  One syntactic scan per unit over the tree-sitter AST (TAstParseCache), with the
  project / library index as an optional second source of type facts:

  * unrelated-class-cast             -- T(x) where the static class of x and T are
                                        on different branches of the class tree;
  * self-as-interface-in-constructor -- Self handed out as an interface while the
                                        reference count can still free the object;
  * destructor-not-nil-safe          -- the destructor dereferences a field that a
                                        constructor may not have created yet;
  * field-free-without-nil           -- FField.Free outside the destructor with a
                                        path to the routine end that leaves the
                                        dangling reference in the field;
  * field-ownership-unclear          -- a field created in a constructor, never
                                        freed by the class, but handed out: whether
                                        the class still owns it is unclear. }

interface

uses
  System.SysUtils
  , System.Generics.Collections
  , DRagLint.Core.Model
  , DRagLint.V151.Api
  ;

const
  /// <summary>Rule id: hard cast between two classes neither of which descends from the other.</summary>
  RULE_UNRELATED_CAST = 'unrelated-class-cast';
  /// <summary>Rule id: Self passed as an interface while construction can still free the object.</summary>
  RULE_SELF_INTF_CTOR = 'self-as-interface-in-constructor';
  /// <summary>Rule id: the destructor dereferences a field a raising constructor may have left nil.</summary>
  RULE_DTOR_NIL_SAFE = 'destructor-not-nil-safe';
  /// <summary>Rule id: a field is freed outside the destructor and keeps its dangling reference.</summary>
  RULE_FREE_WITHOUT_NIL = 'field-free-without-nil';
  /// <summary>Rule id: a field created by the class is handed out and never freed -- ownership unclear.</summary>
  RULE_OWNERSHIP_UNCLEAR = 'field-ownership-unclear';

/// <summary>Runs every rule of lane TYP that ACtx wants over one .pas file.</summary>
/// <param name="ACtx">The file; Store / LibStore may be nil, the file rules then use the unit's own
/// declarations only (a class tree that leaves the unit is unknown and the cast rule stays silent).</param>
/// <returns>Findings in document order per rule; nil when the file is clean or does not parse.</returns>
/// <remarks>
/// Stateless between calls; not thread-safe within one call (one scan object per call).
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.V151.TYP.TV151TYPRules.CheckFile (DRagLint.V151.TYP.pas)</para>
/// <para>Calls: DRagLint.Diagnostics.ParseCache.TAstParseCache.Get, DRagLint.V151.Api.TV151FileCtx.Wants, DRagLint.V151.TYP.Support.TTypScan.Create, DRagLint.V151.TYP.Support.TTypScan.Run, TreeSitter.TTSTree.RootNode</para>
/// <para>Returns: nil; Scan.Run</para>
/// <seealso cref="DRagLint.Diagnostics.ParseCache.TAstParseCache.Get"/>
/// <seealso cref="DRagLint.V151.Api.TV151FileCtx.Wants"/>
/// <seealso cref="DRagLint.V151.TYP.Support.TTypScan.Create"/>
/// <seealso cref="DRagLint.V151.TYP.Support.TTypScan.Run"/>
/// <seealso cref="TreeSitter.TTSTree.RootNode"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function TypCheckFile(const ACtx: TV151FileCtx): TArray<TLintFinding>;

implementation

uses
  System.Classes
  , System.StrUtils
  , TreeSitter
  , DRagLint.Core.Interfaces
  , DRagLint.Diagnostics.ParseCache
  , DRagLint.Lint.RefTypeRules
  ;

const
  { Raising-free constructors: they raise at most EOutOfMemory, so a field created
    after them is still created whenever the constructor gets that far. }
  SAFE_CREATE: array[0..21] of string = (
    'tstringlist', 'tlist', 'tobjectlist', 'tdictionary', 'tobjectdictionary', 'tstringbuilder',
    'tmemorystream', 'tqueue', 'tstack', 'tobjectqueue', 'tobjectstack', 'thashset', 'tinterfacelist',
    'tbits', 'tcomponentlist', 'tobject', 'tpersistent', 'tcriticalsection', 'tthreadlist',
    'tmultireadexclusivewritesynchronizer', 'tstrings', 'tbytesstream');
  { Calls that never raise for an argument of the right type. }
  SAFE_CALLS: array[0..15] of string = (
    'assigned', 'supports', 'length', 'low', 'high', 'ord', 'chr', 'sizeof', 'inc', 'dec', 'include',
    'exclude', 'fillchar', 'setlength', 'freeandnil', 'trim');
  { Receivers whose call takes over an argument: the class may no longer own it. }
  HANDOFF_PREFIXES: array[0..6] of string = ('add', 'insert', 'register', 'attach', 'push', 'enqueue', 'append');
  { Containers that free their items unless created with False. }
  OWNING_CONTAINERS: array[0..4] of string = ('tobjectlist', 'tobjectstack', 'tobjectqueue', 'tcomponentlist',
    'tobjectdictionary');
  { Owners of a created control: an argument here means the owner frees it. }
  OWNER_ARGS: array[0..3] of string = ('self', 'aowner', 'owner', 'powner');
  MAX_CHAIN = 32;
  { characters after a tear-down attribute line searched for the method it marks }
  ATTR_LOOKAHEAD = 400;
  { TryParts phases: before try, try part, except part, finally part }
  PH_TRY = 1;
  PH_EXCEPT = 2;
  PH_FINALLY = 3;
  { an infix node: lhs, operator, rhs }
  INFIX_KIDS = 3;

type
  { One class (or record) declared in the unit. }
  TTypClass = class
    Name       : string;                       { lower-case leaf name }
    RawName    : string;
    Parent     : string;                       { lower-case first heritage entry; '' = TObject }
    IsRecord   : Boolean;
    HasFields  : Boolean;
    HasVirtual : Boolean;                      { declares virtual / dynamic / abstract / message }
    HasNewInst : Boolean;                      { declares NewInstance }
    DeclRelease: Boolean;                      { declares _Release }
    Fields     : TDictionary<string, string>;  { lower field -> type text }
    FieldRaw   : TDictionary<string, string>;  { lower field -> field as written }
    PrivMeths  : TDictionary<string, Boolean>; { lower method names declared private }
    TearDowns  : TDictionary<string, Boolean>; { lower method names carrying a tear-down attribute }
    PropWrite  : TDictionary<string, Boolean>; { lower fields named as a property setter }
    constructor Create;
    destructor Destroy; override;
  end;

  { One scan of one unit. }
  TTypScan = class  // dl:ok high-response@66e0 -- REVIEWED 2026-11-14 v151 TYP: one scan of one unit for five rules sharing the class/field model; splitting it per rule would duplicate that model
  strict private
    FCtx      : TV151FileCtx;
    FSrc      : TBytes;
    FRoot     : TTSNode;
    FFindings : TList<TLintFinding>;
    FEmitted  : TDictionary<string, Boolean>;
    FRoutines : TList<TTSNode>;
    FClasses  : TObjectDictionary<string, TTypClass>;
    FIntfs    : TDictionary<string, Boolean>;
    FReader   : TExprTypeReader;
    FKindMemo : TDictionary<string, Integer>;
    { identifier index for ExemptFreeRoutines, built once on first use: lower-cased
      identifier -> (routine index, occurrences in that routine's body); plus the
      class and method name of each routine in FRoutines, by index }
    FIdentIdx : TObjectDictionary<string, TList<TPair<Integer, Integer>>>;
    FRtClass  : TArray<string>;
    FRtMeth   : TArray<string>;
    procedure BuildIdentIndex;
    function NodeStr(const N: TTSNode): string;
    function Canon(const AText: string): string;
    procedure Gather(const ARoot: TTSNode; const ATypes: array of string; const AList: TList<TTSNode>);
    procedure GatherWalk(const N: TTSNode; AIsRoot: Boolean; const ATypes: array of string; const AList: TList<TTSNode>);
    procedure Emit(const ARule, ASeverity: string; const N: TTSNode; const AMsg, ASym: string);
    function HasKeyword(const N: TTSNode; const AKind: string): Boolean;
    function ClassOf(const ARoutine: TTSNode): string;
    function MethodOf(const ARoutine: TTSNode): string;
    function IsCtor(const ARoutine: TTSNode): Boolean;
    function IsDtor(const ARoutine: TTSNode): Boolean;
    function BodyOf(const ARoutine: TTSNode): TTSNode;
    procedure ParseDecl(const AText: string; const AMap: TDictionary<string, string>;
      const ARaw: TDictionary<string, string>);
    procedure CollectClasses;
    procedure CollectClass(const ADeclType: TTSNode);
    function TypeKind(const AName: string): Integer;
    function IsInterfaceType(const AType: string): Boolean;
    function FieldOf(const AClass, AText: string; out AField: string): Boolean;
    function FileChain(const AName: string; out AChain: TArray<string>): Boolean;
    function LocalTypes(const ARoutine: TTSNode): TDictionary<string, string>;
    function OperandType(const ARoutine: TTSNode; const AOperand: TTSNode;
      const ALocals: TDictionary<string, string>): string;
    function Related(const ASub, ASuper: string): Integer;
    function IsHackOf(const AHack, AOther: string): Boolean;
    function IsCreateExpr(const N: TTSNode; out AClass: string; out AArgs: TArray<string>): Boolean;
    function ContainsRaisingCall(const N: TTSNode): Boolean;
    function StatementsOf(const N: TTSNode): TArray<TTSNode>;
    function TryParts(const ATry: TTSNode; out ATryStmts, AFinStmts: TArray<TTSNode>;
      out AIsFinally: Boolean): Boolean;
    function IsGuardedByIs(const N, AOperand: TTSNode; const AType: string): Boolean;
    procedure CheckCasts(const ARoutine: TTSNode);
    procedure CheckSelfInterface(const ARoutine: TTSNode);
    function SelfPassedAsInterface(const N: TTSNode; const ALocals: TDictionary<string, string>;
      const AClass: string): Boolean;
    function ParamIsInterfaceInAll(const ACallee: string; AIndex: Integer): Boolean;
    procedure CheckDestructors;
    procedure WalkCtorSeq(const AStmts: TArray<TTSNode>; const AClass: string; var ARaised: Boolean;
      ACond: Boolean; const ASuspect: TDictionary<string, string>; const ACreated: TDictionary<string, Boolean>);
    procedure CheckDtorRoutine(const ARoutine: TTSNode; const AClass: string;
      const ASuspect: TDictionary<string, string>; const AViaName: string);
    function GuardedInDtor(const ARoutine, AAccess: TTSNode; const AField: string): Boolean;
    procedure CheckFreeWithoutNil;
    function SetsFieldAfter(const AStmt: TTSNode; const ABody: TTSNode; const AClass, AField: string;
      const ASetters: TDictionary<string, Boolean>): Boolean;
    function StmtSetsField(const AStmt: TTSNode; const AClass, AField: string;
      const ASetters: TDictionary<string, Boolean>): Integer;
    function ExemptFreeRoutines(const AClass: string): TDictionary<string, Boolean>;
    procedure CheckOwnershipUnclear;
  public
    constructor Create(const ACtx: TV151FileCtx; const ASrc: TBytes; const ARoot: TTSNode);
    destructor Destroy; override;
    function Run: TArray<TLintFinding>;
  end;

function InList(const AValue: string; const AList: array of string): Boolean;
var
  S: string;
begin
  for S in AList do
    if S = AValue then Exit(True);
  Result:= False;
end;

{ 'TList<T>' -> 'tlist'; 'Unit.TFoo' -> 'tfoo'. }
function LeafType(const AName: string): string;
var
  P: Integer;
begin
  Result:= Trim(AName);
  P:= Pos('<', Result);
  if P > 0 then Result:= Copy(Result, 1, P - 1);
  P:= LastDelimiter('.', Result);
  if P > 0 then Result:= Copy(Result, P + 1, MaxInt);
  Result:= LowerCase(Trim(Result));
end;

{ An 'IFoo' style name: I followed by an upper-case letter. }
function LooksLikeInterfaceName(const AName: string): Boolean;
var
  S: string;
begin
  S:= Trim(AName);
  Result:= (Length(S) > 1) and (S[1] = 'I') and CharInSet(S[2], ['A'..'Z']);
end;

{ TTypClass }

constructor TTypClass.Create;
begin
  inherited Create;
  Fields   := TDictionary<string, string>.Create;
  FieldRaw := TDictionary<string, string>.Create;
  PrivMeths:= TDictionary<string, Boolean>.Create;
  TearDowns:= TDictionary<string, Boolean>.Create;
  PropWrite:= TDictionary<string, Boolean>.Create;
end;

destructor TTypClass.Destroy;
begin
  PropWrite.Free;
  TearDowns.Free;
  PrivMeths.Free;
  FieldRaw.Free;
  Fields.Free;
  inherited Destroy;
end;

{ TTypScan }

constructor TTypScan.Create(const ACtx: TV151FileCtx; const ASrc: TBytes; const ARoot: TTSNode);
begin
  inherited Create;
  FCtx     := ACtx;
  FSrc     := ASrc;
  FRoot    := ARoot;
  FFindings:= TList<TLintFinding>.Create;
  FEmitted := TDictionary<string, Boolean>.Create;
  FRoutines:= TList<TTSNode>.Create;
  FClasses := TObjectDictionary<string, TTypClass>.Create([doOwnsValues]);
  FIntfs   := TDictionary<string, Boolean>.Create;
  FKindMemo:= TDictionary<string, Integer>.Create;
  if (ACtx.Store <> nil) and (ACtx.FileId > 0) then
    FReader:= TExprTypeReader.Create(ACtx.Store, ACtx.LibStore, ACtx.FileId, ASrc);
end;

destructor TTypScan.Destroy;
begin
  FIdentIdx.Free;
  FReader.Free;
  FKindMemo.Free;
  FIntfs.Free;
  FClasses.Free;
  FRoutines.Free;
  FEmitted.Free;
  FFindings.Free;
  inherited Destroy;
end;

function TTypScan.NodeStr(const N: TTSNode): string;
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

{ Lower-case, blanks and line breaks removed, a leading 'self.' dropped. }
function TTypScan.Canon(const AText: string): string;
begin
  Result:= LowerCase(StringReplace(StringReplace(StringReplace(StringReplace(Trim(AText), ' ', '', [rfReplaceAll]),
    #13, '', [rfReplaceAll]), #10, '', [rfReplaceAll]), #9, '', [rfReplaceAll]));
  if StartsText('self.', Result) then Delete(Result, 1, Length('self.'));
end;

procedure TTypScan.GatherWalk(const N: TTSNode; AIsRoot: Boolean; const ATypes: array of string;
  const AList: TList<TTSNode>);
var
  I: Integer;
begin
  if N.IsNull then Exit;
  if (not AIsRoot) and ((N.NodeType = 'defProc') or (N.NodeType = 'lambda')) then Exit;
  if InList(N.NodeType, ATypes) then AList.Add(N);
  for I:= 0 to N.NamedChildCount - 1 do GatherWalk(N.NamedChild(I), False, ATypes, AList);
end;

{ Document order; a nested routine or anonymous method is not entered. }
procedure TTypScan.Gather(const ARoot: TTSNode; const ATypes: array of string; const AList: TList<TTSNode>);
begin
  GatherWalk(ARoot, True, ATypes, AList);
end;

procedure TTypScan.Emit(const ARule, ASeverity: string; const N: TTSNode; const AMsg, ASym: string);  // dl:ok duplicate-code@c2c1 -- REVIEWED 2026-11-14 v151 INT: same shape over different fields; a helper would need more parameters than it saves
var
  P, Q: TTSPoint;
  F   : TLintFinding;
  Key : string;
begin
  P:= N.StartPoint;
  Q:= N.EndPoint;
  Key:= Format('%s|%d|%d', [ARule, Integer(P.Row), Integer(P.Column)]);
  if FEmitted.ContainsKey(Key) then Exit;
  FEmitted.Add(Key, True);
  F:= Default(TLintFinding);
  F.RuleId    := ARule;
  F.Severity  := ASeverity;
  F.Message   := AMsg;
  F.FilePath  := FCtx.Path;
  F.StartLine := Integer(P.Row) + 1;
  F.StartCol  := TAstParseCache.CharCol(F.FilePath, P); { 1.52 BK-COLS2: character column }
  F.EndLine   := Integer(Q.Row) + 1;
  F.EndCol    := TAstParseCache.CharCol(F.FilePath, Q); { 1.52 BK-COLS2: character column }
  F.SymbolName:= ASym;
  FFindings.Add(F);
end;

function TTypScan.HasKeyword(const N: TTSNode; const AKind: string): Boolean;
var
  I: Integer;
begin
  Result:= False;
  if N.IsNull then Exit;
  for I:= 0 to N.ChildCount - 1 do
    if N.Child(I).NodeType = AKind then Exit(True);
end;

function TTypScan.ClassOf(const ARoutine: TTSNode): string;
var
  Nm: string;
  D : Integer;
begin
  Result:= '';
  Nm:= Trim(NodeStr(ARoutine.ChildByField('header').ChildByField('name')));
  D:= LastDelimiter('.', Nm);
  if D > 1 then Result:= LeafType(Copy(Nm, 1, D - 1));
end;

function TTypScan.MethodOf(const ARoutine: TTSNode): string;
var
  Nm: string;
begin
  Nm:= Trim(NodeStr(ARoutine.ChildByField('header').ChildByField('name')));
  Result:= LowerCase(Copy(Nm, LastDelimiter('.', Nm) + 1, MaxInt));
end;

function TTypScan.IsCtor(const ARoutine: TTSNode): Boolean;
begin
  Result:= HasKeyword(ARoutine.ChildByField('header'), 'kConstructor');
end;

function TTypScan.IsDtor(const ARoutine: TTSNode): Boolean;
begin
  Result:= HasKeyword(ARoutine.ChildByField('header'), 'kDestructor');
end;

function TTypScan.BodyOf(const ARoutine: TTSNode): TTSNode;
begin
  Result:= ARoutine.ChildByField('body');
end;

{ 'A, B: T;' -> a and b typed T (blanks removed); ARaw keeps each name as written. }
procedure TTypScan.ParseDecl(const AText: string; const AMap: TDictionary<string, string>;  // dl:ok duplicate-code@60de -- REVIEWED 2026-11-14 v151 INT: same shape over different fields; a helper would need more parameters than it saves
  const ARaw: TDictionary<string, string>);
var
  P, Cut  : Integer;
  Names, T: string;
  Nm      : string;
begin
  P:= Pos(':', AText);
  if P < 2 then Exit;
  Names:= Copy(AText, 1, P - 1);
  T:= Copy(AText, P + 1, MaxInt);
  Cut:= Pos(';', T);
  if Cut > 0 then T:= Copy(T, 1, Cut - 1);
  Cut:= Pos('=', T);
  if Cut > 0 then T:= Copy(T, 1, Cut - 1);
  T:= StringReplace(StringReplace(StringReplace(Trim(T), ' ', '', [rfReplaceAll]), #13, '', [rfReplaceAll]),
    #10, '', [rfReplaceAll]);
  for Nm in Names.Split([',']) do
  begin
    var Clean: string:= Trim(StringReplace(StringReplace(Nm, 'const ', '', [rfIgnoreCase]), 'var ', '', [rfIgnoreCase]));
    Clean:= Trim(StringReplace(Clean, 'out ', '', [rfIgnoreCase]));
    if (Clean = '') or Clean.Contains(' ') or Clean.Contains('[') then Continue;
    AMap.AddOrSetValue(LowerCase(Clean), T);
    if ARaw <> nil then ARaw.AddOrSetValue(LowerCase(Clean), Clean);
  end;
end;

procedure TTypScan.CollectClass(const ADeclType: TTSNode);  // dl:ok cyclomatic-complexity@0bb4, cognitive-complexity@ad2f -- REVIEWED 2026-11-13 v151 TYP: one pass over a class declaration, one branch per member kind; splitting it scatters the member bookkeeping
var
  TyNode, Cls, K, S: TTSNode;
  C                : TTypClass;
  I, J             : Integer;
  Members          : TList<TTSNode>;
  Txt, Lo          : string;
  IsPriv           : Boolean;
begin
  TyNode:= ADeclType.ChildByField('type');
  Cls:= TyNode;
  if (not Cls.IsNull) and (Cls.NodeType = 'type') and (Cls.NamedChildCount > 0) then Cls:= Cls.NamedChild(0);
  if Cls.IsNull then Exit;
  if Cls.NodeType = 'declIntf' then
  begin
    FIntfs.AddOrSetValue(LeafType(NodeStr(ADeclType.ChildByField('name'))), True);
    Exit;
  end;
  if Cls.NodeType <> 'declClass' then Exit;
  C:= TTypClass.Create;
  C.RawName := Trim(NodeStr(ADeclType.ChildByField('name')));
  C.Name    := LeafType(C.RawName);
  C.IsRecord:= HasKeyword(Cls, 'kRecord') or HasKeyword(Cls, 'kObject');
  for I:= 0 to Cls.NamedChildCount - 1 do
    if (Cls.NamedChild(I).NodeType = 'typeref') and (C.Parent = '') then
      C.Parent:= LeafType(NodeStr(Cls.NamedChild(I)));
  { A first heritage entry that is an interface means the parent is TObject. }
  if (C.Parent <> '') and (FIntfs.ContainsKey(C.Parent) or (C.Parent = 'iinterface') or (C.Parent = 'iunknown')) then
    C.Parent:= '';
  if C.Parent = 'tobject' then C.Parent:= '';
  Members:= TList<TTSNode>.Create;
  try
    { Sections: a member's visibility is the declSection it sits in. }
    for I:= 0 to Cls.NamedChildCount - 1 do
    begin
      S:= Cls.NamedChild(I);
      IsPriv:= (S.NodeType = 'declSection') and HasKeyword(S, 'kPrivate');
      Members.Clear;
      if S.NodeType = 'declSection' then
        for J:= 0 to S.NamedChildCount - 1 do Members.Add(S.NamedChild(J))
      else
        Members.Add(S);
      for K in Members do
      begin
        if K.NodeType = 'declField' then
        begin
          C.HasFields:= True;
          ParseDecl(NodeStr(K), C.Fields, C.FieldRaw);
        end
        else if (K.NodeType = 'declFields') or (K.NodeType = 'declVars') then
        begin
          for J:= 0 to K.NamedChildCount - 1 do
            if K.NamedChild(J).NodeType = 'declField' then
            begin
              C.HasFields:= True;
              ParseDecl(NodeStr(K.NamedChild(J)), C.Fields, C.FieldRaw);
            end;
        end
        else if K.NodeType = 'declProc' then
        begin
          Txt:= NodeStr(K);
          Lo:= LowerCase(Txt);
          var Nm: string:= LowerCase(Trim(NodeStr(K.ChildByField('name'))));
          if ContainsText(Lo, 'virtual') or ContainsText(Lo, 'dynamic') or ContainsText(Lo, 'abstract') or
             ContainsText(Lo, 'message') then
            C.HasVirtual:= True;
          if Nm = 'newinstance' then C.HasNewInst:= True;
          if Nm = '_release' then C.DeclRelease:= True;
          if IsPriv and (Nm <> '') then C.PrivMeths.AddOrSetValue(Nm, True);
          if (Nm <> '') and (ContainsText(Lo, '[teardown]') or ContainsText(Lo, '[teardownfixture]')) then
            C.TearDowns.AddOrSetValue(Nm, True);
        end
        else if K.NodeType = 'declProp' then
        begin
          var Setter: TTSNode:= K.ChildByField('setter');
          if not Setter.IsNull then C.PropWrite.AddOrSetValue(LowerCase(Trim(NodeStr(Setter))), True);
        end;
      end;
    end;
  finally
    Members.Free;
  end;
  { An attribute line before a declaration parses as its own sibling in some
    grammar versions: look at the raw class text as well. }
  Txt:= NodeStr(Cls);
  for Lo in Txt.Split([#10]) do
    if ContainsText(Lo, '[TearDown') then
    begin
      var Idx: Integer:= Txt.IndexOf(Lo);
      var Rest: string:= Copy(Txt, Idx + Length(Lo) + 1, ATTR_LOOKAHEAD);
      var Words: TArray<string>:= Rest.Split([' ', #13, #10, '(', ';', ':'], TStringSplitOptions.ExcludeEmpty);
      for J:= 0 to Length(Words) - 2 do
        if SameText(Words[J], 'procedure') or SameText(Words[J], 'function') then
        begin
          C.TearDowns.AddOrSetValue(LowerCase(Words[J + 1]), True);
          Break;
        end;
    end;
  FClasses.AddOrSetValue(C.Name, C);
end;

procedure TTypScan.CollectClasses;
var
  L: TList<TTSNode>;
  N: TTSNode;
begin
  L:= TList<TTSNode>.Create;
  try
    Gather(FRoot, ['declType'], L);
    { interfaces first: a class heritage list may name them }
    for N in L do
    begin
      var Ty: TTSNode:= N.ChildByField('type');
      if (not Ty.IsNull) and (Ty.NodeType = 'type') and (Ty.NamedChildCount > 0) then Ty:= Ty.NamedChild(0);
      if (not Ty.IsNull) and (Ty.NodeType = 'declIntf') then
        FIntfs.AddOrSetValue(LeafType(NodeStr(N.ChildByField('name'))), True);
    end;
    for N in L do CollectClass(N);
  finally
    L.Free;
  end;
end;

{ 1 = class, 2 = interface, 0 = something else or unknown. The unit's own
  declarations first; then the project index, then the library index: every
  type symbol of that name must agree. }
function TTypScan.TypeKind(const AName: string): Integer;
var
  Leaf : string;
  Store: ISymbolStore;
  S    : TSymbol;
  K    : Integer;
begin
  Leaf:= LeafType(AName);
  if Leaf = '' then Exit(0);
  if FKindMemo.TryGetValue(Leaf, Result) then Exit;
  Result:= 0;
  var Cl: TTypClass;
  if FClasses.TryGetValue(Leaf, Cl) then
    Result:= if Cl.IsRecord then 0 else 1
  else if FIntfs.ContainsKey(Leaf) then
    Result:= 2
  else
    for Store in TArray<ISymbolStore>.Create(FCtx.Store, FCtx.LibStore) do
    begin
      if Store = nil then Continue;
      K:= -1;
      for S in Store.FindSymbolsByExactName(Leaf) do
      begin
        if S.Kind not in [skClass, skInterface, skRecord, skEnum, skTypeAlias] then Continue;
        var Ki: Integer:= if S.Kind = skClass then 1 else if S.Kind = skInterface then 2 else 0;
        if K = -1 then K:= Ki
        else if K <> Ki then K:= 0;
      end;
      if K <> -1 then
      begin
        Result:= K;
        Break;
      end;
    end;
  FKindMemo.AddOrSetValue(Leaf, Result);
end;

function TTypScan.IsInterfaceType(const AType: string): Boolean;
var
  K: Integer;
begin
  K:= TypeKind(AType);
  if K <> 0 then Exit(K = 2);
  { the I-prefix test needs the name's own case: LeafType lower-cases it }
  var Raw: string:= Trim(AType);
  if Raw.Contains('<') then Raw:= Copy(Raw, 1, Pos('<', Raw) - 1);
  Raw:= Copy(Raw, LastDelimiter('.', Raw) + 1, MaxInt);
  Result:= LooksLikeInterfaceName(Raw) and not FClasses.ContainsKey(LeafType(AType));
end;

{ AText ('FFoo' / 'Self.FFoo', any case) names a field of AClass declared in this unit. }
function TTypScan.FieldOf(const AClass, AText: string; out AField: string): Boolean;
var
  C: TTypClass;
begin
  AField:= Canon(AText);
  Result:= (AClass <> '') and FClasses.TryGetValue(AClass, C) and C.Fields.ContainsKey(AField);
end;

{ The class chain of AName within the unit: [AName, parent, ...]. True only when
  every link is declared here and the top one descends straight from TObject. }
function TTypScan.FileChain(const AName: string; out AChain: TArray<string>): Boolean;
var
  Cur: string;
  C  : TTypClass;
begin
  AChain:= nil;
  Cur:= LeafType(AName);
  while Length(AChain) < MAX_CHAIN do
  begin
    if Cur = 'tobject' then Exit(True);
    if not FClasses.TryGetValue(Cur, C) then Exit(False);
    if C.IsRecord then Exit(False);
    AChain:= AChain + [Cur];
    if C.Parent = '' then Exit(True);
    Cur:= C.Parent;
  end;
  Result:= False;
end;

{ Locals and parameters of ARoutine, lower name -> type text. Caller frees. }
function TTypScan.LocalTypes(const ARoutine: TTSNode): TDictionary<string, string>;
var
  L   : TList<TTSNode>;
  N   : TTSNode;
  Args: TTSNode;
  J   : Integer;
begin
  Result:= TDictionary<string, string>.Create;
  L:= TList<TTSNode>.Create;
  try
    for J:= 0 to ARoutine.NamedChildCount - 1 do
      if ARoutine.NamedChild(J).NodeType = 'declVars' then Gather(ARoutine.NamedChild(J), ['declVar'], L);
    Gather(BodyOf(ARoutine), ['varDef'], L);
    for N in L do ParseDecl(NodeStr(N).Replace('var ', '', [rfIgnoreCase]), Result, nil);
  finally
    L.Free;
  end;
  Args:= ARoutine.ChildByField('header').ChildByField('args');
  if not Args.IsNull then
    for J:= 0 to Args.NamedChildCount - 1 do
      if Args.NamedChild(J).NodeType = 'declArg' then ParseDecl(NodeStr(Args.NamedChild(J)), Result, nil);
end;

{ Static type of a cast operand: the index (ref_types) when it answers, else the
  unit's own declarations (locals, parameters, fields of the method's class and its
  in-unit ancestors, Self). '' = unknown. }
function TTypScan.OperandType(const ARoutine: TTSNode; const AOperand: TTSNode;
  const ALocals: TDictionary<string, string>): string;
var
  Leaf, Nm, Cls: string;
  C            : TTypClass;
  Guard        : Integer;
begin
  Result:= '';
  if (FReader <> nil) and FReader.Ready and FReader.TypeLeafOf(AOperand, Leaf) then Exit(LeafType(Leaf));
  if AOperand.NodeType <> 'identifier' then
  begin
    if (AOperand.NodeType = 'exprDot') and SameText(Trim(NodeStr(AOperand.ChildByField('lhs'))), 'self') then
      Nm:= LowerCase(Trim(NodeStr(AOperand.ChildByField('rhs'))))
    else
      Exit;
  end
  else
    Nm:= LowerCase(Trim(NodeStr(AOperand)));
  Cls:= ClassOf(ARoutine);
  if Nm = 'self' then Exit(Cls);
  if ALocals.TryGetValue(Nm, Result) then Exit(LeafType(Result));
  Guard:= 0;
  while (Cls <> '') and FClasses.TryGetValue(Cls, C) and (Guard < MAX_CHAIN) do
  begin
    if C.Fields.TryGetValue(Nm, Result) then Exit(LeafType(Result));
    Cls:= C.Parent;
    Inc(Guard);
  end;
  Result:= '';
end;

{ Does ASub descend from (or equal) ASuper? 1 yes, 0 no, -1 unknown. The unit's
  own declarations decide when both chains stay in the unit; else the index. }
function TTypScan.Related(const ASub, ASuper: string): Integer;
var
  ChS, ChP: TArray<string>;
  S       : string;
begin
  if ASub = ASuper then Exit(1);
  if ASuper = 'tobject' then Exit(1);
  if FileChain(ASub, ChS) then
  begin
    for S in ChS do
      if S = ASuper then Exit(1);
    if FileChain(ASuper, ChP) then Exit(0);
  end;
  Result:= -1;
  if (FReader <> nil) and FReader.Ready then
    case FReader.Descends(ASub, ASuper) of
      tdYes: Result:= 1;
      tdNo : Result:= 0;
    end;
end;

{ The accessor-class trick: AHack (and every in-unit class between it and a class
  AOther descends from) declares no field and no virtual method, so the object
  layout is that common ancestor's and the cast reads nothing foreign. }
function TTypScan.IsHackOf(const AHack, AOther: string): Boolean;
var
  Cur  : string;
  C    : TTypClass;
  Guard: Integer;
begin
  Result:= False;
  Cur:= AHack;
  Guard:= 0;
  while FClasses.TryGetValue(Cur, C) and (Guard < MAX_CHAIN) do
  begin
    if C.HasFields or C.HasVirtual then Exit;
    Cur:= if C.Parent = '' then 'tobject' else C.Parent;
    if Related(AOther, Cur) = 1 then Exit(True);
    Inc(Guard);
  end;
end;

{ 'TFoo.Create' / 'TFoo.Create(args)' / 'TList<T>.Create': AClass = 'tfoo'. }
function TTypScan.IsCreateExpr(const N: TTSNode; out AClass: string; out AArgs: TArray<string>): Boolean;
var
  Ent, Args: TTSNode;
  C        : string;
  I        : Integer;
begin
  AArgs:= nil;
  AClass:= '';
  Result:= False;
  if N.IsNull then Exit;
  Ent:= N;
  Args:= Default(TTSNode);
  if N.NodeType = 'exprCall' then
  begin
    Ent:= N.ChildByField('entity');
    Args:= N.ChildByField('args');
  end;
  if Ent.NodeType <> 'exprDot' then Exit;
  C:= Canon(NodeStr(Ent));
  if not EndsText('.create', C) then Exit;
  C:= Copy(C, 1, Length(C) - Length('.create'));
  C:= LeafType(C);
  if (Length(C) < 2) or (C[1] <> 't') then Exit;
  AClass:= C;
  Result:= True;
  if Args.IsNull then Exit;
  SetLength(AArgs, Args.NamedChildCount);
  for I:= 0 to Args.NamedChildCount - 1 do AArgs[I]:= Canon(NodeStr(Args.NamedChild(I)));
end;

{ Can evaluating N raise? Any call except inherited, the safe RTL calls, casts to a
  type, and the creation of a raising-free RTL class. }
function TTypScan.ContainsRaisingCall(const N: TTSNode): Boolean;  // dl:ok too-many-exit-points@8d4a -- REVIEWED 2026-11-13 v151 TYP: guard clauses, each one a call shape that can or cannot raise
var
  L   : TList<TTSNode>;
  K   : TTSNode;
  Cls : string;
  Args: TArray<string>;
  Nm  : string;
begin
  Result:= False;
  if N.IsNull then Exit;
  if (N.NodeType = 'statement') and (N.NamedChildCount = 1) then
  begin
    K:= N.NamedChild(0);
    if K.NodeType = 'inherited' then Exit(False);
    if (K.NodeType = 'identifier') or (K.NodeType = 'exprDot') then
    begin
      Nm:= Canon(NodeStr(K));
      if (Nm <> 'exit') and (Nm <> 'break') and (Nm <> 'continue') then Exit(True);
    end;
  end;
  L:= TList<TTSNode>.Create;
  try
    Gather(N, ['exprCall', 'raise'], L);
    for K in L do
    begin
      if K.NodeType = 'raise' then Exit(True);
      if IsCreateExpr(K, Cls, Args) then
      begin
        if InList(Cls, SAFE_CREATE) then Continue;
        Exit(True);
      end;
      var Ent: TTSNode:= K.ChildByField('entity');
      if Ent.NodeType = 'inherited' then Continue;
      Nm:= Canon(NodeStr(Ent));
      if InList(Nm, SAFE_CALLS) then Continue;
      if (Ent.NodeType = 'identifier') and (TypeKind(Nm) <> 0) then Continue; { a type cast }
      Exit(True);
    end;
  finally
    L.Free;
  end;
end;

{ The statement nodes directly inside a block / statements list / try part. }
function TTypScan.StatementsOf(const N: TTSNode): TArray<TTSNode>;
var
  I: Integer;
  K: TTSNode;
begin
  Result:= nil;
  if N.IsNull then Exit;
  for I:= 0 to N.NamedChildCount - 1 do
  begin
    K:= N.NamedChild(I);
    if K.NodeType = 'statements' then Result:= Result + StatementsOf(K)
    else if (K.NodeType <> 'kBegin') and (K.NodeType <> 'kEnd') and (K.NodeType <> 'label') then Result:= Result + [K];
  end;
end;

{ A try statement split at except / finally. }
function TTypScan.TryParts(const ATry: TTSNode; out ATryStmts, AFinStmts: TArray<TTSNode>;
  out AIsFinally: Boolean): Boolean;
var
  I    : Integer;
  K    : TTSNode;
  Phase: Integer;
begin
  ATryStmts:= nil;
  AFinStmts:= nil;
  AIsFinally:= False;
  Result:= ATry.NodeType = 'try';
  if not Result then Exit;
  Phase:= 0;
  for I:= 0 to ATry.ChildCount - 1 do
  begin
    K:= ATry.Child(I);
    if K.NodeType = 'kTry' then Phase:= PH_TRY
    else if K.NodeType = 'kExcept' then Phase:= PH_EXCEPT
    else if K.NodeType = 'kFinally' then
    begin
      Phase:= PH_FINALLY;
      AIsFinally:= True;
    end
    else if K.NodeType = 'statements' then
    begin
      if Phase = PH_TRY then ATryStmts:= ATryStmts + StatementsOf(K)
      else if Phase = PH_FINALLY then AFinStmts:= AFinStmts + StatementsOf(K);
    end
    else if K.IsNamed and (K.NodeType <> 'kEnd') and (Phase = PH_TRY) then ATryStmts:= ATryStmts + [K]
    else if K.IsNamed and (K.NodeType <> 'kEnd') and (Phase = PH_FINALLY) then AFinStmts:= AFinStmts + [K];
  end;
end;

{ ---- unrelated-class-cast -------------------------------------------------- }

{ Is N inside an if / ifElse whose condition holds "<operand> is <AType>"? The `is` test of the
  same type makes the hard cast safe (Y7). }
function TTypScan.IsGuardedByIs(const N, AOperand: TTSNode; const AType: string): Boolean;
var
  P, Cond, B: TTSNode;
  Bins      : TList<TTSNode>;
  Opd       : string;
begin
  Result:= False;
  Opd:= LowerCase(Trim(NodeStr(AOperand)));
  P:= N.Parent;
  while not P.IsNull do
  begin
    if (P.NodeType = 'if') or (P.NodeType = 'ifElse') then
    begin
      Cond:= P.ChildByField('condition');
      Bins:= TList<TTSNode>.Create;
      try
        if not Cond.IsNull then Gather(Cond, ['exprBinary'], Bins);
        for B in Bins do
          if SameText(Trim(NodeStr(B.ChildByField('operator'))), 'is')
             and (LowerCase(Trim(NodeStr(B.ChildByField('lhs')))) = Opd)
             and (LeafType(NodeStr(B.ChildByField('rhs'))) = AType) then Exit(True);
      finally
        Bins.Free;
      end;
    end;
    P:= P.Parent;
  end;
end;

procedure TTypScan.CheckCasts(const ARoutine: TTSNode);
var
  Calls : TList<TTSNode>;
  N, Ent: TTSNode;
  Args  : TTSNode;
  Locals: TDictionary<string, string>;
  T, S  : string;
begin
  Calls:= TList<TTSNode>.Create;
  Locals:= nil;
  try
    Gather(BodyOf(ARoutine), ['exprCall'], Calls);
    for N in Calls do
    begin
      Ent:= N.ChildByField('entity');
      if Ent.NodeType <> 'identifier' then Continue;
      Args:= N.ChildByField('args');
      if Args.IsNull or (Args.NamedChildCount <> 1) then Continue;
      T:= LeafType(NodeStr(Ent));
      if (T = 'tobject') or (TypeKind(T) <> 1) then Continue;
      if Locals = nil then Locals:= LocalTypes(ARoutine);
      S:= OperandType(ARoutine, Args.NamedChild(0), Locals);
      if (S = '') or (S = T) or (S = 'tobject') or (TypeKind(S) <> 1) then Continue;
      if (Related(S, T) <> 0) or (Related(T, S) <> 0) then Continue;
      if IsHackOf(T, S) or IsHackOf(S, T) then Continue;
      if IsGuardedByIs(N, Args.NamedChild(0), T) then Continue;
      Emit(RULE_UNRELATED_CAST, 'warning', N,
        Format('%s(%s) casts a %s to %s, but neither class descends from the other -- the object is read with a ' +
          'foreign layout; check the type with "as" or "is", or fix the variable''s type',
          [Trim(NodeStr(Ent)), Trim(NodeStr(Args.NamedChild(0))), S, Trim(NodeStr(Ent))]), T);
    end;
  finally
    Locals.Free;
    Calls.Free;
  end;
end;

{ ---- self-as-interface-in-constructor ------------------------------------- }

{ Every known declaration named like ACallee's last segment takes an interface at
  parameter AIndex (0-based). No declaration found = False. }
function TTypScan.ParamIsInterfaceInAll(const ACallee: string; AIndex: Integer): Boolean;
var
  Nm   : string;
  Store: ISymbolStore;
  S    : TSymbol;
  Found: Integer;

  function SigParamType(const ASig: string; out AType: string): Boolean;
  var
    Inner: string;
    P, Q : Integer;
    Parts: TArray<string>;
    Part : string;
    Idx  : Integer;
  begin
    Result:= False;
    AType:= '';
    P:= Pos('(', ASig);
    Q:= Pos(')', ASig);
    if (P = 0) or (Q < P) then Exit;
    Inner:= Copy(ASig, P + 1, Q - P - 1);
    Parts:= Inner.Split([';']);
    Idx:= 0;
    for Part in Parts do
    begin
      var Colon: Integer:= Pos(':', Part);
      var NamePart: string:= if Colon > 0 then Copy(Part, 1, Colon - 1) else Part;
      var Names: TArray<string>:= NamePart.Split([',']);
      var Ty: string:= if Colon > 0 then Copy(Part, Colon + 1, MaxInt) else '';
      if Ty.Contains('=') then Ty:= Copy(Ty, 1, Pos('=', Ty) - 1);
      if (AIndex >= Idx) and (AIndex < Idx + Length(Names)) then
      begin
        AType:= Trim(Ty);
        Exit(AType <> '');
      end;
      Inc(Idx, Length(Names));
    end;
  end;

  function Check(const ASig: string): Boolean;
  var
    Ty: string;
  begin
    Inc(Found);
    Result:= SigParamType(ASig, Ty) and IsInterfaceType(Ty);
  end;

var
  L: TList<TTSNode>;
  D: TTSNode;
begin
  Result:= False;
  Found:= 0;
  Nm:= LowerCase(Copy(ACallee, LastDelimiter('.', ACallee) + 1, MaxInt));
  if Nm = '' then Exit;
  L:= TList<TTSNode>.Create;
  try
    GatherWalk(FRoot, True, ['declProc'], L);
    for D in L do
      if (SameText(Trim(NodeStr(D.ChildByField('name'))), Nm) or
          EndsText('.' + Nm, Trim(NodeStr(D.ChildByField('name'))))) and not Check(NodeStr(D)) then
        Exit(False);
  finally
    L.Free;
  end;
  for Store in TArray<ISymbolStore>.Create(FCtx.Store, FCtx.LibStore) do
  begin
    if Store = nil then Continue;
    for S in Store.FindSymbolsByExactName(Nm) do
      if (S.Kind in [skMethod, skProcedure, skFunction, skConstructor]) and not Check(S.Signature) then
        Exit(False);
  end;
  Result:= Found > 0;
end;

{ Does N hand Self out as an interface? `Self as IX`, `IX(Self)`, `X := Self`
  with X an interface, or Self as an argument whose parameter is an interface in
  every known declaration of the callee. }
function TTypScan.SelfPassedAsInterface(const N: TTSNode; const ALocals: TDictionary<string, string>;
  const AClass: string): Boolean;
var
  L   : TList<TTSNode>;
  K   : TTSNode;
  Args: TTSNode;
  I   : Integer;
  Ty  : string;
  C   : TTypClass;
begin
  Result:= False;
  L:= TList<TTSNode>.Create;
  try
    Gather(N, ['exprAs', 'exprBinary', 'exprCall', 'assignment'], L);
    for K in L do
    begin
      if (K.NodeType = 'exprAs') or (K.NodeType = 'exprBinary') then
      begin
        if (K.NamedChildCount >= INFIX_KIDS) and SameText(Trim(NodeStr(K.NamedChild(0))), 'self') and
           (K.NamedChild(1).NodeType = 'kAs') and IsInterfaceType(NodeStr(K.NamedChild(2))) then
          Exit(True);
      end
      else if K.NodeType = 'assignment' then
      begin
        if Canon(NodeStr(K.ChildByField('rhs'))) <> 'self' then Continue;
        var Lhs: string:= Canon(NodeStr(K.ChildByField('lhs')));
        Ty:= '';
        if (not ALocals.TryGetValue(Lhs, Ty)) and FClasses.TryGetValue(AClass, C) then
          C.Fields.TryGetValue(Lhs, Ty);
        if (Ty <> '') and IsInterfaceType(Ty) then Exit(True);
      end
      else
      begin
        Args:= K.ChildByField('args');
        if Args.IsNull then Continue;
        var Ent: TTSNode:= K.ChildByField('entity');
        if (Ent.NodeType = 'identifier') and (Args.NamedChildCount = 1) and
           SameText(Trim(NodeStr(Args.NamedChild(0))), 'self') and IsInterfaceType(NodeStr(Ent)) then
          Exit(True);
        if Ent.NodeType = 'inherited' then Continue;
        for I:= 0 to Args.NamedChildCount - 1 do
          if SameText(Trim(NodeStr(Args.NamedChild(I))), 'self') and
             ParamIsInterfaceInAll(Trim(NodeStr(Ent)), I) then
            Exit(True);
      end;
    end;
  finally
    L.Free;
  end;
end;

procedure TTypScan.CheckSelfInterface(const ARoutine: TTSNode);
var
  Cls, Meth : string;
  Chain     : TArray<string>;
  C         : TTypClass;
  OwnCount  : Boolean;
  Interfaced: Boolean;
  Stmts     : TArray<TTSNode>;
  St        : TTSNode;
  AfterInh  : Boolean;
  Locals    : TDictionary<string, string>;
  S         : string;
begin
  Cls:= ClassOf(ARoutine);
  if Cls = '' then Exit;
  Meth:= MethodOf(ARoutine);
  if not (IsCtor(ARoutine) or (Meth = 'afterconstruction')) then Exit;
  { Case 1: the unit's own reference counting -- a _Release in the chain, no
    NewInstance anywhere in it, the whole chain declared here. }
  OwnCount:= False;
  if FileChain(Cls, Chain) then
  begin
    for S in Chain do
      if FClasses.TryGetValue(S, C) then
      begin
        if C.HasNewInst then
        begin
          OwnCount:= False;
          Break;
        end;
        if C.DeclRelease then
          for var Rr: TTSNode in FRoutines do
            if (ClassOf(Rr) = S) and (MethodOf(Rr) = '_release') then
            begin
              var Body: string:= LowerCase(NodeStr(BodyOf(Rr)));
              if ContainsStr(Body, 'destroy') or ContainsStr(Body, '.free') or ContainsStr(Body, 'free;') then
                OwnCount:= True;
            end;
      end;
  end;
  { Case 2: a TInterfacedObject descendant after inherited AfterConstruction. }
  if not OwnCount then
  begin
    if Meth <> 'afterconstruction' then Exit;
    Interfaced:= Related(Cls, 'tinterfacedobject') = 1;
    if not Interfaced then
    begin
      { an in-unit chain that leaves the unit at TInterfacedObject }
      S:= Cls;
      var Guard: Integer:= 0;
      while FClasses.TryGetValue(S, C) and (Guard < MAX_CHAIN) do
      begin
        if C.HasNewInst then Break;
        if C.Parent = 'tinterfacedobject' then
        begin
          Interfaced:= True;
          Break;
        end;
        S:= C.Parent;
        Inc(Guard);
      end;
    end;
    if not Interfaced then Exit;
  end;
  Locals:= LocalTypes(ARoutine);
  try
    Stmts:= StatementsOf(BodyOf(ARoutine));
    AfterInh:= OwnCount;
    for St in Stmts do
    begin
      if (not AfterInh) and StartsText('inherited', Canon(NodeStr(St))) then
      begin
        AfterInh:= True;
        Continue;
      end;
      if not AfterInh then Continue;
      if SelfPassedAsInterface(St, Locals, Cls) then
        if OwnCount then
          Emit(RULE_SELF_INTF_CTOR, 'warning', St,
            Format('Self is handed out as an interface while %s is still being constructed -- its own reference ' +
              'counting goes from 0 to 1 and back to 0 and frees the object before construction ends; hold a ' +
              'reference first or pass Self after construction', [ClassOf(ARoutine)]), Cls)
        else
          Emit(RULE_SELF_INTF_CTOR, 'warning', St,
            Format('Self is handed out as an interface after inherited AfterConstruction in %s -- the protective ' +
              'reference count is already gone, so the release at the end of the call can free the object; move ' +
              'this statement before inherited', [ClassOf(ARoutine)]), Cls);
    end;
  finally
    Locals.Free;
  end;
end;

{ ---- destructor-not-nil-safe ---------------------------------------------- }

{ Walks a constructor's statements in order. ARaised = a call that can raise has
  run before; ACond = the statements run only on some paths. A field created when
  either holds goes to ASuspect (field -> what made it uncertain). }
procedure TTypScan.WalkCtorSeq(const AStmts: TArray<TTSNode>; const AClass: string; var ARaised: Boolean;
  ACond: Boolean; const ASuspect: TDictionary<string, string>; const ACreated: TDictionary<string, Boolean>);
var
  St       : TTSNode;
  Fld, Cls : string;
  Args     : TArray<string>;
  TryS, Fin: TArray<TTSNode>;
  IsFin    : Boolean;
  Inner    : TList<TTSNode>;
  A        : TTSNode;
  Ty       : string;
  C        : TTypClass;
begin
  if not FClasses.TryGetValue(AClass, C) then Exit;
  for St in AStmts do
  begin
    if St.NodeType = 'assignment' then
    begin
      if FieldOf(AClass, NodeStr(St.ChildByField('lhs')), Fld) and IsCreateExpr(St.ChildByField('rhs'), Cls, Args) then
      begin
        Ty:= '';
        C.Fields.TryGetValue(Fld, Ty);
        if not IsInterfaceType(Ty) then
        begin
          if ACond and not ACreated.ContainsKey(Fld) then
            ASuspect.AddOrSetValue(Fld, 'is created only on some paths of the constructor')
          else if ARaised and not ACreated.ContainsKey(Fld) then
            ASuspect.AddOrSetValue(Fld, 'is created after a call that can raise');
          ACreated.AddOrSetValue(Fld, True);
        end;
      end;
      if ContainsRaisingCall(St.ChildByField('rhs')) then ARaised:= True;
      Continue;
    end;
    if St.NodeType = 'block' then
    begin
      WalkCtorSeq(StatementsOf(St), AClass, ARaised, ACond, ASuspect, ACreated);
      Continue;
    end;
    if TryParts(St, TryS, Fin, IsFin) then
    begin
      WalkCtorSeq(TryS, AClass, ARaised, ACond, ASuspect, ACreated);
      if IsFin then WalkCtorSeq(Fin, AClass, ARaised, ACond, ASuspect, ACreated)
      else ARaised:= True; { a handler that swallows: anything after it may follow a failure }
      Continue;
    end;
    if (St.NodeType = 'statement') then
    begin
      if ContainsRaisingCall(St) then ARaised:= True;
      Continue;
    end;
    { if / case / loops / with: creations inside are conditional, unless an
      if-else creates the same field in both branches. }
    Inner:= TList<TTSNode>.Create;
    try
      if St.NodeType = 'ifElse' then
      begin
        var InThen: TDictionary<string, Boolean>:= TDictionary<string, Boolean>.Create;
        var Both  : TDictionary<string, Boolean>:= TDictionary<string, Boolean>.Create;
        try
          Gather(St.ChildByField('then'), ['assignment'], Inner);
          for A in Inner do
            if FieldOf(AClass, NodeStr(A.ChildByField('lhs')), Fld) and IsCreateExpr(A.ChildByField('rhs'), Cls, Args) then
              InThen.AddOrSetValue(Fld, True);
          Inner.Clear;
          Gather(St.ChildByField('else'), ['assignment'], Inner);
          for A in Inner do
            if FieldOf(AClass, NodeStr(A.ChildByField('lhs')), Fld) and InThen.ContainsKey(Fld) and
               IsCreateExpr(A.ChildByField('rhs'), Cls, Args) then
              Both.AddOrSetValue(Fld, True);
          for Fld in Both.Keys do
          begin
            if ARaised and not ACreated.ContainsKey(Fld) then
              ASuspect.AddOrSetValue(Fld, 'is created after a call that can raise');
            ACreated.AddOrSetValue(Fld, True);
          end;
        finally
          Both.Free;
          InThen.Free;
        end;
        Inner.Clear;
      end;
      Gather(St, ['assignment'], Inner);
      for A in Inner do
        if FieldOf(AClass, NodeStr(A.ChildByField('lhs')), Fld) and (not ACreated.ContainsKey(Fld)) and
           IsCreateExpr(A.ChildByField('rhs'), Cls, Args) then
        begin
          Ty:= '';
          C.Fields.TryGetValue(Fld, Ty);
          if not IsInterfaceType(Ty) then
            ASuspect.AddOrSetValue(Fld, 'is created only on some paths of the constructor');
        end;
    finally
      Inner.Free;
    end;
    if ContainsRaisingCall(St) then ARaised:= True;
  end;
end;

{ Is the access AAccess to AField inside the destructor protected by a nil test:
  an enclosing `if Assigned(F)` / `if F <> nil`, or an earlier statement that
  tests F against nil (`if F = nil then Exit`)? }
function TTypScan.GuardedInDtor(const ARoutine, AAccess: TTSNode; const AField: string): Boolean;
var
  L   : TList<TTSNode>;
  N   : TTSNode;
  Cond: string;
begin
  Result:= False;
  L:= TList<TTSNode>.Create;
  try
    Gather(BodyOf(ARoutine), ['if', 'ifElse', 'while', 'exprBinary'], L);
    for N in L do
    begin
      if N.StartByte > AAccess.StartByte then Continue;
      if N.NodeType = 'exprBinary' then
      begin
        { `Assigned(F) and F.X` / `(F <> nil) and F.X`: short-circuit guard }
        if (N.EndByte < AAccess.EndByte) then Continue;
        if not SameText(Trim(NodeStr(N.ChildByField('operator'))), 'and') then Continue;
        Cond:= Canon(NodeStr(N.ChildByField('lhs')));
      end
      else
        Cond:= Canon(NodeStr(N.ChildByField('condition')));
      if ContainsStr(Cond, 'assigned(' + AField + ')') or ContainsStr(Cond, 'assigned(self.' + AField + ')') or  // dl:ok boolean-expression-complexity@cd56 -- REVIEWED 2026-11-13 v151 TYP: the six spellings of a nil test of one field; naming each adds nothing
         ContainsStr(Cond, AField + '<>nil') or ContainsStr(Cond, AField + '=nil') or
         ContainsStr(Cond, 'nil<>' + AField) or ContainsStr(Cond, 'nil=' + AField) then
        Exit(True);
    end;
  finally
    L.Free;
  end;
end;

procedure TTypScan.CheckDtorRoutine(const ARoutine: TTSNode; const AClass: string;
  const ASuspect: TDictionary<string, string>; const AViaName: string);
var
  L     : TList<TTSNode>;
  N, Lhs: TTSNode;
  Fld   : string;
  Why   : string;
  Rhs   : string;
  C     : TTypClass;
begin
  if not FClasses.TryGetValue(AClass, C) then Exit;
  L:= TList<TTSNode>.Create;
  try
    Gather(BodyOf(ARoutine), ['exprDot', 'exprSubscript'], L);
    for N in L do
    begin
      Lhs:= if N.NodeType = 'exprDot' then N.ChildByField('lhs') else N.ChildByField('entity');
      if Lhs.IsNull then Continue;
      if not FieldOf(AClass, NodeStr(Lhs), Fld) then Continue;
      if not ASuspect.TryGetValue(Fld, Why) then Continue;
      if N.NodeType = 'exprDot' then
      begin
        Rhs:= LowerCase(Trim(NodeStr(N.ChildByField('rhs'))));
        if (Rhs = 'free') or (Rhs = 'disposeof') then Continue;
      end;
      if GuardedInDtor(ARoutine, N, Fld) then Continue;
      var Msg: string:= Format('%s %s, so when a constructor raises it is still nil while the destructor runs -- ' +
        '%s then raises an access violation that hides the first exception; test it with Assigned first',
        [C.FieldRaw[Fld], Why, Trim(NodeStr(N))]);
      if AViaName <> '' then Msg:= Msg + Format(' (%s is called only from the destructor)', [AViaName]);  // dl:ok concat-in-loop@edd3 -- REVIEWED 2026-11-13 v151 TYP: one append per finding message, at most once per finding
      Emit(RULE_DTOR_NIL_SAFE, 'warning', N, Msg, C.RawName + '.' + C.FieldRaw[Fld]);
    end;
  finally
    L.Free;
  end;
end;

procedure TTypScan.CheckDestructors;
var
  R, R2     : TTSNode;
  Cls       : string;
  Raised    : Boolean;
  Suspect   : TDictionary<string, string>;
  Created   : TDictionary<string, Boolean>;
  Done      : TDictionary<string, Boolean>;
  C         : TTypClass;
  Meth      : string;
  CalledElse: Boolean;
  CalledDtor: Boolean;
begin
  Done:= TDictionary<string, Boolean>.Create;
  Suspect:= TDictionary<string, string>.Create;
  Created:= TDictionary<string, Boolean>.Create;
  try
    for R in FRoutines do
    begin
      if not IsDtor(R) then Continue;
      Cls:= ClassOf(R);
      if (Cls = '') or Done.ContainsKey(Cls) or not FClasses.TryGetValue(Cls, C) then Continue;
      Done.Add(Cls, True);
      Suspect.Clear;
      for R2 in FRoutines do
        if IsCtor(R2) and (ClassOf(R2) = Cls) then
        begin
          Raised:= False;
          Created.Clear;
          WalkCtorSeq(StatementsOf(BodyOf(R2)), Cls, Raised, False, Suspect, Created);
        end;
      if Suspect.Count = 0 then Continue;
      for R2 in FRoutines do
        if IsDtor(R2) and (ClassOf(R2) = Cls) then CheckDtorRoutine(R2, Cls, Suspect, '');
      { private methods of the class that only the destructor calls }
      for R2 in FRoutines do
      begin
        if (ClassOf(R2) <> Cls) or IsDtor(R2) or IsCtor(R2) then Continue;
        Meth:= MethodOf(R2);
        if not C.PrivMeths.ContainsKey(Meth) then Continue;
        CalledElse:= False;
        CalledDtor:= False;
        for var R3: TTSNode in FRoutines do
        begin
          if R3 = R2 then Continue;
          var Ids: TList<TTSNode>:= TList<TTSNode>.Create;
          try
            Gather(BodyOf(R3), ['identifier'], Ids);
            for var Id: TTSNode in Ids do
              if SameText(Trim(NodeStr(Id)), Meth) then
              begin
                if IsDtor(R3) and (ClassOf(R3) = Cls) then CalledDtor:= True
                else CalledElse:= True;
              end;
          finally
            Ids.Free;
          end;
          if CalledElse then Break;
        end;
        if CalledDtor and not CalledElse then
          CheckDtorRoutine(R2, Cls, Suspect, Trim(NodeStr(R2.ChildByField('header').ChildByField('name'))));
      end;
    end;
  finally
    Created.Free;
    Suspect.Free;
    Done.Free;
  end;
end;

{ ---- field-free-without-nil ----------------------------------------------- }

{ 1 = AStmt sets AField on every path through it (a direct assignment, or a call
  of a method of the class that assigns it); 2 = it ends the routine (Exit / raise);
  0 = neither. }
function TTypScan.StmtSetsField(const AStmt: TTSNode; const AClass, AField: string;  // dl:ok too-many-exit-points@9b5d -- REVIEWED 2026-11-13 v151 TYP: guard clauses, one per statement kind that decides the answer
  const ASetters: TDictionary<string, Boolean>): Integer;
var
  Fld, Nm: string;
  K      : TTSNode;
begin
  Result:= 0;
  if AStmt.NodeType = 'assignment' then
  begin
    if FieldOf(AClass, NodeStr(AStmt.ChildByField('lhs')), Fld) and (Fld = AField) then Exit(1);
    Exit;
  end;
  if AStmt.NodeType = 'raise' then Exit(2);
  if (AStmt.NodeType = 'block') or (AStmt.NodeType = 'statements') then
  begin
    for K in StatementsOf(AStmt) do
    begin
      Result:= StmtSetsField(K, AClass, AField, ASetters);
      if Result <> 0 then Exit;
    end;
    Exit;
  end;
  if (AStmt.NodeType = 'statement') and (AStmt.NamedChildCount = 1) then
  begin
    K:= AStmt.NamedChild(0);
    if K.NodeType = 'exprCall' then
    begin
      if SameText(Trim(NodeStr(K.ChildByField('entity'))), 'freeandnil') and
         (Canon(NodeStr(K.ChildByField('args'))) = AField) then
        Exit(1);
      K:= K.ChildByField('entity');
    end;
    Nm:= Canon(NodeStr(K));
    if (Nm = 'exit') or StartsText('exit(', Nm) then Exit(2);
    if ASetters.ContainsKey(Nm) then Exit(1);
    Exit;
  end;
  { an if-else that sets it in both branches sets it }
  if (AStmt.NodeType = 'ifElse') and
     (StmtSetsField(AStmt.ChildByField('then'), AClass, AField, ASetters) = 1) and
     (StmtSetsField(AStmt.ChildByField('else'), AClass, AField, ASetters) = 1) then
    Exit(1);
  { any other compound statement: an Exit or raise inside leaves on a path that
    has not set it }
  var Inner: TList<TTSNode>:= TList<TTSNode>.Create;
  try
    Gather(AStmt, ['statement', 'raise'], Inner);
    for K in Inner do
    begin
      if K.NodeType = 'raise' then Exit(2);
      Nm:= Canon(NodeStr(K));
      if (Nm = 'exit;') or (Nm = 'exit') or StartsText('exit(', Nm) then Exit(2);
    end;
  finally
    Inner.Free;
  end;
end;

{ Is AField set again on every path from AStmt (its Free) to the routine end?
  Walks the statements after AStmt, then after each enclosing statement, up to
  ABody. The first statement that sets it decides yes; an Exit / raise before
  that, or the routine end, decides no. }
function TTypScan.SetsFieldAfter(const AStmt: TTSNode; const ABody: TTSNode; const AClass, AField: string;
  const ASetters: TDictionary<string, Boolean>): Boolean;
var
  Cur, Par: TTSNode;
  Sib     : TTSNode;
  R       : Integer;
begin
  Result:= False;
  Cur:= AStmt;
  while (not Cur.IsNull) and not (Cur = ABody) do  // dl:ok nonminimal-bool@4ac4 -- REVIEWED 2026-11-13 v151 TYP: TTSNode declares Equal but no NotEqual operator; <> does not compile
  begin
    Par:= Cur.Parent;
    if Par.IsNull then Exit;
    { a repeat / while / for body runs again: no conclusion from the loop head }
    Sib:= Cur.NextSibling;
    while not Sib.IsNull do
    begin
      if Sib.IsNamed then
      begin
        R:= StmtSetsField(Sib, AClass, AField, ASetters);
        if R = 1 then Exit(True);
        if R = 2 then Exit(False);
      end;
      Sib:= Sib.NextSibling;
    end;
    { leaving an except handler or a try part continues after the try }
    Cur:= Par;
  end;
end;

{ Methods of AClass in which a Free without nil is allowed: destructors,
  BeforeDestruction, *Destroy handlers, tear-down methods, and methods called only
  from these. }
{ One walk over every routine body: the identifier index and the per-routine
  class / method names ExemptFreeRoutines looks up. Keys are LowerCase (ASCII),
  matching the SameText comparison against the lower-cased MethodOf. }
procedure TTypScan.BuildIdentIndex;
var
  Ids   : TList<TTSNode>;
  Counts: TDictionary<string, Integer>;
  Occ   : TList<TPair<Integer, Integer>>;
  I, Cnt: Integer;
  Key   : string;
begin
  FIdentIdx:= TObjectDictionary<string, TList<TPair<Integer, Integer>>>.Create([doOwnsValues]);
  SetLength(FRtClass, FRoutines.Count);
  SetLength(FRtMeth, FRoutines.Count);
  Ids:= TList<TTSNode>.Create;
  Counts:= TDictionary<string, Integer>.Create;
  try
    for I:= 0 to FRoutines.Count - 1 do
    begin
      FRtClass[I]:= ClassOf(FRoutines[I]);
      FRtMeth[I]:= MethodOf(FRoutines[I]);
      Ids.Clear;
      Counts.Clear;
      Gather(BodyOf(FRoutines[I]), ['identifier'], Ids);
      for var Id: TTSNode in Ids do
      begin
        Key:= LowerCase(Trim(NodeStr(Id)));
        Cnt:= 0;
        Counts.TryGetValue(Key, Cnt);
        Counts.AddOrSetValue(Key, Cnt + 1);
      end;
      for var P: TPair<string, Integer> in Counts do
      begin
        if not FIdentIdx.TryGetValue(P.Key, Occ) then
        begin
          Occ:= TList<TPair<Integer, Integer>>.Create;
          FIdentIdx.Add(P.Key, Occ);
        end;
        Occ.Add(TPair<Integer, Integer>.Create(I, P.Value));
      end;
    end;
  finally
    Counts.Free;
    Ids.Free;
  end;
end;

function TTypScan.ExemptFreeRoutines(const AClass: string): TDictionary<string, Boolean>;
var
  R      : TTSNode;
  C      : TTypClass;
  Meth   : string;
  Changed: Boolean;
  Occ    : TList<TPair<Integer, Integer>>;
  Callers: Integer;
  Exempt : Integer;
  I      : Integer;
begin
  if FIdentIdx = nil then BuildIdentIndex;
  Result:= TDictionary<string, Boolean>.Create;
  FClasses.TryGetValue(AClass, C);
  for I:= 0 to FRoutines.Count - 1 do
  begin
    if FRtClass[I] <> AClass then Continue;
    R:= FRoutines[I];
    Meth:= FRtMeth[I];
    { a close handler that sets Action := caFree hands the form to its destruction }
    if IsDtor(R) or (Meth = 'beforedestruction') or EndsText('destroy', Meth) or  // dl:ok boolean-expression-complexity@912e -- REVIEWED 2026-11-13 v151 TYP: the list of exempt routine kinds, each a named case in the rule doc
       ((C <> nil) and C.TearDowns.ContainsKey(Meth)) or ContainsStr(Canon(NodeStr(BodyOf(R))), 'action:=cafree') then
      Result.AddOrSetValue(Meth, True);
  end;
  { a method called only from exempt methods of the class is exempt too; the
    identifier index replaces a walk of every routine body per candidate }
  repeat
    Changed:= False;
    for I:= 0 to FRoutines.Count - 1 do
    begin
      if (FRtClass[I] <> AClass) or IsCtor(FRoutines[I]) then Continue;
      Meth:= FRtMeth[I];
      if Result.ContainsKey(Meth) then Continue;
      Callers:= 0;
      Exempt:= 0;
      if FIdentIdx.TryGetValue(Meth, Occ) then
        for var P: TPair<Integer, Integer> in Occ do
        begin
          if P.Key = I then Continue;
          Inc(Callers, P.Value);
          if (FRtClass[P.Key] = AClass) and Result.ContainsKey(FRtMeth[P.Key]) then Inc(Exempt, P.Value);
        end;
      if (Callers > 0) and (Callers = Exempt) then
      begin
        Result.AddOrSetValue(Meth, True);
        Changed:= True;
      end;
    end;
  until not Changed;
end;

procedure TTypScan.CheckFreeWithoutNil;
var
  R      : TTSNode;
  Cls    : string;
  C      : TTypClass;
  Exempt : TObjectDictionary<string, TDictionary<string, Boolean>>;
  Setters: TObjectDictionary<string, TDictionary<string, Boolean>>;
  Ex     : TDictionary<string, Boolean>;
  St     : TDictionary<string, Boolean>;
  L      : TList<TTSNode>;
  N, K   : TTSNode;
  Fld    : string;
begin
  Exempt := TObjectDictionary<string, TDictionary<string, Boolean>>.Create([doOwnsValues]);
  Setters:= TObjectDictionary<string, TDictionary<string, Boolean>>.Create([doOwnsValues]);
  L:= TList<TTSNode>.Create;
  try
    for R in FRoutines do
    begin
      Cls:= ClassOf(R);
      if (Cls = '') or IsDtor(R) or not FClasses.TryGetValue(Cls, C) then Continue;
      if not Exempt.TryGetValue(Cls, Ex) then
      begin
        Ex:= ExemptFreeRoutines(Cls);
        Exempt.Add(Cls, Ex);
      end;
      if Ex.ContainsKey(MethodOf(R)) then Continue;
      L.Clear;
      Gather(BodyOf(R), ['statement'], L);
      for N in L do
      begin
        if N.NamedChildCount <> 1 then Continue;
        K:= N.NamedChild(0);
        if K.NodeType = 'exprCall' then
        begin
          if (K.ChildByField('args').IsNull) or (K.ChildByField('args').NamedChildCount = 0) then
            K:= K.ChildByField('entity')
          else
            Continue;
        end;
        if K.NodeType <> 'exprDot' then Continue;
        if not SameText(Trim(NodeStr(K.ChildByField('rhs'))), 'free') then Continue;
        if not FieldOf(Cls, NodeStr(K.ChildByField('lhs')), Fld) then Continue;
        { the setters of this field: methods of the class with a top-level assignment to it }
        if not Setters.TryGetValue(Cls + '|' + Fld, St) then
        begin
          St:= TDictionary<string, Boolean>.Create;
          Setters.Add(Cls + '|' + Fld, St);
          for var R2: TTSNode in FRoutines do
            if (ClassOf(R2) = Cls) and not (R2 = R) then  // dl:ok nonminimal-bool@b1df -- REVIEWED 2026-11-13 v151 TYP: TTSNode declares Equal but no NotEqual operator; <> does not compile
              for var S2: TTSNode in StatementsOf(BodyOf(R2)) do
                if StmtSetsField(S2, Cls, Fld, St) = 1 then
                begin
                  St.AddOrSetValue(MethodOf(R2), True);
                  Break;
                end;
        end;
        if SetsFieldAfter(N, BodyOf(R), Cls, Fld, St) then Continue;
        Emit(RULE_FREE_WITHOUT_NIL, 'warning', N,
          Format('%s is freed in %s but the field keeps the dangling reference on a path to the end of the method ' +
            '-- a later access or a second Free hits freed memory; use FreeAndNil(%s) or assign the field again',
            [C.FieldRaw[Fld], Trim(NodeStr(R.ChildByField('header').ChildByField('name'))), C.FieldRaw[Fld]]),
          C.RawName + '.' + C.FieldRaw[Fld]);
      end;
    end;
  finally
    L.Free;
    Setters.Free;
    Exempt.Free;
  end;
end;

{ ---- field-ownership-unclear ---------------------------------------------- }

procedure TTypScan.CheckOwnershipUnclear;  // dl:ok cyclomatic-complexity@67bc, cognitive-complexity@6694 -- REVIEWED 2026-11-13 v151 TYP: one walk that collects created, freed and handed-out facts per class in a single pass over its routines
var
  R         : TTSNode;
  Cls, Fld  : string;
  C         : TTypClass;
  L         : TList<TTSNode>;
  N, A      : TTSNode;
  Created   : TDictionary<string, TTSNode>;
  Freed     : TDictionary<string, Boolean>;
  HandedOut : TDictionary<string, string>;
  Owning    : TDictionary<string, Boolean>;
  Args      : TArray<string>;
  CCls, Arg : string;
  Ty, How   : string;
  Pair      : TPair<string, TTSNode>;
  Owned     : Boolean;
begin
  Created  := TDictionary<string, TTSNode>.Create;
  Freed    := TDictionary<string, Boolean>.Create;
  HandedOut:= TDictionary<string, string>.Create;
  Owning   := TDictionary<string, Boolean>.Create;
  L:= TList<TTSNode>.Create;
  try
    for C in FClasses.Values do
    begin
      Cls:= C.Name;
      Created.Clear;
      Freed.Clear;
      HandedOut.Clear;
      Owning.Clear;
      for R in FRoutines do
      begin
        if ClassOf(R) <> Cls then Continue;
        L.Clear;
        Gather(BodyOf(R), ['assignment', 'statement', 'exprCall'], L);
        for N in L do
        begin
          if N.NodeType = 'assignment' then
          begin
            A:= N.ChildByField('rhs');
            if FieldOf(Cls, NodeStr(N.ChildByField('lhs')), Fld) and IsCreateExpr(A, CCls, Args) then
            begin
              { an owning container field: it frees what is added to it }
              if InList(CCls, OWNING_CONTAINERS) and not ((Length(Args) > 0) and (Args[0] = 'false')) then
                Owning.AddOrSetValue(Fld, True);
              if IsCtor(R) and not Created.ContainsKey(Fld) then
              begin
                Owned:= False;
                for Arg in Args do
                  if InList(Arg, OWNER_ARGS) then Owned:= True;
                Ty:= '';
                C.Fields.TryGetValue(Fld, Ty);
                if (not Owned) and not IsInterfaceType(Ty) and not StartsText('tarray', LeafType(Ty)) then
                  Created.Add(Fld, N);
              end;
              Continue;
            end;
            { handed out: Result := F, Other.Prop := F }
            if FieldOf(Cls, NodeStr(A), Fld) then
            begin
              var Lhs: string:= Canon(NodeStr(N.ChildByField('lhs')));
              if Lhs = 'result' then HandedOut.AddOrSetValue(Fld, 'returned')
              else if Lhs.Contains('.') and not HandedOut.ContainsKey(Fld) then
                HandedOut.AddOrSetValue(Fld, 'stored in ' + Trim(NodeStr(N.ChildByField('lhs'))));
            end;
          end
          else if N.NodeType = 'statement' then
          begin
            if N.NamedChildCount <> 1 then Continue;
            A:= N.NamedChild(0);
            if A.NodeType = 'exprCall' then A:= A.ChildByField('entity');
            if A.NodeType = 'exprDot' then
            begin
              var M: string:= LowerCase(Trim(NodeStr(A.ChildByField('rhs'))));
              if ((M = 'free') or (M = 'disposeof') or (M = 'destroy') or (M = 'release')) and
                 FieldOf(Cls, NodeStr(A.ChildByField('lhs')), Fld) then
                Freed.AddOrSetValue(Fld, True);
            end;
          end
          else
          begin
            { exprCall: FreeAndNil(F), Exit(F), X.AddY(F) }
            var Ent: string:= Canon(NodeStr(N.ChildByField('entity')));
            var Ar: TTSNode:= N.ChildByField('args');
            if Ar.IsNull then Continue;
            for var I: Integer:= 0 to Ar.NamedChildCount - 1 do
            begin
              if not FieldOf(Cls, NodeStr(Ar.NamedChild(I)), Fld) then Continue;
              if Ent = 'freeandnil' then Freed.AddOrSetValue(Fld, True)
              else if Ent = 'exit' then HandedOut.AddOrSetValue(Fld, 'returned')
              else
              begin
                var Dot: Integer:= LastDelimiter('.', Ent);
                var Meth: string:= Copy(Ent, Dot + 1, MaxInt);
                var Recv: string:= Copy(Ent, 1, Dot - 1);
                var Hand: Boolean:= False;
                for var P: string in HANDOFF_PREFIXES do
                  if StartsText(P, Meth) then Hand:= True;
                if not Hand then Continue;
                if (Dot > 0) and Owning.ContainsKey(Recv) then Continue;
                if (Dot > 0) and FieldOf(Cls, Recv, Arg) and Owning.ContainsKey(Arg) then Continue;
                HandedOut.AddOrSetValue(Fld, 'handed to ' + Trim(NodeStr(N.ChildByField('entity'))));
              end;
            end;
          end;
        end;
      end;
      for Pair in Created do
      begin
        if Freed.ContainsKey(Pair.Key) then Continue;
        if not HandedOut.TryGetValue(Pair.Key, How) then Continue;
        { handed to an owning container field of this class: the container frees it }
        if StartsText('handed to ', How) then
        begin
          var Recv: string:= Canon(Copy(How, Length('handed to ') + 1, MaxInt));
          Recv:= Copy(Recv, 1, LastDelimiter('.', Recv) - 1);
          if Owning.ContainsKey(Recv) then Continue;
        end;
        Emit(RULE_OWNERSHIP_UNCLEAR, 'hint', Pair.Value,
          Format('%s is created by %s and never freed by it, but it is %s -- decide who owns the object: free it in ' +
            'the destructor, or document that the receiver takes it over', [C.FieldRaw[Pair.Key], C.RawName, How]),
          C.RawName + '.' + C.FieldRaw[Pair.Key]);
      end;
    end;
  finally
    L.Free;
    Owning.Free;
    HandedOut.Free;
    Freed.Free;
    Created.Free;
  end;
end;

function TTypScan.Run: TArray<TLintFinding>;
var
  All: TList<TTSNode>;
  R  : TTSNode;

  procedure AllRoutines(const N: TTSNode);
  var
    I: Integer;
  begin
    if N.IsNull then Exit;
    if N.NodeType = 'defProc' then All.Add(N);
    for I:= 0 to N.NamedChildCount - 1 do AllRoutines(N.NamedChild(I));
  end;

begin
  All:= TList<TTSNode>.Create;
  try
    AllRoutines(FRoot);
    FRoutines.AddRange(All);
  finally
    All.Free;
  end;
  CollectClasses;
  for R in FRoutines do
  begin
    if FCtx.Wants(RULE_UNRELATED_CAST) then CheckCasts(R);
    if FCtx.Wants(RULE_SELF_INTF_CTOR) then CheckSelfInterface(R);
  end;
  if FCtx.Wants(RULE_DTOR_NIL_SAFE) then CheckDestructors;
  if FCtx.Wants(RULE_FREE_WITHOUT_NIL) then CheckFreeWithoutNil;
  if FCtx.Wants(RULE_OWNERSHIP_UNCLEAR) then CheckOwnershipUnclear;
  Result:= FFindings.ToArray;
end;

function TypCheckFile(const ACtx: TV151FileCtx): TArray<TLintFinding>;
var
  PF  : TParsedFile;
  Scan: TTypScan;
begin
  Result:= nil;
  if not (ACtx.Wants(RULE_UNRELATED_CAST) or ACtx.Wants(RULE_SELF_INTF_CTOR) or ACtx.Wants(RULE_DTOR_NIL_SAFE) or
          ACtx.Wants(RULE_FREE_WITHOUT_NIL) or ACtx.Wants(RULE_OWNERSHIP_UNCLEAR)) then
    Exit;
  PF:= TAstParseCache.Get(ACtx.Path);
  if PF.Tree = nil then Exit;
  Scan:= TTypScan.Create(ACtx, PF.Src, PF.Tree.RootNode);
  try
    Result:= Scan.Run;
  finally
    Scan.Free;
  end;
end;

end.
