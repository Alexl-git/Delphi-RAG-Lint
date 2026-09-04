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
  // A loaded external lint rule expressed as a tree-sitter S-expression query.
  // Sister .json file (same basename) supplies metadata: id, severity, message.
  /// <summary><!-- drag-lint:auto -->A loaded external lint rule expressed as a
  /// tree-sitter S-expression query. Sister .json file (same basename) supplies metadata:
  /// id, severity, message.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Lint.Linter.pas), DRagLint.Lint.Linter.TLinter.Destroy (DRagLint.Lint.Linter.pas), DRagLint.Lint.Linter.TLinter.DefaultDisabledRuleIds (DRagLint.Lint.Linter.pas), DRagLint.Lint.Linter.TLinter.CheckFileImpl (DRagLint.Lint.Linter.pas), declaration (DRagLint.Lint.QueryRules.pas) (+1 more)</para>
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
      { True if the picked node (or any ancestor up to the root) is one of the
        node kinds in FExcludeAncestors -- used to suppress a match that sits in
        a structural context the rule should not flag (e.g. an integer literal
        that IS the value of a const definition, for large-magic-number). }
      /// <summary><!-- drag-lint:auto -->True if the picked node (or any ancestor up to
      /// the root) is one of the node kinds in FExcludeAncestors -- used to suppress a
      /// match that sits in a structural context the rule should not flag (e.g. an
      /// integer literal that IS the value of a const definition, for
      /// large-magic-number).</summary>
      /// <param name="ANode"><!-- drag-lint:auto type -->const TTSNode</param>
      /// <returns><!-- drag-lint:auto -->Boolean -- Observed: False.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.Lint.QueryRules.TQueryRule.Run (DRagLint.Lint.QueryRules.pas)</para>
      /// <para>Calls: SameText</para>
      /// <para>Reads: FExcludeAncestors</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Lint.QueryRules.TQueryRule.Create"/>
      /// <seealso cref="DRagLint.Lint.QueryRules.TQueryRule.Destroy"/>
      /// <seealso cref="DRagLint.Lint.QueryRules.TQueryRule.HasRequiredAncestor"/>
      /// <seealso cref="DRagLint.Lint.QueryRules.TQueryRule.Run"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      function InExcludedAncestor(const ANode: TTSNode): Boolean;
      { True when FRequireAncestors is empty (no requirement) or the node has an
        ancestor of one of those kinds. }
      /// <summary><!-- drag-lint:auto -->True when FRequireAncestors is empty (no
      /// requirement) or the node has an ancestor of one of those kinds.</summary>
      /// <param name="ANode"><!-- drag-lint:auto type -->const TTSNode</param>
      /// <returns><!-- drag-lint:auto -->Boolean -- Observed: False.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.Lint.QueryRules.TQueryRule.Run (DRagLint.Lint.QueryRules.pas)</para>
      /// <para>Calls: SameText</para>
      /// <para>Reads: FRequireAncestors</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Lint.QueryRules.TQueryRule.Create"/>
      /// <seealso cref="DRagLint.Lint.QueryRules.TQueryRule.Destroy"/>
      /// <seealso cref="DRagLint.Lint.QueryRules.TQueryRule.InExcludedAncestor"/>
      /// <seealso cref="DRagLint.Lint.QueryRules.TQueryRule.Run"/>
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
      /// <remarks>Only the NEAREST enclosing argument list is consulted, so a
      /// literal nested in an inner call is judged by that inner callee. See
      /// <c>FExcludeArgOf</c> for why this cannot be an ancestor-kind test.
      /// Pure.</remarks>
      function IsArgumentOfExcludedCallee(const ANode: TTSNode; const ASource: TBytes): Boolean;
    public
      /// <param name="ALanguage"><!-- drag-lint:auto type -->const PTSLanguage</param>
      /// <param name="AQuerySource"><!-- drag-lint:auto type -->const string</param>
      /// <param name="AScmPath"><!-- drag-lint:auto type -->const string</param>
      /// <param name="AJsonPath"><!-- drag-lint:auto type -->const string</param>
      /// <exception cref="Exception"><!-- drag-lint:auto --></exception>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.Lint.QueryRules.TQueryRuleLoader.LoadAll (DRagLint.Lint.QueryRules.pas)</para>
      /// <para>Calls: DRagLint.Lint.QueryRules.ExtractRequiredLiteral, Format, SameText, TreeSitter.Query.TTSQuery.Create, TSQueryError</para>
      /// <para>constructor</para>
      /// <para>Complexity: 12 (cyclomatic, outer body), 58 lines (full implementation)</para>
      /// <para>Reads: FId, FExcludeAncestors, FRequireAncestors, FQuery   Writes: FSourcePath, FId, FSeverity, FMessage, FWarnCapture, FEnabled, FRequiredText, FRuleId (+3 more)</para>
      /// <para>Touches: file system</para>
      /// <seealso cref="DRagLint.Lint.QueryRules.ExtractRequiredLiteral"/>
      /// <seealso cref="TreeSitter.Query.TTSQuery.Create"/>
      /// <seealso cref="DRagLint.Lint.QueryRules.TQueryRule.Destroy"/>
      /// <seealso cref="DRagLint.Lint.QueryRules.TQueryRule.HasRequiredAncestor"/>
      /// <seealso cref="DRagLint.Lint.QueryRules.TQueryRule.InExcludedAncestor"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      constructor Create(const ALanguage: PTSLanguage; const AQuerySource, AScmPath, AJsonPath: string);
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Reads: FQuery</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Lint.QueryRules.TQueryRule.Create"/>
      /// <seealso cref="DRagLint.Lint.QueryRules.TQueryRule.HasRequiredAncestor"/>
      /// <seealso cref="DRagLint.Lint.QueryRules.TQueryRule.InExcludedAncestor"/>
      /// <seealso cref="DRagLint.Lint.QueryRules.TQueryRule.Run"/>
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
      /// <para>Calls: Default, DRagLint.Lint.QueryRules.AllPredicatesPass, DRagLint.Lint.QueryRules.NoteRuleTicks, DRagLint.Lint.QueryRules.TQueryRule.HasRequiredAncestor, DRagLint.Lint.QueryRules.TQueryRule.InExcludedAncestor, Integer, SameText, TreeSitter.Query.TTSQuery.CaptureNameForID, TreeSitter.Query.TTSQueryCursor.Create, TreeSitter.Query.TTSQueryCursor.Execute, TreeSitter.Query.TTSQueryCursor.NextMatch</para>
      /// <para>Complexity: 12 (cyclomatic, outer body), 82 lines (full implementation)</para>
      /// <para>Reads: FQuery, FWarnCapture, FId, FSeverity, FMessage, FRuleId</para>
      /// <para>Pure</para>
      /// <seealso cref="DRagLint.Lint.QueryRules.AllPredicatesPass"/>
      /// <seealso cref="DRagLint.Lint.QueryRules.NoteRuleTicks"/>
      /// <seealso cref="DRagLint.Lint.QueryRules.TQueryRule.HasRequiredAncestor"/>
      /// <seealso cref="DRagLint.Lint.QueryRules.TQueryRule.InExcludedAncestor"/>
      /// <seealso cref="TreeSitter.Query.TTSQuery.CaptureNameForID"/>
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
      /// <summary><!-- drag-lint:auto -->Loads every *.scm under ARulesDir as a
      /// TQueryRule, paired with the sibling &lt;basename&gt;.json if present. Skips and
      /// warns on compile failures.</summary>
      /// <param name="ALanguage"><!-- drag-lint:auto type -->const PTSLanguage</param>
      /// <param name="ARulesDir"><!-- drag-lint:auto type -->const string</param>
      /// <returns><!-- drag-lint:auto type -->TArray&lt;TQueryRule&gt;</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// <para>Called from: DRagLint.Lint.Linter.TLinter.Create (DRagLint.Lint.Linter.pas)</para>
      /// <para>Calls: ChangeFileExt, DRagLint.Lint.QueryRules.TQueryRule.Create, Format, Writeln</para>
      /// <para>Touches: file system</para>
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
  /// <para>Used by: DRagLint.CLI.DoLintAll (DRagLint.CLI.pas), declaration (DRagLint.Lint.QueryRules.pas), DRagLint.Lint.QueryRules.QueryRuleTimings (DRagLint.Lint.QueryRules.pas)</para>
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
/// <para>Calls: CompareText</para>
/// <para>Pure</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function QueryRuleTimings: TArray<TQueryRuleTiming>;

implementation

uses
  System.Diagnostics       { TStopwatch -- the per-rule .scm timing below }
  , System.Generics.Defaults { TComparer -- sorting that table by cost }
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

constructor TQueryRule.Create(const ALanguage: PTSLanguage; const AQuerySource, AScmPath, AJsonPath: string);
var
  ErrOff : UInt32       ;
  ErrType: TTSQueryError;
  JSON   : TJSONObject  ;
  RawJson: string       ;
  ExArr  : TJSONArray   ;
  ExVal  : TJSONValue   ;
begin
  inherited Create;
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
      { Optional structural REQUIREMENT ("require_ancestor"): the match counts
        only inside one of these node kinds. E.g. concat-in-loop lists the three
        loop kinds, so `S := S + X` executed once no longer reports a quadratic
        cost that a single execution cannot have. }
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
    finally
      JSON.Free;
    end;
  end; // if

  ErrOff:= 0;
  ErrType:= TSQueryError(0);
  FQuery:= TTSQuery.Create(ALanguage, AQuerySource, ErrOff, ErrType);
  if FQuery.Query = nil then
  begin
    raise Exception.CreateFmt( 'tree-sitter query compile failed: rule "%s" (offset %d, errType %d, ' + 'source %s)', [FId, ErrOff, Ord(ErrType), AScmPath]);
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

// Evaluate one predicate. Returns True if it passes.
function EvalPredicate(const AQuery: TTSQuery; const AMatch: TTSQueryMatch; const ASource: TBytes; const AArgs: TArray<TPredicateArg>): Boolean;
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

  // Unknown predicate - treat as pass (don't suppress matches just because
  // we don't recognise a directive).
  Result:= True;
end; // function

function AllPredicatesPass(const AQuery: TTSQuery; const AMatch: TTSQueryMatch; const ASource: TBytes): Boolean;
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
          if not EvalPredicate(AQuery, AMatch, ASource, Current.ToArray) then Exit(False);
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
    try
      Cursor.Execute(FQuery, ARootNode);
      while Cursor.NextMatch(Match) do
      begin
        // v0.3: evaluate predicates before emitting a finding.
        if not AllPredicatesPass(FQuery, Match, ASource) then Continue;

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
        FoundList.Add(Finding);
      end; // while
      Result:= FoundList.ToArray;
    finally
      Cursor.Free;
      FoundList.Free;
    end; // try
  finally
    if Profiled then NoteRuleTicks(FRuleId, TStopwatch.GetTimeStamp - ProfT0);
  end; // try
end; // function

{ TQueryRuleLoader }

class function TQueryRuleLoader.LoadAll(const ALanguage: PTSLanguage; const ARulesDir: string): TArray<TQueryRule>;
var
  Files   : TArray<string>   ;
  ScmPath : string           ;
  JsonPath: string           ;
  Source  : string           ;
  Rule    : TQueryRule       ;
  List    : TList<TQueryRule>;
begin
  SetLength(Result, 0);
  if not TDirectory.Exists(ARulesDir) then Exit;
  Files:= TDirectory.GetFiles(ARulesDir, '*.scm', TSearchOption.soAllDirectories);
  List:= TList<TQueryRule>.Create;
  try
    for ScmPath in Files do
    begin
      JsonPath:= ChangeFileExt(ScmPath, '.json');
      try
        Source:= TFile.ReadAllText(ScmPath, TEncoding.UTF8);
        Rule:= TQueryRule.Create(ALanguage, Source, ScmPath, JsonPath);
        List.Add(Rule);
      except
        on E: Exception do Writeln(Format('  RULE-LOAD-FAIL %s: %s', [ScmPath, E.Message]));
      end;
    end;
    Result:= List.ToArray;
  finally
    List.Free;
  end; // try
end; // function

end.
