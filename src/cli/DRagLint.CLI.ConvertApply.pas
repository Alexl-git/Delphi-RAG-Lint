unit DRagLint.CLI.ConvertApply;

// ---------------------------------------------------------------------------
// The convert-apply verb: book validation, encoding guard, rollback, the post-apply re-index and the batch.
// Moved verbatim out of DRagLint.CLI.Convert (lane v1511 SPLIT, T07; that unit alone was over 2,000 lines).
// ---------------------------------------------------------------------------

interface

uses
  DRagLint.CLI.Common;

/// <summary>drag-lint convert-apply --unit F.pas --rules FILE --db PATH [--db ...]
/// [--only Name1,Name2,...] [--apply] [--no-backup] [--no-warn-unlinked] [--format json] -- Track 3 sub-project B: locates the
/// component instances to convert in the sibling .dfm and rewrites all five surfaces
/// (#1 declaration retype, #2 uses-add, #3 .dfm re-emit, #4 property/event access-site
/// rewrite via ref-gap G's member-access index, #5 runtime-creator retype + TODO markers).
/// Without --apply this
/// is DRY-RUN ONLY (RenderDryRun preview, writes nothing). With --apply (Task 4) it actually writes:
/// a freshness guard runs first (CheckFreshness -- refuses on stale/unindexed F or T
/// types), then each touched file is backed up to its next-free NAME.EXT.BCK&lt;n&gt;
/// (DRagLint.Convert.Backup.BackupFiles) and a recovery.txt block is appended BEFORE the
/// conversion write (WriteRecoveryRecord), then the edits are written
/// (TTextEditApplier.Apply(..., AWriteBackups:=False) -- our own backup layer already
/// backed up, so the applier must NOT also write its own .bak), then the converted .pas
/// is stamped with a provenance comment (PrependConvertComment). --no-backup skips the
/// backup/recovery/comment steps entirely (still converts). --unit reuses GhostUnit (same
/// --unit -> non-document-command routing as ghost-check; see ParseArgs) and --only reuses
/// OnlySections (same comma-split TArray&lt;string&gt; already used by `index --all`).</summary>
/// <param name="AArgs">GhostUnit=--unit (the .pas file to convert); RulesFile=--rules;
/// OnlySections=--only (comma-split instance-name allow-list); Apply=--apply; NoBackup=
/// --no-backup; NoWarnUnlinked=--no-warn-unlinked (silences the per-(source type, property)
/// unlinked warnings; the json count and unlinked[] stay); DbPath/DbPaths=index(es).</param>
/// <returns>0 on success (dry-run preview shown, or --apply wrote successfully); 1 on a
/// hard error (missing .dfm when rules need it, invalid rules, BuildApplyPlan Ok=False, or
/// --apply refused by the freshness guard -- a stale or unindexed type of any block; a deliberate
/// refusal -- a #convert type that resolves in no --db (C13 d: an index gap, refused on dry run and
/// --apply alike, before any rule error), a unit-rules {$IF...} uses entry, any
/// TApplyResult.Refusal -- goes through RefuseUnit: 'REFUSED: <reason>', apply/1 refused=true,
/// reason, nothing written); 2 on bad args (missing --unit/--rules, file not
/// found, no readable db (an explicit --db that is missing or stale is exit 2)).</returns>
/// <exception cref="EConvertApplyWrite"><!-- drag-lint:auto exc -->cannot write %s: the file is read-only -- unit not changed, nothing written; cannot write %s: %s -- unit not changed, nothing written; write failed for %s: %s: %s -- rolled back, unit not changed; write failed for %s: %s: %s -- rollback FAILED for %s: the unit may be PARTLY converted; %s</exception>
/// <remarks>
/// Resolves the sibling .dfm as the same base name + '.dfm' next to --unit;
/// missing .dfm is a hard error (exit 1) for a book with NO unit rules, since every #convert
/// rule needs DFM instances to locate. A book with unit rules (#unuse / #use / #useswap,
/// 1.20.6) applies them to the unit's uses clauses (PlanUnitRules) -- alone when there is no
/// .dfm, no #convert block or no matching instance (json component_part says which),
/// otherwise folded into BuildApplyPlan's plan; a unit whose entry to remove sits in a
/// conditional region is refused (exit 1, nothing written). Every readable --db is opened
/// up front into Stores (not just the first; a stale explicit --db exits 2 here, before
/// any rule is checked). The .dfm is then read (FindInheritedInstances, 1.22.0, C8 N1/N3): an
/// inherited/inline object of a From type is NOT converted and no longer refuses the unit -- it
/// is skipped and reported with its declaring ancestor (apply/1 inherited[] {name, type, line,
/// ancestor_unit, ancestor_state unconverted|converted|mismatched|outside, reason, action}, a 'line N: warning:'
/// line in warnings[], items[] kind inherited-instance-skipped), while the unit's own instances,
/// code and unit rules convert; R26 counts it as left unconverted. One whose ancestor already has
/// the To type is RETYPED instead (1.26.0, C8 N2: action retyped), and a converted ancestor's field
/// used only in code joins the access-site rewrite (N2a, FindInheritedCodeUses: action code). Rules are then validated (ValidateConvertBook)
/// BEFORE BuildApplyPlan runs -- EVERY block against its OWN From/To classes, each path resolved
/// segment by segment (1.20.6, T2b: no property tree is built, so validating the whole book is
/// cheap and ruling R5's per-unit scope and --validate-all-blocks are gone), and a #mapping
/// against the block(s) that #apply it; a block whose type resolves in no --db REFUSES the unit
/// (C13 d, UnresolvedReason); a BARE #convert type resolves in the unit's own scope (the unit,
/// its last uses entry declaring it, a lone unit-level declarer -- never a nested class, never
/// the first class of that name), and one that scope cannot settle REFUSES the unit naming the
/// candidates (AmbiguousReason: qualify the #convert line) -- and a rules error refuses (exit 1) rather than attempting a plan
/// from a broken rule set. A #link / #default / #mapping path whose members all exist but one
/// is inaccessible on the .dfm surface is NOT an error (T2h, owner ruling R12): it is skipped
/// per block (WithoutUnreachableRules, inside each re-emit -- a #link / #default line is dropped,
/// a #mapping keeps its branch order and loses only the unreachable targets, and a mapping whose
/// #when source is unreachable is skipped whole), the unit converts everything else, and each is reported
/// -- apply/1 unreachable[] objects, the same text in warnings[] / items[]
/// (rule-path-unreachable), and a text-mode 'line N: warning: ...' line under Warnings. Validation and BuildApplyPlan share one TConvertTreeCache, so each
/// class's members are resolved once per run (json classes_built). The freshness guard
/// (CheckFreshness, every block) and BuildApplyPlan both
/// resolve From/To TYPES across ALL of Stores (first-that-resolves-wins), while unit/
/// instance-scoped lookups use whichever store actually has --unit/the .dfm indexed -- the
/// From type, To type, and the form's own instances may each live in a DIFFERENT --db. On
/// dry-run a stale/unindexed type only WARNS (the preview still renders), on --apply it
/// REFUSES (exit 1) before any write is attempted. A book whose #link carries a glyph
/// expression validates but is REFUSED here (exit 1, through the rule-error path) until
/// CV-2 realises G-links (UnrealisedGlyphLinks) -- never carried whole.
/// 1.33.0 (CONVERTER G2): a --unit whose .pas NO supplied --db indexes is REFUSED (exit 1,
/// reason 'not covered by any supplied --db'), dry run and --apply, single and batch alike --
/// it used to plan its unit rules and skip every instance, so --apply half-converted it.
/// G3: every apply/1 object carries exit_code (that unit's). G1: --progress writes one
/// stderr JSON line per finished unit ({"progress":{"verb":"convert-apply","unit_done",
/// "units","unit","ok","refused","exit_code"}}, flushed); stdout is unchanged by it.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.RunCommand (DRagLint.CLI.pas)</para>
/// <para>Calls: AmbiguousReason, AppendDescendantReport, AppendInheritedReport, BackupFiles, BookChainWarnings, BookScopeKey, BoolToStr, BuildApplyPlan, BuildUnitRulesOnlyPlan, CheckFreshness (+67 more)</para>
/// <para>Returns: FailUnit(Format('sibling .dfm not found: %s (every #convert rule needs .dfm instances to locate)', [DfmPath]), 1); Code; 1; 0; 2; RunUnit(Units[0])</para>
/// <para>Complexity: 40 (cyclomatic, outer body), 873 lines (full implementation)</para>
/// <para>Catches: Exception (raises EConvertApplyWrite); Exception (swallowed)</para>
/// <para>Touches: file system</para>
/// <seealso cref="DRagLint.CLI.Common.ExplicitDbsExist"/>
/// <seealso cref="DRagLint.CLI.Common.OpenReadOnlyStore"/>
/// <seealso cref="DRagLint.CLI.Common.StaleDbRefusesRun"/>
/// <seealso cref="DRagLint.CLI.Common.WriteStdoutDocument"/>
/// <seealso cref="DRagLint.CLI.ConsumerDbs.ResolveConsumerDbs"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function DoConvertApply(const AArgs: TArgs): Integer;

implementation

uses
  DRagLint.Core.Model, DRagLint.CLI.ConsumerDbs, DRagLint.Core.FileTime, Winapi.Windows, System.SysUtils,
  System.Classes, System.IOUtils, DRagLint.Core.Versions, System.NetEncoding, System.JSON, System.StrUtils,
  System.DateUtils, System.Generics.Collections, System.Generics.Defaults, System.SyncObjs, System.Math,
  System.Character, Data.DB, FireDAC.Comp.Client, FireDAC.Stan.Async, FireDAC.Stan.Param, FireDAC.DApt,
  TreeSitter, DRagLint.Core.Interfaces, DRagLint.Refactor.TextEdit, DRagLint.Convert.Rules,
  DRagLint.Convert.CastLib, DRagLint.Convert.Apply, DRagLint.Convert.Backup, DRagLint.Convert.UnitRules,
  DRagLint.CLI.Convert, DRagLint.CLI.ConvertApplyJson;

{ 1.20.6 (Task 2, T2b): the From/To classes of EVERY #convert block,
  index-aligned for ValidateConversionRulesPerBlock ([0] = the region before
  the first #convert, left unset). Each side comes from ATrees (ClassFor), shared
  with BuildApplyPlan, so each class's members are resolved once per run and only
  when a path asks for them.
  A block whose From or To type resolves in no --db goes to AUnresolved (its
  #convert line, the type in Message) -- an unset side would skip every check
  of the block and pass it silently (ruling R7). C13 d: that is an INDEX gap,
  not a rule-book error, so the caller refuses the unit on it (UnresolvedReason).
  A BARE type resolves in ATrees' SetScope unit (ScopedClass, the pas_uses[]
  rule, then inference -- owner ruling 2026-10-11). One settled by INFERENCE, and
  one still ambiguous, each add a TQualifyFix to AFixes (the #convert line from
  ARuleLines): 'inferred' converts with a warning, 'refused' is never guessed --
  the caller refuses the unit (AmbiguousReason). }
function BuildBlockClasses(ATrees: TConvertTreeCache; const ARules: TConversionRuleSet;
  const ARuleLines: TArray<string>; AUnresolved: TList<TRuleError>; AFixes: TList<TQualifyFix>): TArray<TBlockClasses>;
var
  R    : TConversionRule;
  Block: Integer;

  procedure RequireResolved(const AConv: TConversionRule; const AType, ASide: string);
  var
    E: TRuleError;
  begin
    if AType = '' then Exit;
    var Scoped: TScopedClass:= ATrees.ScopedClass(AType);
    var Text  : string:= if (AConv.LineNo >= 1) and (AConv.LineNo <= Length(ARuleLines)) then ARuleLines[AConv.LineNo - 1]
                         else Format('#convert %s -> %s', [AConv.FromType, AConv.ToType]);
    if (Scoped.Resolution = PAS_RES_AMBIGUOUS) or (Scoped.Inferred <> '') then
      AFixes.Add(MakeQualifyFix(Text, AConv.LineNo, AType, ASide, Scoped));
    if Scoped.Resolution <> PAS_RES_CLASS_NOT_FOUND then Exit;
    E        := Default(TRuleError);
    E.LineNo := AConv.LineNo;
    E.Message:= AType;
    AUnresolved.Add(E);
  end;

begin
  SetLength(Result, 1);
  Block:= 0;
  for R in ARules.Rules do
    if R.Kind = rkConvert then
    begin
      Inc(Block);
      SetLength(Result, Block + 1);
      RequireResolved(R, R.FromType, 'from');
      RequireResolved(R, R.ToType, 'to');
      Result[Block].FromClass:= ATrees.ClassFor(R.FromType);
      Result[Block].ToClass  := ATrees.ClassFor(R.ToType);
    end;
end;

{ 1.20.6: convert-apply's rule check. EVERY #convert block is validated against
  its own classes (ValidateConversionRulesPerBlock, classes from ATrees; T2b
  reverted ruling R5's per-unit scope, because resolving a path no longer costs
  a tree), a block whose type resolves nowhere comes back in AUnresolved (C13 d:
  the caller REFUSES the unit, see UnresolvedReason), a bare type the scope left
  ambiguous in AFixes (refused or inferred, see BuildBlockClasses), and a #link carrying a glyph expression is refused
  (UnrealisedGlyphLinks) unless AGlyphStitch, which checks its class has an N reader instead. A path through a member that exists but is
  inaccessible is not an error: it comes back in AUnreachable (T2h, owner
  ruling R12), one record per block it is unreachable in -- print through
  DistinctUnreachable, filter per block through WithoutUnreachableRules. }
function ValidateConvertBook(ATrees: TConvertTreeCache; const ARules: TConversionRuleSet; const ARuleLines: TArray<string>; AGlyphStitch: Boolean;
  out AUnreachable: TArray<TUnreachablePath>; out AUnresolved: TArray<TRuleError>;
  out AFixes: TArray<TQualifyFix>): TArray<TRuleError>;
var
  TypeErrs: TList<TRuleError>;
  Fixes   : TList<TQualifyFix>;
  Classes : TArray<TBlockClasses>;
begin
  TypeErrs:= TList<TRuleError>.Create;
  Fixes   := TList<TQualifyFix>.Create;
  try
    Classes    := BuildBlockClasses(ATrees, ARules, ARuleLines, TypeErrs, Fixes);
    AUnresolved:= TypeErrs.ToArray;
    AFixes     := Fixes.ToArray;
    Result     := ValidateConversionRulesPerBlock(ARules, Classes, AUnreachable);
    Result     := Result + (if AGlyphStitch then MissingGlyphCountReaders(ARules, Classes) else UnrealisedGlyphLinks(ARules));
  finally
    Fixes.Free;
    TypeErrs.Free;
  end;
end;

{ Owner ruling 2026-10-11: the REFUSED reason for bare #convert types the unit's
  scope and inference cannot settle -- every 'refused' fix's QualifyRefusalText
  (the line, the name, each candidate and why, what to do), joined. '' when
  AFixes holds none. }
function AmbiguousReason(const AFixes: TArray<TQualifyFix>): string;
begin
  var Parts: TArray<string>:= nil;
  for var F: TQualifyFix in AFixes do
    if F.Outcome = 'refused' then Parts:= Parts + [QualifyRefusalText(F)];
  Result:= String.Join('; ', Parts);
end;

{ The scope key of a book's #convert classes in ATrees' current unit: every
  block's From and To as ScopedClass resolves them (an inference included).
  Two units with the same key validate identically, so a batch validates the
  book once per distinct key. }
function BookScopeKey(ATrees: TConvertTreeCache; const ARules: TConversionRuleSet): string;
begin
  Result:= '';
  for var R: TConversionRule in ARules.Rules do
    if R.Kind = rkConvert then
      for var T: string in [R.FromType, R.ToType] do
      begin
        var S: TScopedClass:= ATrees.ScopedClass(T);
        Result:= Result + S.Resolution + ':' + S.QName + ':' + String.Join(',', S.Candidates) + ':' +
          S.Inferred + ':' + String.Join(',', S.Why) + ';';
      end;
end;
{ C13 d (owner ruling 2026-10-06): the REFUSED reason for #convert types that
  resolve in no --db. Each is '<Type> (line N)', the block's #convert line; the
  text says it is an index gap (library or project index), never a rule-book
  error, because the converter cannot convert a type it cannot see. }
function UnresolvedReason(const AUnresolved: TArray<TRuleError>): string;
var
  Parts: TArray<string>;
  U    : TRuleError;
begin
  Parts:= nil;
  for U in AUnresolved do Parts:= Parts + [Format('%s (line %d)', [U.Message, U.LineNo])];
  Result:= Format('%s %s in no --db -- index gap in the library or project index; reindex, or report it, before converting',
    [String.Join(', ', Parts), if Length(Parts) = 1 then 'resolves' else 'resolve']);
end;

{ 1.25.1 (the DMREADINGS defect): a plan the edit applier would refuse in
  part fails the WHOLE unit before anything is written. TTextEditApplier.Apply
  works file by file and refuses one file's edits whole on overlapping delete
  ranges -- after the .pas has already been written -- so a unit came out
  half-converted with exit 0. Checked on the dry run too, so the preview
  fails exactly as --apply would: Ok=False, exit 1, nothing written. }
{ 1.25.1: True when two byte arrays hold the same bytes. }
function SameBytes(const A, B: TBytes): Boolean;
begin
  Result:= (Length(A) = Length(B)) and ((Length(A) = 0) or CompareMem(@A[0], @B[0], Length(A)));
end;

{ 1.25.1: the backup file BackupFiles made for APath ('orig -> backup'
  lines), or '' when none was made (--no-backup). }
function BackupOf(const AMappings: TArray<string>; const APath: string): string;
const
  MAP_ARROW = ' -> ';
begin
  for var M: string in AMappings do
  begin
    var At: Integer:= Pos(MAP_ARROW, M);
    if (At > 0) and SameText(Copy(M, 1, At - 1), APath) then Exit(Copy(M, At + Length(MAP_ARROW), MaxInt));
  end;
  Result:= '';
end;

{ 1.25.1 (all-or-nothing, write half): puts every file of a unit back the way
  it was before a write that failed part-way. AOriginals[I] is AFiles[I] as read
  just before the write; a file still holding those bytes is left alone, any
  other is rewritten from its .BCK backup when one was made, else from
  AOriginals, and then re-read and compared. Returns the files that could NOT
  be restored byte-identical ([] = rolled back). Never raises.
  TEST SEAM: DRAGLINT_TEST_FAIL_ROLLBACK=1 makes every restore fail, so the
  rollback-failed report can be exercised (run_convert_apply_atomic.ps1). }
function RollBackUnitFiles(const AFiles: TArray<string>; const AOriginals: TArray<TBytes>;
  const AMappings: TArray<string>): TArray<string>;
const
  TEST_FAIL_ROLLBACK = 'DRAGLINT_TEST_FAIL_ROLLBACK';
var
  Src: TBytes;
begin
  Result:= nil;
  for var I: Integer:= 0 to High(AFiles) do
    try
      if SameBytes(TFile.ReadAllBytes(AFiles[I]), AOriginals[I]) then Continue;
      if GetEnvironmentVariable(TEST_FAIL_ROLLBACK) = '1' then
        raise EInOutError.CreateFmt('%s=1: simulated restore failure', [TEST_FAIL_ROLLBACK]);
      var Bck: string:= BackupOf(AMappings, AFiles[I]);
      Src:= if (Bck <> '') and TFile.Exists(Bck) then TFile.ReadAllBytes(Bck) else AOriginals[I];
      TFile.WriteAllBytes(AFiles[I], Src);
      if not SameBytes(TFile.ReadAllBytes(AFiles[I]), AOriginals[I]) then Result:= Result + [AFiles[I]];
    except
      on Exception do Result:= Result + [AFiles[I]];
    end;
end;

{ 1.26.0 (C8 N2 review): the REFUSED reason when the --db that indexes AUnitPas
  had its edges derived by a resolver older than convert-apply's access-site
  scoping needs (E5 field binds, resolver 1.12.0), or carries no resolver stamp
  -- '' otherwise. On such a DB a field read is left unbound, and the rewrite
  would skip it as unverifiable: refusing is the honest answer, dry run and
  --apply alike. The text names the DB and the exact re-derive command. }
function ResolverRefusal(const AStores: TArray<ISymbolStore>; const ADbs: TArray<string>;
  const AUnitPas: string): string;
const
  MIN_RESOLVER = '1.12.0-alpha';
var
  Holders: TArray<Integer>;
begin
  Result:= '';
  { 1.26.5: the DBs that hold the unit, found the way its symbols are found
    (UnitFileIdIn) -- a DB copied with a moved tree stores the OLD paths, and
    the exact-path match this used to make found none and skipped the check
    in silence. When still none holds it, every non-library --db is checked:
    the guard is never skipped. }
  Holders:= nil;
  for var I: Integer:= 0 to High(AStores) do
    if (I <= High(ADbs)) and (UnitFileIdIn(AStores[I], AUnitPas) > 0) then Holders:= Holders + [I];
  if Length(Holders) = 0 then
    for var I: Integer:= 0 to High(AStores) do
      if (I <= High(ADbs)) and not SameText(AStores[I].GetMetaValue(SCAN_TYPE_KEY), SCAN_TYPE_LIBRARY) then Holders:= Holders + [I];
  for var I: Integer in Holders do
  begin
    var Ver: string:= ResolverVersionOfFingerprint(AStores[I].GetMetaValue(RESOLVER_FP_KEY));
    if (Ver <> '') and (CompareDottedVersions(Ver, MIN_RESOLVER) >= 0) then Continue;
    Exit(Format('%s: edges were derived by resolver %s; convert-apply needs %s or newer (bound field reads) -- re-derive first: drag-lint %s',
      [ADbs[I], if Ver <> '' then Ver else '(none)', MIN_RESOLVER, IndexRemedyFor(AStores[I], ADbs[I], {AResolveOnly=}True)]));
  end;
end;

{ 1.34.1 (CONV-ENC E2): the path half of one --raise-encoding "<path>=<level>" entry. }
function RaiseEntryPath(const AEntry: string): string;
begin
  var Eq: Integer:= LastDelimiter('=', AEntry);
  Result:= if Eq > 0 then Copy(AEntry, 1, Eq - 1) else AEntry;
end;

{ 1.34.1: the level half of one --raise-encoding entry ('' when it has no '='). }
function RaiseEntryLevel(const AEntry: string): string;
begin
  var Eq: Integer:= LastDelimiter('=', AEntry);
  Result:= if Eq > 0 then Copy(AEntry, Eq + 1, MaxInt) else '';
end;

{ 1.34.1: True when two paths name the same file (case-insensitive, expanded). }
function SameFilePath(const A, B: string): Boolean;
begin
  Result:= SameText(ExpandFileName(A), ExpandFileName(B));
end;

{ 1.34.1 (CONV-ENC E2): the exit-2 message for a bad --raise-encoding entry of this
  run, or '' when every entry is well formed: the level must be utf8-bom, and the path
  must be one of AUnits or the sibling .dfm of one. }
function RaiseEncodingError(const AEntries, AUnits: TArray<string>): string;
begin
  Result:= '';
  for var E: string in AEntries do
  begin
    if not SameText(RaiseEntryLevel(E), ENC_RAISE_LEVEL) then
      Exit(Format('raise-encoding: "%s" is not a supported level for %s (only %s)', [RaiseEntryLevel(E), RaiseEntryPath(E), ENC_RAISE_LEVEL]));
    var Known: Boolean:= False;
    for var U: string in AUnits do
      if SameFilePath(RaiseEntryPath(E), U) or SameFilePath(RaiseEntryPath(E), TPath.ChangeExtension(U, '.dfm')) then Known:= True;
    if not Known then Exit(Format('raise-encoding: %s is not a file of this run', [RaiseEntryPath(E)]));
  end;
end;

{ 1.34.1: True when --raise-encoding names APath. }
function IsRaisedFile(const AEntries: TArray<string>; const APath: string): Boolean;
begin
  for var E: string in AEntries do
    if SameFilePath(RaiseEntryPath(E), APath) then Exit(True);
  Result:= False;
end;

{ 1.34.1 (CONV-ENC E1'/E3): the encoding guard for one unit's plan, run on the dry run and
  --apply alike, nothing written. The .pas is checked before the .dfm. A file named by
  --raise-encoding is skipped (UTF-8 holds every character). A TEXT .dfm: its edits' string
  literals get Delphi #codes for what its encoding cannot hold (AEdits is rewritten); a
  character it cannot hold OUTSIDE a literal (an identifier: class, property, enum value),
  where DFM syntax has no #code, refuses like a .pas (lane H, 2026-10-26). A binary .dfm is never compared (one line appended to AWarnings). For a .pas
  whose encoding cannot hold a value, ACtx gets the refusal (RefusalKind and Enc*) and the
  reason text is returned; '' means the unit may proceed. }
function EncodingGuardReason(const AArgs: TArgs; const AUnitPas, ADfm: string;
  var AEdits: TArray<TTextEdit>; var AReport: TApplyReport; var ACtx: TApplyJsonCtx): string;
const
  MAX_CHARS = 8;
var
  OldText: string;
begin
  Result:= '';
  for var Path: string in [AUnitPas, ADfm] do
  begin
    if (Path = '') or not TFile.Exists(Path) then Continue;
    var Values: TArray<string>:= nil;
    for var E: TTextEdit in AEdits do
      if SameText(E.FilePath, Path) and (E.Text <> '') then Values:= Values + [E.Text];
    if Length(Values) = 0 then Continue;
    var IsDfm: Boolean:= SameText(ExtractFileExt(Path), '.dfm');
    var Bytes: TBytes:= TFile.ReadAllBytes(Path);
    if IsDfm and IsBinaryDfmFile(Bytes) then
    begin
      var It: TApplyItem:= Default(TApplyItem);
      It.Kind    := aikEncodingNotChecked;
      It.Field   := afWarnings;
      It.FilePath:= Path;
      It.Text    := Format('%s is a binary .dfm: its encoding was not checked', [Path]);
      AReport.Warnings:= AReport.Warnings + [It.Text];
      AReport.Items   := AReport.Items + [It];
      Continue;
    end;
    if IsRaisedFile(AArgs.RaiseEncoding, Path) then Continue;
    var Fmt: TTextFileFormat:= TTextFileFormat.Decode(Bytes, OldText);
    if Fmt.Encoding <> TEncoding.ANSI then Continue;
    var Where: string:= '';
    if IsDfm then
    begin
      Values:= nil;
      for var I: Integer:= 0 to High(AEdits) do
        if SameText(AEdits[I].FilePath, Path) then
        begin
          AEdits[I].Text:= EscapeUnfitForDfm(AEdits[I].Text, Fmt.Encoding);
          Values:= Values + [AEdits[I].Text];
        end;
      Where:= ' outside a string literal, where a #code is not allowed,';
    end;
    var Codes: TArray<Integer>:= UnfitCodePoints(Fmt, Values);
    if Length(Codes) = 0 then Continue;
    var Edited: string:= TTextEditApplier.ApplyToText(Path, OldText, AEdits);
    ACtx.EncChars:= nil;
    var Parts: TArray<string>:= nil;
    for var K: Integer:= 0 to Min(High(Codes), MAX_CHARS - 1) do
    begin
      var Mf: TEncodingMisfit;
      Mf.Code:= Codes[K];
      Mf.Text:= TCharacter.ConvertFromUtf32(Codes[K]);
      Mf.Line:= FirstLineOfCodePoint(Edited, Codes[K]);
      ACtx.EncChars:= ACtx.EncChars + [Mf];
      Parts:= Parts + [Format('U+%.4X line %d', [Mf.Code, Mf.Line])];
    end;
    ACtx.RefusalKind:= 'encoding_refused';
    ACtx.EncFile    := Path;
    ACtx.EncName    := TextFileEncodingName(Fmt);
    ACtx.EncTotal   := Length(Codes);
    Exit(Format('encoding: %d character(s)%s do not fit %s (%s): %s -- raise the file to UTF-8 with BOM, or skip the unit',
      [Length(Codes), Where, Path, ACtx.EncName, String.Join(', ', Parts)]));
  end;
end;

procedure RefuseUnapplicablePlan(var APlan: TApplyResult);
var
  Refusal: string;
begin
  if not APlan.Ok then Exit;
  Refusal:= TTextEditApplier.RefusalOf(APlan.Edits);
  if Refusal = '' then Exit;
  APlan.Ok   := False;
  APlan.Error:= Refusal + ' -- unit not changed, nothing written';
end;

{ 1.27.0 (C9): the index a convert-apply --apply refreshes for AUnitPas, and
  why not when it does not -- Status 'dry-run' with Db / Project set, 'off'
  (--no-reindex, --no-reconcile-uses) or 'skipped' with Reason. THE GUARANTEE:
  only a --db of this run that (a) indexes the unit, (b) is a PROJECT index
  (scan_type) and (c) holds exactly one project file (.dproj, else .dpr) is
  ever chosen -- the unit's own project DB. Two holders, a library holder, or
  none: skipped, nothing written. }
function ReindexPreview(const AStores: TArray<ISymbolStore>; const ADbs: TArray<string>;
  const AUnitPas: string; const AArgs: TArgs): TUsesReindex;
var
  Holders: TArray<Integer>;
  Proj   : TArray<string>;
begin
  Result:= Default(TUsesReindex);
  if AArgs.NoReindex or AArgs.NoReconcileUses then
  begin
    Result.Status:= 'off';
    Exit;
  end;
  Result.Status:= 'skipped';
  Holders:= nil;
  for var I: Integer:= 0 to High(AStores) do
    if (I <= High(ADbs)) and (UnitFileIdIn(AStores[I], AUnitPas) > 0) then Holders:= Holders + [I];
  if Length(Holders) <> 1 then
  begin
    Result.Reason:= if Length(Holders) = 0 then 'no --db indexes the unit'
                    else Format('%d --db indexes hold the unit -- refusing to guess which is its project DB', [Length(Holders)]);
    Exit;
  end;
  var St: ISymbolStore:= AStores[Holders[0]];
  Result.Db:= ADbs[Holders[0]];
  if not SameText(St.GetMetaValue(SCAN_TYPE_KEY), SCAN_TYPE_PROJECT) then
  begin
    Result.Reason:= Format('%s is not a project index (scan_type "%s")', [Result.Db, St.GetMetaValue(SCAN_TYPE_KEY)]);
    Exit;
  end;
  for var Ext: string in ['.dproj', '.dpr'] do
    if Length(Proj) = 0 then
      for var FS: TFileStamp in St.GetAllFileStamps do
        if SameText(ExtractFileExt(FS.Path), Ext) then Proj:= Proj + [FS.Path];
  if Length(Proj) <> 1 then
  begin
    Result.Reason:= Format('%s holds %d project files -- cannot name the one to re-index', [Result.Db, Length(Proj)]);
    Exit;
  end;
  Result.Project:= Proj[0];
  Result.Status := 'dry-run';
end;

type
  { 1.23.0 (C13): a unit's --apply write cannot be done (a read-only or locked
    file, or a failure mid-write); DoConvertApply turns it into that unit's
    failure, exit 2 }
  EConvertApplyWrite = class(Exception);

{ 1.42 (CONVAPPLY-INHERITED): True when two unit lists are the same paths in
  the same order (case-insensitive) }
function SameUnitOrder(const AA, AB: TArray<string>): Boolean;
begin
  Result:= Length(AA) = Length(AB);
  if not Result then Exit;
  for var I: Integer:= 0 to High(AA) do
    if not SameText(AA[I], AB[I]) then Exit(False);
end;

{ 1.42: the units' file names, comma-separated, for the text-mode order note }
function UnitNamesJoined(const AUnits: TArray<string>): string;
begin
  Result:= '';
  for var U: string in AUnits do
    Result:= Result + (if Result = '' then '' else ', ') + ExtractFileName(U);
end;

{ 1.42 (CONVAPPLY-INHERITED): the batch's apply/1 objects put back into --unit
  order. ABatch holds them in RUN order, unit I's objects at
  ASliceStart[I] .. ASliceStart[I + 1] - 1; ARunOrder is a permutation of
  ACmdOrder (a repeated path is matched to its occurrences in turn). Returns
  nil when the orders agree, else a NEW array of clones the caller owns;
  ABatch is never freed here. }
function ReorderBatchJson(const ABatch: TJSONArray; const ASliceStart: TArray<Integer>;
  const ARunOrder, ACmdOrder: TArray<string>): TJSONArray;
var
  Used: TArray<Boolean>;
  Done: Boolean;
begin
  if SameUnitOrder(ARunOrder, ACmdOrder) then Exit(nil);
  SetLength(Used, Length(ARunOrder));
  Done  := False;
  Result:= TJSONArray.Create;
  try
    for var C: string in ACmdOrder do
      for var R: Integer:= 0 to High(ARunOrder) do
        if not Used[R] and SameText(ARunOrder[R], C) then
        begin
          Used[R]:= True;
          for var J: Integer:= ASliceStart[R] to ASliceStart[R + 1] - 1 do
            Result.AddElement(ABatch.Items[J].Clone as TJSONValue);
          Break;
        end;
    Done:= True;
  finally
    if not Done then FreeAndNil(Result);
  end;
end;

function DoConvertApply(const AArgs: TArgs): Integer;
var
  UnitPas   : string            ;
  DfmPath   : string            ;
  RulesText : string            ;
  Rules     : TConversionRuleSet;
  RuleErrors: TArray<TRuleError>;
  Unresolved: TArray<TRuleError>;
  QualifyFixes: TArray<TQualifyFix>; { bare #convert types refused or inferred (owner ruling 2026-10-11) }
  Trees     : TConvertTreeCache ; { one per run: validation and BuildApplyPlan share its member caches }
  Dbs       : TArray<string>    ;
  Stores    : TArray<ISymbolStore>;
  RoOk      : Boolean           ;
  LDb       : string            ;
  PlanRes   : TApplyResult      ;
  Freshness   : TFreshnessResult;
  { 1.23.0 (C13 b2) batch state: every --unit; the book checks done once
    (RunUnit); the apply/1 collector under batch JSON (nil otherwise) }
  Units          : TArray<string>;
  BookChecked    : Boolean;
  BookKey        : string;  { BookScopeKey of the unit the book was last validated for }
  FreshChecked   : Boolean;
  BookUnreachable: TArray<TUnreachablePath>;
  BatchJson      : TJSONArray;
  BookBuilt      : Integer; { classes the book validation built (C13: per-unit classes_built) }
  CastLib        : TCastLib; { 1.33.1: parsed ONCE before any unit runs; a configuration error fails the whole batch (exit 6) }
  { --format json / --json. Both are parsed globally (ParseArgs), so this verb
    only has to READ them. Under JSON every Writeln on the success and failure
    paths is suppressed -- one stray line and the document stops parsing. }
  UseJson     : Boolean         ;
  JCtx        : TApplyJsonCtx   ;

  // The --apply write sequence. Nested so its five working variables
  // (TouchedFiles/TouchedSet/Ed/Timestamp/Mappings) live here instead of in
  // DoConvertApply's var block, which was already at the 25-local limit.
  procedure PerformApplyWrites;
  var
    TouchedFiles: TList<string>;
    TouchedSet  : TDictionary<string, Boolean>;
    Ed          : TTextEdit;
    Timestamp   : string;
    Mappings    : TArray<string>;
    Originals   : TArray<TBytes>; { 1.25.1: each touched file's bytes before the write, for the rollback }
  begin
    { 1.20.6: a unit-rules-only run that changes nothing writes nothing -- no
      backup, no recovery record, no provenance stamp on an untouched unit, so
      a book run over many units leaves the ones it does not touch
      byte-identical. The component path keeps its historical behaviour. }
    if (JCtx.ComponentPart <> 'applied') and (Length(PlanRes.Edits) = 0) then Exit;
    // 1. Collect the distinct touched file paths from the edit set.
    TouchedFiles:= TList<string>.Create;
    TouchedSet  := TDictionary<string, Boolean>.Create(TIStringComparer.Ordinal); { F7: UnitPas and an edit's path may differ in case }
    try
      for Ed in PlanRes.Edits do
        if not TouchedSet.ContainsKey(Ed.FilePath) then
        begin TouchedSet.Add(Ed.FilePath, True); TouchedFiles.Add(Ed.FilePath); end;

      { 1.34.1 (CONV-ENC E2): a file named by --raise-encoding joins the set even when no
        edit touches it, so it is pre-checked, backed up and rolled back with the rest }
      for var RE: string in AArgs.RaiseEncoding do
      begin
        var RPath: string:= RaiseEntryPath(RE);
        if (SameFilePath(RPath, UnitPas) or SameFilePath(RPath, JCtx.DfmPath)) and TFile.Exists(RPath)
          and not TouchedSet.ContainsKey(RPath) then
        begin
          TouchedSet.Add(RPath, True);
          TouchedFiles.Add(RPath);
        end;
      end;

      Timestamp:= FormatDateTime('yyyy-mm-dd hh:nn:ss', NowLocal);

      { F7 (2026-10-25): step 4 stamps the .pas even when no edit touches it (a
        .dfm-only conversion), so it joins the set HERE -- pre-checked, backed
        up, in recovery.txt and named in the stamp's "backup:" field. Under
        --no-backup there is no stamp, so it is not written and not checked. }
      if not AArgs.NoBackup and not TouchedSet.ContainsKey(UnitPas) then
      begin
        TouchedSet.Add(UnitPas, True);
        TouchedFiles.Add(UnitPas);
      end;

      // 1b. (1.23.0, C13) Every touched file must be writable BEFORE anything
      // is written: the applier writes file by file, so a read-only or locked
      // .pas found mid-way would leave the .dfm converted and the .pas not.
      // A refusal here leaves the unit byte-identical, with no .BCK and no
      // recovery record. (A failure AFTER this check -- a lock taken in
      // between, a full disk -- is ROLLED BACK since 1.25.1: see step 3.)
      for var F: string in TouchedFiles do
      begin
        if TFileAttribute.faReadOnly in TFile.GetAttributes(F) then
          raise EConvertApplyWrite.CreateFmt('cannot write %s: the file is read-only -- unit not changed, nothing written', [F]);
        try
          TFileStream.Create(F, fmOpenReadWrite or fmShareExclusive).Free;
        except
          on Ex: Exception do
            raise EConvertApplyWrite.CreateFmt('cannot write %s: %s -- unit not changed, nothing written', [F, Ex.Message]);
        end;
      end;

      // 2. Backup + recovery record BEFORE any conversion write. Writing the
      // recovery record first means a crash between here and the actual write
      // still leaves a complete recovery map alongside the untouched .BCK files.
      if not AArgs.NoBackup then
      begin
        BackupFiles(TouchedFiles.ToArray, Mappings);
        WriteRecoveryRecord(ExtractFileDir(UnitPas), Timestamp, AArgs.RulesFile, Mappings);
      end;

      { 1.25.1: the unit's files as they are now -- the .pas too, which step 4
        stamps even when it carries no edit -- so a failed write rolls back }
      if not TouchedSet.ContainsKey(UnitPas) then TouchedFiles.Add(UnitPas);
      Originals:= nil;
      for var F: string in TouchedFiles do Originals:= Originals + [TFile.ReadAllBytes(F)];
      try
        { 1.34.1 (E2): re-store each raised file as UTF-8 with a BOM first; the applier and
          the stamp below then keep that format. A binary .dfm is never rewritten. }
        for var RE: string in AArgs.RaiseEncoding do
          for var F: string in TouchedFiles do
            if SameFilePath(RaiseEntryPath(RE), F) and not IsBinaryDfmFile(TFile.ReadAllBytes(F)) then
              TFile.WriteAllBytes(F, RaiseBytesToUtf8Bom(TFile.ReadAllBytes(F)));
        // 3. Perform the conversion write. AWriteBackups=False: our backup layer
        // (step 2) already backed up every touched file -- letting the applier
        // ALSO write its own .bak would double-backup.
        TTextEditApplier.Apply(PlanRes.Edits, False);

        // 4. Stamp the converted .pas with a provenance comment (skipped along
        // with backups under --no-backup, per the brief: keep --no-backup simple).
        if not AArgs.NoBackup then
          PrependConvertComment(UnitPas, Timestamp, AArgs.RulesFile, Mappings);
      except
        on Ex: Exception do
        begin
          { 1.25.1: all-or-nothing -- a write that fails part-way is ROLLED
            BACK, every file of the unit restored byte-identical. Only a
            rollback that itself fails leaves the unit partly converted, and
            then the files it could not restore are named. }
          var NotRestored: TArray<string>:= RollBackUnitFiles(TouchedFiles.ToArray, Originals, Mappings);
          if Length(NotRestored) = 0 then
            raise EConvertApplyWrite.CreateFmt('write failed for %s: %s: %s -- rolled back, unit not changed',
              [ExtractFileName(UnitPas), Ex.ClassName, Ex.Message]);
          raise EConvertApplyWrite.CreateFmt('write failed for %s: %s: %s -- rollback FAILED for %s: the unit may be PARTLY converted; %s',
            [ExtractFileName(UnitPas), Ex.ClassName, Ex.Message, String.Join(', ', NotRestored),
             if AArgs.NoBackup then 'no backup was taken (--no-backup)'
             else 'restore it from the .BCK backups recorded in recovery.txt']);
        end;
      end;
    finally
      TouchedFiles.Free;
      TouchedSet.Free;
    end;
  end;

  // 1.20.6 (T2h, owner ruling R12): each UNREACHABLE rule path becomes one more
  // warnings[] line -- its whole 'line N: warning: ...' text -- and its items[]
  // mirror (kind rule-path-unreachable, the rules file and line), so Report
  // invariant 1 holds. The structured facts are JCtx.Unreachable.
  procedure MergeUnreachable(var AReport: TApplyReport);
  var
    It: TApplyItem;
    U : TUnreachablePath;
  begin
    for U in DistinctUnreachable(JCtx.Unreachable) do
    begin
      It         := Default(TApplyItem);
      It.Kind    := aikRulePathUnreachable;
      It.Field   := afWarnings;
      It.FilePath:= AArgs.RulesFile;
      It.Path    := U.Path;
      It.Text    := U.Message;
      It.Line    := U.LineNo;
      It.RuleLine:= U.LineNo;
      AReport.Warnings:= AReport.Warnings + [U.Message];
      AReport.Items   := AReport.Items + [It];
    end;
  end;

  // 1.37.0 (CHAIN H3): the book's single-pass warnings (a chain, a duplicate
  // From type) join warnings[] as plain text, beside the unreachable and
  // inferred ones; they never change the exit code.
  procedure MergeBookChain(var AReport: TApplyReport);
  begin
    for var W: TRuleError in BookChainWarnings(Rules) do
      AReport.Warnings:= AReport.Warnings + [Format('line %d: warning: %s', [W.LineNo, W.Message])];
  end;

  // Owner ruling 2026-10-11: each #convert class settled by INFERENCE becomes
  // one warnings[] line (QualifyInferredText) and its items[] mirror (kind
  // convert-class-inferred); the structured row is JCtx.QualifyFixes.
  procedure MergeInferred(var AReport: TApplyReport);
  begin
    for var QF: TQualifyFix in JCtx.QualifyFixes do
      if QF.Outcome = 'inferred' then
      begin
        var It: TApplyItem:= Default(TApplyItem);
        It.Kind    := aikConvertClassInferred;
        It.Field   := afWarnings;
        It.FilePath:= AArgs.RulesFile;
        It.Path    := QF.Name;
        It.Text    := QualifyInferredText(QF);
        It.Line    := QF.RuleLine;
        It.RuleLine:= QF.RuleLine;
        AReport.Warnings:= AReport.Warnings + [It.Text];
        AReport.Items   := AReport.Items + [It];
      end;
  end;

  // Owner ruling 2026-10-11: text mode, after a refusal -- every suggested
  // replacement line, ready to paste over the rules file's line.
  procedure PrintQualifyFixes;
  begin
    for var QF: TQualifyFix in JCtx.QualifyFixes do
      if QF.Outcome = 'refused' then
      begin
        Writeln(Format('  line %d of %s -- replace "%s" with one of:', [QF.RuleLine, AArgs.RulesFile, QF.Current]));
        for var QS: TQualifySuggestion in QF.Suggestions do
          Writeln(Format('    %s    { %s }', [QS.Replacement, QS.Why]));
        Writeln(Format('  or: %s', [QF.Alternative]));
      end;
  end;

  // 1.20.6 (T2f): the ONE exit for a deliberate refusal. JSON: ok=false,
  // refused=true, reason (and error) = AReason. Text: one 'REFUSED: ' line.
  // Nothing has been written when this is called. Exit(RefuseUnit(S)).
  function RefuseUnit(const AReason: string): Integer;
  begin
    JCtx.Ok     := False;
    JCtx.Error  := AReason;
    JCtx.Refused:= True; { set in text mode too: the batch summary counts it }
    JCtx.Reason := AReason;
    if UseJson then
      EmitApplyJson(JCtx)
    else
      Writeln('REFUSED: ' + AReason);
    Result:= 1;
  end;

  // 1.20.6: one line saying the component part was skipped, and why; nothing
  // when it ran. Text mode only -- JSON carries component_part.
  procedure PrintComponentPart;
  begin
    if JCtx.ComponentPart = 'skipped-no-dfm' then
      Writeln('dfm: none -- component part skipped, unit rules only')
    else if JCtx.ComponentPart = 'skipped-no-convert-rules' then
      Writeln('no #convert block in the book -- component part skipped, unit rules only')
    else if JCtx.ComponentPart = 'skipped-no-instances' then
      Writeln('no .dfm instance matches a #convert block -- component part skipped, unit rules only');
  end;

  // 1.33.1: the castlib configuration error, the same text for every unit.
  // Exit 6 = a CONFIGURATION error (1.28.0); 2 means a write failure / rollback.
  const EXIT_CASTLIB_UNUSABLE = 6;

  function CastLibFailure: string;
  begin
    Result:= Format('castlib %s: %s', [AArgs.CastLibFile, String.Join('; ', CastLib.Errors)]);
  end;

  // ERROR: <AMsg> for one unit -- text, or under batch JSON an apply/1 object
  // with ok=false -- and AExit as that unit's exit code.
  function FailUnit(const AMsg: string; AExit: Integer): Integer;
  begin
    if UseJson then
    begin
      JCtx.Ok   := False;
      JCtx.Error:= AMsg;
      EmitApplyJson(JCtx);
    end
    else
      Writeln('ERROR: ' + AMsg);
    Result:= AExit;
  end;

  // 1.23.0 (C13 b2): ONE unit's whole run -- its sibling .dfm, plan, writes and
  // report -- against the shared Rules / Stores / Trees. The book is validated
  // (and its freshness checked) the FIRST time a unit reaches that step, then
  // reused: a single --unit run keeps its old order, a batch pays for both and
  // for every class's members once. Returns the unit's exit code (0 / 1 / 2).
  function RunUnit(const AUnitPas: string): Integer;  // dl:ok too-many-exit-points@ab98, cyclomatic-complexity@eae5, method-too-long@9bf6, cognitive-complexity@4135 -- (lint sweep b0bad3cf..HEAD): the branch count and length are that same early-outcome chain; splitting it is a convert-apply refactor, not a sweep fix. Each Exit is a distinct per-unit outcome (refusal incl. an unindexed unit (1.33.0), rule errors, freshness, an unexecutable castlib (1.27.0), plan failure, write failure, dry run) moved from DoConvertApply, which carried the same shape; one result per early outcome is the convert-apply contract (REVIEWED 2026-11-18 INT13: re-measured after 1.52 GA-1 counts if-expressions; shape and reason unchanged)
  var
    UnitStart: Integer; { Trees.ClassesBuilt when this unit started }
    ValHere  : Integer; { classes this unit's call to the book validation built (0 after the first) }
    OnlyEff  : TArray<string>; { this unit's instance allow-list: --only, or --only-type expanded against its .dfm }

    { apply/1 classes_built for THIS unit: the book's validation set plus what
      this unit's own run added -- what a single-unit run of it reports }
    function UnitClassesBuilt: Integer;
    begin
      Result:= BookBuilt + (Trees.ClassesBuilt - UnitStart) - ValHere;
    end;

    { C8 N2 / N2a: an inherited[] entry this run converts -- retyped or code }
    function HasRetype: Boolean;
    begin
      for var Inh: TInheritedInstance in JCtx.InheritedInsts do
        if (Inh.Action = INH_ACTION_RETYPED) or (Inh.Action = INH_ACTION_CODE) then Exit(True);
      Result:= False;
    end;

    { C8 N2a: a --only name that names no .dfm object but a code-only entry
      is MATCHED -- the split is redone in --only order }
    procedure MatchCodeOnlyNames;
    var
      Matched, Unmatched: TArray<string>;
    begin
      Matched  := nil;
      Unmatched:= nil;
      for var N: string in OnlyEff do
      begin
        var IsCode: Boolean:= False;
        for var Inh: TInheritedInstance in JCtx.InheritedInsts do
          if (Inh.Action = INH_ACTION_CODE) and SameText(Inh.Name, N) then IsCode:= True;
        if IsCode or MatchText(N, JCtx.OnlyMatched) then Matched:= Matched + [N]
        else Unmatched:= Unmatched + [N];
      end;
      JCtx.OnlyMatched  := Matched;
      JCtx.OnlyUnmatched:= Unmatched;
    end;

  begin
    UnitStart:= Trees.ClassesBuilt;
    ValHere  := 0;
    UnitPas:= AUnitPas;
    PlanRes:= Default(TApplyResult);
    JCtx   := Default(TApplyJsonCtx);
    JCtx.Mode:= if AArgs.Apply then 'apply' else 'dry-run';
    JCtx.RulesFile:= AArgs.RulesFile;
    JCtx.Freshness.Fresh:= True;
    JCtx.Sink   := BatchJson;
    JCtx.UnitPas:= UnitPas;
    { 1.33.1: an unusable castlib refuses EVERY unit of the batch, before anything else is looked at }
    if Length(CastLib.Errors) > 0 then Exit(FailUnit(CastLibFailure, EXIT_CASTLIB_UNUSABLE));
    if not TFile.Exists(UnitPas) then Exit(FailUnit(Format('unit not found: %s', [UnitPas]), 2));
    { a bare #convert / .dfm class name resolves in THIS unit's scope }
    Trees.SetScope(UnitPas, Rules);
    { 1.26.0: a DB whose edges predate bound field reads is refused, dry run too }
    var StaleResolver: string:= ResolverRefusal(Stores, Dbs, UnitPas);
    if StaleResolver <> '' then Exit(RefuseUnit(StaleResolver));
    { 1.33.0 (CONVERTER G2): a unit no --db indexes cannot locate one instance,
      yet its unit rules would still be written -- a half conversion. REFUSED,
      dry run and --apply, single and batch alike (as C13 d's index gap).
      UnitFileIdIn resolves a moved tree's unit the way its symbols are found. }
    var Indexed: Boolean:= False;
    for var St: ISymbolStore in Stores do
      if UnitFileIdIn(St, UnitPas) > 0 then Indexed:= True;
    if not Indexed then
      Exit(RefuseUnit(Format('%s is not covered by any supplied --db (%s) -- index its project, then re-run; nothing was planned',
        [UnitPas, String.Join(', ', Dbs)])));
    // Sibling .dfm: same base name + '.dfm', same folder as --unit.
    DfmPath:= TPath.ChangeExtension(UnitPas, '.dfm');
    JCtx.DfmPath:= DfmPath;
    { wave 148 CV (C12 N5): --only-type expands to this unit's instance names }
    OnlyEff:= AArgs.OnlySections;
    if Length(AArgs.OnlyTypes) > 0 then
      ExpandOnlyTypes(if TFile.Exists(DfmPath) then ReadUnitText(DfmPath) else '',
        Rules, AArgs.OnlyTypes, OnlyEff, JCtx.OnlyMatched, JCtx.OnlyUnmatched);
    { C13 N3: which --only names name an object of a #convert From type }
    if Length(AArgs.OnlySections) > 0 then
      SplitOnlyNames(if TFile.Exists(DfmPath) then ReadUnitText(DfmPath) else '',
        Rules, OnlyEff, JCtx.OnlyMatched, JCtx.OnlyUnmatched);
    { 1.25.1: a kept parent's nested From-type children convert with it
      (the --only unmatched line is printed below, once C8 N2a's code-only
      names have been matched) }
    if (Length(OnlyEff) > 0) and TFile.Exists(DfmPath) then
      JCtx.OnlyIncluded:= NestedOnlyInstances(ReadUnitText(DfmPath), Rules, OnlyEff);
    if not UseJson then
      for var NO: TNestedOnly in JCtx.OnlyIncluded do
        Writeln(Format('--only: %s converts too -- nested in %s', [NO.Instance.InstanceName, NO.Parent]));
    { 1.20.6: a missing .dfm is fatal only to a book with NO unit rules -- its
      #convert blocks have nothing to locate. A book with #unuse / #use /
      #useswap still has the unit's uses clauses to change, so it runs them and
      reports the component part as skipped (component_part skipped-no-dfm). }
    if not TFile.Exists(DfmPath) and not BookHasUnitRules(Rules) and not BookHasIdentifierMigrates(Rules) then
    begin
      var NothingWhy: string:= BookNothingToDoReason(Rules, UnitPas);
      if NothingWhy <> '' then Exit(FailUnit(NothingWhy, 1));
      Exit(FailUnit(Format('sibling .dfm not found: %s (every #convert rule needs .dfm instances to locate)', [DfmPath]), 1));
    end;

    { 1.22.0 (C8 N1, N3; replaces 1.20.6's ruling-R6 refusal). Inherited /
      inline .dfm objects of a From type are declared by an ANCESTOR, so they
      are skipped -- each reported with its declaring ancestor (apply/1
      inherited[], a 'line N: warning:' line) -- while the unit's own
      instances, code and unit rules convert. R26 still counts them as left
      unconverted, so a #unuse that would break them refuses the unit. }
    JCtx.InheritedInsts:= FindInheritedInstances(Trees, UnitPas, DfmPath, Rules, OnlyEff);
    { 1.26.0 (C8 N2a): fields a converted ancestor declares that this unit's
      code uses with no .dfm block -- inherited[] action 'code'. A --only name
      that names one counts as matched. }
    JCtx.InheritedInsts:= JCtx.InheritedInsts +
      FindInheritedCodeUses(Trees, UnitPas, Rules, OnlyEff, JCtx.InheritedInsts);
    if (Length(JCtx.OnlyUnmatched) > 0) and (Length(AArgs.OnlyTypes) = 0) then MatchCodeOnlyNames;
    if (Length(JCtx.OnlyUnmatched) > 0) and (Length(AArgs.OnlyTypes) > 0) and not UseJson then
      Writeln('--only-type: no #convert instance of type ' + String.Join(', ', JCtx.OnlyUnmatched) + ' (ignored)')
    else if (Length(JCtx.OnlyUnmatched) > 0) and not UseJson then
      Writeln('--only: no #convert instance named ' + String.Join(', ', JCtx.OnlyUnmatched) + ' (ignored)');
    { EVERY block is validated against its OWN From/To classes (1.20.6, Task 2
      and T2b) -- driven from the rules file's own #convert headers rather than
      --from/--to (convert-apply has neither). It used to take the first block's
      pair for the whole book, so every link of blocks 2..N failed. A valid
      G-expression passes validation, but nothing realises it yet (CV-2):
      refuse through the same path rather than carry the source image whole. }
    { the book's classes resolve in each unit's scope: a unit whose #convert
      classes resolve differently from the last one validated is validated
      again (BookScopeKey); a batch of like units still validates once }
    var ScopeKey: string:= BookScopeKey(Trees, Rules);
    if not BookChecked or (ScopeKey <> BookKey) then
    begin
      BookChecked:= True;
      BookKey    := ScopeKey;
      ValHere    := Trees.ClassesBuilt;
      RuleErrors := ValidateConvertBook(Trees, Rules, RulesText.Replace(#13#10, #10).Replace(#13, #10).Split([#10]), AArgs.GlyphStitch,
        BookUnreachable, Unresolved, QualifyFixes);
      ValHere    := Trees.ClassesBuilt - ValHere;
      BookBuilt  := BookBuilt + ValHere;
    end;
    JCtx.Unreachable := BookUnreachable;
    JCtx.QualifyFixes:= QualifyFixes;
    JCtx.ClassesBuilt:= UnitClassesBuilt;
    { T2h: an UNREACHABLE path warns and its rule is skipped (BuildApplyPlan
      below gets the book without those lines); it never fails the unit. On
      every JSON exit from here on, warnings[] carries the messages too. }
    MergeUnreachable(JCtx.Report);
    MergeInferred(JCtx.Report);
    MergeBookChain(JCtx.Report);
    { C13 d: a type no --db resolves is an index gap -- the unit is REFUSED,
      dry run and --apply alike, before any rule error is reported }
    if Length(Unresolved) > 0 then Exit(RefuseUnit(UnresolvedReason(Unresolved)));
    { a bare #convert type this unit's scope cannot settle is REFUSED, never
      validated against a guessed class }
    var Ambiguity: string:= AmbiguousReason(QualifyFixes);
    if Ambiguity <> '' then
    begin
      var Code: Integer:= RefuseUnit(Ambiguity);
      if not UseJson then PrintQualifyFixes;
      Exit(Code);
    end;
    if Length(RuleErrors) > 0 then
    begin
      { A JSON consumer gets a parseable ok=false document naming every rule
        error, rather than prose on stdout that its parser would choke on. }
      if UseJson then
      begin
        JCtx.Ok        := False;
        JCtx.Error     := 'conversion rules failed validation';
        JCtx.RuleErrors:= RuleErrors;
        EmitApplyJson(JCtx);
        Exit(1);
      end;
      Writeln('ERROR: conversion rules failed validation:');
      for var RE: TRuleError in RuleErrors do Writeln(Format('  line %d: %s', [RE.LineNo, RE.Message]));
      for var UW: string in JCtx.Report.Warnings do Writeln('  ' + UW);
      Exit(1);
    end;
    // Freshness guard (Task 4): before trusting the index-derived class
    // members, verify the F and T types of every block are indexed and current. Covers two
    // failure modes -- "stale" (indexed but the source file changed on disk
    // since) and "not indexed at all" (ResolveClassQName-equivalent lookup
    // fails, which would otherwise silently hand BuildPropTree an empty tree).
    // dry-run: WARN and continue (so a user can still preview a plan while
    // reindexing). --apply: REFUSE outright -- writing a conversion built from
    // a stale/empty property tree could silently drop or mis-map properties.
    if not FreshChecked then
    begin
      FreshChecked:= True;
      Freshness   := CheckFreshness(Stores, Rules);
    end;
    { B-18 (1.31.7): the unit's OWN .pas and .dfm too -- per unit, never cached.
      A stale target warns on a dry run (merged into freshness) and REFUSES
      --apply below; a stale From/To type keeps its own error path. }
    var UnitFresh: TFreshnessResult:= CheckUnitFreshness(Stores, UnitPas, DfmPath);
    JCtx.Freshness:= Freshness;
    if not UnitFresh.Fresh then
    begin
      JCtx.Freshness.Fresh  := False;
      JCtx.Freshness.Reasons:= JCtx.Freshness.Reasons + UnitFresh.Reasons;
    end;
    if not Freshness.Fresh then
    begin
      if AArgs.Apply then
      begin
        { --apply refuses. Under JSON the reasons ride in freshness.reasons, so
          the consumer sees WHY without parsing prose. }
        if UseJson then
        begin
          JCtx.Ok   := False;
          JCtx.Error:= 'freshness guard failed -- refusing to --apply';
          EmitApplyJson(JCtx);
          Exit(1);
        end;
        Writeln('ERROR: freshness guard failed -- refusing to --apply:');
        for var S: string in Freshness.Reasons do Writeln('  ' + S);
        Exit(1);
      end
      else if not UseJson then
      begin
        { dry-run only warns. Under JSON the warning is NOT printed -- it is
          already carried structurally by freshness.fresh=false + reasons. }
        Writeln('WARNING: freshness guard failed (dry-run only, would refuse on --apply):');
        for var S: string in Freshness.Reasons do Writeln('  ' + S);
      end;
    end;
    if not UnitFresh.Fresh then
    begin
      if AArgs.Apply then Exit(RefuseUnit(UnitFresh.Reasons[0]));
      if not UseJson then
      begin
        Writeln('WARNING: freshness guard failed (dry-run only, would refuse on --apply):');
        for var S: string in UnitFresh.Reasons do Writeln('  ' + S);
      end;
    end;

    { 1.20.6: which parts of the book run on this unit. A book WITH unit rules
      runs them alone when its component part has nothing to act on -- no .dfm,
      no #convert block, or no .dfm instance a block matches; everywhere else
      BuildApplyPlan runs the whole book (its unit rules folded in). A book with
      no unit rules takes the old path unchanged, errors included. }
    JCtx.ComponentPart:= ConvertApplyComponentPart(Rules, DfmPath, OnlyEff,
      Length(JCtx.InheritedInsts) > 0, HasRetype);
    if JCtx.ComponentPart = 'skipped-no-dfm' then JCtx.DfmPath:= '';
    { 1.27.0 (C15): a castlib the engine cannot execute (an unknown value
      transform) fails the unit -- a cast silently not performed is the worse outcome.
      1.28.0 (owner 2026-10-11): its own exit code 6, a CONFIGURATION error; 2 means a
      write failure / rollback on this verb and must not be read as one. }
    { the castlib was parsed and validated once, before the unit loop (see CastLibFailure) }
    { 1.42 (MIG-TYPE): identifier #migrate rules act on the unit's CODE, so a
      unit with no .dfm, or none a #convert block matches, still runs
      BuildApplyPlan when it has a #migrate site; component_part keeps saying
      the component part was skipped. A missing .dfm gets here with no unit
      rules only because the book has identifier #migrate lines: with no site
      it keeps the old refusal. }
    var Book: TApplyBook:= TApplyBook.Create(Rules, JCtx.Unreachable);
    Book.Reconcile:= not AArgs.NoReconcileUses; { C9, default on }
    var IdSites: Boolean:= (JCtx.ComponentPart <> 'applied') or not TFile.Exists(DfmPath);
    IdSites:= IdSites and UnitHasIdentifierMigrateSites(Trees, UnitPas, Book);
    if (JCtx.ComponentPart = 'applied') and not TFile.Exists(DfmPath) then
    begin
      if not IdSites then
      begin
        var NothingWhy: string:= BookNothingToDoReason(Rules, UnitPas);
        if NothingWhy <> '' then Exit(FailUnit(NothingWhy, 1));
        Exit(FailUnit(Format('sibling .dfm not found: %s (every #convert rule needs .dfm instances to locate)', [DfmPath]), 1));
      end;
      JCtx.ComponentPart:= 'skipped-no-dfm';
      JCtx.DfmPath      := '';
    end;
    PlanRes:= if (JCtx.ComponentPart = 'applied') or IdSites then
                BuildApplyPlan(Trees, UnitPas, JCtx.DfmPath, Book,
                  OnlyEff, CastLib, not AArgs.NoWarnUnlinked, JCtx.InheritedInsts)
              else
                BuildUnitRulesOnlyPlan(Trees, UnitPas, JCtx.DfmPath, Rules, OnlyEff, not AArgs.NoReconcileUses);
    JCtx.UsesReconcile:= if AArgs.NoReconcileUses then 'off'
                         else if PlanRes.Report.UsesReconcile <> '' then PlanRes.Report.UsesReconcile
                         else 'on';
    JCtx.Reindex:= ReindexPreview(Stores, Dbs, UnitPas, AArgs);
    RefuseUnapplicablePlan(PlanRes); { 1.25.1: all-or-nothing across .pas and .dfm }
    JCtx.ClassesBuilt:= UnitClassesBuilt;
    if PlanRes.Refused then Exit(RefuseUnit(PlanRes.Error));
    if not PlanRes.Ok then
    begin
      if UseJson then
      begin
        JCtx.Ok   := False;
        JCtx.Error:= PlanRes.Error;
        EmitApplyJson(JCtx);
        Exit(1);
      end;
      Writeln('ERROR: ' + PlanRes.Error);
      Exit(1);
    end;

    { 1.34.1 (CONV-ENC E1'/E3): a value the target .pas cannot hold refuses the unit, dry
      run and --apply alike, nothing written; a text .dfm gets #codes instead }
    var EncReason: string:= EncodingGuardReason(AArgs, UnitPas, JCtx.DfmPath, PlanRes.Edits, PlanRes.Report, JCtx);
    if EncReason <> '' then Exit(RefuseUnit(EncReason));

    JCtx.Ok       := True;
    MergeUnreachable(PlanRes.Report); { text mode prints them in its Warnings block }
    MergeInferred(PlanRes.Report);    { likewise }
    MergeBookChain(PlanRes.Report);   { likewise }
    AppendInheritedReport(JCtx.InheritedInsts, DfmPath, PlanRes.Report); { likewise }
    { 1.25.0: descendants that still stream / use an instance converted here.
      A warning, never a refusal; only the instances the plan converted count. }
    if JCtx.ComponentPart = 'applied' then
    begin
      JCtx.Descendants:= FindDescendantUses(Trees, UnitPas, DfmPath, Rules,
        ConvertedInstancesOf(PlanRes.Report, DfmPath, Rules, OnlyEff));
      AppendDescendantReport(JCtx.Descendants, DfmPath, PlanRes.Report);
    end;
    JCtx.Report   := PlanRes.Report;
    JCtx.EditCount:= Length(PlanRes.Edits);

    if not AArgs.Apply then
    begin
      // DRY-RUN: writes nothing.
      if UseJson then
      begin
        { RenderDryRun and the summary are BOTH suppressed -- the edit plan is
          reported as edits_count, and the summary as the six arrays + items. }
        EmitApplyJson(JCtx);
        Exit(0);
      end;
      Writeln(TTextEditApplier.RenderDryRun(PlanRes.Edits));
      Writeln('');
      PrintComponentPart;
      PrintApplyReport(PlanRes.Report, Length(PlanRes.Edits), 'planned');
      Exit(0);
    end;

    { a write failure fails THIS unit (exit 2) instead of the run: a batch
      goes on with the next unit (see PerformApplyWrites for what is on disk) }
    try
      PerformApplyWrites;
    except
      on Ex: Exception do Exit(FailUnit(Ex.Message, 2));
    end;
    { C9: re-index after convert -- the unit's OWN project DB only }
    if (JCtx.ComponentPart <> 'applied') and (Length(PlanRes.Edits) = 0) and (JCtx.Reindex.Status = 'dry-run') then
    begin
      JCtx.Reindex.Status:= 'skipped';
      JCtx.Reindex.Reason:= 'nothing was written';
    end
    else if JCtx.Reindex.Status = 'dry-run' then
      RefreshProjectIndex(JCtx.Reindex);

    if UseJson then
      EmitApplyJson(JCtx)
    else
    begin
      PrintComponentPart;
      PrintApplyReport(PlanRes.Report, Length(PlanRes.Edits), 'applied');
    end;
    Result:= 0;
  end;

  // 1.23.0 (C13 b2): the apply-batch/1 wrapper -- one apply/1 object per unit,
  // in --unit order, plus the run's totals. exit_code is the worst unit's.
  procedure EmitBatchJson(AExit, AOk, ARefused: Integer);
  var
    JRoot: TJSONObject;
  begin
    JRoot:= TJSONObject.Create;
    try
      JRoot.AddPair('schema'       , 'apply-batch/1');
      JRoot.AddPair('mode'         , if AArgs.Apply then 'apply' else 'dry-run');
      JRoot.AddPair('rules_file'   , AArgs.RulesFile);
      JRoot.AddPair('units_count'  , TJSONNumber.Create(BatchJson.Count));
      JRoot.AddPair('ok'           , TJSONBool.Create(AOk = BatchJson.Count));
      JRoot.AddPair('exit_code'    , TJSONNumber.Create(AExit));
      JRoot.AddPair('ok_count'     , TJSONNumber.Create(AOk));
      JRoot.AddPair('refused_count', TJSONNumber.Create(ARefused));
      JRoot.AddPair('failed_count' , TJSONNumber.Create(BatchJson.Count - AOk - ARefused));
      JRoot.AddPair('classes_built', TJSONNumber.Create(Trees.ClassesBuilt));
      JRoot.AddPair('units'        , BatchJson);
      BatchJson:= nil; { JRoot owns it now }
      WriteStdoutDocument(JRoot.ToJSON + sLineBreak);
    finally
      JRoot.Free;
    end;
  end;

  // 1.33.0 (CONVERTER G3): exit_code on the apply/1 object(s) this unit
  // appended from index AFrom on (normally one) -- additive, last key.
  procedure StampUnitExit(AFrom, ACode: Integer);
  begin
    if not UseJson then Exit;
    for var K: Integer:= AFrom to BatchJson.Count - 1 do
      if BatchJson.Items[K] is TJSONObject then
        TJSONObject(BatchJson.Items[K]).AddPair('exit_code', TJSONNumber.Create(ACode));
  end;

  // 1.33.0 (CONVERTER G1): --progress -- one JSON line on STDERR per finished
  // unit, flushed now (stdout untouched; off by default -- see MakeProgressWriter).
  procedure ReportUnitProgress(AIndex, ACode: Integer);
  begin
    if not AArgs.UnitProgress then Exit;
    Writeln(ErrOutput, Format('{"progress":{"verb":"convert-apply","unit_done":%d,"units":%d,"unit":%s,' +
      '"ok":%s,"refused":%s,"exit_code":%d}}',
      [AIndex + 1, Length(Units), ProgressJsonStr(Units[AIndex]),
       BoolToStr(ACode = 0, True).ToLower, BoolToStr(JCtx.Refused, True).ToLower, ACode]));
    Flush(ErrOutput);
  end;

begin
  if not ExplicitDbsExist(AArgs, 'convert-apply') then Exit(2);
  UseJson:= AArgs.AsJson or SameText(AArgs.Format, 'json');
  { every --unit, in order (C13 b2); GhostUnit alone for a caller that set
    only that field }
  Units:= AArgs.ConvertUnits;
  if (Length(Units) = 0) and (AArgs.GhostUnit <> '') then Units:= [AArgs.GhostUnit];

  if (Length(Units) = 0) or (AArgs.RulesFile = '') then
  begin
    Writeln('Usage: drag-lint convert-apply --unit <F.pas> [--unit <G.pas> ...] --rules <file> --db PATH [--db ...] [--only Name1,Name2,... | --only-type Type1,Type2,...] [--castlib <file>] [--glyph-stitch] [--apply] [--no-backup] [--raise-encoding "<path>=utf8-bom" ...] [--no-warn-unlinked] [--no-reconcile-uses] [--no-reindex] [--progress] [--format json]');
    Exit(2);
  end;
  if (Length(AArgs.OnlyTypes) > 0) and (Length(AArgs.OnlySections) > 0) then
  begin
    Writeln('ERROR: --only-type and --only are mutually exclusive');
    Exit(2);
  end;
  { one unit keeps its old first check; a batch checks each unit in RunUnit }
  if (Length(Units) = 1) and not TFile.Exists(Units[0]) then
  begin
    Writeln(Format('ERROR: unit not found: %s', [Units[0]]));
    Exit(2);
  end;
  if not TFile.Exists(AArgs.RulesFile) then
  begin
    Writeln(Format('ERROR: rules file not found: %s', [AArgs.RulesFile]));
    Exit(2);
  end;
  { 1.34.1 (CONV-ENC E2): a bad --raise-encoding entry is a usage error }
  var RaiseErr: string:= RaiseEncodingError(AArgs.RaiseEncoding, Units);
  if RaiseErr <> '' then
  begin
    Writeln('ERROR: ' + RaiseErr);
    Exit(2);
  end;

  try
    RulesText:= TFile.ReadAllText(AArgs.RulesFile);
  except
    on Ex: Exception do
    begin
      Writeln(Format('ERROR: cannot read rules file: %s (%s)', [AArgs.RulesFile, Ex.Message]));
      Exit(2);
    end;
  end;
  Rules:= ParseConversionRules(RulesText);

  { one unit keeps its old order: a missing .dfm (book without unit rules)
    fails before any --db is opened }
  if (Length(Units) = 1) and not TFile.Exists(TPath.ChangeExtension(Units[0], '.dfm')) and not BookHasUnitRules(Rules) and
     not BookHasIdentifierMigrates(Rules) and (BookNothingToDoReason(Rules, Units[0]) = '') then
  begin
    Writeln(Format('ERROR: sibling .dfm not found: %s (every #convert rule needs .dfm instances to locate)',
      [TPath.ChangeExtension(Units[0], '.dfm')]));
    Exit(1);
  end;

  Dbs:= ResolveConsumerDbs(AArgs);
  if Length(Dbs) = 0 then
  begin
    Writeln('ERROR: no drag-lint index found. Pass --db <file.sqlite> or build the index first.');
    Exit(2);
  end;

  // Open EVERY readable --db up front (not just the first) -- Bug 2: the
  // From type, To type, and the form's own instances may each live in a
  // DIFFERENT --db, so rule validation, the freshness guard and BuildApplyPlan
  // all need cross-db type resolution (first-db-that-resolves-wins), while
  // unit/instance-scoped lookups use whichever store actually has --unit/the
  // .dfm indexed. This runs BEFORE the rules are validated, so a stale
  // explicit --db exits 2 (StaleDbRefusesRun) rather than being skipped while
  // the trees are built -- pinned by run_explicit_db_strict.ps1's T5 row.
  var StoresList: TList<ISymbolStore>:= TList<ISymbolStore>.Create;
  var OpenedDbs: TArray<string>:= nil;
  try
    for LDb in Dbs do
    begin
      if not TFile.Exists(LDb) then Continue;
      var St: ISymbolStore:= OpenReadOnlyStore(LDb, RoOk);
      if not RoOk then
      begin
        if StaleDbRefusesRun(AArgs, 'convert-apply', LDb) then Exit(2);
        Continue; { manifest-resolved: stale DB reported, scan the rest }
      end;
      StoresList.Add(St);
      OpenedDbs:= OpenedDbs + [LDb];
    end;
    Stores:= StoresList.ToArray;
    Dbs   := OpenedDbs; { 1.26.0: index-aligned with Stores (ResolverRefusal names the DB) }
  finally
    StoresList.Free;
  end;
  if Length(Stores) = 0 then
  begin
    Writeln('ERROR: no readable drag-lint index among --db path(s)');
    Exit(2);
  end;

  { 1.43 ENUMMAP: named explicitly, so an unusable one stops the run: mapping against
    today's enum instead would leave the old members silently unrenamed. Read-only,
    and kept out of Stores: it answers only for a #migrate enum's OLD members. }
  var OldPlatformStores: TArray<ISymbolStore>:= nil;
  for var OldDb: string in AArgs.OldPlatformDbs do
  begin
    var OldOk: Boolean:= False;
    var OldSt: ISymbolStore:= nil;
    if TFile.Exists(OldDb) then OldSt:= OpenReadOnlyStore(OldDb, OldOk);
    if not OldOk then
    begin
      Writeln(Format('ERROR: --old-platform-db %s is not a readable drag-lint index; nothing was changed', [OldDb]));
      Exit(2);
    end;
    OldPlatformStores:= OldPlatformStores + [OldSt];
  end;

  CastLib     := ParseCastLib(AArgs.CastLibFile);
  BookBuilt   := 0;
  BookChecked := False;
  FreshChecked:= False;
  BatchJson   := nil;
  { JSON collects every unit's apply/1 object (1.33.0: a single --unit too, so
    its exit_code can be stamped); one --unit still writes a bare apply/1 }
  if UseJson then BatchJson:= TJSONArray.Create;
  Trees:= TConvertTreeCache.Create(Stores);
  try
    Trees.DbPaths:= Dbs; { C9: names the db of a uses_unresolved candidate }
    Trees.OldPlatformStores:= OldPlatformStores;
    if Length(Units) = 1 then
    begin
      { 1.33.0 G3: the apply/1 document carries exit_code, known only once the
        unit is done -- so under JSON it is collected, stamped, then written }
      Result:= RunUnit(Units[0]);
      StampUnitExit(0, Result);
      if UseJson and (BatchJson.Count > 0) then WriteStdoutDocument(BatchJson.Items[0].ToJSON + sLineBreak);
      ReportUnitProgress(0, Result);
      Exit;
    end;
    { 1.23.0 (C13 b2): batch. A unit's refusal or failure never stops the
      others; the exit code is the worst unit's (6 > 2 > 1 > 0; 6 = an unusable castlib, 1.28.0). }
    Result:= 0;
    var NOk     : Integer:= 0;
    var NRefused: Integer:= 0;
    { 1.42 (CONVAPPLY-INHERITED, owner ruling Q5): run ancestor-first, so a
      descendant's inherited objects see their ancestor already converted;
      the report keeps --unit order (ReorderBatchJson) }
    var CmdOrder: TArray<string>:= Units;
    Units:= OrderUnitsAncestorFirst(Trees, Units, Rules);
    var SliceStart: TArray<Integer>;
    SetLength(SliceStart, Length(Units) + 1);
    if not UseJson and not SameUnitOrder(CmdOrder, Units) then
      Writeln('convert-apply: units run ancestor-first: ' + UnitNamesJoined(Units));
    for var I: Integer:= 0 to High(Units) do
    begin
      if not UseJson then Writeln(Format('=== unit %d of %d: %s ===', [I + 1, Length(Units), Units[I]]));
      var Code: Integer;
      var Before: Integer:= if UseJson then BatchJson.Count else 0;
      SliceStart[I]:= Before;
      try
        Code:= RunUnit(Units[I]);
      except
        { anything else a unit raises fails that unit, never the batch }
        on Ex: Exception do
          Code:= FailUnit(Format('%s: %s: %s -- unit not finished', [ExtractFileName(Units[I]), Ex.ClassName, Ex.Message]), 2);
      end;
      StampUnitExit(Before, Code);
      ReportUnitProgress(I, Code);
      if Code > Result then Result:= Code;
      if Code = 0 then Inc(NOk)
      else if JCtx.Refused then Inc(NRefused);
      if not UseJson then Writeln('');
    end;
    if UseJson then
    begin
      SliceStart[Length(Units)]:= BatchJson.Count;
      var Reordered: TJSONArray:= ReorderBatchJson(BatchJson, SliceStart, Units, CmdOrder);
      if Reordered <> nil then
      begin
        BatchJson.Free;  // dl:ok unprotected-object-free@c94d -- REVIEWED 2026-11-03: BatchJson is owned by DoConvertApply's outer try-finally (BatchJson.Free); this swaps in the reordered copy, which that finally then frees
        BatchJson:= Reordered;
      end;
      EmitBatchJson(Result, NOk, NRefused);
    end
    else
      Writeln(Format('batch: %d unit(s) -- %d ok, %d refused, %d failed; classes_built %d; exit %d',
        [Length(Units), NOk, NRefused, Length(Units) - NOk - NRefused, Trees.ClassesBuilt, Result]));
  finally
    BatchJson.Free;
    Trees.Free;
  end;
end; // function

end.
