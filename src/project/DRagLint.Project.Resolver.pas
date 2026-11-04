unit DRagLint.Project.Resolver;

interface

uses
  System.SysUtils
  , System.StrUtils
  , System.RegularExpressions
  , System.Classes
  , System.IOUtils
  , System.Generics.Collections
  , System.Win     .Registry
  , Winapi.Windows
  , DRagLint.Core.StudioEnv { TStudioEnv: the ONLY source of a RAD Studio path }
  ;

const
  /// <summary>The BDS key of the one Studio this product runs on (Delphi 13): what
  /// every reader uses when nothing names another target.</summary>
  DEFAULT_BDS_KEY = '37.0';

/// <summary>True when a Studio's key names a root folder that exists.</summary>
/// <param name="AStudio">A BDS key, e.g. '20.0'.</param>
/// <returns>False for a missing key, and for a key an uninstalled Studio left
/// behind pointing at a folder that is gone.</returns>
function IsBdsStudioInstalled(const AStudio: string): Boolean;

type
  // Resolves the set of folders that should be scanned for a Delphi project.
  // Inputs: a .dproj path. Outputs: deduplicated folder list combining:
  //   - the .dproj's own folder
  //   - DCC_UnitSearchPath entries from the .dproj
  //   - Library and Browsing paths from registry (Win32 + Win64, HKCU + HKLM)
  //   - folders containing each unit listed in the .dpr's `uses X in 'path'`
  //     clauses (one level deep)
  // All $(BDS) and similar macros are expanded.
  /// <summary><!-- drag-lint:auto sum -->Resolves the set of folders that should be
  /// scanned for a Delphi project. Inputs: a .dproj path. Outputs: deduplicated folder
  /// list combining: - the .dproj's own folder - DCC_UnitSearchPath entries from the
  /// .dproj - Library and Browsing paths from registry (Win32 + Win64, HKCU + HKLM) -
  /// folders containing each unit listed in the .dpr's `uses X in 'path'` clauses (one
  /// level deep) All $(BDS) and similar macros are expanded.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: [drag-lint]declaration (DRagLint.Index.Coverage.pas), [drag-lint]declaration (DRagLint.Index.DbSelect.pas), [drag-lint]declaration (DRagLint.Index.Plan.pas), [drag-lint]DRagLint.CLI.BuildPlanItem (DRagLint.CLI.pas), [drag-lint]DRagLint.CLI.BuildProjectFileScope (DRagLint.CLI.pas), [drag-lint]DRagLint.CLI.CompileUnitInContext (DRagLint.CLI.pas), [drag-lint]DRagLint.CLI.DoCheckUnit (DRagLint.CLI.pas), [drag-lint]DRagLint.CLI.DoCycles.OpenPlanLibrary (DRagLint.CLI.pas), [drag-lint]DRagLint.CLI.DoIndex (DRagLint.CLI.pas), [drag-lint]DRagLint.CLI.DoIndexAll (DRagLint.CLI.pas), [drag-lint]DRagLint.CLI.DoLibraryDrift (DRagLint.CLI.pas), [drag-lint]DRagLint.CLI.DoReconcileProject (DRagLint.CLI.pas), [drag-lint]DRagLint.CLI.DoResolveDbsList (DRagLint.CLI.pas), [drag-lint]DRagLint.CLI.DoSelfTestClosure (DRagLint.CLI.pas), [drag-lint]DRagLint.CLI.DoSelfTestCoverage (DRagLint.CLI.pas), [drag-lint]DRagLint.CLI.DoSelfTestDbSelect (DRagLint.CLI.pas),
  /// [drag-lint]DRagLint.CLI.LibrarySectionDbs (DRagLint.CLI.pas), [drag-lint]DRagLint.CLI.MakeSiblingStoreResolver (DRagLint.CLI.pas), [drag-lint]DRagLint.CLI.ResolveConsumerDbs (DRagLint.CLI.pas), [drag-lint]DRagLint.CLI.ResolveLibraryDb (DRagLint.CLI.pas), [drag-lint]DRagLint.CLI.ResolveReadDbsForFileWith (DRagLint.CLI.pas), [drag-lint]DRagLint.Doc.Batch.TDocBatch.DocumentProject (DRagLint.Doc.Batch.pas), [drag-lint]DRagLint.Index.DbSelect.TDbSelect.Resolve (DRagLint.Index.DbSelect.pas), [drag-lint]DRagLint.Lint.ProjectChecks.TProjectChecks.CheckUsedUnitResolvable.EnsureDcuStems (DRagLint.Lint.ProjectChecks.pas), [drag-lint]DRagLint.Refactor.MultiProjectRename.FindRenameOwners (DRagLint.Refactor.MultiProjectRename.pas), [drag-lint]DRagLint.Refactor.MultiProjectRename.LibraryRoots (DRagLint.Refactor.MultiProjectRename.pas)</para>
  /// <para>Used in units: Config.IndexesFrame, Config.SettingsFrame, [drag-lint]DRagLint.CLI, [drag-lint]DRagLint.Doc.Batch, [drag-lint]DRagLint.Index.Coverage, [drag-lint]DRagLint.Index.DbSelect, [drag-lint]DRagLint.Index.Plan, [drag-lint]DRagLint.Lint.ProjectChecks, DragLint.Plugin.OptionsFrames, [drag-lint]DRagLint.Refactor.MultiProjectRename</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TProjectResolver = class
    strict private
      FBDS            : string                          ;
      FStudio         : string                          ; // the BDS key this instance reads
      FCurrentPlatform: string                          ; // what $(Platform) expands to right now
      FEnvVars        : TDictionary<string, string>     ; // RAD Studio "Environment Variables" (e.g. DXVCL), loaded lazily
      FEnvVarsLoaded  : Boolean                          ;
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.Project.Resolver.TProjectResolver.ResolveNamedMacro (DRagLint.Project.Resolver.pas)</para>
      /// <para>Calls: UpperCase</para>
      /// <para>Reads: FEnvVarsLoaded, FEnvVars   Writes: FEnvVarsLoaded</para>
      /// <para>Touches: registry</para>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.AddFolderIfReal"/>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.AddSemicolonList"/>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.CollectProjectFolders"/>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.Create"/>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.Destroy"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure EnsureEnvVarsLoaded                     ;
      /// <param name="AName"><!-- drag-lint:auto type -->const string</param>
      /// <param name="AValue"><!-- drag-lint:auto type -->out string</param>
      /// <returns><!-- drag-lint:auto -->Boolean -- Observed: AValue &lt;&gt; ''.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.Project.Resolver.TProjectResolver.ExpandMacros (DRagLint.Project.Resolver.pas)</para>
      /// <para>Calls: DRagLint.Project.Resolver.TProjectResolver.EnsureEnvVarsLoaded, GetEnvironmentVariable, UpperCase</para>
      /// <para>Reads: FEnvVars</para>
      /// <para>Mutates: AValue (out)</para>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.EnsureEnvVarsLoaded"/>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.AddFolderIfReal"/>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.AddSemicolonList"/>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.CollectProjectFolders"/>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.Create"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function ResolveNamedMacro(const AName: string; out AValue: string): Boolean;
      /// <param name="APath"><!-- drag-lint:auto type -->const string</param>
      /// <returns><!-- drag-lint:auto type -->string</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.Project.Resolver.TProjectResolver.AddFolderIfReal (DRagLint.Project.Resolver.pas), DRagLint.Project.Resolver.TProjectResolver.AddSemicolonList (DRagLint.Project.Resolver.pas)</para>
      /// <para>Calls: DRagLint.Project.Resolver.TProjectResolver.ResolveNamedMacro, Pos, StringReplace</para>
      /// <para>Reads: FBDS, FCurrentPlatform</para>
      /// <para>Touches: file system</para>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.ResolveNamedMacro"/>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.AddFolderIfReal"/>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.AddSemicolonList"/>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.CollectProjectFolders"/>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.Create"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function ExpandMacros(const APath: string): string;
      /// <param name="AList"><!-- drag-lint:auto type -->TList&lt;string&gt;</param>
      /// <param name="APath"><!-- drag-lint:auto type -->const string</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.Project.Resolver.TProjectResolver.AddSemicolonList (DRagLint.Project.Resolver.pas), DRagLint.Project.Resolver.TProjectResolver.ReadDProj (DRagLint.Project.Resolver.pas), DRagLint.Project.Resolver.TProjectResolver.ReadDprUsesPaths (DRagLint.Project.Resolver.pas)</para>
      /// <para>Calls: DRagLint.Project.Resolver.TProjectResolver.ExpandMacros, SameText</para>
      /// <para>Catches: Exception (swallowed)</para>
      /// <para>Touches: file system</para>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.ExpandMacros"/>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.AddSemicolonList"/>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.CollectProjectFolders"/>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.Create"/>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.Destroy"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure AddFolderIfReal(AList: TList<string>; const APath: string);
      /// <param name="AList"><!-- drag-lint:auto type -->TList&lt;string&gt;</param>
      /// <param name="ASemicolonList"><!-- drag-lint:auto type -->const string</param>
      /// <param name="ABaseDir"><!-- drag-lint:auto type -->const string</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.Project.Resolver.TProjectResolver.ReadDProj (DRagLint.Project.Resolver.pas), DRagLint.Project.Resolver.TProjectResolver.ReadLibraryPaths/3 (DRagLint.Project.Resolver.pas)</para>
      /// <para>Calls: DRagLint.Project.Resolver.TProjectResolver.AddFolderIfReal, DRagLint.Project.Resolver.TProjectResolver.ExpandMacros</para>
      /// <para>Touches: file system</para>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.AddFolderIfReal"/>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.ExpandMacros"/>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.CollectProjectFolders"/>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.Create"/>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.Destroy"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure AddSemicolonList(AList: TList<string>; const ASemicolonList: string; const ABaseDir: string);
      /// <summary><!-- drag-lint:auto sum -->Enumerates every platform subkey under
      /// this Studio's Library across both hives and registry views, deduplicated
      /// case-insensitively. These are the names Delphi itself registers (Win32, Win64,
      /// Android64, iOSDevice64, ...).</summary>
      /// <returns><!-- drag-lint:auto -->TArray&lt;string&gt; -- Observed: List.ToArray.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.Project.Resolver.TProjectResolver.EnumRegistryPlatforms (DRagLint.Project.Resolver.pas), DRagLint.Project.Resolver.TProjectResolver.ResolveLibraryPaths (DRagLint.Project.Resolver.pas)</para>
      /// <para>Calls: DRagLint.Project.Resolver.TProjectResolver.EnumLibraryPlatforms.AddUnique, HKEY, SameText</para>
      /// <para>Touches: registry</para>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.EnumLibraryPlatforms.AddUnique"/>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.AddFolderIfReal"/>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.AddSemicolonList"/>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.CollectProjectFolders"/>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.Create"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function EnumLibraryPlatforms: TArray<string>;
      /// <param name="AList"><!-- drag-lint:auto type -->TList&lt;string&gt;</param>
      /// <param name="APlatforms"><!-- drag-lint:auto type -->const TArray&lt;string&gt;</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.Project.Resolver.TProjectResolver.ReadPlatformLibraryPaths (DRagLint.Project.Resolver.pas), DRagLint.Project.Resolver.TProjectResolver.Resolve (DRagLint.Project.Resolver.pas), DRagLint.Project.Resolver.TProjectResolver.ResolveLibraryPaths (DRagLint.Project.Resolver.pas)</para>
      /// <para>Calls: DRagLint.Project.Resolver.TProjectResolver.ReadLibraryPaths/3</para>
      /// <para>Overload 1 of 2</para>
      /// <para>Pure</para>
      /// <para>Directives: overload</para>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.ReadLibraryPaths"/>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.AddFolderIfReal"/>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.AddSemicolonList"/>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.CollectProjectFolders"/>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.Create"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure ReadLibraryPaths(AList: TList<string>; const APlatforms: TArray<string>); overload;
    /// <summary><!-- drag-lint:auto sum -->Indexing callers must keep BOTH -- a
    /// browsing-only root is still code the user can open and therefore code the index
    /// should know. So Resolve is unchanged and only the COMPILE path opts out.</summary>
    /// <param name="AList"><!-- drag-lint:auto type -->TList&lt;string&gt;</param>
    /// <param name="APlatforms"><!-- drag-lint:auto type -->const TArray&lt;string&gt;</param>
    /// <param name="ASearchPathOnly"><!-- drag-lint:auto type -->Boolean</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Project.Resolver.TProjectResolver.ReadLibraryPaths/2 (DRagLint.Project.Resolver.pas), DRagLint.Project.Resolver.TProjectResolver.ResolveCompilePaths (DRagLint.Project.Resolver.pas)</para>
    /// <para>Calls: DRagLint.Project.Resolver.ReadRegPathInto, DRagLint.Project.Resolver.TProjectResolver.AddSemicolonList, HKEY</para>
    /// <para>Overload 2 of 2</para>
    /// <para>Writes: FCurrentPlatform</para>
    /// <para>Directives: overload</para>
    /// <seealso cref="DRagLint.Project.Resolver.ReadRegPathInto"/>
    /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.AddSemicolonList"/>
    /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.AddFolderIfReal"/>
    /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.CollectProjectFolders"/>
    /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.Create"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure ReadLibraryPaths(AList: TList<string>; const APlatforms: TArray<string>; ASearchPathOnly: Boolean); overload;
      /// <param name="ADprojPath"><!-- drag-lint:auto type -->const string</param>
      /// <param name="AList"><!-- drag-lint:auto type -->TList&lt;string&gt;</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.Project.Resolver.TProjectResolver.CollectProjectFolders (DRagLint.Project.Resolver.pas)</para>
      /// <para>Calls: DRagLint.Project.Resolver.TProjectResolver.AddFolderIfReal, DRagLint.Project.Resolver.TProjectResolver.AddSemicolonList, Format</para>
      /// <para>Touches: file system</para>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.AddFolderIfReal"/>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.AddSemicolonList"/>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.CollectProjectFolders"/>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.Create"/>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.Destroy"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure ReadDProj       (const ADprojPath: string; AList: TList<string>);
      /// <param name="ADprPath"><!-- drag-lint:auto type -->const string</param>
      /// <param name="AList"><!-- drag-lint:auto type -->TList&lt;string&gt;</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.Project.Resolver.TProjectResolver.CollectProjectFolders (DRagLint.Project.Resolver.pas)</para>
      /// <para>Calls: Copy, DRagLint.Project.Resolver.TProjectResolver.AddFolderIfReal, Pos, PosEx</para>
      /// <para>Touches: file system</para>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.AddFolderIfReal"/>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.AddSemicolonList"/>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.CollectProjectFolders"/>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.Create"/>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.Destroy"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure ReadDprUsesPaths(const ADprPath  : string; AList: TList<string>);
      /// <summary><!-- drag-lint:auto sum -->The project's OWN folders, shared by Resolve
      /// and ResolveProjectOnly: the .dproj search paths plus the directories named by
      /// the main source's `in '...'` clauses. Deliberately contains no registry lookup
      /// -- that tail is what separates a compiler search path from an indexing scope,
      /// and it is added by Resolve alone.</summary>
      /// <param name="ADprojPath"><!-- drag-lint:auto type -->const string</param>
      /// <param name="AList"><!-- drag-lint:auto type -->TList&lt;string&gt;</param>
      /// <exception cref="Exception"><!-- drag-lint:auto exc -->.dproj not found: %s</exception>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.Project.Resolver.TProjectResolver.Resolve (DRagLint.Project.Resolver.pas), DRagLint.Project.Resolver.TProjectResolver.ResolveCompilePaths (DRagLint.Project.Resolver.pas), DRagLint.Project.Resolver.TProjectResolver.ResolveProjectOnly (DRagLint.Project.Resolver.pas)</para>
      /// <para>Calls: DRagLint.Project.Resolver.TProjectResolver.ReadDProj, DRagLint.Project.Resolver.TProjectResolver.ReadDprUsesPaths</para>
      /// <para>Touches: file system</para>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.ReadDProj"/>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.ReadDprUsesPaths"/>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.AddFolderIfReal"/>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.AddSemicolonList"/>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.Create"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure CollectProjectFolders(const ADprojPath: string; AList: TList<string>);
    public
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.CLI.BuildPlanItem (DRagLint.CLI.pas), DRagLint.CLI.BuildProjectFileScope (DRagLint.CLI.pas), DRagLint.CLI.CompileUnitInContext (DRagLint.CLI.pas), DRagLint.CLI.DoCycles.OpenPlanLibrary (DRagLint.CLI.pas), DRagLint.CLI.DoIndex (DRagLint.CLI.pas) (+16 more)</para>
      /// <para>Calls: DRagLint.Core.StudioEnv.TStudioEnv.RootOrEmpty</para>
      /// <para>constructor</para>
      /// <para>Writes: FBDS, FCurrentPlatform, FEnvVars, FEnvVarsLoaded</para>
      /// <seealso cref="DRagLint.Core.StudioEnv.TStudioEnv.RootOrEmpty"/>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.AddFolderIfReal"/>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.AddSemicolonList"/>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.CollectProjectFolders"/>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.Destroy"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      constructor Create;
      /// <summary>A resolver over ANOTHER Studio's key: its Search and Browsing
      /// paths, platform list and Environment Variables, with $(BDS) and
      /// $(BDSCOMMONDIR) expanding from that key's RootDir.</summary>
      /// <param name="AStudio">A BDS key; DEFAULT_BDS_KEY behaves exactly as Create.</param>
      /// <remarks>Does not check the key is installed: IsBdsStudioInstalled is the
      /// caller's decision. TStudioEnv and the compiler stay on 37.0.</remarks>
      constructor CreateForStudio(const AStudio: string);
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Reads: FEnvVars</para>
      /// <para>Pure</para>
      /// <para>Directives: override</para>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.AddFolderIfReal"/>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.AddSemicolonList"/>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.CollectProjectFolders"/>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.Create"/>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.EnsureEnvVarsLoaded"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      destructor Destroy; override;
      /// <summary>The COMPILER search path for ADprojPath: the project's own
      /// folders PLUS the IDE's registry Library/Browsing paths for Win32 and
      /// Win64. Use for anything that has to invoke dcc, which must be able to
      /// find the RTL.</summary>
      /// <param name="ADprojPath">Absolute path to the .dproj.</param>
      /// <returns>Deduplicated existing folders, project folders first.</returns>
      /// <exception cref="Exception">Raised when ADprojPath does not exist.</exception>
      /// <remarks>
      /// NOT an indexing scope. The registry tail is the whole machine's
      /// library -- 151 folders on a typical box -- so walking what this returns
      /// indexes the entire RTL/VCL and every installed component's source. Use
      /// <see cref="ResolveProjectOnly"/> to index a project.
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Calls: DRagLint.Project.Resolver.TProjectResolver.CollectProjectFolders, DRagLint.Project.Resolver.TProjectResolver.ReadLibraryPaths/2</para>
      /// <para>Returns: List.ToArray</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.CollectProjectFolders"/>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.ReadLibraryPaths"/>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.AddFolderIfReal"/>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.AddSemicolonList"/>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.Create"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function Resolve(const ADprojPath: string): TArray<string>;
    /// <summary>The folders dcc should COMPILE against: the project's own plus
    /// the TARGET platform's registry Search Path, in registry order.</summary>
    /// <param name="ADprojPath"><!-- drag-lint:auto type -->const string</param>
    /// <param name="APlatform"><!-- drag-lint:auto type -->const string</param>
    /// <returns><!-- drag-lint:auto -->TArray&lt;string&gt; -- Observed: List.ToArray.</returns>
    /// <exception cref="Exception"><!-- drag-lint:auto exc -->via DRagLint.Project.Resolver.TProjectResolver.CollectProjectFolders: .dproj not found: %s</exception>
    /// <remarks>
    /// Deliberately NOT Resolve: that one adds the Browsing Path and
    /// both platforms, which is right for indexing and wrong for compiling --
    /// it put a Source dir 102 positions ahead of its DCU dir and made dcc
    /// rebuild Spring4D from source on every invocation.
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.CLI.CompileUnitInContext (DRagLint.CLI.pas)</para>
    /// <para>Calls: DRagLint.Project.Resolver.TProjectResolver.CollectProjectFolders, DRagLint.Project.Resolver.TProjectResolver.ReadLibraryPaths/3</para>
    /// <para>Pure</para>
    /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.CollectProjectFolders"/>
    /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.ReadLibraryPaths"/>
    /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.AddFolderIfReal"/>
    /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.AddSemicolonList"/>
    /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.Create"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function ResolveCompilePaths(const ADprojPath, APlatform: string): TArray<string>;
      /// <summary>The INDEXING scope for ADprojPath: the project's own folders
      /// only -- its .dproj search paths, the directories named by the .dpr's
      /// `in '...'` clauses, and the project directory itself. The registry
      /// Library/Browsing paths are deliberately NOT appended.</summary>
      /// <param name="ADprojPath">Absolute path to the .dproj.</param>
      /// <returns>Deduplicated existing folders. Typically 1-5 entries.</returns>
      /// <exception cref="Exception">Raised when ADprojPath does not exist.</exception>
      /// <remarks>
      /// Split out from <see cref="Resolve"/> on 2026-08-03: `index
      /// --project` had been walking Resolve's registry tail, which turned a
      /// 12-unit project into a 153-folder scan duplicating library-Win32.sqlite
      /// and library-Win64.sqlite wholesale. Library coverage belongs in those
      /// shared indexes; a consumer reaches it by passing a second --db.
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Calls: DRagLint.Project.Resolver.TProjectResolver.CollectProjectFolders</para>
      /// <para>Returns: List.ToArray</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.CollectProjectFolders"/>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.AddFolderIfReal"/>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.AddSemicolonList"/>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.Create"/>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.Destroy"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function ResolveProjectOnly(const ADprojPath: string): TArray<string>;
      // Library/Browsing paths from registry only - no .dproj required.
      // Useful for "index everything Delphi knows about" without a project.
      //   AAllPlatforms = False -> Win32 + Win64 only (the IDE's native targets).
      //   AAllPlatforms = True  -> every platform subkey under ...\BDS\37.0\Library
      //     (Android*, iOS*, Linux64, OSX*, Win64x, ...), which additionally pulls
      //     in the Posix / Androidapi / iOSapi / Macapi platform source trees.
      /// <summary><!-- drag-lint:auto sum -->Library/Browsing paths from registry only -
      /// no .dproj required. Useful for "index everything Delphi knows about" without a
      /// project. AAllPlatforms = False -&gt; Win32 + Win64 only (the IDE's native
      /// targets). AAllPlatforms = True -&gt; every platform subkey under
      /// ...\BDS\37.0\Library (Android*, iOS*, Linux64, OSX*, Win64x, ...), which
      /// additionally pulls in the Posix / Androidapi / iOSapi / Macapi platform source
      /// trees.</summary>
      /// <param name="AAllPlatforms"><!-- drag-lint:auto type -->Boolean = False</param>
      /// <returns><!-- drag-lint:auto -->TArray&lt;string&gt; -- Observed: List.ToArray.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.CLI.BuildPlanItem (DRagLint.CLI.pas), DRagLint.CLI.BuildProjectFileScope (DRagLint.CLI.pas), DRagLint.CLI.CompileUnitInContext (DRagLint.CLI.pas), DRagLint.CLI.DoIndex (DRagLint.CLI.pas), DRagLint.CLI.DoReconcileProject (DRagLint.CLI.pas) (+4 more)</para>
      /// <para>Calls: DRagLint.Project.Resolver.TProjectResolver.EnumLibraryPlatforms, DRagLint.Project.Resolver.TProjectResolver.ReadLibraryPaths/2</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.EnumLibraryPlatforms"/>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.ReadLibraryPaths"/>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.AddFolderIfReal"/>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.AddSemicolonList"/>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.CollectProjectFolders"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function ResolveLibraryPaths(AAllPlatforms: Boolean = False): TArray<string>;
      /// <summary>Returns every platform name registered under this Studio's Library,
      /// deduplicated case-insensitively. Wraps the private EnumLibraryPlatforms.
      /// Returns at least ['Win32','Win64'] as a fallback when the registry is empty.</summary>
      /// <returns>Array of platform names (e.g. Win32, Win64, Android64).</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.CLI.BuildPlanItem (DRagLint.CLI.pas), DRagLint.CLI.DoIndexAll (DRagLint.CLI.pas), DRagLint.Index.Plan.ResolvePlan (DRagLint.Index.Plan.pas)</para>
      /// <para>Calls: DRagLint.Project.Resolver.TProjectResolver.EnumLibraryPlatforms</para>
      /// <para>Returns: EnumLibraryPlatforms; ['Win32', 'Win64']</para>
      /// <para>Effect-free (proven)</para>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.EnumLibraryPlatforms"/>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.AddFolderIfReal"/>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.AddSemicolonList"/>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.CollectProjectFolders"/>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.Create"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function EnumRegistryPlatforms: TArray<string>;
      /// <summary>Returns the resolved Library + Browsing search paths for one
      /// specific platform, as absolute folder paths. Probes HKCU + HKLM,
      /// both 32-bit and 64-bit registry views.</summary>
      /// <param name="APlatform">Platform subkey name, e.g. 'Win32', 'Win64'.</param>
      /// <returns>Deduplicated array of existing absolute folder paths.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.CLI.DoLibraryDrift (DRagLint.CLI.pas), DRagLint.Index.Plan.ResolvePlan (DRagLint.Index.Plan.pas), DRagLint.Lint.ProjectChecks.TProjectChecks.CheckUsedUnitResolvable.EnsureDcuStems (DRagLint.Lint.ProjectChecks.pas)</para>
      /// <para>Calls: DRagLint.Project.Resolver.TProjectResolver.ReadLibraryPaths/2</para>
      /// <para>Returns: List.ToArray</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.ReadLibraryPaths"/>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.AddFolderIfReal"/>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.AddSemicolonList"/>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.CollectProjectFolders"/>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.Create"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function ReadPlatformLibraryPaths(const APlatform: string): TArray<string>;
      /// <summary>The roots `index` keeps OUT of a project closure.</summary>
      /// <returns>On the default Studio exactly ResolveLibraryPaths. On another: what
      /// the platform library DBs (built from 37.0) cover, plus that Studio's own
      /// folders -- everything else on its path has no other index to live in.</returns>
      function ClosureLibraryRoots: TArray<string>;
      /// <summary>The roots that are not project MEMBERS: a unit under one needs no
      /// listing in the .dpr, because the compiler finds it through the library path.</summary>
      /// <returns>On the default Studio exactly ResolveLibraryPaths; on another, its
      /// whole library path plus the default Studio's.</returns>
      /// <remarks>For reconcile-project, unit-not-in-dpr, unit-not-in-library, autodoc
      /// and rename: a unit `index` added from the library path is not a project gap.</remarks>
      function MembershipLibraryRoots: TArray<string>;
      /// <summary>The folders a closure searches after the project's own, as dcc does.</summary>
      /// <param name="APlatform">The target platform.</param>
      /// <returns>Nil on the default Studio, where library units stay in the library
      /// DB. On another, its Search Path minus ClosureLibraryRoots, in path order.</returns>
      function ClosureSearchTail(const APlatform: string): TArray<string>;
  end;

implementation

uses
  System.JSON;

const
  BDS_REG_ROOT = '\Software\Embarcadero\BDS\';
  ENV_VARS_SUBKEY = '\Environment Variables';
  LIBRARY_SUBKEY = '\Library';
  ROOT_DIR_VALUE = 'RootDir';
  FIXTURE_ENV_VAR = 'DRAGLINT_TEST_BDS_REGISTRY';
  STUDIO_OWNED_FOLDER = '\embarcadero\';

type
  /// <summary>Everything this unit reads from a BDS registry key, as an input seam:
  /// a test replaces the whole tree without touching the real registry.</summary>
  /// <remarks>Stateless; each call reads its source afresh. A key or value that is
  /// not there answers empty, never raises.</remarks>
  IBdsRegistry = interface
    ['{6E0C4B1D-2A7F-4C53-9D3E-7A1B5F60C2E4}']
    /// <summary>The RootDir value of a Studio's key.</summary>
    /// <param name="AStudio">A BDS key, e.g. '20.0'.</param>
    /// <returns>The value as stored, or ''.</returns>
    function RootDir(const AStudio: string): string;
    /// <summary>The platform subkeys under the key's Library, in probe order.</summary>
    /// <param name="AStudio">A BDS key.</param>
    /// <returns>Names, duplicates possible (one source per hive and view).</returns>
    function LibraryPlatforms(const AStudio: string): TArray<string>;
    /// <summary>One path value of one platform, in probe order.</summary>
    /// <param name="AStudio">A BDS key.</param>
    /// <param name="APlatform">A platform subkey; case-insensitive.</param>
    /// <param name="AValueName">'Search Path' or 'Browsing Path'.</param>
    /// <returns>The raw semicolon lists, one per source that has the value.</returns>
    function LibraryPathValues(const AStudio, APlatform, AValueName: string): TArray<string>;
    /// <summary>The IDE's user-defined Environment Variables of a Studio.</summary>
    /// <param name="AStudio">A BDS key.</param>
    /// <returns>Name/value pairs as stored.</returns>
    function EnvironmentVariables(const AStudio: string): TArray<TPair<string, string>>;
  end;

  { A DRAGLINT_TEST_BDS_REGISTRY file that is not a JSON object: a broken test
    set-up, which must not read as an empty registry. }
  EBdsRegistryFixture = class(Exception);

  { The machine's registry: both hives and both views, HKCU first, 32-bit first --
    the order the resolver always read in, which ReadLibraryPaths's dedup and so the
    closure's root order depend on. }
  TRealBdsRegistry = class(TInterfacedObject, IBdsRegistry)
  public
    function RootDir(const AStudio: string): string;
    function LibraryPlatforms(const AStudio: string): TArray<string>;
    function LibraryPathValues(const AStudio, APlatform, AValueName: string): TArray<string>;
    function EnvironmentVariables(const AStudio: string): TArray<TPair<string, string>>;
  end;

  { The test seam: see ActiveBdsRegistry for the shape. Owns the parsed JSON. }
  TFixtureBdsRegistry = class(TInterfacedObject, IBdsRegistry)
  strict private
    FRoot: TJSONObject;
    function Child(AParent: TJSONObject; const AName: string): TJSONObject;
  public
    constructor Create(const AFixtureFile: string);
    destructor Destroy; override;
    function RootDir(const AStudio: string): string;
    function LibraryPlatforms(const AStudio: string): TArray<string>;
    function LibraryPathValues(const AStudio, APlatform, AValueName: string): TArray<string>;
    function EnvironmentVariables(const AStudio: string): TArray<TPair<string, string>>;
  end;

function TRealBdsRegistry.RootDir(const AStudio: string): string;
var
  Reg     : TRegistry;
  HiveRoot: HKEY     ;
  Sam     : Cardinal ;
begin
  Result:= '';
  for HiveRoot in [HKEY(HKEY_CURRENT_USER), HKEY(HKEY_LOCAL_MACHINE)] do
    for Sam in [KEY_WOW64_32KEY, KEY_WOW64_64KEY] do
    begin
      Reg:= TRegistry.Create(KEY_READ or Sam);
      try
        Reg.RootKey:= HiveRoot;
        if Reg.OpenKeyReadOnly(BDS_REG_ROOT + AStudio) then
        try
          if Reg.ValueExists(ROOT_DIR_VALUE) then Result:= Trim(Reg.ReadString(ROOT_DIR_VALUE));
        finally
          Reg.CloseKey;
        end;
      finally
        Reg.Free;
      end;
      if Result <> '' then Exit;
    end;
end;

function TRealBdsRegistry.LibraryPlatforms(const AStudio: string): TArray<string>;
var
  Names   : TStringList;
  Reg     : TRegistry  ;
  HiveRoot: HKEY       ;
  Sam     : Cardinal   ;
begin
  Result:= nil;
  Names:= TStringList.Create;
  try
    for HiveRoot in [HKEY(HKEY_CURRENT_USER), HKEY(HKEY_LOCAL_MACHINE)] do
      for Sam in [KEY_WOW64_32KEY, KEY_WOW64_64KEY] do
      begin
        Reg:= TRegistry.Create(KEY_READ or Sam);
        try
          Reg.RootKey:= HiveRoot;
          if Reg.OpenKeyReadOnly(BDS_REG_ROOT + AStudio + LIBRARY_SUBKEY) then
          try
            Names.Clear;
            Reg.GetKeyNames(Names);
            Result:= Result + Names.ToStringArray;
          finally
            Reg.CloseKey;
          end;
        finally
          Reg.Free;
        end;
      end;
  finally
    Names.Free;
  end;
end;

function TRealBdsRegistry.LibraryPathValues(const AStudio, APlatform, AValueName: string): TArray<string>;
var
  Reg     : TRegistry;
  HiveRoot: HKEY     ;
  Sam     : Cardinal ;
begin
  Result:= nil;
  for HiveRoot in [HKEY(HKEY_CURRENT_USER), HKEY(HKEY_LOCAL_MACHINE)] do
    for Sam in [KEY_WOW64_32KEY, KEY_WOW64_64KEY] do
    begin
      Reg:= TRegistry.Create(KEY_READ or Sam);
      try
        Reg.RootKey:= HiveRoot;
        if Reg.OpenKeyReadOnly(BDS_REG_ROOT + AStudio + LIBRARY_SUBKEY + '\' + APlatform) then
        try
          if Reg.ValueExists(AValueName) then Result:= Result + [Reg.ReadString(AValueName)];
        finally
          Reg.CloseKey;
        end;
      finally
        Reg.Free;
      end;
    end;
end;

function TRealBdsRegistry.EnvironmentVariables(const AStudio: string): TArray<TPair<string, string>>;
var
  Reg  : TRegistry  ;
  Names: TStringList;
  Name : string     ;
begin
  Result:= nil;
  Names:= TStringList.Create;
  Reg:= TRegistry.Create(KEY_READ);
  try
    Reg.RootKey:= HKEY_CURRENT_USER;
    if Reg.OpenKeyReadOnly(BDS_REG_ROOT + AStudio + ENV_VARS_SUBKEY) then
    try
      Reg.GetValueNames(Names);
      for Name in Names do
        if (Name.Trim <> '') and Reg.ValueExists(Name) then
          Result:= Result + [TPair<string, string>.Create(Name, Reg.ReadString(Name))];
    finally
      Reg.CloseKey;
    end;
  finally
    Reg.Free;
    Names.Free;
  end;
end;

constructor TFixtureBdsRegistry.Create(const AFixtureFile: string);
begin
  inherited Create;
  FRoot:= TJSONObject.ParseJSONValue(TFile.ReadAllText(AFixtureFile)) as TJSONObject; // dl:ok taint-path-traversal -- REVIEWED 2026-11-03 a test seam: the variable is set by the guard that owns the file, and the file is only parsed, never executed or written
  if FRoot = nil then raise EBdsRegistryFixture.CreateFmt('%s: not a JSON object: %s', [FIXTURE_ENV_VAR, AFixtureFile]);
end;

destructor TFixtureBdsRegistry.Destroy;
begin
  FRoot.Free;
  inherited Destroy;
end;

function TFixtureBdsRegistry.Child(AParent: TJSONObject; const AName: string): TJSONObject;
begin
  Result:= nil;
  if AParent = nil then Exit;
  for var Pair: TJSONPair in AParent do
    if SameText(Pair.JsonString.Value, AName) and (Pair.JsonValue is TJSONObject) then Exit(TJSONObject(Pair.JsonValue));
end;

function TFixtureBdsRegistry.RootDir(const AStudio: string): string;
var
  Studio: TJSONObject;
begin
  Result:= '';
  Studio:= Child(FRoot, AStudio);
  if Studio <> nil then Studio.TryGetValue<string>(ROOT_DIR_VALUE, Result);
end;

function TFixtureBdsRegistry.LibraryPlatforms(const AStudio: string): TArray<string>;
var
  Lib: TJSONObject;
begin
  Result:= nil;
  Lib:= Child(Child(FRoot, AStudio), 'Library');
  if Lib <> nil then
    for var Pair: TJSONPair in Lib do Result:= Result + [Pair.JsonString.Value];
end;

function TFixtureBdsRegistry.LibraryPathValues(const AStudio, APlatform, AValueName: string): TArray<string>;
var
  Plat : TJSONObject;
  Value: string     ;
begin
  Result:= nil;
  Plat:= Child(Child(Child(FRoot, AStudio), 'Library'), APlatform);
  if (Plat <> nil) and Plat.TryGetValue<string>(AValueName, Value) then Result:= [Value];
end;

function TFixtureBdsRegistry.EnvironmentVariables(const AStudio: string): TArray<TPair<string, string>>;
var
  Vars: TJSONObject;
begin
  Result:= nil;
  Vars:= Child(Child(FRoot, AStudio), 'Environment Variables');
  if Vars <> nil then
    for var Pair: TJSONPair in Vars do
      Result:= Result + [TPair<string, string>.Create(Pair.JsonString.Value, Pair.JsonValue.Value)];
end;

function BdsRegistryFixturePath: string;
begin
  Result:= Trim(GetEnvironmentVariable(FIXTURE_ENV_VAR));
end;

/// <summary>The registry every TProjectResolver reads: the real one, unless the
/// DRAGLINT_TEST_BDS_REGISTRY environment variable names a JSON fixture.</summary>
/// <returns>A stateless reader.</returns>
/// <remarks>The fixture replaces the WHOLE tree, 37.0 included, so a guard cannot
/// pass through the machine's own Studio by accident. Shape:
/// {"20.0": {"RootDir": "...", "Library": {"Win32": {"Search Path": "..."}},
/// "Environment Variables": {"NAME": "..."}}}.</remarks>
function ActiveBdsRegistry: IBdsRegistry;
begin
  if BdsRegistryFixturePath = '' then Exit(TRealBdsRegistry.Create);
  Result:= TFixtureBdsRegistry.Create(BdsRegistryFixturePath);
end;

function IsBdsStudioInstalled(const AStudio: string): Boolean;
var
  Root: string;
begin
  Root:= Trim(ActiveBdsRegistry.RootDir(AStudio));
  Result:= (Root <> '') and TDirectory.Exists(Root);
end;

{ True when AFile is AFolder or lies under it; case-insensitive. }
function IsUnderAnyRoot(const AFile: string; const ARoots: TArray<string>): Boolean;
var
  NormFile: string;
begin
  NormFile:= IncludeTrailingPathDelimiter(LowerCase(AFile));
  for var Root: string in ARoots do
    if NormFile.StartsWith(IncludeTrailingPathDelimiter(LowerCase(Root))) then Exit(True);
  Result:= False;
end;

constructor TProjectResolver.CreateForStudio(const AStudio: string);
begin
  Create;
  if SameText(AStudio, DEFAULT_BDS_KEY) then Exit;
  FStudio:= AStudio;
  FBDS:= ExcludeTrailingPathDelimiter(Trim(ActiveBdsRegistry.RootDir(AStudio)));
end;

function TProjectResolver.ClosureLibraryRoots: TArray<string>;
var
  Installed: TProjectResolver;
begin
  Result:= ResolveLibraryPaths;
  if SameText(FStudio, DEFAULT_BDS_KEY) then Exit;
  var Own: TArray<string>:= Result;
  Installed:= TProjectResolver.Create;
  try
    Result:= Installed.ResolveLibraryPaths;
  finally
    Installed.Free;
  end;
  for var Root: string in Own do
    if IsUnderAnyRoot(Root, [FBDS]) or ContainsText(Root, STUDIO_OWNED_FOLDER) then Result:= Result + [Root];
end;

function TProjectResolver.MembershipLibraryRoots: TArray<string>;
var
  Installed: TProjectResolver;
begin
  Result:= ResolveLibraryPaths;
  if SameText(FStudio, DEFAULT_BDS_KEY) then Exit;
  Installed:= TProjectResolver.Create;
  try
    Result:= Result + Installed.ResolveLibraryPaths;
  finally
    Installed.Free;
  end;
end;

function TProjectResolver.ClosureSearchTail(const APlatform: string): TArray<string>;
var
  List    : TList<string> ;
  Excluded: TArray<string>;
begin
  Result:= nil;
  if SameText(FStudio, DEFAULT_BDS_KEY) then Exit;
  Excluded:= ClosureLibraryRoots;
  List:= TList<string>.Create;
  try
    ReadLibraryPaths(List, [APlatform], True);
    for var Root: string in List do
      if not IsUnderAnyRoot(Root, Excluded) then Result:= Result + [Root];
  finally
    List.Free;
  end;
end;

constructor TProjectResolver.Create;
begin
  inherited Create;
  { TryRoot, not Root: constructing a resolver must not raise. This class is
    built on every project-scoped verb, and $(BDS) is one macro among many --
    a machine without Studio can still resolve a .dproj's own folders. When it
    does not resolve, FBDS stays EMPTY so $(BDS) expands to nothing and the
    resulting path fails the existence checks downstream, rather than pointing
    at a Studio that is not there. }
  FStudio:= DEFAULT_BDS_KEY;
  { A fixture replaces the whole tree, this key's RootDir included. }
  FBDS:= if BdsRegistryFixturePath <> '' then ExcludeTrailingPathDelimiter(Trim(ActiveBdsRegistry.RootDir(DEFAULT_BDS_KEY)))
         else TStudioEnv.RootOrEmpty;
  FCurrentPlatform:= 'Win64';
  FEnvVars:= TDictionary<string, string>.Create;
  FEnvVarsLoaded:= False;
end;

destructor TProjectResolver.Destroy;
begin
  FEnvVars.Free;
  inherited Destroy;
end;

/// <summary>Lazily loads the RAD Studio user-defined "Environment Variables"
/// (Tools > Options > Environment Variables; e.g. DXVCL) from the BDS registry
/// into FEnvVars, so that arbitrary $(NAME) path macros resolve. Idempotent:
/// the registry is read at most once per resolver instance.</summary>
/// <remarks>Names are stored upper-cased for case-insensitive lookup. Only the
/// key names are captured here; VALUES may themselves contain macros (including
/// nested $(NAME)), which ResolveNamedMacro leaves to a subsequent ExpandMacros
/// pass on the returned path.</remarks>
procedure TProjectResolver.EnsureEnvVarsLoaded;
begin
  if FEnvVarsLoaded then Exit;
  FEnvVarsLoaded:= True; // set first: a failed read must not retry every path
  for var Pair: TPair<string, string> in ActiveBdsRegistry.EnvironmentVariables(FStudio) do
    FEnvVars.AddOrSetValue(UpperCase(Pair.Key.Trim), Pair.Value);
end;

/// <summary>Resolves a single macro NAME (the text inside a $(...)), trying the
/// RAD Studio user "Environment Variables" first, then the process environment.
/// Returns True and the value on a hit; False if the name is unknown.</summary>
function TProjectResolver.ResolveNamedMacro(const AName: string; out AValue: string): Boolean;
begin
  EnsureEnvVarsLoaded;
  if FEnvVars.TryGetValue(UpperCase(AName.Trim), AValue) then Exit(True);
  AValue:= GetEnvironmentVariable(AName.Trim);
  Result:= AValue <> '';
end;

/// <summary>Expands RAD Studio path macros in APath. The four most common
/// build macros ($(BDS), $(BDSCOMMONDIR), $(Platform), $(Config)) are handled
/// directly; any REMAINING $(NAME) tokens are resolved against the user-defined
/// "Environment Variables" registry key and the process environment (this is
/// how $(DXVCL) and other vendor macros expand). Unresolvable macros are left
/// verbatim, so a bad path is dropped by AddFolderIfReal rather than silently
/// pointing at the wrong folder.</summary>
/// <remarks>The named-macro sweep is bounded (max 8 iterations) so a macro whose
/// value references itself cannot loop forever.</remarks>
function TProjectResolver.ExpandMacros(const APath: string): string;
const
  MAX_PASSES = 8;
var
  Rx      : TRegEx      ;
  Matches : TMatchCollection;
  M       : TMatch      ;
  Name    : string      ;
  Val     : string      ;
  Changed : Boolean     ;
  Pass    : Integer     ;
begin
  Result:= APath;
  Result:= StringReplace(Result, '$(BDS)', FBDS, [rfReplaceAll, rfIgnoreCase]);
  Result:= StringReplace(Result, '$(BDSCOMMONDIR)', TPath.Combine(FBDS, '..\Studio\Public\Documents'), [rfReplaceAll, rfIgnoreCase]);
  Result:= StringReplace(Result, '$(Platform)', FCurrentPlatform, [rfReplaceAll, rfIgnoreCase]);
  Result:= StringReplace(Result, '$(Config)'  , 'Debug'         , [rfReplaceAll, rfIgnoreCase]);

  // Resolve any remaining $(NAME) via the RAD Studio user Environment Variables
  // and the process environment (e.g. $(DXVCL) -> C:\...\DevExpress\VCL). A
  // resolved value may itself contain macros, so loop until stable (bounded).
  // TMatchEvaluator is 'of object' (not an anonymous method), so instead of
  // TRegEx.Replace-with-evaluator we enumerate the distinct $(NAME) tokens and
  // StringReplace each one.
  Rx:= TRegEx.Create('\$\(([A-Za-z_][A-Za-z0-9_]*)\)');
  Pass:= 0;
  repeat
    Changed:= False;
    Inc(Pass);
    if Pos('$(', Result) = 0 then Break;
    Matches:= Rx.Matches(Result);
    for M in Matches do
    begin
      Name:= M.Groups[1].Value;
      if ResolveNamedMacro(Name, Val) then
      begin
        Result:= StringReplace(Result, M.Value, Val, [rfReplaceAll, rfIgnoreCase]);
        Changed:= True;
      end;
      // unknown macro -> leave verbatim; AddFolderIfReal then drops the path
    end;
  until (not Changed) or (Pass >= MAX_PASSES);
end;

procedure TProjectResolver.AddFolderIfReal(AList: TList<string>; const APath: string);
var
  Normalized: string;
begin
  if APath.Trim = '' then Exit;
  Normalized:= ExpandMacros(APath.Trim);
  try
    Normalized:= TPath.GetFullPath(Normalized);
  except
    Exit;
  end;
  if not TDirectory.Exists(Normalized) then Exit;
  // Case-insensitive dedup.
  for var Existing in AList do
    if SameText(Existing, Normalized) then Exit;
  AList.Add(Normalized);
end; // procedure

procedure TProjectResolver.AddSemicolonList(AList: TList<string>; const ASemicolonList, ABaseDir: string);
var
  Parts   : TArray<string>;
  P       : string        ;
  Resolved: string        ;
begin
  if ASemicolonList.Trim = '' then Exit;
  Parts:= ASemicolonList.Split([';']);
  for P in Parts do
  begin
    if P.Trim = '' then Continue;
    Resolved:= ExpandMacros(P.Trim);
    if not TPath.IsPathRooted(Resolved) then Resolved:= TPath.Combine(ABaseDir, Resolved);
    AddFolderIfReal(AList, Resolved);
  end;
end;

// Enumerates every platform subkey under this Studio's Library across both
// hives and registry views, deduplicated case-insensitively. These are the
// names Delphi itself registers (Win32, Win64, Android64, iOSDevice64, ...).
function TProjectResolver.EnumLibraryPlatforms: TArray<string>;
var
  List: TList<string>;

  procedure AddUnique(const AName: string);
  begin
    if AName.Trim = '' then Exit;
    for var Existing in List do
      if SameText(Existing, AName) then Exit;
    List.Add(AName);
  end;

begin
  List:= TList<string>.Create;
  try
    for var Name: string in ActiveBdsRegistry.LibraryPlatforms(FStudio) do AddUnique(Name);
    Result:= List.ToArray;
  finally
    List.Free;
  end; // try
end; // begin

procedure TProjectResolver.ReadLibraryPaths(AList: TList<string>; const APlatforms: TArray<string>);
begin
  { FALSE, i.e. BOTH paths -- this overload must stay byte-identical in
    behaviour to what it was, because its three callers are INDEXING callers.
    Narrowing them to the Search Path would silently shrink what gets indexed,
    and a smaller index answers confidently rather than failing. Only the
    COMPILE path opts out, via ResolveCompilePaths. }
  ReadLibraryPaths(AList, APlatforms, False);
end;

{ ASearchPathOnly=True omits the Browsing Path, and that distinction is the
  whole of a 2026-09-11 performance bug.

  The IDE COMPILES against the Search Path; the Browsing Path exists so Ctrl+Click
  can find declarations, and it is source-heavy by design. Feeding both to dcc put
  C:\Projects\spring4d\Source\Base\Collections at -U position 8 while
  spring4d\Library\Delphi13\Win64\Debug sat at 110 -- so dcc compiled Spring4D
  from source and died on its includes. Measured on this box: the Win64 Search
  Path has 98 entries and orders every DCU dir ahead of its Source dir already;
  the Browsing Path adds 135 more, and that is where the disorder comes from.

  Indexing callers must keep BOTH -- a browsing-only root is still code the user
  can open and therefore code the index should know. So Resolve is unchanged and
  only the COMPILE path opts out. }
procedure TProjectResolver.ReadLibraryPaths(AList: TList<string>;
  const APlatforms: TArray<string>; ASearchPathOnly: Boolean);
const
  VALUE_NAMES: array[0..1] of string = ('Search Path', 'Browsing Path');
var
  Plat    : string      ;
  Last    : Integer     ;
  Registry: IBdsRegistry;
begin
  Last:= if ASearchPathOnly then 0 else High(VALUE_NAMES);
  Registry:= ActiveBdsRegistry;
  // The real registry probes HKCU + HKLM, both 32-bit + 64-bit views.
  for Plat in APlatforms do
  begin
    FCurrentPlatform:= Plat; // so $(Platform) expands to this target
    for var VIdx: Integer:= 0 to Last do
      for var RawList: string in Registry.LibraryPathValues(FStudio, Plat, VALUE_NAMES[VIdx]) do
        AddSemicolonList(AList, RawList, '');
  end;
  FCurrentPlatform:= 'Win64'; // back to default for any later expansion
end;

procedure TProjectResolver.ReadDProj(const ADprojPath: string; AList: TList<string>);
const
  // Tag names whose text content is a semicolon-separated path list.
  PATH_TAGS: array[0..3] of string = ( 'DCC_UnitSearchPath', 'DCC_UnitAliases', 'DCC_ObjPath', 'DCC_DcuOutput' );
var
  Content: string          ;
  Tag    : string          ;
  Pattern: string          ;
  Text   : string          ;
  BaseDir: string          ;
  Matches: TMatchCollection;
  M      : TMatch          ;
begin
  BaseDir:= TPath.GetDirectoryName(ADprojPath);
  AddFolderIfReal(AList, BaseDir);

  // Skip XML DOM (MSXML COM init is not present in many Delphi installs).
  // We only need a few specific tags - plain regex over the file text.
  Content:= TFile.ReadAllText(ADprojPath, TEncoding.UTF8);
  for Tag in PATH_TAGS do
  begin
    Pattern:= Format('<%s>(.*?)</%s>', [Tag, Tag]);
    Matches:= TRegEx.Matches(Content, Pattern, [roIgnoreCase, roSingleLine]);
    for M in Matches do
    begin
      Text:= M.Groups[1].Value;
      AddSemicolonList(AList, Text, BaseDir);
    end;
  end;
end; // procedure

procedure TProjectResolver.ReadDprUsesPaths(const ADprPath: string; AList: TList<string>);
var
  Content: string;
  BaseDir: string;
  // Quick-and-dirty: find every `in '...'` literal, strip quotes, resolve.
  P       : Integer;
  EndQ    : Integer;
  StartQ  : Integer;
  Quoted  : string ;
  Resolved: string ;
  FolderOf: string ;
begin
  if not TFile.Exists(ADprPath) then Exit;
  BaseDir:= TPath.GetDirectoryName(ADprPath);
  Content:= TFile.ReadAllText     (ADprPath);
  P:= 1;
  while True do
  begin
    P:= Pos(' in ''', Content, P);
    if P = 0 then Break;
    StartQ:= P + 4; // points to opening quote
    EndQ:= PosEx('''', Content, StartQ + 1);
    if EndQ = 0 then Break;
    Quoted:= Copy(Content, StartQ + 1, EndQ - StartQ - 1);
    Resolved:= Quoted;
    if not TPath.IsPathRooted(Resolved) then Resolved:= TPath.Combine(BaseDir, Resolved);
    FolderOf:= TPath.GetDirectoryName(Resolved);
    AddFolderIfReal(AList, FolderOf);
    P:= EndQ + 1;
  end;
end; // procedure

function TProjectResolver.ResolveLibraryPaths(AAllPlatforms: Boolean): TArray<string>;
var
  List     : TList<string> ;
  Platforms: TArray<string>;
begin
  if AAllPlatforms then
  begin
    Platforms:= EnumLibraryPlatforms;
    if Length(Platforms) = 0 then Platforms:= ['Win32', 'Win64']; // fallback if enumeration found nothing
  end
  else Platforms:= ['Win32', 'Win64'];

  List:= TList<string>.Create;
  try
    ReadLibraryPaths(List, Platforms);
    Result:= List.ToArray;
  finally
    List.Free;
  end;
end; // function

function TProjectResolver.EnumRegistryPlatforms: TArray<string>;
begin
  Result:= EnumLibraryPlatforms;
  if Length(Result) = 0 then Result:= ['Win32', 'Win64'];
end;

function TProjectResolver.ReadPlatformLibraryPaths(const APlatform: string): TArray<string>;
var
  List: TList<string>;
begin
  List:= TList<string>.Create;
  try
    ReadLibraryPaths(List, [APlatform]);
    Result:= List.ToArray;
  finally
    List.Free;
  end;
end;

// The project's OWN folders, shared by Resolve and ResolveProjectOnly: the
// .dproj search paths plus the directories named by the main source's
// `in '...'` clauses. Deliberately contains no registry lookup -- that tail is
// what separates a compiler search path from an indexing scope, and it is added
// by Resolve alone.
procedure TProjectResolver.CollectProjectFolders(const ADprojPath: string; AList: TList<string>);
var
  DprPath   : string;
  MainSource: string;
begin
  if not TFile.Exists(ADprojPath) then raise Exception.CreateFmt('.dproj not found: %s', [ADprojPath]);

  ReadDProj(ADprojPath, AList);

  // Try to find the matching .dpr (same basename) next to the .dproj
  MainSource:= TPath.ChangeExtension(ADprojPath, '.dpr');
  if TFile.Exists(MainSource) then DprPath:= MainSource
  else
  begin
    // Sometimes the .dpk has the uses list (packages)
    MainSource:= TPath.ChangeExtension(ADprojPath, '.dpk');
    if TFile.Exists(MainSource) then DprPath:= MainSource
    else DprPath:= '';
  end;
  if DprPath <> '' then ReadDprUsesPaths(DprPath, AList);
end; // procedure

{ See the declaration. Project folders first, then the TARGET platform's Search
  Path in registry order -- which already puts every DCU dir ahead of its Source
  dir on this box, so no reordering and no directory listing is needed. }
function TProjectResolver.ResolveCompilePaths(const ADprojPath, APlatform: string): TArray<string>;
var
  List: TList<string>;
begin
  List:= TList<string>.Create;
  try
    CollectProjectFolders(ADprojPath, List);
    ReadLibraryPaths(List, [APlatform], True);
    Result:= List.ToArray;
  finally
    List.Free;
  end;
end;
function TProjectResolver.Resolve(const ADprojPath: string): TArray<string>;
var
  List: TList<string>;
begin
  List:= TList<string>.Create;
  try
    CollectProjectFolders(ADprojPath, List);
    ReadLibraryPaths(List, ['Win32', 'Win64']);
    Result:= List.ToArray;
  finally
    List.Free;
  end; // try
end; // function

function TProjectResolver.ResolveProjectOnly(const ADprojPath: string): TArray<string>;
var
  List: TList<string>;
begin
  List:= TList<string>.Create;
  try
    CollectProjectFolders(ADprojPath, List);
    Result:= List.ToArray;
  finally
    List.Free;
  end; // try
end; // function

end.
