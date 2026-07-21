unit DRagLint.Doc.Regions;

interface

uses
  System.SysUtils, System.Classes, System.StrUtils,
  DRagLint.Core.Model, DRagLint.Doc.Facts;

const
  AUTO_BEGIN = '<!-- drag-lint:auto BEGIN -->';
  AUTO_END   = '<!-- drag-lint:auto END -->';
  AUTO_PARAM = '<!-- drag-lint:auto param -->';

type
  TDocRegions = class
  private
    /// <summary>Removes any managed fenced block from S: everything from the
    /// first AUTO_BEGIN occurrence through the end of the line containing the
    /// following AUTO_END (inclusive). Prose before/after the fence is kept.
    /// Idempotent regeneration relies on this so re-runs never nest blocks.</summary>
    class function StripManagedBlock(const S: string): string;
  public
    /// <summary>Renders the fenced facts-block body lines (each prefixed
    /// APrefix), from AFacts. Sections: Called from / Calls / Used in units /
    /// Raises / Deprecated / Overrides / Overridden by / Implements / Overload
    /// k of n / abstract / virtual / Since / SeeAlso. Empty sections omitted;
    /// '' when there are no facts. Displayed counts below the true *Total get a
    /// ' (+N more)' suffix. Deprecated is ground-truth from the Pascal
    /// 'deprecated' directive (not the unrelated &lt;deprecated/&gt; doc-comment
    /// tag) -- emitted only when the directive was found on the declaration.
    /// The cheap fact group (v(ADP1 T3): Overrides/Overridden by/Implements/
    /// Overload/abstract/virtual) is gathered unconditionally for method-like
    /// symbols -- see TDocFacts' field comments for how each is derived and
    /// DRagLint.Doc.Facts.DetectMethodDirectives for the virtual/abstract
    /// source probe. SeeAlso emits one &lt;seealso cref&gt; line per entry; it is
    /// populated only when the facts were built with the --seealso opt-in, so
    /// by default no &lt;seealso&gt; line appears.</summary>
    class function RenderFactsBlock(const AFacts: TDocFacts; const APrefix: string): string;
    /// <summary>Produces the full merged DocInsight comment text (///-prefixed
    /// lines joined by CRLF): preserved hand-written prose + a regenerated
    /// managed facts block (fenced inside remarks) + managed param tags.
    /// Fresh comments emit EMPTY managed placeholders (summary/param empty;
    /// returns carries only the mined 'Observed: ...' facts, if any) -- never
    /// "TODO" text, so generated docs never trip drag-lint's own TODO rule.
    /// Repair preserves Summary/Remarks prose and hand-typed param
    /// descriptions, adds/removes managed param tags, and flags hand-typed
    /// params no longer present in the signature. See IsManagedDesc for how
    /// managed (regenerable) content is told apart from hand-typed prose.</summary>
    class function MergeComment(const AExisting: TParsedDoc;
      const ASigParams: TArray<string>; const AFacts: TDocFacts;
      AHasReturn: Boolean; const APrefix: string): string;
  end;

implementation

/// <summary>Builds the " Observed: a; b." suffix (XML-escaped) from mined return
/// cases, or '' when none. Deterministic -> idempotent across runs.</summary>
function ObservedSuffix(const ACases: TArray<string>): string;
  function Esc(const S: string): string;
  begin
    Result:= StringReplace(S, '&', '&amp;', [rfReplaceAll]);
    Result:= StringReplace(Result, '<', '&lt;', [rfReplaceAll]);
    Result:= StringReplace(Result, '>', '&gt;', [rfReplaceAll]);
  end;
var i: Integer; Sb: TStringBuilder;
begin
  Result:= '';
  if Length(ACases) = 0 then Exit;
  Sb:= TStringBuilder.Create;
  try
    Sb.Append(' Observed: ');
    for i:= 0 to High(ACases) do
    begin
      if i > 0 then Sb.Append('; ');
      Sb.Append(Esc(ACases[i]));
    end;
    Sb.Append('.');
    Result:= Sb.ToString;
  finally Sb.Free; end;
end;

/// <summary>True when S is MANAGED (auto-generated/regenerable) content, as
/// opposed to hand-typed prose. Managed content is either empty (the current
/// emitted placeholder) or exactly the legacy 'TODO: describe.' sentinel that
/// older drag-lint builds used to emit -- recognizing the legacy string here
/// is what makes an old TODO-carrying doc self-heal (regenerate to empty/
/// Observed) the next time `document` runs over it. Any other text is
/// hand-typed and preserved verbatim by the merge logic.</summary>
function IsManagedDesc(const S: string): Boolean;
begin
  Result:= (Trim(S) = '') or SameText(Trim(S), 'TODO: describe.');
end;

class function TDocRegions.StripManagedBlock(const S: string): string;
var
  BeginPos: Integer;
  EndPos  : Integer;
  EolPos  : Integer;
  Head    : string ;
  Tail    : string ;
begin
  // Input is POST-PARSER: the XML doc parser has already stripped the /// prefix
  // and joined lines, so S is the bare Remarks prose (no leading ///). Find the
  // fenced block by the sentinel SUBSTRINGS. The TrimRight over '/'/space below is
  // a harmless safety net for a hypothetical raw-block caller that still carries a
  // /// prefix; it is a no-op on parser-supplied input.
  BeginPos:= Pos(AUTO_BEGIN, S);
  if BeginPos = 0 then Exit(S);
  EndPos:= PosEx(AUTO_END, S, BeginPos);
  if EndPos = 0 then
  begin
    // Malformed: BEGIN with no END. Drop from BEGIN's line start to end.
    Result:= Copy(S, 1, BeginPos - 1).TrimRight([#13, #10, ' ', '/']);
    Exit;
  end;
  // Head = text before the BEGIN. Trim trailing newline/space (the '/' in the set
  // is the safety net noted above; no /// arrives via the parser path).
  Head:= Copy(S, 1, BeginPos - 1).TrimRight([#13, #10, ' ', '/']);
  // Tail = text after the line that contains AUTO_END.
  EolPos:= EndPos + Length(AUTO_END);
  while (EolPos <= Length(S)) and (S[EolPos] <> #13) and (S[EolPos] <> #10) do
    Inc(EolPos);
  Tail:= Copy(S, EolPos, MaxInt).TrimLeft([#13, #10]);
  if (Head <> '') and (Tail <> '') then
    Result:= Head + sLineBreak + Tail
  else
    Result:= Head + Tail;
end;

class function TDocRegions.RenderFactsBlock(const AFacts: TDocFacts; const APrefix: string): string;
var
  Sb: TStringBuilder;
  function MoreSuffix(AShown, ATotal: Integer): string;
  begin
    if ATotal > AShown then Result:= Format(' (+%d more)', [ATotal - AShown]) else Result:= '';
  end;
  function JoinRefs(const A: TArray<TDocFactRef>): string;
  var i: Integer;
  begin
    Result:= '';
    for i:= 0 to High(A) do
    begin
      if i > 0 then Result:= Result + ', ';
      Result:= Result + A[i].Display + ' (' + A[i].Location + ')';
      // v14 (D5): mark honest uncertainty. A caller whose Confidence is anything
      // OTHER than 'certain'/'' ('ambiguous' = >1 candidate on the type chain;
      // 'unverified' = a name-match with no resolved call_edge) gets a trailing
      // ' ?'. The Facts builder already orders plain (certain) callers before the
      // '?' ones, so the rendered line reads plain-first.
      if not ((A[i].Confidence = '') or SameText(A[i].Confidence, 'certain')) then
        Result:= Result + ' ?';
    end;
  end;
begin
  Sb:= TStringBuilder.Create;
  try
    if Length(AFacts.CalledFrom) > 0 then
      Sb.AppendLine(APrefix + 'Called from: ' + JoinRefs(AFacts.CalledFrom) + MoreSuffix(Length(AFacts.CalledFrom), AFacts.CalledFromTotal));
    if Length(AFacts.Calls) > 0 then
      Sb.AppendLine(APrefix + 'Calls: ' + string.Join(', ', AFacts.Calls) + MoreSuffix(Length(AFacts.Calls), AFacts.CallsTotal));
    if Length(AFacts.UsedInUnits) > 0 then
      Sb.AppendLine(APrefix + 'Used in units: ' + string.Join(', ', AFacts.UsedInUnits) + MoreSuffix(Length(AFacts.UsedInUnits), AFacts.UsedInTotal));
    if Length(AFacts.Raises) > 0 then
      Sb.AppendLine(APrefix + 'Raises: ' + string.Join(', ', AFacts.Raises));
    // v(ADF T3): ground-truth 'deprecated' directive line. Emitted only when
    // AFacts.Deprecated (the directive was actually found on the decl -- see
    // TDocFactsBuilder.DetectDeprecated). A message renders 'Deprecated: <msg>';
    // a bare directive (no message string) renders the bare 'Deprecated.' line.
    if AFacts.Deprecated then
    begin
      if AFacts.DeprecatedMsg <> '' then
        Sb.AppendLine(APrefix + 'Deprecated: ' + AFacts.DeprecatedMsg)
      else
        Sb.AppendLine(APrefix + 'Deprecated.');
    end;
    // v(ADP1 T3): cheap fact group -- each line omit-when-empty, same discipline
    // as the sections above. Overrides/Implements are plain qualified names
    // (never '?'-tagged -- Overrides is ancestry-grounded, Implements is a
    // documented name-based heuristic per TDocFacts.Implements' comment, not an
    // uncertain/ambiguous match in the CalledFrom sense). Overridden by mirrors
    // CalledFrom's cap-plus-'(+N more)' pattern. Overload is a single 'k of n'
    // line, only when n > 1. abstract/virtual are bare one-word marker lines
    // and are INDEPENDENT facts -- a virtual; abstract method correctly
    // renders BOTH (abstract implies virtual). The mutual exclusion that IS
    // enforced is virtual-vs-Overrides: an override suppresses the virtual
    // marker, emitting Overrides instead (see TDocFacts.IsVirtual).
    if AFacts.Overrides <> '' then
      Sb.AppendLine(APrefix + 'Overrides: ' + AFacts.Overrides);
    if Length(AFacts.OverriddenBy) > 0 then
      Sb.AppendLine(APrefix + 'Overridden by: ' + string.Join(', ', AFacts.OverriddenBy) + MoreSuffix(Length(AFacts.OverriddenBy), AFacts.OverriddenByTotal));
    if AFacts.Implements <> '' then
      Sb.AppendLine(APrefix + 'Implements: ' + AFacts.Implements);
    if AFacts.OverloadCount > 1 then
      Sb.AppendLine(APrefix + Format('Overload %d of %d', [AFacts.OverloadOrdinal, AFacts.OverloadCount]));
    if AFacts.IsAbstract then
      Sb.AppendLine(APrefix + 'abstract');
    if AFacts.IsVirtual then
      Sb.AppendLine(APrefix + 'virtual');
    // v(ADF T5): OPT-IN git <since> line. AFacts.Since is '' unless the caller
    // built the facts with --since (TDocFactsBuilder.Build's AIncludeSince) AND
    // git confidently attributed the declaration line, so this renders NOTHING by
    // default and NOTHING on any git failure (absence over a wrong fact) -- the
    // non-since managed block is unchanged. The date is a real git commit date
    // (YYYY-MM-DD), never a guess; one line so the block regenerates idempotently.
    if AFacts.Since <> '' then
      Sb.AppendLine(APrefix + '<since>' + AFacts.Since + '</since>');
    // v(ADF T4): OPT-IN <seealso> cref lines. AFacts.SeeAlso is EMPTY unless the
    // caller built the facts with --seealso (TDocFactsBuilder.Build's
    // AIncludeSeeAlso), so this section renders NOTHING by default -- the
    // non-seealso managed block is unchanged. Each entry is a real indexed
    // qualified name (a resolved callee or a sibling), so no '?'-tagged cref is
    // ever emitted. The list is pre-sorted+capped by Build; one cref per line so
    // the block regenerates idempotently.
    for var SeeI:= 0 to High(AFacts.SeeAlso) do
      Sb.AppendLine(APrefix + '<seealso cref="' + AFacts.SeeAlso[SeeI] + '"/>');
    Result:= Sb.ToString.TrimRight([#13, #10]);
  finally
    Sb.Free;
  end;
end;

class function TDocRegions.MergeComment(const AExisting: TParsedDoc;
  const ASigParams: TArray<string>; const AFacts: TDocFacts;
  AHasReturn: Boolean; const APrefix: string): string;
var
  Sb   : TStringBuilder;
  P    : string        ;
  Facts: string        ;
begin
  Sb:= TStringBuilder.Create;
  try
    Facts:= RenderFactsBlock(AFacts, APrefix);
    if not AExisting.HasContent then
    begin
      Sb.AppendLine(APrefix + '<summary></summary>');
      for P in ASigParams do
        Sb.AppendLine(APrefix + '<param name="' + P + '"></param>' + AUTO_PARAM);
      if AHasReturn then
        Sb.AppendLine(APrefix + '<returns>' + Trim(ObservedSuffix(AFacts.ReturnCases)) + '</returns>');
      if Facts <> '' then
      begin
        Sb.AppendLine(APrefix + '<remarks>');
        Sb.AppendLine(APrefix + AUTO_BEGIN);
        Sb.AppendLine(Facts);
        Sb.AppendLine(APrefix + AUTO_END);
        Sb.AppendLine(APrefix + '</remarks>');
      end;
      Result:= Sb.ToString.TrimRight([#13, #10]);
      Exit;
    end;

    // Existing comment: preserve prose, regenerate managed regions. Rebuild from
    // the parsed model: keep Summary (or blank it if managed -- see
    // IsManagedDesc), keep hand-typed params + descs, add AUTO_PARAM tags for
    // missing sig params, drop AUTO_PARAM tags for params no longer in the
    // signature, flag hand-typed stale params, then the returns tag, then a
    // fresh <remarks> managed block.
    var SummaryText: string:= AExisting.Summary;
    if IsManagedDesc(SummaryText) then SummaryText:= '';
    Sb.AppendLine(APrefix + '<summary>' + SummaryText + '</summary>');

    // MANAGED-vs-HAND-TYPED param detection is CONTENT-BASED, not sentinel-based.
    // We APPEND the AUTO_PARAM sentinel after a managed <param> line for human /
    // diff visibility, but the doc parser STRIPS trailing sentinels (and the ///
    // prefix) before AExisting.Params is populated, so the marker does not survive
    // a round-trip. On regeneration we therefore RE-DERIVE "managed" from the desc
    // CONTENT via IsManagedDesc: empty, or exactly the legacy 'TODO: describe.'
    // sentinel => managed/regenerable (re-emit EMPTY with the AUTO_PARAM marker,
    // cleaning up any legacy TODO text); any OTHER desc => hand-typed (preserve
    // as-is, no marker; flag if the param is stale). Edge case: a genuine hand-typed
    // desc that is literally 'TODO: describe.' is treated as managed. Acceptable for
    // Chunk 1. This content-based scheme is idempotency-safe: run N and run N+1 see
    // the same desc content and classify identically.
    // existing params first, in signature order where possible
    for P in ASigParams do
    begin
      var Found: Boolean:= False;
      for var EP in AExisting.Params do
        if SameText(EP.Name, P) then
        begin
          if IsManagedDesc(EP.Desc) then
            Sb.AppendLine(APrefix + '<param name="' + P + '"></param>' + AUTO_PARAM)
          else
            Sb.AppendLine(APrefix + '<param name="' + P + '">' + EP.Desc + '</param>');
          Found:= True; Break;
        end;
      if not Found then
        Sb.AppendLine(APrefix + '<param name="' + P + '"></param>' + AUTO_PARAM);
    end;
    // stale hand-typed params: in the comment but not the signature -> flag, keep
    for var EP in AExisting.Params do
    begin
      var StillThere: Boolean:= False;
      for P in ASigParams do if SameText(EP.Name, P) then begin StillThere:= True; Break; end;
      if (not StillThere) and (not IsManagedDesc(EP.Desc)) then
        Sb.AppendLine(APrefix + '<param name="' + EP.Name + '">' + EP.Desc + '</param> <!-- drag-lint: param no longer exists -->');
    end;

    if AHasReturn then
    begin
      var Ret: string:= AExisting.ReturnsText;
      // Managed (empty, or the legacy TODO sentinel) -> regenerate from the
      // mined facts only (empty when there are no cases). Author-edited
      // returns (non-managed) win: do NOT inject Observed into hand text.
      if IsManagedDesc(Ret) then
        Ret:= Trim(ObservedSuffix(AFacts.ReturnCases));
      Sb.AppendLine(APrefix + '<returns>' + Ret + '</returns>');
    end;

    // remarks: keep hand prose (AExisting.Remarks) OUTSIDE the fence, then a fresh
    // managed block. Strip any old fenced block from the prose before re-emitting
    // so a second run does not nest blocks.
    var Prose: string:= StripManagedBlock(AExisting.Remarks);
    if (Trim(Prose) <> '') or (Facts <> '') then
    begin
      Sb.AppendLine(APrefix + '<remarks>');
      if Trim(Prose) <> '' then
      begin
        // Hand-written remarks prose may contain multiple lines (the parser joins
        // them with bare #10). Emit EACH line APrefix-prefixed so every output line
        // carries /// and the final CRLF join stays valid -- never one line with an
        // embedded bare LF. Normalize CRLF/CR to LF, split, drop empty lines.
        var NormProse: string:= StringReplace(Trim(Prose), #13#10, #10, [rfReplaceAll]);
        NormProse:= StringReplace(NormProse, #13, #10, [rfReplaceAll]);
        for var ProseLine in NormProse.Split([#10]) do
          if Trim(ProseLine) <> '' then
            Sb.AppendLine(APrefix + Trim(ProseLine));
      end;
      if Facts <> '' then
      begin
        Sb.AppendLine(APrefix + AUTO_BEGIN);
        Sb.AppendLine(Facts);
        Sb.AppendLine(APrefix + AUTO_END);
      end;
      Sb.AppendLine(APrefix + '</remarks>');
    end;
    Result:= Sb.ToString.TrimRight([#13, #10]);
  finally
    Sb.Free;
  end;
end;

end.
