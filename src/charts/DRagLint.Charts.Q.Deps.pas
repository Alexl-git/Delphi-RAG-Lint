unit DRagLint.Charts.Q.Deps;

(* The `deps` question in-process: a port of charts\src\Emit-Deps.ps1 (spec s11; the PS
  output is the reference, P3). The units one unit uses and the units that use it, from
  unit_uses: rows are units, clusters are DIRECTORIES, every row clicks through to the
  uses-clause line, interface uses are solid and implementation uses dashed. Users are
  joined on the RESOLVED target_file_id (unit_name_norm is the last dotted segment and
  over-matches across namespaces). Units outside the project closure are filtered in the
  SQL, before the display cap of 40 per side; what the cap hides is counted and said.

  Emit-Deps predates Emit-Common and keeps its own cluster builder (no AddRowCluster: the
  row has no note, the header no subtitle, and the port map is keyed by row, not ordinal).

  PS traps closed: `Group-Object Dir | Sort-Object Name` groups case-insensitively and
  orders the groups by CompareGroupKeys; the port map is a PS hashtable, so its keys are
  case-insensitive and a later row overwrites an earlier one; `-eq 'implementation'` and
  `-like '(outside*'` are case-insensitive; Split-Path -Parent / -Leaf. *)

interface

const
  /// <summary>The registered question id.</summary>
  DEPS_ID = 'deps';

implementation

uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.Generics.Defaults, System.StrUtils,
  System.RegularExpressions, DRagLint.Charts.Question, DRagLint.Charts.Index, DRagLint.Charts.Text,
  DRagLint.Charts.Dot;

const
  USER_BORDER = '#3B5BDB';
  USER_FILL = '#EDF2FF';
  USER_HDR = '#3B5BDB';
  ROOT_BORDER = '#0F766E';
  ROOT_FILL = '#E2F1EF';
  ROOT_HDR = '#0F766E';
  USES_BORDER = '#B45309';
  USES_FILL = '#FEF6EC';
  USES_HDR = '#B45309';
  EXT_BORDER = '#6B7280';
  EXT_FILL = '#F3F4F6';
  EXT_HDR = '#6B7280';
  ROW_INK = '#1F2933';
  LINE_INK = '#8A94A6';
  ROOT_INK = '#0B3F39';
  FONT_MONO = 'Consolas';
  FONT_SANS = 'Segoe UI';
  { Emit-Deps -MaxRows: a DISPLAY cap per side, not a population limit }
  MAX_ROWS = 40;
  SIDE_IN = 'in';
  SIDE_OUT = 'out';
  SECTION_IMPL = 'implementation';
  OUTSIDE_DIR = '(outside the project closure)';
  OUTSIDE_PREFIX = '(outside';
  EXTERNAL_DIR = '(external)';
  ROOT_DIR = '(root)';
  DASHED = ', style=dashed';

type
  TDepRow = record
    LabelText, FilePath, Line, Section, Key, Dir: string;
  end;

  { one Group-Object group: the first row's Dir and the rows, in input order }
  TDirGroup = record
    Name: string;
    Rows: TArray<TDepRow>;
  end;

{ Get-DirLeaf: the folder a file sits in }
function DirLeaf(const pPath: string): string;
begin
  if Trim(pPath) = '' then
    Exit(EXTERNAL_DIR);
  var D:= ExtractFileDir(pPath);
  if Trim(D) = '' then
    Exit(ROOT_DIR);
  Result:= ExtractFileName(ExcludeTrailingPathDelimiter(D));
end;

(* Group-Object Dir | Sort-Object Name *)
function GroupByDir(const pRows: TArray<TDepRow>): TArray<TDirGroup>;
begin
  Result:= [];
  var Slot:= TDictionary<string, Integer>.Create(TIStringComparer.Ordinal);
  try
    for var R in pRows do
    begin
      var K: Integer;
      if not Slot.TryGetValue(R.Dir, K) then
      begin
        var G: TDirGroup;
        G.Name:= R.Dir;
        G.Rows:= [];
        Result:= Result + [G];
        K:= High(Result);
        Slot.Add(R.Dir, K);
      end;
      Result[K].Rows:= Result[K].Rows + [R];
    end;
  finally
    Slot.Free;
  end;
  { names are unique case-insensitively, so the order is total and no tie can move }
  TArray.Sort<TDirGroup>(Result, TComparer<TDirGroup>.Construct(
    function(const pL, pR: TDirGroup): Integer begin Result:= CompareGroupKeys(pL.Name, pR.Name); end));
end;

function Emit(const pArgs: TQuestionArgs; const pOutDir: string): TChartResult;
var
  NodeId: Integer;
  Ports: TDictionary<string, string>;
  Sb: TStringBuilder;

  procedure AddCluster(const pSide, pTitle: string; const pRows: TArray<TDepRow>; const pBorder, pFill, pHdr: string);
  begin
    Inc(NodeId);
    var Nid:= 'n' + IntToStr(NodeId);
    Sb.AppendLine(Format('  subgraph cluster_%s_%d {', [pSide, NodeId]));
    Sb.AppendLine(Format('    style="rounded,filled"; color="%s"; fillcolor="%s"; penwidth=2;', [pBorder, pFill]));
    Sb.AppendLine('    label=""; margin=10;');
    var Tbl:= TStringBuilder.Create;
    try
      Tbl.Append('<TABLE BORDER="0" CELLBORDER="0" CELLSPACING="3" CELLPADDING="5">');
      Tbl.Append(Format('<TR><TD ALIGN="LEFT" BGCOLOR="%s"><FONT COLOR="#FFFFFF" FACE="%s" POINT-SIZE="14"><B> %s </B></FONT></TD></TR>',
        [pHdr, FONT_SANS, XmlText(pTitle)]));
      var P:= 0;
      for var R in pRows do
      begin
        Inc(P);
        var Href:= RowHref(R.FilePath, StrToIntDef(R.Line, 0));
        var Tip:= XmlText(Format('%s  --  uses clause at %s:%s  [%s]', [R.LabelText, FileNameOf(R.FilePath), R.Line, R.Section]));
        Tbl.Append(Format('<TR><TD PORT="p%d" ALIGN="LEFT" HREF="%s" TITLE="%s">', [P, Href, Tip]));
        Tbl.Append(Format('<FONT COLOR="%s">%s</FONT>', [ROW_INK, XmlText(R.LabelText)]));
        Tbl.Append(Format('  <FONT COLOR="%s" POINT-SIZE="12">:%s</FONT>', [LINE_INK, R.Line]));
        Tbl.Append('</TD></TR>');
        Ports.AddOrSetValue(pSide + '|' + R.Key, Format('%s:p%d', [Nid, P]));
      end;
      Tbl.Append('</TABLE>');
      Sb.AppendLine(Format('    %s [label=<%s>];', [Nid, Tbl.ToString]));
      Sb.AppendLine('  }');
    finally
      Tbl.Free;
    end;
  end;

  function Count(pIndex: TChartsIndex; const pFrom: string): Integer;
  begin
    var Rows:= pIndex.Query('SELECT COUNT(*) AS n ' + pFrom);
    try
      Result:= Rows[0].I('n');
    finally
      Rows.Free;
    end;
  end;

begin
  var UnitName:= pArgs.Target;
  var Index:= TChartsIndex.Create(pArgs.GuardedDb);
  Ports:= TDictionary<string, string>.Create(TIStringComparer.Ordinal);
  Sb:= TStringBuilder.Create;
  try
    { the external filter is in the SQL, BEFORE the limit (R24); $Unit goes in raw, as in the PS }
    var OutFrom:=
      '  FROM unit_uses u' + sLineBreak +
      '  JOIN files f ON f.id = u.file_id' + sLineBreak +
      '  LEFT JOIN files t ON t.id = u.target_file_id' + sLineBreak +
      ' WHERE f.path LIKE ''%\' + UnitName + '.pas'' AND t.path IS NOT NULL AND t.path <> ''''';
    var InFrom:=
      '  FROM unit_uses u' + sLineBreak +
      '  JOIN files f ON f.id = u.file_id' + sLineBreak +
      '  JOIN files t ON t.id = u.target_file_id' + sLineBreak +
      ' WHERE t.path LIKE ''%\' + UnitName + '.pas''';
    var UsesTotal:= Count(Index, OutFrom);
    var UsersTotal:= Count(Index, InFrom);
    var UseRows: TArray<TDepRow>:= [];
    var Q:= Index.Query(Format('SELECT u.unit_name AS name, u.section AS section, u.start_line AS line,' + sLineBreak +
      '       f.path AS src, t.path AS target' + sLineBreak + '%s' + sLineBreak +
      ' ORDER BY u.section, u.unit_name' + sLineBreak + ' LIMIT %d', [OutFrom, MAX_ROWS]));
    try
      for var R in Q do
      begin
        var D: TDepRow;
        D.LabelText:= R.S('name');
        D.FilePath:= R.S('src');
        D.Line:= R.S('line');
        D.Section:= R.S('section');
        D.Key:= D.LabelText + '|' + D.Line;
        D.Dir:= if R.S('target') = '' then OUTSIDE_DIR else DirLeaf(R.S('target'));
        UseRows:= UseRows + [D];
      end;
    finally
      Q.Free;
    end;
    var UserRows: TArray<TDepRow>:= [];
    Q:= Index.Query(Format('SELECT f.path AS src, u.section AS section, u.start_line AS line' + sLineBreak + '%s' + sLineBreak +
      ' ORDER BY f.path' + sLineBreak + ' LIMIT %d', [InFrom, MAX_ROWS]));
    try
      for var R in Q do
      begin
        var D: TDepRow;
        D.LabelText:= ChangeFileExt(FileNameOf(R.S('src')), '');
        D.FilePath:= R.S('src');
        D.Line:= R.S('line');
        D.Section:= R.S('section');
        D.Key:= D.FilePath + '|' + D.Line;
        D.Dir:= DirLeaf(D.FilePath);
        UserRows:= UserRows + [D];
      end;
    finally
      Q.Free;
    end;
    var UsesHidden:= UsesTotal - Length(UseRows);
    var UsersHidden:= UsersTotal - Length(UserRows);

    { ---- dot ---- }
    NodeId:= 0;
    Sb.AppendLine('digraph deps {');
    Sb.AppendLine('  rankdir=LR; bgcolor="transparent"; compound=true;');
    Sb.AppendLine('  nodesep=0.35; ranksep=1.2; splines=spline;');
    Sb.AppendLine(Format('  node [shape=plaintext, fontname="%s", fontsize=14];', [FONT_MONO]));
    Sb.AppendLine(Format('  edge [fontname="%s", fontsize=11, penwidth=1.5, arrowsize=0.8];', [FONT_MONO]));
    Sb.AppendLine('');

    for var G in GroupByDir(UserRows) do
      AddCluster(SIDE_IN, G.Name + '  (uses this)', G.Rows, USER_BORDER, USER_FILL, USER_HDR);

    Sb.AppendLine('  subgraph cluster_root {');
    Sb.AppendLine(Format('    style="rounded,filled"; color="%s"; fillcolor="%s"; penwidth=3;', [ROOT_BORDER, ROOT_FILL]));
    Sb.AppendLine('    label=""; margin=12;');
    var RootTbl:= TStringBuilder.Create;
    try
      RootTbl.Append(Format('<TABLE BORDER="0" CELLBORDER="0" CELLSPACING="3" CELLPADDING="7"><TR><TD ALIGN="LEFT" BGCOLOR="%s">' +
        '<FONT COLOR="#FFFFFF" FACE="%s" POINT-SIZE="14"><B> unit &#183; focus </B></FONT></TD></TR><TR><TD><FONT COLOR="%s" ' +
        'POINT-SIZE="18"><B>%s</B></FONT></TD></TR>', [ROOT_HDR, FONT_SANS, ROOT_INK, XmlText(UnitName)]));
      if UsersHidden > 0 then
        AddDisclosureRow(RootTbl, Format('+%d more units that use this not shown -- %d of %d drawn (display cap %d)',
          [UsersHidden, Length(UserRows), UsersTotal, MAX_ROWS]), LINE_INK);
      if UsesHidden > 0 then
        AddDisclosureRow(RootTbl, Format('+%d more units this uses not shown -- %d of %d drawn (display cap %d)',
          [UsesHidden, Length(UseRows), UsesTotal, MAX_ROWS]), LINE_INK);
      RootTbl.Append('</TABLE>');
      Sb.AppendLine(Format('    root [label=<%s>];', [RootTbl.ToString]));
      Sb.AppendLine('  }');
    finally
      RootTbl.Free;
    end;

    for var G in GroupByDir(UseRows) do
    begin
      var IsExt:= StartsText(OUTSIDE_PREFIX, G.Name);
      AddCluster(SIDE_OUT, G.Name + '  (used by this)', G.Rows,
        if IsExt then EXT_BORDER else USES_BORDER, if IsExt then EXT_FILL else USES_FILL, if IsExt then EXT_HDR else USES_HDR);
    end;

    Sb.AppendLine('');
    for var R in UserRows do
    begin
      var Port: string;
      if not Ports.TryGetValue(SIDE_IN + '|' + R.Key, Port) then
        Continue;
      var St:= if SameText(R.Section, SECTION_IMPL) then DASHED else '';
      Sb.AppendLine(Format('  %s -> root [color="%s"%s];', [Port, USER_BORDER, St]));
    end;
    var Impl:= 0;
    for var R in UseRows do
    begin
      if SameText(R.Section, SECTION_IMPL) then
        Inc(Impl);
      var Port: string;
      if not Ports.TryGetValue(SIDE_OUT + '|' + R.Key, Port) then
        Continue;
      var St:= if SameText(R.Section, SECTION_IMPL) then DASHED else '';
      var Col:= if StartsText(OUTSIDE_PREFIX, R.Dir) then EXT_BORDER else USES_BORDER;
      Sb.AppendLine(Format('  root -> %s [color="%s"%s];', [Port, Col, St]));
    end;
    Sb.AppendLine('}');

    { ---- write + lay out ---- }
    var Msgs: TArray<string>;
    Result.Layout:= DotLayout(pArgs.Dot, Sb.ToString, pOutDir, TRegEx.Replace(UnitName, '[^A-Za-z0-9]', '_'), Msgs);
    var Rows:= Length(UserRows) + Length(UseRows);
    Result.LeftCount:= Length(UserRows);
    Result.RightCount:= Length(UseRows);
    Result.ClickTargets:= Result.Layout.Anchors;
    Result.AllClickable:= Result.Layout.Anchors >= Rows;
    Result.Fields:= [TMetaField.Int('UsedBy', Length(UserRows)), TMetaField.Int('Uses', Length(UseRows)),
      TMetaField.Int('UsedByTotal', UsersTotal), TMetaField.Int('UsesTotal', UsesTotal),
      TMetaField.Int('UsedByHidden', UsersHidden), TMetaField.Int('UsesHidden', UsesHidden),
      TMetaField.Int('ImplementationUses', Impl), TMetaField.Int('ClickTargets', Result.Layout.Anchors),
      TMetaField.Int('Expected', Rows), TMetaField.Bool('AllClickable', Result.AllClickable)];
  finally
    Sb.Free;
    Ports.Free;
    Index.Free;
  end;
end;

initialization
  RegisterChartQuestion(DEPS_ID, Emit);

end.
