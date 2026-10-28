unit DRagLint.Index.DataFlowFacts;

/// <summary>Index-time data-flow facts: for one routine, which SOURCE (a declared
/// parameter, a field, a unit global, a feeding ref, the var/out slot of an earlier
/// call) can reach which DESTINATION (a call argument, a member write, a field or
/// global write, a var/out parameter of this routine, Result). The rows go to the
/// data_flows table (TDataFlowRow, DF_DST_* / DF_SRC_* in DRagLint.Core.Model) and
/// are composed across routines by the taint rules (DRagLint.Lint.TaintRules).</summary>
/// <remarks>
/// T1 (2026-10-27, plan docs\superpowers\plans\2026-10-27-taint-interprocedural-plan.md
/// sections 2-3). TRoutineVarTable classifies every identifier (parameter / local /
/// Result / other); a forward lattice (TTaintReach, implementation section) runs over
/// TCfgBuilder's CFG with TDataFlowSolver: per routine variable a MAY set of source
/// tokens (with a via-local bit) and a MUST set. A plain assignment kills and gens, a
/// receive (container mutator, member write on a local, var-arg pass) gens, joins union
/// MAY and intersect MUST. Rows are recorded in one final pass over the fixpoint IN
/// values; 'result' / 'outparam' rows come from the IN value of the Exit block. A row's
/// Cond is True when its token is in MAY but not MUST at the destination (a branch or
/// loop decided it). A routine whose CFG is Skipped (goto / label / asm) or has more
/// than DF_CFG_BLOCK_CAP blocks takes the flow-insensitive fallback (source-order
/// walk, gen-only, iterated to a fixpoint; every row Cond = True); lambda bodies are
/// always walked that way with the state at the lambda. `with` bodies (opaque CFG
/// items) emit nothing. Rows are deduplicated on (destination, source) -- ViaLocal
/// and Cond are AND-merged -- and capped at DF_ROW_CAP per routine (a stderr note).
/// This unit is under src\index, so the extractor version guard hashes it: any change
/// to it is an extractor change. All .pas source: strict 7-bit ASCII, CRLF, no BOM.
/// </remarks>

interface

uses
  System.SysUtils
  , System.Generics.Collections
  , DRagLint.Core.Model  // dl:unit DRagLint.Core.Model accepted -- the DF_* kind constants and TDataFlowRow ARE the T0 contract this unit writes
  , TreeSitter
  ;

const
  /// <summary>A routine whose CFG has more blocks than this takes the flow-insensitive
  /// fallback (cost guard; a stderr note names it).</summary>
  DF_CFG_BLOCK_CAP = 2000;

type
  /// <summary>The routines one unit declares, keyed by lower-case name: per argument
  /// position, True when SOME same-named routine of the unit has a var / out
  /// parameter there. Built once per file by TDataFlowFacts.BuildCallees; it decides
  /// which call arguments get an 'argout' source (see TDataFlowFacts.Collect).</summary>
  /// <remarks>Owned by the caller of BuildCallees. Name-keyed on purpose: the
  /// extractor sees one file, so overloads and same-named methods of different
  /// classes are merged (any var/out at a position keeps that position).</remarks>
  TDataFlowCallees = TDictionary<string, TArray<Boolean>>;

  /// <summary>Computes the data_flows rows of one routine from its tree-sitter
  /// subtree. Stateless apart from two process-wide counters; NOT thread-safe
  /// (the indexer's per-file loop is single-threaded).</summary>
  TDataFlowFacts = class
    public
      /// <summary>The data_flows rows of routine ASym (see TDataFlowRow for every
      /// column's meaning).</summary>
      /// <param name="ASym">The routine symbol with its REAL identity: Id = symbols.id
      /// written in this file tx (becomes every row's SymbolId), ParentId = the owning
      /// class's symbols.id or -1 (becomes OwnerId, -1 -> 0).</param>
      /// <param name="AProc">The routine's defProc node.</param>
      /// <param name="ABody">The routine's body (block) node.</param>
      /// <param name="ASrc">The UTF-8 source bytes AProc/ABody index into.</param>
      /// <param name="AOwnerFields">Field names of the owning class (and ancestors known
      /// to this DB), as declared; empty for a plain routine.</param>
      /// <param name="AGlobals">This unit's unit-level variable names, as declared.</param>
      /// <param name="ACallees">This unit's routines (BuildCallees); nil = none known.
      /// Not owned.</param>
      /// <returns>The rows, deduplicated, at most DF_ROW_CAP; nil when nothing is
      /// proven or the body is pure asm. FileId is left 0 (PutDataFlows takes it from
      /// the file tx).</returns>
      /// <remarks>Never raises: an exception inside the walk (a malformed tree) is
      /// caught, a one-line stderr note names the routine, and nil is returned --
      /// silence over a wrong claim, and the file tx is not rolled back for it.
      /// Literals, nil, and values of numeric/boolean declared type emit nothing;
      /// identifiers the var table cannot classify are refs (by position).
      /// An argument variable gets an 'argout' source (the callee may write it) only
      /// when the callee may have a var / out parameter at that position: a callee
      /// in ACallees decides by its mask (a position past every same-unit overload
      /// is kept); otherwise a short built-in RTL list decides (value-only routines
      /// drop, TryGetValue keeps position 1 only); every OTHER callee is unresolved
      /// here and KEEPS its argout source -- the linter resolves the callee and
      /// reads its outparam rows, so no taint the walk needs is lost.</remarks>
      class function Collect(const ASym: TSymbol; const AProc, ABody: TTSNode; const ASrc: TBytes;
                             const AOwnerFields: TArray<string>;
                             const AGlobals: TArray<string>;
                             const ACallees: TDataFlowCallees): TArray<TDataFlowRow>; static;
      /// <summary>The var/out masks of every routine ASymbols declares (parsed from
      /// TSymbol.Signature), for Collect.</summary>
      /// <param name="ASymbols">One file's parsed symbols; non-routine kinds are skipped.</param>
      /// <returns>A new dictionary the CALLER frees (never nil).</returns>
      class function BuildCallees(const ASymbols: TArray<TSymbol>): TDataFlowCallees; static;
      /// <summary>Routines that took the flow-insensitive fallback since process start
      /// (Skipped CFG or over DF_CFG_BLOCK_CAP blocks).</summary>
      /// <returns>The running count.</returns>
      class function FallbackCount: Integer; static;
      /// <summary>Routines whose rows hit DF_ROW_CAP since process start.</summary>
      /// <returns>The running count.</returns>
      class function CappedCount: Integer; static;
  end;

implementation

uses
  System.Generics.Defaults
  , DRagLint.Analysis.Cfg
  , DRagLint.Analysis.DataFlow
  , DRagLint.Analysis.Flow.Lattices
  ;

var
  GFallbacks: Integer = 0;
  GCapped   : Integer = 0;

const
  { Engine knowledge (plan section 2). Growing any list is safe -- it only adds
    rows or flow -- but it IS extraction: an extractor bump. }
  { receive: `X.<m>(e)` means "local/param X receives e" }
  TAINT_RECEIVER_MUTATORS: array[0..5] of string = ('add', 'append', 'insert', 'addstrings', 'assign', 'addpair');
  { a call of one of these names with ONE argument is a typecast: its value is its argument's }
  TAINT_TYPECASTS: array[0..12] of string = ('string', 'unicodestring', 'ansistring', 'widestring', 'rawbytestring',
    'utf8string', 'shortstring', 'pchar', 'pwidechar', 'pansichar', 'variant', 'olevariant', 'pointer');
  { calls whose RESULT is numeric / boolean: no flow out (arg rows are still recorded) }
  TAINT_NOFLOW_RESULT: array[0..20] of string = ('length', 'high', 'low', 'sizeof', 'ord', 'assigned', 'inc', 'dec',
    'setlength', 'freeandnil', 'pos', 'sametext', 'samestr', 'comparetext', 'comparestr', 'inttostr', 'strtoint',
    'strtointdef', 'round', 'trunc', 'odd');
  { member reads of a local/param that are numeric: `L.Count` is not "read L" }
  TAINT_NUMERIC_MEMBERS: array[0..4] of string = ('count', 'length', 'capacity', 'itemindex', 'recordcount');
  { declared types whose values carry no taint }
  TAINT_SCALAR_TYPES: array[0..27] of string = ('integer', 'int64', 'cardinal', 'byte', 'word', 'longint',
    'longword', 'shortint', 'smallint', 'uint64', 'uint32', 'int32', 'uint16', 'int16', 'uint8', 'int8',
    'nativeint', 'nativeuint', 'boolean', 'bytebool', 'wordbool', 'longbool', 'double', 'single', 'extended',
    'real', 'currency', 'tdatetime');
  TAINT_STRING_TYPES: array[0..6] of string = ('string', 'unicodestring', 'ansistring', 'widestring',
    'rawbytestring', 'utf8string', 'shortstring');
  { expression nodes that carry no source: literals, nil, booleans, and shapes with no ref to point at }
  TAINT_INERT_NODES: array[0..9] of string = ('literalString', 'literalNumber', 'literalChar', 'kNil', 'kTrue', 'kFalse',
    'inherited', 'exprTpl', 'typeref', 'comment');
  { argout (lane ARGOUT): RTL routines with NO var/out parameter -- an argument
    passed to one is never written by it. Consulted only for a callee this unit
    does not declare. Name-keyed: a project routine of the same name in ANOTHER
    unit with a var/out parameter would lose its argout source (accepted). }
  TAINT_ARGOUT_NONE: array[0..58] of string = ('copy', 'trim', 'trimleft', 'trimright', 'lowercase',
    'uppercase', 'ansilowercase', 'ansiuppercase', 'extractfileext', 'extractfilename', 'extractfilepath',
    'extractfiledir', 'changefileext', 'expandfilename', 'includetrailingpathdelimiter',
    'excludetrailingpathdelimiter', 'startsstr', 'startstext', 'endsstr', 'endstext', 'containsstr',
    'containstext', 'matchstr', 'matchtext', 'indexstr', 'indextext', 'posex', 'lastdelimiter', 'ifthen',
    'charinset', 'fileexists', 'directoryexists', 'forcedirectories', 'quotedstr', 'stringreplace', 'format',
    'containskey', 'containsvalue', 'combine', 'getfullpath', 'ispathrooted', 'getdirectoryname',
    'getextension', 'getfilename', 'getfilenamewithoutextension', 'readalltext', 'readallbytes',
    'readalllines', 'writealltext', 'writeallbytes', 'exists', 'ismatch', 'addorsetvalue', 'addpair',
    'createdirectory', 'getlastwritetime', 'leftstr', 'rightstr', 'midstr');
  { RTL routines whose ONLY var/out parameter is at TAINT_ARGOUT_OUT1_POS (TryGetValue(Key, out Value)) }
  TAINT_ARGOUT_OUT1: array[0..0] of string = ('trygetvalue');
  TAINT_ARGOUT_OUT1_POS = 1;
  { the flow-insensitive walk iterates to a fixpoint, at most this many passes }
  DF_FLAT_PASSES = 8;
  { BaseIdent descends at most this many receiver levels (a malformed-tree guard, not a semantic limit) }
  DF_RECEIVER_DEPTH = 32;

function InList(const AName: string; const AList: array of string): Boolean;
var
  S: string;
begin
  for S in AList do
    if S = AName then Exit(True);
  Result:= False;
end;

{ ---- sorted unique integer sets ---------------------------------------- }

type
  TIntSet = TArray<Integer>;

function SetHas(const A: TIntSet; V: Integer): Boolean;
var
  Lo, Hi, Mid: Integer;
begin
  Lo:= 0;
  Hi:= High(A);
  while Lo <= Hi do
  begin
    Mid:= (Lo + Hi) shr 1;
    if A[Mid] = V then Exit(True);
    if A[Mid] < V then Lo:= Mid + 1 else Hi:= Mid - 1;
  end;
  Result:= False;
end;

function SetUnion(const A, B: TIntSet): TIntSet;
var
  I, J, K: Integer;
begin
  if Length(A) = 0 then Exit(B);
  if Length(B) = 0 then Exit(A);
  SetLength(Result, Length(A) + Length(B));
  I:= 0;
  J:= 0;
  K:= 0;
  while (I < Length(A)) or (J < Length(B)) do
  begin
    if (J >= Length(B)) or ((I < Length(A)) and (A[I] < B[J])) then
    begin
      Result[K]:= A[I];
      Inc(I);
    end
    else if (I >= Length(A)) or (B[J] < A[I]) then
    begin
      Result[K]:= B[J];
      Inc(J);
    end
    else
    begin
      Result[K]:= A[I];
      Inc(I);
      Inc(J);
    end;
    Inc(K);
  end;
  SetLength(Result, K);
end;

function SetInter(const A, B: TIntSet): TIntSet;
var
  I, J, K: Integer;
begin
  SetLength(Result, Length(A));
  I:= 0;
  J:= 0;
  K:= 0;
  while (I < Length(A)) and (J < Length(B)) do
  begin
    if A[I] < B[J] then Inc(I)
    else if B[J] < A[I] then Inc(J)
    else
    begin
      Result[K]:= A[I];
      Inc(K);
      Inc(I);
      Inc(J);
    end;
  end;
  SetLength(Result, K);
end;

function SetEq(const A, B: TIntSet): Boolean;
var
  I: Integer;
begin
  if Length(A) <> Length(B) then Exit(False);
  for I:= 0 to High(A) do
    if A[I] <> B[I] then Exit(False);
  Result:= True;
end;

function SetNorm(const A: TIntSet): TIntSet;
var
  I, K: Integer;
begin
  Result:= Copy(A);
  if Length(Result) < 2 then Exit;
  TArray.Sort<Integer>(Result);
  K:= 1;
  for I:= 1 to High(Result) do
    if Result[I] <> Result[K - 1] then
    begin
      Result[K]:= Result[I];
      Inc(K);
    end;
  SetLength(Result, K);
end;

{ ---- lattice value ------------------------------------------------------ }

type
  /// <summary>Per routine variable slot: MAY = encoded source elements (token * 2 +
  /// via-local bit), MUST = token ids reaching on every path. Reached = False is the
  /// lattice bottom (an unreached block; MUST's top).</summary>
  TTaintVal = record
    Reached: Boolean;
    May    : TArray<TIntSet>;
    Must   : TArray<TIntSet>;
  end;

  TExprVal = record
    May : TIntSet;   { encoded elements }
    Must: TIntSet;   { token ids }
  end;

  TSrcTok = record
    Kind : string;
    Index: Integer;
    Line : Integer;
    Col  : Integer;
    Name : string;
  end;

  TCollector = class;

  TTaintReach = class(TInterfacedObject, IDataFlowAnalysis<TTaintVal>)
  strict private
    FC: TCollector;
  public
    constructor Create(AC: TCollector);
    function Direction: TFlowDir;
    function Bottom: TTaintVal;
    function Boundary: TTaintVal;
    function Join(const A, B: TTaintVal): TTaintVal;
    function Transfer(const ABlock: TCfgBlock; const AIn: TTaintVal): TTaintVal;
    function Equals(const A, B: TTaintVal): Boolean; reintroduce;
  end;

  TCollector = class  // dl:ok god-class@dfb5, high-response@dfb5 -- one private per-routine walker: the lattice ops, the expression evaluator and the row sink share one state by design (taint T1)
  strict private
    FSym        : TSymbol;
    FProc       : TTSNode;
    FBody       : TTSNode;
    FSrc        : TBytes;
    FVars       : TRoutineVarTable;
    FNSlots     : Integer;
    FSlotKind   : TArray<TVarKind>;
    FSlotScalar : TArray<Boolean>;
    FSlotString : TArray<Boolean>;
    FSlotPIdx   : TArray<Integer>;
    FSlotPTok   : TArray<Integer>;
    FSlotName   : TArray<string>;
    FSiteLine   : TArray<Integer>;
    FSiteCol    : TArray<Integer>;
    FResultSlot : Integer;
    FFields     : TDictionary<string, string>;
    FGlobals    : TDictionary<string, string>;
    FCallees    : TDataFlowCallees;
    FIterables  : TDictionary<string, TArray<TTSNode>>;
    FToks       : TList<TSrcTok>;
    FTokIdx     : TDictionary<string, Integer>;
    FRows       : TList<TDataFlowRow>;
    FRowIdx     : TDictionary<string, Integer>;
    FRecording  : Boolean;
    FInsensitive: Boolean;
    FCapped     : Boolean;
    function Text(const N: TTSNode): string;
    function Tok(const AKind: string; AIndex, ALine, ACol: Integer; const AName: string): Integer;
    function TokVal(ATok: Integer): TExprVal;
    function SlotOf(const N: TTSNode): Integer;
    function BaseIdent(const N: TTSNode): TTSNode;
    function CopyVal(const A: TTaintVal): TTaintVal;
    procedure AddRow(const AKind: string; ALine, ACol, AIndex: Integer; const AName, ARecv: string;
                     ATok: Integer; AVia, ACond: Boolean);
    procedure RecordDst(const AKind: string; const APos: TTSNode; AIndex: Integer; const AName, ARecv: string;
                        const AV: TExprVal);
    procedure AssignSlot(var St: TTaintVal; ASlot: Integer; const AV: TExprVal; AKill: Boolean; const ASite: TTSNode);
    procedure ReceiveInto(var St: TTaintVal; const ABase: TTSNode; const AV: TExprVal);
    function ReadSlot(const St: TTaintVal; ASlot: Integer): TExprVal;
    function Eval(var St: TTaintVal; const N: TTSNode): TExprVal;
    function EvalIdent(var St: TTaintVal; const N: TTSNode): TExprVal;
    function EvalDot(var St: TTaintVal; const N: TTSNode): TExprVal;
    function EvalCall(var St: TTaintVal; const N: TTSNode): TExprVal;
    function ArgMayBeWritten(const ACallee: string; AIndex: Integer): Boolean;
    procedure ApplyAssignment(var St: TTaintVal; const N: TTSNode);
    procedure ApplyMemberWrite(var St: TTaintVal; const ALhs: TTSNode; const AV: TExprVal);
    procedure ApplyStmtExpr(var St: TTaintVal; const E: TTSNode);
    procedure ApplyItem(var St: TTaintVal; const N: TTSNode);
    procedure WalkLambda(const St: TTaintVal; const N: TTSNode);
    procedure FlatWalk(var St: TTaintVal; const N: TTSNode);
    procedure EmitExitRows(const St: TTaintVal);
    procedure RunInsensitive;
    procedure RunCfg(const ACfg: TCfg);
    procedure ScanBody(const N: TTSNode);
  public
    constructor Create(const ASym: TSymbol; const AProc, ABody: TTSNode; const ASrc: TBytes;
                       const AOwnerFields, AGlobals: TArray<string>; const ACallees: TDataFlowCallees);
    destructor Destroy; override;
    function Bottom: TTaintVal;
    function Boundary: TTaintVal;
    function Join(const A, B: TTaintVal): TTaintVal;
    function Transfer(const ABlock: TCfgBlock; const AIn: TTaintVal): TTaintVal;
    function Same(const A, B: TTaintVal): Boolean;
    procedure Run;
    function Rows: TArray<TDataFlowRow>;
  end;

function ExprUnion(const A, B: TExprVal): TExprVal;
begin
  Result.May := SetUnion(A.May, B.May);
  Result.Must:= SetUnion(A.Must, B.Must);
end;

function ExprEmpty: TExprVal;
begin
  Result.May := nil;
  Result.Must:= nil;
end;

function IsDottedIdentChain(const N: TTSNode): Boolean;
var
  R: TTSNode;
begin
  Result:= False;
  if N.IsNull then Exit;
  if N.NodeType = 'identifier' then Exit(True);
  if N.NodeType <> 'exprDot' then Exit;
  R:= N.ChildByField('rhs');
  if R.IsNull or (R.NodeType <> 'identifier') then Exit;
  Result:= IsDottedIdentChain(N.ChildByField('lhs'));
end;

function IsIndexedReceiver(const N: TTSNode): Boolean;  // dl:ok too-many-exit-points@0ebd -- shape-dispatch guard clauses mirroring the parser's IsIndexedMemberReceiver
var
  Op, Operand, R: TTSNode;
begin
  Result:= False;
  if N.IsNull then Exit;
  if N.NodeType = 'exprSubscript' then Exit(True);
  if N.NodeType = 'exprUnary' then
  begin
    Op     := N.ChildByField('operator');
    Operand:= N.ChildByField('operand');
    if Op.IsNull or Operand.IsNull or (Op.StartByte < Operand.EndByte) then Exit; { prefix operator }
    Exit(IsDottedIdentChain(Operand) or IsIndexedReceiver(Operand));
  end;
  if N.NodeType <> 'exprDot' then Exit;
  R:= N.ChildByField('rhs');
  if R.IsNull or (R.NodeType <> 'identifier') then Exit;
  Result:= IsIndexedReceiver(N.ChildByField('lhs'));
end;

function IsParenRooted(const N: TTSNode): Boolean;
var
  R: TTSNode;
begin
  Result:= False;
  if N.IsNull then Exit;
  if N.NodeType = 'exprParens' then Exit(True);
  if N.NodeType <> 'exprDot' then Exit;
  R:= N.ChildByField('rhs');
  if R.IsNull or (R.NodeType <> 'identifier') then Exit;
  Result:= IsParenRooted(N.ChildByField('lhs'));
end;

{ Mirror of the parser's IsHardCastRootedReceiver (ref-gap G5): a bare identifier
  called with exactly ONE argument -- T(X) -- or a dotted identifier chain rooted
  in one, T(X).A.B. A cast and a one-argument function call look alike; the
  parser records the ref either way and the resolver decides. }
function IsHardCastRooted(const N: TTSNode): Boolean;
var
  E, A, R: TTSNode;
begin
  Result:= False;
  if N.IsNull then Exit;
  if N.NodeType = 'exprCall' then
  begin
    E:= N.ChildByField('entity');
    A:= N.ChildByField('args');
    Exit((not E.IsNull) and (E.NodeType = 'identifier') and (not A.IsNull) and (A.NamedChildCount = 1));
  end;
  if N.NodeType <> 'exprDot' then Exit;
  R:= N.ChildByField('rhs');
  if R.IsNull or (R.NodeType <> 'identifier') then Exit;
  Result:= IsHardCastRooted(N.ChildByField('lhs'));
end;

{ The receiver shapes L for which the parser emits a 'member-access' ref at the
  member identifier of `L.M` (DRagLint.Parser.Delphi13, ref-gaps G, G2, G3, G4, G5):
  a plain identifier other than Self, a dotted identifier chain, an indexed, a
  parenthesised or a hard-cast root. Mirrored here so every 'write' row and every src 'ref' row
  lands on a refs row (run_dataflow_facts.ps1 joins them). }
function RefShapeOk(const L: TTSNode; AIsSelf: Boolean): Boolean;
begin
  Result:= False;
  if L.IsNull then Exit;
  if L.NodeType = 'identifier' then Exit(not AIsSelf);
  Result:= ((L.NodeType = 'exprDot') and IsDottedIdentChain(L)) or IsIndexedReceiver(L) or IsParenRooted(L) or IsHardCastRooted(L);
end;
{ ---- TTaintReach -------------------------------------------------------- }

constructor TTaintReach.Create(AC: TCollector);
begin
  inherited Create;
  FC:= AC;
end;

function TTaintReach.Direction: TFlowDir;
begin
  Result:= fdForward;
end;

function TTaintReach.Bottom: TTaintVal;
begin
  Result:= FC.Bottom;
end;

function TTaintReach.Boundary: TTaintVal;
begin
  Result:= FC.Boundary;
end;

function TTaintReach.Join(const A, B: TTaintVal): TTaintVal;
begin
  Result:= FC.Join(A, B);
end;

function TTaintReach.Transfer(const ABlock: TCfgBlock; const AIn: TTaintVal): TTaintVal;
begin
  Result:= FC.Transfer(ABlock, AIn);
end;

function TTaintReach.Equals(const A, B: TTaintVal): Boolean;
begin
  Result:= FC.Same(A, B);
end;

{ ---- TCollector --------------------------------------------------------- }

constructor TCollector.Create(const ASym: TSymbol; const AProc, ABody: TTSNode; const ASrc: TBytes;
                              const AOwnerFields, AGlobals: TArray<string>; const ACallees: TDataFlowCallees);
var
  S          : string;
  I, PCounter: Integer;
  RV         : TRoutineVar;
  LType      : string;
begin
  inherited Create;
  FCallees  := ACallees;
  FSym      := ASym;
  FProc     := AProc;
  FBody     := ABody;
  FSrc      := ASrc;
  FFields   := TDictionary<string, string>.Create;
  FGlobals  := TDictionary<string, string>.Create;
  FIterables:= TDictionary<string, TArray<TTSNode>>.Create;
  FToks     := TList<TSrcTok>.Create;
  FTokIdx   := TDictionary<string, Integer>.Create;
  FRows     := TList<TDataFlowRow>.Create;
  FRowIdx   := TDictionary<string, Integer>.Create;
  for S in AOwnerFields do FFields.AddOrSetValue(LowerCase(S), S);
  for S in AGlobals do FGlobals.AddOrSetValue(LowerCase(S), S);
  FVars:= TRoutineVarTable.Build(AProc, ASrc);
  ScanBody(ABody);
  FNSlots:= FVars.Count;
  SetLength(FSlotKind, FNSlots);
  SetLength(FSlotScalar, FNSlots);
  SetLength(FSlotString, FNSlots);
  SetLength(FSlotPIdx, FNSlots);
  SetLength(FSlotPTok, FNSlots);
  SetLength(FSlotName, FNSlots);
  SetLength(FSiteLine, FNSlots);
  SetLength(FSiteCol, FNSlots);
  PCounter:= 0;
  for I:= 0 to FNSlots - 1 do
  begin
    RV:= FVars.Get(I);
    LType:= LowerCase(Trim(RV.TypeText));
    FSlotKind[I]  := RV.Kind;
    FSlotScalar[I]:= InList(LType, TAINT_SCALAR_TYPES);
    FSlotString[I]:= InList(LType, TAINT_STRING_TYPES);
    FSlotName[I]  := RV.Display;
    FSlotPIdx[I]  := -1;
    FSlotPTok[I]  := -1;
    if RV.Kind in [vkParamVar, vkParamOut, vkParamConst, vkParamValue] then
    begin
      FSlotPIdx[I]:= PCounter;
      Inc(PCounter);
      if not FSlotScalar[I] then FSlotPTok[I]:= Tok(DF_SRC_PARAM, FSlotPIdx[I], 0, 0, RV.Display);
    end;
  end;
  FResultSlot:= FVars.IndexOf('result');
end;

destructor TCollector.Destroy;
begin
  FRowIdx.Free;
  FRows.Free;
  FTokIdx.Free;
  FToks.Free;
  FIterables.Free;
  FGlobals.Free;
  FFields.Free;
  FVars.Free;
  inherited;  // dl:ok inherited-bare@246d -- destructor chaining to TObject.Destroy
end;

{ Registers what TRoutineVarTable.Build leaves out on purpose (a single bare inline
  `var X: T;` -- see its RegisterRedeclaredDefs) and collects every foreach
  iterator -> iterable expression. Lambdas and nested routines are their own scope. }
procedure TCollector.ScanBody(const N: TTSNode);
var
  I      : Integer;
  IdN, It: TTSNode;
  RV     : TRoutineVar;
  Key    : string;
  Arr    : TArray<TTSNode>;
begin
  if N.IsNull then Exit;
  if (N.NodeType = 'defProc') or (N.NodeType = 'lambda') then Exit;
  if N.NodeType = 'varDef' then
  begin
    IdN:= Default(TTSNode);
    for I:= 0 to N.NamedChildCount - 1 do
      if N.NamedChild(I).NodeType = 'identifier' then
      begin
        IdN:= N.NamedChild(I);
        Break;
      end;
    if (not IdN.IsNull) and (FVars.IndexOf(LowerCase(Text(IdN))) < 0) then
    begin
      RV:= Default(TRoutineVar);
      RV.Name    := LowerCase(Text(IdN));
      RV.Display := Text(IdN);
      RV.Kind    := vkLocal;
      RV.TypeText:= Trim(Text(N.ChildByField('type')));
      RV.DeclLine:= Integer(IdN.StartPoint.Row) + 1;
      RV.DeclCol := Integer(IdN.StartPoint.Column) + 1;
      FVars.Add(RV);
    end;
  end;
  if N.NodeType = 'foreach' then
  begin
    It:= N.ChildByField('iterator');
    if (not It.IsNull) and (It.NodeType = 'varAssignDef') then
      for I:= 0 to It.NamedChildCount - 1 do
        if It.NamedChild(I).NodeType = 'identifier' then
        begin
          It:= It.NamedChild(I);
          Break;
        end;
    if (not It.IsNull) and (It.NodeType = 'identifier') and (not N.ChildByField('iterable').IsNull) then
    begin
      Key:= LowerCase(Text(It));
      if not FIterables.TryGetValue(Key, Arr) then Arr:= nil;
      FIterables.AddOrSetValue(Key, Arr + [N.ChildByField('iterable')]);
    end;
  end;
  for I:= 0 to N.NamedChildCount - 1 do ScanBody(N.NamedChild(I));
end;

function TCollector.Text(const N: TTSNode): string;
var
  S, E: Integer;
begin
  Result:= '';
  if N.IsNull then Exit;
  S:= Integer(N.StartByte);
  E:= Integer(N.EndByte);
  if (S < 0) or (E <= S) or (E > Length(FSrc)) then Exit;
  Result:= TEncoding.UTF8.GetString(FSrc, S, E - S);
end;

function TCollector.Tok(const AKind: string; AIndex, ALine, ACol: Integer; const AName: string): Integer;
var
  Key: string;
  T  : TSrcTok;
begin
  Key:= AKind + '|' + IntToStr(AIndex) + '|' + IntToStr(ALine) + '|' + IntToStr(ACol) + '|' + LowerCase(AName);
  if FTokIdx.TryGetValue(Key, Result) then Exit;
  T.Kind := AKind;
  T.Index:= AIndex;
  T.Line := ALine;
  T.Col  := ACol;
  T.Name := AName;
  Result:= FToks.Add(T);
  FTokIdx.Add(Key, Result);
end;

function TCollector.TokVal(ATok: Integer): TExprVal;
begin
  Result.May := [ATok * 2];
  Result.Must:= [ATok];
end;

function TCollector.SlotOf(const N: TTSNode): Integer;
begin
  Result:= -1;
  if N.IsNull or (N.NodeType <> 'identifier') then Exit;
  Result:= FVars.IndexOfAt(LowerCase(Text(N)), Integer(N.StartByte));
end;

{ The leftmost identifier of a receiver expression (`X`, `X.f`, `X[i]`, `X.f[i].g`),
  skipping a leading `Self.`; a null node when the root is not an identifier. }
function TCollector.BaseIdent(const N: TTSNode): TTSNode;
var
  Cur, L: TTSNode;
  Guard : Integer;
begin
  Result:= Default(TTSNode);
  Cur   := N;
  for Guard:= 1 to DF_RECEIVER_DEPTH do
  begin
    if Cur.IsNull then Exit;
    if Cur.NodeType = 'identifier' then Exit(Cur);
    if Cur.NodeType = 'exprDot' then
    begin
      L:= Cur.ChildByField('lhs');
      if (not L.IsNull) and (L.NodeType = 'identifier') and SameText(Text(L), 'Self') then Exit(Cur.ChildByField('rhs'));
      Cur:= L;
    end
    else if Cur.NodeType = 'exprSubscript' then Cur:= Cur.ChildByField('entity')
    else Exit;
  end;
end;

function TCollector.CopyVal(const A: TTaintVal): TTaintVal;
begin
  Result.Reached:= A.Reached;
  Result.May    := Copy(A.May);
  Result.Must   := Copy(A.Must);
end;

function TCollector.Bottom: TTaintVal;
begin
  Result.Reached:= False;
  Result.May    := nil;
  Result.Must   := nil;
end;

function TCollector.Boundary: TTaintVal;
var
  I: Integer;
begin
  Result.Reached:= True;
  SetLength(Result.May, FNSlots);
  SetLength(Result.Must, FNSlots);
  for I:= 0 to FNSlots - 1 do
    if (FSlotPTok[I] >= 0) and (FSlotKind[I] <> vkParamOut) then
    begin
      Result.May[I] := [FSlotPTok[I] * 2];
      Result.Must[I]:= [FSlotPTok[I]];
    end;
end;

function TCollector.Join(const A, B: TTaintVal): TTaintVal;
var
  I: Integer;
begin
  if not A.Reached then Exit(B);
  if not B.Reached then Exit(A);
  Result.Reached:= True;
  SetLength(Result.May, FNSlots);
  SetLength(Result.Must, FNSlots);
  for I:= 0 to FNSlots - 1 do
  begin
    Result.May[I] := SetUnion(A.May[I], B.May[I]);
    Result.Must[I]:= SetInter(A.Must[I], B.Must[I]);
  end;
end;

function TCollector.Same(const A, B: TTaintVal): Boolean;
var
  I: Integer;
begin
  if A.Reached <> B.Reached then Exit(False);
  if not A.Reached then Exit(True);
  for I:= 0 to FNSlots - 1 do
    if not (SetEq(A.May[I], B.May[I]) and SetEq(A.Must[I], B.Must[I])) then Exit(False);
  Result:= True;
end;

procedure TCollector.AddRow(const AKind: string; ALine, ACol, AIndex: Integer; const AName, ARecv: string;  // dl:ok too-many-parameters@254c -- one argument per data_flows column; a record would only restate TDataFlowRow
                            ATok: Integer; AVia, ACond: Boolean);
var
  Key: string;
  Idx: Integer;
  R  : TDataFlowRow;
  T  : TSrcTok;
begin
  Key:= AKind + '|' + IntToStr(ALine) + '|' + IntToStr(ACol) + '|' + IntToStr(AIndex) + '|' + LowerCase(AName)
        + '|' + IntToStr(ATok);
  if FRowIdx.TryGetValue(Key, Idx) then
  begin
    R:= FRows[Idx];
    R.ViaLocal:= R.ViaLocal and AVia;
    R.Cond    := R.Cond and ACond;
    FRows[Idx]:= R;
    Exit;
  end;
  if FRows.Count >= DF_ROW_CAP then
  begin
    if not FCapped then
    begin
      FCapped:= True;
      Inc(GCapped);
      Writeln(ErrOutput, Format('data_flows: row cap %d reached in %s (line %d); later rows dropped',
        [DF_ROW_CAP, FSym.Name, FSym.ImplStartLine]));
    end;
    Exit;
  end;
  T:= FToks[ATok];
  R:= Default(TDataFlowRow);
  R.SymbolId   := FSym.Id;
  R.OwnerId    := if FSym.ParentId > 0 then FSym.ParentId else 0;
  R.DstKind    := AKind;
  R.DstLine    := ALine;
  R.DstCol     := ACol;
  R.DstIndex   := AIndex;
  R.DstName    := AName;
  R.DstReceiver:= ARecv;
  R.SrcKind    := T.Kind;
  R.SrcIndex   := T.Index;
  R.SrcLine    := T.Line;
  R.SrcCol     := T.Col;
  R.SrcName    := T.Name;
  R.ViaLocal   := AVia;
  R.Cond       := ACond;
  FRowIdx.Add(Key, FRows.Add(R));
end;

procedure TCollector.RecordDst(const AKind: string; const APos: TTSNode; AIndex: Integer; const AName, ARecv: string;
                               const AV: TExprVal);
var
  E, T: Integer;
begin
  if (not FRecording) or APos.IsNull then Exit;
  for E in AV.May do
  begin
    T:= E shr 1;
    AddRow(AKind, Integer(APos.StartPoint.Row) + 1, Integer(APos.StartPoint.Column) + 1, AIndex, AName, ARecv,
      T, (E and 1) = 1, FInsensitive or not SetHas(AV.Must, T));
  end;
end;

procedure TCollector.AssignSlot(var St: TTaintVal; ASlot: Integer; const AV: TExprVal; AKill: Boolean;
                                const ASite: TTSNode);
var
  L, C: Integer;
begin
  if (ASlot < 0) or (ASlot >= FNSlots) then Exit;
  if FSlotScalar[ASlot] then
  begin
    St.May[ASlot] := nil;
    St.Must[ASlot]:= nil;
    Exit;
  end;
  if AKill and not FInsensitive then
  begin
    St.May[ASlot] := AV.May;
    St.Must[ASlot]:= AV.Must;
  end
  else
  begin
    St.May[ASlot] := SetUnion(St.May[ASlot], AV.May);
    St.Must[ASlot]:= SetUnion(St.Must[ASlot], AV.Must);
  end;
  if FRecording and (not ASite.IsNull) then
  begin
    L:= Integer(ASite.StartPoint.Row) + 1;
    C:= Integer(ASite.StartPoint.Column) + 1;
    if (FSiteLine[ASlot] = 0) or (L < FSiteLine[ASlot]) or ((L = FSiteLine[ASlot]) and (C < FSiteCol[ASlot])) then
    begin
      FSiteLine[ASlot]:= L;
      FSiteCol[ASlot] := C;
    end;
  end;
end;

{ `X.Add(e)`, `X.f := e`, `X[i] := e`: the base X receives e. A local/param slot
  gains e's sources; a field or global base is a 'field' / 'global' destination. }
procedure TCollector.ReceiveInto(var St: TTaintVal; const ABase: TTSNode; const AV: TExprVal);
var
  Slot: Integer;
  Nm  : string;
begin
  if ABase.IsNull or (ABase.NodeType <> 'identifier') then Exit;
  Slot:= SlotOf(ABase);
  if Slot >= 0 then
  begin
    AssignSlot(St, Slot, AV, False, ABase);
    Exit;
  end;
  Nm:= LowerCase(Text(ABase));
  if FFields.ContainsKey(Nm) then RecordDst(DF_DST_FIELD, ABase, -1, Text(ABase), '', AV)
  else if FGlobals.ContainsKey(Nm) then RecordDst(DF_DST_GLOBAL, ABase, -1, Text(ABase), '', AV);
end;

function TCollector.ReadSlot(const St: TTaintVal; ASlot: Integer): TExprVal;
var
  I, E: Integer;
begin
  Result:= ExprEmpty;
  if (ASlot < 0) or (ASlot >= FNSlots) or FSlotScalar[ASlot] then Exit;
  SetLength(Result.May, Length(St.May[ASlot]));
  for I:= 0 to High(St.May[ASlot]) do
  begin
    E:= St.May[ASlot][I];
    { a parameter read as itself is direct; everything else came through state }
    if (E shr 1) <> FSlotPTok[ASlot] then E:= E or 1;
    Result.May[I]:= E;
  end;
  Result.May := SetNorm(Result.May);
  Result.Must:= St.Must[ASlot];
end;

function TCollector.EvalIdent(var St: TTaintVal; const N: TTSNode): TExprVal;
var
  Slot: Integer;
  Nm  : string;
begin
  Result:= ExprEmpty;
  Nm:= LowerCase(Text(N));
  if (Nm = '') or (Nm = 'self') then Exit;
  Slot:= SlotOf(N);
  if Slot >= 0 then Exit(ReadSlot(St, Slot));
  if FFields.ContainsKey(Nm) then Exit(TokVal(Tok(DF_SRC_FIELD, -1, 0, 0, Text(N))));
  if FGlobals.ContainsKey(Nm) then Exit(TokVal(Tok(DF_SRC_GLOBAL, -1, 0, 0, Text(N))));
  Result:= TokVal(Tok(DF_SRC_REF, -1, Integer(N.StartPoint.Row) + 1, Integer(N.StartPoint.Column) + 1, Text(N)));
end;

function TCollector.EvalDot(var St: TTaintVal; const N: TTSNode): TExprVal;  // dl:ok too-many-exit-points@49b8 -- one early Exit per receiver shape (Self, local, member ref)
var
  L, R, Base: TTSNode;
  LV        : TExprVal;
  Member, BN: string;
begin
  L:= N.ChildByField('lhs');
  R:= N.ChildByField('rhs');
  if (not L.IsNull) and (L.NodeType = 'identifier') and SameText(Text(L), 'Self') then
  begin
    if R.IsNull or (R.NodeType <> 'identifier') then Exit(Eval(St, R));
    if FFields.ContainsKey(LowerCase(Text(R))) then Exit(TokVal(Tok(DF_SRC_FIELD, -1, 0, 0, Text(R))));
    Exit(TokVal(Tok(DF_SRC_REF, -1, Integer(R.StartPoint.Row) + 1, Integer(R.StartPoint.Column) + 1, Text(R))));
  end;
  LV:= Eval(St, L);
  Member:= '';
  if (not R.IsNull) and (R.NodeType = 'identifier') then Member:= LowerCase(Text(R));
  Base:= BaseIdent(L);
  if InList(Member, TAINT_NUMERIC_MEMBERS) then Exit(ExprEmpty);
  { a member of a local / param reads that variable }
  if SlotOf(Base) >= 0 then Exit(LV);
  if (Member <> '') and RefShapeOk(L, SameText(Text(L), 'Self')) then
  begin
    Result:= TokVal(Tok(DF_SRC_REF, -1, Integer(R.StartPoint.Row) + 1, Integer(R.StartPoint.Column) + 1, Text(R)));
    BN:= LowerCase(Text(Base));
    if ((BN <> '') and (FFields.ContainsKey(BN) or FGlobals.ContainsKey(BN))) or IsHardCastRooted(L) then Result:= ExprUnion(Result, LV); { a cast keeps its operand's taint }
    Exit;
  end;
  Result:= LV;
end;

function TCollector.EvalCall(var St: TTaintVal; const N: TTSNode): TExprVal;
var
  Ent, Args, NameN, Arg, Recv: TTSNode;
  Callee, RecvText           : string;
  I, Slot, CallLine, CallCol : Integer;
  ArgVals                    : TArray<TExprVal>;
  RecvVal, All               : TExprVal;
  T                          : Integer;
begin
  Result:= ExprEmpty;
  Ent := N.ChildByField('entity');
  Args:= N.ChildByField('args');
  NameN:= Default(TTSNode);
  Recv := Default(TTSNode);
  RecvText:= '';
  if not Ent.IsNull then
  begin
    if Ent.NodeType = 'identifier' then NameN:= Ent
    else if Ent.NodeType = 'exprDot' then
    begin
      NameN:= Ent.ChildByField('rhs');
      Recv := Ent.ChildByField('lhs');
      RecvText:= Trim(Text(Recv));
    end;
  end;
  if not Args.IsNull then
  begin
    SetLength(ArgVals, Args.NamedChildCount);
    for I:= 0 to Args.NamedChildCount - 1 do ArgVals[I]:= Eval(St, Args.NamedChild(I));
  end;
  RecvVal:= ExprEmpty;
  if not Recv.IsNull then RecvVal:= Eval(St, Recv);
  if NameN.IsNull or (NameN.NodeType <> 'identifier') then
  begin
    if (not Ent.IsNull) and (Ent.NodeType <> 'exprDot') and (Ent.NodeType <> 'identifier') then Eval(St, Ent);
    Exit;
  end;
  Callee:= LowerCase(Text(NameN));
  if Recv.IsNull and (Length(ArgVals) = 1) and InList(Callee, TAINT_TYPECASTS) then Exit(ArgVals[0]);
  if Recv.IsNull and (Callee = 'exit') then Exit;
  CallLine:= Integer(NameN.StartPoint.Row) + 1;
  CallCol := Integer(NameN.StartPoint.Column) + 1;
  for I:= 0 to High(ArgVals) do RecordDst(DF_DST_ARG, NameN, I, Text(NameN), RecvText, ArgVals[I]);
  { receive: X.Add(e) and friends }
  if (not Recv.IsNull) and InList(Callee, TAINT_RECEIVER_MUTATORS) then
  begin
    All:= ExprEmpty;
    for I:= 0 to High(ArgVals) do All:= ExprUnion(All, ArgVals[I]);
    ReceiveInto(St, BaseIdent(Recv), All);
  end;
  { argout: a plain variable argument may be written by the callee (a var/out slot) }
  if not InList(Callee, TAINT_NOFLOW_RESULT) then
    for I:= 0 to High(ArgVals) do
    begin
      Arg:= Args.NamedChild(I);
      Slot:= SlotOf(Arg);
      if (Slot < 0) or FSlotScalar[Slot] or not ArgMayBeWritten(Callee, I) then Continue;
      T:= Tok(DF_SRC_ARGOUT, I, CallLine, CallCol, Text(NameN));
      St.May[Slot] := SetUnion(St.May[Slot], [T * 2]);
      St.Must[Slot]:= SetUnion(St.Must[Slot], [T]);
    end;
  if InList(Callee, TAINT_NOFLOW_RESULT) then Exit;
  Result:= TokVal(Tok(DF_SRC_REF, -1, CallLine, CallCol, Text(NameN)));
  { a method of a string-typed local/param (`S.Trim`, `S.Substring(1)`) derives from it }
  Slot:= SlotOf(BaseIdent(Recv));
  if (Slot >= 0) and FSlotString[Slot] then Result:= ExprUnion(Result, RecvVal);
end;

{ May the callee ACallee (lower case) write argument AIndex? A same-unit callee
  answers by its var/out mask (a position past every overload: unknown, kept);
  else the RTL lists; else unresolved here -- kept, the linter resolves it. }
function TCollector.ArgMayBeWritten(const ACallee: string; AIndex: Integer): Boolean;
var
  Mask: TArray<Boolean>;
begin
  if Assigned(FCallees) and FCallees.TryGetValue(ACallee, Mask) then Exit((AIndex > High(Mask)) or Mask[AIndex]);
  Result:= if InList(ACallee, TAINT_ARGOUT_OUT1) then AIndex = TAINT_ARGOUT_OUT1_POS else not InList(ACallee, TAINT_ARGOUT_NONE);
end;

{ Per declared parameter of signature text ASig ('(const A, B: string; var C): T'),
  True when it is a var / out parameter. Splits on ';' at paren/bracket depth 0;
  a leading [attribute] is skipped. No parameter list: empty. }
function VarOutMask(const ASig: string): TArray<Boolean>;
var
  P, I, Depth, Start: Integer;
  Groups            : TArray<string>;
  G, Names, Modif   : string;
  IsVar             : Boolean;
begin
  Result:= nil;
  P:= Pos('(', ASig);
  if P = 0 then Exit;
  Groups:= nil;
  Depth:= 0;
  Start:= P + 1;
  for I:= P + 1 to Length(ASig) do
  begin
    if CharInSet(ASig[I], ['(', '[']) then Inc(Depth)
    else if CharInSet(ASig[I], [')', ']']) then
    begin
      if Depth = 0 then
      begin
        Groups:= Groups + [Copy(ASig, Start, I - Start)];
        Break;
      end;
      Dec(Depth);
    end
    else if (ASig[I] = ';') and (Depth = 0) then
    begin
      Groups:= Groups + [Copy(ASig, Start, I - Start)];
      Start:= I + 1;
    end;
  end;
  for G in Groups do
  begin
    Names:= Trim(G);
    if Names.StartsWith('[') and Names.Contains(']') then Names:= Trim(Copy(Names, Pos(']', Names) + 1, MaxInt));
    if Names.Contains(':') then Names:= Trim(Copy(Names, 1, Pos(':', Names) - 1));
    if Names = '' then Continue;
    Modif:= LowerCase(Names.Split([' ', #9, #13, #10], TStringSplitOptions.ExcludeEmpty)[0]);
    IsVar:= (Modif = 'var') or (Modif = 'out');
    for I:= 0 to High(Names.Split([','])) do Result:= Result + [IsVar];
  end;
end;

function TCollector.Eval(var St: TTaintVal; const N: TTSNode): TExprVal;  // dl:ok too-many-exit-points@ea9b -- node-type dispatcher: one Exit per grammar node kind
var
  NT, Op: string;
  I     : Integer;
  A, B  : TExprVal;
  OpN   : TTSNode;
begin
  Result:= ExprEmpty;
  if N.IsNull then Exit;
  NT:= N.NodeType;
  if InList(NT, TAINT_INERT_NODES) then Exit;
  if NT = 'identifier' then Exit(EvalIdent(St, N));
  if NT = 'exprDot' then Exit(EvalDot(St, N));
  if NT = 'exprCall' then Exit(EvalCall(St, N));
  if NT = 'assignment' then
  begin
    ApplyAssignment(St, N);
    Exit;
  end;
  if NT = 'lambda' then
  begin
    WalkLambda(St, N);
    Exit;
  end;
  if NT = 'exprSubscript' then
  begin
    Eval(St, N.ChildByField('args'));
    Exit(Eval(St, N.ChildByField('entity')));
  end;
  if NT = 'exprBinary' then
  begin
    OpN:= N.ChildByField('operator');
    Op := if OpN.IsNull then '' else OpN.NodeType;
    A:= Eval(St, N.ChildByField('lhs'));
    B:= Eval(St, N.ChildByField('rhs'));
    if Op = 'kAdd' then Exit(ExprUnion(A, B));
    if Op = 'kAs' then Exit(A);
    Exit;
  end;
  if NT = 'exprUnary' then
  begin
    OpN:= N.ChildByField('operator');
    Op := if OpN.IsNull then '' else OpN.NodeType;
    A:= Eval(St, N.ChildByField('operand'));
    if (Op = 'kAt') or (Op = 'kHat') then Exit(A);
    Exit;
  end;
  if NT = 'exprIf' then
  begin
    Eval(St, N.ChildByField('condition'));
    A:= Eval(St, N.ChildByField('then'));
    B:= Eval(St, N.ChildByField('else'));
    Result.May := SetUnion(A.May, B.May);
    Result.Must:= SetInter(A.Must, B.Must);
    Exit;
  end;
  { exprParens, exprBrackets (`[A, B]`: an open array is one value), exprArgs, anything else }
  for I:= 0 to N.NamedChildCount - 1 do Result:= ExprUnion(Result, Eval(St, N.NamedChild(I)));
end;

procedure TCollector.ApplyMemberWrite(var St: TTaintVal; const ALhs: TTSNode; const AV: TExprVal);
var
  Ent, Member, Recv, Base: TTSNode;
begin
  Ent:= ALhs;
  if ALhs.NodeType = 'exprSubscript' then
  begin
    Eval(St, ALhs.ChildByField('args'));
    Ent:= ALhs.ChildByField('entity');
    if (not Ent.IsNull) and (Ent.NodeType = 'identifier') then
    begin
      { X[i] := e }
      ReceiveInto(St, Ent, AV);
      Exit;
    end;
  end;
  if Ent.IsNull or (Ent.NodeType <> 'exprDot') then
  begin
    Eval(St, Ent);
    Exit;
  end;
  Recv  := Ent.ChildByField('lhs');
  Member:= Ent.ChildByField('rhs');
  Eval(St, Recv);
  if (not Recv.IsNull) and (Recv.NodeType = 'identifier') and SameText(Text(Recv), 'Self') then
  begin
    if (not Member.IsNull) and (Member.NodeType = 'identifier') then
      RecordDst(DF_DST_FIELD, Member, -1, Text(Member), '', AV);
    Exit;
  end;
  Base:= BaseIdent(Recv);
  ReceiveInto(St, Base, AV);
  if (not Member.IsNull) and (Member.NodeType = 'identifier') and RefShapeOk(Recv, SameText(Text(Recv), 'Self')) then
    RecordDst(DF_DST_WRITE, Member, -1, Text(Member), Trim(Text(Recv)), AV);
end;

procedure TCollector.ApplyAssignment(var St: TTaintVal; const N: TTSNode);
var
  Lhs, OpN, IdN: TTSNode;
  V            : TExprVal;
  Kill         : Boolean;
  Slot, I      : Integer;
  Nm           : string;
begin
  Lhs:= N.ChildByField('lhs');
  OpN:= N.ChildByField('operator');
  V  := Eval(St, N.ChildByField('rhs'));
  Kill:= OpN.IsNull or (OpN.NodeType = 'kAssign');
  if Lhs.IsNull then Exit;
  if Lhs.NodeType = 'varAssignDef' then
  begin
    IdN:= Lhs.ChildByField('name');
    if IdN.IsNull then
      for I:= 0 to Lhs.NamedChildCount - 1 do
        if Lhs.NamedChild(I).NodeType = 'identifier' then
        begin
          IdN:= Lhs.NamedChild(I);
          Break;
        end;
    AssignSlot(St, SlotOf(IdN), V, True, IdN);
    Exit;
  end;
  if Lhs.NodeType = 'identifier' then
  begin
    Slot:= SlotOf(Lhs);
    if Slot >= 0 then
    begin
      AssignSlot(St, Slot, V, Kill, Lhs);
      Exit;
    end;
    Nm:= LowerCase(Text(Lhs));
    if FFields.ContainsKey(Nm) then RecordDst(DF_DST_FIELD, Lhs, -1, Text(Lhs), '', V)
    else if FGlobals.ContainsKey(Nm) then RecordDst(DF_DST_GLOBAL, Lhs, -1, Text(Lhs), '', V)
    else RecordDst(DF_DST_WRITE, Lhs, -1, Text(Lhs), '', V);
    Exit;
  end;
  if (Lhs.NodeType = 'exprDot') or (Lhs.NodeType = 'exprSubscript') then
  begin
    ApplyMemberWrite(St, Lhs, V);
    Exit;
  end;
  Eval(St, Lhs);
end;

procedure TCollector.ApplyStmtExpr(var St: TTaintVal; const E: TTSNode);
var
  Ent, Args: TTSNode;
begin
  if E.IsNull then Exit;
  if E.NodeType = 'exprCall' then
  begin
    Ent := E.ChildByField('entity');
    Args:= E.ChildByField('args');
    if (not Ent.IsNull) and (Ent.NodeType = 'identifier') and SameText(Text(Ent), 'exit') then
    begin
      if (not Args.IsNull) and (Args.NamedChildCount > 0) and (FResultSlot >= 0) then
        AssignSlot(St, FResultSlot, Eval(St, Args.NamedChild(0)), True, E);
      Exit;
    end;
  end;
  Eval(St, E);
end;

procedure TCollector.ApplyItem(var St: TTaintVal; const N: TTSNode);
var
  I : Integer;
  NT: string;
begin
  NT:= N.NodeType;
  if NT = 'assignment' then ApplyAssignment(St, N)
  else if NT = 'statement' then
    for I:= 0 to N.NamedChildCount - 1 do ApplyStmtExpr(St, N.NamedChild(I))
  else if (NT = 'exprCall') or (NT = 'exprDot') or (NT = 'identifier') then ApplyStmtExpr(St, N)
  else if (NT <> 'varDef') and (NT <> 'asm') then Eval(St, N);
end;

{ A lambda body: walked structurally with a COPY of the state at the lambda (its
  captured locals), flow-insensitively, recording on the second pass only. Its
  writes never flow back into the enclosing routine's state. }
procedure TCollector.WalkLambda(const St: TTaintVal; const N: TTSNode);
var
  LS        : TTaintVal;
  SaveRec   : Boolean;
  SaveInsens: Boolean;
begin
  if (not FRecording) or (not St.Reached) then Exit;
  LS:= CopyVal(St);
  SaveRec:= FRecording;
  SaveInsens:= FInsensitive;
  FInsensitive:= True;
  try
    FRecording:= False;
    FlatWalk(LS, N.ChildByField('body'));
    FRecording:= SaveRec;
    FlatWalk(LS, N.ChildByField('body'));
  finally
    FRecording  := SaveRec;
    FInsensitive:= SaveInsens;
  end;
end;

{ Source-order walk of a statement subtree (the flow-insensitive mode). }
procedure TCollector.FlatWalk(var St: TTaintVal; const N: TTSNode);
var
  I     : Integer;
  NT    : string;
  It, Cn: TTSNode;
begin
  if N.IsNull then Exit;
  NT:= N.NodeType;
  if (NT = 'defProc') or (NT = 'with') or (NT = 'asm') or (NT = 'comment') then Exit;
  if (NT = 'assignment') or (NT = 'statement') or (NT = 'raise') then
  begin
    ApplyItem(St, N);
    Exit;
  end;
  if NT.StartsWith('expr') or (NT = 'identifier') or (NT = 'lambda') then
  begin
    ApplyStmtExpr(St, N);
    Exit;
  end;
  if NT = 'foreach' then
  begin
    It:= N.ChildByField('iterator');
    if (not It.IsNull) and (It.NodeType = 'varAssignDef') then
      for I:= 0 to It.NamedChildCount - 1 do
        if It.NamedChild(I).NodeType = 'identifier' then
        begin
          It:= It.NamedChild(I);
          Break;
        end;
    AssignSlot(St, SlotOf(It), Eval(St, N.ChildByField('iterable')), False, It);
    FlatWalk(St, N.ChildByField('body'));
    Exit;
  end;
  for I:= 0 to N.NamedChildCount - 1 do
  begin
    Cn:= N.NamedChild(I);
    FlatWalk(St, Cn);
  end;
end;

function TCollector.Transfer(const ABlock: TCfgBlock; const AIn: TTaintVal): TTaintVal;
var
  Item    : TCfgItem;
  Name    : string;
  Slot    : Integer;
  Iters   : TArray<TTSNode>;
  ItN     : TTSNode;
  V       : TExprVal;
  SaveRec : Boolean;
begin
  if not AIn.Reached then Exit(AIn);
  Result:= CopyVal(AIn);
  for Name in ABlock.EntryDefs do
  begin
    Slot:= FVars.IndexOf(Name);
    if (Slot < 0) or not FIterables.TryGetValue(Name, Iters) then Continue;
    V:= ExprEmpty;
    SaveRec:= FRecording;
    FRecording:= False;
    try
      for ItN in Iters do V:= ExprUnion(V, Eval(Result, ItN));
    finally
      FRecording:= SaveRec;
    end;
    AssignSlot(Result, Slot, V, True, Default(TTSNode));
  end;
  for Item in ABlock.Items do
  begin
    if Item.Opaque then Continue;
    ApplyItem(Result, Item.Node);
  end;
end;

procedure TCollector.EmitExitRows(const St: TTaintVal);
var
  S, E, T, L, C, Idx: Integer;
  Kind, Nm          : string;
begin
  if not St.Reached then Exit;
  for S:= 0 to FNSlots - 1 do
  begin
    if FSlotScalar[S] then Continue;
    if S = FResultSlot then
    begin
      Kind:= DF_DST_RESULT;
      Idx:= -1;
      Nm:= '';
    end
    else if FSlotKind[S] in [vkParamVar, vkParamOut] then
    begin
      Kind:= DF_DST_OUTPARAM;
      Idx:= FSlotPIdx[S];
      Nm:= FSlotName[S];
    end
    else Continue;
    L:= FSiteLine[S];
    C:= FSiteCol[S];
    if L = 0 then
    begin
      L:= Integer(FProc.StartPoint.Row) + 1;
      C:= Integer(FProc.StartPoint.Column) + 1;
    end;
    for E in St.May[S] do
    begin
      T:= E shr 1;
      if T = FSlotPTok[S] then Continue; { a var param still holding its own entry value }
      AddRow(Kind, L, C, Idx, Nm, '', T, (E and 1) = 1, FInsensitive or not SetHas(St.Must[S], T));
    end;
  end;
end;

procedure TCollector.RunInsensitive;
var
  St, Prev: TTaintVal;
  Pass    : Integer;
begin
  Inc(GFallbacks);
  FInsensitive:= True;
  FRecording  := False;
  St:= Boundary;
  for Pass:= 1 to DF_FLAT_PASSES do
  begin
    Prev:= CopyVal(St);
    FlatWalk(St, FBody);
    if Same(Prev, St) then Break;
  end;
  FRecording:= True;
  FlatWalk(St, FBody);
  EmitExitRows(St);
end;

procedure TCollector.RunCfg(const ACfg: TCfg);
var
  Ana     : IDataFlowAnalysis<TTaintVal>;
  Ins, Outs: TArray<TTaintVal>;
  B       : TCfgBlock;
begin
  Ana:= TTaintReach.Create(Self);
  if not TDataFlowSolver<TTaintVal>.Solve(ACfg, Ana, Ins, Outs) then
  begin
    RunInsensitive;
    Exit;
  end;
  FRecording:= True;
  for B in ACfg.Blocks do
    if Ins[B.Index].Reached then Transfer(B, Ins[B.Index]);
  EmitExitRows(Ins[ACfg.ExitIdx]);
end;

procedure TCollector.Run;
var
  Cfg: TCfg;
begin
  Cfg:= TCfgBuilder.Build(FProc, FSrc);
  try
    if Cfg.Skipped then RunInsensitive
    else if Cfg.BlockCount > DF_CFG_BLOCK_CAP then
    begin
      Writeln(ErrOutput, Format('data_flows: flow-insensitive fallback for %s (line %d, %d CFG blocks > %d)',
        [FSym.Name, FSym.ImplStartLine, Cfg.BlockCount, DF_CFG_BLOCK_CAP]));
      RunInsensitive;
    end
    else RunCfg(Cfg);
  finally
    Cfg.Free;
  end;
end;

function TCollector.Rows: TArray<TDataFlowRow>;
begin
  Result:= FRows.ToArray;
end;

{ ---- TDataFlowFacts ----------------------------------------------------- }

class function TDataFlowFacts.Collect(const ASym: TSymbol; const AProc, ABody: TTSNode; const ASrc: TBytes;
                                      const AOwnerFields: TArray<string>;
                                      const AGlobals: TArray<string>;
                                      const ACallees: TDataFlowCallees): TArray<TDataFlowRow>;
var
  C: TCollector;
begin
  Result:= nil;
  if AProc.IsNull or ABody.IsNull or (ABody.NodeType = 'asm') then Exit;
  C:= TCollector.Create(ASym, AProc, ABody, ASrc, AOwnerFields, AGlobals, ACallees);
  try
    try
      C.Run;
      Result:= C.Rows;
    except
      on E: Exception do
      begin
        Writeln(ErrOutput, Format('data_flows: %s (line %d) skipped: %s: %s', [ASym.Name, ASym.ImplStartLine, E.ClassName, E.Message]));
        Result:= nil;
      end;
    end;
  finally
    C.Free;
  end;
end;

class function TDataFlowFacts.BuildCallees(const ASymbols: TArray<TSymbol>): TDataFlowCallees;
var
  S         : TSymbol;
  Key       : string;
  Mask, Old : TArray<Boolean>;
  I         : Integer;
begin
  Result:= TDataFlowCallees.Create;
  for S in ASymbols do
  begin
    if S.Kind not in [skFunction, skProcedure, skMethod, skConstructor, skDestructor] then Continue;
    { 'TFoo.Bar' (an implementation header) and 'Bar<T>' key as 'bar', the call's identifier }
    Key:= LowerCase(S.Name);
    if Key.Contains('<') then Key:= Copy(Key, 1, Pos('<', Key) - 1);
    Key:= Copy(Key, LastDelimiter('.', Key) + 1, MaxInt);
    Mask:= VarOutMask(S.Signature);
    if Result.TryGetValue(Key, Old) then
    begin
      if Length(Old) > Length(Mask) then SetLength(Mask, Length(Old));
      for I:= 0 to High(Old) do Mask[I]:= Mask[I] or Old[I];
    end;
    Result.AddOrSetValue(Key, Mask);
  end;
end;

class function TDataFlowFacts.FallbackCount: Integer;
begin
  Result:= GFallbacks;
end;

class function TDataFlowFacts.CappedCount: Integer;
begin
  Result:= GCapped;
end;

end.
