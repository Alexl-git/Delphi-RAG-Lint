unit DRagLint.Lint.RuleCatalog;

{ Single machine-readable catalog of every drag-lint rule. The BUILT-IN registry
  below is the one place that knows each built-in's category / title / default
  severity / default-enabled / parameters. External .scm rules are merged in by
  BuildCatalog (source:"scm"); their severity/message come from the sidecar json
  and their category from ScmCategory(). Pure metadata -- no analysis logic. }

interface

uses
  System.SysUtils, System.StrUtils, System.Generics.Collections, System.Generics.Defaults,
  System.JSON, System.IOUtils, System.Hash,
  DRagLint.Lint.Compliance;

const
  { THE complexity thresholds. ONE definition, read by BOTH the rule catalog
    below AND every checker call site in DRagLint.CLI -- which previously
    repeated the literals 15 / 25 / 120 at six places. That is the drift channel
    this codebase keeps paying for: the catalog advertises a default, a call
    site passes a different one, and `drag-lint rules` then documents a number
    the engine does not use.

    Retuned 2026-08-10 from 15 / 25 / 120 after measuring the distribution over
    drag-lint's own 94 files -- see the catalog entries for the arithmetic.
    Overridable per project via `thresholds` in drag-lint-lint.json. }
  DEFAULT_CYCLOMATIC_THRESHOLD = 30 ; // was 15; median flagged value was 22
  DEFAULT_COGNITIVE_THRESHOLD  = 65 ; // was 25; median flagged value was 40
  DEFAULT_METHOD_TOO_LONG      = 250; // was 120; median flagged body was 182

const
  { THE PER-FILE RULES THAT SHIP OFF BY DEFAULT, IN ONE PLACE.

    A catalog entry's default_enabled=False does NOT suppress output on its own:
    every surface that reports findings has to hand these ids to
    TLintConfig.ShouldKeep as the "default-disabled" set, or the rule is
    published anyway. The CLI's `lint` and `lint-all` verbs each wrote that list
    out by hand, and the LSP -- a THIRD surface, and the one the IDE gutter
    actually reads -- wrote no list at all: DRagLint.LSP.Completion passed a
    literal False for every rule. Measured on this repo, that published 461
    string-equality-comparison plus 888 nil-comparison marks that the CLI hides,
    1,349 spurious gutter marks whose only effect is to teach a reader to skim.

    So it is ONE list, and it lives in the catalog -- the unit that already owns
    rule ids and is a leaf, so the CLI, the LSP and anything later can all see
    it. This is the same ruling PROJECT_RULES_OFF_BY_DEFAULT records in
    DRagLint.CLI for the project-level rules; those stay there because only the
    project verbs can emit them, whereas every id below is reachable from a
    single-file lint.

    Why each one is off (the reasons the two CLI copies carried):
      function-result-ignored     FP-prone -- builders/adders/runners legitimately
                                  discard a result.
      unsafe-typecast-without-is  an unguarded hard cast is usually provably safe
                                  to the author.
      exhaustive-enum-case        handling a deliberate subset with no else is
                                  ordinary.
      interface-object-mixing     first-cut same-routine dual-handle heuristic.
      multiple-statements-per-line pure style.
      magic-literal               medium-FP; floods legacy code.
      boolean-flag-parameter      a common, deliberate idiom here.
      commented-out-code          owner ruling 2026-08-13: parking code is a
                                  working habit, and the rule cannot tell code
                                  from PROSE ABOUT code.
      string-equality-comparison  a CENSUS, not a defect check -- it fires on
                                  every string '=' and cannot tell "meant
                                  case-insensitive" from "meant case-sensitive";
                                  its top sites are AST tag comparisons where
                                  SameText would be a BUG. 406 findings here.
      nil-comparison              reports a STYLE PREFERENCE on every nil test;
                                  `<> nil` is deliberate on non-object pointers.
                                  311 findings here.
      public-writable-field       measured 44 findings in 6/103 files, almost all
                                  intentional record-like data carriers.
      loop-control-flag           the riskiest heuristic of its batch.
      mutable-global-variable     68 findings across 27/103 files, mostly
                                  legitimate singletons/caches.
      default-encoding-io         65 findings, mostly ReadAllText on known-ASCII
                                  project/config files.
      split-variable              a refactoring hint, not a bug.
      separate-query-from-modifier CQS is inherently noisy (lazy getters, fluent
                                  mutators).
      ifdef-undefined-symbol      measured 2026-09-23 on ORM3 CLIENT (151 of its
                                  152 .dproj members): 175 findings, but only 6
                                  distinct symbols -- TRACE_BP (and BP3/BP6),
                                  TRACE_CODESITE, M2022_REFERENCE, NOABLAS --
                                  all deliberate OFF switches for trace code,
                                  none a typo. Dead in every build is true;
                                  worth a warning per site is not. Opt in to
                                  hunt typos, or list the switches in
                                  ifdef_allow.
      review-marker-reason-unreviewed  owner ruling OWN-7 2026-09-23: the
                                  REVIEWED stamp is new, so every existing
                                  dl:ok would report at once. Opt in per project.

    Every one of them is opt-in, unchanged: `--rule <id>` on the CLI, or
    "enabled":["<id>"] in drag-lint-lint.json, which ShouldKeep honours. }
  BUILTIN_RULES_OFF_BY_DEFAULT: TArray<string> = [
    'function-result-ignored', 'unsafe-typecast-without-is', 'exhaustive-enum-case',
    'interface-object-mixing', 'multiple-statements-per-line', 'magic-literal',
    'boolean-flag-parameter', 'commented-out-code', 'string-equality-comparison',
    'nil-comparison', 'public-writable-field', 'loop-control-flag',
    'mutable-global-variable', 'default-encoding-io', 'split-variable',
    'separate-query-from-modifier', 'ifdef-undefined-symbol', 'review-marker-reason-unreviewed',
    { clippy-parity wave (L0): OFF-by-default new built-ins }
    'else-after-exit', 'missing-const-param', 'local-shadows-field', 'method-could-be-static',
    'too-many-bool-fields', 'index-loop-to-for-in',
    { gap-rules wave (G0): OFF-by-default new built-ins }
    'copy-paste-assignment', 'unused-loop-variable', 'virtual-never-overridden'];

  { THE WHOLE-ROUTINE METRIC RULES, in one place because the CHECKER and the
    `allow` WRITER must agree on the list or a marker is written under one hash
    scheme and verified under the other.

    What they share: the finding anchors on the routine's HEADER line while its
    subject is the entire routine, and its message quotes a NUMBER. That
    combination is what made a `dl:ok` on one of them unable to go stale -- the
    marker hash covers the declaration line, which does not change when the body
    grows. Measured before the fix: allow a 6-exit routine, add a seventh Exit,
    and `lint` reports nothing at all, neither the finding nor a stale marker.

    duplicate-code is deliberately NOT here. It is block-scoped rather than
    routine-scoped and carries no single metric its review is about. }
  ROUTINE_METRIC_RULES: TArray<string> = [
    'too-many-exit-points', 'cyclomatic-complexity', 'cognitive-complexity',
    'method-too-long', 'too-many-locals', 'too-many-parameters', 'deep-nesting'];

type
  /// <summary>A single configurable parameter of a rule (threshold or naming knob).</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: [drag-lint]declaration (DRagLint.Lint.RuleCatalog.pas), [drag-lint]DRagLint.CLI.DoRules (DRagLint.CLI.pas), [drag-lint]DRagLint.CLI.DoRules.AddParamsJson (DRagLint.CLI.pas), [drag-lint]DRagLint.Lint.RuleCatalog.MkParam (DRagLint.Lint.RuleCatalog.pas), [drag-lint]DRagLint.Lint.RuleCatalog.TRuleCatalog.BuiltinRegistry.B (DRagLint.Lint.RuleCatalog.pas)</para>
  /// <para>Used in units: DRagLint.CLI, DRagLint.Lint.RuleCatalog, DragLint.Plugin.LintOptionsFrame</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TRuleParam = record
    Name      : string;  // config key (e.g. 'threshold', 'class_prefix')
    ParamType : string;  // 'int' | 'string' | 'stringlist' | 'bool'
    DefaultVal: string;  // textual default
  end;

  /// <summary>One catalogued rule.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Lint.RuleCatalog.pas), DRagLint.CLI.ApplyLineMarkers (DRagLint.CLI.pas), DRagLint.CLI.DoAllow (DRagLint.CLI.pas), DRagLint.CLI.DoLint (DRagLint.CLI.pas), DRagLint.CLI.DoRules (DRagLint.CLI.pas) (+4 more)</para>
  /// <para>Used in units: DRagLint.CLI, DRagLint.Lint.RuleCatalog</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TRuleInfo = record
    Id             : string;
    Category       : string;  // one of the 12 canonical buckets
    Title          : string;
    DefaultSeverity: string;  // 'hint' | 'info' | 'warning' | 'error'
    Source         : string;  // 'builtin' | 'scm'
    DefaultEnabled : Boolean;
    HasSidecarFix  : Boolean; // .scm only: its sidecar .json carries a "fix" key (autofix wave A0)
    Params         : TArray<TRuleParam>;
    Compliance     : TComplianceLabels;  // rules\compliance.json row; empty when unlabelled
  end;

  /// <summary>Per-category and total rule counts for the catalog summary.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Lint.RuleCatalog.pas), DRagLint.CLI.DoRules (DRagLint.CLI.pas), DRagLint.Lint.RuleCatalog.TRuleCatalog.Summarize (DRagLint.Lint.RuleCatalog.pas)</para>
  /// <para>Used in units: DRagLint.CLI, DRagLint.Lint.RuleCatalog</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TCatalogSummary = record
    Total      : Integer;
    Categories : Integer;
    PerCategory: TArray<TPair<string, Integer>>;  // (category, count), category order = first-seen
  end;

  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.CLI.ApplyLineMarkers (DRagLint.CLI.pas), DRagLint.CLI.DoAllow (DRagLint.CLI.pas), DRagLint.CLI.DoLint (DRagLint.CLI.pas), DRagLint.CLI.DoRules (DRagLint.CLI.pas)</para>
  /// <para>Used in units: DRagLint.CLI</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TRuleCatalog = class
  public
    /// <summary>Set by the last <see cref="BuildCatalog"/>: the compliance.json error text, '' when fine.</summary>
    class var ComplianceError: string;
    /// <summary>The in-code registry of all built-in rules (no .scm).</summary>
    /// <returns><!-- drag-lint:auto -->TArray&lt;TRuleInfo&gt; -- Observed: L.ToArray.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Lint.RuleCatalog.TRuleCatalog.BuildCatalog (DRagLint.Lint.RuleCatalog.pas)</para>
    /// <para>Calls: DRagLint.Lint.RuleCatalog.MkParam, DRagLint.Lint.RuleCatalog.TRuleCatalog.BuiltinRegistry.B, IntToStr</para>
    /// <para>Directives: static</para>
    /// <seealso cref="DRagLint.Lint.RuleCatalog.MkParam"/>
    /// <seealso cref="DRagLint.Lint.RuleCatalog.TRuleCatalog.BuiltinRegistry.B"/>
    /// <seealso cref="DRagLint.Lint.RuleCatalog.TRuleCatalog.BuildCatalog"/>
    /// <seealso cref="DRagLint.Lint.RuleCatalog.TRuleCatalog.ScmCategory"/>
    /// <seealso cref="DRagLint.Lint.RuleCatalog.TRuleCatalog.Summarize"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function BuiltinRegistry: TArray<TRuleInfo>; static;
    /// <summary>Full catalog: built-ins + external .scm rules from ARulesDir
    /// (default &lt;exe-dir&gt;\rules). Deduped by id (builtin wins). Sorted by
    /// (category, id). When ACategory&lt;&gt;'' only that category is returned.</summary>
    /// <param name="ARulesDir"><!-- drag-lint:auto type -->const string = ''</param>
    /// <param name="ACategory"><!-- drag-lint:auto type -->const string = ''</param>
    /// <param name="AWithLabels">True (default): fill each rule's Compliance from
    /// rules\compliance.json and set ComplianceError. False: skip that file entirely --
    /// Compliance stays empty and ComplianceError is left untouched -- for a caller that
    /// only needs the rule ids (the review-marker pass), which saves the compliance.json
    /// parse.</param>
    /// <returns><!-- drag-lint:auto -->TArray&lt;TRuleInfo&gt; -- Observed: Res.ToArray.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.CLI.ApplyLineMarkers (DRagLint.CLI.pas), DRagLint.CLI.DoAllow (DRagLint.CLI.pas), DRagLint.CLI.DoLint (DRagLint.CLI.pas), DRagLint.CLI.DoRules (DRagLint.CLI.pas)</para>
    /// <para>Calls: CompareText, DRagLint.Lint.RuleCatalog.TRuleCatalog.BuiltinRegistry, DRagLint.Lint.RuleCatalog.TRuleCatalog.ScmCategory, MatchStr, ParamStr, SameText</para>
    /// <para>Complexity: 15 (cyclomatic, outer body), 88 lines (full implementation)</para>
    /// <para>Catches: Exception (swallowed)</para>
    /// <para>Touches: file system</para>
    /// <para>Directives: static</para>
    /// <seealso cref="DRagLint.Lint.RuleCatalog.TRuleCatalog.BuiltinRegistry"/>
    /// <seealso cref="DRagLint.Lint.RuleCatalog.TRuleCatalog.ScmCategory"/>
    /// <seealso cref="DRagLint.Lint.RuleCatalog.TRuleCatalog.Summarize"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function BuildCatalog(const ARulesDir: string = '';
      const ACategory: string = ''; AWithLabels: Boolean = True): TArray<TRuleInfo>; static;
    /// <summary>Totals + per-category counts over ACatalog.</summary>
    /// <param name="ACatalog"><!-- drag-lint:auto type -->const TArray&lt;TRuleInfo&gt;</param>
    /// <returns><!-- drag-lint:auto type -->TCatalogSummary</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.CLI.DoRules (DRagLint.CLI.pas)</para>
    /// <para>Pure</para>
    /// <para>Directives: static</para>
    /// <seealso cref="DRagLint.Lint.RuleCatalog.TRuleCatalog.BuildCatalog"/>
    /// <seealso cref="DRagLint.Lint.RuleCatalog.TRuleCatalog.BuiltinRegistry"/>
    /// <seealso cref="DRagLint.Lint.RuleCatalog.TRuleCatalog.ScmCategory"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function Summarize(const ACatalog: TArray<TRuleInfo>): TCatalogSummary; static;
    /// <summary>Category bucket for an external .scm rule id; 'other' if unmapped.</summary>
    /// <param name="AId"><!-- drag-lint:auto type -->const string</param>
    /// <returns><!-- drag-lint:auto -->string -- Observed: 'bug-patterns';
    /// 'resource-lifetime'; 'security'; 'platform'; 'structure'; 'dead-code'.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Lint.RuleCatalog.TRuleCatalog.BuildCatalog (DRagLint.Lint.RuleCatalog.pas)</para>
    /// <para>Calls: MatchStr</para>
    /// <para>Pure</para>
    /// <para>Directives: static</para>
    /// <seealso cref="DRagLint.Lint.RuleCatalog.TRuleCatalog.BuildCatalog"/>
    /// <seealso cref="DRagLint.Lint.RuleCatalog.TRuleCatalog.BuiltinRegistry"/>
    /// <seealso cref="DRagLint.Lint.RuleCatalog.TRuleCatalog.Summarize"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function ScmCategory(const AId: string): string; static;
  end;

/// <summary>True when ARuleId is a whole-routine metric rule whose `dl:ok`
/// review must be bound to the measured value.</summary>
/// <param name="ARuleId">Rule id, compared case-insensitively.</param>
/// <returns>True for the seven ids in ROUTINE_METRIC_RULES.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.ApplyLineMarkers (DRagLint.CLI.pas), DRagLint.CLI.DoAllow (DRagLint.CLI.pas), DRagLint.LSP.Completion.TLspCompletion.BuildCodeActions (DRagLint.LSP.Completion.pas), DRagLint.LSP.Completion.TLspCompletion.BuildDiagnostics (DRagLint.LSP.Completion.pas), DRagLint.LSP.Completion.TLspCompletion.DiagnosticsFromLintJson (DRagLint.LSP.Completion.pas) (+1 more)</para>
/// <para>Calls: SameText</para>
/// <para>Returns: False</para>
/// <para>Pure</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function IsRoutineMetricRule(const ARuleId: string): Boolean;

/// <summary>The marker hash for a routine-metric finding: the ordinary window
/// hash, bound to the value the review was granted for.</summary>
/// <param name="AWindowHash">TReviewMarkers.HashWindow over the anchor line.</param>
/// <param name="AMetric">The finding's measured value (TLintFinding.Metric).</param>
/// <returns>Four lowercase hex digits, the same shape HashWindow returns, so the
/// marker GRAMMAR (`rule@hhhh`) is unchanged.</returns>
/// <remarks>
/// Lives here rather than in DRagLint.Lint.ReviewMarker deliberately:
/// that unit is mirrored byte-for-byte into YADF's vendor tree and pinned by
/// run_reviewmarker_yadf_mirror.ps1, so putting this there would drag an
/// unrelated repository into the change. Only what the four digits are computed
/// FROM changes -- the same kind of move f709bea already made once when HashLine
/// became HashWindow.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.DoAllow (DRagLint.CLI.pas), DRagLint.Lint.RuleCatalog.MarkerExpectedHash (DRagLint.Lint.RuleCatalog.pas), DRagLint.LSP.Completion.TLspCompletion.BuildCodeActions (DRagLint.LSP.Completion.pas)</para>
/// <para>Calls: Copy, IntToStr, LowerCase</para>
/// <para>Returns: LowerCase(Copy(THashSHA2.GetHashString(AWindowHash + '|' + IntToStr(AMetric)), 1, 4))</para>
/// <para>Pure</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function MetricHash(const AWindowHash: string; AMetric: Integer): string;

/// <summary>The hash a `dl:ok` marker must carry to verify against a finding:
/// TReviewMarkers.HashWindow at the anchor line, passed through MetricHash for
/// a routine-metric rule (IsRoutineMetricRule).</summary>
/// <param name="ALines">The finding's file, one entry per line.</param>
/// <param name="ARuleId">The finding's rule id.</param>
/// <param name="AStartLine">1-based anchor line (TLintFinding.StartLine).</param>
/// <param name="AMetric">The finding's measured value (TLintFinding.Metric);
/// ignored for a non-metric rule.</param>
/// <returns>Four lowercase hex digits.</returns>
/// <remarks>The ONE definition the CLI's ApplyLineMarkers and the LSP's
/// BuildDiagnostics both use (C2), feeding TReviewMarkers.Suppresses. Lives
/// here, not in ReviewMarker, for the same mirror reason as MetricHash. A finding
/// anchored on a `///` line is hashed at DocCommentMarkerLine, the declaration
/// the block documents, because that is where its marker lives. Pure.</remarks>
function MarkerExpectedHash(const ALines: TArray<string>; const ARuleId: string;
  AStartLine, AMetric: Integer): string;

/// <summary>The line that carries the `dl:ok` marker for a finding anchored on
/// ALine: ALine itself, unless ALine is a `///` DocInsight doc-comment line, in
/// which case the first line after that contiguous `///` block -- the
/// declaration the block documents.</summary>
/// <param name="ALines">The finding's file, one entry per line.</param>
/// <param name="ALine">1-based anchor line (TLintFinding.StartLine).</param>
/// <returns>A 1-based line &gt;= ALine. ALine when it is out of range, is not a
/// `///` line, or the block runs to the end of the file.</returns>
/// <remarks>H2 (2026-10-25). A marker written ON a `///` line becomes doc text
/// (`///` runs to end of line), so `allow` refused such lines and doc-drift --
/// which anchors on the block's first line -- could not be reviewed at all. The
/// declaration is not a guess: DocInsight attaches a `///` block to the
/// declaration that immediately follows it. Used by `allow` (where to write),
/// ApplyLineMarkers and the LSP (how far the suppression span reaches) and
/// MarkerExpectedHash (where the hash is taken), so the three agree. Pure.</remarks>
function DocCommentMarkerLine(const ALines: TArray<string>; ALine: Integer): Integer;

/// <summary>Records that rule AId carries a sidecar "fix" key, so the autofix
/// registry reports it fixable (autofix wave A0, 2026-10-27).</summary>
/// <param name="AId">The rule id; compared case-insensitively.</param>
/// <param name="ARisky">True when any of its fix entries is "risky": true.</param>
/// <remarks>Called by BuildCatalog for every sidecar it reads and by
/// TQueryRule.Create for every rule it loads, so `rules --json` and `lint --fix`
/// agree without either loading the other. Process-wide; thread-safe. A second
/// call for the same id ORs ARisky in.</remarks>
procedure RegisterSidecarFixRule(const AId: string; ARisky: Boolean);

/// <summary>Has rule AId been registered as carrying a sidecar fix?</summary>
/// <param name="AId">The rule id; compared case-insensitively.</param>
/// <param name="ARisky">Out: True when its fix is registered risky.</param>
/// <returns>True when RegisterSidecarFixRule was called for AId in this process.</returns>
function IsSidecarFixRule(const AId: string; out ARisky: Boolean): Boolean;


implementation

uses
  DRagLint.Lint.ReviewMarker;

var
  { id -> risky. Guarded by TMonitor on itself; created in initialization. }
  GSidecarFixes: TDictionary<string, Boolean>;

procedure RegisterSidecarFixRule(const AId: string; ARisky: Boolean);
var
  Prior: Boolean;
begin
  if AId = '' then Exit;
  TMonitor.Enter(GSidecarFixes);
  try
    if GSidecarFixes.TryGetValue(AId, Prior) then ARisky:= ARisky or Prior;
    GSidecarFixes.AddOrSetValue(AId, ARisky);
  finally
    TMonitor.Exit(GSidecarFixes);
  end;
end;

function IsSidecarFixRule(const AId: string; out ARisky: Boolean): Boolean;
begin
  TMonitor.Enter(GSidecarFixes);
  try
    Result:= GSidecarFixes.TryGetValue(AId, ARisky);
    if not Result then ARisky:= False;
  finally
    TMonitor.Exit(GSidecarFixes);
  end;
end;


{ True when a sidecar "fix" value (object or array of objects) has an entry
  marked "risky": true. }
function SidecarFixIsRisky(const AFix: TJSONValue): Boolean;
var
  V: TJSONValue;
begin
  Result:= False;
  if AFix is TJSONObject then
  begin
    V:= TJSONObject(AFix).GetValue('risky');
    Exit((V <> nil) and SameText(V.Value, 'true'));
  end;
  if AFix is TJSONArray then
    for var Item: TJSONValue in TJSONArray(AFix) do
      if SidecarFixIsRisky(Item) then Exit(True);
end;

function MarkerExpectedHash(const ALines: TArray<string>; const ARuleId: string;
  AStartLine, AMetric: Integer): string;
begin
  Result:= TReviewMarkers.HashWindow(ALines, DocCommentMarkerLine(ALines, AStartLine) - 1);
  if IsRoutineMetricRule(ARuleId) then Result:= MetricHash(Result, AMetric);
end;

function DocCommentMarkerLine(const ALines: TArray<string>; ALine: Integer): Integer;

  function IsDocLine(AIdx: Integer): Boolean;
  begin
    Result:= TrimLeft(ALines[AIdx]).StartsWith('///');
  end;

begin
  Result:= ALine;
  if (ALine < 1) or (ALine > Length(ALines)) or not IsDocLine(ALine - 1) then Exit;
  var Idx: Integer:= ALine; { 0-based index of the line after ALine }
  while (Idx < Length(ALines)) and IsDocLine(Idx) do Inc(Idx);
  if Idx < Length(ALines) then Result:= Idx + 1;
end;

function IsRoutineMetricRule(const ARuleId: string): Boolean;
var
  R: string;
begin
  for R in ROUTINE_METRIC_RULES do
    if SameText(R, ARuleId) then Exit(True);
  Result:= False;
end;

function MetricHash(const AWindowHash: string; AMetric: Integer): string;
begin
  Result:= LowerCase(Copy(THashSHA2.GetHashString(AWindowHash + '|' + IntToStr(AMetric)), 1, 4));
end;

function MkParam(const AName, AType, ADefault: string): TRuleParam;
begin
  Result.Name:= AName; Result.ParamType:= AType; Result.DefaultVal:= ADefault;
end;

class function TRuleCatalog.BuiltinRegistry: TArray<TRuleInfo>;
var
  L: TList<TRuleInfo>;
  procedure B(const AId, ACat, ASev, ATitle: string; AEnabled: Boolean = True;
    const AParams: TArray<TRuleParam> = nil);
  var R: TRuleInfo;
  begin
    R.Id:= AId; R.Category:= ACat; R.DefaultSeverity:= ASev; R.Title:= ATitle;
    R.Source:= 'builtin'; R.DefaultEnabled:= AEnabled; R.Params:= AParams;
    L.Add(R);
  end;
begin
  L:= TList<TRuleInfo>.Create;
  try
    { --- bug-patterns --- }
    B('syntax-error',                  'bug-patterns', 'error',   'Source has a syntax error');
    B('unbalanced-begin-end',          'bug-patterns', 'warning', 'Unbalanced begin/end');
    B('raise-in-finally',              'bug-patterns', 'warning', 'raise inside a finally block masks the in-flight exception');
    B('code-after-exit',               'bug-patterns', 'warning', 'Unreachable code after Exit/raise/Break/Continue/Halt');
    B('control-flow-in-finally',       'bug-patterns', 'warning', 'Exit/Break/Continue/Halt inside a finally block');
    B('missing-inherited-ctor',        'bug-patterns', 'warning', 'Constructor without an inherited call');
    B('missing-inherited-dtor',        'bug-patterns', 'warning', 'Destructor without an inherited call');
    B('float-equality-comparison',     'bug-patterns', 'warning', 'Floating-point value compared with =');
    B('length-zero-compare',           'bug-patterns', 'info',    'Length(s) compared to 0 -- use s = '''' / s <> ''''');
    B('string-equality-comparison',    'bug-patterns', 'info',    'String compared with = -- consider SameText/SameStr semantics', False); { OFF by default -- it fires on EVERY string equality, so it is a census rather than a defect check: 406 findings on drag-lint's own source, the largest single rule in the report, and the top sites are AST node-type tag comparisons (NT = 'exprUnary') where case-sensitivity is exactly what is wanted and SameText would be WRONG. It cannot tell "meant case-insensitive, wrote =" from "meant case-sensitive, wrote =", and without that distinction it carries no signal. Kept for a deliberate case-sensitivity audit; opt in via "enabled" }
    B('format-argument-count',         'bug-patterns', 'error',   'Format() argument count does not match the specifiers');
    B('format-specifier-type-mismatch','bug-patterns', 'error',   'Format() specifier type does not match the literal argument');
    B('loop-executes-at-most-once',    'bug-patterns', 'warning', 'Loop body starts with Exit/Break/raise -- runs at most once');
    B('virtual-method-in-constructor', 'bug-patterns', 'warning', 'Virtual/dynamic method called from a constructor');
    B('try-except-swallowed',          'bug-patterns', 'warning', 'try..except swallows the exception (no raise/log)');
    B('criticalsection-not-released',  'bug-patterns', 'error',   'Critical section acquired without a matching Leave/Release/TMonitor.Exit in finally');
    B('ui-access-in-thread',           'bug-patterns', 'warning', 'UI access inside a TThread.Execute (not thread-safe)');
    B('global-form-variable',          'bug-patterns', 'warning', 'Unit-level global variable of the form class type -- potential leak');
    B('unsafe-typecast-without-is',    'bug-patterns', 'warning', 'Hard cast TFoo(x) of an object reference with no guarding ''x is TFoo''', False); { OFF by default -- heuristic; many unguarded casts are provably safe. Opt in via "enabled" }
    B('exception-constructed-but-not-raised', 'bug-patterns', 'warning', 'Exception E...Create(...) constructed as a statement but never raised');
    B('duplicate-exception-handler',   'bug-patterns', 'warning', 'Two ''on <Class>'' handlers for the same class in one try -- the second is unreachable');
    B('repeated-else-if-condition',    'bug-patterns', 'warning', 'The same condition repeats in an if/else-if chain -- the later branch is unreachable');
    B('property-references-itself',    'bug-patterns', 'warning', 'A property''s read/write accessor is the property itself -- infinite recursion');
    B('exhaustive-enum-case',          'bug-patterns', 'warning', 'case on an enum type omits some members and has no else (store-aware; same-file enums covered without a DB)', False); { OFF by default -- a case handling a subset with no else is common; opt in via "enabled" }
    B('lossy-cast',                    'bug-patterns', 'info',    'Ansi-narrowing cast of a Unicode string -- characters outside the code page are lost (W1057)');

    { --- resource-lifetime --- }
    B('freeandnil-on-interface',       'resource-lifetime', 'warning', 'FreeAndNil on an interface reference');
    B('interface-object-mixing',       'resource-lifetime', 'info',    'Object aliased into an interface AND manually freed in the same routine -- dual-handle double-free risk', False); { OFF by default -- first-cut same-routine heuristic; opt in via "enabled" }
    B('unprotected-object-free',       'resource-lifetime', 'warning', 'Object created + freed without try-finally');
    B('use-after-free',                'resource-lifetime', 'warning', 'Object used after X.Free');
    B('destructor-without-override',   'resource-lifetime', 'warning', 'Destructor not declared ''override'' -- hides the inherited destructor (leak)');
    B('create-inside-try',             'resource-lifetime', 'warning', 'Object constructed as the first statement inside its try..finally -- construct before the try');
    B('abstract-method-instantiation', 'resource-lifetime', 'warning', 'TFoo.Create on a class with an unimplemented abstract method -- raises EAbstractError (store-backed)');

    { --- security --- }
    B('unsafe-shellexecute',           'security', 'error',   'A command line built at runtime: WinExec/CreateProcess with a non-literal command, or ShellExecute with runtime parameters, a non-plain verb, or an interpreter as lpFile');
    B('path-traversal',                'security', 'warning', 'Concatenated path passed to a file API -- path traversal risk');
    { Was rules\hardcoded-absolute-path.scm ("any literal starting with a drive letter,
      anywhere") until 2026-08-31; the .scm pair was DELETED, not filtered, so the
      built-in owns this id unconditionally and there is no dual implementation to drift.
      Design: docs\INBOX-b7-path-literal-reverse-taint-plan.md. Severity stays info and
      the id is unchanged so existing dl:ok markers and baselines keep matching.
      NARROWED 2026-09-01 to an ABSOLUTE ROOT (owner ruling); the title below moved
      with it. Rationale lives at IsPathPortion in DRagLint.Diagnostics.AstChecks.
      THIRD TIER added 2026-09-02 (owner ruling 2): a literal reaching NO sink is
      no longer silent, it reports at info for review. See ReportOrphanLiterals. }
    B('hardcoded-absolute-path',       'security', 'info',    'A hardcoded ABSOLUTE root -- a drive letter or a UNC lead. A COMPLETE path reaching a file/directory/ini/dataset-location sink reports at warning; a bare root at info; a literal reaching NO modelled sink at info, for review (a relative path and a bare file name + extension are allowed)');
    B('weak-random-for-security',      'security', 'warning', 'A security-named variable is generated with System.Random (not a CSPRNG)');
    B('dfm-hardcoded-credential',      'security', 'warning', 'A credential-named DFM property (Password/Secret/ApiKey) holds a literal string');
    B('insecure-temp-file',            'security', 'warning', 'File written to a hardcoded temp path (\Temp\, C:\Temp) -- predictable/insecure location');

    { --- platform --- }
    B('win64-pointer-cast',            'platform', 'warning', 'Pointer cast to a 32-bit integer type -- unsafe on Win64');
    B('nativeint-truncation',          'platform', 'warning', 'NativeInt/pointer-sized value cast to a 32-bit integer type -- truncates on Win64');
    B('default-encoding-io',           'platform', 'warning', 'File I/O (LoadFromFile/SaveToFile, TFile.*, TStreamReader/Writer) with no explicit TEncoding -- defaults to ANSI/locale', False); { OFF by default -- FP-sanity over src/ found 65 findings across 16/103 files, mostly TFile.ReadAllText on known-ASCII project/config files (dproj/json); opt in via "enabled": ["default-encoding-io"] }

    { --- complexity (all parameterized) --- }
    B('too-many-parameters',  'complexity', 'info', 'Routine has too many parameters', True, [MkParam('threshold','int','7')]);
    B('too-many-locals',      'complexity', 'info', 'Routine has too many local variables', True, [MkParam('threshold','int','25')]);
    { v(2026-08-10): 120 -> 250. Measured over drag-lint's own 94 files: median
      flagged body is 182 lines, p75 is 300. A threshold BELOW the median of
      what it flags is not selecting outliers, it is describing the codebase. }
    B('method-too-long',      'complexity', 'info', 'Routine body is too long', True, [MkParam('threshold','int',IntToStr(DEFAULT_METHOD_TOO_LONG))]);
    B('deep-nesting',         'complexity', 'info', 'Nesting is too deep', True, [MkParam('threshold','int','5')]);
    B('too-many-exit-points', 'complexity', 'info', 'Routine has too many Exit statements', True, [MkParam('threshold','int','5')]);
    { WARNING, not error, on the requester's own pre-authorisation: they asked for
      error and said to ship as a warning first if a corpus scan made that look
      optimistic. Enabled by DEFAULT because the CLI runs it unconditionally --
      a catalog that said 'off' while the engine fired would be two surfaces
      disagreeing about the same input. }
    B('stat-gated-destructive', 'bug-patterns', 'warning', 'Destructive act gated on a file-existence check (a failed stat answers False)', True, []);
    { v(2026-08-10): THE COMPLEXITY THRESHOLDS WERE FLAGGING THE MEDIAN.
      Measured across drag-lint's own corpus (94 files, 2,499 findings):

        rule                    old  median  p75   p90   max     old count
        cyclomatic-complexity    15      22   30    55    264          180
        cognitive-complexity     25      40   65   124  10572          165

      A cyclomatic threshold of 15 against a median flagged value of 22 does not
      identify outliers -- it reports that this codebase exists, 180 times. The
      new values sit at p75, which reports ~43 and ~41 routines respectively:
      few enough to read, and the genuine monsters are untouched (ParseArgs in
      DRagLint.CLI.pas measures cyclomatic 264 / cognitive 10,572 and fires at
      any threshold anyone would defend).

      These are DEFAULTS, not a verdict on your code: `thresholds` in
      drag-lint-lint.json overrides both per project. A team that wants the
      stricter historical values simply sets them back. }
    B('cyclomatic-complexity','complexity', 'info', 'Cyclomatic complexity is too high', True, [MkParam('threshold','int',IntToStr(DEFAULT_CYCLOMATIC_THRESHOLD))]);
    B('cognitive-complexity', 'complexity', 'info', 'Cognitive complexity is too high (nesting-weighted)', True, [MkParam('threshold','int',IntToStr(DEFAULT_COGNITIVE_THRESHOLD))]);
    B('case-with-too-few-branches','complexity', 'hint', 'case has fewer than N branches -- an if is clearer', True, [MkParam('threshold','int','2')]);
    B('boolean-expression-complexity','complexity', 'info', 'Boolean expression has more than N and/or/xor operators', True, [MkParam('threshold','int','4')]);
    B('duplicate-code',       'complexity', 'info', 'Duplicated code block detected (Type-2, renamed-identifier tolerant)', True, [MkParam('threshold','int','90')]);
    B('unit-too-large',       'complexity', 'info', 'Unit exceeds N source lines', True, [MkParam('threshold','int','2000')]);

    { --- firedac --- }
    B('firedac-open-execsql-mismatch', 'firedac', 'warning', 'Open vs ExecSQL does not match the SQL kind');
    B('dataset-open-without-close',    'firedac', 'warning', 'Dataset opened without a matching Close in finally');
    B('field-by-name-in-loop',         'firedac', 'warning', 'FieldByName called inside a loop -- cache the field');

    { --- dead-code --- }
    B('unused-local',          'dead-code', 'hint',    'Local variable is never used');
    B('unused-parameter',      'dead-code', 'warning', 'Parameter is never used');
    B('identical-then-else',   'dead-code', 'warning', 'then and else branches are identical');
    B('referenced-never-set',  'dead-code', 'warning', 'Private field is read but never assigned');
    B('redundant-parentheses', 'dead-code', 'hint',    'Redundant parentheses around a single term or nested parens');
    { OFF by default -- owner ruling, 2026-08-13: "I often do this and forget to
      clean it, or comment out debug output when I do not need it but might need
      it later." Deliberately-parked code is a normal working habit here, so the
      rule was reporting an intent it cannot distinguish from an accident.
      It also cannot tell code from PROSE ABOUT code: both YADF findings were a
      doc comment showing a before/after example of what the formatter does.
      Opt back in per project with "enabled":["commented-out-code"]. }
    B('commented-out-code',    'dead-code', 'hint',    'Comment appears to be commented-out code (assignment or call)', False);
    B('function-result-ignored','dead-code','hint',    'Result of a same-unit function call is discarded', False); { OFF by default -- FP-prone (builders/adders/runners legitimately discard results); opt in via "enabled" }
    B('redundant-cast',        'dead-code', 'hint',    'Cast of a value to the type it already has (no-op)');

    { --- data-flow --- }
    B('used-before-assignment','data-flow', 'error',   'Variable used before assignment');
    B('function-result-not-set','data-flow','warning', 'Function Result not assigned on every path');
    B('out-param-not-set',     'data-flow', 'warning', 'out parameter not assigned on every path');
    B('overwrite-before-read', 'data-flow', 'warning', 'Value overwritten before it is read');
    B('write-only-local',      'data-flow', 'info',    'Local assigned but never read');
    B('loop-var-after-loop',   'data-flow', 'warning', 'Loop variable used after the loop');
    B('object-leak',           'data-flow', 'info',    'Created object may leak (not freed on every path)');
    B('not-assigned-interface','data-flow', 'warning', 'Interface variable dereferenced before assignment (nil interface call)');
    B('double-free',           'data-flow', 'warning', 'Object freed twice on a path with no reassignment between (double free)');

    { --- naming (all info; two ship disabled) --- }
    B('type-name-prefix',    'naming', 'info', 'Type name must carry the configured prefix', True,
      [MkParam('class_prefix','string','T'), MkParam('exception_prefix','string','E'),
       MkParam('interface_prefix','string','I'), MkParam('pointer_prefix','string','P')]);
    B('field-name-prefix',   'naming', 'info', 'Field name must carry the configured prefix', True,
      [MkParam('field_prefix','string','F')]);
    B('param-name-prefix',   'naming', 'info', 'Parameter name must carry the configured prefix', False,
      [MkParam('param_prefix','string','')]);
    B('method-pascalcase',   'naming', 'info', 'Method/routine name casing', True,
      [MkParam('method_case','string','PascalCase')]);
    B('const-casing',        'naming', 'info', 'Constant name casing', True,
      [MkParam('const_case','stringlist','PascalCase,UPPER_CASE')]);
    { 2026-10-13: two unit/class-level consts or vars that differ only by
      underscores (StationType_Operator / StationTypeOperator). }
    B('confusable-identifier', 'naming', 'warning', 'Two declarations differ only by underscores', True);
    B('local-var-casing',    'naming', 'info', 'Local variable name casing', True,
      [MkParam('local_case','string','PascalCase')]);
    { Split out of local-var-casing (2026-08-10). Casing is high-noise and this
      is high-signal, so they are separately tunable: a local named FName reads
      as an object field and is not one. Shares field_prefix/param_prefix with
      the field/param rules rather than declaring its own, so "what F means"
      has ONE answer across the whole naming family. }
    B('local-field-prefix',  'naming', 'info', 'Local variable wears the field/param prefix', True,
      [MkParam('field_prefix','string','F'),
       MkParam('param_prefix','string','')]);
    B('unit-name-matches-file','naming','info', 'Unit name must equal the file base name');
    B('reserved-word-casing','naming', 'info', 'Reserved words must be lowercase', True,
      [MkParam('keyword_case','string','lowercase')]);
    B('hungarian-or-short-identifier','naming','info','Short or Hungarian-prefixed identifier', False,
      [MkParam('min_identifier_len','int','3'),
       MkParam('hungarian_prefixes','stringlist','lpsz,psz,sz,lp,int,str,dw,b,p,n'),
       MkParam('short_identifier_check','bool','false')]);

    { --- structure --- }
    B('inline-comment-in-multiline-args', 'structure', 'warning', 'Inline comment inside a multi-line argument list');
    B('line-too-long',                    'structure', 'warning', 'Line longer than 1020 characters -- dcc64 compiles it only at some file offsets (F2069)'); { ON by default: owner ruling D3 2026-10-25 }
    B('multiple-statements-per-line',     'structure', 'hint',    'Two or more statements share one source line', False); { OFF by default -- pure style; opt in via "enabled" }

    { --- refactoring (Fowler catalog; v0.79) --- }
    B('magic-literal', 'refactoring', 'hint', 'Unexplained numeric literal -- extract a named constant', False); { OFF by default -- medium-FP, opt in via "enabled" }
    B('boolean-flag-parameter', 'refactoring', 'hint', 'Boolean flag parameter selects behavior -- consider splitting the routine', False); { OFF by default -- see FP-sanity note in DeadCodeChecks.pas }
    B('message-chain', 'refactoring', 'hint', 'Message chain too long -- consider Hide Delegate', True, [MkParam('threshold','int','4')]); { ON by default -- see FP-sanity note in DeadCodeChecks.pas }
    B('public-writable-field', 'refactoring', 'info', 'Public class field -- expose via a property instead', False); { OFF by default -- 44 findings/6 files on src/, mostly intentional field-bag DTOs; opt in via "enabled" }
    B('loop-control-flag', 'refactoring', 'hint', 'Loop exit driven by a boolean flag -- consider Break', False); { OFF by default -- riskiest heuristic of the batch; opt in via "enabled" }
    B('mutable-global-variable', 'refactoring', 'info', 'Mutable global variable -- shared mutable state (Fowler Global Data)', False); { OFF by default -- see FP-sanity note in AstChecks.pas; opt in via "enabled" }
    B('repeated-type-switch', 'refactoring', 'info', 'Same case-selector repeated across 3+ methods -- Replace Conditional with Polymorphism (project-wide)', False); { OFF by default -- medium-FP (message-map dispatches, name-based grouping); opt in via "enabled" }
    B('middle-man', 'refactoring', 'info', 'Class mostly delegates to one field -- Remove Middle Man (inline or expose the delegate)', False); { OFF by default -- facades/interposers/OTA-NTA wrappers are legitimate middle-men; opt in via "enabled" }
    B('feature-envy', 'refactoring', 'info', 'Method accesses another class more than its own -- Move Method closer to the data it uses', False, [MkParam('minAccess','int','3')]); { OFF by default -- target-class resolution is name-based (no type inference), so the own/foreign split is heuristic; opt in via "enabled" }
    B('split-variable', 'refactoring', 'info', 'Local reused for two unrelated purposes (disjoint lifetimes) -- Split Variable into two locals', False); { OFF by default -- M2 two-live-range flow signal (linear routines only); opt in via "enabled" }
    B('separate-query-from-modifier', 'refactoring', 'info', 'Value-returning function also mutates state -- Command-Query Separation violation; split into a pure query and a command', False); { OFF by default -- inherently noisy (lazy getters, fluent mutators); conservative field-write predicate; opt in via "enabled" }

    { --- review markers (dl:ok; 2026-08-12) ---
      Meta-rules ABOUT the suppression mechanism, emitted by the one central
      marker filter rather than by any checker. They ship ON (reason-unreviewed
      excepted, see below): a review marker
      that has quietly stopped describing its code is the exact silent-wrong-
      answer this project keeps paying for, so noticing it is the default. }
    B('review-marker-stale',  'review-markers', 'hint', 'dl:ok marker no longer matches the line it reviews -- the finding is reported again; re-review and re-mark');
    B('review-marker-unused', 'review-markers', 'hint', 'dl:ok marker records a finding that no longer occurs -- remove the marker');
    { The sibling of the rule above, and the more important of the two: `unused`
      catches a marker that has stopped matching, this catches one that NEVER
      matched. A hand-written `dl:ok rule: prose` parses into a rule id that does
      not exist, so it suppressed nothing and was reported by nothing -- the
      source read as reviewed while the linter had never agreed. hint, not
      warning, because the remedy is always a one-line edit. }
    B('review-marker-malformed', 'review-markers', 'hint', 'dl:ok names something that is not a rule id -- the marker suppresses nothing');
    { The third way a marker can suppress nothing while reading as a review: its
      @hash was never computed. `@0000` or a non-hex `@xxxx` on a `//` marker, or
      an all-zero one stranded in a block comment where no marker is ever read
      (INBOX B1: LintTree.pas carried exactly that, and stale/unused were both
      clean over it). ON, because it cannot flood: it needs a known rule id AND a
      hash no hash function produces, and in block comments only the all-zero
      form counts, so prose quoting the grammar stays silent. }
    B('review-marker-placeholder-hash', 'review-markers', 'hint', 'dl:ok carries a placeholder or malformed @hash (e.g. @0000) -- it suppresses nothing; re-record it with `allow`');
    { OWNER RULING OWN-7 (2026-09-23). The @hash covers CODE only, so a reason
      can go false without the marker ever going stale (INBOX B2). The optional
      `REVIEWED <yyyy-mm-dd>` stamp in the reason records when a human last
      re-read it. OFF by default: every marker written before the stamp existed
      would report at once. Opt in per project; max_age_days is the threshold
      key "review-marker-reason-unreviewed" (0 = presence only). }
    B('review-marker-reason-unreviewed', 'review-markers', 'hint', 'dl:ok reason has no REVIEWED <yyyy-mm-dd> stamp, or it is older than max_age_days -- re-read the reason and re-stamp it', False,
      [MkParam('max_age_days', 'int', '180')]);

    { --- project-wide --- }
    B('unit-not-in-dpr',       'project-wide', 'warning', 'Unit is referenced but not listed in the .dpr');
    { T-22 (owner ruling 2026-10-25): the THIRD-PARTY half of "used, but neither
      in the project nor in the library". The own-roots half is unit-not-in-dpr's
      third direction. Fix: `reconcile-project --apply --to library` (or --apply). }
    B('unit-not-in-library',   'project-wide', 'warning', 'Third-party unit the project compiles via its search path is neither a project member nor in the library');
    B('used-unit-not-resolvable', 'project-wide', 'warning', 'Used unit resolves to no known unit (project/library/alias)');
    { Needs a .dproj: without one the build's defines are unknown, so the rule
      runs only when --project names it or the --db's project is known, and a
      bare `lint <file>` reports nothing. ifdef_allow is the drag-lint-lint.json
      top-level key of the same name. OFF by default -- the measurement is at
      BUILTIN_RULES_OFF_BY_DEFAULT above. }
    B('ifdef-undefined-symbol', 'project-wide', 'warning', 'IFDEF/IFNDEF/defined() tests a symbol no build of the project defines -- dead branch, usually a typo', False,
      [MkParam('ifdef_allow', 'stringlist', '')]);
    { Needs a .dproj with Win32 AND Win64 enabled; compares the EFFECTIVE define
      sets per config (DprojEffectiveDefines), and fires only where the code
      tests the symbol. ON by default (owner 2026-10-25): 0 findings on ORM3 and
      DataCopy; the corpus splits (FastMM4 FULLDEBUGMODE, DUNITXDEBUG) sit in
      third-party trees the IFDEF clause or --lint-third-party keeps out.
      platform_divergent_allow is the drag-lint-lint.json top-level key. }
    B('platform-divergent-define', 'project-wide', 'warning', 'A conditional symbol tested by IFDEF/IFNDEF/defined() is defined for one platform (Win32/Win64) of a config and not the other -- the two builds compile different code', True,
      [MkParam('platform_divergent_allow', 'stringlist', '')]);
    { info, not warning -- INTERIM. Measured wrong ~13% of the time in the
      direction of breaking the build or the product (type-helper calls, DFM-
      registered classes, initialization-only units are all invisible to it).
      The emit site in DRagLint.Lint.ProjectRules carries the full reasoning and
      the two conditions for restoring it to warning. }
    B('unused-unit-in-uses',   'project-wide', 'warning', 'Unit in uses is never referenced'); { SEVERITY IS PER FINDING, and this is the higher of the two: warning when the named unit has no initialization section, info when it has one and removal could therefore fail at runtime after a clean build. The catalogue advertises the ceiling, since it describes a rule, not a finding. Measured: 1,899 of library-Win64's 5,671 units have an initialization section, so neither value is right for every finding }
    B('god-class',             'project-wide', 'info',    'Class has too many members/responsibilities');
    B('unused-public-symbol',  'project-wide', 'info',    'Public symbol is never referenced');
    B('unused-private-member', 'project-wide', 'warning', 'Private member is never referenced');
    B('layering-violation',    'project-wide', 'warning', 'Unit dependency crosses an architectural layer');
    B('interface-reference-cycle','project-wide','warning','Interface reference cycle (ARC leak)');
    B('circular-uses',         'project-wide', 'warning', 'Circular unit dependency (a uses-graph cycle among project units)');
    B('cycle-participant-unit', 'project-wide', 'info', 'This unit is one of the units of a circular unit dependency -- the per-unit view of circular-uses, pointing at `cycles --plan`', False); { NR-C1, 2026-09-28. OFF by default until its corpus count is audited; OptedIn-gated in TProjectLintRules.Run. circular-uses anchors ONE finding per cycle at its alphabetically-first unit, so a per-file lint of any other member said nothing -- this is the view an editor needs for the open file. A projection of the same Tarjan pass (CollectCircularUsesDetailed), so the two can never disagree }
    B('global-only-uses-edge', 'project-wide', 'info',    'A global variable is the ONLY link from one unit to another -- relocating it (or injecting it, when it is interface-typed) deletes the uses edge', True); { ON by default since 2026-08-30 on the owner's ruling: the house standard is every rule ON unless it would flood, and this one does not -- measured 8 / 21 / 0 findings on ORM3 client / server / this repo. Still gated on OptedIn in TProjectLintRules.Run, because it is a full refs scan (0.92 s on a 144 MB index) and post-hoc filtering would hide that cost; the gate now defaults to KEEPING it. }
    B('with-hides-outer-symbol', 'bug-patterns', 'warning', 'A bare name inside a with body binds to the with-target while an outer scope declares the same name -- the compiler never warns'); { ON by default on the owner's explicit ruling 2026-08-30 ("Even 1 out of 100 might be really useful. I did spend a lot of time few months ago exactly because of such an error"), which WITHDREW the plan's 300-finding volume gate. The PRECISION gate stayed: the rule is silent whenever the with-target type, the member surface or the outer declaration cannot be proven, and TObject members are excluded on both sides }
    B('enum-read-inside-with', 'bug-patterns', 'warning', 'A bare name inside a with body names an enum value AND a member of the with-target -- the compiler binds the member, drag-lint''s index records the enum value'); { ON by default (2026-09-23, INBOX-lint-rules-from-new-facts section 1).
      SINCE RESOLVER 1.8.0 the index models with scope and binds such a read to the member whenever it can type the with-target, so this rule reports only the RESIDUAL: a with-target the resolver cannot type (a library class, an ambiguous type name) but this rule can, through its by-name surfaces over the project AND library indexes. It cannot flood: it needs BOTH a same-named member on a with-target AND the index's own binding of that exact identifier to an enum_value -- the bare "enum read inside a with-bearing routine" population (178 sites on ORM3 CLIENT) is silent by construction, and so are scoped-enum and library enum values the index never bound. Every finding is a real name collision the compiler resolves silently. Emitted by TAstChecker.CheckWithHiding, sharing its with-target surfaces. }
    B('enum-bare-read-scoped', 'bug-patterns', 'warning', 'A bare name spelled like a value of a visible $SCOPEDENUMS ON enum -- warning when it binds to another symbol of that name and the types say the enum may be meant (that symbol, or the site target, is of the enum type), hint when it stays unbound and nothing else carries the name (E2003); write TEnum.Value');
       { ON by default. X4 2026-10-25; RETARGETED 2026-10-26 (owner ruling, lane XT-SCOPED) after E14 made
         the resolver decline the bare scoped read, which left the old target (an index binding to the scoped
         value) with no input. Visible = the enum is declared in the same file or in a unit the file uses; a
         const aliasing the value (X = TEnum.X, the Vcl.Dialogs idiom) is not a finding. Warning = type match
         (owner ruling 2026-10-26): the bound symbol is of the enum type, or the site target is (LHS of :=,
         other operand of = <> in); an untypable target is skipped, no guessing. An unbound name another
         symbol carries is skipped (the resolver declined for its own reason, e.g. an untypable with).
         Library slice 2026-10-26 (12 VCL/FMX units): 941 findings untyped, 0 type-matched (571 of 613 bound
         sites untypable). Reads the extractor fact symbols.directives = 'scopedenums' on the enum type
         -- silent on an index parsed before that fact existed. Emitted by
         TAstChecker.CheckEnumBareReadScoped. }
    B('dependent-project-not-recompiled', 'project-wide', 'warning', 'A dl:shared unit was changed after another project that also compiles it last built -- that project still holds object code for the older text', True); { OFF by default until R3 audits the volume. TWO DELIBERATE DIVERGENCES FROM docs\INDEX-SCHEMA.md:174, both to be KEPT and neither to be "fixed" to match the doc: (1) staleness compares against the CURRENT DISK mtime, not the stored mtime_unix, because the stored one is only as fresh as the last index and would call a just-edited file current; (2) a NULL last_compiled_unix is SILENT, not stale -- NULL means never compiled through refresh-findings, which is every file in a fresh checkout, and reporting them all would flood a new clone with findings about work nobody has done yet }
    B('dfm-property-not-declared', 'project-wide', 'warning', 'A .dfm sets a property that the component''s class and its ancestors do not declare -- the form fails to load or silently drops the setting', True); { OFF by default until R3 audits the volume on ORM3 CLIENT. THREE gates keep it off correct code and each one matters more than the positive case: a full ancestor walk (most .dfm properties are inherited), SILENCE when any ancestor is unresolvable (an unknown chain is where the property probably is -- treating it as absent reports the whole VCL), and SILENCE on an ambiguous class name. Collection item rows need no gate: the extractor emits the whole <item ... end> value as ONE dfm-prop row, so the inner names never arrive as property names }
    B('duplicate-global-decl', 'project-wide', 'warning', 'The same name is declared at interface unit level in two or more units -- const, var, type, record, class, interface, enum or routine -- so which one compiles depends on uses order; or a project global that ALSO exists in a library unit the declaring file uses (masking an RTL name -- almost always a naming error; no autofix, a refactoring tool knows which one you meant)'); { ON by default and NOT OptedIn-gated, unlike its sibling above: symbols-only, no refs join, measured 0.05 s on a 144 MB index, 11 findings on ORM3 and 0 on this repo. Owner's own named mistake class }
    B('uses-global-census', 'project-wide', 'info', 'How many of a used unit''s globals and consts this unit actually draws, against how many that unit declares -- acknowledge a travels-together pair with // dl:unit <unit> accepted', True); { ON by default since 2026-08-30 on the owner's ruling (see global-only-uses-edge above). A census rather than a defect report, but a small one -- and `// dl:census-ok <unit>` is the acknowledgement path for a pair that legitimately travels together. Still gated on OptedIn in TProjectLintRules.Run for its cost (1.26 s full refs scan); the gate now defaults to KEEPING it. }
    B('enum-helper-separate-units', 'project-wide', 'warning', 'Enum helper (record/class helper) is declared in a different unit than its target enum -- consider co-locating'); { ON by default (explicit user decision, enum-helper-generator milestone 2026-07-07) -- diverges from the recent OFF-by-default convention for advisory rules; whole-DB helper edge (type_helpers, v15) via ISymbolStore.FindHelpersOfTypeSymbol (symbol-identity match, Task 9b), no heritage string-parsing }
    B('enum-ordinal-persisted', 'project-wide', 'warning', 'An enum whose ordinal crosses a stream / pipe / dataset / registry boundary (an ordinal cast TEnum(x) or Ord(v) in a routine that also calls a sink from rules\enum-persist-sinks.txt) has values with implicit ordinals -- inserting or reordering a value silently changes stored data; pin each value (= N)'); { ON by default (owner ruling 2026-10-25, lane X6): 3 findings on ORM3, 0 on DataCopy; fully pinned enums never fire }
    { --- lane B-ENUM (INBOX-lint-rules-from-new-facts-2026-09-23 rules 2 + 3) --- }
    B('enum-ordinal-cast', 'bug-patterns', 'warning', 'A hard-coded enum ordinal -- a literal cast to an enum type TEnum(5), an enum''s ordinal compared with a literal (Ord(X) = 3), or case Ord(X) of with literal labels; inserting or reordering a value silently changes the meaning. Ord() against Ord(), a negative sentinel TEnum(-1) and an enum whose values are all pinned (= N) are exempt; one dl:ok on the enum TYPE line reviews every cast of it'); { ON by default (B-ENUM 2026-10-28): 11 findings, 11/11 true positives -- 10 on ORM3 CLIENT (TContrMode(0..4) in uPLANLIST), 1 on the engine tree (TSQueryError(0)); pinned TCommandID (Ord(ACmd) >= 200) and TDocCommentKind(-1) sentinels exempt by design }
    B('unused-enum-value', 'project-wide', 'hint', 'An enum value nothing in the project names, in an enum type with no implicit use (Low/High, Succ/Pred, casts, Ord, RTTI, a streamed property) -- one finding per value, the decision per type. A filler value named for its own ordinal (Dummy0 at 0) is exempt; one dl:ok on the TYPE line reviews every value'); { ON by default (ENUMRULES 2026-10-28, owner): B-ENUM measured 0 on ORM3 CLIENT and the engine tree (every candidate type has a real implicit use); filler padding and type-level dl:ok keep the owner's DB-ordinal enums silent }

    { --- purity v2 (spec 2026-09-15 section 14) --- BOTH OFF BY DEFAULT until
      the corpus counts are audited. They read the `purity` resolve stage's
      STORED verdict (symbol_facts.effect_free / effect_summary), so they say
      nothing at all on an index built before that stage existed -- silence
      there is "not computed", never "nothing to report". Opt in via --enable
      or "enabled":["<id>"]; the CLI's OptIn array is what actually makes the
      scan run (see DoLintAll/DoLintProject), so a catalogue flag alone would
      leave them unreachable rather than merely off.
      discarded-effect-free-result is ON since 1.20.1 (owner ruling DEC-7,
      2026-09-28): 3/3 real on ORM3 (TAttrPlan.Describe). Known caveat: it does
      not consider virtual overrides, so a call dispatched to an override with
      effects can still be reported. Guard:
      tests\lint-project\purity-rules\run_purity_rules.ps1 run 1. }
    B('discarded-effect-free-result', 'project-wide', 'info', 'A proven effect-free value-returning routine is called in statement position and its result discarded -- the call does nothing', True);
    B('query-name-with-effect',       'project-wide', 'info', 'A Get*/Is*/Has*/Find*/Can*/Should* routine has a PROVEN escaping effect (writes a field, global state or frees storage) -- a question that also changes something', False);
    { assert-with-side-effect (INBOX 2026-09-23 rule 4) ships OFF for the same
      reason as the two above: it reads the STORED purity verdict and the resolved
      call edges, so on an index without the purity stage it is silent rather
      than clean, and its corpus count has not been audited yet. 'warning', not
      'info': a Debug-only effect is a real behavioural difference between the
      two builds, not a style point. }
    B('assert-with-side-effect',      'project-wide', 'warning', 'A routine with a PROVEN effect (writes a field, a global, a parameter or frees storage) is called inside Assert -- release builds compile Assert out, so the effect happens in Debug only', False);
    { --- lane B-EFFECT (1.37.0): three more readers of the stored purity / ui_affinity facts,
      all OFF and OptedIn-gated like assert-with-side-effect (10-sample gates in the lane REPORT). }
    B('side-effect-in-short-circuit',  'project-wide', 'info', 'A routine with a PROVEN effect is called in the right operand of a Boolean and/or -- short-circuit evaluation skips it whenever the left operand decides the result', False);
    B('property-getter-with-effect',   'project-wide', 'info', 'A property''s read accessor is a method with a PROVEN self-field or global write (lazy initialisers and memos exempt) -- reading a property should not change state', False);
    B('ui-access-in-thread-transitive', 'project-wide', 'warning', 'A TThread.Execute reaches, through resolved calls not marshalled by Synchronize/Queue, a routine that touches the UI -- the call path is printed', False);

    { --- documentation (ADF milestone) --- }
    B('missing-doc', 'documentation', 'warning', 'Public declaration has no DocInsight doc-comment', False); // OFF by default -- fires 1302x on drag-lint's own first-run wave; opt in via "enabled"
    B('doc-drift',   'documentation', 'warning', 'DocInsight comment has drifted from the code it documents (--fix repairs the mechanically-safe subset)');
    { The gate doc-drift STRUCTURALLY cannot be. doc-drift walks symbols; an
      orphan block belongs to no symbol, so a stacked block is invisible to it
      and to every convergence check built on it -- measured 2026-08-14, pass B
      green on three YADF projects over source that already carried one. This is
      a FILE-level scan (DRagLint.Diagnostics.DeadCodeChecks) for exactly that
      reason. See docs\INBOX-autodoc-not-idempotent-on-yadf.md. }
    B('doc-orphan-block', 'documentation', 'warning', 'Managed facts block is attached to no declaration -- a previous --apply stacked it above an existing block');
    { USER RULING 2026-08-09. Split out of doc-drift so the severity can be
      ERROR: the rest of doc-drift reports documentation that is INCOMPLETE,
      while a <param> naming a parameter the signature does not have is
      documentation that is FALSE -- follow it and the call does not compile.
      One rule id cannot carry two severities without the catalogue lying, which
      is why this is its own entry rather than a special case inside doc-drift. }
    B('doc-param-not-in-signature', 'documentation', 'error', 'A <param> tag names a parameter the routine does not declare');
    { ON by default. Severity RAISED from hint to WARNING by user ruling
      2026-08-09 ("If method has params and they are not documented it should be
      reported as warning"), superseding the hint chosen on 2026-08-07. The
      volume note from that first ruling still applies and is now warning-loud:
      inline param comments are rare, so this is roughly one finding per
      undocumented parameter across a codebase (30 on the YADF corpus). That
      volume was measured and put to the user before the raise. Report-only --
      there is nothing a fix could write, since the whole point is that the
      meaning is not in the code (ruling D-3). }
    B('doc-param-no-description', 'documentation', 'warning', 'A <param> tag is present but has no description -- the parameter''s meaning is still undocumented'); { ON by default; NOT fixable (lane A5B, 2026-10-27): the finding asks for prose only a human can write -- a stub description would still read as empty to the rule. doc-drift's --fix refreshes the facts block of the same decl }

    { --- metrics (CK class metrics; v0.78) --- }
    B('too-many-children', 'metrics', 'info', 'Class has too many direct subclasses (NOC)', True, [MkParam('threshold','int','10')]);
    B('deep-inheritance', 'metrics', 'info', 'Class inheritance is too deep (DIT)', True, [MkParam('threshold','int','6')]);
    B('high-response', 'metrics', 'info', 'Class response set is too large (RFC)', True, [MkParam('threshold','int','50')]);
    B('high-coupling', 'metrics', 'info', 'Class is coupled to too many other classes (CBO)', True, [MkParam('threshold','int','20')]);
    B('low-cohesion', 'metrics', 'info', 'Class methods lack cohesion (LCOM4)', True, [MkParam('threshold','int','26')]);
    { v0.81 coupling metrics -- OFF by default. fan-out aliases high-coupling/CBO
      (so it does not double-fire); fan-in is a whole-project reverse aggregation.
      Both need field-tuned thresholds; opt in via "enabled". }
    B('fan-out', 'metrics', 'info', 'Class depends on too many other classes (efferent coupling Ce; aliases CBO)', False, [MkParam('threshold','int','20')]);
    B('fan-in', 'metrics', 'info', 'Class is referenced by too many other classes (afferent coupling Ca)', False, [MkParam('threshold','int','20')]);
    B('instability', 'metrics', 'info', 'Class instability (I=Ce/(Ca+Ce)) is high -- unstable: depends on many, nothing depends on it', False, [MkParam('threshold','int','80'), MkParam('instability-floor','int','5')]);

    { --- clippy-parity wave (2026-10-27): ids registered up front by lane L0; the
      checker for each lives in its own src\diagnostics unit (stub until its lane
      lands). Titles say WHAT and WHY in one sentence. --- }
    B('loop-condition-invariant', 'bug-patterns', 'warning', 'Loop condition never changes inside the body -- the loop cannot end or never runs again');
    B('for-bound-modified-in-body', 'bug-patterns', 'warning', 'For-loop bound or counter variable is modified in the body -- Delphi evaluates the bound once, so the change has no effect');
    B('infinite-loop-no-exit', 'bug-patterns', 'warning', 'Loop with a constant-true condition has no Exit/Break/raise -- it can never terminate');
    B('redundant-continue-exit', 'dead-code', 'hint', 'Continue or Exit as the last statement of a loop or routine does nothing -- remove it');
    B('else-after-exit', 'refactoring', 'hint', 'else after a branch that ends in Exit/raise/Continue/Break -- drop the else to cut nesting', False);
    B('unconditional-recursion', 'bug-patterns', 'warning', 'Routine calls itself on every path -- it recurses until the stack overflows');
    B('bad-bit-mask', 'bug-patterns', 'warning', 'Bit-mask test that is always true or always false (e.g. X and 0 or X or -1 compared) -- the mask is wrong');
    B('invalid-regex-literal', 'bug-patterns', 'warning', 'Regular-expression literal does not compile -- the call will raise at run time');
    B('double-dictionary-lookup', 'refactoring', 'info', 'ContainsKey followed by an indexed read looks the key up twice -- use TryGetValue');
    B('case-same-branches', 'dead-code', 'info', 'Case branches have identical bodies -- merge the labels or the branches are a copy-paste error');
    B('misleading-indentation', 'bug-patterns', 'warning', 'Statement is indented as if it were controlled by the preceding if/while/for but is not -- likely a missing begin/end');
    B('missing-const-param', 'refactoring', 'hint', 'Parameter is never modified, assigned or passed as var -- declare it const to avoid a copy or refcount', False);
    B('local-shadows-field', 'structure', 'info', 'Local variable or parameter has the same name as a field of the class -- it hides the field and invites mistakes', False);
    B('method-could-be-static', 'refactoring', 'hint', 'Method never uses Self or any instance member -- make it a class function or a free routine', False);
    B('large-stack-local', 'complexity', 'info', 'Local variable is very large -- it can overflow the thread stack; allocate it on the heap', True, [MkParam('threshold','int','65536')]);
    B('too-many-bool-fields', 'refactoring', 'info', 'Class has many Boolean fields -- they are probably a state machine or a set of flags in disguise', False, [MkParam('threshold','int','5')]);
    B('inline-on-large-routine', 'complexity', 'hint', 'inline on a long or try-containing routine -- the compiler will not inline it or code bloat outweighs the gain', True, [MkParam('threshold','int','20')]);
    B('wait-while-holding-lock', 'bug-patterns', 'warning', 'Blocking call (Synchronize, WaitFor, Sleep, SendMessage, dialog) while a lock is held -- risk of deadlock');
    B('disallowed-method', 'policy', 'warning', 'Call to a method the project configuration disallows -- see the configured reason');
    B('disallowed-type', 'policy', 'warning', 'Use of a type the project configuration disallows -- see the configured reason');
    B('disallowed-name', 'policy', 'warning', 'Use of an identifier the project configuration disallows -- see the configured reason');
    B('index-loop-to-for-in', 'modernize', 'hint', 'Index loop only reads Items[I] -- a for..in loop is shorter and cannot go out of range', False);
    B('duplicate-unit-on-search-path', 'structure', 'warning', 'Two files with the same unit name are on the search path -- the compiler may pick the wrong one');
    { gap-rules wave (G0): the 22 built-in ids of lanes G4-G8 }
    B('field-created-not-freed', 'resource-lifetime', 'warning', 'Field created in a constructor is never freed by any method of the class -- the object leaks when the owner is destroyed');
    B('free-of-owned-item', 'resource-lifetime', 'warning', 'Item freed by hand although its OwnsObjects container frees it too -- double free');
    B('mismatched-alloc-free', 'resource-lifetime', 'warning', 'Memory released by a call from a different family than the one that allocated it (GetMem/Dispose, New/FreeMem, ...) -- heap corruption');
    B('freeonterminate-then-wait', 'resource-lifetime', 'warning', 'WaitFor or Free on a thread that has FreeOnTerminate set -- the thread may already be gone');
    B('begin-end-pair-not-in-finally', 'bug-patterns', 'warning', 'BeginUpdate/EndUpdate style pair whose closing call is missing or not in a finally -- an exception leaves the resource held');
    B('nil-check-after-dereference', 'bug-patterns', 'warning', 'Reference is dereferenced and only afterwards tested against nil -- either the use is too early or the check is redundant');
    B('address-of-local-returned', 'bug-patterns', 'warning', 'Address of a local variable or by-value parameter is returned -- it dangles once the routine exits');
    B('constant-index-out-of-range', 'bug-patterns', 'warning', 'Literal index outside the declared array bounds (or S[0] on a 1-based string) -- range error or memory overrun');
    B('copy-paste-assignment', 'bug-patterns', 'hint', 'Run of similar assignments where one right-hand side repeats another -- likely a copy-paste typo', False);
    B('exception-escapes-thread', 'bug-patterns', 'warning', 'Thread body has no top-level try..except -- an unhandled exception silently ends the thread');
    B('raise-in-destructor', 'bug-patterns', 'warning', 'raise inside a destructor -- an exception during cleanup aborts the rest of the teardown and leaks');
    B('network-client-without-timeout', 'security', 'warning', 'Network client created without any timeout set -- a stalled peer blocks the caller indefinitely');
    B('closure-captures-loop-local', 'bug-patterns', 'warning', 'Anonymous method captures a local assigned inside the loop and runs later -- every closure sees the last value');
    B('hides-ancestor-virtual', 'bug-patterns', 'warning', 'Method has the same name as an ancestor virtual method but is neither override nor reintroduce -- the ancestor method is hidden');
    B('needless-exit', 'dead-code', 'hint', 'Exit as the last statement of a routine does nothing -- remove it');
    B('free-of-parameter', 'resource-lifetime', 'warning', 'Free of a by-value or const parameter -- the caller''s reference now dangles');
    B('property-accessor-name', 'naming', 'info', 'Property accessor is not named F<Prop> / Get<Prop> / Set<Prop> -- the convention makes accessors findable');
    B('unused-loop-variable', 'dead-code', 'hint', 'for-loop counter is never used in the body -- the loop only repeats; check the intent', False);
    B('dfm-event-handler-missing', 'project-wide', 'warning', 'A .dfm names an event handler that the form class and its ancestors do not declare -- the form fails to load');
    B('dfm-password-edit-unmasked', 'security', 'info', 'Edit control named like a password field has no PasswordChar -- the secret is shown on screen');
    B('uses-movable-to-implementation', 'project-wide', 'hint', 'Interface uses entry is needed only by the implementation section -- move it to cut coupling and compile time');
    B('virtual-never-overridden', 'project-wide', 'hint', 'Virtual method with no override anywhere in the project -- the virtual dispatch buys nothing', False);
    { taint wave T2: store-backed interprocedural taint (DRagLint.Lint.TaintRules; catalogues rules\taint-*.json) }
    B('taint-sql-injection', 'security', 'error', 'Tainted data reaches an SQL text sink -- a catalogued source (command line, edit control, request) flows across routines into ExecSQL / SQL.Text (CWE-89)');
    B('taint-command-injection', 'security', 'error', 'Tainted data reaches a process launch sink -- a catalogued source flows across routines into ShellExecute / CreateProcess / WinExec (CWE-78)');
    B('taint-path-traversal', 'security', 'warning', 'Tainted data reaches a file-system path sink -- a catalogued source flows across routines into a file / directory API (CWE-22)');
    { lane INC3: the preprocessor's IF symbol table (DRagLint.Diagnostics.PpChecks) }
    B('pp-unresolved-if', 'bug-patterns', 'hint', '$IF names a constant the index cannot resolve -- the directive was taken as False, so the wrong branch (and include) may be indexed');
    Result:= L.ToArray;
  finally
    L.Free;
  end;
end;

class function TRuleCatalog.ScmCategory(const AId: string): string;
begin
  if MatchStr(AId, ['empty-except','empty-on-handler','empty-finally','bare-except',
    'raise-bare-exception','reraise-loses-stack','nil-comparison','not-in-precedence',
    'not-comparison-precedence','self-assignment','comparison-same-operands',
    'classname-string-compare','empty-conditional','empty-loop-body','constant-condition',
    'ifthen-both-branches','uppercase-compare','uppercase-compare-always-false',
    'off-by-one-count','division-by-zero-literal',
    'empty-procedure-body','empty-case-branch','large-magic-number','case-magic-numbers',
    'sleep-in-vcl','parser-error']) then
    Result:= 'bug-patterns'
  else if MatchStr(AId, ['redundant-assigned-free']) then
    Result:= 'resource-lifetime'
  else if MatchStr(AId, ['hardcoded-credential','hardcoded-connection-string','sql-injection-concat',
    'hardcoded-absolute-path','hardcoded-ip-address']) then
    Result:= 'security'
  else if MatchStr(AId, ['inline-assembly','sizeof-pointer-assumption','pchar-arithmetic',
    'unsafe-string-api','locale-sensitive-conversion','gettickcount-wraparound','deprecated-rtl-function']) then
    Result:= 'platform'
  else if MatchStr(AId, ['public-field','goto-statement','with-statement','nested-with','with-multiple-items']) then
    Result:= 'structure'
  else if MatchStr(AId, ['redundant-as-tobject','redundant-not-not','boolean-result-returned-directly',
    'boolean-comparison-true']) then
    Result:= 'dead-code'
  else
    Result:= 'other';  { writeln-in-source, outputdebugstring, compiler-magic-comments, assert-call, inherited-bare, concat-in-loop }
end;

class function TRuleCatalog.BuildCatalog(const ARulesDir, ACategory: string; AWithLabels: Boolean): TArray<TRuleInfo>;
var
  Dir   : string;
  ById  : TDictionary<string, TRuleInfo>;
  Order : TList<string>;
  R     : TRuleInfo;
  F     : string;
  Files : TArray<string>;
  Raw   : string;
  Root  : TJSONValue;
  Obj   : TJSONObject;
  Sc    : TRuleInfo;
  Res   : TList<TRuleInfo>;
  Id    : string;
  Labels: TComplianceTable;
begin
  if ARulesDir <> '' then Dir:= ARulesDir
  else Dir:= TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), 'rules');
  Labels:= nil;
  if AWithLabels then Labels:= TComplianceTable.Shared(ARulesDir, ComplianceError);

  ById:= TDictionary<string, TRuleInfo>.Create;
  Order:= TList<string>.Create;
  try
    { built-ins first (they win dedup) }
    for R in BuiltinRegistry do
      if not ById.ContainsKey(R.Id) then begin ById.Add(R.Id, R); Order.Add(R.Id); end;

    { external .scm sidecars }
    if TDirectory.Exists(Dir) then
    begin
      Files:= TDirectory.GetFiles(Dir, '*.json', TSearchOption.soAllDirectories);
      for F in Files do
      begin
        if SameText(TPath.GetFileName(F), 'compliance.json') then Continue; { label data, not a rule sidecar }
        Raw:= '';
        try Raw:= TFile.ReadAllText(F, TEncoding.UTF8); except Continue; end;
        Root:= TJSONObject.ParseJSONValue(Raw);
        if not (Root is TJSONObject) then begin Root.Free; Continue; end;
        try
          Obj:= Root as TJSONObject;
          if Obj.GetValue('id') = nil then Continue;
          Id:= Obj.GetValue('id').Value;
          if (Id = '') or ById.ContainsKey(Id) then Continue; { builtin/dup wins }
          Sc.Id:= Id;
          Sc.Source:= 'scm';
          if (Obj.GetValue('category') <> nil) and (Obj.GetValue('category').Value <> '') then
            Sc.Category:= Obj.GetValue('category').Value  { optional sidecar key; lets a rule file name its own category (e.g. modernize, policy) }
          else Sc.Category:= ScmCategory(Id);
          if Obj.GetValue('severity') <> nil then Sc.DefaultSeverity:= Obj.GetValue('severity').Value
          else Sc.DefaultSeverity:= 'warning';
          if Obj.GetValue('message') <> nil then Sc.Title:= Obj.GetValue('message').Value
          else Sc.Title:= Id;
          if (Obj.GetValue('enabled') <> nil) then
            Sc.DefaultEnabled:= not SameText(Obj.GetValue('enabled').Value, 'false')
          else Sc.DefaultEnabled:= True;
          { An .scm sidecar that forgets "enabled": false is still OFF if the
            engine's shared list says so. nil-comparison is exactly that case:
            its JSON says nothing, so `rules --json` advertised
            default_enabled=true for a rule every lint verb hides -- and the
            plugin's Options page, which ticks its checkboxes from this field,
            showed it ON. The catalogue is what a user reads to find out what
            runs; it does not get to disagree with what runs. }
          if MatchStr(Id, BUILTIN_RULES_OFF_BY_DEFAULT) then Sc.DefaultEnabled:= False;
          { autofix wave A0: a "fix" key makes the rule fixable -- registered so
            IsFixableRule (DRagLint.Lint.Autofix) answers for it }
          Sc.HasSidecarFix:= Obj.GetValue('fix') <> nil;
          if Sc.HasSidecarFix then RegisterSidecarFixRule(Id, SidecarFixIsRisky(Obj.GetValue('fix')));
          Sc.Params:= nil;
          ById.Add(Id, Sc); Order.Add(Id);
        finally
          Root.Free;
        end;
      end;
    end;

    { emit in (category, id) order; optional single-category filter }
    Res:= TList<TRuleInfo>.Create;
    try
      for Id in Order do
      begin
        R:= ById[Id];
        if Labels <> nil then Labels.TryGet(R.Id, R.Compliance);
        if (ACategory = '') or SameText(R.Category, ACategory) then Res.Add(R);
      end;
      Res.Sort(TComparer<TRuleInfo>.Construct(
        function(const A, B: TRuleInfo): Integer
        begin
          Result:= CompareText(A.Category, B.Category);
          if Result = 0 then Result:= CompareText(A.Id, B.Id);
        end));
      Result:= Res.ToArray;
    finally
      Res.Free;
    end;
  finally
    Order.Free;
    ById.Free;
  end;
end;

class function TRuleCatalog.Summarize(const ACatalog: TArray<TRuleInfo>): TCatalogSummary;
var
  Counts: TDictionary<string, Integer>;
  Order : TList<string>;
  R     : TRuleInfo;
  C     : string;
  N     : Integer;
begin
  Counts:= TDictionary<string, Integer>.Create;
  Order:= TList<string>.Create;
  try
    Result.Total:= Length(ACatalog);
    Result.PerCategory:= nil;
    for R in ACatalog do
    begin
      if Counts.TryGetValue(R.Category, N) then Counts[R.Category]:= N + 1
      else begin Counts.Add(R.Category, 1); Order.Add(R.Category); end;
    end;
    Result.Categories:= Order.Count;
    for C in Order do
      Result.PerCategory:= Result.PerCategory + [TPair<string, Integer>.Create(C, Counts[C])];
  finally
    Order.Free;
    Counts.Free;
  end;
end;

initialization
  GSidecarFixes:= TDictionary<string, Boolean>.Create(TIStringComparer.Ordinal);

finalization
  GSidecarFixes.Free;

end.
