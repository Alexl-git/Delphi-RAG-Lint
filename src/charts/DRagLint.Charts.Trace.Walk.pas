unit DRagLint.Charts.Trace.Walk;  // dl:ok unit-too-large@6ccb -- REVIEWED 2026-10-18: the port of Trace.Walk.ps1 Parts 3-5 (one PS part per unit, ruling R-B); the classifier, the server and the routes share the walker's side-keyed caches

(* The round-trip WALK (a port of charts\src\Trace.Walk.ps1 Parts 3-5 -- lines 860-1999 minus
  Get-EventWiring, plus the fresh-checked wrappers of 748-756 and 792-804; the PS output is the
  reference). From the anchor's handler (or a fill call, or a server dispatch arm) down the bodies of the
  routines it reaches, as numbered trace items.

  Part 3, the routine facts and the classifier (PS 898-905, 1277-1289): one routine BODY, line by line.
  A routine's facts are every ref in its impl range joined to the symbol it binds to (call_edges target
  first, then refs.symbol_id) with the target's unit tested against the transport convention (tpipe), and
  every literal; a NESTED routine's refs and literals are left out (it is walked as its own routine).
  Bound callees are walked and kept only when their subtree holds a step (drops logger noise); a CROSSES
  item carries Command for the driver. Conditions hang on the step of their `if` line, else the nearest
  step of this body above it, else they come back in Conds for the caller's CALLS step. A line inside a
  branch for ANOTHER table (T5-R1) is not walked, and one OMITS step counts it and quotes the condition
  (only a routine whose literals name such a table is read for this). Every step line's enclosing CHAIN
  is read (fix round 1, Important 1): every if around a path step is written ONCE, verbatim, on the first
  path step of its branch -- WHEN in the then branch, UNLESS in the else; when exactly ONE side answers
  (a success response or a commit, T5-R10 / T5-R12) the OTHER side is that condition's `-- else` note,
  not steps; an except handler is the note of UNLESS <try body> raises. A response overwritten later on
  the path is a default; an attached On* handler runs at its receiver's ApplyUpdates, not at the attach.

  Part 4, the server (PS 1603-1609, 1693-1725, 1831-1839): DISPATCH (engine ask E2 retires it) is a read
  of the command constant inside a transport-unit routine, then the first BOUND call after it whose
  target is declared OUTSIDE that unit, bounded by the next enum read. DATABASE (ruling P15): the STOPS
  says only what was QUERIED -- a SQL fact naming the anchor table is kept; otherwise the statement
  member (UpdateSQL / SelectSQL and the write-statement members of final-review M7) is named where a
  walked routine names it, with its load line from FIB$DATASETS_INFO (FW-R1) and the fb_datasets row
  count of THIS index; a READ names the SELECT literal's assignments as written and carries After, the
  RUNS step the DATABASE steps stand behind (M4).

  Part 5, the routes (PS 1919-1986): the READ fill routes (a bound call on a line of the dataset's unit
  that carries the TABLE literal and names the dataset, whose callee's subtree reaches a CROSSES -- each
  walked with its OWN Seen), the traced route ids (M1: the first CLIENT crossing of each direction is its
  sender, the owners before it are on the page) and ALSO (P10: the other callers of a sender whose
  payload names the anchor table).

  RT3 -- INDEX SCOPING. The PS rebinds $DbPath dynamically (Invoke-OnDb) and its caches key on it.
  Delphi has no dynamic scope: the walker holds BOTH indexes (Near = CLIENT, Far = SERVER) with their
  readers, every method takes the side explicitly (TTraceSide), and the facts, impl and source caches are
  keyed by side. Server handling and database steps run on tsServer; everything else on the side asked.

  PowerShell traps closed here: $Visited is a hashtable of ints (TDictionary<Integer, Byte>); the
  context's Seen keys `<path>|<line>` and every other string-keyed hashtable are case-INSENSITIVE
  (TIStringComparer.Ordinal); `[int]$_.tpipe -eq 1` where tpipe may be NULL (TIndexRow.I reads 0);
  `-eq` / `-ne` / `-in` / `-contains` / `-like` / `-match` on strings are case-insensitive (SameText,
  StartsText, TRegEx with IgnoreCase) and `-ceq` / `-cmatch` are not; `$items.Remove($s0)` removes by
  reference (the item is extracted and freed when the walk ends, because later tests still read it);
  `$items.Contains($_)` is a reference test; `Select-Object -First 1` after Where is the first in LIST
  order and `Select-Object -Unique` keeps first-seen order (a list with a Contains check), while
  `Sort-Object -Unique` sorts (SortUniqueNames for strings, a numeric sort for ints); `Measure-Object
  -Minimum` over col reads the refs' 1-based start_col and the walk passes it on as written;
  `$deferred.Remove($d)` runs inside a foreach over a COPY; `-like 'SENDS rsp*'` is a case-insensitive
  prefix test; `$h0.Children.Insert($k, ...)` keeps the caller's conditions ahead of the callee's; the
  unary-comma returns are plain lists here. The hashtable key order the PS sorts branches from (`$br.Keys
  | Sort-Object { IfLine }`) is not reproducible: ties on IfLine keep first-seen order (TPsSort).

  OWNERSHIP. Every list a method returns is a NEW object the caller frees; the items in it are owned by
  that list, so a caller that hands them to a TTraceSection extracts them (TObjectList.Extract) or sets
  OwnsObjects False once it has handed over every one. TServerHandling.Stop and TDatabaseSteps.After are
  BORROWED pointers into an owning list. The OMITS records Merge-TraceOmits reads are kept by the walker
  (an Add-Member property in the PS), keyed by the item; an item is read as OMITS only when its Omits flag
  is set. *)

interface

uses
  System.SysUtils
  , System.Generics.Collections
  , DRagLint.Charts.Index
  , DRagLint.Charts.Source
  , DRagLint.Charts.Sql
  , DRagLint.Charts.Trace.FormA
  , DRagLint.Charts.Trace.Shim
  , DRagLint.Charts.Trace.Anchor  // dl:unit DRagLint.Charts.Trace.Anchor accepted -- RT_EVENTS, the write events, travel with the anchor's dataset and its wiring reader
  ;

type
  /// <summary>One entry of the RT_OPS verb table: a dataset op / transaction / SQL call and the verb its step gets.</summary>
  TRtOp = record
    /// <summary>The call name (matched case-insensitively).</summary>
    Name: string;
    /// <summary>The step verb.</summary>
    Verb: string;
  end;

  /// <summary>One entry of RT_FB_SNAPSHOT: a FIB$ table and the engine table that snapshots it.</summary>
  TRtFbSnapshot = record
    /// <summary>The FIB$ table, upper case.</summary>
    Table   : string;
    /// <summary>The index table holding its rows.</summary>
    Snapshot: string;
  end;

const
  /// <summary>The calls that are DATASET OPs / transaction / SQL steps, and the verb they get (the PS $script:RtOps).</summary>
  RT_OPS: array[0..11] of TRtOp = (
    (Name: 'SaveToStream'; Verb: 'SERIALIZES'), (Name: 'LoadFromStream'; Verb: 'DESERIALIZES'),
    (Name: 'CommitUpdates'; Verb: 'APPLIES'), (Name: 'CancelUpdates'; Verb: 'APPLIES'), (Name: 'ApplyUpdates'; Verb: 'APPLIES'),
    (Name: 'EmptyDataSet'; Verb: 'EMPTIES'), (Name: 'StartTransaction'; Verb: 'OPENS'), (Name: 'Commit'; Verb: 'RUNS'),
    (Name: 'Rollback'; Verb: 'RUNS'), (Name: 'Execute'; Verb: 'RUNS'), (Name: 'ExecSQL'; Verb: 'RUNS'), (Name: 'Open'; Verb: 'RUNS'));
  /// <summary>A FIB$ literal that is SQL reading a FIB$ table, not a message that names one (the PS $script:RtFibSqlRx).</summary>
  RT_FIB_SQL_RX = '(?i)\b(FROM|JOIN|INTO|UPDATE)\s+FIB\$';
  /// <summary>The write-statement members of a dataset definition (final-review M7).</summary>
  RT_WRITE_STMTS: array[0..3] of string = ('InsertSQL', 'UpdateSQL', 'ModifySQL', 'DeleteSQL');
  /// <summary>The FIB$ tables whose snapshot the index may hold (the PS $script:RtFbSnapshot).</summary>
  RT_FB_SNAPSHOT: array[0..1] of TRtFbSnapshot = (
    (Table: 'FIB$DATASETS_INFO'; Snapshot: 'fb_datasets'), (Table: 'FIB$FIELDS_INFO'; Snapshot: 'fb_field_info'));
  /// <summary>The Windows I/O primitives that make a TRANSPORT-CONVENTION callee a step of the path (RC-R6).</summary>
  RT_OUTWARD_IO_CALLS: array[0..3] of string = ('WriteFile', 'WriteFileEx', 'TransactNamedPipe', 'CallNamedPipe');
  /// <summary>The success responses (ruling T5-R13): a write acknowledged, rows returned.</summary>
  RT_SUCCESS_RSP: array[0..1] of string = ('rspOK', 'rspData');

type
  /// <summary>Which index a call reads: the CLIENT (near) or the SERVER (far) one (RT3).</summary>
  TTraceSide = (tsClient, tsServer);

  /// <summary>One routine's body facts. Port of the Get-RoutineFacts object.</summary>
  /// <remarks>Owns Refs and Lits. Cached by the walker per side and id; never free one the walker returned.</remarks>
  TRoutineFacts = class
  public
    /// <summary>symbols.id.</summary>
    Id       : Integer;
    /// <summary>symbols.name.</summary>
    Name     : string;
    /// <summary>symbols.qualified_name.</summary>
    QName    : string;
    /// <summary>The qualified name without its unit (Class.Method).</summary>
    Short    : string;
    /// <summary>The declaring file as indexed.</summary>
    Path     : string;
    /// <summary>files.id of Path.</summary>
    Fid      : Integer;
    /// <summary>symbols.parent_id; 0 when NULL.</summary>
    Pid      : Integer;
    /// <summary>symbols.impl_start_line; 0 when there is no body.</summary>
    ImplStart: Integer;
    /// <summary>symbols.impl_end_line.</summary>
    ImplEnd  : Integer;
    /// <summary>symbols.start_line (the declaration).</summary>
    Decl     : Integer;
    /// <summary>symbol_facts.sql_reads; '' when NULL.</summary>
    SqlReads : string;
    /// <summary>symbol_facts.sql_writes; '' when NULL.</summary>
    SqlWrites: string;
    /// <summary>Every ref of the body (rid kind nm recv line col ecol tid tkind tname tq tistart tdecl tpath tfid tpipe), by line, column, id.</summary>
    Refs     : TObjectList<TIndexRow>;
    /// <summary>Every literal / format literal of the body (kind text line col ecol), by line, column, id.</summary>
    Lits     : TObjectList<TIndexRow>;
    /// <summary>Constructor: empty lists.</summary>
    constructor Create;
    /// <summary>Frees the lists.</summary>
    destructor Destroy; override;
  end;

  /// <summary>A fresh file's raw and stripped line arrays (the PS Get-TraceSource object).</summary>
  TTraceSource = record
    /// <summary>The lines as written (Latin-1).</summary>
    Raw     : TArray<string>;
    /// <summary>The same lines with comments, strings and directives blanked column for column.</summary>
    Stripped: TArray<string>;
  end;

  /// <summary>What the walk is parametrised by: the anchor, the boundary convention and the two index names (the PS $Ctx hashtable).</summary>
  /// <remarks>Owns Seen. The PS copies the hashtable per fill route with Seen cleared (Clone) and per dry walk with Seen copied
  /// (Clone(True)). Not thread-safe.</remarks>
  TTraceContext = class
  public
    /// <summary>The anchor table; '' when none.</summary>
    Table      : string;
    /// <summary>The anchor column.</summary>
    Column     : string;
    /// <summary>TABLE.COLUMN.</summary>
    TableColumn: string;
    /// <summary>The anchor dataset; valid when HasDataSet.</summary>
    DataSet    : TTraceDataSet;
    /// <summary>False for the PS $null dataset.</summary>
    HasDataSet : Boolean;
    /// <summary>The transport-unit condition on symbols u (BoundaryLikes).</summary>
    Likes      : string;
    /// <summary>The CLIENT index's name (the FROM facet of a crossing).</summary>
    NearIndex  : string;
    /// <summary>The SERVER index's name (the TO facet; named in the server's stop texts).</summary>
    FarIndex   : string;
    /// <summary>`<path>|<line>` of every FIB$ literal already shown; case-insensitive keys.</summary>
    Seen       : TDictionary<string, Byte>;
    /// <summary>Constructor: an empty context.</summary>
    constructor Create;
    /// <summary>Frees Seen.</summary>
    destructor Destroy; override;
    /// <summary>A copy of this context.</summary>
    /// <param name="pWithSeen">True: Seen is copied (a dry walk); False: Seen starts empty (a fill route).</param>
    /// <returns>A new context the caller frees.</returns>
    function Clone(pWithSeen: Boolean = False): TTraceContext;
  end;

  /// <summary>What one Walk-Routine returned: the items and the conditions no step of the body could host.</summary>
  /// <remarks>Owns both lists and what is in them. The caller frees it.</remarks>
  TWalkResult = class
  public
    /// <summary>The trace items, in walk order; owned.</summary>
    Items: TObjectList<TTraceItem>;
    /// <summary>The pending conditions for the caller's CALLS step; owned.</summary>
    Conds: TObjectList<TTraceChild>;
    /// <summary>Constructor: empty lists.</summary>
    constructor Create;
    /// <summary>Frees the lists and their contents.</summary>
    destructor Destroy; override;
  end;

  /// <summary>The server side of one command. Port of the Get-ServerHandling object.</summary>
  /// <remarks>Owns Items. Stop is BORROWED from Items (nil when the server side was walked).</remarks>
  TServerHandling = class
  public
    /// <summary>The ROUTES / CALLS / handler items, or the one STOPS; owned.</summary>
    Items         : TObjectList<TTraceItem>;
    /// <summary>The rsp* constants the walked routines read, Sort-Object -Unique order.</summary>
    Responses     : TArray<string>;
    /// <summary>False for the PS $null contract.</summary>
    HasContract   : Boolean;
    /// <summary>The dispatch target's qualified name.</summary>
    ContractText  : string;
    /// <summary>The target's declaration anchor.</summary>
    ContractAnchor: string;
    /// <summary>True when a handler was reached and walked (final-review I2).</summary>
    Walked        : Boolean;
    /// <summary>The STOPS that ended the server side; nil when Walked. Borrowed from Items.</summary>
    Stop          : TTraceItem;
    /// <summary>Constructor: an empty list.</summary>
    constructor Create;
    /// <summary>Frees Items.</summary>
    destructor Destroy; override;
  end;

  /// <summary>The DATABASE steps of one direction. Port of Get-DatabaseSteps' array plus the select stop's After.</summary>
  /// <remarks>Owns Items. After is BORROWED from the server items the steps were built from.</remarks>
  TDatabaseSteps = class
  public
    /// <summary>The STOPS / column steps; owned.</summary>
    Items: TObjectList<TTraceItem>;
    /// <summary>A read: the server step that RUNS the query (the DATABASE steps stand right after it); nil when none.</summary>
    After: TTraceItem;
    /// <summary>Constructor: an empty list.</summary>
    constructor Create;
    /// <summary>Frees Items.</summary>
    destructor Destroy; override;
  end;

  /// <summary>One fill route of the anchor dataset. Port of a Get-FillRoutes row.</summary>
  /// <remarks>Owns Walk and Ctx.</remarks>
  TFillRoute = class
  public
    /// <summary>The fill call's line.</summary>
    Line       : Integer;
    /// <summary>The routine holding the call (Class.Method); '' when none.</summary>
    Routine    : string;
    /// <summary>The callee's symbols.id.</summary>
    TargetId   : Integer;
    /// <summary>The callee's short name.</summary>
    TargetShort: string;
    /// <summary>The callee's file as indexed.</summary>
    TargetPath : string;
    /// <summary>The callee's impl start line.</summary>
    TargetImpl : Integer;
    /// <summary>The fill line's literals, quoted from source, each after a space; '' when none.</summary>
    Lits       : string;
    /// <summary>The callee's walk (it holds a crossing); owned.</summary>
    Walk       : TWalkResult;
    /// <summary>The route's own context (Seen of its own); owned.</summary>
    Ctx        : TTraceContext;
    /// <summary>Frees Walk and Ctx.</summary>
    destructor Destroy; override;
  end;

  /// <summary>What the traced paths already show. Port of the Get-TracedRouteIds object.</summary>
  TTracedRoutes = record
    /// <summary>Each direction's first CLIENT crossing (borrowed).</summary>
    Senders: TArray<TTraceItem>;
    /// <summary>The owners of the client items before it, first-seen order.</summary>
    Callers: TArray<Integer>;
  end;

  /// <summary>The round-trip walker over the CLIENT and SERVER indexes (Trace.Walk.ps1 Parts 3-5).</summary>
  /// <remarks>Nothing passed to the constructor is owned: the indexes, readers, catalogue and table set must
  /// outlive the walker. Source overrides (a stale-file test) live on the readers. Holds the per-run caches
  /// the PS kept in $script: variables, keyed by side. Not thread-safe.</remarks>
  TTraceWalker = class  // dl:ok high-response@8975 -- REVIEWED 2026-10-18: the walker IS the PS Part 3-5 family (Get-RoutineFacts .. Get-AlsoRoutes); its response set is the SQL, shim and model calls each part makes, split into one private method per PS helper
  private
    type
      { the $Tgt / Resolve-HandlerByName object: what a CALLS step names }
      TCallTarget = record
        Found: Boolean;
        Id   : Integer;
        Short: string;
        Path : string;
        Line : Integer;
        Grade: string;
        Ask  : string;
      end;
      { one New-OmitStep record: Count, Keyword, Condition, Anchor, Routine }
      TOmitRec = record
        Count    : Integer;
        Keyword  : string;
        Condition: string;
        Anchor   : string;
        Routine  : string;
      end;
      { the $G Get-ElseNote reads: a shim result's block (with its fail span) or a synthetic block }
      TElseScope = record
        BlockStart: Integer;
        BlockEnd  : Integer;
        ExitArg   : string;
        Form      : string;
        SpanLine  : Integer;
        SpanFrom  : Integer;
        SpanTo    : Integer;
      end;
      { one step line's facts (the PS $info[$ln]) }
      TLineInfo = class
        Rs   : TArray<TIndexRow>;
        Lits : TArray<TIndexRow>;
        Chain: TArray<TShimResult>;
      end;
      { the Get-PayloadText object }
      TPayload = record
        Text: string;
        Note: string;
      end;
    var
    FNear      : TChartsIndex;
    FFar       : TChartsIndex;
    FNearReader: TSourceReader;
    FFarReader : TSourceReader;
    FCatalog   : TSqlCatalog;
    FSet       : TSqlTableSet;
    FResolver  : TTraceAnchorResolver;
    FFacts     : TObjectDictionary<string, TRoutineFacts>;
    FImpls     : TObjectDictionary<string, TObjectList<TIndexRow>>;
    FSources   : TDictionary<string, TTraceSource>;
    FOmits     : TDictionary<TTraceItem, TArray<TOmitRec>>;
    function IndexOf(pSide: TTraceSide): TChartsIndex;
    function ReaderOf(pSide: TTraceSide): TSourceReader;
    function OutwardIoCallee(pSide: TTraceSide; pId: Integer; pCtx: TTraceContext): Boolean;
    function FormatTraceLiteral(pSide: TTraceSide; pLit: TIndexRow; const pPath: string; pFid: Integer): string;
    function LineLits(pSide: TTraceSide; const pLits: TArray<TIndexRow>; const pPath: string; pFid: Integer): string;
    function ResolveImplByName(pSide: TTraceSide; const pRecv, pName: string; pF: TRoutineFacts): TObjectList<TIndexRow>;
    function ResolveHandlerByName(pSide: TTraceSide; pRef: TIndexRow; pF: TRoutineFacts): TCallTarget;
    function FibLiterals(pSide: TTraceSide; pFid: Integer): TObjectList<TIndexRow>;
    function ElseNote(pSide: TTraceSide; pF: TRoutineFacts; const pG: TElseScope): string;
    function PayloadText(pSide: TTraceSide; pF: TRoutineFacts; pLine: Integer; pCtx: TTraceContext): TPayload;
    procedure AddCallsStep(pList: TObjectList<TTraceItem>; const pTgt: TCallTarget; pSub: TWalkResult; pCaller: TRoutineFacts;
      pSiteLine: Integer; const pLits: string; pAlways: Boolean; const pNote: string = '');
    function LineCandidateCols(pSide: TTraceSide; const pRs, pLits: TArray<TIndexRow>; pF: TRoutineFacts): TArray<Integer>;
    function LineYield(pSide: TTraceSide; pI: TLineInfo; pF: TRoutineFacts; pDepth: Integer; pVisited: TDictionary<Integer, Byte>;
      pCtx: TTraceContext): Integer;
    function DryYield(pSide: TTraceSide; pId, pDepth: Integer; pVisited: TDictionary<Integer, Byte>; pDry: TTraceContext;
      out pAny: Boolean): Integer;
    function NewOmitStep(const pRecs: TArray<TOmitRec>): TTraceItem;
    function WalkedCaseSelector(const pItems: TArray<TTraceItem>; pF: TRoutineFacts; pLine: Integer; out pSelector: string;
      out pSelLine: Integer): Boolean;
    function SelectStop(const pServerItems: TArray<TTraceItem>; pCtx: TTraceContext; out pAfter: TTraceItem): TTraceItem;
    function WriteStatementStop(const pServerItems: TArray<TTraceItem>; pCtx: TTraceContext): TTraceItem;
    function CountRows(pSide: TTraceSide; const pTable: string): Integer;
  public
    /// <summary>Constructor.</summary>
    /// <param name="pNear">The CLIENT index; not owned.</param>
    /// <param name="pFar">The SERVER index; not owned.</param>
    /// <param name="pNearReader">A source reader over pNear; not owned.</param>
    /// <param name="pFarReader">A source reader over pFar; not owned.</param>
    /// <param name="pCatalog">The SQL catalogue (the column state of the DATABASE steps); not owned.</param>
    /// <param name="pSet">The SQL table set (the PS $SqlSet); not owned.</param>
    constructor Create(pNear, pFar: TChartsIndex; pNearReader, pFarReader: TSourceReader; pCatalog: TSqlCatalog;
      pSet: TSqlTableSet);
    /// <summary>Frees the caches.</summary>
    destructor Destroy; override;
    /// <summary>One routine's body facts, cached per side and id for the run.</summary>
    /// <param name="pSide">The index the id belongs to.</param>
    /// <param name="pId">symbols.id.</param>
    /// <param name="pLikes">The transport-unit condition (BoundaryLikes) the tpipe column tests.</param>
    /// <returns>The walker's own facts; do not free them.</returns>
    /// <exception cref="EChartsTrace">'Get-RoutineFacts: symbol &lt;id&gt; is not in the &lt;client|server&gt; index'.</exception>
    /// <remarks>Port of Get-RoutineFacts (Trace.Walk.ps1:906). The SQL is verbatim.</remarks>
    function RoutineFacts(pSide: TTraceSide; pId: Integer; const pLikes: string): TRoutineFacts;
    /// <summary>A FRESH file's raw and stripped lines, read once per side and path.</summary>
    /// <param name="pSide">The index the path belongs to.</param>
    /// <param name="pPath">A path of that index.</param>
    /// <returns>The lines (shared; do not modify).</returns>
    /// <exception cref="EChartsTrace">'round-trip: &lt;leaf&gt; differs from the indexed copy (sha256) -- refusing to read it. Reindex the project, then re-run.' (AC-14, RT16).</exception>
    /// <remarks>Port of Get-TraceSource (Trace.Walk.ps1:794).</remarks>
    function TraceSource(pSide: TTraceSide; const pPath: string): TTraceSource;
    /// <summary>The guard condition around the Exit on one line, read from FRESH source.</summary>
    /// <param name="pSide">The index the path belongs to.</param>
    /// <param name="pPath">A path of that index.</param>
    /// <param name="pExitLine">The Exit's line.</param>
    /// <param name="pRoutineStart">The routine's impl start line.</param>
    /// <returns>The shim's result (Form 'unknown' with a Reason for anything it cannot read).</returns>
    /// <exception cref="EChartsTrace">'round-trip: &lt;leaf&gt; differs from the indexed copy (sha256) -- refusing to quote a condition from it. Reindex the project, then re-run.'</exception>
    /// <remarks>Port of Get-GuardCondition (Trace.Walk.ps1:748).</remarks>
    function GuardCondition(pSide: TTraceSide; const pPath: string; pExitLine, pRoutineStart: Integer): TShimResult;
    /// <summary>One routine BODY, line by line, as trace items (spec section 4's classifier).</summary>
    /// <param name="pSide">The index pId belongs to.</param>
    /// <param name="pId">The routine's symbols.id.</param>
    /// <param name="pDepth">Call levels left; below 0 nothing is walked.</param>
    /// <param name="pVisited">The routines already walked on this path; the walk adds pId. Shared with the callees (a routine is walked once).</param>
    /// <param name="pCtx">The context; its Seen grows with every FIB$ literal shown.</param>
    /// <returns>A new result the caller frees: the items and the conditions no step of this body hosts.</returns>
    /// <exception cref="EChartsTrace">A walked file is stale (TraceSource / GuardCondition), or the model refuses a text.</exception>
    /// <remarks>Port of Walk-Routine (Trace.Walk.ps1:1290).</remarks>
    function WalkRoutine(pSide: TTraceSide; pId, pDepth: Integer; pVisited: TDictionary<Integer, Byte>;
      pCtx: TTraceContext): TWalkResult;
    /// <summary>The server side of one command, on the SERVER index: the dispatch arm, the handler, its walk.</summary>
    /// <param name="pCmdName">The cmd* constant the crossing carries.</param>
    /// <param name="pCtx">The context (the walk adds to its Seen).</param>
    /// <param name="pDepth">Call levels for the handler's walk.</param>
    /// <returns>A new result the caller frees. Walked False with Stop set when no arm or no one implementation was found.</returns>
    /// <remarks>Port of Get-ServerHandling (Trace.Walk.ps1:1647) with Find-DispatchArm and Resolve-InterfaceImpl.</remarks>
    function ServerHandling(const pCmdName: string; pCtx: TTraceContext; pDepth: Integer): TServerHandling;
    /// <summary>The DATABASE steps below a walked server side, on the SERVER index (ruling P15).</summary>
    /// <param name="pServerItems">The server items (TServerHandling.Items, in order).</param>
    /// <param name="pCtx">The context (Table, Column, TableColumn, FarIndex).</param>
    /// <param name="pMode">'write' or 'read' (case-insensitive).</param>
    /// <returns>A new result the caller frees: a STOPS naming the statement (unless a SQL fact names the table), then the column step
    /// or its STOPS. A read's select stop sets After.</returns>
    /// <remarks>Port of Get-DatabaseSteps (Trace.Walk.ps1:1726), Get-WalkedCaseSelector and Get-SelectStop.</remarks>
    function DatabaseSteps(const pServerItems: TArray<TTraceItem>; pCtx: TTraceContext; const pMode: string): TDatabaseSteps;
    /// <summary>The routines that FILL the anchor dataset and reach a crossing, on the CLIENT index, by line.</summary>
    /// <param name="pDs">The anchor dataset.</param>
    /// <param name="pCtx">The context; each route gets its own copy with an empty Seen.</param>
    /// <param name="pDepth">Call levels for each candidate's walk.</param>
    /// <returns>A new owning list the caller frees; the first is traced, the rest are ALSO.</returns>
    /// <remarks>Port of Get-FillRoutes (Trace.Walk.ps1:1925).</remarks>
    function FillRoutes(const pDs: TTraceDataSet; pCtx: TTraceContext; pDepth: Integer): TObjectList<TFillRoute>;
    /// <summary>What the traced paths already show: each direction's first CLIENT crossing and the owners before it.</summary>
    /// <param name="pPaths">One item list per direction, in text order.</param>
    /// <returns>Senders (borrowed) and Callers (first-seen).</returns>
    /// <remarks>Port of Get-TracedRouteIds (Trace.Walk.ps1:1959). Pure. SERVER / DATABASE actors are skipped (M1).</remarks>
    class function TracedRouteIds(const pPaths: TArray<TArray<TTraceItem>>): TTracedRoutes; static;
    /// <summary>ALSO: the other callers of each traced sender whose payload names the anchor table, on the CLIENT index.</summary>
    /// <param name="pSenders">TracedRouteIds' Senders.</param>
    /// <param name="pSkipIds">Callers already on the page.</param>
    /// <param name="pCtx">The context (Table, Likes).</param>
    /// <returns>A new owning list of 'CALLS &lt;sender&gt;' steps by call line, anchored at the call site.</returns>
    /// <remarks>Port of Get-AlsoRoutes (Trace.Walk.ps1:1979) with Test-TableSpecificSender.</remarks>
    function AlsoRoutes(const pSenders: TArray<TTraceItem>; const pSkipIds: TArray<Integer>; pCtx: TTraceContext): TObjectList<TTraceItem>;
    /// <summary>ONE OMITS disclosure per section (T5-R1): the OMITS steps the walk left in pSection become one, at the place of the first.</summary>
    /// <param name="pSection">The section; its items are replaced in place (the merged ones are freed).</param>
    /// <remarks>Port of Merge-TraceOmits (Trace.Walk.ps1:1267). Fewer than two OMITS: nothing changes.</remarks>
    procedure MergeTraceOmits(pSection: TTraceSection);
    /// <summary>The number of files of one index (the A-RT5-ONDB proof).</summary>
    /// <param name="pSide">The index.</param>
    /// <returns>SELECT COUNT(*) FROM files.</returns>
    function FilesCount(pSide: TTraceSide): Integer;
    /// <summary>An index's own last-indexed stamp, UTC to the minute (final-review M3).</summary>
    /// <param name="pIndex">Any index (the SQL one too); not owned.</param>
    /// <returns>'yyyy-MM-ddTHH:mmZ' from schema_meta indexed_at_unix, or 'unstamped' when it is missing or not all digits.</returns>
    /// <remarks>Port of Get-IndexStamp (Emit-RoundTrip.ps1:95).</remarks>
    class function IndexStamp(pIndex: TChartsIndex): string; static;
  end;

/// <summary>The SQL condition on symbols u that matches the transport-unit naming convention.</summary>
/// <param name="pPattern">LIKE patterns joined by '|'.</param>
/// <returns>`u.qualified_name LIKE '&lt;p&gt;'` per part, joined ' OR '.</returns>
/// <remarks>Port of Get-BoundaryLikes (Trace.Walk.ps1:894).</remarks>
function BoundaryLikes(const pPattern: string): string;

/// <summary>The stream format a `SaveToStream(&lt;stream&gt;, &lt;format&gt;)` call names.</summary>
/// <param name="pRawLine">One raw source line.</param>
/// <returns>The last argument when it is one plain identifier, as written; '' otherwise.</returns>
/// <remarks>Port of Get-StreamFormat (Trace.Walk.ps1:973). Pure.</remarks>
function StreamFormat(const pRawLine: string): string;

implementation

uses
  System.Generics.Defaults
  , System.RegularExpressions
  , System.DateUtils
  , System.Math
  , System.StrUtils
  , DRagLint.Charts.Text
  , DRagLint.Charts.Columns
  , DRagLint.Charts.PsSort
  ;

const
  KIND_STEP = 'step';
  KIND_STOPS = 'stops';
  KIND_CROSSES = 'crosses';
  GRADE_BY_NAME = 'by name';
  GRADE_INFERRED = 'inferred';
  ASK_E1 = 'E1';
  ASK_E2 = 'E2';
  ASK_E3 = 'E3';
  ASK_E4 = 'E4';
  SIDE_KEY: array[TTraceSide] of string = ('client', 'server');
  { ConvertTo-TraceWord's cap on a FIB$ literal (READS <text>) }
  FIB_WORD_MAX = 60;
  { Get-ElseNote: a literal must be longer than this, trimmed, to be the one the branch sends out }
  ELSE_LIT_MIN = 8;
  RE_SELF = '^Self\.';
  RE_TPL_TAIL = '<.*$';
  RE_TRACE_UNSAFE = '"| @| \[| -- |--$|[^\x20-\x7E]';
  RE_NOTE_UNSAFE = '"|; |[^\x20-\x7E]';
  RE_SELECTOR_UNSAFE = '"| @| \[| -- |; ';
  RE_ASSIGN_UNSAFE = '"| @| \[| -- |; |\s\s|[^\x20-\x7E]';
  RE_OMIT_UNSAFE = '; |[\r\n]';
  RE_RAISE = '\braise\b';
  RE_STREAM = '\bSaveToStream\s*\(([^()]*)\)';
  RE_IDENT = '^[A-Za-z_]\w*$';
  RE_CASE_SELECTOR = '^case\s+(.+?)\s+of$';
  RE_RUNS_EXEC = '^RUNS (\S+\.)?(Execute|ExecSQL)\b';
  RE_FIB_DATASETS = '^READS .*FIB\$DATASETS_INFO';
  RE_RUNS_APPLIES = '^(RUNS|APPLIES) ';
  RE_FIB_READ = '^READS .*\bFIB\$\w+';
  RE_FIB_TABLE = '\b(FIB\$\w+)';
  RE_RUNS_OPEN = '^RUNS (\S+\.)?Open\b';
  RE_SELECT_LIT = '^\s*SELECT\b';
  RE_SQL_FACT_SPLIT = '[,;\s]+';
  RE_PAYLOAD_KV = '[=|]';
  RE_SENDS = '^SENDS ';
  RE_DIGITS = '^\d+$';
  STAMP_FORMAT = 'yyyy-mm-dd"T"hh:nn"Z"';
  STAMP_NONE = 'unstamped';
  COMMIT_CALLS: array[0..1] of string = ('CommitUpdates', 'Commit');
  BRANCH_FORMS: array[0..1] of string = ('inline', 'block');
  SIDE_THEN = 'then';
  SIDE_ELSE = 'else';
  SIDES: array[0..1] of string = (SIDE_THEN, SIDE_ELSE);
  FIB_DATASETS = 'fb_datasets';

  SQL_FACTS = 'SELECT s.id AS id, s.name AS name, s.qualified_name AS q, s.impl_start_line AS istart, s.impl_end_line AS iend, ' +
    's.start_line AS decl, f.path AS path, s.file_id AS fid, s.parent_id AS pid, sf.sql_reads AS sqlr, sf.sql_writes AS sqlw ' +
    'FROM symbols s JOIN files f ON f.id = s.file_id LEFT JOIN symbol_facts sf ON sf.symbol_id = s.id WHERE s.id = %d';
  SQL_FACT_REFS = 'SELECT r.id AS rid, r.kind AS kind, r.name_text AS nm, r.receiver_text AS recv, r.start_line AS line, ' +
    'r.start_col AS col, r.end_col AS ecol, t.id AS tid, t.kind AS tkind, t.name AS tname, t.qualified_name AS tq, ' +
    't.impl_start_line AS tistart, t.start_line AS tdecl, tf.path AS tpath, t.file_id AS tfid, ' +
    '(SELECT 1 FROM symbols u WHERE u.file_id = t.file_id AND u.kind = ''unit'' AND (%s)) AS tpipe FROM refs r ' +
    'LEFT JOIN symbols t ON t.id = COALESCE((SELECT ce.target_symbol_id FROM call_edges ce WHERE ce.ref_id = r.id), r.symbol_id) ' +
    'LEFT JOIN files tf ON tf.id = t.file_id WHERE r.file_id = %d AND r.start_line BETWEEN %d AND %d ' +
    'AND (r.enclosing_symbol_id = %d OR r.enclosing_symbol_id IS NULL)';
  SQL_FACT_LITS = 'SELECT sl.kind AS kind, sl.text AS text, sl.start_line AS line, sl.start_col AS col, sl.end_col AS ecol ' +
    'FROM string_literals sl WHERE sl.file_id = %d AND sl.start_line BETWEEN %d AND %d AND sl.kind IN (''literal'', ''format'') ' +
    'AND NOT EXISTS (SELECT 1 FROM symbols n WHERE n.parent_id = %d AND n.impl_start_line > 0 AND sl.start_line BETWEEN ' +
    'n.impl_start_line AND n.impl_end_line)';
  SQL_SCOPE_TYPES = 'SELECT DISTINCT COALESCE(TRIM(s.signature), '''') AS sig, s.kind AS k FROM symbols s ' +
    'WHERE UPPER(s.name) = UPPER(''%s'') AND %s';
  SQL_IMPL_BY_NAME = 'SELECT s.id AS id, s.qualified_name AS q, s.impl_start_line AS istart, f.path AS path, s.file_id AS fid, ' +
    's.parent_id AS pid, ''%s'' AS rkinds FROM symbols s JOIN files f ON f.id = s.file_id WHERE s.name = ''%s'' AND ' +
    's.kind = ''method'' AND s.impl_start_line > 0 AND s.parent_id IN (SELECT c.id FROM symbols c WHERE c.kind = ''class'' ' +
    'AND UPPER(c.name) IN (%s))';
  SQL_HANDLER_BY_NAME = 'SELECT s.id AS id, s.qualified_name AS q, s.impl_start_line AS istart, f.path AS path FROM symbols s ' +
    'JOIN files f ON f.id = s.file_id WHERE s.parent_id = %d AND s.name = ''%s'' AND s.kind = ''method'' AND s.impl_start_line > 0';
  SQL_FIB_LITS = 'SELECT sl.text AS text, sl.start_line AS line, sl.id AS id, (SELECT s.name FROM symbols s WHERE ' +
    's.file_id = sl.file_id AND s.impl_start_line <= sl.start_line AND s.impl_end_line >= sl.start_line AND s.kind IN ' +
    '(''method'',''procedure'',''function'',''constructor'') ORDER BY s.impl_start_line DESC LIMIT 1) AS routine ' +
    'FROM string_literals sl WHERE sl.file_id = %d AND sl.kind = ''literal'' AND sl.text LIKE ''%%FIB$%%''';
  SQL_DISPATCH_READS = 'SELECT r.start_line AS line, encl.id AS eid, encl.qualified_name AS routine, encl.impl_end_line AS iend, ' +
    'f.path AS path, f.id AS fid FROM refs r JOIN symbols tgt ON tgt.id = r.symbol_id JOIN symbols encl ON ' +
    'encl.id = r.enclosing_symbol_id JOIN files f ON f.id = encl.file_id JOIN symbols u ON u.file_id = f.id AND u.kind = ''unit'' ' +
    'WHERE tgt.kind = ''enum_value'' AND tgt.name = ''%s'' AND (%s) ORDER BY f.path, r.start_line';
  SQL_DISPATCH_NEXT = 'SELECT MIN(r.start_line) AS l FROM refs r JOIN symbols t ON t.id = r.symbol_id WHERE ' +
    'r.enclosing_symbol_id = %d AND t.kind = ''enum_value'' AND r.start_line > %d';
  SQL_DISPATCH_CALL = 'SELECT r.start_line AS line, t.id AS id, t.qualified_name AS q, t.kind AS kind, t.impl_start_line AS istart, ' +
    't.start_line AS decl, t.name AS name, tf.path AS path FROM refs r JOIN call_edges ce ON ce.ref_id = r.id JOIN symbols t ON ' +
    't.id = ce.target_symbol_id JOIN files tf ON tf.id = t.file_id WHERE r.enclosing_symbol_id = %d AND r.start_line > %d AND ' +
    'r.start_line <= %d AND t.file_id <> %d ORDER BY r.start_line, r.start_col LIMIT 1';
  SQL_IFACE_IMPL = 'SELECT s.id AS id, s.qualified_name AS q, s.impl_start_line AS istart, f.path AS path FROM symbols s ' +
    'JOIN files f ON f.id = s.file_id WHERE s.name = ''%s'' AND s.kind = ''method'' AND s.impl_start_line > 0 AND s.parent_id IN ' +
    '(SELECT c.id FROM symbols c WHERE c.kind = ''class'' AND c.heritage LIKE ''%%%s%%'')';
  SQL_ENUM_DECL = 'SELECT s.start_line AS l, f.path AS p FROM symbols s JOIN files f ON f.id = s.file_id WHERE ' +
    's.kind = ''enum_value'' AND s.name = ''%s'' LIMIT 1';
  SQL_FILL_ROUTES = 'SELECT sl.start_line AS line, e.qualified_name AS routine, t.id AS tid, t.qualified_name AS tq, ' +
    't.impl_start_line AS tistart, tf.path AS tpath, r.id AS rid FROM string_literals sl JOIN refs r ON r.file_id = sl.file_id ' +
    'AND r.start_line = sl.start_line AND r.kind = ''call'' JOIN call_edges ce ON ce.ref_id = r.id JOIN symbols t ON ' +
    't.id = ce.target_symbol_id JOIN files tf ON tf.id = t.file_id LEFT JOIN symbols e ON e.id = r.enclosing_symbol_id ' +
    'WHERE sl.file_id = %d AND sl.kind = ''literal'' AND UPPER(sl.text) = ''%s'' AND t.impl_start_line > 0 AND EXISTS ' +
    '(SELECT 1 FROM refs d WHERE d.file_id = sl.file_id AND d.start_line = sl.start_line AND d.name_text = ''%s'')';
  SQL_FILL_LITS = 'SELECT sl.kind AS kind, sl.text AS text, sl.start_line AS line, sl.start_col AS col, sl.end_col AS ecol ' +
    'FROM string_literals sl WHERE sl.file_id = %d AND sl.start_line = %d AND sl.kind = ''literal'' ORDER BY sl.start_col, sl.id';
  SQL_SENDER_CALLERS = 'SELECT e.id AS eid, e.qualified_name AS q, r.start_line AS line, ef.path AS path, r.id AS rid ' +
    'FROM call_edges ce JOIN refs r ON r.id = ce.ref_id JOIN symbols e ON e.id = r.enclosing_symbol_id JOIN files ef ON ' +
    'ef.id = e.file_id WHERE ce.target_symbol_id = %d';
  SQL_COUNT = 'SELECT COUNT(*) AS n FROM %s';
  SQL_STAMP = 'SELECT value AS v FROM schema_meta WHERE key = ''indexed_at_unix''';

{ ---- small helpers ------------------------------------------------------------------------- }

function InNames(const pName: string; const pList: array of string): Boolean;
begin
  for var S in pList do
    if SameText(pName, S) then
      Exit(True);
  Result:= False;
end;

function OpVerb(const pName: string; out pVerb: string): Boolean;
begin
  pVerb:= '';
  for var Op in RT_OPS do
    if SameText(Op.Name, pName) then
    begin
      pVerb:= Op.Verb;
      Exit(True);
    end;
  Result:= False;
end;

function IsOp(const pName: string): Boolean;
begin
  var V: string;
  Result:= OpVerb(pName, V);
end;

function IsKind(pR: TIndexRow; const pKind: string): Boolean;
begin
  Result:= SameText(pR.S('kind'), pKind);
end;

function IsCall(pR: TIndexRow): Boolean;
begin
  Result:= IsKind(pR, 'call');
end;

function IsEnum(pR: TIndexRow): Boolean;
begin
  Result:= SameText(pR.S('tkind'), 'enum_value');
end;

function IsEventRef(pR: TIndexRow): Boolean;
begin
  Result:= IsKind(pR, 'member-access') and InNames(pR.S('nm'), RT_EVENTS);
end;

{ a bound call into project code: tid set, a body, not a constructor }
function IsBoundCall(pR: TIndexRow): Boolean;
begin
  Result:= IsCall(pR) and (pR.I('tid') <> 0) and (pR.I('tistart') > 0) and not SameText(pR.S('tkind'), 'constructor');
end;

function IsPipe(pR: TIndexRow): Boolean;
begin
  Result:= pR.I('tpipe') = 1;
end;

function Filter(const pRows: TArray<TIndexRow>; const pPred: TFunc<TIndexRow, Boolean>): TArray<TIndexRow>;
begin
  var L:= TList<TIndexRow>.Create;
  try
    for var R in pRows do
      if pPred(R) then
        L.Add(R);
    Result:= L.ToArray;
  finally
    L.Free;
  end;
end;

{ the handler a wiring line names: the last read / member-access / call that is neither the event nor its receiver }
function HandlerRefs(const pRs: TArray<TIndexRow>; pE0: TIndexRow): TArray<TIndexRow>;
begin
  Result:= Filter(pRs, function(R: TIndexRow): Boolean
    begin
      Result:= (IsKind(R, 'read') or IsKind(R, 'member-access') or IsCall(R)) and not SameText(R.S('nm'), pE0.S('nm')) and
        not SameText(R.S('nm'), pE0.S('recv'));
    end);
end;

function SortedUniqueInts(const pValues: TArray<Integer>): TArray<Integer>;
begin
  var L:= TList<Integer>.Create;
  try
    for var V in pValues do
      if not L.Contains(V) then
        L.Add(V);
    L.Sort;
    Result:= L.ToArray;
  finally
    L.Free;
  end;
end;

function LastSegment(const pQName: string): string;
begin
  var P:= pQName.LastIndexOf('.');
  Result:= if P < 0 then pQName else pQName.Substring(P + 1);
end;

{ `$a, $b = $Anchor -split ':'` }
procedure SplitAnchor(const pAnchor: string; out pFile: string; out pLine: Integer);
begin
  var Parts:= pAnchor.Split([':']);
  pFile:= if Length(Parts) > 0 then Parts[0] else '';
  pLine:= if Length(Parts) > 1 then StrToIntDef(Parts[1], 0) else 0;
end;

procedure AddRtItem(pList: TObjectList<TTraceItem>; pItem: TTraceItem; pLine, pOwner: Integer);
begin
  pItem.Line:= pLine;
  pItem.Owner:= pOwner;
  pList.Add(pItem);
end;

procedure MoveItems(pFrom, pTo: TObjectList<TTraceItem>);
begin
  pFrom.OwnsObjects:= False;
  try
    for var I in pFrom do
      pTo.Add(I);
    pFrom.Clear;
  finally
    pFrom.OwnsObjects:= True;
  end;
end;

procedure MoveConds(pFrom, pTo: TObjectList<TTraceChild>);
begin
  pFrom.OwnsObjects:= False;
  try
    for var C in pFrom do
      pTo.Add(C);
    pFrom.Clear;
  finally
    pFrom.OwnsObjects:= True;
  end;
end;

{ the `X, Y or Z` join of the PS: all but the last joined ', ', then pLastSep and the last }
function JoinLast(const pParts: TArray<string>; const pLastSep: string): string;
begin
  if Length(pParts) <= 1 then
    Exit(string.Join('', pParts));
  Result:= string.Join(', ', Copy(pParts, 0, Length(pParts) - 1)) + pLastSep + pParts[High(pParts)];
end;

{ Test-SuccessLine }
function SuccessLine(const pRs: TArray<TIndexRow>): Boolean;
begin
  var Ok:= False;
  var Wr:= False;
  for var R in pRs do
  begin
    if IsEnum(R) and InNames(R.S('tname'), RT_SUCCESS_RSP) then
      Ok:= True;
    if IsKind(R, 'write') then
      Wr:= True;
    if IsCall(R) and InNames(R.S('nm'), COMMIT_CALLS) then
      Exit(True);
  end;
  Result:= Ok and Wr;
end;

{ ---- the context, the results ------------------------------------------------------------- }

constructor TRoutineFacts.Create;
begin
  inherited Create;
  Refs:= TObjectList<TIndexRow>.Create;
  Lits:= TObjectList<TIndexRow>.Create;
end;

destructor TRoutineFacts.Destroy;
begin
  Refs.Free;
  Lits.Free;
  inherited Destroy;
end;

constructor TTraceContext.Create;
begin
  inherited Create;
  Seen:= TDictionary<string, Byte>.Create(TIStringComparer.Ordinal);
end;

destructor TTraceContext.Destroy;
begin
  Seen.Free;
  inherited Destroy;
end;

function TTraceContext.Clone(pWithSeen: Boolean): TTraceContext;
begin
  Result:= TTraceContext.Create;
  Result.Table:= Table;
  Result.Column:= Column;
  Result.TableColumn:= TableColumn;
  Result.DataSet:= DataSet;
  Result.HasDataSet:= HasDataSet;
  Result.Likes:= Likes;
  Result.NearIndex:= NearIndex;
  Result.FarIndex:= FarIndex;
  if pWithSeen then
    for var P in Seen do
      Result.Seen.AddOrSetValue(P.Key, P.Value);
end;

constructor TWalkResult.Create;
begin
  inherited Create;
  Items:= TObjectList<TTraceItem>.Create;
  Conds:= TObjectList<TTraceChild>.Create;
end;

destructor TWalkResult.Destroy;
begin
  Items.Free;
  Conds.Free;
  inherited Destroy;
end;

constructor TServerHandling.Create;
begin
  inherited Create;
  Items:= TObjectList<TTraceItem>.Create;
end;

destructor TServerHandling.Destroy;
begin
  Items.Free;
  inherited Destroy;
end;

constructor TDatabaseSteps.Create;
begin
  inherited Create;
  Items:= TObjectList<TTraceItem>.Create;
end;

destructor TDatabaseSteps.Destroy;
begin
  Items.Free;
  inherited Destroy;
end;

destructor TFillRoute.Destroy;
begin
  Walk.Free;
  Ctx.Free;
  inherited Destroy;
end;

{ ---- one routine's walk (the Walk-Routine body, block by block) ---------------------------- }

type
  TRowList = TList<TIndexRow>;

  { a condition on its way to a host step (the PS $co / $conds entries) }
  TCondRec = class
  public
    IfLine      : Integer;
    Guard       : Boolean;
    Item        : TTraceChild;
    Placed      : Boolean;
    HasHostFrom : Boolean;
    HostFrom    : Integer;
    HostTo      : Integer;
    HasHostLines: Boolean;
    HostLines   : TArray<Integer>;
    IsStrict    : Boolean;
    destructor Destroy; override;
  end;

  { one if of the body's branch structure (the PS $br / $xb entries) }
  TBranch = class
  public
    E        : TShimResult;
    ThenLines: TList<Integer>;
    ElseLines: TList<Integer>;
    Removed  : TList<Integer>;
    Side     : string;
    constructor Create(const pE: TShimResult);
    destructor Destroy; override;
  end;

  { an On* handler attached to a dataset, waiting for its ApplyUpdates }
  TDeferred = class
  public
    Recv : string;
    Event: string;
    Hs   : TTraceWalker.TCallTarget;
    Line : Integer;
  end;

  TRoutineWalk = class  // dl:ok god-class@504e, high-response@504e -- REVIEWED 2026-10-18: the state of ONE Walk-Routine call (its PS locals) and its five blocks, one method each; splitting it would pass that state between classes and lose the line-for-line map to Trace.Walk.ps1:1290-1601
  private
    FWalker        : TTraceWalker;
    FSide     : TTraceSide;
    FId       : Integer;
    FDepth    : Integer;
    FVisited  : TDictionary<Integer, Byte>;
    FCtx      : TTraceContext;
    FRoutine        : TRoutineFacts;
    FItems    : TObjectList<TTraceItem>;
    FPend     : TObjectList<TTraceChild>;
    FSrc      : TTraceSource;
    FRefsAt   : TObjectDictionary<Integer, TRowList>;
    FLitsAt   : TObjectDictionary<Integer, TRowList>;
    FConds    : TObjectList<TCondRec>;
    FSkip     : TDictionary<Integer, Byte>;
    FGuardGs  : TArray<TShimResult>;
    FAllTok   : TArray<TShimToken>;
    FAllLines : TArray<Integer>;
    FInfo     : TObjectDictionary<Integer, TTraceWalker.TLineInfo>;
    FInfoLines: TArray<Integer>;
    FOmitLines: TDictionary<Integer, Byte>;
    FOmitRecs : TList<TTraceWalker.TOmitRec>;
    FOmitFirst: Integer;
    FDropped  : TObjectList<TTraceItem>;
    function RowsAt(pMap: TObjectDictionary<Integer, TRowList>; pLine: Integer): TArray<TIndexRow>;
    function Anchor(pLine: Integer): string;
    procedure IndexBody;
    procedure ReadGuards;
    procedure ReadLineInfo;
    procedure ReadOmits;
    procedure ReadBranches;
    procedure AddBranchConds(pBr: TObjectDictionary<string, TBranch>; const pOrder: TList<string>);
    procedure AddExceptConds(pXb: TObjectDictionary<string, TBranch>; const pOrder: TList<string>);
    procedure Classify;
    function ClassifyCrossing(pLn: Integer; const pRs: TArray<TIndexRow>): Boolean;
    function ClassifyOps(pLn: Integer; const pRs, pLits: TArray<TIndexRow>; pDeferred: TObjectList<TDeferred>): Boolean;
    function ClassifyEvent(pLn: Integer; const pRs: TArray<TIndexRow>; pDeferred: TObjectList<TDeferred>): Boolean;
    procedure ClassifyCalls(pLn: Integer; const pRs, pLits: TArray<TIndexRow>);
    procedure OverwrittenSends;
    procedure SqlFact(const pVerb, pTables, pNote: string);
    procedure SqlFacts;
    procedure HostConds;
  public
    constructor Create(pW: TTraceWalker; pSide: TTraceSide; pId, pDepth: Integer; pVisited: TDictionary<Integer, Byte>;
      pCtx: TTraceContext; pRes: TWalkResult);
    destructor Destroy; override;
    procedure Run;
  end;

destructor TCondRec.Destroy;
begin
  if not Placed then
    Item.Free;
  inherited Destroy;
end;

constructor TBranch.Create(const pE: TShimResult);
begin
  inherited Create;
  E:= pE;
  ThenLines:= TList<Integer>.Create;
  ElseLines:= TList<Integer>.Create;
  Removed:= TList<Integer>.Create;
end;

destructor TBranch.Destroy;
begin
  Removed.Free;
  ElseLines.Free;
  ThenLines.Free;
  inherited Destroy;
end;

function MinOf(pL: TList<Integer>): Integer;
begin
  Result:= pL[0];
  for var V in pL do
    Result:= Min(Result, V);
end;

function MaxOf(pL: TList<Integer>): Integer;
begin
  Result:= pL[0];
  for var V in pL do
    Result:= Max(Result, V);
end;

function BlockScope(pFrom, pTo: Integer): TTraceWalker.TElseScope;
begin
  Result:= Default(TTraceWalker.TElseScope);
  Result.BlockStart:= pFrom;
  Result.BlockEnd:= pTo;
end;

function BranchKey(const pE: TShimResult): string;
begin
  Result:= IntToStr(pE.StmtLine) + ':' + IntToStr(pE.StmtCol);
end;

{ `$b.Side -in 'then', 'else' -and $b.Side -ne $side`: the path follows the OTHER side only }
function OtherSideOnly(const pBranchSide, pSide: string): Boolean;
begin
  Result:= ((pBranchSide = SIDE_THEN) or (pBranchSide = SIDE_ELSE)) and (pBranchSide <> pSide);
end;

constructor TRoutineWalk.Create(pW: TTraceWalker; pSide: TTraceSide; pId, pDepth: Integer; pVisited: TDictionary<Integer, Byte>;
  pCtx: TTraceContext; pRes: TWalkResult);
begin
  inherited Create;
  FWalker:= pW;
  FSide:= pSide;
  FId:= pId;
  FDepth:= pDepth;
  FVisited:= pVisited;
  FCtx:= pCtx;
  FRoutine:= pW.RoutineFacts(pSide, pId, pCtx.Likes);
  FItems:= pRes.Items;
  FPend:= pRes.Conds;
  FRefsAt:= TObjectDictionary<Integer, TRowList>.Create([doOwnsValues]);
  FLitsAt:= TObjectDictionary<Integer, TRowList>.Create([doOwnsValues]);
  FConds:= TObjectList<TCondRec>.Create;
  FSkip:= TDictionary<Integer, Byte>.Create;
  FInfo:= TObjectDictionary<Integer, TTraceWalker.TLineInfo>.Create([doOwnsValues]);
  FOmitLines:= TDictionary<Integer, Byte>.Create;
  FOmitRecs:= TList<TTraceWalker.TOmitRec>.Create;
  FDropped:= TObjectList<TTraceItem>.Create;
end;

destructor TRoutineWalk.Destroy;
begin
  FDropped.Free;
  FOmitRecs.Free;
  FOmitLines.Free;
  FInfo.Free;
  FSkip.Free;
  FConds.Free;
  FLitsAt.Free;
  FRefsAt.Free;
  inherited Destroy;
end;

function TRoutineWalk.RowsAt(pMap: TObjectDictionary<Integer, TRowList>; pLine: Integer): TArray<TIndexRow>;
begin
  var L: TRowList;
  Result:= if pMap.TryGetValue(pLine, L) then L.ToArray else nil;
end;

function TRoutineWalk.Anchor(pLine: Integer): string;
begin
  Result:= TraceAnchorText(FRoutine.Path, pLine);
end;

procedure TRoutineWalk.Run;
begin
  IndexBody;
  ReadGuards;
  ReadLineInfo;
  ReadOmits;
  ReadBranches;
  Classify;
  OverwrittenSends;
  SqlFacts;
  HostConds;
end;

{ the body's refs and literals by line, built once }
procedure TRoutineWalk.IndexBody;
begin
  for var R in FRoutine.Refs do
  begin
    var L: TRowList;
    if not FRefsAt.TryGetValue(R.I('line'), L) then
    begin
      L:= TRowList.Create;
      FRefsAt.Add(R.I('line'), L);
    end;
    L.Add(R);
  end;
  for var R in FRoutine.Lits do
  begin
    var L: TRowList;
    if not FLitsAt.TryGetValue(R.I('line'), L) then
    begin
      L:= TRowList.Create;
      FLitsAt.Add(R.I('line'), L);
    end;
    L.Add(R);
  end;
end;

{ a guard's failure span on its `then` line is the else note, not path steps }
procedure DropSpan(pMap: TObjectDictionary<Integer, TRowList>; const pSp: TGuardSpan);
begin
  var L: TRowList;
  if pMap.TryGetValue(pSp.Line, L) then
    for var K:= L.Count - 1 downto 0 do
      if (L[K].I('col') - 1 >= pSp.FromCol) and (L[K].I('col') - 1 < pSp.ToCol) then
        L.Delete(K);
end;

{ the conditions: one per Exit the index anchored, quoted by the shim (E1); a condition two Exits share is
  written once; the branch that ends in the Exit is the OTHER path (its lines are skipped, its failure span on
  the `then` line too -- final-review I1) }
procedure TRoutineWalk.ReadGuards;
begin
  FSrc:= FWalker.TraceSource(FSide, FRoutine.Path);
  var Xs: TArray<Integer>;
  var ExitList:= TList<Integer>.Create;
  try
    for var R in FRoutine.Refs do
      if IsCall(R) and SameText(R.S('nm'), 'Exit') then
        ExitList.Add(R.I('line'));
    Xs:= SortedUniqueInts(ExitList.ToArray);
  finally
    ExitList.Free;
  end;
  var CondSeen:= TDictionary<string, Byte>.Create(TIStringComparer.Ordinal);
  var Gs:= TList<TShimResult>.Create;
  try
    for var Xl in Xs do
    begin
      var G:= FWalker.GuardCondition(FSide, FRoutine.Path, Xl, FRoutine.ImplStart);
      if SameText(G.Form, 'unknown') then
      begin
        AddRtItem(FItems, NewTraceStep(KIND_STOPS, TraceStopText(G.Reason), Anchor(Xl), '', FRoutine.Short,
          'no condition is quoted for this Exit', ASK_E1), Xl, FId);
        Continue;
      end;
      for var Q:= G.BlockStart to G.BlockEnd do
        if Q <> G.IfLine then
          FSkip.AddOrSetValue(Q, 1);
      var Scope:= BlockScope(G.BlockStart, G.BlockEnd);
      Scope.ExitArg:= G.ExitArg;
      Scope.Form:= G.Form;
      if (G.CondL2 > 0) and (G.CondL2 <= Length(FSrc.Stripped)) then
      begin
        var Sp:= GuardFailSpan(G, FSrc.Stripped[G.CondL2 - 1]);
        if Sp.Found then
        begin
          Scope.SpanLine:= Sp.Line;
          Scope.SpanFrom:= Sp.FromCol;
          Scope.SpanTo:= Sp.ToCol;
          DropSpan(FRefsAt, Sp);
          DropSpan(FLitsAt, Sp);
        end;
      end;
      var Ck:= Format('%d|%s|%s', [G.IfLine, G.Keyword, G.Condition]);
      if CondSeen.ContainsKey(Ck) then
        Continue;
      CondSeen.Add(Ck, 1);
      var Item:= NewTraceCond(G.Keyword, G.Condition, Anchor(G.IfLine), FWalker.ElseNote(FSide, FRoutine, Scope), ASK_E1);
      var Co:= TCondRec.Create;
      Co.Item:= Item;
      Co.IfLine:= G.IfLine;
      Co.Guard:= True;
      if SameText(G.Form, 'except') and (G.StmtLine <> 0) then
      begin
        Co.HasHostFrom:= True;
        Co.HostFrom:= G.StmtLine;
        Co.HostTo:= G.IfLine;
      end;
      FConds.Add(Co);
      Gs.Add(G);
    end;
    FGuardGs:= Gs.ToArray;
  finally
    Gs.Free;
    CondSeen.Free;
  end;
end;

{ every line that could make a step gets the CHAIN of its enclosing conditions, read once over the routine's tokens }
procedure TRoutineWalk.ReadLineInfo;
begin
  FAllTok:= ShimTokens(FSrc.Stripped, FRoutine.ImplStart, FRoutine.ImplEnd);
  FAllLines:= SortedUniqueInts(FRefsAt.Keys.ToArray + FLitsAt.Keys.ToArray);
  for var Ln in FAllLines do
  begin
    if FSkip.ContainsKey(Ln) then
      Continue;
    var Rs:= RowsAt(FRefsAt, Ln);
    var Lits:= RowsAt(FLitsAt, Ln);
    var Cols:= FWalker.LineCandidateCols(FSide, Rs, Lits, FRoutine);
    var CL:= TList<Integer>.Create;
    try
      CL.AddRange(Cols);
      for var R in Rs do
        if IsEventRef(R) then
          CL.Add(R.I('col'));
      if CL.Count = 0 then
        Continue;
      var I:= TTraceWalker.TLineInfo.Create;
      I.Rs:= Rs;
      I.Lits:= Lits;
      I.Chain:= EnclosingChainFromLines(FSrc.Raw, FSrc.Stripped, Ln, MinIntValue(CL.ToArray), FRoutine.ImplStart, FAllTok);
      FInfo.Add(Ln, I);
    finally
      CL.Free;
    end;
  end;
  FInfoLines:= SortedUniqueInts(FInfo.Keys.ToArray);
end;

{ T5-R1: a line inside a branch for another table is not walked; EVERY if of its chain is tested, innermost first (I5) }
procedure TRoutineWalk.ReadOmits;
begin
  if FCtx.Table = '' then
    Exit;
  var Others:= TList<string>.Create;
  try
    for var N in FWalker.FSet.Names do
      if not SameText(N, FCtx.Table) then
        Others.Add(UpperCase(N));
    var Branchy:= False;
    for var L in FRoutine.Lits do
      if IsKind(L, 'literal') and Others.Contains(UpperCase(L.S('text'))) then
      begin
        Branchy:= True;
        Break;
      end;
    if not Branchy then
      Exit;
  finally
    Others.Free;
  end;
  for var Ln in FInfoLines do
  begin
    var Found:= False;
    var E0: TShimResult;
    for var E in FInfo[Ln].Chain do
      if InNames(E.Form, BRANCH_FORMS) and OtherTableBranch(E.Keyword, E.Condition, FCtx.Table, FWalker.FSet.Names) then
      begin
        E0:= E;
        Found:= True;
        Break;
      end;
    if not Found then
      Continue;
    FOmitLines.AddOrSetValue(Ln, 1);
    var Y:= FWalker.LineYield(FSide, FInfo[Ln], FRoutine, FDepth, FVisited, FCtx);
    if Y > 0 then
    begin
      var Rec: TTraceWalker.TOmitRec;
      Rec.Count:= Y;
      Rec.Keyword:= E0.Keyword;
      Rec.Condition:= E0.Condition;
      Rec.Anchor:= Anchor(E0.IfLine);
      Rec.Routine:= FRoutine.Short;
      FOmitRecs.Add(Rec);
      if FOmitFirst = 0 then
        FOmitFirst:= Ln;
    end;
  end;
end;

{ Important 1 / T5-R10 / T5-R12: every if around a path step is written ONCE, on the first path step of its branch;
  when exactly ONE side answers, the other side is that condition's else note; an except handler is the note of
  UNLESS <try body> raises }
procedure TRoutineWalk.ReadBranches;
begin
  var Br:= TObjectDictionary<string, TBranch>.Create([doOwnsValues], TIStringComparer.Ordinal);
  var BrOrder:= TList<string>.Create;
  var Xb:= TObjectDictionary<string, TBranch>.Create([doOwnsValues], TIStringComparer.Ordinal);
  var XbOrder:= TList<string>.Create;
  try
    for var Ln in FInfoLines do
    begin
      if FOmitLines.ContainsKey(Ln) then
        Continue;
      for var E in FInfo[Ln].Chain do
      begin
        if not InNames(E.Form, BRANCH_FORMS) then
          Continue;
        var K:= BranchKey(E);
        var B: TBranch;
        if not Br.TryGetValue(K, B) then
        begin
          B:= TBranch.Create(E);
          Br.Add(K, B);
          BrOrder.Add(K);
        end;
        if E.Keyword = 'WHEN' then
          B.ThenLines.Add(Ln)
        else
          B.ElseLines.Add(Ln);
      end;
    end;
    for var K in BrOrder do
    begin
      var B:= Br[K];
      var Th:= TList<TTraceWalker.TLineInfo>.Create;
      var El:= TList<TTraceWalker.TLineInfo>.Create;
      try
        for var Ln in B.ThenLines do
          Th.Add(FInfo[Ln]);
        for var Ln in B.ElseLines do
          El.Add(FInfo[Ln]);
        var T:= False;
        for var I in Th do
          T:= T or SuccessLine(I.Rs);
        var E:= False;
        for var I in El do
          E:= E or SuccessLine(I.Rs);
        B.Side:= if T and E then 'both' else if T then SIDE_THEN else if E then SIDE_ELSE else 'none';
      finally
        El.Free;
        Th.Free;
      end;
    end;
    for var Ln in FInfoLines do
    begin
      if FOmitLines.ContainsKey(Ln) then
        Continue;
      for var E in FInfo[Ln].Chain do
      begin
        var K:= BranchKey(E);
        if SameText(E.Form, 'except') then
        begin
          var X: TBranch;
          if not Xb.TryGetValue(K, X) then
          begin
            X:= TBranch.Create(E);
            Xb.Add(K, X);
            XbOrder.Add(K);
          end;
          X.Removed.Add(Ln);
          FSkip.AddOrSetValue(Ln, 1);
          Break;
        end;
        if not InNames(E.Form, BRANCH_FORMS) or not Br.ContainsKey(K) then
          Continue;
        var S:= if E.Keyword = 'WHEN' then SIDE_THEN else SIDE_ELSE;
        if OtherSideOnly(Br[K].Side, S) then
        begin
          Br[K].Removed.Add(Ln);
          FSkip.AddOrSetValue(Ln, 1);
          Break;
        end;
      end;
    end;
    AddBranchConds(Br, BrOrder);
    AddExceptConds(Xb, XbOrder);
  finally
    XbOrder.Free;
    Xb.Free;
    BrOrder.Free;
    Br.Free;
  end;
end;

{ the branches by IfLine (first-seen order among ties: the PS hashtable order is not reproducible) }
function ByIfLine(pMap: TObjectDictionary<string, TBranch>; const pOrder: TList<string>): TArray<TBranch>;
begin
  var L:= TList<TBranch>.Create;
  try
    for var K in pOrder do
      L.Add(pMap[K]);
    Result:= L.ToArray;
  finally
    L.Free;
  end;
  TPsSort<TBranch>.Sort(Result, function(const pA, pB: TBranch): Integer begin Result:= CompareValue(pA.E.IfLine, pB.E.IfLine); end);
end;

procedure TRoutineWalk.AddBranchConds(pBr: TObjectDictionary<string, TBranch>; const pOrder: TList<string>);
begin
  var GuardIfs:= TDictionary<string, Byte>.Create(TIStringComparer.Ordinal);
  try
    for var Gc in FConds do
      if Gc.Guard then
        GuardIfs.AddOrSetValue(IntToStr(Gc.IfLine) + '|' + Gc.Item.Condition, 1);
    for var B in ByIfLine(pBr, pOrder) do
    begin
      if GuardIfs.ContainsKey(IntToStr(B.E.IfLine) + '|' + B.E.Condition) then
        Continue;
      for var S in SIDES do
      begin
        if OtherSideOnly(B.Side, S) then
          Continue;
        var Src_:= if S = SIDE_THEN then B.ThenLines else B.ElseLines;
        var OnPath:= TList<Integer>.Create;
        try
          for var Ln in Src_ do
            if not FSkip.ContainsKey(Ln) then
              OnPath.Add(Ln);
          if OnPath.Count = 0 then
            Continue;
          var Nt:= if (B.Side = S) and (B.Removed.Count > 0) then FWalker.ElseNote(FSide, FRoutine, BlockScope(MinOf(B.Removed), MaxOf(B.Removed)))
            else '';
          var Item:= NewTraceCond(if S = SIDE_THEN then 'WHEN' else 'UNLESS', B.E.Condition, Anchor(B.E.IfLine), Nt, ASK_E1);
          var Co:= TCondRec.Create;
          Co.Item:= Item;
          Co.IfLine:= B.E.IfLine;
          Co.HasHostLines:= True;
          Co.HostLines:= OnPath.ToArray;
          Co.IsStrict:= True;
          FConds.Add(Co);
        finally
          OnPath.Free;
        end;
      end;
    end;
  finally
    GuardIfs.Free;
  end;
end;

procedure TRoutineWalk.AddExceptConds(pXb: TObjectDictionary<string, TBranch>; const pOrder: TList<string>);
begin
  for var B in ByIfLine(pXb, pOrder) do
  begin
    { a handler that does nothing the walk would show (a logger line) has no else to name }
    var Sum:= 0;
    for var Ln in B.Removed do
      Inc(Sum, FWalker.LineYield(FSide, FInfo[Ln], FRoutine, FDepth, FVisited, FCtx));
    if Sum = 0 then
      Continue;
    var Nt:= FWalker.ElseNote(FSide, FRoutine, BlockScope(MinOf(B.Removed), MaxOf(B.Removed)));
    var Item:= NewTraceCond('UNLESS', B.E.Condition, Anchor(B.E.IfLine), Nt, ASK_E1);
    var Co:= TCondRec.Create;
    Co.Item:= Item;
    Co.IfLine:= B.E.IfLine;
    Co.HasHostFrom:= True;
    Co.HostFrom:= B.E.StmtLine;
    Co.HostTo:= B.E.IfLine;
    FConds.Add(Co);
  end;
end;

{ CROSSES: a transport call carrying a protocol constant }
function TRoutineWalk.ClassifyCrossing(pLn: Integer; const pRs: TArray<TIndexRow>): Boolean;
begin
  var Cmd:= Filter(pRs, function(R: TIndexRow): Boolean begin Result:= IsEnum(R) and StartsText('cmd', R.S('tname')); end);
  var Trans:= Filter(pRs, function(R: TIndexRow): Boolean begin Result:= IsCall(R) and IsPipe(R); end);
  Result:= (Length(Trans) > 0) and (Length(Cmd) > 0);
  if not Result then
    Exit;
  var C:= Cmd[0];
  var T0:= Trans[0];
  var X:= NewTraceStep(KIND_CROSSES, 'process boundary', Anchor(pLn), '', FRoutine.Short, C.S('tname') + ' via ' + T0.S('tname'));
  try
    X.Command:= C.S('tname');
    X.Children.Add(NewTraceFacet('FROM', FCtx.NearIndex, '', 'the index this side was read from'));
    X.Children.Add(NewTraceFacet('TO', FCtx.FarIndex, '', 'the counterpart index, queried separately'));
    X.Children.Add(NewTraceFacet('OVER', UnitNameOf(T0.S('tpath')) + '.' + T0.S('tname'), TraceAnchorText(T0.S('tpath'),
      T0.I('tistart')), 'transport unit matched by naming convention'));
    var Pt:= FWalker.PayloadText(FSide, FRoutine, pLn, FCtx);
    X.Children.Add(NewTraceFacet('WITH', C.S('tname') + ' ' + Pt.Text, Anchor(pLn), Pt.Note));
    X.Children.Add(NewTraceFacet('CONTRACT', C.S('tq'), TraceAnchorText(C.S('tpath'), C.I('tdecl')), ''));
  except
    on E: Exception do
    begin
      X.Free;
      raise;
    end;
  end;
  AddRtItem(FItems, X, pLn, FId);
end;

{ DATASET OP / transaction / SQL execution; an ApplyUpdates fires the handlers attached to its receiver }
function TRoutineWalk.ClassifyOps(pLn: Integer; const pRs, pLits: TArray<TIndexRow>; pDeferred: TObjectList<TDeferred>): Boolean;
begin
  var Ops:= Filter(pRs, function(R: TIndexRow): Boolean begin Result:= IsCall(R) and IsOp(R.S('nm')); end);
  for var O in Ops do
  begin
    var Verb: string;
    OpVerb(O.S('nm'), Verb);
    var Recv:= if O.S('recv') <> '' then O.S('recv') + '.' else '';
    AddRtItem(FItems, NewTraceStep(KIND_STEP, Verb + ' ' + Recv + O.S('nm') + FWalker.LineLits(FSide, pLits, FRoutine.Path, FRoutine.Fid), Anchor(pLn), '',
      FRoutine.Short), pLn, FId);
    if SameText(O.S('nm'), 'ApplyUpdates') then
    begin
      var Rv:= TRegEx.Replace(O.S('recv'), RE_SELF, '', [roIgnoreCase]);
      var Hit:= TList<TDeferred>.Create;
      try
        for var D in pDeferred do
          if SameText(D.Recv, Rv) then
            Hit.Add(D);
        for var D in Hit do
        begin
          var Sub:= FWalker.WalkRoutine(FSide, D.Hs.Id, FDepth - 1, FVisited, FCtx);
          FWalker.AddCallsStep(FItems, D.Hs, Sub, FRoutine, pLn, '', False, Format('fired by %s.ApplyUpdates at :%d, attached as %s.%s at :%d',
            [Rv, pLn, D.Recv, D.Event, D.Line]));
          pDeferred.Remove(D);
        end;
      finally
        Hit.Free;
      end;
    end;
  end;
  Result:= Length(Ops) > 0;
end;

{ event wiring / attach: `<x>.<Event> := <Handler>` }
function TRoutineWalk.ClassifyEvent(pLn: Integer; const pRs: TArray<TIndexRow>; pDeferred: TObjectList<TDeferred>): Boolean;
begin
  Result:= False;
  var Ev:= Filter(pRs, IsEventRef);
  if Length(Ev) = 0 then
    Exit;
  var E0:= Ev[0];
  var H:= HandlerRefs(pRs, E0);
  if Length(H) = 0 then
    Exit;
  var Hs:= FWalker.ResolveHandlerByName(FSide, H[High(H)], FRoutine);
  if not Hs.Found then
    Exit;
  var Verb:= if StartsText('On', E0.S('nm')) then 'ATTACHES' else 'FIRES';
  AddRtItem(FItems, NewTraceStep(KIND_STEP, Verb + ' ' + E0.S('recv') + '.' + E0.S('nm') + ' -> ' + Hs.Short, Anchor(pLn), Hs.Grade,
    FRoutine.Short, '', Hs.Ask), pLn, FId);
  if (Verb = 'ATTACHES') and (E0.S('recv') <> '') then
  begin
    var D:= TDeferred.Create;
    D.Recv:= TRegEx.Replace(E0.S('recv'), RE_SELF, '', [roIgnoreCase]);
    D.Event:= E0.S('nm');
    D.Hs:= Hs;
    D.Line:= pLn;
    pDeferred.Add(D);
  end
  else
    FWalker.AddCallsStep(FItems, Hs, FWalker.WalkRoutine(FSide, Hs.Id, FDepth - 1, FVisited, FCtx), FRoutine, pLn, '', False);
  Result:= True;
end;

{ bound calls into project code (descended), and unbound calls with a receiver the index declares (by name) }
procedure TRoutineWalk.ClassifyCalls(pLn: Integer; const pRs, pLits: TArray<TIndexRow>);
begin
  for var C in Filter(pRs, IsBoundCall) do
  begin
    var G1:= False;
    for var G in FGuardGs do
      G1:= G1 or InShimCondition(G, pLn, C.I('col'));
    var Io:= False;
    if not G1 and IsPipe(C) then
    begin
      Io:= FWalker.OutwardIoCallee(FSide, C.I('tid'), FCtx);
      if not Io then
        Continue;
    end;
    var Sub:= if IsPipe(C) then TWalkResult.Create else FWalker.WalkRoutine(FSide, C.I('tid'), FDepth - 1, FVisited, FCtx);
    var Tgt:= Default(TTraceWalker.TCallTarget);
    Tgt.Found:= True;
    Tgt.Id:= C.I('tid');
    Tgt.Short:= ShortName(C.S('tq'), UnitNameOf(C.S('tpath')));
    Tgt.Path:= C.S('tpath');
    Tgt.Line:= C.I('tistart');
    FWalker.AddCallsStep(FItems, Tgt, Sub, FRoutine, pLn, FWalker.LineLits(FSide, pLits, FRoutine.Path, FRoutine.Fid), G1 or Io);
  end;
  for var C in Filter(pRs, function(R: TIndexRow): Boolean begin Result:= IsCall(R) and (R.I('tid') = 0) and (R.S('recv') <> ''); end) do
  begin
    var Impl:= FWalker.ResolveImplByName(FSide, C.S('recv'), C.S('nm'), FRoutine);
    var Ask:= 'receiver-typed-calls';
    if Impl.Count > 0 then
      for var K in Impl[0].S('rkinds').Split([',']) do
        if InNames(K, ['field', 'property']) then
          Ask:= 'in-class-field-reads';
    if Impl.Count = 1 then
    begin
      var I:= Impl[0];
      var Sub:= FWalker.WalkRoutine(FSide, I.I('id'), FDepth - 1, FVisited, FCtx);
      var Tgt:= Default(TTraceWalker.TCallTarget);
      Tgt.Found:= True;
      Tgt.Id:= I.I('id');
      Tgt.Short:= ShortName(I.S('q'), UnitNameOf(I.S('path')));
      Tgt.Path:= I.S('path');
      Tgt.Line:= I.I('istart');
      Tgt.Grade:= GRADE_BY_NAME;
      Tgt.Ask:= Ask;
      FWalker.AddCallsStep(FItems, Tgt, Sub, FRoutine, pLn, FWalker.LineLits(FSide, pLits, FRoutine.Path, FRoutine.Fid), True);
      var Fl:= FWalker.FibLiterals(FSide, I.I('fid'));
      try
        for var L in Fl do
        begin
          var K:= I.S('path') + '|' + IntToStr(L.I('line'));
          if FCtx.Seen.ContainsKey(K) then
            Continue;
          FCtx.Seen.Add(K, 1);
          AddRtItem(FItems, NewTraceStep(KIND_STEP, 'READS ' + TraceWord(L.S('text'), FIB_WORD_MAX), TraceAnchorText(I.S('path'),
            L.I('line')), GRADE_INFERRED, L.S('routine'), Format('a FIB$ literal in %s, the unit of %s', [UnitNameOf(I.S('path')),
            Tgt.Short]), ASK_E4), pLn, FId);
        end;
      finally
        Fl.Free;
      end;
    end
    else if Impl.Count > 1 then
      AddRtItem(FItems, NewTraceStep(KIND_STOPS, TraceStopText(Format('%s.%s is unbound and %d classes implement %s',
        [C.S('recv'), C.S('nm'), Impl.Count, C.S('nm')])), Anchor(pLn), '', FRoutine.Short, '', Ask), pLn, FId);
  end;
end;

{ the per-line classifier, in the PS order: OMITS, CROSSES, RESPONSE, ops, FIB$ literals, wiring, calls; then the
  attached handlers no ApplyUpdates of their receiver fired }
procedure TRoutineWalk.Classify;
begin
  var Deferred:= TObjectList<TDeferred>.Create;
  try
    for var Ln in FAllLines do
    begin
      if FSkip.ContainsKey(Ln) then
        Continue;
      if FOmitLines.ContainsKey(Ln) then
      begin
        if Ln = FOmitFirst then
          AddRtItem(FItems, FWalker.NewOmitStep(FOmitRecs.ToArray), Ln, FId);
        Continue;
      end;
      var Rs:= RowsAt(FRefsAt, Ln);
      var Lits:= RowsAt(FLitsAt, Ln);
      if ClassifyCrossing(Ln, Rs) then
        Continue;
      var Rsp:= Filter(Rs, function(R: TIndexRow): Boolean begin Result:= IsEnum(R) and StartsText('rsp', R.S('tname')); end);
      if Length(Rsp) > 0 then
      begin
        var Verb:= if Length(Filter(Rs, function(R: TIndexRow): Boolean begin Result:= IsKind(R, 'write'); end)) > 0 then 'SENDS'
          else 'RECEIVES';
        var Names: TArray<string>;
        SetLength(Names, Length(Rsp));
        for var K:= 0 to High(Rsp) do
          Names[K]:= Rsp[K].S('tname');
        AddRtItem(FItems, NewTraceStep(KIND_STEP, Verb + ' ' + string.Join(' or ', SortUniqueNames(Names)), Anchor(Ln), '', FRoutine.Short),
          Ln, FId);
        Continue;
      end;
      if ClassifyOps(Ln, Rs, Lits, Deferred) then
        Continue;
      for var L in Lits do
      begin
        if not TRegEx.IsMatch(L.S('text'), RT_FIB_SQL_RX) then
          Continue;
        var K:= FRoutine.Path + '|' + IntToStr(Ln);
        if FCtx.Seen.ContainsKey(K) then
          Continue;
        FCtx.Seen.Add(K, 1);
        AddRtItem(FItems, NewTraceStep(KIND_STEP, 'READS ' + TraceWord(L.S('text'), FIB_WORD_MAX), Anchor(Ln), GRADE_INFERRED, FRoutine.Short,
          'a FIB$ literal in the body', ASK_E4), Ln, FId);
      end;
      if ClassifyEvent(Ln, Rs, Deferred) then
        Continue;
      ClassifyCalls(Ln, Rs, Lits);
    end;
    for var D in Deferred.ToArray do
      FWalker.AddCallsStep(FItems, D.Hs, FWalker.WalkRoutine(FSide, D.Hs.Id, FDepth - 1, FVisited, FCtx), FRoutine, D.Line, '', False,
        Format('attached as %s.%s at :%d, no %s.ApplyUpdates follows in this routine', [D.Recv, D.Event, D.Line, D.Recv]));
  finally
    Deferred.Free;
  end;
end;

{ Important 1: a response written and then OVERWRITTEN on the path is a default, not a send }
procedure TRoutineWalk.OverwrittenSends;
begin
  var Sends: TArray<TTraceItem>;
  var SL:= TList<TTraceItem>.Create;
  try
    for var I in FItems do
      if (I.Owner = FId) and (I.Kind = KIND_STEP) and StartsText('SENDS rsp', I.Text) then
        SL.Add(I);
    Sends:= SL.ToArray;
  finally
    SL.Free;
  end;
  for var S0 in Sends do
  begin
    var Tg0:= '';
    for var R in RowsAt(FRefsAt, S0.Line) do
      if IsKind(R, 'write') then
      begin
        Tg0:= R.S('nm');
        Break;
      end;
    if Tg0 = '' then
      Continue;
    var Later: TTraceItem:= nil;
    for var X in Sends do
    begin
      if (X.Line <= S0.Line) or not FItems.Contains(X) then
        Continue;
      for var R in RowsAt(FRefsAt, X.Line) do
        if IsKind(R, 'write') and SameText(R.S('nm'), Tg0) then
        begin
          Later:= X;
          Break;
        end;
      if Later <> nil then
        Break;
    end;
    if Later = nil then
      Continue;
    var Rn:= TRegEx.Replace(S0.Text, RE_SENDS, '', [roIgnoreCase]);
    FDropped.Add(FItems.Extract(S0));
    var Add:= Format('overwrites the %s default set at :%d', [Rn, S0.Line]);
    Later.Note:= if Later.Note <> '' then Later.Note + ', ' + Add else Add;
    for var Gc in FConds do
      if Gc.Guard and (Gc.IfLine > S0.Line) and (Gc.IfLine < Later.Line) then
        Gc.Item.Note:= if Gc.Item.Note <> '' then Format('%s, responds %s, the default set at :%d', [Gc.Item.Note, Rn, S0.Line])
          else Format('else responds %s, the default set at :%d', [Rn, S0.Line]);
  end;
end;

procedure TRoutineWalk.SqlFact(const pVerb, pTables, pNote: string);
begin
  if FCtx.Table = '' then
    Exit;
  for var Tb in TRegEx.Split(pTables, RE_SQL_FACT_SPLIT) do
    if (Tb <> '') and SameText(Tb, FCtx.Table) then
    begin
      AddRtItem(FItems, NewTraceStep(KIND_STEP, pVerb + ' ' + UpperCase(Tb), Anchor(FRoutine.ImplStart), '', FRoutine.Short, pNote), FRoutine.ImplEnd, FId);
      Exit;
    end;
end;

{ the routine's own SQL facts, at its last line, only the anchor's table (T5-R1) }
procedure TRoutineWalk.SqlFacts;
begin
  SqlFact('WRITES', FRoutine.SqlWrites, 'sql_writes fact');
  SqlFact('READS', FRoutine.SqlReads, 'sql_reads fact');
end;

{ every condition on its host step: its branch's first path step, an except body's first step, the step of its
  if line, else the nearest step above; a caller's if stands ahead of the callee's own conditions (I6) }
procedure TRoutineWalk.HostConds;
begin
  var Own:= TList<TTraceItem>.Create;
  try
    for var I in FItems do
      if (I.Owner = FId) and (I.Kind <> KIND_STOPS) and not I.Omits then
        Own.Add(I);
    for var C in FConds do
    begin
      var H: TTraceItem:= nil;
      if C.HasHostLines then
      begin
        for var I in Own do
          if TArray.Contains<Integer>(C.HostLines, I.Line) then
          begin
            H:= I;
            Break;
          end;
      end
      else if C.HasHostFrom then
        for var I in Own do
          if (I.Line > C.HostFrom) and (I.Line < C.HostTo) then
          begin
            H:= I;
            Break;
          end;
      if (H = nil) and C.IsStrict then
        Continue;
      if H = nil then
        for var I in Own do
          if I.Line = C.IfLine then
          begin
            H:= I;
            Break;
          end;
      if H = nil then
        for var I in Own do
          if (I.Kind = KIND_STEP) and (I.Line < C.IfLine) then
            H:= I;
      C.Placed:= True;
      if H = nil then
      begin
        FPend.Add(C.Item);
        Continue;
      end;
      var OnCall:= (H.CalleeId <> 0) and (H.CalleeId <> FId);
      if OnCall then
        C.Item.Routine:= FRoutine.Short;
      if OnCall and C.HasHostLines then
      begin
        H.Children.Insert(H.CallerConds, C.Item);
        H.CallerConds:= H.CallerConds + 1;
      end
      else
        H.Children.Add(C.Item);
    end;
  finally
    Own.Free;
  end;
end;

{ ---- the walker ------------------------------------------------------------------------------ }

constructor TTraceWalker.Create(pNear, pFar: TChartsIndex; pNearReader, pFarReader: TSourceReader; pCatalog: TSqlCatalog;
  pSet: TSqlTableSet);
begin
  inherited Create;
  FNear:= pNear;
  FFar:= pFar;
  FNearReader:= pNearReader;
  FFarReader:= pFarReader;
  FCatalog:= pCatalog;
  FSet:= pSet;
  FResolver:= TTraceAnchorResolver.Create(pNear, pNearReader, nil, pCatalog, pSet);
  FFacts:= TObjectDictionary<string, TRoutineFacts>.Create([doOwnsValues], TIStringComparer.Ordinal);
  FImpls:= TObjectDictionary<string, TObjectList<TIndexRow>>.Create([doOwnsValues], TIStringComparer.Ordinal);
  FSources:= TDictionary<string, TTraceSource>.Create(TIStringComparer.Ordinal);
  FOmits:= TDictionary<TTraceItem, TArray<TOmitRec>>.Create;
end;

destructor TTraceWalker.Destroy;
begin
  FOmits.Free;
  FSources.Free;
  FImpls.Free;
  FFacts.Free;
  FResolver.Free;
  inherited Destroy;
end;

function TTraceWalker.IndexOf(pSide: TTraceSide): TChartsIndex;
begin
  Result:= if pSide = tsClient then FNear else FFar;
end;

function TTraceWalker.ReaderOf(pSide: TTraceSide): TSourceReader;
begin
  Result:= if pSide = tsClient then FNearReader else FFarReader;
end;

function TTraceWalker.RoutineFacts(pSide: TTraceSide; pId: Integer; const pLikes: string): TRoutineFacts;
begin
  var Key:= SIDE_KEY[pSide] + '|' + IntToStr(pId);
  if FFacts.TryGetValue(Key, Result) then
    Exit;
  var Ix:= IndexOf(pSide);
  var S:= Ix.Query(Format(SQL_FACTS, [pId]));
  try
    if S.Count = 0 then
      raise EChartsTrace.CreateFmt('Get-RoutineFacts: symbol %d is not in the %s index', [pId, SIDE_KEY[pSide]]);
    Result:= TRoutineFacts.Create;
    try
      var R:= S[0];
      Result.Id:= pId;
      Result.Name:= R.S('name');
      Result.QName:= R.S('q');
      Result.Short:= ShortName(R.S('q'), UnitNameOf(R.S('path')));
      Result.Path:= R.S('path');
      Result.Fid:= R.I('fid');
      Result.Pid:= R.I('pid');
      Result.ImplStart:= R.I('istart');
      Result.ImplEnd:= R.I('iend');
      Result.Decl:= R.I('decl');
      Result.SqlReads:= R.S('sqlr');
      Result.SqlWrites:= R.S('sqlw');
      if Result.ImplStart > 0 then
      begin
        Result.Refs.Free;
        Result.Refs:= nil;
        Result.Refs:= Ix.AllRows(Format(SQL_FACT_REFS, [pLikes, Result.Fid, Result.ImplStart, Result.ImplEnd, pId]),
          'r.start_line, r.start_col, r.id');
        Result.Lits.Free;
        Result.Lits:= nil;
        Result.Lits:= Ix.AllRows(Format(SQL_FACT_LITS, [Result.Fid, Result.ImplStart, Result.ImplEnd, pId]),
          'sl.start_line, sl.start_col, sl.id');
      end;
    except
      on E: Exception do
      begin
        Result.Free;
        raise;
      end;
    end;
  finally
    S.Free;
  end;
  FFacts.Add(Key, Result);
end;

function TTraceWalker.TraceSource(pSide: TTraceSide; const pPath: string): TTraceSource;
begin
  var Key:= SIDE_KEY[pSide] + '|' + pPath;
  if FSources.TryGetValue(Key, Result) then
    Exit;
  var Rd:= ReaderOf(pSide);
  if not Rd.SourceFresh(pPath) then
    raise EChartsTrace.Create('round-trip: ' + FileNameOf(pPath) +
      ' differs from the indexed copy (sha256) -- refusing to read it. Reindex the project, then re-run.');
  var Read:= Rd.ReadPath(pPath);
  Result.Stripped:= Rd.StrippedSourceLines(Read);
  Result.Raw:= SplitLines(ReadLatin1(Read));
  FSources.Add(Key, Result);
end;

function TTraceWalker.GuardCondition(pSide: TTraceSide; const pPath: string; pExitLine, pRoutineStart: Integer): TShimResult;
begin
  if not ReaderOf(pSide).SourceFresh(pPath) then
    raise EChartsTrace.Create('round-trip: ' + FileNameOf(pPath) +
      ' differs from the indexed copy (sha256) -- refusing to quote a condition from it. Reindex the project, then re-run.');
  var S:= TraceSource(pSide, pPath);
  Result:= GuardConditionFromLines(S.Raw, S.Stripped, pExitLine, pRoutineStart);
end;

function TTraceWalker.OutwardIoCallee(pSide: TTraceSide; pId: Integer; pCtx: TTraceContext): Boolean;
begin
  var F:= RoutineFacts(pSide, pId, pCtx.Likes);
  for var R in F.Refs do
    if IsCall(R) and (R.I('tid') = 0) and InNames(R.S('nm'), RT_OUTWARD_IO_CALLS) and ((R.S('recv') = '') or
      SameText(R.S('recv'), 'Winapi.Windows')) then
      Exit(True);
  Result:= False;
end;

{ Format-TraceLiteral: the token as written, or `(a literal at :N)` when a text cannot carry it (T5-R5) }
function TTraceWalker.FormatTraceLiteral(pSide: TTraceSide; pLit: TIndexRow; const pPath: string; pFid: Integer): string;
begin
  var Ln:= pLit.I('line');
  var RawLine:= '';
  var HasRaw:= False;
  if pFid <> 0 then
  begin
    var Raw:= TraceSource(pSide, pPath).Raw;
    if (Ln >= 1) and (Ln <= Length(Raw)) then
    begin
      RawLine:= Raw[Ln - 1];
      HasRaw:= True;
    end;
  end;
  var Lt:= LiteralSourceText(pLit.S('text'), pLit.I('col'), pLit.I('ecol'), RawLine, HasRaw);
  Result:= if TRegEx.IsMatch(Lt, RE_TRACE_UNSAFE) then Format('(a literal at :%d)', [Ln]) else Lt;
end;

function TTraceWalker.LineLits(pSide: TTraceSide; const pLits: TArray<TIndexRow>; const pPath: string; pFid: Integer): string;
begin
  var L:= TList<string>.Create;
  try
    for var R in pLits do
      if IsKind(R, 'literal') then
        L.Add(FormatTraceLiteral(pSide, R, pPath, pFid));
    Result:= if L.Count > 0 then ' ' + string.Join(' ', L.ToArray) else '';
  finally
    L.Free;
  end;
end;

{ Resolve-ImplByName: the receiver's declared type in the NEAREST scope that declares it, then the one method of that name }
function TTraceWalker.ResolveImplByName(pSide: TTraceSide; const pRecv, pName: string; pF: TRoutineFacts): TObjectList<TIndexRow>;
begin
  var Segs:= TRegEx.Replace(pRecv, RE_SELF, '', [roIgnoreCase]).Split(['.']);
  if Length(Segs) = 0 then
    Segs:= [''];
  var Root:= Segs[High(Segs)];
  var Key:= Format('%s|%d|%s|%s', [SIDE_KEY[pSide], pF.Id, UpperCase(pRecv), pName]);
  if FImpls.TryGetValue(Key, Result) then
    Exit;
  var Scopes: TArray<string>;
  if Length(Segs) = 1 then
    Scopes:= [Format('s.parent_id = %d AND s.kind IN (''local_var'',''param'')', [pF.Id]),
      Format('s.parent_id = %d AND s.kind IN (''field'',''property'')', [pF.Pid]), 's.kind = ''var''']
  else
    Scopes:= ['s.kind IN (''var'',''field'',''property'',''param'',''local_var'')'];
  var Ix:= IndexOf(pSide);
  var T: TObjectList<TIndexRow>:= nil;
  try
    for var Sc in Scopes do
    begin
      T.Free;
      T:= Ix.Query(Format(SQL_SCOPE_TYPES, [TChartsIndex.SqlText(Root), Sc]));
      if T.Count > 0 then
        Break;
    end;
    var Types:= TList<string>.Create;
    var Kinds:= TList<string>.Create;
    try
      for var R in T do
        if R.S('sig') <> '' then
        begin
          var Ty:= TRegEx.Replace(R.S('sig'), RE_TPL_TAIL, '').Trim;
          if Ty <> '' then
            Types.Add(Ty);
          Kinds.Add(R.S('k'));
        end;
      if Kinds.Count = 0 then
        Result:= TObjectList<TIndexRow>.Create
      else
      begin
        var Up: TArray<string>:= SortUniqueNames(Types.ToArray);
        for var K:= 0 to High(Up) do
          Up[K]:= UpperCase(Up[K]);
        Result:= Ix.Query(Format(SQL_IMPL_BY_NAME, [string.Join(',', SortUniqueNames(Kinds.ToArray)), TChartsIndex.SqlText(pName),
          TChartsIndex.SqlInList(Up)]));
      end;
    finally
      Kinds.Free;
      Types.Free;
    end;
  finally
    T.Free;
  end;
  FImpls.Add(Key, Result);
end;

{ Resolve-HandlerByName: the handler a wiring line names, bound (certain) or a method of the same class by name (E3) }
function TTraceWalker.ResolveHandlerByName(pSide: TTraceSide; pRef: TIndexRow; pF: TRoutineFacts): TCallTarget;
begin
  Result:= Default(TCallTarget);
  if (pRef.I('tid') <> 0) and (pRef.I('tistart') > 0) then
  begin
    Result.Found:= True;
    Result.Id:= pRef.I('tid');
    Result.Short:= ShortName(pRef.S('tq'), UnitNameOf(pRef.S('tpath')));
    Result.Path:= pRef.S('tpath');
    Result.Line:= pRef.I('tistart');
    Exit;
  end;
  var H:= IndexOf(pSide).Query(Format(SQL_HANDLER_BY_NAME, [pF.Pid, TChartsIndex.SqlText(pRef.S('nm'))]));
  try
    if H.Count <> 1 then
      Exit;
    Result.Found:= True;
    Result.Id:= H[0].I('id');
    Result.Short:= ShortName(H[0].S('q'), UnitNameOf(H[0].S('path')));
    Result.Path:= H[0].S('path');
    Result.Line:= H[0].I('istart');
    Result.Grade:= GRADE_BY_NAME;
    Result.Ask:= ASK_E3;
  finally
    H.Free;
  end;
end;

function TTraceWalker.FibLiterals(pSide: TTraceSide; pFid: Integer): TObjectList<TIndexRow>;
begin
  Result:= IndexOf(pSide).AllRows(Format(SQL_FIB_LITS, [pFid]), 'sl.start_line, sl.id');
  for var K:= Result.Count - 1 downto 0 do
    if not TRegEx.IsMatch(Result[K].S('text'), RT_FIB_SQL_RX) then
      Result.Delete(K);
end;

{ Get-ElseNote: what the other branch does -- dataset ops, protocol constants, the literal that goes out with it }
function TTraceWalker.ElseNote(pSide: TTraceSide; pF: TRoutineFacts; const pG: TElseScope): string;
begin
  var G:= pG;
  var InBr: TFunc<TIndexRow, Boolean>:= function(pO: TIndexRow): Boolean
    begin
      var L:= pO.I('line');
      Result:= (L >= G.BlockStart) and (L <= G.BlockEnd) and ((L <> G.SpanLine) or ((pO.I('col') - 1 >= G.SpanFrom) and
        (pO.I('col') - 1 < G.SpanTo)));
    end;
  var InRefs:= Filter(pF.Refs.ToArray, InBr);
  var Parts:= TList<string>.Create;
  var OutLn:= TDictionary<Integer, Byte>.Create;
  try
    for var O in InRefs do
      if IsCall(O) and IsOp(O.S('nm')) then
        Parts.Add((if O.S('recv') <> '' then O.S('recv') + '.' else '') + O.S('nm') + ' @' + TraceAnchorText(pF.Path, O.I('line')));
    var En:= TList<string>.Create;
    try
      for var O in InRefs do
        if IsEnum(O) and (StartsText('rsp', O.S('tname')) or StartsText('cmd', O.S('tname'))) then
          En.Add(O.S('tname'));
      if En.Count > 0 then
        Parts.Add(string.Join('/', SortUniqueNames(En.ToArray)));
    finally
      En.Free;
    end;
    for var R in InRefs do
    begin
      if IsKind(R, 'write') and SameText(R.S('tkind'), 'param') then
        OutLn.AddOrSetValue(R.I('line'), 1);
      if IsEnum(R) and StartsText('rsp', R.S('tname')) then
        for var O in InRefs do
          if (O.I('line') = R.I('line')) and IsKind(O, 'write') then
          begin
            OutLn.AddOrSetValue(R.I('line'), 1);
            Break;
          end;
    end;
    var Src:= TraceSource(pSide, pF.Path);
    var St:= Src.Stripped;
    var Q:= G.BlockStart;
    while (Q <= G.BlockEnd) and (Q <= Length(St)) do
    begin
      var Ln:= St[Q - 1];
      if Q = G.SpanLine then
      begin
        var A:= Min(G.SpanFrom, Length(Ln));
        Ln:= Ln.Substring(A, Max(0, Min(G.SpanTo, Length(Ln)) - A));
      end;
      if TRegEx.IsMatch(Ln, RE_RAISE, [roIgnoreCase]) then
        OutLn.AddOrSetValue(Q, 1);
      Inc(Q);
    end;
    for var L in pF.Lits do
      if InBr(L) and OutLn.ContainsKey(L.I('line')) and (IsKind(L, 'literal') or IsKind(L, 'format')) and
        (L.S('text').Trim.Length > ELSE_LIT_MIN) then
      begin
        var Ln:= L.I('line');
        var HasRaw:= (Ln >= 1) and (Ln <= Length(Src.Raw));
        var Lt:= LiteralSourceText(L.S('text'), L.I('col'), L.I('ecol'), if HasRaw then Src.Raw[Ln - 1] else '', HasRaw);
        Parts.Add(if TRegEx.IsMatch(Lt, RE_NOTE_UNSAFE) then Format('a literal at :%d', [Ln]) else Lt);
        Break;
      end;
    if G.ExitArg <> '' then
      Parts.Add('Exit(' + G.ExitArg + ')');
    if SameText(G.Form, 'case') then
      Exit(Format('else arm at :%d', [G.BlockStart]) + (if Parts.Count > 0 then ': ' + string.Join(', ', Parts.ToArray) else ''));
    Result:= if Parts.Count > 0 then 'else ' + string.Join(', ', Parts.ToArray) else '';
  finally
    OutLn.Free;
    Parts.Free;
  end;
end;

{ Get-PayloadLits: the routine's literals before the send that name the anchor table, else its key=value literals }
function PayloadLits(pF: TRoutineFacts; pLine: Integer; const pTable: string): TArray<TIndexRow>;
begin
  var Before:= Filter(pF.Lits.ToArray, function(L: TIndexRow): Boolean begin Result:= (L.I('line') < pLine) and IsKind(L, 'literal'); end);
  Result:= Filter(Before, function(L: TIndexRow): Boolean
    begin
      Result:= (pTable <> '') and UpperCase(L.S('text')).Contains(UpperCase(pTable));
    end);
  if Length(Result) = 0 then
    Result:= Filter(Before, function(L: TIndexRow): Boolean begin Result:= TRegEx.IsMatch(L.S('text'), RE_PAYLOAD_KV); end);
end;

{ Test-TableSpecificSender: the PAYLOAD literals name the anchor table as a word (M2) }
function TableSpecificSender(pF: TRoutineFacts; pLine: Integer; const pTable: string): Boolean;
begin
  var Rx:= '\b' + TRegEx.Escape(pTable) + '\b';
  for var L in PayloadLits(pF, pLine, pTable) do
    if TRegEx.IsMatch(L.S('text'), Rx, [roIgnoreCase]) then
      Exit(True);
  Result:= False;
end;

function TTraceWalker.PayloadText(pSide: TTraceSide; pF: TRoutineFacts; pLine: Integer; pCtx: TTraceContext): TPayload;
begin
  var Pl:= PayloadLits(pF, pLine, pCtx.Table);
  var Parts: TArray<string>;
  SetLength(Parts, Length(Pl));
  var Lines: TArray<Integer>;
  SetLength(Lines, Length(Pl));
  for var K:= 0 to High(Pl) do
  begin
    Parts[K]:= FormatTraceLiteral(pSide, Pl[K], pF.Path, pF.Fid);
    Lines[K]:= Pl[K].I('line');
  end;
  var T:= string.Join(' + ', Parts);
  Result.Note:= 'payload inferred from the literals before the send';
  var Pls:= SortedUniqueInts(Lines);
  if Length(Pls) = 1 then
  begin
    var Src:= TraceSource(pSide, pF.Path);
    var Ex:= ConcatAssignExpr(Src.Raw[Pls[0] - 1], Src.Stripped[Pls[0] - 1]);
    if (Ex <> '') and not TRegEx.IsMatch(Ex, RE_TRACE_UNSAFE) then
    begin
      T:= Ex;
      Result.Note:= Format('payload quoted from the assignment at :%d', [Pls[0]]);
    end;
  end;
  var Sv: TIndexRow:= nil;
  for var R in pF.Refs do
    if (R.I('line') < pLine) and SameText(R.S('nm'), 'SaveToStream') and IsCall(R) then
      Sv:= R;
  if Sv <> nil then
  begin
    var Fmt:= StreamFormat(TraceSource(pSide, pF.Path).Raw[Sv.I('line') - 1]);
    T:= T + (if T <> '' then ' + ' else '') + (if Fmt <> '' then Fmt + ' stream' else 'stream');
  end;
  Result.Text:= if T <> '' then T else 'payload built before the send (no literal found)';
end;

procedure TTraceWalker.AddCallsStep(pList: TObjectList<TTraceItem>; const pTgt: TCallTarget; pSub: TWalkResult; pCaller: TRoutineFacts;  // dl:ok too-many-parameters@a35b -- REVIEWED 2026-10-18: Add-CallsStep's own eight parameters (Trace.Walk.ps1:1162: List, Tgt, Sub, Caller, SiteLine, Lits, -Always, -Note), kept one to one with the PS
  pSiteLine: Integer; const pLits: string; pAlways: Boolean; const pNote: string);
begin
  try
    if not pAlways and (pSub.Items.Count = 0) and (pSub.Conds.Count = 0) then
      Exit;
    var S:= NewTraceStep(KIND_STEP, 'CALLS ' + pTgt.Short + pLits, TraceAnchorText(pTgt.Path, pTgt.Line), pTgt.Grade, pCaller.Short,
      if pNote <> '' then pNote else Format('from :%d', [pSiteLine]), pTgt.Ask);
    S.CalleeId:= pTgt.Id;
    MoveConds(pSub.Conds, S.Children);
    AddRtItem(pList, S, pSiteLine, pCaller.Id);
    MoveItems(pSub.Items, pList);
  finally
    pSub.Free;
  end;
end;

{ Get-LineCandidates: the columns of the refs / literals of one line that could make a step }
function TTraceWalker.LineCandidateCols(pSide: TTraceSide; const pRs, pLits: TArray<TIndexRow>; pF: TRoutineFacts): TArray<Integer>;
begin
  var L:= TList<Integer>.Create;
  try
    for var R in pRs do
    begin
      if IsCall(R) and IsOp(R.S('nm')) then
        L.Add(R.I('col'))
      else if IsBoundCall(R) then
        L.Add(R.I('col'))
      else if IsCall(R) and (R.I('tid') = 0) and (R.S('recv') <> '') and (ResolveImplByName(pSide, R.S('recv'), R.S('nm'), pF).Count = 1) then
        L.Add(R.I('col'))
      else if IsEnum(R) and (StartsText('cmd', R.S('tname')) or StartsText('rsp', R.S('tname'))) then
        L.Add(R.I('col'));
    end;
    for var Li in pLits do
      if TRegEx.IsMatch(Li.S('text'), RT_FIB_SQL_RX) then
        L.Add(0);
    Result:= L.ToArray;
  finally
    L.Free;
  end;
end;

{ Get-LineYield: how many STEPS one line would have yielded (T5-R6), the subtrees from a DRY walk over copies of
  Visited and Seen }
function TTraceWalker.DryYield(pSide: TTraceSide; pId, pDepth: Integer; pVisited: TDictionary<Integer, Byte>; pDry: TTraceContext;
  out pAny: Boolean): Integer;
begin
  var V:= TDictionary<Integer, Byte>.Create(pVisited);
  try
    var Sub:= WalkRoutine(pSide, pId, pDepth, V, pDry);
    try
      pAny:= (Sub.Items.Count > 0) or (Sub.Conds.Count > 0);
      Result:= Sub.Items.Count;
    finally
      Sub.Free;
    end;
  finally
    V.Free;
  end;
end;

function TTraceWalker.LineYield(pSide: TTraceSide; pI: TLineInfo; pF: TRoutineFacts; pDepth: Integer; pVisited: TDictionary<Integer, Byte>;
  pCtx: TTraceContext): Integer;
begin
  var Rs:= pI.Rs;
  var HasCmd:= False;
  var HasRsp:= False;
  var HasTrans:= False;
  for var R in Rs do
  begin
    if IsEnum(R) and StartsText('cmd', R.S('tname')) then
      HasCmd:= True;
    if IsEnum(R) and StartsText('rsp', R.S('tname')) then
      HasRsp:= True;
    if IsCall(R) and IsPipe(R) then
      HasTrans:= True;
  end;
  if HasCmd and HasTrans then
    Exit(1);
  if HasRsp then
    Exit(1);
  var Ops:= Length(Filter(Rs, function(R: TIndexRow): Boolean begin Result:= IsCall(R) and IsOp(R.S('nm')); end));
  if Ops > 0 then
    Exit(Ops);
  Result:= Length(Filter(pI.Lits, function(L: TIndexRow): Boolean begin Result:= TRegEx.IsMatch(L.S('text'), RT_FIB_SQL_RX); end));
  var Dry:= pCtx.Clone(True);
  try
    var Any: Boolean;
    var Ev:= Filter(Rs, IsEventRef);
    var H: TArray<TIndexRow>:= nil;
    if Length(Ev) > 0 then
      H:= HandlerRefs(Rs, Ev[0]);
    var Hs:= Default(TCallTarget);
    if Length(H) > 0 then
      Hs:= ResolveHandlerByName(pSide, H[High(H)], pF);
    if Hs.Found then
    begin
      var N:= DryYield(pSide, Hs.Id, pDepth - 1, pVisited, Dry, Any);
      Inc(Result, 1 + (if Any then 1 + N else 0));
      Exit;
    end;
    for var C in Filter(Rs, IsBoundCall) do
      if not IsPipe(C) then
      begin
        var N:= DryYield(pSide, C.I('tid'), pDepth - 1, pVisited, Dry, Any);
        if Any then
          Inc(Result, 1 + N);
      end;
    for var C in Filter(Rs, IsBoundCall) do
      if IsPipe(C) and OutwardIoCallee(pSide, C.I('tid'), pCtx) then
        Inc(Result);
    for var C in Filter(Rs, function(R: TIndexRow): Boolean begin Result:= IsCall(R) and (R.I('tid') = 0) and (R.S('recv') <> ''); end) do
    begin
      var Impl:= ResolveImplByName(pSide, C.S('recv'), C.S('nm'), pF);
      if Impl.Count <> 1 then
        Continue;
      Inc(Result, 1 + DryYield(pSide, Impl[0].I('id'), pDepth - 1, pVisited, Dry, Any));
      var Fl:= FibLiterals(pSide, Impl[0].I('fid'));
      try
        for var L in Fl do
          if not Dry.Seen.ContainsKey(Impl[0].S('path') + '|' + IntToStr(L.I('line'))) then
            Inc(Result);
      finally
        Fl.Free;
      end;
    end;
  finally
    Dry.Free;
  end;
end;
{ New-OmitStep: the OMITS disclosure (T5-R1) }
function TTraceWalker.NewOmitStep(const pRecs: TArray<TOmitRec>): TTraceItem;
begin
  var N:= 0;
  var Rn: TArray<string>;
  SetLength(Rn, Length(pRecs));
  for var K:= 0 to High(pRecs) do
  begin
    Inc(N, pRecs[K].Count);
    Rn[K]:= pRecs[K].Routine;
  end;
  Rn:= SortUniqueNames(Rn);
  var Seen:= TDictionary<string, Byte>.Create(TIStringComparer.Ordinal);
  var Cs:= TList<string>.Create;
  try
    for var R in pRecs do
    begin
      var K:= R.Keyword + '|' + R.Condition + '|' + R.Anchor;
      if Seen.ContainsKey(K) then
        Continue;
      Seen.Add(K, 1);
      Cs.Add(if TRegEx.IsMatch(R.Condition, RE_OMIT_UNSAFE) or (TraceCondProblem(R.Condition) <> '') then R.Keyword + ' at ' + R.Anchor
        else R.Keyword + ' ' + R.Condition + ' @' + R.Anchor);
    end;
    Result:= NewTraceStep(KIND_STEP, Format('OMITS %d step(s) in branches for other tables, every enclosing if read up to a loop or case arm',
      [N]), pRecs[0].Anchor, '', if Length(Rn) = 1 then Rn[0] else '', 'not walked, the branch conditions: ' + string.Join(' / ', Cs.ToArray),
      ASK_E1);
  finally
    Cs.Free;
    Seen.Free;
  end;
  Result.Omits:= True;
  FOmits.AddOrSetValue(Result, pRecs);
end;

function TTraceWalker.WalkRoutine(pSide: TTraceSide; pId, pDepth: Integer; pVisited: TDictionary<Integer, Byte>;
  pCtx: TTraceContext): TWalkResult;
begin
  Result:= TWalkResult.Create;
  try
    if pVisited.ContainsKey(pId) or (pDepth < 0) then
      Exit;
    pVisited.AddOrSetValue(pId, 1);
    var F:= RoutineFacts(pSide, pId, pCtx.Likes);
    if F.ImplStart <= 0 then
      Exit;
    var Rw:= TRoutineWalk.Create(Self, pSide, pId, pDepth, pVisited, pCtx, Result);
    try
      Rw.Run;
    finally
      Rw.Free;
    end;
  except
    on E: Exception do
    begin
      Result.Free;
      raise;
    end;
  end;
end;

{ ---- Part 4: the server side, on the SERVER index ----------------------------------------- }

type
  { the Find-DispatchArm object }
  TDispatchArm = record
    Found   : Boolean;
    Line    : Integer;
    Routine : string;
    Path    : string;
    CallLine: Integer;
    TId     : Integer;
    TQ      : string;
    TIStart : Integer;
    TDecl   : Integer;
    TPath   : string;
    TName   : string;
  end;

function FindDispatchArm(pIx: TChartsIndex; const pCmdName, pLikes: string): TDispatchArm;
begin
  Result:= Default(TDispatchArm);
  var Reads:= pIx.Query(Format(SQL_DISPATCH_READS, [TChartsIndex.SqlText(pCmdName), pLikes]));
  try
    for var Rd in Reads do
    begin
      var Hi:= Rd.I('iend');
      var Nx:= pIx.Query(Format(SQL_DISPATCH_NEXT, [Rd.I('eid'), Rd.I('line')]));
      try
        if (Nx.Count > 0) and (Nx[0].I('l') <> 0) then
          Hi:= Nx[0].I('l');
      finally
        Nx.Free;
      end;
      var C:= pIx.Query(Format(SQL_DISPATCH_CALL, [Rd.I('eid'), Rd.I('line'), Hi, Rd.I('fid')]));
      try
        if C.Count = 0 then
          Continue;
        Result.Found:= True;
        Result.Line:= Rd.I('line');
        Result.Routine:= LastSegment(Rd.S('routine'));
        Result.Path:= Rd.S('path');
        Result.CallLine:= C[0].I('line');
        Result.TId:= C[0].I('id');
        Result.TQ:= C[0].S('q');
        Result.TIStart:= C[0].I('istart');
        Result.TDecl:= C[0].I('decl');
        Result.TPath:= C[0].S('path');
        Result.TName:= C[0].S('name');
        Exit;
      finally
        C.Free;
      end;
    end;
  finally
    Reads.Free;
  end;
end;

function TTraceWalker.ServerHandling(const pCmdName: string; pCtx: TTraceContext; pDepth: Integer): TServerHandling;
begin
  Result:= TServerHandling.Create;
  try
    var Arm:= FindDispatchArm(FFar, pCmdName, pCtx.Likes);
    if not Arm.Found then
    begin
      var At:= 'unknown:0';
      var Decl:= FFar.Query(Format(SQL_ENUM_DECL, [TChartsIndex.SqlText(pCmdName)]));
      try
        if Decl.Count > 0 then
          At:= TraceAnchorText(Decl[0].S('p'), Decl[0].I('l'));
      finally
        Decl.Free;
      end;
      Result.Stop:= NewTraceStep(KIND_STOPS, TraceStopText(Format('no transport routine of %s reads %s and then calls a handler ' +
        'declared in another unit', [pCtx.FarIndex, pCmdName])), At, '', '', '', ASK_E2);
      AddRtItem(Result.Items, Result.Stop, 0, 0);
      Exit;
    end;
    AddRtItem(Result.Items, NewTraceStep(KIND_STEP, Format('ROUTES %s TO %s', [pCmdName, ShortName(Arm.TQ, UnitNameOf(Arm.TPath))]),
      TraceAnchorText(Arm.Path, Arm.Line), '', Arm.Routine, Format('the first cross-unit call after the constant, at :%d', [Arm.CallLine]),
      ASK_E2), Arm.Line, 0);
    Result.HasContract:= True;
    Result.ContractText:= Arm.TQ;
    Result.ContractAnchor:= TraceAnchorText(Arm.TPath, Arm.TDecl);
    var Impl:= Default(TCallTarget);
    if Arm.TIStart > 0 then
    begin
      Impl.Id:= Arm.TId;
      Impl.Short:= ShortName(Arm.TQ, UnitNameOf(Arm.TPath));
      Impl.Path:= Arm.TPath;
      Impl.Line:= Arm.TIStart;
    end
    else
    begin
      var Segs:= Arm.TQ.Split(['.']);
      var Iface:= if Length(Segs) >= 2 then Segs[High(Segs) - 1] else '';
      var Im:= FFar.Query(Format(SQL_IFACE_IMPL, [TChartsIndex.SqlText(Arm.TName), TChartsIndex.SqlText(Iface)]));
      try
        if Im.Count <> 1 then
        begin
          Result.Stop:= NewTraceStep(KIND_STOPS, TraceStopText(Format('%s has %d implementations in classes whose heritage names its ' +
            'interface', [Arm.TQ, Im.Count])), TraceAnchorText(Arm.TPath, Arm.TDecl), '', Arm.Routine, '', ASK_E2);
          AddRtItem(Result.Items, Result.Stop, Arm.CallLine, 0);
          Exit;
        end;
        Impl.Id:= Im[0].I('id');
        Impl.Short:= ShortName(Im[0].S('q'), UnitNameOf(Im[0].S('path')));
        Impl.Path:= Im[0].S('path');
        Impl.Line:= Im[0].I('istart');
        Impl.Grade:= GRADE_BY_NAME;
      finally
        Im.Free;
      end;
    end;
    var Visited:= TDictionary<Integer, Byte>.Create;
    try
      var Sub:= WalkRoutine(tsServer, Impl.Id, pDepth, Visited, pCtx);
      try
        Result.Walked:= True;
        var Note:= Format('from :%d', [Arm.CallLine]) + (if Impl.Grade <> '' then ', the interface method resolved to its one implementation'
          else '');
        var S:= NewTraceStep(KIND_STEP, 'CALLS ' + Impl.Short, TraceAnchorText(Impl.Path, Impl.Line), Impl.Grade, Arm.Routine, Note,
          if Impl.Grade <> '' then ASK_E2 else '');
        MoveConds(Sub.Conds, S.Children);
        AddRtItem(Result.Items, S, Arm.CallLine, 0);
        MoveItems(Sub.Items, Result.Items);
      finally
        Sub.Free;
      end;
      var Rsp:= TList<string>.Create;
      try
        for var VId in Visited.Keys do
        begin
          var F: TRoutineFacts;
          if not FFacts.TryGetValue(SIDE_KEY[tsServer] + '|' + IntToStr(VId), F) then
            Continue;
          for var R in F.Refs do
            if IsEnum(R) and StartsText('rsp', R.S('tname')) then
              Rsp.Add(R.S('tname'));
        end;
        Result.Responses:= SortUniqueNames(Rsp.ToArray);
      finally
        Rsp.Free;
      end;
    finally
      Visited.Free;
    end;
  except
    on E: Exception do
    begin
      Result.Free;
      raise;
    end;
  end;
end;

{ Get-WalkedCaseSelector: the `case <X> of` condition the walk already quoted in routine pF above pLine }
function TTraceWalker.WalkedCaseSelector(const pItems: TArray<TTraceItem>; pF: TRoutineFacts; pLine: Integer; out pSelector: string;
  out pSelLine: Integer): Boolean;
begin
  pSelector:= '';
  pSelLine:= 0;
  var Leaf:= FileNameOf(pF.Path);
  for var I in pItems do
    for var Ch in I.Children do
    begin
      if (Ch.Kind <> 'cond') or not TRegEx.IsMatch(Ch.Condition, RE_CASE_SELECTOR) then
        Continue;
      var X:= TRegEx.Match(Ch.Condition, RE_CASE_SELECTOR).Groups[1].Value;
      var Fl: string;
      var L: Integer;
      SplitAnchor(Ch.Anchor, Fl, L);
      if not SameText(Fl, Leaf) or (L < pF.ImplStart) or (L >= pLine) then
        Continue;
      if TRegEx.IsMatch(X, RE_SELECTOR_UNSAFE) then
        Exit(False);
      pSelector:= X;
      pSelLine:= L;
      Exit(True);
    end;
  Result:= False;
end;

function TTraceWalker.CountRows(pSide: TTraceSide; const pTable: string): Integer;
begin
  var Q:= IndexOf(pSide).Query(Format(SQL_COUNT, [pTable]));
  try
    Result:= Q[0].I('n');
  finally
    Q.Free;
  end;
end;

type
  { a statement-member ref of a walked routine (the PS $naming entries) }
  TNaming = record
    F  : TRoutineFacts;
    Ref: TIndexRow;
  end;

  { one write-statement member with its own load line (FW-R1) }
  TWriteMember = record
    Text     : string;
    HasLoader: Boolean;
    Loader   : TNaming;
  end;

function OwnersOf(const pItems: TArray<TTraceItem>): TArray<Integer>;
begin
  var L:= TList<Integer>.Create;
  try
    for var I in pItems do
      if (I.Owner > 0) and not L.Contains(I.Owner) then
        L.Add(I.Owner);
    Result:= L.ToArray;
  finally
    L.Free;
  end;
end;

function StepsMatching(const pItems: TArray<TTraceItem>; const pRx: string): TArray<TTraceItem>;
begin
  var L:= TList<TTraceItem>.Create;
  try
    for var I in pItems do
      if (I.Kind = KIND_STEP) and TRegEx.IsMatch(I.Text, pRx, [roIgnoreCase]) then
        L.Add(I);
    Result:= L.ToArray;
  finally
    L.Free;
  end;
end;

{ the walk's FIB$DATASETS_INFO read inside a routine of pNaming, naming pName when it is not '' (the first by ref line when pSorted) }
function FindLoader(const pServerItems: TArray<TTraceItem>; const pNaming: TArray<TNaming>; const pName: string; pSorted: Boolean;
  out pHit: TNaming): Boolean;
begin
  pHit:= Default(TNaming);
  for var Fs in StepsMatching(pServerItems, RE_FIB_DATASETS) do
  begin
    var FsFile: string;
    var FsLine: Integer;
    SplitAnchor(Fs.Anchor, FsFile, FsLine);
    var Found:= False;
    for var N in pNaming do
      if ((pName = '') or SameText(N.Ref.S('nm'), pName)) and SameText(FileNameOf(N.F.Path), FsFile) and (FsLine >= N.F.ImplStart) and
        (FsLine <= N.F.ImplEnd) then
        if not Found or (pSorted and (N.Ref.I('line') < pHit.Ref.I('line'))) then
        begin
          pHit:= N;
          Found:= True;
          if not pSorted then
            Break;
        end;
    if Found then
      Exit(True);
  end;
  Result:= False;
end;

{ the write direction's statement STOPS (final-review M7, FW-R1, P15) }
function TTraceWalker.WriteStatementStop(const pServerItems: TArray<TTraceItem>; pCtx: TTraceContext): TTraceItem;
const
  STMT = 'UpdateSQL';
begin
  var Owners:= OwnersOf(pServerItems);
  var NL:= TList<TNaming>.Create;
  var WL:= TList<TNaming>.Create;
  try
    for var Own in Owners do
    begin
      var Fo: TRoutineFacts;
      if not FFacts.TryGetValue(SIDE_KEY[tsServer] + '|' + IntToStr(Own), Fo) then
        Continue;
      for var M in Fo.Refs do
        if IsKind(M, 'member-access') then
        begin
          var N: TNaming;
          N.F:= Fo;
          N.Ref:= M;
          if SameText(M.S('nm'), STMT) then
            NL.Add(N);
          if InNames(M.S('nm'), RT_WRITE_STMTS) then
            WL.Add(N);
        end;
    end;
    var Naming:= NL.ToArray;
    var WmNaming:= WL.ToArray;
    var ApplyOwners: TArray<Integer>:= [];
    for var I in StepsMatching(pServerItems, RE_RUNS_EXEC) do
      ApplyOwners:= ApplyOwners + [I.Owner];
    var HasPick:= False;
    var P0: TNaming;
    for var N in Naming do
      if TArray.Contains<Integer>(ApplyOwners, N.F.Id) then
      begin
        P0:= N;
        HasPick:= True;
        Break;
      end;
    if not HasPick and (Length(Naming) > 0) then
    begin
      P0:= Naming[0];
      HasPick:= True;
    end;
    var Loader: TNaming;
    var HasLoader:= FindLoader(pServerItems, Naming, '', False, Loader);
    var Fb:= CountRows(tsServer, FIB_DATASETS);
    var Held:= if Fb = 0 then Format('fb_datasets has 0 rows in %s', [pCtx.FarIndex])
      else Format('fb_datasets has %d rows in %s, which this walk does not look up', [Fb, pCtx.FarIndex]);
    var FromWhat:= 'from FIB$DATASETS_INFO rows' + (if Fb = 0 then ' the index does not hold' else '');
    var Why, At, Rn, Nt: string;
    if HasPick then
    begin
      var SText:= (if P0.Ref.S('recv') <> '' then P0.Ref.S('recv') + '.' else '') + STMT;
      { the write-statement members of the same receiver, by line then column, unique by name (first kept) }
      var WmSorted:= Filter(P0.F.Refs.ToArray, function(R: TIndexRow): Boolean
        begin
          Result:= IsKind(R, 'member-access') and InNames(R.S('nm'), RT_WRITE_STMTS) and (R.S('recv') = P0.Ref.S('recv'));
        end);
      TPsSort<TIndexRow>.Sort(WmSorted, function(const pA, pB: TIndexRow): Integer
        begin
          Result:= CompareValue(pA.I('line'), pB.I('line'));
          if Result = 0 then
            Result:= CompareValue(pA.I('col'), pB.I('col'));
        end);
      var WmSeen:= TDictionary<string, Byte>.Create(TIStringComparer.Ordinal);
      var Wm:= TList<TWriteMember>.Create;
      try
        for var R in WmSorted do
        begin
          if WmSeen.ContainsKey(R.S('nm')) then
            Continue;
          WmSeen.Add(R.S('nm'), 1);
          var X: TWriteMember;
          X.Text:= (if R.S('recv') <> '' then R.S('recv') + '.' else '') + R.S('nm');
          X.HasLoader:= FindLoader(pServerItems, WmNaming, R.S('nm'), True, X.Loader);
          Wm.Add(X);
        end;
        var Sel: string;
        var SelLine: Integer;
        var HasSel:= WalkedCaseSelector(pServerItems, P0.F, P0.Ref.I('line'), Sel, SelLine);
        var AllLoaded:= Wm.Count > 0;
        for var X in Wm do
          AllLoaded:= AllLoaded and X.HasLoader;
        var Names: TArray<string>;
        SetLength(Names, Wm.Count);
        for var K:= 0 to Wm.Count - 1 do
          Names[K]:= if (Wm.Count > 1) and AllLoaded then Format('%s (loaded at %s)', [Wm[K].Text, TraceAnchorText(Wm[K].Loader.F.Path,
            Wm[K].Loader.Ref.I('line'))]) else Wm[K].Text;
        var Alts:= if Length(Names) > 1 then JoinLast(Names, ' or ') else SText;
        var How:= if (Wm.Count > 1) and HasSel then Format(', picked by the case over %s at :%d', [Sel, SelLine]) else '';
        var LoadClause: string;
        if (Length(Names) > 1) and AllLoaded then
          LoadClause:= ', ' + FromWhat
        else if HasLoader then
          LoadClause:= Format(', loaded at %s %s', [TraceAnchorText(Loader.F.Path, Loader.Ref.I('line')), FromWhat])
        else
        begin
          LoadClause:= ', whose text the walk does not read';
          for var X in Wm do
            if X.HasLoader then
            begin
              LoadClause:= Format(', loaded in %s (%s-%d), %s', [X.Loader.F.Short, TraceAnchorText(X.Loader.F.Path, X.Loader.F.ImplStart),
                X.Loader.F.ImplEnd, FromWhat]);
              Break;
            end;
        end;
        Why:= Format('the statement for the posted %s row is %s%s%s (%s)', [pCtx.Table, Alts, How, LoadClause, Held]);
      finally
        Wm.Free;
        WmSeen.Free;
      end;
      At:= TraceAnchorText(P0.F.Path, P0.Ref.I('line'));
      Rn:= P0.F.Short;
      Nt:= 'the statement member is named here' + (if TArray.Contains<Integer>(ApplyOwners, P0.F.Id) then
        ', in the routine that executes it' else '');
    end
    else
    begin
      var Last: TTraceItem:= nil;
      var Ra:= StepsMatching(pServerItems, RE_RUNS_APPLIES);
      if Length(Ra) > 0 then
        Last:= Ra[High(Ra)]
      else
        for var I in pServerItems do
          if I.Kind <> KIND_CROSSES then
            Last:= I;
      Why:= Format('no walked routine names the statement for the posted %s row', [pCtx.Table]) + (if Last <> nil then
        Format(', applied in %s at %s', [Last.Routine, Last.Anchor]) else '') + ' (' + Held + ')';
      var Tb:= FSet.Table(pCtx.Table);
      At:= if Last <> nil then Last.Anchor else if Tb <> nil then TraceAnchorText(Tb.Path, Tb.Line) else TraceAnchorText('', 0);
      Rn:= if Last <> nil then Last.Routine else '';
      Nt:= '';
    end;
    Result:= NewTraceStep(KIND_STOPS, TraceStopText(Why), At, '', Rn, Nt, ASK_E4);
  finally
    WL.Free;
    NL.Free;
  end;
end;

{ Get-SelectStop: DATABASE for a READ -- where the SELECT is assembled, with After (M4) }
function TTraceWalker.SelectStop(const pServerItems: TArray<TTraceItem>; pCtx: TTraceContext; out pAfter: TTraceItem): TTraceItem;
begin
  pAfter:= nil;
  var Fib:= StepsMatching(pServerItems, RE_FIB_READ);
  var Loaders:= OwnersOf(Fib);
  var Tabs:= TList<string>.Create;
  var Held:= TList<string>.Create;
  try
    for var I in Fib do
    begin
      var M:= TRegEx.Match(I.Text, RE_FIB_TABLE, [roIgnoreCase]);
      if M.Success and not Tabs.Contains(UpperCase(M.Groups[1].Value)) then
        Tabs.Add(UpperCase(M.Groups[1].Value));
    end;
    var Runs: TArray<TTraceItem>;
    var RL:= TList<TTraceItem>.Create;
    try
      for var I in StepsMatching(pServerItems, RE_RUNS_OPEN) do
        if not TArray.Contains<Integer>(Loaders, I.Owner) then
          RL.Add(I);
      Runs:= RL.ToArray;
    finally
      RL.Free;
    end;
    var Sum:= 0;
    for var T in Tabs do
      for var Sn in RT_FB_SNAPSHOT do
        if SameText(Sn.Table, T) then
        begin
          var N:= CountRows(tsServer, Sn.Snapshot);
          Held.Add(Format('%s has %d rows', [Sn.Snapshot, N]));
          Inc(Sum, N);
        end;
    var HeldTxt:= '';
    if Held.Count > 0 then
      HeldTxt:= Format(', and the FIB$ rows the walk reads (%s) are %s (%s in %s)', [string.Join(', ', Tabs.ToArray),
        if Sum = 0 then 'not in the index' else 'not looked up by this walk', string.Join(', ', Held.ToArray), pCtx.FarIndex]);
    for var Own in OwnersOf(Runs) do
    begin
      var F: TRoutineFacts;
      if not FFacts.TryGetValue(SIDE_KEY[tsServer] + '|' + IntToStr(Own), F) then
        Continue;
      var Sel: TIndexRow:= nil;
      for var L in F.Lits do
        if IsKind(L, 'literal') and TRegEx.IsMatch(L.S('text'), RE_SELECT_LIT, [roIgnoreCase]) then
        begin
          Sel:= L;
          Break;
        end;
      if Sel = nil then
        Continue;
      var Ln:= Sel.I('line');
      var Src:= TraceSource(tsServer, F.Path);
      var W0: TIndexRow:= nil;
      for var R in F.Refs do
        if (R.I('line') = Ln) and IsKind(R, 'write') and (R.S('recv') = '') and (R.I('col') < Sel.I('col')) then
          W0:= R;
      var Parts:= TList<string>.Create;
      try
        if W0 <> nil then
          for var Wr in F.Refs do
          begin
            if not IsKind(Wr, 'write') or (Wr.S('recv') <> '') or not SameText(Wr.S('nm'), W0.S('nm')) then
              Continue;
            var Wl:= Wr.I('line');
            var Ex:= AssignExprAt(Src.Raw[Wl - 1], Src.Stripped[Wl - 1], Wr.I('col'));
            var At:= if Parts.Count > 0 then ':' + IntToStr(Wl) else TraceAnchorText(F.Path, Wl);
            Parts.Add(if (Ex <> '') and not TRegEx.IsMatch(Ex, RE_ASSIGN_UNSAFE) then Format('%s (%s:= %s)', [At, Wr.S('nm'), Ex]) else At);
          end;
        var Where_: string;
        if Parts.Count = 0 then
          Where_:= 'at ' + TraceAnchorText(F.Path, Ln)
        else if Parts.Count = 1 then
          Where_:= Format('in %s at %s', [W0.S('nm'), Parts[0]])
        else
          Where_:= Format('in %s at %s', [W0.S('nm'), JoinLast(Parts.ToArray, ' and ')]);
        var Why:= Format('the SELECT statement for %s is assembled %s, from values the index holds no text for%s', [pCtx.Table, Where_,
          HeldTxt]);
        Result:= NewTraceStep(KIND_STOPS, TraceStopText(Why), TraceAnchorText(F.Path, Ln), '', F.Short,
          'the statement is assembled here, in the routine that runs it', ASK_E4);
      finally
        Parts.Free;
      end;
      for var R in Runs do
        if R.Owner = Own then
        begin
          pAfter:= R;
          Break;
        end;
      Exit;
    end;
    var Last: TTraceItem:= nil;
    if Length(Runs) > 0 then
      Last:= Runs[High(Runs)]
    else
      for var I in pServerItems do
        if I.Kind <> KIND_CROSSES then
          Last:= I;
    var Why:= Format('no walked routine assembles a SELECT for %s from a literal', [pCtx.Table]) + (if Last <> nil then
      Format(', run in %s at %s', [Last.Routine, Last.Anchor]) else '') + HeldTxt;
    var Tb:= FSet.Table(pCtx.Table);
    var At:= if Last <> nil then Last.Anchor else if Tb <> nil then TraceAnchorText(Tb.Path, Tb.Line) else TraceAnchorText('', 0);
    Result:= NewTraceStep(KIND_STOPS, TraceStopText(Why), At, '', if Last <> nil then Last.Routine else '', '', ASK_E4);
    pAfter:= Last;
  finally
    Held.Free;
    Tabs.Free;
  end;
end;

function TTraceWalker.DatabaseSteps(const pServerItems: TArray<TTraceItem>; pCtx: TTraceContext; const pMode: string): TDatabaseSteps;
begin
  Result:= TDatabaseSteps.Create;
  try
    var IsWrite:= SameText(pMode, 'write');
    var Verb:= if IsWrite then 'WRITES' else 'READS';
    var Fact:= StepsMatching(pServerItems, '^' + Verb + ' .*\b' + TRegEx.Escape(pCtx.Table) + '\b');
    var Tb:= FSet.Table(pCtx.Table);
    var TbAnchor:= if Tb <> nil then TraceAnchorText(Tb.Path, Tb.Line) else TraceAnchorText('', 0);
    if (Length(Fact) = 0) and not IsWrite then
      AddRtItem(Result.Items, SelectStop(pServerItems, pCtx, Result.After), 0, 0)
    else if Length(Fact) = 0 then
      AddRtItem(Result.Items, WriteStatementStop(pServerItems, pCtx), 0, 0);
    var Cs:= SqlColumnState(FCatalog, FSet, pCtx.Table, pCtx.Column, TServerSqlHit.None, '');
    if Cs.IsColumn then
      AddRtItem(Result.Items, NewTraceStep(KIND_STEP, Verb + ' ' + pCtx.TableColumn, TraceAnchorText(Cs.Path, Cs.Line), GRADE_INFERRED, '',
        FResolver.ColumnFactNote(Cs, FSet), ASK_E4), 0, 0)
    else
      AddRtItem(Result.Items, NewTraceStep(KIND_STOPS, TraceStopText(pCtx.TableColumn + ': ' + Cs.Caption), TbAnchor, '', '', '', ASK_E4),
        0, 0);
  except
    on E: Exception do
    begin
      Result.Free;
      raise;
    end;
  end;
end;

{ ---- Part 5: READ routes and ALSO, on the CLIENT index ------------------------------------- }

function TTraceWalker.FillRoutes(const pDs: TTraceDataSet; pCtx: TTraceContext; pDepth: Integer): TObjectList<TFillRoute>;
begin
  Result:= TObjectList<TFillRoute>.Create;
  try
    var Rows:= FNear.AllRows(Format(SQL_FILL_ROUTES, [pDs.Fid, TChartsIndex.SqlText(UpperCase(pCtx.Table)), TChartsIndex.SqlText(pDs.Name)]),
      'sl.start_line, r.id');
    var Seen:= TDictionary<string, Byte>.Create;
    try
      for var R in Rows do
      begin
        var K:= IntToStr(R.I('line')) + '|' + IntToStr(R.I('tid'));
        if Seen.ContainsKey(K) then
          Continue;
        Seen.Add(K, 1);
        { each candidate walks with its OWN Seen; a dropped one leaves nothing behind }
        var Route:= TFillRoute.Create;
        Result.Add(Route);
        Route.Ctx:= pCtx.Clone;
        var V:= TDictionary<Integer, Byte>.Create;
        try
          Route.Walk:= WalkRoutine(tsClient, R.I('tid'), pDepth, V, Route.Ctx);
        finally
          V.Free;
        end;
        var HasX:= False;
        for var I in Route.Walk.Items do
          HasX:= HasX or (I.Kind = KIND_CROSSES);
        if not HasX then
        begin
          Result.Remove(Route);
          Continue;
        end;
        var Ll:= FNear.Query(Format(SQL_FILL_LITS, [pDs.Fid, R.I('line')]));
        try
          Route.Lits:= LineLits(tsClient, Ll.ToArray, pDs.FileName, pDs.Fid);
        finally
          Ll.Free;
        end;
        Route.Line:= R.I('line');
        Route.Routine:= if R.S('routine') <> '' then ShortName(R.S('routine'), UnitNameOf(pDs.FileName)) else '';
        Route.TargetId:= R.I('tid');
        Route.TargetShort:= ShortName(R.S('tq'), UnitNameOf(R.S('tpath')));
        Route.TargetPath:= R.S('tpath');
        Route.TargetImpl:= R.I('tistart');
      end;
    finally
      Seen.Free;
      Rows.Free;
    end;
  except
    on E: Exception do
    begin
      Result.Free;
      raise;
    end;
  end;
end;
class function TTraceWalker.TracedRouteIds(const pPaths: TArray<TArray<TTraceItem>>): TTracedRoutes;
begin
  var Snd:= TList<TTraceItem>.Create;
  var Cal:= TList<Integer>.Create;
  try
    for var P in pPaths do
      for var I in P do
      begin
        if InNames(I.Actor, ['SERVER', 'DATABASE']) then
          Continue;
        if I.Kind = KIND_CROSSES then
        begin
          if I.Owner <> 0 then
            Snd.Add(I);
          Break;
        end;
        if (I.Owner <> 0) and not Cal.Contains(I.Owner) then
          Cal.Add(I.Owner);
      end;
    Result.Senders:= Snd.ToArray;
    Result.Callers:= Cal.ToArray;
  finally
    Cal.Free;
    Snd.Free;
  end;
end;

function TTraceWalker.AlsoRoutes(const pSenders: TArray<TTraceItem>; const pSkipIds: TArray<Integer>; pCtx: TTraceContext): TObjectList<TTraceItem>;
begin
  Result:= TObjectList<TTraceItem>.Create;
  try
    var Done:= TDictionary<Integer, Byte>.Create;
    try
      for var X in pSenders do
      begin
        var Sid:= X.Owner;
        if (Sid = 0) or Done.ContainsKey(Sid) then
          Continue;
        Done.Add(Sid, 1);
        var S:= RoutineFacts(tsClient, Sid, pCtx.Likes);
        if not TableSpecificSender(S, X.Line, pCtx.Table) then
          Continue;
        var Callers:= FNear.AllRows(Format(SQL_SENDER_CALLERS, [Sid]), 'r.start_line, r.id');
        try
          for var C in Callers do
            if not TArray.Contains<Integer>(pSkipIds, C.I('eid')) then
              Result.Add(NewTraceStep(KIND_STEP, 'CALLS ' + S.Short, TraceAnchorText(C.S('path'), C.I('line')), '',
                ShortName(C.S('q'), UnitNameOf(C.S('path'))), 'another caller of the traced sender'));
        finally
          Callers.Free;
        end;
      end;
    finally
      Done.Free;
    end;
  except
    on E: Exception do
    begin
      Result.Free;
      raise;
    end;
  end;
end;

procedure TTraceWalker.MergeTraceOmits(pSection: TTraceSection);
begin
  var Om:= TList<TTraceItem>.Create;
  try
    for var I in pSection.Items do
      if I.Omits and FOmits.ContainsKey(I) then
        Om.Add(I);
    if Om.Count < 2 then
      Exit;
    var Recs:= TList<TOmitRec>.Create;
    try
      for var O in Om do
        Recs.AddRange(FOmits[O]);
      var M:= NewOmitStep(Recs.ToArray);
      M.Line:= Om[0].Line;
      M.Owner:= Om[0].Owner;
      var Idx:= pSection.Items.IndexOf(Om[0]);
      for var O in Om do
        FOmits.Remove(O);
      pSection.Items[Idx]:= M;
      for var K:= 1 to Om.Count - 1 do
        pSection.Items.Remove(Om[K]);
    finally
      Recs.Free;
    end;
  finally
    Om.Free;
  end;
end;

function TTraceWalker.FilesCount(pSide: TTraceSide): Integer;
begin
  Result:= CountRows(pSide, 'files');
end;

class function TTraceWalker.IndexStamp(pIndex: TChartsIndex): string;
begin
  Result:= STAMP_NONE;
  var Q:= pIndex.Query(SQL_STAMP);
  try
    if (Q.Count > 0) and TRegEx.IsMatch(Q[0].S('v'), RE_DIGITS) then
      Result:= FormatDateTime(STAMP_FORMAT, UnixToDateTime(StrToInt64(Q[0].S('v')), True), TFormatSettings.Invariant);
  finally
    Q.Free;
  end;
end;

function BoundaryLikes(const pPattern: string): string;
begin
  var Parts:= pPattern.Split(['|']);
  for var K:= 0 to High(Parts) do
    Parts[K]:= 'u.qualified_name LIKE ''' + TChartsIndex.SqlText(Parts[K]) + '''';
  Result:= string.Join(' OR ', Parts);
end;

function StreamFormat(const pRawLine: string): string;
begin
  var M:= TRegEx.Match(pRawLine, RE_STREAM, [roIgnoreCase]);
  if not M.Success then
    Exit('');
  var A:= M.Groups[1].Value.Split([',']);
  if Length(A) = 0 then
    Exit('');
  var Last_:= A[High(A)].Trim;
  Result:= if (Length(A) >= 2) and TRegEx.IsMatch(Last_, RE_IDENT, [roIgnoreCase]) then Last_ else '';
end;

end.
