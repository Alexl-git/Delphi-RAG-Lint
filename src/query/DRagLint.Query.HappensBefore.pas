unit DRagLint.Query.HappensBefore;

{ drag-lint 1.52 -- lane HBSOLVER: the cross-routine solve of check-init and its entry point CheckInit.

  Spec docs\superpowers\specs\2026-11-17-happens-before-design.md sec. 5.4 (amended by ruling HB2), plan
  docs\superpowers\plans\2026-11-17-happens-before-phase1.md lane SOLVER; acceptance
  tests\autotest\run_check_init_verdicts.ps1 over tests\fixtures\happens-before\solve-*.

  For a unit variable or class var T:
    1. EVENTS (lane HBEVENTS): the writers and the uses of T.
    2. REACH-A: the routines that hold a counting writer of T, plus everything that reaches one backwards
       over call_edges (every confidence) and dispatch fan-in. MustA(r) = "every normal completion of r
       has written T": a LEAST fixpoint (start False) of SolveRoutine's exit bit with MARKS = the writer
       sites of r and the certain calls whose callee set (the callee unless abstract, plus every
       override) is all MustA.
    3. Per program P (one per .dpr; a pseudo-program over every file when the index holds none): the
       ancestors of the use's routine, cut at P's roots (its initialization chain, its program block,
       every escaped routine). EntryDone(r) is a GREATEST fixpoint (start True): AND over every call site
       of r in P of the state just before that call in the caller. An ordered root takes the chain
       state: EntryDone(init k) = EntryDone(init k-1) or MustA(init k-1); the program block starts after
       the last init; an escaped routine starts False.
    4. Verdict of a use = the state just before it. True -> SET. False -> NEVER-SET when HbIsNeverSet
       holds, else MAY-BE-UNSET with a witness (root first, BFS to the nearest unproven root) and the
       reason codes of spec 6.4. Several programs judge the use: the worst wins.
    5. Budget: --max-routines CFGs (distinct routines) per query; exhausted -> MAY-BE-UNSET + budget.

  Initialization sections and the program block have no `defProc`, so SolveRoutine cannot take them.
  They are judged here at TOP-LEVEL STATEMENT granularity (TopLevelSolve): a mark counts only inside
  a plain statement (assignment / call) at the top of the block, inside a nested begin..end, or inside
  either part of a try..finally; never under if / case / loops / try..except / with, never in an
  anonymous method, a short-circuit right operand or an if-expression branch. A goto / label / asm
  refuses the block (cfg-skipped). An `Exit` before a mark keeps the mark from the exit bit.

  Owner ruling 2026-11-17 13:56 (unresolved callee): T passed to a callee with no resolved signature
  is not a silent soft writer. The answer carries the warning
  '<Callee>: source not available -- does it set <T> (by-ref unknown)?' at the call site, the verdict
  can be neither SET (unless proven by other writers) nor NEVER-SET, and the limit code
  `unknown-callee` marks the answer (the verdict literal UNKNOWN-CALLEE needs a THbVerdict member:
  HANDOVER to Types / Render). The ~30 read-only RTL routines of the events lane stay exempt. The
  user records the answer once per call site with a line comment on the call line:
  `// dl:callee-reads` (the callee only reads T: no writer, no warning) or `// dl:callee-sets` (the
  callee always sets T: a counting var-arg writer).

  Read-only; nothing is persisted (no extractor change). Every doubt answers MAY-BE-UNSET: a wrong
  SET costs more than a hundred MAY answers. }

interface

uses
  DRagLint.Query.HappensBefore.Types
  ;

const
  /// <summary>Limit code of an answer that holds an argument passed to an unresolved callee
  /// (owner ruling 2026-11-17: the variable's answer is UNKNOWN-CALLEE).</summary>
  HB_LIMIT_UNKNOWN_CALLEE = 'unknown-callee';

  /// <summary>Line comment on a call line: the unresolved callee only READS the argument.</summary>
  HB_MARKER_CALLEE_READS = 'dl:callee-reads';

  /// <summary>Line comment on a call line: the unresolved callee always SETS the argument.</summary>
  HB_MARKER_CALLEE_SETS = 'dl:callee-sets';

/// <summary>Answers check-init for one target (spec 5.4): SET, NEVER-SET or MAY-BE-UNSET per judged
/// use, the headline (worst use), the writer list (ruling HB2), witness hops and reason codes.</summary>
/// <param name="pDbPath">The project index; must exist and be readable (the verb checks the schema).</param>
/// <param name="pTarget">QName or unique trailing part of a unit variable, class var or instance field;
/// '' when only pAt names the target.</param>
/// <param name="pAt">`file:line[:col]` of the one use to judge, '' to judge every use.</param>
/// <param name="pOptions">MaxRoutines (0 = HB_DEFAULT_MAX_ROUTINES) and Explain.</param>
/// <returns>A complete answer; Proven is True only for a SET or NEVER-SET backed by a proof.</returns>
/// <exception cref="EHbUsage">Malformed pAt; unknown / ambiguous target; --at naming another variable
/// (raised by the events lane, candidates attached).</exception>
/// <remarks>Read-only. Not thread-safe (the shared parse cache). Deterministic: every set is walked in
/// sorted order, so two runs give the same answer except Budget.Ms. Instance fields are answered
/// by the constructor model (DRagLint.Query.HappensBefore.Fields.CheckInstanceField, spec 5.5).
/// An unresolved callee that receives the target adds the limit unknown-callee and its warning to
/// Summary; such an answer is never NEVER-SET and never SET unless other writers prove it.</remarks>
function CheckInit(const pDbPath, pTarget, pAt: string; const pOptions: THbOptions): THbAnswer;  // dl:ok unused-public-symbol@915c -- REVIEWED 2026-11-17 v152 HBSOLVER: check-init contract; consumers are the CLI verb and MCP tool, wired at INT (handover H-CLI) and the solve-driver fixture

implementation

uses
  System.SysUtils
, System.Classes
, System.Math
, System.Diagnostics
, System.Generics.Collections
, System.Generics.Defaults
, System.RegularExpressions
, TreeSitter
, DRagLint.Core.Interfaces
, DRagLint.Storage.SQLite
, DRagLint.Charts.Index
, DRagLint.Diagnostics.ParseCache
, DRagLint.Lint.InitSections
, DRagLint.Query.HappensBefore.Events
, DRagLint.Query.HappensBefore.Roots
, DRagLint.Query.HappensBefore.Intra
, DRagLint.Query.HappensBefore.Fields
  ;

type
  /// <summary>One call site (a ref with a call edge).</summary>
  TCallSite = record
    CallerId: Int64;
    CalleeId: Int64;
    FilePath: string;
    Line: Integer;
    Col: Integer;
    /// <summary>confidence = certain and the ref is a call (or names a function): may carry MustA.</summary>
    Certain: Boolean;
  end;

  /// <summary>What the solver needs to know about one routine symbol.</summary>
  TRoutineInfo = record
    Id: Int64;
    Kind: string;
    QName: string;
    FileId: Int64;
    FilePath: string;
    Line: Integer;
    IsFunction: Boolean;
    IsAbstract: Boolean;
  end;

  /// <summary>A routine solved with every query site the solver can ask about it.</summary>
  TSolved = record
    State: THbRoutineState;
  end;

  /// <summary>One program as the solver sees it: its files, its ordered chain and the chain states.</summary>
  TProgramView = record
    Name: string;
    ProgramBlockId: Int64;
    Files: TArray<Int64>;
    AllFiles: Boolean;
    ChainIds: TArray<Int64>;
    ChainDisplay: TArray<string>;
    Unreliable: Boolean;
  end;

  /// <summary>The verdict of one use in one program, with what the witness needs.</summary>
  TUseInProgram = record
    Judged: Boolean;
    Done: Boolean;
    InClosure: Boolean;
    Located: Boolean;
    Witness: TArray<THbHop>;
    Reasons: TArray<THbReason>;
    Why: string;
  end;

  /// <summary>The solver of one CheckInit call. Owns its caches; the index and store belong to CheckInit.</summary>
  TSolver = class  // dl:ok god-class@1457, high-response@1457 -- REVIEWED 2026-11-17 v152 HBSOLVER: one solve = one object holding the fixpoint caches; its RFC is the index queries each fixpoint step needs
  strict private
    FIndex: TChartsIndex;
    FStore: ISymbolStore;
    FMax: Integer;
    FEvents: THbEvents;
    FInfo: TDictionary<Int64, TRoutineInfo>;
    FCallsIn: TDictionary<Int64, TArray<TCallSite>>;
    FCallersOf: TDictionary<Int64, TArray<TCallSite>>;
    FOverrides: TDictionary<Int64, TArray<Int64>>;
    FBases: TDictionary<Int64, TArray<Int64>>;
    FWriterSites: TDictionary<Int64, TArray<THbSite>>;
    FUseSites: TDictionary<Int64, TArray<THbSite>>;
    FReachA: THashSet<Int64>;
    FMustA: THashSet<Int64>;
    FBudgetSet: THashSet<Int64>;
    FCache: TDictionary<string, TSolved>;
    FSkipped: THashSet<Int64>;
    FClassifier: THbEscapeClassifier;
    FPrograms: TArray<TProgramView>;
    FExhausted: Boolean;
    FUnorderedRoots: THashSet<Int64>;
    FMustFinal: Boolean;
    function Rows(const pSql: string): TObjectList<TIndexRow>;
    function Info(pId: Int64): TRoutineInfo;
    procedure LoadInfos(const pIds: TArray<Int64>);
    function ReadSites(const pWhere: string): TArray<TCallSite>;
    function CallsIn(pId: Int64): TArray<TCallSite>;
    function BasesOf(pId: Int64): TArray<Int64>;
    function OverridesOf(pId: Int64): TArray<Int64>;
    function DispatchClosure(pId: Int64; const pSqlFmt: string): TArray<Int64>;
    function CallersOf(pId: Int64): TArray<TCallSite>;
    function CalleeSet(pId: Int64): TArray<Int64>;
    function CallCountsAsMark(const pSite: TCallSite): Boolean;
    function MarksOf(pId: Int64): TArray<THbSite>;
    function QueriesOf(pId: Int64): TArray<THbSite>;
    function RawSolve(pId: Int64; pEntry: Boolean): THbRoutineState;
    function Solve(pId: Int64; pEntry: Boolean): THbRoutineState;
    function StateAt(const pState: THbRoutineState; pLine, pCol: Integer; out pQuery: THbQueryState): Boolean;
    procedure ComputeReachA;
    procedure ComputeMustA;
    procedure LoadPrograms;
    function InProgram(const pProg: TProgramView; pId: Int64): Boolean;
    function ChainPos(const pProg: TProgramView; pId: Int64): Integer;
    function ChainEntry(const pProg: TProgramView; pPos: Integer): Boolean;
    function IsRoot(const pProg: TProgramView; pId: Int64; out pEntry: Boolean; out pNote: string): Boolean;
    function JudgeUse(const pProg: TProgramView; const pUse: THbSite): TUseInProgram;
    function RootReasons(const pProg: TProgramView; pRootId: Int64; out pWhy: string): TArray<THbReason>;
    function HopReasons(pId: Int64; pLine, pCol: Integer): TArray<THbReason>;
  public
    constructor Create(const pIndex: TChartsIndex; const pStore: ISymbolStore; pMax: Integer;
      const pEvents: THbEvents);
    destructor Destroy; override;
    /// <summary>Judges every use of the events; fills Uses, Verdict, Reasons, Roots, Budget.</summary>
    procedure Run(var pAnswer: THbAnswer);
  end;

const
  KIND_INIT = 'initialization';
  KIND_FINAL = 'finalization';
  KIND_PROGRAM = 'program';
  KIND_LIBRARY = 'library';
  CONF_CERTAIN = 'certain';
  REF_CALL = 'call';
  DIRECTIVE_ABSTRACT = 'abstract';
  CALLEE_LOOKBACK_LINES = 10;
  { a section / main block sits at most this deep under the tree root }
  TOP_CONTAINER_MAX_DEPTH = 3;
  WHY_PREFIX = 'why not SET: ';

{ ---------------------------------------------------------------------------------------------- }
{ small helpers                                                                                   }

{ The warning text of the owner ruling for an argument passed to an unresolved callee:
  '<Callee>: source not available -- does it set <Arg> (by-ref unknown)?' }
function HbUnknownCalleeWarning(const pCallee, pArg: string): string;
begin
  Result:= pCallee + ': source not available -- does it set ' + pArg + ' (by-ref unknown)?';
end;

function Id64(const pRow: TIndexRow; const pCol: string): Int64;
begin
  Result:= StrToInt64Def(pRow.S(pCol), 0);
end;

function SiteKey(pLine, pCol: Integer): string;
begin
  Result:= IntToStr(pLine) + ':' + IntToStr(pCol);
end;

function SiteBefore(pLine1, pCol1, pLine2, pCol2: Integer): Boolean;
begin
  Result:= (pLine1 < pLine2) or ((pLine1 = pLine2) and (pCol1 < pCol2));
end;

function LastPart(const pQName: string): string;
begin
  Result:= Copy(pQName, LastDelimiter('.', pQName) + 1, MaxInt);
end;

procedure AddReason(var pList: TArray<THbReason>; pReason: THbReason);
begin
  for var R in pList do
    if R = pReason then Exit;
  pList:= pList + [pReason];
end;

function SortedReasons(const pList: TArray<THbReason>): TArray<THbReason>;
begin
  Result:= nil;
  for var R:= Low(THbReason) to High(THbReason) do
    for var X in pList do
      if X = R then
      begin
        Result:= Result + [R];
        Break;
      end;
end;

function SortedIds(const pSet: THashSet<Int64>): TArray<Int64>;
begin
  Result:= pSet.ToArray;
  TArray.Sort<Int64>(Result);
end;

function IdList(const pIds: TArray<Int64>): string;
begin
  Result:= '';
  for var I in pIds do Result:= Result + (if Result = '' then '' else ',') + IntToStr(I);
end;

{ ---------------------------------------------------------------------------------------------- }
{ top-level statement solve of an initialization / finalization section and of a program block   }

function NodeText(const pSrc: TBytes; const pNode: TTSNode): string;
begin
  Result:= '';
  if pNode.IsNull or (Integer(pNode.EndByte) > Length(pSrc)) then Exit;
  Result:= TEncoding.UTF8.GetString(pSrc, Integer(pNode.StartByte), Integer(pNode.EndByte - pNode.StartByte));
end;

{ The statements of a container (initialization / finalization / block / statements), keywords left out. }
function StatementsOf(const pNode: TTSNode): TArray<TTSNode>;
begin
  Result:= nil;
  for var I:= 0 to pNode.NamedChildCount - 1 do
  begin
    var C:= pNode.NamedChild(I);
    var T:= C.NodeType;
    if (T <> '') and (T[1] = 'k') and (Length(T) > 1) and CharInSet(T[2], ['A'..'Z']) then Continue;
    if T = 'comment' then Continue;
    Result:= Result + [C];
  end;
end;

{ True when a mark at pSite inside pStmt runs every time pStmt completes normally. }
function MarkIsMust(const pSrc: TBytes; const pStmt: TTSNode; const pSite: THbSite): Boolean;
begin
  var T:= pStmt.NodeType;
  if (T = 'assignment') or (T = 'statement') or (T = 'varDef') or (T = 'constInline') then
  begin
    var L: Boolean;
    var G:= HbSiteGuarded(pSrc, pStmt, pSite, L);
    Exit(not (G or L));
  end;
  if (T = 'block') or (T = 'statements') then
  begin
    for var C in StatementsOf(pStmt) do
      if HbNodeContains(C, pSite) then Exit(MarkIsMust(pSrc, C, pSite));
    Exit(False);
  end;
  if T = 'try' then
  begin
    var HasFinally:= False;
    for var I:= 0 to pStmt.NamedChildCount - 1 do
      if pStmt.NamedChild(I).NodeType = 'kFinally' then HasFinally:= True;
    if not HasFinally then Exit(False);
    for var I:= 0 to pStmt.NamedChildCount - 1 do
    begin
      var C:= pStmt.NamedChild(I);
      if (C.NodeType = 'statements') and HbNodeContains(C, pSite) then Exit(MarkIsMust(pSrc, C, pSite));
    end;
  end;
  Result:= False;
end;

function SubtreeHas(const pNode: TTSNode; const pTypes: array of string): Boolean;
begin
  for var S in pTypes do
    if pNode.NodeType = S then Exit(True);
  for var I:= 0 to pNode.NamedChildCount - 1 do
    if SubtreeHas(pNode.NamedChild(I), pTypes) then Exit(True);
  Result:= False;
end;

{ The container node of an initialization / finalization section or a program block. }
function FindTopContainer(const pRoot: TTSNode; const pKind: string; pStartLine: Integer): TTSNode;
var
  Best: TTSNode;

  procedure Walk(const pNode: TTSNode; pDepth: Integer);
  begin
    if pDepth > TOP_CONTAINER_MAX_DEPTH then Exit;
    for var I:= 0 to pNode.NamedChildCount - 1 do
    begin
      var C:= pNode.NamedChild(I);
      var T:= C.NodeType;
      if (pKind = KIND_INIT) or (pKind = KIND_FINAL) then
      begin
        if T = pKind then
        begin
          Best:= C;
          Exit;
        end;
        { a unit's `begin .. end.` initialization part }
        if (pKind = KIND_INIT) and (T = 'block') and (pNode.NodeType = 'unit')
          and (Integer(C.StartPoint.row) + 1 >= pStartLine) then Best:= C;
      end
      else if (T = 'block') and ((pNode.NodeType = KIND_PROGRAM) or (pNode.NodeType = KIND_LIBRARY)) then
        Best:= C;  { the LAST block of the program is its main block }
      Walk(C, pDepth + 1);
    end;
  end;

begin
  Best:= Default(TTSNode);
  Walk(pRoot, 0);
  Result:= Best;
end;

{ Must-analysis of a top-level block (see the unit header): the bit before each query and at exit. }
function TopLevelSolve(const pPath, pKind: string; pStartLine: Integer; pRoutineId: Int64;
  const pMarks, pQueries: TArray<THbSite>; pEntry: Boolean): THbRoutineState;
begin
  Result:= Default(THbRoutineState);
  Result.RoutineId:= pRoutineId;
  SetLength(Result.Queries, Length(pQueries));
  for var I:= 0 to High(pQueries) do Result.Queries[I].Site:= pQueries[I];
  if (pPath = '') or not FileExists(pPath) then Exit;
  var PF:= TAstParseCache.Get(pPath);
  if PF.Tree = nil then Exit;
  var Src:= PF.Src;
  var Box:= FindTopContainer(PF.Tree.RootNode, pKind, pStartLine);
  if Box.IsNull then Exit;
  Result.Found:= True;
  if SubtreeHas(Box, ['goto', 'label', 'asm']) then
  begin
    Result.CfgSkipped:= True;
    Exit;
  end;
  var Stmts:= StatementsOf(Box);
  var ExitRe:= TRegEx.Create('\bexit\b', [roIgnoreCase]);
  { MustIdx = the earliest top-level statement that holds a must mark (MaxInt: none) }
  var MustIdx:= MaxInt;
  var ExitMust:= False;
  for var M in pMarks do
    for var K:= 0 to High(Stmts) do
      if HbNodeContains(Stmts[K], M) then
      begin
        if MarkIsMust(Src, Stmts[K], M) then
        begin
          MustIdx:= Min(MustIdx, K);
          var Before:= '';
          for var J:= 0 to K - 1 do Before:= Before + NodeText(Src, Stmts[J]) + #10;
          if not ExitRe.IsMatch(Before) then ExitMust:= True;
        end;
        Break;
      end;
  for var Q:= 0 to High(Result.Queries) do
    for var K:= 0 to High(Stmts) do
      if HbNodeContains(Stmts[K], Result.Queries[Q].Site) then
      begin
        Result.Queries[Q].Located:= True;
        var L: Boolean;
        HbSiteGuarded(Src, Stmts[K], Result.Queries[Q].Site, L);
        Result.Queries[Q].InClosure:= L;
        Result.Queries[Q].Done:= (not L) and (pEntry or (MustIdx < K));
        Break;
      end;
  Result.ExitReachable:= True;
  Result.ExitDone:= pEntry or ExitMust;
end;

{ ---------------------------------------------------------------------------------------------- }
{ TSolver                                                                                         }

constructor TSolver.Create(const pIndex: TChartsIndex; const pStore: ISymbolStore; pMax: Integer;
  const pEvents: THbEvents);
begin
  inherited Create;
  FIndex:= pIndex;
  FStore:= pStore;
  FMax:= pMax;
  FEvents:= pEvents;
  FInfo:= TDictionary<Int64, TRoutineInfo>.Create;
  FCallsIn:= TDictionary<Int64, TArray<TCallSite>>.Create;
  FCallersOf:= TDictionary<Int64, TArray<TCallSite>>.Create;
  FOverrides:= TDictionary<Int64, TArray<Int64>>.Create;
  FBases:= TDictionary<Int64, TArray<Int64>>.Create;
  FWriterSites:= TDictionary<Int64, TArray<THbSite>>.Create;
  FUseSites:= TDictionary<Int64, TArray<THbSite>>.Create;
  FReachA:= THashSet<Int64>.Create;
  FMustA:= THashSet<Int64>.Create;
  FBudgetSet:= THashSet<Int64>.Create;
  FCache:= TDictionary<string, TSolved>.Create;
  FSkipped:= THashSet<Int64>.Create;
  FUnorderedRoots:= THashSet<Int64>.Create;
  FClassifier:= THbEscapeClassifier.Create(pStore);
  for var W in FEvents.Writers do
    if W.Counts and (W.Site.RoutineId <> 0) then
    begin
      var L: TArray<THbSite>;
      if not FWriterSites.TryGetValue(W.Site.RoutineId, L) then L:= nil;
      FWriterSites.AddOrSetValue(W.Site.RoutineId, L + [W.Site]);
    end;
  for var U in FEvents.UseSites do
    if U.Site.RoutineId <> 0 then
    begin
      var L: TArray<THbSite>;
      if not FUseSites.TryGetValue(U.Site.RoutineId, L) then L:= nil;
      FUseSites.AddOrSetValue(U.Site.RoutineId, L + [U.Site]);
    end;
end;

destructor TSolver.Destroy;
begin
  FClassifier.Free;
  FUnorderedRoots.Free;
  FSkipped.Free;
  FCache.Free;
  FBudgetSet.Free;
  FMustA.Free;
  FReachA.Free;
  FUseSites.Free;
  FWriterSites.Free;
  FBases.Free;
  FOverrides.Free;
  FCallersOf.Free;
  FCallsIn.Free;
  FInfo.Free;
  inherited;
end;

function TSolver.Rows(const pSql: string): TObjectList<TIndexRow>;
begin
  Result:= FIndex.Query(pSql);
end;

procedure TSolver.LoadInfos(const pIds: TArray<Int64>);
begin
  var Need: TArray<Int64>:= nil;
  for var I in pIds do
    if (I <> 0) and not FInfo.ContainsKey(I) then Need:= Need + [I];
  if Need = nil then Exit;
  var R:= Rows('SELECT s.id, s.kind, s.qualified_name, s.file_id, f.path, s.start_line, ' +
    'COALESCE(s.impl_start_line, 0) AS isl, COALESCE(s.signature, '''') AS sig, COALESCE(s.directives, '''') AS dir ' +
    'FROM symbols s JOIN files f ON f.id = s.file_id WHERE s.id IN (' + IdList(Need) + ')');
  try
    for var Row in R do
    begin
      var I:= Default(TRoutineInfo);
      I.Id:= Id64(Row, 'id');
      I.Kind:= Row.S('kind');
      I.QName:= Row.S('qualified_name');
      I.FileId:= Id64(Row, 'file_id');
      I.FilePath:= Row.S('path');
      I.Line:= if Row.I('isl') > 0 then Row.I('isl') else Row.I('start_line');
      var Sig:= Row.S('sig');
      var Close:= LastDelimiter(')', Sig);
      I.IsFunction:= (I.Kind = 'function') or ((I.Kind = 'method') and Copy(Sig, Close + 1, MaxInt).Contains(':'));
      I.IsAbstract:= LowerCase(Row.S('dir')).Contains(DIRECTIVE_ABSTRACT);
      FInfo.AddOrSetValue(I.Id, I);
    end;
  finally
    R.Free;
  end;
  for var I in Need do
    if not FInfo.ContainsKey(I) then
    begin
      var X:= Default(TRoutineInfo);
      X.Id:= I;
      FInfo.Add(I, X);
    end;
end;

function TSolver.Info(pId: Int64): TRoutineInfo;
begin
  if not FInfo.TryGetValue(pId, Result) then
  begin
    LoadInfos([pId]);
    Result:= FInfo[pId];
  end;
end;

function TSolver.ReadSites(const pWhere: string): TArray<TCallSite>;
begin
  Result:= nil;
  { a ref in a program's main block has no enclosing symbol: its routine is the program symbol }
  var R:= Rows('SELECT COALESCE(r.enclosing_symbol_id, (SELECT p.id FROM symbols p WHERE p.file_id = r.file_id ' +
    'AND p.kind IN (''program'', ''library'') ORDER BY p.id LIMIT 1), 0) AS caller, c.target_symbol_id AS callee, f.path, ' +
    'r.start_line, r.start_col, r.kind AS rk, c.confidence FROM refs r JOIN call_edges c ON c.ref_id = r.id ' +
    'JOIN files f ON f.id = r.file_id WHERE ' + pWhere + ' ORDER BY f.path, r.start_line, r.start_col, r.id');
  try
    var Ids: TArray<Int64>:= nil;
    for var Row in R do Ids:= Ids + [Id64(Row, 'callee')];
    LoadInfos(Ids);
    for var Row in R do
    begin
      var S:= Default(TCallSite);
      S.CallerId:= Id64(Row, 'caller');
      S.CalleeId:= Id64(Row, 'callee');
      S.FilePath:= Row.S('path');
      S.Line:= Row.I('start_line');
      S.Col:= Row.I('start_col');
      S.Certain:= (Row.S('confidence') = CONF_CERTAIN) and ((Row.S('rk') = REF_CALL) or FInfo[S.CalleeId].IsFunction);
      Result:= Result + [S];
    end;
  finally
    R.Free;
  end;
end;

function TSolver.CallsIn(pId: Int64): TArray<TCallSite>;
begin
  if FCallsIn.TryGetValue(pId, Result) then Exit;
  var I:= Info(pId);
  { the main block's refs carry no enclosing symbol }
  var IsMain:= (I.Kind = KIND_PROGRAM) or (I.Kind = KIND_LIBRARY);
  Result:= ReadSites(if IsMain then
    Format('(r.enclosing_symbol_id = %d OR (r.enclosing_symbol_id IS NULL AND r.file_id = %d))', [pId, I.FileId])
  else
    Format('r.enclosing_symbol_id = %d', [pId]));
  FCallsIn.Add(pId, Result);
end;

{ The transitive closure of one dispatch_edges direction from pId, sorted, pId left out. pSqlFmt selects
  the next ids as column x and takes the current id as its one %d (ids only: no text reaches the SQL). }
function TSolver.DispatchClosure(pId: Int64; const pSqlFmt: string): TArray<Int64>;
begin
  Result:= nil;
  var Seen:= THashSet<Int64>.Create;
  try
    var Work:= [pId];
    while Work <> nil do
    begin
      var Cur:= Work[High(Work)];
      SetLength(Work, Length(Work) - 1);
      var R:= Rows(Format(pSqlFmt, [Cur]));
      try
        for var Row in R do
        begin
          var X:= Id64(Row, 'x');
          if (X <> pId) and Seen.Add(X) then
          begin
            Result:= Result + [X];
            Work:= Work + [X];
          end;
        end;
      finally
        R.Free;
      end;
    end;
  finally
    Seen.Free;
  end;
  TArray.Sort<Int64>(Result);
end;

function TSolver.BasesOf(pId: Int64): TArray<Int64>;
begin
  if FBases.TryGetValue(pId, Result) then Exit;
  Result:= DispatchClosure(pId,
    'SELECT base_symbol_id AS x FROM dispatch_edges WHERE impl_symbol_id = %d ORDER BY base_symbol_id');
  FBases.Add(pId, Result);
end;

function TSolver.OverridesOf(pId: Int64): TArray<Int64>;
begin
  if FOverrides.TryGetValue(pId, Result) then Exit;
  Result:= DispatchClosure(pId,
    'SELECT impl_symbol_id AS x FROM dispatch_edges WHERE kind = ''override'' AND base_symbol_id = %d ORDER BY impl_symbol_id');
  FOverrides.Add(pId, Result);
end;

function TSolver.CallersOf(pId: Int64): TArray<TCallSite>;
begin
  if FCallersOf.TryGetValue(pId, Result) then Exit;
  Result:= ReadSites('c.target_symbol_id IN (' + IdList([pId] + BasesOf(pId)) + ')');
  FCallersOf.Add(pId, Result);
end;

{ What a call to pId can run: pId itself unless abstract, and every override of it. }
function TSolver.CalleeSet(pId: Int64): TArray<Int64>;
begin
  Result:= if Info(pId).IsAbstract then nil else [pId];
  Result:= Result + OverridesOf(pId);
end;

function TSolver.CallCountsAsMark(const pSite: TCallSite): Boolean;
begin
  Result:= False;
  if not pSite.Certain then Exit;
  var Set_:= CalleeSet(pSite.CalleeId);
  if Set_ = nil then Exit;
  for var C in Set_ do
    if not FMustA.Contains(C) then Exit;
  Result:= True;
end;

function TSolver.MarksOf(pId: Int64): TArray<THbSite>;
begin
  if not FWriterSites.TryGetValue(pId, Result) then Result:= nil;
  for var C in CallsIn(pId) do
    if CallCountsAsMark(C) then
    begin
      var S:= Default(THbSite);
      S.FileName:= C.FilePath;
      S.Line:= C.Line;
      S.Col:= C.Col;
      Result:= Result + [S];
    end;
end;

function TSolver.QueriesOf(pId: Int64): TArray<THbSite>;
begin
  Result:= nil;
  for var C in CallsIn(pId) do
  begin
    var S:= Default(THbSite);
    S.FileName:= C.FilePath;
    S.Line:= C.Line;
    S.Col:= C.Col;
    Result:= Result + [S];
  end;
  var U: TArray<THbSite>;
  if FUseSites.TryGetValue(pId, U) then Result:= Result + U;
end;

function TSolver.RawSolve(pId: Int64; pEntry: Boolean): THbRoutineState;
begin
  Result:= Default(THbRoutineState);
  Result.RoutineId:= pId;
  if not FBudgetSet.Contains(pId) then
  begin
    if FBudgetSet.Count >= FMax then
    begin
      FExhausted:= True;
      var Q:= QueriesOf(pId);
      SetLength(Result.Queries, Length(Q));
      for var I:= 0 to High(Q) do Result.Queries[I].Site:= Q[I];
      Exit;
    end;
    FBudgetSet.Add(pId);
  end;
  var I:= Info(pId);
  var TopLevel:= (I.Kind = KIND_INIT) or (I.Kind = KIND_FINAL) or (I.Kind = KIND_PROGRAM) or (I.Kind = KIND_LIBRARY);
  Result:= if TopLevel then TopLevelSolve(I.FilePath, I.Kind, I.Line, pId, MarksOf(pId), QueriesOf(pId), pEntry)
    else SolveRoutine(FStore, pId, MarksOf(pId), QueriesOf(pId), pEntry);
  if Result.CfgSkipped then FSkipped.Add(pId);
end;

function TSolver.Solve(pId: Int64; pEntry: Boolean): THbRoutineState;
var
  S: TSolved;
begin
  var Key:= IntToStr(pId) + (if pEntry then ':1' else ':0');
  if FMustFinal and FCache.TryGetValue(Key, S) then Exit(S.State);
  Result:= RawSolve(pId, pEntry);
  if FMustFinal then
  begin
    S.State:= Result;
    FCache.AddOrSetValue(Key, S);
  end;
end;

function TSolver.StateAt(const pState: THbRoutineState; pLine, pCol: Integer; out pQuery: THbQueryState): Boolean;
begin
  for var Q in pState.Queries do
    if (Q.Site.Line = pLine) and (Q.Site.Col = pCol) then
    begin
      pQuery:= Q;
      Exit(True);
    end;
  pQuery:= Default(THbQueryState);
  Result:= False;
end;

procedure TSolver.ComputeReachA;
begin
  var Work:= TList<Int64>.Create;
  try
    var Seeds:= FWriterSites.Keys.ToArray;
    TArray.Sort<Int64>(Seeds);
    for var W in Seeds do
      if FReachA.Add(W) then Work.Add(W);
    while Work.Count > 0 do
    begin
      var Cur:= Work[Work.Count - 1];
      Work.Delete(Work.Count - 1);
      for var C in CallersOf(Cur) do
        if (C.CallerId <> 0) and FReachA.Add(C.CallerId) then Work.Add(C.CallerId);
    end;
  finally
    Work.Free;
  end;
end;

procedure TSolver.ComputeMustA;
begin
  { least fixpoint: sweep REACH-A in id order until no routine turns True }
  var Ids:= SortedIds(FReachA);
  LoadInfos(Ids);
  var Changed:= True;
  while Changed and not FExhausted do
  begin
    Changed:= False;
    for var R in Ids do
    begin
      if FMustA.Contains(R) then Continue;
      var St:= RawSolve(R, False);
      if St.Found and St.ExitDone then
      begin
        FMustA.Add(R);
        Changed:= True;
      end;
    end;
  end;
  FMustFinal:= True;
end;

procedure TSolver.LoadPrograms;
begin
  FPrograms:= nil;
  var Roots:= LoadRoots(FStore);
  for var O in ProgramInitOrders(FStore) do
  begin
    var P:= Default(TProgramView);
    P.Name:= O.ProgramName;
    P.ProgramBlockId:= O.ProgramBlockId;
    P.Files:= [O.ProgramFileId];
    for var U in O.Units do P.Files:= P.Files + [U.FileId];
    TArray.Sort<Int64>(P.Files);
    for var C in Roots.Chains do
      if C.ProgramFileId = O.ProgramFileId then
      begin
        for var R in C.Roots do
        begin
          P.ChainIds:= P.ChainIds + [R.SymbolId];
          P.ChainDisplay:= P.ChainDisplay + [R.Display];
        end;
        P.Unreliable:= C.Unreliable;
      end;
    FPrograms:= FPrograms + [P];
  end;
  if FPrograms = nil then
  begin
    var P:= Default(TProgramView);
    P.Name:= '';
    P.AllFiles:= True;
    FPrograms:= [P];
  end;
end;

function TSolver.InProgram(const pProg: TProgramView; pId: Int64): Boolean;
begin
  if pProg.AllFiles then Exit(True);
  var F:= Info(pId).FileId;
  var Idx: Integer;
  Result:= TArray.BinarySearch<Int64>(pProg.Files, F, Idx);
end;

function TSolver.ChainPos(const pProg: TProgramView; pId: Int64): Integer;
begin
  for var K:= 0 to High(pProg.ChainIds) do
    if pProg.ChainIds[K] = pId then Exit(K);
  Result:= -1;
end;

{ The bit on entry of chain link pPos: some earlier link must-wrote. An unreliable chain proves nothing. }
function TSolver.ChainEntry(const pProg: TProgramView; pPos: Integer): Boolean;
begin
  Result:= False;
  if pProg.Unreliable then Exit;
  for var K:= 0 to pPos - 1 do
    if FMustA.Contains(pProg.ChainIds[K]) then Exit(True);
end;

function TSolver.IsRoot(const pProg: TProgramView; pId: Int64; out pEntry: Boolean; out pNote: string): Boolean;
begin
  pEntry:= False;
  pNote:= '';
  var K:= ChainPos(pProg, pId);
  if K >= 0 then
  begin
    pEntry:= ChainEntry(pProg, K);
    pNote:= Format('%s, link %d of %d (%s)', [pProg.ChainDisplay[K], K + 1, Length(pProg.ChainIds), pProg.Name]);
    Exit(True);
  end;
  var I:= Info(pId);
  if (I.Kind = KIND_INIT) or (I.Kind = KIND_PROGRAM) or (I.Kind = KIND_LIBRARY) then
  begin
    pNote:= 'unordered root: ' + I.Kind + ' of ' + I.QName;
    Exit(True);
  end;
  var C:= FClassifier.ClassOf(pId);
  Result:= C <> hecNone;
  if Result then pNote:= 'escaped root (' + EscapeClassCode(C) + ')';
end;

function TSolver.RootReasons(const pProg: TProgramView; pRootId: Int64; out pWhy: string): TArray<THbReason>;
begin
  Result:= nil;
  pWhy:= '';
  var I:= Info(pRootId);
  var K:= ChainPos(pProg, pRootId);
  if K >= 0 then
  begin
    if pProg.Unreliable then
    begin
      AddReason(Result, hrUnreliableOrder);
      pWhy:= 'the initialization order of ' + pProg.Name + ' depends on a conditional / include-borne uses entry';
    end;
    for var J:= K + 1 to High(pProg.ChainIds) do
      if FReachA.Contains(pProg.ChainIds[J]) then
      begin
        AddReason(Result, hrWriterLaterUnit);
        if pWhy = '' then
          pWhy:= Format('root "%s" (link %d of %d) runs before "%s" (link %d), which writes it',
            [pProg.ChainDisplay[K], K + 1, Length(pProg.ChainIds), pProg.ChainDisplay[J], J + 1]);
        Break;
      end;
    Exit;
  end;
  if (I.Kind = KIND_INIT) or (I.Kind = KIND_PROGRAM) or (I.Kind = KIND_LIBRARY) then
  begin
    AddReason(Result, hrUnorderedRoot);
    pWhy:= 'root "' + I.QName + '" is in no program''s initialization order';
    Exit;
  end;
  var C:= FClassifier.ClassOf(pRootId);
  case C of
    hecAddressTaken:
      begin
        AddReason(Result, hrEscapedRoutine);
        AddReason(Result, hrIndirectCall);
      end;
    hecExported, hecInterfaceMethod, hecZeroCallers:
      AddReason(Result, hrEscapedRoutine);
  else
    AddReason(Result, hrUnorderedRoot);
  end;
  pWhy:= Format('root "%s" can run at any time (escaped: %s)', [I.QName, EscapeClassCode(C)]);
end;

{ Reasons a routine on the witness contributes, judged at its query position pLine:pCol. }
function TSolver.HopReasons(pId: Int64; pLine, pCol: Integer): TArray<THbReason>;
var
  W: TArray<THbSite>;
begin
  Result:= nil;
  if FSkipped.Contains(pId) then AddReason(Result, hrCfgSkipped);
  if FWriterSites.TryGetValue(pId, W) then
    for var S in W do
      if SiteBefore(S.Line, S.Col, pLine, pCol) then AddReason(Result, hrWriterConditional)
      else AddReason(Result, hrWriterAfterUseSameRoutine);
  for var C in CallsIn(pId) do
  begin
    if not FReachA.Contains(C.CalleeId) then
    begin
      { a virtual call whose base writes nothing can still dispatch to a writing override }
      var Any:= False;
      for var O in OverridesOf(C.CalleeId) do
        if FReachA.Contains(O) then Any:= True;
      if not Any then Continue;
    end;
    var Before:= SiteBefore(C.Line, C.Col, pLine, pCol);
    if CallCountsAsMark(C) then
    begin
      if Before then AddReason(Result, hrWriterConditional)
      else AddReason(Result, hrWriterAfterUseSameRoutine);
      Continue;
    end;
    if not Before then Continue;
    var Members:= CalleeSet(C.CalleeId);
    var SomeMust:= False;
    for var M in Members do
      if FMustA.Contains(M) then SomeMust:= True;
    if (Length(Members) > 1) and SomeMust then AddReason(Result, hrVirtualFanout)
    else AddReason(Result, hrCalleeNotMust);
  end;
end;

function TSolver.JudgeUse(const pProg: TProgramView; const pUse: THbSite): TUseInProgram;  // dl:ok cyclomatic-complexity@125b, cognitive-complexity@900b -- REVIEWED 2026-11-17 v152 HBSOLVER: one walk of spec 5.4 per use (root, hop, budget, closure cases); split pieces would share every local, so kept whole and covered by 18 verdict fixtures
var
  Entry: Boolean;
  Note: string;
  Q: THbQueryState;
begin
  Result:= Default(TUseInProgram);
  var U:= pUse.RoutineId;
  if (U = 0) or not InProgram(pProg, U) then Exit;
  { ANC = ancestors of U in this program, cut at roots }
  var Anc:= TList<Int64>.Create;
  var InAnc:= THashSet<Int64>.Create;
  var RootSet:= THashSet<Int64>.Create;
  var Unknown:= THashSet<Int64>.Create;
  var ED:= TDictionary<Int64, Boolean>.Create;
  try
    Anc.Add(U);
    InAnc.Add(U);
    var Head:= 0;
    while Head < Anc.Count do
    begin
      var R:= Anc[Head];
      Inc(Head);
      if IsRoot(pProg, R, Entry, Note) then
      begin
        RootSet.Add(R);
        ED.AddOrSetValue(R, Entry);
        Continue;
      end;
      for var C in CallersOf(R) do
      begin
        if C.CallerId = 0 then
        begin
          Unknown.Add(R);
          Continue;
        end;
        if not InProgram(pProg, C.CallerId) then Continue;
        if InAnc.Add(C.CallerId) then Anc.Add(C.CallerId);
      end;
    end;
    if (RootSet.Count = 0) and (Unknown.Count = 0) then Exit;  { no root of this program reaches the use }
    Result.Judged:= True;
    { greatest fixpoint of EntryDone over the non-root ancestors }
    var Ids:= Anc.ToArray;
    TArray.Sort<Int64>(Ids);
    for var R in Ids do
      if not RootSet.Contains(R) then ED.AddOrSetValue(R, not Unknown.Contains(R));
    var Changed:= True;
    while Changed do
    begin
      Changed:= False;
      for var R in Ids do
      begin
        if RootSet.Contains(R) or not ED[R] then Continue;
        var V:= True;
        for var C in CallersOf(R) do
        begin
          if (C.CallerId = 0) or not InProgram(pProg, C.CallerId) then Continue;
          var St:= Solve(C.CallerId, ED[C.CallerId]);
          if not (StateAt(St, C.Line, C.Col, Q) and Q.Done) then
          begin
            V:= False;
            Break;
          end;
        end;
        if not V then
        begin
          ED[R]:= False;
          Changed:= True;
        end;
      end;
    end;
    { the use itself }
    var USt:= Solve(U, ED[U]);
    if StateAt(USt, pUse.Line, pUse.Col, Q) then
    begin
      Result.Located:= Q.Located;
      Result.InClosure:= Q.InClosure;
      Result.Done:= Q.Done and not Q.InClosure;
    end;
    if Result.Done then Exit;
    { witness: BFS from U over callers whose call state is False, to the nearest unproven root }
    var Parent:= TDictionary<Int64, TCallSite>.Create;  { caller -> the call site that leads to its child }
    var ChildOf:= TDictionary<Int64, Int64>.Create;     { caller -> the routine it calls on the path }
    var Seen:= THashSet<Int64>.Create;
    var Queue:= TList<Int64>.Create;
    try
      var Found:= Int64(0);
      Queue.Add(U);
      Seen.Add(U);
      var H:= 0;
      if ED[U] then Found:= U  { the gap is inside U itself }
      else
        while (H < Queue.Count) and (Found = 0) do
        begin
          var R:= Queue[H];
          Inc(H);
          if (RootSet.Contains(R) or Unknown.Contains(R)) and not ED[R] then
          begin
            Found:= R;
            Break;
          end;
          for var C in CallersOf(R) do
          begin
            if (C.CallerId = 0) or not InProgram(pProg, C.CallerId) or not InAnc.Contains(C.CallerId) then Continue;
            var St:= Solve(C.CallerId, ED[C.CallerId]);
            if StateAt(St, C.Line, C.Col, Q) and Q.Done then Continue;
            if Seen.Add(C.CallerId) then
            begin
              Parent.Add(C.CallerId, C);
              ChildOf.Add(C.CallerId, R);
              Queue.Add(C.CallerId);
            end;
          end;
        end;
      if Found = 0 then Found:= U;
      { hops root first: follow ChildOf from Found down to U }
      begin
        var RootI:= Info(Found);
        IsRoot(pProg, Found, Entry, Note);
        if Note = '' then Note:= 'entry of ' + RootI.QName;
        var Hop:= Default(THbHop);
        Hop.Step:= 1;
        Hop.Routine:= RootI.QName;
        Hop.FileName:= RootI.FilePath;
        Hop.Line:= RootI.Line;
        Hop.Note:= Note;
        Result.Witness:= [Hop];
        var HopReasonsAll: TArray<THbReason>:= nil;
        var Cur:= Found;
        while (Cur <> U) and ChildOf.ContainsKey(Cur) do
        begin
          var C:= Parent[Cur];
          for var X in HopReasons(Cur, C.Line, C.Col) do AddReason(HopReasonsAll, X);
          var Child:= ChildOf[Cur];
          var CI:= Info(Child);
          Hop:= Default(THbHop);
          Hop.Step:= Length(Result.Witness) + 1;
          Hop.Routine:= CI.QName;
          Hop.FileName:= C.FilePath;
          Hop.Line:= C.Line;
          Hop.Col:= C.Col;
          Hop.Note:= '-> ' + CI.QName;
          Result.Witness:= Result.Witness + [Hop];
          Cur:= Child;
        end;
        for var X in HopReasons(U, pUse.Line, pUse.Col) do AddReason(HopReasonsAll, X);
        Hop:= Default(THbHop);
        Hop.Step:= Length(Result.Witness) + 1;
        Hop.Routine:= Info(U).QName;
        Hop.FileName:= pUse.FileName;
        Hop.Line:= pUse.Line;
        Hop.Col:= pUse.Col;
        Hop.Note:= 'reads ' + LastPart(FEvents.Target.QName);
        Result.Witness:= Result.Witness + [Hop];
        { reasons: the root's, then the hops' }
        var Why: string;
        if (RootSet.Contains(Found) or Unknown.Contains(Found)) and not ED[Found] then
        begin
          if Unknown.Contains(Found) and not RootSet.Contains(Found) then
          begin
            AddReason(Result.Reasons, hrEscapedRoutine);
            Why:= '"' + RootI.QName + '" has a caller the index cannot place';
          end
          else
            for var X in RootReasons(pProg, Found, Why) do AddReason(Result.Reasons, X);
          if not RootSet.Contains(Found) then FUnorderedRoots.Add(Found)
          else if ChainPos(pProg, Found) < 0 then FUnorderedRoots.Add(Found);
        end;
        if Result.InClosure then
        begin
          AddReason(Result.Reasons, hrEscapedRoutine);
          if Why = '' then Why:= 'the use is inside an anonymous method: it runs whenever the closure is called';
        end;
        for var X in HopReasonsAll do AddReason(Result.Reasons, X);
        if Why = '' then
        begin
          for var X in HopReasonsAll do
          begin
            case X of
              hrWriterConditional: Why:= 'a writer before the use does not run on every path';
              hrWriterAfterUseSameRoutine: Why:= 'a writer runs only after the use';
              hrCalleeNotMust: Why:= 'a routine called before the use does not write it on every path';
              hrVirtualFanout: Why:= 'a virtual call before the use can dispatch to an override that does not write it';
              hrCfgSkipped: Why:= 'a routine on the path holds goto / label / asm (not analysed)';
            end;
            if Why <> '' then Break;
          end;
        end;
        if (Why = '') and not Result.Located then Why:= 'the use could not be placed in its routine''s control flow';
        if Why = '' then Why:= 'no writer runs before the use on every path';
        Result.Why:= Why;
      end;
    finally
      Queue.Free;
      Seen.Free;
      ChildOf.Free;
      Parent.Free;
    end;
  finally
    ED.Free;
    Unknown.Free;
    RootSet.Free;
    InAnc.Free;
    Anc.Free;
  end;
end;

procedure TSolver.Run(var pAnswer: THbAnswer);
begin
  ComputeReachA;
  ComputeMustA;
  LoadPrograms;
  var JudgedPrograms:= THashSet<string>.Create;
  try
    var Headline:= hvSet;
    var AnyCounted:= False;
    for var UseIdx:= 0 to High(FEvents.UseSites) do
    begin
      var Use:= FEvents.UseSites[UseIdx];
      var A:= Default(THbUseAnswer);
      A.Site:= Use.Site;
      A.Verdict:= hvSet;
      var Judged:= False;
      var Bad: TUseInProgram;
      var HaveBad:= False;
      var Count:= 0;
      for var P in FPrograms do
      begin
        var J:= JudgeUse(P, Use.Site);
        if not J.Judged then Continue;
        Judged:= True;
        Inc(Count);
        JudgedPrograms.Add(P.Name);
        if (not J.Done) and not HaveBad then
        begin
          Bad:= J;
          HaveBad:= True;
        end;
      end;
      if not Judged then
      begin
        { no root reaches the use (or it has no routine): not proven }
        A.Verdict:= hvMayBeUnset;
        A.Why:= WHY_PREFIX + 'no root of any program reaches the use';
        AddReason(A.Reasons, hrUnorderedRoot);
      end
      else if HaveBad then
      begin
        A.Verdict:= hvMayBeUnset;
        A.Witness:= Bad.Witness;
        A.Reasons:= Bad.Reasons;
        A.Why:= WHY_PREFIX + Bad.Why;
        if Count > 1 then AddReason(A.Reasons, hrMultiProgram);
      end;
      if FExhausted and (A.Verdict <> hvSet) then AddReason(A.Reasons, hrBudget);
      if FExhausted and (A.Verdict = hvSet) then
      begin
        { a proof that ran out of budget is no proof }
        A.Verdict:= hvMayBeUnset;
        AddReason(A.Reasons, hrBudget);
        A.Why:= WHY_PREFIX + 'the --max-routines budget ran out';
      end;
      if Use.GuardedTest then AddReason(A.Reasons, hrGuardedTest);
      A.Reasons:= SortedReasons(A.Reasons);
      pAnswer.JudgedUses:= pAnswer.JudgedUses + [A];
      if (not Use.GuardedTest) or (Length(FEvents.UseSites) = 1) then
      begin
        Headline:= HbWorseVerdict(Headline, A.Verdict);
        AnyCounted:= True;
      end;
    end;
    pAnswer.Verdict:= if AnyCounted then Headline else hvSet;
    if (JudgedPrograms.Count > 1) and (pAnswer.Verdict = hvMayBeUnset) then AddReason(pAnswer.Reasons, hrMultiProgram);
    if FExhausted then AddReason(pAnswer.Reasons, hrBudget);
    { roots summary: the ordered chains of the programs, then the unordered roots met }
    for var P in FPrograms do
      for var D in P.ChainDisplay do
        if not TArray.Contains<string>(pAnswer.Roots.Ordered, D) then pAnswer.Roots.Ordered:= pAnswer.Roots.Ordered + [D];
    pAnswer.Roots.Unordered:= FUnorderedRoots.Count;
    pAnswer.Budget.Routines:= FBudgetSet.Count;
    pAnswer.Budget.Exhausted:= FExhausted;
  finally
    JudgedPrograms.Free;
  end;
end;

{ ---------------------------------------------------------------------------------------------- }
{ unresolved callees (owner ruling 2026-11-17 13:56)                                              }

type
  TCalleeArg = record
    WriterIdx: Integer;
    Callee: string;
    Marker: string;   { '', HB_MARKER_CALLEE_READS or HB_MARKER_CALLEE_SETS }
  end;

{ For every unresolved soft writer: the unresolved call it is an argument of, and the marker on its line. }
function FindCalleeArgs(const pIndex: TChartsIndex; const pEvents: THbEvents): TArray<TCalleeArg>;
begin
  Result:= nil;
  var Lines:= TDictionary<string, TStringList>.Create;
  try
    for var I:= 0 to High(pEvents.Writers) do
    begin
      var W:= pEvents.Writers[I];
      if (W.How <> hwUnresolved) or W.Resolved then Continue;
      var R:= pIndex.Query('SELECT r.name_text, r.start_line, r.start_col FROM refs r JOIN files f ON f.id = r.file_id ' +
        'LEFT JOIN call_edges c ON c.ref_id = r.id WHERE f.path = ''' + TChartsIndex.SqlText(W.Site.FileName) +
        ''' AND r.kind = ''call'' AND r.symbol_id IS NULL AND c.ref_id IS NULL AND r.start_line BETWEEN ' +
        IntToStr(W.Site.Line - CALLEE_LOOKBACK_LINES) + ' AND ' + IntToStr(W.Site.Line) +
        ' AND (r.start_line < ' + IntToStr(W.Site.Line) + ' OR r.start_col < ' + IntToStr(W.Site.Col) + ') ' +
        'ORDER BY r.start_line DESC, r.start_col DESC LIMIT 1');
      try
        if R.Count = 0 then Continue;  { an unresolved name-matched write, not an argument }
        var A:= Default(TCalleeArg);
        A.WriterIdx:= I;
        A.Callee:= R[0].S('name_text');
        var SL: TStringList;
        if not Lines.TryGetValue(W.Site.FileName, SL) then
        begin
          SL:= TStringList.Create;
          if FileExists(W.Site.FileName) then SL.LoadFromFile(W.Site.FileName);  // dl:ok taint-path-traversal@aae9 -- REVIEWED 2026-11-17 v152 HBSOLVER: the path is files.path from the project index, read only; the env-var chain is the DB location, not this path
          Lines.Add(W.Site.FileName, SL);
        end;
        var CallLine:= R[0].I('start_line');
        for var L:= CallLine to W.Site.Line do
          if InRange(L, 1, SL.Count) then
          begin
            var T:= LowerCase(SL[L - 1]);
            if T.Contains(HB_MARKER_CALLEE_READS) then A.Marker:= HB_MARKER_CALLEE_READS
            else if T.Contains(HB_MARKER_CALLEE_SETS) then A.Marker:= HB_MARKER_CALLEE_SETS;
          end;
        Result:= Result + [A];
      finally
        R.Free;
      end;
    end;
  finally
    for var SL in Lines.Values do SL.Free;
    Lines.Free;
  end;
end;

{ A writer or use in a program's main block carries no routine (the index leaves enclosing_symbol_id
  NULL there): give it the program symbol so the solver can place it. }
procedure PlaceMainBlockSites(const pIndex: TChartsIndex; var pEvents: THbEvents);
var
  Cache: TDictionary<string, TPair<Int64, string>>;

  procedure Place(var pSite: THbSite);
  var
    P: TPair<Int64, string>;
  begin
    if (pSite.RoutineId <> 0) or (pSite.FileName = '') then Exit;
    if not Cache.TryGetValue(pSite.FileName, P) then
    begin
      P:= TPair<Int64, string>.Create(0, '');
      var R:= pIndex.Query('SELECT s.id, s.qualified_name FROM symbols s JOIN files f ON f.id = s.file_id ' +
        'WHERE f.path = ''' + TChartsIndex.SqlText(pSite.FileName) + ''' AND s.kind IN (''program'', ''library'') ' +
        'ORDER BY s.id LIMIT 1');
      try
        if R.Count > 0 then P:= TPair<Int64, string>.Create(Id64(R[0], 'id'), R[0].S('qualified_name'));
      finally
        R.Free;
      end;
      Cache.Add(pSite.FileName, P);
    end;
    pSite.RoutineId:= P.Key;
    pSite.Routine:= P.Value;
  end;

begin
  Cache:= TDictionary<string, TPair<Int64, string>>.Create;
  try
    for var I:= 0 to High(pEvents.Writers) do Place(pEvents.Writers[I].Site);
    for var I:= 0 to High(pEvents.UseSites) do Place(pEvents.UseSites[I].Site);
  finally
    Cache.Free;
  end;
end;

{ ---------------------------------------------------------------------------------------------- }
{ CheckInit                                                                                       }

{ Unresolved callees (owner ruling): a dl:callee-reads marker drops the soft writer, dl:callee-sets makes it a
  counting var-arg writer whose argument is no read; an unmarked one keeps the writer and adds a warning. }
procedure ApplyCalleeMarkers(const pIndex: TChartsIndex; var pEvents: THbEvents; out pWarnings: TArray<string>);
begin
  pWarnings:= nil;
  var Keep: TArray<THbWriter>:= nil;
  var Args:= FindCalleeArgs(pIndex, pEvents);
  for var I:= 0 to High(pEvents.Writers) do
  begin
    var W:= pEvents.Writers[I];
    var Arg:= Default(TCalleeArg);
    var Found:= False;
    for var A in Args do
      if A.WriterIdx = I then
      begin
        Arg:= A;
        Found:= True;
        Break;
      end;
    if Found and (Arg.Marker = HB_MARKER_CALLEE_READS) then Continue;
    if Found and (Arg.Marker = HB_MARKER_CALLEE_SETS) then
    begin
      W.How:= hwVarArg;
      W.Counts:= True;
      var UseList: TArray<THbUse>:= nil;
      for var U in pEvents.UseSites do
        if not ((U.Site.Line = W.Site.Line) and (U.Site.Col = W.Site.Col)
          and SameText(U.Site.FileName, W.Site.FileName)) then UseList:= UseList + [U];
      pEvents.UseSites:= UseList;
    end
    else if Found then
      pWarnings:= pWarnings + [HbUnknownCalleeWarning(Arg.Callee, LastPart(pEvents.Target.QName)) +
        Format(' (%s:%d:%d)', [ExtractFileName(W.Site.FileName), W.Site.Line, W.Site.Col])];
    Keep:= Keep + [W];
  end;
  pEvents.Writers:= Keep;
end;

{ Every use gets the same verdict and why (instance fields, NEVER-SET). }
procedure AnswerEveryUse(var pAnswer: THbAnswer; const pEvents: THbEvents; pVerdict: THbVerdict; const pWhy: string);
begin
  for var U in pEvents.UseSites do
  begin
    var A:= Default(THbUseAnswer);
    A.Site:= U.Site;
    A.Verdict:= pVerdict;
    A.Why:= WHY_PREFIX + pWhy;
    if U.GuardedTest then A.Reasons:= [hrGuardedTest];
    pAnswer.JudgedUses:= pAnswer.JudgedUses + [A];
  end;
end;

{ The writer-kind reason codes on every MAY use: soft-writer, nil-write-only (dropped when only soft writers
  exist and none of them writes nil). }
procedure AddWriterReasons(const pEvents: THbEvents; var pAnswer: THbAnswer);
begin
  var AnyCounting:= False;
  var AnySoft:= pEvents.IsPublished or pEvents.AbsoluteOverlay;
  var AnyNil:= False;
  for var W in pEvents.Writers do
  begin
    if W.Counts then AnyCounting:= True
    else if W.How in [hwUnresolved, hwWithOpaque, hwAddressOf, hwDfmStream] then AnySoft:= True;
    if W.How = hwAssignNil then AnyNil:= True;
  end;
  var NilOnly:= not AnyCounting and not (AnySoft and not AnyNil);
  for var I:= 0 to High(pAnswer.JudgedUses) do
  begin
    if pAnswer.JudgedUses[I].Verdict <> hvMayBeUnset then Continue;
    if AnySoft then AddReason(pAnswer.JudgedUses[I].Reasons, hrSoftWriter);
    if NilOnly then AddReason(pAnswer.JudgedUses[I].Reasons, hrNilWriteOnly);
    pAnswer.JudgedUses[I].Reasons:= SortedReasons(pAnswer.JudgedUses[I].Reasons);
  end;
end;

function CheckInit(const pDbPath, pTarget, pAt: string; const pOptions: THbOptions): THbAnswer;
var
  AtSite: THbSite;
  Blockers: TArray<THbReason>;
  Warnings: TArray<string>;
begin
  Result:= Default(THbAnswer);
  AtSite:= Default(THbSite);
  if (pAt <> '') and not HbParseAt(pAt, AtSite) then
    raise EHbUsage.CreateCandidates(Format('--at must be <file>:<line>[:<col>], got "%s"', [pAt]), nil);
  var Watch:= TStopwatch.StartNew;
  var MaxR:= if pOptions.MaxRoutines > 0 then pOptions.MaxRoutines else HB_DEFAULT_MAX_ROUTINES;
  var Index:= TChartsIndex.Create(pDbPath);
  try
    var Store: ISymbolStore:= TSQLiteSymbolStore.Create(pDbPath, {AReadOnly=}True);
    var Events:= CollectEvents(Index, pTarget, AtSite);
    PlaceMainBlockSites(Index, Events);
    ApplyCalleeMarkers(Index, Events, Warnings);
    Result.Target:= Events.Target;
    Result.Writers:= Events.Writers;
    Result.Scope:= if Events.Target.Kind = htkInstanceField then hsInstance else hsProgram;
    if Events.Target.Kind = htkInstanceField then
    begin
      { spec 5.5: the constructor model (lane HBFIELDS) }
      Result:= CheckInstanceField(Index, Store, Events, MaxR);
      { the answer's writers include the writes through another object the events lane read as uses }
      Events.Writers:= Result.Writers;
      AddWriterReasons(Events, Result);
    end
    else if HbIsNeverSet(Events, Blockers) then
    begin
      Result.Verdict:= hvNeverSet;
      Result.Proven:= True;
      Result.Summary:= 'no resolved writer, no soft writer, not published, no absolute overlay';
      AnswerEveryUse(Result, Events, hvNeverSet, 'nothing ever writes it');
    end
    else
    begin
      var Solver:= TSolver.Create(Index, Store, MaxR, Events);
      try
        Solver.Run(Result);
      finally
        Solver.Free;
      end;
      AddWriterReasons(Events, Result);
      Result.Proven:= Result.Verdict = hvSet;
      Result.Summary:= if Result.Verdict = hvSet then '(proven: every judged use runs after a counting writer)'
        else '(not proven)';
    end;
    if Warnings <> nil then
    begin
      Result.Limits:= Result.Limits + [HB_LIMIT_UNKNOWN_CALLEE];
      if Result.Verdict <> hvSet then
      begin
        Result.Summary:= 'UNKNOWN-CALLEE: ' + string.Join('; ', Warnings);
        Result.Proven:= False;
      end;
    end;
    Result.Reasons:= SortedReasons(Result.Reasons);
  finally
    Index.Free;
  end;
  Result.Budget.Ms:= Watch.ElapsedMilliseconds;
end;

end.
