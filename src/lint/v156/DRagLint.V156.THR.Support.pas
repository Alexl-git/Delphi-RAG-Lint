unit DRagLint.V156.THR.Support;

{ Wave v156 lane THR-R -- helpers of DRagLint.V156.THR (private to the lane): the analysis behind
  G-05 lock-order-inversion, on the lock sites of DRagLint.Query.LockSites (lane THR-S).

  An ORDER EDGE "A before B" is one place where lock B is taken (a blocking enter) while lock A is held:
    * directly -- the enter of B lies inside a region of A in the same routine;
    * through a call -- a call lies inside a region of A, and the called routine, or a routine it calls
      (LOCK_ORDER_CALL_DEPTH calls deep at most), enters B.
  Two edges "A before B" and "B before A" are an INVERSION: a thread at the first place and a thread at
  the second can wait for each other forever. Both places are reported.

  What keeps the rule silent:
    * a lock that is not Exact (a local, a parameter, a field of another object, a property, an
      expression): its key means nothing outside its own routine;
    * a try-enter, as the second lock (a failed try does not wait) and as the held lock (its region is
      conditional);
    * a second lock that is already held at that place (re-entered, it cannot wait);
    * a lock taken shared (BeginRead) at BOTH places -- readers do not block readers;
    * a common third lock held at both places (a gate): the two orders cannot interleave.
  Limits inherited from the lock sites: source order stands in for control flow, the same class
  instance is assumed for a field lock, a lock inside an anonymous method counts under the routine
  that declares it, `with` receivers are not followed. }

interface

uses
  DRagLint.Core.Interfaces
  , DRagLint.Core.Model
  , DRagLint.Lint.Config
  ;

const
  /// <summary>How many calls deep a lock taken by a called routine is followed (1 = the called routine only).</summary>
  LOCK_ORDER_CALL_DEPTH = 4;

/// <summary>Finds every place where two locks are taken in the opposite order of another place.</summary>
/// <param name="pStore">An open project index; nil or a store that is not SQLite answers nil.</param>
/// <param name="pCfg">The run's lint configuration (severity override of the rule).</param>
/// <param name="pRuleId">Rule id the findings carry.</param>
/// <param name="pSeverity">Default severity of the rule.</param>
/// <returns>One finding per place (the enter of the second lock, or the call that leads to it), by
/// file, line, column; nil when the project has no inversion.</returns>
/// <remarks>Read-only. One scan of the lock sites; call it once per run.</remarks>
function LockOrderInversions(const pStore: ISymbolStore; const pCfg: TLintConfig;
  const pRuleId, pSeverity: string): TArray<TLintFinding>;

implementation

uses
  System.SysUtils
  , System.Generics.Collections
  , System.Generics.Defaults
  , Data.DB
  , FireDAC.Comp.Client
  , DRagLint.Storage.SQLite
  , DRagLint.Query.LockSites
  ;

const
  { A reach that visits more routines than this stops growing: a guard against a pathological call fan-out. }
  REACH_ROUTINE_CAP = 2000;
  { Routine ids per IN (...) list of the call query. }
  ID_CHUNK = 400;

  PAIR_KEY = '%s|%s';
  PLACE_KEY = '%s|%d|%d';

  SQL_CALLS_IN_ROUTINES =
    'SELECT r.enclosing_symbol_id, r.start_line, r.start_col, ce.target_symbol_id, s.qualified_name ' +
    'FROM refs r JOIN call_edges ce ON ce.ref_id = r.id ' +
    'JOIN symbols s ON s.id = ce.target_symbol_id ' +
    'WHERE r.enclosing_symbol_id IN (%s) ' +
    'ORDER BY r.enclosing_symbol_id, r.start_line, r.start_col';
  CALL_ROUTINE_ID = 0;
  CALL_LINE       = 1;
  CALL_COL        = 2;
  CALL_TARGET_ID  = 3;
  CALL_TARGET_QN  = 4;

  SQL_CALLEES_OF =
    'SELECT DISTINCT ce.target_symbol_id FROM refs r JOIN call_edges ce ON ce.ref_id = r.id ' +
    'WHERE r.enclosing_symbol_id = :id';
  PARAM_ID = 'id';

  MSG_DIRECT =
    'Lock order inversion: %s is taken here while %s is held (taken at line %d), but %s takes %s first ' +
    'and then %s (%s:%d) -- two threads can deadlock; take the two locks in one order everywhere';
  MSG_VIA_CALL =
    'Lock order inversion: %s, called here while %s is held (taken at line %d), takes %s (in %s, %s:%d), ' +
    'but %s takes %s first and then %s (%s:%d) -- two threads can deadlock; take the two locks in one order everywhere';

type
  { One blocking enter of an exact lock. }
  TAcquire = record
    Key: string;
    Shared: Boolean;
    RoutineQName: string;
    FilePath: string;
    Line: Integer;
  end;

  { "OuterKey is held when InnerKey is taken", at one place. }
  TOrderEdge = record
    OuterKey: string;
    InnerKey: string;
    OuterShared: Boolean;
    InnerShared: Boolean;
    Held: TArray<string>;   // every exact lock held at the place, OuterKey among them
    RoutineQName: string;
    FilePath: string;
    Line: Integer;          // the place: the enter of the inner lock, or the call that leads to it
    Col: Integer;
    OuterLine: Integer;
    ViaQName: string;       // '' = direct; else the routine called at the place
    Taken: TAcquire;        // where the inner lock is entered
  end;

  { One run of the analysis over one index. }
  TLockOrderRun = class
  private
    FStore: ISymbolStore;
    FRoutines: TArray<TRoutineLockSites>;
    FByRoutine: TDictionary<Int64, Integer>;
    FNames: TDictionary<string, string>;
    FCallees: TDictionary<Int64, TArray<Int64>>;
    FReach: TDictionary<Int64, TArray<TAcquire>>;
    FEdges: TList<TOrderEdge>;
    FByPair: TObjectDictionary<string, TList<Integer>>;
    FCalleeQuery: TFDQuery;
    function NewQuery(const pSql: string): TFDQuery;
    function NameOf(const pKey: string): string;
    function OwnAcquires(pRoutineId: Int64): TArray<TAcquire>;
    function CalleesOf(pRoutineId: Int64): TArray<Int64>;
    function Reach(pRoutineId: Int64): TArray<TAcquire>;
    procedure HeldRegions(const pRoutine: TRoutineLockSites; pLine, pCol: Integer;
      out pAllKeys: TArray<string>; out pOuter: TArray<Integer>);
    procedure AddEdges(const pRoutine: TRoutineLockSites; const pOuter: TArray<Integer>;
      pLine, pCol: Integer; const pTaken: TAcquire; const pViaQName: string);
    procedure CollectNames;
    procedure CollectDirectEdges;
    procedure CollectCallEdges;
    procedure CollectCallEdgesOf(const pIdList: string);
    function Opposite(const pEdge: TOrderEdge; out pOther: TOrderEdge): Boolean;
    function MessageOf(const pEdge, pOther: TOrderEdge): string;
  public
    constructor Create(const pStore: ISymbolStore);
    destructor Destroy; override;
    function Run(const pCfg: TLintConfig; const pRuleId, pSeverity: string): TArray<TLintFinding>;
  end;

function HasKey(const pKeys: TArray<string>; const pKey: string): Boolean;
begin
  Result:= False;
  for var K in pKeys do
    if K = pKey then Exit(True);
end;

{ True when a thread at pEdge and a thread at pOther can wait for each other. }
function CanDeadlock(const pEdge, pOther: TOrderEdge): Boolean;
begin
  { pEdge holds A and wants B; pOther holds B and wants A. A wait needs one exclusive side per lock. }
  Result:= not (pEdge.OuterShared and pOther.InnerShared) and not (pEdge.InnerShared and pOther.OuterShared);
  if Result then
    for var K in pEdge.Held do
      if (K <> pEdge.OuterKey) and (K <> pEdge.InnerKey) and HasKey(pOther.Held, K) then Exit(False);
end;

{ TLockOrderRun }

constructor TLockOrderRun.Create(const pStore: ISymbolStore);
begin
  inherited Create;
  FStore    := pStore;
  FByRoutine:= TDictionary<Int64, Integer>.Create;
  FNames    := TDictionary<string, string>.Create;
  FCallees  := TDictionary<Int64, TArray<Int64>>.Create;
  FReach    := TDictionary<Int64, TArray<TAcquire>>.Create;
  FEdges    := TList<TOrderEdge>.Create;
  FByPair   := TObjectDictionary<string, TList<Integer>>.Create([doOwnsValues]);
end;

destructor TLockOrderRun.Destroy;
begin
  FCalleeQuery.Free;
  FByPair.Free;
  FEdges.Free;
  FReach.Free;
  FCallees.Free;
  FNames.Free;
  FByRoutine.Free;
  inherited;
end;

{ The caller frees the query. }
function TLockOrderRun.NewQuery(const pSql: string): TFDQuery;
begin
  Result:= TFDQuery.Create(nil);
  Result.Connection:= (FStore as TSQLiteSymbolStore).GetConnection;
  Result.SQL.Text  := pSql;
end;

function TLockOrderRun.NameOf(const pKey: string): string;
begin
  if not FNames.TryGetValue(pKey, Result) then Result:= pKey;
end;

{ Fills FByRoutine and the display name of every exact lock. }
procedure TLockOrderRun.CollectNames;
begin
  for var I:= 0 to High(FRoutines) do
  begin
    if FRoutines[I].RoutineId <> 0 then FByRoutine.AddOrSetValue(FRoutines[I].RoutineId, I);
    for var Site in FRoutines[I].Sites do
      if Site.Exact and not FNames.ContainsKey(Site.LockKey) then
        FNames.Add(Site.LockKey, if Site.LockQName <> '' then Site.LockQName else Site.LockText);
  end;
end;

{ The blocking enters of exact locks written in the routine itself. }
function TLockOrderRun.OwnAcquires(pRoutineId: Int64): TArray<TAcquire>;
var
  At: Integer;
  Acquire: TAcquire;
begin
  Result:= nil;
  if not FByRoutine.TryGetValue(pRoutineId, At) then Exit;
  for var Site in FRoutines[At].Sites do
    if (Site.Op = lsoEnter) and Site.Exact then
    begin
      Acquire.Key         := Site.LockKey;
      Acquire.Shared      := Site.Shared;
      Acquire.RoutineQName:= FRoutines[At].RoutineQName;
      Acquire.FilePath    := FRoutines[At].FilePath;
      Acquire.Line        := Site.Line;
      Result:= Result + [Acquire];
    end;
end;

{ The routines pRoutineId calls, each once; answered from memory on a second ask. }
function TLockOrderRun.CalleesOf(pRoutineId: Int64): TArray<Int64>;
begin
  if FCallees.TryGetValue(pRoutineId, Result) then Exit;
  Result:= nil;
  if FCalleeQuery = nil then FCalleeQuery:= NewQuery(SQL_CALLEES_OF);
  FCalleeQuery.Close;
  FCalleeQuery.ParamByName(PARAM_ID).AsLargeInt:= pRoutineId;
  FCalleeQuery.Open;
  try
    while not FCalleeQuery.Eof do
    begin
      Result:= Result + [FCalleeQuery.Fields[0].AsLargeInt];
      FCalleeQuery.Next;
    end;
  finally
    FCalleeQuery.Close;
  end;
  FCallees.Add(pRoutineId, Result);
end;

{ Every lock pRoutineId enters, itself or through the routines it calls (LOCK_ORDER_CALL_DEPTH levels,
  pRoutineId being level 1); one entry per lock and mode, the nearest first. }
function TLockOrderRun.Reach(pRoutineId: Int64): TArray<TAcquire>;
begin
  if FReach.TryGetValue(pRoutineId, Result) then Exit;
  Result:= nil;
  var Seen:= TDictionary<Int64, Boolean>.Create;
  var Got := TDictionary<string, Boolean>.Create;
  try
    var Level: TArray<Int64>:= [pRoutineId];
    Seen.Add(pRoutineId, True);
    for var Depth:= 1 to LOCK_ORDER_CALL_DEPTH do
    begin
      var Next: TArray<Int64>:= nil;
      for var Id in Level do
      begin
        for var Acquire in OwnAcquires(Id) do
        begin
          var ModeKey:= Format(PAIR_KEY, [Acquire.Key, BoolToStr(Acquire.Shared)]);
          if Got.ContainsKey(ModeKey) then Continue;
          Got.Add(ModeKey, True);
          Result:= Result + [Acquire];
        end;
        if Depth = LOCK_ORDER_CALL_DEPTH then Continue;
        for var Callee in CalleesOf(Id) do
          if (Seen.Count < REACH_ROUTINE_CAP) and not Seen.ContainsKey(Callee) then
          begin
            Seen.Add(Callee, True);
            Next:= Next + [Callee];
          end;
      end;
      Level:= Next;
      if Level = nil then Break;
    end;
  finally
    Got.Free;
    Seen.Free;
  end;
  FReach.Add(pRoutineId, Result);
end;

{ The locks held at a position of pRoutine: pAllKeys = every region's key (exact or not, tried or not),
  pOuter = the regions an order edge may start from (exact, entered by a blocking enter). }
procedure TLockOrderRun.HeldRegions(const pRoutine: TRoutineLockSites; pLine, pCol: Integer;
  out pAllKeys: TArray<string>; out pOuter: TArray<Integer>);
begin
  pAllKeys:= nil;
  pOuter  := nil;
  for var R in pRoutine.HeldAt(pLine, pCol) do
  begin
    var Region:= pRoutine.Regions[R];
    pAllKeys:= pAllKeys + [Region.LockKey];
    if Region.Exact and (pRoutine.Sites[Region.EnterSite].Op = lsoEnter) then pOuter:= pOuter + [R];
  end;
end;

{ One edge per held region of pOuter: "that lock is held when pTaken.Key is taken at pLine, pCol". }
procedure TLockOrderRun.AddEdges(const pRoutine: TRoutineLockSites; const pOuter: TArray<Integer>;
  pLine, pCol: Integer; const pTaken: TAcquire; const pViaQName: string);
var
  Edge: TOrderEdge;
  List: TList<Integer>;
begin
  var Held: TArray<string>:= nil;
  for var R in pOuter do Held:= Held + [pRoutine.Regions[R].LockKey];
  for var R in pOuter do
  begin
    var Region:= pRoutine.Regions[R];
    Edge:= Default(TOrderEdge);
    Edge.OuterKey    := Region.LockKey;
    Edge.InnerKey    := pTaken.Key;
    Edge.OuterShared := pRoutine.Sites[Region.EnterSite].Shared;
    Edge.InnerShared := pTaken.Shared;
    Edge.Held        := Held;
    Edge.RoutineQName:= pRoutine.RoutineQName;
    Edge.FilePath    := pRoutine.FilePath;
    Edge.Line        := pLine;
    Edge.Col         := pCol;
    Edge.OuterLine   := Region.StartLine;
    Edge.ViaQName    := pViaQName;
    Edge.Taken       := pTaken;
    var Pair:= Format(PAIR_KEY, [Edge.OuterKey, Edge.InnerKey]);
    if not FByPair.TryGetValue(Pair, List) then
    begin
      List:= TList<Integer>.Create;
      FByPair.Add(Pair, List);
    end;
    List.Add(FEdges.Add(Edge));
  end;
end;

{ Edges whose second lock is entered in the routine that holds the first. }
procedure TLockOrderRun.CollectDirectEdges;
var
  AllKeys: TArray<string>;
  Outer: TArray<Integer>;
  Taken: TAcquire;
begin
  for var Routine in FRoutines do
    for var Site in Routine.Sites do
    begin
      if (Site.Op <> lsoEnter) or not Site.Exact then Continue;
      HeldRegions(Routine, Site.Line, Site.Col, AllKeys, Outer);
      if (Outer = nil) or HasKey(AllKeys, Site.LockKey) then Continue;
      Taken.Key         := Site.LockKey;
      Taken.Shared      := Site.Shared;
      Taken.RoutineQName:= Routine.RoutineQName;
      Taken.FilePath    := Routine.FilePath;
      Taken.Line        := Site.Line;
      AddEdges(Routine, Outer, Site.Line, Site.Col, Taken, '');
    end;
end;

{ Edges of the calls made by the routines of pIdList (a comma list of routine ids). }
procedure TLockOrderRun.CollectCallEdgesOf(const pIdList: string);
var
  AllKeys: TArray<string>;
  Outer: TArray<Integer>;
  At: Integer;
begin
  var Query:= NewQuery(Format(SQL_CALLS_IN_ROUTINES, [pIdList]));
  try
    Query.Open;
    while not Query.Eof do
    begin
      if FByRoutine.TryGetValue(Query.Fields[CALL_ROUTINE_ID].AsLargeInt, At) then
      begin
        var Line:= Query.Fields[CALL_LINE].AsInteger;
        var Col := Query.Fields[CALL_COL].AsInteger;
        HeldRegions(FRoutines[At], Line, Col, AllKeys, Outer);
        if Outer <> nil then
          for var Taken in Reach(Query.Fields[CALL_TARGET_ID].AsLargeInt) do
            if not HasKey(AllKeys, Taken.Key) then
              AddEdges(FRoutines[At], Outer, Line, Col, Taken, Query.Fields[CALL_TARGET_QN].AsString);
      end;
      Query.Next;
    end;
  finally
    Query.Free;
  end;
end;

{ Edges whose second lock is entered by a routine called while the first is held. Only the routines
  that hold an exact lock over some stretch are asked for their calls. }
procedure TLockOrderRun.CollectCallEdges;
begin
  var Ids:= '';
  var Count:= 0;
  for var Routine in FRoutines do
  begin
    if Routine.RoutineId = 0 then Continue;
    var Holds:= False;
    for var Region in Routine.Regions do
      if Region.Exact and (Routine.Sites[Region.EnterSite].Op = lsoEnter) then Holds:= True;
    if not Holds then Continue;
    Ids:= Ids + (if Ids = '' then '' else ',') + IntToStr(Routine.RoutineId);
    Inc(Count);
    if Count = ID_CHUNK then
    begin
      CollectCallEdgesOf(Ids);
      Ids  := '';
      Count:= 0;
    end;
  end;
  if Ids <> '' then CollectCallEdgesOf(Ids);
end;

{ The first place that takes the two locks of pEdge in the opposite order and can deadlock with it. }
function TLockOrderRun.Opposite(const pEdge: TOrderEdge; out pOther: TOrderEdge): Boolean;
var
  List: TList<Integer>;
begin
  Result:= False;
  pOther:= Default(TOrderEdge);
  if not FByPair.TryGetValue(Format(PAIR_KEY, [pEdge.InnerKey, pEdge.OuterKey]), List) then Exit;
  for var I in List do
    if CanDeadlock(pEdge, FEdges[I]) then
    begin
      pOther:= FEdges[I];
      Exit(True);
    end;
end;

function TLockOrderRun.MessageOf(const pEdge, pOther: TOrderEdge): string;
begin
  var Outer:= NameOf(pEdge.OuterKey);
  var Inner:= NameOf(pEdge.InnerKey);
  var OtherFile:= ExtractFileName(pOther.FilePath);
  Result:=
    if pEdge.ViaQName = '' then
      Format(MSG_DIRECT, [Inner, Outer, pEdge.OuterLine, pOther.RoutineQName, Inner, Outer,
        OtherFile, pOther.Line])
    else
      Format(MSG_VIA_CALL, [pEdge.ViaQName, Outer, pEdge.OuterLine, Inner, pEdge.Taken.RoutineQName,
        ExtractFileName(pEdge.Taken.FilePath), pEdge.Taken.Line, pOther.RoutineQName, Inner, Outer,
        OtherFile, pOther.Line]);
end;

function TLockOrderRun.Run(const pCfg: TLintConfig; const pRuleId, pSeverity: string): TArray<TLintFinding>;
var
  Other: TOrderEdge;
  Finding: TLintFinding;
begin
  Result:= nil;
  FRoutines:= LockSitesOfProject(FStore);
  if FRoutines = nil then Exit;
  CollectNames;
  CollectDirectEdges;
  CollectCallEdges;
  var Reported:= TDictionary<string, Boolean>.Create;
  try
    for var Edge in FEdges do
    begin
      if not Opposite(Edge, Other) then Continue;
      var Place:= Format(PLACE_KEY, [LowerCase(Edge.FilePath), Edge.Line, Edge.Col]);
      if Reported.ContainsKey(Place) then Continue;
      Reported.Add(Place, True);
      Finding:= Default(TLintFinding);
      Finding.RuleId   := pRuleId;
      Finding.FilePath := Edge.FilePath;
      Finding.StartLine:= Edge.Line;
      Finding.StartCol := Edge.Col;
      Finding.EndLine  := Edge.Line;
      Finding.EndCol   := Edge.Col + 1;
      Finding.Severity := pCfg.ApplySeverity(pRuleId, pSeverity);
      Finding.Message  := MessageOf(Edge, Other);
      Result:= Result + [Finding];
    end;
  finally
    Reported.Free;
  end;
  TArray.Sort<TLintFinding>(Result, TComparer<TLintFinding>.Construct(
    function(const pLeft, pRight: TLintFinding): Integer
    begin
      Result:= CompareText(pLeft.FilePath, pRight.FilePath);
      if Result = 0 then Result:= pLeft.StartLine - pRight.StartLine;
      if Result = 0 then Result:= pLeft.StartCol - pRight.StartCol;
    end));
end;

function LockOrderInversions(const pStore: ISymbolStore; const pCfg: TLintConfig;
  const pRuleId, pSeverity: string): TArray<TLintFinding>;
begin
  Result:= nil;
  if (pStore = nil) or (pStore is not TSQLiteSymbolStore) then Exit;
  var Run:= TLockOrderRun.Create(pStore);
  try
    Result:= Run.Run(pCfg, pRuleId, pSeverity);
  finally
    Run.Free;
  end;
end;

end.
