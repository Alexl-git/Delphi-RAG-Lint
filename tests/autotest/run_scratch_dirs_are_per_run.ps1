<#
  run_scratch_dirs_are_per_run.ps1 -- static guard: no runner uses a FIXED
  scratch path under a temp root. Defect D23 (2026-09-24 follow-ups).

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
  block comment, not inside a here-string body) that names ANY path directly
  under a temp root (C:\TEMP, $env:TEMP, $env:TMP), in either spelling:
    * a literal path   C:\TEMP\draglint_x   "$env:TEMP\dlflush"
    * a Join-Path      Join-Path C:\TEMP 'draglint_x'
                       Join-Path $env:TEMP "refactor_rename.sqlite"
    * a built name     Join-Path C:\TEMP ('draglint_x_' + $name)
                       Join-Path $env:TEMP ("lintstore_" + $case.Name)  -- one
      folder per fixture is still the SAME folder on every run
  unless the same line carries a per-run component ($PID, a GUID,
  GetRandomFileName, Get-Random). A line that is unique per run by
  construction is skipped, so the guard cannot nag about the safe idiom.

  What it does NOT flag, and why: a temp path that is embedded TEXT rather
  than a PowerShell path value. Two shapes, both structural:
    * the body of a VERBATIM here-string (the lines after one ending @', up
      to the line starting '@) -- e.g. Delphi fixture source written to disk.
      A @' body never expands, so nothing in it is a path the runner uses.
      An EXPANDING @" body is still scanned: "$env:TEMP\x" in it becomes a
      real path in whatever the runner generates;
    * a literal quoted INSIDE another string, e.g.
      LineOf "S := 'C:\Temp\x.txt';" -- the inner quote is a character of the
      outer string, so the path is data the runner searches for, not a
      location it writes to (tests\reviewmarker\run_allow_refuses_codeless_line.ps1).

  There is deliberately NO allow-list. A runner owned by another change that
  still holds a fixed path makes this RED until that runner is fixed.

  History: until 2026-09-28 the guard matched only draglint_* / drag-lint-*
  names, and every other fixed name ($env:TEMP\dlflush, refactor_rename.sqlite,
  lintstore_<case>.sqlite, ...) was a known remainder -- 16 runners, 24 lines.
  Those runners were made per-run on 2026-09-28 (D23 remainder, BACKLOG-TRIAGE
  TH-2) and the pattern widened to any name, so there is no remainder.

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

# A temp root, then ANY name (the first character of one is enough). A per-run
# component anywhere on the line exempts it via the per-run test below.
$tempRoot  = '(?:C:\\TEMP|\$env:TEMP|\$env:TMP)'
$nameStart = '[A-Za-z0-9_]'
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
<#
  True when the literal temp path starting at pAt sits in a quote NESTED inside
  another string -- "S := 'C:\TEMP\x';" -- which makes it a character run of
  the outer string (text the runner searches for), not a path value. Walks the
  prefix tracking PowerShell's quote state: inside "..." a backtick escapes the
  next character and ' is literal; inside '...' only ' matters ('' toggles
  twice, so it needs no special case).
#>
function Test-NestedLiteral([string]$pLine, [int]$pAt) {
  $st = ''
  for ($i = 0; $i -lt $pAt; $i++) {
    $c = $pLine[$i]
    if ($st -eq '"') {
      if ($c -eq [char]96) { $i++; continue }
      if ($c -eq '"') { $st = '' }
    } elseif ($st -eq "'") {
      if ($c -eq "'") { $st = '' }
    } elseif ($c -eq '"' -or $c -eq "'") {
      $st = [string]$c
    }
  }
  if ($pAt -eq 0) { return $false }
  $prev = [string]$pLine[$pAt - 1]
  return (($st -eq '"' -and $prev -eq "'") -or ($st -eq "'" -and $prev -eq '"'))
}

function Find-FixedScratch([string]$pRoot) {
  $hits = @()
  foreach ($f in @(Get-ChildItem -LiteralPath $pRoot -Recurse -File -Filter 'run_*.ps1')) {
    $inBlock = $false
    $inVerbatim = $false
    $n = 0
    foreach ($line in (Get-Content -LiteralPath $f.FullName)) {
      $n++
      if ($inVerbatim) { if ($line -match "^'@") { $inVerbatim = $false }; continue }
      if ($inBlock) { if ($line -match '#>') { $inBlock = $false }; continue }
      if ($line -match '^\s*<#') { if ($line -notmatch '#>') { $inBlock = $true }; continue }
      if ($line -match '^\s*#') { continue }
      # A verbatim here-string opens at the END of its line; the opener line
      # itself is still code and is scanned below.
      if ($line -match "@'\s*$") { $inVerbatim = $true }
      $isJoin = $line -match $joinRe
      $isLiteral = $false
      foreach ($m in [regex]::Matches($line, $literalRe, 'IgnoreCase')) {
        if (-not (Test-NestedLiteral $line $m.Index)) { $isLiteral = $true; break }
      }
      if (-not $isLiteral -and -not $isJoin) { continue }
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
  $cr = 'C:\TEMP\'
  $er = '$env:TEMP\'
  $jp = 'Join-Path'
  $bad = @(
    ('[string]$WorkDir = "' + $ct + 'planted_literal"'),
    ('$w = ''' + $ct + 'planted_single'''),
    ('$s = Join-Path C:\TEMP ''' + 'draglint_' + 'planted_join'''),
    ('[string]$WorkDir = "' + $et + 'planted-env"'),
    ('$w = "' + '$env:TEMP\' + 'draglint_' + 'planted_underscore"'),
    ('$w = Join-Path $env:TEMP ''' + 'drag-lint-' + 'planted-envjoin'''),
    ('$d = Join-Path C:\TEMP (''' + 'draglint_' + 'planted_built_'' + $name)'),
    # Any name, not only draglint_* (the pre-2026-09-28 remainder shapes).
    ('[string]$WorkDir = "' + $er + 'plantedflush"'),
    ('$db = ' + $jp + ' $env:TEMP "' + 'planted_plain.sqlite"'),
    ('$db = ' + $jp + ' $env:TEMP ("' + 'lintstore_" + $case.Name + ".sqlite")'),
    ('$sb = "' + $er + 'planted_text"; Remove-Item $sb -Recurse'),
    # Mid-string but NOT nested in another quote: still a path value.
    ('& $exe index $dir "--db=' + $cr + 'planted_mid.sqlite"')
  )
  $good = @(
    ('[string]$WorkDir = "' + $ct + 'planted_ok_$PID"'),
    ('[string]$WorkDir = "' + $et + 'planted-ok-$PID"'),
    ('$s = Join-Path C:\TEMP "' + 'draglint_' + 'planted_ok_$PID"'),
    ('$s = Join-Path C:\TEMP ([guid]::NewGuid().ToString())'),
    ('$d = Join-Path C:\TEMP (''' + 'draglint_' + 'planted_built_'' + $name + "_$PID")'),
    ('$d = Join-Path $env:TEMP (''' + 'draglint_' + 'planted_stamp_'' + (Get-Date -Format ''yyyyMMdd-HHmmss''))'),
    ('$db = ' + $jp + ' $env:TEMP ("' + 'lintstore_" + $case.Name + "_$PID.sqlite")'),
    ('# $w = "' + $ct + 'planted_in_comment"'),
    '<#',
    ('  ' + $ct + 'planted_in_block'),
    '#>',
    # Embedded TEXT: a literal nested inside another string, and a verbatim
    # here-string body (run_allow_refuses_codeless_line.ps1's two shapes).
    ('$codeLine = LineOf "S := ''' + $cr + 'x.txt'';"'),
    ('$body = @' + "'"),
    ('  S := ''' + $cr + 'x.txt'';'),
    ("'" + '@')
  )
  # The verbatim here-string must CLOSE: a fixed path after it is code again.
  $after = @(
    ('$w2 = "' + $er + 'planted_after_heredoc"')
  )
  $plant = Join-Path $work 'run_planted_fixture.ps1'
  [IO.File]::WriteAllText($plant, ((@($bad) + @($good) + @($after)) -join "`r`n") + "`r`n", [Text.Encoding]::ASCII)
  $ctl = Find-FixedScratch $work
  $flaggedLines = @($ctl | ForEach-Object { [int](($_ -split ':')[1]) })
  $firstAfter = $bad.Count + $good.Count + 1
  $expected = @(1..$bad.Count) + @($firstAfter..($firstAfter + $after.Count - 1))
  Check 'every planted fixed shape is flagged' (@($expected | Where-Object { $flaggedLines -notcontains $_ }).Count -eq 0) `
    ("flagged lines: " + ($flaggedLines -join ',') + "; expected: " + ($expected -join ','))
  Check 'no planted safe shape is flagged' ($flaggedLines.Count -eq $expected.Count) `
    ("flagged $($flaggedLines.Count), expected $($expected.Count)")

  Write-Host ''
  Write-Host 'No runner uses a fixed scratch path under a temp root' -ForegroundColor Cyan
  $runners = @(Get-ChildItem -LiteralPath $testsRoot -Recurse -File -Filter 'run_*.ps1')
  Check 'the runner scan found runners at all (vacuity)' ($runners.Count -gt 0) "runners: $($runners.Count)"
  $found = Find-FixedScratch $testsRoot
  foreach ($h in $found) { Write-Host "  fixed: $h" -ForegroundColor Yellow }
  $files = @($found | ForEach-Object { ($_ -split ':')[0] } | Select-Object -Unique)
  Check 'no run_*.ps1 names a fixed scratch path under a temp root' ($found.Count -eq 0) `
    "$($found.Count) line(s) in $($files.Count) file(s)"
} finally {
  if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
}

if ($script:fail) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green; exit 0
