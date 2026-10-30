unit DRagLint.Lint.QueryRules;

interface

uses
  System.SysUtils
  , System.Classes
  , System.IOUtils
  , System.JSON
  , System.Generics.Collections
  , System.RegularExpressions
  , TreeSitter
  , TreeSitterLib
  , TreeSitter.Query
  , DRagLint.Core.Model
  ;

type
  /// <summary>One entry of a rule sidecar's "fix" key (autofix wave A0,
  /// 2026-10-27): what the autofix does with the finding's span.</summary>
  /// <remarks>Grammar (rules\&lt;id&gt;.json): "fix" is ONE object or an ARRAY of
  /// objects; each is { "when_capture": "&lt;name&gt;" (optional), then exactly one
  /// of "replace": "&lt;template&gt;" | "delete": "span" | "statement", plus
  /// optional "uses": "&lt;Unit&gt;" and "risky": true }. The FIRST entry whose
  /// when_capture is bound in the match (or that has none) and whose template
  /// expands completely wins; no winner = the finding carries no fix. Templates
  /// substitute {capture} with the capture's RAW source text (not
  /// regex-escaped, unlike exclude_if_preceded_by) and may span lines ("\n").
  /// An object with neither replace nor a known delete value is ignored.</remarks>
  TSidecarFix = record
    WhenCapture: string      ;  { '' = always; else applies only when this capture is bound }
    Kind       : TLintFixKind;  { lfkReplace / lfkDeleteSpan / lfkDeleteStatement }
    Template   : string      ;  { lfkReplace only }
    UsesUnit   : string      ;  { '' = none }
    Risky      : Boolean     ;  { behaviour-changing fix: tagged risky, still applied }
    NeedsCompiler: Integer   ;  { 1.38 "needs_compiler": a match that binds this entry is dropped under an older --target-compiler; 0 = any }
  end;

  // A loaded external lint rule expressed as a tree-sitter S-expression query.
  // Sister .json file (same basename) supplies metadata: id, severity, message.
  /// <summary><!-- drag-lint:auto sum -->A loaded external lint rule expressed as a
  /// tree-sitter S-expression query. Sister .json file (same basename) supplies metadata:
  /// id, severity, message.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Lint.Linter.pas), declaration (DRagLint.Lint.QueryRules.pas), DRagLint.Lint.Linter.TLinter.CheckFileImpl (DRagLint.Lint.Linter.pas), DRagLint.Lint.Linter.TLinter.DefaultDisabledRuleIds (DRagLint.Lint.Linter.pas), DRagLint.Lint.Linter.TLinter.Destroy (DRagLint.Lint.Linter.pas) (+1 more)</para>
  /// <para>Used in units: DRagLint.Lint.Linter, DRagLint.Lint.QueryRules</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TQueryRule = class
    strict private
      FQuery          : TTSQuery       ;
      FId             : string         ;
      FSeverity       : string         ;
      FMessage        : string         ;
      FSourcePath     : string         ;
      FWarnCapture    : string         ;
      FEnabled        : Boolean        ;
      FRuleId         : string         ;
      { A literal that MUST appear in a file's text for this query to have any
        chance of matching, or '' when none could be proven. See RequiredText. }
      FRequiredText   : string         ;
      FExcludeAncestors: TArray<string>;
      { The MIRROR of FExcludeAncestors: node kinds at least one of which must be
        an ancestor for the match to count at all. Empty = no requirement, which
        is every existing rule, so this changes nothing that does not ask for it.

        Added for concat-in-loop, whose id, comment and message all say "in a
        loop" while its query matched `S := S + X` ANYWHERE -- 328 findings on
        drag-lint's own source, most of them single-shot concatenations that are
        not quadratic in anything. A rule that cannot express its own
        precondition cannot be calibrated; this is that precondition. }
      FRequireAncestors: TArray<string>;
      { Lowercased substrings, ANY of which must occur in the FILE TEXT for
        this rule to run at all. Empty = no requirement (every existing rule).

        This is SCOPE, not the optimisation FRequiredText is. sleep-in-vcl is
        the case that forced it: its query matches any `Sleep(` call anywhere,
        while its id and its whole message are about freezing a VCL UI. A
        headless console or test unit has no UI to freeze, so the finding was
        never true there -- DataCopy carried 11 of them in one DUnitX unit
        whose uses clause names no VCL unit at all.

        A rule that cannot express its own precondition cannot be calibrated,
        which is the same reasoning that added require_ancestor. }
      FRequireFileText: TArray<string>;
      { Callee names whose ARGUMENTS this rule must not fire on. Empty = no
        exemption (every pre-existing rule), so this changes nothing that does
        not ask for it.

        large-magic-number is the case that forced it. `EncodeDate(2026, 8, 11)`
        was reported as a magic number whose remedy is to name the constant --
        but the literal is a YEAR, and `YEAR_2026 = 2026` is a worse way of
        writing 2026. DataCopy carried 16 of these. Reported 2026-08-31 and
        accepted by the owner in the same reply.

        WHY NOT exclude_if_ancestor. That tests an ancestor's NODE KIND, and the
        kind here is `exprCall` -- shared by every call in the language, so
        listing it would silence the rule almost everywhere. The distinguishing
        fact is WHICH routine is being called, which is a node's TEXT, not its
        kind.

        WHY THE NEAREST ENCLOSING CALL, not any ancestor call. In
        `EncodeDate(2026, 8, Foo(5000))` the 5000 is an argument of Foo and must
        still fire; only the nearest exprArgs decides. Verified against a real
        AST dump rather than assumed -- the grammar's node names have been wrong
        in this repo's comments five times. }
      FExcludeArgOf: TArray<string>;
      { Optional PRECEDING-TEXT exemption ("exclude_if_preceded_by", N-14): regexes,
        case-insensitive, with (*name*)-style placeholders -- the capture name in curly braces -- replaced by the regex-escaped text of capture
        @name. The match is dropped when one of them matches the source text of the
        enclosing routine before the picked node. A pattern naming a capture the match
        did not bind never excludes. }
      FExcludePrecededBy: TArray<string>;
      { The sidecar "fix" entries (autofix wave A0), in file order; empty = the
        rule carries no sidecar fix. See TSidecarFix. }
      FFixes: TArray<TSidecarFix>;
      { True if the picked node (or any ancestor up to the root) is one of the
        node kinds in FExcludeAncestors -- used to suppress a match that sits in
        a structural context the rule should not flag (e.g. an integer literal
        that IS the value of a const definition, for large-magic-number). }
      /// <summary><!-- drag-lint:auto sum -->True if the picked node (or any ancestor up
      /// to the root) is one of the node kinds in FExcludeAncestors -- used to suppress a
      /// match that sits in a structural context the rule should not flag (e.g. an
      /// integer literal that IS the value of a const definition, for
      /// large-magic-number).</summary>
      /// <param name="ANode"><!-- drag-lint:auto type -->const TTSNode</param>
      /// <returns><!-- drag-lint:auto -->Boolean -- Observed: False.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.Lint.QueryRules.TQueryRule.Run (DRagLint.Lint.QueryRules.pas)</para>
      /// <para>Calls: SameText, TreeSitter.TTSNodeHelper.IsNull, TreeSitter.TTSNodeHelper.NodeType, TreeSitter.TTSNodeHelper.Parent</para>
      /// <para>Reads: FExcludeAncestors</para>
      /// <para>Pure</para>
      /// <seealso cref="TreeSitter.TTSNodeHelper.IsNull"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.NodeType"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.Parent"/>
      /// <seealso cref="DRagLint.Lint.QueryRules.TQueryRule.Create"/>
      /// <seealso cref="DRagLint.Lint.QueryRules.TQueryRule.Destroy"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function InExcludedAncestor(const ANode: TTSNode): Boolean;
      { True when FRequireAncestors is empty (no requirement) or the node has an
        ancestor of one of those kinds. }
      /// <summary><!-- drag-lint:auto sum -->True when FRequireAncestors is empty (no
      /// requirement) or the node has an ancestor of one of those kinds.</summary>
      /// <param name="ANode"><!-- drag-lint:auto type -->const TTSNode</param>
      /// <returns><!-- drag-lint:auto -->Boolean -- Observed: False.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.Lint.QueryRules.TQueryRule.Run (DRagLint.Lint.QueryRules.pas)</para>
      /// <para>Calls: SameText, TreeSitter.TTSNodeHelper.IsNull, TreeSitter.TTSNodeHelper.NodeType, TreeSitter.TTSNodeHelper.Parent</para>
      /// <para>Reads: FRequireAncestors</para>
      /// <para>Pure</para>
      /// <seealso cref="TreeSitter.TTSNodeHelper.IsNull"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.NodeType"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.Parent"/>
      /// <seealso cref="DRagLint.Lint.QueryRules.TQueryRule.Create"/>
      /// <seealso cref="DRagLint.Lint.QueryRules.TQueryRule.Destroy"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function HasRequiredAncestor(const ANode: TTSNode): Boolean;
      /// <summary>True when the node sits in the argument list of a call whose
      /// callee is named in <c>exclude_if_argument_of</c>.</summary>
      /// <param name="ANode">The node the finding would be reported on.</param>
      /// <param name="ASource">The file's bytes; the callee name is node TEXT,
      /// so it cannot be answered from the tree shape alone.</param>
      /// <returns>True to DROP the match. False when no exemption is declared,
      /// which is every pre-existing rule.</returns>
      /// <remarks>
      /// Only the NEAREST enclosing argument list is consulted, so a
      /// literal nested in an inner call is judged by that inner callee. See
      /// <c>FExcludeArgOf</c> for why this cannot be an ancestor-kind test.
      /// Pure.
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.Lint.QueryRules.TQueryRule.Run (DRagLint.Lint.QueryRules.pas)</para>
      /// <para>Calls: DRagLint.Lint.QueryRules.NodeText, SameText, TreeSitter.TTSNodeHelper.IsNull, TreeSitter.TTSNodeHelper.NamedChild, TreeSitter.TTSNodeHelper.NamedChildCount, TreeSitter.TTSNodeHelper.NodeType, TreeSitter.TTSNodeHelper.Parent, Trim</para>
      /// <para>Returns: False</para>
      /// <para>Reads: FExcludeArgOf</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Lint.QueryRules.NodeText"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.IsNull"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.NamedChild"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.NamedChildCount"/>
      /// <seealso cref="TreeSitter.TTSNodeHelper.NodeType"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function IsArgumentOfExcludedCallee(const ANode: TTSNode; const ASource: TBytes): Boolean;
      function IsPrecededByExcludedText(const APicked: TTSNode; const ACaptures: TTSQueryCaptureArray; const ASource: TBytes): Boolean;
      { Expands the first applicable fix entry onto AFinding. False = that entry's
        needs_compiler is newer than ActiveTargetCompiler: the caller drops the match. }
      function AttachFix(var AFinding: TLintFinding; const ACaptures: TTSQueryCaptureArray; const ASource: TBytes): Boolean;
    public
      /// <param name="ALanguage"><!-- drag-lint:auto type -->const PTSLanguage</param>
      /// <param name="AQuerySource"><!-- drag-lint:auto type -->const string</param>
      /// <param name="AScmPath"><!-- drag-lint:auto type -->const string</param>
      /// <param name="AJsonPath"><!-- drag-lint:auto type -->const string</param>
      /// <exception cref="Exception"><!-- drag-lint:auto exc -->tree-sitter query compile failed: rule "%s" (offset %d, errType %d,</exception>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.Lint.QueryRules.TQueryRuleLoader.LoadAll (DRagLint.Lint.QueryRules.pas)</para>
      /// <para>Calls: DRagLint.Lint.QueryRules.ExtractRequiredLiteral, Format, LowerCase, SameText, TreeSitter.Query.TTSQuery.Create, Trim, TSQueryError</para>
      /// <para>constructor</para>
      /// <para>Complexity: 16 (cyclomatic, outer body), 81 lines (full implementation)</para>
      /// <para>Reads: FId, FExcludeAncestors, FExcludeArgOf, FExcludePrecededBy, FRequireAncestors, FRequireFileText, FQuery   Writes: FSourcePath, FId, FSeverity, FMessage, FWarnCapture, FEnabled, FRequiredText, FRuleId (+6 more)</para>
      /// <para>Touches: file system</para>
      /// <seealso cref="DRagLint.Lint.QueryRules.ExtractRequiredLiteral"/>
      /// <seealso cref="TreeSitter.Query.TTSQuery.Create"/>
      /// <seealso cref="DRagLint.Lint.QueryRules.TQueryRule.Destroy"/>
      /// <seealso cref="DRagLint.Lint.QueryRules.TQueryRule.HasRequiredAncestor"/>
      /// <seealso cref="DRagLint.Lint.QueryRules.TQueryRule.InExcludedAncestor"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      constructor Create(const ALanguage: PTSLanguage; const AQuerySource, AScmPath, AJsonPath: string);
      /// <summary>Builds the rule around a query compiled elsewhere -- the loader
      /// compiles every .scm in parallel, then builds the rules in path order.</summary>
      /// <param name="AQuerySource">The .scm text AQuery was compiled from.</param>
      /// <param name="AScmPath">Path of the .scm; its base name is the default id.</param>
      /// <param name="AJsonPath">Sidecar json path; skipped when it does not exist.</param>
      /// <param name="AQuery">The compiled query, or nil. Ownership passes to the
      /// rule at entry, so it is freed even when this constructor raises.</param>
      /// <param name="AErrOff">ts_query_new error offset, reported on failure.</param>
      /// <param name="AErrType">ts_query_new error type, reported on failure.</param>
      /// <exception cref="Exception">AQuery is nil or did not compile.</exception>
      /// <remarks>Same observable effects, in the same order, as Create.</remarks>
      constructor CreateCompiled(const AQuerySource, AScmPath, AJsonPath: string; const AQuery: TTSQuery; const AErrOff: UInt32; const AErrType: TTSQueryError);
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Reads: FQuery</para>
      /// <para>Pure</para>
      /// <para>Directives: override</para>
      /// <seealso cref="DRagLint.Lint.QueryRules.TQueryRule.Create"/>
      /// <seealso cref="DRagLint.Lint.QueryRules.TQueryRule.HasRequiredAncestor"/>
      /// <seealso cref="DRagLint.Lint.QueryRules.TQueryRule.InExcludedAncestor"/>
      /// <seealso cref="DRagLint.Lint.QueryRules.TQueryRule.IsArgumentOfExcludedCallee"/>
      /// <seealso cref="DRagLint.Lint.QueryRules.TQueryRule.IsPrecededByExcludedText"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      destructor Destroy; override;
      /// <param name="ARootNode"><!-- drag-lint:auto type -->const TTSNode</param>
      /// <param name="ASource"><!-- drag-lint:auto type -->const TBytes</param>
      /// <param name="AFilePath"><!-- drag-lint:auto type -->const string</param>
      /// <returns><!-- drag-lint:auto -->TArray&lt;TLintFinding&gt; -- Observed:
      /// FoundList.ToArray.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.CLI.Run (DRagLint.CLI.pas) ?, DRagLint.Lint.Linter.TLinter.CheckFileImpl (DRagLint.Lint.Linter.pas)</para>
      /// <para>Calls: Default, DRagLint.Lint.QueryRules.AllPredicatesPass, DRagLint.Lint.QueryRules.NoteRuleTicks, DRagLint.Lint.QueryRules.RuleProfileArmed, DRagLint.Lint.QueryRules.TQueryRule.HasRequiredAncestor, DRagLint.Lint.QueryRules.TQueryRule.InExcludedAncestor, DRagLint.Lint.QueryRules.TQueryRule.IsArgumentOfExcludedCallee, DRagLint.Lint.QueryRules.TQueryRule.IsPrecededByExcludedText, Integer, SameText (+7 more)</para>
      /// <para>Complexity: 14 (cyclomatic, outer body), 86 lines (full implementation)</para>
      /// <para>Reads: FQuery, FWarnCapture, FId, FSeverity, FMessage, FRuleId</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Lint.QueryRules.AllPredicatesPass"/>
      /// <seealso cref="DRagLint.Lint.QueryRules.NoteRuleTicks"/>
      /// <seealso cref="DRagLint.Lint.QueryRules.RuleProfileArmed"/>
      /// <seealso cref="DRagLint.Lint.QueryRules.TQueryRule.HasRequiredAncestor"/>
      /// <seealso cref="DRagLint.Lint.QueryRules.TQueryRule.InExcludedAncestor"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function Run(const ARootNode: TTSNode; const ASource: TBytes; const AFilePath: string): TArray<TLintFinding>;
      /// <summary>A literal the FILE TEXT must contain for this rule's query to
      /// be capable of matching -- a cheap pre-filter the caller may use to skip
      /// running the query at all. '' when no such literal could be proven.</summary>
      /// <remarks>
      /// WHY. Measured on ORM3 2026-08-24: `gettickcount-wraparound` cost 17.48 s
      /// of the 52.82 s ALL 55 .scm rules cost together -- a third of the phase --
      /// to produce ONE finding on the whole corpus. It matches bare
      /// `(identifier)`, so tree-sitter visits every identifier in every file and
      /// runs a regex on each.
      ///
      /// The tempting fix is to narrow the pattern to `(exprCall ...)` like its
      /// cheap sibling `outputdebugstring` (1.41 s, same job). That is WRONG: the
      /// rule's one real hit is `GetTickCount` WITHOUT parentheses, passed as an
      /// argument, so narrowing would buy 16 s by deleting the only finding it has
      /// ever produced here.
      ///
      /// This is the semantics-preserving alternative. The predicate is anchored
      /// to a literal, so the query provably cannot match a file whose text does
      /// not contain that literal -- skipping it changes no result.
      ///
      /// DELIBERATELY CONSERVATIVE: set ONLY when the .scm holds exactly ONE
      /// `#match?` whose pattern is exactly `(?i)^word$`. More than one predicate,
      /// or any regex machinery beyond that, and this stays '' and the rule runs
      /// as before. A wrong literal here would silence a rule, which is far worse
      /// than a slow one -- so the bar is "provable", not "probably fine".
      /// </remarks>
      property RequiredText: string read FRequiredText;
      /// <summary>Lowercased substrings, ANY of which must appear in a file's
      /// text before this rule runs against it. Empty means no requirement.</summary>
      property RequireFileText: TArray<string> read FRequireFileText;
      property Id        : string  read FId      ;
      property Severity  : string  read FSeverity;
      property Message   : string  read FMessage ;
      property SourcePath: string  read FSourcePath;
      property Enabled   : Boolean read FEnabled ;
      property RuleId    : string  read FRuleId  ;
      /// <summary>The sidecar "fix" entries; empty when the rule has none.</summary>
      property Fixes     : TArray<TSidecarFix> read FFixes;
  end;

  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.Lint.Linter.TLinter.Create (DRagLint.Lint.Linter.pas)</para>
  /// <para>Used in units: DRagLint.Lint.Linter</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TQueryRuleLoader = class
    public
      // Loads every *.scm under ARulesDir as a TQueryRule, paired with the
      // sibling <basename>.json if present. Skips and warns on compile failures.
      /// <summary><!-- drag-lint:auto sum -->Loads every *.scm under ARulesDir as a
      /// TQueryRule, paired with the sibling &lt;basename&gt;.json if present. Skips and
      /// warns on compile failures.</summary>
      /// <param name="ALanguage"><!-- drag-lint:auto type -->const PTSLanguage</param>
      /// <param name="ARulesDir"><!-- drag-lint:auto type -->const string</param>
      /// <returns><!-- drag-lint:auto type -->TArray&lt;TQueryRule&gt;</returns>
      /// <exception cref="Exception"><!-- drag-lint:auto exc -->via DRagLint.Lint.QueryRules.TQueryRule.Create: tree-sitter query compile failed: rule "%s" (offset %d, errType %d,</exception>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.Lint.Linter.TLinter.Create (DRagLint.Lint.Linter.pas)</para>
      /// <para>Calls: ChangeFileExt, DRagLint.Lint.QueryRules.IsUnderNestedRulesDir, DRagLint.Lint.QueryRules.TQueryRule.Create, ExtractFileName, Format, FreeAndNil, LowerCase, Writeln</para>
      /// <para>Catches: Exception (swallowed)</para>
      /// <para>Touches: file system</para>
      /// <seealso cref="DRagLint.Lint.QueryRules.IsUnderNestedRulesDir"/>
      /// <seealso cref="DRagLint.Lint.QueryRules.TQueryRule.Create"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function LoadAll(const ALanguage: PTSLanguage; const ARulesDir: string): TArray<TQueryRule>;
  end;

  /// <summary>One rule's share of the .scm query cost, accumulated across every
  /// file this process linted.</summary>
  /// <remarks>
  /// Diagnostic only, and populated ONLY while DRAGLINT_PROFILE is set.
  /// See QueryRuleTimings for why this exists.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Lint.QueryRules.pas), DRagLint.CLI.DoLintAll (DRagLint.CLI.pas), DRagLint.Lint.QueryRules.QueryRuleTimings (DRagLint.Lint.QueryRules.pas)</para>
  /// <para>Used in units: DRagLint.CLI, DRagLint.Lint.QueryRules</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
type
  TQueryRuleTiming = record
    /// <summary>The rule id as the sidecar json declares it.</summary>
    RuleId : string ;
    /// <summary>Seconds spent inside TQueryRule.Run for this rule.</summary>
    Seconds: Double ;
    /// <summary>Times Run was entered -- normally once per scanned file.</summary>
    Calls  : Int64  ;
  end;

/// <summary>Per-rule .scm query cost, most expensive first.</summary>
/// <returns>One entry per rule that ran; empty when DRAGLINT_PROFILE was unset.</returns>
/// <remarks>
/// SESSION 36 (P3). The .scm queries are the largest single item left in
/// lint-all -- 54.35 s of a 277 s ORM3 run -- but that is the cost of all 114
/// TOGETHER, which is not something a fix can be aimed at. The standing
/// instruction on this item is to MEASURE PER RULE BEFORE TOUCHING ANYTHING,
/// because the last two attempts to optimise this phase from the aggregate
/// picked the wrong target: the quadratic `Findings := Findings + X` measured
/// 0.00 s, and the .scm double parse was real but worth 1.38 s of 271 s.
/// Two QueryPerformanceCounter reads per rule per file, and only when armed.
/// Not thread-safe; lint-all is single-threaded here.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.DoLintAll (DRagLint.CLI.pas)</para>
/// <para>Calls: CompareText</para>
/// <para>Pure</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function QueryRuleTimings: TArray<TQueryRuleTiming>;


/// <summary>The declared type of AName as seen from byte offset AByte of a
/// parsed file -- the same scope walk #declared-type? makes.</summary>
/// <param name="ARoot">Root node of the file's tree.</param>
/// <param name="ASource">The bytes the tree was parsed from.</param>
/// <param name="AByte">A byte offset inside the routine that uses AName.</param>
/// <param name="AName">The identifier to resolve; case-insensitive.</param>
/// <param name="AType">Out: the declared type text, whitespace removed.</param>
/// <returns>True when a same-routine local, parameter, inline var or unit-level
/// var declares AName with an explicit type; False for a field, a with-member,
/// an untyped inline var or anything else the source does not show.</returns>
function DeclaredTypeAt(const ARoot: TTSNode; const ASource: TBytes; AByte: UInt32;
  const AName: string; out AType: string): Boolean;

implementation

uses
  System.Diagnostics       { TStopwatch -- the per-rule .scm timing below }
  , System.Threading        { TParallel.For -- the loader compiles the .scm queries in parallel }
  , System.StrUtils        { IndexText -- capture-name lookup for sidecar fixes }
  , DRagLint.Lint.RuleCatalog { RegisterSidecarFixRule -- a rule with a "fix" key is fixable }
  , DRagLint.Lint.TargetCompiler { per-entry needs_compiler gate in AttachFix }
  , System.Generics.Defaults { TComparer -- sorting that table by cost }
  , System.RegularExpressionsCore { ERegularExpressionError -- a bad rule regex }
  ;

{ Armed once, from DRAGLINT_PROFILE, so the unarmed path costs one Boolean test
  per rule per file rather than an environment read. }
var
  GRuleProfileArmed: Boolean;
  GRuleProfileRead : Boolean;
  GRuleTicks       : TDictionary<string, Int64>;
  GRuleCalls       : TDictionary<string, Int64>;

function RuleProfileArmed: Boolean;
begin
  if not GRuleProfileRead then
  begin
    GRuleProfileArmed:= GetEnvironmentVariable('DRAGLINT_PROFILE') <> '';
    GRuleProfileRead := True;
    if GRuleProfileArmed then
    begin
      GRuleTicks:= TDictionary<string, Int64>.Create;
      GRuleCalls:= TDictionary<string, Int64>.Create;
    end;
  end;
  Result:= GRuleProfileArmed;
end;

procedure NoteRuleTicks(const ARuleId: string; ATicks: Int64);
var
  Prior: Int64;
begin
  if GRuleTicks = nil then Exit;
  if not GRuleTicks.TryGetValue(ARuleId, Prior) then Prior:= 0;
  GRuleTicks.AddOrSetValue(ARuleId, Prior + ATicks);
  if not GRuleCalls.TryGetValue(ARuleId, Prior) then Prior:= 0;
  GRuleCalls.AddOrSetValue(ARuleId, Prior + 1);
end;

function QueryRuleTimings: TArray<TQueryRuleTiming>;
var
  Pair: TPair<string, Int64>;
  T   : TQueryRuleTiming    ;
  N   : Int64               ;
begin
  SetLength(Result, 0);
  if GRuleTicks = nil then Exit;
  for Pair in GRuleTicks do
  begin
    T.RuleId := Pair.Key;
    T.Seconds:= Pair.Value / TStopwatch.Frequency;
    if not GRuleCalls.TryGetValue(Pair.Key, N) then N:= 0;
    T.Calls  := N;
    Result:= Result + [T];
  end;
  { Most expensive first -- the whole point is to name the top few. }
  TArray.Sort<TQueryRuleTiming>(Result, TComparer<TQueryRuleTiming>.Construct(
    function(const L, R: TQueryRuleTiming): Integer
    begin
      if L.Seconds > R.Seconds then Result:= -1
      else if L.Seconds < R.Seconds then Result:= 1
      else Result:= CompareText(L.RuleId, R.RuleId);
    end));
end;

function NodeText(const ANode: TTSNode; const ASource: TBytes): string;
var
  StartIdx: Integer;
  EndIdx  : Integer;
  Len     : Integer;
begin
  Result:= '';
  if ANode.IsNull then Exit;
  StartIdx:= Integer(ANode.StartByte);
  EndIdx  := Integer(ANode.EndByte  );
  Len:= EndIdx - StartIdx;
  if (Len <= 0) or (StartIdx < 0) or (EndIdx > Length(ASource)) then Exit;
  Result:= TEncoding.UTF8.GetString(ASource, StartIdx, Len);
end;

{ TQueryRule }

function TQueryRule.InExcludedAncestor(const ANode: TTSNode): Boolean;
var
  Cur: TTSNode;
  Ex : string ;
begin
  Result:= False;
  if Length(FExcludeAncestors) = 0 then Exit;
  Cur:= ANode;
  while not Cur.IsNull do
  begin
    for Ex in FExcludeAncestors do
      if SameText(Cur.NodeType, Ex) then Exit(True);
    Cur:= Cur.Parent;
  end;
end;

function TQueryRule.HasRequiredAncestor(const ANode: TTSNode): Boolean;
var
  Cur: TTSNode;
  Rq : string ;
begin
  { No requirement declared -> every match qualifies. This is the path every
    pre-existing rule takes, so the feature cannot change their behaviour. }
  if Length(FRequireAncestors) = 0 then Exit(True);
  Result:= False;
  Cur:= ANode;
  while not Cur.IsNull do
  begin
    for Rq in FRequireAncestors do
      if SameText(Cur.NodeType, Rq) then Exit(True);
    Cur:= Cur.Parent;
  end;
end;

{ AST SHAPE, DUMPED NOT GUESSED (tools\dumpnode, 2026-09-03):

    exprCall  ChildCount=4 NamedChildCount=2
      child[0] identifier  named=True   EncodeDate
      child[1] (           named=False
      child[2] exprArgs    named=True   2026, 8, 11
      child[3] )           named=False

  So the argument list is an `exprArgs` whose parent is the `exprCall`, and the
  callee is that call's FIRST NAMED child. This repo's own comments have named
  grammar nodes wrongly five times, which is why it was dumped.

  The climb STOPS at the first exprArgs. `EncodeDate(2026, 8, Foo(5000))` dumps
  as two nested exprCalls, and 5000's nearest exprArgs belongs to Foo -- so it
  is judged against Foo and still fires. Walking all the way to the root would
  exempt it, which would be a silent false negative inside the very shape this
  exemption is narrowest about. }
function TQueryRule.IsArgumentOfExcludedCallee(const ANode: TTSNode; const ASource: TBytes): Boolean;
var
  Cur   : TTSNode;
  Call  : TTSNode;
  Callee: string ;
  Ex    : string ;
begin
  Result:= False;
  { Not declared -> never runs. Every pre-existing rule takes this path. }
  if Length(FExcludeArgOf) = 0 then Exit;
  Cur:= ANode;
  while not Cur.IsNull do
  begin
    if SameText(Cur.NodeType, 'exprArgs') then
    begin
      Call:= Cur.Parent;
      if Call.IsNull or (not SameText(Call.NodeType, 'exprCall')) then Exit;
      if Call.NamedChildCount = 0 then Exit;
      Callee:= Trim(NodeText(Call.NamedChild(0), ASource));
      for Ex in FExcludeArgOf do
        if SameText(Callee, Ex) then Exit(True);
      Exit; { nearest argument list decides -- see the header }
    end;
    Cur:= Cur.Parent;
  end;
end;

{ N-14. See FExcludePrecededBy. The window is the enclosing routine (defProc)
  up to the picked node, or the file start when the match is outside a routine.
  Each brace-wrapped capture name becomes the regex-escaped text of capture @name, so the pattern can
  insist on the SAME array the match named. }
function TQueryRule.IsPrecededByExcludedText(const APicked: TTSNode; const ACaptures: TTSQueryCaptureArray; const ASource: TBytes): Boolean;
var
  Cur     : TTSNode;
  StartB  : Integer;
  Window  : string ;
  Pat     : string ;
  Expanded: string ;
  Cap     : TTSQueryCapture;
  CapName : string ;
  Bound   : Boolean;
begin
  Result:= False;
  if Length(FExcludePrecededBy) = 0 then Exit;
  StartB:= 0;
  Cur:= APicked.Parent;
  while not Cur.IsNull do
  begin
    if Cur.NodeType = 'defProc' then
    begin
      StartB:= Integer(Cur.StartByte);
      Break;
    end;
    Cur:= Cur.Parent;
  end;
  if Integer(APicked.StartByte) <= StartB then Exit;
  Window:= TEncoding.UTF8.GetString(ASource, StartB, Integer(APicked.StartByte) - StartB);
  for Pat in FExcludePrecededBy do
  begin
    Expanded:= Pat;
    for Cap in ACaptures do
    begin
      CapName:= FQuery.CaptureNameForID(Cap.index);
      Expanded:= StringReplace(Expanded, '{' + CapName + '}', TRegEx.Escape(Trim(NodeText(Cap.node, ASource))), [rfReplaceAll, rfIgnoreCase]);
    end;
    Bound:= not TRegEx.IsMatch(Expanded, '\{[A-Za-z0-9_]+\}');
    if Bound and TRegEx.IsMatch(Window, Expanded, [roIgnoreCase]) then Exit(True);
  end;
end;

{ The literal a query's text must contain for it to be able to match -- see
  TQueryRule.RequiredText for why this exists and why it is this strict.

  PROVEN, NOT GUESSED. Returns a literal ONLY for the exact shape

      (#match? @cap "(?i)^word$")

  appearing EXACTLY ONCE in the .scm, where word is [A-Za-z0-9_]+. Anything else
  -- a second #match?, a #not-match?, alternation, character classes, an unanchored
  pattern -- returns '' and the rule runs unfiltered. Getting this wrong silences a
  rule, which is far worse than a slow rule, so the bar is deliberately high and
  the failure direction is "run it anyway".

  Comment lines (';' to end of line) are ignored: a rule's header prose routinely
  mentions the API name and must not be mistaken for a predicate. }
function ExtractRequiredLiteral(const AQuerySource: string): string;
var
  Code: TStringBuilder;
  Line: string        ;
  P    : Integer      ;
  M    : TMatchCollection;
begin
  Result:= '';
  { Strip ';' comments first. }
  Code:= TStringBuilder.Create;
  try
    for Line in AQuerySource.Split([sLineBreak, #10]) do
    begin
      P:= Pos(';', Line);
      if P > 0 then Code.AppendLine(Copy(Line, 1, P - 1))
               else Code.AppendLine(Line);
    end;
    { Every #match?-family predicate, so a second one (or a #not-match?) is seen
      and disqualifies the rule rather than being skipped over. }
    M:= TRegEx.Matches(Code.ToString, '#(?:not-)?match\?\s+@\S+\s+"([^"]*)"');
    if M.Count <> 1 then Exit;
    var Pat: string:= M.Item[0].Groups[1].Value;
    { Exactly the anchored case-insensitive word form, nothing else. }
    var W: TMatch:= TRegEx.Match(Pat, '^\(\?i\)\^([A-Za-z0-9_]+)\$$');
    if not W.Success then Exit;
    { And it must be a #match?, not a #not-match? -- absence of the literal makes
      a NEGATED predicate TRUE, so the file would still need visiting. }
    if Code.ToString.Contains('#not-match?') then Exit;
    Result:= LowerCase(W.Groups[1].Value);
  finally
    Code.Free;
  end;
end;

{ Parses a sidecar "fix" value (one object or an array of objects) into its
  entries, in order; malformed objects are dropped. Grammar: TSidecarFix. }
function ParseSidecarFix(const AValue: TJSONValue): TArray<TSidecarFix>;

  procedure AddOne(const AObj: TJSONObject);
  var
    Fx: TSidecarFix;
    V : TJSONValue ;
  begin
    Fx:= Default(TSidecarFix);
    V:= AObj.GetValue('when_capture');
    if V <> nil then Fx.WhenCapture:= Trim(V.Value);
    V:= AObj.GetValue('uses');
    if V <> nil then Fx.UsesUnit:= Trim(V.Value);
    V:= AObj.GetValue('risky');
    Fx.Risky:= (V <> nil) and SameText(V.Value, 'true');
    V:= AObj.GetValue('needs_compiler');
    if V <> nil then Fx.NeedsCompiler:= StrToIntDef(V.Value, 0);
    if AObj.GetValue('replace') <> nil then
    begin
      Fx.Kind    := lfkReplace;
      Fx.Template:= AObj.GetValue('replace').Value;
    end
    else if AObj.GetValue('delete') <> nil then
    begin
      V:= AObj.GetValue('delete');
      if SameText(V.Value, 'span') then Fx.Kind:= lfkDeleteSpan
      else if SameText(V.Value, 'statement') then Fx.Kind:= lfkDeleteStatement
      else Exit;   { unknown delete target: the entry is ignored }
    end
    else Exit;     { neither replace nor delete: ignored }
    Result:= Result + [Fx];
  end;

begin
  Result:= nil;
  if AValue is TJSONObject then AddOne(TJSONObject(AValue))
  else if AValue is TJSONArray then
    for var Item: TJSONValue in TJSONArray(AValue) do
      if Item is TJSONObject then AddOne(TJSONObject(Item));
end;

{ Expands a sidecar fix template: each brace-wrapped capture name becomes the RAW
  text of that capture (case-insensitive). False when a placeholder is left
  unbound -- the entry then does not apply, so a half-expanded template is never
  written. }
function ExpandFixTemplate(const ATemplate: string; const ANames, ATexts: TArray<string>; out AText: string): Boolean;
var
  i   : Integer       ;
  Ph  : TMatch        ;
  Last: Integer       ;
  SB  : TStringBuilder;
begin
  AText:= ATemplate;
  { Every placeholder must be bound BEFORE anything is substituted: a capture's
    own text may hold a brace comment such as (*x*) written with braces, which
    must neither count as unbound nor be expanded again. }
  for Ph in TRegEx.Matches(ATemplate, '\{([A-Za-z_][A-Za-z0-9_]*)\}') do
    if IndexText(Ph.Groups[1].Value, ANames) < 0 then Exit(False);
  { one pass over the template, so substituted text is never re-scanned }
  SB:= TStringBuilder.Create;
  try
    Last:= 1;
    for Ph in TRegEx.Matches(ATemplate, '\{([A-Za-z_][A-Za-z0-9_]*)\}') do
    begin
      SB.Append(Copy(ATemplate, Last, Ph.Index - Last));
      i:= IndexText(Ph.Groups[1].Value, ANames);
      SB.Append(if i <= High(ATexts) then ATexts[i] else Ph.Value);   { i >= 0: checked above }
      Last:= Ph.Index + Ph.Length;
    end;
    SB.Append(Copy(ATemplate, Last, MaxInt));
    AText:= SB.ToString;
  finally
    SB.Free;
  end;
  Result:= True;
end;

constructor TQueryRule.Create(const ALanguage: PTSLanguage; const AQuerySource, AScmPath, AJsonPath: string);  // dl:ok missing-inherited-ctor@8f39 -- delegates to CreateCompiled, which calls inherited Create
var
  ErrOff : UInt32       ;
  ErrType: TTSQueryError;
begin
  ErrOff:= 0;
  ErrType:= TSQueryError(0);
  CreateCompiled(AQuerySource, AScmPath, AJsonPath, TTSQuery.Create(ALanguage, AQuerySource, ErrOff, ErrType), ErrOff, ErrType);
end; // constructor

constructor TQueryRule.CreateCompiled(const AQuerySource, AScmPath, AJsonPath: string; const AQuery: TTSQuery; const AErrOff: UInt32; const AErrType: TTSQueryError);
var
  JSON   : TJSONObject  ;
  RawJson: string       ;
  ExArr  : TJSONArray   ;
  ExVal  : TJSONValue   ;
begin
  inherited Create;
  FQuery:= AQuery; { first: Destroy frees it if anything below raises }
  FSourcePath:= AScmPath;
  FId:= TPath.GetFileNameWithoutExtension(AScmPath);
  FSeverity:= 'warning';
  FMessage:= Format('matched rule "%s"', [FId]);
  FWarnCapture:= 'warn';
  FEnabled:= True;   // rules run unless their sidecar json says "enabled": false
  FRequiredText:= ExtractRequiredLiteral(AQuerySource);

  if (AJsonPath <> '') and TFile.Exists(AJsonPath) then
  begin
    RawJson:= TFile.ReadAllText(AJsonPath, TEncoding.UTF8);
    JSON:= TJSONObject.ParseJSONValue(RawJson) as TJSONObject;
    if Assigned(JSON) then
    try
      if JSON.GetValue('id'          ) <> nil then begin FId:= JSON.GetValue('id').Value; FRuleId:= FId; end;
      if JSON.GetValue('severity'    ) <> nil then FSeverity   := JSON.GetValue('severity'    ).Value;
      if JSON.GetValue('message'     ) <> nil then FMessage    := JSON.GetValue('message'     ).Value;
      if JSON.GetValue('warn_capture') <> nil then FWarnCapture:= JSON.GetValue('warn_capture').Value;
      if JSON.GetValue('enabled'     ) <> nil then
        FEnabled:= not SameText(JSON.GetValue('enabled').Value, 'false');
      { Optional structural exemption: node kinds whose subtree should NOT fire
        this rule. A match is dropped when the picked node has an ancestor of any
        listed kind. E.g. large-magic-number lists "declConst" so a literal that
        IS a const's value is not told to "name the constant" -- it already is. }
      ExArr:= JSON.GetValue('exclude_if_ancestor') as TJSONArray;
      if Assigned(ExArr) then
        for ExVal in ExArr do
          FExcludeAncestors:= FExcludeAncestors + [ExVal.Value];
      { Optional CALLEE exemption ("exclude_if_argument_of"): the match is
        dropped when it sits in the argument list of a call to one of these
        routines. large-magic-number lists the date constructors, so
        `EncodeDate(2026, 8, 11)` is not told to name a constant for the year.
        See FExcludeArgOf for why an ancestor-KIND test cannot express this. }
      ExArr:= JSON.GetValue('exclude_if_argument_of') as TJSONArray;
      if Assigned(ExArr) then
        for ExVal in ExArr do
          FExcludeArgOf:= FExcludeArgOf + [ExVal.Value];
      ExArr:= JSON.GetValue('exclude_if_preceded_by') as TJSONArray;
      if Assigned(ExArr) then
        for ExVal in ExArr do
          FExcludePrecededBy:= FExcludePrecededBy + [ExVal.Value];
      { Optional structural REQUIREMENT ("require_ancestor"): the match counts
        only inside one of these node kinds. E.g. concat-in-loop lists the four
        loop kinds (for / foreach / while / repeat), so `S := S + X` executed
        once no longer reports a quadratic cost that a single execution cannot
        have. `foreach` is the for-in node; it was missing until D20. }
      ExArr:= JSON.GetValue('require_ancestor') as TJSONArray;
      if Assigned(ExArr) then
        for ExVal in ExArr do
          FRequireAncestors:= FRequireAncestors + [ExVal.Value];
      { Optional FILE-TEXT requirement ("require_file_text"): the rule does not
        run at all against a file whose text contains none of these. Matched
        case-insensitively against the whole file, so it sees the uses clause,
        qualified calls and the dfm-bearing header alike. See FRequireFileText. }
      ExArr:= JSON.GetValue('require_file_text') as TJSONArray;
      if Assigned(ExArr) then
        for ExVal in ExArr do
          if Trim(ExVal.Value) <> '' then
            FRequireFileText:= FRequireFileText + [LowerCase(Trim(ExVal.Value))];
      { Optional sidecar FIX ("fix", autofix wave A0): see TSidecarFix. }
      FFixes:= ParseSidecarFix(JSON.GetValue('fix'));
    finally
      JSON.Free;
    end;
  end; // if
  if Length(FFixes) > 0 then
  begin
    var AnyRisky: Boolean:= False;
    for var Fx: TSidecarFix in FFixes do AnyRisky:= AnyRisky or Fx.Risky;
    RegisterSidecarFixRule(FId, AnyRisky);
  end;

  if (FQuery = nil) or (FQuery.Query = nil) then
  begin
    raise Exception.CreateFmt( 'tree-sitter query compile failed: rule "%s" (offset %d, errType %d, ' + 'source %s)', [FId, AErrOff, Ord(AErrType), AScmPath]); // dl:ok raise-bare-exception@0a61 -- REVIEWED 2026-10-30: a rule-load failure is only shown as text by the loader (RULE-LOAD-FAIL), which catches Exception; a subclass would add nothing for any caller
  end;
end; // constructor

destructor TQueryRule.Destroy;
begin
  FQuery.Free;
  inherited;
end;

// Resolve a predicate step group to a list of args. The first arg is the
// operator (e.g. "eq?"); subsequent args are either captured node text or
// literal strings.
type
  TPredicateArg = record
    IsCapture   : Boolean;
    CaptureIndex: UInt32 ;
    StringValue : string ;
  end;

function ResolveCaptureText(const AMatch: TTSQueryMatch; ACaptureIndex: UInt32; const ASource: TBytes): string;
var
  Caps: TTSQueryCaptureArray;
  i   : Integer             ;
begin
  Result:= '';
  Caps:= AMatch.CapturesArray;
  for i:= 0 to Length(Caps) - 1 do
    if Caps[i].index = ACaptureIndex then Exit(NodeText(Caps[i].node, ASource));
end;

// The NODE behind a capture index, or a null node when the match has none.
function ResolveCaptureNode(const AMatch: TTSQueryMatch; ACaptureIndex: UInt32): TTSNode;
var
  Caps: TTSQueryCaptureArray;
  i   : Integer             ;
begin
  Result:= Default(TTSNode);
  Caps:= AMatch.CapturesArray;
  for i:= 0 to Length(Caps) - 1 do
    if Caps[i].index = ACaptureIndex then Exit(Caps[i].node);
end;

{ (#in? @cap "nodeType" ["nameRegex"]) / (#not-in? ...) -- 2026-09-16.

  True (for #in?) when SOME ancestor of the captured node has NodeType
  "nodeType" and, if a third argument is given, that ancestor's `name:` field
  matches the regex. #not-in? is the negation. Without the regex the predicate
  is purely structural ("is this literal inside a declConst at all").

  WHY A NEW PREDICATE. tree-sitter's own predicates see only the captured text,
  so a rule cannot say "unless the enclosing declaration is named like a
  version". hardcoded-ip-address needed exactly that: `YADF_MIN_VERSION =
  '1.0.6.6'` is the shape of an IPv4 literal AND of every dotted version
  constant a codebase has, and a rule wrong in a whole CATEGORY teaches people
  to skim it. Writing one pattern per syntactic context the literal can sit in
  (const, assignment, argument, ...) would need node names this repo has been
  wrong about five times; walking Parent from the capture needs none of them.

  The walk is bounded by the tree's depth and runs only for matches that
  already passed the cheaper predicates before it in the same pattern, so put
  it LAST in a rule. Unknown field / no `name:` on the ancestor counts as "no
  match" for the regex form, never as an error. }
function AncestorNamedLike(const ANode: TTSNode; const ASource: TBytes; const ANodeType, ANameRx: string): Boolean;
var
  Cur : TTSNode;
  Nm  : TTSNode;
begin
  Result:= False;
  if ANode.IsNull then Exit;
  Cur:= ANode.Parent;
  while not Cur.IsNull do
  begin
    if Cur.NodeType = ANodeType then
    begin
      if ANameRx = '' then Exit(True);
      Nm:= Cur.ChildByField('name');
      { a defProc carries its name on the header (declProc), not on itself }
      if Nm.IsNull and (ANodeType = 'defProc') then
        Nm:= Cur.ChildByField('header').ChildByField('name');
      if not Nm.IsNull then
        try
          if TRegEx.IsMatch(NodeText(Nm, ASource), ANameRx) then Exit(True);
        except
          { a bad regex in a rule file must not take the scan down }
        end;
    end;
    Cur:= Cur.Parent;
  end;
end;

{ True when ANode's subtree contains an `identifier` whose text is AName
  (case-insensitive -- Delphi identifiers are). }
function SubtreeHasIdentifier(const ANode: TTSNode; const ASource: TBytes; const AName: string): Boolean;
var
  I: Integer;
begin
  if ANode.IsNull then Exit(False);
  if (ANode.NodeType = 'identifier') and SameText(NodeText(ANode, ASource), AName) then Exit(True);
  for I:= 0 to Integer(ANode.NamedChildCount) - 1 do
    if SubtreeHasIdentifier(ANode.NamedChild(I), ASource, AName) then Exit(True);
  Result:= False;
end;

{ True when AStmt is `AName := <expr>` and <expr> does not read AName -- a
  statement that throws the old value away. Named children of an assignment
  are [identifier, kAssign, rhs] (keywords are named nodes in this grammar),
  so the right side is the LAST named child. }
function IsResetOf(const AStmt: TTSNode; const ASource: TBytes; const AName: string): Boolean;
const
  MIN_ASSIGN_CHILDREN = 3; // lhs, kAssign, rhs
var
  Lhs: TTSNode;
begin
  if AStmt.IsNull or (AStmt.NodeType <> 'assignment') then Exit(False);
  if Integer(AStmt.NamedChildCount) < MIN_ASSIGN_CHILDREN then Exit(False);
  Lhs:= AStmt.NamedChild(0);
  if (Lhs.NodeType <> 'identifier') or not SameText(NodeText(Lhs, ASource), AName) then Exit(False);
  Result:= not SubtreeHasIdentifier(AStmt.NamedChild(AStmt.NamedChildCount - 1), ASource, AName);
end;

{ (#reset-in-loop? @assign) / (#not-reset-in-loop? @assign) -- 2026-09-23, L6.

  True when the variable assigned by @assign (`S := S + X`) is ALSO reset --
  `S := <expr not reading S>` -- unconditionally in the same pass of the
  NEAREST enclosing loop. Then S does not accumulate across iterations: each
  pass rebuilds it, the concatenation is O(1) per pass, and concat-in-loop's
  "O(n^2), use TStringList" is false. `T := 'row '; T := T + IntToStr(J);` in
  a loop body is the reported shape.

  UNCONDITIONAL is the whole test. The reset must be a SIBLING statement in a
  statement list (`block`, or the `statements` of a repeat/try/case arm) that
  lies on the path from @assign up to the nearest loop: every statement of such
  a list runs whenever @assign's own statement does. A reset inside an `if`
  that is not on that path is conditional and does not count, so the finding
  stands. Siblings AFTER the concatenation count as well as siblings before it
  -- `S := S + X; Emit(S); S := ''` empties S before the next pass. The walk
  STOPS at the nearest loop (for / foreach / while / repeat, dumped not
  guessed), so an outer loop's reset never excuses an inner loop that really
  does accumulate. Early exits (Continue/Break/Exit between the two) are not
  modelled; they can only turn a real accumulation into a missed one. }
function ResetInSameIteration(const AAssign: TTSNode; const ASource: TBytes): Boolean;
const
  LOOP_KINDS: array[0..3] of string = ('for', 'foreach', 'while', 'repeat');
var
  Name  : string ;
  Cur   : TTSNode;
  Parent: TTSNode;
  Sib   : TTSNode;
  I     : Integer;
  Kind  : string ;
begin
  Result:= False;
  if AAssign.IsNull or (AAssign.NamedChildCount = 0) then Exit;
  Name:= NodeText(AAssign.NamedChild(0), ASource);
  if Name = '' then Exit;
  Cur:= AAssign;
  while True do
  begin
    Parent:= Cur.Parent;
    if Parent.IsNull then Exit;
    for Kind in LOOP_KINDS do
      if Parent.NodeType = Kind then Exit; { reached the nearest loop }
    if (Parent.NodeType = 'block') or (Parent.NodeType = 'statements') then
      for I:= 0 to Integer(Parent.NamedChildCount) - 1 do
      begin
        Sib:= Parent.NamedChild(I);
        if (Sib.StartByte = Cur.StartByte) and (Sib.EndByte = Cur.EndByte) then Continue;
        if IsResetOf(Sib, ASource, Name) then Exit(True);
      end;
    Cur:= Parent;
  end;
end;

{ (#reset-in-loop? @assign) / (#not-reset-in-loop? @assign) -- see
  ResetInSameIteration. Malformed arguments pass, like every predicate here:
  a directive we cannot read must not silently suppress matches. }
function EvalResetInLoop(const AMatch: TTSQueryMatch; const ASource: TBytes;
  const AArgs: TArray<TPredicateArg>; ANegated: Boolean): Boolean;
const
  OP_AND_CAPTURE = 2; // the operator + one capture
  CAP_ARG        = 1;
begin
  if (Length(AArgs) <> OP_AND_CAPTURE) or not AArgs[CAP_ARG].IsCapture then Exit(True);
  Result:= ResetInSameIteration(ResolveCaptureNode(AMatch, AArgs[CAP_ARG].CaptureIndex), ASource);
  if ANegated then Result:= not Result;
end;

{ ANode's named children, in order, from ONE tree-cursor walk.

  NOT a loop over NamedChild(I): tree-sitter answers ts_node_named_child by
  re-walking the child list from the first child, so such a loop is O(n^2) on
  a wide node -- a routine body of 10k statements is one `block` with 10k
  children. The cursor steps sibling to sibling, O(n) in all. }
function NamedChildrenOf(const ANode: TTSNode): TArray<TTSNode>;
var
  Cur : TTSTreeCursor  ;
  List: TList<TTSNode> ;
begin
  List:= TList<TTSNode>.Create;
  try
    Cur:= TTSTreeCursor.Create(ANode);
    try
      if Cur.GotoFirstChild then
        repeat
          if Cur.CurrentNode.IsNamed then List.Add(Cur.CurrentNode);
        until not Cur.GotoNextSibling;
    finally
      Cur.Free;
    end;
    Result:= List.ToArray;
  finally
    List.Free;
  end; // try
end;

{ The `type` field text of ADecl with all whitespace removed (`^ Char` ->
  `^Char`), or '' when the declaration carries no explicit type -- an
  inferred inline `var X := Expr`. }
function DeclTypeText(const ADecl: TTSNode; const ASource: TBytes): string;
var
  Ty: TTSNode;
begin
  Ty:= ADecl.ChildByField('type');
  if Ty.IsNull then Exit('');
  Result:= TRegEx.Replace(NodeText(Ty, ASource), '\s', '');
end;

type
  { One name a scope declares among its direct children (see
    TDeclScopeCache.Build). IsInline marks a block's inline var, which is in
    scope only for uses at or after EndByte. }
  TScopeDecl = record
    TypeText: string ;
    EndByte : UInt32 ;
    IsInline: Boolean;
  end;

  { Per-scope declaration tables for ONE TQueryRule.Run (X-23, 2026-10-26).

    #declared-type? walks from a capture to every enclosing scope and asks
    "is this name declared here?". Answered by scanning the scope's children
    per match, that is O(children) per match: on a routine body of n
    statements each matched `X + n` paid for the whole block, O(n^2) per file
    (2k lines 11.7 s, 4k 40.8 s, 10k 252 s of `lint` / LSP didOpen). This
    builds each scope's table once, from one cursor walk, and answers every
    later question from it.

    Keyed by the node's identity (tree-sitter subtree id + start byte), so it
    is valid for ONE tree only -- Run creates and frees it around one cursor
    execution and never shares it. Not thread-safe; it never needs to be. }
  TDeclScopeCache = class
  strict private
    FScopes: TObjectDictionary<string, TDictionary<string, TArray<TScopeDecl>>>;
    class procedure AddNames(AMap: TDictionary<string, TArray<TScopeDecl>>; const ADecl: TTSNode;
      const ASource: TBytes; AEndByte: UInt32; AIsInline: Boolean); static;
    class function Build(const AScope: TTSNode; const ASource: TBytes): TDictionary<string, TArray<TScopeDecl>>; static;
  public
    constructor Create;
    destructor Destroy; override;
    function Find(const AScope: TTSNode; const ASource: TBytes; const AName: string;
      ABeforeByte: UInt32; out AType: string): Boolean;
  end;

constructor TDeclScopeCache.Create;
begin
  inherited Create;
  FScopes:= TObjectDictionary<string, TDictionary<string, TArray<TScopeDecl>>>.Create([doOwnsValues]);
end;

destructor TDeclScopeCache.Destroy;
begin
  FScopes.Free;
  inherited Destroy;
end;

{ Records every `identifier` directly under ADecl (`A, B: T` carries two; the
  type sits inside its own `type` node, so it is never mistaken for a name)
  under its lowercased text, in declaration order. }
class procedure TDeclScopeCache.AddNames(AMap: TDictionary<string, TArray<TScopeDecl>>; const ADecl: TTSNode;
  const ASource: TBytes; AEndByte: UInt32; AIsInline: Boolean);
var
  D   : TScopeDecl       ;
  Id  : TTSNode          ;
  Key : string           ;
  Prev: TArray<TScopeDecl>;
begin
  D.TypeText:= DeclTypeText(ADecl, ASource);
  D.EndByte := AEndByte;
  D.IsInline:= AIsInline;
  for Id in NamedChildrenOf(ADecl) do
    if Id.NodeType = 'identifier' then
    begin
      Key:= LowerCase(NodeText(Id, ASource));
      if AMap.TryGetValue(Key, Prev) then AMap[Key]:= Prev + [D]
      else AMap.Add(Key, [D]);
    end;
end;

{ The declarations among the direct children of AScope, in child order.
  Var sections (`declVars` > `declVar`) count wherever they sit; a routine's
  header contributes its `declArgs`; inline vars (`varDef`, and the
  `varAssignDef` lhs of an `assignment`) count only inside a `block`, tagged
  IsInline with the END of the statement that declares them. A nested
  routine is a child of its parent's `defProc`, but its own locals are never
  visited here: they are not in scope for the parent. }
class function TDeclScopeCache.Build(const AScope: TTSNode; const ASource: TBytes): TDictionary<string, TArray<TScopeDecl>>;
var
  IsBlock: Boolean;
  Child  : TTSNode;
  Sub    : TTSNode;
  Args   : TTSNode;
  Kind   : string ;
begin
  Result:= TDictionary<string, TArray<TScopeDecl>>.Create;
  IsBlock:= AScope.NodeType = 'block';
  for Child in NamedChildrenOf(AScope) do
  begin
    Kind:= Child.NodeType;
    if Kind = 'declVars' then
    begin
      for Sub in NamedChildrenOf(Child) do
        if Sub.NodeType = 'declVar' then AddNames(Result, Sub, ASource, 0, False);
    end
    else if Kind = 'declProc' then
    begin
      Args:= Child.ChildByField('args');
      if not Args.IsNull then
        for Sub in NamedChildrenOf(Args) do
          if Sub.NodeType = 'declArg' then AddNames(Result, Sub, ASource, 0, False);
    end
    else if IsBlock then
    begin
      Sub:= Child;
      if Kind = 'assignment' then Sub:= Child.ChildByField('lhs');
      if (not Sub.IsNull) and ((Sub.NodeType = 'varDef') or (Sub.NodeType = 'varAssignDef')) then
        AddNames(Result, Sub, ASource, Child.EndByte, True);
    end;
  end; // for
end;

{ True, with AType set, when AScope's direct children declare AName in a way
  that is in scope at ABeforeByte; the FIRST such declaration in child order
  wins. An inline var counts only when its statement ENDS at or before
  ABeforeByte -- it is not in scope above its declaration. AType is '' for an
  untyped inline var. The scope's table is built on its first question. }
function TDeclScopeCache.Find(const AScope: TTSNode; const ASource: TBytes; const AName: string;
  ABeforeByte: UInt32; out AType: string): Boolean;
var
  Key : string                                  ;
  Map : TDictionary<string, TArray<TScopeDecl>> ;
  Hits: TArray<TScopeDecl>                      ;
  D   : TScopeDecl                              ;
begin
  AType:= '';
  Key:= Format('%p:%d', [AScope.id, AScope.StartByte]);
  if not FScopes.TryGetValue(Key, Map) then
  begin
    Map:= Build(AScope, ASource);
    FScopes.Add(Key, Map);
  end;
  if Map.TryGetValue(LowerCase(AName), Hits) then
    for D in Hits do
      if (not D.IsInline) or (D.EndByte <= ABeforeByte) then
      begin
        AType:= D.TypeText;
        Exit(True);
      end;
  Result:= False;
end;

{ (#declared-type? @ident "regex") -- 2026-10-14, pchar-arithmetic.

  True when the identifier captured by @ident is declared, in a scope the
  source itself shows, with a type whose text (whitespace removed) matches the
  case-insensitive regex. The walk goes from the capture outwards: each
  enclosing `block` (inline vars declared above the use), each enclosing
  routine (its var sections and parameters), then the unit's own var
  sections. The INNERMOST declaration wins, so a nested routine's local
  shadows its parent's.

  Anything it cannot SEE answers False: a field, a global from another unit,
  a `with` member, an untyped inline var (`var P := Expr`). That is a
  deliberate choice of silence over a guess -- the rule this was written for
  (pchar-arithmetic) used to guess from a `P` prefix and reported
  `PRows := PRows + [Row]` on a TArray. Malformed arguments pass, like every
  predicate here.

  ACache answers each scope's "declared here?" from a table built once per
  scope (X-23): without it every match re-scanned every enclosing scope and
  the rule was quadratic in the routine's length. }
function DeclaredTypeMatches(const ANode: TTSNode; const ASource: TBytes; const ATypeRx: string;
  ACache: TDeclScopeCache): Boolean;
var
  Name : string ;
  Cur  : TTSNode;
  Ty   : string ;
begin
  Result:= False;
  if ANode.IsNull or (ANode.NodeType <> 'identifier') then Exit;
  Name:= NodeText(ANode, ASource);
  Cur:= ANode.Parent;
  while not Cur.IsNull do
  begin
    if ACache.Find(Cur, ASource, Name, ANode.StartByte, Ty) then
    begin
      if Ty = '' then Exit;
      try
        Exit(TRegEx.IsMatch(Ty, ATypeRx, [roIgnoreCase]));
      except  // dl:ok try-except-swallowed@c2a3 -- REVIEWED 2026-10-14: a malformed rule regex answers "no match", never aborts the scan
        on ERegularExpressionError do Exit; { a bad regex in a rule file must not take the scan down }
      end;
    end;
    Cur:= Cur.Parent;
  end;
end;

function DeclaredTypeAt(const ARoot: TTSNode; const ASource: TBytes; AByte: UInt32;
  const AName: string; out AType: string): Boolean;
var
  Cur  : TTSNode        ;
  Kid  : TTSNode        ;
  Found: Boolean        ;
  Cache: TDeclScopeCache;
begin
  AType:= '';
  Result:= False;
  if ARoot.IsNull or (AName = '') then Exit;
  { descend to the innermost named node holding AByte }
  Cur:= ARoot;
  repeat
    Found:= False;
    for Kid in NamedChildrenOf(Cur) do
    begin
      if (Kid.StartByte <= AByte) and (AByte < Kid.EndByte) then
      begin
        Cur:= Kid;
        Found:= True;
        Break;
      end;
    end;
  until not Found;
  Cache:= TDeclScopeCache.Create;
  try
    while not Cur.IsNull do
    begin
      if Cache.Find(Cur, ASource, AName, AByte, AType) then Exit(AType <> '');
      Cur:= Cur.Parent;
    end;
  finally
    Cache.Free;
  end;
end;

function EvalDeclaredType(const AMatch: TTSQueryMatch; const ASource: TBytes;
  const AArgs: TArray<TPredicateArg>; ACache: TDeclScopeCache): Boolean;
const
  OP_CAPTURE_RX = 3; // the operator + one capture + the regex
  CAP_ARG       = 1;
  RX_ARG        = 2;
begin
  if (Length(AArgs) <> OP_CAPTURE_RX) or not AArgs[CAP_ARG].IsCapture or AArgs[RX_ARG].IsCapture then Exit(True);
  Result:= DeclaredTypeMatches(ResolveCaptureNode(AMatch, AArgs[CAP_ARG].CaptureIndex), ASource,
    AArgs[RX_ARG].StringValue, ACache);
end;

// Evaluate one predicate. Returns True if it passes.
function EvalPredicate(const AQuery: TTSQuery; const AMatch: TTSQueryMatch; const ASource: TBytes; const AArgs: TArray<TPredicateArg>;
  ACache: TDeclScopeCache): Boolean;
const
  { #in? / #not-in? argument positions: (#in? @cap "nodeType" ["nameRegex"]) }
  CapArg    = 1;
  TypeArg   = 2;
  NameRxArg = 3;
  MinArgs   = 3; { op + @cap + "nodeType" }
  MaxArgs   = 4; { ... + "nameRegex" }
var
  i        : Integer;
  Op       : string ;
  FirstText: string ;
  Other    : string ;
  Pattern  : string ;
begin
  if Length(AArgs) < 1 then Exit(True);
  if not AArgs[0].IsCapture then Op:= AArgs[0].StringValue
  else Op:= '';

  if (Op = 'eq?') or (Op = 'not-eq?') then
  begin
    // (#eq? @cap "literal")  or  (#eq? @cap1 @cap2)
    // Resolve each subsequent arg to a string and compare all-equal.
    if Length(AArgs) < 3 then Exit(True);
    if AArgs[1].IsCapture then FirstText:= ResolveCaptureText(AMatch, AArgs[1].CaptureIndex, ASource)
    else FirstText:= AArgs[1].StringValue;
    Result:= True;
    for i:= 2 to Length(AArgs) - 1 do
    begin
      if AArgs[i].IsCapture then Other:= ResolveCaptureText(AMatch, AArgs[i].CaptureIndex, ASource)
      else Other:= AArgs[i].StringValue;
      if FirstText <> Other then
      begin
        Result:= False;
        Break;
      end;
    end;
    if Op = 'not-eq?' then Result:= not Result;
    Exit;
  end; // if

  if (Op = 'match?') or (Op = 'not-match?') then
  begin
    if Length(AArgs) <> 3 then Exit(True);
    if not AArgs[1].IsCapture then Exit(True);
    if AArgs[2].IsCapture then Exit(True);
    FirstText:= ResolveCaptureText(AMatch, AArgs[1].CaptureIndex, ASource);
    Pattern:= AArgs[2].StringValue;
    try
      Result:= TRegEx.IsMatch(FirstText, Pattern);
    except
      Result:= False;
    end;
    if Op = 'not-match?' then Result:= not Result;
    Exit;
  end;

  if (Op = 'any-of?') or (Op = 'not-any-of?') then
  begin
    if Length(AArgs) < 3 then Exit(True);
    if not AArgs[1].IsCapture then Exit(True);
    FirstText:= ResolveCaptureText(AMatch, AArgs[1].CaptureIndex, ASource);
    Result:= False;
    for i:= 2 to Length(AArgs) - 1 do
      if (not AArgs[i].IsCapture) and (AArgs[i].StringValue = FirstText) then
      begin
        Result:= True;
        Break;
      end;
    if Op = 'not-any-of?' then Result:= not Result;
    Exit;
  end;

  if (Op = 'in?') or (Op = 'not-in?') then
  begin
    { (#in? @cap "nodeType") or (#in? @cap "nodeType" "nameRegex") -- see
      AncestorNamedLike. Malformed arguments pass, like every other predicate
      here: a directive we cannot read must not silently suppress matches. }
    if (Length(AArgs) < MinArgs) or (Length(AArgs) > MaxArgs) then Exit(True);
    if (not AArgs[CapArg].IsCapture) or AArgs[TypeArg].IsCapture then Exit(True);
    if (Length(AArgs) = MaxArgs) and AArgs[NameRxArg].IsCapture then Exit(True);
    Pattern:= '';
    if Length(AArgs) = MaxArgs then Pattern:= AArgs[NameRxArg].StringValue;
    Result:= AncestorNamedLike(ResolveCaptureNode(AMatch, AArgs[CapArg].CaptureIndex), ASource, AArgs[TypeArg].StringValue, Pattern);
    if Op = 'not-in?' then Result:= not Result;
    Exit;
  end;

  if (Op = 'reset-in-loop?') or (Op = 'not-reset-in-loop?') then
    Exit(EvalResetInLoop(AMatch, ASource, AArgs, Op = 'not-reset-in-loop?'));

  if Op = 'declared-type?' then
    Exit(EvalDeclaredType(AMatch, ASource, AArgs, ACache));

  // Unknown predicate - treat as pass (don't suppress matches just because
  // we don't recognise a directive).
  Result:= True;
end; // function

function AllPredicatesPass(const AQuery: TTSQuery; const AMatch: TTSQueryMatch; const ASource: TBytes;
  ACache: TDeclScopeCache): Boolean;
var
  Steps  : TTSQueryPredicateStepArray;
  Current: TList<TPredicateArg>      ;
  Arg    : TPredicateArg             ;
  i      : Integer                   ;
begin
  Steps:= AQuery.PredicatesForPattern(AMatch.pattern_index);
  if Length(Steps) = 0 then Exit(True);
  Current:= TList<TPredicateArg>.Create;
  try
    for i:= 0 to Length(Steps) - 1 do
    begin
      case Steps[i].&type of
        TSQueryPredicateStepTypeCapture:
        begin
          Arg.IsCapture:= True;
          Arg.CaptureIndex:= Steps[i].value_id;
          Arg.StringValue:= '';
          Current.Add(Arg);
        end;
        TSQueryPredicateStepTypeString:
        begin
          Arg.IsCapture   := False;
          Arg.CaptureIndex:= 0;
          Arg.StringValue:= AQuery.StringValueForID(Steps[i].value_id);
          Current.Add(Arg);
        end;
        TSQueryPredicateStepTypeDone:
        begin
          // End of one predicate. Evaluate; if false, the whole match
          // fails. Then reset Current for the next predicate (if any).
          if not EvalPredicate(AQuery, AMatch, ASource, Current.ToArray, ACache) then Exit(False);
          Current.Clear;
        end;
      end; // case
    end; // for
    Result:= True;
  finally
    Current.Free;
  end; // try
end; // function

function TQueryRule.Run(const ARootNode: TTSNode; const ASource: TBytes; const AFilePath: string): TArray<TLintFinding>;
var
  Cursor     : TTSQueryCursor      ;
  Match      : TTSQueryMatch       ;
  Captures   : TTSQueryCaptureArray;
  CapIdx     : UInt32              ;
  FoundList  : TList<TLintFinding> ;
  Finding    : TLintFinding        ;
  CapNode    : TTSNode             ;
  CaptureName: string              ;
  Picked     : TTSNode             ;
  HasWarn    : Boolean             ;
  HasFirst   : Boolean             ;
  i          : Integer             ;
  ProfT0     : Int64               ;
  Profiled   : Boolean             ;
  DeclCache  : TDeclScopeCache     ; { X-23: #declared-type? scope tables, this tree only }
begin
  { P3 MEASUREMENT. Off unless DRAGLINT_PROFILE is set -- see QueryRuleTimings.
    try/finally rather than a tail call: several Exit paths below would otherwise
    drop the sample, and a per-rule table that silently omits its cheapest-
    looking rules is worse than none. }
  Profiled:= RuleProfileArmed;
  if Profiled then ProfT0:= TStopwatch.GetTimeStamp else ProfT0:= 0;
  try
    FoundList:= TList<TLintFinding>.Create;
    Cursor:= TTSQueryCursor.Create;
    DeclCache:= TDeclScopeCache.Create;
    try
      Cursor.Execute(FQuery, ARootNode);
      while Cursor.NextMatch(Match) do
      begin
        // v0.3: evaluate predicates before emitting a finding.
        if not AllPredicatesPass(FQuery, Match, ASource, DeclCache) then Continue;

        Captures:= Match.CapturesArray;
        // Prefer the capture named @<FWarnCapture>; otherwise pin to the
        // first capture.
        Picked:= Default(TTSNode);
        HasWarn := False;
        HasFirst:= False;
        for i:= 0 to Length(Captures) - 1 do
        begin
          CapIdx:= Captures[i].index;
          CaptureName:= FQuery.CaptureNameForID(CapIdx);
          CapNode:= Captures[i].node;
          if (not HasFirst) then
          begin
            Picked  := CapNode;
            HasFirst:= True;
          end;
          if SameText(CaptureName, FWarnCapture) then
          begin
            Picked := CapNode;
            HasWarn:= True;
            Break;
          end;
        end; // for
        if not (HasWarn or HasFirst) then Continue;

        { Structural exemption (JSON "exclude_if_ancestor"): drop the match when the
          picked node lives inside one of the excluded node kinds. }
        if InExcludedAncestor(Picked) then Continue;
        { Callee exemption (JSON "exclude_if_argument_of"): drop the match when
          it is an argument of a call this rule declares uninteresting. }
        if IsArgumentOfExcludedCallee(Picked, ASource) then Continue;
        if IsPrecededByExcludedText(Picked, Captures, ASource) then Continue;
        if not HasRequiredAncestor(Picked) then Continue;

        Finding:= Default(TLintFinding);
        Finding.RuleId  := FId;
        Finding.Severity:= FSeverity;
        Finding.FilePath:= AFilePath;
        Finding.Message := FMessage;
        Finding.StartLine:= Integer(Picked.StartPoint.row   ) + 1;
        Finding.StartCol := Integer(Picked.StartPoint.column) + 1;
        Finding.EndLine  := Integer(Picked.EndPoint  .row   ) + 1;
        Finding.EndCol   := Integer(Picked.EndPoint  .column) + 1;
        if (Length(FFixes) > 0) and not AttachFix(Finding, Captures, ASource) then Continue;
        FoundList.Add(Finding);
      end; // while
      Result:= FoundList.ToArray;
    finally
      DeclCache.Free;
      Cursor.Free;
      FoundList.Free;
    end; // try
  finally
    if Profiled then NoteRuleTicks(FRuleId, TStopwatch.GetTimeStamp - ProfT0);
  end; // try
end; // function

{ Autofix wave A0: the FIRST fix entry that applies to this match is expanded
  onto the finding. An entry applies when its when_capture (if any) is bound
  and its template expands with no placeholder left over. }
function TQueryRule.AttachFix(var AFinding: TLintFinding; const ACaptures: TTSQueryCaptureArray; const ASource: TBytes): Boolean;
var
  Names: TArray<string>;
  Texts: TArray<string>;
  Fx   : TSidecarFix   ;
  Txt  : string        ;
  i    : Integer       ;
begin
  SetLength(Names, Length(ACaptures));
  SetLength(Texts, Length(ACaptures));
  for i:= 0 to High(ACaptures) do
  begin
    Names[i]:= FQuery.CaptureNameForID(ACaptures[i].index);
    Texts[i]:= NodeText(ACaptures[i].node, ASource);
  end;
  Result:= True;
  for Fx in FFixes do
  begin
    if (Fx.WhenCapture <> '') and (IndexText(Fx.WhenCapture, Names) < 0) then Continue;
    { two-way modernize (1.38): the pattern this entry fixes needs a newer
      compiler than the run targets -- the advice itself is void, drop the match }
    if IsGatedByTarget(Fx.NeedsCompiler, ActiveTargetCompiler) then Exit(False);
    Txt:= '';
    if (Fx.Kind = lfkReplace) and not ExpandFixTemplate(Fx.Template, Names, Texts, Txt) then Continue;
    AFinding.FixKind:= Fx.Kind;
    AFinding.FixText:= Txt;
    AFinding.FixUses:= Fx.UsesUnit;
    Exit;
  end;
end;

{ True when ScmPath sits below a sub-directory (relative to ARulesDir) named `rules`. }
function IsUnderNestedRulesDir(const ARulesDir, AScmPath: string): Boolean;
var
  Rel : string;
  Part: string;
begin
  Result:= False;
  Rel:= ExtractFilePath(ExtractRelativePath(IncludeTrailingPathDelimiter(ARulesDir), AScmPath));
  for Part in Rel.Split([PathDelim]) do
    if SameText(Part, 'rules') then Exit(True);
end; // function

{ TQueryRuleLoader }

class function TQueryRuleLoader.LoadAll(const ALanguage: PTSLanguage; const ARulesDir: string): TArray<TQueryRule>;
var
  Files   : TArray<string>   ;
  ScmPath : string           ;
  JsonPath: string           ;
  Rule    : TQueryRule       ;
  List    : TList<TQueryRule>;
  Seen    : TDictionary<string, string>;
  FirstAt : string           ;
  Wall    : TStopwatch       ;
  SumTicks: Int64            ;
  Sources : TArray<string>   ;
  LoadErrs: TArray<string>   ;
  Queries : TArray<TTSQuery> ;
  ErrOffs : TArray<UInt32>   ;
  ErrTypes: TArray<TTSQueryError>;
  Ticks   : TArray<Int64>    ;
  Lang    : PTSLanguage      ;
  I       : Integer          ;
begin
  SetLength(Result, 0);
  if not TDirectory.Exists(ARulesDir) then Exit;
  Wall:= TStopwatch.StartNew;
  Files:= TDirectory.GetFiles(ARulesDir, '*.scm', TSearchOption.soAllDirectories);
  // Key = rule id + file name: one id may legitimately span several forms (hardcoded-credential
  // const + assignment), but the same id in the same-named file twice is a stray copy.
  TArray.Sort<string>(Files); // deterministic: first path wins a duplicate
  { READ + COMPILE IN PARALLEL, BUILD IN ORDER (lane IPERF, 2026-10-28).
    ts_query_new is the whole cost of this routine -- 95 queries, ~30 ms each and
    254 ms for the worst, 3.2 s of a 3.8 s single-file lint -- and it is paid by
    EVERY lint process before the file is even read. Each query compiles against
    the read-only language independently, so the compiles fan out over the pool.
    Everything with an observable effect -- the sidecar json, fix registration,
    the duplicate check, both messages and the result order -- stays in the
    serial loop below, in sorted-path order, exactly as before.
    Guard: tests\autotest\run_rule_load_parallel.ps1. }
  Lang:= ALanguage;
  SetLength(Sources, Length(Files));
  SetLength(LoadErrs, Length(Files));
  SetLength(Queries, Length(Files));
  SetLength(ErrOffs, Length(Files));
  SetLength(ErrTypes, Length(Files));
  SetLength(Ticks, Length(Files));
  try
    TParallel.For(0, High(Files),
      procedure(AIdx: Integer)
      begin
        // A nested directory named `rules` is an xcopy accident, never a rule folder.
        if IsUnderNestedRulesDir(ARulesDir, Files[AIdx]) then Exit;
        var T0: Int64:= TStopwatch.GetTimeStamp;
        try
          Sources[AIdx]:= TFile.ReadAllText(Files[AIdx], TEncoding.UTF8);
          Queries[AIdx]:= TTSQuery.Create(Lang, Sources[AIdx], ErrOffs[AIdx], ErrTypes[AIdx]);
        except  // dl:ok try-except-swallowed@e8d3 -- not swallowed: the message is kept in LoadErrs and printed as RULE-LOAD-FAIL in path order by the serial loop
          on E: Exception do LoadErrs[AIdx]:= E.Message;
        end;
        Ticks[AIdx]:= TStopwatch.GetTimeStamp - T0;
      end);
    SumTicks:= 0;
    List:= TList<TQueryRule>.Create;
    Seen:= TDictionary<string, string>.Create;
    try
      for I:= 0 to High(Files) do
      begin
        ScmPath:= Files[I];
        if IsUnderNestedRulesDir(ARulesDir, ScmPath) then Continue;
        Inc(SumTicks, Ticks[I]);
        JsonPath:= ChangeFileExt(ScmPath, '.json');
        try
          if LoadErrs[I] <> '' then
          begin
            Writeln(Format('  RULE-LOAD-FAIL %s: %s', [ScmPath, LoadErrs[I]]));
            Continue;
          end;
          { Ownership moves to the rule BEFORE the call: CreateCompiled frees the
            query itself when it raises, so the finally below must not see it. }
          var Q: TTSQuery:= Queries[I];
          Queries[I]:= nil;
          Rule:= TQueryRule.CreateCompiled(Sources[I], ScmPath, JsonPath, Q, ErrOffs[I], ErrTypes[I]);
          if Seen.TryGetValue(Rule.Id + '|' + LowerCase(ExtractFileName(ScmPath)), FirstAt) then
          begin
            Writeln(ErrOutput, Format('  RULE-DUPLICATE-ID %s: %s ignored (already loaded from %s)', [Rule.Id, ScmPath, FirstAt]));
            FreeAndNil(Rule); // dl:ok unprotected-object-free@b455 -- REVIEWED 2026-10-24: nothing between Create and this Free can raise (Format/Writeln on strings); ownership passes to List only at List.Add
            Continue;
          end;
          Seen.Add(Rule.Id + '|' + LowerCase(ExtractFileName(ScmPath)), ScmPath);
          List.Add(Rule);
        except
          on E: Exception do Writeln(Format('  RULE-LOAD-FAIL %s: %s', [ScmPath, E.Message]));
        end;
      end;
      Result:= List.ToArray;
      if RuleProfileArmed then
        Writeln(ErrOutput, Format('[rule-load] %d rules compiled: wall %.3f s, cpu-sum %.3f s',
          [Length(Result), Wall.Elapsed.TotalSeconds, SumTicks / TStopwatch.Frequency], TFormatSettings.Invariant));
    finally
      Seen.Free;
      List.Free;
    end; // try
  finally
    for I:= 0 to High(Queries) do Queries[I].Free; { only a query no rule took over }
  end; // try
end; // function

end.
