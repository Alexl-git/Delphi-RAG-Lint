unit DRagLint.CLI.RuleScope;

{ drag-lint 1.52 -- verbs `rules disable` / `rules enable` (ruling B4 part 3,
  PLAN section 5 D1: scope line | unit | project, a reason on every entry).
  Scaffold created by lane FRAME: DRagLint.CLI.pas parses the flags and calls
  RunRuleScope in ONE dispatch line; everything else lives here. Lane DISRULE
  owns this unit (its signature is the FRAME contract). }

interface

/// <summary>Runs `drag-lint rules disable|enable --rule &lt;id&gt; --scope line|unit|project
/// [--file F --line N] --reason "..." [--project P] [--config C] [--json]`.</summary>
/// <param name="pAction">'disable' or 'enable' (the positional after `rules`).</param>
/// <param name="pRuleId">--rule value.</param>
/// <param name="pScope">--scope value: 'line', 'unit' or 'project'; '' when absent.</param>
/// <param name="pFile">--file value (line and unit scope), '' when absent.</param>
/// <param name="pLine">--line value (line scope), 0 when absent.</param>
/// <param name="pReason">--reason value, '' when absent.</param>
/// <param name="pProject">--project value, '' when absent.</param>
/// <param name="pConfigPath">--config value (the project lint config to edit), '' when absent.</param>
/// <param name="pJson">--json (or --format json).</param>
/// <returns>Process exit code: 0 done, 1 nothing to do, 2 usage error.</returns>
/// <remarks>FRAME stub: prints `rules <action>: not implemented (1.52 scaffold)` on stderr and returns 2.</remarks>
function RunRuleScope(const pAction, pRuleId, pScope, pFile: string; pLine: Integer;
  const pReason, pProject, pConfigPath: string; pJson: Boolean): Integer;

implementation

uses
  System.SysUtils
  ;

function RunRuleScope(const pAction, pRuleId, pScope, pFile: string; pLine: Integer;  // dl:ok too-many-parameters@c2ad, unused-parameter@797f -- REVIEWED 2026-11-17 v152 FRAME: one positional per CLI flag keeps the CLI.pas dispatch a single line with no options builder there (FRAME contract, TT plan section 6 E1 shape); unused: the stub ignores its inputs, the owning lane's implementation reads every one
  const pReason, pProject, pConfigPath: string; pJson: Boolean): Integer;  // dl:ok unused-parameter@e510 -- REVIEWED 2026-11-17 v152 FRAME: FRAME verb-unit contract signature; the stub ignores its inputs, the owning lane's implementation reads every one
begin
  Writeln(ErrOutput, 'rules ' + pAction + ': not implemented (1.52 scaffold)');
  Result:= 2;
end;

end.
