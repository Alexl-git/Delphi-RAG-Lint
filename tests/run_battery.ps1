<#
  run_battery.ps1 -- THE battery. Runs EVERY runner under tests\, not a subset.

  Why this exists
  ---------------
  "Full battery" was folklore for the whole of Auto-Document Phase 3: six tasks
  in a row reported green against tests\autodoc (45) + tests\autotest (67) = 112
  runners, while tests\ actually held 180. The other 68 had never been run by any
  task in the phase, and one of them (autofix\run_missing_doc_fix.ps1) had been
  red since Task 3 changed the emitter. An unstated definition silently became
  the definition. This script IS the definition, and it prints its own
  denominator before running anything so a shrinking battery is visible instead
  of silent.

  What a runner is
  ----------------
  A runner is a file named run_*.ps1 anywhere under tests\ (RECURSIVE -- a
  non-recursive scan misses tests\lint-project's 4 runners, which live one level
  down in per-case subdirectories; that is how "68" and "64" could both look
  right). Enumeration is dynamic. There is deliberately no hardcoded list: a
  literal list is exactly what drifted for six tasks.

  Exclusions
  ----------
  Only the -Exclude patterns below, each with a stated reason. Non-runner .ps1
  helpers (tests\autotest\_manifest_common.ps1, tests\preprocess\lib\oracle.ps1,
  tests\lint-store\enclosing-attribution\verify.ps1,
  tests\textindex\fts5_spike.ps1, tests\textindex\schema_v10.ps1) are not
  excluded -- they are simply not named run_*.ps1, so they never enter the set.

  Usage
  -----
    pwsh -File tests\run_battery.ps1                       # everything (default)
    pwsh -File tests\run_battery.ps1 -Include autodoc,autotest
    pwsh -File tests\run_battery.ps1 -Include callresolve -TimeoutSec 300
    pwsh -File tests\run_battery.ps1 -List                 # enumerate only
    pwsh -File tests\run_battery.ps1 -LogDir C:\TEMP\battery

  -Include / -Exclude match against the repo-relative path with forward slashes
  (e.g. 'tests/autodoc/run_doc_p3_marker.ps1'), so a bare suite name like
  'autodoc' selects the whole suite and a runner name selects one runner.

  Exit code: 0 only when every runner in the enumerated set passed.
#>
[CmdletBinding()]
param(
  # Substring/wildcard filters kept from the enumerated set. Default: everything.
  [string[]]$Include = @(),

  # Substring/wildcard filters removed from the enumerated set. Every entry here
  # MUST carry a reason in the table below -- an undocumented exclusion is the
  # bug this script exists to kill.
  [string[]]$Exclude = @(),

  # Per-runner wall-clock budget. 180 s is the value the 2026-07-27 sweep used.
  [int]$TimeoutSec = 180,

  # Enumerate and print the set, run nothing.
  [switch]$List,

  # Where per-runner transcripts go. Default: a timestamped dir under $env:TEMP.
  [string]$LogDir = ''
)

$ErrorActionPreference = 'Continue'

# ---------------------------------------------------------------------------
# Documented default exclusions. Format: pattern = one-line reason.
# KEEP THIS AS SHORT AS POSSIBLE. Anything added here is a hole in the battery,
# so a reason that is not "this is not a test" needs a second opinion.
# ---------------------------------------------------------------------------
$DefaultExclusions = [ordered]@{
  'tests/run_battery.ps1' = 'this driver itself -- it is named run_*.ps1 and would recurse into itself forever'
}

$repoRoot  = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$testsRoot = (Resolve-Path $PSScriptRoot).Path

function RelPath([string]$full) {
  $full.Substring($repoRoot.Length + 1).Replace('\', '/')
}

function MatchesAny([string]$rel, [string[]]$pats) {
  foreach ($p in $pats) {
    if ([string]::IsNullOrWhiteSpace($p)) { continue }
    $g = $(if ($p -match '[\*\?]') { $p } else { "*$p*" })
    if ($rel -like $g) { return $true }
  }
  return $false
}

# --- Enumerate (dynamic, recursive, run_*.ps1 only) ------------------------
$allRunners = Get-ChildItem -LiteralPath $testsRoot -Recurse -Filter 'run_*.ps1' -File |
              Sort-Object FullName
$totalFound = $allRunners.Count

$excludePats = @($DefaultExclusions.Keys) + $Exclude
$excluded    = @($allRunners | Where-Object { MatchesAny (RelPath $_.FullName) $excludePats })
$kept        = @($allRunners | Where-Object { -not (MatchesAny (RelPath $_.FullName) $excludePats) })
if ($Include.Count -gt 0) {
  $kept = @($kept | Where-Object { MatchesAny (RelPath $_.FullName) $Include })
}

# --- Print the denominator BEFORE running anything -------------------------
Write-Host ''
Write-Host '=== drag-lint battery ===' -ForegroundColor Cyan
Write-Host ("  runners found under tests\ (run_*.ps1, recursive) : {0}" -f $totalFound)
Write-Host ("  excluded by policy                               : {0}" -f $excluded.Count)
foreach ($k in $DefaultExclusions.Keys) {
  Write-Host ("      {0}  -- {1}" -f $k, $DefaultExclusions[$k]) -ForegroundColor DarkGray
}
foreach ($k in $Exclude) {
  Write-Host ("      {0}  -- (caller-supplied -Exclude)" -f $k) -ForegroundColor DarkGray
}
if ($Include.Count -gt 0) {
  Write-Host ("  -Include filter                                  : {0}" -f ($Include -join ', ')) -ForegroundColor Yellow
  Write-Host ("  SUBSET RUN -- this is NOT the full battery." ) -ForegroundColor Yellow
}
Write-Host ("  runners to execute                               : {0}" -f $kept.Count) -ForegroundColor Cyan
Write-Host ("  per-runner timeout                               : {0}s" -f $TimeoutSec)

# Per-suite breakdown, so a suite vanishing is visible.
$bySuite = $kept | Group-Object { (RelPath $_.FullName).Split('/')[1] } | Sort-Object Name
Write-Host '  by suite:'
foreach ($g in $bySuite) { Write-Host ("      {0,-16} {1}" -f $g.Name, $g.Count) }
Write-Host ''

if ($List) {
  foreach ($r in $kept) { Write-Host (RelPath $r.FullName) }
  exit 0
}

if ($LogDir -eq '') {
  $LogDir = Join-Path $env:TEMP ('draglint_battery_' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
}
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
Write-Host ("  logs: {0}" -f $LogDir)
Write-Host ''

# --- Run ------------------------------------------------------------------
$results = New-Object System.Collections.Generic.List[object]
$i = 0
$sw = [System.Diagnostics.Stopwatch]::StartNew()

foreach ($r in $kept) {
  $i++
  $rel = RelPath $r.FullName
  $logFile = Join-Path $LogDir (($rel -replace '[\\/]', '__') + '.log')
  Write-Host ("[{0,3}/{1}] {2} ... " -f $i, $kept.Count, $rel) -NoNewline

  $rsw = [System.Diagnostics.Stopwatch]::StartNew()
  # Each runner gets its own pwsh process so a crash/exit cannot take the
  # battery with it, and its CWD is the repo root (the sweep's convention).
  $proc = Start-Process -FilePath 'pwsh' `
            -ArgumentList @('-NoProfile', '-NonInteractive', '-File', $r.FullName) `
            -WorkingDirectory $repoRoot -PassThru `
            -RedirectStandardOutput $logFile -RedirectStandardError ($logFile + '.err') `
            -WindowStyle Hidden

  $state = ''
  if ($proc.WaitForExit($TimeoutSec * 1000)) {
    $code  = $proc.ExitCode
    $state = $(if ($code -eq 0) { 'PASS' } else { 'FAIL' })
  } else {
    $state = 'TIMEOUT'
    $code  = $null
    # Kill the whole tree -- runners spawn drag-lint.exe children, and an
    # orphaned one holds a .sqlite lock that fails the NEXT runner too.
    try { $proc.Kill($true) } catch { }
  }
  $rsw.Stop()

  $colour = @{ PASS = 'Green'; FAIL = 'Red'; TIMEOUT = 'Magenta' }[$state]
  Write-Host ("{0} ({1:N1}s)" -f $state, $rsw.Elapsed.TotalSeconds) -ForegroundColor $colour

  $results.Add([pscustomobject]@{
    Runner = $rel; State = $state; ExitCode = $code
    Seconds = [math]::Round($rsw.Elapsed.TotalSeconds, 1); Log = $logFile
  })
}
$sw.Stop()

# --- Report ---------------------------------------------------------------
$pass    = @($results | Where-Object State -eq 'PASS').Count
$fail    = @($results | Where-Object State -eq 'FAIL')
$timeout = @($results | Where-Object State -eq 'TIMEOUT')

Write-Host ''
Write-Host '=== battery summary ===' -ForegroundColor Cyan
Write-Host ("  {0} pass / {1} fail / {2} timeout out of {3} executed  (of {4} found)" -f `
            $pass, $fail.Count, $timeout.Count, $results.Count, $totalFound)
Write-Host ("  wall clock: {0:N1} min" -f $sw.Elapsed.TotalMinutes)

if ($fail.Count -gt 0) {
  Write-Host ''
  Write-Host '  FAIL:' -ForegroundColor Red
  foreach ($f in $fail) { Write-Host ("    {0}  (exit {1})" -f $f.Runner, $f.ExitCode) -ForegroundColor Red }
}
if ($timeout.Count -gt 0) {
  Write-Host ''
  Write-Host ("  TIMEOUT (> {0}s):" -f $TimeoutSec) -ForegroundColor Magenta
  foreach ($t in $timeout) { Write-Host ("    {0}" -f $t.Runner) -ForegroundColor Magenta }
}

$csv = Join-Path $LogDir 'results.csv'
$results | Export-Csv -NoTypeInformation -Encoding utf8 -Path $csv
Write-Host ''
Write-Host ("  results: {0}" -f $csv)
Write-Host ''

exit $(if ($fail.Count -eq 0 -and $timeout.Count -eq 0) { 0 } else { 1 })
