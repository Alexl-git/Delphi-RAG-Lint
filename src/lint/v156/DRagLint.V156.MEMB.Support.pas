unit DRagLint.V156.MEMB.Support;

{ Wave v156 lane MEM-B -- helpers of DRagLint.V156.MEMB (private to the lane): one walker per linted unit.
  fresh-instance-as-argument and class-passed-as-interface read the exact callee from call_edges, its
  parameter from DRagLint.V154.ParamModes and what the callee does with the parameter from the callee's own
  syntax tree (data_flows cannot tell `Keep(AFoo)` from `Writeln(AFoo.Name)`: both are an 'arg' row).
  The stored form of indexof-result-unchecked needs the syntax tree only. }

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
  /// <summary>Rule id of G-11: an EXISTING id, it moved here from the .scm rule and keeps its name.</summary>
  RULE_FRESH_INSTANCE_AS_ARGUMENT = 'fresh-instance-as-argument';
  /// <summary>Rule id of G-11: an object of a reference-counted class handed to an interface parameter.</summary>
  RULE_CLASS_PASSED_AS_INTERFACE = 'class-passed-as-interface';
  /// <summary>Host rule id of G-63 (the .scm rule reports the inline form, this lane the stored form).</summary>
  RULE_INDEXOF_RESULT_UNCHECKED = 'indexof-result-unchecked';

type
  /// <summary>Answer of an ancestry question that the index may be unable to decide.</summary>
  TMembAnswer = (maNo, maYes, maUnknown);

  /// <summary>One run of the lane over one parsed unit.</summary>
  /// <remarks>Create, call the Check methods, Free. Not thread-safe. The node lists are collected once, in Create.
  /// CheckArguments reports nothing without a project index (ACtx.Store) that knows the file.</remarks>
  TMembRun = class
  strict private
    FCtx     : TV151FileCtx;
    FSrc     : TBytes;
    FCalls   : TList<TTSNode>;
    FAssigns : TList<TTSNode>;
    FEdges   : TDictionary<string, Int64>;
    FParams  : TDictionary<Int64, TV154ParamList>;
    FReadOnly: TDictionary<string, Boolean>;
    FCategories: TDictionary<string, TTypeCategory>;
    FFindings: TList<TLintFinding>;
    procedure Collect(const ARoot: TTSNode);
    procedure Emit(const ARule, ASeverity, AMessage: string; const ANode: TTSNode);
    function Text(const ANode: TTSNode): string;
    procedure LoadEdges;
    function Callee(const ACall: TTSNode; out ASymbol: TSymbol; out AParams: TV154ParamList): Boolean;
    function Category(const AType: string; AFileId: Int64): TTypeCategory;
    function Descends(const AClass, AAncestor: string): TMembAnswer;
    function CountsItself(const AClass: string): Boolean;
    function ReferenceCounted(const AClass: string): Boolean;
    function FreshClass(const AArg: TTSNode): string;
    function OwnedByComponent(const AArg: TTSNode; const AClass: string): Boolean;
    function CalleeOnlyReads(const ACallee: TSymbol; const AParam: string): Boolean;
    function VariableClass(const AArg, ACall: TTSNode): string;
    procedure CheckFresh(const AArg, ACall: TTSNode; const ACallee: TSymbol; const AParam: TV154Param);
    procedure CheckInterface(const AArg, ACall: TTSNode; const AParam: TV154Param);
    procedure CheckCall(const ACall: TTSNode; AFresh, AInterface: Boolean);
    procedure CheckStoredIndex(const AAssign: TTSNode);
  public
    /// <summary>Parses (or takes from the parse cache) the unit of ACtx and collects its calls and assignments.</summary>
    /// <param name="ACtx">The file being linted; Store / LibStore may be nil.</param>
    constructor Create(const ACtx: TV151FileCtx);
    /// <summary>Frees the node lists and the findings list.</summary>
    destructor Destroy; override;
    /// <summary>Checks every call argument of the unit against the exact callee's parameter.</summary>
    /// <param name="AFresh">Report fresh-instance-as-argument: `TFoo.Create` handed to a class parameter that the callee only reads.</param>
    /// <param name="AInterface">Report class-passed-as-interface: an object of a reference-counted class handed to an interface
    /// parameter, either created in the argument of a const parameter, or held in a variable that is used after the call.</param>
    /// <remarks>Silent when the call has no certain call edge, the callee's parameters are not known, the callee is virtual
    /// or has no body in the index, or the class ancestry cannot be decided.</remarks>
    procedure CheckArguments(AFresh, AInterface: Boolean);
    /// <summary>Reports a local variable that takes an IndexOf-family result and is then used as an index
    /// (subscript, Delete, Exchange) with no mention of the variable in between.</summary>
    /// <remarks>Syntax tree only. Silent when the assignment stands in a loop.</remarks>
    procedure CheckStoredIndexes;
    /// <summary>The findings of the Check methods called so far.</summary>
    /// <returns>A copy; empty when nothing was found.</returns>
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
  , DRagLint.Analysis.Flow.Lattices
  ;

const
  SEVERITY_INFO = 'info';
  SEVERITY_WARNING = 'warning';
  ROUTINE_NODES: array[0..1] of string = ('defProc', 'lambda');
  LOOP_NODES: array[0..3] of string = ('while', 'for', 'foreach', 'repeat');
  CONSTRUCTOR_PREFIX = 'Create';
  NIL_TEXT = 'nil';
  COMPONENT_CLASS = 'TComponent';
  COUNTED_CLASS = 'TInterfacedObject';
  ADDREF_METHOD = '_AddRef';
  { ancestry leaves that end a chain without a library index }
  ROOT_TYPES: array[0..3] of string = ('TObject', 'TInterfacedObject', 'IInterface', 'IUnknown');
  { members that end the life of their receiver }
  RELEASE_MEMBERS: array[0..3] of string = ('free', 'destroy', 'disposeof', 'freeinstance');
  { comparisons read a reference and keep nothing }
  READ_OPERATORS: array[0..2] of string = ('kEq', 'kNeq', 'kIs');
  READ_CALLS: array[0..1] of string = ('assigned', 'system.assigned');
  INDEX_CALLS: array[0..6] of string = ('indexof', 'indexofname', 'indexofobject', 'pos', 'posex', 'lastindexof', 'findindex');
  INDEX_USERS: array[0..1] of string = ('delete', 'exchange');

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

function LowerText(const ANode: TTSNode; const ASrc: TBytes): string;
begin
  Result:= LowerCase(Trim(NodeText(ANode, ASrc)));
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

{ The declared names of a declArg / declVar: the identifiers before its type. }
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

{ The declArg nodes of a routine or an anonymous method. }
function Arguments(const ARoutine: TTSNode): TArray<TTSNode>;
var
  Args: TTSNode;
  I   : Integer;
begin
  Result:= nil;
  Args  := ARoutine.ChildByField('header');
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

{ The written type of a declArg / declVar; '' when it has none. }
function DeclaredType(const ADecl: TTSNode; const ASrc: TBytes): string;
var
  I: Integer;
begin
  Result:= '';
  for I:= 0 to ADecl.NamedChildCount - 1 do
    if ADecl.NamedChild(I).NodeType = 'type' then Exit(Trim(NodeText(ADecl.NamedChild(I), ASrc)));
end;

{ Uses of AName under ANode: headers, types and nested routines that declare the name again are left out. }
procedure AddUses(const ANode: TTSNode; const AName: string; const ASrc: TBytes; AList: TList<TTSNode>);
var
  I: Integer;
  Decl, Child: TTSNode;
begin
  if (ANode.NodeType = 'identifier') and SameText(NodeText(ANode, ASrc), AName) and (not IsMemberName(ANode)) then AList.Add(ANode);
  for I:= 0 to ANode.NamedChildCount - 1 do
  begin
    Child:= ANode.NamedChild(I);
    if MatchStr(Child.NodeType, ['declProc', 'declVars', 'type', 'typeref']) then Continue;
    if MatchStr(Child.NodeType, ROUTINE_NODES) and Declares(Child, AName, ASrc, Decl) then Continue;
    AddUses(Child, AName, ASrc, AList);
  end;
end;

function LastName(const AName: string): string;
begin
  Result:= Copy(AName, LastDelimiter('.', AName) + 1, MaxInt);
end;

{ TFoo<T>.TBar -> TFoo.TBar }
function WithoutGenerics(const AName: string): string;
begin
  Result:= TRegEx.Replace(AName, '<[^<>]*>', '');
end;

function LooksLikeClass(const AName: string): Boolean;
begin
  Result:= (Length(AName) > 1) and (AName[1] = 'T') and CharInSet(AName[2], ['A'..'Z']);
end;

{ The first routine of the tree that starts inside the given lines; null when there is none. }
function RoutineAt(const ANode: TTSNode; AFirstLine, ALastLine: Integer): TTSNode;
var
  I, Line: Integer;
begin
  Result:= Default(TTSNode);
  if (Integer(ANode.EndPoint.Row) + 1 < AFirstLine) or (Integer(ANode.StartPoint.Row) + 1 > ALastLine) then Exit;
  Line:= Integer(ANode.StartPoint.Row) + 1;
  if (ANode.NodeType = 'defProc') and (Line >= AFirstLine) then Exit(ANode);
  for I:= 0 to ANode.NamedChildCount - 1 do
  begin
    Result:= RoutineAt(ANode.NamedChild(I), AFirstLine, ALastLine);
    if not Result.IsNull then Exit;
  end;
end;

{ The use reads the reference and keeps nothing: a member other than Free, a comparison, Assigned(). }
function ReadOnlyUse(const AUse: TTSNode; const ASrc: TBytes): Boolean;
var
  Node, Up: TTSNode;
begin
  Node:= AUse;
  Up  := Node.Parent;
  while Up.NodeType = 'exprParens' do
  begin
    Node:= Up;
    Up  := Node.Parent;
  end;
  if Up.NodeType = 'exprDot' then
    Result:= (Up.ChildByField('lhs') = Node) and (not MatchStr(LowerText(Up.ChildByField('rhs'), ASrc), RELEASE_MEMBERS))
  else if Up.NodeType = 'exprBinary' then Result:= MatchStr(Up.ChildByField('operator').NodeType, READ_OPERATORS)
  else if (Up.NodeType = 'exprArgs') and (Up.Parent.NodeType = 'exprCall') then
    Result:= MatchStr(LowerText(Up.Parent.ChildByField('entity'), ASrc), READ_CALLS)
  else Result:= False;
end;

{ TTSNode has an Equal operator and no NotEqual. }
function SameNode(const A, B: TTSNode): Boolean;
begin
  Result:= A = B;
end;

function InLoop(const ANode, ARoutine: TTSNode): Boolean;
var
  Up: TTSNode;
begin
  Result:= False;
  Up    := ANode.Parent;
  while (not Up.IsNull) and (not SameNode(Up, ARoutine)) do
  begin
    if MatchStr(Up.NodeType, LOOP_NODES) then Exit(True);
    Up:= Up.Parent;
  end;
end;

function SiteKey(ALine, ACol: Integer): string;
begin
  Result:= Format('%d:%d', [ALine, ACol]);
end;

{ ---- TMembRun ---- }

constructor TMembRun.Create(const ACtx: TV151FileCtx);
var
  Parsed: TParsedFile;
begin
  inherited Create;
  FCtx     := ACtx;
  FCalls   := TList<TTSNode>.Create;
  FAssigns := TList<TTSNode>.Create;
  FParams  := TDictionary<Int64, TV154ParamList>.Create;
  FReadOnly:= TDictionary<string, Boolean>.Create;
  FCategories:= TDictionary<string, TTypeCategory>.Create;
  FFindings:= TList<TLintFinding>.Create;
  Parsed   := TAstParseCache.Get(ACtx.Path);
  if Parsed.Tree = nil then Exit;
  FSrc:= Parsed.Src;
  Collect(Parsed.Tree.RootNode);
end;

destructor TMembRun.Destroy;
begin
  FFindings.Free;
  FCategories.Free;
  FReadOnly.Free;
  FParams.Free;
  FEdges.Free;
  FAssigns.Free;
  FCalls.Free;
  inherited;
end;

function TMembRun.Findings: TArray<TLintFinding>;
begin
  Result:= FFindings.ToArray;
end;

{ One cursor walk that compares node symbols, not node names: every unit of a project passes here. }
procedure TMembRun.Collect(const ARoot: TTSNode);
var
  Cursor: TTSTreeCursor;
  Node  : TTSNode;
  ExprCall, Assignment: TSSymbol;

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
  ExprCall  := ARoot.Language.SymbolForName['exprCall', True];
  Assignment:= ARoot.Language.SymbolForName['assignment', True];
  Cursor    := TTSTreeCursor.Create(ARoot);
  try
    repeat
      Node:= Cursor.CurrentNode;
      if Node.Symbol = ExprCall then FCalls.Add(Node)
      else if Node.Symbol = Assignment then FAssigns.Add(Node);
    until not Next;
  finally
    Cursor.Free;
  end;
end;

procedure TMembRun.Emit(const ARule, ASeverity, AMessage: string; const ANode: TTSNode);
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

function TMembRun.Text(const ANode: TTSNode): string;
begin
  Result:= NodeText(ANode, FSrc);
end;

{ ---- the exact callee ---- }

{ The certain call edges of the file, read once. }
procedure TMembRun.LoadEdges;
var
  Query: TFDQuery;
begin
  if FEdges <> nil then Exit;
  FEdges:= TDictionary<string, Int64>.Create;
  Query := TFDQuery.Create(nil);
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

{ The exact callee and its parameters; False when the index does not name it or the call has more arguments. }
function TMembRun.Callee(const ACall: TTSNode; out ASymbol: TSymbol; out AParams: TV154ParamList): Boolean;
var
  Name: TTSNode;
  Id  : Int64;
begin
  ASymbol:= Default(TSymbol);
  AParams:= Default(TV154ParamList);
  LoadEdges;
  Name:= CalleeName(ACall);
  if Name.IsNull or not FEdges.TryGetValue(SiteKey(Integer(Name.StartPoint.Row) + 1, TAstParseCache.CharCol(FCtx.Path, Name.StartPoint)), Id) then
    Exit(False);
  ASymbol:= FCtx.Store.GetSymbolById(Id);
  if not FParams.TryGetValue(Id, AParams) then
  begin
    AParams:= V154RoutineParams(FCtx.Store, ASymbol);
    FParams.Add(Id, AParams);
  end;
  Result:= AParams.Known and (Length(CallArguments(ACall)) <= Length(AParams.Params));
end;

{ ---- types ---- }

{ Class, interface or something else: the project index, then the library, remembered per name and file. }
function TMembRun.Category(const AType: string; AFileId: Int64): TTypeCategory;
var
  Key: string;
begin
  Key:= Format('%d:%s', [AFileId, LowerCase(AType)]);
  if FCategories.TryGetValue(Key, Result) then Exit;
  Result:= FCtx.Store.ResolveTypeCategory(AType, AFileId);
  if (Result = tcUnknown) and (FCtx.LibStore <> nil) then Result:= FCtx.LibStore.ResolveTypeCategory(AType, 0);
  if (Result = tcUnknown) and SameText(AType, ROOT_TYPES[0]) then Result:= tcClass;
  FCategories.Add(Key, Result);
end;

{ Is AAncestor in the ancestry of AClass: the project chain first, then each of its open ends in the library. }
function TMembRun.Descends(const AClass, AAncestor: string): TMembAnswer;
var
  Leaves: TArray<string>;
  Leaf  : string;
begin
  if SameText(AClass, AAncestor) or FCtx.Store.IsDescendantOf(AClass, AAncestor, FCtx.FileId) then Exit(maYes);
  Result:= maNo;
  Leaves:= FCtx.Store.UnresolvedAncestorNames(AClass, FCtx.FileId);
  { a class the project does not declare is its own open end }
  if FCtx.Store.ResolveTypeCategory(AClass, FCtx.FileId) = tcUnknown then Leaves:= [AClass];
  for Leaf in Leaves do
  begin
    if SameText(Leaf, AAncestor) then Exit(maYes);
    if MatchText(Leaf, ROOT_TYPES) then Continue;
    if FCtx.LibStore = nil then Result:= maUnknown
    else if FCtx.LibStore.IsDescendantOf(Leaf, AAncestor, 0) then Exit(maYes)
    else if FCtx.LibStore.ResolveTypeCategory(Leaf, 0) = tcUnknown then Result:= maUnknown;
  end;
end;

{ The class or a project ancestor declares _AddRef: its life is not the reference count of TInterfacedObject. }
function TMembRun.CountsItself(const AClass: string): Boolean;
var
  Symbol  : TSymbol;
  Ancestor: TTypeAncestor;
begin
  Symbol:= FCtx.Store.ResolveTypeNameToClass(AClass, FCtx.FileId);
  if Symbol.Id <= 0 then Exit(False);
  Result:= FCtx.Store.FindChildSymbolByName(Symbol.Id, ADDREF_METHOD).Id > 0;
  if Result then Exit;
  for Ancestor in FCtx.Store.GetTransitiveAncestors(Symbol.Id) do
    if (Ancestor.SymbolId > 0) and (FCtx.Store.FindChildSymbolByName(Ancestor.SymbolId, ADDREF_METHOD).Id > 0) then Exit(True);
end;

function TMembRun.ReferenceCounted(const AClass: string): Boolean;
begin
  Result:= (Descends(AClass, COUNTED_CLASS) = maYes) and (not CountsItself(AClass));
end;

{ The class a `TFoo.Create` / `TFoo.Create(..)` argument creates; '' when the argument is anything else. }
function TMembRun.FreshClass(const AArg: TTSNode): string;
var
  Dot, Lhs: TTSNode;
  Kind    : TTypeCategory;
begin
  Result:= '';
  Dot   := AArg;
  if Dot.NodeType = 'exprCall' then Dot:= Dot.ChildByField('entity');
  if Dot.IsNull or (Dot.NodeType <> 'exprDot') or (not StartsText(CONSTRUCTOR_PREFIX, Trim(Text(Dot.ChildByField('rhs'))))) then Exit;
  Lhs:= Dot.ChildByField('lhs');
  if Lhs.IsNull or HasNode(Lhs, ['exprCall', 'exprSubscript']) then Exit;
  Result:= LastName(WithoutGenerics(Trim(Text(Lhs))));
  Kind  := Category(Result, FCtx.FileId);
  if (Kind <> tcClass) and ((Kind <> tcUnknown) or (not LooksLikeClass(Result))) then Result:= '';
end;

{ TButton.Create(Self): the owner frees it. Also True when the class may be a component and the index cannot tell. }
function TMembRun.OwnedByComponent(const AArg: TTSNode; const AClass: string): Boolean;
var
  Args: TArray<TTSNode>;
begin
  Result:= False;
  if AArg.NodeType <> 'exprCall' then Exit;
  Args:= CallArguments(AArg);
  if (Args = nil) or SameText(Trim(Text(Args[0])), NIL_TEXT) then Exit;
  Result:= Descends(AClass, COMPONENT_CLASS) <> maNo;
end;

{ Every use of the parameter in the callee's body reads it: nothing stores, returns, passes on or frees the object. }
function TMembRun.CalleeOnlyReads(const ACallee: TSymbol; const AParam: string): Boolean;
var
  Key    : string;
  Parsed : TParsedFile;
  Routine, Use: TTSNode;
  Found  : TList<TTSNode>;
begin
  Key:= Format('%d:%s', [ACallee.Id, LowerCase(AParam)]);
  if FReadOnly.TryGetValue(Key, Result) then Exit;
  Result:= False;
  if (not ACallee.IsVirtual) and (ACallee.ImplStartLine > 0) then
  begin
    Parsed:= TAstParseCache.Get(FCtx.Store.GetFilePath(ACallee.FileId));
    if Parsed.Tree <> nil then
    begin
      Routine:= RoutineAt(Parsed.Tree.RootNode, ACallee.ImplStartLine, ACallee.ImplEndLine);
      if (not Routine.IsNull) and SameText(LastName(Trim(NodeText(Routine.ChildByField('header').ChildByField('name'), Parsed.Src))), ACallee.Name) then
      begin
        Found:= TList<TTSNode>.Create;
        try
          AddUses(Routine, AParam, Parsed.Src, Found);
          Result:= True;
          for Use in Found do
            if not ReadOnlyUse(Use, Parsed.Src) then Result:= False;
        finally
          Found.Free;
        end;
      end;
    end;
  end;
  FReadOnly.Add(Key, Result);
end;

{ ---- fresh-instance-as-argument, class-passed-as-interface ---- }

procedure TMembRun.CheckFresh(const AArg, ACall: TTSNode; const ACallee: TSymbol; const AParam: TV154Param);
var
  Created: string;
begin
  Created:= FreshClass(AArg);
  if (Created = '') or OwnedByComponent(AArg, Created) or (not CalleeOnlyReads(ACallee, AParam.Name)) then Exit;
  Emit(RULE_FRESH_INSTANCE_AS_ARGUMENT, SEVERITY_INFO, Format('%s creates an object that %s only reads through "%s": nobody frees it',
    [Trim(Text(AArg)), Trim(Text(CalleeName(ACall))), AParam.Name]), AArg);
end;

{ The class of the local variable or parameter an argument names; '' when the argument is anything else,
  the class is not reference counted, or the variable is not used after the call. }
function TMembRun.VariableClass(const AArg, ACall: TTSNode): string;
var
  Routine, Decl, Use: TTSNode;
  Found  : TList<TTSNode>;
  After  : Boolean;
begin
  Result:= '';
  if AArg.NodeType <> 'identifier' then Exit;
  Routine:= Enclosing(AArg);
  if Routine.IsNull or not Declares(Routine, Text(AArg), FSrc, Decl) then Exit;
  Result:= LastName(WithoutGenerics(DeclaredType(Decl, FSrc)));
  if (Result = '') or (Category(Result, FCtx.FileId) <> tcClass) or (not ReferenceCounted(Result)) then Exit('');
  After:= False;
  Found:= TList<TTSNode>.Create;
  try
    AddUses(Routine, Text(AArg), FSrc, Found);
    for Use in Found do
      if Use.StartByte >= ACall.EndByte then After:= True;
  finally
    Found.Free;
  end;
  if not After then Result:= '';
end;

procedure TMembRun.CheckInterface(const AArg, ACall: TTSNode; const AParam: TV154Param);
var
  Created: string;
begin
  Created:= FreshClass(AArg);
  { v156 FP-1: a fresh instance of a reference-counted class in a const interface argument is the safe idiom -- the compiler
    holds a temporary interface reference for the call, so the object is released after it and a callee that stores the
    interface keeps its own reference. 4 of 4 hits on real code were this idiom; only the variable form below is a hazard. }
  if Created <> '' then Exit;
  Created:= VariableClass(AArg, ACall);
  if Created <> '' then
    Emit(RULE_CLASS_PASSED_AS_INTERFACE, SEVERITY_WARNING, Format('%s is an object reference of the reference-counted class %s, passed to the interface ' +
      'parameter "%s" of %s and used afterwards: a reference taken in the call frees the object when it is released', [Trim(Text(AArg)), Created,
      AParam.Name, Trim(Text(CalleeName(ACall)))]), AArg);
end;

procedure TMembRun.CheckCall(const ACall: TTSNode; AFresh, AInterface: Boolean);
var
  Args  : TArray<TTSNode>;
  Target: TSymbol;
  Params: TV154ParamList;
  I     : Integer;
  Wanted: Boolean;
begin
  Args  := CallArguments(ACall);
  Wanted:= False;
  for I:= 0 to High(Args) do
    Wanted:= Wanted or (Args[I].NodeType = 'identifier') or (FreshClass(Args[I]) <> '');
  if (not Wanted) or (not Callee(ACall, Target, Params)) then Exit;
  for I:= 0 to High(Args) do
  begin
    if (Params.Params[I].Mode not in [pmValue, pmConst]) or Params.Params[I].IsUntyped then Continue;
    case Category(LastName(WithoutGenerics(Params.Params[I].TypeText)), Target.FileId) of
      tcClass: if AFresh then CheckFresh(Args[I], ACall, Target, Params.Params[I]);
      tcInterface: if AInterface then CheckInterface(Args[I], ACall, Params.Params[I]);
    end;
  end;
end;

procedure TMembRun.CheckArguments(AFresh, AInterface: Boolean);
var
  Call: TTSNode;
begin
  if (FCtx.Store is not TSQLiteSymbolStore) or (FCtx.FileId = 0) then Exit;
  for Call in FCalls do CheckCall(Call, AFresh, AInterface);
end;

{ ---- indexof-result-unchecked, the stored form ---- }

procedure TMembRun.CheckStoredIndex(const AAssign: TTSNode);
var
  Target, Value, Routine, Decl, Use, First, User: TTSNode;
  Found: TList<TTSNode>;
begin
  Target:= AAssign.ChildByField('lhs');
  Value := AAssign.ChildByField('rhs');
  if Target.IsNull or Value.IsNull or (Target.NodeType <> 'identifier') or (Value.NodeType <> 'exprCall') then Exit;
  if not MatchStr(LowerText(CalleeName(Value), FSrc), INDEX_CALLS) then Exit;
  Routine:= Enclosing(AAssign);
  if Routine.IsNull or (not Declares(Routine, Text(Target), FSrc, Decl)) or InLoop(AAssign, Routine) then Exit;
  First:= Default(TTSNode);
  Found:= TList<TTSNode>.Create;
  try
    AddUses(Routine, Text(Target), FSrc, Found);
    for Use in Found do
      if (Use.StartByte >= AAssign.EndByte) and (First.IsNull or (Use.StartByte < First.StartByte)) then First:= Use;
  finally
    Found.Free;
  end;
  if First.IsNull or (First.Parent.NodeType <> 'exprArgs') or (not SameNode(Enclosing(First), Routine)) then Exit;
  User:= First.Parent.Parent;
  { a method only: System.Delete(S, 0, 1) on a string does nothing }
  if (User.NodeType = 'exprSubscript') or ((User.NodeType = 'exprCall') and (User.ChildByField('entity').NodeType = 'exprDot') and
    MatchStr(LowerText(CalleeName(User), FSrc), INDEX_USERS)) then
    Emit(RULE_INDEXOF_RESULT_UNCHECKED, SEVERITY_WARNING, Format('"%s" holds the result of %s (line %d) and is used as an index before it is tested: ' +
      'the result is -1 (0 for Pos) when the item is absent', [Text(First), Trim(Text(CalleeName(Value))), Integer(AAssign.StartPoint.Row) + 1]), First);
end;

procedure TMembRun.CheckStoredIndexes;
var
  Assign: TTSNode;
begin
  for Assign in FAssigns do CheckStoredIndex(Assign);
end;

end.
