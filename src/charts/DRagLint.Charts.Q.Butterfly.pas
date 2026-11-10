unit DRagLint.Charts.Q.Butterfly;

(* The `butterfly` question in-process: a port of charts\src\Emit-Butterfly.ps1 (spec s11; the PS
  output is the reference, P3). One routine at the centre, its CALLERS fanned out to the left and
  its CALLEES to the right, each side clustered by (hop, unit); every box is a click target.

  D6 STORY (the PS header). A row is one SYMBOL at its shallowest hop; an edge is one distinct
  (parent, child) pair. The engine's tree repeats a symbol whenever a second parent reaches it
  (the repeat is cycle-marked and not expanded): a repeat adds its EDGE (that call is real) and
  never a second row. The focus itself is never a row: a path back to it is an edge into the
  focus box. Only the engine's depth-1 children touch the focus box.

  DATA ROUTE (decision F1). The PS spawns `butterfly --qname Q --depth N --format json`; this unit
  calls what DoButterfly calls, in-process (spec P5 forbids starting drag-lint.exe from a ported
  emitter), over a read-only TSQLiteSymbolStore: BuildReverseCallTree (callers) and
  BuildForwardCallTree (callees; the Callers field of a forward node holds its CALLEES), both
  from the FIRST resolved root id. More than one root id is NOT a refusal in this verb (it
  composes a SINGLE centre node); zero callers and/or zero callees is a valid one-node chart.
  The root id comes from a private mirror of the CLI's ResolveEndpointIds. The only refusal is
  'symbol not found: <target>' (the verb's own line; the PS text names a process never started).

  FIELDS (F5). ExportSvg, ExportPng and ExportPdf are the FILE SIZES in bytes of the three layout
  outputs (0 when a file is missing, as Get-FileSize does). They go into meta.json. ExportSvg and
  ExportPng must match the PS run byte for byte; ExportPdf is not byte-stable (cairo: 38862 / 38863
  in two runs, 2026-10-16), so parity masks it (ruling R1) and the tests check it is > 0.

  PS traps closed: -eq and hashtable keys are case-blind (SameText, TIStringComparer.Ordinal);
  Sort-Object Level -Stable keeps the engine's order within a hop; Group-Object sorts its groups
  by the STRING key (CompareGroupKeys, so '10|x' sorts before '2|x'); the line of the focus href
  is always the REVERSE root's line, even when the file came from the callees root; Write-Host
  lines are not output (no host stream here). *)

interface

const
  /// <summary>The registered question id of the butterfly chart.</summary>
  BUTTERFLY_ID = 'butterfly';

implementation

uses
  System.SysUtils, System.IOUtils, System.Generics.Collections, System.Generics.Defaults,
  System.RegularExpressions, DRagLint.Core.Interfaces, DRagLint.Storage.SQLite,
  DRagLint.Report.RCallTree, DRagLint.Charts.Question, DRagLint.Charts.Index, DRagLint.Charts.Text,
  DRagLint.Charts.Dot;

const
  CALLER_BORDER = '#3B5BDB';
  CALLER_FILL = '#EDF2FF';
  CALLER_HDR = '#3B5BDB';
  FOCUS_BORDER = '#0F766E';
  FOCUS_FILL = '#E2F1EF';
  FOCUS_HDR = '#0F766E';
  CALLEE_BORDER = '#B45309';
  CALLEE_FILL = '#FEF6EC';
  CALLEE_HDR = '#B45309';
  ROW_INK = '#1F2933';
  LINE_INK = '#8A94A6';
  FOCUS_INK = '#0B3F39';
  FONT_MONO = 'Consolas';
  FONT_SANS = 'Segoe UI';
  SIDE_IN = 'in';
  SIDE_OUT = 'out';
  FOCUS_PORT = 'focus';

type
  /// <summary>One flattened tree node: a symbol reached from ParentQ at hop Level.</summary>
  /// <remarks>ParentQ is '' under the root (the focus). A cycle-marked repeat is a node too.</remarks>
  TBfNode = record
    QName, FilePath: string;
    Line, Level: Integer;
    ParentQ: string;
  end;

  /// <summary>One Group-Object group of rows: its key (the first row's), level, unit and rows.</summary>
  TBfGroup = class
    Name: string;
    Level: Integer;
    UnitName: string;
    Rows: TList<TBfNode>;
    /// <summary>An empty group named after its first row.</summary>
    /// <param name="pName">The group key, '&lt;level&gt;|&lt;unit&gt;'.</param>
    /// <param name="pLevel">The rows' level.</param>
    /// <param name="pUnitName">The rows' unit, as the first row names it.</param>
    constructor Create(const pName: string; pLevel: Integer; const pUnitName: string);
    /// <summary>Frees the row list.</summary>
    destructor Destroy; override;
  end;

constructor TBfGroup.Create(const pName: string; pLevel: Integer; const pUnitName: string);
begin
  inherited Create;
  Name:= pName;
  Level:= pLevel;
  UnitName:= pUnitName;
  Rows:= TList<TBfNode>.Create;
end;

destructor TBfGroup.Destroy;
begin
  Rows.Free;
  inherited Destroy;
end;

// Mirror of DRagLint.CLI.pas ResolveEndpointIds (private to the CLI unit, decision F1): exact name, else qualified name.
function ResolveEndpointIds(const pStore: ISymbolStore; const pName: string): TArray<Int64>;
begin
  Result:= [];
  var Syms:= pStore.FindSymbolsByExactName(pName);
  if Length(Syms) = 0 then
    Syms:= pStore.FindSymbolsByQualifiedName(pName);
  for var S in Syms do
    if not TArray.Contains<Int64>(Result, S.Id) then
      Result:= Result + [S.Id];
end;

/// <summary>Flattens a tree node's children into nodes (PS Flatten, the D6 shape).</summary>
/// <param name="pNode">The node whose children (its Callers field, on both sides) are added.</param>
/// <param name="pParentQ">The qualified name of pNode; '' for the root (the focus).</param>
/// <param name="pLevel">The children's hop (1 under the root).</param>
/// <param name="pAcc">The nodes, appended in walk order; must not be nil.</param>
/// <remarks>Every child is appended, a cycle-marked repeat included; a cycle node is never
/// expanded, the engine already stopped there.</remarks>
procedure Flatten(const pNode: TRCallNode; const pParentQ: string; pLevel: Integer; pAcc: TList<TBfNode>);
begin
  for var K in pNode.Callers do
  begin
    var N:= Default(TBfNode);
    N.QName:= K.QName;
    N.FilePath:= K.SiteFile;
    N.Line:= K.SiteLine;
    N.Level:= pLevel;
    N.ParentQ:= pParentQ;
    pAcc.Add(N);
    if not K.Cycle then
      Flatten(K, K.QName, pLevel + 1, pAcc);
  end;
end;

/// <summary>One row per symbol, at its shallowest hop (PS Get-DistinctRows).</summary>
/// <param name="pNodes">The flattened nodes.</param>
/// <param name="pFocusQ">The focus qualified name; it never becomes a row.</param>
/// <returns>The distinct nodes ordered by hop, the engine's order kept within a hop; qualified
/// names compare case-insensitively (PS -eq and hashtable keys).</returns>
function DistinctRows(pNodes: TList<TBfNode>; const pFocusQ: string): TList<TBfNode>;
begin
  Result:= TList<TBfNode>.Create;
  var Seen:= TDictionary<string, Boolean>.Create(TIStringComparer.Ordinal);
  try
    var MaxLevel:= 0;
    for var N in pNodes do
      if N.Level > MaxLevel then
        MaxLevel:= N.Level;
    for var Lvl:= 1 to MaxLevel do
      for var N in pNodes do
      begin
        if (N.Level <> Lvl) or SameText(N.QName, pFocusQ) or Seen.ContainsKey(N.QName) then
          Continue;
        Seen.Add(N.QName, True);
        Result.Add(N);
      end;
  finally
    Seen.Free;
  end;
end;

// Group-Object { "<level>|<unit>" } | Sort-Object Name: case-blind keys, sorted by the STRING key.
function GroupByKey(pRows: TList<TBfNode>; pGroups: TObjectList<TBfGroup>): TArray<TBfGroup>;  // dl:ok duplicate-code@c8e9 -- REVIEWED 2026-10-16: ports the PS Group-Object over the rows line for line (decision F1, precedent bdd013e3); sharing it with Q.WhoCalls would make one parity finding span two questions
begin
  var Slot:= TDictionary<string, TBfGroup>.Create(TIStringComparer.Ordinal);
  try
    for var R in pRows do
    begin
      var UnitName:= UnitNameOf(R.FilePath);
      var Key:= IntToStr(R.Level) + '|' + UnitName;
      var G: TBfGroup;
      if not Slot.TryGetValue(Key, G) then
      begin
        G:= TBfGroup.Create(Key, R.Level, UnitName);
        pGroups.Add(G);
        Slot.Add(Key, G);
      end;
      G.Rows.Add(R);
    end;
  finally
    Slot.Free;
  end;
  Result:= pGroups.ToArray;
  { keys are unique case-insensitively, so the order is total and no tie can move }
  TArray.Sort<TBfGroup>(Result, TComparer<TBfGroup>.Construct(
    function(const pL, pR: TBfGroup): Integer begin Result:= CompareGroupKeys(pL.Name, pR.Name); end));
end;

// Add-UnitCluster: the emitter's own older grammar (no subtitle, every row anchored, no note cell).
procedure AddUnitCluster(pSb: TStringBuilder; const pSide, pUnit: string; pLevel: Integer; pRows: TList<TBfNode>;  // dl:ok too-many-parameters@0d0a -- REVIEWED 2026-10-16: the parameter list of the PS Add-UnitCluster plus the node counter and port map the script keeps in script scope, so the call sites read like the script
  const pBorder, pFill, pHdr: string; var pNodeId: Integer; pPortMap: TDictionary<string, string>);
begin
  Inc(pNodeId);
  var Nid:= 'n' + IntToStr(pNodeId);
  pSb.AppendLine(Format('  subgraph cluster_%s_%d {', [pSide, pNodeId]));
  pSb.AppendLine(Format('    style="rounded,filled"; color="%s"; fillcolor="%s"; penwidth=2;', [pBorder, pFill]));
  pSb.AppendLine('    label=""; margin=10;');
  var Tbl:= TStringBuilder.Create;
  try
    Tbl.Append('<TABLE BORDER="0" CELLBORDER="0" CELLSPACING="3" CELLPADDING="5">');
    { a unit reached at two hops gets two boxes, and the second says so }
    var Hop:= if pLevel > 1 then ' &#183; hop ' + IntToStr(pLevel) else '';
    Tbl.Append(Format('<TR><TD ALIGN="LEFT" BGCOLOR="%s"><FONT COLOR="#FFFFFF" FACE="%s" POINT-SIZE="14"><B> %s%s </B></FONT></TD></TR>',
      [pHdr, FONT_SANS, XmlText(pUnit), Hop]));
    var P:= 0;
    for var R in pRows do
    begin
      Inc(P);
      Tbl.Append(Format('<TR><TD PORT="p%d" ALIGN="LEFT" HREF="%s" TITLE="%s">',
        [P, RowHref(R.FilePath, R.Line), XmlText(Format('%s  --  %s:%d', [R.QName, FileNameOf(R.FilePath), R.Line]))]));
      Tbl.Append(Format('<FONT COLOR="%s">%s</FONT>', [ROW_INK, XmlText(ShortName(R.QName, pUnit))]));
      Tbl.Append(Format('  <FONT COLOR="%s" POINT-SIZE="12">:%d</FONT>', [LINE_INK, R.Line]));
      Tbl.Append('</TD></TR>');
      pPortMap.AddOrSetValue(pSide + '|' + R.QName, Format('%s:p%d', [Nid, P]));
    end;
    Tbl.Append('</TABLE>');
    pSb.AppendLine(Format('    %s [label=<%s>];', [Nid, Tbl.ToString]));
  finally
    Tbl.Free;
  end;
  pSb.AppendLine('  }');
end;

// Get-Port: the focus port for the root / the focus itself, else the port-map value, else ''.
function PortOf(pPortMap: TDictionary<string, string>; const pSide, pQ, pFocusQ: string): string;
begin
  if (pQ = '') or SameText(pQ, pFocusQ) then
    Exit(FOCUS_PORT);
  if not pPortMap.TryGetValue(pSide + '|' + pQ, Result) then
    Result:= '';
end;

// Get-FileSize: the size in bytes, 0 when the file is missing.
function FileSizeOf(const pPath: string): Integer;
begin
  if TFile.Exists(pPath) then
    Result:= Integer(TFile.GetSize(pPath))
  else
    Result:= 0;
end;

// The focus cluster (PS 214-221). The href line is ALWAYS the reverse root's line (PS 218, mirrored).
procedure AddFocusBox(pSb: TStringBuilder; const pQName, pFocusFile: string; pLine: Integer);
begin
  var FocusUnit:= UnitNameOf(pFocusFile);
  pSb.AppendLine('  subgraph cluster_focus {');
  pSb.AppendLine(Format('    style="rounded,filled"; color="%s"; fillcolor="%s"; penwidth=3;', [FOCUS_BORDER, FOCUS_FILL]));
  pSb.AppendLine('    label=""; margin=12;');
  var FHdr:= Format('<TR><TD ALIGN="LEFT" BGCOLOR="%s"><FONT COLOR="#FFFFFF" FACE="%s" POINT-SIZE="14"><B> %s &#183; focus </B></FONT></TD></TR>',
    [FOCUS_HDR, FONT_SANS, XmlText(FocusUnit)]);
  pSb.AppendLine(Format('    focus [label=<<TABLE BORDER="0" CELLBORDER="0" CELLSPACING="3" CELLPADDING="7">%s' +
    '<TR><TD HREF="%s" TITLE="%s"><FONT COLOR="%s" POINT-SIZE="18"><B>%s</B></FONT></TD></TR></TABLE>>];',
    [FHdr, RowHref(pFocusFile, pLine), XmlText(pQName), FOCUS_INK, XmlText(ShortName(pQName, FocusUnit))]));
  pSb.AppendLine('  }');
end;

/// <summary>Answers butterfly for pArgs.Target (Emit-Butterfly.ps1).</summary>
/// <param name="pArgs">The question; Target is a routine, Depth the hops walked on each side.</param>
/// <param name="pOutDir">The bundle folder the layout files go to.</param>
/// <returns>The chart: LeftCount the distinct callers, RightCount the distinct callees; the fields
/// are Callers, Callees, Edges, FocusIn, FocusOut, ClickTargets, Expected, AllClickable and the
/// three export sizes.</returns>
/// <exception cref="EChartsQuestion">The target is not in the index ('symbol not found: ...').</exception>
/// <remarks>When the target resolves to several symbols the first one is drawn (no ambiguity
/// refusal in this verb). An empty wing is a valid chart.</remarks>
function Emit(const pArgs: TQuestionArgs; const pOutDir: string): TChartResult;
begin
  var Store: ISymbolStore:= TSQLiteSymbolStore.Create(pArgs.GuardedDb, True);
  var CallerNodes:= TList<TBfNode>.Create;
  var CalleeNodes:= TList<TBfNode>.Create;
  var PortMap:= TDictionary<string, string>.Create(TIStringComparer.Ordinal);
  var EdgeSeen:= TDictionary<string, Boolean>.Create(TIStringComparer.Ordinal);
  var Callers: TList<TBfNode>:= nil;
  var Callees: TList<TBfNode>:= nil;
  var Groups:= TObjectList<TBfGroup>.Create(True);
  try
    var RootIds:= ResolveEndpointIds(Store, pArgs.Target);
    if Length(RootIds) = 0 then
      raise EChartsQuestion.CreateFmt('symbol not found: %s', [pArgs.Target]);
    var Opts:= Default(TRCallOptions);
    Opts.Depth:= pArgs.Depth;
    var ReverseTree:= BuildReverseCallTree(Store, RootIds[0], Opts);
    var ForwardTree:= BuildForwardCallTree(Store, RootIds[0], Opts);
    var FocusQ:= ReverseTree.Root.QName;
    Flatten(ReverseTree.Root, '', 1, CallerNodes);
    Flatten(ForwardTree.Root, '', 1, CalleeNodes);
    Callers:= DistinctRows(CallerNodes, FocusQ);
    Callees:= DistinctRows(CalleeNodes, FocusQ);

    var FocusFile:= ReverseTree.Root.SiteFile;
    if Trim(FocusFile) = '' then
      FocusFile:= ForwardTree.Root.SiteFile;

    var Sb:= TStringBuilder.Create;
    try
      var NodeId:= 0;
      Sb.AppendLine('digraph butterfly {');
      Sb.AppendLine('  rankdir=LR; bgcolor="transparent"; compound=true;');
      Sb.AppendLine('  nodesep=0.35; ranksep=1.1; splines=spline;');
      Sb.AppendLine(Format('  graph [fontname="%s"];', [FONT_SANS]));
      Sb.AppendLine(Format('  node  [shape=plaintext, fontname="%s", fontsize=14];', [FONT_MONO]));
      Sb.AppendLine(Format('  edge  [fontname="%s", fontsize=11, color="%s", penwidth=1.5, arrowsize=0.8];', [FONT_MONO, LINE_INK]));
      Sb.AppendLine('');

      for var G in GroupByKey(Callers, Groups) do
        AddUnitCluster(Sb, SIDE_IN, G.UnitName, G.Level, G.Rows, CALLER_BORDER, CALLER_FILL, CALLER_HDR, NodeId, PortMap);
      AddFocusBox(Sb, FocusQ, FocusFile, ReverseTree.Root.SiteLine);
      var CalleeGroups:= TObjectList<TBfGroup>.Create(True);
      try
        for var G in GroupByKey(Callees, CalleeGroups) do
          AddUnitCluster(Sb, SIDE_OUT, G.UnitName, G.Level, G.Rows, CALLEE_BORDER, CALLEE_FILL, CALLEE_HDR, NodeId, PortMap);
      finally
        CalleeGroups.Free;
      end;

      Sb.AppendLine('');
      { one arrow per distinct (parent, child) pair, drawn from the PARENT the engine reached it through }
      var FocusIn:= 0;
      var FocusOut:= 0;
      for var N in CallerNodes do
      begin
        var EdgeFrom:= PortOf(PortMap, SIDE_IN, N.QName, FocusQ);
        var EdgeTo:= PortOf(PortMap, SIDE_IN, N.ParentQ, FocusQ);
        if (EdgeFrom = '') or (EdgeTo = '') or EdgeSeen.ContainsKey(EdgeFrom + '>' + EdgeTo) then
          Continue;
        EdgeSeen.Add(EdgeFrom + '>' + EdgeTo, True);
        if EdgeTo = FOCUS_PORT then
          Inc(FocusIn);
        Sb.AppendLine(Format('  %s -> %s [color="%s"];', [EdgeFrom, EdgeTo, CALLER_BORDER]));
      end;
      for var N in CalleeNodes do
      begin
        var EdgeFrom:= PortOf(PortMap, SIDE_OUT, N.ParentQ, FocusQ);
        var EdgeTo:= PortOf(PortMap, SIDE_OUT, N.QName, FocusQ);
        if (EdgeFrom = '') or (EdgeTo = '') or EdgeSeen.ContainsKey(EdgeFrom + '>' + EdgeTo) then
          Continue;
        EdgeSeen.Add(EdgeFrom + '>' + EdgeTo, True);
        if EdgeFrom = FOCUS_PORT then
          Inc(FocusOut);
        Sb.AppendLine(Format('  %s -> %s [color="%s"];', [EdgeFrom, EdgeTo, CALLEE_BORDER]));
      end;
      Sb.AppendLine('}');

      var Msgs: TArray<string>;
      var Base:= TRegEx.Replace(pArgs.Target, '[^A-Za-z0-9]', '_');
      Result.Layout:= DotLayout(pArgs.Dot, Sb.ToString, pOutDir, Base, Msgs);

      var Expected:= Callers.Count + Callees.Count + 1;
      Result.LeftCount:= Callers.Count;
      Result.RightCount:= Callees.Count;
      Result.ClickTargets:= Result.Layout.Anchors;
      Result.AllClickable:= Result.Layout.Anchors >= Expected;
      Result.Fields:= [TMetaField.Int('Callers', Callers.Count), TMetaField.Int('Callees', Callees.Count),
        TMetaField.Int('Edges', EdgeSeen.Count), TMetaField.Int('FocusIn', FocusIn),
        TMetaField.Int('FocusOut', FocusOut), TMetaField.Int('ClickTargets', Result.Layout.Anchors),
        TMetaField.Int('Expected', Expected), TMetaField.Bool('AllClickable', Result.AllClickable),
        TMetaField.Int('ExportSvg', FileSizeOf(Result.Layout.Svg)),
        TMetaField.Int('ExportPng', FileSizeOf(Result.Layout.Png)),
        TMetaField.Int('ExportPdf', FileSizeOf(Result.Layout.Pdf))];
    finally
      Sb.Free;
    end;
  finally
    Groups.Free;
    EdgeSeen.Free;
    PortMap.Free;
    Callees.Free;
    Callers.Free;
    CalleeNodes.Free;
    CallerNodes.Free;
  end;
end;

initialization
  RegisterChartQuestion(BUTTERFLY_ID, Emit);

end.
