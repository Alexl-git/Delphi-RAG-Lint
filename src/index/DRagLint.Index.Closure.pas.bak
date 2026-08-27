unit DRagLint.Index.Closure;

// Compile-closure resolver: given a .dpr/.dproj, returns the set of
// project-local source files that would actually be compiled -- the member
// units, every unit they pull in transitively via `uses` that resolves to a
// project-local file (NOT under a Delphi Library/Browsing path), plus any
// {$I}/{$INCLUDE} include files encountered along the way.
//
// Loose files sitting in the project folders that nothing references are
// NOT included in the closure.  If an `exclude` glob matches a file that IS
// reached via `uses`, the file is still included in Files but a Warning is
// emitted naming the using unit.
//
// Parsing limitation: `uses` extraction is a pragmatic text scan (regex,
// word-boundary, skip inside block comments/string literals as best-effort).
// It handles dotted unit names (System.SysUtils) but treats them as unresolved
// when no matching file is found on the search path.  Conditional compilation
// ({$IFDEF}) is NOT evaluated -- all branches are scanned, so units mentioned
// in the inactive branch may be enqueued but will simply not resolve to a
// project-local file and will be skipped.

interface

uses
  System.SysUtils
  , System.Classes
  , System.IOUtils
  , System.Generics.Collections
  , System.RegularExpressions
  , DRagLint.Preprocess.Types
  ;

type
  /// <summary>Holds the result of a compile-closure walk.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.CLI.BuildPlanItem (DRagLint.CLI.pas), DRagLint.CLI.DoIndex (DRagLint.CLI.pas), DRagLint.CLI.BuildProjectFileScope (DRagLint.CLI.pas), DRagLint.CLI.DoSelfTestClosure (DRagLint.CLI.pas), DRagLint.Doc.Batch.TDocBatch.DocumentProject (DRagLint.Doc.Batch.pas) (+3 more)</para>
  /// <para>Used in units: DRagLint.CLI, DRagLint.Doc.Batch, DRagLint.Index.Closure, DRagLint.Index.Reconcile</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TClosureResult = record
    /// <summary>Absolute .pas/.inc paths in the project-local closure, deduped.</summary>
    Files: TArray<string>;
    /// <summary>Human-readable warnings, e.g. excluded-but-in-closure messages.</summary>
    Warnings: TArray<string>;
    /// <summary>The unit name that pulled each Files[i] into the closure.
    /// Parallel to Files: UsedBy[i] is the using-unit for Files[i].
    /// '&lt;project&gt;' for entries seeded directly from the .dpr/.dproj member list.
    /// Existing callers need not change -- they simply ignore this field.</summary>
    UsedBy: TArray<string>;
  end;

  /// <summary>Resolves the compile closure of a Delphi .dpr or .dproj project.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.CLI.BuildPlanItem (DRagLint.CLI.pas), DRagLint.CLI.DoIndex (DRagLint.CLI.pas), DRagLint.CLI.BuildProjectFileScope (DRagLint.CLI.pas), DRagLint.CLI.DoSelfTestClosure (DRagLint.CLI.pas), DRagLint.Doc.Batch.TDocBatch.DocumentProject (DRagLint.Doc.Batch.pas) (+1 more)</para>
  /// <para>Used in units: DRagLint.CLI, DRagLint.Doc.Batch, DRagLint.Index.Reconcile</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TClosureResolver = class
    strict private
      FLibraryRoots: TArray<string>;

      // PP-Task-10: per-config file discovery. When FPreprocessEnabled, source
      // content is run through the in-process directive preprocessor under
      // FProfile BEFORE its `uses` clause is scanned, so a unit `uses`d only
      // under an inactive branch is blanked to spaces and never discovered.
      // FPreprocessFellBack latches the one-shot fallback log (a per-file
      // preprocess exception falls back to the raw content for that file).
      FPreprocessEnabled : Boolean;
      FProfile           : TDefineProfile;
      FPreprocessFellBack: Boolean;

      // Run the directive preprocessor over AContent under FProfile when
      // FPreprocessEnabled, returning the resolved text (inactive-branch bytes
      // blanked to spaces, offsets 1:1). When disabled -- or on a per-file
      // preprocess exception (logged once) -- returns AContent unchanged so the
      // caller falls back to the old all-branch scan for that file.
      /// <summary><!-- drag-lint:auto -->Run the directive preprocessor over AContent
      /// under FProfile when FPreprocessEnabled, returning the resolved text
      /// (inactive-branch bytes blanked to spaces, offsets 1:1). When disabled -- or on a
      /// per-file preprocess exception (logged once) -- returns AContent unchanged so the
      /// caller falls back to the old all-branch scan for that file.</summary>
      /// <param name="AContent"><!-- drag-lint:auto type -->const string</param>
      /// <param name="AFileLabel"><!-- drag-lint:auto type -->const string</param>
      /// <returns><!-- drag-lint:auto -->string -- Observed:
      /// TEncoding.UTF8.GetString(Resolved); AContent.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.Index.Closure.TClosureResolver.Resolve (DRagLint.Index.Closure.pas)</para>
      /// <para>Calls: DRagLint.Core.Encoding.EnsureUtf8Bytes, DRagLint.Preprocess.Preprocess/2, Format, Writeln</para>
      /// <para>Reads: FPreprocessEnabled, FProfile, FPreprocessFellBack   Writes: FPreprocessFellBack</para>
      /// <seealso cref="DRagLint.Core.Encoding.EnsureUtf8Bytes"/>
      /// <seealso cref="DRagLint.Preprocess.Preprocess"/>
      /// <seealso cref="DRagLint.Index.Closure.TClosureResolver.Create"/>
      /// <seealso cref="DRagLint.Index.Closure.TClosureResolver.ExtractIncludes"/>
      /// <seealso cref="DRagLint.Index.Closure.TClosureResolver.ExtractUses"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function MaybePreprocess(const AContent, AFileLabel: string): string;

      // ---- unit-file resolution helpers ----------------------------------------

      // Return True if AFile is rooted under any library root (case-insensitive).
      /// <summary><!-- drag-lint:auto -->Return True if AFile is rooted under any library
      /// root (case-insensitive).</summary>
      /// <param name="AFile"><!-- drag-lint:auto type -->const string</param>
      /// <returns><!-- drag-lint:auto -->Boolean -- Observed: False.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.Index.Closure.TClosureResolver.Resolve (DRagLint.Index.Closure.pas)</para>
      /// <para>Calls: LowerCase, StringReplace</para>
      /// <para>Reads: FLibraryRoots</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Index.Closure.TClosureResolver.Create"/>
      /// <seealso cref="DRagLint.Index.Closure.TClosureResolver.ExtractIncludes"/>
      /// <seealso cref="DRagLint.Index.Closure.TClosureResolver.ExtractUses"/>
      /// <seealso cref="DRagLint.Index.Closure.TClosureResolver.FindIncFile"/>
      /// <seealso cref="DRagLint.Index.Closure.TClosureResolver.FindUnitFile"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function IsLibraryFile(const AFile: string): Boolean;

      // Search ASearchPaths for <AUnitName>.pas (case-insensitive first-file-wins).
      // Returns the full absolute path, or '' if not found.
      /// <summary><!-- drag-lint:auto -->Search ASearchPaths for &lt;AUnitName&gt;.pas
      /// (case-insensitive first-file-wins). Returns the full absolute path, or '' if not
      /// found.</summary>
      /// <param name="AUnitName"><!-- drag-lint:auto type -->const string</param>
      /// <param name="ASearchPaths"><!-- drag-lint:auto type -->const TArray&lt;string&gt;</param>
      /// <returns><!-- drag-lint:auto -->string -- Observed: ''.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.Index.Closure.TClosureResolver.Resolve (DRagLint.Index.Closure.pas)</para>
      /// <para>Touches: file system</para>
      /// <seealso cref="DRagLint.Index.Closure.TClosureResolver.Create"/>
      /// <seealso cref="DRagLint.Index.Closure.TClosureResolver.ExtractIncludes"/>
      /// <seealso cref="DRagLint.Index.Closure.TClosureResolver.ExtractUses"/>
      /// <seealso cref="DRagLint.Index.Closure.TClosureResolver.FindIncFile"/>
      /// <seealso cref="DRagLint.Index.Closure.TClosureResolver.IsLibraryFile"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function FindUnitFile(const AUnitName: string; const ASearchPaths: TArray<string>): string;

      // Search ASearchPaths + the dir of AFromFile for AIncName (as-given, then
      // relative to each search path).  Returns absolute path or ''.
      /// <summary><!-- drag-lint:auto -->Search ASearchPaths + the dir of AFromFile for
      /// AIncName (as-given, then relative to each search path). Returns absolute path or
      /// ''.</summary>
      /// <param name="AIncName"><!-- drag-lint:auto type -->const string</param>
      /// <param name="AFromDir"><!-- drag-lint:auto type -->const string</param>
      /// <param name="ASearchPaths"><!-- drag-lint:auto type -->const TArray&lt;string&gt;</param>
      /// <returns><!-- drag-lint:auto -->string -- Observed: ''.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.Index.Closure.TClosureResolver.Resolve (DRagLint.Index.Closure.pas)</para>
      /// <para>Touches: file system</para>
      /// <seealso cref="DRagLint.Index.Closure.TClosureResolver.Create"/>
      /// <seealso cref="DRagLint.Index.Closure.TClosureResolver.ExtractIncludes"/>
      /// <seealso cref="DRagLint.Index.Closure.TClosureResolver.ExtractUses"/>
      /// <seealso cref="DRagLint.Index.Closure.TClosureResolver.FindUnitFile"/>
      /// <seealso cref="DRagLint.Index.Closure.TClosureResolver.IsLibraryFile"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function FindIncFile(const AIncName, AFromDir: string; const ASearchPaths: TArray<string>): string;

      // ---- .dpr/.dproj parsing --------------------------------------------------

      // Parse the .dpr `uses` clause: fill AUnitNames (name) + AUnitFiles
      // (the `in 'path'` specifier when given, or '' when not).
      // Both lists are parallel (same index).
      /// <summary><!-- drag-lint:auto -->Parse the .dpr `uses` clause: fill AUnitNames
      /// (name) + AUnitFiles (the `in 'path'` specifier when given, or '' when not). Both
      /// lists are parallel (same index).</summary>
      /// <param name="AContent"><!-- drag-lint:auto type -->const string</param>
      /// <param name="ABaseDir"><!-- drag-lint:auto type -->const string</param>
      /// <param name="AUnitNames"><!-- drag-lint:auto type -->TStringList</param>
      /// <param name="AUnitFiles"><!-- drag-lint:auto type -->TStringList</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.Index.Closure.TClosureResolver.Resolve (DRagLint.Index.Closure.pas)</para>
      /// <para>Calls: Copy, DRagLint.Lint.ProjectChecks.Parse.StripPasCommentsKeepLayout, Pos, SameText</para>
      /// <para>Touches: file system</para>
      /// <seealso cref="DRagLint.Lint.ProjectChecks.Parse.StripPasCommentsKeepLayout"/>
      /// <seealso cref="DRagLint.Index.Closure.TClosureResolver.Create"/>
      /// <seealso cref="DRagLint.Index.Closure.TClosureResolver.ExtractIncludes"/>
      /// <seealso cref="DRagLint.Index.Closure.TClosureResolver.ExtractUses"/>
      /// <seealso cref="DRagLint.Index.Closure.TClosureResolver.FindIncFile"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure ParseDprUses(const AContent, ABaseDir: string; AUnitNames, AUnitFiles: TStringList);

      // Return the `<DCCReference Include="...">` file paths from a .dproj.
      /// <summary><!-- drag-lint:auto -->Return the `&lt;DCCReference Include="..."&gt;`
      /// file paths from a .dproj.</summary>
      /// <param name="AContent"><!-- drag-lint:auto type -->const string</param>
      /// <param name="ABaseDir"><!-- drag-lint:auto type -->const string</param>
      /// <param name="AFiles"><!-- drag-lint:auto type -->TStringList</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.Index.Closure.TClosureResolver.Resolve (DRagLint.Index.Closure.pas)</para>
      /// <para>Touches: file system</para>
      /// <seealso cref="DRagLint.Index.Closure.TClosureResolver.Create"/>
      /// <seealso cref="DRagLint.Index.Closure.TClosureResolver.ExtractIncludes"/>
      /// <seealso cref="DRagLint.Index.Closure.TClosureResolver.ExtractUses"/>
      /// <seealso cref="DRagLint.Index.Closure.TClosureResolver.FindIncFile"/>
      /// <seealso cref="DRagLint.Index.Closure.TClosureResolver.FindUnitFile"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure ParseDprojRefs(const AContent, ABaseDir: string; AFiles: TStringList);

      // Read search paths from the .dproj's DCC_UnitSearchPath tags.
      /// <summary><!-- drag-lint:auto -->Read search paths from the .dproj's
      /// DCC_UnitSearchPath tags.</summary>
      /// <param name="AContent"><!-- drag-lint:auto type -->const string</param>
      /// <param name="ABaseDir"><!-- drag-lint:auto type -->const string</param>
      /// <param name="APaths"><!-- drag-lint:auto type -->TStringList</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.Index.Closure.TClosureResolver.Resolve (DRagLint.Index.Closure.pas)</para>
      /// <para>Calls: Pos</para>
      /// <para>Touches: file system</para>
      /// <seealso cref="DRagLint.Index.Closure.TClosureResolver.Create"/>
      /// <seealso cref="DRagLint.Index.Closure.TClosureResolver.ExtractIncludes"/>
      /// <seealso cref="DRagLint.Index.Closure.TClosureResolver.ExtractUses"/>
      /// <seealso cref="DRagLint.Index.Closure.TClosureResolver.FindIncFile"/>
      /// <seealso cref="DRagLint.Index.Closure.TClosureResolver.FindUnitFile"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure ParseDprojSearchPaths(const AContent, ABaseDir: string; APaths: TStringList);

      // ---- source text scanning ------------------------------------------------

      // Strip block comments { } and (* *) and string literals from AText so
      // that `uses`/`{$I}` scanning does not pick up identifiers inside them.
      // Does NOT strip // comments (they end at EOL, and our regex won't cross
      // lines for uses-identifiers anyway).
      /// <summary><!-- drag-lint:auto -->Strip block comments { } and (* *) and string
      /// literals from AText so that `uses`/`{$I}` scanning does not pick up identifiers
      /// inside them. Does NOT strip // comments (they end at EOL, and our regex won't
      /// cross lines for uses-identifiers anyway).</summary>
      /// <param name="AText"><!-- drag-lint:auto type -->const string</param>
      /// <returns><!-- drag-lint:auto -->string -- Observed: SB.ToString.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.Index.Closure.TClosureResolver.ExtractUses (DRagLint.Index.Closure.pas)</para>
      /// <para>Complexity: 22 (cyclomatic, outer body), 110 lines (full implementation)</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Index.Closure.TClosureResolver.Create"/>
      /// <seealso cref="DRagLint.Index.Closure.TClosureResolver.ExtractIncludes"/>
      /// <seealso cref="DRagLint.Index.Closure.TClosureResolver.ExtractUses"/>
      /// <seealso cref="DRagLint.Index.Closure.TClosureResolver.FindIncFile"/>
      /// <seealso cref="DRagLint.Index.Closure.TClosureResolver.FindUnitFile"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function StripCommentsAndStrings(const AText: string): string;

      // Scan AText for uses-clause identifiers (both interface and implementation
      // sections).  Returns a list of dotted unit names.
      /// <summary><!-- drag-lint:auto -->Scan AText for uses-clause identifiers (both
      /// interface and implementation sections). Returns a list of dotted unit names.</summary>
      /// <param name="AText"><!-- drag-lint:auto type -->const string</param>
      /// <returns><!-- drag-lint:auto -->TArray&lt;string&gt; -- Observed: List.ToArray.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.Index.Closure.TClosureResolver.Resolve (DRagLint.Index.Closure.pas)</para>
      /// <para>Calls: Copy, DRagLint.Index.Closure.TClosureResolver.StripCommentsAndStrings, SameText</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Index.Closure.TClosureResolver.StripCommentsAndStrings"/>
      /// <seealso cref="DRagLint.Index.Closure.TClosureResolver.Create"/>
      /// <seealso cref="DRagLint.Index.Closure.TClosureResolver.ExtractIncludes"/>
      /// <seealso cref="DRagLint.Index.Closure.TClosureResolver.FindIncFile"/>
      /// <seealso cref="DRagLint.Index.Closure.TClosureResolver.FindUnitFile"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function ExtractUses(const AText: string): TArray<string>;

      // Scan AText for {$I filename} / {$INCLUDE filename} directives.
      /// <summary><!-- drag-lint:auto -->Scan AText for {$I filename} / {$INCLUDE
      /// filename} directives.</summary>
      /// <param name="AText"><!-- drag-lint:auto type -->const string</param>
      /// <returns><!-- drag-lint:auto -->TArray&lt;string&gt; -- Observed: List.ToArray.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.Index.Closure.TClosureResolver.Resolve (DRagLint.Index.Closure.pas)</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Index.Closure.TClosureResolver.Create"/>
      /// <seealso cref="DRagLint.Index.Closure.TClosureResolver.ExtractUses"/>
      /// <seealso cref="DRagLint.Index.Closure.TClosureResolver.FindIncFile"/>
      /// <seealso cref="DRagLint.Index.Closure.TClosureResolver.FindUnitFile"/>
      /// <seealso cref="DRagLint.Index.Closure.TClosureResolver.IsLibraryFile"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function ExtractIncludes(const AText: string): TArray<string>;

    public
      /// <summary>Create a resolver that treats files under ALibraryRoots as library
      /// (excluded from the closure).
      /// Pass TProjectResolver.ResolveLibraryPaths as ALibraryRoots.</summary>
      /// <param name="ALibraryRoots"><!-- drag-lint:auto type -->const TArray&lt;string&gt;</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.CLI.BuildPlanItem (DRagLint.CLI.pas), DRagLint.CLI.BuildProjectFileScope (DRagLint.CLI.pas), DRagLint.CLI.DoIndex (DRagLint.CLI.pas), DRagLint.CLI.DoSelfTestClosure (DRagLint.CLI.pas), DRagLint.Doc.Batch.TDocBatch.DocumentProject (DRagLint.Doc.Batch.pas) (+1 more)</para>
      /// <para>Calls: Default</para>
      /// <para>constructor</para>
      /// <para>Writes: FLibraryRoots, FPreprocessEnabled, FProfile, FPreprocessFellBack</para>
      /// <seealso cref="DRagLint.Index.Closure.TClosureResolver.ExtractIncludes"/>
      /// <seealso cref="DRagLint.Index.Closure.TClosureResolver.ExtractUses"/>
      /// <seealso cref="DRagLint.Index.Closure.TClosureResolver.FindIncFile"/>
      /// <seealso cref="DRagLint.Index.Closure.TClosureResolver.FindUnitFile"/>
      /// <seealso cref="DRagLint.Index.Closure.TClosureResolver.IsLibraryFile"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      constructor Create(const ALibraryRoots: TArray<string>);

      /// <summary>PP-Task-10: enable/disable per-config directive preprocessing of source
      /// content before its `uses` clause is scanned. When enabled, a unit
      /// `uses`d only under an inactive {$IFDEF} branch (per AProfile) is NOT
      /// discovered/pulled into the closure. When disabled (the default), the
      /// resolver keeps the prior all-branch scan + brace-stripping unchanged.</summary>
      /// <param name="AEnabled">True runs Preprocess before every uses-scan.</param>
      /// <param name="AProfile">The active define profile (platform built-ins
      /// and/or .dproj-derived DCC_Define). Used only when AEnabled.</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.CLI.BuildPlanItem (DRagLint.CLI.pas), DRagLint.CLI.BuildProjectFileScope (DRagLint.CLI.pas), DRagLint.CLI.DoSelfTestClosure (DRagLint.CLI.pas), DRagLint.CLI.DoIndex (DRagLint.CLI.pas) ?</para>
      /// <para>Writes: FPreprocessEnabled, FProfile, FPreprocessFellBack</para>
      /// <seealso cref="DRagLint.Index.Closure.TClosureResolver.Create"/>
      /// <seealso cref="DRagLint.Index.Closure.TClosureResolver.ExtractIncludes"/>
      /// <seealso cref="DRagLint.Index.Closure.TClosureResolver.ExtractUses"/>
      /// <seealso cref="DRagLint.Index.Closure.TClosureResolver.FindIncFile"/>
      /// <seealso cref="DRagLint.Index.Closure.TClosureResolver.FindUnitFile"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      procedure SetPreprocess(AEnabled: Boolean; const AProfile: TDefineProfile);

      /// <summary>Resolve the compile closure of a .dpr or .dproj project.
      /// Returns the set of project-local .pas/.inc files that get compiled:
      /// the project member units + transitive project-local uses + {$I} files.
      /// Files under any ALibraryRoot are silently excluded and not recursed.
      /// A file that is reached via uses AND matches an AExclude glob pattern is
      /// still added to Files but also produces a Warning entry.</summary>
      /// <param name="AProjectFile">Absolute or relative path to the .dpr or .dproj.</param>
      /// <param name="AExclude">Glob patterns for "stale" files (still included in
      /// closure but warned). Pass [] for no exclusion warnings.</param>
      /// <returns>TClosureResult with deduped Files list and Warnings.</returns>
      /// <exception cref="Exception"><!-- drag-lint:auto --></exception>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.CLI.BuildPlanItem (DRagLint.CLI.pas), DRagLint.CLI.BuildProjectFileScope (DRagLint.CLI.pas), DRagLint.CLI.DoSelfTestClosure (DRagLint.CLI.pas), DRagLint.Doc.Batch.TDocBatch.DocumentProject (DRagLint.Doc.Batch.pas), DRagLint.Index.Reconcile.TProjectReconciler.Analyze (DRagLint.Index.Reconcile.pas) (+1 more)</para>
      /// <para>Calls: DRagLint.Index.Closure.TClosureResolver.ExtractIncludes, DRagLint.Index.Closure.TClosureResolver.ExtractUses, DRagLint.Index.Closure.TClosureResolver.FindIncFile, DRagLint.Index.Closure.TClosureResolver.FindUnitFile, DRagLint.Index.Closure.TClosureResolver.IsLibraryFile, DRagLint.Index.Closure.TClosureResolver.MaybePreprocess, DRagLint.Index.Closure.TClosureResolver.ParseDprojRefs, DRagLint.Index.Closure.TClosureResolver.ParseDprojSearchPaths, DRagLint.Index.Closure.TClosureResolver.ParseDprUses, DRagLint.Index.Closure.TClosureResolver.Resolve.EnqueueFile, LowerCase</para>
      /// <para>Complexity: 23 (cyclomatic, outer body), 207 lines (full implementation)</para>
      /// <para>Touches: file system</para>
      /// <seealso cref="DRagLint.Index.Closure.TClosureResolver.ExtractIncludes"/>
      /// <seealso cref="DRagLint.Index.Closure.TClosureResolver.ExtractUses"/>
      /// <seealso cref="DRagLint.Index.Closure.TClosureResolver.FindIncFile"/>
      /// <seealso cref="DRagLint.Index.Closure.TClosureResolver.FindUnitFile"/>
      /// <seealso cref="DRagLint.Index.Closure.TClosureResolver.IsLibraryFile"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function Resolve(const AProjectFile: string; const AExclude: TArray<string>): TClosureResult;
  end;

implementation

uses
  DRagLint.Index.Glob
  , DRagLint.Preprocess       // PP-Task-10: Preprocess(bytes, profile)
  , DRagLint.Core.Encoding    // PP-Task-10: EnsureUtf8Bytes
  { StripPasCommentsKeepLayout -- ONE implementation, shared with
    ParseUsesFromContent, so the .dpr and .pas uses-clause readers cannot drift.
    Despite its unit name this is a pure leaf: its interface pulls in nothing but
    System.*, so there is no dependency cycle and no lint machinery is dragged
    into the indexer. (The name is now wrong for its role; renaming it means
    touching the .dpr and .dproj of four projects, so it is left alone
    deliberately rather than overlooked.) }
  , DRagLint.Lint.ProjectChecks.Parse
  ;

{ ---- TClosureResolver ------------------------------------------------------- }

constructor TClosureResolver.Create(const ALibraryRoots: TArray<string>);
begin
  inherited Create;
  FLibraryRoots:= ALibraryRoots;
  // PP-Task-10: safe default -- a bare TClosureResolver keeps the pre-Task-10
  // all-branch scan; the CLI opts in via SetPreprocess.
  FPreprocessEnabled := False;
  FProfile           := Default(TDefineProfile);
  FPreprocessFellBack:= False;
end;

procedure TClosureResolver.SetPreprocess(AEnabled: Boolean; const AProfile: TDefineProfile);
begin
  FPreprocessEnabled := AEnabled;
  FProfile           := AProfile;
  FPreprocessFellBack:= False;   // reset the one-shot fallback latch per configure
end;

function TClosureResolver.MaybePreprocess(const AContent, AFileLabel: string): string;
// PP-Task-10: when preprocessing is enabled, resolve compiler-directive branches
// per FProfile BEFORE the caller scans `uses`, so inactive-branch unit names are
// blanked to spaces and never discovered. Offsets do not matter here (the caller
// needs unit NAMES, not spans), so we transcode string->UTF-8 bytes, preprocess,
// and decode back. A per-file preprocess exception falls back to the RAW content
// (logged once) so the closure never hard-fails on one bad file.
var
  Utf8    : TBytes;
  Resolved: TBytes;
begin
  if not FPreprocessEnabled then Exit(AContent);
  try
    Utf8:= EnsureUtf8Bytes(TEncoding.UTF8.GetBytes(AContent));
    Resolved:= Preprocess(Utf8, FProfile);
    Result:= TEncoding.UTF8.GetString(Resolved);
  except
    on E: Exception do
    begin
      if not FPreprocessFellBack then
      begin
        FPreprocessFellBack:= True;
        Writeln(ErrOutput, Format(
          '  PREPROCESS FALLBACK (closure): %s -- %s: %s (scanning raw; further fallbacks silent)',
          [AFileLabel, E.ClassName, E.Message]));
      end;
      Result:= AContent;   // fall back to the raw all-branch scan for this file
    end;
  end;
end;

function TClosureResolver.IsLibraryFile(const AFile: string): Boolean;
var
  NormFile: string;
  NormRoot: string;
  Root    : string;
begin
  NormFile:= LowerCase(StringReplace(AFile, '/', '\', [rfReplaceAll]));
  for Root in FLibraryRoots do
  begin
    NormRoot:= LowerCase(StringReplace(Root, '/', '\', [rfReplaceAll]));
    if not NormRoot.EndsWith('\') then NormRoot:= NormRoot + '\';
    if NormFile.StartsWith(NormRoot) then Exit(True);
  end;
  Result:= False;
end;

function TClosureResolver.FindUnitFile(const AUnitName: string; const ASearchPaths: TArray<string>): string;
var
  Dir      : string;
  Candidate: string;
  FileName : string;
begin
  // Dotted names like System.SysUtils become System.SysUtils.pas
  FileName:= AUnitName + '.pas';
  for Dir in ASearchPaths do
  begin
    Candidate:= TPath.Combine(Dir, FileName);
    if TFile.Exists(Candidate) then Exit(TPath.GetFullPath(Candidate));
  end;
  Result:= '';
end;

function TClosureResolver.FindIncFile(const AIncName, AFromDir: string; const ASearchPaths: TArray<string>): string;
var
  Dir      : string;
  Candidate: string;
begin
  // Try relative to the including file's directory first
  Candidate:= TPath.Combine(AFromDir, AIncName);
  if TFile.Exists(Candidate) then Exit(TPath.GetFullPath(Candidate));
  // Then try each search path
  for Dir in ASearchPaths do
  begin
    Candidate:= TPath.Combine(Dir, AIncName);
    if TFile.Exists(Candidate) then Exit(TPath.GetFullPath(Candidate));
  end;
  Result:= '';
end;

procedure TClosureResolver.ParseDprUses(const AContent, ABaseDir: string; AUnitNames, AUnitFiles: TStringList);
// Parse:  uses  unitname [in 'file.pas'] [, ...] ;
// Also handles the program/library's own `uses` clause which may span lines.
// We look for the FIRST `uses` block (the program uses) and also any
// subsequent ones (though .dpr files typically have only one).
const
  // Matches: <unitname> [in '<path>']  (dotted names, spaces OK around 'in')
  PAT_ITEM = '([A-Za-z_][A-Za-z0-9_.]*)\s*(?:in\s*''([^'']*)''\s*)?';
var
  UsesPos  : Integer         ;
  SemiPos  : Integer         ;
  Stripped : string          ;
  ItemPat  : string          ;
  Matches  : TMatchCollection;
  M        : TMatch          ;
  UName    : string          ;
  UFile    : string          ;
begin
  { SCRUB COMMENTS FIRST, over the WHOLE FILE, before anything is located in it.

    (Delimiters named in prose below, not shown: a closing brace inside a braced
    comment ends it early, which is the same trap DRagLint.Lint.SharedUnit's
    header records and it has now cost three builds in this codebase.)

    The ad-hoc stripper that used to live below handled BRACE comments ONLY --
    not slash-slash, not star-paren -- and it ran only AFTER the `uses` clause had
    been located. Both halves were wrong, and both put PHANTOM UNITS INTO THE
    COMPILE CLOSURE, which is the input to project index membership:

      * `\buses\b` was matched against UNSCRUBBED text, so the word "uses" in a
        .dpr header comment anchored the search and everything after it was read
        as a uses clause.
      * a commented-out member inside a real clause --
        `// OldUnit in 'old.pas',` -- survived the brace-only strip and was
        harvested as a live unit.

    A phantom closure member is not cosmetic: the unit is indexed, its symbols
    answer queries, and `lint-all --project` reports on a file the project does
    not compile. A member wrongly DROPPED is the same defect in the quiet
    direction.

    StripPasCommentsKeepLayout blanks every comment form to spaces while keeping
    length and line breaks, so every position computed below is still a position
    in the original text. It is the SAME function ParseUsesFromContent already
    scrubs with (DRagLint.Lint.ProjectChecks.Parse), so the .dpr path and the
    .pas path now agree by construction instead of by coincidence -- this family
    of defect spreads by each site growing its own half-scanner, and the fix is
    to stop having more than one.

    It also subsumes what the removed comment was worried about: a conditional
    directive such as an IFDEF for EurekaLog, and the form-name annotation that
    follows a member, are both braced, so they are blanked too. PAT_ITEM still
    never sees identifiers inside braces, and the
    ERegularExpressionError-on-optional-group-2 path that used to describe stays
    closed. }
  var Scrubbed: string:= StripPasCommentsKeepLayout(AContent);

  // Find `uses` keyword (word-boundary, case-insensitive)
  var Re:= TRegEx.Create('\buses\b', [roIgnoreCase]);
  var UsesMatch:= Re.Match(Scrubbed);
  if not UsesMatch.Success then Exit;

  UsesPos:= UsesMatch.Index + UsesMatch.Length - 1; // 1-based, end of 'uses'
  // Find the closing semicolon of the uses block
  SemiPos:= Pos(';', Scrubbed, UsesPos);
  if SemiPos = 0 then Exit;

  Stripped:= Copy(Scrubbed, UsesPos + 1, SemiPos - UsesPos - 1);

  ItemPat:= PAT_ITEM;
  Matches:= TRegEx.Matches(Stripped, ItemPat, [roIgnoreCase]);
  for M in Matches do
  begin
    UName:= M.Groups[1].Value.Trim;
    if SameText(UName, '') then Continue;
    // Skip keywords that regex might catch
    if SameText(UName, 'in') then Continue;

    UFile:= '';
    // Guard: PAT_ITEM has 2 capture groups; access group 2 only when present.
    if (M.Groups.Count > 2) and M.Groups[2].Success then
    begin
      UFile:= M.Groups[2].Value.Trim;
      if (UFile <> '') and (not TPath.IsPathRooted(UFile)) then UFile:= TPath.GetFullPath(TPath.Combine(ABaseDir, UFile));
    end;

    AUnitNames.Add(UName);
    AUnitFiles.Add(UFile);
  end; // for
end; // procedure

procedure TClosureResolver.ParseDprojRefs(const AContent, ABaseDir: string; AFiles: TStringList);
// Matches: <DCCReference Include="some\path.pas"/>
var
  Pat     : string          ;
  Matches : TMatchCollection;
  M       : TMatch          ;
  RefPath : string          ;
  Resolved: string          ;
begin
  Pat:= '<DCCReference\s+Include="([^"]+\.pas)"';
  Matches:= TRegEx.Matches(AContent, Pat, [roIgnoreCase]);
  for M in Matches do
  begin
    RefPath:= M.Groups[1].Value;
    if not TPath.IsPathRooted(RefPath) then Resolved:= TPath.GetFullPath(TPath.Combine(ABaseDir, RefPath))
    else Resolved:= TPath.GetFullPath(RefPath);
    AFiles.Add(Resolved);
  end;
end;

procedure TClosureResolver.ParseDprojSearchPaths(const AContent, ABaseDir: string; APaths: TStringList);
var
  Pat     : string          ;
  Matches : TMatchCollection;
  M       : TMatch          ;
  RawList : string          ;
  P       : string          ;
  Resolved: string          ;
  Parts   : TArray<string>  ;
begin
  Pat:= '<DCC_UnitSearchPath>(.*?)</DCC_UnitSearchPath>';
  Matches:= TRegEx.Matches(AContent, Pat, [roIgnoreCase, roSingleLine]);
  for M in Matches do
  begin
    RawList:= M.Groups[1].Value;
    Parts:= RawList.Split([';']);
    for P in Parts do
    begin
      Resolved:= P.Trim;
      if Resolved = '' then Continue;
      // Minimal macro expansion: $(BDS) is a library path, skip it
      if Pos('$(', Resolved) > 0 then Continue;
      if not TPath.IsPathRooted(Resolved) then Resolved:= TPath.GetFullPath(TPath.Combine(ABaseDir, Resolved));
      if TDirectory.Exists(Resolved) then APaths.Add(Resolved);
    end;
  end;
end; // procedure

function TClosureResolver.StripCommentsAndStrings(const AText: string): string;
// Replace block comment content with spaces (preserving length so positions
// are not disturbed) and string literal content with spaces.
// This is a best-effort pass; nested comments are not valid Pascal so we
// don't handle them.
var
  I       : Integer       ;
  Len     : Integer       ;
  C       : Char          ;
  InBrace : Boolean       ; // { } comment vs (* *) comment
  InParen : Boolean       ;
  InString: Boolean       ;
  SB      : TStringBuilder;
begin
  SB:= TStringBuilder.Create(Length(AText));
  try
    I:= 1;
    Len:= Length(AText);
    InBrace := False;
    InParen := False;
    InString:= False;
    while I <= Len do
    begin
      C:= AText[I];
      if InString then
      begin
        if C = '''' then
        begin
          // Doubled quote inside string is escaped
          if (I < Len) and (AText[I + 1] = '''') then
          begin
            SB.Append('  ');
            Inc(I, 2);
            Continue;
          end;
          InString:= False;
          SB.Append(' ');
        end
        else SB.Append(' ');
        Inc(I);
        Continue;
      end; // if
      if InBrace then
      begin
        if C = '}' then
        begin
          InBrace:= False;
          SB.Append(' ');
        end
        else SB.Append(' ');
        Inc(I);
        Continue;
      end;
      if InParen then
      begin
        if (C = '*') and (I < Len) and (AText[I + 1] = ')') then
        begin
          InParen:= False;
          SB.Append('  ');
          Inc(I, 2);
          Continue;
        end
        else SB.Append(' ');
        Inc(I);
        Continue;
      end;
      // Not inside any comment or string
      if C = '''' then
      begin
        InString:= True;
        SB.Append(' ');
        Inc(I);
        Continue;
      end;
      if C = '{' then
      begin
        // Check for {$I ...} or {$INCLUDE ...} -- these are DIRECTIVES, not
        // comments, and should NOT be stripped here.  We will pick them up in
        // ExtractIncludes separately on the ORIGINAL text.
        // However to avoid regex picking up words inside ordinary {..} comments
        // we still blank them out in the uses-scan output.
        InBrace:= True;
        SB.Append(' ');
        Inc(I);
        Continue;
      end;
      if (C = '(') and (I < Len) and (AText[I + 1] = '*') then
      begin
        InParen:= True;
        SB.Append('  ');
        Inc(I, 2);
        Continue;
      end;
      // // line comment: skip to end of line
      if (C = '/') and (I < Len) and (AText[I + 1] = '/') then
      begin
        while (I <= Len) and (AText[I] <> #10) do
        begin
          SB.Append(' ');
          Inc(I);
        end;
        Continue;
      end;
      SB.Append(C);
      Inc(I);
    end; // while
    Result:= SB.ToString;
  finally
    SB.Free;
  end; // try
end; // function

function TClosureResolver.ExtractUses(const AText: string): TArray<string>;
// Scan stripped text for ALL `uses` clauses (interface + implementation).
// Each clause: `uses <name> [, <name>]* ;`
// We collect every dotted-identifier list between `uses` and `;`.
var
  Stripped : string          ;
  Clause   : string          ;
  Token    : string          ;
  ReUses   : TRegEx          ;
  ReIdent  : TRegEx          ;
  UsesMatch: TMatch          ;
  Pos      : Integer         ;
  SemiPos  : Integer         ;
  ClauseEnd: Integer         ;
  Matches  : TMatchCollection;
  M        : TMatch          ;
  List     : TList<string>   ;
begin
  Stripped:= StripCommentsAndStrings(AText);
  List:= TList<string>.Create;
  try
    ReUses := TRegEx.Create('\buses\b'               , [roIgnoreCase]);
    ReIdent:= TRegEx.Create('[A-Za-z_][A-Za-z0-9_.]*', [            ]);

    UsesMatch:= ReUses.Match(Stripped);
    while UsesMatch.Success do
    begin
      Pos:= UsesMatch.Index + UsesMatch.Length; // 1-based char after 'uses'
      SemiPos:= System.Pos(';', Stripped, Pos);
      if SemiPos = 0 then Break;

      ClauseEnd:= SemiPos - Pos;
      Clause:= Copy(Stripped, Pos, ClauseEnd);

      { COLUMN-ALIGNED qualified names. Whitespace around the dot of a qualified
        unit name is insignificant to the compiler, and this codebase aligns them
        for readability -- DRagLint.CLI.pas alone has 64 entries of the shape

            , DRagLint.Doc        .Batch
            , DRagLint.Core   .Interfaces

        The identifier regex below stops at the space, so such an entry yielded
        TWO junk tokens ("DRagLint.Doc" and "Batch") and never the real unit
        name. Every consumer that asks "is this unit reached via uses?" then
        answered no: `reconcile-project` reported 28 genuinely-used units as
        "EXTRA -- listed but never reached via uses (review)", which invites
        deleting units the build needs.

        The INDEX was never short a file -- the closure also takes the .dproj
        member list, which covers them (closure 108 = indexed 108, measured
        before and after this fix) -- so this changes what is REACHABLE, not
        what is extracted.

        Collapsing the whitespace cannot merge two separate units: a uses clause
        separates entries with commas, so a dot between two identifiers is by
        definition part of one qualified name. Strings and comments are already
        gone (StripCommentsAndStrings above), so no path literal is affected. }
      Clause:= TRegEx.Replace(Clause, '\s*\.\s*', '.');

      Matches:= ReIdent.Matches(Clause);
      for M in Matches do
      begin
        Token:= M.Value;
        // Skip `in` keyword (appears after unit name in .dpr-style files
        // scanned here -- though that style is usually only in the .dpr itself)
        if SameText(Token, 'in') then Continue;
        List.Add(Token);
      end;

      // Advance past this semicolon
      UsesMatch:= ReUses.Match(Stripped, SemiPos);
    end; // while

    Result:= List.ToArray;
  finally
    List.Free;
  end; // try
end; // function

function TClosureResolver.ExtractIncludes(const AText: string): TArray<string>;
// Scan the ORIGINAL text (not stripped) for {$I name} and {$INCLUDE name}.
// The directive is inside braces so is a special compiler-directive form.
// Recognises both:   {$I filename}   and   {$INCLUDE filename}
var
  Re     : TRegEx          ;
  Matches: TMatchCollection;
  M      : TMatch          ;
  List   : TList<string>   ;
begin
  List:= TList<string>.Create;
  try
    Re:= TRegEx.Create( '\{\$(?:I|INCLUDE)\s+([^\}\s]+)\s*\}', [roIgnoreCase]);
    Matches:= Re.Matches(AText);
    for M in Matches do
      if M.Groups[1].Success then List.Add(M.Groups[1].Value.Trim);
    Result:= List.ToArray;
  finally
    List.Free;
  end;
end;

function TClosureResolver.Resolve(const AProjectFile: string; const AExclude: TArray<string>): TClosureResult;
type
  // Queue entry: unit name + resolved file (may be '' = not yet resolved)
  TWorkItem = record
    UnitName : string; // may be '' for inc files enqueued directly
    FilePath : string; // absolute resolved path (may be '' if resolution pending)
    UsingUnit: string; // unit that pulled this in (for warning message)
  end;
var
  ProjectAbs : string                      ;
  BaseDir    : string                      ;
  Ext        : string                      ;
  Content    : string                      ;
  SearchPaths: TStringList                 ; // ordered search-path list
  Visited    : TDictionary<string, Boolean>; // lowercase abs-path -> True
  Files      : TList<string>               ;
  Warnings   : TList<string>               ;
  UsedByList : TList<string>               ; // parallel to Files; using-unit per entry
  Queue      : TQueue<TWorkItem>           ;

  UnitNames    : TStringList;
  UnitFilePaths: TStringList;
  DprojRefFiles: TStringList;

  SearchArr   : TArray<string>;
  Item        : TWorkItem     ;
  ResolvedFile: string        ;
  UnitDir     : string        ;
  SubUses     : TArray<string>;
  SubIncs     : TArray<string>;
  IncFile     : string        ;
  SubName     : string        ;
  Wi          : TWorkItem     ;
  BaseName    : string        ;

  procedure EnqueueFile(const AAbsPath, AUsingUnit: string);
  var
    LKey: string   ;
    W2  : TWorkItem;
  begin
    LKey:= LowerCase(AAbsPath);
    if Visited.ContainsKey(LKey) then Exit;
    Visited.Add(LKey, True);
    Files     .Add(AAbsPath  );
    UsedByList.Add(AUsingUnit);
    W2.UnitName := '';
    W2.FilePath := AAbsPath;
    W2.UsingUnit:= AUsingUnit;
    Queue.Enqueue(W2);
    // Exclude-but-in-closure warning
    if TGlob.MatchesAny(TPath.GetFileName(AAbsPath), AExclude) then
      Warnings.Add('WARN: ' + AAbsPath + ' is in the compile closure (used by ' + AUsingUnit + ') but matches an exclude pattern');
  end;

begin
  ProjectAbs:= TPath.GetFullPath(AProjectFile);
  if not TFile.Exists(ProjectAbs) then raise Exception.CreateFmt('Project file not found: %s', [ProjectAbs]);

  BaseDir:= TPath.GetDirectoryName(ProjectAbs);
  Ext:= LowerCase(TPath.GetExtension(ProjectAbs));

  Files     := TList<string>.Create;
  Warnings  := TList<string>.Create;
  UsedByList:= TList<string>.Create;
  Visited:= TDictionary<string, Boolean>.Create;
  Queue:= TQueue<TWorkItem>.Create;
  SearchPaths:= TStringList.Create;
  SearchPaths.CaseSensitive:= False;

  UnitNames    := TStringList.Create;
  UnitFilePaths:= TStringList.Create;
  DprojRefFiles:= TStringList.Create;
  try
    // --- Step 1: build search paths -------------------------------------------
    // Always include the project base directory first
    SearchPaths.Add(BaseDir);

    Content:= TFile.ReadAllText(ProjectAbs);

    if Ext = '.dproj' then
    begin
      ParseDprojSearchPaths(Content, BaseDir, SearchPaths);
      // Also try to find the sibling .dpr
      var DprPath:= TPath.ChangeExtension(ProjectAbs, '.dpr');
      if TFile.Exists(DprPath) then
      begin
        var DprContent:= MaybePreprocess(TFile.ReadAllText(DprPath), DprPath);
        ParseDprUses(DprContent, BaseDir, UnitNames, UnitFilePaths);
      end;
      // Seed from DCCReference entries
      ParseDprojRefs(Content, BaseDir, DprojRefFiles);
    end
    else // .dpr  (or .dpk)
    begin
      { SEARCH PATHS COME FROM THE .dproj, EVEN WHEN RESOLVING A .dpr.

        A .dpr carries no search paths -- they live in the .dproj's
        DCC_UnitSearchPath. Without them a unit that sits outside the project
        folder cannot be resolved to a file at all, so it never enters the
        closure.

        That is not cosmetic. TProjectReconciler.Analyze resolves the closure
        from the .dpr NO MATTER which file it was given, so this branch is the
        one reconcile always takes. On this repo it left src\doc off the path,
        DRagLint.Doc.Drift could not be resolved, it was absent from ClosureSet,
        and reconcile reported it as EXTRA -- "listed but never reached via
        uses" -- which was false. Reproduced 2026-08-26.

        SEARCH PATHS ONLY -- deliberately NOT ParseDprojRefs. Seeding the
        DCCReference members here would make the EXTRA set vacuously empty:
        every listed unit would be in the closure BECAUSE it was listed, and
        reconcile would go green without ever reaching anything through uses.
        That is the wrong kind of green, and it would hide the very defect the
        verb exists to find. }
      var SiblingDproj: string := TPath.ChangeExtension(ProjectAbs, '.dproj');
      if TFile.Exists(SiblingDproj) then
        try
          ParseDprojSearchPaths(TFile.ReadAllText(SiblingDproj), BaseDir, SearchPaths);
        except
          { An unreadable or malformed .dproj must not take the .dpr walk down;
            it simply contributes no extra search paths. }
        end;

      // PP-Task-10: preprocess the .dpr/.dpk source before its uses-scan so the
      // inactive-branch units are blanked (per-config discovery). The .dproj XML
      // branch above is NOT preprocessed (Content there feeds XML parsers).
      ParseDprUses(MaybePreprocess(Content, ProjectAbs), BaseDir, UnitNames, UnitFilePaths);
    end;

    SearchArr:= SearchPaths.ToStringArray;

    // --- Step 2: seed the worklist -------------------------------------------
    // .dproj: seed from DCCReference paths
    for var F in DprojRefFiles do
    begin
      if TFile.Exists(F) and not IsLibraryFile(F) then
      begin
        Wi.UnitName:= TPath.GetFileNameWithoutExtension(F);
        Wi.FilePath := F;
        Wi.UsingUnit:= '<project>';
        EnqueueFile(F, '<project>');
      end;
    end;

    // .dpr / sibling .dpr for .dproj: seed from parsed uses clause
    for var I:= 0 to UnitNames.Count - 1 do
    begin
      var UN:= UnitNames    [I];
      var UF:= UnitFilePaths[I];
      ResolvedFile:= '';

      if UF <> '' then
      begin
        // `in 'path'` specifier: use that path directly
        if TFile.Exists(UF) then ResolvedFile:= UF;
      end;

      if ResolvedFile = '' then ResolvedFile:= FindUnitFile(UN, SearchArr);

      if (ResolvedFile <> '') and not IsLibraryFile(ResolvedFile) then
      begin
        Wi.UnitName := UN;
        Wi.FilePath := ResolvedFile;
        Wi.UsingUnit:= '<project>';
        // EnqueueFile handles dedup + warning
        EnqueueFile(ResolvedFile, '<project>');
      end;
    end; // for

    // --- Step 3: BFS ---------------------------------------------------------
    while Queue.Count > 0 do
    begin
      Item:= Queue.Dequeue;

      if Item.FilePath = '' then Continue;
      if not TFile.Exists(Item.FilePath) then Continue;

      var FileExt:= LowerCase(TPath.GetExtension(Item.FilePath));
      if FileExt = '.inc' then Continue; // don't recurse into .inc for uses, just leave it in Files

      UnitDir:= TPath.GetDirectoryName(Item.FilePath);
      // PP-Task-10: preprocess the unit source before its uses-scan so a unit
      // pulled in only under an inactive branch of THIS member unit is likewise
      // not discovered (per-config transitive closure). {$I}/{$INCLUDE} scanning
      // below uses the RAW content -- includes are file references we still want
      // resolved regardless of branch, and MaybePreprocess blanks directives.
      var RawUnitContent:= TFile.ReadAllText(Item.FilePath);
      var UnitContent:= MaybePreprocess(RawUnitContent, Item.FilePath);

      // (a) Recurse into `uses` references
      SubUses:= ExtractUses(UnitContent);
      for SubName in SubUses do
      begin
        if SubName = '' then Continue;
        ResolvedFile:= FindUnitFile(SubName, SearchArr);
        // Also try relative to the unit's own directory (not always on path)
        if (ResolvedFile = '') and TFile.Exists(TPath.Combine(UnitDir, SubName + '.pas')) then ResolvedFile:= TPath.GetFullPath( TPath.Combine(UnitDir, SubName + '.pas'));

        if (ResolvedFile <> '') and not IsLibraryFile(ResolvedFile) then
        begin
          // Determine the "using unit" name for warnings
          BaseName:= TPath.GetFileNameWithoutExtension(Item.FilePath);
          EnqueueFile(ResolvedFile, BaseName);
        end;
      end;

      // (b) {$I}/{$INCLUDE} files -- add but don't recurse for uses. Scan the
      // RAW content: MaybePreprocess blanks ALL directives (including {$I}), so
      // include discovery must read the original text. Include-file discovery is
      // intentionally all-branch and thus identical to the pre-Task-10 behaviour.
      SubIncs:= ExtractIncludes(RawUnitContent);
      for IncFile in SubIncs do
      begin
        ResolvedFile:= FindIncFile(IncFile, UnitDir, SearchArr);
        if (ResolvedFile <> '') and not IsLibraryFile(ResolvedFile) then
        begin
          BaseName:= TPath.GetFileNameWithoutExtension(Item.FilePath);
          EnqueueFile(ResolvedFile, BaseName);
        end;
      end;
    end; // while

    Result.Files   := Files     .ToArray;
    Result.Warnings:= Warnings  .ToArray;
    Result.UsedBy  := UsedByList.ToArray;
  finally
    DprojRefFiles.Free;
    UnitFilePaths.Free;
    UnitNames.Free;
    SearchPaths.Free;
    Queue.Free;
    Visited.Free;
    Warnings.Free;
    UsedByList.Free;
    Files.Free;
  end; // try
end; // begin

end.
