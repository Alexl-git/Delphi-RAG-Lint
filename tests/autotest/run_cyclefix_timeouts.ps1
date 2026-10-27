<#
  run_cyclefix_timeouts.ps1 -- the time limits of `cycles --fix`, after the owner ruling of
  2026-10-26 (lane X-BT): NO timeout for IDE runs. The IDE shows progress and has Cancel, and a slow
  machine must not abort a result the user waits for. Stopping a run is Cancel's job, and Cancel
  never hard-kills the engine mid-apply: it asks the engine to stand down (the maintenance control
  channel), the engine rolls back and exits 1, and only after a grace is the tree killed.

  (Before the ruling this guard pinned the opposite inequality -- E18 final review F1: the plugin's
  130-minute limit above the engine's 120-minute worst case, so the engine's own limit fired first.
  With neither side bounded by default that question is gone; the remaining ordering is the cancel
  grace, T5.)

    T1 the constants parse (engine: CDefaultBuildTimeoutS, CSecondBuild, CReindexTimeoutMs,
       CReindexSteps, CKillMarginMs, CChildStandDownMs; plugin: CYCLE_FIX_TIMEOUT_MS,
       CYCLE_FIX_CANCEL_GRACE_MS);
    T2 the engine's default build limit is 0 = none (--build-timeout sets one);
    T3 the plugin's CYCLE_FIX_TIMEOUT_MS is 0 = none;
    T4 ProcRun reads a limit <= 0 as "no deadline" (else T3 would mean "kill at once");
    T5 the plugin's cancel grace is ABOVE the engine's CChildStandDownMs -- a --part all parent gives
       its child that long to roll back, so a forwarded stand-down finishes before the IDE kills;
       T5b POSITIVE CONTROL: an equal grace is reported as not above;
    T6 every IDE cycle-fix job sets Job.CancelGraceMs := CYCLE_FIX_CANCEL_GRACE_MS (3: the tab's
       Dry run / Apply, the Structure tree's two), so Cancel stands the engine down instead of
       killing it;
    T7 a whole-apply child's limit (ChildApplyLimitMs) is derived from --build-timeout: three builds,
       CReindexSteps re-index steps and CKillMarginMs -- and INFINITE when the builds are unbounded.
  Source only; needs no engine. -Root points at another source tree (the RED run used the pre-lane
  sources of 1b7a70d3: T1-T3 and T5-T7 fail there).
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
function Test-Above([long]$Limit, [long]$Other) { return $Limit -gt $Other }
function Src([string]$Rel) { $p = Join-Path $Root $Rel; if (Test-Path $p) { return [IO.File]::ReadAllText($p) } return '' }

$engineSrc = Join-Path $Root 'src\cli\DRagLint.CLI.CycleFix.pas'
$pluginSrc = Join-Path $Root 'src\delphi-plugin\DragLint.Plugin.CycleFix.pas'
$e = Get-IntConsts $engineSrc
$p = Get-IntConsts $pluginSrc
$eNames = 'CDefaultBuildTimeoutS', 'CSecondBuild', 'CReindexTimeoutMs', 'CReindexSteps', 'CKillMarginMs', 'CChildStandDownMs'
$pNames = 'CYCLE_FIX_TIMEOUT_MS', 'CYCLE_FIX_CANCEL_GRACE_MS'
$missing = @($eNames | Where-Object { -not $e.ContainsKey($_) }) + @($pNames | Where-Object { -not $p.ContainsKey($_) })
Check 'T1 the engine and plugin constants parse' ($missing.Count -eq 0) ("missing: " + ($missing -join ', '))
Check 'T2 the engine''s default build limit is 0 (none)' ($e.ContainsKey('CDefaultBuildTimeoutS') -and $e['CDefaultBuildTimeoutS'] -eq 0) ("got: " + $e['CDefaultBuildTimeoutS'])
Check 'T3 the plugin CYCLE_FIX_TIMEOUT_MS is 0 (none)' ($p.ContainsKey('CYCLE_FIX_TIMEOUT_MS') -and $p['CYCLE_FIX_TIMEOUT_MS'] -eq 0) ("got: " + $p['CYCLE_FIX_TIMEOUT_MS'])
$procRun = Src 'src\delphi-plugin\DragLint.Plugin.ProcRun.pas'
Check 'T4 ProcRun reads a limit <= 0 as no deadline' ($procRun -match 'Deadline:=\s*if ATimeoutMs > 0 then GetTickCount64 \+ UInt64\(ATimeoutMs\) else High\(UInt64\);') ''
if ($e.ContainsKey('CChildStandDownMs') -and $p.ContainsKey('CYCLE_FIX_CANCEL_GRACE_MS')) {
  Check 'T5 the plugin cancel grace is above the engine''s CChildStandDownMs' (Test-Above $p['CYCLE_FIX_CANCEL_GRACE_MS'] $e['CChildStandDownMs']) ("{0} s vs {1} s" -f ($p['CYCLE_FIX_CANCEL_GRACE_MS'] / 1000), ($e['CChildStandDownMs'] / 1000))
} else { Check 'T5 the plugin cancel grace is above the engine''s CChildStandDownMs' $false 'constants missing' }
Check 'T5b positive control: an equal grace is NOT above' (-not (Test-Above 60000 60000)) ''
$jobs = (Src 'src\delphi-plugin\DragLint.Plugin.UsesDepsFrame.pas') + (Src 'src\delphi-plugin\DragLint.Plugin.StructureForm.pas')
$graceSites = [regex]::Matches($jobs, 'Job\.CancelGraceMs\s*:=\s*CYCLE_FIX_CANCEL_GRACE_MS\s*;').Count
$limitSites = [regex]::Matches($jobs, 'Job\.TimeoutMs\s*:=\s*CYCLE_FIX_TIMEOUT_MS\s*;').Count
Check 'T6 every IDE cycle-fix job takes a graceful Cancel (3 of 3)' (($graceSites -eq 3) -and ($limitSites -eq 3)) "CancelGraceMs sites=$graceSites, TimeoutMs sites=$limitSites"
$m = [regex]::Match((Src 'src\cli\DRagLint.CLI.CycleFix.pas'), '(?s)function ChildApplyLimitMs: Cardinal;\s*begin(.*?)\bend;')
$body = if ($m.Success) { $m.Groups[1].Value } else { '' }
Check 'T7 ChildApplyLimitMs: INFINITE when unbounded, else 3 builds + CReindexSteps + CKillMarginMs' (
  ($body -match 'GBuildTimeoutMs = INFINITE then Exit\(INFINITE\)') -and ($body -match '\(1 \+ CSecondBuild\) \* GBuildTimeoutMs') -and
  ($body -match 'CReindexSteps\) \* CReindexTimeoutMs') -and ($body -match 'CKillMarginMs')) $body

if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
