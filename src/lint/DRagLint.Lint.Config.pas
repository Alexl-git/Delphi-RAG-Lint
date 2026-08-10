unit DRagLint.Lint.Config;

interface

uses
  System.SysUtils, System.JSON, System.IOUtils, System.Generics.Collections,
  DRagLint.Core.Model;

type
  /// <summary>Configurable naming conventions read from the drag-lint-lint.json
  /// "naming" block. Empty-string prefixes disable that prefix check; empty
  /// ConstCase disables const casing. KeywordCase='' disables reserved-word-casing;
  /// ShortIdentifierCheck=False (default) disables hungarian-or-short-identifier.
  /// Defaults match the project conventions (TMyClass / EMyException / IMyIntf /
  /// PMyType / FMyField / pMyParam, PascalCase, lowercase keywords).</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// Used by: declaration (DRagLint.Diagnostics.NamingChecks.pas), DRagLint.Diagnostics.NamingChecks.TNamingChecker.Check (DRagLint.Diagnostics.NamingChecks.pas), declaration (DRagLint.Lint.Config.pas), DRagLint.Lint.Config.TLintConfig.Load (DRagLint.Lint.Config.pas), declaration (DRagLint.Refactor.NamingFix.pas)
  /// Used in units: DRagLint.Diagnostics.NamingChecks, DRagLint.Lint.Config, DRagLint.Refactor.NamingFix
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
    /// Called from: DRagLint.Lint.Config.TLintConfig.Load (DRagLint.Lint.Config.pas), DRagLint.CLI.ParseArgs (DRagLint.CLI.pas) ?, DRagLint.CLI.ResolveIndexProfile (DRagLint.CLI.pas) ?, DRagLint.CLI.DoScanAll (DRagLint.CLI.pas) ?, DRagLint.CLI.DoResolveUses (DRagLint.CLI.pas) ? (+37 more)
    /// Pure
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
  /// Used by: DRagLint.CLI.LoadLintConfig (DRagLint.CLI.pas), DRagLint.CLI.FinalizeAndOutput (DRagLint.CLI.pas), DRagLint.CLI.DoLint (DRagLint.CLI.pas), DRagLint.CLI.DoLintAll (DRagLint.CLI.pas), declaration (DRagLint.Lint.ClassMetrics.pas) (+3 more)
  /// Used in units: DRagLint.CLI, DRagLint.Lint.ClassMetrics, DRagLint.Lint.Config, DRagLint.LSP.Completion
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
    /// <param name="AArr"><!-- drag-lint:auto type -->const TArray&lt;string&gt;</param>
    /// <param name="AId"><!-- drag-lint:auto type -->const string</param>
    /// <returns><!-- drag-lint:auto -->Observed: False.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.Lint.Config.TLintConfig.IsAutoFix (DRagLint.Lint.Config.pas), DRagLint.Lint.Config.TLintConfig.ShouldKeep (DRagLint.Lint.Config.pas), DRagLint.CLI.DoCycles (DRagLint.CLI.pas) ?, DRagLint.CLI.ErrorSignatures (DRagLint.CLI.pas) ?, DRagLint.CLI.ResolveEndpointIds (DRagLint.CLI.pas) ? (+2 more)
    /// Calls: SameText, Trim
    /// Pure
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
    /// Called from: DRagLint.Lint.Config.TLintConfig.ApplyConfigObject (DRagLint.Lint.Config.pas)
    /// Calls: SameText, StrToIntDef
    /// Complexity: 16 (cyclomatic, outer body), 37 lines (full implementation)
    /// Reads: Naming
    /// Pure
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
    /// Calls: DRagLint.Lint.Config.TLintConfig.ApplyNamingObject, DRagLint.Lint.Config.TLintConfig.SetSeverityPair, SameText, StrToIntDef, unchanged
    /// Complexity: 15 (cyclomatic, outer body), 63 lines (full implementation)
    /// Reads: FDisabled, FEnabled, FAutoFix, FThreshNames, FThreshValues   Writes: FDisabled, FEnabled, FAutoFix, FThreshNames, FThreshValues
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.ApplyNamingObject"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.SetSeverityPair"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.AddAutoFix"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.AddDisabled"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.AddEnabled"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure ApplyConfigObject(const AObj: TJSONObject; AReplace: Boolean);
  public
    /// <summary>Naming conventions parsed from the "naming" block; always
    /// populated with TNamingConfig.Default when no block is present.</summary>
    Naming: TNamingConfig;
    /// <summary>Loads config from APath (JSON). Empty/missing APath yields a
    /// no-op default config. If AProfile is non-empty and present under
    /// "profiles", the profile is merged over the top-level values: list fields
    /// (disabled, enabled) are replaced wholesale; map fields (severity,
    /// thresholds, naming) are updated per-key so base entries the profile
    /// omits are inherited unchanged.</summary>
    /// <param name="APath"><!-- drag-lint:auto type -->const string</param>
    /// <param name="AProfile"><!-- drag-lint:auto type -->const string</param>
    /// <returns><!-- drag-lint:auto -->Observed: Default(TLintConfig).</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.CLI.LoadLintConfig (DRagLint.CLI.pas), DRagLint.LSP.Completion.TLspCompletion.BuildDiagnostics (DRagLint.LSP.Completion.pas)
    /// Calls: DRagLint.Lint.Config.TNamingConfig.Default
    /// Touches: file system
    /// <seealso cref="DRagLint.Lint.Config.TNamingConfig.Default"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.AddAutoFix"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.AddDisabled"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.AddEnabled"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.ApplyConfigObject"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function Load(const APath, AProfile: string): TLintConfig; static;
    /// <summary>Returns the configured severity for ARuleId, else ADefault.</summary>
    /// <param name="ARuleId"><!-- drag-lint:auto type -->const string</param>
    /// <param name="ADefault"><!-- drag-lint:auto type -->const string</param>
    /// <returns><!-- drag-lint:auto -->Observed: ADefault.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.CLI.FinalizeAndOutput (DRagLint.CLI.pas), DRagLint.LSP.Completion.TLspCompletion.BuildDiagnostics (DRagLint.LSP.Completion.pas)
    /// Calls: SameText
    /// Reads: FSevNames, FSevValues
    /// Pure
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
    /// <returns><!-- drag-lint:auto -->Observed: True.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.CLI.FinalizeAndOutput (DRagLint.CLI.pas), DRagLint.LSP.Completion.TLspCompletion.BuildDiagnostics (DRagLint.LSP.Completion.pas), DRagLint.Lint.Config.TLintConfig.IsEnabled (DRagLint.Lint.Config.pas)
    /// Calls: DRagLint.Lint.Config.TLintConfig.Contains
    /// Reads: FDisabled, FEnabled
    /// Pure
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
    /// <returns><!-- drag-lint:auto -->Observed: ShouldKeep(ARuleId, False).</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Calls: DRagLint.Lint.Config.TLintConfig.ShouldKeep
    /// Pure
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
    /// <returns><!-- drag-lint:auto -->Observed: Contains(FAutoFix, ARuleId).</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.CLI.FinalizeAndOutput (DRagLint.CLI.pas)
    /// Calls: DRagLint.Lint.Config.TLintConfig.Contains
    /// Reads: FAutoFix
    /// Pure
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.Contains"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.AddAutoFix"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.AddDisabled"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.AddEnabled"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.ApplyConfigObject"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function IsAutoFix(const ARuleId: string): Boolean;
    /// <summary>Returns the configured threshold for AName, else ADefault.</summary>
    /// <param name="AName"><!-- drag-lint:auto type -->const string</param>
    /// <param name="ADefault"><!-- drag-lint:auto type -->Integer</param>
    /// <returns><!-- drag-lint:auto -->Observed: ADefault.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Called from: DRagLint.Lint.ClassMetrics.TClassMetrics.Run (DRagLint.Lint.ClassMetrics.pas), DRagLint.CLI.DoLint (DRagLint.CLI.pas) ?, DRagLint.CLI.DoLintAll (DRagLint.CLI.pas) ?
    /// Calls: SameText
    /// Reads: FThreshNames, FThreshValues
    /// Pure
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
    /// Calls: Trim
    /// Reads: FEnabled   Writes: FEnabled
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
    /// Calls: Trim
    /// Reads: FDisabled   Writes: FDisabled
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
    /// Calls: Trim
    /// Reads: FAutoFix   Writes: FAutoFix
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
    /// <returns><!-- drag-lint:auto -->Observed: FDisabled.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Reads: FDisabled
    /// Owns returned: borrowed
    /// Pure
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.AddAutoFix"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.AddDisabled"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.AddEnabled"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.ApplyConfigObject"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.ApplyNamingObject"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function DisabledIds: TArray<string>;
    /// <summary>Returns a copy of the enabled rule-id list.</summary>
    /// <returns><!-- drag-lint:auto -->Observed: FEnabled.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Reads: FEnabled
    /// Owns returned: borrowed
    /// Pure
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.AddAutoFix"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.AddDisabled"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.AddEnabled"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.ApplyConfigObject"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.ApplyNamingObject"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    function EnabledIds: TArray<string>;
    /// <summary>Returns a copy of the auto-fix rule-id list.</summary>
    /// <returns><!-- drag-lint:auto -->Observed: FAutoFix.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// Reads: FAutoFix
    /// Owns returned: borrowed
    /// Pure
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
    /// Reads: FSevNames, FSevValues
    /// Pure
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
    /// Reads: FThreshNames, FThreshValues
    /// Pure
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
    /// Writes: FDisabled
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
    /// Writes: FEnabled
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
    /// Writes: FAutoFix
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
    /// Called from: DRagLint.Lint.Config.TLintConfig.ApplyConfigObject (DRagLint.Lint.Config.pas)
    /// Calls: SameText
    /// Reads: FSevNames, FSevValues   Writes: FSevNames, FSevValues
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
    /// Calls: SameText
    /// Reads: FThreshNames, FThreshValues   Writes: FThreshNames, FThreshValues
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.AddAutoFix"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.AddDisabled"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.AddEnabled"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.ApplyConfigObject"/>
    /// <seealso cref="DRagLint.Lint.Config.TLintConfig.ApplyNamingObject"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    procedure SetThresholdPair(const AName: string; AValue: Integer);
  end;

implementation

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

procedure TLintConfig.ApplyConfigObject(const AObj: TJSONObject; AReplace: Boolean);
var
  Pair: TJSONPair;
  V   : TJSONValue;
begin
  if AObj = nil then Exit;
  if AObj.GetValue('disabled') is TJSONArray then
  begin
    if AReplace then FDisabled:= nil;
    for V in (AObj.GetValue('disabled') as TJSONArray) do FDisabled:= FDisabled + [V.Value];
  end;
  if AObj.GetValue('enabled') is TJSONArray then
  begin
    if AReplace then FEnabled:= nil;
    for V in (AObj.GetValue('enabled') as TJSONArray) do FEnabled:= FEnabled + [V.Value];
  end;
  if AObj.GetValue('autofix') is TJSONArray then
  begin
    if AReplace then FAutoFix:= nil;
    for V in (AObj.GetValue('autofix') as TJSONArray) do FAutoFix:= FAutoFix + [V.Value];
  end;
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
  if AObj.GetValue('naming') is TJSONObject then
    ApplyNamingObject(AObj.GetValue('naming') as TJSONObject);
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
        Result.ApplyConfigObject(Profiles.GetValue(AProfile) as TJSONObject, True);
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
