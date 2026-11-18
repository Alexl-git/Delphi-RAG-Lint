unit DRagLint.Core.LintBudget;

{ Time budgets of the lint machinery, in one unit.

  1. How long a caller waits for ONE out-of-process `drag-lint lint <file>` run.
  Two callers spawn that child with a hard budget and fall back (or show
  nothing) when it runs out: the LSP's `--full-rules` publish
  (DRagLint.LSP.Server.RunFullRulesLint) and the IDE plugin's live runner
  (DragLint.Plugin.LiveDiagnostics). Both used to carry their own 8000. A
  platform-library unit (an RTL/VCL file whose owning index is a
  `library-*.sqlite`) skips the flow, type-aware and project rules (LSP C11/C12)
  and still measured 7.8 s on a 100%-CPU box, so it gets twice the budget. One
  unit, compiled into both the engine and the plugin package, so the two can no
  longer drift. Pure: no I/O, no globals. Pinned by
  tests\autotest\fixtures\lintbudget\LintBudgetHarness.dpr
  (tests\autotest\run_plugin_library_timeout_guard.ps1).

  2. The per-rule, per-file runtime budget of the v151/v152 rule frame
  (PLAN 1.52 D9, lane BUDGET). The frame (DRagLint.V151.Dispatch) opens a
  budget for each file, wraps every lane call in RuleBudgetBeginCall /
  RuleBudgetEndCall, and every TV151FileCtx.Wants(<rule>) reports the rule the
  lane is about to compute through RuleBudgetEnter. Wall time between two such
  marks is charged to the rule last entered (time before the first Wants of a
  call is charged to the lane, key 'lane:<NAME>'). A rule whose time on the
  file passes the budget is SKIPPED for the rest of that file: Wants answers
  False for it, the frame drops its findings for the file, and the file gets
  one rule-skipped-budget note. A running rule is never interrupted (there is
  no safe pre-emption in-process): the skip takes effect when the rule hands
  control back. State is per thread (threadvar), so parallel lint-all workers
  do not share a clock; the run-wide summary is guarded by a lock.

  3. The near-parse-limit warning of the index walker (IsNearParseLimit).

  No unit of the lint engine is used here: the plugin package compiles this
  unit too. }

interface

const
  /// <summary>Budget for one lint child of a project (non-library) file, in ms.</summary>
  LINT_CHILD_TIMEOUT_MS = 8000;
  /// <summary>Budget for one lint child of a platform-library unit, in ms (2x the
  /// project budget; see the unit comment for the measurement).</summary>
  LINT_CHILD_LIBRARY_TIMEOUT_MS = 2 * LINT_CHILD_TIMEOUT_MS;

  /// <summary>Rule id of the note a file gets when a rule overran its budget there.</summary>
  RULE_SKIPPED_BUDGET_ID = 'rule-skipped-budget';
  /// <summary>Catalog title of RULE_SKIPPED_BUDGET_ID.</summary>
  RULE_SKIPPED_BUDGET_TITLE = 'A rule exceeded its per-file time budget and was skipped for this file';
  /// <summary>Prefix of the budget key that charges time spent in a lane call before
  /// the lane asked for any rule (key = prefix + lane name).</summary>
  RULE_BUDGET_LANE_PREFIX = 'lane:';
  /// <summary>Environment switch: any non-empty value other than '0' turns the budget
  /// off for the whole process (same effect as the CLI's --no-budget).</summary>
  ENV_RULE_BUDGET_OFF = 'DRAGLINT_NO_BUDGET';
  /// <summary>Test seam: '&lt;rule-id&gt;=&lt;ms&gt;' sleeps that long the first time a
  /// lane asks for the rule in a file (tests\autotest\run_v152_BUDGET.ps1).</summary>
  ENV_RULE_BUDGET_TEST_SLEEP = 'DRAGLINT_TEST_RULE_SLEEP_MS';
  /// <summary>A unit this close (percent) below the parse limit gets a warning at index time.</summary>
  PARSE_LIMIT_WARN_PERCENT = 10;

type
  /// <summary>One rule (or lane key) that overran the budget on one file.</summary>
  TRuleBudgetSkip = record
    /// <summary>Rule id, or RULE_BUDGET_LANE_PREFIX + lane name.</summary>
    RuleId   : string;
    /// <summary>Wall time charged to it on the file when the overrun was seen, in ms.</summary>
    ElapsedMs: Int64;
  end;

/// <summary>Tells whether an index path names a platform-library index.</summary>
/// <param name="pDbPath">Path (or bare file name) of a .sqlite index; may be ''.</param>
/// <returns>True when the file name starts with <c>library-</c>, case-insensitively
/// -- the same test the engine's lint gates (FlowIsLibrary) use.</returns>
/// <remarks>
/// Pure; thread-safe.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.Core.LintBudget.LintChildTimeoutMs (DRagLint.Core.LintBudget.pas)</para>
/// <para>Calls: ExtractFileName, LowerCase</para>
/// <para>Returns: LowerCase(ExtractFileName(pDbPath)).StartsWith('library-')</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function IsLibraryIndexPath(const pDbPath: string): Boolean;

/// <summary>Chooses the lint-child budget for a file from the index that OWNS it.</summary>
/// <param name="pOwningDbPath">The first index, in the order the child lint is given
/// them, that contains the file; '' when none does.</param>
/// <returns>LINT_CHILD_LIBRARY_TIMEOUT_MS for a library index, else
/// LINT_CHILD_TIMEOUT_MS (also for '').</returns>
/// <remarks>
/// Pure; thread-safe.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: [drag-lint]DRagLint.LSP.Server.TLSPServer.RunFullRulesLint (DRagLint.LSP.Server.pas), [dclDragLintWizard]DragLint.Plugin.LiveDiagnostics.TLintDiagnosticProvider.GetDiagnostics (DragLint.Plugin.LiveDiagnostics.pas)</para>
/// <para>Calls: DRagLint.Core.LintBudget.IsLibraryIndexPath</para>
/// <para>Returns: if IsLibraryIndexPath(pOwningDbPath) then LINT_CHILD_LIBRARY_TIMEOUT_MS</para>
/// <seealso cref="DRagLint.Core.LintBudget.IsLibraryIndexPath"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function LintChildTimeoutMs(const pOwningDbPath: string): Cardinal;

/// <summary>Turns the per-rule budget off (or back on) for the whole process.</summary>
/// <param name="pDisabled">True = no rule is ever skipped (the CLI's --no-budget).</param>
/// <remarks>Set once before linting starts; not meant to change while files are linted.</remarks>
procedure SetRuleBudgetDisabled(pDisabled: Boolean);

/// <summary>The budget that applies to a file, after the process-wide switches.</summary>
/// <param name="pConfigMs">The lint config's rule_time_budget_ms (0 = off).</param>
/// <returns>0 when SetRuleBudgetDisabled(True) was called, when ENV_RULE_BUDGET_OFF is set
/// to anything but '' or '0', or when pConfigMs &lt;= 0; else pConfigMs.</returns>
/// <remarks>Reads the environment on every call; thread-safe.</remarks>
function RuleBudgetEffectiveMs(pConfigMs: Integer): Integer;

/// <summary>Opens the budget of one file on the calling thread.</summary>
/// <param name="pBudgetMs">Per-rule budget in ms; 0 or less = off (no rule is skipped).</param>
/// <remarks>Discards a budget the thread left open. With the budget off and no test seam
/// in the environment no state is created, so every other call is a no-op that costs a
/// threadvar read. Pair with RuleBudgetEndFile in a try-finally.</remarks>
procedure RuleBudgetBeginFile(pBudgetMs: Integer);

/// <summary>Starts one lane call of the frame (charges time to 'lane:' + pLane until
/// the lane asks for a rule).</summary>
/// <param name="pLane">Lane name as the frame lists it.</param>
/// <returns>False when the lane key already overran on this file: the frame skips the call.</returns>
function RuleBudgetBeginCall(const pLane: string): Boolean;

/// <summary>Records that the running lane is about to compute pRuleId.</summary>
/// <param name="pRuleId">Rule id the lane asks for (TV151FileCtx.Wants).</param>
/// <returns>False when pRuleId already overran its budget on this file (the lane must not
/// compute it); True otherwise, and always True with no budget open.</returns>
/// <remarks>Closes the time slice of the rule entered before; applies the test seam.</remarks>
function RuleBudgetEnter(const pRuleId: string): Boolean;

/// <summary>Ends the lane call opened by RuleBudgetBeginCall and charges its last slice.</summary>
procedure RuleBudgetEndCall;

/// <summary>Has this rule (or lane key) overrun its budget on the current file?</summary>
/// <param name="pRuleId">Rule id, or RULE_BUDGET_LANE_PREFIX + lane name.</param>
/// <returns>True when skipped; False with no budget open.</returns>
function RuleBudgetIsSkipped(const pRuleId: string): Boolean;

/// <summary>Closes the file's budget, adds its skips to the run-wide summary and frees the state.</summary>
/// <returns>Every rule / lane key that overran on the file, in the order the overruns were seen;
/// nil when none did or no budget was open.</returns>
function RuleBudgetEndFile: TArray<TRuleBudgetSkip>;

/// <summary>Text of the one rule-skipped-budget note of a file.</summary>
/// <param name="pSkips">The file's skips (RuleBudgetEndFile); must not be empty.</param>
/// <param name="pBudgetMs">The budget that applied, in ms.</param>
/// <returns>One line naming every skipped rule with its time, the budget, and the way to change it.</returns>
function RuleBudgetNoteMessage(const pSkips: TArray<TRuleBudgetSkip>; pBudgetMs: Integer): string;

/// <summary>The run-wide summary of skipped rules (for lint-all's summary).</summary>
/// <returns>'' when no rule was skipped in this process since the last reset; else one line
/// 'rule budget: N skip(s) on M file(s): rule-a (k files), ...', rules sorted by id.</returns>
/// <remarks>Thread-safe.</remarks>
function RuleBudgetSummaryLine: string;

/// <summary>Clears the run-wide summary (a long-lived process between runs).</summary>
/// <remarks>Thread-safe.</remarks>
procedure RuleBudgetResetSummary;

/// <summary>Is a unit of this size within PARSE_LIMIT_WARN_PERCENT below the parse limit?</summary>
/// <param name="pSizeBytes">File size in bytes.</param>
/// <param name="pLimitKB">The index walker's parse limit in KB; 0 or less = unlimited.</param>
/// <returns>True when pLimitKB &gt; 0 and pSizeBytes is above 90 percent of the limit and
/// not above the limit itself (the walker skips those with its own line).</returns>
/// <remarks>Pure; thread-safe.</remarks>
function IsNearParseLimit(pSizeBytes: Int64; pLimitKB: Integer): Boolean;

/// <summary>The index walker's warning line for a unit near the parse limit.</summary>
/// <param name="pPath">The unit's path.</param>
/// <param name="pSizeBytes">Its size in bytes.</param>
/// <param name="pLimitKB">The parse limit in KB.</param>
/// <returns>'  WARN &lt;path&gt;: &lt;n&gt; KB is within 10% of the parse limit (&lt;limit&gt; KB) ...'.</returns>
/// <remarks>Pure; thread-safe.</remarks>
function ParseLimitWarning(const pPath: string; pSizeBytes: Int64; pLimitKB: Integer): string;

implementation

uses
  System.SysUtils
  , System.Classes
  , System.Diagnostics
  , System.SyncObjs
  , System.Generics.Collections
  , System.Generics.Defaults
  ;

const
  MS_PER_SECOND  = 1000;
  BYTES_PER_KB   = 1024;
  PERCENT_WHOLE  = 100;

type
  { The budget state of one file on one thread. }
  TRuleBudgetClock = class
  strict private
    FBudgetTicks: Int64;                       // 0 = off (only the test seam is live)
    FCurrent    : string;                      // key the running slice is charged to, '' = none
    FMark       : Int64;                       // TStopwatch timestamp the slice started at
    FSpent      : TDictionary<string, Int64>;  // key -> ticks charged on this file
    FSkipped    : TDictionary<string, Boolean>;
    FSkips      : TList<TRuleBudgetSkip>;
    FSleepRule  : string;
    FSleepMs    : Integer;
    FSlept      : Boolean;
    procedure CloseSlice;
  public
    constructor Create(pBudgetMs: Integer; const pSleepRule: string; pSleepMs: Integer);
    destructor Destroy; override;
    procedure Switch(const pKey: string);
    procedure EndCall;
    function IsSkipped(const pKey: string): Boolean;
    function SleepFor(const pRuleId: string): Integer;
    function Skips: TArray<TRuleBudgetSkip>;
  end;

threadvar
  GClock: TRuleBudgetClock;

var
  GDisabled    : Boolean;
  GSummaryLock : TCriticalSection;
  GSummaryRules: TDictionary<string, Integer>;  // rule -> files it was skipped on
  GSummaryFiles: Integer;
  GSummarySkips: Integer;

function IsLibraryIndexPath(const pDbPath: string): Boolean;
begin
  Result:= LowerCase(ExtractFileName(pDbPath)).StartsWith('library-');
end; // function

function LintChildTimeoutMs(const pOwningDbPath: string): Cardinal;
begin
  Result:= if IsLibraryIndexPath(pOwningDbPath) then LINT_CHILD_LIBRARY_TIMEOUT_MS else LINT_CHILD_TIMEOUT_MS;
end; // function

{ TRuleBudgetClock }

constructor TRuleBudgetClock.Create(pBudgetMs: Integer; const pSleepRule: string; pSleepMs: Integer);
begin
  inherited Create;
  FBudgetTicks:= if pBudgetMs > 0 then (Int64(pBudgetMs) * TStopwatch.Frequency) div MS_PER_SECOND else 0;
  FSpent  := TDictionary<string, Int64>.Create(TIStringComparer.Ordinal);
  FSkipped:= TDictionary<string, Boolean>.Create(TIStringComparer.Ordinal);
  FSkips  := TList<TRuleBudgetSkip>.Create;
  FSleepRule:= pSleepRule;
  FSleepMs  := pSleepMs;
end;

destructor TRuleBudgetClock.Destroy;
begin
  FSkips.Free;
  FSkipped.Free;
  FSpent.Free;
  inherited Destroy;
end;

procedure TRuleBudgetClock.CloseSlice;
var
  Total: Int64;
begin
  if FCurrent = '' then Exit;
  var Stamp: Int64:= TStopwatch.GetTimeStamp;
  if not FSpent.TryGetValue(FCurrent, Total) then Total:= 0;
  Total:= Total + (Stamp - FMark);
  FSpent.AddOrSetValue(FCurrent, Total);
  FMark:= Stamp;
  if (FBudgetTicks > 0) and (Total > FBudgetTicks) and not FSkipped.ContainsKey(FCurrent) then
  begin
    FSkipped.Add(FCurrent, True);
    var S: TRuleBudgetSkip;
    S.RuleId   := FCurrent;
    S.ElapsedMs:= (Total * MS_PER_SECOND) div TStopwatch.Frequency;
    FSkips.Add(S);
  end;
end;

procedure TRuleBudgetClock.Switch(const pKey: string);
begin
  if pKey = FCurrent then Exit;
  CloseSlice;
  FCurrent:= pKey;
  FMark   := TStopwatch.GetTimeStamp;
end;

procedure TRuleBudgetClock.EndCall;
begin
  CloseSlice;
  FCurrent:= '';
end;

function TRuleBudgetClock.IsSkipped(const pKey: string): Boolean;
begin
  Result:= FSkipped.ContainsKey(pKey);
end;

function TRuleBudgetClock.SleepFor(const pRuleId: string): Integer;
begin
  Result:= 0;
  if FSlept or (FSleepRule = '') or not SameText(pRuleId, FSleepRule) then Exit;
  FSlept:= True;
  Result:= FSleepMs;
end;

function TRuleBudgetClock.Skips: TArray<TRuleBudgetSkip>;
begin
  Result:= FSkips.ToArray;
end;

{ per-rule budget }

procedure SetRuleBudgetDisabled(pDisabled: Boolean);
begin
  GDisabled:= pDisabled;
end;

function RuleBudgetEffectiveMs(pConfigMs: Integer): Integer;
begin
  var Env: string:= Trim(GetEnvironmentVariable(ENV_RULE_BUDGET_OFF));
  if GDisabled or ((Env <> '') and (Env <> '0')) or (pConfigMs <= 0) then Exit(0);
  Result:= pConfigMs;
end;

{ Parses ENV_RULE_BUDGET_TEST_SLEEP ('<rule>=<ms>'); False when unset or malformed. }
function TestSleepSeam(out pRule: string; out pMs: Integer): Boolean;
begin
  pRule:= '';
  pMs  := 0;
  var Raw: string:= Trim(GetEnvironmentVariable(ENV_RULE_BUDGET_TEST_SLEEP));
  var Eq: Integer:= Pos('=', Raw);
  if Eq <= 1 then Exit(False);
  pRule:= Trim(Copy(Raw, 1, Eq - 1));
  pMs  := StrToIntDef(Trim(Copy(Raw, Eq + 1, MaxInt)), 0);
  Result:= pMs > 0;
end;

procedure RuleBudgetBeginFile(pBudgetMs: Integer);
var
  SleepRule: string;
  SleepMs  : Integer;
begin
  FreeAndNil(GClock);
  var Seam: Boolean:= TestSleepSeam(SleepRule, SleepMs);
  if (pBudgetMs <= 0) and not Seam then Exit;
  GClock:= TRuleBudgetClock.Create(pBudgetMs, SleepRule, SleepMs);
end;

function RuleBudgetBeginCall(const pLane: string): Boolean;
begin
  if GClock = nil then Exit(True);
  var Key: string:= RULE_BUDGET_LANE_PREFIX + pLane;
  if GClock.IsSkipped(Key) then Exit(False);
  GClock.Switch(Key);
  Result:= True;
end;

function RuleBudgetEnter(const pRuleId: string): Boolean;
begin
  if GClock = nil then Exit(True);
  GClock.Switch(pRuleId);
  var Ms: Integer:= GClock.SleepFor(pRuleId);
  if Ms > 0 then TThread.Sleep(Ms);
  Result:= not GClock.IsSkipped(pRuleId);
end;

procedure RuleBudgetEndCall;
begin
  if GClock <> nil then GClock.EndCall;
end;

function RuleBudgetIsSkipped(const pRuleId: string): Boolean;
begin
  Result:= (GClock <> nil) and GClock.IsSkipped(pRuleId);
end;

function RuleBudgetEndFile: TArray<TRuleBudgetSkip>;
begin
  Result:= nil;
  if GClock = nil then Exit;
  try
    GClock.EndCall;
    Result:= GClock.Skips;
  finally
    FreeAndNil(GClock);
  end;
  if Length(Result) = 0 then Exit;
  GSummaryLock.Enter;
  try
    Inc(GSummaryFiles);
    for var S: TRuleBudgetSkip in Result do
    begin
      var N: Integer;
      if not GSummaryRules.TryGetValue(S.RuleId, N) then N:= 0;
      GSummaryRules.AddOrSetValue(S.RuleId, N + 1);
      Inc(GSummarySkips);
    end;
  finally
    GSummaryLock.Leave;
  end;
end;

function RuleBudgetNoteMessage(const pSkips: TArray<TRuleBudgetSkip>; pBudgetMs: Integer): string;
begin
  var Parts: TArray<string>:= nil;
  for var S: TRuleBudgetSkip in pSkips do Parts:= Parts + [Format('%s (%d ms)', [S.RuleId, S.ElapsedMs])];
  Result:= Format('%s exceeded the per-rule time budget of %d ms on this file and %s skipped for it; ' +
    'raise rule_time_budget_ms in the lint config (0 = off) or run with --no-budget to get its findings',
    [string.Join(', ', Parts), pBudgetMs, if Length(pSkips) = 1 then 'was' else 'were']);
end;

function RuleBudgetSummaryLine: string;
begin
  GSummaryLock.Enter;
  try
    if GSummarySkips = 0 then Exit('');
    var Keys: TArray<string>:= GSummaryRules.Keys.ToArray;
    TArray.Sort<string>(Keys);
    var Parts: TArray<string>:= nil;
    for var K: string in Keys do Parts:= Parts + [Format('%s (%d file%s)', [K, GSummaryRules[K], if GSummaryRules[K] = 1 then '' else 's'])];
    Result:= Format('rule budget: %d skip(s) on %d file(s): %s', [GSummarySkips, GSummaryFiles, string.Join(', ', Parts)]);
  finally
    GSummaryLock.Leave;
  end;
end;

procedure RuleBudgetResetSummary;
begin
  GSummaryLock.Enter;
  try
    GSummaryRules.Clear;
    GSummaryFiles:= 0;
    GSummarySkips:= 0;
  finally
    GSummaryLock.Leave;
  end;
end;

{ parse limit }

function IsNearParseLimit(pSizeBytes: Int64; pLimitKB: Integer): Boolean;
begin
  if pLimitKB <= 0 then Exit(False);
  var Limit: Int64:= Int64(pLimitKB) * BYTES_PER_KB;
  Result:= (pSizeBytes <= Limit) and (pSizeBytes * PERCENT_WHOLE > Limit * (PERCENT_WHOLE - PARSE_LIMIT_WARN_PERCENT));
end;

function ParseLimitWarning(const pPath: string; pSizeBytes: Int64; pLimitKB: Integer): string;
begin
  Result:= Format('  WARN %s: %d KB is within %d%% of the parse limit (%d KB); a little more code and the unit is no longer indexed (settings.maxParseFileKB)',
    [pPath, pSizeBytes div BYTES_PER_KB, PARSE_LIMIT_WARN_PERCENT, pLimitKB]);
end;

initialization
  GSummaryLock := TCriticalSection.Create;
  GSummaryRules:= TDictionary<string, Integer>.Create(TIStringComparer.Ordinal);

finalization
  GSummaryRules.Free;
  GSummaryLock.Free;

end.
