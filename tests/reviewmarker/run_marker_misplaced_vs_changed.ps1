<#
  run_marker_misplaced_vs_changed.ps1 -- `review-marker-stale` must not assert a
  cause it has not established.

  WHY THIS EXISTS

    DataCopy, 2026-09-01: "review-marker-stale fires on files nobody touched --
    the most alarming of the three, because if hashes drift for unchanged text
    then every stale finding everywhere is suspect."

    They were right to be alarmed, and the message is what made it alarming. A
    hash mismatch has at least three causes:

      (a) the reviewed code really did change;
      (b) the marker sits on a line that is NOT the finding's anchor, so it was
          hashed against a different window than the checker computes -- it can
          never verify, however untouched the code is;
      (c) the marker predates a change in HOW markers are hashed (HashLine ->
          HashWindow, and the bare-except anchor move that forced it).

    The message asserted (a) unconditionally: "the line changed since it was
    reviewed". On uFileUtils.pas:2028/2055 -- two byte-identical duplicated
    blocks carrying markers recorded @54b7 -- that was simply false. Measured on
    the shipped build: `allow --fix-line 2028` produces @ab38 and
    `allow --fix-line 2029` produces @1b83, so @54b7 came from neither line under
    the current scheme, i.e. cause (c), reported as cause (a).

    Case (b) IS decidable with information the checker already holds, and this
    test pins that: when the marker's own line differs from the finding's anchor
    AND the marker's hash equals the window hash at the marker's own line, it was
    recorded against the wrong anchor -- provably, not probably.

  WHAT IT DOES NOT CLAIM
    (a) and (c) are NOT separable here, and the message must stop pretending they
    are. The second assertion below is that the non-misplaced message offers both
    readings rather than asserting one.

  POSITIVE CONTROL
    A genuinely edited line must still produce the changed/stale report --
    otherwise "no false alarm" could be achieved by never reporting anything.
#>
[CmdletBinding()]
param(
  [string]$Exe = "$PSScriptRoot\..\..\third_party\dll-win64\drag-lint.exe",
  [string]$WorkDir = "$env:TEMP\drag-lint-marker-misplaced"
)
$ErrorActionPreference = 'Stop'
$script:Failed = $false
function Check($n, $ok, $d = '') {
  $s = if ($ok) { 'PASS' } else { 'FAIL' }
  $c = if ($ok) { 'Green' } else { 'Red' }
  Write-Host ("  [{0}] {1} {2}" -f $s, $n, $d) -ForegroundColor $c
  if (-not $ok) { $script:Failed = $true }
}

if (-not (Test-Path $Exe)) { Write-Host "FATAL: engine not found: $Exe" -ForegroundColor Red; exit 2 }
if (Test-Path $WorkDir) { Get-ChildItem -LiteralPath $WorkDir -File | Remove-Item -Force }
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null

# A WRAPPED concat-in-loop: the rule anchors on the first line, a trailing
# comment can also live on the second. That is the whole shape of the defect.
$src = @(
  'unit Wrapped;'
  ''
  'interface'
  ''
  'implementation'
  ''
  'uses'
  '  System.SysUtils;'
  ''
  'procedure Accumulate;'
  'var'
  '  S: string;'
  '  I: Integer;'
  'begin'
  '  S := '''';'
  '  for I := 0 to 10 do'
  '    S := S +'
  '         IntToStr(I);'
  '  Writeln(S);'
  'end;'
  ''
  'end.'
)
$anchor = 17   # 'S := S +'      -- where concat-in-loop reports
$tail   = 18   # 'IntToStr(I);'  -- the span's last line

function Write-Fixture($path, $lines) {
  [IO.File]::WriteAllLines($path, [string[]]$lines, (New-Object Text.ASCIIEncoding))
}
function Lint($path) {
  (& $Exe lint $path --enable concat-in-loop 2>&1 | Out-String)
}

# ---------------------------------------------------------------------------
Write-Host 'SETUP -- the rule anchors where we think it does' -ForegroundColor Cyan
$f = Join-Path $WorkDir 'Wrapped.pas'
Write-Fixture $f $src
$base = Lint $f
Check "concat-in-loop reports line $anchor" ($base -match ":${anchor}:\d+\s+\[info\] concat-in-loop") `
  (($base -split "`r?`n" | Select-String 'concat-in-loop' | Select-Object -First 1).ToString().Trim())

# ---------------------------------------------------------------------------
Write-Host 'CASE 1 -- a marker on the SPAN TAIL is MISPLACED, not evidence of change' -ForegroundColor Cyan
# allow hashes the window at the line it writes to, so writing at the tail
# produces exactly the shape found in DataCopy: a marker that can never verify.
& $Exe allow $f --fix-line $tail --fix-rule concat-in-loop --apply *>&1 | Out-Null
$tailLine = ([IO.File]::ReadAllLines($f))[$tail - 1]
Check 'the marker landed on the span tail' ($tailLine -match 'dl:ok concat-in-loop@') $tailLine.Trim()

$out1 = Lint $f
$stale1 = ($out1 -split "`r?`n" | Select-String 'review-marker-stale' | Select-Object -First 1)
Check 'a stale hint is produced' ([bool]$stale1)
if ($stale1) {
  # The MESSAGE only. Matching the whole output line let the work directory's
  # own name ("drag-lint-marker-misplaced") satisfy an assertion about the
  # wording -- a vacuous pass, caught by the RED check and fixed here.
  $msg = ($stale1.ToString() -split 'review-marker-stale:', 2)[-1]
  Check 'it does NOT assert the code changed' `
    ($msg -notmatch 'the line changed since it was reviewed') $msg.Trim()
  Check 'it names the marker line AND the anchor line' `
    (($msg -match "\b$tail\b") -and ($msg -match "\b$anchor\b")) $msg.Trim()
  Check 'it says the marker is on the wrong anchor' `
    ($msg -match 'anchor|wrong line|misplaced') $msg.Trim()
  Check 'it names the remediation line' `
    ($msg -match "--fix-line\s+$anchor") $msg.Trim()
}

# ---------------------------------------------------------------------------
Write-Host 'CASE 2 -- a marker on the ANCHOR verifies, and stays quiet' -ForegroundColor Cyan
$f2 = Join-Path $WorkDir 'Anchor.pas'
Write-Fixture $f2 $src
& $Exe allow $f2 --fix-line $anchor --fix-rule concat-in-loop --apply *>&1 | Out-Null
$out2 = Lint $f2
Check 'the finding is suppressed' ($out2 -notmatch '\[info\] concat-in-loop')
Check 'and no stale hint is raised' ($out2 -notmatch 'review-marker-stale')

# ---------------------------------------------------------------------------
Write-Host 'POSITIVE CONTROL -- a REAL edit still reports stale' -ForegroundColor Cyan
# Same file, edited INSIDE the hashed window but NOT on the concat itself --
# editing the concat changes its shape so the rule stops firing, and then there
# is no finding to report stale about (that mistake made this control vacuous
# on the first run). If this stops
# reporting, the fix has bought quiet by going blind.
$edited = [IO.File]::ReadAllLines($f2)
# A RENAME, and the reasoning behind that is worth keeping -- three earlier
# attempts at this control were all vacuous:
#   * editing line 19, then line 18, changed NO hash. HashWindow only widens
#     past one line when the anchor normalizes to a LONE KEYWORD (the
#     bare-except case); for an ordinary statement it is HashLine of that single
#     line, so only line 17 can matter.
#   * replacing line 17 outright deleted the marker, leaving nothing to be stale.
#   * `S := S + '' +` kept the marker but changed the shape enough that
#     concat-in-loop stopped firing -- no finding, so no stale check runs.
# Renaming the accumulator changes the anchor line's text while preserving both
# the marker and the rule's shape, which is exactly what "the code changed" means.
$edited = $edited | ForEach-Object { $_ -replace '\bS\b', 'Acc' }
[IO.File]::WriteAllLines($f2, [string[]]$edited, (New-Object Text.ASCIIEncoding))
$out3 = Lint $f2
$stale3 = ($out3 -split "`r?`n" | Select-String 'review-marker-stale' | Select-Object -First 1)
Check 'an edited line still reports stale' ([bool]$stale3)
if ($stale3) {
  # Message only, for the same reason as CASE 1: the work directory is called
  # "drag-lint-marker-misplaced", so matching the whole line tests the PATH.
  $msg3 = ($stale3.ToString() -split 'review-marker-stale:', 2)[-1]
  Check 'and that message is NOT the misplaced one' `
    ($msg3 -notmatch 'anchor|misplaced') $msg3.Trim()
}

# ---------------------------------------------------------------------------
if ($script:Failed) { Write-Host 'RESULT: FAIL' -ForegroundColor Red; exit 1 }
Write-Host 'RESULT: PASS' -ForegroundColor Green
exit 0
