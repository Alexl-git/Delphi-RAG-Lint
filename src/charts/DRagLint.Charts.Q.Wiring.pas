unit DRagLint.Charts.Q.Wiring;

(* The `wiring` question in-process: a port of charts\src\Emit-Wiring.ps1 (spec s11; the PS
  output is the reference, P3). Who REGISTERS an interface, with what lifetime, and where it
  is RESOLVED: registrations on the left, the interface in the middle, resolution sites on
  the right (rankdir=LR).

  Built on di_bindings, never symbol_facts.wiring (0 non-NULL on both ORM3 indexes). The
  `wiring` verb answers the same empty document for an unregistered INTERFACE and for a
  CLASS, so the kind check happens HERE, against the index, before the store is asked: the
  verb's silence is not evidence. The index-wide registration total is on every chart and
  states a NUMBER, never a cause.

  Data route (G1): the PS spawns `wiring --qname <bare> --format json`, whose document is
  DRagLint.Wiring.BuildWiringJson. The port calls the three store methods behind it
  (FindImplementationsOf, FindDiResolveSites, FindEventHandlersForForm) in that order, on a
  read-only TSQLiteSymbolStore opened BESIDE the TChartsIndex (two read-only handles on one
  file); no JSON is built. Array order is the store's order; the PS never sorts it.

  PS traps closed: `-eq`, hashtable keys and `Sort-Object -Unique` are case-insensitive
  (SameText, TIStringComparer.Ordinal); `Sort-Object` over strings is CompareGroupKeys
  order; Write-Host is not output. The PS reads `$h.name` for an event handler but the verb
  writes the key `handler`, so `$h.name` is always $null and the row label is always the
  unit name: that is MIRRORED, not fixed (ruling R2). Note rows keep their port and get an
  edge, exactly as Add-RowCluster does. *)

interface

const
  /// <summary>The registered question id.</summary>
  WIRING_ID = 'wiring';

implementation

uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.Generics.Defaults,
  System.RegularExpressions, DRagLint.Core.Model, DRagLint.Core.Interfaces, DRagLint.Storage.SQLite,
  DRagLint.Charts.Question,
  DRagLint.Charts.Index, // dl:unit DRagLint.Charts.Index accepted -- the resolver, the SQL text escaper and CompareGroupKeys travel with TChartsIndex, so the refusal texts and the sort order cannot drift from the other questions
  DRagLint.Charts.Text, DRagLint.Charts.Dot, DRagLint.Charts.PsSort;

const
  REG_BORDER = '#0F766E';
  REG_FILL = '#E2F1EF';
  REG_HDR = '#0F766E';
  FOCUS_BORDER = '#3B5BDB';
  FOCUS_FILL = '#EDF2FF';
  FOCUS_HDR = '#3B5BDB';
  USE_BORDER = '#B45309';
  USE_FILL = '#FEF6EC';
  USE_HDR = '#B45309';
  EH_BORDER = '#7C3AED';
  EH_FILL = '#F3EEFF';
  EH_HDR = '#7C3AED';
  ROW_INK = '#1F2933';
  LINE_INK = '#8A94A6';
  FONT_MONO = 'Consolas';
  FONT_SANS = 'Segoe UI';

function MakeStyle(const pBorder, pFill, pHdr: string): TClusterStyle;
begin
  Result:= TClusterStyle.Make(pBorder, pFill, pHdr);
  Result.RowInk:= ROW_INK;
  Result.LineInk:= LINE_INK;
  Result.FontSans:= FONT_SANS;
end;

/// <summary>The routine whose body holds a source line: the innermost one.</summary>
/// <param name="pIndex">The open index.</param>
/// <param name="pPath">files.path of the resolution site.</param>
/// <param name="pLine">The site's line.</param>
/// <returns>The qualified name, or '' when the line sits in no routine body.</returns>
/// <remarks>Innermost = ORDER BY impl_start_line DESC LIMIT 1 (Get-SiteOwner, PS 113-124).</remarks>
function SiteOwner(const pIndex: TChartsIndex; const pPath: string; pLine: Integer): string;
begin
  var Rows:= pIndex.Query(
    'SELECT s.qualified_name AS q' + sLineBreak +
    '  FROM symbols s JOIN files f ON f.id = s.file_id' + sLineBreak +
    ' WHERE f.path = ''' + TChartsIndex.SqlText(pPath) + '''' + sLineBreak +
    '   AND s.impl_start_line IS NOT NULL AND s.impl_end_line IS NOT NULL' + sLineBreak +
    '   AND s.impl_start_line <= ' + IntToStr(pLine) + ' AND s.impl_end_line >= ' + IntToStr(pLine) + sLineBreak +
    ' ORDER BY s.impl_start_line DESC' + sLineBreak +
    ' LIMIT 1');
  try
    Result:= if Rows.Count > 0 then Rows[0].S('q') else '';
  finally
    Rows.Free;
  end;
end;

// the focus table of the interface (PS 172-191): not AddRowCluster, its own grammar
function FocusTable(const pIName: string; pDeclared: Boolean; const pSel: TMemberSelection;
  pIdxRegs, pIdxIfaces: Integer; const pLifetimes: TArray<string>; pImplCount: Integer): string;
begin
  var Tbl:= TStringBuilder.Create;
  try
    Tbl.Append('<TABLE BORDER="0" CELLBORDER="0" CELLSPACING="3" CELLPADDING="5">');
    Tbl.Append(Format('<TR><TD ALIGN="LEFT" BGCOLOR="%s"><FONT COLOR="#FFFFFF" FACE="%s" POINT-SIZE="14"><B> %s </B></FONT></TD></TR>',
      [FOCUS_HDR, FONT_SANS, XmlText(pIName)]));
    if pDeclared then
    begin
      Tbl.Append(Format('<TR><TD PORT="p1" ALIGN="LEFT" HREF="%s" TITLE="%s">',
        [RowHref(pSel.Path, pSel.FocusLine), XmlText(pSel.QName)]));
      Tbl.Append(Format('<FONT COLOR="%s">%s</FONT>', [ROW_INK, XmlText(UnitNameOf(pSel.Path))]));
      Tbl.Append(Format('  <FONT COLOR="%s" POINT-SIZE="12">:%d</FONT></TD></TR>', [LINE_INK, pSel.FocusLine]));
    end
    else
      AddDisclosureRow(Tbl, 'not declared in this index', LINE_INK);
    AddDisclosureRow(Tbl, Format('index-wide: %d registration(s) over %d interface(s)', [pIdxRegs, pIdxIfaces]), LINE_INK);
    if Length(pLifetimes) > 1 then
      AddDisclosureRow(Tbl, 'registered with DIFFERENT lifetimes: ' + string.Join(', ', pLifetimes), LINE_INK);
    if pImplCount = 0 then
      AddDisclosureRow(Tbl, 'a registration made in another project index is not visible here', LINE_INK);
    Tbl.Append('</TABLE>');
    Result:= Tbl.ToString;
  finally
    Tbl.Free;
  end;
end;

// the distinct lifetimes of ALL bindings, case-blind (first spelling kept), in Sort-Object order
function DistinctLifetimes(const pImpls: TArray<TDiBindingRow>): TArray<string>;
begin
  Result:= [];
  var Seen:= TDictionary<string, Boolean>.Create(TIStringComparer.Ordinal);
  try
    for var B in pImpls do
      if not Seen.ContainsKey(B.Lifetime) then
      begin
        Seen.Add(B.Lifetime, True);
        Result:= Result + [B.Lifetime];
      end;
  finally
    Seen.Free;
  end;
  TPsSort<string>.Sort(Result, CompareGroupKeys);
end;

/// <summary>Answers `wiring` for pArgs.Target: the registrations of an interface, its resolution sites and event handlers.</summary>
/// <param name="pArgs">The question arguments; Target names an interface (qualified or bare), Cap bounds each side.</param>
/// <param name="pOutDir">Where dot, svg, plain, png and pdf are written.</param>
/// <returns>The chart result; zero registrations is an answer, not a refusal.</returns>
/// <exception cref="EChartsQuestion">The index has no DI registrations at all, or the name is neither declared nor registered.</exception>
/// <exception cref="EChartsIndex">The name is ambiguous or not an interface (the text comes from ResolveMemberSelection).</exception>
/// <remarks>Opens a read-only TSQLiteSymbolStore beside the TChartsIndex (two read-only handles on one file).</remarks>
function Emit(const pArgs: TQuestionArgs; const pOutDir: string): TChartResult;
var
  Found: Boolean;
begin
  var Store: ISymbolStore:= TSQLiteSymbolStore.Create(pArgs.GuardedDb, True);  // dl:ok object-leak@8a34 -- REVIEWED 2026-10-17: ISymbolStore is reference-counted and released at scope exit, as in Q.Butterfly
  var Index:= TChartsIndex.Create(pArgs.GuardedDb);
  try
    { ---- 1. the index-wide pre-check, before anything else ---- }
    var IdxRegs:= 0;
    var IdxIfaces:= 0;
    var Pre:= Index.Query('SELECT COUNT(*) AS n, COUNT(DISTINCT interface_name) AS ifaces FROM di_bindings');
    try
      if Pre.Count > 0 then
      begin
        IdxRegs:= Pre[0].I('n');
        IdxIfaces:= Pre[0].I('ifaces');
      end;
    finally
      Pre.Free;
    end;
    if IdxRegs = 0 then
      raise EChartsQuestion.Create('wiring: this index has NO DI registrations at all (di_bindings is empty), so no interface in ' +
        'it can be shown as wired. Ask the index that holds the container configuration.');

    { ---- 2. the selection: the kind check the verb cannot do ---- }
    var Sel:= Index.ResolveMemberSelection(pArgs.Target, ['interface'], True,
      'wiring selects an INTERFACE -- ask hierarchy for a class', Found);
    var IName:= if Found then Sel.Name else pArgs.Target.Substring(pArgs.Target.LastIndexOf('.') + 1);
    if not Found then
    begin
      var Reg:= Index.Query('SELECT COUNT(*) AS n FROM di_bindings WHERE interface_name = ''' + TChartsIndex.SqlText(IName) + '''');
      var RegCount:= 0;
      try
        if Reg.Count > 0 then
          RegCount:= Reg[0].I('n');
      finally
        Reg.Free;
      end;
      if RegCount = 0 then
        raise EChartsQuestion.Create(Format('%s is not declared in this index and nothing in it registers that name. ' +
          'This index has %d registration(s) over %d interface(s).', [pArgs.Target, IdxRegs, IdxIfaces]));
    end;

    { ---- 3. the three store reads behind the verb ---- }
    var Impls:= Store.FindImplementationsOf(IName);
    var Sites:= Store.FindDiResolveSites(IName);
    var Handlers:= Store.FindEventHandlersForForm(IName);
    var ImplTop:= TRanked<TDiBindingRow>.TopRanked(Impls, pArgs.Cap, nil);
    var ResTop:= TRanked<TReference>.TopRanked(Sites, pArgs.Cap, nil);

    var Sb:= TStringBuilder.Create;
    try
      Sb.AppendLine('digraph wiring {');
      Sb.AppendLine('  rankdir=LR; bgcolor="transparent"; compound=true;');
      Sb.AppendLine('  nodesep=0.3; ranksep=1.4; splines=spline;');
      Sb.AppendLine(Format('  graph [fontname="%s"];', [FONT_SANS]));
      Sb.AppendLine(Format('  node  [shape=plaintext, fontname="%s", fontsize=14];', [FONT_MONO]));
      Sb.AppendLine(Format('  edge  [fontname="%s", fontsize=11, color="%s", penwidth=1.4, arrowsize=0.7];', [FONT_MONO, LINE_INK]));
      Sb.AppendLine('');

      var NodeId:= 0;
      var Clusters:= 0;
      var Anchored:= 0;

      { ---- LEFT: registrations; the lifetime is ON the row ---- }
      Inc(NodeId);
      Inc(Clusters);
      var LNid:= 'n' + IntToStr(NodeId);
      var RegRows: TArray<TDotRow>:= [];
      for var B in ImplTop.Shown do
      begin
        Inc(Anchored);
        var BFile:= Store.GetFilePath(B.FileId);
        RegRows:= RegRows + [TDotRow.Anchored(B.ImplName, B.StartLine, RowHref(BFile, B.StartLine),
          Format('%s registered as %s with lifetime %s -- %s:%d', [B.ImplName, IName, B.Lifetime, FileNameOf(BFile), B.StartLine]),
          B.Lifetime)];
      end;
      if Length(Impls) = 0 then
      begin
        // 0 registrations is an ANSWER (N16), readable only next to the index-wide total
        RegRows:= RegRows + [NoteRow('nothing in this index registers it')];
        RegRows:= RegRows + [NoteRow(Format('this index has %d registration(s) in total', [IdxRegs]))];
      end;
      var Dt:= DisclosureText(ImplTop.HiddenRows, 0, 'registrations');
      if Dt <> '' then
        RegRows:= RegRows + [NoteRow(Dt)];
      var LPorts:= AddRowCluster(Sb, 'cluster_reg_' + IntToStr(NodeId), LNid, 'registered by',
        Format('%d registration%s', [Length(Impls), if Length(Impls) <> 1 then 's' else '']), RegRows,
        MakeStyle(REG_BORDER, REG_FILL, REG_HDR));

      { ---- FOCUS: the interface ---- }
      Inc(NodeId);
      Inc(Clusters);
      var FNid:= 'n' + IntToStr(NodeId);
      if Found then
        Inc(Anchored);
      var Lifetimes:= DistinctLifetimes(Impls);
      Sb.AppendLine(Format('  subgraph cluster_focus_%d {', [NodeId]));
      Sb.AppendLine(Format('    style="rounded,filled"; color="%s"; fillcolor="%s"; penwidth=2;', [FOCUS_BORDER, FOCUS_FILL]));
      Sb.AppendLine('    label=""; margin=10;');
      Sb.AppendLine(Format('    %s [label=<%s>];', [FNid, FocusTable(IName, Found, Sel, IdxRegs, IdxIfaces, Lifetimes, Length(Impls))]));
      Sb.AppendLine('  }');

      { ---- RIGHT: resolution sites ---- }
      Inc(NodeId);
      Inc(Clusters);
      var RNid:= 'n' + IntToStr(NodeId);
      var UseRows: TArray<TDotRow>:= [];
      for var Rs in ResTop.Shown do
      begin
        var RFile:= Store.GetFilePath(Rs.FileId);
        var Owner:= SiteOwner(Index, RFile, Rs.StartLine);
        Inc(Anchored);
        var Caption:= if Owner <> '' then Owner else UnitNameOf(RFile);
        var Note:= if Owner <> '' then '' else 'not inside a routine body';
        UseRows:= UseRows + [TDotRow.Anchored(Caption, Rs.StartLine, RowHref(RFile, Rs.StartLine),
          Format('resolves %s -- %s:%d', [IName, FileNameOf(RFile), Rs.StartLine]), Note)];
      end;
      if Length(Sites) = 0 then
        UseRows:= UseRows + [NoteRow('no resolution site in this index')];
      Dt:= DisclosureText(ResTop.HiddenRows, 0, 'sites');
      if Dt <> '' then
        UseRows:= UseRows + [NoteRow(Dt)];
      var RPorts:= AddRowCluster(Sb, 'cluster_use_' + IntToStr(NodeId), RNid, 'resolved at',
        Format('%d site%s', [Length(Sites), if Length(Sites) <> 1 then 's' else '']), UseRows,
        MakeStyle(USE_BORDER, USE_FILL, USE_HDR));

      { ---- event_handlers, only when the corpus has them ---- }
      if Length(Handlers) > 0 then
      begin
        Inc(NodeId);
        Inc(Clusters);
        var HNid:= 'n' + IntToStr(NodeId);
        var HRows: TArray<TDotRow>:= [];
        for var H in Handlers do
        begin
          var HFile:= Store.GetFilePath(H.FileId);
          if HFile <> '' then
          begin
            Inc(Anchored);
            // the PS label reads $h.name, a key the verb never writes (it writes `handler`): always the unit name
            HRows:= HRows + [TDotRow.Anchored(UnitNameOf(HFile), H.StartLine, RowHref(HFile, H.StartLine),
              Format('event handler -- %s:%d', [FileNameOf(HFile), H.StartLine]), '')];
          end
          else  // cannot fire: GetFilePath of an indexed FileId is never empty; kept as the PS [string]$h
            HRows:= HRows + [NoteRow(Format('@{handler=%s; file=; line=%d}', [H.NameText, H.StartLine]))];
        end;
        AddRowCluster(Sb, 'cluster_eh_' + IntToStr(NodeId), HNid, 'event handlers', IntToStr(Length(Handlers)), HRows,
          MakeStyle(EH_BORDER, EH_FILL, EH_HDR));
        Sb.AppendLine(Format('  %s -> %s [style=invis];', [FNid, HNid]));
      end;

      { ---- edges: registration -> interface -> resolution (note rows keep their port) ---- }
      Sb.AppendLine('');
      for var P in LPorts do
        Sb.AppendLine(Format('  %s -> %s:p1 [color="%s"];', [P, FNid, REG_BORDER]));
      for var P in RPorts do
        Sb.AppendLine(Format('  %s:p1 -> %s [color="%s"];', [FNid, P, USE_BORDER]));
      Sb.AppendLine('}');

      { ---- lay out ---- }
      var Msgs: TArray<string>;
      var Base:= 'wiring_' + TRegEx.Replace(IName, '[^A-Za-z0-9]', '_');
      Result.Layout:= DotLayout(pArgs.Dot, Sb.ToString, pOutDir, Base, Msgs);

      Result.LeftCount:= Length(Impls);
      Result.RightCount:= Length(Sites);
      Result.ClickTargets:= Result.Layout.Anchors;
      Result.AllClickable:= Result.Layout.Anchors >= Anchored;
      Result.Fields:= [TMetaField.Str('Interface', IName), TMetaField.Bool('DeclaredHere', Found),
        TMetaField.Int('Registrations', Length(Impls)), TMetaField.Int('ResolvedAt', Length(Sites)),
        TMetaField.Int('EventHandlers', Length(Handlers)), TMetaField.Str('Lifetimes', string.Join(',', Lifetimes)),
        TMetaField.Int('IndexRegs', IdxRegs), TMetaField.Int('IndexIfaces', IdxIfaces),
        TMetaField.Int('Clusters', Clusters), TMetaField.Int('ClickTargets', Result.Layout.Anchors),
        TMetaField.Int('Expected', Anchored), TMetaField.Bool('AllClickable', Result.AllClickable)];
    finally
      Sb.Free;
    end;
  finally
    Index.Free;

  end;
end;

initialization
  RegisterChartQuestion(WIRING_ID, Emit);

end.
