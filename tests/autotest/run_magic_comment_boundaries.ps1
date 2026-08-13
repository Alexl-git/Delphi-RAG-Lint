<#
  run_magic_comment_boundaries.ps1 -- `compiler-magic-comments` must match MARKER
  WORDS, not substrings of ordinary words.

  THE BUG (found 2026-08-13 while triaging YADF)
  ----------------------------------------------
  The rule was a bare alternation with no word boundaries:

      (#match? @warn "TODO|FIXME|HACK|XXX|BUG")

  so "BUG" matched inside **DEBUG**. Every comment mentioning `{$IFDEF DEBUG}`,
  `DEBUG_MODE`, or an identifier of the form `BUG_SOMETHING` (test-case names are
  the common case -- YADF has `BUG_DROPPED_INCLUDE_DIRECTIVE`) was reported as an
  untracked work item. The rule is `info`-severity and fires per comment, so this
  was quiet, permanent noise in every project rather than an obvious break.

  The fix is `\b(...)\b`. `_` is a word character, which is what makes the
  boundary do the right thing at both ends: no boundary before BUG in
  DEBUG_MODE, none after it in BUG_DROPPED_INCLUDE.

  WHY THE NEGATIVE CASES ARE THE POINT
  ------------------------------------
  Deleting `BUG` from the alternation would also make the false positives go
  away, and would silence a marker the rule is meant to catch. So case 1 asserts
  a bare `BUG:` marker STILL fires. Same reasoning as the case-dataflow suite:
  the cheap fix and the correct fix are only distinguishable by the assertions
  that demand the rule keep working.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-magic-boundaries"
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
if (Test-Path $WorkDir) { Remove-Item -Recurse -Force $WorkDir }
New-Item -ItemType Directory $WorkDir | Out-Null

# One comment per procedure, so a finding's LINE identifies which comment fired.
# `lint --rule <id>` is not usable here: its validator only knows the built-in
# rules and refuses every external .scm id, this one included -- see
# docs\INBOX-lint-rule-filter-leaks-other-rules.md. So the run is unfiltered and
# the findings are filtered here instead.
$fixture = Join-Path $WorkDir 'MagicBoundaries.pas'
$body = @"
unit MagicBoundaries;

interface

// MUST FIRE: a genuine TODO marker
procedure A;
// MUST FIRE: FIXME: still broken
procedure B;
// MUST FIRE: BUG: this one is a real marker word
procedure C;
// MUST NOT FIRE: DEBUG_MODE is a compile-time flag
procedure D;
// MUST NOT FIRE: BUG_DROPPED_INCLUDE_DIRECTIVE is a test case name
procedure E;
// MUST NOT FIRE: built with DEBUG symbols
procedure F;
// MUST NOT FIRE: nothing of interest on this line
procedure G;

implementation

procedure A; begin end;
procedure B; begin end;
procedure C; begin end;
procedure D; begin end;
procedure E; begin end;
procedure F; begin end;
procedure G; begin end;

end.
"@
$norm = $body -replace "`r`n", "`n" -replace "`n", "`r`n"
[System.IO.File]::WriteAllText($fixture, $norm, [System.Text.Encoding]::ASCII)

# Line numbers of the comments above, derived from the fixture rather than
# hardcoded, so editing the fixture cannot silently decouple them.
$lines = [System.IO.File]::ReadAllLines($fixture)
$must    = @{}
$mustNot = @{}
for ($i = 0; $i -lt $lines.Count; $i++) {
  if ($lines[$i] -match '^// MUST FIRE: (.+)$')     { $must[$i + 1]    = $Matches[1] }
  if ($lines[$i] -match '^// MUST NOT FIRE: (.+)$') { $mustNot[$i + 1] = $Matches[1] }
}
Check 'fixture yields 3 must-fire and 4 must-not-fire comments' (
  ($must.Count -eq 3) -and ($mustNot.Count -eq 4)) "$($must.Count)/$($mustNot.Count)"

$out  = (& $Exe lint $fixture 2>$null)
$fired = @()
foreach ($line in $out) {
  if ("$line" -match ':(\d+):\d+\s+\[\w+\]\s+compiler-magic-comments:') { $fired += [int]$Matches[1] }
}
$fired = @($fired | Sort-Object -Unique)
Write-Host ("  fired on lines: {0}" -f ($fired -join ', ')) -ForegroundColor DarkGray

Write-Host ''
Write-Host 'Marker words MUST still fire' -ForegroundColor Cyan
foreach ($ln in ($must.Keys | Sort-Object)) {
  Check ("line {0} fires -- {1}" -f $ln, $must[$ln]) ($fired -contains $ln)
}

Write-Host ''
Write-Host 'Substrings of ordinary words MUST NOT fire' -ForegroundColor Cyan
foreach ($ln in ($mustNot.Keys | Sort-Object)) {
  Check ("line {0} silent -- {1}" -f $ln, $mustNot[$ln]) (-not ($fired -contains $ln))
}

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
