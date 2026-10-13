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
  DRagLint.Index.Manifest
  ;

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
  /// <para>Used by: declaration (DRagLint.Refactor.MultiProjectRename.pas), DRagLint.Refactor.MultiProjectRename.FindRenameOwners (DRagLint.Refactor.MultiProjectRename.pas), DRagLint.Refactor.MultiProjectRename.OwnerOf (DRagLint.Refactor.MultiProjectRename.pas)</para>
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
  /// <para>Used by: declaration (DRagLint.Refactor.MultiProjectRename.pas), DRagLint.Refactor.MultiProjectRename.FindRenameOwners (DRagLint.Refactor.MultiProjectRename.pas)</para>
  /// <para>Used in units: DRagLint.Refactor.MultiProjectRename</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TOwnerDiscovery = record
    /// <summary>How many DISTINCT databases were asked (criterion 8e's "of N").</summary>
    Probed: Integer;
    /// <summary>Every index that holds the file, preferred DB first, then plan
    /// order. Library owners included, Kind = okLibrary.</summary>
    Owners: TArray<TRenameOwner>;
    /// <summary>'dbpath: reason' for each index that could not be read
    /// (criterion 8c) -- ownership unknown, never "not an owner".</summary>
    Unknown: TArray<string>;
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
/// <returns>Probed = number of distinct DB paths asked (duplicates folded
/// case-insensitively); Owners = every dmMember DB, preferred first, then plan
/// order; Unknown = 'dbpath: reason' for every dmUnknown DB.</returns>
/// <remarks>
/// Raises nothing of its own: an unreadable DB lands in Unknown, not
/// in an exception. A library owner is returned rather than refused here so
/// the caller can name the library in its refusal (criterion 8d).
/// Reads the registry (library path expansion, via ResolvePlan) and opens each
/// DB read-only, closing it before the next. Not thread-safe only in so far as
/// ResolvePlan is not; touches no shared state of its own.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Calls: Default, DRagLint.Index.Plan.ResolvePlan, DRagLint.Project.Resolver.TProjectResolver.Create, DRagLint.Refactor.MultiProjectRename.DbKey, DRagLint.Refactor.MultiProjectRename.OwnerOf, DRagLint.Storage.FileMembership.DbMembership, SameText</para>
/// <para>Returns: Default(TOwnerDiscovery)</para>
/// <para>Complexity: 13 (cyclomatic, outer body), 59 lines (full implementation)</para>
/// <seealso cref="DRagLint.Index.Plan.ResolvePlan"/>
/// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.Create"/>
/// <seealso cref="DRagLint.Refactor.MultiProjectRename.DbKey"/>
/// <seealso cref="DRagLint.Refactor.MultiProjectRename.OwnerOf"/>
/// <seealso cref="DRagLint.Storage.FileMembership.DbMembership"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function FindRenameOwners(const AManifest: TIndexManifest; const APlatform, AFilePath,
  APreferredDb: string): TOwnerDiscovery;

implementation

uses
  System.SysUtils
  , System.Generics.Collections
  , DRagLint.Index.Plan
  , DRagLint.Project.Resolver
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
  try
    for Item in Plan.Items do
    begin
      if (Item.Platform <> '') and (APlatform <> '') and not SameText(Item.Platform, APlatform) then Continue;
      Key:= DbKey(Item.DbPath);
      if (Key = '') or Seen.Contains(Key) then Continue;
      Seen.Add(Key);
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

    Result.Probed := Seen.Count;
    Result.Owners := Owners.ToArray;
    Result.Unknown:= Unknown.ToArray;
  finally
    Unknown.Free;
    Owners .Free;
    Seen   .Free;
  end; // try
end; // function

end.
