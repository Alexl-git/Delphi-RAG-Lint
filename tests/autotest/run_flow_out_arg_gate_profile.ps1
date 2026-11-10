<#
  run_flow_out_arg_gate_profile.ps1 -- lint-all must not pay for the OFF out-arg passes (wave 147 PF,
  E-LINTALL-SLOWER).

  THE DEFECT. 1.46 (lane 146 t1) added local-only-out-arg, dead-store-before-out-arg and
  by-value-arg-before-assignment, all OFF by default, but TFlowChecker ran their passes on every
  routine of every run. On the Micronite2027 copy the FlowChecker liveness window grew from 1.5 s to
  52 s and the replay window from 1.8 s to 13 s, and the final filter dropped every finding of those
  passes. The fix hands the checker RuleKeptByRun and skips a pass whose ids are not kept.

  The observable: under DRAGLINT_PROFILE the flow breakdown prints a `TOutAwareLiveness` solver row
  only when the second (out-aware) liveness solve ran.
    * default run          -> no TOutAwareLiveness solve (FAILS on the 1.46.0 engine: the solve runs)
    * --enable the two ids -> solve(s) > 0 and the rule still reports (positive control: a gate that
                              is always False, or a checker that never solves, fails here)
  run_flow_out_arg_rules.ps1 pins the findings themselves.

  Usage: pwsh -File tests\autotest\run_flow_out_arg_gate_profile.ps1 [-Exe <drag-lint.exe>] [-RulesDir <dir>]
#>
[CmdletBinding()]
param(
  [string]$Exe      = "$PSScriptRoot\..\..\src\cli\Win64\Debug\drag-lint.exe",
  [string]$RulesDir = "$PSScriptRoot\..\..\rules",
  [string]$WorkDir  = "C:\TEMP\draglint_flow_out_gate_$PID"
)
$ErrorActionPreference = 'Stop'; $script:fail = $false
function Check($n, $ok, $d) {
  Write-Host ("[{0}] {1}" -f (@('FAIL', 'PASS')[[int][bool]$ok]), $n)
  if (-not $ok) { if ($d) { Write-Host "      $d" }; $script:fail = $true }
}
function Write-Ascii($p, $t) { [IO.File]::WriteAllText($p, (($t -replace "`r`n", "`n") -replace "`n", "`r`n"), [Text.Encoding]::ASCII) }
function OutAwareSolves($text) {
  $m = [regex]::Match($text, 'TOutAwareLiveness\s+[\d.]+ s\s+\([^\r\n]*?(\d+) solve\(s\)\)')
  if ($m.Success) { return [int]$m.Groups[1].Value } else { return 0 }
}

$Unit = @"
unit uGateOut;
interface
type
  TGetter = class
  public
    procedure GetOut(out V: Integer);
  end;
procedure OnlyOut(G: TGetter);
procedure DeadBeforeOut(G: TGetter);
implementation
procedure TGetter.GetOut(out V: Integer); begin V := 1; end;
procedure OnlyOut(G: TGetter);
var
  tloX: Integer;
begin
  G.GetOut(tloX);
end;
procedure DeadBeforeOut(G: TGetter);
var
  tdsY: Integer;
begin
  tdsY := 5;
  G.GetOut(tdsY);
  if tdsY > 0 then G.GetOut(tdsY);
end;
end.
"@

try {
  $exePath = (Resolve-Path $Exe).Path
  $rules   = (Resolve-Path $RulesDir).Path
  if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
  $src = Join-Path $WorkDir 'src'
  [void](New-Item -ItemType Directory -Path $src -Force)
  Write-Ascii (Join-Path $src 'uGateOut.pas') $Unit
  $db = Join-Path $WorkDir 'gate.sqlite'
  & $exePath index $src --db $db 2>&1 | Out-Null
  Check 'index built' (Test-Path $db) $db

  $env:DRAGLINT_PROFILE = '1'
  try {
    $dflt = (& $exePath lint-all --output "$env:TEMP\dl-lintall-$PID.txt" --db $db --rules-dir $rules --library-db none 2>&1 | Out-String)
    $on   = (& $exePath lint-all --output "$env:TEMP\dl-lintall-$PID.txt" --db $db --rules-dir $rules --library-db none --enable 'local-only-out-arg,dead-store-before-out-arg' 2>&1 | Out-String)
  } finally { $env:DRAGLINT_PROFILE = $null }

  Check 'profile printed the flow breakdown (default run)' ($dflt -match 'FlowChecker\.Check breakdown') ''
  Check 'profile printed the flow breakdown (--enable run)' ($on -match 'FlowChecker\.Check breakdown') ''
  $s0 = OutAwareSolves $dflt; $s1 = OutAwareSolves $on
  Write-Host ("  out-aware solves: default={0} enabled={1}" -f $s0, $s1)
  Check 'GATE default run skips the out-aware liveness solve' ($s0 -eq 0) "TOutAwareLiveness solve(s) = $s0"
  Check 'CONTROL --enable runs the out-aware liveness solve' ($s1 -gt 0) "TOutAwareLiveness solve(s) = $s1"
  Check 'CONTROL --enable still reports local-only-out-arg' ($on -match 'local-only-out-arg') ''
  Check 'CONTROL default reports neither OFF rule' (($dflt -notmatch 'local-only-out-arg:') -and ($dflt -notmatch 'dead-store-before-out-arg:')) ''
}
catch { Write-Host "[FAIL] exception: $($_.Exception.Message)"; $script:fail = $true }
finally { if (Test-Path $WorkDir) { try { [IO.Directory]::Delete($WorkDir, $true) } catch { Write-Host "  (work dir left: $WorkDir)" } } }

if ($script:fail) { Write-Host 'run_flow_out_arg_gate_profile: FAIL'; exit 1 }
Write-Host 'run_flow_out_arg_gate_profile: PASS'; exit 0
