<#
  run_marker_malformed_advises_every_form.ps1 -- the one message whose whole job
  is to teach `dl:ok` syntax must enumerate EVERY form the parser accepts, and
  each form it advertises must actually work.

  THE DEFECT (docs\INBOX-malformed-marker-message-omits-the-colon-form.md)
  -----------------------------------------------------------------------
  `645f70c` made `dl:ok <rule-id>: <reason>` a first-class accepted form --
  TReviewMarkers.SplitReason splits on the first `:` as well as on ` -- `. The
  advice text in `review-marker-malformed` was never updated, so it enumerated
  three of the four accepted forms:

    Write `dl:ok <rule-id>` , `dl:ok <rule-id>@<hash>` or
    `dl:ok <rule-id> -- <reason>`, or run `drag-lint allow` to format it.

  Nothing MISFIRED -- everything it recommended was correct. The cost is that
  the omitted form is the one people write by hand (DataCopy used it on all 11
  of its sites), so the message that exists to teach the syntax told its reader
  the form they had just used was unavailable.

  WHY THE TWO HALVES NEVER MET, which is why nothing caught this
  --------------------------------------------------------------
  This text fires on an UNKNOWN RULE ID. The colon form parses the rule id
  correctly, so a well-formed colon marker never reaches this message and a
  malformed one never demonstrates the colon form. No test asserted this
  message's TEXT at all.

  HOW THIS SUITE IS DRIFT-PROOF, not just fixed
  ---------------------------------------------
  Asserting "the message contains the colon form" would pass forever against a
  hand-edited string and would say nothing about whether the string is TRUE.
  So this suite closes the loop in both directions:

    * every form the message advertises is EXERCISED here against the real
      engine -- a form that stops working fails this suite;
    * the advertised set must equal the exercised set EXACTLY -- adding a fifth
      form to the message without proving it here is a FAILURE, and so is the
      original defect (an accepted form missing from the message shows up as an
      exercised form that is not advertised).

  POSITIVE CONTROLS -- this suite must be incapable of passing vacuously
  ---------------------------------------------------------------------
  The obvious vacuity is a fixture where `concat-in-loop` never fires at all:
  every "is suppressed" check would pass with the rule switched off. So the
  fixture keeps TWO statements that must still be reported -- one carrying the
  malformed marker (a marker that suppresses nothing must suppress nothing) and
  one carrying no marker at all -- and the surviving count is asserted exactly.

  `review-marker-malformed` is reachable ONLY from `lint-all`; the `lint` verb
  calls FinalizeAndOutput without AScannedFiles. See
  docs\INBOX-lint-verb-cannot-report-unused-markers.md.

  Run from a NEUTRAL CWD (C:\TEMP), pwsh 7.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-marker-malformed-forms"
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

$fixture = Join-Path $WorkDir 'MarkerForms.pas'
$db      = Join-Path $WorkDir 'MarkerForms.sqlite'

# One real rule id on every marker but the malformed one. concat-in-loop is on
# by default and anchors on the statement's first line, and every statement here
# is single-line, so the marker and the anchor coincide (the WRAPPED case is
# run_marker_span.ps1's subject, not this one).
$body = @'
unit MarkerForms;

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
    S := S + IntToStr(I); // dl:ok concat-in-loop
  end;
  for I := 0 to 3 do
  begin
    S := S + Trim(S); // dl:ok concat-in-loop -- reviewed, the loop is bounded
  end;
  for I := 0 to 3 do
  begin
    S := S + UpperCase(S); // dl:ok concat-in-loop: reviewed, the loop is bounded
  end;
  for I := 0 to 3 do
  begin
    S := S + LowerCase(S); // dl:ok because reasons
  end;
  for I := 0 to 3 do
  begin
    S := S + IntToHex(I, 2);
  end;
  Writeln(S);
end;

end.
'@
function Write-Ascii([string]$Path, [string]$Text) {
  $norm = $Text -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllText($Path, $norm, [System.Text.Encoding]::ASCII)
}
Write-Ascii $fixture $body

$lines = [System.IO.File]::ReadAllLines($fixture)
function LineOf([string]$Needle) {
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i].Trim() -eq $Needle) { return $i + 1 } }
  return -1
}
$lnBare    = LineOf 'S := S + IntToStr(I); // dl:ok concat-in-loop'
$lnDash    = LineOf 'S := S + Trim(S); // dl:ok concat-in-loop -- reviewed, the loop is bounded'
$lnColon   = LineOf 'S := S + UpperCase(S); // dl:ok concat-in-loop: reviewed, the loop is bounded'
$lnBogus   = LineOf 'S := S + LowerCase(S); // dl:ok because reasons'
$lnUnmarked= LineOf 'S := S + IntToHex(I, 2);'
Check 'all five fixture lines located' (
  @($lnBare,$lnDash,$lnColon,$lnBogus,$lnUnmarked) -notcontains -1) `
  "bare $lnBare, dash $lnDash, colon $lnColon, bogus $lnBogus, unmarked $lnUnmarked"

& $Exe index $WorkDir --db $db 2>&1 | Out-Null
Check 'fixture indexed' (Test-Path $db)

function Lint-Fixture {
  $concat = @(); $stale = @{}; $malformed = @{}
  foreach ($line in (& $Exe lint-all --db $db 2>&1)) {
    $t = "$line"
    if ($t -match ':(\d+):\d+\s+\[\w+\]\s+concat-in-loop:')           { $concat += [int]$Matches[1] }
    elseif ($t -match ':(\d+):\d+\s+\[\w+\]\s+review-marker-stale:')  { $stale[[int]$Matches[1]] = $t }
    elseif ($t -match ':(\d+):\d+\s+\[\w+\]\s+review-marker-malformed:') { $malformed[[int]$Matches[1]] = $t }
  }
  return [pscustomobject]@{
    Concat    = @($concat | Sort-Object -Unique)
    Stale     = $stale
    Malformed = $malformed
  }
}
$r = Lint-Fixture
Write-Host ("  concat-in-loop fired on: {0}" -f ($r.Concat -join ', ')) -ForegroundColor DarkGray

Write-Host ''
Write-Host 'POSITIVE CONTROL -- the rule is live and the marker matcher is bounded' -ForegroundColor Cyan
# Without these, every 'is suppressed' check below passes with concat-in-loop off.
Check "unmarked statement (line $lnUnmarked) STILL fires" ($r.Concat -contains $lnUnmarked)
Check "the malformed marker suppresses NOTHING (line $lnBogus still fires)" ($r.Concat -contains $lnBogus)
Check 'exactly two findings survive' ($r.Concat.Count -eq 2) "got: $($r.Concat -join ', ')"
Check "review-marker-malformed fired on line $lnBogus" ($r.Malformed.ContainsKey($lnBogus))
Check 'review-marker-malformed fired on that line ONLY' ($r.Malformed.Count -eq 1) `
  "lines: $($r.Malformed.Keys -join ', ')"

$msg = if ($r.Malformed.ContainsKey($lnBogus)) { $r.Malformed[$lnBogus] } else { '' }

Write-Host ''
Write-Host 'THE ADVERTISED FORMS -- each one must be accepted by the parser' -ForegroundColor Cyan
Check "the bare form (line $lnBare) is suppressed"                (-not ($r.Concat -contains $lnBare))
Check "the -- reason form (line $lnDash) is suppressed"           (-not ($r.Concat -contains $lnDash))
Check "the COLON reason form (line $lnColon) is suppressed"       (-not ($r.Concat -contains $lnColon)) `
  'the form the message used to omit'

# The @hash form, proved the way an operator reaches it: a hash-less marker is
# honoured but reports the hash to re-mark with, so harvest that hash and use it.
# This also pins that adding @hash to the comment does not itself move the hash
# -- if it did, the advice would send the reader in a circle.
$want = ''
if ($r.Stale.ContainsKey($lnBare) -and ($r.Stale[$lnBare] -match 're-mark it as concat-in-loop@([0-9a-f]{4})')) {
  $want = $Matches[1]
}
Check 'a hash-less marker reports the hash to re-mark with' ($want -ne '') $r.Stale[$lnBare]
if ($want -ne '') {
  # Replace the whole line, so this does not depend on the here-string's line endings.
  Write-Ascii $fixture ($body.Replace(
    'S := S + IntToStr(I); // dl:ok concat-in-loop',
    "S := S + IntToStr(I); // dl:ok concat-in-loop@$want"))
  & $Exe index $WorkDir --db $db 2>&1 | Out-Null
  $r2 = Lint-Fixture
  Check "the @hash form (line $lnBare, @$want) is suppressed" (-not ($r2.Concat -contains $lnBare))
  Check "and is VERIFIED -- no review-marker-stale on line $lnBare" (-not $r2.Stale.ContainsKey($lnBare))
  Check 'the two controls still fire after the re-mark' (
    ($r2.Concat -contains $lnUnmarked) -and ($r2.Concat -contains $lnBogus)) "got: $($r2.Concat -join ', ')"
}

Write-Host ''
Write-Host 'THE DRIFT GATE -- advertised set must EQUAL the exercised set' -ForegroundColor Cyan
# Every backticked token in the message that starts with `dl:ok` is a form the
# message tells the reader to write. `drag-lint allow` is backticked too and is
# a command, not a form, so the dl:ok prefix is the filter.
$advertised = @()
foreach ($m in [regex]::Matches($msg, '`(dl:ok[^`]*)`')) {
  $advertised += ($m.Groups[1].Value -replace '\s+', ' ').Trim()
}
$advertised = @($advertised | Sort-Object -Unique)
$exercised  = @(@(
  'dl:ok <rule-id>',
  'dl:ok <rule-id> -- <reason>',
  'dl:ok <rule-id>: <reason>',
  'dl:ok <rule-id>@<hash>'
) | Sort-Object)
Write-Host ("  advertised: {0}" -f ($advertised -join ' | ')) -ForegroundColor DarkGray

$missing = @($exercised | Where-Object { $advertised -notcontains $_ })
$extra   = @($advertised | Where-Object { $exercised  -notcontains $_ })
Check 'every accepted form is advertised' ($missing.Count -eq 0) `
  "not advertised: $($missing -join ' | ') -- add it to the format string in DRagLint.CLI.pas"
Check 'every advertised form is proved here' ($extra.Count -eq 0) `
  "advertised but not exercised: $($extra -join ' | ') -- add a fixture leg above, do not delete this check"

Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'PASS' -ForegroundColor Green
exit 0
