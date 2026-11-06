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
  System.SysUtils
  , DRagLint.Core.Model
  , DRagLint.Core.Interfaces
  , TreeSitter
  ;

const
  /// <summary>Rule id: `x is T` where the static type of x already descends from T.</summary>
  IS_ALWAYS_TRUE_RULE = 'is-always-true';
  /// <summary>Rule id, shared with the lexical check in AstChecks: this unit answers every
  /// hard cast whose operand has a ref_types row, and that check only the others.</summary>
  UNSAFE_TYPECAST_RULE = 'unsafe-typecast-without-is';
  /// <summary>Rule id, shared with the lexical check in AstChecks: this unit answers the
  /// shapes that check cannot type, a member chain or a call result, and `x as T`.</summary>
  REDUNDANT_CAST_RULE = 'redundant-cast';
  /// <summary>Rule id: an argument wider than the parameter it is passed to.</summary>
  ARGUMENT_NARROWS_RULE = 'argument-narrows';
  /// <summary>Rule id: an interface variable assigned an object that is not reference counted.</summary>
  INTERFACE_HOLDER_RULE = 'interface-holder-of-non-refcounted';
  /// <summary>Rule id: `with TFoo.Create do` that nobody frees.</summary>
  WITH_ON_TEMPORARY_RULE = 'with-on-temporary';
  /// <summary>Rule id: a cast to an ancestor and straight back down, TLeaf(TBase(x)).</summary>
  UPCAST_THEN_DOWNCAST_RULE = 'upcast-then-downcast';
  /// <summary>Every project rule this unit emits, as `--rule` and dl:ok markers spell them.</summary>
  REF_TYPE_RULES: array[0..6] of string = (IS_ALWAYS_TRUE_RULE, UPCAST_THEN_DOWNCAST_RULE, WITH_ON_TEMPORARY_RULE, INTERFACE_HOLDER_RULE, ARGUMENT_NARROWS_RULE, REDUNDANT_CAST_RULE, UNSAFE_TYPECAST_RULE);
  /// <summary>The ones that ship OFF; each names why in the catalog.</summary>
  REF_TYPE_RULES_OFF: array of string = [UNSAFE_TYPECAST_RULE];

/// <summary>True when the rule ships OFF by default (see the catalog).</summary>
/// <param name="ARuleId">One of REF_TYPE_RULES.</param>
/// <returns>The value to hand TLintConfig.ShouldKeep as ADefaultDisabled.</returns>
function RefTypeRuleDefaultOff(const ARuleId: string): Boolean;

/// <summary>The static type ref_types records for the reference at a position.</summary>
/// <param name="AStore">The index; nil or a store that is not SQLite answers False.</param>
/// <param name="AFileId">The file's id in AStore; 0 answers False.</param>
/// <param name="ALine">1-based line.</param>
/// <param name="ACol">1-based column.</param>
/// <param name="AName">The name written there: a ref of another name is no answer.</param>
/// <param name="ATypeLeaf">Out: the type's leaf name.</param>
/// <returns>False with no table (an index older than 1.44) or no row: the caller
/// keeps what it knew without the fact.</returns>
/// <remarks>Two queries per call, for rule candidates and not for every expression.</remarks>
function RefStaticTypeAt(const AStore: ISymbolStore; AFileId: Int64; ALine, ACol: Integer; const AName: string;
  out ATypeLeaf: string): Boolean;

type
  /// <summary>The answer to "does type A descend from type B" over the indexed ancestry.</summary>
  /// <remarks>Three values on purpose: a rule that wants to SUPPRESS on proof uses tdYes, a rule
  /// that wants to FIRE on proof of absence uses tdNo, and tdUnknown never changes what a rule
  /// does today.</remarks>
  TDescent = (
    /// <summary>Not decidable: no such type, a homonym that disagrees, an unresolved or generic
    /// ancestor with no library index, or not a class or interface.</summary>
    tdUnknown,
    /// <summary>The whole ancestry was followed and the ancestor is not in it.</summary>
    tdNo,
    /// <summary>The ancestor is in the ancestry of every class of that name.</summary>
    tdYes);

/// <summary>Whether a class or interface descends from an ancestor (index fact type_ancestors).</summary>
/// <param name="AStore">The project index; nil or a store that is not SQLite answers tdUnknown.</param>
/// <param name="ALibStore">The platform library index, or nil. Without it an ancestor outside the
/// project is not followed: a positive answer still stands, a negative one becomes tdUnknown.</param>
/// <param name="ATypeLeaf">The type's name; a qualified name is cut to its leaf. Case-insensitive.</param>
/// <param name="AAncestorLeaf">The ancestor's name, leaf only. Case-insensitive. The type itself counts.</param>
/// <returns>tdYes, tdNo or tdUnknown; see TDescent. Needs no ref_types table, only type_ancestors.</returns>
/// <remarks>Homonyms are intersected as in the unit comment: they can turn tdYes into tdUnknown,
/// never create one. One call builds its own caches; use TExprTypeReader.Descends in a loop.</remarks>
function TypeDescendsFrom(const AStore, ALibStore: ISymbolStore; const ATypeLeaf, AAncestorLeaf: string): TDescent;

type
  /// <summary>Static types of expressions in ONE unit, from ref_types (index fact F1).</summary>
  /// <remarks>Not thread-safe. Owns its caches and a query on AStore's connection, so it must not
  /// outlive the store. Creating it costs one query for the file's refs; ask many nodes of the same
  /// file from one reader. Safe inside a `with`, no caller has to guard: there a name may bind to
  /// a member of the with-subject, so the reader answers only when the resolver decided the name
  /// (see TypeLeafOf). The first with-subject is outside its own scope; a later one is inside.</remarks>
  TExprTypeReader = class
    strict private
      FScan : TObject;
      FReady: Boolean;
    public
      /// <summary>Opens the unit's refs for reading.</summary>
      /// <param name="AStore">The project index; nil or not SQLite makes every answer false/unknown.</param>
      /// <param name="ALibStore">The platform library index, or nil (see TypeDescendsFrom).</param>
      /// <param name="AFileId">The unit's id in AStore.</param>
      /// <param name="ASrc">The unit's source bytes exactly as the node was parsed from (UTF-8).</param>
      constructor Create(const AStore, ALibStore: ISymbolStore; AFileId: Int64; const ASrc: TBytes);
      destructor Destroy; override;
      /// <summary>False when the index has no ref_types table (older than 1.44) or the store is unusable.</summary>
      property Ready: Boolean read FReady;
      /// <summary>The static type leaf of an expression node.</summary>
      /// <param name="ANode">An identifier, a dotted chain (`A.B.C`: the type of C), a call (`F(x)`,
      /// `A.B(x)`: the result type), a parenthesised expression, `x as T` or `T(x)`.</param>
      /// <param name="ALeaf">Out: the type's leaf name as written in the index; '' when false.</param>
      /// <returns>False with no table, no row, a conflicting row, or an expression shape that has
      /// no static type (a subscript, a dereference, arithmetic): the caller keeps what it knew.
      /// Inside a `with` scope also False unless a ref_types row proves it: the expression's own row
      /// and the row of its leftmost name (or an explicit Self), neither of them a cast. The written
      /// type of `x as T` or `T(x)` is no proof there, and neither is a chain rooted in a subscript or
      /// parentheses. Never a wrong type: unknown instead.</returns>
      function TypeLeafOf(const ANode: TTSNode; out ALeaf: string): Boolean;
      /// <summary>TypeDescendsFrom on this reader's caches.</summary>
      /// <param name="ATypeLeaf">See TypeDescendsFrom.</param>
      /// <param name="AAncestorLeaf">See TypeDescendsFrom.</param>
      /// <returns>See TypeDescendsFrom.</returns>
      function Descends(const ATypeLeaf, AAncestorLeaf: string): TDescent;
  end;

/// <summary>One-shot TExprTypeReader.TypeLeafOf: the static type leaf of one expression node.</summary>
/// <param name="AStore">The project index.</param>
/// <param name="AFileId">The unit's id in AStore.</param>
/// <param name="ANode">The expression node (see TExprTypeReader.TypeLeafOf).</param>
/// <param name="ASrc">The unit's source bytes the node came from.</param>
/// <param name="ALeaf">Out: the type's leaf name.</param>
/// <returns>False when no fact answers; see TExprTypeReader.TypeLeafOf.</returns>
/// <remarks>Loads the unit's refs on every call: for more than a few nodes of one unit make a
/// TExprTypeReader.</remarks>
function StaticTypeLeafOfExpr(const AStore: ISymbolStore; AFileId: Int64; const ANode: TTSNode; const ASrc: TBytes;
  out ALeaf: string): Boolean;
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
  System.Generics.Collections
  , System.RegularExpressions
  , FireDAC.Comp.Client
  , FireDAC.Stan.Param  // dl:ok unused-unit-in-uses@c61d -- REVIEWED 2026-11-05: TFDParam.SetAsLargeInt is inline, and without this unit the compiler says H2443 at every parameter assignment
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
  OVERLOAD_WORD    = 'overload';
  { How many aliases of an alias are followed. }
  MAX_ALIAS_HOPS   = 4;
  { Storage of the signed and unsigned integer types and the floats: a rank, not a promise of sizeof. }
  WIDTH_FLOAT_BASE = 100;
  NODE_ASSIGN      = 'assignment';
  OP_NODE_ASSIGN   = 'kAssign';
  SELF_WORD        = 'Self';
  ADDREF_NAME      = '_AddRef';
  { Bases whose _AddRef / _Release do nothing. }
  NON_REFCOUNTED: array[0..2] of string = ('tcomponent', 'tnorefcountobject', 'tsingletonimplementation');
  { How far a nested routine's parents are climbed to reach its class. }
  MAX_PARENT_HOPS  = 8;
  CLASS_COMPONENT  = 'tcomponent';
  CLASS_THREAD     = 'tthread';
  FIELD_BODY       = 'body';
  VIA_CTOR         = 'ctor';
  VIA_RESULT       = 'result';
  VIA_CAST         = 'cast';
  KEYWORD_NODE_PREFIX = 'k';
  NIL_WORD         = 'nil';
  { A call that ends the object's life, or hands the job to the object. }
  FREE_WORDS_RX    = '\b(free|destroy|release|disposeof|freeandnil|freeonterminate)\b';
  SEV_WARNING      = 'warning';
  SEV_HINT         = 'hint';
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
    /// <summary>The type's symbol in the project index; 0 for a library type or a homonym.</summary>
    SymbolId  : Int64;
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
  TRefTypeScan = class  // dl:ok god-class@9eb0, high-response@9eb0 -- REVIEWED 2026-11-05: one scan and its caches; the rules share the type closure and the per-file ref map, and splitting them would only pass that state around
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
      FSymbols : TDictionary<Int64, TSymbol>;
      { 'operand text|type', lower case: the `x is T` tests of the current file. File-scoped,
        as the lexical check's are: a guard elsewhere silences, which errs towards silence. }
      FGuards  : TDictionary<string, Boolean>;
      FWithDepth: Integer;
      FOwnRefCount: TArray<string>;
      FOwnRefCountRead: Boolean;
      function Wants(const ARuleId: string): Boolean;
      function Text(const ANode: TTSNode): string;
      function FactAt(const ANode: TTSNode; out AFact: TRefFact): Boolean;
      procedure LoadRefs(AFileId: Int64);
      procedure Emit(const ARuleId: string; const ANode: TTSNode; const AMessage: string; const ASeverity: string = SEV_WARNING);
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
      procedure CheckRedundantCast(const ANode: TTSNode; const AOuter: TTypeFacts; const AOperand: TTSNode);
      procedure CollectGuards(const ANode: TTSNode);
      procedure CheckUnsafeCast(const ANode: TTSNode; const AOuter: TTypeFacts; const AOperand: TTSNode);
      procedure CheckCast(const ANode: TTSNode);
      procedure CheckWith(const ANode: TTSNode);
      function OwnRefCountClasses: TArray<string>;
      function SelfType(const AAssignLhs: TTSNode): TExprType;
      procedure CheckAssign(const ANode: TTSNode);
      function SymbolOf(AId: Int64): TSymbol;
      function ResolveAlias(const ATypeName: string): string;
      function NumericName(const ANode: TTSNode; out AFact: TRefFact): Boolean;
      procedure CheckArguments(const ANode: TTSNode);
      procedure CheckIs(const ANode: TTSNode);
      procedure Walk(const ANode: TTSNode);
    public
      constructor Create(const AStore, ALibStore: ISymbolStore; const ARules: TArray<string>);
      destructor Destroy; override;
      /// <summary>Scans one file of the index.</summary>
      procedure ScanFile(AFileId: Int64);
      /// <summary>True when the index carries the ref_types table.</summary>
      function HasFact: Boolean;
      /// <summary>Points the scan at one file's refs and source, for ExprTypeLeaf.</summary>
      procedure Attach(AFileId: Int64; const ASrc: TBytes);
      /// <summary>The static type leaf of an expression; False when no fact answers.</summary>
      function ExprTypeLeaf(const ANode: TTSNode; out ALeaf: string): Boolean;
      { True when a name in ANode may bind to a member of an enclosing with-subject. }
      function InWithScope(const ANode: TTSNode): Boolean;
      { The identifier whose ref carries the type of the (parens-free) expression; null when none. }
      function LastHopName(const AInner: TTSNode): TTSNode;
      { ExprTypeLeaf inside a with scope: answers only on proof, see TExprTypeReader.TypeLeafOf. }
      function WithProofLeaf(const AInner: TTSNode; out ALeaf: string): Boolean;
      /// <summary>Descent of a type name from an ancestor leaf over the closure.</summary>
      function DescentOf(const ATypeLeaf, AAncestorLeaf: string): TDescent;
      /// <summary>The findings so far, in scan order.</summary>
      function Findings: TArray<TLintFinding>;
  end;

/// <summary>Bytes of a numeric type name, plus WIDTH_FLOAT_BASE for a float; 0 for any other type.</summary>
function NumericWidth(const ALowerType: string): Integer;  // dl:ok too-many-exit-points@f4c0 -- REVIEWED 2026-11-05: guard clauses, each declining a shape the rule cannot prove
const
  WIDTH_1: array[0..1] of string = ('shortint', 'byte');
  WIDTH_2: array[0..1] of string = ('smallint', 'word');
  WIDTH_4: array[0..5] of string = ('integer', 'longint', 'cardinal', 'longword', 'fixedint', 'fixeduint');
  WIDTH_8: array[0..5] of string = ('int64', 'uint64', 'nativeint', 'nativeuint', 'intptr', 'uintptr');
  BYTES_1 = 1; BYTES_2 = 2; BYTES_4 = 4; BYTES_8 = 8;
begin
  Result:= 0;
  for var S: string in WIDTH_1 do if S = ALowerType then Exit(BYTES_1);
  for var S: string in WIDTH_2 do if S = ALowerType then Exit(BYTES_2);
  for var S: string in WIDTH_4 do if S = ALowerType then Exit(BYTES_4);
  for var S: string in WIDTH_8 do if S = ALowerType then Exit(BYTES_8);
  if ALowerType = 'single' then Exit(WIDTH_FLOAT_BASE + BYTES_4);
  if (ALowerType = 'double') or (ALowerType = 'real') then Exit(WIDTH_FLOAT_BASE + BYTES_8);
end;

/// <summary>The by-value parameter types of a routine signature in order; '' for a
/// var / out / untyped / array parameter, which never narrows.</summary>
function ParamTypes(const ASignature: string): TArray<string>;
begin
  Result:= nil;
  var Open: Integer:= ASignature.IndexOf('(');
  if Open < 0 then Exit;
  var Depth: Integer:= 0;
  var Close: Integer:= -1;
  for var I: Integer:= Open to ASignature.Length - 1 do
  begin
    if ASignature.Chars[I] = '(' then Inc(Depth)
    else if ASignature.Chars[I] = ')' then
    begin
      Dec(Depth);
      if Depth = 0 then
      begin
        Close:= I;
        Break;
      end;
    end;
  end;
  if Close < 0 then Exit;
  for var Part: string in ASignature.Substring(Open + 1, Close - Open - 1).Split([';']) do
  begin
    var P: string:= Part.Trim;
    var Colon: Integer:= P.IndexOf(':');
    var Names: string:= if Colon >= 0 then P.Substring(0, Colon) else P;
    var TypeText: string:= '';
    if Colon >= 0 then TypeText:= P.Substring(Colon + 1).Split(['='])[0].Trim;
    var Low: string:= Names.Trim.ToLower;
    if Low.StartsWith('var ') or Low.StartsWith('out ') then TypeText:= '';
    for var N: string in Names.Split([',']) do
      Result:= Result + [TypeText];
  end;
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
  FSymbols := TDictionary<Int64, TSymbol>.Create;
  FGuards  := TDictionary<string, Boolean>.Create;
  FQuery   := TFDQuery.Create(nil);
  FQuery.Connection:= (AStore as TSQLiteSymbolStore).GetConnection;
end;

destructor TRefTypeScan.Destroy;
begin
  FQuery.Free;
  FSymbols.Free;
  FGuards.Free;
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
  COL_LINE = 0; COL_COL = 1; COL_NAME = 2; COL_SYM = 3; COL_ENCL = 4; COL_TID = 5; COL_QNAME = 6; COL_VIA = 7;
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

procedure TRefTypeScan.Emit(const ARuleId: string; const ANode: TTSNode; const AMessage: string; const ASeverity: string);
var
  F: TLintFinding;
begin
  F:= Default(TLintFinding);
  F.RuleId   := ARuleId;
  F.Severity := ASeverity;
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
    if (ASym.Kind = skClass) and not Names.Contains(ROOT_CLASS) then Names.Add(ROOT_CLASS);
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
  if AOutermost then Result.SymbolId:= ASym.Id;
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
    if S.Kind not in TYPE_KINDS then Continue;
    var One: TTypeFacts:= FactsOfSymbol(AStore, S, AOutermost);
    if First then
    begin
      Result:= One;
      First := False;
      Continue;
    end;
    { A homonym: only what ALL of them agree on survives. }
    Result.Homonym := True;
    Result.SymbolId:= 0;
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

function TRefTypeScan.StaticType(const ANode: TTSNode): TExprType;  // dl:ok too-many-exit-points@f142 -- REVIEWED 2026-11-05: guard clauses, each declining a shape the rule cannot prove
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

procedure TRefTypeScan.CheckRedundantCast(const ANode: TTSNode; const AOuter: TTypeFacts; const AOperand: TTSNode);
begin
  { A hard cast of a single variable is AstChecks' shape (it finds it without an index);
    a bare function call, which its type map cannot type, is this one's. }
  var Fact: TRefFact;
  if (ANode.NodeType = NODE_CALL) and (AOperand.NodeType = TYPE_NODE_ID)
     and not (FactAt(AOperand, Fact) and (Fact.Via = VIA_RESULT)) then Exit;
  var Source: TExprType:= StaticType(AOperand);
  if (not Source.Known) or (not Source.Facts.IsClass) or Source.Facts.Homonym then Exit;
  if not SameText(Source.Facts.Name, AOuter.Name) then Exit;
  if (Source.Facts.SymbolId <> AOuter.SymbolId) and (Source.Facts.SymbolId > 0) and (AOuter.SymbolId > 0) then Exit;
  Emit(REDUNDANT_CAST_RULE, ANode, Format('Redundant cast: %s is already of type %s', [Text(AOperand), AOuter.Name]), SEV_HINT);
end;

procedure TRefTypeScan.CollectGuards(const ANode: TTSNode);
begin
  if ANode.IsNull then Exit;
  if ANode.NodeType = NODE_BINARY then
  begin
    var Op: TTSNode:= ANode.ChildByField(FIELD_OP);
    if (not Op.IsNull) and SameText(Text(Op).Trim, OP_IS) then
      FGuards.AddOrSetValue(Text(ANode.ChildByField(FIELD_LHS)).Trim.ToLower + '|' + LeafOf(Text(ANode.ChildByField(FIELD_RHS))).ToLower, True);
  end;
  for var I: Integer:= 0 to Integer(ANode.NamedChildCount) - 1 do
    CollectGuards(ANode.NamedChild(I));
end;

procedure TRefTypeScan.CheckUnsafeCast(const ANode: TTSNode; const AOuter: TTypeFacts; const AOperand: TTSNode);  // dl:ok too-many-exit-points@701b -- REVIEWED 2026-11-05: guard clauses, each declining a shape the rule cannot prove
var
  Inner  : TTypeFacts;
  InnerOp: TTSNode;
begin
  if ANode.NodeType <> NODE_CALL then Exit;
  if SameText(AOuter.Name, ROOT_CLASS) then Exit;
  { A cast of a cast is upcast-then-downcast's. }
  if CastParts(AOperand, Inner, InnerOp) then Exit;
  var Source: TExprType:= StaticType(AOperand);
  if (not Source.Known) or (not Source.Facts.IsClass) then Exit;
  if Source.Facts.HasAncestor(AOuter.Name.ToLower) then Exit; { an upcast cannot fail }
  var OperandText: string:= Text(AOperand).Trim;
  if FGuards.ContainsKey(OperandText.ToLower + '|' + AOuter.Name.ToLower) then Exit;
  Emit(UNSAFE_TYPECAST_RULE, ANode,
    Format('Unchecked hard cast %s(%s): its static type is %s, with no ''is %s'' guard; a wrong run-time type crashes or corrupts. Guard with ''is'' or use the ''as'' operator.',
      [AOuter.Name, OperandText, Source.Facts.Name, AOuter.Name]));
end;

procedure TRefTypeScan.CheckCast(const ANode: TTSNode);
var
  Outer  : TTypeFacts;
  Operand: TTSNode;
begin
  if not CastParts(ANode, Outer, Operand) then Exit;
  if (not Outer.IsClass) or Outer.Homonym then Exit;
  if Wants(UPCAST_THEN_DOWNCAST_RULE) then CheckUpcastThenDowncast(ANode, Outer, Operand);
  if Wants(REDUNDANT_CAST_RULE) then CheckRedundantCast(ANode, Outer, Operand);
  if Wants(UNSAFE_TYPECAST_RULE) then CheckUnsafeCast(ANode, Outer, Operand);
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

function TRefTypeScan.OwnRefCountClasses: TArray<string>;
begin
  if not FOwnRefCountRead then
  begin
    FOwnRefCountRead:= True;
    for var S: TSymbol in FStore.FindSymbolsByExactName(ADDREF_NAME) do
      if S.ParentId > 0 then FOwnRefCount:= FOwnRefCount + [FStore.GetSymbolById(S.ParentId).Name.ToLower];
  end;
  Result:= FOwnRefCount;
end;

function TRefTypeScan.SelfType(const AAssignLhs: TTSNode): TExprType;
var
  Fact: TRefFact;
begin
  Result:= Default(TExprType);
  var Name: TTSNode:= if AAssignLhs.NodeType = NODE_DOT then AAssignLhs.ChildByField(FIELD_RHS) else AAssignLhs;
  if (not FactAt(Name, Fact)) or (Fact.Enclosing <= 0) then Exit;
  var Id: Int64:= Fact.Enclosing;
  for var Hop: Integer:= 1 to MAX_PARENT_HOPS do
  begin
    if Id <= 0 then Exit;
    var Sym: TSymbol:= FStore.GetSymbolById(Id);
    if Sym.Kind = skClass then
    begin
      Result.Facts:= FactsOfId(Id);
      Result.Known:= True;
      Exit;
    end;
    Id:= Sym.ParentId;
  end;
end;

procedure TRefTypeScan.CheckAssign(const ANode: TTSNode);  // dl:ok too-many-exit-points@c598 -- REVIEWED 2026-11-05: guard clauses, each declining a shape the rule cannot prove
begin
  var Op: TTSNode:= ANode.ChildByField(FIELD_OP);
  if Op.IsNull or (Op.NodeType <> OP_NODE_ASSIGN) then Exit;
  var LhsN: TTSNode:= ANode.ChildByField(FIELD_LHS);
  var Holder: TExprType:= StaticType(LhsN);
  if (not Holder.Known) or not Holder.Facts.IsIntf then Exit;
  var RhsN: TTSNode:= ANode.ChildByField(FIELD_RHS);
  while (not RhsN.IsNull) and (RhsN.NodeType = NODE_PARENS) do RhsN:= RhsN.NamedChild(0);
  if RhsN.IsNull then Exit;
  if IsAsNode(RhsN) then RhsN:= RhsN.ChildByField(FIELD_LHS);
  var Source: TExprType:= if SameText(Text(RhsN), SELF_WORD) then SelfType(LhsN) else StaticType(RhsN);
  if (not Source.Known) or not Source.Facts.IsClass then Exit;
  var Base: string:= '';
  for var S: string in NON_REFCOUNTED do
    if Source.Facts.HasAncestor(S) then Base:= S;
  if Base = '' then Exit;
  for var S: string in OwnRefCountClasses do
    if Source.Facts.HasAncestor(S) then Exit; { its class counts references itself }
  Emit(INTERFACE_HOLDER_RULE, ANode,
    Format('Interface variable %s of type %s holds a %s, whose %s does not count references: the variable keeps nothing alive and dangles once the object is freed.',
      [Text(LhsN), Holder.Facts.Name, Source.Facts.Name, Base]));
end;

function TRefTypeScan.SymbolOf(AId: Int64): TSymbol;
begin
  if FSymbols.TryGetValue(AId, Result) then Exit;
  Result:= FStore.GetSymbolById(AId);
  FSymbols.Add(AId, Result);
end;

function TRefTypeScan.ResolveAlias(const ATypeName: string): string;
begin
  Result:= LeafOf(ATypeName);
  for var Hop: Integer:= 1 to MAX_ALIAS_HOPS do
  begin
    if NumericWidth(Result.ToLower) > 0 then Exit;
    var Target: string:= '';
    var Count : Integer:= 0;
    for var S: TSymbol in FStore.FindSymbolsByExactName(Result) do
      if S.Kind = skTypeAlias then
      begin
        Inc(Count);
        Target:= S.Signature;
      end;
    { A homonym names no one type. }
    if (Count <> 1) or (Target = '') then Exit;
    Result:= LeafOf(Target);
  end;
end;

function TRefTypeScan.NumericName(const ANode: TTSNode; out AFact: TRefFact): Boolean;
begin
  Result:= False;
  AFact := Default(TRefFact);
  var Name: TTSNode:= Default(TTSNode);
  if ANode.NodeType = TYPE_NODE_ID then
  begin
    if FWithDepth > 0 then Exit;
    Name:= ANode;
  end
  else if ANode.NodeType = NODE_DOT then Name:= ANode.ChildByField(FIELD_RHS)
  else if ANode.NodeType = NODE_CALL then
  begin
    var Ent: TTSNode:= ANode.ChildByField(FIELD_ENTITY);
    if Ent.IsNull then Exit;
    if Ent.NodeType = TYPE_NODE_ID then
    begin
      if FWithDepth > 0 then Exit;
      Name:= Ent;
    end
    else if Ent.NodeType = NODE_DOT then Name:= Ent.ChildByField(FIELD_RHS);
  end;
  if Name.IsNull or (Name.NodeType <> TYPE_NODE_ID) then Exit;
  if (not FactAt(Name, AFact)) or (AFact.TypeQName = '') or (AFact.SymbolId <= 0) then Exit;
  { A constant's value is known to fit, or the compiler said so. }
  Result:= SymbolOf(AFact.SymbolId).Kind <> skConstDecl;
end;

procedure TRefTypeScan.CheckArguments(const ANode: TTSNode);  // dl:ok too-many-exit-points@d8e0 -- REVIEWED 2026-11-05: guard clauses, each declining a shape the rule cannot prove
var
  Callee: TRefFact;
  Arg   : TRefFact;
begin
  var Ent: TTSNode:= ANode.ChildByField(FIELD_ENTITY);
  var Args: TTSNode:= ANode.ChildByField(FIELD_ARGS);
  if Ent.IsNull or Args.IsNull then Exit;
  var Name: TTSNode:= if Ent.NodeType = NODE_DOT then Ent.ChildByField(FIELD_RHS) else Ent;
  if Name.IsNull or (Name.NodeType <> TYPE_NODE_ID) then Exit;
  if (Ent.NodeType = TYPE_NODE_ID) and (FWithDepth > 0) then Exit;
  if (not FactAt(Name, Callee)) or (Callee.SymbolId <= 0) then Exit;
  var Sym: TSymbol:= SymbolOf(Callee.SymbolId);
  if Sym.Kind not in [skProcedure, skFunction, skMethod, skConstructor] then Exit;
  { The resolver's overload choice is the part a width argument cannot rest on. }
  if Sym.Directives.ToLower.Contains(OVERLOAD_WORD) or Sym.Modifiers.ToLower.Contains(OVERLOAD_WORD) then Exit;
  var Params: TArray<string>:= ParamTypes(Sym.Signature);
  if Integer(Args.NamedChildCount) > Length(Params) then Exit;
  for var I: Integer:= 0 to Integer(Args.NamedChildCount) - 1 do
  begin
    if Params[I] = '' then Continue;
    var ArgN: TTSNode:= Args.NamedChild(I);
    if not NumericName(ArgN, Arg) then Continue;
    var ArgType  : string:= ResolveAlias(Arg.TypeQName);
    var ParamType: string:= ResolveAlias(Params[I]);
    var ArgW  : Integer:= NumericWidth(ArgType.ToLower);
    var ParamW: Integer:= NumericWidth(ParamType.ToLower);
    if (ArgW = 0) or (ParamW = 0) then Continue;
    if (ArgW > WIDTH_FLOAT_BASE) <> (ParamW > WIDTH_FLOAT_BASE) then Continue;
    if ArgW <= ParamW then Continue;
    Emit(ARGUMENT_NARROWS_RULE, ArgN,
      Format('%s is %s but parameter %d of %s is %s: the value is truncated silently. Widen the parameter, or narrow it explicitly after a range check.',
        [Text(ArgN), ArgType, I + 1, Sym.Name, ParamType]));
  end;
end;

procedure TRefTypeScan.Walk(const ANode: TTSNode);
begin
  if ANode.IsNull then Exit;
  var NT: string:= ANode.NodeType;
  if NT = NODE_CALL then
  begin
    CheckCast(ANode);
    if Wants(ARGUMENT_NARROWS_RULE) then CheckArguments(ANode);
  end
  else if IsAsNode(ANode) then CheckCast(ANode)
  else if NT = NODE_BINARY then CheckIs(ANode)
  else if (NT = NODE_ASSIGN) and Wants(INTERFACE_HOLDER_RULE) then CheckAssign(ANode);
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
  FGuards.Clear;
  if Wants(UNSAFE_TYPECAST_RULE) then CollectGuards(PF.Tree.RootNode);
  Walk(PF.Tree.RootNode);
end;

function RefStaticTypeAt(const AStore: ISymbolStore; AFileId: Int64; ALine, ACol: Integer; const AName: string;
  out ATypeLeaf: string): Boolean;
var
  Q: TFDQuery;
begin
  Result   := False;
  ATypeLeaf:= '';
  if (AStore = nil) or (AFileId <= 0) or (AStore is not TSQLiteSymbolStore) then Exit;
  Q:= TFDQuery.Create(nil);
  try
    Q.Connection:= (AStore as TSQLiteSymbolStore).GetConnection;
    Q.SQL.Text  := 'SELECT 1 FROM sqlite_master WHERE type = ''table'' AND name = ''ref_types''';
    Q.Open;
    if Q.Eof then Exit;
    Q.Close;
    Q.SQL.Text:= 'SELECT t.type_qname FROM refs r JOIN ref_types t ON t.ref_id = r.id ' +
                 'WHERE r.file_id = :f AND r.start_line = :l AND r.start_col = :c AND r.name_text = :n COLLATE NOCASE LIMIT 1';
    Q.ParamByName('f').AsLargeInt  := AFileId;
    Q.ParamByName('l').AsInteger   := ALine;
    Q.ParamByName('c').AsInteger   := ACol;
    Q.ParamByName('n').AsWideString:= AName;
    Q.Open;
    if Q.Eof then Exit;
    ATypeLeaf:= LeafOf(Q.Fields[0].AsString);
    Result   := True;
  finally
    Q.Free;
  end;
end;

procedure TRefTypeScan.Attach(AFileId: Int64; const ASrc: TBytes);
begin
  FFileId   := AFileId;
  FSrc      := ASrc;
  FWithDepth:= 0;
  LoadRefs(AFileId);
end;

function TRefTypeScan.ExprTypeLeaf(const ANode: TTSNode; out ALeaf: string): Boolean;  // dl:ok too-many-exit-points -- REVIEWED 2026-11-06: guard clauses, each declining a shape that has no static type
begin
  ALeaf := '';
  Result:= False;
  if ANode.IsNull then Exit;
  var Inner: TTSNode:= ANode;
  while (not Inner.IsNull) and (Inner.NodeType = NODE_PARENS) do Inner:= Inner.NamedChild(0);
  if Inner.IsNull then Exit;
  if InWithScope(ANode) then Exit(WithProofLeaf(Inner, ALeaf));
  var T: TExprType:= StaticType(ANode);
  if T.Known and (T.Facts.Name <> '') then
  begin
    ALeaf := LeafOf(T.Facts.Name);
    Exit(True);
  end;
  { A type the store has no class for (a record, a simple type) still has its recorded name. }
  var Fact: TRefFact;
  var Name: TTSNode:= LastHopName(Inner);
  if Name.IsNull or (Name.NodeType <> TYPE_NODE_ID) or not FactAt(Name, Fact) or (Fact.TypeQName = '') then Exit;
  ALeaf := LeafOf(Fact.TypeQName);
  Result:= ALeaf <> '';
end;

function TRefTypeScan.InWithScope(const ANode: TTSNode): Boolean;
begin
  Result:= False;
  var P: TTSNode:= ANode.Parent;
  while not P.IsNull do
  begin
    if P.NodeType = NODE_WITH then
    begin
      { The first subject is evaluated outside its own with; every other child is inside. The
        grammar's keywords are named children (kWith first). A comment before the subject reads as
        the first child: that errs towards unknown. }
      var First: TTSNode:= Default(TTSNode);
      for var I: Integer:= 0 to Integer(P.NamedChildCount) - 1 do
      begin
        First:= P.NamedChild(I);
        if not First.NodeType.StartsWith(KEYWORD_NODE_PREFIX) then Break;
      end;
      if First.IsNull or (ANode.StartByte < First.StartByte) or (ANode.EndByte > First.EndByte) then Exit(True);
    end;
    P:= P.Parent;
  end;
end;

function TRefTypeScan.LastHopName(const AInner: TTSNode): TTSNode;
begin
  Result:= Default(TTSNode);
  if AInner.NodeType = TYPE_NODE_ID then Result:= AInner
  else if AInner.NodeType = NODE_DOT then Result:= AInner.ChildByField(FIELD_RHS)
  else if AInner.NodeType = NODE_CALL then
  begin
    var Ent: TTSNode:= AInner.ChildByField(FIELD_ENTITY);
    if Ent.IsNull then Exit;
    if Ent.NodeType = TYPE_NODE_ID then Result:= Ent
    else if Ent.NodeType = NODE_DOT then Result:= Ent.ChildByField(FIELD_RHS);
  end;
end;

function TRefTypeScan.WithProofLeaf(const AInner: TTSNode; out ALeaf: string): Boolean;
var
  Fact: TRefFact;
begin
  ALeaf := '';
  Result:= False;
  var Name: TTSNode:= LastHopName(AInner);
  if Name.IsNull or (Name.NodeType <> TYPE_NODE_ID) or not FactAt(Name, Fact) then Exit;
  if (Fact.TypeQName = '') or (Fact.Via = VIA_CAST) then Exit;
  { The resolver's with verdict decided the chain's leftmost name, unless that name is a cast head:
    the cast rung takes any call whose name is a type, without asking the with scope. }
  var Root: TTSNode:= AInner;
  while not Root.IsNull do
    if Root.NodeType = NODE_DOT then Root:= Root.ChildByField(FIELD_LHS)
    else if Root.NodeType = NODE_CALL then Root:= Root.ChildByField(FIELD_ENTITY)
    else Break;
  if Root.IsNull or (Root.NodeType <> TYPE_NODE_ID) then Exit;
  if not SameText(Text(Root), SELF_WORD) then
  begin
    var RootFact: TRefFact;
    if (not FactAt(Root, RootFact)) or (RootFact.TypeQName = '') or (RootFact.Via = VIA_CAST) then Exit;
  end;
  ALeaf := LeafOf(Fact.TypeQName);
  Result:= ALeaf <> '';
end;

function TRefTypeScan.DescentOf(const ATypeLeaf, AAncestorLeaf: string): TDescent;
begin
  Result:= tdUnknown;
  var F: TTypeFacts:= FactsOfName(ATypeLeaf);
  if (not F.Known) or not (F.IsClass or F.IsIntf) then Exit;
  if F.HasAncestor(LeafOf(AAncestorLeaf).ToLower) then Exit(tdYes);
  if F.Complete and not F.Homonym then Result:= tdNo;
end;

constructor TExprTypeReader.Create(const AStore, ALibStore: ISymbolStore; AFileId: Int64; const ASrc: TBytes);
begin
  inherited Create;
  if (AStore = nil) or (AStore is not TSQLiteSymbolStore) then Exit;
  FScan := TRefTypeScan.Create(AStore, ALibStore, nil);
  FReady:= TRefTypeScan(FScan).HasFact;
  if FReady and (AFileId > 0) then TRefTypeScan(FScan).Attach(AFileId, ASrc);
end;

destructor TExprTypeReader.Destroy;
begin
  FScan.Free;
  inherited Destroy;
end;

function TExprTypeReader.TypeLeafOf(const ANode: TTSNode; out ALeaf: string): Boolean;
begin
  ALeaf := '';
  Result:= FReady and TRefTypeScan(FScan).ExprTypeLeaf(ANode, ALeaf);
end;

function TExprTypeReader.Descends(const ATypeLeaf, AAncestorLeaf: string): TDescent;
begin
  Result:= tdUnknown;
  if FScan <> nil then Result:= TRefTypeScan(FScan).DescentOf(ATypeLeaf, AAncestorLeaf);
end;

function TypeDescendsFrom(const AStore, ALibStore: ISymbolStore; const ATypeLeaf, AAncestorLeaf: string): TDescent;
begin
  var R: TExprTypeReader:= TExprTypeReader.Create(AStore, ALibStore, 0, nil);
  try
    Result:= R.Descends(ATypeLeaf, AAncestorLeaf);
  finally
    R.Free;
  end;
end;

function StaticTypeLeafOfExpr(const AStore: ISymbolStore; AFileId: Int64; const ANode: TTSNode; const ASrc: TBytes;
  out ALeaf: string): Boolean;
begin
  var R: TExprTypeReader:= TExprTypeReader.Create(AStore, nil, AFileId, ASrc);
  try
    Result:= R.TypeLeafOf(ANode, ALeaf);
  finally
    R.Free;
  end;
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
