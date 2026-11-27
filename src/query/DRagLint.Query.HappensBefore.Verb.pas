unit DRagLint.Query.HappensBefore.Verb;

{ drag-lint 1.56 -- lane HB4: the answer of the `happens-before --a <event> --b <event>` verb (G-56;
  spec docs\superpowers\specs\2026-11-17-happens-before-design.md sec. 2.4) over the
  DRagLint.Query.HappensBefore* units. DRagLint.CLI.HappensBefore parses the command line and prints.

  QUESTION: on every execution, has event A happened before event B happens?
    YES  proven: every site of B runs after a site of A.
    NO   proven: there is a run of B with no A before it (A has no site at all, or every site of A
         runs after a site of B in its own routine, so the first B ran before the first A).
    MAY  not proven either way. Every doubt answers MAY: a wrong YES or NO is worse than a MAY.

  An EVENT is a set of index sites:
    write:<QName>    the writers of a unit variable, class var or instance field (events lane)
    read:<QName>     its reads
    call:<QName>     the call sites the index resolves to that routine
    extcall:<Name>[,<Name>...]   the calls of routines the index does NOT hold (RTL, a library), by name
    extwrite:<Name>[,<Name>...]  the assignments to (or through) a variable the index does NOT hold
    app-run:<program>|*          the top-level Application.Run of that program block (* = every program)
    site:<file>:<line>[:<col>]   one source position
  A site is DEFINITE when the event certainly happens there; a var / out argument, a call the index
  cannot resolve or a write inside a `with` is an UNCERTAIN site (the event may or may not happen).
  An event is INCOMPLETE when it can also happen where the index holds no site (address taken,
  published, virtual dispatch, a routine something outside the code runs).

  PROOF, all through DRagLint.Query.HappensBefore.Intra.SolveRoutine (a must-analysis, so every step
  is sound; nothing of the check-init solver is copied):
    same-routine  the marks of A in B's routine dominate B.
    callee        ... counting a certain call of a routine that performs A on every normal return.
    callers       B's routine is called only by resolved, certain calls and A is proven before
                  every one of them (HBV_MAX_CALLER_DEPTH levels up).
    check-init    write:T before read:T that the three above could not prove is handed to
                  DRagLint.Query.HappensBefore.CheckInit (ordered roots: initialization chain, program
                  block, handler order); its SET is a YES. Its optimism is inherited: check-init
                  counts a var / out argument as a write.
    program-order (lane HB5)  what the three above could not prove goes to the ordered-root solve
                  DRagLint.Query.HappensBefore.HbOrderSolve with the DEFINITE sites of A as marks:
                  initialization chain, program block, handler order, call chains. The same solve
                  with B as marks proves the b-first NO; a NO never leans on the handler-order
                  heuristic or on indirect-call edges, a YES that does carries the limit.
  YES needs a complete B; NO needs a complete A.

  PRE-CHECK (lane HB5): before any routine body is solved, the call graph alone says which sites of
  B a proof can reach at all -- the routines that hold a site of A, everything that reaches one
  backwards (calls of every confidence, dispatch, indirect edges), and everything those reach
  forwards. A site of B outside that set is unprovable and answers a-in-other-routine at once
  (limit pre-check); when that is every site of B, the b-first proof is not tried either. The pre-check stands down (proves nothing, refutes nothing) when A is in an
  initialization section or a program block, when a walk passes HBV_PRECHECK_MAX_NODES, and for
  write:T / read:T (the constructor model of check-init orders sites the call graph does not).

  Sites are not instances: `write:TFoo.FBar` is a write of FBar on ANY object (limit
  instance-insensitive).

  Read-only; nothing is persisted (no extractor change). }

interface

uses
  DRagLint.Query.HappensBefore.Types
  ;

const
  /// <summary>How many caller levels the `callers` proof climbs from a site of B.</summary>
  HBV_MAX_CALLER_DEPTH = 6;
  /// <summary>The `limits[]` code of an answer that matched an `extcall:` event by NAME: the index
  /// does not hold the callee, so a same-named routine of another unit matches too.</summary>
  HBV_LIMIT_MATCHED_BY_NAME = 'matched-by-name';
  /// <summary>The `limits[]` code of an answer over an instance field: the sites of every object count
  /// as one event.</summary>
  HBV_LIMIT_INSTANCE_INSENSITIVE = 'instance-insensitive';
  /// <summary>The `limits[]` code of an answer the --max-routines budget stopped short.</summary>
  HBV_LIMIT_BUDGET = 'budget';
  /// <summary>The `limits[]` code of an answer in which the call-graph pre-check answered at least one
  /// site of B (no routine that performs A reaches it) without solving a routine body.</summary>
  HBV_LIMIT_PRECHECK = 'pre-check';
  /// <summary>Prefix of the `limits[]` codes a program-order proof leaned on: followed by
  /// relied-on-handler-order or relied-on-indirect-edges.</summary>
  HBV_LIMIT_PROGRAM_ORDER = 'program-order: ';
  /// <summary>How many routines one walk of the pre-check may visit before it stands down.</summary>
  HBV_PRECHECK_MAX_NODES = 5000;
  /// <summary>The program-order solve is not tried with more marks than this (cost).</summary>
  HBV_ORDER_MAX_MARKS = 256;
  /// <summary>Exit code of a YES.</summary>
  HBV_EXIT_YES = 0;
  /// <summary>Exit code of a NO or a MAY.</summary>
  HBV_EXIT_NOT_YES = 1;

type
  /// <summary>The three answers of the verb. The literals are YES, NO, MAY.</summary>
  THbvVerdict = (hbvYes, hbvNo, hbvMay);

  /// <summary>The kinds of event a `--a` / `--b` value can name: the prefix is write, read, call, extcall,
  /// site, extwrite, app-run.</summary>
  THbvEventKind = (hekWrite, hekRead, hekCall, hekExtCall, hekSite, hekExtWrite, hekAppRun);

  /// <summary>Closed list of reason codes, in the order of the `reasons[]` literals a-never-happens, b-first,
  /// a-not-on-every-path, a-in-other-routine, a-site-uncertain, a-sites-incomplete, b-sites-incomplete,
  /// no-b-site, no-routine-body, budget; tools branch on them. Never rename one.</summary>
  /// <remarks>a-never-happens and b-first are the two proofs of NO; the rest explain a MAY.</remarks>
  THbvReason = (hvrANeverHappens, hvrBFirst, hvrANotOnEveryPath, hvrAInOtherRoutine, hvrASiteUncertain,
    hvrASitesIncomplete, hvrBSitesIncomplete, hvrNoBSite, hvrNoRoutineBody, hvrBudget);

  /// <summary>How a site was proven: same-routine, callee, callers, check-init, program-order; hvmNone = not proven.</summary>
  THbvMethod = (hvmNone, hvmSameRoutine, hvmCallee, hvmCallers, hvmCheckInit, hvmProgramOrder);

  /// <summary>One site of an event.</summary>
  THbvSite = record
    /// <summary>File (full path), line, column, enclosing routine (RoutineId 0 = no routine body:
    /// program block, initialization section, unit level).</summary>
    Site: THbSite;
    /// <summary>True when the event certainly happens when this site runs.</summary>
    Definite: Boolean;
    /// <summary>For an uncertain site: the source line and why it is uncertain; else ''.</summary>
    Note: string;
  end;

  /// <summary>One resolved `--a` / `--b` event.</summary>
  THbvEvent = record
    /// <summary>The event as the answer spells it: `kind:name` with the resolved QName.</summary>
    Spec: string;
    Kind: THbvEventKind;
    /// <summary>Resolved QName (write / read / call), the bare name (extcall) or file:line[:col] (site).</summary>
    Name: string;
    /// <summary>Every site, sorted by file, line, column.</summary>
    Sites: TArray<THbvSite>;
    /// <summary>False when the event can also happen where the index holds no site.</summary>
    Complete: Boolean;
    /// <summary>One line per reason the event is incomplete; empty when Complete.</summary>
    IncompleteWhy: TArray<string>;
    /// <summary>True for write / read of an instance field (limit instance-insensitive).</summary>
    InstanceField: Boolean;
  end;

  /// <summary>The verdict of one judged site.</summary>
  THbvSiteAnswer = record
    Site: THbSite;
    /// <summary>True when the row is a site of A judged against B (the b-first proof of NO); False
    /// for a site of B judged against A.</summary>
    SideA: Boolean;
    /// <summary>True when the other event is proven to have happened before this site.</summary>
    Proven: Boolean;
    /// <summary>How it was proven; hvmNone when not.</summary>
    Method: THbvMethod;
    /// <summary>Why it was not proven (meaningful when Proven is False).</summary>
    Reason: THbvReason;
    /// <summary>One line for the user.</summary>
    Why: string;
    /// <summary>True when the call-graph pre-check answered this site (never Proven): no routine body
    /// was solved for it and no later proof is tried.</summary>
    PreChecked: Boolean;
  end;

  /// <summary>The complete answer of one `happens-before` question.</summary>
  /// <remarks>Value record; the caller owns nothing. Proven is True for YES and NO, False for MAY.</remarks>
  THbvAnswer = record
    /// <summary>The preset that produced A and B, '' for a plain --a / --b question.</summary>
    Preset: string;
    A: THbvEvent;
    B: THbvEvent;
    Verdict: THbvVerdict;
    Proven: Boolean;
    /// <summary>One line: what was proven, or why nothing was.</summary>
    Summary: string;
    /// <summary>Distinct reason codes, in enum order.</summary>
    Reasons: TArray<THbvReason>;
    /// <summary>Distinct proof methods used, in enum order (never hvmNone).</summary>
    Methods: TArray<THbvMethod>;
    /// <summary>The judged sites: sites of B for YES / MAY, plus sites of A when b-first was tried.</summary>
    Judged: TArray<THbvSiteAnswer>;
    /// <summary>Limit codes (HBV_LIMIT_*, `check-init: &lt;verdict&gt;`).</summary>
    Limits: TArray<string>;
    /// <summary>Routine bodies solved.</summary>
    Routines: Integer;
    /// <summary>True when --max-routines stopped the proof short.</summary>
    Exhausted: Boolean;
    /// <summary>Wall-clock milliseconds.</summary>
    Ms: Int64;
  end;

/// <summary>Answers "has event A happened before event B, on every execution?" over one index.</summary>
/// <param name="pDbPath">The project index; must exist and be readable (the verb checks the schema).</param>
/// <param name="pA">Event A: `write:`, `read:`, `call:`, `extcall:` or `site:` (see the unit header).</param>
/// <param name="pB">Event B, same forms.</param>
/// <param name="pOptions">MaxRoutines (0 = HB_DEFAULT_MAX_ROUTINES) caps the routine bodies solved;
/// MaxSeconds caps the wall clock of the whole question, the check-init step included (0 = HB_DEFAULT_MAX_SECONDS, negative = no cap). Explain is not read.</param>
/// <returns>YES only when every site of a complete B is proven to run after A; NO only when a complete
/// A has no site, or every site of A is proven to run after B in its own routine; else MAY with a
/// reason per unproven site. A B without sites answers MAY (no-b-site): a YES over nothing is vacuous.</returns>
/// <exception cref="EHbUsage">Malformed event, unknown event kind, unknown or ambiguous target /
/// routine / file (candidates attached).</exception>
/// <remarks>Read-only. Not thread-safe (the shared parse cache and clock of the check-init units).
/// Deterministic except Ms.</remarks>
function HappensBefore(const pDbPath, pA, pB: string; const pOptions: THbOptions): THbvAnswer;

/// <summary>Expands a preset name into its events.</summary>
/// <param name="pPreset">Preset name, case-insensitive.</param>
/// <param name="pA">Out: event A of the preset; '' when the preset takes the caller's --a.</param>
/// <param name="pB">Out: event B of the preset.</param>
/// <returns>False for a name that is not a built preset (pA and pB are then '').</returns>
/// <remarks>Built: `randomize` (A = extcall:Randomize, B = extcall:Random); `format-settings`
/// (A = extwrite:FormatSettings, B = extcall: of the RTL routines that format or parse with the
/// global settings); `before-app-run` (A = the caller's --a, B = app-run:*).</remarks>
function HbvPresetEvents(const pPreset: string; out pA, pB: string): Boolean;

/// <summary>The names of the built presets, in help order.</summary>
/// <returns>A new array; never empty.</returns>
function HbvPresetNames: TArray<string>;

/// <summary>The `--json` document of an answer (one line).</summary>
/// <param name="pAnswer">A complete answer.</param>
/// <returns>`{verb, preset?, a, b, verdict, proven, summary, reasons[], methods[], judged[], limits[],
/// budget{routines, ms, exhausted}}`; a / b = `{event, kind, name, complete, incomplete[], sites[]}`.</returns>
function HbvAnswerJson(const pAnswer: THbvAnswer): string;

/// <summary>Prints an answer as text on stdout: header, verdict line, judged sites, uncertain sites
/// of A, incomplete notes, limits.</summary>
/// <param name="pAnswer">A complete answer.</param>
procedure WriteHbvAnswer(const pAnswer: THbvAnswer);

/// <summary>The process exit code of an answer.</summary>
/// <param name="pAnswer">A complete answer.</param>
/// <returns>HBV_EXIT_YES for YES, HBV_EXIT_NOT_YES for NO and MAY.</returns>
function HbvExitCode(const pAnswer: THbvAnswer): Integer;

implementation

uses
  System.SysUtils
, System.Classes
, System.IOUtils
, System.JSON
, System.Math
, System.StrUtils
, System.Diagnostics
, System.Generics.Collections
, System.Generics.Defaults
, DRagLint.Core.Interfaces
, DRagLint.Storage.SQLite
, DRagLint.Charts.Index
, DRagLint.Query.HappensBefore.Events
, DRagLint.Query.HappensBefore.Intra
, DRagLint.Query.HappensBefore.Roots
, DRagLint.Query.HappensBefore.Handlers
, DRagLint.Query.HappensBefore
  ;

const
  VERB_NAME = 'happens-before';
  EVENT_SEP = ':';
  QNAME_SEP = '.';
  NAME_LIST_SEP = ',';
  APP_RUN_ALL = '*';
  KIND_CODES: array[THbvEventKind] of string = ('write', 'read', 'call', 'extcall', 'site', 'extwrite', 'app-run');
  VERDICT_CODES: array[THbvVerdict] of string = ('YES', 'NO', 'MAY');
  REASON_CODES: array[THbvReason] of string = ('a-never-happens', 'b-first', 'a-not-on-every-path',
    'a-in-other-routine', 'a-site-uncertain', 'a-sites-incomplete', 'b-sites-incomplete', 'no-b-site',
    'no-routine-body', 'budget');
  METHOD_CODES: array[THbvMethod] of string = ('', 'same-routine', 'callee', 'callers', 'check-init', 'program-order');
  PRESET_RANDOMIZE = 'randomize';
  PRESET_FORMAT_SETTINGS = 'format-settings';
  PRESET_BEFORE_APP_RUN = 'before-app-run';
  { the RTL routines that format or parse with the global FormatSettings when no settings argument is given }
  FORMAT_SETTINGS_USERS = 'Format,FormatFloat,FormatCurr,FormatDateTime,FloatToStr,FloatToStrF,CurrToStr,CurrToStrF,' +
    'StrToFloat,StrToFloatDef,TryStrToFloat,StrToCurr,StrToCurrDef,TryStrToCurr,DateToStr,TimeToStr,DateTimeToStr,' +
    'StrToDate,StrToDateDef,TryStrToDate,StrToTime,StrToTimeDef,TryStrToTime,StrToDateTime,StrToDateTimeDef,TryStrToDateTime';
  REF_KINDS_EXTCALL = '''call'', ''read''';
  REF_KINDS_EXTWRITE = '''write'', ''write-through''';
  ROOT_KINDS_SQL = '''initialization'', ''finalization'', ''program'', ''library''';
  SECTION_KINDS_SQL = '''initialization'', ''finalization''';
  ORDER_WHY_PREFIX = 'why not SET: ';
  CHECK_INIT_LIMIT = 'check-init: ';
  PRESET_NAMES: array[0..2] of string = (PRESET_RANDOMIZE, PRESET_FORMAT_SETTINGS, PRESET_BEFORE_APP_RUN);
  EVENT_KINDS_HELP = 'write:<QName>, read:<QName>, call:<QName>, extcall:<Name>[,<Name>...], extwrite:<Name>[,<Name>...], ' +
    'site:<file>:<line>[:<col>], app-run:<program>|*';
  ROUTINE_KINDS_SQL = '''procedure'', ''function'', ''method'', ''constructor'', ''destructor''';
  { a routine declared in the interface carries its body in impl_*_line; one that lives only in the
    implementation carries it in start_line / end_line (impl_* = 0 or NULL) }
  SQL_BODY_FIRST = '(CASE WHEN COALESCE(s.impl_start_line, 0) > 0 THEN s.impl_start_line ELSE s.start_line END)';
  SQL_BODY_LAST = '(CASE WHEN COALESCE(s.impl_end_line, 0) > 0 THEN s.impl_end_line ELSE s.end_line END)';
  KIND_FUNCTION = 'function';
  KIND_METHOD = 'method';
  CONF_CERTAIN = 'certain';
  REF_CALL = 'call';
  SQL_IS_BASE = 'SELECT 1 AS x FROM dispatch_edges WHERE base_symbol_id = %d LIMIT 1';
  SQL_IN_DISPATCH = 'SELECT 1 AS x FROM dispatch_edges WHERE base_symbol_id = %d OR impl_symbol_id = %d LIMIT 1';
  SQL_EDGE_SITES = 'SELECT c.target_symbol_id AS callee, COALESCE(r.enclosing_symbol_id, 0) AS caller, f.path, ' +
    'r.start_line, r.start_col, r.kind AS rk, c.confidence, s.kind AS sk, COALESCE(s.signature, '''') AS sig ' +
    'FROM refs r JOIN call_edges c ON c.ref_id = r.id JOIN files f ON f.id = r.file_id ' +
    'JOIN symbols s ON s.id = c.target_symbol_id WHERE %s ORDER BY f.path, r.start_line, r.start_col, r.id';

type
  { One resolved call edge: where the call is, what it calls, and whether it is a real, certain call. }
  TEdgeSite = record
    Site: THbSite;
    CalleeId: Int64;
    IsCall: Boolean;
    Certain: Boolean;
    Confidence: string;
  end;

  { The marks of one event (A for the YES proof, B for the b-first proof) and what was derived from them. }
  TMarkSide = class
  strict private
    FDirect: TDictionary<Int64, TArray<THbSite>>;
    FReach: THashSet<Int64>;
    FReachBuilt: Boolean;
    FMust: TDictionary<Int64, Boolean>;
    FMustBusy: THashSet<Int64>;
    FEntryBusy: THashSet<Int64>;
  public
    constructor Create(const pEvent: THbvEvent);
    destructor Destroy; override;
    { definite sites by routine }
    property Direct: TDictionary<Int64, TArray<THbSite>> read FDirect;
    { routines that hold a mark or reach one over certain calls; filled by TEngine.BuildReach }
    property Reach: THashSet<Int64> read FReach;
    property ReachBuilt: Boolean read FReachBuilt write FReachBuilt;
    { memo of TEngine.MustExit, and the routines being solved / whose callers are being judged }
    property Must: TDictionary<Int64, Boolean> read FMust;
    property MustBusy: THashSet<Int64> read FMustBusy;
    property EntryBusy: THashSet<Int64> read FEntryBusy;
  end;

  TEngine = class  // dl:ok high-response@8aca -- REVIEWED 2026-11-27 v156 HB4: one engine per question -- event resolution (4 kinds) plus the three site proofs share its index, store, classifier and budget; its RFC is the store and solver calls those need, splitting it would only pass the same six caches around
  strict private
    FIndex: TChartsIndex;
    FStore: ISymbolStore;
    FClassifier: THbEscapeClassifier;
    FMaxRoutines: Integer;
    FSolved: Integer;
    FExhausted: Boolean;
    FVarEvents: TDictionary<string, THbEvents>;
    FNames: TDictionary<Int64, string>;
    FSource: TDictionary<string, TArray<string>>;
    FCallsIn: TDictionary<Int64, TArray<TEdgeSite>>;
    FPossible: THashSet<Int64>;
    FPreConclusive: Boolean;
    FHasIndirect: Boolean;
    function Walk(const pSeeds: TArray<Int64>; pUp: Boolean; const pRoots, pInto: THashSet<Int64>): Boolean;
    function Id64(const pRow: TIndexRow; const pCol: string): Int64;
    function RoutineName(pId: Int64): string;
    function SourceLine(const pFile: string; pLine: Integer): string;
    function VarEvents(const pName: string): THbEvents;
    function EdgeSites(const pWhere: string): TArray<TEdgeSite>;
    function CallsIn(pRoutineId: Int64): TArray<TEdgeSite>;
    function HasDispatch(pRoutineId: Int64; pAsBaseOnly: Boolean): Boolean;
    function Spend: Boolean;
    procedure AddSite(var pEvent: THbvEvent; const pSite: THbSite; pDefinite: Boolean; const pWhy: string);
    procedure ResolveVar(var pEvent: THbvEvent);
    procedure ResolveCall(var pEvent: THbvEvent);
    procedure ResolveUnresolved(var pEvent: THbvEvent; const pRefKinds: string);
    procedure ResolveAppRun(var pEvent: THbvEvent);
    procedure ResolveSite(var pEvent: THbvEvent);
    procedure BuildReach(pSide: TMarkSide);
    function AllMarks(pSide: TMarkSide; pRoutineId: Int64): TArray<THbSite>;
    function MustExit(pSide: TMarkSide; pRoutineId: Int64): Boolean;
    function StateAt(const pMarks: TArray<THbSite>; const pSite: THbSite; out pNoBody: Boolean): Boolean;
    function CallersProve(pSide: TMarkSide; pRoutineId: Int64; pDepth: Integer): Boolean;
  public
    constructor Create(const pIndex: TChartsIndex; const pStore: ISymbolStore; pMaxRoutines: Integer);
    destructor Destroy; override;
    function Resolve(const pSpec, pFlag: string): THbvEvent;
    function Dominated(pSide: TMarkSide; const pSite: THbSite; pDepth: Integer; out pMethod: THbvMethod;
      out pNoBody: Boolean): Boolean;
    { the call-graph pre-check: which routines a proof of "A first" can reach at all (unit header) }
    procedure PreCheck(const pA, pB: THbvEvent);
    { True when the pre-check is conclusive and says no proof can reach a site in pRoutineId }
    function PreRefuted(pRoutineId: Int64): Boolean;
    { adds the routine bodies another solver spent on this question }
    procedure Charge(pRoutines: Integer; pExhausted: Boolean);
    property MaxRoutines: Integer read FMaxRoutines;
    property Solved: Integer read FSolved;
    property Exhausted: Boolean read FExhausted;
  end;

function HbvPresetNames: TArray<string>;
begin
  Result:= nil;
  for var N in PRESET_NAMES do Result:= Result + [N];
end;

function HbvPresetEvents(const pPreset: string; out pA, pB: string): Boolean;
begin
  pA:= '';
  pB:= '';
  Result:= True;
  if SameText(pPreset, PRESET_RANDOMIZE) then
  begin
    pA:= KIND_CODES[hekExtCall] + EVENT_SEP + 'Randomize';
    pB:= KIND_CODES[hekExtCall] + EVENT_SEP + 'Random';
  end
  else if SameText(pPreset, PRESET_FORMAT_SETTINGS) then
  begin
    pA:= KIND_CODES[hekExtWrite] + EVENT_SEP + 'FormatSettings';
    pB:= KIND_CODES[hekExtCall] + EVENT_SEP + FORMAT_SETTINGS_USERS;
  end
  else if SameText(pPreset, PRESET_BEFORE_APP_RUN) then
    pB:= KIND_CODES[hekAppRun] + EVENT_SEP + APP_RUN_ALL
  else
    Result:= False;
end;

function HbvExitCode(const pAnswer: THbvAnswer): Integer;
begin
  Result:= if pAnswer.Verdict = hbvYes then HBV_EXIT_YES else HBV_EXIT_NOT_YES;
end;

function SiteText(const pSite: THbSite): string;
begin
  Result:= Format('%s:%d', [ExtractFileName(pSite.FileName), pSite.Line]);
  if pSite.Col > 0 then Result:= Result + EVENT_SEP + IntToStr(pSite.Col);
end;

function SiteLess(const pLeft, pRight: THbSite): Integer;
begin
  Result:= CompareText(pLeft.FileName, pRight.FileName);
  if Result = 0 then Result:= CompareValue(pLeft.Line, pRight.Line);
  if Result = 0 then Result:= CompareValue(pLeft.Col, pRight.Col);
end;

{ TMarkSide }

constructor TMarkSide.Create(const pEvent: THbvEvent);
begin
  inherited Create;
  FDirect:= TDictionary<Int64, TArray<THbSite>>.Create;
  FReach:= THashSet<Int64>.Create;
  FMust:= TDictionary<Int64, Boolean>.Create;
  FMustBusy:= THashSet<Int64>.Create;
  FEntryBusy:= THashSet<Int64>.Create;
  { only a DEFINITE site is a mark: an uncertain one proves nothing }
  for var S in pEvent.Sites do
    if S.Definite and (S.Site.RoutineId <> 0) then
    begin
      var Have: TArray<THbSite>:= nil;
      FDirect.TryGetValue(S.Site.RoutineId, Have);
      FDirect.AddOrSetValue(S.Site.RoutineId, Have + [S.Site]);
    end;
end;

destructor TMarkSide.Destroy;
begin
  FEntryBusy.Free;
  FMustBusy.Free;
  FMust.Free;
  FReach.Free;
  FDirect.Free;
  inherited;
end;

{ TEngine }

constructor TEngine.Create(const pIndex: TChartsIndex; const pStore: ISymbolStore; pMaxRoutines: Integer);
begin
  inherited Create;
  FIndex:= pIndex;
  FStore:= pStore;
  FMaxRoutines:= pMaxRoutines;
  FClassifier:= THbEscapeClassifier.Create(pStore);
  FVarEvents:= TDictionary<string, THbEvents>.Create;
  FNames:= TDictionary<Int64, string>.Create;
  FSource:= TDictionary<string, TArray<string>>.Create;
  FCallsIn:= TDictionary<Int64, TArray<TEdgeSite>>.Create;
  FPossible:= THashSet<Int64>.Create;
end;

destructor TEngine.Destroy;
begin
  FPossible.Free;
  FCallsIn.Free;
  FSource.Free;
  FNames.Free;
  FVarEvents.Free;
  FClassifier.Free;
  inherited;
end;

function TEngine.Id64(const pRow: TIndexRow; const pCol: string): Int64;
begin
  Result:= StrToInt64Def(pRow.S(pCol), 0);
end;

function TEngine.RoutineName(pId: Int64): string;
begin
  if pId = 0 then Exit('');
  if FNames.TryGetValue(pId, Result) then Exit;
  Result:= '';
  var R:= FIndex.Query(Format('SELECT qualified_name FROM symbols WHERE id = %d', [pId]));
  try
    if R.Count > 0 then Result:= R[0].S('qualified_name');
  finally
    R.Free;
  end;
  FNames.Add(pId, Result);
end;

function TEngine.SourceLine(const pFile: string; pLine: Integer): string;
begin
  var Lines: TArray<string>:= nil;
  if not FSource.TryGetValue(pFile, Lines) then
  begin
    try
      Lines:= TFile.ReadAllLines(pFile);
    except
      on E: Exception do Lines:= nil; { the source moved since the index was written: no excerpt }
    end;
    FSource.Add(pFile, Lines);
  end;
  Result:= if InRange(pLine, 1, Length(Lines)) then Lines[pLine - 1].Trim else '';
end;

function TEngine.VarEvents(const pName: string): THbEvents;
begin
  var Key:= LowerCase(pName);
  if FVarEvents.TryGetValue(Key, Result) then Exit;
  Result:= CollectEvents(FIndex, pName, Default(THbSite));
  FVarEvents.Add(Key, Result);
end;

function TEngine.EdgeSites(const pWhere: string): TArray<TEdgeSite>;
begin
  Result:= nil;
  var R:= FIndex.Query(Format(SQL_EDGE_SITES, [pWhere]));
  try
    for var Row in R do
    begin
      var E:= Default(TEdgeSite);
      E.Site.FileName:= Row.S('path');
      E.Site.Line:= Row.I('start_line');
      E.Site.Col:= Row.I('start_col');
      E.Site.RoutineId:= Id64(Row, 'caller');
      E.Site.Routine:= RoutineName(E.Site.RoutineId);
      E.CalleeId:= Id64(Row, 'callee');
      E.Confidence:= Row.S('confidence');
      var Sig:= Row.S('sig');
      { the solver's rule: a non-call ref is a call only when the callee is a function (a
        parameterless function named in an expression); a procedure there is a value }
      var IsFunction:= (Row.S('sk') = KIND_FUNCTION) or
        ((Row.S('sk') = KIND_METHOD) and Copy(Sig, LastDelimiter(')', Sig) + 1, MaxInt).Contains(EVENT_SEP));
      E.IsCall:= (Row.S('rk') = REF_CALL) or IsFunction;
      E.Certain:= E.IsCall and (E.Confidence = CONF_CERTAIN);
      Result:= Result + [E];
    end;
  finally
    R.Free;
  end;
end;

function TEngine.CallsIn(pRoutineId: Int64): TArray<TEdgeSite>;
begin
  if FCallsIn.TryGetValue(pRoutineId, Result) then Exit;
  Result:= EdgeSites(Format('r.enclosing_symbol_id = %d', [pRoutineId]));
  FCallsIn.Add(pRoutineId, Result);
end;

function TEngine.HasDispatch(pRoutineId: Int64; pAsBaseOnly: Boolean): Boolean;
begin
  var R:= FIndex.Query(Format(if pAsBaseOnly then SQL_IS_BASE else SQL_IN_DISPATCH, [pRoutineId, pRoutineId]));
  try
    Result:= R.Count > 0;
  finally
    R.Free;
  end;
end;

function TEngine.Spend: Boolean;
begin
  Result:= (FSolved < FMaxRoutines) and not HbTimeUp;
  if Result then Inc(FSolved)
  else FExhausted:= True;
end;

procedure TEngine.AddSite(var pEvent: THbvEvent; const pSite: THbSite; pDefinite: Boolean; const pWhy: string);
begin
  var S:= Default(THbvSite);
  S.Site:= pSite;
  if S.Site.Routine = '' then S.Site.Routine:= RoutineName(S.Site.RoutineId);
  S.Definite:= pDefinite;
  if not pDefinite then S.Note:= SourceLine(pSite.FileName, pSite.Line) + ' -- ' + pWhy;
  pEvent.Sites:= pEvent.Sites + [S];
end;

procedure TEngine.ResolveVar(var pEvent: THbvEvent);
const
  WHY: array[THbWriterHow] of string = ('', '', 'a var argument: whether the callee writes it on every path is not known',
    'an out argument: whether the callee writes it on every path is not known', '', '',
    'passed to a callee the index cannot resolve: whether it writes is not known',
    'inside a with: the receiver is not known', '');
begin
  var Ev:= VarEvents(pEvent.Name);
  pEvent.Name:= Ev.Target.QName;
  pEvent.InstanceField:= Ev.Target.Kind = htkInstanceField;
  if Ev.IsPublished then
    pEvent.IncompleteWhy:= pEvent.IncompleteWhy + ['the target is published: RTTI and DFM streaming can reach it'];
  if Ev.AbsoluteOverlay then
    pEvent.IncompleteWhy:= pEvent.IncompleteWhy + ['another variable overlays it (absolute)'];
  for var W in Ev.Writers do
    case W.How of
      hwAddressOf:
        pEvent.IncompleteWhy:= pEvent.IncompleteWhy + ['its address is taken at ' + SiteText(W.Site)];
      hwDfmStream:
        if pEvent.Kind = hekWrite then
          pEvent.IncompleteWhy:= pEvent.IncompleteWhy + ['DFM streaming writes it (no source site)'];
      else
        if pEvent.Kind = hekWrite then
          AddSite(pEvent, W.Site, W.How in [hwAssign, hwAssignNil, hwCreateInto], WHY[W.How]);
    end;
  if pEvent.Kind = hekRead then
    for var U in Ev.UseSites do AddSite(pEvent, U.Site, True, '');
end;

procedure TEngine.ResolveCall(var pEvent: THbvEvent);
begin
  var Want:= pEvent.Name;
  var Last:= Want.Substring(Want.LastIndexOf(QNAME_SEP) + 1);
  var Ids: TArray<Int64>:= nil;
  var Names: TArray<string>:= nil;
  var Cands: TArray<string>:= nil;
  var R:= FIndex.Query(Format('SELECT s.id, s.qualified_name, f.path, s.start_line FROM symbols s ' +
    'JOIN files f ON f.id = s.file_id WHERE s.kind IN (%s) AND lower(s.name) = ''%s'' ORDER BY s.qualified_name, s.id',
    [ROUTINE_KINDS_SQL, TChartsIndex.SqlText(LowerCase(Last))]));
  try
    for var Row in R do
    begin
      var Q:= Row.S('qualified_name');
      if not (SameText(Q, Want) or EndsText(QNAME_SEP + Want, Q)) then Continue;
      Ids:= Ids + [Id64(Row, 'id')];
      if IndexText(Q, Names) >= 0 then Continue;
      Names:= Names + [Q];
      Cands:= Cands + [Format('%s  (%s:%d)', [Q, ExtractFileName(Row.S('path')), Row.I('start_line')])];
    end;
  finally
    R.Free;
  end;
  if Names = nil then
    raise EHbUsage.Create(Format('no routine "%s" in the index. For a routine the index does not hold ' +
      '(RTL, a library) use %s:%s', [Want, KIND_CODES[hekExtCall], Last]));
  if Length(Names) > 1 then
    raise EHbUsage.CreateCandidates(Format('routine "%s" is ambiguous: qualify it', [Want]), Cands);
  pEvent.Name:= Names[0];
  var IdList:= '';
  for var Id in Ids do
  begin
    IdList:= IdList + IfThen(IdList <> '', ', ') + IntToStr(Id);
    var Esc:= FClassifier.ClassOf(Id);
    if Esc not in [hecNone, hecZeroCallers] then
      pEvent.IncompleteWhy:= pEvent.IncompleteWhy + [Format('%s can run without a call the index sees (%s)',
        [Names[0], EscapeClassCode(Esc)])];
    if HasDispatch(Id, {pAsBaseOnly=}False) then
      pEvent.IncompleteWhy:= pEvent.IncompleteWhy + [Names[0] + ' takes part in virtual / interface dispatch: ' +
        'a call through the base is not one of its sites'];
  end;
  for var E in EdgeSites('c.target_symbol_id IN (' + IdList + ')') do
    if not E.IsCall then
      pEvent.IncompleteWhy:= pEvent.IncompleteWhy + ['it is named as a value at ' + SiteText(E.Site)]
    else
      AddSite(pEvent, E.Site, E.Certain, 'the index resolved this call with confidence ' + E.Confidence);
end;

procedure TEngine.ResolveUnresolved(var pEvent: THbvEvent; const pRefKinds: string);
begin
  var Names: TArray<string>:= nil;
  var InList:= '';
  for var Part in pEvent.Name.Split([NAME_LIST_SEP]) do
  begin
    var N:= Part.Trim;
    if N.Contains(QNAME_SEP) then N:= N.Substring(N.LastIndexOf(QNAME_SEP) + 1);
    if (N = '') or (IndexText(N, Names) >= 0) then Continue;
    Names:= Names + [N];
    InList:= InList + IfThen(InList <> '', ', ') + '''' + TChartsIndex.SqlText(LowerCase(N)) + '''';
  end;
  if Names = nil then
    raise EHbUsage.Create(Format('%s%s needs a name, or names separated by "%s"', [KIND_CODES[pEvent.Kind], EVENT_SEP, NAME_LIST_SEP]));
  pEvent.Name:= string.Join(NAME_LIST_SEP, Names);
  var R:= FIndex.Query(Format('SELECT f.path, r.start_line, r.start_col, COALESCE(r.enclosing_symbol_id, 0) AS caller ' +
    'FROM refs r JOIN files f ON f.id = r.file_id WHERE r.symbol_id IS NULL AND r.kind IN (%s) ' +
    'AND lower(r.name_text) IN (%s) ORDER BY f.path, r.start_line, r.start_col, r.id', [pRefKinds, InList]));
  try
    for var Row in R do
    begin
      var S:= Default(THbSite);
      S.FileName:= Row.S('path');
      S.Line:= Row.I('start_line');
      S.Col:= Row.I('start_col');
      S.RoutineId:= Id64(Row, 'caller');
      AddSite(pEvent, S, True, '');
    end;
  finally
    R.Free;
  end;
end;

procedure TEngine.ResolveAppRun(var pEvent: THbvEvent);
begin
  var Every:= pEvent.Name = APP_RUN_ALL;
  var Known:= Every;
  var Orderer:= THbHandlerOrderer.Create(FIndex);
  try
    var R:= FIndex.Query('SELECT id, name FROM symbols WHERE kind IN (''program'', ''library'') ORDER BY name, id');
    try
      for var Row in R do
      begin
        if not (Every or SameText(Row.S('name'), pEvent.Name)) then Continue;
        Known:= True;
        var S: THbSite;
        if Orderer.RunSiteOf(Id64(Row, 'id'), S) then
        begin
          { the program block is no routine body: the program-order solve places the site }
          S.RoutineId:= 0;
          S.Routine:= '';
          AddSite(pEvent, S, True, '');
        end;
      end;
    finally
      R.Free;
    end;
  finally
    Orderer.Free;
  end;
  if not Known then
    raise EHbUsage.Create(Format('no program "%s" in the index. %s%s%s names every program', [pEvent.Name,
      KIND_CODES[hekAppRun], EVENT_SEP, APP_RUN_ALL]));
end;

procedure TEngine.ResolveSite(var pEvent: THbvEvent);
begin
  var At:= Default(THbSite);
  if not HbParseAt(pEvent.Name, At) then
    raise EHbUsage.Create(Format('%s%s needs <file>:<line>[:<col>] with line and col >= 1, got "%s"',
      [KIND_CODES[hekSite], EVENT_SEP, pEvent.Name]));
  var Want:= At.FileName.Replace('/', PathDelim);
  var FileId: Int64:= 0;
  var Paths: TArray<string>:= nil;
  var R:= FIndex.Query('SELECT id, path FROM files ORDER BY path');
  try
    for var Row in R do
    begin
      var P:= Row.S('path');
      if not (SameText(P, Want) or EndsText(PathDelim + Want, P)) then Continue;
      FileId:= Id64(Row, 'id');
      Paths:= Paths + [P];
    end;
  finally
    R.Free;
  end;
  if Paths = nil then raise EHbUsage.Create(Format('no file "%s" in the index', [At.FileName]));
  if Length(Paths) > 1 then
    raise EHbUsage.CreateCandidates(Format('file "%s" is ambiguous: give more of its path', [At.FileName]), Paths);
  At.FileName:= Paths[0];
  { the innermost routine whose body holds the line; none = program block, section or unit level }
  R:= FIndex.Query(Format('SELECT s.id FROM symbols s WHERE s.file_id = %d AND s.kind IN (%s) AND %s <= %d AND %s >= %d ' +
    'ORDER BY %s DESC, s.id LIMIT 1',
    [FileId, ROUTINE_KINDS_SQL, SQL_BODY_FIRST, At.Line, SQL_BODY_LAST, At.Line, SQL_BODY_FIRST]));
  try
    if R.Count > 0 then At.RoutineId:= Id64(R[0], 'id');
  finally
    R.Free;
  end;
  if At.RoutineId = 0 then
  begin
    { a section is no routine body, but the program-order solve places a site by its section symbol }
    R:= FIndex.Query(Format('SELECT s.id FROM symbols s WHERE s.file_id = %d AND s.kind IN (%s) AND s.start_line <= %d ' +
      'AND s.end_line >= %d ORDER BY s.start_line DESC, s.id LIMIT 1', [FileId, SECTION_KINDS_SQL, At.Line, At.Line]));
    try
      if R.Count > 0 then At.RoutineId:= Id64(R[0], 'id');
    finally
      R.Free;
    end;
  end;
  AddSite(pEvent, At, True, '');
end;

function TEngine.Resolve(const pSpec, pFlag: string): THbvEvent;
begin
  Result:= Default(THbvEvent);
  var Cut:= pSpec.IndexOf(EVENT_SEP);
  var KindIx:= if Cut > 0 then IndexText(pSpec.Substring(0, Cut), KIND_CODES) else -1;
  Result.Name:= pSpec.Substring(Cut + 1).Trim;
  if (KindIx < 0) or (Result.Name = '') then
    raise EHbUsage.Create(Format('%s needs an event, got "%s". Events: %s', [pFlag, pSpec, EVENT_KINDS_HELP]));
  Result.Kind:= THbvEventKind(KindIx);
  case Result.Kind of
    hekWrite, hekRead: ResolveVar(Result);
    hekCall: ResolveCall(Result);
    hekExtCall: ResolveUnresolved(Result, REF_KINDS_EXTCALL);
    hekExtWrite: ResolveUnresolved(Result, REF_KINDS_EXTWRITE);
    hekSite: ResolveSite(Result);
    hekAppRun: ResolveAppRun(Result);
  end;
  Result.Complete:= Result.IncompleteWhy = nil;
  Result.Spec:= KIND_CODES[Result.Kind] + EVENT_SEP + Result.Name;
  TArray.Sort<THbvSite>(Result.Sites, TComparer<THbvSite>.Construct(
    function(const pLeft, pRight: THbvSite): Integer
    begin
      Result:= SiteLess(pLeft.Site, pRight.Site);
    end));
end;

{ One walk of the pre-check over the call graph (calls of every confidence, dispatch edges, indirect
  edges), from pSeeds into pInto: callers when pUp, callees when not. False = stand down: the walk met
  a caller the index cannot place or (pUp) an ordered root, passed the node cap, or ran out of time. }
function TEngine.Walk(const pSeeds: TArray<Int64>; pUp: Boolean; const pRoots, pInto: THashSet<Int64>): Boolean;
const
  SQL_UP = 'SELECT DISTINCT COALESCE(r.enclosing_symbol_id, 0) AS x FROM refs r JOIN call_edges c ON c.ref_id = r.id ' +
    'WHERE c.target_symbol_id = %0:d UNION SELECT base_symbol_id FROM dispatch_edges WHERE impl_symbol_id = %0:d';
  SQL_UP_INDIRECT = ' UNION SELECT COALESCE(r.enclosing_symbol_id, 0) FROM indirect_edges e LEFT JOIN refs r ' +
    'ON r.id = e.ref_id WHERE e.target_symbol_id = %0:d';
  SQL_DOWN = 'SELECT DISTINCT c.target_symbol_id AS x FROM refs r JOIN call_edges c ON c.ref_id = r.id ' +
    'WHERE r.enclosing_symbol_id = %0:d UNION SELECT impl_symbol_id FROM dispatch_edges WHERE base_symbol_id = %0:d';
  SQL_DOWN_INDIRECT = ' UNION SELECT e.target_symbol_id FROM indirect_edges e JOIN refs r ON r.id = e.ref_id ' +
    'WHERE r.enclosing_symbol_id = %0:d';
begin
  Result:= False;
  var Sql:= if pUp then SQL_UP + IfThen(FHasIndirect, SQL_UP_INDIRECT) else SQL_DOWN + IfThen(FHasIndirect, SQL_DOWN_INDIRECT);
  var Queue:= TQueue<Int64>.Create;
  try
    for var Id in pSeeds do
      if pInto.Add(Id) then Queue.Enqueue(Id);
    while Queue.Count > 0 do
    begin
      if (pInto.Count > HBV_PRECHECK_MAX_NODES) or HbTimeUp then Exit;
      var R:= FIndex.Query(Format(Sql + ' ORDER BY 1', [Queue.Dequeue]));
      try
        for var Row in R do
        begin
          var X:= Id64(Row, 'x');
          if pUp and ((X = 0) or pRoots.Contains(X)) then Exit;
          if (X <> 0) and pInto.Add(X) then Queue.Enqueue(X);
        end;
      finally
        R.Free;
      end;
    end;
  finally
    Queue.Free;
  end;
  Result:= True;
end;

procedure TEngine.PreCheck(const pA, pB: THbvEvent);
begin
  FPreConclusive:= False;
  FPossible.Clear;
  { write:T / read:T: check-init's constructor model orders sites no call path connects }
  if (pA.Kind = hekWrite) and (pB.Kind = hekRead) and SameText(pA.Name, pB.Name) then Exit;
  var Roots:= THashSet<Int64>.Create;
  try
    var R:= FIndex.Query('SELECT COUNT(*) AS n FROM sqlite_master WHERE type = ''table'' AND name = ''indirect_edges''');
    try
      FHasIndirect:= (R.Count > 0) and (R[0].I('n') > 0);
    finally
      R.Free;
    end;
    R:= FIndex.Query(Format('SELECT id FROM symbols WHERE kind IN (%s) ORDER BY id', [ROOT_KINDS_SQL]));
    try
      for var Row in R do Roots.Add(Id64(Row, 'id'));
    finally
      R.Free;
    end;
    { every site of A seeds the walk, the uncertain ones too: the pre-check only ever says "unprovable" }
    var Seeds: TArray<Int64>:= nil;
    for var S in pA.Sites do
    begin
      if (S.Site.RoutineId = 0) or Roots.Contains(S.Site.RoutineId) then Exit;
      Seeds:= Seeds + [S.Site.RoutineId];
    end;
    if Seeds = nil then Exit;
    var Up:= THashSet<Int64>.Create;
    try
      if not Walk(Seeds, {pUp=}True, Roots, Up) then Exit;
      var UpIds:= Up.ToArray;
      TArray.Sort<Int64>(UpIds);
      FPreConclusive:= Walk(UpIds, {pUp=}False, Roots, FPossible);
    finally
      Up.Free;
    end;
  finally
    Roots.Free;
  end;
end;

function TEngine.PreRefuted(pRoutineId: Int64): Boolean;
begin
  Result:= FPreConclusive and (pRoutineId <> 0) and not FPossible.Contains(pRoutineId);
end;

procedure TEngine.Charge(pRoutines: Integer; pExhausted: Boolean);
begin
  Inc(FSolved, pRoutines);
  FExhausted:= FExhausted or pExhausted;
end;

procedure TEngine.BuildReach(pSide: TMarkSide);
begin
  if pSide.ReachBuilt then Exit;
  pSide.ReachBuilt:= True;
  { the routines that hold a mark, and everything that reaches one backwards over certain calls:
    only those can perform the event on every return }
  var Queue:= TQueue<Int64>.Create;
  try
    var Seeds:= pSide.Direct.Keys.ToArray;
    TArray.Sort<Int64>(Seeds);
    for var Id in Seeds do
    begin
      pSide.Reach.Add(Id);
      Queue.Enqueue(Id);
    end;
    while Queue.Count > 0 do
    begin
      if pSide.Reach.Count > FMaxRoutines then
      begin
        FExhausted:= True;
        Break;
      end;
      var R:= FIndex.Query(Format('SELECT DISTINCT COALESCE(r.enclosing_symbol_id, 0) AS caller FROM refs r ' +
        'JOIN call_edges c ON c.ref_id = r.id WHERE c.target_symbol_id = %d AND c.confidence = ''%s'' ORDER BY 1',
        [Queue.Dequeue, CONF_CERTAIN]));
      try
        for var Row in R do
        begin
          var Caller:= Id64(Row, 'caller');
          if (Caller <> 0) and pSide.Reach.Add(Caller) then Queue.Enqueue(Caller);
        end;
      finally
        R.Free;
      end;
    end;
  finally
    Queue.Free;
  end;
end;

function TEngine.AllMarks(pSide: TMarkSide; pRoutineId: Int64): TArray<THbSite>;
begin
  Result:= nil;
  pSide.Direct.TryGetValue(pRoutineId, Result);
  BuildReach(pSide);
  { a certain call of a routine that performs the event on every normal return is a mark; a callee
    with an override is not (which body runs is not known) }
  for var C in CallsIn(pRoutineId) do
    if C.Certain and pSide.Reach.Contains(C.CalleeId) and not HasDispatch(C.CalleeId, {pAsBaseOnly=}True)
      and MustExit(pSide, C.CalleeId) then
      Result:= Result + [C.Site];
end;

function TEngine.MustExit(pSide: TMarkSide; pRoutineId: Int64): Boolean;
begin
  if pSide.Must.TryGetValue(pRoutineId, Result) then Exit;
  { a routine on its own call path proves nothing (least fixpoint: False) }
  if pSide.MustBusy.Contains(pRoutineId) or not Spend then Exit(False);
  pSide.MustBusy.Add(pRoutineId);
  try
    var St:= SolveRoutine(FStore, pRoutineId, AllMarks(pSide, pRoutineId), nil, {pEntryDone=}False);
    Result:= St.Found and not St.CfgSkipped and St.ExitReachable and St.ExitDone;
  finally
    pSide.MustBusy.Remove(pRoutineId);
  end;
  pSide.Must.AddOrSetValue(pRoutineId, Result);
end;

function TEngine.StateAt(const pMarks: TArray<THbSite>; const pSite: THbSite; out pNoBody: Boolean): Boolean;
begin
  var St:= SolveRoutine(FStore, pSite.RoutineId, pMarks, [pSite], {pEntryDone=}False);
  pNoBody:= not St.Found or St.CfgSkipped or (Length(St.Queries) = 0) or not St.Queries[0].Located
    or St.Queries[0].InClosure;
  Result:= not pNoBody and St.Queries[0].Done;
end;

function TEngine.CallersProve(pSide: TMarkSide; pRoutineId: Int64; pDepth: Integer): Boolean;
var
  Method: THbvMethod;
  NoBody: Boolean;
begin
  Result:= False;
  { only a routine that runs through resolved, certain calls and nothing else has a provable entry }
  if pSide.EntryBusy.Contains(pRoutineId) or (FClassifier.ClassOf(pRoutineId) <> hecNone)
    or HasDispatch(pRoutineId, {pAsBaseOnly=}False) then Exit;
  var Sites:= EdgeSites(Format('c.target_symbol_id = %d', [pRoutineId]));
  if Sites = nil then Exit;
  pSide.EntryBusy.Add(pRoutineId);
  try
    for var S in Sites do
      if not S.Certain or not Dominated(pSide, S.Site, pDepth, Method, NoBody) then Exit;
    Result:= True;
  finally
    pSide.EntryBusy.Remove(pRoutineId);
  end;
end;

function TEngine.Dominated(pSide: TMarkSide; const pSite: THbSite; pDepth: Integer; out pMethod: THbvMethod;
  out pNoBody: Boolean): Boolean;
begin
  pMethod:= hvmNone;
  pNoBody:= pSite.RoutineId = 0;
  if pNoBody or not Spend then Exit(False);
  var Marks: TArray<THbSite>:= nil;
  pSide.Direct.TryGetValue(pSite.RoutineId, Marks);
  Result:= StateAt(Marks, pSite, pNoBody);
  if Result then pMethod:= hvmSameRoutine;
  if Result or pNoBody then Exit;
  var More:= AllMarks(pSide, pSite.RoutineId);
  if Length(More) > Length(Marks) then
  begin
    Result:= StateAt(More, pSite, pNoBody);
    if Result then pMethod:= hvmCallee;
  end;
  if not Result and (pDepth < HBV_MAX_CALLER_DEPTH) and CallersProve(pSide, pSite.RoutineId, pDepth + 1) then
  begin
    Result:= True;
    pMethod:= hvmCallers;
  end;
end;

{ ---- the question ---- }

procedure AddReason(var pAnswer: THbvAnswer; pReason: THbvReason);
begin
  if not TArray.Contains<THbvReason>(pAnswer.Reasons, pReason) then
  begin
    pAnswer.Reasons:= pAnswer.Reasons + [pReason];
    TArray.Sort<THbvReason>(pAnswer.Reasons);
  end;
end;

procedure AddMethod(var pAnswer: THbvAnswer; pMethod: THbvMethod);
begin
  if (pMethod <> hvmNone) and not TArray.Contains<THbvMethod>(pAnswer.Methods, pMethod) then
  begin
    pAnswer.Methods:= pAnswer.Methods + [pMethod];
    TArray.Sort<THbvMethod>(pAnswer.Methods);
  end;
end;

procedure AddLimit(var pAnswer: THbvAnswer; const pLimit: string);
begin
  if IndexStr(pLimit, pAnswer.Limits) < 0 then pAnswer.Limits:= pAnswer.Limits + [pLimit];
end;

{ Why a site of B is not proven to run after A: what A offers in that routine decides the code. }
function WhyNot(const pA: THbvEvent; const pSite: THbSite; pNoBody, pExhausted: Boolean; out pWhy: string): THbvReason;
begin
  var Definite:= 0;
  var Uncertain:= '';
  for var S in pA.Sites do
    if (S.Site.RoutineId = pSite.RoutineId) and (pSite.RoutineId <> 0) then
      if S.Definite then Inc(Definite)
      else if Uncertain = '' then Uncertain:= Format('%s  %s', [SiteText(S.Site), S.Note]);
  if pNoBody then
  begin
    Result:= hvrNoRoutineBody;
    pWhy:= 'the site is in no routine body this verb can solve (program block, initialization section, ' +
      'unit level, anonymous method, or a body with goto / asm)';
  end
  else if pExhausted then
  begin
    Result:= hvrBudget;
    pWhy:= 'the --max-routines budget ran out before the proof was complete';
  end
  else if Definite > 0 then
  begin
    Result:= hvrANotOnEveryPath;
    pWhy:= 'A is in this routine, but not on every path that reaches the site';
  end
  else if Uncertain <> '' then
  begin
    Result:= hvrASiteUncertain;
    pWhy:= 'A may happen at ' + Uncertain;
  end
  else
  begin
    Result:= hvrAInOtherRoutine;
    pWhy:= 'A has no site in this routine, in a callee that always performs it, or before every call of this routine';
  end;
end;

{ Judges every site of pQuery against the marks of pMarks; True when all are proven. }
function JudgeAll(pEngine: TEngine; const pMarks, pQuery: THbvEvent; pSideA: Boolean; var pAnswer: THbvAnswer): Boolean;
begin
  Result:= True;
  var Side:= TMarkSide.Create(pMarks);
  try
    for var S in pQuery.Sites do
    begin
      var Row:= Default(THbvSiteAnswer);
      Row.Site:= S.Site;
      Row.SideA:= pSideA;
      var NoBody:= False;
      Row.PreChecked:= not pSideA and pEngine.PreRefuted(S.Site.RoutineId);
      if not Row.PreChecked then Row.Proven:= pEngine.Dominated(Side, S.Site, 0, Row.Method, NoBody);
      if Row.PreChecked then
      begin
        Row.Reason:= hvrAInOtherRoutine;
        Row.Why:= 'pre-check: no routine that performs A, and no caller of one, reaches this routine (call graph only, no body solved)';
        AddLimit(pAnswer, HBV_LIMIT_PRECHECK);
      end
      else if Row.Proven then
        Row.Why:= Format('%s runs first on every path (%s)', [if pSideA then 'B' else 'A', METHOD_CODES[Row.Method]])
      else if pSideA then
        Row.Why:= 'not proven to run after B'
      else
        Row.Reason:= WhyNot(pMarks, S.Site, NoBody, pEngine.Exhausted, Row.Why);
      Result:= Result and Row.Proven;
      pAnswer.Judged:= pAnswer.Judged + [Row];
    end;
  finally
    Side.Free;
  end;
end;

{ write:T before read:T the site proofs could not decide: the check-init solver knows the ordered roots. }
function CheckInitProves(const pDbPath: string; const pOptions: THbOptions; var pAnswer: THbvAnswer): Boolean;
begin
  Result:= False;
  if (pAnswer.A.Kind <> hekWrite) or (pAnswer.B.Kind <> hekRead) or not SameText(pAnswer.A.Name, pAnswer.B.Name) then Exit;
  var Init:= CheckInit(pDbPath, pAnswer.A.Name, '', pOptions);
  Result:= (Init.Verdict = hvSet) and (Init.JudgedUses <> nil) and (IndexStr(HB_LIMIT_NO_JUDGED_USE, Init.Limits) < 0);
  if not Result then
  begin
    AddLimit(pAnswer, CHECK_INIT_LIMIT + VerdictCode(Init.Verdict));
    Exit;
  end;
  { what check-init leaned on travels with the answer }
  for var L in Init.Limits do AddLimit(pAnswer, CHECK_INIT_LIMIT + L);
  for var I:= 0 to High(pAnswer.Judged) do
    if not pAnswer.Judged[I].SideA and not pAnswer.Judged[I].Proven then
    begin
      pAnswer.Judged[I].Proven:= True;
      pAnswer.Judged[I].Method:= hvmCheckInit;
      pAnswer.Judged[I].Why:= 'check-init answers SET for every use ' + Init.Summary;
    end;
end;

{ Lane HB5: the sites of one side the site proofs left open go to the ordered-root solve, with the
  DEFINITE sites of pMarks as marks. True when every site of that side is proven afterwards. }
function OrderProves(pEngine: TEngine; const pDbPath: string; const pMarks: THbvEvent; pSideA: Boolean;
  var pAnswer: THbvAnswer): Boolean;
const
  RELIED: array[0..1] of THbReason = (hrReliedOnHandlerOrder, hrReliedOnIndirectEdges);
  CONDITIONAL: array[0..2] of THbReason = (hrWriterConditional, hrWriterAfterUseSameRoutine, hrCalleeNotMust);
begin
  var Marks: TArray<THbSite>:= nil;
  for var S in pMarks.Sites do
    if S.Definite then Marks:= Marks + [S.Site];
  var Rows: TArray<Integer>:= nil;
  var Queries: TArray<THbSite>:= nil;
  for var I:= 0 to High(pAnswer.Judged) do
    if (pAnswer.Judged[I].SideA = pSideA) and not pAnswer.Judged[I].Proven and not pAnswer.Judged[I].PreChecked then
    begin
      Rows:= Rows + [I];
      Queries:= Queries + [pAnswer.Judged[I].Site];
    end;
  if (Marks <> nil) and (Queries <> nil) and (Length(Marks) <= HBV_ORDER_MAX_MARKS) and not pEngine.Exhausted then
  begin
    var Solved:= HbOrderSolve(pDbPath, Marks, Queries, pEngine.MaxRoutines);
    pEngine.Charge(Solved.Budget.Routines, Solved.Budget.Exhausted);
    if Length(Solved.JudgedUses) = Length(Rows) then
      for var K:= 0 to High(Rows) do
      begin
        var Use:= Solved.JudgedUses[K];
        var Leans: TArray<THbReason>:= nil;
        for var L in RELIED do
          if TArray.Contains<THbReason>(Use.Reasons, L) then Leans:= Leans + [L];
        if (Use.Verdict = hvSet) and not (pSideA and (Leans <> nil)) then
        begin
          pAnswer.Judged[Rows[K]].Proven:= True;
          pAnswer.Judged[Rows[K]].Method:= hvmProgramOrder;
          pAnswer.Judged[Rows[K]].Why:= Format('%s runs first on every path from every root that reaches the site (%s)',
            [if pSideA then 'B' else 'A', METHOD_CODES[hvmProgramOrder]]);
          for var L in Leans do AddLimit(pAnswer, HBV_LIMIT_PROGRAM_ORDER + ReasonCode(L));
        end
        else if not pSideA and (Use.Verdict <> hvSet) then
        begin
          { the site was placed after all: say what the order solve saw, in the verb's reason codes }
          var NotAlways:= False;
          for var C in CONDITIONAL do NotAlways:= NotAlways or TArray.Contains<THbReason>(Use.Reasons, C);
          if pAnswer.Judged[Rows[K]].Reason = hvrNoRoutineBody then
            pAnswer.Judged[Rows[K]].Reason:= if NotAlways then hvrANotOnEveryPath else hvrAInOtherRoutine;
          pAnswer.Judged[Rows[K]].Why:= Format('%s | %s: %s', [pAnswer.Judged[Rows[K]].Why, METHOD_CODES[hvmProgramOrder],
            Use.Why.Replace(ORDER_WHY_PREFIX, '').Replace('writer', 'site of A').Replace('the use', 'this site')]);
        end;
      end;
  end;
  Result:= True;
  for var J in pAnswer.Judged do
    if (J.SideA = pSideA) and not J.Proven then Exit(False);
end;

procedure Conclude(var pAnswer: THbvAnswer; pVerdict: THbvVerdict; const pSummary: string);
begin
  pAnswer.Verdict:= pVerdict;
  pAnswer.Proven:= pVerdict <> hbvMay;
  pAnswer.Summary:= pSummary;
  for var J in pAnswer.Judged do
    if J.Proven and (J.SideA = (pVerdict = hbvNo)) then AddMethod(pAnswer, J.Method)
    else if not J.Proven and not J.SideA and (pVerdict = hbvMay) then AddReason(pAnswer, J.Reason);
end;

procedure Decide(pEngine: TEngine; const pDbPath: string; const pOptions: THbOptions; var pAnswer: THbvAnswer);
begin
  if pAnswer.B.Sites = nil then
  begin
    AddReason(pAnswer, hvrNoBSite);
    Conclude(pAnswer, hbvMay, '(not proven: B has no site in the index, so there is nothing to judge)');
    Exit;
  end;
  if pAnswer.A.Sites = nil then
  begin
    if pAnswer.A.Complete then
    begin
      AddReason(pAnswer, hvrANeverHappens);
      Conclude(pAnswer, hbvNo, '(proven: A has no site in the index, B has -- A never happens before B)');
    end
    else
    begin
      AddReason(pAnswer, hvrASitesIncomplete);
      Conclude(pAnswer, hbvMay, '(not proven: A has no site in the index, but it can happen where the index holds none)');
    end;
    Exit;
  end;
  pEngine.PreCheck(pAnswer.A, pAnswer.B);
  var AllB:= JudgeAll(pEngine, pAnswer.A, pAnswer.B, {pSideA=}False, pAnswer);
  { NO: every site of a complete A runs after a site of B in its own activation, so the first A of any
    run is preceded by a B that no A preceded. Uncertain sites of A are judged too. }
  { the pre-check's relation is symmetric (a common ancestor of an A routine and a B routine): when it
    refuted EVERY site of B, no site of A can be proven to run after B either, so b-first is not tried }
  var AllRefuted:= True;
  for var J in pAnswer.Judged do AllRefuted:= AllRefuted and J.PreChecked;
  if not AllB and not AllRefuted and pAnswer.A.Complete and (JudgeAll(pEngine, pAnswer.B, pAnswer.A, {pSideA=}True, pAnswer)
    or OrderProves(pEngine, pDbPath, pAnswer.B, {pSideA=}True, pAnswer)) then
  begin
    AddReason(pAnswer, hvrBFirst);
    Conclude(pAnswer, hbvNo, '(proven: every site of A runs after a site of B, so the first B runs with no A before it)');
    Exit;
  end;
  if not AllB then AllB:= CheckInitProves(pDbPath, pOptions, pAnswer);
  if not AllB then AllB:= OrderProves(pEngine, pDbPath, pAnswer.A, {pSideA=}False, pAnswer);
  if AllB and pAnswer.B.Complete then
    Conclude(pAnswer, hbvYes, '(proven: every site of B runs after A)')
  else if AllB then
  begin
    AddReason(pAnswer, hvrBSitesIncomplete);
    Conclude(pAnswer, hbvMay, '(not proven: every known site of B runs after A, but B can also happen where the index holds no site)');
  end
  else
  begin
    if not pAnswer.A.Complete then AddReason(pAnswer, hvrASitesIncomplete);
    Conclude(pAnswer, hbvMay, '(not proven either way)');
  end;
end;

function HappensBefore(const pDbPath, pA, pB: string; const pOptions: THbOptions): THbvAnswer;
begin
  Result:= Default(THbvAnswer);
  var Watch:= TStopwatch.StartNew;
  HbStartClock(if IsZero(pOptions.MaxSeconds) then HB_DEFAULT_MAX_SECONDS else pOptions.MaxSeconds);
  var Index:= TChartsIndex.Create(pDbPath);
  try
    var Store: ISymbolStore:= TSQLiteSymbolStore.Create(pDbPath, {AReadOnly=}True);
    var Engine:= TEngine.Create(Index, Store,
      if pOptions.MaxRoutines > 0 then pOptions.MaxRoutines else HB_DEFAULT_MAX_ROUTINES);
    try
      Result.A:= Engine.Resolve(pA, '--a');
      Result.B:= Engine.Resolve(pB, '--b');
      if (Result.A.Kind in [hekExtCall, hekExtWrite]) or (Result.B.Kind in [hekExtCall, hekExtWrite]) then
        AddLimit(Result, HBV_LIMIT_MATCHED_BY_NAME);
      if Result.A.InstanceField or Result.B.InstanceField then AddLimit(Result, HBV_LIMIT_INSTANCE_INSENSITIVE);
      Decide(Engine, pDbPath, pOptions, Result);
      Result.Routines:= Engine.Solved;
      Result.Exhausted:= Engine.Exhausted;
      if Result.Exhausted then
      begin
        AddLimit(Result, HBV_LIMIT_BUDGET);
        if Result.Verdict = hbvMay then AddReason(Result, hvrBudget);
      end;
    finally
      Engine.Free;
    end;
  finally
    Index.Free;
  end;
  Result.Ms:= Watch.ElapsedMilliseconds;
end;

{ ---- rendering ---- }

function EventJson(const pEvent: THbvEvent): TJSONObject;
begin
  Result:= TJSONObject.Create;
  Result.AddPair('event', pEvent.Spec);
  Result.AddPair('kind', KIND_CODES[pEvent.Kind]);
  Result.AddPair('name', pEvent.Name);
  Result.AddPair('complete', TJSONBool.Create(pEvent.Complete));
  var Why:= TJSONArray.Create;
  for var W in pEvent.IncompleteWhy do Why.Add(W);
  Result.AddPair('incomplete', Why);
  var Sites:= TJSONArray.Create;
  for var S in pEvent.Sites do
  begin
    var O:= TJSONObject.Create;
    O.AddPair('file', S.Site.FileName);
    O.AddPair('line', TJSONNumber.Create(S.Site.Line));
    O.AddPair('col', TJSONNumber.Create(S.Site.Col));
    O.AddPair('routine', S.Site.Routine);
    O.AddPair('definite', TJSONBool.Create(S.Definite));
    O.AddPair('note', S.Note);
    Sites.Add(O);
  end;
  Result.AddPair('sites', Sites);
end;

function HbvAnswerJson(const pAnswer: THbvAnswer): string;
begin
  var Root:= TJSONObject.Create;
  try
    Root.AddPair('verb', VERB_NAME);
    if pAnswer.Preset <> '' then Root.AddPair('preset', pAnswer.Preset);
    Root.AddPair('a', EventJson(pAnswer.A));
    Root.AddPair('b', EventJson(pAnswer.B));
    Root.AddPair('verdict', VERDICT_CODES[pAnswer.Verdict]);
    Root.AddPair('proven', TJSONBool.Create(pAnswer.Proven));
    Root.AddPair('summary', pAnswer.Summary);
    var Reasons:= TJSONArray.Create;
    for var R in pAnswer.Reasons do Reasons.Add(REASON_CODES[R]);
    Root.AddPair('reasons', Reasons);
    var Methods:= TJSONArray.Create;
    for var M in pAnswer.Methods do Methods.Add(METHOD_CODES[M]);
    Root.AddPair('methods', Methods);
    var Judged:= TJSONArray.Create;
    for var J in pAnswer.Judged do
    begin
      var O:= TJSONObject.Create;
      O.AddPair('side', if J.SideA then 'a' else 'b');
      O.AddPair('file', J.Site.FileName);
      O.AddPair('line', TJSONNumber.Create(J.Site.Line));
      O.AddPair('col', TJSONNumber.Create(J.Site.Col));
      O.AddPair('routine', J.Site.Routine);
      O.AddPair('proven', TJSONBool.Create(J.Proven));
      O.AddPair('method', METHOD_CODES[J.Method]);
      O.AddPair('reason', if J.Proven or J.SideA then '' else REASON_CODES[J.Reason]);
      O.AddPair('why', J.Why);
      Judged.Add(O);
    end;
    Root.AddPair('judged', Judged);
    var Limits:= TJSONArray.Create;
    for var L in pAnswer.Limits do Limits.Add(L);
    Root.AddPair('limits', Limits);
    var Budget:= TJSONObject.Create;
    Budget.AddPair('routines', TJSONNumber.Create(pAnswer.Routines));
    Budget.AddPair('ms', TJSONNumber.Create(pAnswer.Ms));
    Budget.AddPair('exhausted', TJSONBool.Create(pAnswer.Exhausted));
    Root.AddPair('budget', Budget);
    Result:= Root.ToJSON;
  finally
    Root.Free;
  end;
end;

procedure WriteEventNotes(const pLabel: string; const pEvent: THbvEvent);
begin
  for var S in pEvent.Sites do
    if not S.Definite then
      Writeln(Format('  %s? %s  in %s   %s', [pLabel, SiteText(S.Site), S.Site.Routine, S.Note]));
  for var W in pEvent.IncompleteWhy do
    Writeln(Format('  %s incomplete: %s', [pLabel, W]));
end;

procedure WriteHbvAnswer(const pAnswer: THbvAnswer);
const
  SITE_WORD: array[Boolean] of string = ('sites', 'site');
begin
  Writeln(Format('%s  A = %s (%d %s)   B = %s (%d %s)%s', [VERB_NAME,
    pAnswer.A.Spec, Length(pAnswer.A.Sites), SITE_WORD[Length(pAnswer.A.Sites) = 1],
    pAnswer.B.Spec, Length(pAnswer.B.Sites), SITE_WORD[Length(pAnswer.B.Sites) = 1],
    if pAnswer.Preset <> '' then '   preset ' + pAnswer.Preset else '']));
  Writeln(Format('verdict  %s   %s', [VERDICT_CODES[pAnswer.Verdict], pAnswer.Summary]));
  { the rows that carry the verdict: sites of B for a YES, sites of A for a b-first NO, all for a MAY }
  for var J in pAnswer.Judged do
    if (pAnswer.Verdict = hbvMay) or (J.SideA = (pAnswer.Verdict = hbvNo)) then
      Writeln(Format('  %s  %s  in %s   %s   %s', [if J.SideA then 'A' else 'B', SiteText(J.Site), J.Site.Routine,
      if J.Proven then 'proven' else if J.SideA then 'open' else REASON_CODES[J.Reason], J.Why]));
  WriteEventNotes('A', pAnswer.A);
  WriteEventNotes('B', pAnswer.B);
  if pAnswer.Limits <> nil then Writeln('limits: ', string.Join(', ', pAnswer.Limits));
end;

end.
