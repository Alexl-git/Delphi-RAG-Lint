unit DRagLint.Charts.Q.ClassSurface;

(* The `class-surface` question in-process: a port of charts\src\Emit-ClassSurface.ps1
  (spec s11; the PS output is the reference, P3). What a TYPE exposes, grouped by
  visibility: the members come structured from symbols by parent_id (never from the
  `surface` verb's flat source slice), the visibility from symbols.modifiers. Each
  visibility cluster is capped at -SurfaceCap rows (methods before properties before
  fields, then by name) and discloses what it left out; one edge per cluster.

  PS traps closed: the [ordered] dictionaries ByKind / ByVisibility are case-insensitive
  (a later key that differs only in case overwrites the value and keeps the first
  position); `-notcontains` and `switch -Regex` are case-insensitive; Measure-Object -Sum
  is a [double], so Shown, Hidden and Expected are written as 24.0 in meta.json;
  IsNullOrWhiteSpace is PsTrim, not Delphi Trim. *)

interface

const
  /// <summary>The registered question id.</summary>
  CLASS_SURFACE_ID = 'class-surface';

implementation

uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.RegularExpressions,
  DRagLint.Charts.Question, DRagLint.Charts.Index, DRagLint.Charts.Text, DRagLint.Charts.Dot,
  DRagLint.Charts.Source;

const
  PUB_BORDER = '#0F766E';
  PUB_FILL = '#E2F1EF';
  PUB_HDR = '#0F766E';
  PROT_BORDER = '#B45309';
  PROT_FILL = '#FEF6EC';
  PROT_HDR = '#B45309';
  PRIV_BORDER = '#98A2B3';
  PRIV_FILL = '#F4F5F7';
  PRIV_HDR = '#98A2B3';
  FOCUS_BORDER = '#0E7490';
  FOCUS_FILL = '#ECFEFF';
  FOCUS_HDR = '#0E7490';
  ROW_INK = '#1F2933';
  LINE_INK = '#8A94A6';
  FOCUS_INK = '#0B3F39';
  FONT_MONO = 'Consolas';
  FONT_SANS = 'Segoe UI';
  NO_VIS = '(no visibility recorded)';
  HINT = 'class-surface needs a type; a unit has no members to expose';
  { Delphi's own order, most visible first }
  VIS_ORDER: array[0..5] of string = ('published', 'public', 'protected', 'strict protected', 'private', 'strict private');

type
  { a PS [ordered] dictionary of counts: case-insensitive keys, insertion order }
  TCounts = record
    Keys  : TArray<string>;
    Values: TArray<Integer>;
    function IndexOf(const pKey: string): Integer;
    procedure Put(const pKey: string; pValue: Integer);
    function Fields: TArray<TMetaField>;
  end;

  TVisCluster = record
    Vis   : string;
    Total : Integer;
    Hidden: Integer;
    Rows  : TArray<TDotRow>;
  end;

function TCounts.IndexOf(const pKey: string): Integer;
begin
  for var K:= 0 to High(Keys) do
    if SameText(Keys[K], pKey) then
      Exit(K);
  Result:= -1;
end;

procedure TCounts.Put(const pKey: string; pValue: Integer);
begin
  var K:= IndexOf(pKey);
  if K >= 0 then
    Values[K]:= pValue
  else
  begin
    Keys:= Keys + [pKey];
    Values:= Values + [pValue];
  end;
end;

function TCounts.Fields: TArray<TMetaField>;
begin
  SetLength(Result, Length(Keys));
  for var K:= 0 to High(Keys) do
    Result[K]:= TMetaField.Int(Keys[K], Values[K]);
end;

function Emit(const pArgs: TQuestionArgs; const pOutDir: string): TChartResult;
var
  ByKind, ByVis: TCounts;
  Found: Boolean;
begin
  ByKind:= Default(TCounts);
  ByVis:= Default(TCounts);
  var Index:= TChartsIndex.Create(pArgs.GuardedDb);
  try
    { ---- 1. the type ---- }
    var Sel:= Index.ResolveMemberSelection(pArgs.Target, ['class', 'interface', 'record'], False, HINT, Found);
    var UnitName:= UnitNameOf(Sel.Path);
    var QText:= TChartsIndex.SqlText(Sel.QName);

    { ---- 2. the members, structured: aggregate totals first ---- }
    var Total:= 0;
    var Rows:= Index.Query(
      'SELECT c.kind AS kind, COUNT(*) AS n' + sLineBreak +
      '  FROM symbols c JOIN symbols t ON t.id = c.parent_id' + sLineBreak +
      ' WHERE t.qualified_name = ''' + QText + '''' + sLineBreak +
      ' GROUP BY 1 ORDER BY 2 DESC');
    try
      for var R in Rows do
      begin
        ByKind.Put(R.S('kind'), R.I('n'));
        Inc(Total, R.I('n'));
      end;
    finally
      Rows.Free;
    end;
    if Total = 0 then
      raise EChartsQuestion.CreateFmt('%s is a %s with no members in this index', [Sel.QName, Sel.Kind]);

    Rows:= Index.Query(
      'SELECT CASE WHEN c.modifiers IS NULL OR c.modifiers = '''' THEN ''' + NO_VIS + '''' + sLineBreak +
      '            ELSE c.modifiers END AS vis, COUNT(*) AS n' + sLineBreak +
      '  FROM symbols c JOIN symbols t ON t.id = c.parent_id' + sLineBreak +
      ' WHERE t.qualified_name = ''' + QText + '''' + sLineBreak +
      ' GROUP BY 1 ORDER BY 2 DESC');
    try
      for var R in Rows do
        ByVis.Put(R.S('vis'), R.I('n'));
    finally
      Rows.Free;
    end;

    { ---- 3. the rows that will actually be DRAWN ---- }
    var VisKeys: TArray<string>:= [];
    for var V in VIS_ORDER do
      if ByVis.IndexOf(V) >= 0 then
        VisKeys:= VisKeys + [V];
    for var V in ByVis.Keys do
    begin
      var Known:= False;
      for var O in VIS_ORDER do
        Known:= Known or SameText(O, V);
      if not Known then
        VisKeys:= VisKeys + [V];
    end;

    var FileName:= FileNameOf(Sel.Path);
    var Clusters: TArray<TVisCluster>:= [];
    var Shown:= 0;
    var Hidden:= 0;
    for var Vis in VisKeys do
    begin
      var C:= Default(TVisCluster);
      C.Vis:= Vis;
      C.Total:= ByVis.Values[ByVis.IndexOf(Vis)];
      C.Rows:= [];
      var Pred:= if SameText(Vis, NO_VIS) then '(c.modifiers IS NULL OR c.modifiers = '''')'
        else 'c.modifiers = ''' + TChartsIndex.SqlText(Vis) + '''';
      Rows:= Index.Query(
        'SELECT c.kind AS kind, c.name AS name, c.signature AS signature,' + sLineBreak +
        '       c.start_line AS start_line, c.impl_start_line AS impl_start_line,' + sLineBreak +
        '       c.is_virtual AS is_virtual' + sLineBreak +
        '  FROM symbols c JOIN symbols t ON t.id = c.parent_id' + sLineBreak +
        ' WHERE t.qualified_name = ''' + QText + ''' AND ' + Pred + sLineBreak +
        ' ORDER BY CASE c.kind WHEN ''constructor'' THEN 0 WHEN ''destructor'' THEN 1' + sLineBreak +
        '                      WHEN ''method'' THEN 2 WHEN ''property'' THEN 3' + sLineBreak +
        '                      WHEN ''field'' THEN 4 ELSE 5 END, c.name' + sLineBreak +
        ' LIMIT ' + IntToStr(pArgs.SurfaceCap));
      try
        for var R in Rows do
        begin
          var Ln:= if R.I('impl_start_line') <> 0 then R.I('impl_start_line') else R.I('start_line');
          var Sig:= R.S('signature');
          if PsTrim(Sig) = '' then
            Sig:= R.S('kind') + ' ' + R.S('name');
          var Note:= if R.I('is_virtual') = 1 then R.S('kind') + ', virtual' else R.S('kind');
          C.Rows:= C.Rows + [TDotRow.Anchored(R.S('name'), Ln, RowHref(Sel.Path, Ln),
            Format('%s  --  %s:%d', [Sig, FileName, Ln]), Note)];
        end;
        C.Hidden:= C.Total - Rows.Count;
        if C.Hidden < 0 then
          C.Hidden:= 0;
        Inc(Shown, Rows.Count);
      finally
        Rows.Free;
      end;
      Inc(Hidden, C.Hidden);
      Clusters:= Clusters + [C];
    end;
    if Shown + Hidden <> Total then
      raise EChartsQuestion.CreateFmt('class-surface: shown %d + hidden %d does not equal %d members -- the cap accounting is wrong',
        [Shown, Hidden, Total]);

    { ---- 4. dot ---- }
    var Sb:= TStringBuilder.Create;
    try
      Sb.AppendLine('digraph classsurface {');
      Sb.AppendLine('  rankdir=LR; bgcolor="transparent"; compound=true;');
      Sb.AppendLine('  nodesep=0.35; ranksep=1.2; splines=spline;');
      Sb.AppendLine(Format('  graph [fontname="%s"];', [FONT_SANS]));
      Sb.AppendLine(Format('  node  [shape=plaintext, fontname="%s", fontsize=14];', [FONT_MONO]));
      Sb.AppendLine(Format('  edge  [fontname="%s", fontsize=11, color="%s", penwidth=1.5, arrowsize=0.8];', [FONT_MONO, LINE_INK]));
      Sb.AppendLine('');

      Sb.AppendLine('  subgraph cluster_focus {');
      Sb.AppendLine(Format('    style="rounded,filled"; color="%s"; fillcolor="%s"; penwidth=3;', [FOCUS_BORDER, FOCUS_FILL]));
      Sb.AppendLine('    label=""; margin=12;');
      var FTbl:= TStringBuilder.Create;
      try
        FTbl.Append('<TABLE BORDER="0" CELLBORDER="0" CELLSPACING="3" CELLPADDING="7">');
        FTbl.Append(Format('<TR><TD ALIGN="LEFT" BGCOLOR="%s"><FONT COLOR="#FFFFFF" FACE="%s" POINT-SIZE="14"><B> %s &#183; %s </B></FONT></TD></TR>',
          [FOCUS_HDR, FONT_SANS, XmlText(UnitName), Sel.Kind]));
        FTbl.Append(Format('<TR><TD HREF="%s" TITLE="%s"><FONT COLOR="%s" POINT-SIZE="18"><B>%s</B></FONT></TD></TR>',
          [RowHref(Sel.Path, Sel.FocusLine), XmlText(Format('%s  --  %s:%d', [Sel.QName, FileName, Sel.FocusLine])),
           FOCUS_INK, XmlText(Sel.Name)]));
        var KindParts: TArray<string>:= [];
        for var K:= 0 to High(ByKind.Keys) do
          KindParts:= KindParts + [Format('%d %s', [ByKind.Values[K], ByKind.Keys[K]])];
        AddDisclosureRow(FTbl, Format('%d members: %s', [Total, string.Join(', ', KindParts)]), LINE_INK);
        FTbl.Append('</TABLE>');
        Sb.AppendLine(Format('    focus [label=<%s>];', [FTbl.ToString]));
      finally
        FTbl.Free;
      end;
      Sb.AppendLine('  }');

      var Edges: TArray<string>:= [];
      var Nid:= 0;
      for var C in Clusters do
      begin
        Inc(Nid);
        var Style: TClusterStyle;
        if TRegEx.IsMatch(C.Vis, 'published|^public', [roIgnoreCase]) then
          Style:= TClusterStyle.Make(PUB_BORDER, PUB_FILL, PUB_HDR)
        else if TRegEx.IsMatch(C.Vis, 'protected', [roIgnoreCase]) then
          Style:= TClusterStyle.Make(PROT_BORDER, PROT_FILL, PROT_HDR)
        else
          Style:= TClusterStyle.Make(PRIV_BORDER, PRIV_FILL, PRIV_HDR);
        Style.RowInk:= ROW_INK;
        Style.LineInk:= LINE_INK;
        Style.FontSans:= FONT_SANS;
        var Cells:= C.Rows;
        var D:= DisclosureText(C.Hidden, 0, 'members');
        if D <> '' then
          Cells:= Cells + [NoteRow(D)];
        AddRowCluster(Sb, 'cluster_vis' + IntToStr(Nid), 'nv' + IntToStr(Nid), C.Vis,
          Format('%d member%s', [C.Total, if C.Total <> 1 then 's' else '']), Cells, Style);
        Edges:= Edges + [Format('  focus -> nv%d [color="%s", penwidth=2];', [Nid, Style.Border])];
      end;

      Sb.AppendLine('');
      for var E in Edges do
        Sb.AppendLine(E);
      Sb.AppendLine('}');

      { ---- 5. lay out ---- }
      var Msgs: TArray<string>;
      Result.Layout:= DotLayout(pArgs.Dot, Sb.ToString, pOutDir, TRegEx.Replace(Sel.QName, '[^A-Za-z0-9]', '_') + '_surface', Msgs);
    finally
      Sb.Free;
    end;
    var Expected:= Shown + 1;
    Result.LeftCount:= Total;
    Result.RightCount:= Shown;
    Result.RightJson:= TMetaField.RealJson(Shown);
    Result.ClickTargets:= Result.Layout.Anchors;
    Result.AllClickable:= Result.Layout.Anchors >= Expected;
    Result.Fields:= [TMetaField.Str('Resolved', Sel.QName), TMetaField.Str('Kind', Sel.Kind),
      TMetaField.Int('Members', Total), TMetaField.Obj('ByKind', ByKind.Fields),
      TMetaField.Obj('ByVisibility', ByVis.Fields), TMetaField.Real('Shown', Shown),
      TMetaField.Real('Hidden', Hidden), TMetaField.Int('Clusters', Length(Clusters)),
      TMetaField.Int('ClickTargets', Result.Layout.Anchors), TMetaField.Real('Expected', Expected),
      TMetaField.Bool('AllClickable', Result.AllClickable)];
  finally
    Index.Free;
  end;
end;

initialization
  RegisterChartQuestion(CLASS_SURFACE_ID, Emit);

end.
