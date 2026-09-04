<#
  run_marker_metric_scope.ps1 -- a `dl:ok` on a WHOLE-ROUTINE METRIC rule must go
  stale when the metric moves, and must NOT go stale on an unrelated body edit.

  THE DEFECT THIS PINS (T3):
    The marker hash covers ONE LINE -- the routine's declaration -- while these
    seven rules' subject is the entire routine. So a review could not go stale.
    Measured on the pre-fix build, in four commands: allow a 6-exit routine, add
    a seventh Exit inside the body, re-lint -> 0 findings and NO
    review-marker-stale. The review said "6 exits here is fine" and went on
    answering for 7, which is the exact failure a `dl:ok` exists to prevent -- an
    accountable review that has quietly stopped being about the code.

  THE FIX, and why it is shaped this way:
    The hash INPUT becomes `window-hash|metric`. The marker GRAMMAR is untouched
    (`rule@hhhh`), and DRagLint.Lint.ReviewMarker is untouched -- that unit is
    mirrored byte-for-byte into YADF's vendor tree and pinned by
    run_reviewmarker_yadf_mirror.ps1, which must stay green precisely because
    nothing there moved.

    A body-SPAN hash was the other option and is worse: it would flag a renamed
    local, i.e. re-record all 58 markers in this class on any edit. Check 4 is
    the pin for that decision, not decoration.

  THE CONTROLS:
    * check 1 proves the rule is alive in this fixture, so a later silence means
      "suppressed" rather than "never fired";
    * check 4 edits the body WITHOUT moving the metric and requires silence --
      this fails under a body-span hash, and it fails under "switch the rule off"
      only because check 1 is also asserted;
    * check 5 verifies a LINE-scope rule in the same file still behaves exactly
      as before, so the change is scoped to the seven metric rules;
    * check 6 runs the remedy the stale hint printed and requires ONE marker
      afterwards, refreshed in place, and a clean re-lint;
    * check 7 requires `allow` to REFUSE a line with no metric finding, since the
      old behaviour there was to write a hash that could never verify.

  Exit code: 0 on full pass, 1 on any failure.
#>
[CmdletBinding()]
param(
  [string]$Exe     = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = (Join-Path ([IO.Path]::GetTempPath()) ("draglint-metricmarker-" + [Guid]::NewGuid().ToString('N')))
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
  $s = if ($Ok) { 'PASS' } else { 'FAIL' }
  $c = if ($Ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $Name, $Detail) -ForegroundColor $c
  if (-not $Ok) { $script:Failed = $true }
}

Write-Host '== dl:ok on a whole-routine metric: bound to the number ==' -ForegroundColor Cyan
if (-not (Test-Path -LiteralPath $Exe)) { Write-Host "FATAL: engine not found at $Exe" -ForegroundColor Red; exit 1 }
$Exe = (Resolve-Path $Exe).Path
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
$pas     = Join-Path $WorkDir 'uT3Probe.pas'
$errFile = Join-Path $WorkDir 'stderr.txt'

# The probe. Six Exit statements (max 5), plus a self-assignment on its own line
# so a LINE-scope rule can be verified alongside in the same file.
$SIX = @(
  'unit uT3Probe;'
  ''
  'interface'
  ''
  'function Pick(const A: Integer): string;'
  'procedure Nudge(var B: Integer);'
  ''
  'implementation'
  ''
  'function Pick(const A: Integer): string;'
  'begin'
  '  Result:= '''';'
  '  if A = 1 then begin Result:= ''one'';   Exit; end;'
  '  if A = 2 then begin Result:= ''two'';   Exit; end;'
  '  if A = 3 then begin Result:= ''three''; Exit; end;'
  '  if A = 4 then begin Result:= ''four'';  Exit; end;'
  '  if A = 5 then begin Result:= ''five'';  Exit; end;'
  '  if A = 6 then begin Result:= ''six'';   Exit; end;'
  'end;'
  ''
  'procedure Nudge(var B: Integer);'
  'begin'
  '  B:= B;'
  'end;'
  ''
  'end.'
) -join "`r`n"
$HEADER_LINE = 10   # `function Pick(...)` in the implementation section
$SELFASG_LINE = 23  # `B:= B;`

function Write-Probe([string]$Text) { [System.IO.File]::WriteAllText($pas, $Text + "`r`n", [System.Text.Encoding]::ASCII) }
function Lint([string[]]$Extra) {
  $a = @('lint', $pas) + $Extra
  $o = & $Exe @a 2>$errFile
  [pscustomobject]@{ Out = (($o | Out-String) -replace "`r`n", "`n"); Code = $LASTEXITCODE }
}
function Allow([int]$Line, [string]$Rule) {
  $o = & $Exe allow $pas '--fix-line' $Line '--fix-rule' $Rule '--apply' 2>$errFile
  [pscustomobject]@{ Out = (($o | Out-String) -replace "`r`n", "`n"); Code = $LASTEXITCODE }
}
function Markers { @(Get-Content -LiteralPath $pas | Where-Object { $_ -match 'dl:ok' }) }

# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '-- 1. KNOWN-FIRING (without this, every silence below proves nothing)' -ForegroundColor Cyan
Write-Probe $SIX
$r = Lint @('--rule','too-many-exit-points')
Write-Host ("  " + (($r.Out -split "`n" | Where-Object { $_ -match 'too-many-exit' }) -join "`n  ")) -ForegroundColor DarkGray
Check 'the rule fires on the 6-exit routine' ($r.Out -match 'too-many-exit-points') ''
Check 'and it anchors on the header line' ($r.Out -match ":$HEADER_LINE`:") "expected line $HEADER_LINE"
Check 'and the message quotes the metric' ($r.Out -match 'has 6 Exit statements') ''

# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '-- 2. the writer and the checker agree on the NEW hash input' -ForegroundColor Cyan
$a = Allow $HEADER_LINE 'too-many-exit-points'
Check 'allow --apply succeeds' ($a.Code -eq 0) ("exit=$($a.Code) " + $a.Out.Trim())
$m = Markers
Check 'exactly one dl:ok marker was written' ($m.Count -eq 1) ("markers: " + ($m -join ' | '))
$r = Lint @('--rule','too-many-exit-points')
Check 'and the finding is now suppressed' ($r.Out -match '0 finding') ($r.Out.Trim())

# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '-- 3. THE FIX: the metric grows, the declaration does not' -ForegroundColor Cyan
$grown = ([System.IO.File]::ReadAllText($pas)).Replace(
  "  if A = 6 then begin Result:= 'six';   Exit; end;",
  "  if A = 6 then begin Result:= 'six';   Exit; end;`r`n  if A = 7 then begin Result:= 'seven'; Exit; end;")
[System.IO.File]::WriteAllText($pas, $grown, [System.Text.Encoding]::ASCII)
$r = Lint @()
Write-Host ("  " + (($r.Out -split "`n" | Where-Object { $_ -match '\[' }) -join "`n  ")) -ForegroundColor DarkGray
Check 'the finding is reported again' ($r.Out -match 'too-many-exit-points: Routine has 7') ''
Check 'AND the marker is reported stale' ($r.Out -match 'review-marker-stale') ''
Check 'the stale message names the LIVE metric (7)' ($r.Out -match 'now measures 7') ''
Check 'and prints the exact re-record command' ($r.Out -match "allow --fix-line $HEADER_LINE --fix-rule too-many-exit-points") ''

# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '-- 4. DESIGN PIN: a body edit that does NOT move the metric stays silent' -ForegroundColor Cyan
# Back to six exits, then change the body in two ways that a body-span hash would
# catch and a metric-bound hash must not: a renamed literal and an added comment.
$reverted = $SIX.Replace("'three'", "'THREE'").Replace("  Result:= '';", "  // an added comment`r`n  Result:= '';")
Write-Probe $reverted
$a = Allow $HEADER_LINE 'too-many-exit-points'   # re-record against the edited text
Check 'the routine can be allowed again' ($a.Code -eq 0) ("exit=$($a.Code)")
# Now a FURTHER body edit with the metric untouched.
$tweaked = ([System.IO.File]::ReadAllText($pas)).Replace("'five'", "'FIVE'")
[System.IO.File]::WriteAllText($pas, $tweaked, [System.Text.Encoding]::ASCII)
$r = Lint @('--rule','too-many-exit-points')
Check 'still suppressed -- a metric-bound hash ignores body churn' `
  ($r.Out -notmatch 'too-many-exit-points: Routine has') ($r.Out.Trim())
Check 'and no stale hint was emitted' ($r.Out -notmatch 'review-marker-stale') ''

# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '-- 5. NEIGHBOUR: a LINE-scope rule in the same file is untouched' -ForegroundColor Cyan
$r = Lint @('--rule','self-assignment')
Check 'self-assignment fires before its marker' ($r.Out -match 'self-assignment') ($r.Out.Trim())
$selfLine = 0
$idx = 0
foreach ($ln in (Get-Content -LiteralPath $pas)) { $idx++; if ($ln -match '^\s*B:=\s*B;') { $selfLine = $idx; break } }
Check 'the self-assignment line was located' ($selfLine -gt 0) "line=$selfLine"
if ($selfLine -gt 0) {
  $a = Allow $selfLine 'self-assignment'
  Check 'allow works on a line-scope rule' ($a.Code -eq 0) ("exit=$($a.Code) " + $a.Out.Trim())
  $r = Lint @('--rule','self-assignment')
  Check 'and it is suppressed, exactly as before this change' `
    ($r.Out -notmatch "self-assignment: 'X := X'") ($r.Out.Trim())
}

# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '-- 6. ROUND TRIP: the printed remedy refreshes the marker in place' -ForegroundColor Cyan
$grown2 = ([System.IO.File]::ReadAllText($pas)).Replace(
  "  if A = 6 then begin Result:= 'six';   Exit; end;",
  "  if A = 6 then begin Result:= 'six';   Exit; end;`r`n  if A = 7 then begin Result:= 'seven'; Exit; end;")
[System.IO.File]::WriteAllText($pas, $grown2, [System.Text.Encoding]::ASCII)
$r = Lint @('--rule','too-many-exit-points')
$stale = @($r.Out -split "`n" | Where-Object { $_ -match 'review-marker-stale' }) | Select-Object -First 1
Check 'the grown routine is stale again' ($null -ne $stale) ($r.Out.Trim())
$remedyLine = 0
if ($null -ne $stale -and $stale -match 'allow --fix-line (\d+)') { $remedyLine = [int]$Matches[1] }
Check 'the hint names a line to re-record on' ($remedyLine -gt 0) "line=$remedyLine"
if ($remedyLine -gt 0) {
  $a = Allow $remedyLine 'too-many-exit-points'
  Check 'the printed remedy succeeds verbatim' ($a.Code -eq 0) ("exit=$($a.Code) " + $a.Out.Trim())
  $m = @(Markers | Where-Object { $_ -match 'too-many-exit-points' })
  Check 'the marker was REFRESHED, not duplicated' `
    ($m.Count -eq 1 -and (([regex]::Matches($m[0], 'too-many-exit-points@')).Count -eq 1)) `
    ("markers: " + ($m -join ' | '))
  $r = Lint @('--rule','too-many-exit-points')
  Check 'and the re-lint is clean' `
    ($r.Out -notmatch 'too-many-exit-points: Routine has' -and $r.Out -notmatch 'review-marker-stale') ($r.Out.Trim())
}

# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '-- 7. allow REFUSES a line with no metric finding' -ForegroundColor Cyan
# Old behaviour wrote a hash there that could never verify -- a marker that reads
# as a human review and suppresses nothing.
$bodyLine = 0; $idx = 0
foreach ($ln in (Get-Content -LiteralPath $pas)) { $idx++; if ($ln -match "if A = 3 then") { $bodyLine = $idx; break } }
Check 'a non-header body line was located' ($bodyLine -gt 0) "line=$bodyLine"
if ($bodyLine -gt 0) {
  $a = Allow $bodyLine 'too-many-exit-points'
  Check 'it exits 2 rather than writing an unverifiable marker' ($a.Code -eq 2) ("exit=$($a.Code)")
  Check 'and says why' ($a.Out -match 'whole-routine metric rule') ($a.Out.Trim())
  $m = @(Markers | Where-Object { $_ -match 'too-many-exit-points' })
  Check 'CONTROL: nothing was written -- still one marker' ($m.Count -eq 1) ("markers: " + ($m -join ' | '))
}

Remove-Item -LiteralPath $WorkDir -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ''
if ($script:Failed) { Write-Host 'FAIL' -ForegroundColor Red; exit 1 } else { Write-Host 'PASS' -ForegroundColor Green; exit 0 }
