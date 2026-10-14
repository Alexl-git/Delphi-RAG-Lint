unit DRagLint.Charts.Q.TouchesTables;

(* The `touches-tables` question in-process: a port of charts\src\Emit-TouchesTables.ps1
  (spec s11; the PS output is the reference, P3). Which physical tables a method reads and
  which it writes, from symbol_facts.sql_reads / sql_writes; each table row clicks through
  to the first string literal inside the method body that names it (word-bounded, so
  GEN_DRA1_ID does not resolve DRA1), else to the method line, said as 'fact only'.

  The index-wide pre-check runs FIRST and refuses an index with no SQL facts at all (a
  client index owns no FireDAC connection): zero for the index is a different answer from
  zero for one method, which draws the focus alone with a note.

  PS traps closed: Split-Tables' Sort-Object -Unique orders case-insensitively and
  culture-aware (SortUniqueNames, CompareGroupKeys); `-contains` is case-insensitive (the
  names are upper-cased first, so ordinal is the same); a NULL SUM reads as 0. *)

interface

const
  /// <summary>The registered question id.</summary>
  TOUCHES_TABLES_ID = 'touches-tables';

implementation

uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.RegularExpressions,
  DRagLint.Charts.Question, DRagLint.Charts.Index, DRagLint.Charts.Text, DRagLint.Charts.Dot,
  DRagLint.Charts.Sql;

const
  DB_BORDER = '#BE185D';
  DB_FILL = '#FDF2F8';
  DB_HDR = '#BE185D';
  FOCUS_BORDER = '#0F766E';
  FOCUS_FILL = '#E2F1EF';
  FOCUS_HDR = '#0F766E';
  ROW_INK = '#1F2933';
  LINE_INK = '#8A94A6';
  FOCUS_INK = '#0B3F39';
  FONT_MONO = 'Consolas';
  FONT_SANS = 'Segoe UI';
  MODE_READ = 'read';
  MODE_WRITTEN = 'written';
  FACT_ONLY = 'fact only';

{ Split-Tables: comma list -> trimmed, upper-cased, non-empty, Sort-Object -Unique }
function SplitTables(const pValue: string): TArray<string>;
begin
  if Trim(pValue) = '' then
    Exit(nil);
  var Parts: TArray<string>:= [];
  for var P in TRegEx.Split(pValue, ',\s*') do
  begin
    var U:= P.Trim.ToUpperInvariant;
    if U <> '' then
      Parts:= Parts + [U];
  end;
  Result:= SortUniqueNames(Parts);
end;

function Plural(pCount: Integer): string;
begin
  Result:= if pCount <> 1 then 's' else '';
end;

function Emit(const pArgs: TQuestionArgs; const pOutDir: string): TChartResult;
var
  Lits: TObjectList<TIndexRow>;
begin
  var Qname:= pArgs.Target;
  var Index:= TChartsIndex.Create(pArgs.GuardedDb);
  try
    { ---- 1. index-wide pre-check, BEFORE anything else ---- }
    var Pre:= Index.Query(
      'SELECT SUM(sql_reads IS NOT NULL) AS r, SUM(sql_writes IS NOT NULL) AS w,' + sLineBreak +
      '       SUM(sql_reads IS NOT NULL OR sql_writes IS NOT NULL) AS either,' + sLineBreak +
      '       COUNT(*) AS n' + sLineBreak +
      '  FROM symbol_facts');
    var NReads, NWrites, NEither, NFacts: Integer;
    try
      NReads:= Pre[0].I('r');
      NWrites:= Pre[0].I('w');
      NEither:= Pre[0].I('either');
      NFacts:= Pre[0].I('n');
    finally
      Pre.Free;
    end;
    if NEither = 0 then
      raise EChartsQuestion.CreateFmt('touches-tables: this index has NO SQL facts at all (%d sql_reads, %d sql_writes ' +
        'across %d symbol_facts rows). That is correct, not a gap: this project has no FireDAC ' +
        'connection, so no method can touch a table. Ask on the index of the process that owns the ' +
        'connection (for ORM3 that is the SERVER index).', [NReads, NWrites, NFacts]);

    { ---- 2. the symbol, then its facts ---- }
    var Loc:= Index.SymbolLocation(Qname);
    var UnitName:= UnitNameOf(Loc.Path);
    var Reads, Writes: TArray<string>;
    var Fact:= Index.Query(Format('SELECT sf.sql_reads AS r, sf.sql_writes AS w FROM symbol_facts sf WHERE sf.symbol_id = %d', [Loc.Id]));
    try
      if Fact.Count > 0 then
      begin
        Reads:= SplitTables(Fact[0].S('r'));
        Writes:= SplitTables(Fact[0].S('w'));
      end;
    finally
      Fact.Free;
    end;
    var Both:= 0;
    for var R in Reads do
      for var W in Writes do
        if SameText(R, W) then
        begin
          Inc(Both);
          Break;
        end;
    var Distinct:= Length(SortUniqueNames(Reads + Writes));

    { ---- 3. provenance: the first literal inside the body that NAMES the table ---- }
    Lits:= nil;
    try
      if (Distinct > 0) and (Loc.ImplStart > 0) and (Loc.ImplEnd >= Loc.ImplStart) then
        Lits:= Index.Query(Format(
          'SELECT sl.start_line AS line, sl.kind AS kind, sl.text AS text' + sLineBreak +
          '  FROM string_literals sl JOIN files f ON f.id = sl.file_id' + sLineBreak +
          ' WHERE f.path = ''%s'' AND sl.kind IN (''literal'',''format'')' + sLineBreak +
          '   AND sl.start_line BETWEEN %d AND %d' + sLineBreak +
          ' ORDER BY sl.start_line', [TChartsIndex.SqlText(Loc.Path), Loc.ImplStart, Loc.ImplEnd]));
      var Unresolved:= 0;
      var FileName:= FileNameOf(Loc.Path);
      var TableRow:= function(const pTable, pMode: string): TDotRow
        begin
          var Re:= '(?i)(^|[^A-Z0-9_])' + TRegEx.Escape(pTable) + '([^A-Z0-9_]|$)';
          if Lits <> nil then
            for var L in Lits do
              if TRegEx.IsMatch(L.S('text'), Re) then
                Exit(TDotRow.Anchored(pTable, L.I('line'), RowHref(Loc.Path, L.I('line')),
                  Format('%s (%s)  --  %s:%d', [pTable, pMode, FileName, L.I('line')])));
          Inc(Unresolved);
          Result:= TDotRow.Anchored(pTable, Loc.FocusLine, RowHref(Loc.Path, Loc.FocusLine),
            Format('%s (%s)  --  (fact only; no literal names %s inside the method)', [pTable, pMode, pTable]), FACT_ONLY);
        end;
      var ReadRows: TArray<TDotRow>:= [];
      for var T in Reads do
        ReadRows:= ReadRows + [TableRow(T, MODE_READ)];
      var WriteRows: TArray<TDotRow>:= [];
      for var T in Writes do
        WriteRows:= WriteRows + [TableRow(T, MODE_WRITTEN)];

      { ---- 4. dot ---- }
      var Style:= TClusterStyle.Make(DB_BORDER, DB_FILL, DB_HDR);
      Style.RowInk:= ROW_INK;
      Style.LineInk:= LINE_INK;
      Style.FontSans:= FONT_SANS;
      var Sb:= TStringBuilder.Create;
      try
        Sb.AppendLine('digraph touchestables {');
        Sb.AppendLine('  rankdir=LR; bgcolor="transparent"; compound=true;');
        Sb.AppendLine('  nodesep=0.35; ranksep=1.3; splines=spline;');
        Sb.AppendLine(Format('  graph [fontname="%s"];', [FONT_SANS]));
        Sb.AppendLine(Format('  node  [shape=plaintext, fontname="%s", fontsize=14];', [FONT_MONO]));
        Sb.AppendLine(Format('  edge  [fontname="%s", fontsize=11, color="%s", penwidth=1.5, arrowsize=0.8];', [FONT_MONO, LINE_INK]));
        Sb.AppendLine('');
        var ReadPorts: TArray<string>:= [];
        if Length(ReadRows) > 0 then
          ReadPorts:= AddRowCluster(Sb, 'cluster_reads', 'nr', 'reads',
            Format('%d table%s', [Length(ReadRows), Plural(Length(ReadRows))]), ReadRows, Style);

        Sb.AppendLine('  subgraph cluster_focus {');
        Sb.AppendLine(Format('    style="rounded,filled"; color="%s"; fillcolor="%s"; penwidth=3;', [FOCUS_BORDER, FOCUS_FILL]));
        Sb.AppendLine('    label=""; margin=12;');
        var FHref:= RowHref(Loc.Path, Loc.FocusLine);
        var FHdr:= Format('<TR><TD ALIGN="LEFT" BGCOLOR="%s"><FONT COLOR="#FFFFFF" FACE="%s" POINT-SIZE="14"><B> %s &#183; focus </B></FONT></TD></TR>',
          [FOCUS_HDR, FONT_SANS, XmlText(UnitName)]);
        var FTip:= XmlText(Format('%s  --  %s:%d', [Qname, FileName, Loc.FocusLine]));
        var FTbl:= '<TABLE BORDER="0" CELLBORDER="0" CELLSPACING="3" CELLPADDING="7">' + FHdr +
          Format('<TR><TD HREF="%s" TITLE="%s"><FONT COLOR="%s" POINT-SIZE="18"><B>%s</B></FONT></TD></TR>',
            [FHref, FTip, FOCUS_INK, XmlText(ShortName(Qname, UnitName))]);
        if Distinct = 0 then
          FTbl:= FTbl + Format('<TR><TD ALIGN="LEFT"><FONT COLOR="%s" POINT-SIZE="12">touches no tables (%d methods in this index do)</FONT></TD></TR>',
            [LINE_INK, NEither]);
        Sb.AppendLine(Format('    focus [label=<%s</TABLE>>];', [FTbl]));
        Sb.AppendLine('  }');

        var WritePorts: TArray<string>:= [];
        if Length(WriteRows) > 0 then
          WritePorts:= AddRowCluster(Sb, 'cluster_writes', 'nw', 'writes',
            Format('%d table%s', [Length(WriteRows), Plural(Length(WriteRows))]), WriteRows, Style);

        Sb.AppendLine('');
        for var K:= 0 to High(ReadRows) do
          Sb.AppendLine(Format('  %s -> focus [color="%s"];', [ReadPorts[K], DB_BORDER]));
        for var K:= 0 to High(WriteRows) do
          Sb.AppendLine(Format('  focus -> %s [color="%s", penwidth=2.2];', [WritePorts[K], DB_BORDER]));
        Sb.AppendLine('}');

        { ---- 5. lay out ---- }
        var Msgs: TArray<string>;
        var Base:= TRegEx.Replace(Qname, '[^A-Za-z0-9]', '_');
        Result.Layout:= DotLayout(pArgs.Dot, Sb.ToString, pOutDir, Base, Msgs);
      finally
        Sb.Free;
      end;
      var Expected:= Length(ReadRows) + Length(WriteRows) + 1;
      Result.LeftCount:= Length(ReadRows);
      Result.RightCount:= Length(WriteRows);
      Result.ClickTargets:= Result.Layout.Anchors;
      Result.AllClickable:= Result.Layout.Anchors >= Expected;
      Result.Fields:= [TMetaField.Int('Reads', Length(ReadRows)), TMetaField.Int('Writes', Length(WriteRows)),
        TMetaField.Int('Both', Both), TMetaField.Int('Distinct', Distinct), TMetaField.Int('Unresolved', Unresolved),
        TMetaField.Int('IndexSqlSymbols', NEither), TMetaField.Int('ClickTargets', Result.Layout.Anchors),
        TMetaField.Int('Expected', Expected), TMetaField.Bool('AllClickable', Result.AllClickable)];
    finally
      Lits.Free;
    end;
  finally
    Index.Free;
  end;
end;

initialization
  RegisterChartQuestion(TOUCHES_TABLES_ID, Emit);

end.
