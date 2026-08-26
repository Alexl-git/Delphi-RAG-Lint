unit DRagLint.Index.Manifest;

/// <summary>Manifest config types: load / merge (global + local) / validate / save
/// for the drag-lint named-database index manifest (.drag-lint.json).</summary>
/// <remarks>
/// Config discovery:
///   1. Global config: &lt;EngineDir&gt;\drag-lint.json (beside the EXE).
///   2. Local override: .drag-lint.json found by walking AStartDir up to the root.
/// Merge rules: local scalars override global ONLY when they are present in the
/// local file; local GlobalExclude is APPENDED to (not replacing) the global list;
/// a local section with the same Name replaces the matching global section; new
/// local sections are appended.
/// All .pas source: strict 7-bit ASCII, CRLF line endings, no BOM.
/// </remarks>

interface

uses
  System.SysUtils
  , System.Classes
  , System.IOUtils
  , System.JSON
  , System.Generics.Collections
  ;

type
  /// <summary>Governs how projects are partitioned when building indexes.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Index.Manifest.pas)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TProjectsIndexing = (piPerProject, piPerGroup, piSingle);

  /// <summary>Top-level settings block from the drag-lint manifest.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.CLI.DoSelfTestManifestSaveAtomic (DRagLint.CLI.pas), declaration (DRagLint.Index.Manifest.pas), DRagLint.Index.Manifest.TManifestIO.ParseTextEx (DRagLint.Index.Manifest.pas), DRagLint.Index.Manifest.TManifestIO.Load (DRagLint.Index.Manifest.pas)</para>
  /// <para>Used in units: DRagLint.CLI, DRagLint.Index.Manifest</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TIndexSettings = record
    /// <summary>How project folders map to index DBs.</summary>
    CurrentProjectsIndexing: TProjectsIndexing;
    /// <summary>Default platform token used for {platform} expansion and DB selection.</summary>
    DefaultPlatform: string;
    /// <summary>Maximum DB file size (MB) before the 32-bit engine emits a warning.</summary>
    SizeGuardMB: Integer;
    /// <summary>Path to the drag-lint engine EXE, or 'auto' to locate beside the current EXE.</summary>
    EnginePath: string;
    /// <summary>Maximum parallel index jobs. 0 = auto (min(CpuCount, sectionCount)).</summary>
    MaxJobs: Integer;
    /// <summary>Maximum file size in KB that the indexer will hand to the
    /// tree-sitter parser. Files exceeding this threshold are skipped with a
    /// SKIP warning. 0 is normalised to 2048 (the safe default).
    /// Override via CLI: --max-file-kb N (0 = unlimited).</summary>
    MaxParseFileKB: Integer;
    /// <summary>Returns a record with all fields set to their documented defaults.</summary>
    /// <returns><!-- drag-lint:auto -->TIndexSettings -- Observed:
    /// Default(TIndexSettings).</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.CLI.DoSelfTestManifestSaveAtomic (DRagLint.CLI.pas), DRagLint.Index.Manifest.TManifestIO.Load (DRagLint.Index.Manifest.pas), DRagLint.Index.Manifest.TManifestIO.ParseTextEx (DRagLint.Index.Manifest.pas)</para>
    /// <para>Calls: Default</para>
    /// <para>Pure</para>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function Defaults: TIndexSettings; static;
  end; // record

  /// <summary>Doc-generation settings, parsed from the manifest 'docs' object.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.CLI.DoSelfTestManifestSaveAtomic (DRagLint.CLI.pas), declaration (DRagLint.Index.Manifest.pas), DRagLint.Index.Manifest.TManifestIO.ParseTextEx (DRagLint.Index.Manifest.pas), DRagLint.Index.Manifest.TManifestIO.Load (DRagLint.Index.Manifest.pas)</para>
  /// <para>Used in units: DRagLint.CLI, DRagLint.Index.Manifest</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TDocSettings = record
    /// <summary>Max distinct return cases enumerated in a generated &lt;returns&gt;
    /// (the "Observed: ..." list). Default 20. 0 or negative disables enumeration
    /// (bare TODO only).</summary>
    MaxReturnCases: Integer;
    /// <summary>Max distinct callers listed on the generated "Called from:" line
    /// (v(ADP1 T1)). Default 5. Callers beyond the cap are summarised as a
    /// trailing "(+N more)" (RenderFactsBlock); the true count is unaffected.
    /// 0 or negative shows no callers (still counted in the "(+N more)" total).</summary>
    MaxCallers: Integer;
    /// <summary>ADP1 T2: threshold (impl body line count, ImplEndLine -
    /// ImplStartLine) at or under which a Get*/Set* method is treated as a
    /// TRIVIAL property accessor and SKIPPED by the batch document verbs
    /// (document --unit/--project, document-all). Default 2. UNLIKE
    /// MaxReturnCases/MaxCallers, this filter is ON BY DEFAULT -- the default
    /// lives in code (TDocSettings.Defaults), and an absent
    /// docs.accessor_trivial_max_lines key does NOT disable the filter, it
    /// just leaves the threshold at 2. --include-accessors (CLI) disables the
    /// filter outright for one run, independent of this threshold. document
    /// --qname (single-symbol) is never filtered by this setting.</summary>
    AccessorTrivialMaxLines: Integer;
    /// <summary>v(ADP2 T3): the McCabe cyclomatic complexity at or above which
    /// a generated DocInsight comment's managed block gets a 'Complexity: N
    /// (cyclomatic), M lines' line (RenderFactsBlock). Default 10. Applied at
    /// RENDER time (see RenderFactsBlock's remarks), NOT at index time -- the
    /// raw Cyclomatic/BodyLoc values are always computed and stored for every
    /// analyzed routine, so changing this threshold takes effect on the very
    /// next `document` run with no reindex required.</summary>
    ComplexityMin: Integer;
    /// <summary>Record with all fields at documented defaults (MaxReturnCases=20, MaxCallers=5, AccessorTrivialMaxLines=2, ComplexityMin=10).</summary>
    /// <returns><!-- drag-lint:auto -->TDocSettings -- Observed: Default(TDocSettings).</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.CLI.DoSelfTestManifestSaveAtomic (DRagLint.CLI.pas), DRagLint.Index.Manifest.TManifestIO.Load (DRagLint.Index.Manifest.pas), DRagLint.Index.Manifest.TManifestIO.ParseTextEx (DRagLint.Index.Manifest.pas)</para>
    /// <para>Calls: Default</para>
    /// <para>Pure</para>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function Defaults: TDocSettings; static;
  end; // record

  /// <summary>Which top-level settings keys were explicitly present in a parsed JSON block.
  /// Used by the merge logic to distinguish "absent" (keep global) from "present but default".</summary>
  /// <param name="skCurrentProjectsIndexing"><!-- drag-lint:auto --></param>
  /// <param name="skDefaultPlatform"><!-- drag-lint:auto --></param>
  /// <param name="skSizeGuardMB"><!-- drag-lint:auto --></param>
  /// <param name="skEnginePath"><!-- drag-lint:auto --></param>
  /// <param name="skMaxJobs"><!-- drag-lint:auto --></param>
  /// <param name="skMaxParseFileKB"><!-- drag-lint:auto --></param>
  /// <param name="skMaxReturnCases"><!-- drag-lint:auto --></param>
  /// <param name="skMaxCallers"><!-- drag-lint:auto --></param>
  /// <param name="skAccessorTrivialMaxLines"><!-- drag-lint:auto --></param>
  /// <param name="skComplexityMin"><!-- drag-lint:auto --></param>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.CLI.DoSelfTestManifestMerge (DRagLint.CLI.pas), declaration (DRagLint.Index.Manifest.pas), DRagLint.Index.Manifest.TManifestIO.ParseTextEx (DRagLint.Index.Manifest.pas), DRagLint.Index.Manifest.TManifestIO.ParseText (DRagLint.Index.Manifest.pas), DRagLint.Index.Manifest.TManifestIO.Load (DRagLint.Index.Manifest.pas)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TSettingsKeySet = set of ( skCurrentProjectsIndexing, skDefaultPlatform, skSizeGuardMB, skEnginePath, skMaxJobs, skMaxParseFileKB, skMaxReturnCases, skMaxCallers, skAccessorTrivialMaxLines, skComplexityMin );

  /// <summary>Describes one named index section within the manifest.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.CLI.ResolveIndexDb (DRagLint.CLI.pas), DRagLint.CLI.DoScanAll (DRagLint.CLI.pas), DRagLint.CLI.DetectPlatformFromDproj (DRagLint.CLI.pas), DRagLint.CLI.DoSelfTestSectionDb (DRagLint.CLI.pas), DRagLint.CLI.DoSelfTestManifestSaveAtomic (DRagLint.CLI.pas) (+9 more)</para>
  /// <para>Used in units: DRagLint.CLI, DRagLint.Index.Coverage, DRagLint.Index.Manifest, DRagLint.Index.Plan</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TIndexSection = record
    /// <summary>Unique human-readable name used to identify and reference this section.</summary>
    Name: string;
    /// <summary>Output SQLite file. May be empty (default: &lt;OutDir&gt;\&lt;Name&gt;.sqlite),
    /// a bare filename, or a template containing '{platform}'.</summary>
    Db: string;
    /// <summary>Data source: '' = include-list (folder tree); 'registry-libraries' = Delphi registry paths.</summary>
    Source: string;
    /// <summary>Platform tokens this section targets. ['*'] means all known platforms.</summary>
    Platforms: TArray<string>;
    /// <summary>Folder paths or .dpr/.dproj files to index. Relative to RootDir.</summary>
    Include: TArray<string>;
    /// <summary>Per-section glob patterns whose matches are excluded from the walk.</summary>
    Exclude: TArray<string>;
    /// <summary>If non-empty, only files matching one of these globs are indexed.</summary>
    IncludeOnly: TArray<string>;
    /// <summary>When True, .gitignore / .hgignore files found during the walk are honoured.</summary>
    UseIgnoreFiles: Boolean;
    /// <summary>Section names (or '*' for all) whose resolved roots are treated as
    /// already-indexed and excluded from this section's walk (deduplication).</summary>
    DedupAgainst: TArray<string>;
    /// <summary>When True and Source='', only MS*.SQL files pass the SQL file gate.</summary>
    /// <remarks>Applies to folder-tree (non-library) sections only; ignored when Source='registry-libraries'.</remarks>
    SqlOnlyMS: Boolean;
  end; // record

  /// <summary>Complete parsed and merged manifest for a drag-lint installation.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.CLI.LoadDocMaxReturnCases (DRagLint.CLI.pas), DRagLint.CLI.LoadDocMaxCallers (DRagLint.CLI.pas), DRagLint.CLI.LoadDocAccessorMaxLines (DRagLint.CLI.pas), DRagLint.CLI.DoIndexAll (DRagLint.CLI.pas), DRagLint.CLI.ResolveIndexDb (DRagLint.CLI.pas) (+28 more)</para>
  /// <para>Used in units: DRagLint.CLI, DRagLint.Index.Coverage, DRagLint.Index.DbSelect, DRagLint.Index.Manifest, DRagLint.Index.ManifestWrite, DRagLint.Index.Plan</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TIndexManifest = record
    /// <summary>Absolute directory of the resolved config file (used to expand relative paths).</summary>
    RootDir: string;
    /// <summary>Directory where output SQLite DBs are written. Relative to RootDir.</summary>
    OutDir: string;
    /// <summary>Glob patterns applied to every section's walk before section-level excludes.
    /// During merge, local global-excludes are ADDITIVE to global ones (appended after).</summary>
    GlobalExclude: TArray<string>;
    /// <summary>Settings block parsed from the 'settings' key.</summary>
    Settings: TIndexSettings;
    /// <summary>Doc-generation settings parsed from the 'docs' key.</summary>
    Docs: TDocSettings;
    /// <summary>Ordered list of index sections.</summary>
    Sections: TArray<TIndexSection>;
    /// <summary>Returns True and populates ASection if a section named AName exists (case-insensitive).</summary>
    /// <param name="AName">Section name to look up.</param>
    /// <param name="ASection">Receives a copy of the matched section.</param>
    /// <returns>True if found; False otherwise.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Index.Manifest.TManifestIO.Validate (DRagLint.Index.Manifest.pas), DRagLint.Index.Plan.ResolvePlan (DRagLint.Index.Plan.pas)</para>
    /// <para>Calls: Default, SameText</para>
    /// <para>Returns: True; False</para>
    /// <para>Reads: Sections</para>
    /// <para>Mutates: ASection (out)</para>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function FindSection(const AName: string; out ASection: TIndexSection): Boolean;
  end; // record

  /// <summary>Load, parse, validate and save drag-lint index manifests.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.CLI.LoadDocMaxReturnCases (DRagLint.CLI.pas), DRagLint.CLI.LoadDocMaxCallers (DRagLint.CLI.pas), DRagLint.CLI.LoadDocAccessorMaxLines (DRagLint.CLI.pas), DRagLint.CLI.ManifestToJson (DRagLint.CLI.pas), DRagLint.CLI.DoIndexAll (DRagLint.CLI.pas) (+19 more)</para>
  /// <para>Used in units: DRagLint.CLI, DRagLint.Index.Manifest, DRagLint.Index.ManifestWrite</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TManifestIO = class
    public
      /// <summary>Load and merge: reads the global config beside AEngineDir, then
      /// walks AStartDir up to the root looking for .drag-lint.json and merges it
      /// (local scalars override global when present; local GlobalExclude appends to global;
      /// same-name sections replace; new sections append).</summary>
      /// <param name="AEngineDir">Directory containing the drag-lint EXE (global config source).</param>
      /// <param name="AStartDir">Directory to begin the upward local-config search.</param>
      /// <returns>Merged TIndexManifest. RootDir is set to the local config dir if found,
      /// else to AEngineDir.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.CLI.DoIndex (DRagLint.CLI.pas), DRagLint.CLI.DoIndexAll (DRagLint.CLI.pas), DRagLint.CLI.DoLibraryDrift (DRagLint.CLI.pas), DRagLint.CLI.DoQuery (DRagLint.CLI.pas), DRagLint.CLI.DoReconcileProject (DRagLint.CLI.pas) (+13 more)</para>
      /// <para>Calls: Default, DRagLint.Index.Manifest.TDocSettings.Defaults, DRagLint.Index.Manifest.TIndexSettings.Defaults, DRagLint.Index.Manifest.TManifestIO.Load.MergeSections, DRagLint.Index.Manifest.TManifestIO.ParseText, DRagLint.Index.Manifest.TManifestIO.ParseTextEx, SameText, Writeln</para>
      /// <para>Returns: Default(TIndexManifest); GlobalManifest; LocalManifest</para>
      /// <para>Complexity: 24 (cyclomatic, outer body), 129 lines (full implementation)</para>
      /// <para>Touches: file system</para>
      /// <seealso cref="DRagLint.Index.Manifest.TDocSettings.Defaults"/>
      /// <seealso cref="DRagLint.Index.Manifest.TIndexSettings.Defaults"/>
      /// <seealso cref="DRagLint.Index.Manifest.TManifestIO.Load.MergeSections"/>
      /// <seealso cref="DRagLint.Index.Manifest.TManifestIO.ParseText"/>
      /// <seealso cref="DRagLint.Index.Manifest.TManifestIO.ParseTextEx"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function Load(const AEngineDir, AStartDir: string): TIndexManifest; static;

      /// <summary>Parse a manifest from JSON text and set RootDir to ARootDir.</summary>
      /// <param name="AJson">Raw JSON string (UTF-8 or ASCII).</param>
      /// <param name="ARootDir">Absolute directory associated with this JSON (used for relative paths).</param>
      /// <returns>Populated TIndexManifest.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.CLI.DoIndexAll (DRagLint.CLI.pas), DRagLint.CLI.DoLibraryDrift (DRagLint.CLI.pas), DRagLint.CLI.DoMigrateDbs (DRagLint.CLI.pas), DRagLint.CLI.DoReconcileProject (DRagLint.CLI.pas), DRagLint.CLI.DoResolveDbsList (DRagLint.CLI.pas) (+5 more)</para>
      /// <para>Calls: DRagLint.Index.Manifest.TManifestIO.ParseTextEx</para>
      /// <para>Returns: ParseTextEx(AJson, ARootDir, Keys)</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Index.Manifest.TManifestIO.ParseTextEx"/>
      /// <seealso cref="DRagLint.Index.Manifest.TManifestIO.Load"/>
      /// <seealso cref="DRagLint.Index.Manifest.TManifestIO.Save"/>
      /// <seealso cref="DRagLint.Index.Manifest.TManifestIO.ToJson"/>
      /// <seealso cref="DRagLint.Index.Manifest.TManifestIO.Validate"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function ParseText(const AJson, ARootDir: string): TIndexManifest; static;

      /// <summary>Parse a manifest from JSON text, also returning which top-level settings
      /// keys were explicitly present in the JSON. Used by the merge logic.</summary>
      /// <param name="AJson">Raw JSON string (UTF-8 or ASCII).</param>
      /// <param name="ARootDir">Absolute directory associated with this JSON (used for relative paths).</param>
      /// <param name="ASettingsKeys">Receives the set of settings keys that were present.</param>
      /// <returns>Populated TIndexManifest.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.CLI.DoSelfTestManifestMerge (DRagLint.CLI.pas), DRagLint.Index.Manifest.TManifestIO.Load (DRagLint.Index.Manifest.pas), DRagLint.Index.Manifest.TManifestIO.ParseText (DRagLint.Index.Manifest.pas)</para>
      /// <para>Calls: Default, DRagLint.Index.Manifest.JsonStrArr, DRagLint.Index.Manifest.ParseProjectsIndexing, DRagLint.Index.Manifest.ParseSection, DRagLint.Index.Manifest.TDocSettings.Defaults, DRagLint.Index.Manifest.TIndexSettings.Defaults, Include, TJSONArray, TJSONObject</para>
      /// <para>Returns: Default(TIndexManifest)</para>
      /// <para>Complexity: 25 (cyclomatic, outer body), 131 lines (full implementation)</para>
      /// <para>Mutates: ASettingsKeys (out)</para>
      /// <seealso cref="DRagLint.Index.Manifest.JsonStrArr"/>
      /// <seealso cref="DRagLint.Index.Manifest.ParseProjectsIndexing"/>
      /// <seealso cref="DRagLint.Index.Manifest.ParseSection"/>
      /// <seealso cref="DRagLint.Index.Manifest.TDocSettings.Defaults"/>
      /// <seealso cref="DRagLint.Index.Manifest.TIndexSettings.Defaults"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function ParseTextEx(const AJson, ARootDir: string; out ASettingsKeys: TSettingsKeySet): TIndexManifest; static;

      /// <summary>Serialise AManifest to a JSON object. Caller owns the returned object and
      /// must free it. Platforms ['*'] is emitted as the bare string "all";
      /// DedupAgainst ['*'] is emitted as the bare string "*".</summary>
      /// <param name="AManifest">Manifest to serialise.</param>
      /// <returns>New TJSONObject; caller must free.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.CLI.ManifestToJson (DRagLint.CLI.pas), DRagLint.Index.Manifest.TManifestIO.Save (DRagLint.Index.Manifest.pas)</para>
      /// <para>Calls: DRagLint.Index.Manifest.ProjectsIndexingToStr</para>
      /// <para>Returns: TJSONObject.Create</para>
      /// <para>Complexity: 12 (cyclomatic, outer body), 100 lines (full implementation)</para>
      /// <para>Owns returned: new (caller owns)</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Index.Manifest.ProjectsIndexingToStr"/>
      /// <seealso cref="DRagLint.Index.Manifest.TManifestIO.Load"/>
      /// <seealso cref="DRagLint.Index.Manifest.TManifestIO.ParseText"/>
      /// <seealso cref="DRagLint.Index.Manifest.TManifestIO.ParseTextEx"/>
      /// <seealso cref="DRagLint.Index.Manifest.TManifestIO.Save"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function ToJson(const AManifest: TIndexManifest): TJSONObject; static;

      /// <summary>Serialise AManifest to a .drag-lint.json file at APath,
      /// ATOMICALLY: the full new content is written to a sibling temp file
      /// first, then swapped into place with a single filesystem replace, so
      /// an interruption (crash, kill, power loss) mid-write can never leave
      /// APath truncated or empty -- APath is either the OLD content or the
      /// NEW content, never a partial write. Written as UTF-8 WITHOUT a BOM
      /// (byte-for-byte plain ASCII when the content is all-ASCII), matching
      /// the hand-maintained file this overwrites -- see B8.</summary>
      /// <param name="AManifest">Manifest to write.</param>
      /// <param name="APath">Destination file path.</param>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.CLI.DoMigrateDbs (DRagLint.CLI.pas), DRagLint.CLI.DoSelfTestManifestSaveAtomic (DRagLint.CLI.pas)</para>
      /// <para>Calls: DRagLint.Index.Manifest.TManifestIO.ToJson, MoveFileEx, PChar</para>
      /// <para>Touches: file system</para>
      /// <seealso cref="DRagLint.Index.Manifest.TManifestIO.ToJson"/>
      /// <seealso cref="DRagLint.Index.Manifest.TManifestIO.Load"/>
      /// <seealso cref="DRagLint.Index.Manifest.TManifestIO.ParseText"/>
      /// <seealso cref="DRagLint.Index.Manifest.TManifestIO.ParseTextEx"/>
      /// <seealso cref="DRagLint.Index.Manifest.TManifestIO.Validate"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class procedure Save(const AManifest: TIndexManifest; const APath: string); static;

      /// <summary>Validate the manifest and return the first human-readable error,
      /// or '' if the manifest is valid.</summary>
      /// <param name="AManifest">Manifest to validate.</param>
      /// <returns>Empty string if valid; first error message otherwise.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.CLI.DoIndexAll (DRagLint.CLI.pas)</para>
      /// <para>Calls: DRagLint.Index.Manifest.TIndexManifest.FindSection, Format</para>
      /// <para>Returns: ''; Format('Section %d has an empty name', [I]); Format('Duplicate section name: "%s"', [Sec.Name]); Format('Section "%s" has no include paths and source is not registry-libraries', [Sec.Name]); Format('Section "%s" dedupAgainst references unknown section "%s"', [Sec.Name, DA])</para>
      /// <para>Complexity: 14 (cyclomatic, outer body), 63 lines (full implementation)</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Index.Manifest.TIndexManifest.FindSection"/>
      /// <seealso cref="DRagLint.Index.Manifest.TManifestIO.Load"/>
      /// <seealso cref="DRagLint.Index.Manifest.TManifestIO.ParseText"/>
      /// <seealso cref="DRagLint.Index.Manifest.TManifestIO.ParseTextEx"/>
      /// <seealso cref="DRagLint.Index.Manifest.TManifestIO.Save"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function Validate(const AManifest: TIndexManifest): string; static;
  end;

type
  /// <summary>Outcome of resolving a PROJECT FILE to the manifest section that
  /// owns it.</summary>
  /// <remarks>
  /// Three outcomes, not two, because the caller must be able to tell
  /// "no section owns this project" from "several claim it". Collapsing either
  /// onto a chosen DB is what made a project-scoped rebuild destructive: the
  /// wrong DB gets cleared and refilled, and the right one is never written.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Index.Manifest.pas)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TProjectDbMatch = (
    /// <summary>No section's include list names this project file.</summary>
    pdmNone,
    /// <summary>Exactly one section names it; ADb holds that section's DB.</summary>
    pdmUnique,
    /// <summary>Two or more sections name it; the caller must refuse, not choose.</summary>
    pdmAmbiguous);

/// <summary>Resolves a .dpr/.dproj PROJECT FILE to the index DB of the manifest
/// section that owns it, matching the project file EXACTLY rather than by the
/// folder it sits in.</summary>
/// <param name="AManifest">Parsed manifest. Relative include paths are expanded
/// against its RootDir; a relative section Db against its OutDir.</param>
/// <param name="AProjectFile">Absolute or relative path to the .dpr/.dproj whose
/// owning section is wanted. Compared case-insensitively after full-path
/// normalisation, so '..' segments and case differences do not defeat it.</param>
/// <param name="ADb">Receives the absolute DB path on pdmUnique; '' otherwise.
/// The file need not exist -- a section whose DB has never been built still
/// resolves, which is exactly what an indexer (a WRITER) needs.</param>
/// <param name="AClaimants">Receives the names of every section naming this
/// project: one entry on pdmUnique, two or more on pdmAmbiguous, empty on
/// pdmNone. Give these to the user verbatim; they are the manifest edit needed
/// to fix an ambiguity.</param>
/// <returns>pdmUnique, pdmNone or pdmAmbiguous.</returns>
/// <remarks>
/// Only include entries whose extension is .dpr or .dproj are
/// considered, so FOLDER sections (Library, SQL, a whole-tree union) can never
/// match here and keep whatever folder-prefix behaviour the caller applies as
/// its fallback.
/// This exists because folder-prefix matching CANNOT distinguish sibling
/// projects. Several sections legitimately share one directory
/// (ORM3\PACKAGE holds Interfaces.dproj and TestMicroniteObjects.dproj;
/// DataCopy holds DataCopy.dproj and SortTest.dproj), and a resolver that folds
/// each include down to its folder sees one identical key for all of them and
/// silently keeps whichever came first. Harmless while indexing was additive;
/// data loss once the caller passes --rebuild, which clears the whole DB.
/// Pure: no file system access, no globals. Safe to call from any thread.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.DoResolveDbsList (DRagLint.CLI.pas), DRagLint.CLI.ResolveConsumerDbs (DRagLint.CLI.pas), DRagLint.CLI.ResolveFrameworkContextDb (DRagLint.CLI.pas), DRagLint.Index.Manifest.ResolveReadDbs (DRagLint.Index.Manifest.pas), DRagLint.Index.ManifestWrite.RegisterProjectSection (DRagLint.Index.ManifestWrite.pas)</para>
/// <para>Calls: DRagLint.Index.Manifest.ExpandSectionDb, DRagLint.Index.Manifest.NormalizeProjectPath, ExtractFileExt, SameText</para>
/// <para>Returns: pdmNone; pdmUnique</para>
/// <para>Complexity: 10 (cyclomatic, outer body), 43 lines (full implementation)</para>
/// <para>Mutates: ADb (out), AClaimants (out)</para>
/// <seealso cref="DRagLint.Index.Manifest.ExpandSectionDb"/>
/// <seealso cref="DRagLint.Index.Manifest.NormalizeProjectPath"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ResolveProjectDb(const AManifest: TIndexManifest; const AProjectFile: string;
  out ADb: string; out AClaimants: TArray<string>): TProjectDbMatch;

/// <summary>Expands a section's configured output database path to an absolute path.</summary>
/// <param name="AManifest">Parsed manifest; provides RootDir and OutDir context.</param>
/// <param name="ASection">Section whose Db field is to be expanded.</param>
/// <returns>Absolute path to the section's output database file. An explicit
/// ASection.Db always wins. Otherwise, for a PROJECT section (one whose first
/// Include is a .dproj/.dpr/.dpk -- see SectionProjectFile), the default is
/// &lt;project folder&gt;\_D-RAG\&lt;project file base&gt;.sqlite. For a folder-scan
/// section, the default remains &lt;OutDir&gt;\&lt;SectionName&gt;.sqlite.</returns>
/// <remarks>
/// Handles relative paths, empty paths (defaults), and environment variable expansion.
/// Used by DB selection logic to match resolved DBs back to manifest sections.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.DoMigrateDbs (DRagLint.CLI.pas), DRagLint.CLI.DoSelfTestSectionDb (DRagLint.CLI.pas), DRagLint.CLI.LintAnchorDir (DRagLint.CLI.pas), DRagLint.Index.Manifest.ResolveFolderDb (DRagLint.Index.Manifest.pas), DRagLint.Index.Manifest.ResolveProjectDb (DRagLint.Index.Manifest.pas) (+1 more)</para>
/// <para>Calls: DRagLint.Index.Manifest.SectionProjectFile, ExpandFileName, ExtractFilePath</para>
/// <para>Touches: file system</para>
/// <seealso cref="DRagLint.Index.Manifest.SectionProjectFile"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ExpandSectionDb(const AManifest: TIndexManifest; const ASection: TIndexSection): string;

/// <summary>The project file a section is anchored to, expanded to an absolute
/// path, or '' when the section scans a folder tree instead.</summary>
/// <param name="AManifest">Parsed manifest; RootDir anchors a relative include.</param>
/// <param name="ASection">Section to inspect.</param>
/// <returns>Absolute .dproj/.dpr/.dpk path, or '' for a folder-scan section.</returns>
/// <remarks>
/// Only the FIRST include is considered. A section whose target is a
/// project indexes that project's compile closure, so a second project target
/// would be a second section -- which is how the manifest already models it.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.DoMigrateDbs (DRagLint.CLI.pas), DRagLint.CLI.LintAnchorDir (DRagLint.CLI.pas), DRagLint.Index.Manifest.ExpandSectionDb (DRagLint.Index.Manifest.pas)</para>
/// <para>Calls: ExpandFileName, ExtractFileExt, LowerCase</para>
/// <para>Touches: file system</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function SectionProjectFile(const AManifest: TIndexManifest; const ASection: TIndexSection): string;

/// <summary>Resolves any file to a section DB by FOLDER: the section whose
/// include folder is the most specific ancestor of AFilePath wins.</summary>
/// <param name="AManifest">Parsed manifest. Relative includes are expanded against
/// its RootDir.</param>
/// <param name="AFilePath">File whose covering section is wanted.</param>
/// <returns>Absolute DB path of the longest-matching section, or '' when no
/// section's include folder is an ancestor.</returns>
/// <remarks>
/// A .dpr/.dproj include is folded to ITS FOLDER here on purpose -- this
/// is the coarse fallback used for an ordinary .pas, which no exact rule can
/// place. Ties go to the FIRST section (the comparison is a strict '&gt;'), which
/// is precisely why this must not be the only rule once two projects share a
/// folder: see ResolveProjectDb and ResolveReadDbs.
/// Pure: no file system access. Safe to call from any thread.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Index.Manifest.ResolveReadDbs (DRagLint.Index.Manifest.pas)</para>
/// <para>Calls: DRagLint.Index.Manifest.ExpandSectionDb, ExpandFileName, ExtractFileExt, ExtractFilePath, IncludeTrailingPathDelimiter, LowerCase, Pos, SameText</para>
/// <para>Returns: ''; ExpandSectionDb(AManifest, Sec)</para>
/// <para>Complexity: 13 (cyclomatic, outer body), 39 lines (full implementation)</para>
/// <para>Touches: file system</para>
/// <seealso cref="DRagLint.Index.Manifest.ExpandSectionDb"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ResolveFolderDb(const AManifest: TIndexManifest; const AFilePath: string): string;

/// <summary>Ordered list of DBs a READER (hover, Find Usages, LSP) should open
/// for AEditorFile, preferring the index of the ACTIVE PROJECT.</summary>
/// <param name="AManifest">Parsed manifest.</param>
/// <param name="AActiveProjectFile">The .dproj currently active in the IDE, or ''
/// when none is. Resolved with ResolveProjectDb, so only an unambiguous owner
/// counts.</param>
/// <param name="AEditorFile">The file being edited/queried; may be ''.</param>
/// <returns>Up to two paths: the active project's DB first (when it resolves
/// uniquely), then the folder-matched DB for AEditorFile when that is different.
/// Either may be absent; the result may be empty.</returns>
/// <remarks>
/// ORDER IS THE ANSWER, and both entries earn their place.
/// The active project comes FIRST because the editor file alone cannot decide:
/// ORM3's COMMON\ units belong to BOTH the client and the server project, so a
/// folder rule answers such a file from whichever section happens to be listed
/// first, no matter what the developer is actually building. The active project
/// is the only signal available here that says which of several equally valid
/// answers is the wanted one.
/// The folder match is KEPT, not replaced, because the editor file is often
/// outside the active project entirely -- browsing library or third-party source
/// with a project open is routine. Dropping it would trade wrong answers for no
/// answers on exactly those files. A reader passes both to the engine and the
/// first DB that can answer does.
/// Deliberately NOT file-to-project membership, which is the fully correct key
/// and needs the index to say which project claims a given .pas. That is a
/// larger mechanism and its own task; the active project gets the common case
/// right at a fraction of the cost.
/// Pure: no file system access. Safe to call from any thread.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.DoResolveDbsList (DRagLint.CLI.pas)</para>
/// <para>Calls: DRagLint.Index.Manifest.ResolveFolderDb, DRagLint.Index.Manifest.ResolveProjectDb, SameText</para>
/// <para>Pure</para>
/// <seealso cref="DRagLint.Index.Manifest.ResolveFolderDb"/>
/// <seealso cref="DRagLint.Index.Manifest.ResolveProjectDb"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ResolveReadDbs(const AManifest: TIndexManifest;
  const AActiveProjectFile, AEditorFile: string): TArray<string>;

type
  /// <summary>"Does the index at ADbPath contain a files row for AFilePath?"</summary>
  /// <param name="ADbPath"><!-- drag-lint:auto type -->const string</param>
  /// <param name="AFilePath"><!-- drag-lint:auto type -->const string</param>
  /// <returns><!-- drag-lint:auto type -->Boolean</returns>
  /// <remarks>
  /// A callback so the ordering rules stay pure and testable while the
  /// actual SQL lives with the storage layer. Implementations must normalise both
  /// sides the way the store does (DRagLint.Storage.FileMembership.DbContainsFile
  /// is the real one).
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Index.Manifest.pas)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TDbContainsFileFunc = reference to function(const ADbPath, AFilePath: string): Boolean;

/// <summary>Reorders candidate DBs so the ones that ACTUALLY CONTAIN AFilePath
/// come first, with AActiveProjectDb winning ties.</summary>
/// <param name="ACandidates">Candidate DBs in preference order (typically the
/// output of ResolveReadDbs). Returned unchanged when nothing contains the
/// file.</param>
/// <param name="AActiveProjectDb">The active project's DB, used ONLY to break
/// ties between DBs that all contain the file. May be ''.</param>
/// <param name="AFilePath">The open file whose owning index is wanted.</param>
/// <param name="AContains">Membership probe; when nil the candidates are
/// returned unchanged.</param>
/// <returns>A permutation of ACandidates -- same members, never fewer. Callers
/// that read only Result[0] get the DB that can actually answer.</returns>
/// <remarks>
/// WHY MEMBERSHIP AND NOT "WHICH PROJECT IS ACTIVE".
/// Preferring the active project (the previous rule) is right for a file INSIDE
/// that project and wrong for every other file. Most consumers pass the whole
/// list to the engine and are unharmed, but a consumer that reads only the first
/// entry -- TDragLintStructureForm.ResolveDbForFile -- then queries an index that
/// does not contain the open file at all, and gets silence rather than an error.
/// "Callers tolerate an extra DB" only holds for callers that read more than one.
/// The active project stays as the TIEBREAK because membership genuinely is not
/// unique: ORM3's COMMON\ units belong to the client AND the server closure, so
/// two DBs legitimately contain the same file and something has to choose.
/// Order is otherwise STABLE, so the existing preference survives among equals
/// and the no-match case is byte-identical to the old behaviour -- which is what
/// keeps library-source browsing working.
/// Pure apart from AContains. Cost is one probe per candidate (small list).
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.DoResolveDbsList (DRagLint.CLI.pas), DRagLint.CLI.ResolveConsumerDbs (DRagLint.CLI.pas)</para>
/// <para>Calls: AContains, SameText</para>
/// <para>Returns: ACandidates; Holders + Others</para>
/// <para>Complexity: 11 (cyclomatic, outer body), 49 lines (full implementation)</para>
/// <para>Pure</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function OrderDbsByMembership(const ACandidates: TArray<string>;
  const AActiveProjectDb, AFilePath: string;
  const AContains: TDbContainsFileFunc): TArray<string>;

/// <summary>Reads the docs.complexity_min threshold used by the doc/hover
/// verbs (`document --qname/--unit/--project`, `document-all`, and
/// `hover`). Gates the 'Complexity:' line at RENDER time (v(ADP2 T3) in
/// DRagLint.Doc.Regions.TDocRegions.RenderFactsBlock/FormatPhase2FactLines --
/// v(ADP2 T9) for hover's call) -- changing this value never needs a
/// reindex, since the raw Cyclomatic/BodyLoc values already live in the
/// index and only this display gate changes. Loads the manifest the same
/// way every other doc-verb loader does (engine dir beside the exe, current
/// working dir walking up for a local .drag-lint.json override). Lives here
/// (not in DRagLint.CLI, where earlier Phase 2 tasks first added it) so
/// BOTH DRagLint.CLI.DoHover and DRagLint.LSP.Server.HandleHover can load
/// the identical threshold `document` uses -- the LSP server does not (and
/// must not, to avoid a unit cycle) depend on the CLI unit.</summary>
/// <returns>The configured docs.complexity_min value. Best-effort: any load
/// failure (missing files, malformed JSON) falls back to 10
/// (TDocSettings.Defaults.ComplexityMin), so a doc/hover verb never errors
/// out over a manifest problem.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Calls: DRagLint.Index.Manifest.TManifestIO.Load, ExtractFilePath, ParamStr</para>
/// <para>Returns: 10; DocManifest.Docs.ComplexityMin</para>
/// <para>Pure</para>
/// <seealso cref="DRagLint.Index.Manifest.TManifestIO.Load"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function LoadDocComplexityMin: Integer;

implementation

uses
  Winapi.Windows   { MoveFileEx / MOVEFILE_REPLACE_EXISTING -- TManifestIO.Save's atomic swap }
  , DRagLint.Core.Model
  ;

{ ---------------------------------------------------------------------- }
{  Helpers                                                                 }
{ ---------------------------------------------------------------------- }

function JsonStrArr(const AArr: TJSONArray): TArray<string>;
var
  I: Integer;
begin
  if AArr = nil then
  begin
    Result:= nil;
    Exit;
  end;
  SetLength(Result, AArr.Count);
  for I:= 0 to AArr.Count - 1 do Result[I]:= AArr.Items[I].Value;
end;

{ Accept either a bare string or an array of strings.
  The string "all" or "*" maps to ['*']. }
function ParseStringOrArray(const AVal: TJSONValue): TArray<string>;
var
  S: string;
begin
  Result:= nil;
  if AVal = nil then Exit;
  if AVal is TJSONArray then
  begin
    Result:= JsonStrArr(TJSONArray(AVal));
    Exit;
  end;
  S:= AVal.Value;
  if (S = 'all') or (S = '*') then Result:= ['*']
  else Result:= [S];
end;

function ParseProjectsIndexing(const S: string): TProjectsIndexing;
begin
  if SameText(S, 'perGroup') then Result:= piPerGroup
  else if SameText(S, 'single') then Result:= piSingle
  else Result:= piPerProject;
end;

function ProjectsIndexingToStr(const V: TProjectsIndexing): string;
begin
  case V of
    piPerGroup: Result:= 'perGroup';
    piSingle  : Result:= 'single';
    else Result:= 'perProject';
  end;
end;

function ParseSection(const AObj: TJSONObject): TIndexSection;
var
  V: TJSONValue;
  B: TJSONBool ;
begin
  Result:= Default(TIndexSection);
  Result.UseIgnoreFiles:= True;
  Result.SqlOnlyMS     := True;

  V:= AObj.GetValue('name');
  if V <> nil then Result.Name:= V.Value;

  V:= AObj.GetValue('db');
  if V <> nil then Result.Db:= V.Value;

  V:= AObj.GetValue('source');
  if V <> nil then Result.Source:= V.Value;

  V:= AObj.GetValue('platforms');
  if V <> nil then Result.Platforms:= ParseStringOrArray(V);

  V:= AObj.GetValue('include');
  if V is TJSONArray then Result.Include:= JsonStrArr(TJSONArray(V))
  else if (V <> nil) then Result.Include:= [V.Value];

  V:= AObj.GetValue('exclude');
  if V is TJSONArray then Result.Exclude:= JsonStrArr(TJSONArray(V))
  else if (V <> nil) then Result.Exclude:= [V.Value];

  V:= AObj.GetValue('includeOnly');
  if V is TJSONArray then Result.IncludeOnly:= JsonStrArr(TJSONArray(V))
  else if (V <> nil) then Result.IncludeOnly:= [V.Value];

  { useIgnoreFiles: accept also legacy 'useGitignore' key (back-compat) }
  B:= AObj.GetValue('useIgnoreFiles') as TJSONBool;
  if B <> nil then Result.UseIgnoreFiles:= B.AsBoolean
  else
  begin
    B:= AObj.GetValue('useGitignore') as TJSONBool;
    if B <> nil then Result.UseIgnoreFiles:= B.AsBoolean;
  end;

  V:= AObj.GetValue('dedupAgainst');
  if V <> nil then Result.DedupAgainst:= ParseStringOrArray(V);

  B:= AObj.GetValue('sqlOnlyMS') as TJSONBool;
  if B <> nil then Result.SqlOnlyMS:= B.AsBoolean;
end; // function

{ ---------------------------------------------------------------------- }
{  TIndexSettings                                                          }
{ ---------------------------------------------------------------------- }

class function TIndexSettings.Defaults: TIndexSettings;
begin
  Result:= Default(TIndexSettings);
  Result.CurrentProjectsIndexing:= piPerProject;
  Result.DefaultPlatform        := 'Win32';
  Result.SizeGuardMB            := 1500;
  Result.EnginePath             := 'auto';
  Result.MaxJobs                := 0;
  Result.MaxParseFileKB         := 2048;
end;

{ ---------------------------------------------------------------------- }
{  TDocSettings                                                            }
{ ---------------------------------------------------------------------- }

class function TDocSettings.Defaults: TDocSettings;
begin
  Result:= Default(TDocSettings);
  Result.MaxReturnCases          := 20;
  Result.MaxCallers              := 5;
  Result.AccessorTrivialMaxLines := 2;  // ADP1 T2: ON by default (see field comment).
  Result.ComplexityMin           := 10; // ADP2 T3: see field comment.
end;

{ ---------------------------------------------------------------------- }
{  TIndexManifest                                                          }
{ ---------------------------------------------------------------------- }

function TIndexManifest.FindSection(const AName: string; out ASection: TIndexSection): Boolean;
var
  I: Integer;
begin
  for I:= 0 to High(Sections) do
    if SameText(Sections[I].Name, AName) then
    begin
      ASection:= Sections[I];
      Exit(True);
    end;
  Result:= False;
  ASection:= Default(TIndexSection);
end;

{ ---------------------------------------------------------------------- }
{  TManifestIO.ParseTextEx                                                 }
{ ---------------------------------------------------------------------- }

class function TManifestIO.ParseTextEx(const AJson, ARootDir: string; out ASettingsKeys: TSettingsKeySet): TIndexManifest;
var
  Root     : TJSONObject;
  JSettings: TJSONObject;
  JIndexes : TJSONObject;
  JSections: TJSONArray ;
  V        : TJSONValue ;
  N        : TJSONNumber;
  I        : Integer    ;
begin
  Result:= Default(TIndexManifest);
  Result.RootDir:= ARootDir;
  Result.Settings:= TIndexSettings.Defaults;
  Result.Docs:= TDocSettings.Defaults;
  ASettingsKeys:= [];

  Root:= TJSONObject.ParseJSONValue(AJson) as TJSONObject;
  if Root = nil then Exit;
  try
    { -- settings block -- }
    JSettings:= Root.GetValue('settings') as TJSONObject;
    if JSettings <> nil then
    begin
      V:= JSettings.GetValue('currentProjectsIndexing');
      if (V <> nil) and (V.Value <> '') then
      begin
        Result.Settings.CurrentProjectsIndexing:= ParseProjectsIndexing(V.Value);
        Include(ASettingsKeys, skCurrentProjectsIndexing);
      end;

      V:= JSettings.GetValue('defaultPlatform');
      if (V <> nil) and (V.Value <> '') then
      begin
        Result.Settings.DefaultPlatform:= V.Value;
        Include(ASettingsKeys, skDefaultPlatform);
      end;

      N:= JSettings.GetValue('sizeGuardMB') as TJSONNumber;
      if N <> nil then
      begin
        Result.Settings.SizeGuardMB:= N.AsInt;
        Include(ASettingsKeys, skSizeGuardMB);
      end;

      V:= JSettings.GetValue('enginePath');
      if (V <> nil) and (V.Value <> '') then
      begin
        Result.Settings.EnginePath:= V.Value;
        Include(ASettingsKeys, skEnginePath);
      end;

      N:= JSettings.GetValue('maxJobs') as TJSONNumber;
      if N <> nil then
      begin
        Result.Settings.MaxJobs:= N.AsInt;
        Include(ASettingsKeys, skMaxJobs);
      end;

      N:= JSettings.GetValue('maxParseFileKB') as TJSONNumber;
      if N <> nil then
      begin
        { 0 in JSON means "use default 2048"; a negative value disables the
          guard (unlimited). CLI --max-file-kb 0 overrides to unlimited after
          this is applied. }
        var KB:= N.AsInt;
        if KB = 0 then KB:= 2048;
        Result.Settings.MaxParseFileKB:= KB;
        Include(ASettingsKeys, skMaxParseFileKB);
      end;
    end; // if

    { -- docs block -- }
    var JDocs: TJSONObject:= Root.GetValue('docs') as TJSONObject;
    if JDocs <> nil then
    begin
      var ND: TJSONNumber:= JDocs.GetValue('max_return_cases') as TJSONNumber;
      if ND <> nil then
      begin
        Result.Docs.MaxReturnCases:= ND.AsInt;
        Include(ASettingsKeys, skMaxReturnCases);
      end;

      var NC: TJSONNumber:= JDocs.GetValue('max_callers') as TJSONNumber;
      if NC <> nil then
      begin
        Result.Docs.MaxCallers:= NC.AsInt;
        Include(ASettingsKeys, skMaxCallers);
      end;

      // ADP1 T2: docs.accessor_trivial_max_lines -- OVERRIDES the code
      // default of 2 when present; absent leaves Result.Docs.AccessorTrivialMaxLines
      // at the Defaults() value already seeded above (the filter stays ON).
      var NA: TJSONNumber:= JDocs.GetValue('accessor_trivial_max_lines') as TJSONNumber;
      if NA <> nil then
      begin
        Result.Docs.AccessorTrivialMaxLines:= NA.AsInt;
        Include(ASettingsKeys, skAccessorTrivialMaxLines);
      end;

      // ADP2 T3: docs.complexity_min -- OVERRIDES the code default of 10 when
      // present; absent leaves Result.Docs.ComplexityMin at the Defaults()
      // value already seeded above.
      var NCx: TJSONNumber:= JDocs.GetValue('complexity_min') as TJSONNumber;
      if NCx <> nil then
      begin
        Result.Docs.ComplexityMin:= NCx.AsInt;
        Include(ASettingsKeys, skComplexityMin);
      end;
    end;

    { -- indexes block -- }
    JIndexes:= Root.GetValue('indexes') as TJSONObject;
    if JIndexes <> nil then
    begin
      V:= JIndexes.GetValue('outDir');
      if (V <> nil) and (V.Value <> '') then Result.OutDir:= V.Value;

      V:= JIndexes.GetValue('exclude');
      if V is TJSONArray then Result.GlobalExclude:= JsonStrArr(TJSONArray(V));

      JSections:= JIndexes.GetValue('sections') as TJSONArray;
      if JSections <> nil then
      begin
        SetLength(Result.Sections, JSections.Count);
        for I:= 0 to JSections.Count - 1 do
          if JSections.Items[I] is TJSONObject then Result.Sections[I]:= ParseSection(TJSONObject(JSections.Items[I]));
      end;
    end; // if
  finally
    Root.Free;
  end; // try
end; // function

{ ---------------------------------------------------------------------- }
{  TManifestIO.ParseText                                                   }
{ ---------------------------------------------------------------------- }

class function TManifestIO.ParseText(const AJson, ARootDir: string): TIndexManifest;
var
  Keys: TSettingsKeySet;
begin
  Result:= ParseTextEx(AJson, ARootDir, Keys);
end;

{ ---------------------------------------------------------------------- }
{  TManifestIO.Load                                                        }
{ ---------------------------------------------------------------------- }

class function TManifestIO.Load(const AEngineDir, AStartDir: string): TIndexManifest;
var
  GlobalPath    : string         ;
  LocalPath     : string         ;
  GlobalManifest: TIndexManifest ;
  LocalManifest : TIndexManifest ;
  LocalKeys     : TSettingsKeySet;
  Content       : string         ;
  HaveGlobal    : Boolean        ;
  HaveLocal     : Boolean        ;
  Dir           : string         ;
  Parent        : string         ;

  procedure MergeSections(var ADest: TIndexManifest; const ASrc: TIndexManifest);
  var
    K       : Integer;
    L       : Integer;
    MatchIdx: Integer;
  begin
    for K:= 0 to High(ASrc.Sections) do
    begin
      MatchIdx:= -1;
      for L:= 0 to High(ADest.Sections) do
        if SameText(ADest.Sections[L].Name, ASrc.Sections[K].Name) then
        begin
          MatchIdx:= L;
          Break;
        end;
      if MatchIdx >= 0 then ADest.Sections[MatchIdx]:= ASrc.Sections[K]
      else
      begin
        SetLength(ADest.Sections, Length(ADest.Sections) + 1);
        ADest.Sections[High(ADest.Sections)]:= ASrc.Sections[K];
      end;
    end; // for
  end; // procedure

begin
  Result:= Default(TIndexManifest);
  HaveGlobal:= False;
  HaveLocal := False;
  LocalKeys:= [];

  { Try global: <AEngineDir>\drag-lint.json (no leading dot -- the EXE-side config) }
  GlobalPath:= TPath.Combine(AEngineDir, 'drag-lint.json');
  if TFile.Exists(GlobalPath) then
  begin
    try
      Content:= TFile.ReadAllText(GlobalPath);
      GlobalManifest:= ParseText(Content, AEngineDir);
      HaveGlobal:= True;
    except
      on E: Exception do Writeln(ErrOutput, 'WARNING: could not parse config at ', GlobalPath, ': ', E.Message);
    end;
  end;

  { Try local: walk AStartDir .. root for .drag-lint.json }
  LocalPath:= '';
  Dir:= TPath.GetFullPath(AStartDir);
  while Dir <> '' do
  begin
    var Candidate:= TPath.Combine(Dir, '.drag-lint.json');
    if TFile.Exists(Candidate) then
    begin
      LocalPath:= Candidate;
      Break;
    end;
    Parent:= TPath.GetDirectoryName(Dir);
    if (Parent = '') or (Parent = Dir) then Break;
    Dir:= Parent;
  end;

  if LocalPath <> '' then
  begin
    try
      Content:= TFile.ReadAllText(LocalPath);
      LocalManifest:= ParseTextEx(Content, TPath.GetDirectoryName(LocalPath), LocalKeys);
      HaveLocal:= True;
    except
      on E: Exception do Writeln(ErrOutput, 'WARNING: could not parse config at ', LocalPath, ': ', E.Message);
    end;
  end;

  if HaveGlobal and HaveLocal then
  begin
    { Merge: start from global, override with local scalars only when present,
      append local GlobalExclude (additive), then sections }
    Result:= GlobalManifest;
    if LocalManifest.OutDir <> '' then Result.OutDir:= LocalManifest.OutDir;
    { GlobalExclude: APPEND local to global (additive -- local excludes do not
      replace global ones; both apply after merge) }
    if Length(LocalManifest.GlobalExclude) > 0 then
    begin
      var OldLen:= Length(Result.GlobalExclude);
      SetLength(Result.GlobalExclude, OldLen + Length(LocalManifest.GlobalExclude));
      for var K:= 0 to High(LocalManifest.GlobalExclude) do Result.GlobalExclude[OldLen + K]:= LocalManifest.GlobalExclude[K];
    end;
    { Settings: local scalars override ONLY when the key was present in the local file }
    if skDefaultPlatform         in LocalKeys then Result.Settings.DefaultPlatform        := LocalManifest.Settings.DefaultPlatform;
    if skEnginePath              in LocalKeys then Result.Settings.EnginePath             := LocalManifest.Settings.EnginePath;
    if skSizeGuardMB             in LocalKeys then Result.Settings.SizeGuardMB            := LocalManifest.Settings.SizeGuardMB;
    if skMaxJobs                 in LocalKeys then Result.Settings.MaxJobs                := LocalManifest.Settings.MaxJobs;
    if skCurrentProjectsIndexing in LocalKeys then Result.Settings.CurrentProjectsIndexing:= LocalManifest.Settings.CurrentProjectsIndexing;
    if skMaxParseFileKB          in LocalKeys then Result.Settings.MaxParseFileKB         := LocalManifest.Settings.MaxParseFileKB;
    // Docs.* merges PER FIELD (like every Settings.* line above), not as one
    // whole-record copy: a local .drag-lint.json that overrides ONLY
    // max_callers (say) must not silently reset max_return_cases back to
    // LocalManifest's own default -- each key overrides independently.
    if skMaxReturnCases          in LocalKeys then Result.Docs.MaxReturnCases            := LocalManifest.Docs.MaxReturnCases;
    if skMaxCallers              in LocalKeys then Result.Docs.MaxCallers                := LocalManifest.Docs.MaxCallers;
    if skAccessorTrivialMaxLines in LocalKeys then Result.Docs.AccessorTrivialMaxLines   := LocalManifest.Docs.AccessorTrivialMaxLines;
    if skComplexityMin           in LocalKeys then Result.Docs.ComplexityMin             := LocalManifest.Docs.ComplexityMin;
    Result.RootDir:= LocalManifest.RootDir;
    MergeSections(Result, LocalManifest);
  end // if
  else if HaveLocal  then Result:= LocalManifest
  else if HaveGlobal then Result:= GlobalManifest
  else
  begin
    { Neither found: return defaults. Docs must be defaulted explicitly here too
      (Task 10 bugfix) -- Result started as Default(TIndexManifest) above, which
      zero-fills Docs.MaxReturnCases to 0 (enumeration disabled); every OTHER
      branch (HaveLocal, HaveGlobal, both) gets Docs from a ParseText/ParseTextEx
      call that already sets Result.Docs:= TDocSettings.Defaults, so only this
      neither-found fallback was missing it. }
    Result.Settings:= TIndexSettings.Defaults;
    Result.Docs:= TDocSettings.Defaults;
    Result.RootDir:= AStartDir;
  end;
end; // begin

{ ---------------------------------------------------------------------- }
{  TManifestIO.Validate                                                    }
{ ---------------------------------------------------------------------- }

class function TManifestIO.Validate(const AManifest: TIndexManifest): string;
var
  Names: TStringList  ;
  I    : Integer      ;
  Sec  : TIndexSection;
  DA   : string       ;
  Found: Boolean      ;
  DSec : TIndexSection;
begin
  Result:= '';
  if AManifest.Docs.MaxReturnCases < 0 then Exit('docs.max_return_cases must be >= 0');
  if AManifest.Docs.MaxCallers < 0 then Exit('docs.max_callers must be >= 0');
  if AManifest.Docs.AccessorTrivialMaxLines < 0 then Exit('docs.accessor_trivial_max_lines must be >= 0');
  if AManifest.Docs.ComplexityMin < 0 then Exit('docs.complexity_min must be >= 0');
  Names:= TStringList.Create;
  Names.CaseSensitive:= False;
  try
    { Each section must have a non-empty unique name }
    for I:= 0 to High(AManifest.Sections) do
    begin
      Sec:= AManifest.Sections[I];
      if Sec.Name = '' then
      begin
        Result:= Format('Section %d has an empty name', [I]);
        Exit;
      end;
      if Names.IndexOf(Sec.Name) >= 0 then
      begin
        Result:= Format('Duplicate section name: "%s"', [Sec.Name]);
        Exit;
      end;
      Names.Add(Sec.Name);
    end;

    { Each section must have either Include paths or Source='registry-libraries' }
    for I:= 0 to High(AManifest.Sections) do
    begin
      Sec:= AManifest.Sections[I];
      if (Sec.Source <> 'registry-libraries') and (Length(Sec.Include) = 0) then
      begin
        Result:= Format('Section "%s" has no include paths and source is not registry-libraries', [Sec.Name]);
        Exit;
      end;
    end;

    { Every dedupAgainst name (other than '*') must resolve to a known section }
    for I:= 0 to High(AManifest.Sections) do
    begin
      Sec:= AManifest.Sections[I];
      for DA in Sec.DedupAgainst do
      begin
        if DA = '*' then Continue;
        Found:= AManifest.FindSection(DA, DSec);
        if not Found then
        begin
          Result:= Format('Section "%s" dedupAgainst references unknown section "%s"', [Sec.Name, DA]);
          Exit;
        end;
      end;
    end;
  finally
    Names.Free;
  end; // try
end; // function

{ ---------------------------------------------------------------------- }
{  TManifestIO.ToJson                                                      }
{ ---------------------------------------------------------------------- }

class function TManifestIO.ToJson(const AManifest: TIndexManifest): TJSONObject;
var
  JSettings  : TJSONObject  ;
  JIndexes   : TJSONObject  ;
  JSections  : TJSONArray   ;
  JExclude   : TJSONArray   ;
  JInclude   : TJSONArray   ;
  JSecExclude: TJSONArray   ;
  JIncOnly   : TJSONArray   ;
  JPlats     : TJSONArray   ;
  JDedup     : TJSONArray   ;
  Sec        : TIndexSection;
  S          : string       ;
begin
  Result:= TJSONObject.Create;

  { settings }
  JSettings:= TJSONObject.Create;
  Result.AddPair('settings', JSettings);
  JSettings.AddPair('currentProjectsIndexing', ProjectsIndexingToStr(AManifest.Settings.CurrentProjectsIndexing));
  JSettings.AddPair('defaultPlatform', AManifest.Settings.DefaultPlatform);
  JSettings.AddPair('sizeGuardMB', TJSONNumber.Create(AManifest.Settings.SizeGuardMB));
  JSettings.AddPair('enginePath', AManifest.Settings.EnginePath);
  JSettings.AddPair('maxJobs'       , TJSONNumber.Create(AManifest.Settings.MaxJobs       ));
  JSettings.AddPair('maxParseFileKB', TJSONNumber.Create(AManifest.Settings.MaxParseFileKB));

  { docs }
  var JDocs:= TJSONObject.Create;
  Result.AddPair('docs', JDocs);
  JDocs.AddPair('max_return_cases', TJSONNumber.Create(AManifest.Docs.MaxReturnCases));
  JDocs.AddPair('max_callers', TJSONNumber.Create(AManifest.Docs.MaxCallers));
  JDocs.AddPair('accessor_trivial_max_lines', TJSONNumber.Create(AManifest.Docs.AccessorTrivialMaxLines));
  JDocs.AddPair('complexity_min', TJSONNumber.Create(AManifest.Docs.ComplexityMin));

  { indexes }
  JIndexes:= TJSONObject.Create;
  Result.AddPair('indexes', JIndexes);
  JIndexes.AddPair('outDir', AManifest.OutDir);

  JExclude:= TJSONArray.Create;
  JIndexes.AddPair('exclude', JExclude);
  for S in AManifest.GlobalExclude do JExclude.AddElement(TJSONString.Create(S));

  JSections:= TJSONArray.Create;
  JIndexes.AddPair('sections', JSections);
  for Sec in AManifest.Sections do
  begin
    var JSecObj:= TJSONObject.Create;
    JSections.AddElement(JSecObj);
    JSecObj.AddPair('name', Sec.Name);
    if Sec.Db     <> '' then JSecObj.AddPair('db'    , Sec.Db    );
    if Sec.Source <> '' then JSecObj.AddPair('source', Sec.Source);

    if Length(Sec.Platforms) > 0 then
    begin
      if (Length(Sec.Platforms) = 1) and (Sec.Platforms[0] = '*') then JSecObj.AddPair('platforms', 'all')
      else
      begin
        JPlats:= TJSONArray.Create;
        JSecObj.AddPair('platforms', JPlats);
        for S in Sec.Platforms do JPlats.AddElement(TJSONString.Create(S));
      end;
    end;

    if Length(Sec.Include) > 0 then
    begin
      JInclude:= TJSONArray.Create;
      JSecObj.AddPair('include', JInclude);
      for S in Sec.Include do JInclude.AddElement(TJSONString.Create(S));
    end;

    if Length(Sec.Exclude) > 0 then
    begin
      JSecExclude:= TJSONArray.Create;
      JSecObj.AddPair('exclude', JSecExclude);
      for S in Sec.Exclude do JSecExclude.AddElement(TJSONString.Create(S));
    end;

    if Length(Sec.IncludeOnly) > 0 then
    begin
      JIncOnly:= TJSONArray.Create;
      JSecObj.AddPair('includeOnly', JIncOnly);
      for S in Sec.IncludeOnly do JIncOnly.AddElement(TJSONString.Create(S));
    end;

    JSecObj.AddPair('useIgnoreFiles', TJSONBool.Create(Sec.UseIgnoreFiles));

    if Length(Sec.DedupAgainst) > 0 then
    begin
      if (Length(Sec.DedupAgainst) = 1) and (Sec.DedupAgainst[0] = '*') then JSecObj.AddPair('dedupAgainst', '*')
      else
      begin
        JDedup:= TJSONArray.Create;
        JSecObj.AddPair('dedupAgainst', JDedup);
        for S in Sec.DedupAgainst do JDedup.AddElement(TJSONString.Create(S));
      end;
    end;

    JSecObj.AddPair('sqlOnlyMS', TJSONBool.Create(Sec.SqlOnlyMS));
  end; // for
end; // function

{ ---------------------------------------------------------------------- }
{  TManifestIO.Save                                                        }
{ ---------------------------------------------------------------------- }

class procedure TManifestIO.Save(const AManifest: TIndexManifest; const APath: string);
var
  Root    : TJSONObject;
  JsonText: string     ;
  TmpPath : string     ;
begin
  Root:= ToJson(AManifest);
  try
    JsonText:= Root.Format(2);
  finally
    Root.Free;
  end;
  { Atomic write. migrate-dbs calls this once per section moved -- up to 27
    times in one unattended run -- against the user's real, hand-maintained
    manifest. A plain TFile.WriteAllText TRUNCATES APath before writing a
    byte of the new content, so an interruption mid-write (a crash, a kill, a
    power loss) would leave drag-lint.json truncated or empty, losing every
    section's mapping, not just the one being saved right now. Write the full
    new content to a sibling temp file first (nothing yet depends on it),
    then swap it into place with ONE atomic filesystem operation: a
    MoveFileEx rename with MOVEFILE_REPLACE_EXISTING, which either fully
    succeeds or leaves the ORIGINAL file completely untouched -- there is no
    observable half-written state either way, whether or not APath already
    exists (the same call handles the very first save too). NOT TFile.Replace:
    its Delphi wrapper unconditionally runs its backup-filename parameter
    through TPath.GetFullPath, which raises EInOutArgumentException on an
    empty string -- there is no way to ask it for "no backup" even though the
    underlying Win32 ReplaceFile supports that directly (a NULL backup
    pointer), so the wrapper cannot be used without leaving a stray .bak
    file behind on every single save. MoveFileEx needs no backup at all. }
  { B8 (this repo's own recorded fix, see DoLintAll): GetBytes, not
    WriteAllText(..., TEncoding.UTF8). TEncoding.UTF8 carries a PREAMBLE, and
    WriteAllText emits it, so a hand-maintained drag-lint.json a real user
    edits -- and that other, non-Delphi tooling (jq, a strict JSON parser)
    reads -- would open with EF BB BF at byte 0. TFile.ReadAllText silently
    skips a BOM on the way back in, which is exactly why this went unnoticed
    from inside drag-lint itself. GetBytes returns the same UTF-8 WITHOUT the
    preamble: a manifest that needs a non-ASCII character (an accented path)
    still round-trips as UTF-8, while the ordinary all-ASCII manifest stays
    byte-for-byte plain ASCII, matching the file the user started with. }
  TmpPath:= APath + '.tmp';
  TFile.WriteAllBytes(TmpPath, TEncoding.UTF8.GetBytes(JsonText));
  try
    if not MoveFileEx(PChar(TmpPath), PChar(APath), MOVEFILE_REPLACE_EXISTING or MOVEFILE_WRITE_THROUGH) then
      RaiseLastOSError;
  except
    if TFile.Exists(TmpPath) then TFile.Delete(TmpPath);
    raise;
  end;
end;

{ ---------------------------------------------------------------------- }
{  ResolveProjectDb                                                        }
{ ---------------------------------------------------------------------- }

{ Case-folded absolute form of APath, with a relative path first anchored to
  ABaseDir (NOT the process CWD -- manifest includes are documented relative to
  RootDir, and a resolver whose answer depended on the caller's current
  directory would be non-deterministic). ExpandFileName rather than
  TPath.GetFullPath because it collapses '..' segments without raising on a
  malformed path -- there is nothing useful to do with such an exception here
  except swallow it, and swallowing is what this codebase's own lint forbids. }
function NormalizeProjectPath(const APath, ABaseDir: string): string;
var
  P: string;
begin
  Result:= '';
  if APath = '' then Exit;
  P:= APath;
  if TPath.IsRelativePath(P) and (ABaseDir <> '') then P:= TPath.Combine(ABaseDir, P);
  Result:= LowerCase(ExpandFileName(P));
end;

function SectionProjectFile(const AManifest: TIndexManifest; const ASection: TIndexSection): string;
var
  Ext: string;
begin
  Result:= '';
  if Length(ASection.Include) = 0 then Exit;
  Result:= ASection.Include[0];
  if Result = '' then Exit;
  if TPath.IsRelativePath(Result) and (AManifest.RootDir <> '') then
    Result:= TPath.Combine(AManifest.RootDir, Result);
  Result:= ExpandFileName(Result);
  Ext   := LowerCase(ExtractFileExt(Result));
  if (Ext <> '.dproj') and (Ext <> '.dpr') and (Ext <> '.dpk') then Result:= '';
end;

function ExpandSectionDb(const AManifest: TIndexManifest; const ASection: TIndexSection): string;
var
  OutBase : string;
  ProjFile: string;
begin
  Result:= ASection.Db;
  { An omitted Db on a PROJECT section resolves to that project's own _D-RAG
    home, named after the PROJECT FILE. Not the folder and not the section name:
    five folders here host two or three projects (YADF, YADFOT and YADFSetup all
    live in C:\Projects\YADF), so a folder-derived name would collide.
    An explicit Db still wins -- the escape hatch for a read-only or network
    source tree that cannot host a database. }
  if Result = '' then
  begin
    ProjFile:= SectionProjectFile(AManifest, ASection);
    if ProjFile <> '' then
      Exit(TPath.Combine(TPath.Combine(ExtractFilePath(ProjFile), DRAG_HOME_DIR),
                         TPath.GetFileNameWithoutExtension(ProjFile) + '.sqlite'));
    Result:= ASection.Name + '.sqlite';
  end;
  if not TPath.IsRelativePath(Result) then Exit(ExpandFileName(Result));
  OutBase:= AManifest.OutDir;
  if OutBase = '' then OutBase:= AManifest.RootDir
  else if TPath.IsRelativePath(OutBase) then OutBase:= TPath.Combine(AManifest.RootDir, OutBase);
  Result:= ExpandFileName(TPath.Combine(OutBase, Result));
end;

function ResolveProjectDb(const AManifest: TIndexManifest; const AProjectFile: string;
  out ADb: string; out AClaimants: TArray<string>): TProjectDbMatch;
var
  Target : string       ;
  FoundDb: string       ;
  Ext    : string       ;
  Sec    : TIndexSection;
  I      : Integer      ;
  J      : Integer      ;
begin
  ADb       := '';
  AClaimants:= nil;
  Result    := pdmNone;
  if AProjectFile = '' then Exit;

  Target := NormalizeProjectPath(AProjectFile, '');
  FoundDb:= '';

  for I:= 0 to High(AManifest.Sections) do
  begin
    Sec:= AManifest.Sections[I];
    for J:= 0 to High(Sec.Include) do
    begin
      { FOLDER includes are skipped outright -- they are the fallback's business,
        not this function's. Only a .dpr/.dproj entry can name a project. }
      Ext:= ExtractFileExt(Sec.Include[J]);
      if not (SameText(Ext, '.dproj') or SameText(Ext, '.dpr')) then Continue;
      if NormalizeProjectPath(Sec.Include[J], AManifest.RootDir) <> Target then Continue;

      SetLength(AClaimants, Length(AClaimants) + 1);
      AClaimants[High(AClaimants)]:= Sec.Name;
      if Length(AClaimants) = 1 then FoundDb:= ExpandSectionDb(AManifest, Sec);
      { One claim per SECTION: a section that lists the same project twice is
        sloppy, not ambiguous, and must not be reported as a conflict with
        itself. }
      Break;
    end; // for
  end; // for

  if Length(AClaimants) = 0 then Exit(pdmNone);
  if Length(AClaimants) >  1 then Exit(pdmAmbiguous);
  ADb   := FoundDb;
  Result:= pdmUnique;
end; // function

{ ---------------------------------------------------------------------- }
{  ResolveFolderDb / ResolveReadDbs                                        }
{ ---------------------------------------------------------------------- }

function ResolveFolderDb(const AManifest: TIndexManifest; const AFilePath: string): string;
var
  FileNorm: string       ;
  IncRaw  : string       ;
  IncNorm : string       ;
  Sec     : TIndexSection;
  BestLen : Integer      ;
  I       : Integer      ;
  J       : Integer      ;
begin
  Result:= '';
  if AFilePath = '' then Exit;
  FileNorm:= LowerCase(IncludeTrailingPathDelimiter(ExtractFilePath(ExpandFileName(AFilePath))));
  BestLen := -1;

  for I:= 0 to High(AManifest.Sections) do
  begin
    Sec:= AManifest.Sections[I];
    { A section with no include list (registry-libraries) has nothing to match. }
    for J:= 0 to High(Sec.Include) do
    begin
      IncRaw:= Sec.Include[J];
      if IncRaw = '' then Continue;
      { An include may be a folder OR a project file -- use the project's folder. }
      if SameText(ExtractFileExt(IncRaw), '.dproj') or SameText(ExtractFileExt(IncRaw), '.dpr') then
        IncRaw:= ExtractFilePath(IncRaw);
      if IncRaw = '' then Continue;
      if TPath.IsRelativePath(IncRaw) and (AManifest.RootDir <> '') then
        IncRaw:= TPath.Combine(AManifest.RootDir, IncRaw);
      IncNorm:= LowerCase(IncludeTrailingPathDelimiter(ExpandFileName(IncRaw)));
      { Length > 1 rejects a degenerate root-only include, which would otherwise
        be an ancestor of everything. }
      if (Length(IncNorm) > 1) and (Pos(IncNorm, FileNorm) = 1) and (Length(IncNorm) > BestLen) then
      begin
        Result := ExpandSectionDb(AManifest, Sec);
        BestLen:= Length(IncNorm);
      end;
    end; // for
  end; // for
end; // function

function ResolveReadDbs(const AManifest: TIndexManifest;
  const AActiveProjectFile, AEditorFile: string): TArray<string>;
var
  ProjDb   : string        ;
  FolderDb : string        ;
  Claimants: TArray<string>;
begin
  Result:= nil;

  { Only an UNAMBIGUOUS owner is preferred. An ambiguous project falls through to
    the folder rule rather than refusing: this is the READ path, where a slightly
    too-broad DB is a cosmetic problem, not the destructive one the WRITE path
    faces. }
  ProjDb:= '';
  if ResolveProjectDb(AManifest, AActiveProjectFile, ProjDb, Claimants) <> pdmUnique then ProjDb:= '';
  if ProjDb <> '' then
  begin
    SetLength(Result, 1);
    Result[0]:= ProjDb;
  end;

  { Kept as a SECOND entry, never as an override: an editor file outside the
    active project (library / third-party source) is answered by nothing else. }
  FolderDb:= ResolveFolderDb(AManifest, AEditorFile);
  if (FolderDb <> '') and (not SameText(FolderDb, ProjDb)) then
  begin
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)]:= FolderDb;
  end;
end; // function

{ ---------------------------------------------------------------------- }
{  OrderDbsByMembership                                                    }
{ ---------------------------------------------------------------------- }

function OrderDbsByMembership(const ACandidates: TArray<string>;
  const AActiveProjectDb, AFilePath: string;
  const AContains: TDbContainsFileFunc): TArray<string>;
var
  Holders: TArray<string>;
  Others : TArray<string>;
  Db     : string        ;
  I      : Integer       ;
  ActIdx : Integer       ;
begin
  Result:= ACandidates;
  if (Length(ACandidates) < 2) or (AFilePath = '') or (not Assigned(AContains)) then Exit;

  Holders:= nil;
  Others := nil;
  for Db in ACandidates do
  begin
    if AContains(Db, AFilePath) then
    begin
      SetLength(Holders, Length(Holders) + 1);
      Holders[High(Holders)]:= Db;
    end
    else
    begin
      SetLength(Others, Length(Others) + 1);
      Others[High(Others)]:= Db;
    end;
  end; // for

  { Nothing holds the file: leave the caller's order completely alone. This is
    the library-source case, and "unchanged" is the whole promise. }
  if Length(Holders) = 0 then Exit;

  { Tie-break among holders ONLY -- promote the active project's DB to the front
    of the holders. A file in two closures (ORM3\COMMON) is a real tie, not a
    defect, and this is the one signal that resolves it. }
  ActIdx:= -1;
  if AActiveProjectDb <> '' then
    for I:= 0 to High(Holders) do
      if SameText(Holders[I], AActiveProjectDb) then begin ActIdx:= I; Break; end;

  if ActIdx > 0 then
  begin
    Db:= Holders[ActIdx];
    for I:= ActIdx downto 1 do Holders[I]:= Holders[I - 1];
    Holders[0]:= Db;
  end;

  Result:= Holders + Others;
end; // function

{ ---------------------------------------------------------------------- }
{  LoadDocComplexityMin                                                    }
{ ---------------------------------------------------------------------- }

// v(ADP2 T3): reads the docs.complexity_min threshold for the doc/hover
// verbs (see the interface declaration's DocInsight comment for the full
// rationale). v(ADP2 T9): RELOCATED here from DRagLint.CLI (where it was a
// private implementation-only function) so BOTH DRagLint.CLI.DoHover and
// DRagLint.LSP.Server.HandleHover can call the SAME loader -- LSP.Server
// must not depend on the CLI unit (CLI already depends on LSP.Server), and
// this unit (DRagLint.Index.Manifest) sits below both in the dependency
// graph. Behavior is unchanged from the original CLI.pas copy: same
// manifest discovery (engine dir beside the exe + current working dir
// walking up for a local override), same 10 fallback on any load failure.
function LoadDocComplexityMin: Integer;
var
  DocManifest: TIndexManifest;
begin
  Result:= 10;
  try
    DocManifest:= TManifestIO.Load(ExtractFilePath(ParamStr(0)), GetCurrentDir);
    Result:= DocManifest.Docs.ComplexityMin;
  except
    Result:= 10;
  end;
end;

end.
