unit DRagLint.Lint.TaintRules;

/// <summary>Interprocedural taint rules (taint-sql-injection, taint-command-injection,
/// taint-path-traversal): from every catalogued SINK site, walk the data_flows facts
/// backwards across routines, fields, globals and the library store until a catalogued
/// SOURCE, a sanitizer or a dead end; one finding per (sink site, source site) with its
/// path on TLintFinding.Path.</summary>
/// <remarks>
/// T0 (2026-10-27) was the CONTRACT commit: types, rule ids, the catalogue schema and
/// the Check signature. T2 (2026-10-27) implements the walk (plan
/// docs\superpowers\plans\2026-10-27-taint-interprocedural-plan.md sections 4-7) and
/// loads the catalogues (LoadConfig).
///
/// CATALOGUE JSON SCHEMA (rules\taint-sources.json, rules\taint-sinks.json,
/// rules\taint-propagators.json; each file is ONE JSON object):
///   taint-sources.json     { "sources":     [ SOURCE, ... ] }
///   taint-sinks.json       { "sinks":       [ SINK, ... ] }
///   taint-propagators.json { "propagators": [ PROPAGATOR, ... ],
///                            "sanitizers":  [ SANITIZER, ... ] }
///   SOURCE     { "id": str (unique), "name": str (qualified 'Vcl.StdCtrls.TCustomEdit.Text'
///                or bare 'ParamStr'), "kind": "call"|"read", "confidence": "certain"|"weak",
///                "enabled": bool (default true; false = second-order, on via second_order),
///                "categories": [ "sql"|"cmd"|"path", ... ] (optional; default every rule --
///                under an unlisted rule the value is TRUSTED and the branch stops clean;
///                an unknown category raises ELintConfigError),
///                "trusted_args": [ str, ... ] (optional; a 'call' whose argument list, read
///                from the source line at the call and trimmed, equals one of these
///                case-insensitively is TRUSTED: `0` = ParamStr(0), the module path;
///                `'APPDATA'` = an OS known folder; an argument list that does not close on
///                the call's line never matches),
///                "note": str (optional) }                                 -> TTaintSourceEntry
///   SINK       { "id": str (unique), "rule": one of the TAINT_RULE_* ids, "name": str (leaf
///                name of the call or written member), "kind": "call"|"write",
///                "args": [int, ...] (0-based argument positions; [] for "write" = the RHS),
///                "receiver_suffix": str (optional; matched against refs.receiver_text,
///                e.g. ".SQL"), "type": str (optional; owning type qname or bare name, the
///                resolved target's owner must be it or a descendant), "cwe": "CWE-89" }
///                                                                         -> TTaintSinkEntry
///   PROPAGATOR { "name": str, "args": [int, ...] (0-based; -1 = every argument),
///                "to": "result"|"receiver"|"outparam" (default "result"),
///                "out": int (the outparam position when "to" = "outparam"; else -1) }
///                                                                   -> TTaintPropagatorEntry
///   SANITIZER  { "name": str, "sanitizes": [ "sql"|"cmd"|"path"|"all", ... ] }
///                                                                    -> TTaintSanitizerEntry
/// The `taint` object of the lint config MERGES additively: keys "sources", "sinks",
/// "propagators", "sanitizers" (same row shapes, appended), "disable": [str] (removes a
/// built-in entry by "id"; propagators/sanitizers, which have no id, by "name"), and the
/// scalars of TTaintConfig under their JSON names (max_depth, lib_depth, max_rounds,
/// follow_ambiguous, weak_receiver_regex, weak_severity_drop, max_paths_per_sink,
/// second_order). Unknown keys are ignored (the rest of TLintConfig does the same); a
/// sink naming an unknown rule or a malformed catalogue raises ELintConfigError.
///
/// NAME MATCHING (sources, propagators, sanitizers): a name is 'Leaf' (a free routine:
/// matches an unresolved call of that name, or a resolved LIBRARY routine of that leaf
/// name -- a resolved PROJECT routine of the same name is project code and is walked
/// instead), or 'TType.Leaf' / 'Unit.Path.TType.Leaf' (the second-to-last segment is the
/// owning type: the resolved member's class, or the declared type of the receiver
/// variable / field / global, or the receiver text itself for `TType.Method(..)`, must
/// be TType or descend from it -- proved over the project store, then the library).
/// An unresolved bare call is 'certain' unless the project declares a routine of that
/// name (then 'weak': it could be shadowed). An unresolved `X.Text` read whose receiver
/// text matches weak_receiver_regex (case-insensitive) and that no catalogue entry
/// proves is a 'weak' source.
///
/// FIXTURE DB (what T2 develops against before T1 is green): index the fixture project
/// (tests\lint-project\taint\) with an engine built from T0 or later -- data_flows exists
/// and is empty -- then INSERT the rows T1 would emit, keyed by real ids:
/// symbol_id = symbols.id of the routine (by qualified_name), file_id = files.id (by path),
/// owner_id = the routine's parent class symbols.id or 0, every position = the
/// refs.start_line/start_col of the ref at that site; kinds = the DF_* text values;
/// via_local/cond 0|1. The INSERT script is tests\lint-project\taint\fixture_rows.py
/// (python sqlite3, the run_purity_emit technique); a real T1 index of the same fixture
/// must give a superset of those rows.
/// All .pas source: strict 7-bit ASCII, CRLF line endings, no BOM.
/// </remarks>

interface

uses
  System.SysUtils
  , DRagLint.Core.Model // dl:unit DRagLint.Core.Model accepted -- the DF_* kind constants ARE the data_flows contract T0 put in the model; the walker compares exactly those
  , DRagLint.Core.Interfaces
  ;

const
  /// <summary>Rule id: tainted data reaches an SQL text sink (error, CWE-89).</summary>
  TAINT_RULE_SQL  = 'taint-sql-injection';
  /// <summary>Rule id: tainted data reaches a process/shell launch sink (error, CWE-78).</summary>
  TAINT_RULE_CMD  = 'taint-command-injection';
  /// <summary>Rule id: tainted data reaches a file-system path sink (warning, CWE-22).</summary>
  TAINT_RULE_PATH = 'taint-path-traversal';
  /// <summary>Sanitizer category of TAINT_RULE_SQL.</summary>
  TAINT_CAT_SQL   = 'sql';
  /// <summary>Sanitizer category of TAINT_RULE_CMD.</summary>
  TAINT_CAT_CMD   = 'cmd';
  /// <summary>Sanitizer category of TAINT_RULE_PATH.</summary>
  TAINT_CAT_PATH  = 'path';
  /// <summary>Sanitizer category that stops every rule (StrToInt and friends).</summary>
  TAINT_CAT_ALL   = 'all';
  /// <summary>Every taint finding's message starts with this text (distinguishes it from the
  /// local shape rules in text and SARIF).</summary>
  TAINT_MSG_PREFIX = 'Tainted data reaches';

type
  /// <summary>One SOURCE catalogue row (rules\taint-sources.json "sources"[]).</summary>
  TTaintSourceEntry = record
    /// <summary>Unique id ("disable" key).</summary>
    Id        : string ;
    /// <summary>Qualified or bare name of the call / read member.</summary>
    Name      : string ;
    /// <summary>'call' (the call's result is tainted) or 'read' (the member read is).</summary>
    Kind      : string ;
    /// <summary>'certain' or 'weak'.</summary>
    Confidence: string ;
    /// <summary>False = off unless second_order (TField/TDataSet sources).</summary>
    Enabled   : Boolean;
    /// <summary>Free text.</summary>
    Note      : string ;
    /// <summary>TAINT_CAT_SQL / _CMD / _PATH values this source is attacker data for; empty =
    /// every rule. Under a rule whose category is not listed the value is trusted: the
    /// branch stops clean, as at a sanitizer.</summary>
    Categories: TArray<string>;
    /// <summary>Argument lists (as written, trimmed, compared case-insensitively) that make a
    /// 'call' source trusted: `0` for ParamStr (the module path), `'APPDATA'` for
    /// GetEnvironmentVariable (an OS known folder). Empty = every call is a source.</summary>
    TrustedArgs: TArray<string>;
  end;

  /// <summary>One SINK catalogue row (rules\taint-sinks.json "sinks"[]).</summary>
  TTaintSinkEntry = record
    /// <summary>Unique id ("disable" key).</summary>
    Id            : string ;
    /// <summary>One of the TAINT_RULE_* ids.</summary>
    Rule          : string ;
    /// <summary>Leaf name of the call or written member.</summary>
    Name          : string ;
    /// <summary>'call' or 'write'.</summary>
    Kind          : string ;
    /// <summary>0-based argument positions that must not be tainted; empty for 'write'.</summary>
    Args          : TArray<Integer>;
    /// <summary>Required suffix of refs.receiver_text ('' = any).</summary>
    ReceiverSuffix: string ;
    /// <summary>Owning type the resolved target must be or descend from ('' = any; bare
    /// entries also match unresolved calls).</summary>
    TypeName      : string ;
    /// <summary>'CWE-89' etc.</summary>
    Cwe           : string ;
  end;

  /// <summary>One PROPAGATOR row (rules\taint-propagators.json "propagators"[]).</summary>
  TTaintPropagatorEntry = record
    /// <summary>Qualified or bare routine name.</summary>
    Name    : string ;
    /// <summary>0-based argument positions whose taint flows on; -1 = every argument.</summary>
    Args    : TArray<Integer>;
    /// <summary>'result', 'receiver' or 'outparam'.</summary>
    ToSlot  : string ;
    /// <summary>The outparam position when ToSlot = 'outparam'; else -1.</summary>
    OutIndex: Integer;
  end;

  /// <summary>One SANITIZER row (rules\taint-propagators.json "sanitizers"[]).</summary>
  TTaintSanitizerEntry = record
    /// <summary>Qualified or bare routine name.</summary>
    Name     : string ;
    /// <summary>TAINT_CAT_* values this sanitizer stops.</summary>
    Sanitizes: TArray<string>;
  end;

  /// <summary>The merged taint configuration: built-in catalogues plus the `taint`
  /// object of the lint config (see the unit remarks for the JSON shape).</summary>
  TTaintConfig = record
    /// <summary>Merged sources (disabled ones removed).</summary>
    Sources         : TArray<TTaintSourceEntry>;
    /// <summary>Merged sinks.</summary>
    Sinks           : TArray<TTaintSinkEntry>;
    /// <summary>Merged propagators.</summary>
    Propagators     : TArray<TTaintPropagatorEntry>;
    /// <summary>Merged sanitizers.</summary>
    Sanitizers      : TArray<TTaintSanitizerEntry>;
    /// <summary>JSON max_depth: walk depth safety cap (default 16).</summary>
    MaxDepth        : Integer;
    /// <summary>JSON lib_depth: hops inside the library store (default 4).</summary>
    LibDepth        : Integer;
    /// <summary>JSON max_rounds: fixpoint re-query rounds for a key on a cycle (default 4).</summary>
    MaxRounds       : Integer;
    /// <summary>JSON follow_ambiguous: follow 'ambiguous' call edges (default False).</summary>
    FollowAmbiguous : Boolean;
    /// <summary>JSON weak_receiver_regex: an unresolved `.Text` read on a receiver matching it
    /// (case-insensitive) is a weak source (default
    /// '(Edit|edt|Memo|mmo|Combo|cbo|cmb|Input|Query|Param)').</summary>
    WeakReceiverRegex: string;
    /// <summary>JSON weak_severity_drop: a weak finding is one severity lower (default True).</summary>
    WeakSeverityDrop: Boolean;
    /// <summary>JSON max_paths_per_sink: findings per sink before "+N more paths" (default 3).</summary>
    MaxPathsPerSink : Integer;
    /// <summary>JSON second_order: enable Enabled=False (TField/TDataSet) sources (default False).</summary>
    SecondOrder     : Boolean;
    /// <summary>The defaults above with EMPTY catalogues (LoadConfig fills them from rules\taint-*.json).</summary>
    /// <returns>A config with every scalar at its documented default.</returns>
    class function Defaults: TTaintConfig; static;
  end;

  /// <summary>Counters for the DRAGLINT_DEBUG / DRAGLINT_PROFILE stderr line
  /// `taint: sinks N, keys N, rows read N, library hops N, hits N, partial keys N, depth caps N, N ms`.</summary>
  TTaintStats = record
    /// <summary>Sink sites examined (one per site and rule).</summary>
    Sinks      : Integer;
    /// <summary>Memo keys (routine, slot) evaluated.</summary>
    Keys       : Integer;
    /// <summary>data_flows rows read.</summary>
    RowsRead   : Integer;
    /// <summary>Hops taken inside the library store.</summary>
    LibraryHops: Integer;
    /// <summary>Source hits found (before the per-sink path cap).</summary>
    Hits       : Integer;
    /// <summary>Sinks whose answer is partial (a cap or max_rounds was reached).</summary>
    PartialKeys: Integer;
    /// <summary>Evaluations cut at the walk-depth guard (TAINT_EVAL_DEPTH_CAP memo keys in flight
    /// plus nested row evaluations): that branch answers "unknown" (no hit), never a stack overflow.</summary>
    DepthCaps  : Integer;
    /// <summary>Wall time of Check.</summary>
    ElapsedMs  : Int64  ;
    /// <summary>True when the project store has no data_flows table, or the table is empty
    /// over a multi-file scope (indexed before extractor 1.26.0): the caller prints ONE
    /// stale-index note; no findings.</summary>
    StaleIndex : Boolean;
    /// <summary>The stats as the one stderr line the CLI prints under DRAGLINT_DEBUG.</summary>
    /// <returns>`taint: sinks N, keys N, rows read N, library hops N, hits N, partial keys N, depth caps N, N ms`.</returns>
    function ToLine: string;
  end;

  /// <summary>The three taint rules over a store's data_flows facts.</summary>
  TTaintRules = class
    public
      /// <summary>Builds the merged configuration: the three built-in catalogues of
      /// ARulesDir, then each `taint` override object in order (additive lists, scalar
      /// overrides, "disable" applied last).</summary>
      /// <param name="ARulesDir">The rules directory; '' = &lt;exe-dir&gt;\rules (the same default
      /// TRuleCatalog.BuildCatalog uses).</param>
      /// <param name="AOverrides">JSON texts of `taint` objects (TLintConfig.TaintJson), applied in
      /// order; may be empty.</param>
      /// <returns>Defaults plus every merged entry; sources with "enabled": false are kept only
      /// when second_order is True.</returns>
      /// <exception cref="ELintConfigError">A catalogue or override is not a JSON object, or a
      /// sink names a rule that is not one of the TAINT_RULE_* ids.</exception>
      /// <remarks>A MISSING catalogue file is not an error (a dev tree without rules\) but prints
      /// ONE stderr note per process naming it, so an empty catalogue never reads as a clean
      /// run.</remarks>
      class function LoadConfig(const ARulesDir: string; const AOverrides: TArray<string>): TTaintConfig; static;
      /// <summary>Finds every taint path into a catalogued sink inside the scope files.</summary>
      /// <param name="AStore">The project store (must not be nil).</param>
      /// <param name="ALibStore">The library store the lint path already opened, or nil (library
      /// routines are then never walked; catalogued names still match by name).</param>
      /// <param name="AScopeFileIds">files.id of the files being linted (sinks are searched only
      /// there; the walk may leave the scope and the project).</param>
      /// <param name="ACfg">The merged configuration.</param>
      /// <param name="AStats">Counters for the trace line; zeroed on entry.</param>
      /// <returns>One finding per (sink site, source site) -- at most ACfg.MaxPathsPerSink per sink
      /// and rule, the last one's message ending in "+N more paths" when more were found --
      /// RuleId one of TAINT_RULE_*, Message starting with TAINT_MSG_PREFIX, Path = source
      /// -> hops -> sink, SymbolName = the sink's routine.</returns>
      /// <remarks>Read-only on both stores. A store without data_flows (HasDataFlows False)
      /// returns nil with AStats.StaleIndex True. Memoised per (rule category, routine, slot)
      /// for the whole call, so a lint-all run is one demand-driven fixpoint; a key met again
      /// while on the stack answers its partial set and the sink is re-queried up to
      /// ACfg.MaxRounds times until nothing grows (AStats.PartialKeys counts sinks still
      /// growing at the cap). Not thread-safe.</remarks>
      class function Check(const AStore, ALibStore: ISymbolStore; const AScopeFileIds: TArray<Int64>;
                           const ACfg: TTaintConfig; out AStats: TTaintStats): TArray<TLintFinding>; static;
  end;

implementation

uses
  System.Generics.Collections
  , System.Generics.Defaults
  , System.JSON
  , System.IOUtils
  , System.StrUtils
  , System.Diagnostics
  , System.RegularExpressions
  , DRagLint.Lint.Config
  ;

const
  STORE_PROJECT  = 0;
  STORE_LIB      = 1;
  HIT_CAP        = 32;   { distinct source sites kept per memo key }
  DEFAULT_DEPTH  = 16;
  DEFAULT_LIB    = 4;
  DEFAULT_ROUNDS = 4;
  DEFAULT_PATHS  = 3;
  { memo keys in flight + nested EvalRows calls on one walk: every evaluator
    recursion passes through one of the two, so this bounds the native stack
    whatever max_depth is configured to }
  TAINT_EVAL_DEPTH_CAP = 256;
  SEV_ERROR      = 'error';
  SEV_WARNING    = 'warning';
  SEV_INFO       = 'info';
  CONF_CERTAIN   = 'certain';
  CONF_WEAK      = 'weak';
  KIND_CALL      = 'call';
  KIND_READ      = 'read';
  KIND_WRITE     = 'write';
  SLOT_RESULT    = 'result';
  SLOT_OUTPARAM  = 'outparam';
  FILE_SOURCES   = 'taint-sources.json';
  FILE_SINKS     = 'taint-sinks.json';
  FILE_PROPS     = 'taint-propagators.json';
  WEAK_TEXT_LEAF = 'Text';
  REF_TYPE_USE   = 'type_use';
  DIR_OVERRIDE   = 'override';

var
  GMissingNoted: Boolean = False;

type
  { One source site reaching the point being evaluated. Path runs source-first. }
  THit = record
    Key    : string ;
    SrcName: string ;
    SrcKind: string ;
    Weak   : Boolean;
    Fields : Integer;
    Path   : TArray<TLintLocation>;
  end;

  { What a value expression inside one routine derives from: source hits, plus the
    routine's own parameters (mapped to call-site arguments by the caller). }
  TSummary = record
    Hits  : TArray<THit>;
    Params: TArray<Integer>;
  end;

  TMemoEntry = record
    Sum    : TSummary;
    Partial: Boolean;
    Round  : Integer;
  end;

  { A ref at one site, bound as far as the stores allow. }
  TResolved = record
    Found   : Boolean;
    Store   : Integer;
    Sym     : TSymbol;
    Weak    : Boolean;
    Name    : string ;
    Receiver: string ;
    RecvType: string ;
  end;

  TTaintWalker = class  // dl:ok god-class@700f, high-response@700f -- REVIEWED 2026-10-27: ONE demand-driven fixpoint; its fields are the per-run caches (refs, edges, symbols, rows, memo, stack) every slot evaluator shares, and its methods are the mutually recursive evaluators of plan section 4 (ref, call, slot, callers, field, global). Splitting them would hand the memo and the cycle stack a second owner.
  private
    FStores      : array[STORE_PROJECT..STORE_LIB] of ISymbolStore;
    FCfg         : TTaintConfig;
    FCat         : string;
    FStats       : TTaintStats;
    FMemo        : TDictionary<string, TMemoEntry>;
    FStack       : TDictionary<string, Boolean>;
    FSites       : TDictionary<string, Boolean>;
    FRefs        : TDictionary<string, TArray<TReference>>;
    FRefFiles    : TDictionary<string, Boolean>;
    FEdges       : TDictionary<string, TArray<TCallEdge>>;
    FEdgeRoutines: TDictionary<string, Boolean>;
    FSyms        : TDictionary<string, TSymbol>;
    FPaths       : TDictionary<string, string>;
    FLines       : TDictionary<string, TArray<string>>;
    FRoutineRows : TDictionary<string, TArray<TDataFlowRow>>;
    FMembers     : TDictionary<Int64, Int64>;
    FProjNames   : TDictionary<string, Boolean>;
    FTypeIs      : TDictionary<string, Boolean>;
    FWeakRegex   : TRegEx;
    FLibDepth    : Integer;
    FEvalDepth   : Integer;
    FCycleReads  : Integer;
    FRound       : Integer;
    FChanged     : Boolean;
    FCapHit      : Boolean;
    function  Sym(AStore: Integer; AId: Int64): TSymbol;
    function  PathOf(AStore: Integer; AFileId: Int64): string;
    function  CallArgText(AStore: Integer; AFileId: Int64; ALine, ACol: Integer): string;
    function  ShortName(AStore: Integer; const ASym: TSymbol): string;
    function  RefsAt(AStore: Integer; AFileId: Int64; ALine, ACol: Integer): TArray<TReference>;
    function  EdgesOf(AStore: Integer; AEnclosing, ARefId: Int64): TArray<TCallEdge>;
    function  MemberOf(ARefId: Int64): Int64;
    function  RowsOf(AStore: Integer; ARoutine: Int64; const AKind: string): TArray<TDataFlowRow>;
    function  ArgRowsAt(AStore: Integer; const X: TSymbol; AFileId: Int64; ALine, ACol: Integer;
                        const AIdx: TArray<Integer>): TArray<TDataFlowRow>;
    function  ProjectHasRoutine(const AName: string): Boolean;
    function  IsRoutine(const S: TSymbol): Boolean;
    function  DeclaredTypeOf(AStore: Integer; const X: TSymbol; const AIdent: string): string;
    function  TypeIs(AStore: Integer; AFileId: Int64; const AType, AWanted: string): Boolean;
    function  Resolve(AStore: Integer; const X: TSymbol; AFileId: Int64; ALine, ACol: Integer;
                      const AName: string): TResolved;
    function  NameMatches(const AEntry: string; const R: TResolved; AFileId: Int64; out AWeak: Boolean): Boolean;
    function  Loc(AStore: Integer; const X: TSymbol; AFileId: Int64; ALine, ACol: Integer; const ANote: string): TLintLocation;
    function  SourceHit(AStore: Integer; const X: TSymbol; const ARow: TDataFlowRow; const AName, AKind, ANote: string;
                        AWeak: Boolean): THit;
    procedure AddHit(var AAcc: TSummary; const AHit: THit);
    procedure Merge(var AAcc: TSummary; const AAdd: TSummary; AWithParams: Boolean);
    procedure MergeHop(var AAcc: TSummary; const AAdd: TSummary; const AHop: TLintLocation; AWeak: Boolean; AFieldInc: Integer);
    procedure AddParam(var AAcc: TSummary; AIdx: Integer);
    function  DepthCapped(const AWhere: string): Boolean;
    function  Enter(const AKey: string; out ASum: TSummary; out AStartCycles: Integer): Boolean;
    procedure Leave(const AKey: string; const ASum: TSummary; AStartCycles: Integer);
    function  EvalRows(AStore: Integer; const X: TSymbol; const ARows: TArray<TDataFlowRow>): TSummary;
    function  EvalRef(AStore: Integer; const X: TSymbol; const ARow: TDataFlowRow): TSummary;
    function  EvalArgOut(AStore: Integer; const X: TSymbol; const ARow: TDataFlowRow): TSummary;
    function  CallSummary(AStore: Integer; const X: TSymbol; const ARow: TDataFlowRow; const R: TResolved;
                          const ASlot: string; AOutIdx: Integer): TSummary;
    function  SlotSummary(AStore: Integer; const T: TSymbol; const ASlot: string; AOutIdx: Integer): TSummary;
    function  CallersParam(const X: TSymbol; AIdx: Integer): TSummary;
    function  FieldSummary(AStore: Integer; const ARow: TDataFlowRow): TSummary;
    function  IsInheritedField(AStore: Integer; const X: TSymbol; const AName: string): Boolean;
    function  GlobalSummary(AStore: Integer; const ARow: TDataFlowRow): TSummary;
    function  Top(AStore: Integer; const X: TSymbol; const ASum: TSummary): TSummary;
    function  Implementations(AStore: Integer; const T: TSymbol): TArray<TSymbol>;
    function  BaseMethods(const X: TSymbol): TArray<TSymbol>;
    function  SinkMatches(const AEntry: TTaintSinkEntry; const X: TSymbol; const ARow: TDataFlowRow; out AWeak: Boolean): Boolean;
    function  EvalSink(const X: TSymbol; const ARows: TArray<TDataFlowRow>): TSummary;
    function  Findings(const X: TSymbol; const ARow: TDataFlowRow; const ARule: string; AWeakSink: Boolean;
                       const AHits: TArray<THit>): TArray<TLintFinding>;
  public
    constructor Create(const AStore, ALibStore: ISymbolStore; const ACfg: TTaintConfig);
    destructor Destroy; override;
    function Run(const AScopeFileIds: TArray<Int64>): TArray<TLintFinding>;
    property Stats: TTaintStats read FStats;
  end;

{ ---- small helpers ---------------------------------------------------------- }

function LastSeg(const AName: string): string;
begin
  Result:= Copy(AName, LastDelimiter('.', AName) + 1, MaxInt);
end;

{ The owning type of 'TType.Leaf' / 'Unit.TType.Leaf'; '' for a bare 'Leaf'. }
function OwnerSeg(const AName: string): string;
var
  P: Integer;
begin
  P:= LastDelimiter('.', AName);
  if P = 0 then Exit('');
  Result:= LastSeg(Copy(AName, 1, P - 1));
end;

{ True when AValue is in AList; a -1 element means "every position". }
function InInts(AValue: Integer; const AList: TArray<Integer>): Boolean;
var
  V: Integer;
begin
  for V in AList do
    if (V = AValue) or (V < 0) then Exit(True);
  Result:= False;
end;

function InStrs(const AValue: string; const AList: TArray<string>): Boolean;
var
  V: string;
begin
  for V in AList do
    if SameText(V, AValue) then Exit(True);
  Result:= False;
end;

function RuleCategory(const ARule: string): string;
begin
  if SameText(ARule, TAINT_RULE_CMD) then Result:= TAINT_CAT_CMD
  else if SameText(ARule, TAINT_RULE_PATH) then Result:= TAINT_CAT_PATH
  else Result:= TAINT_CAT_SQL;
end;

function RuleCweText(const ARule: string): string;
begin
  if SameText(ARule, TAINT_RULE_CMD) then Result:= 'CWE-78 OS command injection'
  else if SameText(ARule, TAINT_RULE_PATH) then Result:= 'CWE-22 path traversal'
  else Result:= 'CWE-89 SQL injection';
end;

function RuleBaseSeverity(const ARule: string): string;
begin
  Result:= if SameText(ARule, TAINT_RULE_PATH) then SEV_WARNING else SEV_ERROR;
end;

function DropSeverity(const ASev: string): string;
begin
  if SameText(ASev, SEV_ERROR) then Result:= SEV_WARNING
  else if SameText(ASev, SEV_WARNING) then Result:= SEV_INFO
  else Result:= ASev;
end;

{ An identifier written like a type ('TFileStream', 'TPath'): a class-method or
  constructor call names its class as the receiver. }
function LooksLikeTypeName(const AText: string): Boolean;
begin
  Result:= (Length(AText) >= 2) and CharInSet(AText[1], ['T', 'E', 'I'])
           and CharInSet(AText[2], ['A'..'Z']) and (not AText.Contains('.'));
end;

{ 'Unit.TType.Method' -> 'TType.Method'; 'Unit.Routine' -> 'Routine'. }
function DisplayRoutine(const AQName: string): string;
var
  Owner: string;
begin
  Owner:= OwnerSeg(AQName);
  Result:= if LooksLikeTypeName(Owner) then Owner + '.' + LastSeg(AQName) else LastSeg(AQName);
end;

{ ---- JSON catalogue parsing ---------------------------------------------------- }

function JStr(const AObj: TJSONObject; const AKey, ADefault: string): string;
var
  V: TJSONValue;
begin
  V:= AObj.GetValue(AKey);
  if (V = nil) or (V is TJSONNull) then Exit(ADefault);
  Result:= V.Value;
end;

function JBool(const AObj: TJSONObject; const AKey: string; ADefault: Boolean): Boolean;
var
  V: TJSONValue;
begin
  V:= AObj.GetValue(AKey);
  if V is TJSONBool then Exit((V as TJSONBool).AsBoolean);
  Result:= ADefault;
end;

function JInt(const AObj: TJSONObject; const AKey: string; ADefault: Integer): Integer;
var
  V: TJSONValue;
begin
  V:= AObj.GetValue(AKey);
  if V is TJSONNumber then Exit((V as TJSONNumber).AsInt);
  Result:= ADefault;
end;

{ The elements under AKey; empty when the key is absent or not an array. Owned by AObj. }
function JArr(const AObj: TJSONObject; const AKey: string): TArray<TJSONValue>;
var
  A: TJSONArray;
  I: Integer;
begin
  Result:= nil;
  if (AObj.GetValue(AKey) is not TJSONArray) then Exit;
  A:= AObj.GetValue(AKey) as TJSONArray;
  SetLength(Result, A.Count);
  for I:= 0 to A.Count - 1 do Result[I]:= A.Items[I];
end;

function JInts(const AObj: TJSONObject; const AKey: string): TArray<Integer>;
var
  E: TJSONValue;
begin
  Result:= nil;
  for E in JArr(AObj, AKey) do
    if E is TJSONNumber then Result:= Result + [(E as TJSONNumber).AsInt];
end;

function JStrs(const AObj: TJSONObject; const AKey: string): TArray<string>;
var
  E: TJSONValue;
begin
  Result:= nil;
  for E in JArr(AObj, AKey) do Result:= Result + [E.Value];
end;
function ParseObject(const AText, AWhat: string): TJSONObject;
var
  V: TJSONValue;
begin
  V:= TJSONObject.ParseJSONValue(AText);
  if (V is not TJSONObject) then
  begin
    V.Free;
    raise ELintConfigError.CreateFmt('taint: %s is not a JSON object', [AWhat]);
  end;
  Result:= V as TJSONObject;
end;

procedure AppendSources(const AObj: TJSONObject; var ACfg: TTaintConfig; const AWhat: string);
var
  E  : TJSONValue;
  O  : TJSONObject;
  Src: TTaintSourceEntry;
  Cat: string;
begin
  for E in JArr(AObj, 'sources') do
    if E is TJSONObject then
    begin
      O:= E as TJSONObject;
      Src:= Default(TTaintSourceEntry);
      Src.Id        := JStr(O, 'id', '');
      Src.Name      := JStr(O, 'name', '');
      Src.Kind      := JStr(O, 'kind', KIND_CALL);
      Src.Confidence:= JStr(O, 'confidence', CONF_CERTAIN);
      Src.Enabled   := JBool(O, 'enabled', True);
      Src.Note      := JStr(O, 'note', '');
      Src.Categories:= JStrs(O, 'categories');
      Src.TrustedArgs:= JStrs(O, 'trusted_args');
      for Cat in Src.Categories do
        if not MatchText(Cat, [TAINT_CAT_SQL, TAINT_CAT_CMD, TAINT_CAT_PATH]) then
          raise ELintConfigError.CreateFmt('taint: source "%s" in %s names unknown category "%s"', [Src.Id, AWhat, Cat]);
      if Src.Name <> '' then ACfg.Sources:= ACfg.Sources + [Src];
    end;
end;

procedure AppendSinks(const AObj: TJSONObject; var ACfg: TTaintConfig; const AWhat: string);
var
  E  : TJSONValue;
  O  : TJSONObject;
  Snk: TTaintSinkEntry;
begin
  for E in JArr(AObj, 'sinks') do
    if E is TJSONObject then
    begin
      O:= E as TJSONObject;
      Snk:= Default(TTaintSinkEntry);
      Snk.Id            := JStr(O, 'id', '');
      Snk.Rule          := JStr(O, 'rule', '');
      Snk.Name          := JStr(O, 'name', '');
      Snk.Kind          := JStr(O, 'kind', KIND_CALL);
      Snk.Args          := JInts(O, 'args');
      Snk.ReceiverSuffix:= JStr(O, 'receiver_suffix', '');
      Snk.TypeName      := JStr(O, 'type', '');
      Snk.Cwe           := JStr(O, 'cwe', '');
      if not MatchText(Snk.Rule, [TAINT_RULE_SQL, TAINT_RULE_CMD, TAINT_RULE_PATH]) then
        raise ELintConfigError.CreateFmt('taint: sink "%s" in %s names unknown rule "%s"', [Snk.Id, AWhat, Snk.Rule]);
      if Snk.Name <> '' then ACfg.Sinks:= ACfg.Sinks + [Snk];
    end;
end;

procedure AppendPropagators(const AObj: TJSONObject; var ACfg: TTaintConfig);
var
  E  : TJSONValue;
  O  : TJSONObject;
  Prp: TTaintPropagatorEntry;
  San: TTaintSanitizerEntry;
begin
  for E in JArr(AObj, 'propagators') do
      if E is TJSONObject then
      begin
        O:= E as TJSONObject;
        Prp:= Default(TTaintPropagatorEntry);
        Prp.Name    := JStr(O, 'name', '');
        Prp.Args    := JInts(O, 'args');
        Prp.ToSlot  := JStr(O, 'to', SLOT_RESULT);
        Prp.OutIndex:= JInt(O, 'out', -1);
        if Prp.Name <> '' then ACfg.Propagators:= ACfg.Propagators + [Prp];
      end;
  for E in JArr(AObj, 'sanitizers') do
      if E is TJSONObject then
      begin
        O:= E as TJSONObject;
        San:= Default(TTaintSanitizerEntry);
        San.Name     := JStr(O, 'name', '');
        San.Sanitizes:= JStrs(O, 'sanitizes');
        if San.Name <> '' then ACfg.Sanitizers:= ACfg.Sanitizers + [San];
      end;
end;

procedure AppendEntries(const AObj: TJSONObject; var ACfg: TTaintConfig; var ADisable: TArray<string>;
                        const AWhat: string);
begin
  AppendSources(AObj, ACfg, AWhat);
  AppendSinks(AObj, ACfg, AWhat);
  AppendPropagators(AObj, ACfg);
  ADisable:= ADisable + JStrs(AObj, 'disable');
end;

procedure ApplyScalars(const AObj: TJSONObject; var ACfg: TTaintConfig);
begin
  ACfg.MaxDepth         := JInt (AObj, 'max_depth',           ACfg.MaxDepth);
  ACfg.LibDepth         := JInt (AObj, 'lib_depth',           ACfg.LibDepth);
  ACfg.MaxRounds        := JInt (AObj, 'max_rounds',          ACfg.MaxRounds);
  ACfg.FollowAmbiguous  := JBool(AObj, 'follow_ambiguous',    ACfg.FollowAmbiguous);
  ACfg.WeakReceiverRegex:= JStr (AObj, 'weak_receiver_regex', ACfg.WeakReceiverRegex);
  ACfg.WeakSeverityDrop := JBool(AObj, 'weak_severity_drop',  ACfg.WeakSeverityDrop);
  ACfg.MaxPathsPerSink  := JInt (AObj, 'max_paths_per_sink',  ACfg.MaxPathsPerSink);
  ACfg.SecondOrder      := JBool(AObj, 'second_order',        ACfg.SecondOrder);
end;

{ ---- TTaintConfig / TTaintStats ---------------------------------------------- }

class function TTaintConfig.Defaults: TTaintConfig;
begin
  Result:= Default(TTaintConfig);
  Result.MaxDepth         := DEFAULT_DEPTH;
  Result.LibDepth         := DEFAULT_LIB;
  Result.MaxRounds        := DEFAULT_ROUNDS;
  Result.FollowAmbiguous  := False;
  Result.WeakReceiverRegex:= '(Edit|edt|Memo|mmo|Combo|cbo|cmb|Input|Query|Param)';
  Result.WeakSeverityDrop := True;
  Result.MaxPathsPerSink  := DEFAULT_PATHS;
  Result.SecondOrder      := False;
end;

function TTaintStats.ToLine: string;
begin
  Result:= Format('taint: sinks %d, keys %d, rows read %d, library hops %d, hits %d, partial keys %d, depth caps %d, %d ms',
    [Sinks, Keys, RowsRead, LibraryHops, Hits, PartialKeys, DepthCaps, ElapsedMs]);
end;

{ ---- TTaintRules ------------------------------------------------------------- }

class function TTaintRules.LoadConfig(const ARulesDir: string; const AOverrides: TArray<string>): TTaintConfig;
var
  Dir    : string;
  Fn     : string;
  Obj    : TJSONObject;
  Disable: TArray<string>;
  Text   : string;
  Missing: string;
  Srcs   : TArray<TTaintSourceEntry>;
  Snks   : TArray<TTaintSinkEntry>;
  Prps   : TArray<TTaintPropagatorEntry>;
  Sans   : TArray<TTaintSanitizerEntry>;
  Src    : TTaintSourceEntry;
  Snk    : TTaintSinkEntry;
  Prp    : TTaintPropagatorEntry;
  San    : TTaintSanitizerEntry;
begin
  Result := TTaintConfig.Defaults;
  Disable:= nil;
  Missing:= '';
  Dir:= if ARulesDir <> '' then ARulesDir else TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), 'rules');
  for Fn in TArray<string>.Create(FILE_SOURCES, FILE_SINKS, FILE_PROPS) do
  begin
    if not TFile.Exists(TPath.Combine(Dir, Fn)) then
    begin
      Missing:= Missing + IfThen(Missing <> '', ', ') + Fn;
      Continue;
    end;
    Obj:= ParseObject(TFile.ReadAllText(TPath.Combine(Dir, Fn), TEncoding.UTF8), Fn);
    try
      AppendEntries(Obj, Result, Disable, Fn);
    finally
      Obj.Free;
    end;
  end;
  if (Missing <> '') and not GMissingNoted then
  begin
    GMissingNoted:= True;
    Writeln(ErrOutput, 'taint: catalogue file(s) not found in ' + Dir + ': ' + Missing +
      ' -- the taint rules see only what the config adds');
  end;
  for Text in AOverrides do
  begin
    Obj:= ParseObject(Text, 'the "taint" object of the lint config');
    try
      AppendEntries(Obj, Result, Disable, 'the lint config');
      ApplyScalars(Obj, Result);
    finally
      Obj.Free;
    end;
  end;
  Srcs:= nil;
  for Src in Result.Sources do
    if (Src.Enabled or Result.SecondOrder) and not InStrs(Src.Id, Disable) then Srcs:= Srcs + [Src];
  Snks:= nil;
  for Snk in Result.Sinks do
    if not InStrs(Snk.Id, Disable) then Snks:= Snks + [Snk];
  Prps:= nil;
  for Prp in Result.Propagators do
    if not InStrs(Prp.Name, Disable) then Prps:= Prps + [Prp];
  Sans:= nil;
  for San in Result.Sanitizers do
    if not InStrs(San.Name, Disable) then Sans:= Sans + [San];
  Result.Sources    := Srcs;
  Result.Sinks      := Snks;
  Result.Propagators:= Prps;
  Result.Sanitizers := Sans;
end;

class function TTaintRules.Check(const AStore, ALibStore: ISymbolStore; const AScopeFileIds: TArray<Int64>;
                                 const ACfg: TTaintConfig; out AStats: TTaintStats): TArray<TLintFinding>;
var
  W : TTaintWalker;
  Sw: TStopwatch;
begin
  AStats:= Default(TTaintStats);
  Result:= nil;
  if (AStore = nil) or not AStore.HasDataFlows then
  begin
    AStats.StaleIndex:= True;
    Exit;
  end;
  Sw:= TStopwatch.StartNew;
  W:= TTaintWalker.Create(AStore, ALibStore, ACfg);
  try
    Result:= W.Run(AScopeFileIds);
    AStats:= W.Stats;
  finally
    W.Free;
  end;
  AStats.ElapsedMs:= Sw.ElapsedMilliseconds;
end;

{ ---- TTaintWalker -------------------------------------------------------------- }

constructor TTaintWalker.Create(const AStore, ALibStore: ISymbolStore; const ACfg: TTaintConfig);
begin
  inherited Create;
  FStores[STORE_PROJECT]:= AStore;
  FStores[STORE_LIB    ]:= ALibStore;
  FCfg         := ACfg;
  FMemo        := TDictionary<string, TMemoEntry>.Create;
  FStack       := TDictionary<string, Boolean>.Create;
  FSites       := TDictionary<string, Boolean>.Create;
  FRefs        := TDictionary<string, TArray<TReference>>.Create;
  FRefFiles    := TDictionary<string, Boolean>.Create;
  FEdges       := TDictionary<string, TArray<TCallEdge>>.Create;
  FEdgeRoutines:= TDictionary<string, Boolean>.Create;
  FSyms        := TDictionary<string, TSymbol>.Create;
  FPaths       := TDictionary<string, string>.Create;
  FLines       := TDictionary<string, TArray<string>>.Create;
  FRoutineRows := TDictionary<string, TArray<TDataFlowRow>>.Create;
  FMembers     := nil;
  FProjNames   := TDictionary<string, Boolean>.Create;
  FTypeIs      := TDictionary<string, Boolean>.Create;
  if FCfg.WeakReceiverRegex <> '' then FWeakRegex:= TRegEx.Create(FCfg.WeakReceiverRegex, [roIgnoreCase]);
end;

destructor TTaintWalker.Destroy;
begin
  FMemo.Free;
  FStack.Free;
  FSites.Free;
  FRefs.Free;
  FRefFiles.Free;
  FEdges.Free;
  FEdgeRoutines.Free;
  FSyms.Free;
  FPaths.Free;
  FLines.Free;
  FRoutineRows.Free;
  FMembers.Free;
  FProjNames.Free;
  FTypeIs.Free;
  inherited Destroy;
end;

function TTaintWalker.Sym(AStore: Integer; AId: Int64): TSymbol;
var
  K: string;
begin
  if AId <= 0 then Exit(Default(TSymbol));
  K:= Format('%d|%d', [AStore, AId]);
  if FSyms.TryGetValue(K, Result) then Exit;
  Result:= FStores[AStore].GetSymbolById(AId);
  FSyms.Add(K, Result);
end;

function TTaintWalker.PathOf(AStore: Integer; AFileId: Int64): string;
var
  K: string;
begin
  K:= Format('%d|%d', [AStore, AFileId]);
  if FPaths.TryGetValue(K, Result) then Exit;
  Result:= FStores[AStore].GetFilePath(AFileId);
  FPaths.Add(K, Result);
end;

{ The argument list of the call whose name starts at (ALine, ACol), as written and
  trimmed; '' when the file is unreadable or the list does not close on that line. }
function TTaintWalker.CallArgText(AStore: Integer; AFileId: Int64; ALine, ACol: Integer): string;
var
  K    : string;
  Lines: TArray<string>;
  Path : string;
  S    : string;
  P    : Integer;
  Start: Integer;
  Depth: Integer;
  InStr: Boolean;
begin
  Result:= '';
  K:= Format('%d|%d', [AStore, AFileId]);
  if not FLines.TryGetValue(K, Lines) then
  begin
    Lines:= nil;
    Path := PathOf(AStore, AFileId);
    if (Path <> '') and TFile.Exists(Path) then Lines:= TFile.ReadAllLines(Path);
    FLines.Add(K, Lines);
  end;
  if (ALine < 1) or (ALine > Length(Lines)) or (ACol < 1) then Exit;
  S:= Lines[ALine - 1];
  P:= ACol;
  while (P <= Length(S)) and CharInSet(S[P], ['A'..'Z', 'a'..'z', '0'..'9', '_', '.']) do Inc(P);
  while (P <= Length(S)) and (S[P] = ' ') do Inc(P);
  if (P > Length(S)) or (S[P] <> '(') then Exit;
  Start:= P + 1;
  Depth:= 0;
  InStr:= False;
  while P <= Length(S) do
  begin
    if S[P] = '''' then InStr:= not InStr
    else if (not InStr) and (S[P] = '(') then Inc(Depth)
    else if (not InStr) and (S[P] = ')') then
    begin
      Dec(Depth);
      if Depth = 0 then Exit(Trim(Copy(S, Start, P - Start)));
    end;
    Inc(P);
  end;
end;

function TTaintWalker.ShortName(AStore: Integer; const ASym: TSymbol): string;
var
  P: TSymbol;
begin
  Result:= ASym.Name;
  P:= Sym(AStore, ASym.ParentId);
  if P.Kind in [skClass, skRecord, skInterface] then Result:= P.Name + '.' + ASym.Name;
end;

function TTaintWalker.RefsAt(AStore: Integer; AFileId: Int64; ALine, ACol: Integer): TArray<TReference>;
var
  FileKey: string;
  K : string;
  R : TReference;
  L : TArray<TReference>;
begin
  FileKey:= Format('%d|%d', [AStore, AFileId]);
  if not FRefFiles.ContainsKey(FileKey) then
  begin
    FRefFiles.Add(FileKey, True);
    for R in FStores[AStore].GetReferencesFromFile(AFileId) do
    begin
      K:= Format('%s|%d|%d', [FileKey, R.StartLine, R.StartCol]);
      if not FRefs.TryGetValue(K, L) then L:= nil;
      FRefs.AddOrSetValue(K, L + [R]);
    end;
  end;
  if not FRefs.TryGetValue(Format('%s|%d|%d', [FileKey, ALine, ACol]), Result) then Result:= nil;
end;

function TTaintWalker.EdgesOf(AStore: Integer; AEnclosing, ARefId: Int64): TArray<TCallEdge>;  // dl:ok duplicate-code@5a40 -- REVIEWED 2026-10-27: same load-once-then-group shape as RefsAt over a different reader and element type (TCallEdge vs TReference); a generic helper would need a reader callback per call for two 15-line caches
var
  RK: string;
  K : string;
  E : TCallEdge;
  L : TArray<TCallEdge>;
begin
  RK:= Format('%d|%d', [AStore, AEnclosing]);
  if not FEdgeRoutines.ContainsKey(RK) then
  begin
    FEdgeRoutines.Add(RK, True);
    for E in FStores[AStore].GetCallEdgesFromSymbol(AEnclosing) do
    begin
      K:= Format('%d|%d', [AStore, E.RefId]);
      if not FEdges.TryGetValue(K, L) then L:= nil;
      FEdges.AddOrSetValue(K, L + [E]);
    end;
  end;
  if not FEdges.TryGetValue(Format('%d|%d', [AStore, ARefId]), Result) then Result:= nil;
end;

{ member_accesses of the PROJECT store (a qualified field/property read), loaded
  once; the library store is never dumped (its table is millions of rows). }
function TTaintWalker.MemberOf(ARefId: Int64): Int64;
var
  E: TCallEdge;
begin
  if FMembers = nil then
  begin
    FMembers:= TDictionary<Int64, Int64>.Create;
    for E in FStores[STORE_PROJECT].DumpAllMemberAccesses do
      FMembers.AddOrSetValue(E.RefId, E.TargetSymbolId);
  end;
  if not FMembers.TryGetValue(ARefId, Result) then Result:= 0;
end;

function TTaintWalker.RowsOf(AStore: Integer; ARoutine: Int64; const AKind: string): TArray<TDataFlowRow>;
var
  K: string;
begin
  K:= Format('%d|%d|%s', [AStore, ARoutine, AKind]);
  if FRoutineRows.TryGetValue(K, Result) then Exit;
  Result:= FStores[AStore].GetDataFlowsOf(ARoutine, AKind);
  Inc(FStats.RowsRead, Length(Result));
  FRoutineRows.Add(K, Result);
end;

function TTaintWalker.ArgRowsAt(AStore: Integer; const X: TSymbol; AFileId: Int64; ALine, ACol: Integer;
                                const AIdx: TArray<Integer>): TArray<TDataFlowRow>;
var
  Row: TDataFlowRow;
begin
  Result:= nil;
  for Row in RowsOf(AStore, X.Id, DF_DST_ARG) do
    if (Row.DstLine = ALine) and (Row.DstCol = ACol) and (Row.FileId = AFileId) and InInts(Row.DstIndex, AIdx) then
      Result:= Result + [Row];
end;

function TTaintWalker.IsRoutine(const S: TSymbol): Boolean;
begin
  Result:= S.Kind in [skProcedure, skFunction, skMethod, skConstructor, skDestructor];
end;

function TTaintWalker.ProjectHasRoutine(const AName: string): Boolean;
var
  S: TSymbol;
  K: string;
begin
  K:= LowerCase(AName);
  if FProjNames.TryGetValue(K, Result) then Exit;
  Result:= False;
  for S in FStores[STORE_PROJECT].FindSymbolsByExactName(AName) do
    if IsRoutine(S) then
    begin
      Result:= True;
      Break;
    end;
  FProjNames.Add(K, Result);
end;

{ The declared type of an identifier at a site in routine X: a local or parameter
  of X, then a field of X's class or an ancestor, then a unit-level variable with a
  unique name. '' when none of them answers. }
function TTaintWalker.DeclaredTypeOf(AStore: Integer; const X: TSymbol; const AIdent: string): string;
var
  C  : TSymbol;
  P  : TSymbol;
  Anc: TTypeAncestor;
  Hit: TSymbol;
  N  : Integer;
  S  : TSymbol;
begin
  Result:= '';
  if AIdent = '' then Exit;
  C:= FStores[AStore].FindChildSymbolByName(X.Id, AIdent);
  if C.Id > 0 then Exit(Trim(C.Signature));
  P:= Sym(AStore, X.ParentId);
  if P.Kind in [skClass, skRecord] then
  begin
    C:= FStores[AStore].FindChildSymbolByName(P.Id, AIdent);
    if (C.Id > 0) and (C.Kind in [skField, skProperty, skVarDecl]) then Exit(Trim(C.Signature));
    for Anc in FStores[AStore].GetTransitiveAncestors(P.Id) do
      if Anc.Resolved and (Anc.SymbolId > 0) then
      begin
        C:= FStores[AStore].FindChildSymbolByName(Anc.SymbolId, AIdent);
        if (C.Id > 0) and (C.Kind in [skField, skProperty]) then Exit(Trim(C.Signature));
      end;
  end;
  N:= 0;
  Hit:= Default(TSymbol);
  for S in FStores[AStore].FindSymbolsByExactName(AIdent) do
    if S.Kind = skVarDecl then
    begin
      Inc(N);
      Hit:= S;
    end;
  if N = 1 then Result:= Trim(Hit.Signature);
end;

function TTaintWalker.TypeIs(AStore: Integer; AFileId: Int64; const AType, AWanted: string): Boolean;
var
  K: string;
  T: string;
begin
  T:= LastSeg(AType);
  if (T = '') or (AWanted = '') then Exit(False);
  if SameText(T, AWanted) then Exit(True);
  K:= LowerCase(T + '|' + AWanted);
  if FTypeIs.TryGetValue(K, Result) then Exit;
  Result:= FStores[STORE_PROJECT].IsDescendantOf(T, AWanted, if AStore = STORE_PROJECT then AFileId else 0);
  if (not Result) and (FStores[STORE_LIB] <> nil) then
    Result:= FStores[STORE_LIB].IsDescendantOf(T, AWanted, 0);
  FTypeIs.Add(K, Result);
end;

function TTaintWalker.Resolve(AStore: Integer; const X: TSymbol; AFileId: Int64; ALine, ACol: Integer;
                              const AName: string): TResolved;
var
  Refs: TArray<TReference>;
  R   : TReference;
  E   : TCallEdge;
  M   : Int64;
  Seg : string;
begin
  Result:= Default(TResolved);
  Result.Store:= AStore;
  Result.Name := AName;
  Refs:= RefsAt(AStore, AFileId, ALine, ACol);
  for R in Refs do
    if (R.ReceiverText <> '') and (Result.Receiver = '') then Result.Receiver:= R.ReceiverText;
  for R in Refs do
  begin
    if Result.Name = '' then Result.Name:= R.NameText;
    for E in EdgesOf(AStore, X.Id, R.Id) do
      if (E.TargetSymbolId > 0) and (SameText(E.Confidence, CONF_CERTAIN) or FCfg.FollowAmbiguous) then
      begin
        Result.Found:= True;
        Result.Sym  := Sym(AStore, E.TargetSymbolId);
        Result.Weak := not SameText(E.Confidence, CONF_CERTAIN);
        Break;
      end;
    if Result.Found then Break;
  end;
  if (not Result.Found) and (AStore = STORE_PROJECT) then
    for R in Refs do
    begin
      M:= MemberOf(R.Id);
      if M > 0 then
      begin
        Result.Found:= True;
        Result.Sym  := Sym(AStore, M);
        Break;
      end;
    end;
  if not Result.Found then
    for R in Refs do
      if (R.SymbolId > 0) and not SameText(R.Kind, REF_TYPE_USE) then
      begin
        Result.Found:= True;
        Result.Sym  := Sym(AStore, R.SymbolId);
        Break;
      end;
  { The receiver's own type: only a single identifier can be looked up (a dotted
    receiver's type is a member chain this walk does not type). }
  Seg:= Result.Receiver;
  if (Seg <> '') and (not Seg.Contains('.')) then
  begin
    Result.RecvType:= DeclaredTypeOf(AStore, X, Seg);
    if (Result.RecvType = '') and LooksLikeTypeName(Seg) then Result.RecvType:= Seg;
  end;
end;

function TTaintWalker.NameMatches(const AEntry: string; const R: TResolved; AFileId: Int64; out AWeak: Boolean): Boolean;
var
  Owner: string;
  P    : TSymbol;
begin
  AWeak:= False;
  if not SameText(LastSeg(AEntry), R.Name) then Exit(False);
  Owner:= OwnerSeg(AEntry);
  if Owner = '' then
  begin
    { A resolved PROJECT routine of this name is project code, walked, not catalogued. }
    if R.Found and (R.Store = STORE_PROJECT) and IsRoutine(R.Sym) then Exit(False);
    AWeak:= (not R.Found) and ProjectHasRoutine(R.Name);
    Exit(True);
  end;
  if R.Found then
  begin
    P:= Sym(R.Store, R.Sym.ParentId);
    if (P.Kind in [skClass, skRecord, skInterface]) and TypeIs(R.Store, AFileId, P.Name, Owner) then Exit(True);
  end;
  Result:= (R.RecvType <> '') and TypeIs(STORE_PROJECT, AFileId, R.RecvType, Owner);
end;

function TTaintWalker.Loc(AStore: Integer; const X: TSymbol; AFileId: Int64; ALine, ACol: Integer;
                          const ANote: string): TLintLocation;
begin
  Result:= Default(TLintLocation);
  Result.FilePath:= PathOf(AStore, AFileId);
  Result.Line    := ALine;
  Result.Col     := ACol;
  Result.Routine := X.QualifiedName;
  Result.Note    := ANote;
end;

function TTaintWalker.SourceHit(AStore: Integer; const X: TSymbol; const ARow: TDataFlowRow;
                                const AName, AKind, ANote: string; AWeak: Boolean): THit;
begin
  Result:= Default(THit);
  Result.Key    := Format('%s|%d|%d', [PathOf(AStore, ARow.FileId), ARow.SrcLine, ARow.SrcCol]);
  Result.SrcName:= AName;
  Result.SrcKind:= AKind;
  Result.Weak   := AWeak;
  Result.Path   := [Loc(AStore, X, ARow.FileId, ARow.SrcLine, ARow.SrcCol, 'source ' + AName + ANote)];
end;

procedure TTaintWalker.AddHit(var AAcc: TSummary; const AHit: THit);
var
  I: Integer;
begin
  for I:= 0 to High(AAcc.Hits) do
    if AAcc.Hits[I].Key = AHit.Key then
    begin
      { keep the better witness: certain over weak, then the shorter path }
      if (AAcc.Hits[I].Weak and not AHit.Weak)
         or ((AAcc.Hits[I].Weak = AHit.Weak) and (Length(AHit.Path) < Length(AAcc.Hits[I].Path))) then
        AAcc.Hits[I]:= AHit;
      Exit;
    end;
  if Length(AAcc.Hits) >= HIT_CAP then
  begin
    FCapHit:= True;
    Exit;
  end;
  AAcc.Hits:= AAcc.Hits + [AHit];
end;

procedure TTaintWalker.AddParam(var AAcc: TSummary; AIdx: Integer);
begin
  if (AIdx >= 0) and not InInts(AIdx, AAcc.Params) then AAcc.Params:= AAcc.Params + [AIdx];
end;

procedure TTaintWalker.Merge(var AAcc: TSummary; const AAdd: TSummary; AWithParams: Boolean);
var
  H: THit;
  P: Integer;
begin
  for H in AAdd.Hits do AddHit(AAcc, H);
  if AWithParams then
    for P in AAdd.Params do AddParam(AAcc, P);
end;

procedure TTaintWalker.MergeHop(var AAcc: TSummary; const AAdd: TSummary; const AHop: TLintLocation;
                                AWeak: Boolean; AFieldInc: Integer);
var
  H: THit;
  C: THit;
begin
  for H in AAdd.Hits do
  begin
    C:= H;
    C.Path  := Copy(H.Path) + [AHop];
    C.Weak  := H.Weak or AWeak;
    C.Fields:= H.Fields + AFieldInc;
    AddHit(AAcc, C);
  end;
end;

{ The native-stack guard, whatever max_depth says: memo keys in flight plus nested
  EvalRows calls. At TAINT_EVAL_DEPTH_CAP the branch answers unknown (no hit), the
  sink is partial, the stats line counts it and DRAGLINT_DEBUG names the first one. }
function TTaintWalker.DepthCapped(const AWhere: string): Boolean;
begin
  Result:= FStack.Count + FEvalDepth >= TAINT_EVAL_DEPTH_CAP;
  if not Result then Exit;
  FCapHit:= True;
  Inc(FStats.DepthCaps);
  if (FStats.DepthCaps = 1) and (GetEnvironmentVariable('DRAGLINT_DEBUG') <> '') then
    Writeln(ErrOutput, Format('taint: walk depth cap %d reached at %s -- that branch is unknown',
      [TAINT_EVAL_DEPTH_CAP, AWhere]));
end;

{ Memo protocol. True = the caller computes the key (seeded in ASum with the
  previous round's partial answer) and must call Leave. False = ASum is the
  answer: a final memo entry, the partial set of a key on the stack (a cycle),
  or empty at the depth cap. }
function TTaintWalker.Enter(const AKey: string; out ASum: TSummary; out AStartCycles: Integer): Boolean;
var
  E   : TMemoEntry;
  Have: Boolean;
begin
  ASum:= Default(TSummary);
  AStartCycles:= FCycleReads;
  Have:= FMemo.TryGetValue(AKey, E);
  if FStack.ContainsKey(AKey) then
  begin
    Inc(FCycleReads);
    if Have then ASum:= E.Sum;
    Exit(False);
  end;
  if Have and ((not E.Partial) or (E.Round = FRound)) then
  begin
    ASum:= E.Sum;
    Exit(False);
  end;
  if (FStack.Count >= FCfg.MaxDepth) or DepthCapped(AKey) then
  begin
    FCapHit:= True;
    Inc(FCycleReads);   { the caller's answer is incomplete: re-query next round }
    Exit(False);
  end;
  if Have then ASum:= E.Sum
  else Inc(FStats.Keys);
  FStack.Add(AKey, True);
  Result:= True;
end;

procedure TTaintWalker.Leave(const AKey: string; const ASum: TSummary; AStartCycles: Integer);
var
  E  : TMemoEntry;
  Old: TMemoEntry;
begin
  FStack.Remove(AKey);
  E.Sum    := ASum;
  E.Partial:= FCycleReads > AStartCycles;
  E.Round  := FRound;
  if FMemo.TryGetValue(AKey, Old) then
  begin
    if (Length(Old.Sum.Hits) <> Length(ASum.Hits)) or (Length(Old.Sum.Params) <> Length(ASum.Params)) then
      FChanged:= True;
  end
  else if E.Partial then
    FChanged:= True;
  FMemo.AddOrSetValue(AKey, E);
end;

function TTaintWalker.EvalRows(AStore: Integer; const X: TSymbol; const ARows: TArray<TDataFlowRow>): TSummary;
var
  Row    : TDataFlowRow;
  SiteKey: string;
begin
  Result:= Default(TSummary);
  if DepthCapped(X.QualifiedName) then Exit;
  Inc(FEvalDepth);
  try
    for Row in ARows do
      if Row.SrcKind = DF_SRC_PARAM then AddParam(Result, Row.SrcIndex)
      else if (Row.SrcKind = DF_SRC_REF) or (Row.SrcKind = DF_SRC_ARGOUT) then
      begin
        { a call site already being evaluated on this walk (a loop-carried
          S := F(S) makes F's argument derive from F's own result): it adds
          nothing the other rows do not -- the least fixpoint -- so skip it, and
          count it as a cycle read so an enclosing memo key is re-queried as partial }
        SiteKey:= Format('%d|%d|%d|%d|%s|%d', [AStore, X.Id, Row.SrcLine, Row.SrcCol, Row.SrcKind, Row.SrcIndex]);
        if FSites.ContainsKey(SiteKey) then
        begin
          Inc(FCycleReads);
          Continue;
        end;
        FSites.Add(SiteKey, True);
        try
          if Row.SrcKind = DF_SRC_REF then Merge(Result, EvalRef(AStore, X, Row), True)
          else Merge(Result, EvalArgOut(AStore, X, Row), True);
        finally
          FSites.Remove(SiteKey);
        end;
      end
      else if Row.SrcKind = DF_SRC_FIELD then Merge(Result, FieldSummary(AStore, Row), False)
      else if Row.SrcKind = DF_SRC_GLOBAL then Merge(Result, GlobalSummary(AStore, Row), False);
  finally
    Dec(FEvalDepth);
  end;
end;

{ A src 'ref' row: the value of the call / read at (SrcLine, SrcCol) inside X. }
function TTaintWalker.EvalRef(AStore: Integer; const X: TSymbol; const ARow: TDataFlowRow): TSummary;
var
  R   : TResolved;
  Src : TTaintSourceEntry;
  San : TTaintSanitizerEntry;
  Prp : TTaintPropagatorEntry;
  Weak: Boolean;
  I   : Integer;
begin
  Result:= Default(TSummary);
  { 0. a bare read of a field the owner INHERITS: the extractor only classifies the
    owner's own fields (T1 contract), so an ancestor's field arrives as a ref by
    name and is resolved here -- then it is a field read like any other. }
  if IsInheritedField(AStore, X, ARow.SrcName) then
  begin
    var FRow:= ARow;
    FRow.SrcKind:= DF_SRC_FIELD;
    Exit(FieldSummary(AStore, FRow));
  end;
  R:= Resolve(AStore, X, ARow.FileId, ARow.SrcLine, ARow.SrcCol, ARow.SrcName);
  { a. a catalogued source }
  for Src in FCfg.Sources do
    if NameMatches(Src.Name, R, ARow.FileId, Weak) then
    begin
      { a source this rule trusts (ParamStr under path-traversal), or a trusted argument
        (ParamStr(0)): clean, not walked into }
      if (Src.Categories <> nil) and not InStrs(FCat, Src.Categories) then Exit;
      if (Src.TrustedArgs <> nil) and InStrs(CallArgText(AStore, ARow.FileId, ARow.SrcLine, ARow.SrcCol), Src.TrustedArgs) then Exit;
      AddHit(Result, SourceHit(AStore, X, ARow,
        if OwnerSeg(Src.Name) <> '' then OwnerSeg(Src.Name) + '.' + LastSeg(Src.Name) else LastSeg(Src.Name),
        Src.Kind, '', Weak or R.Weak or SameText(Src.Confidence, CONF_WEAK)));
      Exit;
    end;
  { e. an unresolved `X.Text` on a receiver named like an input control }
  if (not R.Found) and (FCfg.WeakReceiverRegex <> '') and SameText(R.Name, WEAK_TEXT_LEAF) and (R.Receiver <> '')
     and FWeakRegex.IsMatch(R.Receiver) then
  begin
    AddHit(Result, SourceHit(AStore, X, ARow, R.Receiver + '.' + R.Name, KIND_READ, ' (weak: receiver name)', True));
    Exit;
  end;
  { b. a sanitizer for this category stops the branch }
  for San in FCfg.Sanitizers do
    if (InStrs(FCat, San.Sanitizes) or InStrs(TAINT_CAT_ALL, San.Sanitizes)) and NameMatches(San.Name, R, ARow.FileId, Weak) then
      Exit;
  { c. a propagator: the listed arguments at this site (not a path hop: the value
    stays in the same routine) }
  for Prp in FCfg.Propagators do
    if SameText(Prp.ToSlot, SLOT_RESULT) and NameMatches(Prp.Name, R, ARow.FileId, Weak) then
    begin
      Result:= EvalRows(AStore, X, ArgRowsAt(AStore, X, ARow.FileId, ARow.SrcLine, ARow.SrcCol, Prp.Args));
      if Weak then
        for I:= 0 to High(Result.Hits) do Result.Hits[I].Weak:= True;
      Exit;
    end;
  { d. a routine whose own facts say what its Result derives from }
  Result:= CallSummary(AStore, X, ARow, R, SLOT_RESULT, -1);
end;

{ The value a call at ARow's source site hands back through ASlot ('result', or
  'outparam' AOutIdx): the callee's summary, its parameters mapped onto the
  argument rows at the site. Unresolved project calls try the library by name. }
function TTaintWalker.CallSummary(AStore: Integer; const X: TSymbol; const ARow: TDataFlowRow; const R: TResolved;
                                  const ASlot: string; AOutIdx: Integer): TSummary;
var
  Targets: TArray<TSymbol>;
  Cand   : TArray<TSymbol>;
  TStore : Integer;
  T      : TSymbol;
  S      : TSymbol;
  Sub    : TSummary;
  Arg    : TSummary;
  P      : Integer;
  Q      : Integer;
  Weak   : Boolean;
  Hop    : TLintLocation;
begin
  Result:= Default(TSummary);
  Targets:= nil;
  TStore := R.Store;
  Weak   := R.Weak;
  if R.Found and IsRoutine(R.Sym) then
    Targets:= [R.Sym] + Implementations(R.Store, R.Sym)
  else if (not R.Found) and (AStore = STORE_PROJECT) and (FStores[STORE_LIB] <> nil) and (R.Name <> '') then
  begin
    { no project binding: the library by name (a unique routine with a body, or the
      one owned by the receiver's type) }
    Cand:= nil;
    for S in FStores[STORE_LIB].FindSymbolsByExactName(R.Name) do
      if IsRoutine(S) and (S.ImplStartLine > 0) then Cand:= Cand + [S];
    if (Length(Cand) > 1) and (R.RecvType <> '') then
    begin
      Targets:= Cand;
      Cand:= nil;
      for S in Targets do
        if SameText(Sym(STORE_LIB, S.ParentId).Name, LastSeg(R.RecvType)) then Cand:= Cand + [S];
      Targets:= nil;
    end;
    if Length(Cand) = 1 then
    begin
      Targets:= Cand;
      TStore := STORE_LIB;
      Weak   := Weak or ProjectHasRoutine(R.Name);
    end;
  end;
  for T in Targets do
  begin
    if TStore = STORE_LIB then
    begin
      if FLibDepth >= FCfg.LibDepth then Continue;
      Inc(FLibDepth);
      Inc(FStats.LibraryHops);
    end;
    try
      Sub:= SlotSummary(TStore, T, ASlot, AOutIdx);
    finally
      if TStore = STORE_LIB then Dec(FLibDepth);
    end;
    Hop:= Loc(AStore, X, ARow.FileId, ARow.SrcLine, ARow.SrcCol,
      (if ASlot = SLOT_RESULT then 'through ' else Format('out param %d of ', [AOutIdx])) + ShortName(TStore, T));
    MergeHop(Result, Sub, Hop, Weak, 0);
    { a parameter that flows to the slot: the caller's argument, through this callee (a hop) }
    for P in Sub.Params do
    begin
      Arg:= EvalRows(AStore, X, ArgRowsAt(AStore, X, ARow.FileId, ARow.SrcLine, ARow.SrcCol, [P]));
      MergeHop(Result, Arg, Hop, Weak, 0);
      for Q in Arg.Params do AddParam(Result, Q);
    end;
  end;
end;

function TTaintWalker.SlotSummary(AStore: Integer; const T: TSymbol; const ASlot: string; AOutIdx: Integer): TSummary;
var
  Key : string;
  Cyc : Integer;
  Rows: TArray<TDataFlowRow>;
  Row : TDataFlowRow;
begin
  Key:= Format('%s|%s|%d|%d|%d', [FCat, ASlot, AStore, T.Id, AOutIdx]);
  if not Enter(Key, Result, Cyc) then Exit;
  try
    Rows:= nil;
    for Row in RowsOf(AStore, T.Id, ASlot) do
      if (ASlot = SLOT_RESULT) or (Row.DstIndex = AOutIdx) then Rows:= Rows + [Row];
    Merge(Result, EvalRows(AStore, T, Rows), True);
  finally
    Leave(Key, Result, Cyc);
  end;
end;

{ A src 'argout' row: a variable passed at position SrcIndex of the earlier call at
  (SrcLine, SrcCol) carries what the callee writes to that var/out parameter. }
function TTaintWalker.EvalArgOut(AStore: Integer; const X: TSymbol; const ARow: TDataFlowRow): TSummary;
var
  R   : TResolved;
  Src : TTaintSourceEntry;
  Prp : TTaintPropagatorEntry;
  Weak: Boolean;
begin
  Result:= Default(TSummary);
  R:= Resolve(AStore, X, ARow.FileId, ARow.SrcLine, ARow.SrcCol, ARow.SrcName);
  { a source CALL fills its out arguments (ReadLn(S)) }
  for Src in FCfg.Sources do
    if SameText(Src.Kind, KIND_CALL) and NameMatches(Src.Name, R, ARow.FileId, Weak) then
    begin
      if (Src.Categories <> nil) and not InStrs(FCat, Src.Categories) then Exit;
      AddHit(Result, SourceHit(AStore, X, ARow, LastSeg(Src.Name), Src.Kind, ' (out argument)',
        Weak or R.Weak or SameText(Src.Confidence, CONF_WEAK)));
      Exit;
    end;
  for Prp in FCfg.Propagators do
    if SameText(Prp.ToSlot, SLOT_OUTPARAM) and (Prp.OutIndex = ARow.SrcIndex) and NameMatches(Prp.Name, R, ARow.FileId, Weak) then
      Exit(EvalRows(AStore, X, ArgRowsAt(AStore, X, ARow.FileId, ARow.SrcLine, ARow.SrcCol, Prp.Args)));
  Result:= CallSummary(AStore, X, ARow, R, SLOT_OUTPARAM, ARow.SrcIndex);
end;

{ Overrides of a virtual method T in its owner's descendants: a call through the
  base can land in any of them. }
function TTaintWalker.Implementations(AStore: Integer; const T: TSymbol): TArray<TSymbol>;
var
  Cls: TSymbol;
  Dn : string;
  C  : TSymbol;
  M  : TSymbol;
begin
  Result:= nil;
  if not T.IsVirtual then Exit;
  Cls:= Sym(AStore, T.ParentId);
  if (Cls.Kind not in [skClass, skInterface]) then Exit;
  for Dn in FStores[AStore].FindDescendantNames(Cls.Name) do
    for C in FStores[AStore].FindSymbolsByExactName(LastSeg(Dn)) do
      if C.Kind = skClass then
      begin
        M:= FStores[AStore].FindChildSymbolByName(C.Id, T.Name);
        if (M.Id > 0) and (M.Id <> T.Id) and IsRoutine(M) then Result:= Result + [M];
      end;
end;

{ The methods an override X overrides (callers of the base reach X by dispatch). }
function TTaintWalker.BaseMethods(const X: TSymbol): TArray<TSymbol>;
var
  Cls: TSymbol;
  Anc: TTypeAncestor;
  M  : TSymbol;
begin
  Result:= nil;
  if Pos(DIR_OVERRIDE, LowerCase(X.Directives)) = 0 then Exit;
  Cls:= Sym(STORE_PROJECT, X.ParentId);
  for Anc in FStores[STORE_PROJECT].GetTransitiveAncestors(Cls.Id) do
    if Anc.Resolved and (Anc.SymbolId > 0) then
    begin
      M:= FStores[STORE_PROJECT].FindChildSymbolByName(Anc.SymbolId, X.Name);
      if (M.Id > 0) and IsRoutine(M) then Result:= Result + [M];
    end;
end;

{ Parameter AIdx of project routine X as a source: every caller's argument AIdx. }
function TTaintWalker.CallersParam(const X: TSymbol; AIdx: Integer): TSummary;
var
  Key   : string;
  Cyc   : Integer;
  Bases : TArray<TSymbol>;
  B     : TSymbol;
  Caller: TResolvedCaller;
  Seen  : TDictionary<string, Boolean>;
  SeenK : string;
  C     : TSymbol;
  Row   : TDataFlowRow;
  Hop   : TLintLocation;
begin
  Key:= Format('%s|param|%d|%d', [FCat, X.Id, AIdx]);
  if not Enter(Key, Result, Cyc) then Exit;
  Seen:= TDictionary<string, Boolean>.Create;
  try
    Bases:= [X] + BaseMethods(X);
    for B in Bases do
      for Caller in FStores[STORE_PROJECT].FindResolvedCallers(B.Id) do
      begin
        if Caller.EnclosingSymbolId <= 0 then Continue;
        if (not SameText(Caller.Confidence, CONF_CERTAIN)) and not FCfg.FollowAmbiguous then Continue;
        SeenK:= Format('%d|%d|%d', [B.Id, Caller.EnclosingSymbolId, Caller.CallSiteLine]);
        if Seen.ContainsKey(SeenK) then Continue;
        Seen.Add(SeenK, True);
        C:= Sym(STORE_PROJECT, Caller.EnclosingSymbolId);
        for Row in RowsOf(STORE_PROJECT, C.Id, DF_DST_ARG) do
          if (Row.DstLine = Caller.CallSiteLine) and (Row.DstIndex = AIdx) and SameText(Row.DstName, B.Name) then
          begin
            Hop:= Loc(STORE_PROJECT, C, Row.FileId, Row.DstLine, Row.DstCol,
              Format('argument %d of %s', [AIdx, ShortName(STORE_PROJECT, X)]));
            MergeHop(Result, Top(STORE_PROJECT, C, EvalRows(STORE_PROJECT, C, [Row])), Hop, False, 0);
          end;
      end;
  finally
    Seen.Free;
    Leave(Key, Result, Cyc);
  end;
end;

function TTaintWalker.Top(AStore: Integer; const X: TSymbol; const ASum: TSummary): TSummary;
var
  P: Integer;
begin
  Result:= Default(TSummary);
  Merge(Result, ASum, False);
  if AStore = STORE_PROJECT then
    for P in ASum.Params do Merge(Result, CallersParam(X, P), False);
end;

{ A src 'field' row: every writer of that field in the owner, its ancestors and
  descendants (object-insensitive by design). }
function TTaintWalker.FieldSummary(AStore: Integer; const ARow: TDataFlowRow): TSummary;
var
  Key   : string;
  Cyc   : Integer;
  Owners: TArray<Int64>;
  Cls   : TSymbol;
  Anc   : TTypeAncestor;
  Dn    : string;
  C     : TSymbol;
  W     : TDataFlowRow;
  WS    : TSymbol;
  Hop   : TLintLocation;
begin
  Key:= Format('%s|field|%d|%d|%s', [FCat, AStore, ARow.OwnerId, LowerCase(ARow.SrcName)]);
  if not Enter(Key, Result, Cyc) then Exit;
  try
    Owners:= [ARow.OwnerId];
    Cls:= Sym(AStore, ARow.OwnerId);
    if Cls.Id > 0 then
    begin
      for Anc in FStores[AStore].GetTransitiveAncestors(Cls.Id) do
        if Anc.Resolved and (Anc.SymbolId > 0) then Owners:= Owners + [Anc.SymbolId];
      for Dn in FStores[AStore].FindDescendantNames(Cls.Name) do
        for C in FStores[AStore].FindSymbolsByExactName(LastSeg(Dn)) do
          if C.Kind = skClass then Owners:= Owners + [C.Id];
    end;
    for W in FStores[AStore].GetFieldWriters(Owners, ARow.SrcName) do
    begin
      Inc(FStats.RowsRead);
      WS:= Sym(AStore, W.SymbolId);
      Hop:= Loc(AStore, WS, W.FileId, W.DstLine, W.DstCol,
        Format('via field %s.%s written in %s', [Cls.Name, ARow.SrcName, ShortName(AStore, WS)]));
      MergeHop(Result, Top(AStore, WS, EvalRows(AStore, WS, [W])), Hop, False, 1);
    end;
  finally
    Leave(Key, Result, Cyc);
  end;
end;

{ True when AName, read bare inside routine X, is a field X's class inherits: the
  class itself declares no member of that name (its own field would already be a
  'field' row; any other own member hides the ancestor's), and the NEAREST resolved
  ancestor declaring the name declares it as a field. }
function TTaintWalker.IsInheritedField(AStore: Integer; const X: TSymbol; const AName: string): Boolean;
var
  P  : TSymbol;
  C  : TSymbol;
  Anc: TTypeAncestor;
begin
  Result:= False;
  if (AName = '') or AName.Contains('.') or (X.ParentId <= 0) then Exit;
  P:= Sym(AStore, X.ParentId);
  if P.Kind <> skClass then Exit;
  if FStores[AStore].FindChildSymbolByName(P.Id, AName).Id > 0 then Exit;
  for Anc in FStores[AStore].GetTransitiveAncestors(P.Id) do
    if Anc.Resolved and (Anc.SymbolId > 0) then
    begin
      C:= FStores[AStore].FindChildSymbolByName(Anc.SymbolId, AName);
      if C.Id > 0 then Exit(C.Kind = skField);
    end;
end;

{ A src 'global' row: every writer of that unit variable. A writer in another file
  is weak when more than one unit declares a variable of that name. }
function TTaintWalker.GlobalSummary(AStore: Integer; const ARow: TDataFlowRow): TSummary;
var
  Key  : string;
  Cyc  : Integer;
  Decls: Integer;
  S    : TSymbol;
  W    : TDataFlowRow;
  WS   : TSymbol;
  Hop  : TLintLocation;
begin
  Key:= Format('%s|global|%d|%s', [FCat, AStore, LowerCase(ARow.SrcName)]);
  if not Enter(Key, Result, Cyc) then Exit;
  try
    Decls:= 0;
    for S in FStores[AStore].FindSymbolsByExactName(ARow.SrcName) do
      if S.Kind = skVarDecl then Inc(Decls);
    for W in FStores[AStore].GetGlobalWriters(ARow.SrcName, 0) do
    begin
      Inc(FStats.RowsRead);
      WS:= Sym(AStore, W.SymbolId);
      Hop:= Loc(AStore, WS, W.FileId, W.DstLine, W.DstCol,
        Format('via global %s written in %s', [ARow.SrcName, ShortName(AStore, WS)]));
      MergeHop(Result, Top(AStore, WS, EvalRows(AStore, WS, [W])), Hop, (W.FileId <> ARow.FileId) and (Decls > 1), 1);
    end;
  finally
    Leave(Key, Result, Cyc);
  end;
end;

{ The catalogue-only half of a sink match: name, kind, argument position, receiver suffix. }
function SinkShapeMatches(const AEntry: TTaintSinkEntry; const ARow: TDataFlowRow): Boolean;
var
  KindOk    : Boolean;
  ReceiverOk: Boolean;
begin
  KindOk:= if SameText(AEntry.Kind, KIND_WRITE) then ARow.DstKind = DF_DST_WRITE else (ARow.DstKind = DF_DST_ARG) and (Length(AEntry.Args) > 0) and InInts(ARow.DstIndex, AEntry.Args);
  ReceiverOk:= (AEntry.ReceiverSuffix = '') or EndsText(AEntry.ReceiverSuffix, ARow.DstReceiver);
  Result:= SameText(AEntry.Name, ARow.DstName) and KindOk and ReceiverOk;
end;

function TTaintWalker.SinkMatches(const AEntry: TTaintSinkEntry; const X: TSymbol; const ARow: TDataFlowRow;
                                  out AWeak: Boolean): Boolean;
var
  R: TResolved;
  P: TSymbol;
begin
  AWeak:= False;
  if not SinkShapeMatches(AEntry, ARow) then Exit(False);
  R:= Resolve(STORE_PROJECT, X, ARow.FileId, ARow.DstLine, ARow.DstCol, ARow.DstName);
  { a resolved PROJECT routine of that name is project code, not the catalogued API }
  if AEntry.TypeName = '' then Result:= not (R.Found and IsRoutine(R.Sym))
  else if R.Found and IsRoutine(R.Sym) then
  begin
    P:= Sym(STORE_PROJECT, R.Sym.ParentId);
    Result:= (P.Kind in [skClass, skRecord, skInterface]) and TypeIs(STORE_PROJECT, ARow.FileId, P.Name, AEntry.TypeName);
  end
  else if R.RecvType <> '' then Result:= TypeIs(STORE_PROJECT, ARow.FileId, R.RecvType, AEntry.TypeName)
  else
  begin
    { a typed sink is a member: a bare `Copy(S, 1, 2)` is never `TFile.Copy`; a member
      call on a receiver of unknown type matches by name only, reported weak }
    Result:= ARow.DstReceiver <> '';
    AWeak := Result;
  end;
end;
function TTaintWalker.EvalSink(const X: TSymbol; const ARows: TArray<TDataFlowRow>): TSummary;
var
  Rounds: Integer;
begin
  FChanged:= False;
  Inc(FRound);
  Result:= Top(STORE_PROJECT, X, EvalRows(STORE_PROJECT, X, ARows));
  { re-query while a partial (cycle-reached) key keeps growing }
  Rounds:= 1;
  while FChanged and (Rounds < FCfg.MaxRounds) do
  begin
    FChanged:= False;
    Inc(FRound);
    Merge(Result, Top(STORE_PROJECT, X, EvalRows(STORE_PROJECT, X, ARows)), False);
    Inc(Rounds);
  end;
  if FChanged then Inc(FStats.PartialKeys);
end;

{ The findings of one sink site and rule: certain before weak, shorter paths first,
  at most MaxPathsPerSink, the last one naming how many more there were. }
function TTaintWalker.Findings(const X: TSymbol; const ARow: TDataFlowRow; const ARule: string; AWeakSink: Boolean;
                               const AHits: TArray<THit>): TArray<TLintFinding>;
var
  Hits : TArray<THit>;
  J    : Integer;
  F    : TLintFinding;
  Weak : Boolean;
  L    : TLintLocation;
  Names: string;
  Prev : string;
  Hops : Integer;
begin
  Result:= nil;
  Hits:= Copy(AHits);
  TArray.Sort<THit>(Hits, TComparer<THit>.Construct(
    function(const A, B: THit): Integer
    begin
      Result:= Ord(A.Weak) - Ord(B.Weak);
      if Result = 0 then Result:= Length(A.Path) - Length(B.Path);
      if Result = 0 then Result:= CompareStr(A.Key, B.Key);
    end));
  for J:= 0 to High(Hits) do
  begin
    if J >= FCfg.MaxPathsPerSink then Break;
    F:= Default(TLintFinding);
    F.RuleId    := ARule;
    F.FileId    := ARow.FileId;
    F.FilePath  := PathOf(STORE_PROJECT, ARow.FileId);
    F.StartLine := ARow.DstLine;
    F.StartCol  := ARow.DstCol;
    F.EndLine   := ARow.DstLine;
    F.EndCol    := ARow.DstCol + Length(ARow.DstName);
    F.SymbolName:= X.Name;
    Weak:= Hits[J].Weak or AWeakSink;
    F.Severity:= RuleBaseSeverity(ARule);
    if Weak and FCfg.WeakSeverityDrop then F.Severity:= DropSeverity(F.Severity);
    F.Path:= Copy(Hits[J].Path) + [Loc(STORE_PROJECT, X, ARow.FileId, ARow.DstLine, ARow.DstCol, 'sink ' + ARow.DstName)];
    Names:= '';
    Prev := '';
    Hops := 0;
    for L in F.Path do
      if (L.Routine <> '') and not SameText(L.Routine, Prev) then
      begin
        Names:= Names + IfThen(Names <> '', ' -> ') + DisplayRoutine(L.Routine);
        Prev := L.Routine;
        Inc(Hops);
      end;
    F.Message:= Format('%s %s from %s (%s) via %s (%d hops, %d via fields/globals%s) -- %s',
      [TAINT_MSG_PREFIX, ARow.DstName, Hits[J].SrcName, Hits[J].SrcKind, Names, Hops - 1,
       Hits[J].Fields, IfThen(Weak, ', weak'), RuleCweText(ARule)]);
    if (J = FCfg.MaxPathsPerSink - 1) and (Length(Hits) > FCfg.MaxPathsPerSink) then
      F.Message:= F.Message + Format(' (+%d more paths)', [Length(Hits) - FCfg.MaxPathsPerSink]);
    Result:= Result + [F];
  end;
end;

function TTaintWalker.Run(const AScopeFileIds: TArray<Int64>): TArray<TLintFinding>;
var
  Fid     : Int64;
  Path    : string;
  S       : TSymbol;
  Rows    : TArray<TDataFlowRow>;
  Row     : TDataFlowRow;
  R2      : TDataFlowRow;
  Group   : TArray<TDataFlowRow>;
  Done    : TDictionary<string, Boolean>;
  SiteKey : string;
  Entry   : TTaintSinkEntry;
  Rules   : TArray<string>;
  WeakSink: TArray<Boolean>;
  Weak    : Boolean;
  I, K    : Integer;
  Sum     : TSummary;
  Routines: Integer;
begin
  Result  := nil;
  Routines:= 0;
  Done:= TDictionary<string, Boolean>.Create;
  try
    for Fid in AScopeFileIds do
    begin
      Path:= PathOf(STORE_PROJECT, Fid);
      if Path = '' then Continue;
      for S in FStores[STORE_PROJECT].FindSymbolsByFile(Path) do
      begin
        if not IsRoutine(S) or (S.ImplStartLine <= 0) then Continue;
        FSyms.AddOrSetValue(Format('%d|%d', [STORE_PROJECT, S.Id]), S);
        Inc(Routines);
        Rows:= RowsOf(STORE_PROJECT, S.Id, '');
        for Row in Rows do
        begin
          if (Row.DstKind <> DF_DST_ARG) and (Row.DstKind <> DF_DST_WRITE) then Continue;
          SiteKey:= Format('%d|%d|%d|%s|%d', [Row.FileId, Row.DstLine, Row.DstCol, Row.DstKind, Row.DstIndex]);
          if Done.ContainsKey(SiteKey) then Continue;
          Done.Add(SiteKey, True);
          { the rules this site is a sink of (a certain entry wins over a weak one) }
          Rules:= nil;
          WeakSink:= nil;
          for Entry in FCfg.Sinks do
            if SinkMatches(Entry, S, Row, Weak) then
            begin
              K:= -1;
              for I:= 0 to High(Rules) do
                if SameText(Rules[I], Entry.Rule) then K:= I;
              if K < 0 then
              begin
                Rules:= Rules + [Entry.Rule];
                WeakSink:= WeakSink + [Weak];
              end
              else if not Weak then WeakSink[K]:= False;
            end;
          if Rules = nil then Continue;
          Group:= nil;
          for R2 in Rows do
            if (R2.DstKind = Row.DstKind) and (R2.DstLine = Row.DstLine) and (R2.DstCol = Row.DstCol)
               and (R2.DstIndex = Row.DstIndex) then Group:= Group + [R2];
          for I:= 0 to High(Rules) do
          begin
            Inc(FStats.Sinks);
            FCat:= RuleCategory(Rules[I]);
            Sum:= EvalSink(S, Group);
            Inc(FStats.Hits, Length(Sum.Hits));
            Result:= Result + Findings(S, Row, Rules[I], WeakSink[I], Sum.Hits);
          end;
        end;
      end;
    end;
  finally
    Done.Free;
  end;
  if FCapHit then Inc(FStats.PartialKeys);
  { an existing but EMPTY data_flows over a real scope: indexed before 1.26.0 }
  FStats.StaleIndex:= (FStats.RowsRead = 0) and (Routines > 0) and (Length(AScopeFileIds) > 1);
end;

end.
