unit DRagLint.Charts.Q.MemberAccess;

(* The `who-writes` AND `who-reads` questions in-process: a port of the ROWS, the DOT and the FIELDS of
  charts\src\Emit-MemberAccess.ps1 (steps 6-8; spec s11; the PS output is the reference, P3), registered from
  this one unit exactly as Q.WhoCalls registers its two ids: the PS header rules ONE emitter for both
  questions, and the mode is read from the question id. The data (PS steps 1-5 and the measurements) is
  DRagLint.Charts.MemberAccess (decision M2, by reference); this unit only draws it.

  WHAT IT DRAWS. The routines that ASSIGN (who-writes) or READ (who-reads) one FIELD or PROPERTY, as one
  cluster of anchored rows beside a focus node that is the member itself. STATE is a new palette role --
  neither caller blue nor callee amber -- and DIRECTION carries read versus write, not colour: a writer
  points AT the member (the routine acts on it), the member points at a reader (the value flows out).
  Writers are drawn heavier (penwidth 3): a write is the stronger claim about shared state. A routine that
  both reads and writes appears on both sides in the mode that draws both; here each question draws one
  wing, and the other direction's count is printed on the focus ('reads (not drawn): ...'), so a zero in
  the drawn direction is never a bare '0'. A disclosure row is a NOTE row (no Href) and gets no edge.

  NOT PORTED. -Mode both at the question level (M1: no question id carries it; the data layer accepts it,
  ruling R5, and this unit never passes it); the PS 200-row refusal of the site query (the in-process
  query has no cap); Write-Host output (no host stream here).

  PS TRAPS CLOSED. Build-Wing's unary comma `, $rows.ToArray()` nested by an `@()` wrapper and made an empty
  wing a blank row: a TArray<TDotRow> has no such nesting. `$sel.Kind -eq 'property'` is case-blind
  (SameText). `[string]::IsNullOrWhiteSpace($Href)` is Href = '' here, because TDotRow.Href is '' (a note
  row) or a RowHref. `$x = if (...) { @() }` assigning $null does not exist. The bundle header labels are
  '' where the PS wrote $null (TChartResult.LeftLabel / RightLabel, decision M12), and the meta.json
  fields are TMetaField.Null in that case. *)

interface

const
  /// <summary>The registered question id of the writers wing (Emit-MemberAccess.ps1 -Mode write).</summary>
  WHO_WRITES_ID = 'who-writes';
  /// <summary>The registered question id of the readers wing (Emit-MemberAccess.ps1 -Mode read),
  /// answered by the same unit.</summary>
  WHO_READS_ID = 'who-reads';

implementation

uses
  System.SysUtils, System.Generics.Collections, System.RegularExpressions, DRagLint.Core.Interfaces,
  DRagLint.Storage.SQLite, DRagLint.Charts.Question,
  DRagLint.Charts.Index, DRagLint.Charts.Text, DRagLint.Charts.Dot,
  DRagLint.Charts.MemberAccess; // dl:unit DRagLint.Charts.MemberAccess accepted -- the data layer's mode ids travel with its collector and its text helpers; this unit draws what that unit collects

const
  { STATE: the member tier, neither caller blue, callee amber, focus teal, ui violet nor db rose }
  STATE_BORDER = '#0E7490';
  STATE_FILL = '#ECFEFF';
  STATE_HDR = '#0E7490';
  FOCUS_BORDER = '#0F766E';
  FOCUS_FILL = '#E2F1EF';
  FOCUS_HDR = '#0F766E';
  ROW_INK = '#1F2933';
  LINE_INK = '#8A94A6';
  FOCUS_INK = '#0B3F39';
  FONT_MONO = 'Consolas';
  FONT_SANS = 'Segoe UI';
  { the tooltip names at most this many sites, as line:col }
  SITE_TIP_MAX = 6;
  WRITER_PEN_WIDTH = 3;

/// <summary>The one row of a routine in one wing.</summary>
/// <param name="pData">The collected facts; supplies the sites and the selection.</param>
/// <param name="pRow">The routine and how many sites find-callers reported in it.</param>
/// <param name="pMode">MODE_WRITE or MODE_READ.</param>
/// <param name="pUnanchored">Incremented when the index holds no site for the routine.</param>
/// <returns>An anchored row: the FIRST site (line and column in the tooltip), or the member's own line
/// with the note 'site not located' when SQL found no site (still anchored, so it gets an edge).</returns>
function RoutineRow(pData: TMemberAccessData; const pRow: TRoutineHits; const pMode: string;
  var pUnanchored: Integer): TDotRow;
begin
  var Sel:= pData.Sel;
  var SS:= pData.SitesOf(pRow.Routine, pMode);
  if Length(SS) = 0 then
  begin
    { the verb named this routine but SQL found no site: anchor to the member, and SAY it }
    Inc(pUnanchored);
    Exit(TDotRow.Anchored(ShortName(pRow.Routine, UnitNameOf(Sel.Path)), Sel.FocusLine, RowHref(Sel.Path, Sel.FocusLine),
      Format('%s -- %d %s site(s); no site location in the index, anchored to the member', [pRow.Routine, pRow.Sites, pMode]),
      'site not located'));
  end;
  var Shown: TArray<string>:= [];
  var TipCount:= Length(SS);
  if TipCount > SITE_TIP_MAX then
    TipCount:= SITE_TIP_MAX;
  for var K:= 0 to TipCount - 1 do
    Shown:= Shown + [Format('%d:%d', [SS[K].Line, SS[K].Col])];
  var More:= '';
  if Length(SS) > SITE_TIP_MAX then
    More:= Format(' (+%d more)', [Length(SS) - SITE_TIP_MAX]);
  var Plural:= '';
  if Length(SS) <> 1 then
    Plural:= 's';
  var Note:= '';
  if Length(SS) > 1 then
    Note:= Format('%d sites', [Length(SS)]);
  Result:= TDotRow.Anchored(ShortName(pRow.Routine, UnitNameOf(SS[0].Path)), SS[0].Line, RowHref(SS[0].Path, SS[0].Line),
    Format('%d %s site%s: %s%s', [Length(SS), pMode, Plural, string.Join(', ', Shown), More]), Note);
end;

/// <summary>The rows of one wing: one per shown routine, then the 'more routines' disclosure.</summary>
/// <param name="pData">The collected facts.</param>
/// <param name="pTop">The ranked, capped routines of the wing.</param>
/// <param name="pMode">MODE_WRITE or MODE_READ.</param>
/// <param name="pUnanchored">Incremented per routine with no site.</param>
/// <returns>The rows; the disclosure is a note row (no Href), so it gets no edge.</returns>
function BuildWing(pData: TMemberAccessData; const pTop: TRanked<TRoutineHits>; const pMode: string;
  var pUnanchored: Integer): TArray<TDotRow>;
begin
  Result:= [];
  for var R in pTop.Shown do
    Result:= Result + [RoutineRow(pData, R, pMode, pUnanchored)];
  var Disclosure:= DisclosureText(pTop.HiddenRows, pTop.HiddenSites, 'routines');
  if Disclosure <> '' then
    Result:= Result + [NoteRow(Disclosure)];
end;

/// <summary>The disclosure rows for what the index holds UNBOUND in one direction.</summary>
/// <param name="pTable">The focus table being built; must not be nil.</param>
/// <param name="pU">The unreported refs of one kind.</param>
/// <param name="pPrefix">'engine D13' (writes) or 'engine' (reads).</param>
/// <param name="pSel">The selection, for the member name and its file.</param>
/// <remarks>Same-file refs by line (very probably this member), other files by count only (may be other
/// symbols). None of them is counted in a wing or a total.</remarks>
procedure AddUnreportedRows(pTable: TStringBuilder; const pU: TUnreportedAccess; const pPrefix: string;
  const pSel: TMemberSelection);
begin
  if pU.Same > 0 then
  begin
    var More:= '';
    if pU.Same > Length(pU.SameLines) then
      More:= Format(' (+%d more)', [pU.Same - Length(pU.SameLines)]);
    AddDisclosureRow(pTable, Format('%s: %d UNBOUND %s(s) named %s in %s at %s%s -- by name, NOT counted above',
      [pPrefix, pU.Same, pU.Kind, pSel.Name, FileNameOf(pSel.Path), string.Join(', ', pU.SameLines), More]), LINE_INK);
  end;
  if pU.Elsewhere > 0 then
    AddDisclosureRow(pTable, Format('%s: %d more unbound %s(s) of the name %s in other files -- may be other symbols',
      [pPrefix, pU.Elsewhere, pU.Kind, pSel.Name]), LINE_INK);
end;

/// <summary>The focus node's HTML-label table: the member, then every disclosure the chart owes.</summary>
/// <param name="pData">The collected facts.</param>
/// <returns>The complete TABLE text (without the node wrapper).</returns>
/// <remarks>Disclosure order, as the PS: zero note and unbound writes (write wing), zero note and unbound
/// reads (read wing), the not-drawn counts of the other direction, then one hint per backing accessor.</remarks>
function FocusTable(pData: TMemberAccessData): string;
begin
  var Sel:= pData.Sel;
  var Unit_:= pData.UnitName;
  var FHdr:= Format('<TR><TD ALIGN="LEFT" BGCOLOR="%s"><FONT COLOR="#FFFFFF" FACE="%s" POINT-SIZE="14"><B> %s &#183; %s </B></FONT></TD></TR>',
    [FOCUS_HDR, FONT_SANS, XmlText(Unit_), Sel.Kind]);
  var FTip:= XmlText(Format('%s  --  %s:%d', [Sel.QName, FileNameOf(Sel.Path), Sel.FocusLine]));
  var Tbl:= TStringBuilder.Create;
  try
    Tbl.Append('<TABLE BORDER="0" CELLBORDER="0" CELLSPACING="3" CELLPADDING="7">' + FHdr);
    Tbl.Append(Format('<TR><TD HREF="%s" TITLE="%s"><FONT COLOR="%s" POINT-SIZE="18"><B>%s</B></FONT></TD></TR>',
      [RowHref(Sel.Path, Sel.FocusLine), FTip, FOCUS_INK, XmlText(ShortName(Sel.QName, Unit_))]));
    if pData.ShowWrite and (pData.TotalWrites = 0) then
      AddDisclosureRow(Tbl, ZeroNote('write', pData.WU, pData.TotalReads, pData.RU, Sel), LINE_INK);
    if pData.ShowWrite then
      AddUnreportedRows(Tbl, pData.WU, 'engine D13', Sel);
    if pData.ShowRead and (pData.TotalReads = 0) then
      AddDisclosureRow(Tbl, ZeroNote('read', pData.RU, pData.TotalWrites, pData.WU, Sel), LINE_INK);
    if pData.ShowRead then
      AddUnreportedRows(Tbl, pData.RU, 'engine', Sel);
    { the OTHER direction is not drawn line by line, but its count is printed }
    if (not pData.ShowWrite) and (pData.WU.Total > 0) and (pData.TotalReads <> 0) then
      AddDisclosureRow(Tbl, 'writes (not drawn): ' + FormatAccessCount(pData.TotalWrites, pData.WU, Sel), LINE_INK);
    if (not pData.ShowRead) and (pData.RU.Total > 0) and (pData.TotalWrites <> 0) then
      AddDisclosureRow(Tbl, 'reads (not drawn): ' + FormatAccessCount(pData.TotalReads, pData.RU, Sel), LINE_INK);
    { a property and its backing are DIFFERENT selections: the hint keeps the other answer reachable }
    for var B in pData.Backing do
      if SameText(B.Kind, 'field') then
        AddDisclosureRow(Tbl, Format('backed by %s -- ask who-writes on it for writes that bypass this property', [B.Name]), LINE_INK)
      else
        AddDisclosureRow(Tbl, Format('accessor %s -- ask who-calls on it', [B.Name]), LINE_INK);
    Tbl.Append('</TABLE>');
    Result:= Tbl.ToString;
  finally
    Tbl.Free;
  end;
end;

/// <summary>A count's meta.json field: the label when there is one, else JSON null.</summary>
/// <param name="pName">The field name.</param>
/// <param name="pLabel">The label; '' is the PS $null.</param>
/// <returns>TMetaField.Str, or TMetaField.Null for ''.</returns>
function LabelField(const pName, pLabel: string): TMetaField;
begin
  if pLabel = '' then
    Result:= TMetaField.Null(pName)
  else
    Result:= TMetaField.Str(pName, pLabel);
end;

/// <summary>The plural s of a count.</summary>
/// <param name="pN">The count.</param>
/// <returns>'' for exactly 1, else 's'.</returns>
function PluralS(pN: Integer): string;
begin
  Result:= 's';
  if pN = 1 then
    Result:= '';
end;

/// <summary>Appends the whole DOT text: header, writers, focus, readers, edges.</summary>
/// <param name="pSb">The DOT text being built; must not be nil.</param>
/// <param name="pData">The collected facts.</param>
/// <param name="pWriteRows">The writers wing rows (empty when not drawn).</param>
/// <param name="pReadRows">The readers wing rows (empty when not drawn).</param>
procedure BuildDot(pSb: TStringBuilder; pData: TMemberAccessData; const pWriteRows, pReadRows: TArray<TDotRow>);
begin
  pSb.AppendLine('digraph memberaccess {');
  pSb.AppendLine('  rankdir=LR; bgcolor="transparent"; compound=true;');
  pSb.AppendLine('  nodesep=0.35; ranksep=1.3; splines=spline;');
  pSb.AppendLine(Format('  graph [fontname="%s"];', [FONT_SANS]));
  pSb.AppendLine(Format('  node  [shape=plaintext, fontname="%s", fontsize=14];', [FONT_MONO]));
  pSb.AppendLine(Format('  edge  [fontname="%s", fontsize=11, color="%s", penwidth=1.5, arrowsize=0.8];', [FONT_MONO, LINE_INK]));
  pSb.AppendLine('');
  var Style:= TClusterStyle.Make(STATE_BORDER, STATE_FILL, STATE_HDR);
  Style.RowInk:= ROW_INK;
  Style.LineInk:= LINE_INK;
  Style.FontSans:= FONT_SANS;
  var WritePorts: TArray<string>:= [];
  var ReadPorts: TArray<string>:= [];
  { WRITERS on the left, heavier than readers }
  if Length(pWriteRows) > 0 then
  begin
    var WStyle:= Style;
    WStyle.PenWidth:= WRITER_PEN_WIDTH;
    WritePorts:= AddRowCluster(pSb, 'cluster_writers', 'nw', 'writers',
      Format('%d routine%s, %d site%s', [pData.WTop.Total, PluralS(pData.WTop.Total),
        pData.TotalWrites, PluralS(pData.TotalWrites)]), pWriteRows, WStyle);
  end;
  { focus: the MEMBER }
  pSb.AppendLine('  subgraph cluster_focus {');
  pSb.AppendLine(Format('    style="rounded,filled"; color="%s"; fillcolor="%s"; penwidth=3;', [FOCUS_BORDER, FOCUS_FILL]));
  pSb.AppendLine('    label=""; margin=12;');
  pSb.AppendLine(Format('    focus [label=<%s>];', [FocusTable(pData)]));
  pSb.AppendLine('  }');
  if Length(pReadRows) > 0 then
    ReadPorts:= AddRowCluster(pSb, 'cluster_readers', 'nr', 'readers',
      Format('%d routine%s, %d site%s', [pData.RTop.Total, PluralS(pData.RTop.Total),
        pData.TotalReads, PluralS(pData.TotalReads)]), pReadRows, Style);  // dl:ok duplicate-code@1d9f -- REVIEWED 2026-10-17: the cluster-and-edge tail mirrors the script's own two wing blocks (precedent Q.Hierarchy, decision F9); sharing it would cost a callback for a Format and an AppendLine
  pSb.AppendLine('');
  { writer -> member (the routine acts ON it); member -> reader (the value flows OUT). A note row gets NO edge. }
  for var I:= 0 to High(pWriteRows) do
    if pWriteRows[I].Href <> '' then
      pSb.AppendLine(Format('  %s -> focus [color="%s", penwidth=2.2];', [WritePorts[I], STATE_BORDER]));
  for var I:= 0 to High(pReadRows) do
    if pReadRows[I].Href <> '' then
      pSb.AppendLine(Format('  focus -> %s [color="%s"];', [ReadPorts[I], STATE_BORDER]));
  pSb.AppendLine('}');
end;

/// <summary>Answers who-writes or who-reads for pArgs.Target (Emit-MemberAccess.ps1 -Mode write / read).</summary>
/// <param name="pArgs">The question; Question picks the wing, Target is a field or property, Cap bounds the routines drawn.</param>
/// <param name="pOutDir">The bundle folder the layout files go to.</param>
/// <returns>The chart: LeftCount the sites of the asked direction, RightCount the distinct routines; LeftLabel and
/// RightLabel carry the emitter's own wording when find-callers does not report the whole story.</returns>
/// <exception cref="EChartsIndex">The target is not in the index, is ambiguous, or is a method (ResolveMemberSelection's text).</exception>
/// <remarks>Opens a read-only TSQLiteSymbolStore beside the TChartsIndex (two read-only handles on one file).</remarks>
function Emit(const pArgs: TQuestionArgs; const pOutDir: string): TChartResult;
begin
  var Writing:= SameText(pArgs.Question, WHO_WRITES_ID);
  var Mode:= MODE_READ;
  if Writing then
    Mode:= MODE_WRITE;
  var Db:= pArgs.GuardedDb;
  var Store: ISymbolStore:= TSQLiteSymbolStore.Create(Db, True);
  var Index:= TChartsIndex.Create(Db);
  var Data: TMemberAccessData:= nil;
  try
    Data:= CollectMemberAccess(Index, Store, pArgs.Target, Mode, pArgs.Cap);
    var Unanchored:= 0;
    var WriteRows: TArray<TDotRow>:= [];
    var ReadRows: TArray<TDotRow>:= [];
    if Data.ShowWrite then
      WriteRows:= BuildWing(Data, Data.WTop, MODE_WRITE, Unanchored);
    if Data.ShowRead then
      ReadRows:= BuildWing(Data, Data.RTop, MODE_READ, Unanchored);
    var Sb:= TStringBuilder.Create;
    try
      BuildDot(Sb, Data, WriteRows, ReadRows);
      var Msgs: TArray<string>;
      var Base:= TRegEx.Replace(Data.Sel.QName, '[^A-Za-z0-9]', '_') + '_' + Mode;
      Result.Layout:= DotLayout(pArgs.Dot, Sb.ToString, pOutDir, Base, Msgs);
    finally
      Sb.Free;
    end;
    { anchored rows plus the focus, which carries an HREF }
    var Anchored:= 0;
    for var R in WriteRows do
      if R.Href <> '' then
        Inc(Anchored);
    for var R in ReadRows do
      if R.Href <> '' then
        Inc(Anchored);
    var Expected:= Anchored + 1;
    Result.ClickTargets:= Result.Layout.Anchors;
    Result.AllClickable:= Result.Layout.Anchors >= Expected;
    var WritesLabel:= Data.CountLabel(Data.WU);
    var ReadsLabel:= Data.CountLabel(Data.RU);
    var RoutinesLabel:= Data.RoutinesLabel;
    Result.LeftCount:= Data.TotalReads;
    Result.LeftLabel:= ReadsLabel;
    if Writing then
    begin
      Result.LeftCount:= Data.TotalWrites;
      Result.LeftLabel:= WritesLabel;
    end;
    Result.RightCount:= Data.DistinctRoutines;
    Result.RightLabel:= RoutinesLabel;
    var Names: TArray<string>:= [];
    for var B in Data.Backing do
      Names:= Names + [B.Name];
    var ShownWriters:= Length(Data.WTop.Shown);
    var ShownReaders:= Length(Data.RTop.Shown);
    Result.Fields:= [TMetaField.Str('Question', pArgs.Question), TMetaField.Str('Mode', Mode),
      TMetaField.Str('Kind', Data.Sel.Kind), TMetaField.Str('Resolved', Data.Sel.QName),
      TMetaField.Int('Writes', Data.TotalWrites), TMetaField.Int('Reads', Data.TotalReads),
      TMetaField.Int('Routines', Data.DistinctRoutines), TMetaField.Int('Sites', Data.TotalSites),
      TMetaField.Int('ShownWriters', ShownWriters), TMetaField.Int('ShownReaders', ShownReaders),
      TMetaField.Int('Shown', ShownWriters + ShownReaders),
      TMetaField.Int('HiddenRoutines', Data.WTop.HiddenRows + Data.RTop.HiddenRows),
      TMetaField.Int('HiddenSites', Data.WTop.HiddenSites + Data.RTop.HiddenSites),
      TMetaField.Int('Unanchored', Unanchored), TMetaField.StrList('Backing', Names),
      TMetaField.Str('CrossCheck', Data.CrossCheck),
      TMetaField.Int('D13SameFile', Data.WU.Same), TMetaField.Int('D13Elsewhere', Data.WU.Elsewhere),
      TMetaField.Int('ReadsSameFile', Data.RU.Same), TMetaField.Int('ReadsElsewhere', Data.RU.Elsewhere),
      TMetaField.Str('ReadsSameLines', string.Join(',', Data.RU.SameLines)),
      TMetaField.Int('WritesUnreported', Data.WU.Total), TMetaField.Int('ReadsUnreported', Data.RU.Total),
      LabelField('WritesLabel', WritesLabel), LabelField('ReadsLabel', ReadsLabel),
      LabelField('RoutinesLabel', RoutinesLabel), TMetaField.Int('ClickTargets', Result.Layout.Anchors),
      TMetaField.Int('Expected', Expected), TMetaField.Bool('AllClickable', Result.AllClickable)];
  finally
    Data.Free;
    Index.Free;
  end;
end;

initialization
  RegisterChartQuestion(WHO_WRITES_ID, Emit);
  RegisterChartQuestion(WHO_READS_ID, Emit);

end.
