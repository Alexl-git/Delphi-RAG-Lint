unit DRagLint.Index.DbSelect;

/// <summary>Manifest-driven DB list selection for consumers (query, lsp, serve).
/// Resolves the ordered set of SQLite DBs a consumer should open when the
/// user passes no explicit --db flags.</summary>
/// <remarks>
/// Selection order: all non-library section DBs first (in manifest order),
/// then EVERY library section DB whose Platform matches APlatform, in manifest
/// order (152b DBS / O4; before, only the first library section was kept).
/// Only paths that exist on disk are included (ARequireExists=True, the
/// production default).  Pass ARequireExists=False in selftests so library
/// DB paths can be asserted even when the library index has not been built.
/// All .pas source: strict 7-bit ASCII, CRLF line endings, no BOM.
/// </remarks>

interface

uses
  System.SysUtils
  , System.IOUtils
  , DRagLint.Index  .Manifest
  , DRagLint.Index  .Plan
  , DRagLint.Project.Resolver
  ;

type
  /// <summary>Resolves the ordered DB list a consumer should open when
  /// no --db flags are given.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.CLI.DoCycles.OpenPlanLibrary (DRagLint.CLI.pas), DRagLint.CLI.DoResolveDbsList (DRagLint.CLI.pas), DRagLint.CLI.DoSelfTestDbSelect (DRagLint.CLI.pas), DRagLint.CLI.DoUnwith (DRagLint.CLI.pas), DRagLint.CLI.ResolveConsumerDbs (DRagLint.CLI.pas) (+2 more)</para>
  /// <para>Used in units: DRagLint.CLI</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TDbSelect = class
    public
      /// <summary>Ordered DB list a consumer should open when no --db is given:
      /// every NON-library section's DbPath, followed by EVERY library section
      /// DB matching APlatform, in manifest order. Only paths that EXIST on
      /// disk are returned (when ARequireExists=True). Project DBs first,
      /// library DBs last (cross-DB resolution order).</summary>
      /// <param name="AManifest">Parsed manifest supplying section info and settings.</param>
      /// <param name="APlatform">Platform token used to pick the library-{platform} DB
      /// (e.g. 'Win32', 'Win64'). Empty string matches no library section.</param>
      /// <param name="AResolver">Project resolver for platform enumeration;
      /// caller owns the lifetime.</param>
      /// <param name="ARequireExists">When True (default), only existing files are
      /// returned. Pass False in selftests to assert resolved paths without
      /// requiring the DB files to be built.</param>
      /// <returns>Ordered array of absolute DB paths: non-library sections first,
      /// then the platform's library sections in manifest order. A library path
      /// named by two sections appears once.</returns>
      /// <remarks>
      /// <para>The library half agrees with the CLI's ResolveLibraryDbs (same
      /// plan, same platform filter, same order). A consumer that needs ONE
      /// library takes the first library section; a consumer that opens a store
      /// list reads them all, and first-wins on a duplicate qualified name keeps
      /// the earlier section's symbol.</para>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.CLI.DoCycles.OpenPlanLibrary (DRagLint.CLI.pas), DRagLint.CLI.DoResolveDbsList (DRagLint.CLI.pas), DRagLint.CLI.DoSelfTestDbSelect (DRagLint.CLI.pas), DRagLint.CLI.DoUnwith (DRagLint.CLI.pas), DRagLint.CLI.ResolveConsumerDbs (DRagLint.CLI.pas) (+2 more)</para>
      /// <para>Calls: DRagLint.Index.DbSelect.TDbSelect.Resolve.Append, DRagLint.Index.Plan.ResolvePlan, SameText</para>
      /// <para>Returns: OutList</para>
      /// <para>Directives: static</para>
      /// <seealso cref="DRagLint.Index.DbSelect.TDbSelect.Resolve.Append"/>
      /// <seealso cref="DRagLint.Index.Plan.ResolvePlan"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function Resolve(const AManifest: TIndexManifest; const APlatform: string; AResolver: TProjectResolver; ARequireExists: Boolean = True): TArray<string>; static;
  end;

implementation

class function TDbSelect.Resolve(const AManifest: TIndexManifest; const APlatform: string; AResolver: TProjectResolver; ARequireExists: Boolean): TArray<string>;
var
  PlatFilter: TArray<string>;
  Plan      : TIndexPlan    ;
  PS        : TPlanSection  ;
  LibDbPaths: TArray<string>;
  OutList   : TArray<string>;

  procedure Append(const APath: string);
  begin
    if APath = '' then Exit;
    if ARequireExists and not TFile.Exists(APath) then Exit;
    SetLength(OutList, Length(OutList) + 1);
    OutList[High(OutList)]:= APath;
  end;

begin
  OutList:= nil;
  LibDbPaths:= nil;

  // Resolve the full plan, restricting library expansion to APlatform only
  // (so we get the library DBs of APlatform, not those of every platform).
  if APlatform <> '' then PlatFilter:= [APlatform]
  else PlatFilter:= nil;

  Plan:= ResolvePlan(AManifest, PlatFilter, AResolver);

  // Collect non-library sections first (manifest order), then library.
  for PS in Plan.Items do
  begin
    if PS.Mode <> smLibrary then Append(PS.DbPath)
    else
    begin
      // Library section expanded for APlatform -- collected for the tail:
      // every section in manifest order (152b DBS / O4), each path once.
      if SameText(PS.Platform, APlatform) and (PS.DbPath <> '') then
      begin
        var Dup:= False;
        for var Seen: string in LibDbPaths do
          if SameText(Seen, PS.DbPath) then Dup:= True;
        if not Dup then LibDbPaths:= LibDbPaths + [PS.DbPath];
      end;
    end;
  end;

  // Append the library DBs last.
  for var LibDbPath: string in LibDbPaths do Append(LibDbPath);

  Result:= OutList;
end; // begin

end.
