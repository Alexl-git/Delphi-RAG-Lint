<#
  run_cyclefix_timeouts.ps1 -- E18 final review F1: every CALLER of a `cycles --fix --apply` waits
  longer than the engine's own limits allow one --apply to run, so an engine limit always fires
  first and the engine rolls back itself (a caller's kill bypasses the rollback).

  One --apply may legitimately take: the baseline build, the after build and its one repair
  rebuild ((1 + CSecondBuild) * CBuildTimeoutMs), then the child re-index and the child `cycles`
  (2 * CReindexTimeoutMs) -- src\cli\DRagLint.CLI.CycleFix.pas. This guard recomputes that sum
  from the engine's constants itself (it does not trust CApplyWorstMs) and checks:
    T1 the engine constants parse;
    T2 CAllIterationMs (the --part all child limit) is above the sum;
    T3 the plugin's CYCLE_FIX_TIMEOUT_MS (src\delphi-plugin\DragLint.Plugin.CycleFix.pas) is above it;
    T4 POSITIVE CONTROL: a limit equal to the sum is reported as NOT above it.
  Source only; needs no engine. -Root points at another source tree (the RED run used the
  038c6b75 sources, where both limits were below the sum).
#>
[CmdletBinding()]
param(
  [string]$Root = (Join-Path $PSScriptRoot '..\..')
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}

# Every `Name = <integer expression>;` constant of a unit, evaluated in source order; names of
# earlier constants are substituted. A right-hand side that is not integer arithmetic is skipped.
function Get-IntConsts([string]$Path) {
  $vals = @{}
  foreach ($l in [IO.File]::ReadAllLines($Path)) {
    if ($l -notmatch '^\s*([A-Za-z_]\w*)\s*=\s*([^;''{]+);') { continue }
    $name = $Matches[1]; $rhs = $Matches[2]
    foreach ($k in ($vals.Keys | Sort-Object Length -Descending)) { $rhs = [regex]::Replace($rhs, "\b$k\b", [string]$vals[$k]) }
    if ($rhs -notmatch '^[\d\s\+\*\(\)\-]+$') { continue }
    $vals[$name] = [long](New-Object System.Data.DataTable).Compute($rhs, '')
  }
  return $vals
}

function Test-Above([long]$Limit, [long]$Worst) { return $Limit -gt $Worst }

$engineSrc = Join-Path $Root 'src\cli\DRagLint.CLI.CycleFix.pas'
$pluginSrc = Join-Path $Root 'src\delphi-plugin\DragLint.Plugin.CycleFix.pas'
$e = Get-IntConsts $engineSrc
$p = Get-IntConsts $pluginSrc
$names = 'CBuildTimeoutMs', 'CReindexTimeoutMs', 'CSecondBuild', 'CAllIterationMs'
$parsed = @($names | Where-Object { -not $e.ContainsKey($_) }).Count -eq 0
Check 'T1 the engine constants parse' ($parsed -and $p.ContainsKey('CYCLE_FIX_TIMEOUT_MS')) ("missing: " + (($names | Where-Object { -not $e.ContainsKey($_) }) -join ', '))
if ($parsed -and $p.ContainsKey('CYCLE_FIX_TIMEOUT_MS')) {
  $worst = (1 + $e['CSecondBuild']) * $e['CBuildTimeoutMs'] + 2 * $e['CReindexTimeoutMs']
  Write-Host ("  one --apply may run {0} min (3 builds x {1} min + 2 x {2} min)" -f ($worst / 60000), ($e['CBuildTimeoutMs'] / 60000), ($e['CReindexTimeoutMs'] / 60000))
  Check 'T2 CAllIterationMs (--part all child limit) is above one --apply' (Test-Above $e['CAllIterationMs'] $worst) ("{0} min vs {1} min" -f ($e['CAllIterationMs'] / 60000), ($worst / 60000))
  Check 'T3 the plugin CYCLE_FIX_TIMEOUT_MS is above one --apply' (Test-Above $p['CYCLE_FIX_TIMEOUT_MS'] $worst) ("{0} min vs {1} min" -f ($p['CYCLE_FIX_TIMEOUT_MS'] / 60000), ($worst / 60000))
  Check 'T4 positive control: a limit equal to the worst case is NOT above it' (-not (Test-Above $worst $worst)) ''
}

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
