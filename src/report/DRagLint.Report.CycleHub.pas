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
  System.SysUtils, System.Generics.Collections, System.Generics.Defaults, System.JSON,
  DRagLint.Core.Interfaces, DRagLint.Core.Model, DRagLint.Report.CyclePlan;

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

const
  CMembersInText = 6;  { member names named on the text line; JSON carries them all }
  CSymbolsInText = 6;

type
  TEdge = record
    A: string;
    B: string;
  end;

{ Kahn: is the group acyclic once the units in pDrop and the edges pSkip accepts are ignored? }
function IsAcyclic(const pUnits: TArray<string>; const pEdges: TArray<TEdge>;
  const pDropUnit: string; const pSkipFrom, pSkipTo: string): Boolean;
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
        if E.A = U then
        begin
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

function AnalyseCycleHubs(const pStore: ISymbolStore; const pGroup: TArray<string>;
  const pGraph: TCycleGraph): TCycleHubReport;
var
  InGroup  : TDictionary<string, Boolean>;
  Edges    : TList<TEdge>;
  SymUnit  : TDictionary<Int64, string>;      { symbol id -> declaring unit stem (group units only) }
  SymKind  : TDictionary<Int64, TSymbolKind>;
  SymName  : TDictionary<Int64, string>;
  SymMember: TDictionary<Int64, Boolean>;     { symbol id -> declared inside a type (field, method, property) }
  RefsOf   : TDictionary<string, TArray<TReference>>;
  Weight   : TDictionary<string, Integer>;    { 'a->b' -> refs crossing }
  Hubs     : TList<TCycleHub>;
begin
  Result.Hubs:= nil;
  Result.ZeroRefEdges:= 0;
  Result.Edges:= 0;
  InGroup:= TDictionary<string, Boolean>.Create;
  Edges  := TList<TEdge>.Create;
  SymUnit:= TDictionary<Int64, string>.Create;
  SymKind:= TDictionary<Int64, TSymbolKind>.Create;
  SymName:= TDictionary<Int64, string>.Create;
  SymMember:= TDictionary<Int64, Boolean>.Create;
  RefsOf := TDictionary<string, TArray<TReference>>.Create;
  Weight := TDictionary<string, Integer>.Create;
  Hubs   := TList<TCycleHub>.Create;
  try
    for var U in pGroup do InGroup.AddOrSetValue(U, True);
    { the uses edges inside the group }
    for var U in pGroup do
    begin
      var L: TList<string>;
      if not pGraph.Adj.TryGetValue(U, L) then Continue;
      for var V in L do
        if (V <> U) and InGroup.ContainsKey(V) then
        begin
          var E: TEdge;
          E.A:= U;
          E.B:= V;
          Edges.Add(E);
          Weight.AddOrSetValue(U + '->' + V, 0);
        end;
    end;
    Result.Edges:= Edges.Count;
    { symbols and refs of every unit of the group, once }
    for var U in pGroup do
    begin
      var Path: string;
      var Fid : Int64;
      if pGraph.UnitFile.TryGetValue(U, Path) then
        for var S in pStore.FindSymbolsByFile(Path) do
        begin
          SymUnit.AddOrSetValue(S.Id, U);
          SymKind.AddOrSetValue(S.Id, S.Kind);
          SymName.AddOrSetValue(S.Id, S.Name);
          SymMember.AddOrSetValue(S.Id, S.ParentId > 0);
        end;
      if pGraph.UnitFid.TryGetValue(U, Fid) then RefsOf.AddOrSetValue(U, pStore.GetReferencesFromFile(Fid))
      else RefsOf.AddOrSetValue(U, nil);
    end;
    { edge weights }
    for var U in pGroup do
      for var R in RefsOf[U] do
      begin
        var T: string;
        if (R.SymbolId > 0) and SymUnit.TryGetValue(R.SymbolId, T) and (T <> U) then
        begin
          var K:= U + '->' + T;
          var W: Integer;
          if Weight.TryGetValue(K, W) then Weight[K]:= W + 1;
        end;
      end;
    for var P in Weight do
      if P.Value = 0 then Inc(Result.ZeroRefEdges);
    { hubs: the units whose removal leaves the rest acyclic }
    var EdgeArr:= Edges.ToArray;
    for var U in pGroup do
    begin
      if not IsAcyclic(pGroup, EdgeArr, U, '', '') then Continue;
      var H: TCycleHub;
      H.UnitStem:= U;
      H.InSide.Edges:= 0; H.InSide.IntfEdges:= 0; H.InSide.Refs:= 0;
      H.OutSide.Edges:= 0; H.OutSide.IntfEdges:= 0; H.OutSide.Refs:= 0;
      for var E in EdgeArr do
      begin
        var IsIntf:= pGraph.IntfEdges.ContainsKey(E.A + '->' + E.B);
        if E.B = U then
        begin
          Inc(H.InSide.Edges);
          if IsIntf then Inc(H.InSide.IntfEdges);
          Inc(H.InSide.Refs, Weight[E.A + '->' + E.B]);
        end
        else if E.A = U then
        begin
          Inc(H.OutSide.Edges);
          if IsIntf then Inc(H.OutSide.IntfEdges);
          Inc(H.OutSide.Refs, Weight[E.A + '->' + E.B]);
        end;
      end;
      H.InSide.BreaksAlone := IsAcyclic(pGroup, EdgeArr, '', '', U);
      H.OutSide.BreaksAlone:= IsAcyclic(pGroup, EdgeArr, '', U, '');
      { spoke->hub surface: hub symbols referenced from the other units }
      var SymRefs : TDictionary<Int64, Integer>;
      var SymUnits: TDictionary<Int64, TDictionary<string, Boolean>>;
      var HubVars: TDictionary<string, Boolean>;  { lower-case names of the hub's globals }
      SymRefs := TDictionary<Int64, Integer>.Create;
      SymUnits:= TObjectDictionary<Int64, TDictionary<string, Boolean>>.Create([doOwnsValues]);
      HubVars := TDictionary<string, Boolean>.Create;
      try
        for var P in SymUnit do
          if (P.Value = U) and (SymKind[P.Key] = skVarDecl) then HubVars.AddOrSetValue(LowerCase(SymName[P.Key]), True);
        for var V in pGroup do
        begin
          if V = U then Continue;
          for var R in RefsOf[V] do
          begin
            var T: string;
            if (R.SymbolId > 0) and SymUnit.TryGetValue(R.SymbolId, T) and (T = U) then
            begin
              { a resolved member reached through a hub global is counted under that global's
                member names below, not as a surface symbol of its own }
              if SymMember[R.SymbolId] and HubVars.ContainsKey(LowerCase(R.ReceiverText)) then Continue;
              var N: Integer;
              if not SymRefs.TryGetValue(R.SymbolId, N) then N:= 0;
              SymRefs.AddOrSetValue(R.SymbolId, N + 1);
              var Us: TDictionary<string, Boolean>;
              if not SymUnits.TryGetValue(R.SymbolId, Us) then
              begin
                Us:= TDictionary<string, Boolean>.Create;
                SymUnits.Add(R.SymbolId, Us);
              end;
              Us.AddOrSetValue(V, True);
            end;
          end;
        end;
        var Syms:= TList<TCycleHubSymbol>.Create;
        try
          for var P in SymRefs do
          begin
            var HS: TCycleHubSymbol;
            HS.Kind := KindName(SymKind[P.Key]);
            HS.Name := SymName[P.Key];
            HS.Refs := P.Value;
            HS.Units:= SymUnits[P.Key].Count;
            HS.Members:= nil;
            if SymKind[P.Key] = skVarDecl then
            begin
              { member names read through the global: refs whose receiver text is the global }
              var MemRefs : TDictionary<string, Integer>;
              var MemUnits: TDictionary<string, TDictionary<string, Boolean>>;
              MemRefs := TDictionary<string, Integer>.Create;
              MemUnits:= TObjectDictionary<string, TDictionary<string, Boolean>>.Create([doOwnsValues]);
              try
                for var V in pGroup do
                begin
                  if V = U then Continue;
                  for var R in RefsOf[V] do
                    if SameText(R.ReceiverText, HS.Name) and (R.NameText <> '') then
                    begin
                      var N: Integer;
                      if not MemRefs.TryGetValue(R.NameText, N) then N:= 0;
                      MemRefs.AddOrSetValue(R.NameText, N + 1);
                      var Us: TDictionary<string, Boolean>;
                      if not MemUnits.TryGetValue(R.NameText, Us) then
                      begin
                        Us:= TDictionary<string, Boolean>.Create;
                        MemUnits.Add(R.NameText, Us);
                      end;
                      Us.AddOrSetValue(V, True);
                    end;
                end;
                var Mems:= TList<TCycleHubMember>.Create;
                try
                  for var M in MemRefs do
                  begin
                    var HM: TCycleHubMember;
                    HM.Name := M.Key;
                    HM.Refs := M.Value;
                    HM.Units:= MemUnits[M.Key].Count;
                    Mems.Add(HM);
                  end;
                  Mems.Sort(TComparer<TCycleHubMember>.Construct(
                    function(const L, R: TCycleHubMember): Integer
                    begin
                      Result:= R.Refs - L.Refs;
                      if Result = 0 then Result:= CompareText(L.Name, R.Name);
                    end));
                  HS.Members:= Mems.ToArray;
                finally
                  Mems.Free;
                end;
              finally
                MemUnits.Free;
                MemRefs.Free;
              end;
            end;
            Syms.Add(HS);
          end;
          Syms.Sort(TComparer<TCycleHubSymbol>.Construct(
            function(const L, R: TCycleHubSymbol): Integer
            begin
              Result:= R.Refs - L.Refs;
              if Result = 0 then Result:= CompareText(L.Name, R.Name);
            end));
          H.SpokeToHub:= Syms.ToArray;
        finally
          Syms.Free;
        end;
      finally
        HubVars.Free;
        SymUnits.Free;
        SymRefs.Free;
      end;
      { hub->spoke surface: what the hub's own refs take from the other units }
      H.HubToSpoke.Construction:= 0;
      H.HubToSpoke.VarWrite    := 0;
      H.HubToSpoke.VarRead     := 0;
      H.HubToSpoke.MethodCall  := 0;
      var OutUnits:= TDictionary<string, Boolean>.Create;
      try
        for var R in RefsOf[U] do
        begin
          var T: string;
          if not ((R.SymbolId > 0) and SymUnit.TryGetValue(R.SymbolId, T) and (T <> U)) then Continue;
          OutUnits.AddOrSetValue(T, True);
          case SymKind[R.SymbolId] of
            skClass      : if SameText(R.Kind, 'read') then Inc(H.HubToSpoke.Construction);
            skConstructor: Inc(H.HubToSpoke.Construction);
            skVarDecl    : if SameText(R.Kind, 'write') then Inc(H.HubToSpoke.VarWrite)
                           else Inc(H.HubToSpoke.VarRead);
            skMethod     : if SameText(R.Kind, 'call') then Inc(H.HubToSpoke.MethodCall);
          end;
        end;
        H.HubToSpoke.Units:= OutUnits.Count;
      finally
        OutUnits.Free;
      end;
      { the lighter side: distinct surfaces to cut }
      if Length(H.SpokeToHub) <= H.HubToSpoke.Units then H.LighterSide:= 'spoke->hub'
      else H.LighterSide:= 'hub->spoke';
      Hubs.Add(H);
    end;
    Result.Hubs:= Hubs.ToArray;
  finally
    Hubs.Free;
    Weight.Free;
    RefsOf.Free;
    SymMember.Free;
    SymName.Free;
    SymKind.Free;
    SymUnit.Free;
    Edges.Free;
    InGroup.Free;
  end;
end;

function YesNo(pB: Boolean): string;
begin
  Result:= if pB then 'yes' else 'no';
end;

function CycleHubLines(const pReport: TCycleHubReport): TArray<string>;
var
  L: TList<string>;
begin
  L:= TList<string>.Create;
  try
    if Length(pReport.Hubs) = 0 then
      L.Add('      hubs: none (no single unit whose removal leaves the group acyclic)')
    else
      for var H in pReport.Hubs do
      begin
        L.Add(Format('      hub %s: in %d edges (%d impl, %d intf) %d refs, the in-side alone breaks the group: %s; ' +
          'out %d edges (%d impl, %d intf) %d refs, the out-side alone: %s',
          [H.UnitStem, H.InSide.Edges, H.InSide.Edges - H.InSide.IntfEdges, H.InSide.IntfEdges, H.InSide.Refs,
           YesNo(H.InSide.BreaksAlone), H.OutSide.Edges, H.OutSide.Edges - H.OutSide.IntfEdges, H.OutSide.IntfEdges,
           H.OutSide.Refs, YesNo(H.OutSide.BreaksAlone)]));
        var Parts:= TList<string>.Create;
        try
          for var I:= 0 to Length(H.SpokeToHub) - 1 do
          begin
            if I >= CSymbolsInText then
            begin
              Parts.Add(Format('... %d more', [Length(H.SpokeToHub) - CSymbolsInText]));
              Break;
            end;
            var S:= H.SpokeToHub[I];
            var Txt:= Format('%s %s %d refs in %d units', [S.Kind, S.Name, S.Refs, S.Units]);
            if Length(S.Members) > 0 then
            begin
              var MP:= TList<string>.Create;
              try
                for var J:= 0 to Length(S.Members) - 1 do
                begin
                  if J >= CMembersInText then
                  begin
                    MP.Add('...');
                    Break;
                  end;
                  MP.Add(Format('%s %d', [S.Members[J].Name, S.Members[J].Refs]));
                end;
                Txt:= Txt + Format(' (%d member names: %s)', [Length(S.Members), string.Join(', ', MP.ToArray)]);
              finally
                MP.Free;
              end;
            end;
            Parts.Add(Txt);
          end;
          L.Add(Format('        spoke->hub surface: %d symbols -- %s', [Length(H.SpokeToHub), string.Join('; ', Parts.ToArray)]));
        finally
          Parts.Free;
        end;
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

procedure AddCycleHubJson(const pReport: TCycleHubReport; const pGroup: TJSONObject);
var
  Arr: TJSONArray;
begin
  Arr:= TJSONArray.Create;
  for var H in pReport.Hubs do
  begin
    var JH:= TJSONObject.Create;
    JH.AddPair('unit', H.UnitStem);
    JH.AddPair('in', SideToJson(H.InSide));
    JH.AddPair('out', SideToJson(H.OutSide));
    var JS:= TJSONArray.Create;
    for var S in H.SpokeToHub do
    begin
      var JO:= TJSONObject.Create;
      JO.AddPair('kind', S.Kind);
      JO.AddPair('name', S.Name);
      JO.AddPair('refs', TJSONNumber.Create(S.Refs));
      JO.AddPair('units', TJSONNumber.Create(S.Units));
      var JM:= TJSONArray.Create;
      for var M in S.Members do
      begin
        var JMO:= TJSONObject.Create;
        JMO.AddPair('name', M.Name);
        JMO.AddPair('refs', TJSONNumber.Create(M.Refs));
        JMO.AddPair('units', TJSONNumber.Create(M.Units));
        JM.AddElement(JMO);
      end;
      JO.AddPair('members', JM);
      JS.AddElement(JO);
    end;
    JH.AddPair('spoke_to_hub', JS);
    var JT:= TJSONObject.Create;
    JT.AddPair('construction', TJSONNumber.Create(H.HubToSpoke.Construction));
    JT.AddPair('var_write', TJSONNumber.Create(H.HubToSpoke.VarWrite));
    JT.AddPair('var_read', TJSONNumber.Create(H.HubToSpoke.VarRead));
    JT.AddPair('method_call', TJSONNumber.Create(H.HubToSpoke.MethodCall));
    JT.AddPair('units', TJSONNumber.Create(H.HubToSpoke.Units));
    JH.AddPair('hub_to_spoke', JT);
    JH.AddPair('lighter_side', H.LighterSide);
    Arr.AddElement(JH);
  end;
  pGroup.AddPair('hubs', Arr);
  pGroup.AddPair('zero_ref_edges', TJSONNumber.Create(pReport.ZeroRefEdges));
end;

end.
