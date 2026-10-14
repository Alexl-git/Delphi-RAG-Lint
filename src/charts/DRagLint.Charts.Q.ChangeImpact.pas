unit DRagLint.Charts.Q.ChangeImpact;

(* The `change-impact` question in-process: a port of charts\src\Emit-ChangeImpact.ps1
  (spec s11; the PS output is the reference, P3). What a change to a method or a type
  affects: a BFS UP the callers (the direction measured intact) for -Depth levels -- a
  type is seeded with its members, and at level 1 also reaches the routines that name
  it in a type_use reference -- summarised in ZONES (directories below the common root)
  and units, each zone's rows ranked by distance. The walk stops after the level on
  which the reached nodes (seeds excluded) pass 400, and says CAPPED. Nothing reached is
  a refusal that names the reasons it can be true.

  New-DiagramArtifact passes -Depth (default 2) and not -Cap, so a zone shows the
  emitter's own 8 rows.

  PS traps closed: `Sort-Object -Unique` over units / zones drops case-insensitive
  duplicates (SortUniqueNames); `Sort-Object { size } -Descending` and `Sort-Object D, Q`
  are NOT stable (TPsSort); `-eq` on zone names is case-insensitive; Measure-Object
  -Maximum is a [double] (MaxHop 2.0). The PS reads the affected symbols in 60-id chunks
  taken in hashtable order, each chunk in id order: for at most 60 routines that IS id
  order, which is what this port uses for every size (the order only reaches the chart
  through Sort-Object D, Q ties, i.e. overloads sharing a qualified name). *)

interface

const
  /// <summary>The registered question id.</summary>
  CHANGE_IMPACT_ID = 'change-impact';

implementation

uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.RegularExpressions,
  DRagLint.Charts.Question, DRagLint.Charts.Index, DRagLint.Charts.Text, DRagLint.Charts.Dot,
  DRagLint.Charts.Sql, DRagLint.Charts.PsSort;

const
  D1_BORDER = '#B02A37';
  D1_FILL = '#FDECEE';
  D1_HDR = '#B02A37';
  D2_BORDER = '#B45309';
  D2_FILL = '#FEF6EC';
  D2_HDR = '#B45309';
  D3_BORDER = '#3B5BDB';
  D3_FILL = '#EDF2FF';
  D3_HDR = '#3B5BDB';
  FOCUS_BORDER = '#0F766E';
  FOCUS_FILL = '#E2F1EF';
  FOCUS_HDR = '#0F766E';
  ROW_INK = '#1F2933';
  LINE_INK = '#8A94A6';
  FONT_MONO = 'Consolas';
  FONT_SANS = 'Segoe UI';
  { Emit-ChangeImpact -MaxNodes: the frontier cap, reported when hit }
  MAX_NODES = 400;
  { Emit-ChangeImpact -Cap: rows per zone cluster; the bundler never passes it }
  ZONE_CAP = 8;
  HINT = 'change-impact selects a METHOD or a TYPE';
  { the zone colour is the nearest hop in it: direct callers, then one step further, then the rest }
  HOP_DIRECT = 1;
  HOP_SECOND = 2;

type
  TImpactItem = record
    Id, Line, D: Integer;
    Q, Path, UnitName, Zone: string;
  end;

function IdList(const pIds: TArray<Integer>): string;
begin
  var Parts: TArray<string>;
  SetLength(Parts, Length(pIds));
  for var K:= 0 to High(pIds) do
    Parts[K]:= IntToStr(pIds[K]);
  Result:= string.Join(',', Parts);
end;

{ adds every not-yet-seen enclosing routine of the query to the walk at distance pD }
procedure Reach(pIndex: TChartsIndex; const pSql: string; pD: Integer; pDist: TDictionary<Integer, Integer>;
  var pNext: TArray<Integer>);
begin
  var Rows:= pIndex.Query(pSql);
  try
    for var P in Rows do
      if not pDist.ContainsKey(P.I('caller')) then
      begin
        pDist.Add(P.I('caller'), pD);
        pNext:= pNext + [P.I('caller')];
      end;
  finally
    Rows.Free;
  end;
end;

{ Get-CommonRootLen over the directory of every file in the index }
function IndexRootLen(pIndex: TChartsIndex): Integer;
begin
  var Dirs: TArray<string>:= [];
  var Rows:= pIndex.Query('SELECT DISTINCT path AS p FROM files ORDER BY path');
  try
    for var P in Rows do
      Dirs:= Dirs + [ExtractFileDir(P.S('p').Replace('/', '\'))];
  finally
    Rows.Free;
  end;
  Result:= CommonRootLen(Dirs);
end;

procedure DepthStyle(pMinD: Integer; out pStyle: TClusterStyle);
begin
  case pMinD of
    HOP_DIRECT: pStyle:= TClusterStyle.Make(D1_BORDER, D1_FILL, D1_HDR);
    HOP_SECOND: pStyle:= TClusterStyle.Make(D2_BORDER, D2_FILL, D2_HDR);
  else
    pStyle:= TClusterStyle.Make(D3_BORDER, D3_FILL, D3_HDR);
  end;
  pStyle.RowInk:= ROW_INK;
  pStyle.LineInk:= LINE_INK;
  pStyle.FontSans:= FONT_SANS;
end;

function Emit(const pArgs: TQuestionArgs; const pOutDir: string): TChartResult;
var
  Found: Boolean;
  Items: TArray<TImpactItem>;
  Rows: TObjectList<TIndexRow>;
  Style: TClusterStyle;
begin
  var Index:= TChartsIndex.Create(pArgs.GuardedDb);
  var Dist:= TDictionary<Integer, Integer>.Create;
  try
    var Sel:= Index.ResolveMemberSelection(pArgs.Target,
      ['method', 'function', 'procedure', 'constructor', 'destructor', 'class', 'interface', 'record', 'type'], False, HINT, Found);
    var IsType:= SameText(Sel.Kind, 'class') or SameText(Sel.Kind, 'interface') or SameText(Sel.Kind, 'record') or SameText(Sel.Kind, 'type');

    { ---- seeds ---- }
    var Seeds: TArray<Integer>:= [Sel.Id];
    var MemberCount:= 0;
    if IsType then
    begin
      Rows:= Index.AllRows(Format('SELECT id FROM symbols WHERE parent_id = %d', [Sel.Id]), 'id');
      try
        MemberCount:= Rows.Count;
        for var M in Rows do
          Seeds:= Seeds + [M.I('id')];
      finally
        Rows.Free;
      end;
    end;

    { ---- BFS over CALLERS ---- }
    for var S in Seeds do
      Dist.AddOrSetValue(S, 0);
    var Frontier:= Seeds;
    var SeedCount:= Dist.Count;
    var Capped:= False;
    for var D:= 1 to pArgs.Depth do
    begin
      if Length(Frontier) = 0 then
        Break;
      var Next: TArray<Integer>:= [];
      Reach(Index,
        'SELECT DISTINCT r.enclosing_symbol_id AS caller' + sLineBreak +
        '  FROM call_edges ce JOIN refs r ON r.id = ce.ref_id' + sLineBreak +
        ' WHERE ce.target_symbol_id IN (' + IdList(Frontier) + ') AND r.enclosing_symbol_id IS NOT NULL' + sLineBreak +
        ' ORDER BY r.enclosing_symbol_id', D, Dist, Next);
      { a TYPE is also affected through plain type references, not only calls }
      if IsType and (D = 1) then
        Reach(Index,
          'SELECT DISTINCT r.enclosing_symbol_id AS caller' + sLineBreak +
          '  FROM refs r' + sLineBreak +
          Format(' WHERE r.symbol_id = %d AND r.kind = ''type_use'' AND r.enclosing_symbol_id IS NOT NULL', [Sel.Id]) + sLineBreak +
          ' ORDER BY r.enclosing_symbol_id', D, Dist, Next);
      if Dist.Count - SeedCount > MAX_NODES then
      begin
        Capped:= True;
        Break;
      end;
      Frontier:= Next;
    end;

    var Affected: TArray<Integer>:= [];
    for var P in Dist do
      if P.Value > 0 then
        Affected:= Affected + [P.Key];
    if Length(Affected) = 0 then
      raise EChartsQuestion.CreateFmt('nothing in this index depends on %s -- 0 callers at any depth. ' +
        'That is a real answer for a leaf, an entry point, or something reached only by ' +
        'interface dispatch, whose call edges are incomplete on this build.', [Sel.QName]);
    TArray.Sort<Integer>(Affected);

    { ---- resolve the affected symbols ---- }
    var RootLen:= IndexRootLen(Index);
    Items:= [];
    Rows:= Index.Query(
      'SELECT s.id AS id, s.qualified_name AS q, s.impl_start_line AS line,' + sLineBreak +
      '       s.start_line AS dline, f.path AS path' + sLineBreak +
      '  FROM symbols s JOIN files f ON f.id = s.file_id' + sLineBreak +
      ' WHERE s.id IN (' + IdList(Affected) + ')');
    try
      for var R in Rows do
      begin
        var It:= Default(TImpactItem);
        It.Id:= R.I('id');
        It.Q:= R.S('q');
        It.Line:= if R.I('line') <> 0 then R.I('line') else R.I('dline');
        It.Path:= R.S('path');
        It.UnitName:= UnitNameOf(It.Path);
        It.Zone:= PathZone(It.Path, RootLen);
        It.D:= Dist[It.Id];
        Items:= Items + [It];
      end;
    finally
      Rows.Free;
    end;
    var UnitNames, ZoneNames: TArray<string>;
    var MaxHop:= 0;
    for var It in Items do
    begin
      UnitNames:= UnitNames + [It.UnitName];
      ZoneNames:= ZoneNames + [It.Zone];
      if It.D > MaxHop then
        MaxHop:= It.D;
    end;
    var Units:= SortUniqueNames(UnitNames);
    var Zones:= SortUniqueNames(ZoneNames);
    var InZone:= function(const pZone: string): TArray<TImpactItem>
      begin
        Result:= [];
        for var It in Items do
          if SameText(It.Zone, pZone) then
            Result:= Result + [It];
      end;

    { ---- dot ---- }
    var NodeId:= 1;
    var Clusters:= 1;
    var Anchored:= 1;
    var FNid:= 'n' + IntToStr(NodeId);
    var Sb:= TStringBuilder.Create;
    try
      Sb.AppendLine('digraph changeimpact {');
      Sb.AppendLine('  rankdir=LR; bgcolor="transparent"; compound=true;');
      Sb.AppendLine('  nodesep=0.35; ranksep=1.5; splines=spline;');
      Sb.AppendLine(Format('  graph [fontname="%s"];', [FONT_SANS]));
      Sb.AppendLine(Format('  node  [shape=plaintext, fontname="%s", fontsize=14];', [FONT_MONO]));
      Sb.AppendLine(Format('  edge  [fontname="%s", fontsize=11, color="%s", penwidth=1.4, arrowsize=0.7];', [FONT_MONO, LINE_INK]));
      Sb.AppendLine('');

      var FTbl:= TStringBuilder.Create;
      try
        FTbl.Append('<TABLE BORDER="0" CELLBORDER="0" CELLSPACING="3" CELLPADDING="5">');
        FTbl.Append(Format('<TR><TD ALIGN="LEFT" BGCOLOR="%s"><FONT COLOR="#FFFFFF" FACE="%s" POINT-SIZE="14"><B> %s </B></FONT></TD></TR>',
          [FOCUS_HDR, FONT_SANS, XmlText(Sel.Name)]));
        FTbl.Append(Format('<TR><TD PORT="p1" ALIGN="LEFT" HREF="%s" TITLE="%s">', [RowHref(Sel.Path, Sel.FocusLine), XmlText(Sel.QName)]));
        FTbl.Append(Format('<FONT COLOR="%s">%s</FONT>', [ROW_INK, XmlText(UnitNameOf(Sel.Path))]));
        FTbl.Append(Format('  <FONT COLOR="%s" POINT-SIZE="12">:%d</FONT></TD></TR>', [LINE_INK, Sel.FocusLine]));
        AddDisclosureRow(FTbl, Format('BLAST RADIUS: %d routine(s), %d unit(s), %d zone(s)', [Length(Items), Length(Units), Length(Zones)]), LINE_INK);
        AddDisclosureRow(FTbl, Format('walked %d level(s) of CALLERS%s', [pArgs.Depth,
          if IsType then Format(' from the type and its %d member(s)', [MemberCount]) else '']), LINE_INK);
        if Capped then
          AddDisclosureRow(FTbl, Format('frontier CAPPED at %d -- the real radius is larger', [MAX_NODES]), LINE_INK);
        AddDisclosureRow(FTbl, 'impact fans out over CALLERS: edges INTO a symbol are owned by the calling file', LINE_INK);
        AddDisclosureRow(FTbl, 'an unresolved caller is invisible here -- a small radius is a floor, not a ceiling', LINE_INK);
        var EdgelessNote:= TChartsIndex.EdgelessDisclosure(Index.EdgelessFiles);
        if EdgelessNote <> '' then
          AddDisclosureRow(FTbl, EdgelessNote, LINE_INK);
        FTbl.Append('</TABLE>');
        Sb.AppendLine(Format('  subgraph cluster_focus_%d {', [NodeId]));
        Sb.AppendLine(Format('    style="rounded,filled"; color="%s"; fillcolor="%s"; penwidth=2;', [FOCUS_BORDER, FOCUS_FILL]));
        Sb.AppendLine('    label=""; margin=10;');
        Sb.AppendLine(Format('    %s [label=<%s>];', [FNid, FTbl.ToString]));
        Sb.AppendLine('  }');
      finally
        FTbl.Free;
      end;

      var Ranked:= Copy(Zones);
      TPsSort<string>.Sort(Ranked, function(const pL, pR: string): Integer
        begin Result:= Length(InZone(pR)) - Length(InZone(pL)); end);
      for var Z in Ranked do
      begin
        var Zi:= InZone(Z);
        if Length(Zi) = 0 then
          Continue;
        TPsSort<TImpactItem>.Sort(Zi, function(const pL, pR: TImpactItem): Integer
          begin
            Result:= pL.D - pR.D;
            if Result = 0 then
              Result:= CompareGroupKeys(pL.Q, pR.Q);
          end);
        var Top:= TRanked<TImpactItem>.TopRanked(Zi, ZONE_CAP, function(pIt: TImpactItem): Integer
          begin Result:= pIt.D; end);
        var Cells: TArray<TDotRow>:= [];
        for var It in Top.Shown do
        begin
          Inc(Anchored);
          Cells:= Cells + [TDotRow.Anchored(ShortName(It.Q, It.UnitName), It.Line, RowHref(It.Path, It.Line),
            Format('%s -- %s:%d, %d hop(s) from the change', [It.Q, It.UnitName, It.Line, It.D]), Format('hop %d', [It.D]))];
        end;
        var Dt:= DisclosureText(Top.HiddenRows, 0, 'routines');
        if Dt <> '' then
          Cells:= Cells + [NoteRow(Dt)];
        var ZoneUnits: TArray<string>:= [];
        var MinD:= MaxInt;
        for var It in Zi do
        begin
          ZoneUnits:= ZoneUnits + [It.UnitName];
          if It.D < MinD then
            MinD:= It.D;
        end;
        Cells:= Cells + [NoteRow(Format('%d unit(s) in this zone', [Length(SortUniqueNames(ZoneUnits))]))];
        DepthStyle(MinD, Style);
        Inc(NodeId);
        Inc(Clusters);
        var Nid:= 'n' + IntToStr(NodeId);
        AddRowCluster(Sb, 'cluster_z_' + IntToStr(NodeId), Nid, Z,
          Format('%d routine%s', [Length(Zi), if Length(Zi) <> 1 then 's' else '']), Cells, Style);
        Sb.AppendLine(Format('  %s:p1 -> %s [color="%s"];', [FNid, Nid, Style.Border]));
      end;
      Sb.AppendLine('}');

      var Msgs: TArray<string>;
      Result.Layout:= DotLayout(pArgs.Dot, Sb.ToString, pOutDir, 'impact_' + TRegEx.Replace(Sel.QName, '[^A-Za-z0-9]', '_'), Msgs);
    finally
      Sb.Free;
    end;
    Result.LeftCount:= Length(Items);
    Result.RightCount:= Length(Units);
    Result.ClickTargets:= Result.Layout.Anchors;
    Result.AllClickable:= Result.Layout.Anchors >= Anchored;
    Result.Fields:= [TMetaField.Str('Qname', Sel.QName), TMetaField.Bool('IsType', IsType),
      TMetaField.Int('Members', MemberCount), TMetaField.Int('Affected', Length(Items)),
      TMetaField.Int('Units', Length(Units)), TMetaField.Int('Zones', Length(Zones)),
      TMetaField.Real('MaxHop', MaxHop), TMetaField.Bool('Capped', Capped),
      TMetaField.Int('Clusters', Clusters), TMetaField.Int('ClickTargets', Result.Layout.Anchors),
      TMetaField.Int('Expected', Anchored), TMetaField.Bool('AllClickable', Result.AllClickable)];
  finally
    Dist.Free;
    Index.Free;
  end;
end;

initialization
  RegisterChartQuestion(CHANGE_IMPACT_ID, Emit);

end.
