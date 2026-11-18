<#
  run_check_init_memberwrite.ps1 -- INT H-F1 (1.52): a target written ONLY through a member access
  (`TCounter.Hits := 3` class var via class name, `mwData.GUnitQ := 4` unit-qualified global) is a
  WRITER in DRagLint.Query.HappensBefore.Events, never a use, so check-init never answers NEVER-SET
  for it. Fixture tests\fixtures\happens-before\events-memberwrite.

  Positive control: GNever (read, never written) still answers NEVER-SET with no writers, so the
  NEVER-SET path is alive and the negative assertions are not vacuous.

  Usage: pwsh -File tests\autotest\run_check_init_memberwrite.ps1 [-Exe <drag-lint.exe>]
  Exit 0 = PASS, 1 = FAIL.
#>
param([string]$Exe = "third_party\dll-win64\drag-lint.exe")
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
Set-Location $repo
$exePath = (Resolve-Path $Exe).Path
$work = Join-Path C:\TEMP "draglint_hbmw_$PID"
[void](New-Item -ItemType Directory -Force -Path $work)
$script:pass = 0
$script:fail = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  if ($Ok) { $script:pass++ } else { $script:fail++ }
  Write-Host ("[{0}] {1}{2}" -f $(if ($Ok) { 'PASS' } else { 'FAIL' }), $Name, $(if ($Detail -and -not $Ok) { "  ($Detail)" } else { '' }))
}

Copy-Item (Join-Path $repo 'tests\fixtures\happens-before\events-memberwrite\*') $work -Force
$db = Join-Path $work 'mw.sqlite'
& $exePath index $work --db $db 2>&1 | Out-Null
Check 'fixture indexed' (Test-Path $db)

function Answer([string]$Target) {
  $raw = & $exePath check-init $Target --db $db --json 2>$null
  return (($raw | Out-String) | ConvertFrom-Json)
}
function HasSiteLine($Rows, [int]$Line) { return @($Rows | Where-Object { $_.file -like '*mwData.pas' -and $_.line -eq $Line }).Count -gt 0 }

foreach ($case in @(@('TCounter.Hits', 25), @('GUnitQ', 26))) {
  $t = $case[0]; $ln = $case[1]
  $a = Answer $t
  Check "$t has a writer at mwData.pas:$ln" (HasSiteLine $a.writers $ln) ("writers=" + (@($a.writers | ForEach-Object { "$($_.line):$($_.how)" }) -join ','))
  Check "$t member write is not a use" (-not (HasSiteLine $a.uses $ln))
  Check "$t is not NEVER-SET" ($a.verdict -ne 'NEVER-SET') "verdict=$($a.verdict)"
  Write-Host "  $t verdict=$($a.verdict)"
}

$n = Answer 'GNever'
Check 'control: GNever answers NEVER-SET' ($n.verdict -eq 'NEVER-SET') "verdict=$($n.verdict)"
Check 'control: GNever has no writers' (@($n.writers).Count -eq 0)
Check 'control: GNever has its use' (@($n.uses).Count -ge 1)

Write-Host ("RESULT: {0} passed, {1} failed" -f $script:pass, $script:fail)
exit ([int]($script:fail -gt 0))
