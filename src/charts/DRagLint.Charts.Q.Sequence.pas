unit DRagLint.Charts.Q.Sequence;

{ drag-lint 1.56 -- lane CHB-1: the chart question `sequence` (`ask sequence`).
  G-45: the calls of the target routine in source order, as a sequence diagram.
  The id, its menu caption and its two count labels are a row of V156_QUESTIONS in DRagLint.Charts.Question
  (written by W2FRAME; another wording is a request to INT).

  Data (single index, read-only): the refs of kind `call` whose enclosing_symbol_id is the routine, ordered by
  (start_line, start_col, id) -- the refs order of the routine. The receiver of a call is the type that declares
  the call_edges target (the unit for a free routine); a call with no call_edge is drawn to the participant
  "(unresolved)". Participants are the routine's own owner (first column) and every distinct receiver in order of
  first call. The diagram is a dot layout: one column per participant, one rank per call, calls numbered 1..n.
  Cap bounds the calls shown; the rest is disclosed in the graph label. }

interface

const
  /// <summary>The registered question id.</summary>
  SEQUENCE_ID = 'sequence';

implementation

uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.RegularExpressions,
  DRagLint.Charts.Question, DRagLint.Charts.Index, DRagLint.Charts.Text, DRagLint.Charts.Dot;

const
  DEFAULT_CAP = 40;
  UNRESOLVED_NAME = '(unresolved)';
  LINE_INK = '#8A94A6';
  HEAD_FILL = '#E2F1EF';
  NO_PARTICIPANT = -1;

type
  /// <summary>One column of the diagram.</summary>
  TParticipant = record
    Name: string;
    Path: string;
    Line: Integer;
  end;

  /// <summary>One call: callee name, and the participant column it lands in.</summary>
  TCall = record
    Name: string;
    Line: Integer;
    Target: Integer;
  end;

function IndexOfParticipant(const pList: TList<TParticipant>; const pName: string): Integer;
begin
  Result:= NO_PARTICIPANT;
  for var K:= 0 to pList.Count - 1 do
    if SameText(pList[K].Name, pName) then
      Exit(K);
end;

function EnsureParticipant(const pList: TList<TParticipant>; const pName, pPath: string; pLine: Integer): Integer;
begin
  Result:= IndexOfParticipant(pList, pName);
  if Result = NO_PARTICIPANT then
  begin
    var P: TParticipant;
    P.Name:= pName;
    P.Path:= pPath;
    P.Line:= pLine;
    pList.Add(P);
    Result:= pList.Count - 1;
  end;
end;

// The routine's owner: its parent type, else (a free routine) its unit.
function OwnerOf(const pIndex: TChartsIndex; pRoutineId: Integer; const pFallback: string; out pPath: string; out pLine: Integer): string;
begin
  Result:= pFallback;
  pPath:= '';
  pLine:= 0;
  var Rows:= pIndex.Query(
    'SELECT p.name AS name, p.start_line AS start_line, f.path AS path' + sLineBreak +
    '  FROM symbols s JOIN symbols p ON p.id = s.parent_id JOIN files f ON f.id = p.file_id' + sLineBreak +
    ' WHERE s.id = ' + pRoutineId.ToString);
  try
    if Rows.Count > 0 then
    begin
      Result:= Rows[0].S('name');
      pPath:= Rows[0].S('path');
      pLine:= Rows[0].I('start_line');
    end;
  finally
    Rows.Free;
  end;
end;

function Node(const pPrefix: string; pColumn, pStep: Integer): string;
begin
  Result:= Format('%s%d_%d', [pPrefix, pColumn, pStep]);
end;

/// <summary>Answers `sequence` for pArgs.Target: the routine's calls in refs order between their owners.</summary>
/// <param name="pArgs">The question arguments; Target is a routine name (qualified or bare); Cap bounds the calls shown.</param>
/// <param name="pOutDir">Where dot, svg, plain, png and pdf are written.</param>
/// <returns>The chart result: LeftCount = calls shown, RightCount = participants.</returns>
/// <exception cref="EChartsIndex">The name is not in the index, ambiguous, or not a routine.</exception>
/// <exception cref="EChartsQuestion">The routine makes no calls in the index.</exception>
/// <remarks>Read-only. Meta fields: Resolved, Calls, Participants, Unresolved, Hidden, ClickTargets, Expected, AllClickable.</remarks>
function Emit(const pArgs: TQuestionArgs; const pOutDir: string): TChartResult;
var
  Found: Boolean;
begin
  var Index:= TChartsIndex.Create(pArgs.GuardedDb);
  var Parts:= TList<TParticipant>.Create;
  var Calls:= TList<TCall>.Create;
  try
    var Sel:= Index.ResolveMemberSelection(pArgs.Target, ['method', 'procedure', 'function', 'constructor', 'destructor'],
      False, 'name a routine', Found);
    var OwnerPath: string;
    var OwnerLine: Integer;
    var Owner:= OwnerOf(Index, Sel.Id, UnitNameOf(Sel.Path), OwnerPath, OwnerLine);
    EnsureParticipant(Parts, Owner, OwnerPath, OwnerLine);

    var Rows:= Index.Query(
      'SELECT r.id AS id, r.name_text AS name_text, r.start_line AS call_line, p.name AS owner_name,' + sLineBreak +
      '       p.start_line AS owner_line, pf.path AS owner_path, t.id AS tid, tf.path AS tpath, t.start_line AS tline' + sLineBreak +
      '  FROM refs r' + sLineBreak +
      '  LEFT JOIN call_edges ce ON ce.ref_id = r.id' + sLineBreak +
      '  LEFT JOIN symbols t ON t.id = ce.target_symbol_id' + sLineBreak +
      '  LEFT JOIN files tf ON tf.id = t.file_id' + sLineBreak +
      '  LEFT JOIN symbols p ON p.id = t.parent_id' + sLineBreak +
      '  LEFT JOIN files pf ON pf.id = p.file_id' + sLineBreak +
      ' WHERE r.enclosing_symbol_id = ' + Sel.Id.ToString + ' AND r.kind = ''call''' + sLineBreak +
      ' ORDER BY r.start_line, r.start_col, r.id');
    var Hidden:= 0;
    var Unresolved:= 0;
    var CapCalls:= if pArgs.Cap > 0 then pArgs.Cap else DEFAULT_CAP;
    try
      for var R in Rows do
      begin
        if Calls.Count >= CapCalls then
        begin
          Inc(Hidden);
          Continue;
        end;
        var C: TCall;
        C.Name:= R.S('name_text');
        C.Line:= R.I('call_line');
        if R.I('tid') = 0 then
        begin
          Inc(Unresolved);
          C.Target:= EnsureParticipant(Parts, UNRESOLVED_NAME, '', 0);
        end
        else if R.S('owner_name') <> '' then
          C.Target:= EnsureParticipant(Parts, R.S('owner_name'), R.S('owner_path'), R.I('owner_line'))
        else
          C.Target:= EnsureParticipant(Parts, UnitNameOf(R.S('tpath')), R.S('tpath'), R.I('tline'));
        Calls.Add(C);
      end;
    finally
      Rows.Free;
    end;
    if Calls.Count = 0 then
      raise EChartsQuestion.Create(Sel.QName + ' makes no calls in this index');

    var Sb:= TStringBuilder.Create;
    try
      Sb.AppendLine('digraph sequence {');
      Sb.AppendLine('  rankdir=TB; bgcolor="transparent"; nodesep=1.2; ranksep=0.45; newrank=true;');
      Sb.AppendLine('  node [fontname="Consolas", fontsize=13]; edge [fontname="Consolas", fontsize=11];');
      if Hidden > 0 then
        Sb.AppendLine(Format('  graph [label="%d more call(s) not shown (cap %d)", labelloc=b];', [Hidden, CapCalls]));
      Sb.Append('  { rank=same;');
      for var K:= 0 to Parts.Count - 1 do
      begin
        var Url:= '';
        if Parts[K].Path <> '' then
          Url:= Format(', URL="%s"', [RowHref(Parts[K].Path, Parts[K].Line)]);
        Sb.Append(Format(' %s [shape=box, style="rounded,filled", fillcolor="%s", label="%s"%s];',
          [Node('h', K, 0), HEAD_FILL, XmlText(Parts[K].Name), Url]));
      end;
      Sb.AppendLine(' }');
      for var K:= 1 to Parts.Count - 1 do
        Sb.AppendLine(Format('  %s -> %s [style=invis];', [Node('h', K - 1, 0), Node('h', K, 0)]));
      for var I:= 1 to Calls.Count do
      begin
        Sb.Append('  { rank=same;');
        for var K:= 0 to Parts.Count - 1 do
          Sb.Append(Format(' %s [shape=point, width=0.05, label=""];', [Node('s', K, I)]));
        Sb.AppendLine(' }');
        for var K:= 1 to Parts.Count - 1 do
          Sb.AppendLine(Format('  %s -> %s [style=invis];', [Node('s', K - 1, I), Node('s', K, I)]));
      end;
      for var K:= 0 to Parts.Count - 1 do
        for var I:= 1 to Calls.Count do
          Sb.AppendLine(Format('  %s -> %s [style=dashed, arrowhead=none, color="%s", weight=10];',
            [Node(if I = 1 then 'h' else 's', K, if I = 1 then 0 else I - 1), Node('s', K, I), LINE_INK]));
      for var I:= 1 to Calls.Count do
      begin
        var C:= Calls[I - 1];
        Sb.AppendLine(Format('  %s -> %s [constraint=false, label="%d: %s", URL="%s"];',
          [Node('s', 0, I), Node('s', C.Target, I), I, XmlText(C.Name), RowHref(Sel.Path, C.Line)]));
      end;
      Sb.AppendLine('}');
      var Msgs: TArray<string>;
      var Base:= TRegEx.Replace(Sel.QName, '[^A-Za-z0-9]', '_') + '_sequence';
      Result.Layout:= DotLayout(pArgs.Dot, Sb.ToString, pOutDir, Base, Msgs);
    finally
      Sb.Free;
    end;

    var Expected:= Calls.Count;
    for var P in Parts do
      if P.Path <> '' then
        Inc(Expected);
    Result.LeftCount:= Calls.Count;
    Result.RightCount:= Parts.Count;
    Result.ClickTargets:= Result.Layout.Anchors;
    Result.AllClickable:= Result.Layout.Anchors >= Expected;
    Result.Fields:= [TMetaField.Str('Resolved', Sel.QName), TMetaField.Int('Calls', Calls.Count),
      TMetaField.Int('Participants', Parts.Count), TMetaField.Int('Unresolved', Unresolved),
      TMetaField.Int('Hidden', Hidden), TMetaField.Int('ClickTargets', Result.Layout.Anchors),
      TMetaField.Int('Expected', Expected), TMetaField.Bool('AllClickable', Result.AllClickable)];
  finally
    Calls.Free;
    Parts.Free;
    Index.Free;
  end;
end;

initialization
  RegisterChartQuestion(SEQUENCE_ID, Emit);

end.
