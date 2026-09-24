<#
  run_scratch_dirs_are_per_run.ps1 -- static guard: no runner uses a FIXED
  drag-lint scratch path under a temp root. Defect D23 (2026-09-24 follow-ups).

  Why this exists
  ---------------
  Test runners picked their scratch folder by a fixed name --
  C:\TEMP\draglint_<x>, Join-Path C:\TEMP 'draglint_<x>',
  "$env:TEMP\drag-lint-<x>" -- and most of them wipe it recursively at start.
  That is safe for ONE run and destroys a sibling's fixtures when the same
  suite runs twice at once: two worktrees, two sessions, or a battery beside a
  hand-run suite. Measured 2026-09-24: two copies of
  tests\callresolve\run_unit_qualified_call_bind.ps1 started 1.5 s apart ->
  the first died with "sql returned no JSON" because the second had deleted
  and re-created draglint_unitqual_bind under it.

  run_battery_jobs_guard.ps1 already asks "do two DIFFERENT runners share a
  name"; it cannot see ONE runner racing itself, because a runner always
  shares its fixed name with its own second copy. The only fix for that is a
  name unique per run, and the idiom is a -$PID / _$PID suffix: $PID is unique
  per `pwsh -File` process (the battery spawns one per runner), needs no
  helper, and keeps the folder greppable.

  What it flags
  -------------
  In every tests\**\run_*.ps1, a CODE line (not a # comment, not inside a
  block comment) that names a draglint_* / drag-lint-* path directly under a
  temp root (C:\TEMP, $env:TEMP, $env:TMP), in either spelling:
    * a literal path   C:\TEMP\draglint_x   "$env:TEMP\drag-lint-x"
    * a Join-Path      Join-Path C:\TEMP 'draglint_x'
    * a built name     Join-Path C:\TEMP ('draglint_x_' + $name)  -- one
      folder per fixture is still the SAME folder on every run
  unless the same line carries a per-run component ($PID, a GUID,
  GetRandomFileName, Get-Random). A line that is unique per run by
  construction is skipped, so the guard cannot nag about the safe idiom.

  There is deliberately NO allow-list. A runner owned by another change that
  still holds a fixed path makes this RED until that runner is fixed.

  Scratch paths NOT named draglint/drag-lint (e.g. $env:TEMP\dlflush,
  refactor_rename.sqlite) are outside this guard's pattern; they are a known
  remainder, not a clearance.

  Positive control: a planted runner in this guard's own per-run scratch
  folder carries one line of each flagged shape and one line of each safe
  shape; the scan must flag exactly the former.

  Usage: pwsh -File tests\autotest\run_scratch_dirs_are_per_run.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$script:fail = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  $tag = if ($Ok) { 'PASS' } else { 'FAIL' }
  Write-Host ("[{0}] {1}{2}" -f $tag, $Name, $(if ($Detail) { "  ($Detail)" } else { '' }))
  if (-not $Ok) { $script:fail = $true }
}

# A temp root, then a draglint_* / drag-lint-* name. The name part stops at
# anything that is not a plain path character, so "..._$PID" leaves a match
# whose line is then exempted by the per-run test below.
$tempRoot  = '(?:C:\\TEMP|\$env:TEMP|\$env:TMP)'
$nameStart = '(?:draglint|drag-lint)[_-]'
$literalRe = $tempRoot + '\\' + $nameStart
# The optional '(' admits a name BUILT per fixture -- Join-Path C:\TEMP
# ('draglint_x_' + $name) -- which is still the same folder on every run.
$joinRe    = 'Join-Path\s+' + $tempRoot + '\s+\(?\s*[''"]' + $nameStart
# A to-the-second timestamp (run_battery.ps1's own draglint_battery_<stamp>)
# also counts as per run; a date alone would not.
$perRunRe  = '\$PID\b|\$\{PID\}|Guid|GetRandomFileName|Get-Random|Get-Date -Format ''[^'']*HHmmss'

<#
  Returns 'file:line: text' for every flagged line of every run_*.ps1 under
  pRoot. Comment handling is the same shape as run_battery_jobs_guard.ps1:
  a text scan that cannot tell prose from code reports the comment above a
  fix as the defect it describes.
#>
function Find-FixedScratch([string]$pRoot) {
  $hits = @()
  foreach ($f in @(Get-ChildItem -LiteralPath $pRoot -Recurse -File -Filter 'run_*.ps1')) {
    $inBlock = $false
    $n = 0
    foreach ($line in (Get-Content -LiteralPath $f.FullName)) {
      $n++
      if ($inBlock) { if ($line -match '#>') { $inBlock = $false }; continue }
      if ($line -match '^\s*<#') { if ($line -notmatch '#>') { $inBlock = $true }; continue }
      if ($line -match '^\s*#') { continue }
      if ($line -notmatch $literalRe -and $line -notmatch $joinRe) { continue }
      if ($line -match $perRunRe) { continue }
      $hits += ('{0}:{1}: {2}' -f $f.FullName.Substring($pRoot.Length).TrimStart('\'), $n, $line.Trim())
    }
  }
  return ,$hits
}

$testsRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$work = Join-Path $env:TEMP "drag-lint-scratch-guard-$PID"
try {
  Write-Host 'POSITIVE CONTROL -- planted fixed paths are flagged, safe ones are not' -ForegroundColor Cyan
  New-Item -ItemType Directory -Path $work -Force | Out-Null
  # Built by concatenation so this guard's own source never holds a flagged
  # line (it scans itself as part of tests\).
  $ct = 'C:\TEMP\' + 'draglint_'
  $et = '$env:TEMP\' + 'drag-lint-'
  $bad = @(
    ('[string]$WorkDir = "' + $ct + 'planted_literal"'),
    ('$w = ''' + $ct + 'planted_single'''),
    ('$s = Join-Path C:\TEMP ''' + 'draglint_' + 'planted_join'''),
    ('[string]$WorkDir = "' + $et + 'planted-env"'),
    ('$w = "' + '$env:TEMP\' + 'draglint_' + 'planted_underscore"'),
    ('$w = Join-Path $env:TEMP ''' + 'drag-lint-' + 'planted-envjoin'''),
    ('$d = Join-Path C:\TEMP (''' + 'draglint_' + 'planted_built_'' + $name)')
  )
  $good = @(
    ('[string]$WorkDir = "' + $ct + 'planted_ok_$PID"'),
    ('[string]$WorkDir = "' + $et + 'planted-ok-$PID"'),
    ('$s = Join-Path C:\TEMP "' + 'draglint_' + 'planted_ok_$PID"'),
    ('$s = Join-Path C:\TEMP ([guid]::NewGuid().ToString())'),
    ('$d = Join-Path C:\TEMP (''' + 'draglint_' + 'planted_built_'' + $name + "_$PID")'),
    ('$d = Join-Path $env:TEMP (''' + 'draglint_' + 'planted_stamp_'' + (Get-Date -Format ''yyyyMMdd-HHmmss''))'),
    ('# $w = "' + $ct + 'planted_in_comment"'),
    '<#',
    ('  ' + $ct + 'planted_in_block'),
    '#>'
  )
  $plant = Join-Path $work 'run_planted_fixture.ps1'
  [IO.File]::WriteAllText($plant, ((@($bad) + @($good)) -join "`r`n") + "`r`n", [Text.Encoding]::ASCII)
  $ctl = Find-FixedScratch $work
  $flaggedLines = @($ctl | ForEach-Object { [int](($_ -split ':')[1]) })
  $expected = 1..$bad.Count
  Check 'every planted fixed shape is flagged' (@($expected | Where-Object { $flaggedLines -notcontains $_ }).Count -eq 0) `
    ("flagged lines: " + ($flaggedLines -join ','))
  Check 'no planted safe shape is flagged' ($flaggedLines.Count -eq $bad.Count) `
    ("flagged $($flaggedLines.Count), expected $($bad.Count)")

  Write-Host ''
  Write-Host 'No runner uses a fixed drag-lint scratch path' -ForegroundColor Cyan
  $runners = @(Get-ChildItem -LiteralPath $testsRoot -Recurse -File -Filter 'run_*.ps1')
  Check 'the runner scan found runners at all (vacuity)' ($runners.Count -gt 0) "runners: $($runners.Count)"
  $found = Find-FixedScratch $testsRoot
  foreach ($h in $found) { Write-Host "  fixed: $h" -ForegroundColor Yellow }
  $files = @($found | ForEach-Object { ($_ -split ':')[0] } | Select-Object -Unique)
  Check 'no run_*.ps1 names a fixed draglint/drag-lint scratch path' ($found.Count -eq 0) `
    "$($found.Count) line(s) in $($files.Count) file(s)"
} finally {
  if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
}

if ($script:fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
