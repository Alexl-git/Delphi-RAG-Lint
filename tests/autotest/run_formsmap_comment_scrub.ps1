# Guard: forms-csv must not read COMMENTED-OUT source as code.
#
# INBOX-remaining-raw-text-scans-read-comments-as-code, instance #1 (FormsMap).
#
# THE PATH THIS ACTUALLY EXERCISES -- read before editing the fixture.
#
# The primary launch edges come from the AST-exact `refs` index, which never
# sees a comment, so a commented-out `TfrmX.Create` cannot invent a form edge.
# The reachable harm is one step later, in CaptionForHandler step (3)
# (DRagLint.FormsMap.pas:583): when no control is bound directly to the
# launching routine, it TEXT-SCANS the form's own .pas for callers of that
# routine and takes the FIRST match. A commented-out call therefore wins the
# caption, and a real navigation edge is labelled with the wrong button.
#
# So the fixture launches frmRealS from OpenReal -- a public method no control
# is bound to -- and gives OpenReal three apparent callers, in file order:
#   btnBraceClick   { OpenReal; }        two-line brace comment
#   btnGhostClick   // OpenReal;   and   (* OpenReal; *)
#   btnRealClick    OpenReal;            <- the only real one, deliberately last
#
# Unscrubbed, the caption comes out 'Brace'. Scrubbed, it comes out 'Real'.
#
# WHY THE POSITIVE CONTROL IS THE POINT OF THIS FILE
#
# "the caption is not 'Brace'" is also satisfied by a scrub so aggressive it
# eats the real call too -- the edge would then fall back to '(via OpenReal)'.
# The REAL-CAPTION arm asserts the edge is captioned 'Real', which fails in
# both directions: too little scrubbing and too much.
#
# The no-trailing-newline pass re-runs every arm against a copy whose last line
# has no EOL, because that is exactly where a re-split of the scrubbed text and
# TFile.ReadAllLines disagree on the element count. A shift there moves the
# real call into the handler above it and the caption silently becomes 'Ghost'.
#
# Usage: pwsh -File tests/autotest/run_formsmap_comment_scrub.ps1 [-Exe <path>]
[CmdletBinding()]
param(
    [string] $Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
    [string] $FixtureDir = "$PSScriptRoot\..\fixtures\formsmap-scrub",
    [string] $WorkDir = "$env:TEMP\drag-lint-formsmap-scrub-$PID"
)
try {
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail='') {
    $status = if ($Ok) {'PASS'} else {'FAIL'}
    $color  = if ($Ok) {'Green'} else {'Red'}
    Write-Host ("  [{0}] {1} {2}" -f $status, $Name, $Detail) -ForegroundColor $color
    if (-not $Ok) { $script:Failed = $true }
}
if (-not (Test-Path $Exe)) { Write-Host "FATAL: exe not found: $Exe" -ForegroundColor Red; exit 2 }
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null

# Runs index + forms-csv over a project directory and returns the CSV text.
function Get-FormsCsv([string]$ProjDir, [string]$Tag) {
    $db  = "$WorkDir\$Tag.sqlite"
    $out = "$WorkDir\$Tag.csv"
    & $Exe index $ProjDir --db $db 2>&1 | Out-Null
    Check "$Tag`: index exits 0" ($LASTEXITCODE -eq 0)
    & $Exe forms-csv --project "$ProjDir\Scrub.dproj" --db $db --out $out 2>&1 | Out-Null
    Check "$Tag`: forms-csv exits 0" ($LASTEXITCODE -eq 0)
    Check "$Tag`: csv exists" (Test-Path $out)
    if (-not (Test-Path $out)) { return '' }
    return (Get-Content $out -Raw)
}

# Asserts every arm against one CSV. Called once per line-ending variant so a
# regression cannot hide in whichever variant was not checked.
function Assert-Arms([string]$Csv, [string]$Tag) {
    # POSITIVE CONTROL -- the real caller still wins the caption. Fails if the
    # scrub is too aggressive (edge degrades to '(via OpenReal)') just as surely
    # as it fails if a decoy wins.
    # v6 (algorithm 6): the index pass resolves this edge first, through
    # call_edges, which never see comments; the text scan this file was written
    # for is now the fallback and only runs for a From -> To pair the index
    # cannot explain. The arms below still pin the observable answer.
    Check "$Tag`: REAL-CAPTION control -- edge captioned 'Real'" `
        ($Csv -match '(?m)^\d+,"frmRealS","uScrubReal","Real","Real","TButton","TfrmRootS\.btnRealClick",')

    # THE DEFECT -- a brace comment must not caption the edge.
    Check "$Tag`: brace-comment caller ignored" (-not ($Csv -match "'Brace'"))

    # THE DEFECT -- line and star-paren comments must not caption the edge.
    # This is also the arm that catches an off-by-one in the re-split: a shift
    # moves the real call into btnGhostClick, directly above it.
    Check "$Tag`: line/star-paren comment caller ignored" (-not ($Csv -match "'Ghost'"))

    # The edge must not have degraded to the no-caption fallback.
    Check "$Tag`: caption did not fall back to '(via OpenReal)'" `
        (-not ($Csv -match '\(via OpenReal\)'))

    Check "$Tag`: root form present as the main form" ($Csv -match '(?m)^\d+,"frmRootS","uScrubMain","Main form \(opens at startup\)",')
    Check "$Tag`: no form reported unresolved" (-not ($Csv -match '"unresolved"'))
}

# --- Pass 1: fixture as checked in (file ends with a newline) ---------------
Write-Host 'Pass 1: uScrubMain.pas WITH a trailing newline'
$csv1 = Get-FormsCsv $FixtureDir 'trail'
Assert-Arms $csv1 'trail'

# (v6 dropped the PAS-lines column, so the line-count check that lived here has
# nothing left to measure.)

# --- Pass 2: same fixture, last line has NO end-of-line --------------------
Write-Host 'Pass 2: uScrubMain.pas WITHOUT a trailing newline'
$NoTrailDir = "$WorkDir\notrail"
Copy-Item $FixtureDir $NoTrailDir -Recurse
$mainPath = "$NoTrailDir\uScrubMain.pas"
$text = [System.IO.File]::ReadAllText($mainPath)
$text = $text.TrimEnd("`r", "`n")
[System.IO.File]::WriteAllText($mainPath, $text, [System.Text.Encoding]::ASCII)
Check 'notrail: fixture copy really has no trailing EOL' `
    (-not ([System.IO.File]::ReadAllText($mainPath)).EndsWith("`n"))
$csv2 = Get-FormsCsv $NoTrailDir 'notrail'
Assert-Arms $csv2 'notrail'

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
} finally {
  # D23: this run's scratch is $PID-suffixed; remove it so per-run folders do not pile up in TEMP.
  foreach ($d23 in @("$env:TEMP\drag-lint-formsmap-scrub-$PID")) { if (Test-Path -LiteralPath $d23) { Remove-Item -LiteralPath $d23 -Recurse -Force -ErrorAction SilentlyContinue } }
}
