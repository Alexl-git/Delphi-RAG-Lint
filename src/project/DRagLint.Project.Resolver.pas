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

type
  // Resolves the set of folders that should be scanned for a Delphi project.
  // Inputs: a .dproj path. Outputs: deduplicated folder list combining:
  //   - the .dproj's own folder
  //   - DCC_UnitSearchPath entries from the .dproj
  //   - Library and Browsing paths from registry (Win32 + Win64, HKCU + HKLM)
  //   - folders containing each unit listed in the .dpr's `uses X in 'path'`
  //     clauses (one level deep)
  // All $(BDS) and similar macros are expanded.
  /// <summary><!-- drag-lint:auto -->Resolves the set of folders that should be scanned
  /// for a Delphi project. Inputs: a .dproj path. Outputs: deduplicated folder list
  /// combining: - the .dproj's own folder - DCC_UnitSearchPath entries from the .dproj -
  /// Library and Browsing paths from registry (Win32 + Win64, HKCU + HKLM) - folders
  /// containing each unit listed in the .dpr's `uses X in 'path'` clauses (one level
  /// deep) All $(BDS) and similar macros are expanded.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.CLI.BuildPlanItem (DRagLint.CLI.pas), DRagLint.CLI.DoIndexAll (DRagLint.CLI.pas), DRagLint.CLI.DoIndex (DRagLint.CLI.pas), DRagLint.CLI.DoScanAll (DRagLint.CLI.pas), DRagLint.CLI.BuildProjectFileScope (DRagLint.CLI.pas) (+16 more)</para>
  /// <para>Used in units: DRagLint.CLI, DRagLint.Doc.Batch, DRagLint.Index.Coverage, DRagLint.Index.DbSelect, DRagLint.Index.Plan</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TProjectResolver = class
    strict private
      FBDS            : string                          ;
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
      /// <para>Called from: DRagLint.Project.Resolver.TProjectResolver.ReadDProj (DRagLint.Project.Resolver.pas), DRagLint.Project.Resolver.TProjectResolver.ReadLibraryPaths (DRagLint.Project.Resolver.pas)</para>
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
      /// <summary><!-- drag-lint:auto -->Enumerates every platform subkey under
      /// ...\BDS\37.0\Library across both hives and registry views, deduplicated
      /// case-insensitively. These are the names Delphi itself registers (Win32, Win64,
      /// Android64, iOSDevice64, ...).</summary>
      /// <returns><!-- drag-lint:auto -->TArray&lt;string&gt; -- Observed: List.ToArray.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
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
      /// <para>Calls: DRagLint.Project.Resolver.ReadRegPathInto, DRagLint.Project.Resolver.TProjectResolver.AddSemicolonList, HKEY</para>
      /// <para>Writes: FCurrentPlatform</para>
      /// <seealso cref="DRagLint.Project.Resolver.ReadRegPathInto"/>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.AddSemicolonList"/>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.AddFolderIfReal"/>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.CollectProjectFolders"/>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.Create"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure ReadLibraryPaths(AList: TList<string>; const APlatforms: TArray<string>);
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
      /// <summary><!-- drag-lint:auto -->The project's OWN folders, shared by Resolve and
      /// ResolveProjectOnly: the .dproj search paths plus the directories named by the
      /// main source's `in '...'` clauses. Deliberately contains no registry lookup --
      /// that tail is what separates a compiler search path from an indexing scope, and
      /// it is added by Resolve alone.</summary>
      /// <param name="ADprojPath"><!-- drag-lint:auto type -->const string</param>
      /// <param name="AList"><!-- drag-lint:auto type -->TList&lt;string&gt;</param>
      /// <exception cref="Exception"><!-- drag-lint:auto --></exception>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.Project.Resolver.TProjectResolver.Resolve (DRagLint.Project.Resolver.pas), DRagLint.Project.Resolver.TProjectResolver.ResolveProjectOnly (DRagLint.Project.Resolver.pas)</para>
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
      /// <para>Called from: DRagLint.Doc.Batch.TDocBatch.DocumentProject (DRagLint.Doc.Batch.pas)</para>
      /// <para>Calls: GetEnvironmentVariable</para>
      /// <para>constructor</para>
      /// <para>Reads: FBDS   Writes: FBDS, FCurrentPlatform, FEnvVars, FEnvVarsLoaded</para>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.AddFolderIfReal"/>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.AddSemicolonList"/>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.CollectProjectFolders"/>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.Destroy"/>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.EnsureEnvVarsLoaded"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      constructor Create;
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Reads: FEnvVars</para>
      /// <para>Pure</para>
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
      /// <para>Called from: DRagLint.CLI.CompileUnitInContext (DRagLint.CLI.pas), DRagLint.CLI.DoCheckUnit (DRagLint.CLI.pas), DRagLint.CLI.DoIndex (DRagLint.CLI.pas) ?</para>
      /// <para>Calls: DRagLint.Project.Resolver.TProjectResolver.CollectProjectFolders, DRagLint.Project.Resolver.TProjectResolver.ReadLibraryPaths</para>
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
      /// <summary><!-- drag-lint:auto -->Library/Browsing paths from registry only - no
      /// .dproj required. Useful for "index everything Delphi knows about" without a
      /// project. AAllPlatforms = False -&gt; Win32 + Win64 only (the IDE's native
      /// targets). AAllPlatforms = True -&gt; every platform subkey under
      /// ...\BDS\37.0\Library (Android*, iOS*, Linux64, OSX*, Win64x, ...), which
      /// additionally pulls in the Posix / Androidapi / iOSapi / Macapi platform source
      /// trees.</summary>
      /// <param name="AAllPlatforms"><!-- drag-lint:auto type -->Boolean = False</param>
      /// <returns><!-- drag-lint:auto -->TArray&lt;string&gt; -- Observed: List.ToArray.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.CLI.BuildPlanItem (DRagLint.CLI.pas), DRagLint.CLI.BuildProjectFileScope (DRagLint.CLI.pas), DRagLint.CLI.CompileUnitInContext (DRagLint.CLI.pas), DRagLint.CLI.DoCheckUnit (DRagLint.CLI.pas), DRagLint.CLI.DoIndex (DRagLint.CLI.pas) (+4 more)</para>
      /// <para>Calls: DRagLint.Project.Resolver.TProjectResolver.ReadLibraryPaths</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.ReadLibraryPaths"/>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.AddFolderIfReal"/>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.AddSemicolonList"/>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.CollectProjectFolders"/>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.Create"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function ResolveLibraryPaths(AAllPlatforms: Boolean = False): TArray<string>;
      /// <summary>Returns every platform name registered under BDS\37.0\Library,
      /// deduplicated case-insensitively. Wraps the private EnumLibraryPlatforms.
      /// Returns at least ['Win32','Win64'] as a fallback when the registry is empty.</summary>
      /// <returns>Array of platform names (e.g. Win32, Win64, Android64).</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.Index.Plan.ResolvePlan (DRagLint.Index.Plan.pas)</para>
      /// <para>Returns: EnumLibraryPlatforms; ['Win32', 'Win64']</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.AddFolderIfReal"/>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.AddSemicolonList"/>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.CollectProjectFolders"/>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.Create"/>
      /// <seealso cref="DRagLint.Project.Resolver.TProjectResolver.Destroy"/>
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
      /// <para>Called from: DRagLint.CLI.DoLibraryDrift (DRagLint.CLI.pas), DRagLint.Index.Plan.ResolvePlan (DRagLint.Index.Plan.pas), DRagLint.Lint.ProjectChecks.TProjectChecks.CheckUsedUnitResolvable.EnsureDcuStems (DRagLint.Lint.ProjectChecks.pas) ?</para>
      /// <para>Calls: DRagLint.Project.Resolver.TProjectResolver.ReadLibraryPaths</para>
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
  end;

implementation

const
  BDS_REG_PATH = '\Software\Embarcadero\BDS\37.0';

constructor TProjectResolver.Create;
begin
  inherited Create;
  { TryRoot, not Root: constructing a resolver must not raise. This class is
    built on every project-scoped verb, and $(BDS) is one macro among many --
    a machine without Studio can still resolve a .dproj's own folders. When it
    does not resolve, FBDS stays EMPTY so $(BDS) expands to nothing and the
    resulting path fails the existence checks downstream, rather than pointing
    at a Studio that is not there. }
  FBDS:= TStudioEnv.RootOrEmpty;
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
var
  Reg  : TRegistry  ;
  Names: TStringList;
  Name : string     ;
begin
  if FEnvVarsLoaded then Exit;
  FEnvVarsLoaded:= True; // set first: a failed read must not retry every path
  Names:= TStringList.Create;
  Reg:= TRegistry.Create(KEY_READ);
  try
    Reg.RootKey:= HKEY_CURRENT_USER;
    if Reg.OpenKeyReadOnly(BDS_REG_PATH + '\Environment Variables') then
    try
      Reg.GetValueNames(Names);
      for Name in Names do
        if (Name.Trim <> '') and Reg.ValueExists(Name) then
          FEnvVars.AddOrSetValue(UpperCase(Name.Trim), Reg.ReadString(Name));
    finally
      Reg.CloseKey;
    end;
  finally
    Reg.Free;
    Names.Free;
  end;
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

procedure ReadRegPathInto(const ARoot: HKEY; const AKey, AValue: string; ASamDesired: Cardinal; const AAdd: TProc<string>);
var
  Reg     : TRegistry;
  RegValue: string   ;
begin
  Reg:= TRegistry.Create(KEY_READ or ASamDesired);
  try
    Reg.RootKey:= ARoot;
    if Reg.OpenKeyReadOnly(AKey) then
    try
      if Reg.ValueExists(AValue) then
      begin
        RegValue:= Reg.ReadString(AValue);
        AAdd(RegValue);
      end;
    finally
      Reg.CloseKey;
    end;
  finally
    Reg.Free;
  end;
end; // procedure

// Enumerates every platform subkey under ...\BDS\37.0\Library across both
// hives and registry views, deduplicated case-insensitively. These are the
// names Delphi itself registers (Win32, Win64, Android64, iOSDevice64, ...).
function TProjectResolver.EnumLibraryPlatforms: TArray<string>;
var
  List    : TList<string>;
  Names   : TStringList  ;
  Reg     : TRegistry    ;
  HiveRoot: HKEY         ;
  Sam     : Cardinal     ;
  Name    : string       ;

  procedure AddUnique(const AName: string);
  begin
    if AName.Trim = '' then Exit;
    for var Existing in List do
      if SameText(Existing, AName) then Exit;
    List.Add(AName);
  end;

begin
  List:= TList<string>.Create;
  Names:= TStringList.Create;
  try
    for HiveRoot in [HKEY(HKEY_CURRENT_USER), HKEY(HKEY_LOCAL_MACHINE)] do
      for Sam in [KEY_WOW64_32KEY, KEY_WOW64_64KEY] do
      begin
        Reg:= TRegistry.Create(KEY_READ or Sam);
        try
          Reg.RootKey:= HiveRoot;
          if Reg.OpenKeyReadOnly(BDS_REG_PATH + '\Library') then
          try
            Names.Clear;
            Reg.GetKeyNames(Names);
            for Name in Names do AddUnique(Name);
          finally
            Reg.CloseKey;
          end;
        finally
          Reg.Free;
        end;
      end; // for
    Result:= List.ToArray;
  finally
    Names.Free;
    List.Free;
  end; // try
end; // begin

procedure TProjectResolver.ReadLibraryPaths(AList: TList<string>; const APlatforms: TArray<string>);
const
  VALUE_NAMES: array[0..1] of string = ('Search Path', 'Browsing Path');
var
  Plat    : string  ;
  Val     : string  ;
  HiveRoot: HKEY    ;
  Sam     : Cardinal;
  RegBase : string  ;
begin
  // Probe HKCU + HKLM, both 32-bit + 64-bit registry views.
  for Plat in APlatforms do
  begin
    FCurrentPlatform:= Plat; // so $(Platform) expands to this target
    for Val in VALUE_NAMES do
    begin
      RegBase:= BDS_REG_PATH + '\Library\' + Plat;
      for HiveRoot in [HKEY(HKEY_CURRENT_USER), HKEY(HKEY_LOCAL_MACHINE)] do
        for Sam in [KEY_WOW64_32KEY, KEY_WOW64_64KEY] do ReadRegPathInto(HiveRoot, RegBase, Val, Sam, procedure (S: string) begin AddSemicolonList(AList, S, ''); end);
    end;
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
