unit DRagLint.Charts.Q.WhoCalls;

(* The `who-calls` question in-process: a port of the CALLERS direction of
  charts\src\Emit-WhoCalls.ps1 (spec s11; the PS output is the reference, P3). The N-deep
  CALLER tree of one routine: every RESOLVED call site (call_edges) up to -Depth levels,
  clustered by (depth, unit) so the picture flows depth N -> ... -> depth 1 -> focus. A row
  is a CALL SITE, not a method: the port map is keyed by row ordinal, because one method
  legitimately appears twice at different sites (ReserveNextID reaches AddOperation at :4084
  and again at :4102 as a cycle row). Zero callers is a refusal that names the DFM as the
  likely caller of an event handler.

  The NAME bucket (find-callers --name <bare>) is counted always and reported separately as
  NameMatches / NameOnly (name rows at a site no resolved row covers); it is never added to
  Callers and is not drawn.

  DATA ROUTE (decision D1). The PS spawns two engine verbs; this unit calls the engine's own
  units in-process instead (spec P5 forbids starting drag-lint.exe from a ported emitter):
  the tree is DRagLint.Report.RCallTree.BuildReverseCallTree, the function reverse-calltree
  itself calls, over a read-only TSQLiteSymbolStore; the root id is resolved by a private
  mirror of the CLI's ResolveEndpointIds (exact name, else qualified name, ids de-duplicated).
  The name bucket (D2) is ISymbolStore.FindCallersByName followed by private mirrors of the
  CLI's two find-callers post-filters, DropRefsThatCannotBeCallers and
  CollapseRefsAtSameSite (DRagLint.CLI.pas); moving those to a shared query unit is deferred
  to an engine session.

  REFUSALS (D3). Unknown target: 'symbol not found: <target>' (the verb's own line; the PS
  message names a process this port never starts). A target resolving to more than one
  symbol: '<target> resolves to N symbols in this index -- name one qualified routine' (the
  PS dies on an [int] cast). Zero callers and the flatten mismatch are the PS text verbatim.

  NOT PORTED (D4): -WithNameMatches (PS lines 239-260, the dashed name cluster). Ask-Report
  and New-DiagramArtifact never pass it, so NameRendered is always false and Expected is
  Rows + 1. The Write-Host progress lines are not output (no host stream here).

  THE CALLEE DIRECTION (D5) is not registered: what-it-calls is still answered by the PS.
  Porting it is a diff of this unit, at these PS lines: 93-98 (the amber callee palette),
  134-137 (the 'calls nothing' empty message), 156-164 (bucket not probed: NameMatches and
  NameOnly are JSON null, which needs a TMetaField.Null), 205 (groups sorted ascending),
  270 (edge drawn parent -> row), 281 (base name suffix '_callees'), 296-297 (Callers 0,
  Callees Rows) and 304-305 (the null bucket fields).

  PS traps closed: Group-Object groups by "<level>|<unit>" case-insensitively AND sorts its
  groups by key (CompareGroupKeys), each group keeping its rows in input order and named
  after its first row; `Sort-Object { [int]level } -Descending` is NOT stable (TPsSort
  keeps its tie order among the units of one level); Measure-Object -Maximum is a [double]
  (MaxDepth 1.0). *)

interface

const
  /// <summary>The registered question id.</summary>
  WHO_CALLS_ID = 'who-calls';

implementation

uses
  System.SysUtils, System.Generics.Collections, System.Generics.Defaults,
  System.RegularExpressions, DRagLint.Core.Model, DRagLint.Core.Interfaces, DRagLint.Storage.SQLite,
  DRagLint.Report.RCallTree, DRagLint.Charts.Question, DRagLint.Charts.Index, DRagLint.Charts.Text,
  DRagLint.Charts.Dot, DRagLint.Charts.PsSort;

const
  CALLER_BORDER = '#3B5BDB';
  CALLER_FILL = '#EDF2FF';
  CALLER_HDR = '#3B5BDB';
  FOCUS_BORDER = '#0F766E';
  FOCUS_FILL = '#E2F1EF';
  FOCUS_HDR = '#0F766E';
  ROW_INK = '#1F2933';
  LINE_INK = '#8A94A6';
  FOCUS_INK = '#0B3F39';
  FONT_MONO = 'Consolas';
  FONT_SANS = 'Segoe UI';
  DIRECTION = 'callers';
  QUESTION = WHO_CALLS_ID;
  { CollapseRefsAtSameSite's kind ranks: the surviving row at one position is the highest }
  RANK_CALL = 3;
  RANK_MEMBER_ACCESS = 2;
  RANK_READ = 1;

type
  /// <summary>One flattened row of the caller tree: a CALL SITE (Expand-Callers' object).</summary>
  /// <remarks>Idx is the row's ordinal; Parent is the ordinal of the row it calls, -1 for the
  /// focus. A Cycle row is listed but never expanded.</remarks>
  TCallRow = record
    Idx, Line, Level, Parent: Integer;
    QName, Site, FilePath: string;
    Cycle: Boolean;
  end;

  /// <summary>One Group-Object group of rows: its key (the first row's), level, unit and rows.</summary>
  TCallGroup = class
    Name: string;
    Level: Integer;
    UnitName: string;
    Rows: TList<TCallRow>;
    /// <summary>An empty group named after its first row.</summary>
    /// <param name="pName">The group key, '&lt;level&gt;|&lt;unit&gt;'.</param>
    /// <param name="pLevel">The rows' level.</param>
    /// <param name="pUnitName">The rows' unit, as the first row names it.</param>
    constructor Create(const pName: string; pLevel: Integer; const pUnitName: string);
    /// <summary>Frees the row list.</summary>
    destructor Destroy; override;
  end;

constructor TCallGroup.Create(const pName: string; pLevel: Integer; const pUnitName: string);
begin
  inherited Create;
  Name:= pName;
  Level:= pLevel;
  UnitName:= pUnitName;
  Rows:= TList<TCallRow>.Create;
end;

destructor TCallGroup.Destroy;
begin
  Rows.Free;
  inherited Destroy;
end;

/// <summary>The symbol ids reverse-calltree --qname resolves a name to.</summary>
/// <param name="pStore">The open store.</param>
/// <param name="pName">A bare or qualified name.</param>
/// <returns>Every matching id, de-duplicated, in store order; empty when nothing matches.</returns>
/// <remarks>Mirror of DRagLint.CLI.pas ResolveEndpointIds (private to the CLI unit, D1):
/// exact name first, else qualified name.</remarks>
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

/// <summary>Drops the name refs that cannot be calls: writes, and reads of a same-named local.</summary>
/// <param name="pStore">The open store.</param>
/// <param name="pRefs">FindCallersByName's refs.</param>
/// <returns>The refs that may be calls, in input order.</returns>
/// <remarks>Mirror of DRagLint.CLI.pas DropRefsThatCannotBeCallers (decision D2): a 'write'
/// never calls; a 'read' whose enclosing routine declares a local, parameter, var or const of
/// that name reads THAT.</remarks>
function DropRefsThatCannotBeCallers(const pStore: ISymbolStore; const pRefs: TArray<TReference>): TArray<TReference>;
begin
  Result:= [];
  for var R in pRefs do
  begin
    if SameText(R.Kind, 'write') then
      Continue;
    if SameText(R.Kind, 'read') and (R.EnclosingSymbolId > 0) then
    begin
      var Child:= pStore.FindChildSymbolByName(R.EnclosingSymbolId, R.NameText);
      if (Child.Id > 0) and (Child.Kind in [skLocalVar, skParam, skVarDecl, skConstDecl]) then
        Continue;
    end;
    Result:= Result + [R];
  end;
end;

/// <summary>The rank of a ref kind when two refs share one position.</summary>
/// <param name="pKind">The ref kind.</param>
/// <returns>call 3, member-access 2, read 1, anything else 0.</returns>
function KindRank(const pKind: string): Integer;
begin
  if SameText(pKind, 'call') then
    Exit(RANK_CALL);
  if SameText(pKind, 'member-access') then
    Exit(RANK_MEMBER_ACCESS);
  if SameText(pKind, 'read') then
    Exit(RANK_READ);
  Result:= 0;
end;

/// <summary>One ref per call site (file, line, column).</summary>
/// <param name="pRefs">The refs.</param>
/// <returns>The refs with each position once: the highest-ranked kind there, in the slot the
/// first ref at that position took.</returns>
/// <remarks>Mirror of DRagLint.CLI.pas CollapseRefsAtSameSite (decision D2).</remarks>
function CollapseRefsAtSameSite(const pRefs: TArray<TReference>): TArray<TReference>;
begin
  Result:= [];
  var Seen:= TDictionary<string, Integer>.Create;
  try
    for var R in pRefs do
    begin
      var Key:= Format('%d:%d:%d', [R.FileId, R.StartLine, R.StartCol]);
      var Idx: Integer;
      if Seen.TryGetValue(Key, Idx) then
      begin
        if KindRank(R.Kind) > KindRank(Result[Idx].Kind) then
          Result[Idx]:= R;
        Continue;
      end;
      Result:= Result + [R];
      Seen.Add(Key, High(Result));
    end;
  finally
    Seen.Free;
  end;
end;

/// <summary>Flattens a caller tree node's children into rows (Expand-Callers).</summary>
/// <param name="pNode">The node whose callers are added.</param>
/// <param name="pParent">The ordinal of pNode's row; -1 for the root (the focus).</param>
/// <param name="pLevel">The children's level (1 under the root).</param>
/// <param name="pRows">The rows, appended in walk order; must not be nil.</param>
/// <remarks>A cycle row is added but never expanded: the engine already stopped there.</remarks>
procedure ExpandCallers(const pNode: TRCallNode; pParent, pLevel: Integer; pRows: TList<TCallRow>);
begin
  for var K in pNode.Callers do
  begin
    var R:= Default(TCallRow);
    R.Idx:= pRows.Count;
    R.QName:= K.QName;
    R.Site:= K.Site;
    R.FilePath:= K.SiteFile;
    R.Line:= K.SiteLine;
    R.Level:= pLevel;
    R.Cycle:= K.Cycle;
    R.Parent:= pParent;
    pRows.Add(R);
    if not K.Cycle then
      ExpandCallers(K, R.Idx, pLevel + 1, pRows);
  end;
end;

/// <summary>Group-Object { "&lt;level&gt;|&lt;unit&gt;" } then Sort-Object { [int]level } -Descending.</summary>
/// <param name="pRows">The rows.</param>
/// <param name="pGroups">Owns the groups made; must not be nil.</param>
/// <returns>The groups: case-insensitive keys, sorted by key, then by level descending in
/// Sort-Object's (unstable) order.</returns>
function GroupByLevelAndUnit(pRows: TList<TCallRow>; pGroups: TObjectList<TCallGroup>): TArray<TCallGroup>;
begin
  var Slot:= TDictionary<string, TCallGroup>.Create(TIStringComparer.Ordinal);
  try
    for var R in pRows do
    begin
      var UnitName:= UnitNameOf(R.FilePath);
      var Key:= IntToStr(R.Level) + '|' + UnitName;
      var G: TCallGroup;
      if not Slot.TryGetValue(Key, G) then
      begin
        G:= TCallGroup.Create(Key, R.Level, UnitName);
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
  TArray.Sort<TCallGroup>(Result, TComparer<TCallGroup>.Construct(
    function(const pL, pR: TCallGroup): Integer begin Result:= CompareGroupKeys(pL.Name, pR.Name); end));
  TPsSort<TCallGroup>.Sort(Result, function(const pL, pR: TCallGroup): Integer
    begin Result:= pR.Level - pL.Level; end);
end;

/// <summary>Appends the focus cluster: the target's unit header and its 18-point short name.</summary>
/// <param name="pSb">The DOT text; must not be nil.</param>
/// <param name="pTarget">The asked qualified name.</param>
/// <param name="pFocusFile">The target's declaring file.</param>
/// <param name="pFocusLine">The line a reader should open (the body when there is one).</param>
procedure AddFocus(pSb: TStringBuilder; const pTarget, pFocusFile: string; pFocusLine: Integer);
begin
  var FocusUnit:= UnitNameOf(pFocusFile);
  pSb.AppendLine('  subgraph cluster_focus {');
  pSb.AppendLine(Format('    style="rounded,filled"; color="%s"; fillcolor="%s"; penwidth=3;', [FOCUS_BORDER, FOCUS_FILL]));
  pSb.AppendLine('    label=""; margin=12;');
  var FHref:= RowHref(pFocusFile, pFocusLine);
  var FHdr:= Format('<TR><TD ALIGN="LEFT" BGCOLOR="%s"><FONT COLOR="#FFFFFF" FACE="%s" POINT-SIZE="14"><B> %s &#183; focus </B></FONT></TD></TR>',
    [FOCUS_HDR, FONT_SANS, XmlText(FocusUnit)]);
  var FTip:= XmlText(Format('%s  --  %s:%d', [pTarget, FileNameOf(pFocusFile), pFocusLine]));
  pSb.AppendLine(Format('    focus [label=<<TABLE BORDER="0" CELLBORDER="0" CELLSPACING="3" CELLPADDING="7">%s' +
    '<TR><TD HREF="%s" TITLE="%s"><FONT COLOR="%s" POINT-SIZE="18"><B>%s</B></FONT></TD></TR></TABLE>>];',
    [FHdr, FHref, FTip, FOCUS_INK, XmlText(ShortName(pTarget, FocusUnit))]));
  pSb.AppendLine('  }');
end;

/// <summary>Answers who-calls for pArgs.Target (Emit-WhoCalls.ps1 -Direction callers).</summary>
/// <param name="pArgs">The question; Target is a routine, Depth the caller levels walked.</param>
/// <param name="pOutDir">The bundle folder the layout files go to.</param>
/// <returns>The chart: LeftCount the resolved call sites, RightCount the cycle rows.</returns>
/// <exception cref="EChartsQuestion">Unknown or ambiguous target, zero callers, flatten mismatch.</exception>
/// <exception cref="EChartsIndex">The focus is not in the index (SymbolLocation).</exception>
function Emit(const pArgs: TQuestionArgs; const pOutDir: string): TChartResult;
begin
  var Db:= pArgs.GuardedDb;
  var Store: ISymbolStore:= TSQLiteSymbolStore.Create(Db, True);
  var Index:= TChartsIndex.Create(Db);
  var Rows:= TList<TCallRow>.Create;
  var Groups:= TObjectList<TCallGroup>.Create(True);
  try
    { ---- 1. the RESOLVED bucket ---- }
    var RootIds:= ResolveEndpointIds(Store, pArgs.Target);
    if Length(RootIds) = 0 then
      raise EChartsQuestion.CreateFmt('symbol not found: %s', [pArgs.Target]);
    if Length(RootIds) > 1 then
      raise EChartsQuestion.CreateFmt('%s resolves to %d symbols in this index -- name one qualified routine',
        [pArgs.Target, Length(RootIds)]);
    var Opts:= Default(TRCallOptions);
    Opts.Depth:= pArgs.Depth;
    var Tree:= BuildReverseCallTree(Store, RootIds[0], Opts);
    ExpandCallers(Tree.Root, -1, 1, Rows);
    var NodeCount:= Tree.Summary.NodeCount;
    if Rows.Count + 1 <> NodeCount then
      raise EChartsQuestion.CreateFmt('flatten mismatch: %d rows vs node_count %d -- did you read the wrong child key?',
        [Rows.Count, NodeCount]);
    if Rows.Count = 0 then
      raise EChartsQuestion.CreateFmt('%s has 0 callers in call_edges (node_count %d). If it is an event handler ' +
        'the caller is the DFM -- ask event-wiring instead.', [pArgs.Target, NodeCount]);
    var Cycles:= 0;
    var MaxDepth:= 0;
    for var R in Rows do
    begin
      if R.Cycle then
        Inc(Cycles);
      if R.Level > MaxDepth then
        MaxDepth:= R.Level;
    end;

    { ---- 2. the focus line ---- }
    var Loc:= Index.SymbolLocation(pArgs.Target);
    var FocusFile:= Loc.Path;

    { ---- 3. the NAME bucket, counted always ---- }
    var Parts:= pArgs.Target.Split(['.']);
    var Bare:= Parts[High(Parts)];
    var NameRows:= CollapseRefsAtSameSite(DropRefsThatCannotBeCallers(Store, Store.FindCallersByName(Bare)));
    var NameOnly:= 0;
    var Seen:= TDictionary<string, Boolean>.Create;
    try
      for var R in Rows do
        Seen.AddOrSetValue(R.FilePath.ToLowerInvariant + '|' + IntToStr(R.Line), True);
      for var N in NameRows do
        if not Seen.ContainsKey(Store.GetFilePath(N.FileId).ToLowerInvariant + '|' + IntToStr(N.StartLine)) then
          Inc(NameOnly);
    finally
      Seen.Free;
    end;

    { ---- 4. dot ---- }
    var NodeId:= 0;
    var Clusters:= 0;
    var PortOf: TArray<string>;
    SetLength(PortOf, Rows.Count);
    var Sb:= TStringBuilder.Create;
    try
      Sb.AppendLine('digraph whocalls {');
      Sb.AppendLine('  rankdir=LR; bgcolor="transparent"; compound=true;');
      Sb.AppendLine('  nodesep=0.35; ranksep=1.1; splines=spline;');
      Sb.AppendLine(Format('  graph [fontname="%s"];', [FONT_SANS]));
      Sb.AppendLine(Format('  node  [shape=plaintext, fontname="%s", fontsize=14];', [FONT_MONO]));
      Sb.AppendLine(Format('  edge  [fontname="%s", fontsize=11, color="%s", penwidth=1.5, arrowsize=0.8];', [FONT_MONO, LINE_INK]));
      Sb.AppendLine('');

      { CALLERS: deepest first, so the flow reads depth N -> ... -> depth 1 -> focus }
      var Style:= TClusterStyle.Make(CALLER_BORDER, CALLER_FILL, CALLER_HDR);
      Style.RowInk:= ROW_INK;
      Style.LineInk:= LINE_INK;
      Style.FontSans:= FONT_SANS;
      for var G in GroupByLevelAndUnit(Rows, Groups) do
      begin
        Inc(NodeId);
        Inc(Clusters);
        var Cells: TArray<TDotRow>:= [];
        for var R in G.Rows do
          Cells:= Cells + [TDotRow.Anchored(ShortName(R.QName, G.UnitName), R.Line, RowHref(R.FilePath, R.Line),
            Format('%s  --  %s:%d', [R.QName, FileNameOf(R.FilePath), R.Line]), if R.Cycle then 'cycle' else '')];
        var Ports:= AddRowCluster(Sb, Format('cluster_d%d_%d', [G.Level, NodeId]), 'n' + IntToStr(NodeId), G.UnitName,
          'depth ' + IntToStr(G.Level), Cells, Style);
        for var K:= 0 to G.Rows.Count - 1 do
          PortOf[G.Rows[K].Idx]:= Ports[K];
      end;

      AddFocus(Sb, pArgs.Target, FocusFile, Loc.FocusLine);

      Sb.AppendLine('');
      for var R in Rows do
      begin
        var Mine:= PortOf[R.Idx];
        var Parent:= if R.Parent < 0 then 'focus' else PortOf[R.Parent];
        if (Mine = '') or (Parent = '') then
          Continue;
        Sb.AppendLine(Format('  %s -> %s [color="%s"%s];', [Mine, Parent, CALLER_BORDER, if R.Cycle then ', style=dashed' else '']));
      end;
      Sb.AppendLine('}');

      { ---- 5. lay out ---- }
      var Msgs: TArray<string>;
      Result.Layout:= DotLayout(pArgs.Dot, Sb.ToString, pOutDir, TRegEx.Replace(pArgs.Target, '[^A-Za-z0-9]', '_'), Msgs);
    finally
      Sb.Free;
    end;

    var Expected:= Rows.Count + 1;
    Result.LeftCount:= Rows.Count;
    Result.RightCount:= Cycles;
    Result.ClickTargets:= Result.Layout.Anchors;
    Result.AllClickable:= Result.Layout.Anchors >= Expected;
    Result.Fields:= [TMetaField.Str('Direction', DIRECTION), TMetaField.Str('Question', QUESTION),
      TMetaField.Int('Rows', Rows.Count), TMetaField.Int('Callers', Rows.Count), TMetaField.Int('Callees', 0),
      TMetaField.Int('NodeCount', NodeCount), TMetaField.Int('Cycles', Cycles), TMetaField.Real('MaxDepth', MaxDepth),
      TMetaField.Bool('Truncated', Tree.Summary.Truncated), TMetaField.Int('Clusters', Clusters),
      TMetaField.Int('NameMatches', Length(NameRows)), TMetaField.Int('NameOnly', NameOnly),
      TMetaField.Bool('NameRendered', False), TMetaField.Int('ClickTargets', Result.Layout.Anchors),
      TMetaField.Int('Expected', Expected), TMetaField.Bool('AllClickable', Result.AllClickable)];
  finally
    Groups.Free;
    Rows.Free;
    Index.Free;
  end;
end;

initialization
  RegisterChartQuestion(WHO_CALLS_ID, Emit);

end.
