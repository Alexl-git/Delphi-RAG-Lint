unit DRagLint.Charts.Q.ShownWhere;

(* The `shown-where` question in-process: a port of charts\src\Emit-ShownWhere.ps1 (spec
  s11; the PS output is the reference, P3). Which UI controls display a database column,
  read from the DFM data bindings (string_literals of kind dfm-prop whose owner is a
  binding property) -- NOT from symbol_facts.ui_affinity, which is a thread-affinity hint
  with zero coverage on fields (the PS header measures it). Code-driven display is
  invisible to this route, and the chart says so.

  The index-wide pre-check runs FIRST: an index with no binding at all (a service) is
  refused as "not applicable", which is a different claim from "not shown".

  PS traps closed: Group-Object groups the bindings by .dfm path case-insensitively AND
  sorts its groups by key (CompareGroupKeys), keeping each group's rows in input order and
  naming the group after its first row; `Sort-Object { $_.Count } -Descending` is not
  stable (TPsSort reproduces its tie order); `-not $_.control` is true for NULL and ''. *)

interface

const
  /// <summary>The registered question id.</summary>
  SHOWN_WHERE_ID = 'shown-where';

implementation

uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.Generics.Defaults,
  System.RegularExpressions, DRagLint.Charts.Question, DRagLint.Charts.Index, DRagLint.Charts.Text,
  DRagLint.Charts.Dot, DRagLint.Charts.PsSort;

const
  FORM_BORDER = '#7C3AED';
  FORM_FILL = '#F3EEFF';
  FORM_HDR = '#7C3AED';
  FOCUS_BORDER = '#0F766E';
  FOCUS_FILL = '#E2F1EF';
  FOCUS_HDR = '#0F766E';
  ROW_INK = '#1F2933';
  LINE_INK = '#8A94A6';
  MORE_FILL = '#F3F4F6';
  MORE_HDR = '#6B7280';
  MORE_STYLE = 'rounded,filled,dashed';
  FONT_MONO = 'Consolas';
  FONT_SANS = 'Segoe UI';
  UNRESOLVED_CONTROL = '(unresolved control)';
  { the binding properties the PS measured; anything else is not a data binding }
  BIND: array[0..8] of string = ('DataBinding.FieldName', 'DataBinding.DataField', 'FieldName', 'DataField',
    'DataController.KeyFieldNames', 'Properties.KeyFieldNames',
    'DataController.DetailKeyFieldNames', 'DataController.MasterKeyFieldNames',
    'IndexFieldNames');

type
  { one Group-Object group: its name (the first row's key) and its rows, in input order }
  TFormGroup = class
    Name: string;
    Rows: TList<TIndexRow>;
    constructor Create(const pName: string);
    destructor Destroy; override;
  end;

constructor TFormGroup.Create(const pName: string);
begin
  inherited Create;
  Name:= pName;
  Rows:= TList<TIndexRow>.Create;
end;

destructor TFormGroup.Destroy;
begin
  Rows.Free;
  inherited Destroy;
end;

function BindList: TArray<string>;
begin
  SetLength(Result, Length(BIND));
  for var K:= 0 to High(BIND) do
    Result[K]:= BIND[K];
end;

function Plural(pCount: Integer): string;
begin
  Result:= if pCount <> 1 then 's' else '';
end;

(* Group-Object { [string]$_.dfm }: case-insensitive groups, sorted by key *)
function GroupByForm(const pRows: TObjectList<TIndexRow>; const pGroups: TObjectList<TFormGroup>): TArray<TFormGroup>;
begin
  var Slot:= TDictionary<string, TFormGroup>.Create(TIStringComparer.Ordinal);
  try
    for var R in pRows do
    begin
      var G: TFormGroup;
      if not Slot.TryGetValue(R.S('dfm'), G) then
      begin
        G:= TFormGroup.Create(R.S('dfm'));
        pGroups.Add(G);
        Slot.Add(G.Name, G);
      end;
      G.Rows.Add(R);
    end;
  finally
    Slot.Free;
  end;
  Result:= pGroups.ToArray;
  { keys are unique case-insensitively, so the order is total and no tie can move }
  TArray.Sort<TFormGroup>(Result, TComparer<TFormGroup>.Construct(
    function(const pL, pR: TFormGroup): Integer begin Result:= CompareGroupKeys(pL.Name, pR.Name); end));
end;

function Emit(const pArgs: TQuestionArgs; const pOutDir: string): TChartResult;
var
  Rows: TObjectList<TIndexRow>;
  Found: Boolean;
begin
  var Column:= pArgs.Target;
  var Index:= TChartsIndex.Create(pArgs.GuardedDb);
  try
    var InBind:= TChartsIndex.SqlInList(BindList);
    { ---- 1. index-wide pre-check FIRST ---- }
    var IdxRows:= 0;
    var IdxCols:= 0;
    var IdxForms:= 0;
    var Pre:= Index.Query(
      'SELECT COUNT(*) AS n, COUNT(DISTINCT text) AS cols, COUNT(DISTINCT file_id) AS forms' + sLineBreak +
      '  FROM string_literals' + sLineBreak +
      ' WHERE kind = ''dfm-prop'' AND owner_name IN (' + InBind + ')');
    try
      if Pre.Count > 0 then
      begin
        IdxRows:= Pre[0].I('n');
        IdxCols:= Pre[0].I('cols');
        IdxForms:= Pre[0].I('forms');
      end;
    finally
      Pre.Free;
    end;
    if IdxRows = 0 then
      raise EChartsQuestion.Create('shown-where: this index contains NO DFM data bindings at all, so the question is not ' +
        'applicable to it -- that is different from the column not being shown. A service or ' +
        'console project has no data-aware UI. Ask the index that holds the forms.');

    { ---- 2. the bindings for this column ---- }
    Rows:= Index.Query(
      'SELECT sl.text AS col, sl.owner_name AS prop, sl.start_line AS line,' + sLineBreak +
      '       f.path AS dfm, c.name AS control, c.qualified_name AS cq,' + sLineBreak +
      '       p.name AS parent' + sLineBreak +
      '  FROM string_literals sl' + sLineBreak +
      '  JOIN files f ON f.id = sl.file_id' + sLineBreak +
      '  LEFT JOIN symbols c ON c.id = sl.symbol_id' + sLineBreak +
      '  LEFT JOIN symbols p ON p.id = c.parent_id' + sLineBreak +
      ' WHERE sl.kind = ''dfm-prop'' AND UPPER(sl.text) = UPPER(''' + TChartsIndex.SqlText(Column) + ''')' + sLineBreak +
      '   AND sl.owner_name IN (' + InBind + ')' + sLineBreak +
      ' ORDER BY f.path, sl.start_line');
    var Groups:= TObjectList<TFormGroup>.Create(True);
    try
      if Rows.Count = 0 then
      begin
        var AsField:= Index.ResolveMemberSelection(Column, ['field', 'property'], True, 'shown-where selects a DB COLUMN', Found);
        var What:= if Found then Format('%s is a Delphi %s, and no DFM binds a column of that name', [AsField.QName, AsField.Kind])
          else Format('no DFM in this index binds a column called ''%s''', [Column]);
        raise EChartsQuestion.CreateFmt('%s. This chart reads DFM data bindings (%d in this index over %d columns); ' +
          'it cannot see code-driven display such as Label.Caption := Field.AsString, and ' +
          'symbol_facts.ui_affinity does NOT answer this question -- it is a thread-affinity hint ' +
          'carried by routines, with zero coverage on fields and properties.', [What, IdxRows, IdxCols]);
      end;

      var Unresolved:= 0;
      for var R in Rows do
        if R.S('control') = '' then
          Inc(Unresolved);
      var ByForm:= GroupByForm(Rows, Groups);

      { ---- 3. dot ---- }
      var NodeId:= 0;
      var Clusters:= 0;
      var Anchored:= 0;
      var Sb:= TStringBuilder.Create;
      try
        Sb.AppendLine('digraph shownwhere {');
        Sb.AppendLine('  rankdir=LR; bgcolor="transparent"; compound=true;');
        Sb.AppendLine('  nodesep=0.35; ranksep=1.4; splines=spline;');
        Sb.AppendLine(Format('  graph [fontname="%s"];', [FONT_SANS]));
        Sb.AppendLine(Format('  node  [shape=plaintext, fontname="%s", fontsize=14];', [FONT_MONO]));
        Sb.AppendLine(Format('  edge  [fontname="%s", fontsize=11, color="%s", penwidth=1.4, arrowsize=0.7];', [FONT_MONO, LINE_INK]));
        Sb.AppendLine('');

        Inc(NodeId);
        Inc(Clusters);
        var FNid:= 'n' + IntToStr(NodeId);
        var FTbl:= TStringBuilder.Create;
        try
          FTbl.Append('<TABLE BORDER="0" CELLBORDER="0" CELLSPACING="3" CELLPADDING="5">');
          FTbl.Append(Format('<TR><TD ALIGN="LEFT" BGCOLOR="%s"><FONT COLOR="#FFFFFF" FACE="%s" POINT-SIZE="14"><B> %s </B></FONT></TD></TR>',
            [FOCUS_HDR, FONT_SANS, XmlText(Column)]));
          AddDisclosureRow(FTbl, Format('%d data binding(s) on %d form(s)', [Rows.Count, Length(ByForm)]), LINE_INK);
          AddDisclosureRow(FTbl, Format('index-wide: %d binding(s) over %d column(s) in %d form file(s)', [IdxRows, IdxCols, IdxForms]), LINE_INK);
          AddDisclosureRow(FTbl, 'DFM data bindings only -- code-driven display is not indexed and is not shown', LINE_INK);
          if Unresolved > 0 then
            AddDisclosureRow(FTbl, Format('%d binding(s) did not resolve to a control symbol', [Unresolved]), LINE_INK);
          FTbl.Append('</TABLE>');
          Sb.AppendLine(Format('  subgraph cluster_focus_%d {', [NodeId]));
          Sb.AppendLine(Format('    style="rounded,filled"; color="%s"; fillcolor="%s"; penwidth=2;', [FOCUS_BORDER, FOCUS_FILL]));
          Sb.AppendLine('    label=""; margin=10;');
          Sb.AppendLine(Format('    %s [label=<%s>];', [FNid, FTbl.ToString]));
          Sb.AppendLine('  }');
        finally
          FTbl.Free;
        end;

        (* Sort-Object { $_.Count } -Descending: NOT stable -- TPsSort keeps its tie order *)
        var Ranked:= Copy(ByForm);
        TPsSort<TFormGroup>.Sort(Ranked, function(const pL, pR: TFormGroup): Integer
          begin Result:= pR.Rows.Count - pL.Rows.Count; end);
        var Top:= TRanked<TFormGroup>.TopRanked(Ranked, pArgs.Cap, function(pG: TFormGroup): Integer
          begin Result:= pG.Rows.Count; end);
        var FormStyle:= TClusterStyle.Make(FORM_BORDER, FORM_FILL, FORM_HDR);
        FormStyle.RowInk:= ROW_INK;
        FormStyle.LineInk:= LINE_INK;
        FormStyle.FontSans:= FONT_SANS;
        for var G in Top.Shown do
        begin
          var Dfm:= G.Rows[0].S('dfm');
          var Cells: TArray<TDotRow>:= [];
          for var B in G.Rows do
          begin
            Inc(Anchored);
            var Ctl:= if B.S('control') <> '' then B.S('control') else UNRESOLVED_CONTROL;
            var Note:= if B.S('parent') <> '' then 'in ' + B.S('parent') else B.S('prop');
            Cells:= Cells + [TDotRow.Anchored(Ctl, B.I('line'), RowHref(Dfm, B.I('line')),
              Format('%s.%s = ''%s'' -- %s:%d', [Ctl, B.S('prop'), B.S('col'), FileNameOf(Dfm), B.I('line')]), Note)];
          end;
          Inc(NodeId);
          Inc(Clusters);
          var Nid:= 'n' + IntToStr(NodeId);
          AddRowCluster(Sb, 'cluster_form_' + IntToStr(NodeId), Nid, UnitNameOf(Dfm),
            Format('%d control%s', [G.Rows.Count, Plural(G.Rows.Count)]), Cells, FormStyle);
          Sb.AppendLine(Format('  %s -> %s [color="%s"];', [FNid, Nid, FORM_BORDER]));
        end;
        var D:= DisclosureText(Top.HiddenRows, 0, 'forms');
        if D <> '' then
        begin
          Inc(NodeId);
          Inc(Clusters);
          var MoreStyle:= TClusterStyle.Make(LINE_INK, MORE_FILL, MORE_HDR);
          MoreStyle.RowInk:= ROW_INK;
          MoreStyle.LineInk:= LINE_INK;
          MoreStyle.FontSans:= FONT_SANS;
          MoreStyle.Style:= MORE_STYLE;
          AddRowCluster(Sb, 'cluster_more_' + IntToStr(NodeId), 'n' + IntToStr(NodeId), 'not shown', '', [NoteRow(D)], MoreStyle);
        end;
        Sb.AppendLine('}');

        var Msgs: TArray<string>;
        Result.Layout:= DotLayout(pArgs.Dot, Sb.ToString, pOutDir, 'shownwhere_' + TRegEx.Replace(Column, '[^A-Za-z0-9]', '_'), Msgs);
      finally
        Sb.Free;
      end;
      Result.LeftCount:= Rows.Count;
      Result.RightCount:= Length(ByForm);
      Result.ClickTargets:= Result.Layout.Anchors;
      Result.AllClickable:= Result.Layout.Anchors >= Anchored;
      Result.Fields:= [TMetaField.Str('Column', Column), TMetaField.Int('Bindings', Rows.Count),
        TMetaField.Int('Forms', Length(ByForm)), TMetaField.Int('Unresolved', Unresolved),
        TMetaField.Int('IndexRows', IdxRows), TMetaField.Int('IndexColumns', IdxCols),
        TMetaField.Int('Clusters', Clusters), TMetaField.Int('ClickTargets', Result.Layout.Anchors),
        TMetaField.Int('Expected', Anchored), TMetaField.Bool('AllClickable', Result.AllClickable)];
    finally
      Groups.Free;
      Rows.Free;
    end;
  finally
    Index.Free;
  end;
end;

initialization
  RegisterChartQuestion(SHOWN_WHERE_ID, Emit);

end.
