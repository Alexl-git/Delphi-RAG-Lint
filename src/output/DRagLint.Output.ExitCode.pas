unit DRagLint.Output.ExitCode;

interface

uses
  System.SysUtils, DRagLint.Core.Model;

/// <summary>Computes a process exit code from the surviving findings and the
/// --fail-on policy.</summary>
/// <param name="AFindings">Final surviving findings.</param>
/// <param name="AFailOn">'' (use ADefaultCode), 'none' (always 0), or a severity
/// name; nonzero iff any finding's rank >= that name's rank.</param>
/// <param name="ADefaultCode">The command's pre-existing exit code, used when
/// AFailOn is '' (preserves today's behavior).</param>
/// <returns>0 or 1 per the policy, or ADefaultCode when AFailOn is ''.</returns>
/// <remarks>
/// Pure function; no state; thread-safe.
/// <!-- drag-lint:auto BEGIN -->
/// Called from: DRagLint.CLI.FinalizeAndOutput (DRagLint.CLI.pas)
/// Calls: DRagLint.Output.ExitCode.SeverityRank, SameText
/// Returns: 0
/// Pure
/// <seealso cref="DRagLint.Output.ExitCode.SeverityRank"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function ExitCodeFor(const AFindings: TArray<TLintFinding>; const AFailOn: string; ADefaultCode: Integer): Integer;

implementation

/// <summary>Numeric rank of a drag-lint severity for ordering/comparison.
/// error=3, warning=2, info=1, hint/unknown=0.</summary>
function SeverityRank(const ASeverity: string): Integer;
begin
  if SameText(ASeverity, 'error') then Result:= 3
  else if SameText(ASeverity, 'warning') then Result:= 2
  else if SameText(ASeverity, 'info') then Result:= 1
  else Result:= 0;
end;

function ExitCodeFor(const AFindings: TArray<TLintFinding>; const AFailOn: string; ADefaultCode: Integer): Integer;
var
  Threshold: Integer;
  F: TLintFinding;
begin
  if AFailOn = '' then Exit(ADefaultCode);
  if SameText(AFailOn, 'none') then Exit(0);
  Threshold:= SeverityRank(AFailOn);
  for F in AFindings do
    if SeverityRank(F.Severity) >= Threshold then Exit(1);
  Result:= 0;
end;

end.
