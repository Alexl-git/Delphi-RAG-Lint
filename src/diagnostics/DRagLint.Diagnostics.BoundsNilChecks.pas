unit DRagLint.Diagnostics.BoundsNilChecks;

{ Gap-rules wave (plan 2026-10-27-rule-gaps-and-compliance-plan.md), lane G5.
  The ids are already in LINT_GATE_BOUNDS_NIL (CLI.pas) and in
  TRuleCatalog.BuiltinRegistry -- this lane registers nothing in CLI.pas or
  RuleCatalog.pas.
  Rules (pure AST, no symbol store needed):
    nil-check-after-dereference : in ONE block, a statement dereferences an
                           identifier (X.member, X[i], X^) and a LATER statement
                           of the same block tests it (Assigned(X), X <> nil,
                           X = nil) with no assignment to X between. Only simple
                           statements count as the dereference (an `if` that
                           guards the use is not one); X.Free / Destroy / Release
                           are not dereferences for this rule. warning.
    address-of-local-returned : `Result := @L`, `Exit(@L)`, and the casts
                           PChar/PAnsiChar/PWideChar/Pointer(L) of a string or
                           static-array local, where L is a routine local or a
                           BY-VALUE parameter. var/const/out parameters and
                           globals are the non-hit. warning.
    constant-index-out-of-range : A[<literal>] where A is a local, field or
                           const of this file declared array[lo..hi] of and the
                           literal lies outside lo..hi; S[0] where S is a
                           (1-based) string. A name declared with two different
                           shapes in the file is ambiguous and stays silent. warning.
    copy-paste-assignment : OFF. A run of >= 3 consecutive `A.p := B.q`
                           assignments (same A, same B) where all rows but one
                           have p = q and the odd row repeats another row's q; a
                           2-row run is a hit only when the two lhs members are a
                           known axis pair (Left/Top, Width/Height, X/Y, Min/Max).
                           hint. Fixable (risky): the odd rhs member becomes p.
    index-possibly-out-of-range : ON (1.52 IDXRANGE3, spec 2026-11-16-index-possibly-out-of-range-design.md).
                           A[idx] where A is a static or dynamic array and idx a routine local
                           or parameter, with no dominating guard (for over the bounds, if /
                           while condition, InRange, an earlier Exit/raise guard) and no write
                           history bounding idx on BOTH sides. Reported on the nearest write of
                           idx (warning); an unwritten parameter reports on the access (hint).
                           A subrange type is not a guard. Fixable (risky): an InRange guard
                           raising params.index-possibly-out-of-range.exception_class. }

interface

uses
  DRagLint.Core.Model
  , DRagLint.Core.Interfaces
  , DRagLint.Lint.Config
  ;

type
  /// <summary>Checker for the BoundsNilChecks rules of the gap-rules wave (G5).</summary>
  /// <remarks>
  /// Stateless; thread-safe. Called from DoLint and DoLintAll behind
  /// LintRuleWants(rule, LINT_GATE_BOUNDS_NIL). All five rules are emitted on every
  /// call; the CLI filters by --rule and by the enabled set (copy-paste-assignment
  /// is OFF by default; index-possibly-out-of-range is ON since 1.52 IDXRANGE3).
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.CLI.DoLint (DRagLint.CLI.pas), DRagLint.CLI.DoLintAll (DRagLint.CLI.pas)</para>
  /// <para>Used in units: DRagLint.CLI</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TBoundsNilChecker = class
  public
    /// <summary>Runs the BoundsNilChecks rules against one source file.</summary>
    /// <param name="AFile">Absolute path to the .pas/.inc source file.</param>
    /// <param name="ACfg">Effective lint configuration; only IndexGuardExceptionClass is read (the class the index-possibly-out-of-range fix raises).</param>
    /// <param name="AStore">Optional symbol store; nil when the run has no index (unused: store-free rules).</param>
    /// <param name="AFileId">File id within AStore (ignored when AStore is nil).</param>
    /// <returns>One finding per violation; empty when clean or unparsable. The CLI filters by --rule.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.CLI.DoLint (DRagLint.CLI.pas), DRagLint.CLI.DoLintAll (DRagLint.CLI.pas)</para>
    /// <para>Calls: DRagLint.Diagnostics.BoundsNilChecks.TBnRun.Create, DRagLint.Diagnostics.BoundsNilChecks.TBnRun.Run, DRagLint.Diagnostics.ParseCache.TAstParseCache.Get, TreeSitter.TTSTree.RootNode</para>
    /// <para>Returns: nil; Run.Run(PF.Tree.RootNode)</para>
    /// <para>Directives: static</para>
    /// <seealso cref="DRagLint.Diagnostics.BoundsNilChecks.TBnRun.Create"/>
    /// <seealso cref="DRagLint.Diagnostics.BoundsNilChecks.TBnRun.Run"/>
    /// <seealso cref="DRagLint.Diagnostics.ParseCache.TAstParseCache.Get"/>
    /// <seealso cref="TreeSitter.TTSTree.RootNode"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function Check(const AFile: string; const ACfg: TLintConfig;
      const AStore: ISymbolStore; AFileId: Int64): TArray<TLintFinding>; static;
  end;

implementation

uses
  System.SysUtils
  , System.Classes
  , System.Generics.Collections
  , System.Generics.Defaults
  , System.RegularExpressions
  , TreeSitter
  , DRagLint.Diagnostics.ParseCache
  , DRagLint.Refactor.TextEdit
  , DRagLint.Lint.Autofix
  , System.StrUtils
  , DRagLint.Core.LiveDocs
  ;

const
  MAX_FINDINGS = 200;
  MIN_RUN_ROWS = 3;
  RULE_NIL_CHECK = 'nil-check-after-dereference';
  RULE_ADDR_LOCAL = 'address-of-local-returned';
  RULE_CONST_INDEX = 'constant-index-out-of-range';
  RULE_COPY_PASTE = 'copy-paste-assignment';
  RULE_INDEX_RANGE = 'index-possibly-out-of-range';
  DEFAULT_INDEX_GUARD_EXCEPTION = 'EArgumentOutOfRangeException';
  DYN_ARRAY_TYPE_PATTERN = '^(?:packed\s+)?array\s+of\b|^tarray\s*<|^tbytes$';
  { Members whose call is not a use of the object for nil-check-after-dereference. }
  RELEASE_MEMBERS: array[0..3] of string = ('free', 'destroy', 'disposeof', 'release');
  { Axis-pair lhs members: a 2-row copy-paste run is a hit only for these. }
  AXIS_PAIRS: array[0..3] of array[0..1] of string = (
    ('left', 'top'), ('width', 'height'), ('x', 'y'), ('min', 'max'));
  STRING_TYPES: array[0..4] of string = (
    'string', 'unicodestring', 'ansistring', 'rawbytestring', 'widestring');
  CAST_NAMES: array[0..3] of string = ('pchar', 'pansichar', 'pwidechar', 'pointer');
  ARRAY_TYPE_PATTERN = '^(?:packed\s+)?array\s*\[\s*(-?\w+)\s*\.\.\s*(-?\w+)\s*\]\s*of\b';

type
  { What a declaration says about one name, as far as the rules care. }
  TDeclKind = (dkOther, dkString, dkArray, dkDynArray);

  TDeclInfo = record
    Kind   : TDeclKind;
    Lo     : Integer;
    Hi     : Integer;
    ByRef  : Boolean;  { var / const / out / constref parameter }
    IsParam: Boolean;
    Ambig  : Boolean;  { the file declares the name with different shapes }
  end;

  { One assignment row of a copy-paste run. }
  TCopyRow = record
    Node : TTSNode;
    LBase: string;
    P    : string;
    RBase: string;
    Q    : string;
  end;

  { A symbolic integer for index-possibly-out-of-range: the count named by Base plus Off; Base ''
    is the constant Off. Bases: 'len:a' (Length of array a), 'cnt:b' (b.Count) -- both >= 0 --
    and 'id:n' (n, never written in the routine; any sign). Ok False: unknown. }
  TSym = record
    Base: string;
    Off : Integer;
    Ok  : Boolean;
  end;

  { The per-routine state a local-caller check swaps out while it reads the caller. }
  TBnSaved = record
    Scopes  : TObjectList<TDictionary<string, TDeclInfo>>;
    LenAlias: TDictionary<string, string>;
    LenCache: TDictionary<string, TSym>;
    WriteCnt: TDictionary<string, Integer>;
    CurProc : TTSNode;
  end;

  { One A[idx] under analysis by index-possibly-out-of-range: what is being indexed, by what, the
    writes of the index in the routine, and the sides proven so far. }
  TIdxCtx = record
    Access : TTSNode;
    Idx    : string;            { lower-cased index name }
    Arr    : string;            { lower-cased array name }
    Info   : TDeclInfo;         { the array's shape }
    IdxInfo: TDeclInfo;         { the index's declaration (IsParam) }
    Writes : TList<TTSNode>;    { not owned }
    Lo     : Boolean;           { lower side proven }
    Hi     : Boolean;           { upper side proven }
    Silent : Boolean;           { a v1 cut applies: no finding }
    Loop   : TTSNode;           { innermost loop around the access }
    FgnText: string;            { another collection's bound guarding the upper side, unproven }
    FgnSym : TSym;              { that guard as idx <= FgnSym }
    FgnNode: TTSNode;           { the for loop ending at that bound (report site with no write) }
  end;

  { One walk over one parsed file. Private to this unit. }
  TBnRun = class
  strict private
    FSrc     : TBytes;
    FFile    : string;
    FFindings: TList<TLintFinding>;
    FGlobals : TDictionary<string, TDeclInfo>;
    FScopes  : TObjectList<TDictionary<string, TDeclInfo>>;
    FConsts  : TDictionary<string, Integer>;      { file-level integer consts with a literal value }
    FConstBad: TDictionary<string, Boolean>;      { const names declared twice with different values }
    FAliases : TDictionary<string, TDeclInfo>;    { file-level type aliases of a string or array[lo..hi] }
    FAliasBad: TDictionary<string, Boolean>;
    FExClass : string;                            { the exception class the index guard fix raises }
    FLenAlias: TDictionary<string, string>;       { per routine: local written once as Length/High/Low(A) -> 'fn:a' }
    FRoot    : TTSNode;
    FCurProc : TTSNode;                           { the routine index-possibly-out-of-range is reading }
    FTraceDepth: Integer;                         { 1 while a local caller is read: no further tracing }
    FLenCache: TDictionary<string, TSym>;         { per routine: array -> its length }
    FWriteCnt: TDictionary<string, Integer>;      { per routine: name -> number of writes }
    FFileLen : TDictionary<string, TSym>;         { file-wide length of a non-local array }
    FMinLen  : TDictionary<string, Integer>;      { routine start + param array -> least length its local callers pass }
    FCallSites: TObjectDictionary<string, TList<TTSNode>>; { bare routine name -> its call nodes }
    FCallOk  : TDictionary<string, Boolean>;      { bare routine name -> every use of it is a local call }
    FStore   : ISymbolStore;                      { optional index: bounds of another unit's const / var array (1.52 BK-RULEFP) }
    FStoreArr: TDictionary<string, TDeclInfo>;    { name -> that array's shape from the index (dkOther: none / ambiguous) }
    FAccess  : TTSNode;                           { the access under analysis: dominance of a Length guard }
    FStableFrom: Cardinal;                        { 1.52 IDXRANGE3: window [From, To] in which a name / field / Length nobody changes reads as one value (0: none) }
    FStableTo  : Cardinal;
    FBoundVisit: TDictionary<string, Integer>;    { BoundAt: name -> path offset when it was entered (cycle check) }
    FBoundOff  : Integer;                         { BoundAt: sum of the +/- k offsets along the current path }
    FBoundMemo : TDictionary<string, string>;     { BoundAt: per top-level query, results that hit no chain back ('' unknown) }
    FBoundCycles: Integer;                        { BoundAt: chains back taken so far (a result after one is not memoised) }
    FCalleeLen : TDictionary<string, string>;     { routine name -> 'index:cnt|len' of the param its Result is sized by ('' none) }
    function Txt(const N: TTSNode): string;
    function IsTrivia(const N: TTSNode): Boolean;
    procedure EmitAt(const ANode: TTSNode; const ARuleId, AMessage, ASeverity: string);
    function BareIdent(const N: TTSNode): string;
    function OperatorType(const N: TTSNode): string;
    function IsTypeLikeName(const AName: string): Boolean;
    function ClassifyType(const ATypeText: string; out ALo, AHi: Integer): TDeclKind;
    procedure NamesBefore(const ADecl, AType: TTSNode; AList: TList<string>);
    procedure AddDecl(ADict: TDictionary<string, TDeclInfo>; const AName: string; const AInfo: TDeclInfo; AMergeAmbig: Boolean);
    procedure RecordDecl(const ADecl: TTSNode; ADict: TDictionary<string, TDeclInfo>; AMergeAmbig: Boolean);
    procedure CollectGlobals(const N: TTSNode);
    procedure CollectNamed(const N: TTSNode);
    function ConstValue(const AName: string; out AValue: Integer): Boolean;
    function BoundValue(const AToken: string; out AValue: Integer): Boolean;
    function EvalIndex(const N: TTSNode; out AValue: Integer): Boolean;
    function BuildScope(const AProc: TTSNode): TDictionary<string, TDeclInfo>;
    function Lookup(const AName: string; out AInfo: TDeclInfo): Boolean;
    procedure CheckSubscript(const N: TTSNode);
    function IsAddrOfLocal(const N: TTSNode; ALocals: TDictionary<string, TDeclInfo>): Boolean;
    function IsPointerCastOfLocal(const N: TTSNode; ALocals: TDictionary<string, TDeclInfo>): Boolean;
    function AddressTarget(const N: TTSNode; ALocals: TDictionary<string, TDeclInfo>): Boolean;
    procedure ScanReturns(const N: TTSNode; ALocals: TDictionary<string, TDeclInfo>);
    procedure CheckProc(const AProc: TTSNode);
    procedure CollectDerefs(const N: TTSNode; ASet: TDictionary<string, Boolean>);
    procedure CollectNilChecks(const N: TTSNode; ASet: TDictionary<string, TTSNode>);
    procedure CollectAssigned(const N: TTSNode; ASet: TDictionary<string, Boolean>);
    procedure CheckNilBlock(const ABlock: TTSNode);
    procedure FlushCopyRun(ARows: TList<TCopyRow>);
    function IsMemberCopy(const N: TTSNode): Boolean;
    procedure CheckCopyBlock(const ABlock: TTSNode);
    function IsBoundedArray(const AName: string; out AInfo: TDeclInfo): Boolean;
    function IsArrayFn(const N: TTSNode; const AFn, AArr: string): Boolean;
    function IsLenMinus(const N: TTSNode; const AArr: string): Boolean;
    function ProvesLower(const E: TTSNode; AStrict: Boolean; const AArr: string; const AInfo: TDeclInfo): Boolean;
    function ProvesUpper(const E: TTSNode; AStrict: Boolean; const AArr: string; const AInfo: TDeclInfo): Boolean;
    procedure CompareFacts(var ACtx: TIdxCtx; const E: TTSNode; ANegate: Boolean);
    procedure CondFacts(var ACtx: TIdxCtx; const C: TTSNode; ANegate: Boolean);
    function IsLeaveStmt(const N: TTSNode): Boolean;
    function IsGrowOf(const N: TTSNode; const AArr: string): Boolean;
    procedure CollectLenAliases(const ABody: TTSNode);
    function AssignTarget(const AAssign: TTSNode): string;
    function Mentions(const N: TTSNode; const AIdent: string): Boolean;
    procedure CollectIdxWrites(const N: TTSNode; const AIdx: string; AList: TList<TTSNode>);
    function WriteKeeps(const ACtx: TIdxCtx; const W: TTSNode; ALower: Boolean): Boolean;
    function CaseOn(const ACase: TTSNode; const AIdx: string): Boolean;
    function HoldsSince(const ACtx: TIdxCtx; AFrom: Cardinal): Boolean;
    function LeavesBefore(const W, AAccess: TTSNode; AFrom: Cardinal; ALoopLeave: Boolean): Boolean;
    function ExclusiveBranches(const W, AAccess: TTSNode): Boolean;
    function FixAnchorLine(const AAccess: TTSNode): Integer;
    procedure ProvenanceSides(var ACtx: TIdxCtx);
    procedure ApplyBranch(var ACtx: TIdxCtx; const C, P: TTSNode);
    procedure ApplyForBounds(var ACtx: TIdxCtx; const P: TTSNode);
    procedure ApplyLoop(var ACtx: TIdxCtx; const C, P: TTSNode);
    procedure ApplySiblings(var ACtx: TIdxCtx; const C: TTSNode);
    procedure ClimbGuards(var ACtx: TIdxCtx);
    function InScopes(const AName: string): Boolean;
    function WritesOf(const AName: string): Integer;
    function SymOf(const E: TTSNode): TSym;
    function LenSymOf(const AArr: string): TSym;
    function FileLenOf(const AArr: string): TSym;
    function HighSym(const AArr: string; const AInfo: TDeclInfo): TSym;
    function MinLenOf(const AArr: string): Integer;
    function UpperWithin(const U: TSym; const AArr: string; const AInfo: TDeclInfo): Boolean;
    function ForeignBound(const E: TTSNode; const AArr: string): Boolean;
    procedure NoteForeign(var ACtx: TIdxCtx; const E: TTSNode; AStrict: Boolean; const AFor: TTSNode);
    function CondUpperSym(const C: TTSNode; const AIdx: string; ANegate: Boolean; out AU: TSym): Boolean;
    function StepWrite(const W: TTSNode; const AIdx: string): Boolean;
    function ExitCap(const ACtx: TIdxCtx; const W: TTSNode; out AU: TSym; out AInThen: Boolean): Boolean;
    function WriteUpper(const W: TTSNode; out AU: TSym): Boolean;
    function UpperSides(const ACtx: TIdxCtx; const AReach: TList<TTSNode>): Boolean;
    function OnePastWhile(const ACtx: TIdxCtx): Boolean;
    function CountInvariant(const ACtx: TIdxCtx): Boolean;
    { 1.52 BK-RULEFP: the FP classes of the IDXRANGE2 12-sample }
    function KeepsSince(const ACtx: TIdxCtx; AFrom: Cardinal; ALower: Boolean): Boolean;
    procedure ApplyKeptGuard(var ACtx: TIdxCtx; const ACond: TTSNode; AFrom: Cardinal);
    function IsClampOf(const AThen: TTSNode; const ACtx: TIdxCtx): Boolean;
    procedure SetFacts(var ACtx: TIdxCtx; const E: TTSNode);
    function SetRange(const S: TTSNode; out AMin, AMax: Integer): Boolean;
    function IsUnwrittenParam(const E: TTSNode): Boolean;
    function RoutineConst(const AName: string; out AValue: Integer): Boolean;
    function StoreArray(const AName: string; out AInfo: TDeclInfo): Boolean;
    function UpperConstOf(const E: TTSNode; ADepth: Integer; out AValue: Integer): Boolean;
    function LowerConstOf(const E: TTSNode; ADepth: Integer; out AValue: Integer): Boolean;
    function GuardMinLen(const AArr: string): Integer;
    function IsSizeChangeOf(const N: TTSNode; const AArr: string): Boolean;
    function DomSetLength(const AArr: string): TTSNode;
    function SizeChangedIn(const AArr: string; AFrom, ATo: Cardinal): Boolean;
    function DomLenOf(const AArr: string): TSym;
    function IsStepUp(const W: TTSNode; const AX: string): Boolean;
    function LocalLeast(const AX: string; ADepth: Integer; out AValue: Integer): Boolean;
    function IsLookupWrite(const W: TTSNode; out AText: string): Boolean;
    function StmtDominates(const W, AAt: TTSNode): Boolean;
    function LoopsAround(const N: TTSNode; AList: TList<TTSNode>): Integer;
    function ForOfCounter(const AX: string; const AAt: TTSNode): TTSNode;
    function IsOwnLocal(const AX: string): Boolean;
    function TouchedIn(const AX: string; AFrom, ATo: Cardinal; AWhole: Boolean = False): Boolean;
    function CondBound(const C: TTSNode; const AX: string; ANegate, AUpper: Boolean; out AV: Integer): Boolean;
    function LoopTrips(const ALoop: TTSNode; ADepth: Integer; out AT: Integer): Boolean;
    function FloatBound(const ACall, AAt: TTSNode; AUpper: Boolean; out AV: Integer): Boolean;
    function EvalBound(const E, AAt: TTSNode; AUpper: Boolean; ADepth: Integer; out AV: Integer): Boolean;
    function BoundAt(const AX: string; const AAt: TTSNode; AUpper: Boolean; ADepth: Integer; out AV: Integer): Boolean;
    function EqualLenGuard(const A, B: string): Boolean;
    function TryBodySetLength(const ATry: TTSNode; const AArr: string): TTSNode;
    function DeclaresLocal(const AProc: TTSNode; const AX: string): Boolean;
    function DottedPath(const N: TTSNode): string;
    function CallName(const ACall: TTSNode): string;
    function NameEscapes(const N: TTSNode; const AX: string; AWithCalls: Boolean): Boolean;
    function PassesByRef(const ACall: TTSNode; const AX: string): Boolean;
    function TouchedPath(const APath: string; AFrom, ATo: Cardinal): Boolean;
    function UpperAtSite(const ASite, AE: TTSNode; const AArr: string; AOff: Integer): Boolean;
    function LocalBoundedBy(const E: TTSNode; AStrict: Boolean; const ACtx: TIdxCtx): Boolean;
    procedure LeaveGuardsBefore(const AAt: TTSNode; AList: TList<TTSNode>);
    function ForCounterOverwritten(const AFor: TTSNode; AEvents: TList<TTSNode>): Boolean;
    function CalleeSizes(const ACall: TTSNode): string;
    function CalleeArgLen(const ACall: TTSNode; ATarget: string): TSym;
    function OuterLenOf(const AArr: string): TSym;
    function CalleeResultLen(const ACall: TTSNode): TSym;
    function SelfBoundedFor(const ACtx: TIdxCtx; const F: TTSNode; C0, SLo: Integer): Boolean;
    procedure BuildCallIndex;
    function ParamNames(const AProc: TTSNode): TArray<string>;
    function LocalCalls(const AProc: TTSNode; out ASites: TList<TTSNode>): Boolean;
    function EnclosingProc(const N: TTSNode): TTSNode;
    procedure EnterRoutine(const AProc: TTSNode; out ASaved: TBnSaved);
    procedure LeaveRoutine(const ASaved: TBnSaved);
    function TranslateSym(const S: TSym; const ACallee, AArgs: TTSNode): TSym;
    function ProveIndexAt(const ASite, AIdxExpr: TTSNode; const AArr: string): Boolean;
    function CallersProveIndex(const AProc: TTSNode; const ACtx: TIdxCtx): Boolean;
    function CallersProveUpper(const AProc: TTSNode; const ACtx: TIdxCtx): Boolean;
    procedure EmitIndexFinding(const AProc: TTSNode; const ACtx: TIdxCtx; AReported: TDictionary<string, Boolean>);
    procedure CheckIndexAccess(const AProc: TTSNode; var ACtx: TIdxCtx; AReported: TDictionary<string, Boolean>);
    procedure CheckIndexFlow(const AProc: TTSNode);
    procedure Visit(const N: TTSNode);
  public
    constructor Create(const AFile: string; const ASrc: TBytes; const AExClass: string; const AStore: ISymbolStore);
    destructor Destroy; override;
    function Run(const ARoot: TTSNode): TArray<TLintFinding>;
  end;

constructor TBnRun.Create(const AFile: string; const ASrc: TBytes; const AExClass: string; const AStore: ISymbolStore);
begin
  inherited Create;
  FFile:= AFile;
  FStore:= AStore;
  FStoreArr:= TDictionary<string, TDeclInfo>.Create;
  FSrc := ASrc;
  FExClass:= if AExClass <> '' then AExClass else DEFAULT_INDEX_GUARD_EXCEPTION;
  FLenAlias:= TDictionary<string, string>.Create;
  FLenCache:= TDictionary<string, TSym>.Create;
  FWriteCnt:= TDictionary<string, Integer>.Create;
  FFileLen := TDictionary<string, TSym>.Create;
  FMinLen  := TDictionary<string, Integer>.Create;
  FFindings:= TList<TLintFinding>.Create;
  FGlobals := TDictionary<string, TDeclInfo>.Create;
  FScopes  := TObjectList<TDictionary<string, TDeclInfo>>.Create(True);
  FConsts  := TDictionary<string, Integer>.Create;
  FConstBad:= TDictionary<string, Boolean>.Create;
  FAliases := TDictionary<string, TDeclInfo>.Create;
  FAliasBad:= TDictionary<string, Boolean>.Create;
  FBoundVisit:= TDictionary<string, Integer>.Create;
  FBoundMemo := TDictionary<string, string>.Create;
  FCalleeLen := TDictionary<string, string>.Create;
end;

destructor TBnRun.Destroy;
begin
  FCalleeLen.Free;
  FBoundMemo.Free;
  FBoundVisit.Free;
  FStoreArr.Free;
  FCallOk.Free;
  FCallSites.Free;
  FMinLen.Free;
  FFileLen.Free;
  FWriteCnt.Free;
  FLenCache.Free;
  FLenAlias.Free;
  FAliasBad.Free;
  FAliases.Free;
  FConstBad.Free;
  FConsts.Free;
  FScopes.Free;
  FGlobals.Free;
  FFindings.Free;
  inherited Destroy;
end;

function TBnRun.Txt(const N: TTSNode): string;
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

function TBnRun.IsTrivia(const N: TTSNode): Boolean;
var
  T: string;
begin
  T:= N.NodeType;
  Result:= (T = 'comment') or (T = 'pp')
    or ((Length(T) > 1) and (T[1] = 'k') and CharInSet(T[2], ['A'..'Z']));
end;

procedure TBnRun.EmitAt(const ANode: TTSNode; const ARuleId, AMessage, ASeverity: string);
var
  P: TTSPoint;
  F: TLintFinding;
begin
  if FFindings.Count >= MAX_FINDINGS then Exit;
  P:= ANode.StartPoint;
  F:= Default(TLintFinding);
  F.RuleId   := ARuleId;
  F.Severity := ASeverity;
  F.Message  := AMessage;
  F.FilePath := FFile;
  F.StartLine:= Integer(P.Row) + 1;
  F.StartCol := TAstParseCache.CharCol(F.FilePath, P); { 1.52 BK-COLS2: character column }
  F.EndLine  := F.StartLine;
  F.EndCol   := F.StartCol + Length(Trim(Txt(ANode)));
  FFindings.Add(F);
end;

{ The lower-cased text of N when it is a bare identifier (parentheses peeled), else ''. }
function TBnRun.BareIdent(const N: TTSNode): string;
var
  C: TTSNode;
begin
  Result:= '';
  if N.IsNull then Exit;
  if N.NodeType = 'identifier' then Exit(LowerCase(Txt(N)));
  if (N.NodeType = 'exprParens') and (N.NamedChildCount = 1) then
  begin
    C:= N.NamedChild(0);
    if C.NodeType = 'identifier' then Result:= LowerCase(Txt(C));
  end;
end;

function TBnRun.OperatorType(const N: TTSNode): string;
var
  O: TTSNode;
begin
  Result:= '';
  O:= N.ChildByField('operator');
  if not O.IsNull then Result:= O.NodeType;
end;

{ `TFoo.Create` / `TFoo.ClassName`: the left side is a type (T + capital), not an object that could be nil. }
function TBnRun.IsTypeLikeName(const AName: string): Boolean;
begin
  Result:= (Length(AName) > 1) and (AName[1] = 'T') and CharInSet(AName[2], ['A'..'Z']);
end;

function TBnRun.ClassifyType(const ATypeText: string; out ALo, AHi: Integer): TDeclKind;
var
  T: string;
  M: TMatch;
  S: string;
  Alias: TDeclInfo;
begin
  ALo:= 0;
  AHi:= -1;
  Result:= dkOther;
  T:= LowerCase(Trim(ATypeText));
  for S in STRING_TYPES do
    if T = S then Exit(dkString);
  if FAliases.TryGetValue(T, Alias) and (not FAliasBad.ContainsKey(T)) then
  begin
    ALo:= Alias.Lo;
    AHi:= Alias.Hi;
    Exit(Alias.Kind);
  end;
  M:= TRegEx.Match(T, ARRAY_TYPE_PATTERN);
  if M.Success and BoundValue(M.Groups[1].Value, ALo) and BoundValue(M.Groups[2].Value, AHi) then
    Result:= dkArray
  else if TRegEx.IsMatch(T, DYN_ARRAY_TYPE_PATTERN) then
  begin
    ALo:= 0;
    AHi:= -1;
    Result:= dkDynArray;
  end
  else
  begin
    ALo:= 0;
    AHi:= -1;
  end;
end;

{ An array bound token: a decimal literal, or a file-level integer const (a named bound). }
function TBnRun.BoundValue(const AToken: string; out AValue: Integer): Boolean;
var
  Neg: Boolean;
  Tok: string;
begin
  Neg:= (AToken <> '') and (AToken[1] = '-');
  Tok:= AToken;
  if Neg then Delete(Tok, 1, 1);
  Result:= TryStrToInt(Tok, AValue);
  if (not Result) and FConsts.TryGetValue(Tok, AValue) and (not FConstBad.ContainsKey(Tok)) then Result:= True;
  if Result and Neg then AValue:= -AValue;
end;

{ File-level consts with an integer literal value and type aliases of string / array[lo..hi]: the
  names constant-index-out-of-range can resolve. A name declared twice with a different meaning is
  recorded as bad and stays silent. Runs before CollectGlobals so the shapes are known. }
procedure TBnRun.CollectNamed(const N: TTSNode);
var
  T, Nm    : string;
  I, V     : Integer;
  Val, Typ : TTSNode;
  Info, Old: TDeclInfo;
begin
  if N.IsNull then Exit;
  T:= N.NodeType;
  if (T = 'defProc') or (T = 'lambda') then Exit;
  if T = 'declConst' then
  begin
    Val:= N.ChildByField('defaultValue');
    Nm := LowerCase(Txt(N.ChildByField('name')));
    if (not Val.IsNull) and (Nm <> '') and (Val.NamedChildCount >= 1) and (Val.NamedChild(Val.NamedChildCount - 1).NodeType = 'literalNumber') then
    begin
      if TryStrToInt(Txt(Val.NamedChild(Val.NamedChildCount - 1)), V) and ((not FConsts.TryGetValue(Nm, I)) or (I = V)) then FConsts.AddOrSetValue(Nm, V)
      else FConstBad.AddOrSetValue(Nm, True);
    end
    else if Nm <> '' then
      FConstBad.AddOrSetValue(Nm, True);
    Exit;
  end;
  if T = 'declType' then
  begin
    Typ:= N.ChildByField('type');
    Nm := LowerCase(Txt(N.ChildByField('name')));
    if (not Typ.IsNull) and (Nm <> '') then
    begin
      Info:= Default(TDeclInfo);
      Info.Kind:= ClassifyType(Txt(Typ), Info.Lo, Info.Hi);
      if Info.Kind = dkOther then FAliasBad.AddOrSetValue(Nm, True)
      else if FAliases.TryGetValue(Nm, Old) and ((Old.Kind <> Info.Kind) or (Old.Lo <> Info.Lo) or (Old.Hi <> Info.Hi)) then
        FAliasBad.AddOrSetValue(Nm, True)
      else FAliases.AddOrSetValue(Nm, Info);
    end
    else if Nm <> '' then
      FAliasBad.AddOrSetValue(Nm, True);
    Exit;
  end;
  for I:= 0 to N.ChildCount - 1 do CollectNamed(N.Child(I));
end;

{ A file-level const by name; a routine-local declaration of the same name shadows it. }
function TBnRun.ConstValue(const AName: string; out AValue: Integer): Boolean;
var
  I: Integer;
begin
  Result:= False;
  AValue:= 0;
  if RoutineConst(AName, AValue) then Exit(True);  { 1.52 BK-RULEFP: the routine's own const section }
  for I:= 0 to FScopes.Count - 1 do
    if FScopes[I].ContainsKey(AName) then Exit;
  Result:= FConsts.TryGetValue(AName, AValue) and (not FConstBad.ContainsKey(AName));
end;

{ The integer value of a constant index expression: a literal, a file-level const, unary minus,
  + / - of those, parentheses. False for anything else (a variable, a call). }
function TBnRun.EvalIndex(const N: TTSNode; out AValue: Integer): Boolean;  // dl:ok too-many-exit-points@f533 -- REVIEWED 2026-11-14 v151 INT: guard clauses per syntax shape; each early exit is a classification
var
  A, B: Integer;
  Op  : string;
begin
  Result:= False;
  AValue:= 0;
  if N.IsNull then Exit;
  if N.NodeType = 'literalNumber' then
    Exit(TRegEx.IsMatch(Txt(N), '^-?\d{1,9}$') and TryStrToInt(Txt(N), AValue));
  if N.NodeType = 'identifier' then
    Exit(ConstValue(LowerCase(Txt(N)), AValue));
  if (N.NodeType = 'exprParens') and (N.NamedChildCount = 1) then
    Exit(EvalIndex(N.NamedChild(0), AValue));
  if N.NodeType = 'exprUnary' then
  begin
    if (OperatorType(N) <> 'kSub') or (not EvalIndex(N.ChildByField('operand'), A)) then Exit;
    AValue:= -A;
    Exit(True);
  end;
  if N.NodeType = 'exprBinary' then
  begin
    Op:= OperatorType(N);
    if ((Op <> 'kAdd') and (Op <> 'kSub')) or (not EvalIndex(N.ChildByField('lhs'), A))
       or (not EvalIndex(N.ChildByField('rhs'), B)) then Exit;
    if Op = 'kAdd' then AValue:= A + B else AValue:= A - B;  // dl:ok ifthen-to-if-expression@191a -- REVIEWED 2026-11-14 v151 INT: classic if/else kept in a lane unit written before the ternary sweep
    Result:= True;
  end;
end;

{ The identifiers that name a declaration: its children before the type node. }
procedure TBnRun.NamesBefore(const ADecl, AType: TTSNode; AList: TList<string>);
var
  I: Integer;
  C: TTSNode;
  Limit: Cardinal;
begin
  if AType.IsNull then Exit;
  Limit:= AType.StartByte;
  for I:= 0 to ADecl.ChildCount - 1 do
  begin
    C:= ADecl.Child(I);
    if C.StartByte >= Limit then Break;
    if C.NodeType = 'identifier' then AList.Add(LowerCase(Txt(C)));
  end;
end;

procedure TBnRun.AddDecl(ADict: TDictionary<string, TDeclInfo>; const AName: string; const AInfo: TDeclInfo; AMergeAmbig: Boolean);
var
  Old: TDeclInfo;
  New: TDeclInfo;
begin
  New:= AInfo;
  if AMergeAmbig and ADict.TryGetValue(AName, Old) then
  begin
    if Old.Ambig or (Old.Kind <> New.Kind) or (Old.Lo <> New.Lo) or (Old.Hi <> New.Hi) then
    begin
      New.Kind := dkOther;
      New.Ambig:= True;
    end;
  end;
  ADict.AddOrSetValue(AName, New);
end;

procedure TBnRun.RecordDecl(const ADecl: TTSNode; ADict: TDictionary<string, TDeclInfo>; AMergeAmbig: Boolean);
var
  TypeN: TTSNode;
  Names: TList<string>;
  Info : TDeclInfo;
  S    : string;
  I    : Integer;
begin
  TypeN:= ADecl.ChildByField('type');
  Info:= Default(TDeclInfo);
  Info.Kind:= dkOther;
  if not TypeN.IsNull then Info.Kind:= ClassifyType(Txt(TypeN), Info.Lo, Info.Hi);
  if ADecl.NodeType = 'declArg' then
  begin
    Info.IsParam:= True;
    for I:= 0 to ADecl.ChildCount - 1 do
      if (ADecl.Child(I).NodeType = 'kVar') or (ADecl.Child(I).NodeType = 'kConst')
        or (ADecl.Child(I).NodeType = 'kOut') or (ADecl.Child(I).NodeType = 'kConstref') then
        Info.ByRef:= True;
  end;
  Names:= TList<string>.Create;
  try
    if TypeN.IsNull then
    begin
      TypeN:= ADecl.ChildByField('name');
      if not TypeN.IsNull then Names.Add(LowerCase(Txt(TypeN)));
    end
    else
      NamesBefore(ADecl, TypeN, Names);
    for S in Names do
      AddDecl(ADict, S, Info, AMergeAmbig);
  finally
    Names.Free;
  end;
end;

{ File-level view: every var / field / const declared OUTSIDE a routine. }
procedure TBnRun.CollectGlobals(const N: TTSNode);
var
  T: string;
  I: Integer;
begin
  if N.IsNull then Exit;
  T:= N.NodeType;
  if (T = 'defProc') or (T = 'lambda') then Exit;
  if (T = 'declVar') or (T = 'declField') or (T = 'declConst') then
  begin
    RecordDecl(N, FGlobals, True);
    Exit;
  end;
  for I:= 0 to N.ChildCount - 1 do CollectGlobals(N.Child(I));
end;

{ The locals and parameters of one routine. }
function TBnRun.BuildScope(const AProc: TTSNode): TDictionary<string, TDeclInfo>;

  procedure Walk(const N: TTSNode);
  var
    T: string;
    I: Integer;
  begin
    if N.IsNull then Exit;
    T:= N.NodeType;
    if (T = 'declVar') or (T = 'declConst') or (T = 'declArg') then
    begin
      RecordDecl(N, Result, False);
      Exit;
    end;
    if (T = 'defProc') or (T = 'lambda') then Exit;
    for I:= 0 to N.ChildCount - 1 do Walk(N.Child(I));
  end;

  { Inline `var X := ...` / `const X = ...` / `for var X ...`: the type is inferred, so the name only SHADOWS an outer declaration. }
  procedure WalkInline(const N: TTSNode);
  var
    T: string;
    I: Integer;
    Info: TDeclInfo;
  begin
    if N.IsNull then Exit;
    T:= N.NodeType;
    if (T = 'defProc') or (T = 'lambda') then Exit;
    if (T = 'varDef') or (T = 'varAssignDef') or (T = 'constInline') then
    begin
      Info:= Default(TDeclInfo);
      for I:= 0 to N.ChildCount - 1 do
        if N.Child(I).NodeType = 'identifier' then Result.AddOrSetValue(LowerCase(Txt(N.Child(I))), Info);
    end;
    for I:= 0 to N.ChildCount - 1 do WalkInline(N.Child(I));
  end;
var
  I: Integer;
  T: string;
begin
  Result:= TDictionary<string, TDeclInfo>.Create;
  Walk(AProc.ChildByField('header'));
  WalkInline(AProc.ChildByField('body'));
  for I:= 0 to AProc.ChildCount - 1 do
  begin
    T:= AProc.Child(I).NodeType;
    if (T = 'declVars') or (T = 'declConsts') then Walk(AProc.Child(I));
  end;
end;

function TBnRun.Lookup(const AName: string; out AInfo: TDeclInfo): Boolean;
var
  I: Integer;
begin
  for I:= FScopes.Count - 1 downto 0 do
    if FScopes[I].TryGetValue(AName, AInfo) then Exit(True);
  Result:= FGlobals.TryGetValue(AName, AInfo);
end;

{ ---- constant-index-out-of-range ---------------------------------------- }

procedure TBnRun.CheckSubscript(const N: TTSNode);
var
  Ent, Args, Arg: TTSNode;
  Name: string;
  Info: TDeclInfo;
  Idx: Integer;
begin
  Ent:= N.ChildByField('entity');
  Args:= N.ChildByField('args');
  if Ent.IsNull or Args.IsNull or (Ent.NodeType <> 'identifier') then Exit;
  if Args.NamedChildCount <> 1 then Exit;
  Arg:= Args.NamedChild(0);
  if Arg.IsNull or (not EvalIndex(Arg, Idx)) then Exit;
  Name:= LowerCase(Txt(Ent));
  if not Lookup(Name, Info) then Exit;
  case Info.Kind of
    dkArray:
      if (Idx < Info.Lo) or (Idx > Info.Hi) then
        EmitAt(N, RULE_CONST_INDEX,
          Format('Index %d is outside the declared bounds %d..%d of %s -- range error or memory overrun',
            [Idx, Info.Lo, Info.Hi, Txt(Ent)]), 'warning');
    dkString:
      if Idx = 0 then
        EmitAt(N, RULE_CONST_INDEX,
          Format('Strings are 1-based: %s[0] is out of range', [Txt(Ent)]), 'warning');
  end;
end;

{ ---- address-of-local-returned ------------------------------------------ }

{ True when N is `@L` of a routine-owned, non-reference location. }
function TBnRun.IsAddrOfLocal(const N: TTSNode; ALocals: TDictionary<string, TDeclInfo>): Boolean;
var
  Name: string;
  Info: TDeclInfo;
begin
  Name:= BareIdent(N.ChildByField('operand'));
  Result:= (Name <> '') and ALocals.TryGetValue(Name, Info) and not Info.ByRef;
end;

{ True when N is `PChar(L)` / `Pointer(L)` ... of a string or static-array routine-owned local. }
function TBnRun.IsPointerCastOfLocal(const N: TTSNode; ALocals: TDictionary<string, TDeclInfo>): Boolean;
var
  Args: TTSNode;
  Name, Cast, C: string;
  Info: TDeclInfo;
begin
  Result:= False;
  Args:= N.ChildByField('args');
  if not Args.IsNull and (Args.NamedChildCount = 1) then
  begin
    Cast:= BareIdent(N.ChildByField('entity'));
    Name:= BareIdent(Args.NamedChild(0));
    if (Cast <> '') and (Name <> '') then
      for C in CAST_NAMES do
        if C = Cast then
          Result:= ALocals.TryGetValue(Name, Info) and not Info.ByRef and (Info.Kind in [dkString, dkArray]);
  end;
end;

{ True when N is `@L` / `PChar(L)` ... of a routine-owned storage location. }
function TBnRun.AddressTarget(const N: TTSNode; ALocals: TDictionary<string, TDeclInfo>): Boolean;
begin
  Result:= False;
  if N.IsNull then Exit;
  if (N.NodeType = 'exprParens') and (N.NamedChildCount = 1) then
    Result:= AddressTarget(N.NamedChild(0), ALocals)
  else if (N.NodeType = 'exprUnary') and (OperatorType(N) = 'kAt') then
    Result:= IsAddrOfLocal(N, ALocals)
  else if N.NodeType = 'exprCall' then
    Result:= IsPointerCastOfLocal(N, ALocals);
end;
procedure TBnRun.ScanReturns(const N: TTSNode; ALocals: TDictionary<string, TDeclInfo>);
var
  T, Callee: string;
  I: Integer;
  Lhs, Args, Ent: TTSNode;
begin
  if N.IsNull then Exit;
  T:= N.NodeType;
  if (T = 'defProc') or (T = 'lambda') then Exit;
  if T = 'assignment' then
  begin
    Lhs:= N.ChildByField('lhs');
    if (BareIdent(Lhs) = 'result') and AddressTarget(N.ChildByField('rhs'), ALocals) then
      EmitAt(N, RULE_ADDR_LOCAL,
        'Address of a local variable or by-value parameter is returned -- it dangles once the routine exits', 'warning');
  end
  else if T = 'exprCall' then
  begin
    Ent:= N.ChildByField('entity');
    Args:= N.ChildByField('args');
    Callee:= BareIdent(Ent);
    if (Callee = 'exit') and not Args.IsNull and (Args.NamedChildCount = 1)
      and AddressTarget(Args.NamedChild(0), ALocals) then
      EmitAt(N, RULE_ADDR_LOCAL,
        'Address of a local variable or by-value parameter is returned -- it dangles once the routine exits', 'warning');
  end;
  for I:= 0 to N.ChildCount - 1 do ScanReturns(N.Child(I), ALocals);
end;

procedure TBnRun.CheckProc(const AProc: TTSNode);
var
  Locals: TDictionary<string, TDeclInfo>;
begin
  { Only a function can return an address: its header carries a return type. }
  if AProc.ChildByField('header').ChildByField('type').IsNull then Exit;
  Locals:= FScopes[FScopes.Count - 1];
  ScanReturns(AProc.ChildByField('body'), Locals);
end;

{ ---- nil-check-after-dereference ---------------------------------------- }

procedure TBnRun.CollectDerefs(const N: TTSNode; ASet: TDictionary<string, Boolean>);
var
  T, Name, RawName, Member, R: string;
  I: Integer;
  Skip: Boolean;
begin
  if N.IsNull then Exit;
  T:= N.NodeType;
  if (T = 'lambda') or (T = 'defProc') then Exit;
  Name:= '';
  if T = 'exprDot' then
  begin
    Name:= BareIdent(N.ChildByField('lhs'));
    RawName:= Txt(N.ChildByField('lhs'));
    Member:= LowerCase(Txt(N.ChildByField('rhs')));
    Skip:= False;
    for R in RELEASE_MEMBERS do
      if R = Member then Skip:= True;
    if Skip then Name:= '';
  end
  else if T = 'exprSubscript' then
  begin
    Name:= BareIdent(N.ChildByField('entity'));
    RawName:= Txt(N.ChildByField('entity'));
  end
  else if (T = 'exprUnary') and (OperatorType(N) = 'kHat') then
  begin
    Name:= BareIdent(N.ChildByField('operand'));
    RawName:= Txt(N.ChildByField('operand'));
  end;
  if (Name <> '') and (Name <> 'self') and (Name <> 'inherited') and not IsTypeLikeName(RawName) then
    ASet.AddOrSetValue(Name, True);
  for I:= 0 to N.ChildCount - 1 do CollectDerefs(N.Child(I), ASet);
end;

procedure TBnRun.CollectNilChecks(const N: TTSNode; ASet: TDictionary<string, TTSNode>);
var
  T, Name: string;
  I: Integer;
  L, R, Args: TTSNode;
begin
  if N.IsNull then Exit;
  T:= N.NodeType;
  if (T = 'lambda') or (T = 'defProc') then Exit;
  if T = 'exprCall' then
  begin
    if SameText(BareIdent(N.ChildByField('entity')), 'assigned') then
    begin
      Args:= N.ChildByField('args');
      if not Args.IsNull and (Args.NamedChildCount = 1) then
      begin
        Name:= BareIdent(Args.NamedChild(0));
        if Name <> '' then ASet.AddOrSetValue(Name, N);
      end;
    end;
  end
  else if (T = 'exprBinary') and ((OperatorType(N) = 'kEq') or (OperatorType(N) = 'kNeq')) then
  begin
    L:= N.ChildByField('lhs');
    R:= N.ChildByField('rhs');
    if (R.NodeType = 'kNil') and (BareIdent(L) <> '') then ASet.AddOrSetValue(BareIdent(L), N)
    else if (L.NodeType = 'kNil') and (BareIdent(R) <> '') then ASet.AddOrSetValue(BareIdent(R), N);
  end;
  for I:= 0 to N.ChildCount - 1 do CollectNilChecks(N.Child(I), ASet);
end;

{ Identifiers assigned anywhere in N (`X := ...`) or passed to FreeAndNil. }
procedure TBnRun.CollectAssigned(const N: TTSNode; ASet: TDictionary<string, Boolean>);
var
  T, Name: string;
  I: Integer;
  Args: TTSNode;
begin
  if N.IsNull then Exit;
  T:= N.NodeType;
  if (T = 'lambda') or (T = 'defProc') then Exit;
  if T = 'assignment' then
  begin
    Name:= BareIdent(N.ChildByField('lhs'));
    if Name <> '' then ASet.AddOrSetValue(Name, True);
  end
  else if (T = 'exprCall') and SameText(BareIdent(N.ChildByField('entity')), 'freeandnil') then
  begin
    Args:= N.ChildByField('args');
    if not Args.IsNull and (Args.NamedChildCount = 1) then
    begin
      Name:= BareIdent(Args.NamedChild(0));
      if Name <> '' then ASet.AddOrSetValue(Name, True);
    end;
  end;
  for I:= 0 to N.ChildCount - 1 do CollectAssigned(N.Child(I), ASet);
end;

procedure TBnRun.CheckNilBlock(const ABlock: TTSNode);
var
  Derefd : TDictionary<string, Boolean>;
  Stmt   : TDictionary<string, Boolean>;
  Checks : TDictionary<string, TTSNode>;
  Assigns: TDictionary<string, Boolean>;
  I      : Integer;
  Child  : TTSNode;
  Pair   : TPair<string, TTSNode>;
  Key    : string;
  Simple : Boolean;
  Cond   : TTSNode;
begin
  Derefd := TDictionary<string, Boolean>.Create;
  Checks := TDictionary<string, TTSNode>.Create;
  Assigns:= TDictionary<string, Boolean>.Create;
  Stmt   := TDictionary<string, Boolean>.Create;
  try
    for I:= 0 to ABlock.NamedChildCount - 1 do
    begin
      Child:= ABlock.NamedChild(I);
      if Child.IsNull or IsTrivia(Child) then Continue;
      { 1. a nil test on an identifier dereferenced by an EARLIER statement }
      if (Derefd.Count > 0) and ((Child.NodeType = 'if') or (Child.NodeType = 'ifElse')) then
      begin
        Cond:= Child.ChildByField('condition');
        Checks.Clear;
        CollectNilChecks(Cond, Checks);
        for Pair in Checks do
          if Derefd.ContainsKey(Pair.Key) then
          begin
            EmitAt(Pair.Value, RULE_NIL_CHECK,
              Format('%s is dereferenced earlier in this block and only then tested against nil -- either the use is too early or the check is redundant',
                [Pair.Key]), 'warning');
            Break;
          end;
      end;
      { 2. what this statement dereferences (simple statements only) }
      Simple:= (Child.NodeType = 'statement') or (Child.NodeType = 'assignment');
      if Simple then
      begin
        Stmt.Clear;
        CollectDerefs(Child, Stmt);
        Checks.Clear;
        CollectNilChecks(Child, Checks);
        for Key in Stmt.Keys do
          if not Checks.ContainsKey(Key) then Derefd.AddOrSetValue(Key, True);
      end;
      { 3. an assignment anywhere in the statement forgets the dereference }
      Assigns.Clear;
      CollectAssigned(Child, Assigns);
      for Key in Assigns.Keys do Derefd.Remove(Key);
    end;
  finally
    Stmt.Free;
    Assigns.Free;
    Checks.Free;
    Derefd.Free;
  end;
end;

{ ---- copy-paste-assignment ---------------------------------------------- }

function IsAxisPair(const A, B: string): Boolean;
var
  I: Integer;
begin
  Result:= False;
  for I:= Low(AXIS_PAIRS) to High(AXIS_PAIRS) do
    if ((A = AXIS_PAIRS[I][0]) and (B = AXIS_PAIRS[I][1]))
      or ((A = AXIS_PAIRS[I][1]) and (B = AXIS_PAIRS[I][0])) then
      Exit(True);
end;

procedure TBnRun.FlushCopyRun(ARows: TList<TCopyRow>);
var
  I, J, OddIdx, OddCount: Integer;
  Hit: Boolean;
begin
  OddIdx:= -1;
  OddCount:= 0;
  if ARows.Count >= 2 then
  begin
    for I:= 0 to ARows.Count - 1 do
      if ARows[I].P <> ARows[I].Q then
      begin
        Inc(OddCount);
        OddIdx:= I;
      end;
    if OddCount = 1 then
    begin
      { EndLine := X.StartLine after StartLine := X.StartLine is a one-line span, not a typo. }
      Hit:= False;
      if not (ARows[OddIdx].P.StartsWith('end') and ARows[OddIdx].Q.StartsWith('start')) then
      for J:= 0 to ARows.Count - 1 do
        if (J <> OddIdx) and (ARows[J].Q = ARows[OddIdx].Q)
          and ((ARows.Count >= MIN_RUN_ROWS) or IsAxisPair(ARows[OddIdx].P, ARows[J].P)) then Hit:= True;
      if Hit then
        EmitAt(ARows[OddIdx].Node, RULE_COPY_PASTE,
          Format('Assignment copies "%s.%s" like the row above/below -- likely a copy-paste typo (expected %s.%s)',
            [ARows[OddIdx].RBase, ARows[OddIdx].Q, ARows[OddIdx].RBase, ARows[OddIdx].P]), 'hint');
    end;
  end;
  ARows.Clear;
end;

{ `A.p := B.q`: a plain assignment whose both sides are a member access with a simple member name. }
function TBnRun.IsMemberCopy(const N: TTSNode): Boolean;
var
  Lhs, Rhs: TTSNode;
begin
  Lhs:= N.ChildByField('lhs');
  Rhs:= N.ChildByField('rhs');
  Result:= (N.NodeType = 'assignment') and (OperatorType(N) = 'kAssign')
    and (Lhs.NodeType = 'exprDot') and (Rhs.NodeType = 'exprDot');
  if Result then
    Result:= (Lhs.ChildByField('rhs').NodeType = 'identifier') and (Rhs.ChildByField('rhs').NodeType = 'identifier');
end;

procedure TBnRun.CheckCopyBlock(const ABlock: TTSNode);
var
  Rows: TList<TCopyRow>;
  I   : Integer;
  Child, Lhs, Rhs: TTSNode;
  Row : TCopyRow;
begin
  Rows:= TList<TCopyRow>.Create;
  try
    for I:= 0 to ABlock.NamedChildCount - 1 do
    begin
      Child:= ABlock.NamedChild(I);
      if Child.IsNull or IsTrivia(Child) then Continue;
      Lhs:= Child.ChildByField('lhs');
      Rhs:= Child.ChildByField('rhs');
      if IsMemberCopy(Child) then
      begin
        Row.Node := Child;
        Row.LBase:= LowerCase(Txt(Lhs.ChildByField('lhs')));
        Row.P    := LowerCase(Txt(Lhs.ChildByField('rhs')));
        Row.RBase:= LowerCase(Txt(Rhs.ChildByField('lhs')));
        Row.Q    := LowerCase(Txt(Rhs.ChildByField('rhs')));
        if (Rows.Count > 0) and ((Rows[0].LBase <> Row.LBase) or (Rows[0].RBase <> Row.RBase)) then FlushCopyRun(Rows);
        Rows.Add(Row);
      end
      else
        FlushCopyRun(Rows);
    end;
    FlushCopyRun(Rows);
  finally
    Rows.Free;
  end;
end;

{ ---- index-possibly-out-of-range (1.52 IDXRANGE) ------------------------- }

{ N lies within ARoutine's text. }
function NodeWithin(const N, ARoutine: TTSNode): Boolean;
begin
  Result:= (not N.IsNull) and (not ARoutine.IsNull) and (N.StartByte >= ARoutine.StartByte) and (N.EndByte <= ARoutine.EndByte);
end;

function MkSym(const ABase: string; AOff: Integer): TSym;
begin
  Result.Base:= ABase;
  Result.Off := AOff;
  Result.Ok  := True;
end;

const
  LEN_BASE        = 'len:';     { TSym base of Length(A) }
  MAX_BOUND_DEPTH = 30;
  MAX_CALLER_DEPTH = 4;         { OuterLenOf: how many nested routines deep a call chain is followed }         { BoundAt / EvalBound: how far a chain of locals is followed }
  BOUND_NONE_HI   = -MaxInt;    { upper mode: no value reaches yet (the neutral element of max) }
  BOUND_NONE_LO   = MaxInt;     { lower mode: the neutral element of min }
  { calls that take an integer argument by value: passing the index to one is no write }
  BY_VALUE_FNS: array[0..33] of string = ('length', 'high', 'low', 'ord', 'chr', 'inttostr', 'format',
    'abs', 'min', 'max', 'succ', 'pred', 'odd', 'sqr', 'trunc', 'round', 'assigned', 'sizeof', 'inttohex', 'inrange',
    'sametext', 'samestr', 'comparetext', 'comparestr', 'uppercase', 'lowercase', 'trim', 'trimleft', 'trimright',
    'quotedstr', 'strtoint', 'strtointdef', 'containstext', 'containsstr');
  FLOAT_ROUNDERS: array[0..3] of string = ('floor', 'trunc', 'round', 'ceil');
  CONTROL_NODES: array[0..11] of string = ('if', 'ifElse', 'while', 'for', 'foreach', 'repeat', 'case',
    'caseCase', 'exceptionHandler', 'exprIf', 'exprBinary', 'lambda');

{ AFn takes its argument number APos (0-based) by value: a by-value RTL routine, or a by-value
  position of an RTL routine with a by-reference parameter. Anything else may write a bare variable. }
function ArgByValue(const AFn: string; APos: Integer): Boolean;
const
  BY_VALUE_AT: array[0..9] of string = ('readbuffer:1', 'writebuffer:1', 'move:2', 'fillchar:1,2', 'setlength:1',
    'getstring:1,2', 'delete:1,2', 'insert:0,2', 'copy:0,1,2', 'pos:0,1,2');
var
  S: string;
begin
  if IndexStr(AFn, BY_VALUE_FNS) >= 0 then Exit(True);
  for S in BY_VALUE_AT do
    if StartsText(AFn + ':', S) then Exit(ContainsStr(',' + Copy(S, Length(AFn) + 2, MaxInt) + ',', ',' + IntToStr(APos) + ','));
  Result:= False;
end;

function NeutralBound(AUpper: Boolean): Integer;
begin
  Result:= if AUpper then BOUND_NONE_HI else BOUND_NONE_LO;
end;

function IsNeutralBound(AV: Integer): Boolean;
begin
  Result:= (AV = BOUND_NONE_HI) or (AV = BOUND_NONE_LO);
end;

{ The join of two bounds of one value: the larger for an upper bound, the smaller for a lower one. }
function JoinBound(A, B: Integer; AUpper: Boolean): Integer;
begin
  Result:= if AUpper = (A > B) then A else B;
end;

{ The tighter of two bounds: the smaller upper bound, the larger lower one. }
function TightBound(A, B: Integer; AUpper: Boolean): Integer;
begin
  Result:= JoinBound(A, B, not AUpper);
end;

function ShiftBound(AV, AK: Integer): Integer;
begin
  Result:= if IsNeutralBound(AV) then AV else AV + AK;
end;

function IsLoopNode(const N: TTSNode): Boolean;
begin
  Result:= (N.NodeType = 'while') or (N.NodeType = 'repeat') or (N.NodeType = 'for') or (N.NodeType = 'foreach');
end;

function FloorOf(const AX: Double): Integer;
begin
  Result:= Trunc(AX);
  if Frac(AX) < 0 then Dec(Result);
end;

function CeilOf(const AX: Double): Integer;
begin
  Result:= -FloorOf(-AX);
end;

{ N with its parentheses peeled. }
function Peeled(const N: TTSNode): TTSNode;
begin
  Result:= N;
  while (not Result.IsNull) and (Result.NodeType = 'exprParens') and (Result.NamedChildCount = 1) do Result:= Result.NamedChild(0);
end;

{ The leftmost identifier of a designator (`a`, `a.b.c`, `a[i].b`), lower-cased; '' for anything else. }
function RootName(const ATxt: string): string;
var
  M: TMatch;
begin
  M:= TRegEx.Match(ATxt, '^\s*\(*\s*@?\s*([A-Za-z_]\w*)');
  Result:= if M.Success then LowerCase(M.Groups[1].Value) else '';
end;

{ The lower-cased text of N when it is a name or a dotted path of names (`a`, `Owner.List`), else ''. }
function TBnRun.DottedPath(const N: TTSNode): string;
var
  P: TTSNode;
begin
  Result:= '';
  P:= Peeled(N);
  if P.IsNull or ((P.NodeType <> 'identifier') and (P.NodeType <> 'exprDot')) then Exit;
  if TRegEx.IsMatch(Txt(P), '^\s*[A-Za-z_]\w*(\s*\.\s*[A-Za-z_]\w*)*\s*$') then
    Result:= LowerCase(StringReplace(Trim(Txt(P)), ' ', '', [rfReplaceAll]));
end;

{ The for loop AFor sits in a loop L, and an assignment of its counter (one of AEvents) that is a statement of L's own
  body comes after it with no Continue of L in between: the counter left undefined by AFor never
  reaches the next trip of L. }
function TBnRun.ForCounterOverwritten(const AFor: TTSNode; AEvents: TList<TTSNode>): Boolean;
var
  L, LBody, W, P, Q: TTSNode;
  Stack: TList<TTSNode>;
  I: Integer;
begin
  Result:= False;
  L:= AFor.Parent;
  while (not L.IsNull) and not IsLoopNode(L) and (L.NodeType <> 'defProc') do L:= L.Parent;
  if L.IsNull or (L.NodeType = 'defProc') then Exit;
  LBody:= L.ChildByField('body');
  if LBody.IsNull then Exit;
  for W in AEvents do
  begin
    if (W.NodeType <> 'assignment') or (W.StartByte < AFor.EndByte) or (W.EndByte > LBody.EndByte) then Continue;
    P:= W.Parent;
    while (not P.IsNull) and (P.NodeType <> 'block') and (P.NodeType <> 'statements') and (IndexStr(P.NodeType, CONTROL_NODES) < 0) do P:= P.Parent;
    if not (P = LBody) then Continue;  // dl:ok nonminimal-bool@4dfa -- REVIEWED 2026-11-18 IDXRANGE3: TTSNode declares Equal but no NotEqual; <> does not compile
    { no Continue of L between the for loop and W }
    Stack:= TList<TTSNode>.Create;
    try
      Stack.Add(LBody);
      while Stack.Count > 0 do
      begin
        Q:= Stack.Last;
        Stack.Delete(Stack.Count - 1);
        if Q.IsNull or (Q.EndByte <= AFor.EndByte) or (Q.StartByte >= W.StartByte) or (IsLoopNode(Q) and not (Q = L)) then Continue;  // dl:ok nonminimal-bool@c1b4 -- REVIEWED 2026-11-18 IDXRANGE3: TTSNode declares Equal but no NotEqual; <> does not compile
        if TRegEx.IsMatch(LowerCase(Trim(Txt(Q))), '^continue\b') and (Q.NamedChildCount = 0) then Exit(False);
        for I:= 0 to Q.ChildCount - 1 do Stack.Add(Q.Child(I));
      end;
    finally
      Stack.Free;
    end;
    Exit(True);
  end;
end;

{ YADF.Groups:238, YADF.Layout:4579: an array of an enclosing routine, indexed in a nested one -- its
  length as that routine gives it, when none of its nested routines resizes it, the nested routine
  holding the access is named in its body only after the array is first sized there (and nowhere
  else), and the names the length is expressed in mean the same in the nested routine. }
function TBnRun.OuterLenOf(const AArr: string): TSym;  // dl:ok too-many-exit-points@e885 -- REVIEWED 2026-11-18 IDXRANGE3: guard clauses per syntax shape; each early exit is a classification
var
  Chain, Stack: TList<TTSNode>;
  P, Outer, Child, OBody, N: TTSNode;
  K, I: Integer;
  First: Cardinal;
  Nm, BaseName: string;
  Saved: TBnSaved;
  Visiting: TList<string>;

  { every use of the nested routine AName in Outer is in Outer's body after First, a recursive call,
    or in another nested routine of which the same holds }
  function OnlyAfter(const AName: string; ADepth: Integer): Boolean;
  var
    Todo: TList<TTSNode>;
    M, R: TTSNode;
    J: Integer;
    RName: string;
  begin
    Result:= False;
    if ADepth > MAX_CALLER_DEPTH then Exit;
    if Visiting.IndexOf(AName) >= 0 then Exit(True);
    Visiting.Add(AName);
    Todo:= TList<TTSNode>.Create;
    try
      Todo.Add(Outer);
      while Todo.Count > 0 do
      begin
        M:= Todo.Last;
        Todo.Delete(Todo.Count - 1);
        if M.IsNull then Continue;
        if (M.NodeType = 'identifier') and SameText(Txt(M), AName) then
        begin
          R:= EnclosingProc(M);
          if R.IsNull then Exit;
          RName:= LowerCase(Trim(Txt(R.ChildByField('header').ChildByField('name'))));
          if R = Outer then
          begin
            if (not NodeWithin(M, OBody)) or (M.StartByte < First) then Exit;
          end
          else if (RName <> AName) and not OnlyAfter(RName, ADepth + 1) then
            Exit;
        end;
        for J:= 0 to M.ChildCount - 1 do Todo.Add(M.Child(J));
      end;
      Result:= True;
    finally
      Todo.Free;
    end;
  end;

begin
  Result:= Default(TSym);
  if (FTraceDepth > 0) or FCurProc.IsNull or (FScopes.Count < 2) then Exit;
  K:= -1;
  for I:= FScopes.Count - 2 downto 0 do
    if FScopes[I].ContainsKey(AArr) then
    begin
      K:= I;
      Break;
    end;
  if K < 0 then Exit;
  Chain:= TList<TTSNode>.Create;
  Stack:= TList<TTSNode>.Create;
  Visiting:= TList<string>.Create;
  try
    P:= FCurProc;
    while not P.IsNull do
    begin
      if P.NodeType = 'defProc' then Chain.Insert(0, P);
      P:= P.Parent;
    end;
    if Chain.Count <> FScopes.Count then Exit;
    Outer:= Chain[K];
    Child:= Chain[K + 1];
    OBody:= Outer.ChildByField('body');
    Nm:= LowerCase(Trim(Txt(Child.ChildByField('header').ChildByField('name'))));
    { the first size change in Outer's own body; none in a nested routine or a lambda }
    First:= High(Cardinal);
    Stack.Add(Outer);
    while Stack.Count > 0 do
    begin
      N:= Stack.Last;
      Stack.Delete(Stack.Count - 1);
      if N.IsNull then Continue;
      if IsSizeChangeOf(N, AArr) then
      begin
        if (not NodeWithin(N, OBody)) or not (EnclosingProc(N) = Outer) then Exit;  // dl:ok nonminimal-bool@3fbb -- REVIEWED 2026-11-18 IDXRANGE3: TTSNode declares Equal but no NotEqual; <> does not compile
        if N.StartByte < First then First:= N.StartByte;
      end;
      for I:= 0 to N.ChildCount - 1 do Stack.Add(N.Child(I));
    end;
    if First = High(Cardinal) then Exit;
    { the nested routine is named only in Outer's body after First, or in nested routines that are }
    if not OnlyAfter(Nm, 0) then Exit;
    EnterRoutine(Outer, Saved);
    try
      Result:= LenSymOf(AArr);
    finally
      LeaveRoutine(Saved);
    end;
    if Result.Ok and (Result.Base <> '') then
    begin
      BaseName:= Copy(Result.Base, Pos(':', Result.Base) + 1, MaxInt);
      for I:= K + 1 to FScopes.Count - 1 do
        if FScopes[I].ContainsKey(BaseName) then Exit(Default(TSym));
    end;
  finally
    Visiting.Free;
    Stack.Free;
    Chain.Free;
  end;
end;

{ At the call ASite in its caller (the current routine) AE + AOff stays within AArr, read in the window
  from the SetLength of AArr that dominates the call to the call itself. }
function TBnRun.UpperAtSite(const ASite, AE: TTSNode; const AArr: string; AOff: Integer): Boolean;
var
  OldAccess, Dom: TTSNode;
  OldFrom, OldTo: Cardinal;
  U: TSym;
  Info: TDeclInfo;
begin
  OldAccess:= FAccess;
  OldFrom:= FStableFrom;
  OldTo:= FStableTo;
  FAccess:= ASite;
  try
    Dom:= DomSetLength(AArr);
    if not Dom.IsNull then
    begin
      FStableFrom:= Dom.StartByte;
      FStableTo:= ASite.EndByte;
    end;
    U:= SymOf(AE);
    if not Lookup(AArr, Info) then Info:= Default(TDeclInfo);
    Result:= U.Ok and UpperWithin(MkSym(U.Base, U.Off + AOff), AArr, Info);
  finally
    FAccess:= OldAccess;
    FStableFrom:= OldFrom;
    FStableTo:= OldTo;
  end;
end;

{ YADF.Layout:8067: `idx < Y` (AStrict) / `idx <= Y` with Y a local of the routine whose every write
  leaves it within the array (+ 1 when strict): `Y := -1`, `Y := k` inside `for k := 0 to High(A)`.
  Y is no for counter, never passed to a call by reference and never has its address taken. }
function TBnRun.LocalBoundedBy(const E: TTSNode; AStrict: Boolean; const ACtx: TIdxCtx): Boolean;  // dl:ok too-many-exit-points@99e9 -- REVIEWED 2026-11-18 IDXRANGE3: guard clauses per syntax shape; each early exit is a classification
var
  N, W: TTSNode;
  Y: string;
  L: TList<TTSNode>;
  U: TSym;
  Info: TDeclInfo;

begin
  Result:= False;
  N:= Peeled(E);
  if N.IsNull or (N.NodeType <> 'identifier') then Exit;
  Y:= LowerCase(Txt(N));
  if (not IsOwnLocal(Y)) or FScopes[FScopes.Count - 1][Y].IsParam or (Y = ACtx.Idx) then Exit;
  if NameEscapes(FCurProc, Y, True) then Exit;
  L:= TList<TTSNode>.Create;
  try
    CollectIdxWrites(FCurProc.ChildByField('body'), Y, L);
    if L.Count = 0 then Exit;
    Info:= ACtx.Info;
    for W in L do
    begin
      if (W.NodeType <> 'assignment') or not WriteUpper(W, U) then Exit;
      if AStrict then Dec(U.Off);
      if not UpperWithin(U, ACtx.Arr, Info) then Exit;
    end;
    Result:= True;
  finally
    L.Free;
  end;
end;
{ Something in the routine between AFrom and ATo may change the value at the dotted path APath
  (`rec.list`): an assignment to it or to a prefix of it, a method of it or of a prefix, a pass of it
  or of a prefix to a call that may take it by reference, its (or a prefix's) address, or a pointer
  set from the root's address. A write to a sibling field or an element is no change. }
function TBnRun.TouchedPath(const APath: string; AFrom, ATo: Cardinal): Boolean;  // dl:ok too-many-exit-points@d140, deep-nesting@5639 -- REVIEWED 2026-11-18 IDXRANGE3: guard clauses per syntax shape; the scan nests one level per node kind it checks
var
  Stack: TList<TTSNode>;
  N, Args, Ent: TTSNode;
  I: Integer;
  Fn, P, Root: string;

  function PrefixOf(const A: string): Boolean;
  begin
    Result:= (A <> '') and ((A = APath) or StartsStr(A + '.', APath));
  end;

begin
  Root:= RootName(APath);
  if TouchedIn(Root, AFrom, ATo, True) then Exit(True);  { the root itself, a pointer to it }
  Result:= True;
  Stack:= TList<TTSNode>.Create;
  try
    Stack.Add(FCurProc.ChildByField('body'));
    while Stack.Count > 0 do
    begin
      N:= Stack.Last;
      Stack.Delete(Stack.Count - 1);
      if N.IsNull or (N.EndByte <= AFrom) or (N.StartByte >= ATo) then Continue;
      if N.StartByte >= AFrom then
      begin
        if (N.NodeType = 'assignment') and PrefixOf(DottedPath(N.ChildByField('lhs'))) then Exit;
        if (N.NodeType = 'exprUnary') and (OperatorType(N) = 'kAt') and PrefixOf(DottedPath(N.ChildByField('operand'))) then Exit;
        if (N.NodeType = 'exprCall') and not (N = FAccess) then  // dl:ok nonminimal-bool@da26 -- REVIEWED 2026-11-18 IDXRANGE3: TTSNode declares Equal but no NotEqual; <> does not compile
        begin
          Ent:= N.ChildByField('entity');
          if (Ent.NodeType = 'exprDot') and PrefixOf(DottedPath(Ent.ChildByField('lhs'))) then Exit;
          Fn:= CallName(N);
          Args:= N.ChildByField('args');
          if not Args.IsNull then
            for I:= 0 to Args.NamedChildCount - 1 do
            begin
              P:= DottedPath(Args.NamedChild(I));
              if PrefixOf(P) and not ArgByValue(Fn, I) then Exit;
            end;
        end;
        if (N.NodeType = 'exprDot') and (not N.Parent.IsNull) and ((N.Parent.NodeType = 'block') or (N.Parent.NodeType = 'statements'))
          and PrefixOf(DottedPath(N.ChildByField('lhs'))) then Exit;
      end;
      for I:= 0 to N.ChildCount - 1 do Stack.Add(N.Child(I));
    end;
    Result:= False;
  finally
    Stack.Free;
  end;
end;
{ AX may change behind the routine's own writes: a lambda or a nested routine names it (one that
  declares its own AX does not), its address is taken -- and, with AWithCalls, it is a for counter or
  is passed bare to a call that may take it by reference. }
function TBnRun.NameEscapes(const N: TTSNode; const AX: string; AWithCalls: Boolean): Boolean;  // dl:ok too-many-exit-points@6c3b -- REVIEWED 2026-11-18 IDXRANGE3: guard clauses per syntax shape; each early exit is a classification
var
  J: Integer;
begin
  Result:= False;
  if N.IsNull then Exit;
  if N.NodeType = 'lambda' then Exit(Mentions(N, AX));
  if (N.NodeType = 'defProc') and not (N = FCurProc) then Exit(Mentions(N, AX) and not DeclaresLocal(N, AX));  // dl:ok nonminimal-bool@a164 -- REVIEWED 2026-11-18 IDXRANGE3: TTSNode declares Equal but no NotEqual; <> does not compile
  if (N.NodeType = 'exprUnary') and (OperatorType(N) = 'kAt') and (RootName(Txt(N.ChildByField('operand'))) = AX) then Exit(True);
  if AWithCalls and (N.NodeType = 'for') and (AssignTarget(N.ChildByField('start')) = AX) then Exit(True);
  if AWithCalls and (N.NodeType = 'exprCall') and PassesByRef(N, AX) then Exit(True);
  for J:= 0 to N.ChildCount - 1 do
    if NameEscapes(N.Child(J), AX, AWithCalls) then Exit(True);
end;

{ The routine name a call names: its last dotted part, lower-cased (`FS.ReadBuffer` -> readbuffer). }
function TBnRun.CallName(const ACall: TTSNode): string;
begin
  Result:= LowerCase(Trim(Txt(ACall.ChildByField('entity'))));
  if ContainsStr(Result, '.') then Result:= Copy(Result, LastDelimiter('.', Result) + 1, MaxInt);
end;

{ The call ACall (no Inc / Dec) passes the bare name AX where the callee may take it by reference. }
function TBnRun.PassesByRef(const ACall: TTSNode; const AX: string): Boolean;
var
  Fn: string;
  A: TTSNode;
  J: Integer;
begin
  Result:= False;
  Fn:= CallName(ACall);
  A:= ACall.ChildByField('args');
  if (Fn = 'inc') or (Fn = 'dec') or A.IsNull then Exit;
  for J:= 0 to A.NamedChildCount - 1 do
    if (BareIdent(A.NamedChild(J)) = AX) and not ArgByValue(Fn, J) then Exit(True);
end;

{ The end of the loops around the access under analysis that start after AFrom (else the access). }
function AccessReach(const AAccess: TTSNode; AFrom: Cardinal): Cardinal;
var
  P: TTSNode;
begin
  Result:= AAccess.EndByte;
  P:= AAccess.Parent;
  while (not P.IsNull) and (P.StartByte > AFrom) and (P.NodeType <> 'defProc') do
  begin
    if IsLoopNode(P) and (P.EndByte > Result) then Result:= P.EndByte;
    P:= P.Parent;
  end;
end;

const
  CMP_OPS    : array[0..3] of string = ('kLt', 'kGt', 'kLte', 'kGte');
  CMP_MIRROR : array[0..3] of string = ('kGt', 'kLt', 'kGte', 'kLte');  { idx < X  ==  X > idx }
  CMP_NEGATED: array[0..3] of string = ('kGte', 'kLte', 'kGt', 'kLt');  { not (idx < X)  ==  idx >= X }

{ `idx <op> X` read as `X <op'> idx`: the mirrored comparison operator ('' for a non-comparison). }
function MirrorOp(const AOp: string): string;
var
  I: Integer;
begin
  I:= IndexStr(AOp, CMP_OPS);
  Result:= if I >= 0 then CMP_MIRROR[I] else '';
end;

{ The comparison operator of `not (idx <op> X)` ('' for a non-comparison). }
function NegateOp(const AOp: string): string;
var
  I: Integer;
begin
  I:= IndexStr(AOp, CMP_OPS);
  Result:= if I >= 0 then CMP_NEGATED[I] else '';
end;

{ True when AName resolves to an array whose bounds the rule can name: a static
  array[lo..hi] or a dynamic / open array (bounds 0..High). }
function TBnRun.IsBoundedArray(const AName: string; out AInfo: TDeclInfo): Boolean;
begin
  Result:= Lookup(AName, AInfo) and (not AInfo.Ambig) and (AInfo.Kind in [dkArray, dkDynArray]);
end;

{ N (parentheses peeled) is the call AFn(AArr) -- Low / High / Length of that array -- or a local
  written once as that call (FLenAlias). }
function TBnRun.IsArrayFn(const N: TTSNode; const AFn, AArr: string): Boolean;
var
  E, Args: TTSNode;
begin
  Result:= False;
  E:= N;
  while (not E.IsNull) and (E.NodeType = 'exprParens') and (E.NamedChildCount = 1) do E:= E.NamedChild(0);
  if E.IsNull then Exit;
  if E.NodeType = 'identifier' then
    Exit(FLenAlias.ContainsKey(LowerCase(Txt(E))) and (FLenAlias[LowerCase(Txt(E))] = AFn + ':' + AArr));
  if E.NodeType <> 'exprCall' then Exit;
  Args:= E.ChildByField('args');
  Result:= (BareIdent(E.ChildByField('entity')) = AFn) and (not Args.IsNull)
    and (Args.NamedChildCount = 1) and (LowerCase(Trim(Txt(Args.NamedChild(0)))) = AArr);
end;

{ N is `Length(A) - k` (k >= 1) or `High(A) - k` (k >= 0): at most High(A). }
function TBnRun.IsLenMinus(const N: TTSNode; const AArr: string): Boolean;
var
  K: Integer;
  IsSub: Boolean;
begin
  IsSub:= (not N.IsNull) and (N.NodeType = 'exprBinary') and (OperatorType(N) = 'kSub');
  if not (IsSub and EvalIndex(N.ChildByField('rhs'), K)) then Exit(False);
  Result:= (IsArrayFn(N.ChildByField('lhs'), 'length', AArr) and (K >= 1))
    or (IsArrayFn(N.ChildByField('lhs'), 'high', AArr) and (K >= 0));
end;

{ idx >= E (AStrict: idx > E) proves the lower side. }
function TBnRun.ProvesLower(const E: TTSNode; AStrict: Boolean; const AArr: string; const AInfo: TDeclInfo): Boolean;
var
  V, Lo: Integer;
  S: TSym;
begin
  Lo:= if AInfo.Kind = dkArray then AInfo.Lo else 0;
  Result:= IsArrayFn(E, 'low', AArr);
  if (not Result) and EvalIndex(E, V) then
    Result:= (V >= Lo) or (AStrict and (V + 1 >= Lo));
  if not Result then
  begin
    { a symbolic bound: Low(B) of another array, a count (>= 0) plus an offset }
    S:= SymOf(E);
    if S.Ok and ((S.Base = '') or StartsText('len:', S.Base) or StartsText('cnt:', S.Base)) then
      Result:= (S.Off >= Lo) or (AStrict and (S.Off + 1 >= Lo));
  end;
end;

{ idx <= E (AStrict: idx < E) proves the upper side. }
function TBnRun.ProvesUpper(const E: TTSNode; AStrict: Boolean; const AArr: string; const AInfo: TDeclInfo): Boolean;
var
  V: Integer;
  S: TSym;
begin
  Result:= IsArrayFn(E, 'high', AArr) or IsLenMinus(E, AArr);
  if (not Result) and AStrict then
    Result:= IsArrayFn(E, 'length', AArr);
  if (not Result) and (AInfo.Kind = dkArray) and EvalIndex(E, V) then
    Result:= (V <= AInfo.Hi) or (AStrict and (V <= AInfo.Hi + 1));
  if not Result then
  begin
    { a symbolic bound (1.52 IDXRANGE2): another array's / list's count, a SetLength size }
    S:= SymOf(E);
    if S.Ok then
    begin
      if AStrict then Dec(S.Off);
      Result:= UpperWithin(S, AArr, AInfo);
    end;
  end;
  { 1.52 BK-RULEFP (uINSPRSLT:1871): a local written once from an if-expression of constants }
  if (not Result) and UpperConstOf(E, 0, V) then
  begin
    S:= Default(TSym);
    S.Ok:= True;
    S.Off:= if AStrict then V - 1 else V;
    Result:= UpperWithin(S, AArr, AInfo);
  end;
end;

{ `idx <op> X` / `X <op> idx` (E a comparison): the side it proves, folded into ACtx. }
procedure TBnRun.CompareFacts(var ACtx: TIdxCtx; const E: TTSNode; ANegate: Boolean);
var
  Other: TTSNode;
  Op: string;
begin
  Op:= OperatorType(E);
  if BareIdent(E.ChildByField('lhs')) = ACtx.Idx then
    Other:= E.ChildByField('rhs')
  else if BareIdent(E.ChildByField('rhs')) = ACtx.Idx then
  begin
    Other:= E.ChildByField('lhs');
    Op:= MirrorOp(Op);
  end
  else
    Exit;
  if ANegate then Op:= NegateOp(Op);
  if Op = 'kGte' then ACtx.Lo:= ACtx.Lo or ProvesLower(Other, False, ACtx.Arr, ACtx.Info)
  else if Op = 'kGt' then ACtx.Lo:= ACtx.Lo or ProvesLower(Other, True, ACtx.Arr, ACtx.Info)
  else if (Op = 'kLte') or (Op = 'kLt') then
  begin
    if ProvesUpper(Other, Op = 'kLt', ACtx.Arr, ACtx.Info) or LocalBoundedBy(Other, Op = 'kLt', ACtx) then ACtx.Hi:= True
    else if (ACtx.FgnText = '') and (ACtx.Writes.Count > 0) and IsUnwrittenParam(Other) then
    begin
      { 1.52 BK-RULEFP (YADF.Tokens:208): bounded by a parameter -- proven when every local caller
        passes a valid index of the array (CallersProveUpper) }
      ACtx.FgnText:= Trim(Txt(Other));
      ACtx.FgnSym := SymOf(Other);
      if (Op = 'kLt') and ACtx.FgnSym.Ok then Dec(ACtx.FgnSym.Off);
    end
    else NoteForeign(ACtx, Other, Op = 'kLt', Default(TTSNode));
  end;
end;

{ The bound facts condition C proves about ACtx.Idx for ACtx.Arr (ANegate: the facts of `not C`). }
procedure TBnRun.CondFacts(var ACtx: TIdxCtx; const C: TTSNode; ANegate: Boolean);
const
  INRANGE_ARGS = 3;
var
  E, Args: TTSNode;
  Op: string;
begin
  E:= C;
  while (not E.IsNull) and (E.NodeType = 'exprParens') and (E.NamedChildCount = 1) do E:= E.NamedChild(0);
  if E.IsNull then Exit;
  if (E.NodeType = 'exprUnary') and (OperatorType(E) = 'kNot') then
    CondFacts(ACtx, E.ChildByField('operand'), not ANegate)
  else if E.NodeType = 'exprCall' then
  begin
    Args:= E.ChildByField('args');
    if (not ANegate) and (BareIdent(E.ChildByField('entity')) = 'inrange') and (not Args.IsNull)
      and (Args.NamedChildCount = INRANGE_ARGS) and (BareIdent(Args.NamedChild(0)) = ACtx.Idx) then
    begin
      ACtx.Lo:= ACtx.Lo or ProvesLower(Args.NamedChild(1), False, ACtx.Arr, ACtx.Info);
      if ProvesUpper(Args.NamedChild(2), False, ACtx.Arr, ACtx.Info) then ACtx.Hi:= True
      else NoteForeign(ACtx, Args.NamedChild(2), False, Default(TTSNode));
    end;
  end
  else if E.NodeType = 'exprBinary' then
  begin
    Op:= OperatorType(E);
    if ((Op = 'kAnd') and not ANegate) or ((Op = 'kOr') and ANegate) then
    begin
      CondFacts(ACtx, E.ChildByField('lhs'), ANegate);
      CondFacts(ACtx, E.ChildByField('rhs'), ANegate);
    end
    else if Op = 'kIn' then
    begin
      if not ANegate then SetFacts(ACtx, E);
    end
    else
      CompareFacts(ACtx, E, ANegate);
  end;
end;

{ A then-branch that always leaves: raise / Exit / Continue / Break, or a block ending in one. }
function TBnRun.IsLeaveStmt(const N: TTSNode): Boolean;
var
  I: Integer;
begin
  Result:= False;
  if N.IsNull then Exit;
  if N.NodeType = 'raise' then Exit(True);
  if N.NodeType = 'block' then
  begin
    for I:= N.NamedChildCount - 1 downto 0 do
      if not IsTrivia(N.NamedChild(I)) then Exit(IsLeaveStmt(N.NamedChild(I)));
    Exit;
  end;
  Result:= TRegEx.IsMatch(LowerCase(Trim(Txt(N))), '^(exit|continue|break)\b');
end;

{ A then-branch that grows AArr: `SetLength(A, ...)`, or a block ending in one (the grow-on-demand
  `if i >= Length(A) then SetLength(A, ...)` -- after it, i is below Length(A)). }
function TBnRun.IsGrowOf(const N: TTSNode; const AArr: string): Boolean;
var
  I: Integer;
begin
  Result:= False;
  if N.IsNull then Exit;
  if N.NodeType = 'block' then
  begin
    for I:= N.NamedChildCount - 1 downto 0 do
      if not IsTrivia(N.NamedChild(I)) then Exit(IsGrowOf(N.NamedChild(I), AArr));
    Exit;
  end;
  { by text, like IsLeaveStmt: a statement wrapper node may sit between the branch and the call }
  Result:= TRegEx.IsMatch(LowerCase(Trim(Txt(N))), '^setlength\s*\(\s*' + TRegEx.Escape(AArr) + '\s*,');
end;

{ The written identifier of an assignment's left side (also `for var i :=` / `var i :=`). }
function TBnRun.AssignTarget(const AAssign: TTSNode): string;
var
  Lhs: TTSNode;
  I  : Integer;
begin
  Result:= '';
  Lhs:= AAssign.ChildByField('lhs');
  if Lhs.IsNull then Exit;
  if Lhs.NodeType = 'varAssignDef' then
  begin
    for I:= 0 to Lhs.ChildCount - 1 do
      if Lhs.Child(I).NodeType = 'identifier' then Exit(LowerCase(Txt(Lhs.Child(I))));
    Exit;
  end;
  Result:= BareIdent(Lhs);
end;

{ True when N's subtree names AIdent (any identifier node). }
function TBnRun.Mentions(const N: TTSNode; const AIdent: string): Boolean;
var
  I: Integer;
begin
  Result:= False;
  if N.IsNull then Exit;
  if (N.NodeType = 'identifier') and SameText(Txt(N), AIdent) then Exit(True);
  for I:= 0 to N.ChildCount - 1 do
    if Mentions(N.Child(I), AIdent) then Exit(True);
end;

{ Every write of AIdx in the body: `idx := e`, `Inc(idx)`, `Dec(idx)`, `for idx in ...`. A
  for-loop's own counter assignment is not a write here (the loop bounds it). Lambdas are skipped. }
procedure TBnRun.CollectIdxWrites(const N: TTSNode; const AIdx: string; AList: TList<TTSNode>);
var
  T: string;
  I: Integer;
  Args: TTSNode;
  IsForStart: Boolean;
begin
  if N.IsNull then Exit;
  T:= N.NodeType;
  if (T = 'lambda') or (T = 'defProc') then Exit;
  IsForStart:= (not N.Parent.IsNull) and (N.Parent.NodeType = 'for') and (N.Parent.ChildByField('start') = N);
  if (T = 'assignment') and (AssignTarget(N) = AIdx) and not IsForStart then
    AList.Add(N)
  else if T = 'exprCall' then
  begin
    Args:= N.ChildByField('args');
    if ((BareIdent(N.ChildByField('entity')) = 'inc') or (BareIdent(N.ChildByField('entity')) = 'dec'))
      and (not Args.IsNull) and (Args.NamedChildCount >= 1) and (BareIdent(Args.NamedChild(0)) = AIdx) then
      AList.Add(N);
  end
  else if (T = 'foreach') and (BareIdent(N.ChildByField('iterator')) = AIdx) then
    AList.Add(N);
  for I:= 0 to N.ChildCount - 1 do CollectIdxWrites(N.Child(I), AIdx, AList);
end;

{ Does write W keep the lower (ALower) / upper side of ACtx.Idx within ACtx.Arr's range by itself? }
function TBnRun.WriteKeeps(const ACtx: TIdxCtx; const W: TTSNode; ALower: Boolean): Boolean;
var
  Rhs: TTSNode;
  K  : Integer;
  Fn : string;
begin
  Result:= False;
  if W.NodeType = 'exprCall' then
  begin
    Fn:= BareIdent(W.ChildByField('entity'));
    Exit((ALower and (Fn = 'inc')) or ((not ALower) and (Fn = 'dec')));
  end;
  if W.NodeType <> 'assignment' then Exit;
  Rhs:= W.ChildByField('rhs');
  Result:= if ALower then ProvesLower(Rhs, False, ACtx.Arr, ACtx.Info) else ProvesUpper(Rhs, False, ACtx.Arr, ACtx.Info);
  { idx := idx + k keeps the lower side, idx := idx - k the upper side (k >= 0) }
  if (not Result) and (Rhs.NodeType = 'exprBinary') and (BareIdent(Rhs.ChildByField('lhs')) = ACtx.Idx)
    and EvalIndex(Rhs.ChildByField('rhs'), K) and (K >= 0) then
    Result:= (ALower and (OperatorType(Rhs) = 'kAdd')) or ((not ALower) and (OperatorType(Rhs) = 'kSub'));
end;

{ `case AIdx of`: the selector is the first non-keyword child. }
function TBnRun.CaseOn(const ACase: TTSNode; const AIdx: string): Boolean;
var
  I: Integer;
begin
  Result:= False;
  for I:= 0 to ACase.NamedChildCount - 1 do
    if not IsTrivia(ACase.NamedChild(I)) then Exit(BareIdent(ACase.NamedChild(I)) = AIdx);
end;

{ True when no write of ACtx.Idx starts strictly between AFrom and the access (a guard still holds).
  1.52 IDXRANGE3 (YADF.Layout:457): a write whose block then leaves -- Exit / raise, or Continue /
  Break of a loop around the access when the guard is inside that loop -- does not count, nor does one in
  the other branch of an if / else the access sits in (YADF.Guard:500). }
function TBnRun.HoldsSince(const ACtx: TIdxCtx; AFrom: Cardinal): Boolean;
var
  W: TTSNode;
begin
  Result:= True;
  for W in ACtx.Writes do
    if (W.StartByte > AFrom) and (W.StartByte < ACtx.Access.StartByte) and not LeavesBefore(W, ACtx.Access, AFrom, True)
      and not ExclusiveBranches(W, ACtx.Access) then Exit(False);
end;

{ W and AAccess sit in the two branches of one if / else (or two arms of one case): within one pass
  neither runs after the other. }
function TBnRun.ExclusiveBranches(const W, AAccess: TTSNode): Boolean;
var
  P, BW, BA: TTSNode;
begin
  Result:= False;
  P:= W.Parent;
  while (not P.IsNull) and (P.NodeType <> 'defProc') and not NodeWithin(AAccess, P) do P:= P.Parent;
  if P.IsNull or (P.NodeType = 'defProc') then Exit;
  if P.NodeType = 'ifElse' then
  begin
    BW:= P.ChildByField('then');
    BA:= P.ChildByField('else');
    Exit((NodeWithin(W, BW) and NodeWithin(AAccess, BA)) or (NodeWithin(W, BA) and NodeWithin(AAccess, BW)));
  end;
  if P.NodeType = 'case' then
  begin
    BW:= W;
    while (not BW.IsNull) and not (BW.Parent = P) do BW:= BW.Parent;  // dl:ok nonminimal-bool@8ec4 -- REVIEWED 2026-11-18 IDXRANGE3: TTSNode declares Equal but no NotEqual; <> does not compile
    BA:= AAccess;
    while (not BA.IsNull) and not (BA.Parent = P) do BA:= BA.Parent;  // dl:ok nonminimal-bool@173d -- REVIEWED 2026-11-18 IDXRANGE3: TTSNode declares Equal but no NotEqual; <> does not compile
    Result:= (not BW.IsNull) and (not BA.IsNull) and (BW.NodeType = 'caseCase') and (BA.NodeType = 'caseCase') and not (BW = BA);  // dl:ok nonminimal-bool@0607 -- REVIEWED 2026-11-18 IDXRANGE3: TTSNode declares Equal but no NotEqual; <> does not compile
  end;
end;

{ After W control surely leaves before it can reach AAccess: a statement list holding W (but not
  AAccess) ends in Exit / raise -- or, with ALoopLeave, in Continue / Break of the innermost loop
  around that list when the loop holds AAccess and (Continue) AFrom lies inside the loop. Never
  across a try (an exception skips the leave). }
function TBnRun.LeavesBefore(const W, AAccess: TTSNode; AFrom: Cardinal; ALoopLeave: Boolean): Boolean;  // dl:ok too-many-exit-points@06fc -- REVIEWED 2026-11-18 IDXRANGE3: guard clauses per syntax shape; each early exit is a classification
var
  P, S, T: TTSNode;
  I: Integer;
  Word: string;
begin
  Result:= False;
  P:= W.Parent;
  while (not P.IsNull) and (P.NodeType <> 'defProc') and (P.NodeType <> 'lambda') do
  begin
    if NodeWithin(AAccess, P) or (P.NodeType = 'try') then Exit;
    if (P.NodeType = 'block') or (P.NodeType = 'statements') then
    begin
      S:= Default(TTSNode);
      for I:= P.NamedChildCount - 1 downto 0 do
        if not IsTrivia(P.NamedChild(I)) then
        begin
          S:= P.NamedChild(I);
          Break;
        end;
      if (not S.IsNull) and (S.StartByte >= W.EndByte) and IsLeaveStmt(S) then
      begin
        Word:= LowerCase(TrimLeft(Txt(S)));
        if StartsText('exit', Word) or StartsText('raise', Word) then Exit(True);
        if not ALoopLeave then Exit;
        T:= P.Parent;
        while (not T.IsNull) and not IsLoopNode(T) and (T.NodeType <> 'defProc') do T:= T.Parent;
        if T.IsNull or (T.NodeType = 'defProc') or not NodeWithin(AAccess, T) then Exit;
        if StartsText('break', Word) then Exit(True);
        Exit(AFrom > T.StartByte);
      end;
    end;
    P:= P.Parent;
  end;
end;

{ The line the autofix inserts its guard before: the access's own statement when that statement
  is a direct member of a statement list and starts its line; 0 when the access sits in a
  condition, a loop header or a one-statement branch (the insertion would change the meaning). }
function TBnRun.FixAnchorLine(const AAccess: TTSNode): Integer;
const
  CONTROL: array[0..10] of string = ('if', 'ifElse', 'while', 'for', 'foreach', 'repeat', 'case',
    'caseCase', 'try', 'with', 'exceptionHandler');
  TAB_BYTE = 9;
  LF_BYTE  = 10;
var
  C, P: TTSNode;
  S: string;
  B: Integer;
begin
  Result:= 0;
  C:= AAccess;
  while not C.IsNull do
  begin
    for S in CONTROL do
      if C.NodeType = S then Exit;
    P:= C.Parent;
    if P.IsNull or (P.NodeType = 'defProc') or (P.NodeType = 'lambda') then Exit;
    if (P.NodeType = 'block') or (P.NodeType = 'statements') then Break;
    C:= P;
  end;
  if C.IsNull then Exit;
  B:= Integer(C.StartByte) - 1;
  while (B >= 0) and ((FSrc[B] = Ord(' ')) or (FSrc[B] = TAB_BYTE)) do Dec(B);
  if (B >= 0) and (FSrc[B] <> LF_BYTE) then Exit;
  Result:= Integer(C.StartPoint.Row) + 1;
end;

{ Provenance: a side holds when every write that can REACH the access keeps it -- earlier writes,
  and later ones inside the outermost loop around it (they flow back on the next iteration).
  Never for a parameter: its incoming value is unknown. }
procedure TBnRun.ProvenanceSides(var ACtx: TIdxCtx);
var
  C, Outer, W: TTSNode;
  Reach: TList<TTSNode>;
begin
  ACtx.Lo:= False;
  ACtx.Hi:= False;
  if ACtx.IdxInfo.IsParam or (ACtx.Writes.Count = 0) then Exit;
  Outer:= Default(TTSNode);
  C:= ACtx.Access.Parent;
  while (not C.IsNull) and (C.NodeType <> 'defProc') and (C.NodeType <> 'lambda') do
  begin
    if (C.NodeType = 'while') or (C.NodeType = 'repeat') or (C.NodeType = 'for') or (C.NodeType = 'foreach') then Outer:= C;
    C:= C.Parent;
  end;
  ACtx.Lo:= True;
  Reach:= TList<TTSNode>.Create;
  try
    for W in ACtx.Writes do
      if (W.StartByte < ACtx.Access.StartByte) or ((not Outer.IsNull) and (W.StartByte < Outer.EndByte)) then
      begin
        ACtx.Lo:= ACtx.Lo and WriteKeeps(ACtx, W, True);
        Reach.Add(W);
      end;
    ACtx.Hi:= UpperSides(ACtx, Reach);
  finally
    Reach.Free;
  end;
end;

{ C under a branching parent P: an if / if-expression branch, or the right side of a short-circuit. }
procedure TBnRun.ApplyBranch(var ACtx: TIdxCtx; const C, P: TTSNode);
var
  ElseAt: Cardinal;
  I: Integer;
begin
  if (P.NodeType = 'if') or (P.NodeType = 'ifElse') then
  begin
    if not HoldsSince(ACtx, P.ChildByField('condition').EndByte) then Exit;
    if P.ChildByField('then') = C then CondFacts(ACtx, P.ChildByField('condition'), False)
    else if P.ChildByField('else') = C then CondFacts(ACtx, P.ChildByField('condition'), True);
  end
  else if P.NodeType = 'exprIf' then
  begin
    if P.ChildByField('condition') = C then Exit;
    { `if c then X else Y` as an expression: X sits before the kElse child, Y after it }
    ElseAt:= P.EndByte;
    for I:= 0 to P.ChildCount - 1 do
      if P.Child(I).NodeType = 'kElse' then ElseAt:= P.Child(I).StartByte;
    CondFacts(ACtx, P.ChildByField('condition'), C.StartByte > ElseAt);
  end
  else if (P.NodeType = 'exprBinary') and (P.ChildByField('rhs') = C) then
  begin
    { short-circuit: `X and A[i]` evaluates the right side only when X holds; `X or A[i]` only when it fails }
    if OperatorType(P) = 'kAnd' then CondFacts(ACtx, P.ChildByField('lhs'), False)
    else if OperatorType(P) = 'kOr' then CondFacts(ACtx, P.ChildByField('lhs'), True);
  end;
end;

{ `for idx := s to/downto e` around the access: both sides when the bounds are recognised. A loop
  that runs to ANOTHER collection's bound not proven within this array's (parallel arrays, owner
  C1 2026-11-17) proves the low side and records that bound -- a warning on the for line unless the
  local callers prove it. Any other unrecognised bound stays silent (v1 cut). }
procedure TBnRun.ApplyForBounds(var ACtx: TIdxCtx; const P: TTSNode);
var
  I: Integer;
  IsDown, LoOk, HiOk: Boolean;
  StartE, EndE, HiE: TTSNode;
begin
  IsDown:= False;
  for I:= 0 to P.ChildCount - 1 do
    if P.Child(I).NodeType = 'kDownto' then IsDown:= True;
  StartE:= P.ChildByField('start').ChildByField('rhs');
  EndE  := P.ChildByField('end');
  HiE   := if IsDown then StartE else EndE;
  LoOk  := ProvesLower(if IsDown then EndE else StartE, False, ACtx.Arr, ACtx.Info);
  HiOk  := ProvesUpper(HiE, False, ACtx.Arr, ACtx.Info);
  if LoOk and HiOk then
  begin
    ACtx.Lo:= True;
    ACtx.Hi:= True;
  end
  else if LoOk and ForeignBound(HiE, ACtx.Arr) then
  begin
    ACtx.Lo:= True;
    NoteForeign(ACtx, HiE, False, P);
  end
  else
    ACtx.Silent:= True;
end;

{ C under a loop P: the while condition, the for bounds, the repeat cut; records the innermost loop. }
procedure TBnRun.ApplyLoop(var ACtx: TIdxCtx; const C, P: TTSNode);
begin
  if ACtx.Loop.IsNull then ACtx.Loop:= P;
  if P.NodeType = 'while' then
  begin
    if (P.ChildByField('body') = C) and HoldsSince(ACtx, P.ChildByField('condition').EndByte) then
      CondFacts(ACtx, P.ChildByField('condition'), False);
  end
  else if P.NodeType = 'repeat' then
    ACtx.Silent:= ACtx.Silent or Mentions(P.ChildByField('condition'), ACtx.Idx)  { v1 cut: repeat conditions }
  else if (P.NodeType = 'for') and (P.ChildByField('body') = C) and (AssignTarget(P.ChildByField('start')) = ACtx.Idx) then
    ApplyForBounds(ACtx, P);
end;

{ Earlier statements of the list holding C: `if <fail> then Exit / raise / Continue / Break` and
  the grow-on-demand `if i >= Length(A) then SetLength(A, ...)` guard; Assert is a v1 cut. }
procedure TBnRun.ApplySiblings(var ACtx: TIdxCtx; const C: TTSNode);
var
  S, ThenN: TTSNode;
begin
  S:= C.PrevSibling;
  while not S.IsNull do
  begin
    ThenN:= S.ChildByField('then');
    if (S.NodeType = 'if') and (IsLeaveStmt(ThenN) or IsGrowOf(ThenN, ACtx.Arr)) then
    begin
      if HoldsSince(ACtx, S.EndByte) then CondFacts(ACtx, S.ChildByField('condition'), True)
      else ApplyKeptGuard(ACtx, S.ChildByField('condition'), S.EndByte);
    end
    else if (S.NodeType = 'if') and IsClampOf(ThenN, ACtx) and HoldsSince(ACtx, S.EndByte) then
      CondFacts(ACtx, S.ChildByField('condition'), True)  { 1.52 BK-RULEFP (STATS:1988): `if not c then idx := k` }
    else if (S.NodeType = 'exprCall') and (BareIdent(S.ChildByField('entity')) = 'assert') and Mentions(S, ACtx.Idx) then
      ACtx.Silent:= True;
    S:= S.PrevSibling;
  end;
end;

{ Every dominating guard from the access up to its routine. }
procedure TBnRun.ClimbGuards(var ACtx: TIdxCtx);
var
  C, P: TTSNode;
  T: string;
begin
  C:= ACtx.Access;
  P:= C.Parent;
  while (not P.IsNull) and (P.NodeType <> 'defProc') and (P.NodeType <> 'lambda') do
  begin
    T:= P.NodeType;
    if (T = 'if') or (T = 'ifElse') or (T = 'exprIf') or (T = 'exprBinary') then
      ApplyBranch(ACtx, C, P)
    else if (T = 'while') or (T = 'repeat') or (T = 'foreach') or (T = 'for') then
      ApplyLoop(ACtx, C, P)
    else if (T = 'case') and CaseOn(P, ACtx.Idx) then
      ACtx.Silent:= True  { v1 cut: case ranges }
    else if (T = 'block') or (T = 'statements') then
      ApplySiblings(ACtx, C);
    C:= P;
    P:= C.Parent;
  end;
end;

{ The finding for an unproven access: on the nearest preceding write (else a later write inside the
  enclosing loop) as a warning, or on the access as a hint for an unwritten parameter. One finding
  per write / per parameter (AReported). }
procedure TBnRun.EmitIndexFinding(const AProc: TTSNode; const ACtx: TIdxCtx; AReported: TDictionary<string, Boolean>);
const
  MSG_BODY = ' reaches %s[%s] at line %d %s '
    + '-- check it before the access; ERangeError is only the last resort (in %s; %s)';
var
  Report, W: TTSNode;
  Key, Routine, Tail, Ent, Arg, Body, Clause, Lookup, Sev, Prefix: string;
  Anchor: Integer;
begin
  Report:= Default(TTSNode);
  for W in ACtx.Writes do
    if (W.StartByte < ACtx.Access.StartByte) and (Report.IsNull or (W.StartByte > Report.StartByte)) then Report:= W;
  if Report.IsNull and not ACtx.Loop.IsNull then
    for W in ACtx.Writes do
      if (W.StartByte > ACtx.Access.StartByte) and (W.EndByte <= ACtx.Loop.EndByte) and Report.IsNull then Report:= W;
  { a for loop running to another collection's bound is the site that made it unsafe }
  if (not ACtx.FgnNode.IsNull) and (Report.IsNull or (ACtx.FgnNode.StartByte > Report.StartByte)) then Report:= ACtx.FgnNode;
  if Report.IsNull and not ACtx.IdxInfo.IsParam then Exit;
  Key:= if Report.IsNull then 'p' + ACtx.Idx else 'w' + IntToStr(Report.StartByte);
  if AReported.ContainsKey(Key) then Exit;
  AReported.Add(Key, True);
  Ent:= Txt(ACtx.Access.ChildByField('entity'));
  Arg:= Trim(Txt(ACtx.Access.ChildByField('args')));
  Routine:= Trim(Txt(AProc.ChildByField('header').ChildByField('name')));
  Anchor:= FixAnchorLine(ACtx.Access);
  Tail:= if Anchor > 0 then Format('fix raises %s at line %d', [FExClass, Anchor])
    else 'no autofix: the access sits in a condition or a one-statement branch';
  Clause:= if ACtx.FgnText <> '' then Format('bounded only by %s, which is not proven to lie within %s''s range', [ACtx.FgnText, Ent])
    else Format('with no guard bounding it to %s''s range on both sides', [Ent]);
  Body:= Format(MSG_BODY, [Ent, Arg, Integer(ACtx.Access.StartPoint.Row) + 1, Clause, Routine, Tail]);
  Sev:= 'warning';
  if Report.IsNull then
  begin
    Prefix:= Format('Parameter ''%s''', [Arg]);
    if ACtx.FgnText = '' then Sev:= 'hint';  { C1: a parameter checked against another collection stays a warning }
    Report:= ACtx.Access;
  end
  else if Report.NodeType = 'for' then
    Prefix:= Format('Loop counter ''%s'' runs to %s here and', [Arg, ACtx.FgnText])
  else if IsLookupWrite(Report, Lookup) then
  begin
    { ORM3 2026-11-17: a value read from a dictionary / lookup has a range the rule cannot see }
    Prefix:= Format('''%s'' is read here from the lookup %s (its value range is not visible to the rule) and', [Arg, Lookup]);
    Sev:= 'hint';
  end
  else
    Prefix:= Format('''%s'' is written here and', [Arg]);
  EmitAt(Report, RULE_INDEX_RANGE, Prefix + Body, Sev);
end;

{ One access A[idx]: proves both sides or reports the write that made it unsafe. }
procedure TBnRun.CheckIndexAccess(const AProc: TTSNode; var ACtx: TIdxCtx; AReported: TDictionary<string, Boolean>);
var
  Dom: TTSNode;
  V: Integer;
  U: TSym;
begin
  FAccess:= ACtx.Access;
  { 1.52 IDXRANGE3: the window in which names nobody changes read as one value (SymOf) }
  FStableFrom:= 0;
  FStableTo:= 0;
  if FTraceDepth = 0 then
  begin
    Dom:= DomSetLength(ACtx.Arr);
    if not Dom.IsNull then
    begin
      FStableFrom:= Dom.StartByte;
      FStableTo:= AccessReach(ACtx.Access, Dom.StartByte);
    end;
  end;
  try
    ProvenanceSides(ACtx);
    ACtx.Silent:= False;
    ACtx.Loop:= Default(TTSNode);
    ACtx.FgnText:= '';
    ACtx.FgnSym:= Default(TSym);
    ACtx.FgnNode:= Default(TTSNode);
    ClimbGuards(ACtx);
    if ACtx.Silent or (ACtx.Lo and ACtx.Hi) then Exit;
    if (not ACtx.Hi) and (OnePastWhile(ACtx) or CountInvariant(ACtx)) then ACtx.Hi:= True;
    if ACtx.Lo and ACtx.Hi then Exit;
    { 1.52 IDXRANGE3: the bounds the index's writes and guards give (index chains, a constant cap,
      a for counter copied out of its loop, a rounded float behind a range guard) }
    if (not ACtx.Lo) and BoundAt(ACtx.Idx, ACtx.Access, False, 0, V) and (not IsNeutralBound(V))
      and (V >= (if ACtx.Info.Kind = dkArray then ACtx.Info.Lo else 0)) then ACtx.Lo:= True;
    if (not ACtx.Hi) and BoundAt(ACtx.Idx, ACtx.Access, True, 0, V) and (not IsNeutralBound(V))
      and UpperWithin(MkSym('', V), ACtx.Arr, ACtx.Info) then ACtx.Hi:= True;
    { 1.52 IDXRANGE3 (uPipeSessionBuilder:4522): `SetLength(A, n + 1); A[n]` -- the index names the size }
    if not ACtx.Hi then
    begin
      U:= SymOf(ACtx.Access.ChildByField('args').NamedChild(0));
      if U.Ok and (U.Base <> '') and UpperWithin(U, ACtx.Arr, ACtx.Info) then ACtx.Hi:= True;
    end;
    if ACtx.Lo and ACtx.Hi then Exit;
    if FTraceDepth = 0 then
    begin
      { C1: the other collection's bound proven within this array's by every local caller }
      if ACtx.Lo and (not ACtx.Hi) and ACtx.FgnSym.Ok and CallersProveUpper(AProc, ACtx) then Exit;
      { C2: an unchecked index parameter every local caller passes in range }
      if ACtx.IdxInfo.IsParam and (ACtx.Writes.Count = 0) and (ACtx.FgnText = '') and CallersProveIndex(AProc, ACtx) then Exit;
    end;
    EmitIndexFinding(AProc, ACtx, AReported);
  finally
    FStableFrom:= 0;
    FStableTo:= 0;
  end;
end;

{ Locals of the body written exactly once, as `n := Length(A)` / `High(A)` / `Low(A)`: a bound on n
  is then a bound on A. Any second write (assignment, Inc / Dec, for counter) disqualifies n. }
procedure TBnRun.CollectLenAliases(const ABody: TTSNode);
var
  Writes: TDictionary<string, Integer>;
  Cand  : TDictionary<string, string>;

  { `Length(x)` / `High(x)` / `Low(x)` -> 'fn:x', else '' }
  function BoundCallKey(const ARhs: TTSNode): string;
  var
    R, Args: TTSNode;
    Fn: string;
  begin
    Result:= '';
    R:= ARhs;
    while (not R.IsNull) and (R.NodeType = 'exprParens') and (R.NamedChildCount = 1) do R:= R.NamedChild(0);
    if R.IsNull or (R.NodeType <> 'exprCall') then Exit;
    Fn:= BareIdent(R.ChildByField('entity'));
    Args:= R.ChildByField('args');
    if not ((Fn = 'length') or (Fn = 'high') or (Fn = 'low')) then Exit;
    if (not Args.IsNull) and (Args.NamedChildCount = 1) and (BareIdent(Args.NamedChild(0)) <> '') then
      Result:= Fn + ':' + BareIdent(Args.NamedChild(0));
  end;

  procedure Walk(const N: TTSNode);
  var
    I, C: Integer;
    T, Nm, Key: string;
    Args: TTSNode;
  begin
    if N.IsNull then Exit;
    T:= N.NodeType;
    if (T = 'lambda') or (T = 'defProc') then Exit;
    Nm:= '';
    if T = 'assignment' then
    begin
      Nm:= AssignTarget(N);
      Key:= BoundCallKey(N.ChildByField('rhs'));
      if (Nm <> '') and (Key <> '') then Cand.AddOrSetValue(Nm, Key);
    end
    else if (T = 'exprCall') and ((BareIdent(N.ChildByField('entity')) = 'inc') or (BareIdent(N.ChildByField('entity')) = 'dec')) then
    begin
      Args:= N.ChildByField('args');
      if (not Args.IsNull) and (Args.NamedChildCount >= 1) then Nm:= BareIdent(Args.NamedChild(0));
    end;
    if Nm <> '' then
    begin
      if not Writes.TryGetValue(Nm, C) then C:= 0;
      Writes.AddOrSetValue(Nm, C + 1);
    end;
    for I:= 0 to N.ChildCount - 1 do Walk(N.Child(I));
  end;

var
  Pair: TPair<string, string>;
  C: Integer;
begin
  FLenAlias.Clear;
  Writes:= TDictionary<string, Integer>.Create;
  Cand:= TDictionary<string, string>.Create;
  try
    Walk(ABody);
    for Pair in Cand do
      if Writes.TryGetValue(Pair.Key, C) and (C = 1) then FLenAlias.Add(Pair.Key, Pair.Value);
  finally
    Cand.Free;
    Writes.Free;
  end;
end;

{ ---- index-possibly-out-of-range: symbolic bounds and local callers (1.52 IDXRANGE2) ---- }

{ N sits inside a loop of its routine (while / repeat / for / for-in). }
function IsInLoop(const N: TTSNode): Boolean;
var
  Q: TTSNode;
begin
  Result:= False;
  Q:= N.Parent;
  while (not Q.IsNull) and (Q.NodeType <> 'defProc') and (Q.NodeType <> 'lambda') do
  begin
    if (Q.NodeType = 'while') or (Q.NodeType = 'repeat') or (Q.NodeType = 'for') or (Q.NodeType = 'foreach') then Exit(True);
    Q:= Q.Parent;
  end;
end;


function IsCountBase(const ABase: string): Boolean;
begin
  Result:= StartsText('len:', ABase) or StartsText('cnt:', ABase);
end;

{ A <= B; a count base of B is taken to be at least AMinCount. }
function SymLE(const A, B: TSym; AMinCount: Integer): Boolean;
begin
  Result:= False;
  if not (A.Ok and B.Ok) then Exit;
  if A.Base = B.Base then Exit(A.Off <= B.Off);
  if (A.Base = '') and IsCountBase(B.Base) then Result:= A.Off <= AMinCount + B.Off;
end;

function TBnRun.InScopes(const AName: string): Boolean;
var
  I: Integer;
begin
  Result:= False;
  for I:= 0 to FScopes.Count - 1 do
    if FScopes[I].ContainsKey(AName) then Exit(True);
end;

{ How many writes of AName the current routine's body holds (cached per routine). }
function TBnRun.WritesOf(const AName: string): Integer;
var
  L: TList<TTSNode>;
begin
  if FCurProc.IsNull then Exit(1);
  if FWriteCnt.TryGetValue(AName, Result) then Exit;
  L:= TList<TTSNode>.Create;
  try
    CollectIdxWrites(FCurProc.ChildByField('body'), AName, L);
    Result:= L.Count;
  finally
    L.Free;
  end;
  FWriteCnt.Add(AName, Result);
end;

{ E as a symbolic integer: a constant, Length / High / Low of an array, X.Count, a name the routine
  never writes, a local alias of Length(A), and + / - of those with at most one base. }
function TBnRun.SymOf(const E: TTSNode): TSym;

  function ArrFn(const AFn, AX: string): TSym;
  var
    Info: TDeclInfo;
  begin
    Result:= Default(TSym);
    if (not Lookup(AX, Info)) and not StoreArray(AX, Info) then Info:= Default(TDeclInfo);  { 1.52 BK-RULEFP: another unit's const array }
    if Info.Kind = dkArray then
    begin
      if AFn = 'length' then Result:= MkSym('', Info.Hi - Info.Lo + 1)
      else if AFn = 'high' then Result:= MkSym('', Info.Hi)
      else if AFn = 'low' then Result:= MkSym('', Info.Lo);
    end
    else if (Info.Kind = dkDynArray) or (AX = 'result') then
    begin
      if AFn = 'low' then Exit(MkSym('', 0));
      if (AFn <> 'high') and (AFn <> 'length') then Exit;
      Result:= LenSymOf(AX);
      if (AFn = 'high') and Result.Ok then Dec(Result.Off);
    end
    else if AFn = 'length' then
      Result:= MkSym('len:' + AX, 0);
  end;

var
  N, Args: TTSNode;
  V: Integer;
  X, Al, Op: string;
  A, B: TSym;
  Stable, IsLenFn: Boolean;
begin
  Result:= Default(TSym);
  N:= E;
  while (not N.IsNull) and (N.NodeType = 'exprParens') and (N.NamedChildCount = 1) do N:= N.NamedChild(0);
  if N.IsNull then Exit;
  if EvalIndex(N, V) then Exit(MkSym('', V));
  { 1.52 IDXRANGE3: inside the window of the access under analysis (from the dominating SetLength to
    the end of the loops around the access) a name, a field path or a Length nobody there changes
    reads as one value (BASICSF:3578, Pipes.Framing:557, Blueprint4.ViewModel:3004) }
  Stable:= (FStableFrom > 0) and (N.StartByte >= FStableFrom) and (N.EndByte <= FStableTo) and NodeWithin(N, FCurProc);
  if N.NodeType = 'exprCall' then
  begin
    Args:= N.ChildByField('args');
    Op:= BareIdent(N.ChildByField('entity'));
    IsLenFn:= (Op = 'length') or (Op = 'high');
    X:= if (not Args.IsNull) and (Args.NamedChildCount = 1) then DottedPath(Args.NamedChild(0)) else '';
    { 1.52 IDXRANGE3 (YADF.Layout:9888): Length / High of a field path nobody changes in the window }
    IsLenFn:= IsLenFn and Stable and ContainsStr(X, '.');
    if IsLenFn and IsOwnLocal(RootName(X)) and not TouchedPath(X, FStableFrom, FStableTo) then
      Result:= MkSym('len:' + X, if Op = 'high' then -1 else 0)
    else if (not Args.IsNull) and (Args.NamedChildCount = 1) and (BareIdent(Args.NamedChild(0)) <> '') then
    begin
      X:= BareIdent(Args.NamedChild(0));
      Op:= BareIdent(N.ChildByField('entity'));
      Result:= ArrFn(Op, X);
      IsLenFn:= (Op = 'length') or (Op = 'high');
      if (not Result.Ok) and Stable and IsLenFn and IsOwnLocal(X) and not TouchedIn(X, FStableFrom, FStableTo, True) then
        Result:= MkSym('len:' + X, if Op = 'high' then -1 else 0);
    end;
  end
  else if N.NodeType = 'exprDot' then
  begin
    if (DottedPath(N.ChildByField('lhs')) <> '') and SameText(Trim(Txt(N.ChildByField('rhs'))), 'count') then
      Result:= MkSym('cnt:' + DottedPath(N.ChildByField('lhs')), 0)  { 1.52 IDXRANGE3: also Owner.List.Count (uBroadcastServer:686) }
    else if Stable and TRegEx.IsMatch(Txt(N), '^\s*[A-Za-z_]\w*(\s*\.\s*[A-Za-z_]\w*)+\s*$')
      and IsOwnLocal(RootName(Txt(N))) and not TouchedPath(DottedPath(N), FStableFrom, FStableTo) then
      Result:= MkSym('fld:' + LowerCase(StringReplace(Txt(N), ' ', '', [rfReplaceAll])), 0);
  end
  else if N.NodeType = 'identifier' then
  begin
    X:= LowerCase(Txt(N));
    if FLenAlias.TryGetValue(X, Al) then
      Result:= ArrFn(Copy(Al, 1, Pos(':', Al) - 1), Copy(Al, Pos(':', Al) + 1, MaxInt))
    else if WritesOf(X) = 0 then
      Result:= MkSym('id:' + X, 0)
    else if Stable and IsOwnLocal(X) and not TouchedIn(X, FStableFrom, FStableTo) then
      Result:= MkSym('id:' + X, 0);
  end
  else if N.NodeType = 'exprBinary' then
  begin
    Op:= OperatorType(N);
    if (Op <> 'kAdd') and (Op <> 'kSub') then Exit;
    A:= SymOf(N.ChildByField('lhs'));
    B:= SymOf(N.ChildByField('rhs'));
    if not (A.Ok and B.Ok) then Exit;
    if Op = 'kAdd' then
    begin
      if A.Base = '' then Result:= MkSym(B.Base, A.Off + B.Off)
      else if B.Base = '' then Result:= MkSym(A.Base, A.Off + B.Off);
    end
    else if B.Base = '' then Result:= MkSym(A.Base, A.Off - B.Off)
    else if A.Base = B.Base then Result:= MkSym('', A.Off - B.Off);
  end;
end;

{ Length(AArr) in the current routine: a static array's size; for a dynamic one the size every
  SetLength(AArr, n) of the routine agrees on (none: Length itself, or the file-wide size of a
  non-local); unknown when the routine also assigns, Deletes from or Inserts into it. }
function TBnRun.LenSymOf(const AArr: string): TSym;
var
  Info : TDeclInfo;
  Have : Boolean;
  Bad  : Boolean;
  Found: TSym;
  Assigns: Integer;
  SavedFrom: Cardinal;

  procedure Walk(const N: TTSNode);
  var
    I, J: Integer;
    Fn: string;
    Args: TTSNode;
    S: TSym;
  begin
    if N.IsNull or Bad then Exit;
    if (N.NodeType = 'lambda') or (N.NodeType = 'defProc') then Exit;
    if (N.NodeType = 'assignment') and (AssignTarget(N) = AArr) then
    begin
      { 1.52 BK-RULEFP (Pipes.Protocol:1069, Blueprint4:1722): `A := nil` before any SetLength is no
        size the rule relies on; ONE whole assignment outside a loop (and no SetLength) fixes Length(A).
        1.52 IDXRANGE3: `A := F(P)` whose routine sizes Result by P counts as SetLength(A, P.Count) }
      S:= CalleeResultLen(Peeled(N.ChildByField('rhs')));
      if S.Ok then
      begin
        if Have and ((S.Base <> Found.Base) or (S.Off <> Found.Off)) then Bad:= True
        else
        begin
          Found:= S;
          Have:= True;
        end;
      end
      else if IsInLoop(N) then Bad:= True
      else if Have or not MatchText(Trim(Txt(N.ChildByField('rhs'))), ['nil', '[]']) then Inc(Assigns);
    end
    else if N.NodeType = 'exprCall' then
    begin
      Fn:= BareIdent(N.ChildByField('entity'));
      Args:= N.ChildByField('args');
      if (not Args.IsNull) and (Args.NamedChildCount >= 2) then
      begin
        if (Fn = 'setlength') and (BareIdent(Args.NamedChild(0)) = AArr) then
        begin
          S:= SymOf(Args.NamedChild(1));
          if (not S.Ok) or (Have and ((S.Base <> Found.Base) or (S.Off <> Found.Off))) then
            Bad:= True
          else
          begin
            Found:= S;
            Have:= True;
          end;
        end
        else if ((Fn = 'delete') and (BareIdent(Args.NamedChild(0)) = AArr))
          or ((Fn = 'insert') and (BareIdent(Args.NamedChild(1)) = AArr)) then
          Bad:= True
        else
          { 1.52 IDXRANGE3 (YADF.Layout:2638): a call whose routine sizes this out / var argument by
            another argument's Count / Length first (CalleeSizes) counts as that SetLength }
          for J:= 0 to Args.NamedChildCount - 1 do
            if BareIdent(Args.NamedChild(J)) = AArr then
            begin
              S:= CalleeArgLen(N, IntToStr(J));
              if not S.Ok then Continue;
              if Have and ((S.Base <> Found.Base) or (S.Off <> Found.Off)) then Bad:= True
              else
              begin
                Found:= S;
                Have:= True;
              end;
            end;
      end;
    end;
    for I:= 0 to N.ChildCount - 1 do Walk(N.Child(I));
  end;

begin
  if FLenCache.TryGetValue(AArr, Result) then Exit;
  if Lookup(AArr, Info) and (Info.Kind = dkArray) then
    Result:= MkSym('', Info.Hi - Info.Lo + 1)
  else
  begin
    FLenCache.AddOrSetValue(AArr, Default(TSym));  { a SetLength cycle reads unknown }
    Have := False;
    Bad  := False;
    Assigns:= 0;
    Found:= Default(TSym);
    SavedFrom:= FStableFrom;
    FStableFrom:= 0;  { cached per routine: no window-dependent symbol }
    try
      if not FCurProc.IsNull then Walk(FCurProc.ChildByField('body'));
    finally
      FStableFrom:= SavedFrom;
    end;
    if (Assigns > 1) or ((Assigns = 1) and Have) then Bad:= True;
    if Bad then Result:= Default(TSym)
    else if Have then Result:= Found
    else if InScopes(AArr) and not FScopes[FScopes.Count - 1].ContainsKey(AArr) then
    begin
      Result:= OuterLenOf(AArr);  { 1.52 IDXRANGE3: an array of an enclosing routine }
      if not Result.Ok then Result:= MkSym('len:' + AArr, 0);
    end
    else if InScopes(AArr) or (AArr = 'result') then Result:= MkSym('len:' + AArr, 0)
    else Result:= FileLenOf(AArr);
  end;
  FLenCache.AddOrSetValue(AArr, Result);
end;

{ The size every SetLength(AArr, ...) of the FILE agrees on, for a field / global array. Only sizes
  that read the same in any routine count: `X.Count`, `Length(X)`, a constant. }
function TBnRun.FileLenOf(const AArr: string): TSym;
var
  Have : Boolean;
  Bad  : Boolean;
  Found: TSym;

  function RawSize(const A2: TTSNode): TSym;
  var
    V: Integer;
    Args: TTSNode;
  begin
    Result:= Default(TSym);
    if (A2.NodeType = 'exprDot') and (BareIdent(A2.ChildByField('lhs')) <> '')
      and SameText(Trim(Txt(A2.ChildByField('rhs'))), 'count') then
      Exit(MkSym('cnt:' + BareIdent(A2.ChildByField('lhs')), 0));
    Args:= A2.ChildByField('args');
    if (A2.NodeType = 'exprCall') and (BareIdent(A2.ChildByField('entity')) = 'length') and (not Args.IsNull)
      and (Args.NamedChildCount = 1) and (BareIdent(Args.NamedChild(0)) <> '') then
      Exit(MkSym('len:' + BareIdent(Args.NamedChild(0)), 0));
    if EvalIndex(A2, V) then Result:= MkSym('', V);
  end;

  procedure Walk(const N: TTSNode);
  var
    I: Integer;
    Fn: string;
    Args: TTSNode;
    S: TSym;
  begin
    if N.IsNull or Bad then Exit;
    if (N.NodeType = 'assignment') and (AssignTarget(N) = AArr) then
      Bad:= True
    else if N.NodeType = 'exprCall' then
    begin
      Fn:= BareIdent(N.ChildByField('entity'));
      Args:= N.ChildByField('args');
      if (not Args.IsNull) and (Args.NamedChildCount >= 2) then
      begin
        if (Fn = 'setlength') and (BareIdent(Args.NamedChild(0)) = AArr) then
        begin
          S:= RawSize(Args.NamedChild(1));
          if (not S.Ok) or (Have and ((S.Base <> Found.Base) or (S.Off <> Found.Off))) then
            Bad:= True
          else
          begin
            Found:= S;
            Have:= True;
          end;
        end
        else if ((Fn = 'delete') and (BareIdent(Args.NamedChild(0)) = AArr))
          or ((Fn = 'insert') and (BareIdent(Args.NamedChild(1)) = AArr)) then
          Bad:= True;
      end;
    end;
    for I:= 0 to N.ChildCount - 1 do Walk(N.Child(I));
  end;

begin
  if FFileLen.TryGetValue(AArr, Result) then Exit;
  Have := False;
  Bad  := False;
  Found:= Default(TSym);
  Walk(FRoot);
  if Bad then Result:= Default(TSym)
  else if Have then Result:= Found
  else Result:= MkSym('len:' + AArr, 0);
  FFileLen.Add(AArr, Result);
end;

{ The highest valid index of AArr as a symbolic integer. }
function TBnRun.HighSym(const AArr: string; const AInfo: TDeclInfo): TSym;
begin
  if AInfo.Kind = dkArray then Exit(MkSym('', AInfo.Hi));
  Result:= LenSymOf(AArr);
  if Result.Ok then Dec(Result.Off);
end;

{ The least Length the local callers give the open / dynamic parameter array AArr of the current
  routine (each passes a static array or one sized by a constant SetLength); 0 when unknown. }
function TBnRun.MinLenOf(const AArr: string): Integer;
var
  Sites: TList<TTSNode>;
  Site, Callee, Caller, Args: TTSNode;
  P: Integer;
  Key, X: string;
  Saved: TBnSaved;
  L: TSym;
begin
  Result:= 0;
  if (FTraceDepth > 0) or FCurProc.IsNull then Exit;
  Callee:= FCurProc;
  Key:= IntToStr(Callee.StartByte) + ':' + AArr;
  if FMinLen.TryGetValue(Key, Result) then Exit;
  FMinLen.Add(Key, 0);
  P:= IndexStr(AArr, ParamNames(Callee));
  if (P < 0) or not LocalCalls(Callee, Sites) then Exit;
  Result:= MaxInt;
  for Site in Sites do
  begin
    Args:= Site.ChildByField('args');
    Caller:= EnclosingProc(Site);
    if Args.IsNull or (P >= Args.NamedChildCount) or Caller.IsNull then Exit(0);
    X:= BareIdent(Args.NamedChild(P));
    if X = '' then Exit(0);
    EnterRoutine(Caller, Saved);
    try
      L:= LenSymOf(X);
    finally
      LeaveRoutine(Saved);
    end;
    if not (L.Ok and (L.Base = '')) then Exit(0);
    if L.Off < Result then Result:= L.Off;
  end;
  FMinLen.AddOrSetValue(Key, Result);
end;

{ idx <= U keeps idx within AArr's upper bound. }
function TBnRun.UpperWithin(const U: TSym; const AArr: string; const AInfo: TDeclInfo): Boolean;
var
  H, D: TSym;
  MinC, G: Integer;
  OtherLen: Boolean;
begin
  H:= HighSym(AArr, AInfo);
  MinC:= 0;
  if H.Ok and (H.Base = 'len:' + AArr) then
  begin
    MinC:= MinLenOf(AArr);
    G:= GuardMinLen(AArr);  { 1.52 BK-RULEFP: a dominating `if Length(A) < K then raise` }
    if G > MinC then MinC:= G;
  end;
  Result:= SymLE(U, H, MinC);
  if (not Result) and (AInfo.Kind <> dkArray) then
  begin
    { 1.52 BK-RULEFP: the size the dominating SetLength gives, when the routine sizes it twice }
    D:= DomLenOf(AArr);
    if D.Ok then Dec(D.Off);
    Result:= SymLE(U, D, 0);
  end;
  { 1.52 IDXRANGE3 (ShapesMatch): another array's length that a dominating guard made equal }
  { 1.52 IDXRANGE3 (ShapesMatch, uPdfScanRescan:523): another array's length made equal to this one's by a
    dominating guard or by the same SetLength size: High(AArr) is that length - 1 }
  OtherLen:= U.Ok and StartsText(LEN_BASE, U.Base) and (AInfo.Kind <> dkArray);
  if (not Result) and OtherLen and EqualLenGuard(Copy(U.Base, Length(LEN_BASE) + 1, MaxInt), AArr) then
    Result:= U.Off <= -1;
end;

{ E (or E -/+ k) names ANOTHER collection's bound: Length / High of another array or string,
  X.Count, or a local alias of another array's Length / High. }
function TBnRun.ForeignBound(const E: TTSNode; const AArr: string): Boolean;
var
  N, Args: TTSNode;
  Fn, Al: string;
begin
  Result:= False;
  N:= E;
  while (not N.IsNull) and (N.NodeType = 'exprParens') and (N.NamedChildCount = 1) do N:= N.NamedChild(0);
  if (not N.IsNull) and (N.NodeType = 'exprBinary') and ((OperatorType(N) = 'kSub') or (OperatorType(N) = 'kAdd')) then
    N:= N.ChildByField('lhs');
  while (not N.IsNull) and (N.NodeType = 'exprParens') and (N.NamedChildCount = 1) do N:= N.NamedChild(0);
  if N.IsNull then Exit;
  if N.NodeType = 'exprCall' then
  begin
    Fn:= BareIdent(N.ChildByField('entity'));
    Args:= N.ChildByField('args');
    Result:= ((Fn = 'length') or (Fn = 'high')) and (not Args.IsNull) and (Args.NamedChildCount = 1)
      and (BareIdent(Args.NamedChild(0)) <> '') and (BareIdent(Args.NamedChild(0)) <> AArr);
  end
  else if N.NodeType = 'exprDot' then
    Result:= (BareIdent(N.ChildByField('lhs')) <> '') and SameText(Trim(Txt(N.ChildByField('rhs'))), 'count')
  else if N.NodeType = 'identifier' then
    Result:= FLenAlias.TryGetValue(LowerCase(Txt(N)), Al) and not EndsText(':' + AArr, Al);
end;

{ A dominating upper guard against another collection's bound that did not prove the side: keep
  the first one for the message, the local-caller check and (AFor) the report site. }
procedure TBnRun.NoteForeign(var ACtx: TIdxCtx; const E: TTSNode; AStrict: Boolean; const AFor: TTSNode);
begin
  if (ACtx.FgnText <> '') or not ForeignBound(E, ACtx.Arr) then Exit;
  ACtx.FgnText:= Trim(Txt(E));
  ACtx.FgnSym := SymOf(E);
  if AStrict and ACtx.FgnSym.Ok then Dec(ACtx.FgnSym.Off);
  ACtx.FgnNode:= AFor;
end;

{ The upper bound condition C proves for AIdx (ANegate: the bound of `not C`), as idx <= AU. }
function TBnRun.CondUpperSym(const C: TTSNode; const AIdx: string; ANegate: Boolean; out AU: TSym): Boolean;
var
  E, Other: TTSNode;
  Op: string;
begin
  Result:= False;
  AU:= Default(TSym);
  E:= C;
  while (not E.IsNull) and (E.NodeType = 'exprParens') and (E.NamedChildCount = 1) do E:= E.NamedChild(0);
  if E.IsNull then Exit;
  if (E.NodeType = 'exprUnary') and (OperatorType(E) = 'kNot') then
    Exit(CondUpperSym(E.ChildByField('operand'), AIdx, not ANegate, AU));
  if E.NodeType <> 'exprBinary' then Exit;
  Op:= OperatorType(E);
  if ((Op = 'kAnd') and not ANegate) or ((Op = 'kOr') and ANegate) then
    Exit(CondUpperSym(E.ChildByField('lhs'), AIdx, ANegate, AU) or CondUpperSym(E.ChildByField('rhs'), AIdx, ANegate, AU));
  if BareIdent(E.ChildByField('lhs')) = AIdx then
    Other:= E.ChildByField('rhs')
  else if BareIdent(E.ChildByField('rhs')) = AIdx then
  begin
    Other:= E.ChildByField('lhs');
    Op:= MirrorOp(Op);
  end
  else
    Exit;
  if ANegate then Op:= NegateOp(Op);
  if (Op <> 'kLte') and (Op <> 'kLt') then Exit;
  AU:= SymOf(Other);
  if AU.Ok and (Op = 'kLt') then Dec(AU.Off);
  Result:= AU.Ok;
end;

{ W adds exactly 1 to AIdx: `Inc(idx)` or `idx := idx + 1`. }
function TBnRun.StepWrite(const W: TTSNode; const AIdx: string): Boolean;
var
  Args, Rhs: TTSNode;
  K: Integer;
begin
  if W.NodeType = 'exprCall' then
  begin
    Args:= W.ChildByField('args');
    Exit((BareIdent(W.ChildByField('entity')) = 'inc') and (not Args.IsNull) and (Args.NamedChildCount = 1));
  end;
  Result:= False;
  if W.NodeType <> 'assignment' then Exit;
  Rhs:= W.ChildByField('rhs');
  Result:= (not Rhs.IsNull) and (Rhs.NodeType = 'exprBinary') and (OperatorType(Rhs) = 'kAdd')
    and (BareIdent(Rhs.ChildByField('lhs')) = AIdx) and EvalIndex(Rhs.ChildByField('rhs'), K) and (K = 1);
end;

{ ORM3 GAGEFRM2:417: a step `Inc(idx)` followed at once by `if <idx too big> then ... Exit`. Past
  that if, idx <= AU; AInThen: the access sits in that if's then-branch (idx is AU + 1 at most). }
function TBnRun.ExitCap(const ACtx: TIdxCtx; const W: TTSNode; out AU: TSym; out AInThen: Boolean): Boolean;
var
  S, P, ThenN: TTSNode;
begin
  Result:= False;
  AInThen:= False;
  AU:= Default(TSym);
  if not StepWrite(W, ACtx.Idx) then Exit;
  S:= W;
  P:= S.Parent;
  while (not P.IsNull) and (P.NodeType <> 'block') and (P.NodeType <> 'statements') and (P.NodeType <> 'defProc') do
  begin
    S:= P;
    P:= S.Parent;
  end;
  if P.IsNull or (P.NodeType = 'defProc') then Exit;
  S:= S.NextNamedSibling;
  while (not S.IsNull) and IsTrivia(S) do S:= S.NextNamedSibling;
  if S.IsNull or (S.NodeType <> 'if') then Exit;
  ThenN:= S.ChildByField('then');
  if (not IsLeaveStmt(ThenN)) or not CondUpperSym(S.ChildByField('condition'), ACtx.Idx, True, AU) then Exit;
  AInThen:= (ACtx.Access.StartByte >= ThenN.StartByte) and (ACtx.Access.EndByte <= ThenN.EndByte);
  Result:= True;
end;

{ The largest value an assignment `idx := e` leaves, e as a symbolic integer. }
function TBnRun.WriteUpper(const W: TTSNode; out AU: TSym): Boolean;
var
  F: TTSNode;
  I: Integer;
  IsDown: Boolean;
begin
  AU:= Default(TSym);
  if W.NodeType <> 'assignment' then Exit(False);
  { 1.52 IDXRANGE3 (YADF.Layout:8066): `x := i` inside `for i := s to e`: at most e }
  begin
    F:= ForOfCounter(BareIdent(W.ChildByField('rhs')), W);
    if not F.IsNull then
    begin
      IsDown:= False;
      for I:= 0 to F.ChildCount - 1 do
        if F.Child(I).NodeType = 'kDownto' then IsDown:= True;
      AU:= SymOf(if IsDown then F.ChildByField('start').ChildByField('rhs') else F.ChildByField('end'));
    end
    else AU:= SymOf(W.ChildByField('rhs'));
  end;
  Result:= AU.Ok;
end;

{ The upper side from the reaching writes: each keeps it (WriteKeeps), leaves a value within the
  array, or is an Exit-capped step. An access inside the cap's then-branch sees cap + 1, which is
  safe when every other reaching write stays within the cap. }
function TBnRun.UpperSides(const ACtx: TIdxCtx; const AReach: TList<TTSNode>): Boolean;
var
  W, Capped: TTSNode;
  U, CapU: TSym;
  InThen: Boolean;
  MinC: Integer;
begin
  Result:= False;
  if AReach.Count = 0 then Exit;
  Capped:= Default(TTSNode);
  CapU:= Default(TSym);
  for W in AReach do
  begin
    if ExitCap(ACtx, W, U, InThen) then
    begin
      if InThen then
      begin
        if not Capped.IsNull then Exit;
        Capped:= W;
        CapU:= U;
        Continue;
      end;
      if UpperWithin(U, ACtx.Arr, ACtx.Info) then Continue;
    end;
    if WriteKeeps(ACtx, W, False) then Continue;
    if WriteUpper(W, U) and UpperWithin(U, ACtx.Arr, ACtx.Info) then Continue;
    Exit;
  end;
  if Capped.IsNull then Exit(True);
  if not UpperWithin(MkSym(CapU.Base, CapU.Off + 1), ACtx.Arr, ACtx.Info) then Exit;
  MinC:= if CapU.Base = 'len:' + ACtx.Arr then MinLenOf(ACtx.Arr) else 0;
  for W in AReach do
  begin
    if W = Capped then Continue;
    if ExitCap(ACtx, W, U, InThen) and (not InThen) and SymLE(U, CapU, MinC) then Continue;
    if WriteUpper(W, U) and SymLE(U, CapU, MinC) then Continue;
    Exit;
  end;
  Result:= True;
end;

{ ORM3 BASICSF:1394: `while A[i] .. and (i <= G) do Inc(i)` reads A[i] before the bound -- G + 1 at
  most when every write in the loop is a step of 1 and every write outside it stays within A. }
function TBnRun.OnePastWhile(const ACtx: TIdxCtx): Boolean;
var
  C, P, Wh, W: TTSNode;
  G, U: TSym;
begin
  Result:= False;
  if ACtx.IdxInfo.IsParam then Exit;
  Wh:= Default(TTSNode);
  C:= ACtx.Access;
  P:= C.Parent;
  while (not P.IsNull) and (P.NodeType <> 'block') and (P.NodeType <> 'statements') and (P.NodeType <> 'defProc') do
  begin
    if (P.NodeType = 'while') and (P.ChildByField('condition') = C) then
    begin
      Wh:= P;
      Break;
    end;
    C:= P;
    P:= C.Parent;
  end;
  if Wh.IsNull or not CondUpperSym(Wh.ChildByField('condition'), ACtx.Idx, False, G) then Exit;
  for W in ACtx.Writes do
    if (W.StartByte >= Wh.StartByte) and (W.EndByte <= Wh.EndByte) then
    begin
      if not StepWrite(W, ACtx.Idx) then Exit;
    end
    else if not (WriteKeeps(ACtx, W, False) or (WriteUpper(W, U) and UpperWithin(U, ACtx.Arr, ACtx.Info))) then
      Exit;
  Result:= UpperWithin(MkSym(G.Base, G.Off + 1), ACtx.Arr, ACtx.Info);
end;

{ ---- 1.52 BK-RULEFP: the FP classes of the IDXRANGE2 12-sample ------------- }

const
  MAX_CONST_DEPTH = 4;  { local -> its one write -> ... : how far UpperConstOf / LowerConstOf follow }

{ Every write of ACtx.Idx between AFrom and the access keeps the lower (ALower) / upper side by itself
  (Inc or idx + k for the lower, Dec or idx - k for the upper): a guard fact on that side survives. }
function TBnRun.KeepsSince(const ACtx: TIdxCtx; AFrom: Cardinal; ALower: Boolean): Boolean;
var
  W: TTSNode;
begin
  Result:= True;
  for W in ACtx.Writes do
    if (W.StartByte > AFrom) and (W.StartByte < ACtx.Access.StartByte) and not WriteKeeps(ACtx, W, ALower) then Exit(False);
end;

{ YADF.Tokens:208: a leave-guard `if <fail> then Exit` followed by writes of idx -- each side the
  guard proves still holds when every later write keeps that side (`if j < 0 then Exit; Inc(j)`). }
procedure TBnRun.ApplyKeptGuard(var ACtx: TIdxCtx; const ACond: TTSNode; AFrom: Cardinal);
var
  Tmp: TIdxCtx;
begin
  Tmp:= ACtx;
  Tmp.Lo:= False;
  Tmp.Hi:= False;
  CondFacts(Tmp, ACond, True);
  if Tmp.Lo and KeepsSince(ACtx, AFrom, True) then ACtx.Lo:= True;
  if Tmp.Hi and KeepsSince(ACtx, AFrom, False) then ACtx.Hi:= True;
end;

{ STATS:1988: AThen is `idx := e` (alone, or the only statement of a block) with e inside the array on
  both sides -- after `if c then idx := e` either `not c` holds or idx = e. }
function TBnRun.IsClampOf(const AThen: TTSNode; const ACtx: TIdxCtx): Boolean;
var
  N: TTSNode;
  I, Cnt: Integer;
begin
  Result:= False;
  N:= AThen;
  if N.IsNull then Exit;
  if N.NodeType = 'block' then
  begin
    Cnt:= 0;
    for I:= 0 to AThen.NamedChildCount - 1 do
      if not IsTrivia(AThen.NamedChild(I)) then
      begin
        Inc(Cnt);
        N:= AThen.NamedChild(I);
      end;
    if Cnt <> 1 then Exit;
  end;
  Result:= (N.NodeType = 'assignment') and (AssignTarget(N) = ACtx.Idx)
    and WriteKeeps(ACtx, N, True) and WriteKeeps(ACtx, N, False);
end;

{ STATS:1988: `idx in [a, b, c..d]` with constant elements -- the least element proves the lower
  side, the greatest the upper side. }
procedure TBnRun.SetFacts(var ACtx: TIdxCtx; const E: TTSNode);
var
  MinV, MaxV: Integer;
begin
  if (BareIdent(E.ChildByField('lhs')) <> ACtx.Idx) or not SetRange(E.ChildByField('rhs'), MinV, MaxV) then Exit;
  if MinV >= (if ACtx.Info.Kind = dkArray then ACtx.Info.Lo else 0) then ACtx.Lo:= True;
  if UpperWithin(MkSym('', MaxV), ACtx.Arr, ACtx.Info) then ACtx.Hi:= True;
end;

{ `[a, b, c..d]` with constant elements: its least and greatest element (False for anything else or
  an empty set). }
function TBnRun.SetRange(const S: TTSNode; out AMin, AMax: Integer): Boolean;
var
  El: TTSNode;
  I, V, V2: Integer;
begin
  Result:= False;
  AMin:= MaxInt;
  AMax:= -MaxInt;
  if S.IsNull or (S.NodeType <> 'exprBrackets') then Exit;
  for I:= 0 to S.NamedChildCount - 1 do
  begin
    El:= S.NamedChild(I);
    if IsTrivia(El) then Continue;
    if El.NodeType = 'range' then
    begin
      if (El.NamedChildCount < 2) or not (EvalIndex(El.NamedChild(0), V) and EvalIndex(El.NamedChild(1), V2)) then Exit(False);
    end
    else if EvalIndex(El, V) then
      V2:= V
    else
      Exit(False);
    if V < AMin then AMin:= V;
    if V2 > AMax then AMax:= V2;
    Result:= True;
  end;
end;

{ E (parentheses peeled) is a parameter of the current routine that the routine never writes. }
function TBnRun.IsUnwrittenParam(const E: TTSNode): Boolean;
var
  N: TTSNode;
begin
  Result:= False;
  N:= E;
  while (not N.IsNull) and (N.NodeType = 'exprParens') and (N.NamedChildCount = 1) do N:= N.NamedChild(0);
  if N.IsNull or (N.NodeType <> 'identifier') or FCurProc.IsNull then Exit;
  Result:= (IndexStr(LowerCase(Txt(N)), ParamNames(FCurProc)) >= 0) and (WritesOf(LowerCase(Txt(N))) = 0);
end;

{ uINSPRSLT:1871: a const of the current routine's own declaration section with an integer literal
  value (`const HIST_BINS = 9;` before the body). }
function TBnRun.RoutineConst(const AName: string; out AValue: Integer): Boolean;
var
  Stack: TList<TTSNode>;
  N, Val: TTSNode;
  I: Integer;
begin
  Result:= False;
  AValue:= 0;
  if FCurProc.IsNull then Exit;
  Stack:= TList<TTSNode>.Create;
  try
    Stack.Add(FCurProc);
    while Stack.Count > 0 do
    begin
      N:= Stack.Last;
      Stack.Delete(Stack.Count - 1);
      if (N.NodeType = 'block') or (N.NodeType = 'lambda') or ((N.NodeType = 'defProc') and not (N = FCurProc)) then Continue;  // dl:ok nonminimal-bool@d04b -- REVIEWED 2026-11-18 BK-RULEFP: TTSNode declares Equal but no NotEqual; <> does not compile
      if (N.NodeType = 'declConst') and (LowerCase(Txt(N.ChildByField('name'))) = AName) then
      begin
        Val:= N.ChildByField('defaultValue');
        Exit((not Val.IsNull) and (Val.NamedChildCount >= 1) and TryStrToInt(Txt(Val.NamedChild(Val.NamedChildCount - 1)), AValue));
      end;
      for I:= 0 to N.ChildCount - 1 do Stack.Add(N.Child(I));
    end;
  finally
    Stack.Free;
  end;
end;

{ uINSPRSLT:1871: AName as a const / var array of ANOTHER unit, read from the index (lint --db): its
  static bounds. Every same-named const / var row must be an array with the same bounds. Cached. }
function TBnRun.StoreArray(const AName: string; out AInfo: TDeclInfo): Boolean;
var
  S: TSymbol;
  Lo, Hi: Integer;
  Have: Boolean;
begin
  AInfo:= Default(TDeclInfo);
  if FStore = nil then Exit(False);
  if not FStoreArr.TryGetValue(AName, AInfo) then
  begin
    Have:= False;
    for S in FStore.FindSymbolsByExactName(AName) do
    begin
      if S.Kind not in [skConstDecl, skVarDecl] then Continue;
      if (ClassifyType(S.Signature, Lo, Hi) <> dkArray) or (Have and ((Lo <> AInfo.Lo) or (Hi <> AInfo.Hi))) then
      begin
        AInfo:= Default(TDeclInfo);
        Break;
      end;
      AInfo.Kind:= dkArray;
      AInfo.Lo:= Lo;
      AInfo.Hi:= Hi;
      Have:= True;
    end;
    FStoreArr.Add(AName, AInfo);
  end;
  Result:= AInfo.Kind = dkArray;
end;

{ uINSPRSLT:1871: the greatest value E can take -- a constant (also Length / High of a static or
  foreign const array), an if-expression of such, or a local written ONCE (outside any loop, before
  the access) from such an expression. }
function TBnRun.UpperConstOf(const E: TTSNode; ADepth: Integer; out AValue: Integer): Boolean;
var
  N: TTSNode;
  S: TSym;
  A, B: Integer;
  L: TList<TTSNode>;
  X: string;
begin
  Result:= False;
  AValue:= 0;
  N:= E;
  while (not N.IsNull) and (N.NodeType = 'exprParens') and (N.NamedChildCount = 1) do N:= N.NamedChild(0);
  if N.IsNull or (ADepth > MAX_CONST_DEPTH) then Exit;
  S:= SymOf(N);
  if S.Ok and (S.Base = '') then
  begin
    AValue:= S.Off;
    Exit(True);
  end;
  if N.NodeType = 'exprIf' then
  begin
    if UpperConstOf(N.ChildByField('then'), ADepth + 1, A) and UpperConstOf(N.ChildByField('else'), ADepth + 1, B) then
    begin
      AValue:= if A > B then A else B;
      Result:= True;
    end;
    Exit;
  end;
  if N.NodeType <> 'identifier' then Exit;
  X:= LowerCase(Txt(N));
  if (not NodeWithin(FAccess, FCurProc)) or (IndexStr(X, ParamNames(FCurProc)) >= 0) or not InScopes(X) then Exit;
  L:= TList<TTSNode>.Create;
  try
    CollectIdxWrites(FCurProc.ChildByField('body'), X, L);
    if (L.Count = 1) and (L[0].NodeType = 'assignment') and (L[0].EndByte <= FAccess.StartByte) and not IsInLoop(L[0]) then
      Result:= UpperConstOf(L[0].ChildByField('rhs'), ADepth + 1, AValue);
  finally
    L.Free;
  end;
end;

{ Blueprint4:2009: the least value E can take -- a constant, x + k / x - k of such, or a local whose
  every write is a constant-valued assignment or a step up (Inc, x := x + k with k >= 0). }
function TBnRun.LowerConstOf(const E: TTSNode; ADepth: Integer; out AValue: Integer): Boolean;
var
  N: TTSNode;
  K, V: Integer;
  X, Op: string;
begin
  Result:= False;
  AValue:= 0;
  N:= E;
  while (not N.IsNull) and (N.NodeType = 'exprParens') and (N.NamedChildCount = 1) do N:= N.NamedChild(0);
  if N.IsNull or (ADepth > MAX_CONST_DEPTH) then Exit;
  if EvalIndex(N, V) then
  begin
    AValue:= V;
    Exit(True);
  end;
  if N.NodeType = 'exprBinary' then
  begin
    Op:= OperatorType(N);
    if ((Op = 'kAdd') or (Op = 'kSub')) and EvalIndex(N.ChildByField('rhs'), K) and LowerConstOf(N.ChildByField('lhs'), ADepth + 1, V) then
    begin
      AValue:= if Op = 'kAdd' then V + K else V - K;
      Result:= True;
    end;
    Exit;
  end;
  if (N.NodeType <> 'identifier') or FCurProc.IsNull then Exit;
  X:= LowerCase(Txt(N));
  if (IndexStr(X, ParamNames(FCurProc)) >= 0) or not InScopes(X) then Exit;
  Result:= LocalLeast(X, ADepth, AValue);
end;

{ W only raises AX: `Inc(AX)`, `Inc(AX, k)` or `AX := AX + k` with a constant k >= 0. }
function TBnRun.IsStepUp(const W: TTSNode; const AX: string): Boolean;
var
  Args, R: TTSNode;
  K: Integer;
begin
  if W.NodeType = 'exprCall' then
  begin
    Args:= W.ChildByField('args');
    Exit((BareIdent(W.ChildByField('entity')) = 'inc')
      and (Args.IsNull or (Args.NamedChildCount < 2) or (EvalIndex(Args.NamedChild(1), K) and (K >= 0))));
  end;
  Result:= False;
  R:= W.ChildByField('rhs');
  if (W.NodeType <> 'assignment') or (R.NodeType <> 'exprBinary') or (OperatorType(R) <> 'kAdd') then Exit;
  Result:= (BareIdent(R.ChildByField('lhs')) = AX) and EvalIndex(R.ChildByField('rhs'), K) and (K >= 0);
end;

{ The least value the local AX holds: every write is a step up or a constant-valued assignment (the
  least of those counts); at least one assignment. }
function TBnRun.LocalLeast(const AX: string; ADepth: Integer; out AValue: Integer): Boolean;
var
  L: TList<TTSNode>;
  W: TTSNode;
  V: Integer;
begin
  Result:= False;
  AValue:= MaxInt;
  L:= TList<TTSNode>.Create;
  try
    CollectIdxWrites(FCurProc.ChildByField('body'), AX, L);
    for W in L do
      if not IsStepUp(W, AX) then
      begin
        if (W.NodeType <> 'assignment') or not LowerConstOf(W.ChildByField('rhs'), ADepth + 1, V) then Exit(False);
        if V < AValue then AValue:= V;
        Result:= True;
      end;
  finally
    L.Free;
  end;
end;

{ uINSPRSLT:1871: the least Length(AArr) that a dominating `if Length(AArr) < K then <leave>` (also
  `<= K`, `High(AArr) < K`, and either side of an `or`) guarantees at the access under analysis;
  0 when there is none. }
function TBnRun.GuardMinLen(const AArr: string): Integer;
var
  S, E: TTSNode;
  Todo: TList<TTSNode>;
  K, M: Integer;
  Op: string;
begin
  Result:= 0;
  if not NodeWithin(FAccess, FCurProc) then Exit;
  Todo:= TList<TTSNode>.Create;
  try
    LeaveGuardsBefore(FAccess, Todo);
    for K:= 0 to Todo.Count - 1 do
    begin
      S:= Todo[K];
      Todo[K]:= S.ChildByField('condition');
    end;
    while Todo.Count > 0 do
    begin
      E:= Todo.Last;
      Todo.Delete(Todo.Count - 1);
      while (not E.IsNull) and (E.NodeType = 'exprParens') and (E.NamedChildCount = 1) do E:= E.NamedChild(0);
      if E.IsNull or (E.NodeType <> 'exprBinary') then Continue;
      Op:= OperatorType(E);
      if Op = 'kOr' then
      begin
        Todo.Add(E.ChildByField('lhs'));
        Todo.Add(E.ChildByField('rhs'));
        Continue;
      end;
      if not EvalIndex(E.ChildByField('rhs'), K) then Continue;
      M:= 0;
      if IsArrayFn(E.ChildByField('lhs'), 'length', AArr) then
      begin
        if Op = 'kLt' then M:= K
        else if Op = 'kLte' then M:= K + 1;
      end
      else if IsArrayFn(E.ChildByField('lhs'), 'high', AArr) then
      begin
        if Op = 'kLt' then M:= K + 1
        else if Op = 'kLte' then M:= K + 2;
      end;
      if M > Result then Result:= M;
    end;
  finally
    Todo.Free;
  end;
end;

{ N changes AArr's size: `A := ..`, SetLength(A, ..), Delete(A, ..), Insert(.., A, ..). }
function TBnRun.IsSizeChangeOf(const N: TTSNode; const AArr: string): Boolean;
var
  Fn: string;
  Args: TTSNode;
begin
  Result:= False;
  if N.NodeType = 'assignment' then Exit(AssignTarget(N) = AArr);
  if N.NodeType <> 'exprCall' then Exit;
  Fn:= BareIdent(N.ChildByField('entity'));
  Args:= N.ChildByField('args');
  if Args.IsNull or (Args.NamedChildCount < 2) then Exit;
  Result:= (((Fn = 'setlength') or (Fn = 'delete')) and (BareIdent(Args.NamedChild(0)) = AArr))
    or ((Fn = 'insert') and (BareIdent(Args.NamedChild(1)) = AArr));
end;

{ Blueprint4:1722/2009, uBroadcastServer:373: Length(AArr) at the access under analysis from the
  nearest DOMINATING `SetLength(AArr, n)` (an earlier statement of an enclosing statement list) when
  nothing else changes AArr's size between it and the access, nor anywhere in the loops around the
  access that start after it (a trim `SetLength(A, Count)` after the loop does not count). }
function TBnRun.DomSetLength(const AArr: string): TTSNode;
var
  C, P, S, N: TTSNode;
begin
  Result:= Default(TTSNode);
  C:= FAccess;
  P:= C.Parent;
  while (not P.IsNull) and Result.IsNull and (P.NodeType <> 'defProc') and (P.NodeType <> 'lambda') do
  begin
    if (P.NodeType = 'block') or (P.NodeType = 'statements') then
    begin
      S:= C.PrevSibling;
      while (not S.IsNull) and Result.IsNull do
      begin
        N:= S;
        { a statement wrapper node may sit between the list and the call (see IsGrowOf) }
        while (not N.IsNull) and (N.NodeType <> 'exprCall') and (N.NamedChildCount = 1) do N:= N.NamedChild(0);
        if (not N.IsNull) and (N.NodeType = 'exprCall') and (BareIdent(N.ChildByField('entity')) = 'setlength') and IsSizeChangeOf(N, AArr) then Result:= N
        else if S.NodeType = 'try' then Result:= TryBodySetLength(S, AArr);  { 1.52 IDXRANGE3 (Blueprint4.ViewModel:2490) }
        S:= S.PrevSibling;
      end;
    end;
    C:= P;
    P:= C.Parent;
  end;
end;

{ ATry is a try..finally (no except: an exception never falls through past it) whose body holds
  `SetLength(AArr, ..)` as a statement of its own: the last such call (null when there is none). }
function TBnRun.TryBodySetLength(const ATry: TTSNode; const AArr: string): TTSNode;
var
  I, J: Integer;
  HasFinally: Boolean;
  Body, N: TTSNode;
begin
  Result:= Default(TTSNode);
  HasFinally:= False;
  Body:= Default(TTSNode);
  for I:= 0 to ATry.ChildCount - 1 do
  begin
    if ATry.Child(I).NodeType = 'kExcept' then Exit;
    if ATry.Child(I).NodeType = 'kFinally' then HasFinally:= True;
    if Body.IsNull and ((ATry.Child(I).NodeType = 'statements') or (ATry.Child(I).NodeType = 'block')) then Body:= ATry.Child(I);
  end;
  if (not HasFinally) or Body.IsNull then Exit;
  for J:= Body.NamedChildCount - 1 downto 0 do
  begin
    N:= Body.NamedChild(J);
    while (not N.IsNull) and (N.NodeType <> 'exprCall') and (N.NamedChildCount = 1) do N:= N.NamedChild(0);
    if (not N.IsNull) and (N.NodeType = 'exprCall') and (BareIdent(N.ChildByField('entity')) = 'setlength') and IsSizeChangeOf(N, AArr) then Exit(N);
  end;
end;

{ AProc (a nested routine) declares its own AX: a use of AX inside it is no capture. }
function TBnRun.DeclaresLocal(const AProc: TTSNode; const AX: string): Boolean;
var
  Scope: TDictionary<string, TDeclInfo>;
begin
  Scope:= BuildScope(AProc);
  try
    Result:= Scope.ContainsKey(AX);
  finally
    Scope.Free;
  end;
end;

{ Something in the current routine changes AArr's size between the bytes AFrom and ATo. }
function TBnRun.SizeChangedIn(const AArr: string; AFrom, ATo: Cardinal): Boolean;
var
  Stack: TList<TTSNode>;
  N: TTSNode;
  I: Integer;
begin
  Result:= False;
  Stack:= TList<TTSNode>.Create;
  try
    Stack.Add(FCurProc.ChildByField('body'));
    while (Stack.Count > 0) and not Result do
    begin
      N:= Stack.Last;
      Stack.Delete(Stack.Count - 1);
      if N.IsNull or (N.EndByte <= AFrom) or (N.StartByte >= ATo) or (N.NodeType = 'lambda') then Continue;
      { 1.52 IDXRANGE3 (Pipes.Framing:557): `A := nil; Exit` never reaches the access }
      Result:= (N.StartByte >= AFrom) and IsSizeChangeOf(N, AArr)
        and not ((not FAccess.IsNull) and NodeWithin(FAccess, FCurProc) and LeavesBefore(N, FAccess, 0, False));
      for I:= 0 to N.ChildCount - 1 do Stack.Add(N.Child(I));
    end;
  finally
    Stack.Free;
  end;
end;

{ Blueprint4:1722/2009, uBroadcastServer:373: Length(AArr) at the access under analysis from the
  nearest DOMINATING `SetLength(AArr, n)` (an earlier statement of an enclosing statement list) when
  nothing else changes AArr's size between it and the access, nor anywhere in the loops around the
  access that start after it (a trim `SetLength(A, Count)` after the loop does not count). }
function TBnRun.DomLenOf(const AArr: string): TSym;
var
  Found, P: TTSNode;
  Hi: Cardinal;
begin
  Result:= Default(TSym);
  if not NodeWithin(FAccess, FCurProc) then Exit;
  Found:= DomSetLength(AArr);
  if Found.IsNull then Exit;
  Hi:= FAccess.StartByte;
  P:= FAccess.Parent;
  while (not P.IsNull) and (P.StartByte > Found.StartByte) and (P.NodeType <> 'defProc') do
  begin
    if ((P.NodeType = 'while') or (P.NodeType = 'repeat') or (P.NodeType = 'for') or (P.NodeType = 'foreach')) and (P.EndByte > Hi) then Hi:= P.EndByte;
    P:= P.Parent;
  end;
  if not SizeChangedIn(AArr, Found.EndByte, Hi) then Result:= SymOf(Found.ChildByField('args').NamedChild(1));
end;

{ ORM3 Blueprint4:1722: idx starts at a constant before a for loop and takes ONE step per trip (one
  step write, after the access, in no nested loop): at most start + trips - 1 at the access. }
function TBnRun.CountInvariant(const ACtx: TIdxCtx): Boolean;
var
  F, P, W, Step, It, StartE, Init, L: TTSNode;
  AroundF: TList<TTSNode>;
  I, C0, SLo, V: Integer;
  IsDown, HaveInit: Boolean;
  S, E, U, Trips: TSym;
  Info: TDeclInfo;

  function InNestedLoop(const N: TTSNode): Boolean;
  var
    Q: TTSNode;
  begin
    Result:= False;
    Q:= N.Parent;
    while (not Q.IsNull) and not (Q = F) do
    begin
      if (Q.NodeType = 'while') or (Q.NodeType = 'repeat') or (Q.NodeType = 'for') or (Q.NodeType = 'foreach') then Exit(True);
      Q:= Q.Parent;
    end;
  end;

begin
  Result:= False;
  if ACtx.IdxInfo.IsParam then Exit;
  F:= Default(TTSNode);
  P:= ACtx.Access.Parent;
  while (not P.IsNull) and (P.NodeType <> 'defProc') and (P.NodeType <> 'lambda') do
  begin
    if (P.NodeType = 'for') or (P.NodeType = 'foreach') then
    begin
      F:= P;
      Break;
    end;
    if (P.NodeType = 'while') or (P.NodeType = 'repeat') then Exit;
    P:= P.Parent;
  end;
  if F.IsNull or ((F.NodeType = 'for') and (AssignTarget(F.ChildByField('start')) = ACtx.Idx)) then Exit;
  Step:= Default(TTSNode);
  C0:= 0;
  SLo:= 0;
  HaveInit:= False;
  { 1.52 IDXRANGE3 (uBroadcastServer:481/515): the last write before F that dominates it hides the
    earlier ones; a write after F reaches it only through a loop around F }
  Init:= Default(TTSNode);
  for W in ACtx.Writes do
    if (W.EndByte <= F.StartByte) and StmtDominates(W, F) and (Init.IsNull or (W.StartByte > Init.StartByte)) then Init:= W;
  AroundF:= TList<TTSNode>.Create;
  try
    LoopsAround(F, AroundF);
    for W in ACtx.Writes do
      if (W.StartByte >= F.StartByte) and (W.EndByte <= F.EndByte) then
      begin
        if (not Step.IsNull) or (not StepWrite(W, ACtx.Idx)) or (W.StartByte < ACtx.Access.StartByte) or InNestedLoop(W) then Exit;
        Step:= W;
      end
      else if (not Init.IsNull) and (W.StartByte < Init.StartByte) then
        Continue
      else if W.StartByte > F.StartByte then
      begin
        for L in AroundF do
          if NodeWithin(W, L) then Exit;
      end
      else
      begin
        if (not WriteUpper(W, U)) or (U.Base <> '') or (U.Off < 0) then Exit;
        HaveInit:= True;
        if U.Off > C0 then C0:= U.Off;
      end;
  finally
    AroundF.Free;
  end;
  if Step.IsNull or not HaveInit then Exit;
  if F.NodeType = 'foreach' then
  begin
    { 1.52 BK-RULEFP (uBroadcastServer:373): `for x in C` / `C.Keys` / `C.Values` makes C.Count trips,
      `for x in A` Length(A) trips }
    It:= F.ChildByField('iterable');
    while (not It.IsNull) and (It.NodeType = 'exprParens') and (It.NamedChildCount = 1) do It:= It.NamedChild(0);
    if It.IsNull then Exit;
    if (It.NodeType = 'exprDot') and (DottedPath(It.ChildByField('lhs')) <> '')
      and MatchText(Trim(Txt(It.ChildByField('rhs'))), ['keys', 'values']) then
      Trips:= MkSym('cnt:' + DottedPath(It.ChildByField('lhs')), 0)
    else if (It.NodeType = 'identifier') and IsBoundedArray(BareIdent(It), Info) then
    begin
      Trips:= HighSym(BareIdent(It), Info);
      if Trips.Ok then Inc(Trips.Off);
    end
    else if (It.NodeType = 'identifier') and not (Lookup(BareIdent(It), Info) and (Info.Kind = dkString)) then
      Trips:= MkSym('cnt:' + BareIdent(It), 0)
    else
      Exit;
    if not Trips.Ok then Exit;
    Exit(UpperWithin(MkSym(Trips.Base, Trips.Off - 1 + C0), ACtx.Arr, ACtx.Info));
  end;
  IsDown:= False;
  for I:= 0 to F.ChildCount - 1 do
    if F.Child(I).NodeType = 'kDownto' then IsDown:= True;
  StartE:= F.ChildByField('start').ChildByField('rhs');
  S:= SymOf(StartE);
  E:= SymOf(F.ChildByField('end'));
  if not IsDown then
  begin
    { 1.52 BK-RULEFP (Blueprint4:2009): a start that is not a constant counts by its least value;
      1.52 IDXRANGE3: or by the bound its writes and guards give }
    if S.Ok and (S.Base = '') then SLo:= S.Off
    else if not (LowerConstOf(StartE, 0, SLo) or (EvalBound(StartE, F, False, 0, SLo) and not IsNeutralBound(SLo))) then Exit;
    if SelfBoundedFor(ACtx, F, C0, SLo) then Exit(True);  { 1.52 IDXRANGE3: compaction over A itself }
    { 1.52 IDXRANGE3 (FlexDateTime:420): an end that is no symbol counts by its greatest value }
    if (not E.Ok) and EvalBound(F.ChildByField('end'), F, True, 0, V) and not IsNeutralBound(V) then E:= MkSym('', V);
  end;
  if not E.Ok then Exit;
  { start + trips - 1: the steps taken before the access in the last trip }
  if IsDown then
  begin
    if (not S.Ok) or (E.Base <> '') then Exit;
    U:= MkSym(S.Base, S.Off - E.Off + C0);
  end
  else
    U:= MkSym(E.Base, E.Off - SLo + C0);
  Result:= UpperWithin(U, ACtx.Arr, ACtx.Info);
end;

{ ORM3 uJobList:997: `idx := Map.GetValueOrDefault(..)`, `Map.Items[..]`, `Map[k]` -- an index read
  from a lookup whose value range the rule cannot see (reported as a hint). }
function TBnRun.IsLookupWrite(const W: TTSNode; out AText: string): Boolean;
var
  R, Ent: TTSNode;
  Info: TDeclInfo;
  M: string;
begin
  Result:= False;
  AText:= '';
  if W.NodeType <> 'assignment' then Exit;
  R:= W.ChildByField('rhs');
  while (not R.IsNull) and (R.NodeType = 'exprParens') and (R.NamedChildCount = 1) do R:= R.NamedChild(0);
  if R.IsNull then Exit;
  if R.NodeType = 'exprCall' then
  begin
    Ent:= R.ChildByField('entity');
    if Ent.IsNull or (Ent.NodeType <> 'exprDot') then Exit;
    M:= LowerCase(Trim(Txt(Ent.ChildByField('rhs'))));
    Result:= (M = 'getvalueordefault') or (M = 'items');
  end
  else if R.NodeType = 'exprSubscript' then
    Result:= not IsBoundedArray(BareIdent(R.ChildByField('entity')), Info);
  if Result then AText:= Trim(Txt(R));
end;

{ ---- index-possibly-out-of-range: value bounds along the writes (1.52 IDXRANGE3) ---------- }


{ W runs on every path that reaches AAt: W sits, through no control statement, in a statement list
  that holds AAt, and ends before it. }
function TBnRun.StmtDominates(const W, AAt: TTSNode): Boolean;
var
  P: TTSNode;
begin
  Result:= False;
  if W.IsNull or AAt.IsNull or (W.EndByte > AAt.StartByte) then Exit;
  P:= W.Parent;
  while (not P.IsNull) and (P.NodeType <> 'block') and (P.NodeType <> 'statements') do
  begin
    if (IndexStr(P.NodeType, CONTROL_NODES) >= 0) or (P.NodeType = 'defProc') then Exit;
    P:= P.Parent;
  end;
  Result:= NodeWithin(AAt, P);
end;

{ The loops around N inside its routine, innermost first, into AList (cleared); returns their count. }
function TBnRun.LoopsAround(const N: TTSNode; AList: TList<TTSNode>): Integer;
var
  Q: TTSNode;
begin
  AList.Clear;
  Q:= N.Parent;
  while (not Q.IsNull) and (Q.NodeType <> 'defProc') and (Q.NodeType <> 'lambda') do
  begin
    if IsLoopNode(Q) then AList.Add(Q);
    Q:= Q.Parent;
  end;
  Result:= AList.Count;
end;

{ The `for AX := ...` loop whose body holds AAt (null when there is none). }
function TBnRun.ForOfCounter(const AX: string; const AAt: TTSNode): TTSNode;
var
  P: TTSNode;
begin
  Result:= Default(TTSNode);
  P:= AAt.Parent;
  while (not P.IsNull) and (P.NodeType <> 'defProc') and (P.NodeType <> 'lambda') do
  begin
    if (P.NodeType = 'for') and (AssignTarget(P.ChildByField('start')) = AX) and NodeWithin(AAt, P.ChildByField('body')) then Exit(P);
    P:= P.Parent;
  end;
end;

{ AX is a local or a parameter of the routine under analysis. }
function TBnRun.IsOwnLocal(const AX: string): Boolean;
begin
  Result:= (AX <> '') and (FScopes.Count > 0) and FScopes[FScopes.Count - 1].ContainsKey(AX);
end;


{ Something in the routine may change AX (a local / parameter, or the record a field path starts at)
  between the bytes AFrom and ATo: an assignment to it or into it, Inc / Dec, a size change, its
  address taken, a bare pass to a call that may take it by reference, or a use of a pointer that
  was set from its address anywhere in the routine. }
function TBnRun.TouchedIn(const AX: string; AFrom, ATo: Cardinal; AWhole: Boolean): Boolean;  // dl:ok cyclomatic-complexity@52f4, too-many-exit-points@ed2b -- REVIEWED 2026-11-18 IDXRANGE3: one flow pass over the writes in text order; the branches share its per-event state, a split scatters it
var
  Stack, All: TList<TTSNode>;
  Aliases: TList<string>;
  N, Args, Op, Asg: TTSNode;
  I: Integer;
  T, Fn, Al: string;
  IsStmt: Boolean;
begin
  Result:= True;
  if FCurProc.IsNull then Exit;
  Stack:= TList<TTSNode>.Create;
  All:= TList<TTSNode>.Create;
  Aliases:= TList<string>.Create;
  try
    { the pointers set from @AX anywhere in the routine }
    Stack.Add(FCurProc.ChildByField('body'));
    while Stack.Count > 0 do
    begin
      N:= Stack.Last;
      Stack.Delete(Stack.Count - 1);
      if N.IsNull then Continue;
      All.Add(N);
      if (N.NodeType = 'exprUnary') and (OperatorType(N) = 'kAt') and (RootName(Txt(N.ChildByField('operand'))) = AX) then
      begin
        Asg:= N.Parent;
        while (not Asg.IsNull) and (Asg.NodeType <> 'assignment') and (Asg.NodeType <> 'block') and (Asg.NodeType <> 'defProc') do Asg:= Asg.Parent;
        if (not Asg.IsNull) and (Asg.NodeType = 'assignment') and (AssignTarget(Asg) <> '') then Aliases.Add(AssignTarget(Asg));
      end;
      for I:= 0 to N.ChildCount - 1 do Stack.Add(N.Child(I));
    end;
    for N in All do
    begin
      if (N.StartByte < AFrom) or (N.StartByte >= ATo) then Continue;
      T:= N.NodeType;
      if (T = 'assignment') and (RootName(Txt(N.ChildByField('lhs'))) = AX) and ((not AWhole) or (BareIdent(N.ChildByField('lhs')) = AX)) then Exit;
      if (T = 'identifier') and (Aliases.IndexOf(LowerCase(Txt(N))) >= 0) then Exit;
      if (T = 'exprUnary') and (OperatorType(N) = 'kAt') and (RootName(Txt(N.ChildByField('operand'))) = AX)
        and ((not AWhole) or (BareIdent(N.ChildByField('operand')) = AX)) then Exit;
      if (T = 'exprCall') and not (N = FAccess) then  { the call under analysis reads its arguments first }  // dl:ok nonminimal-bool@8aba -- REVIEWED 2026-11-18 IDXRANGE3: TTSNode declares Equal but no NotEqual; <> does not compile
      begin
        { a method of AX may change it }
        if (N.ChildByField('entity').NodeType = 'exprDot') and (RootName(Txt(N.ChildByField('entity'))) = AX)
          and ((not AWhole) or (BareIdent(N.ChildByField('entity').ChildByField('lhs')) = AX)) then Exit;
        Fn:= CallName(N);
        Args:= N.ChildByField('args');
        if Args.IsNull then Continue;
        for I:= 0 to Args.NamedChildCount - 1 do
        begin
          Op:= Peeled(Args.NamedChild(I));
          if Op.IsNull or IsTrivia(Op) or ArgByValue(Fn, I) then Continue;
          Al:= Op.NodeType;
          if ((Al = 'identifier') or ((not AWhole) and ((Al = 'exprDot') or (Al = 'exprSubscript')))) and (RootName(Txt(Op)) = AX) then Exit;
        end;
      end;
      { a parameterless method call statement `AX.Clear;` }
      IsStmt:= (not N.Parent.IsNull) and ((N.Parent.NodeType = 'block') or (N.Parent.NodeType = 'statements'));
      if (T = 'exprDot') and IsStmt
        and (RootName(Txt(N)) = AX) and ((not AWhole) or (BareIdent(N.ChildByField('lhs')) = AX)) then Exit;
    end;
    Result:= False;
  finally
    Aliases.Free;
    All.Free;
    Stack.Free;
  end;
end;

{ The bound condition C (ANegate: `not C`) puts on the local AX: an upper (AUpper) or lower bound
  against a constant, through not / and / or and `AX in [..]`. }
function TBnRun.CondBound(const C: TTSNode; const AX: string; ANegate, AUpper: Boolean; out AV: Integer): Boolean;  // dl:ok too-many-exit-points@2a53, cyclomatic-complexity@f73a -- REVIEWED 2026-11-18 IDXRANGE3: one flow pass over the writes in text order; the branches share its per-event state, a split scatters it
var
  E, Other: TTSNode;
  Op: string;
  A, B, K, V, V2: Integer;
  HaveA, HaveB: Boolean;
  Sy: TSym;
begin
  Result:= False;
  AV:= 0;
  E:= Peeled(C);
  if E.IsNull then Exit;
  if (E.NodeType = 'exprUnary') and (OperatorType(E) = 'kNot') then
    Exit(CondBound(E.ChildByField('operand'), AX, not ANegate, AUpper, AV));
  if E.NodeType <> 'exprBinary' then Exit;
  Op:= OperatorType(E);
  if ((Op = 'kAnd') and not ANegate) or ((Op = 'kOr') and ANegate) then
  begin
    { both hold: either side's bound holds, the tighter wins }
    HaveA:= CondBound(E.ChildByField('lhs'), AX, ANegate, AUpper, A);
    HaveB:= CondBound(E.ChildByField('rhs'), AX, ANegate, AUpper, B);
    if HaveA and HaveB then AV:= TightBound(A, B, AUpper)
    else if HaveA then AV:= A
    else if HaveB then AV:= B
    else Exit;
    Exit(True);
  end;
  if (Op = 'kAnd') or (Op = 'kOr') then
  begin
    { one of them holds: only a bound both sides give }
    if not (CondBound(E.ChildByField('lhs'), AX, ANegate, AUpper, A) and CondBound(E.ChildByField('rhs'), AX, ANegate, AUpper, B)) then Exit;
    AV:= JoinBound(A, B, AUpper);
    Exit(True);
  end;
  if Op = 'kIn' then
  begin
    if ANegate or (BareIdent(E.ChildByField('lhs')) <> AX) or not SetRange(E.ChildByField('rhs'), V, V2) then Exit;
    AV:= if AUpper then V2 else V;
    Exit(True);
  end;
  if BareIdent(E.ChildByField('lhs')) = AX then
    Other:= E.ChildByField('rhs')
  else if BareIdent(E.ChildByField('rhs')) = AX then
  begin
    Other:= E.ChildByField('lhs');
    Op:= MirrorOp(Op);
  end
  else
    Exit;
  if ANegate then Op:= NegateOp(Op);
  if not EvalIndex(Other, K) then
  begin
    Sy:= SymOf(Other);
    if not (Sy.Ok and (Sy.Base = '')) then Exit;
    K:= Sy.Off;
  end;
  if AUpper and (Op = 'kLt') then AV:= K - 1
  else if AUpper and (Op = 'kLte') then AV:= K
  else if (not AUpper) and (Op = 'kGt') then AV:= K + 1
  else if (not AUpper) and (Op = 'kGte') then AV:= K
  else Exit;
  Result:= True;
end;

{ The most trips the for loop ALoop makes, from the bounds of its start and end (0 at least). }
function TBnRun.LoopTrips(const ALoop: TTSNode; ADepth: Integer; out AT: Integer): Boolean;
var
  I, Hi, Lo: Integer;
  IsDown: Boolean;
  S, E: TTSNode;
begin
  Result:= False;
  AT:= 0;
  if ALoop.NodeType <> 'for' then Exit;
  IsDown:= False;
  for I:= 0 to ALoop.ChildCount - 1 do
    if ALoop.Child(I).NodeType = 'kDownto' then IsDown:= True;
  S:= ALoop.ChildByField('start').ChildByField('rhs');
  E:= ALoop.ChildByField('end');
  if not (EvalBound(if IsDown then S else E, ALoop, True, ADepth + 1, Hi) and EvalBound(if IsDown then E else S, ALoop, False, ADepth + 1, Lo)) then Exit;
  if IsNeutralBound(Hi) or IsNeutralBound(Lo) then Exit;
  AT:= if Hi - Lo + 1 > 0 then Hi - Lo + 1 else 0;
  Result:= True;
end;

{ STATS:1779: `Floor(Abs(x) * c + d)` (also Trunc / Round / Ceil, c >= 0) under a dominating guard
  `Abs(x) <= k` (an if branch, or `if Abs(x) > k then Exit`), x never written: the integer range of
  the result -- Abs(x) lies in 0..k. }
function TBnRun.FloatBound(const ACall, AAt: TTSNode; AUpper: Boolean; out AV: Integer): Boolean;  // dl:ok cyclomatic-complexity@edbb -- REVIEWED 2026-11-18 IDXRANGE3: one flow pass over the writes in text order; the branches share its per-event state, a split scatters it
var
  AbsN: TTSNode;
  Cm, Dd, Hi, Val: Double;
  HaveHi: Boolean;
  AbsTxt, Fn: string;

  function Lit(const N: TTSNode; out AF: Double): Boolean;
  var
    P: TTSNode;
  begin
    P:= Peeled(N);
    Result:= (not P.IsNull) and StartsText('literal', P.NodeType) and TryStrToFloat(Trim(Txt(P)), AF, TFormatSettings.Invariant);
  end;

  function OpText(const N: TTSNode): string;
  begin
    Result:= Trim(Txt(N.ChildByField('operator')));
  end;

  { N = AbsN * C + D }
  function Linear(const N0: TTSNode; out AC, AD: Double): Boolean;  // dl:ok too-many-exit-points@4930 -- REVIEWED 2026-11-18 IDXRANGE3: guard clauses per syntax shape; each early exit is a classification
  var
    N: TTSNode;
    F, C1, D1: Double;
    Op: string;
  begin
    Result:= False;
    N:= Peeled(N0);
    AC:= 1;
    AD:= 0;
    if N.IsNull then Exit;
    if (N.NodeType = 'exprCall') and (BareIdent(N.ChildByField('entity')) = 'abs') then
    begin
      if not AbsN.IsNull then Exit;
      AbsN:= N;
      Exit(True);
    end;
    if N.NodeType <> 'exprBinary' then Exit;
    Op:= OpText(N);
    if (Op = '+') or (Op = '-') then
    begin
      if Lit(N.ChildByField('rhs'), F) and Linear(N.ChildByField('lhs'), C1, D1) then
      begin
        AC:= C1;
        AD:= if Op = '+' then D1 + F else D1 - F;
        Exit(True);
      end;
      if (Op = '+') and Lit(N.ChildByField('lhs'), F) and Linear(N.ChildByField('rhs'), C1, D1) then
      begin
        AC:= C1;
        AD:= D1 + F;
        Exit(True);
      end;
    end
    else if Op = '*' then
    begin
      if (Lit(N.ChildByField('rhs'), F) and Linear(N.ChildByField('lhs'), C1, D1))
        or (Lit(N.ChildByField('lhs'), F) and Linear(N.ChildByField('rhs'), C1, D1)) then
      begin
        AC:= C1 * F;
        AD:= D1 * F;
        Exit(True);
      end;
    end;
  end;

  { a comparison of AbsTxt with a literal in C gives Abs(x) <= AHi (ANegate: `not C`) }
  function AbsHi(const C0: TTSNode; ANegate: Boolean; out AHi: Double): Boolean;  // dl:ok too-many-exit-points@dc5e -- REVIEWED 2026-11-18 IDXRANGE3: guard clauses per syntax shape; each early exit is a classification
  var
    E: TTSNode;
    Op: string;
    F, A, B: Double;
    HA, HB, OnLeft: Boolean;
  begin
    Result:= False;
    AHi:= 0;
    E:= Peeled(C0);
    if E.IsNull then Exit;
    if (E.NodeType = 'exprUnary') and (OperatorType(E) = 'kNot') then Exit(AbsHi(E.ChildByField('operand'), not ANegate, AHi));
    if E.NodeType <> 'exprBinary' then Exit;
    Op:= OperatorType(E);
    if ((Op = 'kAnd') and not ANegate) or ((Op = 'kOr') and ANegate) then
    begin
      HA:= AbsHi(E.ChildByField('lhs'), ANegate, A);
      HB:= AbsHi(E.ChildByField('rhs'), ANegate, B);
      if HA and HB then AHi:= if A < B then A else B
      else if HA then AHi:= A
      else if HB then AHi:= B
      else Exit;
      Exit(True);
    end;
    OnLeft:= SameText(StringReplace(Txt(E.ChildByField('lhs')), ' ', '', [rfReplaceAll]), AbsTxt) and Lit(E.ChildByField('rhs'), F);
    if not OnLeft then
    begin
      if not (SameText(StringReplace(Txt(E.ChildByField('rhs')), ' ', '', [rfReplaceAll]), AbsTxt) and Lit(E.ChildByField('lhs'), F)) then Exit;
      Op:= MirrorOp(Op);
    end;
    if ANegate then Op:= NegateOp(Op);
    if (Op <> 'kLt') and (Op <> 'kLte') then Exit;
    AHi:= F;
    Result:= True;
  end;

  { the identifiers inside Abs(..) are never written in the routine }
  function AbsArgFixed(const N: TTSNode): Boolean;
  var
    I: Integer;
  begin
    if N.NodeType = 'identifier' then Exit(WritesOf(LowerCase(Txt(N))) = 0);
    for I:= 0 to N.ChildCount - 1 do
      if not AbsArgFixed(N.Child(I)) then Exit(False);
    Result:= True;
  end;

var
  Args, C, P, S, ThenN: TTSNode;
  G: Double;
begin
  Result:= False;
  AV:= 0;
  Fn:= BareIdent(ACall.ChildByField('entity'));
  Args:= ACall.ChildByField('args');
  if (IndexStr(Fn, FLOAT_ROUNDERS) < 0) or Args.IsNull or (Args.NamedChildCount <> 1) then Exit;
  AbsN:= Default(TTSNode);
  if (not Linear(Args.NamedChild(0), Cm, Dd)) or AbsN.IsNull or (Cm < 0) then Exit;
  if not AbsArgFixed(AbsN.ChildByField('args')) then Exit;
  if not AUpper then
  begin
    Val:= Dd;  { Abs(x) >= 0 }
    AV:= if Fn = 'ceil' then CeilOf(Val) else FloorOf(Val);
    Exit(True);
  end;
  AbsTxt:= StringReplace(Txt(AbsN), ' ', '', [rfReplaceAll]);
  HaveHi:= False;
  Hi:= 0;
  C:= AAt;
  P:= C.Parent;
  while (not P.IsNull) and (P.NodeType <> 'defProc') and (P.NodeType <> 'lambda') do
  begin
    if ((P.NodeType = 'if') or (P.NodeType = 'ifElse')) and ((P.ChildByField('then') = C) or (P.ChildByField('else') = C)) then
    begin
      if AbsHi(P.ChildByField('condition'), P.ChildByField('else') = C, G) and ((not HaveHi) or (G < Hi)) then
      begin
        Hi:= G;
        HaveHi:= True;
      end;
    end
    else if (P.NodeType = 'block') or (P.NodeType = 'statements') then
    begin
      S:= C.PrevSibling;
      while not S.IsNull do
      begin
        ThenN:= S.ChildByField('then');
        if (S.NodeType = 'if') and IsLeaveStmt(ThenN) and AbsHi(S.ChildByField('condition'), True, G) and ((not HaveHi) or (G < Hi)) then
        begin
          Hi:= G;
          HaveHi:= True;
        end;
        S:= S.PrevSibling;
      end;
    end;
    C:= P;
    P:= C.Parent;
  end;
  if not HaveHi then Exit;
  Val:= Cm * Hi + Dd;
  AV:= if (Fn = 'floor') or (Fn = 'trunc') then FloorOf(Val) else CeilOf(Val);
  Result:= True;
end;

{ A bound of the integer expression E as it is evaluated at AAt: a constant, a local or parameter
  (BoundAt), a for counter whose loop holds AAt (its start / end), x + k / x - k, an if-expression,
  a rounded float (FloatBound); Length / Count / Abs are at least 0. }
function TBnRun.EvalBound(const E, AAt: TTSNode; AUpper: Boolean; ADepth: Integer; out AV: Integer): Boolean;  // dl:ok cyclomatic-complexity@970c, too-many-exit-points@6f81 -- REVIEWED 2026-11-18 IDXRANGE3: one flow pass over the writes in text order; the branches share its per-event state, a split scatters it
var
  N, F, L, R, Other: TTSNode;
  K, A, B, I: Integer;
  S: TSym;
  Op, Fn, X: string;
  IsDown, Have: Boolean;

  function NonNeg(const M0: TTSNode): Boolean;
  var
    M: TTSNode;
    V: Integer;
  begin
    M:= Peeled(M0);
    if M.IsNull then Exit(False);
    if EvalIndex(M, V) then Exit(V >= 0);
    if M.NodeType = 'exprCall' then Exit(MatchText(BareIdent(M.ChildByField('entity')), ['length', 'abs']));
    Result:= (M.NodeType = 'exprDot') and SameText(Trim(Txt(M.ChildByField('rhs'))), 'count');
  end;

begin
  Result:= False;
  AV:= 0;
  N:= Peeled(E);
  if N.IsNull or (ADepth > MAX_BOUND_DEPTH) then Exit;
  if EvalIndex(N, AV) then Exit(True);
  S:= SymOf(N);
  if S.Ok and (S.Base = '') then
  begin
    AV:= S.Off;
    Exit(True);
  end;
  if N.NodeType = 'identifier' then
  begin
    X:= LowerCase(Txt(N));
    F:= ForOfCounter(X, AAt);
    if not F.IsNull then
    begin
      IsDown:= False;
      for I:= 0 to F.ChildCount - 1 do
        if F.Child(I).NodeType = 'kDownto' then IsDown:= True;
      { ascending: start .. end; downto: end .. start }
      if AUpper <> IsDown then Exit(EvalBound(F.ChildByField('end'), F, AUpper, ADepth + 1, AV));
      Exit(EvalBound(F.ChildByField('start').ChildByField('rhs'), F, AUpper, ADepth + 1, AV));
    end;
    if IsOwnLocal(X) then Result:= BoundAt(X, AAt, AUpper, ADepth + 1, AV);
    Exit;
  end;
  if N.NodeType = 'exprBinary' then
  begin
    Op:= OperatorType(N);
    if (Op <> 'kAdd') and (Op <> 'kSub') then Exit;
    L:= N.ChildByField('lhs');
    R:= N.ChildByField('rhs');
    Have:= EvalIndex(R, K);
    Other:= L;
    if Have and (Op = 'kSub') then K:= -K;
    if (not Have) and (Op = 'kAdd') and EvalIndex(L, K) then
    begin
      Have:= True;
      Other:= R;
    end;
    if Have then
    begin
      Inc(FBoundOff, K);
      try
        Result:= EvalBound(Other, AAt, AUpper, ADepth + 1, A);
      finally
        Dec(FBoundOff, K);
      end;
      if Result then AV:= ShiftBound(A, K);
      Exit;
    end;
    { a lower bound only: x + (something never negative) }
    if (not AUpper) and (Op = 'kAdd') then
    begin
      if NonNeg(R) then Exit(EvalBound(L, AAt, False, ADepth + 1, AV));
      if NonNeg(L) then Exit(EvalBound(R, AAt, False, ADepth + 1, AV));
    end;
    Exit;
  end;
  if N.NodeType = 'exprIf' then
  begin
    if EvalBound(N.ChildByField('then'), AAt, AUpper, ADepth + 1, A) and EvalBound(N.ChildByField('else'), AAt, AUpper, ADepth + 1, B) then
    begin
      AV:= JoinBound(A, B, AUpper);
      Result:= True;
    end;
    Exit;
  end;
  if N.NodeType = 'exprCall' then
  begin
    Fn:= BareIdent(N.ChildByField('entity'));
    if IndexStr(Fn, FLOAT_ROUNDERS) >= 0 then Exit(FloatBound(N, AAt, AUpper, AV));
    if (not AUpper) and NonNeg(N) then Exit(True);
    if (not AUpper) and (Fn = 'high') then
    begin
      AV:= -1;
      Exit(True);
    end;
    Exit;
  end;
  if (not AUpper) and NonNeg(N) then Result:= True;
end;

{ The bound (AUpper: upper, else lower) of the local / parameter AX at AAt, from its writes in text
  order (a dominating write resets it, a conditional one joins, Inc / Dec move it -- in a for loop
  that does not hold AAt by the loop's trips), the writes in the loops around AAt (they flow back),
  a guard right after a write (`x := f; if x < 0 then Exit`) and the guards that dominate AAt after
  the last write. A parameter starts unknown; a pass to a call that may take it by reference, an
  address taken or a capture make it unknown. A chain of locals that comes back to AX is followed
  once: it adds nothing when its offsets do not grow the bound (ORM3 / YADF index chains). }
function TBnRun.BoundAt(const AX: string; const AAt: TTSNode; AUpper: Boolean; ADepth: Integer; out AV: Integer): Boolean;  // dl:ok cognitive-complexity@4f9f, cyclomatic-complexity@4cbf, too-many-locals@8053 -- REVIEWED 2026-11-18 IDXRANGE3: one flow pass over the writes in text order; the branches share its per-event state, a split scatters it
var
  Events, AtLoops, ELoops: TList<TTSNode>;
  E, Body, Gd, Nx, Inner, ThenN, C, P, S, Args, EvalAt: TTSNode;
  Entered, Net, V, Val, K, T, G, Own, I: Integer;
  LastByte: Cardinal;
  Known, ValOk, InAtLoop, IsInc, Dom, InBranch: Boolean;
  Fn, Key, MemoKey, Memo: string;
  Keys: TDictionary<Cardinal, Cardinal>;
  CyclesAt: Integer;

  procedure Gather(const N: TTSNode);
  var
    J: Integer;
  begin
    if N.IsNull then Exit;
    if ((N.NodeType = 'for') and (AssignTarget(N.ChildByField('start')) = AX))
      or ((N.NodeType = 'exprCall') and PassesByRef(N, AX)) then Events.Add(N);
    for J:= 0 to N.ChildCount - 1 do Gather(N.Child(J));
  end;

  function InList(const N: TTSNode; AList: TList<TTSNode>): Boolean;
  var
    Q: TTSNode;
  begin
    for Q in AList do
      if Q = N then Exit(True);
    Result:= False;
  end;

  procedure Tighten(AG: Integer);
  begin
    if Known and not IsNeutralBound(V) then V:= TightBound(V, AG, AUpper)
    else
    begin
      V:= AG;
      Known:= True;
    end;
  end;

begin
  Result:= False;
  AV:= 0;
  if (ADepth > MAX_BOUND_DEPTH) or FCurProc.IsNull or (not IsOwnLocal(AX)) or (not NodeWithin(AAt, FCurProc)) then Exit;
  Key:= AX + '@' + IntToStr(AAt.StartByte);  { one name at one point: a chain through a loop comes back to it }
  if FBoundVisit.Count = 0 then FBoundMemo.Clear;
  MemoKey:= Key + (if AUpper then '^' else 'v');
  if FBoundMemo.TryGetValue(MemoKey, Memo) then
  begin
    Result:= Memo <> '';
    if Result then AV:= StrToInt(Memo);
    Exit;
  end;
  if FBoundVisit.TryGetValue(Key, Entered) then
  begin
    Inc(FBoundCycles);
    { a chain back to AX: neutral when the way round does not grow the bound }
    Net:= FBoundOff - Entered;
    if (AUpper and (Net <= 0)) or ((not AUpper) and (Net >= 0)) then
    begin
      AV:= NeutralBound(AUpper);
      Result:= True;
    end;
    Exit;
  end;
  Body:= FCurProc.ChildByField('body');
  if NameEscapes(FCurProc, AX, False) then Exit;
  FBoundVisit.Add(Key, FBoundOff);
  CyclesAt:= FBoundCycles;
  Events:= TList<TTSNode>.Create;
  AtLoops:= TList<TTSNode>.Create;
  ELoops:= TList<TTSNode>.Create;
  try
    CollectIdxWrites(Body, AX, Events);
    Gather(Body);
    LoopsAround(AAt, AtLoops);
    { text order, except that a write after AAt in a loop around it flows in at that loop's head:
      it comes before the writes of the loop body that precede AAt (YADF.Layout:2665) }
    Keys:= TDictionary<Cardinal, Cardinal>.Create;
    try
      for E in Events do
      begin
        Keys.AddOrSetValue(E.StartByte, E.StartByte);
        if E.StartByte >= AAt.StartByte then
          for Gd in AtLoops do
            if NodeWithin(E, Gd) then
            begin
              Keys.AddOrSetValue(E.StartByte, Gd.StartByte);
              Break;
            end;
      end;
      Events.Sort(TComparer<TTSNode>.Construct(
        function(const A, B: TTSNode): Integer
        begin
          Result:= Integer(Keys[A.StartByte]) - Integer(Keys[B.StartByte]);
          if Result = 0 then Result:= Integer(A.StartByte) - Integer(B.StartByte);
        end));
    finally
      Keys.Free;
    end;
    Known:= not FScopes[FScopes.Count - 1][AX].IsParam;  { a parameter's incoming value is unknown }
    V:= NeutralBound(AUpper);
    LastByte:= 0;
    for E in Events do
    begin
      LoopsAround(E, ELoops);
      InAtLoop:= False;
      Own:= 0;
      Inner:= Default(TTSNode);
      for Gd in ELoops do
        if InList(Gd, AtLoops) then InAtLoop:= True
        else if not (Gd = E) then  // dl:ok nonminimal-bool@1204 -- REVIEWED 2026-11-18 IDXRANGE3: TTSNode declares Equal but no NotEqual; <> does not compile
        begin
          Inc(Own);
          if Inner.IsNull then Inner:= Gd;
        end;
      { only the writes before AAt, and those in a loop around AAt, reach it }
      if (E.StartByte >= AAt.StartByte) and not InAtLoop then Continue;
      if E.StartByte > LastByte then LastByte:= E.StartByte;
      { a write that dominates AAt resets it -- in a loop around AAt too: every way round passes it }
      Dom:= (Own = 0) and (E.StartByte < AAt.StartByte) and StmtDominates(E, AAt);
      if E.NodeType = 'for' then
      begin
        { a for loop over AX in a loop around AAt, after AAt, whose undefined counter a later
          statement of that loop's body overwrites before the loop goes round (YADF.Layout:2801) }
        if InAtLoop and (E.StartByte > AAt.StartByte) and ForCounterOverwritten(E, Events) then Continue;
        { AX is that loop's counter: inside the body its range is the loop's bounds (the header runs
          on every way in), after the loop it is undefined }
        Known:= False;
        if NodeWithin(AAt, E.ChildByField('body')) then
        begin
          IsInc:= False;  { reused: True for a downto loop }
          for I:= 0 to E.ChildCount - 1 do
            if E.Child(I).NodeType = 'kDownto' then IsInc:= True;
          Known:= EvalBound(if AUpper <> IsInc then E.ChildByField('end') else E.ChildByField('start').ChildByField('rhs'),
            E, AUpper, ADepth + 1, V);
        end;
        Continue;
      end;
      if E.NodeType = 'foreach' then
      begin
        Known:= False;
        Continue;
      end;
      if E.NodeType = 'exprCall' then
      begin
        Fn:= BareIdent(E.ChildByField('entity'));
        if (Fn <> 'inc') and (Fn <> 'dec') then
        begin
          Known:= False;  { a pass to a call that may take AX by reference }
          Continue;
        end;
        IsInc:= Fn = 'inc';
        Args:= E.ChildByField('args');
        K:= 1;
        if (not Args.IsNull) and (Args.NamedChildCount >= 2) and not (EvalIndex(Args.NamedChild(1), K) and (K >= 0)) then
        begin
          if (AUpper and IsInc) or ((not AUpper) and not IsInc) then Known:= False;
          Continue;
        end;
        if AUpper <> IsInc then Continue;  { an Inc keeps a lower bound, a Dec an upper one }
        if (not Known) or IsNeutralBound(V) or InAtLoop then
        begin
          Known:= False;
          Continue;
        end;
        if Own = 0 then V:= if AUpper then V + K else V - K
        else if (Own = 1) and LoopTrips(Inner, ADepth, T) then V:= if AUpper then V + K * T else V - K * T
        else Known:= False;
        Continue;
      end;
      { an assignment / an initialised `var x := ..`; one in a loop around AAt that does not dominate
        it is read at the head of the innermost such loop -- every write of that loop reaches there,
        so the bound covers its value, and chains through the loop come back to one point }
      EvalAt:= E;
      if InAtLoop and not Dom then
        for Gd in ELoops do
          if InList(Gd, AtLoops) then
          begin
            EvalAt:= Gd.ChildByField('body');
            if EvalAt.IsNull then EvalAt:= Gd.NamedChild(0);
            Break;
          end;
      ValOk:= EvalBound(E.ChildByField('rhs'), EvalAt, AUpper, ADepth + 1, Val);
      { a guard right after it: `x := f(..); if x < 0 then Exit` }
      Nx:= E;
      while (not Nx.Parent.IsNull) and (Nx.Parent.NodeType <> 'block') and (Nx.Parent.NodeType <> 'statements')
        and (IndexStr(Nx.Parent.NodeType, CONTROL_NODES) < 0) and (Nx.Parent.NodeType <> 'defProc') do Nx:= Nx.Parent;
      if (not Nx.Parent.IsNull) and ((Nx.Parent.NodeType = 'block') or (Nx.Parent.NodeType = 'statements')) then
      begin
        Nx:= Nx.NextNamedSibling;
        while (not Nx.IsNull) and IsTrivia(Nx) do Nx:= Nx.NextNamedSibling;
        if (not Nx.IsNull) and (Nx.NodeType = 'if') and IsLeaveStmt(Nx.ChildByField('then'))
          and (Nx.EndByte <= AAt.StartByte) and CondBound(Nx.ChildByField('condition'), AX, True, AUpper, G) then
        begin
          Val:= if ValOk and not IsNeutralBound(Val) then TightBound(Val, G, AUpper) else G;
          ValOk:= True;
        end;
      end;
      if Dom then
      begin
        Known:= ValOk;
        V:= Val;
      end
      else if ValOk then V:= JoinBound(V, Val, AUpper)
      else Known:= False;
    end;
    { the guards that dominate AAt after the last write that reaches it }
    C:= AAt;
    P:= C.Parent;
    while (not P.IsNull) and (P.NodeType <> 'defProc') and (P.NodeType <> 'lambda') do
    begin
      InBranch:= ((P.NodeType = 'if') or (P.NodeType = 'ifElse')) and ((P.ChildByField('then') = C) or (P.ChildByField('else') = C));
      if InBranch and (P.ChildByField('condition').StartByte > LastByte)
        and CondBound(P.ChildByField('condition'), AX, P.ChildByField('else') = C, AUpper, G) then
        Tighten(G)
      else if (P.NodeType = 'while') and (P.ChildByField('body') = C) and (P.ChildByField('condition').StartByte > LastByte)
        and CondBound(P.ChildByField('condition'), AX, False, AUpper, G) then
        Tighten(G)
      else if (P.NodeType = 'block') or (P.NodeType = 'statements') then
      begin
        S:= C.PrevSibling;
        while (not S.IsNull) and (S.StartByte > LastByte) do
        begin
          ThenN:= S.ChildByField('then');
          if (S.NodeType = 'if') and IsLeaveStmt(ThenN) and CondBound(S.ChildByField('condition'), AX, True, AUpper, G) then Tighten(G);
          S:= S.PrevSibling;
        end;
      end;
      C:= P;
      P:= C.Parent;
    end;
    Result:= Known;
    AV:= V;
    if FBoundCycles = CyclesAt then FBoundMemo.AddOrSetValue(MemoKey, if Known then IntToStr(V) else '');
  finally
    ELoops.Free;
    AtLoops.Free;
    Events.Free;
    FBoundVisit.Remove(Key);
  end;
end;


{ YADF ShapesMatch: a dominating `if Length(A) <> Length(B) then <leave>` (also High, either order,
  either side of an `or`) with neither array resized from there to the access: same length. }
function TBnRun.EqualLenGuard(const A, B: string): Boolean;  // dl:ok too-many-exit-points@d669 -- REVIEWED 2026-11-18 IDXRANGE3: guard clauses per syntax shape; each early exit is a classification
var
  S, E: TTSNode;
  Guards, Todo: TList<TTSNode>;
  Hi: Cardinal;
  DA, DB, First, Last: TTSNode;
  SA: string;
  Id: TMatch;

  { `Fn(A) <> Fn(B)` (either order) for Length or High }
  function SameFnPair(const ANeq: TTSNode; const AFn: string): Boolean;
  var
    L, R: TTSNode;
  begin
    L:= ANeq.ChildByField('lhs');
    R:= ANeq.ChildByField('rhs');
    Result:= (IsArrayFn(L, AFn, A) and IsArrayFn(R, AFn, B)) or (IsArrayFn(L, AFn, B) and IsArrayFn(R, AFn, A));
  end;

begin
  Result:= False;
  if (A = B) or FAccess.IsNull or not NodeWithin(FAccess, FCurProc) then Exit;
  Guards:= TList<TTSNode>.Create;
  Todo:= TList<TTSNode>.Create;
  try
    LeaveGuardsBefore(FAccess, Guards);
    for S in Guards do
    begin
      Hi:= AccessReach(FAccess, S.EndByte);
      if SizeChangedIn(A, S.EndByte, Hi) or SizeChangedIn(B, S.EndByte, Hi) then Continue;
      Todo.Clear;
      Todo.Add(S.ChildByField('condition'));
      while Todo.Count > 0 do
      begin
        E:= Peeled(Todo.Last);
        Todo.Delete(Todo.Count - 1);
        if E.IsNull or (E.NodeType <> 'exprBinary') then Continue;
        if OperatorType(E) = 'kOr' then
        begin
          Todo.Add(E.ChildByField('lhs'));
          Todo.Add(E.ChildByField('rhs'));
        end
        else if (OperatorType(E) = 'kNeq') and (SameFnPair(E, 'length') or SameFnPair(E, 'high')) then
          Exit(True);
      end;
    end;
  finally
    Todo.Free;
    Guards.Free;
  end;
  { 1.52 IDXRANGE3 (uPdfScanRescan:523): both sized by the same expression, nothing it reads changed
    between the two SetLengths, neither resized up to the access }
  DA:= DomSetLength(A);
  DB:= DomSetLength(B);
  if DA.IsNull or DB.IsNull then Exit;
  SA:= StringReplace(LowerCase(Txt(DA.ChildByField('args').NamedChild(1))), ' ', '', [rfReplaceAll]);
  if SA <> StringReplace(LowerCase(Txt(DB.ChildByField('args').NamedChild(1))), ' ', '', [rfReplaceAll]) then Exit;
  First:= if DA.StartByte < DB.StartByte then DA else DB;
  Last:= if DA.StartByte < DB.StartByte then DB else DA;
  if SizeChangedIn(A, First.EndByte, Last.StartByte) or SizeChangedIn(B, First.EndByte, Last.StartByte) then Exit;
  for Id in TRegEx.Matches(SA, '[a-z_]\w*(\.[a-z_]\w*)*') do
    if TouchedPath(Id.Value, First.EndByte, Last.StartByte) then Exit;
  Hi:= AccessReach(FAccess, Last.StartByte);
  Result:= not (SizeChangedIn(A, DA.EndByte, Hi) or SizeChangedIn(B, DB.EndByte, Hi));
end;

{ The `if <c> then <leave>` statements that dominate AAt: earlier statements of every statement
  list around it, nearest first, into AList. }
procedure TBnRun.LeaveGuardsBefore(const AAt: TTSNode; AList: TList<TTSNode>);
var
  C, P, S: TTSNode;
begin
  C:= AAt;
  P:= C.Parent;
  while (not P.IsNull) and (P.NodeType <> 'defProc') and (P.NodeType <> 'lambda') do
  begin
    if (P.NodeType = 'block') or (P.NodeType = 'statements') then
    begin
      S:= C.PrevSibling;
      while not S.IsNull do
      begin
        if (S.NodeType = 'if') and IsLeaveStmt(S.ChildByField('then')) then AList.Add(S);
        S:= S.PrevSibling;
      end;
    end;
    C:= P;
    P:= C.Parent;
  end;
end;

{ YADF.Layout:5813/6319, :2638: the routine a call names starts with `SetLength(X, P.Count)` (or
  Length(P)) statements, X its Result or one of its parameters, P another parameter, and changes X's
  size nowhere else -- in this unit, or in another unit of the index (lint --db). The spec, cached
  per name: 'target=param:cnt|len' entries joined by ';', target 'r' for Result or a param index. }
function TBnRun.CalleeSizes(const ACall: TTSNode): string;
var
  Nm: string;
  Ent: TTSNode;

  function TxtIn(const N: TTSNode; const ASrc: TBytes): string;
  begin
    Result:= '';
    if N.IsNull or (Integer(N.EndByte) > Length(ASrc)) or (N.EndByte <= N.StartByte) then Exit;
    Result:= TEncoding.UTF8.GetString(ASrc, Integer(N.StartByte), Integer(N.EndByte - N.StartByte));
  end;

  function SizerSpec(const AProc: TTSNode; const ASrc: TBytes): string;
  var
    Params, Entries: TList<string>;
    Body, St, N, Arg: TTSNode;
    Stack: TList<TTSNode>;
    I, Sizes: Integer;
    T, Fn, Tgt, Src, Kind, PName: string;
    M: TMatch;
    Done: Boolean;

    procedure CollectParams(const H: TTSNode);
    var
      J: Integer;
      Ty, Dv: TTSNode;
    begin
      if H.IsNull then Exit;
      if H.NodeType = 'declArg' then
      begin
        Ty:= H.ChildByField('type');
        Dv:= H.ChildByField('defaultValue');
        for J:= 0 to H.NamedChildCount - 1 do
          if (H.NamedChild(J).NodeType = 'identifier') and not (H.NamedChild(J) = Ty) and not (H.NamedChild(J) = Dv) then  // dl:ok nonminimal-bool@db1d -- REVIEWED 2026-11-18 IDXRANGE3: TTSNode declares Equal but no NotEqual; <> does not compile
            Params.Add(LowerCase(TxtIn(H.NamedChild(J), ASrc)));
        Exit;
      end;
      for J:= 0 to H.ChildCount - 1 do CollectParams(H.Child(J));
    end;

    { X's size and P change nowhere but in the one leading SetLength }
    function OnlySizer(const AX, AP: string): Boolean;
    var
      J: Integer;
    begin
      Result:= False;
      Sizes:= 0;
      Stack.Clear;
      Stack.Add(Body);
      while Stack.Count > 0 do
      begin
        N:= Stack.Last;
        Stack.Delete(Stack.Count - 1);
        if N.IsNull or (N.NodeType = 'lambda') or (N.NodeType = 'defProc') then Continue;
        T:= N.NodeType;
        if (T = 'assignment') and MatchText(Trim(TxtIn(N.ChildByField('lhs'), ASrc)), [AX, AP]) then Exit;
        if (T = 'assignment') and (AX = 'result') and SameText(Trim(TxtIn(N.ChildByField('lhs'), ASrc)), PName) then Exit;
        if T = 'exprCall' then
        begin
          Fn:= LowerCase(Trim(TxtIn(N.ChildByField('entity'), ASrc)));
          Arg:= N.ChildByField('args');
          if MatchText(Fn, ['setlength', 'delete', 'insert']) and (not Arg.IsNull)
            and TRegEx.IsMatch(TxtIn(Arg, ASrc), '\b' + TRegEx.Escape(AX) + '\b', [roIgnoreCase]) then Inc(Sizes);
        end;
        for J:= 0 to N.ChildCount - 1 do Stack.Add(N.Child(J));
      end;
      Result:= Sizes = 1;
    end;

  begin
    Result:= '';
    Body:= AProc.ChildByField('body');
    if Body.IsNull then Exit;
    PName:= LowerCase(Trim(TxtIn(AProc.ChildByField('header').ChildByField('name'), ASrc)));
    Params:= TList<string>.Create;
    Stack:= TList<TTSNode>.Create;
    Entries:= TList<string>.Create;
    try
      CollectParams(AProc.ChildByField('header'));
      Done:= False;
      for I:= 0 to Body.NamedChildCount - 1 do
      begin
        if Done then Break;
        St:= Body.NamedChild(I);
        if IsTrivia(St) then Continue;
        while (not St.IsNull) and (St.NodeType <> 'exprCall') and (St.NamedChildCount = 1) do St:= St.NamedChild(0);
        M:= TRegEx.Match(TxtIn(St, ASrc), '^\s*setlength\s*\(\s*(\w+)\s*,\s*(?:(\w+)\s*\.\s*count|length\s*\(\s*(\w+)\s*\))\s*\)\s*$', [roIgnoreCase]);
        if St.IsNull or (St.NodeType <> 'exprCall') or not M.Success then
        begin
          Done:= True;
          Continue;
        end;
        Tgt:= LowerCase(M.Groups[1].Value);
        Kind:= if M.Groups[2].Success and (M.Groups[2].Value <> '') then 'cnt' else 'len';
        Src:= LowerCase(if Kind = 'cnt' then M.Groups[2].Value else M.Groups[3].Value);
        if (Params.IndexOf(Src) < 0) or ((Tgt <> 'result') and (Params.IndexOf(Tgt) < 0)) or not OnlySizer(Tgt, Src) then Continue;
        Entries.Add((if Tgt = 'result' then 'r' else IntToStr(Params.IndexOf(Tgt))) + '=' + IntToStr(Params.IndexOf(Src)) + ':' + Kind);
      end;
      Result:= string.Join(';', Entries.ToArray);
    finally
      Entries.Free;
      Stack.Free;
      Params.Free;
    end;
  end;

  function FindProc(const ARoot: TTSNode; const ASrc: TBytes; out AProc: TTSNode): Integer;
  var
    Stack: TList<TTSNode>;
    N: TTSNode;
    I: Integer;
  begin
    Result:= 0;
    AProc:= Default(TTSNode);
    Stack:= TList<TTSNode>.Create;
    try
      Stack.Add(ARoot);
      while Stack.Count > 0 do
      begin
        N:= Stack.Last;
        Stack.Delete(Stack.Count - 1);
        if N.IsNull then Continue;
        if N.NodeType = 'defProc' then
        begin
          if SameText(Trim(TxtIn(N.ChildByField('header').ChildByField('name'), ASrc)), Nm) then
          begin
            Inc(Result);
            AProc:= N;
          end;
          Continue;
        end;
        for I:= 0 to N.ChildCount - 1 do Stack.Add(N.Child(I));
      end;
    finally
      Stack.Free;
    end;
  end;

  function StoreSpec: string;  // dl:ok too-many-exit-points@560e -- REVIEWED 2026-11-18 IDXRANGE3: guard clauses per syntax shape; each early exit is a classification
  var
    S: TSymbol;
    FileId: Int64;
    Path: string;
    PF: TParsedFile;
    Proc: TTSNode;
  begin
    Result:= '';
    if FStore = nil then Exit;
    FileId:= -1;
    for S in FStore.FindSymbolsByExactName(Nm) do
    begin
      if not (S.Kind in [skFunction, skProcedure]) then Exit;  // dl:ok nonminimal-bool@63b1 -- REVIEWED 2026-11-18 IDXRANGE3: TTSNode declares Equal but no NotEqual; <> does not compile
      if (FileId >= 0) and (S.FileId <> FileId) then Exit;
      FileId:= S.FileId;
    end;
    if FileId < 0 then Exit;
    Path:= FStore.GetFilePath(FileId);
    if (Path = '') or SameText(Path, FFile) then Exit;
    PF:= TAstParseCache.Get(Path);
    if (PF.Tree = nil) or (FindProc(PF.Tree.RootNode, PF.Src, Proc) <> 1) then Exit;
    Result:= SizerSpec(Proc, PF.Src);
  end;

var
  Proc: TTSNode;
  Found: Integer;
begin
  Result:= '';
  if ACall.IsNull or (ACall.NodeType <> 'exprCall') then Exit;
  Ent:= ACall.ChildByField('entity');
  if Ent.IsNull or (Ent.NodeType <> 'identifier') then Exit;
  Nm:= LowerCase(Txt(Ent));
  if FCalleeLen.TryGetValue(Nm, Result) then Exit;
  Found:= FindProc(FRoot, FSrc, Proc);
  if Found = 1 then Result:= SizerSpec(Proc, FSrc)
  else if Found = 0 then Result:= StoreSpec;
  FCalleeLen.Add(Nm, Result);
end;

{ The length the call ACall gives its Result (ATarget 'r') or its argument number ATarget: the
  Count / Length of the argument its sizer names (CalleeSizes); unknown otherwise. }
function TBnRun.CalleeArgLen(const ACall: TTSNode; ATarget: string): TSym;
var
  Entry, Src, Kind: string;
  Args: TTSNode;
  P: Integer;
begin
  Result:= Default(TSym);
  for Entry in CalleeSizes(ACall).Split([';']) do
  begin
    if not StartsStr(ATarget + '=', Entry) then Continue;
    Src:= Copy(Entry, Length(ATarget) + 2, MaxInt);
    P:= StrToIntDef(Copy(Src, 1, Pos(':', Src) - 1), -1);
    Kind:= Copy(Src, Pos(':', Src) + 1, MaxInt);
    Args:= ACall.ChildByField('args');
    if (P < 0) or Args.IsNull or (P >= Args.NamedChildCount) or (BareIdent(Args.NamedChild(P)) = '') then Exit;
    Exit(MkSym(Kind + ':' + BareIdent(Args.NamedChild(P)), 0));
  end;
end;

{ `A := F(.., P, ..)`: Length(A) from F's leading `SetLength(Result, P.Count)` (CalleeSizes). }
function TBnRun.CalleeResultLen(const ACall: TTSNode): TSym;
begin
  Result:= CalleeArgLen(ACall, 'r');
end;
{ YADF.Layout:11227 (compaction): `k := c0` then `for i := s to High(A)` (or Length(A) - k) with ONE
  `Inc(k)` per trip after the access A[k], A not resized in the loop: k stays at most High(A) when
  c0 <= s (+ k - 1). }
function TBnRun.SelfBoundedFor(const ACtx: TIdxCtx; const F: TTSNode; C0, SLo: Integer): Boolean;
var
  EndE, N: TTSNode;
  K, Off: Integer;
begin
  Result:= False;
  if F.NodeType <> 'for' then Exit;
  EndE:= F.ChildByField('end');
  N:= Peeled(EndE);
  if IsArrayFn(N, 'high', ACtx.Arr) then Off:= -1
  else if (not N.IsNull) and (N.NodeType = 'exprBinary') and (OperatorType(N) = 'kSub')
    and IsArrayFn(N.ChildByField('lhs'), 'length', ACtx.Arr) and EvalIndex(N.ChildByField('rhs'), K) then Off:= -K
  else if (not N.IsNull) and (N.NodeType = 'exprBinary') and (OperatorType(N) = 'kSub')
    and IsArrayFn(N.ChildByField('lhs'), 'high', ACtx.Arr) and EvalIndex(N.ChildByField('rhs'), K) then Off:= -1 - K
  else Exit;
  if SizeChangedIn(ACtx.Arr, F.StartByte, F.EndByte) then Exit;
  { k <= c0 + (trips - 1) = c0 + (len + Off) - SLo; within High = len - 1 }
  Result:= C0 + Off - SLo <= -1;
end;

{ Once per file: every call `Name(...)` by bare name, and which names are used ONLY as such calls --
  one definition, no declaration (interface / class member / forward), never passed as a value. }
procedure TBnRun.BuildCallIndex;
var
  Ident : TDictionary<string, Integer>;
  Defs  : TDictionary<string, Integer>;
  DefIds: TDictionary<string, Integer>;
  Decls : TDictionary<string, Integer>;

  procedure Bump(ADict: TDictionary<string, Integer>; const AName: string; ABy: Integer);
  var
    C: Integer;
  begin
    if not ADict.TryGetValue(AName, C) then C:= 0;
    ADict.AddOrSetValue(AName, C + ABy);
  end;

  function CountIds(const N: TTSNode; const AName: string): Integer;
  var
    I: Integer;
  begin
    Result:= 0;
    if N.IsNull then Exit;
    if (N.NodeType = 'identifier') and SameText(Txt(N), AName) then Inc(Result);
    for I:= 0 to N.ChildCount - 1 do Inc(Result, CountIds(N.Child(I), AName));
  end;

  procedure Walk(const N: TTSNode);
  var
    I: Integer;
    T, Nm: string;
    Ent, NameN: TTSNode;
    L: TList<TTSNode>;
  begin
    if N.IsNull then Exit;
    T:= N.NodeType;
    if T = 'identifier' then
      Bump(Ident, LowerCase(Txt(N)), 1)
    else if T = 'exprCall' then
    begin
      Ent:= N.ChildByField('entity');
      if (not Ent.IsNull) and (Ent.NodeType = 'identifier') then
      begin
        Nm:= LowerCase(Txt(Ent));
        if not FCallSites.TryGetValue(Nm, L) then
        begin
          L:= TList<TTSNode>.Create;
          FCallSites.Add(Nm, L);
        end;
        L.Add(N);
      end;
    end
    else if T = 'defProc' then
    begin
      NameN:= N.ChildByField('header').ChildByField('name');
      Nm:= LowerCase(Trim(Txt(NameN)));
      Bump(Defs, Nm, 1);
      Bump(DefIds, Nm, CountIds(NameN, Nm));
    end
    else if (T = 'declProc') and not ((not N.Parent.IsNull) and (N.Parent.NodeType = 'defProc')) then
      Bump(Decls, LowerCase(Trim(Txt(N.ChildByField('name')))), 1);  { a defProc's own header is not a declaration }
    for I:= 0 to N.ChildCount - 1 do Walk(N.Child(I));
  end;

var
  Pair: TPair<string, TList<TTSNode>>;
  D, Ids, Dc, UseCnt: Integer;
begin
  FCallSites:= TObjectDictionary<string, TList<TTSNode>>.Create([doOwnsValues]);
  FCallOk:= TDictionary<string, Boolean>.Create;
  Ident := TDictionary<string, Integer>.Create;
  Defs  := TDictionary<string, Integer>.Create;
  DefIds:= TDictionary<string, Integer>.Create;
  Decls := TDictionary<string, Integer>.Create;
  try
    Walk(FRoot);
    for Pair in FCallSites do
    begin
      if not Defs.TryGetValue(Pair.Key, D) then D:= 0;
      if not DefIds.TryGetValue(Pair.Key, Ids) then Ids:= 0;
      if not Decls.TryGetValue(Pair.Key, Dc) then Dc:= 0;
      if not Ident.TryGetValue(Pair.Key, UseCnt) then UseCnt:= 0;
      FCallOk.Add(Pair.Key, (D = 1) and (Dc = 0) and (UseCnt = Pair.Value.Count + Ids));
    end;
  finally
    Decls.Free;
    DefIds.Free;
    Defs.Free;
    Ident.Free;
  end;
end;

{ The parameter names of AProc in declaration order, lower-cased. }
function TBnRun.ParamNames(const AProc: TTSNode): TArray<string>;
var
  Acc: TList<string>;

  procedure Walk(const N: TTSNode);
  var
    I: Integer;
    C, Ty, Dv: TTSNode;
  begin
    if N.IsNull then Exit;
    if N.NodeType = 'declArg' then
    begin
      Ty:= N.ChildByField('type');
      Dv:= N.ChildByField('defaultValue');
      for I:= 0 to N.NamedChildCount - 1 do
      begin
        C:= N.NamedChild(I);
        if (C.NodeType = 'identifier') and not (C = Ty) and not (C = Dv) then Acc.Add(LowerCase(Txt(C)));
      end;
      Exit;
    end;
    for I:= 0 to N.ChildCount - 1 do Walk(N.Child(I));
  end;

begin
  Acc:= TList<string>.Create;
  try
    Walk(AProc.ChildByField('header'));
    Result:= Acc.ToArray;
  finally
    Acc.Free;
  end;
end;

{ The call sites of AProc when every use of its name in the file is a plain local call (C2: an
  exported, overloaded, method or by-value routine has callers the file cannot see). }
function TBnRun.LocalCalls(const AProc: TTSNode; out ASites: TList<TTSNode>): Boolean;
var
  Nm: string;
  Ok: Boolean;
begin
  ASites:= nil;
  if FCallSites = nil then BuildCallIndex;
  Nm:= LowerCase(Trim(Txt(AProc.ChildByField('header').ChildByField('name'))));
  Result:= FCallOk.TryGetValue(Nm, Ok) and Ok and FCallSites.TryGetValue(Nm, ASites);
end;

{ The routine whose body holds N; null inside a lambda or outside any routine. }
function TBnRun.EnclosingProc(const N: TTSNode): TTSNode;
begin
  Result:= N.Parent;
  while (not Result.IsNull) and (Result.NodeType <> 'defProc') do
  begin
    if Result.NodeType = 'lambda' then Exit(Default(TTSNode));
    Result:= Result.Parent;
  end;
end;

{ Switches the per-routine state to AProc (a local caller) for one check; LeaveRoutine restores it. }
procedure TBnRun.EnterRoutine(const AProc: TTSNode; out ASaved: TBnSaved);
var
  Chain: TList<TTSNode>;
  P: TTSNode;
  I: Integer;
begin
  ASaved.Scopes  := FScopes;
  ASaved.LenAlias:= FLenAlias;
  ASaved.LenCache:= FLenCache;
  ASaved.WriteCnt:= FWriteCnt;
  ASaved.CurProc := FCurProc;
  FScopes  := TObjectList<TDictionary<string, TDeclInfo>>.Create(True);
  FLenAlias:= TDictionary<string, string>.Create;
  FLenCache:= TDictionary<string, TSym>.Create;
  FWriteCnt:= TDictionary<string, Integer>.Create;
  FCurProc := AProc;
  Inc(FTraceDepth);
  Chain:= TList<TTSNode>.Create;
  try
    P:= AProc;
    while not P.IsNull do
    begin
      if P.NodeType = 'defProc' then Chain.Insert(0, P);
      P:= P.Parent;
    end;
    for I:= 0 to Chain.Count - 1 do FScopes.Add(BuildScope(Chain[I]));
  finally
    Chain.Free;
  end;
  CollectLenAliases(AProc.ChildByField('body'));
end;

procedure TBnRun.LeaveRoutine(const ASaved: TBnSaved);
begin
  FWriteCnt.Free;
  FLenCache.Free;
  FLenAlias.Free;
  FScopes.Free;
  FScopes  := ASaved.Scopes;
  FLenAlias:= ASaved.LenAlias;
  FLenCache:= ASaved.LenCache;
  FWriteCnt:= ASaved.WriteCnt;
  FCurProc := ASaved.CurProc;
  Dec(FTraceDepth);
end;

{ S, a bound in the callee's terms, as the caller sees it at a call with AArgs: a callee parameter in
  the base becomes the argument passed for it. Unknown when the base names anything else. }
function TBnRun.TranslateSym(const S: TSym; const ACallee, AArgs: TTSNode): TSym;
var
  Kind, Nm, B: string;
  P, Colon: Integer;
  Arg: TTSNode;
begin
  Result:= Default(TSym);
  if not S.Ok then Exit;
  if S.Base = '' then Exit(S);
  Colon:= Pos(':', S.Base);
  Kind:= Copy(S.Base, 1, Colon - 1);
  Nm  := Copy(S.Base, Colon + 1, MaxInt);
  P:= IndexStr(Nm, ParamNames(ACallee));
  if (P < 0) or (P >= AArgs.NamedChildCount) then Exit;
  Arg:= AArgs.NamedChild(P);
  B:= BareIdent(Arg);
  if Kind = 'cnt' then
  begin
    if B <> '' then Result:= MkSym('cnt:' + B, S.Off);
  end
  else if Kind = 'len' then
  begin
    if B <> '' then Result:= LenSymOf(B);
    if Result.Ok then Inc(Result.Off, S.Off);
  end
  else
  begin
    Result:= SymOf(Arg);
    if Result.Ok then Inc(Result.Off, S.Off);
  end;
end;

{ At call ASite, in its caller (the current routine), AIdxExpr lies within AArr's range. }
function TBnRun.ProveIndexAt(const ASite, AIdxExpr: TTSNode; const AArr: string): Boolean;
var
  Ctx: TIdxCtx;
  V: Integer;
  Writes: TList<TTSNode>;
  OldAccess, RetT: TTSNode;
begin
  Result:= False;
  Ctx:= Default(TIdxCtx);
  if not IsBoundedArray(AArr, Ctx.Info) then
  begin
    { 1.52 BK-RULEFP (YADF.Tokens:230): the caller passes its own Result of a dynamic-array type }
    RetT:= FCurProc.ChildByField('header').ChildByField('type');
    if (AArr <> 'result') or RetT.IsNull or not TRegEx.IsMatch(LowerCase(Trim(Txt(RetT))), DYN_ARRAY_TYPE_PATTERN) then Exit;
    Ctx.Info.Kind:= dkDynArray;
  end;
  if EvalIndex(AIdxExpr, V) then
    Exit((V >= (if Ctx.Info.Kind = dkArray then Ctx.Info.Lo else 0)) and UpperWithin(MkSym('', V), AArr, Ctx.Info));
  Ctx.Idx:= BareIdent(AIdxExpr);
  if (Ctx.Idx = '') or not FScopes[FScopes.Count - 1].TryGetValue(Ctx.Idx, Ctx.IdxInfo) then Exit;
  Ctx.Access:= ASite;
  Ctx.Arr:= AArr;
  OldAccess:= FAccess;
  FAccess:= ASite;
  Writes:= TList<TTSNode>.Create;
  try
    CollectIdxWrites(FCurProc.ChildByField('body'), Ctx.Idx, Writes);
    Ctx.Writes:= Writes;
    ProvenanceSides(Ctx);
    ClimbGuards(Ctx);
    if not Ctx.Hi then Ctx.Hi:= OnePastWhile(Ctx) or CountInvariant(Ctx);
    Result:= Ctx.Lo and Ctx.Hi;
  finally
    FAccess:= OldAccess;
    Writes.Free;
  end;
end;

{ C2 (owner 2026-11-17): every local call of AProc passes an index proven within the array it
  passes (or within the non-local array the access names). }
function TBnRun.CallersProveIndex(const AProc: TTSNode; const ACtx: TIdxCtx): Boolean;
var
  Sites: TList<TTSNode>;
  Site, Args, Caller: TTSNode;
  Names: TArray<string>;
  PIdx, PArr: Integer;
  ArrAt: string;
  Saved: TBnSaved;
begin
  Result:= False;
  if not LocalCalls(AProc, Sites) then Exit;
  Names:= ParamNames(AProc);
  PIdx:= IndexStr(ACtx.Idx, Names);
  PArr:= IndexStr(ACtx.Arr, Names);
  if PIdx < 0 then Exit;
  if (PArr < 0) and FScopes[FScopes.Count - 1].ContainsKey(ACtx.Arr) then Exit;  { a local array: no caller sees it }
  for Site in Sites do
  begin
    Args:= Site.ChildByField('args');
    Caller:= EnclosingProc(Site);
    if Args.IsNull or Caller.IsNull or (PIdx >= Args.NamedChildCount) or (PArr >= Args.NamedChildCount) then Exit;
    ArrAt:= if PArr >= 0 then BareIdent(Args.NamedChild(PArr)) else ACtx.Arr;
    if ArrAt = '' then Exit;
    EnterRoutine(Caller, Saved);
    try
      if (PArr < 0) and InScopes(ACtx.Arr) then Exit;  { the caller shadows the array }
      if not ProveIndexAt(Site, Args.NamedChild(PIdx), ArrAt) then Exit;
    finally
      LeaveRoutine(Saved);
    end;
  end;
  Result:= True;
end;

{ C1 (owner 2026-11-17): at every local call of AProc the other collection's bound that guards the
  access lies within the array passed for ACtx.Arr (e.g. the caller sized it from that Count). }
function TBnRun.CallersProveUpper(const AProc: TTSNode; const ACtx: TIdxCtx): Boolean;
var
  Sites: TList<TTSNode>;
  Site, Args, Caller: TTSNode;
  PArr, PB: Integer;
  ArrAt: string;
  Saved: TBnSaved;
  U: TSym;
  Info: TDeclInfo;
begin
  Result:= False;
  if not LocalCalls(AProc, Sites) then Exit;
  PArr:= IndexStr(ACtx.Arr, ParamNames(AProc));
  if (PArr < 0) and FScopes[FScopes.Count - 1].ContainsKey(ACtx.Arr) then Exit;
  for Site in Sites do
  begin
    Args:= Site.ChildByField('args');
    Caller:= EnclosingProc(Site);
    if Args.IsNull or Caller.IsNull or (PArr >= Args.NamedChildCount) then Exit;
    ArrAt:= if PArr >= 0 then BareIdent(Args.NamedChild(PArr)) else ACtx.Arr;
    if ArrAt = '' then Exit;
    EnterRoutine(Caller, Saved);
    try
      if (PArr < 0) and InScopes(ACtx.Arr) then Exit;
      if StartsText('id:', ACtx.FgnSym.Base) then
      begin
        { 1.52 BK-RULEFP: idx <= P + Off (Off <= 0) with P a parameter: the argument is a valid index }
        PB:= IndexStr(Copy(ACtx.FgnSym.Base, Length('id:') + 1, MaxInt), ParamNames(AProc));
        if (ACtx.FgnSym.Off > 0) or (PB < 0) or (PB >= Args.NamedChildCount) then Exit;
        { 1.52 IDXRANGE3 (Blueprint4.ViewModel:2474): `idx < L` with the caller passing SetLength(B, N); f(B, N) }
        if (ACtx.FgnSym.Off < 0) and UpperAtSite(Site, Args.NamedChild(PB), ArrAt, ACtx.FgnSym.Off) then Continue;
        if not ProveIndexAt(Site, Args.NamedChild(PB), ArrAt) then Exit;
        Continue;
      end;
      U:= TranslateSym(ACtx.FgnSym, AProc, Args);
      if not Lookup(ArrAt, Info) then Info:= Default(TDeclInfo);
      if not (U.Ok and UpperWithin(U, ArrAt, Info)) then Exit;
    finally
      LeaveRoutine(Saved);
    end;
  end;
  Result:= True;
end;

{ Every A[idx] of one routine, where A is a bounded array and idx a routine local or parameter. }
procedure TBnRun.CheckIndexFlow(const AProc: TTSNode);
var
  Body: TTSNode;
  Locals: TDictionary<string, TDeclInfo>;
  Accesses: TList<TTSNode>;
  Writes: TList<TTSNode>;
  Reported: TDictionary<string, Boolean>;
  Unsafe: Boolean;

  procedure Gather(const N: TTSNode);
  var
    I: Integer;
  begin
    if N.IsNull then Exit;
    if (N.NodeType = 'lambda') or (N.NodeType = 'defProc') then Exit;
    if (N.NodeType = 'with') or (N.NodeType = 'goto') then Unsafe:= True;
    if N.NodeType = 'exprSubscript' then Accesses.Add(N);
    for I:= 0 to N.ChildCount - 1 do Gather(N.Child(I));
  end;

  { a lambda in the body that names AIdx may write it }
  function InLambda(const N: TTSNode; const AIdx: string): Boolean;
  var
    J: Integer;
  begin
    Result:= False;
    if N.IsNull then Exit;
    if N.NodeType = 'lambda' then Exit(Mentions(N, AIdx));
    for J:= 0 to N.ChildCount - 1 do
      if InLambda(N.Child(J), AIdx) then Exit(True);
  end;

  { a nested routine or a lambda that names AIdx may write it: the routine-local view is blind there }
  function CapturedElsewhere(const AIdx: string): Boolean;
  var
    I: Integer;
  begin
    Result:= InLambda(Body, AIdx);
    if not Result then
      for I:= 0 to AProc.ChildCount - 1 do
        if (AProc.Child(I).NodeType = 'defProc') and Mentions(AProc.Child(I), AIdx) then
          Exit(True);
  end;

var
  N, Args, IdxN: TTSNode;
  Ctx: TIdxCtx;
  V: Integer;
begin
  Body:= AProc.ChildByField('body');
  if Body.IsNull then Exit;
  Locals:= FScopes[FScopes.Count - 1];
  Unsafe:= False;
  Accesses:= TList<TTSNode>.Create;
  Writes:= TList<TTSNode>.Create;
  Reported:= TDictionary<string, Boolean>.Create;
  try
    Gather(Body);
    if Unsafe then Exit;
    FCurProc:= AProc;
    FLenCache.Clear;
    FWriteCnt.Clear;
    CollectLenAliases(Body);
    for N in Accesses do
    begin
      Args:= N.ChildByField('args');
      if Args.IsNull or (Args.NamedChildCount <> 1) then Continue;
      IdxN:= Args.NamedChild(0);
      Ctx:= Default(TIdxCtx);
      Ctx.Access:= N;
      Ctx.Idx:= BareIdent(IdxN);
      Ctx.Arr:= BareIdent(N.ChildByField('entity'));
      if (Ctx.Idx = '') or (Ctx.Arr = '') or EvalIndex(IdxN, V) then Continue;
      if not Locals.TryGetValue(Ctx.Idx, Ctx.IdxInfo) then Continue;   { v1 cut: field / global index }
      if not IsBoundedArray(Ctx.Arr, Ctx.Info) then Continue;
      if CapturedElsewhere(Ctx.Idx) then Continue;
      Writes.Clear;
      CollectIdxWrites(Body, Ctx.Idx, Writes);
      Ctx.Writes:= Writes;
      CheckIndexAccess(AProc, Ctx, Reported);
    end;
  finally
    Reported.Free;
    Writes.Free;
    Accesses.Free;
  end;
end;

{ ---- the walk ------------------------------------------------------------ }

procedure TBnRun.Visit(const N: TTSNode);
var
  T: string;
  I: Integer;
  Pushed: Boolean;
begin
  if N.IsNull or (FFindings.Count >= MAX_FINDINGS) then Exit;
  T:= N.NodeType;
  Pushed:= False;
  if T = 'defProc' then
  begin
    FScopes.Add(BuildScope(N));
    Pushed:= True;
    CheckProc(N);
    CheckIndexFlow(N);
  end
  else if (T = 'block') or (T = 'statements') then
  begin
    CheckNilBlock(N);
    CheckCopyBlock(N);
  end
  else if T = 'exprSubscript' then
    CheckSubscript(N);
  for I:= 0 to N.ChildCount - 1 do Visit(N.Child(I));
  if Pushed then FScopes.Delete(FScopes.Count - 1);
end;

function TBnRun.Run(const ARoot: TTSNode): TArray<TLintFinding>;
begin
  FRoot:= ARoot;
  CollectNamed(ARoot);
  CollectGlobals(ARoot);
  Visit(ARoot);
  Result:= FFindings.ToArray;
end;

{ ---- the checker entry point -------------------------------------------- }

class function TBoundsNilChecker.Check(const AFile: string; const ACfg: TLintConfig;
  const AStore: ISymbolStore; AFileId: Int64): TArray<TLintFinding>;  // dl:ok unused-parameter@255c -- AFileId: signature fixed by the shared checker shape
var
  PF : TParsedFile;
  Run: TBnRun;
begin
  Result:= nil;
  PF:= TAstParseCache.Get(AFile);
  if PF.Tree = nil then Exit;
  Run:= TBnRun.Create(AFile, PF.Src, ACfg.IndexGuardExceptionClass, AStore);
  try
    Result:= Run.Run(PF.Tree.RootNode);
  finally
    Run.Free;
  end;
end;

{ ---- the copy-paste-assignment fixer ------------------------------------ }

{ Rewrites the odd row's right-hand member to the left-hand member:
  `R.Top := A.Left` -> `R.Top := A.Top`. Single-line assignments only. }
function FixCopyPasteAssignment(const AFinding: TLintFinding; ALines: TStringList): TArray<TTextEdit>;
var
  Line, Span, Lhs, Rhs, PMember, RPrefix, NewRhs: string;
  AssignAt, RhsStart, DotL, DotR: Integer;
  E: TTextEdit;
begin
  Result:= nil;
  if (AFinding.StartLine <> AFinding.EndLine) or (AFinding.StartLine < 1) or (AFinding.StartLine > ALines.Count) then Exit;
  Line:= ALines[AFinding.StartLine - 1];
  Span:= Copy(Line, AFinding.StartCol, AFinding.EndCol - AFinding.StartCol);
  AssignAt:= Pos(':=', Span);
  if AssignAt < 2 then Exit;
  Lhs:= Trim(Copy(Span, 1, AssignAt - 1));
  Rhs:= Trim(Copy(Span, AssignAt + 2, MaxInt));
  DotL:= LastDelimiter('.', Lhs);
  DotR:= LastDelimiter('.', Rhs);
  if (DotL < 2) or (DotR < 2) then Exit;
  PMember:= Copy(Lhs, DotL + 1, MaxInt);
  RPrefix:= Copy(Rhs, 1, DotR);
  NewRhs:= RPrefix + PMember;
  if SameText(NewRhs, Rhs) then Exit;
  RhsStart:= AFinding.StartCol + AssignAt + 1;
  while (RhsStart <= Length(Line)) and (Line[RhsStart] = ' ') do Inc(RhsStart);
  E:= Default(TTextEdit);
  E.FilePath  := AFinding.FilePath;
  E.Kind      := tekReplaceInLine;
  E.Line      := AFinding.StartLine;
  E.Col       := RhsStart;
  E.EndCol    := RhsStart + Length(Rhs);
  E.Text      := NewRhs;
  E.ExpectText:= Rhs;
  Result:= [E];
end;

{ ---- the index-possibly-out-of-range fixer ------------------------------- }

{ Inserts `if not InRange(i, Low(A), High(A)) then raise <Ex>.CreateFmt(...)` on its own line
  before each anchorable access the findings name, at that statement's indentation, and adds
  System.Math / System.SysUtils to the uses clause when missing. Everything it needs is in the
  finding message (`reaches A[i] at line N ... (in R; fix raises Ex at line K)`), so a cached
  finding fixes the same way. A finding whose anchor line no longer contains `A[i` is skipped. }
function FixIndexPossiblyOutOfRange(const APath: string; const AFindings: TArray<TLintFinding>; out AFixed: Integer): TArray<TTextEdit>;
const
  MSG_RE = 'reaches (\w+)\[(\w+)\] at line (\d+) .*\(in ([^;]*); fix raises ([\w.]+) at line (\d+)\)$';
  G_ARR = 1;
  G_IDX = 2;
  G_ACCESS = 3;
  G_ROUTINE = 4;
  G_CLASS = 5;
  G_ANCHOR = 6;
var
  Lines: TStringList;
  M: TMatch;
  Arr, Idx, Routine, ExClass, Indent, Text, Key: string;
  AccessLine, Anchor, L: Integer;
  Seen: TDictionary<string, Boolean>;
  E: TTextEdit;
  Found: Boolean;
begin
  Result:= nil;
  AFixed:= 0;
  Lines:= TStringList.Create;
  Seen:= TDictionary<string, Boolean>.Create;
  try
    Lines.AddStrings(TLiveDocuments.ReadLines(APath));
    for var F: TLintFinding in AFindings do
    begin
      if not SameText(F.RuleId, RULE_INDEX_RANGE) or not SameText(F.FilePath, APath) then Continue;
      M:= TRegEx.Match(F.Message, MSG_RE);
      if not M.Success then Continue;
      Arr       := M.Groups[G_ARR].Value;
      Idx       := M.Groups[G_IDX].Value;
      AccessLine:= StrToIntDef(M.Groups[G_ACCESS].Value, 0);
      Routine   := M.Groups[G_ROUTINE].Value;
      ExClass   := M.Groups[G_CLASS].Value;
      Anchor    := StrToIntDef(M.Groups[G_ANCHOR].Value, 0);
      if (Anchor < 1) or (Anchor > Lines.Count) or (AccessLine < Anchor) or (AccessLine > Lines.Count) then Continue;
      Found:= False;
      for L:= Anchor to AccessLine do
        if ContainsText(Lines[L - 1], Arr + '[' + Idx) then Found:= True;
      if not Found then Continue;
      Indent:= Copy(Lines[Anchor - 1], 1, Length(Lines[Anchor - 1]) - Length(TrimLeft(Lines[Anchor - 1])));
      Text:= Format('%sif not InRange(%s, Low(%s), High(%s)) then raise %s.CreateFmt(''%s index %%d outside %%d..%%d in %s'', [%s, Low(%s), High(%s)]);',
        [Indent, Idx, Arr, Arr, ExClass, Arr, Routine, Idx, Arr, Arr]);
      Key:= IntToStr(Anchor) + #1 + LowerCase(Text);
      Inc(AFixed);
      if Seen.ContainsKey(Key) then Continue;
      Seen.Add(Key, True);
      E:= Default(TTextEdit);
      E.FilePath:= APath;
      E.Kind    := tekInsertLines;
      E.Line    := Anchor - 1;      { insert AFTER line Anchor-1 = before the access's statement }
      E.Text    := Text;
      Result:= Result + [E];
    end;
    if Length(Result) = 0 then Exit;
    if EnsureImplUses(APath, Lines, 'System.Math', E) then Result:= Result + [E];
    if EnsureImplUses(APath, Lines, 'System.SysUtils', E) then Result:= Result + [E];
  finally
    Seen.Free;
    Lines.Free;
  end;
end;

initialization
  RegisterFixer(RULE_COPY_PASTE, FixCopyPasteAssignment, True);
  RegisterFileFixer(RULE_INDEX_RANGE, FixIndexPossiblyOutOfRange, True);
  MarkFixManualOnly(RULE_INDEX_RANGE);  { owner C3 2026-11-17: never applied by a batch fix }

end.
