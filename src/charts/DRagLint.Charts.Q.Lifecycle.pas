unit DRagLint.Charts.Q.Lifecycle;

(* The `lifecycle` question in-process: a port of charts\src\Emit-Lifecycle.ps1 (spec
  s11; the PS output is the reference, P3). Which of a form's lifecycle stages are wired
  (a dfm_event fact), implemented but wired by nothing (a Form<Stage> method -- a NAME-
  CONVENTION inference, labelled as one), or absent, drawn top to bottom in Delphi's real
  create -> destroy order with OnDeactivate as a dashed aside. "Is a form" is a HERITAGE
  check over type_ancestors (by name: every form root is RTL / DevExpress), not a row
  count: a form that wires nothing still renders.

  PS traps closed: the stage hashtables have case-insensitive keys (a stage wired twice
  keeps the first; an unwired name seen twice keeps the last); `-contains` against the
  form roots is case-insensitive; `[int]$null` ends the heritage walk. *)

interface

const
  /// <summary>The registered question id.</summary>
  LIFECYCLE_ID = 'lifecycle';

implementation

uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.Generics.Defaults, System.RegularExpressions,
  DRagLint.Charts.Question, DRagLint.Charts.Index, DRagLint.Charts.Text, DRagLint.Charts.Dot;

const
  WIRED_BORDER = '#0F766E';
  WIRED_FILL = '#E2F1EF';
  WIRED_HDR = '#0F766E';
  UNWIRED_BORDER = '#B45309';
  UNWIRED_FILL = '#FEF6EC';
  UNWIRED_HDR = '#B45309';
  ABSENT_BORDER = '#9AA3AF';
  ABSENT_FILL = '#F3F4F6';
  ABSENT_HDR = '#6B7280';
  FOCUS_BORDER = '#3B5BDB';
  FOCUS_FILL = '#EDF2FF';
  FOCUS_HDR = '#3B5BDB';
  ROW_INK = '#1F2933';
  LINE_INK = '#8A94A6';
  FONT_MONO = 'Consolas';
  FONT_SANS = 'Segoe UI';
  SOLID_STYLE = 'rounded,filled';
  DASHED_STYLE = 'rounded,filled,dashed';
  STATE_WIRED = 'wired';
  STATE_UNWIRED = 'unwired';
  STATE_ABSENT = 'absent';
  { the heritage walk is bounded so a cyclic heritage cannot hang }
  MAX_HOPS = 12;
  HINT = 'lifecycle selects a FORM CLASS -- ask class-surface for a plain class';
  { the create -> destroy spine, in Delphi's order; OnDeactivate is NOT in it }
  SPINE: array[0..5] of string = ('OnCreate', 'OnShow', 'OnActivate', 'OnCloseQuery', 'OnClose', 'OnDestroy');
  ASIDE: array[0..0] of string = ('OnDeactivate');
  { the conventional method name of each stage: the inference, isolated in one place }
  CONVENTION: array[0..6] of array[0..1] of string = (
    ('OnCreate', 'FormCreate'), ('OnShow', 'FormShow'), ('OnActivate', 'FormActivate'),
    ('OnDeactivate', 'FormDeactivate'), ('OnCloseQuery', 'FormCloseQuery'),
    ('OnClose', 'FormClose'), ('OnDestroy', 'FormDestroy'));
  FORM_ROOTS: array[0..5] of string = ('TForm', 'TCustomForm', 'TdxRibbonForm', 'TDataModule', 'TFrame', 'TCustomFrame');

type
  TStageHandler = record
    Owner, Handler, Qname, Pas: string;
    Impl: Integer;
  end;

  TStageState = record
    Stage, State, Handler, Qname, Pas, Owner: string;
    Line: Integer;
  end;

function ConventionStage(const pMethod: string): string;
begin
  for var K:= Low(CONVENTION) to High(CONVENTION) do
    if SameText(CONVENTION[K, 1], pMethod) then
      Exit(CONVENTION[K, 0]);
  Result:= '';
end;

function IsFormRoot(const pName: string): Boolean;
begin
  for var R in FORM_ROOTS do
    if SameText(R, pName) then
      Exit(True);
  Result:= False;
end;

function Quoted(const pValues: array of string): string;
begin
  var Parts: TArray<string>:= [];
  for var V in pValues do
    Parts:= Parts + [V];
  Result:= TChartsIndex.SqlInList(Parts);
end;

{ ordinal 0 upward until an unresolved ancestor }
function Heritage(pIndex: TChartsIndex; pId: Integer): TArray<string>;
begin
  Result:= [];
  var Cur:= pId;
  var Hop:= 0;
  while (Hop < MAX_HOPS) and (Cur <> 0) do
  begin
    var A:= pIndex.Query(Format('SELECT ancestor_name AS nm, ancestor_symbol_id AS sid FROM type_ancestors WHERE symbol_id = %d AND ordinal = 0', [Cur]));
    try
      if A.Count = 0 then
        Break;
      Result:= Result + [A[0].S('nm')];
      Cur:= A[0].I('sid');
    finally
      A.Free;
    end;
    Inc(Hop);
  end;
end;

function Emit(const pArgs: TQuestionArgs; const pOutDir: string): TChartResult;
var
  Found: Boolean;
  Oddities: TArray<string>;
begin
  var Index:= TChartsIndex.Create(pArgs.GuardedDb);
  var Wired:= TDictionary<string, TStageHandler>.Create(TIStringComparer.Ordinal);
  var Unwired:= TDictionary<string, TStageHandler>.Create(TIStringComparer.Ordinal);
  var Sb:= TStringBuilder.Create;
  try
    { ---- 1. resolve the selection ---- }
    var Sel:= Index.ResolveMemberSelection(pArgs.Target, ['class'], False, HINT, Found);

    { ---- 2. heritage check (N14) ---- }
    var Chain:= Heritage(Index, Sel.Id);
    var IsForm:= False;
    for var Nm in Chain do
      IsForm:= IsForm or IsFormRoot(Nm);
    if not IsForm then
    begin
      var Seen:= if Length(Chain) > 0 then string.Join(' -> ', Chain) else '(no ancestors recorded)';
      raise EChartsQuestion.CreateFmt('%s is not a form: its heritage is %s, and none of %s appears in it. Note this is a HERITAGE check -- ' +
        'a real form that wires nothing is a different answer and still renders.', [Sel.QName, Seen, string.Join('/', FORM_ROOTS)]);
    end;

    { ---- 3. what the DFM wires ---- }
    var QText:= TChartsIndex.SqlText(Sel.QName);
    var FirstPas:= '';
    var Rows:= Index.Query(
      'SELECT sf.dfm_event AS ev, s.id AS sid, s.name AS handler, s.qualified_name AS qname,' + sLineBreak +
      '       s.start_line AS decl_line, s.impl_start_line AS impl_line, f.path AS pas' + sLineBreak +
      '  FROM symbol_facts sf' + sLineBreak +
      '  JOIN symbols s ON s.id = sf.symbol_id' + sLineBreak +
      '  JOIN symbols c ON c.id = s.parent_id' + sLineBreak +
      '  JOIN files f ON f.id = s.file_id' + sLineBreak +
      ' WHERE c.qualified_name = ''' + QText + '''' + sLineBreak +
      '   AND sf.dfm_event IS NOT NULL' + sLineBreak +
      '   AND substr(sf.dfm_event, instr(sf.dfm_event, ''.'') + 1) IN (' + Quoted(SPINE) + ',' + Quoted(ASIDE) + ')' + sLineBreak +
      ' ORDER BY sf.dfm_event');
    try
      if Rows.Count > 0 then
        FirstPas:= Rows[0].S('pas');
      for var W in Rows do
      begin
        var Ev:= W.S('ev');
        var DotAt:= Pos('.', Ev);
        var Stage:= if DotAt > 0 then Copy(Ev, DotAt + 1, MaxInt) else Ev;
        if Wired.ContainsKey(Stage) then
          Continue;
        var H:= Default(TStageHandler);
        H.Owner:= if DotAt > 0 then Copy(Ev, 1, DotAt - 1) else '';
        H.Handler:= W.S('handler');
        H.Qname:= W.S('qname');
        H.Impl:= if W.I('impl_line') <> 0 then W.I('impl_line') else W.I('decl_line');
        H.Pas:= W.S('pas');
        Wired.Add(Stage, H);
      end;
    finally
      Rows.Free;
    end;

    { ---- 4. what is implemented but wired by nothing ---- }
    var ConvNames: TArray<string>:= [];
    for var K:= Low(CONVENTION) to High(CONVENTION) do
      ConvNames:= ConvNames + [CONVENTION[K, 1]];
    Rows:= Index.Query(
      'SELECT s.id AS sid, s.name AS m, s.qualified_name AS qname,' + sLineBreak +
      '       s.start_line AS decl_line, s.impl_start_line AS impl_line, f.path AS pas' + sLineBreak +
      '  FROM symbols s' + sLineBreak +
      '  JOIN symbols c ON c.id = s.parent_id' + sLineBreak +
      '  JOIN files f ON f.id = s.file_id' + sLineBreak +
      '  LEFT JOIN symbol_facts sf ON sf.symbol_id = s.id AND sf.dfm_event IS NOT NULL' + sLineBreak +
      ' WHERE c.qualified_name = ''' + QText + '''' + sLineBreak +
      '   AND s.name IN (' + TChartsIndex.SqlInList(ConvNames) + ')' + sLineBreak +
      '   AND sf.symbol_id IS NULL' + sLineBreak +
      ' ORDER BY s.name');
    try
      if (FirstPas = '') and (Rows.Count > 0) then
        FirstPas:= Rows[0].S('pas');
      for var M in Rows do
      begin
        var Stage:= ConventionStage(M.S('m'));
        if Stage = '' then
          Continue;
        var H:= Default(TStageHandler);
        H.Handler:= M.S('m');
        H.Qname:= M.S('qname');
        H.Impl:= if M.I('impl_line') <> 0 then M.I('impl_line') else M.I('decl_line');
        H.Pas:= M.S('pas');
        Unwired.AddOrSetValue(Stage, H);
      end;
    finally
      Rows.Free;
    end;

    { ---- 5. resolve each stage to exactly one of three states ---- }
    Oddities:= [];
    var StateOf:= function(const pStage: string): TStageState
      var
        H, U: TStageHandler;
      begin
        Result:= Default(TStageState);
        Result.Stage:= pStage;
        if Wired.TryGetValue(pStage, H) then
        begin
          if Unwired.TryGetValue(pStage, U) then
            Oddities:= Oddities + [Format('%s is wired to %s, but %s also exists and is wired to nothing', [pStage, H.Handler, U.Handler])];
          Result.State:= STATE_WIRED;
          Result.Handler:= H.Handler;
          Result.Qname:= H.Qname;
          Result.Line:= H.Impl;
          Result.Pas:= H.Pas;
          Result.Owner:= H.Owner;
        end
        else if Unwired.TryGetValue(pStage, U) then
        begin
          Result.State:= STATE_UNWIRED;
          Result.Handler:= U.Handler;
          Result.Qname:= U.Qname;
          Result.Line:= U.Impl;
          Result.Pas:= U.Pas;
        end
        else
          Result.State:= STATE_ABSENT;
      end;
    var SpineStates: TArray<TStageState>:= [];
    for var S in SPINE do
      SpineStates:= SpineStates + [StateOf(S)];
    var AsideStates: TArray<TStageState>:= [];
    for var S in ASIDE do
      AsideStates:= AsideStates + [StateOf(S)];
    var NWired:= 0;
    var NUnwired:= 0;
    var NAbsent:= 0;
    for var St in SpineStates + AsideStates do
      if St.State = STATE_WIRED then Inc(NWired)
      else if St.State = STATE_UNWIRED then Inc(NUnwired)
      else Inc(NAbsent);
    var UnitName:= UnitNameOf(if FirstPas <> '' then FirstPas else Sel.Path);

    { ---- 6. dot ---- }
    Sb.AppendLine('digraph lifecycle {');
    Sb.AppendLine('  rankdir=TB; bgcolor="transparent"; compound=true;');
    Sb.AppendLine('  nodesep=0.35; ranksep=0.45; splines=spline;');
    Sb.AppendLine(Format('  graph [fontname="%s"];', [FONT_SANS]));
    Sb.AppendLine(Format('  node  [shape=plaintext, fontname="%s", fontsize=14];', [FONT_MONO]));
    Sb.AppendLine(Format('  edge  [fontname="%s", fontsize=11, color="%s", penwidth=1.4, arrowsize=0.7];', [FONT_MONO, LINE_INK]));
    Sb.AppendLine('');

    var NodeId:= 0;
    var Clusters:= 0;
    var AnchoredRows:= 0;
    var AddStageCluster:= function(const pSt: TStageState): string
      var
        Style: TClusterStyle;
        Cells: TArray<TDotRow>;
      begin
        Inc(NodeId);
        Inc(Clusters);
        if pSt.State = STATE_WIRED then
        begin
          Style:= TClusterStyle.Make(WIRED_BORDER, WIRED_FILL, WIRED_HDR);
          Style.Style:= SOLID_STYLE;
          Cells:= [TDotRow.Anchored(pSt.Handler, pSt.Line, RowHref(pSt.Pas, pSt.Line),
            Format('%s  --  wired in the DFM as %s.%s; body at %s:%d', [pSt.Qname, pSt.Owner, pSt.Stage, FileNameOf(pSt.Pas), pSt.Line]),
            if pSt.Owner <> '' then 'wired by ' + pSt.Owner else 'wired')];
          Inc(AnchoredRows);
        end
        else if pSt.State = STATE_UNWIRED then
        begin
          Style:= TClusterStyle.Make(UNWIRED_BORDER, UNWIRED_FILL, UNWIRED_HDR);
          Style.Style:= DASHED_STYLE;
          Cells:= [TDotRow.Anchored(pSt.Handler, pSt.Line, RowHref(pSt.Pas, pSt.Line),
            Format('%s  --  IMPLEMENTED at %s:%d but NOTHING in the DFM wires it. Matched by name convention, not by an index fact.',
              [pSt.Qname, FileNameOf(pSt.Pas), pSt.Line]), 'implemented, NOT wired'),
            NoteRow('matched by name convention, not a fact')];
          Inc(AnchoredRows);
        end
        else
        begin
          Style:= TClusterStyle.Make(ABSENT_BORDER, ABSENT_FILL, ABSENT_HDR);
          Style.Style:= DASHED_STYLE;
          Cells:= [NoteRow('(not implemented)')];
        end;
        Style.RowInk:= ROW_INK;
        Style.LineInk:= LINE_INK;
        Style.FontSans:= FONT_SANS;
        var Ports:= AddRowCluster(Sb, 'cluster_stage_' + IntToStr(NodeId), 'n' + IntToStr(NodeId), pSt.Stage, pSt.State, Cells, Style);
        Result:= Ports[0];
      end;

    var SpinePorts: TArray<string>:= [];
    for var St in SpineStates do
      SpinePorts:= SpinePorts + [AddStageCluster(St)];
    Sb.AppendLine('');
    for var K:= 0 to High(SpinePorts) - 1 do
      Sb.AppendLine(Format('  %s -> %s [color="%s", penwidth=1.6];', [SpinePorts[K], SpinePorts[K + 1], WIRED_BORDER]));
    for var St in AsideStates do
      Sb.AppendLine(Format('  %s -> %s [style=invis];', [SpinePorts[0], AddStageCluster(St)]));

    { focus box: what was selected, and the caveats that apply to the whole picture }
    Inc(NodeId);
    Inc(Clusters);
    var FNid:= 'n' + IntToStr(NodeId);
    var FTbl:= TStringBuilder.Create;
    try
      FTbl.Append('<TABLE BORDER="0" CELLBORDER="0" CELLSPACING="3" CELLPADDING="5">');
      FTbl.Append(Format('<TR><TD ALIGN="LEFT" BGCOLOR="%s"><FONT COLOR="#FFFFFF" FACE="%s" POINT-SIZE="14"><B> %s </B></FONT></TD></TR>',
        [FOCUS_HDR, FONT_SANS, XmlText(Sel.QName)]));
      AddDisclosureRow(FTbl, Format('%s  &#183;  %s', [UnitName, string.Join(' -> ', Chain)]), LINE_INK);
      AddDisclosureRow(FTbl, Format('wired %d  &#183;  implemented but not wired %d  &#183;  absent %d', [NWired, NUnwired, NAbsent]), LINE_INK);
      AddDisclosureRow(FTbl, 'OnDeactivate is drawn apart: it is focus loss, not a pre-close stage', LINE_INK);
      if NUnwired > 0 then
        AddDisclosureRow(FTbl, 'dashed amber = a Form<Stage> method exists that no DFM wires (name convention)', LINE_INK);
      for var O in Oddities do
        AddDisclosureRow(FTbl, O, LINE_INK);
      FTbl.Append('</TABLE>');
      Sb.AppendLine(Format('  subgraph cluster_focus_%d {', [NodeId]));
      Sb.AppendLine(Format('    style="rounded,filled"; color="%s"; fillcolor="%s"; penwidth=2;', [FOCUS_BORDER, FOCUS_FILL]));
      Sb.AppendLine('    label=""; margin=10;');
      Sb.AppendLine(Format('    %s [label=<%s>];', [FNid, FTbl.ToString]));
      Sb.AppendLine('  }');
    finally
      FTbl.Free;
    end;
    Sb.AppendLine(Format('  %s -> %s [style=invis];', [FNid, SpinePorts[0]]));
    Sb.AppendLine('}');

    { ---- 7. lay out ---- }
    var Msgs: TArray<string>;
    Result.Layout:= DotLayout(pArgs.Dot, Sb.ToString, pOutDir, 'lifecycle_' + TRegEx.Replace(Sel.QName, '[^A-Za-z0-9]', '_'), Msgs);
    Result.LeftCount:= NWired;
    Result.RightCount:= NUnwired;
    Result.ClickTargets:= Result.Layout.Anchors;
    Result.AllClickable:= Result.Layout.Anchors >= AnchoredRows;
    Result.Fields:= [TMetaField.Str('Form', Sel.QName), TMetaField.Str('Heritage', string.Join(' -> ', Chain)),
      TMetaField.Int('Wired', NWired), TMetaField.Int('NotWired', NUnwired), TMetaField.Int('Absent', NAbsent),
      TMetaField.Int('Stages', Length(SPINE) + Length(ASIDE)), TMetaField.Int('Oddities', Length(Oddities)),
      TMetaField.Int('Clusters', Clusters), TMetaField.Int('ClickTargets', Result.Layout.Anchors),
      TMetaField.Int('Expected', AnchoredRows), TMetaField.Bool('AllClickable', Result.AllClickable)];
  finally
    Sb.Free;
    Unwired.Free;
    Wired.Free;
    Index.Free;
  end;
end;

initialization
  RegisterChartQuestion(LIFECYCLE_ID, Emit);

end.
