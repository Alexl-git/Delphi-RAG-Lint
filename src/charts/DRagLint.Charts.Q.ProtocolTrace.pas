unit DRagLint.Charts.Q.ProtocolTrace;

(* The `protocol-trace` question in-process: a port of charts\src\Emit-ProtocolTrace.ps1
  (spec s11; the PS output is the reference, P3). Where a protocol command travels: the
  refs of a command CONSTANT (enum_value) or a wire FIELD, or every enum-value read inside
  a METHOD, read by SQL with the site line and the enclosing routine, zoned by FILE PATH
  (a shared unit sits in both project indexes, so the database never classifies a row)
  and collapsed to one row per routine, ranked by sites. The with-block risk (R7) is a
  flat disclosure: this index cannot single the affected rows out.

  PS traps closed: Group-Object (per routine, per constant) groups case-insensitively and
  sorts its groups by key (CompareGroupKeys), naming each group after its first row;
  `Sort-Object -Unique` drops case-insensitive duplicates (SortUniqueNames); the zone
  `Sort-Object { count } -Descending` is NOT stable (TPsSort). Its input is a hashtable's
  key order, which .NET randomises per process for string keys, so the PS order of two
  zones with EQUAL counts is not reproducible by anyone; first-seen order is used.
  `-notmatch '(?i)client|server'` is a case-insensitive regex. *)

interface

const
  /// <summary>The registered question id.</summary>
  PROTOCOL_TRACE_ID = 'protocol-trace';

implementation

uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.Generics.Defaults,
  System.RegularExpressions, DRagLint.Charts.Question, DRagLint.Charts.Index, DRagLint.Charts.Text,
  DRagLint.Charts.Dot, DRagLint.Charts.Sql, DRagLint.Charts.PsSort;

const
  CMD_BORDER = '#7C3AED';
  ZONE_BORDER = '#3B5BDB';
  ZONE_FILL = '#EDF2FF';
  ZONE_HDR = '#3B5BDB';
  COMMON_BORDER = '#0F766E';
  COMMON_FILL = '#E2F1EF';
  COMMON_HDR = '#0F766E';
  FOCUS_BORDER = '#B45309';
  FOCUS_FILL = '#FEF6EC';
  FOCUS_HDR = '#B45309';
  ROW_INK = '#1F2933';
  LINE_INK = '#8A94A6';
  FONT_MONO = 'Consolas';
  FONT_SANS = 'Segoe UI';
  MODE_COMMAND = 'command';
  MODE_FIELD = 'field';
  MODE_METHOD = 'method';
  UNIT_LEVEL = '(unit level) ';
  { Format-CommandNote names up to this many constants, then counts them }
  NAMED_CONSTANTS = 3;
  HINT = 'protocol-trace selects a command constant, a wire field, or a method';

type
  { one Group-Object group over index rows: its name (the first row's key) and its rows }
  TRowGroup = record
    Name: string;
    Rows: TArray<TIndexRow>;
  end;

  TRoutineRow = record
    Name, Path: string;
    Sites, Line: Integer;
    HasRoutine: Boolean;
    Cmds: TArray<TRowGroup>;
  end;

(* Group-Object { key }: case-insensitive groups, in first-seen order unless pSorted *)
function GroupRows(const pRows: TArray<TIndexRow>; const pKey: TFunc<TIndexRow, string>; pSorted: Boolean): TArray<TRowGroup>;
begin
  Result:= [];
  var Slot:= TDictionary<string, Integer>.Create(TIStringComparer.Ordinal);
  try
    for var R in pRows do
    begin
      var Key:= pKey(R);
      var K: Integer;
      if not Slot.TryGetValue(Key, K) then
      begin
        var G:= Default(TRowGroup);
        G.Name:= Key;
        Result:= Result + [G];
        K:= High(Result);
        Slot.Add(Key, K);
      end;
      Result[K].Rows:= Result[K].Rows + [R];
    end;
  finally
    Slot.Free;
  end;
  { keys are unique case-insensitively, so the order is total and no tie can move }
  if pSorted then
    TArray.Sort<TRowGroup>(Result, TComparer<TRowGroup>.Construct(
      function(const pL, pR: TRowGroup): Integer begin Result:= CompareGroupKeys(pL.Name, pR.Name); end));
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

{ Format-CommandNote: up to three constants NAMED, more COUNTED }
function CommandNote(const pCounts: TArray<TRowGroup>; pSites: Integer): string;
begin
  if Length(pCounts) = 0 then
    Exit('');
  if Length(pCounts) > NAMED_CONSTANTS then
    Exit(Format('%d constants', [Length(pCounts)]) + (if pSites > Length(pCounts) then Format(', %d reads', [pSites]) else ''));
  var Parts: TArray<string>:= [];
  for var G in pCounts do
    Parts:= Parts + [G.Name + (if Length(G.Rows) > 1 then Format(' x%d', [Length(G.Rows)]) else '')];
  Result:= string.Join(', ', Parts);
end;

function LastSegment(const pQName: string): string;
begin
  var Parts:= pQName.Split(['.']);
  Result:= if Length(Parts) = 0 then '' else Parts[High(Parts)];
end;

{ one row per routine, carrying its site count and the constants it reads }
function ByRoutine(const pZoneRows: TArray<TIndexRow>): TArray<TRoutineRow>;
begin
  Result:= [];
  var Groups:= GroupRows(pZoneRows, function(pR: TIndexRow): string
    begin
      Result:= if pR.S('routine') <> '' then pR.S('routine') else UNIT_LEVEL + UnitNameOf(pR.S('path'));
    end, True);
  for var G in Groups do
  begin
    var B:= Default(TRoutineRow);
    B.Name:= G.Name;
    B.Sites:= Length(G.Rows);
    B.HasRoutine:= G.Rows[0].S('routine') <> '';
    B.Path:= G.Rows[0].S('path');
    B.Line:= G.Rows[0].I('line');
    var WithTarget: TArray<TIndexRow>:= [];
    for var R in G.Rows do
      if R.S('target_q') <> '' then
        WithTarget:= WithTarget + [R];
    B.Cmds:= GroupRows(WithTarget, function(pR: TIndexRow): string begin Result:= LastSegment(pR.S('target_q')); end, True);
    Result:= Result + [B];
  end;
  TPsSort<TRoutineRow>.Sort(Result, function(const pL, pR: TRoutineRow): Integer
    begin
      Result:= pR.Sites - pL.Sites;
      if Result = 0 then
        Result:= CompareGroupKeys(pL.Name, pR.Name);
    end);
end;

function Emit(const pArgs: TQuestionArgs; const pOutDir: string): TChartResult;
var
  Found: Boolean;
  Rows: TObjectList<TIndexRow>;
begin
  var Index:= TChartsIndex.Create(pArgs.GuardedDb);
  Rows:= nil;
  try
    { ---- 1. resolve the selection and pick the mode ---- }
    var Sel:= Index.ResolveMemberSelection(pArgs.Target, ['enum_value', 'field', 'property', 'method', 'function', 'procedure'],
      False, HINT, Found);
    var Mode:= if SameText(Sel.Kind, 'enum_value') then MODE_COMMAND
      else if SameText(Sel.Kind, 'field') or SameText(Sel.Kind, 'property') then MODE_FIELD
      else MODE_METHOD;

    { ---- 2. zone map ---- }
    var RootLen:= IndexRootLen(Index);

    { ---- 3. gather the rows ---- }
    var Where:= if Mode = MODE_METHOD then Format('r.enclosing_symbol_id = %d AND tgt.kind = ''enum_value''', [Sel.Id])
      else Format('r.symbol_id = %d', [Sel.Id]);
    Rows:= Index.Query(
      'SELECT r.id AS rid, r.kind AS kind, r.name_text AS nm, r.start_line AS line,' + sLineBreak +
      '       f.path AS path, encl.qualified_name AS routine,' + sLineBreak +
      '       encl.impl_start_line AS rline, ef.path AS rpath,' + sLineBreak +
      '       tgt.qualified_name AS target_q, tgt.kind AS target_kind' + sLineBreak +
      '  FROM refs r' + sLineBreak +
      '  JOIN files f ON f.id = r.file_id' + sLineBreak +
      '  LEFT JOIN symbols encl ON encl.id = r.enclosing_symbol_id' + sLineBreak +
      '  LEFT JOIN files ef ON ef.id = encl.file_id' + sLineBreak +
      '  LEFT JOIN symbols tgt ON tgt.id = r.symbol_id' + sLineBreak +
      ' WHERE ' + Where + sLineBreak +
      ' ORDER BY r.id');
    var Commands:= 0;
    if Mode = MODE_COMMAND then
      Commands:= 1
    else if Mode = MODE_METHOD then
    begin
      var Targets: TArray<string>:= [];
      for var R in Rows do
        Targets:= Targets + [R.S('target_q')];
      Commands:= Length(SortUniqueNames(Targets));
    end;
    if Rows.Count = 0 then
    begin
      if Mode = MODE_METHOD then
        raise EChartsQuestion.CreateFmt('%s references no enum constant at all, so it speaks no protocol this index can see. ' +
          'If you expected commands here, check that the constant is an enum value rather than a typed const.', [Sel.QName]);
      raise EChartsQuestion.CreateFmt('%s has no references in this index', [Sel.QName]);
    end;

    { ---- 4. classify every row by ZONE, and by whether it is attributed ---- }
    var Unattributed:= 0;
    var KindNames: TArray<string>:= [];
    var RoutineNames: TArray<string>:= [];
    for var R in Rows do
    begin
      if R.S('routine') = '' then
        Inc(Unattributed)
      else
        RoutineNames:= RoutineNames + [R.S('routine')];
      KindNames:= KindNames + [R.S('kind')];
    end;
    var Zones:= GroupRows(Rows.ToArray, function(pR: TIndexRow): string begin Result:= PathZone(pR.S('path'), RootLen); end, False);
    TPsSort<TRowGroup>.Sort(Zones, function(const pL, pR: TRowGroup): Integer
      begin Result:= Length(pR.Rows) - Length(pL.Rows); end);
    var Kinds:= SortUniqueNames(KindNames);
    var Routines:= Length(SortUniqueNames(RoutineNames));

    { ---- 5. dot ---- }
    var NodeId:= 1;
    var Clusters:= 1;
    var Anchored:= 1;
    var FNid:= 'n' + IntToStr(NodeId);
    var Sb:= TStringBuilder.Create;
    try
      Sb.AppendLine('digraph prototrace {');
      Sb.AppendLine('  rankdir=LR; bgcolor="transparent"; compound=true;');
      Sb.AppendLine('  nodesep=0.35; ranksep=1.4; splines=spline;');
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
        AddDisclosureRow(FTbl, Format('%s  &#183;  %d reference(s) in %d zone(s)', [Sel.Kind, Rows.Count, Length(Zones)]), LINE_INK);
        if Length(Kinds) = 1 then
          AddDisclosureRow(FTbl, Format('every reference is a ''%s''', [Kinds[0]]), LINE_INK)
        else
          AddDisclosureRow(FTbl, 'MIXED reference kinds: ' + string.Join(', ', Kinds), LINE_INK);
        if Unattributed > 0 then
          AddDisclosureRow(FTbl, Format('%d reference(s) sit at unit level, not inside a routine', [Unattributed]), LINE_INK);
        AddDisclosureRow(FTbl, 'rows are zoned by FILE PATH: a shared unit is in both project indexes', LINE_INK);
        AddDisclosureRow(FTbl, 'read from refs by SQL (the site line and column; find-callers --resolved also reports enum-value refs, without a column)', LINE_INK);
        if Mode <> MODE_FIELD then
          AddDisclosureRow(FTbl, 'a bare-name binding inside a `with` block is unverified (engine risk R7; 178 such reads on CLIENT)', LINE_INK);
        FTbl.Append('</TABLE>');
        Sb.AppendLine(Format('  subgraph cluster_focus_%d {', [NodeId]));
        Sb.AppendLine(Format('    style="rounded,filled"; color="%s"; fillcolor="%s"; penwidth=2;', [FOCUS_BORDER, FOCUS_FILL]));
        Sb.AppendLine('    label=""; margin=10;');
        Sb.AppendLine(Format('    %s [label=<%s>];', [FNid, FTbl.ToString]));
        Sb.AppendLine('  }');
      finally
        FTbl.Free;
      end;

      { one cluster per ZONE, rows are the routines that reference it }
      for var Z in Zones do
      begin
        var Top:= TRanked<TRoutineRow>.TopRanked(ByRoutine(Z.Rows), pArgs.Cap, function(pB: TRoutineRow): Integer
          begin Result:= pB.Sites; end);
        var Cells: TArray<TDotRow>:= [];
        for var B in Top.Shown do
        begin
          Inc(Anchored);
          var Note:= if B.Sites > 1 then Format('%d sites', [B.Sites]) else '';
          if (Mode = MODE_METHOD) and (Length(B.Cmds) > 0) then
            Note:= CommandNote(B.Cmds, B.Sites);
          Cells:= Cells + [TDotRow.Anchored(if B.HasRoutine then ShortName(B.Name, UnitNameOf(B.Path)) else B.Name,
            B.Line, RowHref(B.Path, B.Line),
            Format('%s -- %s:%d%s', [B.Name, FileNameOf(B.Path), B.Line,
              if B.Sites > 1 then Format('  (%d references)', [B.Sites]) else '']), Note)];
        end;
        var Dt:= DisclosureText(Top.HiddenRows, Top.HiddenSites, 'routines');
        if Dt <> '' then
          Cells:= Cells + [NoteRow(Dt)];
        var IsCommon:= (Length(Z.Rows) > 0) and not TRegEx.IsMatch(Z.Name, '(?i)client|server');
        var Style:= if IsCommon then TClusterStyle.Make(COMMON_BORDER, COMMON_FILL, COMMON_HDR)
          else TClusterStyle.Make(ZONE_BORDER, ZONE_FILL, ZONE_HDR);
        Style.RowInk:= ROW_INK;
        Style.LineInk:= LINE_INK;
        Style.FontSans:= FONT_SANS;
        Inc(NodeId);
        Inc(Clusters);
        var Nid:= 'n' + IntToStr(NodeId);
        var N:= Length(Z.Rows);
        AddRowCluster(Sb, 'cluster_zone_' + IntToStr(NodeId), Nid, Z.Name,
          Format('%d reference%s', [N, if N <> 1 then 's' else '']), Cells, Style);
        Sb.AppendLine(Format('  %s:p1 -> %s [color="%s"];', [FNid, Nid, CMD_BORDER]));
      end;
      Sb.AppendLine('}');

      { ---- 6. lay out ---- }
      var Msgs: TArray<string>;
      Result.Layout:= DotLayout(pArgs.Dot, Sb.ToString, pOutDir, 'prototrace_' + TRegEx.Replace(Sel.QName, '[^A-Za-z0-9]', '_'), Msgs);
    finally
      Sb.Free;
    end;
    Result.LeftCount:= Rows.Count;
    Result.RightCount:= Length(Zones);
    Result.ClickTargets:= Result.Layout.Anchors;
    Result.AllClickable:= Result.Layout.Anchors >= Anchored;
    Result.Fields:= [TMetaField.Str('Qname', Sel.QName), TMetaField.Str('Mode', Mode), TMetaField.Int('Refs', Rows.Count),
      TMetaField.Int('Zones', Length(Zones)), TMetaField.Int('Routines', Routines), TMetaField.Int('Commands', Commands),
      TMetaField.Int('Unattributed', Unattributed), TMetaField.Str('Kinds', string.Join(',', Kinds)),
      TMetaField.Int('Clusters', Clusters), TMetaField.Int('ClickTargets', Result.Layout.Anchors),
      TMetaField.Int('Expected', Anchored), TMetaField.Bool('AllClickable', Result.AllClickable)];
  finally
    Rows.Free;
    Index.Free;
  end;
end;

initialization
  RegisterChartQuestion(PROTOCOL_TRACE_ID, Emit);

end.
