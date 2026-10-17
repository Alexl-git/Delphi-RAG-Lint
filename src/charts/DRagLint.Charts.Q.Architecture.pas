unit DRagLint.Charts.Q.Architecture;

(* The `architecture` question in-process: a port of charts\src\Emit-Architecture.ps1 (spec s11;
  the PS output is the reference, P3). The whole project's layering, MEASURED: internal zones
  on the left (rankdir=LR), third-party groups on the right, the arrows between zones labelled
  with the edge count.

  deps-report classifies EXTERNALS only; the internal structure comes from
  unit_uses.target_file_id and a layering rule. Zones are SOURCE DIRECTORIES below the common
  root, measured, never invented. A back-edge is the smaller direction of a zone pair against
  the larger, drawn red and dashed, and never called a violation: the index declares no layer
  order. Externals are unresolved by definition, so their rows carry no href.

  Data route (H4): the PS spawns `deps-report --db <db> --format json`. The port calls
  DRagLint.Report.Deps.BuildDepsReport DIRECTLY on the read-only ISymbolStore opened beside the
  TChartsIndex, with the four options DoDepsReport uses (Depth 3, AllSources False,
  NamePattern '', MaxList 20); no JSON is built. The report unit is READ, never edited.

  Not ported (H1): -NoExternals (the PS never gets it from New-DiagramArtifact, so the externals
  branch is unconditional) and -MaxPerZone (the const MAX_PER_ZONE = 6 is what NDA passes).
  The target is the literal `project` and is IGNORED, as the PS takes none.

  PS traps closed: hashtable keys, `-eq`, `-contains` and `-match (?i)` are case-blind
  (TIStringComparer.Ordinal, SameText, StartsText); EVERY Sort-Object goes through TPsSort
  because Sort-Object is introsort and tied keys move (group sizes and used-by counts really
  tie); `Sort-Object -Unique` is SortUniqueNames; InDegree counts edges into non-unit files too
  (the increment happens BEFORE the zone check); Write-Host is not output. *)

interface

const
  /// <summary>The registered question id.</summary>
  ARCHITECTURE_ID = 'architecture';

implementation

uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.Generics.Defaults,
  System.RegularExpressions, System.Math, System.StrUtils, DRagLint.Core.Interfaces, DRagLint.Storage.SQLite, DRagLint.Report.Deps,
  DRagLint.Charts.Question,
  DRagLint.Charts.Index, // dl:unit DRagLint.Charts.Index accepted -- the resolver, the SQL text escaper and CompareGroupKeys travel with TChartsIndex, so the refusal texts and the sort order cannot drift from the other questions
  DRagLint.Charts.Sql, DRagLint.Charts.Text, DRagLint.Charts.Dot, DRagLint.Charts.PsSort;

const
  MAX_PER_ZONE = 6;
  ZONE_BORDER = '#3B5BDB';
  ZONE_FILL = '#EDF2FF';
  ZONE_HDR = '#3B5BDB';
  EXT_BORDER = '#6B7280';
  EXT_FILL = '#F3F4F6';
  EXT_HDR = '#6B7280';
  UNK_BORDER = '#B45309';
  UNK_FILL = '#FEF6EC';
  UNK_HDR = '#B45309';
  BACK_EDGE = '#B02A37';
  FOCUS_BORDER = '#0F766E';
  FOCUS_FILL = '#E2F1EF';
  FOCUS_HDR = '#0F766E';
  ROW_INK = '#1F2933';
  LINE_INK = '#8A94A6';
  FONT_MONO = 'Consolas';
  FONT_SANS = 'Segoe UI';
  DEPS_DEPTH = 3;
  DEPS_MAX_LIST = 20;
  STEM_MIN = 4;
  STEM_PREFIX_MAX = 6;

type
  // one zone -> zone aggregate of the matrix; Intf is counted as the PS does and never output
  TZonePair = record
    N: Integer;
    Intf: Integer;
  end;

  // the smaller direction of a zone pair against the larger
  TBackEdge = record
    From: string;
    To_: string;
    N: Integer;
    Against: Integer;
  end;

function MakeStyle(const pBorder, pFill, pHdr: string): TClusterStyle;
begin
  Result:= TClusterStyle.Make(pBorder, pFill, pHdr);
  Result.RowInk:= ROW_INK;
  Result.LineInk:= LINE_INK;
  Result.FontSans:= FONT_SANS;
end;

// InDegree of a file: how many uses edges point at it (0 when none)
function DegreeOf(const pInDegree: TDictionary<Integer, Integer>; pFid: Integer): Integer;
begin
  if not pInDegree.TryGetValue(pFid, Result) then
    Result:= 0;
end;

// the first pLen '\'-segments of pDir joined with '\' (PS 114)
function RootOf(const pDir: string; pLen: Integer): string;
begin
  var Parts:= pDir.Split(['\']);
  Result:= string.Join('\', Copy(Parts, 0, pLen));
end;

// a vendor-looking name in `unknown` is a CLASSIFIER gap (PS 185-202). Mirrored quirk: 'other'
// (5 letters) is a stem too; 'RTL' (3) is skipped.
function ClassifierGaps(const pReport: TDepsReport; const pExtByGroup: TDictionary<string, TList<TDepsExternal>>): TArray<string>;
begin
  Result:= [];
  var Unknown: TList<TDepsExternal>;
  if not pExtByGroup.TryGetValue('unknown', Unknown) then
    Exit;
  var Known: TArray<string>:= [];
  for var GC in pReport.Summary.GroupCounts do
  begin
    var GName:= DepsGroupStr(GC.Group);
    if not SameText(GName, 'unknown') then
      Known:= Known + [GName];
  end;
  for var X in Unknown do
    for var G in Known do
    begin
      var Stem:= TRegEx.Replace(G, '[^A-Za-z]', '');
      if (Length(Stem) >= STEM_MIN) and StartsText(Copy(Stem, 1, Min(STEM_PREFIX_MAX, Length(Stem))), X.UnitName) then
      begin
        Result:= Result + [X.UnitName + ' is in ''unknown'' but looks like ' + G];
        Break;
      end;
    end;
end;

// the focus table (PS 289-312): not AddRowCluster, its own grammar
function FocusTable(pUnits, pZones, pEdges, pDrawn: Integer; const pRootPath: string; pSingleZone: Boolean;  // dl:ok too-many-parameters@7b94 -- REVIEWED 2026-10-17: the parameter list is the set of numbers and lists the PS focus table interpolates (Emit-Architecture.ps1 289-312); a record would only rename them
  const pBack: TList<TBackEdge>; pExtUnits, pExtEdges: Integer; const pGaps: TArray<string>): string;
begin
  var Tbl:= TStringBuilder.Create;
  try
    Tbl.Append('<TABLE BORDER="0" CELLBORDER="0" CELLSPACING="3" CELLPADDING="5">');
    Tbl.Append(Format('<TR><TD ALIGN="LEFT" BGCOLOR="%s"><FONT COLOR="#FFFFFF" FACE="%s" POINT-SIZE="14"><B> architecture </B></FONT></TD></TR>',
      [FOCUS_HDR, FONT_SANS]));
    AddDisclosureRow(Tbl, Format('%d project units in %d source zone(s) under %s', [pUnits, pZones, pRootPath]), LINE_INK);
    AddDisclosureRow(Tbl, Format('%d internal uses edges  &#183;  %d cross-zone arrow(s) drawn', [pEdges, pDrawn]), LINE_INK);
    if pSingleZone then
      AddDisclosureRow(Tbl, 'this project keeps every unit in one folder, so there are no internal zones to draw', LINE_INK);
    for var B in pBack do
      AddDisclosureRow(Tbl, Format('back-edge: %s -> %s, %d edge(s) against %d the other way', [B.From, B.To_, B.N, B.Against]), LINE_INK);
    if pBack.Count > 0 then
      AddDisclosureRow(Tbl, 'a back-edge is an asymmetry this index measured; no layer order is declared anywhere', LINE_INK);
    AddDisclosureRow(Tbl, 'zones are SOURCE DIRECTORIES: namespace prefixes cover only 9% of units here', LINE_INK);
    AddDisclosureRow(Tbl, Format('%d external units over %d external edges, none resolved in this index', [pExtUnits, pExtEdges]), LINE_INK);
    AddDisclosureRow(Tbl, 'third-party rows carry no link: those units are not in this index', LINE_INK);
    for var V in pGaps do
      AddDisclosureRow(Tbl, 'classifier gap: ' + V, LINE_INK);
    Tbl.Append('</TABLE>');
    Result:= Tbl.ToString;
  finally
    Tbl.Free;
  end;
end;

/// <summary>Answers `architecture`: the project's source-directory zones, the measured arrows and back-edges between them, and the third-party groups.</summary>
/// <param name="pArgs">The question arguments; Target is the literal `project` and is ignored, Cap is not read.</param>
/// <param name="pOutDir">Where dot, svg, plain, png and pdf are written.</param>
/// <returns>The chart result; LeftCount is the unit count, RightCount the back-edge count.</returns>
/// <exception cref="EChartsQuestion">The index holds no unit symbols at all.</exception>
/// <remarks>Opens a read-only TSQLiteSymbolStore beside the TChartsIndex (two read-only handles on one file) and calls BuildDepsReport on it.</remarks>
function Emit(const pArgs: TQuestionArgs; const pOutDir: string): TChartResult;  // dl:ok method-too-long@5acb, deep-nesting@5be6 -- REVIEWED 2026-10-17: ports the one-script PS body line for line (H2-H8); the sections share a dozen locals (zones, matrix, degrees, report), so splitting would only thread them as parameters
begin
  var Store: ISymbolStore:= TSQLiteSymbolStore.Create(pArgs.GuardedDb, True);  // dl:ok object-leak@8a34 -- REVIEWED 2026-10-17: ISymbolStore is reference-counted and released at scope exit, as in Q.Wiring
  var Index:= TChartsIndex.Create(pArgs.GuardedDb);
  try
    { ---- 1. every unit, with its file (PS 101-106) ---- }
    var Units:= Index.AllRows(
      'SELECT s.qualified_name AS q, s.start_line AS line, f.path AS path, f.id AS fid' + sLineBreak +
      '  FROM symbols s JOIN files f ON f.id = s.file_id' + sLineBreak +
      ' WHERE s.kind = ''unit''', 's.qualified_name');
    try
      if Units.Count = 0 then
        raise EChartsQuestion.Create('architecture: this index holds no unit symbols at all');

      { ---- 2. zones = source directory relative to the common root (PS 112-130) ---- }
      var DirList: TArray<string>:= [];
      for var U in Units do
        DirList:= DirList + [ExtractFileDir(U.S('path').Replace('/', '\'))];
      var Dirs:= SortUniqueNames(DirList);
      var RootLen:= CommonRootLen(Dirs);
      var RootPath:= if RootLen > 0 then RootOf(Dirs[0], RootLen) else '(no common root)';

      var ZoneOf:= TDictionary<Integer, string>.Create;
      var ZoneUnits:= TObjectDictionary<string, TList<TIndexRow>>.Create([doOwnsValues], TIStringComparer.Ordinal);
      var Zones: TArray<string>:= [];
      var Edges:= Index.AllRows(
        'SELECT uu.file_id AS src, uu.target_file_id AS dst, uu.section AS section' + sLineBreak +
        '  FROM unit_uses uu' + sLineBreak +
        ' WHERE uu.target_file_id IS NOT NULL', 'uu.id');
      var Matrix:= TDictionary<string, TZonePair>.Create(TIStringComparer.Ordinal);
      var InDegree:= TDictionary<Integer, Integer>.Create;
      var BackEdges:= TList<TBackEdge>.Create;
      var ExtByGroup:= TObjectDictionary<string, TList<TDepsExternal>>.Create([doOwnsValues], TIStringComparer.Ordinal);
      var ZonePort:= TDictionary<string, string>.Create(TIStringComparer.Ordinal);
      var BackKey:= TDictionary<string, Boolean>.Create(TIStringComparer.Ordinal);
      var Sb:= TStringBuilder.Create;
      try
        for var U in Units do
        begin
          var Z:= PathZone(U.S('path'), RootLen);
          ZoneOf.AddOrSetValue(U.I('fid'), Z);
          var ZList: TList<TIndexRow>;
          if not ZoneUnits.TryGetValue(Z, ZList) then
          begin
            ZList:= TList<TIndexRow>.Create;
            ZoneUnits.Add(Z, ZList);
            Zones:= Zones + [Z];
          end;
          ZList.Add(U);
        end;
        // N5: hashtable key order is per-process; the sort (size desc, then name) is the contract
        TPsSort<string>.Sort(Zones,
          function(const pA, pB: string): Integer
          begin
            Result:= ZoneUnits[pB].Count - ZoneUnits[pA].Count;
            if Result = 0 then
              Result:= CompareGroupKeys(pA, pB);
          end);
        var SingleZone:= Length(Zones) <= 1;

        { ---- 3. internal edges, aggregated zone -> zone (PS 132-168) ---- }
        for var E in Edges do
        begin
          var Dst:= E.I('dst');
          InDegree.AddOrSetValue(Dst, DegreeOf(InDegree, Dst) + 1);  // before the zone check: an edge into a non-unit file counts
          var ZA, ZB: string;
          if not (ZoneOf.TryGetValue(E.I('src'), ZA) and ZoneOf.TryGetValue(Dst, ZB)) then
            Continue;
          var Key:= ZA + '|' + ZB;
          var Pair: TZonePair;
          if not Matrix.TryGetValue(Key, Pair) then
          begin
            Pair.N:= 0;
            Pair.Intf:= 0;
          end;
          Inc(Pair.N);
          if SameText(E.S('section'), 'interface') then
            Inc(Pair.Intf);
          Matrix.AddOrSetValue(Key, Pair);
        end;

        // back-edges: for each unordered pair, the smaller direction against the larger
        for var I:= 0 to High(Zones) do
          for var J:= I + 1 to High(Zones) do
          begin
            var A:= Zones[I];
            var B:= Zones[J];
            var AB, BA: TZonePair;
            if not Matrix.TryGetValue(A + '|' + B, AB) then
              AB.N:= 0;
            if not Matrix.TryGetValue(B + '|' + A, BA) then
              BA.N:= 0;
            if (AB.N > 0) and (BA.N > 0) then
            begin
              var BE: TBackEdge;
              // ties (ab = ba) go to the second zone as the source: PS `-ge`
              if AB.N >= BA.N then
              begin
                BE.From:= B;
                BE.To_:= A;
                BE.N:= BA.N;
                BE.Against:= AB.N;
              end
              else
              begin
                BE.From:= A;
                BE.To_:= B;
                BE.N:= AB.N;
                BE.Against:= BA.N;
              end;
              BackEdges.Add(BE);
            end;
          end;

        { ---- 4. externals: BuildDepsReport, the route behind `deps-report --format json` (PS 170-183) ---- }
        var Opts: TDepsOptions;
        Opts.Depth:= DEPS_DEPTH;
        Opts.AllSources:= False;
        Opts.NamePattern:= '';
        Opts.MaxList:= DEPS_MAX_LIST;
        var Rep:= BuildDepsReport([Store], Opts);
        for var X in Rep.Externals do
        begin
          var GName:= DepsGroupStr(X.Group);
          var GList: TList<TDepsExternal>;
          if not ExtByGroup.TryGetValue(GName, GList) then
          begin
            GList:= TList<TDepsExternal>.Create;
            ExtByGroup.Add(GName, GList);
          end;
          GList.Add(X);
        end;
        var Gaps:= ClassifierGaps(Rep, ExtByGroup);

        { ---- 5. dot (PS 204-318) ---- }
        Sb.AppendLine('digraph architecture {');
        Sb.AppendLine('  rankdir=LR; bgcolor="transparent"; compound=true;');
        Sb.AppendLine('  nodesep=0.45; ranksep=1.5; splines=spline;');
        Sb.AppendLine(Format('  graph [fontname="%s"];', [FONT_SANS]));
        Sb.AppendLine(Format('  node  [shape=plaintext, fontname="%s", fontsize=14];', [FONT_MONO]));
        Sb.AppendLine(Format('  edge  [fontname="%s", fontsize=11, color="%s", penwidth=1.4, arrowsize=0.8];', [FONT_MONO, LINE_INK]));
        Sb.AppendLine('');

        var NodeId:= 0;
        var Clusters:= 0;
        var Anchored:= 0;

        { LEFT: one cluster per zone, rows are its most-depended-upon units }
        for var Z in Zones do
        begin
          Inc(NodeId);
          Inc(Clusters);
          var Nid:= 'n' + IntToStr(NodeId);
          var Ranked:= ZoneUnits[Z].ToArray;
          TPsSort<TIndexRow>.Sort(Ranked,
            function(const pA, pB: TIndexRow): Integer
            begin
              Result:= DegreeOf(InDegree, pB.I('fid')) - DegreeOf(InDegree, pA.I('fid'));
              if Result = 0 then
                Result:= CompareGroupKeys(pA.S('q'), pB.S('q'));
            end);
          var TopZ:= TRanked<TIndexRow>.TopRanked(Ranked, MAX_PER_ZONE, nil);
          var Rows: TArray<TDotRow>:= [];
          for var U in TopZ.Shown do
          begin
            var Deg:= DegreeOf(InDegree, U.I('fid'));
            Inc(Anchored);
            Rows:= Rows + [TDotRow.Anchored(U.S('q'), U.I('line'), RowHref(U.S('path'), U.I('line')),
              Format('%s -- used by %d unit(s) in this project', [U.S('q'), Deg]), Format('used by %d', [Deg]))];
          end;
          var Dt:= DisclosureText(TopZ.HiddenRows, 0, 'units');
          if Dt <> '' then
            Rows:= Rows + [NoteRow(Dt)];
          var Ports:= AddRowCluster(Sb, 'cluster_zone_' + IntToStr(NodeId), Nid, Z,
            Format('%d units', [ZoneUnits[Z].Count]), Rows, MakeStyle(ZONE_BORDER, ZONE_FILL, ZONE_HDR));
          ZonePort.AddOrSetValue(Z, Ports[0]);
        end;

        { arrows between zones, labelled with the measured edge count }
        Sb.AppendLine('');
        for var BE in BackEdges do
          BackKey.AddOrSetValue(BE.From + '|' + BE.To_, True);
        var Drawn:= 0;
        var Keys:= Matrix.Keys.ToArray;
        TPsSort<string>.Sort(Keys, CompareGroupKeys);  // N5: sorted for a stable dot
        for var K in Keys do
        begin
          var Cut:= K.IndexOf('|');
          var PA:= K.Substring(0, Cut);
          var PB:= K.Substring(Cut + 1);
          if SameText(PA, PB) then
            Continue;  // self-dependency is not a layering fact
          if not (ZonePort.ContainsKey(PA) and ZonePort.ContainsKey(PB)) then
            Continue;
          var IsBack:= BackKey.ContainsKey(K);
          var Col:= if IsBack then BACK_EDGE else ZONE_BORDER;
          var Sty:= if IsBack then ', style=dashed' else '';
          var Back:= if IsBack then ' back' else '';
          var Lbl:= IntToStr(Matrix[K].N) + Back;
          var Pen:= if IsBack then '2.2' else '1.6';
          Sb.AppendLine(Format('  %s -> %s [color="%s", penwidth=%s%s, label="%s"];', [ZonePort[PA], ZonePort[PB], Col, Pen, Sty, Lbl]));
          Inc(Drawn);
        end;

        { RIGHT: third-party groups, biggest first (ties introsort-ordered, hence TPsSort) }
        var Groups:= Copy(Rep.Summary.GroupCounts);
        TPsSort<TDepsGroupCount>.Sort(Groups,
          function(const pA, pB: TDepsGroupCount): Integer
          begin
            Result:= pB.UnitCount - pA.UnitCount;
          end);
        for var GC in Groups do
        begin
          var GName:= DepsGroupStr(GC.Group);
          Inc(NodeId);
          Inc(Clusters);
          var Nid:= 'n' + IntToStr(NodeId);
          var IsUnknown:= SameText(GName, 'unknown');
          var List: TArray<TDepsExternal>:= [];
          var GList: TList<TDepsExternal>;
          if ExtByGroup.TryGetValue(GName, GList) then
            List:= GList.ToArray;
          TPsSort<TDepsExternal>.Sort(List,
            function(const pA, pB: TDepsExternal): Integer
            begin
              Result:= pB.UsedByCount - pA.UsedByCount;
            end);
          var TopG:= TRanked<TDepsExternal>.TopRanked(List, MAX_PER_ZONE, nil);
          var Rows: TArray<TDotRow>:= [];
          for var X in TopG.Shown do  // unresolved by definition: no file in this index, so NO href
            Rows:= Rows + [NoteRow(Format('%s  (used by %d)', [X.UnitName, X.UsedByCount]))];
          var Dt:= DisclosureText(TopG.HiddenRows, 0, 'units');
          if Dt <> '' then
            Rows:= Rows + [NoteRow(Dt)];
          Rows:= Rows + [NoteRow(Format('used by %d project unit(s)', [GC.ProjectUnitCount]))];
          var Style:= if IsUnknown then MakeStyle(UNK_BORDER, UNK_FILL, UNK_HDR) else MakeStyle(EXT_BORDER, EXT_FILL, EXT_HDR);
          Style.Style:= 'rounded,filled,dashed';
          AddRowCluster(Sb, 'cluster_ext_' + IntToStr(NodeId), Nid, GName, Format('%d external units', [GC.UnitCount]), Rows, Style);
        end;

        { FOCUS }
        Inc(NodeId);
        Inc(Clusters);
        var FNid:= 'n' + IntToStr(NodeId);
        Sb.AppendLine(Format('  subgraph cluster_focus_%d {', [NodeId]));
        Sb.AppendLine(Format('    style="rounded,filled"; color="%s"; fillcolor="%s"; penwidth=2;', [FOCUS_BORDER, FOCUS_FILL]));
        Sb.AppendLine('    label=""; margin=10;');
        Sb.AppendLine(Format('    %s [label=<%s>];', [FNid, FocusTable(Units.Count, Length(Zones), Edges.Count, Drawn, RootPath,
          SingleZone, BackEdges, Rep.Summary.ExternalUnitCount, Rep.Summary.ExternalEdgeCount, Gaps)]));
        Sb.AppendLine('  }');
        Sb.AppendLine('}');

        { ---- 6. lay out ---- }
        var Msgs: TArray<string>;
        Result.Layout:= DotLayout(pArgs.Dot, Sb.ToString, pOutDir, 'architecture', Msgs);

        Result.LeftCount:= Units.Count;
        Result.RightCount:= BackEdges.Count;
        Result.ClickTargets:= Result.Layout.Anchors;
        Result.AllClickable:= Result.Layout.Anchors >= Anchored;
        Result.Fields:= [TMetaField.Int('Units', Units.Count), TMetaField.Int('Zones', Length(Zones)),
          TMetaField.Int('InternalEdges', Edges.Count), TMetaField.Int('CrossZone', Drawn),
          TMetaField.Int('BackEdges', BackEdges.Count), TMetaField.Int('ExternalUnits', Rep.Summary.ExternalUnitCount),
          TMetaField.Int('ExternalEdges', Rep.Summary.ExternalEdgeCount), TMetaField.Int('Groups', Length(Rep.Summary.GroupCounts)),
          TMetaField.Int('ClassifierGaps', Length(Gaps)), TMetaField.Int('Clusters', Clusters),
          TMetaField.Int('ClickTargets', Result.Layout.Anchors), TMetaField.Int('Expected', Anchored),
          TMetaField.Bool('AllClickable', Result.AllClickable)];
      finally
        Sb.Free;
        BackKey.Free;
        ZonePort.Free;
        ExtByGroup.Free;
        BackEdges.Free;
        InDegree.Free;
        Matrix.Free;
        Edges.Free;
        ZoneUnits.Free;
        ZoneOf.Free;
      end;
    finally
      Units.Free;
    end;
  finally
    Index.Free;
  end;
end;

initialization
  RegisterChartQuestion(ARCHITECTURE_ID, Emit);

end.
