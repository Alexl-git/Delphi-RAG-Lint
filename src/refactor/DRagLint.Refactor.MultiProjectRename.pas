unit DRagLint.Refactor.MultiProjectRename;

/// <summary>Multi-project rename support: which configured indexes OWN a
/// source file, found by the file's FULL PATH in each index's files table.</summary>
/// <remarks>Spec: docs\superpowers\specs\2026-10-13-multi-project-rename.md,
/// criteria 8a-8e. A shared unit is compiled by several projects, and a rename
/// that rewrites only one of them breaks the rest; this unit names all of them.
/// There is NO disk sweep of project files and no folder-derived candidate
/// subset: the manifest lists every DB, and each DB's files table -- built from
/// its compile closure -- is the authority (owner ruling 2026-10-13).
/// Pinned by tests\autotest\run_rename_owners_harness.ps1.
/// All .pas source: strict 7-bit ASCII, CRLF line endings, no BOM.</remarks>

interface

uses
  System.SysUtils
  , DRagLint.Core.Model
  , DRagLint.Index.Manifest
  , DRagLint.Lint.Config
  , DRagLint.Refactor.NamingFix
  , DRagLint.Refactor.TextEdit
  ;

const
  /// <summary>RefreshOwner's AReason for an owner with no project file.</summary>
  REASON_FOLDER_DB = 'no project file -- folder DBs are not reindexed by a rename';
  /// <summary>RefreshOwner's AReason for a project owner whose index carries
  /// ANOTHER project's project_tag (the DB is some other project's closure).
  /// Format arguments: the stored tag, the owner's project file NAME, the
  /// project file, the DB path.</summary>
  /// <remarks>Never reindexed: an incremental `index --project` keeps the
  /// other closure's rows, so only the --rebuild named here can fix it.</remarks>
  REASON_TAG_MISMATCH = 'index was built from project %s, not %s -- rebuild it: '
    + 'drag-lint index --project %s --db %s --rebuild';
  /// <summary>The evidence text for project members the index does not hold.
  /// Format arguments: how many, and the first few member paths ', '-joined
  /// (', ...' appended when there are more).</summary>
  REASON_MEMBERS_MISSING = '%d project member(s) not in the index: %s';
  /// <summary>RefreshOwner's AReason when an apply's reindex still left
  /// members out. Format arguments: the REASON_MEMBERS_MISSING text, the
  /// project file, the DB path.</summary>
  REASON_MEMBERS_STILL_MISSING = 'still missing after reindex: %s -- rebuild it: '
    + 'drag-lint index --project %s --db %s --rebuild';

type
  /// <summary>What kind of index owns the file.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Refactor.MultiProjectRename.pas)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TOwnerKind = (
    /// <summary>A project (closure) or project-less folder DB: project code.</summary>
    okProject,
    /// <summary>A registry-library DB: not project code, so a rename must be
    /// refused (criterion 8d) -- by the CALLER, which reports why.</summary>
    okLibrary);

  /// <summary>One index whose files table holds the file being renamed.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Refactor.MultiProjectRename.pas), DRagLint.Refactor.MultiProjectRename.FindRenameOwners (DRagLint.Refactor.MultiProjectRename.pas), DRagLint.Refactor.MultiProjectRename.OwnerOf (DRagLint.Refactor.MultiProjectRename.pas), DRagLint.Refactor.MultiProjectRename.StaleEvidence (DRagLint.Refactor.MultiProjectRename.pas), DRagLint.Refactor.MultiProjectRename.TagMismatch (DRagLint.Refactor.MultiProjectRename.pas) (+1 more)</para>
  /// <para>Used in units: DRagLint.Refactor.MultiProjectRename</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TRenameOwner = record
    /// <summary>Absolute path of the owning .sqlite index, as the plan resolved it.</summary>
    DbPath: string;
    /// <summary>Manifest section name, shown to the user.</summary>
    SectionName: string;
    /// <summary>Absolute .dproj/.dpr/.dpk of a closure section; '' for a
    /// library section and for a folder-tree section (which has no project
    /// file to reindex, so a caller treats it as unverified).</summary>
    ProjectFile: string;
    /// <summary>Project or library; see TOwnerKind.</summary>
    Kind: TOwnerKind;
  end; // record

  /// <summary>The result of probing every configured index for one file.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Refactor.MultiProjectRename.pas), DRagLint.CLI.PlanMultiOwnerNaming (DRagLint.CLI.pas), DRagLint.Refactor.MultiProjectRename.BlockReason (DRagLint.Refactor.MultiProjectRename.pas), DRagLint.Refactor.MultiProjectRename.FindRenameOwners (DRagLint.Refactor.MultiProjectRename.pas), DRagLint.Refactor.MultiProjectRename.OpenOwners (DRagLint.Refactor.MultiProjectRename.pas)</para>
  /// <para>Used in units: DRagLint.CLI, DRagLint.Refactor.MultiProjectRename</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TOwnerDiscovery = record
    /// <summary>How many DISTINCT databases were asked (criterion 8e's "of N").</summary>
    Probed: Integer;
    /// <summary>Every index that holds the file, preferred DB first, then plan
    /// order. Library owners included, Kind = okLibrary.</summary>
    Owners: TArray<TRenameOwner>;
    /// <summary>'dbpath: reason' for each index that could not be read
    /// (criterion 8c) -- ownership unknown, never "not an owner". A DB that
    /// exists but cannot be opened (locked, corrupt) lands here.</summary>
    Unknown: TArray<string>;
    /// <summary>'section (dbpath)' for each configured index whose DB FILE does
    /// not exist (Ruling 14): no index, so the project is not checked -- not an
    /// owner, not unknown, not counted in Probed, and never blocking.</summary>
    Unindexed: TArray<string>;
  end; // record

  /// <summary>Whether an owning DB may be used for a rename, after RefreshOwner.</summary>
  /// <remarks>Spec criteria 3-5.</remarks>
  TOwnerFreshness = (
    /// <summary>Nothing changed on disk since the DB was indexed; used as is.</summary>
    ofFresh,
    /// <summary>Was stale, was reindexed, and is fresh now.</summary>
    ofReindexed,
    /// <summary>Could not be opened, could not be reindexed, or is still stale
    /// afterwards: the project counts as UNVERIFIED for the rename (criterion 5).</summary>
    ofUnverified,
    /// <summary>A PREVIEW only (no reindex callback, Ruling 12): stale, not
    /// reindexed, and planned on its data as it is. Never blocking; the apply
    /// reindexes it and re-plans.</summary>
    ofStale);

  /// <summary>One owning index's part in a rename plan.</summary>
  /// <remarks>Value type. In TMultiRenamePlan.Owners it describes the owner
  /// (RefCount 0); in TTargetPlan.Owners it also counts that owner's edits.</remarks>
  TOwnerReport = record
    /// <summary>The owner, as FindRenameOwners returned it.</summary>
    Owner: TRenameOwner;
    /// <summary>RefreshOwner's verdict; ofUnverified for a library owner and
    /// for a project DB that could not be opened after its refresh.</summary>
    Freshness: TOwnerFreshness;
    /// <summary>'' when usable; otherwise why the owner is unverified.</summary>
    Reason: string;
    /// <summary>Edits this owner contributed for the target OUTSIDE the
    /// target's own file (the shared unit), before de-duplication.</summary>
    RefCount: Integer;
  end; // record

  /// <summary>Whether a planned rename is written.</summary>
  TRenameDecision = (
    /// <summary>Free in every owner, edits built and merged: apply it.</summary>
    rdApply,
    /// <summary>Unsafe in some owner (unknown, unverified, library, taken,
    /// unresolved, conflicting edits): write nothing for it.</summary>
    rdDropped);

  /// <summary>The plan for ONE naming target across every owning index.</summary>
  /// <remarks>Value type; owns nothing.</remarks>
  TTargetPlan = record
    /// <summary>The target as the first owner that resolved it built it.</summary>
    Target: TNamingTarget;
    /// <summary>The chosen name for rdApply; for rdDropped the name the rename
    /// wanted (the first candidate), '' when there is none.</summary>
    NewName: string;
    /// <summary>Apply or dropped.</summary>
    Decision: TRenameDecision;
    /// <summary>'' for rdApply; for rdDropped why, naming the project or
    /// library first, e.g. 'project B: name MyConst already declared in uB'.</summary>
    Reason: string;
    /// <summary>rdApply: every owner with its RefCount (an nsLocal target: the
    /// one owner it was built from). rdDropped: every owner, RefCount 0.</summary>
    Owners: TArray<TOwnerReport>;
    /// <summary>Merged, de-duplicated edits; nil for rdDropped.</summary>
    Edits: TArray<TTextEdit>;
  end; // record

  /// <summary>A rename plan for the naming findings of ONE file.</summary>
  TMultiRenamePlan = record
    /// <summary>The discovery the plan was built from, unchanged.</summary>
    Discovery: TOwnerDiscovery;
    /// <summary>One report per Discovery.Owners entry, same order, RefCount 0:
    /// what the `rename-project:` lines print.</summary>
    Owners: TArray<TOwnerReport>;
    /// <summary>One plan per distinct target Key, in finding order.</summary>
    Targets: TArray<TTargetPlan>;
  end; // record

/// <summary>Probes every index the manifest configures for APlatform and
/// reports which of them hold AFilePath, which do not, and which could not be
/// asked.</summary>
/// <param name="AManifest">Parsed manifest; its RootDir anchors relative paths.
/// Only read.</param>
/// <param name="APlatform">Platform whose library expansion is probed, e.g.
/// 'Win64'. Project and folder sections carry no platform and are always
/// probed. '' probes every platform a library section declares.</param>
/// <param name="AFilePath">Absolute path of the source file. Matched by FULL
/// PATH (case-insensitive), never by unit name (criterion 8a).</param>
/// <param name="APreferredDb">The DB the caller started from; when it is an
/// owner it is listed first. '' for no preference. Compared case-insensitively
/// after expansion.</param>
/// <returns>Probed = number of distinct existing DB paths asked (duplicates
/// folded case-insensitively); Owners = every dmMember DB, preferred first,
/// then plan order; Unknown = 'dbpath: reason' for every dmUnknown DB;
/// Unindexed = 'section (dbpath)' for every configured DB whose file does not
/// exist (Ruling 14).</returns>
/// <remarks>
/// Raises nothing of its own: an unreadable DB lands in Unknown, not
/// in an exception. A DB file that does not exist is never opened (so never
/// created) and is not "unknown": a never-built section has no index to ask. A library owner is returned rather than refused here so
/// the caller can name the library in its refusal (criterion 8d).
/// Reads the registry (library path expansion, via ResolvePlan) and opens each
/// DB read-only, closing it before the next. Not thread-safe only in so far as
/// ResolvePlan is not; touches no shared state of its own.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.PlanMultiOwnerNaming (DRagLint.CLI.pas)</para>
/// <para>Calls: Default, DRagLint.Index.Plan.ResolvePlan, DRagLint.Project.Resolver.TProjectResolver.Create, DRagLint.Refactor.MultiProjectRename.DbKey, DRagLint.Refactor.MultiProjectRename.OwnerOf, DRagLint.Storage.FileMembership.DbMembership, FileExists, SameText</para>
/// <para>Returns: Default(TOwnerDiscovery)</para>
/// <para>Complexity: 14 (cyclomatic, outer body), 69 lines (full implementation)</para>
/// <seealso cref="DRagLint.Index.Plan.ResolvePlan"/>
/// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.Create"/>
/// <seealso cref="DRagLint.Refactor.MultiProjectRename.DbKey"/>
/// <seealso cref="DRagLint.Refactor.MultiProjectRename.OwnerOf"/>
/// <seealso cref="DRagLint.Storage.FileMembership.DbMembership"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function FindRenameOwners(const AManifest: TIndexManifest; const APlatform, AFilePath,
  APreferredDb: string): TOwnerDiscovery;

/// <summary>Makes one owning DB fresh before a rename uses it, or says why it
/// cannot (spec criteria 3-5).</summary>
/// <param name="AOwner">The owner to check. Only DbPath and ProjectFile are read.</param>
/// <param name="AReindex">Runs an incremental `index --project` as
/// AReindex(ProjectFile, DbPath) and returns True on success. Supplied by the
/// caller (the CLI) so this unit never links DRagLint.CLI. Called at most once,
/// and only for an owner with a project file whose DB opened and was stale.
/// nil for a PREVIEW (Ruling 12): nothing is reindexed and nothing is written.</param>
/// <param name="AReason">'' for ofFresh and ofReindexed; for ofStale the
/// REASON_MEMBERS_MISSING text and/or '&lt;n&gt; changed file(s)', '; '-joined
/// in that order (or the missing-stamp text); otherwise why the owner is
/// unverified -- REASON_TAG_MISMATCH, REASON_FOLDER_DB, 'reindex failed: index
/// --project &lt;file&gt;', REASON_MEMBERS_STILL_MISSING, 'still stale after
/// reindex: &lt;first path&gt; -- if this DB was once widened by a folder
/// index, rebuild it: ...', or the message of whatever was raised.</param>
/// <returns>ofFresh when ChangedFilePaths is empty, the DB carries its
/// INDEXED_AT_KEY stamp and (for a project owner) holds every declared member;
/// ofStale when it is stale, has a project file and AReindex is nil;
/// ofReindexed when it was stale and AReindex made it fresh; ofUnverified
/// otherwise (a stale folder DB is unverified in a preview too, and a project
/// tag mismatch is unverified in a preview and an apply alike).</returns>
/// <remarks>
/// <para>A DB without the INDEXED_AT_KEY stamp is STALE, not fresh: nothing
/// says a completed run ever wrote it. A completed `index --project` writes it.</para>
/// <para>Per-row freshness cannot see a row that is ABSENT, so a project owner
/// is also checked as a whole (INBOX rename-owner-without-target-reports-fresh):
/// (1) a non-empty PROJECT_TAG_KEY that is not SanitizeProjectTag of the project
/// file's base name means the DB is another project's closure -- unverified at
/// once, never reindexed; an empty tag (an index older than the stamp) is no
/// mismatch. (2) A declared member -- a .dproj DCCReference .pas, or a .dpr/.dpk
/// uses name with a same-named .pas in the project folder -- that exists on
/// disk but has no files row is stale evidence, handled like a changed file.
/// Units the closure reaches only transitively are not checked.</para>
/// <para>Criterion 3 (changed files only) is met by the incremental
/// `index --project` itself, which skips every up-to-date file; an in-process
/// per-file path would duplicate DoIndex's resolve stages (Task 4 spike,
/// ledger). A folder DB (ProjectFile = '') is never reindexed: `index &lt;dir&gt;
/// --db` is the call that widens a project DB, so it is not made here.</para>
/// <para>Raises nothing: every exception becomes ofUnverified with its message.
/// The store is opened read-only and released before AReindex runs.</para>
/// </remarks>
function RefreshOwner(const AOwner: TRenameOwner; const AReindex: TFunc<string, string, Boolean>;
  out AReason: string): TOwnerFreshness;

/// <summary>Builds the rename of the naming findings of ONE file across every
/// index that owns that file: one new name free in all of them, and the merged
/// edits of all of them -- or the reason the rename is unsafe.</summary>
/// <param name="ADiscovery">FindRenameOwners' result for the file. Owners are
/// refreshed and opened in this order (criterion 2).</param>
/// <param name="AFindings">The file's naming findings (the CLI passes only the
/// opt-in naming rules). EVERY finding gets a plan: one no usable owner store
/// built a target for is rdDropped with the block reason (fix round 1).</param>
/// <param name="ANaming">Naming config supplying candidates and prefixes.</param>
/// <param name="AReindex">Passed to RefreshOwner for each project owner:
/// AReindex(ProjectFile, DbPath) runs an incremental `index --project`. nil
/// for a PREVIEW (Ruling 12): no owner is reindexed, a stale one is ofStale and
/// planned on its current data, and its stale-position or unresolved results
/// do not drop a target -- the plan is provisional for that owner, and the
/// apply (which passes a callback) reindexes it and plans again.</param>
/// <returns>Owners: one report per owner. Targets: one plan per target Key, and one
/// rdDropped plan per finding no opened store resolved (no owner opened, or all
/// unverified) -- so a refusal is never silent.
/// An nsGlobal target is rdDropped when the discovery has an Unknown DB, any
/// owner is a library (8d) or unverified, any opened store does not resolve it
/// tsReady, no candidate is free in EVERY opened store, a store's edits hit a
/// stale position, or two stores produce different edits for one span
/// (criterion 8). Otherwise NewName is the first candidate free everywhere and
/// Edits the union of every store's edits, exact duplicates dropped (key
/// lower(file)|line|col|endcol|text, criterion 7).</returns>
/// <remarks>
/// <para>"Free" in a store = in FreeCandidates (same-scope ConflictReason) AND
/// no other symbol of that name is declared at unit scope anywhere in that
/// project, nor at any scope in a file the rename edits -- a same-named
/// declaration there would capture the renamed references.</para>
/// <para>An nsLocal target is routine-local, so no other project can reference
/// it: it is built ONCE, from the first opened store, and the owner
/// refusals above do not apply to it.</para>
/// <para>Opens each usable owner DB read-only, and releases every store before
/// returning. Raises nothing of its own; an owner whose store cannot be opened
/// is unverified.</para>
/// Pinned by tests\autotest\run_multi_project_rename.ps1.
/// </remarks>
function PlanMultiProjectRename(const ADiscovery: TOwnerDiscovery;
  const AFindings: TArray<TLintFinding>; const ANaming: TNamingConfig;
  const AReindex: TFunc<string, string, Boolean>): TMultiRenamePlan;

/// <summary>The text a `rename-project:` line prints for AFreshness.</summary>
/// <param name="AFreshness">The owner's freshness.</param>
/// <returns>'fresh', 'reindexed', 'stale' or 'unverified'.</returns>
/// <remarks>Pure. The IDE plugin parses these words.</remarks>
function OwnerFreshnessText(AFreshness: TOwnerFreshness): string;

/// <summary>Unions every owner's edits for one target into one set, written
/// against ONE spelling of each file.</summary>
/// <param name="AParts">One edit list per owner, in owner order.</param>
/// <param name="APreferredPath">The spelling to use for that file (the target's
/// own file, as --file named it); '' for none. Every other file keeps the
/// first spelling any owner used.</param>
/// <param name="AMerged">Out: the merged edits; nil when the result is a conflict.</param>
/// <returns>'' on success; otherwise why the edits conflict.</returns>
/// <remarks>An exact duplicate (same file case-insensitively, line, col, end
/// col and text) is kept once; two DIFFERENT edits at one file/line/col are a
/// conflict (criterion 8). Every surviving edit's FilePath is rewritten to the
/// file's one canonical spelling (Ruling 13): two owners store BASICS.PAS and
/// Basics.pas, and the applier must see one file, back it up once and check
/// its edits together. Pure; pinned by run_rename_owners_harness.ps1 P1-P2.</remarks>
function MergeEdits(const AParts: TArray<TArray<TTextEdit>>; const APreferredPath: string;
  out AMerged: TArray<TTextEdit>): string;

/// <summary>The write-time all-or-nothing guard over a run's rename plans:
/// turns every rdApply plan whose edit set FindStaleEdit calls stale into
/// rdDropped.</summary>
/// <param name="APlans">Every plan of the run; updated in place (Decision,
/// Reason, Edits).</param>
/// <param name="AAllOrNothing">True for a single fix (--fix-line, criterion
/// 9): when ANY plan is dropped here, EVERY other rdApply plan is dropped too,
/// so the run writes no rename edit at all. False for a batch (criterion 10):
/// only the stale plans are dropped.</param>
/// <param name="AEdits">Out: the edits of the plans that are still rdApply.</param>
/// <param name="ANotes">Out: one 'Old -> New file:line (stale)' text per plan
/// dropped because its own edit went stale (what `rename-dropped-at-write:`
/// prints).</param>
/// <returns>How many plans were turned from rdApply to rdDropped.</returns>
/// <remarks>Reads the files the edits name (via FindStaleEdit); writes
/// nothing. Pinned by run_rename_owners_harness.ps1 checks AW1-AW4.</remarks>
function GuardPlansAtWrite(var APlans: TArray<TTargetPlan>; AAllOrNothing: Boolean;
  out AEdits: TArray<TTextEdit>; out ANotes: TArray<string>): Integer;

/// <summary>The write-time all-or-nothing check for one multi-project rename:
/// is any of its edits no longer applicable to the file as it is on disk
/// NOW?</summary>
/// <param name="AEdits">One target's merged edits (TTargetPlan.Edits).</param>
/// <param name="AStale">Out: the first edit that failed; Default when none did.</param>
/// <returns>True when a tekReplaceInLine edit with an ExpectText no longer holds
/// it at [Col, EndCol) of Line (case-insensitive -- the same rule
/// TTextEditApplier applies per edit), or its file is gone. Edits of other
/// kinds, and unguarded ones, are not checked.</returns>
/// <remarks>The applier drops a stale edit and writes the rest; for a rename
/// that crosses projects that is a half-rename, so the caller checks the
/// WHOLE set first and writes none of it when this returns True (fix round 1,
/// ruling 8). Reads each file once (ANSI); writes nothing. Pinned by
/// run_rename_owners_harness.ps1 checks G1-G4.</remarks>
function FindStaleEdit(const AEdits: TArray<TTextEdit>; out AStale: TTextEdit): Boolean;
implementation

uses
  System.Classes
  , System.Generics.Collections
  , System.StrUtils
  , System.IOUtils
  , DRagLint.Core.Interfaces
  , DRagLint.Refactor.Rename
  , DRagLint.Storage.SQLite
  , DRagLint.Index.Freshness // dl:unit DRagLint.Index.Freshness accepted -- StaleEvidence calls ChangedFilePaths and reads the INDEXED_AT_KEY stamp the freshness module defines; the const travels with that call
  , DRagLint.Index.Plan
  , DRagLint.Project.Resolver
  , DRagLint.Project.Members
  , DRagLint.Project.Coherence // dl:unit DRagLint.Project.Coherence accepted -- TagMismatch reads the PROJECT_TAG_KEY stamp this module defines beside ProjectTagConflicts, which compares it; the const travels with that call
  , DRagLint.Lint.ProjectChecks.Parse
  , DRagLint.Storage.FileMembership
  ;

function DbKey(const ADbPath: string): string;
begin
  Result:= if ADbPath = '' then '' else LowerCase(ExpandFileName(ADbPath));
end; // function

function OwnerOf(const AManifest: TIndexManifest; const ASection: TPlanSection): TRenameOwner;
var
  Sec: TIndexSection;
begin
  Result:= Default(TRenameOwner);
  Result.DbPath     := ASection.DbPath;
  Result.SectionName:= ASection.Name;
  Result.Kind       := if ASection.Mode = smLibrary then okLibrary else okProject;
  { smFolderTree stays '': a project-less folder DB has nothing to reindex. }
  if (ASection.Mode = smClosure) and AManifest.FindSection(ASection.Name, Sec) then
    Result.ProjectFile:= SectionProjectFile(AManifest, Sec);
end; // function

function FindRenameOwners(const AManifest: TIndexManifest; const APlatform, AFilePath,
  APreferredDb: string): TOwnerDiscovery;
var
  Resolver : TProjectResolver ;
  Plan     : TIndexPlan       ;
  Filter   : TArray<string>   ;
  Seen     : TList<string>    ;
  Owners   : TList<TRenameOwner>;
  Unknown  : TList<string>    ;
  Unindexed: TList<string>   ;
  Item     : TPlanSection     ;
  Key      : string           ;
  Reason   : string           ;
  Member   : TDbMembership    ;
  PrefKey  : string           ;
  I        : Integer          ;
begin
  Result:= Default(TOwnerDiscovery);
  Filter:= nil;
  if APlatform <> '' then Filter:= [APlatform];
  Resolver:= TProjectResolver.Create;
  try
    Plan:= ResolvePlan(AManifest, Filter, Resolver);
  finally
    Resolver.Free;
  end; // try

  Seen   := TList<string>.Create;
  Owners := TList<TRenameOwner>.Create;
  Unknown:= TList<string>.Create;
  Unindexed:= TList<string>.Create;
  try
    for Item in Plan.Items do
    begin
      if (Item.Platform <> '') and (APlatform <> '') and not SameText(Item.Platform, APlatform) then Continue;
      Key:= DbKey(Item.DbPath);
      if (Key = '') or Seen.Contains(Key) then Continue;
      Seen.Add(Key);
      { Ruling 14: no file = no index -- not unknown, not probed, not opened. }
      if not FileExists(Item.DbPath) then
      begin
        Unindexed.Add(Item.Name + ' (' + Item.DbPath + ')');
        Continue;
      end;
      Member:= DbMembership(Item.DbPath, AFilePath, Reason);
      if Member = dmMember then Owners.Add(OwnerOf(AManifest, Item))
      else if Member = dmUnknown then Unknown.Add(Item.DbPath + ': ' + Reason);
    end; // for

    { Preferred DB first; the rest keep plan order. }
    PrefKey:= DbKey(APreferredDb);
    if PrefKey <> '' then
      for I:= 0 to Owners.Count - 1 do
        if DbKey(Owners[I].DbPath) = PrefKey then
        begin
          if I > 0 then Owners.Move(I, 0);
          Break;
        end;

    Result.Probed   := Seen.Count - Unindexed.Count;
    Result.Owners   := Owners.ToArray;
    Result.Unknown  := Unknown.ToArray;
    Result.Unindexed:= Unindexed.ToArray;
  finally
    Unindexed.Free;
    Unknown.Free;
    Owners .Free;
    Seen   .Free;
  end; // try
end; // function

const
  { How many missing members REASON_MEMBERS_MISSING names before ', ...'. }
  MAX_MEMBER_EXAMPLES = 3;

{ Adds APath to AList when the file exists and is not listed yet (AList is
  case-insensitive). }
procedure AddMember(AList: TStringList; const APath: string);
begin
  if TFile.Exists(APath) and (AList.IndexOf(APath) < 0) then AList.Add(APath);
end; // procedure

{ The .pas members AProjectFile DECLARES, absolute, existing on disk, in
  declaration order: the .dproj's DCCReferences, then each .dpr/.dpk uses name
  that has a same-named .pas in the project folder. A .dpr finds its sibling
  .dproj and a .dproj its sibling .dpr/.dpk. Units the closure reaches only
  transitively are not members (out of scope). Reads files; writes nothing. }
function DeclaredMembers(const AProjectFile: string): TArray<string>;
var
  Dproj    : string     ;
  Prog     : string     ;
  Ref      : string     ;
  Name     : string     ;
  StartLine: Integer    ;
  List     : TStringList;
begin
  if SameText(ExtractFileExt(AProjectFile), '.dproj') then
  begin
    Dproj:= AProjectFile;
    Prog := FindSiblingProgramFile(AProjectFile);
  end
  else
  begin
    Dproj:= ChangeFileExt(AProjectFile, '.dproj');
    Prog := AProjectFile;
  end;
  List:= TStringList.Create;
  try
    for Ref in ReadDCCReferences(Dproj) do
      if SameText(ExtractFileExt(Ref), '.pas') then
        AddMember(List, if TPath.IsPathRooted(Ref) then Ref else TPath.GetFullPath(TPath.Combine(ExtractFilePath(Dproj), Ref)));
    if Prog <> '' then
      for Name in ExtractUsesNames(Prog, StartLine) do
        AddMember(List, TPath.Combine(ExtractFilePath(AProjectFile), Name + '.pas'));
    Result:= List.ToStringArray;
  finally
    List.Free;
  end; // try
end; // function

{ REASON_MEMBERS_MISSING for the members of AProjectFile that AStore holds no
  files row for; '' when it holds every one. Read-only. }
function MissingMembers(const AStore: ISymbolStore; const AProjectFile: string): string;
var
  C    : TMemberCoherence;
  Names: TArray<string>  ;
  Count: Integer         ;
begin
  Count:= 0;
  Names:= nil;
  for C in ComputeCoherence(AStore, PairDfmSiblings(DeclaredMembers(AProjectFile))) do
    if not C.Indexed then
    begin
      Inc(Count);
      if Count <= MAX_MEMBER_EXAMPLES then Names:= Names + [C.Member.UnitPath];
    end;
  if Count = 0 then Exit('');
  Result:= Format(REASON_MEMBERS_MISSING, [Count, string.Join(', ', Names) + (if Count > MAX_MEMBER_EXAMPLES then ', ...' else '')]);
end; // function

{ REASON_TAG_MISMATCH when the DB of a PROJECT owner is stamped with another
  project's tag; '' when the tags agree or the DB carries none. Read-only;
  raises when the DB cannot be opened. }
function TagMismatch(const AOwner: TRenameOwner): string;
var
  Store: ISymbolStore;
  Tag  : string      ;
begin
  Store:= TSQLiteSymbolStore.Create(AOwner.DbPath, True);
  Tag  := Trim(Store.GetMetaValue(PROJECT_TAG_KEY));
  if not ProjectTagConflicts(Tag, AOwner.ProjectFile) then Exit('');
  Result:= Format(REASON_TAG_MISMATCH, [Tag, ExtractFileName(AOwner.ProjectFile), AOwner.ProjectFile, AOwner.DbPath]);
end; // function

{ '' when the DB of AOwner is fresh; otherwise what makes it stale -- the
  first changed path, the missing completed-run stamp, or (a project owner)
  the REASON_MEMBERS_MISSING text. AChanged: how many files changed (0 for a
  missing stamp). AMissing: the members text, '' when none are missing or the
  stamp is. Read-only; raises when the DB cannot be opened or read. }
function StaleEvidence(const AOwner: TRenameOwner; out AChanged: Integer; out AMissing: string): string;
var
  Store  : ISymbolStore  ;
  Changed: TArray<string>;
begin
  AChanged:= 0;
  AMissing:= '';
  { Read-only never CREATES: a missing path raises instead of leaving an empty
    database behind. }
  Store:= TSQLiteSymbolStore.Create(AOwner.DbPath, True);
  if Store.GetMetaValue(INDEXED_AT_KEY) = '' then Exit('index carries no ' + INDEXED_AT_KEY + ' stamp');
  Changed := ChangedFilePaths(Store);
  AChanged:= Length(Changed);
  if AOwner.ProjectFile <> '' then AMissing:= MissingMembers(Store, AOwner.ProjectFile);
  Result  := if AChanged > 0 then Changed[0] else AMissing;
end; // function

{ A preview's ofStale reason: the members text, then the changed-file count,
  '; '-joined; AEvidence itself (the missing stamp) when neither applies. }
function PreviewStaleText(const AEvidence, AMissing: string; AChanged: Integer): string;
var
  Parts: TArray<string>;
begin
  Parts:= nil;
  if AMissing <> '' then Parts:= Parts + [AMissing];
  if AChanged > 0 then Parts:= Parts + [Format('%d changed file(s)', [AChanged])];
  Result:= if Parts = nil then AEvidence else string.Join('; ', Parts);
end; // function

function RefreshOwner(const AOwner: TRenameOwner; const AReindex: TFunc<string, string, Boolean>;
  out AReason: string): TOwnerFreshness;
var
  Evidence: string ;
  Missing : string ;
  Changed : Integer;
begin
  AReason:= '';
  try
    { Another project's closure: no reindex of THIS project can repair it. }
    if AOwner.ProjectFile <> '' then AReason:= TagMismatch(AOwner);
    if AReason <> '' then Exit(ofUnverified);
    Evidence:= StaleEvidence(AOwner, Changed, Missing);
    if Evidence = '' then Exit(ofFresh);
    if AOwner.ProjectFile = '' then
    begin
      AReason:= REASON_FOLDER_DB;
      Exit(ofUnverified);
    end;
    { A preview never reindexes (Ruling 12): say how stale, plan on it as is. }
    if not Assigned(AReindex) then
    begin
      AReason:= PreviewStaleText(Evidence, Missing, Changed);
      Exit(ofStale);
    end;
    if not AReindex(AOwner.ProjectFile, AOwner.DbPath) then
    begin
      AReason:= 'reindex failed: index --project ' + AOwner.ProjectFile;
      Exit(ofUnverified);
    end;
    Evidence:= StaleEvidence(AOwner, Changed, Missing);
    Result  := if Evidence = '' then ofReindexed else ofUnverified;
    { Still missing members, or (M5) rows a folder-target index once swept in:
      outside the closure, no incremental run visits them -- only a rebuild. }
    if (Evidence <> '') and (Changed = 0) and (Missing <> '') then
      AReason:= Format(REASON_MEMBERS_STILL_MISSING, [Missing, AOwner.ProjectFile, AOwner.DbPath])
    else if Evidence <> '' then
      AReason:= Format('still stale after reindex: %s -- if this DB was once widened by a folder index, '
        + 'rebuild it: drag-lint index --project %s --db %s --rebuild', [Evidence, AOwner.ProjectFile, AOwner.DbPath]);
  except
    on E: Exception do
    begin
      AReason:= E.Message;
      Result := ofUnverified;
    end;
  end; // try
end; // function

const
  REASON_LIBRARY = 'a library unit is not project code';

type
  { One owner while a plan is built: its report, its read-only store (nil when
    it is not usable) and the targets BuildNamingTargets built against it. }
  TOwnerState = record
    Report : TOwnerReport;
    Store  : ISymbolStore;
    Targets: TArray<TNamingTarget>;
  end; // record

function OwnerFreshnessText(AFreshness: TOwnerFreshness): string;
begin
  case AFreshness of
    ofFresh    : Result:= 'fresh';
    ofReindexed: Result:= 'reindexed';
    ofStale    : Result:= 'stale';
  else
    Result:= 'unverified';
  end; // case
end; // function

function StatusText(AStatus: TTargetStatus): string;
begin
  case AStatus of
    tsNoChange     : Result:= 'the name already conforms';
    tsUnresolved   : Result:= 'the symbol is not resolved in this index';
    tsStalePosition: Result:= 'the index holds the symbol at another position (stale index)';
  else
    Result:= 'every candidate name is taken';
  end; // case
end; // function

function ProjectReason(const AOwner: TRenameOwner; const AWhy: string): string;
begin
  Result:= 'project ' + AOwner.SectionName + ': ' + AWhy;
end; // function

{ True when AStatus, from an owner a PREVIEW left stale (ofStale, Ruling 12),
  is the staleness itself talking: the apply reindexes that owner and plans
  again, so the preview does not drop the target for it. }
function StaleTolerated(const AState: TOwnerState; AStatus: TTargetStatus): Boolean;
begin
  Result:= (AState.Report.Freshness = ofStale) and (AStatus in [tsStalePosition, tsUnresolved]);
end; // function

function FindTarget(const ATargets: TArray<TNamingTarget>; const AKey: string;
  out ATarget: TNamingTarget): Boolean;
var
  T: TNamingTarget;
begin
  for T in ATargets do
    if T.Key = AKey then
    begin
      ATarget:= T;
      Exit(True);
    end;
  ATarget:= Default(TNamingTarget);
  Result := False;
end; // function

{ Refreshes and opens every owner, in discovery order. A library owner is never
  opened; an owner RefreshOwner leaves unverified, or whose store cannot be
  opened, keeps Store = nil. }
function OpenOwners(const ADiscovery: TOwnerDiscovery; const AFindings: TArray<TLintFinding>;
  const ANaming: TNamingConfig; const AReindex: TFunc<string, string, Boolean>): TArray<TOwnerState>;
var
  I     : Integer;
  Reason: string ;
begin
  SetLength(Result, Length(ADiscovery.Owners));
  for I:= 0 to High(Result) do
  begin
    Result[I].Report.Owner:= ADiscovery.Owners[I];
    if ADiscovery.Owners[I].Kind = okLibrary then
    begin
      Result[I].Report.Freshness:= ofUnverified;
      Result[I].Report.Reason   := REASON_LIBRARY;
      Continue;
    end;
    Result[I].Report.Freshness:= RefreshOwner(ADiscovery.Owners[I], AReindex, Reason);
    Result[I].Report.Reason   := Reason;
    if Result[I].Report.Freshness = ofUnverified then Continue;
    try
      Result[I].Store  := TSQLiteSymbolStore.Create(ADiscovery.Owners[I].DbPath, True);
      Result[I].Targets:= BuildNamingTargets(Result[I].Store, AFindings, ANaming);
    except
      on E: Exception do
      begin
        Result[I].Store           := nil;
        Result[I].Targets         := nil;
        Result[I].Report.Freshness:= ofUnverified;
        Result[I].Report.Reason   := E.Message;
      end;
    end; // try
  end; // for
end; // function

{ Why no nsGlobal target may be renamed at all: every unknown DB (8c), library
  owner (8d) and unverified project (criterion 5), '; '-joined. '' when none. }
function BlockReason(const ADiscovery: TOwnerDiscovery; const AStates: TArray<TOwnerState>): string;
var
  Parts: TArray<string>;
  U    : string       ;
  S    : TOwnerState  ;
begin
  Parts:= nil;
  for S in AStates do
    if S.Report.Owner.Kind = okLibrary then
      Parts:= Parts + ['library ' + S.Report.Owner.SectionName + ': ' + REASON_LIBRARY]
    else if S.Store = nil then
      Parts:= Parts + [ProjectReason(S.Report.Owner, 'unverified -- ' + S.Report.Reason)];
  for U in ADiscovery.Unknown do Parts:= Parts + ['ownership unknown: ' + U];
  Result:= string.Join('; ', Parts);
end; // function

{ Why another declaration in AStore would capture ANewName after the rename:
  a symbol of that name at unit scope anywhere in the project, or at any scope
  in a file the rename edits. '' when there is none. ATarget itself (same
  qualified name: a pure re-casing) does not count. }
function ShadowReason(const AStore: ISymbolStore; const ATarget: TNamingTarget;
  const ANewName: string; const AEdits: TArray<TTextEdit>): string;
var
  FileIds: TList<Int64>;
  E      : TTextEdit   ;
  Sym    : TSymbol     ;
  Parent : TSymbol     ;
  Fid    : Int64       ;
  Scope  : string      ;
begin
  Result := '';
  FileIds:= TList<Int64>.Create;
  try
    for E in AEdits do
    begin
      Fid:= AStore.FindFileIdByPath(E.FilePath);
      if (Fid > 0) and not FileIds.Contains(Fid) then FileIds.Add(Fid);
    end;
    for Sym in AStore.FindSymbolsByExactName(ANewName) do
    begin
      if (not SameText(Sym.Name, ANewName)) or SameText(Sym.QualifiedName, ATarget.QName) then Continue;
      Parent:= if Sym.ParentId > 0 then AStore.GetSymbolById(Sym.ParentId) else Default(TSymbol);
      if FileIds.Contains(Sym.FileId) or (Parent.Id = 0) or (Parent.Kind in [skUnit, skProgram, skPackage]) then
      begin
        Scope := if EndsText('.' + Sym.Name, Sym.QualifiedName)
                 then Copy(Sym.QualifiedName, 1, Length(Sym.QualifiedName) - Length(Sym.Name) - 1)
                 else Sym.QualifiedName;
        Result:= Format('name %s already declared in %s', [ANewName, Scope]);
        Break;
      end;
    end; // for
  finally
    FileIds.Free;
  end; // try
end; // function

{ Why ACand cannot be used in one owner's store; '' when it can, with AEdits
  the store's edits for it. }
function CandidateWhy(const AState: TOwnerState; const ATarget: TNamingTarget;
  const ACand: string; out AEdits: TArray<TTextEdit>): string;
var
  Skipped: Integer;
  Why    : string ;
begin
  AEdits:= nil;
  if IndexStr(ACand, FreeCandidates(AState.Store, ATarget)) < 0 then
  begin
    Why:= TRenameRefactoring.ConflictReason(AState.Store, ATarget.QName, ACand);
    Exit(ProjectReason(AState.Report.Owner, if Why <> '' then Why else 'name ' + ACand + ' is not free'));
  end;
  AEdits:= BuildTargetEdits(AState.Store, ATarget, ACand, Skipped);
  { A preview's stale owner (ofStale) keeps the edits that could be placed:
    its plan is provisional, and the apply re-plans after reindexing it. }
  if AState.Report.Freshness <> ofStale then
  begin
    if Skipped > 0 then
      Exit(ProjectReason(AState.Report.Owner, Format('%d edit(s) at a position the index no longer matches (stale index)', [Skipped])));
    if Length(AEdits) = 0 then Exit(ProjectReason(AState.Report.Owner, 'no edit could be placed'));
  end;
  Result:= ShadowReason(AState.Store, ATarget, ACand, AEdits);
  if Result <> '' then Result:= ProjectReason(AState.Report.Owner, Result);
end; // function

function MergeEdits(const AParts: TArray<TArray<TTextEdit>>; const APreferredPath: string;
  out AMerged: TArray<TTextEdit>): string;
var
  Seen    : TDictionary<string, string>;
  Spelling: TDictionary<string, string>; { lower(path) -> the one spelling written }
  Part    : TArray<TTextEdit>          ;
  E       : TTextEdit                  ;
  Canon   : TTextEdit                  ;
  Path    : string                     ;
  K3      : string                     ;
  K5      : string                     ;
  Prev    : string                     ;
begin
  Result  := '';
  AMerged := nil;
  Seen    := TDictionary<string, string>.Create;
  Spelling:= TDictionary<string, string>.Create;
  try
    if APreferredPath <> '' then Spelling.Add(LowerCase(APreferredPath), APreferredPath);
    for Part in AParts do
      for E in Part do
      begin
        K3:= LowerCase(E.FilePath) + '|' + IntToStr(E.Line) + '|' + IntToStr(E.Col);
        K5:= K3 + '|' + IntToStr(E.EndCol) + '|' + E.Text;
        if not Seen.TryGetValue(K3, Prev) then
        begin
          Seen.Add(K3, K5);
          if not Spelling.TryGetValue(LowerCase(E.FilePath), Path) then
          begin
            Path:= E.FilePath;
            Spelling.Add(LowerCase(Path), Path);
          end;
          Canon         := E;
          Canon.FilePath:= Path;
          AMerged       := AMerged + [Canon];
        end
        else if Prev <> K5 then
        begin
          AMerged:= nil;
          Exit(Format('two projects edit %s line %d col %d differently', [E.FilePath, E.Line, E.Col]));
        end;
      end; // for
  finally
    Spelling.Free;
    Seen.Free;
  end; // try
end; // function

{ Tries ACand in every opened owner. '' when it is free in all of them, with
  AParts[I] the edits of owner I; otherwise the first owner's reason. An owner
  whose target is not tsReady (only a preview's tolerated stale owner reaches
  here so) contributes no edits and no veto. }
function TryCandidate(const AStates: TArray<TOwnerState>; const ATargets: TArray<TNamingTarget>;
  const ACand: string; out AParts: TArray<TArray<TTextEdit>>): string;
var
  I: Integer;
begin
  Result:= '';
  SetLength(AParts, Length(AStates));
  for I:= 0 to High(AStates) do
  begin
    if ATargets[I].Status <> tsReady then Continue;
    Result:= CandidateWhy(AStates[I], ATargets[I], ACand, AParts[I]);
    if Result <> '' then Break;
  end;
end; // function

{ Sets ARefs[I] to owner I's edits outside AFile (the shared unit itself). }
function OwnerReports(const AStates: TArray<TOwnerState>; const AParts: TArray<TArray<TTextEdit>>;
  const AFile: string): TArray<TOwnerReport>;
var
  I: Integer  ;
  E: TTextEdit;
begin
  SetLength(Result, Length(AStates));
  for I:= 0 to High(AStates) do
  begin
    Result[I]:= AStates[I].Report;
    if I <= High(AParts) then
      for E in AParts[I] do
        if not SameText(E.FilePath, AFile) then Inc(Result[I].RefCount);
  end;
end; // function

{ An nsGlobal target: one name free in EVERY owner, every owner's edits merged. }
function PlanGlobal(const AStates: TArray<TOwnerState>; const ABlock: string;
  const ABase: TNamingTarget): TTargetPlan;
var
  Ts      : TArray<TNamingTarget>          ;
  Parts   : TArray<TArray<TTextEdit>>      ;
  I       : Integer                        ;
  Cand    : string                         ;
  Why     : string                         ;
  FirstWhy: string                         ;
begin
  Result         := Default(TTargetPlan);
  Result.Target  := ABase;
  Result.Decision:= rdDropped;
  if Length(ABase.Candidates) > 0 then Result.NewName:= ABase.Candidates[0];
  Result.Owners:= OwnerReports(AStates, nil, '');
  Result.Reason:= ABlock;
  if ABlock <> '' then Exit;

  SetLength(Ts, Length(AStates));
  for I:= 0 to High(AStates) do
  begin
    if not FindTarget(AStates[I].Targets, ABase.Key, Ts[I]) then Ts[I].Status:= tsUnresolved;
    if (Ts[I].Status <> tsReady) and not StaleTolerated(AStates[I], Ts[I].Status) then
    begin
      Result.Reason:= ProjectReason(AStates[I].Report.Owner, StatusText(Ts[I].Status));
      Exit;
    end;
  end; // for

  FirstWhy:= '';
  for Cand in ABase.Candidates do
  begin
    Why:= TryCandidate(AStates, Ts, Cand, Parts);
    if Why = '' then Why:= MergeEdits(Parts, ABase.Finding.FilePath, Result.Edits);
    if Why = '' then
    begin
      Result.NewName := Cand;
      Result.Decision:= rdApply;
      Result.Reason  := '';
      Result.Owners  := OwnerReports(AStates, Parts, ABase.Finding.FilePath);
      Exit;
    end;
    if FirstWhy = '' then FirstWhy:= Why;
  end; // for
  Result.Reason:= if FirstWhy <> '' then FirstWhy else StatusText(tsAllCandidatesTaken);
end; // function

{ An nsLocal target: routine-local, so no other project can reference it --
  built ONCE, from the first opened owner that resolved it. }
function PlanLocal(const AStates: TArray<TOwnerState>; const ABase: TNamingTarget): TTargetPlan;
var
  I          : Integer       ;
  T          : TNamingTarget ;
  FreeNames  : TArray<string>;
  Skipped    : Integer       ;
  Provisional: Boolean       ;
begin
  Result         := Default(TTargetPlan);
  Result.Target  := ABase;
  Result.Decision:= rdDropped;
  if Length(ABase.Candidates) > 0 then Result.NewName:= ABase.Candidates[0];
  Result.Owners:= OwnerReports(AStates, nil, '');
  Result.Reason:= 'no owning index could be opened';
  for I:= 0 to High(AStates) do
    if (AStates[I].Store <> nil) and FindTarget(AStates[I].Targets, ABase.Key, T) then
    begin
      { A preview's stale owner (ofStale): its stale results do not drop the
        target -- the plan is provisional and the apply re-plans (Ruling 12). }
      Provisional:= AStates[I].Report.Freshness = ofStale;
      FreeNames  := FreeCandidates(AStates[I].Store, T);
      if StaleTolerated(AStates[I], T.Status) then
      begin
        Result.Decision:= rdApply;
        Result.Reason  := '';
        Result.Owners  := [AStates[I].Report];
      end
      else if T.Status <> tsReady then Result.Reason:= ProjectReason(AStates[I].Report.Owner, StatusText(T.Status))
      else if Length(FreeNames) = 0 then Result.Reason:= ProjectReason(AStates[I].Report.Owner, StatusText(tsAllCandidatesTaken))
      else
      begin
        Result.NewName:= FreeNames[0];
        Result.Edits  := BuildTargetEdits(AStates[I].Store, T, FreeNames[0], Skipped);
        if ((Skipped > 0) or (Length(Result.Edits) = 0)) and not Provisional then
        begin
          Result.Edits := nil;
          Result.Reason:= ProjectReason(AStates[I].Report.Owner, 'no edit could be placed (stale index)');
        end
        else
        begin
          Result.Decision:= rdApply;
          Result.Reason  := '';
          Result.Owners  := [AStates[I].Report];
        end;
      end;
      Break;
    end; // if
end; // function

{ TNamingTarget.Key's spelling for a finding (BuildNamingTargets builds the same). }
function FindingKey(const AFinding: TLintFinding): string;
begin
  Result:= LowerCase(AFinding.FilePath) + '|' + IntToStr(AFinding.StartLine) + '|'
    + IntToStr(AFinding.StartCol) + '|' + LowerCase(AFinding.RuleId);
end; // function

{ The identifier at a finding's span as it is on disk; '' when unreadable. }
function IdentifierAt(const AFinding: TLintFinding): string;
var
  Lines: TArray<string>;
begin
  Result:= '';
  try
    Lines:= TFile.ReadAllLines(AFinding.FilePath, TEncoding.ANSI);
    if (AFinding.StartLine >= 1) and (AFinding.StartLine <= Length(Lines)) and (AFinding.EndCol > AFinding.StartCol) then
      Result:= Copy(Lines[AFinding.StartLine - 1], AFinding.StartCol, AFinding.EndCol - AFinding.StartCol);
  except
    on E: Exception do Result:= '';  { unreadable: the plan still says why it was dropped }
  end; // try
end; // function

{ A dropped plan for a finding no usable owner store built a target for. }
function UnplannedTarget(const AStates: TArray<TOwnerState>; const AFinding: TLintFinding;
  const AReason: string): TTargetPlan;
begin
  Result                := Default(TTargetPlan);
  Result.Target.Key     := FindingKey(AFinding);
  Result.Target.Finding := AFinding;
  Result.Target.OldName := IdentifierAt(AFinding);
  Result.Target.Status  := tsUnresolved;
  Result.Decision       := rdDropped;
  Result.Reason         := AReason;
  Result.Owners         := OwnerReports(AStates, nil, '');
end; // function

{ True when ALine holds AEdit.ExpectText at [Col, EndCol), case-insensitively. }
function SpanHolds(const ALine: string; const AEdit: TTextEdit): Boolean;
var
  WidthOk: Boolean;
begin
  WidthOk:= (AEdit.Col >= 1) and (AEdit.EndCol - AEdit.Col = Length(AEdit.ExpectText));
  Result := WidthOk and (AEdit.EndCol - 1 <= Length(ALine))
    and SameText(Copy(ALine, AEdit.Col, AEdit.EndCol - AEdit.Col), AEdit.ExpectText);
end; // function

function FindStaleEdit(const AEdits: TArray<TTextEdit>; out AStale: TTextEdit): Boolean;
var
  Cache: TDictionary<string, TArray<string>>;
  E    : TTextEdit                          ;
  Lines: TArray<string>                     ;
  Key  : string                             ;
  Ok   : Boolean                            ;
begin
  Result:= False;
  AStale:= Default(TTextEdit);
  Cache := TDictionary<string, TArray<string>>.Create;
  try
    for E in AEdits do
    begin
      if (E.Kind <> tekReplaceInLine) or (E.ExpectText = '') then Continue;
      Key:= LowerCase(E.FilePath);
      if not Cache.TryGetValue(Key, Lines) then
      begin
        Lines:= nil;
        if TFile.Exists(E.FilePath) then Lines:= TFile.ReadAllLines(E.FilePath, TEncoding.ANSI);
        Cache.Add(Key, Lines);
      end;
      { TTextEditApplier's ReplaceEditIsValid rule: the span [Col, EndCol) on
        Line holds ExpectText, compared case-insensitively. }
      Ok:= (E.Line >= 1) and (E.Line <= Length(Lines)) and SpanHolds(Lines[E.Line - 1], E);
      if not Ok then
      begin
        AStale:= E;
        Exit(True);
      end;
    end; // for
  finally
    Cache.Free;
  end; // try
end; // function

function GuardPlansAtWrite(var APlans: TArray<TTargetPlan>; AAllOrNothing: Boolean;
  out AEdits: TArray<TTextEdit>; out ANotes: TArray<string>): Integer;
var
  I    : Integer         ;
  Bad  : TTextEdit       ;
  Kept : TList<TTextEdit>;
  Notes: TList<string>   ;
begin
  Result:= 0;
  Kept  := TList<TTextEdit>.Create;
  Notes := TList<string>.Create;
  try
    for I:= 0 to High(APlans) do
    begin
      if APlans[I].Decision <> rdApply then Continue;
      if not FindStaleEdit(APlans[I].Edits, Bad) then
      begin
        Kept.AddRange(APlans[I].Edits);
        Continue;
      end;
      Notes.Add(Format('%s -> %s %s:%d (stale)', [APlans[I].Target.OldName, APlans[I].NewName, Bad.FilePath, Bad.Line]));
      APlans[I].Decision:= rdDropped;
      APlans[I].Reason  := Format('%s:%d changed on disk after the rename was planned (stale)', [Bad.FilePath, Bad.Line]);
      APlans[I].Edits   := nil;
      Inc(Result);
    end; // for
    { T5 / criterion 9: a single fix is all-or-nothing per RUN, not per target. }
    if AAllOrNothing and (Result > 0) then
    begin
      for I:= 0 to High(APlans) do
        if APlans[I].Decision = rdApply then
        begin
          APlans[I].Decision:= rdDropped;
          APlans[I].Reason  := 'not written: another rename of this fix changed on disk after it was planned (all-or-nothing)';
          APlans[I].Edits   := nil;
          Inc(Result);
        end;
      Kept.Clear;
    end;
    AEdits:= Kept.ToArray;
    ANotes:= Notes.ToArray;
  finally
    Notes.Free;
    Kept.Free;
  end; // try
end; // function

function PlanMultiProjectRename(const ADiscovery: TOwnerDiscovery;
  const AFindings: TArray<TLintFinding>; const ANaming: TNamingConfig;
  const AReindex: TFunc<string, string, Boolean>): TMultiRenamePlan;
var
  States: TArray<TOwnerState>;
  Seen  : TList<string>      ;
  Block : string             ;
  S     : TOwnerState        ;
  T     : TNamingTarget      ;
  F     : TLintFinding       ;
  I     : Integer            ;
begin
  Result          := Default(TMultiRenamePlan);
  Result.Discovery:= ADiscovery;
  States:= OpenOwners(ADiscovery, AFindings, ANaming, AReindex);
  Seen  := TList<string>.Create;
  try
    SetLength(Result.Owners, Length(States));
    for I:= 0 to High(States) do Result.Owners[I]:= States[I].Report;
    Block:= BlockReason(ADiscovery, States);
    for S in States do
      for T in S.Targets do
      begin
        if Seen.Contains(T.Key) then Continue;
        Seen.Add(T.Key);
        if T.Scope = nsLocal then Result.Targets:= Result.Targets + [PlanLocal(States, T)]
        else Result.Targets:= Result.Targets + [PlanGlobal(States, Block, T)];
      end; // for
    { A finding no usable store built a target for -- no owner opened at all,
      or every one unverified -- is still PLANNED, as dropped: it must reach
      the refusal / `dropped` line, never vanish (fix round 1, I2). }
    for F in AFindings do
      if not Seen.Contains(FindingKey(F)) then
      begin
        Seen.Add(FindingKey(F));
        Result.Targets:= Result.Targets + [UnplannedTarget(States, F,
          if Block <> '' then Block else 'no owning index could resolve the finding')];
      end;
  finally
    Seen.Free;
    for I:= 0 to High(States) do States[I].Store:= nil;
  end; // try
end; // function

end.
