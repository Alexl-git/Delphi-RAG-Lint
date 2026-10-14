unit DRagLint.Charts.Q.ExceptionPaths;

(* The `exception-paths` question in-process: a port of charts\src\Emit-ExceptionPaths.ps1 (the
  PS output is the reference, P3). What does this routine raise, what does it handle itself, and
  where up the caller chain is each raise caught?

  The refs of the focus body are classified by the comment-stripped source token next to them
  (ExceptionRefClass): `raise X.Create` is a RAISE, `on [E:] X do` a HANDLE, anything else is
  dropped and counted. Statements with no identifier (bare `except`, `raise;`, `raise <var>`)
  come from a source scan and are drawn [inferred]. Callers are walked over call_edges to
  -Depth levels; each raised type is walked per call EDGE (InvokeExceptionWalk), a caller's
  handler counting only when a call site lies inside its try (TryBlocks / FindHandlerBlock).
  The chart never says "unhandled".

  The script's numbered sections are methods of TExceptionPathsChart (SelectFocus, ReadFocus,
  WalkCallers, ReadCallers, HandledWhere, EndNotes, DrawFocus, DrawBody, DrawCallers,
  DrawHandlerEdges, ResultFields) and its local functions are private methods (Get-RoutineInfo,
  Get-NestedSkip, Get-BodyExceptions, Get-TypeChain, Test-ClassInIndex, Get-CatchVerdict,
  Get-CallerVerdict, Get-HasCallers, the $evalEdge block, Get-EventCount, Get-WalkSentence,
  Add-CappedCluster). The helpers the script takes from Emit-Common are the ported ones in
  DRagLint.Charts.Exceptions / Source / Index / Dot / Text.

  Not ported: the -SourceOverride test hook and the -MaxCallers / -Depth defaults of the script
  (New-DiagramArtifact passes -Depth and -Cap and never the others, so MaxCallers is the script's
  150), the Write-Host progress lines, and the focus box's third branch (`elseif ($staleCallers)`
  after `if ($types.Count) ... elseif (-not $types.Count)`), which no input can reach.

  ROW CAP: Get-NestedSkip and Get-TypeChain call Invoke-IndexQuery WITHOUT -FailOnTruncate, so
  past 200 rows the PS answer is silently short; the port keeps only the first 200 rows of those
  queries (PS_ROW_CAP) to stay the same answer. Every other query is paged (Get-AllIndexRows) or
  chunked to 60 ids, so it is answered in full on both sides.

  PS traps closed: `-ieq` / `-eq` on names are case-insensitive (SameText) and so are the
  type-keyed hashtables ($ancCache, $inIndexCache, $portOfType, $touched: TIStringComparer);
  Sort-Object is not stable (TPsSort) and orders text with CompareGroupKeys; `Sort-Object -Unique`
  keeps the first of each run of equal keys; Measure-Object -Sum is a [double] (Caught, Escapes,
  NoCallerEnds, CappedCallers, CatchAndPass print '.0' when above 0, the int 0 otherwise); a
  WalkSentence with no raised type is JSON null; and the ORDER of a hashtable's int keys is the
  .NET Hashtable bucket order (PsHashtableOrder), which decides the tooltip of a caller calling
  two walked routines and the input order of the caller sort. *)

interface

const
  /// <summary>The registered question id.</summary>
  EXCEPTION_PATHS_ID = 'exception-paths';

/// <summary>The order in which a PowerShell @{} hashtable enumerates int keys inserted in the given order.</summary>
/// <param name="pKeys">Distinct non-negative keys, in insertion order.</param>
/// <returns>The keys in .Keys order.</returns>
/// <remarks>A simulation of System.Collections.Hashtable (load factor 0.72, primes table, double
/// hashing with HashPrime 101, rehash on expand and on collision-heavy occupancy) and of its
/// enumerator, which walks the buckets from the last to the first. Int32.GetHashCode is the value,
/// so the order is deterministic, unlike string keys.</remarks>
function PsHashtableOrder(const pKeys: TArray<Integer>): TArray<Integer>;

implementation

uses
  System.SysUtils, System.Math, System.Generics.Defaults, System.Generics.Collections, System.RegularExpressions,
  DRagLint.Charts.Question, DRagLint.Charts.Index, DRagLint.Charts.Text, DRagLint.Charts.Dot,
  DRagLint.Charts.Source, DRagLint.Charts.Sql, DRagLint.Charts.Exceptions, DRagLint.Charts.PsSort;

const
  RAISE_BORDER = '#B02A37';
  RAISE_FILL = '#FDECEE';
  RAISE_HDR = '#B02A37';
  HANDLE_BORDER = '#2F9E44';
  HANDLE_FILL = '#EBFBEE';
  HANDLE_HDR = '#2F9E44';
  CALLER_BORDER = '#3B5BDB';
  CALLER_FILL = '#EDF2FF';
  CALLER_HDR = '#3B5BDB';
  FOCUS_BORDER = '#0F766E';
  FOCUS_FILL = '#E2F1EF';
  FOCUS_HDR = '#0F766E';
  STALE_BORDER = '#6B7280';
  STALE_FILL = '#F3F4F6';
  STALE_HDR = '#6B7280';
  ROW_INK = '#1F2933';
  LINE_INK = '#8A94A6';
  FONT_MONO = 'Consolas';
  FONT_SANS = 'Segoe UI';
  STYLE_SOLID = 'rounded,filled';
  STYLE_DASHED = 'rounded,filled,dashed';
  INFERRED_NOTE = 'source scan; compiler directives not evaluated';
  HINT = 'exception-paths selects a routine';
  RE_RAISE = '(re-raise)';
  KIND_BARE = 'bare-except';
  KIND_RERAISE = 'reraise';
  KIND_RAISE_VAR = 'raise-var';
  KIND_RAISE_OTHER = 'raise-other';
  CLASS_RAISE = 'raise';
  CLASS_HANDLE = 'handle';
  EV_CAUGHT = 'caught';
  EV_PARTIAL = 'partial';
  EV_RERAISED = 'reraised';
  EV_UNVERIFIED = 'unverified';
  EV_MAY = 'may';
  V_BARE = 'bare';
  V_CATCH_ALL = 'catch-all';
  V_EXACT = 'exact';
  V_ANCESTOR = 'ancestor';
  V_NO = 'no';
  CHAIN_EXTERNAL = 'external';
  CHAIN_AMBIGUOUS = 'ambiguous';
  CHAIN_WALKED = 'walked';
  END_CAP = 'cap';
  END_NO_ROW = 'no-row';
  END_UNBOUND = 'unbound-in-index';
  END_LEFT = 'left-index';
  CATCH_ALL_NAME = 'Exception';
  CALLER_ROW_KEY = '';
  { the script's -MaxCallers default; New-DiagramArtifact does not pass it }
  MAX_CALLERS = 150;
  { ids per IN-list (the PS chunk) }
  ID_CHUNK = 60;
  { a call site / handler position is line * POS_SCALE + column }
  POS_SCALE = 100000;
  { Get-TypeChain's link cap }
  CHAIN_LINKS = 32;
  { Invoke-IndexQuery's silent row cap (no -FailOnTruncate) }
  PS_ROW_CAP = 200;
  { the focus header's point size }
  HEADER_POINTS = 14;
  { the point size of the focus row's line number }
  LINE_POINTS = 12;

  { System.Collections.Hashtable / HashHelpers }
  HT_PRIMES: array[0..47] of Integer = (3, 7, 11, 17, 23, 29, 37, 47, 59, 71, 89, 107, 131, 163, 197, 239, 293,
    353, 431, 521, 631, 761, 919, 1103, 1327, 1597, 1931, 2333, 2801, 3371, 4049, 4861, 5839, 7013, 8419, 10103,
    12143, 14591, 17519, 21023, 25229, 30293, 36353, 43627, 52361, 62851, 75431, 90523);
  HT_HASH_PRIME = 101;
  HT_LOAD_FACTOR: Single = 0.72;
  HT_INITIAL_SIZE = 3;
  { HashHelpers.IsPrime trial division: odd divisors from 3 }
  HT_FIRST_ODD_DIVISOR = 3;
  HT_ODD_STEP = 2;
  HT_COLLIDED = Cardinal($80000000);
  HT_HASH_MASK = $7FFFFFFF;
  HT_WORD_MASK = $FFFFFFFF;
  { Hashtable.Insert rehashes a collision-heavy table only above this many keys }
  HT_REHASH_MIN_COUNT = 100;

type
  { one bucket of the simulated Hashtable }
  THtBucket = record
    Used    : Boolean;
    Key     : Integer;
    HashColl: Cardinal;
  end;

  { the simulated Hashtable's state }
  THtState = record
    Buckets  : TArray<THtBucket>;
    Count    : Integer;
    LoadSize : Integer;
    Occupancy: Integer;
  end;

  { one row of Get-RoutineInfo }
  TRoutineInfo = record
    Id      : Integer;
    Q       : string;
    Name    : string;
    FileId  : Integer;
    Path    : string;
    UnitName: string;
    FromLine: Integer;
    ToLine  : Integer;
    Line    : Integer;
  end;

  { a classified ref (raise / handle) or a stale one }
  TExcRef = record
    TypeName: string;
    Line    : Integer;
    Col     : Integer;
    Kind    : string;
  end;

  { the Get-BodyExceptions result }
  TBody = record
    Fresh     : Boolean;
    ScanStale : Boolean;
    RefCount  : Integer;
    Raises    : TArray<TExcRef>;
    Handles   : TArray<TExcRef>;
    Inferred  : TArray<TExceptionSourceRow>;
    StaleRows : TArray<TExcRef>;
    Dropped   : Integer;
    OtherKinds: Integer;
  end;

  { one walked caller (the PS $callers row) }
  TCallerNode = record
    Info  : TRoutineInfo;
    D     : Integer;
    Body  : TBody;
    HasTry: Boolean;
    Tries : TTryBlocks;
    Lines : TArray<string>;
  end;

  { one handler candidate of a caller }
  THandlerCand = record
    H   : string;
    Line: Integer;
    Pos : Int64;
    Bare: Boolean;
  end;

  { one handler event (the PS $evs row) }
  TCatchEvent = record
    TypeName  : string;
    CallerId  : Integer;
    CallerName: string;
    Handler   : THandlerCand;
    Kind      : string;
    How       : string;
    Inside    : Integer;
    Total     : Integer;
    Callee    : Integer;
  end;

  { the Get-CallerVerdict result }
  TCallerVerdict = record
    Events     : TArray<TCatchEvent>;
    NotGuarding: TArray<string>;
    No         : TArray<string>;
    Catches    : Boolean;
  end;

  { the $evalEdge result, kept per evaluated edge }
  TEdgeResult = record
    Stopped    : Boolean;
    Stale      : Boolean;
    Events     : TArray<TCatchEvent>;
    NotGuarding: TArray<string>;
    No         : TArray<string>;
  end;

  { the Get-TypeChain result }
  TTypeChain = record
    TypeName: string;
    State   : string;
    EndKind : string;
    Names   : TArray<string>;
  end;

  { one $typeResults row }
  TTypeResult = record
    TypeName    : string;
    Walk        : TExceptionWalk;
    Catchers    : TArray<TCatchEvent>;
    CatchAndPass: TArray<Integer>;
    Events      : TArray<TCatchEvent>;
    NotGuarding : TArray<string>;
    No          : TArray<string>;
  end;

  { one $escapeRows row }
  TEscapeRow = record
    Callee  : Integer;
    Line    : Integer;
    TypeName: string;
  end;

  { the Add-CappedCluster result }
  TCappedCluster = record
    Nid  : string;
    Ports: TArray<string>;
    Shown: Integer;
  end;

  { The script's state: one chart, one index, one run. Owns the index, the reader, the
    exception helpers, the caller graph and every working dictionary; Destroy frees what exists. }
  TExceptionPathsChart = class  // dl:ok god-class@0a34, high-response@0a34 -- REVIEWED 2026-10-14: the class IS Emit-ExceptionPaths.ps1 (one script, one chart): its fields are the script-scope state the PS local functions share, its methods one per script section and local function; splitting it would break the line-for-line port the parity harness checks
  private
    FArgs        : TQuestionArgs;
    FIndex       : TChartsIndex;
    FReader      : TSourceReader;
    FExc         : TExceptionIndex;
    FGraph       : TExceptionGraph;
    FSel         : TMemberSelection;
    FIdx         : TExceptionStats;
    FFocus       : TRoutineInfo;
    FBody        : TBody;
    FRaiseTypes  : TArray<string>;
    FInfRaise    : TArray<TExceptionSourceRow>;
    FInfBare     : TArray<TExceptionSourceRow>;
    FDist        : TDictionary<Integer, Integer>;
    FDistOrder   : TList<Integer>;
    FCalleeOrder : TList<Integer>;
    FCallerCapped: Boolean;
    FLevels      : Integer;
    FCInfo       : TDictionary<Integer, TRoutineInfo>;
    FCallers     : TArray<TCallerNode>;
    FCallerById  : TDictionary<Integer, Integer>;
    FStaleCallers: Integer;
    FEdgeResults : TList<TEdgeResult>;
    FAncCache    : TDictionary<string, TTypeChain>;
    FInIndex     : TDictionary<string, Boolean>;
    FTypes       : TArray<string>;
    FTypeResults : TArray<TTypeResult>;
    FEvents      : TArray<TCatchEvent>;
    FNgCount     : Integer;
    FNgUndrawn   : Integer;
    FNoCount     : Integer;
    FStaleNote   : string;
    FWalkLines   : TArray<string>;
    FEndNote     : TDictionary<Integer, string>;
    FEscapeRows  : TDictionary<Integer, TArray<TEscapeRow>>;
    FTouched     : TDictionary<string, Boolean>;
    FFreshFiles  : Integer;
    FSb          : TStringBuilder;
    FNodeId      : Integer;
    FClusters    : Integer;
    FAnchored    : Integer;
    FFnid        : string;
    FFileName    : string;
    FPortOfType  : TDictionary<string, string>;
    FRaiseNid    : string;
    FCatchPort   : TDictionary<string, string>;
    { local functions of the script }
    procedure ReadRoutineInfo(const pIds: TArray<Integer>; pInto: TDictionary<Integer, TRoutineInfo>);
    function NestedSkip(const pRt: TRoutineInfo): TArray<TLineSpan>;
    function BodyExceptions(const pRt: TRoutineInfo; pHandlersOnly: Boolean): TBody;
    function TypeChain(const pType: string): TTypeChain;
    function ClassInIndex(const pName: string): Boolean;
    function CatchVerdict(const pType, pHandler: string; pBare: Boolean): string;
    function CallerVerdict(const pCaller: TCallerNode; const pType: string; const pSites: TArray<Int64>): TCallerVerdict;
    function HasCallers(const pIds: TArray<Integer>): TArray<Integer>;
    function EvaluateEdge(pCaller, pCallee: Integer; const pSites: TArray<Int64>; const pType: string): TEdgeVerdict;
    function EventCount(const pKind: string): Integer;
    function WalkSentence(const pTr: TTypeResult): string;
    function AddCappedCluster(const pKey, pTitle: string; const pRows: TArray<TDotRow>; const pNoun, pBorder, pFill,
      pHdr, pStyle, pFooter: string): TCappedCluster;
    function CalleeName(pCallee: Integer): string;
    function SumOf(const pCounts: TArray<Integer>; const pName: string): TMetaField;
    { the script's sections }
    procedure SelectFocus;
    procedure ReadFocus;
    procedure WalkCallers;
    procedure ReadCallers;
    procedure HandledWhere;
    procedure EndNotes;
    procedure DrawFocus;
    procedure DrawBody;
    procedure DrawCallers;
    procedure DrawHandlerEdges;
    function ResultFields: TArray<TMetaField>;
  public
    constructor Create(const pArgs: TQuestionArgs);
    destructor Destroy; override;
    function Emit(const pOutDir: string): TChartResult;
  end;

{ ---- the Hashtable simulation ---- }

function HtGetPrime(pMin: Integer): Integer;
begin
  for var P in HT_PRIMES do
    if P >= pMin then
      Exit(P);
  { past the 48 primes copied here (.NET's own table continues to 7199369): HashHelpers.GetPrime's computed
    branch -- the next odd prime whose predecessor is not a multiple of HashPrime. Unreachable in practice:
    growing past 90523 buckets needs more than ~65k keys (load factor 0.72), and the walk stops at MAX_CALLERS (150).
    It differs from .NET above 90523, where .NET would still pick from its table. }
  Result:= pMin or 1;
  while True do
  begin
    var IsPrime:= True;
    var D:= HT_FIRST_ODD_DIVISOR;
    while D * D <= Result do
    begin
      if Result mod D = 0 then
      begin
        IsPrime:= False;
        Break;
      end;
      Inc(D, HT_ODD_STEP);
    end;
    if IsPrime and ((Result - 1) mod HT_HASH_PRIME <> 0) then
      Exit;
    Inc(Result, HT_ODD_STEP);
  end;
end;

function HtIncrement(pSeed: Cardinal; pSize: Integer): Cardinal;
begin
  Result:= 1 + Cardinal(((UInt64(pSeed) * HT_HASH_PRIME) and HT_WORD_MASK) mod Cardinal(pSize - 1));
end;

{ putEntry: a key into a fresh bucket array (rehash) }
procedure HtPut(var pState: THtState; var pBuckets: TArray<THtBucket>; pKey: Integer; pHash: Cardinal);
begin
  var Incr:= HtIncrement(pHash, Length(pBuckets));
  var B:= Integer(pHash mod Cardinal(Length(pBuckets)));
  while pBuckets[B].Used do
  begin
    if pBuckets[B].HashColl and HT_COLLIDED = 0 then
    begin
      pBuckets[B].HashColl:= pBuckets[B].HashColl or HT_COLLIDED;
      Inc(pState.Occupancy);
    end;
    B:= Integer((UInt64(B) + Incr) mod Cardinal(Length(pBuckets)));
  end;
  pBuckets[B].Used:= True;
  pBuckets[B].Key:= pKey;
  pBuckets[B].HashColl:= pBuckets[B].HashColl or pHash;
end;

procedure HtRehash(var pState: THtState; pNewSize: Integer);
begin
  pState.Occupancy:= 0;
  var Fresh: TArray<THtBucket>;
  SetLength(Fresh, pNewSize);
  for var Nb:= 0 to High(pState.Buckets) do
    if pState.Buckets[Nb].Used then
      HtPut(pState, Fresh, pState.Buckets[Nb].Key, pState.Buckets[Nb].HashColl and HT_HASH_MASK);
  pState.Buckets:= Fresh;
  pState.LoadSize:= Trunc(HT_LOAD_FACTOR * pNewSize);
end;

procedure HtInsert(var pState: THtState; pKey: Integer);
begin
  if pState.Count >= pState.LoadSize then
    HtRehash(pState, HtGetPrime(2 * Length(pState.Buckets)))
  else if (pState.Occupancy > pState.LoadSize) and (pState.Count > HT_REHASH_MIN_COUNT) then
    HtRehash(pState, Length(pState.Buckets));
  var Hash:= Cardinal(pKey) and HT_HASH_MASK;
  var Incr:= HtIncrement(Hash, Length(pState.Buckets));
  var B:= Integer(Hash mod Cardinal(Length(pState.Buckets)));
  while pState.Buckets[B].Used do
  begin
    if pState.Buckets[B].Key = pKey then
      Exit;
    if pState.Buckets[B].HashColl and HT_COLLIDED = 0 then
    begin
      pState.Buckets[B].HashColl:= pState.Buckets[B].HashColl or HT_COLLIDED;
      Inc(pState.Occupancy);
    end;
    B:= Integer((UInt64(B) + Incr) mod Cardinal(Length(pState.Buckets)));
  end;
  pState.Buckets[B].Used:= True;
  pState.Buckets[B].Key:= pKey;
  pState.Buckets[B].HashColl:= pState.Buckets[B].HashColl or Hash;
  Inc(pState.Count);
end;

function PsHashtableOrder(const pKeys: TArray<Integer>): TArray<Integer>;
begin
  var St:= Default(THtState);
  SetLength(St.Buckets, HT_INITIAL_SIZE);
  St.LoadSize:= Trunc(HT_LOAD_FACTOR * HT_INITIAL_SIZE);
  for var K in pKeys do
    HtInsert(St, K);
  Result:= [];
  for var B:= High(St.Buckets) downto 0 do
    if St.Buckets[B].Used then
      Result:= Result + [St.Buckets[B].Key];
end;

{ ---- small helpers ---- }

{ the ids pIds[pFrom .. pFrom + ID_CHUNK - 1], comma-separated for an IN-list (the PS 60-id chunk) }
function IdChunk(const pIds: TArray<Integer>; pFrom: Integer): string;
begin
  var Parts: TArray<string>:= [];
  for var J:= pFrom to Min(pFrom + ID_CHUNK, Length(pIds)) - 1 do
    Parts:= Parts + [IntToStr(pIds[J])];
  Result:= string.Join(',', Parts);
end;

function Plural(pCount: Integer; const pMany: string = 's'; const pOne: string = ''): string;
begin
  Result:= if pCount <> 1 then pMany else pOne;
end;

{ the last '.'-separated segment (the PS (-split '\.')[-1]) }
function LastSegment(const pName: string): string;
begin
  Result:= Copy(pName, LastDelimiter('.', pName) + 1, MaxInt);
end;

function IntIn(const pValues: TArray<Integer>; pValue: Integer): Boolean;
begin
  for var V in pValues do
    if V = pValue then
      Exit(True);
  Result:= False;
end;

function SortedIntsText(const pValues: TArray<Integer>): string;
begin
  var A:= Copy(pValues);
  TArray.Sort<Integer>(A);
  Result:= IntsText(A);
end;

{ the distinct strings of pValues, added to pSet }
procedure AddKeys(pSet: TDictionary<string, Boolean>; const pValues: TArray<string>);
begin
  for var V in pValues do
    pSet.AddOrSetValue(V, True);
end;

{ ---- TExceptionPathsChart ---- }

constructor TExceptionPathsChart.Create(const pArgs: TQuestionArgs);
begin
  inherited Create;
  FArgs:= pArgs;
  FIndex:= TChartsIndex.Create(pArgs.GuardedDb);
  FReader:= TSourceReader.Create(FIndex);
  FExc:= TExceptionIndex.Create(FIndex, FReader);
  FGraph:= TExceptionGraph.Create;
  FDist:= TDictionary<Integer, Integer>.Create;
  FDistOrder:= TList<Integer>.Create;
  FCalleeOrder:= TList<Integer>.Create;
  FCInfo:= TDictionary<Integer, TRoutineInfo>.Create;
  FCallerById:= TDictionary<Integer, Integer>.Create;
  FEdgeResults:= TList<TEdgeResult>.Create;
  FAncCache:= TDictionary<string, TTypeChain>.Create(TIStringComparer.Ordinal);
  FInIndex:= TDictionary<string, Boolean>.Create(TIStringComparer.Ordinal);
  FEndNote:= TDictionary<Integer, string>.Create;
  FEscapeRows:= TDictionary<Integer, TArray<TEscapeRow>>.Create;
  FTouched:= TDictionary<string, Boolean>.Create(TIStringComparer.Ordinal);
  FPortOfType:= TDictionary<string, string>.Create(TIStringComparer.Ordinal);
  FCatchPort:= TDictionary<string, string>.Create;
  FSb:= TStringBuilder.Create;
end;

destructor TExceptionPathsChart.Destroy;
begin
  FSb.Free;
  FCatchPort.Free;
  FPortOfType.Free;
  FTouched.Free;
  FEscapeRows.Free;
  FEndNote.Free;
  FInIndex.Free;
  FAncCache.Free;
  FEdgeResults.Free;
  FCallerById.Free;
  FCInfo.Free;
  FCalleeOrder.Free;
  FDistOrder.Free;
  FDist.Free;
  FGraph.Free;
  FExc.Free;
  FReader.Free;
  FIndex.Free;
  inherited Destroy;
end;

{ Get-RoutineInfo: symbol rows in chunks of 60 ids }
procedure TExceptionPathsChart.ReadRoutineInfo(const pIds: TArray<Integer>; pInto: TDictionary<Integer, TRoutineInfo>);
begin
  var I:= 0;
  while I < Length(pIds) do
  begin
    var Rows:= FIndex.Query(
      'SELECT s.id AS id, s.qualified_name AS q, s.name AS name, s.file_id AS fid,' + sLineBreak +
      '       s.impl_start_line AS a, s.impl_end_line AS b, s.start_line AS dline, f.path AS path' + sLineBreak +
      '  FROM symbols s JOIN files f ON f.id = s.file_id' + sLineBreak +
      ' WHERE s.id IN (' + IdChunk(pIds, I) + ')');
    try
      for var R in Rows do
      begin
        var Ri:= Default(TRoutineInfo);
        Ri.Id:= R.I('id');
        Ri.Q:= R.S('q');
        Ri.Name:= R.S('name');
        Ri.FileId:= R.I('fid');
        Ri.Path:= R.S('path');
        Ri.UnitName:= UnitNameOf(Ri.Path);
        Ri.FromLine:= R.I('a');
        Ri.ToLine:= R.I('b');
        Ri.Line:= if Ri.FromLine <> 0 then Ri.FromLine else R.I('dline');
        pInto.AddOrSetValue(Ri.Id, Ri);
      end;
    finally
      Rows.Free;
    end;
    Inc(I, ID_CHUNK);
  end;
end;

{ Get-NestedSkip: nested routines' bodies belong to THEM }
function TExceptionPathsChart.NestedSkip(const pRt: TRoutineInfo): TArray<TLineSpan>;
begin
  Result:= [];
  if pRt.FromLine <= 0 then
    Exit;
  var Rows:= FIndex.Query(Format(
    'SELECT impl_start_line AS a, impl_end_line AS b FROM symbols' + sLineBreak +  // dl:ok sql-injection-concat@9ada -- REVIEWED 2026-10-14: read-only index query; every value spliced in is an Integer (ids, lines) or a constant
    ' WHERE file_id = %d AND id <> %d AND impl_start_line > 0' + sLineBreak +
    '   AND impl_start_line >= %d AND impl_end_line <= %d', [pRt.FileId, pRt.Id, pRt.FromLine, pRt.ToLine]));
  try
    for var I:= 0 to Min(Rows.Count, PS_ROW_CAP) - 1 do
      Result:= Result + [TLineSpan.Make(Rows[I].I('a'), Rows[I].I('b'))];
  finally
    Rows.Free;
  end;
end;

{ Get-BodyExceptions: one routine body; pHandlersOnly (callers) reads type_use refs only }
function TExceptionPathsChart.BodyExceptions(const pRt: TRoutineInfo; pHandlersOnly: Boolean): TBody;
begin
  Result:= Default(TBody);
  var Kinds:= if pHandlersOnly then '''type_use''' else '''read'',''type_use''';
  var Refs:= FIndex.AllRows(Format(
    'SELECT r.id AS id, r.kind AS kind, r.name_text AS name, r.start_line AS line,' + sLineBreak +
    '       r.start_col AS col, r.end_col AS ecol' + sLineBreak +
    '  FROM refs r' + sLineBreak +
    ' WHERE r.enclosing_symbol_id = %d AND r.kind IN (%s)', [pRt.Id, Kinds]), 'r.id');
  try
    Result.Fresh:= FReader.SourceFresh(pRt.Path);
    Result.RefCount:= Refs.Count;
    for var R in Refs do
    begin
      var IsExc:= FExc.IsExceptionTypeName(R.S('name'));
      var Row:= Default(TExcRef);
      Row.TypeName:= R.S('name');
      Row.Line:= R.I('line');
      if not Result.Fresh then
      begin
        { never classified: the exception-named refs are listed as [stale source] }
        if IsExc then
        begin
          Row.Kind:= R.S('kind');
          Result.StaleRows:= Result.StaleRows + [Row];
        end;
        Continue;
      end;
      var C:= FReader.SourceContext(pRt.Path, R.I('line'), R.I('col'), R.I('ecol') - R.I('col'));
      var Cls:= ExceptionRefClass(C, R.S('kind'));
      Row.Col:= R.I('col');
      if Cls = CLASS_RAISE then
        Result.Raises:= Result.Raises + [Row]
      else if Cls = CLASS_HANDLE then
        Result.Handles:= Result.Handles + [Row]
      else if IsExc then
        Inc(Result.Dropped);
    end;
  finally
    Refs.Free;
  end;
  { casts and qualified `is`-tests arrive as call / member-access refs: counted, never drawn }
  if not pHandlersOnly then
  begin
    var Ok:= FIndex.AllRows(Format(
      'SELECT r.id AS id, r.name_text AS name FROM refs r' + sLineBreak +  // dl:ok sql-injection-concat@3ec4 -- REVIEWED 2026-10-14: read-only index query; every value spliced in is an Integer (ids, lines) or a constant
      ' WHERE r.enclosing_symbol_id = %d AND r.kind NOT IN (''read'',''type_use'')' + sLineBreak +
      '   AND %s', [pRt.Id, ExceptionNameSql('r.name_text')]), 'r.id');
    try
      for var O in Ok do
        if FExc.IsExceptionTypeName(O.S('name')) and Result.Fresh then
        begin
          Inc(Result.Dropped);
          Inc(Result.OtherKinds);
        end;
    finally
      Ok.Free;
    end;
  end;
  if pRt.FromLine > 0 then
  begin
    var Scan:= FExc.SourceRows(pRt.Path, pRt.FromLine, pRt.ToLine, NestedSkip(pRt));
    Result.ScanStale:= Scan.Stale;
    for var S in Scan.Rows do
      if SameText(S.Kind, KIND_BARE) or (not pHandlersOnly and (SameText(S.Kind, KIND_RERAISE) or
        SameText(S.Kind, KIND_RAISE_VAR) or SameText(S.Kind, KIND_RAISE_OTHER))) then
        Result.Inferred:= Result.Inferred + [S];
  end;
end;

{ Get-TypeChain: ancestry walked inside the index only (R4), cached per type }
function TExceptionPathsChart.TypeChain(const pType: string): TTypeChain;
begin
  if FAncCache.TryGetValue(pType, Result) then
    Exit;
  Result:= Default(TTypeChain);
  Result.TypeName:= pType;
  Result.Names:= [pType];
  Result.State:= CHAIN_EXTERNAL;
  Result.EndKind:= '';
  var Decl:= FIndex.Query(Format('SELECT DISTINCT id AS id, qualified_name AS q FROM symbols WHERE kind = ''class'' AND name = ''%s''',
    [TChartsIndex.SqlText(pType)]));
  try
    var N:= Min(Decl.Count, PS_ROW_CAP);
    var Qs: TArray<string>:= [];
    for var I:= 0 to N - 1 do
      Qs:= Qs + [Decl[I].S('q')];
    if (N > 1) and (Length(SortUniqueNames(Qs)) > 1) then
      Result.State:= CHAIN_AMBIGUOUS
    else if N >= 1 then
    begin
      Result.State:= CHAIN_WALKED;
      Result.EndKind:= END_CAP;
      var Cur:= Decl[0].I('id');
      for var I:= 0 to CHAIN_LINKS - 1 do
      begin
        var A:= FIndex.Query(Format('SELECT ancestor_name AS n, ancestor_symbol_id AS s FROM type_ancestors WHERE symbol_id = %d AND ordinal = 0',
          [Cur]));
        try
          if A.Count = 0 then
          begin
            Result.EndKind:= END_NO_ROW;
            Break;
          end;
          var An:= LastSegment(A[0].S('n'));
          Result.Names:= Result.Names + [An];
          if A[0].I('s') <> 0 then
          begin
            Cur:= A[0].I('s');
            Continue;
          end;
          Result.EndKind:= if ClassInIndex(An) then END_UNBOUND else END_LEFT;
          Break;
        finally
          A.Free;
        end;
      end;
    end;
  finally
    Decl.Free;
  end;
  FAncCache.AddOrSetValue(pType, Result);
end;

{ Test-ClassInIndex, cached per name }
function TExceptionPathsChart.ClassInIndex(const pName: string): Boolean;
begin
  if FInIndex.TryGetValue(pName, Result) then
    Exit;
  var N:= FIndex.Query(Format('SELECT COUNT(*) AS n FROM symbols WHERE kind = ''class'' AND name = ''%s''', [TChartsIndex.SqlText(pName)]));
  try
    Result:= N[0].I('n') > 0;
  finally
    N.Free;
  end;
  FInIndex.AddOrSetValue(pName, Result);
end;

{ Get-CatchVerdict: exact / catch-all / ancestor / bare are SOLID type matches, may is dashed, no cannot catch }
function TExceptionPathsChart.CatchVerdict(const pType, pHandler: string; pBare: Boolean): string;  // dl:ok too-many-exit-points@1578 -- REVIEWED 2026-10-14: ports Get-CatchVerdict, a ladder of early returns, line for line; the order of the returns IS the verdict precedence
begin
  if pBare then
    Exit(V_BARE);
  if SameText(pHandler, CATCH_ALL_NAME) then
    Exit(V_CATCH_ALL);
  if SameText(pType, RE_RAISE) then
    Exit(EV_MAY);
  if SameText(pHandler, pType) then
    Exit(V_EXACT);
  var Ch:= TypeChain(pType);
  for var I:= 1 to High(Ch.Names) do
    if SameText(Ch.Names[I], pHandler) then
      Exit(V_ANCESTOR);
  { 'no' ONLY when the chain provably LEFT the project (R11) }
  if SameText(Ch.State, CHAIN_WALKED) and SameText(Ch.EndKind, END_LEFT) and ClassInIndex(pHandler) then
    Exit(V_NO);
  Result:= EV_MAY;
end;

{ Get-CallerVerdict: all handler events of one caller for one type over the call sites }
function TExceptionPathsChart.CallerVerdict(const pCaller: TCallerNode; const pType: string;
  const pSites: TArray<Int64>): TCallerVerdict;
begin
  Result:= Default(TCallerVerdict);
  var Cands: TArray<THandlerCand>:= [];
  for var H in pCaller.Body.Handles do
  begin
    var C:= Default(THandlerCand);
    C.H:= H.TypeName;
    C.Line:= H.Line;
    C.Pos:= Int64(H.Line) * POS_SCALE + H.Col;
    Cands:= Cands + [C];
  end;
  for var S in pCaller.Body.Inferred do
  begin
    var C:= Default(THandlerCand);
    C.H:= 'except';
    C.Line:= S.Line;
    C.Pos:= Int64(S.Line) * POS_SCALE + S.Col;
    C.Bare:= True;
    Cands:= Cands + [C];
  end;
  TPsSort<THandlerCand>.Sort(Cands,
    function(const pL, pR: THandlerCand): Integer
    begin
      Result:= CompareValue(pL.Pos, pR.Pos);
    end);
  for var H in Cands do
  begin
    var V:= CatchVerdict(pType, H.H, H.Bare);
    var Key:= Format('%d:%d', [pCaller.Info.Id, H.Pos]);
    if V = V_NO then
    begin
      Result.No:= Result.No + [Key];
      Continue;
    end;
    var Ev:= Default(TCatchEvent);
    Ev.TypeName:= pType;
    Ev.CallerId:= pCaller.Info.Id;
    Ev.CallerName:= pCaller.Info.Name;
    Ev.Handler:= H;
    Ev.How:= V;
    Ev.Total:= Length(pSites);
    var Blk: TTryBlock;
    if not (pCaller.HasTry and pCaller.Tries.Decided and FindHandlerBlock(pCaller.Tries, H.Pos, Blk)) then
    begin
      Ev.Kind:= if V = EV_MAY then EV_MAY else EV_UNVERIFIED;
      Result.Events:= Result.Events + [Ev];
      Continue;
    end;
    var Inside:= 0;
    for var S in pSites do
      if (S > Blk.TryPos) and (S < Blk.ExceptPos) then
        Inc(Inside);
    if Inside = 0 then
    begin
      Result.NotGuarding:= Result.NotGuarding + [Key];
      Continue;
    end;
    if V = EV_MAY then
      Ev.Kind:= EV_MAY
    else if HandlerReraises(pCaller.Lines, Blk, H.Pos, H.Bare) then
      Ev.Kind:= EV_RERAISED
    else if Inside < Length(pSites) then
      Ev.Kind:= EV_PARTIAL
    else
      Ev.Kind:= EV_CAUGHT;
    Ev.Inside:= Inside;
    Result.Events:= Result.Events + [Ev];
  end;
  for var Ev in Result.Events do
    if Ev.Kind = EV_CAUGHT then
      Result.Catches:= True;
end;

{ Get-HasCallers: which ids have at least one resolved caller }
function TExceptionPathsChart.HasCallers(const pIds: TArray<Integer>): TArray<Integer>;
begin
  Result:= [];
  var I:= 0;
  while I < Length(pIds) do
  begin
    var Rows:= FIndex.AllRows(
      'SELECT DISTINCT ce.target_symbol_id AS t FROM call_edges ce JOIN refs r ON r.id = ce.ref_id' + sLineBreak +  // dl:ok sql-injection-concat@16fe -- REVIEWED 2026-10-14: read-only index query; every value spliced in is an Integer (ids, lines) or a constant
      ' WHERE ce.target_symbol_id IN (' + IdChunk(pIds, I) + ') AND r.enclosing_symbol_id IS NOT NULL',
      'ce.target_symbol_id');
    try
      for var R in Rows do
        Result:= Result + [R.I('t')];
    finally
      Rows.Free;
    end;
    Inc(I, ID_CHUNK);
  end;
end;

{ $evalEdge: does this incoming CALL EDGE's caller stop the type there? A stale caller is not read. }
function TExceptionPathsChart.EvaluateEdge(pCaller, pCallee: Integer; const pSites: TArray<Int64>;
  const pType: string): TEdgeVerdict;
begin
  var R:= Default(TEdgeResult);
  var Ix: Integer;
  if not FCallerById.TryGetValue(pCaller, Ix) or not FCallers[Ix].Body.Fresh then
    R.Stale:= True
  else
  begin
    var Er:= CallerVerdict(FCallers[Ix], pType, pSites);
    for var K:= 0 to High(Er.Events) do
      Er.Events[K].Callee:= pCallee;
    R.Stopped:= Er.Catches;
    R.Events:= Er.Events;
    R.NotGuarding:= Er.NotGuarding;
    R.No:= Er.No;
  end;
  FEdgeResults.Add(R);
  Result.Stopped:= R.Stopped;
  Result.Tag:= FEdgeResults.Count - 1;
end;

{ Get-EventCount }
function TExceptionPathsChart.EventCount(const pKind: string): Integer;
begin
  Result:= 0;
  for var Ev in FEvents do
    if Ev.Kind = pKind then
      Inc(Result);
end;

function TExceptionPathsChart.CalleeName(pCallee: Integer): string;
var
  Ri: TRoutineInfo;
begin
  if pCallee = FSel.Id then
    Exit(FSel.Name);
  if FCInfo.TryGetValue(pCallee, Ri) then
    Exit(Ri.Name);
  Result:= '?';
end;

{ Get-WalkSentence: the handled-where sentence of one raised type, never "unhandled" (R3) }
function TExceptionPathsChart.WalkSentence(const pTr: TTypeResult): string;
begin
  if pTr.Walk.FocusNoCaller and (Length(pTr.Walk.Capped) = 0) then
    Exit('no resolved caller in this index');
  var Depth:= FArgs.Depth;
  var Lv:= Format('%d caller level%s', [Depth, Plural(Depth)]);
  var Cw:= Format('%d caller%s evaluated', [pTr.Walk.Evaluated, Plural(pTr.Walk.Evaluated)]);
  var K:= Length(pTr.Catchers);
  var S: string;
  if K > 0 then
  begin
    var Top:= TRanked<TCatchEvent>.TopRanked(pTr.Catchers, FArgs.Cap, nil);
    var Names: TArray<string>:= [];
    for var Ev in Top.Shown do
      Names:= Names + [Format('%s:%d on the call to %s', [Ev.CallerName, Ev.Handler.Line, CalleeName(Ev.Callee)])];
    if Top.HiddenRows > 0 then
      Names:= Names + [Format('+%d more', [Top.HiddenRows])];
    S:= Format('caught on %d call edge%s (%s) within %s (%s)', [K, Plural(K), string.Join(', ', Names), Lv, Cw]);
  end
  else
    S:= Format('no handler found within %s (%s)', [Lv, Cw]);
  var Parts: TArray<string>:= [];
  var B:= Length(pTr.CatchAndPass);
  if B > 0 then
    Parts:= Parts + [Format('%d catching caller%s also let%s it escape on another call', [B, Plural(B), Plural(B, '', 's')])];
  var M:= Length(pTr.Walk.Escapes);
  if M > 0 then
    Parts:= Parts + [Format('escapes the walk on %d path end%s after %d level%s', [M, Plural(M), Depth, Plural(Depth)])];
  var Pe:= Length(pTr.Walk.Ends);
  if Pe > 0 then
    Parts:= Parts + [Format('reaches %d caller%s', [Pe, Plural(Pe, 's with no resolved caller of their own',
      ' with no resolved caller of its own')])];
  var Cp:= Length(pTr.Walk.Capped);
  if Cp > 0 then
    Parts:= Parts + [Format('%d caller%s not walked (cap)', [Cp, Plural(Cp)])];
  for var Kn in TArray<string>.Create(EV_RERAISED, EV_PARTIAL, EV_UNVERIFIED, EV_MAY) do
  begin
    var Kc:= 0;
    for var Ev in pTr.Events do
      if Ev.Kind = Kn then
        Inc(Kc);
    if Kc = 0 then
      Continue;
    var Word:= 'may catch';
    if Kn = EV_RERAISED then
      Word:= 'caught and re-raised'
    else if Kn = EV_PARTIAL then
      Word:= 'caught at only some call sites'
    else if Kn = EV_UNVERIFIED then
      Word:= 'handler(s) not verified around the call';
    Parts:= Parts + [Format('%d %s', [Kc, Word])];
  end;
  Result:= (if Length(Parts) > 0 then S + '; ' + string.Join('; ', Parts) else S) + FStaleNote;
end;

{ Add-CappedCluster: a capped row cluster; Shown is how many of pRows are drawn (the first ones) }
function TExceptionPathsChart.AddCappedCluster(const pKey, pTitle: string; const pRows: TArray<TDotRow>; const pNoun,  // dl:ok too-many-parameters@eaff -- REVIEWED 2026-10-14: the parameter list of the PS Add-CappedCluster, kept so each call site reads like the script
  pBorder, pFill, pHdr, pStyle, pFooter: string): TCappedCluster;
begin
  Inc(FNodeId);
  Inc(FClusters);
  Result.Nid:= 'n' + IntToStr(FNodeId);
  var Top:= TRanked<TDotRow>.TopRanked(pRows, FArgs.Cap, nil);
  var Cells: TArray<TDotRow>:= [];
  for var R in Top.Shown do
  begin
    Cells:= Cells + [R];
    if R.Href <> '' then
      Inc(FAnchored);
  end;
  var More:= DisclosureText(Top.HiddenRows, 0, pNoun);
  if More <> '' then
    Cells:= Cells + [NoteRow(More)];
  if pFooter <> '' then
    Cells:= Cells + [NoteRow(pFooter)];
  var Style:= TClusterStyle.Make(pBorder, pFill, pHdr);
  Style.RowInk:= ROW_INK;
  Style.LineInk:= LINE_INK;
  Style.FontSans:= FONT_SANS;
  Style.Style:= pStyle;
  Result.Ports:= AddRowCluster(FSb, Format('cluster_%s_%d', [pKey, FNodeId]), Result.Nid, pTitle, IntToStr(Top.Total), Cells, Style);
  Result.Shown:= Length(Top.Shown);
end;

{ ---- 0/1. the selection and the index-wide pre-check ---- }
procedure TExceptionPathsChart.SelectFocus;
var
  Found: Boolean;
begin
  FSel:= FIndex.ResolveMemberSelection(FArgs.Target, ['method', 'procedure', 'function', 'constructor', 'destructor'], False, HINT,
    Found);
  FIdx:= FExc.IndexStats;
  if FIdx.Candidates = 0 then
    raise EChartsQuestion.Create('exception-paths: this index holds NO reference to an exception type at all ' +
      '(no ref named E<Name> or Exception), so there is nothing to classify -- ask the index ' +
      'that holds the code.');
end;

{ ---- 2. the focus body ---- }
procedure TExceptionPathsChart.ReadFocus;
var
  Info: TDictionary<Integer, TRoutineInfo>;
begin
  Info:= TDictionary<Integer, TRoutineInfo>.Create;
  try
    ReadRoutineInfo([FSel.Id], Info);
    if not Info.TryGetValue(FSel.Id, FFocus) then
      raise EChartsQuestion.CreateFmt('exception-paths: symbol %d is not in this index', [FSel.Id]);
  finally
    Info.Free;
  end;
  FBody:= BodyExceptions(FFocus, False);
  var Names: TArray<string>:= [];
  for var R in FBody.Raises do
    Names:= Names + [R.TypeName];
  FRaiseTypes:= SortUniqueNames(Names);
  for var S in FBody.Inferred do
    if S.Kind <> KIND_BARE then
      FInfRaise:= FInfRaise + [S]
    else
      FInfBare:= FInfBare + [S];
end;

{ ---- 3. callers, walked UP over call_edges, every call SITE kept per (caller, callee) edge ---- }
procedure TExceptionPathsChart.WalkCallers;
begin
  FDist.Add(FSel.Id, 0);
  FDistOrder.Add(FSel.Id);
  var Frontier: TArray<Integer>:= [FSel.Id];
  for var D:= 1 to FArgs.Depth do
  begin
    if Length(Frontier) = 0 then
      Break;
    for var N in Frontier do
      FGraph.MarkFetched(N);
    var Next: TArray<Integer>:= [];
    var I:= 0;
    while I < Length(Frontier) do
    begin
      var Pairs:= FIndex.AllRows(
        'SELECT r.enclosing_symbol_id AS caller, ce.target_symbol_id AS callee,' + sLineBreak +
        '       group_concat(r.start_line || '':'' || r.start_col, '','') AS sites' + sLineBreak +
        '  FROM call_edges ce JOIN refs r ON r.id = ce.ref_id' + sLineBreak +
        ' WHERE ce.target_symbol_id IN (' + IdChunk(Frontier, I) + ') AND r.enclosing_symbol_id IS NOT NULL' + sLineBreak +
        ' GROUP BY r.enclosing_symbol_id, ce.target_symbol_id', 'caller, callee');
      try
        for var P in Pairs do
        begin
          var Cid:= P.I('caller');
          var Tid:= P.I('callee');
          if not FDist.ContainsKey(Cid) then
          begin
            if FDist.Count - 1 >= MAX_CALLERS then
            begin
              { recorded, not walked: a capped node must never read as "no resolved caller" }
              FCallerCapped:= True;
              FGraph.AddCapped(Tid, Cid);
              Continue;
            end;
            FDist.Add(Cid, D);
            FDistOrder.Add(Cid);
            Next:= Next + [Cid];
          end;
          var Sites: TArray<Int64>:= [];
          for var Site in P.S('sites').Split([',']) do
          begin
            var A:= Site.Split([':']);
            Sites:= Sites + [StrToInt64(A[0]) * POS_SCALE + StrToInt(A[1])];
          end;
          if Length(FGraph.CallersOf(Tid)) = 0 then
            FCalleeOrder.Add(Tid);
          FGraph.AddCaller(Tid, Cid, Sites);
        end;
      finally
        Pairs.Free;
      end;
      Inc(I, ID_CHUNK);
    end;
    if Length(Next) > 0 then
      FLevels:= D;
    Frontier:= Next;
  end;
end;

{ ---- 3b. every caller's handlers and try blocks, sorted by depth then name ---- }
procedure TExceptionPathsChart.ReadCallers;
begin
  var Ids: TArray<Integer>:= [];
  for var Id in PsHashtableOrder(FDistOrder.ToArray) do
    if FDist[Id] > 0 then
      Ids:= Ids + [Id];
  if Length(Ids) > 0 then
    ReadRoutineInfo(Ids, FCInfo);
  FCallers:= [];
  for var Id in Ids do
  begin
    var C:= Default(TCallerNode);
    if not FCInfo.TryGetValue(Id, C.Info) then
      raise EChartsQuestion.CreateFmt('exception-paths: caller symbol %d is not in this index', [Id]);
    C.D:= FDist[Id];
    C.Body:= BodyExceptions(C.Info, True);
    { the try-block nesting of the caller span (R10); a stale file is not scanned }
    if C.Body.Fresh and (C.Info.FromLine > 0) then
    begin
      C.Lines:= FReader.StrippedSourceLines(FReader.ReadPath(C.Info.Path));
      C.Tries:= TryBlocks(C.Lines, C.Info.FromLine, C.Info.ToLine);
      C.HasTry:= True;
    end;
    FCallers:= FCallers + [C];
  end;
  TPsSort<TCallerNode>.Sort(FCallers,
    function(const pL, pR: TCallerNode): Integer
    begin
      Result:= CompareValue(pL.D, pR.D);
      if Result = 0 then
        Result:= CompareGroupKeys(pL.Info.Q, pR.Info.Q);
    end);
  for var I:= 0 to High(FCallers) do
  begin
    FCallerById.AddOrSetValue(FCallers[I].Info.Id, I);
    if not FCallers[I].Body.Fresh then
      Inc(FStaleCallers);
  end;
end;

{ ---- 4. handled-where, per raised type, per call EDGE (Invoke-ExceptionWalk) ---- }
procedure TExceptionPathsChart.HandledWhere;
var
  NgKeys: TDictionary<string, Boolean>;
  NoKeys: TDictionary<string, Boolean>;
  Drawn : TDictionary<string, Boolean>;
begin
  FTypes:= Copy(FRaiseTypes);
  if Length(FInfRaise) > 0 then
    FTypes:= FTypes + [RE_RAISE];
  NgKeys:= TDictionary<string, Boolean>.Create;
  NoKeys:= TDictionary<string, Boolean>.Create;
  Drawn:= TDictionary<string, Boolean>.Create;
  try
    for var T in FTypes do
    begin
      var Tr:= Default(TTypeResult);
      Tr.TypeName:= T;
      Tr.Walk:= InvokeExceptionWalk(FSel.Id, FGraph, FArgs.Depth, T, EvaluateEdge, HasCallers);
      var Stops: TArray<Integer>:= [];
      var TypeNg:= TDictionary<string, Boolean>.Create;
      var TypeNo:= TDictionary<string, Boolean>.Create;
      try
        for var E in Tr.Walk.Edges do
        begin
          var R:= FEdgeResults[E.Verdict.Tag];
          Tr.Events:= Tr.Events + R.Events;
          AddKeys(TypeNg, R.NotGuarding);
          AddKeys(TypeNo, R.No);
          if not R.Stopped then
            Continue;
          for var Ev in R.Events do
            if Ev.Kind = EV_CAUGHT then
            begin
              Tr.Catchers:= Tr.Catchers + [Ev];
              Break;
            end;
          if not IntIn(Stops, E.Caller) then
            Stops:= Stops + [E.Caller];
        end;
        Tr.NotGuarding:= TypeNg.Keys.ToArray;
        Tr.No:= TypeNo.Keys.ToArray;
      finally
        TypeNo.Free;
        TypeNg.Free;
      end;
      { a caller that stops T on one edge and lets it through on another: both drawn }
      TArray.Sort<Integer>(Stops);
      for var Cid in Stops do
        if IntIn(Tr.Walk.Passing, Cid) then
          Tr.CatchAndPass:= Tr.CatchAndPass + [Cid];
      FEvents:= FEvents + Tr.Events;
      AddKeys(NgKeys, Tr.NotGuarding);
      AddKeys(NoKeys, Tr.No);
      FTypeResults:= FTypeResults + [Tr];
    end;
    { DISTINCT handler positions (final wave, item 3), drawn and not-guarding counted apart }
    for var Ev in FEvents do
      Drawn.AddOrSetValue(Format('%d:%d', [Ev.CallerId, Ev.Handler.Pos]), True);
    FNgCount:= NgKeys.Count;
    FNgUndrawn:= 0;
    for var K in NgKeys.Keys do
      if not Drawn.ContainsKey(K) then
        Inc(FNgUndrawn);
    FNoCount:= NoKeys.Count;
  finally
    Drawn.Free;
    NoKeys.Free;
    NgKeys.Free;
  end;
  FStaleNote:= if FStaleCallers > 0 then
    Format('; %d caller%s not read: source changed since indexing', [FStaleCallers, Plural(FStaleCallers)]) else '';
  FWalkLines:= [];
  for var Tr in FTypeResults do
  begin
    var S:= WalkSentence(Tr);
    FWalkLines:= FWalkLines + [if Length(FTypes) > 1 then Tr.TypeName + ': ' + S else S];
  end;
end;

{ per node, where a raised type's walk ended; and the escaping calls of a catching caller }
procedure TExceptionPathsChart.EndNotes;
begin
  for var Tr in FTypeResults do
  begin
    for var N in Tr.Walk.Escapes do
      FEndNote.AddOrSetValue(N, Format('walk ends here: callers beyond %d levels', [FArgs.Depth]));
    for var N in Tr.Walk.Ends do
      FEndNote.AddOrSetValue(N, 'no resolved caller');
    for var N in Tr.Walk.Passing do
    begin
      var Cap:= FGraph.CappedOf(N);
      if Length(Cap) > 0 then
        FEndNote.AddOrSetValue(N, Format('%d caller(s) not walked (cap)', [Length(Cap)]));
    end;
  end;
  for var Tr in FTypeResults do
    for var Cid in Tr.CatchAndPass do
      for var Ed in Tr.Walk.Edges do
      begin
        if (Ed.Caller <> Cid) or Ed.Verdict.Stopped then
          Continue;
        var Rows: TArray<TEscapeRow>;
        if not FEscapeRows.TryGetValue(Cid, Rows) then
          Rows:= [];
        var Sites:= Copy(Ed.Sites);
        TArray.Sort<Int64>(Sites);
        for var Sp in Sites do
        begin
          var Er:= Default(TEscapeRow);
          Er.Callee:= Ed.Callee;
          Er.Line:= Integer(Sp div POS_SCALE);
          Er.TypeName:= Tr.TypeName;
          Rows:= Rows + [Er];
        end;
        FEscapeRows.AddOrSetValue(Cid, Rows);
      end;
  { files touched: the focus file and every caller file }
  FTouched.AddOrSetValue(FFocus.Path, FBody.Fresh);
  for var C in FCallers do
    FTouched.AddOrSetValue(C.Info.Path, C.Body.Fresh);
  FFreshFiles:= 0;
  for var Fresh in FTouched.Values do
    if Fresh then
      Inc(FFreshFiles);
end;

{ ---- 5. dot: the focus box ---- }
procedure TExceptionPathsChart.DrawFocus;
var
  FocusTbl: TStringBuilder;
begin
  FSb.AppendLine('digraph exceptionpaths {');
  FSb.AppendLine('  rankdir=LR; bgcolor="transparent"; compound=true;');
  FSb.AppendLine('  nodesep=0.35; ranksep=1.3; splines=spline;');
  FSb.AppendLine(Format('  graph [fontname="%s"];', [FONT_SANS]));
  FSb.AppendLine(Format('  node  [shape=plaintext, fontname="%s", fontsize=14];', [FONT_MONO]));
  FSb.AppendLine(Format('  edge  [fontname="%s", fontsize=11, color="%s", penwidth=1.4, arrowsize=0.7];', [FONT_MONO, LINE_INK]));
  FSb.AppendLine('');
  FFileName:= FileNameOf(FFocus.Path);
  Inc(FNodeId);
  Inc(FClusters);
  FFnid:= 'n' + IntToStr(FNodeId);
  FocusTbl:= TStringBuilder.Create;
  try
    FocusTbl.Append('<TABLE BORDER="0" CELLBORDER="0" CELLSPACING="3" CELLPADDING="5">');
    FocusTbl.Append(Format('<TR><TD ALIGN="LEFT" BGCOLOR="%s"><FONT COLOR="#FFFFFF" FACE="%s" POINT-SIZE="%d"><B> %s </B></FONT></TD></TR>',
      [FOCUS_HDR, FONT_SANS, HEADER_POINTS, XmlText(ShortName(FSel.QName, FFocus.UnitName))]));
    Inc(FAnchored);
    FocusTbl.Append(Format('<TR><TD PORT="p1" ALIGN="LEFT" HREF="%s" TITLE="%s">', [RowHref(FFocus.Path, FSel.FocusLine), XmlText(FSel.QName)]));
    FocusTbl.Append(Format('<FONT COLOR="%s">%s</FONT>', [ROW_INK, XmlText(FFocus.UnitName)]));
    FocusTbl.Append(Format('  <FONT COLOR="%s" POINT-SIZE="%d">:%d</FONT></TD></TR>', [LINE_INK, LINE_POINTS, FSel.FocusLine]));
    AddDisclosureRow(FocusTbl, Format('%d raise site(s) (%d type(s)) -- %d handler clause(s) in body -- ' +
      '%d bare except block(s) [inferred] -- callers walked: %d over %d level(s)',
      [Length(FBody.Raises), Length(FRaiseTypes), Length(FBody.Handles), Length(FInfBare), Length(FCallers), FLevels]), LINE_INK);
    if Length(FInfRaise) > 0 then
      AddDisclosureRow(FocusTbl, Format('%d re-raise statement(s) [inferred] -- raise; / raise <var> carry no type reference',
        [Length(FInfRaise)]), LINE_INK);
    if FBody.Dropped > 0 then
      AddDisclosureRow(FocusTbl, Format('%d other reference(s) to exception types in this body are declarations or tests (not drawn)',
        [FBody.Dropped]), LINE_INK);
    AddDisclosureRow(FocusTbl, Format('type_use refs read from source at file:line:col; files checked fresh: %d of %d',
      [FFreshFiles, FTouched.Count]), LINE_INK);
    if not FBody.Fresh then
      AddDisclosureRow(FocusTbl, Format('[stale source] %s differs from the indexed copy -- %d reference(s) in this body were NOT classified',
        [FFileName, FBody.RefCount]), LINE_INK);
    if Length(FTypes) > 0 then
    begin
      for var Wl in FWalkLines do
        AddDisclosureRow(FocusTbl, 'handled-where: ' + Wl, LINE_INK);
    end
    else
    begin
      var Callers:= if Length(FCallers) > 0 then Format('%d walked over %d level(s)%s', [Length(FCallers), FLevels, FStaleNote])
        else 'no resolved caller in this index';
      AddDisclosureRow(FocusTbl, 'callers: ' + Callers, LINE_INK);
    end;
    if FCallerCapped then
      AddDisclosureRow(FocusTbl, Format('caller walk CAPPED at %d -- more callers exist', [MAX_CALLERS]), LINE_INK);
    AddDisclosureRow(FocusTbl, Format('approximately %d raise sites / %d handlers index-wide (name-filtered); ' +
      'candidate refs in fresh files: %d of %d files', [FIdx.RaiseSites, FIdx.HandleSites, FIdx.FreshFiles, FIdx.Files]), LINE_INK);
    AddDisclosureRow(FocusTbl, 'callers come from resolved call_edges only: interface dispatch and DFM event wiring are not in them', LINE_INK);
    if Length(FCallers) > 0 then
      AddDisclosureRow(FocusTbl, 'a caller''s handler counts only when a call site lies between its try and its except ' +
        '(nesting scan of the stripped caller body)', LINE_INK);
    if (FNgCount > 0) and (FNgUndrawn = FNgCount) then
      AddDisclosureRow(FocusTbl, Format('%d matching handler(s) in callers guard other statements, not the call -- not drawn', [FNgCount]), LINE_INK)
    else if FNgCount > 0 then
      AddDisclosureRow(FocusTbl, Format('%d matching handler(s) in callers guard other statements, not the call, on at least one call edge -- ' +
        '%d not drawn; %d drawn where they do enclose a call', [FNgCount, FNgUndrawn, FNgCount - FNgUndrawn]), LINE_INK);
    if FNoCount > 0 then
      AddDisclosureRow(FocusTbl, Format('%d typed handler(s) in callers cannot catch: declared here, and the raised type''s ancestry ' +
        'left the project without reaching them -- not drawn', [FNoCount]), LINE_INK);  // dl:ok duplicate-code@6674 -- REVIEWED 2026-10-14: each Q unit ports ONE Emit-*.ps1 line for line (spec P3), and the PS emitters repeat the focus box's closing rows verbatim; sharing them would make one parity finding span two questions
    var Edgeless:= TChartsIndex.EdgelessDisclosure(FIndex.EdgelessFiles);
    if Edgeless <> '' then
      AddDisclosureRow(FocusTbl, Edgeless, LINE_INK);
    FocusTbl.Append('</TABLE>');
    FSb.AppendLine(Format('  subgraph cluster_focus_%d {', [FNodeId]));
    FSb.AppendLine(Format('    style="rounded,filled"; color="%s"; fillcolor="%s"; penwidth=2;', [FOCUS_BORDER, FOCUS_FILL]));
    FSb.AppendLine('    label=""; margin=10;');
    FSb.AppendLine(Format('    %s [label=<%s>];', [FFnid, FocusTbl.ToString]));
    FSb.AppendLine('  }');
  finally
    FocusTbl.Free;
  end;
end;

{ ---- 5. dot: raises, re-raises, handlers, bare excepts, stale refs ---- }
procedure TExceptionPathsChart.DrawBody;
begin
  var ByLine: TComparison<TExcRef>:= function(const pL, pR: TExcRef): Integer
    begin
      Result:= CompareValue(pL.Line, pR.Line);
    end;
  var ByRowLine: TComparison<TExceptionSourceRow>:= function(const pL, pR: TExceptionSourceRow): Integer
    begin
      Result:= CompareValue(pL.Line, pR.Line);
    end;
  { LEFT: raises, ref-anchored }
  if Length(FBody.Raises) > 0 then
  begin
    var Sorted:= Copy(FBody.Raises);
    TPsSort<TExcRef>.Sort(Sorted, ByLine);
    var Rows: TArray<TDotRow>:= [];
    for var R in Sorted do
      Rows:= Rows + [TDotRow.Anchored('raise ' + R.TypeName, R.Line, RowHref(FFocus.Path, R.Line),
        Format('raise %s -- %s:%d:%d', [R.TypeName, FFileName, R.Line, R.Col]))];
    var C:= AddCappedCluster('raises', 'RAISES', Rows, 'raise sites', RAISE_BORDER, RAISE_FILL, RAISE_HDR, STYLE_SOLID, '');
    FRaiseNid:= C.Nid;
    for var I:= 0 to C.Shown - 1 do
      if not FPortOfType.ContainsKey(Sorted[I].TypeName) then
        FPortOfType.Add(Sorted[I].TypeName, C.Ports[I]);
    FSb.AppendLine(Format('  %s -> %s [color="%s", dir=none];', [C.Nid, FFnid, RAISE_BORDER]));
  end;
  { LEFT, dashed: re-raises found only in source }
  if Length(FInfRaise) > 0 then
  begin
    var Sorted:= Copy(FInfRaise);
    TPsSort<TExceptionSourceRow>.Sort(Sorted, ByRowLine);
    var Rows: TArray<TDotRow>:= [];
    for var R in Sorted do
      Rows:= Rows + [TDotRow.Anchored(R.Text + ' [inferred]', R.Line, RowHref(FFocus.Path, R.Line),
        Format('%s at %s:%d -- %s', [R.Text, FFileName, R.Line, INFERRED_NOTE]),
        if R.Kind = KIND_RERAISE then 're-raise' else 'raises an object')];
    var C:= AddCappedCluster('inferredraises', 'RE-RAISES [inferred]', Rows, 're-raises', RAISE_BORDER, RAISE_FILL, RAISE_HDR,
      STYLE_DASHED, INFERRED_NOTE);
    if Length(C.Ports) > 0 then
      FPortOfType.AddOrSetValue(RE_RAISE, C.Ports[0]);
    FSb.AppendLine(Format('  %s -> %s [color="%s", style=dashed, dir=none];', [C.Nid, FFnid, RAISE_BORDER]));  // dl:ok duplicate-code@6b77 -- REVIEWED 2026-10-14: the script draws its five body clusters as five near-identical blocks (spec P3, line-for-line); folding them would make one parity finding span several clusters
  end;
  { RIGHT: handlers in body }
  if Length(FBody.Handles) > 0 then
  begin
    var Sorted:= Copy(FBody.Handles);
    TPsSort<TExcRef>.Sort(Sorted, ByLine);
    var Rows: TArray<TDotRow>:= [];
    for var R in Sorted do
      Rows:= Rows + [TDotRow.Anchored('on ' + R.TypeName, R.Line, RowHref(FFocus.Path, R.Line),
        Format('on ...: %s do -- %s:%d:%d', [R.TypeName, FFileName, R.Line, R.Col]))];
    var C:= AddCappedCluster('handlers', 'HANDLERS IN BODY', Rows, 'handler clauses', HANDLE_BORDER, HANDLE_FILL, HANDLE_HDR,
      STYLE_SOLID, '');
    FSb.AppendLine(Format('  %s -> %s [color="%s", dir=none];', [FFnid, C.Nid, HANDLE_BORDER]));
  end;
  { RIGHT, dashed: bare except blocks }
  if Length(FInfBare) > 0 then
  begin
    var Sorted:= Copy(FInfBare);
    TPsSort<TExceptionSourceRow>.Sort(Sorted, ByRowLine);
    var Rows: TArray<TDotRow>:= [];
    for var R in Sorted do
      Rows:= Rows + [TDotRow.Anchored('except (no on clause) [inferred]', R.Line, RowHref(FFocus.Path, R.Line),
        Format('bare except at %s:%d -- %s', [FFileName, R.Line, INFERRED_NOTE]), 'catches everything')];
    var C:= AddCappedCluster('inferredhandlers', 'BARE EXCEPT [inferred]', Rows, 'bare except blocks', HANDLE_BORDER, HANDLE_FILL,
      HANDLE_HDR, STYLE_DASHED, INFERRED_NOTE);
    FSb.AppendLine(Format('  %s -> %s [color="%s", style=dashed, dir=none];', [FFnid, C.Nid, HANDLE_BORDER]));
  end;
  { stale: listed, never classified }
  if Length(FBody.StaleRows) > 0 then
  begin
    var Sorted:= Copy(FBody.StaleRows);
    TPsSort<TExcRef>.Sort(Sorted, ByLine);
    var Rows: TArray<TDotRow>:= [];
    for var R in Sorted do
      Rows:= Rows + [TDotRow.Anchored(R.TypeName + ' [stale source]', R.Line, RowHref(FFocus.Path, R.Line),
        Format('%s %s at %s:%d -- the file on disk differs from the indexed copy; not classified', [R.Kind, R.TypeName, FFileName, R.Line]),
        'not classified')];
    var C:= AddCappedCluster('stale', '[stale source]', Rows, 'references', STALE_BORDER, STALE_FILL, STALE_HDR, STYLE_DASHED,
      'file differs from the indexed copy -- nothing here is classified');
    FSb.AppendLine(Format('  %s -> %s [color="%s", style=dashed, dir=none];', [FFnid, C.Nid, STALE_BORDER]));
  end;
end;

{ ---- 5. dot: the caller chain, one cluster per depth ---- }
procedure TExceptionPathsChart.DrawCallers;
begin
  var CalleeOrder:= PsHashtableOrder(FCalleeOrder.ToArray);
  var CallerStyle:= TClusterStyle.Make(CALLER_BORDER, CALLER_FILL, CALLER_HDR);
  CallerStyle.RowInk:= ROW_INK;
  CallerStyle.LineInk:= LINE_INK;
  CallerStyle.FontSans:= FONT_SANS;
  var PrevPort:= FFnid + ':p1';
  for var D:= 1 to FLevels do
  begin
    { callers holding a drawn handler first, so -Cap never hides the row an edge points at }
    var AtD: TArray<TCallerNode>:= [];
    for var C in FCallers do
      if C.D = D then
        AtD:= AtD + [C];
    TPsSort<TCallerNode>.Sort(AtD,
      function(const pL, pR: TCallerNode): Integer
      begin
        var LNo:= True;
        var RNo:= True;
        for var Ev in FEvents do
        begin
          if Ev.CallerId = pL.Info.Id then
            LNo:= False;
          if Ev.CallerId = pR.Info.Id then
            RNo:= False;
        end;
        Result:= CompareValue(Ord(LNo), Ord(RNo));
        if Result = 0 then
          Result:= CompareGroupKeys(pL.Info.Q, pR.Info.Q);
      end);
    if Length(AtD) = 0 then
      Continue;
    var Rows: TArray<TDotRow>:= [];
    var Keys: TArray<string>:= [];
    for var C in AtD do
    begin
      var Ci:= C.Info;
      { what this caller calls on the walk, and where (the Tip), from the edge map }
      var Calls: TArray<string>:= [];
      for var Tid in CalleeOrder do
        for var E2 in FGraph.CallersOf(Tid) do
        begin
          if E2.Caller <> Ci.Id then
            Continue;
          var Ls: TArray<Integer>:= [];
          for var S in E2.Sites do
            if not IntIn(Ls, Integer(S div POS_SCALE)) then
              Ls:= Ls + [Integer(S div POS_SCALE)];
          TArray.Sort<Integer>(Ls);
          var LsText: TArray<string>:= [];
          for var L in Ls do
            LsText:= LsText + [IntToStr(L)];
          Calls:= Calls + [Format('%s at :%s', [CalleeName(Tid), string.Join(', ', LsText)])];
        end;
      var Hn:= Length(C.Body.Handles) + Length(C.Body.Inferred);
      var Note:= if not C.Body.Fresh then '[stale source] not read: source changed since indexing' else Format('%d handler(s)', [Hn]);
      var En: string;
      if FEndNote.TryGetValue(Ci.Id, En) then
        Note:= Note + ' -- ' + En;
      Rows:= Rows + [TDotRow.Anchored(ShortName(Ci.Q, Ci.UnitName), Ci.Line, RowHref(Ci.Path, Ci.Line),
        Format('%s calls %s in %s', [Ci.Q, string.Join('; ', Calls), FileNameOf(Ci.Path)]), Note)];
      Keys:= Keys + [CALLER_ROW_KEY];
      { the handler rows an event points at }
      var HRows:= TDictionary<Int64, THandlerCand>.Create;
      try
        for var Ev in FEvents do
          if Ev.CallerId = Ci.Id then
            HRows.AddOrSetValue(Ev.Handler.Pos, Ev.Handler);
        var Hps:= HRows.Keys.ToArray;
        TArray.Sort<Int64>(Hps);
        for var Hp in Hps do
        begin
          var H:= HRows[Hp];
          var Lbl:= if H.Bare then '  except (no on clause) [inferred]' else '  on ' + H.H;
          Rows:= Rows + [TDotRow.Anchored(Lbl, H.Line, RowHref(Ci.Path, H.Line),
            Format('%s in %s -- %s:%d', [Lbl.Trim, Ci.Q, FileNameOf(Ci.Path), H.Line]), 'handler')];
          Keys:= Keys + [Format('%d|%d', [Ci.Id, Hp])];
        end;
      finally
        HRows.Free;
      end;
      { it caught on one call but lets the type through another (R13): anchored }
      var Esc: TArray<TEscapeRow>;
      if FEscapeRows.TryGetValue(Ci.Id, Esc) then
      begin
        TPsSort<TEscapeRow>.Sort(Esc,
          function(const pL, pR: TEscapeRow): Integer
          begin
            Result:= CompareValue(pL.Line, pR.Line);
          end);
        for var I:= 0 to High(Esc) do
        begin
          { Sort-Object -Unique: the first of each run of equal lines }
          if (I > 0) and (Esc[I].Line = Esc[I - 1].Line) then
            Continue;
          var Er:= Esc[I];
          Rows:= Rows + [TDotRow.Anchored('  escapes via the call to ' + CalleeName(Er.Callee), Er.Line, RowHref(Ci.Path, Er.Line),
            Format('%s passes %s at %s:%d -- this call is not inside a catching try', [Er.TypeName, Ci.Q, FileNameOf(Ci.Path), Er.Line]),
            'not caught here')];
          Keys:= Keys + [Format('esc|%d|%d', [Ci.Id, Er.Line])];
        end;
      end;
    end;
    { no cap on handler rows (they carry edges); callers beyond -Cap are disclosed }
    Inc(FNodeId);
    Inc(FClusters);
    var Nid:= 'n' + IntToStr(FNodeId);
    var Cells: TArray<TDotRow>:= [];
    var Keep: TArray<string>:= [];
    var Shown:= 0;
    var Hidden:= 0;
    var SkipHandlers:= False;
    for var I:= 0 to High(Rows) do
    begin
      if Keys[I] = CALLER_ROW_KEY then
      begin
        if Shown >= FArgs.Cap then
        begin
          Inc(Hidden);
          SkipHandlers:= True;
          Continue;
        end;
        Inc(Shown);
        SkipHandlers:= False;
      end
      else if SkipHandlers then
        Continue;
      Cells:= Cells + [Rows[I]];
      Keep:= Keep + [Keys[I]];
      Inc(FAnchored);
    end;
    var More:= DisclosureText(Hidden, 0, 'callers');
    if More <> '' then
    begin
      Cells:= Cells + [NoteRow(More)];
      Keep:= Keep + [CALLER_ROW_KEY];
    end;
    var Ports:= AddRowCluster(FSb, Format('cluster_d%d_%d', [D, FNodeId]), Nid, 'CALLERS',
      Format('depth %d, %d caller%s', [D, Length(AtD), Plural(Length(AtD))]), Cells, CallerStyle);
    for var I:= 0 to High(Keep) do
      if Keep[I] <> CALLER_ROW_KEY then
        FCatchPort.AddOrSetValue(Keep[I], Ports[I]);
    { the exception travels UP: from the callee level to the level that called it }
    FSb.AppendLine(Format('  %s -> %s [color="%s", label=" escapes to depth %d "];', [PrevPort, Nid, CALLER_BORDER, D]));
    PrevPort:= Nid;
  end;
end;

{ ---- 5. dot: handler edges, raise row -> the caller handler, styled by what was PROVEN ---- }
procedure TExceptionPathsChart.DrawHandlerEdges;
begin
  for var Ev in FEvents do
  begin
    var From: string;
    if not FPortOfType.TryGetValue(Ev.TypeName, From) then
      From:= if FRaiseNid <> '' then FRaiseNid else FFnid;
    var Target: string;
    if not FCatchPort.TryGetValue(Format('%d|%d', [Ev.CallerId, Ev.Handler.Pos]), Target) then
      Continue;
    var At:= Format('%s:%d on the call to %s', [Ev.CallerName, Ev.Handler.Line, CalleeName(Ev.Callee)]);
    var Lbl: string;
    var St:= 'penwidth=2';
    if Ev.Kind = EV_CAUGHT then
      Lbl:= Format('caught (%s) at %s', [Ev.How, At])
    else if Ev.Kind = EV_PARTIAL then
      Lbl:= Format('caught (%s) at %s for %d of %d call sites', [Ev.How, At, Ev.Inside, Ev.Total])
    else if Ev.Kind = EV_RERAISED then
      Lbl:= Format('caught and re-raised (%s) at %s', [Ev.How, At])
    else
    begin
      St:= 'style=dashed';
      Lbl:= if Ev.Kind = EV_UNVERIFIED then 'handler in caller body; call site not verified inside its try [inferred]'
        else 'may catch -- ancestry not in this index';
    end;
    FSb.AppendLine(Format('  %s -> %s [color="%s", %s, label=" %s "];', [From, Target, HANDLE_BORDER, St, XmlText(Lbl)]));
  end;
  FSb.AppendLine('}');
end;

{ a Measure-Object -Sum: a [double] above 0, else the int 0 the script sets }
function TExceptionPathsChart.SumOf(const pCounts: TArray<Integer>; const pName: string): TMetaField;
begin
  var S:= 0;
  for var N in pCounts do
    Inc(S, N);
  Result:= if S > 0 then TMetaField.Real(pName, S) else TMetaField.Int(pName, 0);
end;

function TExceptionPathsChart.ResultFields: TArray<TMetaField>;
begin
  var Lines: TArray<Integer>:= [];
  for var R in FBody.Raises do
    Lines:= Lines + [R.Line];
  var RaiseLines:= SortedIntsText(Lines);
  Lines:= [];
  for var R in FBody.Handles do
    Lines:= Lines + [R.Line];
  var HandleLines:= SortedIntsText(Lines);
  var Inferred: TArray<string>:= [];
  for var S in FBody.Inferred do
    Inferred:= Inferred + [Format('%s@%d', [S.Kind, S.Line])];
  var CallerNames: TArray<string>:= [];
  var NotEvaluated: TArray<string>:= [];
  for var C in FCallers do
  begin
    var Dn:= Format('d%d:%s', [C.D, C.Info.Name]);
    CallerNames:= CallerNames + [Dn];
    var Evaluated:= False;
    for var Tr in FTypeResults do
      for var E in Tr.Walk.Edges do
        if E.Caller = C.Info.Id then
          Evaluated:= True;
    if not Evaluated then
      NotEvaluated:= NotEvaluated + [Dn];
  end;
  var Caught: TArray<Integer>:= [];
  var Escapes: TArray<Integer>:= [];
  var Ends: TArray<Integer>:= [];
  var Capped: TArray<Integer>:= [];
  var Both: TArray<Integer>:= [];
  var Paths: TArray<string>:= [];
  for var Tr in FTypeResults do
  begin
    Caught:= Caught + [Length(Tr.Catchers)];
    Escapes:= Escapes + [Length(Tr.Walk.Escapes)];
    Ends:= Ends + [Length(Tr.Walk.Ends)];
    Capped:= Capped + [Length(Tr.Walk.Capped)];
    Both:= Both + [Length(Tr.CatchAndPass)];
    Paths:= Paths + [Format('%s:%d/%d/%d/%d/%d', [Tr.TypeName, Length(Tr.Catchers), Length(Tr.Walk.Escapes),
      Length(Tr.Walk.Ends), Tr.Walk.Evaluated, Length(Tr.Walk.Capped)])];
  end;
  var Events: TArray<string>:= [];
  for var Ev in FEvents do
    Events:= Events + [Format('%s:%s:%d', [Ev.Kind, Ev.CallerName, Ev.Handler.Line])];
  var Walk:= TMetaField.Str('WalkSentence', string.Join('; ', FWalkLines));
  if Length(FWalkLines) = 0 then
    Walk.Json:= 'null';
  var Solid:= EventCount(EV_CAUGHT) + EventCount(EV_PARTIAL) + EventCount(EV_RERAISED);
  Result:= [TMetaField.Str('Qname', FSel.QName), TMetaField.Int('Raises', Length(FBody.Raises)),
    TMetaField.Int('RaiseTypes', Length(FRaiseTypes)), TMetaField.Str('RaiseTypeNames', string.Join(',', FRaiseTypes)),
    TMetaField.Str('RaiseLines', RaiseLines), TMetaField.Int('Handles', Length(FBody.Handles)),
    TMetaField.Str('HandleLines', HandleLines), TMetaField.Int('Dropped', FBody.Dropped),
    TMetaField.Int('Inferred', Length(FBody.Inferred)), TMetaField.Int('InferredRaises', Length(FInfRaise)),
    TMetaField.Int('BareExcepts', Length(FInfBare)), TMetaField.Str('InferredLines', string.Join(',', Inferred)),
    TMetaField.Int('StaleRows', Length(FBody.StaleRows)), TMetaField.Bool('FocusFresh', FBody.Fresh)];
  Result:= Result + [TMetaField.Int('Callers', Length(FCallers)), TMetaField.Int('CallerLevels', FLevels),
    TMetaField.Str('CallerNames', string.Join(',', CallerNames)), TMetaField.Bool('CallersCapped', FCallerCapped),
    SumOf(Caught, 'Caught'), SumOf(Escapes, 'Escapes'), SumOf(Ends, 'NoCallerEnds'), SumOf(Capped, 'CappedCallers'),
    SumOf(Both, 'CatchAndPass'), TMetaField.Str('TypePaths', string.Join(',', Paths)), TMetaField.Int('SolidEdges', Solid),
    TMetaField.Int('ReRaised', EventCount(EV_RERAISED)), TMetaField.Int('Partial', EventCount(EV_PARTIAL)),
    TMetaField.Int('Unverified', EventCount(EV_UNVERIFIED)), TMetaField.Int('MayCatch', EventCount(EV_MAY))];
  Result:= Result + [TMetaField.Int('NotGuarding', FNgCount), TMetaField.Int('NotGuardingUndrawn', FNgUndrawn),
    TMetaField.Str('NotEvaluated', string.Join(',', NotEvaluated)), TMetaField.Int('NoVerdicts', FNoCount),
    TMetaField.Int('StaleCallers', FStaleCallers), TMetaField.Str('Events', string.Join(',', Events)), Walk,
    TMetaField.Int('FilesTouched', FTouched.Count), TMetaField.Int('StaleFiles', FTouched.Count - FFreshFiles),
    TMetaField.Int('IndexCandidates', FIdx.Candidates), TMetaField.Int('IndexRaise', FIdx.RaiseSites),
    TMetaField.Int('IndexHandle', FIdx.HandleSites), TMetaField.Int('IndexDropped', FIdx.Dropped),
    TMetaField.Int('IndexRaiseRoutines', FIdx.RaiseRoutines), TMetaField.Int('IndexHandleRoutines', FIdx.HandleRoutines),
    TMetaField.Int('Clusters', FClusters)];
end;

function TExceptionPathsChart.Emit(const pOutDir: string): TChartResult;
begin
  SelectFocus;
  ReadFocus;
  WalkCallers;
  ReadCallers;
  HandledWhere;
  EndNotes;
  DrawFocus;
  DrawBody;
  DrawCallers;
  DrawHandlerEdges;

  var Msgs: TArray<string>;
  Result.Layout:= DotLayout(FArgs.Dot, FSb.ToString, pOutDir, 'excpaths_' + TRegEx.Replace(FSel.QName, '[^A-Za-z0-9]', '_'), Msgs);
  Result.LeftCount:= Length(FBody.Raises);
  Result.RightCount:= Length(FBody.Handles);
  Result.ClickTargets:= Result.Layout.Anchors;
  Result.AllClickable:= Result.Layout.Anchors >= FAnchored;
  Result.Fields:= ResultFields + [TMetaField.Int('ClickTargets', Result.Layout.Anchors), TMetaField.Int('Expected', FAnchored),
    TMetaField.Bool('AllClickable', Result.AllClickable)];
end;

function Emit(const pArgs: TQuestionArgs; const pOutDir: string): TChartResult;
begin
  var Chart:= TExceptionPathsChart.Create(pArgs);
  try
    Result:= Chart.Emit(pOutDir);
  finally
    Chart.Free;
  end;
end;

initialization
  RegisterChartQuestion(EXCEPTION_PATHS_ID, Emit);

end.
