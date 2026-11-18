unit DRagLint.Query.HappensBefore.Fields;

{ drag-lint 1.52 -- lane HBFIELDS: instance fields by the constructor model.

  Spec docs\superpowers\specs\2026-11-17-happens-before-design.md sec. 5.5 (amended by rulings HB2 / HB4),
  plan docs\superpowers\plans\2026-11-17-happens-before-phase1.md lane FIELDS; acceptance
  tests\autotest\run_check_init_fields.ps1 over tests\fixtures\happens-before\fields-*.

  For an instance field F of class C the proof is per instance, by construction:
    * MustF(r) = "every normal completion of method r has written F through Self": a LEAST fixpoint
      (start False) of SolveRoutine's exit bit over the methods of C and of its descendants. A MARK is a
      counting writer of F whose receiver is Self (no receiver ref, or the ref `Self`), or a certain call
      on Self (no receiver: `Prepare`, `inherited Create`, a sibling constructor; or `Self.Prepare`)
      whose callee set (the callee unless abstract, plus every override) is all MustF.
    * Every constructor DECLARED in C must have MustF (else ctor-misses-field); C must declare one (else
      no-declared-ctor); a C constructor marked `overload` leaves an inherited constructor callable on C
      (ctor-misses-field); every constructor declared in a descendant must have MustF, i.e. chain to a
      C constructor that does (else subclass-ctor-skips); a bare `Self` (not a receiver) in a
      constructor before the write hands the object out unfinished (self-escapes-in-ctor).
    * A use inside a constructor of C or a descendant is judged by the state before it (entry False).
      Any other use is judged against the class-level blockers above and, walking its callers backward
      (call edges plus dispatch fan-in), against a constructor call site that runs BEFORE the write
      (writer-after-use-same-routine) or an ANCESTOR constructor that reaches it through a virtual
      call (virtual-call-in-ancestor-ctor); such a use is still SET when its own routine writes F
      before it. A use in a destructor is MAY (writer-conditional: the destructor also runs when a
      constructor raised before the write) unless it is the nil-safe `F.Free`.
  NEVER-SET: HbIsNeverSet of the events after adding the writes through another object
  (`Other.F := ..`, which the events lane reads as a use). The limits line always holds
  instance-by-constructors and names every assign-nil writer (use-after-free-not-judged <file>:<line>).

  Read-only; nothing is persisted (no extractor change). Every doubt answers MAY-BE-UNSET. }

interface

uses
  DRagLint.Core.Interfaces
, DRagLint.Charts.Index
, DRagLint.Query.HappensBefore.Types
, DRagLint.Query.HappensBefore.Events
  ;

const
  /// <summary>Limit code on every instance-field answer: the proof is per instance and by constructors
  /// only (spec 5.5); order between later method calls on the same object is lane HBRECV's.</summary>
  HB_LIMIT_BY_CONSTRUCTORS = 'instance-by-constructors';

  /// <summary>Limit code prefix naming one assign-nil writer of the field: `use-after-free-not-judged
  /// <file>:<line>` (a later `F := nil` / FreeAndNil is not judged; use-after-free is phase 4).</summary>
  HB_LIMIT_USE_AFTER_FREE = 'use-after-free-not-judged';

/// <summary>Answers check-init for one instance field by the constructor model (spec 5.5).</summary>
/// <param name="pIndex">Open index of the project; caller owns it.</param>
/// <param name="pStore">Read-only store over the same DB (SolveRoutine parses through it).</param>
/// <param name="pEvents">CollectEvents' result for an htkInstanceField target, main-block sites placed;
/// must not describe another target kind.</param>
/// <param name="pMaxRoutines">Most routines solved (CFGs built) by this query; &gt;= 1.</param>
/// <returns>A complete answer with Scope = instance: Target and Writers (the events' writers plus the
/// writes through another object), a verdict per use, the headline (worst non-guarded use; the
/// constructor proof when no use exists), Summary (for MAY: every writer routine and whether every
/// constructor calls it), Reasons (budget), Limits, Budget.Routines / Exhausted. Budget.Ms is the
/// caller's.</returns>
/// <remarks>Read-only. Not thread-safe (the shared parse cache). Deterministic: ids, sites and callers
/// are walked in sorted order. SET is a proof under spec 6.1; every unproven link answers
/// MAY-BE-UNSET with a reason code of spec 6.4 and a witness (blocking constructor or class first,
/// then the use).</remarks>
function CheckInstanceField(const pIndex: TChartsIndex; const pStore: ISymbolStore; const pEvents: THbEvents;
  pMaxRoutines: Integer): THbAnswer;

implementation

uses
  System.SysUtils
, System.Generics.Collections
, System.Generics.Defaults
, DRagLint.Query.HappensBefore.Intra
  ;

type
  TRows = TObjectList<TIndexRow>;

  /// <summary>One call site with its receiver: OnSelf when the call has no receiver ref or the
  /// receiver is `Self`.</summary>
  TFieldCall = record
    CallerId: Int64;
    CalleeId: Int64;
    FilePath: string;
    Line: Integer;
    Col: Integer;
    Certain: Boolean;
    OnSelf: Boolean;
  end;

  /// <summary>A method of C, of a descendant or of an ancestor.</summary>
  TFieldMethod = record
    Id: Int64;
    Kind: string;
    QName: string;
    ClassId: Int64;
    FilePath: string;
    Line: Integer;
    IsAbstract: Boolean;
    IsOverload: Boolean;
    IsClassMethod: Boolean;
  end;

  /// <summary>Why the constructor proof fails for every use outside a constructor.</summary>
  TFieldBlocker = record
    Reason: THbReason;
    Hop: THbHop;
    Why: string;
  end;

  /// <summary>What the backward walk from a use's routine found.</summary>
  TReachHit = record
    Found: Boolean;
    Reason: THbReason;
    Hop: THbHop;
    Why: string;
  end;

  /// <summary>One CheckInstanceField call: holds the index caches and the fixpoint.</summary>
  TFieldSolver = class  // dl:ok god-class@282c, high-response@282c -- REVIEWED 2026-11-17 v152 HBFIELDS: one query = one object holding the class family, the call caches and the MustF fixpoint; its methods are the steps of spec 5.5, covered by 20 fields cases
  strict private
    FIndex: TChartsIndex;
    FStore: ISymbolStore;
    FEvents: THbEvents;
    FMax: Integer;
    FFieldName: string;
    FClassId: Int64;
    FClassQName: string;
    FClassFile: string;
    FClassLine: Integer;
    FFamily: THashSet<Int64>;
    FAncestors: THashSet<Int64>;
    FDescendants: TArray<Int64>;
    FMethods: TDictionary<Int64, TFieldMethod>;
    FCalls: TDictionary<Int64, TArray<TFieldCall>>;
    FCallers: TDictionary<Int64, TArray<TFieldCall>>;
    FBases: TDictionary<Int64, TArray<Int64>>;
    FOverrides: TDictionary<Int64, TArray<Int64>>;
    FSelfWrites: TDictionary<Int64, TArray<THbSite>>;
    FSelfRefs: TDictionary<Int64, TArray<THbSite>>;
    FUses: TArray<THbUse>;
    FMustF: THashSet<Int64>;
    FMustFinal: Boolean;
    FStates: TDictionary<Int64, THbRoutineState>;
    FSolved: THashSet<Int64>;
    FExhausted: Boolean;
    function Rows(const pSql: string): TRows;
    function IdClosure(pStart: Int64; const pSqlFmt: string): TArray<Int64>;
    procedure LoadFamily;
    procedure LoadMethods;
    procedure LoadWrites(var pAnswer: THbAnswer);
    function ReadCalls(const pWhere: string): TArray<TFieldCall>;
    function CallsIn(pId: Int64): TArray<TFieldCall>;
    function CallersOf(pId: Int64): TArray<TFieldCall>;
    function BasesOf(pId: Int64): TArray<Int64>;
    function OverridesOf(pId: Int64): TArray<Int64>;
    function SelfRefsIn(pId: Int64): TArray<THbSite>;
    function MarksOf(pId: Int64): TArray<THbSite>;
    function QueriesOf(pId: Int64): TArray<THbSite>;
    function Solve(pId: Int64): THbRoutineState;
    function DoneAt(const pState: THbRoutineState; pLine, pCol: Integer): Boolean;
    procedure ComputeMustF;
    function IsMethodKind(const pKind: string): Boolean;
    function IsCtorOf(pId: Int64; pFamilyOnly: Boolean): Boolean;
    function CtorsOf(pClassId: Int64): TArray<Int64>;
    function MethodHop(pId: Int64; pLine, pCol: Integer; const pNote: string): THbHop;
    function ClassBlockers: TArray<TFieldBlocker>;
    function ReachBeforeWrite(const pUse: THbUse): TReachHit;
    function IsNilSafeFree(const pUse: THbUse): Boolean;
    function WriterRoutineNote: string;
  public
    constructor Create(const pIndex: TChartsIndex; const pStore: ISymbolStore; const pEvents: THbEvents;
      pMax: Integer);
    destructor Destroy; override;
    /// <summary>Fills pAnswer (whose Target and Writers the caller set) with the verdicts.</summary>
    procedure Run(var pAnswer: THbAnswer);
  end;

const
  KIND_CTOR = 'constructor';
  KIND_DTOR = 'destructor';
  RECEIVER_SELF = 'self';
  NAME_FREE = 'free';
  WHY_PREFIX = 'why not SET: ';
  { what a backward caller walk may visit, as a multiple of --max-routines }
  WALK_FACTOR = 4;

function Id64(const pRow: TIndexRow; const pCol: string): Int64;
begin
  Result:= StrToInt64Def(pRow.S(pCol), 0);
end;

function IdList(const pIds: TArray<Int64>): string;
begin
  Result:= '';
  for var I in pIds do Result:= Result + (if Result = '' then '' else ',') + IntToStr(I);
  if Result = '' then Result:= '0';
end;

function SiteOf(const pPath: string; pLine, pCol: Integer): THbSite;
begin
  Result:= Default(THbSite);
  Result.FileName:= pPath;
  Result.Line:= pLine;
  Result.Col:= pCol;
end;

function SameSite(const pA, pB: THbSite): Boolean;
begin
  Result:= (pA.Line = pB.Line) and (pA.Col = pB.Col) and SameText(pA.FileName, pB.FileName);
end;

procedure AddReason(var pList: TArray<THbReason>; pReason: THbReason);
begin
  for var R in pList do
    if R = pReason then Exit;
  pList:= pList + [pReason];
end;

function SortedReasons(const pList: TArray<THbReason>): TArray<THbReason>;
begin
  Result:= Copy(pList);
  TArray.Sort<THbReason>(Result, TComparer<THbReason>.Construct(
    function(const pL, pR: THbReason): Integer
    begin
      Result:= Ord(pL) - Ord(pR);
    end));
end;

function LastPart(const pQName: string): string;
begin
  Result:= Copy(pQName, LastDelimiter('.', pQName) + 1, MaxInt);
end;

{ ---------------------------------------------------------------------------------------------- }
{ TFieldSolver                                                                                    }

constructor TFieldSolver.Create(const pIndex: TChartsIndex; const pStore: ISymbolStore; const pEvents: THbEvents;
  pMax: Integer);
begin
  inherited Create;
  FIndex:= pIndex;
  FStore:= pStore;
  FEvents:= pEvents;
  FMax:= pMax;
  FFieldName:= LastPart(pEvents.Target.QName);
  FFamily:= THashSet<Int64>.Create;
  FAncestors:= THashSet<Int64>.Create;
  FMethods:= TDictionary<Int64, TFieldMethod>.Create;
  FCalls:= TDictionary<Int64, TArray<TFieldCall>>.Create;
  FCallers:= TDictionary<Int64, TArray<TFieldCall>>.Create;
  FBases:= TDictionary<Int64, TArray<Int64>>.Create;
  FOverrides:= TDictionary<Int64, TArray<Int64>>.Create;
  FSelfWrites:= TDictionary<Int64, TArray<THbSite>>.Create;
  FSelfRefs:= TDictionary<Int64, TArray<THbSite>>.Create;
  FMustF:= THashSet<Int64>.Create;
  FStates:= TDictionary<Int64, THbRoutineState>.Create;
  FSolved:= THashSet<Int64>.Create;
end;

destructor TFieldSolver.Destroy;
begin
  FSolved.Free;
  FStates.Free;
  FMustF.Free;
  FSelfRefs.Free;
  FSelfWrites.Free;
  FOverrides.Free;
  FBases.Free;
  FCallers.Free;
  FCalls.Free;
  FMethods.Free;
  FAncestors.Free;
  FFamily.Free;
  inherited;
end;

function TFieldSolver.Rows(const pSql: string): TRows;
begin
  Result:= FIndex.Query(pSql);
end;

{ The transitive closure of one id relation from pStart, sorted, pStart left out. pSqlFmt selects the next
  ids as column x and takes the current id as its one %d (ids only: no text reaches the SQL). }
function TFieldSolver.IdClosure(pStart: Int64; const pSqlFmt: string): TArray<Int64>;
begin
  Result:= nil;
  var Seen:= THashSet<Int64>.Create;
  try
    var Work:= [pStart];
    while Work <> nil do
    begin
      var Cur:= Work[High(Work)];
      SetLength(Work, Length(Work) - 1);
      var R:= Rows(Format(pSqlFmt, [Cur]));
      try
        for var Row in R do
        begin
          var X:= Id64(Row, 'x');
          if (X <> 0) and (X <> pStart) and Seen.Add(X) then
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

procedure TFieldSolver.LoadFamily;
begin
  var R:= Rows('SELECT c.id, c.qualified_name AS q, c.start_line AS ln, f.path FROM symbols s ' +
    'JOIN symbols c ON c.id = s.parent_id JOIN files f ON f.id = c.file_id WHERE s.id = ' +
    IntToStr(FEvents.Target.SymbolId));
  try
    if R.Count > 0 then
    begin
      FClassId:= Id64(R[0], 'id');
      FClassQName:= R[0].S('q');
      FClassLine:= R[0].I('ln');
      FClassFile:= R[0].S('path');
    end;
  finally
    R.Free;
  end;
  if FClassId = 0 then Exit;
  FFamily.Add(FClassId);
  FDescendants:= IdClosure(FClassId, 'SELECT symbol_id AS x FROM type_ancestors WHERE ancestor_symbol_id = %d ' +
    'AND ancestor_kind = ''class'' ORDER BY symbol_id');
  for var D in FDescendants do FFamily.Add(D);
  for var A in IdClosure(FClassId, 'SELECT ancestor_symbol_id AS x FROM type_ancestors WHERE symbol_id = %d ' +
    'AND ancestor_kind = ''class'' AND ancestor_symbol_id IS NOT NULL ORDER BY ancestor_symbol_id') do
    FAncestors.Add(A);
end;

function TFieldSolver.IsMethodKind(const pKind: string): Boolean;
begin
  Result:= (pKind = KIND_CTOR) or (pKind = KIND_DTOR) or (pKind = 'method') or (pKind = 'procedure') or
    (pKind = 'function');
end;

procedure TFieldSolver.LoadMethods;
begin
  var Owners:= FFamily.ToArray + FAncestors.ToArray;
  var R:= Rows('SELECT s.id, s.kind, s.qualified_name AS q, s.parent_id AS pid, f.path, s.start_line AS ln, ' +
    'COALESCE(s.impl_start_line, 0) AS isl, LOWER(COALESCE(s.directives, '''')) AS dir, ' +
    'COALESCE(s.is_class_method, 0) AS cm FROM symbols s JOIN files f ON f.id = s.file_id ' +
    'WHERE s.parent_id IN (' + IdList(Owners) + ') ORDER BY s.id');
  try
    for var Row in R do
    begin
      if not IsMethodKind(Row.S('kind')) then Continue;
      var M:= Default(TFieldMethod);
      M.Id:= Id64(Row, 'id');
      M.Kind:= Row.S('kind');
      M.QName:= Row.S('q');
      M.ClassId:= Id64(Row, 'pid');
      M.FilePath:= Row.S('path');
      M.Line:= if Row.I('isl') > 0 then Row.I('isl') else Row.I('ln');
      M.IsAbstract:= Row.S('dir').Contains('abstract');
      M.IsOverload:= Row.S('dir').Contains('overload');
      M.IsClassMethod:= Row.I('cm') <> 0;
      FMethods.Add(M.Id, M);
    end;
  finally
    R.Free;
  end;
end;

{ Self writes per routine; writes through another object become writer rows (the events lane reads
  `Other.F := ..` as a use) and leave the use list. }
procedure TFieldSolver.LoadWrites(var pAnswer: THbAnswer);
begin
  var Foreign:= TList<THbSite>.Create;
  try
    var R:= Rows('SELECT f.path, r.start_line AS ln, r.start_col AS col, r.kind AS rk, ' +
      'COALESCE(r.enclosing_symbol_id, 0) AS enc, COALESCE(e.qualified_name, '''') AS encq, ' +
      'COALESCE(m.mode, '''') AS mode FROM refs r JOIN files f ON f.id = r.file_id ' +
      'JOIN ref_receivers rr ON rr.ref_id = r.id JOIN refs rv ON rv.id = rr.receiver_ref_id ' +
      'LEFT JOIN symbols e ON e.id = r.enclosing_symbol_id ' +
      'LEFT JOIN member_accesses m ON m.ref_id = r.id AND m.member_symbol_id = r.symbol_id ' +
      'WHERE r.symbol_id = ' + IntToStr(FEvents.Target.SymbolId) + ' AND LOWER(rv.name_text) <> ''' +
      RECEIVER_SELF + ''' ORDER BY f.path, r.start_line, r.start_col, r.id');
    try
      for var Row in R do
      begin
        var S:= SiteOf(Row.S('path'), Row.I('ln'), Row.I('col'));
        S.RoutineId:= Id64(Row, 'enc');
        S.Routine:= Row.S('encq');
        Foreign.Add(S);
        if (Row.S('rk') <> 'member-access') or (Row.S('mode') <> 'write') then Continue;
        var Known:= False;
        for var W in pAnswer.Writers do
          if SameSite(W.Site, S) then Known:= True;
        if Known then Continue;
        var W:= Default(THbWriter);
        W.Site:= S;
        W.How:= hwAssign;
        W.Resolved:= True;
        W.Counts:= True;
        pAnswer.Writers:= pAnswer.Writers + [W];
        var Keep: TArray<THbUse>:= nil;
        for var U in FEvents.UseSites do
          if not SameSite(U.Site, S) then Keep:= Keep + [U];
        FEvents.UseSites:= Keep;
      end;
    finally
      R.Free;
    end;
    FEvents.Writers:= pAnswer.Writers;
    FUses:= FEvents.UseSites;
    for var W in FEvents.Writers do
    begin
      if not (W.Counts and W.Resolved and (W.How in [hwAssign, hwCreateInto, hwVarArg, hwOutArg])) then Continue;
      if not FMethods.ContainsKey(W.Site.RoutineId) then Continue;
      if not FFamily.Contains(FMethods[W.Site.RoutineId].ClassId) then Continue;
      var IsForeign:= False;
      for var F in Foreign do
        if SameSite(F, W.Site) then IsForeign:= True;
      if IsForeign then Continue;
      var L: TArray<THbSite>;
      if not FSelfWrites.TryGetValue(W.Site.RoutineId, L) then L:= nil;
      FSelfWrites.AddOrSetValue(W.Site.RoutineId, L + [SiteOf(W.Site.FileName, W.Site.Line, W.Site.Col)]);
    end;
  finally
    Foreign.Free;
  end;
end;

function TFieldSolver.ReadCalls(const pWhere: string): TArray<TFieldCall>;
begin
  Result:= nil;
  var R:= Rows('SELECT COALESCE(r.enclosing_symbol_id, (SELECT p.id FROM symbols p WHERE p.file_id = r.file_id ' +
    'AND p.kind IN (''program'', ''library'') ORDER BY p.id LIMIT 1), 0) AS caller, c.target_symbol_id AS callee, ' +
    'f.path, r.start_line AS ln, r.start_col AS col, c.confidence AS conf, ' +
    'COALESCE((SELECT LOWER(rv.name_text) FROM ref_receivers rr JOIN refs rv ON rv.id = rr.receiver_ref_id ' +
    'WHERE rr.ref_id = r.id ORDER BY rv.id LIMIT 1), '''') AS rcv, ' +
    '(SELECT COUNT(*) FROM ref_receivers rr WHERE rr.ref_id = r.id) AS nrcv ' +
    'FROM refs r JOIN call_edges c ON c.ref_id = r.id JOIN files f ON f.id = r.file_id WHERE ' + pWhere +
    ' ORDER BY f.path, r.start_line, r.start_col, r.id');
  try
    for var Row in R do
    begin
      var C:= Default(TFieldCall);
      C.CallerId:= Id64(Row, 'caller');
      C.CalleeId:= Id64(Row, 'callee');
      C.FilePath:= Row.S('path');
      C.Line:= Row.I('ln');
      C.Col:= Row.I('col');
      C.Certain:= Row.S('conf') = 'certain';
      C.OnSelf:= (Row.I('nrcv') = 0) or (Row.S('rcv') = RECEIVER_SELF);
      Result:= Result + [C];
    end;
  finally
    R.Free;
  end;
end;

function TFieldSolver.CallsIn(pId: Int64): TArray<TFieldCall>;
begin
  if FCalls.TryGetValue(pId, Result) then Exit;
  Result:= ReadCalls(Format('r.enclosing_symbol_id = %d', [pId]));
  FCalls.Add(pId, Result);
end;

function TFieldSolver.BasesOf(pId: Int64): TArray<Int64>;
begin
  if FBases.TryGetValue(pId, Result) then Exit;
  Result:= IdClosure(pId, 'SELECT base_symbol_id AS x FROM dispatch_edges WHERE impl_symbol_id = %d ' +
    'ORDER BY base_symbol_id');
  FBases.Add(pId, Result);
end;

function TFieldSolver.OverridesOf(pId: Int64): TArray<Int64>;
begin
  if FOverrides.TryGetValue(pId, Result) then Exit;
  Result:= IdClosure(pId, 'SELECT impl_symbol_id AS x FROM dispatch_edges WHERE kind = ''override'' ' +
    'AND base_symbol_id = %d ORDER BY impl_symbol_id');
  FOverrides.Add(pId, Result);
end;

function TFieldSolver.CallersOf(pId: Int64): TArray<TFieldCall>;
begin
  if FCallers.TryGetValue(pId, Result) then Exit;
  Result:= ReadCalls('c.target_symbol_id IN (' + IdList([pId] + BasesOf(pId)) + ')');
  FCallers.Add(pId, Result);
end;

{ Every bare `Self` in pId: a Self ref that is not the receiver of another ref (handed out, compared,
  stored). }
function TFieldSolver.SelfRefsIn(pId: Int64): TArray<THbSite>;
begin
  if FSelfRefs.TryGetValue(pId, Result) then Exit;
  Result:= nil;
  var R:= Rows('SELECT f.path, r.start_line AS ln, r.start_col AS col FROM refs r JOIN files f ON f.id = r.file_id ' +
    'WHERE r.enclosing_symbol_id = ' + IntToStr(pId) + ' AND LOWER(r.name_text) = ''' + RECEIVER_SELF + ''' ' +
    'AND NOT EXISTS (SELECT 1 FROM ref_receivers x WHERE x.receiver_ref_id = r.id) ' +
    'ORDER BY r.start_line, r.start_col, r.id');
  try
    for var Row in R do Result:= Result + [SiteOf(Row.S('path'), Row.I('ln'), Row.I('col'))];
  finally
    R.Free;
  end;
  FSelfRefs.Add(pId, Result);
end;

function TFieldSolver.MarksOf(pId: Int64): TArray<THbSite>;
begin
  if not FSelfWrites.TryGetValue(pId, Result) then Result:= nil;
  for var C in CallsIn(pId) do
  begin
    if not (C.Certain and C.OnSelf) then Continue;
    var M: TFieldMethod;
    var Callees: TArray<Int64>:= nil;
    if not (FMethods.TryGetValue(C.CalleeId, M) and M.IsAbstract) then Callees:= [C.CalleeId];
    Callees:= Callees + OverridesOf(C.CalleeId);
    var All:= Callees <> nil;
    for var X in Callees do
      if not FMustF.Contains(X) then All:= False;
    if All then Result:= Result + [SiteOf(C.FilePath, C.Line, C.Col)];
  end;
end;

function TFieldSolver.QueriesOf(pId: Int64): TArray<THbSite>;
begin
  Result:= nil;
  for var C in CallsIn(pId) do Result:= Result + [SiteOf(C.FilePath, C.Line, C.Col)];
  for var U in FUses do
    if U.Site.RoutineId = pId then Result:= Result + [SiteOf(U.Site.FileName, U.Site.Line, U.Site.Col)];
  Result:= Result + SelfRefsIn(pId);
end;

{ SolveRoutine with entry False (no routine is entered with F proven set); cached once MustF is final.
  A routine beyond the --max-routines budget answers Found = False. }
function TFieldSolver.Solve(pId: Int64): THbRoutineState;
begin
  if FMustFinal and FStates.TryGetValue(pId, Result) then Exit;
  Result:= Default(THbRoutineState);
  Result.RoutineId:= pId;
  if not FSolved.Contains(pId) then
  begin
    if FSolved.Count >= FMax then
    begin
      FExhausted:= True;
      Exit;
    end;
    FSolved.Add(pId);
  end;
  Result:= SolveRoutine(FStore, pId, MarksOf(pId), QueriesOf(pId), False);
  if FMustFinal then FStates.Add(pId, Result);
end;

function TFieldSolver.DoneAt(const pState: THbRoutineState; pLine, pCol: Integer): Boolean;
begin
  Result:= False;
  for var Q in pState.Queries do
    if (Q.Site.Line = pLine) and (Q.Site.Col = pCol) then Exit(Q.Done);
end;

procedure TFieldSolver.ComputeMustF;
begin
  { least fixpoint over the instance methods of C and its descendants, in id order }
  var Ids:= FMethods.Keys.ToArray;
  TArray.Sort<Int64>(Ids);
  var Changed:= True;
  while Changed and not FExhausted do
  begin
    Changed:= False;
    for var Id in Ids do
    begin
      var M:= FMethods[Id];
      if M.IsClassMethod or not FFamily.Contains(M.ClassId) or FMustF.Contains(Id) then Continue;
      var St:= Solve(Id);
      if St.Found and St.ExitDone then
      begin
        FMustF.Add(Id);
        Changed:= True;
      end;
    end;
  end;
  FMustFinal:= True;
end;

function TFieldSolver.IsCtorOf(pId: Int64; pFamilyOnly: Boolean): Boolean;
var
  M: TFieldMethod;
begin
  var IsCtor:= FMethods.TryGetValue(pId, M) and (M.Kind = KIND_CTOR) and not M.IsClassMethod;
  var InScope:= FFamily.Contains(M.ClassId) or ((not pFamilyOnly) and FAncestors.Contains(M.ClassId));
  Result:= IsCtor and InScope;
end;

function TFieldSolver.CtorsOf(pClassId: Int64): TArray<Int64>;
begin
  Result:= nil;
  for var M in FMethods.Values do
    if (M.ClassId = pClassId) and (M.Kind = KIND_CTOR) and not M.IsClassMethod then Result:= Result + [M.Id];
  TArray.Sort<Int64>(Result);
end;

function TFieldSolver.MethodHop(pId: Int64; pLine, pCol: Integer; const pNote: string): THbHop;
var
  M: TFieldMethod;
begin
  Result:= Default(THbHop);
  if FMethods.TryGetValue(pId, M) then
  begin
    Result.Routine:= M.QName;
    Result.FileName:= M.FilePath;
    Result.Line:= M.Line;
  end;
  if pLine > 0 then
  begin
    Result.Line:= pLine;
    Result.Col:= pCol;
  end;
  Result.Note:= pNote;
end;

{ The blockers that hold for every use outside a constructor (spec 5.5), in reason-code order. }
function TFieldSolver.ClassBlockers: TArray<TFieldBlocker>;

  procedure Add(pReason: THbReason; const pHop: THbHop; const pWhy: string);
  begin
    var B:= Default(TFieldBlocker);
    B.Reason:= pReason;
    B.Hop:= pHop;
    B.Why:= pWhy;
    Result:= Result + [B];
  end;

begin
  Result:= nil;
  var Ctors:= CtorsOf(FClassId);
  for var K in Ctors do
  begin
    var St:= Solve(K);
    if not (St.Found and St.ExitDone) then
      Add(hrCtorMissesField, MethodHop(K, 0, 0, 'does not set ' + FFieldName + ' on every path'),
        FMethods[K].QName + ' does not set ' + FFieldName + ' on every path');
  end;
  for var K in Ctors do
    if FMethods[K].IsOverload then
    begin
      Add(hrCtorMissesField, MethodHop(K, 0, 0, 'declared overload: an inherited constructor stays callable'),
        FMethods[K].QName + ' is declared overload: an inherited constructor stays callable and does not set ' +
        FFieldName);
      Break;
    end;
  if Ctors = nil then
  begin
    var H:= Default(THbHop);
    H.Routine:= FClassQName;
    H.FileName:= FClassFile;
    H.Line:= FClassLine;
    H.Note:= 'declares no constructor';
    Add(hrNoDeclaredCtor, H, FClassQName + ' declares no constructor');
  end;
  for var D in FDescendants do
    for var K in CtorsOf(D) do
    begin
      var St:= Solve(K);
      if not (St.Found and St.ExitDone) then
        Add(hrSubclassCtorSkips, MethodHop(K, 0, 0, 'does not chain to a constructor that sets ' + FFieldName),
          FMethods[K].QName + ' does not chain to a constructor that sets ' + FFieldName);
    end;
  var AllCtors:= TList<Int64>.Create;
  try
    AllCtors.AddRange(Ctors);
    for var D in FDescendants do AllCtors.AddRange(CtorsOf(D));
    for var K in AllCtors do
      for var S in SelfRefsIn(K) do
        if not DoneAt(Solve(K), S.Line, S.Col) then
        begin
          Add(hrSelfEscapesInCtor, MethodHop(K, S.Line, S.Col, 'hands Self out before it sets ' + FFieldName),
            FMethods[K].QName + ' hands Self out before it sets ' + FFieldName);
          Break;
        end;
  finally
    AllCtors.Free;
  end;
  TArray.Sort<TFieldBlocker>(Result, TComparer<TFieldBlocker>.Construct(
    function(const pL, pR: TFieldBlocker): Integer
    begin
      Result:= Ord(pL.Reason) - Ord(pR.Reason);
    end));
end;

{ Walks the callers of the use's routine backward (call edges plus dispatch fan-in) to the constructors:
  a family constructor call site that runs before the write, or an ancestor constructor. }
function TFieldSolver.ReachBeforeWrite(const pUse: THbUse): TReachHit;
begin
  Result:= Default(TReachHit);
  var Seen:= THashSet<Int64>.Create;
  try
    var Work:= TQueue<Int64>.Create;
    try
      Work.Enqueue(pUse.Site.RoutineId);
      Seen.Add(pUse.Site.RoutineId);
      while Work.Count > 0 do
      begin
        var Cur:= Work.Dequeue;
        for var C in CallersOf(Cur) do
        begin
          if C.CallerId = 0 then Continue;
          if IsCtorOf(C.CallerId, True) then
          begin
            if DoneAt(Solve(C.CallerId), C.Line, C.Col) then Continue;
            Result.Found:= True;
            Result.Reason:= hrWriterAfterUseSameRoutine;
            Result.Hop:= MethodHop(C.CallerId, C.Line, C.Col, 'calls before it sets ' + FFieldName);
            Result.Why:= 'reached from ' + FMethods[C.CallerId].QName + Format(' (line %d)', [C.Line]) +
              ' before it sets ' + FFieldName;
            Exit;
          end;
          if IsCtorOf(C.CallerId, False) then
          begin
            Result.Found:= True;
            Result.Reason:= hrVirtualCallInAncestorCtor;
            Result.Hop:= MethodHop(C.CallerId, C.Line, C.Col, 'ancestor constructor runs before ' + FFieldName +
              ' is set');
            Result.Why:= 'reached from the ancestor constructor ' + FMethods[C.CallerId].QName +
              Format(' (line %d)', [C.Line]) + ' before ' + FFieldName + ' is set';
            Exit;
          end;
          if Seen.Add(C.CallerId) then
          begin
            if Seen.Count > FMax * WALK_FACTOR then
            begin
              FExhausted:= True;
              Exit;
            end;
            Work.Enqueue(C.CallerId);
          end;
        end;
      end;
    finally
      Work.Free;
    end;
  finally
    Seen.Free;
  end;
end;

{ `F.Free` (TObject.Free tests for nil): the use is the receiver of a `Free` ref. }
function TFieldSolver.IsNilSafeFree(const pUse: THbUse): Boolean;
begin
  var R:= Rows('SELECT COUNT(*) AS n FROM refs u JOIN files f ON f.id = u.file_id ' +
    'JOIN ref_receivers rr ON rr.receiver_ref_id = u.id JOIN refs m ON m.id = rr.ref_id ' +
    'WHERE u.symbol_id = ' + IntToStr(FEvents.Target.SymbolId) + ' AND f.path = ''' +
    TChartsIndex.SqlText(pUse.Site.FileName) + ''' AND u.start_line = ' + IntToStr(pUse.Site.Line) +
    ' AND u.start_col = ' + IntToStr(pUse.Site.Col) + ' AND LOWER(m.name_text) = ''' + NAME_FREE + '''');
  try
    Result:= (R.Count > 0) and (R[0].I('n') > 0);
  finally
    R.Free;
  end;
end;

{ 'writer routines: X (called by every constructor), Y (not called by every constructor)' over the
  routines that write F through Self. "Called" = reached from the constructor over call edges. }
function TFieldSolver.WriterRoutineNote: string;
begin
  Result:= '';
  var Ctors:= CtorsOf(FClassId);
  var Ids:= FSelfWrites.Keys.ToArray;
  TArray.Sort<Int64>(Ids);
  for var W in Ids do
  begin
    var Text: string;
    if IsCtorOf(W, True) then Text:= FMethods[W].QName + ' (constructor)'
    else
    begin
      var Reached:= THashSet<Int64>.Create;
      try
        var Work:= [W];
        Reached.Add(W);
        while (Work <> nil) and (Reached.Count <= FMax * WALK_FACTOR) do
        begin
          var Cur:= Work[High(Work)];
          SetLength(Work, Length(Work) - 1);
          for var C in CallersOf(Cur) do
            if (C.CallerId <> 0) and Reached.Add(C.CallerId) then Work:= Work + [C.CallerId];
        end;
        var Every:= Ctors <> nil;
        for var K in Ctors do
          if not Reached.Contains(K) then Every:= False;
        Text:= FMethods[W].QName + (if Every then ' (called by every constructor)' else
          ' (not called by every constructor)');
      finally
        Reached.Free;
      end;
    end;
    Result:= Result + (if Result = '' then '' else ', ') + Text;
  end;
  if Result <> '' then Result:= 'writer routines: ' + Result;
end;

procedure TFieldSolver.Run(var pAnswer: THbAnswer);
begin
  LoadFamily;
  LoadMethods;
  LoadWrites(pAnswer);
  var Blockers: TArray<THbReason>;
  if HbIsNeverSet(FEvents, Blockers) then
  begin
    pAnswer.Verdict:= hvNeverSet;
    pAnswer.Proven:= True;
    pAnswer.Summary:= 'no resolved writer, no soft writer, not published, no absolute overlay';
    for var U in FUses do
    begin
      var A:= Default(THbUseAnswer);
      A.Site:= U.Site;
      A.Verdict:= hvNeverSet;
      A.Why:= WHY_PREFIX + 'nothing ever writes it';
      if U.GuardedTest then A.Reasons:= [hrGuardedTest];
      pAnswer.JudgedUses:= pAnswer.JudgedUses + [A];
    end;
    Exit;
  end;
  ComputeMustF;
  var ClassB:= ClassBlockers;
  var Headline:= if ClassB <> nil then hvMayBeUnset else hvSet;
  var AnyCounted:= False;
  var UseHeadline:= hvSet;
  for var U in FUses do
  begin
    var A:= Default(THbUseAnswer);
    A.Site:= U.Site;
    var UseHop:= Default(THbHop);
    UseHop.Routine:= U.Site.Routine;
    UseHop.FileName:= U.Site.FileName;
    UseHop.Line:= U.Site.Line;
    UseHop.Col:= U.Site.Col;
    UseHop.Note:= 'reads ' + FFieldName;
    var First: TArray<THbHop>:= nil;
    if IsCtorOf(U.Site.RoutineId, True) then
    begin
      if not DoneAt(Solve(U.Site.RoutineId), U.Site.Line, U.Site.Col) then
      begin
        AddReason(A.Reasons, hrWriterAfterUseSameRoutine);
        A.Why:= WHY_PREFIX + 'the constructor reads ' + FFieldName + ' before it sets it on every path';
        First:= [];
      end;
    end
    else
    begin
      for var B in ClassB do
      begin
        AddReason(A.Reasons, B.Reason);
        if A.Why = '' then
        begin
          A.Why:= WHY_PREFIX + B.Why;
          First:= [B.Hop];
        end;
      end;
      var IsDtor:= FMethods.ContainsKey(U.Site.RoutineId) and (FMethods[U.Site.RoutineId].Kind = KIND_DTOR);
      if IsDtor and not IsNilSafeFree(U) then
      begin
        AddReason(A.Reasons, hrWriterConditional);
        if A.Why = '' then
        begin
          A.Why:= WHY_PREFIX + 'the destructor also runs when a constructor raised before it set ' + FFieldName;
          First:= [];
        end;
      end;
      var Hit:= ReachBeforeWrite(U);
      if Hit.Found and not DoneAt(Solve(U.Site.RoutineId), U.Site.Line, U.Site.Col) then
      begin
        AddReason(A.Reasons, Hit.Reason);
        if A.Why = '' then
        begin
          A.Why:= WHY_PREFIX + Hit.Why;
          First:= [Hit.Hop];
        end;
      end;
    end;
    if FExhausted then
    begin
      AddReason(A.Reasons, hrBudget);
      if A.Why = '' then A.Why:= WHY_PREFIX + 'the --max-routines budget ran out';
    end;
    A.Verdict:= if A.Reasons = nil then hvSet else hvMayBeUnset;
    if A.Verdict <> hvSet then
    begin
      First:= First + [UseHop];
      for var I:= 0 to High(First) do First[I].Step:= I + 1;
      A.Witness:= First;
    end;
    if U.GuardedTest then AddReason(A.Reasons, hrGuardedTest);
    A.Reasons:= SortedReasons(A.Reasons);
    pAnswer.JudgedUses:= pAnswer.JudgedUses + [A];
    if (not U.GuardedTest) or (Length(FUses) = 1) then
    begin
      UseHeadline:= HbWorseVerdict(UseHeadline, A.Verdict);
      AnyCounted:= True;
    end;
  end;
  if AnyCounted then Headline:= UseHeadline
  else if FExhausted then Headline:= hvMayBeUnset;
  pAnswer.Verdict:= Headline;
  pAnswer.Proven:= Headline = hvSet;
  if FExhausted then AddReason(pAnswer.Reasons, hrBudget);
  var NCtors:= Length(CtorsOf(FClassId));
  if Headline = hvSet then
    pAnswer.Summary:= if NCtors = 1 then '(every instance: the constructor sets it before it returns)'
      else Format('(every instance: all %d constructors set it before they return)', [NCtors])
  else
  begin
    var Why:= '';
    for var A in pAnswer.JudgedUses do
      if (A.Verdict = hvMayBeUnset) and (Why = '') then Why:= Copy(A.Why, Length(WHY_PREFIX) + 1, MaxInt);
    if (Why = '') and (ClassB <> nil) then Why:= ClassB[0].Why;
    pAnswer.Summary:= '(not proven: ' + Why + ')';
    var Note:= WriterRoutineNote;
    if Note <> '' then pAnswer.Summary:= pAnswer.Summary + ' ' + Note;
  end;
  pAnswer.Budget.Routines:= FSolved.Count;
  pAnswer.Budget.Exhausted:= FExhausted;
end;

function CheckInstanceField(const pIndex: TChartsIndex; const pStore: ISymbolStore; const pEvents: THbEvents;
  pMaxRoutines: Integer): THbAnswer;
begin
  Result:= Default(THbAnswer);
  Result.Target:= pEvents.Target;
  Result.Writers:= pEvents.Writers;
  Result.Scope:= hsInstance;
  var Solver:= TFieldSolver.Create(pIndex, pStore, pEvents, if pMaxRoutines > 0 then pMaxRoutines
    else HB_DEFAULT_MAX_ROUTINES);
  try
    Solver.Run(Result);
  finally
    Solver.Free;
  end;
  Result.Reasons:= SortedReasons(Result.Reasons);
  Result.Limits:= [HB_LIMIT_BY_CONSTRUCTORS];
  for var W in Result.Writers do
    if W.How = hwAssignNil then
      Result.Limits:= Result.Limits + [Format('%s %s:%d', [HB_LIMIT_USE_AFTER_FREE, ExtractFileName(W.Site.FileName),
        W.Site.Line])];
end;

end.
