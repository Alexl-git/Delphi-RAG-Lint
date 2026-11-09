unit DRagLint.Report.CycleHub;

/// <summary>`cycles --hub`: the hub analysis of one circular unit group (spec
/// docs\superpowers\specs\2026-11-08-hub-scc-phased.md, phase P1). A hub is a unit whose
/// removal leaves the rest of the group acyclic (a star, not a tangle); the report names
/// every hub, the uses edges and reference weights on each side of it, whether cutting
/// one side alone breaks the group, what the spokes take from the hub (globals with the
/// member names read through them, routines) and what the hub takes from the spokes.</summary>
/// <remarks>Read-only over the index; never runs the planner, opens no library, needs no
/// project. Member names are counted by `refs.name_text` of the references whose
/// `receiver_text` is a hub global (the fact that exists today; phase P5 resolves them).
/// Owned by the caller: the graph (BuildCycleGraph) is only read.</remarks>

interface

uses
  System.SysUtils, System.Generics.Collections, System.JSON,
  DRagLint.Core.Interfaces, DRagLint.Report.CyclePlan;

type
  /// <summary>One side of a hub: the uses edges that enter (in) or leave (out) it inside the group.</summary>
  TCycleHubSide = record
    /// <summary>Uses edges on this side, inside the group.</summary>
    Edges: Integer;
    /// <summary>How many of them are interface-section edges.</summary>
    IntfEdges: Integer;
    /// <summary>References crossing this side (consumer unit to a symbol declared in the other unit).</summary>
    Refs: Integer;
    /// <summary>True when cutting every edge of this side, and nothing else, leaves the group acyclic.</summary>
    BreaksAlone: Boolean;
  end;

  /// <summary>A member name read through a hub global from the spokes, with its weight.</summary>
  TCycleHubMember = record
    Name: string;
    Refs: Integer;
    Units: Integer;
  end;

  /// <summary>One hub symbol the spokes reference: kind, name, weight and (for a global) the member names read through it.</summary>
  TCycleHubSymbol = record
    Kind: string;
    Name: string;
    Refs: Integer;
    Units: Integer;
    Members: TArray<TCycleHubMember>;
  end;

  /// <summary>What the hub takes from its spokes, by shape.</summary>
  TCycleHubOut = record
    Construction: Integer;
    VarWrite: Integer;
    VarRead: Integer;
    MethodCall: Integer;
    Units: Integer;
  end;

  /// <summary>One hub of a group.</summary>
  TCycleHub = record
    /// <summary>Lower-case unit stem, as `cycles` prints it.</summary>
    UnitStem: string;
    InSide: TCycleHubSide;
    OutSide: TCycleHubSide;
    /// <summary>Hub symbols referenced from the spokes, heaviest first.</summary>
    SpokeToHub: TArray<TCycleHubSymbol>;
    HubToSpoke: TCycleHubOut;
    /// <summary>'spoke->hub' or 'hub->spoke': the side with fewer distinct surfaces to cut.</summary>
    LighterSide: string;
  end;

  /// <summary>The hub report of one group.</summary>
  TCycleHubReport = record
    Hubs: TArray<TCycleHub>;
    /// <summary>Uses edges inside the group that no reference crosses (dead uses).</summary>
    ZeroRefEdges: Integer;
    /// <summary>Uses edges inside the group.</summary>
    Edges: Integer;
  end;

/// <summary>Analyses one circular group for hubs.</summary>
/// <param name="pStore">The index the group came from; read only.</param>
/// <param name="pGroup">The group's lower-case unit stems (one entry of ComputeSccs).</param>
/// <param name="pGraph">The graph DoCycles built (BuildCycleGraph); read only.</param>
/// <returns>Hubs in group order; none when no single unit's removal leaves the rest acyclic.</returns>
/// <remarks>Cost: one FindSymbolsByFile and one GetReferencesFromFile per unit of the group, plus
/// O(n * (n + m)) acyclicity tests over the group's n units and m edges.</remarks>
function AnalyseCycleHubs(const pStore: ISymbolStore; const pGroup: TArray<string>;
  const pGraph: TCycleGraph): TCycleHubReport;

/// <summary>The text block `cycles --hub` prints under a group line.</summary>
/// <param name="pReport">From AnalyseCycleHubs.</param>
/// <returns>Lines indented to sit under the group line; "hubs: none ..." when there is no hub.</returns>
function CycleHubLines(const pReport: TCycleHubReport): TArray<string>;

/// <summary>Adds the `hubs` array and `zero_ref_edges` to a group object of `cycles --format json`.</summary>
/// <param name="pReport">From AnalyseCycleHubs.</param>
/// <param name="pGroup">The group's JSON object; gains the two pairs.</param>
procedure AddCycleHubJson(const pReport: TCycleHubReport; const pGroup: TJSONObject);

implementation

uses
  System.Generics.Defaults, DRagLint.Core.Model;

const
  CMembersInText = 6;  { member names named on the text line; JSON carries them all }
  CSymbolsInText = 6;

type
  TEdge = record
    A: string;
    B: string;
  end;

  { refs and distinct consumer units per key (a symbol id as text, or a member name) }
  TTally = class
  private
    FRefs : TDictionary<string, Integer>;
    FUnits: TObjectDictionary<string, TDictionary<string, Boolean>>;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Add(const pKey, pUnit: string);
    function Keys: TArray<string>;
    function Refs(const pKey: string): Integer;
    function Units(const pKey: string): Integer;
  end;

  { the symbols and references of one group, loaded once }
  TGroupFacts = class
  private
    FGroup   : TArray<string>;
    FGraph   : TCycleGraph;
    FEdges   : TArray<TEdge>;
    FSymUnit : TDictionary<Int64, string>;      { symbol id -> declaring unit stem (group units only) }
    FSymKind : TDictionary<Int64, TSymbolKind>;
    FSymName : TDictionary<Int64, string>;
    FSymMember: TDictionary<Int64, Boolean>;    { declared inside a type (field, method, property) }
    FRefsOf  : TDictionary<string, TArray<TReference>>;
    FWeight  : TDictionary<string, Integer>;    { 'a->b' -> refs crossing the edge }
    function TargetUnit(const pRef: TReference; out pUnit: string): Boolean;
    procedure LoadEdges;
    procedure LoadSymbolsAndRefs(const pStore: ISymbolStore);
    procedure CountWeights;
    function SpokeToHub(const pHub: string): TArray<TCycleHubSymbol>;
    function MembersThrough(const pHub, pGlobal: string): TArray<TCycleHubMember>;
    function HubToSpoke(const pHub: string): TCycleHubOut;
    function SideOf(const pHub: string; pIn: Boolean): TCycleHubSide;
  public
    constructor Create(const pStore: ISymbolStore; const pGroup: TArray<string>; const pGraph: TCycleGraph);
    destructor Destroy; override;
    function Analyse: TCycleHubReport;
  end;

{ Kahn: is the group acyclic once pDropUnit and the edges leaving pSkipFrom / entering pSkipTo are ignored? }
function IsAcyclic(const pUnits: TArray<string>; const pEdges: TArray<TEdge>;
  const pDropUnit, pSkipFrom, pSkipTo: string): Boolean;
var
  InDeg: TDictionary<string, Integer>;
  Queue: TQueue<string>;
  Seen : Integer;
  Kept : TList<TEdge>;
begin
  InDeg:= TDictionary<string, Integer>.Create;
  Queue:= TQueue<string>.Create;
  Kept := TList<TEdge>.Create;
  try
    for var U in pUnits do
      if U <> pDropUnit then InDeg.Add(U, 0);
    for var E in pEdges do
    begin
      if (E.A = pDropUnit) or (E.B = pDropUnit) then Continue;
      if (pSkipFrom <> '') and (E.A = pSkipFrom) then Continue;
      if (pSkipTo <> '') and (E.B = pSkipTo) then Continue;
      Kept.Add(E);
      InDeg[E.B]:= InDeg[E.B] + 1;
    end;
    for var P in InDeg do
      if P.Value = 0 then Queue.Enqueue(P.Key);
    Seen:= 0;
    while Queue.Count > 0 do
    begin
      var U:= Queue.Dequeue;
      Inc(Seen);
      for var E in Kept do
      begin
        if E.A <> U then Continue;
        InDeg[E.B]:= InDeg[E.B] - 1;
        if InDeg[E.B] = 0 then Queue.Enqueue(E.B);
      end;
    end;
    Result:= Seen = InDeg.Count;
  finally
    Kept.Free;
    Queue.Free;
    InDeg.Free;
  end;
end;

function KindName(pKind: TSymbolKind): string;
begin
  case pKind of
    skVarDecl    : Result:= 'var';
    skField      : Result:= 'field';
    skMethod     : Result:= 'method';
    skClass      : Result:= 'class';
    skProcedure  : Result:= 'procedure';
    skFunction   : Result:= 'function';
    skConstructor: Result:= 'constructor';
    skProperty   : Result:= 'property';
    skConstDecl  : Result:= 'const';
    skTypeAlias  : Result:= 'type';
    skRecord     : Result:= 'record';
    skInterface  : Result:= 'interface';
    skEnum       : Result:= 'enum';
  else
    Result:= 'other';
  end;
end;

{ TTally }

constructor TTally.Create;
begin
  inherited Create;
  FRefs := TDictionary<string, Integer>.Create;
  FUnits:= TObjectDictionary<string, TDictionary<string, Boolean>>.Create([doOwnsValues]);
end;

destructor TTally.Destroy;
begin
  FUnits.Free;
  FRefs.Free;
  inherited Destroy;
end;

procedure TTally.Add(const pKey, pUnit: string);
var
  N : Integer;
  Us: TDictionary<string, Boolean>;
begin
  if not FRefs.TryGetValue(pKey, N) then N:= 0;
  FRefs.AddOrSetValue(pKey, N + 1);
  if not FUnits.TryGetValue(pKey, Us) then
  begin
    Us:= TDictionary<string, Boolean>.Create;
    FUnits.Add(pKey, Us);
  end;
  Us.AddOrSetValue(pUnit, True);
end;

function TTally.Keys: TArray<string>;
begin
  Result:= FRefs.Keys.ToArray;
end;

function TTally.Refs(const pKey: string): Integer;
begin
  Result:= FRefs[pKey];
end;

function TTally.Units(const pKey: string): Integer;
begin
  Result:= FUnits[pKey].Count;
end;

{ TGroupFacts }

constructor TGroupFacts.Create(const pStore: ISymbolStore; const pGroup: TArray<string>; const pGraph: TCycleGraph);
begin
  inherited Create;
  FGroup:= pGroup;
  FGraph:= pGraph;
  FSymUnit  := TDictionary<Int64, string>.Create;
  FSymKind  := TDictionary<Int64, TSymbolKind>.Create;
  FSymName  := TDictionary<Int64, string>.Create;
  FSymMember:= TDictionary<Int64, Boolean>.Create;
  FRefsOf   := TDictionary<string, TArray<TReference>>.Create;
  FWeight   := TDictionary<string, Integer>.Create;
  LoadEdges;
  LoadSymbolsAndRefs(pStore);
  CountWeights;
end;

destructor TGroupFacts.Destroy;
begin
  FWeight.Free;
  FRefsOf.Free;
  FSymMember.Free;
  FSymName.Free;
  FSymKind.Free;
  FSymUnit.Free;
  inherited Destroy;
end;

procedure TGroupFacts.LoadEdges;
var
  InGroup: TDictionary<string, Boolean>;
  Edges  : TList<TEdge>;
  L      : TList<string>;
begin
  InGroup:= TDictionary<string, Boolean>.Create;
  Edges  := TList<TEdge>.Create;
  try
    for var U in FGroup do InGroup.AddOrSetValue(U, True);
    for var U in FGroup do
    begin
      if not FGraph.Adj.TryGetValue(U, L) then Continue;
      for var V in L do
      begin
        if (V = U) or not InGroup.ContainsKey(V) then Continue;
        var E: TEdge;
        E.A:= U;
        E.B:= V;
        Edges.Add(E);
        FWeight.AddOrSetValue(U + '->' + V, 0);
      end;
    end;
    FEdges:= Edges.ToArray;
  finally
    Edges.Free;
    InGroup.Free;
  end;
end;

procedure TGroupFacts.LoadSymbolsAndRefs(const pStore: ISymbolStore);
var
  Path: string;
  Fid : Int64;
begin
  for var U in FGroup do
  begin
    if FGraph.UnitFile.TryGetValue(U, Path) then
      for var S in CycleSymbolsByFile(FGraph, pStore, Path) do
      begin
        FSymUnit.AddOrSetValue(S.Id, U);
        FSymKind.AddOrSetValue(S.Id, S.Kind);
        FSymName.AddOrSetValue(S.Id, S.Name);
        FSymMember.AddOrSetValue(S.Id, S.ParentId > 0);
      end;
    if FGraph.UnitFid.TryGetValue(U, Fid) then FRefsOf.AddOrSetValue(U, CycleRefsFromFile(FGraph, pStore, Fid))
    else FRefsOf.AddOrSetValue(U, nil);
  end;
end;

function TGroupFacts.TargetUnit(const pRef: TReference; out pUnit: string): Boolean;
begin
  Result:= (pRef.SymbolId > 0) and FSymUnit.TryGetValue(pRef.SymbolId, pUnit);
end;

procedure TGroupFacts.CountWeights;
var
  T: string;
  W: Integer;
begin
  for var U in FGroup do
    for var R in FRefsOf[U] do
      if TargetUnit(R, T) and (T <> U) and FWeight.TryGetValue(U + '->' + T, W) then FWeight[U + '->' + T]:= W + 1;
end;

function TGroupFacts.SideOf(const pHub: string; pIn: Boolean): TCycleHubSide;
begin
  Result:= Default(TCycleHubSide);
  for var E in FEdges do
  begin
    if (pIn and (E.B <> pHub)) or (not pIn and (E.A <> pHub)) then Continue;
    Inc(Result.Edges);
    if FGraph.IntfEdges.ContainsKey(E.A + '->' + E.B) then Inc(Result.IntfEdges);
    Inc(Result.Refs, FWeight[E.A + '->' + E.B]);
  end;
  Result.BreaksAlone:= if pIn then IsAcyclic(FGroup, FEdges, '', '', pHub) else IsAcyclic(FGroup, FEdges, '', pHub, '');
end;

function TGroupFacts.MembersThrough(const pHub, pGlobal: string): TArray<TCycleHubMember>;
var
  Tally: TTally;
  Mems : TList<TCycleHubMember>;
begin
  Tally:= TTally.Create;
  Mems := TList<TCycleHubMember>.Create;
  try
    for var V in FGroup do
    begin
      if V = pHub then Continue;
      for var R in FRefsOf[V] do
        if SameText(R.ReceiverText, pGlobal) and (R.NameText <> '') then Tally.Add(R.NameText, V);
    end;
    for var K in Tally.Keys do
    begin
      var M: TCycleHubMember;
      M.Name := K;
      M.Refs := Tally.Refs(K);
      M.Units:= Tally.Units(K);
      Mems.Add(M);
    end;
    Mems.Sort(TComparer<TCycleHubMember>.Construct(
      function(const L, R: TCycleHubMember): Integer
      begin
        Result:= R.Refs - L.Refs;
        if Result = 0 then Result:= CompareText(L.Name, R.Name);
      end));
    Result:= Mems.ToArray;
  finally
    Mems.Free;
    Tally.Free;
  end;
end;

function TGroupFacts.SpokeToHub(const pHub: string): TArray<TCycleHubSymbol>;
var
  HubVars: TDictionary<string, Boolean>;  { lower-case names of the hub's globals }
  Tally  : TTally;
  Syms   : TList<TCycleHubSymbol>;
  T      : string;
begin
  HubVars:= TDictionary<string, Boolean>.Create;
  Tally  := TTally.Create;
  Syms   := TList<TCycleHubSymbol>.Create;
  try
    for var P in FSymUnit do
      if (P.Value = pHub) and (FSymKind[P.Key] = skVarDecl) then HubVars.AddOrSetValue(LowerCase(FSymName[P.Key]), True);
    for var V in FGroup do
    begin
      if V = pHub then Continue;
      for var R in FRefsOf[V] do
      begin
        if not (TargetUnit(R, T) and (T = pHub)) then Continue;
        { a resolved member reached through a hub global is counted under that global's member names, not as a surface symbol }
        if FSymMember[R.SymbolId] and HubVars.ContainsKey(LowerCase(R.ReceiverText)) then Continue;
        Tally.Add(IntToStr(R.SymbolId), V);
      end;
    end;
    for var K in Tally.Keys do
    begin
      var Id:= StrToInt64(K);
      var S: TCycleHubSymbol;
      S.Kind := KindName(FSymKind[Id]);
      S.Name := FSymName[Id];
      S.Refs := Tally.Refs(K);
      S.Units:= Tally.Units(K);
      S.Members:= if FSymKind[Id] = skVarDecl then MembersThrough(pHub, S.Name) else nil;
      Syms.Add(S);
    end;
    Syms.Sort(TComparer<TCycleHubSymbol>.Construct(
      function(const L, R: TCycleHubSymbol): Integer
      begin
        Result:= R.Refs - L.Refs;
        if Result = 0 then Result:= CompareText(L.Name, R.Name);
      end));
    Result:= Syms.ToArray;
  finally
    Syms.Free;
    Tally.Free;
    HubVars.Free;
  end;
end;

function TGroupFacts.HubToSpoke(const pHub: string): TCycleHubOut;
var
  OutUnits: TDictionary<string, Boolean>;
  T       : string;
begin
  Result:= Default(TCycleHubOut);
  OutUnits:= TDictionary<string, Boolean>.Create;
  try
    for var R in FRefsOf[pHub] do
    begin
      if not (TargetUnit(R, T) and (T <> pHub)) then Continue;
      OutUnits.AddOrSetValue(T, True);
      case FSymKind[R.SymbolId] of
        skClass      : if SameText(R.Kind, 'read') then Inc(Result.Construction);
        skConstructor: Inc(Result.Construction);
        skVarDecl    : if SameText(R.Kind, 'write') then Inc(Result.VarWrite) else Inc(Result.VarRead);
        skMethod     : if SameText(R.Kind, 'call') then Inc(Result.MethodCall);
      end;
    end;
    Result.Units:= OutUnits.Count;
  finally
    OutUnits.Free;
  end;
end;

function TGroupFacts.Analyse: TCycleHubReport;
var
  Hubs: TList<TCycleHub>;
begin
  Result:= Default(TCycleHubReport);
  Result.Edges:= Length(FEdges);
  for var P in FWeight do
    if P.Value = 0 then Inc(Result.ZeroRefEdges);
  Hubs:= TList<TCycleHub>.Create;
  try
    for var U in FGroup do
    begin
      if not IsAcyclic(FGroup, FEdges, U, '', '') then Continue;
      var H:= Default(TCycleHub);
      H.UnitStem  := U;
      H.InSide    := SideOf(U, True);
      H.OutSide   := SideOf(U, False);
      H.SpokeToHub:= SpokeToHub(U);
      H.HubToSpoke:= HubToSpoke(U);
      H.LighterSide:= if Length(H.SpokeToHub) <= H.HubToSpoke.Units then 'spoke->hub' else 'hub->spoke';
      Hubs.Add(H);
    end;
    Result.Hubs:= Hubs.ToArray;
  finally
    Hubs.Free;
  end;
end;

function AnalyseCycleHubs(const pStore: ISymbolStore; const pGroup: TArray<string>;
  const pGraph: TCycleGraph): TCycleHubReport;
var
  Facts: TGroupFacts;
begin
  Facts:= TGroupFacts.Create(pStore, pGroup, pGraph);
  try
    Result:= Facts.Analyse;
  finally
    Facts.Free;
  end;
end;

function YesNo(pB: Boolean): string;
begin
  Result:= if pB then 'yes' else 'no';
end;

function SideText(const pSide: TCycleHubSide; const pLabel, pAlone: string): string;
begin
  Result:= Format('%s %d edges (%d impl, %d intf) %d refs, %s: %s',
    [pLabel, pSide.Edges, pSide.Edges - pSide.IntfEdges, pSide.IntfEdges, pSide.Refs, pAlone, YesNo(pSide.BreaksAlone)]);
end;

{ "var GH 12 refs in 3 units (2 member names: F1 6, M 6)" }
function SymbolText(const pSym: TCycleHubSymbol): string;
var
  MP: TList<string>;
begin
  Result:= Format('%s %s %d refs in %d units', [pSym.Kind, pSym.Name, pSym.Refs, pSym.Units]);
  if Length(pSym.Members) = 0 then Exit;
  MP:= TList<string>.Create;
  try
    for var J:= 0 to Length(pSym.Members) - 1 do
    begin
      if J >= CMembersInText then
      begin
        MP.Add('...');
        Break;
      end;
      MP.Add(Format('%s %d', [pSym.Members[J].Name, pSym.Members[J].Refs]));
    end;
    Result:= Format('%s (%d member names: %s)', [Result, Length(pSym.Members), string.Join(', ', MP.ToArray)]);
  finally
    MP.Free;
  end;
end;

function SurfaceText(const pHub: TCycleHub): string;
var
  Parts: TList<string>;
begin
  Parts:= TList<string>.Create;
  try
    for var I:= 0 to Length(pHub.SpokeToHub) - 1 do
    begin
      if I >= CSymbolsInText then
      begin
        Parts.Add(Format('... %d more', [Length(pHub.SpokeToHub) - CSymbolsInText]));
        Break;
      end;
      Parts.Add(SymbolText(pHub.SpokeToHub[I]));
    end;
    Result:= Format('        spoke->hub surface: %d symbols -- %s', [Length(pHub.SpokeToHub), string.Join('; ', Parts.ToArray)]);
  finally
    Parts.Free;
  end;
end;

function CycleHubLines(const pReport: TCycleHubReport): TArray<string>;
var
  L: TList<string>;
begin
  L:= TList<string>.Create;
  try
    if Length(pReport.Hubs) = 0 then L.Add('      hubs: none (no single unit whose removal leaves the group acyclic)');
    for var H in pReport.Hubs do
    begin
      L.Add(Format('      hub %s: %s; %s', [H.UnitStem,
        SideText(H.InSide, 'in', 'the in-side alone breaks the group'), SideText(H.OutSide, 'out', 'the out-side alone')]));
      L.Add(SurfaceText(H));
      L.Add(Format('        hub->spoke surface: %d constructions, %d var writes, %d var reads, %d method calls in %d units',
        [H.HubToSpoke.Construction, H.HubToSpoke.VarWrite, H.HubToSpoke.VarRead, H.HubToSpoke.MethodCall, H.HubToSpoke.Units]));
      L.Add(Format('        lighter side: %s (%d hub symbols vs %d spoke surfaces)',
        [H.LighterSide, Length(H.SpokeToHub), H.HubToSpoke.Units]));
    end;
    L.Add(Format('      zero-ref edges inside the group: %d of %d', [pReport.ZeroRefEdges, pReport.Edges]));
    Result:= L.ToArray;
  finally
    L.Free;
  end;
end;

function SideToJson(const pSide: TCycleHubSide): TJSONObject;
begin
  Result:= TJSONObject.Create;
  Result.AddPair('edges', TJSONNumber.Create(pSide.Edges));
  Result.AddPair('intf_edges', TJSONNumber.Create(pSide.IntfEdges));
  Result.AddPair('refs', TJSONNumber.Create(pSide.Refs));
  Result.AddPair('breaks_alone', TJSONBool.Create(pSide.BreaksAlone));
end;

function SymbolToJson(const pSym: TCycleHubSymbol): TJSONObject;
var
  JM: TJSONArray;
begin
  Result:= TJSONObject.Create;
  Result.AddPair('kind', pSym.Kind);
  Result.AddPair('name', pSym.Name);
  Result.AddPair('refs', TJSONNumber.Create(pSym.Refs));
  Result.AddPair('units', TJSONNumber.Create(pSym.Units));
  JM:= TJSONArray.Create;
  for var M in pSym.Members do
  begin
    var JMO:= TJSONObject.Create;
    JMO.AddPair('name', M.Name);
    JMO.AddPair('refs', TJSONNumber.Create(M.Refs));
    JMO.AddPair('units', TJSONNumber.Create(M.Units));
    JM.AddElement(JMO);
  end;
  Result.AddPair('members', JM);
end;

function HubToJson(const pHub: TCycleHub): TJSONObject;
var
  JS: TJSONArray;
  JT: TJSONObject;
begin
  Result:= TJSONObject.Create;
  Result.AddPair('unit', pHub.UnitStem);
  Result.AddPair('in', SideToJson(pHub.InSide));
  Result.AddPair('out', SideToJson(pHub.OutSide));
  JS:= TJSONArray.Create;
  for var S in pHub.SpokeToHub do JS.AddElement(SymbolToJson(S));
  Result.AddPair('spoke_to_hub', JS);
  JT:= TJSONObject.Create;
  JT.AddPair('construction', TJSONNumber.Create(pHub.HubToSpoke.Construction));
  JT.AddPair('var_write', TJSONNumber.Create(pHub.HubToSpoke.VarWrite));
  JT.AddPair('var_read', TJSONNumber.Create(pHub.HubToSpoke.VarRead));
  JT.AddPair('method_call', TJSONNumber.Create(pHub.HubToSpoke.MethodCall));
  JT.AddPair('units', TJSONNumber.Create(pHub.HubToSpoke.Units));
  Result.AddPair('hub_to_spoke', JT);
  Result.AddPair('lighter_side', pHub.LighterSide);
end;

procedure AddCycleHubJson(const pReport: TCycleHubReport; const pGroup: TJSONObject);
var
  Arr: TJSONArray;
begin
  Arr:= TJSONArray.Create;
  for var H in pReport.Hubs do Arr.AddElement(HubToJson(H));
  pGroup.AddPair('hubs', Arr);
  pGroup.AddPair('zero_ref_edges', TJSONNumber.Create(pReport.ZeroRefEdges));
end;

end.
