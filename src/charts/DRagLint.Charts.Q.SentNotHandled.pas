unit DRagLint.Charts.Q.SentNotHandled;

{ drag-lint 1.56 -- lane CHB-2: the chart question `sent-not-handled` (`ask sent-not-handled`).
  G-71: protocol commands that are sent but never handled, over --counterpart-db.
  The id, its menu caption and its two count labels are a row of V156_QUESTIONS in DRagLint.Charts.Question
  (written by W2FRAME; another wording is a request to INT). A question, not a lint rule (owner ruling).

  Definitions (the same evidence crosses-boundary uses; the chart prints them):
    command  = an enum_value symbol (a protocol command constant);
    sent     = the project index has a routine that names the command AND calls a routine of a transport unit
               (unit name Pipes.% | uPipe% | uBroadcast%); the transport units' own routines do not count;
    handled  = the counterpart index names the same command (by name, case-blind) in a routine outside the
               transport units.
  A command the counterpart merely sends is therefore counted handled: the question leaves no real handler
  unreported, and may miss a command whose only counterpart use is another send. It says so in the graph.
  Target is `project` (every sent command) or one command name. With no --counterpart-db the question is
  refused: without the far side "never handled" cannot be told from "handled elsewhere". }

interface

const
  /// <summary>The registered question id.</summary>
  SENT_NOT_HANDLED_ID = 'sent-not-handled';

implementation

uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.Generics.Defaults,
  DRagLint.Charts.Question, DRagLint.Charts.Index, DRagLint.Charts.Text, DRagLint.Charts.Dot, DRagLint.Charts.Tools;

const
  DEFAULT_CAP = 40;
  BOUNDARY_PATTERN = 'Pipes.%|uPipe%|uBroadcast%';
  PROJECT_TARGET = 'project';
  OK_FILL = '#E2F1EF';
  BAD_FILL = '#FDE8E8';
  NOTE_INK = '#8A94A6';

type
  /// <summary>One sent command.</summary>
  TSentCommand = record
    Name: string;
    QName: string;
    Senders: Integer;
    Line: Integer;
    Path: string;
    Handled: Boolean;
  end;

// the SQL predicate "file pFileCol belongs to a transport unit"
function BoundaryFileSql(const pFileCol: string): string;
begin
  var Likes: TArray<string>:= [];
  for var P in BOUNDARY_PATTERN.Split(['|']) do
    Likes:= Likes + ['u.qualified_name LIKE ''' + TChartsIndex.SqlText(P) + ''''];
  Result:= pFileCol + ' IN (SELECT u.file_id FROM symbols u WHERE u.kind = ''unit'' AND (' + string.Join(' OR ', Likes) + '))';
end;

// the commands the project index sends: named in a routine that calls into a transport unit
function SentCommands(const pIndex: TChartsIndex; const pOnly: string): TList<TSentCommand>;
begin
  Result:= TList<TSentCommand>.Create;
  var Rows:= pIndex.Query(
    'SELECT tgt.name AS nm, tgt.qualified_name AS q, COUNT(DISTINCT r.enclosing_symbol_id) AS senders,' + sLineBreak +
    '       MIN(r.start_line) AS line, MIN(f.path) AS path' + sLineBreak +
    '  FROM refs r' + sLineBreak +
    '  JOIN symbols tgt ON tgt.id = r.symbol_id AND tgt.kind = ''enum_value''' + sLineBreak +
    '  JOIN files f ON f.id = r.file_id' + sLineBreak +
    ' WHERE NOT (' + BoundaryFileSql('r.file_id') + ')' + sLineBreak +
    '   AND r.enclosing_symbol_id IN (' + sLineBreak +
    '       SELECT r2.enclosing_symbol_id FROM call_edges ce' + sLineBreak +
    '         JOIN refs r2 ON r2.id = ce.ref_id' + sLineBreak +
    '         JOIN symbols s ON s.id = ce.target_symbol_id' + sLineBreak +
    '        WHERE ' + BoundaryFileSql('s.file_id') + ')' + sLineBreak +
    '   AND (''' + TChartsIndex.SqlText(pOnly) + ''' = '''' OR LOWER(tgt.name) = LOWER(''' + TChartsIndex.SqlText(pOnly) + '''))' + sLineBreak +
    ' GROUP BY tgt.qualified_name, tgt.name' + sLineBreak +
    ' ORDER BY LOWER(tgt.name), tgt.qualified_name');
  try
    for var R in Rows do
    begin
      var C: TSentCommand;
      C.Name:= R.S('nm');
      C.QName:= R.S('q');
      C.Senders:= R.I('senders');
      C.Line:= R.I('line');
      C.Path:= R.S('path');
      C.Handled:= False;
      Result.Add(C);
    end;
  finally
    Rows.Free;
  end;
end;

// marks every command the counterpart index names outside a transport unit as handled
procedure MarkHandled(const pArgs: TQuestionArgs; const pCmds: TList<TSentCommand>);
var
  Note: string;
begin
  var Names: TArray<string>:= [];
  for var C in pCmds do
    Names:= Names + [C.Name];
  if Length(Names) = 0 then
    Exit;
  var Far:= TChartsIndex.Create(CloneDb(pArgs.CounterpartDb, pArgs.CloneRoot, Note));
  var Known:= TDictionary<string, Boolean>.Create(TIStringComparer.Ordinal);
  try
    var Rows:= Far.Query(
      'SELECT DISTINCT tgt.name AS nm FROM refs r' + sLineBreak +  // dl:ok sql-injection-concat@2e06 -- read-only index query; names go through SqlInList (quoted), the boundary predicate is built from a constant
      '  JOIN symbols tgt ON tgt.id = r.symbol_id AND tgt.kind = ''enum_value''' + sLineBreak +
      ' WHERE NOT (' + BoundaryFileSql('r.file_id') + ')' + sLineBreak +
      '   AND tgt.name IN (' + TChartsIndex.SqlInList(Names) + ')');
    try
      for var R in Rows do
        Known.AddOrSetValue(R.S('nm'), True);
    finally
      Rows.Free;
    end;
    for var K:= 0 to pCmds.Count - 1 do
    begin
      var C:= pCmds[K];
      C.Handled:= Known.ContainsKey(C.Name);
      pCmds[K]:= C;
    end;
  finally
    Known.Free;
    Far.Free;
  end;
end;

function NodeLine(pIdx: Integer; const pC: TSentCommand): string;
begin
  var Url:= if pC.Path <> '' then Format(', URL="%s"', [RowHref(pC.Path, pC.Line)]) else '';
  Result:= Format('  c%d [label="%s\n%d sending routine(s)", fillcolor="%s"%s];',
    [pIdx, XmlText(pC.Name), pC.Senders, if pC.Handled then OK_FILL else BAD_FILL, Url]);
end;

/// <summary>Answers `sent-not-handled`: the commands the project index sends that the counterpart index never handles.</summary>
/// <param name="pArgs">The question arguments; Target is `project` or one command name; CounterpartDb is required; Cap bounds the commands drawn.</param>
/// <param name="pOutDir">Where dot, svg, plain, png and pdf are written.</param>
/// <returns>The chart result: LeftCount = commands sent, RightCount = commands never handled.</returns>
/// <exception cref="EChartsQuestion">No counterpart index was given, or no command is sent in this index.</exception>
/// <remarks>Read-only on both indexes (the counterpart goes through the clone guard). Zero never-handled commands is an answer. Meta fields: Sent, Handled, NeverHandled, Shown, Hidden, ClickTargets, Expected, AllClickable.</remarks>
function Emit(const pArgs: TQuestionArgs; const pOutDir: string): TChartResult;
begin
  if pArgs.CounterpartDb = '' then
    raise EChartsQuestion.Create('sent-not-handled needs the other side: give --counterpart-db <index>');
  var Only:= if SameText(Trim(pArgs.Target), PROJECT_TARGET) then '' else Trim(pArgs.Target);
  var Index:= TChartsIndex.Create(pArgs.GuardedDb);
  var Cmds:= SentCommands(Index, Only);
  var Sb:= TStringBuilder.Create;
  try
    if Cmds.Count = 0 then
      raise EChartsQuestion.Create('no command is sent in this index (a command is an enum constant named in a routine that calls a transport unit: ' + BOUNDARY_PATTERN + ')');
    MarkHandled(pArgs, Cmds);
    var Never:= 0;
    for var C in Cmds do
      if not C.Handled then
        Inc(Never);
    var CapCmds:= if pArgs.Cap > 0 then pArgs.Cap else DEFAULT_CAP;
    // never-handled first: the cap must not cut the finding
    var Order: TArray<Integer>:= [];
    for var K:= 0 to Cmds.Count - 1 do
      if not Cmds[K].Handled then
        Order:= Order + [K];
    for var K:= 0 to Cmds.Count - 1 do
      if Cmds[K].Handled then
        Order:= Order + [K];
    var Shown:= Length(Order);
    if Shown > CapCmds then
      Shown:= CapCmds;
    Sb.AppendLine('digraph sentnothandled {');
    Sb.AppendLine('  rankdir=LR; bgcolor="transparent"; nodesep=0.3;');
    Sb.AppendLine('  node [fontname="Consolas", fontsize=12, shape=box, style="rounded,filled"];');
    Sb.AppendLine(Format('  graph [label="%d sent, %d never handled; sent = names a command and calls a transport unit, handled = the counterpart names it outside the transport units%s", labelloc=b];',
      [Cmds.Count, Never, if Shown < Length(Order) then Format('; %d command(s) not shown (cap %d)', [Length(Order) - Shown, CapCmds]) else '']));
    var Anchored:= 0;
    for var K:= 0 to Shown - 1 do
    begin
      Sb.AppendLine(NodeLine(K, Cmds[Order[K]]));
      if Cmds[Order[K]].Path <> '' then
        Inc(Anchored);
    end;
    if Never = 0 then
      Sb.AppendLine(Format('  none [label="every command sent here is handled by the counterpart", shape=note, fillcolor="white", fontcolor="%s"];', [NOTE_INK]));
    Sb.AppendLine('}');
    var Msgs: TArray<string>;
    Result.Layout:= DotLayout(pArgs.Dot, Sb.ToString, pOutDir, 'sent_not_handled', Msgs);
    Result.LeftCount:= Cmds.Count;
    Result.RightCount:= Never;
    Result.ClickTargets:= Result.Layout.Anchors;
    Result.AllClickable:= Result.Layout.Anchors >= Anchored;
    Result.Fields:= [TMetaField.Int('Sent', Cmds.Count), TMetaField.Int('Handled', Cmds.Count - Never),
      TMetaField.Int('NeverHandled', Never), TMetaField.Int('Shown', Shown),
      TMetaField.Int('Hidden', Length(Order) - Shown), TMetaField.Int('ClickTargets', Result.Layout.Anchors),
      TMetaField.Int('Expected', Anchored), TMetaField.Bool('AllClickable', Result.AllClickable)];
  finally
    Sb.Free;
    Cmds.Free;
    Index.Free;
  end;
end;

initialization
  RegisterChartQuestion(SENT_NOT_HANDLED_ID, Emit);

end.
