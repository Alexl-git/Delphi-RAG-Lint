unit ConvRules.BlockOps;

{ Pure curation operations over block lists: select, delete, split out, copy out,
  link-level merge PLANNING (PlanMerge), applying a plan (ApplyMerge), and folding
  a whole working set into one file by precedence (Compose). The working set
  itself, file I/O, backups and the VCL form are built on top of this unit, not in it.

  Every operation moves the blocks' RAW TEXT, so a block that was merely moved is
  byte-identical to what it was in its old file -- comments, blank lines and
  unrecognised directives included. Nothing here touches the file system or VCL, so
  all of it is unit-tested against inline fixtures. }

interface

uses
  System.SysUtils
  , System.Classes
  , System.Generics.Collections
  , ConvRules.BlockFile
  , // dl:unit ConvRules.BlockFile accepted -- shares HEADERLESS_KINDS
        ConvRules.Model
  ;

/// <summary>PURE: the blocks at AIndexes, in ASCENDING index order regardless of
/// the order AIndexes were given in (the grid may report checks out of order).
/// Out-of-range indexes are ignored.</summary>
/// <param name="ABlocks"><!-- drag-lint:auto type -->const TRuleBlocks</param>
/// <param name="AIndexes"><!-- drag-lint:auto type -->const TArray&lt;Integer&gt;</param>
/// <returns><!-- drag-lint:auto type -->TRuleBlocks</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: ConvRules.BlockOps.SplitOut (ConvRules.BlockOps.pas)</para>
/// <para>Calls: ConvRules.BlockOps.NormalizeIndexes</para>
/// <para>Pure</para>
/// <seealso cref="ConvRules.BlockOps.NormalizeIndexes"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function SelectBlocks(const ABlocks: TRuleBlocks; const AIndexes: TArray<Integer>): TRuleBlocks;

/// <summary>PURE: ABlocks minus the blocks at AIndexes, order otherwise preserved.</summary>
/// <param name="ABlocks"><!-- drag-lint:auto type -->const TRuleBlocks</param>
/// <param name="AIndexes"><!-- drag-lint:auto type -->const TArray&lt;Integer&gt;</param>
/// <returns><!-- drag-lint:auto -->TRuleBlocks -- Observed: List.ToArray.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: ConvRules.BlockOps.SplitOut (ConvRules.BlockOps.pas), ConvRules.CurationForm.TCurationForm.DoDelete (ConvRules.CurationForm.pas)</para>
/// <para>Calls: ConvRules.BlockOps.DeleteBlocks.Selected, ConvRules.BlockOps.NormalizeIndexes</para>
/// <para>Pure</para>
/// <seealso cref="ConvRules.BlockOps.DeleteBlocks.Selected"/>
/// <seealso cref="ConvRules.BlockOps.NormalizeIndexes"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function DeleteBlocks(const ABlocks: TRuleBlocks; const AIndexes: TArray<Integer>): TRuleBlocks;

/// <summary>PURE: move blocks out -- ARemaining is the source without them,
/// AMoved is the blocks themselves in their original relative order.</summary>
/// <param name="ASource"><!-- drag-lint:auto type -->const TRuleBlocks</param>
/// <param name="AIndexes"><!-- drag-lint:auto type -->const TArray&lt;Integer&gt;</param>
/// <param name="ARemaining"><!-- drag-lint:auto type -->out TRuleBlocks</param>
/// <param name="AMoved"><!-- drag-lint:auto type -->out TRuleBlocks</param>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: ConvRules.CurationForm.TCurationForm.DoSplit (ConvRules.CurationForm.pas)</para>
/// <para>Calls: ConvRules.BlockOps.DeleteBlocks, ConvRules.BlockOps.SelectBlocks</para>
/// <para>Mutates: AMoved (out), ARemaining (out)</para>
/// <seealso cref="ConvRules.BlockOps.DeleteBlocks"/>
/// <seealso cref="ConvRules.BlockOps.SelectBlocks"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure SplitOut(const ASource: TRuleBlocks; const AIndexes: TArray<Integer>; out ARemaining, AMoved: TRuleBlocks);

/// <summary>PURE: the enablement rule for the Split / Delete commands. True only
/// when ASelected names at least one in-range block of ABlocks and none of the
/// blocks it names is headerless (HEADERLESS_KINDS).</summary>
/// <param name="ABlocks">The file's blocks; the selection indexes into these.</param>
/// <param name="ASelected">Selected block indexes; duplicates and out-of-range
/// entries are ignored, and a selection made only of them is no selection.</param>
/// <returns>True when Split and Delete may act on the selection.</returns>
/// <remarks>
/// A preamble or trailer holds file-scope directives that belong to no
/// single rule, so moving or deleting one from the grid would silently strip the
/// book. Before rbkTrailing existed this could only reach the preamble; since
/// 0acff42 an unguarded Delete could remove the 43-line #migrate tail of
/// convrules\BDE-to-FireDAC.rules.
/// <para>There is no Copy command. CopyOut was retired on 2026-09-09 because it
/// left the source intact, manufacturing the duplicate state FindDuplicates
/// reports; a rule may be MOVED between books, never COPIED.</para>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: ConvRules.CurationForm.TCurationForm.DoDelete (ConvRules.CurationForm.pas), ConvRules.CurationForm.TCurationForm.DoSplit (ConvRules.CurationForm.pas), ConvRules.CurationForm.TCurationForm.UpdateEnabled (ConvRules.CurationForm.pas)</para>
/// <para>Calls: ConvRules.BlockOps.NormalizeIndexes</para>
/// <para>Returns: False; True</para>
/// <para>Pure</para>
/// <seealso cref="ConvRules.BlockOps.NormalizeIndexes"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function CanOperateOn(const ABlocks: TRuleBlocks; const ASelected: TArray<Integer>): Boolean;

/// <summary>PURE: the blocks one file contributes to a SELECTIVE compose -- every
/// headerless block (HEADERLESS_KINDS) plus the rule blocks named by ASelected,
/// all in FILE order.</summary>
/// <param name="ABlocks">The file's blocks.</param>
/// <param name="ASelected">Rule-block indexes. Out-of-range, duplicate and
/// headerless indexes are ignored, so a preamble named in the selection is
/// included once, not twice.</param>
/// <returns>The contributed blocks; JoinBlocks of them is the file's share of the
/// composed text.</returns>
/// <remarks>
/// Selecting every rule block returns the file unchanged, so the join is
/// byte-identical to the source; selecting none returns only the preamble and
/// trailer. The preamble travels because an #apply inside a selected block names
/// a #mapping declared there, and the trailer because #migrate is file-scope --
/// see CheckApplyIntegrity, which makes that falsifiable. A user who wants
/// neither removes the FILE from the working set.
/// <para>Compose itself is unchanged: this is applied per input BEFORE Compose
/// folds the set, which keeps Compose's own semantics and tests untouched.</para>
/// <para>A composed book is GENERATED, DISPOSABLE output for --rules, never an
/// authored source, so carrying a #mapping into it is not a second authored copy
/// and does not breach the one-rule-one-place rule.</para>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: ConvRules.WorkingSet.TWorkingSet.ComposeSelected (ConvRules.WorkingSet.pas)</para>
/// <para>Calls: ConvRules.BlockOps.InSelection, ConvRules.BlockOps.NormalizeIndexes</para>
/// <para>Returns: List.ToArray</para>
/// <para>Pure</para>
/// <seealso cref="ConvRules.BlockOps.InSelection"/>
/// <seealso cref="ConvRules.BlockOps.NormalizeIndexes"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function SelectForCompose(const ABlocks: TRuleBlocks; const ASelected: TArray<Integer>): TRuleBlocks;

/// <summary>PURE: ascending, de-duplicated union of two selections over ABlocks;
/// out-of-range indexes are dropped.</summary>
/// <param name="ABlocks">The file's blocks, for the range check.</param>
/// <param name="A">One selection.</param>
/// <param name="B">Another.</param>
/// <returns>The union, ascending and without duplicates.</returns>
/// <remarks>
/// The ONE way every selection source adds to the set -- checkboxes and
/// by-type today, by-tag when the engine deploys #tag support. Keeping the merge
/// in one function is what lets a third source arrive without reworking the
/// other two.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: ConvRules.WorkingSet.TWorkingSet.SelectByTag (ConvRules.WorkingSet.pas), ConvRules.WorkingSet.TWorkingSet.SelectByTypes (ConvRules.WorkingSet.pas), ConvRules.WorkingSet.TWorkingSet.SetSelected (ConvRules.WorkingSet.pas)</para>
/// <para>Calls: ConvRules.BlockOps.NormalizeIndexes</para>
/// <para>Returns: NormalizeIndexes(A + B, Length(ABlocks))</para>
/// <para>Pure</para>
/// <seealso cref="ConvRules.BlockOps.NormalizeIndexes"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function UnionSelections(const ABlocks: TRuleBlocks; const A, B: TArray<Integer>): TArray<Integer>;

/// <summary>PURE: indexes of the rbkConvert blocks whose From type matches a name
/// in ATypeNames, compared on the BARE name, case-insensitively.</summary>
/// <param name="ABlocks">The file's blocks.</param>
/// <param name="ATypeNames">Type names, bare or qualified -- typically the
/// component types found on an examined form.</param>
/// <returns>Ascending block indexes; empty when nothing matches.</returns>
/// <remarks>
/// Matching goes through CatalogFromText and BareTypeName, the same path
/// the form-types panel uses, so the curation window and the panel cannot
/// disagree about which rule covers a type. Headerless blocks are never matched:
/// they carry no #convert, so they cannot answer a type question -- and they
/// travel regardless.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: ConvRules.WorkingSet.TWorkingSet.SelectByTypes (ConvRules.WorkingSet.pas)</para>
/// <para>Calls: ConvRules.RuleCatalog.BareTypeName, ConvRules.RuleCatalog.CatalogFromText, SameText</para>
/// <para>Returns: List.ToArray</para>
/// <para>Pure</para>
/// <seealso cref="ConvRules.RuleCatalog.BareTypeName"/>
/// <seealso cref="ConvRules.RuleCatalog.CatalogFromText"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function BlocksConvertingTypes(const ABlocks: TRuleBlocks; const ATypeNames: TArray<string>): TArray<Integer>;

/// <summary>PURE: indexes of the rbkConvert blocks carrying ATag.</summary>
/// <param name="ABlocks">The file's blocks.</param>
/// <param name="ATag">A tag name; '' matches nothing.</param>
/// <returns>Ascending block indexes; empty when nothing carries the tag.</returns>
/// <remarks>
/// Goes through CatalogFromText and SelectByTag, the same path the
/// catalog uses, so the curation window and the catalog cannot disagree about
/// which rules a tag covers. The THIRD selection source the design left room
/// for -- it lands as one more UnionSelections contributor, with no rework to
/// checkboxes or by-type.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: ConvRules.WorkingSet.TWorkingSet.SelectByTag (ConvRules.WorkingSet.pas)</para>
/// <para>Calls: ConvRules.RuleCatalog.CatalogFromText, ConvRules.RuleCatalog.SelectByTag, Trim</para>
/// <para>Returns: nil; List.ToArray</para>
/// <para>Pure</para>
/// <seealso cref="ConvRules.RuleCatalog.CatalogFromText"/>
/// <seealso cref="ConvRules.RuleCatalog.SelectByTag"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function BlocksWithTag(const ABlocks: TRuleBlocks; const ATag: string): TArray<Integer>;

/// <summary>PURE: the one-line report a selective compose writes per file.</summary>
/// <param name="APath">The file's path; only its file name is shown.</param>
/// <param name="ABlocks">Its blocks.</param>
/// <param name="ASelected">Its selection.</param>
/// <returns>'&lt;name&gt;: N of M rule block(s) selected; file header/trailer travel',
/// or a NO rule blocks form when the selection is empty.</returns>
/// <remarks>
/// A file contributing only file-scope directives is a surprising state
/// worth saying out loud -- its #remove and #migrate lines still reach the job.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: ConvRules.WorkingSet.TWorkingSet.ComposeSelected (ConvRules.WorkingSet.pas)</para>
/// <para>Calls: ConvRules.BlockOps.NormalizeIndexes, ConvRules.BlockOps.RuleBlockCount, ExtractFileName, Format</para>
/// <para>Pure</para>
/// <seealso cref="ConvRules.BlockOps.NormalizeIndexes"/>
/// <seealso cref="ConvRules.BlockOps.RuleBlockCount"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function SelectionReportLine(const APath: string; const ABlocks: TRuleBlocks; const ASelected: TArray<Integer>): string;

type
  /// <summary>One #link inside a block, with its verbatim source line.</summary>
  /// <remarks>
  /// Parsed with TRuleBook so the DSL grammar lives in exactly one place;
  /// Line is the ORIGINAL text and is what gets written, never a re-emission.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: ConvRules.BlockOps.BlockLinks (ConvRules.BlockOps.pas), ConvRules.BlockOps.PlanMerge (ConvRules.BlockOps.pas), declaration (ConvRules.BlockOps.pas)</para>
  /// <para>Used in units: ConvRules.BlockOps</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TBlockLink = record
    Line    : string; // verbatim source line, no terminator
    LinkTo  : string; // target path (left of '<-')
    LinkFrom: string; // source path (right of '<-')
    Cast    : string; // optional cast name ('' = identity)
  end;

  /// <summary>What the merger decided to do with one incoming line or block.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (ConvRules.BlockOps.pas)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TMergeAction = (
    maAppendBlock, // incoming block has no counterpart -> append it whole
    maMergeLink, // incoming #link is missing from the target -> append the line
    maMergeOther, // incoming non-link line not already present -> append the line
    maSkipDuplicate, // identical link already present -> do nothing
    maConflict // target already linked from a different source (or cast)
  );

  /// <summary>One planned merge decision.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: ConvRules.BlockOps.ApplyMerge (ConvRules.BlockOps.pas), ConvRules.BlockOps.MergeReportLines (ConvRules.BlockOps.pas), ConvRules.BlockOps.PlanMerge (ConvRules.BlockOps.pas), ConvRules.BlockOps.TMergePlan.ConflictCount (ConvRules.BlockOps.pas), declaration (ConvRules.BlockOps.pas) (+1 more)</para>
  /// <para>Used in units: ConvRules.BlockOps, ConvRules.CurationForm</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TMergeItem = record
    Action          : TMergeAction;
    TargetBlockIdx  : Integer     ; // index into TMergePlan.Target; -1 for maAppendBlock
    IncomingBlockIdx: Integer     ; // index into TMergePlan.Incoming
    Line            : string      ; // the incoming line, verbatim ('' for maAppendBlock)
    ToPath          : string      ; // contested/merged target path ('' when n/a)
    ExistingLine    : string      ; // maConflict: the target's current #link line
    ExistingFrom    : string      ; // maConflict: its source path
    IncomingFrom    : string      ; // maConflict: the incoming source path
  end;

  /// <summary>A merge worked out but NOT applied. Planning is pure and writes
  /// nothing, which is what lets a conflict be reported before either link is
  /// written (acceptance criterion 6).</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: ConvRules.BlockOps.Compose (ConvRules.BlockOps.pas), ConvRules.CurationForm.TCurationForm.DoMerge (ConvRules.CurationForm.pas), declaration (ConvRules.BlockOps.pas)</para>
  /// <para>Used in units: ConvRules.BlockOps, ConvRules.CurationForm</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TMergePlan = record
    Target  : TRuleBlocks       ;
    Incoming: TRuleBlocks       ;
    Items   : TArray<TMergeItem>;
    /// <summary>How many items need a user decision.</summary>
    /// <returns><!-- drag-lint:auto type -->Integer</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: ConvRules.CurationForm.TCurationForm.DoMerge (ConvRules.CurationForm.pas)</para>
    /// <para>Reads: Items</para>
    /// <para>Pure</para>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function ConflictCount: Integer;
  end; // record

  /// <summary>PURE: the #link lines of one block, parsed via TRuleBook (read-only --
  /// the model is never asked to re-emit).</summary>
  /// <param name="ABlock"><!-- drag-lint:auto type -->const TRuleBlock</param>
  /// <returns><!-- drag-lint:auto -->TArray&lt;TBlockLink&gt; -- Observed: List.ToArray.</returns>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Called from: ConvRules.BlockOps.PlanMerge (ConvRules.BlockOps.pas)</para>
  /// <para>Calls: ConvRules.Model.TRuleBook.Create, ConvRules.Model.TRuleBook.LoadFromString</para>
  /// <para>Pure</para>
  /// <seealso cref="ConvRules.Model.TRuleBook.Create"/>
  /// <seealso cref="ConvRules.Model.TRuleBook.LoadFromString"/>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
function BlockLinks(const ABlock: TRuleBlock): TArray<TBlockLink>;

/// <summary>PURE: work out how AIncoming would fold into ATarget. Blocks are matched
/// by trimmed header, case-insensitively. Within a matched pair: an identical link
/// is skipped; a target already linked from a different source (or with a different
/// cast) is a CONFLICT; a new target -- including one fed by an already-used source
/// -- is merged; non-link lines not already present in the target are merged
/// verbatim, where "already present" is an EXACT match after trimming (case-
/// SENSITIVE -- non-link content is never deduped just because it differs only in
/// case). An incoming block with no counterpart is appended whole.</summary>
/// <param name="ATarget"><!-- drag-lint:auto type -->const TRuleBlocks</param>
/// <param name="AIncoming"><!-- drag-lint:auto type -->const TRuleBlocks</param>
/// <returns>A plan; ATarget and AIncoming are copied into it unmodified.</returns>
/// <remarks>
/// The case-SENSITIVE dedup of non-link lines is deliberate but it does
/// sit oddly in a DSL that is otherwise case-insensitive: '#Default X = 1' and
/// '#default X = 1' are not "identical", so a merge keeps BOTH and the engine then
/// sees the directive twice. The trade is intentional -- dropping a line the user
/// wrote is worse than keeping a near-duplicate they can see and delete.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: ConvRules.BlockOps.Compose (ConvRules.BlockOps.pas), ConvRules.CurationForm.TCurationForm.DoMerge (ConvRules.CurationForm.pas)</para>
/// <para>Calls: ConvRules.BlockOps.BlockLinks, ConvRules.BlockOps.BlockOtherLines, ConvRules.BlockOps.IndexOfHeader, ConvRules.BlockOps.PlanMerge.FindTargetLink, ConvRules.BlockOps.PlanMerge.TargetHasLine, Default, SameText, Trim</para>
/// <para>Pure</para>
/// <seealso cref="ConvRules.BlockOps.BlockLinks"/>
/// <seealso cref="ConvRules.BlockOps.BlockOtherLines"/>
/// <seealso cref="ConvRules.BlockOps.IndexOfHeader"/>
/// <seealso cref="ConvRules.BlockOps.PlanMerge.FindTargetLink"/>
/// <seealso cref="ConvRules.BlockOps.PlanMerge.TargetHasLine"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function PlanMerge(const ATarget, AIncoming: TRuleBlocks): TMergePlan;

type
  /// <summary>How one conflict is settled.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: ConvRules.CurationForm.TCurationForm.DoMerge (ConvRules.CurationForm.pas), declaration (ConvRules.BlockOps.pas)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TMergeResolution = (mrKeepExisting, mrTakeIncoming);

  /// <summary>One file of a working set, in composition order.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: ConvRules.WorkingSet.TWorkingSet.ComposeAll (ConvRules.WorkingSet.pas), ConvRules.WorkingSet.TWorkingSet.ComposeSelected (ConvRules.WorkingSet.pas), declaration (ConvRules.BlockOps.pas)</para>
  /// <para>Used in units: ConvRules.BlockOps, ConvRules.WorkingSet</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TComposeInput = record
    Path  : string     ;
    Blocks: TRuleBlocks;
  end;

  /// <summary>What a composition did: a human-readable line per decision that was
  /// not a plain no-op, plus the two counts the status bar shows.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: ConvRules.BlockOps.Compose (ConvRules.BlockOps.pas), ConvRules.CurationForm.TCurationForm.DoCompose (ConvRules.CurationForm.pas), ConvRules.WorkingSet.TWorkingSet.ComposeAll (ConvRules.WorkingSet.pas), declaration (ConvRules.BlockOps.pas), declaration (ConvRules.WorkingSet.pas) (+1 more)</para>
  /// <para>Used in units: ConvRules.BlockOps, ConvRules.CurationForm, ConvRules.WorkingSet</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TComposeReport = record
    Lines        : TArray<string>;
    ResolvedCount: Integer       ; // collisions auto-resolved by precedence
    AppendedCount: Integer       ; // whole blocks appended
  end;

  /// <summary>PURE: apply a plan and return the merged block list. AResolutions is
  /// indexed by CONFLICT ORDINAL (the i-th maConflict item in plan order); a missing
  /// entry means mrKeepExisting. mrTakeIncoming replaces the existing #link line in
  /// place, verbatim; every other write appends the incoming line verbatim to the end
  /// of the matched block. The target blocks are never re-emitted.</summary>
  /// <param name="APlan"><!-- drag-lint:auto type -->const TMergePlan</param>
  /// <param name="AResolutions"><!-- drag-lint:auto type -->const TArray&lt;TMergeResolution&gt;</param>
  /// <returns><!-- drag-lint:auto -->TRuleBlocks -- Observed: Blocks.ToArray.</returns>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Called from: ConvRules.BlockOps.Compose (ConvRules.BlockOps.pas), ConvRules.CurationForm.TCurationForm.DoMerge (ConvRules.CurationForm.pas)</para>
  /// <para>Calls: ConvRules.BlockOps.AppendLinesToBlock, ConvRules.BlockOps.EnsureTrailingEol, ConvRules.BlockOps.ReplaceLineInBlock, ConvRules.BlockOps.ResolutionAt</para>
  /// <para>Pure</para>
  /// <seealso cref="ConvRules.BlockOps.AppendLinesToBlock"/>
  /// <seealso cref="ConvRules.BlockOps.EnsureTrailingEol"/>
  /// <seealso cref="ConvRules.BlockOps.ReplaceLineInBlock"/>
  /// <seealso cref="ConvRules.BlockOps.ResolutionAt"/>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
function ApplyMerge(const APlan: TMergePlan; const AResolutions: TArray<TMergeResolution>): TRuleBlocks;

/// <summary>PURE: one report line per non-trivial decision, naming AIncomingName
/// (the file the blocks came from) so a composed report is readable.</summary>
/// <param name="APlan"><!-- drag-lint:auto type -->const TMergePlan</param>
/// <param name="AResolutions"><!-- drag-lint:auto type -->const TArray&lt;TMergeResolution&gt;</param>
/// <param name="AIncomingName"><!-- drag-lint:auto type -->const string</param>
/// <returns><!-- drag-lint:auto -->TArray&lt;string&gt; -- Observed: List.ToArray.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: ConvRules.BlockOps.Compose (ConvRules.BlockOps.pas), ConvRules.CurationForm.TCurationForm.DoMerge (ConvRules.CurationForm.pas)</para>
/// <para>Calls: ConvRules.BlockOps.ResolutionAt, Format, Trim</para>
/// <para>Pure</para>
/// <seealso cref="ConvRules.BlockOps.ResolutionAt"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function MergeReportLines(const APlan: TMergePlan; const AResolutions: TArray<TMergeResolution>; const AIncomingName: string): TArray<string>;

/// <summary>PURE: fold the working set into one file, top to bottom, with the merge
/// semantics above. Earlier files win: every collision is auto-resolved in favour of
/// the earlier file and listed in AReport (composing three large books must not mean
/// answering hundreds of prompts). Returns the composed file text.</summary>
/// <param name="AInputs"><!-- drag-lint:auto type -->const TArray&lt;TComposeInput&gt;</param>
/// <param name="AReport"><!-- drag-lint:auto type -->out TComposeReport</param>
/// <returns><!-- drag-lint:auto -->string -- Observed: JoinBlocks(Acc).</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: ConvRules.WorkingSet.TWorkingSet.ComposeAll (ConvRules.WorkingSet.pas), ConvRules.WorkingSet.TWorkingSet.ComposeSelected (ConvRules.WorkingSet.pas)</para>
/// <para>Calls: ConvRules.BlockFile.JoinBlocks, ConvRules.BlockOps.ApplyMerge, ConvRules.BlockOps.MergeReportLines, ConvRules.BlockOps.PlanMerge, Default, ExtractFileName</para>
/// <para>Mutates: AReport (out)</para>
/// <seealso cref="ConvRules.BlockFile.JoinBlocks"/>
/// <seealso cref="ConvRules.BlockOps.ApplyMerge"/>
/// <seealso cref="ConvRules.BlockOps.MergeReportLines"/>
/// <seealso cref="ConvRules.BlockOps.PlanMerge"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function Compose(const AInputs: TArray<TComposeInput>; out AReport: TComposeReport): string;

/// <summary>PURE: the block, guaranteed to end with a line terminator. A file whose
/// last line had no EOL would otherwise glue itself onto whatever is appended after
/// it, producing '#link R <- S#convert X.T -> Y.T'.</summary>
/// <param name="ABlock"><!-- drag-lint:auto type -->const TRuleBlock</param>
/// <returns><!-- drag-lint:auto -->TRuleBlock -- Observed: ABlock.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: ConvRules.BlockOps.ApplyMerge (ConvRules.BlockOps.pas), ConvRules.BlockOps.ConcatBlocks (ConvRules.BlockOps.pas)</para>
/// <para>Calls: ConvRules.BlockFile.BlockEol</para>
/// <para>Pure</para>
/// <seealso cref="ConvRules.BlockFile.BlockEol"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function EnsureTrailingEol(const ABlock: TRuleBlock): TRuleBlock;

/// <summary>PURE: AFirst followed by ASecond, with AFirst's last block terminated so
/// the two never run together. Used when appending split-out blocks to an existing
/// file (a move, not a merge).</summary>
/// <param name="AFirst"><!-- drag-lint:auto type -->const TRuleBlocks</param>
/// <param name="ASecond"><!-- drag-lint:auto type -->const TRuleBlocks</param>
/// <returns><!-- drag-lint:auto type -->TRuleBlocks</returns>
/// <remarks>
/// AFirst is COPIED, not aliased: a dynamic array is a reference and an
/// element write does not copy-on-write, so returning AFirst itself would terminate
/// the caller's last block -- and callers hand in TWorkingSet.Item(i).Blocks, which
/// shares the working set's stored array.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: ConvRules.CurationForm.TCurationForm.WriteBlocksTo (ConvRules.CurationForm.pas)</para>
/// <para>Calls: ConvRules.BlockOps.EnsureTrailingEol, Copy</para>
/// <para>Pure</para>
/// <seealso cref="ConvRules.BlockOps.EnsureTrailingEol"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ConcatBlocks(const AFirst, ASecond: TRuleBlocks): TRuleBlocks;

/// <summary>PURE: the headers of AIncoming that AExisting ALREADY has, matched the
/// way PlanMerge matches them (same Kind, trimmed header, case-insensitively).</summary>
/// <param name="AExisting"><!-- drag-lint:auto type -->const TRuleBlocks</param>
/// <param name="AIncoming"><!-- drag-lint:auto type -->const TRuleBlocks</param>
/// <returns><!-- drag-lint:auto -->TArray&lt;string&gt; -- Observed: List.ToArray.</returns>
/// <remarks>
/// A split/copy APPENDS verbatim without merging, and its target dialog has
/// no overwrite prompt, so a duplicated header silently leaves the target holding two
/// blocks for one rule -- this is what the form warns from. Preamble blocks have no
/// header and are never reported.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: ConvRules.CurationForm.TCurationForm.WriteBlocksTo (ConvRules.CurationForm.pas)</para>
/// <para>Calls: ConvRules.BlockOps.IndexOfHeader, Trim</para>
/// <para>Pure</para>
/// <seealso cref="ConvRules.BlockOps.IndexOfHeader"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function DuplicateHeaders(const AExisting, AIncoming: TRuleBlocks): TArray<string>;

implementation

uses
  { RuleCatalog is used ONLY here, in the implementation: by-type selection goes
    through CatalogFromText/BareTypeName so this unit and the form-types panel
    cannot disagree about which rule covers a type. No cycle -- RuleCatalog uses
    ConvRules.Model, never ConvRules.BlockOps.

    System.Generics.Defaults was dropped on 2026-09-09: a dead import since
    d6c46d0, referencing no symbol here. TList.Sort reaches TComparer.Default
    through System.Generics.Collections' own uses, so no import is owed for it. }
        ConvRules.RuleCatalog
  ;

{ Ascending, de-duplicated copy of a selection. }
function NormalizeIndexes(const AIndexes: TArray<Integer>; ACount: Integer): TArray<Integer>;
var
  List: TList<Integer>;
  i   : Integer       ;
begin
  List:= TList<Integer>.Create;
  try
    for i in AIndexes do
      if (i >= 0) and (i < ACount) and (List.IndexOf(i) < 0) then
        List.Add(i);
    List.Sort;
    Result:= List.ToArray;
  finally
    List.Free;
  end;
end; // function

function SelectBlocks(const ABlocks: TRuleBlocks; const AIndexes: TArray<Integer>): TRuleBlocks;
var
  Idx: TArray<Integer>;
  i  : Integer        ;
begin
  Idx:= NormalizeIndexes(AIndexes, Length(ABlocks));
  SetLength(Result, Length(Idx));
  for i:= 0 to High(Idx) do
    Result[i]:= ABlocks[Idx[i]];
end;

function DeleteBlocks(const ABlocks: TRuleBlocks; const AIndexes: TArray<Integer>): TRuleBlocks;
var
  Idx : TArray<Integer>  ;
  List: TList<TRuleBlock>;
  i   : Integer          ;

  function Selected(AIndex: Integer): Boolean;
  var
    k: Integer;
  begin
    for k in Idx do
      if k = AIndex then
        Exit(True);
    Result:= False;
  end;

begin
  Idx:= NormalizeIndexes(AIndexes, Length(ABlocks));
  List:= TList<TRuleBlock>.Create;
  try
    for i:= 0 to High(ABlocks) do
      if not Selected(i) then
        List.Add(ABlocks[i]);
    Result:= List.ToArray;
  finally
    List.Free;
  end;
end; // begin

procedure SplitOut(const ASource: TRuleBlocks; const AIndexes: TArray<Integer>; out ARemaining, AMoved: TRuleBlocks);
begin
  AMoved    := SelectBlocks(ASource, AIndexes);
  ARemaining:= DeleteBlocks(ASource, AIndexes);
end;

function CanOperateOn(const ABlocks: TRuleBlocks; const ASelected: TArray<Integer>): Boolean;
var
  Idx: TArray<Integer>;
  i  : Integer        ;
begin
  { NormalizeIndexes drops out-of-range and duplicate entries, so a selection made
    only of stale indexes correctly reads as no selection at all. }
  Idx:= NormalizeIndexes(ASelected, Length(ABlocks));
  if Length(Idx) = 0 then
    Exit(False);
  for i in Idx do
    if ABlocks[i].Kind in HEADERLESS_KINDS then
      Exit(False);
  Result:= True;
end;

{ True when AIndex is named by the normalised selection AIdx. }
function InSelection(const AIdx: TArray<Integer>; AIndex: Integer): Boolean;
var
  i: Integer;
begin
  for i in AIdx do
    if i = AIndex then
      Exit(True);
  Result:= False;
end;

{ How many blocks of ABlocks carry a rule of their own (i.e. are selectable). }
function RuleBlockCount(const ABlocks: TRuleBlocks): Integer;
var
  B: TRuleBlock;
begin
  Result:= 0;
  for B in ABlocks do
    if not (B.Kind in HEADERLESS_KINDS) then
      Inc(Result);
end;

function SelectForCompose(const ABlocks: TRuleBlocks; const ASelected: TArray<Integer>): TRuleBlocks;
var
  Idx : TArray<Integer>  ;
  List: TList<TRuleBlock>;
  i   : Integer          ;
begin
  Idx:= NormalizeIndexes(ASelected, Length(ABlocks));
  List:= TList<TRuleBlock>.Create;
  try
    { One pass in FILE order, so the output order never depends on the order the
      grid reported its checks in -- and a headerless block named in the
      selection is still emitted exactly once, by this branch. }
    for i:= 0 to High(ABlocks) do
      if (ABlocks[i].Kind in HEADERLESS_KINDS) or InSelection(Idx, i) then
        List.Add(ABlocks[i]);
    Result:= List.ToArray;
  finally
    List.Free;
  end;
end; // function

function UnionSelections(const ABlocks: TRuleBlocks; const A, B: TArray<Integer>): TArray<Integer>;
begin
  Result:= NormalizeIndexes(A + B, Length(ABlocks));
end;

function BlocksConvertingTypes(const ABlocks: TRuleBlocks; const ATypeNames: TArray<string>): TArray<Integer>;
var
  List: TList<Integer>;
  Cat : TRuleCatalog  ;
  i   : Integer       ;
  Name: string        ;
begin
  List:= TList<Integer>.Create;
  try
    for i:= 0 to High(ABlocks) do
    begin
      if ABlocks[i].Kind in HEADERLESS_KINDS then
        Continue;
      { The block's own text yields its own catalog entry, so entry and block
        index stay aligned by construction -- no second lookup to get wrong. }
      Cat:= CatalogFromText(ABlocks[i].RawText, '');
      if Length(Cat) = 0 then
        Continue;
      for Name in ATypeNames do
        if SameText(BareTypeName(Name), BareTypeName(Cat[0].FromType)) then
        begin
          List.Add(i);
          Break;
        end;
    end; // for
    Result:= List.ToArray;
  finally
    List.Free;
  end; // try
end; // function

function BlocksWithTag(const ABlocks: TRuleBlocks; const ATag: string): TArray<Integer>;
var
  List: TList<Integer>;
  i   : Integer       ;
begin
  Result:= nil;
  if Trim(ATag) = '' then
    Exit;
  List:= TList<Integer>.Create;
  try
    for i:= 0 to High(ABlocks) do
    begin
      if ABlocks[i].Kind in HEADERLESS_KINDS then
        Continue;
      { The block's own text yields its own catalog entry, so a hit IS this
        block -- no second lookup to get wrong. }
      if Length(SelectByTag(CatalogFromText(ABlocks[i].RawText, ''), ATag)) > 0 then
        List.Add(i);
    end;
    Result:= List.ToArray;
  finally
    List.Free;
  end; // try
end; // function

function SelectionReportLine(const APath: string; const ABlocks: TRuleBlocks; const ASelected: TArray<Integer>): string;
var
  Total : Integer;
  Picked: Integer;
  i     : Integer;
begin
  Total:= RuleBlockCount(ABlocks);
  { Count only RULE blocks: a headerless index in the selection travels anyway
    and must not be reported as a chosen rule. }
  Picked:= 0;
  for i in NormalizeIndexes(ASelected, Length(ABlocks)) do
    if not (ABlocks[i].Kind in HEADERLESS_KINDS) then
      Inc(Picked);
  if Picked = 0 then
    Result:= Format('%s: NO rule blocks selected -- only its file header/trailer ' + 'travel (its #remove / #unuse / #migrate still reach the job)', [ExtractFileName(APath)])
  else
    Result:= Format('%s: %d of %d rule block(s) selected; file header/trailer travel', [ExtractFileName(APath), Picked, Total]);
end; // function

function TMergePlan.ConflictCount: Integer;
var
  It: TMergeItem;
begin
  Result:= 0;
  for It in Items do
    if It.Action = maConflict then
      Inc(Result);
end;

function BlockLinks(const ABlock: TRuleBlock): TArray<TBlockLink>;
var
  Book: TRuleBook        ;
  List: TList<TBlockLink>;
  i   : Integer          ;
  L   : TBlockLink       ;
begin
  List:= TList<TBlockLink>.Create;
  Book:= TRuleBook.Create;
  try
    Book.LoadFromString(ABlock.RawText);
    for i:= 0 to Book.Nodes.Count - 1 do
      if Book.Nodes[i].Kind = rnkLink then
      begin
        L.Line    := Book.Nodes[i].Raw;
        L.LinkTo  := Book.Nodes[i].LinkTo;
        L.LinkFrom:= Book.Nodes[i].LinkFrom;
        L.Cast    := Book.Nodes[i].Cast;
        List.Add(L);
      end;
    Result:= List.ToArray;
  finally
    Book.Free;
    List.Free;
  end; // try
end; // function

{ Every line of a block except its header, its #link lines and its blank lines --
  i.e. #default / #ignore / #note / comments / unknown directives. }
function BlockOtherLines(const ABlock: TRuleBlock): TArray<string>;
var
  Lines: TArray<TRawLine>;
  List : TList<string>   ;
  i    : Integer         ;
  i0   : Integer         ;
begin
  List:= TList<string>.Create;
  try
    Lines:= SplitRawLines(ABlock.RawText);
    // Headerless kinds start at line 0; every other kind's line 0 IS its header.
    if ABlock.Kind in HEADERLESS_KINDS then
      i0:= 0
    else
      i0:= 1;
    for i:= i0 to High(Lines) do
      if (Trim(Lines[i].Text) <> '')
         and not SameText(FirstToken(Lines[i].Text), '#link') then
        List.Add(Lines[i].Text);
    Result:= List.ToArray;
  finally
    List.Free;
  end; // try
end; // function

{ Index of the target block whose trimmed header equals AHeader, or -1. }
function IndexOfHeader(const ABlocks: TRuleBlocks; const AHeader: string; AKind: TRuleBlockKind): Integer;
var
  i: Integer;
begin
  for i:= 0 to High(ABlocks) do
    if (ABlocks[i].Kind = AKind) and SameText(Trim(ABlocks[i].Header), Trim(AHeader)) then
      Exit(i);
  Result:= -1;
end;

function DuplicateHeaders(const AExisting, AIncoming: TRuleBlocks): TArray<string>;
var
  List: TList<string>;
  i   : Integer      ;
begin
  List:= TList<string>.Create;
  try
    for i:= 0 to High(AIncoming) do
      // Headerless kinds have no header to duplicate; matching them on '' would
      // report every preamble and trailer as a collision with every other one.
      if not (AIncoming[i].Kind in HEADERLESS_KINDS)
         and (IndexOfHeader(AExisting, AIncoming[i].Header, AIncoming[i].Kind) >= 0) then
        List.Add(Trim(AIncoming[i].Header));
    Result:= List.ToArray;
  finally
    List.Free;
  end; // try
end; // function

function PlanMerge(const ATarget, AIncoming: TRuleBlocks): TMergePlan;
var
  Items   : TList<TMergeItem> ;
  bi      : Integer           ;
  ti      : Integer           ;
  TgtLinks: TArray<TBlockLink>;
  IncLinks: TArray<TBlockLink>;
  IncOther: TArray<string>    ;
  TgtOther: TArray<string>    ;
  Item    : TMergeItem        ;
  L       : TBlockLink        ;
  S       : string            ;
  Existing: TBlockLink        ;

  function FindTargetLink(const AToPath: string; out AFound: TBlockLink): Boolean;
  var
    k: Integer;
  begin
    for k:= 0 to High(TgtLinks) do
      if SameText(TgtLinks[k].LinkTo, AToPath) then
      begin
        AFound:= TgtLinks[k];
        Exit(True);
      end;
    Result:= False;
  end;

{ EXACT match after trimming -- case-SENSITIVE. Non-#link content (comments,
    #default/#ignore/#note, unknown directives) is never silently deduped just
    because it differs only in case; only a truly identical line is skipped.
    CONSEQUENCE, in a DSL that is otherwise case-insensitive: '#Default X = 1' and
    '#default X = 1' both survive a merge and the engine sees the directive twice.
    Accepted -- see the <remarks> on PlanMerge; losing a line the user wrote would
    be the worse failure. }
  function TargetHasLine(const ALine: string): Boolean;
  var
    k: Integer;
  begin
    for k:= 0 to High(TgtOther) do
      if Trim(TgtOther[k]) = Trim(ALine) then
        Exit(True);
    Result:= False;
  end;

begin
  Result.Target  := ATarget;
  Result.Incoming:= AIncoming;
  Items:= TList<TMergeItem>.Create;
  try
    for bi:= 0 to High(AIncoming) do
    begin
      ti:= IndexOfHeader(ATarget, AIncoming[bi].Header, AIncoming[bi].Kind);
      if ti < 0 then
      begin
        Item:= Default(TMergeItem);
        Item.Action:= maAppendBlock;
        Item.TargetBlockIdx:= -1;
        Item.IncomingBlockIdx:= bi;
        Items.Add(Item);
        Continue;
      end;

      TgtLinks:= BlockLinks     (ATarget  [ti]);
      TgtOther:= BlockOtherLines(ATarget  [ti]);
      IncLinks:= BlockLinks     (AIncoming[bi]);
      IncOther:= BlockOtherLines(AIncoming[bi]);

      for L in IncLinks do
      begin
        Item:= Default(TMergeItem);
        Item.TargetBlockIdx  := ti;
        Item.IncomingBlockIdx:= bi;
        Item.Line  := L.Line;
        Item.ToPath:= L.LinkTo;
        if not FindTargetLink(L.LinkTo, Existing) then
          Item.Action:= maMergeLink // missing (incl. fan-out)
        else if SameText(Existing.LinkFrom, L.LinkFrom)
                and SameText(Existing.Cast, L.Cast) then
          Item.Action:= maSkipDuplicate
        else
        begin
          Item.Action:= maConflict;
          Item.ExistingLine:= Existing.Line;
          Item.ExistingFrom:= Existing.LinkFrom;
          Item.IncomingFrom:= L       .LinkFrom;
        end;
        Items.Add(Item);
      end; // for

      for S in IncOther do
        if not TargetHasLine(S) then
        begin
          Item:= Default(TMergeItem);
          Item.Action          := maMergeOther;
          Item.TargetBlockIdx  := ti;
          Item.IncomingBlockIdx:= bi;
          Item.Line            := S;
          Items.Add(Item);
        end;
    end; // for
    Result.Items:= Items.ToArray;
  finally
    Items.Free;
  end; // try
end; // begin

{ Append whole lines to the end of a block, using the block's own terminator and
  first making sure the block ends with one.

  CALLER BEWARE -- "the end of the block" is literally the end of RawText. That is
  right for an rbkConvert/rbkPreamble/rbkTrailing block, which has no closing line, and WRONG for
  an rbkCast/rbkEnum block, whose RawText INCLUDES its 'end' line and any trailing
  blanks (see SplitCastLibBlocks): the appended line lands AFTER 'end', outside the
  block body, and nothing here can tell. That is why the curation form refuses a
  merge or a compose whose TARGET is a catalog -- see ConvRules.BlockFile's
  GrammarAcceptsMerge. Do not "fix" it by teaching this function to insert before
  'end': that is a feature with its own design questions (where among the body lines,
  what about trailing comments) and needs deciding, not guessing. }
function AppendLinesToBlock(const ABlock: TRuleBlock; const ALines: TArray<string>): TRuleBlock;
var
  Eol: string;
  S  : string;
begin
  Result:= ABlock;
  if Length(ALines) = 0 then
    Exit;
  Eol:= BlockEol(ABlock);
  if (Result.RawText <> '')
     and not (Result.RawText.EndsWith(#10) or Result.RawText.EndsWith(#13)) then
    Result.RawText:= Result.RawText + Eol;
  for S in ALines do
  begin
    Result.RawText:= Result.RawText + S + Eol;
    Inc(Result.EndLine);
  end;
end; // function

{ Replace the FIRST line equal to AOld with ANew, keeping every terminator. }
function ReplaceLineInBlock(const ABlock: TRuleBlock; const AOld, ANew: string): TRuleBlock;
var
  Lines: TArray<TRawLine>;
  i    : Integer         ;
  Done : Boolean         ;
begin
  Result:= ABlock;
  Lines:= SplitRawLines(ABlock.RawText);
  Done:= False;
  Result.RawText:= '';
  for i:= 0 to High(Lines) do
  begin
    if (not Done) and (Lines[i].Text = AOld) then
    begin
      Result.RawText:= Result.RawText + ANew + Lines[i].Eol;
      Done:= True;
    end
    else
      Result.RawText:= Result.RawText + Lines[i].Text + Lines[i].Eol;
  end;
end; // function

function EnsureTrailingEol(const ABlock: TRuleBlock): TRuleBlock;
begin
  Result:= ABlock;
  if (Result.RawText <> '')
     and not (Result.RawText.EndsWith(#10) or Result.RawText.EndsWith(#13)) then
    Result.RawText:= Result.RawText + BlockEol(Result);
end;

function ConcatBlocks(const AFirst, ASecond: TRuleBlocks): TRuleBlocks;
var
  i: Integer;
begin
  // Copy, never alias: the element write below would otherwise reach through into
  // AFirst itself (a dynamic array is a reference; only SetLength uniquifies).
  Result:= Copy(AFirst);
  if Length(Result) > 0 then
    Result[High(Result)]:= EnsureTrailingEol(Result[High(Result)]);
  for i:= 0 to High(ASecond) do
  begin
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)]:= ASecond[i];
  end;
end; // function

{ The resolution for the AConflictOrdinal-th conflict (default: keep existing). }
function ResolutionAt(const AResolutions: TArray<TMergeResolution>; AConflictOrdinal: Integer): TMergeResolution;
begin
  if (AConflictOrdinal >= 0) and (AConflictOrdinal <= High(AResolutions)) then
    Result:= AResolutions[AConflictOrdinal]
  else
    Result:= mrKeepExisting;
end;

function ApplyMerge(const APlan: TMergePlan; const AResolutions: TArray<TMergeResolution>): TRuleBlocks;
var
  Blocks: TList<TRuleBlock>;
  i     : Integer          ;
  cOrd  : Integer          ;
  It    : TMergeItem       ;
begin
  Blocks:= TList<TRuleBlock>.Create;
  try
    for i:= 0 to High(APlan.Target) do
      Blocks.Add(APlan.Target[i]);
    cOrd:= 0;
    for i:= 0 to High(APlan.Items) do
    begin
      It:= APlan.Items[i];
      case It.Action of
        maAppendBlock:
        begin
          // terminate whatever is currently last, or the two blocks run together
          if Blocks.Count > 0 then
            Blocks[Blocks.Count - 1]:= EnsureTrailingEol(Blocks[Blocks.Count - 1]);
          Blocks.Add(APlan.Incoming[It.IncomingBlockIdx]);
        end;
        maMergeLink, maMergeOther:
          Blocks[It.TargetBlockIdx]:= AppendLinesToBlock(Blocks[It.TargetBlockIdx], [It.Line]);
        maConflict:
        begin
          if ResolutionAt(AResolutions, cOrd) = mrTakeIncoming then
            Blocks[It.TargetBlockIdx]:= ReplaceLineInBlock(Blocks[It.TargetBlockIdx], It.ExistingLine, It.Line);
          Inc(cOrd);
        end;
        maSkipDuplicate: ; // nothing to do
      end; // case
    end; // for
    Result:= Blocks.ToArray;
  finally
    Blocks.Free;
  end; // try
end; // function

function MergeReportLines(const APlan: TMergePlan; const AResolutions: TArray<TMergeResolution>; const AIncomingName: string): TArray<string>;
var
  List: TList<string>;
  i   : Integer      ;
  cOrd: Integer      ;
  It  : TMergeItem   ;
begin
  List:= TList<string>.Create;
  try
    cOrd:= 0;
    for i:= 0 to High(APlan.Items) do
    begin
      It:= APlan.Items[i];
      case It.Action of
        maAppendBlock:
          List.Add(Format('%s: appended block %s', [AIncomingName, Trim(APlan.Incoming[It.IncomingBlockIdx].Header)]));
        maMergeLink:
          List.Add(Format('%s: merged %s', [AIncomingName, Trim(It.Line)]));
        maMergeOther:
          List.Add(Format('%s: merged line %s', [AIncomingName, Trim(It.Line)]));
        maConflict:
        begin
          if ResolutionAt(AResolutions, cOrd) = mrTakeIncoming then
            List.Add(Format(
                '%s: conflict on %s -- took incoming (%s <- %s), dropped (%s <- %s)', [AIncomingName, It.ToPath, It.ToPath, It.IncomingFrom, It.ToPath, It.ExistingFrom]))
          else
            List.Add(Format( '%s: conflict on %s -- kept earlier (%s <- %s), dropped (%s <- %s)', [AIncomingName, It.ToPath, It.ToPath, It.ExistingFrom, It.ToPath, It.IncomingFrom]));
          Inc(cOrd);
        end;
        maSkipDuplicate: ; // a duplicate is a no-op, not worth a report line
      end; // case
    end; // for
    Result:= List.ToArray;
  finally
    List.Free;
  end; // try
end; // function

function Compose(const AInputs: TArray<TComposeInput>; out AReport: TComposeReport): string;
var
  Acc  : TRuleBlocks  ;
  Plan : TMergePlan   ;
  Lines: TList<string>;
  i    : Integer      ;
  k    : Integer      ;
  Name : string       ;
begin
  AReport:= Default(TComposeReport);
  if Length(AInputs) = 0 then
    Exit('');
  Acc:= AInputs[0].Blocks;
  Lines:= TList<string>.Create;
  try
    for i:= 1 to High(AInputs) do
    begin
      Name:= ExtractFileName(AInputs[i].Path);
      Plan:= PlanMerge(Acc, AInputs[i].Blocks);
      for k:= 0 to High(Plan.Items) do
      case Plan.Items[k].Action of
        maConflict   : Inc(AReport.ResolvedCount);
        maAppendBlock: Inc(AReport.AppendedCount);
      end;
      Lines.AddRange(MergeReportLines(Plan, nil, Name)); // nil = keep earlier
      Acc:= ApplyMerge(Plan, nil);
    end; // for
    AReport.Lines:= Lines.ToArray;
    Result:= JoinBlocks(Acc);
  finally
    Lines.Free;
  end; // try
end; // function

end.
