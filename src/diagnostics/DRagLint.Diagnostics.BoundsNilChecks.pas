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
    Unsigned: Boolean; { 1.52.1 SLZ-RULE2: declared Cardinal / Word / Byte / UInt64 ... (never negative) }
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
    Sentinel: Boolean;          { 1.52.1 SLZ-RULE2: a dominating guard excludes the not-found sentinel (`<> -1`, `>= 0`) }
    Foreign: Boolean;           { 1.52.3 IDXRANGE-TP: Info was read from the index (another unit's array) }
  end;

  { index-possibly-out-of-range (1.53 SLZ-IDXFP): one side of array Arr (its least index: Lower; else its
    greatest) that a value is asked to be on. }
  TSideQ = record
    Arr  : string;
    Info : TDeclInfo;
    Lower: Boolean;
  end;

  { A value being proven: the offset it is proven with, and how many writes the path had passed. }
  TSideMark = record
    Off  : Integer;
    Steps: Integer;
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
    FArgModes  : TDictionary<string, string>;     { 1.52.1 SLZ-RULE2: routine name declared in this file -> 'v'/'r' per parameter ('?' overloads disagree) }
    FIdentCnt  : TDictionary<string, Integer>;    { 1.53 SLZ-IDXFP: identifier -> how often the file names it (BuildCallIndex) }
    FDefCount  : TDictionary<string, Integer>;    { last name part -> number of routine bodies }
    FDefNode   : TDictionary<string, TTSNode>;    { last name part -> its last body }
    FPrivDecls : TDictionary<string, Integer>;    { member name -> 1: its one declaration is private to the file and not virtual; 0 otherwise }
    FSideVisit : TDictionary<string, TSideMark>;  { SideOf: what is being proven (chains back) }
    FSideNodes : TDictionary<string, TArray<TTSNode>>; { EventsOf / AccessesOf per routine and name }
    FStoreModes: TDictionary<string, string>;     { routine name -> by-value letters of its parameters in the index }
    FSideBudget: Integer;                         { SideOf: expressions left to read for this access }
    FSideWrites: Integer;                         { SideOf: writes passed on the current path }
    FSideRoutines: Integer;                       { SideOf: routines entered on the current path }
    procedure BuildArgModes;
    function StoreArgByValue(const AFn: string; APos: Integer): Boolean;
    function LocalArgByValue(const ACall: TTSNode; APos: Integer): Boolean;
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
    function IsBoundedArrayOrStore(const AName: string; out AInfo: TDeclInfo): Boolean;
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
    function OneValue(const AX: string; const AAt: TTSNode): Boolean;
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
    function ModOfLen(const E: TTSNode; const AArr: string; ALower: Boolean): Boolean;
    function LocalFunction(const AName: string): Boolean;
    function CallDerived(const ACtx: TIdxCtx): Boolean;
    function IsSentinel(const E: TTSNode): Boolean;
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
    function ProvenOverrun(const ACtx: TIdxCtx): Boolean;
    function WhileExitUpper(const ACtx: TIdxCtx; out AV: Integer): Boolean;
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
    function ValuePeeled(const E: TTSNode): TTSNode;
    function NonNegOf(const E: TTSNode): Boolean;
    function IsStepDown(const W: TTSNode; const AX: string): Boolean;
    function EventsOf(const AX: string): TArray<TTSNode>;
    function EventsIn(const AX: string; const ANode: TTSNode): TArray<TTSNode>;
    function AccessesOf(const AArr: string): TArray<TTSNode>;
    function GrowsOnly(const N: TTSNode; const AArr: string): Boolean;
    function ShrunkIn(const AArr: string; AFrom, ATo: Cardinal): Boolean;
    function SideKept(const AX: string; AFrom: Cardinal; const AAt: TTSNode; ALower: Boolean): Boolean;
    function SplitName(const N0: TTSNode; const AX: string; out AK: Integer; out ASlack: TTSNode): Boolean;
    function FactSide(const C: TTSNode; const AX: string; ANegate: Boolean; const AQ: TSideQ; AOff, ADepth: Integer): Boolean;
    function PredicateSide(const ACall: TTSNode; const AX: string; const AQ: TSideQ; AOff, ADepth: Integer): Boolean;
    function GuardHolds(const ACond: TTSNode; ANegate: Boolean; AFrom: Cardinal; const AX: string; const AAt: TTSNode; const AQ: TSideQ; AOff, ADepth: Integer): Boolean;
    function LastStatement(const ABlock: TTSNode): TTSNode;
    function SiblingSide(const S: TTSNode; const AX: string; const AAt: TTSNode; const AQ: TSideQ; AOff, ADepth: Integer): Boolean;
    function RunsInBlock(const N, AThen: TTSNode): Boolean;
    function GuardSide(const AX: string; const AAt: TTSNode; const AQ: TSideQ; AOff, ADepth: Integer): Boolean;
    function RunsBefore(const N, AAt: TTSNode): Boolean;
    procedure NameFacts(const C: TTSNode; const AX: string; ANegate: Boolean; AFacts: TList<string>);
    function NamesChange(const ATxt: string; AFrom: Cardinal; const AAt: TTSNode): Boolean;
    procedure FactsAt(const AX: string; const AAt: TTSNode; AFacts: TList<string>);
    function GuardedBefore(const S: TTSNode; const AX: string; const AAt: TTSNode; ALower: Boolean): Boolean;
    function NamedElsewhere(const AProc: TTSNode; const AX: string): Boolean;
    function CheckedAccess(const S: TTSNode; const AX: string; const AQ: TSideQ): Boolean;
    function PriorSide(const AX: string; const AAt: TTSNode; const AQ: TSideQ; AOff: Integer): Boolean;
    function GrownAfter(const W: TTSNode; const AX: string; const AQ: TSideQ): Boolean;
    function ReadCap(const ARhs: TTSNode; const AQ: TSideQ): Integer;
    function ClampOf(const W: TTSNode; const AX: string; ALower: Boolean): Boolean;
    function LastOfAppended(const W: TTSNode; const AQ: TSideQ): Boolean;
    function EventSide(const W: TTSNode; const AX: string; const AQ: TSideQ; AOff, ADepth: Integer): Boolean;
    function ResizedSide(const W, AAt: TTSNode; const AQ: TSideQ; AOff, ADepth: Integer): Boolean;
    function WritesSide(const AX: string; const AAt: TTSNode; const AQ: TSideQ; AOff, ADepth: Integer): Boolean;
    function SideLocal(const AX: string): Boolean;
    function SideRevisited(const AKey: string; const AQ: TSideQ; AOff: Integer; out AHolds: Boolean): Boolean;
    procedure SideEnter(const AKey: string; AOff, ASteps: Integer);
    function IdentSide(const AX: string; const AAt: TTSNode; const AQ: TSideQ; AOff, ADepth: Integer): Boolean;
    function ElementSide(const AColl: string; const AQ: TSideQ; AOff, ADepth: Integer): Boolean;
    function SeenCalls(const AProc: TTSNode; out ASites: TList<TTSNode>): Boolean;
    function ArrayOwner(const AFrom: TTSNode; const AArr: string): TTSNode;
    function OuterClass(const N: TTSNode): string;
    function SameOuterArray(const AProc, AOther: TTSNode; const AArr: string): Boolean;
    function CallersSide(const AX: string; const AQ: TSideQ; AOff, ADepth: Integer): Boolean;
    function CalleeSide(const ACall: TTSNode; const AQ: TSideQ; AOff, ADepth, AOutArg: Integer): Boolean;
    function LengthNamed(const N: TTSNode; out AB: string; out AOff: Integer): Boolean;
    function SymSide(const N: TTSNode; const AQ: TSideQ; AOff: Integer): Boolean;
    function ConstSide(AV: Integer; const AQ: TSideQ): Boolean;
    function SideOf(const E: TTSNode; const AQ: TSideQ; AOff, ADepth: Integer): Boolean;
    function ChosenSide(const AIf: TTSNode; AElse: Boolean; const AQ: TSideQ; AOff, ADepth: Integer): Boolean;
    function ZeroBased(const AQ: TSideQ): TSideQ;
    function ElementRead(const N: TTSNode): Boolean;
    function CallSide(const N: TTSNode; const AQ: TSideQ; AOff, ADepth: Integer): Boolean;
    function HalfSide(const L, R: TTSNode; AShift: Boolean; const AQ: TSideQ; AOff, ADepth: Integer): Boolean;
    function SizeEvents(const AName: string; const AScope: TTSNode): TArray<TTSNode>;
    function SizeKey(const W: TTSNode; const AName: string): string;
    function SizePrefix(const W: TTSNode; const AName: string): string;
    function SizedTogether(const X, Y: TTSNode): Boolean;
    function SizeReadChanged(const X, Y: TTSNode; const AKey: string): Boolean;
    function PassedByRefLocally(const N: TTSNode; const A, B: string): Boolean;
    function TwinArrays(const A, B: string; ADepth: Integer): Boolean;
    function SizedOnce(const A, B: string; const AEvA, AEvB: TArray<TTSNode>): Boolean;
    function SizesKept(const A, B: string; AFrom: Cardinal): Boolean;
    function EnsuresLength(const S: TTSNode; const A, B: string): Boolean;
    function LengthCond(const C: TTSNode; ANegate: Boolean; const A, B: string): Boolean;
    function MappedArray(const A, B: string): Boolean;
    function LenAtLeast(const A, B: string): Boolean;
    function AccessSide(const ACtx: TIdxCtx; ALower: Boolean): Boolean;
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
  FStoreModes:= TDictionary<string, string>.Create;
  FSideVisit:= TDictionary<string, TSideMark>.Create;
  FSideNodes:= TDictionary<string, TArray<TTSNode>>.Create;
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
  FArgModes.Free;
  FCalleeLen.Free;
  FBoundMemo.Free;
  FBoundVisit.Free;
  FStoreArr.Free;
  FCallOk.Free;
  FStoreModes.Free;
  FSideNodes.Free;
  FSideVisit.Free;
  FPrivDecls.Free;
  FDefNode.Free;
  FDefCount.Free;
  FIdentCnt.Free;
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
  if not TypeN.IsNull then
  begin
    Info.Kind:= ClassifyType(Txt(TypeN), Info.Lo, Info.Hi);
    Info.Unsigned:= MatchText(Trim(Txt(TypeN)), ['Cardinal', 'LongWord', 'DWORD', 'UInt32', 'UInt64', 'NativeUInt',
      'Word', 'UInt16', 'Byte', 'UInt8']);
  end;
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
  BY_VALUE_FNS: array[0..51] of string = ('length', 'high', 'low', 'ord', 'chr', 'inttostr', 'format',
    'abs', 'min', 'max', 'succ', 'pred', 'odd', 'sqr', 'trunc', 'round', 'assigned', 'sizeof', 'inttohex', 'inrange',
    'sametext', 'samestr', 'comparetext', 'comparestr', 'uppercase', 'lowercase', 'trim', 'trimleft', 'trimright',
    'quotedstr', 'strtoint', 'strtointdef', 'containstext', 'containsstr',
    'exit', 'write', 'writeln', 'integer', 'int64', 'cardinal', 'nativeint', 'nativeuint', 'word', 'byte', 'boolean', 'char',
    'uint64', 'dword', 'longint', 'stringofchar', 'sleep', 'ifthen');
  FLOAT_ROUNDERS: array[0..3] of string = ('floor', 'trunc', 'round', 'ceil');
  CONTROL_NODES: array[0..11] of string = ('if', 'ifElse', 'while', 'for', 'foreach', 'repeat', 'case',
    'caseCase', 'exceptionHandler', 'exprIf', 'exprBinary', 'lambda');

{ AFn takes its argument number APos (0-based) by value: a by-value RTL routine, or a by-value
  position of an RTL routine with a by-reference parameter. Anything else may write a bare variable. }
function ArgByValue(const AFn: string; APos: Integer): Boolean;
const
  BY_VALUE_AT: array[0..18] of string = ('readbuffer:1', 'writebuffer:1', 'move:2', 'fillchar:1,2', 'setlength:1',
    'getstring:1,2', 'delete:1,2', 'insert:0,2', 'copy:0,1,2', 'pos:0,1,2', 'trygetvalue:0', 'containskey:0', 'addorsetvalue:0,1',
    'add:0,1', 'push:0', 'enqueue:0', 'contains:0', 'indexof:0', 'substring:0,1');
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

{ ATxt lower-cased without blanks (a text comparison of two small expressions). }
function TightText(const ATxt: string): string;
begin
  Result:= LowerCase(TRegEx.Replace(ATxt, '\s+', ''));
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
    if (not Lookup(AArr, Info)) and not StoreArray(AArr, Info) then Info:= Default(TDeclInfo);
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
    if (BareIdent(A.NamedChild(J)) = AX) and not (ArgByValue(Fn, J) or LocalArgByValue(ACall, J) or StoreArgByValue(Fn, J)) then Exit(True);
end;

{ 1.53 SLZ-IDXFP (PurityStage:1221 BeatProgress(I)): every routine AFn the index knows (lint --db) takes
  its argument number APos by value; False when it knows none. Cached per name as 'v' / 'r' letters. }
function TBnRun.StoreArgByValue(const AFn: string; APos: Integer): Boolean;
var
  S: TSymbol;
  Modes, One, Part, Head: string;
  M: TMatch;
  Have: Boolean;
  I: Integer;
begin
  if FStore = nil then Exit(False);
  if not FStoreModes.TryGetValue(AFn, Modes) then
  begin
    Modes:= '';
    Have:= False;
    for S in FStore.FindSymbolsByExactName(AFn) do
    begin
      if S.Kind not in [skFunction, skProcedure, skMethod, skConstructor] then Continue;
      One:= '';
      M:= TRegEx.Match(S.Signature, '^\s*\(([^()]*)\)');
      if not M.Success then One:= '?'
      else
        for Part in M.Groups[1].Value.Split([';']) do
        begin
          Head:= LowerCase(Trim(Part));
          for I:= 0 to Length(Copy(Head, 1, Pos(':', Head + ':') - 1).Split([','])) - 1 do
            One:= One + (if TRegEx.IsMatch(Head, '^(\[[^\]]*\]\s*)?(var|out)\b') then 'r' else 'v');
        end;
      Modes:= if Have and (Modes <> One) then '?' else One;
      Have:= True;
    end;
    FStoreModes.Add(AFn, Modes);
  end;
  Result:= (APos < Length(Modes)) and (Modes[APos + 1] = 'v');
end;

{ 1.52.1 SLZ-RULE2 (self-LoopZero, ProjectRules.pas:1805): every routine header in this file
  (bodies, forwards, class members), by its last name part -> one letter per parameter, 'r' for
  var / out (the callee may write the argument), 'v' otherwise. Two headers of one name that
  disagree (overloads, homonyms) store '?', which answers nothing. }
procedure TBnRun.BuildArgModes;

  function ModesOf(const AHeader: TTSNode): string;
  var
    I, J: Integer;
    Arg, C, Ty, Dv: TTSNode;
    ByRef: Boolean;
    Args: TTSNode;
    SB: TStringBuilder;
  begin
    Result:= '';
    Args:= Default(TTSNode);
    for I:= 0 to AHeader.NamedChildCount - 1 do
      if AHeader.NamedChild(I).NodeType = 'declArgs' then Args:= AHeader.NamedChild(I);
    if Args.IsNull then Exit;
    SB:= TStringBuilder.Create;
    try
      for I:= 0 to Args.NamedChildCount - 1 do
      begin
        Arg:= Args.NamedChild(I);
        if Arg.NodeType <> 'declArg' then Continue;
        Ty:= Arg.ChildByField('type');
        Dv:= Arg.ChildByField('defaultValue');
        ByRef:= False;
        for J:= 0 to Arg.ChildCount - 1 do
          if (Arg.Child(J).NodeType = 'kVar') or (Arg.Child(J).NodeType = 'kOut') then ByRef:= True;
        for J:= 0 to Arg.NamedChildCount - 1 do
        begin
          C:= Arg.NamedChild(J);
          if (C.NodeType <> 'identifier') or (C = Ty) or (C = Dv) then Continue;
          SB.Append(if ByRef then 'r' else 'v');
        end;
      end;
      Result:= SB.ToString;
    finally
      SB.Free;
    end;
  end;

  procedure Walk(const N: TTSNode);
  var
    I: Integer;
    Nm, M, Old: string;
  begin
    if N.IsNull then Exit;
    if N.NodeType = 'declProc' then
    begin
      Nm:= LowerCase(Trim(Txt(N.ChildByField('name'))));
      if ContainsStr(Nm, '.') then Nm:= Copy(Nm, LastDelimiter('.', Nm) + 1, MaxInt);
      M:= ModesOf(N);
      if Nm <> '' then
        if not FArgModes.TryGetValue(Nm, Old) then FArgModes.Add(Nm, M)
        else if Old <> M then FArgModes[Nm]:= '?';
    end;
    for I:= 0 to N.ChildCount - 1 do Walk(N.Child(I));
  end;

begin
  FArgModes:= TDictionary<string, string>.Create;
  Walk(FRoot);
end;

{ True when ACall names a routine declared in this file (a bare name, not `X.Foo`) whose
  parameter at APos is a value / const parameter, so the call cannot change the argument. }
function TBnRun.LocalArgByValue(const ACall: TTSNode; APos: Integer): Boolean;
var
  Ent: TTSNode;
  M: string;
begin
  Result:= False;
  Ent:= ACall.ChildByField('entity');
  if Ent.IsNull or (Ent.NodeType <> 'identifier') then Exit;
  if FArgModes = nil then BuildArgModes;
  if not FArgModes.TryGetValue(LowerCase(Trim(Txt(Ent))), M) then Exit;
  Result:= (APos >= 0) and (APos < Length(M)) and (M[APos + 1] = 'v');
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

{ 1.52.3 IDXRANGE-TP (uINSPRSLT:5575 reads MscConst.NssDistConvert[i]): IsBoundedArray, else AName as
  a const / var array of ANOTHER unit read from the index (StoreArray). A declaration this unit can see
  always wins, also when it is no array. }
function TBnRun.IsBoundedArrayOrStore(const AName: string; out AInfo: TDeclInfo): Boolean;
begin
  Result:= IsBoundedArray(AName, AInfo) or ((not Lookup(AName, AInfo)) and StoreArray(AName, AInfo));
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
  V: Integer;
begin
  Op:= OperatorType(E);
  { 1.52.1 SLZ-RULE2 (D): `idx <> NOT_FOUND` (or the else / after-Exit side of `idx = NOT_FOUND`) with a
    negative sentinel. It proves no side by itself; CheckIndexAccess accepts it for a call-derived index
    (the IndexOf contract: the callee returns the sentinel or a valid index). }
  if (Op = 'kEq') or (Op = 'kNeq') then
  begin
    if BareIdent(E.ChildByField('lhs')) = ACtx.Idx then Other:= E.ChildByField('rhs')
    else if BareIdent(E.ChildByField('rhs')) = ACtx.Idx then Other:= E.ChildByField('lhs')
    else Exit;
    if ((Op = 'kNeq') <> ANegate) and IsSentinel(Other) then ACtx.Sentinel:= True;
    Exit;
  end;
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
  { 1.52.1 SLZ-RULE2 (D): `idx >= 0` / `idx > -1` (or `if idx < 0 then Continue`) is the same sentinel test }
  if ((Op = 'kGte') or (Op = 'kGt')) and EvalIndex(Other, V) then
    ACtx.Sentinel:= ACtx.Sentinel or (V = (if Op = 'kGte' then 0 else -1));
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
  if not Result then Result:= ModOfLen(Rhs, ACtx.Arr, ALower);  { 1.52.1 SLZ-RULE2 (E) }
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
    ACtx.Sentinel:= False;
    ClimbGuards(ACtx);
    if ACtx.Silent or (ACtx.Lo and ACtx.Hi) then Exit;
    { 1.52.1 SLZ-RULE2 (D): a call-derived index behind a sentinel guard (CyclePlan.pas:2680) }
    if ACtx.Sentinel and CallDerived(ACtx) then Exit;
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
    { 1.53 SLZ-IDXFP: each side through guards, writes, callers and equal lengths }
    if (not ACtx.Lo) and AccessSide(ACtx, True) then ACtx.Lo:= True;
    if (not ACtx.Hi) and AccessSide(ACtx, False) then ACtx.Hi:= True;
    if ACtx.Lo and ACtx.Hi then Exit;
    { 1.52.3 IDXRANGE-TP: another unit's array is reported on a PROVEN overrun only (its own unit's
      guards and clamps are not this rule's view; the ORM3 FP set kept 0 new FPs this way) }
    if ACtx.Foreign and not ProvenOverrun(ACtx) then Exit;
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

{ The local AX is written once, outside any loop, by a statement every path to AAt has run: it reads as
  one value from there on. }
function TBnRun.OneValue(const AX: string; const AAt: TTSNode): Boolean;
var
  Evs: TArray<TTSNode>;
begin
  Result:= False;
  if FCurProc.IsNull or (not IsOwnLocal(AX)) or not NodeWithin(AAt, FCurProc) then Exit;
  Evs:= EventsOf(AX);
  Result:= (Length(Evs) = 1) and (Evs[0].NodeType = 'assignment') and (not IsInLoop(Evs[0])) and StmtDominates(Evs[0], AAt)
    and not NameEscapes(FCurProc, AX, False);
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
      Result:= ArrFn(Copy(Al, 1, Pos(':', Al) - 1), Copy(Al, Pos(':', Al) + 1, MaxInt));
    if Result.Ok then Exit;
    if WritesOf(X) = 0 then
      Result:= MkSym('id:' + X, 0)
    else if OneValue(X, N) then
      Result:= MkSym('id:' + X, 0)  { 1.53 SLZ-IDXFP: `N := ..` once; SetLength(A, N); .. < N }
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
  Rows   : TList<string>;  { AArr and the local arrays it exchanges whole values with }
  RowMoves, K: Integer;
  RowLoop: Boolean;
  Cur    : string;         { the array Walk reads the size changes of }

  { `B` / `Copy(B)` of another local dynamic array that is no parameter, else '' }
  function RowSource(const ARhs: TTSNode): string;
  var
    R, A: TTSNode;
    I2: TDeclInfo;
  begin
    R:= Peeled(ARhs);
    if (not R.IsNull) and (R.NodeType = 'exprCall') and (BareIdent(R.ChildByField('entity')) = 'copy') then
    begin
      A:= R.ChildByField('args');
      if A.IsNull or (A.NamedChildCount <> 1) then Exit('');
      R:= A.NamedChild(0);
    end;
    Result:= BareIdent(R);
    if (Result = '') or (Result = Cur) or not (IsOwnLocal(Result) and Lookup(Result, I2) and (I2.Kind in [dkDynArray, dkOther]) and not I2.IsParam) then Result:= '';
  end;

  function CopyOfParam(const ARhs: TTSNode; out AS1: TSym): Boolean;
  var
    M: TMatch;
    P: string;
  begin
    AS1:= Default(TSym);
    M:= TRegEx.Match(TightText(Txt(ARhs)), '^(?:copy\((\w+)\)|(\w+))$');
    if not M.Success then Exit(False);
    P:= M.Groups[1].Value;
    if P = '' then P:= M.Groups[2].Value;
    Result:= (IndexStr(P, ParamNames(FCurProc)) >= 0) and (Length(SizeEvents(P, FCurProc.ChildByField('body'))) = 0);
    if Result then AS1:= MkSym(LEN_BASE + P, 0);
  end;

  procedure Walk(const N: TTSNode);
  var
    I, J: Integer;
    Fn: string;
    Args: TTSNode;
    S: TSym;
  begin
    if N.IsNull or Bad then Exit;
    if (N.NodeType = 'lambda') or (N.NodeType = 'defProc') then Exit;
    if (N.NodeType = 'assignment') and (AssignTarget(N) = Cur) then
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
      else if (not IsInLoop(N)) and CopyOfParam(N.ChildByField('rhs'), S) then
      begin
        { 1.53 SLZ-IDXFP: `A := Copy(P)` of a parameter the routine never resizes }
        if Have and ((S.Base <> Found.Base) or (S.Off <> Found.Off)) then Bad:= True
        else
        begin
          Found:= S;
          Have:= True;
        end;
      end
      else if RowSource(N.ChildByField('rhs')) <> '' then
      begin
        { 1.53 SLZ-IDXFP: `Prev := Copy(Cur)` / `Prev := Cur` (row swap): every array of the group has one size }
        if Rows.IndexOf(RowSource(N.ChildByField('rhs'))) < 0 then Rows.Add(RowSource(N.ChildByField('rhs')));
        Inc(RowMoves);
        if IsInLoop(N) then RowLoop:= True;
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
        if (Fn = 'setlength') and (BareIdent(Args.NamedChild(0)) = Cur) then
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
        else if ((Fn = 'delete') and (BareIdent(Args.NamedChild(0)) = Cur))
          or ((Fn = 'insert') and (BareIdent(Args.NamedChild(1)) = Cur)) then
          Bad:= True
        else
          { 1.52 IDXRANGE3 (YADF.Layout:2638): a call whose routine sizes this out / var argument by
            another argument's Count / Length first (CalleeSizes) counts as that SetLength }
          for J:= 0 to Args.NamedChildCount - 1 do
            if BareIdent(Args.NamedChild(J)) = Cur then
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
    Rows:= TList<string>.Create;
    try
      Rows.Add(AArr);
      RowMoves:= 0;
      RowLoop:= False;
      K:= 0;
      while (K < Rows.Count) and not FCurProc.IsNull do
      begin
        Cur:= Rows[K];
        Walk(FCurProc.ChildByField('body'));
        Inc(K);
      end;
      { no size known for the group: a whole assignment of another array is what it was before }
      if not Have then
      begin
        Inc(Assigns, RowMoves);
        Bad:= Bad or RowLoop;
      end;    finally
      Rows.Free;
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
    if EvalIndex(A2, V) then Exit(MkSym('', V));
    { 1.53 SLZ-IDXFP (ArchDiagram:382): a field the file assigns once reads as one value in every routine }
    if (BareIdent(A2) <> '') and ArrayOwner(EnclosingProc(A2), BareIdent(A2)).IsNull and FGlobals.ContainsKey(BareIdent(A2))
      and (Length(SizeEvents(BareIdent(A2), FRoot)) = 1) then Result:= MkSym('id:' + BareIdent(A2), 0);
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

{ 1.52.1 SLZ-RULE2 (E, Q.ExceptionPaths.pas:417): E is `X mod Length(AArr)` under integer casts. Its
  magnitude is below Length(AArr), so the upper side holds; the lower side (ALower) holds only when the
  dividend cannot be negative -- an unsigned cast (`Cardinal(H)`, `UInt64(H)`) or a name declared
  unsigned. `AKey mod Length(A)` with a signed AKey stays unproven (Delphi's mod keeps the sign). }
function TBnRun.ModOfLen(const E: TTSNode; const AArr: string; ALower: Boolean): Boolean;
const
  CASTS   : array[0..11] of string = ('integer', 'longint', 'int32', 'int64', 'nativeint', 'cardinal',
    'longword', 'dword', 'uint32', 'uint64', 'nativeuint', 'word');
  UNSIGNED: array[0..6] of string = ('cardinal', 'longword', 'dword', 'uint32', 'uint64', 'nativeuint', 'word');

  function Strip(const N: TTSNode; out ACast: string): TTSNode;
  var
    A: TTSNode;
  begin
    Result:= N;
    ACast:= '';
    while not Result.IsNull do
      if (Result.NodeType = 'exprParens') and (Result.NamedChildCount = 1) then Result:= Result.NamedChild(0)
      else if (Result.NodeType = 'exprCall') and (IndexStr(BareIdent(Result.ChildByField('entity')), CASTS) >= 0) then
      begin
        A:= Result.ChildByField('args');
        if A.IsNull or (A.NamedChildCount <> 1) then Exit;
        ACast:= BareIdent(Result.ChildByField('entity'));
        Result:= A.NamedChild(0);
      end
      else Exit;
  end;

  function UnsignedCast(const N: TTSNode): Boolean;
  var
    C: string;
  begin
    Strip(N, C);
    Result:= IndexStr(C, UNSIGNED) >= 0;
  end;

var
  N, L: TTSNode;
  Cast: string;
  Info: TDeclInfo;
begin
  Result:= False;
  N:= Strip(E, Cast);
  if N.IsNull or (N.NodeType <> 'exprBinary') or not SameText(Trim(Txt(N.ChildByField('operator'))), 'mod')
    or not IsArrayFn(Strip(N.ChildByField('rhs'), Cast), 'length', AArr) then Exit;
  if not ALower then Exit(True);
  L:= Strip(N.ChildByField('lhs'), Cast);
  if not L.IsNull then
    Result:= (IndexStr(Cast, UNSIGNED) >= 0)
      or ((L.NodeType = 'identifier') and Lookup(LowerCase(Txt(L)), Info) and Info.Unsigned)
      or ((L.NodeType = 'exprBinary') and (OperatorType(L) = 'kAdd') and UnsignedCast(L.ChildByField('lhs')));  { 1.53 SLZ-IDXFP: (UInt64(B) + Incr) mod .. }
end;

{ 1.52.1 SLZ-RULE2 (D): a not-found sentinel -- a negative constant (`-1`, a file const = -1) or a
  name that says so (`NOT_FOUND`, `CNotFound`) when its value lives in another unit. }
function TBnRun.IsSentinel(const E: TTSNode): Boolean;
var
  V: Integer;
begin
  if EvalIndex(E, V) then Exit(V < 0);
  Result:= (E.NodeType = 'identifier') and ContainsText(StringReplace(Txt(E), '_', '', [rfReplaceAll]), 'notfound');
end;

{ AName is a function with a body in this file (the last part of a method's name counts). }
function TBnRun.LocalFunction(const AName: string): Boolean;
var
  Def: TTSNode;
begin
  if FCallSites = nil then BuildCallIndex;
  Result:= FDefNode.TryGetValue(AName, Def) and not Def.ChildByField('header').ChildByField('type').IsNull;
end;

{ 1.52.1 SLZ-RULE2 (D): every write of the index is `idx := F(..)` -- a routine result, not arithmetic
  or an intrinsic -- so a sentinel test leaves the callee's "valid index or sentinel" contract. }
function TBnRun.CallDerived(const ACtx: TIdxCtx): Boolean;
const
  NOT_LOOKUPS: array[0..13] of string = ('length', 'high', 'low', 'pred', 'succ', 'ord', 'abs', 'trunc', 'round',
    'random', 'min', 'max', 'integer', 'sizeof');
var
  W, R: TTSNode;
  Info: TDeclInfo;
begin
  Result:= (ACtx.Writes.Count > 0) and not ACtx.IdxInfo.IsParam;
  if not Result then Exit;
  for W in ACtx.Writes do
  begin
    if W.NodeType <> 'assignment' then Exit(False);
    R:= W.ChildByField('rhs');
    while (not R.IsNull) and (R.NodeType = 'exprParens') and (R.NamedChildCount = 1) do R:= R.NamedChild(0);
    if R.IsNull then Exit(False);
    { 1.53 SLZ-IDXFP: `c := CurrentCase` (a function of this file), `at := FList.ItemIndex` (QualifyForm:230) }
    if (R.NodeType = 'identifier') and not Lookup(LowerCase(Txt(R)), Info) and LocalFunction(LowerCase(Txt(R))) then Continue;
    if (R.NodeType = 'exprDot') and EndsText('index', Trim(Txt(R.ChildByField('rhs')))) then Continue;
    if (R.NodeType <> 'exprCall') or (IndexStr(CallName(R), NOT_LOOKUPS) >= 0) then Exit(False);
  end;
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
  static bounds. Every same-named interface const / var row must be an array with the same bounds. Cached. }
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
      { 1.52.3 IDXRANGE-TP: only an interface declaration is visible to another unit; a routine-local or
        implementation const of the same name (this unit's own are Lookup's) must not make the name ambiguous }
      if (S.Kind not in [skConstDecl, skVarDecl]) or not SameText(S.Section, 'interface') then Continue;
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

{ 1.52.3 IDXRANGE-TP: the index's bounds at the access, from its writes and guards (BoundAt), leave the
  array's static range: greater than Hi or less than Lo. False when a side is unknown. }
function TBnRun.ProvenOverrun(const ACtx: TIdxCtx): Boolean;
var
  V: Integer;
  AboveHi, BelowLo: Boolean;
begin
  AboveHi:= BoundAt(ACtx.Idx, ACtx.Access, True, 0, V) and (not IsNeutralBound(V)) and (V > ACtx.Info.Hi);
  BelowLo:= BoundAt(ACtx.Idx, ACtx.Access, False, 0, V) and (not IsNeutralBound(V)) and (V < ACtx.Info.Lo);
  Result:= AboveHi or BelowLo or (WhileExitUpper(ACtx, V) and (V > ACtx.Info.Hi));
end;

{ 1.52.3 IDXRANGE-TP (uINSPRSLT:5575 `while (H[i] = 0) and (i <= 4) do Inc(i); X:= C[i]`): the last write
  of the index before the access is a step of 1 inside a while that ends before the access and whose
  condition bounds the index by a constant G, every write in that loop a step of 1. The index can leave
  the loop at G + 1 (AV). False for a G that is not a constant (`i < Last`). }
function TBnRun.WhileExitUpper(const ACtx: TIdxCtx; out AV: Integer): Boolean;
var
  W, LastW, Wh: TTSNode;
  G: TSym;
begin
  Result:= False;
  AV:= 0;
  LastW:= Default(TTSNode);
  for W in ACtx.Writes do
    if (W.EndByte <= ACtx.Access.StartByte) and (LastW.IsNull or (W.StartByte > LastW.StartByte)) then LastW:= W;
  if LastW.IsNull or not StepWrite(LastW, ACtx.Idx) then Exit;
  Wh:= LastW.Parent;
  while (not Wh.IsNull) and (Wh.NodeType <> 'while') and (Wh.NodeType <> 'defProc') do Wh:= Wh.Parent;
  if Wh.IsNull or (Wh.NodeType <> 'while') or (Wh.EndByte > ACtx.Access.StartByte) then Exit;
  if (not CondUpperSym(Wh.ChildByField('condition'), ACtx.Idx, False, G)) or (G.Base <> '') then Exit;
  for W in ACtx.Writes do
    if (W.StartByte >= Wh.StartByte) and (W.EndByte <= Wh.EndByte) and not StepWrite(W, ACtx.Idx) then Exit;
  AV:= G.Off + 1;
  Result:= True;
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
      { 1.53 SLZ-IDXFP (FieldRepo.Check:261): `if Length(A) = 0 then Exit` / `if A = nil then Exit` }
      if (Op = 'kEq') and (TightText(Txt(E)) = AArr + '=nil') and (Result < 1) then Result:= 1;
      if not EvalIndex(E.ChildByField('rhs'), K) then Continue;
      M:= 0;
      if (Op = 'kEq') and (K = 0) and IsArrayFn(E.ChildByField('lhs'), 'length', AArr) then M:= 1;

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

  { AMember sits in a private section, or its class in the implementation section, and no directive
    (virtual, override, message ..) lets anything but a plain call reach it }
  function HiddenMember(const AMember: TTSNode): Boolean;
  var
    P: TTSNode;
    J: Integer;
  begin
    Result:= False;
    for J:= 0 to AMember.NamedChildCount - 1 do
      if (AMember.NamedChild(J).NodeType = 'procAttribute')
        and MatchText(Trim(Txt(AMember.NamedChild(J))), ['virtual', 'override', 'dynamic', 'message', 'abstract']) then Exit;
    if TRegEx.IsMatch(Txt(AMember), '(?i);\s*(virtual|override|dynamic|message|abstract)\b') then Exit;
    P:= AMember.Parent;
    while not P.IsNull do
    begin
      if P.NodeType = 'implementation' then Exit(True);
      if P.NodeType = 'declSection' then
        for J:= 0 to P.ChildCount - 1 do
          if P.Child(J).NodeType = 'kPrivate' then Exit(True);
      P:= P.Parent;
    end;
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
      Nm:= Copy(Nm, LastDelimiter('.', Nm) + 1, MaxInt);
      Bump(FDefCount, Nm, 1);
      FDefNode.AddOrSetValue(Nm, N);
    end
    else if (T = 'declProc') and not ((not N.Parent.IsNull) and (N.Parent.NodeType = 'defProc')) then
    begin
      Nm:= LowerCase(Trim(Txt(N.ChildByField('name'))));
      Bump(Decls, Nm, 1);  { a defProc's own header is not a declaration }
      { 1.53 SLZ-IDXFP: a second declaration of the name, or one other units / a descendant can reach, is 0 }
      FPrivDecls.AddOrSetValue(Nm, if HiddenMember(N) and not FPrivDecls.ContainsKey(Nm) then 1 else 0);
    end;

    for I:= 0 to N.ChildCount - 1 do Walk(N.Child(I));
  end;

var
  Pair: TPair<string, TList<TTSNode>>;
  D, Ids, Dc, UseCnt: Integer;
begin
  FCallSites:= TObjectDictionary<string, TList<TTSNode>>.Create([doOwnsValues]);
  FCallOk:= TDictionary<string, Boolean>.Create;
  FIdentCnt := TDictionary<string, Integer>.Create;
  FDefCount := TDictionary<string, Integer>.Create;
  FDefNode  := TDictionary<string, TTSNode>.Create;
  FPrivDecls:= TDictionary<string, Integer>.Create;
  Ident := FIdentCnt;
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
  if not IsBoundedArrayOrStore(AArr, Ctx.Info) then
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
      if (not Lookup(ArrAt, Info)) and not StoreArray(ArrAt, Info) then Info:= Default(TDeclInfo);
      if not (U.Ok and UpperWithin(U, ArrAt, Info)) then Exit;
    finally
      LeaveRoutine(Saved);
    end;
  end;
  Result:= True;
end;

{ ---- index-possibly-out-of-range: one side of a value at one point (1.53 SLZ-IDXFP) --------
  The provers above read one routine's literal and symbolic bounds. The ones below answer "is E + off
  on the safe side of A at this point", following the guards, the earlier accesses of the same
  element, the writes of the names E reads, the callers of a parameter and the results of a local
  function. A chain that comes back to a name it is proving holds by induction when it passed a write
  and its offset did not grow towards the bound. }

const
  MAX_SIDE_DEPTH   = 40;    { SideOf: how long a chain of names / calls is followed }
  MAX_SIDE_CALLERS = 4;     { CallersSide / CalleeSide: how many routines deep }
  SIDE_BUDGET      = 1500;  { SideOf: expressions read per access and side }
  FN_LENGTH        = 'length';
  FN_HIGH          = 'high';
  FN_SETLENGTH     = 'setlength';
  WORD_RESULT      = 'result';
  KEY_NIL          = 'nil';  { SizeKey: the array is emptied }
  KEY_TEXT         = 'txt:'; { SizeKey: + the text of the assigned value }
  KEY_APPEND       = 'app';  { SizeKey: + the number of elements appended }
  { integer casts that keep an index value }
  INT_CASTS: array[0..4] of string = ('integer', 'longint', 'int32', 'int64', 'nativeint');
  UNSIGNED_CASTS: array[0..5] of string = ('cardinal', 'longword', 'dword', 'uint32', 'uint64', 'nativeuint');

{ The statement of a statement list that holds N (N itself when it is one); null outside a list. }
function ListStatement(const N: TTSNode): TTSNode;
begin
  Result:= N;
  while not Result.IsNull do
  begin
    if Result.Parent.IsNull or (Result.NodeType = 'defProc') then Exit(Default(TTSNode));
    if (Result.Parent.NodeType = 'block') or (Result.Parent.NodeType = 'statements') then Exit;
    Result:= Result.Parent;
  end;
end;

{ `for .. downto ..`. }
function IsDownFor(const AFor: TTSNode): Boolean;
var
  I: Integer;
begin
  Result:= False;
  for I:= 0 to AFor.ChildCount - 1 do
    if AFor.Child(I).NodeType = 'kDownto' then Exit(True);
end;

{ E without parentheses and value-keeping integer casts. }
function TBnRun.ValuePeeled(const E: TTSNode): TTSNode;
var
  A: TTSNode;
begin
  Result:= Peeled(E);
  while (not Result.IsNull) and (Result.NodeType = 'exprCall') and MatchStr(BareIdent(Result.ChildByField('entity')), INT_CASTS) do
  begin
    A:= Result.ChildByField('args');
    if A.IsNull or (A.NamedChildCount <> 1) then Exit;
    Result:= Peeled(A.NamedChild(0));
  end;
  { an unsigned cast of a length reads as the length }
  if (not Result.IsNull) and (Result.NodeType = 'exprCall') and MatchStr(BareIdent(Result.ChildByField('entity')), UNSIGNED_CASTS) then
  begin
    A:= Result.ChildByField('args');
    if (not A.IsNull) and (A.NamedChildCount = 1) and NonNegOf(A.NamedChild(0)) then Result:= Peeled(A.NamedChild(0));
  end;
end;

{ E is never negative: Length / Abs / Pos, X.Count / X.Length, a constant >= 0, a name declared with
  an unsigned type, the sum of two such. }
function TBnRun.NonNegOf(const E: TTSNode): Boolean;
var
  N: TTSNode;
  V: Integer;
  Info: TDeclInfo;
begin
  N:= ValuePeeled(E);
  if N.IsNull then Exit(False);
  if EvalIndex(N, V) then Exit(V >= 0);
  if N.NodeType = 'exprCall' then Exit(MatchStr(CallName(N), [FN_LENGTH, 'abs', 'pos', 'ord', 'sizeof']));
  if N.NodeType = 'exprDot' then Exit(MatchText(Trim(Txt(N.ChildByField('rhs'))), ['count', FN_LENGTH]));
  if N.NodeType = 'identifier' then Exit(Lookup(LowerCase(Txt(N)), Info) and Info.Unsigned);
  Result:= (N.NodeType = 'exprBinary') and (OperatorType(N) = 'kAdd') and NonNegOf(N.ChildByField('lhs')) and NonNegOf(N.ChildByField('rhs'));
end;

{ W only lowers AX: `Dec(AX)`, `Dec(AX, k)` or `AX := AX - k` with a constant k >= 0. }
function TBnRun.IsStepDown(const W: TTSNode; const AX: string): Boolean;
var
  Args, R: TTSNode;
  K: Integer;
begin
  if W.NodeType = 'exprCall' then
  begin
    Args:= W.ChildByField('args');
    Exit((BareIdent(W.ChildByField('entity')) = 'dec')
      and (Args.IsNull or (Args.NamedChildCount < 2) or (EvalIndex(Args.NamedChild(1), K) and (K >= 0))));
  end;
  Result:= False;
  if W.NodeType <> 'assignment' then Exit;
  R:= W.ChildByField('rhs');
  if R.IsNull or (R.NodeType <> 'exprBinary') or (OperatorType(R) <> 'kSub') then Exit;
  Result:= (BareIdent(R.ChildByField('lhs')) = AX) and EvalIndex(R.ChildByField('rhs'), K) and (K >= 0);
end;

{ Everything in the current routine that may write the local AX: assignments, Inc / Dec, for / for-in
  loops over it, calls that may take it by reference. Cached per routine and name. }
function TBnRun.EventsOf(const AX: string): TArray<TTSNode>;
var
  L: TList<TTSNode>;
  Key: string;

  procedure Gather(const N: TTSNode);
  var
    J: Integer;
  begin
    if N.IsNull or (N.NodeType = 'lambda') or (N.NodeType = 'defProc') then Exit;
    if ((N.NodeType = 'for') and (AssignTarget(N.ChildByField('start')) = AX))
      or ((N.NodeType = 'exprCall') and PassesByRef(N, AX)) then L.Add(N);
    for J:= 0 to N.ChildCount - 1 do Gather(N.Child(J));
  end;

begin
  Key:= IntToStr(FCurProc.StartByte) + ':' + AX;
  if FSideNodes.TryGetValue(Key, Result) then Exit;
  L:= TList<TTSNode>.Create;
  try
    CollectIdxWrites(FCurProc.ChildByField('body'), AX, L);
    Gather(FCurProc.ChildByField('body'));
    Result:= L.ToArray;
  finally
    L.Free;
  end;
  FSideNodes.Add(Key, Result);
end;

{ The writes of AX inside ANode. }
function TBnRun.EventsIn(const AX: string; const ANode: TTSNode): TArray<TTSNode>;
var
  W: TTSNode;
begin
  Result:= nil;
  for W in EventsOf(AX) do
    if NodeWithin(W, ANode) then Result:= Result + [W];
end;

{ Every `AArr[..]` of the current routine's own body, in text order. Cached per routine and array. }
function TBnRun.AccessesOf(const AArr: string): TArray<TTSNode>;
var
  L: TList<TTSNode>;
  Key: string;

  procedure Gather(const N: TTSNode);
  var
    J: Integer;
  begin
    if N.IsNull or (N.NodeType = 'lambda') or (N.NodeType = 'defProc') then Exit;
    if (N.NodeType = 'exprSubscript') and (BareIdent(N.ChildByField('entity')) = AArr) then L.Add(N);
    for J:= 0 to N.ChildCount - 1 do Gather(N.Child(J));
  end;

begin
  Key:= IntToStr(FCurProc.StartByte) + '[' + AArr;
  if FSideNodes.TryGetValue(Key, Result) then Exit;
  L:= TList<TTSNode>.Create;
  try
    Gather(FCurProc.ChildByField('body'));
    Result:= L.ToArray;
  finally
    L.Free;
  end;
  FSideNodes.Add(Key, Result);
end;

{ The size change N never shortens AArr: an append, a longer SetLength (Length(A) + k, Length(A) * k,
  x + k right after x := Length(A)), one under `if .. > Length(A) then`. }
function TBnRun.GrowsOnly(const N: TTSNode; const AArr: string): Boolean;
const
  NEAR_STATEMENTS = 3;
var
  T, Len, Cond: string;
  M: TMatch;
  S, P: TTSNode;
  I: Integer;
begin
  T:= TRegEx.Replace(TightText(Txt(N)), ';$', '');
  Len:= 'length(' + AArr + ')';
  if StartsStr(AArr + ':=' + AArr + '+', T) or StartsStr('insert(', T) then Exit(True);
  Result:= StartsStr('setlength(' + AArr + ',' + Len + '+', T) or StartsStr('setlength(' + AArr + ',' + Len + '*', T);
  if Result or not StartsStr('setlength(', T) then Exit;
  M:= TRegEx.Match(T, '^setlength\(\w+,(\w+)\+\d+\)$');
  S:= ListStatement(N);
  if M.Success then
    for I:= 1 to NEAR_STATEMENTS do
    begin
      if not S.IsNull then S:= S.PrevNamedSibling;
      if (not S.IsNull) and (TRegEx.Replace(TightText(Txt(S)), ';$', '') = M.Groups[1].Value + ':=' + Len) then Exit(True);
    end;
  P:= N.Parent;
  while (not P.IsNull) and (P.NodeType <> 'if') and (IndexStr(P.NodeType, CONTROL_NODES) < 0) do P:= P.Parent;
  if P.IsNull or (P.NodeType <> 'if') then Exit;
  Cond:= TightText(Txt(P.ChildByField('condition')));
  Result:= TRegEx.IsMatch(Cond, '^[^<>=]+>=?' + TRegEx.Escape(Len) + '$') or TRegEx.IsMatch(Cond, '^' + TRegEx.Escape(Len) + '<=?[^<>=]+$');
end;

{ Something in the current routine may make AArr shorter between the bytes AFrom and ATo: a size
  change that is no append (`A := A + [..]`, `SetLength(A, Length(A) + k)`, Insert). }
function TBnRun.ShrunkIn(const AArr: string; AFrom, ATo: Cardinal): Boolean;
var
  Stack: TList<TTSNode>;
  N: TTSNode;
  I: Integer;
begin
  Result:= False;
  if ATo <= AFrom then Exit;
  Stack:= TList<TTSNode>.Create;
  try
    Stack.Add(FCurProc.ChildByField('body'));
    while (Stack.Count > 0) and not Result do
    begin
      N:= Stack.Last;
      Stack.Delete(Stack.Count - 1);
      if N.IsNull or (N.EndByte <= AFrom) or (N.StartByte >= ATo) or (N.NodeType = 'lambda') then Continue;
      if (N.StartByte >= AFrom) and IsSizeChangeOf(N, AArr) then
      begin
        Result:= not GrowsOnly(N, AArr);
      end;
      for I:= 0 to N.ChildCount - 1 do Stack.Add(N.Child(I));
    end;
  finally
    Stack.Free;
  end;
end;

{ A fact about AX read at byte AFrom still holds on its side (ALower) at AAt: no write of AX between
  them -- nor in a loop around AAt that starts after AFrom -- leaves that side. }
function TBnRun.SideKept(const AX: string; AFrom: Cardinal; const AAt: TTSNode; ALower: Boolean): Boolean;
var
  W, L: TTSNode;
  Loops: TList<TTSNode>;
  IsLoopEv, Between, Looped, Keeps: Boolean;
begin
  Result:= False;
  Loops:= TList<TTSNode>.Create;
  try
    LoopsAround(AAt, Loops);
    for W in EventsOf(AX) do
    begin
      IsLoopEv:= (W.NodeType = 'for') or (W.NodeType = 'foreach');
      Between:= (W.StartByte > AFrom) and ((W.EndByte <= AAt.StartByte) or (IsLoopEv and (W.StartByte < AAt.StartByte)));
      Looped:= False;
      for L in Loops do
        if (L.StartByte > AFrom) and NodeWithin(W, L) then Looped:= True;
      if not (Between or Looped) then Continue;
      Keeps:= if ALower then IsStepUp(W, AX) else IsStepDown(W, AX);
      if Keeps or ClampOf(W, AX, ALower) or LeavesBefore(W, AAt, AFrom, True) then Continue;
      if (not Looped) and ExclusiveBranches(W, AAt) then Continue;
      Exit;
    end;
    Result:= True;
  finally
    Loops.Free;
  end;
end;

{ N0 is AX + AK: the name itself, AX +/- a constant, a constant + AX; or AX + something never negative
  (ASlack: that something), which only an upper fact may use. }
function TBnRun.SplitName(const N0: TTSNode; const AX: string; out AK: Integer; out ASlack: TTSNode): Boolean;
var
  N, L, R: TTSNode;
  Op: string;
begin
  AK:= 0;
  ASlack:= Default(TTSNode);
  N:= ValuePeeled(N0);
  if N.IsNull then Exit(False);
  if N.NodeType = 'identifier' then Exit(LowerCase(Txt(N)) = AX);
  if N.NodeType <> 'exprBinary' then Exit(False);
  Op:= OperatorType(N);
  if (Op <> 'kAdd') and (Op <> 'kSub') then Exit(False);
  L:= ValuePeeled(N.ChildByField('lhs'));
  R:= ValuePeeled(N.ChildByField('rhs'));
  if BareIdent(L) = AX then
  begin
    if EvalIndex(R, AK) then
    begin
      if Op = 'kSub' then AK:= -AK;
      Exit(True);
    end;
    ASlack:= R;
    Exit((Op = 'kAdd') and NonNegOf(R));
  end;
  if (Op <> 'kAdd') or (BareIdent(R) <> AX) then Exit(False);
  if EvalIndex(L, AK) then Exit(True);
  ASlack:= L;
  Result:= NonNegOf(L);
end;

{ Condition C (ANegate: `not C`) puts AX + AOff on the side AQ asks for. }
function TBnRun.FactSide(const C: TTSNode; const AX: string; ANegate: Boolean; const AQ: TSideQ; AOff, ADepth: Integer): Boolean;
const
  INRANGE_ARGS = 3;
var
  E, Args, Other, Slack: TTSNode;
  Op: string;
  K, V, V2, Lo, Strict: Integer;
  Q0: TSideQ;
  Info: TDeclInfo;
begin
  Result:= False;
  E:= Peeled(C);
  if E.IsNull then Exit;
  if (E.NodeType = 'exprUnary') and (OperatorType(E) = 'kNot') then
    Exit(FactSide(E.ChildByField('operand'), AX, not ANegate, AQ, AOff, ADepth));
  Lo:= if AQ.Info.Kind = dkArray then AQ.Info.Lo else 0;
  if E.NodeType = 'exprCall' then
  begin
    Args:= E.ChildByField('args');
    if ANegate or Args.IsNull then Exit;
    if BareIdent(E.ChildByField('entity')) <> 'inrange' then Exit(PredicateSide(E, AX, AQ, AOff, ADepth));
    if (Args.NamedChildCount <> INRANGE_ARGS) or (BareIdent(Args.NamedChild(0)) <> AX) then Exit;
    Exit(SideOf(if AQ.Lower then Args.NamedChild(1) else Args.NamedChild(2), AQ, AOff, ADepth + 1));
  end;
  if E.NodeType <> 'exprBinary' then Exit;
  Op:= OperatorType(E);
  if (Op = 'kAnd') or (Op = 'kOr') then
  begin
    Result:= FactSide(E.ChildByField('lhs'), AX, ANegate, AQ, AOff, ADepth);
    { `a and b` holds (`a or b` fails): either side is a fact; otherwise both must be }
    if Result = ((Op = 'kAnd') <> ANegate) then Exit;
    Exit(FactSide(E.ChildByField('rhs'), AX, ANegate, AQ, AOff, ADepth));
  end;
  if Op = 'kIn' then
  begin
    if ANegate or (BareIdent(E.ChildByField('lhs')) <> AX) or not SetRange(E.ChildByField('rhs'), V, V2) then Exit;
    Exit(if AQ.Lower then V + AOff >= Lo else UpperWithin(MkSym('', V2 + AOff), AQ.Arr, AQ.Info));
  end;
  if SplitName(E.ChildByField('lhs'), AX, K, Slack) then Other:= E.ChildByField('rhs')
  else if SplitName(E.ChildByField('rhs'), AX, K, Slack) then
  begin
    Other:= E.ChildByField('lhs');
    Op:= MirrorOp(Op);
  end
  else Exit;
  if ANegate then
  begin
    if Op = 'kEq' then Op:= 'kNeq'
    else if Op = 'kNeq' then Op:= 'kEq'
    else Op:= NegateOp(Op);
  end;
  Strict:= if (Op = 'kLt') or (Op = 'kGt') then 1 else 0;
  if Op = 'kEq' then
    Result:= Slack.IsNull and SideOf(Other, AQ, AOff - K, ADepth + 1)
  else if (not AQ.Lower) and ((Op = 'kLt') or (Op = 'kLte')) then
  begin
    if not Slack.IsNull then
    begin
      { AX + E <= Y with E >= 1 }
      Q0:= Default(TSideQ);
      Q0.Info.Kind:= dkDynArray;
      Q0.Lower:= True;
      if SideOf(Slack, Q0, -1, ADepth + 1) then Inc(Strict);
    end;
    Result:= SideOf(Other, AQ, AOff - K - Strict, ADepth + 1);
  end
  else if AQ.Lower and Slack.IsNull and ((Op = 'kGt') or (Op = 'kGte')) then
    Result:= SideOf(Other, AQ, AOff - K + Strict, ADepth + 1)
  else if AQ.Lower and Slack.IsNull and (Op = 'kNeq') and (K = 0) and EvalIndex(Other, V) and (V + 1 + AOff >= Lo) then
    { AX <> V and AX >= V }
    Result:= ((V = 0) and Lookup(AX, Info) and Info.Unsigned) or IdentSide(AX, E, AQ, Lo - V, ADepth + 1)
  else if (not AQ.Lower) and Slack.IsNull and (Op = 'kNeq') and (K = 0) and (AOff = 0) and IsArrayFn(Other, FN_LENGTH, AQ.Arr) then
    { AX <> Length(A) and AX <= Length(A) }
    Result:= IdentSide(AX, E, AQ, -1, ADepth + 1);
end;

{ `if IsName(AX) then`: a Boolean function of this file whose body is one `Result := e` on the parameter
  AX is passed for (CallResolver:11969). }
function TBnRun.PredicateSide(const ACall: TTSNode; const AX: string; const AQ: TSideQ; AOff, ADepth: Integer): Boolean;
var
  Def, Args, OldAccess: TTSNode;
  Evs: TArray<TTSNode>;
  I, PX, PArr, Cnt: Integer;
  Q2: TSideQ;
  Saved: TBnSaved;
  Names: TArray<string>;
  Nm: string;
begin
  Result:= False;
  Nm:= BareIdent(ACall.ChildByField('entity'));
  if (Nm = '') or (FSideRoutines >= MAX_SIDE_CALLERS) then Exit;
  if FCallSites = nil then BuildCallIndex;
  if not (FDefCount.TryGetValue(Nm, Cnt) and (Cnt = 1) and FDefNode.TryGetValue(Nm, Def)) or Def.ChildByField('body').IsNull then Exit;
  if not SameText(Trim(Txt(Def.ChildByField('header').ChildByField('type'))), 'boolean') then Exit;
  Args:= ACall.ChildByField('args');
  Names:= ParamNames(Def);
  PX:= -1;
  PArr:= -1;
  for I:= 0 to Args.NamedChildCount - 1 do
    if BareIdent(Args.NamedChild(I)) = AX then PX:= I
    else if BareIdent(Args.NamedChild(I)) = AQ.Arr then PArr:= I;
  if (PX < 0) or (PX > High(Names)) or (PArr > High(Names)) then Exit;
  Q2:= AQ;
  if PArr >= 0 then Q2.Arr:= Names[PArr]
  else if not SameOuterArray(Def, FCurProc, AQ.Arr) then Exit;
  OldAccess:= FAccess;
  Inc(FSideRoutines);
  EnterRoutine(Def, Saved);
  FAccess:= Def.ChildByField('body');
  try
    if (PArr >= 0) and not IsBoundedArrayOrStore(Q2.Arr, Q2.Info) then Exit;
    Evs:= EventsOf(WORD_RESULT);
    Result:= (Length(Evs) = 1) and (Evs[0].NodeType = 'assignment') and (WritesOf(Names[PX]) = 0)
      and not TRegEx.IsMatch(Txt(FAccess), '(?i)\bexit\b') and FactSide(Evs[0].ChildByField('rhs'), Names[PX], False, Q2, AOff, ADepth + 1);
  finally
    FAccess:= OldAccess;
    LeaveRoutine(Saved);
    Dec(FSideRoutines);
  end;
end;

{ One guard (ACond, ANegate: its failure) read at byte AFrom proves AX + AOff at AAt. }
function TBnRun.GuardHolds(const ACond: TTSNode; ANegate: Boolean; AFrom: Cardinal; const AX: string; const AAt: TTSNode;
  const AQ: TSideQ; AOff, ADepth: Integer): Boolean;
begin
  Result:= (not ACond.IsNull) and Mentions(ACond, AX) and SideKept(AX, AFrom, AAt, AQ.Lower)
    and not ((not AQ.Lower) and ShrunkIn(AQ.Arr, AFrom, AAt.StartByte))
    and FactSide(ACond, AX, ANegate, AQ, AOff, ADepth + 1);
end;

{ The last statement of the block ABlock; null for anything else. }
function TBnRun.LastStatement(const ABlock: TTSNode): TTSNode;
var
  I: Integer;
begin
  Result:= Default(TTSNode);
  if ABlock.IsNull or (ABlock.NodeType <> 'block') then Exit;
  for I:= ABlock.NamedChildCount - 1 downto 0 do
    if not IsTrivia(ABlock.NamedChild(I)) then Exit(ABlock.NamedChild(I));
end;

{ An earlier statement S of a list that holds AAt proves AX + AOff: `if <fail> then <leave>`, a grow of
  the array, `if c then AX := e` (either c failed or e), a loop left through its own condition only. }
function TBnRun.SiblingSide(const S: TTSNode; const AX: string; const AAt: TTSNode; const AQ: TSideQ; AOff, ADepth: Integer): Boolean;
var
  ThenN, Last: TTSNode;
  Evs: TArray<TTSNode>;
begin
  Result:= False;
  if S.NodeType = 'if' then
  begin
    ThenN:= S.ChildByField('then');
    if not (IsLeaveStmt(ThenN) or ((not AQ.Lower) and IsGrowOf(ThenN, AQ.Arr))) then
    begin
      Evs:= EventsIn(AX, ThenN);
      if Length(Evs) = 0 then Exit;
      Last:= LastStatement(ThenN);
      Inc(FSideWrites);
      try
        { the branch's one write, or a leave guard the branch ends in (XCONST:770) }
        if (Length(Evs) = 1) and RunsInBlock(Evs[0], ThenN) then
        begin
          if not EventSide(Evs[0], AX, AQ, AOff, ADepth + 1) then Exit;
        end
        else if Last.IsNull or (Last.NodeType <> 'if') or (not IsLeaveStmt(Last.ChildByField('then')))
          or not FactSide(Last.ChildByField('condition'), AX, True, AQ, AOff, ADepth + 1) then Exit;
      finally
        Dec(FSideWrites);
      end;
    end;
    Exit(GuardHolds(S.ChildByField('condition'), True, S.EndByte, AX, AAt, AQ, AOff, ADepth));
  end;
  if ((S.NodeType = 'repeat') or (S.NodeType = 'while')) and not TRegEx.IsMatch(Txt(S), '(?i)\b(break|goto)\b') then
    Result:= GuardHolds(S.ChildByField('condition'), S.NodeType = 'while', S.EndByte, AX, AAt, AQ, AOff, ADepth);
end;

{ N is AThen, or a statement of AThen's own list (it runs whenever AThen does). }
function TBnRun.RunsInBlock(const N, AThen: TTSNode): Boolean;
var
  P: TTSNode;
begin
  P:= N;
  while (not P.IsNull) and not (P = AThen) do
  begin
    if IndexStr(P.NodeType, CONTROL_NODES) >= 0 then Exit(False);
    P:= P.Parent;
  end;
  Result:= not P.IsNull;
end;

{ A guard that dominates AAt proves AX + AOff there. }
function TBnRun.GuardSide(const AX: string; const AAt: TTSNode; const AQ: TSideQ; AOff, ADepth: Integer): Boolean;
var
  C, P, S, Cond: TTSNode;
  T, Op: string;
  ElseAt: Cardinal;
  I: Integer;
begin
  Result:= False;
  C:= AAt;
  P:= C.Parent;
  while (not P.IsNull) and (P.NodeType <> 'defProc') and (P.NodeType <> 'lambda') do
  begin
    T:= P.NodeType;
    Cond:= P.ChildByField('condition');
    if (T = 'if') or (T = 'ifElse') then
    begin
      if P.ChildByField('then') = C then Result:= GuardHolds(Cond, False, Cond.EndByte, AX, AAt, AQ, AOff, ADepth)
      else if P.ChildByField('else') = C then Result:= GuardHolds(Cond, True, Cond.EndByte, AX, AAt, AQ, AOff, ADepth);
    end
    else if (T = 'exprIf') and not (Cond = C) then  // dl:ok nonminimal-bool -- TTSNode declares Equal but no NotEqual; <> does not compile
    begin
      ElseAt:= P.EndByte;
      for I:= 0 to P.ChildCount - 1 do
        if P.Child(I).NodeType = 'kElse' then ElseAt:= P.Child(I).StartByte;
      Result:= GuardHolds(Cond, C.StartByte > ElseAt, Cond.EndByte, AX, AAt, AQ, AOff, ADepth);
    end
    else if T = 'exprBinary' then
    begin
      Op:= OperatorType(P);
      if (P.ChildByField('rhs') = C) and ((Op = 'kAnd') or (Op = 'kOr')) then
        Result:= GuardHolds(P.ChildByField('lhs'), Op = 'kOr', P.ChildByField('lhs').EndByte, AX, AAt, AQ, AOff, ADepth);
    end
    else if T = 'while' then
    begin
      if P.ChildByField('body') = C then Result:= GuardHolds(Cond, False, Cond.EndByte, AX, AAt, AQ, AOff, ADepth);
    end
    else if (T = 'block') or (T = 'statements') then
    begin
      S:= C.PrevSibling;
      while (not S.IsNull) and not Result do
      begin
        Result:= SiblingSide(S, AX, AAt, AQ, AOff, ADepth);
        S:= S.PrevSibling;
      end;
    end;
    if Result then Exit;
    C:= P;
    P:= C.Parent;
  end;
end;

{ N is evaluated on every path that reaches AAt after it: no branch, short-circuit right side, case or
  try around N lies between N and the point. }
function TBnRun.RunsBefore(const N, AAt: TTSNode): Boolean;
var
  C, P: TTSNode;
  T, Op: string;
  Last, IsCond, OnlyIfTrue: Boolean;
begin
  Result:= False;
  if N.EndByte > AAt.StartByte then Exit;
  OnlyIfTrue:= False;
  C:= N;
  repeat
    P:= C.Parent;
    if P.IsNull then Exit;
    T:= P.NodeType;
    if (T = 'defProc') or (T = 'lambda') or (T = 'caseCase') or (T = 'exceptionHandler') or (T = 'try') or (T = 'case') then Exit;
    Last:= NodeWithin(AAt, P);
    IsCond:= P.ChildByField('condition') = C;
    if MatchStr(T, ['if', 'ifElse', 'while', 'exprIf']) and not IsCond then Exit;
    { the right side of `G and ..` ran when the whole condition held: inside the branch it guards }
    if OnlyIfTrue then
    begin
      if MatchStr(T, ['if', 'ifElse']) then Exit(NodeWithin(AAt, P.ChildByField('then')));
      if T = 'while' then Exit(NodeWithin(AAt, P.ChildByField('body')));
      if (T <> 'exprParens') and ((T <> 'exprBinary') or (OperatorType(P) <> 'kAnd')) then Exit;
    end;
    if ((T = 'for') or (T = 'foreach')) and (P.ChildByField('body') = C) then Exit;
    Op:= if T = 'exprBinary' then OperatorType(P) else '';
    if (Op = 'kOr') and (P.ChildByField('rhs') = C) then Exit;
    if (Op = 'kAnd') and (P.ChildByField('rhs') = C) then
    begin
      { a point in the same condition, after N, is reached only through N too }
      if Last then Exit(True);
      OnlyIfTrue:= True;
    end;
    C:= P;
  until Last;
  Result:= True;
end;

{ A comparison of AX that condition C (ANegate: its failure) makes hold, as 'op|other side' (AX on the left). }
procedure TBnRun.NameFacts(const C: TTSNode; const AX: string; ANegate: Boolean; AFacts: TList<string>);
var
  E, Other: TTSNode;
  Op: string;
begin
  E:= Peeled(C);
  if E.IsNull then Exit;
  if (E.NodeType = 'exprUnary') and (OperatorType(E) = 'kNot') then NameFacts(E.ChildByField('operand'), AX, not ANegate, AFacts)
  else if E.NodeType = 'exprBinary' then
  begin
    Op:= OperatorType(E);
    if ((Op = 'kAnd') and not ANegate) or ((Op = 'kOr') and ANegate) then
    begin
      NameFacts(E.ChildByField('lhs'), AX, ANegate, AFacts);
      NameFacts(E.ChildByField('rhs'), AX, ANegate, AFacts);
      Exit;
    end;
    if BareIdent(E.ChildByField('lhs')) = AX then Other:= E.ChildByField('rhs')
    else if BareIdent(E.ChildByField('rhs')) = AX then
    begin
      Other:= E.ChildByField('lhs');
      Op:= MirrorOp(Op);
    end
    else Exit;
    if ANegate then Op:= NegateOp(Op);
    AFacts.Add(Op + '|' + TightText(Txt(Other)));
  end;
end;

{ A name ATxt mentions is written between AFrom and AAt (or in a loop around AAt that starts after AFrom);
  a name that is no local counts as unchanged unless the routine assigns it. }
function TBnRun.NamesChange(const ATxt: string; AFrom: Cardinal; const AAt: TTSNode): Boolean;
var
  M: TMatch;
  W, L: TTSNode;
  Loops: TList<TTSNode>;
begin
  Result:= False;
  Loops:= TList<TTSNode>.Create;
  try
    LoopsAround(AAt, Loops);
    for M in TRegEx.Matches(ATxt, '[a-z_]\w*') do
    begin
      for W in EventsOf(M.Value) do
      begin
        if (W.StartByte > AFrom) and (W.StartByte < AAt.StartByte) then Exit(True);
        for L in Loops do
          if (L.StartByte > AFrom) and NodeWithin(W, L) then Exit(True);
      end;
      if SizeChangedIn(M.Value, AFrom, AAt.StartByte) then Exit(True);
    end;
  finally
    Loops.Free;
  end;
end;

{ The comparisons of AX that the conditions around AAt and the leave guards before it make hold there. }
procedure TBnRun.FactsAt(const AX: string; const AAt: TTSNode; AFacts: TList<string>);
var
  C, P, S, Cond: TTSNode;
  T, Op: string;

  { condition ACond still holds at AAt: nothing wrote AX since }
  procedure Take(const ACond: TTSNode; ANegate: Boolean; AFrom: Cardinal);
  begin
    if SideKept(AX, AFrom, AAt, True) and SideKept(AX, AFrom, AAt, False) then NameFacts(ACond, AX, ANegate, AFacts);
  end;

begin
  C:= AAt;
  P:= C.Parent;
  while (not P.IsNull) and (P.NodeType <> 'defProc') and (P.NodeType <> 'lambda') do
  begin
    T:= P.NodeType;
    Cond:= P.ChildByField('condition');
    if ((T = 'if') or (T = 'ifElse')) and (P.ChildByField('then') = C) then Take(Cond, False, Cond.EndByte)
    else if (T = 'ifElse') and (P.ChildByField('else') = C) then Take(Cond, True, Cond.EndByte)
    else if (T = 'while') and (P.ChildByField('body') = C) then Take(Cond, False, Cond.EndByte)
    else if T = 'exprBinary' then
    begin
      Op:= OperatorType(P);
      if (P.ChildByField('rhs') = C) and ((Op = 'kAnd') or (Op = 'kOr')) then
        Take(P.ChildByField('lhs'), Op = 'kOr', P.ChildByField('lhs').EndByte);
    end
    else if (T = 'block') or (T = 'statements') then
    begin
      S:= C.PrevSibling;
      while not S.IsNull do
      begin
        if (S.NodeType = 'if') and IsLeaveStmt(S.ChildByField('then')) then Take(S.ChildByField('condition'), True, S.EndByte);
        S:= S.PrevSibling;
      end;
    end;
    C:= P;
    P:= C.Parent;
  end;
end;

{ An earlier access S of the same element in the right side of `G and ..`, G one comparison of AX that
  bounds it on the OTHER side (`while (P >= 0) and (A[P] ..) do Dec(P)`), which also holds at AAt: AX only
  moved away from the side asked for since, so G held for S too and S was evaluated (one finding for one
  start value). }
function TBnRun.GuardedBefore(const S: TTSNode; const AX: string; const AAt: TTSNode; ALower: Boolean): Boolean;
var
  C, P, Top: TTSNode;
  Want, Here: TList<string>;
  Op: string;
begin
  Result:= False;
  if S.EndByte > AAt.StartByte then Exit;
  Want:= TList<string>.Create;
  Here:= TList<string>.Create;
  try
    { the conjuncts S stands behind, up to the condition of its statement }
    Top:= Default(TTSNode);
    C:= S;
    P:= C.Parent;
    while not P.IsNull and (IndexStr(P.NodeType, ['exprBinary', 'exprParens', 'exprUnary', 'exprCall', 'exprArgs', 'exprDot', 'exprSubscript']) >= 0) do
    begin
      if (P.NodeType = 'exprBinary') and (P.ChildByField('rhs') = C) then
      begin
        Op:= OperatorType(P);
        if Op = 'kOr' then Exit;
        if Op = 'kAnd' then
        begin
          NameFacts(P.ChildByField('lhs'), AX, False, Want);
          if Want.Count <> 1 then Exit;
          Top:= P;
        end;
      end;
      C:= P;
      P:= C.Parent;
    end;
    if Top.IsNull or (Want.Count <> 1) or not RunsBefore(C, AAt) then Exit;
    if Peeled(Top.ChildByField('lhs')).NodeType <> 'exprBinary' then Exit;
    Op:= OperatorType(Peeled(Top.ChildByField('lhs')));
    if (Op = 'kAnd') or (Op = 'kOr') then Exit;
    Op:= Copy(Want[0], 1, Pos('|', Want[0]) - 1);
    if ALower and (Op <> 'kLt') and (Op <> 'kLte') then Exit;
    if (not ALower) and (Op <> 'kGt') and (Op <> 'kGte') then Exit;
    if not SideKept(AX, S.EndByte, AAt, ALower) then Exit;
    { the other side of the guard must read the same at both points }
    if NamesChange(Copy(Want[0], Pos('|', Want[0]) + 1, MaxInt), S.EndByte, AAt) then Exit;
    FactsAt(AX, AAt, Here);
    Result:= Here.IndexOf(Want[0]) >= 0;
  finally
    Here.Free;
    Want.Free;
  end;
end;

{ The same element was read or written before AAt on every path to it, and nothing since moved the
  index off that side or shortened the array: an index out of range failed there, and that access has
  its own finding. }
function TBnRun.PriorSide(const AX: string; const AAt: TTSNode; const AQ: TSideQ; AOff: Integer): Boolean;
var
  S, Args: TTSNode;
begin
  Result:= False;
  if (AQ.Lower and (AOff < 0)) or ((not AQ.Lower) and (AOff > 0)) then Exit;
  for S in AccessesOf(AQ.Arr) do
  begin
    if S.StartByte >= AAt.StartByte then Break;
    Args:= S.ChildByField('args');
    if Args.IsNull or (Args.NamedChildCount <> 1) or (BareIdent(Args.NamedChild(0)) <> AX) then Continue;
    if ((RunsBefore(S, AAt) and SideKept(AX, S.EndByte, AAt, AQ.Lower)) or GuardedBefore(S, AX, AAt, AQ.Lower))
      and not ShrunkIn(AQ.Arr, S.EndByte, AAt.StartByte) and CheckedAccess(S, AX, AQ) then Exit(True);
  end;
end;

{ The rule checks the access S of AX itself: no v1 cut (an index a nested routine or a lambda names, a
  routine with `with` / goto, a for loop with other bounds, case AX of, repeat .. until on AX, Assert). }
function TBnRun.CheckedAccess(const S: TTSNode; const AX: string; const AQ: TSideQ): Boolean;
var
  Ctx: TIdxCtx;
  Writes: TList<TTSNode>;
  OldAccess: TTSNode;
begin
  Result:= False;
  if NamedElsewhere(FCurProc, AX) or TRegEx.IsMatch(Txt(FCurProc.ChildByField('body')), '(?i)\b(with|goto)\b') then Exit;
  Ctx:= Default(TIdxCtx);
  Ctx.Access:= S;
  Ctx.Idx:= AX;
  Ctx.Arr:= AQ.Arr;
  Ctx.Info:= AQ.Info;
  OldAccess:= FAccess;
  FAccess:= S;
  Writes:= TList<TTSNode>.Create;
  try
    CollectIdxWrites(FCurProc.ChildByField('body'), AX, Writes);
    Ctx.Writes:= Writes;
    ClimbGuards(Ctx);
    Result:= not Ctx.Silent;
  finally
    Writes.Free;
    FAccess:= OldAccess;
  end;
end;

{ `AX := Length(A)` followed in its statement list by an append to A or `SetLength(A, AX + 1)`: the
  appended element. }
function TBnRun.GrownAfter(const W: TTSNode; const AX: string; const AQ: TSideQ): Boolean;
const
  NEAR_STATEMENTS = 3;
var
  S: TTSNode;
  I: Integer;
  T: string;
begin
  Result:= False;
  if AQ.Lower or not IsArrayFn(W.ChildByField('rhs'), FN_LENGTH, AQ.Arr) then Exit;
  S:= ListStatement(W);
  for I:= 1 to NEAR_STATEMENTS do
  begin
    if S.IsNull then Exit;
    S:= S.NextNamedSibling;
    while (not S.IsNull) and IsTrivia(S) do S:= S.NextNamedSibling;
    if S.IsNull then Exit;
    T:= TightText(Txt(S));
    if StartsStr('setlength(' + AQ.Arr + ',' + AX + '+', T) or StartsStr('setlength(' + AQ.Arr + ',length(' + AQ.Arr + ')+', T)
      or StartsStr(AQ.Arr + ':=' + AQ.Arr + '+', T) then Exit(True);
  end;
end;

{ `AX := F(.., SizeOf(A) - k, ..)` (a byte array) or `.. Length(A) - k ..`: a read that returns at most
  the size it is given. Result k (-MaxInt: no such read): AX is at most Length(A) - k. }
function TBnRun.ReadCap(const ARhs: TTSNode; const AQ: TSideQ): Integer;
var
  Args: TTSNode;
  I: Integer;
  A: string;
  M: TMatch;
begin
  Result:= -MaxInt;
  if AQ.Lower or ARhs.IsNull or (ARhs.NodeType <> 'exprCall') then Exit;
  Args:= ARhs.ChildByField('args');
  if Args.IsNull or (Args.NamedChildCount < 2) then Exit;
  A:= TRegEx.Escape(AQ.Arr);
  for I:= 0 to Args.NamedChildCount - 1 do
  begin
    M:= TRegEx.Match(TightText(Txt(Args.NamedChild(I))), '^(length|sizeof)\(' + A + '\)(?:-(\d{1,9}))?$');
    if M.Success and ((M.Groups[1].Value = FN_LENGTH)
      or TRegEx.IsMatch(Txt(FCurProc), '(?i)\b' + A + '\s*:\s*array\s*\[[^\]]*\]\s*of\s+(byte|ansichar|uint8)\b')) then
      Exit(if M.Groups.Count > 2 then StrToIntDef(M.Groups[2].Value, 0) else 0);
  end;
end;

{ W is `AX := E` alone in `if E < AX then` (a minimum: never raises AX) -- or, ALower, in
  `if E > AX then` (a maximum: never lowers it). }
function TBnRun.ClampOf(const W: TTSNode; const AX: string; ALower: Boolean): Boolean;
var
  P, C: TTSNode;
  E, Op: string;
begin
  Result:= False;
  P:= W.Parent;
  while (not P.IsNull) and (P.NodeType <> 'if') and (IndexStr(P.NodeType, CONTROL_NODES) < 0) do P:= P.Parent;
  if P.IsNull or (P.NodeType <> 'if') then Exit;
  C:= Peeled(P.ChildByField('condition'));
  if C.IsNull or (C.NodeType <> 'exprBinary') or not RunsInBlock(W, P.ChildByField('then')) then Exit;
  E:= TightText(Txt(W.ChildByField('rhs')));
  Op:= OperatorType(C);
  if (BareIdent(C.ChildByField('lhs')) = AX) and (TightText(Txt(C.ChildByField('rhs'))) = E) then Op:= MirrorOp(Op)
  else if (BareIdent(C.ChildByField('rhs')) <> AX) or (TightText(Txt(C.ChildByField('lhs'))) <> E) then Exit;
  Result:= if ALower then (Op = 'kGt') or (Op = 'kGte') else (Op = 'kLt') or (Op = 'kLte');
end;

{ `AX := High(B)` / `Length(B) - 1` right after an append to B: at least 0. }
function TBnRun.LastOfAppended(const W: TTSNode; const AQ: TSideQ): Boolean;
const
  NEAR_STATEMENTS = 3;
var
  S: TTSNode;
  M: TMatch;
  I: Integer;
  B, T: string;
begin
  Result:= False;
  if (not AQ.Lower) or ((AQ.Info.Kind = dkArray) and (AQ.Info.Lo > 0)) then Exit;
  M:= TRegEx.Match(TightText(Txt(W.ChildByField('rhs'))), '^(?:high\((\w+)\)|length\((\w+)\)-1)$');
  if not M.Success then Exit;
  B:= M.Groups[1].Value;
  if B = '' then B:= M.Groups[2].Value;
  S:= ListStatement(W);
  for I:= 1 to NEAR_STATEMENTS do
  begin
    if S.IsNull then Exit;
    S:= S.PrevNamedSibling;
    while (not S.IsNull) and IsTrivia(S) do S:= S.PrevNamedSibling;
    if S.IsNull then Exit;
    T:= TightText(Txt(S));
    if StartsStr('setlength(' + B + ',length(' + B + ')+', T) or StartsStr(B + ':=' + B + '+[', T) then Exit(True);
  end;
end;
{ Write W leaves AX + AOff on the side AQ asks for. }
function TBnRun.EventSide(const W: TTSNode; const AX: string; const AQ: TSideQ; AOff, ADepth: Integer): Boolean;
var
  Args, Rhs, S: TTSNode;
  K: Integer;
  IsInc: Boolean;
begin
  Result:= False;
  if W.NodeType = 'exprCall' then
  begin
    IsInc:= BareIdent(W.ChildByField('entity')) = 'inc';
    Args:= W.ChildByField('args');
    if (not IsInc) and (BareIdent(W.ChildByField('entity')) <> 'dec') then
    begin
      { 1.53 SLZ-IDXFP (Doc.Document:745): a local routine's out / var argument }
      if Args.IsNull then Exit;
      for K:= 0 to Args.NamedChildCount - 1 do
        if (BareIdent(Args.NamedChild(K)) = AX) and not CalleeSide(W, AQ, AOff, ADepth + 1, K) then Exit;
      Exit(True);
    end;
    K:= 1;
    if (Args.NamedChildCount >= 2) and not EvalIndex(Args.NamedChild(1), K) then
    begin
      if (IsInc <> AQ.Lower) or not NonNegOf(Args.NamedChild(1)) then Exit;
      K:= 0;
    end;
    Exit(IdentSide(AX, Args.NamedChild(0), AQ, if IsInc then AOff + K else AOff - K, ADepth + 1));
  end;
  if W.NodeType = 'foreach' then
    Exit(ElementSide(BareIdent(W.ChildByField('iterable')), AQ, AOff, ADepth + 1));
  if W.NodeType <> 'assignment' then Exit;
  Rhs:= W.ChildByField('rhs');
  if SideOf(Rhs, AQ, AOff, ADepth + 1) then Exit(True);
  if ClampOf(W, AX, AQ.Lower) and IdentSide(AX, W, AQ, AOff, ADepth + 1) then Exit(True);
  if ((AOff = 0) and GrownAfter(W, AX, AQ)) or (AOff < ReadCap(Peeled(Rhs), AQ)) or ((AOff >= 0) and LastOfAppended(W, AQ)) then Exit(True);
  { a guard right after it: `x := f(..); if x < 0 then Exit` }
  S:= ListStatement(W);
  if S.IsNull or not RunsInBlock(W, S) then Exit;
  S:= S.NextNamedSibling;
  while (not S.IsNull) and IsTrivia(S) do S:= S.NextNamedSibling;
  Result:= (not S.IsNull) and (S.NodeType = 'if') and IsLeaveStmt(S.ChildByField('then'))
    and FactSide(S.ChildByField('condition'), AX, True, AQ, AOff, ADepth + 1);
end;

{ Between write W and AAt the only size change of the array that may shorten it is `SetLength(A, Length(B))`,
  and W's value lies within B too (Convert.Apply:2382). }
function TBnRun.ResizedSide(const W, AAt: TTSNode; const AQ: TSideQ; AOff, ADepth: Integer): Boolean;
var
  N, One: TTSNode;
  M: TMatch;
  Q2: TSideQ;
begin
  Result:= False;
  One:= Default(TTSNode);
  for N in SizeEvents(AQ.Arr, FCurProc.ChildByField('body')) do
    if (N.StartByte >= W.EndByte) and (N.StartByte < AAt.StartByte) and not GrowsOnly(N, AQ.Arr) then
    begin
      if not One.IsNull then Exit;
      One:= N;
    end;
  if One.IsNull then Exit;
  M:= TRegEx.Match(TRegEx.Replace(TightText(Txt(One)), ';$', ''), '^setlength\(\w+,length\((\w+)\)\)$');
  if not M.Success then Exit;
  Q2:= AQ;
  Q2.Arr:= M.Groups[1].Value;
  Result:= IsBoundedArray(Q2.Arr, Q2.Info) and not ShrunkIn(Q2.Arr, W.EndByte, AAt.StartByte)
    and SideOf(W.ChildByField('rhs'), Q2, AOff, ADepth + 1);
end;

{ Every write of AX that reaches AAt leaves AX + AOff on the side AQ asks for (a parameter: also
  every caller's argument). }
function TBnRun.WritesSide(const AX: string; const AAt: TTSNode; const AQ: TSideQ; AOff, ADepth: Integer): Boolean;
var
  W, D, L, Common: TTSNode;
  Loops: TList<TTSNode>;
  Any, Reaches, Sets: Boolean;
begin
  Result:= False;
  D:= Default(TTSNode);
  for W in EventsOf(AX) do
  begin
    { a for-in loop around AAt gives AX its value on every trip }
    if W.NodeType = 'foreach' then Sets:= NodeWithin(AAt, W.ChildByField('body'))
    else Sets:= (W.NodeType <> 'for') and StmtDominates(W, AAt);
    if Sets and (D.IsNull or (W.StartByte > D.StartByte)) then D:= W;
  end;
  Any:= False;
  Loops:= TList<TTSNode>.Create;
  try
    LoopsAround(AAt, Loops);
    for W in EventsOf(AX) do
    begin
      Common:= Default(TTSNode);
      for L in Loops do
        if Common.IsNull and NodeWithin(W, L) then Common:= L;
      { a write in a loop around AAt reaches it unless the dominating write of that loop comes after it }
      if Common.IsNull then
        Reaches:= (W.EndByte <= AAt.StartByte) and (D.IsNull or (W.StartByte >= D.StartByte))
          and not LeavesBefore(W, AAt, 0, False) and not ExclusiveBranches(W, AAt)
      else
        Reaches:= (Common = W) or D.IsNull or (D = W) or not NodeWithin(D, Common)
          or ((D.StartByte < W.StartByte) and (W.StartByte < AAt.StartByte));
      if not Reaches then Continue;
      if (not AQ.Lower) and (W.NodeType = 'assignment') and (W.EndByte <= AAt.StartByte) and ShrunkIn(AQ.Arr, W.EndByte, AAt.StartByte)
        and not ResizedSide(W, AAt, AQ, AOff, ADepth) then Exit;
      Any:= True;
      Inc(FSideWrites);
      try
        if not EventSide(W, AX, AQ, AOff, ADepth + 1) then Exit;
      finally
        Dec(FSideWrites);
      end;
    end;
  finally
    Loops.Free;
  end;
  if D.IsNull and IsOwnLocal(AX) and FScopes[FScopes.Count - 1][AX].IsParam then Exit(CallersSide(AX, AQ, AOff, ADepth + 1));
  Result:= Any;
end;

{ AX is a local / parameter of the current routine, or its Result. }
function TBnRun.SideLocal(const AX: string): Boolean;
begin
  Result:= IsOwnLocal(AX) or ((AX = WORD_RESULT) and not FCurProc.ChildByField('header').ChildByField('type').IsNull);
end;

{ AKey is being proven already; AHolds: what that says about AOff now. }
function TBnRun.SideRevisited(const AKey: string; const AQ: TSideQ; AOff: Integer; out AHolds: Boolean): Boolean;
var
  M: TSideMark;
begin
  AHolds:= False;
  Result:= FSideVisit.TryGetValue(AKey, M);
  if Result then AHolds:= (FSideWrites > M.Steps) and (if AQ.Lower then AOff >= M.Off else AOff <= M.Off);
end;

{ Marks AKey as being proven for AOff. }
procedure TBnRun.SideEnter(const AKey: string; AOff, ASteps: Integer);
var
  M: TSideMark;
begin
  M.Off:= AOff;
  M.Steps:= ASteps;
  FSideVisit.Add(AKey, M);
end;

{ The local AX, read at AAt, plus AOff is on the side AQ asks for. }
function TBnRun.IdentSide(const AX: string; const AAt: TTSNode; const AQ: TSideQ; AOff, ADepth: Integer): Boolean;
var
  Key: string;
  F: TTSNode;
begin
  Result:= False;
  Dec(FSideBudget);
  if (FSideBudget < 0) or (ADepth > MAX_SIDE_DEPTH) or not SideLocal(AX) then Exit;
  Key:= Format('%d|%s|%d|%s|%s', [FCurProc.StartByte, AX, AAt.StartByte, BoolToStr(AQ.Lower), AQ.Arr]);
  if SideRevisited(Key, AQ, AOff, Result) then Exit;
  if NameEscapes(FCurProc, AX, False) then Exit(False);
  SideEnter(Key, AOff, FSideWrites);
  try
    if AQ.Lower and NonNegOf(AAt) and ConstSide(AOff, AQ) then Exit(True);
    if GuardSide(AX, AAt, AQ, AOff, ADepth) or PriorSide(AX, AAt, AQ, AOff) then Exit(True);
    F:= ForOfCounter(AX, AAt);
    if F.IsNull then Exit(WritesSide(AX, AAt, AQ, AOff, ADepth));
    { the counter: its loop's start (the lower side, upwards) or end }
    Result:= SideOf(if AQ.Lower <> IsDownFor(F) then F.ChildByField('start').ChildByField('rhs') else F.ChildByField('end'), AQ, AOff, ADepth + 1);
  finally
    FSideVisit.Remove(Key);
  end;
end;

{ Every element the routine puts into its own local list / array AColl, plus AOff, is on the side AQ
  asks for. False when anything but the known reads touches AColl. }
function TBnRun.ElementSide(const AColl: string; const AQ: TSideQ; AOff, ADepth: Integer): Boolean;
const
  READS: array[0..17] of string = ('count', 'clear', 'free', 'sort', 'delete', 'remove', 'contains', 'indexof', 'toarray',
    'last', 'first', 'capacity', 'reverse', 'trimexcess', 'pop', 'peek', 'dequeue', 'extract');
  ADDS : array[0..2] of string = ('add', 'push', 'enqueue');
var
  Key: string;
  Stores: Integer;

  { the elements of `[a, b]` }
  function AllOf(const ABr: TTSNode): Boolean;
  var
    J: Integer;
    El: TTSNode;
  begin
    Result:= True;
    for J:= 0 to ABr.NamedChildCount - 1 do
    begin
      El:= ABr.NamedChild(J);
      if IsTrivia(El) then Continue;
      Inc(Stores);
      if (El.NodeType = 'range') or not SideOf(El, AQ, AOff, ADepth + 1) then Exit(False);
    end;
  end;

  { AColl := ARhs }
  function StoreOk(const ARhs: TTSNode): Boolean;
  var
    N, R: TTSNode;
    T: string;
  begin
    N:= Peeled(ARhs);
    if N.IsNull then Exit(False);
    T:= TightText(Txt(N));
    if (T = KEY_NIL) or (T = '[]') or TRegEx.IsMatch(T, '^t\w+(<[\w.,<>]+>)?\.create(\(\))?$') then Exit(True);
    if N.NodeType = 'exprBrackets' then Exit(AllOf(N));
    if (N.NodeType = 'exprBinary') and (OperatorType(N) = 'kAdd') and (BareIdent(N.ChildByField('lhs')) = AColl) then
    begin
      R:= Peeled(N.ChildByField('rhs'));
      Exit((R.NodeType = 'exprBrackets') and AllOf(R));
    end;
    Result:= (N.NodeType = 'exprDot') and SameText(Trim(Txt(N.ChildByField('rhs'))), 'toarray');
    if not Result then Exit;
    Inc(Stores);
    Result:= ElementSide(BareIdent(N.ChildByField('lhs')), AQ, AOff, ADepth + 1);
  end;

  { one mention of AColl }
  function UseOk(const AId: TTSNode): Boolean;
  var
    P, G, Args: TTSNode;
    T, Mem: string;
  begin
    P:= AId.Parent;
    G:= P.Parent;
    T:= P.NodeType;
    if T = 'exprSubscript' then
    begin
      if not (P.ChildByField('entity') = AId) then Exit(True);  // dl:ok nonminimal-bool -- TTSNode declares Equal but no NotEqual; <> does not compile
      if (G.NodeType = 'assignment') and (G.ChildByField('lhs') = P) then
      begin
        Inc(Stores);
        Exit(SideOf(G.ChildByField('rhs'), AQ, AOff, ADepth + 1));
      end;
      Exit((G.NodeType <> 'exprArgs') or not MatchStr(CallName(G.Parent), ['inc', 'dec']));
    end;
    if T = 'exprDot' then
    begin
      if not (P.ChildByField('lhs') = AId) then Exit(True);  // dl:ok nonminimal-bool -- TTSNode declares Equal but no NotEqual; <> does not compile
      Mem:= LowerCase(Trim(Txt(P.ChildByField('rhs'))));
      if MatchStr(Mem, READS) then Exit(True);
      if (not MatchStr(Mem, ADDS)) or (G.NodeType <> 'exprCall') then Exit(False);
      Args:= G.ChildByField('args');
      Inc(Stores);
      Exit((not Args.IsNull) and (Args.NamedChildCount = 1) and SideOf(Args.NamedChild(0), AQ, AOff, ADepth + 1));
    end;
    if T = 'assignment' then Exit((P.ChildByField('rhs') = AId) or StoreOk(P.ChildByField('rhs')));
    if T = 'varAssignDef' then Exit((G.NodeType = 'assignment') and StoreOk(G.ChildByField('rhs')));
    if T = 'exprArgs' then
      Exit(MatchStr(TRegEx.Replace(CallName(G), '<.*$', ''), [FN_LENGTH, FN_HIGH, 'low', FN_SETLENGTH, 'freeandnil', 'sort', 'exit']));
    Result:= MatchStr(T, ['exprBinary', 'foreach', 'varDef', 'exprParens']);
  end;

  function Walk(const N: TTSNode): Boolean;
  var
    J: Integer;
  begin
    Result:= True;
    if N.IsNull then Exit;
    if (N.NodeType = 'lambda') or (N.NodeType = 'defProc') then Exit(not Mentions(N, AColl));
    if (N.NodeType = 'identifier') and SameText(Txt(N), AColl) then Exit(UseOk(N));
    for J:= 0 to N.ChildCount - 1 do
      if not Walk(N.Child(J)) then Exit(False);
  end;

begin
  Result:= False;
  Dec(FSideBudget);
  if (AColl = '') or (FSideBudget < 0) or (ADepth > MAX_SIDE_DEPTH) or not IsOwnLocal(AColl) then Exit;
  if FScopes[FScopes.Count - 1][AColl].IsParam then Exit;
  Key:= Format('%d|el|%s|%s|%s', [FCurProc.StartByte, AColl, BoolToStr(AQ.Lower), AQ.Arr]);
  Inc(FSideWrites);  { an element is always read after a store }
  try
    if SideRevisited(Key, AQ, AOff, Result) then Exit;
    SideEnter(Key, AOff, FSideWrites - 1);
    try
      Stores:= 0;
      Result:= Walk(FCurProc.ChildByField('body')) and (Stores > 0);
    finally
      FSideVisit.Remove(Key);
    end;
  finally
    Dec(FSideWrites);
  end;
end;

{ The calls of AProc when the file sees all of them: LocalCalls, or a method of this file's own class
  that is private there (or whose class sits in the implementation section), not virtual, declared
  and defined once, and named only in plain calls. }
function TBnRun.SeenCalls(const AProc: TTSNode; out ASites: TList<TTSNode>): Boolean;
var
  Nm: string;
  Ids, Cnt: Integer;
begin
  if LocalCalls(AProc, ASites) then Exit(True);
  Nm:= LowerCase(Trim(Txt(AProc.ChildByField('header').ChildByField('name'))));
  if not ContainsStr(Nm, '.') then Exit(False);
  Nm:= Copy(Nm, LastDelimiter('.', Nm) + 1, MaxInt);
  { the two mentions that are no call: the class's declaration and the body's header }
  Result:= FDefCount.TryGetValue(Nm, Cnt) and (Cnt = 1) and FPrivDecls.TryGetValue(Nm, Cnt) and (Cnt = 1)
    and FCallSites.TryGetValue(Nm, ASites) and FIdentCnt.TryGetValue(Nm, Ids) and (Ids = ASites.Count + 2);
end;

{ The routine that declares the local array AArr as AFrom's scope sees it; null for a field / global. }
function TBnRun.ArrayOwner(const AFrom: TTSNode; const AArr: string): TTSNode;
begin
  Result:= AFrom;
  while not Result.IsNull do
  begin
    if (Result.NodeType = 'defProc') and DeclaresLocal(Result, AArr) then Exit;
    Result:= Result.Parent;
  end;
end;

{ The class of the outermost method around N ('' for a plain routine), lower-cased. }
function TBnRun.OuterClass(const N: TTSNode): string;
var
  P: TTSNode;
begin
  Result:= '';
  P:= N;
  while not P.IsNull do
  begin
    if P.NodeType = 'defProc' then Result:= LowerCase(Trim(Txt(P.ChildByField('header').ChildByField('name'))));
    P:= P.Parent;
  end;
  Result:= Copy(Result, 1, LastDelimiter('.', Result) - 1);
end;

{ AProc's AArr and AOther's AArr (one calls the other) are the same array: a field of one class, a
  global, or the same enclosing routine's local. }
function TBnRun.SameOuterArray(const AProc, AOther: TTSNode; const AArr: string): Boolean;
var
  Owner: TTSNode;
begin
  Owner:= ArrayOwner(AProc, AArr);
  if Owner.IsNull then Exit(ArrayOwner(AOther, AArr).IsNull and SameText(OuterClass(AProc), OuterClass(AOther)));
  Result:= ArrayOwner(AOther, AArr) = Owner;
end;

{ Every caller of the current routine passes an argument for its parameter AX that, plus AOff, is on
  the side AQ asks for. }
function TBnRun.CallersSide(const AX: string; const AQ: TSideQ; AOff, ADepth: Integer): Boolean;
var
  Sites: TList<TTSNode>;
  Site, Args, Caller, Proc, OldAccess, RetT: TTSNode;
  Names: TArray<string>;
  PX, PArr: Integer;
  Q2: TSideQ;
  Saved: TBnSaved;
  Key: string;
begin
  Result:= False;
  if not SeenCalls(FCurProc, Sites) then Exit;
  Proc:= FCurProc;
  Names:= ParamNames(Proc);
  PX:= IndexStr(AX, Names);
  PArr:= IndexStr(AQ.Arr, Names);
  if (PX < 0) or ((PArr < 0) and DeclaresLocal(Proc, AQ.Arr)) then Exit;
  Key:= Format('%d|cs|%s|%s|%s', [Proc.StartByte, AX, BoolToStr(AQ.Lower), AQ.Arr]);
  Inc(FSideWrites);  { passing an argument is a write of the parameter }
  Inc(FSideRoutines);
  try
    if SideRevisited(Key, AQ, AOff, Result) or (FSideRoutines > MAX_SIDE_CALLERS) then Exit;
    SideEnter(Key, AOff, FSideWrites - 1);
    try
      for Site in Sites do
      begin
        Args:= Site.ChildByField('args');
        Caller:= EnclosingProc(Site);
        if Args.IsNull or Caller.IsNull or (PX >= Args.NamedChildCount) or (PArr >= Args.NamedChildCount) then Exit;
        Q2:= AQ;
        if PArr >= 0 then Q2.Arr:= BareIdent(Args.NamedChild(PArr))
        else if not SameOuterArray(Proc, Caller, AQ.Arr) then Exit;
        if Q2.Arr = '' then Exit;
        OldAccess:= FAccess;
        EnterRoutine(Caller, Saved);
        FAccess:= Site;
        try
          if PArr >= 0 then
          begin
            { the caller's own Result of a dynamic-array type, or an array it sees }
            RetT:= Caller.ChildByField('header').ChildByField('type');
            Q2.Info:= Default(TDeclInfo);
            if (Q2.Arr = WORD_RESULT) and (not RetT.IsNull) and TRegEx.IsMatch(LowerCase(Trim(Txt(RetT))), DYN_ARRAY_TYPE_PATTERN) then
              Q2.Info.Kind:= dkDynArray
            else if not IsBoundedArrayOrStore(Q2.Arr, Q2.Info) then Exit;
          end;
          if not SideOf(Args.NamedChild(PX), Q2, AOff, ADepth + 1) then Exit;
        finally
          FAccess:= OldAccess;
          LeaveRoutine(Saved);
        end;
      end;
      Result:= True;
    finally
      FSideVisit.Remove(Key);
    end;
  finally
    Dec(FSideRoutines);
    Dec(FSideWrites);
  end;
end;

{ Every value the local routine ACall names can return (AOutArg -1: each `Result := e` and `Exit(e)` of
  its one body) or leave in its argument number AOutArg, plus AOff, is on the side AQ asks for. }
function TBnRun.CalleeSide(const ACall: TTSNode; const AQ: TSideQ; AOff, ADepth, AOutArg: Integer): Boolean;
var
  Def, Args, Ent, OldAccess: TTSNode;
  Nm, Key, Target: string;
  Cnt, I: Integer;
  Q2: TSideQ;
  Saved: TBnSaved;

  { the returns of the current routine (the callee) }
  function ReturnsOk: Boolean;
  var
    W, A: TTSNode;
    Exits: TList<TTSNode>;
    Rets: Integer;
    Keeps: Boolean;

    procedure Gather(const N: TTSNode);
    var
      J: Integer;
    begin
      if N.IsNull or (N.NodeType = 'lambda') or (N.NodeType = 'defProc') then Exit;
      if (N.NodeType = 'exprCall') and (BareIdent(N.ChildByField('entity')) = 'exit') then Exits.Add(N);
      for J:= 0 to N.ChildCount - 1 do Gather(N.Child(J));
    end;

  begin
    Result:= False;
    Rets:= 0;
    Exits:= TList<TTSNode>.Create;
    try
      if AOutArg < 0 then Gather(FCurProc.ChildByField('body'));
      for W in EventsOf(Target) do
      begin
        Inc(Rets);
        Keeps:= if Q2.Lower then IsStepUp(W, Target) else IsStepDown(W, Target);
        if Keeps then Continue;
        if (W.NodeType <> 'assignment') or not SideOf(W.ChildByField('rhs'), Q2, AOff, ADepth + 1) then Exit;
      end;
      for W in Exits do
      begin
        A:= W.ChildByField('args');
        if A.IsNull or (A.NamedChildCount = 0) then Continue;
        Inc(Rets);
        if not SideOf(A.NamedChild(0), Q2, AOff, ADepth + 1) then Exit;
      end;
      Result:= Rets > 0;
    finally
      Exits.Free;
    end;
  end;

begin
  Result:= False;
  Ent:= if ACall.NodeType = 'exprCall' then ACall.ChildByField('entity') else ACall;
  if Ent.IsNull or (Ent.NodeType <> 'identifier') then Exit;
  if FCallSites = nil then BuildCallIndex;
  Nm:= LowerCase(Txt(Ent));
  if not (FDefCount.TryGetValue(Nm, Cnt) and (Cnt = 1) and FDefNode.TryGetValue(Nm, Def)) then Exit;
  if Def.ChildByField('body').IsNull then Exit;
  Target:= WORD_RESULT;
  if AOutArg >= 0 then
  begin
    if AOutArg > High(ParamNames(Def)) then Exit;
    Target:= ParamNames(Def)[AOutArg];
  end
  else if Def.ChildByField('header').ChildByField('type').IsNull then Exit;
  Q2:= AQ;
  Args:= if ACall.NodeType = 'exprCall' then ACall.ChildByField('args') else Default(TTSNode);
  I:= -1;
  if not Args.IsNull then
    for Cnt:= 0 to Args.NamedChildCount - 1 do
      if BareIdent(Args.NamedChild(Cnt)) = AQ.Arr then I:= Cnt;
  if I >= 0 then
  begin
    if I > High(ParamNames(Def)) then Exit;
    Q2.Arr:= ParamNames(Def)[I];
  end
  else if not SameOuterArray(Def, FCurProc, AQ.Arr) then Exit;
  Key:= Format('%d|fn|%s|%s|%s', [Def.StartByte, Target, BoolToStr(AQ.Lower), Q2.Arr]);
  Inc(FSideWrites);
  Inc(FSideRoutines);
  try
    if SideRevisited(Key, AQ, AOff, Result) or (FSideRoutines > MAX_SIDE_CALLERS) then Exit;
    OldAccess:= FAccess;
    SideEnter(Key, AOff, FSideWrites - 1);
    EnterRoutine(Def, Saved);
    FAccess:= Def.ChildByField('body');
    try
      Result:= ((I < 0) or IsBoundedArrayOrStore(Q2.Arr, Q2.Info)) and ReturnsOk;
    finally
      FAccess:= OldAccess;
      LeaveRoutine(Saved);
      FSideVisit.Remove(Key);
    end;
  finally
    Dec(FSideRoutines);
    Dec(FSideWrites);
  end;
end;

{ N names Length(AB) + AOff of an array: `High(B)`, `Length(B)`, a local alias of either. }
function TBnRun.LengthNamed(const N: TTSNode; out AB: string; out AOff: Integer): Boolean;
var
  Args: TTSNode;
  Fn, Al: string;
begin
  AB:= '';
  Fn:= '';
  AOff:= 0;
  if N.IsNull then Exit(False);
  if N.NodeType = 'exprCall' then
  begin
    Fn:= BareIdent(N.ChildByField('entity'));
    Args:= N.ChildByField('args');
    if Args.IsNull or (Args.NamedChildCount <> 1) then Exit(False);
    AB:= BareIdent(Args.NamedChild(0));
  end
  else if (N.NodeType = 'identifier') and FLenAlias.TryGetValue(LowerCase(Txt(N)), Al) then
  begin
    Fn:= Copy(Al, 1, Pos(':', Al) - 1);
    AB:= Copy(Al, Pos(':', Al) + 1, MaxInt);
  end;
  if Fn = FN_HIGH then AOff:= -1;
  Result:= (AB <> '') and ((Fn = FN_HIGH) or (Fn = FN_LENGTH));
end;

{ E + AOff is on the side AQ asks for by E's own text: a constant, a symbol, a length. }
function TBnRun.SymSide(const N: TTSNode; const AQ: TSideQ; AOff: Integer): Boolean;
var
  S, H: TSym;
  V, K, Lo: Integer;
  B: string;
begin
  Result:= False;
  Lo:= if AQ.Info.Kind = dkArray then AQ.Info.Lo else 0;
  S:= SymOf(N);
  if AQ.Lower then
    Exit((S.Ok and ((S.Base = '') or IsCountBase(S.Base)) and (S.Off + AOff >= Lo)) or ((AOff >= Lo) and NonNegOf(N)));
  if S.Ok and UpperWithin(MkSym(S.Base, S.Off + AOff), AQ.Arr, AQ.Info) then Exit(True);
  if UpperConstOf(N, 0, V) and UpperWithin(MkSym('', V + AOff), AQ.Arr, AQ.Info) then Exit(True);
  if AQ.Info.Kind = dkArray then Exit;
  if LengthNamed(N, B, K) and (K + AOff <= -1) and ((B = AQ.Arr) or LenAtLeast(AQ.Arr, B)) then Exit(True);
  H:= HighSym(AQ.Arr, AQ.Info);
  Result:= S.Ok and H.Ok and StartsText(LEN_BASE, S.Base) and StartsText(LEN_BASE, H.Base) and (S.Off + AOff <= H.Off)
    and EqualLenGuard(Copy(S.Base, Length(LEN_BASE) + 1, MaxInt), Copy(H.Base, Length(LEN_BASE) + 1, MaxInt));
end;

{ The constant AV is on the side AQ asks for; a value below 0 never passes a dynamic array's end. }
function TBnRun.ConstSide(AV: Integer; const AQ: TSideQ): Boolean;
begin
  if AQ.Lower then Exit(AV >= (if AQ.Info.Kind = dkArray then AQ.Info.Lo else 0));
  Result:= UpperWithin(MkSym('', AV), AQ.Arr, AQ.Info)
    or ((AQ.Info.Kind <> dkArray) and ((AV < 0) or (AV < GuardMinLen(AQ.Arr))));
end;

{ E + AOff is on the side AQ asks for (its lower side: at least Low; upper: at most High). }
function TBnRun.SideOf(const E: TTSNode; const AQ: TSideQ; AOff, ADepth: Integer): Boolean;
var
  N, L, R: TTSNode;
  V, K: Integer;
  Op, Word: string;
begin
  Result:= False;
  Dec(FSideBudget);
  if E.IsNull or (FSideBudget < 0) or (ADepth > MAX_SIDE_DEPTH) then Exit;
  N:= ValuePeeled(E);
  if N.IsNull then Exit;
  if EvalIndex(N, V) then Exit(ConstSide(V + AOff, AQ));
  if SymSide(N, AQ, AOff) then Exit(True);
  if N.NodeType = 'identifier' then
  begin
    Word:= LowerCase(Txt(N));
    if SideLocal(Word) then Exit(IdentSide(Word, N, AQ, AOff, ADepth));
    Exit((not InScopes(Word)) and CalleeSide(N, AQ, AOff, ADepth, -1));
  end;
  if N.NodeType = 'exprIf' then
    Exit((SideOf(N.ChildByField('then'), AQ, AOff, ADepth + 1) or ChosenSide(N, False, AQ, AOff, ADepth))
      and (SideOf(N.ChildByField('else'), AQ, AOff, ADepth + 1) or ChosenSide(N, True, AQ, AOff, ADepth)));
  if N.NodeType = 'exprSubscript' then
    Exit(ElementSide(BareIdent(N.ChildByField('entity')), AQ, AOff, ADepth + 1));
  if N.NodeType = 'exprCall' then Exit(CallSide(N, AQ, AOff, ADepth));
  if ElementRead(N) then Exit(ElementSide(BareIdent(N.ChildByField('lhs')), AQ, AOff, ADepth + 1));
  if N.NodeType <> 'exprBinary' then Exit;
  L:= N.ChildByField('lhs');
  R:= N.ChildByField('rhs');
  Op:= OperatorType(N);
  Word:= LowerCase(Trim(Txt(N.ChildByField('operator'))));
  if Op = 'kAdd' then
  begin
    if EvalIndex(ValuePeeled(R), K) then Exit(SideOf(L, AQ, AOff + K, ADepth + 1));
    if EvalIndex(ValuePeeled(L), K) then Exit(SideOf(R, AQ, AOff + K, ADepth + 1));
    Result:= AQ.Lower and ((AQ.Info.Kind <> dkArray) or (AQ.Info.Lo <= 0))
      and SideOf(L, AQ, AOff, ADepth + 1) and (NonNegOf(R) or SideOf(R, ZeroBased(AQ), 0, ADepth + 1));
  end
  else if Op = 'kSub' then
  begin
    if EvalIndex(ValuePeeled(R), K) then Exit(SideOf(L, AQ, AOff - K, ADepth + 1));
    Result:= (not AQ.Lower) and NonNegOf(R) and SideOf(L, AQ, AOff, ADepth + 1);
  end
  else if Word = 'mod' then
    Result:= (AOff = 0) and ModOfLen(N, AQ.Arr, AQ.Lower)
  else if (Word = 'div') or (Word = 'shr') then
    Result:= HalfSide(L, R, Word = 'shr', AQ, AOff, ADepth);
end;

{ `if E < k then a else E` (AElse: the else value; else the then value): the condition compares that very
  expression, which bounds it. }
function TBnRun.ChosenSide(const AIf: TTSNode; AElse: Boolean; const AQ: TSideQ; AOff, ADepth: Integer): Boolean;
var
  C, Other: TTSNode;
  V, Op: string;
  Strict: Integer;
begin
  Result:= False;
  C:= Peeled(AIf.ChildByField('condition'));
  if C.IsNull or (C.NodeType <> 'exprBinary') then Exit;
  V:= TightText(Txt(if AElse then AIf.ChildByField('else') else AIf.ChildByField('then')));
  Op:= OperatorType(C);
  if TightText(Txt(C.ChildByField('lhs'))) = V then Other:= C.ChildByField('rhs')
  else if TightText(Txt(C.ChildByField('rhs'))) = V then
  begin
    Other:= C.ChildByField('lhs');
    Op:= MirrorOp(Op);
  end
  else Exit;
  if AElse then Op:= NegateOp(Op);
  Strict:= if (Op = 'kLt') or (Op = 'kGt') then 1 else 0;
  if AQ.Lower and ((Op = 'kGt') or (Op = 'kGte')) then Result:= SideOf(Other, AQ, AOff + Strict, ADepth + 1)
  else if (not AQ.Lower) and ((Op = 'kLt') or (Op = 'kLte')) then Result:= SideOf(Other, AQ, AOff - Strict, ADepth + 1);
end;

{ AQ as the question "at least 0". }
function TBnRun.ZeroBased(const AQ: TSideQ): TSideQ;
begin
  Result:= AQ;
  Result.Lower:= True;
  Result.Info.Kind:= dkDynArray;
end;

{ SideOf for a call: Min / Max / EnsureRange, a function of this file. }
function TBnRun.CallSide(const N: TTSNode; const AQ: TSideQ; AOff, ADepth: Integer): Boolean;
const
  PAIR_ARGS   = 2;
  ENSURE_ARGS = 3;
var
  Args: TTSNode;
  Fn: string;
begin
  Fn:= BareIdent(N.ChildByField('entity'));
  Args:= N.ChildByField('args');
  if (not Args.IsNull) and (Args.NamedChildCount = PAIR_ARGS) and ((Fn = 'min') or (Fn = 'max')) then
  begin
    { one argument is enough for an upper bound of Min / a lower bound of Max; else both }
    Result:= SideOf(Args.NamedChild(0), AQ, AOff, ADepth + 1);
    if Result = (AQ.Lower = (Fn = 'max')) then Exit;
    Exit(SideOf(Args.NamedChild(1), AQ, AOff, ADepth + 1));
  end;
  if (Fn = 'ensurerange') and (not Args.IsNull) and (Args.NamedChildCount = ENSURE_ARGS) then
    Exit(SideOf(Args.NamedChild(1), AQ, AOff, ADepth + 1) and SideOf(Args.NamedChild(2), AQ, AOff, ADepth + 1));
  { 1.53 SLZ-IDXFP (Analysis.DataFlow:416): `B := Work.Dequeue` -- an element of a local list }
  if ElementRead(N.ChildByField('entity')) then
    Exit(ElementSide(BareIdent(N.ChildByField('entity').ChildByField('lhs')), AQ, AOff, ADepth + 1));
  Result:= CalleeSide(N, AQ, AOff, ADepth, -1);
end;

{ N is `X.Dequeue` / `.Pop` / `.Peek` / `.Extract` / `.First` / `.Last`. }
function TBnRun.ElementRead(const N: TTSNode): Boolean;
begin
  Result:= (not N.IsNull) and (N.NodeType = 'exprDot')
    and MatchText(Trim(Txt(N.ChildByField('rhs'))), ['dequeue', 'pop', 'peek', 'extract', 'first', 'last']);
end;

{ `L div k` / `L shr k` (+ AOff): the midpoint (x + y [+ 1]) div 2 of two values on the safe side, or a
  quotient of a value between 0 and the bound. }
function TBnRun.HalfSide(const L, R: TTSNode; AShift: Boolean; const AQ: TSideQ; AOff, ADepth: Integer): Boolean;
const
  HALF_DIV = 2;
var
  Sum, A, B: TTSNode;
  K, Extra: Integer;
begin
  Result:= False;
  if not EvalIndex(ValuePeeled(R), K) or (K < (if AShift then 1 else HALF_DIV)) then Exit;
  Sum:= ValuePeeled(L);
  Extra:= 0;
  if (Sum.NodeType = 'exprBinary') and (OperatorType(Sum) = 'kAdd') and EvalIndex(ValuePeeled(Sum.ChildByField('rhs')), Extra) then
    Sum:= ValuePeeled(Sum.ChildByField('lhs'));
  if (Sum.NodeType = 'exprBinary') and (OperatorType(Sum) = 'kAdd') and ((Extra = 0) or (Extra = 1))
    and (K = (if AShift then 1 else HALF_DIV)) then
  begin
    A:= Sum.ChildByField('lhs');
    B:= Sum.ChildByField('rhs');
    if AQ.Lower or (Extra = 0) then Exit(SideOf(A, AQ, AOff, ADepth + 1) and SideOf(B, AQ, AOff, ADepth + 1));
    Exit((SideOf(A, AQ, AOff + 1, ADepth + 1) and SideOf(B, AQ, AOff, ADepth + 1))
      or (SideOf(A, AQ, AOff, ADepth + 1) and SideOf(B, AQ, AOff + 1, ADepth + 1)));
  end;
  { 0 <= x: 0 <= x div k <= x }
  if not SideOf(L, ZeroBased(AQ), 0, ADepth + 1) then Exit;
  Result:= if AQ.Lower then (AOff >= 0) and ((AQ.Info.Kind <> dkArray) or (AQ.Info.Lo <= AOff)) else SideOf(L, AQ, AOff, ADepth + 1);
end;

{ ---- two arrays of one length (1.53 SLZ-IDXFP) ---- }

{ The size changes of AName inside AScope (the routine that declares it, or the file's root for a field
  / global), in text order: assignments to it (also `X.AName :=`), SetLength, Delete, Insert. }
function TBnRun.SizeEvents(const AName: string; const AScope: TTSNode): TArray<TTSNode>;
var
  L: TList<TTSNode>;

  function DottedChange(const N: TTSNode): Boolean;
  var
    A: TTSNode;
  begin
    if N.NodeType = 'assignment' then A:= N.ChildByField('lhs')
    else
    begin
      if (N.NodeType <> 'exprCall') or not MatchStr(CallName(N), [FN_SETLENGTH, 'delete']) then Exit(False);
      A:= N.ChildByField('args');
      if A.IsNull or (A.NamedChildCount = 0) then Exit(False);
      A:= A.NamedChild(0);
    end;
    Result:= (not A.IsNull) and (A.NodeType = 'exprDot') and SameText(Trim(Txt(A.ChildByField('rhs'))), AName);
  end;

  procedure Walk(const N: TTSNode);
  var
    J: Integer;
  begin
    if N.IsNull then Exit;
    if IsSizeChangeOf(N, AName) or ((AScope = FRoot) and DottedChange(N)) then L.Add(N);
    for J:= 0 to N.ChildCount - 1 do Walk(N.Child(J));
  end;

begin
  L:= TList<TTSNode>.Create;
  try
    Walk(AScope);
    Result:= L.ToArray;
  finally
    L.Free;
  end;
end;

{ What a size change does, in words that match for two arrays changed alike: 'nil', 'app<n>',
  'set:<size>', 'del:<args>', 'txt:<rhs>' -- the array's own name read as @. }
function TBnRun.SizeKey(const W: TTSNode; const AName: string): string;
var
  T, Own: string;
  M: TMatch;
  R: TTSNode;
begin
  Own:= '(?<![\w.])(\w+\.)*' + TRegEx.Escape(AName) + '\b';
  if W.NodeType = 'assignment' then
  begin
    R:= Peeled(W.ChildByField('rhs'));
    T:= TRegEx.Replace(TightText(Txt(R)), Own, '@');
    if (T = KEY_NIL) or (T = '[]') then Exit(KEY_NIL);
    if StartsStr('@+[', T) and (R.NodeType = 'exprBinary') and (Peeled(R.ChildByField('rhs')).NodeType = 'exprBrackets') then
      Exit(KEY_APPEND + IntToStr(Peeled(R.ChildByField('rhs')).NamedChildCount));
    Exit(KEY_TEXT + T);
  end;
  if CallName(W) = 'insert' then Exit(KEY_APPEND + '1');
  T:= TRegEx.Replace(TightText(Txt(W.ChildByField('args'))), Own, '@');
  T:= TRegEx.Replace(T, '^\((.*)\)$', '$1');
  if CallName(W) = 'delete' then Exit('del:' + T);
  T:= Copy(T, Pos(',', T) + 1, MaxInt);
  if T = '0' then Exit(KEY_NIL);
  M:= TRegEx.Match(T, '^length\(@\)\+(\d+)$');
  Result:= if M.Success then KEY_APPEND + M.Groups[1].Value else 'set:' + T;
end;

{ The text before the array's name in `X.A :=` / SetLength(X.A, ..). }
function TBnRun.SizePrefix(const W: TTSNode; const AName: string): string;
var
  T: string;
begin
  T:= TightText(Txt(if W.NodeType = 'assignment' then W.ChildByField('lhs') else W.ChildByField('args').NamedChild(0)));
  Result:= if EndsText('.' + AName, T) then Copy(T, 1, Length(T) - Length(AName)) else '';
end;

{ X and Y are statements of one list, no leave between them, and the access is not between them. }
function TBnRun.SizedTogether(const X, Y: TTSNode): Boolean;
var
  SX, SY, T: TTSNode;
begin
  SX:= ListStatement(X);
  SY:= ListStatement(Y);
  if SX.IsNull or SY.IsNull or not (SX.Parent = SY.Parent) then Exit(False);  // dl:ok nonminimal-bool -- TTSNode declares Equal but no NotEqual; <> does not compile
  if SY.StartByte < SX.StartByte then
  begin
    T:= SX;
    SX:= SY;
    SY:= T;
  end;
  if (FAccess.StartByte >= SX.EndByte) and (FAccess.EndByte <= SY.StartByte) then Exit(False);
  T:= SX.NextNamedSibling;
  while (not T.IsNull) and (T.StartByte < SY.StartByte) do
  begin
    if TRegEx.IsMatch(Txt(T), '(?i)\b(exit|raise|continue|break|goto)\b') then Exit(False);
    T:= T.NextNamedSibling;
  end;
  Result:= True;
end;

{ A statement strictly between the size changes X and Y names something their size AKey (`set:e`, `del:a`,
  `txt:e`) reads: the two may see different values. }
function TBnRun.SizeReadChanged(const X, Y: TTSNode; const AKey: string): Boolean;
var
  T: TTSNode;
  From, Upto: Cardinal;
  M: TMatch;
begin
  Result:= False;
  if StartsStr(KEY_APPEND, AKey) or (AKey = KEY_NIL) then Exit;
  From:= if X.StartByte < Y.StartByte then X.EndByte else Y.EndByte;
  Upto:= if X.StartByte < Y.StartByte then Y.StartByte else X.StartByte;
  T:= ListStatement(if X.StartByte < Y.StartByte then X else Y).NextNamedSibling;
  while (not T.IsNull) and (T.StartByte < Upto) do
  begin
    if T.StartByte >= From then
      for M in TRegEx.Matches(Copy(AKey, Pos(':', AKey) + 1, MaxInt), '[a-z_]\w*') do
        if (M.Value <> FN_LENGTH) and Mentions(T, M.Value) and not StartsStr(FN_SETLENGTH + '(', TightText(Txt(T))) then Exit(True);
    T:= T.NextNamedSibling;
  end;
end;

{ A routine of this file takes A or B by reference somewhere in N: it may size one of them. }
function TBnRun.PassedByRefLocally(const N: TTSNode; const A, B: string): Boolean;
var
  J: Integer;
  Args: TTSNode;
  M, Nm: string;
begin
  Result:= False;
  if N.IsNull then Exit;
  if N.NodeType = 'exprCall' then
  begin
    Args:= N.ChildByField('args');
    if FArgModes = nil then BuildArgModes;
    if (not Args.IsNull) and FArgModes.TryGetValue(CallName(N), M) then
      for J:= 0 to Args.NamedChildCount - 1 do
      begin
        Nm:= BareIdent(Args.NamedChild(J));
        if ((Nm = A) or (Nm = B)) and ((M = '?') or ((J < Length(M)) and (M[J + 1] = 'r'))) then Exit(True);
      end;
  end;
  for J:= 0 to N.ChildCount - 1 do
    if PassedByRefLocally(N.Child(J), A, B) then Exit(True);
end;

{ Length(A) >= Length(B) at the access because the two are only ever changed together: each change of B
  has the same change of A (or `SetLength(A, Length(B))` / `SetLength(B, Length(A))`) in the same
  statement list, and what is left of A only grows. Both are locals of one routine, or both fields /
  globals of this file. }
function TBnRun.TwinArrays(const A, B: string; ADepth: Integer): Boolean;
var
  EvA, EvB: TArray<TTSNode>;
  Scope, OA, OB, W: TTSNode;
  Used: TArray<Boolean>;
  I: Integer;
  Found: Boolean;

  function Matches(const X, Y: TTSNode): Boolean;
  var
    KX, KY: string;
  begin
    KX:= SizeKey(X, A);
    KY:= SizeKey(Y, B);
    Result:= ((KX = KY) or ((KX = 'set:length(' + B + ')') and (X.StartByte > Y.StartByte))
      or ((KY = 'set:length(' + A + ')') and (Y.StartByte > X.StartByte))
      { `B := E; SetLength(A, Length(E) [+ k])`, `A := KeptA; B := KeptB` }
      or (TRegEx.IsMatch(KY, '^txt:\w+$') and TRegEx.IsMatch(KX, '^set:length\(' + Copy(KY, Length(KEY_TEXT) + 1, MaxInt) + '\)(\+\d+)?$'))
      or (TRegEx.IsMatch(KY, '^txt:\w+$') and TRegEx.IsMatch(KX, '^txt:\w+$') and (ADepth = 0)
        and TwinArrays(Copy(KX, Length(KEY_TEXT) + 1, MaxInt), Copy(KY, Length(KEY_TEXT) + 1, MaxInt), 1)))
      and (SizePrefix(X, A) = SizePrefix(Y, B)) and SizedTogether(X, Y) and not SizeReadChanged(X, Y, KY);
  end;

begin
  Result:= False;
  OA:= ArrayOwner(FCurProc, A);
  OB:= ArrayOwner(FCurProc, B);
  if (OA.IsNull <> OB.IsNull) or ((not OA.IsNull) and not (OA = OB)) then Exit;  // dl:ok nonminimal-bool -- TTSNode declares Equal but no NotEqual; <> does not compile
  Scope:= if OA.IsNull then FRoot else OA;
  if (not OA.IsNull) and ((IndexStr(A, ParamNames(OA)) >= 0) or (IndexStr(B, ParamNames(OA)) >= 0)) then Exit;
  EvA:= SizeEvents(A, Scope);
  EvB:= SizeEvents(B, Scope);
  if (Length(EvA) = 0) or (Length(EvB) = 0) then Exit;
  if OA.IsNull and SizedOnce(A, B, EvA, EvB) then Exit(True);
  SetLength(Used, Length(EvA));
  for W in EvB do
  begin
    Found:= False;
    for I:= 0 to High(EvA) do
      if (not Found) and (not Used[I]) and Matches(EvA[I], W) then
      begin
        Used[I]:= True;
        Found:= True;
      end;
    if (not Found) and (SizeKey(W, B) <> KEY_NIL) then Exit;
  end;
  for I:= 0 to High(EvA) do
    if (not Used[I]) and not StartsStr(KEY_APPEND, SizeKey(EvA[I], A)) then Exit;
  Result:= not PassedByRefLocally(Scope, A, B);
end;

{ Two fields: B gets its length in one place of the file, A in one place, `SetLength(A, Length(B))`
  (a reset to nil counts as neither). }
function TBnRun.SizedOnce(const A, B: string; const AEvA, AEvB: TArray<TTSNode>): Boolean;
var
  W, One: TTSNode;
  CntA, CntB: Integer;
begin
  CntA:= 0;
  CntB:= 0;
  One:= Default(TTSNode);
  for W in AEvA do
    if SizeKey(W, A) <> KEY_NIL then
    begin
      Inc(CntA);
      One:= W;
    end;
  for W in AEvB do
    if SizeKey(W, B) <> KEY_NIL then Inc(CntB);
  Result:= (CntA = 1) and (CntB = 1) and TRegEx.IsMatch(SizeKey(One, A), '^set:length\(' + TRegEx.Escape(B) + '\)(\+\d+)?$');
end;

{ From AFrom to the end of the loops around the access A is not shortened and B keeps its size -- a
  field B also through every routine of this file that changes it: the window names none. }
function TBnRun.SizesKept(const A, B: string; AFrom: Cardinal): Boolean;
var
  Hi: Cardinal;
  W, P: TTSNode;
  Nm: string;

  function NamedIn(const N: TTSNode): Boolean;
  var
    J: Integer;
  begin
    Result:= False;
    if N.IsNull or (N.EndByte <= AFrom) or (N.StartByte >= Hi) then Exit;
    if (N.NodeType = 'exprDot') and not SameText(Trim(Txt(N.ChildByField('lhs'))), 'self') then Exit(NamedIn(N.ChildByField('lhs')));
    if (N.NodeType = 'identifier') and (N.StartByte >= AFrom) and SameText(Txt(N), Nm) then Exit(True);
    for J:= 0 to N.ChildCount - 1 do
      if NamedIn(N.Child(J)) then Exit(True);
  end;

begin
  Hi:= AccessReach(FAccess, AFrom);
  if ShrunkIn(A, AFrom, Hi) or SizeChangedIn(B, AFrom, Hi) then Exit(False);
  Result:= True;
  if not ArrayOwner(FCurProc, B).IsNull then Exit;
  for W in SizeEvents(B, FRoot) do
  begin
    P:= EnclosingProc(W);
    if P.IsNull then Exit(False);
    Nm:= LowerCase(Trim(Txt(P.ChildByField('header').ChildByField('name'))));
    Nm:= Copy(Nm, LastDelimiter('.', Nm) + 1, MaxInt);
    if NamedIn(FCurProc.ChildByField('body')) then Exit(False);
  end;
end;

{ Statement S (an earlier one of a list around the access) makes Length(A) >= Length(B):
  `if Length(A) < Length(B) then SetLength(A, Length(B))`, or `if not Same then Exit` after
  `Same := Length(A) = Length(B)`. }
function TBnRun.EnsuresLength(const S: TTSNode; const A, B: string): Boolean;
var
  W, ThenN: TTSNode;
  T, Cond, LA, LB, X: string;
  M: TMatch;
begin
  Result:= False;
  if S.NodeType <> 'if' then Exit;
  LA:= 'length(' + A + ')';
  LB:= 'length(' + B + ')';
  ThenN:= S.ChildByField('then');
  Cond:= TightText(Txt(S.ChildByField('condition')));
  T:= TRegEx.Replace(TightText(Txt(ThenN)), ';$', '');
  if T = 'setlength(' + A + ',' + LB + ')' then
    Exit(MatchStr(Cond, [LB + '>' + LA, LA + '<' + LB, LA + '<>' + LB, LB + '<>' + LA]));
  M:= TRegEx.Match(Cond, '^not\(?(\w+)\)?$');
  if (not M.Success) or not IsLeaveStmt(ThenN) then Exit;
  X:= M.Groups[1].Value;
  W:= S.PrevNamedSibling;
  while (not W.IsNull) and IsTrivia(W) do W:= W.PrevNamedSibling;
  if W.IsNull then Exit;
  T:= TRegEx.Replace(TightText(Txt(W)), ';$', '');
  Result:= MatchStr(T, [X + ':=' + LA + '=' + LB, X + ':=' + LB + '=' + LA]);
end;

{ Condition C (ANegate: its failure) says Length(A) >= Length(B). }
function TBnRun.LengthCond(const C: TTSNode; ANegate: Boolean; const A, B: string): Boolean;
var
  E: TTSNode;
  Op, LA, LB, L, R: string;
begin
  Result:= False;
  E:= Peeled(C);
  if E.IsNull then Exit;
  if (E.NodeType = 'exprUnary') and (OperatorType(E) = 'kNot') then Exit(LengthCond(E.ChildByField('operand'), not ANegate, A, B));
  if E.NodeType <> 'exprBinary' then Exit;
  Op:= OperatorType(E);
  if (Op = 'kAnd') or (Op = 'kOr') then
    Exit(((Op = 'kAnd') <> ANegate) and (LengthCond(E.ChildByField('lhs'), ANegate, A, B) or LengthCond(E.ChildByField('rhs'), ANegate, A, B)));
  LA:= 'length(' + A + ')';
  LB:= 'length(' + B + ')';
  L:= TightText(Txt(E.ChildByField('lhs')));
  R:= TightText(Txt(E.ChildByField('rhs')));
  if (L = LB) and (R = LA) then Op:= MirrorOp(Op)
  else if (L <> LA) or (R <> LB) then Exit;
  if ANegate then Op:= if Op = 'kNeq' then 'kEq' else if Op = 'kEq' then 'kNeq' else NegateOp(Op);
  Result:= (Op = 'kEq') or (Op = 'kGte') or (Op = 'kGt');
end;

{ The local A is filled by one append per trip of a loop over B (`for x in B do begin ..; A := A + [e] end`,
  no Continue / Break in it), the access is after that loop and B keeps its size from the loop on. }
function TBnRun.MappedArray(const A, B: string): Boolean;
var
  W, App, F, St: TTSNode;
begin
  Result:= False;
  if not (ArrayOwner(FCurProc, A) = FCurProc) or (IndexStr(A, ParamNames(FCurProc)) >= 0) then Exit;  // dl:ok nonminimal-bool -- TTSNode declares Equal but no NotEqual; <> does not compile
  App:= Default(TTSNode);
  for W in SizeEvents(A, FCurProc) do
    if SizeKey(W, A) = KEY_APPEND + '1' then
    begin
      if not App.IsNull then Exit;
      App:= W;
    end
    else if (SizeKey(W, A) <> KEY_NIL) or not App.IsNull then Exit;
  if App.IsNull then Exit;
  F:= App.Parent;
  while (not F.IsNull) and (F.NodeType <> 'foreach') and (F.NodeType <> 'for') do
  begin
    if (F.NodeType <> 'block') and (F.NodeType <> 'statements') and (F.NodeType <> 'statement') then Exit;
    F:= F.Parent;
  end;
  if F.IsNull or (FAccess.StartByte < F.EndByte) or IsInLoop(F) or TRegEx.IsMatch(Txt(F), '(?i)\b(continue|break|goto)\b') then Exit;
  if F.NodeType = 'foreach' then
  begin
    if BareIdent(F.ChildByField('iterable')) <> B then Exit;
  end
  else if not (IsArrayFn(F.ChildByField('end'), FN_HIGH, B) and (TightText(Txt(F.ChildByField('start').ChildByField('rhs'))) = '0')) then Exit;
  St:= ListStatement(F);
  Result:= (not St.IsNull) and StmtDominates(F, FAccess) and SizesKept(A, B, F.EndByte) and not SizeChangedIn(B, F.StartByte, F.EndByte);
end;

{ Length(A) >= Length(B) at the access under analysis. }
function TBnRun.LenAtLeast(const A, B: string): Boolean;
var
  Dom, C, P, S, W, D: TTSNode;
begin
  Result:= False;
  if FAccess.IsNull or not NodeWithin(FAccess, FCurProc) then Exit;
  if EqualLenGuard(B, A) then Exit(True);
  { SetLength(A, Length(B)) [+ k] }
  Dom:= DomSetLength(A);
  if (not Dom.IsNull) and TRegEx.IsMatch(TightText(Txt(Dom.ChildByField('args').NamedChild(1))), '^length\(' + TRegEx.Escape(B) + '\)(\+\d+)?$')
    and SizesKept(A, B, Dom.EndByte) then Exit(True);
  { A := Copy(B) / A := B }
  D:= Default(TTSNode);
  for W in SizeEvents(A, FCurProc.ChildByField('body')) do
    if StmtDominates(W, FAccess) and (D.IsNull or (W.StartByte > D.StartByte)) then D:= W;
  if (not D.IsNull) and (D.NodeType = 'assignment') and MatchStr(TightText(Txt(D.ChildByField('rhs'))), [B, 'copy(' + B + ')'])
    and SizesKept(A, B, D.EndByte) then Exit(True);
  C:= FAccess;
  P:= C.Parent;
  while (not P.IsNull) and (P.NodeType <> 'defProc') and (P.NodeType <> 'lambda') do
  begin
    if ((P.NodeType = 'if') or (P.NodeType = 'ifElse')) and ((P.ChildByField('then') = C) or (P.ChildByField('else') = C))
      and LengthCond(P.ChildByField('condition'), P.ChildByField('else') = C, A, B)
      and SizesKept(A, B, P.ChildByField('condition').EndByte) then Exit(True);
    if (P.NodeType = 'block') or (P.NodeType = 'statements') then
    begin
      S:= C.PrevNamedSibling;
      while not S.IsNull do
      begin
        if EnsuresLength(S, A, B) and SizesKept(A, B, S.EndByte) then Exit(True);
        S:= S.PrevNamedSibling;
      end;
    end;
    C:= P;
    P:= C.Parent;
  end;
  Result:= MappedArray(A, B) or TwinArrays(A, B, 0);
end;

{ One side of the access under analysis by the provers above. }
function TBnRun.AccessSide(const ACtx: TIdxCtx; ALower: Boolean): Boolean;
var
  Q: TSideQ;
begin
  Q.Arr:= ACtx.Arr;
  Q.Info:= ACtx.Info;
  Q.Lower:= ALower;
  FSideBudget:= SIDE_BUDGET;
  FSideWrites:= 0;
  FSideRoutines:= 0;
  FSideVisit.Clear;
  Result:= IdentSide(ACtx.Idx, ACtx.Access.ChildByField('args').NamedChild(0), Q, 0, 0);
end;

{ A nested routine of AProc or a lambda in its body names AX and may write it: the routine-local view is
  blind there. }
function TBnRun.NamedElsewhere(const AProc: TTSNode; const AX: string): Boolean;

  function InLambda(const N: TTSNode): Boolean;
  var
    J: Integer;
  begin
    Result:= False;
    if N.IsNull then Exit;
    if N.NodeType = 'lambda' then Exit(Mentions(N, AX));
    for J:= 0 to N.ChildCount - 1 do
      if InLambda(N.Child(J)) then Exit(True);
  end;

var
  I: Integer;
begin
  Result:= InLambda(AProc.ChildByField('body'));
  if not Result then
    for I:= 0 to AProc.ChildCount - 1 do
      if (AProc.Child(I).NodeType = 'defProc') and Mentions(AProc.Child(I), AX) then Exit(True);
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
      if not IsBoundedArray(Ctx.Arr, Ctx.Info) then
      begin
        { 1.52.3 IDXRANGE-TP (uINSPRSLT:5575): another unit's const / var array, read from the index }
        if Lookup(Ctx.Arr, Ctx.Info) or not StoreArray(Ctx.Arr, Ctx.Info) then Continue;
        Ctx.Foreign:= True;
      end;
      if NamedElsewhere(AProc, Ctx.Idx) then Continue;
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
