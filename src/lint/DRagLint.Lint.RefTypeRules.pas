unit DRagLint.Lint.RefTypeRules;

{ The project lint rules that stand on index fact F1, table ref_types: the static
  type of a reference (1.44, lane rulesf1; spec lanes\143\fabcyc\REPORT.md section 5).

  One walk over each unit's tree. An expression's static type comes ONLY from
  ref_types and from a type name written in the source, never from a guess:

    * x, a.b.c, F(y) -- the ref_types row of the last name;
    * TFoo(x), x as TFoo -- the written type.

  Anything else (a subscript, a dereference, an arithmetic expression) has no
  static type here and the rules stay silent. A subscript is excluded on purpose:
  the row of `List` in `List[i]` is the type of the list, not of the element.

  A class's ancestry is the transitive closure of type_ancestors in the project,
  continued by name in the library index. Homonyms are intersected: an ancestor
  counts only when EVERY class of that name has it, so a homonym can only make a
  rule silent, never make it fire. No library index and an unresolved ancestor
  leave the closure incomplete, which is also silence.

  Inside a `with` body a bare name may bind to a member of the with-expression,
  and that binding is the part of the index a rule cannot check, so an operand
  there has no static type.

  An index older than 1.44 has no ref_types table: every rule answers nothing. }

interface

uses
  DRagLint.Core.Model
  , DRagLint.Core.Interfaces
  ;

const
  /// <summary>Rule id: `x is T` where the static type of x already descends from T.</summary>
  IS_ALWAYS_TRUE_RULE = 'is-always-true';
  /// <summary>Rule id: `with TFoo.Create do` that nobody frees.</summary>
  WITH_ON_TEMPORARY_RULE = 'with-on-temporary';
  /// <summary>Rule id: a cast to an ancestor and straight back down, TLeaf(TBase(x)).</summary>
  UPCAST_THEN_DOWNCAST_RULE = 'upcast-then-downcast';
  /// <summary>Every project rule this unit emits, as `--rule` and dl:ok markers spell them.</summary>
  REF_TYPE_RULES: array[0..2] of string = (IS_ALWAYS_TRUE_RULE, UPCAST_THEN_DOWNCAST_RULE, WITH_ON_TEMPORARY_RULE);
  /// <summary>The ones that ship OFF; each names why in the catalog.</summary>
  REF_TYPE_RULES_OFF: array of string = [];

/// <summary>True when the rule ships OFF by default (see the catalog).</summary>
/// <param name="ARuleId">One of REF_TYPE_RULES.</param>
/// <returns>The value to hand TLintConfig.ShouldKeep as ADefaultDisabled.</returns>
function RefTypeRuleDefaultOff(const ARuleId: string): Boolean;

/// <summary>Runs the rules on index fact F1 over a project index.</summary>
/// <param name="AStore">The project index; nil, a store that is not SQLite, or an
/// index with no ref_types table yields no findings.</param>
/// <param name="ALibStore">The platform library index, or nil. Without it a class
/// on a library base has an incomplete ancestry and the rules that need the
/// ancestor stay silent.</param>
/// <param name="ARules">The rule ids to evaluate; empty yields no findings.</param>
/// <param name="AOnlyFileId">One file's id, or 0 for every file of the index.</param>
/// <returns>One finding per offending expression, anchored at it.</returns>
/// <remarks>Reads one file's refs per file (one query) and parses through
/// TAstParseCache. A ref whose name no longer matches the source at its position
/// answers nothing, so a stale index errs towards silence.</remarks>
function CollectRefTypeRules(const AStore, ALibStore: ISymbolStore; const ARules: TArray<string>;
  AOnlyFileId: Int64): TArray<TLintFinding>;

implementation

uses
  System.SysUtils
  , System.Generics.Collections
  , System.RegularExpressions
  , Data.DB
  , FireDAC.Comp.Client
  , FireDAC.Stan.Param
  , TreeSitter
  , DRagLint.Diagnostics.ParseCache
  , DRagLint.Storage.SQLite
  ;

const
  TYPE_NODE_ID     = 'identifier';
  NODE_DOT         = 'exprDot';
  NODE_CALL        = 'exprCall';
  NODE_PARENS      = 'exprParens';
  { The grammar aliases exprAs to exprBinary: `x as T` is told apart by its operator node. }
  OP_NODE_AS       = 'kAs';
  NODE_BINARY      = 'exprBinary';
  NODE_WITH        = 'with';
  FIELD_LHS        = 'lhs';
  FIELD_RHS        = 'rhs';
  FIELD_OP         = 'operator';
  FIELD_ENTITY     = 'entity';
  FIELD_ARGS       = 'args';
  OP_IS            = 'is';
  ROOT_CLASS       = 'tobject';
  CLASS_COMPONENT  = 'tcomponent';
  CLASS_THREAD     = 'tthread';
  FIELD_BODY       = 'body';
  VIA_CTOR         = 'ctor';
  NIL_WORD         = 'nil';
  { A call that ends the object's life, or hands the job to the object. }
  FREE_WORDS_RX    = '\b(free|destroy|release|disposeof|freeandnil|freeonterminate)\b';
  SEV_WARNING      = 'warning';
  { Bits of the line in a position key; a column stays far below 2^20. }
  POS_LINE_SHIFT   = 20;

type
  /// <summary>The ref_types row of one reference, as read for one file.</summary>
  TRefFact = record
    Name        : string;
    SymbolId    : Int64 ;
    TypeSymbolId: Int64 ;
    TypeQName   : string;
    Via         : string;
    Enclosing   : Int64 ;
    { Two refs at one position disagree on the type: no answer. }
    Conflict    : Boolean;
  end;

  /// <summary>What the rules need to know about one type.</summary>
  TTypeFacts = record
    Known     : Boolean;
    IsClass   : Boolean;
    IsIntf    : Boolean;
    /// <summary>The written or declared name, for messages.</summary>
    Name      : string;
    /// <summary>Lower-case leaf names of the type and of every ancestor.</summary>
    Closure   : TArray<string>;
    /// <summary>False when some ancestor could not be followed.</summary>
    Complete  : Boolean;
    /// <summary>The name stands for several types, so it identifies none of them.</summary>
    Homonym   : Boolean;
    function HasAncestor(const ALeaf: string): Boolean;
  end;

  /// <summary>The static type of one expression.</summary>
  TExprType = record
    Known: Boolean;
    Facts: TTypeFacts;
  end;

  /// <summary>One run over a project index.</summary>
  TRefTypeScan = class
    strict private
      FStore   : ISymbolStore;
      FLib     : ISymbolStore;
      FRules   : TArray<string>;
      FFindings: TList<TLintFinding>;
      FRefs    : TDictionary<Int64, TRefFact>;
      FByName  : TDictionary<string, TTypeFacts>;
      FById    : TDictionary<Int64, TTypeFacts>;
      FLibName : TDictionary<string, TTypeFacts>;
      FQuery   : TFDQuery;
      FPath    : string;
      FFileId  : Int64;
      FSrc     : TBytes;
      FWithDepth: Integer;
      function Wants(const ARuleId: string): Boolean;
      function Text(const ANode: TTSNode): string;
      function FactAt(const ANode: TTSNode; out AFact: TRefFact): Boolean;
      procedure LoadRefs(AFileId: Int64);
      procedure Emit(const ARuleId: string; const ANode: TTSNode; const AMessage: string);
      function ClosureFromStore(const AStore: ISymbolStore; const ASym: TSymbol; AOutermost: Boolean;
        var AFacts: TTypeFacts): Boolean;
      function FactsOfSymbol(const AStore: ISymbolStore; const ASym: TSymbol; AOutermost: Boolean): TTypeFacts;
      function MergeSymbols(const AStore: ISymbolStore; const ASyms: TArray<TSymbol>; const AName: string;
        AOutermost: Boolean): TTypeFacts;
      function LibraryFacts(const ALeaf: string): TTypeFacts;
      function FactsOfName(const AName: string): TTypeFacts;
      function FactsOfId(AId: Int64): TTypeFacts;
      function WrittenType(const ANode: TTSNode): TTypeFacts;
      function CastTarget(const ANode: TTSNode; out AFacts: TTypeFacts; out AOperand: TTSNode): Boolean;
      function StaticType(const ANode: TTSNode): TExprType;
      function CastParts(const ANode: TTSNode; out ATarget: TTypeFacts; out AOperand: TTSNode): Boolean;
      procedure CheckUpcastThenDowncast(const ANode: TTSNode; const AOuter: TTypeFacts; const AOperand: TTSNode);
      procedure CheckCast(const ANode: TTSNode);
      procedure CheckWith(const ANode: TTSNode);
      procedure CheckIs(const ANode: TTSNode);
      procedure Walk(const ANode: TTSNode);
    public
      constructor Create(const AStore, ALibStore: ISymbolStore; const ARules: TArray<string>);
      destructor Destroy; override;
      /// <summary>Scans one file of the index.</summary>
      procedure ScanFile(AFileId: Int64);
      /// <summary>True when the index carries the ref_types table.</summary>
      function HasFact: Boolean;
      /// <summary>The findings so far, in scan order.</summary>
      function Findings: TArray<TLintFinding>;
  end;

function IsAsNode(const ANode: TTSNode): Boolean;
begin
  Result:= (ANode.NodeType = NODE_BINARY) and (not ANode.ChildByField(FIELD_OP).IsNull)
    and (ANode.ChildByField(FIELD_OP).NodeType = OP_NODE_AS);
end;

function LeafOf(const AName: string): string;
var
  Dot: Integer;
begin
  Result:= AName.Trim;
  Dot   := Result.LastDelimiter('.');
  if Dot >= 0 then Result:= Result.Substring(Dot + 1);
end;

function TTypeFacts.HasAncestor(const ALeaf: string): Boolean;
begin
  Result:= False;
  for var S: string in Closure do
    if S = ALeaf then Exit(True);
end;

function PosKey(ALine, ACol: Integer): Int64;
begin
  Result:= (Int64(ALine) shl POS_LINE_SHIFT) or Int64(ACol);
end;

constructor TRefTypeScan.Create(const AStore, ALibStore: ISymbolStore; const ARules: TArray<string>);
begin
  inherited Create;
  FStore   := AStore;
  FLib     := ALibStore;
  FRules   := ARules;
  FFindings:= TList<TLintFinding>.Create;
  FRefs    := TDictionary<Int64, TRefFact>.Create;
  FByName  := TDictionary<string, TTypeFacts>.Create;
  FById    := TDictionary<Int64, TTypeFacts>.Create;
  FLibName := TDictionary<string, TTypeFacts>.Create;
  FQuery   := TFDQuery.Create(nil);
  FQuery.Connection:= (AStore as TSQLiteSymbolStore).GetConnection;
end;

destructor TRefTypeScan.Destroy;
begin
  FQuery.Free;
  FLibName.Free;
  FById.Free;
  FByName.Free;
  FRefs.Free;
  FFindings.Free;
  inherited Destroy;
end;

function TRefTypeScan.HasFact: Boolean;
begin
  FQuery.SQL.Text:= 'SELECT 1 FROM sqlite_master WHERE type = ''table'' AND name = ''ref_types''';
  FQuery.Open;
  try
    Result:= not FQuery.Eof;
  finally
    FQuery.Close;
  end;
end;

function TRefTypeScan.Findings: TArray<TLintFinding>;
begin
  Result:= FFindings.ToArray;
end;

function TRefTypeScan.Wants(const ARuleId: string): Boolean;
begin
  Result:= False;
  for var S: string in FRules do
    if SameText(S, ARuleId) then Exit(True);
end;

function TRefTypeScan.Text(const ANode: TTSNode): string;
var
  StartIdx: Integer;
  Len     : Integer;
begin
  Result:= '';
  if ANode.IsNull then Exit;
  StartIdx:= Integer(ANode.StartByte);
  Len     := Integer(ANode.EndByte) - StartIdx;
  if (Len <= 0) or (StartIdx < 0) or (StartIdx + Len > Length(FSrc)) then Exit;
  Result:= TEncoding.UTF8.GetString(FSrc, StartIdx, Len);
end;

procedure TRefTypeScan.LoadRefs(AFileId: Int64);
const
  COL_LINE = 0; COL_COL = 1; COL_NAME = 2; COL_SYM = 3; COL_ENCL = 4; COL_TID = 5; COL_QNAME = 6; COL_VIA = 7;  // dl:ok multiple-statements-per-line -- a column map reads as one row of the SELECT below
begin
  FRefs.Clear;
  FQuery.SQL.Text:= 'SELECT r.start_line, r.start_col, r.name_text, r.symbol_id, r.enclosing_symbol_id, ' +
                    '  t.type_symbol_id, t.type_qname, t.via ' +
                    'FROM refs r LEFT JOIN ref_types t ON t.ref_id = r.id WHERE r.file_id = :f';
  FQuery.ParamByName('f').AsLargeInt:= AFileId;
  FQuery.Open;
  try
    while not FQuery.Eof do
    begin
      var Key: Int64:= PosKey(FQuery.Fields[COL_LINE].AsInteger, FQuery.Fields[COL_COL].AsInteger);
      var F: TRefFact:= Default(TRefFact);
      F.Name        := FQuery.Fields[COL_NAME].AsString;
      F.SymbolId    := FQuery.Fields[COL_SYM].AsLargeInt;
      F.Enclosing   := FQuery.Fields[COL_ENCL].AsLargeInt;
      F.TypeSymbolId:= FQuery.Fields[COL_TID].AsLargeInt;
      F.TypeQName   := FQuery.Fields[COL_QNAME].AsString;
      F.Via         := FQuery.Fields[COL_VIA].AsString;
      var Old: TRefFact;
      if FRefs.TryGetValue(Key, Old) then
      begin
        { A second ref at one position: an untyped one adds nothing; a typed one
          that disagrees leaves no answer. }
        if F.TypeQName = '' then F:= Old
        else if (Old.TypeQName <> '') and not SameText(Old.TypeQName, F.TypeQName) then F.Conflict:= True;
      end;
      FRefs.AddOrSetValue(Key, F);
      FQuery.Next;
    end;
  finally
    FQuery.Close;
  end;
end;

function TRefTypeScan.FactAt(const ANode: TTSNode; out AFact: TRefFact): Boolean;
begin
  AFact:= Default(TRefFact);
  Result:= (not ANode.IsNull)
    and FRefs.TryGetValue(PosKey(Integer(ANode.StartPoint.Row) + 1, Integer(ANode.StartPoint.Column) + 1), AFact)
    and (not AFact.Conflict)
    and SameText(AFact.Name, Text(ANode));
end;

procedure TRefTypeScan.Emit(const ARuleId: string; const ANode: TTSNode; const AMessage: string);
var
  F: TLintFinding;
begin
  F:= Default(TLintFinding);
  F.RuleId   := ARuleId;
  F.Severity := SEV_WARNING;
  F.Message  := AMessage;
  F.FileId   := FFileId;
  F.FilePath := FPath;
  F.StartLine:= Integer(ANode.StartPoint.Row) + 1;
  F.StartCol := Integer(ANode.StartPoint.Column) + 1;
  F.EndLine  := Integer(ANode.EndPoint.Row) + 1;
  F.EndCol   := Integer(ANode.EndPoint.Column) + 1;
  FFindings.Add(F);
end;

function TRefTypeScan.ClosureFromStore(const AStore: ISymbolStore; const ASym: TSymbol; AOutermost: Boolean;
  var AFacts: TTypeFacts): Boolean;
var
  Names: TList<string>;
begin
  Result:= True;
  Names := TList<string>.Create;
  try
    Names.Add(ASym.Name.ToLower);
    for var A: TTypeAncestor in AStore.GetTransitiveAncestors(ASym.Id) do
    begin
      var Leaf: string:= LeafOf(A.Name).ToLower;
      if Leaf.Contains('<') then
      begin
        { A generic base: its instantiation is a different class from a plain
          homonym, so it is kept verbatim and not followed. }
        Names.Add(Leaf);
        Result:= False;
        Continue;
      end;
      if not Names.Contains(Leaf) then Names.Add(Leaf);
      if A.Resolved then Continue;
      if not AOutermost then
      begin
        Result:= False;
        Continue;
      end;
      var Lib: TTypeFacts:= LibraryFacts(Leaf);
      if not Lib.Known then
      begin
        Result:= False;
        Continue;
      end;
      if not Lib.Complete then Result:= False;
      for var N: string in Lib.Closure do
        if not Names.Contains(N) then Names.Add(N);
    end;
    if ASym.Kind = skClass then
      if not Names.Contains(ROOT_CLASS) then Names.Add(ROOT_CLASS);
    AFacts.Closure:= Names.ToArray;
  finally
    Names.Free;
  end;
end;

function TRefTypeScan.FactsOfSymbol(const AStore: ISymbolStore; const ASym: TSymbol; AOutermost: Boolean): TTypeFacts;
begin
  Result        := Default(TTypeFacts);
  Result.Known  := True;
  Result.Name   := ASym.Name;
  Result.IsClass:= ASym.Kind = skClass;
  Result.IsIntf := ASym.Kind = skInterface;
  if not (Result.IsClass or Result.IsIntf) then Exit;
  Result.Complete:= ClosureFromStore(AStore, ASym, AOutermost, Result);
end;

function TRefTypeScan.MergeSymbols(const AStore: ISymbolStore; const ASyms: TArray<TSymbol>; const AName: string;
  AOutermost: Boolean): TTypeFacts;
const
  TYPE_KINDS = [skClass, skInterface, skRecord, skEnum, skTypeAlias];
begin
  Result:= Default(TTypeFacts);
  var First: Boolean:= True;
  for var S: TSymbol in ASyms do
  begin
    if not (S.Kind in TYPE_KINDS) then Continue;
    var One: TTypeFacts:= FactsOfSymbol(AStore, S, AOutermost);
    if First then
    begin
      Result:= One;
      First := False;
      Continue;
    end;
    { A homonym: only what ALL of them agree on survives. }
    Result.Homonym := True;
    Result.IsClass := Result.IsClass and One.IsClass;
    Result.IsIntf  := Result.IsIntf and One.IsIntf;
    Result.Complete:= Result.Complete and One.Complete;
    var Keep: TArray<string>:= nil;
    for var N: string in Result.Closure do
      if One.HasAncestor(N) then Keep:= Keep + [N];
    Result.Closure:= Keep;
  end;
  if Result.Known then Result.Name:= AName;
end;

function TRefTypeScan.LibraryFacts(const ALeaf: string): TTypeFacts;
begin
  Result:= Default(TTypeFacts);
  if FLib = nil then Exit;
  var Key: string:= ALeaf.ToLower;
  if FLibName.TryGetValue(Key, Result) then Exit;
  Result:= MergeSymbols(FLib, FLib.FindSymbolsByExactName(ALeaf), ALeaf, {AOutermost=}False);
  FLibName.Add(Key, Result);
end;

function TRefTypeScan.FactsOfName(const AName: string): TTypeFacts;
begin
  var Leaf: string:= LeafOf(AName);
  var Key : string:= Leaf.ToLower;
  if FByName.TryGetValue(Key, Result) then Exit;
  if Leaf.Contains('<') or Leaf.Contains(' ') then Result:= Default(TTypeFacts)
  else
  begin
    Result:= MergeSymbols(FStore, FStore.FindSymbolsByExactName(Leaf), Leaf, {AOutermost=}True);
    if not Result.Known then Result:= LibraryFacts(Leaf);
  end;
  FByName.Add(Key, Result);
end;

function TRefTypeScan.FactsOfId(AId: Int64): TTypeFacts;
begin
  if FById.TryGetValue(AId, Result) then Exit;
  Result:= FactsOfSymbol(FStore, FStore.GetSymbolById(AId), {AOutermost=}True);
  FById.Add(AId, Result);
end;

function TRefTypeScan.WrittenType(const ANode: TTSNode): TTypeFacts;
begin
  Result:= Default(TTypeFacts);
  if ANode.IsNull then Exit;
  if (ANode.NodeType <> TYPE_NODE_ID) and (ANode.NodeType <> NODE_DOT) then Exit;
  var Name: TTSNode:= if ANode.NodeType = NODE_DOT then ANode.ChildByField(FIELD_RHS) else ANode;
  var Fact: TRefFact;
  if FactAt(Name, Fact) and (Fact.SymbolId > 0) then
  begin
    Result:= FactsOfId(Fact.SymbolId);
    if Result.IsClass or Result.IsIntf then Exit;
    { A bound name that is not a type (a variable, a routine) is not a type name. }
    Exit(Default(TTypeFacts));
  end;
  Result:= FactsOfName(Text(Name));
end;

function TRefTypeScan.CastTarget(const ANode: TTSNode; out AFacts: TTypeFacts; out AOperand: TTSNode): Boolean;
begin
  Result:= False;
  AFacts:= Default(TTypeFacts);
  AOperand:= Default(TTSNode);
  if ANode.NodeType <> NODE_CALL then Exit;
  var Ent: TTSNode:= ANode.ChildByField(FIELD_ENTITY);
  var Args: TTSNode:= ANode.ChildByField(FIELD_ARGS);
  if Ent.IsNull or Args.IsNull or (Args.NamedChildCount <> 1) then Exit;
  AFacts:= WrittenType(Ent);
  if not (AFacts.IsClass or AFacts.IsIntf) then Exit;
  AOperand:= Args.NamedChild(0);
  Result:= True;
end;

function TRefTypeScan.StaticType(const ANode: TTSNode): TExprType;
var
  Fact: TRefFact;
begin
  Result:= Default(TExprType);
  if ANode.IsNull then Exit;
  var NT: string:= ANode.NodeType;
  if NT = NODE_PARENS then Exit(StaticType(ANode.NamedChild(0)));
  if IsAsNode(ANode) then
  begin
    Result.Facts:= WrittenType(ANode.ChildByField(FIELD_RHS));
    Result.Known:= Result.Facts.IsClass or Result.Facts.IsIntf;
    Exit;
  end;
  var Name: TTSNode:= Default(TTSNode);
  if NT = TYPE_NODE_ID then Name:= ANode
  else if NT = NODE_DOT then Name:= ANode.ChildByField(FIELD_RHS)
  else if NT = NODE_CALL then
  begin
    var Operand: TTSNode;
    var Target : TTypeFacts;
    if CastTarget(ANode, Target, Operand) then
    begin
      Result.Facts:= Target;
      Result.Known:= True;
      Exit;
    end;
    var Ent: TTSNode:= ANode.ChildByField(FIELD_ENTITY);
    if Ent.IsNull then Exit;
    if Ent.NodeType = TYPE_NODE_ID then Name:= Ent
    else if Ent.NodeType = NODE_DOT then Name:= Ent.ChildByField(FIELD_RHS);
  end;
  if Name.IsNull or (Name.NodeType <> TYPE_NODE_ID) then Exit;
  if (FWithDepth > 0) and ((NT = TYPE_NODE_ID) or (ANode.ChildByField(FIELD_LHS).IsNull)) then Exit;
  if not FactAt(Name, Fact) or (Fact.TypeQName = '') then Exit;
  Result.Facts:= if Fact.TypeSymbolId > 0 then FactsOfId(Fact.TypeSymbolId) else FactsOfName(Fact.TypeQName);
  Result.Known:= Result.Facts.Known;
end;

procedure TRefTypeScan.CheckIs(const ANode: TTSNode);
begin
  var Op: TTSNode:= ANode.ChildByField(FIELD_OP);
  if Op.IsNull or not SameText(Text(Op).Trim, OP_IS) then Exit;
  var LhsN: TTSNode:= ANode.ChildByField(FIELD_LHS);
  var Lhs: TExprType:= StaticType(LhsN);
  if (not Lhs.Known) or not Lhs.Facts.IsClass then Exit;
  var Target: TTypeFacts:= WrittenType(ANode.ChildByField(FIELD_RHS));
  if (not Target.IsClass) or Target.Homonym then Exit;
  if Wants(IS_ALWAYS_TRUE_RULE) and Lhs.Facts.HasAncestor(Target.Name.ToLower) then
    Emit(IS_ALWAYS_TRUE_RULE, ANode,
      Format('''%s'' is declared %s, which is already a %s: this test only asks whether it is nil. Write Assigned(%s), or the declared type is wrong.',
        [Text(LhsN), Lhs.Facts.Name, Target.Name, Text(LhsN)]));
end;

function TRefTypeScan.CastParts(const ANode: TTSNode; out ATarget: TTypeFacts; out AOperand: TTSNode): Boolean;
begin
  Result  := False;
  ATarget := Default(TTypeFacts);
  AOperand:= Default(TTSNode);
  if ANode.IsNull then Exit;
  if ANode.NodeType = NODE_CALL then Exit(CastTarget(ANode, ATarget, AOperand));
  if ANode.NodeType = NODE_PARENS then Exit(CastParts(ANode.NamedChild(0), ATarget, AOperand));
  if not IsAsNode(ANode) then Exit;
  ATarget := WrittenType(ANode.ChildByField(FIELD_RHS));
  AOperand:= ANode.ChildByField(FIELD_LHS);
  Result  := ATarget.IsClass or ATarget.IsIntf;
end;

procedure TRefTypeScan.CheckUpcastThenDowncast(const ANode: TTSNode; const AOuter: TTypeFacts; const AOperand: TTSNode);
var
  Inner  : TTypeFacts;
  InnerOp: TTSNode;
begin
  if not CastParts(AOperand, Inner, InnerOp) then Exit;
  if (not Inner.IsClass) or Inner.Homonym then Exit;
  var Source: TExprType:= StaticType(InnerOp);
  if (not Source.Known) or not Source.Facts.IsClass then Exit;
  var InnerLeaf: string:= Inner.Name.ToLower;
  if not (Source.Facts.HasAncestor(InnerLeaf) and AOuter.HasAncestor(InnerLeaf)) then Exit;
  if SameText(AOuter.Name, Inner.Name) then Exit;
  Emit(UPCAST_THEN_DOWNCAST_RULE, ANode,
    Format('''%s'' is declared %s: the cast to %s adds nothing and the cast on to %s narrows it unchecked. Cast once, with ''as'' or behind an ''is'' test, or fix the declared type.',
      [Text(InnerOp), Source.Facts.Name, Inner.Name, AOuter.Name]));
end;

procedure TRefTypeScan.CheckCast(const ANode: TTSNode);
var
  Outer  : TTypeFacts;
  Operand: TTSNode;
begin
  if not CastParts(ANode, Outer, Operand) then Exit;
  if (not Outer.IsClass) or Outer.Homonym then Exit;
  if Wants(UPCAST_THEN_DOWNCAST_RULE) then CheckUpcastThenDowncast(ANode, Outer, Operand);
end;

procedure TRefTypeScan.CheckWith(const ANode: TTSNode);
var
  Fact: TRefFact;
begin
  var Body: TTSNode:= ANode.ChildByField(FIELD_BODY);
  if Body.IsNull then Exit;
  for var I: Integer:= 0 to Integer(ANode.NamedChildCount) - 1 do
  begin
    var Ent: TTSNode:= ANode.NamedChild(I);
    if Ent.StartByte >= Body.StartByte then Break;
    var Callee: TTSNode:= Ent;
    var Args  : TTSNode:= Default(TTSNode);
    if Ent.NodeType = NODE_CALL then
    begin
      Callee:= Ent.ChildByField(FIELD_ENTITY);
      Args  := Ent.ChildByField(FIELD_ARGS);
    end;
    if Callee.IsNull or (Callee.NodeType <> NODE_DOT) then Continue;
    if (not FactAt(Callee.ChildByField(FIELD_RHS), Fact)) or (Fact.Via <> VIA_CTOR) then Continue;
    { The written class, not the row's: `TFoo.Create` may bind to a constructor TFoo inherits. }
    var Cls: TTypeFacts:= WrittenType(Callee.ChildByField(FIELD_LHS));
    if not Cls.IsClass then Continue;
    if Cls.HasAncestor(CLASS_THREAD) then Continue; { may free itself (FreeOnTerminate) }
    if Cls.HasAncestor(CLASS_COMPONENT) and (not Args.IsNull) and (Args.NamedChildCount > 0)
       and not SameText(Text(Args.NamedChild(0)).Trim, NIL_WORD) then Continue; { an owner takes it }
    if TRegEx.IsMatch(Text(Body), FREE_WORDS_RX, [roIgnoreCase]) then Continue;
    Emit(WITH_ON_TEMPORARY_RULE, Ent,
      Format('with on a new %s that nothing frees: the object has no name once the block ends, so it leaks. Hold it in a variable, or free it in the block.', [Cls.Name]));
  end;
end;

procedure TRefTypeScan.Walk(const ANode: TTSNode);
begin
  if ANode.IsNull then Exit;
  var NT: string:= ANode.NodeType;
  if IsAsNode(ANode) or (NT = NODE_CALL) then CheckCast(ANode)
  else if NT = NODE_BINARY then CheckIs(ANode);
  var IsWith: Boolean:= NT = NODE_WITH;
  if IsWith and Wants(WITH_ON_TEMPORARY_RULE) then CheckWith(ANode);
  if IsWith then Inc(FWithDepth);
  for var I: Integer:= 0 to Integer(ANode.NamedChildCount) - 1 do
    Walk(ANode.NamedChild(I));
  if IsWith then Dec(FWithDepth);
end;

procedure TRefTypeScan.ScanFile(AFileId: Int64);
begin
  FFileId:= AFileId;
  FPath  := FStore.GetFilePath(AFileId);
  if FPath = '' then Exit;
  var PF: TParsedFile:= TAstParseCache.Get(FPath);
  if PF.Tree = nil then Exit;
  FSrc:= PF.Src;
  LoadRefs(AFileId);
  if FRefs.Count = 0 then Exit;
  FWithDepth:= 0;
  Walk(PF.Tree.RootNode);
end;

function RefTypeRuleDefaultOff(const ARuleId: string): Boolean;
begin
  Result:= False;
  for var S: string in REF_TYPE_RULES_OFF do
    if SameText(S, ARuleId) then Exit(True);
end;

function CollectRefTypeRules(const AStore, ALibStore: ISymbolStore; const ARules: TArray<string>;
  AOnlyFileId: Int64): TArray<TLintFinding>;
begin
  Result:= nil;
  if (AStore = nil) or (Length(ARules) = 0) or (AStore is not TSQLiteSymbolStore) then Exit;
  var Scan: TRefTypeScan:= TRefTypeScan.Create(AStore, ALibStore, ARules);
  try
    if not Scan.HasFact then Exit;
    if AOnlyFileId > 0 then Scan.ScanFile(AOnlyFileId)
    else
      for var Id: Int64 in AStore.GetAllFileIds do
      begin
        Scan.ScanFile(Id);
        TAstParseCache.Clear; { a whole-project walk: one tree at a time }
      end;
    Result:= Scan.Findings;
  finally
    Scan.Free;
  end;
end;

end.
