<#
  post_reindex_sequence.ps1 -- everything that was blocked on the 1.9.0-alpha
  reindex, run unattended the moment it finishes.

  Launch this DETACHED. It waits for the library walks to end, then does, in
  order, the things that could not be done while they held the machine and the
  engine binary:

    0b. PRESERVE the deployed engine -- see the confound note below
    1. deploy the engine            -- blocked until now: stage-engine.ps1
                                       REFUSES to stage while an index run holds
                                       the exe (it once killed a 5-hour job)
    2. re-run the PROJECT sections  -- they completed BEFORE the enum-candidate
                                       resolve fix landed, so they do not have
                                       it; nothing else would ever tell us
    3a. capture MID  -- OLD engine, NEW indexes
    3b. capture AFTER -- NEW engine, NEW indexes
    4. two diffs                    -- BEFORE->MID is the INDEX effect,
                                       MID->AFTER is the ENGINE effect
    5. full battery

  THE CONFOUND THIS EXISTS TO REMOVE (found 2026-08-31, in the 2026-08-30 run's
  own output). Step 1 REPLACES the engine, and the AFTER capture then used the
  new one while BEFORE had used the old. So compare.txt varied TWO things at
  once and could not answer the question it was built for -- 'what did the
  reindex change?'. It was not a subtle confound either: `parser-error` moved
  21 -> 0 and `syntax-error` 3 -> 0 on both corpora, and BOTH are computed at
  LINT time from the source file, so no index change can move them. That is
  proof, not inference.

  The obvious fix -- build AFTER step 3 -- does NOT work, and it is worth
  saying why so nobody 'simplifies' back to it: step 2 re-indexes precisely so
  the project sections carry the NEW engine's resolve fix. Deferring the build
  would defeat the reason step 2 exists.

  So the old engine is COPIED ASIDE first and used for a third reading. Both
  effects are then isolated, and each diff varies exactly one thing.

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

# --- 0b. preserve the OLD engine -------------------------------------------
# The WHOLE directory, not just the exe: the engine needs its tree-sitter DLLs,
# drag-lint.json and rules\ beside it, and every path in that manifest is
# absolute, so a relocated copy resolves to exactly the same databases. This is
# the same private-copy trick the VS Code extension uses to stop the running
# server holding the file being staged.
$deployed = Join-Path $Repo 'third_party\dll-win64'
$oldEngineDir = Join-Path $OutDir 'engine-before'
$oldExe = Join-Path $oldEngineDir 'drag-lint.exe'
if (Test-Path (Join-Path $deployed 'drag-lint.exe')) {
  Say 'preserving the CURRENTLY deployed engine for the MID reading'
  if (Test-Path $oldEngineDir) { Remove-Item -Recurse -Force $oldEngineDir }
  Copy-Item -Path $deployed -Destination $oldEngineDir -Recurse -Force
  $v = (& $oldExe --version 2>&1 | Out-String).Trim()
  Say "preserved engine reports: $v"
} else {
  Say 'NO deployed engine to preserve -- the MID reading will be SKIPPED and'
  Say 'before/after will carry the engine confound. Say so in the summary.'
  $oldExe = ''
}

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

# --- 3a. MID baseline: OLD engine, NEW indexes ------------------------------
# This is the reading that answers the actual question. Taken FIRST, while the
# preserved copy is known good.
$midCsv = Join-Path $OutDir 'baseline\rule_counts_mid.csv'
if ($oldExe -ne '') {
  Say 'capturing the MID baseline (OLD engine against the NEW indexes)'
  & pwsh -NoProfile -File (Join-Path $Repo 'tools\measure\capture_rule_baseline.ps1') `
      -Tag mid -Exe $oldExe *>> $log
  if (-not (Test-Path $midCsv)) {
    Say 'MID capture produced no CSV -- the index effect cannot be isolated this run'
    $midCsv = ''
  }
} else { $midCsv = '' }

# --- 3b. AFTER baseline: NEW engine, NEW indexes ----------------------------
Say 'capturing the AFTER baseline'
& pwsh -NoProfile -File (Join-Path $Repo 'tools\measure\capture_rule_baseline.ps1') -Tag after *>> $log
$afterCsv = Join-Path $OutDir 'baseline\rule_counts_after.csv'
if (-not (Test-Path $afterCsv)) { Say 'AFTER capture produced no CSV -- stopping'; exit 3 }

# --- 4. the diffs -----------------------------------------------------------
# TWO of them, each varying ONE thing. compare.txt keeps its name and its
# meaning as the headline artefact, but it is now the INDEX diff -- which is
# what everyone reading it always believed it was.
$beforeCsv = Join-Path $OutDir 'baseline\rule_counts_before.csv'
$cmp = Join-Path $OutDir 'compare.txt'
if ($midCsv -ne '') {
  Say 'diffing BEFORE vs MID -- the INDEX effect, engine held constant'
  & python (Join-Path $Repo 'tools\measure\compare_rule_baseline.py') `
      $beforeCsv $midCsv *> $cmp
  $cmpExitIndex = $LASTEXITCODE
  $cmpEngine = Join-Path $OutDir 'compare-engine.txt'
  Say 'diffing MID vs AFTER -- the ENGINE effect, indexes held constant'
  & python (Join-Path $Repo 'tools\measure\compare_rule_baseline.py') `
      $midCsv $afterCsv *> $cmpEngine
  Get-Content $cmpEngine | ForEach-Object { Add-Content -Path $log -Value "  [engine] $_" }
} else {
  Say 'NO MID reading -- falling back to BEFORE vs AFTER, which CONFOUNDS index'
  Say 'and engine changes. Read compare.txt with that caveat.'
  & python (Join-Path $Repo 'tools\measure\compare_rule_baseline.py') `
      $beforeCsv $afterCsv *> $cmp
  $cmpExitIndex = $LASTEXITCODE
}
$cmpExit = $cmpExitIndex
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
Say "artifacts: $OutDir  (compare.txt = INDEX effect, compare-engine.txt = ENGINE"
Say "           effect, post-battery.log, baseline\, engine-before\)"
