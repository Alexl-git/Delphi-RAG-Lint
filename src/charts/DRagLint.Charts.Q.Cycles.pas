unit DRagLint.Charts.Q.Cycles;

(* The `cycles` question in-process: a port of charts\src\Emit-Cycles.ps1 (spec s11; the PS
  output is the reference, P3). The unit-level circular dependencies of the whole project, or
  of the groups containing one unit, drawn as one cluster per group with an arrow for every
  MEASURED uses edge between its members.

  A "cycle" here is a strongly-connected component, not a ring: the verb's `units[]` is NOT in
  traversal order, so no arrow is ever inferred from member order. Every arrow is a unit_uses
  edge read from the index, labelled with its line, coloured by its OWN section, or it is not
  drawn. Anchoring is case-blind; a member the index cannot resolve is counted and shown as a
  note row. `interface_cycle: true` means ONE interface edge among the members: the verdict
  counts the sections and says "interface cycle" only for an all-interface loop
  (TestInterfaceLoop), which is the loop the compiler refuses.

  Data route (H9, ruling R1): the PS spawns `cycles --db <db> --format json`, whose document
  DRagLint.CLI.DoCycles builds. The port carries a PRIVATE line-for-line mirror of the SCC
  half of DoCycles (UnitCycles: the adjacency, Tarjan over `for K in Adj.Keys`, members in POP
  order), because the group order and the member order come from TDictionary enumeration over
  the same insertion sequence, so only an identical mirror reproduces them. No JSON is built.
  The mirror is an engine-move candidate (ComputeUnitCycles in DRagLint.Report.CyclePlan); it
  is NOT moved here, the CLI is untouched.

  Not ported: the `cycles --plan` verdict (-Playbook, ruling R2: New-DiagramArtifact never
  passes it, so the PS verdict is always the counted one) and -MaxCycles (the const MAX_CYCLES
  is what NDA passes). The PS `cycles returned no document` refusal cannot fire in-process.

  PS traps closed: `-eq`, `-ne`, `-contains` and hashtable keys are case-blind
  (TIStringComparer.Ordinal, SameText); ToLowerInvariant, not LowerCase, on the unit name;
  `Sort-Object -Unique` is SortUniqueNames; the line sort of the out-edges goes through TPsSort
  (two uses on one line tie); the PS -FailOnTruncate 200-row cap has no counterpart
  (TChartsIndex.Query cuts nothing); Write-Host is not output. *)

interface

const
  /// <summary>The registered question id.</summary>
  CYCLES_ID = 'cycles';
  /// <summary>Most cycle groups drawn; the PS -MaxCycles default, which New-DiagramArtifact never overrides.</summary>
  MAX_CYCLES = 12;

implementation

uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.Generics.Defaults,
  System.RegularExpressions, DRagLint.Core.Model, DRagLint.Core.Interfaces, DRagLint.Storage.SQLite,
  DRagLint.Charts.Question,
  DRagLint.Charts.Index, // dl:unit DRagLint.Charts.Index accepted -- the resolver, the SQL text escaper and CompareGroupKeys travel with TChartsIndex, so the refusal texts and the sort order cannot drift from the other questions
  DRagLint.Charts.Sql, DRagLint.Charts.Text, DRagLint.Charts.Dot, DRagLint.Charts.PsSort, DRagLint.Charts.Checks;

const
  IMPL_BORDER = '#B45309';
  IMPL_FILL = '#FEF6EC';
  IMPL_HDR = '#B45309';
  INTF_BORDER = '#B02A37';
  INTF_FILL = '#FDECEE';
  INTF_HDR = '#B02A37';
  CLEAN_BORDER = '#0F766E';
  CLEAN_FILL = '#E2F1EF';
  CLEAN_HDR = '#0F766E';
  FOCUS_BORDER = '#3B5BDB';
  FOCUS_FILL = '#EDF2FF';
  FOCUS_HDR = '#3B5BDB';
  ROW_INK = '#1F2933';
  LINE_INK = '#8A94A6';
  FONT_MONO = 'Consolas';
  FONT_SANS = 'Segoe UI';
  PROJECT_TARGET = 'project';

type
  // one strongly-connected group of the verb's document: Units in POP order
  TCycleGroup = record
    Units: TArray<string>;
    Size: Integer;
    InterfaceCycle: Boolean;
  end;

  // a group with its 1-based position in the FULL list (the numbering the cluster titles carry)
  TSelected = record
    Ordinal: Integer;
    Cycle: TCycleGroup;
  end;

  // one measured uses edge leaving a unit; Edge is borrowed from the query result
  TOutEdge = record
    To_: string;
    Edge: TIndexRow;
  end;

  TUnitMap = TDictionary<string, TIndexRow>;

function MakeStyle(const pBorder, pFill, pHdr: string): TClusterStyle;
begin
  Result:= TClusterStyle.Make(pBorder, pFill, pHdr);
  Result.RowInk:= ROW_INK;
  Result.LineInk:= LINE_INK;
  Result.FontSans:= FONT_SANS;
end;

// Mirror of DRagLint.CLI.pas DoCycles, the SCC half (H9). Every dictionary type, the insertion
// order and `for K in Adj.Keys` are the verb's own: the group order and the member order come
// from that enumeration.
function UnitCycles(const pStore: ISymbolStore): TArray<TCycleGroup>;
var
  Adj: TObjectDictionary<string, TList<string>>;
  IntfEdges: TDictionary<string, Boolean>;
  TIndex: TDictionary<string, Integer>;
  Lowlink: TDictionary<string, Integer>;
  OnStack: TDictionary<string, Boolean>;
  Stack: TList<string>;
  Sccs: TList<TArray<string>>;
  Counter: Integer;

  function UnitNameOfFile(const pPath: string): string;
  begin
    // indexed paths may use '/': normalise so ExtractFileName strips the directory
    Result:= LowerCase(ChangeFileExt(ExtractFileName(StringReplace(pPath, '/', '\', [rfReplaceAll])), ''));
  end;

  procedure StrongConnect(const pV: string);
  var
    W, Top: string;
    Comp: TList<string>;
    Neighbors: TList<string>;
  begin
    TIndex.AddOrSetValue(pV, Counter);
    Lowlink.AddOrSetValue(pV, Counter);
    Inc(Counter);
    Stack.Add(pV);
    OnStack.AddOrSetValue(pV, True);
    if Adj.TryGetValue(pV, Neighbors) then
      for W in Neighbors do
      begin
        if not TIndex.ContainsKey(W) then
        begin
          if Adj.ContainsKey(W) then
            StrongConnect(W)
          else
            Continue;  // external/library unit: a leaf, cannot be part of a cycle
          if Lowlink[W] < Lowlink[pV] then
            Lowlink[pV]:= Lowlink[W];
        end
        else if OnStack.ContainsKey(W) and OnStack[W] then
          if TIndex[W] < Lowlink[pV] then
            Lowlink[pV]:= TIndex[W];
      end;
    if Lowlink[pV] = TIndex[pV] then
    begin
      Comp:= TList<string>.Create;
      try
        repeat
          Top:= Stack[Stack.Count - 1];
          Stack.Delete(Stack.Count - 1);
          OnStack.AddOrSetValue(Top, False);
          Comp.Add(Top);
        until Top = pV;
        if Comp.Count > 1 then
          Sccs.Add(Comp.ToArray);
      finally
        Comp.Free;
      end;
    end;
  end;

begin
  Adj:= TObjectDictionary<string, TList<string>>.Create([doOwnsValues]);
  IntfEdges:= TDictionary<string, Boolean>.Create;
  TIndex:= TDictionary<string, Integer>.Create;
  Lowlink:= TDictionary<string, Integer>.Create;
  OnStack:= TDictionary<string, Boolean>.Create;
  Stack:= TList<string>.Create;
  Sccs:= TList<TArray<string>>.Create;
  try
    // the adjacency from every indexed file's uses clauses
    for var Fid in pStore.GetAllFileIds do
    begin
      var FilePath:= pStore.GetFilePath(Fid);
      if not SameText(ExtractFileExt(FilePath), '.pas') then
        Continue;
      var UFrom:= UnitNameOfFile(FilePath);
      if UFrom = '' then
        Continue;
      var L: TList<string>;
      if not Adj.TryGetValue(UFrom, L) then
      begin
        L:= TList<string>.Create;
        Adj.AddOrSetValue(UFrom, L);
      end;
      for var Uo in pStore.GetUnitUsesForFile(Fid) do
      begin
        var UTo:= LowerCase(Uo.UnitName);
        if UTo = '' then
          Continue;
        if not L.Contains(UTo) then
          L.Add(UTo);
        if Uo.Section = uusInterface then
          IntfEdges.AddOrSetValue(UFrom + '->' + UTo, True);
      end;
    end;

    // Tarjan SCC over the in-project units
    Counter:= 0;
    for var K in Adj.Keys do
      if not TIndex.ContainsKey(K) then
        StrongConnect(K);

    Result:= [];
    for var Comp in Sccs do
    begin
      var G: TCycleGroup;
      G.Units:= Comp;
      G.Size:= Length(Comp);
      G.InterfaceCycle:= False;
      for var A in Comp do
        for var B in Comp do
          if (A <> B) and IntfEdges.ContainsKey(A + '->' + B) then
            G.InterfaceCycle:= True;
      Result:= Result + [G];
    end;
  finally
    Sccs.Free;
    Stack.Free;
    OnStack.Free;
    Lowlink.Free;
    TIndex.Free;
    IntfEdges.Free;
    Adj.Free;
  end;
end;

// does the group list pNeedle (already lower-cased) among its members (`-contains`, case-blind)
function GroupHasMember(const pGroup: TCycleGroup; const pNeedle: string): Boolean;
begin
  Result:= False;
  for var U in pGroup.Units do
    if U.ToLowerInvariant = pNeedle then
      Exit(True);
end;

// every measured intra-group edge leaving pFrom, in line order (PS Get-OutEdges). Sorted, not left
// in the verb's member order: the row anchors to the FIRST of these (R3 measured the difference).
function OutEdges(const pEdgeKey: TUnitMap; const pFrom: string; const pMembers: TArray<string>): TArray<TOutEdge>;
begin
  Result:= [];
  for var M in pMembers do
  begin
    if SameText(M, pFrom) then
      Continue;
    var Edge: TIndexRow;
    if pEdgeKey.TryGetValue(pFrom + '|' + M, Edge) then
    begin
      var O: TOutEdge;
      O.To_:= M;
      O.Edge:= Edge;
      Result:= Result + [O];
    end;
  end;
  TPsSort<TOutEdge>.Sort(Result,
    function(const pA, pB: TOutEdge): Integer
    begin
      Result:= pA.Edge.I('line') - pB.Edge.I('line');
    end);
end;

// the focus table (PS 332-346): not AddRowCluster, its own grammar
function FocusTable(const pTitle: string; pTotal, pShown, pDrawn, pAnchored, pUnanchored, pHidden: Integer;  // dl:ok too-many-parameters@a840 -- REVIEWED 2026-10-17: the parameters are the counters the PS focus table prints, each one line of it; a record would only rename them
  const pNotes: TList<string>): string;
begin
  var Tbl:= TStringBuilder.Create;
  try
    Tbl.Append('<TABLE BORDER="0" CELLBORDER="0" CELLSPACING="3" CELLPADDING="5">');
    Tbl.Append(Format('<TR><TD ALIGN="LEFT" BGCOLOR="%s"><FONT COLOR="#FFFFFF" FACE="%s" POINT-SIZE="14"><B> %s </B></FONT></TD></TR>',
      [FOCUS_HDR, FONT_SANS, XmlText(pTitle)]));
    AddDisclosureRow(Tbl, Format('%d cycle(s) in this index  &#183;  %d shown', [pTotal, pShown]), LINE_INK);
    AddDisclosureRow(Tbl, Format('%d measured uses edge(s) drawn  &#183;  %d anchored row(s)', [pDrawn, pAnchored]), LINE_INK);
    if pUnanchored > 0 then
      AddDisclosureRow(Tbl, Format('%d member(s) could not be anchored', [pUnanchored]), LINE_INK);
    AddDisclosureRow(Tbl, 'arrows are uses edges read from the index, not the order the verb lists members in', LINE_INK);
    var Disc:= DisclosureText(pHidden, 0, 'cycles');
    if Disc <> '' then
      AddDisclosureRow(Tbl, Disc, LINE_INK);
    for var N in pNotes do
      AddDisclosureRow(Tbl, N, LINE_INK);
    Tbl.Append('</TABLE>');
    Result:= Tbl.ToString;
  finally
    Tbl.Free;
  end;
end;

/// <summary>Answers `cycles`: the project's unit-cycle groups, or the groups containing one unit, with every measured uses edge between their members.</summary>
/// <param name="pArgs">The question arguments; Target is `project` (every group) or a unit name (case-blind); Cap is not read.</param>
/// <param name="pOutDir">Where dot, svg, plain, png and pdf are written.</param>
/// <returns>The chart result; LeftCount is the total group count, RightCount the drawn edge count.</returns>
/// <exception cref="EChartsQuestion">The unit is in no cycle although cycles exist.</exception>
/// <remarks>Opens a read-only TSQLiteSymbolStore beside the TChartsIndex (two read-only handles on one file) for the Tarjan mirror. Zero cycles is an answer, not a refusal.</remarks>
function Emit(const pArgs: TQuestionArgs; const pOutDir: string): TChartResult;  // dl:ok deep-nesting@5be6 -- REVIEWED 2026-10-17: ports the one-script PS body line for line (H9-H13); splitting it would scatter the shared counters and the dot buffer
begin
  var Store: ISymbolStore:= TSQLiteSymbolStore.Create(pArgs.GuardedDb, True);
  var Index:= TChartsIndex.Create(pArgs.GuardedDb);
  var UnitRows: TObjectList<TIndexRow>:= nil;
  var EdgeRows: TObjectList<TIndexRow>:= nil;
  try
    { ---- 1. the cycles themselves (PS 110-115) ---- }
    var Cycles:= UnitCycles(Store);

    { ---- 3. filter to the selection (PS 133-157) ---- }
    var Wanted:= if SameText(pArgs.Target, PROJECT_TARGET) then '' else pArgs.Target;
    var Needle:= Wanted.ToLowerInvariant;
    var Selected: TArray<TSelected>:= [];
    for var I:= 0 to High(Cycles) do
      if (Wanted = '') or GroupHasMember(Cycles[I], Needle) then
      begin
        var Item: TSelected;
        Item.Ordinal:= I + 1;
        Item.Cycle:= Cycles[I];
        Selected:= Selected + [Item];
      end;
    if (Wanted <> '') and (Length(Selected) = 0) and (Length(Cycles) > 0) then
      raise EChartsQuestion.Create(Format('%s is in no cycle in this index (%d cycle(s) exist). ' +
        'Run without -Unit to see them, or check the spelling -- the verb lowercases unit names.', [Wanted, Length(Cycles)]));
    var TotalCycles:= Length(Cycles);
    var Top:= TRanked<TSelected>.TopRanked(Selected, MAX_CYCLES, nil);
    Selected:= Top.Shown;

    { ---- 4. resolve every member unit to a file, case-blind (PS 159-169) ---- }
    var NameList: TArray<string>:= [];
    for var S in Selected do
      for var U in S.Cycle.Units do
        NameList:= NameList + [U.ToLowerInvariant];
    var Members:= SortUniqueNames(NameList);
    var UnitRow:= TUnitMap.Create(TIStringComparer.Ordinal);
    var EdgeKey:= TUnitMap.Create(TIStringComparer.Ordinal);
    try
      if Length(Members) > 0 then
      begin
        UnitRows:= Index.Query(
          'SELECT s.qualified_name AS q, f.path AS path, f.id AS fid, s.start_line AS line' + sLineBreak +
          '  FROM symbols s JOIN files f ON f.id = s.file_id' + sLineBreak +
          ' WHERE s.kind = ''unit'' AND LOWER(s.qualified_name) IN (' + TChartsIndex.SqlInList(Members) + ')');
        for var R in UnitRows do
          UnitRow.AddOrSetValue(R.S('q').ToLowerInvariant, R);

        { ---- 5. the REAL edges among those members (PS 171-189) ---- }
        var InList:= TChartsIndex.SqlInList(Members);
        EdgeRows:= Index.Query(
          'SELECT LOWER(su.qualified_name) AS src, LOWER(uu.unit_name) AS dst,' + sLineBreak +
          '       uu.section AS section, uu.start_line AS line, sf.path AS path' + sLineBreak +
          '  FROM unit_uses uu' + sLineBreak +
          '  JOIN files sf ON sf.id = uu.file_id' + sLineBreak +
          '  JOIN symbols su ON su.file_id = sf.id AND su.kind = ''unit''' + sLineBreak +
          ' WHERE LOWER(su.qualified_name) IN (' + InList + ') AND LOWER(uu.unit_name) IN (' + InList + ')');
        for var E in EdgeRows do
        begin
          var K:= E.S('src') + '|' + E.S('dst');
          if not EdgeKey.ContainsKey(K) then
            EdgeKey.Add(K, E);
        end;
      end;

      // the whole edge map for TestInterfaceLoop, which only looks up member pairs
      var AllEdges: TArray<TUnitEdge>:= [];
      for var E in EdgeKey.Values do
      begin
        var UE: TUnitEdge;
        UE.Src:= E.S('src');
        UE.Dst:= E.S('dst');
        UE.Section:= E.S('section');
        AllEdges:= AllEdges + [UE];
      end;

      { ---- 6. dot (PS 207-319) ---- }
      var Sb:= TStringBuilder.Create;
      var EdgeList:= TList<string>.Create;
      var FocusNote:= TList<string>.Create;
      try
        Sb.AppendLine('digraph cycles {');
        Sb.AppendLine('  rankdir=LR; bgcolor="transparent"; compound=true;');
        Sb.AppendLine('  nodesep=0.4; ranksep=0.9; splines=spline;');
        Sb.AppendLine(Format('  graph [fontname="%s"];', [FONT_SANS]));
        Sb.AppendLine(Format('  node  [shape=plaintext, fontname="%s", fontsize=14];', [FONT_MONO]));
        Sb.AppendLine(Format('  edge  [fontname="%s", fontsize=11, color="%s", penwidth=1.4, arrowsize=0.7];', [FONT_MONO, LINE_INK]));
        Sb.AppendLine('');

        var NodeId:= 0;
        var Clusters:= 0;
        var Anchored:= 0;
        var Unanchored:= 0;
        var DrawnEdges:= 0;
        var Unwalkable:= 0;

        for var Item in Selected do
        begin
          var Mem: TArray<string>:= [];
          for var U in Item.Cycle.Units do
            Mem:= Mem + [U.ToLowerInvariant];

          // rows: each member, anchored to the FIRST uses clause that keeps it in the group
          var Cells: TArray<TDotRow>:= [];
          var Outs: TArray<TArray<TOutEdge>>:= [];
          var GrpEdges:= 0;
          var NIntf:= 0;
          for var U in Mem do
          begin
            var UR: TIndexRow:= nil;
            UnitRow.TryGetValue(U, UR);
            var UOuts:= OutEdges(EdgeKey, U, Mem);
            Outs:= Outs + [UOuts];
            Inc(GrpEdges, Length(UOuts));
            for var O in UOuts do
              if SameText(O.Edge.S('section'), 'interface') then
                Inc(NIntf);
            var Lbl:= if UR <> nil then UR.S('q') else U;
            if Length(UOuts) > 0 then
            begin
              var First:= UOuts[0];
              Inc(Anchored);
              var Parts: TArray<string>:= [];
              for var O in UOuts do
                Parts:= Parts + [Format('%s (%s, line %d)', [O.To_, O.Edge.S('section'), O.Edge.I('line')])];
              var All:= string.Join('; ', Parts);
              var Note:= if Length(UOuts) = 1 then Format('uses %s (%s)', [First.To_, First.Edge.S('section')])
                else Format('uses %d of these units; href goes to the first', [Length(UOuts)]);
              Cells:= Cells + [TDotRow.Anchored(Lbl, First.Edge.I('line'), RowHref(First.Edge.S('path'), First.Edge.I('line')),
                Lbl + ' uses ' + All, Note)];
            end
            else if UR <> nil then
            begin
              // in a strongly-connected group every member has an outgoing intra-group edge: a genuine index gap
              Inc(Anchored);
              Cells:= Cells + [TDotRow.Anchored(Lbl, UR.I('line'), RowHref(UR.S('path'), UR.I('line')),
                Format('%s -- %s; the index holds NO uses edge from it to another member of this group', [Lbl, FileNameOf(UR.S('path'))]),
                'no measured outgoing edge in this group')];
              Inc(Unwalkable);
              FocusNote.Add(Format('group %d: %s has no measured outgoing edge to another member', [Item.Ordinal, U]));
            end
            else
            begin
              Inc(Unanchored);
              Cells:= Cells + [NoteRow(U + ' (not resolvable in this index)')];
            end;
          end;

          var IsIntf:= Item.Cycle.InterfaceCycle;
          var Style:= if IsIntf then MakeStyle(INTF_BORDER, INTF_FILL, INTF_HDR) else MakeStyle(IMPL_BORDER, IMPL_FILL, IMPL_HDR);
          // implementation-only cycles are legal Delphi: dashed, so they do not read with the weight of an interface cycle
          Style.Style:= if IsIntf then 'rounded,filled' else 'rounded,filled,dashed';

          // the verdict counts the sections instead of echoing the flag (R3, DL group 1)
          var IntfLoop:= IsIntf and TestInterfaceLoop(AllEdges, Mem);
          var Verdict: string;
          if not IsIntf then
            Verdict:= 'implementation-only'
          else if IntfLoop then
            Verdict:= Format('interface cycle: an all-interface loop, which the compiler refuses (%d of %d uses interface-section)', [NIntf, GrpEdges])
          else
            Verdict:= Format('interface coupling: %d of %d uses interface-section; every loop crosses an implementation use', [NIntf, GrpEdges]);
          Cells:= Cells + [NoteRow(Verdict)];

          Inc(NodeId);
          Inc(Clusters);
          var Nid:= 'n' + IntToStr(NodeId);
          var Ports:= AddRowCluster(Sb, 'cluster_cycle_' + IntToStr(NodeId), Nid, 'group ' + IntToStr(Item.Ordinal),
            Format('%d units', [Item.Cycle.Size]), Cells, Style);

          // arrows: EVERY measured intra-group edge, labelled with its line, coloured by its own section
          var PortOf:= TDictionary<string, string>.Create(TIStringComparer.Ordinal);
          try
            for var I:= 0 to High(Mem) do
              PortOf.AddOrSetValue(Mem[I], Ports[I]);
            for var I:= 0 to High(Mem) do
              for var O in Outs[I] do
              begin
                var ToPort: string;
                if not (PortOf.ContainsKey(Mem[I]) and PortOf.TryGetValue(O.To_, ToPort)) then
                  Continue;
                var IsIntfEdge:= SameText(O.Edge.S('section'), 'interface');
                var ECol:= if IsIntfEdge then INTF_BORDER else IMPL_BORDER;
                var EPen:= if IsIntfEdge then '2.2' else '1.6';
                Sb.AppendLine(Format('  %s -> %s [color="%s", penwidth=%s, label=":%d"];',
                  [PortOf[Mem[I]], ToPort, ECol, EPen, O.Edge.I('line')]));
                Inc(DrawnEdges);
                EdgeList.Add(Format('%s->%s %s %d', [Mem[I], O.To_, O.Edge.S('section'), O.Edge.I('line')]));
              end;
          finally
            PortOf.Free;
          end;
        end;

        { ---- 7. the zero case is an ANSWER (PS 321-330) ---- }
        if Length(Selected) = 0 then
        begin
          Inc(NodeId);
          Inc(Clusters);
          AddRowCluster(Sb, 'cluster_clean_' + IntToStr(NodeId), 'n' + IntToStr(NodeId), 'no cycles', 'uses-graph is acyclic',
            [NoteRow('the index holds no unit cycle')], MakeStyle(CLEAN_BORDER, CLEAN_FILL, CLEAN_HDR));
        end;

        { ---- 8. focus box (PS 332-352) ---- }
        Inc(NodeId);
        Inc(Clusters);
        var FNid:= 'n' + IntToStr(NodeId);
        var Title:= if Wanted <> '' then 'cycles containing ' + Wanted else 'unit cycles';
        Sb.AppendLine(Format('  subgraph cluster_focus_%d {', [NodeId]));
        Sb.AppendLine(Format('    style="rounded,filled"; color="%s"; fillcolor="%s"; penwidth=2;', [FOCUS_BORDER, FOCUS_FILL]));
        Sb.AppendLine('    label=""; margin=10;');
        Sb.AppendLine(Format('    %s [label=<%s>];', [FNid, FocusTable(Title, TotalCycles, Length(Selected), DrawnEdges, Anchored,
          Unanchored, Top.HiddenRows, FocusNote)]));
        Sb.AppendLine('  }');
        Sb.AppendLine('}');

        { ---- 9. lay out (PS 357-379) ---- }
        var Slug:= if Wanted <> '' then TRegEx.Replace(Wanted, '[^A-Za-z0-9]', '_') else 'project';
        var Base:= 'cycles_' + Slug;
        var Msgs: TArray<string>;
        Result.Layout:= DotLayout(pArgs.Dot, Sb.ToString, pOutDir, Base, Msgs);

        Result.LeftCount:= TotalCycles;
        Result.RightCount:= DrawnEdges;
        Result.ClickTargets:= Result.Layout.Anchors;
        Result.AllClickable:= Result.Layout.Anchors >= Anchored;
        Result.Fields:= [TMetaField.Int('Cycles', TotalCycles), TMetaField.Int('Shown', Length(Selected)),
          TMetaField.Int('Edges', DrawnEdges), TMetaField.StrList('EdgeList', EdgeList.ToArray),
          TMetaField.Int('Anchored', Anchored), TMetaField.Int('Unanchored', Unanchored),
          TMetaField.Int('Unwalkable', Unwalkable), TMetaField.Int('Clusters', Clusters),
          TMetaField.Int('ClickTargets', Result.Layout.Anchors), TMetaField.Int('Expected', Anchored),
          TMetaField.Bool('AllClickable', Result.AllClickable)];
      finally
        FocusNote.Free;
        EdgeList.Free;
        Sb.Free;
      end;
    finally
      EdgeKey.Free;
      UnitRow.Free;
    end;
  finally
    EdgeRows.Free;
    UnitRows.Free;
    Index.Free;
  end;
end;

initialization
  RegisterChartQuestion(CYCLES_ID, Emit);

end.
