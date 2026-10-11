unit ConvRules.ConvertRun;

{ Pure decisions behind the Convert tab (spec 2026-09-29, part 2): backup
  names, what a rule book contains, book order, which source units a dropped
  path stands for, the pre-flight verdict, and the reading of convert-apply's
  apply/1 JSON. No UI and no engine calls -- ConvRules.ConvertRunner executes,
  ConvRules.ConvertTab renders; ConvRulesModelTests.dpr pins every rule here. }

interface

uses
  System.SysUtils
  , ConvRules.Glyph  // dl:unit ConvRules.Glyph accepted -- GLYPH_BOOK_PENDING_SUFFIX travels with BookHasGlyphLinks: the greyed-book text belongs to the glyph gate
  , ConvRules.UnitStatus
  , ConvRules.WorkList
  ;

type
  /// <summary>What a rule book holds, as far as the Convert tab cares.</summary>
  /// <remarks>bkUnitsOnly books cannot run until the engine applies unit rules
  /// (capability apply_unit_rules); bkMixed books run their #convert blocks and
  /// report their unit rules as not applied.</remarks>
  TBookKind = (bkEmpty, bkConvertOnly, bkUnitsOnly, bkMixed);

  /// <summary>One line of the Convert tab's book checklist.</summary>
  TBookEntry = record
    /// <summary>Full path of the .rules file.</summary>
    Path   : string;
    /// <summary>The user's check.</summary>
    Checked: Boolean;
    /// <summary>BookKindOfText of the file's text.</summary>
    Kind   : TBookKind;
    /// <summary>True when the book holds a #link with a glyph expression (BookHasGlyphLinks); runnable only when the engine reports glyph_stitch.</summary>
    HasGlyph: Boolean;
  end;

  /// <summary>One inherited / inline instance convert-apply reported (apply/1
  /// `inherited[]`, engine C8 N1; key names follow the engine's merge notice): left
  /// unconverted, or -- action 'retyped', engine 1.26.0 on -- retyped in place.</summary>
  TInheritedLeft = record
    /// <summary>`name` -- the instance.</summary>
    Name         : string;
    /// <summary>`type` -- its class.</summary>
    TypeName     : string;
    /// <summary>`line` -- its .dfm line; 0 when absent or not an integer.</summary>
    Line         : Integer;
    /// <summary>`ancestor_unit` -- the declaring ancestor's unit; '' for outside.</summary>
    AncestorUnit : string;
    /// <summary>`ancestor_state` -- unconverted / converted / mismatched / outside.</summary>
    AncestorState: string;
    /// <summary>`reason` -- the engine's words.</summary>
    Reason       : string;
    /// <summary>`action` (engine 1.26.0 on, with inherited_retype) -- retyped / code /
    /// skipped / unverified; '' when absent (an older engine: every entry was left).</summary>
    Action       : string;
  end;

  /// <summary>One apply/1 items[] entry of a 1.27.0 kind the Convert tab reports:
  /// cast-not-applied, value-cast-applied or value-cast-check.</summary>
  /// <remarks>Every field is read type-checked: absent, or of another JSON type, it
  /// is '' / 0 -- the entry is still kept with what is known.</remarks>
  TApplyItem = record
    /// <summary>`kind`.</summary>
    Kind    : string;
    /// <summary>`instance` -- the component; '' when the engine names none.</summary>
    Instance: string;
    /// <summary>`file` -- the .pas or .dfm the entry is about, as the engine gives it.</summary>
    FileName: string;
    /// <summary>`path` -- the From member (cast site) or the linked property (value cast).</summary>
    Path    : string;
    /// <summary>`value` -- the cast's name (cast site, value check) or the new value
    /// (value cast, quoted as in the source).</summary>
    Value   : string;
    /// <summary>`old_value` -- the value before a value cast; '' for the other kinds.</summary>
    OldValue: string;
    /// <summary>`text` -- the engine's own sentence.</summary>
    Text    : string;
    /// <summary>`line` -- the line in FileName.</summary>
    Line    : Integer;
    /// <summary>`rule_line` -- the #link's line in the book.</summary>
    RuleLine: Integer;
  end;

  /// <summary>One apply/1 uses[] row (engine 1.27.0, C9 uses reconciliation).</summary>
  /// <remarks>The engine's keys: action remove|add|skipped|kept|moved, unit, section,
  /// source rule|reconcile|convert, needed_by[] of {name, line, section}. A missing or
  /// wrongly-typed field reads as ''.</remarks>
  TUsesRow = record
    /// <summary>`action` -- remove, add, skipped, kept or moved.</summary>
    Action  : string;
    /// <summary>`section` -- interface or implementation.</summary>
    Section : string;
    /// <summary>`unit`.</summary>
    UnitName: string;
    /// <summary>`source` -- rule, reconcile or convert.</summary>
    Source  : string;
    /// <summary>needed_by[] names on every row but a remove: what still needs the
    /// unit (a kept row's .dfm components).</summary>
    NeededBy: TArray<string>;
    /// <summary>needed_by[] names on a remove row: the .pas references the removal
    /// left dangling (the unit will not compile until that code is converted).</summary>
    Dangling: TArray<string>;
  end;

  /// <summary>An engine 1.27.0 apply/1 feature, one per info --json capability.</summary>
  /// <remarks>afCastSiteRefusal: cast_site_refusal (items[] cast-not-applied, one per
  /// .pas site); afValueStripDb: value_cast_strip_db (value-cast-applied /
  /// value-cast-check); afUsesReconcile: uses_reconcile (uses[] rows, uses_unresolved[],
  /// uses_reindex); afPasUses: pas_uses (pas_uses[]); afPasUsesResolution:
  /// pas_uses_resolution (engine 1.28.2: each pas_uses[] row's resolution and
  /// candidates[]; without it both are cleared).</remarks>
  TApplyFeature = (afCastSiteRefusal, afValueStripDb, afUsesReconcile, afPasUses, afPasUsesResolution);
  /// <summary>The apply/1 features the run's engine reported.</summary>
  TApplyFeatures = set of TApplyFeature;

  /// <summary>One convert-apply run, read from its apply/1 JSON.</summary>
  TApplyRow = record
    /// <summary>The engine's own ok flag; False also for unparseable output.</summary>
    Ok        : Boolean;
    /// <summary>The engine declined the unit (apply/1 "refused": true -- inherited
    /// instances, an {$IFDEF} in a uses clause, a stale .dfm span) and did not touch
    /// it. A known limitation, not a fault. Ok is False; Error holds the engine's
    /// "reason".</summary>
    Refused   : Boolean;
    /// <summary>'' when Ok; else the engine's refusal reason, the engine error,
    /// the first rule error ("line N: message") or the head of the unparseable
    /// output.</summary>
    Error     : string;
    /// <summary>edits_count.</summary>
    EditsCount: Integer;
    /// <summary>rule_errors[] length. Greater than 0 = the BOOK failed the
    /// engine's validation (measured 2026-09-29: ok=false, error "conversion
    /// rules failed validation", file untouched) -- a book fault, not a unit
    /// fault.</summary>
    RuleErrorCount: Integer;
    /// <summary>converted[] -- one line per converted instance.</summary>
    Converted : TArray<string>;
    /// <summary>todos[] + reemit_notes[] + warnings[] -- the manual remainder. When inherited[]
    /// is not empty, the engine's per-instance 'line N: warning: inherited instance ...'
    /// warnings are left out: InheritedLeftNote already counts those instances. Likewise a
    /// warnings[] line that is the text of a CastSites or ValueChecks entry is left out
    /// (CastSiteNote / ValueCastNote count it), so each to-do is counted once.</summary>
    Remainder : TArray<string>;
    /// <summary>inherited[] -- the instances left unconverted; empty for an engine
    /// without inherited_instances (it refuses such a unit instead). A non-object
    /// entry is skipped; a missing or wrongly-typed field reads as '' / 0.</summary>
    InheritedLeft: TArray<TInheritedLeft>;
    /// <summary>`component_part` -- what happened to the .dfm's component part
    /// ('skipped-no-instances': the .dfm holds no instance of its own, only inherited
    /// ones, engine C8 N1); '' when absent.</summary>
    ComponentPart: string;
    /// <summary>glyphs[] -- one outcome per converted instance per G-link (engine ask N3); [] when the engine sends none.</summary>
    Glyphs    : TArray<TGlyphOutcome>;
    /// <summary>The engine's own edit-set refusals found in its output, each one
    /// '[drag-lint: |ERROR: ]refused N edit(s) to &lt;file&gt; -- &lt;why&gt;' line,
    /// distinct, in order. Up to 1.25.0 the line goes to stderr
    /// (DRagLint.Refactor.TextEdit), which the editor's capture appends after the
    /// document; from 1.25.1 it is also apply/1 error. warnings[] is read too. Empty
    /// for a clean run.</summary>
    EditRefusals: TArray<string>;
    /// <summary>items[] kind cast-not-applied (afCastSiteRefusal): a class-cast #link
    /// site in the .pas left for the user; [] without the feature.</summary>
    CastSites: TArray<TApplyItem>;
    /// <summary>items[] kind value-cast-applied (afValueStripDb): a value the cast
    /// rewrote; [] without the feature.</summary>
    ValueCasts: TArray<TApplyItem>;
    /// <summary>items[] kind value-cast-check (afValueStripDb): a site the value cast
    /// could not rewrite -- check by hand; [] without the feature.</summary>
    ValueChecks: TArray<TApplyItem>;
    /// <summary>uses[] (afUsesReconcile); [] without the feature (a 1.26 engine sends
    /// uses[] too, under another contract).</summary>
    UsesRows: TArray<TUsesRow>;
    /// <summary>uses_unresolved[] (afUsesReconcile), one text per entry: '&lt;name&gt;
    /// line N: &lt;reason&gt; (&lt;candidate units&gt;)', the parts the engine sent.</summary>
    UsesUnresolved: TArray<string>;
    /// <summary>uses_reindex (afUsesReconcile): its status (done, skipped, failed,
    /// dry-run), plus ': &lt;reason&gt;' when the engine gave one; '' when absent.</summary>
    UsesReindex: string;
    /// <summary>pas_uses[] (afPasUses), via ParsePasUses: what the unit's code still
    /// uses from the old components -- the Work list. UnitPas is apply/1 'unit' and
    /// RunId 0 until the Convert tab stamps them (WorkRunOf); [] without the feature.</summary>
    PasUses: TArray<TPasUseRow>;
  end;

  /// <summary>The verdict before any file is touched.</summary>
  TPreflight = record
    /// <summary>False = refuse the run; Problems says why.</summary>
    Ok      : Boolean;
    /// <summary>Reasons the run is refused.</summary>
    Problems: TArray<string>;
    /// <summary>Checked books that will run, in list (application) order.</summary>
    Runnable: TArray<string>;
    /// <summary>Non-fatal facts for the results (skipped unit-rules books,
    /// unit rules a mixed book will not apply).</summary>
    Notes   : TArray<string>;
  end;

/// <summary>The backup paths for ONE unit's files, sharing one number: N is one
/// above the highest existing .BCK&lt;N&gt; over ALL of AFiles, so a unit's .pas
/// and .dfm restore points pair up by number (X.pas.BCK1 + X.dfm.BCK3 -> both
/// get .BCK4). Gaps are not reused, so N orders backups in time.</summary>
/// <param name="AFiles">The unit's files (its .pas and its .dfm), whether or
/// not each exists -- a stale X.dfm.BCK&lt;N&gt; still counts.</param>
/// <param name="AExists">File-existence probe (injected for tests).</param>
/// <returns>AFiles[i] + '.BCK' + N, in AFiles order; none of them exists yet.</returns>
function SharedBackupPaths(const AFiles: TArray<string>; const AExists: TFileProbe): TArray<string>;

/// <summary>Classifies a rule book by the directives it holds.</summary>
/// <param name="ARulesText">The .rules text.</param>
/// <returns>bkEmpty (no #convert, no unit rule), bkConvertOnly, bkUnitsOnly or bkMixed.</returns>
function BookKindOfText(const ARulesText: string): TBookKind;

/// <summary>AEntry with Kind and HasGlyph set from the book's text -- the ONE place
/// the Convert tab classifies a book, on first listing and on every refresh alike.</summary>
/// <param name="AEntry">The entry; Path and Checked are kept.</param>
/// <param name="ARulesText">The .rules text.</param>
/// <returns>The entry with Kind = BookKindOfText and HasGlyph = BookHasGlyphLinks of
/// ARulesText (both recomputed, so an edit that removed the last G-link clears it).</returns>
function ClassifiedEntry(const AEntry: TBookEntry; const ARulesText: string): TBookEntry;

/// <summary>The checklist suffix for a book and whether its check box is enabled.</summary>
/// <param name="AEntry">The classified entry.</param>
/// <param name="AUnitRulesOk">The engine reports apply_unit_rules.</param>
/// <param name="AGlyphOk">The engine reports glyph_stitch.</param>
/// <param name="AEnabled">False = the book cannot be checked (unit-rules-only while
/// apply_unit_rules is missing, or a G-link book while glyph_stitch is missing).</param>
/// <returns>'  (empty)', '  (unit rules: engine support pending)' or '  (unit rules not
/// applied: engine)' by Kind, then GLYPH_BOOK_PENDING_SUFFIX appended for a G-link book
/// while glyph_stitch is missing; '' when nothing applies.</returns>
function BookListSuffix(const AEntry: TBookEntry; AUnitRulesOk, AGlyphOk: Boolean; out AEnabled: Boolean): string;

/// <summary>The castlib a Convert run records and passes: APath when that file exists.</summary>
/// <param name="APath">The editor's resolved casts.castlib path; '' = none.</param>
/// <returns>APath, or '' when it is '' or names no file (the adapter then passes no
/// --castlib, so the report must not name one either).</returns>
function ExistingCastLib(const APath: string): string;

/// <summary>AEntries with entry AIndex moved ADelta places (clamped to the ends).</summary>
/// <param name="AEntries">The checklist, in application order.</param>
/// <param name="AIndex">The entry to move.</param>
/// <param name="ADelta">-1 = up, +1 = down.</param>
/// <returns>A new array; AEntries unchanged when the move is out of range.</returns>
function MoveEntry(const AEntries: TArray<TBookEntry>; AIndex, ADelta: Integer): TArray<TBookEntry>;

/// <summary>The .pas files APaths stand for: a .pas is itself, a folder its
/// *.pas (not recursive), a .dpr its member files that exist, a .dproj its
/// MainSource .dpr's members.</summary>
/// <param name="APaths">Dropped / added paths.</param>
/// <param name="AErrors">One line per path that could not be expanded.</param>
/// <returns>Full paths, first occurrence order, de-duplicated case-insensitively.</returns>
/// <remarks>A .dpr member is an entry WITH an `in '...'` path; a plain entry
/// (Vcl.Forms) is a library unit, neither expanded nor reported.</remarks>
function ExpandSources(const APaths: TArray<string>; out AErrors: TArray<string>): TArray<string>;

/// <summary>True when the FILE AUnitPas is one of AIndexedFiles: both sides
/// ExpandFileName'd, compared case-insensitively.</summary>
/// <param name="AUnitPas">A .pas path.</param>
/// <param name="AIndexedFiles">File paths in the project index (its `files`
/// table, TEngineAdapter.ListIndexedFiles).</param>
/// <returns>True = indexed.</returns>
/// <remarks>By PATH, never by unit name: convert-apply locates a unit's .dfm
/// block by its path, and the migration case is a same-named unit in another
/// tree (M2022\DM1.pas beside the project's own DM1.pas) -- a name match would
/// pass a unit the engine then cannot find.</remarks>
function UnitInIndex(const AUnitPas: string; const AIndexedFiles: TArray<string>): Boolean;

/// <summary>PURE: where the FILE APath is in APaths, by UnitInIndex's compare (both
/// sides ExpandFileName'd, case-insensitively).</summary>
/// <param name="APath">A file path.</param>
/// <param name="APaths">The paths to search.</param>
/// <returns>The first matching index; -1 when absent.</returns>
function PathIndex(const APath: string; const APaths: TArray<string>): Integer;

/// <summary>The Convert tab's DISPLAYED text for one source row.</summary>
/// <param name="AUnitPas">The listed .pas path. It stays the item string --
/// the job and Preflight consume it -- so only the display changes.</param>
/// <param name="AIndexedFiles">File paths in the project index (see UnitInIndex).</param>
/// <param name="AIndexKnown">False when the index could not be read: then
/// nothing is flagged -- unknown is never reported as indexed OR unindexed.</param>
/// <param name="AFlagged">True = the unit is known NOT to be in the index.</param>
/// <returns>AUnitPas, plus ' -- not in the project index' when AFlagged.</returns>
function SourceRowText(const AUnitPas: string; const AIndexedFiles: TArray<string>; AIndexKnown: Boolean; out AFlagged: Boolean): string;

/// <summary>Decides whether a Convert run may start, and which books run.</summary>
/// <param name="ABooks">The checklist.</param>
/// <param name="AUnits">The source units (.pas paths).</param>
/// <param name="AIndexedFiles">File paths in the project index (see UnitInIndex).</param>
/// <param name="AUnitRulesSupported">The engine reports apply_unit_rules.</param>
/// <param name="AGlyphSupported">The engine reports glyph_stitch; without it a book whose HasGlyph is True is skipped with a note.</param>
/// <returns>Ok=False when no book is checked, no unit is listed, or a unit's
/// FILE is not in the index (convert-apply would report a FALSE "could not
/// locate .dfm object block" for it); Runnable = checked books minus empty ones
/// minus unit-rules-only ones while unsupported, and minus G-link books while glyph_stitch is unsupported.</returns>
function Preflight(const ABooks: TArray<TBookEntry>; const AUnits, AIndexedFiles: TArray<string>; AUnitRulesSupported, AGlyphSupported: Boolean): TPreflight;

/// <summary>Reads convert-apply's --format json output (schema apply/1).</summary>
/// <param name="AJson">The engine's merged stdout+stderr; text before the first
/// '{' and after the last '}' (the "(loaded defaults ...)" line) is ignored.</param>
/// <param name="AFeatures">The engine's 1.27.0 apply/1 features (ApplyFeaturesOf its
/// capabilities). A field of a feature not in the set is left empty, so an older
/// engine's output reads exactly as before. The default (every feature) is for the
/// test seams; a real run passes what the engine reported.</param>
/// <returns>See TApplyRow; never raises. Unknown items[] kinds and unknown keys are
/// ignored; a missing array reads as empty.</returns>
function ParseApplyJson(const AJson: string; AFeatures: TApplyFeatures = [Low(TApplyFeature)..High(TApplyFeature)]): TApplyRow;

/// <summary>PURE: the apply/1 features an engine reported.</summary>
/// <param name="ACapNames">The capability names info --json reported true
/// (TEngineAdapter.CapabilityNames).</param>
/// <returns>One feature per matching name, case-insensitive: cast_site_refusal,
/// value_cast_strip_db, uses_reconcile, pas_uses, pas_uses_resolution (ConvRules.Engine
/// CAPABILITY_*).</returns>
function ApplyFeaturesOf(const ACapNames: TArray<string>): TApplyFeatures;

/// <summary>PURE: the converted row's StripDB part.</summary>
/// <param name="ARow">The book's apply/1 answer.</param>
/// <returns>'; StripDB: N value(s) changed, M to check by hand' (N = ValueCasts, M =
/// ValueChecks); '' when both are 0.</returns>
function ValueCastNote(const ARow: TApplyRow): string;

/// <summary>PURE: the converted row's class-cast part.</summary>
/// <param name="ARow">The book's apply/1 answer.</param>
/// <returns>'; N cast site(s) to convert by hand' (N = CastSites); '' when 0.</returns>
function CastSiteNote(const ARow: TApplyRow): string;

/// <summary>PURE: the converted row's uses part.</summary>
/// <param name="ARow">The book's apply/1 answer.</param>
/// <returns>'; uses: +A -R moved M' (A add rows, R remove rows, M moved rows), then
/// ' (reindex failed: &lt;reason&gt;)' when UsesReindex is a failure; '' when A, R and M
/// are 0 and the reindex did not fail.</returns>
/// <remarks>Kept, skipped and unresolved entries are not counted here: they are in the
/// run report's uses lines (UsesReportNote).</remarks>
function UsesNote(const ARow: TApplyRow): string;

/// <summary>PURE: the run-report note of one items[] entry.</summary>
/// <param name="AItem">A CastSites / ValueCasts / ValueChecks entry.</param>
/// <returns>For value-cast-applied '&lt;file&gt;:&lt;line&gt; &lt;instance&gt;.&lt;path&gt;: &lt;old&gt;
/// -&gt; &lt;new&gt;' (the file name without its folder); for every other kind the engine's
/// text.</returns>
function ApplyItemReportNote(const AItem: TApplyItem): string;

/// <summary>PURE: the run-report note of one uses[] row.</summary>
/// <param name="ARow">The row.</param>
/// <returns>'&lt;unit&gt; (&lt;section&gt;, source &lt;source&gt;)', the parenthesis holding only the
/// parts that are set, then '; needed by: a, b' and '; dangling: a, b' when those
/// lists are not empty.</returns>
function UsesReportNote(const ARow: TUsesRow): string;

/// <summary>PURE: True when convert-apply claims success but refused to write one of
/// the unit's edit sets -- the unit is left HALF-converted.</summary>
/// <param name="ARow">ParseApplyJson's reading of the run.</param>
/// <returns>ARow.Ok and ARow.EditRefusals is not empty. False for a row that is not
/// Ok (failed or refused): it fails on its own already.</returns>
/// <remarks>Engine defect, every version up to 1.25.0: a nested converted component
/// makes the .dfm re-emit plan overlapping deletes; the applier refuses that file's
/// edits whole ('overlapping delete ranges'), writes the .pas anyway, and the run
/// still reports ok=true, exit 0. No apply/1 key carries it -- only the stderr line.
/// A STOP-GAP until the engine applies a unit all-or-nothing; tighten it to the
/// engine's exit contract when that ships.</remarks>
function ApplyHalfWritten(const ARow: TApplyRow): Boolean;

/// <summary>PURE: the note of a row ApplyHalfWritten fails.</summary>
/// <param name="ARow">A row for which ApplyHalfWritten is True.</param>
/// <returns>'engine left the unit half-converted (&lt;ext&gt; edits refused: N edit(s),
/// &lt;why&gt;) -- restored from backup; engine fix pending', one parenthesised part per
/// refusal joined '; ' (the extension is the refused file's, &lt;why&gt; the engine's
/// reason without its trailing parenthesis).</returns>
function HalfWrittenNote(const ARow: TApplyRow): string;

/// <summary>PURE: True when convert-apply FAILED because it refused one of the unit's
/// edit sets -- the engine 1.25.1+ shape, where the plan is checked before anything is
/// written (exit 1, ok=false, 'refused N edit(s) to &lt;file&gt; -- ... -- unit not
/// changed, nothing written').</summary>
/// <param name="ARow">ParseApplyJson's reading of the run.</param>
/// <returns>not ARow.Ok and ARow.EditRefusals is not empty.</returns>
/// <remarks>A UNIT failure, never a book error: the runner's failure path takes it
/// (its restore from its own .BCK is harmless -- the unit is unchanged).</remarks>
function ApplyEditSetRefused(const ARow: TApplyRow): Boolean;

/// <summary>PURE: the note of a row ApplyEditSetRefused fails.</summary>
/// <param name="ARow">A row for which ApplyEditSetRefused is True.</param>
/// <returns>'engine refused the unit as an engine defect (&lt;ext&gt; edits refused: N
/// edit(s), &lt;why&gt;) -- unit not changed, nothing written', the parts as
/// HalfWrittenNote's.</returns>
function EditSetRefusedNote(const ARow: TApplyRow): string;

/// <summary>PURE: the converted row's note for what was left (spec E10).</summary>
/// <param name="ARetypeSupported">The engine reports inherited_retype (C8 N2). False
/// (1.22.0) changes the converted words only (see returns).</param>
/// <param name="AItems">TApplyRow.InheritedLeft -- the engine's own inherited[],
/// reported after the runner's reindex and shown UNFILTERED (controller ruling M4: the
/// R4 omission of ancestors converted earlier in the run is the editor-side code-use
/// note's alone).</param>
/// <returns>'' for none; else 'N inherited instance(s) left: &lt;words&gt;' per distinct
/// words, first-seen order, joined '; '. An action 'retyped' entry is NOT left and is
/// not counted (IsRetypedInstance); an action 'code' entry counts as 'N inherited code
/// use(s) left: &lt;words&gt;' (state converted: 'ancestor &lt;U&gt; converted' with retype,
/// else 'ancestor &lt;U&gt; (ancestor converted; retype needs engine N2)'); an action
/// 'unverified' entry's words are 'ancestor field use not verified against the index'. The words by ancestor_state: unconverted
/// 'ancestor &lt;U&gt; not converted'; converted 'ancestor &lt;U&gt; converted -- retype
/// pending (engine N2)' with retype, else 'ancestor &lt;U&gt; converted -- this unit still has
/// &lt;Type&gt; there and may not compile or load until the engine can retype inherited
/// instances (N2)' (an inherited object of the From type under an ancestor that now
/// declares the To type fails at load, and From-only member uses stop compiling); mismatched 'ancestor &lt;U&gt; has &lt;Found&gt; (neither
/// &lt;From&gt; nor &lt;To&gt;)', the three types read from the engine's reason, or
/// 'ancestor &lt;U&gt; has another type -- &lt;reason&gt;' when the reason has another
/// shape; outside 'ancestor not determinable -- &lt;reason&gt;' (the engine sends no
/// ancestor_unit); any other state 'ancestor &lt;U&gt;: &lt;state&gt;'.</returns>
/// <remarks>Grouping is by the words, so it is by (state, unit), plus the type found for
/// mismatched and the reason for outside.</remarks>
function InheritedLeftNote(const AItems: TArray<TInheritedLeft>; ARetypeSupported: Boolean): string;

/// <summary>PURE: one run-report note for one left instance.</summary>
/// <param name="AItem">The instance.</param>
/// <param name="ARetypeSupported">As for InheritedLeftNote.</param>
/// <returns>'&lt;name&gt;: &lt;type&gt; line N -- &lt;words&gt; (&lt;reason&gt;)' -- for an action 'code'
/// entry '&lt;name&gt;: &lt;type&gt;[ line N] -- code use -- &lt;words&gt; (&lt;reason&gt;)', the line only
/// when above 0 -- the words as
/// InheritedLeftNote's; ' (&lt;reason&gt;)' is left out when the reason is '' or the words
/// already carry it (outside, and a mismatched reason that could not be read).</returns>
function InheritedReportNote(const AItem: TInheritedLeft; ARetypeSupported: Boolean): string;

/// <summary>PURE: did the engine retype this inherited instance (inherited[] action
/// 'retyped', engine 1.26.0 on)?</summary>
/// <param name="AItem">One inherited[] entry.</param>
/// <returns>True for action 'retyped' (any case): the instance is converted, NOT left --
/// InheritedLeftNote does not count it and InheritedReportLines writes no line for it.
/// False for 'skipped', 'code', 'unverified' and a missing action (an older engine).</returns>
function IsRetypedInstance(const AItem: TInheritedLeft): Boolean;

/// <summary>PURE: the converted row's note for what the engine retyped.</summary>
/// <param name="AItems">TApplyRow.InheritedLeft.</param>
/// <returns>'' when none was retyped; else 'N inherited instance(s) retyped'.</returns>
function InheritedRetypedNote(const AItems: TArray<TInheritedLeft>): string;

/// <summary>PURE: the note of a csConverted row.</summary>
/// <param name="AApply">The book's apply/1 answer (Ok).</param>
/// <param name="AInheritedSupported">The engine reports inherited_instances: only then is
/// inherited[] read as that contract (InheritedLeftNote is appended).</param>
/// <param name="ARetypeSupported">The engine reports inherited_retype (passed to
/// InheritedLeftNote).</param>
/// <returns>'N edit(s), M remaining for manual work', then '; no component of its own to
/// convert' when ComponentPart is 'skipped-no-instances' (the engine converted around a
/// .dfm holding only inherited instances, exit 0 -- not a failure), then '; ' +
/// InheritedRetypedNote when supported and something was retyped, then '; ' +
/// InheritedLeftNote when supported and something was left, then ValueCastNote,
/// CastSiteNote and UsesNote (each '' when it has nothing to say). The runner appends
/// the glyph suffix after all of these.</returns>
function ConvertedRowNote(const AApply: TApplyRow; AInheritedSupported, ARetypeSupported: Boolean): string;

/// <summary>PURE: why the Convert tab must not add sources right now, or '' when it may.</summary>
/// <param name="ARunning">A conversion run is in progress.</param>
/// <param name="AChecking">The inherited-instance check is busy: its analysis runs, or
/// one of its prompts is up (the E6 offer, the Convert gate question, the E7 order
/// warning).</param>
/// <returns>The status-line refusal text; '' = the sources may be added.</returns>
/// <remarks>OLE delivers a drop inside ANY modal loop, a MessageDlg included. A prompt
/// was built from the list as it was when it opened, and its answer rewrites that list
/// (E6) or runs it (the gate, E7), so a unit added under it would be lost or listed but
/// not run: the prompt counts as busy. A run outranks a check.</remarks>
function SourcesAddRefusal(ARunning, AChecking: Boolean): string;

/// <summary>PURE: why the project index has no project file to reindex with -- the ONE
/// text Convert and Conversion &gt; Reindex project refuse with.</summary>
/// <param name="AProjectDb">The project index.</param>
/// <param name="AProjectFile">ProjectFileForDb of it; '' when the DB is not in a _D-RAG
/// folder.</param>
/// <returns>'the project index &lt;db&gt; has no project file on disk -- expected
/// &lt;file&gt;' (a description of the expected place when AProjectFile is ''); no
/// leading verb, no final full stop.</returns>
function NoProjectFileText(const AProjectDb, AProjectFile: string): string;

/// <summary>PURE: elapsed time for the progress line.</summary>
/// <param name="AMs">Milliseconds; a negative value reads as 0.</param>
/// <returns>'m:ss' below an hour ('0:42', '3:10'), 'h:mm:ss' from an hour on
/// ('1:02:03'); seconds are truncated.</returns>
function FormatElapsed(AMs: Int64): string;

/// <summary>PURE: reads the counts out of the direct `index --project X --db Y` run (C17).</summary>
/// <param name="AOutput">The engine's output.</param>
/// <param name="AFiles">N of 'Done. Files: N, ...' -- rows in the index; -1 when absent.</param>
/// <param name="AClosure">N of 'Compile closure: N file(s):' -- the project's closure list;
/// -1 when absent.</param>
/// <returns>True when AFiles was found.</returns>
/// <remarks>Deliberately NOT the `index --all` section line: its walked= is the run's
/// admitted walk, a different number, and files &gt; walked there means REBUILD -- the
/// closure count must never be shown under that name.</remarks>
function ParseIndexSummary(const AOutput: string; out AFiles, AClosure: Integer): Boolean;

/// <summary>PURE: the decision behind Conversion &gt; Reindex project (C17).</summary>
/// <param name="ARunning">A Convert run is in progress.</param>
/// <param name="AProjectDb">The editor's project index.</param>
/// <param name="AProjectFile">ProjectFileForDb of it ('' = none derivable).</param>
/// <param name="AProjectFileExists">AProjectFile exists on disk.</param>
/// <returns>'' = go; else the status-line refusal: 'Reindex refused: a conversion is
/// running -- reindex after it finishes.', or 'Reindex refused: ' + NoProjectFileText +
/// '.'.</returns>
function ReindexRefusal(ARunning: Boolean; const AProjectDb, AProjectFile: string; AProjectFileExists: Boolean): string;

/// <summary>PURE: the Reindex project menu hint, naming the index it refreshes.</summary>
/// <param name="AProjectDb">The editor's project index.</param>
/// <returns>'Refresh the project index &lt;db&gt; (incremental index --project) -- after IDE
/// edits, or between conversion stages'.</returns>
function ReindexMenuHint(const AProjectDb: string): string;

/// <summary>PURE: the status line after a Reindex project call (C17).</summary>
/// <param name="ACode">The call's result: the engine's exit code, ENGINE_OUTCOME_CANCELLED
/// or ENGINE_OUTCOME_TIMEOUT.</param>
/// <param name="AOutput">The engine's output.</param>
/// <param name="AProjectFile">The project file reindexed.</param>
/// <param name="AProjectDb">The index refreshed.</param>
/// <param name="AElapsedMs">Wall time of the call.</param>
/// <param name="AIsError">True for a failure or a timeout (SetError, red).</param>
/// <returns>&lt;P&gt; below is '&lt;project file name&gt; (&lt;db file name&gt;)'. 0: 'Reindexed
/// &lt;P&gt;: N file(s) in the index, compile closure M (m:ss)' (', compile closure M' left out
/// when unknown; '... (m:ss); the engine printed no summary line.' when neither).
/// Cancelled: 'Reindex of &lt;P&gt; cancelled after m:ss -- the index may be partly refreshed;
/// run it again.' Timeout: 'Reindex of &lt;P&gt; failed: the engine did not finish in time
/// (m:ss).' Any other code: 'Reindex of &lt;P&gt; failed (exit N): ' + the output's first
/// 200 characters, line breaks as spaces.</returns>
function ReindexOutcomeText(ACode: Integer; const AOutput, AProjectFile, AProjectDb: string; AElapsedMs: Int64; out AIsError: Boolean): string;

implementation

uses
  System.Generics.Collections
  , System.IOUtils
  , System.JSON
  , System.Math
  , System.RegularExpressions
  , System.StrUtils
  , ConvRules.Model
  , ConvRules.UsesHarvest
  , ConvRules.EngineProgress  // dl:unit ConvRules.EngineProgress accepted -- ENGINE_OUTCOME_CANCELLED / _TIMEOUT are the long-call runner's outcome contract ReindexOutcomeText reads, so they travel with the runner
  , ConvRules.Engine  // dl:unit ConvRules.Engine accepted -- the four 1.27.0 CAPABILITY_* names live with the other info --json keys; ApplyFeaturesOf maps them to the apply/1 features it gates
  ;

const
  BCK_TAG          = '.BCK';
  ERR_HEAD_CHARS   = 200;
  // The engine's refusal of one file's edit set, one whole line. Up to 1.25.0 the
  // applier (DRagLint.Refactor.TextEdit) writes it to stderr AFTER the other file
  // was written, exit 0: 'drag-lint: refused <N> edit(s) to <file> -- <why>'. From
  // 1.25.1 the plan is checked before any write, exit 1, ok=false: 'ERROR: refused
  // <N> edit(s) to <file> -- <why> -- unit not changed, nothing written' (apply/1
  // error: the same without 'ERROR: '). Anchored on the whole line, so the words
  // 'overlapping delete ranges' elsewhere never match.
  // Matched case-insensitively (EDIT_REFUSAL_OPTIONS); 'edit', 'edits' and 'edit(s)'.
  EDIT_REFUSAL_PATTERN = '^(?:drag-lint: |ERROR: )?refused (\d+) edit(?:\(s\)|s)? to (.+?) -- (.+)$';
  EDIT_REFUSAL_OPTIONS = [roIgnoreCase];
  EDIT_REFUSAL_PREFIX  = '^(?:drag-lint: |ERROR: )';
  EDIT_REFUSAL_COUNT   = 1;
  EDIT_REFUSAL_FILE    = 2;
  EDIT_REFUSAL_WHY     = 3;
  HALF_PART_FMT = '%s edits refused: %s edit(s), %s';
  HALF_NOTE_FMT = 'engine left the unit half-converted (%s) -- restored from backup; engine fix pending';
  EDIT_SET_REFUSED_FMT = 'engine refused the unit as an engine defect (%s) -- unit not changed, nothing written';
  // The engine's per-instance inherited warning (also an items[] inherited-instance-skipped):
  // 'line N: warning: inherited instance <Name>: <Type> skipped -- <reason>'.
  INHERITED_WARNING_PATTERN = '^line \d+: warning: inherited instance ';
  BCK_PROBE_WINDOW = 50;
  // Engine 1.27.0 apply/1: items[] kinds, uses[] actions, uses_reindex status.
  APPLY_KIND_CAST_SITE   = 'cast-not-applied';
  APPLY_KIND_VALUE_CAST  = 'value-cast-applied';
  APPLY_KIND_VALUE_CHECK = 'value-cast-check';
  USES_ACTION_ADD        = 'add';
  USES_ACTION_REMOVE     = 'remove';
  USES_ACTION_MOVED      = 'moved';
  USES_REINDEX_FAILED    = 'failed';
  VALUE_CAST_NOTE_FMT    = '; StripDB: %d value(s) changed, %d to check by hand';
  CAST_SITE_NOTE_FMT     = '; %d cast site(s) to convert by hand';
  USES_NOTE_FMT          = '; uses: +%d -%d moved %d';
  VALUE_CAST_REPORT_FMT  = '%s:%d %s.%s: %s -> %s';

// The highest N with AFile + '.BCK' + N present; 0 when there is none.
function HighestBackupN(const AFile: string; const AExists: TFileProbe): Integer;
var
  N: Integer;
begin
  Result:= 0;
  N:= 1;
  // Probe upward until a run of misses longer than any plausible gap; the
  // convention in ORM3\CLIENT stays in single digits.
  while N <= Result + BCK_PROBE_WINDOW do
  begin
    if AExists(AFile + BCK_TAG + IntToStr(N)) then
      Result:= N;
    Inc(N);
  end;
end;


function SharedBackupPaths(const AFiles: TArray<string>; const AExists: TFileProbe): TArray<string>;
var
  Highest: Integer;
begin
  Highest:= 0;
  for var LFile: string in AFiles do
    Highest:= Max(Highest, HighestBackupN(LFile, AExists));
  Result:= nil;
  for var LFile: string in AFiles do
    Result:= Result + [LFile + BCK_TAG + IntToStr(Highest + 1)];
end;

function BookKindOfText(const ARulesText: string): TBookKind;
var
  Book    : TRuleBook;
  HasConv : Boolean;
  HasUnits: Boolean;
begin
  Book:= TRuleBook.Create;
  try
    Book.LoadFromString(ARulesText);
    HasConv := Length(Book.ConvertHeaders) > 0;
    HasUnits:= Length(Book.UnitNodes) > 0;
  finally
    Book.Free;
  end; // try
  if HasConv and HasUnits then
    Result:= bkMixed
  else if HasConv then
    Result:= bkConvertOnly
  else if HasUnits then
    Result:= bkUnitsOnly
  else
    Result:= bkEmpty;
end;

function ClassifiedEntry(const AEntry: TBookEntry; const ARulesText: string): TBookEntry;
begin
  Result:= AEntry;
  Result.Kind    := BookKindOfText(ARulesText);
  Result.HasGlyph:= BookHasGlyphLinks(ARulesText);
end;

function BookListSuffix(const AEntry: TBookEntry; AUnitRulesOk, AGlyphOk: Boolean; out AEnabled: Boolean): string;
begin
  AEnabled:= True;
  Result  := '';
  case AEntry.Kind of
    bkEmpty:
      Result:= '  (empty)';
    bkUnitsOnly:
      if not AUnitRulesOk then
      begin
        Result  := '  (unit rules: engine support pending)';
        AEnabled:= False;
      end;
    bkMixed:
      if not AUnitRulesOk then
        Result:= '  (unit rules not applied: engine)';
  end; // case
  if AEntry.HasGlyph and not AGlyphOk then
  begin
    Result  := Result + GLYPH_BOOK_PENDING_SUFFIX;
    AEnabled:= False;
  end;
end;

function ExistingCastLib(const APath: string): string;
begin
  Result:= if (APath <> '') and TFile.Exists(APath) then APath else '';
end;

function MoveEntry(const AEntries: TArray<TBookEntry>; AIndex, ADelta: Integer): TArray<TBookEntry>;
var
  Target: Integer;
  Tmp   : TBookEntry;
begin
  Result:= Copy(AEntries);
  Target:= AIndex + ADelta;
  if (AIndex < 0) or (AIndex > High(Result)) or (Target < 0) or (Target > High(Result)) then
    Exit;
  Tmp:= Result[AIndex];
  Result[AIndex]:= Result[Target];
  Result[Target]:= Tmp;
end;

function ExpandSources(const APaths: TArray<string>; out AErrors: TArray<string>): TArray<string>;
var
  Found: TArray<string>;

  procedure AddPas(const AFile: string);
  begin
    if not MatchText(AFile, Found) then
      Found:= Found + [AFile];
  end;

  // A locked or unreadable file becomes one AErrors line, never an exception:
  // this runs on Explorer drops, and a bad project must not crash a drop.
  function TryRead(const AFile: string; out AText: string): Boolean;
  begin
    AText:= '';
    try
      AText:= TFile.ReadAllText(AFile);
      Result:= True;
    except
      on E: Exception do
      begin
        AErrors:= AErrors + [Format('%s: cannot read (%s)', [ExtractFileName(AFile), E.Message])];
        Result:= False;
      end;
    end; // try
  end;

  procedure AddDpr(const ADpr: string);
  var
    LText: string;
  begin
    if not TryRead(ADpr, LText) then
      Exit;
    for var LMember: TDprMember in ReadDprMembers(LText, ExtractFilePath(ADpr)) do
      if LMember.FilePath = '' then
        Continue // a plain entry (Vcl.Forms) is a library unit, not a member
      else if TFile.Exists(LMember.FilePath) then
        AddPas(TPath.GetFullPath(LMember.FilePath))
      else
        AErrors:= AErrors + [Format('%s: member %s not found (%s)', [ExtractFileName(ADpr), LMember.UnitName, LMember.FilePath])];
  end;

var
  P  : string;
  Ext: string;
begin
  Found  := nil;
  AErrors:= nil;
  for P in APaths do
  begin
    Ext:= LowerCase(ExtractFileExt(P));
    if TDirectory.Exists(P) then
    begin
      for var LFile: string in TDirectory.GetFiles(P, '*.pas') do
        AddPas(TPath.GetFullPath(LFile));
    end
    else if not TFile.Exists(P) then
      AErrors:= AErrors + [P + ': not found']
    else if Ext = '.pas' then
      AddPas(TPath.GetFullPath(P))
    else if Ext = '.dpr' then
      AddDpr(P)
    else if Ext = '.dproj' then
    begin
      var LProj: string;
      if TryRead(P, LProj) then
      begin
        var LMain: string:= MainSourceOf(LProj, ExtractFilePath(P));
        if (LMain <> '') and TFile.Exists(LMain) then
          AddDpr(LMain)
        else
          AErrors:= AErrors + [ExtractFileName(P) + ': no MainSource .dpr found'];
      end;
    end
    else
      AErrors:= AErrors + [P + ': not a .pas, .dpr, .dproj or folder'];
  end; // for
  Result:= Found;
end;

function PathIndex(const APath: string; const APaths: TArray<string>): Integer;
var
  LFull: string;
begin
  LFull:= ExpandFileName(APath);
  for var I: Integer:= 0 to High(APaths) do
    if SameText(ExpandFileName(APaths[I]), LFull) then
      Exit(I);
  Result:= -1;
end;

function UnitInIndex(const AUnitPas: string; const AIndexedFiles: TArray<string>): Boolean;
begin
  Result:= PathIndex(AUnitPas, AIndexedFiles) >= 0;
end;

function SourceRowText(const AUnitPas: string; const AIndexedFiles: TArray<string>; AIndexKnown: Boolean; out AFlagged: Boolean): string;
begin
  AFlagged:= AIndexKnown and not UnitInIndex(AUnitPas, AIndexedFiles);
  Result  := AUnitPas;
  if AFlagged then
    Result:= Result + ' -- not in the project index';
end;

function Preflight(const ABooks: TArray<TBookEntry>; const AUnits, AIndexedFiles: TArray<string>; AUnitRulesSupported, AGlyphSupported: Boolean): TPreflight;
var
  B       : TBookEntry;
  U       : string;
  Missing : TArray<string>;
  AnyCheck: Boolean;
begin
  Result:= Default(TPreflight);
  AnyCheck:= False;
  for B in ABooks do
  begin
    if not B.Checked then
      Continue;
    AnyCheck:= True;
    if B.HasGlyph and not AGlyphSupported then
    begin
      Result.Notes:= Result.Notes + [ExtractFileName(B.Path) + ': glyph links: engine support pending -- skipped'];
      Continue;
    end;
    case B.Kind of
      bkEmpty:
        Result.Notes:= Result.Notes + [ExtractFileName(B.Path) + ': no #convert and no unit rule -- skipped'];
      bkUnitsOnly:
        if AUnitRulesSupported then
          Result.Runnable:= Result.Runnable + [B.Path]
        else
          Result.Notes:= Result.Notes + [ExtractFileName(B.Path) + ': unit rules: engine support pending -- skipped'];
      bkMixed:
      begin
        Result.Runnable:= Result.Runnable + [B.Path];
        if not AUnitRulesSupported then
          Result.Notes:= Result.Notes + [ExtractFileName(B.Path) + ': its unit rules are not applied (engine support pending)'];
      end;
      else
        Result.Runnable:= Result.Runnable + [B.Path];
    end; // case
  end; // for
  if not AnyCheck then
    Result.Problems:= Result.Problems + ['No rule book is checked.'];
  if Length(AUnits) = 0 then
    Result.Problems:= Result.Problems + ['No source unit is listed.'];
  Missing:= nil;
  for U in AUnits do
    if not UnitInIndex(U, AIndexedFiles) then
      Missing:= Missing + [ExtractFileName(U)];
  if Length(Missing) > 0 then
    Result.Problems:= Result.Problems + [Format('Not in the project index (index the project first): %s', [string.Join(', ', Missing)])];
  if AnyCheck and (Length(Result.Runnable) = 0) and (Length(Result.Problems) = 0) then
    Result.Problems:= Result.Problems + ['None of the checked rule books can run (see notes).'];
  Result.Ok:= Length(Result.Problems) = 0;
end;

{ glyphs[] (C10, engine ask N3). Every key is optional and every read is
  type-checked: an older engine sends no array, a future one may add keys or change
  a type, and a value of the wrong JSON type reads as its default -- nothing here
  raises (GetValue<T> would, on a wrong type). }
function GlyphOutcomes(AObj: TJSONObject): TArray<TGlyphOutcome>;

  // A JSON string; TJSONNumber descends from TJSONString, so it is excluded.
  function Str(AItem: TJSONObject; const AKey: string): string;
  var
    LVal: TJSONValue;
  begin
    LVal:= AItem.GetValue(AKey);
    if (LVal is TJSONString) and not (LVal is TJSONNumber) then
      Result:= TJSONString(LVal).Value
    else
      Result:= '';
  end;

  // A JSON number holding an integer; anything else (3.5, "3", true) is False.
  function TryInt(AVal: TJSONValue; out AInt: Integer): Boolean;
  begin
    AInt:= 0;
    Result:= (AVal is TJSONNumber) and TryStrToInt(TJSONNumber(AVal).Value, AInt);
  end;

  function Int(AItem: TJSONObject; const AKey: string): Integer;
  begin
    if not TryInt(AItem.GetValue(AKey), Result) then
      Result:= 0;
  end;

var
  LArr  : TJSONValue;
  LSlots: TJSONValue;
  LItem : TJSONObject;
  LSlot : Integer;
  O     : TGlyphOutcome;
begin
  Result:= nil;
  LArr:= AObj.GetValue('glyphs');
  if not (LArr is TJSONArray) then
    Exit;
  for var LVal: TJSONValue in TJSONArray(LArr) do
  begin
    if not (LVal is TJSONObject) then
      Continue;
    LItem:= TJSONObject(LVal);
    O:= Default(TGlyphOutcome);
    O.Instance   := Str(LItem, 'instance');
    O.FromPath   := Str(LItem, 'from_path');
    O.ToPath     := Str(LItem, 'to_path');
    O.Kind       := Str(LItem, 'kind');
    O.Alternative:= Str(LItem, 'alternative');
    O.Message    := Str(LItem, 'message');
    O.SourceN    := Int(LItem, 'source_n');
    O.RuleLine   := Int(LItem, 'rule_line');
    LSlots:= LItem.GetValue('dropped_slots');
    if LSlots is TJSONArray then
      for var LSlotVal: TJSONValue in TJSONArray(LSlots) do
        if TryInt(LSlotVal, LSlot) then
          O.DroppedSlots:= O.DroppedSlots + [LSlot];
    Result:= Result + [O];
  end;
end;

function ApplyFeaturesOf(const ACapNames: TArray<string>): TApplyFeatures;
begin
  Result:= [];
  if MatchText(CAPABILITY_CAST_SITE_REFUSAL, ACapNames) then
    Include(Result, afCastSiteRefusal);
  if MatchText(CAPABILITY_VALUE_CAST_STRIP_DB, ACapNames) then
    Include(Result, afValueStripDb);
  if MatchText(CAPABILITY_USES_RECONCILE, ACapNames) then
    Include(Result, afUsesReconcile);
  if MatchText(CAPABILITY_PAS_USES, ACapNames) then
    Include(Result, afPasUses);
  if MatchText(CAPABILITY_PAS_USES_RESOLUTION, ACapNames) then
    Include(Result, afPasUsesResolution);
end;

function ValueCastNote(const ARow: TApplyRow): string;
begin
  if Length(ARow.ValueCasts) + Length(ARow.ValueChecks) = 0 then
    Exit('');
  Result:= Format(VALUE_CAST_NOTE_FMT, [Length(ARow.ValueCasts), Length(ARow.ValueChecks)]);
end;

function CastSiteNote(const ARow: TApplyRow): string;
begin
  Result:= if Length(ARow.CastSites) > 0 then Format(CAST_SITE_NOTE_FMT, [Length(ARow.CastSites)]) else '';
end;

function UsesNote(const ARow: TApplyRow): string;
var
  LAdded  : Integer;
  LRemoved: Integer;
  LMoved  : Integer;
  LFailed : Boolean;
begin
  LAdded  := 0;
  LRemoved:= 0;
  LMoved  := 0;
  for var LRow: TUsesRow in ARow.UsesRows do
    if SameText(LRow.Action, USES_ACTION_ADD) then
      Inc(LAdded)
    else if SameText(LRow.Action, USES_ACTION_REMOVE) then
      Inc(LRemoved)
    else if SameText(LRow.Action, USES_ACTION_MOVED) then
      Inc(LMoved);
  // UsesReindex is 'failed' or 'failed: <reason>' (ParseApplyJson).
  LFailed:= SameText(ARow.UsesReindex, USES_REINDEX_FAILED) or StartsText(USES_REINDEX_FAILED + ': ', ARow.UsesReindex);
  if (LAdded + LRemoved + LMoved = 0) and not LFailed then
    Exit('');
  Result:= Format(USES_NOTE_FMT, [LAdded, LRemoved, LMoved]);
  if LFailed then
    Result:= Result + ' (reindex ' + ARow.UsesReindex + ')';
end;

function ApplyItemReportNote(const AItem: TApplyItem): string;
begin
  if SameText(AItem.Kind, APPLY_KIND_VALUE_CAST) then
    Result:= Format(VALUE_CAST_REPORT_FMT, [ExtractFileName(AItem.FileName), AItem.Line, AItem.Instance, AItem.Path, AItem.OldValue, AItem.Value])
  else
    Result:= AItem.Text;
end;

function UsesReportNote(const ARow: TUsesRow): string;
var
  LParts: TArray<string>;
begin
  LParts:= nil;
  if ARow.Section <> '' then
    LParts:= LParts + [ARow.Section];
  if ARow.Source <> '' then
    LParts:= LParts + ['source ' + ARow.Source];
  Result:= ARow.UnitName;
  if Length(LParts) > 0 then
    Result:= Result + ' (' + string.Join(', ', LParts) + ')';
  if Length(ARow.NeededBy) > 0 then
    Result:= Result + '; needed by: ' + string.Join(', ', ARow.NeededBy);
  if Length(ARow.Dangling) > 0 then
    Result:= Result + '; dangling: ' + string.Join(', ', ARow.Dangling);
end;

{ The 1.27.0 apply/1 reads. Every key is read type-checked, as GlyphOutcomes does:
  a missing key, a wrong JSON type or a non-object entry degrades to ''/0 or is
  skipped -- nothing raises. }

// A JSON string member's text; '' when absent or of another JSON type
// (TJSONNumber descends from TJSONString, so it is excluded by name).
function JsonStr(AObj: TJSONObject; const AKey: string): string;
var
  LVal: TJSONValue;
begin
  LVal:= AObj.Values[AKey];
  Result:= if (LVal is TJSONString) and not (LVal is TJSONNumber) then LVal.Value else '';
end;

// A JSON number member holding an integer; 0 for anything else ("25", 3.5, true).
function JsonInt(AObj: TJSONObject; const AKey: string): Integer;
var
  LVal: TJSONValue;
begin
  LVal:= AObj.Values[AKey];
  if not ((LVal is TJSONNumber) and TryStrToInt(LVal.Value, Result)) then
    Result:= 0;
end;

// The items[] entries of one kind.
function ApplyItems(AObj: TJSONObject; const AKind: string): TArray<TApplyItem>;
var
  LItem: TJSONObject;
  O    : TApplyItem;
begin
  Result:= nil;
  if not (AObj.Values['items'] is TJSONArray) then
    Exit;
  for var LVal: TJSONValue in TJSONArray(AObj.Values['items']) do
  begin
    if not (LVal is TJSONObject) then
      Continue;
    LItem:= TJSONObject(LVal);
    if not SameText(JsonStr(LItem, 'kind'), AKind) then
      Continue;
    O:= Default(TApplyItem);
    O.Kind    := JsonStr(LItem, 'kind');
    O.Instance:= JsonStr(LItem, 'instance');
    O.FileName:= JsonStr(LItem, 'file');
    O.Path    := JsonStr(LItem, 'path');
    O.Value   := JsonStr(LItem, 'value');
    O.OldValue:= JsonStr(LItem, 'old_value');
    O.Text    := JsonStr(LItem, 'text');
    O.Line    := JsonInt(LItem, 'line');
    O.RuleLine:= JsonInt(LItem, 'rule_line');
    Result:= Result + [O];
  end;
end;

// The `name` of each object entry of AArr (needed_by[], candidates[] use AKey 'unit').
function EntryNames(AArr: TJSONValue; const AKey: string): TArray<string>;
var
  LName: string;
begin
  Result:= nil;
  if not (AArr is TJSONArray) then
    Exit;
  for var LVal: TJSONValue in TJSONArray(AArr) do
    if LVal is TJSONObject then
    begin
      LName:= JsonStr(TJSONObject(LVal), AKey);
      if LName <> '' then
        Result:= Result + [LName];
    end;
end;

// uses[]: needed_by on a remove row names the references the removal left dangling.
function UsesRows(AObj: TJSONObject): TArray<TUsesRow>;
var
  LItem : TJSONObject;
  LNames: TArray<string>;
  O     : TUsesRow;
begin
  Result:= nil;
  if not (AObj.Values['uses'] is TJSONArray) then
    Exit;
  for var LVal: TJSONValue in TJSONArray(AObj.Values['uses']) do
  begin
    if not (LVal is TJSONObject) then
      Continue;
    LItem:= TJSONObject(LVal);
    O:= Default(TUsesRow);
    O.Action  := JsonStr(LItem, 'action');
    O.Section := JsonStr(LItem, 'section');
    O.UnitName:= JsonStr(LItem, 'unit');
    O.Source  := JsonStr(LItem, 'source');
    LNames:= EntryNames(LItem.Values['needed_by'], 'name');
    if SameText(O.Action, USES_ACTION_REMOVE) then
      O.Dangling:= LNames
    else
      O.NeededBy:= LNames;
    Result:= Result + [O];
  end;
end;

// uses_unresolved[] {name, line, section, reason, candidates[] {unit, db}}, one text each.
function UsesUnresolved(AObj: TJSONObject): TArray<string>;
var
  LItem : TJSONObject;
  LText : string;
  LCands: TArray<string>;
begin
  Result:= nil;
  if not (AObj.Values['uses_unresolved'] is TJSONArray) then
    Exit;
  for var LVal: TJSONValue in TJSONArray(AObj.Values['uses_unresolved']) do
  begin
    if not (LVal is TJSONObject) then
      Continue;
    LItem:= TJSONObject(LVal);
    LText:= JsonStr(LItem, 'name');
    if JsonInt(LItem, 'line') > 0 then
      LText:= LText + ' line ' + IntToStr(JsonInt(LItem, 'line'));
    if JsonStr(LItem, 'reason') <> '' then
      LText:= LText + (if LText <> '' then ': ' else '') + JsonStr(LItem, 'reason');
    LCands:= EntryNames(LItem.Values['candidates'], 'unit');
    if Length(LCands) > 0 then
      LText:= LText + ' (' + string.Join(', ', LCands) + ')';
    if LText <> '' then
      Result:= Result + [LText];
  end;
end;

// uses_reindex {status, reason}: 'status' or 'status: reason'; '' when absent.
function UsesReindex(AObj: TJSONObject): string;
var
  LReason: string;
begin
  if not (AObj.Values['uses_reindex'] is TJSONObject) then
    Exit('');
  Result := JsonStr(TJSONObject(AObj.Values['uses_reindex']), 'status');
  LReason:= JsonStr(TJSONObject(AObj.Values['uses_reindex']), 'reason');
  if LReason <> '' then
    Result:= Result + ': ' + LReason;
end;

function ParseApplyJson(const AJson: string; AFeatures: TApplyFeatures): TApplyRow;

  function Strings(AObj: TJSONObject; const AKey: string): TArray<string>;
  var
    Arr: TJSONArray;
  begin
    Result:= nil;
    if AObj.TryGetValue<TJSONArray>(AKey, Arr) then
      for var LVal: TJSONValue in Arr do
        Result:= Result + [LVal.Value];
  end;

  // A JSON string member's text; '' when absent or of another JSON type
  // (TJSONNumber descends from TJSONString, so it is excluded by name).
  function Str(AObj: TJSONObject; const AKey: string): string;
  var
    LVal: TJSONValue;
  begin
    LVal:= AObj.Values[AKey];
    Result:= if (LVal is TJSONString) and not (LVal is TJSONNumber) then LVal.Value else '';
  end;

  // apply/1 inherited[] (C8 N1). Read type-checked, never by GetValue<T>: a
  // malformed entry must not cost the whole row (GetValue raises on a mismatch).
  function InheritedItems(AObj: TJSONObject): TArray<TInheritedLeft>;
  var
    LItem: TInheritedLeft;
    LNum : TJSONValue;
  begin
    Result:= nil;
    if not (AObj.Values['inherited'] is TJSONArray) then
      Exit;
    for var LVal: TJSONValue in TJSONArray(AObj.Values['inherited']) do
      if LVal is TJSONObject then
      begin
        LItem:= Default(TInheritedLeft);
        LItem.Name         := Str(TJSONObject(LVal), 'name');
        LItem.TypeName     := Str(TJSONObject(LVal), 'type');
        LItem.AncestorUnit := Str(TJSONObject(LVal), 'ancestor_unit');
        LItem.AncestorState:= Str(TJSONObject(LVal), 'ancestor_state');
        LItem.Reason       := Str(TJSONObject(LVal), 'reason');
        LItem.Action       := Str(TJSONObject(LVal), 'action');
        LNum:= TJSONObject(LVal).Values['line'];
        if not ((LNum is TJSONNumber) and TryStrToInt(LNum.Value, LItem.Line)) then
          LItem.Line:= 0;
        Result:= Result + [LItem];
      end;
  end;

  // AWarnings minus the engine's per-instance inherited warnings when inherited[] is
  // there (AHasList): those are the "left" note's, so counting them as manual remainder
  // too would count each instance twice. Without inherited[] they stay.
  function OwnWarnings(const AWarnings: TArray<string>; AHasList: Boolean): TArray<string>;
  begin
    Result:= nil;
    for var LWarn: string in AWarnings do
      if not (AHasList and TRegEx.IsMatch(LWarn, INHERITED_WARNING_PATTERN)) then
        Result:= Result + [LWarn];
  end;

  // AWarnings minus every line that IS one of AItems' text. Matched on the exact text:
  // the engine writes the item's `text` verbatim as its warnings[] line (measured on the
  // 1.27.0 captures: field "warnings", text == the warning), and no other key ties the
  // two -- a looser match (rule line, instance) could swallow an unrelated warning.
  function WithoutItemTexts(const AWarnings: TArray<string>; const AItems: TArray<TApplyItem>): TArray<string>;
  var
    LTaken: Boolean;
  begin
    Result:= nil;
    for var LWarn: string in AWarnings do
    begin
      LTaken:= False;
      for var LItem: TApplyItem in AItems do
        LTaken:= LTaken or ((LItem.Text <> '') and (LItem.Text = LWarn));
      if not LTaken then
        Result:= Result + [LWarn];
    end;
  end;

  // A refusal line without its 'drag-lint: ' / 'ERROR: ' prefix: one refusal read
  // from apply/1 error AND from stderr is the same refusal.
  function RefusalKey(const ALine: string): string;
  begin
    Result:= TRegEx.Replace(ALine, EDIT_REFUSAL_PREFIX, '', EDIT_REFUSAL_OPTIONS);
  end;

  // Every distinct refusal line in ALines, in order, appended to AFound (first form kept).
  procedure AddRefusals(const ALines: TArray<string>; var AFound: TArray<string>);
  var
    LLine: string;
    LSeen: Boolean;
  begin
    for var LRaw: string in ALines do
    begin
      LLine:= Trim(LRaw);
      if not TRegEx.IsMatch(LLine, EDIT_REFUSAL_PATTERN, EDIT_REFUSAL_OPTIONS) then
        Continue;
      LSeen:= False;
      for var LHad: string in AFound do
        LSeen:= LSeen or (RefusalKey(LHad) = RefusalKey(LLine));
      if not LSeen then
        AFound:= AFound + [LLine];
    end;
  end;

var
  Root: TJSONValue;
  Obj : TJSONObject;
  Errs: TJSONArray;
  Text: string;
begin
  Result:= Default(TApplyRow);
  Errs:= nil;
  // stderr is merged into the pipe: skip anything before the document, and --
  // measured 2026-09-29, the engine's "(loaded defaults ...)" line lands AFTER
  // it -- anything after the last '}' (ParseJSONValue rejects trailing text).
  Text:= Trim(AJson);
  if (Text <> '') and (Text[1] <> '{') and (Pos('{', Text) > 0) then
    Text:= Copy(Text, Pos('{', Text), MaxInt);
  if (Text <> '') and (Text[1] = '{') then
    Text:= Copy(Text, 1, LastDelimiter('}', Text));
  Root:= TJSONObject.ParseJSONValue(Text);
  try
    if not (Root is TJSONObject) then
    begin
      Result.Error:= 'unparseable engine output: ' + Copy(Trim(AJson), 1, ERR_HEAD_CHARS);
      Exit;
    end;
    Obj:= TJSONObject(Root);
    Result.Ok        := Obj.GetValue<Boolean>('ok', False);
    Result.EditsCount:= Obj.GetValue<Integer>('edits_count', 0);
    Result.Converted := Strings(Obj, 'converted');
    Result.InheritedLeft:= InheritedItems(Obj);
    Result.ComponentPart:= Str(Obj, 'component_part');
    Result.Glyphs    := GlyphOutcomes(Obj);
    // Engine 1.27.0, each behind its capability: an older engine's items[] / uses[]
    // (a 1.26 per-rule cast-not-applied, its uses rows) is not this contract.
    if afCastSiteRefusal in AFeatures then
      Result.CastSites:= ApplyItems(Obj, APPLY_KIND_CAST_SITE);
    if afValueStripDb in AFeatures then
    begin
      Result.ValueCasts := ApplyItems(Obj, APPLY_KIND_VALUE_CAST);
      Result.ValueChecks:= ApplyItems(Obj, APPLY_KIND_VALUE_CHECK);
    end;
    if afUsesReconcile in AFeatures then
    begin
      Result.UsesRows      := UsesRows(Obj);
      Result.UsesUnresolved:= UsesUnresolved(Obj);
      Result.UsesReindex   := UsesReindex(Obj);
    end;
    if (afPasUses in AFeatures) and (Obj.Values['pas_uses'] is TJSONArray) then
      Result.PasUses:= ParsePasUses(TJSONArray(Obj.Values['pas_uses']), Str(Obj, 'unit'), 0);
    // Engine 1.28.2: resolution / candidates[] are this contract only with the capability.
    if not (afPasUsesResolution in AFeatures) then
      for var I: Integer:= 0 to High(Result.PasUses) do
      begin
        Result.PasUses[I].Resolution:= '';
        Result.PasUses[I].Candidates:= nil;
      end;
    // Each to-do is counted ONCE, in its own note part (controller ruling: items[] is
    // the union the six arrays partition). A cast site / value check is also a
    // warnings[] line, so it leaves the manual remainder when its array holds it.
    Result.Remainder := Strings(Obj, 'todos') + Strings(Obj, 'reemit_notes')
      + WithoutItemTexts(OwnWarnings(Strings(Obj, 'warnings'), Length(Result.InheritedLeft) > 0), Result.CastSites + Result.ValueChecks);
    // The applier's refusal reaches us on stderr, outside the document (no apply/1
    // key carries it, up to engine 1.25.0); warnings[] / error are read as well.
    AddRefusals(AJson.Split([#10]), Result.EditRefusals);
    AddRefusals(Strings(Obj, 'warnings'), Result.EditRefusals);
    AddRefusals([Str(Obj, 'error')], Result.EditRefusals);
    if Obj.TryGetValue<TJSONArray>('rule_errors', Errs) then
      Result.RuleErrorCount:= Errs.Count;
    Result.Refused:= (not Result.Ok) and Obj.GetValue<Boolean>('refused', False);
    if Result.Refused then
    begin
      Result.Error:= Obj.GetValue<string>('reason', '');
      if Result.Error = '' then
        Result.Error:= 'convert-apply refused the unit and gave no reason';
    end
    else if not Result.Ok then
    begin
      // The first rule error is more useful than the generic "conversion rules
      // failed validation" the engine puts in 'error'.
      if Result.RuleErrorCount > 0 then
        Result.Error:= Format('line %d: %s', [Errs.Items[0].GetValue<Integer>('line', 0), Errs.Items[0].GetValue<string>('message', '')])
      else
        Result.Error:= Obj.GetValue<string>('error', '');
      if Result.Error = '' then
        Result.Error:= 'convert-apply reported ok=false with no reason';
    end;
  finally
    Root.Free;
  end; // try
end;

function ApplyHalfWritten(const ARow: TApplyRow): Boolean;
begin
  Result:= ARow.Ok and (Length(ARow.EditRefusals) > 0);
end;

// The refusals of ARow as '<ext> edits refused: N edit(s), <why>' parts, joined '; '.
function RefusalParts(const ARow: TApplyRow): string;
var
  LMatch: TMatch;
  LParts: TArray<string>;
  LWhy  : string;
begin
  LParts:= nil;
  for var LLine: string in ARow.EditRefusals do
  begin
    LMatch:= TRegEx.Match(LLine, EDIT_REFUSAL_PATTERN, EDIT_REFUSAL_OPTIONS);
    if not LMatch.Success then
      Continue;
    // The engine's trailing '(an engine defect; the file is left unchanged)' is about
    // that ONE file -- the other one was written, which is the point of this note.
    LWhy:= LMatch.Groups[EDIT_REFUSAL_WHY].Value;
    if Pos(' (', LWhy) > 0 then
      LWhy:= Copy(LWhy, 1, Pos(' (', LWhy) - 1);
    LParts:= LParts + [Format(HALF_PART_FMT, [LowerCase(ExtractFileExt(LMatch.Groups[EDIT_REFUSAL_FILE].Value)),
      LMatch.Groups[EDIT_REFUSAL_COUNT].Value, LWhy])];
  end;
  Result:= string.Join('; ', LParts);
end;

function HalfWrittenNote(const ARow: TApplyRow): string;
begin
  Result:= Format(HALF_NOTE_FMT, [RefusalParts(ARow)]);
end;

function ApplyEditSetRefused(const ARow: TApplyRow): Boolean;
begin
  Result:= (not ARow.Ok) and (Length(ARow.EditRefusals) > 0);
end;

function EditSetRefusedNote(const ARow: TApplyRow): string;
begin
  Result:= Format(EDIT_SET_REFUSED_FMT, [RefusalParts(ARow)]);
end;

const
  LEFT_FMT        = '%d inherited instance(s) left: %s';
  LEFT_CODE_FMT   = '%d inherited code use(s) left: %s';
  RETYPED_FMT     = '%d inherited instance(s) retyped';
  // inherited[] action (engine 1.26.0 on); '' = an older engine, every entry left.
  ACTION_RETYPED    = 'retyped';
  ACTION_CODE       = 'code';
  ACTION_UNVERIFIED = 'unverified';
  WORDS_UNVERIFIED  = 'ancestor field use not verified against the index';
  WORDS_CODE_CONV    = 'ancestor %s converted';
  WORDS_CODE_CONV_N1 = 'ancestor %s (ancestor converted; retype needs engine N2)';
  REPORT_CODE_FMT    = '%s: %s%s -- code use -- %s';
  REPORT_CODE_LINE   = ' line %d';
  STATE_UNCONV    = 'unconverted';
  STATE_CONV      = 'converted';
  STATE_MISMATCH  = 'mismatched';
  STATE_OUTSIDE   = 'outside';
  WORDS_UNCONV    = 'ancestor %s not converted';
  WORDS_CONV      = 'ancestor %s converted -- retype pending (engine N2)';
  WORDS_CONV_N1   = 'ancestor %s converted -- this unit still has %s there and may not compile or load until the engine can retype inherited instances (N2)';
  WORDS_MISMATCH  = 'ancestor %s has %s (neither %s nor %s)';
  WORDS_MIS_OTHER = 'ancestor %s has another type -- %s';
  WORDS_OUTSIDE   = 'ancestor not determinable -- %s';
  WORDS_OTHER     = 'ancestor %s: %s';
  REPORT_LEFT_FMT = '%s: %s line %d -- %s';
  REPORT_REASON   = ' (%s)';
  NOTE_CONVERTED  = '%d edit(s), %d remaining for manual work';
  NOTE_NO_OWN_COMPONENT = '; no component of its own to convert';
  PART_SKIPPED_NO_INSTANCES = 'skipped-no-instances';
  // The engine's mismatched reason (DRagLint.Convert.Apply, 1.22.0):
  // 'declared in <Unit> as <Found>, neither <From> nor <To> -- not converted'.
  MIS_HEAD    = 'declared in ';
  MIS_AS      = ' as ';
  MIS_NEITHER = ', neither ';
  MIS_NOR     = ' nor ';
  MIS_TAIL    = ' -- ';
  SOURCES_REFUSED_RUNNING  = 'A conversion is running -- sources cannot be added until it finishes.';
  SOURCES_REFUSED_CHECKING = 'Inherited instances are being checked -- add the sources again when it finishes.';

// The engine's mismatched reason read back: True with the three type names when
// AItem.Reason has exactly MIS_HEAD + AncestorUnit + MIS_AS + Found + MIS_NEITHER + From
// + MIS_NOR + To + MIS_TAIL..., each name one non-empty word.
function TryReadMismatch(const AItem: TInheritedLeft; out AFound, AFrom, ATo: string): Boolean;

  // The text of ARest up to ASep (ARest then starts after it); False when ASep is
  // absent or the cut is not one word.
  function Cut(var ARest: string; const ASep: string; out AWord: string): Boolean;
  var
    LPos: Integer;
  begin
    LPos := Pos(ASep, ARest);
    AWord:= if LPos > 0 then Copy(ARest, 1, LPos - 1) else '';
    ARest:= if LPos > 0 then Copy(ARest, LPos + Length(ASep), MaxInt) else '';
    Result:= (AWord <> '') and (Pos(' ', AWord) = 0) and (Pos(',', AWord) = 0);
  end;

var
  LHead: string;
  LRest: string;
begin
  AFound:= '';
  AFrom := '';
  ATo   := '';
  LHead := MIS_HEAD + AItem.AncestorUnit + MIS_AS;
  if (AItem.AncestorUnit = '') or not StartsText(LHead, AItem.Reason) then
    Exit(False);
  LRest := Copy(AItem.Reason, Length(LHead) + 1, MaxInt);
  Result:= Cut(LRest, MIS_NEITHER, AFound) and Cut(LRest, MIS_NOR, AFrom) and Cut(LRest, MIS_TAIL, ATo);
end;

// What was left, in words, per ancestor_state (see InheritedLeftNote).
function LeftWords(const AItem: TInheritedLeft; ARetypeSupported: Boolean): string;
var
  LFound, LFrom, LTo: string;
begin
  if SameText(AItem.Action, ACTION_UNVERIFIED) then
    Result:= WORDS_UNVERIFIED
  else if SameText(AItem.Action, ACTION_CODE) and SameText(AItem.AncestorState, STATE_CONV) then
    // A .pas use: the .dfm load-failure words of WORDS_CONV_N1 do not apply.
    Result:= if ARetypeSupported then Format(WORDS_CODE_CONV, [AItem.AncestorUnit]) else Format(WORDS_CODE_CONV_N1, [AItem.AncestorUnit])
  else if SameText(AItem.AncestorState, STATE_UNCONV) then
    Result:= Format(WORDS_UNCONV, [AItem.AncestorUnit])
  else if SameText(AItem.AncestorState, STATE_CONV) then
    Result:= if ARetypeSupported then Format(WORDS_CONV, [AItem.AncestorUnit]) else Format(WORDS_CONV_N1, [AItem.AncestorUnit, AItem.TypeName])
  else if SameText(AItem.AncestorState, STATE_MISMATCH) then
    Result:= if TryReadMismatch(AItem, LFound, LFrom, LTo) then Format(WORDS_MISMATCH, [AItem.AncestorUnit, LFound, LFrom, LTo])
      else Format(WORDS_MIS_OTHER, [AItem.AncestorUnit, AItem.Reason])
  else if SameText(AItem.AncestorState, STATE_OUTSIDE) then
    Result:= Format(WORDS_OUTSIDE, [AItem.Reason])
  else
    Result:= Format(WORDS_OTHER, [AItem.AncestorUnit, AItem.AncestorState]);
end;

function InheritedLeftNote(const AItems: TArray<TInheritedLeft>; ARetypeSupported: Boolean): string;
var
  LWords : TArray<string>; // one per distinct (format, LeftWords), first-seen order
  LFmts  : TArray<string>;
  LCounts: TArray<Integer>;
  LIdx   : Integer;
  LParts : TArray<string>;
  LText  : string;
  LFmt   : string;
begin
  LWords := nil;
  LFmts  := nil;
  LCounts:= nil;
  // The words carry the grouping: ancestor + state, plus the type found (mismatched)
  // or the reason (outside, an unread mismatched reason) -- two different texts are
  // never merged under one count. A code-only use counts apart from an instance.
  for var LItem: TInheritedLeft in AItems do
  begin
    if IsRetypedInstance(LItem) then
      Continue;
    LText:= LeftWords(LItem, ARetypeSupported);
    LFmt := if SameText(LItem.Action, ACTION_CODE) then LEFT_CODE_FMT else LEFT_FMT;
    LIdx := High(LWords);
    while (LIdx >= 0) and not (SameText(LWords[LIdx], LText) and (LFmts[LIdx] = LFmt)) do
      Dec(LIdx);
    if LIdx < 0 then
    begin
      LWords := LWords + [LText];
      LFmts  := LFmts + [LFmt];
      LCounts:= LCounts + [0];
      LIdx   := High(LWords);
    end;
    Inc(LCounts[LIdx]);
  end;
  LParts:= nil;
  for var I: Integer:= 0 to High(LWords) do
    LParts:= LParts + [Format(LFmts[I], [LCounts[I], LWords[I]])];
  Result:= string.Join('; ', LParts);
end;

function InheritedReportNote(const AItem: TInheritedLeft; ARetypeSupported: Boolean): string;
var
  LWords: string;
begin
  LWords:= LeftWords(AItem, ARetypeSupported);
  if SameText(AItem.Action, ACTION_CODE) then
    Result:= Format(REPORT_CODE_FMT, [AItem.Name, AItem.TypeName, if AItem.Line > 0 then Format(REPORT_CODE_LINE, [AItem.Line]) else '', LWords])
  else
    Result:= Format(REPORT_LEFT_FMT, [AItem.Name, AItem.TypeName, AItem.Line, LWords]);
  if (AItem.Reason <> '') and (Pos(AItem.Reason, LWords) = 0) then
    Result:= Result + Format(REPORT_REASON, [AItem.Reason]);
end;

function IsRetypedInstance(const AItem: TInheritedLeft): Boolean;
begin
  Result:= SameText(AItem.Action, ACTION_RETYPED);
end;

function InheritedRetypedNote(const AItems: TArray<TInheritedLeft>): string;
var
  LCount: Integer;
begin
  LCount:= 0;
  for var LItem: TInheritedLeft in AItems do
    if IsRetypedInstance(LItem) then
      Inc(LCount);
  Result:= if LCount > 0 then Format(RETYPED_FMT, [LCount]) else '';
end;

function ConvertedRowNote(const AApply: TApplyRow; AInheritedSupported, ARetypeSupported: Boolean): string;
var
  LLeft   : string;
  LRetyped: string;
begin
  Result:= Format(NOTE_CONVERTED, [AApply.EditsCount, Length(AApply.Remainder)]);
  if SameText(AApply.ComponentPart, PART_SKIPPED_NO_INSTANCES) then
    Result:= Result + NOTE_NO_OWN_COMPONENT;
  // E10: only an engine with inherited_instances sends inherited[]; the gate keeps an
  // older engine's output from being read as this contract. Unfiltered (ruling M4).
  LRetyped:= if AInheritedSupported then InheritedRetypedNote(AApply.InheritedLeft) else '';
  if LRetyped <> '' then
    Result:= Result + '; ' + LRetyped;
  LLeft:= if AInheritedSupported then InheritedLeftNote(AApply.InheritedLeft, ARetypeSupported) else '';
  if LLeft <> '' then
    Result:= Result + '; ' + LLeft;
  // Engine 1.27.0: each part is '' when its arrays are empty (feature off, or nothing to say).
  Result:= Result + ValueCastNote(AApply) + CastSiteNote(AApply) + UsesNote(AApply);
end;
function SourcesAddRefusal(ARunning, AChecking: Boolean): string;
begin
  if ARunning then
    Result:= SOURCES_REFUSED_RUNNING
  else if AChecking then
    Result:= SOURCES_REFUSED_CHECKING
  else
    Result:= '';
end;

const
  // The project index without its project file: Convert and Reindex project refuse, the
  // tab's stale retry skips its reindex.
  NO_PROJECT_FILE_FMT   = 'the project index %s has no project file on disk -- expected %s';
  NO_PROJECT_FILE_GUESS = '<Project>.dproj beside its _D-RAG folder (the DB is not in one)';
  REINDEX_REFUSED_RUNNING = 'Reindex refused: a conversion is running -- reindex after it finishes.';
  // The direct index --project --db run's two lines. NOT index --all's section line: its
  // files= / walked= are a different population (walked= is not the closure count).
  DIRECT_DONE_RE    = '^\s*Done\. Files: (\d+),';
  DIRECT_CLOSURE_RE = '^Compile closure: (\d+) file\(s\):';
  REINDEX_HEAD_CHARS = 200;
  REINDEX_HINT_FMT   = 'Refresh the project index %s (incremental index --project) -- after IDE edits, or between conversion stages';
  ENGINE_EXIT_OK     = 0;

function FormatElapsed(AMs: Int64): string;
const
  MS_PER_S  = 1000;
  S_PER_MIN = 60;
  S_PER_H   = 3600;
var
  LSec: Int64;
begin
  LSec:= if AMs > 0 then AMs div MS_PER_S else 0;
  if LSec >= S_PER_H then
    Result:= Format('%d:%.2d:%.2d', [LSec div S_PER_H, (LSec mod S_PER_H) div S_PER_MIN, LSec mod S_PER_MIN])
  else
    Result:= Format('%d:%.2d', [LSec div S_PER_MIN, LSec mod S_PER_MIN]);
end;

function NoProjectFileText(const AProjectDb, AProjectFile: string): string;
begin
  Result:= Format(NO_PROJECT_FILE_FMT, [AProjectDb, if AProjectFile = '' then NO_PROJECT_FILE_GUESS else AProjectFile]);
end;

function ParseIndexSummary(const AOutput: string; out AFiles, AClosure: Integer): Boolean;
var
  LMatch: TMatch;
begin
  AFiles  := -1;
  AClosure:= -1;
  LMatch:= TRegEx.Match(AOutput, DIRECT_DONE_RE, [roMultiLine]);
  if not LMatch.Success then
    Exit(False);
  AFiles:= StrToInt(LMatch.Groups[1].Value);
  LMatch:= TRegEx.Match(AOutput, DIRECT_CLOSURE_RE, [roMultiLine]);
  if LMatch.Success then
    AClosure:= StrToInt(LMatch.Groups[1].Value);
  Result:= True;
end;

function ReindexRefusal(ARunning: Boolean; const AProjectDb, AProjectFile: string; AProjectFileExists: Boolean): string;
begin
  if ARunning then
    Result:= REINDEX_REFUSED_RUNNING
  else if (AProjectFile = '') or not AProjectFileExists then
    Result:= 'Reindex refused: ' + NoProjectFileText(AProjectDb, AProjectFile) + '.'
  else
    Result:= '';
end;

function ReindexMenuHint(const AProjectDb: string): string;
begin
  Result:= Format(REINDEX_HINT_FMT, [AProjectDb]);
end;

function ReindexOutcomeText(ACode: Integer; const AOutput, AProjectFile, AProjectDb: string; AElapsedMs: Int64; out AIsError: Boolean): string;
var
  LName   : string;
  LFiles  : Integer;
  LClosure: Integer;
begin
  // The DB is named on every outcome: the editor's default index may not be the one meant.
  LName   := Format('%s (%s)', [ExtractFileName(AProjectFile), ExtractFileName(AProjectDb)]);
  AIsError:= False;
  case ACode of
    ENGINE_EXIT_OK:
      if not ParseIndexSummary(AOutput, LFiles, LClosure) then
        Result:= Format('Reindexed %s (%s); the engine printed no summary line.', [LName, FormatElapsed(AElapsedMs)])
      else if LClosure < 0 then
        Result:= Format('Reindexed %s: %d file(s) in the index (%s)', [LName, LFiles, FormatElapsed(AElapsedMs)])
      else
        Result:= Format('Reindexed %s: %d file(s) in the index, compile closure %d (%s)', [LName, LFiles, LClosure, FormatElapsed(AElapsedMs)]);
    ENGINE_OUTCOME_CANCELLED:
      Result:= Format('Reindex of %s cancelled after %s -- the index may be partly refreshed; run it again.', [LName, FormatElapsed(AElapsedMs)]);
    ENGINE_OUTCOME_TIMEOUT:
    begin
      AIsError:= True;
      Result  := Format('Reindex of %s failed: the engine did not finish in time (%s).', [LName, FormatElapsed(AElapsedMs)]);
    end;
    else
    begin
      AIsError:= True;
      Result  := Format('Reindex of %s failed (exit %d): %s', [LName, ACode,
        Copy(Trim(StringReplace(StringReplace(AOutput, #13#10, ' ', [rfReplaceAll]), #10, ' ', [rfReplaceAll])), 1, REINDEX_HEAD_CHARS)]);
    end;
  end; // case
end;

end.
