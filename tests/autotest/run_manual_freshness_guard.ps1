<#
.SYNOPSIS
  Fails when docs\drag-lint-manual.docx / .pdf are older than the wiki they are
  built from.

.DESCRIPTION
  Session 27, item 7. The manual is generated from docs\wiki\*.md by
  tools\build-manual.ps1. Generated output that is not checked goes stale
  silently -- which is the entire reason CLAUDE.md's docs-in-sync rule exists,
  and the reason four shipping verbs sat undocumented for months.

  The owner flagged this risk when the manual was proposed: "this becomes another
  thing to update". Correct, so it is not left to memory.

  TOLERANCE, and why it is not zero. A fresh `git clone` stamps every working
  file with checkout time, in no guaranteed order, so a strict "manual must be
  newer than every .md" test would fail at random on a clean clone -- and a guard
  that fails for reasons unrelated to the thing it guards is one that gets
  disabled. The manual is therefore allowed to be up to $ToleranceMinutes older
  than the newest page. Real drift is measured in hours or days, not minutes, so
  this loses nothing that matters.

  ABSENT vs STALE -- this changed 2026-08-18 and the reason matters.

  Originally a MISSING manual was a FAIL, because the artifact was TRACKED and
  absence meant someone had deleted a deliverable. The owner then ruled it should
  not be tracked: it is ~1.5 MB of binary per regeneration, and this guard demands
  a regeneration on every wiki edit, so tracking it added that much to history
  each time. It now ships on the GitHub release and is gitignored.

  Once an artifact is built on demand, "absent" is the NORMAL state of a fresh
  clone -- and a guard that fails on the normal state gets disabled, which would
  cost the staleness check too. So absence is now a SKIP, stated out loud.

  What is NOT weakened: a manual that EXISTS and is older than the wiki still
  FAILS. That was always the real defect this guards -- a document that looks
  current and is not. Absence at least cannot mislead anyone.
#>
[CmdletBinding()]
param(
  [string]$Repo = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))),
  [int]$ToleranceMinutes = 5
)

$ErrorActionPreference = 'Stop'
$script:Failed = $false

function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  $status = if ($Ok) { 'PASS' } else { 'FAIL' }
  $color  = if ($Ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $status, $Name, $Detail) -ForegroundColor $color
  if (-not $Ok) { $script:Failed = $true }
}

$Repo = (Resolve-Path $Repo).Path
Write-Host '== generated manual vs the wiki it is built from ==' -ForegroundColor Cyan

$wikiDir = Join-Path $Repo 'docs\wiki'
$docx    = Join-Path $Repo 'docs\drag-lint-manual.docx'
$pdf     = Join-Path $Repo 'docs\drag-lint-manual.pdf'
$builder = Join-Path $Repo 'tools\build-manual.ps1'

Check 'builder script present' (Test-Path -LiteralPath $builder) 'tools\build-manual.ps1'
Check 'wiki directory present' (Test-Path -LiteralPath $wikiDir) $wikiDir
if (-not (Test-Path -LiteralPath $wikiDir)) {
  Write-Host 'MANUAL FRESHNESS GUARD: FAIL' -ForegroundColor Red; exit 1
}

$pages = @(Get-ChildItem -LiteralPath $wikiDir -Filter *.md -File)
Check 'wiki pages located' ($pages.Count -gt 0) "$($pages.Count) page(s)"
if ($pages.Count -eq 0) { Write-Host 'MANUAL FRESHNESS GUARD: FAIL' -ForegroundColor Red; exit 1 }

$newest     = $pages | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
$newestTime = $newest.LastWriteTimeUtc

Write-Host ("  [INFO] newest wiki page: {0} ({1:yyyy-MM-dd HH:mm:ss} UTC)" -f $newest.Name, $newestTime) -ForegroundColor DarkGray

$anyPresent = $false
foreach ($artifact in @($docx, $pdf)) {
  $name = [System.IO.Path]::GetFileName($artifact)
  if (-not (Test-Path -LiteralPath $artifact)) {
    { } | Out-Null
    Write-Host ("  [SKIP] {0} not built -- generate with: pwsh -File tools\build-manual.ps1" -f $name) -ForegroundColor DarkGray
    continue
  }
  $anyPresent = $true
  Check "$name exists" $true ''
  $t   = (Get-Item -LiteralPath $artifact).LastWriteTimeUtc
  $lag = ($newestTime - $t).TotalMinutes
  $ok  = $lag -le $ToleranceMinutes
  $detail = if ($ok) {
    ("built {0:yyyy-MM-dd HH:mm} UTC" -f $t)
  } else {
    ("STALE by {0:N0} minute(s) -- {1} changed after it was built" -f $lag, $newest.Name)
  }
  Check "$name is not older than the wiki" $ok $detail
  if (-not $ok) {
    Write-Host '        ^ the manual no longer reflects the pages it was generated from.' -ForegroundColor Yellow
    Write-Host '          Regenerate it:  pwsh -File tools\build-manual.ps1' -ForegroundColor Yellow
  }
}

if (-not $anyPresent) {
  Write-Host '  [NOTE] no manual on disk -- nothing to check for staleness. This is the' -ForegroundColor DarkGray
  Write-Host '         normal state of a fresh clone: the manual is gitignored and built' -ForegroundColor DarkGray
  Write-Host '         on demand. A manual that EXISTS and is stale still fails.' -ForegroundColor DarkGray
}

# POSITIVE CONTROL. Without it, a bug that left $newestTime unset (or the page
# list empty) would sail through as "nothing is stale" while checking nothing --
# the same fail-open shape that let a scrub run zero times with a green suite.
# It runs whether or not an artifact is present, so the skip path above cannot
# silently disable the whole check.
$ctlFuture = $newestTime.AddYears(10)
$ctlStale  = (($ctlFuture - $newestTime).TotalMinutes -gt $ToleranceMinutes)
Check 'positive control: a page newer than the manual is detected as stale' $ctlStale '+10y probe'

Write-Host ''
if ($script:Failed) { Write-Host 'MANUAL FRESHNESS GUARD: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'MANUAL FRESHNESS GUARD: PASS' -ForegroundColor Green
exit 0
