unit DRagLint.CLI.ConvertApplyJson;

// ---------------------------------------------------------------------------
// convert-apply's report: the text summary and the apply/1 JSON document (TApplyJsonCtx, EmitApplyJson).
// Moved verbatim out of DRagLint.CLI.Convert (lane v1511 SPLIT, T07; that unit alone was over 2,000 lines).
// ---------------------------------------------------------------------------

interface

uses
  System.JSON, DRagLint.CLI.Common, DRagLint.Convert.Rules, DRagLint.Convert.Apply, DRagLint.Refactor.TextEdit;

type

  /// <summary>Everything schema apply/1 reports about one convert-apply run.
  /// A record rather than nine parameters, per too-many-parameters (max 7).</summary>
  /// <remarks>
  /// Populated on the SUCCESS path and on both failure paths (rule
  /// validation, and BuildApplyPlan returning Ok=False), so a JSON consumer gets
  /// a parseable document with ok=false rather than nothing at all.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.CLI.ConvertApplyJson.pas) ?, DRagLint.CLI.ConvertApply.DoConvertApply (DRagLint.CLI.ConvertApply.pas) ?, DRagLint.CLI.ConvertApply.DoConvertApply.RunUnit (DRagLint.CLI.ConvertApply.pas), DRagLint.CLI.ConvertApply.EncodingGuardReason (DRagLint.CLI.ConvertApply.pas) ?, DRagLint.CLI.ConvertApplyJson.EmitApplyJson (DRagLint.CLI.ConvertApplyJson.pas) ?</para>
  /// <para>Used in units: DRagLint.CLI.ConvertApply, DRagLint.CLI.ConvertApplyJson</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TApplyJsonCtx = record
    Report    : TApplyReport;
    UnitPas   : string;
    DfmPath   : string;
    RulesFile : string;
    Mode      : string;  { 'dry-run' or 'apply' }
    Error     : string;
    RuleErrors: TArray<TRuleError>;
    Freshness : TFreshnessResult;
    EditCount : Integer;
    Ok        : Boolean;
    { 1.20.6: what happened to the COMPONENT (#convert / .dfm) part --
      'applied', 'skipped-no-dfm', 'skipped-no-convert-rules' or
      'skipped-no-instances' (the last three: the book's unit rules ran alone);
      '' when the run stopped before planning. }
    ComponentPart: string;
    { 1.20.6 (T2b): how many classes' members the run resolved (validation and
      plan share one cache per store) -- apply/1 classes_built. }
    ClassesBuilt: Integer;
    { 1.20.6 (T2h, owner ruling R12): the rule paths through members that exist
      but are inaccessible -- skipped, never applied -- apply/1 unreachable[].
      Their messages are ALSO in Report.Warnings / Report.Items. }
    Unreachable: TArray<TUnreachablePath>;
    { 1.20.6 (T2f): True for a DELIBERATE refusal -- the unit cannot be
      converted safely and nothing was written (a unit-rules conditional-uses
      refusal, and any TApplyResult.Refusal) --
      apply/1 refused / reason. False for every other outcome, success and
      genuine failure alike. Reason is '' unless Refused. }
    Refused: Boolean;
    Reason : string;
    { 1.34.1 (CONV-ENC E1'): set with Refused when a value does not fit the target
      .pas/.dfm encoding -- apply/1 refusal_kind 'encoding_refused' + the
      encoding_refused object (file, file_encoding, raise_to, chars_total, chars[]).
      RefusalKind is '' for every other outcome (the keys are then omitted). }
    RefusalKind: string;
    EncFile    : string;
    EncName    : string;
    EncTotal   : Integer;
    EncChars   : TArray<TEncodingMisfit>;
    { 1.22.0 (C8 N1): the inherited / inline .dfm objects of a From type the
      run SKIPPED, each with its declaring ancestor -- apply/1 inherited[]. Their
      'line N: warning:' text is ALSO in Report.Warnings / Report.Items. }
    InheritedInsts: TArray<TInheritedInstance>;
    { 1.25.0: the descendant units that still stream or use an instance this
      run converts -- apply/1 descendants[]. Their 'line N: warning:' text is
      ALSO in Report.Warnings / Report.Items. }
    Descendants: TArray<TDescendantUse>;
    { 1.23.0 (C13 b2): batch mode's collector. nil -> EmitApplyJson writes the
      document to stdout (single --unit, unchanged); assigned -> the apply/1
      object is appended to it instead (owned by the array) and nothing is
      written, so DoConvertApply can wrap every unit in one apply-batch/1. }
    Sink: TJSONArray;
    { 1.27.0 (C9): apply/1 uses_reconcile ('on' | 'off' | 'degraded') and the
      post-apply project-index refresh (uses_reindex). }
    UsesReconcile: string;
    Reindex      : TUsesReindex;
    { 1.23.0 (C13 N3): the --only names that name a .dfm object of a #convert
      From type, and the ones that name none -- apply/1 only_matched[] /
      only_unmatched[], spelled as given, in --only order; both [] without
      --only. An unmatched name is ignored (never an error). }
    OnlyMatched  : TArray<string>;
    OnlyUnmatched: TArray<string>;
    { 1.25.1: objects --only left out that convert with a kept parent }
    OnlyIncluded : TArray<TNestedOnly>;
    { owner ruling 2026-10-11: the #convert lines whose bare class name had
      several declarers -- refused, or inferred and warned about --
      apply/1 qualify_fixes[] (capability convert_qualify_fix) }
    QualifyFixes : TArray<TQualifyFix>;
  end;

const
  /// <summary>The only encoding level convert-apply --raise-encoding accepts, and the apply/1
  /// encoding_refused.raise_to value (1.34.1).</summary>
  ENC_RAISE_LEVEL = 'utf8-bom';

/// <summary>Prints the human-readable summary of one convert-apply run: the
/// header line, then one block per non-empty report surface.</summary>
/// <param name="AReport">The report to print. All six of its arrays are shown in full; ResolvedDefaults is summarised as a COUNT instead, because it is the one
/// surface whose volume scales with the form rather than with its defects.</param>
/// <param name="AEditCount">Edit count for the header line.</param>
/// <param name="AVerb">'planned' (dry-run) or 'applied' (--apply).</param>
/// <remarks>
/// This replaces TWO byte-for-byte duplicated print blocks (the dry-run one and
/// the --apply one), which BOTH printed only four of the six arrays: CreatorSites
/// and ReemitNotes were computed by BuildApplyPlan and then silently discarded.
/// That is why the engine could write "verify the creator manually" and no
/// operator ever saw it.
///
/// Block order is Converted, AccessSites, CreatorSites, Todos, ReemitNotes,
/// Warnings -- work-done surfaces first, then the REMAINDER (Todos, ReemitNotes,
/// Warnings: the things a human still has to do).
///
/// Each block is preceded by a BLANK LINE. Consumers slice a block with
/// 'Heading:([\s\S]*?)(\r?\n\r?\n|\z)' (tests\autotest\run_convert_apply.ps1);
/// without a blank terminator every such slice ran to end-of-output and so
/// silently included every later block, which made those assertions pass for the
/// wrong reason. Empty surfaces print nothing at all, as before.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.ConvertApply.DoConvertApply.RunUnit (DRagLint.CLI.ConvertApply.pas)</para>
/// <para>Calls: DRagLint.CLI.ConvertApplyJson.PrintApplyReport.Block, ExtractFileExt, Format, IntToStr, SameText, Writeln</para>
/// <para>Complexity: 32 (cyclomatic, outer body), 127 lines (full implementation)</para>
/// <seealso cref="DRagLint.CLI.ConvertApplyJson.PrintApplyReport.Block"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure PrintApplyReport(const AReport: TApplyReport; AEditCount: Integer; const AVerb: string);

/// <summary>Writes the whole convert-apply run as schema apply/1 JSON.</summary>
/// <param name="ACtx">The run to report.</param>
/// <remarks>
/// Mirrors info/1's house style -- 'schema' first, snake_case keys. It does NOT
/// follow convert-reemit's JSON, which predates the convention, carries no
/// 'schema' key at all and uses camelCase; that is not a precedent to copy.
///
/// INVARIANT, and the reason the typed items exist: items.length equals the sum
/// of the lengths of the six arrays. Each item mirrors one array entry, adding
/// the machine-readable 'kind' and the structured facts behind the prose. The
/// REMAINDER of a conversion is the subset whose 'field' is todos, reemit_notes
/// or warnings.
///
/// Compatibility: adding a kind, or a key, is additive and stays apply/1.
/// RENAMING a kind or a key is a breaking change and requires apply/2. The kind
/// spellings come from ApplyItemKindName, never from a literal here.
///
/// Emits nothing else on stdout: under JSON the caller suppresses RenderDryRun
/// and every Writeln, or the document would not parse.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.ConvertApply.DoConvertApply.FailUnit (DRagLint.CLI.ConvertApply.pas), DRagLint.CLI.ConvertApply.DoConvertApply.RefuseUnit (DRagLint.CLI.ConvertApply.pas), DRagLint.CLI.ConvertApply.DoConvertApply.RunUnit (DRagLint.CLI.ConvertApply.pas)</para>
/// <para>Calls: ApplyFieldName, ApplyItemKindName, DRagLint.CLI.Common.WriteStdoutDocument, DRagLint.CLI.Convert.UnreachableJson, DRagLint.CLI.ConvertApplyJson.EmitApplyJson.ArrOf, DRagLint.CLI.ConvertApplyJson.EmitApplyJson.GlyphsJson, DRagLint.CLI.ConvertApplyJson.EmitApplyJson.ItemJson, DRagLint.CLI.ConvertApplyJson.PasUsesJson, DRagLint.Convert.Rules.DistinctUnreachable</para>
/// <seealso cref="DRagLint.CLI.Common.WriteStdoutDocument"/>
/// <seealso cref="DRagLint.CLI.Convert.UnreachableJson"/>
/// <seealso cref="DRagLint.CLI.ConvertApplyJson.EmitApplyJson.ArrOf"/>
/// <seealso cref="DRagLint.CLI.ConvertApplyJson.EmitApplyJson.GlyphsJson"/>
/// <seealso cref="DRagLint.CLI.ConvertApplyJson.EmitApplyJson.ItemJson"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure EmitApplyJson(const ACtx: TApplyJsonCtx);

/// <summary>apply/1 component_part: what happened to the COMPONENT (#convert / .dfm) part of a convert-apply run.</summary>
/// <param name="ARules">The book.</param>
/// <param name="ADfmPath">The unit's .dfm, '' when there is none.</param>
/// <param name="AOnly">--only names.</param>
/// <param name="AHasInherited">True when the run met inherited / inline objects (a unit-rules-only book still counts as applied).</param>
/// <param name="AHasRetype">True when a retype still applies with no .dfm instance (the part is then not skipped).</param>
/// <returns>'applied', 'skipped-no-dfm', 'skipped-no-convert-rules' or 'skipped-no-instances'.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.ConvertApply.DoConvertApply.RunUnit (DRagLint.CLI.ConvertApply.pas)</para>
/// <para>Calls: DRagLint.Convert.Apply.FindConvertInstances, DRagLint.Convert.Apply.ReadUnitText, DRagLint.Convert.UnitRules.BookHasUnitRules</para>
/// <para>Returns: 'applied'; 'skipped-no-dfm'; 'skipped-no-convert-rules'; 'skipped-no-instances'</para>
/// <para>Touches: file system</para>
/// <seealso cref="DRagLint.Convert.Apply.FindConvertInstances"/>
/// <seealso cref="DRagLint.Convert.Apply.ReadUnitText"/>
/// <seealso cref="DRagLint.Convert.UnitRules.BookHasUnitRules"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ConvertApplyComponentPart(const ARules: TConversionRuleSet; const ADfmPath: string;
  const AOnly: TArray<string>; AHasInherited, AHasRetype: Boolean): string;

implementation

uses
  DRagLint.Convert.UnitRules, DRagLint.Convert.UsesReconcile, Winapi.Windows, System.SysUtils, System.Classes,
  System.IOUtils, System.NetEncoding, System.DateUtils, System.Generics.Collections, System.SyncObjs,
  FireDAC.Stan.Async, FireDAC.Stan.Param, FireDAC.DApt, TreeSitter, DRagLint.CLI.Convert;

procedure PrintApplyReport(const AReport: TApplyReport; AEditCount: Integer; const AVerb: string);

  procedure Block(const AHeading: string; const ALines: TArray<string>);
  var
    S: string;
  begin
    if Length(ALines) = 0 then Exit;
    Writeln('');
    Writeln(AHeading + ':');
    for S in ALines do Writeln('  ' + S);
  end;

var
  S: string;
begin
  Writeln(Format('convert-apply: %d instance(s) converted, %d edit(s) %s',
    [Length(AReport.Converted), AEditCount, AVerb]));
  { Converted keeps its heading-less shape -- it reads as the header's detail. }
  for S in AReport.Converted do Writeln('  ' + S);
  for var GL: TApplyGlyph in AReport.Glyphs do
    Writeln((if GL.Outcome.Kind = 'glyph-stitched' then '  ' + GL.Instance + ': ' else '*** GLYPH TODO: ' + GL.Instance + ': ') + GL.Outcome.Message);
  Block('AccessSites',  AReport.AccessSites);
  Block('CreatorSites', AReport.CreatorSites);
  Block('Todos',        AReport.Todos);
  Block('ReemitNotes',  AReport.ReemitNotes);
  Block('Warnings',     AReport.Warnings);
  { 1.20.6 -- one line per uses-clause change a unit rule made, e.g.
      remove OldU (interface, line 6) -- #useswap OldU -> NewU1, NewU2
    under a heading carrying the two counts; nothing when there are none. }
  if Length(AReport.UsesChanges) > 0 then
  begin
    var NRemoved: Integer:= 0;
    var NSkipped: Integer:= 0;
    var NAdded  : Integer:= 0;
    var NOther  : Integer:= 0; { C9: kept + moved }
    for var UC: TUsesChange in AReport.UsesChanges do
      if UC.Action = 'remove' then Inc(NRemoved)
      else if UC.Action = 'skipped' then Inc(NSkipped)
      else if UC.Action = 'add' then Inc(NAdded)
      else Inc(NOther);
    Writeln('');
    var Head: string:= Format('Uses: %d removed, %d added', [NRemoved, NAdded]);
    if NSkipped > 0 then Head:= Head + Format(', %d removal(s) skipped (--only)', [NSkipped]);
    if NOther > 0 then Head:= Head + Format(', %d kept/moved', [NOther]);
    Writeln(Head);
    for var UC: TUsesChange in AReport.UsesChanges do
    begin
      var Need: string:= '';
      for var N: TUsesNeed in UC.NeededBy do Need:= Need + (if Need = '' then '' else ', ') + Format('%s (line %d)', [N.Name, N.Line]);
      Writeln(Format('  %s %s (%s, line %d) -- %s', [UC.Action, UC.UnitName, UC.Section, UC.Line,
        if UC.Rule <> '' then UC.Rule else UC.Source]) +
        (if UC.Reason <> '' then ' (' + UC.Reason + ')' else '') +
        (if Need <> '' then ' [' + Need + ']' else ''));
    end;
  end;
  { C9: names the conversion introduced whose unit was not added }
  for var UU: TUsesUnresolved in AReport.UsesUnresolved do
  begin
    var Units: string:= '';
    for var C: TUsesCandidate in UU.Candidates do Units:= Units + (if Units = '' then '' else ', ') + C.UnitName;
    Writeln(Format('  unresolved %s (%s, line %d) -- %s%s', [UU.Name, UU.Section, UU.Line, UU.Reason,
      if Units <> '' then ': ' + Units else '']));
  end;  { ResolvedDefaults -- a COUNT, not a listing, and that asymmetry is deliberate.
    Text mode used to print one line per resolved default under ReemitNotes,
    which on a real form is ~2,000 lines of "this worked" ahead of the handful
    that did not. A human reading the terminal needs to know the carries
    happened and how many; the per-property account is a machine's question, so
    it goes to --format json.

    Uses Block so it keeps the `Heading:` + blank-line shape the runner slices
    on, and prints nothing at all when the array is empty, like every other
    surface here. }
  if Length(AReport.ResolvedDefaults) > 0 then
    Block('ResolvedDefaults',
      [Format('%d property value(s) carried from their declared defaults (--format json lists each)',
              [Length(AReport.ResolvedDefaults)])]);
  { 1.27.0 (C15): the value casts (StripDB) -- one count line per unit }
  var VDfm : Integer:= 0;
  var VPas : Integer:= 0;
  var VChk : Integer:= 0;
  for var VI: TApplyItem in AReport.Items do
    if VI.Kind = aikValueCastCheck then Inc(VChk)
    else if (VI.Kind = aikValueCastApplied) and SameText(ExtractFileExt(VI.FilePath), '.dfm') then Inc(VDfm)
    else if VI.Kind = aikValueCastApplied then Inc(VPas);
  if VDfm + VPas + VChk > 0 then
  begin
    Writeln('');
    Writeln(Format('value casts: %d value(s) changed (.dfm %d, .pas %d), %d site(s) to check by hand',
      [VDfm + VPas, VDfm, VPas, VChk]));
  end;
  { 1.27.0 -- pas_uses[]: one summary line, then the work list (unmapped and
    not-rewritten members) with their lines; nothing when the code uses nothing }
  if Length(AReport.PasUses) > 0 then
  begin
    var NUnm : Integer:= 0;
    var NGlob: Integer:= 0;
    var NSame: Integer:= 0;
    var NMap : Integer:= 0;
    var NCast: Integer:= 0;
    var NNotW: Integer:= 0;
    for var PU: TApplyPasUse in AReport.PasUses do
      if PU.Status = PAS_USE_UNMAPPED then Inc(NUnm)
      else if PU.Status = PAS_USE_GLOBAL_DANGLING then Inc(NGlob)
      else if PU.Status = PAS_USE_SAME_NAME then Inc(NSame)
      else if PU.Status = PAS_USE_MAPPED then Inc(NMap)
      else if PU.Status = PAS_USE_NOT_REWRITTEN then Inc(NNotW)
      else Inc(NCast);
    Writeln('');
    Writeln(Format('pas uses: %d unmapped, %d global-dangling, %d same-name, %d mapped, %d cast-refused, %d not-rewritten',
      [NUnm, NGlob, NSame, NMap, NCast, NNotW]));
    for var PU: TApplyPasUse in AReport.PasUses do
    begin
      if (PU.Status <> PAS_USE_UNMAPPED) and (PU.Status <> PAS_USE_NOT_REWRITTEN) then Continue;
      var Ls: string:= '';
      for var L: Integer in PU.Lines do Ls:= Ls + (if Ls = '' then '' else ', ') + IntToStr(L);
      { 1.28.2: an unresolved declarer is SAID, never printed as empty facts }
      var Decl: string;
      if PU.Resolution = PAS_RES_AMBIGUOUS then
        Decl:= 'declaring class ambiguous: ' + string.Join(', ', PU.Candidates)
      else if PU.Resolution = PAS_RES_RESOLVED then
        Decl:= Format('%s, %s, %s in %s', [PU.Kind, PU.Visibility, PU.DeclaredIn, PU.DeclaringUnit])
      else
        Decl:= PU.Resolution;
      Writeln(Format('  %s %s.%s (%s) -- %s %s',
        [PU.Status, PU.Instance, PU.Member, Decl, if Length(PU.Lines) = 1 then 'line' else 'lines', Ls]));
    end;
  end;
end; // procedure

/// <summary>apply/1 pas_uses[] (1.27.0): one object per TApplyPasUse.</summary>
/// <param name="AUses">The report's PasUses.</param>
/// <param name="ARulesFile">The book the run applied; every row names it
/// (rules_file, additive) so a consumer merging several runs keeps the book.</param>
/// <returns>A new array; the caller owns it (AddPair takes it over).</returns>
/// <remarks>Additive keys after 1.33: migrate_to (the New of the #migrate
/// convert-apply realises for the member, DL_NONE for a deliberate break, ''
/// when none; status stays mapped) and rules_file.</remarks>
function PasUsesJson(const AUses: TArray<TApplyPasUse>; const ARulesFile: string): TJSONArray;
begin
  Result:= TJSONArray.Create;
  for var PU: TApplyPasUse in AUses do
  begin
    var JP: TJSONObject:= TJSONObject.Create;
    JP.AddPair('instance'      , PU.Instance);
    JP.AddPair('from_type'     , PU.FromType);
    JP.AddPair('to_type'       , PU.ToType);
    JP.AddPair('member'        , PU.Member);
    JP.AddPair('kind'          , PU.Kind);
    JP.AddPair('visibility'    , PU.Visibility);
    JP.AddPair('declaring_unit', PU.DeclaringUnit);
    JP.AddPair('declared_in'   , PU.DeclaredIn);
    JP.AddPair('status'        , PU.Status);
    var JL: TJSONArray:= TJSONArray.Create;
    for var L: Integer in PU.Lines do JL.Add(L);
    JP.AddPair('lines'         , JL);
    JP.AddPair('count'         , TJSONNumber.Create(Length(PU.Lines)));
    JP.AddPair('resolution'    , PU.Resolution);   { 1.28.2 }
    var JC: TJSONArray:= TJSONArray.Create;
    for var C: string in PU.Candidates do JC.Add(C);
    JP.AddPair('candidates'    , JC);
    JP.AddPair('migrate_to'    , PU.MigrateTo);    { G4, additive }
    JP.AddPair('rules_file'    , ARulesFile);      { G7, additive }
    Result.AddElement(JP);
  end;
end;
procedure EmitApplyJson(const ACtx: TApplyJsonCtx);

  function ArrOf(const AItems: TArray<string>): TJSONArray;
  var
    S: string;
  begin
    Result:= TJSONArray.Create;
    for S in AItems do Result.Add(S);
  end;

  { apply/1 glyphs[]: always present, [] when none (asks N3). The key names are the
  ones the editor's ConvRules.ConvertRun.GlyphOutcomes reads. }
function GlyphsJson(const AGlyphs: TArray<TApplyGlyph>): TJSONArray;
begin
  Result:= TJSONArray.Create;
  for var G: TApplyGlyph in AGlyphs do
  begin
    var O: TJSONObject:= TJSONObject.Create;
    O.AddPair('instance' , G.Instance);
    O.AddPair('from_path', G.Outcome.FromPath);
    O.AddPair('to_path'  , G.Outcome.ToPath);
    O.AddPair('kind'     , G.Outcome.Kind);
    O.AddPair('source_n' , TJSONNumber.Create(G.Outcome.SourceN));
    O.AddPair('alternative', G.Outcome.Alternative);
    var D: TJSONArray:= TJSONArray.Create;
    for var Slot: Integer in G.Outcome.DroppedSlots do D.Add(Slot);
    O.AddPair('dropped_slots', D);
    O.AddPair('rule_line', TJSONNumber.Create(G.Outcome.RuleLine));
    O.AddPair('line'     , TJSONNumber.Create(G.Line));
    O.AddPair('message'  , G.Outcome.Message);
    Result.AddElement(O);
  end;
end;

function ItemJson(const AItem: TApplyItem): TJSONObject;
  begin
    Result:= TJSONObject.Create;
    Result.AddPair('kind'     , ApplyItemKindName(AItem.Kind));
    Result.AddPair('field'    , ApplyFieldName(AItem.Field));
    Result.AddPair('instance' , AItem.Instance);
    Result.AddPair('from_type', AItem.FromType);
    Result.AddPair('to_type'  , AItem.ToType);
    Result.AddPair('file'     , AItem.FilePath);
    Result.AddPair('path'     , AItem.Path);
    Result.AddPair('text'     , AItem.Text);
    Result.AddPair('line'     , TJSONNumber.Create(AItem.Line));
    Result.AddPair('rule_line', TJSONNumber.Create(AItem.RuleLine));
    { 1.26.5: additive, and only on the kinds that are ABOUT a value }
    if AItem.Kind in [aikBookWarning, aikRefPathLike, aikRefDangling, aikCastNotApplied, aikValueCastApplied, aikValueCastCheck,
                      aikMigrateApplied, aikMigrateCheck, aikDeliberateBreak] then
      Result.AddPair('value', AItem.Value);
    { 1.27.0 (C15): the literal a value cast replaced; C18: the member text a
      #migrate renamed or wrapped }
    if AItem.Kind in [aikValueCastApplied, aikMigrateApplied, aikDeliberateBreak, aikMigrateCheck] then { G11: + the check's Old }
      Result.AddPair('old_value', AItem.OldValue);
  end;

var
  JRoot, JFresh, JErr: TJSONObject;
  JRuleErrors, JItems: TJSONArray;
  JResolved: TJSONArray ;
  JRD      : TJSONObject;
  RE  : TRuleError;
  Item: TApplyItem;
  RD  : TApplyResolvedDefault;
begin
  JRoot:= TJSONObject.Create;
  try
    JRoot.AddPair('schema', 'apply/1');
    JRoot.AddPair('mode', ACtx.Mode);
    JRoot.AddPair('unit', ACtx.UnitPas);
    JRoot.AddPair('dfm', ACtx.DfmPath);
    JRoot.AddPair('rules_file', ACtx.RulesFile);
    JRoot.AddPair('ok', TJSONBool.Create(ACtx.Ok));
    JRoot.AddPair('error', ACtx.Error);
    { T2f: always emitted; the editor keys its 'refused -- not changed' row on
      refused == true. reason is '' unless refused. }
    JRoot.AddPair('refused', TJSONBool.Create(ACtx.Refused));
    JRoot.AddPair('reason', ACtx.Reason);
    if ACtx.RefusalKind <> '' then
    begin
      JRoot.AddPair('refusal_kind', ACtx.RefusalKind);
      var JEnc: TJSONObject:= TJSONObject.Create;
      JEnc.AddPair('file'         , ACtx.EncFile);
      JEnc.AddPair('file_encoding', ACtx.EncName);
      JEnc.AddPair('raise_to'     , ENC_RAISE_LEVEL);
      JEnc.AddPair('chars_total'  , TJSONNumber.Create(ACtx.EncTotal));
      var JChars: TJSONArray:= TJSONArray.Create;
      for var Mf: TEncodingMisfit in ACtx.EncChars do
      begin
        var JC: TJSONObject:= TJSONObject.Create;
        JC.AddPair('code', TJSONNumber.Create(Mf.Code));
        JC.AddPair('text', Mf.Text);
        JC.AddPair('line', TJSONNumber.Create(Mf.Line));
        JChars.AddElement(JC);
      end;
      JEnc.AddPair('chars', JChars);
      JRoot.AddPair('encoding_refused', JEnc);
    end;

    JRuleErrors:= TJSONArray.Create;
    for RE in ACtx.RuleErrors do
    begin
      JErr:= TJSONObject.Create;
      JErr.AddPair('line', TJSONNumber.Create(RE.LineNo));
      JErr.AddPair('message', RE.Message);
      JRuleErrors.AddElement(JErr);
    end;
    JRoot.AddPair('rule_errors', JRuleErrors);

    JRoot.AddPair('edits_count', TJSONNumber.Create(ACtx.EditCount));

    JFresh:= TJSONObject.Create;
    JFresh.AddPair('fresh', TJSONBool.Create(ACtx.Freshness.Fresh));
    JFresh.AddPair('reasons', ArrOf(ACtx.Freshness.Reasons));
    JRoot.AddPair('freshness', JFresh);

    JRoot.AddPair('converted'    , ArrOf(ACtx.Report.Converted));
    JRoot.AddPair('access_sites' , ArrOf(ACtx.Report.AccessSites));
    JRoot.AddPair('creator_sites', ArrOf(ACtx.Report.CreatorSites));
    JRoot.AddPair('todos'        , ArrOf(ACtx.Report.Todos));
    JRoot.AddPair('reemit_notes' , ArrOf(ACtx.Report.ReemitNotes));
    JRoot.AddPair('warnings'     , ArrOf(ACtx.Report.Warnings));

    JItems:= TJSONArray.Create;
    for Item in ACtx.Report.Items do JItems.AddElement(ItemJson(Item));
    JRoot.AddPair('items', JItems);

    { resolved_defaults -- ALWAYS present, [] when empty, exactly like the six
      arrays: a consumer must never have to tell "none" apart from "this engine
      does not report it". Placed AFTER items so a streaming reader sees the
      remainder first, which is the half that needs a human.

      Six keys, not ten. Every entry would carry the same kind and field, `file`
      is the document's own `dfm`, and `text` -- the bulk of a TApplyItem -- now
      holds nothing that is not a typed key here. to_path and value in
      particular were previously recoverable ONLY by parsing the prose. }
    JResolved:= TJSONArray.Create;
    for RD in ACtx.Report.ResolvedDefaults do
    begin
      JRD:= TJSONObject.Create;
      JRD.AddPair('instance' , RD.Instance);
      JRD.AddPair('from_path', RD.FromPath);
      JRD.AddPair('to_path'  , RD.ToPath  );
      JRD.AddPair('value'    , RD.Value   );
      JRD.AddPair('rule_line', TJSONNumber.Create(RD.RuleLine));
      JRD.AddPair('line'     , TJSONNumber.Create(RD.Line    ));
      JResolved.AddElement(JRD);
    end;
    JRoot.AddPair('resolved_defaults', JResolved);
    JRoot.AddPair('glyphs', GlyphsJson(ACtx.Report.Glyphs));

    { unlinked_source_properties / unlinked_source_property_sites / unlinked[]
      -- row 6 steps 1-3, complete (2026-09-16). Step 1 shipped the two
      integers alone, keyed by property NAME, so a number existed before a
      design did; measured 2 distinct / 22 sites on ORM3 VARINSP, and the
      converter team's own test was "2 is a warning, 200 is a report".

      Now derived from Report.Unlinked, which is keyed by (SOURCE TYPE,
      property) -- their refinement (a): with one #convert block the two keys
      agree, with two blocks two source types both dropping 'Style' must be two
      rows. The counts keep their step-1 names and meaning (rows, and the sum of
      their sites), so a consumer written against step 1 still parses; the
      array is additive and carries the per-row fraction their refinement (b)
      asked for, '2 of 20 instances', as sites/instances.

      The matching warnings are in warnings[]/items[] as kind
      'unlinked-source-property' unless --no-warn-unlinked; this block is
      emitted either way, so silencing the warning never loses the count.

      The denominator that matters is properties PRESENT IN THE SOURCE .dfm --
      which is exactly what the reemit Dropped list holds -- never the source
      type's surface. TabcToggleBtn has 3,905 proptree leaves and sets about
      nine per button; counting the surface would be the flood they warned of. }
    var UnlinkedTotal: Integer:= 0;
    var JUnlinked: TJSONArray:= TJSONArray.Create;
    for var U: TApplyUnlinked in ACtx.Report.Unlinked do
    begin
      Inc(UnlinkedTotal, U.Sites);
      var JU: TJSONObject:= TJSONObject.Create;
      JU.AddPair('from_type', U.FromType);
      JU.AddPair('path'     , U.Path);
      JU.AddPair('sites'    , TJSONNumber.Create(U.Sites));
      JU.AddPair('instances', TJSONNumber.Create(U.Instances));
      JUnlinked.AddElement(JU);
    end;
    JRoot.AddPair('unlinked_source_properties', TJSONNumber.Create(Length(ACtx.Report.Unlinked)));
    JRoot.AddPair('unlinked_source_property_sites', TJSONNumber.Create(UnlinkedTotal));
    { 1.26.0 (C8 N2 review): the code sites NOT rewritten because the index
      could not tie them to the converted field (items[] access-site-unverified) }
    var Unverified: Integer:= 0;
    for var UIt: TApplyItem in ACtx.Report.Items do
      if UIt.Kind = aikAccessSiteUnverified then Inc(Unverified);
    JRoot.AddPair('access_sites_unverified', TJSONNumber.Create(Unverified));
    JRoot.AddPair('unlinked', JUnlinked);

    { 1.20.6 -- the unit rules. component_part says whether the #convert /
      .dfm part ran; uses[] has one row per uses-clause change a unit rule
      made (action remove|add, unit, section interface|implementation, line in
      the unit as read, rule as normalised from the book), and the two counts
      sum it by action. Always present, [] / 0 when the book has no unit
      rules, like every other array here. The #convert blocks' own uses-add is
      NOT a row: it is surface #2 and is counted in edits_count as before. }
    JRoot.AddPair('component_part', ACtx.ComponentPart);
    var UsesRemoved: Integer:= 0;
    var UsesAdded  : Integer:= 0;
    var UsesKept   : Integer:= 0;
    var UsesMoved  : Integer:= 0;
    var JUses: TJSONArray:= TJSONArray.Create;
    for var UC: TUsesChange in ACtx.Report.UsesChanges do
    begin
      if UC.Action = 'remove' then Inc(UsesRemoved)
      else if UC.Action = 'add' then Inc(UsesAdded) { 'skipped' (C13 N4) is neither }
      else if UC.Action = 'kept' then Inc(UsesKept)
      else if UC.Action = 'moved' then Inc(UsesMoved);
      var JUC: TJSONObject:= TJSONObject.Create;
      JUC.AddPair('action' , UC.Action);
      JUC.AddPair('unit'   , UC.UnitName);
      JUC.AddPair('section', UC.Section);
      JUC.AddPair('line'   , TJSONNumber.Create(UC.Line));
      JUC.AddPair('rule'   , UC.Rule);
      JUC.AddPair('reason' , UC.Reason); { '' unless skipped (C13 N4) or kept (C9) }
      { 1.27.0 (C9) -- additive: who asked (rule | reconcile | convert) and why
        the row exists (kept: the .dfm components; reconcile add: the
        introduced names; remove: the .pas references left dangling) }
      JUC.AddPair('source' , UC.Source);
      var JNeed: TJSONArray:= TJSONArray.Create;
      for var N: TUsesNeed in UC.NeededBy do
      begin
        var JN: TJSONObject:= TJSONObject.Create;
        JN.AddPair('name'   , N.Name);
        JN.AddPair('line'   , TJSONNumber.Create(N.Line));
        JN.AddPair('section', N.Section);
        JNeed.AddElement(JN);
      end;
      JUC.AddPair('needed_by', JNeed);
      JUses.AddElement(JUC);
    end;
    JRoot.AddPair('uses', JUses);
    JRoot.AddPair('uses_removed', TJSONNumber.Create(UsesRemoved));
    JRoot.AddPair('uses_added'  , TJSONNumber.Create(UsesAdded));
    { 1.27.0 (C9) -- ALWAYS present, like every array here }
    JRoot.AddPair('uses_kept'   , TJSONNumber.Create(UsesKept));
    JRoot.AddPair('uses_moved'  , TJSONNumber.Create(UsesMoved));
    var JUnres: TJSONArray:= TJSONArray.Create;
    for var UU: TUsesUnresolved in ACtx.Report.UsesUnresolved do
    begin
      var JU: TJSONObject:= TJSONObject.Create;
      JU.AddPair('name'   , UU.Name);
      JU.AddPair('line'   , TJSONNumber.Create(UU.Line));
      JU.AddPair('section', UU.Section);
      JU.AddPair('reason' , UU.Reason);
      var JC: TJSONArray:= TJSONArray.Create;
      for var C: TUsesCandidate in UU.Candidates do
      begin
        var JCO: TJSONObject:= TJSONObject.Create;
        JCO.AddPair('unit', C.UnitName);
        JCO.AddPair('db'  , C.Db);
        JC.AddElement(JCO);
      end;
      JU.AddPair('candidates', JC);
      JUnres.AddElement(JU);
    end;
    JRoot.AddPair('uses_unresolved', JUnres);
    JRoot.AddPair('uses_reconcile', ACtx.UsesReconcile);
    var JRx: TJSONObject:= TJSONObject.Create;
    JRx.AddPair('status' , ACtx.Reindex.Status);
    JRx.AddPair('db'     , ACtx.Reindex.Db);
    JRx.AddPair('project', ACtx.Reindex.Project);
    JRx.AddPair('ms'     , TJSONNumber.Create(ACtx.Reindex.Ms));
    JRx.AddPair('reason' , ACtx.Reindex.Reason);
    JRoot.AddPair('uses_reindex', JRx);
    { 1.27.0 -- what the .pas still uses that the conversion map does not
      cover: one row per (instance, member) reached through a converted
      instance, then one per global from a unit the reconciliation removes.
      ALWAYS present, [] when none. status mapped | cast-refused | same-name |
      unmapped | global-dangling; the editor filters on it. }
    JRoot.AddPair('pas_uses', PasUsesJson(ACtx.Report.PasUses, ACtx.RulesFile));
    { 1.20.6 (T2b) -- the classes whose members the run resolved, summed over
      the --db stores. No property tree is built; this is the whole cost. }
    JRoot.AddPair('classes_built', TJSONNumber.Create(ACtx.ClassesBuilt));

    { 1.20.6 (T2h, owner ruling R12, JSON shape R13) -- one OBJECT per rule path
      through a member that exists but is inaccessible on the .dfm surface
      (see UnreachableJson for the keys). ALWAYS present, [] when none.
      warnings[] above stays an array of STRINGS and carries each object's
      message too, so a consumer reading only warnings[] still sees them. }
    JRoot.AddPair('unreachable', UnreachableJson(DistinctUnreachable(ACtx.Unreachable)));

    { 1.22.0 (C8 N1) -- one OBJECT per inherited / inline .dfm object of a From
      type (1.26.0: and per code-only use of a converted ancestor's field):
      action retyped | code | skipped; ancestor_state unconverted | converted |
      mismatched | outside, ancestor_unit '' when not known. ALWAYS present, [] when none;
      warnings[] carries each one's 'line N: warning:' text too, and items[]
      its kind inherited-instance-skipped mirror. }
    var JInh: TJSONArray:= TJSONArray.Create;
    for var Inh: TInheritedInstance in ACtx.InheritedInsts do
    begin
      var JI: TJSONObject:= TJSONObject.Create;
      JI.AddPair('name'          , Inh.Name);
      JI.AddPair('type'          , Inh.TypeName);
      JI.AddPair('line'          , TJSONNumber.Create(Inh.Line));
      JI.AddPair('ancestor_unit' , Inh.AncestorUnit);
      JI.AddPair('ancestor_state', Inh.AncestorState);
      JI.AddPair('reason'        , Inh.Reason);
      JI.AddPair('action'        , Inh.Action); { 1.26.0 (C8 N2): retyped | code | skipped }
      JInh.AddElement(JI);
    end;
    JRoot.AddPair('inherited', JInh);

    { 1.25.0 -- one OBJECT per (descendant unit, converted instance) the
      descendant still streams (.dfm) or uses (code): reason dfm | code | both,
      line in the descendant .dfm, else its first code reference. ALWAYS
      present, [] when none; warnings[] carries each one's 'line N: warning:'
      text too, and items[] its kind descendant-not-converted mirror. }
    var JDesc: TJSONArray:= TJSONArray.Create;
    for var Desc: TDescendantUse in ACtx.Descendants do
    begin
      var JD: TJSONObject:= TJSONObject.Create;
      JD.AddPair('unit'  , Desc.UnitName);
      JD.AddPair('name'  , Desc.Name);
      JD.AddPair('type'  , Desc.TypeName);
      JD.AddPair('line'  , TJSONNumber.Create(Desc.Line));
      JD.AddPair('reason', Desc.Reason);
      JDesc.AddElement(JD);
    end;
    JRoot.AddPair('descendants', JDesc);

    { 1.23.0 (C13 N3) -- ALWAYS present, [] without --only. }
    JRoot.AddPair('only_matched'  , ArrOf(ACtx.OnlyMatched));
    JRoot.AddPair('only_unmatched', ArrOf(ACtx.OnlyUnmatched));
    { 1.25.1 -- ALWAYS present, [] without --only: one (name, parent) object per object
      --only did not name that converts because a kept parent contains it }
    var JInc: TJSONArray:= TJSONArray.Create;
    for var NO: TNestedOnly in ACtx.OnlyIncluded do
    begin
      var JN: TJSONObject:= TJSONObject.Create;
      JN.AddPair('name'  , NO.Instance.InstanceName);
      JN.AddPair('parent', NO.Parent);
      JInc.AddElement(JN);
    end;
    JRoot.AddPair('only_included', JInc);
    { owner ruling 2026-10-11 -- ALWAYS present, [] when every #convert class
      resolved without inference: one object per ambiguous #convert line, with
      the ready-to-paste qualified lines the editor offers as a one-click fix }
    var JFixes: TJSONArray:= TJSONArray.Create;
    for var QF: TQualifyFix in ACtx.QualifyFixes do
    begin
      var JF: TJSONObject:= TJSONObject.Create;
      JF.AddPair('rule_line', TJSONNumber.Create(QF.RuleLine));
      JF.AddPair('current'  , QF.Current);
      JF.AddPair('name'     , QF.Name);
      JF.AddPair('side'     , QF.Side);
      JF.AddPair('outcome'  , QF.Outcome);
      JF.AddPair('chosen'   , QF.Chosen);
      JF.AddPair('inference', QF.Inference);
      var JSug: TJSONArray:= TJSONArray.Create;
      for var QS: TQualifySuggestion in QF.Suggestions do
      begin
        var JS: TJSONObject:= TJSONObject.Create;
        JS.AddPair('replacement', QS.Replacement);
        JS.AddPair('candidate'  , QS.Candidate);
        JS.AddPair('why'        , QS.Why);
        JS.AddPair('alternative', QS.Alternative);
        JSug.AddElement(JS);
      end;
      JF.AddPair('suggestions', JSug);
      JF.AddPair('alternative', QF.Alternative);
      JFixes.AddElement(JF);
    end;
    JRoot.AddPair('qualify_fixes', JFixes);

    if Assigned(ACtx.Sink) then
    begin
      ACtx.Sink.AddElement(JRoot); { batch mode: the array owns it now }
      JRoot:= nil;
    end
    else
      WriteStdoutDocument(JRoot.ToJSON + sLineBreak); // after every stderr byte (T2i R18)
  finally
    JRoot.Free;
  end;
end; // procedure

{ 1.20.6: which part of a convert-apply book runs on a unit -- the value of
  apply/1's component_part. 'applied' (BuildApplyPlan runs the whole book)
  unless the book has UNIT rules and its component part has nothing to act
  on: 'skipped-no-dfm', 'skipped-no-convert-rules' (no #convert block) or
  'skipped-no-instances' (no .dfm instance a block matches, after --only). A
  book with no unit rules is 'applied', so its old errors stand -- unless the
  .dfm holds inherited / inline instances of a From type (AHasInherited, C8
  N1): those are skipped and reported, so a .dfm with no OTHER instance is
  'skipped-no-instances' and converts nothing rather than failing -- unless
  one of them is retyped or a converted ancestor's field is used in code
  (AHasRetype, C8 N2 / N2a, 1.26.0): then BuildApplyPlan runs, 'applied'. }
function ConvertApplyComponentPart(const ARules: TConversionRuleSet; const ADfmPath: string;
  const AOnly: TArray<string>; AHasInherited, AHasRetype: Boolean): string;
var
  R         : TConversionRule;
  HasConvert: Boolean;
begin
  Result:= 'applied';
  if not BookHasUnitRules(ARules) and not AHasInherited then Exit;
  HasConvert:= False;
  for R in ARules.Rules do
    if R.Kind = rkConvert then HasConvert:= True;
  if not TFile.Exists(ADfmPath) then
    Result:= 'skipped-no-dfm'
  else if not HasConvert then
    Result:= 'skipped-no-convert-rules'
  else if (Length(FindConvertInstances(ReadUnitText(ADfmPath), ARules, AOnly)) = 0) and
          not AHasRetype then
    Result:= 'skipped-no-instances';
end;

end.
