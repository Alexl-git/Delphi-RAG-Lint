unit DRagLint.Index.FieldLineage;

{ drag-lint 1.56 -- lane EXT-B3: B14, field lineage facts (spec
  docs\superpowers\specs\2026-11-27-derived-field-lineage-design.md section 4.3).

  Two passes over the SAME tree, both driven by one syntactic classifier (ClassifySite):

  1. the routine-facts hook (TIndexer.RegisterRoutineFactsHook 'field-lineage'), once per routine:
       ds_field_accesses  B14-1  every by-name dataset-field access and every accessor write, also
                                 inside `with` bodies (B14-6a);
       loop_facts         B14-5  every while / repeat / for / for-in statement with its condition range;
       data_flows         B14-6b the 'dsfield' rows of a field write inside a `with` body (the walk
                                 does not enter a `with` body), every row cond = 1.
  2. the data-flow walk hooks (TDataFlowFacts.RegisterExprHook / RegisterWriteHook), on every pass:
       B14-3  a field READ adds a positioned 'dsfield' source to the value of its expression;
       B14-2  a field WRITE the walk gives no 'write' row for gets a 'dsfield' destination row.

  Purely syntactic: no type is known here. A reader narrows by refs.receiver_type_text at the same
  position, or by the DFM facts. Nothing in this unit changes or removes a row another lane wrote. }

interface

uses
  DRagLint.Core.Model,  // dl:ok uses-global-census -- the named constants are the whole contract this unit draws; the unit pair travels together
  DRagLint.Core.Indexer;

type
  /// <summary>1.56 B14: emits the field-lineage facts of one routine and registers the hooks that
  /// produce them during an index run.</summary>
  /// <remarks>Stateless; every method is a class method. The unit's initialization calls
  /// RegisterHooks, so linking the unit into an engine is what turns the facts on (an extraction
  /// change: the extractor version must move with it).</remarks>
  TFieldLineage = class
    public
      /// <summary>The routine-facts hook: appends the routine's ds_field_accesses and loop_facts rows
      /// to AFacts and the `with`-body 'dsfield' rows (B14-6b) to AFlows.</summary>
      /// <param name="ACtx">The routine (or a program's main block) as the indexer hands it to
      /// every routine-facts hook.</param>
      /// <param name="AFlows">The routine's data_flows rows so far; rows are only appended, each with
      /// dst_kind DF_DST_DSFIELD and Cond = True.</param>
      /// <param name="AFacts">The file's 1.56 facts; rows are only appended. A loop's Parent is the
      /// index of its enclosing loop in AFacts.LoopFacts, -1 = none.</param>
      /// <remarks>Runs inside the file transaction; does not raise on an unexpected tree shape (a
      /// node it cannot classify gives no row). Not thread-safe per ACtx; no shared state.</remarks>
      class procedure CollectRoutine(const ACtx: TRoutineFactsCtx; var AFlows: TArray<TDataFlowRow>;
        var AFacts: TExtFileFacts); static;
      /// <summary>Registers CollectRoutine with the indexer and the B14-2 / B14-3 hooks with the
      /// data-flow walk.</summary>
      /// <remarks>Idempotent: a second call registers nothing. Process-wide, not thread-safe; called
      /// from this unit's initialization.</remarks>
      class procedure RegisterHooks; static;
  end;

implementation

uses
  System.SysUtils,
  TreeSitter,
  DRagLint.Core.Encoding,
  DRagLint.Analysis.Flow.Lattices,
  DRagLint.Index.DataFlowFacts;

const
  LIN_HOOK_NAME = 'field-lineage';
  { how far a receiver chain / an ancestor chain is followed before giving up }
  LIN_DEPTH_MAX = 64;
  LIN_AS_PREFIX = 'as';
  LIN_AS_MIN_LEN = 3;
  LIN_WITH_SEP = '|';
  { node types }
  NT_IDENT = 'identifier';
  NT_DOT = 'exprDot';
  NT_CALL = 'exprCall';
  NT_SUBSCRIPT = 'exprSubscript';
  NT_PARENS = 'exprParens';
  NT_UNARY = 'exprUnary';
  NT_ASSIGN = 'assignment';
  NT_STRING = 'literalString';
  NT_DEFPROC = 'defProc';
  NT_WITH = 'with';
  NT_WHILE = 'while';
  NT_REPEAT = 'repeat';
  NT_FOR = 'for';
  NT_FOREACH = 'foreach';
  NT_VARDEF = 'varDef';
  NT_DECLARG = 'declArg';
  NT_STATEMENT = 'statement';
  NT_BRACKET = '[';
  NT_COMMENT = 'comment';
  KEYWORD_PREFIX = 'k';
  { field names of the grammar }
  FLD_LHS = 'lhs';
  FLD_RHS = 'rhs';
  FLD_ENTITY = 'entity';
  FLD_ARGS = 'args';
  FLD_BODY = 'body';
  FLD_HEADER = 'header';
  FLD_CONDITION = 'condition';
  FLD_ITERABLE = 'iterable';
  FLD_OPERAND = 'operand';
  FLD_OPERATOR = 'operator';
  { member names, lower case }
  MEM_FIELDBYNAME = 'fieldbyname';
  MEM_FINDFIELD = 'findfield';
  MEM_FIELDVALUES = 'fieldvalues';
  MEM_FIELDS = 'fields';
  MEM_VALUE = 'value';
  MEM_NEWVALUE = 'newvalue';
  MEM_OLDVALUE = 'oldvalue';
  MEM_CURVALUE = 'curvalue';
  MEM_CLEAR = 'clear';
  MEM_ASSIGN = 'assign';
  MEM_SELF = 'self';
  VIS_PUBLISHED = 'published';
  VIS_PUBLIC = 'public';
  QUOTE = '''';

type
  { the source text of a node: TDataFlowSite.NodeText in the walk hooks, TSrcText.TextOf in the routine hook }
  TLinText = function(const ANode: TTSNode): string of object;

  { One classified access. Leaf is the node whose start is the row's position. }
  TDsSite = record
    Mode     : string;
    Shape    : string;
    Accessor : string;
    Leaf     : TTSNode;
    Dataset  : TTSNode; { receiver of FieldByName / FindField / FieldValues / Fields / `[`; null when bare }
    FieldRecv: TTSNode; { shape accessor: the receiver of the accessor }
    NameArg  : TTSNode; { the name / index argument; null for shape accessor }
    Rhs      : TTSNode; { write by `:=`: the right side; Assign: its argument list; else null }
  end;

  TSrcText = class
    strict private
      FSrc: TBytes;
    public
      constructor Create(const ASrc: TBytes);
      function TextOf(const ANode: TTSNode): string;
      function Line(const ANode: TTSNode): Integer;
      function Col(const ANode: TTSNode): Integer;
      function EndLine(const ANode: TTSNode): Integer;
      function EndCol(const ANode: TTSNode): Integer;
  end;

  { the per-routine state of the routine-facts hook }
  TRoutinePass = class  // dl:ok high-response@e590 -- one private per-routine walker: the access rows, the with-body sources and the root classifier share the routine's variable table and source text by design (as TCollector of the data-flow walk)
    strict private
      FCtx       : TRoutineFactsCtx;
      FText      : TSrcText;
      FFields    : TArray<string>; { lower case: the owning class's non-published fields of this file }
      FGlobals   : TArray<string>; { lower case }
      FFlows     : TArray<TDataFlowRow>;
      FAccesses  : TArray<TDsFieldAccessRow>;
      FLoops     : TArray<TLoopFactRow>;
      FLoopBase  : Integer;
      FVars      : TRoutineVarTable; { built on first use: most routines have no access at all }
      FVarsBuilt : Boolean;
      FInline    : TArray<string>;   { lower case: bare inline `var X: T;` names the table leaves out }
      procedure ScanInlineDefs(const ANode: TTSNode; ADepth: Integer);
      function IsLocal(const AIdent: TTSNode): Boolean;
      function InNames(const ANames: TArray<string>; const ALower: string): Boolean;
      procedure LoadFields;
      procedure RootOf(const ASite: TDsSite; AInWith: Boolean; out AKind, AName: string; out AIndex: Integer);
      procedure EmitAccess(const ANode: TTSNode; const ASite: TDsSite; const AWithCtx: string);
      procedure AddFlow(const ARow: TDsFieldAccessRow; const ASrcKind: string; ASrcIndex, ASrcLine, ASrcCol: Integer;
        const ASrcName: string);
      procedure WithIdentSource(const ARow: TDsFieldAccessRow; const AIdent: TTSNode);
      procedure WithDotSource(const ARow: TDsFieldAccessRow; const ADot: TTSNode; ADepth: Integer);
      procedure WithSources(const ARow: TDsFieldAccessRow; const ANode: TTSNode; ADepth: Integer);
      procedure Walk(const ANode: TTSNode; const AWithCtx: string; ALoop, ADepth: Integer);
    public
      constructor Create(const ACtx: TRoutineFactsCtx; ALoopBase: Integer);
      destructor Destroy; override;
      procedure Run;
      property Flows: TArray<TDataFlowRow> read FFlows;
      property Accesses: TArray<TDsFieldAccessRow> read FAccesses;
      property Loops: TArray<TLoopFactRow> read FLoops;
  end;

var
  GRegistered: Boolean = False;

{ ---- TSrcText ---- }

constructor TSrcText.Create(const ASrc: TBytes);
begin
  inherited Create;
  FSrc:= ASrc;
end;

function TSrcText.TextOf(const ANode: TTSNode): string;  // dl:ok duplicate-code -- same shape over different fields or sources; a shared helper would need more parameters than it saves, and this lane must not change extraction or checker structure
var
  S, E: Integer;
begin
  Result:= '';
  if ANode.IsNull then Exit;
  S:= Integer(ANode.StartByte);
  E:= Integer(ANode.EndByte);
  if (S < 0) or (E <= S) or (E > Length(FSrc)) then Exit;
  Result:= TEncoding.UTF8.GetString(FSrc, S, E - S);
end;

function TSrcText.Line(const ANode: TTSNode): Integer;
begin
  Result:= if ANode.IsNull then 0 else Integer(ANode.StartPoint.Row) + 1;
end;

function TSrcText.Col(const ANode: TTSNode): Integer;
begin
  Result:= if ANode.IsNull then 0 else Utf8ByteColToCharCol(FSrc, ANode.StartByte, ANode.StartPoint.Column) + 1;
end;

function TSrcText.EndLine(const ANode: TTSNode): Integer;
begin
  Result:= if ANode.IsNull then 0 else Integer(ANode.EndPoint.Row) + 1;
end;

{ exclusive: the column of the first character after the node }
function TSrcText.EndCol(const ANode: TTSNode): Integer;
begin
  Result:= if ANode.IsNull then 0 else Utf8ByteColToCharCol(FSrc, ANode.EndByte, ANode.EndPoint.Column) + 1;
end;

{ ---- the syntactic classifier (shared by both passes) ---- }

function IsType(const ANode: TTSNode; const AType: string): Boolean;
begin
  Result:= (not ANode.IsNull) and (ANode.NodeType = AType);
end;

{ a keyword (`kWith`, `kDo`, `kFor` ...) or a comment: a named child that is no part of the code }
function IsTrivia(const ANode: TTSNode): Boolean;
var
  NT: string;
begin
  NT:= ANode.NodeType;
  Result:= (NT = NT_COMMENT) or ((Length(NT) > 1) and (NT[1] = KEYWORD_PREFIX) and CharInSet(NT[2], ['A'..'Z']));
end;

function SameNode(const A, B: TTSNode): Boolean;
begin
  Result:= (not A.IsNull) and (not B.IsNull) and (A = B);
end;

{ The member a call / subscript entity names: `F` -> F (no receiver), `X.F` -> F with receiver X. }
function EntityLeaf(const AEntity: TTSNode; out ARecv: TTSNode): TTSNode;
begin
  Result:= Default(TTSNode);
  ARecv := Default(TTSNode);
  if AEntity.IsNull then Exit;
  if AEntity.NodeType = NT_IDENT then Exit(AEntity);
  if AEntity.NodeType <> NT_DOT then Exit;
  Result:= AEntity.ChildByField(FLD_RHS);
  if not IsType(Result, NT_IDENT) then Exit(Default(TTSNode));
  ARecv:= AEntity.ChildByField(FLD_LHS);
end;

{ The single argument of a call / subscript; null when there is not exactly one. }
function SingleArg(const ANode: TTSNode): TTSNode;
var
  Args: TTSNode;
begin
  Result:= Default(TTSNode);
  Args:= ANode.ChildByField(FLD_ARGS);
  if Args.IsNull then Exit;
  if Args.NamedChildCount = 1 then Result:= Args.NamedChild(0);
end;

{ `As` followed by an upper-case letter: AsFloat, AsString, AsBCD ... (spec 4.3, B14-1) }
function IsAsAccessor(const AName: string): Boolean;
begin
  Result:= (Length(AName) >= LIN_AS_MIN_LEN) and SameText(Copy(AName, 1, Length(LIN_AS_PREFIX)), LIN_AS_PREFIX)
           and CharInSet(AName[LIN_AS_MIN_LEN], ['A'..'Z']);
end;

{ a member that reads or writes the VALUE of a field object }
function IsValueMember(const AName: string; ACore: Boolean): Boolean;
var
  L: string;
begin
  if IsAsAccessor(AName) then Exit(True);
  L:= LowerCase(AName);
  Result:= (L = MEM_VALUE) or (L = MEM_NEWVALUE) or (ACore and ((L = MEM_OLDVALUE) or (L = MEM_CURVALUE)));
end;

{ `D.FieldByName(e)`, `D.FindField(e)`, `D.Fields[i]` (also bare, inside `with`): the part of an
  access that names the field. Fills Shape, Leaf (the member identifier), Dataset and NameArg. }
function CoreOf(const ANode: TTSNode; AText: TLinText; var ASite: TDsSite): Boolean;
var
  Leaf, Recv, Arg: TTSNode;
  Name           : string;
begin
  Result:= False;
  if ANode.IsNull then Exit;
  if (ANode.NodeType <> NT_CALL) and (ANode.NodeType <> NT_SUBSCRIPT) then Exit;
  Leaf:= EntityLeaf(ANode.ChildByField(FLD_ENTITY), Recv);
  Arg := SingleArg(ANode);
  if Leaf.IsNull or Arg.IsNull then Exit;
  Name:= LowerCase(AText(Leaf));
  if ANode.NodeType = NT_CALL then
  begin
    if Name = MEM_FIELDBYNAME then ASite.Shape:= DSFA_SHAPE_BYNAME
    else if Name = MEM_FINDFIELD then ASite.Shape:= DSFA_SHAPE_FIND
    else Exit;
  end
  else if Name = MEM_FIELDS then ASite.Shape:= DSFA_SHAPE_INDEX
  else Exit;
  ASite.Leaf   := Leaf;
  ASite.Dataset:= Recv;
  ASite.NameArg:= Arg;
  Result:= True;
end;

{ ANode is the left side of an assignment: its right side. }
function AssignedRhs(const ANode: TTSNode): TTSNode;
var
  P: TTSNode;
begin
  Result:= Default(TTSNode);
  P:= ANode.Parent;
  if IsType(P, NT_ASSIGN) and SameNode(P.ChildByField(FLD_LHS), ANode) then Result:= P.ChildByField(FLD_RHS);
end;

procedure SetModeByAssignment(const ANode: TTSNode; var ASite: TDsSite);
begin
  ASite.Rhs := AssignedRhs(ANode);
  ASite.Mode:= if ASite.Rhs.IsNull then DSFA_MODE_READ else DSFA_MODE_WRITE;
end;

{ `X.Clear` as a statement or `X.Assign(e)` as a call: a write. ANode is the `X.M` node. False when the
  member is used any other way (a receiver of something further, a side of an assignment). }
function IsWriteCall(const ANode: TTSNode; AIsAssign: Boolean; var ASite: TDsSite): Boolean;
var
  P: TTSNode;
begin
  P:= ANode.Parent;
  Result:= not ((IsType(P, NT_DOT) and SameNode(P.ChildByField(FLD_LHS), ANode)) or IsType(P, NT_ASSIGN));
  if Result and AIsAssign then
  begin
    Result:= IsType(P, NT_CALL) and SameNode(P.ChildByField(FLD_ENTITY), ANode) and not SingleArg(P).IsNull;
    if Result then ASite.Rhs:= P.ChildByField(FLD_ARGS);
  end;
  if Result then ASite.Mode:= DSFA_MODE_WRITE;
end;

{ `X.M` where M is an accessor: over a core (`D.FieldByName('F').AsFloat`) or, for shape accessor,
  over anything else (`tblMTOTAL.AsFloat`, `F.Value`, `F.Clear`, `F.Assign(e)`). }
function ClassifyDot(const ANode: TTSNode; AText: TLinText; var ASite: TDsSite): Boolean;
var
  L, M    : TTSNode;
  Name, Lo: string;
  Core    : Boolean;
begin
  Result:= False;
  L:= ANode.ChildByField(FLD_LHS);
  M:= ANode.ChildByField(FLD_RHS);
  if L.IsNull or not IsType(M, NT_IDENT) then Exit;
  Name:= AText(M);
  Lo  := LowerCase(Name);
  Core:= CoreOf(L, AText, ASite);
  if (Lo = MEM_CLEAR) or (Lo = MEM_ASSIGN) then Result:= IsWriteCall(ANode, Lo = MEM_ASSIGN, ASite)
  else
  begin
    Result:= IsValueMember(Name, Core);
    if Result then SetModeByAssignment(ANode, ASite);
  end;
  { a member of Self is a property of the own class, not a field object }
  if Result and (not Core) and IsType(L, NT_IDENT) and SameText(AText(L), MEM_SELF) then Result:= False;
  if not Result then Exit;
  if not Core then
  begin
    ASite.Shape    := DSFA_SHAPE_ACCESSOR;
    ASite.FieldRecv:= L;
  end;
  ASite.Accessor:= Name;
  ASite.Leaf    := M;
end;

{ A core that no accessor follows (`F:= D.FieldByName('X')`, `D.FieldByName('X').IsNull`): a read. }
function ClassifyBareCore(const ANode: TTSNode; AText: TLinText; var ASite: TDsSite): Boolean;
var
  P, M: TTSNode;
  Lo  : string;
begin
  Result:= False;
  if not CoreOf(ANode, AText, ASite) then Exit;
  P:= ANode.Parent;
  if IsType(P, NT_DOT) and SameNode(P.ChildByField(FLD_LHS), ANode) then
  begin
    M:= P.ChildByField(FLD_RHS);
    if IsType(M, NT_IDENT) then
    begin
      Lo:= LowerCase(AText(M));
      { ClassifyDot owns these; a Clear / Assign it declines still is no read of the value }
      if IsValueMember(AText(M), True) or (Lo = MEM_CLEAR) or (Lo = MEM_ASSIGN) then Exit;
    end;
  end;
  ASite.Mode:= DSFA_MODE_READ;
  Result:= True;
end;

{ `D.FieldValues[e]` and the default indexed property `D['F']` (one string literal argument). }
function ClassifySubscript(const ANode: TTSNode; AText: TLinText; var ASite: TDsSite): Boolean;
var
  Ent, Leaf, Recv, Arg, Tok: TTSNode;
  I                        : Integer;
begin
  Result:= False;
  Ent:= ANode.ChildByField(FLD_ENTITY);
  Arg:= SingleArg(ANode);
  if Ent.IsNull or Arg.IsNull then Exit;
  Leaf:= EntityLeaf(Ent, Recv);
  if (not Leaf.IsNull) and SameText(AText(Leaf), MEM_FIELDVALUES) then
  begin
    ASite.Shape  := DSFA_SHAPE_VALUES;
    ASite.Leaf   := Leaf;
    ASite.Dataset:= Recv;
  end
  else
  begin
    if Arg.NodeType <> NT_STRING then Exit;
    if (not Leaf.IsNull) and SameText(AText(Leaf), MEM_FIELDS) then Exit;
    ASite.Shape  := DSFA_SHAPE_DEFAULT;
    ASite.Dataset:= Ent;
    ASite.Leaf   := ANode;
    for I:= 0 to ANode.ChildCount - 1 do
    begin
      Tok:= ANode.Child(I);
      if Tok.NodeType = NT_BRACKET then
      begin
        ASite.Leaf:= Tok;
        Break;
      end;
    end;
  end;
  ASite.NameArg:= Arg;
  SetModeByAssignment(ANode, ASite);
  Result:= True;
end;

{ THE classifier: is ANode, taken alone, the top node of one dataset-field access? Every node is
  asked independently; the parent checks keep one access from being reported at two nodes. }
function ClassifySite(const ANode: TTSNode; AText: TLinText; out ASite: TDsSite): Boolean;
var
  NT: string;
begin
  ASite:= Default(TDsSite);
  Result:= False;
  if ANode.IsNull then Exit;
  NT:= ANode.NodeType;
  if NT = NT_DOT then Result:= ClassifyDot(ANode, AText, ASite)
  else if NT = NT_CALL then Result:= ClassifyBareCore(ANode, AText, ASite)
  else if NT = NT_SUBSCRIPT then
  begin
    Result:= ClassifyBareCore(ANode, AText, ASite);
    if not Result then
    begin
      ASite:= Default(TDsSite);
      Result:= ClassifySubscript(ANode, AText, ASite);
    end;
  end;
  if not Result then ASite:= Default(TDsSite);
end;

{ The leftmost identifier of an expression (`X`, `X.f`, `X[i]`, `X.f(a)`, `(X as T)`), skipping a
  leading `Self.`; null when the root is not an identifier. }
function RootIdent(const AExpr: TTSNode; AText: TLinText): TTSNode;
var
  Cur, L: TTSNode;
  Guard : Integer;
begin
  Result:= Default(TTSNode);
  Cur:= AExpr;
  for Guard:= 1 to LIN_DEPTH_MAX do
  begin
    if Cur.IsNull then Exit;
    if Cur.NodeType = NT_IDENT then
    begin
      if not SameText(AText(Cur), MEM_SELF) then Result:= Cur;
      Exit;
    end;
    if Cur.NodeType = NT_DOT then
    begin
      L:= Cur.ChildByField(FLD_LHS);
      Cur:= if IsType(L, NT_IDENT) and SameText(AText(L), MEM_SELF) then Cur.ChildByField(FLD_RHS) else L;
    end
    else if (Cur.NodeType = NT_SUBSCRIPT) or (Cur.NodeType = NT_CALL) then Cur:= Cur.ChildByField(FLD_ENTITY)
    else if Cur.NodeType = NT_PARENS then Cur:= Cur.NamedChild(0)
    else if Cur.NodeType = NT_UNARY then Cur:= Cur.ChildByField(FLD_OPERAND)
    else if not Cur.ChildByField(FLD_LHS).IsNull then Cur:= Cur.ChildByField(FLD_LHS) { `X as T` }
    else Exit;
  end;
end;

{ the expression whose leftmost identifier is the access's root }
function RootExpr(const ASite: TDsSite): TTSNode;
begin
  Result:= if ASite.Shape = DSFA_SHAPE_ACCESSOR then ASite.FieldRecv else ASite.Dataset;
end;

function EnclosingProc(const ANode: TTSNode): TTSNode;
var
  Guard: Integer;
begin
  Result:= ANode.Parent;
  Guard:= 0;
  while (not Result.IsNull) and (Result.NodeType <> NT_DEFPROC) do
  begin
    Result:= Result.Parent;
    Inc(Guard);
    if Guard > High(Word) then Exit(Default(TTSNode));
  end;
end;

{ 0-based declared position of the parameter AIdent names in its enclosing routine, -1 = not a
  parameter. Mirrors TRoutineVarTable.Build.AddArgs, so it equals data_flows' param index. }
function ParamIndexOf(const AIdent: TTSNode; AText: TLinText): Integer;
var
  Proc, Args, DA, Id: TTSNode;
  I, J, N           : Integer;
  Name              : string;
begin
  Result:= -1;
  if not IsType(AIdent, NT_IDENT) then Exit;
  Proc:= EnclosingProc(AIdent);
  if Proc.IsNull then Exit;
  Args:= Proc.ChildByField(FLD_HEADER);
  if not Args.IsNull then Args:= Args.ChildByField(FLD_ARGS);
  if Args.IsNull then Exit;
  Name:= AText(AIdent);
  N:= 0;
  for I:= 0 to Args.NamedChildCount - 1 do
  begin
    DA:= Args.NamedChild(I);
    if DA.NodeType <> NT_DECLARG then Continue;
    for J:= 0 to DA.NamedChildCount - 1 do
    begin
      Id:= DA.NamedChild(J);
      if Id.NodeType <> NT_IDENT then Continue;
      if SameText(AText(Id), Name) then Exit(N);
      Inc(N);
    end;
  end;
end;

{ ---- the walk's receiver shapes (mirror of DRagLint.Index.DataFlowFacts.RefShapeOk, which is the
       parser's member-access ref rule): the walk records a 'write' row / a positioned 'ref' source
       at the member of `L.M` exactly for these L. ---- }

function IsDottedIdentChain(const ANode: TTSNode): Boolean;
begin
  Result:= False;
  if ANode.IsNull then Exit;
  if ANode.NodeType = NT_IDENT then Exit(True);
  if ANode.NodeType <> NT_DOT then Exit;
  if not IsType(ANode.ChildByField(FLD_RHS), NT_IDENT) then Exit;
  Result:= IsDottedIdentChain(ANode.ChildByField(FLD_LHS));
end;

function IsIndexedReceiver(const ANode: TTSNode): Boolean;
var
  Op, Operand: TTSNode;
begin
  Result:= False;
  if ANode.IsNull then Exit;
  if ANode.NodeType = NT_SUBSCRIPT then Result:= True
  else if ANode.NodeType = NT_UNARY then
  begin
    Op     := ANode.ChildByField(FLD_OPERATOR);
    Operand:= ANode.ChildByField(FLD_OPERAND);
    { a postfix operator only (`P^`) }
    Result:= (not Op.IsNull) and (not Operand.IsNull) and (Op.StartByte >= Operand.EndByte)
             and (IsDottedIdentChain(Operand) or IsIndexedReceiver(Operand));
  end
  else if ANode.NodeType = NT_DOT then
    Result:= IsType(ANode.ChildByField(FLD_RHS), NT_IDENT) and IsIndexedReceiver(ANode.ChildByField(FLD_LHS));
end;

function IsParenRooted(const ANode: TTSNode): Boolean;
begin
  Result:= False;
  if ANode.IsNull then Exit;
  if ANode.NodeType = NT_PARENS then Exit(True);
  if ANode.NodeType <> NT_DOT then Exit;
  if not IsType(ANode.ChildByField(FLD_RHS), NT_IDENT) then Exit;
  Result:= IsParenRooted(ANode.ChildByField(FLD_LHS));
end;

function IsHardCastRooted(const ANode: TTSNode): Boolean;
var
  A: TTSNode;
begin
  Result:= False;
  if ANode.IsNull then Exit;
  if ANode.NodeType = NT_CALL then
  begin
    A:= ANode.ChildByField(FLD_ARGS);
    Exit(IsType(ANode.ChildByField(FLD_ENTITY), NT_IDENT) and (not A.IsNull) and (A.NamedChildCount = 1));
  end;
  if ANode.NodeType <> NT_DOT then Exit;
  if not IsType(ANode.ChildByField(FLD_RHS), NT_IDENT) then Exit;
  Result:= IsHardCastRooted(ANode.ChildByField(FLD_LHS));
end;

function WalkRefShapeOk(const ARecv: TTSNode; AText: TLinText): Boolean;
begin
  Result:= False;
  if ARecv.IsNull then Exit;
  if ARecv.NodeType = NT_IDENT then Exit(not SameText(AText(ARecv), MEM_SELF));
  Result:= ((ARecv.NodeType = NT_DOT) and IsDottedIdentChain(ARecv)) or IsIndexedReceiver(ARecv) or IsParenRooted(ARecv)
           or IsHardCastRooted(ARecv);
end;

{ The walk itself records a 'write' row at the member of this assignment's left side
  (TCollector.ApplyMemberWrite): `R.M := e` and `R.M[i] := e` with a ref-shaped R other than Self. }
function WalkWritesMember(const ALhs: TTSNode; AText: TLinText): Boolean;
var
  Ent, Recv: TTSNode;
begin
  Result:= False;
  Ent:= ALhs;
  if IsType(Ent, NT_SUBSCRIPT) then Ent:= Ent.ChildByField(FLD_ENTITY);
  if not IsType(Ent, NT_DOT) then Exit;
  if not IsType(Ent.ChildByField(FLD_RHS), NT_IDENT) then Exit;
  Recv:= Ent.ChildByField(FLD_LHS);
  if IsType(Recv, NT_IDENT) and SameText(AText(Recv), MEM_SELF) then Exit;
  Result:= WalkRefShapeOk(Recv, AText);
end;

{ ---- what a site says in both passes ---- }

function UnquoteLiteral(const AText: string): string;
begin
  Result:= AText;
  if (Length(Result) >= 2) and (Result[1] = QUOTE) and (Result[Length(Result)] = QUOTE) then
    Result:= StringReplace(Copy(Result, 2, Length(Result) - 2), QUOTE + QUOTE, QUOTE, [rfReplaceAll]);
end;

{ the literal field name of a site, '' when the name is not a plain string literal }
function SiteFieldName(const ASite: TDsSite; AText: TLinText): string;
var
  T: string;
begin
  Result:= '';
  if (ASite.Shape = DSFA_SHAPE_ACCESSOR) or (ASite.Shape = DSFA_SHAPE_INDEX) then Exit;
  if not IsType(ASite.NameArg, NT_STRING) then Exit;
  T:= Trim(AText(ASite.NameArg));
  if (Length(T) < 2) or (T[1] <> QUOTE) or (T[Length(T)] <> QUOTE) then Exit;
  Result:= UnquoteLiteral(T);
end;

{ data_flows.dst_receiver / the dataset as written }
function SiteReceiverText(const ASite: TDsSite; AText: TLinText): string;
begin
  Result:= Trim(AText(RootExpr(ASite)));
end;

{ ---- pass 2: the data-flow walk hooks ---- }

{ B14-3: a field read adds a positioned dsfield source. Shape accessor only where the walk leaves no
  positioned source of its own at the accessor: the root is a local / parameter, or the receiver is
  not ref-shaped. }
{ AIdent is a variable of the routine as the WALK sees it (a slot of its state). The walk reads a
  slot through its state, so every source of the value carries the via-local bit (bit 0 of an
  encoded element) or nothing reached it; any other identifier evaluates to one fresh direct source.
  A parameter still holding its own value reads direct: ask ParamIndexOf first.
  DEPENDS on the element encoding of TDataFlowValue.May (DRagLint.Index.DataFlowFacts.TCollector.ReadSlot). }
function IsWalkVariable(ASite: TDataFlowSite; const AIdent: TTSNode): Boolean;
var
  V: TDataFlowValue;
  E: Integer;
begin
  Result:= False;
  if not IsType(AIdent, NT_IDENT) then Exit;
  V:= ASite.ValueOf(AIdent);
  for E in V.May do
    if not Odd(E) then Exit;
  Result:= True;
end;

procedure LineageExprHook(ASite: TDataFlowSite; const ANode: TTSNode; var AValue: TDataFlowValue);
var
  S   : TDsSite;
  Root: TTSNode;
  Idx : Integer;
begin
  if not ClassifySite(ANode, ASite.NodeText, S) then Exit;
  if S.Mode <> DSFA_MODE_READ then Exit;
  Root:= RootIdent(RootExpr(S), ASite.NodeText);
  Idx := ParamIndexOf(Root, ASite.NodeText);
  if (S.Shape = DSFA_SHAPE_ACCESSOR) and (Idx < 0) and WalkRefShapeOk(S.FieldRecv, ASite.NodeText)
     and not IsWalkVariable(ASite, Root) then Exit;
  AValue:= ASite.Merge(AValue, ASite.NewSource(DF_SRC_DSFIELD, Idx, S.Leaf, SiteFieldName(S, ASite.NodeText), AValue.Cls));
end;

{ B14-2: a field write by `:=` that the walk gives no 'write' row. Never both kinds for one site. }
procedure LineageWriteHook(ASite: TDataFlowSite; const ALhs: TTSNode; const AValue: TDataFlowValue);
var
  S: TDsSite;
begin
  if not ClassifySite(ALhs, ASite.NodeText, S) then Exit;
  if S.Mode <> DSFA_MODE_WRITE then Exit;
  if WalkWritesMember(ALhs, ASite.NodeText) then Exit;
  ASite.EmitRow(DF_DST_DSFIELD, S.Leaf, ParamIndexOf(RootIdent(RootExpr(S), ASite.NodeText), ASite.NodeText),
    SiteFieldName(S, ASite.NodeText), SiteReceiverText(S, ASite.NodeText), AValue);
end;

{ ---- pass 1: the routine-facts hook ---- }

constructor TRoutinePass.Create(const ACtx: TRoutineFactsCtx; ALoopBase: Integer);
var
  S: string;
begin
  inherited Create;
  FCtx     := ACtx;
  FLoopBase:= ALoopBase;
  FText    := TSrcText.Create(ACtx.Src);
  for S in ACtx.Globals do FGlobals:= FGlobals + [LowerCase(S)];
  LoadFields;
end;

destructor TRoutinePass.Destroy;
begin
  FVars.Free;
  FText.Free;
  inherited;
end;

function TRoutinePass.InNames(const ANames: TArray<string>; const ALower: string): Boolean;
var
  S: string;
begin
  Result:= False;
  for S in ANames do
    if S = ALower then Exit(True);
end;

procedure TRoutinePass.ScanInlineDefs(const ANode: TTSNode; ADepth: Integer);
var
  I : Integer;
  Id: TTSNode;
begin
  if ANode.IsNull or (ADepth > High(Word)) then Exit;
  if (ANode.NodeType = NT_DEFPROC) and (ADepth > 0) then Exit;
  if ANode.NodeType = NT_VARDEF then
    for I:= 0 to ANode.NamedChildCount - 1 do
    begin
      Id:= ANode.NamedChild(I);
      if Id.NodeType = NT_IDENT then
      begin
        FInline:= FInline + [LowerCase(FText.TextOf(Id))];
        Break;
      end;
    end;
  for I:= 0 to ANode.NamedChildCount - 1 do ScanInlineDefs(ANode.NamedChild(I), ADepth + 1);
end;

{ AIdent names a parameter, Result or a local of the routine (the data-flow walk's own variable table
  plus the bare inline declarations it registers apart). }
function TRoutinePass.IsLocal(const AIdent: TTSNode): Boolean;
var
  Lo: string;
begin
  if not FVarsBuilt then
  begin
    FVarsBuilt:= True;
    if not (FCtx.IsMainBlock or FCtx.Proc.IsNull) then
    begin
      FVars:= TRoutineVarTable.Build(FCtx.Proc, FCtx.Src);
      ScanInlineDefs(FCtx.Body, 0);
    end;
  end;
  Lo:= LowerCase(FText.TextOf(AIdent));
  Result:= ((FVars <> nil) and (FVars.IndexOfAt(Lo, Integer(AIdent.StartByte)) >= 0)) or InNames(FInline, Lo);
end;

{ The owning class's fields that are NOT form components: a field of the unlabelled leading section
  or of a published section is a component the form file owns (root_kind 'other', spec 4.4), any
  other field is storage of the class (root_kind 'field'). }
procedure TRoutinePass.LoadFields;
var
  Owner: Int64;
  I    : Integer;
  S    : TSymbol;
  Vis  : string;
begin
  FFields:= nil;
  if (FCtx.SymbolIdx < 0) or (FCtx.SymbolIdx > High(FCtx.FileSymbols)) then Exit;
  Owner:= FCtx.FileSymbols[FCtx.SymbolIdx].ParentId;
  if Owner < 0 then Exit;
  for I:= 0 to High(FCtx.FileSymbols) do
  begin
    S:= FCtx.FileSymbols[I];
    if (S.Kind <> skField) or (S.ParentId <> Owner) then Continue;
    Vis:= LowerCase(Trim(S.Modifiers));
    if (Vis = VIS_PUBLISHED) or ((Vis = VIS_PUBLIC) and not S.VisExplicit) then Continue;
    FFields:= FFields + [LowerCase(S.Name)];
  end;
end;

procedure TRoutinePass.RootOf(const ASite: TDsSite; AInWith: Boolean; out AKind, AName: string; out AIndex: Integer);
var
  Expr, Root: TTSNode;
  Lo        : string;
begin
  AKind := DSFA_ROOT_OTHER;
  AName := '';
  AIndex:= -1;
  Expr:= RootExpr(ASite);
  if Expr.IsNull then
  begin
    if AInWith then AKind:= DSFA_ROOT_WITH;
    Exit;
  end;
  Root:= RootIdent(Expr, FText.TextOf);
  if Root.IsNull then Exit;
  AName := FText.TextOf(Root);
  Lo    := LowerCase(AName);
  AIndex:= ParamIndexOf(Root, FText.TextOf);
  if AIndex >= 0 then AKind:= DSFA_ROOT_PARAM
  else if IsLocal(Root) then AKind:= DSFA_ROOT_LOCAL
  else if InNames(FFields, Lo) then AKind:= DSFA_ROOT_FIELD
  else if InNames(FGlobals, Lo) then AKind:= DSFA_ROOT_GLOBAL;
end;

{ the statement holding ANode: its nearest assignment, else its nearest `statement`, else itself }
function StatementOf(const ANode: TTSNode): TTSNode;
var
  Cur  : TTSNode;
  Guard: Integer;
begin
  Result:= ANode;
  Cur:= ANode;
  for Guard:= 1 to LIN_DEPTH_MAX do
  begin
    if Cur.IsNull then Exit;
    if (Cur.NodeType = NT_ASSIGN) or (Cur.NodeType = NT_STATEMENT) then Exit(Cur);
    if (Cur.NodeType = NT_DEFPROC) or (Cur.NodeType = NT_WITH) then Exit;
    Result:= Cur;
    Cur:= Cur.Parent;
  end;
  Result:= ANode;
end;

procedure TRoutinePass.EmitAccess(const ANode: TTSNode; const ASite: TDsSite; const AWithCtx: string);
var
  R   : TDsFieldAccessRow;
  Stmt: TTSNode;
  T   : string;
begin
  R:= Default(TDsFieldAccessRow);
  RootOf(ASite, AWithCtx <> '', R.RootKind, R.RootName, R.RootIndex);
  { shape accessor, READ: only where no E1 / E2 row names the field already (spec B14-1) }
  if (ASite.Shape = DSFA_SHAPE_ACCESSOR) and (ASite.Mode = DSFA_MODE_READ) and (R.RootKind = DSFA_ROOT_OTHER)
     and (AWithCtx = '') then Exit;
  R.FileId  := FCtx.Sym.FileId;
  R.SymbolId:= FCtx.Sym.Id;
  R.Mode    := ASite.Mode;
  R.Line    := FText.Line(ASite.Leaf);
  R.Col     := FText.Col(ASite.Leaf);
  R.Shape   := ASite.Shape;
  R.Accessor:= ASite.Accessor;
  R.WithCtx := AWithCtx;
  if ASite.Shape = DSFA_SHAPE_ACCESSOR then
  begin
    R.FieldText:= Trim(FText.TextOf(ASite.FieldRecv));
    R.NameKind := DSFA_NAME_COMPONENT;
  end
  else
  begin
    R.DatasetText:= Trim(FText.TextOf(ASite.Dataset));
    R.FieldName  := SiteFieldName(ASite, FText.TextOf);
    T:= Trim(FText.TextOf(ASite.NameArg));
    if ASite.Shape = DSFA_SHAPE_INDEX then R.NameKind:= DSFA_NAME_INDEX
    else if IsType(ASite.NameArg, NT_STRING) and ((R.FieldName <> '') or (T = QUOTE + QUOTE)) then R.NameKind:= DSFA_NAME_LITERAL
    { a name held in a parameter / local is built at run time; any other identifier reads as a constant }
    else if IsDottedIdentChain(ASite.NameArg) and not (IsType(ASite.NameArg, NT_IDENT)
            and ((ParamIndexOf(ASite.NameArg, FText.TextOf) >= 0) or IsLocal(ASite.NameArg))) then R.NameKind:= DSFA_NAME_CONST
    else R.NameKind:= DSFA_NAME_EXPR;
    if R.NameKind <> DSFA_NAME_LITERAL then R.NameText:= Copy(T, 1, DSFA_NAME_TEXT_MAX);
  end;
  if (ASite.Mode = DSFA_MODE_WRITE) and not ASite.Rhs.IsNull then
  begin
    R.RhsStartLine:= FText.Line(ASite.Rhs);
    R.RhsStartCol := FText.Col(ASite.Rhs);
    R.RhsEndLine  := FText.EndLine(ASite.Rhs);
    R.RhsEndCol   := FText.EndCol(ASite.Rhs);
  end;
  Stmt:= StatementOf(ANode);
  R.StmtLine:= FText.Line(Stmt);
  R.StmtCol := FText.Col(Stmt);
  FAccesses:= FAccesses + [R];
  { B14-6b: the walk does not enter a `with` body, so the flow rows of this write come from here }
  if (AWithCtx <> '') and (ASite.Mode = DSFA_MODE_WRITE) and not ASite.Rhs.IsNull then WithSources(R, ASite.Rhs, 0);
end;

procedure TRoutinePass.AddFlow(const ARow: TDsFieldAccessRow; const ASrcKind: string; ASrcIndex, ASrcLine, ASrcCol: Integer;
  const ASrcName: string);
var
  F: TDataFlowRow;
  I: Integer;
begin
  for I:= High(FFlows) downto 0 do
  begin
    F:= FFlows[I];
    if (F.DstLine <> ARow.Line) or (F.DstCol <> ARow.Col) then Break;
    if (F.SrcKind = ASrcKind) and (F.SrcIndex = ASrcIndex) and (F.SrcLine = ASrcLine) and (F.SrcCol = ASrcCol)
       and SameText(F.SrcName, ASrcName) then Exit;
  end;
  F:= Default(TDataFlowRow);
  F.SymbolId   := FCtx.Sym.Id;
  F.OwnerId    := if FCtx.Sym.ParentId > 0 then FCtx.Sym.ParentId else 0;
  F.DstKind    := DF_DST_DSFIELD;
  F.DstLine    := ARow.Line;
  F.DstCol     := ARow.Col;
  F.DstIndex   := ARow.RootIndex;
  F.DstName    := ARow.FieldName;
  F.DstReceiver:= if ARow.Shape = DSFA_SHAPE_ACCESSOR then ARow.FieldText else ARow.DatasetText;
  F.SrcKind    := ASrcKind;
  F.SrcIndex   := ASrcIndex;
  F.SrcLine    := ASrcLine;
  F.SrcCol     := ASrcCol;
  F.SrcName    := ASrcName;
  F.Cond       := True;
  FFlows:= FFlows + [F];
end;

{ a bare identifier in a `with` body: a parameter, class field or unit variable is itself, a local gives
  nothing (what reached it is not known here), anything else is a positioned 'ref' }
procedure TRoutinePass.WithIdentSource(const ARow: TDsFieldAccessRow; const AIdent: TTSNode);
var
  Name, Lo: string;
  Idx     : Integer;
begin
  Name:= FText.TextOf(AIdent);
  Lo  := LowerCase(Name);
  if Lo = MEM_SELF then Exit;
  Idx:= ParamIndexOf(AIdent, FText.TextOf);
  if Idx >= 0 then AddFlow(ARow, DF_SRC_PARAM, Idx, 0, 0, Name)
  else if IsLocal(AIdent) then Exit
  else if InNames(FFields, Lo) then AddFlow(ARow, DF_SRC_FIELD, -1, 0, 0, Name)
  else if InNames(FGlobals, Lo) then AddFlow(ARow, DF_SRC_GLOBAL, -1, 0, 0, Name)
  else AddFlow(ARow, DF_SRC_REF, -1, FText.Line(AIdent), FText.Col(AIdent), Name);
end;

{ `R.M` in a `with` body: a positioned 'ref' at M (as the walk does), plus the root of R when it is a
  parameter / class field / unit variable, plus whatever a call inside R reads }
procedure TRoutinePass.WithDotSource(const ARow: TDsFieldAccessRow; const ADot: TTSNode; ADepth: Integer);
var
  M, Recv, Root: TTSNode;
  Lo           : string;
begin
  M:= ADot.ChildByField(FLD_RHS);
  if IsType(M, NT_IDENT) then AddFlow(ARow, DF_SRC_REF, -1, FText.Line(M), FText.Col(M), FText.TextOf(M));
  Recv:= ADot.ChildByField(FLD_LHS);
  if not IsDottedIdentChain(Recv) then
  begin
    WithSources(ARow, Recv, ADepth + 1);
    Exit;
  end;
  Root:= RootIdent(Recv, FText.TextOf);
  if Root.IsNull then Exit;
  Lo:= LowerCase(FText.TextOf(Root));
  if (ParamIndexOf(Root, FText.TextOf) >= 0) or InNames(FFields, Lo) or InNames(FGlobals, Lo) then WithIdentSource(ARow, Root);
end;

{ The sources of an expression inside a `with` body, flow-insensitive: a field read is a 'dsfield'
  source; everything else by WithIdentSource / WithDotSource. }
procedure TRoutinePass.WithSources(const ARow: TDsFieldAccessRow; const ANode: TTSNode; ADepth: Integer);
var
  S   : TDsSite;
  NT  : string;
  Root: TTSNode;
  I   : Integer;
begin
  if ANode.IsNull or (ADepth > LIN_DEPTH_MAX) then Exit;
  NT:= ANode.NodeType;
  if (NT = NT_DEFPROC) or (NT = NT_STRING) then Exit;
  if ClassifySite(ANode, FText.TextOf, S) and (S.Mode = DSFA_MODE_READ) then
  begin
    Root:= RootIdent(RootExpr(S), FText.TextOf);
    AddFlow(ARow, DF_SRC_DSFIELD, ParamIndexOf(Root, FText.TextOf), FText.Line(S.Leaf), FText.Col(S.Leaf),
      SiteFieldName(S, FText.TextOf));
    WithSources(ARow, S.NameArg, ADepth + 1);
  end
  else if NT = NT_IDENT then WithIdentSource(ARow, ANode)
  else if NT = NT_DOT then WithDotSource(ARow, ANode, ADepth)
  else
    for I:= 0 to ANode.NamedChildCount - 1 do WithSources(ARow, ANode.NamedChild(I), ADepth + 1);
end;

{ One loop_facts row. The condition range: while / repeat the condition, for-in the collection, for
  everything from the start assignment to the last expression before `do`. End columns are exclusive. }
function BuildLoopRow(const ASym: TSymbol; AText: TSrcText; const ANode: TTSNode; const AKind: string;
  AParent: Integer): TLoopFactRow;
var
  First, Last, Body, C: TTSNode;
  I                   : Integer;
begin
  Result:= Default(TLoopFactRow);
  Result.FileId   := ASym.FileId;
  Result.SymbolId := ASym.Id;
  Result.Parent   := AParent;
  Result.Kind     := AKind;
  Result.StartLine:= AText.Line(ANode);
  Result.StartCol := AText.Col(ANode);
  Result.EndLine  := AText.EndLine(ANode);
  Result.EndCol   := AText.EndCol(ANode);
  First:= Default(TTSNode);
  Last := Default(TTSNode);
  if (AKind = LOOP_KIND_WHILE) or (AKind = LOOP_KIND_REPEAT) then First:= ANode.ChildByField(FLD_CONDITION)
  else if AKind = LOOP_KIND_FOR_IN then First:= ANode.ChildByField(FLD_ITERABLE)
  else
  begin
    Body:= ANode.ChildByField(FLD_BODY);
    for I:= 0 to ANode.NamedChildCount - 1 do
    begin
      C:= ANode.NamedChild(I);
      if SameNode(C, Body) or IsTrivia(C) then Continue;
      if First.IsNull then First:= C;
      Last:= C;
    end;
  end;
  if Last.IsNull then Last:= First;
  Result.CondStartLine:= AText.Line(First);
  Result.CondStartCol := AText.Col(First);
  Result.CondEndLine  := AText.EndLine(Last);
  Result.CondEndCol   := AText.EndCol(Last);
end;

procedure TRoutinePass.Walk(const ANode: TTSNode; const AWithCtx: string; ALoop, ADepth: Integer);
var
  NT, Ctx, Kind: string;
  S            : TDsSite;
  Body, C      : TTSNode;
  I, Loop      : Integer;
begin
  if ANode.IsNull or (ADepth > High(Word)) then Exit;
  NT:= ANode.NodeType;
  { a nested routine is its own routine; the routine itself is entered at its body, never at a defProc }
  if NT = NT_DEFPROC then Exit;
  if ClassifySite(ANode, FText.TextOf, S) then EmitAccess(ANode, S, AWithCtx);
  if NT = NT_WITH then
  begin
    Body:= ANode.ChildByField(FLD_BODY);
    Ctx:= AWithCtx;
    for I:= 0 to ANode.NamedChildCount - 1 do
    begin
      C:= ANode.NamedChild(I);
      if SameNode(C, Body) or IsTrivia(C) then Continue;
      Walk(C, AWithCtx, ALoop, ADepth + 1);
      { innermost first: a later entity of `with A, B do` shadows an earlier one }
      Ctx:= if Ctx = '' then Trim(FText.TextOf(C)) else Trim(FText.TextOf(C)) + LIN_WITH_SEP + Ctx;
    end;
    Walk(Body, Ctx, ALoop, ADepth + 1);
    Exit;
  end;
  Loop:= ALoop;
  Kind:= '';
  if NT = NT_WHILE then Kind:= LOOP_KIND_WHILE
  else if NT = NT_REPEAT then Kind:= LOOP_KIND_REPEAT
  else if NT = NT_FOR then Kind:= LOOP_KIND_FOR
  else if NT = NT_FOREACH then Kind:= LOOP_KIND_FOR_IN;
  if Kind <> '' then
  begin
    FLoops:= FLoops + [BuildLoopRow(FCtx.Sym, FText, ANode, Kind, ALoop)];
    Loop:= FLoopBase + High(FLoops);
  end;
  for I:= 0 to ANode.NamedChildCount - 1 do Walk(ANode.NamedChild(I), AWithCtx, Loop, ADepth + 1);
end;

procedure TRoutinePass.Run;
var
  I: Integer;
begin
  if FCtx.Body.IsNull then Exit;
  { the body node may itself be a statement; a main block's body is the tree root }
  for I:= 0 to FCtx.Body.NamedChildCount - 1 do Walk(FCtx.Body.NamedChild(I), '', -1, 0);
end;

{ ---- TFieldLineage ---- }

class procedure TFieldLineage.CollectRoutine(const ACtx: TRoutineFactsCtx; var AFlows: TArray<TDataFlowRow>;
  var AFacts: TExtFileFacts);
var
  Pass: TRoutinePass;
begin
  Pass:= TRoutinePass.Create(ACtx, Length(AFacts.LoopFacts));
  try
    Pass.Run;
    if Pass.Accesses <> nil then AFacts.DsFieldAccesses:= AFacts.DsFieldAccesses + Pass.Accesses;
    if Pass.Loops <> nil then AFacts.LoopFacts:= AFacts.LoopFacts + Pass.Loops;
    if Pass.Flows <> nil then AFlows:= AFlows + Pass.Flows;
  finally
    Pass.Free;
  end;
end;

class procedure TFieldLineage.RegisterHooks;
begin
  if GRegistered then Exit;
  GRegistered:= True;
  TIndexer.RegisterRoutineFactsHook(LIN_HOOK_NAME, TFieldLineage.CollectRoutine);
  TDataFlowFacts.RegisterExprHook(NT_DOT, LineageExprHook);
  TDataFlowFacts.RegisterExprHook(NT_CALL, LineageExprHook);
  TDataFlowFacts.RegisterExprHook(NT_SUBSCRIPT, LineageExprHook);
  TDataFlowFacts.RegisterWriteHook(LineageWriteHook);
end;

initialization
  TFieldLineage.RegisterHooks;

end.
