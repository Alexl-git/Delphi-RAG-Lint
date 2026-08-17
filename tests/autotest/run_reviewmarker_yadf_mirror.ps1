<#
  run_reviewmarker_yadf_mirror.ps1 -- YADF's vendored copy of the review-marker
  unit must stay byte-identical to this repo's.

  INBOX-yadf-share-review-marker-hash. drag-lint writes `dl:ok ...@<hash>` markers
  into YADF's own source -- 147 of them as of 2026-08-17 -- so YADF already
  consumes this hash without owning the function. The owner asked for the function
  so YADF can VERIFY a marker and warn when it goes stale. (Never refresh it: a
  correct normalisation-invariant hash only moves when the code's MEANING changed,
  which is exactly when a review must be invalidated.)

  Of the note's two options -- shared search path vs vendored copy -- the vendored
  copy was taken, because a cross-repo unit-path dependency puts drag-lint's source
  tree inside YADF's build. The cost of that choice is DRIFT, and this suite is the
  thing that pays it: the mirror carries no local header at all, precisely so the
  check can be a hash comparison rather than a fuzzy diff.

  WHY THIS IS A SKIP AND NOT A FAILURE when the mirror is absent: YADF is a
  separate repo that need not exist on every machine. A skip is a fail-open, and
  this repo has been bitten by fail-open checks before, so the skip is LOUD, names
  the exact path it looked for, and is paired with a positive control on the side
  that is always present -- if drag-lint's own copy ever goes missing or empty,
  that is a FAILURE here, not a skip.

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param([string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe")

$ErrorActionPreference = 'Stop'; $fail = $false
function Check($n,$ok,$detail=''){ Write-Host ("[{0}] {1}{2}" -f (@('FAIL','PASS')[[int]$ok]),$n,$(if($detail){" -- $detail"}else{''})) -ForegroundColor (@('Red','Green')[[int]$ok]); if(-not $ok){$script:fail=$true} }

$src    = Join-Path $PSScriptRoot '..\..\src\lint\DRagLint.Lint.ReviewMarker.pas'
$mirror = 'C:\Projects\YADF\vendor\drag-lint\DRagLint.Lint.ReviewMarker.pas'

# POSITIVE CONTROL: the source side is always present, so its absence is a real
# failure. Without this, a rename in src\lint would turn this suite into a
# permanent silent skip.
Check 'source unit exists' (Test-Path $src) $src
if (Test-Path $src) {
  Check 'source unit is non-trivial (not an empty/stub file)' ((Get-Item $src).Length -gt 10000) "$((Get-Item $src).Length) bytes"
}

if (-not (Test-Path $mirror)) {
  Write-Host "[SKIP] YADF mirror not present on this machine -- looked for: $mirror" -ForegroundColor Yellow
  Write-Host '       (YADF is a separate repo; nothing to compare. This is NOT a pass of the drift check.)' -ForegroundColor Yellow
} elseif (Test-Path $src) {
  $hSrc = (Get-FileHash $src    -Algorithm SHA256).Hash
  $hMir = (Get-FileHash $mirror -Algorithm SHA256).Hash
  Check 'YADF mirror is byte-identical to src\lint\DRagLint.Lint.ReviewMarker.pas' `
        ($hSrc -eq $hMir) `
        "src=$($hSrc.Substring(0,12)) mirror=$($hMir.Substring(0,12)) -- re-copy the file; do not hand-merge"

  # The two members YADF must actually call. A mirror that dropped HashWindow
  # would still be 'a copy of something' -- and a YADF checker built on HashLine
  # alone disagrees with drag-lint on exactly the lone-keyword anchors
  # HashWindow was added for, which reads as a batch of stale reviews.
  $txt = Get-Content $mirror -Raw
  Check 'mirror exports HashWindow'              ($txt -match 'class function HashWindow')
  Check 'mirror exports NormalizedIsLoneKeyword' ($txt -match 'NormalizedIsLoneKeyword')
  Check 'mirror stayed pure (SysUtils + Hash only)' `
        ($txt -match '(?s)interface\s*uses\s*System\.SysUtils,\s*System\.Hash;')
}

if($fail){ Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
