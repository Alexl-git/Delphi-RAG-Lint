unit DRagLint.Project.TargetStudio;

{ WHICH STUDIO'S LIBRARY PATH A PROJECT IS READ AGAINST (GH #13, Jonathas Paiva's
  report). Since 1.39 the index preprocesses for the Delphi the .dproj targets, but
  the library path, platform list, IDE Environment Variables and $(BDS) stayed on
  37.0, so a 10.3 project lost every unit only 10.3's path names: 61 of them on the
  measured project, with fewer callers and no warning.

  ONE MAPPING. BdsKeyOfCompilerVersion inverts CompilerVersionOfStudioRoot by
  asking it, so the BDS offset stays in Preprocess.Profile alone.

  THE TAIL. Reading the right key is not enough: the closure once used library paths
  only to EXCLUDE, so a unit on a path and on no project search path stayed unreachable
  under any key. TClosureResolver.SetLibraryTail searches it, in one walk over the real
  project (1.43; 1.42 asked the resolver a second question about a temp shadow project
  because src\index could not change then). }

interface

uses
  DRagLint.Index.Closure
  , DRagLint.Project.Resolver  // dl:ok uses-global-census@d4b1 -- REVIEWED 2026-11-04: DEFAULT_BDS_KEY belongs with the resolver this unit opens per key
  ;

type
  /// <summary>The Studio key one project's library paths come from, and how that
  /// choice was made.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.CLI.BuildPlanItem (DRagLint.CLI.pas) ?, DRagLint.CLI.DoIndex (DRagLint.CLI.pas), DRagLint.CLI.PlanToJson (DRagLint.CLI.pas) ?, DRagLint.CLI.SectionTargetStudio (DRagLint.CLI.pas) ?, DRagLint.Project.TargetStudio.ResolveTargetStudio (DRagLint.Project.TargetStudio.pas) (+4 more)</para>
  /// <para>Used in units: DRagLint.CLI, DRagLint.Project.TargetStudio</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TTargetStudio = record
    /// <summary>The key the target asks for; '' when nothing names a target, or
    /// the target has no BDS key the mapping knows.</summary>
    RequestedBds: string;
    /// <summary>The key actually read; never ''.</summary>
    UsedBds: string;
    /// <summary>'Delphi 10.3' for a named target, else ''.</summary>
    TargetName: string;
    /// <summary>One line naming requested and used when the target could not be
    /// honoured; '' otherwise.</summary>
    Note: string;
    /// <summary>True when the key read is not the default Studio's.</summary>
    /// <returns>UsedBds differs from DEFAULT_BDS_KEY.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Project.TargetStudio.TTargetStudio.SummaryLine (DRagLint.Project.TargetStudio.pas), DRagLint.Refactor.MultiProjectRename.LibraryRootsOf (DRagLint.Refactor.MultiProjectRename.pas)</para>
    /// <para>Calls: SameText</para>
    /// <para>Returns: not SameText(UsedBds, DEFAULT_BDS_KEY)</para>
    /// <para>Reads: UsedBds</para>
    /// <seealso cref="DRagLint.Project.TargetStudio.TTargetStudio.OpenResolver"/>
    /// <seealso cref="DRagLint.Project.TargetStudio.TTargetStudio.SummaryLine"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function IsForeign: Boolean;
    /// <summary>A resolver over the key read.</summary>
    /// <returns>The caller owns it.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.CLI.BuildPlanItem (DRagLint.CLI.pas), DRagLint.CLI.BuildProjectFileScope (DRagLint.CLI.pas), DRagLint.CLI.DoIndex (DRagLint.CLI.pas), DRagLint.CLI.DoReconcileProject (DRagLint.CLI.pas), DRagLint.CLI.DoSelfTestClosure (DRagLint.CLI.pas) (+4 more)</para>
    /// <para>Calls: DRagLint.Project.Resolver.TProjectResolver.CreateForStudio</para>
    /// <para>Returns: TProjectResolver.CreateForStudio(UsedBds)</para>
    /// <para>Reads: UsedBds</para>
    /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.CreateForStudio"/>
    /// <seealso cref="DRagLint.Project.TargetStudio.TTargetStudio.IsForeign"/>
    /// <seealso cref="DRagLint.Project.TargetStudio.TTargetStudio.SummaryLine"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function OpenResolver: TProjectResolver;
    /// <summary>The line `index` prints for a foreign key.</summary>
    /// <returns>'Library path: BDS 20.0 (target Delphi 10.3)'; '' on the default.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.CLI.BuildPlanItem (DRagLint.CLI.pas), DRagLint.CLI.DoIndexAll (DRagLint.CLI.pas), DRagLint.CLI.WriteIndexStudioSummary (DRagLint.CLI.pas)</para>
    /// <para>Calls: DRagLint.Project.TargetStudio.TTargetStudio.IsForeign, Format</para>
    /// <para>Returns: if IsForeign then Format('Library path: BDS %s (target %s)', [UsedBds, TargetName])</para>
    /// <para>Reads: UsedBds, TargetName</para>
    /// <seealso cref="DRagLint.Project.TargetStudio.TTargetStudio.IsForeign"/>
    /// <seealso cref="DRagLint.Project.TargetStudio.TTargetStudio.OpenResolver"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function SummaryLine: string;
  end;

/// <summary>Records the run's --target-compiler for ResolveTargetStudio.</summary>
/// <param name="pTargetArg">The raw value; '' when absent.</param>
/// <remarks>
/// Set once at start-up, before any verb. A --jobs child receives the same
/// flag on its command line, so its value matches its parent's.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.Run (DRagLint.CLI.pas)</para>
/// <para>Calls: Trim</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
procedure SetRunTargetCompilerArg(const pTargetArg: string);

/// <summary>Chooses the Studio key for a project, with the precedence of the
/// defines: --target-compiler, then the .dproj's ProjectVersion, then the default.</summary>
/// <param name="pProjectFile">The project; only a .dproj carries a ProjectVersion.
/// '' or anything else takes the default unless --target-compiler names a version.</param>
/// <returns>The choice. Falls back to the default with a Note when the target's key
/// is not installed.</returns>
/// <remarks>
/// An absent or unmappable ProjectVersion is SILENT, as the defines are: that
/// project has no target, so nothing was not honoured. Reads the .dproj and the
/// registry; never raises for a missing file.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.BuildProjectFileScope (DRagLint.CLI.pas), DRagLint.CLI.DoIndex (DRagLint.CLI.pas), DRagLint.CLI.DoReconcileProject (DRagLint.CLI.pas), DRagLint.CLI.DoSelfTestClosure (DRagLint.CLI.pas), DRagLint.CLI.SectionTargetStudio (DRagLint.CLI.pas) (+4 more)</para>
/// <para>Calls: Default, DRagLint.Lint.TargetCompiler.CompilerDisplayName, DRagLint.Lint.TargetCompiler.ResolveTargetCompiler, DRagLint.Project.Resolver.IsBdsStudioInstalled, DRagLint.Project.TargetStudio.BdsKeyOfCompilerVersion, ExtractFileExt, Format, SameText</para>
/// <para>Returns: Default(TTargetStudio)</para>
/// <seealso cref="DRagLint.Lint.TargetCompiler.CompilerDisplayName"/>
/// <seealso cref="DRagLint.Lint.TargetCompiler.ResolveTargetCompiler"/>
/// <seealso cref="DRagLint.Project.Resolver.IsBdsStudioInstalled"/>
/// <seealso cref="DRagLint.Project.TargetStudio.BdsKeyOfCompilerVersion"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ResolveTargetStudio(const pProjectFile: string): TTargetStudio;

/// <summary>A project's compile closure with the library tail searched after the
/// project's own folders, as dcc does.</summary>
/// <param name="pClosure">Configured with library roots and profile. Not owned.</param>
/// <param name="pProjectFile">The .dproj, .dpr or .dpk.</param>
/// <param name="pExclude">Exclude globs, as TClosureResolver.Resolve takes them.</param>
/// <param name="pTail">TProjectResolver.ClosureSearchTail; nil for the plain closure.</param>
/// <returns>TClosureResolver.Resolve's result; a unit found through the tail appears
/// where the walk met it, and Result.SearchPaths ends with the tail.</returns>
/// <exception cref="Exception">As TClosureResolver.Resolve when the project file
/// does not exist.</exception>
/// <remarks>
/// Sets pTail on pClosure, replacing any earlier tail. Writes nothing to disk.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.BuildPlanItem (DRagLint.CLI.pas), DRagLint.CLI.DoIndex (DRagLint.CLI.pas), DRagLint.CLI.DoSelfTestClosure (DRagLint.CLI.pas)</para>
/// <para>Calls: DRagLint.Index.Closure.TClosureResolver.Resolve, DRagLint.Index.Closure.TClosureResolver.SetLibraryTail</para>
/// <para>Returns: pClosure.Resolve(pProjectFile, pExclude)</para>
/// <seealso cref="DRagLint.Index.Closure.TClosureResolver.Resolve"/>
/// <seealso cref="DRagLint.Index.Closure.TClosureResolver.SetLibraryTail"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ResolveTargetClosure(pClosure: TClosureResolver; const pProjectFile: string;
  const pExclude, pTail: TArray<string>): TClosureResult;

implementation

uses
  System.SysUtils
  , DRagLint.Lint.TargetCompiler  // dl:ok uses-global-census@d7c5 -- REVIEWED 2026-11-04: TARGET_COMPILER_AUTO is the token of the resolver call this unit makes
  , DRagLint.Preprocess.Profile
  ;

const
  { CompilerVersionOfStudioRoot reads a folder's leaf; any parent does. }
  PROBE_PARENT = 'x\';
  KEY_SUFFIX = '.0';
  FIRST_MAPPED_BDS = 14;

var
  GRunTargetArg: string;

function TTargetStudio.IsForeign: Boolean;
begin
  Result:= not SameText(UsedBds, DEFAULT_BDS_KEY);
end;

function TTargetStudio.OpenResolver: TProjectResolver;
begin
  Result:= TProjectResolver.CreateForStudio(UsedBds);
end;

function TTargetStudio.SummaryLine: string;
begin
  Result:= if IsForeign then Format('Library path: BDS %s (target %s)', [UsedBds, TargetName]) else '';
end;

{ The inverse of CompilerVersionOfStudioRoot: 33 -> '20.0'; '' when that mapping has none (XE5 and older). }
function BdsKeyOfCompilerVersion(pCompilerVersion: Integer): string;
begin
  for var Bds: Integer:= FIRST_MAPPED_BDS to pCompilerVersion do
    if CompilerVersionOfStudioRoot(PROBE_PARENT + IntToStr(Bds) + KEY_SUFFIX) = pCompilerVersion then
      Exit(IntToStr(Bds) + KEY_SUFFIX);
  Result:= '';
end;

procedure SetRunTargetCompilerArg(const pTargetArg: string);
begin
  GRunTargetArg:= Trim(pTargetArg);
end;

function ResolveTargetStudio(const pProjectFile: string): TTargetStudio;
var
  Tok    : string ;
  Version: Integer;
  Err    : string ;
begin
  Result:= Default(TTargetStudio);
  Result.UsedBds:= DEFAULT_BDS_KEY;
  Tok:= GRunTargetArg;
  if (Tok = '') and SameText(ExtractFileExt(pProjectFile), '.dproj') then Tok:= TARGET_COMPILER_AUTO;
  if Tok = '' then Exit;
  if not ResolveTargetCompiler(Tok, '', '', pProjectFile, Version, Err) then Exit;

  Result.TargetName:= CompilerDisplayName(Version);
  Result.RequestedBds:= BdsKeyOfCompilerVersion(Version);
  if Result.RequestedBds = '' then
    Result.Note:= Format('note: library path: target %s has no BDS key this engine can map; using BDS %s',
      [Result.TargetName, DEFAULT_BDS_KEY])
  else if IsBdsStudioInstalled(Result.RequestedBds) then Result.UsedBds:= Result.RequestedBds
  else if not SameText(Result.RequestedBds, DEFAULT_BDS_KEY) then
    Result.Note:= Format('note: library path: target %s wants BDS %s, which is not installed here; using BDS %s',
      [Result.TargetName, Result.RequestedBds, DEFAULT_BDS_KEY]);
end;

function ResolveTargetClosure(pClosure: TClosureResolver; const pProjectFile: string;
  const pExclude, pTail: TArray<string>): TClosureResult;
begin
  pClosure.SetLibraryTail(pTail);
  Result:= pClosure.Resolve(pProjectFile, pExclude);
end;

end.
