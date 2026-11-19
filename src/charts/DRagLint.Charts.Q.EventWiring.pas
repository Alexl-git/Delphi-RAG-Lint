unit DRagLint.Charts.Q.EventWiring;

(* The `event-wiring` question in-process: a port of charts\src\Emit-EventWiring.ps1
  (spec s11; the PS output is the reference, P3). Which handler runs on which event of a
  FORM CLASS: the rows come from the dfm_event fact (never from a name convention), the
  event assignment line from the DFM's string_literals (the first matching assignment at
  or after the component's dfm-type line), else the handler's declaration, said as
  'pas fallback'. Left: one cluster per event kind; right: the handlers, by name.
  -Control is a FILTER applied after the class scoped the question, never the selector.

  PS traps closed: Group-Object Event groups case-insensitively and sorts its groups by key
  (CompareGroupKeys), then `Sort-Object { $_.Group.Count } -Descending` and
  `Sort-Object Handler` are NOT stable (TPsSort); `Sort-Object -Unique` drops
  case-insensitive duplicates (SortUniqueNames); the hashtables (component line, ports)
  have case-insensitive keys and a later key overwrites; `-eq` is case-insensitive;
  `-split '\.', 2` splits at the first dot only. *)

interface

const
  /// <summary>The registered question id.</summary>
  EVENT_WIRING_ID = 'event-wiring';

implementation

uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.Generics.Defaults,
  System.RegularExpressions, DRagLint.Charts.Question, DRagLint.Charts.Index, DRagLint.Charts.Text,
  DRagLint.Charts.Dot, DRagLint.Charts.Sql, DRagLint.Charts.PsSort;

const
  UI_BORDER = '#7C3AED';
  UI_FILL = '#F3EEFF';
  UI_HDR = '#7C3AED';
  CALLEE_BORDER = '#B45309';
  CALLEE_FILL = '#FEF6EC';
  CALLEE_HDR = '#B45309';
  ROW_INK = '#1F2933';
  LINE_INK = '#8A94A6';
  FONT_MONO = 'Consolas';
  FONT_SANS = 'Segoe UI';
  UNKNOWN_EVENT = '(unknown)';
  PAS_FALLBACK = 'pas fallback';
  CONTROL_ARG = 'Control';

type
  TWiringRow = record
    Comp, Event, Handler, Qname, Pas: string;
    Decl, Impl, DfmLine: Integer;
    DfmExact: Boolean;
    function Key: string;
  end;

  { one Group-Object group: the first row's Event and the rows, in input order }
  TEventGroup = record
    Name: string;
    Rows: TArray<TWiringRow>;
  end;

function TWiringRow.Key: string;
begin
  Result:= Qname + '|' + Comp + '|' + Event;
end;

(* Group-Object Event: case-insensitive groups, sorted by key *)
function GroupByEvent(const pRows: TArray<TWiringRow>): TArray<TEventGroup>;
begin
  Result:= [];
  var Slot:= TDictionary<string, Integer>.Create(TIStringComparer.Ordinal);
  try
    for var R in pRows do
    begin
      var K: Integer;
      if not Slot.TryGetValue(R.Event, K) then
      begin
        var G:= Default(TEventGroup);
        G.Name:= R.Event;
        Result:= Result + [G];
        K:= High(Result);
        Slot.Add(R.Event, K);
      end;
      Result[K].Rows:= Result[K].Rows + [R];
    end;
  finally
    Slot.Free;
  end;
  { keys are unique case-insensitively, so the order is total and no tie can move }
  TArray.Sort<TEventGroup>(Result, TComparer<TEventGroup>.Construct(
    function(const pL, pR: TEventGroup): Integer begin Result:= CompareGroupKeys(pL.Name, pR.Name); end));
end;

function UniqueCount(const pValues: TArray<string>): Integer;
begin
  Result:= Length(SortUniqueNames(pValues));
end;

function Emit(const pArgs: TQuestionArgs; const pOutDir: string): TChartResult;
var
  Rows: TArray<TWiringRow>;
begin
  var Form:= pArgs.Target;
  var Control:= pArgs.Command.Get(CONTROL_ARG);
  var Index:= TChartsIndex.Create(pArgs.GuardedDb);
  var CompAt:= TDictionary<string, Integer>.Create(TIStringComparer.Ordinal);
  var LeftPort:= TDictionary<string, string>.Create(TIStringComparer.Ordinal);
  var RightPort:= TDictionary<string, string>.Create(TIStringComparer.Ordinal);
  try
    { ---- Q1: the handler facts ---- }
    Rows:= [];
    var Q:= Index.Query(
      'SELECT sf.dfm_event AS ev, s.name AS handler, s.qualified_name AS qname,' + sLineBreak +
      '       s.start_line AS decl_line, s.impl_start_line AS impl_line, f.path AS pas' + sLineBreak +
      '  FROM symbol_facts sf JOIN symbols s ON s.id = sf.symbol_id' + sLineBreak +
      '  JOIN symbols c ON c.id = s.parent_id' + sLineBreak +
      '  JOIN files f ON f.id = s.file_id' + sLineBreak +
      ' WHERE c.qualified_name = ''' + TChartsIndex.SqlText(Form) + ''' AND sf.dfm_event IS NOT NULL' + sLineBreak +
      ' ORDER BY sf.dfm_event');
    try
      if Q.Count = 0 then
      begin
        var All:= Index.Query('SELECT COUNT(*) AS n FROM symbol_facts WHERE dfm_event IS NOT NULL');
        try
          var N:= if All.Count > 0 then All[0].S('n') else '0';
          raise EChartsQuestion.CreateFmt('no dfm_event facts under %s (index has %s across all forms) -- is this a form class?', [Form, N]);
        finally
          All.Free;
        end;
      end;
      for var H in Q do
      begin
        var R:= Default(TWiringRow);
        var Ev:= H.S('ev');
        var Dot:= Pos('.', Ev);
        if Dot > 0 then
        begin
          R.Comp:= Copy(Ev, 1, Dot - 1);
          R.Event:= Copy(Ev, Dot + 1, MaxInt);
        end
        else
        begin
          R.Comp:= Ev;
          R.Event:= UNKNOWN_EVENT;
        end;
        R.Handler:= H.S('handler');
        R.Qname:= H.S('qname');
        R.Decl:= H.I('decl_line');
        R.Impl:= if H.I('impl_line') <> 0 then H.I('impl_line') else R.Decl;
        R.Pas:= H.S('pas');
        Rows:= Rows + [R];
      end;
    finally
      Q.Free;
    end;
    var FormEventCount:= Length(Rows);

    if Control <> '' then
    begin
      var Kept: TArray<TWiringRow>:= [];
      for var R in Rows do
        if SameText(R.Comp, Control) then
          Kept:= Kept + [R];
      Rows:= Kept;
      if Length(Rows) = 0 then
        raise EChartsQuestion.CreateFmt('control %s has no dfm_event rows on %s (the form has %d)', [Control, Form, FormEventCount]);
    end;

    var Pas:= Rows[0].Pas;
    var Dfm:= ChangeFileExt(Pas, '.dfm');
    var UnitName:= UnitNameOf(Pas);

    { ---- Q2/Q3: where the DFM says it (both IN-lists are mandatory) ---- }
    var CompNames: TArray<string>:= [];
    var HandlerNames: TArray<string>:= [];
    var Qnames: TArray<string>:= [];
    var EventNames: TArray<string>:= [];
    for var R in Rows do
    begin
      CompNames:= CompNames + [R.Comp];
      HandlerNames:= HandlerNames + [R.Handler];
      Qnames:= Qnames + [R.Qname];
      EventNames:= EventNames + [R.Event];
    end;
    var Comps:= SortUniqueNames(CompNames);
    var DfmText:= TChartsIndex.SqlText(Dfm);
    Q:= Index.Query(
      'SELECT sl.owner_name AS comp, sl.start_line AS line' + sLineBreak +
      '  FROM string_literals sl JOIN files f ON f.id = sl.file_id' + sLineBreak +
      ' WHERE f.path = ''' + DfmText + ''' AND sl.kind = ''dfm-type''' + sLineBreak +
      '   AND sl.owner_name IN (' + TChartsIndex.SqlInList(Comps) + ')' + sLineBreak +
      ' ORDER BY sl.start_line');
    try
      for var C in Q do
      begin
        var Was: Integer;
        if not CompAt.TryGetValue(C.S('comp'), Was) or (C.I('line') < Was) then
          CompAt.AddOrSetValue(C.S('comp'), C.I('line'));
      end;
    finally
      Q.Free;
    end;
    var EvLines:= Index.Query(
      'SELECT sl.owner_name AS ev, sl.start_line AS line, sl.text AS handler' + sLineBreak +
      '  FROM string_literals sl JOIN files f ON f.id = sl.file_id' + sLineBreak +
      ' WHERE f.path = ''' + DfmText + ''' AND sl.kind = ''dfm-prop'' AND sl.owner_name LIKE ''On%''' + sLineBreak +
      '   AND sl.text IN (' + TChartsIndex.SqlInList(SortUniqueNames(HandlerNames)) + ')' + sLineBreak +
      ' ORDER BY sl.start_line');
    var Resolved:= 0;
    var Fallback:= 0;
    try
      for var K:= 0 to High(Rows) do
      begin
        var At: Integer;
        if not CompAt.TryGetValue(Rows[K].Comp, At) then
          At:= -1;
        var HitLine:= -1;
        if At >= 0 then
          for var E in EvLines do
            if SameText(E.S('ev'), Rows[K].Event) and SameText(E.S('handler'), Rows[K].Handler) and (E.I('line') >= At) then
            begin
              HitLine:= E.I('line');
              Break;
            end;
        Rows[K].DfmExact:= HitLine >= 0;
        if Rows[K].DfmExact then
        begin
          Rows[K].DfmLine:= HitLine;
          Inc(Resolved);
        end
        else
        begin
          Rows[K].DfmLine:= Rows[K].Decl;
          Inc(Fallback);
        end;
      end;
    finally
      EvLines.Free;
    end;

    { ---- dot ---- }
    var DfmName:= FileNameOf(Dfm);
    var PasName:= FileNameOf(Pas);
    var Clusters:= 0;
    var Edges:= 0;
    var Sb:= TStringBuilder.Create;
    try
      Sb.AppendLine('digraph eventwiring {');
      Sb.AppendLine('  rankdir=LR; bgcolor="transparent"; compound=true;');
      Sb.AppendLine('  nodesep=0.3; ranksep=1.4; splines=spline;');
      Sb.AppendLine(Format('  graph [fontname="%s"];', [FONT_SANS]));
      Sb.AppendLine(Format('  node  [shape=plaintext, fontname="%s", fontsize=14];', [FONT_MONO]));
      Sb.AppendLine(Format('  edge  [fontname="%s", fontsize=11, color="%s", penwidth=1.4, arrowsize=0.7];', [FONT_MONO, LINE_INK]));
      Sb.AppendLine('');

      var NodeId:= 0;
      { LEFT: one cluster per EVENT KIND, rows are COMPONENTS, href into the DFM }
      var ByKind:= GroupByEvent(Rows);
      TPsSort<TEventGroup>.Sort(ByKind, function(const pL, pR: TEventGroup): Integer
        begin Result:= Length(pR.Rows) - Length(pL.Rows); end);
      var UiStyle:= TClusterStyle.Make(UI_BORDER, UI_FILL, UI_HDR);
      UiStyle.RowInk:= ROW_INK;
      UiStyle.LineInk:= LINE_INK;
      UiStyle.FontSans:= FONT_SANS;
      for var G in ByKind do
      begin
        Inc(NodeId);
        Inc(Clusters);
        var Cells: TArray<TDotRow>:= [];
        for var R in G.Rows do
        begin
          var Assign:= Format('%s.%s = %s', [R.Comp, R.Event, R.Handler]);
          if R.DfmExact then
            Cells:= Cells + [TDotRow.Anchored(R.Comp, R.DfmLine, RowHref(Dfm, R.DfmLine),
              Format('%s  --  %s:%d', [Assign, DfmName, R.DfmLine]))]
          else
            Cells:= Cells + [TDotRow.Anchored(R.Comp, R.DfmLine, RowHref(Pas, R.DfmLine),
              Format('%s  --  no matching assignment found in %s; pointing at the handler declaration in %s:%d',
                [Assign, DfmName, PasName, R.DfmLine]), PAS_FALLBACK)];
        end;
        var N:= Length(G.Rows);
        var Ports:= AddRowCluster(Sb, 'cluster_ev_' + IntToStr(NodeId), 'n' + IntToStr(NodeId), G.Name,
          Format('%d control%s', [N, if N <> 1 then 's' else '']), Cells, UiStyle);
        for var K:= 0 to N - 1 do
          LeftPort.AddOrSetValue(G.Rows[K].Key, Ports[K]);
      end;

      { RIGHT: one cluster, the form UNIT, rows are HANDLER METHODS, href into the .pas }
      Inc(NodeId);
      Inc(Clusters);
      var HandlerRows:= Copy(Rows);
      TPsSort<TWiringRow>.Sort(HandlerRows, function(const pL, pR: TWiringRow): Integer
        begin Result:= CompareGroupKeys(pL.Handler, pR.Handler); end);
      var Cells: TArray<TDotRow>:= [];
      for var R in HandlerRows do
        Cells:= Cells + [TDotRow.Anchored(R.Handler, R.Impl, RowHref(Pas, R.Impl), Format('%s  --  %s:%d', [R.Qname, PasName, R.Impl]))];
      var FormParts:= Form.Split(['.']);
      var HandlerStyle:= TClusterStyle.Make(CALLEE_BORDER, CALLEE_FILL, CALLEE_HDR);
      HandlerStyle.RowInk:= ROW_INK;
      HandlerStyle.LineInk:= LINE_INK;
      HandlerStyle.FontSans:= FONT_SANS;
      var RPorts:= AddRowCluster(Sb, 'cluster_handlers_' + IntToStr(NodeId), 'n' + IntToStr(NodeId), UnitName,
        FormParts[High(FormParts)], Cells, HandlerStyle);
      for var K:= 0 to High(HandlerRows) do
        RightPort.AddOrSetValue(HandlerRows[K].Key, RPorts[K]);

      Sb.AppendLine('');
      for var R in Rows do
      begin
        var L, Rp: string;
        if LeftPort.TryGetValue(R.Key, L) and RightPort.TryGetValue(R.Key, Rp) then
        begin
          Sb.AppendLine(Format('  %s -> %s [color="%s"];', [L, Rp, UI_BORDER]));
          Inc(Edges);
        end;
      end;
      Sb.AppendLine('}');

      { ---- lay out ---- }
      var Msgs: TArray<string>;
      var Base:= Form + (if Control <> '' then '.' + Control else '');
      Result.Layout:= DotLayout(pArgs.Dot, Sb.ToString, pOutDir, TRegEx.Replace(Base, '[^A-Za-z0-9]', '_'), Msgs);
    finally
      Sb.Free;
    end;
    var Expected:= Length(Rows) * 2;
    var Handlers:= UniqueCount(Qnames);
    Result.LeftCount:= Length(Rows);
    Result.RightCount:= Handlers;
    Result.ClickTargets:= Result.Layout.Anchors;
    Result.AllClickable:= Result.Layout.Anchors >= Expected;
    Result.Fields:= [TMetaField.Int('Events', Length(Rows)), TMetaField.Int('Handlers', Handlers),
      TMetaField.Int('Components', Length(Comps)), TMetaField.Int('EventKinds', UniqueCount(EventNames)),
      TMetaField.Int('DfmResolved', Resolved), TMetaField.Int('DfmFallback', Fallback),
      TMetaField.Int('Edges', Edges), TMetaField.Int('Clusters', Clusters),
      TMetaField.Int('ClickTargets', Result.Layout.Anchors), TMetaField.Int('Expected', Expected),
      TMetaField.Bool('AllClickable', Result.AllClickable)];
  finally
    RightPort.Free;
    LeftPort.Free;
    CompAt.Free;
    Index.Free;
  end;
end;

initialization
  RegisterChartQuestion(EVENT_WIRING_ID, Emit);

end.
