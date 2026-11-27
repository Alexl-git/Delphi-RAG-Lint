unit DRagLint.Charts.Q.ArchDelta;

{ drag-lint 1.56 -- lane G47: the chart question `architecture-delta` (`ask architecture-delta --counterpart-db <before>`).
  G-47: a picture of what changed between two indexes. The project index (--db) is the AFTER side, the
  counterpart index (--counterpart-db) the BEFORE side; the question is refused without it.

  Data (both indexes read-only, through TChartsIndex.Query and the clone guard): a node is an indexed unit
  (symbols.kind = 'unit'); an edge is a unit_uses entry whose target is an indexed unit of the SAME index
  (library uses are not architecture and are not drawn; self-uses are dropped). Names compare case-blind.
  The two sides are turned into sorted items ('N <unit>', 'E <from> -> <to>') and diffed by the compare
  verb's own engine (DRagLint.Charts.Diff.MyersDiff); nothing here re-implements a diff.
  Colours: added green, removed red, unchanged grey. A UNIT that exists on one side only is filled; an edge
  that exists on one side only is coloured, a removed edge dashed. Only the touched units (an added or removed
  unit, or an end of an added or removed edge, or a member of an introduced cycle) are drawn, with every unchanged edge among them; Cap (default 60)
  bounds those units, the busiest first, and the rest are counted as hidden.
  Cycles: a cycle is a strongly connected component of two or more units. An AFTER cycle is INTRODUCED when no
  single BEFORE cycle holds all its members; a BEFORE cycle is RESOLVED when no single AFTER cycle holds all its
  members. Members of an introduced cycle get a thick red outline, and its added edges are drawn thick.
  Counts: LeftCount = edges added + removed, RightCount = cycles introduced. }

interface

const
  /// <summary>The registered question id.</summary>
  ARCH_DELTA_ID = 'architecture-delta';

implementation

uses
  System.SysUtils, System.Math, System.Generics.Collections, System.Generics.Defaults,
  DRagLint.Charts.Question, DRagLint.Charts.Index, DRagLint.Charts.Text, DRagLint.Charts.Dot,
  DRagLint.Charts.Tools, DRagLint.Charts.Diff;

const
  DEFAULT_CAP = 60;
  ADDED_INK = '#2F9E44';
  ADDED_FILL = '#E6F6E9';
  REMOVED_INK = '#E03131';
  REMOVED_FILL = '#FDE8E8';
  SAME_INK = '#9AA3B2';
  SAME_FILL = '#F4F5F7';
  CYCLE_INK = '#C92A2A';
  CYCLE_PEN = '3';
  EDGE_PEN = '1.2';
  NODE_PEN = '1';
  CYCLE_RANK = 1000;
  ITEM_NODE = 'N ';
  EDGE_ARROW = ' -> ';

type
  // One side of the comparison: the units (lower-case key -> display name) and the unit-to-unit edges.
  TUnitGraph = class
  public
    Units: TDictionary<string, string>;   // dl:ok public-field@a6e1 -- REVIEWED 2026-11-27: unit-private data holder of one question, no invariant to protect
    Edges: TDictionary<string, string>;   // dl:ok public-field@0be1 -- REVIEWED 2026-11-27: as Units; 'from|to' (lower-case) -> ''
    constructor Create;
    destructor Destroy; override;
  end;

  // One strongly connected component of two or more units, as a sorted lower-case member list.
  TCycle = TArray<string>;

constructor TUnitGraph.Create;
begin
  inherited Create;
  Units:= TDictionary<string, string>.Create;
  Edges:= TDictionary<string, string>.Create;
end;

destructor TUnitGraph.Destroy;
begin
  Edges.Free;
  Units.Free;
  inherited Destroy;
end;

function EdgeKey(const pFrom, pTo: string): string;
begin
  Result:= pFrom + '|' + pTo;
end;

function EdgeFrom(const pKey: string): string;
begin
  Result:= pKey.Substring(0, pKey.IndexOf('|'));
end;

function EdgeTo(const pKey: string): string;
begin
  Result:= pKey.Substring(pKey.IndexOf('|') + 1);
end;

// reads the units and the unit-to-unit edges of one index
procedure LoadGraph(const pIndex: TChartsIndex; const pGraph: TUnitGraph);
begin
  var UnitRows:= pIndex.Query('SELECT s.qualified_name AS q FROM symbols s WHERE s.kind = ''unit'' ORDER BY LOWER(s.qualified_name), s.id');
  try
    for var R in UnitRows do
      if not pGraph.Units.ContainsKey(R.S('q').ToLowerInvariant) then
        pGraph.Units.Add(R.S('q').ToLowerInvariant, R.S('q'));
  finally
    UnitRows.Free;
  end;
  var EdgeRows:= pIndex.Query('SELECT DISTINCT LOWER(su.qualified_name) AS src, LOWER(uu.unit_name) AS dst' + sLineBreak +
    '  FROM unit_uses uu JOIN symbols su ON su.file_id = uu.file_id AND su.kind = ''unit''');
  try
    for var E in EdgeRows do
      if (E.S('src') <> E.S('dst')) and pGraph.Units.ContainsKey(E.S('src')) and pGraph.Units.ContainsKey(E.S('dst')) then
        pGraph.Edges.AddOrSetValue(EdgeKey(E.S('src'), E.S('dst')), '');
  finally
    EdgeRows.Free;
  end;
end;

// the graph as sorted diff items: 'N unit' and 'E from -> to' (the compare verb's item shape)
function GraphItems(const pGraph: TUnitGraph): TArray<TDiffItem>;
begin
  Result:= [];
  for var U in pGraph.Units.Keys do
    Result:= Result + [TDiffItem.Make(ITEM_NODE + U, ITEM_NODE + U)];
  for var K in pGraph.Edges.Keys do
  begin
    var Text:= 'E ' + EdgeFrom(K) + EDGE_ARROW + EdgeTo(K);
    Result:= Result + [TDiffItem.Make(Text, Text)];
  end;
  TArray.Sort<TDiffItem>(Result, TComparer<TDiffItem>.Construct(
    function(const pA, pB: TDiffItem): Integer
    begin
      Result:= string.CompareOrdinal(pA.Key, pB.Key);
    end));
end;

// the strongly connected components of two or more units (Tarjan), each member list sorted
function FindCycles(const pGraph: TUnitGraph): TArray<TCycle>;
var
  Names: TArray<string>;
  Adj: TArray<TArray<Integer>>;
  Index, Low: TArray<Integer>;
  OnStack: TArray<Boolean>;
  Stack: TList<Integer>;
  Counter: Integer;
  Found: TList<TCycle>;

  procedure Visit(pNode: Integer);
  begin
    Index[pNode]:= Counter;
    Low[pNode]:= Counter;   // dl:ok index-possibly-out-of-range@bcad -- REVIEWED 2026-11-27: pNode is a position in Names, which every array here is sized from
    Inc(Counter);
    Stack.Add(pNode);
    OnStack[pNode]:= True;
    for var Next in Adj[pNode] do
      if Index[Next] < 0 then
      begin
        Visit(Next);
        Low[pNode]:= Min(Low[pNode], Low[Next]);
      end
      else if OnStack[Next] then
        Low[pNode]:= Min(Low[pNode], Index[Next]);
    if Low[pNode] = Index[pNode] then
    begin
      var Members: TCycle:= [];
      var Top: Integer;
      repeat
        Top:= Stack[Stack.Count - 1];
        Stack.Delete(Stack.Count - 1);
        OnStack[Top]:= False;
        Members:= Members + [Names[Top]];
      until Top = pNode;
      if Length(Members) > 1 then
      begin
        TArray.Sort<string>(Members, TStringComparer.Ordinal);
        Found.Add(Members);
      end;
    end;
  end;

begin
  Names:= pGraph.Units.Keys.ToArray;
  TArray.Sort<string>(Names, TStringComparer.Ordinal);
  var Pos:= TDictionary<string, Integer>.Create;
  Stack:= TList<Integer>.Create;
  Found:= TList<TCycle>.Create;
  try
    SetLength(Adj, Length(Names));
    SetLength(Index, Length(Names));
    SetLength(Low, Length(Names));
    SetLength(OnStack, Length(Names));
    for var K:= 0 to High(Names) do
    begin
      Pos.Add(Names[K], K);
      Index[K]:= -1;
    end;
    for var Key in pGraph.Edges.Keys do
    begin
      var From:= Pos[EdgeFrom(Key)];   // dl:ok index-possibly-out-of-range@be06 -- REVIEWED 2026-11-27: LoadGraph adds an edge only between two indexed units, so both ends are in Pos
      Adj[From]:= Adj[From] + [Pos[EdgeTo(Key)]];
    end;
    Counter:= 0;
    for var K:= 0 to High(Names) do
      if Index[K] < 0 then
        Visit(K);
    Result:= Found.ToArray;
  finally
    Found.Free;
    Stack.Free;
    Pos.Free;
  end;
end;

// the cycles of pSide that no single cycle of pOther holds whole
function CyclesNotIn(const pSide, pOther: TArray<TCycle>): TArray<TCycle>;
begin
  Result:= [];
  for var C in pSide do
  begin
    var Held:= False;
    for var O in pOther do
    begin
      var All:= True;
      for var M in C do
        if not TArray.Contains<string>(O, M) then
          All:= False;
      if All then
        Held:= True;
    end;
    if not Held then
      Result:= Result + [C];
  end;
end;

function InAnyCycle(const pCycles: TArray<TCycle>; const pUnit: string): Boolean;
begin
  Result:= False;
  for var C in pCycles do
    if TArray.Contains<string>(C, pUnit) then
      Exit(True);
end;

function InSameCycle(const pCycles: TArray<TCycle>; const pFrom, pTo: string): Boolean;
begin
  Result:= False;
  for var C in pCycles do
    if TArray.Contains<string>(C, pFrom) and TArray.Contains<string>(C, pTo) then
      Exit(True);
end;

function NodeLine(const pId, pLabel: string; pDelta: TDiffOp; pCycle: Boolean): string;
begin
  var Ink:= SAME_INK;
  var Fill:= SAME_FILL;
  if pDelta = doInsert then
  begin
    Ink:= ADDED_INK;
    Fill:= ADDED_FILL;
  end
  else if pDelta = doDelete then
  begin
    Ink:= REMOVED_INK;
    Fill:= REMOVED_FILL;
  end;
  Result:= Format('  %s [label="%s", color="%s", fillcolor="%s", penwidth=%s];', [pId, XmlText(pLabel),
    if pCycle then CYCLE_INK else Ink, Fill, if pCycle then CYCLE_PEN else NODE_PEN]);
end;

function EdgeLine(const pFromId, pToId: string; pDelta: TDiffOp; pCycle: Boolean): string;
begin
  var Ink:= SAME_INK;
  var Style:= 'solid';
  if pDelta = doInsert then
    Ink:= ADDED_INK
  else if pDelta = doDelete then
  begin
    Ink:= REMOVED_INK;
    Style:= 'dashed';
  end;
  Result:= Format('  %s -> %s [color="%s", style=%s, penwidth=%s];', [pFromId, pToId, Ink, Style,
    if pCycle then CYCLE_PEN else EDGE_PEN]);
end;

/// <summary>Answers `architecture-delta`: the unit dependency graph before (counterpart index) and after (project index).</summary>
/// <param name="pArgs">The question arguments; Target is ignored (project-wide); CounterpartDb is the BEFORE index and is required; Cap bounds the touched units drawn.</param>
/// <param name="pOutDir">Where dot, svg, plain, png and pdf are written.</param>
/// <returns>The chart result: LeftCount = edges added + removed, RightCount = cycles introduced.</returns>
/// <exception cref="EChartsQuestion">No counterpart index was given.</exception>
/// <remarks>Read-only on both indexes (the counterpart goes through the clone guard). No change is an answer (a picture with a note). Meta fields: UnitsAdded, UnitsRemoved, EdgesAdded, EdgesRemoved, EdgesUnchanged, CyclesIntroduced, CyclesResolved, Shown, Hidden, ClickTargets, Expected, AllClickable.</remarks>
function Emit(const pArgs: TQuestionArgs; const pOutDir: string): TChartResult;
begin
  if pArgs.CounterpartDb = '' then
    raise EChartsQuestion.Create('architecture-delta needs the before side: give --counterpart-db <index of the earlier state>');
  var After:= TUnitGraph.Create;
  var Before:= TUnitGraph.Create;
  var Sb:= TStringBuilder.Create;
  var UnitDelta:= TDictionary<string, TDiffOp>.Create;
  var EdgeDelta:= TDictionary<string, TDiffOp>.Create;
  var Touched:= TDictionary<string, Integer>.Create;
  var Drawn:= TDictionary<string, string>.Create;   // unit -> dot id
  try
    var Note: string;
    var AfterIndex:= TChartsIndex.Create(pArgs.GuardedDb);
    try
      LoadGraph(AfterIndex, After);
    finally
      AfterIndex.Free;
    end;
    var BeforeIndex:= TChartsIndex.Create(CloneDb(pArgs.CounterpartDb, pArgs.CloneRoot, Note));
    try
      LoadGraph(BeforeIndex, Before);
    finally
      BeforeIndex.Free;
    end;

    // the compare verb's diff engine over the two item lists
    var OldItems:= GraphItems(Before);
    var NewItems:= GraphItems(After);
    var UnitsAdded:= 0;
    var UnitsRemoved:= 0;
    var EdgesAdded:= 0;
    var EdgesRemoved:= 0;
    for var Edit in MyersDiff(OldItems, NewItems) do
    begin
      if Edit.Op = doEqual then
        Continue;
      var Item:= if Edit.Op = doInsert then NewItems[Edit.NewIndex] else OldItems[Edit.OldIndex];
      var Body:= Item.Key.Substring(Length(ITEM_NODE));
      if Item.Key.StartsWith(ITEM_NODE) then
      begin
        UnitDelta.Add(Body, Edit.Op);
        if Edit.Op = doInsert then
          Inc(UnitsAdded)
        else
          Inc(UnitsRemoved);
      end
      else
      begin
        var Cut:= Body.IndexOf(EDGE_ARROW);
        EdgeDelta.Add(EdgeKey(Body.Substring(0, Cut), Body.Substring(Cut + Length(EDGE_ARROW))), Edit.Op);
        if Edit.Op = doInsert then
          Inc(EdgesAdded)
        else
          Inc(EdgesRemoved);
      end;
    end;

    var Introduced:= CyclesNotIn(FindCycles(After), FindCycles(Before));
    var Resolved:= CyclesNotIn(FindCycles(Before), FindCycles(After));

    // the touched units, the busiest first, bounded by Cap
    for var U in UnitDelta.Keys do
      Touched.AddOrSetValue(U, 0);
    for var K in EdgeDelta.Keys do
    begin
      Touched.AddOrSetValue(EdgeFrom(K), 0);
      Touched.AddOrSetValue(EdgeTo(K), 0);
    end;
    for var K in EdgeDelta.Keys do
    begin
      Touched[EdgeFrom(K)]:= Touched[EdgeFrom(K)] + 1;
      Touched[EdgeTo(K)]:= Touched[EdgeTo(K)] + 1;
    end;
    // the members of an introduced cycle are drawn too (and survive the cap): the picture must show the loop whole
    for var C in Introduced do
      for var M in C do
      begin
        var Rank: Integer;
        if not Touched.TryGetValue(M, Rank) then
          Rank:= 0;
        Touched.AddOrSetValue(M, Rank + CYCLE_RANK);
      end;
    var Order:= Touched.Keys.ToArray;
    TArray.Sort<string>(Order, TComparer<string>.Construct(
      function(const pA, pB: string): Integer
      begin
        Result:= Touched[pB] - Touched[pA];
        if Result = 0 then
          Result:= string.CompareOrdinal(pA, pB);
      end));
    var Cap:= if pArgs.Cap > 0 then pArgs.Cap else DEFAULT_CAP;
    var Total:= Length(Order);
    if Total > Cap then
      SetLength(Order, Cap);
    TArray.Sort<string>(Order, TStringComparer.Ordinal);
    for var K:= 0 to High(Order) do
      Drawn.Add(Order[K], 'u' + IntToStr(K));

    Sb.AppendLine('digraph architecture_delta {');
    Sb.AppendLine('  rankdir=LR; bgcolor="transparent"; nodesep=0.3;');
    Sb.AppendLine('  node [fontname="Consolas", fontsize=12, shape=box, style="rounded,filled"];');
    Sb.AppendLine(Format('  graph [label="%d unit(s) added, %d removed; %d edge(s) added, %d removed, %d unchanged; %d cycle(s) introduced, %d resolved%s", labelloc=b];',
      [UnitsAdded, UnitsRemoved, EdgesAdded, EdgesRemoved, After.Edges.Count - EdgesAdded,
       Length(Introduced), Length(Resolved),
       if Total > Length(Order) then Format('; %d unit(s) not shown (cap %d)', [Total - Length(Order), Cap]) else '']));
    for var U in Order do
    begin
      var Op: TDiffOp;
      if not UnitDelta.TryGetValue(U, Op) then
        Op:= doEqual;
      var Display: string;
      if not After.Units.TryGetValue(U, Display) then
        Display:= Before.Units[U];
      Sb.AppendLine(NodeLine(Drawn[U], Display, Op, InAnyCycle(Introduced, U)));
    end;
    var EdgeKeys:= TList<string>.Create;
    try
      EdgeKeys.AddRange(After.Edges.Keys);
      for var K in Before.Edges.Keys do
        if not After.Edges.ContainsKey(K) then
          EdgeKeys.Add(K);
      EdgeKeys.Sort(TStringComparer.Ordinal);
      for var K in EdgeKeys do
        if Drawn.ContainsKey(EdgeFrom(K)) and Drawn.ContainsKey(EdgeTo(K)) then
        begin
          var Op: TDiffOp;
          if not EdgeDelta.TryGetValue(K, Op) then
            Op:= doEqual;
          Sb.AppendLine(EdgeLine(Drawn[EdgeFrom(K)], Drawn[EdgeTo(K)], Op,
            (Op = doInsert) and InSameCycle(Introduced, EdgeFrom(K), EdgeTo(K))));
        end;
    finally
      EdgeKeys.Free;
    end;
    if Total = 0 then
      Sb.AppendLine('  none [label="no unit or uses edge changed between the two indexes", shape=note, fillcolor="white"];');
    Sb.AppendLine('}');
    var Msgs: TArray<string>;
    Result.Layout:= DotLayout(pArgs.Dot, Sb.ToString, pOutDir, 'architecture_delta', Msgs);
    Result.LeftCount:= EdgesAdded + EdgesRemoved;
    Result.RightCount:= Length(Introduced);
    Result.ClickTargets:= Result.Layout.Anchors;
    Result.AllClickable:= True;
    Result.Fields:= [TMetaField.Int('UnitsAdded', UnitsAdded), TMetaField.Int('UnitsRemoved', UnitsRemoved),
      TMetaField.Int('EdgesAdded', EdgesAdded), TMetaField.Int('EdgesRemoved', EdgesRemoved),
      TMetaField.Int('EdgesUnchanged', After.Edges.Count - EdgesAdded),
      TMetaField.Int('CyclesIntroduced', Length(Introduced)), TMetaField.Int('CyclesResolved', Length(Resolved)),
      TMetaField.Int('Shown', Length(Order)), TMetaField.Int('Hidden', Total - Length(Order)),
      TMetaField.Int('ClickTargets', Result.Layout.Anchors), TMetaField.Int('Expected', 0),
      TMetaField.Bool('AllClickable', Result.AllClickable)];
  finally
    Drawn.Free;
    Touched.Free;
    EdgeDelta.Free;
    UnitDelta.Free;
    Sb.Free;
    Before.Free;
    After.Free;
  end;
end;

initialization
  RegisterChartQuestion(ARCH_DELTA_ID, Emit);

end.
