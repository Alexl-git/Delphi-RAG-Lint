unit DRagLint.Index.Plan;

/// <summary>Resolves a TIndexManifest into a concrete TPlanSection list,
/// performing mode classification, {platform} expansion, absolute-path
/// resolution and cross-section deduplication root assignment.</summary>
/// <remarks>All .pas source: strict 7-bit ASCII, CRLF line endings, no BOM.</remarks>

interface

uses
  System.SysUtils
  , System.IOUtils
  , System.Classes
  , System  .Generics.Collections
  , DRagLint.Core    .Interfaces
  , DRagLint.Index   .Manifest
  , DRagLint.Project .Resolver
  ;

type
  /// <summary>How a manifest section's file set is gathered.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Index.Plan.pas), DRagLint.Index.Plan.ResolvePlan (DRagLint.Index.Plan.pas)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TPlanSectionMode = (
    /// <summary>All files under the listed include folders (recursive walk).</summary>
    smFolderTree,
    /// <summary>Closure of a .dpr / .dproj file (transitively used units).</summary>
    smClosure,
    /// <summary>Delphi registry Library + Browsing paths for one platform.</summary>
    smLibrary);

  /// <summary>Concrete resolved build plan for one index section (or one platform
  /// expansion of a library section).</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.CLI.PlanToJson (DRagLint.CLI.pas), DRagLint.CLI.DoSelfTestRecreate (DRagLint.CLI.pas), DRagLint.CLI.DoLibraryDrift (DRagLint.CLI.pas), DRagLint.Index.Coverage.ComputeCoverage (DRagLint.Index.Coverage.pas), DRagLint.Index.DbSelect.TDbSelect.Resolve (DRagLint.Index.DbSelect.pas) (+3 more)</para>
  /// <para>Used in units: DRagLint.CLI, DRagLint.Index.Coverage, DRagLint.Index.DbSelect, DRagLint.Index.Plan</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TPlanSection = record
    /// <summary>Section name from the manifest (same for all platform expansions).</summary>
    Name: string;
    /// <summary>How files are gathered for this section.</summary>
    Mode: TPlanSectionMode;
    /// <summary>Absolute path to the output SQLite database ({platform} already expanded).</summary>
    DbPath: string;
    /// <summary>Platform token for library sections; empty for folder/closure sections.</summary>
    Platform: string;
    /// <summary>Resolved roots: absolute folder paths (smFolderTree/smLibrary) or
    /// absolute .dpr/.dproj paths (smClosure). Library roots may be numerous.</summary>
    Roots: TArray<string>;
    /// <summary>Union of other sections' resolved roots that this section treats as
    /// already-indexed and should exclude from its walk (cross-index dedup).</summary>
    DedupExcludeRoots: TArray<string>;
    /// <summary>Walk filter derived from global + per-section settings.</summary>
    Filter: TWalkFilter;
  end; // record

  /// <summary>Complete concrete build plan resolved from a TIndexManifest.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.CLI.DoIndexAll (DRagLint.CLI.pas), DRagLint.CLI.DoScanAll (DRagLint.CLI.pas), DRagLint.CLI.MakeSiblingStoreResolver (DRagLint.CLI.pas), DRagLint.CLI.DoLibraryDrift (DRagLint.CLI.pas), DRagLint.Index.Coverage.ComputeCoverage (DRagLint.Index.Coverage.pas) (+3 more)</para>
  /// <para>Used in units: DRagLint.CLI, DRagLint.Index.Coverage, DRagLint.Index.DbSelect, DRagLint.Index.Plan</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TIndexPlan = record
    /// <summary>Ordered list of resolved plan sections (library sections are
    /// expanded one entry per platform).</summary>
    Items: TArray<TPlanSection>;
  end;

/// <summary>Resolve a manifest into a concrete build plan. APlatformsFilter nil
/// = all platforms a library section requests; non-nil restricts library
/// expansion to the intersection with APlatformsFilter. AResolver supplies
/// registry platform enumeration and per-platform library path reads.</summary>
/// <param name="AManifest">Parsed, validated manifest. Must have RootDir set.</param>
/// <param name="APlatformsFilter">Optional whitelist of platform names. Pass nil
/// to accept all platforms the section declares. Caller owns the array lifetime.</param>
/// <param name="AResolver">Resolver instance; caller owns + must not free until
/// after this function returns. Must not be nil.</param>
/// <returns>Fully populated TIndexPlan.</returns>
/// <remarks>
/// Mode classification:
/// Source='registry-libraries' -> smLibrary (one TPlanSection per platform).
/// Any Include entry ending with .dpr/.dproj (case-insensitive) -> smClosure.
/// Otherwise -> smFolderTree.
/// DedupAgainst='*' -> union of ALL other sections' roots.
/// Not thread-safe; call from a single thread.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.DoIndexAll (DRagLint.CLI.pas), DRagLint.CLI.DoLibraryDrift (DRagLint.CLI.pas), DRagLint.CLI.DoScanAll (DRagLint.CLI.pas), DRagLint.CLI.MakeSiblingStoreResolver (DRagLint.CLI.pas), DRagLint.Index.Coverage.ComputeCoverage (DRagLint.Index.Coverage.pas) (+1 more)</para>
/// <para>Calls: Default, DRagLint.Index.Manifest.ExpandSectionDb, DRagLint.Index.Manifest.TIndexManifest.FindSection, DRagLint.Index.Plan.BuildFilter, DRagLint.Index.Plan.ClassifyMode, DRagLint.Index.Plan.CollectRootsByName, DRagLint.Index.Plan.CollectRootsExcept, DRagLint.Index.Plan.ExpandDbPath, DRagLint.Index.Plan.PlatformAllowed, DRagLint.Index.Plan.ResolveRoots, DRagLint.Project.Resolver.TProjectResolver.EnumRegistryPlatforms, DRagLint.Project.Resolver.TProjectResolver.ReadPlatformLibraryPaths</para>
/// <para>Returns: Default(TIndexPlan)</para>
/// <para>Complexity: 13 (cyclomatic, outer body), 126 lines (full implementation)</para>
/// <para>Touches: file system</para>
/// <seealso cref="DRagLint.Index.Manifest.ExpandSectionDb"/>
/// <seealso cref="DRagLint.Index.Manifest.TIndexManifest.FindSection"/>
/// <seealso cref="DRagLint.Index.Plan.BuildFilter"/>
/// <seealso cref="DRagLint.Index.Plan.ClassifyMode"/>
/// <seealso cref="DRagLint.Index.Plan.CollectRootsByName"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ResolvePlan(const AManifest: TIndexManifest; const APlatformsFilter: TArray<string>; AResolver: TProjectResolver): TIndexPlan;

implementation

{ ---------------------------------------------------------------------- }
{  Internal helpers                                                        }
{ ---------------------------------------------------------------------- }

function PlanModeStr(const AMode: TPlanSectionMode): string;
begin
  case AMode of
    smFolderTree: Result:= 'folderTree';
    smClosure   : Result:= 'closure';
    smLibrary   : Result:= 'library';
    else Result:= 'folderTree';
  end;
end;

// Expand {platform} token in ATemplate, then make absolute under ABase.
function ExpandDbPath(const ATemplate, APlatform, ABase, AOutDir: string): string;
var
  S: string;
begin
  S:= ATemplate;
  S:= StringReplace(S, '{platform}', APlatform, [rfReplaceAll, rfIgnoreCase]);
  // Bare filename -> place under OutDir (which is itself relative to ABase)
  if not TPath.IsPathRooted(S) then
  begin
    // If AOutDir is non-empty, combine with it; else directly with ABase
    if AOutDir <> '' then
    begin
      if TPath.IsPathRooted(AOutDir) then S:= TPath.Combine(AOutDir, S)
      else S:= TPath.Combine(TPath.Combine(ABase, AOutDir), S);
    end
    else S:= TPath.Combine(ABase, S);
  end;
  try
    S:= TPath.GetFullPath(S);
  except
    // leave as-is if GetFullPath fails (bad path chars)
  end;
  Result:= S;
end; // function

// Determine mode by scanning Include list for .dpr/.dproj entries.
// If any entry ends with .dpr or .dproj -> smClosure; else smFolderTree.
function ClassifyMode(const ASection: TIndexSection): TPlanSectionMode;
var
  Inc: string;
  Ext: string;
begin
  if SameText(ASection.Source, 'registry-libraries') then Exit(smLibrary);
  for Inc in ASection.Include do
  begin
    Ext:= LowerCase(TPath.GetExtension(Inc));
    if (Ext = '.dpr') or (Ext = '.dproj') then Exit(smClosure);
  end;
  Result:= smFolderTree;
end;

// Resolve include entries to absolute paths against ARootDir.
// All entries are returned regardless of mode; the caller (BuildPlanItem)
// decides how to consume them (closure walk vs folder walk).
function ResolveRoots(const ASection: TIndexSection; const ARootDir: string; AMode: TPlanSectionMode): TArray<string>;
var
  List: TList<string>;
  Inc : string       ;
  Abs : string       ;
begin
  List:= TList<string>.Create;
  try
    for Inc in ASection.Include do
    begin
      if TPath.IsPathRooted(Inc) then Abs:= Inc
      else Abs:= TPath.Combine(ARootDir, Inc);
      try
        Abs:= TPath.GetFullPath(Abs);
      except
        // keep as-is
      end;
      // All include entries are added regardless of mode; smClosure vs smFolderTree
      // distinction is handled in BuildPlanItem (closure walk vs folder walk).
      List.Add(Abs);
    end;
    Result:= List.ToArray;
  finally
    List.Free;
  end; // try
end; // function

// Build the TWalkFilter for a section, applying global + section settings.
function BuildFilter(const AManifest: TIndexManifest; const ASection: TIndexSection): TWalkFilter;
var
  KB: Integer;
begin
  Result:= TWalkFilter.Create;
  Result.GlobalExclude := AManifest.GlobalExclude;
  Result.SectionExclude:= ASection .Exclude;
  Result.IncludeOnly   := ASection .IncludeOnly;
  Result.UseIgnoreFiles:= ASection .UseIgnoreFiles;
  Result.SqlOnlyMS     := ASection .SqlOnlyMS;
  { Propagate the file-size guard from manifest settings.
    0 in settings means "not set" -> fall back to the TWalkFilter.Create
    default of 2048. A negative value is treated as unlimited (0 in the
    filter). }
  KB:= AManifest.Settings.MaxParseFileKB;
  if KB = 0 then KB:= 2048; // default when manifest omits the key
  if KB < 0 then KB:= 0; // negative = unlimited
  Result.MaxFileKB:= KB;
end;

// Append unique strings from ASrc into ADest (case-insensitive dedup).
procedure AppendUnique(var ADest: TArray<string>; const ASrc: TArray<string>);
var
  S    : string ;
  E    : string ;
  Found: Boolean;
begin
  for S in ASrc do
  begin
    Found:= False;
    for E in ADest do
      if SameText(E, S) then
      begin
        Found:= True;
        Break;
      end;
    if not Found then
    begin
      SetLength(ADest, Length(ADest) + 1);
      ADest[High(ADest)]:= S;
    end;
  end;
end; // procedure

// Union of all Roots from all plan items whose Name matches AName (case-insens).
procedure CollectRootsByName(const AItems: TArray<TPlanSection>; const AName: string; var ADest: TArray<string>);
var
  Item: TPlanSection;
begin
  for Item in AItems do
    if SameText(Item.Name, AName) then AppendUnique(ADest, Item.Roots);
end;

// Union of all Roots from every plan item EXCEPT those named AExcludeName.
procedure CollectRootsExcept(const AItems: TArray<TPlanSection>; const AExcludeName: string; var ADest: TArray<string>);
var
  Item: TPlanSection;
begin
  for Item in AItems do
    if not SameText(Item.Name, AExcludeName) then AppendUnique(ADest, Item.Roots);
end;

// Check if APlatform is in AFilter (case-insensitive). Empty filter = all pass.
function PlatformAllowed(const APlatform: string; const AFilter: TArray<string>): Boolean;
var
  F: string;
begin
  if Length(AFilter) = 0 then Exit(True);
  for F in AFilter do
    if SameText(F, APlatform) then Exit(True);
  Result:= False;
end;

{ ---------------------------------------------------------------------- }
{  ResolvePlan                                                             }
{ ---------------------------------------------------------------------- }

function ResolvePlan(const AManifest: TIndexManifest; const APlatformsFilter: TArray<string>; AResolver: TProjectResolver): TIndexPlan;
var
  Sec         : TIndexSection      ;
  Mode        : TPlanSectionMode   ;
  Items       : TList<TPlanSection>;
  PS          : TPlanSection       ;
  OutDir      : string             ;
  DbTemplate  : string             ;
  DbPath      : string             ;
  RegPlatforms: TArray<string>     ;
  SecPlatforms: TArray<string>     ;
  LibRoots    : TArray<string>     ;
  Plat        : string             ;
  I           : Integer            ;
  DA          : string             ;
  DedupRoots  : TArray<string>     ;
begin
  Result:= Default(TIndexPlan);
  Items:= TList<TPlanSection>.Create;
  try
    // Resolve OutDir against RootDir
    OutDir:= AManifest.OutDir;
    if (OutDir <> '') and (not TPath.IsPathRooted(OutDir)) then OutDir:= TPath.Combine(AManifest.RootDir, OutDir);
    if OutDir = '' then OutDir:= AManifest.RootDir;
    try
      OutDir:= TPath.GetFullPath(OutDir);
    except
      // keep as-is
    end;

    // --- Pass 1: resolve each section into plan item(s) (no dedup yet) ---
    for Sec in AManifest.Sections do
    begin
      Mode:= ClassifyMode(Sec);

      if Mode = smLibrary then
      begin
        // Platform expansion: determine which platforms to emit
        if (Length(Sec.Platforms) = 1) and (Sec.Platforms[0] = '*') then RegPlatforms:= AResolver.EnumRegistryPlatforms
        else RegPlatforms:= Sec.Platforms;

        // Apply filter if provided
        if Length(APlatformsFilter) > 0 then
        begin
          SecPlatforms:= nil;
          for Plat in RegPlatforms do
            if PlatformAllowed(Plat, APlatformsFilter) then
            begin
              SetLength(SecPlatforms, Length(SecPlatforms) + 1);
              SecPlatforms[High(SecPlatforms)]:= Plat;
            end;
        end
        else SecPlatforms:= RegPlatforms;

        // Determine DB template: default to '<Name>-{platform}.sqlite'
        DbTemplate:= Sec.Db;
        if DbTemplate = '' then DbTemplate:= Sec.Name + '-{platform}.sqlite';

        // Emit one plan section per platform
        for Plat in SecPlatforms do
        begin
          PS:= Default(TPlanSection);
          PS.Name:= Sec.Name;
          PS.Mode    := smLibrary;
          PS.Platform:= Plat;
          PS.DbPath:= ExpandDbPath(DbTemplate, Plat, AManifest.RootDir, AManifest.OutDir);
          LibRoots:= AResolver.ReadPlatformLibraryPaths(Plat);
          PS.Roots:= LibRoots;
          PS.Filter:= BuildFilter(AManifest, Sec);
          // DedupExcludeRoots: computed in pass 2
          Items.Add(PS);
        end;
      end // if
      else
      begin
        // smFolderTree or smClosure
        PS:= Default(TPlanSection);
        PS.Name:= Sec.Name;
        PS.Mode    := Mode;
        PS.Platform:= '';

        { NOT ExpandDbPath here (that is the smLibrary path, above): a project
          section with no explicit "db" is anchored to ITS OWN project file, not
          to <OutDir>\<Name>.sqlite -- ExpandSectionDb is the one function that
          knows that (project -> _D-RAG home; folder scan -> the OutDir
          default), and migrate-dbs's manifest rewrite depends on this function
          agreeing with it, or a post-migration `index --all` would recreate a
          second, stale database at the old OutDir location. }
        PS.DbPath:= ExpandSectionDb(AManifest, Sec);
        PS.Roots:= ResolveRoots(Sec, AManifest.RootDir, Mode);
        PS.Filter:= BuildFilter(AManifest, Sec);
        Items.Add(PS);
      end;
    end; // for

    // --- Pass 2: compute DedupExcludeRoots for each item ---
    // We need a snapshot of all roots per name at this point.
    for I:= 0 to Items.Count - 1 do
    begin
      PS:= Items[I];
      DedupRoots:= nil;

      // Find the matching manifest section's DedupAgainst list
      var MatchSec: TIndexSection;
      if not AManifest.FindSection(PS.Name, MatchSec) then
      begin
        Items[I]:= PS;
        Continue;
      end;

      for DA in MatchSec.DedupAgainst do
      begin
        if DA = '*' then
          // All sections except this one
          CollectRootsExcept(Items.ToArray, PS.Name, DedupRoots)
        else CollectRootsByName(Items.ToArray, DA, DedupRoots);
      end;

      PS.DedupExcludeRoots:= DedupRoots;
      Items[I]:= PS;
    end; // for

    Result.Items:= Items.ToArray;
  finally
    Items.Free;
  end; // try
end; // function

end.
