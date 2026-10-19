<#
  run_follow_cycle_plan_selftest.ps1 -- tools\follow-cycle-plan.ps1 applied to the
  `cycles --plan` playbook of a COPY of circular-demo must produce exactly the
  `cycles` output the playbook predicted, INCLUDING the order of the groups.

  WHY (E18 Task 2, feasibility 2026-10-19): after Part A on the 3-cycle demo,
  `cycles` printed the groups [4],[2],[3] (Tarjan discovery order) while the
  predicted block printed [2],[3],[4]. A mechanical follower compares line by
  line, so the prediction must keep every group where DoCycles will print it.

  HOW. Copy circular-demo to a private scratch root, index it (--db inside the
  scratch), `cycles --plan` -> plan.txt, follow Cycle 1 (exit 0, 3 new files),
  re-index, `cycles` -> actual. The predicted block is the text between the
  `It must print exactly:` fence of Cycle 1. Both sides drop informational lines
  (`(loaded`, `drag-lint: note:`, `  resolver:`) and are compared line for line.
  Cycles 2 and 3 are refused by the planner: the follower must exit 2 with
  `REFUSE: plan has no mechanical steps`. No compiler involved.
  POSITIVE CONTROL: swapping two predicted group lines in memory must make the
  compare FAIL. Also: -Root applies the same plan to a second copy (DryRun, exit 0).
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-follow-plan-$PID"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  Write-Host ("  [{0}] {1} {2}" -f $(if ($ok) { 'PASS' } else { 'FAIL' }), $n, $d) -ForegroundColor $(if ($ok) { 'Green' } else { 'Red' })
  if (-not $ok) { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe  = (Resolve-Path $Exe).Path
$Repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Follow = Join-Path $Repo 'tools\follow-cycle-plan.ps1'

function Copy-Demo([string]$To) {
  New-Item -ItemType Directory -Force -Path $To | Out-Null
  foreach ($pat in '*.pas', '*.dpr', '*.dproj') { Copy-Item (Join-Path $Repo "circular-demo\$pat") $To -Force }
}
function Keep([string]$Text) {
  @($Text -split "\r?\n" | ForEach-Object { $_.TrimEnd() } |
    Where-Object { $_ -ne '' -and $_ -notmatch '^\(loaded|^drag-lint: note:|^\s+resolver:' })
}
function Run([string[]]$a, [string]$cwd) {
  $o = & $Exe @a 2>$null | Out-String
  return $o
}

New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
Push-Location $WorkDir
try {
  $S = Join-Path $WorkDir 'copy'; Copy-Demo $S
  $dproj = Join-Path $S 'CircularDemo.dproj'; $db = Join-Path $S 'demo.sqlite'
  & $Exe index --project $dproj --db $db *> $null
  Check 'index the copy' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"
  $plan = Join-Path $WorkDir 'plan.txt'
  [IO.File]::WriteAllText($plan, (Run @('cycles', '--db', $db, '--plan') $WorkDir), [Text.Encoding]::ASCII)

  # -Root: the same plan, applied to a second copy (dry run)
  $S2 = Join-Path $WorkDir 'copy2'; Copy-Demo $S2
  $dr = & pwsh -NoProfile -File $Follow -PlanFile $plan -Cycle 1 -Root $S2 -DryRun 2>&1 | Out-String
  Check '-Root -DryRun on a second copy exits 0' ($LASTEXITCODE -eq 0) $dr

  $out = & pwsh -NoProfile -File $Follow -PlanFile $plan -Cycle 1 2>&1 | Out-String
  Check 'Cycle 1 follows: exit 0' ($LASTEXITCODE -eq 0) $out
  Check 'Cycle 1 created 3 new files' (([regex]::Matches($out, '(?m)^created ')).Count -eq 3) $out

  foreach ($c in 2, 3) {
    $o = & pwsh -NoProfile -File $Follow -PlanFile $plan -Cycle $c 2>&1 | Out-String
    Check "Cycle $c is refused (exit 2)" ($LASTEXITCODE -eq 2) $o
    Check "Cycle $c says no mechanical steps" ($o -match 'REFUSE: plan has no mechanical steps') $o
  }

  & $Exe index --project $dproj --db $db *> $null
  $actual = Keep (Run @('cycles', '--db', $db) $WorkDir)

  $pt = [IO.File]::ReadAllText($plan)
  $m = [regex]::Match($pt, '(?s)## Cycle 1:.*?It must print exactly:\s*\r?\n```text\r?\n(.*?)\r?\n```')
  Check 'Cycle 1 has a predicted block' $m.Success
  $pred = if ($m.Success) { Keep $m.Groups[1].Value } else { @() }
  $same = ($pred.Count -gt 0) -and (($pred -join "`n") -ceq ($actual -join "`n"))
  Check 'predicted block == actual cycles output, group order included' $same ("`n  predicted:`n    " + ($pred -join "`n    ") + "`n  actual:`n    " + ($actual -join "`n    "))

  if ($pred.Count -ge 3) {
    $sw = @($pred); $t = $sw[1]; $sw[1] = $sw[2]; $sw[2] = $t
    Check 'POSITIVE CONTROL: swapped group lines no longer compare equal' (($sw -join "`n") -cne ($actual -join "`n"))
  }
} finally {
  Pop-Location
}
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0