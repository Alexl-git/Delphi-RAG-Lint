unit DRagLint.Charts.Q.Effects;

(* The `effects` question in-process: a port of charts\src\Emit-Effects.ps1 (spec s11; the
  PS output is the reference, P3). What a method does to state outside its locals, from
  symbol_facts: effect_free DECIDES the outcome (pure / effects / not analysed -- a NULL
  summary is overwhelmingly the PURE case), the summary tokens fill in the detail (g, h,
  s, p<k> zero-based, and '?' -- an admission, drawn dashed apart). A p<k> is named by
  ORDINAL from symbols.signature (grouped names are separate ordinals), never from
  mutates_params. The witness is shown once, as the first recorded one. Engine D12 (a
  function's own-name Result assignment scored as a global write) is detected from the
  witness and moved to a dashed disclosure.

  The PS -FactOverride test hook is not ported: New-DiagramArtifact never passes it, so a
  bundled chart's TestChart is always false. The D12 branch is reachable only from such
  injected facts (no real row since extractor 1.19); its detector is TestD12OwnNameWrite.

  PS traps closed: String.Trim is Char.IsWhiteSpace (PsTrim); `-split ','` keeps empty
  tokens, which are then skipped; `switch -Regex` matches the lower-cased token; a NULL
  effect_free prints 'NULL'; the `-match 'unk|na'` dashed-edge test is applied to the
  node id literally, as the PS does. *)

interface

const
  /// <summary>The registered question id.</summary>
  EFFECTS_ID = 'effects';

implementation

uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.RegularExpressions,
  DRagLint.Charts.Question, DRagLint.Charts.Index, DRagLint.Charts.Text, DRagLint.Charts.Dot,
  DRagLint.Charts.Source, DRagLint.Charts.Checks;

const
  PURE_BORDER = '#0F766E';
  PURE_FILL = '#E2F1EF';
  PURE_HDR = '#0F766E';
  FX_BORDER = '#B45309';
  FX_FILL = '#FEF6EC';
  FX_HDR = '#B45309';
  UNK_BORDER = '#6B7280';
  UNK_FILL = '#F3F4F6';
  UNK_HDR = '#6B7280';
  NA_BORDER = '#9AA3AF';
  NA_FILL = '#F3F4F6';
  NA_HDR = '#6B7280';
  FOCUS_BORDER = '#3B5BDB';
  FOCUS_FILL = '#EDF2FF';
  FOCUS_HDR = '#3B5BDB';
  ROW_INK = '#1F2933';
  LINE_INK = '#8A94A6';
  FONT_MONO = 'Consolas';
  FONT_SANS = 'Segoe UI';
  DASHED_STYLE = 'rounded,filled,dashed';
  OUTCOME_NA = 'not-analysed';
  OUTCOME_PURE = 'pure';
  OUTCOME_EFFECTS = 'effects';
  NULL_TEXT = 'NULL';
  { the point size of the signature line in the focus box }
  SIGNATURE_POINT_SIZE = 11;
  HINT = 'effects selects a METHOD -- ask class-surface for a type';

type
  TEffectRow = record
    Kind, Text: string;
    Unknown: Boolean;
  end;

  TLink = record
    Nid, Border: string;
    Flagged: Boolean;
  end;

{ Get-ParamNames: parameter names by ORDINAL; a grouped declaration is several ordinals }
function ParamNames(const pSignature: string): TArray<string>;
begin
  Result:= [];
  if PsTrim(pSignature) = '' then
    Exit;
  var Open:= Pos('(', pSignature);
  if Open = 0 then
    Exit;
  var Depth:= 0;
  var EndAt:= 0;
  for var I:= Open to Length(pSignature) do
  begin
    var Ch:= pSignature[I];
    if CharInSet(Ch, ['(', '[']) then
      Inc(Depth)
    else if CharInSet(Ch, [')', ']']) then
    begin
      Dec(Depth);
      if Depth = 0 then
      begin
        EndAt:= I;
        Break;
      end;
    end;
  end;
  if EndAt = 0 then
    Exit;
  var Inner:= Copy(pSignature, Open + 1, EndAt - Open - 1);
  if PsTrim(Inner) = '' then
    Exit;
  { split on ';' at depth 0 }
  var Groups: TArray<string>:= [];
  var Buf:= TStringBuilder.Create;
  try
    Depth:= 0;
    for var Ch in Inner do
    begin
      if CharInSet(Ch, ['(', '[']) then
        Inc(Depth)
      else if CharInSet(Ch, [')', ']']) then
        Dec(Depth);
      if (Ch = ';') and (Depth = 0) then
      begin
        Groups:= Groups + [Buf.ToString];
        Buf.Clear;
        Continue;
      end;
      Buf.Append(Ch);
    end;
    Groups:= Groups + [Buf.ToString];
  finally
    Buf.Free;
  end;
  for var G in Groups do
  begin
    var Decl:= G;
    var Colon:= Pos(':', Decl);
    if Colon > 0 then
      Decl:= Copy(Decl, 1, Colon - 1);
    Decl:= PsTrim(Decl);
    if Decl = '' then
      Continue;
    Decl:= TRegEx.Replace(Decl, '^(?i)\s*(var|out|const|constref)\s+', '');
    for var N in Decl.Split([',']) do
      if PsTrim(N) <> '' then
        Result:= Result + [PsTrim(N)];
  end;
end;

{ Decode, mirroring TEffectSummary.Decode: any unrecognised token folds to '?' }
function DecodeEffects(const pSummary: string; const pParams: TArray<string>; out pUnnamed: Integer): TArray<TEffectRow>;
begin
  Result:= [];
  pUnnamed:= 0;
  if pSummary = '' then
    Exit;
  for var Raw in pSummary.Split([',']) do
  begin
    var Tok:= PsTrim(Raw).ToLowerInvariant;
    if Tok = '' then
      Continue;
    var E:= Default(TEffectRow);
    if Tok = 'g' then
    begin
      E.Kind:= 'g';
      E.Text:= 'writes global state';
    end
    else if Tok = 'h' then
    begin
      E.Kind:= 'h';
      E.Text:= 'frees or resizes heap storage';
    end
    else if Tok = 's' then
    begin
      E.Kind:= 's';
      E.Text:= 'writes fields of its own instance';
    end
    else if TRegEx.IsMatch(Tok, '^p\d+$') then
    begin
      var K:= StrToInt(Copy(Tok, 2, MaxInt));
      E.Kind:= 'p';
      if K < Length(pParams) then
        E.Text:= Format('writes through parameter #%d (%s)', [K, pParams[K]])
      else
      begin
        Inc(pUnnamed);
        var Why:= if Length(pParams) = 0 then 'no parameter list recorded for this symbol'
          else Format('the recorded signature lists only %d parameter(s)', [Length(pParams)]);
        E.Text:= Format('writes through parameter #%d (not named: %s)', [K, Why]);
      end;
    end
    else
    begin
      E.Kind:= '?';
      E.Text:= 'something this build could not classify';
      E.Unknown:= True;
    end;
    Result:= Result + [E];
  end;
end;

function Emit(const pArgs: TQuestionArgs; const pOutDir: string): TChartResult;
var
  Found: Boolean;
  Unnamed: Integer;
  Links: TArray<TLink>;
begin
  var Index:= TChartsIndex.Create(pArgs.GuardedDb);
  var Sb:= TStringBuilder.Create;
  try
    { ---- 1. resolve ---- }
    var Sel:= Index.ResolveMemberSelection(pArgs.Target, ['method', 'function', 'procedure', 'constructor', 'destructor'], False, HINT, Found);
    var Ef, Es, Ew, Mp, Sig: string;
    var Fact:= Index.Query(
      'SELECT sf.effect_free AS ef, sf.effect_summary AS es, sf.effect_witness AS ew,' + sLineBreak +
      '       sf.mutates_params AS mp, s.signature AS sig' + sLineBreak +
      '  FROM symbol_facts sf JOIN symbols s ON s.id = sf.symbol_id' + sLineBreak +
      Format(' WHERE sf.symbol_id = %d', [Sel.Id]));
    try
      if Fact.Count = 0 then
        raise EChartsQuestion.CreateFmt('%s has no symbol_facts row at all -- the purity stage never saw it. ' +
          'That is a different answer from "not analysed"; report it rather than reading it as pure.', [Sel.QName]);
      Ef:= Fact[0].S('ef');   { '' only for NULL: the column holds 0 or 1 }
      Es:= Fact[0].S('es');
      Ew:= Fact[0].S('ew');
      Mp:= Fact[0].S('mp');
      Sig:= Fact[0].S('sig');
    finally
      Fact.Free;
    end;

    { ---- 2-3. parameter names by ORDINAL, then decode ---- }
    var Params:= ParamNames(Sig);
    var Effects:= DecodeEffects(Es, Params, Unnamed);

    { ---- 4. the three outcomes ---- }
    var Outcome:= if Ef = '' then OUTCOME_NA else if StrToIntDef(Ef, 0) = 1 then OUTCOME_PURE else OUTCOME_EFFECTS;
    var EfText:= if Ef = '' then NULL_TEXT else Ef;
    var Kinds: TArray<string>:= [];
    for var E in Effects do
      Kinds:= Kinds + [E.Kind];
    var D12:= TestD12OwnNameWrite(Sel.Name, Ew, Kinds);
    var Known: TArray<TEffectRow>:= [];
    var Unk: TArray<TEffectRow>:= [];
    for var E in Effects do
      if D12 and SameText(E.Kind, 'g') then
        Continue
      else if E.Unknown then
        Unk:= Unk + [E]
      else
        Known:= Known + [E];

    { ---- 5. dot ---- }
    Sb.AppendLine('digraph effects {');
    Sb.AppendLine('  rankdir=LR; bgcolor="transparent"; compound=true;');
    Sb.AppendLine('  nodesep=0.3; ranksep=1.2; splines=spline;');
    Sb.AppendLine(Format('  graph [fontname="%s"];', [FONT_SANS]));
    Sb.AppendLine(Format('  node  [shape=plaintext, fontname="%s", fontsize=14];', [FONT_MONO]));
    Sb.AppendLine(Format('  edge  [fontname="%s", fontsize=11, color="%s", penwidth=1.4, arrowsize=0.7];', [FONT_MONO, LINE_INK]));
    Sb.AppendLine('');

    var NodeId:= 1;
    var Clusters:= 1;
    var Anchored:= 1;
    var FNid:= 'n' + IntToStr(NodeId);
    var FTbl:= TStringBuilder.Create;
    try
      FTbl.Append('<TABLE BORDER="0" CELLBORDER="0" CELLSPACING="3" CELLPADDING="5">');
      FTbl.Append(Format('<TR><TD ALIGN="LEFT" BGCOLOR="%s"><FONT COLOR="#FFFFFF" FACE="%s" POINT-SIZE="14"><B> %s </B></FONT></TD></TR>',
        [FOCUS_HDR, FONT_SANS, XmlText(Sel.Name)]));
      FTbl.Append(Format('<TR><TD PORT="p1" ALIGN="LEFT" HREF="%s" TITLE="%s">', [RowHref(Sel.Path, Sel.FocusLine), XmlText(Sel.QName)]));
      FTbl.Append(Format('<FONT COLOR="%s">%s</FONT>', [ROW_INK, XmlText(UnitNameOf(Sel.Path))]));
      FTbl.Append(Format('  <FONT COLOR="%s" POINT-SIZE="12">:%d</FONT></TD></TR>', [LINE_INK, Sel.FocusLine]));
      if Sig <> '' then
        AddDisclosureRow(FTbl, Sig, LINE_INK, SIGNATURE_POINT_SIZE);
      AddDisclosureRow(FTbl, Format('effect_free = %s  &#183;  stored summary = %s', [EfText, if Es <> '' then Es else '(empty)']), LINE_INK);
      if Ew <> '' then
        AddDisclosureRow(FTbl, 'first recorded witness: ' + Ew, LINE_INK);
      if Mp <> '' then
        AddDisclosureRow(FTbl, 'declared var/out parameters mutated: ' + Mp, LINE_INK);
      if Unnamed > 0 then
        AddDisclosureRow(FTbl, Format('%d parameter effect(s) could not be named from the signature', [Unnamed]), LINE_INK);
      FTbl.Append('</TABLE>');
      Sb.AppendLine(Format('  subgraph cluster_focus_%d {', [NodeId]));
      Sb.AppendLine(Format('    style="rounded,filled"; color="%s"; fillcolor="%s"; penwidth=2;', [FOCUS_BORDER, FOCUS_FILL]));
      Sb.AppendLine('    label=""; margin=10;');
      Sb.AppendLine(Format('    %s [label=<%s>];', [FNid, FTbl.ToString]));
      Sb.AppendLine('  }');
    finally
      FTbl.Free;
    end;

    Links:= [];
    var AddCluster:= procedure(const pCid, pTitle, pSub: string; const pRows: TArray<TDotRow>; const pBorder, pFill, pHdr: string;
      pDashed, pFlagged: Boolean)
      begin
        Inc(NodeId);
        Inc(Clusters);
        var L:= Default(TLink);
        L.Nid:= 'n' + IntToStr(NodeId);
        L.Border:= pBorder;
        L.Flagged:= pFlagged;
        var Style:= TClusterStyle.Make(pBorder, pFill, pHdr);
        Style.RowInk:= ROW_INK;
        Style.LineInk:= LINE_INK;
        Style.FontSans:= FONT_SANS;
        if pDashed then
          Style.Style:= DASHED_STYLE;
        AddRowCluster(Sb, pCid + IntToStr(NodeId), L.Nid, pTitle, pSub, pRows, Style);
        Links:= Links + [L];
      end;

    if Outcome = OUTCOME_PURE then
      AddCluster('cluster_pure_', 'pure', 'no effects recorded',
        [NoteRow('effect_free = 1: this routine writes no global, no field, no parameter'),
         NoteRow('the stored summary is empty, which is how the engine encodes pure')], PURE_BORDER, PURE_FILL, PURE_HDR, False, False);
    if Outcome = OUTCOME_NA then
      AddCluster('cluster_na_', 'not analysed', 'effect_free is NULL',
        [NoteRow('the purity stage recorded no verdict for this routine'),
         NoteRow('this is NOT the same as pure -- nothing is claimed either way')], NA_BORDER, NA_FILL, NA_HDR, True, False);
    if Length(Known) > 0 then
    begin
      var Rows: TArray<TDotRow>:= [];
      for var E in Known do
        Rows:= Rows + [NoteRow(E.Text)];
      AddCluster('cluster_fx_', 'effects', Format('%d recorded', [Length(Known)]), Rows, FX_BORDER, FX_FILL, FX_HDR, False, False);
    end;
    if D12 then
      AddCluster('cluster_d12_', 'engine D12', 'global write NOT shown',
        [NoteRow(Format('the stored g''s witness is this routine''s OWN NAME: ''%s''', [Ew])),
         NoteRow(Format('that is a Result assignment (%s := ...), which this engine build scores as a global write', [Sel.Name])),
         NoteRow('no other global write is visible in the witness (it names only the first blocker)')],
        UNK_BORDER, UNK_FILL, UNK_HDR, True, True);
    if Length(Unk) > 0 then
      AddCluster('cluster_unk_', 'unclassified', Format('%d token', [Length(Unk)]),
        [NoteRow('this build could not classify part of this routine'),
         NoteRow('the effect list above is therefore INCOMPLETE, not final')], UNK_BORDER, UNK_FILL, UNK_HDR, True, False);

    Sb.AppendLine('');
    for var L in Links do
    begin
      var Dashed:= if L.Flagged or TRegEx.IsMatch(L.Nid, 'unk|na', [roIgnoreCase]) then ', style=dashed' else '';
      Sb.AppendLine(Format('  %s:p1 -> %s [color="%s"%s];', [FNid, L.Nid, L.Border, Dashed]));
    end;
    Sb.AppendLine('}');

    { ---- 6. lay out ---- }
    var Msgs: TArray<string>;
    Result.Layout:= DotLayout(pArgs.Dot, Sb.ToString, pOutDir, 'effects_' + TRegEx.Replace(Sel.QName, '[^A-Za-z0-9]', '_'), Msgs);
    Result.LeftCount:= Length(Known);
    Result.RightCount:= Length(Unk);
    Result.ClickTargets:= Result.Layout.Anchors;
    Result.AllClickable:= Result.Layout.Anchors >= Anchored;
    Result.Fields:= [TMetaField.Bool('TestChart', False), TMetaField.Str('Qname', Sel.QName), TMetaField.Str('Outcome', Outcome),
      TMetaField.Str('EffectFree', EfText), TMetaField.Str('Summary', Es), TMetaField.Int('Effects', Length(Known)),
      TMetaField.Int('Unknown', Length(Unk)), TMetaField.Int('Unnamed', Unnamed), TMetaField.Bool('D12Suspect', D12),
      TMetaField.Int('ParamCount', Length(Params)), TMetaField.Str('Witness', Ew),
      TMetaField.Int('Clusters', Clusters), TMetaField.Int('ClickTargets', Result.Layout.Anchors),
      TMetaField.Int('Expected', Anchored), TMetaField.Bool('AllClickable', Result.AllClickable)];
  finally
    Sb.Free;
    Index.Free;
  end;
end;

initialization
  RegisterChartQuestion(EFFECTS_ID, Emit);

end.
