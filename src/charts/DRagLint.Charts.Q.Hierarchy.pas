unit DRagLint.Charts.Q.Hierarchy;

(* The `hierarchy` question in-process: a port of charts\src\Emit-Hierarchy.ps1
  (spec s11; the PS output is the reference, P3). The ancestors and descendants of ONE
  type. Heritage is a DAG, not a tree, so the chart is two flat clusters around the focus:
  what the type inherits from above, what inherits from it below (rankdir=TB, the one
  chart whose axis carries meaning); every arrow means INHERITS FROM and points up.

  Data route (F7): the PS spawns `query ancestors --name <bare>` and `query descendants
  --of <bare>`; both are mirrored in-process over a read-only TSQLiteSymbolStore. The
  ancestors start is the FIRST symbol of FindSymbolsByExactName whose kind is class,
  interface or record (no match: an empty list); the list is GetTransitiveAncestors in the
  verb's order. The descendants are FindDescendantNames through a sorted, duplicate-
  ignoring, case-blind string list, then sorted again with CompareGroupKeys (Sort-Object).
  The first-match rule is the collision mechanism the PS header describes (IDataService
  returns itself), so every row naming the focus is dropped and counted as SelfRefs.
  SINGLE-DB on purpose: an RTL parent is drawn as a note row (outside this project's
  closure), never looked up in the library index.

  Selection (F8): ResolveMemberSelection with AllowMissing. A missing focus is NOT refused
  (TInterfacedObject: nothing declares it, 145 types extend it) - it is drawn un-anchored.
  Refusals (F10): a name that is neither declared nor in any heritage; an ambiguous name
  (the text comes from ResolveMemberSelection). A declared type with no heritage either way
  is the focus alone.

  Rows (F8, F9): ONE batched name lookup for the shown rows; one hit is an anchored row,
  several a note row (ambiguous, not linked), none a note row (not a type in this index).

  Not ported: the PS GREY palette (declared, used nowhere), the Write-Host NOTE lines.

  PS traps closed: `-eq`, hashtable keys and `Sort-Object -Unique` are case-insensitive
  (SameText, TIStringComparer.Ordinal); `Sort-Object` over strings is CompareGroupKeys
  order; Write-Host is not output. *)

interface

const
  /// <summary>The registered question id.</summary>
  HIERARCHY_ID = 'hierarchy';

implementation

uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.Generics.Defaults,
  System.RegularExpressions, DRagLint.Core.Model, DRagLint.Core.Interfaces, DRagLint.Storage.SQLite,
  DRagLint.Charts.Question, DRagLint.Charts.Index, DRagLint.Charts.Text, DRagLint.Charts.Dot,
  DRagLint.Charts.PsSort;

const
  ANC_BORDER = '#3B5BDB';
  ANC_FILL = '#EDF2FF';
  ANC_HDR = '#3B5BDB';
  DESC_BORDER = '#B45309';
  DESC_FILL = '#FEF6EC';
  DESC_HDR = '#B45309';
  FOCUS_BORDER = '#0F766E';
  FOCUS_FILL = '#E2F1EF';
  FOCUS_HDR = '#0F766E';
  ROW_INK = '#1F2933';
  LINE_INK = '#8A94A6';
  FOCUS_INK = '#0B3F39';
  FONT_MONO = 'Consolas';
  FONT_SANS = 'Segoe UI';
  NOT_HERE = '(not in this index)';

type
  TLookup = TObjectDictionary<string, TList<TIndexRow>>;

// mirror of DRagLint.CLI.pas query ancestors: the first class/interface/record named pBare, its transitive ancestors
function AncestorsOf(const pStore: ISymbolStore; const pBare: string): TArray<TTypeAncestor>;
begin
  Result:= [];
  for var S in pStore.FindSymbolsByExactName(pBare) do
    if S.Kind in [skClass, skInterface, skRecord] then
      Exit(pStore.GetTransitiveAncestors(S.Id));
end;

// mirror of DRagLint.CLI.pas query descendants: sorted, duplicate-ignoring, case-blind names
function DescendantsOf(const pStore: ISymbolStore; const pBare: string): TArray<string>;
begin
  var Names:= TStringList.Create;
  try
    Names.CaseSensitive:= False;
    Names.Sorted:= True;
    Names.Duplicates:= dupIgnore;
    for var Nm in pStore.FindDescendantNames(pBare) do
      Names.Add(Nm);
    Result:= Names.ToStringArray;
  finally
    Names.Free;
  end;
end;

/// <summary>Turns a BARE type name into a row: one declaration anchors it, several or none leave a note row.</summary>
/// <param name="pLookup">Bare name to the declaration rows found for it (case-blind keys).</param>
/// <param name="pName">The bare type name.</param>
/// <param name="pNote">The dimmed suffix of an anchored row.</param>
/// <param name="pCollisions">Incremented when several declarations share the name.</param>
/// <param name="pUnlocatable">Incremented when no declaration is found.</param>
/// <returns>The row; Href is '' for a note row.</returns>
function NewTypeRow(const pLookup: TLookup; const pName, pNote: string; var pCollisions, pUnlocatable: Integer): TDotRow;
begin
  var Hits: TList<TIndexRow>:= nil;
  if not pLookup.TryGetValue(pName, Hits) then
    Hits:= nil;
  if (Hits <> nil) and (Hits.Count = 1) then
  begin
    var H:= Hits[0];
    Exit(TDotRow.Anchored(pName, H.I('start_line'), RowHref(H.S('path'), H.I('start_line')),
      Format('%s (%s)  --  %s:%d', [H.S('qualified_name'), H.S('kind'), FileNameOf(H.S('path')), H.I('start_line')]), pNote));
  end;
  if (Hits <> nil) and (Hits.Count > 1) then
  begin
    Inc(pCollisions);
    Exit(NoteRow(Format('%s  (%d types share this name -- ambiguous, not linked)', [pName, Hits.Count])));
  end;
  Inc(pUnlocatable);
  Result:= NoteRow(pName + '  (not a type in this index)');
end;

function AnchoredCount(const pRows: TArray<TDotRow>): Integer;
begin
  Result:= 0;
  for var R in pRows do
    if R.Href <> '' then
      Inc(Result);
end;

/// <summary>Answers `hierarchy` for pArgs.Target: the type's ancestors above it and descendants below it.</summary>
/// <param name="pArgs">The question arguments; Target is a type name (qualified or bare), Cap bounds each side.</param>
/// <param name="pOutDir">Where dot, svg, plain, png and pdf are written.</param>
/// <returns>The chart result; a missing focus with descendants is drawn, not refused.</returns>
/// <exception cref="EChartsQuestion">The name is neither declared nor in any heritage.</exception>
/// <exception cref="EChartsIndex">The name is ambiguous (the text comes from ResolveMemberSelection).</exception>
/// <remarks>Opens a read-only TSQLiteSymbolStore beside the TChartsIndex (two read-only handles on one file).</remarks>
function Emit(const pArgs: TQuestionArgs; const pOutDir: string): TChartResult;
var
  Found: Boolean;
begin
  var Store: ISymbolStore:= TSQLiteSymbolStore.Create(pArgs.GuardedDb, True);
  var Index:= TChartsIndex.Create(pArgs.GuardedDb);
  var Lookup:= TLookup.Create([doOwnsValues], TIStringComparer.Ordinal);
  var LookupRows: TObjectList<TIndexRow>:= nil;
  try
    { ---- 1. the focus, ambiguity refused, a missing focus allowed ---- }
    var Sel:= Index.ResolveMemberSelection(pArgs.Target, ['class', 'interface', 'record', 'type'], True,
      RESOLVE_HINT_DEFAULT, Found);
    var Bare:= if Found then Sel.Name else pArgs.Target.Substring(pArgs.Target.LastIndexOf('.') + 1);
    var UnitName:= if Found then UnitNameOf(Sel.Path) else NOT_HERE;

    { ---- 2. the two verbs, then the self-reference filter ---- }
    var SelfRefs:= 0;
    var Anc: TArray<TTypeAncestor>:= [];
    for var A in AncestorsOf(Store, Bare) do
      if SameText(A.Name, Bare) then
        Inc(SelfRefs)
      else
        Anc:= Anc + [A];
    var Desc: TArray<string>:= [];
    for var D in DescendantsOf(Store, Bare) do
      if SameText(D, Bare) then
        Inc(SelfRefs)
      else
        Desc:= Desc + [D];
    if (not Found) and (Length(Anc) = 0) and (Length(Desc) = 0) then
      raise EChartsQuestion.Create(pArgs.Target + ' is not in this index, and nothing in it inherits from or is inherited by that name');
    var UnresolvedAnc:= 0;
    for var A in Anc do
      if not A.Resolved then
        Inc(UnresolvedAnc);

    { ---- 3. rank and cap ---- }
    TPsSort<string>.Sort(Desc, CompareGroupKeys);
    var ATop:= TRanked<TTypeAncestor>.TopRanked(Anc, pArgs.Cap, nil);
    var DTop:= TRanked<string>.TopRanked(Desc, pArgs.Cap, nil);

    { ---- 4. ONE batched lookup for every name that will be drawn ---- }
    var Seen:= TDictionary<string, Boolean>.Create(TIStringComparer.Ordinal);
    try
      var Wanted: TArray<string>:= [];
      for var A in ATop.Shown do
        if A.Resolved and not Seen.ContainsKey(A.Name) then
        begin
          Seen.Add(A.Name, True);
          Wanted:= Wanted + [A.Name];
        end;
      for var D in DTop.Shown do
        if not Seen.ContainsKey(D) then
        begin
          Seen.Add(D, True);
          Wanted:= Wanted + [D];
        end;
      if Length(Wanted) > 0 then
      begin
        LookupRows:= Index.Query(
          'SELECT s.name AS nm, s.qualified_name AS qualified_name, s.kind AS kind,' + sLineBreak +
          '       s.start_line AS start_line, s.end_line AS end_line,' + sLineBreak +
          '       s.generic_params AS generic_params, f.path AS path' + sLineBreak +
          '  FROM symbols s JOIN files f ON f.id = s.file_id' + sLineBreak +
          ' WHERE s.name IN (' + TChartsIndex.SqlInList(Wanted) + ')' + sLineBreak +
          '   AND s.kind IN (''class'',''interface'',''record'',''type'')' + sLineBreak +
          ' ORDER BY s.name, s.qualified_name');
        var Decls:= TChartsIndex.SelectDeclarationRows(LookupRows);
        try
          for var R in Decls do
          begin
            var Hits: TList<TIndexRow>;
            if not Lookup.TryGetValue(R.S('nm'), Hits) then
            begin
              Hits:= TList<TIndexRow>.Create;
              Lookup.Add(R.S('nm'), Hits);
            end;
            Hits.Add(R);
          end;
        finally
          Decls.Free;
        end;
      end;
    finally
      Seen.Free;
    end;

    { ---- 5. rows ---- }
    var Collisions:= 0;
    var Unlocatable:= 0;
    var AncRows: TArray<TDotRow>:= [];
    for var A in ATop.Shown do
      if not A.Resolved then
        AncRows:= AncRows + [NoteRow(A.Name + '  (outside this project''s closure)')]
      else
        AncRows:= AncRows + [NewTypeRow(Lookup, A.Name, A.Kind, Collisions, Unlocatable)];
    var Dt:= DisclosureText(ATop.HiddenRows, 0, 'ancestors');
    if Dt <> '' then
      AncRows:= AncRows + [NoteRow(Dt)];
    var DescRows: TArray<TDotRow>:= [];
    for var D in DTop.Shown do
      DescRows:= DescRows + [NewTypeRow(Lookup, D, '', Collisions, Unlocatable)];
    Dt:= DisclosureText(DTop.HiddenRows, 0, 'descendants');
    if Dt <> '' then
      DescRows:= DescRows + [NoteRow(Dt)];  // dl:ok duplicate-code@a849 -- REVIEWED 2026-10-16: the row-list tail mirrors the script own repetition between the ancestors and descendants blocks (decision F9, precedent bdd013e3)

    { ---- 6. dot ---- }
    var Sb:= TStringBuilder.Create;
    try
      Sb.AppendLine('digraph hierarchy {');
      Sb.AppendLine('  rankdir=TB; bgcolor="transparent"; compound=true;');
      Sb.AppendLine('  nodesep=0.35; ranksep=1.1; splines=spline;');
      Sb.AppendLine(Format('  graph [fontname="%s"];', [FONT_SANS]));
      Sb.AppendLine(Format('  node  [shape=plaintext, fontname="%s", fontsize=14];', [FONT_MONO]));
      Sb.AppendLine(Format('  edge  [fontname="%s", fontsize=11, color="%s", penwidth=1.5, arrowsize=0.8];', [FONT_MONO, LINE_INK]));
      Sb.AppendLine('');

      var AncPorts: TArray<string>:= [];
      if Length(AncRows) > 0 then
      begin
        var Style:= TClusterStyle.Make(ANC_BORDER, ANC_FILL, ANC_HDR);
        Style.RowInk:= ROW_INK;
        Style.LineInk:= LINE_INK;
        Style.FontSans:= FONT_SANS;
        AncPorts:= AddRowCluster(Sb, 'cluster_ancestors', 'na', 'inherits from', Format('%d direct', [ATop.Total]), AncRows, Style);
      end;

      Sb.AppendLine('  subgraph cluster_focus {');
      Sb.AppendLine(Format('    style="rounded,filled"; color="%s"; fillcolor="%s"; penwidth=3;', [FOCUS_BORDER, FOCUS_FILL]));
      Sb.AppendLine('    label=""; margin=12;');
      var FKind:= if Found then Sel.Kind else 'not declared here';
      var FTbl:= TStringBuilder.Create;
      try
        FTbl.Append('<TABLE BORDER="0" CELLBORDER="0" CELLSPACING="3" CELLPADDING="7">');
        FTbl.Append(Format('<TR><TD ALIGN="LEFT" BGCOLOR="%s"><FONT COLOR="#FFFFFF" FACE="%s" POINT-SIZE="14"><B> %s &#183; %s </B></FONT></TD></TR>',
          [FOCUS_HDR, FONT_SANS, XmlText(UnitName), XmlText(FKind)]));
        if Found then
          FTbl.Append(Format('<TR><TD HREF="%s" TITLE="%s"><FONT COLOR="%s" POINT-SIZE="18"><B>%s</B></FONT></TD></TR>',
            [RowHref(Sel.Path, Sel.FocusLine),
             XmlText(Format('%s  --  %s:%d', [Sel.QName, FileNameOf(Sel.Path), Sel.FocusLine])),
             FOCUS_INK, XmlText(Bare)]))
        else
        begin
          FTbl.Append(Format('<TR><TD><FONT COLOR="%s" POINT-SIZE="18"><B>%s</B></FONT></TD></TR>', [FOCUS_INK, XmlText(Bare)]));
          AddDisclosureRow(FTbl, 'outside this project''s closure -- declared in the platform library index', LINE_INK);
        end;
        if Length(Anc) = 0 then
          AddDisclosureRow(FTbl, 'no declared ancestors', LINE_INK);
        if Length(Desc) = 0 then
          AddDisclosureRow(FTbl, 'nothing in this index inherits from it', LINE_INK);
        if SelfRefs > 0 then
          AddDisclosureRow(FTbl, Format('%d self-reference(s) dropped (name collision)', [SelfRefs]), LINE_INK);
        FTbl.Append('</TABLE>');
        Sb.AppendLine(Format('    focus [label=<%s>];', [FTbl.ToString]));
      finally
        FTbl.Free;
      end;
      Sb.AppendLine('  }');

      var DescPorts: TArray<string>:= [];
      if Length(DescRows) > 0 then
      begin
        var Style:= TClusterStyle.Make(DESC_BORDER, DESC_FILL, DESC_HDR);
        Style.RowInk:= ROW_INK;
        Style.LineInk:= LINE_INK;
        Style.FontSans:= FONT_SANS;
        DescPorts:= AddRowCluster(Sb, 'cluster_descendants', 'nd', 'inherited by',
          Format('%d type%s', [DTop.Total, if DTop.Total <> 1 then 's' else '']), DescRows, Style);
      end;

      Sb.AppendLine('');
      for var I:= 0 to High(AncRows) do
        if AncRows[I].Href <> '' then
          Sb.AppendLine(Format('  focus -> %s [color="%s"];', [AncPorts[I], ANC_BORDER]));
      for var I:= 0 to High(DescRows) do
        if DescRows[I].Href <> '' then
          Sb.AppendLine(Format('  %s -> focus [color="%s"];', [DescPorts[I], DESC_BORDER]));
      Sb.AppendLine('}');

      { ---- 7. lay out ---- }
      var Msgs: TArray<string>;
      var Base:= TRegEx.Replace(if Found then Sel.QName else pArgs.Target, '[^A-Za-z0-9]', '_') + '_hierarchy';
      Result.Layout:= DotLayout(pArgs.Dot, Sb.ToString, pOutDir, Base, Msgs);
    finally
      Sb.Free;
    end;

    var Anchored:= AnchoredCount(AncRows) + AnchoredCount(DescRows);
    var Expected:= Anchored + (if Found then 1 else 0);
    Result.LeftCount:= Length(Anc);
    Result.RightCount:= Length(Desc);
    Result.ClickTargets:= Result.Layout.Anchors;
    Result.AllClickable:= Result.Layout.Anchors >= Expected;
    var FResolved:= TMetaField.Null('Resolved');
    var FKindField:= TMetaField.Null('Kind');
    if Found then
    begin
      FResolved:= TMetaField.Str('Resolved', Sel.QName);
      FKindField:= TMetaField.Str('Kind', Sel.Kind);
    end;
    Result.Fields:= [FResolved, FKindField,
      TMetaField.Bool('FocusDeclared', Found), TMetaField.Int('Ancestors', Length(Anc)),
      TMetaField.Int('UnresolvedAnc', UnresolvedAnc), TMetaField.Int('Descendants', Length(Desc)),
      TMetaField.Int('ShownAncestors', Length(ATop.Shown)), TMetaField.Int('ShownDescendants', Length(DTop.Shown)),
      TMetaField.Int('HiddenAncestors', ATop.HiddenRows), TMetaField.Int('HiddenDescendants', DTop.HiddenRows),
      TMetaField.Int('Collisions', Collisions), TMetaField.Int('Unlocatable', Unlocatable),
      TMetaField.Int('SelfRefs', SelfRefs), TMetaField.Int('ClickTargets', Result.Layout.Anchors),
      TMetaField.Int('Expected', Expected), TMetaField.Bool('AllClickable', Result.AllClickable)];
  finally
    Lookup.Free;
    LookupRows.Free;
    Index.Free;
  end;
end;

initialization
  RegisterChartQuestion(HIERARCHY_ID, Emit);

end.
