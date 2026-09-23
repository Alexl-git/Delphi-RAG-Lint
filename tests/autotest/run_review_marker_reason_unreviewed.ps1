<#
  run_review_marker_reason_unreviewed.ps1 -- `review-marker-reason-unreviewed`
  and the `REVIEWED <yyyy-mm-dd>` stamp (owner ruling OWN-7, 2026-09-23).

  WHY (docs\INBOX-new-rules-from-graph-and-converter-facts.md, B2)
  ---------------------------------------------------------------
  The @hash covers CODE only -- NormalizeLine stops at `//` -- so a marker's
  REASON can drift arbitrarily far from the truth without the marker ever going
  stale. A false reason cannot be detected mechanically; one left unexamined
  for months can. The stamp records when a human last re-read the reason
  against the code:

      S := S + T; // dl:ok concat-in-loop@1a2b -- REVIEWED 2026-09-23 bounded

  WHAT THIS PINS
    * OFF by default (it would flood every legacy marker);
    * with --enable: no stamp -> reported; recent stamp -> silent; stamp older
      than the limit -> reported; stamp in the future -> reported;
    * the limit is the rule's threshold (drag-lint-lint.json
      "thresholds": {"review-marker-reason-unreviewed": N});
    * STAMPING DOES NOT MAKE A MARKER STALE: a marker written by `allow`, then
      re-stamped by hand, still suppresses its finding with no stale hint.

  Run from a NEUTRAL CWD, pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-marker-reason-unreviewed"
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
if (-not (Test-Path $WorkDir)) { New-Item -ItemType Directory $WorkDir | Out-Null }
foreach ($stale in @(Get-ChildItem -LiteralPath $WorkDir -File -ErrorAction SilentlyContinue)) {
  [System.IO.File]::Delete($stale.FullName)
}
$fixture = Join-Path $WorkDir 'ReasonUnreviewed.pas'
$cfg     = Join-Path $WorkDir 'drag-lint-lint.json'

$today   = Get-Date
$recent  = $today.AddDays(-10).ToString('yyyy-MM-dd')
$old     = $today.AddDays(-400).ToString('yyyy-MM-dd')
$future  = $today.AddDays(30).ToString('yyyy-MM-dd')

$body = @"
unit ReasonUnreviewed;

interface

procedure P;

implementation

uses
  System.SysUtils;

procedure P;
var
  I: Integer;
  S: string;
begin
  S := '';
  for I := 0 to 3 do
  begin
    S := S + IntToStr(I); // dl:ok concat-in-loop -- bounded, no stamp
  end;
  for I := 0 to 3 do
  begin
    S := S + Trim(S); // dl:ok concat-in-loop -- REVIEWED $recent bounded
  end;
  for I := 0 to 3 do
  begin
    S := S + UpperCase(S); // dl:ok concat-in-loop -- REVIEWED $old bounded
  end;
  for I := 0 to 3 do
  begin
    S := S + LowerCase(S); // dl:ok concat-in-loop -- REVIEWED $future bounded
  end;
  for I := 0 to 3 do
  begin
    S := S + IntToHex(I, 2);
  end;
  Writeln(S);
end;

end.
"@
function Write-Ascii([string]$Path, [string]$Text) {
  $norm = $Text -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}
Write-Ascii $fixture $body

$lines = [System.IO.File]::ReadAllLines($fixture)
function LineOf([string]$Prefix) {
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i].Trim().StartsWith($Prefix)) { return $i + 1 } }
  return -1
}
$lnNone   = LineOf 'S := S + IntToStr(I);'
$lnRecent = LineOf 'S := S + Trim(S);'
$lnOld    = LineOf 'S := S + UpperCase(S);'
$lnFuture = LineOf 'S := S + LowerCase(S);'
$lnHex    = LineOf 'S := S + IntToHex(I, 2);'
Check 'all fixture lines located' (@($lnNone,$lnRecent,$lnOld,$lnFuture,$lnHex) -notcontains -1)

function Lint-It([string[]]$Extra) {
  $r = @{}; $concat = @(); $stale = @{}
  foreach ($line in (& $Exe lint $fixture @Extra 2>&1)) {
    $t = "$line"
    if     ($t -match ':(\d+):\d+\s+\[\w+\]\s+review-marker-reason-unreviewed:') { $r[[int]$Matches[1]] = $t }
    elseif ($t -match ':(\d+):\d+\s+\[\w+\]\s+concat-in-loop:')                  { $concat += [int]$Matches[1] }
    elseif ($t -match ':(\d+):\d+\s+\[\w+\]\s+review-marker-stale:')             { $stale[[int]$Matches[1]] = $t }
  }
  [pscustomobject]@{ R = $r; Concat = $concat; Stale = $stale }
}

Write-Host 'DEFAULT OFF' -ForegroundColor Cyan
$d = Lint-It @()
Check 'no review-marker-reason-unreviewed without opt-in' ($d.R.Count -eq 0) "got $($d.R.Count)"
Check 'POSITIVE CONTROL: the unmarked statement fires' ($d.Concat -contains $lnHex)

Write-Host 'OPTED IN (--enable)' -ForegroundColor Cyan
$e = Lint-It @('--enable', 'review-marker-reason-unreviewed')
Check "no stamp (line $lnNone) is reported" ($e.R.ContainsKey($lnNone))
Check "recent stamp $recent (line $lnRecent) is silent" (-not $e.R.ContainsKey($lnRecent)) "$($e.R[$lnRecent])"
Check "stamp $old, 400 days old (line $lnOld), is reported" ($e.R.ContainsKey($lnOld))
if ($e.R.ContainsKey($lnOld)) { Check '  ...and the message quotes the age and the limit' ($e.R[$lnOld] -match '400' -and $e.R[$lnOld] -match '180') $e.R[$lnOld] }
Check "future stamp $future (line $lnFuture) is reported" ($e.R.ContainsKey($lnFuture))

Write-Host 'THRESHOLD FROM CONFIG' -ForegroundColor Cyan
[System.IO.File]::WriteAllText($cfg, '{ "enabled": ["review-marker-reason-unreviewed"], "thresholds": { "review-marker-reason-unreviewed": 500 } }', [System.Text.Encoding]::ASCII)
$c = Lint-It @('--config', $cfg)
Check "limit 500: the 400-day stamp (line $lnOld) is now silent" (-not $c.R.ContainsKey($lnOld)) "$($c.R[$lnOld])"
Check 'limit 500: the missing stamp is still reported' ($c.R.ContainsKey($lnNone))

Write-Host 'A STAMP EDIT DOES NOT MAKE THE MARKER STALE' -ForegroundColor Cyan
# Replace the hashless marker on $lnHex's statement with a real one written by
# `allow`, confirm it suppresses cleanly, then add a stamp by hand.
& $Exe allow $fixture --fix-line $lnHex --fix-rule concat-in-loop --apply 2>&1 | Out-Null
$lines = [System.IO.File]::ReadAllLines($fixture)
Check '`allow` wrote a hashed marker' ($lines[$lnHex - 1] -match 'dl:ok concat-in-loop@[0-9a-f]{4}') $lines[$lnHex - 1]
$a = Lint-It @()
Check '  ...which suppresses the finding' (-not ($a.Concat -contains $lnHex))
Check '  ...with no stale hint' (-not $a.Stale.ContainsKey($lnHex)) "$($a.Stale[$lnHex])"
$lines[$lnHex - 1] = $lines[$lnHex - 1] + " -- REVIEWED $recent bounded"
[System.IO.File]::WriteAllLines($fixture, $lines, [System.Text.Encoding]::ASCII)
$b = Lint-It @('--enable', 'review-marker-reason-unreviewed')
Check 'after stamping, the finding is STILL suppressed' (-not ($b.Concat -contains $lnHex))
Check '  ...still no stale hint' (-not $b.Stale.ContainsKey($lnHex)) "$($b.Stale[$lnHex])"
Check '  ...and the stamped marker is not reported unreviewed' (-not $b.R.ContainsKey($lnHex)) "$($b.R[$lnHex])"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL: review-marker-reason-unreviewed' -ForegroundColor Red; exit 1 }
Write-Host 'PASS: review-marker-reason-unreviewed' -ForegroundColor Green
exit 0
