unit DRagLint.V154.FLOW.Support;

{ Wave v154 lane FLOW -- helpers of DRagLint.V154.FLOW (private to the lane): one run over one parsed unit.
    managed-result-read-first    -- Result of a managed type read before it is set on every path (CFG, definite assignment)
    same-variable-two-var-params -- one variable passed to two parameters that can change or clear it (exact callee)
    address-of-nested-routine    -- @Nested / Addr(Nested)
    var-param-never-written      -- a var parameter that is only read (index)
    value-param-assigned         -- a by-value parameter used as a local variable
    constant-return              -- every way out of a function sets the same literal (index)
    redundant-field-init         -- a constructor sets a field of its class to the value it already has
    absolute-overlay             -- a variable declared absolute over another
  A question the source and the index do not answer completely is answered "no finding". }

interface

uses
  System.SysUtils
  , System.Generics.Collections
  , TreeSitter
  , DRagLint.Core.Model
  , DRagLint.V151.Api
  , DRagLint.V154.ParamModes
  ;

const
  RULE_RESULT_FIRST = 'managed-result-read-first';
  RULE_SAME_VAR = 'same-variable-two-var-params';
  RULE_NESTED_ADDR = 'address-of-nested-routine';
  RULE_VAR_UNWRITTEN = 'var-param-never-written';
  RULE_VALUE_SET = 'value-param-assigned';
  RULE_CONST_RETURN = 'constant-return';
  RULE_FIELD_INIT = 'redundant-field-init';
  RULE_OVERLAY = 'absolute-overlay';

type
  /// <summary>What one class declaration of the unit says, as redundant-field-init needs it.</summary>
  TFlowClass = class
  strict private
    FFields   : TDictionary<string, string>;
    FHooked   : Boolean;
    FOwnMemory: Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Instance fields: lower-case name to lower-case type text without blanks.</summary>
    property Fields: TDictionary<string, string> read FFields;
    /// <summary>The class has virtual routines or message handlers, or lists an interface: its code can run inside a call the constructor makes.</summary>
    property Hooked: Boolean read FHooked write FHooked;
    /// <summary>The class replaces NewInstance, so a new object need not be zero.</summary>
    property OwnMemory: Boolean read FOwnMemory write FOwnMemory;
  end;

  /// <summary>One run of the lane over one parsed unit.</summary>
  /// <remarks>Create, call the Check methods, Free. Not thread-safe. The node lists are collected once, in Create.</remarks>
  TFlowRun = class  // dl:ok high-response@2180 -- REVIEWED 2026-11-24 v154 FLOW: one walker per file run; the rules share its node lists and tree helpers
  strict private
    FCtx      : TV151FileCtx;
    FSrc      : TBytes;
    FRoutines : TList<TTSNode>;
    FCalls    : TList<TTSNode>;
    FAddresses: TList<TTSNode>;
    FOverlays : TList<TTSNode>;
    FTypes    : TDictionary<string, TTSNode>;
    FClasses  : TObjectDictionary<string, TFlowClass>;
    FManaged  : TDictionary<string, Boolean>;
    FEdges    : TDictionary<string, Int64>;
    FParams   : TDictionary<Int64, TV154ParamList>;
    FFindings : TList<TLintFinding>;
    procedure Collect(const ARoot: TTSNode);
    procedure Emit(const ARule, ASeverity, AMessage: string; const ANode: TTSNode);
    function Text(const ANode: TTSNode): string;
    function Lower(const ANode: TTSNode): string;
    function Flat(const ANode: TTSNode): string;
    function ManagedText(const AType: string; ADepth: Integer): Boolean;
    function ManagedName(const AType: string; ADepth: Integer): Boolean;
    function ManagedDecl(const ADecl: TTSNode; ADepth: Integer): Boolean;
    function IsResultRead(const ANode: TTSNode): Boolean;
    procedure AddResultReads(const ANode: TTSNode; AList: TList<TTSNode>);
    function ResultReads(const ANode: TTSNode): TArray<TTSNode>;
    function SetAtOnce(const ABody: TTSNode): Boolean;
    function GuardsOf(const ARoutine, ANode: TTSNode): TArray<string>;
    function SameGuard(const ARoutine, ARead: TTSNode): Boolean;
    function FilledEarlier(const AItem, ARead: TTSNode): Boolean;
    procedure CheckResult(const ARoutine: TTSNode);
    procedure LoadEdges;
    function CalleeParams(const ACall: TTSNode): TV154ParamList;
    function Conflict(const A, B: TV154Param): Boolean;
    function VariableText(const AArg: TTSNode): string;
    procedure CheckCallArgs(const ACall: TTSNode);
    function NestedOwner(const ANode: TTSNode; const AName: string): TTSNode;
    function RoutineSymbol(const ARoutine: TTSNode; out ASymbol: TSymbol): Boolean;
    function SignatureFixed(const ASymbol: TSymbol): Boolean;
    function MethodFixed(const ASymbol: TSymbol): Boolean;
    function HasRows(const ASql, AName: string): Boolean;
    function ArgumentOnlyRead(const APath, AArgs: TTSNode): Boolean;
    function MemberOnlyRead(const AName, AType: string): Boolean;
    function UseOnlyReads(const AUse: TTSNode; const AType: string): Boolean;
    procedure CheckVarParam(const ARoutine, AName: TTSNode; const AType: string);
    function SetsParam(const AUse: TTSNode): Boolean;
    procedure CheckValueParam(const ARoutine, AName: TTSNode);
    function ReturnedValue(const ANode: TTSNode; const AOwnName: string): TTSNode;
    procedure AddConstants(const ANode: TTSNode; const AOwnName: string; AValues: TList<string>; var ABad: Boolean);
    procedure CheckConstant(const ARoutine: TTSNode);
    procedure ReadMembers(const ANode: TTSNode; AInfo: TFlowClass);
    procedure AddClass(const ADecl: TTSNode);
    function NamedElsewhere(const AClass, AField: string): Boolean;
    function PlainValue(const ANode, ARoutine: TTSNode; var AOutside: Boolean): Boolean;
    function PlainInherited(const ANode, ARoutine: TTSNode; var AOutside: Boolean): Boolean;
    procedure CheckConstructor(const ARoutine: TTSNode);
    function OverUntyped(const AOverlay, ATarget: TTSNode): Boolean;
  public
    /// <summary>Collects the routines, calls, addresses, overlays and types of the unit.</summary>
    /// <param name="ACtx">The file; Store may be nil.</param>
    constructor Create(const ACtx: TV151FileCtx);
    destructor Destroy; override;
    /// <summary>managed-result-read-first.</summary>
    procedure CheckResults;
    /// <summary>same-variable-two-var-params; nothing without an index.</summary>
    procedure CheckArguments;
    /// <summary>address-of-nested-routine.</summary>
    procedure CheckNestedAddresses;
    /// <summary>var-param-never-written; nothing without an index.</summary>
    procedure CheckVarParams;
    /// <summary>value-param-assigned.</summary>
    procedure CheckValueParams;
    /// <summary>constant-return; nothing without an index.</summary>
    procedure CheckConstants;
    /// <summary>redundant-field-init.</summary>
    procedure CheckFieldInits;
    /// <summary>absolute-overlay.</summary>
    procedure CheckOverlays;
    /// <summary>The findings so far.</summary>
    /// <returns>Findings in the order they were made; nil when none.</returns>
    function Findings: TArray<TLintFinding>;
  end;

implementation

uses
  System.StrUtils
  , System.RegularExpressions
  , FireDAC.Comp.Client
  , FireDAC.Stan.Param
  , TreeSitterLib
  , DRagLint.Core.Interfaces
  , DRagLint.Diagnostics.ParseCache
  , DRagLint.Storage.SQLite
  , DRagLint.Analysis.Cfg
  , DRagLint.Analysis.DataFlow
  , DRagLint.Analysis.Flow.Lattices
  ;

const
  SEVERITY_WARNING = 'warning';
  SEVERITY_HINT = 'hint';
  RESULT_NAME = 'result';
  SELF_NAME = 'self';
  SELF_PREFIX = SELF_NAME + '.';
  SYSTEM_PREFIX = 'system.';
  ROUTINE_NODES: array[0..1] of string = ('defProc', 'lambda');
  IF_NODES: array[0..1] of string = ('if', 'ifElse');
  MANAGED_TYPES: array[0..10] of string = ('string', 'unicodestring', 'ansistring', 'widestring', 'rawbytestring', 'utf8string', 'variant',
    'olevariant', 'iinterface', 'iunknown', 'tbytes');
  { calls that take a variable by value although its name alone stands in the argument list }
  READ_CALLS: array[0..19] of string = ('length', 'high', 'low', 'copy', 'pos', 'trim', 'uppercase', 'lowercase', 'sametext', 'assigned',
    'ord', 'sizeof', 'inttostr', 'writeln', 'abs', 'chr', 'succ', 'pred', 'odd', 'quotedstr');
  INC_CALLS: array[0..1] of string = ('inc', 'dec');
  MAX_DEPTH = 8;
  EVENT_PARAM = 'sender:';
  { a routine with one of these directives has a signature somebody else dictates }
  FIXED_DIRECTIVES: array[0..8] of string = ('virtual', 'dynamic', 'override', 'abstract', 'message', 'external', 'stdcall', 'cdecl', 'safecall');
  { published and default-visibility methods can be bound in a form file }
  CODE_VISIBILITY: array[0..4] of string = ('public', 'private', 'protected', 'strict private', 'strict protected');
  LITERAL_NODES: array[0..5] of string = ('literalNumber', 'literalString', 'literalChar', 'kTrue', 'kFalse', 'kNil');
  ZERO_VALUES: array[0..6] of string = ('0', '0.0', '$0', '$00', 'nil', 'false', '''''');
  ASM_NODES: array[0..0] of string = ('asm');

{ ---- tree ---- }

function NodeText(const ANode: TTSNode; const ASrc: TBytes): string;
var
  First, Last: Integer;
begin
  Result:= '';
  if ANode.IsNull then Exit;
  First:= Integer(ANode.StartByte);
  Last := Integer(ANode.EndByte);
  if (Last > First) and (Last <= Length(ASrc)) then Result:= TEncoding.UTF8.GetString(ASrc, First, Last - First);
end;

{ Lower case without any blank. }
function FlatText(const AText: string): string;
begin
  Result:= string.Join('', LowerCase(AText).Split([' ', #9, #10, #13], TStringSplitOptions.ExcludeEmpty));
end;

function HasChild(const ANode: TTSNode; const AKinds: array of string): Boolean;
var
  I: Integer;
begin
  Result:= False;
  for I:= 0 to ANode.NamedChildCount - 1 do
    if MatchStr(ANode.NamedChild(I).NodeType, AKinds) then Exit(True);
end;

function HasNode(const ANode: TTSNode; const AKinds: array of string): Boolean;
var
  I: Integer;
begin
  Result:= MatchStr(ANode.NodeType, AKinds);
  I     := 0;
  while (not Result) and (I < ANode.NamedChildCount) do
  begin
    Result:= HasNode(ANode.NamedChild(I), AKinds);
    Inc(I);
  end;
end;

{ The routine or anonymous method ANode stands in; null at unit level. }
function Enclosing(const ANode: TTSNode): TTSNode;
begin
  Result:= ANode.Parent;
  while (not Result.IsNull) and (not MatchStr(Result.NodeType, ROUTINE_NODES)) do Result:= Result.Parent;
end;

function IsMemberName(const ANode: TTSNode): Boolean;
var
  Rhs: TTSNode;
begin
  if ANode.Parent.NodeType <> 'exprDot' then Exit(False);
  Rhs   := ANode.Parent.ChildByField('rhs');
  Result:= (not Rhs.IsNull) and (Rhs.StartByte = ANode.StartByte);
end;

{ X, X.F, X[I], X^: the largest path whose base is ANode. }
function PathOf(const ANode: TTSNode): TTSNode;
var
  Up: TTSNode;
begin
  Result:= ANode;
  Up    := Result.Parent;
  while (not Up.IsNull) and (Up.NamedChild(0) = Result) and
    (MatchStr(Up.NodeType, ['exprDot', 'exprSubscript']) or ((Up.NodeType = 'exprUnary') and HasChild(Up, ['kHat']))) do
  begin
    Result:= Up;
    Up    := Result.Parent;
  end;
end;

{ The exprCall whose argument list holds ANode as a whole argument; null when there is none. }
function CallOfArgument(const ANode: TTSNode): TTSNode;
begin
  Result:= Default(TTSNode);
  if (ANode.Parent.NodeType = 'exprArgs') and (ANode.Parent.Parent.NodeType = 'exprCall') then Result:= ANode.Parent.Parent;
end;

function CallArguments(const ACall: TTSNode): TArray<TTSNode>;
var
  Args: TTSNode;
  I   : Integer;
begin
  Result:= nil;
  Args  := ACall.ChildByField('args');
  if Args.IsNull then Exit;
  for I:= 0 to Args.NamedChildCount - 1 do
    if Args.NamedChild(I).NodeType <> 'comment' then Result:= Result + [Args.NamedChild(I)];
end;

{ The called name: Foo(..), A.Foo(..). }
function CalleeName(const ACall: TTSNode): TTSNode;
begin
  Result:= ACall.ChildByField('entity');
  if (not Result.IsNull) and (Result.NodeType = 'exprDot') then Result:= Result.ChildByField('rhs');
end;

{ The declared names of a declArg / declVar / declField: the identifiers before its type. }
function DeclaredNames(const ADecl: TTSNode): TArray<TTSNode>;
var
  I: Integer;
begin
  Result:= nil;
  for I:= 0 to ADecl.NamedChildCount - 1 do
  begin
    if MatchStr(ADecl.NamedChild(I).NodeType, ['type', 'kAbsolute', 'defaultValue']) then Break;
    if ADecl.NamedChild(I).NodeType = 'identifier' then Result:= Result + [ADecl.NamedChild(I)];
  end;
end;

function Header(const ARoutine: TTSNode): TTSNode;
begin
  Result:= ARoutine.ChildByField('header');
end;

{ The declArg nodes of a routine or an anonymous method. }
function Arguments(const ARoutine: TTSNode): TArray<TTSNode>;
var
  Args: TTSNode;
  I   : Integer;
begin
  Result:= nil;
  Args  := Header(ARoutine);
  if Args.IsNull then Args:= ARoutine;
  Args:= Args.ChildByField('args');
  if Args.IsNull then Exit;
  for I:= 0 to Args.NamedChildCount - 1 do
    if Args.NamedChild(I).NodeType = 'declArg' then Result:= Result + [Args.NamedChild(I)];
end;

{ ARoutine's parameter or local variable AName (any case). }
function Declares(const ARoutine: TTSNode; const AName: string; const ASrc: TBytes; out ADecl: TTSNode): Boolean;

  function Names(const ADeclaration: TTSNode): Boolean;
  var
    Name: TTSNode;
  begin
    Result:= False;
    for Name in DeclaredNames(ADeclaration) do
      if SameText(NodeText(Name, ASrc), AName) then
      begin
        ADecl:= ADeclaration;
        Exit(True);
      end;
  end;

var
  I, J: Integer;
  Arg, Vars: TTSNode;
begin
  Result:= False;
  ADecl := Default(TTSNode);
  for Arg in Arguments(ARoutine) do
    if Names(Arg) then Exit(True);
  for I:= 0 to ARoutine.NamedChildCount - 1 do
  begin
    Vars:= ARoutine.NamedChild(I);
    if Vars.NodeType <> 'declVars' then Continue;
    for J:= 0 to Vars.NamedChildCount - 1 do
      if Names(Vars.NamedChild(J)) then Exit(True);
  end;
end;

{ Uses of AName under ANode, nested routines that declare the name again left out. }
procedure AddUses(const ANode: TTSNode; const AName: string; const ASrc: TBytes; AList: TList<TTSNode>);
var
  I: Integer;
  Decl, Child: TTSNode;
begin
  if (ANode.NodeType = 'identifier') and SameText(NodeText(ANode, ASrc), AName) and (not IsMemberName(ANode)) then AList.Add(ANode);
  for I:= 0 to ANode.NamedChildCount - 1 do
  begin
    Child:= ANode.NamedChild(I);
    if MatchStr(Child.NodeType, ['declProc', 'type', 'typeref']) then Continue;
    if MatchStr(Child.NodeType, ROUTINE_NODES) and Declares(Child, AName, ASrc, Decl) then Continue;
    AddUses(Child, AName, ASrc, AList);
  end;
end;

function IsAssignTarget(const APath: TTSNode): Boolean;
begin
  Result:= (APath.Parent.NodeType = 'assignment') and (APath.Parent.ChildByField('lhs') = APath);
end;

function IsAddressOf(const ANode: TTSNode): Boolean;
begin
  Result:= (ANode.NodeType = 'exprUnary') and HasChild(ANode, ['kAt']);
end;

function LastName(const AName: string): string;
begin
  Result:= Copy(AName, LastDelimiter('.', AName) + 1, MaxInt);
end;

{ TFoo<T>.TBar.Create -> TFoo.TBar.Create }
function WithoutGenerics(const AName: string): string;
begin
  Result:= TRegEx.Replace(AName, '<[^<>]*>', '');
end;

function IsInterfaceName(const AName: string): Boolean;
begin
  Result:= (Length(AName) > 1) and (AName[1] = 'I') and CharInSet(AName[2], ['A'..'Z']);
end;

{ ---- TFlowClass ---- }

constructor TFlowClass.Create;
begin
  inherited Create;
  FFields:= TDictionary<string, string>.Create;
end;

destructor TFlowClass.Destroy;
begin
  FFields.Free;
  inherited;
end;

{ ---- TFlowRun ---- }

constructor TFlowRun.Create(const ACtx: TV151FileCtx);
var
  Parsed: TParsedFile;
begin
  inherited Create;
  FCtx      := ACtx;
  FRoutines := TList<TTSNode>.Create;
  FCalls    := TList<TTSNode>.Create;
  FAddresses:= TList<TTSNode>.Create;
  FOverlays := TList<TTSNode>.Create;
  FTypes    := TDictionary<string, TTSNode>.Create;
  FManaged  := TDictionary<string, Boolean>.Create;
  FParams   := TDictionary<Int64, TV154ParamList>.Create;
  FFindings := TList<TLintFinding>.Create;
  Parsed    := TAstParseCache.Get(ACtx.Path);
  if Parsed.Tree = nil then Exit;
  FSrc:= Parsed.Src;
  Collect(Parsed.Tree.RootNode);
end;

destructor TFlowRun.Destroy;
begin
  FFindings.Free;
  FParams.Free;
  FEdges.Free;
  FManaged.Free;
  FClasses.Free;
  FTypes.Free;
  FOverlays.Free;
  FAddresses.Free;
  FCalls.Free;
  FRoutines.Free;
  inherited;
end;

function TFlowRun.Findings: TArray<TLintFinding>;
begin
  Result:= FFindings.ToArray;
end;

{ One cursor walk that compares node symbols, not node names: every unit of a project passes here. }
procedure TFlowRun.Collect(const ARoot: TTSNode);
var
  Cursor: TTSTreeCursor;
  Node  : TTSNode;
  DefProc, ExprCall, DeclType, At, Overlay: TSSymbol;

  function Symbol(const AName: string): TSSymbol;
  begin
    Result:= ARoot.Language.SymbolForName[AName, True];
  end;

  function Next: Boolean;
  begin
    Result:= Cursor.GotoFirstChild or Cursor.GotoNextSibling;
    while not Result do
    begin
      if not Cursor.GotoParent then Exit;
      Result:= Cursor.GotoNextSibling;
    end;
  end;

begin
  DefProc := Symbol('defProc');
  ExprCall:= Symbol('exprCall');
  DeclType:= Symbol('declType');
  At      := Symbol('kAt');
  Overlay := Symbol('kAbsolute');
  Cursor  := TTSTreeCursor.Create(ARoot);
  try
    repeat
      Node:= Cursor.CurrentNode;
      if Node.Symbol = DefProc then FRoutines.Add(Node)
      else if Node.Symbol = ExprCall then FCalls.Add(Node)
      else if Node.Symbol = DeclType then FTypes.AddOrSetValue(Lower(Node.ChildByField('name')), Node)
      else if Node.Symbol = At then FAddresses.Add(Node.Parent)
      else if Node.Symbol = Overlay then FOverlays.Add(Node.Parent);
    until not Next;
  finally
    Cursor.Free;
  end;
end;

procedure TFlowRun.Emit(const ARule, ASeverity, AMessage: string; const ANode: TTSNode);
var
  Finding: TLintFinding;
begin
  Finding:= Default(TLintFinding);
  Finding.RuleId   := ARule;
  Finding.Severity := ASeverity;
  Finding.Message  := AMessage;
  Finding.FilePath := FCtx.Path;
  Finding.StartLine:= Integer(ANode.StartPoint.Row) + 1;
  Finding.StartCol := TAstParseCache.CharCol(FCtx.Path, ANode.StartPoint);
  Finding.EndLine  := Integer(ANode.EndPoint.Row) + 1;
  Finding.EndCol   := TAstParseCache.CharCol(FCtx.Path, ANode.EndPoint);
  FFindings.Add(Finding);
end;

function TFlowRun.Text(const ANode: TTSNode): string;
begin
  Result:= NodeText(ANode, FSrc);
end;

function TFlowRun.Lower(const ANode: TTSNode): string;
begin
  Result:= LowerCase(Trim(Text(ANode)));
end;

function TFlowRun.Flat(const ANode: TTSNode): string;
begin
  Result:= FlatText(Text(ANode));
end;

{ ---- managed-result-read-first ---- }

{ AType is flat text. }
function TFlowRun.ManagedText(const AType: string; ADepth: Integer): Boolean;
var
  Name: string;
begin
  Name:= if StartsStr(SYSTEM_PREFIX, AType) then Copy(AType, Length(SYSTEM_PREFIX) + 1, MaxInt) else AType;
  if (Name = '') or (ADepth > MAX_DEPTH) then Exit(False);
  if MatchStr(Name, MANAGED_TYPES) or StartsStr('tarray<', Name) or StartsStr('arrayof', Name) or StartsStr('ansistring(', Name) then Exit(True);
  if (Name = 'shortstring') or Name.Contains('[') or Name.Contains('^') or Name.Contains('<') then Exit(False);
  if not FManaged.TryGetValue(Name, Result) then
  begin
    Result:= ManagedName(Name, ADepth + 1);
    FManaged.AddOrSetValue(Name, Result);
  end;
end;

{ A declared type name: this unit first, then the index, then the library; every row of the name must agree. }
function TFlowRun.ManagedName(const AType: string; ADepth: Integer): Boolean;
var
  Decl  : TTSNode;
  Symbol: TSymbol;
  Store : ISymbolStore;
begin
  Result:= False;
  if FTypes.TryGetValue(AType, Decl) then Exit(ManagedDecl(Decl, ADepth));
  for Store in [FCtx.Store, FCtx.LibStore] do
  begin
    if Store = nil then Continue;
    for Symbol in Store.FindSymbolsByExactName(AType) do
    begin
      if Symbol.Kind not in [skInterface, skTypeAlias, skClass, skRecord, skEnum, skClassRef] then Continue;
      Result:= (Symbol.Kind = skInterface) or ((Symbol.Kind = skTypeAlias) and ManagedText(FlatText(Symbol.Signature), ADepth));
      if not Result then Exit;
    end;
    if Result then Exit;
  end;
end;

function TFlowRun.ManagedDecl(const ADecl: TTSNode; ADepth: Integer): Boolean;
var
  I: Integer;
  Body: TTSNode;
begin
  Result:= HasChild(ADecl, ['declIntf']);
  for I:= 0 to ADecl.NamedChildCount - 1 do
  begin
    Body:= ADecl.NamedChild(I);
    if (Body.NodeType = 'type') and not HasChild(Body, ['declClass', 'declEnum', 'declSet', 'declProcRef', 'declMetaClass']) then
      Result:= HasChild(Body, ['declIntf']) or ManagedText(Flat(Body), ADepth);
  end;
end;

{ ANode is an identifier Result whose value is used: not a target, not @Result, not an argument the callee may fill. }
function TFlowRun.IsResultRead(const ANode: TTSNode): Boolean;
var
  Path, Call, Callee: TTSNode;
begin
  Path:= PathOf(ANode);
  if IsAssignTarget(Path) or IsAddressOf(Path.Parent) then Exit(False);
  Call:= CallOfArgument(Path);
  if Call.IsNull then Exit(True);
  Callee:= CalleeName(Call);
  Result:= (not Callee.IsNull) and MatchStr(Lower(Callee), READ_CALLS);
end;

procedure TFlowRun.AddResultReads(const ANode: TTSNode; AList: TList<TTSNode>);
var
  I: Integer;
begin
  if MatchStr(ANode.NodeType, ['defProc', 'lambda', 'type', 'typeref']) then Exit;
  if (ANode.NodeType = 'identifier') and (Lower(ANode) = RESULT_NAME) and (not IsMemberName(ANode)) and IsResultRead(ANode) then AList.Add(ANode);
  for I:= 0 to ANode.NamedChildCount - 1 do AddResultReads(ANode.NamedChild(I), AList);
end;

function TFlowRun.ResultReads(const ANode: TTSNode): TArray<TTSNode>;
var
  List: TList<TTSNode>;
begin
  List:= TList<TTSNode>.Create;
  try
    AddResultReads(ANode, List);
    Result:= List.ToArray;
  finally
    List.Free;
  end;
end;

{ The first statement of the body that names Result sets it: no graph needed. }
function TFlowRun.SetAtOnce(const ABody: TTSNode): Boolean;
var
  I: Integer;
  Node: TTSNode;
  Sites: TList<TTSNode>;
begin
  Result:= False;
  Sites := TList<TTSNode>.Create;
  try
    I:= 0;
    while (Sites.Count = 0) and (I < ABody.NamedChildCount) do
    begin
      Node:= ABody.NamedChild(I);
      AddUses(Node, RESULT_NAME, FSrc, Sites);
      Result:= (Sites.Count = 1) and (Node.NodeType = 'assignment') and (Node.ChildByField('lhs') = Sites[0]);
      Inc(I);
    end;
  finally
    Sites.Free;
  end;
end;

{ The conditions ANode stands under, an else marked. }
function TFlowRun.GuardsOf(const ARoutine, ANode: TTSNode): TArray<string>;
var
  Up  : TTSNode;
  I   : Integer;
  Part: string;
begin
  Result:= nil;
  Up    := ANode.Parent;
  while not (Up.IsNull or (Up = ARoutine)) do
  begin
    if MatchStr(Up.NodeType, IF_NODES) and (Up.NamedChild(1).EndByte <= ANode.StartByte) then
    begin
      Part:= Flat(Up.NamedChild(1));
      for I:= 0 to Up.NamedChildCount - 1 do
        if (Up.NamedChild(I).NodeType = 'kElse') and (Up.NamedChild(I).EndByte <= ANode.StartByte) then Part:= 'else ' + Part;
      Result:= Result + [Part];
    end;
    Up:= Up.Parent;
  end;
end;

{ An earlier assignment that sets Result from scratch stands under the same condition as the read. }
function TFlowRun.SameGuard(const ARoutine, ARead: TTSNode): Boolean;
var
  List: TList<TTSNode>;
  Node: TTSNode;
  Mine: TArray<string>;
  Part: string;
begin
  Result:= False;
  Mine  := GuardsOf(ARoutine, ARead);
  if Mine = nil then Exit;
  List:= TList<TTSNode>.Create;
  try
    AddUses(ARoutine.ChildByField('body'), RESULT_NAME, FSrc, List);
    for Node in List do
    begin
      if (Node.StartByte >= ARead.StartByte) or (not IsAssignTarget(Node)) then Continue;
      if Length(ResultReads(Node.Parent)) > 0 then Continue;
      for Part in GuardsOf(ARoutine, Node) do
        if MatchStr(Part, Mine) then Exit(True);
    end;
  finally
    List.Free;
  end;
end;

{ The same item fills Result before it reads it: Fill(Result) and (Result <> ''). }
function TFlowRun.FilledEarlier(const AItem, ARead: TTSNode): Boolean;
var
  List: TList<TTSNode>;
  Node: TTSNode;
begin
  Result:= False;
  List  := TList<TTSNode>.Create;
  try
    AddUses(AItem, RESULT_NAME, FSrc, List);
    for Node in List do
      if (Node.StartByte < ARead.StartByte) and (not IsResultRead(Node)) and (not IsAssignTarget(PathOf(Node))) then
        Result:= CallOfArgument(PathOf(Node)).IsNull or (CallOfArgument(PathOf(Node)).EndByte <= ARead.StartByte);
  finally
    List.Free;
  end;
end;

procedure TFlowRun.CheckResult(const ARoutine: TTSNode);
var
  Cfg  : TCfg;
  Vars : TRoutineVarTable;
  StateIn, StateOut: TArray<TDefAsgnVal>;
  Block: TCfgBlock;
  Item : TCfgItem;
  State: TDefAsgnVal;
  First: TTSNode;
  Slot : Integer;
  May  : Boolean;

  { What Item does on top of State: the transfer of a block of that single item. }
  procedure Step;
  var
    One: TCfgBlock;
    Lone: IDataFlowAnalysis<TDefAsgnVal>;
  begin
    One:= TCfgBlock.Create(0);
    try
      One.Items.Add(Item);
      Lone := TDefiniteAssignment.Create(Vars, FSrc);
      State:= Lone.Transfer(One, State);
    finally
      One.Free;
    end;
  end;

  procedure Judge;
  var
    Node: TTSNode;
  begin
    for Node in ResultReads(Item.Node) do
    begin
      if (not First.IsNull) and (First.StartByte <= Node.StartByte) then Continue;
      if FilledEarlier(Item.Node, Node) or (State.May[Slot] and SameGuard(ARoutine, Node)) then Continue;
      First:= Node;
      May  := State.May[Slot];
    end;
  end;

begin
  Cfg := TCfgBuilder.Build(ARoutine, FSrc, True);
  Vars:= TRoutineVarTable.Build(ARoutine, FSrc);
  try
    Slot:= Vars.IndexOf(RESULT_NAME);
    if Cfg.Skipped or (Slot < 0) or Vars.Get(Slot).Captured or (Vars.Get(Slot).Kind <> vkResult) then Exit;
    if not TDataFlowSolver<TDefAsgnVal>.Solve(Cfg, TDefiniteAssignment.Create(Vars, FSrc), StateIn, StateOut) then Exit;
    First:= Default(TTSNode);
    May  := False;
    for Block in Cfg.Blocks do
    begin
      State:= StateIn[Block.Index];
      for Item in Block.Items do
      begin
        if State.Must[Slot] then Break;
        if not Item.Opaque then Judge;
        Step;
      end;
    end;
    if First.IsNull then Exit;
    Emit(RULE_RESULT_FIRST, SEVERITY_WARNING, Format('Result (%s) is read before it is set%s: it is the caller''s variable and can hold an old value',
      [Text(Header(ARoutine).ChildByField('type')), if May then ' on every path' else '']), First);
  finally
    Vars.Free;
    Cfg.Free;
  end;
end;

procedure TFlowRun.CheckResults;
var
  Routine, Return, Body: TTSNode;
begin
  for Routine in FRoutines do
  begin
    Return:= Header(Routine).ChildByField('type');
    Body  := Routine.ChildByField('body');
    if Return.IsNull or Body.IsNull or (Body.NodeType <> 'block') then Continue;
    if SetAtOnce(Body) or (Length(ResultReads(Body)) = 0) or (not ManagedText(Flat(Return), 0)) then Continue;
    CheckResult(Routine);
  end;
end;

{ ---- same-variable-two-var-params ---- }

function SiteKey(ALine, ACol: Integer): string;
begin
  Result:= Format('%d:%d', [ALine, ACol]);
end;

{ The certain call edges of the file, read once. }
procedure TFlowRun.LoadEdges;
var
  Query: TFDQuery;
begin
  if FEdges <> nil then Exit;
  FEdges:= TDictionary<string, Int64>.Create;
  if (FCtx.Store is not TSQLiteSymbolStore) or (FCtx.FileId = 0) then Exit;
  Query:= TFDQuery.Create(nil);
  try
    Query.Connection:= (FCtx.Store as TSQLiteSymbolStore).GetConnection;
    Query.SQL.Text  := 'SELECT r.start_line, r.start_col, e.target_symbol_id FROM refs r JOIN call_edges e ON e.ref_id = r.id ' +
      'AND e.confidence = ''certain'' WHERE r.file_id = :f AND e.target_symbol_id IS NOT NULL';
    Query.ParamByName('f').AsLargeInt:= FCtx.FileId;
    Query.Open;
    while not Query.Eof do
    begin
      FEdges.AddOrSetValue(SiteKey(Query.Fields[0].AsInteger, Query.Fields[1].AsInteger), Query.Fields[2].AsLargeInt);
      Query.Next;
    end;
  finally
    Query.Free;
  end;
end;

{ The parameters of the exact callee; Known = False when the index does not name it or the call has more arguments. }
function TFlowRun.CalleeParams(const ACall: TTSNode): TV154ParamList;
var
  Name: TTSNode;
  Id  : Int64;
begin
  Result:= Default(TV154ParamList);
  LoadEdges;
  Name:= CalleeName(ACall);
  if Name.IsNull or not FEdges.TryGetValue(SiteKey(Integer(Name.StartPoint.Row) + 1, TAstParseCache.CharCol(FCtx.Path, Name.StartPoint)), Id) then Exit;
  if not FParams.TryGetValue(Id, Result) then
  begin
    Result:= V154RoutineParams(FCtx.Store, FCtx.Store.GetSymbolById(Id));
    FParams.Add(Id, Result);
  end;
  if Length(CallArguments(ACall)) > Length(Result.Params) then Result:= Default(TV154ParamList);
end;

{ One of the two can change or clear the variable while the other still stands for it. }
function TFlowRun.Conflict(const A, B: TV154Param): Boolean;

  function Clears(const AOut, AOther: TV154Param): Boolean;
  begin
    Result:= (AOut.Mode = pmOut) and (AOther.Mode = pmConst) and ManagedText(FlatText(AOut.TypeText), 0);
  end;

begin
  if A.IsUntyped or B.IsUntyped then Exit(False);
  Result:= (A.ByReference and B.ByReference) or Clears(A, B) or Clears(B, A);
end;

{ The variable an argument names, '' when it is something else. }
function TFlowRun.VariableText(const AArg: TTSNode): string;
begin
  Result:= '';
  if (not MatchStr(AArg.NodeType, ['identifier', 'exprDot', 'exprSubscript'])) or HasNode(AArg, ['exprCall', 'lambda']) then Exit;
  Result:= Flat(AArg);
  if StartsStr(SELF_PREFIX, Result) then Delete(Result, 1, Length(SELF_PREFIX));
end;

procedure TFlowRun.CheckCallArgs(const ACall: TTSNode);
var
  Args : TArray<TTSNode>;
  Names: TArray<string>;
  Params: TV154ParamList;
  I, J : Integer;
begin
  Args := CallArguments(ACall);
  Names:= nil;
  if Length(Args) < 2 then Exit;
  for I:= 0 to High(Args) do Names:= Names + [VariableText(Args[I])];
  for I:= 1 to High(Args) do
    for J:= 0 to I - 1 do
    begin
      if (Names[I] = '') or (Names[I] <> Names[J]) then Continue;
      Params:= CalleeParams(ACall);
      if not Params.Known then Exit;
      if not Conflict(Params.Params[J], Params.Params[I]) then Continue;
      Emit(RULE_SAME_VAR, SEVERITY_WARNING, Format('%s is passed to both "%s" and "%s" of %s: a write through one changes the other', [Text(Args[I]),
        Params.Params[J].Name, Params.Params[I].Name, Text(CalleeName(ACall))]), Args[I]);
      Exit;
    end;
end;

procedure TFlowRun.CheckArguments;
var
  Call: TTSNode;
begin
  if (FCtx.Store is not TSQLiteSymbolStore) or (FCtx.FileId = 0) then Exit;
  for Call in FCalls do CheckCallArgs(Call);
end;

{ ---- address-of-nested-routine ---- }

{ The routine that contains the nested routine AName visible at ANode; null when the name means something else. }
function TFlowRun.NestedOwner(const ANode: TTSNode; const AName: string): TTSNode;
var
  I: Integer;
  Decl, Child: TTSNode;
begin
  Result:= Enclosing(ANode);
  while not Result.IsNull do
  begin
    if Declares(Result, AName, FSrc, Decl) then Exit(Default(TTSNode));
    for I:= 0 to Result.NamedChildCount - 1 do
    begin
      Child:= Result.NamedChild(I);
      if (Child.NodeType = 'defProc') and (Lower(Header(Child).ChildByField('name')) = AName) then Exit;
    end;
    Result:= Enclosing(Result);
  end;
end;

procedure TFlowRun.CheckNestedAddresses;
var
  Node, Name, Owner: TTSNode;
  Sites: TList<TTSNode>;
begin
  Sites:= TList<TTSNode>.Create;
  try
    for Node in FAddresses do
      if IsAddressOf(Node) then Sites.Add(Node.NamedChild(Node.NamedChildCount - 1));
    for Node in FCalls do
      if (Lower(Node.ChildByField('entity')) = 'addr') and (Length(CallArguments(Node)) = 1) then Sites.Add(CallArguments(Node)[0]);
    for Name in Sites do
    begin
      if Name.NodeType <> 'identifier' then Continue;
      Owner:= NestedOwner(Name, Lower(Name));
      if Owner.IsNull then Continue;
      Emit(RULE_NESTED_ADDR, SEVERITY_WARNING, Format('Address of the nested routine %s: a call through the pointer lacks the hidden frame of %s ' +
        '(Win64 shifts the arguments; reading an outer local fails)', [Text(Name), Text(Header(Owner).ChildByField('name'))]), Name);
    end;
  finally
    Sites.Free;
  end;
end;

{ ---- what the index knows of a routine ---- }

function TFlowRun.RoutineSymbol(const ARoutine: TTSNode; out ASymbol: TSymbol): Boolean;
begin
  ASymbol:= Default(TSymbol);
  if (FCtx.Store is not TSQLiteSymbolStore) or (FCtx.FileId = 0) then Exit(False);
  ASymbol:= FCtx.Store.FindEnclosingRoutineByImpl(FCtx.FileId, Integer(ARoutine.StartPoint.Row) + 1);
  Result := (ASymbol.Id > 0) and SameText(LastName(Lower(Header(ARoutine).ChildByField('name'))), ASymbol.Name);
end;

function TFlowRun.HasRows(const ASql, AName: string): Boolean;
var
  Query: TFDQuery;
begin
  Query:= TFDQuery.Create(nil);
  try
    Query.Connection:= (FCtx.Store as TSQLiteSymbolStore).GetConnection;
    Query.SQL.Text  := ASql;
    Query.ParamByName('n').AsString:= AName;
    Query.Open;
    Result:= not Query.Eof;
  finally
    Query.Free;
  end;
end;

{ A method a form file, an interface or a class with interfaces may dictate. }
function TFlowRun.MethodFixed(const ASymbol: TSymbol): Boolean;
begin
  if (ASymbol.Kind <> skMethod) or (not MatchStr(Trim(ASymbol.Modifiers), CODE_VISIBILITY)) then Exit(True);
  Result:= FCtx.Store.GetSymbolById(ASymbol.ParentId).Heritage.Contains(',') or
    HasRows('SELECT 1 FROM symbols m JOIN symbols i ON i.id = m.parent_id AND i.kind = ''interface'' WHERE m.name = :n COLLATE NOCASE LIMIT 1', ASymbol.Name);
end;

{ Somebody else dictates the signature: a directive, an event, an interface, or the routine is used as a value. }
function TFlowRun.SignatureFixed(const ASymbol: TSymbol): Boolean;
var
  Directive: string;
begin
  Result:= True;
  if ASymbol.IsVirtual or FlatText(ASymbol.Signature).Contains(EVENT_PARAM) then Exit;
  for Directive in SplitString(ASymbol.Directives, ' ') do
    if MatchStr(Directive, FIXED_DIRECTIVES) then Exit;
  if (ASymbol.Kind not in [skProcedure, skFunction]) and MethodFixed(ASymbol) then Exit;
  Result:= HasRows('SELECT 1 FROM refs r WHERE r.name_text = :n COLLATE NOCASE AND r.kind <> ''call'' ' +
    'AND NOT EXISTS (SELECT 1 FROM call_edges e WHERE e.ref_id = r.id) LIMIT 1', ASymbol.Name);
end;

{ ---- var-param-never-written ---- }

{ The callee, or the index, only reads the argument APath. }
function TFlowRun.ArgumentOnlyRead(const APath, AArgs: TTSNode): Boolean;
var
  Call : TTSNode;
  Args : TArray<TTSNode>;
  Params: TV154ParamList;
  I    : Integer;
begin
  Call:= AArgs.Parent;
  if Call.NodeType <> 'exprCall' then Exit(Call.NodeType = 'exprSubscript');
  if MatchStr(Lower(Call.ChildByField('entity')), READ_CALLS) then Exit(True);
  Params:= CalleeParams(Call);
  Result:= False;
  if not Params.Known then Exit;
  Args:= CallArguments(Call);
  for I:= 0 to High(Args) do
    if Args[I] = APath then Result:= (Params.ModeAt(I) in [pmValue, pmConst]) and (not Params.Params[I].IsUntyped);
end;

{ Naming AName of AType cannot change the variable: a class reference, or a field of a record (a method could change it). }
function TFlowRun.MemberOnlyRead(const AName, AType: string): Boolean;
var
  Symbol: TSymbol;
begin
  case FCtx.Store.ResolveTypeCategory(AType, FCtx.FileId) of
    tcClass, tcInterface: Result:= True;
    tcRecord:
      begin
        Symbol:= FCtx.Store.ResolveTypeNameToClass(AType, FCtx.FileId);
        Result:= (Symbol.Id > 0) and (FCtx.Store.FindChildSymbolByName(Symbol.Id, AName).Kind = skField);
      end;
  else
    Result:= False;
  end;
end;

function TFlowRun.UseOnlyReads(const AUse: TTSNode; const AType: string): Boolean;
var
  Path, Up: TTSNode;
begin
  Path:= PathOf(AUse);
  Up  := Path.Parent;
  if IsAssignTarget(Path) or IsAddressOf(Up) or MatchStr(Up.NodeType, ['with', 'inherited', 'exprParens']) then Exit(False);
  if (Up.NodeType = 'foreach') and (Up.NamedChild(1) = Path) then Exit(False);
  if (AUse.Parent.NodeType = 'exprDot') and (not MemberOnlyRead(Text(AUse.Parent.ChildByField('rhs')), AType)) then Exit(False);
  Result:= (Up.NodeType <> 'exprArgs') or ArgumentOnlyRead(Path, Up);
end;

procedure TFlowRun.CheckVarParam(const ARoutine, AName: TTSNode; const AType: string);
var
  List: TList<TTSNode>;
  Use : TTSNode;
  Symbol: TSymbol;
  Params: TV154ParamList;
  Index : Integer;
begin
  List:= TList<TTSNode>.Create;
  try
    AddUses(ARoutine, Text(AName), FSrc, List);
    if List.Count = 0 then Exit;
    for Use in List do
      if not UseOnlyReads(Use, AType) then Exit;
  finally
    List.Free;
  end;
  if not RoutineSymbol(ARoutine, Symbol) then Exit;
  Params:= V154RoutineParams(FCtx.Store, Symbol);
  Index := Params.IndexOf(Text(AName));
  if (Index < 0) or (Params.Params[Index].Mutated = vmListed) or SignatureFixed(Symbol) then Exit;
  Emit(RULE_VAR_UNWRITTEN, SEVERITY_HINT, Format('The var parameter "%s" of %s is never written: pass it by value or const',
    [Text(AName), Symbol.Name]), AName);
end;

procedure TFlowRun.CheckVarParams;
var
  Routine, Arg, Name: TTSNode;
begin
  if (FCtx.Store is not TSQLiteSymbolStore) or (FCtx.FileId = 0) then Exit;
  for Routine in FRoutines do
    for Arg in Arguments(Routine) do
    begin
      if Arg.ChildByField('type').IsNull or (not HasChild(Arg, ['kVar'])) or HasNode(Routine, ASM_NODES) then Continue;
      for Name in DeclaredNames(Arg) do CheckVarParam(Routine, Name, Trim(Text(Arg.ChildByField('type'))));
    end;
end;

{ ---- value-param-assigned ---- }

function TFlowRun.SetsParam(const AUse: TTSNode): Boolean;
var
  Call: TTSNode;
begin
  if IsAssignTarget(AUse) then Exit(True);
  Call  := CallOfArgument(AUse);
  Result:= (not Call.IsNull) and MatchStr(Lower(Call.ChildByField('entity')), INC_CALLS) and (CallArguments(Call)[0] = AUse);
end;

procedure TFlowRun.CheckValueParam(const ARoutine, AName: TTSNode);
var
  List: TList<TTSNode>;
  Use : TTSNode;
begin
  List:= TList<TTSNode>.Create;
  try
    AddUses(ARoutine, Text(AName), FSrc, List);
    for Use in List do
    begin
      if not SetsParam(Use) then Continue;
      Emit(RULE_VALUE_SET, SEVERITY_HINT, Format('The by-value parameter "%s" is used as a local variable: the caller does not see the new value',
        [Text(AName)]), Use);
      Exit;
    end;
  finally
    List.Free;
  end;
end;

procedure TFlowRun.CheckValueParams;
var
  Routine, Arg, Name: TTSNode;
begin
  for Routine in FRoutines do
    for Arg in Arguments(Routine) do
      if not HasChild(Arg, ['kVar', 'kOut', 'kConst', 'kConstref']) then
        for Name in DeclaredNames(Arg) do CheckValueParam(Routine, Name);
end;

{ ---- constant-return ---- }

{ The value ANode makes the function return: Exit(V), Result := V, Name := V; null for any other node. }
function TFlowRun.ReturnedValue(const ANode: TTSNode; const AOwnName: string): TTSNode;
begin
  Result:= Default(TTSNode);
  if ANode.NodeType = 'assignment' then
  begin
    if MatchStr(Lower(ANode.ChildByField('lhs')), [RESULT_NAME, AOwnName]) then Result:= ANode.ChildByField('rhs');
  end
  else if (ANode.NodeType = 'exprCall') and (Lower(ANode.ChildByField('entity')) = 'exit') and (Length(CallArguments(ANode)) = 1) then
    Result:= CallArguments(ANode)[0];
end;

{ Every value the function can return; ABad when one is not a literal, it raises, or Result is used in any other way. }
procedure TFlowRun.AddConstants(const ANode: TTSNode; const AOwnName: string; AValues: TList<string>; var ABad: Boolean);
var
  I: Integer;
  Value: TTSNode;
begin
  Value:= ReturnedValue(ANode, AOwnName);
  if not Value.IsNull then
  begin
    ABad:= ABad or (not MatchStr(Value.NodeType, LITERAL_NODES));
    AValues.Add(if Value.NodeType = 'literalString' then Text(Value) else Flat(Value));
    Exit;
  end;
  if (ANode.NodeType = 'raise') or ((ANode.NodeType = 'identifier') and (Lower(ANode) = RESULT_NAME) and (not IsMemberName(ANode))) then ABad:= True;
  for I:= 0 to ANode.NamedChildCount - 1 do AddConstants(ANode.NamedChild(I), AOwnName, AValues, ABad);
end;

procedure TFlowRun.CheckConstant(const ARoutine: TTSNode);
var
  Values: TList<string>;
  Symbol: TSymbol;
  Name, Value: string;
  Bad   : Boolean;
  I     : Integer;
begin
  Name  := LastName(Lower(Header(ARoutine).ChildByField('name')));
  Bad   := HasNode(ARoutine, ASM_NODES);
  Values:= TList<string>.Create;
  try
    for I:= 0 to ARoutine.NamedChildCount - 1 do
      if ARoutine.NamedChild(I).NodeType <> 'declProc' then AddConstants(ARoutine.NamedChild(I), Name, Values, Bad);
    if Bad or (Values.Count <= 1) then Exit;
    for Value in Values do
      if Value <> Values[0] then Exit;
    if (not RoutineSymbol(ARoutine, Symbol)) or SignatureFixed(Symbol) then Exit;
    Emit(RULE_CONST_RETURN, SEVERITY_HINT, Format('%s returns %s at each of its %d places: a branch does not do what it says, or the function needs no result',
      [Symbol.Name, Values[0], Values.Count]), Header(ARoutine).ChildByField('name'));
  finally
    Values.Free;
  end;
end;

procedure TFlowRun.CheckConstants;
var
  Routine: TTSNode;
begin
  if (FCtx.Store is not TSQLiteSymbolStore) or (FCtx.FileId = 0) then Exit;
  for Routine in FRoutines do
    if (not Header(Routine).ChildByField('type').IsNull) and (not Routine.ChildByField('body').IsNull) and
       (not HasChild(Header(Routine), ['kOperator'])) then
      CheckConstant(Routine);
end;

{ ---- redundant-field-init ---- }

procedure TFlowRun.ReadMembers(const ANode: TTSNode; AInfo: TFlowClass);
var
  I: Integer;
  Child, Name: TTSNode;
begin
  for I:= 0 to ANode.NamedChildCount - 1 do
  begin
    Child:= ANode.NamedChild(I);
    if (Child.NodeType = 'declSection') or ((Child.NodeType = 'declVars') and (not HasChild(Child, ['kClass']))) then ReadMembers(Child, AInfo)
    else if MatchStr(Child.NodeType, ['declField', 'declFieldNoSemi', 'declVar']) then
    begin
      for Name in DeclaredNames(Child) do AInfo.Fields.AddOrSetValue(Lower(Name), Flat(Child.ChildByField('type')));
    end
    else if Child.NodeType = 'declProc' then
    begin
      if Lower(Child.ChildByField('name')) = 'newinstance' then AInfo.OwnMemory:= True;
      if HasNode(Child, ['kOverride', 'kMessage', 'kVirtual', 'kDynamic']) and (not HasChild(Child, ['kConstructor', 'kDestructor'])) then AInfo.Hooked:= True;
    end
    else if (Child.NodeType = 'typeref') and IsInterfaceName(Text(Child)) then AInfo.Hooked:= True;
  end;
end;

{ ADecl is a declType; a nested class is keyed touter.tinner. }
procedure TFlowRun.AddClass(const ADecl: TTSNode);
var
  Body, Outer: TTSNode;
  Info: TFlowClass;
  Name: string;
begin
  Body:= ADecl.ChildByField('type');
  if (not Body.IsNull) and (Body.NodeType = 'type') and (Body.NamedChildCount > 0) then Body:= Body.NamedChild(0);
  if Body.IsNull or (Body.NodeType <> 'declClass') or HasChild(Body, ['kRecord', 'kObject']) then Exit;
  Name := Flat(ADecl.ChildByField('name'));
  Outer:= ADecl.Parent;
  while not Outer.IsNull do
  begin
    if Outer.NodeType = 'declType' then Name:= Flat(Outer.ChildByField('name')) + '.' + Name;
    Outer:= Outer.Parent;
  end;
  Info:= TFlowClass.Create;
  FClasses.AddOrSetValue(WithoutGenerics(Name), Info);
  ReadMembers(Body, Info);
end;

{ A routine of the class other than its constructors and destructor names AField. }
function TFlowRun.NamedElsewhere(const AClass, AField: string): Boolean;
var
  Routine: TTSNode;
  List: TList<TTSNode>;
begin
  List:= TList<TTSNode>.Create;
  try
    for Routine in FRoutines do
      if StartsStr(AClass + '.', WithoutGenerics(Flat(Header(Routine).ChildByField('name')))) and
         (not HasChild(Header(Routine), ['kConstructor', 'kDestructor'])) then
        AddUses(Routine, AField, FSrc, List);
    Result:= List.Count > 0;
  finally
    List.Free;
  end;
end;

{ ANode runs no routine of the class by itself. AOutside = it runs other code, which may call back. }
function TFlowRun.PlainValue(const ANode, ARoutine: TTSNode; var AOutside: Boolean): Boolean;
var
  Arg, Decl: TTSNode;
begin
  if MatchStr(ANode.NodeType, LITERAL_NODES) then Exit(True);
  if ANode.NodeType = 'identifier' then Exit((Lower(ANode) = SELF_NAME) or Declares(ARoutine, Text(ANode), FSrc, Decl));
  AOutside:= True;
  if ANode.NodeType = 'exprDot' then Exit(SameText(Text(ANode.ChildByField('rhs')), 'Create'));
  Result:= (ANode.NodeType = 'exprCall') and PlainValue(ANode.ChildByField('entity'), ARoutine, AOutside);
  if Result then
    for Arg in CallArguments(ANode) do Result:= Result and PlainValue(Arg, ARoutine, AOutside);
end;

{ inherited, inherited Create(plain values) }
function TFlowRun.PlainInherited(const ANode, ARoutine: TTSNode; var AOutside: Boolean): Boolean;
var
  Arg, Call: TTSNode;
begin
  Result  := True;
  AOutside:= True;
  Call    := ANode.NamedChild(0);
  if Call.NodeType = 'exprCall' then
    for Arg in CallArguments(Call) do Result:= Result and PlainValue(Arg, ARoutine, AOutside);
end;

{ Reads the first statements of the constructor, as long as each is an inherited call or a plain assignment. }
procedure TFlowRun.CheckConstructor(const ARoutine: TTSNode);
var
  Info : TFlowClass;
  Body, Node, Target, Value, Decl: TTSNode;
  Name, Field, FieldType: string;
  I    : Integer;
  Plain, Outside, Fresh: Boolean;
  Seen : TArray<string>;
begin
  Name:= WithoutGenerics(Flat(Header(ARoutine).ChildByField('name')));
  Name:= Copy(Name, 1, LastDelimiter('.', Name) - 1);
  Body:= ARoutine.ChildByField('body');
  if Body.IsNull or (not FClasses.TryGetValue(Name, Info)) or Info.OwnMemory then Exit;
  Outside:= False;
  Plain  := True;
  Seen   := nil;
  I      := 0;
  while Plain and (I < Body.NamedChildCount) do
  begin
    Node:= Body.NamedChild(I);
    Inc(I);
    if MatchStr(Node.NodeType, ['kBegin', 'kEnd', 'comment']) then Continue;
    if (Node.NodeType = 'statement') and HasNode(Node, ['inherited']) then
    begin
      Plain:= PlainInherited(Node, ARoutine, Outside);
      Continue;
    end;
    if Node.NodeType <> 'assignment' then Exit;
    Target:= Node.ChildByField('lhs');
    Value := Node.ChildByField('rhs');
    Field := Flat(Target);
    if StartsStr(SELF_PREFIX, Field) then Delete(Field, 1, Length(SELF_PREFIX))
    else if Declares(ARoutine, Field, FSrc, Decl) then Continue;
    if not Info.Fields.TryGetValue(Field, FieldType) then Exit;
    Fresh:= (not MatchStr(Field, Seen)) and not (Outside and (Info.Hooked or (FCtx.DfmPath <> '')) and NamedElsewhere(Name, Field));
    if Fresh and MatchStr(Flat(Value), ZERO_VALUES) and (FieldType <> 'variant') then
      Emit(RULE_FIELD_INIT, SEVERITY_HINT, Format('%s of a new object is already %s: the constructor need not set it', [Text(Target), Text(Value)]), Target);
    Seen := Seen + [Field];
    Plain:= PlainValue(Value, ARoutine, Outside);
  end;
end;

procedure TFlowRun.CheckFieldInits;
var
  Decl, Routine: TTSNode;
begin
  FreeAndNil(FClasses);
  FClasses:= TObjectDictionary<string, TFlowClass>.Create([doOwnsValues]);
  for Decl in FTypes.Values do AddClass(Decl);
  if FClasses.Count = 0 then Exit;
  for Routine in FRoutines do
    if HasChild(Header(Routine), ['kConstructor']) and (not HasChild(Header(Routine), ['kClass'])) then CheckConstructor(Routine);
end;

{ ---- absolute-overlay ---- }

{ The target is an untyped parameter: the overlay is the only way to give it a type. }
function TFlowRun.OverUntyped(const AOverlay, ATarget: TTSNode): Boolean;
var
  Routine, Decl: TTSNode;
begin
  Result := False;
  Routine:= Enclosing(AOverlay);
  while not Routine.IsNull do
  begin
    if Declares(Routine, Text(ATarget), FSrc, Decl) then Exit((Decl.NodeType = 'declArg') and Decl.ChildByField('type').IsNull);
    Routine:= Enclosing(Routine);
  end;
end;

procedure TFlowRun.CheckOverlays;
var
  Overlay, Target, Name: TTSNode;
  I: Integer;
begin
  for Overlay in FOverlays do
  begin
    Target:= Default(TTSNode);
    for I:= 0 to Overlay.NamedChildCount - 2 do
      if Overlay.NamedChild(I).NodeType = 'kAbsolute' then Target:= Overlay.NamedChild(I + 1);
    if Target.IsNull or OverUntyped(Overlay, Target) then Continue;
    for Name in DeclaredNames(Overlay) do
      Emit(RULE_OVERLAY, SEVERITY_HINT, Format('%s (%s) shares the memory of %s through absolute: no conversion and no size check', [Text(Name),
        Text(Overlay.ChildByField('type')), Text(Target)]), Name);
  end;
end;

end.
