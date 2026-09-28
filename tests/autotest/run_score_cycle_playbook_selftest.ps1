<#
  run_score_cycle_playbook_selftest.ps1 -- tools\score-cycle-playbook.ps1 still
  scores: an UNEDITED copy of circular-demo, scored against the plan the engine
  prints for it, must fail exactly the criteria an untouched tree fails.

  WHY. The scorer (CYC-4, 2026-09-28) is the repeatable end-to-end proof for
  the `cycles --plan` playbook: hand the report to a model, let it edit a copy,
  score the copy. A scorer that silently passed everything would turn every
  future model run into a false PASS, so its verdicts are pinned here on the
  one input whose answer is known without a model.

  EXPECTED on an unedited copy:
    1-CYCLE  FAIL  -- the tree still has the INTERFACE coupling the plan removes
    2-BUILD  PASS  -- the demo compiles as shipped
    3-CUT    FAIL  -- none of the three nominated *.Contracts units exists
    4-SCOPE  PASS  -- nothing changed, so nothing changed outside the report
  and an overall exit 1. The positive half (a model's edited tree scoring 4/4)
  needs a model and is recorded in
  docs\INBOX-test-cycle-playbook-followability-haiku-flash.md.

  Needs RAD Studio (msbuild via rsvars). Run from any CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "C:\TEMP\draglint_score_cycles_selftest_$PID"
)
try {
$ErrorActionPreference = 'Stop'
$script:fail = $false
function Check($n,$ok,$d){
  Write-Host ("[{0}] {1}" -f (@('FAIL','PASS')[[int][bool]$ok]),$n) -ForegroundColor (@('Red','Green')[[int][bool]$ok])
  if(-not $ok){ if($d){ Write-Host "      $d" -ForegroundColor DarkGray }; $script:fail=$true }
}
$rs = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'
if (-not (Test-Path $rs)) { Write-Host 'SKIP: RAD Studio not installed (rsvars.bat missing)'; exit 0 }
$exePath = (Resolve-Path $Exe).Path
$repo    = (Resolve-Path "$PSScriptRoot\..\..").Path
$scorer  = Join-Path $repo 'tools\score-cycle-playbook.ps1'
if (Test-Path $WorkDir) { [IO.Directory]::Delete($WorkDir, $true) }
foreach ($n in 'orig', 'edit') {
  $d = Join-Path $WorkDir "$n\circular-demo"
  New-Item -ItemType Directory -Path $d -Force | Out-Null
  Get-ChildItem (Join-Path $repo 'circular-demo') -File | Where-Object { $_.Name -ne 'CYCLE-REPORT.md' } |
    Copy-Item -Destination $d
}
$report = Join-Path $WorkDir 'report.txt'
Push-Location (Join-Path $WorkDir 'orig')
try {
  & $exePath index --project 'circular-demo\CircularDemo.dproj' --db (Join-Path $WorkDir 'rep.sqlite') 2>&1 | Out-Null
  & $exePath cycles --db (Join-Path $WorkDir 'rep.sqlite') --edges --causes --plan --format text 2>$null |
    Set-Content -LiteralPath $report -Encoding ascii
} finally { Pop-Location }
Check 'V the engine printed a plan with a checklist' ((Get-Content $report -Raw) -match 'It must print exactly:') $report

$raw = pwsh -NoProfile -File $scorer -Original (Join-Path $WorkDir 'orig\circular-demo') -Edited (Join-Path $WorkDir 'edit\circular-demo') `
         -Report $report -Project 'CircularDemo.dproj' -Exe $exePath -Json 2>$null | Out-String
$rc = $LASTEXITCODE
$j = $null
try { $j = $raw | ConvertFrom-Json } catch { $j = $null }
Check 'V the scorer emitted JSON' ($null -ne $j) $raw
Check "T0 overall verdict FAIL, exit 1 (got $rc)" (($rc -eq 1) -and ($null -ne $j) -and (-not $j.pass)) ''
Check 'T1 1-CYCLE FAILS on the untouched tree (interface coupling remains)' (($null -ne $j) -and (-not $j.'1-CYCLE'.pass)) $j.'1-CYCLE'.actual
Check 'T2 2-BUILD PASSES (the demo compiles as shipped)' (($null -ne $j) -and $j.'2-BUILD'.pass) (($j.'2-BUILD'.errors) -join ' | ')
Check 'T3 3-CUT FAILS and names all three missing units' (($null -ne $j) -and (-not $j.'3-CUT'.pass) -and (@($j.'3-CUT'.missing).Count -eq 3)) (($j.'3-CUT'.missing) -join ', ')
Check 'T4 4-SCOPE PASSES (nothing changed)' (($null -ne $j) -and $j.'4-SCOPE'.pass) ''

Write-Host ''
if ($script:fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
} finally {
  # D23: this run's scratch is $PID-suffixed; remove it so per-run folders do not pile up in TEMP.
  foreach ($d23 in @("C:\TEMP\draglint_score_cycles_selftest_$PID")) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
