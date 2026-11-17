unit DRagLint.CLI.Explain;

{ drag-lint 1.52 -- verb `explain <rule-id>`: what a rule means, why it matters,
  bad / good example, default, fixable, how to suppress.
  Scaffold created by lane FRAME: DRagLint.CLI.pas parses the flags and calls
  RunExplain in ONE dispatch line; everything else lives here. Lane EXPLAIN
  owns this unit (its signature is the FRAME contract). }

interface

/// <summary>Runs `drag-lint explain &lt;rule-id&gt; [--json] [--rules-dir D]`.</summary>
/// <param name="pRuleId">The rule id (first positional after `explain`, or --rule), '' when absent.</param>
/// <param name="pRulesDir">--rules-dir value, '' = the engine's default rules folder.</param>
/// <param name="pJson">--json (or --format json).</param>
/// <returns>Process exit code: 0 known id, 2 unknown id or usage error.</returns>
/// <remarks>FRAME stub: prints `explain: not implemented (1.52 scaffold)` on stderr and returns 2.</remarks>
function RunExplain(const pRuleId, pRulesDir: string; pJson: Boolean): Integer;

implementation

uses
  System.SysUtils
  ;

function RunExplain(const pRuleId, pRulesDir: string; pJson: Boolean): Integer;  // dl:ok unused-parameter@59ed -- REVIEWED 2026-11-17 v152 FRAME: FRAME verb-unit contract signature; the stub ignores its inputs, the owning lane's implementation reads every one
begin
  Writeln(ErrOutput, 'explain: not implemented (1.52 scaffold)');
  Result:= 2;
end;

end.
