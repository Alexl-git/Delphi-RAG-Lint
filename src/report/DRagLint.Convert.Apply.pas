unit DRagLint.Convert.Apply;

{
  Track 3 (component conversion), sub-project B -- the convert-apply
  orchestrator. Given a rule set, a target .pas + .dfm pair, and an optional
  --only instance filter, it locates the component instances to convert in the
  .dfm, rewrites all five surfaces (DFM re-emit, .pas decl/uses, property/event
  access sites, creator sites, TODO markers), and returns the combined edit set
  plus a human-readable report.

  Task 1 (skeleton) landed the public types plus stub bodies. Task 2 implements
  instance LOCATION (FindConvertInstances, a scan of the .dfm's 'object Name:
  Class' headers) plus surface #1 (.pas declaration retype: 'Name: FromType;'
  -> 'Name: ToType;') and surface #2 (.pas uses-add for each distinct ToType,
  via TFindUnitRefactoring.Build). Task 3 (this revision) adds surface #3: the
  .dfm object-block RE-EMIT. For each located instance, its object block is
  sliced out of the .dfm by LINE RANGE (the instance's skComponent/skForm
  symbol in the index -- the same DFM tree-sitter parse the indexer already
  ran, so StartLine/EndLine already span the whole 'object Name: Class ...
  end' block, nesting and all; no separate text-based bracket-matching is
  needed), re-emitted via the 2a-i engine (DRagLint.Convert.DfmReemit.
  ReemitComponent) driven by the F/T classes' members (TPropMemberCache via
  TConvertTreeCache, ToPersistent=True, references as leaves; 1.20.6 -- no tree),
  and replaces the original lines via a tekDeleteLines + tekInsertLines pair
  that preserves the block's original indentation. A ReemitComponent failure
  (Ok=False) skips the WHOLE instance -- no .pas retype/uses edits either --
  so a component is never left half-converted; see BuildApplyPlan's remarks.
  Task 5 adds surface #5: RUNTIME-CREATION sites. Every explicit 'FromType.
  Xxx(...)' construction (e.g. 'Edit1 := TOldEdit.Create(Self);') found in the
  .pas via FindConstructionSites gets its type token rewritten to ToType PLUS
  an unconditional TODO end-of-line comment marker -- ToType's constructor/
  init may take a different shape, and this applier never attempts to fix up
  constructor ARGUMENTS; the marker is the safety net. TApplyReport.
  CreatorSites/Todos are populated from this surface. Task 6 (this revision)
  adds surface #4: instance-scoped property/event ACCESS rewrite. For each
  renaming '#link ToMember <- FromMember' rule (ToMember <> FromMember,
  single-segment paths only), FindMemberAccessSites queries the .pas file's
  own refs for ref-gap G's 'member-access' kind (NameText=FromMember, at the
  member token's own span) and resolves each hit's RECEIVER by reading the
  source line text immediately before the member token (ResolveMemberAccess
  Receiver) -- the exprDot parser guarantees a plain identifier sits there.
  A site is only rewritten (FromMember -> ToMember, a tekReplaceInLine on the
  member token) when its receiver names one of THIS unit's converted
  instances (tracked via ConvertedInstNames, populated only for instances
  that survived the surface #3 re-emit checkpoint) -- an access on a
  different, unconverted receiver (e.g. 'Other.Caption' when Other is not a
  converted instance) is left untouched. TApplyReport.AccessSites is
  populated from this surface.
}

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  DRagLint.Core.Interfaces,
  DRagLint.Core.Model,
  DRagLint.Convert.Rules,
  DRagLint.Convert.DfmReemit,
  DRagLint.Convert.CastLib,
  DRagLint.Convert.PropTree,
  DRagLint.Convert.PropCache,
  DRagLint.Convert.UnitRules,
  DRagLint.Convert.UsesReconcile,  // dl:unit DRagLint.Convert.UsesReconcile accepted -- the KEEP_REASON_* / UNRESOLVED_* constants are its row vocabulary, read where the rows become warnings
  DRagLint.Refactor.TextEdit;

const
  /// <summary>apply/1 inherited[].action: the instance is left as it is (C8
  /// N1). A compatibility surface, like the other two.</summary>
  INH_ACTION_SKIPPED = 'skipped';
  /// <summary>apply/1 inherited[].action: the .dfm block is retyped and
  /// converted (C8 N2, 1.26.0).</summary>
  INH_ACTION_RETYPED = 'retyped';
  /// <summary>apply/1 inherited[].action: no .dfm block; only code access
  /// sites follow the converted ancestor (C8 N2a, 1.26.0).</summary>
  INH_ACTION_CODE = 'code';
  /// <summary>apply/1 inherited[].action: a code reference to a converted
  /// ancestor's field that the resolver did NOT bind -- not verified against
  /// the index, so not rewritten; reported as access-site-unverified (C8 N2
  /// review, 1.26.0).</summary>
  INH_ACTION_UNVERIFIED = 'unverified';
  /// <summary>apply/1 pas_uses[].status: a #link covers the member and
  /// convert-apply handles its .pas sites -- renamed, or nothing to rename
  /// (1.27.0).</summary>
  PAS_USE_MAPPED = 'mapped';
  /// <summary>apply/1 pas_uses[].status: a #link covers the member, but
  /// convert-apply makes NO .pas edit for that link shape -- a dotted To or
  /// From path (`#link Properties.X <- X`), so the site still names the From
  /// member and may not compile (1.27.0 review fix wave). Outranks
  /// PAS_USE_MAPPED; PAS_USE_CAST_REFUSED outranks it.</summary>
  PAS_USE_NOT_REWRITTEN = 'not-rewritten';
  /// <summary>apply/1 pas_uses[].status: a CLASS-cast #link covers the member,
  /// so its .pas sites are refused (cast-not-applied). A value cast (StripDB)
  /// counts as PAS_USE_MAPPED (PAS_USE_NOT_REWRITTEN on a dotted path).</summary>
  PAS_USE_CAST_REFUSED = 'cast-refused';
  /// <summary>apply/1 pas_uses[].status: no #link, but the To type (or an
  /// ancestor of it) has a member of that name -- carried implicitly.</summary>
  PAS_USE_SAME_NAME = 'same-name';
  /// <summary>apply/1 pas_uses[].status: no #link and no such member on the
  /// To type -- the work list.</summary>
  PAS_USE_UNMAPPED = 'unmapped';
  /// <summary>apply/1 pas_uses[].status: a global the .pas uses from a unit
  /// the reconciliation removes.</summary>
  PAS_USE_GLOBAL_DANGLING = 'global-dangling';
  /// <summary>apply/1 pas_uses[].resolution: Kind, DeclaringUnit and
  /// DeclaredIn are facts the index holds (1.28.2).</summary>
  PAS_RES_RESOLVED = 'resolved';
  /// <summary>apply/1 pas_uses[].resolution: the From class name has several
  /// unit-level declarers and neither the unit's uses clauses nor the book's
  /// qualification settles which one -- none is picked; Candidates names
  /// them, and Kind / DeclaringUnit / DeclaredIn are '' (1.28.2).</summary>
  PAS_RES_AMBIGUOUS = 'ambiguous';
  /// <summary>apply/1 pas_uses[].resolution: no --db holds the From class
  /// (1.28.2).</summary>
  PAS_RES_CLASS_NOT_FOUND = 'class-not-found';
  /// <summary>apply/1 pas_uses[].resolution: the From class resolved, but
  /// neither it nor any ancestor the index reaches declares the member
  /// (1.28.2).</summary>
  PAS_RES_MEMBER_NOT_FOUND = 'member-not-found';
  /// <summary>apply/1 pas_uses[].resolution, global rows only: the declaring
  /// unit is known but the index does not hold the symbol's kind
  /// (1.28.2).</summary>
  PAS_RES_KIND_UNKNOWN = 'kind-unknown';

type
  /// <summary>One component instance selected for conversion: its DFM instance
  /// name, its current (From) class, and the class it is being converted to
  /// (To), per the matching #convert rule.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Convert.Apply.pas), DRagLint.Convert.Apply.ConvertedInstancesOf (DRagLint.Convert.Apply.pas), DRagLint.Convert.Apply.FindConvertInstances (DRagLint.Convert.Apply.pas), DRagLint.Convert.Apply.FindDescendantUses (DRagLint.Convert.Apply.pas), DRagLint.Convert.Apply.SplitOnlyNames (DRagLint.Convert.Apply.pas) (+6 more)</para>
  /// <para>Used in units: DRagLint.Convert.Apply</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TConvertInstance = record
    InstanceName: string;
    FromType    : string;
    ToType      : string;
  end;

  /// <summary>One .dfm object of a From type that --only did NOT name but that
  /// converts anyway, because it is nested inside one --only did name (1.25.1;
  /// apply/1 only_included[]).</summary>
  /// <remarks>The parent's re-emit converts its nested From-type children
  /// (the owned-part recursion), so leaving the child out would convert it in
  /// the .dfm and not in the .pas -- form and code disagreeing. Parent is the
  /// nearest enclosing converted instance's name.</remarks>
  TNestedOnly = record
    Instance: TConvertInstance;
    Parent  : string;
  end;

  /// <summary>One INHERITED or INLINE .dfm object whose class is the From type
  /// of a #convert block, or one field a converted ancestor declares that the
  /// unit's code uses -- apply/1 inherited[] (C8 engine items N1, N2, N2a).</summary>
  /// <remarks>
  /// The component is DECLARED by an ancestor: the nearest class up the
  /// owner's ancestor chain whose .dfm opens it with `object` (or `inline`).
  /// The owner is the class of the nearest enclosing `inline` frame, else the
  /// .dfm's root class. AncestorState is 'unconverted' (that ancestor's object
  /// still has the From type), 'converted' (it has the block's To type),
  /// 'mismatched' (it has some third type) or 'outside' (not determinable: no
  /// ancestor in the --db declares it, the chain leaves the index, or an
  /// ancestor's .dfm is missing or binary; never guessed, item N3).
  /// AncestorUnit is the declaring unit; '' exactly when AncestorState is
  /// 'outside'. Action (1.26.0) is what the run does with it: 'retyped' (N2:
  /// state 'converted' -- the .dfm header is retyped to ToType, the block's
  /// properties converted, code access sites rewritten), 'code' (N2a: no .dfm
  /// block; a field a converted ancestor declares with ToType that the unit's
  /// code uses -- Line is then the first such reference in the .pas, and only
  /// code access sites are rewritten) or 'skipped' (every other state, and a
  /// retype that could not be planned; Reason says why).
  /// </remarks>
  TInheritedInstance = record
    Name         : string;  { the component name }
    TypeName     : string;  { its class as the .dfm spells it -- the block's From type }
    ToType       : string;  { the block's To type, bare }
    Line         : Integer; { 1-based line of its header in the unit's .dfm ('code': in the .pas) }
    OwnerClass   : string;  { the class whose ancestry declares it }
    AncestorUnit : string;  { the declaring ancestor's unit, or '' }
    AncestorState: string;  { 'unconverted', 'converted', 'mismatched' or 'outside' }
    Reason       : string;  { what happens to it and why, one sentence }
    Action       : string;  { 'retyped', 'code' or 'skipped' }
  end;

  /// <summary>One DESCENDANT unit that still streams or uses a component this
  /// run converts in its ancestor (apply/1 descendants[], 1.25.0) -- the
  /// descendant breaks at load or compile until C8 N2 retypes it.</summary>
  /// <remarks>
  /// A warning, never a refusal. UnitName is the descendant unit (a class
  /// descending from the converted unit's root class, any number of levels
  /// down, or a form hosting such a class as an `inline` frame). Reason is
  /// 'dfm' (its .dfm re-opens the component with `inherited` / `inline` and
  /// the From type), 'code' (a method of a descendant class references the
  /// field) or 'both'. Line is the descendant .dfm's block header for 'dfm' and
  /// 'both', else the first code reference in the descendant .pas.
  /// AncestorLine is the line of the component's `object` block in the
  /// CONVERTED unit's .dfm -- the N of the warning text.
  /// </remarks>
  TDescendantUse = record
    UnitName    : string;  { the descendant unit }
    Name        : string;  { the converted component }
    TypeName    : string;  { its From type, as the ancestor .dfm spells it }
    Line        : Integer; { 1-based; see the remarks }
    Reason      : string;  { 'dfm', 'code' or 'both' }
    AncestorLine: Integer; { 1-based line of its object header in the ancestor .dfm }
  end;

  /// <summary>What one reported line of a convert-apply run IS, as a stable
  /// machine-readable token -- the dispatchable half of the report, so a
  /// consumer never has to pattern-match the prose.</summary>
  /// <remarks>
  /// The wire spelling of each value is produced by ApplyItemKindName and is a
  /// COMPATIBILITY SURFACE (schema apply/1): adding a kind is additive, but
  /// renaming one is a breaking change and requires apply/2.
  /// The REMAINDER of a conversion -- everything the engine did not or could
  /// not carry over -- is exactly the subset of items whose Field is afTodos,
  /// afReemitNotes or afWarnings. aikMappingNotApplied is emitted by the
  /// #mapping surface (DRagLint.Convert.DfmReemit).
  /// NOT represented, deliberately: a property removed by an explicit #remove
  /// or acknowledged by #ignore. Both are silent by design, and whether a
  /// DELIBERATE removal counts as remainder at all is an open question for the
  /// converter side -- see docs\converter\apply-remainder-contract.md.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Convert.Apply.pas), DRagLint.Convert.Apply.ApplyItemKindName (DRagLint.Convert.Apply.pas), DRagLint.Convert.Apply.BuildApplyPlan.PlainItem (DRagLint.Convert.Apply.pas), DRagLint.Convert.Apply.PlanMigrateSites.Item (DRagLint.Convert.Apply.pas), DRagLint.Convert.Apply.ReconcileUnitUses.Warn (DRagLint.Convert.Apply.pas) (+2 more)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TApplyItemKind = (
    aikFieldRetyped,         { .pas published field decl retyped F -> T }
    aikAccessSiteRewritten,  { obj.Old -> obj.New at a .pas access site }
    aikCreatorRetyped,       { FromType.Create -> ToType.Create }
    aikDfmPathCreated,       { intermediate T sub-object synthesized (info) }
    aikCreatorVerify,        { the verify-creator marker left at a rewritten creator }
    aikCreatorUnverified,    { T has no indexed generic Create(AOwner) }
    aikUnmappedProperty,     { F property with a non-default value, dropped }
    aikBinaryTypeMismatch,   { binary/complex value whose F/T types differ }
    aikOwnedPartUnconverted, { nested owned part needing its own #convert }
    aikLinkStubUnfilled,     { #link ToPath still spelled '???' }
    aikCollectionRelocated,  { collection moved verbatim to a new path (info) }
    aikDefaultsMayDiverge,   { a rule-referenced source is absent AND has no
                               usable default, so the T default applies }
    aikCastNotApplied,       { #link carrying a cast, refused on the .pas side:
                               once per rule when the cast is unknown or has no
                               pas template, else once per access site (1.27.0:
                               a pas template is never realized -- Instance,
                               FilePath, Line set; Value is the cast). The
                               1.26.x kind 'cast-applied' is retired. }
    aikInstanceSkipped,      { whole instance skipped before any edit }
    aikFieldDeclNotRetyped,  { shared multi-declarator line, not retyped }
    aikUsesUnitUnresolved,   { no unit found declaring T, uses not added }
    aikMappingSourceAbsent,  { #apply'd #mapping's source is not in the block AND
                               has no usable default to resolve it to }
    aikMappingNotApplied,    { #apply'd #mapping matched no value }
    aikDefaultRuleSuperseded,{ #default skipped -- a rule already carried that path }
    aikDefaultResolved,      { F prop absent-because-default; its value was carried }
    aikEnumCastUnmapped,     { an enum cast had no map for this value and no else }
    aikUnlinkedSourceProperty,{ ONE line per (source type, property) that no
                               #link carries and no #ignore acknowledges, with the
                               site count as a FRACTION of that type's converted
                               instances. The per-instance 'dropped' lines above
                               are the sites; this is the rule-book gap they
                               share. Row 6 step 3, 2026-09-16. }
    aikSubLeafCarried,       { a sub-leaf carried IMPLICITLY under an identity
                               #link (Font <- Font, both TFont) -- nobody typed
                               it, and the report says so (info). }
    aikRulePathUnreachable,  { a #link / #default / #mapping line whose path
                               names members that exist but are inaccessible on
                               the .dfm surface -- skipped, never applied (owner
                               ruling R12, T2h). Path and RuleLine are set; the
                               structured facts are apply/1 unreachable[]. }
    aikInheritedInstanceSkipped, { an inherited / inline .dfm object of a
                               From type, skipped -- its ancestor declares it
                               (C8 N1). Instance and Line are set; the
                               structured facts are apply/1 inherited[]. }
    aikUnitRuleSkipped,      { a #unuse / #useswap removal NOT made because it
                               would strand instances --only left out (C13 N4).
                               RuleLine is the book line, Line the kept uses
                               entry's; the structured row is apply/1 uses[]
                               action 'skipped'. }
    aikDescendantNotConverted, { a descendant unit still streams or uses a
                               converted instance (1.25.0). Instance is the
                               component, Line its object line in the unit's
                               .dfm; the structured row is apply/1
                               descendants[]. }
    aikInheritedInstanceRetyped, { an inherited / inline .dfm object whose
                               declaring ancestor already has the To type,
                               retyped and its block converted (C8 N2,
                               1.26.0). Field converted; Instance and Line
                               (its .dfm header) are set; the structured row
                               is apply/1 inherited[] action 'retyped'. }
    aikAccessSiteUnverified, { a code access a rename would touch whose
                               receiver the index cannot tie to the converted
                               field -- no receiver reference on its line, an
                               unbound reference to a converted ancestor's
                               field, or a member reached through a `with`
                               block -- NOT rewritten (C8 N2 review, 1.26.0).
                               Field warnings; Line and Instance set. }
    aikBookWarning,          { a '#warn' whose source property the instance
                               streams (1.26.5). Field warnings; Instance, Path
                               (the FromPath), Value, RuleLine, Line set. }
    aikRefPathLike,          { a '#check-ref' value containing '\' or ':' --
                               a file path, not a name (1.26.5). Path = ToPath. }
    aikRefDangling,          { a '#check-ref' value no listed Class.Prop of
                               any .dfm in the project index carries (1.26.5). }
    aikRefNotChecked,        { '#check-ref' could not check: the project index
                               holds no .dfm property facts. Once per run. }
    aikUnitRuleKept,         { C9: a watched unit KEPT -- a .dfm component still
                               needs it (owner ruling 2); a WARNING (Q5).
                               RuleLine the book line, Line the uses entry's. }
    aikUsesUnitAmbiguous,    { C9 R8/R8a: a name two or more units declare --
                               none added; candidates in uses_unresolved[]. }
    aikUnitRuleUnverified,   { C9 Q3: a watched unit no --db indexes -- kept. }
    aikUnitRuleDangling,     { C9 ruling 1: a removal leaves .pas references
                               dangling -- the unit will not compile until that
                               code is converted. }
    aikValueCastApplied,     { 1.27.0 (C15): a VALUE cast (castlib `value`,
                               StripDB) rewrote a string literal in the .dfm or
                               the .pas -- field access_sites either way.
                               OldValue -> Value, FilePath, Line set. }
    aikValueCastCheck,       { 1.27.0 (C15): a value-cast site with no edit --
                               a .dfm value or .pas right-hand side that is not
                               ONE string literal, or a read. A warning. }
    aikConvertClassInferred, { owner ruling 2026-10-11: a bare #convert class
                               several units declare, settled by INFERENCE (the
                               project framework, the .dfm's properties) -- a
                               warning; RuleLine set, the structured row is
                               apply/1 qualify_fixes[] outcome 'inferred'. }
    aikMigrateApplied,       { C18 slice 1: a '#migrate Old -> New' inside a
                               #convert block renamed the member token at a
                               bound access site. Field access_sites; Instance,
                               FilePath, Line, RuleLine, Path (Old), Value (New),
                               OldValue (the member as written) set. }
    aikMigrateCheck,         { C18 slice 1: a #migrate site or rule NOT applied
                               -- a with block, an unverified receiver, a rule
                               form slice 1 does not realise, a member another
                               rule already converts. A warning; RuleLine and
                               Path (Old) set, Line / Instance when per site. }
    aikDeliberateBreak,      { C18 slice 1: '#migrate Old -> DL_NONE' wrapped a
                               site's member access, inst.Old ->
                               DL_NONE(inst.Old), so the unit does not compile
                               there until converted by hand (owner Q2: the old
                               text is kept). Field todos; Value 'DL_NONE',
                               OldValue the wrapped text. }
    aikEncodingNotChecked);  { 1.34.1 (CONV-ENC E3): a binary (TPF0) .dfm has no
                               text encoding, so the encoding guard never
                               compared it. A warning; FilePath set. }

  /// <summary>Which of TApplyReport's six legacy arrays an item was reported
  /// in. The wire spelling is produced by ApplyFieldName.</summary>
  /// <remarks>
  /// The three REMAINDER fields are afTodos, afReemitNotes and
  /// afWarnings; afConverted, afAccessSites and afCreatorSites describe work
  /// that WAS done.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Convert.Apply.pas), DRagLint.Convert.Apply.ApplyFieldName (DRagLint.Convert.Apply.pas), DRagLint.Convert.Apply.BuildApplyPlan.InstItem (DRagLint.Convert.Apply.pas), DRagLint.Convert.Apply.BuildApplyPlan.PlainItem (DRagLint.Convert.Apply.pas), DRagLint.Convert.Apply.PlanMigrateSites.Item (DRagLint.Convert.Apply.pas)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TApplyField = (afConverted, afAccessSites, afCreatorSites, afTodos,
                 afReemitNotes, afWarnings);

  /// <summary>One reported line of a convert-apply run, carrying both the
  /// original prose (Text) and the structured facts behind it.</summary>
  /// <remarks>
  /// Every item mirrors exactly one entry in one of TApplyReport's six legacy
  /// string arrays, so Length(Items) always equals the sum of their lengths --
  /// see TApplyReport's remarks.
  /// The non-Text fields are best-effort context, NOT guaranteed populated:
  /// which ones carry a value depends on Kind. Line is a 1-based line in
  /// FilePath and is 0 when unknown -- notably for anything derived from the
  /// DFM re-emit, because TDfmNode carries no line number, so such items can
  /// only be anchored to the instance's object-block header line. RuleLine is
  /// the 1-based line in the rules file that produced the item, or 0.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.CLI.DoConvertApply.MergeInferred (DRagLint.CLI.pas), DRagLint.CLI.DoConvertApply.MergeUnreachable (DRagLint.CLI.pas), DRagLint.CLI.EmitApplyJson (DRagLint.CLI.pas), DRagLint.CLI.EmitApplyJson.ItemJson (DRagLint.CLI.pas), DRagLint.CLI.PrintApplyReport (DRagLint.CLI.pas) (+32 more)</para>
  /// <para>Used in units: DRagLint.CLI, DRagLint.Convert.Apply</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TApplyItem = record
    Kind    : TApplyItemKind;
    Field   : TApplyField;
    Instance: string;  { the .dfm instance name, when the item is about one }
    FromType: string;
    ToType  : string;
    FilePath: string;  { absolute path of the file the item is about }
    Path    : string;  { a .dfm property path, when the item is about one }
    Text    : string;  { the human-readable line, verbatim }
    Line    : Integer; { 1-based line in FilePath, or 0 }
    RuleLine: Integer; { 1-based line in the rules file, or 0 }
    Value   : string;  { 1.26.5: the value a book-warning / ref-* item is about; 1.27.0: the cast of a cast-not-applied item, the NEW literal of a value-cast-applied one; '' otherwise }
    OldValue: string;  { 1.27.0: the literal a value-cast-applied item replaced; '' otherwise }
  end;

  /// <summary>One F property that was absent from the .dfm because it sat at its
  /// declared default, whose value was resolved and written into the target
  /// explicitly. INFORMATIONAL: the work was done and needs no follow-up.</summary>
  /// <remarks>
  /// <para>LIVES OUTSIDE TApplyReport.Items ON PURPOSE. This is the one kind
  /// whose volume scales with the FORM rather than with the defects in it: a
  /// real VARINSP-sized form produces on the order of 2,000 of these against at
  /// most ~1,200 real properties, and items[] is the array a consumer dispatches
  /// on. Leaving them there buried the four kinds a human must actually act on
  /// under work that had already succeeded.</para>
  /// <para>SLIMMER THAN TApplyItem, deliberately. `kind` and `field` would be the
  /// same constant on every entry; `file` is the document's own `dfm`; and `text`
  /// -- the ~130-byte prose -- is the bulk of an item and now carries nothing
  /// that is not a typed key here. ToPath and Value in particular were dropped
  /// on the floor before this record existed: they were recoverable only by
  /// parsing English out of that prose.</para>
  /// <para>FromType/ToType are omitted: they are per-instance constants,
  /// recoverable from the instance's `field-retyped` item. Known gap, accepted --
  /// an owned part with no .pas declaration has no such item, so its types live
  /// only in `converted[]` prose; RuleLine still points at the `#link` under its
  /// `#convert` header, which is the line to edit if the carry was wrong.</para>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Convert.Apply.pas), DRagLint.CLI.EmitApplyJson (DRagLint.CLI.pas), DRagLint.Convert.Apply.BuildApplyPlan (DRagLint.Convert.Apply.pas), DRagLint.Convert.Apply.BuildApplyPlan.EmitResolved (DRagLint.Convert.Apply.pas), DRagLint.Convert.Apply.BuildApplyPlan.FoldReemitReport (DRagLint.Convert.Apply.pas)</para>
  /// <para>Used in units: DRagLint.CLI, DRagLint.Convert.Apply</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TApplyResolvedDefault = record
    Instance: string;  { the .dfm instance -- a nested part appears under its OWN name }
    FromPath: string;  { the F property that was absent because it was at its default }
    ToPath  : string;  { where the value was written }
    Value   : string;  { the resolved default, verbatim }
    RuleLine: Integer; { 1-based line of the #link that carried it, or 0 }
    Line    : Integer; { 1-based line of the instance's .dfm object header, or 0 }
  end;

  /// <summary>One rule-book gap: a source property that at least one converted
  /// instance of FromType carried in its .dfm block and that no #link carries
  /// and no #ignore acknowledges. Keyed by (FromType, Path), NOT by Path alone:
  /// two source types both dropping 'Style' are two gaps, and collapsing them
  /// would hide one the moment a book grows a second #convert block.</summary>
  /// <remarks>
  /// <para>Sites is how many converted instances of FromType carried the
  /// property; Instances is how many instances of FromType were converted at
  /// all. The pair is the whole point (converter team, 2026-09-16): a MINORITY
  /// site count is the STRONGER signal. 20 of 20 dropping Style is a deliberate
  /// non-mapping; 2 of 20 dropping Font.* is the two buttons somebody styled
  /// with ParentFont=False, and dropping those silently restyles exactly the
  /// controls someone cared about. A bare 'x2' invites a skim; '2 of 20' does
  /// not.</para>
  /// <para>The denominator is instances that CONVERTED (cleared the re-emit
  /// checkpoint), not instances found -- a skipped instance produced no
  /// Dropped list, so counting it would understate every fraction.</para>
  /// <para>Sorted by FromType then Path, case-insensitively, so the order is
  /// stable across runs and does not depend on .dfm instance order.</para>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Convert.Apply.pas), DRagLint.CLI.EmitApplyJson (DRagLint.CLI.pas), DRagLint.Convert.Apply.BuildApplyPlan.SummarizeUnlinked (DRagLint.Convert.Apply.pas)</para>
  /// <para>Used in units: DRagLint.CLI, DRagLint.Convert.Apply</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TApplyUnlinked = record
    FromType : string;  { the #convert source type, as the rule spells it }
    Path     : string;  { the dotted source property path, as the .dfm spells it }
    Sites    : Integer; { converted instances of FromType that carried it }
    Instances: Integer; { converted instances of FromType, the denominator }
  end;

  /// <summary>One thing the unit's .pas still uses that a conversion must
  /// account for (apply/1 pas_uses[], 1.27.0): a member reached through a
  /// converted instance, or a global from a unit the reconciliation
  /// removes.</summary>
  /// <remarks>
  /// <para>A MEMBER row is keyed by (Instance, Member). Its sites are the
  /// access-site rewrite's own (FindMemberAccessSites + BoundAccessSites), so
  /// a site the index cannot vouch for is NOT listed. A member reached through
  /// 'with inst do' IS listed (G10) when the index resolved the receiverless
  /// ref, in the routine of that with line, to the member the From class
  /// declares; it is never rewritten. Kind, Visibility,
  /// DeclaredIn and DeclaringUnit describe the member as the From type -- or
  /// the nearest ancestor of it that declares it, across the --db stores --
  /// has it; all four are '' when no store holds it, and Resolution then
  /// says why. The From class (and an ancestor the class's own store cannot
  /// resolve) is resolved through the SCOPE of the unit that names it, never
  /// by bare name alone (1.28.2): the unit itself, then its uses entries
  /// (the last one that declares the name wins, as in Delphi; an interface
  /// declaration sees the interface uses only), then the book's own
  /// qualification of the #convert From type, then a lone declarer; several
  /// declarers left over is PAS_RES_AMBIGUOUS, with Candidates.</para>
  /// <para>A GLOBAL row (Status PAS_USE_GLOBAL_DANGLING) has Instance,
  /// FromType, ToType and Visibility ''; it is the reconciliation's own
  /// dangling verdict (TUsesReconcileResult.Dangling), uncapped, so it exists
  /// only when the reconciliation ran (not with --no-reconcile-uses, nor when
  /// it degraded).</para>
  /// <para>Lines are 1-based lines of the unit as read, distinct and sorted.
  /// Kind is one of method, property, field, event, const, var, type,
  /// routine, enum-value, or '' when unknown; an event is a property named
  /// On + a capital letter. Kind is '' exactly when Resolution is not
  /// PAS_RES_RESOLVED.</para>
  /// </remarks>
  TApplyPasUse = record
    Instance     : string;  { the converted instance; '' for a global }
    FromType     : string;
    ToType       : string;
    Member       : string;  { the member, or the global's name }
    Kind         : string;
    Visibility   : string;  { the member's declared visibility; '' when unknown or global }
    DeclaringUnit: string;
    DeclaredIn   : string;  { the class declaring the member (maybe an ancestor of FromType); a helper type for a global }
    Status       : string;  { a PAS_USE_* constant }
    Lines        : TArray<Integer>;
    Resolution   : string;  { a PAS_RES_* constant (1.28.2) }
    Candidates   : TArray<string>;  { the declaring units, PAS_RES_AMBIGUOUS only (1.28.2) }
    MigrateTo    : string;  { G4: the New of the #migrate convert-apply realises for the member (DL_NONE_MARK for a break); '' when none }
  end;

  /// <summary>Human-readable summary of one convert-apply run, grouped by
  /// surface: Converted lists one line per instance actually rewritten;
  /// AccessSites and CreatorSites list the .pas property/event-access and
  /// object-creation call sites that were rewritten; Todos lists spots that
  /// need manual follow-up (e.g. an unmapped property); ReemitNotes carries
  /// the per-instance notes from the DFM re-emit engine (DRagLint.Convert.
  /// DfmReemit); Warnings lists non-fatal problems found while building the
  /// plan.</summary>
  /// <remarks>
  /// Items is the SAME report in typed form: one TApplyItem per entry across
  /// the six string arrays, in emission order, each carrying the kind and the
  /// structured facts the prose was rendered from.
  /// INVARIANT 1: Length(Items) = the sum of the lengths of the six arrays.
  /// BuildApplyPlan maintains it structurally -- every report line is appended
  /// through a single Emit, which writes to exactly one array and to Items.
  /// The six arrays are kept as-is so existing text consumers are unaffected.
  /// INVARIANT 2: ResolvedDefaults is DISJOINT from Items and from all six
  /// arrays. It is appended through EmitResolved, which is the only writer and
  /// touches nothing else, so invariant 1 above is unaffected by it. A
  /// `default-resolved` entry appears in ResolvedDefaults and NOWHERE ELSE --
  /// that separation is the whole point of the record (see
  /// TApplyResolvedDefault), and a consumer summing the six arrays to predict
  /// Length(Items) must NOT add this one in.
  /// INVARIANT 3: Unlinked is likewise disjoint from Items and the six arrays;
  /// it is derived from the aikUnmappedProperty items AFTER the instance loop
  /// and is ALWAYS populated. The matching aikUnlinkedSourceProperty warnings
  /// (one per Unlinked entry, in Warnings AND Items, so invariant 1 holds) are
  /// emitted only when BuildApplyPlan's AWarnUnlinked is True -- so a caller
  /// that silences the warning still gets the count.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.CLI.pas), declaration (DRagLint.Convert.Apply.pas), DRagLint.CLI.DoConvertApply.MergeInferred (DRagLint.CLI.pas), DRagLint.CLI.DoConvertApply.MergeUnreachable (DRagLint.CLI.pas), DRagLint.CLI.PrintApplyReport (DRagLint.CLI.pas)</para>
  /// <para>Used in units: DRagLint.CLI, DRagLint.CLI.CycleFix, DRagLint.Convert.Apply</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TApplyReport = record
    Converted   : TArray<string>;
    AccessSites : TArray<string>;
    CreatorSites: TArray<string>;
    Todos       : TArray<string>;
    ReemitNotes : TArray<string>;
    Warnings    : TArray<string>;
    Items       : TArray<TApplyItem>;
    { Disjoint from Items and from the six arrays above -- see invariant 2. }
    ResolvedDefaults: TArray<TApplyResolvedDefault>;
    { Disjoint likewise -- see invariant 3. One entry per (source type, property)
      no #link carries; always populated, whether or not it was also warned. }
    Unlinked        : TArray<TApplyUnlinked>;
    { Disjoint likewise. The uses-clause changes the book's UNIT rules (#unuse /
      #use / #useswap) make to the unit -- one row per removed or added name
      (see DRagLint.Convert.UnitRules.TUsesChange). Empty when the book has no
      unit rules; the #convert blocks' own uses-add never appears here. }
    UsesChanges     : TArray<TUsesChange>;
    { C9 (1.27.0): names the conversion introduced whose unit was not added
      (ambiguous / not-found) -- apply/1 uses_unresolved[]. }
    UsesUnresolved  : TArray<TUsesUnresolved>;
    { C9: 'on', 'off' (--no-reconcile-uses) or 'degraded' (the re-index of
      the converted output failed: every watched unit kept) -- apply/1
      uses_reconcile. }
    UsesReconcile   : string;
    { 1.27.0: disjoint likewise. What the .pas still uses that the map does
      not cover -- member rows (sorted by instance, then member) followed by
      global-dangling rows (sorted by name); see TApplyPasUse. }
    PasUses         : TArray<TApplyPasUse>;
  end;

  /// <summary>The outcome of BuildApplyPlan: the full set of text edits to
  /// apply (see DRagLint.Refactor.TextEdit.TTextEditApplier.Apply /
  /// RenderDryRun), the human-readable Report, and Ok/Error signalling
  /// whether a plan could be built at all.</summary>
  /// <remarks>
  /// Ok=False means no edits were computed (e.g. the .pas/.dfm file
  /// was not found, or no instance matched a #convert rule -- possibly because
  /// --only filtered everything out, or the book's unit rules refused the unit);
  /// Error then carries an ASCII diagnostic
  /// message. Ok=True does not imply every instance converted cleanly --
  /// per-instance problems are surfaced via Report.Todos / Report.Warnings
  /// even when Ok=True (e.g. a field declaration that could not be located, or
  /// a ToType whose unit could not be resolved for the uses-add).
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Convert.Apply.pas), DRagLint.CLI.DoConvertApply (DRagLint.CLI.pas), DRagLint.CLI.DoConvertApply.RunUnit (DRagLint.CLI.pas), DRagLint.CLI.RefuseUnapplicablePlan (DRagLint.CLI.pas), DRagLint.Convert.Apply.BuildApplyPlan (DRagLint.Convert.Apply.pas) (+1 more)</para>
  /// <para>Used in units: DRagLint.CLI, DRagLint.Convert.Apply</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TApplyResult = record
    Edits : TArray<TTextEdit>;
    Report: TApplyReport;
    Ok    : Boolean;
    Error : string;
    /// <summary>True when Ok=False is a DELIBERATE refusal -- the unit cannot
    /// be converted safely, so nothing was planned and nothing may be written
    /// -- rather than a failure. convert-apply reports it as apply/1
    /// refused=true, reason=Error, and prints 'REFUSED: ' + Error.</summary>
    Refused: Boolean;
    /// <summary>A refused result: Ok=False, Refused=True, Error=AReason, no
    /// edits. The one call a planner makes to refuse a unit.</summary>
    /// <param name="AReason">Why the unit is refused; one ASCII line, shown
    /// verbatim to the user and to the editor.</param>
    /// <returns>The refused result.</returns>
    class function Refusal(const AReason: string): TApplyResult; static;
  end;

  /// <summary>The rule book convert-apply runs: the parsed rules and what
  /// validation found UNREACHABLE in them (owner ruling R12, T2h).</summary>
  /// <remarks>A record so BuildApplyPlan keeps within the parameter limit;
  /// the two halves always travel together.</remarks>
  TApplyBook = record
    Rules      : TConversionRuleSet;
    Unreachable: TArray<TUnreachablePath>;
    /// <summary>C9: reconcile the unit's uses clauses (default on in the CLI;
    /// False reproduces 1.26.6 exactly).</summary>
    Reconcile  : Boolean;
    /// <summary>Pairs a rule set with its unreachable records.</summary>
    /// <param name="ARules">The parsed, validated rules.</param>
    /// <param name="AUnreachable">ValidateConversionRulesPerBlock's records.</param>
    /// <returns>The pair.</returns>
    class function Create(const ARules: TConversionRuleSet;
      const AUnreachable: TArray<TUnreachablePath>): TApplyBook; static;
  end;

  /// <summary>Outcome of CheckFreshness: whether the F and T types' indexed
  /// source is safe to trust for this convert-apply run.</summary>
  /// <remarks>
  /// Fresh=True only when BOTH the From and To types are indexed
  /// (ResolveClassQName resolves a qualified name) AND their declaring
  /// source files are up to date on disk (ISymbolStore.FileIsUpToDate,
  /// comparing the CURRENT on-disk mtime+sha256 against what was indexed).
  /// Fresh=False covers two distinct causes, both surfaced as human-readable
  /// entries in Reasons: (a) "stale" -- the type IS indexed but its source
  /// file has changed on disk since the last index run, so BuildPropTree
  /// would be working from an outdated property tree; (b) "not indexed" --
  /// ResolveClassQName returned '' for the type, so BuildPropTree would
  /// silently get an EMPTY tree (no properties, no events) rather than an
  /// error. Both are guard failures for the same reason: the conversion plan
  /// would be built from a property tree that does not reflect the type's
  /// real current shape.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.CLI.pas), declaration (DRagLint.Convert.Apply.pas), DRagLint.CLI.DoConvertApply (DRagLint.CLI.pas), DRagLint.CLI.DoConvertApply.RunUnit (DRagLint.CLI.pas), DRagLint.Convert.Apply.CheckFreshness (DRagLint.Convert.Apply.pas) (+1 more)</para>
  /// <para>Used in units: DRagLint.CLI, DRagLint.Convert.Apply</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TFreshnessResult = record
    Fresh  : Boolean;
    Reasons: TArray<string>;
  end;
  /// <summary>The .dfm values one project index holds, for '#check-ref'
  /// (1.26.5).</summary>
  /// <remarks>Keys holds 'CLASS|PROP|VALUE' upper-cased, CLASS the bare .dfm
  /// type token of the component that streams PROP = VALUE. Rows is how many
  /// dfm-prop rows it was built from; 0 means the index has no facts to check
  /// against. Owned by TConvertTreeCache; built once per store per run.</remarks>
  TRefFacts = class
  private
    FKeys: TDictionary<string, Boolean>;
    FRows: Integer;
  public
    /// <summary>Creates an empty fact set.</summary>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Convert.Apply.TConvertTreeCache.RefFactsFor (DRagLint.Convert.Apply.pas)</para>
    /// <para>constructor</para>
    /// <para>Writes: FKeys</para>
    /// <seealso cref="DRagLint.Convert.Apply.TRefFacts.Add"/>
    /// <seealso cref="DRagLint.Convert.Apply.TRefFacts.Destroy"/>
    /// <seealso cref="DRagLint.Convert.Apply.TRefFacts.Has"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    constructor Create;
    /// <summary>Frees Keys.</summary>
    destructor Destroy; override;
    /// <summary>Records one dfm-prop row: AClass (the component's .dfm type
    /// token) streams AProp = AValue.</summary>
    /// <param name="AClass">The type token; qualified or bare.</param>
    /// <param name="AProp">The property name.</param>
    /// <param name="AValue">The streamed value text.</param>
    procedure Add(const AClass, AProp, AValue: string);
    /// <summary>Whether some .dfm streams AProp = AValue on a component of
    /// class AClass (bare names, case-insensitive).</summary>
    /// <param name="AClass">The class; qualified or bare.</param>
    /// <param name="AProp">The property name.</param>
    /// <param name="AValue">The value.</param>
    /// <returns>True when such a row was added.</returns>
    function Has(const AClass, AProp, AValue: string): Boolean;
    /// <summary>The dfm-prop rows added; 0 = no facts to check against.</summary>
    property Rows: Integer read FRows;
  end;

  /// <summary>A class name as one unit's scope resolves it (1.28.2,
  /// pas_uses[]; the #convert classes too since the link-scope fix).</summary>
  /// <remarks>QName is set only when Resolution is PAS_RES_RESOLVED;
  /// Candidates (the declaring units, sorted) only when it is
  /// PAS_RES_AMBIGUOUS. Resolution '' means the name was never asked
  /// about.</remarks>
  TScopedClass = record
    /// <summary>The qualified class; '' unless Resolution is
    /// PAS_RES_RESOLVED.</summary>
    QName     : string;
    /// <summary>PAS_RES_RESOLVED / PAS_RES_AMBIGUOUS /
    /// PAS_RES_CLASS_NOT_FOUND; '' = not asked.</summary>
    Resolution: string;
    /// <summary>The declaring units, PAS_RES_AMBIGUOUS only.</summary>
    Candidates: TArray<string>;
    /// <summary>Index-aligned with Candidates: why each was not chosen
    /// ('not in the unit''s uses', 'framework mismatch: ...', '.dfm property X
    /// not declared', 'tie: ...'). ScopedClass only.</summary>
    Why: TArray<string>;
    /// <summary>Set when ScopedClass settled an otherwise ambiguous bare name
    /// by INFERENCE (owner ruling 2026-10-11): what it was inferred from --
    /// 'the project framework VCL (P.dproj)' or '.dfm properties WordWrap,
    /// Layout'. QName is then the class chosen and Candidates / Why keep the
    /// ones it was chosen over. '' otherwise.</summary>
    Inferred: string;
  end;

  /// <summary>One ready-to-paste replacement for an ambiguous or inferred
  /// #convert line (apply/1 qualify_fixes[].suggestions[]).</summary>
  TQualifySuggestion = record
    /// <summary>The whole #convert line with the bare name qualified.</summary>
    Replacement: string;
    /// <summary>The qualified class this replacement names.</summary>
    Candidate  : string;
    /// <summary>Why this candidate is (or is not) the one: the inference, or
    /// the reason it was not chosen.</summary>
    Why        : string;
    /// <summary>The other way to settle it: '#use Unit' for a To type, 'add
    /// Unit to the unit''s uses' for a From type.</summary>
    Alternative: string;
  end;

  /// <summary>A #convert line whose bare class name had several declarers
  /// (apply/1 qualify_fixes[], capability convert_qualify_fix): REFUSED, or
  /// settled by inference and warned about.</summary>
  /// <remarks>Built by MakeQualifyFix; the editor offers Suggestions as a
  /// one-click correction of the line RuleLine.</remarks>
  TQualifyFix = record
    /// <summary>The #convert line's number in the rules file.</summary>
    RuleLine   : Integer;
    /// <summary>That line as written.</summary>
    Current    : string;
    /// <summary>The bare class name.</summary>
    Name       : string;
    /// <summary>'from' or 'to': the side of the line it is on.</summary>
    Side       : string;
    /// <summary>'refused' or 'inferred'.</summary>
    Outcome    : string;
    /// <summary>The class inferred; '' when refused.</summary>
    Chosen     : string;
    /// <summary>What the class was inferred from; '' when refused.</summary>
    Inference  : string;
    /// <summary>One per candidate; the chosen one first, else sorted.</summary>
    Suggestions: TArray<TQualifySuggestion>;
    /// <summary>The first suggestion's Alternative.</summary>
    Alternative: string;
  end;

  /// <summary>The classes one convert-apply run works from: each type name
  /// resolved ONCE per unit scope, and one member cache per --db store, shared
  /// by rule validation and BuildApplyPlan.</summary>
  /// <remarks>
  /// A type name (a #convert header or a .dfm object's class) is resolved to a
  /// qualified class name. A QUALIFIED name resolves only to a class whose
  /// qualified name is exactly that, first store that holds it wins, so
  /// 'LibX.TNope' never resolves to another unit's TNope. A BARE name resolves
  /// through ScopedClass -- the same in-scope rule as pas_uses[]
  /// (ResolveClassInScope) in the unit SetScope named: the unit's own class,
  /// the last uses entry declaring it, a lone unit-level declarer. A nested
  /// class is never a declarer, and a bare name the scope cannot settle
  /// resolves to NOTHING (it used to be the first class of that name across
  /// the stores -- FMX.StdCtrls.TLabel for a VCL unit). ClassFor
  /// pairs that name with the TPropMemberCache of its store, so a bare and a
  /// qualified spelling of one type share one cache entry. 1.20.6 (T2b): no
  /// property tree is built any more -- every rule path and every dotted .dfm
  /// path is resolved segment by segment, each class's members once per run
  /// (the old depth-6 trees took hours on FireDAC.Comp.Client.TFDQuery). Every
  /// cache uses the options BuildApplyPlan has always used: ancestor climb
  /// stopped at TPersistent, referenced components as leaves; validation uses
  /// the same caches, so a path it accepts is a path the plan can apply.
  /// ClassesBuilt counts the classes resolved (apply/1 classes_built). The
  /// object owns its caches, not Stores; the caller keeps them alive. Not
  /// thread-safe.
  /// </remarks>
  TConvertTreeCache = class
  private type
    TResolved = record
      QName: string;
      Store: Integer;
    end;
  private
    FStores  : TArray<ISymbolStore>;
    FResolved: TDictionary<string, TResolved>;
    FCaches  : TArray<TPropMemberCache>; { index-aligned with FStores; nil until first used }
    FOptions : TPropTreeOptions;
    FRefFacts: TArray<TRefFacts>; { index-aligned with FStores; nil until first asked }
    FUnitIndex: TUsesUnitIndex;   { C9; nil until first asked }
    FDbPaths : TArray<string>;
    FScopeStore : ISymbolStore;                        { SetScope's unit: the store indexing it }
    FScopeFileId: Int64;                               { ... and its file id there; 0 = no scope }
    FScopePath  : string;                              { ... the path SetScope was given }
    FScoped     : TDictionary<string, TScopedClass>;   { UPPER name|hint -> ScopedClass's answer }
    FToOnly     : TArray<string>;                      { bare #convert To names that are no block's From }
    FBookUnits  : TArray<string>;                      { the units the unit uses AFTER the book (BookChosenUnits) }
    FFrameworkDone: Boolean;                           { FFramework read for this scope }
    FFramework    : string;                            { 'VCL' / 'FMX' / '' -- the scope unit's project }
    FFrameworkSrc : string;                            { the .dproj it was read from }
    function InferAmbiguous(const AName: string; var AScoped: TScopedClass): Boolean;
    function Lookup(const ATypeName: string): TResolved;
    function GetClassesBuilt: Integer;
  public
    /// <summary>Creates an empty cache over AStores.</summary>
    /// <param name="AStores">The indexes to resolve against, in --db order.
    /// Not owned.</param>
    constructor Create(const AStores: TArray<ISymbolStore>);
    /// <summary>Frees the member caches.</summary>
    destructor Destroy; override;
    /// <summary>The qualified class name ATypeName resolves to.</summary>
    /// <param name="ATypeName">A bare or qualified class name.</param>
    /// <returns>The qualified name, or '' when no store has such a class or
    /// a bare name is ambiguous in the SetScope unit (see
    /// ScopedClass).</returns>
    /// <remarks>Cheap (a name lookup, no tree build); cached.</remarks>
    function ResolveType(const ATypeName: string): string;
    /// <summary>The member cache of one store, created on first use.</summary>
    /// <param name="AStore">An index into Stores.</param>
    /// <returns>The cache; nil when AStore is out of range.</returns>
    function CacheFor(AStore: Integer): TPropMemberCache;
    /// <summary>The '#check-ref' facts of one store, built on first use and
    /// kept for the run (1.26.5).</summary>
    /// <param name="AStore">One of Stores.</param>
    /// <returns>The facts, owned by this object; nil when AStore is not one
    /// of Stores.</returns>
    /// <remarks>Reads every .dfm's dfm-prop rows once, and the component
    /// classes with one FindSymbolsByFile per .dfm. Shared by every unit of
    /// a batch run.</remarks>
    function RefFactsFor(const AStore: ISymbolStore): TRefFacts;
    /// <summary>ATypeName as one side of a conversion.</summary>
    /// <param name="ATypeName">A bare or qualified class name.</param>
    /// <returns>Its qualified name and the cache of the store it resolved in;
    /// an unset TClassRef (QName='', Cache=nil) when no store has such a
    /// class.</returns>
    /// <remarks>Cheap: a name lookup. Members are resolved lazily, when a path
    /// is asked for.</remarks>
    function ClassFor(const ATypeName: string): TClassRef;
    /// <summary>The class symbol ATypeName resolves to, and the store
    /// holding it (1.27.0, pas_uses[]).</summary>
    /// <param name="ATypeName">A bare or qualified class name.</param>
    /// <param name="AStore">The store the class was resolved in; nil when
    /// none.</param>
    /// <returns>The class symbol; Id = 0 when no store has such a class.</returns>
    function ClassSymbol(const ATypeName: string; out AStore: ISymbolStore): TSymbol;
    /// <summary>The stores this cache resolves against, in --db order.</summary>
    property Stores: TArray<ISymbolStore> read FStores;
    /// <summary>How many classes the member caches have resolved, summed over
    /// the stores (apply/1 classes_built).</summary>
    property ClassesBuilt: Integer read GetClassesBuilt;
    /// <summary>The run's indexed unit set for the uses reconciliation (C9),
    /// built on first use and shared by every unit of a batch.</summary>
    /// <returns>The index, owned by this object.</returns>
    function UnitIndex: TUsesUnitIndex;
    /// <summary>The --db paths, index-aligned with Stores (C9: they name the
    /// db of a uses_unresolved candidate). Set by the caller; may be empty.</summary>
    property DbPaths: TArray<string> read FDbPaths write FDbPaths;
    /// <summary>Names the unit whose scope a BARE type name resolves in from
    /// now on, and the book converting it.</summary>
    /// <param name="AUnitPas">The converted unit's .pas; '' clears the scope
    /// (a bare name then resolves only through a lone unit-level declarer or
    /// a hint).</param>
    /// <param name="ARules">The book. A bare #convert To type that is no
    /// block's From is a class of the unit AFTER conversion: when several
    /// units declare it, the one the book makes the unit use (a #use, a
    /// #convert block's trailing unit, a #useswap New whose Old the unit uses,
    /// a uses entry the book does not remove -- the uses reconciliation's own
    /// tie rule, C9 A8-1) settles it before the unit's current scope
    /// does.</param>
    /// <remarks>Finds the store that indexes AUnitPas; a unit no store
    /// indexes is no scope. A different unit forgets every cached
    /// resolution -- a bare name can name another class there. The same unit
    /// again is a no-op.</remarks>
    procedure SetScope(const AUnitPas: string; const ARules: TConversionRuleSet);
    /// <summary>ATypeName as the SetScope unit sees it -- the one resolution
    /// rule every #convert class, ClassFor / ResolveType included, goes
    /// through (ResolveClassInScope).</summary>
    /// <param name="ATypeName">A bare or qualified class name.</param>
    /// <param name="AHint">A qualified spelling of the same class (the
    /// book's #convert line), used only when the scope does not settle a bare
    /// name; '' for none.</param>
    /// <returns>A qualified name: PAS_RES_RESOLVED exactly when a class of
    /// that qualified name exists. A bare name: PAS_RES_RESOLVED with the
    /// class, PAS_RES_AMBIGUOUS with the declaring units in Candidates (none
    /// picked), or PAS_RES_CLASS_NOT_FOUND. A nested class is never a
    /// declarer.</returns>
    /// <remarks>Cached per name and hint until the scope changes. A bare
    /// name the scope leaves ambiguous is then INFERRED when exactly one
    /// candidate survives (owner ruling 2026-10-11): first the project's
    /// framework (the .dproj beside the scope unit's project file --
    /// FrameworkType, else DCC_Namespace -- drops a Vcl.* or FMX.* candidate of
    /// the other framework), then the form file's kind (a .dfm form is VCL, a
    /// .fmx form FMX: a candidate of the other framework is dropped), then
    /// the .dfm evidence (a candidate that does not
    /// declare a property the scope unit's .dfm streams on an object of that
    /// class, and another candidate does, is dropped). Inferred then names
    /// the evidence; Why says why each other candidate was dropped.</remarks>
    function ScopedClass(const ATypeName: string; const AHint: string = ''): TScopedClass;
  end;

/// <summary>The machine-readable fix for a #convert line whose bare class
/// name was ambiguous (apply/1 qualify_fixes[]).</summary>
/// <param name="ALineText">The #convert line as written in the rules
/// file.</param>
/// <param name="ALine">Its line number.</param>
/// <param name="AName">The bare class name.</param>
/// <param name="ASide">'from' or 'to'.</param>
/// <param name="AScoped">ScopedClass's answer: PAS_RES_AMBIGUOUS (a refusal)
/// or PAS_RES_RESOLVED with Inferred set (an inference).</param>
/// <returns>Outcome 'refused' or 'inferred'; one suggestion per class --
/// the line with AName qualified on ASide -- the inferred one first, the rest
/// sorted.</returns>
function MakeQualifyFix(const ALineText: string; ALine: Integer; const AName, ASide: string;
  const AScoped: TScopedClass): TQualifyFix;
/// <summary>The detailed refusal text of one 'refused' fix: the line, the
/// bare name, every candidate with why it was not chosen, and what to
/// do.</summary>
/// <param name="AFix">A MakeQualifyFix result.</param>
/// <returns>One line, no line break.</returns>
function QualifyRefusalText(const AFix: TQualifyFix): string;
/// <summary>The warning text of one 'inferred' fix.</summary>
/// <param name="AFix">A MakeQualifyFix result with Outcome 'inferred'.</param>
/// <returns>'#convert X resolved to Unit.X (line N): inferred from ...;
/// qualify the line to silence this: <replacement>'.</returns>
function QualifyInferredText(const AFix: TQualifyFix): string;


/// <summary>Verifies the F and T component types named by EVERY #convert
/// block of ARules are indexed and current before BuildApplyPlan trusts
/// their members.</summary>
/// <param name="AStores">The symbol indexes to check against, in the order
/// given (one per --db); the first store that resolves a given type wins
/// (see CheckTypeFreshness's remarks) -- the From and To types, and the
/// form's own instances, may live in DIFFERENT --db files.</param>
/// <param name="ARules">The conversion rule set; the FromType/ToType of EVERY
/// rkConvert block are checked, each distinct type once (1.20.6: it used to be
/// the first block's pair only, so a stale unit behind block 2..N passed; T2b
/// dropped the short-lived per-unit block scope, so a stale type of any block
/// warns on a dry run and refuses --apply, a unit-rules-only run included).</param>
/// <returns>A TFreshnessResult. Fresh=True when every such type resolves to an
/// indexed class in SOME store AND its declaring file is up to date on
/// disk. Fresh=False with one or more human-readable Reasons entries
/// otherwise (see TFreshnessResult's remarks for the two distinct failure
/// causes).</returns>
/// <remarks>
/// Pure read-only: computes the on-disk mtime (unix seconds) and
/// sha256 of each type's declaring source file (mirroring DRagLint.Core.
/// Indexer's own incremental-skip basis: raw bytes, ANSI-decoded for the
/// sha) and asks the store whether that exact (mtime, sha) pair is what is
/// indexed. A type with no #convert rule in ARules at all is treated as
/// vacuously fresh (nothing to check) -- callers should have already
/// validated ARules has at least one #convert rule before reaching here.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.DoConvertApply.RunUnit (DRagLint.CLI.pas)</para>
/// <para>Calls: BareTypeTail, CheckTypeFreshness, Default, DRagLint.Convert.Apply.CheckFreshness.CheckOnce, UpperCase</para>
/// <para>Returns: Default(TFreshnessResult)</para>
/// <seealso cref="DRagLint.Convert.Apply.CheckFreshness.CheckOnce"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function CheckFreshness(const AStores: TArray<ISymbolStore>; const ARules: TConversionRuleSet): TFreshnessResult;

/// <summary>Verifies the TARGET unit's own .pas and sibling .dfm are current
/// in the index convert-apply is about to plan from (B-18, 1.31.7).</summary>
/// <param name="AStores">The symbol indexes, in --db order; for each file the
/// first store that holds a files row for it decides.</param>
/// <param name="AUnitPas">The unit being converted (full path).</param>
/// <param name="ADfmPath">Its sibling .dfm (full path); skipped when it does
/// not exist on disk.</param>
/// <returns>Fresh=True when every such file that a store holds matches that
/// store's recorded (mtime, sha). Fresh=False with one Reasons entry per
/// stale file: 'index is stale for &lt;path&gt; (changed on disk since it was
/// indexed) -- reindex'.</returns>
/// <remarks>
/// CheckFreshness only covers the files declaring the #convert From/To
/// types, so a unit whose .dfm or .pas changed after indexing read as fresh
/// and --apply planned spans and access sites from the stale index. Same
/// (mtime, sha) basis as CheckFreshness. A file no store holds is not
/// reported here (other guards own "not indexed"). Pure read-only; the
/// caller decides the outcome (convert-apply: dry run warns, --apply
/// refuses the unit).
/// </remarks>
function CheckUnitFreshness(const AStores: TArray<ISymbolStore>; const AUnitPas, ADfmPath: string): TFreshnessResult;

/// <summary>The INHERITED and INLINE objects of a .dfm whose class is the From
/// type of a #convert block, each with its declaring ancestor resolved -- the
/// instances convert-apply skips and reports (C8 engine items N1, N3).</summary>
/// <param name="ATrees">The run's tree cache; its Stores are searched for the
/// owner class and its ancestor chain (GetTransitiveAncestors). Not owned.</param>
/// <param name="AUnitPas">The unit being converted; a root class declared in
/// it is preferred over a same-named class elsewhere.</param>
/// <param name="ADfmPath">The unit's sibling .dfm; a missing file yields an
/// empty result.</param>
/// <param name="ARules">The parsed rule book.</param>
/// <param name="AOnly">The --only instance allow-list; empty keeps every one.</param>
/// <returns>One TInheritedInstance per such object, nested ones included, in
/// .dfm order; empty when there is none.</returns>
/// <remarks>
/// FindConvertInstances matches `object` headers only, so these are never
/// converted; until 1.22.0 convert-apply refused their unit whole (ruling R6).
/// The declaring ancestor is the nearest class of the owner's chain (the owner
/// itself first, so a frame's own .dfm counts) whose .dfm -- the class's unit
/// with the extension changed -- opens the component with `object` or
/// `inline`; a .dfm that only re-opens it with `inherited` is passed over.
/// The walk STOPS at an ancestor whose .dfm is missing, binary (TPF0) or not
/// readable as text -- it might declare the component -- and reports
/// 'outside' with a reason naming that file and why. An owner class that
/// resolves to no class or to several (looked up case-insensitively), a chain
/// that leaves the index at an unresolved ancestor, or a chain with no
/// declaring .dfm also give 'outside' -- nothing is guessed. A declaring
/// object of neither the From nor the To type gives 'mismatched'. Action is
/// 'retyped' for state 'converted' (C8 N2, 1.26.0; BuildApplyPlan demotes it to
/// 'skipped' when the retype cannot be planned) and 'skipped' for every other
/// state. AOnly filters the result like FindConvertInstances. Reads the
/// ancestors' .dfm files; writes nothing.
/// </remarks>
function FindInheritedInstances(const ATrees: TConvertTreeCache; const AUnitPas, ADfmPath: string;
  const ARules: TConversionRuleSet; const AOnly: TArray<string>): TArray<TInheritedInstance>;

/// <summary>The id AStore gives the file APath -- found the way the unit's
/// symbols are found, so a source tree moved or copied after indexing still
/// resolves (1.26.5).</summary>
/// <param name="AStore">The store to ask.</param>
/// <param name="APath">The unit (or .dfm) as convert-apply was handed it.</param>
/// <returns>The file id, or a value &lt;= 0 when the store holds no such file.</returns>
/// <remarks>Exact path first, then the expanded path, then the file of the
/// symbols FindSymbolsByFile returns -- which resolves tolerantly (a unique
/// basename is accepted). Before 1.26.5 the reference lookups asked by exact
/// path only while the symbols were found tolerantly: on a moved tree the .dfm
/// converted but every access site was skipped without a word, and the
/// stale-resolver refusal matched no --db and never fired.</remarks>
function UnitFileIdIn(const AStore: ISymbolStore; const APath: string): Int64;

/// <summary>The fields a CONVERTED ancestor declares that AUnitPas's code uses
/// without its .dfm re-opening them (C8 N2a, 1.26.0) -- apply/1 inherited[]
/// entries with action 'code', whose access sites BuildApplyPlan rewrites.</summary>
/// <param name="ATrees">The run's tree cache; the store that indexes AUnitPas
/// is searched. Not owned.</param>
/// <param name="AUnitPas">The descendant unit.</param>
/// <param name="ARules">The parsed rule book; a field counts when its type is
/// the To type of a #convert block (TypeName is that block's From type -- the
/// first such block when several share the To type).</param>
/// <param name="AOnly">The --only allow-list; empty keeps every one.</param>
/// <param name="AInherited">The unit's .dfm entries (FindInheritedInstances);
/// a field named there is not listed again.</param>
/// <returns>One entry per field, in order of its first reference: Line is that
/// reference's line in AUnitPas, AncestorState 'converted', Action 'code'.
/// 1.26.7: a field the declaring ancestor still declares with a block's FROM
/// type is listed too -- AncestorState 'unconverted', Action 'skipped', Reason
/// 'ancestor not converted', nothing rewritten. Empty when there is none.</returns>
/// <remarks>
/// A reference counts only when the resolver BOUND it to the field
/// (refs.symbol_id, E5): a local or parameter of the same name binds to
/// itself and does not count, and an unbound reference is never guessed at.
/// The field must belong to a class among the transitive ancestors of a class
/// AUnitPas declares -- any number of levels up -- and the declaring unit's
/// .dfm must open the component with `object` (or `inline`) and the To type,
/// which is what 'converted' means here. Reads that .dfm; writes nothing.
/// </remarks>
function FindInheritedCodeUses(const ATrees: TConvertTreeCache; const AUnitPas: string;
  const ARules: TConversionRuleSet; const AOnly: TArray<string>;
  const AInherited: TArray<TInheritedInstance>): TArray<TInheritedInstance>;

/// <summary>Reports SKIPPED inherited instances in a convert-apply report:
/// one `line N: warning: ...` per instance whose Action is 'skipped' in
/// Warnings and its typed mirror (kind inherited-instance-skipped) in Items.
/// A 'retyped' or 'code' entry is not a warning and is not reported here.</summary>
/// <param name="AInstances">The instances FindInheritedInstances returned.</param>
/// <param name="ADfmPath">The .dfm their lines refer to (each item's FilePath).</param>
/// <param name="AReport">The report to append to; Items stays equal to the sum
/// of the six arrays (invariant 1).</param>
/// <remarks>Pure apart from AReport.</remarks>
procedure AppendInheritedReport(const AInstances: TArray<TInheritedInstance>; const ADfmPath: string;
  var AReport: TApplyReport);

/// <summary>The descendant units that still stream or use components this run
/// converts in AUnitPas (apply/1 descendants[], 1.25.0) -- each will fail at
/// load or compile until it is converted next (C8 N2).</summary>
/// <param name="ATrees">The run's tree cache; every one of its Stores is
/// searched. Not owned.</param>
/// <param name="AUnitPas">The unit being converted (the ancestor).</param>
/// <param name="ADfmPath">Its .dfm; its root block names the root class and
/// gives each component's object line. A missing file yields an empty
/// result.</param>
/// <param name="ARules">The parsed rule book; a descendant block counts only
/// when its class is still the instance's From type.</param>
/// <param name="AConverted">The instances the run converts -- already
/// filtered by --only and stripped of skipped instances by the caller.</param>
/// <returns>One TDescendantUse per (descendant unit, converted component), in
/// AConverted order, then by unit name; empty when there is none.</returns>
/// <remarks>
/// Descendants are the classes FindDescendantNames lists for the root class,
/// kept only when their transitive ancestors include that class in AUnitPas
/// (a same-named class elsewhere does not count), at every level. A unit
/// counts by its .dfm when it holds an `inherited` / `inline` block named for
/// the component, with the From type, whose owner (the root class, or the
/// nearest enclosing `inline` frame's class -- so a form HOSTING the frame
/// counts too) is the root class or a descendant, matched by class SYMBOL: the
/// class of that name the candidate unit sees (declared in it, in a unit it
/// uses, or the only one indexed), never by name alone. The candidate .dfm
/// files are those the index holds a component symbol of that name in. A unit
/// counts by its code when a method of a descendant class references the
/// field by name -- resolved to the ancestor's field, or unresolved with no
/// receiver or Self and no local / parameter of that name in the routine (or
/// an enclosing one); a descendant's own same-named field binds to itself and
/// does not count. Each descendant file's references are read once per call.
/// Only what the --db stores index is seen: a descendant in another project is
/// not listed. Reads .dfm files; writes nothing.
/// </remarks>
function FindDescendantUses(const ATrees: TConvertTreeCache; const AUnitPas, ADfmPath: string;
  const ARules: TConversionRuleSet; const AConverted: TArray<TConvertInstance>): TArray<TDescendantUse>;

/// <summary>The instances a built plan CONVERTS: the .dfm's own From-type
/// objects --only kept, less every instance the plan skipped whole.</summary>
/// <param name="AReport">The plan's report; its instance-skipped items name
/// the instances left out.</param>
/// <param name="ADfmPath">The unit's .dfm; a missing file yields none.</param>
/// <param name="ARules">The parsed rule book.</param>
/// <param name="AOnly">The --only allow-list; empty keeps every one.</param>
/// <returns>The converted instances, in .dfm order.</returns>
/// <remarks>Reads ADfmPath; writes nothing.</remarks>
function ConvertedInstancesOf(const AReport: TApplyReport; const ADfmPath: string;
  const ARules: TConversionRuleSet; const AOnly: TArray<string>): TArray<TConvertInstance>;

/// <summary>Reports descendant uses in a convert-apply report: one
/// `line N: warning: descendant ...` per use in Warnings and its typed mirror
/// (kind descendant-not-converted) in Items.</summary>
/// <param name="AUses">The uses FindDescendantUses returned.</param>
/// <param name="ADfmPath">The converted unit's .dfm, which N refers to (each
/// item's FilePath).</param>
/// <param name="AReport">The report to append to; Items stays equal to the sum
/// of the six arrays (invariant 1).</param>
/// <remarks>Pure apart from AReport.</remarks>
procedure AppendDescendantReport(const AUses: TArray<TDescendantUse>; const ADfmPath: string;
  var AReport: TApplyReport);

/// <summary>Builds the full convert-apply plan for one unit: locates the
/// component instances to convert in ADfmPath (via FindConvertInstances),
/// rewrites all five surfaces per ARules, and returns the combined edit set
/// plus report.</summary>
/// <param name="ATrees">The run's shared tree cache; its Stores are the symbol
/// indexes to resolve against, in the order given (one per --db). TYPE
/// resolution (From/To classes, ctor-name lookups) tries every store in
/// order, first-that-resolves-wins -- the From/To types may live in a
/// DIFFERENT --db than the unit/instance being converted (Bug 2). Unit-scoped
/// lookups (the .pas/.dfm's own symbols and refs) use whichever store actually
/// has AUnitPas/ADfmPath indexed. Class members rule validation already
/// resolved are reused, not resolved again (1.20.6).</param>
/// <param name="AUnitPas">Path to the .pas file that declares/uses the
/// instances being converted.</param>
/// <param name="ADfmPath">Path to the .dfm file containing the instances'
/// component blocks.</param>
/// <param name="ABook">The validated conversion rule set (ABook.Rules, see
/// DRagLint.Convert.Rules) describing which From types convert to which To
/// types and how each property/event maps, with validation's UNREACHABLE rule
/// paths (ABook.Unreachable, owner ruling R12, T2h): each instance's re-emit
/// runs its own block's rules through WithoutUnreachableRules (inside
/// ReemitComponent), and the .pas access-site pass skips every unreachable
/// #link.</param>
/// <param name="AOnly">Optional allow-list of instance names to restrict the
/// plan to; empty means convert every instance that matches a rule.</param>
/// <param name="ACastLib"><!-- drag-lint:auto type -->const TCastLib</param>
/// <param name="AWarnUnlinked">True (the CLI default) emits one
/// aikUnlinkedSourceProperty warning per Report.Unlinked entry -- a source
/// property some converted instance carried that no #link carries and no
/// #ignore acknowledges -- printed as '&lt;N&gt; of &lt;M&gt; instance(s)'. False
/// (`--no-warn-unlinked`) still fills Report.Unlinked but emits no warning.
/// Default-on because the number earned it: measured 2 distinct gaps over 22
/// sites on a real 36-link book, and the converter team's own test was "2 is
/// a warning, 200 is a report".</param>
/// <param name="AInherited">The unit's inherited[] entries
/// (FindInheritedInstances, then FindInheritedCodeUses), already --only
/// filtered (C8 N2 / N2a, 1.26.0). A 'retyped' entry is converted like an own
/// instance -- its .dfm block re-emitted with its `inherited` / `inline`
/// header kept (see ReemitComponent for what an inherited block does not
/// get), its code access sites rewritten, its To type's unit added -- except
/// that there is no field declaration and no creator site to retype in this
/// unit. It is reported as one converted[] line (kind
/// inherited-instance-retyped); when its block cannot be located or re-emitted
/// its Action becomes 'skipped' with that reason, for AppendInheritedReport. A
/// 'code' entry only joins the access-site rewrite and the uses add. Every
/// other entry is ignored here.</param>
/// <returns>A TApplyResult. Task 2 implements surface #1 (.pas declaration
/// retype) and surface #2 (.pas uses-add): each located instance contributes a
/// tekReplaceInLine edit swapping its FromType token for ToType, plus (once
/// per distinct ToType) the uses-add edit(s) from TFindUnitRefactoring.Build.
/// Task 3 implements surface #3 (.dfm object-block re-emit): each located
/// instance's .dfm object block is replaced (tekDeleteLines + tekInsertLines,
/// same original indentation) with the T block from ReemitComponent, driven by
/// the F/T classes' members (ATrees.ClassFor; each dotted path resolved lazily). A
/// ReemitComponent Ok=False (hard re-emit failure) SKIPS THE WHOLE INSTANCE --
/// its .pas retype/uses edits (surfaces #1/#2) are also withheld, and
/// Report.Warnings gets an entry -- rather than leave a component converted in
/// its .pas declaration but not in its .dfm block (or vice versa). Task 5
/// implements surface #5 (runtime-creator retype + TODO marker). Task 6
/// implements surface #4 (property/event access-site rewrite): for each
/// renaming '#link ToMember &lt;- FromMember' rule, every 'member-access' ref
/// (ref-gap G) in the unit whose receiver names a converted instance (one
/// that survived the surface #3 re-emit checkpoint) contributes a
/// tekReplaceInLine edit swapping FromMember for ToMember at that access
/// site; Report.AccessSites lists each rewrite. An access on a receiver that
/// is NOT a converted instance is left untouched -- see FindMemberAccessSites.
/// Ok=False only on a hard failure (missing .pas/.dfm, zero instances
/// matched and no 'retyped' / 'code' AInherited entry, or -- 1.20.6 -- the book's unit rules refusing the unit, e.g. an
/// entry to remove inside a conditional region: then NOTHING is planned, the
/// #convert edits included). Refused=True, nothing planned, also when an
/// instance's indexed .dfm span no longer holds it -- lines added or removed,
/// a block shrunk onto a sibling's `end`, or the .dfm cut short ('&lt;Name&gt;:
/// index is stale for this .dfm -- reindex') -- and (R26) when a unit-rule
/// removal targets the unit declaring the From type of a #convert instance
/// that stays unconverted, skipped or left out by AOnly ('&lt;rule&gt; would
/// leave &lt;N&gt; unconverted instance(s) of &lt;Type&gt; -- unit not
/// changed') -- unless every such instance is an own instance AOnly left out:
/// then that removal is SKIPPED, not refused (C13 N4; a Report.UsesChanges row
/// with Action 'skipped' and a unit-rule-skipped warning). When the book has unit rules (#unuse / #use /
/// #useswap), surface #2's resolved units are handed to PlanUnitRules, which
/// then plans every uses change to the unit (Report.UsesChanges). Ok=True
/// with per-instance problems noted in Report.Warnings
/// otherwise (including every instance skipped by a re-emit failure).</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.DoConvertApply.RunUnit (DRagLint.CLI.pas)</para>
/// <para>Calls: BookChosenUnits, BookHasUnitRules, BoundAccessSites, BuildToTypeAdd, CharColumn, Choose, CompareText, Copy, DanglingPasUses, Default (+67 more)</para>
/// <para>Returns: if Length(Picked) = 1 then Spelling; Default(TApplyResult); TApplyResult.Refusal(UsesPlan.Error)</para>
/// <para>Complexity: 28 (cyclomatic, outer body), 1465 lines (full implementation)</para>
/// <para>Touches: file system</para>
/// <seealso cref="DRagLint.Convert.Apply.BareTypeTail"/>
/// <seealso cref="DRagLint.Convert.Apply.BuildApplyPlan.AddCodeEntries"/>
/// <seealso cref="DRagLint.Convert.Apply.BuildApplyPlan.Emit"/>
/// <seealso cref="DRagLint.Convert.Apply.BuildApplyPlan.FoldReemitReport"/>
/// <seealso cref="DRagLint.Convert.Apply.BuildApplyPlan.InstItem"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function BuildApplyPlan(const ATrees: TConvertTreeCache; const AUnitPas, ADfmPath: string;
  const ABook: TApplyBook; const AOnly: TArray<string>;
  const ACastLib: TCastLib; AWarnUnlinked: Boolean;
  var AInherited: TArray<TInheritedInstance>): TApplyResult;

/// <summary>The convert-apply plan for a unit whose COMPONENT part is skipped
/// -- no sibling .dfm, no #convert block in the book, or no .dfm instance any
/// block matches -- so only the book's unit rules (#unuse / #use / #useswap)
/// act on it.</summary>
/// <param name="ATrees">Resolves a .dfm instance's From type to the unit that
/// declares it (R26 below). Not owned.</param>
/// <param name="AUnitPas">The unit to change; read from disk as it is now.</param>
/// <param name="ADfmPath">The unit's sibling .dfm, or '' (or a missing file)
/// when it has none.</param>
/// <param name="ARules">The parsed, validated rule book; its #convert blocks
/// only count toward the ADD-wins normalisation (see PlanUnitRules).</param>
/// <param name="AOnly">The --only names (may be empty). When every instance a
/// removal would strand was left out by it, the removal is SKIPPED (C13 N4):
/// the unit stays in uses, Report.UsesChanges gets an Action 'skipped' row and
/// Report.Warnings / Items a unit-rule-skipped line.</param>
/// <param name="AReconcile">True reconciles the uses against the .dfm as it stands
/// (see remarks, C9); False (default) is the 1.26.6 behaviour with the R26
/// refusal.</param>
/// <returns>Ok=True with the uses-clause edits in Edits and one row per
/// change in Report.UsesChanges (both empty when the book changes nothing
/// here); every other report array empty. Ok=False with Error when the unit
/// does not exist or PlanUnitRules refuses it (e.g. an entry to remove sits in
/// a conditional region) -- then nothing is planned. Refused=True, Ok=False
/// (R26) when a removal (#unuse, or #useswap's Old) targets the unit that
/// declares the From type of a #convert instance in ADfmPath -- every such
/// instance stays unconverted on this path -- with Error
/// '&lt;rule&gt; would leave &lt;N&gt; unconverted instance(s) of &lt;Type&gt; --
/// unit not changed'.</returns>
/// <remarks>Reads the unit and the .dfm; writes nothing. The uses clauses are
/// lexed from the unit's own bytes; the index is consulted only for R26's
/// declaring unit. Pinned by run_convert_apply_unit_rules.ps1 (arm R).
/// AReconcile (C9, 1.27.0): the uses are RECONCILED instead -- the .dfm as it
/// stands is re-indexed, a watched unit one of its components needs is KEPT
/// (a 'kept' row and a warning, never the R26 refusal), one only .pas code
/// needs is removed with its dangling references reported, an unknown one is
/// kept (unit-rule-unverified); the --only 'skipped' row is unchanged.
/// False is the 1.26.6 behaviour above, exactly. Pinned by
/// run_convert_apply_uses_reconcile.ps1.</remarks>
function BuildUnitRulesOnlyPlan(const ATrees: TConvertTreeCache; const AUnitPas, ADfmPath: string;
  const ARules: TConversionRuleSet; const AOnly: TArray<string>; AReconcile: Boolean = False): TApplyResult;

/// <summary>Scans a .dfm's component headers (top-level and nested) and
/// returns the instances that should be converted: those whose class matches
/// a '#convert FromType' rule in ARules, filtered by AOnly when given.</summary>
/// <param name="ADfmText">The full text of the .dfm (or a single form's
/// component tree) to scan.</param>
/// <param name="ARules">The validated conversion rule set; only rules'
/// FromType classes are matched against each object header's class.</param>
/// <param name="AOnly">Optional allow-list of instance names; when non-empty,
/// only instances whose name appears here are returned.</param>
/// <returns>One TConvertInstance per matching component, in the order found.</returns>
/// <remarks>
/// Scans for lines shaped like 'object &lt;Name&gt;: &lt;Class&gt;' (any
/// indentation depth, so both top-level and nested components are found -- a
/// nested instance is as convertible as a top-level one). A line is recognised
/// as an object header when, after trimming leading whitespace, it starts with
/// the keyword 'object ' followed by an identifier, a ':', and a second
/// identifier (the class); anything else on the line (extra whitespace, a
/// trailing comment) is tolerated. Lines that don't match this shape (property
/// lines, 'end', inherited/inline headers) are skipped -- this is a location
/// scan only, not a full DFM parse (Task 3's ParseDfmBlock/ReemitComponent do
/// the real per-instance re-emit). Pure; deterministic; no I/O.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.ConvertApplyComponentPart (DRagLint.CLI.pas), DRagLint.Convert.Apply.BuildApplyPlan (DRagLint.Convert.Apply.pas), DRagLint.Convert.Apply.ConvertedInstancesOf (DRagLint.Convert.Apply.pas), DRagLint.Convert.Apply.DemoteOnlySkips (DRagLint.Convert.Apply.pas), DRagLint.Convert.Apply.RemovalLeavesUnconverted (DRagLint.Convert.Apply.pas) (+1 more)</para>
/// <para>Calls: Default, DRagLint.Convert.Apply.FindConvertRuleFor, DRagLint.Convert.Apply.InOnlyList, DRagLint.Convert.Apply.TryParseObjectHeader, Trim</para>
/// <para>Returns: nil; List.ToArray</para>
/// <seealso cref="DRagLint.Convert.Apply.FindConvertRuleFor"/>
/// <seealso cref="DRagLint.Convert.Apply.InOnlyList"/>
/// <seealso cref="DRagLint.Convert.Apply.TryParseObjectHeader"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function FindConvertInstances(const ADfmText: string; const ARules: TConversionRuleSet;
  const AOnly: TArray<string>): TArray<TConvertInstance>;

/// <summary>The .dfm objects of a From type that --only left out but that sit
/// inside an object --only kept (1.25.1) -- each converts with its parent.</summary>
/// <param name="ADfmText">The unit's .dfm text.</param>
/// <param name="ARules">The parsed rule book.</param>
/// <param name="AOnly">The --only names; empty gives an empty result (every
/// instance converts anyway).</param>
/// <returns>One TNestedOnly per such object, in .dfm order, any depth below the
/// kept parent -- a child included this way includes its own children too.</returns>
/// <remarks>Only `object` blocks count, as in FindConvertInstances. Blocks are
/// tracked on a stack: object / inherited / inline headers and collection
/// `item`s open one, `end` / `end>` closes one. Pure.</remarks>
function NestedOnlyInstances(const ADfmText: string; const ARules: TConversionRuleSet;
  const AOnly: TArray<string>): TArray<TNestedOnly>;

/// <summary>Splits convert-apply's --only names into the ones that name a .dfm
/// object of a #convert From type and the ones that name none (C13 N3, apply/1
/// only_matched[] / only_unmatched[]).</summary>
/// <param name="ADfmText">The unit's .dfm text; '' when it has none (then every
/// name is unmatched).</param>
/// <param name="ARules">The parsed rule book; only its #convert From types
/// count.</param>
/// <param name="AOnly">The --only names, as given.</param>
/// <param name="AMatched">The AOnly names that match an object -- own,
/// inherited or inline -- case-insensitively, in AOnly order, spelled as given
/// in AOnly.</param>
/// <param name="AUnmatched">The rest, same order and spelling. A name that
/// matches nothing is ignored by convert-apply (no error, exit unchanged);
/// this is where it is reported.</param>
/// <remarks>Pure; no I/O. Both arrays are empty when AOnly is.</remarks>
procedure SplitOnlyNames(const ADfmText: string; const ARules: TConversionRuleSet;
  const AOnly: TArray<string>; out AMatched, AUnmatched: TArray<string>);

/// <summary>The stable wire name of an item kind, e.g. 'creator-verify'.</summary>
/// <param name="AKind">The kind to spell.</param>
/// <returns>A lowercase, hyphenated ASCII token; never empty.</returns>
/// <remarks>
/// THE SINGLE SOURCE of these names. Every emitter (the apply/1 JSON,
/// the remainder contract doc, any consumer dispatch table) must go through
/// here rather than spelling a literal, so a rename cannot drift apart. Pure.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.EmitApplyJson.ItemJson (DRagLint.CLI.pas)</para>
/// <para>Returns: NAMES[AKind]</para>
/// <para>Pure</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ApplyItemKindName(AKind: TApplyItemKind): string;

/// <summary>The stable wire name of a report field, e.g. 'reemit_notes'.</summary>
/// <param name="AField">The field to spell.</param>
/// <returns>A lowercase, snake_case ASCII token matching the apply/1 JSON key
/// of the corresponding array; never empty.</returns>
/// <remarks>
/// Pure.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.EmitApplyJson.ItemJson (DRagLint.CLI.pas)</para>
/// <para>Returns: NAMES[AField]</para>
/// <para>Pure</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ApplyFieldName(AField: TApplyField): string;

/// <summary>Why convert-apply does NOT realise the member #migrate rule ARule
/// (C18 slice 1), or '' when it does.</summary>
/// <param name="ARule">A rkMigrate rule inside a #convert block.</param>
/// <returns>'' for a plain member renamed to a plain identifier or to DL_NONE;
/// else the reason sentence convert-apply prints in its migrate-check item
/// (scoped form, call / assignment form, no replacement, a replacement
/// template, uses units after the rule).</returns>
/// <remarks>Pure. Shared by convert-apply and convert-validate (G3), so the
/// two never disagree about which forms are applied.</remarks>
function MigrateRuleRefusal(const ARule: TConversionRule): string;

implementation

uses
  System.StrUtils,
  System.Generics.Defaults,
  System.IOUtils,
  System.Classes,
  System.Hash,
  System.DateUtils,
  System.RegularExpressions;

var
  { 1.26.5: '#check-ref not checked' is said ONCE PER RUN (a batch of units is
    one process), not per instance or per unit. }
  GRefNotCheckedSaid: Boolean = False;

function ApplyItemKindName(AKind: TApplyItemKind): string;
const
  { Positional against TApplyItemKind -- keep the two in step. A new kind is
    appended to BOTH; renaming an existing entry breaks apply/1 (see the type's
    remarks) and requires a schema bump. }
  NAMES: array[TApplyItemKind] of string = (
    'field-retyped', 'access-site-rewritten', 'creator-retyped',
    'dfm-path-created', 'creator-verify', 'creator-unverified',
    'unmapped-property', 'binary-type-mismatch', 'owned-part-unconverted',
    'link-stub-unfilled', 'collection-relocated', 'defaults-may-diverge',
    'cast-not-applied', 'instance-skipped', 'field-decl-not-retyped',
    'uses-unit-unresolved', 'mapping-source-absent', 'mapping-not-applied',
    'default-rule-superseded', 'default-resolved', 'enum-cast-unmapped',
    'unlinked-source-property', 'sub-leaf-carried', 'rule-path-unreachable',
    'inherited-instance-skipped', 'unit-rule-skipped', 'descendant-not-converted',
    'inherited-instance-retyped', 'access-site-unverified',
    'book-warning', 'ref-path-like', 'ref-dangling', 'ref-not-checked',
    'unit-rule-kept', 'uses-unit-ambiguous', 'unit-rule-unverified', 'unit-rule-dangling',
    'value-cast-applied', 'value-cast-check', 'convert-class-inferred',
    'migrate-applied', 'migrate-check', 'deliberate-break', 'encoding-not-checked');
begin
  Result:= NAMES[AKind];
end;

function ApplyFieldName(AField: TApplyField): string;
const
  { Positional against TApplyField; each name is also the apply/1 JSON key of
    the matching TApplyReport array. }
  NAMES: array[TApplyField] of string = (
    'converted', 'access_sites', 'creator_sites', 'todos', 'reemit_notes',
    'warnings');
begin
  Result:= NAMES[AField];
end;

// True when AName appears (case-insensitively) in AOnly. Empty AOnly means
// "no filter" -- everything passes.
function InOnlyList(const AName: string; const AOnly: TArray<string>): Boolean;
var
  N: string;
begin
  if Length(AOnly) = 0 then Exit(True);
  for N in AOnly do
    if SameText(N, AName) then Exit(True);
  Result:= False;
end;

// Strips a leading 'Unit.' qualifier from a type name, returning only the
// bare tail (e.g. 'LibA.TSrcBtn' -> 'TSrcBtn'; 'TSrcBtn' unchanged). A #convert
// rule's FromType/ToType header may name a type either bare ('TSrcBtn') or
// fully qualified ('LibA.TSrcBtn') -- convert-scaffold and the rule editor
// emit both forms -- but a .dfm object header is ALWAYS bare ('object btn1:
// TSrcBtn', never 'object btn1: LibA.TSrcBtn') and FindSymbolsByExactName /
// the .pas field-decl type token match against the bare name column too. Bug 1 fix: without this, a qualified
// FromType header matched zero .dfm instances ("no convertible instances
// found").
function BareTypeTail(const AQName: string): string;
var
  DotAt: Integer;
begin
  DotAt:= LastDelimiter('.', AQName);
  if DotAt > 0 then Result:= Copy(AQName, DotAt + 1, MaxInt)
  else Result:= AQName;
end;

// Looks up the #convert rule whose FromType matches AClassName (SameText,
// compared by BARE TAIL -- see BareTypeTail -- so a qualified rule header
// still matches the .dfm's always-bare object-header class). Returns True +
// the rule's ToType (also reduced to its bare tail, so every downstream
// lookup that expects a bare class name -- ResolveClassQName, the field-decl
// retype text, GetConstructorNames/ToTypeHasGenericCreate -- keeps working
// whether the rule's header was bare or qualified) when found.
function FindConvertRuleFor(const ARules: TConversionRuleSet; const AClassName: string;
  out AToType: string): Boolean;
var
  R: TConversionRule;
begin
  AToType:= '';
  for R in ARules.Rules do
    if (R.Kind = rkConvert) and SameText(BareTypeTail(R.FromType), AClassName) then
    begin AToType:= BareTypeTail(R.ToType); Exit(True); end;
  Result:= False;
end;

// Parses one trimmed DFM line as an 'object Name: Class' header. Returns True
// + Name/ClassName_ on a match; False for any other line shape (property
// lines, 'end', 'object Name' with no class -- a nested Font/inherited-shape
// sub-object, which has no type to convert and is correctly skipped).
// AKeyword is the header keyword WITH its trailing space: 'object ',
// 'inherited ' or 'inline '.
function TryParseHeaderAfter(const ATrimmedLine, AKeyword: string; out AName, AClassName: string): Boolean;
var
  Rest   : string;
  ColonAt: Integer;
  NamePart, ClassPart: string;
begin
  AName:= ''; AClassName:= '';
  if not StartsText(AKeyword, ATrimmedLine) then Exit(False);
  Rest:= Trim(Copy(ATrimmedLine, Length(AKeyword) + 1, MaxInt));
  ColonAt:= Pos(':', Rest);
  if ColonAt = 0 then Exit(False); { 'object Name' with no class -- e.g. a Font sub-object }
  NamePart := Trim(Copy(Rest, 1, ColonAt - 1));
  ClassPart:= Trim(Copy(Rest, ColonAt + 1, MaxInt));
  { the class token may be followed by nothing else on a well-formed DFM line;
    take the leading identifier run so a stray trailing comment doesn't break it }
  var i: Integer:= 1;
  while (i <= Length(ClassPart)) and (CharInSet(ClassPart[i], ['A'..'Z', 'a'..'z', '0'..'9', '_'])) do Inc(i);
  ClassPart:= Copy(ClassPart, 1, i - 1);
  if (NamePart = '') or (ClassPart = '') then Exit(False);
  AName:= NamePart; AClassName:= ClassPart;
  Result:= True;
end;

function TryParseObjectHeader(const ATrimmedLine: string; out AName, AClassName: string): Boolean;
begin
  Result:= TryParseHeaderAfter(ATrimmedLine, 'object ', AName, AClassName);
end;

function FindConvertInstances(const ADfmText: string; const ARules: TConversionRuleSet;
  const AOnly: TArray<string>): TArray<TConvertInstance>;
var
  Lines : TArray<string>;
  L     : string;
  Trimmed: string;
  Name_, ClassName_, ToType: string;
  List  : TList<TConvertInstance>;
  Inst  : TConvertInstance;
begin
  Result:= nil;
  if Trim(ADfmText) = '' then Exit;

  Lines:= ADfmText.Replace(#13#10, #10).Replace(#13, #10).Split([#10]);

  List:= TList<TConvertInstance>.Create;
  try
    for L in Lines do
    begin
      Trimmed:= Trim(L);
      if not TryParseObjectHeader(Trimmed, Name_, ClassName_) then Continue;
      if not FindConvertRuleFor(ARules, ClassName_, ToType) then Continue;
      if not InOnlyList(Name_, AOnly) then Continue;

      Inst:= Default(TConvertInstance);
      Inst.InstanceName:= Name_;
      Inst.FromType    := ClassName_;
      Inst.ToType      := ToType;
      List.Add(Inst);
    end;
    Result:= List.ToArray;
  finally
    List.Free;
  end;
end;

// Locates the 1-based [Col, EndCol) span of the FromType token on the field
// declaration line 'AInstanceName: AFromType' within lines [AStartLine,
// AEndLine] (inclusive, 1-based, matching TSymbol.StartLine/EndLine for the
// skField symbol -- which spans the WHOLE 'Name: Type;' declaration, not just
// the type). Returns True + ALine/ACol/AEndCol on a match. A scoped text
// search rather than a full re-parse: the field symbol already told us WHICH
// line(s) to look at; this only finds the type token's exact columns for the
// tekReplaceInLine edit.
function LocateFieldTypeToken(const APasLines: TStringList; AStartLine, AEndLine: Integer;
  const AInstanceName, AFromType: string; out ALine, ACol, AEndCol: Integer): Boolean;
var
  LineNo: Integer;
  S     : string;
  NamePos, ColonPos, TypePos: Integer;
begin
  ALine:= 0; ACol:= 0; AEndCol:= 0;
  if AStartLine < 1 then AStartLine:= 1;
  if AEndLine > APasLines.Count then AEndLine:= APasLines.Count;
  for LineNo:= AStartLine to AEndLine do
  begin
    if (LineNo < 1) or (LineNo > APasLines.Count) then Continue;
    S:= APasLines[LineNo - 1]; { 0-based TStringList, 1-based LineNo }

    { find the field name as a whole word }
    NamePos:= 1;
    repeat
      NamePos:= PosEx(AInstanceName, S, NamePos);
      if NamePos = 0 then Break;
      var AfterOk: Boolean:= (NamePos + Length(AInstanceName) > Length(S)) or
        not CharInSet(S[NamePos + Length(AInstanceName)], ['A'..'Z', 'a'..'z', '0'..'9', '_']);
      var BeforeOk: Boolean:= (NamePos = 1) or
        not CharInSet(S[NamePos - 1], ['A'..'Z', 'a'..'z', '0'..'9', '_']);
      if AfterOk and BeforeOk then Break;
      Inc(NamePos);
    until False;
    if NamePos = 0 then Continue;

    { the ':' after the name, then the type token }
    ColonPos:= PosEx(':', S, NamePos + Length(AInstanceName));
    if ColonPos = 0 then Continue;
    TypePos:= ColonPos + 1;
    while (TypePos <= Length(S)) and (S[TypePos] = ' ') do Inc(TypePos);
    if (TypePos + Length(AFromType) - 1 > Length(S)) or
       (not SameText(Copy(S, TypePos, Length(AFromType)), AFromType)) then Continue;
    { require a non-identifier boundary after the type token (';', ' ', end-of-line) }
    var TypeEndPos: Integer:= TypePos + Length(AFromType);
    if (TypeEndPos <= Length(S)) and CharInSet(S[TypeEndPos], ['A'..'Z', 'a'..'z', '0'..'9', '_']) then Continue;

    ALine  := LineNo;
    ACol   := TypePos;
    AEndCol:= TypeEndPos;
    Exit(True);
  end;
  Result:= False;
end;

// Defined with pas_uses[] below; TConvertTreeCache.ScopedClass shares them.
function ResolveClassInScope(ATrees: TConvertTreeCache; const AScope: ISymbolStore; AScopeFileId: Int64;
  const AName: string; AIntfOnly: Boolean; const AHint: string): TScopedClass; forward;
procedure CollectClassDeclarers(ATrees: TConvertTreeCache; const AName, AScopePath: string;
  AQNames, AStems: TList<string>); forward;

type
  // C9 A8-1: one unit the converted unit uses after the book's unit rules.
  TBookUnit = record
    Spelling : string;
    Preferred: Boolean;  { a uses entry of the unit, spelled as the unit writes it }
  end;

// C9 A8-1 (shared since the link-scope fix): every unit that settles a To-type
// tie, in the order PickTieCandidate has always chosen them -- a #use, a
// #convert block's trailing units, a #useswap New whose Old the unit uses,
// then each uses entry of the unit (AUnitUses) the book does not remove
// (review F2: an entry going away settles nothing).
function BookChosenUnits(const ARules: TConversionRuleSet; const AUnitUses: TArray<TUnitUse>;
  const ASameUnit: TSameUnitFunc): TArray<TBookUnit>;

  function MakeBookUnit(const ASpelling: string; APreferred: Boolean): TBookUnit;
  begin
    Result.Spelling := ASpelling;
    Result.Preferred:= APreferred;
  end;

  function UsesUnit(const AUnit: string): Boolean;
  begin
    for var U: TUnitUse in AUnitUses do
      if ASameUnit(U.UnitName, AUnit) then Exit(True);
    Result:= False;
  end;

begin
  Result:= nil;
  var Watched: TArray<TWatchUnit>:= UnitRuleWatchList(ARules, nil, ASameUnit);
  for var R: TConversionRule in ARules.Rules do
    case R.Kind of
      rkUse: Result:= Result + [MakeBookUnit(R.UnitName, False)];
      rkConvert:
        for var U: string in R.UnitsAdd do Result:= Result + [MakeBookUnit(U, False)];
      rkUseSwap:
        { the swap's New is added only when the unit uses Old }
        if UsesUnit(R.UnitName) then
          for var U: string in R.UnitsAdd do Result:= Result + [MakeBookUnit(U, False)];
    end;
  for var U: TUnitUse in AUnitUses do
  begin
    var Removed: Boolean:= False;
    for var W: TWatchUnit in Watched do
      if ASameUnit(W.UnitName, U.UnitName) then Removed:= True;
    if not Removed then Result:= Result + [MakeBookUnit(U.UnitName, True)];
  end;
end;

// The qualified name of the class named exactly AQName ('Unit.TType') in
// AStore, or '' -- never a same-named class of another unit.
function QualifiedClassIn(const AStore: ISymbolStore; const AQName: string): string;
var
  S: TSymbol;
begin
  Result:= '';
  for S in AStore.FindSymbolsByExactName(BareTypeTail(AQName)) do
    if (S.Kind = skClass) and SameText(S.QualifiedName, AQName) then Exit(S.QualifiedName);
end;

constructor TConvertTreeCache.Create(const AStores: TArray<ISymbolStore>);
begin
  inherited Create;
  FStores  := AStores;
  FResolved:= TDictionary<string, TResolved>.Create;
  FScoped  := TDictionary<string, TScopedClass>.Create;
  SetLength(FCaches, Length(AStores));
  FOptions := Default(TPropTreeOptions);
  FOptions.ToPersistent:= True;
  { A REFERENCED COMPONENT IS NOT AN OWNED SUB-OBJECT, and expanding one walks
    the whole form's component graph. Left at the legacy default (False) this is
    the entire reason convert-apply did not finish on a large form.

    MEASURED 2026-09-08 on ORM3 CLIENT\VARINSP (942 KB .dfm, 1,454 object
    blocks), TOvcTable against the Win32 library index:

      default (expand refs)   103.2 s   32,224 properties
      TreatRefsAsLeaves       6.1 s        928 properties

    Owned TPersistent sub-objects (TFont, TStrings, the grid's own view
    objects) still expand -- those ARE part of the block being re-emitted. What
    stops is following a property that merely POINTS at another component,
    which the DFM records as a name reference and which the re-emit never needs
    to descend into. A path THROUGH a referenced component (Connection.Params.X)
    therefore does not resolve, in validation as in the plan. }
  FOptions.TreatRefsAsLeaves:= True;
end;

destructor TConvertTreeCache.Destroy;
var
  C: TPropMemberCache;
begin
  for C in FCaches do C.Free;
  for var F: TRefFacts in FRefFacts do F.Free;
  FUnitIndex.Free;
  FScoped.Free;
  FResolved.Free;
  inherited Destroy;
end;

function TConvertTreeCache.UnitIndex: TUsesUnitIndex;
begin
  if FUnitIndex = nil then FUnitIndex:= TUsesUnitIndex.Create(FStores, FDbPaths);
  Result:= FUnitIndex;
end;

constructor TRefFacts.Create;
begin
  inherited Create;
  FKeys:= TDictionary<string, Boolean>.Create;
end;

destructor TRefFacts.Destroy;
begin
  FKeys.Free;
  inherited Destroy;
end;

procedure TRefFacts.Add(const AClass, AProp, AValue: string);
begin
  Inc(FRows);
  FKeys.AddOrSetValue(UpperCase(BareTypeTail(AClass) + '|' + AProp + '|' + AValue), True);
end;

function TRefFacts.Has(const AClass, AProp, AValue: string): Boolean;
begin
  Result:= FKeys.ContainsKey(UpperCase(BareTypeTail(AClass) + '|' + AProp + '|' + AValue));
end;

function TConvertTreeCache.RefFactsFor(const AStore: ISymbolStore): TRefFacts;
const
  KIND_PROP = 'dfm-prop';
  EXT_DFM   = '.dfm';
var
  Ix     : Integer;
  ClassOf: TDictionary<Int64, string>;
  Path   : string;
  Cls    : string;
begin
  Result:= nil;
  Ix:= -1;
  for var I: Integer:= 0 to High(FStores) do
    if FStores[I] = AStore then Ix:= I;
  if Ix < 0 then Exit;
  if Length(FRefFacts) <> Length(FStores) then SetLength(FRefFacts, Length(FStores));
  if FRefFacts[Ix] <> nil then Exit(FRefFacts[Ix]);
  Result:= TRefFacts.Create;
  FRefFacts[Ix]:= Result;
  ClassOf:= TDictionary<Int64, string>.Create;
  try
    for var Fid: Int64 in AStore.GetAllFileIds do
    begin
      Path:= AStore.GetFilePath(Fid);
      if not SameText(ExtractFileExt(Path), EXT_DFM) then Continue;
      ClassOf.Clear;
      for var Sym: TSymbol in AStore.FindSymbolsByFile(Path) do
        ClassOf.AddOrSetValue(Sym.Id, Sym.Signature);
      for var PL: TStringLiteral in AStore.GetLiteralsByKind(Fid, KIND_PROP) do
      begin
        if not ClassOf.TryGetValue(PL.SymbolId, Cls) then Cls:= '';
        Result.Add(Cls, PL.OwnerName, PL.Text);
      end;
    end;
  finally
    ClassOf.Free;
  end;
end;

function TConvertTreeCache.Lookup(const ATypeName: string): TResolved;
var
  Name: string;
  Key : string;
  I   : Integer;
begin
  Name:= Trim(ATypeName);
  Key := UpperCase(Name);
  if FResolved.TryGetValue(Key, Result) then Exit;
  Result.QName:= '';
  Result.Store:= -1;
  if Pos('.', Name) > 0 then
  begin
    for I:= 0 to High(FStores) do
    begin
      Result.QName:= QualifiedClassIn(FStores[I], Name);
      if Result.QName <> '' then
      begin
        Result.Store:= I;
        Break;
      end;
    end;
  end
  else if Name <> '' then
  begin
    { a bare name: the unit's scope, never the first class of that name }
    var Scoped: TScopedClass:= ScopedClass(Name);
    if Scoped.Resolution = PAS_RES_RESOLVED then Result:= Lookup(Scoped.QName);
  end;
  FResolved.AddOrSetValue(Key, Result);
end;

procedure TConvertTreeCache.SetScope(const AUnitPas: string; const ARules: TConversionRuleSet);
begin
  if (FScopePath <> '') and SameText(FScopePath, AUnitPas) then Exit;
  FScopePath  := AUnitPas;
  FScopeStore := nil;
  FScopeFileId:= 0;
  FToOnly     := nil;
  FBookUnits  := nil;
  FFrameworkDone:= False;
  FFramework    := '';
  FFrameworkSrc := '';
  if AUnitPas <> '' then
    for var St: ISymbolStore in FStores do
    begin
      var Fid: Int64:= UnitFileIdIn(St, AUnitPas);
      if Fid > 0 then
      begin
        FScopeStore := St;
        FScopeFileId:= Fid;
        Break;
      end;
    end;
  var Froms: TArray<string>:= nil;
  for var R: TConversionRule in ARules.Rules do
    if R.Kind = rkConvert then Froms:= Froms + [BareTypeTail(R.FromType)];
  for var R: TConversionRule in ARules.Rules do
    if (R.Kind = rkConvert) and (R.ToType <> '') and (Pos('.', R.ToType) = 0) and
       not MatchText(R.ToType, Froms) and not MatchText(R.ToType, FToOnly) then
      FToOnly:= FToOnly + [R.ToType];
  if Length(FToOnly) > 0 then
    for var B: TBookUnit in BookChosenUnits(ARules,
      if FScopeFileId > 0 then FScopeStore.GetUnitUsesForFile(FScopeFileId) else nil, UnitIndex.SameUnit) do
      FBookUnits:= FBookUnits + [B.Spelling];
  FResolved.Clear;
  FScoped.Clear;
end;

function TConvertTreeCache.ScopedClass(const ATypeName, AHint: string): TScopedClass;
begin
  var Name: string:= Trim(ATypeName);
  var Key : string:= UpperCase(Name + '|' + Trim(AHint));
  if FScoped.TryGetValue(Key, Result) then Exit;
  Result:= Default(TScopedClass);
  { a To type of the unit AFTER conversion: the unit the book makes it use
    settles a tie first (C9 A8-1, the uses reconciliation's own rule) }
  if MatchText(Name, FToOnly) and (Length(FBookUnits) > 0) then
  begin
    var QNames: TList<string>:= TList<string>.Create;
    var Stems : TList<string>:= TList<string>.Create;
    try
      CollectClassDeclarers(Self, Name, if FScopeFileId > 0 then FScopeStore.GetFilePath(FScopeFileId) else '',
        QNames, Stems);
      var Pick: Integer:= -1;
      var Picks: Integer:= 0;
      if Stems.Count > 1 then
        for var I: Integer:= 0 to Stems.Count - 1 do
          for var B: string in FBookUnits do
            if UnitIndex.SameUnit(B, Stems[I]) and (Pick <> I) then
            begin
              Pick:= I;
              Inc(Picks);
            end;
      if Picks = 1 then
      begin
        Result.QName     := QNames[Pick];
        Result.Resolution:= PAS_RES_RESOLVED;
      end;
    finally
      Stems.Free;
      QNames.Free;
    end;
  end;
  if Result.Resolution = '' then
    Result:= ResolveClassInScope(Self, FScopeStore, FScopeFileId, Name, False, Trim(AHint));
  if Result.Resolution = PAS_RES_AMBIGUOUS then
  begin
    { why the scope did not settle each candidate }
    var UsesList: TArray<TUnitUse>:= if FScopeFileId > 0 then FScopeStore.GetUnitUsesForFile(FScopeFileId) else nil;
    SetLength(Result.Why, Length(Result.Candidates));
    for var I: Integer:= 0 to High(Result.Candidates) do
    begin
      Result.Why[I]:= if FScopeFileId > 0 then 'not in the unit''s uses' else 'no unit to scope it';
      for var U: TUnitUse in UsesList do
        if UnitIndex.SameUnit(U.UnitName, Result.Candidates[I]) then
          Result.Why[I]:= Format('tie: the uses entry %s names another candidate too', [U.UnitName]);
    end;
    InferAmbiguous(Name, Result);
  end;
  FScoped.AddOrSetValue(Key, Result);
end;

// owner ruling 2026-10-11 (a): the framework of the project the unit at
// AUnitPath belongs to -- 'VCL' / 'FMX' / '' -- from the .dproj beside a
// project file (.dpr / .dpk) AStore indexes, else the one .dproj in the unit's
// folder: <FrameworkType>, else a DCC_Namespace naming Vcl but not FMX (or the
// reverse). ASource is the .dproj read. Only files that exist are read.
function ProjectFramework(const AStore: ISymbolStore; const AUnitPath: string; out ASource: string): string;

  function FromDproj(const ADproj: string): string;
  begin
    Result:= '';
    var Text: string:= TFile.ReadAllText(ADproj);
    var M: TMatch:= TRegEx.Match(Text, '<FrameworkType>\s*(VCL|FMX)\s*</FrameworkType>', [roIgnoreCase]);
    if M.Success then Exit(UpperCase(M.Groups[1].Value));
    var HasVcl: Boolean:= False;
    var HasFmx: Boolean:= False;
    for var NM: TMatch in TRegEx.Matches(Text, '<DCC_Namespace>([^<]*)</DCC_Namespace>', [roIgnoreCase]) do
      for var Ns: string in NM.Groups[1].Value.Split([';']) do
      begin
        if SameText(Trim(Ns), 'Vcl') then HasVcl:= True;
        if SameText(Trim(Ns), 'FMX') then HasFmx:= True;
      end;
    if HasVcl and not HasFmx then Result:= 'VCL'
    else if HasFmx and not HasVcl then Result:= 'FMX';
  end;

begin
  Result := '';
  ASource:= '';
  var Dprojs: TArray<string>:= nil;
  if AStore <> nil then
    for var Fid: Int64 in AStore.GetAllFileIds do
    begin
      var P: string:= AStore.GetFilePath(Fid);
      var Ext: string:= ExtractFileExt(P);
      if (SameText(Ext, '.dpr') or SameText(Ext, '.dpk')) and TFile.Exists(ChangeFileExt(P, '.dproj')) then
        Dprojs:= Dprojs + [ChangeFileExt(P, '.dproj')];
    end;
  if (Length(Dprojs) = 0) and (AUnitPath <> '') and TDirectory.Exists(ExtractFilePath(AUnitPath)) then
  begin
    var Local: TArray<string>:= TDirectory.GetFiles(ExtractFilePath(AUnitPath), '*.dproj');
    if Length(Local) = 1 then Dprojs:= Local;
  end;
  for var D: string in Dprojs do
  begin
    var F: string:= FromDproj(D);
    if F = '' then Continue;
    if (Result <> '') and (F <> Result) then
    begin
      ASource:= '';
      Exit('');  { two projects disagree: no evidence }
    end;
    Result := F;
    ASource:= D;
  end;
end;

{ Lane H (2026-10-26): a unit's text for the uses planner, decoded as the writer decodes it
  (TTextFileFormat.ReadFile): a UTF-8 / UTF-16 BOM is stripped and its encoding honoured. The
  old ANSI read kept a UTF-8 BOM as three characters in front of 'unit', so a UTF-8 + BOM unit
  with any #use rule was refused as "not a unit". Lane L1 (2026-10-26): EVERY convert-apply
  read of a user .pas / .dfm goes through here or DecodeUnitBytes -- a column computed on an
  ANSI-decoded UTF-8 line drifted against the writer's text, and a .dfm block re-emitted from
  an ANSI decode wrote its non-ASCII captions back as mojibake. }
function ReadUnitText(const APath: string): string;
begin
  TTextFileFormat.ReadFile(APath, Result);
end;

{ Lane L1: ReadUnitText for bytes already read (a caller that first checks for a binary .dfm). }
function DecodeUnitBytes(const ABytes: TBytes): string;
begin
  TTextFileFormat.Decode(ABytes, Result);
end;
// owner ruling 2026-10-11 (b): the property paths the .dfm at ADfmPath streams
// directly on every object whose class is AClassName (bare, case-insensitive):
// the 'Name = value' lines one level inside each 'object|inherited|inline
// X: AClassName' header, distinct. [] when the file is absent or has none.
function DfmStreamedProps(const ADfmPath, AClassName: string): TArray<string>;
const
  DFM_INDENT_STEP = 2;  { a .dfm nests each level two spaces deeper }
begin
  Result:= nil;
  if not TFile.Exists(ADfmPath) then Exit;
  var Lines: TArray<string>:= ReadUnitText(ADfmPath)
    .Replace(#13#10, #10).Replace(#13, #10).Split([#10]);
  var Header: TRegEx:= TRegEx.Create('^(?<ind>\s*)(object|inherited|inline)\s+\w+\s*:\s*(?<cls>[\w.]+)', [roIgnoreCase]);
  var Prop  : TRegEx:= TRegEx.Create('^(?<ind>\s*)(?<name>[A-Za-z_][\w.]*)\s*=', []);
  for var I: Integer:= 0 to High(Lines) do
  begin
    var M: TMatch:= Header.Match(Lines[I]);
    if not (M.Success and SameText(BareTypeTail(M.Groups['cls'].Value), AClassName)) then Continue;
    var Indent: Integer:= Length(M.Groups['ind'].Value);
    for var J: Integer:= I + 1 to High(Lines) do
    begin
      var L: string:= Lines[J];
      if (Length(L) - Length(L.TrimLeft) <= Indent) and (L.Trim <> '') then Break;  { this object's 'end' }
      var PM: TMatch:= Prop.Match(L);
      if PM.Success and (Length(PM.Groups['ind'].Value) = Indent + DFM_INDENT_STEP) and
         not MatchText(PM.Groups['name'].Value, Result) then
        Result:= Result + [PM.Groups['name'].Value];
    end;
  end;
end;

function TConvertTreeCache.InferAmbiguous(const AName: string; var AScoped: TScopedClass): Boolean;
var
  Alive   : TArray<Boolean>;
  Evidence: TArray<string>;

  function AliveCount: Integer;
  begin
    Result:= 0;
    for var B: Boolean in Alive do if B then Inc(Result);
  end;

  function QNameOf(AIndex: Integer): string;
  begin
    Result:= AScoped.Candidates[AIndex] + '.' + AName;
  end;

  function FrameworkOf(const AUnit: string): string;
  begin
    Result:= if StartsText('Vcl.', AUnit) then 'VCL' else if StartsText('FMX.', AUnit) then 'FMX' else '';
  end;

  { (a) the project's framework drops a candidate of the other one }
  procedure DropByFramework;
  begin
    if not FFrameworkDone then
    begin
      FFrameworkDone:= True;
      FFramework    := ProjectFramework(FScopeStore, FScopePath, FFrameworkSrc);
    end;
    if FFramework = '' then Exit;
    var Source : string := Format('%s (%s)', [FFramework, ExtractFileName(FFrameworkSrc)]);
    var Dropped: Boolean:= False;
    for var I: Integer:= 0 to High(Alive) do
    begin
      var CandFw: string:= FrameworkOf(AScoped.Candidates[I]);
      if (CandFw = '') or (CandFw = FFramework) then Continue;
      Alive[I]      := False;
      Dropped       := True;
      AScoped.Why[I]:= 'framework mismatch: the project is ' + Source;
    end;
    if Dropped then Evidence:= Evidence + ['the project framework ' + Source];
  end;

  { (a2) the form file's kind: a .dfm form is VCL, a .fmx form FMX (each
    framework streams its own), so a candidate of the other one is excluded }
  procedure DropByFormKind;
  begin
    if (AliveCount < 2) or (FScopePath = '') then Exit;
    var Form: string:= ChangeFileExt(FScopePath, '.dfm');
    var Fw  : string:= 'VCL';
    if not TFile.Exists(Form) then
    begin
      Form:= ChangeFileExt(FScopePath, '.fmx');
      Fw  := 'FMX';
      if not TFile.Exists(Form) then Exit;
    end;
    var Dropped: Boolean:= False;
    for var I: Integer:= 0 to High(Alive) do
    begin
      var CandFw: string:= FrameworkOf(AScoped.Candidates[I]);
      if not Alive[I] or (CandFw = '') or (CandFw = Fw) then Continue;
      Alive[I]      := False;
      Dropped       := True;
      AScoped.Why[I]:= Format('form-file mismatch: %s is a %s form', [ExtractFileName(Form), Fw]);
    end;
    if Dropped then Evidence:= Evidence + [Format('the form file %s (%s)', [ExtractFileName(Form), Fw])];
  end;

  { whether live candidate AIndex declares each of AProps on the .dfm surface }
  function DeclaresRow(AIndex: Integer; const AProps: TArray<string>): TArray<Boolean>;
  begin
    SetLength(Result, Length(AProps));
    if not Alive[AIndex] then Exit;
    var Ref: TClassRef:= ClassFor(QNameOf(AIndex));
    for var P: Integer:= 0 to High(AProps) do
    begin
      var Node: TPropNode;
      Result[P]:= (Ref.QName <> '') and Ref.ResolvePath(AProps[P], psDfm, Node);
    end;
  end;

  { a property SOME live candidate declares and another does not: evidence.
    One no live candidate declares (DefineProperties: Explicit*, DesignSize)
    tells them apart from nothing -- ignored. }
  function Discriminates(const ADeclares: TArray<TArray<Boolean>>; AProp: Integer): Boolean;
  begin
    var AnyHas : Boolean:= False;
    var AllHave: Boolean:= True;
    for var I: Integer:= 0 to High(Alive) do
      if Alive[I] then
      begin
        AnyHas := AnyHas or ADeclares[I][AProp];
        AllHave:= AllHave and ADeclares[I][AProp];
      end;
    Result:= AnyHas and not AllHave;
  end;

  { (b) the .dfm evidence: what the unit's .dfm streams on objects of AName }
  procedure DropByDfm;
  begin
    if (AliveCount < 2) or (FScopePath = '') then Exit;
    var Props: TArray<string>:= DfmStreamedProps(ChangeFileExt(FScopePath, '.dfm'), AName);
    if Length(Props) = 0 then Exit;
    var Declares: TArray<TArray<Boolean>>;
    SetLength(Declares, Length(Alive));
    for var I: Integer:= 0 to High(Alive) do Declares[I]:= DeclaresRow(I, Props);
    var Used: TArray<string>:= nil;
    for var P: Integer:= 0 to High(Props) do
      if Discriminates(Declares, P) then Used:= Used + [Props[P]];
    if Length(Used) = 0 then Exit;
    for var I: Integer:= 0 to High(Alive) do
      for var P: Integer:= 0 to High(Props) do
        if Alive[I] and MatchText(Props[P], Used) and not Declares[I][P] then
        begin
          Alive[I]      := False;
          AScoped.Why[I]:= Format('.dfm property %s not declared', [Props[P]]);
        end;
    Evidence:= Evidence + ['.dfm properties ' + String.Join(', ', Used)];
  end;

begin
  Result:= False;
  if Length(AScoped.Candidates) < 2 then Exit;
  SetLength(Alive, Length(AScoped.Candidates));
  for var I: Integer:= 0 to High(Alive) do Alive[I]:= True;
  Evidence:= nil;
  DropByFramework;
  DropByFormKind;
  DropByDfm;
  if AliveCount <> 1 then
  begin
    { still a tie: say so on every survivor }
    if Length(Evidence) > 0 then
      for var I: Integer:= 0 to High(Alive) do
        if Alive[I] then AScoped.Why[I]:= 'tie: fits ' + String.Join(' and ', Evidence) + ' as well as another candidate';
    Exit;
  end;
  for var I: Integer:= 0 to High(Alive) do
    if Alive[I] then
    begin
      AScoped.QName     := QNameOf(I);
      AScoped.Resolution:= PAS_RES_RESOLVED;
      AScoped.Inferred  := String.Join(' and ', Evidence);
      AScoped.Why[I]    := 'inferred from ' + AScoped.Inferred;
    end;
  Result:= True;
end;

// ALineText with the bare AName on side ASide ('from': before '->', 'to':
// after it) replaced by AQName -- the first whole-word, unqualified match.
function QualifyLine(const ALineText, AName, ASide, AQName: string): string;
begin
  var Arrow: Integer:= Pos('->', ALineText);
  var Left : string:= if Arrow > 0 then Copy(ALineText, 1, Arrow - 1) else ALineText;
  var Right: string:= if Arrow > 0 then Copy(ALineText, Arrow, MaxInt) else '';
  var Word : TRegEx:= TRegEx.Create('(?<![\w.])' + TRegEx.Escape(AName) + '(?![\w.])', [roIgnoreCase]);
  if ASide = 'from' then Left:= Word.Replace(Left, AQName, 1)
  else Right:= Word.Replace(Right, AQName, 1);
  Result:= Left + Right;
end;

function MakeQualifyFix(const ALineText: string; ALine: Integer; const AName, ASide: string;
  const AScoped: TScopedClass): TQualifyFix;

  function Suggestion(AIndex: Integer): TQualifySuggestion;
  begin
    var Stem: string:= AScoped.Candidates[AIndex];
    Result.Candidate  := Stem + '.' + AName;
    Result.Replacement:= QualifyLine(Trim(ALineText), AName, ASide, Result.Candidate);
    Result.Why        := if AIndex <= High(AScoped.Why) then AScoped.Why[AIndex] else '';
    Result.Alternative:= if ASide = 'to' then '#use ' + Stem else Format('add %s to the unit''s uses', [Stem]);
  end;

begin
  Result:= Default(TQualifyFix);
  Result.RuleLine:= ALine;
  Result.Current := Trim(ALineText);
  Result.Name    := AName;
  Result.Side    := ASide;
  var Inferred: Boolean:= (AScoped.Resolution = PAS_RES_RESOLVED) and (AScoped.Inferred <> '');
  Result.Outcome := if Inferred then 'inferred' else 'refused';
  if Inferred then
  begin
    Result.Chosen   := AScoped.QName;
    Result.Inference:= AScoped.Inferred;
    for var I: Integer:= 0 to High(AScoped.Candidates) do
      if SameText(AScoped.Candidates[I] + '.' + AName, AScoped.QName) then
        Result.Suggestions:= [Suggestion(I)] + Result.Suggestions
      else
        Result.Suggestions:= Result.Suggestions + [Suggestion(I)];
  end
  else
    for var I: Integer:= 0 to High(AScoped.Candidates) do Result.Suggestions:= Result.Suggestions + [Suggestion(I)];
  if Length(Result.Suggestions) > 0 then Result.Alternative:= Result.Suggestions[0].Alternative;
end;

function QualifyRefusalText(const AFix: TQualifyFix): string;
begin
  var Parts: TArray<string>:= nil;
  for var S: TQualifySuggestion in AFix.Suggestions do Parts:= Parts + [Format('%s (%s)', [S.Candidate, S.Why])];
  Result:= Format('%s (line %d): the bare name %s is ambiguous in this unit''s scope -- candidates %s -- ' +
    'qualify the #convert line (paste one of the suggested lines, apply/1 qualify_fixes[]) or %s; ' +
    'nothing was validated against a guess',
    [AFix.Current, AFix.RuleLine, AFix.Name, String.Join(', ', Parts),
     if AFix.Side = 'to' then 'add #use <Unit> to the book' else 'add the declaring unit to the unit''s uses']);
end;

function QualifyInferredText(const AFix: TQualifyFix): string;
begin
  Result:= Format('#convert %s resolved to %s (line %d): inferred from %s; qualify the line to silence this: %s',
    [AFix.Name, AFix.Chosen, AFix.RuleLine, AFix.Inference,
     if Length(AFix.Suggestions) > 0 then AFix.Suggestions[0].Replacement else AFix.Current]);
end;

function TConvertTreeCache.ResolveType(const ATypeName: string): string;
begin
  Result:= Lookup(ATypeName).QName;
end;

function TConvertTreeCache.CacheFor(AStore: Integer): TPropMemberCache;
begin
  if (AStore < 0) or (AStore > High(FStores)) then Exit(nil);
  if FCaches[AStore] = nil then
    FCaches[AStore]:= TPropMemberCache.Create(FStores[AStore], FOptions);
  Result:= FCaches[AStore];
end;

function TConvertTreeCache.ClassFor(const ATypeName: string): TClassRef;
var
  R: TResolved;
begin
  Result:= Default(TClassRef);
  R:= Lookup(ATypeName);
  if R.Store < 0 then Exit;
  Result.QName:= R.QName;
  Result.Cache:= CacheFor(R.Store);
end;

function TConvertTreeCache.ClassSymbol(const ATypeName: string; out AStore: ISymbolStore): TSymbol;
var
  R: TResolved;
begin
  Result:= Default(TSymbol);
  AStore:= nil;
  R:= Lookup(ATypeName);
  if R.Store < 0 then Exit;
  AStore:= FStores[R.Store];
  for var S: TSymbol in AStore.FindSymbolsByExactName(BareTypeTail(R.QName)) do
    if (S.Kind = skClass) and SameText(S.QualifiedName, R.QName) then Exit(S);
end;

function TConvertTreeCache.GetClassesBuilt: Integer;
var
  C: TPropMemberCache;
begin
  Result:= 0;
  for C in FCaches do
    if C <> nil then Inc(Result, C.ClassesBuilt);
end;

const
  { apply/1 inherited[].ancestor_state values (C8 N1 / N3) -- a compatibility
    surface: the converter editor dispatches on these spellings. }
  ANCESTOR_UNCONVERTED = 'unconverted';
  ANCESTOR_CONVERTED   = 'converted';
  ANCESTOR_OUTSIDE     = 'outside';
  ANCESTOR_MISMATCHED  = 'mismatched';
  { the filer signature a compiled (binary) .dfm starts with }
  BINARY_DFM_SIGNATURE = 'TPF0';
  { the first byte of a .dfm stored as a Windows RES resource }
  RES_HEADER_FIRST_BYTE = $FF;
  { a UTF-8 byte-order mark as an ANSI decode spells it }
  UTF8_BOM_AS_ANSI = #$EF#$BB#$BF;
  { .dfm block keywords, without their trailing space }
  KW_OBJECT    = 'object';
  KW_INHERITED = 'inherited';
  KW_INLINE    = 'inline';
  KW_ITEM      = 'item';
  KW_END       = 'end';

// The inherited / inline objects of ADfmText whose class is a From type, with
// Name, TypeName, ToType, Line and OwnerClass set (the ancestor fields are
// left empty). OwnerClass is the class of the nearest ENCLOSING `inline`
// block, else the root block's class: a frame's children are declared by the
// frame, everything else by the form's ancestry. Blocks are tracked on a
// stack -- object / inherited / inline headers (with or without a class) and
// collection `item`s open one, `end` / `end>` closes one. Pure.
function ScanInheritedConvertInstances(const ADfmText: string; const ARules: TConversionRuleSet): TArray<TInheritedInstance>;
var
  Lines  : TArray<string>;
  Kinds  : TList<string>; { the open blocks' keywords, outermost first }
  OpenClasses: TList<string>; { their OpenClasses, '' when the header names none }
  Found  : TList<TInheritedInstance>;
  I      : Integer;
  T, Kw  : string;
  ObjName, ObjClass, ToType: string;
  Inst   : TInheritedInstance;

  function KeywordOf(const ATrimmed: string): string;
  begin
    if StartsText(KW_OBJECT + ' ', ATrimmed) then Result:= KW_OBJECT
    else if StartsText(KW_INHERITED + ' ', ATrimmed) then Result:= KW_INHERITED
    else if StartsText(KW_INLINE + ' ', ATrimmed) then Result:= KW_INLINE
    else Result:= '';
  end;

  function OwnerOf: string;
  begin
    for var K: Integer:= Kinds.Count - 1 downto 1 do
      if Kinds[K] = KW_INLINE then Exit(OpenClasses[K]);
    Result:= if OpenClasses.Count > 0 then OpenClasses[0] else '';
  end;

begin
  Lines  := ADfmText.Replace(#13#10, #10).Replace(#13, #10).Split([#10]);
  Kinds  := TList<string>.Create;
  OpenClasses:= TList<string>.Create;
  Found  := TList<TInheritedInstance>.Create;
  try
    for I:= 0 to High(Lines) do
    begin
      T := Trim(Lines[I]);
      Kw:= KeywordOf(T);
      if Kw <> '' then
      begin
        if not TryParseHeaderAfter(T, Kw + ' ', ObjName, ObjClass) then ObjClass:= '';
        if (Kw <> KW_OBJECT) and (Kinds.Count > 0) and (ObjClass <> '') and
           FindConvertRuleFor(ARules, ObjClass, ToType) then
        begin
          Inst           := Default(TInheritedInstance);
          Inst.Name      := ObjName;
          Inst.TypeName  := ObjClass;
          Inst.ToType    := ToType;
          Inst.Line      := I + 1;
          Inst.OwnerClass:= OwnerOf;
          Found.Add(Inst);
        end;
        Kinds.Add(Kw);
        OpenClasses.Add(ObjClass);
      end
      else if SameText(T, KW_ITEM) then
      begin
        Kinds.Add(KW_ITEM);
        OpenClasses.Add('');
      end
      else if (Kinds.Count > 0) and (SameText(T, KW_END) or SameText(T, KW_END + '>')) then
      begin
        Kinds.Delete(Kinds.Count - 1);
        OpenClasses.Delete(OpenClasses.Count - 1);
      end;
    end;
    Result:= Found.ToArray;
  finally
    Found.Free;
    OpenClasses.Free;
    Kinds.Free;
  end;
end;

function NestedOnlyInstances(const ADfmText: string; const ARules: TConversionRuleSet;
  const AOnly: TArray<string>): TArray<TNestedOnly>;
var
  Open   : TList<string>; { per open block: the converting instance's name, '' when it converts nothing }
  T, Kw  : string;
  HdrName  : string;
  HdrClass : string;
  ToType : string;
  Parent : string;
  N      : TNestedOnly;
begin
  Result:= nil;
  if Length(AOnly) = 0 then Exit;
  Open:= TList<string>.Create;
  try
    for var L: string in ADfmText.Replace(#13#10, #10).Replace(#13, #10).Split([#10]) do
    begin
      T:= Trim(L);
      Kw:= '';
      if StartsText(KW_OBJECT + ' ', T) then Kw:= KW_OBJECT + ' '
      else if StartsText(KW_INHERITED + ' ', T) then Kw:= KW_INHERITED + ' '
      else if StartsText(KW_INLINE + ' ', T) then Kw:= KW_INLINE + ' ';
      if Kw <> '' then
      begin
        Parent:= '';
        for var K: Integer:= Open.Count - 1 downto 0 do
          if Open[K] <> '' then
          begin
            Parent:= Open[K];
            Break;
          end;
        HdrName:= '';
        if (Kw = KW_OBJECT + ' ') and TryParseHeaderAfter(T, Kw, HdrName, HdrClass) and FindConvertRuleFor(ARules, HdrClass, ToType) then
        begin
          if not InOnlyList(HdrName, AOnly) and (Parent <> '') then
          begin
            N:= Default(TNestedOnly);
            N.Instance.InstanceName:= HdrName;
            N.Instance.FromType    := HdrClass;
            N.Instance.ToType      := ToType;
            N.Parent               := Parent;
            Result:= Result + [N];
          end
          else if not InOnlyList(HdrName, AOnly) then
            HdrName:= '';
        end
        else
          HdrName:= '';
        Open.Add(HdrName);
      end
      else if SameText(T, KW_ITEM) then
        Open.Add('')
      else if (Open.Count > 0) and (SameText(T, KW_END) or SameText(T, KW_END + '>')) then
        Open.Delete(Open.Count - 1);
    end;
  finally
    Open.Free;
  end;
end;

// True + the header's class when ADfmText opens a block named AName with
// `object` or `inline` -- i.e. DECLARES it rather than re-opening it with
// `inherited`. Component names are unique within a form, so the first match
// at any depth is the one.
function DfmDeclaresComponent(const ADfmText, AName: string; out AClassName: string): Boolean;
var
  L, T, ObjName: string;
begin
  AClassName:= '';
  for L in ADfmText.Replace(#13#10, #10).Replace(#13, #10).Split([#10]) do
  begin
    T:= Trim(L);
    if (TryParseHeaderAfter(T, KW_OBJECT + ' ', ObjName, AClassName) or
        TryParseHeaderAfter(T, KW_INLINE + ' ', ObjName, AClassName)) and SameText(ObjName, AName) then
      Exit(True);
  end;
  AClassName:= '';
  Result:= False;
end;

// True when ABytes are a compiled (binary) .dfm: the TPF0 filer signature, or
// a Windows resource header (first byte $FF).
function IsBinaryDfmBytes(const ABytes: TBytes): Boolean;
begin
  Result:= ((Length(ABytes) > 0) and (ABytes[0] = RES_HEADER_FIRST_BYTE)) or
           ((Length(ABytes) >= Length(BINARY_DFM_SIGNATURE)) and
            (TEncoding.ANSI.GetString(ABytes, 0, Length(BINARY_DFM_SIGNATURE)) = BINARY_DFM_SIGNATURE));
end;

// True when AText, past leading whitespace and a UTF-8 BOM, opens with a
// text .dfm block header (object / inherited / inline).
function StartsWithBlockHeader(const AText: string): Boolean;
var
  T: string;
begin
  T:= TrimLeft(AText);
  if StartsStr(UTF8_BOM_AS_ANSI, T) then T:= TrimLeft(Copy(T, Length(UTF8_BOM_AS_ANSI) + 1, MaxInt));
  if StartsStr(#$FEFF, T) then T:= TrimLeft(Copy(T, Length(#$FEFF) + 1, MaxInt));
  Result:= StartsText(KW_OBJECT + ' ', T) or StartsText(KW_INHERITED + ' ', T) or StartsText(KW_INLINE + ' ', T);
end;

// True when two paths name the same file, case-insensitively; '' never matches.
function SamePath(const APathA, APathB: string): Boolean;
begin
  Result:= (APathA <> '') and (APathB <> '') and SameText(TPath.GetFullPath(APathA), TPath.GetFullPath(APathB));
end;

// The source files of AOwner's class and of each of its resolved class
// ancestors, nearest first, from the one --db store that resolves AOwner. A
// class declared in AUnitPas wins over same-named classes elsewhere; otherwise
// exactly one candidate across the stores must exist. Empty + ADetail when the
// owner does not resolve; ADetail is also set when the chain stops at an
// unresolved ancestor (the files before it are still returned).
function OwnerChainFiles(const ATrees: TConvertTreeCache; const AOwner, AUnitPas: string;
  out ADetail: string): TArray<string>;
var
  St      : ISymbolStore;
  S       : TSymbol;
  A       : TTypeAncestor;
  Count   : Integer;
  OwnUnit : Boolean;
  PickSt  : ISymbolStore;
  PickSym : TSymbol;
begin
  Result := nil;
  ADetail:= '';
  Count  := 0;
  OwnUnit:= False;
  PickSt := nil;
  PickSym:= Default(TSymbol);
  for St in ATrees.Stores do
    for S in St.FindSymbolsByExactName(AOwner) do
    begin
      if (S.Kind <> skClass) or OwnUnit then Continue;
      Inc(Count);
      OwnUnit:= SamePath(St.GetFilePath(S.FileId), AUnitPas);
      if (Count = 1) or OwnUnit then
      begin
        PickSt := St;
        PickSym:= S;
      end;
    end;
  if Count = 0 then
  begin
    ADetail:= Format('class %s is in no --db', [AOwner]);
    Exit;
  end;
  if (Count > 1) and not OwnUnit then
  begin
    ADetail:= Format('class %s is ambiguous across the --db', [AOwner]);
    Exit;
  end;
  Result:= [PickSt.GetFilePath(PickSym.FileId)];
  for A in PickSt.GetTransitiveAncestors(PickSym.Id) do
  begin
    if SameText(A.Kind, 'interface') then Continue;
    if not A.Resolved then
    begin
      ADetail:= Format('the ancestor chain of %s leaves the index at %s', [AOwner, A.Name]);
      Break;
    end;
    Result:= Result + [PickSt.GetFilePath(A.FileId)];
  end;
end;

function FindInheritedInstances(const ATrees: TConvertTreeCache; const AUnitPas, ADfmPath: string;
  const ARules: TConversionRuleSet; const AOnly: TArray<string>): TArray<TInheritedInstance>;
var
  DfmTexts: TDictionary<string, string>; { ancestor .dfm path (upper) -> text, read once per run }
  I       : Integer;

  { True + the TEXT of an ancestor .dfm; False + why not ('is missing',
    'is binary (TPF0)', 'is not a text .dfm', 'cannot be read: ...'). Texts
    are cached per run; a failure is not, it ends the walk anyway. }
  function TryAncestorDfmText(const APath: string; out AText, AWhy: string): Boolean;
  var
    Bytes: TBytes;
  begin
    AWhy:= '';
    if DfmTexts.TryGetValue(UpperCase(APath), AText) then Exit(True);
    AText:= '';
    if not TFile.Exists(APath) then
    begin
      AWhy:= 'is missing';
      Exit(False);
    end;
    try
      Bytes:= TFile.ReadAllBytes(APath);
    except
      on E: Exception do
      begin
        AWhy:= 'cannot be read: ' + E.Message;
        Exit(False);
      end;
    end;
    if IsBinaryDfmBytes(Bytes) then
    begin
      AWhy:= 'is binary (TPF0)';
      Exit(False);
    end;
    AText:= DecodeUnitBytes(Bytes);
    if not StartsWithBlockHeader(AText) then
    begin
      AText:= '';
      AWhy := 'is not a text .dfm';
      Exit(False);
    end;
    DfmTexts.Add(UpperCase(APath), AText);
    Result:= True;
  end;

  procedure Resolve(var AInst: TInheritedInstance);
  var
    Detail   : string;
    F, Dfm   : string;
    DeclClass: string;
    Text, Why: string;
  begin
    AInst.AncestorState:= ANCESTOR_OUTSIDE;
    AInst.AncestorUnit := '';
    AInst.Action       := INH_ACTION_SKIPPED;
    Detail:= '';
    if AInst.OwnerClass = '' then
      Detail:= 'the .dfm names no owner class'
    else
      for F in OwnerChainFiles(ATrees, AInst.OwnerClass, AUnitPas, Detail) do
      begin
        if F = '' then
        begin
          Detail:= Format('a class in the ancestor chain of %s has no source file in the index', [AInst.OwnerClass]);
          Break;
        end;
        Dfm:= TPath.ChangeExtension(F, '.dfm');
        if SamePath(Dfm, ADfmPath) then Continue;
        { N3: an ancestor whose .dfm cannot be READ as text stops the walk --
          it may declare the component, so crediting a farther ancestor would
          be a guess }
        if not TryAncestorDfmText(Dfm, Text, Why) then
        begin
          Detail:= Format('%s %s', [ExtractFileName(Dfm), Why]);
          Break;
        end;
        if not DfmDeclaresComponent(Text, AInst.Name, DeclClass) then Continue;
        AInst.AncestorUnit:= TPath.GetFileNameWithoutExtension(F);
        if SameText(DeclClass, AInst.TypeName) then
        begin
          AInst.AncestorState:= ANCESTOR_UNCONVERTED;
          AInst.Reason:= Format('declared in %s, which still has %s -- convert %s first (recommended)',
            [AInst.AncestorUnit, DeclClass, AInst.AncestorUnit]);
        end
        else if SameText(DeclClass, AInst.ToType) then
        begin
          AInst.AncestorState:= ANCESTOR_CONVERTED;
          AInst.Action       := INH_ACTION_RETYPED;
          AInst.Reason:= Format('declared in %s, which already has %s -- retyped to %s',
            [AInst.AncestorUnit, DeclClass, AInst.ToType]);
        end
        else
        begin
          AInst.AncestorState:= ANCESTOR_MISMATCHED;
          AInst.Reason:= Format('declared in %s as %s, neither %s nor %s -- not converted',
            [AInst.AncestorUnit, DeclClass, AInst.TypeName, AInst.ToType]);
        end;
        Exit;
      end;
    if Detail = '' then Detail:= Format('no ancestor .dfm of %s declares %s', [AInst.OwnerClass, AInst.Name]);
    AInst.Reason:= Format('declaring ancestor not found (%s) -- convert it from its own project', [Detail]);
  end;

begin
  Result:= nil;
  if (ADfmPath = '') or not TFile.Exists(ADfmPath) then Exit;
  for var Found: TInheritedInstance in ScanInheritedConvertInstances(ReadUnitText(ADfmPath), ARules) do
    if InOnlyList(Found.Name, AOnly) then Result:= Result + [Found];
  DfmTexts:= TDictionary<string, string>.Create;
  try
    for I:= 0 to High(Result) do Resolve(Result[I]);
  finally
    DfmTexts.Free;
  end;
end;

function UnitFileIdIn(const AStore: ISymbolStore; const APath: string): Int64;
var
  Syms: TArray<TSymbol>;
begin
  Result:= AStore.FindFileIdByPath(APath);
  if Result > 0 then Exit;
  Result:= AStore.FindFileIdByPath(TPath.GetFullPath(APath));
  if Result > 0 then Exit;
  Syms:= AStore.FindSymbolsByFile(APath);
  Result:= if Length(Syms) > 0 then Syms[0].FileId else -1;
end;

procedure AppendInheritedReport(const AInstances: TArray<TInheritedInstance>; const ADfmPath: string;
  var AReport: TApplyReport);
const
  UNIT_EXT = '.pas'; { a code-only entry carries its .pas in OwnerClass }
var
  Inst: TInheritedInstance;
  It  : TApplyItem;
begin
  for Inst in AInstances do
  begin
    if Inst.Action = INH_ACTION_UNVERIFIED then
    begin
      It         := Default(TApplyItem);
      It.Kind    := aikAccessSiteUnverified;
      It.Field   := afWarnings;
      It.Instance:= Inst.Name;
      It.FromType:= Inst.TypeName;
      It.ToType  := Inst.ToType;
      It.FilePath:= Inst.OwnerClass; { the .pas, carried here by FindInheritedCodeUses }
      It.Line    := Inst.Line;
      It.Text    := Format('access site %s:%d %s not verified against the index -- not rewritten',
                      [ExtractFileName(Inst.OwnerClass), Inst.Line, Inst.Name]);
      AReport.Warnings:= AReport.Warnings + [It.Text];
      AReport.Items   := AReport.Items + [It];
      Continue;
    end;
    if Inst.Action <> INH_ACTION_SKIPPED then Continue; { retyped / code: not a warning (C8 N2) }
    It         := Default(TApplyItem);
    It.Kind    := aikInheritedInstanceSkipped;
    It.Field   := afWarnings;
    It.Instance:= Inst.Name;
    It.FromType:= Inst.TypeName;
    It.ToType  := Inst.ToType;
    It.FilePath:= if SameText(ExtractFileExt(Inst.OwnerClass), UNIT_EXT) then Inst.OwnerClass else ADfmPath; { 1.26.7: a code-only entry's line is in the .pas }
    It.Line    := Inst.Line;
    It.Text    := Format('line %d: warning: inherited instance %s: %s skipped -- %s',
                    [Inst.Line, Inst.Name, Inst.TypeName, Inst.Reason]);
    AReport.Warnings:= AReport.Warnings + [It.Text];
    AReport.Items   := AReport.Items + [It];
  end;
end;

const
  { apply/1 descendants[].reason values (1.25.0) -- a compatibility surface }
  DESC_REASON_DFM  = 'dfm';
  DESC_REASON_CODE = 'code';
  DESC_REASON_BOTH = 'both';
  { the receiver text of an explicit `Self.X` access }
  SELF_RECEIVER = 'Self';
  { how many parents a reference's enclosing routine is walked up to reach its
    class -- a method, then up to three nested routines inside it }
  ENCLOSING_CLASS_HOPS = 4;
  { the source extension of a form file }
  DFM_EXT = '.dfm';
  { the source extension of a unit }
  PAS_EXT = '.pas';

function FindInheritedCodeUses(const ATrees: TConvertTreeCache; const AUnitPas: string;
  const ARules: TConversionRuleSet; const AOnly: TArray<string>;
  const AInherited: TArray<TInheritedInstance>): TArray<TInheritedInstance>;
const
  { how many parents a field symbol is walked up to reach its class }
  FIELD_CLASS_HOPS = 3;
var
  St       : ISymbolStore;
  FileId   : Int64;
  OwnIds   : TDictionary<Int64, Boolean>;  { classes AUnitPas declares }
  AncIds   : TDictionary<Int64, Boolean>;  { their transitive ancestors, minus the own ones }
  Fields   : TDictionary<Int64, Integer>;  { field symbol id -> index into Found, -1 = not a candidate }
  Found    : TList<TInheritedInstance>;
  DfmTexts : TDictionary<string, string>;  { upper .dfm path -> text ('' when unreadable) }
  S        : TSymbol;
  R        : TReference;
  Ix       : Integer;

  { the class symbol a field belongs to, or 0 }
  function ClassOf(const AField: TSymbol): Int64;
  var
    P: TSymbol;
  begin
    P:= AField;
    for var Hop: Integer:= 1 to FIELD_CLASS_HOPS do
    begin
      if P.ParentId = 0 then Break;
      P:= St.GetSymbolById(P.ParentId);
      if P.Kind = skClass then Exit(P.Id);
    end;
    Result:= 0;
  end;

  { the text of a text .dfm, cached; '' when missing, binary or unreadable }
  function DfmTextOf(const APath: string): string;
  var
    Bytes: TBytes;
  begin
    if DfmTexts.TryGetValue(UpperCase(APath), Result) then Exit;
    Result:= '';
    if TFile.Exists(APath) then
    try
      Bytes:= TFile.ReadAllBytes(APath);
      if not IsBinaryDfmBytes(Bytes) then Result:= DecodeUnitBytes(Bytes);
    except
      on EInOutError do Result:= '';
      on EFileStreamError do Result:= '';
    end;
    DfmTexts.Add(UpperCase(APath), Result);
  end;

  { 1.26.7 (converter request): -1, or the Found index of a new entry when
    AField is a component field the declaring ancestor still declares with a
    #convert block's FROM type. Action 'skipped' (an unbound reference keeps
    AAction 'unverified'), AncestorState 'unconverted', Reason exactly
    'ancestor not converted'; the code is not rewritten, so the descendant
    simply follows its ancestor's conversion later. }
  function UnconvertedCandidate(const AField: TSymbol; const AAction: string): Integer;
  var
    ToType, DeclClass, DeclPas: string;
    Inst: TInheritedInstance;
  begin
    Result:= -1;
    if (AField.Kind <> skField) or not AncIds.ContainsKey(ClassOf(AField)) then Exit;
    if not InOnlyList(AField.Name, AOnly) then Exit;
    for var Inh: TInheritedInstance in AInherited do
      if SameText(Inh.Name, AField.Name) then Exit;
    if not FindConvertRuleFor(ARules, BareTypeTail(AField.Signature), ToType) then Exit;
    DeclPas:= St.GetFilePath(AField.FileId);
    if not DfmDeclaresComponent(DfmTextOf(TPath.ChangeExtension(DeclPas, DFM_EXT)), AField.Name, DeclClass) or
       not SameText(DeclClass, BareTypeTail(AField.Signature)) then Exit;
    Inst              := Default(TInheritedInstance);
    Inst.Name         := AField.Name;
    Inst.TypeName     := DeclClass;
    Inst.ToType       := ToType;
    Inst.AncestorUnit := TPath.GetFileNameWithoutExtension(DeclPas);
    Inst.AncestorState:= ANCESTOR_UNCONVERTED;
    Inst.Action       := if AAction = INH_ACTION_UNVERIFIED then INH_ACTION_UNVERIFIED else INH_ACTION_SKIPPED;
    Inst.OwnerClass   := AUnitPas; { the .pas the line refers to }
    Inst.Reason       := 'ancestor not converted';
    Result:= Found.Add(Inst);
  end;

  { -1, or the Found index of a new entry when AField is a converted ancestor's
    component field of a #convert To type -- or (1.26.7) an UNCONVERTED one's,
    still of the block's From type: listed 'skipped', never rewritten }
  function Candidate(const AField: TSymbol; const AAction: string = INH_ACTION_CODE): Integer;
  var
    FromType, DeclClass, DeclPas: string;
    Inst    : TInheritedInstance;
  begin
    Result:= UnconvertedCandidate(AField, AAction);
    if Result >= 0 then Exit;
    Result:= -1;
    if (AField.Kind <> skField) or not AncIds.ContainsKey(ClassOf(AField)) then Exit;
    if not InOnlyList(AField.Name, AOnly) then Exit;
    for var Inh: TInheritedInstance in AInherited do
      if SameText(Inh.Name, AField.Name) then Exit;
    FromType:= '';
    for var CR: TConversionRule in ARules.Rules do
      if (CR.Kind = rkConvert) and SameText(BareTypeTail(CR.ToType), BareTypeTail(AField.Signature)) then
      begin
        FromType:= BareTypeTail(CR.FromType);
        Break;
      end;
    if FromType = '' then Exit;
    DeclPas:= St.GetFilePath(AField.FileId);
    if not DfmDeclaresComponent(DfmTextOf(TPath.ChangeExtension(DeclPas, DFM_EXT)), AField.Name, DeclClass) or
       not SameText(DeclClass, BareTypeTail(AField.Signature)) then Exit;
    Inst              := Default(TInheritedInstance);
    Inst.Name         := AField.Name;
    Inst.TypeName     := FromType;
    Inst.ToType       := DeclClass;
    Inst.AncestorUnit := TPath.GetFileNameWithoutExtension(DeclPas);
    Inst.AncestorState:= ANCESTOR_CONVERTED;
    Inst.Action       := AAction;
    if AAction = INH_ACTION_UNVERIFIED then
    begin
      Inst.OwnerClass:= AUnitPas; { where the reference is, for the warning }
      Inst.Reason    := Format('declared in %s, which already has %s -- an UNBOUND reference: not verified against the index, not rewritten',
                          [Inst.AncestorUnit, DeclClass]);
    end
    else
      Inst.Reason:= Format('declared in %s, which already has %s -- code access sites follow it (no .dfm block)',
                      [Inst.AncestorUnit, DeclClass]);
    Result:= Found.Add(Inst);
  end;

  { True when the routine ARoutineId sits in (nested routines walked up) belongs
    to a class of this unit and declares no local / parameter named AName }
  function InOwnClassUnshadowed(ARoutineId: Int64; const AName: string): Boolean;
  var
    P: TSymbol;
  begin
    P:= St.GetSymbolById(ARoutineId);
    for var Hop: Integer:= 1 to ENCLOSING_CLASS_HOPS do
    begin
      if P.Id = 0 then Break;
      if P.Kind = skClass then Exit(OwnIds.ContainsKey(P.Id));
      if St.FindChildSymbolByName(P.Id, AName).Id <> 0 then Break;
      P:= St.GetSymbolById(P.ParentId);
    end;
    Result:= False;
  end;

  { 1.26.0 (C8 N2 review): an UNBOUND bare / Self. reference whose name is a
    converted ancestor's component field, in a routine of this unit's class
    that does not shadow it -- the resolver could not tie it to the field, so
    it is not rewritten, and it is REPORTED rather than dropped in silence.
    A name some bound reference already made a 'code' entry is not repeated. }
  procedure CollectUnbound(const ARefs: TArray<TReference>);
  var
    F    : TSymbol;
    Seen : TDictionary<string, Boolean>;
  begin
    Seen:= TDictionary<string, Boolean>.Create;
    try
      for var E: TInheritedInstance in Found do Seen.AddOrSetValue(UpperCase(E.Name), True);
      for var U: TReference in ARefs do
      begin
        if (U.SymbolId <> 0) or (U.EnclosingSymbolId = 0) then Continue;
        if (U.ReceiverText <> '') and not SameText(U.ReceiverText, SELF_RECEIVER) then Continue;
        if Seen.ContainsKey(UpperCase(U.NameText)) then
        begin
          for var K: Integer:= 0 to Found.Count - 1 do
            if (Found[K].Action = INH_ACTION_UNVERIFIED) and SameText(Found[K].Name, U.NameText) and (U.StartLine < Found[K].Line) then
            begin
              var Hit: TInheritedInstance:= Found[K];
              Hit.Line:= U.StartLine;
              Found[K]:= Hit;
            end;
          Continue;
        end;
        if not InOwnClassUnshadowed(U.EnclosingSymbolId, U.NameText) then Continue;
        F:= Default(TSymbol);
        for var AncId: Int64 in AncIds.Keys do
        begin
          F:= St.FindChildSymbolByName(AncId, U.NameText);
          if (F.Id <> 0) and (F.Kind = skField) then Break;
          F:= Default(TSymbol);
        end;
        if F.Id = 0 then Continue;
        var Ix2: Integer:= Candidate(F, INH_ACTION_UNVERIFIED);
        if Ix2 < 0 then Continue;
        var Hit: TInheritedInstance:= Found[Ix2];
        Hit.Line:= U.StartLine;
        Found[Ix2]:= Hit;
        Seen.AddOrSetValue(UpperCase(U.NameText), True);
      end;
    finally
      Seen.Free;
    end;
  end;

begin
  Result:= nil;
  St:= nil;
  FileId:= 0;
  for var C: ISymbolStore in ATrees.Stores do
  begin
    FileId:= UnitFileIdIn(C, AUnitPas); { 1.26.5: a moved tree too }
    if FileId > 0 then
    begin
      St:= C;
      Break;
    end;
  end;
  if St = nil then Exit;
  OwnIds  := TDictionary<Int64, Boolean>.Create;
  AncIds  := TDictionary<Int64, Boolean>.Create;
  Fields  := TDictionary<Int64, Integer>.Create;
  Found   := TList<TInheritedInstance>.Create;
  DfmTexts:= TDictionary<string, string>.Create;
  try
    for S in St.FindSymbolsByFile(St.GetFilePath(FileId)) do
      if S.Kind = skClass then OwnIds.AddOrSetValue(S.Id, True);
    for var OwnId: Int64 in OwnIds.Keys do
      for var A: TTypeAncestor in St.GetTransitiveAncestors(OwnId) do
        if A.Resolved and (A.SymbolId <> 0) and not OwnIds.ContainsKey(A.SymbolId) then
          AncIds.AddOrSetValue(A.SymbolId, True);
    if AncIds.Count = 0 then Exit;
    var FileRefs: TArray<TReference>:= St.GetReferencesFromFile(FileId);
    for R in FileRefs do
    begin
      if R.SymbolId = 0 then Continue;
      if not Fields.TryGetValue(R.SymbolId, Ix) then
      begin
        Ix:= Candidate(St.GetSymbolById(R.SymbolId));
        Fields.Add(R.SymbolId, Ix);
      end;
      if (Ix >= 0) and ((Found[Ix].Line = 0) or (R.StartLine < Found[Ix].Line)) then
      begin
        var Hit: TInheritedInstance:= Found[Ix];
        Hit.Line:= R.StartLine;
        Found[Ix]:= Hit;
      end;
    end;
    CollectUnbound(FileRefs);
    Found.Sort(TComparer<TInheritedInstance>.Construct(
      function(const ALeft, ARight: TInheritedInstance): Integer
      begin
        Result:= ALeft.Line - ARight.Line;
      end));
    Result:= Found.ToArray;
  finally
    DfmTexts.Free;
    Found.Free;
    Fields.Free;
    AncIds.Free;
    OwnIds.Free;
  end;
end;


// The class of ADfmText's root block -- its first object / inherited / inline
// header -- or '' when the first non-blank line is no such header.
function DfmRootClass(const ADfmText: string): string;
var
  L, T, ObjName: string;
begin
  Result:= '';
  for L in ADfmText.Replace(#13#10, #10).Replace(#13, #10).Split([#10]) do
  begin
    T:= Trim(L);
    if StartsStr(UTF8_BOM_AS_ANSI, T) then T:= Trim(Copy(T, Length(UTF8_BOM_AS_ANSI) + 1, MaxInt));
    if T = '' then Continue;
    if not (TryParseHeaderAfter(T, KW_OBJECT + ' ', ObjName, Result) or
            TryParseHeaderAfter(T, KW_INHERITED + ' ', ObjName, Result) or
            TryParseHeaderAfter(T, KW_INLINE + ' ', ObjName, Result)) then Result:= '';
    Exit;
  end;
end;

// 1-based line of ADfmText's `object AName: ...` header, or 0.
function DfmObjectLine(const ADfmText, AName: string): Integer;
var
  Lines        : TArray<string>;
  I            : Integer;
  ObjName, Cls : string;
begin
  Lines:= ADfmText.Replace(#13#10, #10).Replace(#13, #10).Split([#10]);
  for I:= 0 to High(Lines) do
    if TryParseHeaderAfter(Trim(Lines[I]), KW_OBJECT + ' ', ObjName, Cls) and SameText(ObjName, AName) then
      Exit(I + 1);
  Result:= 0;
end;

function FindDescendantUses(const ATrees: TConvertTreeCache; const AUnitPas, ADfmPath: string;
  const ARules: TConversionRuleSet; const AConverted: TArray<TConvertInstance>): TArray<TDescendantUse>;
type
  TDescClass = record
    Store  : Integer;  { index into ATrees.Stores }
    Sym    : TSymbol;
    PasPath: string;
  end;
  { one descendant's first code use of one converted name }
  TCodeHit = record
    Desc: Integer;     { index into Descs }
    Line: Integer;
  end;
var
  DfmText, Root: string;
  Descs     : TList<TDescClass>;
  OwnerIds  : TDictionary<string, Boolean>;   { '<store>:<id>' of the root class and every descendant }
  Names     : TDictionary<string, Boolean>;   { upper converted instance names }
  FieldIds  : TDictionary<string, Int64>;     { '<store>:<UPPER NAME>' -> the field AUnitPas declares }
  CodeHits  : TObjectDictionary<string, TList<TCodeHit>>; { UPPER NAME -> per-descendant first use }
  OwnerSeen : TDictionary<string, Boolean>;   { '<store>:<UPPER OWNER>:<UPPER .pas>' -> owner is ours }
  Scans     : TDictionary<string, TArray<TInheritedInstance>>; { upper .dfm path -> its blocks }
  Found     : TList<TDescendantUse>;
  All       : TList<TDescendantUse>;          { every instance's entries, in order }
  ByUnit    : TDictionary<string, Integer>;   { upper .pas path -> index into Found, per instance }
  Inst      : TConvertInstance;
  AncLine   : Integer;

  function IdKey(AStore: Integer; AId: Int64): string;
  begin
    Result:= IntToStr(AStore) + ':' + IntToStr(AId);
  end;

  { True when ASymId's transitive ancestors include Root declared in AUnitPas }
  function DescendsFromRoot(AStore: Integer; ASymId: Int64): Boolean;
  var
    A: TTypeAncestor;
  begin
    for A in ATrees.Stores[AStore].GetTransitiveAncestors(ASymId) do
      if A.Resolved and SameText(A.Name, Root) and SamePath(ATrees.Stores[AStore].GetFilePath(A.FileId), AUnitPas) then
        Exit(True);
    Result:= False;
  end;

  { the root class, its descendants, and the fields AUnitPas declares under a converted name -- once per store }
  procedure CollectClassesAndFields;
  var
    StIx : Integer;
    DName: string;
    S    : TSymbol;
    D    : TDescClass;
  begin
    for StIx:= 0 to High(ATrees.Stores) do
    begin
      for S in ATrees.Stores[StIx].FindSymbolsByFile(AUnitPas) do
        if (S.Kind = skClass) and SameText(S.Name, Root) then OwnerIds.AddOrSetValue(IdKey(StIx, S.Id), True)
        else if (S.Kind = skField) and Names.ContainsKey(UpperCase(S.Name)) then
          FieldIds.AddOrSetValue(IntToStr(StIx) + ':' + UpperCase(S.Name), S.Id);
      for DName in ATrees.Stores[StIx].FindDescendantNames(Root) do
        for S in ATrees.Stores[StIx].FindSymbolsByExactName(DName) do
          if (S.Kind = skClass) and not OwnerIds.ContainsKey(IdKey(StIx, S.Id)) and DescendsFromRoot(StIx, S.Id) then
          begin
            D.Store  := StIx;
            D.Sym    := S;
            D.PasPath:= ATrees.Stores[StIx].GetFilePath(S.FileId);
            OwnerIds.Add(IdKey(StIx, S.Id), True);
            Descs.Add(D);
          end;
    end;
  end;

  { True when the class named AOwner that ACandPas sees -- declared in it, or
    in a unit it uses, or the only class of that name -- is the root class or
    a descendant. Cached per (store, owner, candidate). }
  function OwnerIsOurs(AStore: Integer; const AOwner, ACandPas: string): Boolean;
  var
    Key     : string;
    Cands   : TList<TSymbol>;
    CandFile: Int64;
    UsesSet : TDictionary<string, Boolean>;
    Pick    : TSymbol;
    Picked  : Integer;
  begin
    Key:= IntToStr(AStore) + ':' + UpperCase(AOwner) + ':' + UpperCase(ACandPas);
    if OwnerSeen.TryGetValue(Key, Result) then Exit;
    Result:= False;
    Cands  := TList<TSymbol>.Create;
    UsesSet:= TDictionary<string, Boolean>.Create;
    try
      for var S: TSymbol in ATrees.Stores[AStore].FindSymbolsByExactName(AOwner) do
        if S.Kind = skClass then Cands.Add(S);
      Pick  := Default(TSymbol);
      Picked:= 0;
      if Cands.Count = 1 then
      begin
        Pick  := Cands[0];
        Picked:= 1;
      end
      else if Cands.Count > 1 then
      begin
        CandFile:= ATrees.Stores[AStore].FindFileIdByPath(ACandPas);
        for var U: TUnitUse in ATrees.Stores[AStore].GetUnitUsesForFile(CandFile) do
          UsesSet.AddOrSetValue(UpperCase(U.UnitName), True);
        for var S: TSymbol in Cands do
          if S.FileId = CandFile then
          begin
            Pick  := S;
            Picked:= 1;
            Break;
          end
          else if UsesSet.ContainsKey(UpperCase(TPath.GetFileNameWithoutExtension(ATrees.Stores[AStore].GetFilePath(S.FileId)))) then
          begin
            Pick:= S;
            Inc(Picked);
          end;
      end;
      Result:= (Picked = 1) and OwnerIds.ContainsKey(IdKey(AStore, Pick.Id));
    finally
      UsesSet.Free;
      Cands.Free;
    end;
    OwnerSeen.Add(Key, Result);
  end;

  { the inherited / inline From-type blocks of one candidate .dfm, scanned once }
  function ScanOf(const ADfm: string): TArray<TInheritedInstance>;
  var
    Bytes: TBytes;
  begin
    if Scans.TryGetValue(UpperCase(ADfm), Result) then Exit;
    Result:= nil;
    if TFile.Exists(ADfm) then
    try
      Bytes:= TFile.ReadAllBytes(ADfm);
      if not IsBinaryDfmBytes(Bytes) then
        Result:= ScanInheritedConvertInstances(DecodeUnitBytes(Bytes), ARules);
    except
      on EInOutError do Result:= nil;     { unreadable: it cannot be listed }
      on EFileStreamError do Result:= nil;
    end;
    Scans.Add(UpperCase(ADfm), Result);
  end;

  { the Found index of AUnitPas's entry for Inst, created on first use }
  function EntryFor(const AUnitPas2: string): Integer;
  var
    U: TDescendantUse;
  begin
    if ByUnit.TryGetValue(UpperCase(AUnitPas2), Result) then Exit;
    U             := Default(TDescendantUse);
    U.UnitName    := TPath.GetFileNameWithoutExtension(AUnitPas2);
    U.Name        := Inst.InstanceName;
    U.TypeName    := Inst.FromType;
    U.AncestorLine:= AncLine;
    Result:= Found.Add(U);
    ByUnit.Add(UpperCase(AUnitPas2), Result);
  end;

  procedure AddDfmUses;
  var
    StIx: Integer;
    S   : TSymbol;
    Dfm : string;
    Seen: TDictionary<string, Boolean>;
    U   : TDescendantUse;
    Ix  : Integer;
  begin
    Seen:= TDictionary<string, Boolean>.Create;
    try
      for StIx:= 0 to High(ATrees.Stores) do
        for S in ATrees.Stores[StIx].FindSymbolsByExactName(Inst.InstanceName) do
        begin
          if S.Kind <> skComponent then Continue;
          Dfm:= ATrees.Stores[StIx].GetFilePath(S.FileId);
          if not SameText(ExtractFileExt(Dfm), DFM_EXT) or SamePath(Dfm, ADfmPath) or Seen.ContainsKey(UpperCase(Dfm)) then Continue;
          Seen.Add(UpperCase(Dfm), True);
          for var Blk: TInheritedInstance in ScanOf(Dfm) do
            if SameText(Blk.Name, Inst.InstanceName) and SameText(Blk.TypeName, Inst.FromType) and
               OwnerIsOurs(StIx, Blk.OwnerClass, TPath.ChangeExtension(Dfm, PAS_EXT)) then
            begin
              Ix:= EntryFor(TPath.ChangeExtension(Dfm, PAS_EXT));
              U := Found[Ix];
              if U.Reason = '' then
              begin
                U.Reason:= DESC_REASON_DFM;
                U.Line  := Blk.Line;
                Found[Ix]:= U;
              end;
              Break;
            end;
        end;
    finally
      Seen.Free;
    end;
  end;

  { the class a routine belongs to, walking nested routines up; 0 when none,
    or when a routine on the way declares a local / param named AName -- an
    unresolved AName there is that local, not the ancestor's field }
  function UnshadowedClassId(AStore: Integer; ARoutineId: Int64; const AName: string): Int64;
  var
    S   : TSymbol;
    Hops: Integer;
  begin
    S:= ATrees.Stores[AStore].GetSymbolById(ARoutineId);
    for Hops:= 1 to ENCLOSING_CLASS_HOPS do
    begin
      if S.Id = 0 then Break;
      if S.Kind = skClass then Exit(S.Id);
      if ATrees.Stores[AStore].FindChildSymbolByName(S.Id, AName).Id <> 0 then Break;
      S:= ATrees.Stores[AStore].GetSymbolById(S.ParentId);
    end;
    Result:= 0;
  end;

  { every descendant's code uses of every converted name: each descendant
    file's references read ONCE }
  procedure CollectCodeUses;
  var
    DIx    : Integer;
    D      : TDescClass;
    R      : TReference;
    Up     : string;
    FieldId: Int64;
    Hits   : TList<TCodeHit>;
    Hit    : TCodeHit;
    Done   : Boolean;
    Refs   : TDictionary<string, TArray<TReference>>; { '<store>:<file id>' -> its refs }
    FileRefs: TArray<TReference>;
  begin
    Refs:= TDictionary<string, TArray<TReference>>.Create;
    try
      for DIx:= 0 to Descs.Count - 1 do
      begin
        D:= Descs[DIx];
        if not Refs.TryGetValue(IdKey(D.Store, D.Sym.FileId), FileRefs) then
        begin
          FileRefs:= ATrees.Stores[D.Store].GetReferencesFromFile(D.Sym.FileId);
          Refs.Add(IdKey(D.Store, D.Sym.FileId), FileRefs);
        end;
        for R in FileRefs do
        begin
          Up:= UpperCase(R.NameText);
          if not Names.ContainsKey(Up) or (R.EnclosingSymbolId = 0) then Continue;
          if not FieldIds.TryGetValue(IntToStr(D.Store) + ':' + Up, FieldId) then FieldId:= 0;
          if not (((FieldId <> 0) and (R.SymbolId = FieldId)) or
                  ((R.SymbolId = 0) and ((R.ReceiverText = '') or SameText(R.ReceiverText, SELF_RECEIVER)))) then Continue;
          if UnshadowedClassId(D.Store, R.EnclosingSymbolId, R.NameText) <> D.Sym.Id then Continue;
          if not CodeHits.TryGetValue(Up, Hits) then
          begin
            Hits:= TList<TCodeHit>.Create;
            CodeHits.Add(Up, Hits);
          end;
          Done:= False;
          for var K: Integer:= 0 to Hits.Count - 1 do
            if Hits[K].Desc = DIx then
            begin
              Hit:= Hits[K];
              if R.StartLine < Hit.Line then Hit.Line:= R.StartLine;
              Hits[K]:= Hit;
              Done:= True;
              Break;
            end;
          if not Done then
          begin
            Hit.Desc:= DIx;
            Hit.Line:= R.StartLine;
            Hits.Add(Hit);
          end;
        end;
      end;
    finally
      Refs.Free;
    end;
  end;

  procedure AddCodeUses;
  var
    Hits: TList<TCodeHit>;
    Ix  : Integer;
    U   : TDescendantUse;
  begin
    if not CodeHits.TryGetValue(UpperCase(Inst.InstanceName), Hits) then Exit;
    for var Hit: TCodeHit in Hits do
    begin
      Ix:= EntryFor(Descs[Hit.Desc].PasPath);
      U := Found[Ix];
      if U.Reason = DESC_REASON_DFM then U.Reason:= DESC_REASON_BOTH
      else if U.Reason = '' then
      begin
        U.Reason:= DESC_REASON_CODE;
        U.Line  := Hit.Line;
      end
      else if (U.Reason = DESC_REASON_CODE) and (Hit.Line < U.Line) then U.Line:= Hit.Line;
      Found[Ix]:= U;
    end;
  end;

begin
  Result:= nil;
  if (Length(AConverted) = 0) or (ADfmPath = '') or not TFile.Exists(ADfmPath) then Exit;
  DfmText:= ReadUnitText(ADfmPath);
  Root   := DfmRootClass(DfmText);
  if Root = '' then Exit;
  Descs    := TList<TDescClass>.Create;
  OwnerIds := TDictionary<string, Boolean>.Create;
  Names    := TDictionary<string, Boolean>.Create;
  FieldIds := TDictionary<string, Int64>.Create;
  CodeHits := TObjectDictionary<string, TList<TCodeHit>>.Create([doOwnsValues]);
  OwnerSeen:= TDictionary<string, Boolean>.Create;
  Scans    := TDictionary<string, TArray<TInheritedInstance>>.Create;
  Found    := TList<TDescendantUse>.Create;
  All      := TList<TDescendantUse>.Create;
  ByUnit   := TDictionary<string, Integer>.Create;
  try
    for Inst in AConverted do Names.AddOrSetValue(UpperCase(Inst.InstanceName), True);
    CollectClassesAndFields;
    CollectCodeUses;
    for Inst in AConverted do
    begin
      AncLine:= DfmObjectLine(DfmText, Inst.InstanceName);
      Found.Clear;
      ByUnit.Clear;
      AddDfmUses;
      AddCodeUses;
      Found.Sort(TComparer<TDescendantUse>.Construct(
        function(const ALeft, ARight: TDescendantUse): Integer
        begin
          Result:= CompareText(ALeft.UnitName, ARight.UnitName);
        end));
      All.AddRange(Found);
    end;
    Result:= All.ToArray;
  finally
    ByUnit.Free;
    All.Free;
    Found.Free;
    Scans.Free;
    OwnerSeen.Free;
    CodeHits.Free;
    FieldIds.Free;
    Names.Free;
    OwnerIds.Free;
    Descs.Free;
  end;
end;

function ConvertedInstancesOf(const AReport: TApplyReport; const ADfmPath: string;
  const ARules: TConversionRuleSet; const AOnly: TArray<string>): TArray<TConvertInstance>;
var
  Skipped: Boolean;
begin
  Result:= nil;
  if (ADfmPath = '') or not TFile.Exists(ADfmPath) then Exit;
  var DfmText: string:= ReadUnitText(ADfmPath);
  var All: TArray<TConvertInstance>:= FindConvertInstances(DfmText, ARules, AOnly);
  for var NO: TNestedOnly in NestedOnlyInstances(DfmText, ARules, AOnly) do All:= All + [NO.Instance];
  for var Inst: TConvertInstance in All do
  begin
    Skipped:= False;
    for var It: TApplyItem in AReport.Items do
      if (It.Kind = aikInstanceSkipped) and SameText(It.Instance, Inst.InstanceName) then Skipped:= True;
    if not Skipped then Result:= Result + [Inst];
  end;
end;

procedure AppendDescendantReport(const AUses: TArray<TDescendantUse>; const ADfmPath: string;
  var AReport: TApplyReport);
var
  U : TDescendantUse;
  It: TApplyItem;
begin
  for U in AUses do
  begin
    It         := Default(TApplyItem);
    It.Kind    := aikDescendantNotConverted;
    It.Field   := afWarnings;
    It.Instance:= U.Name;
    It.FromType:= U.TypeName;
    It.FilePath:= ADfmPath;
    It.Line    := U.AncestorLine;
    It.Text    := Format('line %d: warning: descendant %s still streams %s as %s -- convert it next (needs C8 N2)',
                    [U.AncestorLine, U.UnitName, U.Name, U.TypeName]);
    AReport.Warnings:= AReport.Warnings + [It.Text];
    AReport.Items   := AReport.Items + [It];
  end;
end;


// One construction site: 'AFromType.<ctor>(' found as a whole-word AFromType
// token immediately followed (ignoring intervening whitespace) by '.' and a
// constructor-name identifier. Line/Col/EndCol locate the AFromType token
// itself (1-based, EndCol exclusive) for a tekReplaceInLine edit -- mirrors
// TReference.StartLine/StartCol/EndCol, the same span the indexer already
// recorded for this ref (kind='read', name_text=AFromType).
type
  TCreatorSite = record
    Line, Col, EndCol: Integer;
    CtorName: string; // the identifier after '.', e.g. 'Create' -- always one of AKnownCtorNames on a match
  end;

// Enumerates AClassName's own constructor names (skConstructor children, via
// FindAllChildSymbols -- same lookup/filter ToTypeHasGenericCreate uses for
// its Create-shape probe) for the surface #5 construction-shape check below.
// Inherited constructors are NOT walked (no cheap "walk the base-class chain"
// available here without a second symbol resolve per ancestor; the class's
// OWN constructors plus the fallback below cover the near-totality of real
// component/class construction sites this applier will see). When AClassName
// resolves to an indexed skClass with zero indexed skConstructor children (or
// does not resolve to a class at all), FALLS BACK to ['Create'] -- the
// near-universal VCL/RTL constructor name -- rather than accepting an
// unbounded set of identifiers; this is deliberately conservative (a real but
// unusually-named sole constructor on an unindexed/under-indexed type would be
// missed) because the alternative (matching '.' + ANY identifier) is exactly
// the false-positive bug this function exists to prevent (I-1: 'TOldEdit.
// ClassName' / 'TOldEdit.InheritsFrom(x)' misdetected as constructions).
// Bug 2: AClassName may live in a DIFFERENT --db than the unit being
// converted, so every candidate store in AStores is tried in order --
// first store that resolves AClassName to an indexed skClass wins -- and
// FindAllChildSymbols(ClassSym.Id) runs against that SAME store (an id is
// only meaningful within the store that produced it), mirroring TConvertTreeCache.ClassFor's
// own cross-db convention.
function GetConstructorNames(const AStores: TArray<ISymbolStore>; const AClassName: string): TArray<string>;
var
  Cands   : TArray<TSymbol>;
  ClassSym: TSymbol;
  Found   : Boolean;
  Kids    : TArray<TSymbol>;
  K       : TSymbol;
  List    : TList<string>;
  St      : ISymbolStore;
  ResolvedStore: ISymbolStore;
begin
  Found:= False;
  ClassSym:= Default(TSymbol);
  ResolvedStore:= nil;
  for St in AStores do
  begin
    Cands:= St.FindSymbolsByExactName(AClassName);
    for var S in Cands do
      if S.Kind = skClass then begin ClassSym:= S; Found:= True; ResolvedStore:= St; Break; end;
    if Found then Break;
  end;

  Result:= ['Create']; { fallback: applies whenever the loop below adds nothing }
  if not Found then Exit;

  Kids:= ResolvedStore.FindAllChildSymbols(ClassSym.Id);
  List:= TList<string>.Create;
  try
    for K in Kids do
      if K.Kind = skConstructor then List.Add(K.Name);
    if List.Count > 0 then Result:= List.ToArray;
  finally
    List.Free;
  end;
end;

// Given the whole-word span ending at AEndCol of AFromType on 1-based line
// ALine of APasLines, checks whether it is immediately (modulo whitespace)
// followed by '.' + an identifier that NAMES ONE OF AKnownCtorNames
// (case-insensitively) -- i.e. a real construction 'AFromType.Create(' rather
// than a plain type reference OR a class-static reference like 'AFromType.
// ClassName' / 'AFromType.InheritsFrom(x)' (I-1 fix: matching '.' + ANY
// identifier misdetected those class-static reads as constructions). Returns
// True + the constructor identifier on a match.
function TryMatchConstructionShape(const APasLines: TStringList; ALine, AEndCol: Integer;
  const AKnownCtorNames: TArray<string>; out ACtorName: string): Boolean;
var
  S: string;
  P: Integer;
  NameStart: Integer;
  Name: string;
  IsKnownCtor: Boolean;
begin
  ACtorName:= '';
  if (ALine < 1) or (ALine > APasLines.Count) then Exit(False);
  S:= APasLines[ALine - 1];
  P:= AEndCol;
  while (P <= Length(S)) and (S[P] = ' ') do Inc(P);
  if (P > Length(S)) or (S[P] <> '.') then Exit(False);
  Inc(P);
  while (P <= Length(S)) and (S[P] = ' ') do Inc(P);
  NameStart:= P;
  while (P <= Length(S)) and CharInSet(S[P], ['A'..'Z', 'a'..'z', '0'..'9', '_']) do Inc(P);
  if P = NameStart then Exit(False); { '.' not followed by an identifier }
  Name:= Copy(S, NameStart, P - NameStart);

  IsKnownCtor:= False;
  for var Ctor in AKnownCtorNames do
    if SameText(Name, Ctor) then begin IsKnownCtor:= True; Break; end;
  if not IsKnownCtor then Exit(False); { e.g. '.ClassName' / '.InheritsFrom' -- not a constructor }

  ACtorName:= Name;
  Result:= True;
end;

// Finds every runtime-construction site of AFromType ('AFromType.Xxx(...)',
// e.g. 'TOldEdit.Create(Self)') in AUnitPas, via the store's own reference
// index rather than a fresh text scan: a construction site is recorded by the
// indexer as a 'read' ref whose NameText is the bare class name, at the
// type-name token position (see docs/superpowers/specs/2026-07-09-refgap-e-
// type-references-design.md: "construction sites (TMyclass.Create) ->
// kind='read'"). GetReferencesFromFile gives StartLine/StartCol/EndCol for
// each candidate 'read' ref directly -- no separate token-column search is
// needed (contrast LocateFieldTypeToken, which DOES need one because the field
// symbol's span covers the whole declaration line, not just the type token).
// A 'read' ref is confirmed as a CONSTRUCTION (vs. a plain type reference,
// e.g. a type-test 'X is TOldEdit', or a class-static reference like 'X is
// TOldEdit.ClassName') by TryMatchConstructionShape: the token immediately
// after AFromType (modulo whitespace) must be '.' + an identifier that names
// one of AFromType's own indexed constructors (or 'Create', if AFromType has
// none indexed) -- see GetConstructorNames.
// AStores (Bug 2, cross-db): resolves AFromType's own constructor names, which
// may live in a different --db than AUnitStore. AUnitStore (single, unit-
// scoped): the store that actually has AFileId indexed -- GetReferencesFromFile
// is an id-scoped lookup, so it must go to the SAME store that produced AFileId.
function FindConstructionSites(const AStores: TArray<ISymbolStore>; const AUnitStore: ISymbolStore;
  AFileId: Int64; const APasLines: TStringList; const AFromType: string): TArray<TCreatorSite>;
var
  Refs: TArray<TReference>;
  R   : TReference;
  List: TList<TCreatorSite>;
  Site: TCreatorSite;
  Ctor: string;
  KnownCtorNames: TArray<string>;
begin
  Result:= nil;
  if AFileId <= 0 then Exit;
  KnownCtorNames:= GetConstructorNames(AStores, AFromType);
  Refs:= AUnitStore.GetReferencesFromFile(AFileId);
  List:= TList<TCreatorSite>.Create;
  try
    for R in Refs do
    begin
      if not SameText(R.Kind, 'read') then Continue;
      if not SameText(R.NameText, AFromType) then Continue;
      if not TryMatchConstructionShape(APasLines, R.StartLine, R.EndCol, KnownCtorNames, Ctor) then Continue;
      Site:= Default(TCreatorSite);
      Site.Line    := R.StartLine;
      Site.Col     := R.StartCol;
      Site.EndCol  := R.EndCol;
      Site.CtorName:= Ctor;
      List.Add(Site);
    end;
    Result:= List.ToArray;
  finally
    List.Free;
  end;
end;

// True when AToType has at least one indexed skConstructor child whose
// Signature looks like the generic VCL component shape 'Create(AOwner:
// TComponent)' (parameter-list text loosely matched -- 'TComponent' anywhere
// in the signature is enough; exact formatting varies). Used only to enrich
// the TODO marker/ReemitNotes with a hint of whether a same-shape constructor
// exists; per the brief, the rewrite + TODO marker happen regardless of this
// result -- args are NEVER auto-fixed, so a False here does not block anything.
// Bug 2: AToType may live in a DIFFERENT --db than the unit being converted,
// so every candidate store in AStores is tried in order (first-resolve-wins),
// same convention as GetConstructorNames/TConvertTreeCache.ClassFor.
function ToTypeHasGenericCreate(const AStores: TArray<ISymbolStore>; const AToType: string): Boolean;
var
  Cands   : TArray<TSymbol>;
  ClassSym: TSymbol;
  Found   : Boolean;
  Kids    : TArray<TSymbol>;
  K       : TSymbol;
  St      : ISymbolStore;
  ResolvedStore: ISymbolStore;
begin
  Result:= False;
  Found:= False;
  ClassSym:= Default(TSymbol);
  ResolvedStore:= nil;
  for St in AStores do
  begin
    Cands:= St.FindSymbolsByExactName(AToType);
    for var S in Cands do
      if S.Kind = skClass then begin ClassSym:= S; Found:= True; ResolvedStore:= St; Break; end;
    if Found then Break;
  end;
  if not Found then Exit;

  Kids:= ResolvedStore.FindAllChildSymbols(ClassSym.Id);
  for K in Kids do
    if (K.Kind = skConstructor) and SameText(K.Name, 'Create') and
       (Pos('TComponent', K.Signature) > 0) then Exit(True);
end;

// Checks one class name's freshness across every candidate store, in order --
// FIRST STORE THAT RESOLVES AClassName TO AN INDEXED skClass WINS, mirroring
// the cross-db convention TConvertTreeCache.ClassFor (DoConvertApply,
// BuildApplyPlan) already uses (Bug 2 fix: the From/To type may live in a DIFFERENT --db than
// the form's own instances, so a single store can't always resolve both).
// Once a store resolves the class (via FindSymbolsByExactName, same lookup
// ResolveClassQName uses), ALL of the remaining freshness work -- GetFilePath,
// FileIsUpToDate -- runs against that SAME store (an id/path pair is only
// meaningful within the store that produced it); other stores are not
// consulted further for this class. Appends a human-readable reason to
// AReasons and returns False on either failure mode: unresolved in ANY store
// (not indexed at all) or resolved-but-stale in the store that resolved it.
// True when APath's on-disk (mtime, sha) is exactly what AStore recorded.
// Sha/Mtime basis mirrors DRagLint.Core.Indexer.IndexFile exactly (raw bytes,
// ANSI-decoded for the sha) so this check compares apples to apples against
// what FileIsUpToDate was given when the file was last indexed.
function FileStampIsCurrent(const AStore: ISymbolStore; const APath: string): Boolean;
var
  RawBytes : TBytes;
  Sha      : string;
  MtimeUnix: Int64;
begin
  RawBytes := TFile.ReadAllBytes(APath);
  Sha      := THashSHA2.GetHashString(TEncoding.ANSI.GetString(RawBytes));
  MtimeUnix:= DateTimeToUnix(TFile.GetLastWriteTime(APath), False);
  Result   := AStore.FileIsUpToDate(APath, MtimeUnix, Sha);
end;

function CheckTypeFreshness(const AStores: TArray<ISymbolStore>; const AClassName: string;
  AReasons: TList<string>): Boolean;
var
  Cands  : TArray<TSymbol>;
  S      : TSymbol;
  Found  : Boolean;
  ClassSym: TSymbol;
  FilePath: string;
  St     : ISymbolStore;
  ResolvedStore: ISymbolStore;
begin
  Found:= False;
  ClassSym:= Default(TSymbol);
  ResolvedStore:= nil;
  for St in AStores do
  begin
    Cands:= St.FindSymbolsByExactName(AClassName);
    for S in Cands do
      if S.Kind = skClass then begin ClassSym:= S; Found:= True; ResolvedStore:= St; Break; end;
    if Found then Break;
  end;

  if not Found then
  begin
    AReasons.Add(Format('%s: not indexed (no skClass symbol found) -- reindex the unit declaring this type', [AClassName]));
    Exit(False);
  end;

  FilePath:= ResolvedStore.GetFilePath(ClassSym.FileId);
  if (FilePath = '') or (not TFile.Exists(FilePath)) then
  begin
    AReasons.Add(Format('%s: indexed declaring file not found on disk (%s) -- reindex', [AClassName, FilePath]));
    Exit(False);
  end;

  if not FileStampIsCurrent(ResolvedStore, FilePath) then
  begin
    AReasons.Add(Format('%s: index is stale for %s (file changed on disk since last index) -- reindex before converting', [AClassName, FilePath]));
    Exit(False);
  end;

  Result:= True;
end;

function CheckFreshness(const AStores: TArray<ISymbolStore>; const ARules: TConversionRuleSet): TFreshnessResult;
var
  R       : TConversionRule;
  Reasons : TList<string>;
  Seen    : TList<string>;

  // BareTypeTail: a rule's #convert header may name either type qualified
  // ('LibA.TSrcBtn') -- FindSymbolsByExactName (inside CheckTypeFreshness)
  // matches the bare name column only, same as every other lookup in this
  // unit (see BareTypeTail's own remarks, Bug 1). Each type is checked ONCE,
  // however many blocks name it, so a stale unit is reported once.
  // False only when AType is checked here AND found stale or unindexed.
  function CheckOnce(const AType: string): Boolean;
  var
    Bare: string;
  begin
    Bare:= BareTypeTail(AType);
    if (Bare = '') or Seen.Contains(UpperCase(Bare)) then Exit(True);
    Seen.Add(UpperCase(Bare));
    Result:= CheckTypeFreshness(AStores, Bare, Reasons);
  end;

begin
  Result:= Default(TFreshnessResult);
  Result.Fresh:= True; { no #convert rule at all -> nothing to check, vacuously fresh }

  Reasons:= TList<string>.Create;
  Seen   := TList<string>.Create;
  try
    for R in ARules.Rules do
      if R.Kind = rkConvert then
      begin
        if not CheckOnce(R.FromType) then Result.Fresh:= False;
        if not CheckOnce(R.ToType)   then Result.Fresh:= False;
      end;
    Result.Reasons:= Reasons.ToArray;
  finally
    Seen.Free;
    Reasons.Free;
  end;
end;

function CheckUnitFreshness(const AStores: TArray<ISymbolStore>; const AUnitPas, ADfmPath: string): TFreshnessResult;
begin
  Result:= Default(TFreshnessResult);
  Result.Fresh:= True;
  for var Given: string in [AUnitPas, ADfmPath] do
  begin
    if (Given = '') or not TFile.Exists(Given) then Continue;
    var P: string:= TPath.GetFullPath(Given); { a relative --unit still matches the stored full path }
    for var St: ISymbolStore in AStores do
      if St.FindFileIdByPath(P) > 0 then
      begin
        if not FileStampIsCurrent(St, P) then
        begin
          Result.Fresh  := False;
          Result.Reasons:= Result.Reasons + [Format('index is stale for %s (changed on disk since it was indexed) -- reindex', [P])];
        end;
        Break;
      end;
  end;
end;

// Locates AInstanceName's DFM object-block symbol (skForm for the DFM's root
// object, skComponent for every nested one -- see DRagLint.Parser.DFM.
// WalkObject) among ADfmFileSyms, matching both Name and Signature (the DFM
// class, e.g. 'TOldEdit') so a name collision with a differently-typed
// instance is not mismatched. StartLine/EndLine on the returned symbol are the
// tree-sitter 'object' node's full span (header through its matching 'end',
// nesting already resolved by the grammar) -- exactly the line range to slice
// out of the .dfm text. Id=0 when not found.
function FindDfmInstanceSymbol(const ADfmFileSyms: TArray<TSymbol>;
  const AInstanceName, AFromType: string): TSymbol;
var
  S: TSymbol;
begin
  Result:= Default(TSymbol);
  for S in ADfmFileSyms do
    if (S.Kind in [skForm, skComponent]) and SameText(S.Name, AInstanceName) and
       SameText(S.Signature, AFromType) then Exit(S);
end;

// Leading-whitespace run of ALine, e.g. '  object Edit1: TOldEdit' -> '  '.
// Used to re-apply the original block's indentation to the re-emitted T text,
// which EmitBlock always renders starting at column 1 (AIndent=0).
function LeadingIndent(const ALine: string): string;
var
  i: Integer;
begin
  i:= 1;
  while (i <= Length(ALine)) and CharInSet(ALine[i], [' ', #9]) do Inc(i);
  Result:= Copy(ALine, 1, i - 1);
end;

/// <summary>Reports whether the .dfm lines [AStart..AEnd] (1-based, inclusive) still hold the
/// object block of the named instance.</summary>
/// <param name="ADfmLines">The .dfm as it is on disk now, one entry per line.</param>
/// <param name="AStart">First line of the span, as the index recorded it.</param>
/// <param name="AEnd">Last line of the span, as the index recorded it.</param>
/// <param name="AInstanceName">Name of the instance the span must open with.</param>
/// <returns>True when line AStart opens `object`, `inherited` or `inline` followed by
/// AInstanceName and a colon, and the FIRST `end` after it at the opener's indentation is
/// on line AEnd. False when the .dfm changed after indexing, so the recorded span no
/// longer holds it -- including a block that shrank, whose recorded AEnd now lands on a
/// later sibling's `end` at the same indentation.</returns>
/// <remarks>Both lines must be in range. The check is deliberately shallow: it finds the
/// block's own closing line by indentation (nested blocks are indented deeper) without
/// re-parsing the block.</remarks>
function DfmSpanHoldsInstance(const ADfmLines: TArray<string>; AStart, AEnd: Integer;
  const AInstanceName: string): Boolean;
const
  Openers: array[0..2] of string = ('object ', 'inherited ', 'inline ');
var
  First, Opener, Rest, Indent: string;
  CloseLine: Integer;
begin
  Result:= False;
  First:= ADfmLines[AStart - 1].TrimLeft;
  for Opener in Openers do
    if First.StartsWith(Opener, True) then
    begin
      Rest:= First.Substring(Length(Opener)).TrimLeft;
      Result:= Rest.StartsWith(AInstanceName, True) and
               Rest.Substring(Length(AInstanceName)).TrimLeft.StartsWith(':');
      Break;
    end;
  if not Result then Exit;
  { the block's own end is the first `end` at the opener's indent after it }
  Indent:= LeadingIndent(ADfmLines[AStart - 1]);
  CloseLine:= AStart + 1;
  while (CloseLine <= AEnd) and not (SameText(ADfmLines[CloseLine - 1].Trim, 'end') and
                                     (LeadingIndent(ADfmLines[CloseLine - 1]) = Indent)) do
    Inc(CloseLine);
  Result:= CloseLine = AEnd;
end;

// The unit declaring the class ATypeName resolves to in ATrees -- its indexed
// declaring file's base name ('FireDAC.Comp.Client'), never a guess from the
// qualified name (a nested type's prefix is not a unit) -- or '' when no store
// has the class.
function DeclaringUnitOf(const ATrees: TConvertTreeCache; const ATypeName: string): string;
var
  QName: string;
  St   : ISymbolStore;
  S    : TSymbol;
begin
  Result:= '';
  QName := ATrees.ResolveType(ATypeName);
  if QName = '' then Exit;
  for St in ATrees.Stores do
    for S in St.FindSymbolsByExactName(BareTypeTail(QName)) do
      if (S.Kind = skClass) and SameText(S.QualifiedName, QName) then
        Exit(TPath.GetFileNameWithoutExtension(St.GetFilePath(S.FileId)));
end;

procedure SplitOnlyNames(const ADfmText: string; const ARules: TConversionRuleSet;
  const AOnly: TArray<string>; out AMatched, AUnmatched: TArray<string>);
var
  Names: TArray<string>;
  N    : string;
begin
  AMatched  := nil;
  AUnmatched:= nil;
  if Length(AOnly) = 0 then Exit;
  Names:= nil;
  if ADfmText <> '' then
  begin
    for var Inst: TConvertInstance in FindConvertInstances(ADfmText, ARules, nil) do Names:= Names + [Inst.InstanceName];
    for var Inh: TInheritedInstance in ScanInheritedConvertInstances(ADfmText, ARules) do Names:= Names + [Inh.Name];
  end;
  for N in AOnly do
    if MatchText(N, Names) then AMatched:= AMatched + [N] else AUnmatched:= AUnmatched + [N];
end;

// R26 (1.20.6): the refusal reason when a planned unit-rule REMOVAL (#unuse,
// or #useswap's Old) takes away the unit declaring the From type of a .dfm
// instance that stays unconverted -- skipped, or left out by --only -- which
// would break the compile (E2003); '' when no removal does. Every #convert
// instance of ADfmText counts, inherited / inline ones too (C8 N1: they are
// left unless retyped, N2); AConverted names the ones the plan converts. The text is
// '<rule> would leave <N> unconverted instance(s) of <Type> -- unit not
// changed', <rule> as TUsesChange.Rule spells it.
// C13 N4 (1.23.0): when AOnly is given and EVERY instance a removal would
// strand is an own instance --only left out, the removal is not refused but
// SKIPPED -- returned in ASkips as an Action 'skipped' row (Reason 'would
// leave <N> unconverted instance(s) of <Type>') for the caller to keep the
// unit and report it. A stranded instance left for any other reason (a failed
// re-emit, an inherited / inline object, or no --only at all) keeps R26's
// refusal.
function RemovalLeavesUnconverted(const ATrees: TConvertTreeCache; const ADfmText: string;
  const ARules: TConversionRuleSet; const AConverted: TList<string>; const AOnly: TArray<string>;
  const AChanges: TArray<TUsesChange>; out ASkips: TArray<TUsesChange>): string;
var
  Left : TDictionary<string, Integer>; { From type as the .dfm spells it -> unconverted count }
  Excl : TDictionary<string, Integer>; { the same, counting only own instances --only left out }
  Order: TList<string>;                { the same types, in .dfm order, so the reason is stable }
  Inst : TConvertInstance;
  Ch   : TUsesChange;
  Key  : string;
  Count: Integer;

  procedure Bump(ADict: TDictionary<string, Integer>; const AType: string);
  var
    N: Integer;
  begin
    if not ADict.TryGetValue(AType, N) then N:= 0;
    ADict.AddOrSetValue(AType, N + 1);
  end;

begin
  Result:= '';
  ASkips:= nil;
  Left  := TDictionary<string, Integer>.Create;
  Excl  := TDictionary<string, Integer>.Create;
  Order := TList<string>.Create;
  try
    for Inst in FindConvertInstances(ADfmText, ARules, nil) do
    begin
      if Assigned(AConverted) and AConverted.Contains(Inst.InstanceName) then Continue;
      if not Left.ContainsKey(Inst.FromType) then Order.Add(Inst.FromType);
      Bump(Left, Inst.FromType);
      if (Length(AOnly) > 0) and not InOnlyList(Inst.InstanceName, AOnly) then Bump(Excl, Inst.FromType);
    end;
    { C8 N1: an inherited / inline instance the plan does not retype (N2,
      1.26.0) counts as left unconverted -- and never as left out by --only }
    for var Inh: TInheritedInstance in ScanInheritedConvertInstances(ADfmText, ARules) do
    begin
      if Assigned(AConverted) and AConverted.Contains(Inh.Name) then Continue;
      if not Left.ContainsKey(Inh.TypeName) then Order.Add(Inh.TypeName);
      Bump(Left, Inh.TypeName);
    end;
    for Ch in AChanges do
    begin
      if Ch.Action <> 'remove' then Continue;
      var Parts: TArray<string>:= nil;
      var AllExcluded: Boolean:= True;
      for Key in Order do
        if SameText(DeclaringUnitOf(ATrees, Key), Ch.UnitName.Replace(' ', '').Replace(#9, '')) then
        begin
          if not Excl.TryGetValue(Key, Count) then Count:= 0;
          if Count < Left[Key] then AllExcluded:= False;
          Parts:= Parts + [Format('%d unconverted instance(s) of %s', [Left[Key], Key])];
        end;
      if Length(Parts) = 0 then Continue;
      var Stranded: string:= String.Join(', ', Parts);
      if not AllExcluded then
        Exit(Format('%s would leave %s -- unit not changed', [Ch.Rule, Stranded]));
      var Skip: TUsesChange:= Ch;
      Skip.Action:= 'skipped';
      Skip.Reason:= 'would leave ' + Stranded;
      ASkips:= ASkips + [Skip];
    end;
  finally
    Order.Free;
    Excl.Free;
    Left.Free;
  end;
end;

// The book line of the #unuse / #useswap that removes AUnit, or 0.
function UnitRuleLine(const ARules: TConversionRuleSet; const AUnit: string): Integer;
begin
  for var R: TConversionRule in ARules.Rules do
    if (R.Kind in [rkUnuse, rkUseSwap]) and SameText(R.UnitName.Replace(' ', ''), AUnit.Replace(' ', '').Replace(#9, '')) then
      Exit(R.LineNo);
  Result:= 0;
end;

// C13 N4: the warnings[] text and items[] mirror for one skipped removal.
function SkippedRuleItem(const ARules: TConversionRuleSet; const AUnitPas: string; const ASkip: TUsesChange): TApplyItem;
begin
  Result         := Default(TApplyItem);
  Result.Kind    := aikUnitRuleSkipped;
  Result.Field   := afWarnings;
  Result.FilePath:= AUnitPas;
  Result.Line    := ASkip.Line;
  Result.RuleLine:= UnitRuleLine(ARules, ASkip.UnitName);
  Result.Text    := Format('line %d: warning: %s skipped -- it %s left out by --only; %s kept in uses',
    [Result.RuleLine, ASkip.Rule, ASkip.Reason, ASkip.UnitName]);
end;

// The units of ASkips, for PlanUnitRules' AExtraAdds: a unit there is never
// removed (ADD wins) and, being present already, never added again.
function SkippedUnits(const ASkips: TArray<TUsesChange>): TArray<string>;
begin
  Result:= nil;
  for var S: TUsesChange in ASkips do Result:= Result + [S.UnitName];
end;

{ C9: what ReconcileUnitUses hands back besides the plan. }
type
  TReconcileOutcome = record
    Plan       : TUsesPlan;
    UsePlanner : Boolean;                 { False: the caller keeps its own (Pending) uses edits }
    Items      : TArray<TApplyItem>;      { warnings to Emit, in order }
    Unresolved : TArray<TUsesUnresolved>;
    Status     : string;                  { 'on' / 'degraded' }
    Dangling   : TArray<TUsesDangling>;   { 1.27.0: uncapped, for pas_uses[] }
  end;

// C9: a uses[] row's NeededBy names, joined for a warning line ('A, B (+N more)'
// is not needed: NeededBy is capped at NEEDED_BY_MAX by the reconciler).
function NeedNames(const ANeeds: TArray<TUsesNeed>): string;
begin
  Result:= '';
  for var N: TUsesNeed in ANeeds do
    Result:= Result + (if Result = '' then '' else ', ') + N.Name;
end;

// C9: the instance name of a 'Name: Class' needed_by entry.
function NeedInstance(const ANeed: TUsesNeed): string;
begin
  Result:= ANeed.Name;
  if Result.Contains(':') then Result:= Trim(Result.Substring(0, Result.IndexOf(':')));
end;

// C9 / C13 N4 compatibility: a kept unit whose EVERY keeping component is an
// own #convert instance --only left out is the 1.23.0 'skipped' row, text and
// all -- RemovalLeavesUnconverted still words it, so the two cannot drift.
procedure DemoteOnlySkips(const ATrees: TConvertTreeCache; const ADfmText: string; const ARules: TConversionRuleSet;
  const AConverted: TList<string>; const AOnly: TArray<string>; const AEntries: TArray<TUsesEntryInfo>;
  var ANeeds: TUsesNeeds);
var
  Own  : TArray<string>;
  Skips: TArray<TUsesChange>;
begin
  if (Length(AOnly) = 0) or (ADfmText = '') then Exit;
  Own:= nil;
  for var Inst: TConvertInstance in FindConvertInstances(ADfmText, ARules, nil) do
    if not InOnlyList(Inst.InstanceName, AOnly) then Own:= Own + [Inst.InstanceName];
  for var I: Integer:= 0 to High(ANeeds.Keeps) do
  begin
    var K: TUsesKeep:= ANeeds.Keeps[I];
    if (K.Reason <> KEEP_REASON_DFM) or (Length(K.Keepers) = 0) then Continue;
    { A7-6: decided on EVERY keeper -- NeededBy is the capped display list, so a
      sixth keeper no --only explains would otherwise be missed }
    var AllOnly: Boolean:= True;
    for var N: TUsesNeed in K.Keepers do
      if not MatchText(NeedInstance(N), Own) then AllOnly:= False;
    if not AllOnly then Continue;
    for var E: TUsesEntryInfo in AEntries do
      if SameText(E.Name, K.UnitName) then
        for var W: TWatchUnit in UnitRuleWatchList(ARules, nil, ATrees.UnitIndex.SameUnit) do
          if ATrees.UnitIndex.SameUnit(W.UnitName, E.Name) then
          begin
            var Ch: TUsesChange:= Default(TUsesChange);
            Ch.Action  := 'remove';
            Ch.UnitName:= E.Name;
            Ch.Section := E.Section;
            Ch.Line    := E.Line;
            Ch.Rule    := W.Rule;
            if (RemovalLeavesUnconverted(ATrees, ADfmText, ARules, AConverted, AOnly, [Ch], Skips) = '') and
               (Length(Skips) = 1) then
            begin
              K.Action  := 'skipped';
              K.Reason  := Skips[0].Reason;
              K.NeededBy:= nil;
              K.Keepers := nil;
              ANeeds.Keeps[I]:= K;
            end;
            Break;
          end;
  end;
end;

// C9 (1.27.0): the RECONCILED uses plan for one unit -- the converted text
// (AArgs.Edits applied in memory) is re-indexed and ReconcileUses decides keep /
// remove / add; PlanUnitRules then plans the edits. PlannerNeeded: the unit
// has unit rules or a C13 move, so the planner owns every uses edit; otherwise
// it is used only when the reconciliation itself adds a unit (UsePlanner), and
// the caller keeps its own #convert uses-add edits. Never refuses by itself.
type
  { C9: everything ReconcileUnitUses needs about the unit and its plan. }
  TReconcileUnitArgs = record
    UnitPas, DfmPath: string;
    Rules           : TConversionRuleSet;
    Edits           : TArray<TTextEdit>;   { the plan's non-uses edits }
    Converted       : TList<string>;       { instances the plan converts; may be nil }
    Only            : TArray<string>;
    Adds, IntfAdds  : TArray<string>;      { the #convert surface's To units }
    Handled         : TArray<string>;      { To type names that surface resolves }
    PlannerNeeded   : Boolean;             { unit rules or a C13 move: the planner owns every edit }
  end;


const
  { C18: the '#migrate Old -> DL_NONE' replacement -- a deliberate break. A
    marker, never a unit symbol: the uses reconciliation skips it (G8). }
  DL_NONE_MARK = 'DL_NONE';

function ReconcileUnitUses(const ATrees: TConvertTreeCache; const AArgs: TReconcileUnitArgs): TReconcileOutcome;
var
  UnitIn : TUsesReconcileInput;
  UnitPas, DfmPath: string;
  Rules  : TConversionRuleSet;
  Adds   : TArray<string>;
  Res    : TUsesReconcileResult;
  OrigDfm: string;
  Entries: TArray<TUsesEntryInfo>;

  procedure Warn(AKind: TApplyItemKind; ALine, ARuleLine: Integer; const AText: string);
  var
    It: TApplyItem;
  begin
    It         := Default(TApplyItem);
    It.Kind    := AKind;
    It.Field   := afWarnings;
    It.FilePath:= UnitPas;
    It.Line    := ALine;
    It.RuleLine:= ARuleLine;
    It.Text    := AText;
    Result.Items:= Result.Items + [It];
  end;

begin
  UnitPas:= AArgs.UnitPas;
  DfmPath:= AArgs.DfmPath;
  Rules  := AArgs.Rules;
  Adds   := AArgs.Adds;
  Result:= Default(TReconcileOutcome);
  UnitIn:= Default(TUsesReconcileInput);
  UnitIn.UnitPas     := UnitPas;
  UnitIn.OrigPas     := ReadUnitText(UnitPas);
  UnitIn.ConvPas     := TTextEditApplier.ApplyToText(UnitPas, UnitIn.OrigPas, AArgs.Edits);
  UnitIn.Rules       := Rules;
  UnitIn.ExtraAdds   := Adds;
  UnitIn.HandledNames:= AArgs.Handled + [DL_NONE_MARK]; { G8: a #migrate break's marker needs no unit }
  UnitIn.InterfaceAdds:= AArgs.IntfAdds;
  OrigDfm:= '';
  if (DfmPath <> '') and TFile.Exists(DfmPath) then
  begin
    OrigDfm    := ReadUnitText(DfmPath);
    UnitIn.ConvDfm:= TTextEditApplier.ApplyToText(DfmPath, OrigDfm, AArgs.Edits);
  end;
  Res:= ReconcileUses(ATrees.UnitIndex, UnitIn);
  Result.Status    := Res.Status;
  Result.Unresolved:= Res.Unresolved;
  Result.Dangling  := Res.Dangling;
  ReadUsesEntries(UnitPas, UnitIn.OrigPas, Entries);
  DemoteOnlySkips(ATrees, OrigDfm, Rules, AArgs.Converted, AArgs.Only, Entries, Res.Needs);
  Result.UsePlanner:= AArgs.PlannerNeeded or (Length(Res.Needs.Adds) > 0);
  Result.Plan:= Default(TUsesPlan);
  Result.Plan.Ok:= True;
  if Result.UsePlanner then
    Result.Plan:= PlanUnitRules(UnitPas, UnitIn.OrigPas, Rules, Adds, AArgs.IntfAdds, Res.Needs);
  if not Result.Plan.Ok then Exit;
  for var Ch: TUsesChange in Result.Plan.Changes do
  begin
    var RL: Integer:= UnitRuleLine(Rules, Ch.UnitName);
    if RL = 0 then
      for var W: TWatchUnit in UnitRuleWatchList(Rules, Adds, ATrees.UnitIndex.SameUnit) do
        if ATrees.UnitIndex.SameUnit(W.UnitName, Ch.UnitName) and (RL = 0) then RL:= UnitRuleLine(Rules, W.UnitName);
    if Ch.Action = 'skipped' then
      Result.Items:= Result.Items + [SkippedRuleItem(Rules, UnitPas, Ch)]
    else if (Ch.Action = 'kept') and (Ch.Reason = KEEP_REASON_UNVERIFIED) then
      Warn(aikUnitRuleUnverified, Ch.Line, RL, Format('line %d: warning: %s kept %s -- no --db indexes that unit, so whether anything still needs it is unknown;' +
        ' pass the platform library --db (resolve-dbs --platform Win32|Win64)',
        [RL, Ch.Rule, Ch.UnitName]))
    else if (Ch.Action = 'kept') and (Ch.Reason = KEEP_REASON_DEGRADED) then
      Warn(aikUnitRuleKept, Ch.Line, RL, Format('line %d: warning: %s kept %s -- the re-index of the converted output failed (%s)',
        [RL, Ch.Rule, Ch.UnitName, Res.Detail]))
    else if Ch.Action = 'kept' then
      Warn(aikUnitRuleKept, Ch.Line, RL, Format('line %d: warning: %s kept %s -- still needed by .dfm component(s) %s',
        [RL, Ch.Rule, Ch.UnitName, NeedNames(Ch.NeededBy)]))
    else if (Ch.Action = 'remove') and (Length(Ch.NeededBy) > 0) then
      Warn(aikUnitRuleDangling, Ch.Line, RL, Format('line %d: warning: %s removed %s while .pas code still references %s -- the unit will not compile until that code is converted',
        [RL, Ch.Rule, Ch.UnitName, NeedNames(Ch.NeededBy)]));
  end;
  for var U: TUsesUnresolved in Res.Unresolved do
  begin
    var Units: string:= '';
    for var C: TUsesCandidate in U.Candidates do Units:= Units + (if Units = '' then '' else ', ') + C.UnitName;
    if U.Reason = UNRESOLVED_AMBIGUOUS then
      Warn(aikUsesUnitAmbiguous, U.Line, 0, Format('line %d: warning: "%s" is declared in %d units (%s) -- none added to uses; add #use <unit> to the book to choose',
        [U.Line, U.Name, Length(U.Candidates), Units]))
    else
      Warn(aikUsesUnitUnresolved, U.Line, 0, Format('line %d: warning: could not resolve a unit declaring "%s" to add to uses', [U.Line, U.Name]));
  end;
end;// Prefixes every line of AReemittedBlock (EmitBlock's CRLF-joined, column-1
// output, trailing CRLF trimmed) with AIndent, so the replacement block lands
// at the same indentation depth as the original.
function ReindentBlock(const AReemittedBlock, AIndent: string): string;
var
  Text_: string;
  Parts: TArray<string>;
  i    : Integer;
  SB   : TStringBuilder;
begin
  Text_:= AReemittedBlock;
  while (Length(Text_) >= 2) and (Copy(Text_, Length(Text_) - 1, 2) = #13#10) do
    Text_:= Copy(Text_, 1, Length(Text_) - 2);
  Parts:= Text_.Replace(#13#10, #10).Split([#10]);
  SB:= TStringBuilder.Create;
  try
    for i:= 0 to High(Parts) do
    begin
      if i > 0 then SB.Append(#13#10);
      SB.Append(AIndent).Append(Parts[i]);
    end;
    Result:= SB.ToString;
  finally
    SB.Free;
  end;
end;

// One confirmed surface #4 access site: a 'member-access' ref (FromMember, at
// [Line, Col..EndCol) -- the MEMBER token's own span, exactly as EmitRef
// records it for the exprDot's rhs node) whose receiver (the exprDot's lhs
// identifier, immediately before the '.') names a converted instance.
type
  TAccessSite = record
    Line, Col, EndCol: Integer;
    InstanceName: string; // the receiver, e.g. 'Edit1'
    Member      : string; // the member token as written (1.27.0, pas_uses[])
  end;

// Whole-word identifier-char test shared by the receiver scan below (mirrors
// the boundary checks LocateFieldTypeToken already uses for the same purpose).
function IsIdentChar(C: Char): Boolean; inline;
begin
  Result:= CharInSet(C, ['A'..'Z', 'a'..'z', '0'..'9', '_']);
end;

// True when ALine opens a `with` statement whose targets (the text between
// `with` and `do` on that line) include AName. A text scan of one line, the
// shape PlanAccessSites' with-block report has always used; C18 shares it.
function WithNamesTarget(const ALine, AName: string): Boolean;
const
  KW_WITH = 'with ';
  KW_DO   = ' do';
begin
  var Low: string:= LowerCase(ALine);
  var WithAt: Integer:= Pos(KW_WITH, Low);
  if (WithAt = 0) or ((WithAt > 1) and IsIdentChar(Low[WithAt - 1])) then Exit(False);
  var After: string:= Copy(Low, WithAt + Length(KW_WITH), MaxInt);
  var DoAt: Integer:= Pos(KW_DO, After);
  var Targets: string:= if DoAt > 0 then Copy(After, 1, DoAt - 1) else After;
  for var Tg: string in Targets.Split([',']) do
    if SameText(Trim(Tg), AName) then Exit(True);
  Result:= False;
end;

// C18: the 1-based character column where the member-access expression ending
// in the member token at AMemberCol starts -- `inst` of `inst.Member`, or
// `Self` of `Self.inst.Member` -- or 0 when the text before the member is not
// that shape. The same backward scan as ResolveMemberAccessReceiver.
function MemberAccessStart(const ALine: string; AMemberCol: Integer): Integer;
const
  SELF_TEXT = 'Self';

  { the start of the identifier before the '.' that precedes column AFrom, 0 if none }
  function IdentBeforeDot(AFrom: Integer): Integer;
  begin
    var P: Integer:= AFrom - 1;
    while (P >= 1) and (ALine[P] = ' ') do Dec(P);
    if (P < 1) or (ALine[P] <> '.') then Exit(0);
    Dec(P);
    while (P >= 1) and (ALine[P] = ' ') do Dec(P);
    var NameEnd: Integer:= P;
    while (P >= 1) and IsIdentChar(ALine[P]) do Dec(P);
    Result:= if P + 1 > NameEnd then 0 else P + 1;
  end;

begin
  Result:= IdentBeforeDot(AMemberCol);
  if Result = 0 then Exit;
  var SelfAt: Integer:= IdentBeforeDot(Result);
  if (SelfAt > 0) and SameText(Copy(ALine, SelfAt, Length(SELF_TEXT)), SELF_TEXT) and
     not IsIdentChar(ALine[SelfAt + Length(SELF_TEXT)]) then Result:= SelfAt;
end;

// Resolves the RECEIVER of a member-access ref at (ALine, AMemberCol) --
// i.e. the base identifier immediately before the '.' that precedes the
// member token -- by reading the source line text directly rather than a
// second refs-table lookup: the member-access ref's own span gives us the
// exact column the member token starts at (AMemberCol = the ref's StartCol,
// 1-based), so walking backward from there past whitespace, the '.', more
// whitespace, and then the identifier run is a simple, robust text scan (the
// parser's exprDot handler guarantees a plain-identifier lhs is what emitted
// this ref in the first place -- see ref-gap G in DRagLint.Parser.Delphi13.
// Walk's exprDot case -- so there is always exactly one identifier token to
// find here; this is not a general expression parse). Returns '' when the
// line text does not have the expected 'ident.' shape immediately before
// AMemberCol (defensive -- should not happen for a genuine member-access ref,
// but a stale/mismatched line count must not crash the applier).
function ResolveMemberAccessReceiver(const APasLines: TStringList; ALine, AMemberCol: Integer): string;
var
  S: string;
  P: Integer;
  NameEnd, NameStart: Integer;
begin
  Result:= '';
  if (ALine < 1) or (ALine > APasLines.Count) then Exit;
  S:= APasLines[ALine - 1];
  P:= AMemberCol - 1; { last column BEFORE the member token, 1-based }
  while (P >= 1) and (S[P] = ' ') do Dec(P);
  if (P < 1) or (S[P] <> '.') then Exit; { not immediately preceded by '.': not a simple obj.Member site }
  Dec(P);
  while (P >= 1) and (S[P] = ' ') do Dec(P);
  NameEnd:= P;
  while (P >= 1) and IsIdentChar(S[P]) do Dec(P);
  NameStart:= P + 1;
  if NameStart > NameEnd then Exit; { '.' not preceded by an identifier }
  Result:= Copy(S, NameStart, NameEnd - NameStart + 1);
end;

// Finds every surface #4 access site in AUnitPas for one renaming '#link
// AToMember <- AFromMember' (AToMember and AFromMember already confirmed
// distinct by the caller): every 'member-access' ref whose NameText =
// AFromMember, whose receiver (ResolveMemberAccessReceiver, read off the
// SAME line the ref itself was recorded at) matches one of AInstanceNames
// (case-insensitively -- the .dfm/.pas instance-name spelling is preserved
// verbatim by FindConvertInstances, so an exact SameText match is correct
// here, not a substring/prefix match). AFromMember = '' takes EVERY member
// (1.27.0, pas_uses[]). A member-access whose receiver is
// NOT in AInstanceNames (e.g. 'Other.Caption' when Other is a different,
// unconverted object) is silently skipped -- this instance-scoping is the
// whole point of joining through the receiver, not just matching on member
// name alone (which would also rewrite unrelated types' same-named members).
function FindMemberAccessSites(const AStore: ISymbolStore; AFileId: Int64;
  const APasLines: TStringList; const AFromMember: string;
  const AInstanceNames: TArray<string>): TArray<TAccessSite>;
var
  Refs: TArray<TReference>;
  R   : TReference;
  List: TList<TAccessSite>;
  Site: TAccessSite;
  Receiver: string;
  IsConverted: Boolean;
  N   : string;
begin
  Result:= nil;
  if AFileId <= 0 then Exit;
  Refs:= AStore.GetReferencesFromFile(AFileId);
  List:= TList<TAccessSite>.Create;
  try
    for R in Refs do
    begin
      if not SameText(R.Kind, 'member-access') then Continue;
      if (AFromMember <> '') and not SameText(R.NameText, AFromMember) then Continue;

      { C18: the index column counts UTF-8 bytes; the scan reads characters }
      if (R.StartLine < 1) or (R.StartLine > APasLines.Count) then Continue;
      Receiver:= ResolveMemberAccessReceiver(APasLines, R.StartLine,
        CharColumn(APasLines[R.StartLine - 1], R.StartCol));
      if Receiver = '' then Continue;

      IsConverted:= False;
      for N in AInstanceNames do
        if SameText(N, Receiver) then begin IsConverted:= True; Break; end;
      if not IsConverted then Continue; { e.g. Other.Caption -- Other is not a converted instance }

      Site:= Default(TAccessSite);
      Site.Line        := R.StartLine;
      Site.Col         := R.StartCol;
      Site.EndCol      := R.EndCol;
      Site.InstanceName:= Receiver;
      Site.Member      := R.NameText;
      List.Add(Site);
    end;
    Result:= List.ToArray;
  finally
    List.Free;
  end;
end;

// C8 N2 review (1.26.0): FindMemberAccessSites joins a member access to an
// instance by the RECEIVER'S NAME only, so `<name>.Caption` was rewritten
// wherever it appeared in the unit -- a local or parameter of that name in
// another method, another class's same-named field included. This keeps a
// site only when its receiver IS the instance's field:
//   * the receiver reference is bound (refs.symbol_id) to the field named like
//     the instance that the .dfm's ROOT class (declared in this unit)
//     declares or inherits -- another class's same-named field is not it; or
//   * it is unbound, written bare or as Self.X, and the routine it sits in
//     (walked up through nested routines) declares no local / parameter of
//     that name and belongs to the root class.
// Everything else -- bound to anything else, unbound with another receiver,
// shadowed, in an unrelated class -- is dropped. A site whose line holds NO
// reference for its receiver cannot be checked at all (the .pas changed since
// it was indexed, or the indexer did not record it): it is not rewritten and
// goes to AUnverified, which the caller REPORTS. Applies to own instances and
// to C8 N2 / N2a inherited ones alike. Reads the index; writes nothing.
function BoundAccessSites(const AStore: ISymbolStore; AFileId: Int64; const ADfmPath: string;
  const ASites: TArray<TAccessSite>; out AUnverified: TArray<TAccessSite>): TArray<TAccessSite>;
const
  { how many parents a reference's routine is walked up to reach its class }
  ROUTINE_HOPS = 4;
  { the receiver text of an explicit Self.X access }
  SELF_TEXT = 'Self';
var
  Refs     : TArray<TReference>;
  Classes  : TArray<TSymbol>;
  FieldIds : TDictionary<string, TArray<Int64>>; { UPPER name -> field ids }
  OwnerIds : TDictionary<string, TArray<Int64>>; { UPPER name -> classes declaring / inheriting it }
  ByLine   : TDictionary<Integer, TArray<Integer>>; { line -> indexes into Refs }
  Bound    : TList<TAccessSite>;
  Unbound  : TList<TAccessSite>;

  function Has(const AIds: TArray<Int64>; AId: Int64): Boolean;
  begin
    for var X: Int64 in AIds do
      if X = AId then Exit(True);
    Result:= False;
  end;

  { the field named AName a class of this unit declares, or the nearest an ancestor does }
  procedure ScopeOf(const AName: string; out AFields, AOwners: TArray<Int64>);
  var
    F: TSymbol;
  begin
    if FieldIds.TryGetValue(UpperCase(AName), AFields) then
    begin
      AOwners:= OwnerIds[UpperCase(AName)];
      Exit;
    end;
    AFields:= nil;
    AOwners:= nil;
    for var C: TSymbol in Classes do
    begin
      F:= AStore.FindChildSymbolByName(C.Id, AName);
      if (F.Id = 0) or (F.Kind <> skField) then
      begin
        F:= Default(TSymbol);
        for var A: TTypeAncestor in AStore.GetTransitiveAncestors(C.Id) do
        begin
          if not A.Resolved or (A.SymbolId = 0) then Continue;
          F:= AStore.FindChildSymbolByName(A.SymbolId, AName);
          if (F.Id <> 0) and (F.Kind = skField) then Break;
          F:= Default(TSymbol);
        end;
      end;
      if F.Id = 0 then Continue;
      if not Has(AFields, F.Id) then AFields:= AFields + [F.Id];
      AOwners:= AOwners + [C.Id];
    end;
    FieldIds.Add(UpperCase(AName), AFields);
    OwnerIds.Add(UpperCase(AName), AOwners);
  end;

  { the class a routine belongs to, 0 when a routine on the way declares AName }
  function ClassOfRoutine(ARoutineId: Int64; const AName: string): Int64;
  var
    S: TSymbol;
  begin
    S:= AStore.GetSymbolById(ARoutineId);
    for var Hop: Integer:= 1 to ROUTINE_HOPS do
    begin
      if S.Id = 0 then Break;
      if S.Kind = skClass then Exit(S.Id);
      if AStore.FindChildSymbolByName(S.Id, AName).Id <> 0 then Break;
      S:= AStore.GetSymbolById(S.ParentId);
    end;
    Result:= 0;
  end;

  function SiteIsBound(const ASite: TAccessSite; out AUnchecked: Boolean): Boolean;
  var
    Recv   : TReference;
    Found  : Boolean;
    Fields : TArray<Int64>;
    Owners : TArray<Int64>;
  begin
    Found:= False;
    Recv := Default(TReference);
    var OnLine: TArray<Integer>;
    if ByLine.TryGetValue(ASite.Line, OnLine) then
      for var I: Integer in OnLine do
      begin
        var R: TReference:= Refs[I];
        if (R.StartCol < ASite.Col) and SameText(R.NameText, ASite.InstanceName) and
           ((not Found) or (R.StartCol > Recv.StartCol)) then
        begin
          Recv := R;
          Found:= True;
        end;
      end;
    AUnchecked:= not Found;
    if not Found then Exit(False);
    ScopeOf(ASite.InstanceName, Fields, Owners);
    if Recv.SymbolId <> 0 then Exit(Has(Fields, Recv.SymbolId));
    if (Recv.ReceiverText <> '') and not SameText(Recv.ReceiverText, SELF_TEXT) then Exit(False);
    Result:= Has(Owners, ClassOfRoutine(Recv.EnclosingSymbolId, ASite.InstanceName));
  end;

begin
  Result     := nil;
  AUnverified:= nil;
  if (AFileId <= 0) or (Length(ASites) = 0) then Exit;
  Refs:= AStore.GetReferencesFromFile(AFileId);
  Classes:= nil;
  var Root: string:= '';
  if (ADfmPath <> '') and TFile.Exists(ADfmPath) then Root:= DfmRootClass(ReadUnitText(ADfmPath));
  for var S: TSymbol in AStore.FindSymbolsByFile(AStore.GetFilePath(AFileId)) do
    if (S.Kind = skClass) and SameText(S.Name, Root) then Classes:= Classes + [S];
  FieldIds:= TDictionary<string, TArray<Int64>>.Create;
  OwnerIds:= TDictionary<string, TArray<Int64>>.Create;
  ByLine  := TDictionary<Integer, TArray<Integer>>.Create;
  Bound   := TList<TAccessSite>.Create;
  Unbound := TList<TAccessSite>.Create;
  try
    { review fix wave: the refs bucketed by line ONCE -- a site looks only at
      its own line, not at every ref of the file (was O(sites x refs)) }
    for var I: Integer:= 0 to High(Refs) do
    begin
      var OnLine: TArray<Integer>;
      if not ByLine.TryGetValue(Refs[I].StartLine, OnLine) then OnLine:= nil;
      ByLine.AddOrSetValue(Refs[I].StartLine, OnLine + [I]);
    end;
    for var Site: TAccessSite in ASites do
    begin
      var Unchecked: Boolean;
      if SiteIsBound(Site, Unchecked) then Bound.Add(Site)
      else if Unchecked then Unbound.Add(Site);
    end;
    Result     := Bound.ToArray;
    AUnverified:= Unbound.ToArray;
  finally
    Unbound.Free;
    Bound.Free;
    ByLine.Free;
    OwnerIds.Free;
    FieldIds.Free;
  end;
end;

// 1.26.1 (F1 on the .pas side): the converted instances a #link may rewrite --
// those whose #convert block is the rule's own (the block the .dfm re-emit
// picks: the first #convert whose From type matches, else the first), or every
// one for a file-scope rule before the first #convert. Until 1.26.0 every
// block's #link rewrote every instance's sites: four identical DatabaseName
// edits per DMTEST site, and two blocks linking one path to different targets
// wrote both into the same line. 1.27.0: lifted out of PlanAccessSites so
// pas_uses[] scopes a link exactly as the rewrite does.
// The #convert block (1-based) a #link belongs to: the number of #convert
// rules at or before its line; 0 for a file-scope link before the first.
function LinkRuleBlock(const ARules: TConversionRuleSet; const ALink: TConversionRule): Integer;
begin
  Result:= 0;
  for var Q: TConversionRule in ARules.Rules do
    if (Q.Kind = rkConvert) and (Q.LineNo <= ALink.LineNo) then Inc(Result);
end;

// The #convert block (1-based) the .dfm re-emit picks for each converted
// instance: the first #convert whose From type matches, else the first. An
// instance with no known From type has no entry. The caller frees the result.
// Review fix wave: lifted out of LinkScopeNames so a caller asking for MANY
// links (CollectPasUses) computes it once, not once per link.
function InstanceConvertBlocks(const ARules: TConversionRuleSet; AConverted: TList<string>;
  AFromTypes: TDictionary<string, string>): TDictionary<string, Integer>;
var
  Block, First, Found: Integer;
  FromT: string;
begin
  Result:= TDictionary<string, Integer>.Create;
  for var N: string in AConverted do
  begin
    if not AFromTypes.TryGetValue(N, FromT) then Continue;
    Block:= 0;
    First:= 0;
    Found:= 0;
    for var Q: TConversionRule in ARules.Rules do
      if Q.Kind = rkConvert then
      begin
        Inc(Block);
        if First = 0 then First:= Block;
        if (Found = 0) and SameText(BareTypeTail(Q.FromType), BareTypeTail(FromT)) then Found:= Block;
      end;
    Result.AddOrSetValue(N, if Found = 0 then First else Found);
  end;
end;

// The converted instances whose block (ABlocks) is ARuleBlock, in AConverted
// order; every one of them when ARuleBlock is 0 (a file-scope link).
function ScopeFromBlocks(AConverted: TList<string>; ABlocks: TDictionary<string, Integer>;
  ARuleBlock: Integer): TArray<string>;
var
  B: Integer;
begin
  if ARuleBlock = 0 then Exit(AConverted.ToArray);
  var Names: TList<string>:= TList<string>.Create;
  try
    for var N: string in AConverted do
      if ABlocks.TryGetValue(N, B) and (B = ARuleBlock) then Names.Add(N);
    Result:= Names.ToArray;
  finally
    Names.Free;
  end;
end;

function LinkScopeNames(const ARules: TConversionRuleSet; AConverted: TList<string>;
  AFromTypes: TDictionary<string, string>; const ALink: TConversionRule): TArray<string>;
begin
  var RuleBlock: Integer:= LinkRuleBlock(ARules, ALink);
  if RuleBlock = 0 then Exit(AConverted.ToArray);
  var Blocks: TDictionary<string, Integer>:= InstanceConvertBlocks(ARules, AConverted, AFromTypes);
  try
    Result:= ScopeFromBlocks(AConverted, Blocks, RuleBlock);
  finally
    Blocks.Free;
  end;
end;

// 1.27.0 (pas_uses[]): the pas_uses kind of a symbol. AMember: it is a member
// of a type (a method then, never a routine).
function PasUseKind(AKind: TSymbolKind; const AName: string; AMember: Boolean): string;
const
  EVENT_PREFIX = 'On';
begin
  case AKind of
    skMethod, skConstructor, skDestructor: Result:= 'method';
    skProcedure, skFunction: Result:= if AMember then 'method' else 'routine';
    skProperty:
      Result:= if StartsText(EVENT_PREFIX, AName) and (Length(AName) > Length(EVENT_PREFIX)) and
                  CharInSet(AName[Length(EVENT_PREFIX) + 1], ['A'..'Z']) then 'event' else 'property';
    skField: Result:= 'field';
    skConstDecl: Result:= 'const';
    skVarDecl: Result:= 'var';
    skClass, skInterface, skRecord, skEnum, skTypeAlias: Result:= 'type';
    skEnumValue: Result:= 'enum-value';  { 1.28.2: was '' -- a global-dangling bkOK }
  else
    Result:= '';
  end;
end;

// 1.28.2: the unit-level classes named AName in any of ATrees' stores, one
// per qualified name, appended to AQNames with their unit stems in AStems
// (index-aligned). An implementation-section class counts only when it is
// declared in AScopePath itself.
procedure CollectClassDeclarers(ATrees: TConvertTreeCache; const AName, AScopePath: string;
  AQNames, AStems: TList<string>);
begin
  for var St: ISymbolStore in ATrees.Stores do
    for var S: TSymbol in St.FindSymbolsByExactName(AName) do
    begin
      if (S.Kind <> skClass) or (S.FileId <= 0) then Continue;
      var Path: string:= St.GetFilePath(S.FileId);
      var Stem: string:= TPath.GetFileNameWithoutExtension(Path);
      if not SameText(S.QualifiedName, Stem + '.' + AName) then Continue;   { unit level only }
      if SameText(S.Section, 'implementation') and not SameText(Path, AScopePath) then Continue;
      var Known: Boolean:= False;
      for var Q: string in AQNames do
        if SameText(Q, S.QualifiedName) then Known:= True;
      if Known then Continue;
      AQNames.Add(S.QualifiedName);
      AStems.Add(Stem);
    end;
end;

// 1.28.2: the indexes into AStems that the LAST uses entry of file
// AScopeFileId naming any of them names (AIntfOnly: interface entries only);
// [] when no entry names one. Two or more = that entry is itself ambiguous.
function UsesTiedDeclarers(ATrees: TConvertTreeCache; const AScope: ISymbolStore; AScopeFileId: Int64;
  AIntfOnly: Boolean; AStems: TList<string>): TArray<Integer>;
begin
  Result:= nil;
  var UsesList: TArray<TUnitUse>:= AScope.GetUnitUsesForFile(AScopeFileId);
  TArray.Sort<TUnitUse>(UsesList, TComparer<TUnitUse>.Construct(
    function(const A, B: TUnitUse): Integer
    begin
      Result:= A.StartLine - B.StartLine;
    end));
  for var U: Integer:= High(UsesList) downto 0 do
  begin
    if AIntfOnly and (UsesList[U].Section <> uusInterface) then Continue;
    for var I: Integer:= 0 to AStems.Count - 1 do
      if ATrees.UnitIndex.SameUnit(UsesList[U].UnitName, AStems[I]) then Result:= Result + [I];
    if Length(Result) > 0 then Exit;
  end;
end;

// 1.28.2 (pas_uses[]): the class AName names as file AScopeFileId of AScope
// sees it -- the converter's report: a VCL Label1: TLabel resolved by BARE
// NAME across the --db stores landed on FMX.StdCtrls.TLabel. A qualified
// AName is taken as written. Otherwise, of the unit-level classes of that
// name in any store (an implementation-section one only from the scope file
// itself): the scope unit's own; else the declarer named by the LAST uses
// entry of the file that names exactly one declarer (Delphi's scope order;
// AIntfOnly: interface entries only, for a name used above implementation;
// an entry naming two -- 'StdCtrls' for FMX.StdCtrls and Vcl.StdCtrls -- is
// ambiguous, not a pick); else the one AHint (the book's qualification)
// names; else a lone declarer. Anything else is PAS_RES_AMBIGUOUS. The ONE
// in-scope rule: TConvertTreeCache.ScopedClass resolves every #convert From /
// To class through it too (AScopeFileId 0 = no unit: hint, then lone declarer).
function ResolveClassInScope(ATrees: TConvertTreeCache; const AScope: ISymbolStore; AScopeFileId: Int64;
  const AName: string; AIntfOnly: Boolean; const AHint: string): TScopedClass;
var
  QNames, Stems: TList<string>;
  Tied         : TArray<Integer>;
  Pick         : Integer;
begin
  Result:= Default(TScopedClass);
  Result.Resolution:= PAS_RES_CLASS_NOT_FOUND;
  if Trim(AName) = '' then Exit;
  if Pos('.', AName) > 0 then
  begin
    Result.QName:= ATrees.ResolveType(AName);
    if Result.QName <> '' then Result.Resolution:= PAS_RES_RESOLVED;
    Exit;
  end;
  var ScopePath: string:= if (AScope <> nil) and (AScopeFileId > 0) then AScope.GetFilePath(AScopeFileId) else '';
  var ScopeStem: string:= TPath.GetFileNameWithoutExtension(ScopePath);
  QNames:= TList<string>.Create;
  Stems := TList<string>.Create;
  try
    CollectClassDeclarers(ATrees, AName, ScopePath, QNames, Stems);
    if QNames.Count = 0 then Exit;
    Pick:= -1;
    Tied:= nil;
    for var I: Integer:= 0 to Stems.Count - 1 do
      if (ScopeStem <> '') and SameText(Stems[I], ScopeStem) then Pick:= I;
    if (Pick < 0) and (ScopeStem <> '') then
    begin
      Tied:= UsesTiedDeclarers(ATrees, AScope, AScopeFileId, AIntfOnly, Stems);
      if Length(Tied) = 1 then Pick:= Tied[0];
    end;
    if (Pick < 0) and (Length(Tied) < 2) and SameText(BareTypeTail(AHint), AName) then
      for var I: Integer:= 0 to QNames.Count - 1 do
        if SameText(QNames[I], AHint) then Pick:= I;
    if (Pick < 0) and (QNames.Count = 1) then Pick:= 0;
    if Pick >= 0 then
    begin
      Result.QName     := QNames[Pick];
      Result.Resolution:= PAS_RES_RESOLVED;
      Exit;
    end;
    Result.Resolution:= PAS_RES_AMBIGUOUS;
    if Length(Tied) > 1 then
      for var I: Integer in Tied do Result.Candidates:= Result.Candidates + [Stems[I]]
    else
      Result.Candidates:= Stems.ToArray;
    TArray.Sort<string>(Result.Candidates);
  finally
    Stems.Free;
    QNames.Free;
  end;
end;

// 1.27.0 (pas_uses[]): the member AName of class AClassQName, declared by the
// class itself or by its nearest ancestor that declares it. An ancestor the
// class's store cannot resolve (TComponent of a project class) is resolved
// through the scope of the unit that declares the class (1.28.2,
// ResolveClassInScope -- it was a bare-name lookup) and followed in the store
// that holds it. AOwner is the declaring class, AUnit its unit. False when no
// store holds such a member; AAmbiguous is then the first ancestor whose
// declarer the scope could not settle (Resolution '' when none was).
function FindClassMember(ATrees: TConvertTreeCache; const AClassQName, AName: string;
  out AMember: TSymbol; out AOwner, AUnit: string; out AAmbiguous: TScopedClass): Boolean;
const
  MAX_HOPS = 32;
  MEMBER_KINDS: set of TSymbolKind = [skMethod, skConstructor, skDestructor, skProcedure, skFunction,
                                      skProperty, skField, skConstDecl, skVarDecl,
                                      skClass, skInterface, skRecord, skEnum, skTypeAlias];
var
  Seen: TList<string>;

  function TryIn(const AStore: ISymbolStore; const AClass: TSymbol): Boolean;
  begin
    var M: TSymbol:= AStore.FindChildSymbolByName(AClass.Id, AName);
    Result:= (M.Id <> 0) and (M.Kind in MEMBER_KINDS);
    if not Result then Exit;
    AMember:= M;
    AOwner := AClass.Name;
    AUnit  := TPath.GetFileNameWithoutExtension(AStore.GetFilePath(M.FileId));
  end;

  function Search(const AStore: ISymbolStore; const AClass: TSymbol; ADepth: Integer): Boolean;
  begin
    Result:= False;
    if (AStore = nil) or (AClass.Id = 0) or (ADepth > MAX_HOPS) or Seen.Contains(UpperCase(AClass.QualifiedName)) then Exit;
    Seen.Add(UpperCase(AClass.QualifiedName));
    if TryIn(AStore, AClass) then Exit(True);
    for var A: TTypeAncestor in AStore.GetTransitiveAncestors(AClass.Id) do
    begin
      if A.Resolved and (A.SymbolId <> 0) then
      begin
        if TryIn(AStore, AStore.GetSymbolById(A.SymbolId)) then Exit(True);
        Continue;
      end;
      var Anc: TScopedClass:= ResolveClassInScope(ATrees, AStore, AClass.FileId, A.Name,
        SameText(AClass.Section, 'interface'), '');
      if Anc.Resolution = PAS_RES_AMBIGUOUS then
      begin
        if AAmbiguous.Resolution = '' then AAmbiguous:= Anc;
        Continue;
      end;
      if Anc.QName = '' then Continue;
      var Other: ISymbolStore;
      var C: TSymbol:= ATrees.ClassSymbol(Anc.QName, Other);
      if Search(Other, C, ADepth + 1) then Exit(True);
    end;
  end;

begin
  AMember:= Default(TSymbol);
  AOwner := '';
  AUnit  := '';
  AAmbiguous:= Default(TScopedClass);
  Seen:= TList<string>.Create;
  try
    var St: ISymbolStore;
    var Cls: TSymbol:= ATrees.ClassSymbol(AClassQName, St);
    Result:= Search(St, Cls, 0);
  finally
    Seen.Free;
  end;
end;

type
  // 1.27.0: what CollectPasUses needs about one unit's plan.
  TPasUsesInput = record
    Trees    : TConvertTreeCache;
    Store    : ISymbolStore;                  { the store indexing the unit }
    FileId   : Int64;
    PasLines : TStringList;
    DfmPath  : string;
    Book     : TApplyBook;
    Converted: TList<string>;                 { instances the plan converts }
    FromTypes: TDictionary<string, string>;   { instance -> From type }
    CastLib  : TCastLib;                      { 1.27.0 (C15): a value-cast link is mapped }
    ToTypes  : TDictionary<string, string>;   { instance -> To type }
  end;

// The distinct values of ALines, ascending.
function DistinctSortedLines(const ALines: TArray<Integer>): TArray<Integer>;
begin
  var Sorted: TArray<Integer>:= Copy(ALines);
  TArray.Sort<Integer>(Sorted);
  var Kept: Integer:= 0;
  for var I: Integer:= 0 to High(Sorted) do
    if (Kept = 0) or (Sorted[I] <> Sorted[Kept - 1]) then
    begin
      Sorted[Kept]:= Sorted[I];
      Inc(Kept);
    end;
  SetLength(Sorted, Kept);
  Result:= Sorted;
end;

// 1.27.0 review fix wave: the pas_uses status one #link gives the member its
// FromPath head names -- the access-site planner's own decision, mirrored
// branch for branch (PlanAccessSites):
//   * a CLASS cast, or a cast the library does not hold -> cast-refused
//     (Outcomes 1-3: refused per site, or skipped with one warning);
//   * a dotted To or From path -> not-rewritten (the planner's
//     "nested .dfm path" Continue; a value cast on a dotted path finds no
//     member token either), except an identity link of a plain path;
//   * otherwise -> mapped (renamed, or an identity link: nothing to rename;
//     a value cast's literals are rewritten or checked).
function LinkPasStatus(const ALink: TConversionRule; const ACastLib: TCastLib): string;
begin
  var Dotted  : Boolean:= (Pos('.', ALink.ToPath) > 0) or (Pos('.', ALink.FromPath) > 0);
  var Identity: Boolean:= SameText(ALink.ToPath, ALink.FromPath);
  if ALink.Cast <> '' then
  begin
    var VD: TCastDef;
    if not (FindClassCast(ACastLib, ALink.Cast, VD) and (VD.Value <> '')) then Exit(PAS_USE_CAST_REFUSED);
    Exit(if Dotted then PAS_USE_NOT_REWRITTEN else PAS_USE_MAPPED);
  end;
  Result:= if Dotted and not Identity then PAS_USE_NOT_REWRITTEN else PAS_USE_MAPPED;
end;

// C18 slice 1: '' when convert-apply realises the #migrate rule ARule (a plain
// member renamed to a plain identifier, or to DL_NONE), else why it does not.
// A refused rule is reported (migrate-check), never applied in part.
function MigrateRuleRefusal(const ARule: TConversionRule): string;
begin
  if ARule.Scope <> '' then Exit('a scoped #migrate (Class: / obj.) is not applied yet');
  if not IsValidIdent(ARule.Old) then Exit('only a plain member name is migrated; call and assignment forms are not applied yet');
  if ARule.New = '' then Exit('it names no replacement');
  if not IsValidIdent(ARule.New) then Exit('only a member rename or DL_NONE is applied; replacement templates are not applied yet');
  if Length(ARule.UnitsAdd) > 0 then Exit('uses units after a member #migrate are not added by convert-apply');
  Result:= '';
end;

// 1.38 (owner ruling D2, 2026-10-28): the unit-level declaration AName names
// in the supplied stores -- a type, an enum value, a const, a var or a routine,
// never a member, a local or a parameter. A dotted name is looked up
// qualified. False when no store declares it.
function ResolveMigrateTarget(const ATrees: TConvertTreeCache; const AName: string;
  out ASym: TSymbol; out AStore: ISymbolStore): Boolean;
const
  DECL_KINDS: set of TSymbolKind = [skClass, skInterface, skRecord, skEnum, skEnumValue, skTypeAlias,
                                    skConstDecl, skVarDecl, skProcedure, skFunction];
begin
  ASym  := Default(TSymbol);
  AStore:= nil;
  if AName = '' then Exit(False);
  var Bare: string:= BareTypeTail(AName);
  for var St: ISymbolStore in ATrees.Stores do
  begin
    var Found: TArray<TSymbol>:= if AName.Contains('.') then St.FindSymbolsByQualifiedName(AName)
                                 else St.FindSymbolsByExactName(AName);
    for var S: TSymbol in Found do
      if (S.Kind in DECL_KINDS) and SameText(S.Name, Bare) then
      begin
        ASym  := S;
        AStore:= St;
        Exit(True);
      end;
  end;
  Result:= False;
end;

// 1.38 (D2): an enum member's name after its lowercase prefix (scoWait ->
// 'Wait'); '' when the name has no such prefix or nothing after it.
function EnumMemberStem(const AName: string): string;
begin
  var I: Integer:= 1;
  while (I <= Length(AName)) and CharInSet(AName[I], ['a'..'z']) do Inc(I);
  Result:= if (I = 1) or (I > Length(AName)) then '' else Copy(AName, I, MaxInt);
end;

// 1.38 (D2): True when the #migrate ARule of #convert block ABlock (0 = file
// scope) renames an IDENTIFIER in code -- PlanIdentifierMigrates' job -- and
// not a member of the block's converted instances (PlanMigrateSites'): every
// file-scope rule, and a plain in-block rule that names uses units or whose
// New is an enum value.
function MigrateIsIdentifier(const ATrees: TConvertTreeCache; const ARule: TConversionRule; ABlock: Integer): Boolean;
begin
  if ARule.Kind <> rkMigrate then Exit(False);
  if ABlock = 0 then Exit(True);
  if (ARule.Scope <> '') or not IsValidIdent(ARule.Old) or not IsValidIdent(ARule.New) or
     SameText(ARule.New, DL_NONE_MARK) then Exit(False);
  if Length(ARule.UnitsAdd) > 0 then Exit(True);
  { a member name is PascalCase; only an enum-literal spelling is looked up }
  if EnumMemberStem(ARule.New) = '' then Exit(False);
  var Sym: TSymbol;
  var St : ISymbolStore;
  Result:= ResolveMigrateTarget(ATrees, ARule.New, Sym, St) and (Sym.Kind = skEnumValue);
end;

// The precedence of the link-given pas_uses statuses (higher wins).
function PasStatusRank(const AStatus: string): Integer;
const
  RANK_MAPPED        = 0;
  RANK_NOT_REWRITTEN = 1;
  RANK_CAST_REFUSED  = 2;
begin
  if AStatus = PAS_USE_CAST_REFUSED then Result:= RANK_CAST_REFUSED
  else if AStatus = PAS_USE_NOT_REWRITTEN then Result:= RANK_NOT_REWRITTEN
  else Result:= RANK_MAPPED;
end;

type
  // review fix wave: one cached FindClassMember answer (CollectPasUses).
  TMemberHit = record
    Found   : Boolean;
    Member  : TSymbol;
    Owner   : string;
    DeclUnit: string;
    Ambig   : TScopedClass;  { 1.28.2: an ancestor the scope could not settle }
  end;

// 1.28.2: the From and To types the book's #convert rule for AFromBare spells,
// qualified or not -- the rule FindConvertRuleFor picks (the first match).
procedure ConvertRuleSpelling(const ARules: TConversionRuleSet; const AFromBare: string;
  out AFrom, ATo: string);
begin
  AFrom:= '';
  ATo  := '';
  for var R: TConversionRule in ARules.Rules do
    if (R.Kind = rkConvert) and SameText(BareTypeTail(R.FromType), AFromBare) then
    begin
      AFrom:= R.FromType;
      ATo  := R.ToType;
      Exit;
    end;
end;

// 1.27.0: apply/1 pas_uses[] member rows -- every member the unit's code
// reaches through a converted instance, on the access-site rewrite's own
// bound sites, with what the map does about it (see TApplyPasUse).
function CollectPasUses(const AIn: TPasUsesInput): TArray<TApplyPasUse>;
var
  Cover   : TDictionary<string, string>;      { UPPER instance|member -> a link-given status }
  Index   : TDictionary<string, Integer>;     { UPPER instance|member -> row }
  Rows    : TList<TApplyPasUse>;
  RowLines: TObjectList<TList<Integer>>;      { per row, its lines as found }
  Hits    : TDictionary<string, TMemberHit>;  { UPPER class|member -> FindClassMember's answer }
  ClassMemo: TDictionary<string, TScopedClass>; { UPPER instance|type|side -> ClassOf's answer }
  Blocks  : TDictionary<string, Integer>;     { instance -> its #convert block, once for every link }
  MigTo   : TDictionary<string, string>;      { UPPER instance|member -> a realised #migrate's New (G4) }
  Unv     : TArray<TAccessSite>;
  Status  : string;

  { review fix wave: FindClassMember walks ancestors across every --db; many
    instances share a type, so each (class, member) is asked ONCE. AClassQName
    is qualified (ResolveClassInScope). }
  function Lookup(const AClassQName, AMember: string): TMemberHit;
  begin
    var Key: string:= UpperCase(AClassQName + '|' + AMember);
    if Hits.TryGetValue(Key, Result) then Exit;
    Result:= Default(TMemberHit);
    Result.Found:= FindClassMember(AIn.Trees, AClassQName, AMember, Result.Member, Result.Owner, Result.DeclUnit,
      Result.Ambig);
    Hits.Add(Key, Result);
  end;

  { 1.28.2: instance AInst's From (AToSide False) or To class, through the
    unit's own scope -- never by bare name alone. The From side reads the
    instance's field declaration: its section (an interface field sees the
    interface uses only) and a qualified type written there. The book's
    #convert spelling is the hint either side. }
  function ClassOf(const AInst, AType: string; AToSide: Boolean): TScopedClass;
  begin
    var Key: string:= UpperCase(AInst + '|' + AType + '|' + BoolToStr(AToSide, True));
    if ClassMemo.TryGetValue(Key, Result) then Exit;
    var Name    : string := AType;
    var IntfOnly: Boolean:= False;
    if not AToSide then
      for var F: TSymbol in AIn.Store.FindSymbolsByExactName(AInst) do
        if (F.FileId = AIn.FileId) and (F.Kind = skField) then
        begin
          IntfOnly:= SameText(F.Section, 'interface');
          var Written: string:= Trim(F.Signature);
          if Written.StartsWith(':') then Written:= Trim(Written.Substring(1));
          if (Pos('.', Written) > 0) and SameText(BareTypeTail(Written), AType) then Name:= Written;
          Break;
        end;
    var HintFrom, HintTo, FromBare: string;
    if not AIn.FromTypes.TryGetValue(AInst, FromBare) then FromBare:= '';
    ConvertRuleSpelling(AIn.Book.Rules, if AToSide then BareTypeTail(FromBare) else AType, HintFrom, HintTo);
    { a bare book spelling hints with the class the BLOCK resolved to (scope,
      book units, inference), so a row agrees with the class converted }
    var Hint: string:= if AToSide then HintTo else HintFrom;
    if (Hint <> '') and (Pos('.', Hint) = 0) then Hint:= AIn.Trees.ResolveType(Hint);
    Result:= ResolveClassInScope(AIn.Trees, AIn.Store, AIn.FileId, Name, IntfOnly, Hint);
    ClassMemo.Add(Key, Result);
  end;

  { one site of (AInstance, AMember) on ALine: joins the row, or opens it }
  procedure AddSite(const AInstance, AMember: string; ALine: Integer);
  begin
    var Inst: string:= AInstance;
    for var N: string in AIn.Converted do
      if SameText(N, AInstance) then Inst:= N;
    var K: string:= UpperCase(Inst + '|' + AMember);
    var At: Integer;
    if Index.TryGetValue(K, At) then
    begin
      RowLines[At].Add(ALine);
      Exit;
    end;
    var R: TApplyPasUse:= Default(TApplyPasUse);
    R.Instance:= Inst;
    R.Member  := AMember;
    if not AIn.FromTypes.TryGetValue(Inst, R.FromType) then R.FromType:= '';
    if not AIn.ToTypes.TryGetValue(Inst, R.ToType) then R.ToType:= '';
    var FromCls: TScopedClass:= ClassOf(Inst, R.FromType, False);
    R.Resolution:= FromCls.Resolution;
    R.Candidates:= FromCls.Candidates;
    if FromCls.Resolution = PAS_RES_RESOLVED then
    begin
      var Hit: TMemberHit:= Lookup(FromCls.QName, AMember);
      if Hit.Found then
      begin
        R.Kind         := PasUseKind(Hit.Member.Kind, Hit.Member.Name, True);
        R.Visibility   := Trim(Hit.Member.Modifiers);
        R.DeclaredIn   := Hit.Owner;
        R.DeclaringUnit:= Hit.DeclUnit;
      end
      else if Hit.Ambig.Resolution = PAS_RES_AMBIGUOUS then
      begin
        R.Resolution:= PAS_RES_AMBIGUOUS;
        R.Candidates:= Hit.Ambig.Candidates;
      end
      else
        R.Resolution:= PAS_RES_MEMBER_NOT_FOUND;
    end;
    if not Cover.TryGetValue(K, Status) then
    begin
      { an unresolved To class carries nothing implicitly: unmapped, the
        conservative answer (1.28.2: it was a bare-name lookup) }
      var ToCls: TScopedClass:= if R.ToType = '' then Default(TScopedClass) else ClassOf(Inst, R.ToType, True);
      Status:= if (ToCls.Resolution = PAS_RES_RESOLVED) and Lookup(ToCls.QName, AMember).Found then PAS_USE_SAME_NAME
               else PAS_USE_UNMAPPED;
    end;
    R.Status:= Status;
    if not MigTo.TryGetValue(K, R.MigrateTo) then R.MigrateTo:= '';
    Index.Add(K, Rows.Count);
    Rows.Add(R);
    RowLines.Add(TList<Integer>.Create);
    RowLines.Last.Add(ALine);
  end;

  { G10: a member reached through 'with <inst> do' -- a ref with no receiver,
    after a with line naming a converted instance in the same routine, that
    the index resolved to the member the instance's From class declares. The
    nearest such with line above the ref owns it. Listed only; never rewritten. }
  procedure AddWithSites;
  type
    TWithAt = record
      Line     : Integer;
      Inst     : string;
      Enclosing: Int64;
    end;
  begin
    var Refs: TArray<TReference>:= AIn.Store.GetReferencesFromFile(AIn.FileId);
    var Withs: TList<TWithAt>:= TList<TWithAt>.Create;
    try
      for var Rf: TReference in Refs do
        if (Rf.StartLine >= 1) and (Rf.StartLine <= AIn.PasLines.Count) and (Rf.EnclosingSymbolId > 0) then
          for var N: string in AIn.Converted do
            if SameText(Rf.NameText, N) and WithNamesTarget(AIn.PasLines[Rf.StartLine - 1], N) then
            begin
              var W: TWithAt;
              W.Line     := Rf.StartLine;
              W.Inst     := N;
              W.Enclosing:= Rf.EnclosingSymbolId;
              Withs.Add(W);
            end;
      if Withs.Count = 0 then Exit;
      for var Rf: TReference in Refs do
      begin
        if (Rf.SymbolId <= 0) or (Rf.ReceiverText <> '') or SameText(Rf.Kind, 'member-access') then Continue;
        var Sym: TSymbol:= AIn.Store.GetSymbolById(Rf.SymbolId);
        if (Sym.Id <= 0) or not SameText(Sym.Name, Rf.NameText) or (Sym.ParentId <= 0) then Continue;
        var Owner: string:= AIn.Store.GetSymbolById(Sym.ParentId).Name;
        var Best: Integer:= -1;
        for var I: Integer:= 0 to Withs.Count - 1 do
        begin
          var W: TWithAt:= Withs[I];
          if (W.Enclosing <> Rf.EnclosingSymbolId) or (W.Line >= Rf.StartLine) then Continue;
          if (Best >= 0) and (Withs[Best].Line >= W.Line) then Continue;
          var FromT: string;
          if not AIn.FromTypes.TryGetValue(W.Inst, FromT) then Continue;
          var Cls: TScopedClass:= ClassOf(W.Inst, FromT, False);
          if Cls.Resolution <> PAS_RES_RESOLVED then Continue;
          var Hit: TMemberHit:= Lookup(Cls.QName, Rf.NameText);
          if Hit.Found and SameText(Hit.Owner, Owner) then Best:= I;
        end;
        if Best >= 0 then AddSite(Withs[Best].Inst, Rf.NameText, Rf.StartLine);
      end;
    finally
      Withs.Free;
    end;
  end;

begin
  Result:= nil;
  if (AIn.FileId <= 0) or (AIn.Converted = nil) or (AIn.Converted.Count = 0) then Exit;
  Cover   := TDictionary<string, string>.Create;
  Index   := TDictionary<string, Integer>.Create;
  Rows    := TList<TApplyPasUse>.Create;
  RowLines:= TObjectList<TList<Integer>>.Create(True);
  Hits    := TDictionary<string, TMemberHit>.Create;
  ClassMemo:= TDictionary<string, TScopedClass>.Create;
  Blocks  := InstanceConvertBlocks(AIn.Book.Rules, AIn.Converted, AIn.FromTypes);
  MigTo   := TDictionary<string, string>.Create;
  try
    for var L: TConversionRule in WithoutUnreachableRules(AIn.Book.Rules, AIn.Book.Unreachable, 0).Rules do
    begin
      if (L.Kind <> rkLink) or (L.FromPath = '') or (L.ToPath = '') then Continue;
      var Head: string:= L.FromPath;
      if Head.Contains('.') then Head:= Head.Substring(0, Head.IndexOf('.'));
      var LinkStatus: string:= LinkPasStatus(L, AIn.CastLib);
      for var N: string in ScopeFromBlocks(AIn.Converted, Blocks, LinkRuleBlock(AIn.Book.Rules, L)) do
      begin
        var K: string:= UpperCase(N + '|' + Head);
        { the strongest claim wins: cast-refused > not-rewritten > mapped }
        var Prior: string;
        if not Cover.TryGetValue(K, Prior) or (PasStatusRank(LinkStatus) > PasStatusRank(Prior)) then
          Cover.AddOrSetValue(K, LinkStatus);
      end;
    end;
    { C18 slice 1: a #migrate convert-apply realises maps its member; a #link
      covering the same member keeps its own status (PlanMigrateSites refuses
      the #migrate then) }
    for var M: TConversionRule in AIn.Book.Rules.Rules do
    begin
      if (M.Kind <> rkMigrate) or (MigrateRuleRefusal(M) <> '') then Continue;
      var MBlock: Integer:= LinkRuleBlock(AIn.Book.Rules, M);
      if MigrateIsIdentifier(AIn.Trees, M, MBlock) then Continue; { 1.38: an identifier, not a member migration }
      for var N: string in ScopeFromBlocks(AIn.Converted, Blocks, MBlock) do
        if Cover.TryAdd(UpperCase(N + '|' + M.Old), PAS_USE_MAPPED) and not SameText(M.Old, M.New) then
          MigTo.TryAdd(UpperCase(N + '|' + M.Old), M.New); { G4 }
    end;
    for var S: TAccessSite in BoundAccessSites(AIn.Store, AIn.FileId, AIn.DfmPath,
      FindMemberAccessSites(AIn.Store, AIn.FileId, AIn.PasLines, '', AIn.Converted.ToArray), Unv) do
      AddSite(S.InstanceName, S.Member, S.Line);
    AddWithSites;
    Result:= Rows.ToArray;
    for var I: Integer:= 0 to High(Result) do Result[I].Lines:= DistinctSortedLines(RowLines[I].ToArray);
    TArray.Sort<TApplyPasUse>(Result, TComparer<TApplyPasUse>.Construct(
      function(const A, B: TApplyPasUse): Integer
      begin
        Result:= CompareText(A.Instance, B.Instance);
        if Result = 0 then Result:= CompareText(A.Member, B.Member);
      end));
  finally
    MigTo.Free;
    Blocks.Free;
    ClassMemo.Free;
    Hits.Free;
    RowLines.Free;
    Rows.Free;
    Index.Free;
    Cover.Free;
  end;
end;

// C18 slice 1 (docs\superpowers\specs\2026-10-11-member-replacement-design.md):
// the '#migrate Old -> New' / '#migrate Old -> DL_NONE' rules of each #convert
// block, realised at the bound access sites of that block's converted
// instances -- the #link rename's own site discovery (FindMemberAccessSites +
// BoundAccessSites). New renames the member token; DL_NONE wraps the
// member-access expression, inst.Old -> DL_NONE(inst.Old), keeping the old
// text (owner Q2) so the unit stops compiling exactly there. Columns are
// converted from the index's UTF-8 bytes to characters, and every edit carries
// ExpectText. NEVER rewritten, each a migrate-check warning: a site the index
// cannot vouch for, a `with` naming the instance, a site whose text changed
// since it was indexed, and a whole rule MigrateRuleRefusal declines or whose
// member a #link (or an earlier #migrate) of the block already converts. An
// identifier #migrate (MigrateIsIdentifier: file scope, uses units, or an enum
// value target) is PlanIdentifierMigrates' (1.38). An already wrapped site
// gets no second wrap.
procedure PlanMigrateSites(const AIn: TPasUsesInput; const AUnitPas: string;
  out AEdits: TArray<TTextEdit>; out AItems: TArray<TApplyItem>);
var
  Blocks: TDictionary<string, Integer>;  { instance -> its #convert block }
  Taken : TDictionary<string, Integer>;  { UPPER block|member -> the book line converting it }
  Said  : TDictionary<string, Boolean>;  { UPPER line|instance -> a with block already reported }
  Unv   : TArray<TAccessSite>;
  Edits : TList<TTextEdit>;
  Items : TList<TApplyItem>;
  Conv  : TConversionRule;               { the #convert header of the block being planned }

  { every item names its block's From / To (G9) and the rule's Old member
    (G11; an applied rename or a break overrides it with the text written) }
  function Item(AKind: TApplyItemKind; AField: TApplyField; const ARule: TConversionRule;
    const AInst: string; ALine: Integer; const AText: string): TApplyItem;
  begin
    Result:= Default(TApplyItem);
    Result.Kind    := AKind;
    Result.Field   := AField;
    Result.Instance:= AInst;
    Result.FromType:= Conv.FromType;
    Result.ToType  := Conv.ToType;
    Result.FilePath:= AUnitPas;
    Result.Path    := ARule.Old;
    Result.Value   := ARule.New;
    Result.OldValue:= ARule.Old;
    Result.RuleLine:= ARule.LineNo;
    Result.Line    := ALine;
    Result.Text    := AText;
  end;

  function Check(const ARule: TConversionRule; const AInst: string; ALine: Integer; const AText: string): TApplyItem;
  begin
    Result:= Item(aikMigrateCheck, afWarnings, ARule, AInst, ALine, AText);
  end;

  { True when the text before AStart is 'DL_NONE(' -- the site is wrapped already }
  function AlreadyMarked(const ALine: string; AStart: Integer): Boolean;
  begin
    var Q: Integer:= AStart - 1;
    while (Q >= 1) and (ALine[Q] = ' ') do Dec(Q);
    if (Q < 1) or (ALine[Q] <> '(') then Exit(False);
    Dec(Q);
    while (Q >= 1) and (ALine[Q] = ' ') do Dec(Q);
    var MarkAt: Integer:= Q - Length(DL_NONE_MARK) + 1;
    Result:= (MarkAt >= 1) and SameText(Copy(ALine, MarkAt, Length(DL_NONE_MARK)), DL_NONE_MARK) and
             ((MarkAt = 1) or not IsIdentChar(ALine[MarkAt - 1]));
  end;

  { one bound site of ARule: its edit and its item }
  procedure PlanSite(const ARule: TConversionRule; const ASite: TAccessSite);
  begin
    var LineText: string:= AIn.PasLines[ASite.Line - 1];
    var MemberAt: Integer:= CharColumn(LineText, ASite.Col);
    var MemberEnd: Integer:= CharColumn(LineText, ASite.EndCol);
    var Written: string:= Copy(LineText, MemberAt, MemberEnd - MemberAt);
    var Where: string:= Format('%s:%d', [ExtractFileName(AUnitPas), ASite.Line]);
    if not SameText(Written, ARule.Old) then
    begin
      Items.Add(Check(ARule, ASite.InstanceName, ASite.Line, Format('#migrate site %s %s.%s: the line changed since it was indexed -- not rewritten',
        [Where, ASite.InstanceName, ARule.Old])));
      Exit;
    end;
    var E: TTextEdit:= Default(TTextEdit);
    E.FilePath:= AUnitPas;
    E.Kind    := tekReplaceInLine;
    E.Line    := ASite.Line;
    if not SameText(ARule.New, DL_NONE_MARK) then
    begin
      E.Col       := MemberAt;
      E.EndCol    := MemberEnd;
      E.Text      := ARule.New;
      E.ExpectText:= Written;
      Edits.Add(E);
      var It: TApplyItem:= Item(aikMigrateApplied, afAccessSites, ARule, ASite.InstanceName, ASite.Line,
        Format('%s.%s -> %s.%s (L%d, #migrate)', [ASite.InstanceName, Written, ASite.InstanceName, ARule.New, ASite.Line]));
      It.OldValue:= Written;
      Items.Add(It);
      Exit;
    end;
    var StartAt: Integer:= MemberAccessStart(LineText, MemberAt);
    if StartAt = 0 then
    begin
      Items.Add(Check(ARule, ASite.InstanceName, ASite.Line, Format('#migrate site %s %s.%s: no inst.member expression at the site -- not wrapped in DL_NONE',
        [Where, ASite.InstanceName, ARule.Old])));
      Exit;
    end;
    var Old: string:= Copy(LineText, StartAt, MemberEnd - StartAt);
    var Brk: TApplyItem:= Item(aikDeliberateBreak, afTodos, ARule, ASite.InstanceName, ASite.Line, '');
    Brk.OldValue:= Old;
    if AlreadyMarked(LineText, StartAt) then
      Brk.Text:= Format('%s: %s is already DL_NONE-marked (#migrate line %d) -- convert it by hand', [Where, Old, ARule.LineNo])
    else
    begin
      E.Col       := StartAt;
      E.EndCol    := MemberEnd;
      E.Text      := DL_NONE_MARK + '(' + Old + ')';
      E.ExpectText:= Old;
      Edits.Add(E);
      Brk.Text:= Format('%s: %s -> %s (#migrate line %d) -- a deliberate break: the unit does not compile here until it is converted by hand',
        [Where, Old, E.Text, ARule.LineNo]);
    end;
    Items.Add(Brk);
  end;

begin
  AEdits:= nil;
  AItems:= nil;
  if (AIn.FileId <= 0) or (AIn.Converted = nil) or (AIn.Converted.Count = 0) then Exit;
  Blocks:= InstanceConvertBlocks(AIn.Book.Rules, AIn.Converted, AIn.FromTypes);
  Taken := TDictionary<string, Integer>.Create;
  Said  := TDictionary<string, Boolean>.Create;
  Edits := TList<TTextEdit>.Create;
  Items := TList<TApplyItem>.Create;
  try
    { a #link that edits or refuses the member's .pas sites owns them }
    for var L: TConversionRule in AIn.Book.Rules.Rules do
    begin
      var PlainLink: Boolean:= (L.Kind = rkLink) and (L.FromPath <> '') and (L.ToPath <> '') and (Pos('.', L.FromPath) = 0);
      var Renames  : Boolean:= (Pos('.', L.ToPath) = 0) and not SameText(L.FromPath, L.ToPath);
      if PlainLink and ((L.Cast <> '') or Renames) then
        Taken.AddOrSetValue(UpperCase(IntToStr(LinkRuleBlock(AIn.Book.Rules, L)) + '|' + L.FromPath), L.LineNo);
    end;
    var Block: Integer:= 0;
    Conv:= Default(TConversionRule);
    for var R: TConversionRule in AIn.Book.Rules.Rules do
    begin
      if R.Kind = rkConvert then
      begin
        Inc(Block);
        Conv:= R;
      end;
      if (R.Kind <> rkMigrate) or MigrateIsIdentifier(AIn.Trees, R, Block) then Continue; { 1.38: PlanIdentifierMigrates }
      var Scope: TArray<string>:= ScopeFromBlocks(AIn.Converted, Blocks, Block);
      if Length(Scope) = 0 then Continue; { no instance of this block in the unit }
      var Why: string:= MigrateRuleRefusal(R);
      var Prior: Integer;
      if (Why = '') and (Taken.TryGetValue(UpperCase(IntToStr(Block) + '|' + R.Old), Prior) or
                         Taken.TryGetValue(UpperCase('0|' + R.Old), Prior)) then
        Why:= Format('book line %d already converts %s', [Prior, R.Old]);
      if Why <> '' then
      begin
        Items.Add(Check(R, '', 0, Format('line %d: #migrate %s -> %s NOT applied -- %s; convert its sites by hand',
          [R.LineNo, R.Old, R.New, Why])));
        Continue;
      end;
      Taken.Add(UpperCase(IntToStr(Block) + '|' + R.Old), R.LineNo);
      var Sites: TArray<TAccessSite>:= BoundAccessSites(AIn.Store, AIn.FileId, AIn.DfmPath,
        FindMemberAccessSites(AIn.Store, AIn.FileId, AIn.PasLines, R.Old, Scope), Unv);
      for var U: TAccessSite in Unv do
        Items.Add(Check(R, U.InstanceName, U.Line, Format('#migrate site %s:%d %s.%s not verified against the index -- not rewritten',
          [ExtractFileName(AUnitPas), U.Line, U.InstanceName, R.Old])));
      for var LineNo: Integer:= 1 to AIn.PasLines.Count do
        for var N: string in Scope do
          if WithNamesTarget(AIn.PasLines[LineNo - 1], N) and Said.TryAdd(UpperCase(IntToStr(LineNo) + '|' + N), True) then
            Items.Add(Check(R, N, LineNo, Format('#migrate site %s:%d with %s do ... not verified against the index -- ' +
              'a member reached through a with block is not rewritten; convert it by hand', [ExtractFileName(AUnitPas), LineNo, N])));
      if SameText(R.Old, R.New) then Continue; { identity: nothing to rename }
      for var S: TAccessSite in Sites do PlanSite(R, S);
    end;
    AEdits:= Edits.ToArray;
    AItems:= Items.ToArray;
  finally
    Items.Free;
    Edits.Free;
    Said.Free;
    Taken.Free;
    Blocks.Free;
  end;
end;

// 1.38 (D2): the index just past the comment that opened before AI of ALine
// (ABrace: '{...}', else '(*...*)'); 0 when it does not close on this line.
function PasCommentEnd(const ALine: string; AI: Integer; ABrace: Boolean): Integer;
begin
  var P: Integer:= if ABrace then PosEx('}', ALine, AI) else PosEx('*)', ALine, AI);
  Result:= if P = 0 then 0 else P + (if ABrace then 1 else 2);
end;

// 1.38 (D2): the index just past the string literal whose opening quote is at
// AI of ALine ('' inside it is an escaped quote).
function PasQuotedEnd(const ALine: string; AI: Integer): Integer;
begin
  Result:= AI + 1;
  while Result <= Length(ALine) do
    if ALine[Result] <> '''' then Inc(Result)
    else if (Result < Length(ALine)) and (ALine[Result + 1] = '''') then Inc(Result, 2)
    else Exit(Result + 1);
end;

type
  // 1.38 (D2): one identifier token -- its 1-based line, first column and the
  // column past its end (characters).
  TPasIdentToken = record
    Line, Col, EndCol: Integer;
  end;

// 1.38 (D2): every identifier token of ALines outside comments ({...},
// (*...*), //...), compiler directives and string literals; char / hex /
// number literals and escaped &identifiers are skipped.
function ScanPasIdentifiers(const ALines: TStringList): TArray<TPasIdentToken>;
begin
  var Found: TList<TPasIdentToken>:= TList<TPasIdentToken>.Create;
  try
    var Open: Integer:= 0; // 0 none, 1 a brace comment, 2 a paren-star comment
    for var LineNo: Integer:= 1 to ALines.Count do
    begin
      var S: string:= ALines[LineNo - 1];
      var I: Integer:= 1;
      while I <= Length(S) do
      begin
        if Open <> 0 then
        begin
          var Past: Integer:= PasCommentEnd(S, I, Open = 1);
          if Past = 0 then Break;
          I   := Past;
          Open:= 0;
          Continue;
        end;
        var Two: string:= Copy(S, I, 2);
        if Two = '//' then Break;
        if S[I] = '{' then
        begin
          Open:= 1;
          Inc(I);
        end
        else if Two = '(*' then
        begin
          Open:= 2;
          Inc(I, 2);
        end
        else if S[I] = '''' then I:= PasQuotedEnd(S, I)
        else if CharInSet(S[I], ['#', '$', '&', '0'..'9', 'A'..'Z', 'a'..'z', '_']) then
        begin
          var Tok: TPasIdentToken;
          Tok.Line:= LineNo;
          Tok.Col := I;
          Inc(I);
          while (I <= Length(S)) and IsIdentChar(S[I]) do Inc(I);
          Tok.EndCol:= I;
          if CharInSet(S[Tok.Col], ['A'..'Z', 'a'..'z', '_']) then Found.Add(Tok);
        end
        else Inc(I);
      end;
    end;
    Result:= Found.ToArray;
  finally
    Found.Free;
  end;
end;
type
  // 1.38 (D2): one identifier PlanIdentifierMigrates renames -- a rule's own
  // Old, or an enum member its type #migrate maps by name.
  TIdentMigrate = record
    Old, New : string;
    FromType : string;          { the rule's Old type (an enum member: its enum) }
    ToType   : string;          { the rule's New }
    UsesType : string;          { the declaration whose unit the uses clause needs }
    Qualifier: string;          { the From enum a member may be qualified with }
    Refusal  : string;          { '' renames; else why each site is a warning }
    ByName   : Boolean;         { mapped by EnumMemberStem, not by a book line }
    Rule     : TConversionRule;
  end;

// 1.38 (owner ruling D2, 2026-10-28; INBOX converter-to-engine-migrate-type
// Q1): the identifier #migrate rules (MigrateIsIdentifier) realised in the
// unit's CODE. Every bare identifier token Old outside comments, string
// literals and directives -- a var / param / field / result type, a cast, an
// `is` / `as` operand, a generic argument, an enum literal -- becomes New.
// The target must resolve in a supplied store (ResolveMigrateTarget). A type
// #migrate between two enums also maps each From member to the To member with
// the same EnumMemberStem (never by ordinal); an explicit #migrate line for a
// member overrides that. NEVER silent: a site that is not renamed is a
// migrate-check warning -- the target resolves nowhere, the member has no
// counterpart, Old is declared in this unit or a #convert converts it, or the
// site is qualified (Unit.Old; only From-enum qualification is renamed).
// The From side is trusted, not resolved: a type no index knows is renamed
// all the same (its members are then mapped only by explicit lines, said
// once). AUsesTypes are the declarations whose unit the uses clause needs,
// AIntfTypes those with a site in the interface section.
procedure PlanIdentifierMigrates(const AIn: TPasUsesInput; const AUnitPas: string;
  out AEdits: TArray<TTextEdit>; out AItems: TArray<TApplyItem>; out AUsesTypes, AIntfTypes: TArray<string>);
var
  Map  : TDictionary<string, TIdentMigrate>;  { UPPER Old -> its rename }
  Own  : TDictionary<string, Boolean>;        { UPPER names this unit declares }
  Enums: TList<TIdentMigrate>;                { type rules whose New is an enum }
  Edits: TList<TTextEdit>;
  Items: TList<TApplyItem>;
  UsesT: TList<string>;
  IntfT: TList<string>;
  ImplLine: Integer;

  function Item(AKind: TApplyItemKind; AField: TApplyField; const AM: TIdentMigrate; ALine: Integer;
    const AText: string): TApplyItem;
  begin
    Result:= Default(TApplyItem);
    Result.Kind    := AKind;
    Result.Field   := AField;
    Result.FromType:= AM.FromType;
    Result.ToType  := AM.ToType;
    Result.FilePath:= AUnitPas;
    Result.Path    := AM.Old;
    Result.Value   := AM.New;
    Result.OldValue:= AM.Old;
    Result.RuleLine:= AM.Rule.LineNo;
    Result.Line    := ALine;
    Result.Text    := AText;
  end;

  { the explicit rule R as a map entry (its refusal, if any, decided here) }
  procedure AddRule(const R: TConversionRule);
  var
    M  : TIdentMigrate;
    Sym: TSymbol;
    St : ISymbolStore;
  begin
    M  := Default(TIdentMigrate);
    Sym:= Default(TSymbol);
    St := nil;
    M.Old     := R.Old;
    M.New     := R.New;
    M.FromType:= R.Old;
    M.ToType  := R.New;
    M.Rule    := R;
    if R.Scope <> '' then M.Refusal:= 'a scoped #migrate (Class: / obj.) is not applied yet'
    else if not IsValidIdent(R.Old) then M.Refusal:= 'only a plain identifier is migrated; call and assignment forms are not applied yet'
    else if R.New = '' then M.Refusal:= 'it names no replacement'
    else if SameText(R.New, DL_NONE_MARK) then M.Refusal:= 'DL_NONE marks member sites; an identifier #migrate needs a replacement'
    else if not IsValidIdent(R.New, True) then M.Refusal:= 'replacement templates are not applied yet'
    else if Own.ContainsKey(UpperCase(R.Old)) then M.Refusal:= Format('%s is declared in this unit', [R.Old])
    else if not ResolveMigrateTarget(AIn.Trees, R.New, Sym, St) then
      M.Refusal:= Format('the target %s resolves in no supplied index (library or project)', [R.New]);
    for var C: TConversionRule in AIn.Book.Rules.Rules do
      if (M.Refusal = '') and (C.Kind = rkConvert) and SameText(BareTypeTail(C.FromType), R.Old) then
        M.Refusal:= Format('book line %d converts %s', [C.LineNo, R.Old]);
    if not IsValidIdent(R.Old) then
    begin
      { no token to find: the rule itself is the warning }
      Items.Add(Item(aikMigrateCheck, afWarnings, M, 0, Format('line %d: #migrate %s -> %s NOT applied -- %s; convert its sites by hand',
        [R.LineNo, R.Old, R.New, M.Refusal])));
      Exit;
    end;
    if M.Refusal = '' then
    begin
      M.New     := Sym.Name;
      M.UsesType:= Sym.Name;
      if Sym.Kind = skEnumValue then
      begin
        { the enum the value belongs to: Unit.TEnum.member -> TEnum }
        var Q: string:= Sym.QualifiedName;
        M.UsesType:= BareTypeTail(Copy(Q, 1, LastDelimiter('.', Q) - 1));
      end;
      if Sym.Kind = skEnum then Enums.Add(M);
    end;
    if not Map.TryAdd(UpperCase(M.Old), M) then
      Items.Add(Item(aikMigrateCheck, afWarnings, M, 0, Format('line %d: #migrate %s -> %s NOT applied -- book line %d already migrates %s',
        [R.LineNo, R.Old, R.New, Map[UpperCase(M.Old)].Rule.LineNo, R.Old])));
  end;

  { the members of the enum type rule AT, mapped by stem unless a line maps them }
  procedure AddMembers(const AT: TIdentMigrate);
  var
    FromSym, ToSym: TSymbol;
    FromSt, ToSt  : ISymbolStore;
  begin
    if not (ResolveMigrateTarget(AIn.Trees, AT.Old, FromSym, FromSt) and (FromSym.Kind = skEnum)) then
    begin
      Items.Add(Item(aikMigrateCheck, afWarnings, AT, 0, Format('line %d: #migrate %s -> %s: %s resolves in no supplied index, so its enum ' +
        'members are not mapped by name -- only explicit #migrate member lines rename them', [AT.Rule.LineNo, AT.Old, AT.New, AT.Old])));
      Exit;
    end;
    ResolveMigrateTarget(AIn.Trees, AT.New, ToSym, ToSt);
    var ToMembers: TArray<TSymbol>:= ToSt.FindAllChildSymbols(ToSym.Id);
    for var FM: TSymbol in FromSt.FindAllChildSymbols(FromSym.Id) do
    begin
      if FM.Kind <> skEnumValue then Continue;
      var Prior: TIdentMigrate;
      if Map.TryGetValue(UpperCase(FM.Name), Prior) then
      begin
        { an explicit line wins; it may be qualified with the From enum too }
        if Prior.Qualifier = '' then
        begin
          Prior.Qualifier:= AT.Old;
          Map[UpperCase(FM.Name)]:= Prior;
        end;
        Continue;
      end;
      var M: TIdentMigrate:= AT;
      M.Old      := FM.Name;
      M.New      := '';
      M.Qualifier:= AT.Old;
      M.ByName   := True;
      var Stem: string:= EnumMemberStem(FM.Name);
      var Hits: Integer:= 0;
      for var TM: TSymbol in ToMembers do
        if (TM.Kind = skEnumValue) and (Stem <> '') and SameText(EnumMemberStem(TM.Name), Stem) then
        begin
          Inc(Hits);
          M.New:= TM.Name;
        end;
      if Hits <> 1 then
      begin
        M.New:= '';
        M.Refusal:= Format('enum member %s of %s has %s in %s by its name after the lowercase prefix ("%s"); add #migrate %s -> <member>',
          [FM.Name, AT.Old, if Hits = 0 then 'no counterpart' else Format('%d counterparts', [Hits]), AT.New, Stem, FM.Name]);
      end;
      Map.Add(UpperCase(FM.Name), M);
    end;
  end;

  { one identifier token Tok of line ALineNo at [AStart, AEnd) }
  procedure Site(ALineNo, AStart, AEnd: Integer; const ALine, ATok: string);
  var
    M: TIdentMigrate;
    E: TTextEdit;
  begin
    if (ImplLine = 0) and SameText(ATok, 'implementation') then ImplLine:= ALineNo;
    if not Map.TryGetValue(UpperCase(ATok), M) then Exit;
    var Where: string:= Format('%s:%d', [ExtractFileName(AUnitPas), ALineNo]);
    { Unit.Old / obj.Old: only From-enum qualification renames (never a range '..') }
    var Q: Integer:= AStart - 1;
    while (Q >= 1) and (ALine[Q] = ' ') do Dec(Q);
    if (Q >= 2) and (ALine[Q] = '.') and (ALine[Q - 1] <> '.') then
    begin
      var QEnd: Integer:= Q - 1;
      while (QEnd >= 1) and (ALine[QEnd] = ' ') do Dec(QEnd);
      var QStart: Integer:= QEnd;
      while (QStart > 1) and IsIdentChar(ALine[QStart - 1]) do Dec(QStart);
      var Qual: string:= Copy(ALine, QStart, QEnd - QStart + 1);
      if (M.Qualifier = '') or not SameText(Qual, M.Qualifier) then
      begin
        Items.Add(Item(aikMigrateCheck, afWarnings, M, ALineNo, Format('#migrate site %s %s.%s is qualified -- not renamed; convert it by hand',
          [Where, Qual, ATok])));
        Exit;
      end;
    end;
    if M.Refusal <> '' then
    begin
      Items.Add(Item(aikMigrateCheck, afWarnings, M, ALineNo, Format('#migrate site %s %s NOT renamed -- %s', [Where, ATok, M.Refusal])));
      Exit;
    end;
    if ATok = M.New then Exit; { already the target spelling }
    E:= Default(TTextEdit);
    E.FilePath  := AUnitPas;
    E.Kind      := tekReplaceInLine;
    E.Line      := ALineNo;
    E.Col       := AStart;
    E.EndCol    := AEnd;
    E.Text      := M.New;
    E.ExpectText:= ATok;
    Edits.Add(E);
    var It: TApplyItem:= Item(aikMigrateApplied, afAccessSites, M, ALineNo, Format('%s -> %s (L%d, #migrate line %d%s)',
      [ATok, M.New, ALineNo, M.Rule.LineNo, if M.ByName then ', enum member by name' else '']));
    It.OldValue:= ATok;
    Items.Add(It);
    if not MatchText(M.UsesType, UsesT.ToArray) then UsesT.Add(M.UsesType);
    if (ImplLine = 0) and not MatchText(M.UsesType, IntfT.ToArray) then IntfT.Add(M.UsesType);
  end;

begin
  AEdits    := nil;
  AItems    := nil;
  AUsesTypes:= nil;
  AIntfTypes:= nil;
  if (AIn.PasLines = nil) or (AIn.Trees = nil) then Exit;
  Map  := TDictionary<string, TIdentMigrate>.Create;
  Own  := TDictionary<string, Boolean>.Create;
  Enums:= TList<TIdentMigrate>.Create;
  Edits:= TList<TTextEdit>.Create;
  Items:= TList<TApplyItem>.Create;
  UsesT:= TList<string>.Create;
  IntfT:= TList<string>.Create;
  try
    var Block: Integer:= 0;
    var Any  : Boolean:= False;
    for var R: TConversionRule in AIn.Book.Rules.Rules do
    begin
      if R.Kind = rkConvert then Inc(Block);
      if not MigrateIsIdentifier(AIn.Trees, R, Block) then Continue;
      if not Any and (AIn.Store <> nil) then
        for var S: TSymbol in AIn.Store.FindSymbolsByFile(AUnitPas) do Own.AddOrSetValue(UpperCase(S.Name), True);
      Any:= True;
      AddRule(R);
    end;
    if not Any then Exit;
    for var T: TIdentMigrate in Enums do AddMembers(T);
    ImplLine:= 0;
    for var Tok: TPasIdentToken in ScanPasIdentifiers(AIn.PasLines) do
    begin
      var Ln: string:= AIn.PasLines[Tok.Line - 1];
      Site(Tok.Line, Tok.Col, Tok.EndCol, Ln, Copy(Ln, Tok.Col, Tok.EndCol - Tok.Col));
    end;
    AEdits    := Edits.ToArray;
    AItems    := Items.ToArray;
    AUsesTypes:= UsesT.ToArray;
    AIntfTypes:= IntfT.ToArray;
  finally
    IntfT.Free;
    UsesT.Free;
    Items.Free;
    Edits.Free;
    Enums.Free;
    Own.Free;
    Map.Free;
  end;
end;

// 1.27.0: apply/1 pas_uses[] global rows -- the reconciliation's dangling
// verdicts, sorted by name.
function DanglingPasUses(const ADangling: TArray<TUsesDangling>): TArray<TApplyPasUse>;
begin
  Result:= nil;
  for var D: TUsesDangling in ADangling do
  begin
    var R: TApplyPasUse:= Default(TApplyPasUse);
    R.Member       := D.Name;
    R.Kind         := if D.KindKnown then PasUseKind(D.Kind, D.Name, D.DeclaredIn <> '') else '';
    R.Resolution   := if R.Kind <> '' then PAS_RES_RESOLVED else PAS_RES_KIND_UNKNOWN;
    R.DeclaringUnit:= D.DeclUnit;
    R.DeclaredIn   := D.DeclaredIn;
    R.Status       := PAS_USE_GLOBAL_DANGLING;
    R.Lines        := D.Lines;
    Result:= Result + [R];
  end;
  TArray.Sort<TApplyPasUse>(Result, TComparer<TApplyPasUse>.Construct(
    function(const A, B: TApplyPasUse): Integer
    begin
      Result:= CompareText(A.Member, B.Member);
    end));
end;
// 1.27.0 (C15): the .dfm half of a VALUE cast as items -- one
// value-cast-applied per rewritten value (Value the new literal, OldValue the
// old), one value-cast-check per value that is not ONE string literal. Line is
// the property's own line in the instance's block when it is found there,
// else the block header.
function ValueCastDfmItems(const AVCs: TArray<TReemitValueCast>; const AInst: TConvertInstance;
  const ADfmPath: string; const ADfmLines: TArray<string>; ABlockLine: Integer): TArray<TApplyItem>;
const
  BLOCK_END = 'end';
begin
  Result:= nil;
  for var VC: TReemitValueCast in AVCs do
  begin
    var It: TApplyItem:= Default(TApplyItem);
    It.Instance:= AInst.InstanceName;
    It.FromType:= AInst.FromType;
    It.ToType  := AInst.ToType;
    It.FilePath:= ADfmPath;
    It.Path    := VC.FromPath;
    It.RuleLine:= VC.RuleLine;
    It.Line    := ABlockLine;
    if (ABlockLine >= 1) and (ABlockLine <= Length(ADfmLines)) then
    begin
      var Indent: string:= LeadingIndent(ADfmLines[ABlockLine - 1]);
      for var I: Integer:= ABlockLine to High(ADfmLines) do
      begin
        if (LeadingIndent(ADfmLines[I]) = Indent) and SameText(Trim(ADfmLines[I]), BLOCK_END) then Break;
        if StartsText(VC.FromPath + ' =', Trim(ADfmLines[I])) then
        begin
          It.Line:= I + 1;
          Break;
        end;
      end;
    end;
    if VC.Changed then
    begin
      It.Kind    := aikValueCastApplied;
      It.Field   := afAccessSites; { done work, but not an instance line: converted[] counts instances }
      It.OldValue:= VC.OldValue;
      It.Value   := VC.NewValue;
      It.Text    := Format('%s: value cast %s: %s %s -> %s (.dfm line %d)',
        [AInst.InstanceName, VC.CastName, VC.ToPath, VC.OldValue, VC.NewValue, It.Line]);
    end
    else
    begin
      It.Kind := aikValueCastCheck;
      It.Field:= afWarnings;
      It.Value:= VC.OldValue;
      It.Text := Format('line %d: warning: %s: value cast %s: %s = %s is not one string literal, check by hand',
        [It.Line, AInst.InstanceName, VC.CastName, VC.FromPath, Trim(VC.OldValue)]);
    end;
    Result:= Result + [It];
  end;
end;

type
  // 1.27.0 (C15): what the code at a value-cast access site does with the member.
  TValueCastSiteKind = (vskLiteral, vskNonLiteral, vskRead);

// 1.27.0 (C15): the column just past the string literal opening at AStart in
// AText ('' a doubled quote), or 0 when the line ends before it closes.
function LiteralEnd(const AText: string; AStart: Integer): Integer;
const
  Q = '''';
var
  P: Integer;
begin
  Result:= 0;
  P:= AStart + 1;
  while (P <= Length(AText)) and (Result = 0) do
    if (AText[P] = Q) and (P < Length(AText)) and (AText[P + 1] = Q) then Inc(P, 2)
    else
    begin
      if AText[P] = Q then Result:= P + 1;
      Inc(P);
    end;
end;

// 1.27.0 review fix wave: the column of the first character at or after AP in
// AText that is neither a blank (space, tab) nor inside a comment closed on
// the same line ({..}, (*..*)). A '//' comment, or one left open, runs to the
// end of the line: Length(AText) + 1 is returned.
function SkipBlanksAndComments(const AText: string; AP: Integer): Integer;
const
  PAREN_STAR_OPEN  = '(*';
  PAREN_STAR_CLOSE = '*)';
  LINE_COMMENT     = '//';
begin
  Result:= AP;
  while Result <= Length(AText) do
  begin
    if CharInSet(AText[Result], [' ', #9]) then Inc(Result)
    else if AText[Result] = '{' then
    begin
      var Close: Integer:= Pos('}', AText, Result + 1);
      if Close = 0 then Exit(Length(AText) + 1);
      Result:= Close + 1;
    end
    else if Copy(AText, Result, Length(PAREN_STAR_OPEN)) = PAREN_STAR_OPEN then
    begin
      var Close: Integer:= Pos(PAREN_STAR_CLOSE, AText, Result + Length(PAREN_STAR_OPEN));
      if Close = 0 then Exit(Length(AText) + 1);
      Result:= Close + Length(PAREN_STAR_CLOSE);
    end
    else if Copy(AText, Result, Length(LINE_COMMENT)) = LINE_COMMENT then Exit(Length(AText) + 1)
    else Exit;
  end;
end;

// 1.27.0 (C15): a `:=` whose right-hand side is ONE string literal (its
// [ALitCol, ALitEnd) span returned), any other assignment, or a read. Review
// fix wave: STRICT -- the literal must be followed, on the SAME line, by
// nothing but blanks / closed comments and then ';'. A literal that ends the
// line (a continuation may follow, even behind a comment line), one followed
// by '#nn', '+', a comment running to the line end, or a statement ended by
// `else` / `end` without ';' is vskNonLiteral, never rewritten. Blanks, tabs
// and closed comments between the member and ':=' are allowed.
function ClassifyValueCastSite(const APasLines: TStringList; ALine, ACol: Integer;
  out ALitCol, ALitEnd: Integer): TValueCastSiteKind;
const
  ASSIGN_OP = ':=';
  QUOTE     = '''';
  STMT_END  = ';';
var
  S: string;
  P: Integer;
begin
  ALitCol:= 0;
  ALitEnd:= 0;
  if (ALine < 1) or (ALine > APasLines.Count) then Exit(vskRead);
  S:= APasLines[ALine - 1];
  P:= CharColumn(S, ACol); { C18: ACol is the index's UTF-8 byte column }
  while (P <= Length(S)) and IsIdentChar(S[P]) do Inc(P);
  P:= SkipBlanksAndComments(S, P);
  if Copy(S, P, Length(ASSIGN_OP)) <> ASSIGN_OP then Exit(vskRead);
  Result:= vskNonLiteral;
  P:= SkipBlanksAndComments(S, P + Length(ASSIGN_OP));
  if (P > Length(S)) or (S[P] <> QUOTE) or (LiteralEnd(S, P) = 0) then Exit;
  var LitEnd: Integer:= LiteralEnd(S, P);
  var After: Integer:= SkipBlanksAndComments(S, LitEnd);
  if (After > Length(S)) or (S[After] <> STMT_END) then Exit;
  ALitCol:= P;
  ALitEnd:= LitEnd;
  Result := vskLiteral;
end;
// 1.27.0 (C15): the .pas half of a VALUE cast for one #link: each bound site
// whose assignment has ONE string-literal right-hand side ending the statement
// on its line (ClassifyValueCastSite) gets that literal
// rewritten when the transform changes it (an identity link only); every
// other assignment and every read gets no edit and a value-cast-check
// warning naming its line. A literal the transform leaves alone: nothing.
procedure PlanValueCastSites(const ASites: TArray<TAccessSite>; const ALink: TConversionRule;
  const ADef: TCastDef; const AUnitPas: string; const APasLines: TStringList;
  out AEdits: TArray<TTextEdit>; out AItems: TArray<TApplyItem>);
var
  LitCol, LitEnd: Integer;
  NewLit        : string;
  Why           : string;
begin
  AEdits:= nil;
  AItems:= nil;
  var Renamed: Boolean:= not SameText(ALink.ToPath, ALink.FromPath);
  for var S: TAccessSite in ASites do
  begin
    var It: TApplyItem:= Default(TApplyItem);
    It.Instance:= S.InstanceName;
    It.FilePath:= AUnitPas;
    It.Path    := ALink.FromPath;
    It.RuleLine:= ALink.LineNo;
    It.Line    := S.Line;
    Why:= '';
    case ClassifyValueCastSite(APasLines, S.Line, S.Col, LitCol, LitEnd) of
      vskRead      : Why:= Format('read of %s', [ALink.FromPath]);
      vskNonLiteral: Why:= 'non-literal assignment';
      vskLiteral:
        begin
          var Lit: string:= Copy(APasLines[S.Line - 1], LitCol, LitEnd - LitCol);
          if ApplyValueCast(ADef, Lit, NewLit) <> vcoChanged then Continue;
          if Renamed then Why:= 'renamed link, the literal is not rewritten'
          else
          begin
            var E: TTextEdit:= Default(TTextEdit);
            E.FilePath:= AUnitPas;
            E.Kind    := tekReplaceInLine;
            E.Line    := S.Line;
            E.Col     := LitCol;
            E.EndCol  := LitEnd;
            E.Text    := NewLit;
            AEdits:= AEdits + [E];
            It.Kind    := aikValueCastApplied;
            It.Field   := afAccessSites;
            It.OldValue:= Lit;
            It.Value   := NewLit;
            It.Text    := Format('line %d: #link %s <- %s : %s -- %s:%d %s.%s := %s -> %s',
              [ALink.LineNo, ALink.ToPath, ALink.FromPath, ALink.Cast, ExtractFileName(AUnitPas), S.Line,
               S.InstanceName, ALink.FromPath, Lit, NewLit]);
          end;
        end;
    end;
    if Why <> '' then
    begin
      It.Kind := aikValueCastCheck;
      It.Field:= afWarnings;
      It.Value:= ALink.Cast;
      It.Text := Format('line %d: warning: %s:%d %s.%s -- value cast %s: %s, check by hand',
        [ALink.LineNo, ExtractFileName(AUnitPas), S.Line, S.InstanceName, ALink.FromPath, ALink.Cast, Why]);
    end;
    AItems:= AItems + [It];
  end;
end;

// 1.27.0 review fix wave: the .pas references to a value-cast link's member
// that the access-site binding did NOT resolve to a converted instance -- a
// `with X do TableName := ...` (no receiver at the site), a receiver the index
// cannot vouch for, any other object's same-named member. The .dfm value is
// rewritten regardless, so each is a value-cast-check warning naming its line,
// never an edit and never silence. One item per (line, column); ABound are the
// sites PlanValueCastSites already reports. A dotted FromPath has no single
// member token and yields nothing here (pas_uses says not-rewritten).
function UnresolvedValueCastSites(const AStore: ISymbolStore; AFileId: Int64; const AUnitPas: string;
  const ALink: TConversionRule; const ABound: TArray<TAccessSite>): TArray<TApplyItem>;
var
  Seen: TDictionary<Int64, Boolean>;
  Items: TList<TApplyItem>;

  function PosKey(ALine, ACol: Integer): Int64;
  const
    LINE_SHIFT = 32; { the line in the high 32 bits, the column in the low }
  begin
    Result:= (Int64(ALine) shl LINE_SHIFT) or Cardinal(ACol);
  end;

begin
  Result:= nil;
  if (AFileId <= 0) or (ALink.FromPath = '') or (Pos('.', ALink.FromPath) > 0) then Exit;
  Seen := TDictionary<Int64, Boolean>.Create;
  Items:= TList<TApplyItem>.Create;
  try
    for var B: TAccessSite in ABound do Seen.AddOrSetValue(PosKey(B.Line, B.Col), True);
    for var R: TReference in AStore.GetReferencesFromFile(AFileId) do
    begin
      if not SameText(R.NameText, ALink.FromPath) or Seen.ContainsKey(PosKey(R.StartLine, R.StartCol)) then Continue;
      Seen.Add(PosKey(R.StartLine, R.StartCol), True);
      var It: TApplyItem:= Default(TApplyItem);
      It.Kind    := aikValueCastCheck;
      It.Field   := afWarnings;
      It.Instance:= R.ReceiverText;
      It.FilePath:= AUnitPas;
      It.Path    := ALink.FromPath;
      It.RuleLine:= ALink.LineNo;
      It.Line    := R.StartLine;
      It.Value   := ALink.Cast;
      It.Text    := Format('line %d: warning: %s:%d %s -- value cast %s: the receiver is not resolved to a converted ' +
        'instance (a with block, or a site the index cannot vouch for), not rewritten; the .dfm value is, check by hand',
        [ALink.LineNo, ExtractFileName(AUnitPas), R.StartLine,
         (if R.ReceiverText <> '' then R.ReceiverText + '.' + ALink.FromPath else ALink.FromPath), ALink.Cast]);
      Items.Add(It);
    end;
    Result:= Items.ToArray;
  finally
    Items.Free;
    Seen.Free;
  end;
end;
// C8 N2: the 'retyped' entries of AInherited as instances for BuildApplyPlan's
// loop -- the .dfm spelling of the From type, the bare To type.
function RetypedInstances(const AInherited: TArray<TInheritedInstance>): TArray<TConvertInstance>;
begin
  Result:= nil;
  for var Inh: TInheritedInstance in AInherited do
    if Inh.Action = INH_ACTION_RETYPED then
    begin
      var Inst: TConvertInstance:= Default(TConvertInstance);
      Inst.InstanceName:= Inh.Name;
      Inst.FromType    := Inh.TypeName;
      Inst.ToType      := Inh.ToType;
      Result:= Result + [Inst];
    end;
end;

// The index of AInherited's entry named AName with action AAction, or -1.
// Component names are unique within a form, so an own instance never shares
// its name with an inherited one.
function InheritedIndexOf(const AInherited: TArray<TInheritedInstance>; const AName, AAction: string): Integer;
begin
  for var K: Integer:= 0 to High(AInherited) do
    if (AInherited[K].Action = AAction) and SameText(AInherited[K].Name, AName) then Exit(K);
  Result:= -1;
end;

// True when some AInherited entry has action AAction.
function HasInheritedAction(const AInherited: TArray<TInheritedInstance>; const AAction: string): Boolean;
begin
  for var Inh: TInheritedInstance in AInherited do
    if Inh.Action = AAction then Exit(True);
  Result:= False;
end;

class function TApplyBook.Create(const ARules: TConversionRuleSet;
  const AUnreachable: TArray<TUnreachablePath>): TApplyBook;
begin
  Result            := Default(TApplyBook);
  Result.Rules      := ARules;
  Result.Unreachable:= AUnreachable;
end;

// 1.25.1: AEdits less every in-line edit (tekReplaceInLine / tekInsertInLine)
// that repeats an earlier one exactly -- same file, line, columns and text.
// Two #convert blocks carrying the same renaming #link (Title <- Caption on a
// table and on its fields), or two instances of one type sharing a creator
// site, planned the identical rewrite twice; applied twice, the second splice
// lands on the already-rewritten line and corrupts it ('tbl.Title= tblID.Title
// tbl2ID.Title'). Line deletes and inserts are kept as they are: a repeated
// block edit is an overlap the all-or-nothing guard must see. Order kept.
function DistinctInLineEdits(const AEdits: TArray<TTextEdit>): TArray<TTextEdit>;
var
  Seen: TDictionary<string, Boolean>;
  Key : string;
begin
  Result:= nil;
  Seen  := TDictionary<string, Boolean>.Create;
  try
    for var Ed: TTextEdit in AEdits do
    begin
      if Ed.Kind in [tekReplaceInLine, tekInsertInLine] then
      begin
        Key:= Format('%s|%d|%d|%d|%d|%s', [UpperCase(Ed.FilePath), Ord(Ed.Kind), Ed.Line, Ed.Col, Ed.EndCol, Ed.Text]);
        if Seen.ContainsKey(Key) then Continue;
        Seen.Add(Key, True);
      end;
      Result:= Result + [Ed];
    end;
  finally
    Seen.Free;
  end;
end;

function BuildApplyPlan(const ATrees: TConvertTreeCache; const AUnitPas, ADfmPath: string;  // dl:ok too-many-parameters@3d90, method-too-long@b578, too-many-locals@ddbd -- (308 lines: +the C18 #migrate hook, PlanMigrateSites itself lives outside it; +InstToType and the 1.27.0 pas_uses input record, the surfaces themselves live outside it): parameters -- the eighth is the unit's inherited[] entries (C8 N2), per-unit and updated in place, while the book and the cast library are per-run, so no existing record fits it; length -- 264 lines at 1.25.0, 272 at 1.25.1, 276 with C8 N2 (each addition a one-line hook into a nested routine); every surface is already its own nested routine and the remaining body is the per-instance loop, whose split is a refactor of its own; locals -- one per output surface + per-unit views, shared by the nested routines (same refactor)
  const ABook: TApplyBook; const AOnly: TArray<string>;
  const ACastLib: TCastLib; AWarnUnlinked: Boolean;
  var AInherited: TArray<TInheritedInstance>): TApplyResult;
var
  Stores      : TArray<ISymbolStore>; { ATrees.Stores, in --db order }
  DfmText     : string;
  DfmLines    : TArray<string>;
  DfmFileSyms : TArray<TSymbol>;
  Instances   : TArray<TConvertInstance>;
  Inst        : TConvertInstance;
  Edits       : TList<TTextEdit>;
  Converted   : TList<string>;
  Warnings    : TList<string>;
  ReemitNotes : TList<string>;
  CreatorSites: TList<string>;
  AccessSites : TList<string>;
  Todos       : TList<string>;
  Items       : TList<TApplyItem>; { the typed mirror of the six lists above -- see Emit }
  { NOT a mirror of anything -- its own surface, written only by EmitResolved. }
  ResolvedDefaults: TList<TApplyResolvedDefault>;
  PasLines    : TStringList;
  PasFileSyms : TArray<TSymbol>;
  PasFileId   : Int64;
  PasStore    : ISymbolStore; { the store that actually has AUnitPas indexed -- see StoreForFile }
  DoneUnits   : TDictionary<string, Boolean>; { ToType -> already handled (added or already-used) }
  ToTypesSeen : TList<string>;
  IntfToTypes : TDictionary<string, Boolean>; { ToType -> a retyped field of it is declared in the INTERFACE (C13 a) }
  ConvertedInstNames: TList<string>; { instances that survived the .dfm re-emit -- see surface #4 remarks below }
  InstFromType: TDictionary<string, string>; { 1.26.1: converted instance -> its From type, to pick its #convert block }
  InstToType  : TDictionary<string, string>; { 1.27.0: converted instance -> its To type (pas_uses[]) }
  RefFacts    : TRefFacts; { 1.26.5: the project's .dfm values, borrowed from ATrees; nil until a #check-ref needs it }
  RefFactRows : Integer; { 1.26.5: dfm-prop rows RefFacts was built from; 0 = no facts to check against }
  RefFactsAsked: Boolean; { 1.26.5: BuildRefFacts has run for this unit }
  E           : TTextEdit;
  It          : TApplyItem; { scratch for the main body's own Emit calls }


  // Resolves the store (from Stores, in order) that actually has APath
  // indexed (FindSymbolsByFile non-empty, trying both the given and the
  // fully-qualified path) -- the .pas/.dfm pair being converted may live in a
  // DIFFERENT --db than the From/To types (Bug 2). Falls back to Stores[0]
  // when no store has APath indexed, preserving the prior single-db error
  // paths (a subsequent Length(...)=0 still produces the existing "could not
  // locate" warnings rather than a new failure mode).
  function StoreForFile(const APath: string): ISymbolStore;
  var
    St  : ISymbolStore;
    Syms: TArray<TSymbol>;
  begin
    for St in Stores do
    begin
      Syms:= St.FindSymbolsByFile(APath);
      if Length(Syms) = 0 then Syms:= St.FindSymbolsByFile(TPath.GetFullPath(APath));
      if Length(Syms) > 0 then Exit(St);
    end;
    if Length(Stores) > 0 then Exit(Stores[0]);
    Result:= nil;
  end;


  // Appends ONE report line: the prose to whichever legacy array AItem.Field
  // names, and the typed item to Items. EVERY report line in this routine goes
  // through here, which is what makes TApplyReport's
  // "Length(Items) = sum of the six arrays" invariant true by construction
  // instead of by discipline -- there is no way to add prose without also
  // adding its item, or vice versa.
  procedure Emit(const AItem: TApplyItem);
  begin
    case AItem.Field of
      afConverted   : Converted.Add(AItem.Text);
      afAccessSites : AccessSites.Add(AItem.Text);
      afCreatorSites: CreatorSites.Add(AItem.Text);
      afTodos       : Todos.Add(AItem.Text);
      afReemitNotes : ReemitNotes.Add(AItem.Text);
      afWarnings    : Warnings.Add(AItem.Text);
    end;
    Items.Add(AItem);
  end;

  // The ONLY writer of ResolvedDefaults, and deliberately not routed through
  // Emit: Emit's contract is "one prose line AND one typed item", which is
  // exactly what this kind must stop doing. Keeping it a separate procedure is
  // what makes invariant 1 (Items = sum of the six) survive the split -- a
  // resolved default now touches neither side of it.
  procedure EmitResolved(const AEntry: TApplyResolvedDefault);
  begin
    ResolvedDefaults.Add(AEntry);
  end;

  // An item carrying only what the caller states. Context fields stay empty --
  // see TApplyItem's remarks: they are best-effort, not guaranteed.
  function PlainItem(AKind: TApplyItemKind; AField: TApplyField; const AText: string): TApplyItem;
  begin
    Result:= Default(TApplyItem);
    Result.Kind := AKind;
    Result.Field:= AField;
    Result.Text := AText;
  end;

  // As PlainItem, pre-filled from the instance currently being converted (Inst
  // is the enclosing loop's variable, so this is only valid inside that loop).
  function InstItem(AKind: TApplyItemKind; AField: TApplyField; const AText: string): TApplyItem;
  begin
    Result:= PlainItem(AKind, AField, AText);
    Result.Instance:= Inst.InstanceName;
    Result.FromType:= Inst.FromType;
    Result.ToType  := Inst.ToType;
  end;

  // 1.26.5: RefFacts of the project index (PasStore) -- every value a .dfm
  // streams, keyed 'CLASS|PROP|VALUE' (upper; the component's .dfm type token,
  // bare), borrowed. RUN-LEVEL: built once per store by TConvertTreeCache.RefFactsFor and reused
  // by every unit of a batch; the component classes come from ONE
  // FindSymbolsByFile per .dfm, not a lookup per row.
  procedure BuildRefFacts;
  var
    Facts: TRefFacts;
  begin
    Facts:= if PasStore <> nil then ATrees.RefFactsFor(PasStore) else nil;
    RefFactsAsked:= True;
    if Facts = nil then Exit;
    RefFacts   := Facts;
    RefFactRows:= Facts.Rows;
  end;

  // 1.26.5: the #warn and #check-ref outcomes of one instance's re-emit.
  procedure FoldBookChecks(const AReport: TReemitReport; ABlockLine: Integer);
  const
    PATH_CHARS: array[0..1] of Char = ('\', ':');
  var
    It: TApplyItem;
  begin
    for var BW: TReemitBookWarning in AReport.BookWarnings do
    begin
      It:= InstItem(aikBookWarning, afWarnings,
        Format('line %d: warning: %s: %s', [ABlockLine, Inst.InstanceName, BW.Text]));
      It.FilePath:= ADfmPath;
      It.Line    := ABlockLine;
      It.Path    := BW.FromPath;
      It.Value   := BW.Value;
      It.RuleLine:= BW.RuleLine;
      Emit(It);
    end;
    for var RC: TReemitRefCheck in AReport.RefChecks do
    begin
      var Names: string:= string.Join(' / ', RC.RefTargets);
      if (Pos(PATH_CHARS[0], RC.Value) > 0) or (Pos(PATH_CHARS[1], RC.Value) > 0) then
      begin
        It:= InstItem(aikRefPathLike, afWarnings,
          Format('line %d: warning: %s: %s ''%s'' looks like a file path, not a %s name (#check-ref line %d)',
            [ABlockLine, Inst.InstanceName, RC.ToPath, RC.Value, Names, RC.RuleLine]));
        It.FilePath:= ADfmPath;
        It.Line    := ABlockLine;
        It.Path    := RC.ToPath;
        It.Value   := RC.Value;
        It.RuleLine:= RC.RuleLine;
        Emit(It);
      end;
      if not RefFactsAsked then BuildRefFacts;
      if RefFactRows = 0 then
      begin
        if not GRefNotCheckedSaid then
        begin
          GRefNotCheckedSaid:= True;
          It:= PlainItem(aikRefNotChecked, afWarnings,
            Format('line %d: warning: #check-ref not checked -- the project index holds no .dfm property facts (reindex it with this engine)',
              [RC.RuleLine]));
          It.RuleLine:= RC.RuleLine;
          Emit(It);
        end;
        Continue;
      end;
      var Found: Boolean:= False;
      for var Tg: string in RC.RefTargets do
      begin
        var Dot: Integer:= Tg.LastIndexOf('.') + 1;
        if RefFacts.Has(Copy(Tg, 1, Dot - 1), Copy(Tg, Dot + 1, MaxInt), RC.Value) then
          Found:= True;
      end;
      if Found then Continue;
      It:= InstItem(aikRefDangling, afWarnings,
        Format('line %d: warning: %s: %s ''%s'' matches no %s in the project''s .dfm files -- the reference dangles unless it is defined outside the project''s .dfm files (e.g. a FireDAC connection definition) (#check-ref line %d)',
          [ABlockLine, Inst.InstanceName, RC.ToPath, RC.Value, Names, RC.RuleLine]));
      It.FilePath:= ADfmPath;
      It.Line    := ABlockLine;
      It.Path    := RC.ToPath;
      It.Value   := RC.Value;
      It.RuleLine:= RC.RuleLine;
      Emit(It);
    end;
  end;

  // Folds one instance's re-emit report into ReemitNotes, giving each entry the
  // kind its SOURCE array implies rather than one inferred from its prose.
  // ABlockLine is the instance's .dfm object-block header line: TDfmNode carries
  // no line number, so it is the most precise anchor a re-emit-derived item can
  // have. The prose is byte-identical to what this used to add inline.
  procedure FoldReemitReport(const AReport: TReemitReport; ABlockLine: Integer);
    procedure FoldOne(const AEntries: TArray<string>; AKind: TApplyItemKind; const AFmt: string);
    var
      N : string;
      It: TApplyItem;
    begin
      for N in AEntries do
      begin
        It:= InstItem(AKind, afReemitNotes, Format(AFmt, [Inst.InstanceName, N]));
        It.FilePath:= ADfmPath;
        It.Line    := ABlockLine;
        Emit(It);
      end;
    end;
  begin
    { Dropped is folded inline rather than through FoldOne so the PROPERTY PATH
      lands in It.Path as structured data. The count of distinct unlinked source
      properties is emitted in --format json, and deriving it by parsing
      '<instance>: dropped <prop>' back out of prose would be a measurement of
      the message rather than of the fact. FoldOne stays as it is because its
      other callers pass whole sentences, which are not paths. }
    FoldBookChecks(AReport, ABlockLine);
    for var VI: TApplyItem in ValueCastDfmItems(AReport.ValueCasts, Inst, ADfmPath, DfmLines, ABlockLine) do Emit(VI);
    for var DN: string in AReport.Dropped do
    begin
      var DIt: TApplyItem:= InstItem(aikUnmappedProperty, afReemitNotes,
                                     Format('%s: dropped %s', [Inst.InstanceName, DN]));
      DIt.FilePath:= ADfmPath;
      DIt.Line    := ABlockLine;
      DIt.Path    := DN;
      Emit(DIt);
    end;
    FoldOne(AReport.Mismatched, aikBinaryTypeMismatch,   '%s: mismatched %s');
    FoldOne(AReport.OwnedParts, aikOwnedPartUnconverted, '%s: owned-part %s');
    FoldOne(AReport.Created,    aikDfmPathCreated,       '%s: created %s');
    { Carried is folded inline for the same reason Dropped is: the LEAF PATH and
      the rule line land as structured data (It.Path / It.RuleLine), so a
      consumer can list "the leaves nobody typed" without parsing prose. }
    for var CR: TReemitCarried in AReport.Carried do
    begin
      var CIt: TApplyItem:= InstItem(aikSubLeafCarried, afReemitNotes,
        Format('%s: carried %s -> %s (implicit under #link at line %d; both sides %s)',
               [Inst.InstanceName, CR.FromPath, CR.ToPath, CR.RuleLine, CR.TypeName]));
      CIt.FilePath:= ADfmPath;
      CIt.Line    := ABlockLine;
      CIt.Path    := CR.FromPath;
      CIt.RuleLine:= CR.RuleLine;
      Emit(CIt);
    end;
    { Stubs and Relocated used to live in Notes and were emitted with this same
      '%s: %s' shape -- keeping it means every existing text assertion still
      matches; only the KIND is newly distinguishable. }
    FoldOne(AReport.Stubs,       aikLinkStubUnfilled,     '%s: %s');
    FoldOne(AReport.Relocated,   aikCollectionRelocated,  '%s: %s');
    FoldOne(AReport.MappingNotes, aikMappingSourceAbsent, '%s: %s');
    FoldOne(AReport.Notes,       aikDefaultsMayDiverge,   '%s: %s');

    { B4: an applied #mapping that matched nothing is REMAINDER, so it goes to
      warnings (not reemit_notes) and carries the #apply line that requested it.
      Typed from the start rather than added as prose and re-typed later. }
    for var NA in AReport.NotApplied do
    begin
      var MIt: TApplyItem:= InstItem(aikMappingNotApplied, afWarnings,
        Format('%s: line %d: #apply %s matched nothing -- %s = %s was left unmapped',
          [Inst.InstanceName, NA.RuleLine, NA.MapName, NA.Path, NA.Value]));
      MIt.FilePath:= ADfmPath;
      MIt.Line    := ABlockLine;
      MIt.Path    := NA.Path;
      MIt.RuleLine:= NA.RuleLine;
      Emit(MIt);
    end;

    { D0: a #default that did NOT fire because a #link/#mapping had already
      carried a value onto that path. Remainder for the same reason
      mapping-not-applied is: the operator wrote a rule that did nothing, and
      only the rule book can say which of the two they meant. Nothing was LOST
      -- the source value is the one that survived -- so the text names both. }
    for var DS in AReport.DefaultsSuperseded do
    begin
      var DIt: TApplyItem:= InstItem(aikDefaultRuleSuperseded, afWarnings,
        Format('%s: line %d: #default %s = %s did not fire -- a rule already carried %s',
          [Inst.InstanceName, DS.RuleLine, DS.Path, DS.Value, DS.Existing]));
      DIt.FilePath:= ADfmPath;
      DIt.Line    := ABlockLine;
      DIt.Path    := DS.Path;
      DIt.RuleLine:= DS.RuleLine;
      Emit(DIt);
    end;

    { D4: an F property the .dfm did not stream because it sits at its declared
      default, carried across explicitly. INFORMATIONAL, not remainder -- the
      work was done. It is reported because the value appears in the output
      .dfm without appearing in the input one, and an operator diffing the two
      deserves an account of where it came from.

      GOES TO ResolvedDefaults, NOT THROUGH Emit, AND THAT IS THE POINT OF IT.
      Every other kind here is a remainder: a thing a human must still decide.
      This one is a receipt. Its volume, alone among the kinds, scales with the
      SIZE OF THE FORM rather than with what is wrong with it -- the converter
      team measured ~2,156 of these against at most 1,229 real properties on one
      form -- so while it sat in items[] it buried the four kinds that matter
      under work that had already succeeded. Emitting it through Emit would put
      it back into both items[] and reemit_notes[], which is the defect.

      A nested part arrives here under its OWN instance name, because the
      instance loop converts a part with the part's own trees (MEASURED
      2026-09-14; run_convert_apply.ps1 Phase 9 pins it, and AI-CONVERT-RUNBOOK's
      caveat is about HandleNested, a different path). }
    for var DR in AReport.DefaultsResolved do
    begin
      var RD: TApplyResolvedDefault;
      RD.Instance:= Inst.InstanceName;
      RD.FromPath:= DR.FromPath;
      RD.ToPath  := DR.ToPath;
      RD.Value   := DR.Value;
      RD.RuleLine:= DR.RuleLine;
      RD.Line    := ABlockLine;
      EmitResolved(RD);
    end;

    { D5: a value a named ENUM cast could not translate -- no `map` matched and
      the cast declares no `else`. REMAINDER, and nothing was written for it:
      copying the source member through would put a member of ONE enum type into
      a property of ANOTHER, which either fails to load or silently means
      something else. Carries the cast name and the offending value, so the fix
      is a one-line `map` in the .castlib. }
    for var EU in AReport.EnumUnmapped do
    begin
      var EIt: TApplyItem:= InstItem(aikEnumCastUnmapped, afWarnings,
        Format('%s: line %d: enum cast %s has no mapping for %s = %s and no else -- %s not written',
          [Inst.InstanceName, EU.RuleLine, EU.CastName, EU.FromPath, EU.Value, EU.ToPath]));
      EIt.FilePath:= ADfmPath;
      EIt.Line    := ABlockLine;
      EIt.Path    := EU.FromPath;
      EIt.RuleLine:= EU.RuleLine;
      Emit(EIt);
    end;
  end;

  // Reports an instance skipped whole. A retyped inherited one (C8 N2) is not
  // converted at all then -- it goes back to 'skipped' with AItem's text as
  // the reason, and AppendInheritedReport warns about it instead.
  procedure SkipInstance(const AItem: TApplyItem);
  begin
    var K: Integer:= InheritedIndexOf(AInherited, Inst.InstanceName, INH_ACTION_RETYPED);
    if K < 0 then
    begin
      Emit(AItem);
      Exit;
    end;
    AInherited[K].Action:= INH_ACTION_SKIPPED;
    AInherited[K].Reason:= Format('declared in %s, which already has %s, but not retyped: %s',
      [AInherited[K].AncestorUnit, AInherited[K].ToType, AItem.Text]);
  end;

  // C8 N2a: a field a converted ancestor declares, used in this unit's code
  // only -- its access sites are rewritten like an own instance's, and its To
  // type's unit is added like one. (A stale .dfm refuses the plan anyway.)
  procedure AddCodeEntries;
  begin
    for var CE: TInheritedInstance in AInherited do
    begin
      if CE.Action <> INH_ACTION_CODE then Continue;
      ConvertedInstNames.Add(CE.Name);
      InstFromType.AddOrSetValue(CE.Name, CE.TypeName);
      InstToType.AddOrSetValue(CE.Name, CE.ToType);
      if DoneUnits.ContainsKey(CE.ToType) then Continue;
      DoneUnits.Add(CE.ToType, True);
      ToTypesSeen.Add(CE.ToType);
    end;
  end;
  // -- surface #1: locate the published field decl 'Name: FromType;' via the
  // field symbol (gives us the line range to scope the text search), then find
  // the exact FromType token span for a tekReplaceInLine edit.
  procedure PlanFieldRetype;
  var
    E    : TTextEdit;
    It   : TApplyItem;
    Sym  : TSymbol; { must be local: E1019 forbids a for-in over an enclosing routine's var }
    Found: Boolean;
  begin
    Found:= False;
    for Sym in PasFileSyms do
    begin
      if (Sym.Kind <> skField) or (not SameText(Sym.Name, Inst.InstanceName)) or
         (not SameText(Sym.Signature, Inst.FromType)) then Continue;

      var FLine, FCol, FEndCol: Integer;
      if LocateFieldTypeToken(PasLines, Sym.StartLine, Sym.EndLine,
           Inst.InstanceName, Inst.FromType, FLine, FCol, FEndCol) then
      begin
        E:= Default(TTextEdit);
        E.FilePath:= AUnitPas;
        E.Kind    := tekReplaceInLine;
        E.Line    := FLine;
        E.Col     := FCol;
        E.EndCol  := FEndCol;
        E.Text    := Inst.ToType;
        Edits.Add(E);
        { C13 a: an interface field needs its To type's unit in the INTERFACE uses }
        if SameText(Sym.Section, 'interface') then IntfToTypes.AddOrSetValue(Inst.ToType, True);
        It:= InstItem(aikFieldRetyped, afConverted,
          Format('%s: %s -> %s', [Inst.InstanceName, Inst.FromType, Inst.ToType]));
        It.FilePath:= AUnitPas;
        It.Line    := FLine;
        Emit(It);
        Found:= True;
      end;
      Break; { one matching field symbol is enough }
    end;
    if not Found then
      { A multi-declarator field line (`Edit1, Edit2: TOldEdit;`) indexes only
        the FIRST declarator as a field symbol, so a later name on the shared
        line is not located here -- the .dfm/access/creator surfaces still
        convert it, but this .pas decl line stays typed as the F type. Name the
        limitation so the user fixes the shared line by hand. }
      Emit(InstItem(aikFieldDeclNotRetyped, afWarnings,
        Format('%s: could not locate field declaration "%s: %s" in %s'
          + ' (a shared multi-declarator line is not retyped -- fix the decl by hand)',
          [Inst.InstanceName, Inst.InstanceName, Inst.FromType, AUnitPas])));
  end;

  // -- surface #5: runtime-creator retype. Every explicit construction site
  // 'FromType.Xxx(...)' (e.g. 'Edit1 := TOldEdit.Create(Self);') in this unit
  // gets its type token rewritten to ToType, PLUS a TODO marker comment --
  // ALWAYS, unconditionally: ToType's constructor/init may take a different
  // shape than FromType's (a different parameter list, extra required setup),
  // and this applier never attempts to fix up constructor ARGUMENTS. The marker
  // is the safety net the user checks by hand. A design-time (DFM-only)
  // instance has no .Create in code, so it simply contributes zero sites here --
  // its #1/#2/#3 edits still apply on their own.
  procedure PlanCreatorSites;
  var
    E : TTextEdit;
    It: TApplyItem;
  begin
    var Sites: TArray<TCreatorSite>:= FindConstructionSites(Stores, PasStore, PasFileId, PasLines, Inst.FromType);
    var HasGenericCreate: Boolean:= ToTypeHasGenericCreate(Stores, Inst.ToType);
    for var Site in Sites do
    begin
      var CtorName: string:= Site.CtorName;
      if CtorName = '' then CtorName:= 'Create';

      E:= Default(TTextEdit);
      E.FilePath:= AUnitPas;
      E.Kind    := tekReplaceInLine;
      E.Line    := Site.Line;
      E.Col     := Site.Col;
      E.EndCol  := Site.EndCol;
      E.Text    := Inst.ToType;
      Edits.Add(E);

      var TodoText: string:= Format(
        '{ TODO: drag-lint convert -- verify creator for %s (was %s.%s); %s''s ctor/init may differ }',
        [Inst.ToType, Inst.FromType, CtorName, Inst.ToType]);

      { end-of-line insert keeps line numbers stable for every OTHER edit on
        this line/file (a tekInsertLines line-above would shift every
        subsequent line number, which every other surface's edits are NOT
        computed to account for). }
      var LineLen: Integer:= 0;
      if (Site.Line >= 1) and (Site.Line <= PasLines.Count) then
        LineLen:= Length(PasLines[Site.Line - 1]);
      E:= Default(TTextEdit);
      E.FilePath:= AUnitPas;
      E.Kind    := tekInsertInLine;
      E.Line    := Site.Line;
      E.Col     := LineLen + 1;
      E.Text    := ' ' + TodoText;
      Edits.Add(E);

      It:= InstItem(aikCreatorRetyped, afCreatorSites,
        Format('%s: %s.%s -> %s.%s', [Inst.InstanceName, Inst.FromType, CtorName, Inst.ToType, CtorName]));
      It.FilePath:= AUnitPas;
      It.Line    := Site.Line;
      Emit(It);

      if not HasGenericCreate then
      begin
        It:= InstItem(aikCreatorUnverified, afReemitNotes,
          Format('%s: %s has no indexed generic Create(AOwner: TComponent) -- verify the creator manually',
            [Inst.InstanceName, Inst.ToType]));
        It.FilePath:= AUnitPas;
        It.Line    := Site.Line;
        Emit(It);
      end;

      It:= InstItem(aikCreatorVerify, afTodos, TodoText);
      It.FilePath:= AUnitPas;
      It.Line    := Site.Line;
      Emit(It);
    end;
  end;

  // Surfaces #1 and #5 for an own instance. A retyped inherited one (C8 N2)
  // has neither here -- its field is the ancestor's and nothing in this unit
  // creates it -- so it gets its converted[] line instead, at ABlockLine.
  procedure PlanDeclSurfaces(ABlockLine: Integer);
  begin
    var K: Integer:= InheritedIndexOf(AInherited, Inst.InstanceName, INH_ACTION_RETYPED);
    if K < 0 then
    begin
      PlanFieldRetype;
      PlanCreatorSites;
      Exit;
    end;
    var RIt: TApplyItem:= InstItem(aikInheritedInstanceRetyped, afConverted,
      Format('%s: inherited %s -> %s (declared in %s)',
        [Inst.InstanceName, Inst.FromType, Inst.ToType, AInherited[K].AncestorUnit]));
    RIt.FilePath:= ADfmPath;
    RIt.Line    := ABlockLine;
    Emit(RIt);
  end;

  // 1.25.1 (the DMREADINGS defect): an instance whose .dfm block lies INSIDE
  // the block of an instance this run already re-emitted -- a TField of a
  // converted TTable. Its own delete + insert used to be planned beside the
  // parent's, which covers the same lines: two overlapping delete ranges, so
  // the applier refused the whole .dfm AFTER the .pas had been written.
  //
  // The parent's re-emit already holds a converted copy of the child (the
  // owned-part recursion, run with the PARENT's trees). The child's OWN
  // re-emit (AReemit, its own trees: defaults resolved, remainder reported
  // under its own name -- run_convert_apply.ps1 Phase 9) is the better text,
  // so it REPLACES that copy inside the parent's insert. One delete + insert
  // for the whole parent, the child's report and .pas surfaces as before.
  // When the parent's text holds no `object <Name>: <ToType>` block the child
  // is skipped and warned, its .pas left alone to match. Parents precede their
  // children in .dfm order, so the parent's edits are already in Edits.
  // False when the block is inside no re-emitted block.
  function SpliceIntoParent(AStart, AEnd: Integer; const AReemit: TReemitResult): Boolean;
  var
    Outer, InsIx: Integer;
    Lines       : TArray<string>;
    Hdr, HdrEnd : Integer;
    HdrName     : string;
    HdrClass    : string;
    Ed          : TTextEdit;
  begin
    Outer:= 0;
    for Ed in Edits do
      if (Ed.Kind = tekDeleteLines) and SamePath(Ed.FilePath, ADfmPath) and
         (Ed.Line < AStart) and (Ed.EndLine >= AEnd) then Outer:= Ed.Line;
    if Outer = 0 then Exit(False);
    Result:= True;
    InsIx:= -1;
    for var K: Integer:= 0 to Edits.Count - 1 do
      if (Edits[K].Kind = tekInsertLines) and SamePath(Edits[K].FilePath, ADfmPath) and (Edits[K].Line = Outer - 1) then
        InsIx:= K;
    Hdr:= -1;
    Lines:= nil;
    if InsIx >= 0 then
    begin
      Lines:= Edits[InsIx].Text.Replace(#13#10, #10).Split([#10]);
      for var K: Integer:= 0 to High(Lines) do
        if (TryParseHeaderAfter(Trim(Lines[K]), KW_OBJECT + ' ', HdrName, HdrClass) or
            TryParseHeaderAfter(Trim(Lines[K]), KW_INHERITED + ' ', HdrName, HdrClass) or
            TryParseHeaderAfter(Trim(Lines[K]), KW_INLINE + ' ', HdrName, HdrClass)) and
           SameText(HdrName, Inst.InstanceName) and SameText(HdrClass, Inst.ToType) then
        begin
          Hdr:= K;
          Break;
        end;
    end;
    if Hdr < 0 then
    begin
      var SIt: TApplyItem:= InstItem(aikInstanceSkipped, afWarnings,
        Format('%s: nested in a converted component whose .dfm re-emit does not carry it -- instance skipped',
          [Inst.InstanceName]));
      SIt.FilePath:= ADfmPath;
      SIt.Line    := AStart;
      SkipInstance(SIt); { C8 N2: a retyped inherited child goes back to 'skipped' }
      Exit;
    end;
    { the copy's own `end` is the first one at its header's indent }
    HdrEnd:= Hdr + 1;
    while (HdrEnd < High(Lines)) and not ((Trim(Lines[HdrEnd]) = 'end') and
          (LeadingIndent(Lines[HdrEnd]) = LeadingIndent(Lines[Hdr]))) do Inc(HdrEnd);
    Ed:= Edits[InsIx];
    Ed.Text:= String.Join(#13#10, Lines, 0, Hdr) + (if Hdr > 0 then #13#10 else '') +
      ReindentBlock(AReemit.DfmText, LeadingIndent(Lines[Hdr])) +
      (if HdrEnd < High(Lines) then #13#10 + String.Join(#13#10, Lines, HdrEnd + 1, High(Lines) - HdrEnd) else '');
    Edits[InsIx]:= Ed;
    ConvertedInstNames.Add(Inst.InstanceName);
    InstFromType.AddOrSetValue(Inst.InstanceName, Inst.FromType);
    InstToType.AddOrSetValue(Inst.InstanceName, Inst.ToType);
    FoldReemitReport(AReemit.Report, AStart);
    PlanDeclSurfaces(AStart); { C8 N2: an inherited child has no field / creator here }
    if DoneUnits.ContainsKey(Inst.ToType) then Exit;
    DoneUnits.Add(Inst.ToType, True);
    ToTypesSeen.Add(Inst.ToType);
  end;
  // -- surface #4: instance-scoped property/event ACCESS rewrite, via ref-gap
  // G's 'member-access' refs. Runs ONCE over the whole unit per renaming
  // '#link ToMember <- FromMember' rule (not per-instance --
  // GetReferencesFromFile already returns every ref in the file, and
  // FindMemberAccessSites' own instance-name join is what scopes each hit to a
  // specific converted receiver), rather than inside the per-instance loop: a
  // single access-rewrite pass naturally covers every instance sharing the same
  // rule in one query instead of N redundant whole-file ref scans. Identity
  // renames (ToPath = FromPath) are skipped -- there is nothing to rewrite.
  // Dotted paths (e.g. '#link Name <- Inner.Shade' -- a NESTED .dfm property
  // path) are also skipped here: they describe the .dfm property tree, not a
  // single .pas 'obj.Member' token, so they are out of surface #4's scope (no
  // crash, just no rewrite -- the .dfm-side #link still applies via surface #3).
  procedure PlanAccessSites;
  var
    E  : TTextEdit;
    It : TApplyItem;
    Unv: TArray<TAccessSite>;

    { 1.26.0 (C8 N2 review): a site the index cannot vouch for is REPORTED,
      once per (line, member), never dropped in silence }
    procedure ReportUnverified(const AMember: string);
    begin
      for var U: TAccessSite in Unv do
      begin
        var Dup: Boolean:= False;
        for var Prior: TApplyItem in Items do
          if (Prior.Kind = aikAccessSiteUnverified) and (Prior.Line = U.Line) and SameText(Prior.Path, AMember) then Dup:= True;
        if Dup then Continue;
        var UIt: TApplyItem:= PlainItem(aikAccessSiteUnverified, afWarnings,
          Format('access site %s:%d %s.%s not verified against the index -- not rewritten',
            [ExtractFileName(AUnitPas), U.Line, U.InstanceName, AMember]));
        UIt.Instance:= U.InstanceName;
        UIt.FilePath:= AUnitPas;
        UIt.Path    := AMember;
        UIt.Line    := U.Line;
        Emit(UIt);
      end;
    end;

    { 1.26.0: `with X do Member := ...` reaches X's members with no receiver at
      the site, so the rewrite cannot see them -- each `with` naming a converted
      instance is REPORTED for hand conversion }
    procedure ReportWithBlocks;
    begin
      var Renames: Boolean:= False;
      for var Q: TConversionRule in ABook.Rules.Rules do
        if (Q.Kind = rkLink) and (Q.FromPath <> '') and (Q.ToPath <> '') and not SameText(Q.FromPath, Q.ToPath) then Renames:= True;
      if not Renames then Exit; { nothing a with block could hide }
      for var LineNo: Integer:= 1 to PasLines.Count do
        for var N: string in ConvertedInstNames do
          if WithNamesTarget(PasLines[LineNo - 1], N) then
          begin
            var WIt: TApplyItem:= PlainItem(aikAccessSiteUnverified, afWarnings,
              Format('access site %s:%d with %s do ... not verified against the index -- not rewritten (a member reached through a with block is converted by hand)',
                [ExtractFileName(AUnitPas), LineNo, N]));
            WIt.Instance:= N;
            WIt.FilePath:= AUnitPas;
            WIt.Line    := LineNo;
            Emit(WIt);
          end;
    end;

  begin
    ReportWithBlocks;
    { T2h: an UNREACHABLE #link is never applied -- on the .pas side either. }
    for var LinkRule in WithoutUnreachableRules(ABook.Rules, ABook.Unreachable, 0).Rules do
    begin
      if LinkRule.Kind <> rkLink then Continue;
      if (LinkRule.ToPath = '') or (LinkRule.FromPath = '') then Continue;
      { A CAST IS NOT YET PERFORMED, SO THE RENAME IS REFUSED RATHER THAN
        HALF-APPLIED. This surface rewrites the member IDENTIFIER at an access
        site: `obj.Old` -> `obj.New`. A rule carrying `: Round` says the VALUE
        also needs converting, and this code cannot do that. Renaming without it
        would emit source that compiles and is numerically wrong -- the worst
        possible outcome, and strictly worse than the defect this cast handling
        was added to fix.

        Before the FromPath split landed, `: Round` was swallowed into FromPath
        and matched no member, so nothing was rewritten by accident. Making the
        path resolve correctly therefore OPENS this hazard, and this guard is
        what keeps it closed. It is loud (a warning naming the rule and its cast)
        rather than silent, because a skipped conversion the operator never hears
        about is the same class of defect. }
      { 1.27.0 (C15): a VALUE cast (castlib `value`, StripDB) is not a class
        cast -- it rewrites a string literal and is never refused below. A
        renaming one falls through to the identifier rewrite too. }
      var VDef: TCastDef;
      if (LinkRule.Cast <> '') and FindClassCast(ACastLib, LinkRule.Cast, VDef) and (VDef.Value <> '') then
      begin
        var VEdits: TArray<TTextEdit>;
        var VItems: TArray<TApplyItem>;
        var VScope: TArray<string>:= LinkScopeNames(ABook.Rules, ConvertedInstNames, InstFromType, LinkRule);
        var VSites: TArray<TAccessSite>:= BoundAccessSites(PasStore, PasFileId, ADfmPath,
          FindMemberAccessSites(PasStore, PasFileId, PasLines, LinkRule.FromPath, VScope), Unv);
        PlanValueCastSites(VSites, LinkRule, VDef, AUnitPas, PasLines, VEdits, VItems);
        ReportUnverified(LinkRule.FromPath);
        for var VE: TTextEdit in VEdits do Edits.Add(VE);
        for var VI: TApplyItem in VItems do Emit(VI);
        { review fix wave: every other reference to the member -- a with block,
          an unverified site -- is a check, never silence }
        if Length(VScope) > 0 then
          for var VU: TApplyItem in UnresolvedValueCastSites(PasStore, PasFileId, AUnitPas, LinkRule, VSites) do Emit(VU);
        if SameText(LinkRule.ToPath, LinkRule.FromPath) then Continue;
      end
      else if LinkRule.Cast <> '' then
      begin
        { THREE OUTCOMES, NEVER TWO, AND NEVER SILENCE.

          The refusal above was right when it was the only option: renaming the
          member without converting the VALUE emits source that compiles and is
          wrong, which is worse than not converting. What was missing is the
          other half -- performing the cast when the library says how.

          The three cases need telling apart because two of them need OPPOSITE
          fixes by the operator:
            1. resolved + `pas` template -> 1.26.x realized it here; since 1.27.0
               every access site is REFUSED one by one (see Outcome 1 below).
            2. resolved + EMPTY template -> still by hand, but the fix is to the
               .castlib, so the message must say the cast was FOUND.
            3. name resolves to nothing  -> the fix is to the rule book or the
               --castlib path, so the message keeps its original wording.
          Before this, 2 and 3 produced the identical sentence and sent the
          operator hunting the wrong file.

          THE LOOKUP IS BY NAME, and it is FindClassCast -- not ClassCastFor,
          which takes two TYPE names and returns a cast NAME (the editor's
          question, the inverse of this one). FindClassCast lives beside its
          enum twin in Convert.CastLib.pas for the reason that unit exists: one
          parser, two consumers, no drift. It briefly lived here as a local
          helper only because that file had uncommitted converter-team work in
          it; they committed it as 30fdf633 expressly so this could move, and
          asked that it not stay local. }
        var CastDef  : TCastDef;
        var CastFound: Boolean:= FindClassCast(ACastLib, LinkRule.Cast, CastDef);

        if not CastFound then
        begin
          { Outcome 3 -- unchanged wording, and it already names the cast. }
          It:= PlainItem(aikCastNotApplied, afWarnings,
            Format('line %d: #link %s <- %s : %s SKIPPED on the .pas side -- ' +
              'the cast is not applied by convert-apply, and renaming without it would produce ' +
              'wrong values. Convert this access site by hand.',
              [LinkRule.LineNo, LinkRule.ToPath, LinkRule.FromPath, LinkRule.Cast]));
          It.Path    := LinkRule.FromPath;
          It.RuleLine:= LinkRule.LineNo;
          It.Value   := LinkRule.Cast;
          Emit(It);
          Continue;
        end;

        if Trim(CastDef.PasTemplate) = '' then
        begin
          { Outcome 2 -- FOUND, but the library says nothing about how to do it
            on the .pas side. Naming that is the whole point: the operator edits
            the .castlib instead of looking for a missing rule. }
          It:= PlainItem(aikCastNotApplied, afWarnings,
            Format('line %d: #link %s <- %s : %s SKIPPED on the .pas side -- ' +
              'the cast WAS FOUND in the cast library but carries no pas template, so there is ' +
              'nothing to emit. Convert this access site by hand.%s',
              [LinkRule.LineNo, LinkRule.ToPath, LinkRule.FromPath, LinkRule.Cast,
               (if Trim(CastDef.Todo) <> '' then ' TODO: ' + CastDef.Todo else '')]));
          It.Path    := LinkRule.FromPath;
          It.RuleLine:= LinkRule.LineNo;
          It.Value   := LinkRule.Cast;
          Emit(It);
          Continue;
        end;

        (* Outcome 1 -- a CLASS cast (a castlib block whose pas line is a
           STATEMENT template, AssignGraphic) is FOUND, and every .pas access
           site is still REFUSED -- a VALUE cast never gets here, see above: no edit, one warning per site
           (1.27.0, owner decision -- interim, until a member-replacement
           feature is designed).

           Why no site can be realized: the template is a STATEMENT
           (dst.Assign(src);) while an access site is the member token INSIDE
           an expression (pic1.Picture.Data := 'seed'). There is no correct
           splice of a statement into an expression -- 52d9a1b9 spliced it over
           the member token and wrote pic1.pic1.Glyph.Assign(...);.Data, which
           does not parse. Replacing the whole statement instead is no better:
           the src placeholder reads the FROM member, which the retyped
           instance no longer has, so the emitted code reads a property that
           does not exist. The .dfm half of the cast is unaffected.

           WRITTEN AS A PAREN-STAR COMMENT ON PURPOSE: a literal closing brace
           inside a brace comment ENDS THE COMMENT, so the placeholders are not
           spelled with their braces here. *)
        var CastSites: TArray<TAccessSite>:= BoundAccessSites(PasStore, PasFileId, ADfmPath, FindMemberAccessSites(PasStore, PasFileId, PasLines,
          LinkRule.FromPath, LinkScopeNames(ABook.Rules, ConvertedInstNames, InstFromType, LinkRule)), Unv);
        ReportUnverified(LinkRule.FromPath);
        for var CSite in CastSites do
        begin
          It:= PlainItem(aikCastNotApplied, afWarnings,
            Format('line %d: #link %s <- %s : %s -- access site %s:%d %s.%s not rewritten: the cast''s pas template is a ' +
              'statement and has no correct splice inside an expression; convert this access site by hand',
              [LinkRule.LineNo, LinkRule.ToPath, LinkRule.FromPath, LinkRule.Cast,
               ExtractFileName(AUnitPas), CSite.Line, CSite.InstanceName, LinkRule.FromPath]));
          It.Instance:= CSite.InstanceName;
          It.FilePath:= AUnitPas;
          It.Path    := LinkRule.FromPath;
          It.RuleLine:= LinkRule.LineNo;
          It.Line    := CSite.Line;
          It.Value   := LinkRule.Cast;
          Emit(It);
        end;
        Continue;
      end;
      if SameText(LinkRule.ToPath, LinkRule.FromPath) then Continue; { identity rename -- nothing to rewrite }
      if (Pos('.', LinkRule.ToPath) > 0) or (Pos('.', LinkRule.FromPath) > 0) then Continue; { nested .dfm path, not a .pas access site }

      var Sites: TArray<TAccessSite>:= BoundAccessSites(PasStore, PasFileId, ADfmPath, FindMemberAccessSites(PasStore, PasFileId, PasLines,
        LinkRule.FromPath, LinkScopeNames(ABook.Rules, ConvertedInstNames, InstFromType, LinkRule)), Unv);
      ReportUnverified(LinkRule.FromPath);
      for var Site in Sites do
      begin
        E:= Default(TTextEdit);
        E.FilePath:= AUnitPas;
        E.Kind    := tekReplaceInLine;
        E.Line    := Site.Line;
        { C18: index byte columns -> character columns (the C9 lesson) }
        E.Col     := CharColumn(PasLines[Site.Line - 1], Site.Col);
        E.EndCol  := CharColumn(PasLines[Site.Line - 1], Site.EndCol);
        E.Text    := LinkRule.ToPath;
        Edits.Add(E);

        It:= PlainItem(aikAccessSiteRewritten, afAccessSites,
          Format('%s.%s -> %s.%s (L%d)',
            [Site.InstanceName, LinkRule.FromPath, Site.InstanceName, LinkRule.ToPath, Site.Line]));
        It.Instance:= Site.InstanceName;
        It.FilePath:= AUnitPas;
        It.Path    := LinkRule.FromPath;
        It.Line    := Site.Line;
        It.RuleLine:= LinkRule.LineNo;
        Emit(It);
      end;
    end;
  end;

  // -- surface #2: uses-add for each distinct ToType (once per type).
  // Bug 2: the To type's declaring unit may live in a DIFFERENT --db than the
  // unit being converted (PasStore) -- try every store as the NAME store, in
  // order, keeping PasStore fixed as the UNIT store (whose uses clause is what
  // actually gets edited), first store that resolves (AlreadyUsed or a
  // non-empty edit set) wins.
  //
  // 1.20.6: when the book also has UNIT rules (#unuse / #use / #useswap), the
  // resolved units are NOT edited in here. They are handed to PlanUnitRules
  // instead, which then owns every uses change to the unit: two planners
  // editing one clause could add a unit twice, or append after an entry the
  // other one deletes. A unit already used is handed over too, so a #unuse of
  // it is overruled (ADD wins) rather than breaking the converted unit.
  // AUses is the unit-rule plan (Ok=True and empty when the book has none).
  // C13 a: True when the unit uses AUnit in its implementation clause and NOT
  // in its interface clause (as the index recorded the unit's uses).
  function UsedOnlyInImplementation(const AUnit: string): Boolean;
  var
    InImpl, InIntf: Boolean;
  begin
    InImpl:= False;
    InIntf:= False;
    if PasFileId > 0 then
      for var U: TUnitUse in PasStore.GetUnitUsesForFile(PasFileId) do
        if SameText(U.UnitName, AUnit) then
        begin
          if U.Section = uusInterface then InIntf:= True else InImpl:= True;
        end;
    Result:= InImpl and not InIntf;
  end;
  // C9 A8-1: the ONE candidate of a To-type tie the book or the unit already
  // chooses -- a unit a #use / #useswap New / #convert block adds, or a uses
  // entry of the unit (as the index recorded it) -- spelled as the unit writes
  // it when present, else as the book does. '' when none or more than one
  // candidate is chosen: the tie is then reported, never decided.
  function PickTieCandidate(const ACands: TArray<TUsesCandidate>): string;
  var
    Picked  : TArray<string>;   { candidate unit names chosen, distinct }
    Spelling: string;

    procedure Choose(const ASpelling: string; APreferred: Boolean);
    begin
      for var C: TUsesCandidate in ACands do
        if ATrees.UnitIndex.SameUnit(ASpelling, C.UnitName) then
        begin
          if not MatchText(C.UnitName, Picked) then Picked:= Picked + [C.UnitName];
          if APreferred or (Spelling = '') then Spelling:= ASpelling;
        end;
    end;

  begin
    Picked  := nil;
    Spelling:= '';
    { BookChosenUnits: the book's adds, then the unit's own entries the book
      does not remove (review F2) -- shared with TConvertTreeCache.ScopedClass,
      so the class validated is the class whose unit is added }
    for var B: TBookUnit in BookChosenUnits(ABook.Rules,
      if PasFileId > 0 then PasStore.GetUnitUsesForFile(PasFileId) else nil, ATrees.UnitIndex.SameUnit) do
      Choose(B.Spelling, B.Preferred);
    Result:= if Length(Picked) = 1 then Spelling else '';
  end;
  // C9 A8-2: the line the conversion writes ToType onto in the unit (its first
  // field retype), 0 when it writes it nowhere (an inherited instance only).
  function ToTypeLine(const AToType: string): Integer;
  begin
    Result:= 0;
    for var E: TTextEdit in Edits do
      if (E.Kind = tekReplaceInLine) and SameText(E.FilePath, AUnitPas) and SameText(E.Text, AToType) and
         ((Result = 0) or (E.Line < Result)) then Result:= E.Line;
  end;
  // C9 R8a: a To-type tie nothing settles is REPORTED -- a uses_unresolved row
  // (with the retyped field's line, A8-2) and a uses-unit-ambiguous warning.
  procedure ReportTie(const AToType: string; AWantIntf: Boolean; const ACands: TArray<TUsesCandidate>);
  var
    Un   : TUsesUnresolved;
    Units: string;
    TieIt: TApplyItem;
  begin
    Un:= Default(TUsesUnresolved);
    Un.Name      := AToType;
    Un.Line      := ToTypeLine(AToType);
    Un.Section   := if AWantIntf then 'interface' else 'implementation';
    Un.Reason    := UNRESOLVED_AMBIGUOUS;
    Un.Candidates:= ACands;
    Result.Report.UsesUnresolved:= Result.Report.UsesUnresolved + [Un];
    Units:= '';
    for var C: TUsesCandidate in ACands do Units:= Units + (if Units = '' then '' else ', ') + C.UnitName;
    TieIt:= PlainItem(aikUsesUnitAmbiguous, afWarnings,
      Format('"%s" is declared in %d units (%s) -- none added to uses; add #use <unit> to the book to choose',
        [AToType, Length(ACands), Units]));
    TieIt.ToType  := AToType;
    TieIt.FilePath:= AUnitPas;
    TieIt.Line    := Un.Line;
    Emit(TieIt);
  end;
  // Surface #2's find-unit for one To type: the first store that resolves it
  // (Build's edits / already-used answer). Returns the unit to use INSTEAD of
  // Build's pick, '' to keep it: review F3 -- when ONE unit declares the To
  // type at unit level (AUnitLevel), Build also scores class members (a
  // nested type of the same name) and lets hash order break that tie.
  function BuildToTypeAdd(const AToType: string; AWantIntf: Boolean; const AUnitLevel: TArray<TUsesCandidate>;
    out AResolved: string; out AAlreadyUsed: Boolean; out AEdits: TArray<TTextEdit>): string;
  begin
    AResolved   := '';
    AAlreadyUsed:= False;
    AEdits      := nil;
    for var St in Stores do
    begin
      AEdits:= TFindUnitRefactoring.Build(St, PasStore, AToType, AUnitPas, AResolved, AAlreadyUsed, AWantIntf);
      if AAlreadyUsed or (Length(AEdits) > 0) then Break;
    end;
    Result:= '';
    if (Length(AUnitLevel) = 1) and not ATrees.UnitIndex.SameUnit(AResolved, AUnitLevel[0].UnitName) then
      Result:= AUnitLevel[0].UnitName;
  end;
  procedure PlanUsesAdditions(out AUses: TUsesPlan; out AAdds, AIntfAdds: TArray<string>);
  var
    E : TTextEdit;
    It: TApplyItem;
  begin
    var UnitRules  : Boolean      := BookHasUnitRules(ABook.Rules);
    var MoveNeeded : Boolean      := False;
    var TiePlanned : Boolean      := False;  { review F1: a picked tie unit is written by the planner }
    var Pending    : TList<TTextEdit>:= TList<TTextEdit>.Create;
    var ConvertAdds: TList<string>:= TList<string>.Create;
    var IntfAdds   : TList<string>:= TList<string>.Create;
    try
      for var ToType_ in ToTypesSeen do
      begin
        var ResolvedUnit: string;
        var AlreadyUsed : Boolean;
        var UseEdits: TArray<TTextEdit>;
        var WantIntf: Boolean:= IntfToTypes.ContainsKey(ToType_);
        { C9 R8a: a To type two units declare is REPORTED, never decided by
          dictionary order }
        var TieUnit: string:= '';
        var Amb    : TArray<TUsesCandidate>:= nil;
        if ABook.Reconcile then
        begin
          Amb:= ATrees.UnitIndex.DeclaringUnits(BareTypeTail(ToType_), True);
          if Length(Amb) > 1 then
          begin
            { A8-1: a tie the book's #use (or the unit's own uses) settles is
              resolved to that unit -- through the same ConvertAdds / IntfAdds
              as an unambiguous To type, so an INTERFACE field's unit goes to
              the interface uses (or is moved there), never to where a bare
              #use would put it (the implementation: E2003) }
            TieUnit:= PickTieCandidate(Amb);
            if TieUnit = '' then
            begin
              ReportTie(ToType_, WantIntf, Amb);
              Continue;
            end;
          end;
        end;
        if TieUnit = '' then
          TieUnit:= BuildToTypeAdd(ToType_, WantIntf, Amb, ResolvedUnit, AlreadyUsed, UseEdits);
        if TieUnit <> '' then
        begin
          { review F1: the uses PLANNER writes it -- a book with no unit rule
            has no Pending edit for this unit, so nothing else would }
          if not MatchText(TieUnit, ConvertAdds.ToArray) then ConvertAdds.Add(TieUnit);
          if WantIntf and not MatchText(TieUnit, IntfAdds.ToArray) then IntfAdds.Add(TieUnit);
          TiePlanned:= True;
          Continue;
        end;
        { 1.25.1: two To types declared in ONE unit (TFDTable and
          TFDAutoIncField) planned that unit's add twice -- 'uses LibB, LibB'
          does not compile. The first type's add stands for both. }
        if not AlreadyUsed and (Length(UseEdits) > 0) and MatchText(ResolvedUnit, ConvertAdds.ToArray) then Continue;
        if AlreadyUsed or (Length(UseEdits) > 0) then
        begin
          ConvertAdds.Add(ResolvedUnit);
          if WantIntf then IntfAdds.Add(ResolvedUnit);
          { C13 a: used, but only in the implementation clause -- it has to
            MOVE, which only the uses planner can do }
          if WantIntf and AlreadyUsed and UsedOnlyInImplementation(ResolvedUnit) then MoveNeeded:= True;
        end;
        if AlreadyUsed then Continue;
        if Length(UseEdits) = 0 then
        begin
          It:= PlainItem(aikUsesUnitUnresolved, afWarnings,
            Format('could not resolve a unit declaring "%s" to add to uses', [ToType_]));
          It.ToType  := ToType_;
          It.FilePath:= AUnitPas;
          Emit(It);
          Continue;
        end;
        for E in UseEdits do Pending.Add(E);
      end;
      AUses:= Default(TUsesPlan);
      AUses.Ok:= True;
      { the caller adds AUses.Edits after R26 -- a skipped removal (C13 N4)
        re-plans the unit rules with AAdds / AIntfAdds first }
      AAdds    := ConvertAdds.ToArray;
      AIntfAdds:= IntfAdds.ToArray;
      if ABook.Reconcile then
      begin
        { C9: the re-indexed converted text decides keep / remove / add }
        var Handled: TArray<string>:= nil;
        for var TT in ToTypesSeen do Handled:= Handled + [BareTypeTail(TT)];
        var RA: TReconcileUnitArgs:= Default(TReconcileUnitArgs);
        RA.UnitPas      := AUnitPas;
        RA.DfmPath      := ADfmPath;
        RA.Rules        := ABook.Rules;
        RA.Edits        := DistinctInLineEdits(Edits.ToArray);
        RA.Converted    := ConvertedInstNames;
        RA.Only         := AOnly;
        RA.Adds         := AAdds;
        RA.IntfAdds     := AIntfAdds;
        RA.Handled      := Handled;
        RA.PlannerNeeded:= UnitRules or MoveNeeded or TiePlanned or (Pending.Count > 0);  { review: the planner also reports the #convert adds as rows }
        var Rec: TReconcileOutcome:= ReconcileUnitUses(ATrees, RA);
        for var RIt: TApplyItem in Rec.Items do Emit(RIt);
        Result.Report.UsesUnresolved:= Result.Report.UsesUnresolved + Rec.Unresolved;
        Result.Report.PasUses       := Result.Report.PasUses + DanglingPasUses(Rec.Dangling);
        Result.Report.UsesReconcile := Rec.Status;
        AUses:= Rec.Plan;
        if not Rec.UsePlanner then
          for E in Pending do Edits.Add(E);
      end
      else if UnitRules or MoveNeeded then
        AUses:= PlanUnitRules(AUnitPas, ReadUnitText(AUnitPas), ABook.Rules,
          AAdds, AIntfAdds)
      else
        for E in Pending do Edits.Add(E);
    finally
      IntfAdds.Free;
      ConvertAdds.Free;
      Pending.Free;
    end;
  end;

  // Row 6 steps 2/3 (2026-09-16). Folds the per-instance aikUnmappedProperty
  // items into ONE row per (source type, property) -- Result.Report.Unlinked,
  // always -- and, when AWarnUnlinked, warns once per row with the site count
  // as a FRACTION of that type's converted instances. Runs AFTER the instance
  // loop, so both the numerator (sites) and the denominator (instances that
  // cleared the re-emit checkpoint) are final.
  //
  // The key is (FromType, Path), not Path: with one #convert block the two are
  // identical, which is exactly when it is cheap to get right; with two, two
  // source types both dropping 'Style' would collapse into one row and one of
  // the two rule-book gaps would vanish.
  function SummarizeUnlinked: TArray<TApplyUnlinked>;
  var
    Rows   : TList<TApplyUnlinked>;
    Keys   : TStringList;               { UpperCase('FromType|Path') -> row index, via Objects }
    PerType: TDictionary<string, Integer>; { UpperCase(FromType) -> converted instances }
    Inst2  : TConvertInstance;
    Item   : TApplyItem;
    U      : TApplyUnlinked;
    K      : string;
    N, Idx : Integer;
  begin
    Rows   := TList<TApplyUnlinked>.Create;
    Keys   := TStringList.Create;
    PerType:= TDictionary<string, Integer>.Create;
    try
      Keys.Sorted:= True;
      Keys.Duplicates:= dupError;
      Keys.CaseSensitive:= False;

      { Denominators: instances of each source type that actually converted.
        A skipped instance produced no Dropped list, so counting it would
        understate every fraction. }
      for Inst2 in Instances do
        if ConvertedInstNames.Contains(Inst2.InstanceName) then
        begin
          K:= UpperCase(Inst2.FromType);
          if not PerType.TryGetValue(K, N) then N:= 0;
          PerType.AddOrSetValue(K, N + 1);
        end;

      { Numerators: one Dropped item per (instance, property). }
      for Item in Items do
      begin
        if (Item.Kind <> aikUnmappedProperty) or (Trim(Item.Path) = '') then Continue;
        K:= UpperCase(Item.FromType + '|' + Item.Path);
        if Keys.Find(K, Idx) then
        begin
          Idx:= Integer(Keys.Objects[Idx]);
          U:= Rows[Idx];
          Inc(U.Sites);
          Rows[Idx]:= U;
        end
        else
        begin
          U:= Default(TApplyUnlinked);
          U.FromType:= Item.FromType;
          U.Path    := Item.Path;
          U.Sites   := 1;
          if not PerType.TryGetValue(UpperCase(Item.FromType), U.Instances) then U.Instances:= 0;
          Rows.Add(U);
          Keys.AddObject(K, TObject(Rows.Count - 1));
        end;
      end;

      { Stable order: by source type, then property, case-insensitively -- not
        by .dfm instance order, which is what emission order would give. }
      Rows.Sort(TComparer<TApplyUnlinked>.Construct(
        function(const L, R: TApplyUnlinked): Integer
        begin
          Result:= CompareText(L.FromType, R.FromType);
          if Result = 0 then Result:= CompareText(L.Path, R.Path);
        end));
      Result:= Rows.ToArray;

      if not AWarnUnlinked then Exit;
      for U in Rows do
      begin
        { '2 of 20', never 'x2': a MINORITY site count is the STRONGER signal
          (the two ParentFont=False buttons somebody deliberately styled), and
          a bare multiplier reads as "rare" and invites a skim. }
        It:= PlainItem(aikUnlinkedSourceProperty, afWarnings,
          Format('%s.%s: no #link carries it -- dropped on %d of %d converted instance(s); add a #link, or #ignore %s to accept the drop',
                 [U.FromType, U.Path, U.Sites, U.Instances, U.Path]));
        It.FromType:= U.FromType;
        It.Path    := U.Path;
        It.FilePath:= ADfmPath;
        Emit(It);
      end;
    finally
      PerType.Free;
      Keys.Free;
      Rows.Free;
    end;
  end;

begin
  Result:= Default(TApplyResult);
  Result.Ok:= False;
  Stores:= ATrees.Stores;
  ATrees.SetScope(AUnitPas, ABook.Rules);  { bare #convert / .dfm class names resolve in THIS unit }

  if not TFile.Exists(AUnitPas) then
  begin Result.Error:= Format('unit .pas not found: %s', [AUnitPas]); Exit; end;
  if not TFile.Exists(ADfmPath) then
  begin Result.Error:= Format('.dfm not found: %s', [ADfmPath]); Exit; end;
  if Length(Stores) = 0 then
  begin Result.Error:= 'no symbol store available (empty AStores)'; Exit; end;

  DfmText:= ReadUnitText(ADfmPath);
  Instances:= FindConvertInstances(DfmText, ABook.Rules, AOnly);
  { C8 N2 / N2a (1.26.0): a retyped inherited instance goes through the same
    loop as an own one (InhIndex tells them apart); a code-only entry joins
    the access-site and uses surfaces only }
  Instances:= Instances + RetypedInstances(AInherited);
  { 1.25.1: a child of a kept parent converts with it, .pas included }
  for var NO: TNestedOnly in NestedOnlyInstances(DfmText, ABook.Rules, AOnly) do Instances:= Instances + [NO.Instance];
  if (Length(Instances) = 0) and not HasInheritedAction(AInherited, INH_ACTION_CODE) then
  begin
    Result.Error:= 'no convertible instances found (no #convert rule matched a .dfm instance, or --only filtered everything out)';
    Exit;
  end;

  { split for line-indexed slicing (surface #3); tekDeleteLines/tekInsertLines
    are 1-based against this same line count, matching TTextEditApplier.Apply's
    own TStringList.Text split. }
  DfmLines:= DfmText.Replace(#13#10, #10).Replace(#13, #10).Split([#10]);

  { PasStore: whichever --db actually has AUnitPas indexed -- every unit-scoped
    lookup below (PasFileSyms, PasFileId, and everything keyed off PasFileId)
    goes through THIS SAME store, since an id is only meaningful within the
    store that produced it. }
  PasStore:= StoreForFile(AUnitPas);
  PasFileSyms:= PasStore.FindSymbolsByFile(AUnitPas);
  if Length(PasFileSyms) = 0 then
    PasFileSyms:= PasStore.FindSymbolsByFile(TPath.GetFullPath(AUnitPas));

  { surface #5 needs the .pas file's own refs (GetReferencesFromFile is
    keyed by file id, not path) to find construction sites. }
  PasFileId:= UnitFileIdIn(PasStore, AUnitPas); { 1.26.5: found the way its symbols were }

  var DfmStore: ISymbolStore:= StoreForFile(ADfmPath);
  DfmFileSyms:= DfmStore.FindSymbolsByFile(ADfmPath);
  if Length(DfmFileSyms) = 0 then
    DfmFileSyms:= DfmStore.FindSymbolsByFile(TPath.GetFullPath(ADfmPath));

  { F/T classes come from ATrees, shared with rule validation: each class's
    members are resolved once per run -- see TConvertTreeCache for the options
    and why referenced components are leaves. }

  PasLines:= TStringList.Create;
  Edits    := TList<TTextEdit>.Create;
  Converted:= TList<string>.Create;
  Warnings := TList<string>.Create;
  ReemitNotes:= TList<string>.Create;
  CreatorSites:= TList<string>.Create;
  AccessSites:= TList<string>.Create;
  Todos    := TList<string>.Create;
  Items    := TList<TApplyItem>.Create;
  ResolvedDefaults:= TList<TApplyResolvedDefault>.Create;
  DoneUnits:= TDictionary<string, Boolean>.Create;
  ToTypesSeen:= TList<string>.Create;
  IntfToTypes:= TDictionary<string, Boolean>.Create;
  ConvertedInstNames:= TList<string>.Create;
  InstFromType:= TDictionary<string, string>.Create;
  InstToType  := TDictionary<string, string>.Create;
  RefFacts    := nil;
  RefFactRows := 0;
  RefFactsAsked:= False;
  try
    PasLines.Text:= ReadUnitText(AUnitPas);

    var StaleDfm: string:= '';
    for Inst in Instances do
    begin
      { -- surface #3 FIRST: the .dfm object-block re-emit. A hard re-emit
        failure skips the WHOLE instance (no .pas retype/uses edits either) --
        see BuildApplyPlan's <returns> remarks: converting the .pas declaration
        while leaving the .dfm block in its OLD (From) shape (or vice versa)
        would hand back a component that neither compiles cleanly against the
        new type nor matches its own .dfm, which is worse than leaving it
        entirely unconverted + warned. }
      var DfmSym: TSymbol:= FindDfmInstanceSymbol(DfmFileSyms, Inst.InstanceName, Inst.FromType);
      if DfmSym.Id = 0 then
      begin
        { TWO CAUSES, ONE SYMPTOM -- and the old message named the wrong one.

          The lookup is against DfmFileSyms, which comes from the INDEX
          (:1647-1650). So it fails either because this .dfm is in no supplied
          --db AT ALL, or because it is indexed and this particular object is
          not in it. The old text asserted the second unconditionally:

            btnTop: could not locate .dfm object block for "btnTop: TabcToggleBtn"
                    in ...\VARINSP.dfm -- instance skipped        ... x20

          On a unit covered by no --db that sentence is FALSE ABOUT THE FILE.
          The converter team verified the .dfm was text, not binary, and that
          all twenty blocks were present at lines 4880, 14705, 17564, ... then
          spent a day disproving three plausible readings the message invited
          (binary .dfm, nesting depth, qualified-vs-bare #convert type) before
          finding the real condition. A merely unhelpful message costs a minute;
          a confidently wrong one costs a day.

          Length(DfmFileSyms) = 0 discriminates them exactly, because
          FindConvertInstances reads the .dfm TEXT (:1621) -- which is why an
          unindexed unit still produces instances to warn about at all.

          THE BEHAVIOUR IS UNCHANGED, deliberately. Requiring an index may be
          load-bearing and nobody asked for it to be relaxed; the instance
          counts and the skip/convert accounting are identical. Only the
          sentence differs.

          The else-branch keeps the ORIGINAL wording -- pinned by
          run_convert_apply_index_precondition.ps1's discrimination control --
          because replacing both branches with the new text would trade one
          false claim for another and make the genuine not-in-the-.dfm case
          undiagnosable. It gains a clause naming the two remaining causes,
          since "indexed but absent" and "indexed but STALE" are both live and
          the reader cannot tell them apart from the old sentence either. }
        var SkipMsg: string;
        if Length(DfmFileSyms) = 0 then
          SkipMsg:= Format('%s: %s is not covered by any supplied --db; convert-apply resolves .dfm blocks through the index. ' +
                           'Index it, or pass a --db that covers it -- instance skipped',
            [Inst.InstanceName, ExtractFileName(AUnitPas)])
        else
          SkipMsg:= Format('%s: could not locate .dfm object block for "%s: %s" in %s ' +
                           '(the .dfm IS indexed, so the object is absent from it or the index is stale) -- instance skipped',
            [Inst.InstanceName, Inst.InstanceName, Inst.FromType, ADfmPath]);
        It:= InstItem(aikInstanceSkipped, afWarnings, SkipMsg);
        It.FilePath:= ADfmPath;
        SkipInstance(It);
        Continue;
      end;

      var BlockStart: Integer:= DfmSym.StartLine;
      var BlockEnd  : Integer:= DfmSym.EndLine;
      { the span came from the index; if the .dfm moved on since (lines added or
        removed, or the file cut short so the span runs past its end), splicing
        would delete the wrong lines -- refuse the unit whole (see StaleDfm below) }
      if (BlockStart < 1) or (BlockEnd < BlockStart) or (BlockEnd > Length(DfmLines)) or
         not DfmSpanHoldsInstance(DfmLines, BlockStart, BlockEnd, Inst.InstanceName) then
      begin
        StaleDfm:= Format('%s: index is stale for this .dfm -- reindex', [Inst.InstanceName]);
        Break;
      end;


      var BlockText: string:= String.Join(#13#10, DfmLines, BlockStart - 1, BlockEnd - BlockStart + 1);
      { the From class is the BLOCK's -- the book's #convert spelling, as the
        rule validation resolved it -- not the .dfm header's bare class name }
      var BookFrom, BookTo: string;
      ConvertRuleSpelling(ABook.Rules, BareTypeTail(Inst.FromType), BookFrom, BookTo);
      var ReemitRes: TReemitResult:= ReemitComponent(BlockText, ABook.Rules,
        ATrees.ClassFor(if BookFrom <> '' then BookFrom else Inst.FromType),
        ATrees.ClassFor(Inst.ToType), ACastLib, ABook.Unreachable);
      if not ReemitRes.Ok then
      begin
        It:= InstItem(aikInstanceSkipped, afWarnings,
          Format('%s: .dfm re-emit failed (%s) -- instance skipped', [Inst.InstanceName, ReemitRes.Error]));
        It.FilePath:= ADfmPath;
        It.Line    := BlockStart;
        SkipInstance(It);
        Continue;
      end;

      { 1.25.1: a block inside one this run already re-emitted -- a TField of a
        converted TTable -- goes INTO that re-emit; its own delete + insert
        would overlap the parent's (see SpliceIntoParent) }
      if SpliceIntoParent(BlockStart, BlockEnd, ReemitRes) then Continue;

      { Instance has cleared the re-emit checkpoint -- it WILL get its #1/#2/#5
        edits below, so it is eligible for surface #4's instance-scoping too.
        Recorded here (not after the whole loop) so a skipped instance's name
        never enters the converted-instance set an access-site rewrite is
        scoped against. }
      ConvertedInstNames.Add(Inst.InstanceName);
      InstFromType.AddOrSetValue(Inst.InstanceName, Inst.FromType);
      InstToType.AddOrSetValue(Inst.InstanceName, Inst.ToType);

      var Indent: string:= LeadingIndent(DfmLines[BlockStart - 1]);
      E:= Default(TTextEdit);
      E.FilePath:= ADfmPath;
      E.Kind    := tekDeleteLines;
      E.Line    := BlockStart;
      E.EndLine := BlockEnd;
      Edits.Add(E);

      E:= Default(TTextEdit);
      E.FilePath:= ADfmPath;
      E.Kind    := tekInsertLines;
      E.Line    := BlockStart - 1; { insert AFTER line BlockStart-1 == at the deleted block's old position }
      E.Text    := ReindentBlock(ReemitRes.DfmText, Indent);
      Edits.Add(E);

      FoldReemitReport(ReemitRes.Report, BlockStart);

      PlanDeclSurfaces(BlockStart);

      { -- surface #2: uses-add for each distinct ToType (once per type). }
      if not DoneUnits.ContainsKey(Inst.ToType) then
      begin
        DoneUnits.Add(Inst.ToType, True);
        ToTypesSeen.Add(Inst.ToType);
      end;
    end;

    AddCodeEntries; { C8 N2a }

    PlanAccessSites;
    var PU: TPasUsesInput:= Default(TPasUsesInput);
    PU.Trees    := ATrees;
    PU.Store    := PasStore;
    PU.FileId   := PasFileId;
    PU.PasLines := PasLines;
    PU.DfmPath  := ADfmPath;
    PU.Book     := ABook;
    PU.Converted:= ConvertedInstNames;
    PU.FromTypes:= InstFromType;
    PU.ToTypes  := InstToType;
    PU.CastLib  := ACastLib;
    var MigEdits: TArray<TTextEdit>;
    var MigItems: TArray<TApplyItem>;
    PlanMigrateSites(PU, AUnitPas, MigEdits, MigItems); { C18 slice 1 }
    for var ME: TTextEdit in MigEdits do Edits.Add(ME);
    for var MI: TApplyItem in MigItems do Emit(MI);
    { 1.38 (D2): identifier #migrate rules -- the unit of each renamed target
      joins the To types the uses surface adds }
    var IdUses, IdIntf: TArray<string>;
    PlanIdentifierMigrates(PU, AUnitPas, MigEdits, MigItems, IdUses, IdIntf);
    for var ME: TTextEdit in MigEdits do Edits.Add(ME);
    for var MI: TApplyItem in MigItems do Emit(MI);
    for var UT: string in IdUses do
      if DoneUnits.TryAdd(UT, True) then ToTypesSeen.Add(UT);
    for var UT: string in IdIntf do IntfToTypes.AddOrSetValue(UT, True);
    Result.Report.PasUses:= CollectPasUses(PU); { 1.27.0; PlanUsesAdditions appends the globals }
    var UsesPlan: TUsesPlan;
    var UnitAdds    : TArray<string>:= nil;
    var UnitIntfAdds: TArray<string>:= nil;
    var Skips       : TArray<TUsesChange>:= nil;
    { a stale .dfm span is folded into the uses-plan refusal below, so
      BuildApplyPlan keeps one exit for it }
    if StaleDfm <> '' then
    begin
      UsesPlan.Ok     := False;
      UsesPlan.Refused:= True;
      UsesPlan.Error  := StaleDfm;
    end
    else PlanUsesAdditions(UsesPlan, UnitAdds, UnitIntfAdds);
    { R26: a removal must not take away the unit an unconverted instance needs
      -- C9: subsumed by the reconciliation, which KEEPS such a unit }
    var Leaves: string:= '';
    if UsesPlan.Ok and not ABook.Reconcile then
      Leaves:= RemovalLeavesUnconverted(ATrees, DfmText, ABook.Rules, ConvertedInstNames, AOnly, UsesPlan.Changes, Skips);
    { C13 N4: a removal that would strand only instances --only left out is
      skipped, not refused -- re-plan keeping those units, then report each }
    if UsesPlan.Ok and (Leaves = '') and (Length(Skips) > 0) then
    begin
      UsesPlan:= PlanUnitRules(AUnitPas, ReadUnitText(AUnitPas), ABook.Rules,
        UnitAdds + SkippedUnits(Skips), UnitIntfAdds);
      if UsesPlan.Ok then
      begin
        UsesPlan.Changes:= UsesPlan.Changes + Skips;
        for var Sk: TUsesChange in Skips do Emit(SkippedRuleItem(ABook.Rules, AUnitPas, Sk));
      end;
    end;
    if UsesPlan.Ok then
      for E in UsesPlan.Edits do Edits.Add(E);
    if Leaves <> '' then
    begin
      UsesPlan.Ok     := False;
      UsesPlan.Refused:= True;
      UsesPlan.Error  := Leaves;
    end;
    { a unit the unit rules refuse (a conditional entry) is refused WHOLE --
      its #convert edits included -- so nothing is half-applied }
    if not UsesPlan.Ok then
    begin
      if UsesPlan.Refused then Result:= TApplyResult.Refusal(UsesPlan.Error)
      else Result.Error:= UsesPlan.Error;
      Exit;
    end;
    Result.Report.UsesChanges:= UsesPlan.Changes;
    Result.Report.Unlinked:= SummarizeUnlinked;

    Result.Edits          := DistinctInLineEdits(Edits.ToArray);
    Result.Report.Converted:= Converted.ToArray;
    Result.Report.Warnings := Warnings.ToArray;
    Result.Report.ReemitNotes:= ReemitNotes.ToArray;
    Result.Report.CreatorSites:= CreatorSites.ToArray;
    Result.Report.AccessSites:= AccessSites.ToArray;
    Result.Report.Todos    := Todos.ToArray;
    Result.Report.Items    := Items.ToArray;
    Result.Report.ResolvedDefaults:= ResolvedDefaults.ToArray;
    Result.Ok:= True;
  finally
    PasLines.Free;
    Edits.Free;
    Converted.Free;
    Warnings.Free;
    ReemitNotes.Free;
    CreatorSites.Free;
    AccessSites.Free;
    Todos.Free;
    Items.Free;
    ResolvedDefaults.Free;
    DoneUnits.Free;
    IntfToTypes.Free;
    ToTypesSeen.Free;
    ConvertedInstNames.Free;
    InstFromType.Free;
    InstToType.Free;
  end;
end;

class function TApplyResult.Refusal(const AReason: string): TApplyResult;
begin
  Result        := Default(TApplyResult);
  Result.Refused:= True;
  Result.Error  := AReason;
end;

function BuildUnitRulesOnlyPlan(const ATrees: TConvertTreeCache; const AUnitPas, ADfmPath: string;
  const ARules: TConversionRuleSet; const AOnly: TArray<string>; AReconcile: Boolean): TApplyResult;
var
  UsesPlan: TUsesPlan;
  Leaves  : string;
  Skips   : TArray<TUsesChange>;
begin
  Result:= Default(TApplyResult);
  if not TFile.Exists(AUnitPas) then
  begin
    Result.Error:= Format('unit .pas not found: %s', [AUnitPas]);
    Exit;
  end;
  if AReconcile then
  begin
    { C9: nothing converts here, so the .dfm as it is decides what stays }
    var RA: TReconcileUnitArgs:= Default(TReconcileUnitArgs);
    RA.UnitPas      := AUnitPas;
    RA.DfmPath      := ADfmPath;
    RA.Rules        := ARules;
    RA.Only         := AOnly;
    RA.PlannerNeeded:= True;
    var Rec: TReconcileOutcome:= ReconcileUnitUses(ATrees, RA);
    Result.Ok                   := Rec.Plan.Ok;
    Result.Refused              := Rec.Plan.Refused;
    Result.Error                := Rec.Plan.Error;
    Result.Edits                := Rec.Plan.Edits;
    Result.Report.UsesChanges   := Rec.Plan.Changes;
    Result.Report.UsesUnresolved:= Rec.Unresolved;
    Result.Report.UsesReconcile := Rec.Status;
    Result.Report.PasUses       := DanglingPasUses(Rec.Dangling);
    if Rec.Plan.Ok then
      for var It: TApplyItem in Rec.Items do
      begin
        Result.Report.Warnings:= Result.Report.Warnings + [It.Text];
        Result.Report.Items   := Result.Report.Items + [It];
      end;
    Exit;
  end;
  UsesPlan:= PlanUnitRules(AUnitPas, ReadUnitText(AUnitPas), ARules, nil);
  { R26: every #convert instance of the .dfm stays unconverted here (--only
    left them all out), so no removal may take away a unit they need }
  Leaves:= '';
  Skips := nil;
  if UsesPlan.Ok and (ADfmPath <> '') and TFile.Exists(ADfmPath) then
    Leaves:= RemovalLeavesUnconverted(ATrees, ReadUnitText(ADfmPath), ARules,
      nil, AOnly, UsesPlan.Changes, Skips);
  { C13 N4: every instance was left out by --only -- skip, do not refuse }
  if UsesPlan.Ok and (Leaves = '') and (Length(Skips) > 0) then
  begin
    UsesPlan:= PlanUnitRules(AUnitPas, ReadUnitText(AUnitPas), ARules, SkippedUnits(Skips));
    if UsesPlan.Ok then
    begin
      UsesPlan.Changes:= UsesPlan.Changes + Skips;
      for var Sk: TUsesChange in Skips do
      begin
        var It: TApplyItem:= SkippedRuleItem(ARules, AUnitPas, Sk);
        Result.Report.Warnings:= Result.Report.Warnings + [It.Text];
        Result.Report.Items   := Result.Report.Items + [It];
      end;
    end;
  end;
  if Leaves <> '' then
  begin
    UsesPlan:= Default(TUsesPlan); { a refusal plans nothing }
    UsesPlan.Refused:= True;
    UsesPlan.Error  := Leaves;
  end;
  Result.Ok                := UsesPlan.Ok;
  Result.Refused           := UsesPlan.Refused;
  Result.Error             := UsesPlan.Error;
  Result.Edits             := UsesPlan.Edits;
  Result.Report.UsesChanges:= UsesPlan.Changes;
end;

end.
