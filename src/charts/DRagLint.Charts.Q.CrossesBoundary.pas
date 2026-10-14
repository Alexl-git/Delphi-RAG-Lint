unit DRagLint.Charts.Q.CrossesBoundary;

(* The `crosses-boundary` question in-process: a port of charts\src\Emit-CrossesBoundary.ps1
  (spec s11; the PS output is the reference, P3). Whether a method's work leaves the
  process, on three independent pieces of evidence -- its ZONE, the protocol COMMANDS
  (enum_value refs) it names, and the call edges INTO a transport routine -- never on a
  callee walk, which stops dead at a withheld transport file. The transport units are
  matched by a naming convention (Pipes.% | uPipe% | uBroadcast%) and the chart says so.
  With -CounterpartDb the routines of the OTHER index that name the same commands are
  drawn in their own dashed cluster, joined by command name. No evidence is said as
  "no evidence in this index", never "does not cross".

  PS traps closed: `Sort-Object -Unique` over the command names drops case-insensitive
  duplicates (SortUniqueNames); the counterpart goes through the clone guard like the
  index itself; `[int]$null` is 0 (a routine without a body line clicks to line 0, as in
  the PS). *)

interface

const
  /// <summary>The registered question id.</summary>
  CROSSES_BOUNDARY_ID = 'crosses-boundary';

implementation

uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.RegularExpressions,
  DRagLint.Charts.Question, DRagLint.Charts.Index, DRagLint.Charts.Text, DRagLint.Charts.Dot,
  DRagLint.Charts.Sql, DRagLint.Charts.Tools;

const
  CMD_BORDER = '#7C3AED';
  CMD_FILL = '#F3EEFF';
  CMD_HDR = '#7C3AED';
  PIPE_BORDER = '#B02A37';
  PIPE_FILL = '#FDECEE';
  PIPE_HDR = '#B02A37';
  FAR_BORDER = '#B45309';
  FAR_FILL = '#FEF6EC';
  FAR_HDR = '#B45309';
  FOCUS_BORDER = '#3B5BDB';
  FOCUS_FILL = '#EDF2FF';
  FOCUS_HDR = '#3B5BDB';
  NONE_FILL = '#F3F4F6';
  NONE_HDR = '#6B7280';
  ROW_INK = '#1F2933';
  LINE_INK = '#8A94A6';
  FONT_MONO = 'Consolas';
  FONT_SANS = 'Segoe UI';
  SOLID_STYLE = 'rounded,filled';
  DASHED_STYLE = 'rounded,filled,dashed';
  { Emit-CrossesBoundary -BoundaryPattern: the transport units, by naming convention }
  BOUNDARY_PATTERN = 'Pipes.%|uPipe%|uBroadcast%';
  VERDICT_SELF = 'is the boundary';
  VERDICT_CROSSES = 'crosses';
  VERDICT_NONE = 'no evidence in this index';
  HINT = 'crosses-boundary selects a METHOD';

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

{ the counterpart's routines naming the same commands; nil when there is nothing to ask }
function FarRows(const pArgs: TQuestionArgs; pCmdRows: TObjectList<TIndexRow>): TObjectList<TIndexRow>;
var
  Note: string;
begin
  Result:= nil;
  if (pArgs.CounterpartDb = '') or (pCmdRows.Count = 0) then
    Exit;
  var Names: TArray<string>:= [];
  for var C in pCmdRows do
    Names:= Names + [C.S('nm')];
  var Far:= TChartsIndex.Create(CloneDb(pArgs.CounterpartDb, pArgs.CloneRoot, Note));
  try
    Result:= Far.Query(
      'SELECT tgt.name AS cmd, encl.qualified_name AS routine,' + sLineBreak +
      '       encl.impl_start_line AS line, ef.path AS path, COUNT(*) AS n' + sLineBreak +
      '  FROM refs r' + sLineBreak +
      '  JOIN symbols tgt ON tgt.id = r.symbol_id' + sLineBreak +
      '  JOIN symbols encl ON encl.id = r.enclosing_symbol_id' + sLineBreak +
      '  JOIN files ef ON ef.id = encl.file_id' + sLineBreak +
      ' WHERE tgt.kind = ''enum_value'' AND tgt.name IN (' + TChartsIndex.SqlInList(SortUniqueNames(Names)) + ')' + sLineBreak +
      ' GROUP BY tgt.name, encl.qualified_name, encl.impl_start_line, ef.path' + sLineBreak +
      ' ORDER BY n DESC');
  finally
    Far.Free;
  end;
end;

function Emit(const pArgs: TQuestionArgs; const pOutDir: string): TChartResult;
var
  Found: Boolean;
  CmdRows, PipeCalls, Far: TObjectList<TIndexRow>;
begin
  var Index:= TChartsIndex.Create(pArgs.GuardedDb);
  CmdRows:= nil;
  PipeCalls:= nil;
  Far:= nil;
  var Sb:= TStringBuilder.Create;
  try
    var Sel:= Index.ResolveMemberSelection(pArgs.Target, ['method', 'function', 'procedure', 'constructor', 'destructor'],
      False, HINT, Found);
    var MyZone:= PathZone(Sel.Path, IndexRootLen(Index));

    { ---- boundary unit predicate ---- }
    var Likes: TArray<string>:= [];
    for var P in BOUNDARY_PATTERN.Split(['|']) do
      Likes:= Likes + ['u.qualified_name LIKE ''' + TChartsIndex.SqlText(P) + ''''];
    var LikeSql:= string.Join(' OR ', Likes);

    var SelfRows:= Index.Query(
      'SELECT 1 AS x FROM symbols u JOIN files f ON f.id = u.file_id' + sLineBreak +  // dl:ok sql-injection-concat@f1ea -- REVIEWED 2026-10-14: read-only index query; the path goes through SqlText and the LIKE patterns are the BOUNDARY_PATTERN constant, each through SqlText
      ' WHERE u.kind=''unit'' AND f.path = ''' + TChartsIndex.SqlText(Sel.Path) + ''' AND (' + LikeSql + ')');
    var SelfIsPipe:= SelfRows.Count > 0;
    SelfRows.Free;

    { ---- evidence 2: protocol commands this method references ---- }
    CmdRows:= Index.Query(
      'SELECT tgt.qualified_name AS cmd, tgt.name AS nm, COUNT(*) AS n,' + sLineBreak +
      '       MIN(r.start_line) AS line, f.path AS path' + sLineBreak +
      '  FROM refs r' + sLineBreak +
      '  JOIN symbols tgt ON tgt.id = r.symbol_id' + sLineBreak +
      '  JOIN files f ON f.id = r.file_id' + sLineBreak +
      Format(' WHERE r.enclosing_symbol_id = %d AND tgt.kind = ''enum_value''', [Sel.Id]) + sLineBreak +
      ' GROUP BY tgt.qualified_name, tgt.name, f.path' + sLineBreak +
      ' ORDER BY n DESC');

    { ---- evidence 3: call edges from this method into a transport routine ---- }
    PipeCalls:= Index.Query(
      'SELECT DISTINCT s.qualified_name AS q, s.impl_start_line AS line, f.path AS path' + sLineBreak +
      '  FROM call_edges ce' + sLineBreak +
      '  JOIN refs r ON r.id = ce.ref_id' + sLineBreak +
      '  JOIN symbols s ON s.id = ce.target_symbol_id' + sLineBreak +
      '  JOIN files f ON f.id = s.file_id' + sLineBreak +
      '  JOIN symbols u ON u.file_id = f.id AND u.kind=''unit''' + sLineBreak +
      Format(' WHERE r.enclosing_symbol_id = %d AND (%s)', [Sel.Id, LikeSql]) + sLineBreak +
      ' ORDER BY s.qualified_name');

    { ---- the counterpart index, if one was given ---- }
    Far:= FarRows(pArgs, CmdRows);
    var FarCount:= if Far = nil then 0 else Far.Count;
    var FarName:= if pArgs.CounterpartDb = '' then '' else ChangeFileExt(FileNameOf(pArgs.CounterpartDb), '');

    { ---- the verdict ---- }
    var Verdict:= if SelfIsPipe then VERDICT_SELF
      else if (CmdRows.Count > 0) or (PipeCalls.Count > 0) then VERDICT_CROSSES
      else VERDICT_NONE;

    { ---- dot ---- }
    Sb.AppendLine('digraph crossesboundary {');
    Sb.AppendLine('  rankdir=LR; bgcolor="transparent"; compound=true;');
    Sb.AppendLine('  nodesep=0.35; ranksep=1.5; splines=spline;');
    Sb.AppendLine(Format('  graph [fontname="%s"];', [FONT_SANS]));
    Sb.AppendLine(Format('  node  [shape=plaintext, fontname="%s", fontsize=14];', [FONT_MONO]));
    Sb.AppendLine(Format('  edge  [fontname="%s", fontsize=11, color="%s", penwidth=1.4, arrowsize=0.7];', [FONT_MONO, LINE_INK]));
    Sb.AppendLine('');

    var NodeId:= 1;
    var Clusters:= 1;
    var Anchored:= 1;
    var FNid:= 'n' + IntToStr(NodeId);
    var FTbl:= TStringBuilder.Create;
    try
      FTbl.Append('<TABLE BORDER="0" CELLBORDER="0" CELLSPACING="3" CELLPADDING="5">');
      FTbl.Append(Format('<TR><TD ALIGN="LEFT" BGCOLOR="%s"><FONT COLOR="#FFFFFF" FACE="%s" POINT-SIZE="14"><B> %s </B></FONT></TD></TR>',
        [FOCUS_HDR, FONT_SANS, XmlText(Sel.Name)]));
      FTbl.Append(Format('<TR><TD PORT="p1" ALIGN="LEFT" HREF="%s" TITLE="%s">', [RowHref(Sel.Path, Sel.FocusLine), XmlText(Sel.QName)]));
      FTbl.Append(Format('<FONT COLOR="%s">%s</FONT>', [ROW_INK, XmlText(UnitNameOf(Sel.Path))]));
      FTbl.Append(Format('  <FONT COLOR="%s" POINT-SIZE="12">:%d</FONT></TD></TR>', [LINE_INK, Sel.FocusLine]));
      AddDisclosureRow(FTbl, Format('zone %s  &#183;  VERDICT: %s', [MyZone, Verdict]), LINE_INK);
      if SelfIsPipe then
        AddDisclosureRow(FTbl, 'declared inside the transport layer itself', LINE_INK);
      AddDisclosureRow(FTbl, Format('%d protocol command(s)  &#183;  %d call(s) into a transport routine', [CmdRows.Count, PipeCalls.Count]), LINE_INK);
      if Verdict = VERDICT_NONE then
        AddDisclosureRow(FTbl, 'this is NOT "does not cross" -- absence of an edge is not absence of a call', LINE_INK);
      if (PipeCalls.Count = 0) and (CmdRows.Count > 0) then
        AddDisclosureRow(FTbl, 'commands found but no transport call: the call may be an interface dispatch, or its edge may be missing', LINE_INK);
      AddDisclosureRow(FTbl, Format('transport units matched by naming convention (%s)', [BOUNDARY_PATTERN]), LINE_INK);
      var EdgelessNote:= TChartsIndex.EdgelessDisclosure(Index.EdgelessFiles);
      if EdgelessNote <> '' then
        AddDisclosureRow(FTbl, EdgelessNote, LINE_INK);
      if pArgs.CounterpartDb = '' then
        AddDisclosureRow(FTbl, 'no counterpart index given -- the far side is not shown', LINE_INK);
      FTbl.Append('</TABLE>');
      Sb.AppendLine(Format('  subgraph cluster_focus_%d {', [NodeId]));
      Sb.AppendLine(Format('    style="rounded,filled"; color="%s"; fillcolor="%s"; penwidth=2;', [FOCUS_BORDER, FOCUS_FILL]));
      Sb.AppendLine('    label=""; margin=10;');
      Sb.AppendLine(Format('    %s [label=<%s>];', [FNid, FTbl.ToString]));
      Sb.AppendLine('  }');
    finally
      FTbl.Free;
    end;

    var AddEvidence:= procedure(const pTitle, pSub: string; const pCells: TArray<TDotRow>; const pBorder, pFill, pHdr, pStyle: string)
      begin
        Inc(NodeId);
        Inc(Clusters);
        var Nid:= 'n' + IntToStr(NodeId);
        var Style:= TClusterStyle.Make(pBorder, pFill, pHdr);
        Style.RowInk:= ROW_INK;
        Style.LineInk:= LINE_INK;
        Style.FontSans:= FONT_SANS;
        Style.Style:= pStyle;
        AddRowCluster(Sb, 'cluster_ev_' + IntToStr(NodeId), Nid, pTitle, pSub, pCells, Style);
        Sb.AppendLine(Format('  %s:p1 -> %s [color="%s"];', [FNid, Nid, pBorder]));
      end;

    if CmdRows.Count > 0 then
    begin
      var Top:= TRanked<TIndexRow>.TopRanked(CmdRows.ToArray, pArgs.Cap, function(pR: TIndexRow): Integer begin Result:= pR.I('n'); end);
      var Cells: TArray<TDotRow>:= [];
      for var C in Top.Shown do
      begin
        Inc(Anchored);
        Cells:= Cells + [TDotRow.Anchored(C.S('nm'), C.I('line'), RowHref(C.S('path'), C.I('line')),
          Format('%s -- referenced %s time(s) in this method', [C.S('cmd'), C.S('n')]),
          if C.I('n') > 1 then C.S('n') + ' refs' else '')];
      end;
      var Dt:= DisclosureText(Top.HiddenRows, 0, 'commands');
      if Dt <> '' then
        Cells:= Cells + [NoteRow(Dt)];
      AddEvidence('commands spoken', IntToStr(CmdRows.Count), Cells, CMD_BORDER, CMD_FILL, CMD_HDR, SOLID_STYLE);
    end;

    if PipeCalls.Count > 0 then
    begin
      var Top:= TRanked<TIndexRow>.TopRanked(PipeCalls.ToArray, pArgs.Cap, function(pR: TIndexRow): Integer begin Result:= pR.I('line'); end);
      var Cells: TArray<TDotRow>:= [];
      for var C in Top.Shown do
      begin
        Inc(Anchored);
        var U:= UnitNameOf(C.S('path'));
        Cells:= Cells + [TDotRow.Anchored(ShortName(C.S('q'), U), C.I('line'), RowHref(C.S('path'), C.I('line')),
          Format('%s -- %s:%s', [C.S('q'), FileNameOf(C.S('path')), C.S('line')]), U)];
      end;
      var Dt:= DisclosureText(Top.HiddenRows, 0, 'routines');
      if Dt <> '' then
        Cells:= Cells + [NoteRow(Dt)];
      AddEvidence('reaches the transport', IntToStr(PipeCalls.Count), Cells, PIPE_BORDER, PIPE_FILL, PIPE_HDR, SOLID_STYLE);
    end;

    if FarCount > 0 then
    begin
      var Top:= TRanked<TIndexRow>.TopRanked(Far.ToArray, pArgs.Cap, function(pR: TIndexRow): Integer begin Result:= pR.I('n'); end);
      var Cells: TArray<TDotRow>:= [];
      for var C in Top.Shown do
      begin
        Inc(Anchored);
        Cells:= Cells + [TDotRow.Anchored(ShortName(C.S('routine'), UnitNameOf(C.S('path'))), C.I('line'), RowHref(C.S('path'), C.I('line')),
          Format('%s handles %s -- from the %s index', [C.S('routine'), C.S('cmd'), FarName]), C.S('cmd'))];
      end;
      var Dt:= DisclosureText(Top.HiddenRows, 0, 'routines');
      if Dt <> '' then
        Cells:= Cells + [NoteRow(Dt)];
      Cells:= Cells + [NoteRow(Format('from a DIFFERENT index (%s), joined by command name', [FarName]))];
      AddEvidence('the far side', Format('%d routine(s)', [FarCount]), Cells, FAR_BORDER, FAR_FILL, FAR_HDR, DASHED_STYLE);
    end;

    if Verdict = VERDICT_NONE then
    begin
      Inc(NodeId);
      Inc(Clusters);
      var Style:= TClusterStyle.Make(LINE_INK, NONE_FILL, NONE_HDR);
      Style.RowInk:= ROW_INK;
      Style.LineInk:= LINE_INK;
      Style.FontSans:= FONT_SANS;
      Style.Style:= DASHED_STYLE;
      AddRowCluster(Sb, 'cluster_none_' + IntToStr(NodeId), 'n' + IntToStr(NodeId), 'no boundary evidence', 'in this index',
        [NoteRow('no protocol command referenced, no call into a transport unit'),
         NoteRow('absence is NOT proof: an unresolved or cleared edge looks the same as no call')], Style);
      Sb.AppendLine(Format('  %s:p1 -> n%d [style=dashed];', [FNid, NodeId]));
    end;
    Sb.AppendLine('}');

    var Msgs: TArray<string>;
    Result.Layout:= DotLayout(pArgs.Dot, Sb.ToString, pOutDir, 'boundary_' + TRegEx.Replace(Sel.QName, '[^A-Za-z0-9]', '_'), Msgs);
    Result.LeftCount:= CmdRows.Count;
    Result.RightCount:= PipeCalls.Count;
    Result.ClickTargets:= Result.Layout.Anchors;
    Result.AllClickable:= Result.Layout.Anchors >= Anchored;
    Result.Fields:= [TMetaField.Str('Qname', Sel.QName), TMetaField.Str('Zone', MyZone), TMetaField.Str('Verdict', Verdict),
      TMetaField.Int('Commands', CmdRows.Count), TMetaField.Int('PipeCalls', PipeCalls.Count),
      TMetaField.Int('FarSide', FarCount), TMetaField.Bool('SelfIsPipe', SelfIsPipe),
      TMetaField.Int('Clusters', Clusters), TMetaField.Int('ClickTargets', Result.Layout.Anchors),
      TMetaField.Int('Expected', Anchored), TMetaField.Bool('AllClickable', Result.AllClickable)];
  finally
    Sb.Free;
    Far.Free;
    PipeCalls.Free;
    CmdRows.Free;
    Index.Free;
  end;
end;

initialization
  RegisterChartQuestion(CROSSES_BOUNDARY_ID, Emit);

end.
