<#
  run_index_all_jobs_spawns_workers.ps1 -- `index --all --jobs N` must actually
  spawn N workers, and a parallel run must do the SAME WORK as a sequential one.

  THE DEFECT (docs\INBOX-index-all-jobs-is-silently-ignored.md)
  ------------------------------------------------------------
  The parallel path refused to run without an explicit `--config` and quietly
  downgraded itself:

      NOTE: --jobs >1 requires --config <path>; running sequentially.

  The stated reason was that the child needs "a deterministic config path". The
  premise was wrong twice: the command has already resolved the manifest by
  that line WITHOUT --config, and a single path could not express what it
  resolved anyway, because TManifestIO.Load MERGES <engine>\drag-lint.json with
  the nearest .drag-lint.json above the CWD. The child inherits both inputs
  (ParamStr(0) for the engine dir, lpCurrentDirectory = nil for the CWD), so
  rediscovery is the faithful option, not a fallback.

  WHAT IT COST: three documents -- including C:\Projects\CLAUDE.md -- teach the
  bare `index --all --jobs 0` as the way to build every index, so the mandatory
  post-extractor-bump reindex ran single-threaded for 28 minutes before the
  note was noticed. It had scrolled away by line 4, and a single-threaded run
  looks perfectly healthy: 0 errors, continuous progress.

  THE SECOND DEFECT, found by reading the child command line against the
  sequential call it is supposed to mirror: --resolve-only, --force-reparse and
  --max-file-kb were never forwarded. --resolve-only is the dangerous one -- a
  child without it performs a FULL INDEX instead of a resolve pass, rewriting
  every stored parse on a run whose entire point was not to touch them, and
  reporting success. This suite pins it by contrast (see part C).

  WHY THE ASSERTION IS A PROCESS COUNT AND NOT THE ABSENCE OF THE NOTE
  --------------------------------------------------------------------
  "The note is gone" would pass if the note were merely deleted while the run
  stayed sequential -- which is the exact shape of the bug being fixed. So this
  suite SAMPLES the live process table while the run is in flight and counts
  concurrent engines, filtering on the probe's own section names so the IDE's
  resident `drag-lint lsp --stdio` servers cannot be mistaken for workers.

  POSITIVE CONTROLS -- the instrument must be able to say NO
  ---------------------------------------------------------
  A sampler that always reports ">1" would pass part A vacuously, so the same
  measurement is taken on `--jobs 1`, which must report EXACTLY 1 (the parent
  alone) and must NOT print the parallel summary line. And parallelism that
  produced a different index would be worse than the bug, so the parallel DBs
  are compared row-for-row against the sequential ones.

  SAFETY: the CWD holds the probe manifest, and Load MERGES the engine's real
  33-section manifest into it. Every run is therefore restricted with --only,
  and a dry-run asserts the plan is EXACTLY the three probe sections before
  anything is built -- without that, a regression in --only would index the
  whole machine from inside a test.

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-jobs-probe",
  [int]   $Units   = 250
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
$Exe = (Resolve-Path $Exe).Path
$SECTIONS = @('JobsProbeA','JobsProbeB','JobsProbeC')
$ONLY     = $SECTIONS -join ','

# ------------------------------------------------------------------ fixture --
# Rebuilt only when absent or the wrong size: the units are inert and indexing
# 750 of them is the only slow part of this suite.
$needBuild = -not (Test-Path (Join-Path $WorkDir '.drag-lint.json'))
if (-not $needBuild) {
  foreach ($s in $SECTIONS) {
    $d = Join-Path $WorkDir $s
    if ((-not (Test-Path $d)) -or (@(Get-ChildItem -LiteralPath $d -Filter '*.pas' -File).Count -ne $Units)) { $needBuild = $true }
  }
}
if ($needBuild) {
  New-Item -ItemType Directory -Force $WorkDir | Out-Null
  foreach ($s in $SECTIONS) {
    $d = Join-Path $WorkDir $s
    if (Test-Path $d) { foreach ($old in (Get-ChildItem -LiteralPath $d -File)) { [System.IO.File]::Delete($old.FullName) } }
    New-Item -ItemType Directory -Force $d | Out-Null
    for ($i = 1; $i -le $Units; $i++) {
      $u = "u$s$i"
      $t = "unit $u;`n`ninterface`n`ntype`n  T$u = class`n  public`n    function Calc(const A, B: Integer): Integer;`n    procedure Walk;`n  end;`n`nimplementation`n`nfunction T$u.Calc(const A, B: Integer): Integer;`nbegin`n  Result := A * B + $i;`nend;`n`nprocedure T$u.Walk;`nvar`n  K: Integer;`nbegin`n  for K := 0 to 10 do`n    if Calc(K, $i) > 0 then`n      Continue;`nend;`n`nend.`n"
      $norm = $t -replace "`r`n", "`n" -replace "`n", "`r`n"
      [System.IO.File]::WriteAllText((Join-Path $d "$u.pas"), $norm, [System.Text.Encoding]::ASCII)
    }
  }
  $cfg = [ordered]@{ indexes = [ordered]@{ outDir = '.'; sections = @($SECTIONS | ForEach-Object { [ordered]@{ name = $_; include = @(".\$_") } }) } }
  [System.IO.File]::WriteAllText((Join-Path $WorkDir '.drag-lint.json'), ($cfg | ConvertTo-Json -Depth 8), [System.Text.Encoding]::ASCII)
}
$cfgPath = Join-Path $WorkDir '.drag-lint.json'

function Remove-Dbs { foreach ($s in $SECTIONS) { $p = Join-Path $WorkDir "$s.sqlite"; if (Test-Path $p) { [System.IO.File]::Delete($p) } } }
function Table-Counts([string]$Section) {
  $t = (& $Exe schema --db (Join-Path $WorkDir "$Section.sqlite") 2>&1 | Out-String)
  $o = @()
  foreach ($k in 'files','symbols','refs') {
    if ($t -match "(?m)^\s*$k \((\d+) rows\)") { $o += "$k=$($Matches[1])" } else { $o += "$k=?" }
  }
  return ($o -join ' ')
}
function File-Count([string]$Section) {
  $t = (& $Exe schema --db (Join-Path $WorkDir "$Section.sqlite") 2>&1 | Out-String)
  if ($t -match "(?m)^\s*files \((\d+) rows\)") { return [int]$Matches[1] }
  return -1
}

# Runs the engine from the fixture dir (so discovery finds .drag-lint.json) and
# samples concurrent engines belonging to THIS probe while it is in flight.
function Probe-Run([string]$Label, [string[]]$ExtraArgs) {
  Push-Location $WorkDir
  try {
    $argv = @('index','--all','--only',$ONLY) + $ExtraArgs
    $out  = Join-Path $WorkDir "$Label.out"
    $proc = Start-Process $Exe -ArgumentList $argv -NoNewWindow -PassThru `
              -RedirectStandardOutput $out -RedirectStandardError "$out.err"
    $max = 0
    while (-not $proc.HasExited) {
      $n = @(Get-CimInstance Win32_Process -Filter "Name='drag-lint.exe'" |
             Where-Object { $_.CommandLine -like '*JobsProbe*' }).Count
      if ($n -gt $max) { $max = $n }
      Start-Sleep -Milliseconds 50
    }
    $proc.WaitForExit()
    $so = if (Test-Path $out)       { Get-Content $out -Raw }       else { '' }
    $se = if (Test-Path "$out.err") { Get-Content "$out.err" -Raw } else { '' }
    return [pscustomobject]@{ Exit = $proc.ExitCode; MaxProcs = $max; Out = "$so`n$se" }
  } finally { Pop-Location }
}

# ---------------------------------------------------- SAFETY: scope the plan --
Write-Host ''
Write-Host 'SAFETY -- the plan must be exactly the three probe sections' -ForegroundColor Cyan
Push-Location $WorkDir
$dry = (& $Exe index --all --only $ONLY --dry-run 2>&1 | Out-String)
Pop-Location
$planned = @([regex]::Matches($dry, '(?m)^\s{4}\[([^\]]+)\]')) | ForEach-Object { $_.Groups[1].Value }
Check 'dry-run plans exactly 3 sections' ($planned.Count -eq 3) "planned: $($planned -join ', ')"
Check 'and they are the probe sections only' (
  (@($planned | Where-Object { $_ -notlike 'JobsProbe*' }).Count -eq 0)) "planned: $($planned -join ', ')"
if ($script:Failed) {
  Write-Host 'ABORTING before any build -- --only did not scope the plan.' -ForegroundColor Red
  exit 1
}

# ------------------------------------------------- B. the sequential control --
Write-Host ''
Write-Host 'POSITIVE CONTROL -- --jobs 1 must measure as EXACTLY one process' -ForegroundColor Cyan
Remove-Dbs
$seq = Probe-Run 'jobs1' @('--jobs','1')
Check 'sequential run succeeded' ($seq.Exit -eq 0) "exit=$($seq.Exit)"
Check 'exactly 1 concurrent engine' ($seq.MaxProcs -eq 1) "max=$($seq.MaxProcs) -- if this is >1 the sampler cannot discriminate and part A proves nothing"
Check 'no parallel summary line' (-not ($seq.Out -match 'parallel build:'))
$seqCounts = @{}
foreach ($s in $SECTIONS) { $seqCounts[$s] = Table-Counts $s }
Write-Host ("  sequential: " + (($SECTIONS | ForEach-Object { "$_ [$($seqCounts[$_])]" }) -join '  ')) -ForegroundColor DarkGray
Check 'the sequential run actually indexed something' (
  (@($SECTIONS | Where-Object { $seqCounts[$_] -notmatch 'files=0' }).Count -eq 3)) "a fixture that indexes nothing would make every comparison below vacuous"

# ------------------------------------------------------------- A. the defect --
Write-Host ''
Write-Host 'THE DEFECT -- --jobs N with NO --config must spawn workers' -ForegroundColor Cyan
Remove-Dbs
$par = Probe-Run 'jobs3-noconfig' @('--jobs','3')
Check 'parallel run succeeded' ($par.Exit -eq 0) "exit=$($par.Exit)"
Check 'more than one concurrent engine' ($par.MaxProcs -gt 1) "max=$($par.MaxProcs) (parent + workers)"
Check 'no self-downgrade note' (-not ($par.Out -match 'requires --config')) `
  'the run must not demand a path it has already resolved'
Check 'the parallel summary reports jobs=3' ($par.Out -match 'parallel build: 3/3 sections OK \(jobs=3\)') `
  'asserted separately from the process count: a deleted NOTE with a still-sequential run must not pass'

Write-Host ''
Write-Host 'AND THE WORK MUST BE THE SAME -- a child rediscovers the same manifest' -ForegroundColor Cyan
foreach ($s in $SECTIONS) {
  $now = Table-Counts $s
  Check "$s matches the sequential index" ($now -eq $seqCounts[$s]) "seq[$($seqCounts[$s])] par[$now]"
}

# ------------------------------------------------- C. flag propagation, by contrast --
Write-Host ''
Write-Host 'FLAG PROPAGATION -- --resolve-only must reach the children' -ForegroundColor Cyan
# Proved by CONTRAST, which is what makes it non-vacuous: on deleted databases a
# resolve-only run has nothing to resolve and must parse NOTHING, while the very
# same command without the flag indexes every unit. A dropped flag makes the two
# identical -- and identical is exactly what the bug produced.
Remove-Dbs
$ro = Probe-Run 'jobs3-resolveonly' @('--jobs','3','--resolve-only')
Check 'resolve-only run succeeded' ($ro.Exit -eq 0) "exit=$($ro.Exit)"
$roCounts = @($SECTIONS | ForEach-Object { File-Count $_ })
Check 'no section was parsed under --resolve-only' (
  (@($roCounts | Where-Object { $_ -ne 0 }).Count -eq 0)) "files per section: $($roCounts -join ', ') -- non-zero means the child performed a FULL INDEX"

# BOTH FORMS, and this is the one that carries the RED evidence. The bare form
# above passed even on the PRE-FIX engine -- because that engine downgraded the
# run to sequential, and the sequential path always honoured --resolve-only. The
# downgrade MASKED the propagation bug. Under an explicit --config the pre-fix
# engine really did go parallel, and it indexed 250 files per section on a run
# whose whole point was not to parse anything (measured 2026-09-03). So this leg
# is the one that fails when the flag stops travelling, whatever happens to the
# --config default.
Remove-Dbs
$roCfg = Probe-Run 'jobs3-resolveonly-config' @('--jobs','3','--config',$cfgPath,'--resolve-only')
Check 'resolve-only run with explicit --config succeeded' ($roCfg.Exit -eq 0) "exit=$($roCfg.Exit)"
# WHY THIS ONE LEG CANNOT USE THE PROCESS COUNT (measured 2026-09-05, session 70)
# ------------------------------------------------------------------------------
# Every other leg here samples the process table, and must: they run real work
# for ~5 s, so the sampler takes ~17 polls and reliably measures max=4. THIS leg
# is the opposite -- Remove-Dbs has just run and --resolve-only skips the walk,
# so there is nothing to parse and the whole run lasts 235-780 ms. One
# Get-CimInstance call with a CommandLine filter costs about that much on its
# own, so the sampler gets EXACTLY ONE poll, landing at a random instant.
#
# That is a coin flip, and the recorded history is exactly a coin flip: this
# assertion measured 2, 2, 4, 2, 3 (passing) and then 1 and 0 across seven
# batteries, with NO engine change in between. max=0 is the tell -- a run that
# had gone sequential would still show its own parent, so 0 cannot mean
# "sequential", only "not sampled".
#
# The run really is parallel: its stdout is three processes interleaving into
# one pipe, splicing words mid-token, and it ends with the parallel path's own
# summary line. So assert THAT instead. It is deterministic, and it is not the
# weak "the note is gone" test this suite's header warns about -- the summary is
# printed only by the parallel path, which part B pins from the other side by
# requiring --jobs 1 NOT to print it.
Check 'it went parallel (so the flag really had to travel)' (
  $roCfg.Out -match 'parallel build: 3/3 sections OK \(jobs=3\)') `
  "sampled max=$($roCfg.MaxProcs) (NOT asserted on -- see the comment above)"
$roCfgCounts = @($SECTIONS | ForEach-Object { File-Count $_ })
Check 'no section was parsed under --config --resolve-only' (
  (@($roCfgCounts | Where-Object { $_ -ne 0 }).Count -eq 0)) `
  "files per section: $($roCfgCounts -join ', ') -- the pre-fix engine gave $Units, $Units, $Units here"
Check 'the contrast is real: the same run without the flag DOES parse' (
  (@($SECTIONS | Where-Object { $seqCounts[$_] -match 'files=0' }).Count -eq 0)) `
  "without --resolve-only every section indexed $Units files"

# ----------------------------------------------------- D. --config regression --
Write-Host ''
Write-Host 'REGRESSION -- an explicit --config still parallelises' -ForegroundColor Cyan
Remove-Dbs
$cfgRun = Probe-Run 'jobs3-config' @('--jobs','3','--config',$cfgPath)
Check 'explicit --config run succeeded' ($cfgRun.Exit -eq 0) "exit=$($cfgRun.Exit)"
Check 'more than one concurrent engine' ($cfgRun.MaxProcs -gt 1) "max=$($cfgRun.MaxProcs)"
foreach ($s in $SECTIONS) {
  $now = Table-Counts $s
  Check "$s matches the sequential index" ($now -eq $seqCounts[$s]) "seq[$($seqCounts[$s])] cfg[$now]"
}

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
