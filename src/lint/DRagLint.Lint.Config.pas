unit DRagLint.Lint.Config;

interface

uses
  System.SysUtils, System.JSON, System.IOUtils, System.Generics.Collections,
  System.Masks, { IsPathExcluded's glob match }
  DRagLint.Core.Model;

const
  /// <summary>The exceptions unit assumed when an "exceptions" block is present
  /// but names no unit.</summary>
  /// <remarks>
  /// <para>Owner ruling 2026-08-29: *"create a simple unit, say
  /// uExceptionDefinitions.pas -- the name is in the default settings as
  /// default"*. So writing the block is enough; naming the unit is optional.</para>
  /// <para>An ABSENT block still means OFF, and that is deliberate rather than a
  /// half-measure. Defaulting the NAME is not the same as defaulting the
  /// FEATURE: the enrichment costs an extra AST walk on every linted file, and
  /// ExceptionsUnit's own contract says the unconfigured case must stay
  /// genuinely free -- the walk is skipped, not filtered. Turning it on for
  /// every project on the box would tax all of them to serve the one that opted
  /// in.</para>
  /// </remarks>
  DEFAULT_EXCEPTIONS_UNIT = 'uExceptionDefinitions';
  /// <summary>Ancestor for every generated exception class, from
  /// "exceptions" key "root". Defaults to the RTL's own Exception.</summary>
  /// <remarks>A project with a house base class (EMicroniteError) wants every
  /// generated class under it, because that is what its top-level handlers
  /// catch. Defaulting to Exception rather than to a house name keeps the
  /// generated unit compilable in a project that has no such base -- a
  /// generated unit that does not compile is the one failure this feature
  /// cannot survive.</remarks>
  DEFAULT_EXCEPTIONS_ROOT = 'Exception';

type
  /// <summary>Raised by TLintConfig.Load when a config key is present but malformed
  /// (v1: only the "disallowed" block is validated this strictly).</summary>
  ELintConfigError = class(Exception);

  /// <summary>One entry of the "disallowed" config block: an identifier the project
  /// bans, why, and the files exempt from the ban.</summary>
  /// <remarks>Plain value record. Name may be dotted (TFile.Delete); matching is
  /// case-insensitive and textual (see TDisallowedChecker).</remarks>
  TDisallowedEntry = record
    /// <summary>Banned identifier or dotted identifier path; never empty.</summary>
    Name  : string;
    /// <summary>Why it is banned; shown in the finding. May be empty.</summary>
    Reason: string;
    /// <summary>Case-insensitive path globs (as exclude_paths); a file matching any
    /// is exempt from this entry only.</summary>
    Exempt: TArray<string>;
  end;

  /// <summary>Configurable naming conventions read from the drag-lint-lint.json
  /// "naming" block. Empty-string prefixes disable that prefix check; empty
  /// ConstCase disables const casing. KeywordCase='' disables reserved-word-casing;
  /// ShortIdentifierCheck=False (default) disables hungarian-or-short-identifier.
  /// Defaults match the project conventions (TMyClass / EMyException / IMyIntf /
  /// PMyType / FMyField / pMyParam, PascalCase, lowercase keywords).</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Diagnostics.NamingChecks.pas), declaration (DRagLint.Lint.Config.pas), DRagLint.CLI.PlanMultiOwnerNaming (DRagLint.CLI.pas), DRagLint.Diagnostics.NamingChecks.ExpectedClassPrefix (DRagLint.Diagnostics.NamingChecks.pas), DRagLint.Diagnostics.NamingChecks.TNamingChecker.Check (DRagLint.Diagnostics.NamingChecks.pas) (+5 more)</para>
  /// <para>Used in units: DRagLint.CLI, DRagLint.Diagnostics.NamingChecks, DRagLint.Lint.Config, DRagLint.Refactor.MultiProjectRename, DRagLint.Refactor.NamingFix</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TNamingConfig = record
    ClassPrefix, ExceptionPrefix, InterfacePrefix, PointerPrefix: string;
    FieldPrefix, ParamPrefix: string;
    MethodCase, LocalCase   : string;        // 'PascalCase' | 'UPPER_CASE' | 'camelCase'
    ConstCase               : TArray<string>;
    KeywordCase             : string;        // 'lowercase' (default) | '' disables reserved-word-casing
    MinIdentifierLen        : Integer;       // shortest allowed identifier (hungarian-or-short rule)
    HungarianPrefixes       : TArray<string>;// type-prefix denylist for the hungarian rule
    ShortIdentifierCheck    : Boolean;       // master on/off for hungarian-or-short-identifier (default False)
    /// <returns><!-- drag-lint:auto type -->TNamingConfig</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.CLI.AddStalenessPairs (DRagLint.CLI.pas) ?, DRagLint.CLI.ApplyDocEditsGuarded (DRagLint.CLI.pas) ?, DRagLint.CLI.ParseArgs (DRagLint.CLI.pas) ?, DRagLint.CLI.ResolveIndexProfile (DRagLint.CLI.pas) ?, DRagLint.Lint.Config.TLintConfig.Load (DRagLint.Lint.Config.pas) (+84 more)</para>
    /// <para>Pure</para>
    /// <para>Directives: static</para>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function Default: TNamingConfig; static;
  end;

  /// <summary>Per-project lint configuration loaded from drag-lint-lint.json:
  /// severity overrides, enable/disable lists, metric thresholds, and named
  /// profiles. A value type -- Load returns a fresh copy; AddEnabled/AddDisabled
  /// mutate the local copy in place. An unloaded (default) config is a no-op:
  /// every rule kept at its declared severity, every threshold = the passed
  /// default.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: [drag-lint]declaration (DRagLint.Lint.ClassMetrics.pas), [drag-lint]declaration (DRagLint.Lint.Config.pas), [drag-lint]DRagLint.CLI.BuildExceptionRewriteEdits (DRagLint.CLI.pas), [drag-lint]DRagLint.CLI.DocExcludePredicate (DRagLint.CLI.pas), [drag-lint]DRagLint.CLI.DoExceptionsSync (DRagLint.CLI.pas), [drag-lint]DRagLint.CLI.DoLint (DRagLint.CLI.pas), [drag-lint]DRagLint.CLI.DoLintAll (DRagLint.CLI.pas), [drag-lint]DRagLint.CLI.FinalizeAndOutput (DRagLint.CLI.pas), [drag-lint]DRagLint.CLI.LoadLintConfig (DRagLint.CLI.pas), [drag-lint]DRagLint.CLI.RoutineMetricFindings (DRagLint.CLI.pas), [drag-lint]DRagLint.CLI.RuleKeptByRun (DRagLint.CLI.pas), [drag-lint]DRagLint.Lint.ClassMetrics.TClassMetrics.Run (DRagLint.Lint.ClassMetrics.pas), [drag-lint]DRagLint.LSP.Completion.TLspCompletion.BuildDiagnostics (DRagLint.LSP.Completion.pas)</para>
  /// <para>Used in units: DRagLint.CLI, DRagLint.Lint.ClassMetrics, DRagLint.Lint.Config, DRagLint.LSP.Completion, DragLint.Plugin.LintOptionsFrame</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TLintConfig = record
  strict private
    FDisabled    : TArray<string> ;
    FEnabled     : TArray<string> ;
    FAutoFix     : TArray<string> ;
    FSevNames    : TArray<string> ; // parallel arrays: rule id -> severity
    FSevValues   : TArray<string> ;
    FThreshNames : TArray<string> ; // parallel arrays: metric name -> value
    FThreshValues: TArray<Integer>;
    { v(2026-08-10): "exclude_paths" -- case-insensitive globs matched against a
      file's FULL path. A match drops the file from the lint scan entirely.

      This is a LINT-scope filter, deliberately NOT an index-scope one. Vendored
      code (third_party\delphi-tree-sitter) is in the index because it is part of
      the .dproj compile closure -- excluding it there would strand symbol
      resolution for everything that uses it. But it is not this repo's code to
      restyle: 134 of drag-lint's own 2,765 findings sat in it, 95 of them
      method-pascalcase on C bindings (ts_query_cursor_new), where "fixing" the
      name would diverge from upstream and make every future sync a conflict.
      tests\autotest\run_encoding_guard.ps1 already exempts the same directory
      for the same stated reason; lint did not, and the two should agree. }
    FExcludePaths: TArray<string> ;
    /// <param name="AArr"><!-- drag-lint:auto type -->const TArray&lt;string&gt;</param>
    /// <param name="AId"><!-- drag-lint:auto type -->const string</param>
    /// <returns><!-- drag-lint:auto -->Boolean -- Observed: False.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.CLI.DoUsesAudit.UnitsDefining (DRagLint.CLI.pas) ?, DRagLint.CLI.DoUsesFixSweep.UnitsDefining (DRagLint.CLI.pas) ?, DRagLint.CLI.ErrorSignatures (DRagLint.CLI.pas) ?, DRagLint.Lint.Config.TLintConfig.IsAutoFix (DRagLint.Lint.Config.pas), DRagLint.Lint.Config.TLintConfig.ShouldKeep (DRagLint.Lint.Config.pas) (+7 more)</para>
    /// <para>Calls: SameText, Trim</para>
    /// <para>Pure</para>
    /// <para>Directives: static</para>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.AddAutoFix"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.AddDisabled"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.AddEnabled"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.ApplyConfigObject"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.ApplyNamingObject"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function Contains(const AArr: TArray<string>; const AId: string): Boolean; static;
    /// <summary>Parses a "naming" JSON object and applies each present field
    /// over the current Naming record (field-wise; absent keys are left
    /// unchanged).</summary>
    /// <param name="ANaming"><!-- drag-lint:auto type -->const TJSONObject</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Lint.Config.TLintConfig.ApplyConfigObject (DRagLint.Lint.Config.pas)</para>
    /// <para>Calls: SameText, StrToIntDef</para>
    /// <para>Complexity: 16 (cyclomatic, outer body), 37 lines (full implementation)</para>
    /// <para>Reads: Naming</para>
    /// <para>Pure</para>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.AddAutoFix"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.AddDisabled"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.AddEnabled"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.ApplyConfigObject"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.ApplySeverity"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure ApplyNamingObject(const ANaming: TJSONObject);
    /// <summary>Applies a config JSON object to this instance. When AReplace
    /// is True the disabled/enabled/severity/thresholds arrays are cleared
    /// before merging (profile-override semantics); when False they are
    /// appended (top-level base semantics).</summary>
    /// <param name="AObj"><!-- drag-lint:auto type -->const TJSONObject</param>
    /// <param name="AReplace"><!-- drag-lint:auto type -->Boolean</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Lint.Config.TLintConfig.Load (DRagLint.Lint.Config.pas)</para>
    /// <para>Calls: DRagLint.Lint.Config.TLintConfig.ApplyConfigObject.ApplyList, DRagLint.Lint.Config.TLintConfig.ApplyNamingObject, DRagLint.Lint.Config.TLintConfig.SetSeverityPair, SameText, StrToIntDef</para>
    /// <para>Complexity: 12 (cyclomatic, outer body), 77 lines (full implementation)</para>
    /// <para>Reads: FDisabled, FEnabled, FAutoFix, FExcludePaths, IfdefAllow, PlatformDivergentAllow, FThreshNames, FThreshValues   Writes: FThreshValues, FThreshNames, ExceptionsUnit, ExceptionsRoot</para>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.ApplyConfigObject.ApplyList"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.ApplyNamingObject"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.SetSeverityPair"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.AddAutoFix"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.AddDisabled"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure ApplyConfigObject(const AObj: TJSONObject; AReplace: Boolean);
    /// <summary>Parses the "disallowed" block into DisallowedMethods / Types / Names.</summary>
    /// <param name="ABlock">The "disallowed" JSON object.</param>
    /// <param name="AReplace">True for a profile (lists replaced), False to append.</param>
    /// <exception cref="ELintConfigError">Block, list or entry is malformed.</exception>
    procedure ApplyDisallowedObject(const ABlock: TJSONObject; AReplace: Boolean);
  public
    /// <summary>Entries of "disallowed"."methods" (disallowed-method rule). Empty when
    /// absent, which keeps the rule silent.</summary>
    DisallowedMethods: TArray<TDisallowedEntry>;
    /// <summary>Entries of "disallowed"."types" (disallowed-type rule).</summary>
    DisallowedTypes: TArray<TDisallowedEntry>;
    /// <summary>Entries of "disallowed"."names" (disallowed-name rule).</summary>
    DisallowedNames: TArray<TDisallowedEntry>;
    /// <summary>Naming conventions parsed from the "naming" block; always
    /// populated with TNamingConfig.Default when no block is present.</summary>
    Naming: TNamingConfig;
    /// <summary>The `taint` objects of the config, as JSON text, in the order they were read (top level,
    /// then the profile); TTaintRules.LoadConfig merges them over the built-in catalogues.</summary>
    /// <remarks>Kept as text so this unit does not depend on the taint unit; additive on purpose --
    /// a profile adds to the top level rather than replacing it (the merge is additive by design).</remarks>
    TaintJson: TArray<string>;
    /// <summary>The unit that owns this project's exception classes, from
    /// "exceptions": { "unit": "..." }. EMPTY when the block is absent, and that
    /// is the OFF switch for the whole feature: raise-bare-exception then reports
    /// exactly the text it always did.</summary>
    /// <remarks>Opting in costs one extra AST walk per linted file, so the empty
    /// case must stay genuinely free -- the walk is skipped, not filtered.</remarks>
    ExceptionsUnit: string;
    /// <summary>Ancestor of every generated exception class, from
    /// "exceptions" key "root". DEFAULT_EXCEPTIONS_ROOT when the block is
    /// present but names none; empty when the block is absent.</summary>
    /// <remarks>Its declaring unit is resolved through the index and added to
    /// the generated unit's uses clause, so a house base class in another unit
    /// works without the user editing the generated file -- which they must
    /// never have to do, because the block is rewritten on every run.</remarks>
    ExceptionsRoot: string;
    /// <summary>Conditional symbols the ifdef-undefined-symbol rule treats as
    /// defined, from the top-level "ifdef_allow" string array. For defines set
    /// in third-party .inc files the project never includes directly (a
    /// library version symbol, for example). Compared case-insensitively.</summary>
    /// <remarks>Empty when the key is absent. A profile that names the key
    /// replaces the list; the top level appends.</remarks>
    IfdefAllow: TArray<string>;
    /// <summary>Conditional symbols whose Win32 / Win64 split is deliberate, so
    /// platform-divergent-define does not report them; from the top-level
    /// "platform_divergent_allow" string array. Compared case-insensitively.</summary>
    /// <remarks>Empty when the key is absent. A profile that names the key
    /// replaces the list; the top level appends. Not written by
    /// TLintConfigWriter, which preserves the key verbatim.</remarks>
    PlatformDivergentAllow: TArray<string>;
    /// <summary>The raw "target_compiler" token (two-way modernize, 1.38): a
    /// product version (13, 12, 10.4, XE7 ...), a CompilerVersion (37, 36 ...)
    /// or "auto". Empty when the key is absent.</summary>
    /// <remarks>Not validated here -- DRagLint.Lint.TargetCompiler.
    /// ResolveTargetCompiler parses it (and refuses an unknown token) after the
    /// command line had its say. A profile that names the key replaces the
    /// top-level value, so a "legacy" profile can pin 12 while the top level
    /// stays 13.</remarks>
    TargetCompiler: string;
    /// <summary>True when Load found a profile named AProfile under "profiles" in the
    /// config file. A built-in compliance profile name applies only when this is False
    /// (a user-defined profile of the same name wins).</summary>
    UserProfileFound: Boolean;    /// <summary>True when AFilePath matches any glob in AGlobs (case-insensitive;
    /// '/' and '\' equivalent). The matcher behind IsPathExcluded and the
    /// per-entry "except" lists.</summary>
    /// <param name="AFilePath">Full path of the file.</param>
    /// <param name="AGlobs">Globs; empty entries are ignored.</param>
    /// <returns>False for an empty list or empty path.</returns>
    class function MatchesAnyGlob(const AFilePath: string; const AGlobs: TArray<string>): Boolean; static;
    /// <summary>Loads config from APath (JSON). Empty/missing APath yields a
    /// no-op default config. If AProfile is non-empty and present under
    /// "profiles", the profile is merged over the top-level values: list fields
    /// (disabled, enabled) are replaced wholesale; map fields (severity,
    /// thresholds, naming) are updated per-key so base entries the profile
    /// omits are inherited unchanged.</summary>
    /// <param name="APath"><!-- drag-lint:auto type -->const string</param>
    /// <param name="AProfile"><!-- drag-lint:auto type -->const string</param>
    /// <returns><!-- drag-lint:auto -->TLintConfig -- Observed: Default(TLintConfig).</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.CLI.LoadLintConfig (DRagLint.CLI.pas), DRagLint.LSP.Completion.TLspCompletion.BuildDiagnostics (DRagLint.LSP.Completion.pas)</para>
    /// <para>Calls: DRagLint.Lint.Config.TLintConfig.ApplyConfigObject, DRagLint.Lint.Config.TNamingConfig.Default</para>
    /// <para>Touches: file system</para>
    /// <para>Directives: static</para>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.ApplyConfigObject"/>
    /// <seealso cref="DRagLint.Lint.Config.TNamingConfig.Default"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.AddAutoFix"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.AddDisabled"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.AddEnabled"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function Load(const APath, AProfile: string): TLintConfig; static;
    /// <summary>Returns the configured severity for ARuleId, else ADefault.</summary>
    /// <param name="ARuleId"><!-- drag-lint:auto type -->const string</param>
    /// <param name="ADefault"><!-- drag-lint:auto type -->const string</param>
    /// <returns><!-- drag-lint:auto -->string -- Observed: ADefault.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.CLI.FinalizeAndOutput (DRagLint.CLI.pas), DRagLint.LSP.Completion.TLspCompletion.BuildDiagnostics (DRagLint.LSP.Completion.pas)</para>
    /// <para>Calls: SameText</para>
    /// <para>Reads: FSevNames, FSevValues</para>
    /// <para>Pure</para>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.AddAutoFix"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.AddDisabled"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.AddEnabled"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.ApplyConfigObject"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.ApplyNamingObject"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function ApplySeverity(const ARuleId, ADefault: string): string;
    /// <summary>Keep policy for a finding's rule. Dropped if disabled; an
    /// off-by-default rule (ADefaultDisabled) is dropped unless re-enabled.</summary>
    /// <param name="ARuleId"><!-- drag-lint:auto type -->const string</param>
    /// <param name="ADefaultDisabled"><!-- drag-lint:auto type -->Boolean</param>
    /// <returns><!-- drag-lint:auto -->Boolean -- Observed: True.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.CLI.DoLintAll (DRagLint.CLI.pas), DRagLint.CLI.FinalizeAndOutput (DRagLint.CLI.pas), DRagLint.CLI.RuleKeptByRun (DRagLint.CLI.pas), DRagLint.Lint.Config.TLintConfig.IsEnabled (DRagLint.Lint.Config.pas), DRagLint.LSP.Completion.TLspCompletion.BuildDiagnostics (DRagLint.LSP.Completion.pas)</para>
    /// <para>Calls: DRagLint.Lint.Config.TLintConfig.Contains</para>
    /// <para>Reads: FDisabled, FEnabled</para>
    /// <para>Pure</para>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.Contains"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.AddAutoFix"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.AddDisabled"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.AddEnabled"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.ApplyConfigObject"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function ShouldKeep(const ARuleId: string; ADefaultDisabled: Boolean): Boolean;
    /// <summary>Convenience: ShouldKeep(ARuleId, False).</summary>
    /// <param name="ARuleId"><!-- drag-lint:auto type -->const string</param>
    /// <returns><!-- drag-lint:auto -->Boolean -- Observed: ShouldKeep(ARuleId, False).</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Calls: DRagLint.Lint.Config.TLintConfig.ShouldKeep</para>
    /// <para>Pure</para>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.ShouldKeep"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.AddAutoFix"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.AddDisabled"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.AddEnabled"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.ApplyConfigObject"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function IsEnabled(const ARuleId: string): Boolean;
    /// <summary>Returns True when ARuleId is in the configured auto-fix set.
    /// Independent of enabled/disabled -- a rule may be enabled without being
    /// auto-fixed, or auto-fixed while off by default.</summary>
    /// <param name="ARuleId"><!-- drag-lint:auto type -->const string</param>
    /// <returns><!-- drag-lint:auto -->Boolean -- Observed: Contains(FAutoFix, ARuleId).</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.CLI.FinalizeAndOutput (DRagLint.CLI.pas)</para>
    /// <para>Calls: DRagLint.Lint.Config.TLintConfig.Contains</para>
    /// <para>Reads: FAutoFix</para>
    /// <para>Pure</para>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.Contains"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.AddAutoFix"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.AddDisabled"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.AddEnabled"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.ApplyConfigObject"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function IsAutoFix(const ARuleId: string): Boolean;
    /// <summary>True when AFilePath matches any configured "exclude_paths"
    /// glob and must therefore not be linted at all.</summary>
    /// <param name="AFilePath">Full path of the candidate source file.</param>
    /// <returns>True to SKIP the file; False to lint it. Always False when no
    /// exclude_paths are configured, so behaviour is unchanged by default.</returns>
    /// <remarks>
    /// Case-insensitive, and matched against the WHOLE path so a glob
    /// like <c>*\third_party\*</c> selects a directory subtree. This drops the
    /// file before any rule runs -- it is a scope decision, not a per-rule
    /// suppression, because vendored code is not this codebase's quality
    /// signal for ANY rule.
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.CLI.DocExcludePredicate (DRagLint.CLI.pas), DRagLint.CLI.DoExceptionsSync (DRagLint.CLI.pas), DRagLint.CLI.DoLintAll (DRagLint.CLI.pas)</para>
    /// <para>Calls: LowerCase, MatchesMask, StringReplace</para>
    /// <para>Returns: False; True</para>
    /// <para>Reads: FExcludePaths</para>
    /// <para>Pure</para>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.AddAutoFix"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.AddDisabled"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.AddEnabled"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.ApplyConfigObject"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.ApplyNamingObject"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function IsPathExcluded(const AFilePath: string): Boolean;
    /// <summary>Returns the configured threshold for AName, else ADefault.</summary>
    /// <param name="AName"><!-- drag-lint:auto type -->const string</param>
    /// <param name="ADefault"><!-- drag-lint:auto type -->Integer</param>
    /// <returns><!-- drag-lint:auto -->Integer -- Observed: ADefault.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.CLI.DoLint (DRagLint.CLI.pas), DRagLint.CLI.DoLintAll (DRagLint.CLI.pas), DRagLint.CLI.FinalizeAndOutput (DRagLint.CLI.pas), DRagLint.CLI.RoutineMetricFindings (DRagLint.CLI.pas), DRagLint.Lint.ClassMetrics.TClassMetrics.Run (DRagLint.Lint.ClassMetrics.pas)</para>
    /// <para>Calls: SameText</para>
    /// <para>Reads: FThreshNames, FThreshValues</para>
    /// <para>Pure</para>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.AddAutoFix"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.AddDisabled"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.AddEnabled"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.ApplyConfigObject"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.ApplyNamingObject"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function ThresholdFor(const AName: string; ADefault: Integer): Integer;
    /// <summary>Appends ids to the effective enabled set (for --enable).</summary>
    /// <param name="AIds"><!-- drag-lint:auto type -->const TArray&lt;string&gt;</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.CLI.LoadLintConfig (DRagLint.CLI.pas)</para>
    /// <para>Calls: Trim</para>
    /// <para>Reads: FEnabled   Writes: FEnabled</para>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.AddAutoFix"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.AddDisabled"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.ApplyConfigObject"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.ApplyNamingObject"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.ApplySeverity"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure AddEnabled(const AIds: TArray<string>);
    /// <summary>Appends ids to the effective disabled set (for --disable).</summary>
    /// <param name="AIds"><!-- drag-lint:auto type -->const TArray&lt;string&gt;</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.CLI.LoadLintConfig (DRagLint.CLI.pas)</para>
    /// <para>Calls: Trim</para>
    /// <para>Reads: FDisabled   Writes: FDisabled</para>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.AddAutoFix"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.AddEnabled"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.ApplyConfigObject"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.ApplyNamingObject"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.ApplySeverity"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure AddDisabled(const AIds: TArray<string>);
    /// <summary>Appends ids to the effective auto-fix set.</summary>
    /// <param name="AIds"><!-- drag-lint:auto type -->const TArray&lt;string&gt;</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Calls: Trim</para>
    /// <para>Reads: FAutoFix   Writes: FAutoFix</para>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.AddDisabled"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.AddEnabled"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.ApplyConfigObject"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.ApplyNamingObject"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.ApplySeverity"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure AddAutoFix(const AIds: TArray<string>);
    // -- Read accessors (for serialization) --
    /// <summary>Returns a copy of the disabled rule-id list.</summary>
    /// <returns><!-- drag-lint:auto -->TArray&lt;string&gt; -- Observed: FDisabled.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Reads: FDisabled</para>
    /// <para>Owns returned: borrowed</para>
    /// <para>Pure</para>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.AddAutoFix"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.AddDisabled"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.AddEnabled"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.ApplyConfigObject"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.ApplyNamingObject"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function DisabledIds: TArray<string>;
    /// <summary>Returns a copy of the enabled rule-id list.</summary>
    /// <returns><!-- drag-lint:auto -->TArray&lt;string&gt; -- Observed: FEnabled.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Reads: FEnabled</para>
    /// <para>Owns returned: borrowed</para>
    /// <para>Pure</para>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.AddAutoFix"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.AddDisabled"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.AddEnabled"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.ApplyConfigObject"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.ApplyNamingObject"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function EnabledIds: TArray<string>;
    /// <summary>Returns a copy of the auto-fix rule-id list.</summary>
    /// <returns><!-- drag-lint:auto -->TArray&lt;string&gt; -- Observed: FAutoFix.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Reads: FAutoFix</para>
    /// <para>Owns returned: borrowed</para>
    /// <para>Pure</para>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.AddAutoFix"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.AddDisabled"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.AddEnabled"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.ApplyConfigObject"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.ApplyNamingObject"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function AutoFixIds: TArray<string>;
    /// <summary>Returns severity pairs (rule id, severity string).</summary>
    /// <returns><!-- drag-lint:auto type -->TArray&lt;TPair&lt;string,string&gt;&gt;</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Reads: FSevNames, FSevValues</para>
    /// <para>Pure</para>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.AddAutoFix"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.AddDisabled"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.AddEnabled"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.ApplyConfigObject"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.ApplyNamingObject"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function SeverityPairs: TArray<TPair<string,string>>;
    /// <summary>Returns threshold pairs (metric name, integer value).</summary>
    /// <returns><!-- drag-lint:auto type -->TArray&lt;TPair&lt;string,Integer&gt;&gt;</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Reads: FThreshNames, FThreshValues</para>
    /// <para>Pure</para>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.AddAutoFix"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.AddDisabled"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.AddEnabled"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.ApplyConfigObject"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.ApplyNamingObject"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function ThresholdPairs: TArray<TPair<string,Integer>>;
    // -- Write mutators (for config writer) --
    /// <summary>Replaces the disabled list with AIds.</summary>
    /// <param name="AIds"><!-- drag-lint:auto type -->const TArray&lt;string&gt;</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Writes: FDisabled</para>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.AddAutoFix"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.AddDisabled"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.AddEnabled"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.ApplyConfigObject"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.ApplyNamingObject"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure SetDisabled(const AIds: TArray<string>);
    /// <summary>Replaces the enabled list with AIds.</summary>
    /// <param name="AIds"><!-- drag-lint:auto type -->const TArray&lt;string&gt;</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Writes: FEnabled</para>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.AddAutoFix"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.AddDisabled"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.AddEnabled"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.ApplyConfigObject"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.ApplyNamingObject"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure SetEnabled(const AIds: TArray<string>);
    /// <summary>Replaces the auto-fix list with AIds.</summary>
    /// <param name="AIds"><!-- drag-lint:auto type -->const TArray&lt;string&gt;</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DragLint.Plugin.LintOptionsFrame.TLintOptionsFrame.Save (DragLint.Plugin.LintOptionsFrame.pas)
    /// <para>Writes: FAutoFix</para>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.AddAutoFix"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.AddDisabled"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.AddEnabled"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.ApplyConfigObject"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.ApplyNamingObject"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure SetAutoFix(const AIds: TArray<string>);
    /// <summary>Sets or updates the severity override for AId.</summary>
    /// <param name="AId"><!-- drag-lint:auto type -->const string</param>
    /// <param name="ASev"><!-- drag-lint:auto type -->const string</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Lint.Config.TLintConfig.ApplyConfigObject (DRagLint.Lint.Config.pas)</para>
    /// <para>Calls: SameText</para>
    /// <para>Reads: FSevNames, FSevValues   Writes: FSevValues, FSevNames</para>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.AddAutoFix"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.AddDisabled"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.AddEnabled"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.ApplyConfigObject"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.ApplyNamingObject"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure SetSeverityPair(const AId, ASev: string);
    /// <summary>Sets or updates the threshold override for AName.</summary>
    /// <param name="AName"><!-- drag-lint:auto type -->const string</param>
    /// <param name="AValue"><!-- drag-lint:auto type -->Integer</param>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Calls: SameText</para>
    /// <para>Reads: FThreshNames, FThreshValues   Writes: FThreshValues, FThreshNames</para>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.AddAutoFix"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.AddDisabled"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.AddEnabled"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.ApplyConfigObject"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.ApplyNamingObject"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure SetThresholdPair(const AName: string; AValue: Integer);
  end;

const
  /// <summary>The ONE format of every type-name-prefix finding message:
  /// kind word, type name, expected prefix.</summary>
  /// <remarks>Build messages with TypePrefixFindingMessage and read the prefix
  /// back with TryExpectedPrefixFromTypePrefixMessage; never hand-format or
  /// hand-parse it (the checker emits it, the fixer consumes it).</remarks>
  TYPE_PREFIX_MSG_FMT = '%s "%s" should start with the "%s" prefix';

  /// <summary>Format of the ERROR finding the type-name-prefix rule raises when a
  /// class ancestor is in neither the project nor the library index, so the
  /// E/T prefix cannot be decided. Args: ancestor name, class name.</summary>
  /// <remarks>Build with TypePrefixGapMessage; recognise with
  /// IsTypePrefixGapMessage. The fixer never acts on it.</remarks>
  TYPE_PREFIX_GAP_MSG_FMT = 'Ancestor "%s" of class "%s" is in neither the project nor the library index -- cannot decide the E/T prefix (index gap: reindex, or add the library root)';

/// <summary>Builds the type-name-prefix finding message from TYPE_PREFIX_MSG_FMT.</summary>
/// <param name="AKindWord">One of 'Exception class', 'Class', 'Record', 'Interface', 'Pointer type'.</param>
/// <param name="AName">The offending type name.</param>
/// <param name="APrefix">The expected prefix (e.g. 'T', 'E').</param>
/// <returns>The finding message text.</returns>
/// <remarks>Pure.</remarks>
function TypePrefixFindingMessage(const AKindWord, AName, APrefix: string): string;

/// <summary>Reads the expected prefix back out of a message built by
/// TypePrefixFindingMessage.</summary>
/// <param name="AMessage">A finding message.</param>
/// <param name="APrefix">The prefix inside the message; '' when it is not a type-prefix message.</param>
/// <returns>True when AMessage has the TYPE_PREFIX_MSG_FMT shape with a non-empty prefix.</returns>
/// <remarks>Pure. The inverse of TypePrefixFindingMessage on its prefix argument.</remarks>
function TryExpectedPrefixFromTypePrefixMessage(const AMessage: string; out APrefix: string): Boolean;

/// <summary>Builds the index-gap error message from TYPE_PREFIX_GAP_MSG_FMT.</summary>
/// <param name="AAncestor">The ancestor name known to neither index.</param>
/// <param name="AClassName">The class whose prefix cannot be decided.</param>
/// <returns>The finding message text.</returns>
/// <remarks>Pure.</remarks>
function TypePrefixGapMessage(const AAncestor, AClassName: string): string;

/// <summary>True when AMessage is an index-gap message (TypePrefixGapMessage).</summary>
/// <param name="AMessage">A finding message.</param>
/// <returns>True for the gap shape; the fixer must skip such a finding.</returns>
/// <remarks>Pure.</remarks>
function IsTypePrefixGapMessage(const AMessage: string): Boolean;

implementation

const
  TYPE_PREFIX_MSG_MARK = ' should start with the "';
  TYPE_PREFIX_MSG_TAIL = '" prefix';
  TYPE_PREFIX_GAP_MARK = 'is in neither the project nor the library index';

function TypePrefixFindingMessage(const AKindWord, AName, APrefix: string): string;
begin
  Result:= Format(TYPE_PREFIX_MSG_FMT, [AKindWord, AName, APrefix]);
end;

function TryExpectedPrefixFromTypePrefixMessage(const AMessage: string; out APrefix: string): Boolean;
var
  P   : Integer;
  Rest: string ;
begin
  APrefix:= '';
  Result := False;
  P:= Pos(TYPE_PREFIX_MSG_MARK, AMessage);
  if P = 0 then Exit;
  Rest:= Copy(AMessage, P + Length(TYPE_PREFIX_MSG_MARK), MaxInt);
  if (Length(Rest) <= Length(TYPE_PREFIX_MSG_TAIL))
    or (Copy(Rest, Length(Rest) - Length(TYPE_PREFIX_MSG_TAIL) + 1, MaxInt) <> TYPE_PREFIX_MSG_TAIL) then Exit;
  APrefix:= Copy(Rest, 1, Length(Rest) - Length(TYPE_PREFIX_MSG_TAIL));
  Result := True;
end;

function TypePrefixGapMessage(const AAncestor, AClassName: string): string;
begin
  Result:= Format(TYPE_PREFIX_GAP_MSG_FMT, [AAncestor, AClassName]);
end;

function IsTypePrefixGapMessage(const AMessage: string): Boolean;
begin
  Result:= Pos(TYPE_PREFIX_GAP_MARK, AMessage) > 0;
end;

class function TNamingConfig.Default: TNamingConfig;
begin
  Result.ClassPrefix    := 'T';
  Result.ExceptionPrefix:= 'E';
  Result.InterfacePrefix:= 'I';
  Result.PointerPrefix  := 'P';
  Result.FieldPrefix    := 'F';
  Result.ParamPrefix    := '';  { off by default; set to 'p' in config to enable }
  Result.MethodCase     := 'PascalCase';
  Result.LocalCase      := 'PascalCase';
  Result.ConstCase      := ['PascalCase', 'UPPER_CASE'];
  Result.KeywordCase         := 'lowercase';  { reserved-word-casing ON by default }
  Result.MinIdentifierLen    := 3;
  Result.HungarianPrefixes   := ['lpsz', 'psz', 'sz', 'lp', 'int', 'str', 'dw', 'b', 'p', 'n'];
  Result.ShortIdentifierCheck:= False;        { hungarian-or-short-identifier OFF by default }
end;

class function TLintConfig.Contains(const AArr: TArray<string>; const AId: string): Boolean;
var
  S: string;
begin
  for S in AArr do
    if SameText(Trim(S), AId) then Exit(True);
  Result:= False;
end;

procedure TLintConfig.ApplyNamingObject(const ANaming: TJSONObject);
var
  NJ: TJSONObject;
  TP: TJSONObject;
begin
  if ANaming = nil then Exit;
  NJ:= ANaming;
  if NJ.GetValue('type_prefix') is TJSONObject then
  begin
    TP:= NJ.GetValue('type_prefix') as TJSONObject;
    if TP.GetValue('class')     <> nil then Naming.ClassPrefix    := TP.GetValue('class').Value;
    if TP.GetValue('exception') <> nil then Naming.ExceptionPrefix:= TP.GetValue('exception').Value;
    if TP.GetValue('interface') <> nil then Naming.InterfacePrefix:= TP.GetValue('interface').Value;
    if TP.GetValue('pointer')   <> nil then Naming.PointerPrefix  := TP.GetValue('pointer').Value;
  end;
  if NJ.GetValue('field_prefix') <> nil then Naming.FieldPrefix:= NJ.GetValue('field_prefix').Value;
  if NJ.GetValue('param_prefix') <> nil then Naming.ParamPrefix:= NJ.GetValue('param_prefix').Value;
  if NJ.GetValue('method_case')  <> nil then Naming.MethodCase := NJ.GetValue('method_case').Value;
  if NJ.GetValue('local_case')   <> nil then Naming.LocalCase  := NJ.GetValue('local_case').Value;
  if NJ.GetValue('const_case') is TJSONArray then
  begin
    Naming.ConstCase:= nil;
    for var V in (NJ.GetValue('const_case') as TJSONArray) do
      Naming.ConstCase:= Naming.ConstCase + [V.Value];
  end;
  if NJ.GetValue('keyword_case') <> nil then
    Naming.KeywordCase:= NJ.GetValue('keyword_case').Value;
  if NJ.GetValue('min_identifier_len') <> nil then
    Naming.MinIdentifierLen:= StrToIntDef(NJ.GetValue('min_identifier_len').Value, 3);
  if NJ.GetValue('short_identifier_check') <> nil then
    Naming.ShortIdentifierCheck:= SameText(NJ.GetValue('short_identifier_check').Value, 'true');
  if NJ.GetValue('hungarian_prefixes') is TJSONArray then
  begin
    Naming.HungarianPrefixes:= nil;
    for var HV in (NJ.GetValue('hungarian_prefixes') as TJSONArray) do
      Naming.HungarianPrefixes:= Naming.HungarianPrefixes + [HV.Value];
  end;
end;

procedure TLintConfig.ApplyDisallowedObject(const ABlock: TJSONObject; AReplace: Boolean);

  { One list key into AList; ALabel names it in errors. }
  procedure ApplyEntries(const AKey: string; var AList: TArray<TDisallowedEntry>);
  var
    Arr  : TJSONArray;
    V, G : TJSONValue;
    O    : TJSONObject;
    E    : TDisallowedEntry;
    Idx  : Integer;
  begin
    if ABlock.GetValue(AKey) = nil then Exit;
    if (ABlock.GetValue(AKey) is not TJSONArray) then
      raise ELintConfigError.CreateFmt('config: disallowed.%s must be an array of objects', [AKey]);
    Arr:= ABlock.GetValue(AKey) as TJSONArray;
    if AReplace then AList:= nil;
    Idx:= 0;
    for V in Arr do
    begin
      if (V is not TJSONObject) then
        raise ELintConfigError.CreateFmt('config: disallowed.%s[%d] must be an object with "name"', [AKey, Idx]);
      O:= V as TJSONObject;
      E:= Default(TDisallowedEntry);
      if (O.GetValue('name') is not TJSONString) or (Trim(O.GetValue('name').Value) = '') then
        raise ELintConfigError.CreateFmt('config: disallowed.%s[%d] needs a non-empty string "name"', [AKey, Idx]);
      E.Name:= Trim(O.GetValue('name').Value);
      if O.GetValue('reason') <> nil then
      begin
        if (O.GetValue('reason') is not TJSONString) then
          raise ELintConfigError.CreateFmt('config: disallowed.%s[%d].reason must be a string', [AKey, Idx]);
        E.Reason:= O.GetValue('reason').Value;
      end;
      if O.GetValue('except') <> nil then
      begin
        if (O.GetValue('except') is not TJSONArray) then
          raise ELintConfigError.CreateFmt('config: disallowed.%s[%d].except must be an array of glob strings', [AKey, Idx]);
        for G in (O.GetValue('except') as TJSONArray) do
        begin
          if (G is not TJSONString) then
            raise ELintConfigError.CreateFmt('config: disallowed.%s[%d].except holds a non-string', [AKey, Idx]);
          E.Exempt:= E.Exempt + [G.Value];
        end;
      end;
      AList:= AList + [E];
      Inc(Idx);
    end;
  end;

var
  Pair: TJSONPair;
begin
  for Pair in ABlock do
    if not (SameText(Pair.JsonString.Value, 'methods') or SameText(Pair.JsonString.Value, 'types')
      or SameText(Pair.JsonString.Value, 'names')) then
      raise ELintConfigError.CreateFmt('config: unknown key disallowed.%s (expected methods, types or names)',
        [Pair.JsonString.Value]);
  ApplyEntries('methods', DisallowedMethods);
  ApplyEntries('types', DisallowedTypes);
  ApplyEntries('names', DisallowedNames);
end;

procedure TLintConfig.ApplyConfigObject(const AObj: TJSONObject; AReplace: Boolean);

  { One top-level string-array key into AList: a profile (AReplace) replaces
    the list, the top level appends. An absent or non-array key leaves it. }
  procedure ApplyList(const AKey: string; var AList: TArray<string>);
  var
    V: TJSONValue;
  begin
    if not (AObj.GetValue(AKey) is TJSONArray) then Exit;
    if AReplace then AList:= nil;
    for V in (AObj.GetValue(AKey) as TJSONArray) do AList:= AList + [V.Value];
  end;

var
  Pair: TJSONPair;
begin
  if AObj = nil then Exit;
  ApplyList('disabled', FDisabled);
  ApplyList('enabled', FEnabled);
  ApplyList('autofix', FAutoFix);
  ApplyList('exclude_paths', FExcludePaths);
  ApplyList('ifdef_allow', IfdefAllow);
  ApplyList('platform_divergent_allow', PlatformDivergentAllow);
  { two-way modernize (1.38): a scalar, so a profile simply overrides it }
  if AObj.GetValue('target_compiler') <> nil then TargetCompiler:= Trim(AObj.GetValue('target_compiler').Value);
  if AObj.GetValue('severity') is TJSONObject then
  begin
    { profile semantics: update-or-add each severity key; base keys not
      mentioned in the profile are inherited unchanged (consistent with thresholds) }
    for Pair in (AObj.GetValue('severity') as TJSONObject) do
      SetSeverityPair(Pair.JsonString.Value, Pair.JsonValue.Value);
  end;
  if AObj.GetValue('thresholds') is TJSONObject then
  begin
    if AReplace then
    begin
      { profile semantics: update-or-add each threshold key; base keys not
        mentioned in the profile are inherited unchanged }
      for Pair in (AObj.GetValue('thresholds') as TJSONObject) do
      begin
        var I: Integer;
        var Found: Boolean:= False;
        for I:= 0 to High(FThreshNames) do
          if SameText(FThreshNames[I], Pair.JsonString.Value) then
          begin
            FThreshValues[I]:= StrToIntDef(Pair.JsonValue.Value, 0);
            Found:= True;
            Break;
          end;
        if not Found then
        begin
          FThreshNames := FThreshNames  + [Pair.JsonString.Value              ];
          FThreshValues:= FThreshValues + [StrToIntDef(Pair.JsonValue.Value, 0)];
        end;
      end;
    end
    else
    begin
      for Pair in (AObj.GetValue('thresholds') as TJSONObject) do
      begin
        FThreshNames := FThreshNames  + [Pair.JsonString.Value                    ];
        FThreshValues:= FThreshValues + [StrToIntDef(Pair.JsonValue.Value, 0)];
      end;
    end;
  end;
  if AObj.GetValue('disallowed') <> nil then
  begin
    if (AObj.GetValue('disallowed') is not TJSONObject) then
      raise ELintConfigError.Create('config: "disallowed" must be an object with methods/types/names lists');
    ApplyDisallowedObject(AObj.GetValue('disallowed') as TJSONObject, AReplace);
  end;
  if AObj.GetValue('naming') is TJSONObject then
    ApplyNamingObject(AObj.GetValue('naming') as TJSONObject);
  { taint wave T2: the `taint` object is merged by TTaintRules.LoadConfig }
  if AObj.GetValue('taint') is TJSONObject then
    TaintJson:= TaintJson + [AObj.GetValue('taint').ToJSON];
  { The "exceptions" block, key "unit" -- names the unit that owns the project's
    exception classes. Absent leaves ExceptionsUnit empty, which is the feature's
    off switch. NB: no JSON braces in this comment on purpose; a closing brace
    inside a brace comment ENDS it, which cost a build here on 2026-08-25. }
  if AObj.GetValue('exceptions') is TJSONObject then
  begin
    var ExcObj: TJSONObject:= AObj.GetValue('exceptions') as TJSONObject;
    if ExcObj.GetValue('unit') <> nil then ExceptionsUnit:= ExcObj.GetValue('unit').Value
    else ExceptionsUnit:= DEFAULT_EXCEPTIONS_UNIT;
    if ExcObj.GetValue('root') <> nil then ExceptionsRoot:= ExcObj.GetValue('root').Value
    else ExceptionsRoot:= DEFAULT_EXCEPTIONS_ROOT;
  end;
end;

class function TLintConfig.Load(const APath, AProfile: string): TLintConfig;
var
  Root    : TJSONObject;
  Profiles: TJSONObject;
  RawText : string     ;
  RootVal : TJSONValue ;
begin
  Result:= Default(TLintConfig);
  Result.Naming:= TNamingConfig.Default;
  if (APath = '') or (not TFile.Exists(APath)) then Exit;
  RawText:= TFile.ReadAllText(APath, TEncoding.UTF8);
  RootVal:= TJSONObject.ParseJSONValue(RawText);
  if not (RootVal is TJSONObject) then begin RootVal.Free; Exit; end;
  try
    Root:= RootVal as TJSONObject;
    Result.ApplyConfigObject(Root, False);
    if (AProfile <> '') and (Root.GetValue('profiles') is TJSONObject) then
    begin
      Profiles:= Root.GetValue('profiles') as TJSONObject;
      if Profiles.GetValue(AProfile) is TJSONObject then
      begin
        Result.UserProfileFound:= True;
        Result.ApplyConfigObject(Profiles.GetValue(AProfile) as TJSONObject, True);
      end;
    end;
  finally
    RootVal.Free;
  end;
end;

function TLintConfig.ApplySeverity(const ARuleId, ADefault: string): string;
var
  i: Integer;
begin
  for i:= 0 to High(FSevNames) do
    if SameText(FSevNames[i], ARuleId) then Exit(FSevValues[i]);
  Result:= ADefault;
end;

function TLintConfig.ShouldKeep(const ARuleId: string; ADefaultDisabled: Boolean): Boolean;
begin
  if Contains(FDisabled, ARuleId) then Exit(False);
  if ADefaultDisabled and (not Contains(FEnabled, ARuleId)) then Exit(False);
  Result:= True;
end;

function TLintConfig.IsEnabled(const ARuleId: string): Boolean;
begin
  Result:= ShouldKeep(ARuleId, False);
end;

function TLintConfig.IsAutoFix(const ARuleId: string): Boolean;
begin
  Result:= Contains(FAutoFix, ARuleId);
end;

function TLintConfig.IsPathExcluded(const AFilePath: string): Boolean;
begin
  Result:= MatchesAnyGlob(AFilePath, FExcludePaths);
end;

class function TLintConfig.MatchesAnyGlob(const AFilePath: string; const AGlobs: TArray<string>): Boolean;
var
  G: string;
begin
  Result:= False;
  if (Length(AGlobs) = 0) or (AFilePath = '') then Exit;
  { MatchesMask on the LOWERCASED path, with '/' folded to '\': an author writes
    the glob one way and Windows hands us the other, and a filter that silently
    fails to match is the worst outcome here -- it reports a full scan while
    quietly linting what the config said to skip. }
  var P: string:= LowerCase(StringReplace(AFilePath, '/', '\', [rfReplaceAll]));
  for G in AGlobs do
    if (G <> '') and MatchesMask(P, LowerCase(StringReplace(G, '/', '\', [rfReplaceAll]))) then
      Exit(True);
end;

function TLintConfig.ThresholdFor(const AName: string; ADefault: Integer): Integer;
var
  i: Integer;
begin
  for i:= 0 to High(FThreshNames) do
    if SameText(FThreshNames[i], AName) then Exit(FThreshValues[i]);
  Result:= ADefault;
end;

procedure TLintConfig.AddEnabled(const AIds: TArray<string>);
var
  S: string;
begin
  for S in AIds do
    if Trim(S) <> '' then FEnabled:= FEnabled + [Trim(S)];
end;

procedure TLintConfig.AddDisabled(const AIds: TArray<string>);
var
  S: string;
begin
  for S in AIds do
    if Trim(S) <> '' then FDisabled:= FDisabled + [Trim(S)];
end;

procedure TLintConfig.AddAutoFix(const AIds: TArray<string>);
var
  S: string;
begin
  for S in AIds do
    if Trim(S) <> '' then FAutoFix:= FAutoFix + [Trim(S)];
end;

function TLintConfig.DisabledIds: TArray<string>;
begin
  Result:= FDisabled;
end;

function TLintConfig.EnabledIds: TArray<string>;
begin
  Result:= FEnabled;
end;

function TLintConfig.AutoFixIds: TArray<string>;
begin
  Result:= FAutoFix;
end;

function TLintConfig.SeverityPairs: TArray<TPair<string,string>>;
var
  i: Integer;
begin
  SetLength(Result, Length(FSevNames));
  for i:= 0 to High(FSevNames) do
    Result[i]:= TPair<string,string>.Create(FSevNames[i], FSevValues[i]);
end;

function TLintConfig.ThresholdPairs: TArray<TPair<string,Integer>>;
var
  i: Integer;
begin
  SetLength(Result, Length(FThreshNames));
  for i:= 0 to High(FThreshNames) do
    Result[i]:= TPair<string,Integer>.Create(FThreshNames[i], FThreshValues[i]);
end;

procedure TLintConfig.SetDisabled(const AIds: TArray<string>);
begin
  FDisabled:= AIds;
end;

procedure TLintConfig.SetEnabled(const AIds: TArray<string>);
begin
  FEnabled:= AIds;
end;

procedure TLintConfig.SetAutoFix(const AIds: TArray<string>);
begin
  FAutoFix:= AIds;
end;

procedure TLintConfig.SetSeverityPair(const AId, ASev: string);
var
  i: Integer;
begin
  for i:= 0 to High(FSevNames) do
    if SameText(FSevNames[i], AId) then
    begin
      FSevValues[i]:= ASev;
      Exit;
    end;
  FSevNames := FSevNames  + [AId];
  FSevValues:= FSevValues + [ASev];
end;

procedure TLintConfig.SetThresholdPair(const AName: string; AValue: Integer);
var
  i: Integer;
begin
  for i:= 0 to High(FThreshNames) do
    if SameText(FThreshNames[i], AName) then
    begin
      FThreshValues[i]:= AValue;
      Exit;
    end;
  FThreshNames := FThreshNames  + [AName];
  FThreshValues:= FThreshValues + [AValue];
end;

end.
