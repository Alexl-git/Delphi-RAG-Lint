<#
  post_reindex_sequence.ps1 -- everything that was blocked on the 1.9.0-alpha
  reindex, run unattended the moment it finishes.

  Launch this DETACHED. It waits for the library walks to end, then does, in
  order, the things that could not be done while they held the machine and the
  engine binary:

    1. deploy the engine            -- blocked until now: stage-engine.ps1
                                       REFUSES to stage while an index run holds
                                       the exe (it once killed a 5-hour job)
    2. re-run the PROJECT sections  -- they completed BEFORE the enum-candidate
                                       resolve fix landed, so they do not have
                                       it; nothing else would ever tell us
    3. capture the AFTER baseline
    4. diff it against BEFORE       -- exit 1 there means a rule moved against
                                       prediction, i.e. an extractor defect
    5. full battery

  WHY IT WAITS ON PROCESS COUNT rather than a log marker: reindex-all.ps1 LAUNCHES
  detached workers and exits immediately, so its own log ends long before the work
  does. Two consecutive zero readings, after a floor, guard against the momentary
  gap between sections reading as "finished".

  Everything is logged; nothing here needs a human until the summary at the end.
#>
[CmdletBinding()]
param(
  [string]$Repo   = 'C:\Projects\Delphi-RAG-lint',
  [string]$OutDir = 'C:\TEMP\draglint-extractor-batch-2026-08-30',
  [int]   $MaxWaitMinutes = 360
)
$ErrorActionPreference = 'Continue'
$log = Join-Path $OutDir 'post-reindex.log'
function Say([string]$m) {
  $line = "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $m
  Write-Host $line
  Add-Content -Path $log -Value $line
}

Say '=== post-reindex sequence armed ==='

# --- 0. wait for the reindex ------------------------------------------------
$deadline = (Get-Date).AddMinutes($MaxWaitMinutes)
$zeros = 0
while ((Get-Date) -lt $deadline) {
  $n = @(Get-Process drag-lint -ErrorAction SilentlyContinue).Count
  if ($n -eq 0) { $zeros++ } else { $zeros = 0 }
  if ($zeros -ge 2) { break }
  Start-Sleep -Seconds 30
}
if ($zeros -lt 2) { Say "GAVE UP waiting after $MaxWaitMinutes min -- engine processes still running"; exit 1 }
Say 'reindex finished (two consecutive zero readings)'

# --- 1. deploy --------------------------------------------------------------
Say 'deploying the engine (staging was refused while the reindex held it)'
$bl = Join-Path $OutDir 'post-build.log'
$p = Start-Process cmd.exe -ArgumentList '/c', ('"' + (Join-Path $Repo 'build\build_draglint_win64.bat') + '"') `
       -RedirectStandardOutput $bl -RedirectStandardError "$bl.err" -NoNewWindow -Wait -PassThru
# dcc emits "error E2003:" / "Fatal F2613:" -- NOT "] Error". Matching the wrong
# shape once made a failed build report OK and cost a debugging round.
$err = Select-String -Path $bl -Pattern '(error E\d+|Fatal F\d+)'
if ($err) { Say "BUILD FAILED -- stopping: $($err[0].Line.Trim())"; exit 2 }
Say 'build + deploy OK'

$exe = Join-Path $Repo 'third_party\dll-win64\drag-lint.exe'

# --- 2. re-run the PROJECT sections ----------------------------------------
# They finished before the enum-candidate fix, so their call_edges are missing
# every enum-helper call. There is no fingerprint for resolve-pass staleness
# (docs/INBOX-resolve-pass-staleness-has-no-fingerprint.md), so this is manual
# by necessity, not by choice.
Say 're-running PROJECT sections so they carry the enum-candidate resolve fix'
$pl = Join-Path $OutDir 'post-projects.log'
& pwsh -NoProfile -File (Join-Path $Repo 'tools\reindex-all.ps1') -ProjectsOnly *> $pl
$zeros = 0
while ($zeros -lt 2) {
  $n = @(Get-Process drag-lint -ErrorAction SilentlyContinue).Count
  if ($n -eq 0) { $zeros++ } else { $zeros = 0 }
  Start-Sleep -Seconds 20
}
Say 'project sections re-indexed'

# --- 3. AFTER baseline ------------------------------------------------------
Say 'capturing the AFTER baseline'
& pwsh -NoProfile -File (Join-Path $Repo 'tools\measure\capture_rule_baseline.ps1') -Tag after *>> $log
$afterCsv = Join-Path $OutDir 'baseline\rule_counts_after.csv'
if (-not (Test-Path $afterCsv)) { Say 'AFTER capture produced no CSV -- stopping'; exit 3 }

# --- 4. the prediction diff -------------------------------------------------
Say 'diffing BEFORE vs AFTER against the predicted directions'
$cmp = Join-Path $OutDir 'compare.txt'
& python (Join-Path $Repo 'tools\measure\compare_rule_baseline.py') `
    (Join-Path $OutDir 'baseline\rule_counts_before.csv') $afterCsv *> $cmp
$cmpExit = $LASTEXITCODE
Get-Content $cmp | ForEach-Object { Add-Content -Path $log -Value "    $_" }
if ($cmpExit -ne 0) {
  Say 'PREDICTION DIFF FAILED -- a rule moved against prediction. See compare.txt.'
  Say 'Continuing to the battery anyway: the diff is evidence to read, not a reason to skip the tests.'
} else {
  Say 'prediction diff clean -- every movement matched'
}

# --- 5. full battery --------------------------------------------------------
Say 'running the full battery (~28 min, neutral cwd)'
$btl = Join-Path $OutDir 'post-battery.log'
Push-Location C:\TEMP
try { & pwsh -NoProfile -File (Join-Path $Repo 'tests\run_battery.ps1') *> $btl } finally { Pop-Location }
$summary = (Select-String -Path $btl -Pattern 'pass /.*fail' | Select-Object -Last 1)
if ($summary) { Say ("battery: " + $summary.Line.Trim()) } else { Say 'battery: no summary line found -- read post-battery.log' }
Select-String -Path $btl -Pattern '\.\.\. (FAIL|TIMEOUT)' | ForEach-Object { Say ("  " + $_.Line.Trim()) }

Say '=== post-reindex sequence COMPLETE ==='
Say "artifacts: $OutDir  (compare.txt, post-battery.log, baseline\)"
